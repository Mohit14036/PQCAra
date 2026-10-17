`timescale 1ns/1ps
// poly_tomsg.v -- matches ref/poly.c's poly_tomsg() EXACTLY:
//
//   for(i=0;i<32;i++) {
//     msg[i] = 0;
//     for(j=0;j<8;j++) {
//       t = a->coeffs[8*i+j];      // int16_t -> uint32_t (sign-extends,
//                                   // then reinterpreted mod 2^32 -- the
//                                   // real code relies on this wraparound,
//                                   // it does NOT canonicalize to positive
//                                   // representative first, unlike compress)
//       t <<= 1; t += 1665; t *= 80635; t >>= 28; t &= 1;
//       msg[i] |= t << j;
//     }
//   }
//
// All arithmetic is done in explicit 32-bit unsigned regs so Verilog's
// self-determined multiply width matches C's uint32_t wraparound
// exactly (see polyvec_basemul_acc.v's comment on the analogous 16x16
// truncation bug -- here we WANT the 32-bit truncation, so the operands
// are declared 32-bit on purpose).
//
// One group of 8 coefficients (-> 1 output byte) processed per cycle,
// 32 cycles total.

module poly_tomsg (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start_i,
    input  wire [4095:0] coeffs_in,  // 256 x signed 16-bit
    output reg  [255:0]  msg_out,    // 32 bytes
    output reg            done
);

  reg signed [15:0] mem [0:255];
  reg [4:0] grp_r;  // 0..31

  function automatic tomsg_bit;
    input signed [15:0] coeff;
    reg [31:0] t;
    begin
      t = {{16{coeff[15]}}, coeff};  // sign-extend to 32 bits (matches int16_t->uint32_t)
      t = t << 1;
      t = t + 32'd1665;
      t = t * 32'd80635;             // both operands 32-bit -> 32-bit wraparound, matches uint32_t
      t = t >> 28;
      tomsg_bit = t[0];
    end
  endfunction

  wire b0 = tomsg_bit(mem[8*grp_r+0]);
  wire b1 = tomsg_bit(mem[8*grp_r+1]);
  wire b2 = tomsg_bit(mem[8*grp_r+2]);
  wire b3 = tomsg_bit(mem[8*grp_r+3]);
  wire b4 = tomsg_bit(mem[8*grp_r+4]);
  wire b5 = tomsg_bit(mem[8*grp_r+5]);
  wire b6 = tomsg_bit(mem[8*grp_r+6]);
  wire b7 = tomsg_bit(mem[8*grp_r+7]);

  reg [7:0] out_mem [0:31];
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
          out_mem[grp_r] <= {b7, b6, b5, b4, b3, b2, b1, b0};
          grp_r <= grp_r + 1;
        end
        DONE: begin
          for (li = 0; li < 32; li = li + 1) msg_out[8*li +: 8] <= out_mem[li];
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
