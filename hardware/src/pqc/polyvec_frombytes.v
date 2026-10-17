`timescale 1ns/1ps
// polyvec_frombytes.v -- matches ref/poly.c's poly_frombytes() (called
// 3x by ref/polyvec.c's polyvec_frombytes()) for K=3: inverse of
// polyvec_tobytes.v.
//
//   r[2*i]   = (a[3*i+0] | (a[3*i+1]<<8)) & 0xFFF
//   r[2*i+1] = (a[3*i+1]>>4 | (a[3*i+2]<<4)) & 0xFFF
//
// One group of 3 input bytes (-> 2 coefficients) per cycle, 128 groups
// per polynomial x 3 polynomials = 384 cycles total.

module polyvec_frombytes (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start_i,
    input  wire [9215:0] bytes_in,    // 1152 bytes = 3*384
    output reg  [4095:0] a0_out, a1_out, a2_out,  // K=3 polys, 256 x signed 16-bit each
    output reg            done
);

  reg [7:0] mem [0:1151];
  reg [1:0] poly_idx;
  reg [6:0] grp_r;

  wire [7:0] b0 = mem[384*poly_idx + 3*grp_r + 0];
  wire [7:0] b1 = mem[384*poly_idx + 3*grp_r + 1];
  wire [7:0] b2 = mem[384*poly_idx + 3*grp_r + 2];

  wire [11:0] c0 = {b1[3:0], b0};
  wire [11:0] c1 = {b2, b1[7:4]};

  reg signed [15:0] out_mem [0:255];
  integer li;

  localparam IDLE = 2'd0, RUN = 2'd1, STORE = 2'd2, DONE = 2'd3;
  reg [1:0] state_q, state_d;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q  <= IDLE;
      done     <= 1'b0;
      poly_idx <= 2'd0;
    end else begin
      state_q <= state_d;
      case (state_q)
        IDLE: begin
          done <= 1'b0;
          if (start_i) begin
            for (li = 0; li < 1152; li = li + 1) mem[li] = bytes_in[8*li +: 8];
            poly_idx <= 2'd0;
            grp_r    <= 7'd0;
          end
        end
        RUN: begin
          out_mem[2*grp_r+0] <= $signed({4'b0, c0});
          out_mem[2*grp_r+1] <= $signed({4'b0, c1});
          if (grp_r != 7'd127)
            grp_r <= grp_r + 1;
        end
        STORE: begin
          case (poly_idx)
            2'd0: for (li = 0; li < 256; li = li + 1) a0_out[16*li +: 16] <= out_mem[li];
            2'd1: for (li = 0; li < 256; li = li + 1) a1_out[16*li +: 16] <= out_mem[li];
            2'd2: for (li = 0; li < 256; li = li + 1) a2_out[16*li +: 16] <= out_mem[li];
          endcase
          if (poly_idx != 2'd2) begin
            poly_idx <= poly_idx + 1;
            grp_r    <= 7'd0;
          end
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
      RUN:  if (grp_r == 7'd127) state_d = STORE;
      STORE: begin
        if (poly_idx == 2'd2) state_d = DONE;
        else                  state_d = RUN;
      end
      DONE: state_d = IDLE;
      default: state_d = IDLE;
    endcase
  end

endmodule
