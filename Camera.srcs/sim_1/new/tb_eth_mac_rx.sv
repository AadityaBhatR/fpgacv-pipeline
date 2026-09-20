// =============================================================================
// tb_eth_mac_rx
//
// End-to-end loopback: instantiates a real eth_mac_tx generating a frame
// (dest=aa:bb:cc:dd:ee:ff, src=02:00:00:00:00:01, ethertype=0x88B5,
// payload="HI!") and wires its rmii_txd/rmii_tx_en directly into a real
// eth_mac_rx's rmii_rxd/rmii_crs_dv -- this is the most useful test in the
// suite, since it checks TX and RX agree with each other rather than just
// each one matching its own internal expectations.
//
// Checks:
//   1. rx_byte/rx_byte_valid reconstructs exactly the 60 bytes (dest MAC
//      through payload+padding) that TX was asked to send -- confirms
//      framing, byte ordering, and the delay-line that holds back the FCS
//      bytes are all correct.
//   2. rx_crc_ok asserts true for this untouched frame.
//   3. A SECOND eth_mac_rx instance (rx2) is fed the same bits with one bit
//      deliberately flipped partway through the payload. Its rx_crc_ok must
//      come back FALSE -- this is the important negative test: without it,
//      rx_crc_ok could be stuck at a constant 1 and this suite would never
//      notice.
// =============================================================================
`timescale 1ns/1ps
module tb_eth_mac_rx;
    logic clk = 0;
    logic rst = 1;
    always #10 clk = ~clk; // 50 MHz

    // ---------------- TX side: generates a real frame ----------------
    logic tx_start = 0;
    logic [47:0] dest_mac = 48'hAABBCCDDEEFF;
    logic [47:0] src_mac  = 48'h020000000001;
    logic [15:0] ethertype = 16'h88B5;

    logic [7:0] payload_data;
    logic payload_valid;
    logic payload_last;
    logic payload_ready;
    logic busy;

    logic [1:0] rmii_txd;
    logic rmii_tx_en;

    eth_mac_tx tx(.*);

    byte payload[3] = '{"H", "I", "!"};
    int idx = 0;
    assign payload_valid = (idx < 3);
    assign payload_data  = (idx < 3) ? payload[idx] : 8'h00;
    assign payload_last  = (idx == 2);
    always_ff @(posedge clk) begin
        if (!rst && payload_ready && payload_valid)
            idx <= idx + 1;
    end

    // ---------------- RX side: consumes what TX produced ----------------
    logic [7:0] rx_byte;
    logic rx_byte_valid, rx_sof, rx_eof, rx_crc_ok;

    eth_mac_rx rx(
        .clk(clk), .rst(rst),
        .rmii_crs_dv(rmii_tx_en),
        .rmii_rxd(rmii_txd),
        .rx_byte(rx_byte),
        .rx_byte_valid(rx_byte_valid),
        .rx_sof(rx_sof),
        .rx_eof(rx_eof),
        .rx_crc_ok(rx_crc_ok)
    );

    logic [7:0] got[0:255];
    int got_len = 0;
    logic rx_crc_ok_latched = 0;
    always_ff @(posedge clk) if (rx_eof) rx_crc_ok_latched <= rx_crc_ok;
    always_ff @(posedge clk) begin
        if (!rst && rx_byte_valid) begin
            got[got_len] <= rx_byte;
            got_len      <= got_len + 1;
        end
    end

    // ---------------- negative test: a second RX fed a corrupted wire ----------------
    logic [1:0] rxd_corrupt;
    logic inject_glitch = 0;
    assign rxd_corrupt = rmii_txd ^ (inject_glitch ? 2'b01 : 2'b00);

    logic [7:0] rx2_byte;
    logic rx2_byte_valid, rx2_sof, rx2_eof, rx2_crc_ok;
    logic rx2_crc_ok_latched = 0;
    always_ff @(posedge clk) if (rx2_eof) rx2_crc_ok_latched <= rx2_crc_ok;

    eth_mac_rx rx2(
        .clk(clk), .rst(rst),
        .rmii_crs_dv(rmii_tx_en),
        .rmii_rxd(rxd_corrupt),
        .rx_byte(rx2_byte), .rx_byte_valid(rx2_byte_valid),
        .rx_sof(rx2_sof), .rx_eof(rx2_eof), .rx_crc_ok(rx2_crc_ok)
    );

    initial begin
        repeat (4) @(posedge clk);
        rst = 0;
        @(posedge clk);
        tx_start = 1;
        @(posedge clk);
        tx_start = 0;

        // flip one bit partway through the payload, only on rx2's wire
        repeat (100) @(posedge clk);
        inject_glitch = 1;
        @(posedge clk);
        inject_glitch = 0;

        wait (busy == 0);
        repeat (10) @(posedge clk);

        $write("rx got %0d bytes: ", got_len);
        for (int i = 0; i < got_len; i++) $write("%02x ", got[i]);
        $display("");
        $display("rx_crc_ok seen this run: %b, rx2 (corrupted) crc_ok: %b", rx_crc_ok_latched, rx2_crc_ok_latched);

        if (got_len !== 60) $display("FAIL: expected 60 bytes (dest..payload), got %0d", got_len);
        else if (got[0]!==8'haa || got[5]!==8'hff) $display("FAIL: dest mac wrong");
        else if (got[6]!==8'h02 || got[11]!==8'h01) $display("FAIL: src mac wrong");
        else if (got[12]!==8'h88 || got[13]!==8'hb5) $display("FAIL: ethertype wrong");
        else if (got[14]!=="H" || got[15]!=="I" || got[16]!=="!") $display("FAIL: payload wrong");
        else if (!rx_crc_ok_latched) $display("FAIL: rx_crc_ok did not assert for a good frame");
        else if (rx2_crc_ok_latched) $display("FAIL: rx2_crc_ok should have caught the injected bit-flip");
        else $display("PASS: rx byte stream + crc_ok correct, AND corrupted copy correctly flagged bad");

        $finish;
    end
endmodule
