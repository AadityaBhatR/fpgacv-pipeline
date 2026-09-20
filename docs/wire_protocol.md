# FPGA <-> Host Wire Protocol

This is the contract both sides of the Ethernet link build against. The FPGA
side (Ethernet TX/RX modules in `Camera.srcs/sources_1/new/eth/`) and the PC
side (`host/`) must agree on this exactly, since neither can infer the
other's framing from the raw bytes alone.

All multi-byte integer fields are **big-endian** (network byte order),
matching the IP/UDP headers they sit inside.

## Ports

| Port | Direction | Contents |
|---|---|---|
| 5001 | FPGA -> PC | Video frame chunks |
| 5002 | FPGA -> PC | Audio (microphone) stream |
| 5003 | FPGA -> PC | Telemetry / status |
| 5004 | PC -> FPGA | Return channel: TTS audio + command opcodes |

## Why video is chunked and periodic, audio is continuous

A QVGA (320x240) frame at the framebuffer's native 12-bit RGB444 packing is
320*240*12/8 = **115,200 bytes** -- roughly 80x too large for one Ethernet
frame (max ~1472 bytes of UDP payload before fragmentation). Video is also
the input to the VLM, which only needs a scene snapshot every few seconds,
not a real-time stream. So: video is split into chunks and sent as an
infrequent burst (default every 3s, configurable), while audio -- the
continuously-listened-to input -- streams in small fixed-size packets sent
every 20ms, the whole time the system is running (not gated on any command).

## Video (port 5001)

One frame = many packets, each with a small header identifying which frame
and which chunk this is, since UDP packets can in principle arrive out of
order (even though on a direct point-to-point cable this is unlikely, the
header costs 9 bytes and removes the assumption entirely).

```
byte 0     : 0x01 (packet type: video chunk)
byte 1-4   : frame_id       (uint32, increments once per frame, wraps)
byte 5-6   : chunk_index    (uint16, 0-based)
byte 7-8   : total_chunks   (uint16, for this frame_id)
byte 9-10  : width          (uint16, pixels, e.g. 320)
byte 11-12 : height         (uint16, pixels, e.g. 240)
byte 13    : format         (0x00 = RGB444 packed 12bpp, one nibble pad per
                              pixel expanded to a byte pair -- see below)
byte 14..  : chunk payload  (raw framebuffer bytes for this chunk)
```

`width`/`height`/`format` are repeated on every chunk (a few bytes of
redundancy) rather than only the first, so the host can reassemble a frame
correctly even if it missed chunk 0.

**Pixel format**: the framebuffer stores 12 bits/pixel (4 bits per R/G/B
channel). Pack two pixels into 3 bytes (standard 12bpp packing:
`[RRRRGGGG] [BBBBRRRR] [GGGGBBBB]`) rather than padding each 12-bit pixel
into 2 bytes -- halves the data volume, at the cost of the host needing to
unpack it (a few lines of NumPy, not meaningfully harder).

Frame byte count: 320*240*12/8 = 115200 bytes. At 1400 bytes of chunk
payload each, that's 83 chunks/frame -- comfortably under the uint16
`total_chunks` limit, and 83 packets at 100 Mbps is on the order of 10ms to
transmit, negligible next to the multi-second interval between frames.

**Host reassembly rule**: buffer chunks by `frame_id`; once
`chunks_received == total_chunks` for that frame_id, decode it; if a new
`frame_id` starts arriving before the previous one completed, discard the
incomplete one (don't accumulate stale partial frames indefinitely).

## Audio: microphone stream (port 5002)

16 kHz, 16-bit signed PCM, mono (matches the CIC decimation filter output
in the README's audio pipeline). Sent in fixed 20ms frames -- 320 samples,
640 bytes -- a conventional real-time-audio chunk size (same order as VoIP
framing) that's small enough to keep mic-to-STT latency low.

```
byte 0    : 0x02 (packet type: mic audio)
byte 1-4  : seq_num      (uint32, increments once per packet, wraps)
byte 5..  : PCM payload  (640 bytes = 320 x int16, little-endian samples --
                           note: sample data itself is little-endian even
                           though the header fields are big-endian; this
                           matches what faster-whisper/most audio libraries
                           expect directly, no re-endianing needed)
```

No frame-boundary metadata needed beyond `seq_num` (used only to detect
drops/gaps, not to reassemble -- each packet already IS one complete,
independent 20ms audio frame).

## Telemetry (port 5003, FPGA -> PC)

Low-rate status/health, useful for debugging and for the host orchestrator
to show link state. Sent periodically (e.g. once per second) or on change.

```
byte 0   : 0x03 (packet type: telemetry)
byte 1   : status_flags (bit0 = camera locked, bit1 = mic active, ...)
byte 2-3 : uptime_seconds (uint16)
```

Deliberately minimal for now -- extend as real status signals exist.

## Return channel (port 5004, PC -> FPGA)

Two kinds of data share this port, distinguished by a type byte, since both
originate from the same host-side response cycle (one LLM turn produces
both a spoken reply and, optionally, a command) and both need to reach the
FPGA close together in time.

**TTS audio (Piper output), for playback through the FPGA's DAC:**
```
byte 0    : 0x10 (packet type: TTS audio chunk)
byte 1-4  : utterance_id (uint32, increments once per spoken reply)
byte 5-6  : chunk_index  (uint16)
byte 7-8  : total_chunks (uint16)
byte 9..  : PCM payload  (16-bit signed samples, sample rate matching
                           Piper's configured voice -- en_US-lessac-medium
                           is 22050 Hz; resample to whatever rate the DAC
                           core expects if different)
```
Chunked the same way as video, for the same reason (one utterance's audio
is bigger than one UDP packet) -- reassembly rule is the same pattern too,
except the FPGA side needs to START PLAYING before the full utterance has
arrived (audio has to be streamed to the DAC in real time, not decoded as
one blob), so the FPGA's receiver should feed chunks to the DAC as they
arrive, in `chunk_index` order, rather than buffering the whole utterance.

**Command opcodes:**
```
byte 0   : 0x20 (packet type: command)
byte 1   : opcode        (see opcode table below)
byte 2-5 : arg           (uint32, meaning depends on opcode)
```

### Opcode table (v1 -- extend as real commands exist)

| Opcode | Name | `arg` meaning | FPGA action |
|---|---|---|---|
| 0x00 | NOP | ignored | no-op, for keepalive/testing |
| 0x01 | SET_LED | bit N of arg = LED N on/off (16 LEDs used) | drive `leds` register directly from `arg[15:0]` |
| 0x02 | SET_SERVO_PAN | arg = target angle, 0-180, as arg[7:0] | (once pan/tilt servos exist) set PWM duty cycle |
| 0x03 | SET_SERVO_TILT | same as above | same |
| 0x04 | CLEAR_MEMORY | ignored | pulse a status LED pattern acknowledging a memory-clear voice command (purely cosmetic feedback; the actual memory file lives host-side) |

This table is intentionally short -- see the FPGA command-receiver module
(`eth/cmd_rx.sv`) for how new opcodes get added without changing the wire
format.
