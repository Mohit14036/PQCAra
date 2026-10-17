`timescale 1ns/1ps
// kyber_poly_mul_top.v -- multiplies two polynomials in R_q =
// Z_q[X]/(X^256+1), Q=3329, via Kyber's real NTT-domain pipeline:
//
//   a_ntt = poly_ntt(a)              = ntt(a);            poly_reduce(a)   (barrett every coeff)
//   b_ntt = poly_ntt(b)              = ntt(b);             poly_reduce(b)
//   r     = poly_basemul_montgomery(a_ntt, b_ntt)
//   c     = poly_invntt_tomont(r)
//
// exactly matching ref/poly.c's poly_ntt / poly_basemul_montgomery /
// poly_invntt_tomont, chained the way indcpa.c chains them for a real
// polynomial multiplication. This is the real-Kyber-parameter (Q=3329,
// N=256) counterpart of the uploaded toy's nwc_top.v: same idea (a
// top-level FSM sequencing NTT -> pointwise-multiply -> INTT stages
// built from shared sub-engines with a shared modular-arithmetic core),
// but using Kyber's actual incomplete NTT + Montgomery-domain basemul
// instead of the toy's complete negacyclic-NTT + twist/untwist, because
// Q=3329 does not admit a complete length-256 negacyclic NTT (q-1=3328
// is not divisible by 2N=512) -- see ARA_INTEGRATION.md / package notes.
//
// Reuses the already independently-verified ntt_fwd.v, ntt_inv.v, and
// the newly-added poly_basemul_montgomery.v (all built on the single
// already-verified montgomery_reduce.v/barrett_fixed.v cores). No new
// arithmetic is introduced here -- this module is pure sequencing, one
// barrett-reduce state looping 256 times per poly_ntt() call (same
// single-state loop idiom already used in ntt_inv.v/polyvec_basemul_acc.v).

module kyber_poly_mul_top (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start_i,
    input  wire [4095:0] a_in,     // 256 x signed 16-bit, normal order
    input  wire [4095:0] b_in,
    output reg  [4095:0] c_out,    // 256 x signed 16-bit, normal order
    output reg            done
);

  // ---- ntt_fwd (shared for a and b, sequenced) ----
  reg  [4095:0] ntt_in;
  reg           ntt_start;
  wire [4095:0] ntt_out;
  wire          ntt_done;
  ntt_fwd u_ntt_fwd (.clk(clk), .rst_n(rst_n), .start_i(ntt_start),
                      .coeffs_in(ntt_in), .coeffs_out(ntt_out), .done(ntt_done));

  // ---- shared barrett-reduce pass (poly_reduce): 256 coeffs, one/cycle ----
  reg  [8:0]    br_addr;
  reg  [4095:0] br_mem;
  wire signed [15:0] br_in  = br_mem[16*br_addr +: 16];
  wire signed [15:0] br_out;
  barrett i_barrett (.a(br_in), .r(br_out));

  // ---- basemul (single pair) ----
  reg  [4095:0] bm_a_in, bm_b_in;
  reg           bm_start;
  wire [4095:0] bm_out;
  wire          bm_done;
  poly_basemul_montgomery u_basemul (.clk(clk), .rst_n(rst_n), .start_i(bm_start),
                                      .a_in(bm_a_in), .b_in(bm_b_in),
                                      .r_out(bm_out), .done(bm_done));

  // ---- ntt_inv ----
  reg  [4095:0] intt_in;
  reg           intt_start;
  wire [4095:0] intt_out;
  wire          intt_done;
  ntt_inv u_ntt_inv (.clk(clk), .rst_n(rst_n), .start_i(intt_start),
                      .coeffs_in(intt_in), .coeffs_out(intt_out), .done(intt_done));

  // ---- storage for the two inputs' post-ntt+reduce forms ----
  reg [4095:0] a_ntt_r;
  reg          which_poly;   // 0 = doing a, 1 = doing b (which ntt+reduce pass we're on)

  localparam S_IDLE      = 4'd0,
             S_NTT_GO    = 4'd1,
             S_NTT_WAIT  = 4'd2,
             S_BR        = 4'd3,
             S_BASEMUL_GO= 4'd4,
             S_BASEMUL_WT= 4'd5,
             S_INTT_GO   = 4'd6,
             S_INTT_WAIT = 4'd7,
             S_DONE      = 4'd8;

  reg [3:0] state_q, state_d;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q    <= S_IDLE;
      done       <= 1'b0;
      which_poly <= 1'b0;
    end else begin
      state_q <= state_d;

      ntt_start  <= 1'b0;
      bm_start   <= 1'b0;
      intt_start <= 1'b0;

      case (state_q)
        S_IDLE: begin
          done <= 1'b0;
          if (start_i) begin
            which_poly <= 1'b0;
            ntt_in     <= a_in;
            ntt_start  <= 1'b1;
          end
        end

        S_NTT_WAIT: if (ntt_done) begin
          br_mem  <= ntt_out;
          br_addr <= 9'd0;
        end

        S_BR: begin
          br_mem[16*br_addr +: 16] <= br_out;
          br_addr <= br_addr + 9'd1;
          if (br_addr == 9'd255) begin
            if (which_poly == 1'b0) begin
              // finished a's poly_ntt+reduce; start b's
              a_ntt_r    <= br_mem;
              which_poly <= 1'b1;
              ntt_in     <= b_in;
              ntt_start  <= 1'b1;
            end else begin
              // finished b's poly_ntt+reduce; kick off basemul
              bm_a_in  <= a_ntt_r;
              bm_b_in  <= br_mem;
              bm_start <= 1'b1;
            end
          end
        end

        S_BASEMUL_WT: if (bm_done) begin
          intt_in    <= bm_out;
          intt_start <= 1'b1;
        end

        S_INTT_WAIT: if (intt_done) begin
          c_out <= intt_out;
        end

        S_DONE: done <= 1'b1;

        default: ;
      endcase
    end
  end

  always @(*) begin
    state_d = state_q;
    case (state_q)
      S_IDLE:       if (start_i)          state_d = S_NTT_GO;
      S_NTT_GO:                            state_d = S_NTT_WAIT;
      S_NTT_WAIT:   if (ntt_done)         state_d = S_BR;
      S_BR: begin
        if (br_addr == 9'd255) begin
          if (which_poly == 1'b0) state_d = S_NTT_GO;   // go do b next
          else                     state_d = S_BASEMUL_GO;
        end
      end
      S_BASEMUL_GO:                        state_d = S_BASEMUL_WT;
      S_BASEMUL_WT: if (bm_done)          state_d = S_INTT_GO;
      S_INTT_GO:                           state_d = S_INTT_WAIT;
      S_INTT_WAIT:  if (intt_done)        state_d = S_DONE;
      S_DONE:                              state_d = S_IDLE;
      default:                             state_d = S_IDLE;
    endcase
  end

endmodule
