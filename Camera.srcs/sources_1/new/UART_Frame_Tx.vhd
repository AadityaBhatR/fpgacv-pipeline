library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity UART_Frame_Tx is
    port(
        clk_100mhz      : in  std_logic;
        rst             : in  std_logic;
        btn_snap        : in  std_logic;  -- Button press trigger (BTNU)
        
        -- Frame Buffer Read Interface (from Camera_Capture - 400x300 = 120,000 pixels)
        fb_read_addr    : out integer range 0 to 131071;
        fb_read_data    : in  std_logic_vector(16 downto 0);
        fb_arm_capture  : out std_logic;
        fb_ready        : in  std_logic;

        -- UART Output & Status Indicator
        uart_tx         : out std_logic;
        tx_busy         : out std_logic;
        led_ready       : out std_logic   -- LED 0 ON when fresh frame is ready in BRAM
    );
end UART_Frame_Tx;

architecture Behavioral of UART_Frame_Tx is

    -- Baud Rate Generator Constants for 921,600 Baud (100MHz / 921600 = 108 clocks/bit)
    constant CLKS_PER_BIT : integer := 108;
    
    -- State Machine
    type state_type is (IDLE_READY, SEND_HDR_1, SEND_HDR_2, WAIT_BRAM, FETCH_PIXEL, SEND_HIGH_BYTE, SEND_LOW_BYTE, ARM_FRESH_CAP, WAIT_FRESH_READY);
    signal state : state_type := IDLE_READY;

    -- UART Transmitter Engine Signals
    signal baud_cnt     : integer range 0 to CLKS_PER_BIT := 0;
    signal bit_idx      : integer range 0 to 9 := 0;
    signal tx_shift_reg : std_logic_vector(9 downto 0) := (others => '1');
    signal tx_start     : std_logic := '0';
    signal tx_byte      : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_active    : std_logic := '0';

    -- Button Debouncer Signals
    signal btn_sync1, btn_sync2, btn_prev : std_logic := '0';
    signal snap_requested : std_logic := '0';

    -- Pixel Memory Address & Byte Pipeline
    signal pixel_idx    : integer range 0 to 131071 := 0;
    signal current_pixel: std_logic_vector(15 downto 0) := (others => '0');

begin

    tx_busy <= '0' when state = IDLE_READY else '1';
    led_ready <= '1' when (state = IDLE_READY and fb_ready = '1') else '0';

    -- Button Edge Detection & Snap Request Latch
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if rst = '1' then
                btn_sync1 <= '0'; btn_sync2 <= '0'; btn_prev <= '0';
                snap_requested <= '0';
            else
                btn_sync1 <= btn_snap;
                btn_sync2 <= btn_sync1;
                btn_prev  <= btn_sync2;

                if btn_sync2 = '1' and btn_prev = '0' then
                    snap_requested <= '1';
                elsif state = SEND_HDR_1 then
                    snap_requested <= '0';
                end if;
            end if;
        end if;
    end process;

    -- UART Bit Transmitter Engine Process (921,600 Baud)
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if rst = '1' then
                uart_tx <= '1';
                baud_cnt <= 0;
                bit_idx <= 0;
                tx_active <= '0';
            else
                if tx_start = '1' and tx_active = '0' then
                    tx_shift_reg <= '1' & tx_byte & '0';
                    baud_cnt <= 0;
                    bit_idx <= 0;
                    tx_active <= '1';
                elsif tx_active = '1' then
                    if baud_cnt = CLKS_PER_BIT - 1 then
                        baud_cnt <= 0;
                        uart_tx <= tx_shift_reg(0);
                        tx_shift_reg <= '1' & tx_shift_reg(9 downto 1);
                        if bit_idx = 9 then
                            tx_active <= '0';
                        else
                            bit_idx <= bit_idx + 1;
                        end if;
                    else
                        baud_cnt <= baud_cnt + 1;
                    end if;
                else
                    uart_tx <= '1';
                end if;
            end if;
        end if;
    end process;

    -- Master BRAM Frame Transfer Controller Process
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if rst = '1' then
                state <= IDLE_READY;
                tx_start <= '0';
                tx_byte <= x"00";
                pixel_idx <= 0;
                fb_read_addr <= 0;
                fb_arm_capture <= '0';
            else
                tx_start <= '0';
                fb_arm_capture <= '0';

                case state is
                    when IDLE_READY =>
                        pixel_idx <= 0;
                        fb_read_addr <= 0;
                        if snap_requested = '1' and fb_ready = '1' then
                            state <= SEND_HDR_1;
                        end if;

                    when SEND_HDR_1 =>
                        if tx_active = '0' and tx_start = '0' then
                            tx_byte <= x"AA"; -- Header magic byte 1
                            tx_start <= '1';
                            state <= SEND_HDR_2;
                        end if;

                    when SEND_HDR_2 =>
                        if tx_active = '0' and tx_start = '0' then
                            tx_byte <= x"55"; -- Header magic byte 2
                            tx_start <= '1';
                            pixel_idx <= 0;
                            fb_read_addr <= 0;
                            state <= WAIT_BRAM;
                        end if;

                    when WAIT_BRAM =>
                        state <= FETCH_PIXEL;

                    when FETCH_PIXEL =>
                        -- Fetch 16-bit RGB565 pixel from BRAM
                        current_pixel <= fb_read_data(15 downto 0);
                        state <= SEND_HIGH_BYTE;

                    when SEND_HIGH_BYTE =>
                        if tx_active = '0' and tx_start = '0' then
                            tx_byte <= current_pixel(15 downto 8); -- High Byte
                            tx_start <= '1';
                            state <= SEND_LOW_BYTE;
                        end if;

                    when SEND_LOW_BYTE =>
                        if tx_active = '0' and tx_start = '0' then
                            tx_byte <= current_pixel(7 downto 0); -- Low Byte
                            tx_start <= '1';
                            
                            if pixel_idx = 119999 then
                                state <= ARM_FRESH_CAP; -- Frame transmission complete!
                            else
                                pixel_idx <= pixel_idx + 1;
                                fb_read_addr <= pixel_idx + 1;
                                state <= WAIT_BRAM; -- Wait 1 clock cycle for BRAM read latency
                            end if;
                        end if;

                    when ARM_FRESH_CAP =>
                        -- Hold fb_arm_capture HIGH until Camera_Capture acknowledges by dropping fb_ready to '0'
                        fb_arm_capture <= '1';
                        if fb_ready = '0' then
                            state <= WAIT_FRESH_READY;
                        end if;

                    when WAIT_FRESH_READY =>
                        -- Clear arm request and wait until fresh frame is full in BRAM
                        fb_arm_capture <= '0';
                        if fb_ready = '1' then
                            state <= IDLE_READY;
                        end if;

                    when others =>
                        state <= IDLE_READY;
                end case;
            end if;
        end if;
    end process;

end Behavioral;
