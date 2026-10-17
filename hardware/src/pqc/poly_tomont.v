`timescale 1ns/1ps
// poly_tomont.v -- matches ref/poly.c's poly_tomont() EXACTLY:
//   f = (1<<32) % KYBER_Q = 1353
//   for(i=0;i<256;i++) r[i] = montgomery_reduce((int32_t)r[i]*f);
// One coefficient per cycle, reusing the single already-verified
// montgomery_reduce core.

module poly_tomont (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start_i,
    input  wire [4095:0] coeffs_in,
    output reg  [4095:0] coeffs_out,
    output reg            done
);

  localparam signed [15:0] F = 16'sd1353; // (1<<32) mod 3329

  reg signed [15:0] mem [0:255];
  reg [8:0] i_r;

  wire signed [15:0] cur = mem[i_r];
  wire signed [31:0] prod = cur * F;
  wire signed [15:0] result;
  montgomery_reduce i_fqmul (.a(prod), .r(result));

  integer li;
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
          if (start_i) begin
            for (li = 0; li < 256; li = li + 1) mem[li] = coeffs_in[16*li +: 16];
            i_r <= 9'd0;
          end
        end
        RUN: begin
          mem[i_r] <= result;
          i_r <= i_r + 1;
        end
        DONE: begin
          for (li = 0; li < 256; li = li + 1) coeffs_out[16*li +: 16] <= mem[li];
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
      RUN:  if (i_r == 9'd255) state_d = DONE;
      DONE: state_d = IDLE;
      default: state_d = IDLE;
    endcase
  end

endmodule
