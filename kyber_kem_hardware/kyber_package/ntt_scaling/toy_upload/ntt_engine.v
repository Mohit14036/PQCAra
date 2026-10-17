`timescale 1ns / 1ps
//------------------------------------------------------------------------
// ntt_engine.v
// Iterative in-place Cooley-Tukey (DIT) forward NTT.
//   input  order : natural
//   output order : bit-reversed
// One butterfly per clock cycle (simple sequencer, easy to verify first;
// unroll/pipeline later once functionally verified against Python).
//
// Twiddle ROM address for stage `stage`, block `blk` is:
//      addr = (1<<stage) - 1 + blk
// which exactly matches the flattened twiddle table produced by
// gen_ct_twiddles() in nwc_ntt_ref.py (tw_ct.mem).
//
// References: eprint 2016/504 (NTT), eprint 2013/866 (iterative CT form)
//------------------------------------------------------------------------
module ntt_engine #(
    parameter Q     = 17,
    parameter WIDTH = 5,
    parameter N     = 8,
    parameter LOGN  = 3,               // log2(N)
    parameter TWFILE = "tw_ct.mem"
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  start,          // pulse to begin
    output reg                   done,

    // simple parallel load/read of the N-point memory
    input  wire                  ld_en,
    input  wire [LOGN-1:0]       ld_addr,
    input  wire [WIDTH-1:0]      ld_data,

    input  wire [LOGN-1:0]       rd_addr,
    output wire [WIDTH-1:0]      rd_data
);

    // ---------------------------------------------------------------
    // Data memory (N points) and twiddle ROM (N-1 points)
    // ---------------------------------------------------------------
    reg [WIDTH-1:0] mem [0:N-1];
    reg [WIDTH-1:0] twiddle_rom [0:N-2];

    initial $readmemb(TWFILE, twiddle_rom);

    assign rd_data = mem[rd_addr];

    // ---------------------------------------------------------------
    // FSM state
    // ---------------------------------------------------------------
    localparam S_IDLE = 2'd0, S_RUN = 2'd1, S_DONE = 2'd2;
    reg [1:0] state;

    reg [LOGN-1:0] stage;      // 0 .. LOGN-1
    reg [LOGN-1:0] blk;        // block index within a stage
    reg [LOGN-1:0] j;          // index within a block

    wire [LOGN-1:0] length_w = N >> (stage + 1);      // butterflies per block, stride
    wire [LOGN-1:0] rom_addr = (({{(LOGN-1){1'b0}},1'b1} << stage) - 1'b1) + blk;

    wire [LOGN-1:0] u_idx = blk * (length_w << 1) + j;
    wire [LOGN-1:0] v_idx = u_idx + length_w;

    wire [WIDTH-1:0] u_in = mem[u_idx];
    wire [WIDTH-1:0] v_in = mem[v_idx];
    wire [WIDTH-1:0] w_in = twiddle_rom[rom_addr];
    wire [WIDTH-1:0] u_out, v_out;

    butterfly_ct #(.Q(Q), .WIDTH(WIDTH)) bf (
        .u_in(u_in), .v_in(v_in), .w_in(w_in),
        .u_out(u_out), .v_out(v_out)
    );

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done  <= 1'b0;
            stage <= 0; blk <= 0; j <= 0;
        end else begin
            if (ld_en) begin
                mem[ld_addr] <= ld_data;
            end

            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        state <= S_RUN;
                        stage <= 0; blk <= 0; j <= 0;
                    end
                end

                S_RUN: begin
                    // commit this cycle's butterfly result
                    mem[u_idx] <= u_out;
                    mem[v_idx] <= v_out;

                    // advance j -> blk -> stage counters
                    if (j == length_w - 1) begin
                        j <= 0;
                        if (blk == (({{(LOGN-1){1'b0}},1'b1} << stage) - 1'b1)) begin
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
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
