`timescale 1ns/1ps
// poly_compress.v -- matches ref/poly.c's poly_compress() EXACTLY for
// KYBER_POLYCOMPRESSEDBYTES == 128 (the K=3/Kyber-768 default):
//
//   for(i=0;i<32;i++) {
//     for(j=0;j<8;j++) {
//       u = a->coeffs[8*i+j];
//       u += (u>>15) & KYBER_Q;             // map to positive rep
//       d0 = u<<4; d0 += 1665; d0 *= 80635; d0 >>= 28;
//       t[j] = d0 & 0xf;
//     }
//     r[0]=t[0]|(t[1]<<4); r[1]=t[2]|(t[3]<<4);
//     r[2]=t[4]|(t[5]<<4); r[3]=t[6]|(t[7]<<4);
//     r += 4;
//   }
//
// One group of 8 coefficients (4 output bytes) processed per cycle,
// 32 cycles total. Purely combinational per-coefficient datapath
// (multiply-add-shift, no reduction core needed), replicated x8,
// walked by a simple FSM -- matches realistic resource-shared hardware
// for this cheap arithmetic (unlike Montgomery/Barrett reduction, this
// needs no shared multiplier core to make sense to time-share).

module poly_compress (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start_i,
    input  wire [4095:0] coeffs_in,   // 256 x signed 16-bit
    output reg  [1023:0] bytes_out,   // 128 bytes
    output reg            done
);

  localparam KYBER_Q = 16'sd3329;

  reg signed [15:0] mem [0:255];
  reg [4:0] grp_r;  // 0..31

  function automatic [3:0] compress4;
    input signed [15:0] u_in;
    reg signed [15:0] u_pos;
    reg [31:0] d0;
    begin
      u_pos = (u_in[15]) ? (u_in + KYBER_Q) : u_in;
      d0 = ({16'b0, u_pos} << 4);
      d0 = d0 + 32'd1665;
      d0 = d0 * 32'd80635;
      d0 = d0 >> 28;
      compress4 = d0[3:0];
    end
  endfunction

  wire [3:0] t0 = compress4(mem[8*grp_r+0]);
  wire [3:0] t1 = compress4(mem[8*grp_r+1]);
  wire [3:0] t2 = compress4(mem[8*grp_r+2]);
  wire [3:0] t3 = compress4(mem[8*grp_r+3]);
  wire [3:0] t4 = compress4(mem[8*grp_r+4]);
  wire [3:0] t5 = compress4(mem[8*grp_r+5]);
  wire [3:0] t6 = compress4(mem[8*grp_r+6]);
  wire [3:0] t7 = compress4(mem[8*grp_r+7]);

  reg [7:0] out_mem [0:127];
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
            grp_r <= 5'd0;
          end
        end
        RUN: begin
          out_mem[4*grp_r+0] <= {t1, t0};
          out_mem[4*grp_r+1] <= {t3, t2};
          out_mem[4*grp_r+2] <= {t5, t4};
          out_mem[4*grp_r+3] <= {t7, t6};
          grp_r <= grp_r + 1;
        end
        DONE: begin
          for (li = 0; li < 128; li = li + 1) bytes_out[8*li +: 8] <= out_mem[li];
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
      RUN:  if (grp_r == 5'd31) state_d = DONE;
      DONE: state_d = IDLE;
      default: state_d = IDLE;
    endcase
  end

endmodule
