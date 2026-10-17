`timescale 1ns/1ps
// ct_verify.v -- matches ref/verify.c's verify() EXACTLY for
// KYBER_INDCPA_BYTES == 1088 (K=3 ciphertext length):
//   r = 0; for i: r |= a[i] ^ b[i];
//   return (-(uint64_t)r) >> 63;   // 1 if any byte differs, 0 if all equal
// Purely combinational (1088 XORs OR-reduced), registered on the next
// clock edge for a one-cycle-latency interface consistent with the
// rest of the pipeline.

module ct_verify #(
    parameter CTBYTES = 1088
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start_i,
    input  wire [8*CTBYTES-1:0]    ct_a_in,
    input  wire [8*CTBYTES-1:0]    ct_b_in,
    output reg                     fail_out,   // 1 = mismatch, 0 = match (matches verify()'s return)
    output reg                     done
);

  wire [8*CTBYTES-1:0] xor_bits = ct_a_in ^ ct_b_in;
  wire mismatch = |xor_bits;   // reduction-OR of every bit -- 1 iff any byte differs

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
        RUN:  fail_out <= mismatch;
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
