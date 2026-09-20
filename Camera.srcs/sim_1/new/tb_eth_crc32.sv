// =============================================================================
// tb_eth_crc32
//
// Verifies eth_crc32 against the standard CRC-32 test vector: feeding the
// ASCII bytes of "123456789" (with crc_init pulsed first) must produce
// 0xcbf43926 -- the same value as `python3 -c "import zlib; print(hex(zlib.crc32(b'123456789')))"`.
// If this fails, nothing built on top of eth_crc32 (eth_mac_tx, eth_mac_rx)
// can be trusted, so it's worth running standalone before debugging anything
// else.
// =============================================================================
`timescale 1ns/1ps
module tb_eth_crc32;
    logic clk = 0;
    logic rst = 0;
    logic crc_init = 0;
    logic data_valid = 0;
    logic [7:0] data_in = 0;
    logic [31:0] crc_out;

    eth_crc32 dut(.clk(clk), .rst(rst), .crc_init(crc_init),
                  .data_valid(data_valid), .data_in(data_in), .crc_out(crc_out));

    always #5 clk = ~clk;

    // ASCII "123456789"
    byte msg[9] = '{"1","2","3","4","5","6","7","8","9"};

    task automatic send_byte(input byte b);
        @(posedge clk);
        data_in <= b;
        data_valid <= 1;
        @(posedge clk);
        data_valid <= 0;
    endtask

    initial begin
        // eth_crc32's rst is active-LOW/async: 0 = held in reset, 1 = released
        rst = 0;
        repeat (2) @(posedge clk);
        rst = 1;

        @(posedge clk);
        crc_init <= 1;
        @(posedge clk);
        crc_init <= 0;

        for (int i = 0; i < 9; i++) begin
            send_byte(msg[i]);
        end

        @(posedge clk);
        $display("crc_out = 0x%08x (expect 0xcbf43926)", crc_out);
        if (crc_out === 32'hcbf43926)
            $display("PASS");
        else
            $display("FAIL");
        $finish;
    end
endmodule
