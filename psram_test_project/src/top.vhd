----------------------------------
-- top.vhd PSRAM test for Tang Nano 9K / GW1NR-9
-- rev 1 - shabaz - oct 2026
-- 
--
-- 27 MHz input clock
-- PLL generates 81 MHz memory clock
-- PSRAM IP generates 40.5 MHz clk_out
--
-- PSRAM configuration:
--   PSRAM Memory Interface HS, 2CH
--   Burst length = 32 (i.e. 32 bytes is eight 32-bit words)
--
-- Operation:
--   1. Wait for PLL and both PSRAM channels to calibrate.
--   2. Write Burst Length 32 (BL32) bursts from 0x000000 to 0x1FFFF0.
--   3. Wait, then read the same address range back.
--   4. All eight words in each BL32 burst contain a different test pattern.
--   5. LED0/LED1 (active-low) latch channel-0/channel-1 errors.
--   6. After verification, continuously perform read bursts and serialize them.
--   7. Serial outputs advance at clk_out/32 = 1.265625 Mbit/s.
--
----------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity TOP is
    port (
        clk     : in  std_logic;       -- 27 MHz
        reset_n : in  std_logic;

        led     : out std_logic_vector(1 downto 0);

        out_ch1 : out std_logic;
        out_ch2 : out std_logic;

        -- PSRAM physical interface
        O_psram_ck      : out   std_logic_vector(1 downto 0);
        O_psram_ck_n    : out   std_logic_vector(1 downto 0);
        IO_psram_rwds   : inout std_logic_vector(1 downto 0);
        O_psram_reset_n : out   std_logic_vector(1 downto 0);
        IO_psram_dq     : inout std_logic_vector(15 downto 0);
        O_psram_cs_n    : out   std_logic_vector(1 downto 0)
    );
end TOP;


architecture RTL of TOP is

    --------------------------------------------------------------------
    -- Constants
    --------------------------------------------------------------------

    -- Burst Length 32 (BL32) advances by 32/2 = 16 address units.
    -- Why 32/2 and not 32/4? Because the PSRAM chip happens to be
    -- physically designed for use that way it seems. 
    constant ADDR_STEP : unsigned(20 downto 0) :=
        to_unsigned(16, 21);

    -- Last valid burst starts at 0x1FFFF0.
    constant LAST_ADDR : unsigned(20 downto 0) :=
        to_unsigned(16#1FFFF0#, 21);

    -- Minimum command-to-command spacing for BL32.
    -- User guide requires >=19 clk_out cycles for BL32.
    -- Use 20 for one cycle of margin.
    constant CMD_INTERVAL : integer := 20;

    constant TURNAROUND_CYCLES : integer := 32;


    --------------------------------------------------------------------
    -- PLL component definition as supplied by the Gowin IP gen tool
    --------------------------------------------------------------------

    component Gowin_rPLL
        port (
            clkout : out std_logic;
            lock   : out std_logic;
            clkin  : in  std_logic
        );
    end component;


    --------------------------------------------------------------------
    -- PSRAM component definition as supplied by the Gowin IP gen tool
    --------------------------------------------------------------------

    component PSRAM_Memory_Interface_HS_Top
        port (
            clk             : in    std_logic;
            rst_n           : in    std_logic;
            memory_clk      : in    std_logic;
            pll_lock        : in    std_logic;

            O_psram_ck      : out   std_logic_vector(1 downto 0);
            O_psram_ck_n    : out   std_logic_vector(1 downto 0);
            IO_psram_rwds   : inout std_logic_vector(1 downto 0);
            O_psram_reset_n : out   std_logic_vector(1 downto 0);
            IO_psram_dq     : inout std_logic_vector(15 downto 0);
            O_psram_cs_n    : out   std_logic_vector(1 downto 0);

            init_calib0     : out std_logic;
            init_calib1     : out std_logic;

            clk_out         : out std_logic;

            cmd0            : in std_logic;
            cmd1            : in std_logic;

            cmd_en0         : in std_logic;
            cmd_en1         : in std_logic;

            addr0           : in std_logic_vector(20 downto 0);
            addr1           : in std_logic_vector(20 downto 0);

            wr_data0        : in std_logic_vector(31 downto 0);
            wr_data1        : in std_logic_vector(31 downto 0);

            rd_data0        : out std_logic_vector(31 downto 0);
            rd_data1        : out std_logic_vector(31 downto 0);

            rd_data_valid0  : out std_logic;
            rd_data_valid1  : out std_logic;

            data_mask0      : in std_logic_vector(3 downto 0);
            data_mask1      : in std_logic_vector(3 downto 0)
        );
    end component;


    --------------------------------------------------------------------
    -- Clocks / initialization
    --------------------------------------------------------------------

    signal memory_clk : std_logic;
    signal pll_lock   : std_logic;
    signal clk_out    : std_logic;

    signal init_calib0 : std_logic;
    signal init_calib1 : std_logic;


    --------------------------------------------------------------------
    -- PSRAM user interface
    --------------------------------------------------------------------

    signal cmd0    : std_logic := '0';
    signal cmd1    : std_logic := '0';

    signal cmd_en0 : std_logic := '0';
    signal cmd_en1 : std_logic := '0';

    signal addr0 : std_logic_vector(20 downto 0) :=
        (others => '0');

    signal addr1 : std_logic_vector(20 downto 0) :=
        (others => '0');

    signal wr_data0 : std_logic_vector(31 downto 0) := (others => '0');

    signal wr_data1 : std_logic_vector(31 downto 0) := (others => '0');

    signal rd_data0 : std_logic_vector(31 downto 0);
    signal rd_data1 : std_logic_vector(31 downto 0);

    signal rd_data_valid0 : std_logic;
    signal rd_data_valid1 : std_logic;

    signal data_mask0 : std_logic_vector(3 downto 0) :=
        (others => '0');

    signal data_mask1 : std_logic_vector(3 downto 0) :=
        (others => '0');


    --------------------------------------------------------------------
    -- Definitions, signals, states and test_pattern function
    -- all used to manage the three phases (write data, read and test,
    -- read and playback [serialized for output]).
    --------------------------------------------------------------------

    -- Exercise all 131,072 consecutive BL32 burst starts:
    --   0x000000, 0x000010, ... 0x1FFFF0.
    constant FIRST_TEST_ADDR : unsigned(20 downto 0) := (others => '0');
    constant LAST_TEST_ADDR  : unsigned(20 downto 0) :=
        to_unsigned(16#1FFFF0#, 21);

    -- All these states are used for operation through the three phases
    -- (write, read+test, read+playback)
    type state_t is (
        WAIT_CALIB,
        WRITE_CMD,
        WRITE_GAP,
        WRITE_TO_READ_WAIT,
        READ_CMD,
        READ_GAP,
        PLAY_READ_CMD,
        PLAY_CAPTURE,
        PLAY_SERIAL
    );

    signal state : state_t := WAIT_CALIB;
    signal current_addr : unsigned(20 downto 0) := (others => '0');
    signal command_age : integer range 0 to CMD_INTERVAL-1 := 0;
    signal turnaround_count : integer range 0 to TURNAROUND_CYCLES-1 := 0;

    signal write_word_index : integer range 0 to 7 := 0;
    signal read_word_count0 : integer range 0 to 8 := 0;
    signal read_word_count1 : integer range 0 to 8 := 0;

    signal error_ch0 : std_logic := '0';
    signal error_ch1 : std_logic := '0';

    signal last_rd_data0 : std_logic_vector(31 downto 0) := (others => '0');
    signal last_rd_data1 : std_logic_vector(31 downto 0) := (others => '0');

    -- Playback buffers: one complete BL32 burst = 8 x 32 = 256 bits.
    signal play_buffer0 : std_logic_vector(255 downto 0) := (others => '0');
    signal play_buffer1 : std_logic_vector(255 downto 0) := (others => '0');
    signal serial_bit_index : integer range 0 to 255 := 0;
    signal serial_prescaler : integer range 0 to 31 := 0;
    signal out_ch1_reg : std_logic := '0';
    signal out_ch2_reg : std_logic := '1';

    -- Address- and word-dependent data.  Each BL32 burst contains eight
    -- different 32-bit words.  Channel 1 is the bitwise complement of
    -- channel 0.
    function test_pattern(
        base_addr  : unsigned(20 downto 0);
        word_index : integer;
        channel    : integer
    ) return std_logic_vector is
        variable v : unsigned(31 downto 0);
        constant PATTERN_SEED : unsigned(31 downto 0) := x"A5C35A7E";
    begin
        v := resize(base_addr, 32) xor PATTERN_SEED;
        v := v xor to_unsigned(word_index * 16#01010101#, 32);
        v := v xor shift_left(resize(base_addr, 32), 7);

        if channel = 0 then
            return std_logic_vector(v);
        else
            return not std_logic_vector(v);
        end if;
    end function;

begin

    --------------------------------------------------------------------
    -- PLL: 27 MHz -> 81 MHz
    --------------------------------------------------------------------

    -- this component instance was copy-pasted from the Gowin IP generator output
    pll_inst : Gowin_rPLL
        port map (
            clkin  => clk,
            clkout => memory_clk,
            lock   => pll_lock
        );

    --------------------------------------------------------------------
    -- PSRAM controller
    --------------------------------------------------------------------

    -- this component instance was copy-pasted from the Gowin IP generator output
    psram_instance : PSRAM_Memory_Interface_HS_Top
        port map (
            clk             => clk,
            rst_n           => reset_n,
            memory_clk      => memory_clk,
            pll_lock        => pll_lock,

            O_psram_ck      => O_psram_ck,
            O_psram_ck_n    => O_psram_ck_n,
            IO_psram_rwds   => IO_psram_rwds,
            O_psram_reset_n => O_psram_reset_n,
            IO_psram_dq     => IO_psram_dq,
            O_psram_cs_n    => O_psram_cs_n,

            init_calib0     => init_calib0,
            init_calib1     => init_calib1,
            clk_out         => clk_out,

            cmd0            => cmd0,
            cmd1            => cmd1,
            cmd_en0         => cmd_en0,
            cmd_en1         => cmd_en1,
            addr0           => addr0,
            addr1           => addr1,
            wr_data0        => wr_data0,
            wr_data1        => wr_data1,
            rd_data0        => rd_data0,
            rd_data1        => rd_data1,
            rd_data_valid0  => rd_data_valid0,
            rd_data_valid1  => rd_data_valid1,
            data_mask0      => data_mask0,
            data_mask1      => data_mask1
        );

    -- wire the two address buses permanently to the current_addr registered output
    addr0 <= std_logic_vector(current_addr);
    addr1 <= std_logic_vector(current_addr);

    -- we don't use data masking, set those signal inputs to the PSRAM component to all zeros
    data_mask0 <= "0000";
    data_mask1 <= "0000";

    -- wr_data0/wr_data1 are registered below.  This deliberately mirrors
    -- Gowin's reference transaction style: word 0 is presented with cmd_en,
    -- then words 1..7 are presented on the following seven clk_out cycles.

    --------------------------------------------------------------------
    -- Main controller, clocked by the PSRAM user clock (40.5 MHz).
    --------------------------------------------------------------------

    process(clk_out, reset_n)
    begin
        if reset_n = '0' then
            state <= WAIT_CALIB;
            cmd0 <= '0';
            cmd1 <= '0';
            cmd_en0 <= '0';
            cmd_en1 <= '0';
            current_addr <= FIRST_TEST_ADDR;
            command_age <= 0;
            turnaround_count <= 0;
            write_word_index <= 0;
            wr_data0 <= (others => '0');
            wr_data1 <= (others => '0');
            read_word_count0 <= 0;
            read_word_count1 <= 0;
            error_ch0 <= '0';
            error_ch1 <= '0';
            last_rd_data0 <= (others => '0');
            last_rd_data1 <= (others => '0');
            play_buffer0 <= (others => '0');
            play_buffer1 <= (others => '0');
            serial_bit_index <= 0;
            serial_prescaler <= 0;
            out_ch1_reg <= '0';
            out_ch2_reg <= '1';

        elsif rising_edge(clk_out) then
            -- Default: command enable is a one-cycle pulse.
            cmd_en0 <= '0';
            cmd_en1 <= '0';

            -- Compare returned words against the pattern for the address that
            -- remains stable throughout this READ_GAP interval.
            if rd_data_valid0 = '1' then
                last_rd_data0 <= rd_data0;
                if read_word_count0 < 8 then
                    if rd_data0 /= test_pattern(current_addr, read_word_count0, 0) then
                        error_ch0 <= '1';
                    end if;
                    if state = PLAY_CAPTURE then
                        play_buffer0((read_word_count0 * 32) + 31 downto read_word_count0 * 32) <= rd_data0;
                    end if;
                    read_word_count0 <= read_word_count0 + 1;
                end if;
            end if;

            if rd_data_valid1 = '1' then
                last_rd_data1 <= rd_data1;
                if read_word_count1 < 8 then
                    if rd_data1 /= test_pattern(current_addr, read_word_count1, 1) then
                        error_ch1 <= '1';
                    end if;
                    if state = PLAY_CAPTURE then
                        play_buffer1((read_word_count1 * 32) + 31 downto read_word_count1 * 32) <= rd_data1;
                    end if;
                    read_word_count1 <= read_word_count1 + 1;
                end if;
            end if;

            case state is
                when WAIT_CALIB =>
                    cmd0 <= '0';
                    cmd1 <= '0';
                    current_addr <= FIRST_TEST_ADDR;
                    command_age <= 0;
                    turnaround_count <= 0;
                    write_word_index <= 0;
                    read_word_count0 <= 0;
                    read_word_count1 <= 0;

                    if pll_lock = '1' and init_calib0 = '1' and init_calib1 = '1' then
                        state <= WRITE_CMD;
                    end if;

                when WRITE_CMD =>
                    -- Start one BL32 write.  Register word 0 at the same time
                    -- as cmd_en.  On the following rising edge the PSRAM IP
                    -- sees cmd_en=1 together with word 0, matching the Gowin
                    -- reference-design transaction style.
                    cmd0 <= '1';
                    cmd1 <= '1';
                    cmd_en0 <= '1';
                    cmd_en1 <= '1';
                    wr_data0 <= test_pattern(current_addr, 0, 0);
                    wr_data1 <= test_pattern(current_addr, 0, 1);
                    write_word_index <= 0;
                    command_age <= 0;
                    state <= WRITE_GAP;

                when WRITE_GAP =>
                    cmd0 <= '0';
                    cmd1 <= '0';

                    -- Advance the registered write data once per clk_out for
                    -- the remaining seven words.  current_addr stays fixed for
                    -- the complete command interval.
                    if write_word_index < 7 then
                        wr_data0 <= test_pattern(current_addr, write_word_index + 1, 0);
                        wr_data1 <= test_pattern(current_addr, write_word_index + 1, 1);
                        write_word_index <= write_word_index + 1;
                    end if;

                    -- Hold current_addr for the whole command interval.
                    if command_age = CMD_INTERVAL - 1 then
                        command_age <= 0;
                        if current_addr = LAST_TEST_ADDR then
                            turnaround_count <= 0;
                            state <= WRITE_TO_READ_WAIT;
                        else
                            current_addr <= current_addr + ADDR_STEP;
                            state <= WRITE_CMD;
                        end if;
                    else
                        command_age <= command_age + 1;
                    end if;

                when WRITE_TO_READ_WAIT =>
                    cmd0 <= '0';
                    cmd1 <= '0';

                    if turnaround_count = TURNAROUND_CYCLES - 1 then
                        turnaround_count <= 0;
                        current_addr <= FIRST_TEST_ADDR;
                        state <= READ_CMD;
                    else
                        turnaround_count <= turnaround_count + 1;
                    end if;

                when READ_CMD =>
                    -- Issue one BL32 read at current_addr.
                    cmd0 <= '0';
                    cmd1 <= '0';
                    cmd_en0 <= '1';
                    cmd_en1 <= '1';
                    command_age <= 0;
                    read_word_count0 <= 0;
                    read_word_count1 <= 0;
                    state <= READ_GAP;

                when READ_GAP =>
                    cmd0 <= '0';
                    cmd1 <= '0';

                    -- Do not advance the address until BOTH channels have
                    -- returned all eight words and the 20-cycle command
                    -- interval has elapsed.
                    if command_age < CMD_INTERVAL - 1 then
                        command_age <= command_age + 1;
                    end if;

                    if command_age = CMD_INTERVAL - 1 and
                       read_word_count0 = 8 and read_word_count1 = 8 then
                        command_age <= 0;
                        if current_addr = LAST_TEST_ADDR then
                            -- Full-memory verification passed.  Start playback
                            -- again from address zero.
                            current_addr <= FIRST_TEST_ADDR;
                            state <= PLAY_READ_CMD;
                        else
                            current_addr <= current_addr + ADDR_STEP;
                            state <= READ_CMD;
                        end if;
                    end if;

                when PLAY_READ_CMD =>
                    -- Request one BL32 burst for playback.
                    cmd0 <= '0';
                    cmd1 <= '0';
                    cmd_en0 <= '1';
                    cmd_en1 <= '1';
                    read_word_count0 <= 0;
                    read_word_count1 <= 0;
                    state <= PLAY_CAPTURE;

                when PLAY_CAPTURE =>
                    cmd0 <= '0';
                    cmd1 <= '0';

                    -- rd_data_valid handling above captures the eight words
                    -- from each channel into play_buffer0/play_buffer1.
                    -- Wait until both complete before serializing.
                    if read_word_count0 = 8 and read_word_count1 = 8 then
                        serial_bit_index <= 0;
                        serial_prescaler <= 0;
                        state <= PLAY_SERIAL;
                    end if;

                when PLAY_SERIAL =>
                    cmd0 <= '0';
                    cmd1 <= '0';

                    -- Keep all logic on clk_out.  The /32 prescaler is only
                    -- a clock-enable for the serial outputs, not a new clock.
                    if serial_prescaler = 31 then
                        serial_prescaler <= 0;
                        out_ch1_reg <= play_buffer0(serial_bit_index);
                        out_ch2_reg <= play_buffer1(serial_bit_index);

                        if serial_bit_index = 255 then
                            serial_bit_index <= 0;
                            if current_addr = LAST_TEST_ADDR then
                                current_addr <= FIRST_TEST_ADDR;
                            else
                                current_addr <= current_addr + ADDR_STEP;
                            end if;
                            state <= PLAY_READ_CMD;
                        else
                            serial_bit_index <= serial_bit_index + 1;
                        end if;
                    else
                        serial_prescaler <= serial_prescaler + 1;
                    end if;
            end case;
        end if;
    end process;

    --------------------------------------------------------------------
    -- Outputs
    --
    -- After the full write/read verification pass, each BL32 read is
    -- captured into a 256-bit buffer per channel.  The buffers are then
    -- serialized LSB-first at clk_out/32:
    --
    --     40.5 MHz / 32 = 1.265625 Mbit/s
    --
    -- Ordering is word 0 bit 0..31, then word 1 bit 0..31, ... word 7.
    -- Channel 1 was written as the exact complement of channel 0, so the
    -- two scope outputs should remain complementary during playback.
    --------------------------------------------------------------------

    out_ch1 <= out_ch1_reg;
    out_ch2 <= out_ch2_reg;

    -- LEDs remain sticky verification/readback error indicators.
    -- LED(0) ON = channel 0 has returned at least one incorrect word.
    -- LED(1) ON = channel 1 has returned at least one incorrect word.
    -- Both LEDs should remain OFF during successful operation.
    led(0) <= not error_ch0;
    led(1) <= not error_ch1;

end RTL;
