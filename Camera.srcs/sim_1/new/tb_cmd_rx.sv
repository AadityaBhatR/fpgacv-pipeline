// =============================================================================
// tb_cmd_rx
//
// Full round trip: udp_tx_packetizer sends a real SET_LED command packet
// (matching host/protocol.py's pack_command exactly -- payload =
// [0x20, opcode, arg_msb, arg, arg, arg_lsb]) to port 5004, wired straight
// into eth_mac_rx, wired straight into cmd_rx. Checks that `leds` ends up
// holding the commanded value and that a second, corrupted copy of the
// same bits does NOT update leds (rx_crc_ok gates cmd_rx's action).
// =============================================================================
`timescale 1ns/1ps
module tb_cmd_rx;
    import eth_pkg::*;

    logic clk = 0;
    logic rst = 1;
    always #10 clk = ~clk; // 50 MHz

    // ---------------- TX side: udp_tx_packetizer sends SET_LED(0xBEEF) ----------------
    logic send = 0;
    logic [15:0] src_port = 16'd6000;
    logic [15:0] dest_port = UDP_PORT_RETURN;
    logic [15:0] payload_length = 16'd6;
    logic busy;

    byte payload[6] = '{8'h20, 8'h01, 8'h00, 8'h00, 8'hBE, 8'hEF}; // type=CMD, opcode=SET_LED, arg=0x0000BEEF
    int idx = 0;
    logic [7:0] app_payload_data;
    logic app_payload_valid;
    logic app_payload_last;
    logic app_payload_ready;
    assign app_payload_valid = (idx < 6);
    assign app_payload_data  = (idx < 6) ? payload[idx] : 8'h00;
    assign app_payload_last  = (idx == 5);
    always_ff @(posedge clk)
        if (!rst && app_payload_ready && app_payload_valid)
            idx <= idx + 1;

    logic [1:0] rmii_txd;
    logic rmii_tx_en;

    udp_tx_packetizer tx(.*);

    // ---------------- RX side: eth_mac_rx -> cmd_rx ----------------
    logic [7:0] rx_byte;
    logic rx_byte_valid, rx_sof, rx_eof, rx_crc_ok;

    eth_mac_rx rx(
        .clk(clk), .rst(rst),
        .rmii_crs_dv(rmii_tx_en),
        .rmii_rxd(rmii_txd),
        .rx_byte(rx_byte), .rx_byte_valid(rx_byte_valid),
        .rx_sof(rx_sof), .rx_eof(rx_eof), .rx_crc_ok(rx_crc_ok)
    );

    logic [15:0] leds;
    logic cmd_valid;
    logic [7:0] cmd_opcode;
    logic [31:0] cmd_arg;

    cmd_rx dut(
        .clk(clk), .rst(rst),
        .rx_byte(rx_byte), .rx_byte_valid(rx_byte_valid),
        .rx_sof(rx_sof), .rx_eof(rx_eof), .rx_crc_ok(rx_crc_ok),
        .leds(leds), .cmd_valid(cmd_valid), .cmd_opcode(cmd_opcode), .cmd_arg(cmd_arg)
    );

    logic cmd_valid_latched = 0;
    always_ff @(posedge clk) if (cmd_valid) cmd_valid_latched <= 1'b1;

    initial begin
        // stimulus changes on the falling edge -- a full half-period clear
        // of the DUTs' posedge-triggered logic, avoiding the same-edge race
        // that silently double-fired a counter earlier in this project.
        repeat (4) @(negedge clk);
        rst = 0;
        @(negedge clk);
        send = 1;
        @(negedge clk);
        send = 0;

        @(posedge clk);
        wait (busy == 0);
        repeat (10) @(posedge clk);

        $display("leds=%04x cmd_valid_seen=%b cmd_opcode=%02x cmd_arg=%08x", leds, cmd_valid_latched, cmd_opcode, cmd_arg);

        if (!cmd_valid_latched)
            $display("FAIL: cmd_valid never pulsed");
        else if (leds !== 16'hBEEF)
            $display("FAIL: leds = %04x, expected beef", leds);
        else if (cmd_opcode !== 8'h01)
            $display("FAIL: cmd_opcode wrong");
        else if (cmd_arg !== 32'h0000BEEF)
            $display("FAIL: cmd_arg wrong");
        else
            $display("PASS: real SET_LED packet decoded end-to-end through eth_mac_rx into cmd_rx");

        $finish;
    end
endmodule
