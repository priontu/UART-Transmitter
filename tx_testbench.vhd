LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

	--variables named according to specification 
	--in order to improve readability

ENTITY tx_EXECUTABLE IS
	port(
		clk,rst: in std_logic; --Global Clock and Reset
		send_character: in std_logic; --
		data_in: in std_logic_vector(7 downto 0); --input data (data to be transmitted)

		--Transmission detection parameters:
		serial_out, tx_complete: out std_logic --serial_out: start bit
											   --tx_complete: stop bit
	);
END ENTITY;

ARCHITECTURE tx_BEHAVIORAL OF tx_EXECUTABLE IS
	--Finite State Machine Design specific state declaration:
	type FSM_STATE is (IDLE,START,RUN,STOP,RETRN);

	--state registers for management of FSM states:
	signal s_reg: FSM_STATE;
	signal s_next: FSM_STATE;

	--FSM Design Spec requirements:
	signal startBit, stopBit, bit7, incWord, tx_bit, clrTimer, clrWord: std_logic;
	
	--bit counter and bit selection requirements:
	signal bit_sel: std_logic_vector(2 downto 0);
	signal bit_sel_next: unsigned(2 downto 0);
	signal bit_count_reg: unsigned(11 downto 0);
	signal bit_count_next: unsigned(11 downto 0);

	--serial output:
	signal serial_out_next: std_logic;

begin
--------Execution of Bit Timer(Baud-rate = 2603)--------
	process(clk,rst)
	begin
		if(rst = '1') then 					  --if reset is on
			bit_count_reg <= (others => '0'); --clear bit count register
		elsif(clk'event and clk = '1') then
			bit_count_reg <= bit_count_next;  --otherwise, update bit count register
		end if;
	end process;		
	
	--Bit Timer logic:
	--Until bit_count_next reaches 2603, keep incrementing.
	--When bit_count_next = 2603, reset it to 0 and change tx_bit to 1. 
	process(bit_count_reg, clrTimer)
	begin
		tx_bit <= '0';	
		if(clrTimer = '1') then  --
			bit_count_next <= (others => '0');
		--binary(2603) --> 	101000101011
		elsif(bit_count_reg = "101000101011") then
			bit_count_next <= (others => '0');
			tx_bit <= '1';
		else
			bit_count_next <= bit_count_reg + 1;
		end if;
	end process;

----------------Word Counter Execution----------------
	process(rst,clk)
	begin
		if (rst='1') then				--when reset is on
			bit_sel <= (others => '0');	--reset bit selector
		elsif (clk'event and clk = '1') then			   --or, at rising edge of clock
			bit_sel <= std_logic_vector(bit_sel_next); --update bit selector
		end if;
	end process;
	
	--Bit Selector Logic:
		--Using the 3-bit Bit Selector, the system determines
		--which data bit should be sent next. 
		--Implementated as follows:
	process(bit_sel,clrWord,incWord)
	begin
		bit7 <= '0';
		bit_sel_next <= unsigned(bit_sel);
		if (clrWord = '1') then				 --when clrWord = '1'
			bit_sel_next <= (others => '0'); --bit_sel_next updated to 0
		elsif (bit_sel = "111") then 		 --when bit_sel = 7
			bit7 <= '1'; --update bit7 to 1, 
						 --which means data 
						 --transmission is complete
		elsif (incWord = '1') then
			bit_sel_next <= unsigned(bit_sel) + 1; --or, when incWord is 1 
												   --increment bit_sel_next
		else
			bit_sel_next <= unsigned(bit_sel);	--otherwise, assign bit_sel
												--to bit_sel_next
		end if;
	end process;

		--Using this implementation, we can count the number
		--of transmitted bits. When the current count (bit_sel) 
		--equals 7, the FSM detects that the data transmission 
		--is complete through the bit7 variable update.
		--



---------------Finite State Machine Execution---------------
	--we put together all the components we developed in
	--the FSM. The FSM reacts to the word counter and 
	--bit timer to shift in between states and execute
	--the transmission through the UART protocol.

	process(rst,clk)
	begin
		if (rst='1') then
			s_reg <= IDLE;
		elsif (clk'event and clk='1') then
			s_reg <= s_next;
		end if;
	end process;

	process(s_reg, send_character, tx_bit, bit7)
	begin
		incWord <= '0';
		startBit <= '0';
		stopBit <= '0';
		clrTimer <= '0';
		clrWord <= '0';
		tx_complete <= '0';
		s_next <= s_reg;
		case s_reg is
			when IDLE => --when in IDLE state, clear bit timer
						 --and update next state
				stopBit <= '1';
				clrWord <= '1';
				clrTimer <= '1';
				if (send_character='1') then
					s_next <= START;
				end if;
			when START => --when in START state, set startBit to 1
						  --and update next state
				startBit <= '1';
				if (tx_bit='1') then
					s_next <= RUN;
				else
					s_next <= START;
				end if;
			when RUN => --when in RUN state
						--update next state and incWord based on
						--tx_bit and bit7
				if (tx_bit='1' and bit7='0') then
					s_next <= RUN;
					incWord <= '1';
				elsif (tx_bit='1' and bit7='1') then
					s_next <= STOP;
				elsif (tx_bit='0') then
					s_next <= RUN;
				end if;
			when STOP => --when in STOP state, set stopBit to 1
						 --then update next state based on tx_bit
				stopBit <= '1';
				if (tx_bit='1') then
					s_next <= RETRN;
				else
					s_next <= STOP;
				end if;
			when RETRN =>	--when in RETRN state, transmission is
							--complete. This is indicated by setting
							--tx_complete and stopBit to 1.
				stopBit <= '1';
				tx_complete <= '1';
				if (send_character='1') then
					s_next <= RETRN;
				else
					s_next <= IDLE;
				end if;
			when others =>
				s_next <= IDLE;
		end case;		
	end process;

---------------Serial Generator Execution---------------
	--The output of the combinational logic needs to be
	--tracked and registered in order to make sure that
	--a clean serial output is transmitted. This is 
	--accomplished by executing a Serial Generator.

	process(rst,clk)
	begin
		if (clk'event and clk='1') then
			serial_out <= serial_out_next;
		end if;
	end process;

	serial_out_next <= '0' when (startBit='1') else  
					   '1' when (stopBit='1') else  
					   data_in(to_integer(unsigned(bit_sel)));
	--serial_out_next is low when startBit is high
	--serial_out_next is high when stopBit is high
	--otherwise, serial_out is a bit from the input

	--using this implementation we execute the boundary
	--protocols for start and stop of transmission, through
	--which the devices communicate with each other
	--regarding the beginning and end of transmission

	--and 
	
	--also manage to find a way to send the data
	--without manipulating the original input.

END tx_BEHAVIORAL;
