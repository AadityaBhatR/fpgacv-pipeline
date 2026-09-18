library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.ov5640_config_pkg.all;

entity Camera_Setup is
    port(
        clk_100mhz       : in  std_logic;
        reset            : in  std_logic;
        btn_reconfig     : in  std_logic;                    -- Press BTNL to program Live Camera ROM
        btn_test_rom     : in  std_logic;                    -- Press BTND to program Hardware Color-Bar Test Pattern ROM
        rx_byte          : in  std_logic_vector(7 downto 0); -- UART RX byte from PC
        rx_valid         : in  std_logic;                    -- Pulse when rx_byte is valid
        cam_rst_released : in  std_logic;                    -- '1' when camera RESETB is released (from Top reset sequencer)
        sioc             : out std_logic;
        siod             : inout std_logic;
        done             : out std_logic;
        ack_error        : out std_logic;
        failed_rom_idx   : out std_logic_vector(7 downto 0)
    );
end Camera_Setup;

architecture Behavioral of Camera_Setup is

    -- I2C Tristate Drivers
    signal sda_out : std_logic := '1';
    signal scl_out : std_logic := '1';

    -- 4-Phase Clock Division (400kHz Phase Ticks -> 100kHz I2C SCL Clock)
    signal clk_div  : integer range 0 to 249 := 0;
    signal phase    : unsigned(1 downto 0) := "00";
    signal phase_en : std_logic := '0';

    -- State Machine States
    type state_type is (
        IDLE, START_COND, 
        TX_DEV_ADDR, RX_ACK1, 
        TX_REG_H,    RX_ACK2, 
        TX_REG_L,    RX_ACK3, 
        TX_DATA,     RX_ACK4, 
        STOP_COND,   STOP_HOLD, DELAY_STATE, FINISHED
    );
    signal state : state_type := IDLE;

    -- Writable Configuration RAM Array (Initialized with QVGA 320x240 Boot ROM, dynamic override from Python)
    signal config_ram : rom_type := QVGA_BOOT_ROM;
    signal total_regs : integer range 0 to 256 := REG_COUNT;

    -- Operational Counters & Signals
    signal rom_index     : integer range 0 to 256 := 0;
    signal current_cmd   : std_logic_vector(23 downto 0);
    signal bit_cnt       : integer range 0 to 7 := 7;
    signal shift_tx      : std_logic_vector(7 downto 0) := (others => '0');
    signal delay_cnt     : integer := 0;

    -- UART RX Stream Parser State Machine
    type rx_state_type is (IDLE_SYNC, WAIT_SYNC2, READ_COUNT, READ_ADDR_H, READ_ADDR_L, READ_DATA);
    signal rx_state : rx_state_type := IDLE_SYNC;

    signal rx_reg_count : integer range 0 to 256 := 0;
    signal rx_reg_idx   : integer range 0 to 256 := 0;
    signal temp_addr_h  : std_logic_vector(7 downto 0) := (others => '0');
    signal temp_addr_l  : std_logic_vector(7 downto 0) := (others => '0');

    -- Diagnostic Error Logging (Store up to 16 failed ROM indices)
    type err_array_type is array (0 to 15) of integer range 0 to 255;
    signal err_rom_indices : err_array_type := (others => 0);
    signal err_cnt         : integer range 0 to 16 := 0;
    signal ack_error_reg   : std_logic := '0';

    -- 1-Second Error Rotation Timer
    signal err_disp_timer : integer range 0 to 100_000_000 := 0;
    signal err_disp_idx   : integer range 0 to 15 := 0;

    -- Re-configuration Triggers
    signal btn_rec_sync1, btn_rec_sync2, btn_rec_prev   : std_logic := '0';
    signal btn_test_sync1, btn_test_sync2, btn_test_prev : std_logic := '0';
    signal uart_reconfig_trigger                       : std_logic := '0';
    signal btn_reconfig_trigger                        : std_logic := '0';
    signal master_reconfig                             : std_logic := '0';
    signal test_pattern_active                         : std_logic := '0';

    -- 7-Bit OV5640 I2C Slave Address (0x3C -> Write Address 0x78)
    constant SLAVE_ADDR_W : std_logic_vector(7 downto 0) := x"78";

begin

    -- Open-Drain I2C Line Assignments
    siod <= '0' when sda_out = '0' else 'Z';
    sioc <= '0' when scl_out = '0' else 'Z';

    ack_error <= ack_error_reg;

    -- UART RX Live Register Stream Parser
    -- Protocol: [0x55] [0xAA] [REG_COUNT] followed by [REG_COUNT x (ADDR_H, ADDR_L, DATA)]
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            uart_reconfig_trigger <= '0';
            if reset = '1' then
                rx_state <= IDLE_SYNC;
            elsif rx_valid = '1' then
                case rx_state is
                    when IDLE_SYNC =>
                        if rx_byte = x"55" then
                            rx_state <= WAIT_SYNC2;
                        end if;

                    when WAIT_SYNC2 =>
                        if rx_byte = x"AA" then
                            rx_state <= READ_COUNT;
                        else
                            rx_state <= IDLE_SYNC;
                        end if;

                    when READ_COUNT =>
                        rx_reg_count <= to_integer(unsigned(rx_byte));
                        rx_reg_idx   <= 0;
                        if rx_byte = x"00" then
                            rx_state <= IDLE_SYNC;
                        else
                            rx_state <= READ_ADDR_H;
                        end if;

                    when READ_ADDR_H =>
                        temp_addr_h <= rx_byte;
                        rx_state    <= READ_ADDR_L;

                    when READ_ADDR_L =>
                        temp_addr_l <= rx_byte;
                        rx_state    <= READ_DATA;

                    when READ_DATA =>
                        config_ram(rx_reg_idx) <= temp_addr_h & temp_addr_l & rx_byte;
                        if rx_reg_idx = rx_reg_count - 1 then
                            total_regs            <= rx_reg_count;
                            uart_reconfig_trigger <= '1'; -- Trigger immediate camera programming!
                            rx_state              <= IDLE_SYNC;
                        else
                            rx_reg_idx <= rx_reg_idx + 1;
                            rx_state   <= READ_ADDR_H;
                        end if;
                end case;
            end if;
        end if;
    end process;

    -- BTNL (Live Camera) and BTND (Test Pattern) Re-configuration Edge Detector
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            btn_rec_sync1 <= btn_reconfig;
            btn_rec_sync2 <= btn_rec_sync1;
            btn_rec_prev  <= btn_rec_sync2;

            btn_test_sync1 <= btn_test_rom;
            btn_test_sync2 <= btn_test_sync1;
            btn_test_prev  <= btn_test_sync2;

            if btn_test_sync2 /= btn_test_prev then
                -- SW0 flipped: Update test pattern mode and re-trigger configuration!
                test_pattern_active  <= btn_test_sync2;
                btn_reconfig_trigger <= '1';
            elsif btn_rec_sync2 = '1' and btn_rec_prev = '0' then
                -- BTNL pressed: Re-trigger configuration with current switch state!
                test_pattern_active  <= btn_test_sync2;
                btn_reconfig_trigger <= '1';
            else
                btn_reconfig_trigger <= '0';
            end if;
        end if;
    end process;

    -- Combined Single-Driver Reconfig Trigger
    master_reconfig <= uart_reconfig_trigger or btn_reconfig_trigger;

    -- 400kHz Phase Enable Generator (100MHz / 250 = 400kHz)
    process(clk_100mhz, reset)
    begin
        if reset = '1' then
            clk_div  <= 0;
            phase_en <= '0';
        elsif rising_edge(clk_100mhz) then
            if clk_div = 249 then
                clk_div  <= 0;
                phase_en <= '1';
            else
                clk_div  <= clk_div + 1;
                phase_en <= '0';
            end if;
        end if;
    end process;

    -- 4-Phase I2C Master State Machine (Executes when Python streams registers over UART)
    process(clk_100mhz, reset)
    begin
        if reset = '1' then
            state           <= IDLE;
            sda_out         <= '1';
            scl_out         <= '1';
            phase           <= "00";
            delay_cnt       <= 0;
            rom_index       <= 0;
            bit_cnt         <= 7;
            shift_tx        <= (others => '0');
            done            <= '0';
            ack_error_reg   <= '0';
            err_cnt         <= 0;
            err_rom_indices <= (others => 0);
        elsif rising_edge(clk_100mhz) then
            if master_reconfig = '1' then
                state           <= IDLE;
                sda_out         <= '1';
                scl_out         <= '1';
                phase           <= "00";
                delay_cnt       <= 0;
                rom_index       <= 0;
                bit_cnt         <= 7;
                shift_tx        <= (others => '0');
                done            <= '0';
                ack_error_reg   <= '0';
                err_cnt         <= 0;
                err_rom_indices <= (others => 0);
            elsif phase_en = '1' then
                phase <= phase + 1;

                case state is

                    when IDLE =>
                        sda_out <= '1';
                        scl_out <= '1';
                        phase   <= "00";
                        done    <= '0';
                        -- Gate the stabilization countdown: delay_cnt stays 0 while
                        -- cam_rst is still asserted so I2C never fires into a reset camera.
                        if cam_rst_released = '0' then
                            delay_cnt <= 0;
                        elsif total_regs > 0 then
                            if delay_cnt = 4000 then -- 10ms post-reset stabilization delay
                                delay_cnt <= 0;
                                state     <= START_COND;
                            else
                                delay_cnt <= delay_cnt + 1;
                            end if;
                        end if;

                    when START_COND =>
                        if phase = "00" or phase = "01" then
                            scl_out <= '1'; sda_out <= '1';
                        else
                            scl_out <= '1'; sda_out <= '0'; -- SDA drops while SCL is high (START)
                        end if;

                        if phase = "11" then
                            if rom_index = total_regs then
                                state <= FINISHED;
                            else
                                if test_pattern_active = '1' and config_ram(rom_index)(23 downto 8) = x"503D" then
                                    current_cmd <= x"503D80"; -- Hardware 8-Color Bar Test Pattern!
                                else
                                    current_cmd <= config_ram(rom_index);
                                end if;
                                shift_tx    <= SLAVE_ADDR_W;
                                bit_cnt     <= 7;
                                state       <= TX_DEV_ADDR;
                            end if;
                        end if;

                    -- Transmit Bytes (Device Address, Reg Address High, Reg Address Low, Reg Data)
                    when TX_DEV_ADDR | TX_REG_H | TX_REG_L | TX_DATA =>
                        if phase = "00" then
                            scl_out <= '0';
                            sda_out <= shift_tx(bit_cnt);
                        elsif phase = "01" or phase = "10" then
                            scl_out <= '1';
                        elsif phase = "11" then
                            scl_out <= '0';
                            if bit_cnt = 0 then
                                if state = TX_DEV_ADDR then
                                    state <= RX_ACK1;
                                elsif state = TX_REG_H then
                                    state <= RX_ACK2;
                                elsif state = TX_REG_L then
                                    state <= RX_ACK3;
                                else
                                    state <= RX_ACK4;
                                end if;
                            else
                                bit_cnt <= bit_cnt - 1;
                            end if;
                        end if;

                    -- Receive ACK Bits (Sample SDA on Phase "10" when SCL is Stably High)
                    when RX_ACK1 | RX_ACK2 | RX_ACK3 | RX_ACK4 =>
                        if phase = "00" then
                            scl_out <= '0';
                            sda_out <= '1'; -- Release SDA (tristate 'Z') for slave ACK
                        elsif phase = "01" then
                            scl_out <= '1';
                        elsif phase = "10" then
                            scl_out <= '1';
                            -- Sample camera ACK bit (0 = ACK, 1 = NACK)
                            if siod = '1' then
                                ack_error_reg <= '1';
                                if err_cnt < 16 and (err_cnt = 0 or err_rom_indices(err_cnt - 1) /= rom_index) then
                                    err_rom_indices(err_cnt) <= rom_index;
                                    err_cnt <= err_cnt + 1;
                                end if;
                            end if;
                        elsif phase = "11" then
                            scl_out <= '0';
                            if state = RX_ACK1 then
                                state    <= TX_REG_H;
                                shift_tx <= current_cmd(23 downto 16);
                                bit_cnt  <= 7;
                            elsif state = RX_ACK2 then
                                state    <= TX_REG_L;
                                shift_tx <= current_cmd(15 downto 8);
                                bit_cnt  <= 7;
                            elsif state = RX_ACK3 then
                                state    <= TX_DATA;
                                shift_tx <= current_cmd(7 downto 0);
                                bit_cnt  <= 7;
                            else
                                state    <= STOP_COND;
                            end if;
                        end if;

                    -- Issue STOP Condition
                    when STOP_COND =>
                        if phase = "00" then
                            scl_out <= '0'; sda_out <= '0';
                        elsif phase = "01" or phase = "10" then
                            scl_out <= '1'; sda_out <= '0';
                        elsif phase = "11" then
                            scl_out <= '1'; sda_out <= '1'; -- SDA rises while SCL is high (STOP)
                            state   <= STOP_HOLD;
                        end if;

                    when STOP_HOLD =>
                        sda_out <= '1';
                        scl_out <= '1';
                        if phase = "11" then
                            -- Automatically insert 20ms PLL lock delay whenever 0x3008 = 0x82 (software reset) is written
                            if current_cmd(23 downto 16) = x"30" and current_cmd(15 downto 8) = x"08" and current_cmd(7 downto 0) = x"82" then
                                delay_cnt <= 8000; -- 20ms delay for PLL VCO lock
                                state     <= DELAY_STATE;
                            elsif current_cmd(23 downto 16) = x"30" and current_cmd(15 downto 8) = x"08" and current_cmd(7 downto 0) = x"00" then
                                delay_cnt <= 2000; -- 5ms delay after streaming enable
                                state     <= DELAY_STATE;
                            else
                                rom_index <= rom_index + 1;
                                state     <= START_COND;
                            end if;
                        end if;

                    when DELAY_STATE =>
                        sda_out <= '1';
                        scl_out <= '1';
                        if phase = "11" then
                            if delay_cnt = 0 then
                                rom_index <= rom_index + 1;
                                state     <= START_COND;
                            else
                                delay_cnt <= delay_cnt - 1;
                            end if;
                        end if;

                    when FINISHED =>
                        sda_out <= '1';
                        scl_out <= '1';
                        done    <= '1';

                end case;
            end if;
        end if;
    end process;

    -- Cycle through logged NACK error indices on 7-segment display every 1 second
    process(clk_100mhz, reset)
    begin
        if reset = '1' then
            err_disp_timer <= 0;
            err_disp_idx   <= 0;
        elsif rising_edge(clk_100mhz) then
            if err_disp_timer = 100_000_000 - 1 then
                err_disp_timer <= 0;
                if err_cnt > 0 then
                    if err_disp_idx < err_cnt - 1 then
                        err_disp_idx <= err_disp_idx + 1;
                    else
                        err_disp_idx <= 0;
                    end if;
                end if;
            else
                err_disp_timer <= err_disp_timer + 1;
            end if;
        end if;
    end process;

    failed_rom_idx <= std_logic_vector(to_unsigned(err_rom_indices(err_disp_idx), 8)) when err_cnt > 0 else (others => '0');

end Behavioral;