// =============================================================================
// eth_mac_tx
//
// Serializes one Ethernet frame at a time onto the RMII tx pins. The caller
// (udp_tx_packetizer for real traffic, or a trivial testbench driver for
// milestone 2's hardcoded sanity frame) streams payload bytes in via a
// ready/valid handshake; this module wraps them with preamble/SFD/addresses/
// EtherType/FCS/IFG.
//
// Clock domain: this whole module runs on the 50 MHz eth_ref_clk domain (the
// same clock you drive out to the PHY). 1 byte = 4 clocks (RMII sends 2 bits
// per clock), so payload_ready only needs to pulse once every 4 clocks.
//
// Suggested FSM states:
//
//   IDLE       -- wait for tx_start pulse. Latch dest_mac/ethertype/length.
//                 Pulse crc_init to eth_crc32.
//   PREAMBLE   -- drive 7 bytes of 8'h55 onto txd (LSB-pair-of-byte first,
//                 i.e. txd <= byte[1:0] then byte[3:2] then byte[5:4] then
//                 byte[7:6], 4 clocks per byte). tx_en = 1 throughout.
//   SFD        -- drive one byte 8'hD5.
//   DEST_MAC   -- drive dest_mac, 6 bytes, MSB byte of the address first.
//                 Feed each byte to eth_crc32 (data_valid pulse, one byte
//                 per 4 clocks) -- CRC coverage starts here, NOT at preamble.
//   SRC_MAC    -- drive your own MAC address, 6 bytes. Feed CRC.
//   ETHERTYPE  -- drive the latched ethertype, 2 bytes, MSB first. Feed CRC.
//   PAYLOAD    -- assert payload_ready, consume payload_data whenever
//                 payload_valid = 1, drive it onto txd, feed CRC. Count
//                 bytes sent; if payload_last arrives before the 46-byte
//                 Ethernet minimum has been sent, keep driving zero bytes
//                 (still feeding CRC) until you hit the minimum -- real
//                 frames shorter than 46B must be zero-padded.
//   FCS        -- read crc_fcs from eth_crc32, drive its 4 bytes onto txd
//                 in LEAST-significant-byte-first order (reverse of the
//                 32-bit value's normal big-endian byte order). Do NOT feed
//                 these bytes back into the CRC engine.
//   IFG        -- deassert tx_en, hold idle for >= 12 byte-times (48
//                 clocks), then return to IDLE and clear busy.
//
// Keep `busy` asserted from tx_start until IFG completes, so callers know
// not to issue another tx_start mid-frame.
//
// Suggested ports (design your own):
//   clk, rst                                   -- 50 MHz eth_ref_clk domain
//   tx_start, dest_mac[47:0], ethertype[15:0], busy
//   payload_data[7:0], payload_valid, payload_last, payload_ready
//   rmii_txd[1:0], rmii_tx_en
// =============================================================================
