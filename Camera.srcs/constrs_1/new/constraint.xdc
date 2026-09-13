## Device Configuration Properties
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## Clock signal (100MHz)
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk_100mhz]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports clk_100mhz]

## Center Button for System Reset (Active High BTNC)
set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS33} [get_ports reset_btn]

## Left Button for Live Camera Re-configuration Trigger (Active High BTNL)
set_property -dict {PACKAGE_PIN P17 IOSTANDARD LVCMOS33} [get_ports btn_reconfig]

## Switch 0 (SW0 Pin J15) for Hardware Color-Bar Test Pattern Toggle
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports btn_test_rom]

## Switch 1 (SW1 Pin L16) for RGB Byte-Order Swap (Toggle if colors are inverted/tinted)
set_property -dict {PACKAGE_PIN L16 IOSTANDARD LVCMOS33} [get_ports sw_byte_swap]

## Switch 2 (SW2 Pin M13) for HREF Polarity Invert (Toggle to match camera active line polarity)
set_property -dict {PACKAGE_PIN M13 IOSTANDARD LVCMOS33} [get_ports sw_href_pol]

## Switch 3 (SW3 Pin R15) for VSYNC Polarity Invert (Toggle to match camera frame sync polarity)
set_property -dict {PACKAGE_PIN R15 IOSTANDARD LVCMOS33} [get_ports sw_vsync_pol]

## Switch 4 (SW4 Pin R17) for PCLK Clock Edge Invert (Toggle to eliminate digital streaks/glitches)
set_property -dict {PACKAGE_PIN R17 IOSTANDARD LVCMOS33} [get_ports sw_pclk_edge]

## Switch 5 (SW5 Pin T18) for 90-Degree Image Rotation (Right-side up portrait vs landscape)
set_property -dict {PACKAGE_PIN T18 IOSTANDARD LVCMOS33} [get_ports sw_rotate]

## Switch 6 (SW6 Pin U18) for Horizontal Mirror / Flip
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports sw_mirror]

## Switch 7 (SW7 Pin R13) for Vertical Flip / Invert
set_property -dict {PACKAGE_PIN R13 IOSTANDARD LVCMOS33} [get_ports sw_vflip]

## Micro-USB UART Transmit Pin (FT2232H USB-UART TX)
set_property -dict {PACKAGE_PIN D4 IOSTANDARD LVCMOS33} [get_ports uart_tx]

## Micro-USB UART Receive Pin (FT2232H USB-UART RX)
set_property -dict {PACKAGE_PIN C4 IOSTANDARD LVCMOS33} [get_ports uart_rx_pin]

## =========================================================================
## PMOD JB: Camera Control & Clocks
## =========================================================================
# JB Pin 1: XCLK (FPGA to Camera 25MHz Clock)
set_property -dict {PACKAGE_PIN D14 IOSTANDARD LVCMOS33} [get_ports cam_xclk]

# JB Pin 2: PCLK (Camera to FPGA Pixel Clock) -> SRCC Pin
set_property -dict {PACKAGE_PIN F16 IOSTANDARD LVCMOS33} [get_ports cam_pclk]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets cam_pclk_IBUF]
create_clock -period 40.000 -name cam_pclk_pin -waveform {0.000 20.000} [get_ports cam_pclk]

# JB Pin 3: VSYNC (Start of Frame)
set_property -dict {PACKAGE_PIN G16 IOSTANDARD LVCMOS33} [get_ports cam_vsync]
# JB Pin 4: HREF (Active Pixels)
set_property -dict {PACKAGE_PIN H14 IOSTANDARD LVCMOS33} [get_ports cam_href]

# JB Pin 7: SIOC (I2C Clock) - Pullup for open-drain I2C safety
set_property PACKAGE_PIN E16 [get_ports cam_sioc]
set_property IOSTANDARD LVCMOS33 [get_ports cam_sioc]
set_property PULLTYPE PULLUP [get_ports cam_sioc]

# JB Pin 8: SIOD (I2C Data) - Added Pullup for Open-Drain safety
set_property PACKAGE_PIN F13 [get_ports cam_siod]
set_property IOSTANDARD LVCMOS33 [get_ports cam_siod]
set_property PULLTYPE PULLUP [get_ports cam_siod]

# JB Pin 9: RST (Active Low Reset)
set_property -dict {PACKAGE_PIN G13 IOSTANDARD LVCMOS33} [get_ports cam_rst]
# JB Pin 10: PWDN (Active High Power Down)
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports cam_pwdn]


## =========================================================================
## PMOD JC: 8-Bit Video Data Bus (D9 is MSB, D2 is LSB)
## =========================================================================
# JC Pin 1: Camera D9
set_property -dict {PACKAGE_PIN K1 IOSTANDARD LVCMOS33} [get_ports {cam_d[7]}]
# JC Pin 2: Camera D8
set_property -dict {PACKAGE_PIN F6 IOSTANDARD LVCMOS33} [get_ports {cam_d[6]}]
# JC Pin 3: Camera D7
set_property -dict {PACKAGE_PIN J2 IOSTANDARD LVCMOS33} [get_ports {cam_d[5]}]
# JC Pin 4: Camera D6
set_property -dict {PACKAGE_PIN G6 IOSTANDARD LVCMOS33} [get_ports {cam_d[4]}]
# JC Pin 7: Camera D5
set_property -dict {PACKAGE_PIN E7 IOSTANDARD LVCMOS33} [get_ports {cam_d[3]}]
# JC Pin 8: Camera D4
set_property -dict {PACKAGE_PIN J3 IOSTANDARD LVCMOS33} [get_ports {cam_d[2]}]
# JC Pin 9: Camera D3
set_property -dict {PACKAGE_PIN J4 IOSTANDARD LVCMOS33} [get_ports {cam_d[1]}]
# JC Pin 10: Camera D2
set_property -dict {PACKAGE_PIN E6 IOSTANDARD LVCMOS33} [get_ports {cam_d[0]}]


## =========================================================================
## Debugging LEDs (0 to 15)
## =========================================================================
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports {leds[0]}]
set_property -dict {PACKAGE_PIN K15 IOSTANDARD LVCMOS33} [get_ports {leds[1]}]
set_property -dict {PACKAGE_PIN J13 IOSTANDARD LVCMOS33} [get_ports {leds[2]}]
set_property -dict {PACKAGE_PIN N14 IOSTANDARD LVCMOS33} [get_ports {leds[3]}]
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS33} [get_ports {leds[4]}]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports {leds[5]}]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33} [get_ports {leds[6]}]
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports {leds[7]}]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports {leds[8]}]
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports {leds[9]}]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports {leds[10]}]
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVCMOS33} [get_ports {leds[11]}]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports {leds[12]}]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports {leds[13]}]
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports {leds[14]}]
set_property -dict {PACKAGE_PIN V11 IOSTANDARD LVCMOS33} [get_ports {leds[15]}]


## =========================================================================
## 7-Segment Display (Cathodes seg[6:0] and Anodes an[7:0])
## =========================================================================
# Cathodes A to G
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {seg[6]}]
set_property -dict {PACKAGE_PIN R10 IOSTANDARD LVCMOS33} [get_ports {seg[5]}]
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports {seg[4]}]
set_property -dict {PACKAGE_PIN K13 IOSTANDARD LVCMOS33} [get_ports {seg[3]}]
set_property -dict {PACKAGE_PIN P15 IOSTANDARD LVCMOS33} [get_ports {seg[2]}]
set_property -dict {PACKAGE_PIN T11 IOSTANDARD LVCMOS33} [get_ports {seg[1]}]
set_property -dict {PACKAGE_PIN L18 IOSTANDARD LVCMOS33} [get_ports {seg[0]}]

# Anodes 0 to 7 (AN0 is rightmost digit)
set_property -dict {PACKAGE_PIN J17 IOSTANDARD LVCMOS33} [get_ports {an[0]}]
set_property -dict {PACKAGE_PIN J18 IOSTANDARD LVCMOS33} [get_ports {an[1]}]
set_property -dict {PACKAGE_PIN T9  IOSTANDARD LVCMOS33} [get_ports {an[2]}]
set_property -dict {PACKAGE_PIN J14 IOSTANDARD LVCMOS33} [get_ports {an[3]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {an[4]}]
set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS33} [get_ports {an[5]}]
set_property -dict {PACKAGE_PIN K2  IOSTANDARD LVCMOS33} [get_ports {an[6]}]
set_property -dict {PACKAGE_PIN U13 IOSTANDARD LVCMOS33} [get_ports {an[7]}]


## =========================================================================
## VGA Display Connector Pins (Nexys A7 onboard DB15 VGA DAC)
## =========================================================================
set_property -dict {PACKAGE_PIN A3 IOSTANDARD LVCMOS33} [get_ports {vga_r[0]}]
set_property -dict {PACKAGE_PIN B4 IOSTANDARD LVCMOS33} [get_ports {vga_r[1]}]
set_property -dict {PACKAGE_PIN C5 IOSTANDARD LVCMOS33} [get_ports {vga_r[2]}]
set_property -dict {PACKAGE_PIN A4 IOSTANDARD LVCMOS33} [get_ports {vga_r[3]}]

set_property -dict {PACKAGE_PIN C6 IOSTANDARD LVCMOS33} [get_ports {vga_g[0]}]
set_property -dict {PACKAGE_PIN A5 IOSTANDARD LVCMOS33} [get_ports {vga_g[1]}]
set_property -dict {PACKAGE_PIN B6 IOSTANDARD LVCMOS33} [get_ports {vga_g[2]}]
set_property -dict {PACKAGE_PIN A6 IOSTANDARD LVCMOS33} [get_ports {vga_g[3]}]

set_property -dict {PACKAGE_PIN B7 IOSTANDARD LVCMOS33} [get_ports {vga_b[0]}]
set_property -dict {PACKAGE_PIN C7 IOSTANDARD LVCMOS33} [get_ports {vga_b[1]}]
set_property -dict {PACKAGE_PIN D7 IOSTANDARD LVCMOS33} [get_ports {vga_b[2]}]
set_property -dict {PACKAGE_PIN D8 IOSTANDARD LVCMOS33} [get_ports {vga_b[3]}]

set_property -dict {PACKAGE_PIN B11 IOSTANDARD LVCMOS33} [get_ports vga_hs]
set_property -dict {PACKAGE_PIN B12 IOSTANDARD LVCMOS33} [get_ports vga_vs]