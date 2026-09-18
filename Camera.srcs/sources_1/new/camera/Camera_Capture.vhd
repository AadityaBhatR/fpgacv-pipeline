library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity Camera_Capture is
    port(
        -- Camera DVP Interface (PCLK Domain)
        pclk            : in  std_logic;
        rst             : in  std_logic;
        vsync           : in  std_logic;
        href            : in  std_logic;
        d_in            : in  std_logic_vector(7 downto 0);
        sw_byte_swap    : in  std_logic; -- SW1: '0'=Normal RGB565 byte order, '1'=Swapped byte order
        sw_pclk_edge    : in  std_logic; -- SW4: '0'=Falling edge sampling (clean), '1'=Rising edge direct
        
        -- Frame Buffer Write Interface (to Frame_Buffer_Memory Port A)
        fb_wea          : out std_logic;
        fb_addra        : out std_logic_vector(17 downto 0);
        fb_dina         : out std_logic_vector(11 downto 0);
        
        -- Ping-Pong Bank Status (to VGA Controller in clk_25mhz domain)
        read_bank       : out std_logic; -- '0' = Bank 0 active for read, '1' = Bank 1 active
        
        -- Diagnostics & AI Pipeline Tap
        pixel_data_12b  : out std_logic_vector(11 downto 0);
        pixel_valid     : out std_logic;
        frame_done      : out std_logic;
        cam_line_len    : out integer range 0 to 2047
    );
end Camera_Capture;

architecture Behavioral of Camera_Capture is

    -- Half-cycle phase-aligned sampling registers (clocked on falling edge of PCLK)
    signal d_in_f   : std_logic_vector(7 downto 0) := (others => '0');
    signal href_f   : std_logic := '0';
    signal vsync_f  : std_logic := '0';

    -- Active data and sync signals selected by sw_pclk_edge
    signal d_in_sel  : std_logic_vector(7 downto 0);
    signal href_sel  : std_logic;
    signal vsync_sel : std_logic;

    -- Byte assembler signals
    signal byte_state   : std_logic := '0';
    signal data_high    : std_logic_vector(7 downto 0) := (others => '0');
    signal vsync_prev   : std_logic := '0';
    signal href_prev    : std_logic := '0';
    
    -- Ping-Pong Bank Management
    signal write_bank_reg : std_logic := '0';
    signal read_bank_reg  : std_logic := '1';
    
    -- Strict 2D Coordinate Tracking (PCLK Domain)
    signal cam_x        : integer range 0 to 1023 := 0;
    signal cam_y        : integer range 0 to 1023 := 0;
    signal cam_x_latch  : integer range 0 to 2047 := 320;
    signal cam_y_latch  : integer range 0 to 1023 := 240;

begin

    read_bank    <= read_bank_reg;
    cam_line_len <= cam_x_latch;

    -- 180-Degree Clock Phase Data Latch (Samples 20ns away from camera output transition)
    process(pclk)
    begin
        if falling_edge(pclk) then
            d_in_f  <= d_in;
            href_f  <= href;
            vsync_f <= vsync;
        end if;
    end process;

    d_in_sel  <= d_in_f  when sw_pclk_edge = '0' else d_in;
    href_sel  <= href_f  when sw_pclk_edge = '0' else href;
    vsync_sel <= vsync_f when sw_pclk_edge = '0' else vsync;

    process(pclk)
        variable pixel_12b : std_logic_vector(11 downto 0);
        variable base_addr : integer range 0 to 131072;
        variable target_x  : integer range 0 to 511;
        variable target_y  : integer range 0 to 255;
    begin
        if rising_edge(pclk) then
            if rst = '1' then
                byte_state     <= '0';
                data_high      <= (others => '0');
                vsync_prev     <= '0';
                href_prev      <= '0';
                write_bank_reg <= '0';
                read_bank_reg  <= '1';
                cam_x          <= 0;
                cam_y          <= 0;
                cam_x_latch    <= 320;
                cam_y_latch    <= 240;
                fb_wea         <= '0';
                fb_addra       <= (others => '0');
                fb_dina        <= (others => '0');
                pixel_data_12b <= (others => '0');
                pixel_valid    <= '0';
                frame_done     <= '0';
            else
                fb_wea      <= '0';
                pixel_valid <= '0';
                vsync_prev  <= vsync_sel;
                href_prev   <= href_sel;

                -- 1. Frame Boundary Detection (Active-High VSYNC rising edge)
                if vsync_sel = '1' and vsync_prev = '0' then
                    frame_done     <= '1';
                    read_bank_reg  <= write_bank_reg;      -- Display bank becomes the one just completed
                    write_bank_reg <= not write_bank_reg;  -- Write into alternate bank
                    if cam_y > 100 then
                        cam_y_latch <= cam_y;
                    end if;
                    cam_x          <= 0;
                    cam_y          <= 0;
                    byte_state     <= '0';
                else
                    frame_done     <= '0';
                end if;

                -- 2. Line Boundary Detection (Active-High HREF falling edge)
                if href_sel = '0' and href_prev = '1' then
                    if cam_x > 50 then
                        cam_x_latch <= cam_x;
                    end if;
                    cam_x      <= 0;
                    byte_state <= '0';
                    if cam_y < 1023 then
                        cam_y <= cam_y + 1;
                    end if;
                end if;

                -- Line start synchronization: Ensure byte_state is 0 and cam_x is 0 on HREF rising edge
                if href_sel = '1' and href_prev = '0' then
                    byte_state <= '0';
                    cam_x      <= 0;
                end if;

                -- 3. Pixel Ingest (Active-High HREF)
                if href_sel = '1' then
                    if byte_state = '0' then
                        -- High Byte: R4 R3 R2 R1 R0 G5 G4 G3
                        data_high  <= d_in_sel;
                        byte_state <= '1';
                    else
                        -- Low Byte: G2 G1 G0 B4 B3 B2 B1 B0
                        byte_state <= '0';

                        -- Form 12-bit RGB444 with selectable byte order
                        if sw_byte_swap = '0' then
                            -- Normal: data_high is MSB, d_in_sel is LSB
                            pixel_12b := data_high(7 downto 4) & data_high(2 downto 0) & d_in_sel(7) & d_in_sel(4 downto 1);
                        else
                            -- Swapped: d_in_sel is MSB, data_high is LSB
                            pixel_12b := d_in_sel(7 downto 4) & d_in_sel(2 downto 0) & data_high(7) & data_high(4 downto 1);
                        end if;
                        
                        pixel_data_12b <= pixel_12b;
                        pixel_valid    <= '1';

                        -- Bank base address
                        if write_bank_reg = '0' then
                            base_addr := 0;
                        else
                            base_addr := 76800;
                        end if;

                        -- Full Resolution Ingest (All 240 lines preserved without decimation!)
                        if cam_x_latch > 400 then
                            -- Sensor outputs 640 pixels per line: sample even pixels
                            target_x := cam_x / 2;
                        else
                            -- Sensor outputs 320 pixels per line: 1:1 pixel mapping
                            target_x := cam_x;
                        end if;

                        -- Vertical: All 240 lines captured (Zero skipping!)
                        target_y := cam_y;

                        if (cam_x_latch <= 400 or (cam_x mod 2 = 0)) and (target_x < 320) and (target_y < 240) then
                            fb_wea   <= '1';
                            fb_dina  <= pixel_12b;
                            fb_addra <= std_logic_vector(to_unsigned(base_addr + (target_y * 320 + target_x), 18));
                        end if;

                        if cam_x < 1023 then
                            cam_x <= cam_x + 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

end Behavioral;