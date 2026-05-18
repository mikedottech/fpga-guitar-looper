-- SPDX-FileCopyrightText: 2008-2009 Miguel Angel Exposito
-- SPDX-License-Identifier: MIT
--
-- FPGA Guitar Looper Pedal — top-level module.
-- See LICENSE for full terms.

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_signed.all;
use ieee.numeric_std.all;

entity Looper is
    generic (
         ASIZE          : integer := 23;
         DSIZE          : integer := 16      
    );

	port(
		-- Clock sources
		clk50	 : in	std_logic;
		clk27	 : in	std_logic;
		reset_n	 : in	std_logic;
		leds	 : out	std_logic_vector(4 downto 0);
		key		 : in	std_logic;
		key2	 : in   std_logic;
		key3	 : in   std_logic;
		
		-- SDRAM interface
        SA             : out     std_logic_vector(11 downto 0);               --SDRAM address leds
        BA             : out     std_logic_vector(1 downto 0);                --SDRAM bank address
        CS_N           : out     std_logic_vector(1 downto 0);                --SDRAM Chip Selects
        CKE            : out     std_logic;                                   --SDRAM clock enable
        RAS_N          : out     std_logic;                                   --SDRAM Row address Strobe
        CAS_N          : out     std_logic;                                   --SDRAM Column address Strobe
        WE_N           : out     std_logic;                                   --SDRAM write enable
        DQ             : inout   std_logic_vector(DSIZE-1 downto 0);          --SDRAM data bus
        DQM            : out     std_logic_vector(DSIZE/8-1 downto 0);         --SDRAM data mask lines
		SDR_CLK		   : out	 std_logic;
		
		-- WM8731 Audio codec interface
		AUD_ADCLRCK		: out std_logic; --	Audio CODEC ADC LR Clock
		AUD_ADCDAT		: in std_logic;  --	Audio CODEC ADC Data
		AUD_DACLRCK		: out std_logic; --	Audio CODEC DAC LR Clock
		AUD_DACDAT		: out std_logic; --	Audio CODEC DAC Data
		AUD_BCLK		: out std_logic; --	Audio CODEC Bit-Stream Clock
		AUD_XCK			: out std_logic; --	Audio CODEC Chip Clock
		
		-- I2C Bus
		I2C_SDAT		: inout std_logic; -- I2C Data
		I2C_SCLK		: out std_logic;   -- I2C Clock

		-- PS/2 interface
		PS2_DAT			: in std_logic;	--	PS2 Data
		PS2_CLK			: in std_logic --	PS2 Clock

		
		-- JTAG interface
		--TDO 	   : out std_logic;
		--TDI		   : in std_logic;
		--TCS		   : in std_logic;
		--TCK		   : in std_logic
	);
end entity;

architecture rtl of Looper is
	component MFC
	port(		
		clk 	: in std_logic;
		reset	: in std_logic;
		
		-- DATA IN
		data_in			: in std_logic_vector(15 downto 0);
		wr				: in std_logic;
		in_full			: buffer std_logic;
		
		-- DATA OUT
		data_out		: out std_logic_vector(15 downto 0);
		rd				: in std_logic;
		out_empty		: buffer std_logic;
		
		fifo_clk		: in std_logic;
		
		-- CONTROL
		EOLSet			: in std_logic;
		busy			: out std_logic;
		--postInitWrite	: in std_logic;
		clrtest	 : in std_logic;
		start_writer : in std_logic;
		
		-- SDRAM SIDE
		SA             : out     std_logic_vector(11 downto 0);               --SDRAM address leds
        BA             : out     std_logic_vector(1 downto 0);                --SDRAM bank address
        CS_N           : out     std_logic_vector(1 downto 0);                --SDRAM Chip Selects
        CKE            : out     std_logic;                                   --SDRAM clock enable
        RAS_N          : out     std_logic;                                   --SDRAM Row address Strobe
        CAS_N          : out     std_logic;                                   --SDRAM Column address Strobe
        WE_N           : out     std_logic;                                   --SDRAM write enable
        DQ             : inout   std_logic_vector(15 downto 0);          --SDRAM data bus
        DQM            : out     std_logic_vector(1 downto 0);         --SDRAM data mask lines
		SDR_CLK		   : out	 std_logic

	);
	end component;	
	component alt_pll_x2
	port
	(
		areset : in std_logic;
		inclk0 : in std_logic;
		c0	   : out std_logic;
		c1	   : out std_logic;
		c2	   : out std_logic;
		locked : out std_logic
	);
	end component;
	component pll_audio
	port
	(
		areset	: IN STD_LOGIC  := '0';
		inclk0	: IN STD_LOGIC  := '0';
		c0		: OUT STD_LOGIC 
	);
	end component;
	component reset_delay
	generic	(
		DELAY_CYCLES : integer := 10		
	);
	port (
		reset_n	 	: in	std_logic;
		clk		 	: in	std_logic;
		clklocked	: in	std_logic;
		rst_n_out	: out	std_logic
	);
	end component;
	component CODECC
	port (
		reset_n	: in std_logic;
		
		-- Interface
		oData	 : out std_logic_vector(15 downto 0);
		iClk	 : out std_logic;
		iData	 : in std_logic_vector(15 downto 0);
		
		-- Data
		oAUD_DATA : out std_logic;
		oAUD_LRCK : out std_logic;
		oAUD_BCK  : out std_logic;		
		iAUD_DATA : in std_logic;
		iAUD_LRCK : out std_logic;
		
		clk_18_4 : in std_logic -- 18.432	MHz
	);
	end component;
	component I2C_AV_Config
		port
		(
			iCLK	 : in std_logic;
			iRST_N	 : in std_logic;
			I2C_SCLK : out std_logic;
			I2C_SDAT : inout std_logic
		);
	end component;
	component cmd_interface is
	port(
		clk	: in std_logic;
		reset : in std_logic;
		ps2_clk_i : in std_logic;
		ps2_data_i : in std_logic;		
		cmd : out std_logic_vector(4 downto 0);
		cmd_active : out std_logic
	);
	end component;
	
	-- Build an enumerated type for the state machine
	type state_type is (s0, s1);
	type state2_type is (s0, s1, s2);
	type looper_state_type is (start, start_rec, layer_rec, play, play_pause, layer_pause);
	
	-- Register to hold the current state
	signal state   : state_type;
	signal looper_state : looper_state_type;
	signal state2   : state2_type;
	
	signal clk100 : std_logic;			-- 100 MHz clock
	signal clk100_locked : std_logic;	-- Locked PLL signal
	signal aud_ctrl_clk : std_logic;	-- 18 MHz clock for audio
	signal delay_rst : std_logic;		-- Delayed reset
	
	signal mem_out : std_logic_vector(15 downto 0);
	signal mem_in : std_logic_vector(15 downto 0);
	signal mem_rd  : std_logic;
	signal mem_empty : std_logic;
	signal mem_busy : std_logic;
	signal mem_clk  : std_logic;
	signal mem_wr : std_logic;
	signal mem_full : std_logic;
	
	signal LRCK	: std_logic;
	signal clrtmp : std_logic;
	signal eol : std_logic;
	signal cmd : std_logic_vector (4 downto 0);
	signal read_enable : std_logic;
	signal write_enable : std_logic;
	signal start_writer : std_logic;
	signal mix_store : std_logic_vector(15 downto 0);
	signal mixed_sample : std_logic_vector(15 downto 0);
	
begin

	sdrampll : alt_pll_x2				-- SDRAM PLL (x2)
	port map
	(
		areset => not reset_n,
		inclk0 => clk50,		-- 50 MHz
		c0	   => clk100,		-- 100 MHz
		c1	   => open,
		c2	   => open,
		locked => clk100_locked
	);	
	audiopll : pll_audio				-- Audio CODEC PLL (x2 /3)
	port map
	(
		areset	=> not reset_n,
		inclk0 =>  clk27,
		c0	   =>  aud_ctrl_clk 			-- 18 MHz
	);
	rstdelay: reset_delay				-- Reset delayer
		generic map (
			DELAY_CYCLES => 3000000
		)
		port map (
			clk => clk50,
			reset_n => not cmd(3),
			rst_n_out => delay_rst,
			clklocked => clk100_locked
		);
	
	memoryFlowController : MFC			-- Memory flow controller
	port map (
		clk 	=> clk100,
		reset	=> not delay_rst,
		
		-- DATA IN
		data_in			=> mix_store,
		wr				=> mem_wr,
		in_full			=> mem_full,
		
		-- DATA OUT
		data_out		=> mem_out,
		rd				=> mem_rd,
		out_empty		=> mem_empty,
		
		fifo_clk		=> mem_clk,
		
		-- CONTROL
		EOLSet			=> eol,
		busy			=> mem_busy,
		--postInitWrite	=> '0',
		clrtest	 => clrtmp,
		start_writer => start_writer,
		
		-- SDRAM SIDE
		SA             => SA,
        BA             => BA,
        CS_N           => CS_N,
        CKE            => CKE,
        RAS_N          => RAS_N,
        CAS_N          => CAS_N,
        WE_N           => WE_N,
        DQ             => DQ,
        DQM            => DQM,
		SDR_CLK		   => SDR_CLK
	);
	
	codec_controller : CODECC
	port map (
		reset_n	 => reset_n,
		
		-- Interface
		oData => mem_in,
		iClk	 => mem_clk,
		iData => mixed_sample,
	
		-- DAC Data
		oAUD_DATA => AUD_DACDAT,
		oAUD_LRCK => AUD_DACLRCK,
		oAUD_BCK  => AUD_BCLK,
		
		-- ADC Data
		iAUD_DATA => AUD_ADCDAT,
		iAUD_LRCK => AUD_ADCLRCK,
		
		clk_18_4 => aud_ctrl_clk
	);
	
	-- I2C controller
	I2CC : I2C_AV_Config
	port map
	(
		iCLK	 => clk50,
		iRST_N	 => reset_n,
		I2C_SCLK => I2C_SCLK,
		I2C_SDAT => I2C_SDAT
	);
	
	cmd_if : cmd_interface
	port map(
		clk	=> clk50,
		reset => not reset_n,
		ps2_clk_i => PS2_CLK,
		ps2_data_i => PS2_DAT,
		cmd => cmd,
		cmd_active => open
	);
	
	AUD_XCK <= aud_ctrl_clk;
		
	leds(0) <= delay_rst;
	leds(1) <= mem_full;
	
	mixed_sample <= std_logic_vector((mem_in) + (mem_out));
	
	mix_store <= mixed_sample when looper_state = layer_rec
				 else mem_in;
	
	datapath : process (mem_clk, delay_rst)
	begin
		if delay_rst = '0' then			
			state <= s0;
		elsif (rising_edge(mem_clk)) then
			case state is
				when s0=>		-- Request FIFO data
					mem_rd <= read_enable;
					mem_wr <= write_enable;
					state <= s1;
				when s1=>		-- FIFO latches rdreq and presents data
					state <= s0;
					mem_rd <= '0';					
					mem_wr <= '0';
			end case;
		end if;
	end process;

	looper_fsm : process (clk50, delay_rst)
	begin
		if delay_rst = '0' then			
			looper_state <= start;
			state2 <= s0;
			read_enable <= '0';
			write_enable <= '0';
			eol <= '0';
		elsif (rising_edge(clk50)) then
			case looper_state is
				when start =>
					if(cmd(0) = '1') then
						looper_state <= start_rec;	-- First loop recording
					end if;
					leds(2) <= '0';
					leds(3) <= '0';
				when start_rec =>
					write_enable <= '1';
					if(cmd(0) = '1') then
						eol <= '1';
						looper_state <= play;						
					elsif(cmd(2) = '1') then
						eol <= '1';						
						looper_state <= layer_rec;
					end if;
					leds(2) <= '1';
					leds(3) <= '0';
				when layer_rec =>
					leds(2) <= '1';
					leds(3) <= '1';
					write_enable <= '1';
					read_enable <= '1';
					start_writer <= '1';
					eol <= '0';
					if(cmd(1) = '1') then
						looper_state <= layer_pause;
					elsif(cmd(0) = '1') then
						looper_state <= play;						
					end if;
				when play =>
					eol <= '0';
					write_enable <= '0';
					start_writer <= '0';
					read_enable <= not mem_busy; -- prevents a click
					if(cmd(1) = '1') then						
						looper_state <= play_pause;
					end if;
					leds(2) <= '0';
					leds(3) <= '1';
				when play_pause =>
					read_enable <= '0';
					if(cmd(1) = '1' or cmd(0) = '1') then
						looper_state <= play;
					end if;
					leds(2) <= '0';
					leds(3) <= '0';
				when layer_pause =>
					read_enable <= '0';
					write_enable <= '0';
					if(cmd(1) = '1') then -- unpause
						looper_state <= layer_rec;
					elsif (cmd(0) = '1') then -- switch to normal loop
						--flush_out <= '1';
						looper_state <= play;
					end if;
					leds(2) <= '0';
					leds(3) <= '0';
			end case;
		end if;
	end process;
end rtl;