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
// -----------------------------------------------------------------------
// Suggested internal architecture
// -----------------------------------------------------------------------
// Two nested counters instead of one giant state machine per byte:
//   - `field` (the states below) -- which section of the frame you're in.
//   - `byte_cnt` -- which byte within the current field (resets to 0 when
//     `field` changes).
//   - `nibble_cnt` (0..3) -- which of the 4 clocks for the CURRENT byte.
//     nibble_cnt selects which 2-bit slice of the byte goes on txd:
//       0 -> byte[1:0], 1 -> byte[3:2], 2 -> byte[5:4], 3 -> byte[7:6].
//     On nibble_cnt hitting 3, advance byte_cnt (and roll to the next
//     `field` if byte_cnt has reached that field's length).
// A clean way to pick "the byte to transmit right now": a combinational
// mux/case on `field` (and `byte_cnt` for the multi-byte fields) producing
// a single `current_tx_byte` wire, then one shared piece of logic drives
// `rmii_txd <= current_tx_byte[nibble_cnt*2 +: 2]` regardless of field.
// That keeps the nibble-serialization logic written exactly once.
//
// -----------------------------------------------------------------------
// FSM states
// -----------------------------------------------------------------------
//   IDLE       -- wait for tx_start pulse. Latch dest_mac/ethertype (the
//                 caller must hold these stable from tx_start through the
//                 end of the frame). Pulse crc_init to eth_crc32. Reset
//                 byte_cnt/nibble_cnt/payload byte counter to 0.
//   PREAMBLE   -- 7 bytes of 8'h55. tx_en = 1 throughout (in fact tx_en
//                 stays 1 for every state except IDLE and IFG).
//   SFD        -- 1 byte, 8'hD5.
//   DEST_MAC   -- 6 bytes from the latched dest_mac. Feed each byte to
//                 eth_crc32 (data_valid pulse, once per 4 clocks, aligned
//                 with nibble_cnt == 3 i.e. the last clock of each byte)
//                 -- CRC coverage starts here.
//   SRC_MAC    -- 6 bytes, your own MAC. Feed CRC.
//   ETHERTYPE  -- 2 bytes from the latched ethertype. Feed CRC.
//   PAYLOAD    -- assert payload_ready for one clock every 4 clocks
//                 (whenever nibble_cnt == 3, i.e. you're about to need the
//                 NEXT byte), latch payload_data when payload_valid = 1,
//                 drive it onto txd over the following 4 clocks, feed CRC.
//                 Track a running payload-byte counter. If payload_last
//                 arrives before that counter reaches 46, keep driving
//                 zero bytes (still feeding CRC, still counting) until it
//                 does -- real frames shorter than 46B must be zero-padded.
//   FCS        -- read crc_out from eth_crc32 (should be stable/settled by
//                 the time you get here -- confirm your eth_crc32's
//                 always_comb has no unintended combinational delay chain
//                 issue). Drive its 4 bytes, LEAST-significant-byte first.
//                 Do NOT feed these bytes back into the CRC engine.
//   IFG        -- deassert tx_en. Hold idle for >= 12 byte-times (48
//                 clocks) -- a free-running clock counter is enough, no
//                 nibble/byte tracking needed here. Then return to IDLE
//                 and clear busy.
//
// Keep `busy` asserted from tx_start until IFG completes, so callers know
// not to iszsue another tx_start mid-frame. rst should force you back to
// IDLE/tx_en=0 regardless of what state you were in.
//
// Suggested ports (design your own):
//   clk, rst                                   -- 50 MHz eth_ref_clk domain
//   tx_start, dest_mac[47:0], ethertype[15:0], busy
//   payload_data[7:0], payload_valid, payload_last, payload_ready
//   rmii_txd[1:0], rmii_tx_en
// =============================================================================


module eth_mac_tx(
    input logic clk,rst,
    input logic tx_start,
    input logic [47:0] dest_mac,
    input logic [47:0] src_mac,
    input logic [15:0] ethertype,
    input logic [7:0] payload_data, payload_valid, payload_last, payload_ready,
    output logic rmii_txd[1:0], rmii_tx_en;
    
);
    logic busy;
    logic [1:0] cur_data;
    int cnt_data = 0;


    typedef enum (IDLE, PREAMBLE, SFD, DEST_MAC, SRC_MAC, PAYLOAD, FCS, IFG) state_t;
    state_t current_state, next_state;

    localparam int preamble = 8'h55;
    localparam int k_preamble = 1'd8;
    localparam int sfd      = 8'hD5; 
    localparam int k_sfd    = 1'd1;

    always_ff @(posedge clk) begin
        if(rst) begin
            current_state <= IDLE;
            busy <= 0;
            cur_data <= 2'b00;
            cnt_data <= 0;
            rmii_txd <= 2'b00;
            rmii_tx_en <= 2'b00;
        end

        else begin
            
        end
    
    end

    always_comb begin
        next_state = current_state;

        case(state)
        IDLE: begin

        end
        PREAMBLE: begin
        end
        SFD: begin
        end
        DEST_MAC: begin
        end
        SRC_MAC: begin
        end
        PAYLOAD: begin
        end
        FCS: begin
        end 
        IFG: begin
        end 
        
        endcase 
    
    end



endmodule