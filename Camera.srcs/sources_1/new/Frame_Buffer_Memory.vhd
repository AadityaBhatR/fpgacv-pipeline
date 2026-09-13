library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity Frame_Buffer_Memory is
    port(
        -- Port A: Camera Write Domain (PCLK)
        clka  : in  std_logic;
        wea   : in  std_logic;
        addra : in  std_logic_vector(17 downto 0); -- 18 bits (153,600 words for ping-pong dual buffering)
        dina  : in  std_logic_vector(11 downto 0); -- 12-bit RGB444 pixel
        
        -- Port B: VGA Display Read Domain (25MHz Pixel Clock)
        clkb  : in  std_logic;
        addrb : in  std_logic_vector(17 downto 0); -- 18 bits
        doutb : out std_logic_vector(11 downto 0)  -- 12-bit RGB444 pixel to VGA DAC
    );
end Frame_Buffer_Memory;

architecture Behavioral of Frame_Buffer_Memory is

    -- Ping-Pong Dual Frame Buffer: 2 banks of 76,800 words = 153,600 words x 12 bits
    -- Bank 0: 0 to 76799
    -- Bank 1: 76800 to 153599
    -- Consumes ~50 RAMB36 Block RAM tiles with cascade_height = 1 (Zero DRC violations)
    type ram_type is array (0 to 153599) of std_logic_vector(11 downto 0);
    signal ram : ram_type := (others => (others => '0'));

    attribute ram_style : string;
    attribute ram_style of ram : signal is "block";

    -- Disable BRAM cascading to eliminate Vivado DRC REQP-1962 cascade pin error
    attribute cascade_height : integer;
    attribute cascade_height of ram : signal is 1;

begin

    -- Synchronous Port A Write (Camera PCLK)
    process(clka)
    begin
        if rising_edge(clka) then
            if wea = '1' then
                if to_integer(unsigned(addra)) < 153600 then
                    ram(to_integer(unsigned(addra))) <= dina;
                end if;
            end if;
        end if;
    end process;

    -- Synchronous Port B Read (VGA 25MHz Clock)
    process(clkb)
    begin
        if rising_edge(clkb) then
            if to_integer(unsigned(addrb)) < 153600 then
                doutb <= ram(to_integer(unsigned(addrb)));
            else
                doutb <= (others => '0');
            end if;
        end if;
    end process;

end Behavioral;
