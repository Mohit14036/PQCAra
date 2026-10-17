`timescale 1ns/1ps
// poly_add.v -- matches ref/poly.c's poly_add() EXACTLY:
//   for(i=0;i<256;i++) r[i] = a[i] + b[i];   // no reduction
// Purely combinational (256 independent 16-bit adders); registered on
// the next clock edge into coeffs_out for consistency with the other
// pipeline stages' one-cycle-latency interface.

module poly_add (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start_i,
    input  wire [4095:0] a_in,
    input  wire [4095:0] b_in,
    output reg  [4095:0] coeffs_out,
    output reg            done
);

  genvar gi;
  wire [4095:0] sum_comb;
  generate
    for (gi = 0; gi < 256; gi = gi + 1) begin : gen_add
      assign sum_comb[16*gi +: 16] =
          $signed(a_in[16*gi +: 16]) + $signed(b_in[16*gi +: 16]);
    end
  endgenerate

  typedef enum logic [1:0] {IDLE, RUN, DONE} state_e;
  state_e state_q, state_d;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= IDLE;
      done    <= 1'b0;
    end else begin
      state_q <= state_d;
      case (state_q)
        IDLE: begin
          done <= 1'b0;
        end
        RUN: begin
          coeffs_out <= sum_comb;
        end
        DONE: begin
          done <= 1'b1;
        end
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
