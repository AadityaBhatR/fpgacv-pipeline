library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity VGA_Controller is
    port(
        clk_25mhz : in  std_logic;
        rst       : in  std_logic;
        hsync     : out std_logic;
        vsync     : out std_logic;
        video_on  : out std_logic;
        pixel_x   : out integer range 0 to 799;
        pixel_y   : out integer range 0 to 524
    );
end VGA_Controller;

architecture Behavioral of VGA_Controller is

    -- VGA 640x480 @ 60Hz Timing Constants (25 MHz Pixel Clock)
    -- Horizontal Timing
    constant H_ACTIVE     : integer := 640;
    constant H_FRONT_PORCH: integer := 16;
    constant H_SYNC_PULSE : integer := 96;
    constant H_BACK_PORCH : integer := 48;
    constant H_TOTAL      : integer := H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH; -- 800

    -- Vertical Timing
    constant V_ACTIVE     : integer := 480;
    constant V_FRONT_PORCH: integer := 10;
    constant V_SYNC_PULSE : integer := 2;
    constant V_BACK_PORCH : integer := 33;
    constant V_TOTAL      : integer := V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH; -- 525

    -- Counter Registers
    signal h_count : integer range 0 to H_TOTAL - 1 := 0;
    signal v_count : integer range 0 to V_TOTAL - 1 := 0;

begin

    -- Horizontal and Vertical Position Counters
    process(clk_25mhz)
    begin
        if rising_edge(clk_25mhz) then
            if rst = '1' then
                h_count <= 0;
                v_count <= 0;
            else
                -- Horizontal Counter
                if h_count = H_TOTAL - 1 then
                    h_count <= 0;
                    -- Vertical Counter
                    if v_count = V_TOTAL - 1 then
                        v_count <= 0;
                    else
                        v_count <= v_count + 1;
                    end if;
                else
                    h_count <= h_count + 1;
                end if;
            end if;
        end if;
    end process;

    -- Generate Active Low Sync Pulses and Video On Gate
    hsync <= '0' when (h_count >= H_ACTIVE + H_FRONT_PORCH) and 
                      (h_count < H_ACTIVE + H_FRONT_PORCH + H_SYNC_PULSE) else '1';

    vsync <= '0' when (v_count >= V_ACTIVE + V_FRONT_PORCH) and 
                      (v_count < V_ACTIVE + V_FRONT_PORCH + V_SYNC_PULSE) else '1';

    video_on <= '1' when (h_count < H_ACTIVE) and (v_count < V_ACTIVE) else '0';

    -- Export Current Display Coordinates
    pixel_x <= h_count;
    pixel_y <= v_count;

end Behavioral;
