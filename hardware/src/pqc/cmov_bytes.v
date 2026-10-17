`timescale 1ns/1ps
// cmov_bytes.v -- matches ref/verify.c's cmov() EXACTLY for
// KYBER_SYMBYTES == 32 (the shared-secret length):
//   b = -b;   // all-1s if b==1, all-0s if b==0
//   for i: r[i] ^= b & (r[i] ^ x[i]);   // r[i]=x[i] if b==1, unchanged if b==0
// i.e. a byte-wise constant-time select: out = sel ? x : r.
// Purely combinational, registered on the next clock edge.

module cmov_bytes #(
    parameter NBYTES = 32
) (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   start_i,
    input  wire [8*NBYTES-1:0]    r_in,     // original value (kept if sel==0)
    input  wire [8*NBYTES-1:0]    x_in,     // replacement value (used if sel==1)
    input  wire                   sel_in,
    output reg  [8*NBYTES-1:0]    r_out,
    output reg                    done
);

  wire [8*NBYTES-1:0] mask = {(8*NBYTES){sel_in}};
  wire [8*NBYTES-1:0] result_comb = r_in ^ (mask & (r_in ^ x_in));

  typedef enum logic [1:0] {IDLE, RUN, DONE} state_e;
  state_e state_q, state_d;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= IDLE;
      done    <= 1'b0;
    end else begin
      state_q <= state_d;
      case (state_q)
        IDLE: done <= 1'b0;
        RUN:  r_out <= result_comb;
        DONE: done <= 1'b1;
        default: ;
      endcase
    end
  end

  always @(*) begin
    state_d = state_q;
    case (state_q)
      IDLE: if (start_i) state_d = RUN;
      RUN:  state_d = DONE;
      DONE: state_d = IDLE;
      default: state_d = IDLE;
    endcase
  end

endmodule
