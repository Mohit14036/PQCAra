// =============================================================
// keccak_sponge.v -- generic Keccak sponge construction wrapper
// around the single shared keccak_f1600 permutation core.
//
// Implements exactly the absorb/pad/permute/squeeze sequence used
// by ref/fips202.c's keccak_absorb_once() + (explicit permute for
// SHA3, or finalize+squeeze for SHAKE) + keccak_squeeze():
//   - zero the 1600-bit state
//   - XOR in RATE_BYTES-byte blocks of real input, permuting after
//     each FULL block (no padding on those)
//   - XOR in the final (possibly empty) partial block of real
//     input bytes, then XOR in PAD_BYTE at the byte position right
//     after the real data, and XOR 0x80 into the last byte of the
//     rate (these two can land on the same byte -- combined
//     correctly via a compile-time-constant mask), then permute
//     once more
//   - squeeze OUT_LEN bytes, permuting again between every full
//     RATE_BYTES block of output needed
//
// IN_LEN, OUT_LEN, RATE_BYTES and PAD_BYTE are compile-time
// parameters (Kyber only ever calls each hash/XOF/PRF site with a
// fixed, statically-known length), so this is a realistic
// fixed-function accelerator shape, not a generic streaming API --
// one instance per call site (hash_h, hash_g, prf, rkprf, xof),
// all sharing the same underlying keccak_f1600 permutation core.
//
// PAD_BYTE = 8'h06 for SHA3-256/SHA3-512, 8'h1F for SHAKE128/256.
// =============================================================

module keccak_sponge #(
    parameter RATE_BYTES    = 136,
    parameter IN_LEN        = 64,
    parameter OUT_LEN       = 64,
    parameter [7:0] PAD_BYTE = 8'h06
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start_i,
    input  wire [8*IN_LEN-1:0]          in_bytes,
    output reg  [8*OUT_LEN-1:0]         out_bytes,
    output reg                          done
);

    localparam FULL_BLOCKS = IN_LEN / RATE_BYTES;
    localparam TAIL_BYTES  = IN_LEN % RATE_BYTES;

    // Compile-time-constant padding mask: PAD_BYTE at byte position
    // TAIL_BYTES, and 0x80 at byte position RATE_BYTES-1, correctly
    // combined (XORed) even if they land on the same byte.
    function [1599:0] gen_pad_mask;
        input dummy;
        reg [1599:0] m;
        begin
            m = 1600'd0;
            m[8*TAIL_BYTES +: 8]        = m[8*TAIL_BYTES +: 8] ^ PAD_BYTE;
            m[8*(RATE_BYTES-1) +: 8]    = m[8*(RATE_BYTES-1) +: 8] ^ 8'h80;
            gen_pad_mask = m;
        end
    endfunction
    localparam [1599:0] PAD_MASK = gen_pad_mask(1'b0);

    reg [1599:0] st;
    reg          perm_start;
    wire [1599:0] perm_out;
    wire          perm_done;

    keccak_f1600 u_perm (.clk(clk), .rst_n(rst_n), .start(perm_start),
                          .state_in(st), .state_out(perm_out), .done(perm_done));

    localparam IDLE             = 4'd0,
               ABSORB_FULL_XOR  = 4'd1,
               ABSORB_FULL_PERM = 4'd2,
               ABSORB_FULL_WAIT = 4'd3,
               ABSORB_TAIL_XOR  = 4'd4,
               ABSORB_TAIL_PERM = 4'd5,
               ABSORB_TAIL_WAIT = 4'd6,
               SQUEEZE_EXTRACT  = 4'd7,
               SQUEEZE_PERM     = 4'd8,
               SQUEEZE_WAIT     = 4'd9,
               FINISH           = 4'd10;
    reg [3:0] state_r;

    integer block_idx;
    integer sq_count;
    integer p;
    integer bytes_this_block;
    reg [1599:0] tmp;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_r    <= IDLE;
            done       <= 1'b0;
            perm_start <= 1'b0;
            block_idx  <= 0;
            sq_count   <= 0;
            st         <= 1600'd0;
            out_bytes  <= {(8*OUT_LEN){1'b0}};
        end else begin
            perm_start <= 1'b0;

            case (state_r)
                IDLE: begin
                    done <= 1'b0;
                    if (start_i) begin
                        st        <= 1600'd0;
                        block_idx <= 0;
                        sq_count  <= 0;
                        if (FULL_BLOCKS > 0)
                            state_r <= ABSORB_FULL_XOR;
                        else
                            state_r <= ABSORB_TAIL_XOR;
                    end
                end

                // ---- absorb a full RATE_BYTES block, no padding ----
                ABSORB_FULL_XOR: begin
                    tmp = st;
                    for (p = 0; p < RATE_BYTES; p = p + 1)
                        tmp[8*p +: 8] = tmp[8*p +: 8] ^
                            in_bytes[8*(block_idx*RATE_BYTES + p) +: 8];
                    st      <= tmp;
                    state_r <= ABSORB_FULL_PERM;
                end
                ABSORB_FULL_PERM: begin
                    perm_start <= 1'b1;
                    state_r    <= ABSORB_FULL_WAIT;
                end
                ABSORB_FULL_WAIT: begin
                    if (perm_done) begin
                        st <= perm_out;
                        if (block_idx == FULL_BLOCKS - 1)
                            state_r <= ABSORB_TAIL_XOR;
                        else begin
                            block_idx <= block_idx + 1;
                            state_r   <= ABSORB_FULL_XOR;
                        end
                    end
                end

                // ---- absorb the final (0..RATE_BYTES-1)-byte tail,
                // XOR in the domain-separation padding, permute ----
                ABSORB_TAIL_XOR: begin
                    tmp = st;
                    for (p = 0; p < TAIL_BYTES; p = p + 1)
                        tmp[8*p +: 8] = tmp[8*p +: 8] ^
                            in_bytes[8*(FULL_BLOCKS*RATE_BYTES + p) +: 8];
                    tmp     = tmp ^ PAD_MASK;
                    st      <= tmp;
                    state_r <= ABSORB_TAIL_PERM;
                end
                ABSORB_TAIL_PERM: begin
                    perm_start <= 1'b1;
                    state_r    <= ABSORB_TAIL_WAIT;
                end
                ABSORB_TAIL_WAIT: begin
                    if (perm_done) begin
                        st      <= perm_out;
                        state_r <= SQUEEZE_EXTRACT;
                    end
                end

                // ---- squeeze OUT_LEN bytes, permuting between blocks ----
                SQUEEZE_EXTRACT: begin
                    bytes_this_block = (OUT_LEN - sq_count < RATE_BYTES) ?
                                        (OUT_LEN - sq_count) : RATE_BYTES;
                    for (p = 0; p < bytes_this_block; p = p + 1)
                        out_bytes[8*(sq_count+p) +: 8] <= st[8*p +: 8];
                    if (sq_count + bytes_this_block >= OUT_LEN) begin
                        sq_count <= sq_count + bytes_this_block;
                        state_r  <= FINISH;
                    end else begin
                        sq_count <= sq_count + bytes_this_block;
                        state_r  <= SQUEEZE_PERM;
                    end
                end
                SQUEEZE_PERM: begin
                    perm_start <= 1'b1;
                    state_r    <= SQUEEZE_WAIT;
                end
                SQUEEZE_WAIT: begin
                    if (perm_done) begin
                        st      <= perm_out;
                        state_r <= SQUEEZE_EXTRACT;
                    end
                end

                FINISH: begin
                    done    <= 1'b1;
                    state_r <= IDLE;
                end

                default: state_r <= IDLE;
            endcase
        end
    end

endmodule
