// =============================================================================
// eth_pkg
//
// Shared constants for the Ethernet/IPv4/UDP stack. eth_mac_tx does NOT use
// this -- its dest_mac/src_mac/ethertype are plain ports, and its 802.3
// timing constants (min payload, IFG) are self-contained localparams, since
// those never change. This package is for what actually needs to be shared
// across modules: link addressing and protocol numbers, used by
// udp_tx_packetizer, the future ARP responder, and top-level integration.
// =============================================================================

package eth_pkg;

    // Locally-administered MAC (the "02" first octet) so it can never
    // collide with a real vendor's silicon.
    localparam logic [47:0] FPGA_MAC = 48'h02_00_00_00_00_01;

    // Private link addressing. FPGA_IP is whatever you configure the FPGA
    // side to use; HOST_IP must match the static IP you manually assign to
    // the PC's Ethernet adapter (no DHCP server on a direct link).
    localparam logic [31:0] FPGA_IP = 32'hC0_A8_01_64; // 192.168.1.100
    localparam logic [31:0] HOST_IP = 32'hC0_A8_01_01; // 192.168.1.1

    localparam logic [47:0] HOST_MAC = 48'h3C_EF_A5_06_AF_4C;

    localparam logic [15:0] ETHERTYPE_TEST = 16'h88B5; // milestone 2 sanity frame
    localparam logic [15:0] ETHERTYPE_IPV4 = 16'h0800;
    localparam logic [15:0] ETHERTYPE_ARP  = 16'h0806;

    localparam logic [7:0] IPPROTO_UDP = 8'h11; // 17, IANA-assigned

    localparam logic [15:0] UDP_PORT_VIDEO     = 16'd5001;
    localparam logic [15:0] UDP_PORT_AUDIO     = 16'd5002;
    localparam logic [15:0] UDP_PORT_TELEMETRY = 16'd5003;
    localparam logic [15:0] UDP_PORT_RETURN    = 16'd5004;

endpackage
