`timescale 1ns/1ps
// polyvec_tobytes.v -- matches ref/polyvec.c's polyvec_tobytes() for
// K=3: three back-to-back poly_tobytes() serializations (12-bit/coeff,
// full precision -- this is the real public/secret-key wire format,
// used by pack_pk()/pack_sk() in indcpa.c, NOT the lossy ciphertext
// compression polyvec_compress.v handles).
//
// One group of 2 coefficients (-> 3 output bytes) per cycle, 128
// groups per polynomial x 3 polynomials = 384 cycles total.

module polyvec_tobytes (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start_i,
    input  wire [4095:0] a0_in, a1_in, a2_in,  // K=3 polys, 256 x signed 16-bit each
    output reg  [9215:0] bytes_out,             // 1152 bytes = 3*384
    output reg            done
);

  localparam KYBER_Q = 16'sd3329;

  reg signed [15:0] mem [0:255];
  reg [1:0] poly_idx;  // 0,1,2
  reg [6:0] grp_r;     // 0..127

  function automatic [11:0] posrep;
    input signed [15:0] u_in;
    reg [15:0] t;
    begin
      t = u_in[15] ? (u_in + KYBER_Q) : u_in;
      posrep = t[11:0];
    end
  endfunction

  wire [11:0] t0 = posrep(mem[2*grp_r+0]);
  wire [11:0] t1 = posrep(mem[2*grp_r+1]);

  reg [7:0] out_mem [0:1151];
  integer li;

  localparam IDLE = 2'd0, LOAD_POLY = 2'd1, RUN = 2'd2, DONE = 2'd3;
  reg [1:0] state_q, state_d;

  wire [10:0] out_base = ({9'b0, poly_idx} * 11'd384) + ({4'b0, grp_r} * 11'd3);

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
            poly_idx <= 2'd0;
            grp_r    <= 7'd0;
          end
        end
        LOAD_POLY: begin
          case (poly_idx)
            2'd0: for (li = 0; li < 256; li = li + 1) mem[li] = a0_in[16*li +: 16];
            2'd1: for (li = 0; li < 256; li = li + 1) mem[li] = a1_in[16*li +: 16];
            2'd2: for (li = 0; li < 256; li = li + 1) mem[li] = a2_in[16*li +: 16];
          endcase
          grp_r <= 7'd0;
        end
        RUN: begin
          out_mem[out_base+0] <= t0[7:0];
          out_mem[out_base+1] <= {t1[3:0], t0[11:8]};
          out_mem[out_base+2] <= t1[11:4];
          if (grp_r == 7'd127) begin
            poly_idx <= poly_idx + 1;
          end else begin
            grp_r <= grp_r + 1;
          end
        end
        DONE: begin
          for (li = 0; li < 1152; li = li + 1) bytes_out[8*li +: 8] <= out_mem[li];
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
        if (grp_r == 7'd127) begin
          if (poly_idx == 2'd2) state_d = DONE;
          else                  state_d = LOAD_POLY;
        end
      end
      DONE: state_d = IDLE;
      default: state_d = IDLE;
    endcase
  end

endmodule
