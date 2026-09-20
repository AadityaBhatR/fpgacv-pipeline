// =============================================================================
// cmd_rx
//
// Decodes command packets on the return channel (docs/wire_protocol.md,
// port 5004, packet type 0x20) from eth_mac_rx's deframed byte stream, and
// drives outputs based on the opcode. This is the "v1: just sets outputs
// based on the commands given" module -- SET_LED is wired all the way to a
// real output; other opcodes are exposed generically (cmd_valid/opcode/arg)
// for future modules (servo PWM, DAC audio path) to consume without this
// module needing to know about them.
//
// Byte offsets counted from rx_sof (dest_mac byte 0), fixed since we don't
// support IP options (IHL always 5, 20-byte header) or variable-length
// fields before the payload:
//   0-5   dest_mac        6-11  src_mac         12-13 ethertype
//   14-33 IPv4 header (protocol is header byte 9 = overall byte 23)
//   34-41 UDP header  (dest_port = overall bytes 36-37)
//   42..  UDP payload (byte 0 = packet type; if 0x20: byte1=opcode,
//                       bytes 2-5=arg, MSB first)
//
// Frame is only acted on at rx_eof, and only if rx_crc_ok -- a frame with a
// bad FCS is simply dropped, exactly like a real NIC would.
//
// Suggested ports (design your own):
//   clk, rst
//   rx_byte[7:0], rx_byte_valid, rx_sof, rx_eof, rx_crc_ok  (from eth_mac_rx)
//   leds[15:0]                                              (SET_LED target)
//   cmd_valid, cmd_opcode[7:0], cmd_arg[31:0]                (generic, for
//                                                             future opcodes)
// =============================================================================

module cmd_rx(
    input  logic clk, rst,

    input  logic [7:0] rx_byte,
    input  logic rx_byte_valid,
    input  logic rx_sof,
    input  logic rx_eof,
    input  logic rx_crc_ok,

    output logic [15:0] leds,
    output logic cmd_valid,
    output logic [7:0] cmd_opcode,
    output logic [31:0] cmd_arg
);

    localparam logic [15:0] ETHERTYPE_IPV4 = 16'h0800;
    localparam logic [7:0]  IPPROTO_UDP    = 8'h11;
    localparam logic [15:0] UDP_PORT_RETURN = 16'd5004;
    localparam logic [7:0]  PKT_COMMAND    = 8'h20;
    localparam logic [7:0]  OPCODE_SET_LED = 8'h01;

    // "index of the byte arriving THIS cycle" -- combinational so it reads
    // correctly as 0 on the very same cycle rx_sof fires (the underlying
    // register only updates for the FOLLOWING cycle, same reasoning as
    // eth_mac_rx's own byte/dibit indexing).
    logic [5:0] byte_index_next;
    logic [5:0] cur_idx;
    assign cur_idx = rx_sof ? 6'd0 : byte_index_next;

    always_ff @(posedge clk) begin
        if (rst)
            byte_index_next <= 6'd0;
        else if (rx_byte_valid)
            byte_index_next <= cur_idx + 6'd1;
    end

    logic [15:0] ethertype_r;
    logic [7:0]  ip_protocol_r;
    logic [15:0] dest_port_r;
    logic [7:0]  pkt_type_r;
    logic [7:0]  opcode_r;
    logic [31:0] arg_r;

    always_ff @(posedge clk) begin
        if (rst) begin
            ethertype_r   <= 16'h0;
            ip_protocol_r <= 8'h0;
            dest_port_r   <= 16'h0;
            pkt_type_r    <= 8'h0;
            opcode_r      <= 8'h0;
            arg_r         <= 32'h0;
        end
        else if (rx_byte_valid) begin
            case (cur_idx)
                6'd12: ethertype_r[15:8]   <= rx_byte;
                6'd13: ethertype_r[7:0]    <= rx_byte;
                6'd23: ip_protocol_r       <= rx_byte;
                6'd36: dest_port_r[15:8]   <= rx_byte;
                6'd37: dest_port_r[7:0]    <= rx_byte;
                6'd42: pkt_type_r          <= rx_byte;
                6'd43: opcode_r            <= rx_byte;
                6'd44: arg_r[31:24]        <= rx_byte;
                6'd45: arg_r[23:16]        <= rx_byte;
                6'd46: arg_r[15:8]         <= rx_byte;
                6'd47: arg_r[7:0]          <= rx_byte;
                default: ;
            endcase
        end
    end

    // factored out rather than written inline inside the always_ff below --
    // see eth/udp_tx_packetizer.sv's header comment for why: combining a
    // multi-term condition referencing an externally-supplied signal
    // (rx_crc_ok) directly inside a triggering `if` has, elsewhere in this
    // project, reliably hung this Icarus build. Splitting it into its own
    // signal first sidesteps it and costs nothing.
    logic frame_is_valid_command;
    assign frame_is_valid_command = rx_crc_ok
                                   && (ethertype_r   == ETHERTYPE_IPV4)
                                   && (ip_protocol_r == IPPROTO_UDP)
                                   && (dest_port_r   == UDP_PORT_RETURN)
                                   && (pkt_type_r    == PKT_COMMAND);

    always_ff @(posedge clk) begin
        if (rst) begin
            cmd_valid  <= 1'b0;
            cmd_opcode <= 8'h0;
            cmd_arg    <= 32'h0;
            leds       <= 16'h0;
        end
        else begin
            cmd_valid <= 1'b0; // default; pulses for exactly one cycle below

            if (rx_eof && frame_is_valid_command) begin
                cmd_valid  <= 1'b1;
                cmd_opcode <= opcode_r;
                cmd_arg    <= arg_r;

                if (opcode_r == OPCODE_SET_LED)
                    leds <= arg_r[15:0];
            end
        end
    end

endmodule
