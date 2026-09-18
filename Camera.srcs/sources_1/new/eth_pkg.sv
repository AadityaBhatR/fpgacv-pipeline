// =============================================================================
// eth_pkg
//
// Shared constants for the Ethernet MAC / IPv4 / UDP stack -- define these
// as SystemVerilog parameters/localparams (or a `package ... endpackage`)
// once you're ready to wire modules together.
//
// You'll need at least:
//   - Your FPGA's MAC address. Use a locally-administered address (the
//     second-least-significant bit of the first octet set to 1, e.g.
//     02:xx:xx:xx:xx:xx) so it can never collide with a real vendor OUI.
//   - FPGA_IP / HOST_IP -- a private subnet you configure statically on
//     the PC's NIC (there's no DHCP server on a direct FPGA<->PC link).
//   - HOST_MAC -- hardcode your PC NIC's real MAC (`ipconfig /all` on
//     Windows) for milestones 2-3. Once you build the ARP responder
//     (milestone 5), this gets learned dynamically instead.
//   - EtherType constants: 16'h88B5 (experimental, milestone 2's sanity
//     frame), 16'h0800 (IPv4), 16'h0806 (ARP).
//   - IP protocol number for UDP: 8'h11 (17).
//   - UDP port numbers for video/audio/telemetry/return traffic.
//   - Ethernet's minimum payload length (46 bytes) and minimum interpacket
//     gap (12 byte-times), used by eth_mac_tx's padding/IFG logic.
// =============================================================================

