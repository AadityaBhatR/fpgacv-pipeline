// =============================================================================
// udp_tx_packetizer
//
// Wraps a caller's payload in IPv4 + UDP headers and drives an internally-
// instantiated eth_mac_tx (same encapsulation pattern eth_mac_rx uses for
// eth_crc32) -- callers just get "send this many bytes to this port" plus
// raw RMII pins out, they never touch eth_mac_tx directly.
//
// dest_mac/src_mac/ethertype are fixed (HOST_MAC/FPGA_MAC/IPV4 from
// eth_pkg), since every UDP datagram this module sends uses the same ones.
//
// IPv4 header checksum is NOT optional -- get it wrong and real network
// stacks drop the packet. The UDP checksum IS allowed to be 0x0000
// (disabled) over IPv4, which is what this does.
//
// Frame layout streamed into eth_mac_tx's payload interface:
//   IP_HDR (20B):
//     byte 0    : 8'h45              (version=4, IHL=5)
//     byte 1    : 8'h00              (DSCP/ECN)
//     byte 2-3  : ip_total_length     (= 28 + payload_length, MSB first)
//     byte 4-5  : identification      (free-running counter, MSB first)
//     byte 6-7  : 8'h40 8'h00         (flags=DF, no fragment)
//     byte 8    : 8'h40               (TTL = 64)
//     byte 9    : 8'h11               (protocol = UDP)
//     byte 10-11: ip_checksum          (MSB first)
//     byte 12-15: FPGA_IP (MSB first)
//     byte 16-19: HOST_IP (MSB first)
//   UDP_HDR (8B):
//     byte 0-1  : src_port  (MSB first)
//     byte 2-3  : dest_port (MSB first)
//     byte 4-5  : udp_length (= 8 + payload_length, MSB first)
//     byte 6-7  : 8'h00 8'h00 (checksum disabled)
//   PAYLOAD: passthrough of app_payload_* (skipped entirely if
//     payload_length == 0, in which case UDP_HDR's last byte is also the
//     frame's last byte)
//
// IPv4 header checksum: 16-bit one's-complement sum of the ten 16-bit
// header words (checksum field = 0 while summing), folding any carry out
// above bit 15 back into the low 16 bits until it fits, then complemented.
// =============================================================================

module udp_tx_packetizer(
    input  logic clk, rst,

    input  logic send,
    input  logic [15:0] src_port,
    input  logic [15:0] dest_port,
    input  logic [15:0] payload_length,
    output logic busy,

    input  logic [7:0] app_payload_data,
    input  logic app_payload_valid,
    input  logic app_payload_last,
    output logic app_payload_ready,

    output logic [1:0] rmii_txd,
    output logic rmii_tx_en
);



    typedef enum {IDLE, IP_HDR, UDP_HDR, PAYLOAD, DONE} state_t;
    state_t current_state, next_state;

    // ---- live checksum/length computation from current inputs ----
    logic [15:0] identification;
    logic [15:0] ip_total_length_live, udp_length_live;
    assign ip_total_length_live = 16'd28 + payload_length;
    assign udp_length_live      = 16'd8  + payload_length;

    // Sum of 9 16-bit words (checksum field itself = 0), max value
    // 9*16'hFFFF fits comfortably in 20 bits -- widened to 32 here just so
    // none of the additions below can truncate.
    logic [31:0] chk_sum;
    assign chk_sum = 32'h4500 + {16'h0, ip_total_length_live} + {16'h0, identification}
                   + 32'h4000 + 32'h4011
                   + {16'h0, eth_pkg::FPGA_IP[31:16]} + {16'h0, eth_pkg::FPGA_IP[15:0]}
                   + {16'h0, eth_pkg::HOST_IP[31:16]} + {16'h0, eth_pkg::HOST_IP[15:0]};

    // Exactly two fixed fold stages -- no data-dependent loop, so this
    // synthesizes cleanly. Provably sufficient for 9 words: the carry-out
    // of summing 9 16-bit values is at most 8, so folding it into the low
    // 16 bits can produce at most a further 1-bit carry-out, and folding
    // THAT can never itself carry again (if it did, the low 16 bits after
    // fold 1 would have to be <= 7, nowhere near overflowing when +1).
    logic [31:0] chk_fold1;
    logic [15:0] ip_checksum_live;
    assign chk_fold1        = {16'h0, chk_sum[15:0]} + {16'h0, chk_sum[31:16]};
    assign ip_checksum_live = ~(chk_fold1[15:0] + chk_fold1[31:16]);

    // ---- latched at the moment `send` is accepted, held stable for the
    //      whole frame regardless of what the input ports do afterward ----
    logic [15:0] src_port_lat, dest_port_lat, payload_length_lat;
    logic [15:0] ip_total_length_lat, udp_length_lat, ip_checksum_lat, id_lat;

    logic [4:0] byte_idx;

    // ---- header byte mux ----
    logic [7:0] hdr_byte;
    always_comb begin
        hdr_byte = 8'h00;
        case (current_state)
            IP_HDR: case (byte_idx)
                5'd0:  hdr_byte = 8'h45;
                5'd1:  hdr_byte = 8'h00;
                5'd2:  hdr_byte = ip_total_length_lat[15:8];
                5'd3:  hdr_byte = ip_total_length_lat[7:0];
                5'd4:  hdr_byte = id_lat[15:8];
                5'd5:  hdr_byte = id_lat[7:0];
                5'd6:  hdr_byte = 8'h40;
                5'd7:  hdr_byte = 8'h00;
                5'd8:  hdr_byte = 8'h40;
                5'd9:  hdr_byte = 8'h11;
                5'd10: hdr_byte = ip_checksum_lat[15:8];
                5'd11: hdr_byte = ip_checksum_lat[7:0];
                5'd12: hdr_byte = eth_pkg::FPGA_IP[31:24];
                5'd13: hdr_byte = eth_pkg::FPGA_IP[23:16];
                5'd14: hdr_byte = eth_pkg::FPGA_IP[15:8];
                5'd15: hdr_byte = eth_pkg::FPGA_IP[7:0];
                5'd16: hdr_byte = eth_pkg::HOST_IP[31:24];
                5'd17: hdr_byte = eth_pkg::HOST_IP[23:16];
                5'd18: hdr_byte = eth_pkg::HOST_IP[15:8];
                5'd19: hdr_byte = eth_pkg::HOST_IP[7:0];
                default: hdr_byte = 8'h00;
            endcase
            UDP_HDR: case (byte_idx)
                5'd0: hdr_byte = src_port_lat[15:8];
                5'd1: hdr_byte = src_port_lat[7:0];
                5'd2: hdr_byte = dest_port_lat[15:8];
                5'd3: hdr_byte = dest_port_lat[7:0];
                5'd4: hdr_byte = udp_length_lat[15:8];
                5'd5: hdr_byte = udp_length_lat[7:0];
                5'd6: hdr_byte = 8'h00;
                5'd7: hdr_byte = 8'h00;
                default: hdr_byte = 8'h00;
            endcase
            default: hdr_byte = 8'h00;
        endcase
    end

    // ---- eth_mac_tx instance ----
    logic mac_tx_start, mac_busy;
    logic [7:0] mac_payload_data;
    logic mac_payload_valid, mac_payload_last, mac_payload_ready;

    // Factored out of the state-transition `if`s below rather than written
    // inline as `if (mac_payload_ready && byte_idx == N) next_state = ...` --
    // that inline form reliably hangs this project's Icarus build (a real,
    // reproducible simulator bug, isolated with a minimal repro: referencing
    // an instantiated submodule's output directly inside a condition that
    // assigns a 3+-state enum `next_state` never terminates, even though the
    // exact same pattern is fine in eth_mac_tx/eth_mac_rx). Functionally
    // identical, just computed as its own signal first.
    logic ip_hdr_last_byte, udp_hdr_last_byte, payload_final_byte;
    assign ip_hdr_last_byte   = mac_payload_ready && (byte_idx == 5'd19);
    assign udp_hdr_last_byte  = mac_payload_ready && (byte_idx == 5'd7);
    assign payload_final_byte = mac_payload_ready && app_payload_valid && app_payload_last;
    logic mac_done;
    assign mac_done = !mac_busy;

    eth_mac_tx u_mac (
        .clk(clk), .rst(rst),
        .tx_start(mac_tx_start),
        .dest_mac(eth_pkg::HOST_MAC),
        .src_mac(eth_pkg::FPGA_MAC),
        .ethertype(eth_pkg::ETHERTYPE_IPV4),
        .busy(mac_busy),
        .payload_data(mac_payload_data),
        .payload_valid(mac_payload_valid),
        .payload_last(mac_payload_last),
        .payload_ready(mac_payload_ready),
        .rmii_txd(rmii_txd),
        .rmii_tx_en(rmii_tx_en)
    );

    assign busy = (current_state != IDLE);

    // Deliberately a top-level continuous assign, NOT set inside the
    // procedural always_comb below. Assigning a submodule output straight
    // through to this module's own output port from inside a `case` branch
    // of a procedural block reliably hangs this project's Icarus build (a
    // real, reproducible simulator bug, isolated with a minimal repro) --
    // moving the identical logic to a continuous assign avoids it entirely.
    assign app_payload_ready = (current_state == PAYLOAD) ? mac_payload_ready : 1'b0;

    // Split into separate always_ff blocks (state/byte_idx vs. the
    // send-accept latch/identification counter) rather than one combined
    // block -- combining them reliably double-fired the identification
    // increment for a single send pulse under this project's Icarus build
    // (a real, reproducible simulator bug found while testing).
    always_ff @(posedge clk) begin
        if (rst) begin
            current_state <= IDLE;
            byte_idx      <= 5'd0;
        end
        else begin
            current_state <= next_state;

            if (next_state != current_state)
                byte_idx <= 5'd0;
            else if ((current_state == IP_HDR || current_state == UDP_HDR) && mac_payload_ready)
                byte_idx <= byte_idx + 5'd1;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            identification <= 16'h0000;
        end
        else if (current_state == IDLE && send) begin
            src_port_lat         <= src_port;
            dest_port_lat        <= dest_port;
            payload_length_lat   <= payload_length;
            ip_total_length_lat  <= ip_total_length_live;
            udp_length_lat       <= udp_length_live;
            ip_checksum_lat      <= ip_checksum_live;
            id_lat               <= identification;
            identification       <= identification + 16'h1;
        end
    end

    always_comb begin
        next_state        = current_state;
        mac_tx_start       = 1'b0;
        mac_payload_data   = 8'h00;
        mac_payload_valid  = 1'b0;
        mac_payload_last   = 1'b0;

        case (current_state)
            IDLE: begin
                if (send) begin
                    next_state  = IP_HDR;
                    mac_tx_start = 1'b1;
                end
            end

            IP_HDR: begin
                mac_payload_data  = hdr_byte;
                mac_payload_valid = 1'b1;
                if (ip_hdr_last_byte)
                    next_state = UDP_HDR;
            end

            UDP_HDR: begin
                mac_payload_data  = hdr_byte;
                mac_payload_valid = 1'b1;
                if (udp_hdr_last_byte) begin
                    if (payload_length_lat == 16'd0) begin
                        mac_payload_last = 1'b1; // no payload: UDP header ends the frame
                        next_state       = DONE;
                    end
                    else begin
                        next_state = PAYLOAD;
                    end
                end
            end

            PAYLOAD: begin
                mac_payload_data  = app_payload_data;
                mac_payload_valid = app_payload_valid;
                mac_payload_last  = app_payload_last;
                if (payload_final_byte)
                    next_state = DONE;
            end

            DONE: begin
                if (mac_done)
                    next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

endmodule
