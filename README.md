# FPGA-CV-LLM-Pipeline

Real-time FPGA computer vision ingest, dual-buffered video display pipeline, and multimodal edge AI acceleration interface built on the **Digilent Nexys A7-100T (Xilinx Artix-7 XC7A100T)** and the **OmniVision OV5640 5MP DVP Camera Module**.

---

## 📸 System Overview

```
 [OV5640 Camera] ──(DVP 8-bit @ 25MHz)──► [Camera_Capture]
                                                  │
                                                  ▼
                                      [Dual-Bank Ping-Pong BRAM]
                                       (153,600 x 12-bit RGB444)
                                                  │
                                                  ▼
                                           [VGA_Controller] ──► [VGA Monitor (640x480 @ 60Hz)]
                                                  ▲
 [Host PC / Python] ──(UART 921.6k Baud)──► [Camera_Setup] (SCCB/I2C Master)
```

### Key Hardware & Architecture Highlights:
- **Tear-Free Double Buffering**: Uses 153,600 words of Block RAM split into two 76,800-word banks (Bank 0 / Bank 1). While the camera writes into Bank $N$, the VGA display reads from Bank $1-N$. Bank switching occurs strictly during vertical blanking (`vga_pixel_y = 480`), completely eliminating frame tearing.
- **Physical Signal Integrity / 180° Sampling**: The camera launches DVP data on the rising edge of `PCLK`. The FPGA samples on the **falling edge** of `PCLK` (a 20 ns phase shift), landing directly in the center of the data eye to eliminate high-frequency bit jitter and noise.
- **Native $4\times$ Hardware Binning**: Uses OV5640 internal $4\times$ binning (`0x3814 = 0x71`, `0x3815 = 0x71`) to generate an undistorted $320\times 240$ RGB565 stream at 14 FPS, upscaled 2× to full-screen $640\times 480$ on the VGA display.
- **Auto Exposure Control (AEC) & Auto Gain Control (AGC)**: Fully enabled with calibrated indoor luminance targets (`0x3503 = 0x00`, `0x3A00 = 0x78`, `0x3A0F = 0x30`, `0x3A10 = 0x28`) to prevent white overexposure blowouts.
- **UART Live Register Control**: Python script (`camera_frame_viewer.py`) can stream new register configurations or tweak individual registers in real time at 921,600 baud without re-synthesizing the FPGA.

---

## 🎛️ On-Board Switch Controls

| Switch | State | Function |
| :---: | :---: | :--- |
| **SW0** | `0` = Camera Live, `1` = Test Pattern | Enables OV5640 hardware 8-color bar test pattern |
| **SW1** | `0` = Normal, `1` = Byte Swapped | RGB565 high/low byte order toggle |
| **SW2** | **`1` (UP)** | **HREF Polarity Invert** (Required for active-low camera timing) |
| **SW3** | `0` = Normal, `1` = Inverted | VSYNC Polarity Invert |
| **SW4** | **`0` (DOWN)** | **PCLK Sampling Edge** (`0` = Falling edge phase-aligned, `1` = Rising edge) |
| **SW5** | `0` = Landscape, `1` = Portrait | 90° Image Rotation Engine |
| **SW6** | `0` = Normal, `1` = Mirrored | Horizontal Mirror Flip |
| **SW7** | `0` = Normal, `1` = Inverted | Vertical Flip |

---

## 🔢 7-Segment Display Telemetry

The on-board 8-digit 7-segment display shows real-time system metrics:
- **Digits 7–6**: Measured `PCLK` frequency in MHz (`19` hex = ~25 MHz)
- **Digits 5–4**: Active line length / horizontal pixel count
- **Digits 3–2**: Active frame height / line count (`0F` hex = 240 lines / 16)
- **Digits 1–0**: Measured video frame rate (`0D`–`0E` hex = 13–14 FPS)

---

## 🛠️ Project Structure

```
├── Camera.srcs/
│   ├── sources_1/new/
│   │   ├── Top.vhd                 # Top-level entity integrating all modules
│   │   ├── Camera_Capture.vhd      # DVP byte assembler and BRAM write address generator
│   │   ├── Camera_Setup.vhd        # SCCB (I2C) master and UART live register loader
│   │   ├── Frame_Buffer_Memory.vhd # True dual-port ping-pong BRAM (153.6k x 12b)
│   │   ├── VGA_Controller.vhd      # 640x480 @ 60Hz timing generator
│   │   ├── Debug_Interface.vhd     # 7-segment telemetry & LED status monitor
│   │   ├── UART_Rx.vhd             # High-speed UART receiver (921,600 baud)
│   │   ├── UART_Frame_Tx.vhd       # Optional UART frame streaming transmitter
│   │   └── ov5640_config_pkg.vhd   # 146-register boot ROM table for OV5640
│   └── constrs_1/new/
│       └── constraint.xdc          # Nexys A7-100T master constraints (PMOD JB/JC, VGA, 7-seg)
├── Camera.xpr                      # Vivado Project File
├── build_bitstream.tcl             # Batch script to synthesize & implement design
├── program_fpga.tcl                # Batch script to program FPGA via Vivado Hardware Manager
├── camera_frame_viewer.py          # Python utility to reprogram camera registers via UART
├── .gitignore                      # Git ignore file for Vivado temporary build files
└── README.md                       # Project documentation
```

---

## 🚀 Getting Started

### 1. Build the Bitstream
Open a command prompt or terminal in the project directory and run:
```powershell
vivado -mode batch -nojournal -nolog -source build_bitstream.tcl
```

### 2. Program the FPGA
Ensure the Nexys A7 is connected via USB and turned on, then run:
```powershell
vivado -mode batch -nojournal -nolog -source program_fpga.tcl
```

### 3. (Optional) Reprogram Camera via Python
You can update registers on the fly over USB-UART:
```powershell
# Send baseline 320x240 RGB565 ROM
python camera_frame_viewer.py

# Enable color-bar test pattern
python camera_frame_viewer.py --test-pattern

# Write a single register (e.g. set 0x503D to 0x80)
python camera_frame_viewer.py --write-reg 0x503D 0x80
```
