library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

package ov5640_config_pkg is

    -- Total number of configuration registers to write (146 registers)
    constant REG_COUNT : integer := 146; 
    
    type rom_type is array (0 to 255) of STD_LOGIC_VECTOR(23 downto 0);
    
    -- Format: x"ADDR_DATA" (16-bit Hex Address, 8-bit Hex Data)
    -- True QVGA 320x240 RGB565 DVP Output (25 MHz PCLK, Active-High Sync)
    constant QVGA_BOOT_ROM : rom_type := (
        -- SECTION 1: System Reset, Power Management & DVP Output Enables
        0  => x"300882", -- System Reset (Bit 7=1 Software Reset)
        1  => x"300840", -- Software Power-Down (Maintain Reset State)
        2  => x"300E58", -- DVP Parallel Enable & MIPI Power Down
        3  => x"480004", -- Disable MIPI PHY & Force DVP Parallel Sync Signals
        4  => x"3017FF", -- Pad Output Enable 01 (VSYNC, HREF, PCLK, D[9:6])
        5  => x"3018FF", -- Pad Output Enable 02 (D[5:0])
        6  => x"302C02", -- Pad Drive Strength 2x
        
        -- SECTION 2: Internal PLL Clock Multiplier & System Dividers (25 MHz PCLK)
        7  => x"30341A", -- SC PLL Control 0
        8  => x"303521", -- SC PLL Control 1 (Sys Clock Div = 2)
        9  => x"30363C", -- SC PLL Control 2 (Multiplier = 60)
        10 => x"303713", -- SC PLL Control 3 (Root Div = 1, Pre-Div = 3)
        11 => x"310801", -- System Root Clock Divider
        
        -- SECTION 3: Analog Front-End (AFE) & Essential 4x Subsampling Setup
        12 => x"363036", 13 => x"36310E", 14 => x"3632E2", 15 => x"363312", 16 => x"3621E0",
        17 => x"3704A0", 18 => x"37035A", 19 => x"371578", 20 => x"371701", 21 => x"370B60", 22 => x"37051A",
        23 => x"39010A", 24 => x"361800", 25 => x"361229", 26 => x"370864", 27 => x"370952", 28 => x"370C03",
        29 => x"390502", 30 => x"390610", 31 => x"390310", 
        32 => x"382041", -- Timing TC Reg 20 (vflip)
        33 => x"382107", -- Timing TC Reg 21 (mirror / binning)
        34 => x"381471", -- Subsampling Timing Control 14 (71: 4x hardware binning)
        35 => x"381571", -- Subsampling Timing Control 15 (71: 4x hardware binning)
        36 => x"380000", 37 => x"380100", 38 => x"380200", 39 => x"380304",
        40 => x"38040A", 41 => x"38053F", 42 => x"380607", 43 => x"38079B",
        
        -- SECTION 4: QVGA Resolution Windowing (320 x 240)
        44 => x"380801", -- DVP Output Width MSB (320 = 0x0140)
        45 => x"380940", -- DVP Output Width LSB
        46 => x"380A00", -- DVP Output Height MSB (240 = 0x00F0)
        47 => x"380BF0", -- DVP Output Height LSB
        48 => x"380C07", -- Total Horizontal Line Size MSB (1896 = 0x0768)
        49 => x"380D68", -- Total Horizontal Line Size LSB
        50 => x"380E01", -- Total Vertical Frame Size MSB (500 = 0x01F4)
        51 => x"380FF4", -- Total Vertical Frame Size LSB
        52 => x"381000", 53 => x"381110", 54 => x"381200", 55 => x"381306",
        
        -- SECTION 5: Output Formatter (RGB565 Output & Active-High Polarity)
        56 => x"474023", -- Polarity: Active-High VSYNC, Active-High HREF, Normal PCLK
        57 => x"430061", -- Output Format: RGB565 (R-G-B Byte Order)
        58 => x"501F01", -- ISP RGB Output Mode
        59 => x"471303", -- JPEG Format Config (Disabled for RGB)
        60 => x"440704", -- Quantization Setup
        61 => x"460B35", -- Video FIFO Frame Control 1
        62 => x"460C22", -- Video FIFO Frame Control (Bit 1=1 Manual PCLK Divider Enable)
        63 => x"483722", -- MIPI PHY Control (Power Down MIPI Lanes)
        64 => x"382401", -- DVP PCLK Divider = 1 (25 MHz PCLK)
        65 => x"5000A7", -- ISP Control 0 (LENC, Gamma, DPC, AWB Enable)
        66 => x"5001A3", -- ISP Control 1 (Color Matrix & Scaling Enable - Preserves True Color)
        67 => x"503D00", -- Register 0x503D: Hardware Test Pattern Control (0x00=Off, SW0 overrides to 0x80)
        68 => x"5180FF", -- Auto White Balance (AWB) Boundary
        69 => x"5181F2", -- AWB Step Rate Control
        70 => x"518200", -- AWB Limit Control
        
        -- SECTION 6: Auto Exposure Control (AEC) & Auto Gain Control (AGC)
        71 => x"568410", 72 => x"5685A0", 73 => x"568609", 74 => x"568716",
        75 => x"350300", -- Enable AEC/AGC Auto Mode (Clears manual exposure lock!)
        76 => x"3A0078", -- Enable AEC/AGC & Auto 50/60Hz Banding (Bit 0 = 1!)
        77 => x"3A0203", 78 => x"3A03D8", 79 => x"3A0403", 80 => x"3A0558",
        81 => x"3A0F30", -- AEC Stable Target High (Balanced indoor lighting, eliminates white blowout!)
        82 => x"3A1028", -- AEC Stable Target Low
        83 => x"3A1B30", -- AEC Stable Range High
        84 => x"3A1E28", -- AEC Stable Range Low
        85 => x"3A1160", -- AEC Fast Target High
        86 => x"3A1F10", -- AEC Step Rate
        87 => x"3A15D8", -- 50Hz B50 Low Limit Target
        88 => x"3A0800", 89 => x"3A0950", 90 => x"3A0A00", 91 => x"3A0B06", 92 => x"3A0E02",
        
        -- SECTION 7: Image Tuning (Gamma Curves & Color Correction Matrix)
        93 => x"548001", 94 => x"548108", 95 => x"548214", 96 => x"548328", 97 => x"548451",
        98 => x"548565", 99 => x"548671", 100 => x"54877D", 101 => x"548887", 102 => x"548991",
        103 => x"548A9A", 104 => x"548BAA", 105 => x"548CB8", 106 => x"548DCD", 107 => x"548EDD",
        108 => x"548FEA", 109 => x"54901D",
        110 => x"53811E", 111 => x"53825B", 112 => x"538315", 113 => x"538406", 114 => x"53857E",
        115 => x"538688", 116 => x"53877C", 117 => x"538868", 118 => x"538910", 119 => x"538A01",
        120 => x"538B98", 121 => x"530008", 122 => x"530130", 123 => x"530210", 124 => x"530300",
        125 => x"530908", 126 => x"530A30", 127 => x"530B10", 128 => x"530C00",
        129 => x"502500", 130 => x"50261F", 131 => x"502720", 132 => x"502800",
        
        -- SECTION 8: Auto-White Balance (AWB) Coefficients
        133 => x"518314", 134 => x"518425", 135 => x"518524", 136 => x"518609", 137 => x"518709",
        138 => x"518809", 139 => x"518975", 140 => x"518A54", 141 => x"518BE0", 142 => x"518CB2",
        143 => x"518D42", 144 => x"518E3D",
        
        -- SECTION 9: Final Wake Up & Active Streaming Mode
        145 => x"300800", -- Wake up from software reset to full streaming
        others => (others => '0')
    );

end package ov5640_config_pkg;