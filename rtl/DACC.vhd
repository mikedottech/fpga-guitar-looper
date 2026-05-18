-- SPDX-FileCopyrightText: 2008-2009 Miguel Angel Exposito
-- SPDX-License-Identifier: MIT
--
-- FPGA Guitar Looper Pedal — DAC Controller sub-module.
-- See LICENSE for full terms.

library ieee;
use ieee.std_logic_1164.all;

entity CODECC is

	port 
	(
		reset_n	 : in std_logic;
		
		-- DAC Control
		i2c_clk	 : in std_logic; -- 50 MHz
		i2c_sclk : out std_logic;
		i2c_sdat : inout std_logic;
				
		-- DAC Data
		oAUD_DATA : out std_logic;
		oAUD_LRCK : out std_logic;
		oAUD_BCK  : out std_logic;
		
		clk_18_4 : in std_logic; -- 18.432	MHz

	);

end entity;

architecture rtl of CODECC is

	-- Build an array type for the shift register
	type sr_length is array ((NUM_STAGES-1) downto 0) of std_logic;

	-- Declare the shift register signal
	signal sr: sr_length;

begin

	process (clk)
	begin
		if (rising_edge(clk)) then

			if (enable = '1') then

				-- Shift data by one stage; data from last stage is lost
				sr((NUM_STAGES-1) downto 1) <= sr((NUM_STAGES-2) downto 0);

				-- Load new data into the first stage
				sr(0) <= sr_in;

			end if;
		end if;
	end process;

	-- Capture the data from the last stage, before it is lost
	sr_out <= sr(NUM_STAGES-1);

end rtl;
