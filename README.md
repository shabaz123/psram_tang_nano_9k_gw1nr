# Using PSRAM with the Tang Nano 9k (Gowin GW1NR FPGA with integrated PSRAM die)

The GOWIN GW1NR device integrates an FPGA die, and a PSRAM die, all in one package. The GW1NR is used on the Tang Nano 9k, which makes it easy to get going with the GW1NR.

This repository contains example VHDL that exercises the PSRAM. 

## PSRAM Configuration

The Gowin PSRAM IP was configured to split the 64 Mbit PSRAM into two 32 Mbit channels, 32-bit wide data buses, and read/write bursts of 8 words (each word is four bytes, so 8 words is a 32-byte burst according to the Gowin configuration tool, but better understood as an 8-word burst). 

## What does the VHDL code do?

[PSRAM VHDL Block Diagram](https://raw.githubusercontent.com/shabaz123/psram_tang_nano_9k_gw1nr/main/psram_diag.svg) (Preferably right-click and open in a new window, then pinch-to-zoom etc).

The VHDL performs the following operations in sequence:

(1) Write a test pattern to both channels, filling up the entire PSRAM

(2) Verification: Once filled, the entire PSRAM is read (both channels), and if any word does not match the test pattern, then an LED is latched on, to indicate error

(3) Once the entire PSRAM memory has been verified, the entire PSRAM is read and each word is serialized and output on a FPGA pin, so it can be observed with an oscilloscope if desired. This is done on two pins, one for each channel. Since one channel had an inverted version of the test pattern stored, this means that a 2-channel oscilloscope should show matching but inverted waveforms on the two channels.

