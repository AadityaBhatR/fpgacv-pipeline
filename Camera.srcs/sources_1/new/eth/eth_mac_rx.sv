// =============================================================================
// eth_mac_rx
//
// Milestone 4 module -- build this AFTER milestones 0-3 (TX path) work and
// you've seen real frames land in Wireshark. Deserializes RMII rx pins back
// into bytes, strips preamble/SFD, and hands off dest-MAC-through-payload
// bytes with a running CRC check.
//
// Suggested FSM states:
//
//   IDLE      -- wait for rmii_crs_dv = 1. Reset nibble/byte counters.
//   PREAMBLE  -- accumulate 2 bits/clock into bytes (first nibble received
//                is the LOW bits of the byte, matching the tx bit order).
//                Discard bytes while they read 8'h55. This is also where
//                real hardware often loses lock for a nibble or two --
//                don't assume a fixed preamble length, just look for SFD.
//   SFD       -- once a byte reads 8'hD5, the NEXT byte is the first real
//                frame byte (start of dest MAC). Pulse crc_init here.
//   FRAME     -- for every subsequent byte, feed it to eth_crc32 and to
//                rx_byte/rx_byte_valid. You don't know a byte is real
//                payload vs. part of the trailing FCS until the frame
//                ends -- see the EOF note below for how to handle that.
//   EOF       -- rmii_crs_dv deasserts. Checking the CRC: the classic trick
//                is to feed the FCS bytes into the CRC engine too (don't
//                exclude them) -- a valid frame's *final* crc_reg then
//                equals a fixed magic constant, 32'hC704DD7B. That avoids
//                needing a delay-line to separate payload from FCS for the
//                CRC check itself. Confirm this against a reference before
//                relying on it. You still need SOME delay line (e.g. 4
//                bytes deep) if you want rx_byte_valid to only fire for
//                real payload bytes (excluding the FCS), since you don't
//                know a byte belongs to the FCS until the frame already
//                ended.
//
// Pulse rx_sof on the first FRAME-state byte (start of dest MAC) and rx_eof
// (with rx_crc_ok reflecting the check above) when crs_dv deasserts.
//
// Suggested ports (design your own):
//   clk, rst                                   -- 50 MHz eth_ref_clk domain
//   rmii_crs_dv, rmii_rxd[1:0]
//   rx_byte[7:0], rx_byte_valid, rx_sof, rx_eof, rx_crc_ok
// =============================================================================
