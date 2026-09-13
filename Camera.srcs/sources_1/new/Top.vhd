library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity Top is
    Port (
        clk_100mhz   : in  STD_LOGIC;
        reset_btn    : in  STD_LOGIC;  -- Active high from Nexys A7 center button (BTNC)
        btn_reconfig : in  STD_LOGIC;  -- Left Button (BTNL P17) for live camera re-configuration
        btn_test_rom : in  STD_LOGIC;  -- Switch 0 (SW0 J15) for hardware color-bar test pattern
        sw_byte_swap : in  STD_LOGIC;  -- Switch 1 (SW1 L16) for RGB byte-order swap
        sw_href_pol  : in  STD_LOGIC;  -- Switch 2 (SW2 M13) for HREF polarity invert
        sw_vsync_pol : in  STD_LOGIC;  -- Switch 3 (SW3 R15) for VSYNC polarity invert
        sw_pclk_edge : in  STD_LOGIC;  -- Switch 4 (SW4 R17) for PCLK sampling edge (clean streaks)
        sw_rotate    : in  STD_LOGIC;  -- Switch 5 (SW5 T18) for 90-degree image rotation
        sw_mirror    : in  STD_LOGIC;  -- Switch 6 (SW6 U18) for horizontal mirror / flip
        sw_vflip     : in  STD_LOGIC;  -- Switch 7 (SW7 R13) for vertical flip / invert
        
        -- Camera PMOD Pins
        cam_xclk   : out STD_LOGIC;
        cam_pclk   : in  STD_LOGIC;
        cam_vsync  : in  STD_LOGIC;
        cam_href   : in  STD_LOGIC;
        cam_d      : in  STD_LOGIC_VECTOR(7 downto 0);
        cam_sioc   : out STD_LOGIC;
        cam_siod   : inout STD_LOGIC;
        cam_rst    : out STD_LOGIC;
        cam_pwdn   : out STD_LOGIC;
        
        -- VGA Display Output Pins
        vga_r      : out STD_LOGIC_VECTOR(3 downto 0);
        vga_g      : out STD_LOGIC_VECTOR(3 downto 0);
        vga_b      : out STD_LOGIC_VECTOR(3 downto 0);
        vga_hs     : out STD_LOGIC;
        vga_vs     : out STD_LOGIC;

        -- USB-UART Micro-USB Ports
        uart_tx    : out STD_LOGIC;
        uart_rx_pin: in  STD_LOGIC;

        -- Debugging
        leds       : out STD_LOGIC_VECTOR(15 downto 0);
        seg        : out STD_LOGIC_VECTOR(6 downto 0);
        an         : out STD_LOGIC_VECTOR(7 downto 0)
    );
end Top;

architecture Behavioral of Top is

    -- Xilinx Global Clock Buffer Primitive
    component BUFG is
        port (
            I : in  std_logic;
            O : out std_logic
        );
    end component;

    -- Component Declarations
    component Camera_Setup is
        Port (
            clk_100mhz       : in  STD_LOGIC;
            reset            : in  STD_LOGIC;
            btn_reconfig     : in  STD_LOGIC;
            btn_test_rom     : in  STD_LOGIC;
            rx_byte          : in  STD_LOGIC_VECTOR(7 downto 0);
            rx_valid         : in  STD_LOGIC;
            cam_rst_released : in  STD_LOGIC;
            sioc             : out STD_LOGIC;
            siod             : inout STD_LOGIC;
            done             : out STD_LOGIC;
            ack_error        : out STD_LOGIC;
            failed_rom_idx   : out STD_LOGIC_VECTOR(7 downto 0)
        );
    end component;

    component UART_Rx is
        Port (
            clk_100mhz : in  STD_LOGIC;
            rst        : in  STD_LOGIC;
            uart_rx    : in  STD_LOGIC;
            rx_byte    : out STD_LOGIC_VECTOR(7 downto 0);
            rx_valid   : out STD_LOGIC
        );
    end component;

    component Frame_Buffer_Memory is
        Port (
            clka  : in  std_logic;
            wea   : in  std_logic;
            addra : in  std_logic_vector(17 downto 0);
            dina  : in  std_logic_vector(11 downto 0);
            clkb  : in  std_logic;
            addrb : in  std_logic_vector(17 downto 0);
            doutb : out std_logic_vector(11 downto 0)
        );
    end component;

    component Camera_Capture is
        Port (
            pclk            : in  STD_LOGIC;
            rst             : in  STD_LOGIC;
            vsync           : in  STD_LOGIC;
            href            : in  STD_LOGIC;
            d_in            : in  STD_LOGIC_VECTOR(7 downto 0);
            sw_byte_swap    : in  STD_LOGIC;
            sw_pclk_edge    : in  STD_LOGIC;
            fb_wea          : out STD_LOGIC;
            fb_addra        : out STD_LOGIC_VECTOR(17 downto 0);
            fb_dina         : out STD_LOGIC_VECTOR(11 downto 0);
            read_bank       : out STD_LOGIC;
            pixel_data_12b  : out STD_LOGIC_VECTOR(11 downto 0);
            pixel_valid     : out STD_LOGIC;
            frame_done      : out STD_LOGIC;
            cam_line_len    : out integer range 0 to 2047
        );
    end component;

    component VGA_Controller is
        Port (
            clk_25mhz : in  STD_LOGIC;
            rst       : in  STD_LOGIC;
            hsync     : out STD_LOGIC;
            vsync     : out STD_LOGIC;
            video_on  : out STD_LOGIC;
            pixel_x   : out integer range 0 to 799;
            pixel_y   : out integer range 0 to 524
        );
    end component;

    component Debug_Interface is
        Port (
            clk_100mhz     : in  STD_LOGIC;
            rst            : in  STD_LOGIC;
            vsync          : in  STD_LOGIC;
            href           : in  STD_LOGIC;
            pclk           : in  STD_LOGIC;
            xclk           : in  STD_LOGIC;
            cam_d          : in  STD_LOGIC_VECTOR(7 downto 0);
            config_done    : in  STD_LOGIC;
            ack_error      : in  STD_LOGIC;
            failed_rom_idx : in  STD_LOGIC_VECTOR(7 downto 0);
            fb_ready       : in  STD_LOGIC;
            cam_line_len   : in  integer range 0 to 2047;
            leds           : out STD_LOGIC_VECTOR(15 downto 0);
            seg            : out STD_LOGIC_VECTOR(6 downto 0);
            an             : out STD_LOGIC_VECTOR(7 downto 0)
        );
    end component;

    -- Internal Signals
    
    -- Clocks (Global Buffers)
    signal xclk_cnt        : unsigned(1 downto 0) := (others => '0');
    signal xclk_raw        : std_logic := '0';
    signal clk_25mhz_bufg  : std_logic;
    signal pclk_bufg       : std_logic;
    
    -- Camera Configuration Telemetry
    signal config_done        : std_logic;
    signal ack_error_int      : std_logic;
    signal failed_rom_idx_int : std_logic_vector(7 downto 0);

    -- Frame Buffer Signals
    signal fb_wea_int         : std_logic;
    signal fb_write_addr_int  : std_logic_vector(17 downto 0);
    signal fb_dina_int        : std_logic_vector(11 downto 0);
    signal fb_read_addr_int   : std_logic_vector(17 downto 0);
    signal fb_doutb_int       : std_logic_vector(11 downto 0);
    signal read_bank_int      : std_logic := '0';
    signal vga_display_bank   : std_logic := '0';
    signal frame_done_int     : std_logic;
    signal cam_line_len_int   : integer range 0 to 2047 := 320;

    -- VGA Controller & Upscaler Connections
    signal vga_video_on   : std_logic;
    signal vga_video_on_d : std_logic := '0';
    signal border_blank   : std_logic := '0';
    signal border_blank_d : std_logic := '0';
    signal vga_hs_raw     : std_logic := '1';
    signal vga_vs_raw     : std_logic := '1';
    signal vga_pixel_x    : integer range 0 to 799;
    signal vga_pixel_y    : integer range 0 to 524;

    -- UART Connections
    signal rx_byte_int   : std_logic_vector(7 downto 0);
    signal rx_valid_int  : std_logic;

    -- Camera Hardware Reset Sequencer
    type rst_seq_state_type is (POWER_ON_RST, ACTIVE, BTN_RST);
    signal rst_seq_state        : rst_seq_state_type := POWER_ON_RST;
    signal rst_seq_cnt          : integer range 0 to 15_000_000 := 0;
    signal cam_rst_int          : std_logic := '0';
    signal cam_rst_released_int : std_logic := '0';
    signal btn_rec_top1, btn_rec_top2, btn_rec_top_prev   : std_logic := '0';
    signal btn_test_top1, btn_test_top2, btn_test_top_prev : std_logic := '0';

    -- Camera Signal Polarity Switches
    signal cam_href_active  : std_logic;
    signal cam_vsync_active : std_logic;

begin

    -- Selectable Signal Polarity (SW2 for HREF, SW3 for VSYNC)
    cam_href_active  <= cam_href  when sw_href_pol  = '0' else not cam_href;
    cam_vsync_active <= cam_vsync when sw_vsync_pol = '0' else not cam_vsync;

    -- Drive UART TX Idle
    uart_tx <= '1';

    -- 100MHz to 25MHz Clock Divider
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if reset_btn = '1' then
                xclk_cnt <= (others => '0');
                xclk_raw <= '0';
            else
                xclk_cnt <= xclk_cnt + 1;
                xclk_raw <= std_logic(xclk_cnt(1)); -- 25 MHz
            end if;
        end if;
    end process;

    -- Global Clock Buffers
    U_BUFG_25: BUFG
    port map (
        I => xclk_raw,
        O => clk_25mhz_bufg
    );

    U_BUFG_PCLK: BUFG
    port map (
        I => cam_pclk,
        O => pclk_bufg
    );

    -- Drive Output Clocks and Control Signals
    cam_xclk <= clk_25mhz_bufg;
    cam_rst  <= cam_rst_int;
    cam_pwdn <= '0'; -- Power down disabled

    -- Camera Hardware Reset Sequencer
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            btn_rec_top1      <= btn_reconfig;
            btn_rec_top2      <= btn_rec_top1;
            btn_rec_top_prev  <= btn_rec_top2;

            btn_test_top1     <= btn_test_rom;
            btn_test_top2     <= btn_test_top1;
            btn_test_top_prev <= btn_test_top2;

            if reset_btn = '1' then
                rst_seq_state        <= POWER_ON_RST;
                rst_seq_cnt          <= 0;
                cam_rst_int          <= '0';
                cam_rst_released_int <= '0';
            else
                case rst_seq_state is

                    when POWER_ON_RST =>
                        cam_rst_int          <= '0';
                        cam_rst_released_int <= '0';
                        if rst_seq_cnt = 15_000_000 - 1 then  -- 150 ms at 100 MHz
                            rst_seq_cnt   <= 0;
                            rst_seq_state <= ACTIVE;
                        else
                            rst_seq_cnt <= rst_seq_cnt + 1;
                        end if;

                    when ACTIVE =>
                        cam_rst_int          <= '1';
                        cam_rst_released_int <= '1';
                        -- Trigger hardware reset if BTNL is pressed OR SW0 is flipped
                        if (btn_rec_top2 = '1' and btn_rec_top_prev = '0') or (btn_test_top2 /= btn_test_top_prev) then
                            rst_seq_cnt   <= 0;
                            rst_seq_state <= BTN_RST;
                        end if;

                    when BTN_RST =>
                        cam_rst_int          <= '0';
                        cam_rst_released_int <= '0';
                        if rst_seq_cnt = 2_000_000 - 1 then  -- 20 ms at 100 MHz
                            rst_seq_cnt   <= 0;
                            rst_seq_state <= ACTIVE;
                        else
                            rst_seq_cnt <= rst_seq_cnt + 1;
                        end if;

                end case;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- VGA Bank Sync (Tear-Free Display: update display bank ONLY in vertical blanking)
    -- =========================================================================
    process(clk_25mhz_bufg)
    begin
        if rising_edge(clk_25mhz_bufg) then
            if reset_btn = '1' then
                vga_display_bank <= '0';
            elsif vga_pixel_y = 480 and vga_pixel_x = 0 then
                vga_display_bank <= read_bank_int;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- VGA Read Address Generator & Multi-Axis Rotation/Mirror Engine
    -- =========================================================================
    -- =========================================================================
    -- VGA Read Address Generator & Multi-Axis Rotation/Mirror Engine (320x240 Ping-Pong)
    -- =========================================================================
    process(vga_display_bank, vga_pixel_x, vga_pixel_y, sw_rotate, sw_mirror, sw_vflip)
        variable base_addr : integer := 0;
        variable x_coord   : integer range 0 to 319 := 0;
        variable y_coord   : integer range 0 to 239 := 0;
        variable col_temp  : integer := 0;
        variable row_temp  : integer := 0;
    begin
        -- Ping-pong buffer selection
        if vga_display_bank = '0' then
            base_addr := 0;
        else
            base_addr := 76800;
        end if;

        if sw_rotate = '0' then
            -- Landscape Mode (320x240 upscaled 2x to 640x480 full screen)
            border_blank <= '0';

            -- Horizontal Axis (640 / 2 = 320)
            if sw_mirror = '0' then
                x_coord := vga_pixel_x / 2;
            else
                x_coord := 319 - (vga_pixel_x / 2);
            end if;

            -- Vertical Axis (480 / 2 = 240)
            if sw_vflip = '0' then
                y_coord := vga_pixel_y / 2;
            else
                y_coord := 239 - (vga_pixel_y / 2);
            end if;
        else
            -- Portrait Mode: 90-degree rotated
            -- VGA display is 640x480.
            -- A 240x320 rotated image can be centered horizontally:
            -- 240 pixels horizontally stretched 2x = 480 screen pixels.
            -- Black borders on left (80 px) and right (80 px): [80 .. 559].
            -- For X in [80 .. 559], col_temp = (vga_pixel_x - 80) / 2 -> 0 to 239.
            -- For Y in [0 .. 479], row_temp = (vga_pixel_y * 171) / 256 -> 0 to 319.
            if vga_pixel_x < 80 or vga_pixel_x >= 560 or vga_pixel_y >= 480 then
                border_blank <= '1';
                x_coord      := 0;
                y_coord      := 0;
            else
                border_blank <= '0';
                col_temp := (vga_pixel_x - 80) / 2;
                row_temp := (vga_pixel_y * 171) / 256;
                if row_temp > 319 then
                    row_temp := 319;
                end if;

                if sw_vflip = '0' then
                    x_coord := row_temp;
                else
                    x_coord := 319 - row_temp;
                end if;

                if sw_mirror = '0' then
                    y_coord := 239 - col_temp;
                else
                    y_coord := col_temp;
                end if;
            end if;
        end if;

        -- Clamp safety guards
        if x_coord > 319 then x_coord := 319; end if;
        if y_coord > 239 then y_coord := 239; end if;

        fb_read_addr_int <= std_logic_vector(to_unsigned(base_addr + (y_coord * 320 + x_coord), 18));
    end process;

    -- Pipeline VGA sync signals and blanking gate by 1 cycle (matches BRAM synchronous Port B read latency)
    process(clk_25mhz_bufg)
    begin
        if rising_edge(clk_25mhz_bufg) then
            vga_video_on_d <= vga_video_on;
            border_blank_d <= border_blank;
            vga_hs         <= vga_hs_raw;
            vga_vs         <= vga_vs_raw;
        end if;
    end process;

    -- Drive 12-bit RGB444 to Nexys A7 DB15 VGA DAC (Active when vga_video_on_d = '1' and inside active image window)
    vga_r <= fb_doutb_int(11 downto 8) when (vga_video_on_d = '1' and border_blank_d = '0') else "0000";
    vga_g <= fb_doutb_int(7 downto 4)  when (vga_video_on_d = '1' and border_blank_d = '0') else "0000";
    vga_b <= fb_doutb_int(3 downto 0)  when (vga_video_on_d = '1' and border_blank_d = '0') else "0000";

    -- Submodule Instantiations
    U_UART_Rx: UART_Rx
    port map(
        clk_100mhz => clk_100mhz,
        rst        => reset_btn,
        uart_rx    => uart_rx_pin,
        rx_byte    => rx_byte_int,
        rx_valid   => rx_valid_int
    );

    U_Camera_Setup: Camera_Setup
    port map(
        clk_100mhz       => clk_100mhz,
        reset            => reset_btn,
        btn_reconfig     => btn_reconfig,
        btn_test_rom     => btn_test_rom,
        rx_byte          => rx_byte_int,
        rx_valid         => rx_valid_int,
        cam_rst_released => cam_rst_released_int,
        sioc             => cam_sioc,
        siod             => cam_siod,
        done             => config_done,
        ack_error        => ack_error_int,
        failed_rom_idx   => failed_rom_idx_int
    );

    U_Frame_Buffer_Memory: Frame_Buffer_Memory
    port map(
        clka  => pclk_bufg,
        wea   => fb_wea_int,
        addra => fb_write_addr_int,
        dina  => fb_dina_int,
        clkb  => clk_25mhz_bufg,
        addrb => fb_read_addr_int,
        doutb => fb_doutb_int
    );

    U_Camera_Capture: Camera_Capture
    port map(
        pclk            => pclk_bufg,
        rst             => reset_btn,
        vsync           => cam_vsync_active,
        href            => cam_href_active,
        d_in            => cam_d,
        sw_byte_swap    => sw_byte_swap,
        sw_pclk_edge    => sw_pclk_edge,
        fb_wea          => fb_wea_int,
        fb_addra        => fb_write_addr_int,
        fb_dina         => fb_dina_int,
        read_bank       => read_bank_int,
        pixel_data_12b  => open,
        pixel_valid     => open,
        frame_done      => frame_done_int,
        cam_line_len    => cam_line_len_int
    );

    U_VGA_Controller: VGA_Controller
    port map(
        clk_25mhz => clk_25mhz_bufg,
        rst       => reset_btn,
        hsync     => vga_hs_raw,
        vsync     => vga_vs_raw,
        video_on  => vga_video_on,
        pixel_x   => vga_pixel_x,
        pixel_y   => vga_pixel_y
    );
    
    U_Debug_Interface: Debug_Interface
    port map(
        clk_100mhz     => clk_100mhz,
        rst            => reset_btn,
        vsync          => cam_vsync_active,
        href           => cam_href_active,
        pclk           => pclk_bufg,
        xclk           => clk_25mhz_bufg,
        cam_d          => cam_d,
        config_done    => config_done,
        ack_error      => ack_error_int,
        failed_rom_idx => failed_rom_idx_int,
        fb_ready       => vga_display_bank,
        cam_line_len   => cam_line_len_int,
        leds           => leds,
        seg            => seg,
        an             => an
    );

end Behavioral;