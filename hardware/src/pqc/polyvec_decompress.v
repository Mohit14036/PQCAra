`timescale 1ns/1ps
// polyvec_decompress.v -- matches ref/polyvec.c's polyvec_decompress()
// EXACTLY for KYBER_POLYVECCOMPRESSEDBYTES == K*320 (K=3):
//
//   for(i=0;i<KYBER_K;i++)
//     for(j=0;j<64;j++) {
//       t[0] = a[0] | (a[1]<<8);
//       t[1] = (a[1]>>2) | (a[2]<<6);
//       t[2] = (a[2]>>4) | (a[3]<<4);
//       t[3] = (a[3]>>6) | (a[4]<<2);
//       a += 5;
//       for(k=0;k<4;k++)
//         r->vec[i].coeffs[4*j+k] = ((t[k]&0x3FF)*KYBER_Q + 512) >> 10;
//     }
//
// One group of 5 input bytes (-> 4 output coefficients) per cycle, 64
// groups per polynomial x 3 polynomials = 192 cycles total.

module polyvec_decompress (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start_i,
    input  wire [7679:0] bytes_in,               // 960 bytes = 3*320
    output reg  [4095:0] r0_out, r1_out, r2_out,  // K=3 polys, 256 x signed 16-bit each
    output reg            done
);

  localparam [15:0] KYBER_Q = 16'd3329;

  reg [7:0] mem [0:959];
  reg [1:0] poly_idx;  // 0,1,2
  reg [5:0] grp_r;     // 0..63

  wire [9:0] in_base = ({4'b0, poly_idx} * 10'd320) + ({4'b0, grp_r} * 10'd5);

  wire [7:0] a0 = mem[in_base+0];
  wire [7:0] a1 = mem[in_base+1];
  wire [7:0] a2 = mem[in_base+2];
  wire [7:0] a3 = mem[in_base+3];
  wire [7:0] a4 = mem[in_base+4];

  wire [9:0] t0raw = {a1[1:0], a0};
  wire [9:0] t1raw = {a2[3:0], a1[7:2]};
  wire [9:0] t2raw = {a3[5:0], a2[7:4]};
  wire [9:0] t3raw = {a4[7:0], a3[7:6]};

  function automatic signed [15:0] decompress10;
    input [9:0] t_in;
    reg [31:0] r32;
    begin
      r32 = ({22'b0, t_in} * {16'b0, KYBER_Q}) + 32'd512;
      r32 = r32 >> 10;
      decompress10 = $signed({1'b0, r32[14:0]});
    end
  endfunction

  wire signed [15:0] c0 = decompress10(t0raw);
  wire signed [15:0] c1 = decompress10(t1raw);
  wire signed [15:0] c2 = decompress10(t2raw);
  wire signed [15:0] c3 = decompress10(t3raw);

  reg signed [15:0] out_mem [0:255];
  integer li;

  // NOTE: out_mem is written non-blocking during RUN; a same-cycle read
  // of out_mem to copy it into r*_out would see the PREVIOUS cycle's
  // contents (missing the last group just issued). So the copy-out for
  // each polynomial happens one cycle later, in a dedicated STORE state,
  // after the last group's non-blocking write has actually landed.
  typedef enum logic [1:0] {IDLE, RUN, STORE, DONE} state_e;
  state_e state_q, state_d;

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
            for (li = 0; li < 960; li = li + 1) mem[li] = bytes_in[8*li +: 8];
            poly_idx <= 2'd0;
            grp_r    <= 6'd0;
          end
        end
        RUN: begin
          out_mem[4*grp_r+0] <= c0;
          out_mem[4*grp_r+1] <= c1;
          out_mem[4*grp_r+2] <= c2;
          out_mem[4*grp_r+3] <= c3;
          if (grp_r != 6'd63)
            grp_r <= grp_r + 1;
        end
        STORE: begin
          case (poly_idx)
            2'd0: for (li = 0; li < 256; li = li + 1) r0_out[16*li +: 16] <= out_mem[li];
            2'd1: for (li = 0; li < 256; li = li + 1) r1_out[16*li +: 16] <= out_mem[li];
            2'd2: for (li = 0; li < 256; li = li + 1) r2_out[16*li +: 16] <= out_mem[li];
            default: ;
          endcase
          poly_idx <= poly_idx + 1;
          grp_r    <= 6'd0;
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
      RUN:  if (grp_r == 6'd63) state_d = STORE;
      STORE: begin
        if (poly_idx == 2'd2) state_d = DONE;
        else                  state_d = RUN;
      end
      DONE: state_d = IDLE;
      default: state_d = IDLE;
    endcase
  end

endmodule
