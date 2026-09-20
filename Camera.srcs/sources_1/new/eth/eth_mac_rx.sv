// =============================================================================
// eth_mac_rx
//
// Deserializes RMII rx pins back into bytes: strips preamble/SFD, forwards
// dest-MAC-through-payload bytes (FCS excluded), and checks the CRC. Same
// two-process style as eth_mac_tx (registers in always_ff, next-state/byte
// logic in always_comb), same dibit/byte counting, same eth_crc32 instance.
//
// Frame length is unknown up front (unlike TX), so preamble detection is by
// pattern match (look for SFD = 8'hD5), not a fixed byte count, and end of
// frame is simply "rmii_crs_dv dropped."
//
// CRC check: every byte from dest_mac through the payload is fed into
// eth_crc32 continuously (same as TX). You don't know a byte belongs to the
// FCS (and so should NOT be forwarded as rx_byte, and should NOT be fed to
// the running CRC) until 4 MORE bytes have arrived after it, or the frame
// has already ended -- so two 4-deep delay lines run in lockstep:
//   - byte_pipe: raw received bytes. Whatever falls out the far end is
//     forwarded as rx_byte/rx_byte_valid.
//   - crc_pipe: a snapshot of eth_crc32's crc_out, delayed by the same 4
//     byte-times. Whatever falls out the far end is "crc_out as it stood
//     right after the last real byte, before any FCS byte was fed."
// At frame end, byte_pipe still holds the 4 actual FCS bytes (never
// forwarded), and crc_pipe's output is what a correctly-received frame's
// FCS should equal -- so the two are compared directly. No magic constant
// needed; it's the same comparison TX and RX already agree on.
//
// crc_pipe is pushed one cycle later than byte_pipe (via byte_done_d) to
// account for crc_out's own one-cycle registration delay relative to when
// crc_valid was pulsed for a given byte -- this keeps both pipes indexed
// to the same logical byte despite crc_out lagging by a cycle.
//
// Suggested ports (design your own):
//   clk, rst                                   -- 50 MHz eth_ref_clk domain
//   rmii_crs_dv, rmii_rxd[1:0]
//   rx_byte[7:0], rx_byte_valid, rx_sof, rx_eof, rx_crc_ok
// =============================================================================

module eth_mac_rx(
    input  logic clk, rst,

    input  logic rmii_crs_dv,
    input  logic [1:0] rmii_rxd,

    output logic [7:0] rx_byte,
    output logic rx_byte_valid,
    output logic rx_sof,
    output logic rx_eof,
    output logic rx_crc_ok
);

    localparam logic [7:0] sfd = 8'hD5;

    typedef enum {IDLE, PREAMBLE, FRAME} state_t;
    state_t current_state, next_state;

    int cnt_data;
    logic [1:0] dibit_idx;
    assign dibit_idx = cnt_data[1:0];
    logic byte_done;
    assign byte_done = (dibit_idx == 2'd3);
    logic byte_done_d;   // byte_done, delayed 1 cycle -- see crc_pipe note above
    logic frame_ending;  // '!rmii_crs_dv seen in FRAME', delayed 1 cycle -- see EOF note below

    logic [7:0] byte_shift;   // assembling the current byte, dibit by dibit
    logic [7:0] new_byte;     // = byte_shift -- by the cycle byte_done fires,
                              // the 4th dibit was already folded in on the
                              // PREVIOUS edge, so byte_shift is already the
                              // complete byte. Combining it with this cycle's
                              // rmii_rxd (which already belongs to the NEXT
                              // byte) would pull in one dibit too many.
    assign new_byte = byte_shift;

    // 4-deep delay lines, oldest entry (index 3) is what falls out
    logic [7:0] byte_pipe [0:3];
    logic [31:0] crc_pipe [0:3];
    logic [2:0] pipe_cnt;      // how many real bytes pushed this frame, saturates at 4
    logic first_emitted;       // for rx_sof

    logic crc_init, crc_valid;
    logic [7:0] crc_din;
    logic [31:0] crc_out;

    eth_crc32 u_crc (
        .clk(clk),
        .rst(~rst),          // eth_crc32 is active-low/async, we're active-high/sync
        .crc_init(crc_init),
        .data_valid(crc_valid),
        .data_in(crc_din),
        .crc_out(crc_out),
        .crc_reg_raw()
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            current_state <= IDLE;
            cnt_data      <= 0;
            byte_shift    <= 8'h00;
            pipe_cnt      <= 0;
            first_emitted <= 1'b0;
            rx_byte       <= 8'h00;
            rx_byte_valid <= 1'b0;
            byte_done_d   <= 1'b0;
            frame_ending  <= 1'b0;
        end
        else begin
            current_state <= next_state;

            if (next_state != current_state)
                cnt_data <= 0;
            else
                cnt_data <= cnt_data + 1;

            // gated on the live input, not current_state: current_state only
            // becomes PREAMBLE one cycle AFTER crs_dv first rises (state
            // transitions are registered), which would silently drop the
            // very first real dibit if gated on current_state instead.
            if (rmii_crs_dv)
                byte_shift <= {rmii_rxd, byte_shift[7:2]};

            if (next_state == FRAME && current_state != FRAME) begin
                pipe_cnt      <= 0;
                first_emitted <= 1'b0;
            end

            byte_done_d  <= (current_state == FRAME) && byte_done;
            // rmii_crs_dv drops the SAME cycle the last byte's byte_done
            // fires, one cycle before byte_pipe/crc_pipe's last push for
            // that byte actually commits -- delay the EOF check by one
            // cycle so it reads the pipes AFTER that push lands.
            frame_ending <= (current_state == FRAME) && !rmii_crs_dv;

            rx_byte_valid <= 1'b0; // default: pulse only on a completed FRAME byte, below
            if (current_state == FRAME && byte_done) begin
                byte_pipe[3] <= byte_pipe[2];
                byte_pipe[2] <= byte_pipe[1];
                byte_pipe[1] <= byte_pipe[0];
                byte_pipe[0] <= new_byte;

                if (pipe_cnt < 4)
                    pipe_cnt <= pipe_cnt + 1;

                rx_byte       <= byte_pipe[3];
                rx_byte_valid <= (pipe_cnt >= 4);
                if (pipe_cnt >= 4)
                    first_emitted <= 1'b1;
            end

            if (byte_done_d) begin
                crc_pipe[3] <= crc_pipe[2];
                crc_pipe[2] <= crc_pipe[1];
                crc_pipe[1] <= crc_pipe[0];
                crc_pipe[0] <= crc_out;
            end
        end
    end

    always_comb begin
        next_state = current_state;
        crc_init   = 1'b0;
        crc_valid  = 1'b0;
        crc_din    = new_byte;
        rx_sof     = 1'b0;
        rx_eof     = 1'b0;
        rx_crc_ok  = 1'b0;

        case (current_state)
            IDLE: begin
                if (rmii_crs_dv)
                    next_state = PREAMBLE;
            end

            PREAMBLE: begin
                if (!rmii_crs_dv)
                    next_state = IDLE; // frame aborted before SFD found
                else if (byte_done && new_byte == sfd) begin
                    next_state = FRAME;
                    crc_init   = 1'b1;
                end
                // anything else (0x55 or noise): keep waiting for SFD
            end

            FRAME: begin
                if (byte_done) begin
                    crc_valid = 1'b1; // covers dest_mac..FCS, all of it
                end

                if (!rmii_crs_dv)
                    next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase

        // fires one cycle after the frame actually ended, once byte_pipe's
        // and crc_pipe's final pushes (for the last FCS byte) have landed
        if (frame_ending) begin
            rx_eof    = 1'b1;
            // byte_pipe still holds the 4 actual FCS bytes (never forwarded
            // as rx_byte); reassemble them MSB-byte-first back into the
            // 32-bit value they represent, and compare against crc_pipe's
            // delayed crc_out snapshot.
            rx_crc_ok = ({byte_pipe[0], byte_pipe[1], byte_pipe[2], byte_pipe[3]} == crc_pipe[3]);
        end

        // pulses the same cycle rx_byte_valid will latch true, one ahead
        // of the registered pipe_cnt/first_emitted -- see always_ff
        rx_sof = (current_state == FRAME) && byte_done && (pipe_cnt == 3) && !first_emitted;
    end

endmodule
