`timescale 1ns/1ps
// polyvec_compress.v -- matches ref/polyvec.c's polyvec_compress()
// EXACTLY for KYBER_POLYVECCOMPRESSEDBYTES == K*320 (K=3, the
// Kyber-768 default; 10-bit-per-coefficient compression):
//
//   for(i=0;i<KYBER_K;i++)
//     for(j=0;j<64;j++) {
//       for(k=0;k<4;k++) {
//         t[k] = a->vec[i].coeffs[4*j+k];
//         t[k] += ((int16_t)t[k]>>15) & KYBER_Q;    // positive rep
//         d0 = t[k]; d0<<=10; d0+=1665; d0*=1290167; d0>>=32;
//         t[k] = d0 & 0x3ff;
//       }
//       r[0]=t0[7:0];
//       r[1]=(t0>>8)|(t1<<2);
//       r[2]=(t1>>6)|(t2<<4);
//       r[3]=(t2>>4)|(t3<<6);
//       r[4]=(t3>>2);
//       r += 5;
//     }
//
// One group of 4 coefficients (-> 5 output bytes) per cycle, 64 groups
// per polynomial x 3 polynomials = 192 cycles total.

module polyvec_compress (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start_i,
    input  wire [4095:0] a0_in, a1_in, a2_in,  // K=3 polys, 256 x signed 16-bit each
    output reg  [7679:0] bytes_out,             // 960 bytes = 3*320
    output reg            done
);

  localparam signed [15:0] KYBER_Q = 16'sd3329;

  reg signed [15:0] mem [0:255];
  reg [1:0] poly_idx;  // 0,1,2
  reg [5:0] grp_r;     // 0..63

  function automatic [9:0] compress10;
    input signed [15:0] u_in;
    reg signed [15:0] u_pos;
    reg [63:0] d0;
    begin
      u_pos = (u_in[15]) ? (u_in + KYBER_Q) : u_in;
      d0 = {48'b0, u_pos};
      d0 = d0 << 10;
      d0 = d0 + 64'd1665;
      d0 = d0 * 64'd1290167;
      d0 = d0 >> 32;
      compress10 = d0[9:0];
    end
  endfunction

  wire [9:0] t0 = compress10(mem[4*grp_r+0]);
  wire [9:0] t1 = compress10(mem[4*grp_r+1]);
  wire [9:0] t2 = compress10(mem[4*grp_r+2]);
  wire [9:0] t3 = compress10(mem[4*grp_r+3]);

  wire [7:0] rb0 = t0[7:0];
  wire [7:0] rb1 = {t1[5:0], t0[9:8]};
  wire [7:0] rb2 = {t2[3:0], t1[9:6]};
  wire [7:0] rb3 = {t3[1:0], t2[9:4]};
  wire [7:0] rb4 = t3[9:2];

  reg [7:0] out_mem [0:959];
  integer li;

  typedef enum logic [1:0] {IDLE, LOAD_POLY, RUN, DONE} state_e;
  state_e state_q, state_d;

  wire [9:0] out_base = ({4'b0, poly_idx} * 10'd320) + ({4'b0, grp_r} * 10'd5);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= IDLE;
      done    <= 1'b0;
      poly_idx <= 2'd0;
    end else begin
      state_q <= state_d;
      case (state_q)
        IDLE: begin
          done <= 1'b0;
          if (start_i) begin
            poly_idx <= 2'd0;
            grp_r    <= 6'd0;
          end
        end
        LOAD_POLY: begin
          case (poly_idx)
            2'd0: for (li = 0; li < 256; li = li + 1) mem[li] = a0_in[16*li +: 16];
            2'd1: for (li = 0; li < 256; li = li + 1) mem[li] = a1_in[16*li +: 16];
            2'd2: for (li = 0; li < 256; li = li + 1) mem[li] = a2_in[16*li +: 16];
          endcase
          grp_r <= 6'd0;
        end
        RUN: begin
          out_mem[out_base+0] <= rb0;
          out_mem[out_base+1] <= rb1;
          out_mem[out_base+2] <= rb2;
          out_mem[out_base+3] <= rb3;
          out_mem[out_base+4] <= rb4;
          if (grp_r == 6'd63) begin
            poly_idx <= poly_idx + 1;
          end else begin
            grp_r <= grp_r + 1;
          end
        end
        DONE: begin
          for (li = 0; li < 960; li = li + 1) bytes_out[8*li +: 8] <= out_mem[li];
          done <= 1'b1;
        end
        default: ;
      endcase
    end
  end

  always @(*) begin
    state_d = state_q;
    case (state_q)
      IDLE: if (start_i) state_d = LOAD_POLY;
      LOAD_POLY: state_d = RUN;
      RUN: begin
        if (grp_r == 6'd63) begin
          if (poly_idx == 2'd2) state_d = DONE;
          else                  state_d = LOAD_POLY;
        end
      end
      DONE: state_d = IDLE;
      default: state_d = IDLE;
    endcase
  end

endmodule
