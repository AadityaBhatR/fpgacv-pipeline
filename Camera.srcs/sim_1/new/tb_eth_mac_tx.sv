// =============================================================================
// tb_eth_mac_tx
//
// Drives eth_mac_tx with a broadcast dest_mac, a fixed src_mac/ethertype,
// and a 2-byte payload ("HI", which gets zero-padded to the 46B minimum).
// Reconstructs bytes from the sampled rmii_txd/rmii_tx_en nibble stream
// (inverse of the DUT's own serialization: 4 clocks -> 1 byte, LSB-pair
// first) and checks preamble/SFD/dest MAC/src MAC/EtherType/payload land
// where the frame layout says they should.
//
// The payload source here is intentionally combinational (payload_valid/
// payload_data derived straight from a registered index, not re-registered
// themselves) -- eth_mac_tx samples them the SAME cycle it raises
// payload_ready, so a registered source would hand over data one cycle too
// late. See eth_mac_tx.sv's "Known limitation" note.
//
// Does NOT check the FCS bytes' correctness on its own -- that's covered by
// tb_eth_mac_rx (which cross-checks TX's transmitted FCS by decoding it on
// the RX side and comparing against an independently-recomputed CRC).
// =============================================================================
`timescale 1ns/1ps
module tb_eth_mac_tx;
    logic clk = 0;
    logic rst = 1;
    logic tx_start = 0;
    logic [47:0] dest_mac = 48'hFFFFFFFFFFFF;
    logic [47:0] src_mac  = 48'h020000000001;
    logic [15:0] ethertype = 16'h88B5;

    logic [7:0] payload_data;
    logic payload_valid;
    logic payload_last;
    logic payload_ready;
    logic busy;

    logic [1:0] rmii_txd;
    logic rmii_tx_en;

    eth_mac_tx dut(.*);

    always #10 clk = ~clk; // 50 MHz

    // small payload: "HI" (2 bytes, will get padded to 46)
    byte payload[2] = '{"H", "I"};
    int idx = 0;

    assign payload_valid = (idx < 2);
    assign payload_data  = (idx < 2) ? payload[idx] : 8'h00;
    assign payload_last  = (idx == 1);

    always_ff @(posedge clk) begin
        if (!rst && payload_ready && payload_valid)
            idx <= idx + 1;
    end

    // reconstruct bytes from the nibble stream whenever tx_en is high
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

    initial begin
        repeat (4) @(posedge clk);
        rst = 0;
        @(posedge clk);
        tx_start = 1;
        @(posedge clk);
        tx_start = 0;

        // one more edge before polling busy: reading a combinationally-
        // derived signal like busy in the same delta cycle as the clock
        // edge that's supposed to raise it is a race -- it may still read
        // its pre-edge value, making `wait` succeed trivially before the
        // frame has even started.
        @(posedge clk);
        wait (busy == 0);
        repeat (5) @(posedge clk);

        $write("frame (%0d bytes): ", frame_len);
        for (int i = 0; i < frame_len; i++) $write("%02x ", frame_bytes[i]);
        $display("");

        if (frame_len < 72) $display("FAIL: frame too short");
        else if (frame_bytes[7] !== 8'hD5) $display("FAIL: SFD wrong (byte7=%02x)", frame_bytes[7]);
        else if (frame_bytes[8] !== 8'hFF) $display("FAIL: dest mac wrong");
        else if (frame_bytes[14] !== 8'h02) $display("FAIL: src mac wrong");
        else if (frame_bytes[20] !== 8'h88 || frame_bytes[21] !== 8'hB5) $display("FAIL: ethertype wrong");
        else if (frame_bytes[22] !== "H" || frame_bytes[23] !== "I") $display("FAIL: payload wrong");
        else $display("PASS: header/payload framing looks correct");

        $finish;
    end
endmodule
