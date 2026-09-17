// =============================================================================
// eth_crc32
//
// Byte-serial Ethernet FCS (CRC-32) engine. This is the SAME CRC-32 used by
// zlib/gzip/PNG, so you can verify your implementation in isolation before
// it ever touches real RMII logic:
//
//   python3 -c "import zlib; print(hex(zlib.crc32(b'123456789')))"
//   -> 0xcbf43926
//
// Feed the ASCII bytes of "123456789" in one at a time with crc_init pulsed
// once at the start, and after the 9th byte crc_reg XOR 32'hFFFFFFFF should
// read 32'hcbf43926.
//
// Algorithm (reflected form, processes LSb-first per byte -- matches the
// bit order Ethernet transmits on the wire):
//   1. crc_reg initializes to 32'hFFFFFFFF (pulse crc_init).
//   2. For each incoming byte:
//        crc_reg <= crc_reg ^ (bring the byte in as the low 8 bits)
//        repeat 8 times:
//          if crc_reg[0] == 1'b1
//            crc_reg <= {1'b0, crc_reg[31:1]} ^ 32'hEDB88320;
//          else
//            crc_reg <= {1'b0, crc_reg[31:1]};
//   3. The transmitted FCS = crc_reg ^ 32'hFFFFFFFF, sent onto the wire
//      LEAST-significant BYTE first (i.e. reverse byte order from how you'd
//      normally write the 32-bit value).
//
// Suggested ports (design your own -- this is just a starting contract):
//   clk, rst
//   crc_init      -- pulse: reset crc state to 32'hFFFFFFFF
//   data_valid    -- pulse: data_in holds a new byte this cycle
//   data_in[7:0]
//   crc_reg[31:0] -- running (uninverted) CRC state
//   crc_fcs[31:0] -- crc_reg ^ 32'hFFFFFFFF (the value to transmit)
//
// Implementation note: you can do the 8 bit-iterations either as a fully
// unrolled combinational function (one byte processed per clock) or as a
// bit-serial shifter (8 clocks per byte) -- the fully-unrolled version is
// what you want for the MAC, since RMII only gives you 1 byte every 4
// clocks to work with.
// =============================================================================

module eth_crc32(
    input logic clk, rst
    input logic crc_init,
    input logic data_valid,
    input logic [7:0] data_in,

    output logic [31:0] crc_out;
);

localparam  logic [7:0] POLY   = 32'hEDB88320;
            logic [31:0] crc_reg, crc_next;

always_comb begin
    logic [31:0] c;
    c = {24'h0, data_in};

    for(int i = 0; i < 8; i++) begin
        if(c[0])
            c = (c >> 1) ^ POLY;
        else
            c = (c >> 1);
    end 
    crc_next = c;
end

always_ff @(posedge clk negedge rst) begin
    if(!rst) begin
        crc_reg <= 32'hFFFFFFFF;
    end
    else if(data_valid) begin
            crc_reg <= crc_next;
    end

end

assign crc_out = crc_reg ^ 32'hFFFFFFFF;


endmodule