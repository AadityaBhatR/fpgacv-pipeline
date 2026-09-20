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
// same clock you drive out to the PHY). 1 byte = 4 clocks, because RMII only
// moves 2 bits per clock (txd[1:0]) -- so payload_ready only needs to pulse
// once every 4 clocks, not every clock.
//
// -----------------------------------------------------------------------
// Frame layout (this is what you're building, field by field)
// -----------------------------------------------------------------------
//   Field       Bytes   Content
//   ---------   -----   -------------------------------------------------
//   PREAMBLE      7     8'h55, repeated
//   SFD           1     8'hD5
//   DEST_MAC      6     dest_mac[47:40], [39:32], [31:24], [23:16],
//                       [15:8], [7:0]   (MSB byte first)
//   SRC_MAC       6     your own FPGA_MAC, same MSB-byte-first order
//   ETHERTYPE     2     ethertype[15:8], then ethertype[7:0]
//   PAYLOAD      >=46   passthrough bytes from the caller; zero-pad if the
//                       caller supplies fewer than 46 bytes total
//   FCS           4     crc_out[7:0], crc_out[15:8], crc_out[23:16],
//                       crc_out[31:24]  (LEAST-significant BYTE first --
//                       this is the opposite byte order from every other
//                       multi-byte field above)
//
// CRC coverage: eth_crc32's data_valid pulses must cover DEST_MAC through
// PAYLOAD (14 + payload_length bytes) -- NOT preamble/SFD, and NOT the FCS
// bytes themselves. Use eth_crc32's `crc_out` port (the already-inverted
// value) directly as your 4 FCS bytes -- don't invert it again.
//
// Minimum frame duration (excluding IFG), for sizing testbench timeouts:
// 7+1+6+6+2+46+4 = 72 bytes = 288 clocks @ 50 MHz = 5.76 us.
//
// Known limitation: PAYLOAD has no backpressure/stall support -- whatever
// is on payload_data must be valid the same cycle payload_ready is high.
// Fine for a testbench driver or a packetizer reading out of a buffer;
// would need reworking for a source that can't guarantee that.
//
// Suggested ports (design your own):
//   clk, rst                                   -- 50 MHz eth_ref_clk domain
//   tx_start, dest_mac[47:0], ethertype[15:0], busy
//   payload_data[7:0], payload_valid, payload_last, payload_ready
//   rmii_txd[1:0], rmii_tx_en
// =============================================================================

module eth_mac_tx(
    input  logic clk, rst,
    input  logic tx_start,
    input  logic [47:0] dest_mac,
    input  logic [47:0] src_mac,
    input  logic [15:0] ethertype,
    output logic busy,

    input  logic [7:0] payload_data,
    input  logic payload_valid,
    input  logic payload_last,
    output logic payload_ready,

    output logic [1:0] rmii_txd,
    output logic rmii_tx_en
);

    typedef enum {IDLE, PREAMBLE, SFD, DEST_MAC, SRC_MAC, ETHERTYPE, PAYLOAD, FCS, IFG} state_t;
    state_t current_state, next_state;

    localparam logic [7:0] preamble = 8'h55;
    localparam logic [7:0] sfd      = 8'hD5;

    // field lengths in dibit-clocks (1 byte = 4 clocks)
    localparam int k_preamble        = 7*4;
    localparam int k_sfd             = 1*4;
    localparam int k_addr            = 6*4;
    localparam int k_ethertype       = 2*4;
    localparam int k_fcs             = 4*4;
    localparam int k_ifg             = 12*4;
    localparam int MIN_PAYLOAD_BYTES = 46;

    int cnt_data;
    logic [2:0] byte_idx;
    logic [1:0] dibit_idx;
    assign byte_idx  = cnt_data[4:2];
    assign dibit_idx = cnt_data[1:0];

    logic [47:0] dest_mac_lat, src_mac_lat;
    logic [15:0] ethertype_lat;

    int payload_byte_cnt;
    logic [7:0] payload_byte_lat;
    logic payload_ended;

    logic [7:0] cur_byte;
    logic [1:0] cur_data;
    logic tx_en_comb;

    logic crc_init, crc_valid;
    logic [7:0] crc_din;
    logic [31:0] crc_out;

    eth_crc32 u_crc (
        .clk(clk),
        .rst(~rst),          // eth_crc32 is active-low/async, we're active-high/sync
        .crc_init(crc_init),
        .data_valid(crc_valid),
        .data_in(crc_din),
        .crc_out(crc_out)
    );

    assign busy = (current_state != IDLE);

    always_ff @(posedge clk) begin
        if (rst) begin
            current_state    <= IDLE;
            cnt_data         <= 0;
            dest_mac_lat     <= '0;
            src_mac_lat      <= '0;
            ethertype_lat    <= '0;
            payload_byte_cnt <= 0;
            payload_byte_lat <= 8'h00;
            payload_ended    <= 1'b0;
            rmii_txd         <= 2'b00;
            rmii_tx_en       <= 1'b0;
        end
        else begin
            current_state <= next_state;

            // per-field dibit counter
            if (next_state != current_state)
                cnt_data <= 0;
            else
                cnt_data <= cnt_data + 1;

            // latch header fields once, when a new frame is accepted
            if (current_state == IDLE && tx_start) begin
                dest_mac_lat  <= dest_mac;
                src_mac_lat   <= src_mac;
                ethertype_lat <= ethertype;
            end

            if (next_state == PAYLOAD && current_state != PAYLOAD) begin
                payload_byte_cnt <= 0;
                payload_ended    <= 1'b0;
            end
            else if (current_state == PAYLOAD) begin
                // cut-through: latch the byte the same cycle it's accepted.
                // once ended, keep re-latching zero each byte for padding --
                // payload_ended must NOT affect the byte already in flight
                // (that's handled by the dibit_idx != 0 hold path below).
                if (dibit_idx == 2'd0) begin
                    if (!payload_ended && payload_valid) begin
                        payload_byte_lat <= payload_data;
                        if (payload_last)
                            payload_ended <= 1'b1;
                    end
                    else if (payload_ended) begin
                        payload_byte_lat <= 8'h00;
                    end
                end
                if (dibit_idx == 2'd3)
                    payload_byte_cnt <= payload_byte_cnt + 1;
            end

            // registered pin outputs (lets synthesis pack these into IOB flops)
            rmii_txd   <= cur_data;
            rmii_tx_en <= tx_en_comb;
        end
    end

    always_comb begin
        next_state    = current_state;
        cur_byte      = 8'h00;
        tx_en_comb    = 1'b1;
        crc_init      = 1'b0;
        crc_valid     = 1'b0;
        crc_din       = 8'h00;
        payload_ready = 1'b0;

        case (current_state)
            IDLE: begin
                tx_en_comb = 1'b0;
                if (tx_start) begin
                    next_state = PREAMBLE;
                    crc_init   = 1'b1;
                end
            end

            PREAMBLE: begin
                cur_byte = preamble;
                if (cnt_data == k_preamble - 1)
                    next_state = SFD;
            end

            SFD: begin
                cur_byte = sfd;
                if (cnt_data == k_sfd - 1)
                    next_state = DEST_MAC;
            end

            DEST_MAC: begin
                cur_byte = dest_mac_lat[8*(5-byte_idx) +: 8];
                if (dibit_idx == 2'd3) begin
                    crc_valid = 1'b1;
                    crc_din   = cur_byte;
                end
                if (cnt_data == k_addr - 1)
                    next_state = SRC_MAC;
            end

            SRC_MAC: begin
                cur_byte = src_mac_lat[8*(5-byte_idx) +: 8];
                if (dibit_idx == 2'd3) begin
                    crc_valid = 1'b1;
                    crc_din   = cur_byte;
                end
                if (cnt_data == k_addr - 1)
                    next_state = ETHERTYPE;
            end

            ETHERTYPE: begin
                cur_byte = ethertype_lat[8*(1-byte_idx) +: 8];
                if (dibit_idx == 2'd3) begin
                    crc_valid = 1'b1;
                    crc_din   = cur_byte;
                end
                if (cnt_data == k_ethertype - 1)
                    next_state = PAYLOAD;
            end

            PAYLOAD: begin
                // dibit 0 of a byte: either grab a new real byte, or output
                // zero for padding. dibits 1-3: just hold whatever byte we
                // latched at dibit 0, regardless of payload_ended -- this
                // must not get short-circuited once the last byte arrives.
                if (dibit_idx == 2'd0) begin
                    payload_ready = !payload_ended;
                    cur_byte = (!payload_ended && payload_valid) ? payload_data : 8'h00;
                end
                else begin
                    cur_byte = payload_byte_lat;
                end

                if (dibit_idx == 2'd3) begin
                    crc_valid = 1'b1;
                    crc_din   = cur_byte;
                    if (payload_ended && (payload_byte_cnt + 1 >= MIN_PAYLOAD_BYTES))
                        next_state = FCS;
                end
            end

            FCS: begin
                cur_byte = crc_out[8*byte_idx +: 8]; // byte_idx 0..3 -> LSB byte first
                if (cnt_data == k_fcs - 1)
                    next_state = IFG;
            end

            IFG: begin
                tx_en_comb = 1'b0;
                if (cnt_data == k_ifg - 1)
                    next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase

        // shared nibble slicer: 2 bits/clock, LSB pair of the byte first
        cur_data = cur_byte[dibit_idx*2 +: 2];
    end

endmodule
