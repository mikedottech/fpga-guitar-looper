-- SPDX-FileCopyrightText: 2008-2009 Miguel Angel Exposito
-- SPDX-License-Identifier: MIT
--
-- FPGA Guitar Looper Pedal — bench-top test wrapper for the I2C
-- codec configuration path.
-- See LICENSE for full terms.

library ieee;
use ieee.std_logic_1164.all;

entity LooperTop is
	port(
		-- Clock sources
		clk50	 : in	std_logic;
		reset_n  : in	std_logic;
		-- I2C Bus
		I2C_SCLK		: out std_logic;   -- I2C Clock
		I2C_SDAT		: inout std_logic -- I2C Data
	);
end entity;

architecture rtl of LooperTop is
	component I2C_AV_Config
		port
		(
			iCLK	 : in std_logic;
			iRST_N	 : in std_logic;
			I2C_SCLK : out std_logic;
			I2C_SDAT : inout std_logic
		);
	end component;
begin
	i2c : I2C_AV_CONFIG
	port map
	(
		iCLK 		=> clk50,
		iRST_N		=> reset_n,
		I2C_SCLK	=> I2C_SCLK,
		I2C_SDAT	=> I2C_SDAT		
	);
end rtl;