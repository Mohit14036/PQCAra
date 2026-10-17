// =============================================================
// poly_cbd_eta2.v -- centered binomial distribution sampler, eta=2.
// Matches ref/cbd.c's cbd2(): consumes 128 bytes (2*KYBER_N/4) of
// real PRF output and produces 256 coefficients in {-2,-1,0,1,2}.
//
// One group of 4 input bytes (-> 8 output coefficients) processed
// per cycle, via the same SWAR popcount-of-bit-pairs trick as the
// real C code:
//   t = load32_le(buf[4*i .. 4*i+3])
//   d = (t & 0x55555555) + ((t>>1) & 0x55555555)   // each 2-bit
//       lane of d now holds the popcount (0..2) of the matching
//       2-bit lane of t
//   for j in 0..7: a = d[4j+1:4j], b = d[4j+3:4j+2]; coeff = a - b
// =============================================================

module poly_cbd_eta2 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start_i,
    input  wire [1023:0] buf_in,     // 128 bytes, little-endian byte order (buf_in[7:0]=byte0, ...)
    output reg  [4095:0] coeffs_out, // 256 x 16-bit signed coefficients
    output reg           done
);

    localparam IDLE = 2'd0, RUN = 2'd1, FINISH = 2'd2;
    reg [1:0] state_r;
    integer i, j;
    reg [31:0] t, d;
    reg signed [15:0] a, b;
    reg [4095:0] coeffs_mem;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_r <= IDLE;
            done    <= 1'b0;
            i       <= 0;
        end else begin
            case (state_r)
                IDLE: begin
                    done <= 1'b0;
                    if (start_i) begin
                        i       <= 0;
                        state_r <= RUN;
                    end
                end

                RUN: begin
                    t = buf_in[32*i +: 32];
                    d = (t & 32'h55555555) + ((t >> 1) & 32'h55555555);
                    for (j = 0; j < 8; j = j + 1) begin
                        a = $signed({14'd0, d[4*j+1 -: 2]});
                        b = $signed({14'd0, d[4*j+3 -: 2]});
                        coeffs_mem[16*(8*i+j) +: 16] <= a - b;
                    end
                    if (i == 31) begin
                        state_r <= FINISH;
                    end else begin
                        i <= i + 1;
                    end
                end

                FINISH: begin
                    coeffs_out <= coeffs_mem;
                    done       <= 1'b1;
                    state_r    <= IDLE;
                end

                default: state_r <= IDLE;
            endcase
        end
    end

endmodule
