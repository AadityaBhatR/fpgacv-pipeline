library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity Debug_Interface is
    port(
        clk_100mhz     : in  std_logic;
        rst            : in  std_logic;
        vsync          : in  std_logic;
        href           : in  std_logic;  -- HREF input for line activity
        pclk           : in  std_logic;  -- PCLK input for frequency measurement
        xclk           : in  std_logic;  -- XCLK input for frequency measurement
        cam_d          : in  std_logic_vector(7 downto 0); -- 8-bit video data bus (D9 to D2)
        config_done    : in  std_logic;
        ack_error      : in  std_logic;
        failed_rom_idx : in  std_logic_vector(7 downto 0);
        fb_ready       : in  std_logic; -- Frame Buffer Ready Indicator for LED 0
        cam_line_len   : in  integer range 0 to 2047; -- Line width telemetry (displayed /4 on AN5-AN4)
        leds           : out std_logic_vector(15 downto 0);
        seg            : out std_logic_vector(6 downto 0);
        an             : out std_logic_vector(7 downto 0)
    );
end Debug_Interface;

architecture Behavioral of Debug_Interface is

    -- ==========================================
    -- 1. PCLK & XCLK Frequency Meters (Single Clock Domain)
    -- ==========================================
    signal pclk_sync1, pclk_sync2, pclk_prev : std_logic := '0';
    signal pclk_edge_cnt                     : integer range 0 to 10_000_000 := 0;
    signal pclk_latched_mhz                  : integer range 0 to 255 := 0;
    
    signal xclk_sync1, xclk_sync2, xclk_prev : std_logic := '0';
    signal xclk_edge_cnt                     : integer range 0 to 10_000_000 := 0;
    signal xclk_latched_mhz                  : integer range 0 to 255 := 0;
    
    signal freq_timer                        : integer range 0 to 10_000_000 := 0; -- 100ms window
    -- 2. HREF Activity Counter (Windowed)
    -- ==========================================
    
    -- ==========================================
    -- 3. VSYNC FPS Counter (1-Second Window)
    -- ==========================================
    signal vsync_sync1, vsync_sync2, vsync_prev : std_logic := '0';
    
    signal vsync_edge_cnt           : integer range 0 to 65535 := 0;
    signal latched_fps              : unsigned(7 downto 0) := (others => '0');
    signal sec_counter              : integer range 0 to 100_000_000 := 0;
    
    -- ==========================================
    -- 4. HREF Line Counter (Frame-Synced)
    -- ==========================================
    signal href_sync1, href_sync2, href_prev    : std_logic := '0';
    signal href_count               : integer range 0 to 4095 := 0;
    signal href_latched             : integer range 0 to 4095 := 0;

    -- ==========================================
    -- 5. Seven-Segment Multiplexing Signals
    -- ==========================================
    signal refresh_counter          : integer range 0 to 100_000 := 0;
    signal digit_select             : integer range 0 to 7 := 0; -- All 8 digits active
    signal current_nibble           : std_logic_vector(3 downto 0) := (others => '0');
    
    -- Synchronizer for Camera Line Width (from PCLK domain)
    signal cam_line_len_sync1       : integer range 0 to 2047 := 320;
    signal cam_line_len_sync2       : integer range 0 to 2047 := 320;

    -- Formatted Hex Bytes for Telemetry
    signal pclk_mhz_hex             : std_logic_vector(7 downto 0) := x"00";
    signal xclk_mhz_hex             : std_logic_vector(7 downto 0) := x"00";
    signal href_hex                 : std_logic_vector(7 downto 0) := x"00";
    signal fps_hex                  : std_logic_vector(7 downto 0) := x"00";

    -- ==========================================
    -- Sticky Latches & Toggle Probes for Signal Activity
    -- ==========================================
    signal vsync_ever_high   : std_logic := '0';
    signal href_ever_high    : std_logic := '0';
    
    signal vsync_cnt_600     : integer range 0 to 600 := 0;
    signal href_cnt_288k     : integer range 0 to 288_000 := 0;
    signal led9_vsync_toggle : std_logic := '0';
    signal led8_href_toggle  : std_logic := '0';

begin
    -- LED Mapping:
    -- LED 15: D9 xor D8 (cam_d[7] xor cam_d[6]) -> JC1 / JC2
    -- LED 14: D7 xor D6 (cam_d[5] xor cam_d[4]) -> JC3 / JC4
    -- LED 13: D5 xor D4 (cam_d[3] xor cam_d[2]) -> JC7 / JC8
    -- LED 12: D3 xor D2 (cam_d[1] xor cam_d[0]) -> JC9 / JC10
    -- LED 11: config_done
    -- LED 10: ack_error
    -- LED 9: VSYNC Toggle Probe (Toggles every 600 VSYNC pulses)
    -- LED 8: HREF Toggle Probe (Toggles every 480*600 = 288,000 HREF pulses)
    -- LED 7: Sticky VSYNC Latch (ON permanently once VSYNC pulses high)
    -- LED 6: Sticky HREF Latch (ON permanently once HREF pulses high)
    -- LED 5-1: 00000
    -- LED 0: fb_ready (Frame Buffer Ready Indicator: ON when BRAM is full)
    leds <= (cam_d(7) xor cam_d(6)) & 
            (cam_d(5) xor cam_d(4)) & 
            (cam_d(3) xor cam_d(2)) & 
            (cam_d(1) xor cam_d(0)) & 
            config_done & ack_error & led9_vsync_toggle & led8_href_toggle & vsync_ever_high & href_ever_high & "00000" & fb_ready;

    -- VSYNC (600) & HREF (480*600 = 288,000) Toggle Monitor Process
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if rst = '1' then
                vsync_sync1 <= '0'; vsync_sync2 <= '0'; vsync_prev <= '0';
                href_sync1  <= '0'; href_sync2  <= '0'; href_prev  <= '0';
                vsync_cnt_600 <= 0;
                href_cnt_288k <= 0;
                led9_vsync_toggle <= '0';
                led8_href_toggle  <= '0';
                vsync_ever_high   <= '0';
                href_ever_high    <= '0';
            else
                vsync_sync1 <= vsync;
                vsync_sync2 <= vsync_sync1;
                vsync_prev  <= vsync_sync2;

                href_sync1 <= href;
                href_sync2 <= href_sync1;
                href_prev  <= href_sync2;

                if vsync_sync2 = '1' then
                    vsync_ever_high <= '1';
                end if;
                if href_sync2 = '1' then
                    href_ever_high <= '1';
                end if;

                -- VSYNC Toggle Probe: Toggles LED 9 every 600 VSYNC edges (stage 2 vs stage 3)
                if vsync_sync2 = '1' and vsync_prev = '0' then
                    if vsync_cnt_600 = 600 - 1 then
                        vsync_cnt_600 <= 0;
                        led9_vsync_toggle <= not led9_vsync_toggle;
                    else
                        vsync_cnt_600 <= vsync_cnt_600 + 1;
                    end if;
                end if;

                -- HREF Toggle Probe: Toggles LED 8 every 288,000 (480*600) HREF edges (stage 2 vs stage 3)
                if href_sync2 = '1' and href_prev = '0' then
                    if href_cnt_288k = 288_000 - 1 then
                        href_cnt_288k <= 0;
                        led8_href_toggle <= not led8_href_toggle;
                    else
                        href_cnt_288k <= href_cnt_288k + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- ==========================================
    -- Frequency & Activity Measurement Processes
    -- ==========================================
    
    -- Synchronous PCLK & XCLK Edge Counters
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if rst = '1' then
                pclk_sync1 <= '0'; pclk_sync2 <= '0'; pclk_prev <= '0';
                xclk_sync1 <= '0'; xclk_sync2 <= '0'; xclk_prev <= '0';
                pclk_edge_cnt <= 0; xclk_edge_cnt <= 0;
                pclk_latched_mhz <= 0; xclk_latched_mhz <= 0;
                freq_timer <= 0;
            else
                -- 2-stage CDC Sync for PCLK
                pclk_sync1 <= pclk;
                pclk_sync2 <= pclk_sync1;
                pclk_prev  <= pclk_sync2;
                if pclk_sync2 = '1' and pclk_prev = '0' then
                    pclk_edge_cnt <= pclk_edge_cnt + 1;
                end if;

                -- 2-stage CDC Sync for XCLK
                xclk_sync1 <= xclk;
                xclk_sync2 <= xclk_sync1;
                xclk_prev  <= xclk_sync2;
                if xclk_sync2 = '1' and xclk_prev = '0' then
                    xclk_edge_cnt <= xclk_edge_cnt + 1;
                end if;

                -- 1.024ms Latch Timer (102,400 clock cycles @ 100MHz)
                -- Allows pure bit-shifting (srl 10) for 0.00ns logic delay timing closure
                if freq_timer = 102_400 - 1 then
                    freq_timer <= 0;
                    pclk_latched_mhz <= to_integer(shift_right(to_unsigned(pclk_edge_cnt, 20), 10));
                    xclk_latched_mhz <= to_integer(shift_right(to_unsigned(xclk_edge_cnt, 20), 10));
                    pclk_edge_cnt <= 0;
                    xclk_edge_cnt <= 0;
                else
                    freq_timer <= freq_timer + 1;
                end if;
            end if;
        end if;
    end process;

    -- Measure VSYNC FPS (Direct 2-Stage CDC Edge Counter)
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if (rst = '1') then
                vsync_sync1    <= '0';
                vsync_sync2    <= '0';
                vsync_prev     <= '0';
                latched_fps    <= (others => '0');
                sec_counter    <= 0;
            else
                vsync_sync1 <= vsync;
                vsync_sync2 <= vsync_sync1;
                vsync_prev  <= vsync_sync2;
                
                -- Direct CDC Edge Count (Detects both rising and falling edges for dual-polarity VSYNC support)
                if (vsync_sync2 /= vsync_prev) then
                    vsync_edge_cnt <= vsync_edge_cnt + 1;
                end if;
                
                if sec_counter = 100_000_000 - 1 then
                    sec_counter <= 0;
                    -- Each frame has 2 edges (start and end of VSYNC pulse), so divide total edges by 2 for exact FPS
                    latched_fps <= to_unsigned(vsync_edge_cnt / 2, 8);
                    vsync_edge_cnt <= 0;
                else
                    sec_counter <= sec_counter + 1;
                end if;
            end if;
        end if;
    end process;

    -- Measure HREF Lines Per VSYNC Frame
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if rst = '1' then
                href_sync1   <= '0';
                href_sync2   <= '0';
                href_prev    <= '0';
                href_count   <= 0;
                href_latched <= 0;
            else
                href_sync1 <= href;
                href_sync2 <= href_sync1;
                href_prev  <= href_sync2;

                -- Count rising edges of HREF during frame
                if href_sync2 = '1' and href_prev = '0' then
                    if href_count < 4095 then
                        href_count <= href_count + 1;
                    end if;
                end if;

                -- Latch total lines per frame on VSYNC edge
                if (vsync_sync2 /= vsync_prev) then
                    if href_count > 100 then
                        href_latched <= href_count;
                        href_count   <= 0;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Synchronize cam_line_len across clock domains
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            cam_line_len_sync1 <= cam_line_len;
            cam_line_len_sync2 <= cam_line_len_sync1;
        end if;
    end process;

    -- Convert Integer Measurements to Hex Byte Representations (2 hex digits each)
    pclk_mhz_hex <= std_logic_vector(to_unsigned(pclk_latched_mhz, 8));
    -- AN5-AN4: Camera Line Width / 4 (e.g. 320 / 4 = 80 = 0x50 hex; 640 / 4 = 160 = 0xA0 hex)
    xclk_mhz_hex <= std_logic_vector(to_unsigned(cam_line_len_sync2 / 4, 8));
    -- AN3-AN2 Telemetry:
    -- If ack_error = '1', displays the 2-digit hex index of failing I2C write (failed_rom_idx)
    -- If ack_error = '0', displays lines per frame / 16 (e.g. 240 lines / 16 = 15 = 0x0F hex)
    href_hex     <= failed_rom_idx when ack_error = '1' else std_logic_vector(to_unsigned(to_integer(shift_right(to_unsigned(href_latched, 16), 4)), 8));
    fps_hex      <= std_logic_vector(latched_fps);

    -- ==========================================
    -- Seven-Segment Multiplexer (All 8 Digits)
    -- ==========================================
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if rst = '1' then
                refresh_counter <= 0;
                digit_select <= 0;
            elsif refresh_counter = 100_000 - 1 then
                refresh_counter <= 0;
                if digit_select = 7 then
                    digit_select <= 0;
                else
                    digit_select <= digit_select + 1;
                end if;
            else
                refresh_counter <= refresh_counter + 1;
            end if;
        end if;
    end process;

    -- Digit Selection & Nibble Routing across AN0 to AN7
    process(digit_select, pclk_mhz_hex, xclk_mhz_hex, href_hex, fps_hex)
    begin
        case digit_select is
            when 0 => -- AN0 (Rightmost): FPS LSB
                an <= "11111110";
                current_nibble <= fps_hex(3 downto 0);
            when 1 => -- AN1: FPS MSB
                an <= "11111101";
                current_nibble <= fps_hex(7 downto 4);
            when 2 => -- AN2: HREF Counter LSB
                an <= "11111011";
                current_nibble <= href_hex(3 downto 0);
            when 3 => -- AN3: HREF Counter MSB
                an <= "11110111";
                current_nibble <= href_hex(7 downto 4);
            when 4 => -- AN4: XCLK MHz LSB
                an <= "11101111";
                current_nibble <= xclk_mhz_hex(3 downto 0);
            when 5 => -- AN5: XCLK MHz MSB
                an <= "11011111";
                current_nibble <= xclk_mhz_hex(7 downto 4);
            when 6 => -- AN6: PCLK MHz LSB
                an <= "10111111";
                current_nibble <= pclk_mhz_hex(3 downto 0);
            when 7 => -- AN7 (Leftmost): PCLK MHz MSB
                an <= "01111111";
                current_nibble <= pclk_mhz_hex(7 downto 4);
            when others =>
                an <= "11111111";
                current_nibble <= "0000";
        end case;
    end process;

    -- Hexadecimal 7-Segment Decoder
    process(current_nibble)
    begin
        case current_nibble is
            when x"0" => seg <= "0000001"; -- 0
            when x"1" => seg <= "1001111"; -- 1 (Fixed bottom segment)
            when x"2" => seg <= "0010010"; -- 2
            when x"3" => seg <= "0000110"; -- 3
            when x"4" => seg <= "1001100"; -- 4
            when x"5" => seg <= "0100100"; -- 5
            when x"6" => seg <= "0100000"; -- 6
            when x"7" => seg <= "0001111"; -- 7
            when x"8" => seg <= "0000000"; -- 8
            when x"9" => seg <= "0000100"; -- 9
            when x"A" => seg <= "0001000"; -- A
            when x"B" => seg <= "1100000"; -- b
            when x"C" => seg <= "0110001"; -- C
            when x"D" => seg <= "1000010"; -- d
            when x"E" => seg <= "0110000"; -- E
            when x"F" => seg <= "0111000"; -- F
            when others => seg <= "1111111";
        end case;
    end process;

end Behavioral;