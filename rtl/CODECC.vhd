-- SPDX-FileCopyrightText: 2008-2009 Miguel Angel Exposito
-- SPDX-License-Identifier: MIT
--
-- FPGA Guitar Looper Pedal — CODEC Controller (I2S to WM8731).
-- See LICENSE for full terms.

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity CODECC is

	port 
	(
		reset_n	 : in std_logic;
		
		-- Interface
		oData	 : out std_logic_vector(15 downto 0);
		iClk	 : out std_logic;
		iData	 : in std_logic_vector(15 downto 0);
		
		-- CODEC Control		
		i2c_sclk : out std_logic;
		i2c_sdat : inout std_logic;
				
		-- CODEC Data
		oAUD_DATA : out std_logic;
		oAUD_LRCK : out std_logic;
		oAUD_BCK  : out std_logic;
		
		iAUD_DATA : in std_logic;
		iAUD_LRCK : out std_logic;
		
		clk_18_4 : in std_logic -- 18.432	MHz
	);

end entity;

architecture rtl of CODECC is



	constant REF_CLK	 : integer := 18432000;	-- 18.432	MHz
	constant SAMPLE_RATE : integer := 48000; 	-- 48		KHz
	constant DATA_WIDTH  : integer := 16; 		-- 16 Bits
	constant CHANNEL_NUM : integer := 2;		-- Dual Channel
	signal BCK_DIV : std_logic_vector(3 downto 0);
	signal LRCK_1X_DIV : std_logic_vector(8 downto 0);
	signal LRCK_2X_DIV : std_logic_vector(7 downto 0);
	signal LRCK_4X_DIV : std_logic_vector(6 downto 0);

	signal bck : std_logic;
	signal SEL_Cont : integer range 0 to 15 := 15;
	signal SEL_Cont2 : integer range 0 to 15 := 15;
	signal LRCK_1X : std_logic;
	signal LRCK_2X : std_logic;
	signal LRCK_4x : std_logic;	
	
	signal iData_latch : std_logic_vector(15 downto 0);
	signal oData_latch : std_logic_vector(15 downto 0);
	signal oData_tmp   : std_logic_vector(15 downto 0);
begin

	oAUD_BCK  <= bck;			-- Bit clock
	oAUD_LRCK <= LRCK_1X;		-- Output LR clock
	iAUD_LRCK <= LRCK_1X;		-- Input LR clock
	
	oAUD_DATA  <= iData_latch(SEL_Cont); -- Digital output line
	
	iClk <= LRCK_2X;			-- Module data input sync clock
	
--	oData <= oData_latch;		-- Data output interface

-- Input (mem -> codec) latch
process (LRCK_1X, reset_n)
begin
	if(reset_n = '0') then
		iData_latch <= (others => '0');
	elsif(falling_edge(LRCK_1X)) then
		iData_latch <= iData;
	end if;
end process;

-- Output (codec -> mem) latch (R channel)
process (LRCK_1X, reset_n)
begin
	if(reset_n = '0') then
--		oData_latch <= (others => '0');
		oData <= (others => '0');
	elsif(falling_edge(LRCK_1X)) then
--		oData_latch <= oData_tmp;
		oData <= oData_tmp;
	end if;
end process;

-- AUD_BCK Generator
process (clk_18_4, reset_n)
begin	
	if(reset_n = '0') then	
		BCK_DIV		<=	(others => '0');
		bck			<=	'0';	
	elsif(rising_edge(clk_18_4)) then
		if(BCK_DIV >= REF_CLK/(SAMPLE_RATE*DATA_WIDTH*CHANNEL_NUM*2)-1 ) then
			BCK_DIV	<=	(others => '0');
			bck		<=	not bck;
		else
			BCK_DIV	<=	BCK_DIV+1;
		end if;
	end if;
end process;

-- 16 Bits PISO MSB First
process (bck, reset_n)
begin
	if(reset_n = '0') then	
		SEL_Cont	<=	15;
		oData_tmp <= (others => '0');	
	elsif(falling_edge(bck)) then		
		SEL_Cont	<=	SEL_Cont-1;			
		oData_tmp(SEL_Cont) <= iAUD_DATA;	 -- Digital input line sampler		
	end if;
	
end process;


-- AUD_LRCK Generator
process(clk_18_4, reset_n)
begin
	if(reset_n = '0') then	
		LRCK_1X_DIV	<=	(others => '0');
		LRCK_2X_DIV	<=	(others => '0');
		LRCK_4X_DIV	<=	(others => '0');
		LRCK_1X		<=	'0';
		LRCK_2X		<=	'0';
		LRCK_4X		<=	'0';
	elsif(rising_edge(clk_18_4)) then
		-- LRCK 1X
		if(LRCK_1X_DIV >= REF_CLK/(SAMPLE_RATE*2)-1 ) then		
			LRCK_1X_DIV	<=	(others => '0');
			LRCK_1X	<=	not LRCK_1X;		
		else
			LRCK_1X_DIV		<=	LRCK_1X_DIV+1;
		end if;
		-- LRCK 2X
		if(LRCK_2X_DIV >= REF_CLK/(SAMPLE_RATE*4)-1 ) then		
			LRCK_2X_DIV	<=	(others => '0');
			LRCK_2X	<=	not LRCK_2X;		
		else
			LRCK_2X_DIV		<=	LRCK_2X_DIV+1;		
		end if;
		-- LRCK 4X
		if(LRCK_4X_DIV >= REF_CLK/(SAMPLE_RATE*8)-1 ) then		
			LRCK_4X_DIV	<=	(others => '0');
			LRCK_4X	<=	not LRCK_4X;		
		else
			LRCK_4X_DIV		<=	LRCK_4X_DIV+1;		
		end if;
	end if;
end process;
end rtl;
