`timescale 1ns/1ps
// rej_uniform.v -- sequential wrapper around the already-built
// rej_uniform_parallel combinational compaction unit, matching
// ref/indcpa.c's rej_uniform() EXACTLY:
//
//   ctr = pos = 0;
//   while(ctr < len && pos + 3 <= buflen) {
//     val0 = ((buf[pos+0]>>0) | (buf[pos+1]<<8)) & 0xFFF;
//     val1 = ((buf[pos+1]>>4) | (buf[pos+2]<<4)) & 0xFFF;
//     pos += 3;
//     if(val0 < KYBER_Q) r[ctr++] = val0;
//     if(ctr < len && val1 < KYBER_Q) r[ctr++] = val1;
//   }
//   return ctr;
//
// Processes 4 groups (12 bytes -> up to 8 candidates) per cycle through
// rej_uniform_parallel, which compacts the 0-8 survivors of that cycle
// IN ORDER (prefix-sum compaction is order-preserving, matching the
// real code's group-by-group, val0-then-val1 serial order). Each cycle
// we then accept only the first min(out_count, len-ctr) of that cycle's
// compacted survivors into r_mem -- this reproduces the real code's
// boundary behaviour exactly, including the case where val0 is the
// candidate that reaches len and a still-valid val1 right after it must
// be discarded.
//
// BUFLEN is fixed at compile time to 504 bytes = GEN_MATRIX_NBLOCKS(3)
// * XOF_BLOCKBYTES(168), the real buffer size gen_matrix() uses for its
// first (usually sufficient) squeeze call. 504 / 12 = 42 whole cycles,
// no remainder handling needed for this real, fixed-size buffer.

module rej_uniform #(
    parameter KYBER_Q = 3329,
    parameter BUFLEN  = 504,
    parameter LEN     = 256
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start_i,
    input  wire [8*BUFLEN-1:0] buf_in,   // BUFLEN bytes, buf_in[8*p +: 8] = buf[p]
    output reg  [16*LEN-1:0]   r_out,    // up to LEN accepted 12-bit-in-16-bit coeffs
    output reg  [8:0]          ctr_out,  // final ctr (<= LEN)
    output reg                 done
);

  localparam NGROUPS_PER_CYCLE = 4;
  localparam TOTAL_GROUPS = BUFLEN / 3;              // 168
  localparam TOTAL_CYCLES = TOTAL_GROUPS / NGROUPS_PER_CYCLE; // 42

  reg [7:0] buf_mem [0:BUFLEN-1];
  reg [15:0] r_mem [0:LEN-1];

  reg [8:0]  cyc_r;     // 0..TOTAL_CYCLES
  reg [8:0]  ctr_r;     // 0..LEN

  // ---- feed this cycle's 12 bytes (4 groups) to the combinational unit ----
  wire [11:0][7:0] buf_bytes;
  genvar gi;
  generate
    for (gi = 0; gi < 12; gi = gi + 1) begin : gen_feed
      assign buf_bytes[gi] = buf_mem[cyc_r*12 + gi];
    end
  endgenerate

  wire [7:0][15:0] out_coeffs;
  wire [3:0]        out_count;

  rej_uniform_parallel #(.KYBER_Q(KYBER_Q)) i_rup (
      .buf_bytes(buf_bytes),
      .out_coeffs(out_coeffs),
      .out_count(out_count)
  );

  // how many of this cycle's compacted survivors we can actually take
  wire [8:0] remaining   = LEN - ctr_r;
  wire [3:0] take_this   = (out_count > remaining[3:0] && remaining < 9'd8)
                              ? remaining[3:0] : out_count;

  integer wi;

  typedef enum logic [1:0] {IDLE, LOAD, RUN, DONE} state_e;
  state_e state_q, state_d;
  integer li;

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
            for (li = 0; li < BUFLEN; li = li + 1)
              buf_mem[li] = buf_in[8*li +: 8];
            cyc_r <= 9'd0;
            ctr_r <= 9'd0;
          end
        end
        RUN: begin
          for (wi = 0; wi < 8; wi = wi + 1)
            if (wi < take_this)
              r_mem[ctr_r + wi] <= out_coeffs[wi];
          ctr_r <= ctr_r + take_this;
          cyc_r <= cyc_r + 1;
        end
        DONE: begin
          for (li = 0; li < LEN; li = li + 1)
            r_out[16*li +: 16] <= r_mem[li];
          ctr_out <= ctr_r;
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
      RUN: begin
        if (ctr_r >= LEN || cyc_r == TOTAL_CYCLES - 1)
          state_d = DONE;
      end
      DONE: state_d = IDLE;
      default: state_d = IDLE;
    endcase
  end

endmodule
