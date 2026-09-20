// =============================================================================
// udp_tx_packetizer
//
// Sits between an application payload source (a fixed test string for
// milestone 3; later, the video/audio/telemetry sources) and eth_mac_tx.
// Generates the 20B IPv4 header + 8B UDP header, then passes the caller's
// payload bytes straight through, and drives eth_mac_tx's payload interface.
//
// Unlike the Ethernet FCS, the IPv4 header checksum is NOT optional --
// get it wrong and real network stacks (Windows/Linux/Wireshark) will
// flag/drop the packet. The UDP checksum, by contrast, is allowed to be
// 16'h0000 (disabled) over IPv4 -- leave it 0 for now.
//
// Suggested FSM states:
//
//   IDLE       -- wait for `send`. Latch dest_port and payload_length.
//                 Compute ip_total_length = 20 (IP hdr) + 8 (UDP hdr)
//                                            + payload_length.
//                 Compute udp_length      = 8 + payload_length.
//                 Call eth_mac_tx.tx_start with dest_mac = eth_pkg::HOST_MAC
//                 (hardcoded until milestone 5's ARP responder exists),
//                 src_mac = eth_pkg::FPGA_MAC (eth_mac_tx takes this as a
//                 port too, it's not baked in), and ethertype =
//                 eth_pkg::ETHERTYPE_IPV4.
//   IP_HDR     -- stream these 20 bytes to eth_mac_tx's payload_data/valid,
//                 MSB-first within each multi-byte field:
//                   byte 0    : 8'h45              (version=4, IHL=5)
//                   byte 1    : 8'h00              (DSCP/ECN)
//                   byte 2-3  : ip_total_length     (16-bit, MSB first)
//                   byte 4-5  : identification      (a free-running counter
//                                                     is fine, or 0)
//                   byte 6-7  : 8'h40 8'h00         (flags=DF, no fragment)
//                   byte 8    : 8'h40               (TTL = 64)
//                   byte 9    : 8'h11               (protocol = UDP)
//                   byte 10-11: header checksum      (compute below)
//                   byte 12-15: your FPGA's IP
//                   byte 16-19: the host PC's IP
//
//                 IPv4 header checksum algorithm (do this BEFORE you start
//                 streaming byte 10-11, e.g. combinationally/in IDLE):
//                   1. Treat the 20-byte header as ten 16-bit big-endian
//                      words, with the checksum field itself = 16'h0000.
//                   2. Sum all ten words in a wider accumulator (>16 bits).
//                   3. Fold: while the sum has bits above bit 15, add the
//                      overflow back into the low 16 bits (sum =
//                      sum[15:0] + sum[31:16], repeat until it fits in
//                      16 bits).
//                   4. checksum = ~sum[15:0].
//
//   UDP_HDR    -- stream 8 bytes:
//                   byte 0-1 : src_port  (MSB first)
//                   byte 2-3 : dest_port (MSB first)
//                   byte 4-5 : udp_length (MSB first)
//                   byte 6-7 : 8'h00 8'h00 (checksum disabled)
//   PAYLOAD    -- pass caller's app_payload_data/app_payload_valid straight
//                 through to eth_mac_tx.payload_data/payload_valid, forward
//                 app_payload_ready back from eth_mac_tx.payload_ready, and
//                 forward app_payload_last as eth_mac_tx's payload_last.
//   DONE       -- wait for eth_mac_tx.busy to fall, then clear `busy` here
//                 and return to IDLE.
//
// Suggested ports (design your own):
//   clk, rst
//   send, src_port[15:0], dest_port[15:0], payload_length[15:0], busy
//   app_payload_data[7:0], app_payload_valid, app_payload_last, app_payload_ready
//   mac_tx_start, mac_dest_mac[47:0], mac_ethertype[15:0], mac_busy
//   mac_payload_data[7:0], mac_payload_valid, mac_payload_last, mac_payload_ready
// =============================================================================
