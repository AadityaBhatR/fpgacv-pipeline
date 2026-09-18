library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity UART_Rx is
    port(
        clk_100mhz : in  std_logic;
        rst        : in  std_logic;
        uart_rx    : in  std_logic;
        rx_byte    : out std_logic_vector(7 downto 0);
        rx_valid   : out std_logic
    );
end UART_Rx;

architecture Behavioral of UART_Rx is

    -- 921,600 Baud Clocks Per Bit (100MHz / 921600 = 108)
    constant CLKS_PER_BIT : integer := 108;

    type state_type is (IDLE, RX_START_BIT, RX_DATA_BITS, RX_STOP_BIT);
    signal state : state_type := IDLE;

    signal rx_sync1, rx_sync2 : std_logic := '1';
    signal clk_cnt            : integer range 0 to CLKS_PER_BIT - 1 := 0;
    signal bit_idx            : integer range 0 to 7 := 0;
    signal rx_shift_reg       : std_logic_vector(7 downto 0) := (others => '0');

begin

    -- 2-Stage CDC Synchronizer for UART RX input pin
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            rx_sync1 <= uart_rx;
            rx_sync2 <= rx_sync1;
        end if;
    end process;

    -- UART Receiver State Machine (921,600 Baud)
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if rst = '1' then
                state    <= IDLE;
                clk_cnt  <= 0;
                bit_idx  <= 0;
                rx_valid <= '0';
            else
                rx_valid <= '0';

                case state is

                    when IDLE =>
                        clk_cnt <= 0;
                        bit_idx <= 0;
                        if rx_sync2 = '0' then -- Detect START bit (falling edge)
                            state <= RX_START_BIT;
                        end if;

                    when RX_START_BIT =>
                        -- Sample at the middle of start bit (tick 54)
                        if clk_cnt = (CLKS_PER_BIT / 2) - 1 then
                            if rx_sync2 = '0' then
                                clk_cnt <= 0;
                                state   <= RX_DATA_BITS;
                            else
                                state   <= IDLE; -- False start bit
                            end if;
                        else
                            clk_cnt <= clk_cnt + 1;
                        end if;

                    when RX_DATA_BITS =>
                        if clk_cnt = CLKS_PER_BIT - 1 then
                            clk_cnt <= 0;
                            rx_shift_reg(bit_idx) <= rx_sync2;
                            if bit_idx = 7 then
                                bit_idx <= 0;
                                state   <= RX_STOP_BIT;
                            else
                                bit_idx <= bit_idx + 1;
                            end if;
                        else
                            clk_cnt <= clk_cnt + 1;
                        end if;

                    when RX_STOP_BIT =>
                        if clk_cnt = CLKS_PER_BIT - 1 then
                            clk_cnt  <= 0;
                            rx_byte  <= rx_shift_reg;
                            rx_valid <= '1'; -- Signal 1-clock pulse valid byte received
                            state    <= IDLE;
                        else
                            clk_cnt <= clk_cnt + 1;
                        end if;

                end case;
            end if;
        end if;
    end process;

end Behavioral;
