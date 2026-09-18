// =============================================================================
// eth_crc32
//
// Byte-serial Ethernet FCS (CRC-32) engine. 
//
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
// Current ports 
//   clk, rst
//   crc_init      -- pulse: reset crc state to 32'hFFFFFFFF
//   data_valid    -- pulse: data_in holds a new byte this cycle
//   data_in[7:0]
//   crc_out[31:0]     -- crc_reg ^ 32'hFFFFFFFF (the value to transmit)
//   crc_reg_raw[31:0] -- running UNINVERTED CRC state, for eth_mac_rx's
//                        residual-check trick (compare against the magic
//                        constant 32'hC704DD7B after feeding in the
//                        received FCS bytes)
//
// Implementation note: you can do the 8 bit-iterations either as a fully
// unrolled combinational function (one byte processed per clock) or as a
// bit-serial shifter (8 clocks per byte) -- the fully-unrolled version is
// what you want for the MAC, since RMII only gives you 1 byte every 4
// clocks to work with.
// =============================================================================

module eth_crc32(
    input logic clk, rst,
    input logic crc_init,
    input logic data_valid,
    input logic [7:0] data_in,

    output logic [31:0] crc_out,
    output logic [31:0] crc_reg_raw
);

localparam  logic [31:0] POLY   = 32'hEDB88320;
            logic [31:0] crc_reg, crc_next;

always_comb begin
    logic [31:0] c;
    c = crc_reg ^ {24'h0, data_in};

    for(int i = 0; i < 8; i++) begin
        if(c[0])
            c = (c >> 1) ^ POLY;
        else
            c = (c >> 1);
    end 
    crc_next = c;
end

always_ff @(posedge clk or negedge rst) begin
    if(!rst) begin
        crc_reg <= 32'hFFFFFFFF;
    end
    else if(crc_init) begin
        crc_reg <= 32'hFFFFFFFF;
    end
    else if(data_valid) begin
        crc_reg <= crc_next;
    end

end

assign crc_out     = crc_reg ^ 32'hFFFFFFFF;
assign crc_reg_raw = crc_reg;


endmodule