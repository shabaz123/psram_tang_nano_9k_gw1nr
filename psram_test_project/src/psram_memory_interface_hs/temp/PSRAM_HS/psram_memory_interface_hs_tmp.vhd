--Copyright (C)2014-2025 Gowin Semiconductor Corporation.
--All rights reserved.
--File Title: Template file for instantiation
--Tool Version: V1.9.11.03 Education
--Part Number: GW1NR-LV9QN88PC6/I5
--Device: GW1NR-9
--Device Version: C
--Created Time: Wed Oct  7 05:39:45 2026

--Change the instance name and port connections to the signal names
----------Copy here to design--------

component PSRAM_Memory_Interface_HS_Top
	port (
		clk: in std_logic;
		rst_n: in std_logic;
		memory_clk: in std_logic;
		pll_lock: in std_logic;
		O_psram_ck: out std_logic_vector(1 downto 0);
		O_psram_ck_n: out std_logic_vector(1 downto 0);
		IO_psram_rwds: inout std_logic_vector(1 downto 0);
		O_psram_reset_n: out std_logic_vector(1 downto 0);
		IO_psram_dq: inout std_logic_vector(15 downto 0);
		O_psram_cs_n: out std_logic_vector(1 downto 0);
		init_calib0: out std_logic;
		init_calib1: out std_logic;
		clk_out: out std_logic;
		cmd0: in std_logic;
		cmd1: in std_logic;
		cmd_en0: in std_logic;
		cmd_en1: in std_logic;
		addr0: in std_logic_vector(20 downto 0);
		addr1: in std_logic_vector(20 downto 0);
		wr_data0: in std_logic_vector(31 downto 0);
		wr_data1: in std_logic_vector(31 downto 0);
		rd_data0: out std_logic_vector(31 downto 0);
		rd_data1: out std_logic_vector(31 downto 0);
		rd_data_valid0: out std_logic;
		rd_data_valid1: out std_logic;
		data_mask0: in std_logic_vector(3 downto 0);
		data_mask1: in std_logic_vector(3 downto 0)
	);
end component;

your_instance_name: PSRAM_Memory_Interface_HS_Top
	port map (
		clk => clk,
		rst_n => rst_n,
		memory_clk => memory_clk,
		pll_lock => pll_lock,
		O_psram_ck => O_psram_ck,
		O_psram_ck_n => O_psram_ck_n,
		IO_psram_rwds => IO_psram_rwds,
		O_psram_reset_n => O_psram_reset_n,
		IO_psram_dq => IO_psram_dq,
		O_psram_cs_n => O_psram_cs_n,
		init_calib0 => init_calib0,
		init_calib1 => init_calib1,
		clk_out => clk_out,
		cmd0 => cmd0,
		cmd1 => cmd1,
		cmd_en0 => cmd_en0,
		cmd_en1 => cmd_en1,
		addr0 => addr0,
		addr1 => addr1,
		wr_data0 => wr_data0,
		wr_data1 => wr_data1,
		rd_data0 => rd_data0,
		rd_data1 => rd_data1,
		rd_data_valid0 => rd_data_valid0,
		rd_data_valid1 => rd_data_valid1,
		data_mask0 => data_mask0,
		data_mask1 => data_mask1
	);

----------Copy end-------------------
