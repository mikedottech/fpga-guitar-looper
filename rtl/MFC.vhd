-- SPDX-FileCopyrightText: 2008-2009 Miguel Angel Exposito
-- SPDX-License-Identifier: MIT
--
-- FPGA Guitar Looper Pedal — Memory Flow Controller (MFC).
-- See LICENSE for full terms.
--
-- This module writes data to SDRAM trough an out FIFO and
-- reads trough an in FIFO.
-- Actual writes are only performed when out FIFO is almost full while
-- actual reads are only performed when in FIFO is almost empty.
-- The write FIFO is also flushed when the end of the loop is reached.
-- WAddr and RAddr internal registers hold the current address
-- to read/write.
-- EOLAddr register points to the end of the loop (can be read from outside)

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
entity MFC is
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
		clrtest			: in std_logic;
		start_writer	: in std_logic;
		
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
end entity;

architecture rtl of MFC is
	component xsasdramcntl_dual
	generic
	(
		FREQ			: integer;
		CLK_DIV 		: real;
	--	PIPE_EN 		: bit;
--		MAX_NOP 		: integer;
	--	MULTIPLE_ACTIVE_ROWS : bit;
		DATA_WIDTH 		: integer;
		NROWS 			: integer;
		NCOLS 			: integer;
		HADDR_WIDTH 	: integer;
		SADDR_WIDTH 	: integer;
		SBANK_WIDTH 	: integer;
		PORT_TIME_SLOTS : bit_vector(15 downto 0)
--		TARGET_BOARD	: integer
	);
	port
	(
		-- control
		clk 	: in std_logic;
		bufclk 	: out std_logic;
		clk1x	: out std_logic;
		clk2x	: out std_logic;
		
		-- port 0
		rst0	: in std_logic;
		rd0		: in std_logic;
		wr0		: in std_logic;
		earlyOpBegun0	: out std_logic;
		opBegun0		: out std_logic;
		rdPending0 		: out std_logic;
		done0 			: out std_logic;
		rdDone0			: out std_logic;
		hAddr0			: in std_logic_vector(HADDR_WIDTH-1 downto 0);
		hDIn0			: in std_logic_vector(DATA_WIDTH-1 downto 0);
		hDOut0			: out std_logic_vector(DATA_WIDTH-1 downto 0);
		status0			: out std_logic_vector(3 downto 0);

		-- port 1
		rst1	: in std_logic;
		rd1		: in std_logic;
		wr1		: in std_logic;
		earlyOpBegun1	: out std_logic;
		opBegun1		: out std_logic;
		rdPending1 		: out std_logic;
		done1 			: out std_logic;
		rdDone1			: out std_logic;
		hAddr1			: in std_logic_vector(HADDR_WIDTH-1 downto 0);
		hDIn1			: in std_logic_vector(DATA_WIDTH-1 downto 0);
		hDOut1			: out std_logic_vector(DATA_WIDTH-1 downto 0);
		status1			: out std_logic_vector(3 downto 0);
		
		-- SDRAM side
		sclkfb			: in std_logic;
		sclk			: out std_logic;
		cke				: out std_logic;
		cs_n			: out std_logic;
		ras_n			: out std_logic;
		cas_n			: out std_logic;
		we_n			: out std_logic;
		ba				: out std_logic_vector(SBANK_WIDTH-1 downto 0);
		sAddr			: out std_logic_vector(SADDR_WIDTH-1 downto 0);
		sData			: inout std_logic_vector(DATA_WIDTH-1 downto 0);
		dqmh			: out std_logic;
		dqml			: out std_logic
	);	
	end component;
	component FIFO0
	PORT
	(
		aclr		: IN STD_LOGIC  := '0';
		data		: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
		rdclk		: IN STD_LOGIC ;
		rdreq		: IN STD_LOGIC ;
		wrclk		: IN STD_LOGIC ;
		wrreq		: IN STD_LOGIC ;
		q		: OUT STD_LOGIC_VECTOR (15 DOWNTO 0);
		rdempty		: OUT STD_LOGIC ;
		rdusedw		: OUT STD_LOGIC_VECTOR (9 DOWNTO 0);
		wrfull		: OUT STD_LOGIC ;
		wrusedw		: OUT STD_LOGIC_VECTOR (9 DOWNTO 0)
	);
	end component;

	-- Build an enumerated type for the state machine
	type reader_state_type is (s0, s1, s2);
	type writer_state_type is (s0, s1, s2, s3);
	type EOL_state_type    is (s0, s1, s2);


	-- Register to hold the current state
	signal reader_state   : reader_state_type;
	signal writer_state   : writer_state_type;
	signal EOL_state	  : EOL_state_type;
	
	signal RAddr : std_logic_vector(22 downto 0);
	signal WAddr : std_logic_vector(22 downto 0);
	signal EOLAddr : std_logic_vector(22 downto 0);

	signal reader_earlyOpBegun  : std_logic;
	signal reader_opBegun 		: std_logic;
	signal reader_rdPending 	: std_logic;
	signal reader_done 			: std_logic;
	signal reader_valid 		: std_logic;
	signal reader_data			: std_logic_vector(15 downto 0);
	signal reader_enable		: std_logic := '1';
	
	signal writer_earlyOpBegun  : std_logic;
	signal writer_opBegun 		: std_logic;
	signal writer_rdPending 	: std_logic;
	signal writer_done 			: std_logic;
	signal writer_valid 		: std_logic;	
	signal writer_data			: std_logic_vector(15 downto 0);

	signal memRd : std_logic;
	signal memWr : std_logic;
	
	signal ramclk : std_logic;
	signal sdrclk : std_logic;
	signal in_read : std_logic;
	signal out_clear : std_logic := '0';
	
	signal flush_input : std_logic;
	signal out_full : std_logic;
	signal in_empty : std_logic;
	signal in_words_write : integer range 0 to 512;
	signal out_words_read : integer range 0 to 512;
	
	--signal SIN_CONT : integer range 0 to 47;
	signal SIN_CONT : integer range 0 to 65535;
	signal Sin_Out : std_logic_vector(15 downto 0);
	signal out_used : STD_LOGIC_VECTOR (9 DOWNTO 0);
	signal in_used : STD_LOGIC_VECTOR (9 DOWNTO 0);
	signal test_value : integer range 0 to 65535;
		
	signal initialWrite : std_logic;
	
	signal in_data_latch : std_logic_vector(15 downto 0);
	
--	signal start_writer : std_logic;
	
	constant SIN_SAMPLE_DATA : integer := 48;
	
begin
		SDR_CLK <= sdrclk;				
		sdramCntl : xsasdramcntl_dual
		generic map (
			FREQ 		=> 100_000, -- 100MHz FSB
			CLK_DIV 	=> 1.0,
			DATA_WIDTH 	=> 16,		-- 16 bits
			NROWS 		=> 4096,
			NCOLS 		=> 256,
			HADDR_WIDTH => 23,		-- 23 address bits
			SADDR_WIDTH => 12,		-- 12 address lines
			SBANK_WIDTH => 2,		-- 2 bank selects
--			PORT_TIME_SLOTS => "1111000011110000"
			PORT_TIME_SLOTS => "1111111110000000"
		)
		port map (
			-- control
			clk 			=> clk,
			bufclk 			=> open,
			clk1x			=> ramclk,
			clk2x			=> open,			
						
			-- port 0 (reader)
			rst0			=> reset,
			rd0				=> memRd,
			wr0				=> '0', -- Port 0 doesn't write
			earlyOpBegun0	=> reader_earlyOpBegun,
			opBegun0		=> reader_opBegun,
			rdPending0 		=> reader_rdPending,
			done0 			=> reader_done,
			rdDone0			=> reader_valid,
			hAddr0			=> RAddr,
			hDIn0			=> (others => '0'),
			hDOut0			=> reader_data,
			status0			=> open,
	
			-- port 1 (writer)
			rst1			=> reset,
			rd1				=> '0',
			wr1				=> memWr,
			earlyOpBegun1	=> writer_earlyOpBegun,
			opBegun1		=> writer_opBegun,
			rdPending1 		=> writer_rdPending,
			done1 			=> writer_done,
			rdDone1			=> open,
			hAddr1			=> WAddr,
			hDIn1			=> writer_data, --std_logic_vector(to_unsigned(test_value, 16)), --writer_data,
			hDOut1			=> open,
			status1			=> open,
	

			sclkfb			=> sdrclk,
			sclk			=> sdrclk,
			cke				=> CKE,
			cs_n			=> CS_N(0),
			ras_n			=> RAS_N,
			cas_n			=> CAS_N,
			we_n			=> WE_N,
			ba				=> BA,
			sAddr			=> SA,
			sData			=> DQ,
			dqmh			=> DQM(1),
			dqml			=> DQM(0)
		);
		FIFOIN : FIFO0
		port map (
			aclr 		=> reset,
			data		=> data_in, --Sin_Out, --std_logic_vector(to_unsigned(SIN_Cont, 16)), --Sin_Out, --data_in,
			rdclk		=> ramclk,
			rdreq		=> in_read,
			wrclk		=> fifo_clk,
			wrreq		=> wr,
			q			=> writer_data,
			rdempty		=> in_empty,
			wrfull		=> in_full,
			rdusedw	    => in_used,
			wrusedw		=> open
		);
		
		FIFOOUT : FIFO0
		port map (
			aclr		=> reset or out_clear,
			data		=> reader_data,
			rdclk		=> fifo_clk,
			rdreq		=> rd,
			wrclk		=> ramclk,
			wrreq		=> reader_valid,
			q			=> data_out,
			rdempty		=> out_empty,
			wrfull		=> out_full,
			rdusedw		=> open,
			wrusedw		=> out_used
		);
	

	reader : process (ramclk, reset) -- OUT
	begin
		if(reset = '1') then
			RAddr  <= (others => '0');
			reader_state <= s0;
			memRd <= '0';
		elsif(rising_edge(ramclk)) then
		if(out_clear = '1') then
			memRd <= '0';
			reader_state <= s0;
		else
			case reader_state is
				when s0 =>	-- Wait for outFIFO to become empty
					if(out_used(9) = '0') then						
						if(out_clear = '1') then
							RAddr <= (others => '0');
							reader_state <= s2;
						else
							reader_state <= s1;
							memRd <= '1';
							out_words_read <= 500;
						end if;						
					end if;					
				when s1 => -- outFIFO Feed
					if(out_words_read /= 0) then 			-- There are still words to read and enough space in buffer
						if(reader_earlyOpBegun = '1') then 	-- supply a new address
							if(RAddr = EOLAddr) then 		-- End of loop reached
								RAddr <= (others => '0');	-- Loop!
							else
								RAddr <= RAddr + 1;
							end if;
							out_words_read <= out_words_read - 1;
						end if;
					else
						memRd <= '0';
						reader_state <= s0; -- Go back to waiting state
					end if;
				when s2 => 
					memRd <= '1';
					out_words_read <= 500;
					reader_state <= s1;
			end case;
			end if;		
		end if;
	end process;


	writer : process (ramclk, reset) -- IN
	begin
		if(reset = '1') then
			--test_value <= 0;
			WAddr  <= (others => '0');
			writer_state <= s0;
			in_read <= '0';
			memWr <= '0';
			EOLAddr  <= (others => '1');
--			EOLAddr  <= std_logic_vector(to_unsigned(192000, 23)); -- 4 seconds
		elsif(rising_edge(ramclk)) then
			case writer_state is
				when s0 =>
					if(in_used(9) = '1') then -- Flush due to FIFO full
						writer_state <= s1;
						in_read <= '1';
						in_words_write <= 500;
					elsif(flush_input = '1') then -- Flush due to EOL
						writer_state <= s1;
						in_read <= '1';						
						in_words_write <= conv_integer(in_used) - 1;
						EOLAddr <= ("000000" & in_used) + WAddr - 1;
					end if;
				when s1 =>					
					in_read <= '0';
					memWr <= '1';
					writer_state <= s2;
				when s2 =>					
					if(writer_earlyOpBegun = '1') then -- Write completed
						memWr <= '0';
						if(in_words_write /= 0) then -- There are still words to write		
							if(WAddr = EOLAddr) then -- End of loop reached
								WAddr <= (others => '0');		-- Loop!								
							else
								WAddr <= WAddr + 1;								
							end if;	
							writer_state <= s1;						
							in_words_write <= in_words_write - 1;
							in_read <= '1';							
						else
							if(WAddr = EOLAddr) then -- End of loop reached
								writer_state <= s3;
							else
								writer_State <= s0;
							end if;
						end if;
					end if;
				when s3 =>
					if(start_writer = '1') then
						WAddr <= (others => '0');
						writer_state <= s0;
					end if;
				end case;			
		end if;
	end process writer;

	EOL_marker : process (ramclk, reset)
	begin
		if(reset = '1') then
			flush_input <= '0';
			out_clear <= '0';
			busy <= '0';
		elsif(rising_edge(ramclk)) then
			case EOL_state is
				when s0 => -- Wait fot EOL
					if(EOLSet = '1') then		-- EOL Marker set
						EOL_state <= s1;
						flush_input <= '1';		-- Flush the inFIFO to memory
						out_clear <= '1';
						busy <= '1';					
						EOL_state <= s2;
					else
						busy <= '0';
						out_clear <= '0';
					end if;					
				when s1 => 
					--if(EOLSet = '0') then
								
						
					--end if;					
				when s2 => -- Flush inFIFO
				out_clear <= '0';
					-- Wait until reader starts the clear operation
					--if(reader_state = s2) then
						-- TODO: Capture out used words
						--out_clear <= '0';
						--if(flush_input = '0') then	
						--	EOL_state <= s0;
						--end if;
					--end if;
					-- Wait until writer starts the flush operation
					if(writer_state = s0) then
						flush_input <= '0';
					--	if(out_clear = '0') then
						EOL_state <= s0;
					--	end if;
					end if;					
			end case;
		end if;
	end process;

-- Sine wave (debug)
	process (ramclk, reset)
	begin
		if(reset = '1') then
			SIN_Cont <= 0;
		elsif(rising_edge(ramclk)) then
			if( writer_state = s1) then
				if(SIN_Cont < SIN_SAMPLE_DATA-1 ) then
--				if(SIN_Cont < 65535) then
					SIN_Cont	<=	SIN_Cont+1;
				else
					SIN_Cont	<=	0;
				end if;
			end if;
		end if;
	end process;

	
	table : process(SIN_Cont)
	begin	
		case(SIN_Cont) is
			when 0 =>  Sin_Out       <=       std_logic_vector(to_unsigned( 0, 16));
			when 1  =>  Sin_Out       <=      std_logic_vector(to_unsigned( 4276, 16));
			when 2  =>  Sin_Out       <=      std_logic_vector(to_unsigned( 8480, 16));
			when 3  =>  Sin_Out       <=      std_logic_vector(to_unsigned( 12539, 16));
			when 4  =>  Sin_Out       <=      std_logic_vector(to_unsigned( 16383, 16));
			when 5  =>  Sin_Out       <=      std_logic_vector(to_unsigned( 19947, 16));
			when 6  =>  Sin_Out       <=      std_logic_vector(to_unsigned( 23169, 16));
			when 7  =>  Sin_Out       <=      std_logic_vector(to_unsigned( 25995, 16));
			when 8  =>  Sin_Out       <=      std_logic_vector(to_unsigned( 28377, 16));
			when 9  =>  Sin_Out       <=      std_logic_vector(to_unsigned( 30272, 16));
			when 10  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 31650, 16));
			when 11  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 32486, 16));
			when 12  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 32767, 16));
			when 13  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 32486, 16));
			when 14  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 31650, 16));
			when 15  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 30272, 16));
			when 16  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 28377, 16));
			when 17  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 25995, 16));
			when 18  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 23169, 16));
			when 19  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 19947, 16));
			when 20  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 16383, 16));
			when 21  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 12539, 16));
			when 22  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 8480, 16));
			when 23  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 4276, 16));
			when 24  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 0, 16));
			when 25  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 61259, 16));
			when 26  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 57056, 16));
			when 27  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 52997, 16));
			when 28  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 49153, 16));
			when 29  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 45589, 16));
			when 30  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 42366, 16));
			when 31  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 39540, 16));
			when 32  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 37159, 16));
			when 33  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 35263, 16));
			when 34  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 33885, 16));
			when 35  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 33049, 16));
			when 36  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 32768, 16));
			when 37  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 33049, 16));
			when 38  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 33885, 16));
			when 39  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 35263, 16));
			when 40  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 37159, 16));
			when 41  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 39540, 16));
			when 42  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 42366, 16));
			when 43  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 45589, 16));
			when 44  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 49152, 16));
			when 45  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 52997, 16));		
			when 46  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 57056, 16));			
			when 47  =>  Sin_Out      <=      std_logic_vector(to_unsigned( 61259, 16));
			when others => Sin_Out <= x"0000";
		end case;
	end process;
end rtl;
