`timescale 1ns/1ps
// poly_decompress.v -- matches ref/poly.c's poly_decompress() EXACTLY
// for KYBER_POLYCOMPRESSEDBYTES == 128:
//
//   for(i=0;i<128;i++) {
//     r[2*i+0] = (((a[0]&15)*KYBER_Q)+8) >> 4;
//     r[2*i+1] = (((a[0]>>4)*KYBER_Q)+8) >> 4;
//     a += 1;
//   }
//
// One input byte (-> 2 output coefficients) processed per cycle, 128
// cycles total.

module poly_decompress (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start_i,
    input  wire [1023:0] bytes_in,    // 128 bytes
    output reg  [4095:0] coeffs_out,  // 256 x signed 16-bit
    output reg            done
);

  localparam KYBER_Q = 16'd3329;

  reg [7:0] mem [0:127];
  reg [6:0] i_r;  // 0..127

  wire [3:0] lo = mem[i_r][3:0];
  wire [3:0] hi = mem[i_r][7:4];
  wire [15:0] c0 = (({12'b0, lo} * KYBER_Q) + 16'd8) >> 4;
  wire [15:0] c1 = (({12'b0, hi} * KYBER_Q) + 16'd8) >> 4;

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
            for (li = 0; li < 128; li = li + 1) mem[li] = bytes_in[8*li +: 8];
            i_r <= 7'd0;
          end
        end
        RUN: begin
          out_mem[2*i_r+0] <= c0[15:0];
          out_mem[2*i_r+1] <= c1[15:0];
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
      RUN:  if (i_r == 7'd127) state_d = DONE;
      DONE: state_d = IDLE;
      default: state_d = IDLE;
    endcase
  end

endmodule
