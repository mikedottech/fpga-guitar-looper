-- SPDX-FileCopyrightText: 2008-2009 Miguel Angel Exposito
-- SPDX-License-Identifier: MIT
--
-- FPGA Guitar Looper Pedal — Command Interface.
-- Translates PS/2 keyboard scan codes into looper control commands.
-- See LICENSE for full terms.

library ieee;
use ieee.std_logic_1164.all;

entity cmd_interface is
	port(
		clk	: in std_logic;
		reset : in std_logic;
		ps2_clk_i : in std_logic;
		ps2_data_i : in std_logic;		
		cmd : out std_logic_vector(4 downto 0);
		cmd_active : out std_logic
	);
end entity;

architecture rtl of cmd_interface is
	component ps2_keyboard
	
	port (
	  clk : in std_logic;
	  reset : in std_logic;
-- 	 ps2_clk_en_o_ : out std_logic;
--	 ps2_data_en_o_ : out std_logic;
	  ps2_clk_i : in std_logic;
	  ps2_data_i : in std_logic;
	  rx_extended : out std_logic;
	  rx_released : out std_logic;
	  rx_shift_key_on : out std_logic;
	  rx_scan_code : out std_logic_vector(7 downto 0);
	  rx_ascii : out std_logic_vector(7 downto 0);
	  rx_data_ready : out std_logic;
	  rx_read : in std_logic;
	 -- tx_data : in std_logic_vector(7 downto 0);
	 -- tx_write : in std_logic;
	  tx_write_ack_o : out std_logic;
	  tx_error_no_keyboard_ack : out std_logic;
	  translate : in std_logic
	 );
	end component;
	signal data_ready : std_logic;
	signal scan_code : std_logic_vector(7 downto 0);
	type state_type is (s0, s1);
	signal rx_read : std_logic;
	signal state : state_type;
	signal released : std_logic;
begin
	cmd_active <= '0'; --cmd(0) or cmd(1) or cmd(2) or cmd(3);
	ps2 : ps2_keyboard
	port map
	(
		clk => clk,
		reset => reset,
		ps2_clk_i => ps2_clk_i,
		ps2_data_i => ps2_data_i,
		rx_data_ready => data_ready,
		rx_released => released,
		rx_read => data_ready,
		rx_scan_code => scan_code,
		translate => '1'
	);
	cmd_sense : process(clk, reset)
	begin
		if(reset = '1') then
			cmd <= "00000";
			state <= s0;
		elsif(rising_edge(clk)) then
			case state is	
				when s0 =>
				if(data_ready = '1') then						
					case scan_code is
						when x"29" =>      -- space
							cmd(0) <= '1';
						when x"14" =>	   -- L Ctrl
							cmd(1) <= '1';
						when x"70" =>		-- KP 0								
							cmd(2) <= '1';
						when x"5A" =>
							cmd(3) <= '1';
						when others =>
							cmd <= "00000";
					end case;
					state <= s1;
				end if;					
				when s1 =>
					cmd <= "00000";
					if(data_ready = '1' and released = '1') then
						state <= s0;
					end if;
			end case;
		end if;
	end process;
end rtl;