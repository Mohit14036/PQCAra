`timescale 1ns/1ps
// poly_frommsg.v -- matches ref/poly.c's poly_frommsg() EXACTLY:
//
//   for(i=0;i<32;i++)
//     for(j=0;j<8;j++)
//       r[8*i+j] = ((msg[i]>>j)&1) ? (KYBER_Q+1)/2 : 0;
//
// (cmov_int16(r, val, bit) sets r=val iff bit==1, else leaves r as the
// 0 it was just initialized to -- so this is exactly a per-bit select.)
// One input byte (-> 8 output coefficients) processed per cycle, 32
// cycles total.

module poly_frommsg (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start_i,
    input  wire [255:0] msg_in,      // 32 bytes
    output reg  [4095:0] coeffs_out, // 256 x signed 16-bit
    output reg            done
);

  localparam signed [15:0] HALFQ = 16'sd1665;  // (KYBER_Q+1)/2

  reg [7:0] mem [0:31];
  reg [4:0] i_r;  // 0..31

  wire [7:0] byte_cur = mem[i_r];

  reg signed [15:0] out_mem [0:255];
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
            for (li = 0; li < 32; li = li + 1) mem[li] <= msg_in[8*li +: 8];
            i_r <= 5'd0;
          end
        end
        RUN: begin
          out_mem[8*i_r+0] <= byte_cur[0] ? HALFQ : 16'sd0;
          out_mem[8*i_r+1] <= byte_cur[1] ? HALFQ : 16'sd0;
          out_mem[8*i_r+2] <= byte_cur[2] ? HALFQ : 16'sd0;
          out_mem[8*i_r+3] <= byte_cur[3] ? HALFQ : 16'sd0;
          out_mem[8*i_r+4] <= byte_cur[4] ? HALFQ : 16'sd0;
          out_mem[8*i_r+5] <= byte_cur[5] ? HALFQ : 16'sd0;
          out_mem[8*i_r+6] <= byte_cur[6] ? HALFQ : 16'sd0;
          out_mem[8*i_r+7] <= byte_cur[7] ? HALFQ : 16'sd0;
          i_r <= i_r + 1;
        end
        DONE: begin
          for (li = 0; li < 256; li = li + 1) coeffs_out[16*li +: 16] <= out_mem[li];
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
      RUN:  if (i_r == 5'd31) state_d = DONE;
      DONE: state_d = IDLE;
      default: state_d = IDLE;
    endcase
  end

endmodule
