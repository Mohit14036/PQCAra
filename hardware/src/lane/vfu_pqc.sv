// vfu_pqc.sv -- Post-Quantum Cryptography Vector Functional Unit (Kyber / ML-KEM-768)
//
// A per-lane functional unit for the Ara RVV vector processor. It sits in
// the lane datapath next to the ALU (valu.sv) and the multiplier/FPU
// (vmfpu.sv) and shares their interface shape: it accepts one decoded
// vector instruction from the lane sequencer, reads its source operands
// from the PqcA/PqcB operand queues, and writes results back through the
// VRF write port. Destination addresses use the same
// ara_pkg::vaddr(vid, NrLanes, VLEN) mapping as valu.sv / operand_requester.sv.
//
// It implements the 29 VPQC_* opcodes (ara_pkg::ara_op_e) that make
// ML-KEM-768 (FIPS 203) expressible as a straight-line sequence of vector
// instructions: SHA-3 / SHAKE hashing, forward and inverse NTT, Montgomery
// and Barrett reduction, CBD noise sampling, rejection sampling, base
// multiply-accumulate, polynomial (de)compression and (de)serialization,
// and the constant-time verify/move used by the Fujisaki-Okamoto transform.
// The arithmetic itself lives in the verified primitive blocks under
// hardware/src/pqc/*.v; this unit feeds them operands from the VRF, runs the
// selected block, and writes the outputs back.
//
// Two operand classes:
//   - Elementwise ops (VPQC_MONTMUL, VPQC_BARRETT): four 16-bit Z_q
//     coefficients packed per 64-bit element, processed like an ALU op.
//   - Gather / compute / scatter ops (every other opcode): the op gathers a
//     fixed number of consecutive 64-bit words (n_in), runs one whole-block
//     primitive -- e.g. Keccak-f1600 consumes all 25 state lanes at once,
//     CBD consumes a full 128-byte PRF block -- and scatters n_out words
//     back. The per-op word counts are defined by the n_in()/n_out() tables
//     below, which also drive how many operands the operand requester fetches.

module vfu_pqc import ara_pkg::*; import cf_math_pkg::idx_width; #(
    parameter int unsigned NrLanes = 4,
    // VLEN sizes the VRF destination-address mapping
    // (ara_pkg::vaddr(vid, NrLanes, VLEN)), the same function valu.sv and
    // operand_requester.sv use; it must be driven with the real VLEN so
    // scattered result words land at the correct VRF addresses.
    parameter int unsigned VLEN    = 1024,
    parameter type         vaddr_t = logic,
    parameter type         vfu_operation_t = logic
  ) (
    input  logic                    clk_i,
    input  logic                    rst_ni,
    input  logic [idx_width(NrLanes)-1:0] lane_id_i,

    // Interface with the lane sequencer (same shape as valu.sv)
    input  vfu_operation_t          vfu_operation_i,
    input  logic                    vfu_operation_valid_i,
    output logic                    pqc_ready_o,
    output logic       [NrVInsn-1:0] pqc_vinsn_done_o,

    // Interface with the operand queues: PqcA, PqcB (ara_pkg::opqueue_e)
    input  elen_t       [1:0]        pqc_operand_i,
    input  logic         [1:0]        pqc_operand_valid_i,
    output logic         [1:0]        pqc_operand_ready_o,

    // Interface with the vector register file (same shape as
    // alu_result_req_o/... in valu.sv)
    output logic                     pqc_result_req_o,
    output vid_t                     pqc_result_id_o,
    output vaddr_t                   pqc_result_addr_o,
    output elen_t                    pqc_result_wdata_o,
    output logic          [7:0]       pqc_result_be_o,   // strb_t = ELEN/8 = 8 bits
    input  logic                     pqc_result_gnt_i
  );

  // ---------------------------------------------------------------
  // Elementwise datapath: 4x16-bit Zq coefficients packed per 64-bit
  // ELEN word, reusing the verified montgomery_reduce.v / barrett_fixed.v
  // cores x4 in parallel (one word = one vector element per cycle, same
  // granularity valu.sv itself uses).
  // ---------------------------------------------------------------
  genvar gi;
  wire signed [31:0] mont_prod   [0:3];
  wire signed [15:0] mont_result [0:3];
  wire signed [15:0] barrett_in  [0:3];
  wire signed [15:0] barrett_result [0:3];

  generate
    for (gi = 0; gi < 4; gi = gi + 1) begin : g_pqc_lanes
      assign mont_prod[gi] = $signed(pqc_operand_i[0][16*gi +: 16]) *
                              $signed(pqc_operand_i[1][16*gi +: 16]);
      montgomery_reduce u_mont (.a(mont_prod[gi]), .r(mont_result[gi]));

      assign barrett_in[gi] = $signed(pqc_operand_i[0][16*gi +: 16]);
      barrett u_barrett (.a(barrett_in[gi]), .r(barrett_result[gi]));
    end
  endgenerate

  wire [63:0] montmul_word  = {mont_result[3], mont_result[2], mont_result[1], mont_result[0]};
  wire [63:0] barrett_word  = {barrett_result[3], barrett_result[2], barrett_result[1], barrett_result[0]};

  // ---------------------------------------------------------------
  // Op table: words (64-bit ELEN) gathered per operand stream and words
  // scattered to vd. Both operand streams have the same length when
  // pqc_uses_vs1(op) (Ara gives vs1 and vs2 the same vl).
  // ---------------------------------------------------------------
  function automatic logic [7:0] n_in(ara_op_e op);
    case (op)
      VPQC_KECCAKPERM:   n_in = 8'd25;
      VPQC_CBD2:         n_in = 8'd16;
      VPQC_POLYMUL:      n_in = 8'd64;
      VPQC_SHA3_512_33:  n_in = 8'd5;
      VPQC_SHA3_512_64:  n_in = 8'd8;
      VPQC_SHA3_256_PK:  n_in = 8'd148;
      VPQC_SHAKE128_XOF: n_in = 8'd5;
      VPQC_SHAKE256_PRF: n_in = 8'd5;
      VPQC_SHAKE256_RK:  n_in = 8'd140;
      VPQC_NTT, VPQC_INVNTT, VPQC_REDUCE, VPQC_TOMONT,
      VPQC_PADD, VPQC_PSUB: n_in = 8'd64;
      VPQC_BASEMUL_ACC:  n_in = 8'd192;
      VPQC_REJ:          n_in = 8'd105;
      VPQC_TOBYTES:      n_in = 8'd192;
      VPQC_FROMBYTES:    n_in = 8'd144;
      VPQC_PVCOMP:       n_in = 8'd192;
      VPQC_PVDECOMP:     n_in = 8'd120;
      VPQC_PCOMP:        n_in = 8'd64;
      VPQC_PDECOMP:      n_in = 8'd16;
      VPQC_FROMMSG:      n_in = 8'd4;
      VPQC_TOMSG:        n_in = 8'd64;
      VPQC_CTVERIFY:     n_in = 8'd136;
      VPQC_CMOV:         n_in = 8'd5;
      default:           n_in = 8'd1;
    endcase
  endfunction

  function automatic logic [7:0] n_out(ara_op_e op);
    case (op)
      VPQC_KECCAKPERM:   n_out = 8'd25;
      VPQC_CBD2:         n_out = 8'd64;
      VPQC_POLYMUL:      n_out = 8'd64;
      VPQC_SHA3_512_33:  n_out = 8'd8;
      VPQC_SHA3_512_64:  n_out = 8'd8;
      VPQC_SHA3_256_PK:  n_out = 8'd4;
      VPQC_SHAKE128_XOF: n_out = 8'd105;
      VPQC_SHAKE256_PRF: n_out = 8'd16;
      VPQC_SHAKE256_RK:  n_out = 8'd4;
      VPQC_NTT, VPQC_INVNTT, VPQC_REDUCE, VPQC_TOMONT,
      VPQC_PADD, VPQC_PSUB, VPQC_BASEMUL_ACC: n_out = 8'd64;
      VPQC_REJ:          n_out = 8'd65;    // 64 coeff words + 1 word holding ctr
      VPQC_TOBYTES:      n_out = 8'd144;
      VPQC_FROMBYTES:    n_out = 8'd192;
      VPQC_PVCOMP:       n_out = 8'd120;
      VPQC_PVDECOMP:     n_out = 8'd192;
      VPQC_PCOMP:        n_out = 8'd16;
      VPQC_PDECOMP:      n_out = 8'd64;
      VPQC_FROMMSG:      n_out = 8'd64;
      VPQC_TOMSG:        n_out = 8'd4;
      VPQC_CTVERIFY:     n_out = 8'd1;
      VPQC_CMOV:         n_out = 8'd4;
      default:           n_out = 8'd1;
    endcase
  endfunction

  // ---------------------------------------------------------------
  // Gather buffers / result buffer (192 words = 3 polynomials max)
  // ---------------------------------------------------------------
  reg  [12287:0] bufA, bufB;
  reg  [12287:0] outbuf;

  // FSM / latched instruction state declared first (used by start decode)
  localparam IDLE = 3'd0, EW_RUN = 3'd1, GATHER = 3'd2, COMPUTE_WAIT = 3'd3,
             SCATTER = 3'd4, DONE_ST = 3'd5, LAUNCH = 3'd6;
  reg [2:0] state_q, state_d;
  reg [7:0] elem_cnt;
  ara_op_e op_q;
  vid_t    id_q;
  logic [63:0] vd_base_q;

  // LAUNCH is a one-cycle bubble between GATHER and COMPUTE_WAIT so that the
  // last gathered word's non-blocking write has committed before the compute
  // block samples its inputs (real race found earlier in simulation).
  wire launch = (state_q == LAUNCH);
  function automatic logic is_op(ara_op_e a, ara_op_e b); is_op = (a == b); endfunction

  // ---------------------------------------------------------------
  // Compute blocks (all previously verified standalone). Each has its own
  // start pulse (one-hot by op_q) and its own done; done/outputs are muxed.
  // ---------------------------------------------------------------
  wire [1599:0] keccak_state_out;  wire keccak_done;
  keccak_f1600 u_keccak (.clk(clk_i), .rst_n(rst_ni), .start(launch && op_q == VPQC_KECCAKPERM),
                          .state_in(bufA[1599:0]), .state_out(keccak_state_out), .done(keccak_done));

  wire [4095:0] cbd_coeffs_out;  wire cbd_done;
  poly_cbd_eta2 u_cbd (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_CBD2),
                        .buf_in(bufA[1023:0]), .coeffs_out(cbd_coeffs_out), .done(cbd_done));

  wire [4095:0] poly_mul_c_out;  wire poly_mul_done;
  kyber_poly_mul_top u_poly_mul (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_POLYMUL),
                                  .a_in(bufA[4095:0]), .b_in(bufB[4095:0]),
                                  .c_out(poly_mul_c_out), .done(poly_mul_done));

  // sponges
  wire [511:0]  sp_g33_out;   wire sp_g33_done;
  keccak_sponge #(.RATE_BYTES(72),  .IN_LEN(33),   .OUT_LEN(64),  .PAD_BYTE(8'h06)) u_g33
    (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_SHA3_512_33),
     .in_bytes(bufA[8*33-1:0]), .out_bytes(sp_g33_out), .done(sp_g33_done));
  wire [511:0]  sp_g64_out;   wire sp_g64_done;
  keccak_sponge #(.RATE_BYTES(72),  .IN_LEN(64),   .OUT_LEN(64),  .PAD_BYTE(8'h06)) u_g64
    (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_SHA3_512_64),
     .in_bytes(bufA[511:0]), .out_bytes(sp_g64_out), .done(sp_g64_done));
  wire [255:0]  sp_hpk_out;   wire sp_hpk_done;
  keccak_sponge #(.RATE_BYTES(136), .IN_LEN(1184), .OUT_LEN(32),  .PAD_BYTE(8'h06)) u_hpk
    (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_SHA3_256_PK),
     .in_bytes(bufA[8*1184-1:0]), .out_bytes(sp_hpk_out), .done(sp_hpk_done));
  wire [8*840-1:0] sp_xof_out; wire sp_xof_done;
  keccak_sponge #(.RATE_BYTES(168), .IN_LEN(34),   .OUT_LEN(840), .PAD_BYTE(8'h1F)) u_xof
    (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_SHAKE128_XOF),
     .in_bytes(bufA[8*34-1:0]), .out_bytes(sp_xof_out), .done(sp_xof_done));
  wire [1023:0] sp_prf_out;   wire sp_prf_done;
  keccak_sponge #(.RATE_BYTES(136), .IN_LEN(33),   .OUT_LEN(128), .PAD_BYTE(8'h1F)) u_prf
    (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_SHAKE256_PRF),
     .in_bytes(bufA[8*33-1:0]), .out_bytes(sp_prf_out), .done(sp_prf_done));
  wire [255:0]  sp_rk_out;    wire sp_rk_done;
  keccak_sponge #(.RATE_BYTES(136), .IN_LEN(1120), .OUT_LEN(32),  .PAD_BYTE(8'h1F)) u_rk
    (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_SHAKE256_RK),
     .in_bytes(bufA[8*1120-1:0]), .out_bytes(sp_rk_out), .done(sp_rk_done));

  // single-polynomial transforms
  wire [4095:0] ntt_out, intt_out, red_out, tom_out, padd_out, psub_out;
  wire ntt_done, intt_done, red_done, tom_done, padd_done, psub_done;
  ntt_fwd u_ntt (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_NTT),
                 .coeffs_in(bufA[4095:0]), .coeffs_out(ntt_out), .done(ntt_done));
  ntt_inv u_intt (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_INVNTT),
                  .coeffs_in(bufA[4095:0]), .coeffs_out(intt_out), .done(intt_done));
  poly_barrett_pass u_red (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_REDUCE),
                  .coeffs_in(bufA[4095:0]), .coeffs_out(red_out), .done(red_done));
  poly_tomont u_tom (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_TOMONT),
                  .coeffs_in(bufA[4095:0]), .coeffs_out(tom_out), .done(tom_done));
  poly_add u_padd (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_PADD),
                  .a_in(bufA[4095:0]), .b_in(bufB[4095:0]), .coeffs_out(padd_out), .done(padd_done));
  poly_sub u_psub (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_PSUB),
                  .a_in(bufA[4095:0]), .b_in(bufB[4095:0]), .coeffs_out(psub_out), .done(psub_done));

  wire [4095:0] bm_out; wire bm_done;
  polyvec_basemul_acc u_bm (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_BASEMUL_ACC),
      .a0_in(bufA[4095:0]), .a1_in(bufA[8191:4096]), .a2_in(bufA[12287:8192]),
      .b0_in(bufB[4095:0]), .b1_in(bufB[8191:4096]), .b2_in(bufB[12287:8192]),
      .r_out(bm_out), .done(bm_done));

  wire [4095:0] rej_out; wire [8:0] rej_ctr; wire rej_done;
  rej_uniform #(.BUFLEN(840)) u_rej (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_REJ),
      .buf_in(bufA[8*840-1:0]), .r_out(rej_out), .ctr_out(rej_ctr), .done(rej_done));

  // packing
  wire [9215:0] tb_out; wire tb_done;
  polyvec_tobytes u_tb (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_TOBYTES),
      .a0_in(bufA[4095:0]), .a1_in(bufA[8191:4096]), .a2_in(bufA[12287:8192]),
      .bytes_out(tb_out), .done(tb_done));
  wire [4095:0] fb0, fb1, fb2; wire fb_done;
  polyvec_frombytes u_fb (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_FROMBYTES),
      .bytes_in(bufA[9215:0]), .a0_out(fb0), .a1_out(fb1), .a2_out(fb2), .done(fb_done));
  wire [7679:0] pvc_out; wire pvc_done;
  polyvec_compress u_pvc (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_PVCOMP),
      .a0_in(bufA[4095:0]), .a1_in(bufA[8191:4096]), .a2_in(bufA[12287:8192]),
      .bytes_out(pvc_out), .done(pvc_done));
  wire [4095:0] pvd0, pvd1, pvd2; wire pvd_done;
  polyvec_decompress u_pvd (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_PVDECOMP),
      .bytes_in(bufA[7679:0]), .r0_out(pvd0), .r1_out(pvd1), .r2_out(pvd2), .done(pvd_done));
  wire [1023:0] pc_out; wire pc_done;
  poly_compress u_pc (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_PCOMP),
      .coeffs_in(bufA[4095:0]), .bytes_out(pc_out), .done(pc_done));
  wire [4095:0] pd_out; wire pd_done;
  poly_decompress u_pd (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_PDECOMP),
      .bytes_in(bufA[1023:0]), .coeffs_out(pd_out), .done(pd_done));
  wire [4095:0] fm_out; wire fm_done;
  poly_frommsg u_fm (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_FROMMSG),
      .msg_in(bufA[255:0]), .coeffs_out(fm_out), .done(fm_done));
  wire [255:0] tm_out; wire tm_done;
  poly_tomsg u_tm (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_TOMSG),
      .coeffs_in(bufA[4095:0]), .msg_out(tm_out), .done(tm_done));
  wire cv_fail, cv_done;
  ct_verify #(.CTBYTES(1088)) u_cv (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_CTVERIFY),
      .ct_a_in(bufA[8*1088-1:0]), .ct_b_in(bufB[8*1088-1:0]), .fail_out(cv_fail), .done(cv_done));
  wire [255:0] cm_out; wire cm_done;
  // A = {fail word, rk[255:0]} ; B = kprime. ss = fail ? rk : kprime
  cmov_bytes #(.NBYTES(32)) u_cm (.clk(clk_i), .rst_n(rst_ni), .start_i(launch && op_q == VPQC_CMOV),
      .r_in(bufA[255:0]), .x_in(bufB[255:0]), .sel_in(!bufA[256]), .r_out(cm_out), .done(cm_done));

  logic comp_done;
  logic [12287:0] comp_res;
  always @(*) begin
    comp_done = 1'b0;
    comp_res  = '0;
    case (op_q)
      VPQC_KECCAKPERM:   begin comp_done = keccak_done;  comp_res[1599:0] = keccak_state_out; end
      VPQC_CBD2:         begin comp_done = cbd_done;     comp_res[4095:0] = cbd_coeffs_out; end
      VPQC_POLYMUL:      begin comp_done = poly_mul_done; comp_res[4095:0] = poly_mul_c_out; end
      VPQC_SHA3_512_33:  begin comp_done = sp_g33_done;  comp_res[511:0] = sp_g33_out; end
      VPQC_SHA3_512_64:  begin comp_done = sp_g64_done;  comp_res[511:0] = sp_g64_out; end
      VPQC_SHA3_256_PK:  begin comp_done = sp_hpk_done;  comp_res[255:0] = sp_hpk_out; end
      VPQC_SHAKE128_XOF: begin comp_done = sp_xof_done;  comp_res[8*840-1:0] = sp_xof_out; end
      VPQC_SHAKE256_PRF: begin comp_done = sp_prf_done;  comp_res[1023:0] = sp_prf_out; end
      VPQC_SHAKE256_RK:  begin comp_done = sp_rk_done;   comp_res[255:0] = sp_rk_out; end
      VPQC_NTT:          begin comp_done = ntt_done;     comp_res[4095:0] = ntt_out; end
      VPQC_INVNTT:       begin comp_done = intt_done;    comp_res[4095:0] = intt_out; end
      VPQC_REDUCE:       begin comp_done = red_done;     comp_res[4095:0] = red_out; end
      VPQC_TOMONT:       begin comp_done = tom_done;     comp_res[4095:0] = tom_out; end
      VPQC_PADD:         begin comp_done = padd_done;    comp_res[4095:0] = padd_out; end
      VPQC_PSUB:         begin comp_done = psub_done;    comp_res[4095:0] = psub_out; end
      VPQC_BASEMUL_ACC:  begin comp_done = bm_done;      comp_res[4095:0] = bm_out; end
      VPQC_REJ:          begin comp_done = rej_done;     comp_res[4095:0] = rej_out;
                               comp_res[4096 +: 9] = rej_ctr; end
      VPQC_TOBYTES:      begin comp_done = tb_done;      comp_res[9215:0] = tb_out; end
      VPQC_FROMBYTES:    begin comp_done = fb_done;      comp_res = {fb2, fb1, fb0}; end
      VPQC_PVCOMP:       begin comp_done = pvc_done;     comp_res[7679:0] = pvc_out; end
      VPQC_PVDECOMP:     begin comp_done = pvd_done;     comp_res = {pvd2, pvd1, pvd0}; end
      VPQC_PCOMP:        begin comp_done = pc_done;      comp_res[1023:0] = pc_out; end
      VPQC_PDECOMP:      begin comp_done = pd_done;      comp_res[4095:0] = pd_out; end
      VPQC_FROMMSG:      begin comp_done = fm_done;      comp_res[4095:0] = fm_out; end
      VPQC_TOMSG:        begin comp_done = tm_done;      comp_res[255:0] = tm_out; end
      VPQC_CTVERIFY:     begin comp_done = cv_done;      comp_res[0] = cv_fail; end
      VPQC_CMOV:         begin comp_done = cm_done;      comp_res[255:0] = cm_out; end
      default: ;
    endcase
  end

  // ---------------------------------------------------------------
  // Latched op / id / destination base (vfu_operation_i is only valid for
  // the single dispatch cycle -- see earlier-found bug history).
  // ---------------------------------------------------------------
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      op_q <= VPQC_MONTMUL;
      id_q <= '0;
      vd_base_q <= '0;
    end else if (state_q == IDLE && vfu_operation_valid_i) begin
      op_q <= vfu_operation_i.op;
      id_q <= vfu_operation_i.id;
      vd_base_q <= ara_pkg::vaddr(vfu_operation_i.vd, NrLanes, VLEN);
    end
  end

  // Elementwise (EW_RUN) handshake: wait for operands and for the write grant.
  wire ew_run_needs_vs1      = (op_q == VPQC_MONTMUL);
  wire ew_run_operands_valid = pqc_operand_valid_i[0] &&
                                (!ew_run_needs_vs1 || pqc_operand_valid_i[1]);
  wire ew_run_complete       = ew_run_operands_valid && pqc_result_gnt_i;

  // Gather handshake: joint-valid when the op reads two streams.
  wire uses_b        = pqc_uses_vs1(op_q);
  wire gather_valid  = pqc_operand_valid_i[0] && (!uses_b || pqc_operand_valid_i[1]);
  wire [7:0] nin_c   = n_in(op_q);
  wire [7:0] nout_c  = n_out(op_q);

  wire is_ew_op = (vfu_operation_i.op == VPQC_MONTMUL) || (vfu_operation_i.op == VPQC_BARRETT);

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q  <= IDLE;
      elem_cnt <= 8'd0;
    end else begin
      state_q <= state_d;
      if (state_q == IDLE && vfu_operation_valid_i)
        elem_cnt <= 8'd0;
      else if (state_q == LAUNCH)
        elem_cnt <= 8'd0;                    // SCATTER indexes outbuf from 0
      else if (state_q == GATHER && gather_valid)
        elem_cnt <= elem_cnt + 8'd1;
      else if (state_q == SCATTER && pqc_result_gnt_i)
        elem_cnt <= elem_cnt + 8'd1;

      if (state_q == GATHER && gather_valid) begin
        bufA[64*elem_cnt +: 64] <= pqc_operand_i[0];
        if (uses_b) bufB[64*elem_cnt +: 64] <= pqc_operand_i[1];
      end
      if (state_q == COMPUTE_WAIT && comp_done)
        outbuf <= comp_res;
    end
  end

  always @(*) begin
    state_d = state_q;
    case (state_q)
      IDLE: if (vfu_operation_valid_i) begin
        if (is_ew_op) state_d = EW_RUN;
        else if (vfu_operation_i.op >= VPQC_KECCAKPERM && vfu_operation_i.op <= VPQC_CMOV) state_d = GATHER;
      end
      EW_RUN: if (ew_run_complete) state_d = IDLE;
      GATHER: if (gather_valid && elem_cnt == nin_c - 8'd1) state_d = LAUNCH;
      LAUNCH: state_d = COMPUTE_WAIT;
      COMPUTE_WAIT: if (comp_done) state_d = SCATTER;
      SCATTER: if (pqc_result_gnt_i && elem_cnt == nout_c - 8'd1) state_d = DONE_ST;
      DONE_ST: state_d = IDLE;
      default: state_d = IDLE;
    endcase
  end

  assign pqc_ready_o = (state_q == IDLE);
  assign pqc_vinsn_done_o = ((state_q == DONE_ST) ||
                              (state_q == EW_RUN && ew_run_complete))
                             ? ({{(NrVInsn-1){1'b0}}, 1'b1} << id_q) : '0;

  assign pqc_operand_ready_o[0] =
      (state_q == EW_RUN) ? ew_run_complete :
      (state_q == GATHER) ? gather_valid : 1'b0;
  assign pqc_operand_ready_o[1] =
      (state_q == EW_RUN && op_q == VPQC_MONTMUL) ? ew_run_complete :
      (state_q == GATHER && uses_b) ? gather_valid : 1'b0;

  assign pqc_result_req_o = (state_q == EW_RUN && ew_run_operands_valid) ||
                             (state_q == SCATTER);
  assign pqc_result_id_o  = id_q;
  assign pqc_result_addr_o = vaddr_t'(vd_base_q + {56'd0, elem_cnt});
  assign pqc_result_be_o  = 8'hFF;

  assign pqc_result_wdata_o =
      (op_q == VPQC_MONTMUL) ? montmul_word :
      (op_q == VPQC_BARRETT) ? barrett_word :
      outbuf[64*elem_cnt +: 64];

endmodule
