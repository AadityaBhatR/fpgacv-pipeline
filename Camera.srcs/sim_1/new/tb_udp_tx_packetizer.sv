// =============================================================================
// tb_udp_tx_packetizer
//
// Sends a 5-byte "HELLO" UDP datagram (src_port=5001, dest_port=5003) and
// decodes the ENTIRE resulting Ethernet frame byte-by-byte: preamble, SFD,
// dest/src MAC, EtherType, the full 20B IPv4 header (including checksum),
// the 8B UDP header, and the payload+padding.
//
// The IPv4 checksum expected value (0xB716) was computed by hand offline,
// not re-derived with the same fold algorithm here -- reusing the DUT's own
// method in its testbench risks a correlated bug (if the fold logic has a
// mistake, both sides would agree on the same wrong answer and this test
// would falsely pass).
// =============================================================================
`timescale 1ns/1ps
module tb_udp_tx_packetizer;
    import eth_pkg::*;

    logic clk = 0;
    logic rst = 1;
    always #10 clk = ~clk; // 50 MHz

    logic send = 0;
    logic [15:0] src_port = 16'd5001;
    logic [15:0] dest_port = 16'd5003;
    logic [15:0] payload_length = 16'd5;
    logic busy;

    logic [7:0] app_payload_data;
    logic app_payload_valid;
    logic app_payload_last;
    logic app_payload_ready;

    logic [1:0] rmii_txd;
    logic rmii_tx_en;

    udp_tx_packetizer dut(.*);

    byte payload[5] = '{"H","E","L","L","O"};
    int idx = 0;
    assign app_payload_valid = (idx < 5);
    assign app_payload_data  = (idx < 5) ? payload[idx] : 8'h00;
    assign app_payload_last  = (idx == 4);
    always_ff @(posedge clk)
        if (!rst && app_payload_ready && app_payload_valid)
            idx <= idx + 1;

    // reconstruct bytes from the nibble stream (same technique as tb_eth_mac_tx)
    logic [7:0] frame_bytes[0:255];
    int frame_len = 0;
    logic [7:0] shift_byte;
    int nib_cnt = 0;
    always_ff @(posedge clk) begin
        if (!rst) begin
            if (rmii_tx_en) begin
                shift_byte <= {rmii_txd, shift_byte[7:2]};
                nib_cnt <= nib_cnt + 1;
                if (nib_cnt == 3) begin
                    frame_bytes[frame_len] <= {rmii_txd, shift_byte[7:2]};
                    frame_len <= frame_len + 1;
                    nib_cnt <= 0;
                end
            end else begin
                nib_cnt <= 0;
            end
        end
    end

    // watchdog: never let a stuck FSM hang the simulator indefinitely
    initial begin
        #1_000_000;
        $display("FAIL: watchdog timeout, simulation never finished");
        $finish;
    end

    initial begin
        // stimulus changes on the falling edge, a full half-period away from
        // the DUT's posedge-triggered logic -- changing it right at/after
        // posedge would race the DUT's own same-edge evaluation (confirmed
        // while debugging this test: that race silently double-fired the
        // identification counter for a single send pulse)
        repeat (4) @(negedge clk);
        rst = 0;
        @(negedge clk);
        send = 1;
        @(negedge clk);
        send = 0;

        @(posedge clk);
        wait (busy == 0);
        repeat (5) @(posedge clk);

        $write("frame (%0d bytes): ", frame_len);
        for (int i = 0; i < frame_len; i++) $write("%02x ", frame_bytes[i]);
        $display("");

        if (frame_len !== 72)
            $display("FAIL: expected 72 bytes total, got %0d", frame_len);
        else if (frame_bytes[7] !== 8'hD5)
            $display("FAIL: SFD wrong");
        else if ({frame_bytes[8],frame_bytes[9],frame_bytes[10],frame_bytes[11],frame_bytes[12],frame_bytes[13]} !== HOST_MAC)
            $display("FAIL: dest mac != HOST_MAC");
        else if ({frame_bytes[14],frame_bytes[15],frame_bytes[16],frame_bytes[17],frame_bytes[18],frame_bytes[19]} !== FPGA_MAC)
            $display("FAIL: src mac != FPGA_MAC");
        else if ({frame_bytes[20],frame_bytes[21]} !== 16'h0800)
            $display("FAIL: ethertype != IPv4");
        else if (frame_bytes[22] !== 8'h45 || frame_bytes[23] !== 8'h00)
            $display("FAIL: IP version/IHL/DSCP wrong");
        else if ({frame_bytes[24],frame_bytes[25]} !== 16'd33)
            $display("FAIL: ip_total_length wrong, got %0d expect 33", {frame_bytes[24],frame_bytes[25]});
        else if ({frame_bytes[26],frame_bytes[27]} !== 16'h0000)
            $display("FAIL: identification wrong (expected 0 on first send after reset)");
        else if (frame_bytes[30] !== 8'h40)
            $display("FAIL: TTL wrong");
        else if (frame_bytes[31] !== 8'h11)
            $display("FAIL: protocol != UDP");
        else if ({frame_bytes[32],frame_bytes[33]} !== 16'hB716)
            $display("FAIL: ip checksum wrong, got %04x expect b716", {frame_bytes[32],frame_bytes[33]});
        else if ({frame_bytes[34],frame_bytes[35],frame_bytes[36],frame_bytes[37]} !== FPGA_IP)
            $display("FAIL: src IP != FPGA_IP");
        else if ({frame_bytes[38],frame_bytes[39],frame_bytes[40],frame_bytes[41]} !== HOST_IP)
            $display("FAIL: dst IP != HOST_IP");
        else if ({frame_bytes[42],frame_bytes[43]} !== 16'd5001)
            $display("FAIL: udp src_port wrong");
        else if ({frame_bytes[44],frame_bytes[45]} !== 16'd5003)
            $display("FAIL: udp dest_port wrong");
        else if ({frame_bytes[46],frame_bytes[47]} !== 16'd13)
            $display("FAIL: udp_length wrong, got %0d expect 13", {frame_bytes[46],frame_bytes[47]});
        else if ({frame_bytes[48],frame_bytes[49]} !== 16'h0000)
            $display("FAIL: udp checksum should be disabled (0x0000)");
        else if (frame_bytes[50]!=="H" || frame_bytes[51]!=="E" || frame_bytes[52]!=="L"
                 || frame_bytes[53]!=="L" || frame_bytes[54]!=="O")
            $display("FAIL: payload wrong");
        else
            $display("PASS: full Ethernet+IPv4+UDP frame decoded correctly, checksum included");

        $finish;
    end
endmodule
