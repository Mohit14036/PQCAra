`timescale 1ns / 1ps
//------------------------------------------------------------------------
// intt_engine.v
// Iterative in-place Gentleman-Sande (DIF) inverse NTT.
//   input  order : bit-reversed
//   output order : natural
// Butterfly:  u' = u + v (mod q)
//             v' = w*(u - v) (mod q)
//
// Twiddle ROM address for stage `stage`, block `blk`:
//      addr = N - (N >> stage) + blk
// matching gen_gs_twiddles() in nwc_ntt_ref.py (tw_gs.mem).
//
// Final N^-1 scaling is applied as a separate modq_mul with a constant
// (N_INV) after this engine's `done` pulse -- see nwc_top.v.
//------------------------------------------------------------------------
module intt_engine #(
    parameter Q     = 17,
    parameter WIDTH = 5,
    parameter N     = 8,
    parameter LOGN  = 3,
    parameter TWFILE = "tw_gs.mem"
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  start,
    output reg                   done,

    input  wire                  ld_en,
    input  wire [LOGN-1:0]       ld_addr,
    input  wire [WIDTH-1:0]      ld_data,

    input  wire [LOGN-1:0]       rd_addr,
    output wire [WIDTH-1:0]      rd_data
);

    reg [WIDTH-1:0] mem [0:N-1];
    reg [WIDTH-1:0] twiddle_rom [0:N-2];
    initial $readmemb(TWFILE, twiddle_rom);

    assign rd_data = mem[rd_addr];

    localparam S_IDLE = 2'd0, S_RUN = 2'd1, S_DONE = 2'd2;
    reg [1:0] state;

    reg [LOGN-1:0] stage;   // 0 .. LOGN-1 ; length = 1<<stage
    reg [LOGN-1:0] blk;
    reg [LOGN-1:0] j;

    wire [LOGN-1:0] length_w = (1 << stage);
    wire [LOGN-1:0] rom_addr = N - (N >> stage) + blk;

    wire [LOGN-1:0] u_idx = blk * (length_w << 1) + j;
    wire [LOGN-1:0] v_idx = u_idx + length_w;

    wire [WIDTH-1:0] u_in = mem[u_idx];
    wire [WIDTH-1:0] v_in = mem[v_idx];
    wire [WIDTH-1:0] w_in = twiddle_rom[rom_addr];

    wire [WIDTH-1:0] sum_uv, diff_uv, v_out;

    modq_add #(.Q(Q), .WIDTH(WIDTH)) add_i (.a(u_in), .b(v_in), .sum_mod_q(sum_uv));
    modq_sub #(.Q(Q), .WIDTH(WIDTH)) sub_i (.a(u_in), .b(v_in), .diff_mod_q(diff_uv));
    modq_mul #(.Q(Q), .WIDTH(WIDTH)) mul_i (.a(w_in), .b(diff_uv), .prod_mod_q(v_out));

    wire [LOGN-1:0] blocks_this_stage = N >> (stage + 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; done <= 1'b0;
            stage <= 0; blk <= 0; j <= 0;
        end else begin
            if (ld_en) mem[ld_addr] <= ld_data;

            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        state <= S_RUN; stage <= 0; blk <= 0; j <= 0;
                    end
                end

                S_RUN: begin
                    mem[u_idx] <= sum_uv;
                    mem[v_idx] <= v_out;

                    if (j == length_w - 1) begin
                        j <= 0;
                        if (blk == blocks_this_stage - 1) begin
                            blk <= 0;
                            if (stage == LOGN - 1) begin
                                state <= S_DONE;
                            end else begin
                                stage <= stage + 1'b1;
                            end
                        end else begin
                            blk <= blk + 1'b1;
                        end
                    end else begin
                        j <= j + 1'b1;
                    end
                end

                S_DONE: begin
                    done <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
