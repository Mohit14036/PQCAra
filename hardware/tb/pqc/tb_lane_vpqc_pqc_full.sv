`timescale 1ns/1ps
// tb_lane_vpqc_pqc_full.sv -- extends tb_lane_vpqc_montmul.sv's real,
// full behavioral SIMULATION (not --lint-only elaboration) of the
// actual, wired-in hardware/src/lane/lane.sv hierarchy to the remaining
// four PQC ops:
// VPQC_BARRETT, VPQC_KECCAKPERM, VPQC_CBD2, VPQC_POLYMUL. Only
// VPQC_MONTMUL had been driven through the real lane.sv this way before
// this file; this closes that gap for the rest of the op set.
//
// Same real, boundary-level techniques as tb_lane_vpqc_montmul.sv (no
// backdoor force/poke of DUT state):
//  - Source operands are preloaded into the real VRF through lane.sv's
//    own sldu_result_req_i/addr_i/wdata_i/be_i port (the real
//    "slide-unit writes a result" interface), at the real VRF address
//    ara_pkg::vaddr() computes for each register -- the exact function
//    operand_requester.sv itself calls.
//  - The destination register's content is read back via a passive,
//    read-only peek into vector_regfile.sv's real tc_sram banks.
//
// NEW vs. tb_lane_vpqc_montmul.sv: the whole-vector-register ops
// (KECCAKPERM/CBD2/POLYMUL) gather/scatter MANY consecutive ELEN words
// per register, not just one. Two things that were invisible in the
// single-word MONTMUL test become load-bearing here:
//   1. The real VRF is banked 8-way (ara_pkg.sv's NrVRFBanksPerLane=8),
//      and consecutive ELEN-word addresses round-robin across banks
//      (word w of a register lands in bank w mod 8) -- confirmed by
//      reading operand_requester.sv's own address-increment logic
//      (`requester_metadata_d.addr = requester_metadata_q.addr + 1`)
//      and vector_regfile.sv's per-bank instantiation. The MONTMUL test
//      could get away with a single hardcoded `gen_banks[0]` peek
//      because its one output word always happened to land at an
//      address that was a multiple of 8 (bank 0); a 25/64-word gather
//      cycles through all 8 banks and needs a real bank-aware read.
//   2. VLEN must be large enough that one register can actually hold
//      the largest of these ops' word counts (64, for VPQC_POLYMUL) in
//      a single lane -- confirmed via operand_requester.sv's own
//      address computation (`vaddr(vs, NrLanes, VLEN)`, word-granularity,
//      incrementing by 1 per fetched word, with no scale_vl rescaling
//      for the PQC operand requests in lane_sequencer.sv, so
//      effective_vector_body_length == pe_req.vl exactly). VLEN is
//      raised from tb_lane_vpqc_montmul.sv's 4096 to 32768 here so each
//      lane's register capacity (VLENB/NrLanes/8 = 128 ELEN words) is
//      comfortably more than the 64 words POLYMUL needs.
//
// One further, real, already-documented limitation this file
// deliberately works within rather than papering over: cross-lane
// distribution of the whole-register ops' gathered elements across
// NrLanes>1 is explicitly "not designed" (see ARA_INTEGRATION.md).
// Nothing about how many WORDS this single lane's own pe_req.vl
// requests, or how operand_requester.sv fetches them, actually depends
// on NrLanes beyond the per-lane register-capacity formula above (this
// testbench drives one `lane` instance directly with its own pe_req_i,
// bypassing the higher-level ara_dispatcher.sv step that would normally
// split a global vl across multiple lanes) -- so this file's results are
// real evidence for the PQC datapath itself, within the same "single
// lane in isolation" scope tb_lane_vpqc_montmul.sv already established,
// and do NOT close the separate, still-open cross-lane gap.

module tb_lane_vpqc_pqc_full;
  import ara_pkg::*;
  import rvv_pkg::*;

  localparam int unsigned NrLanes = 4;
  localparam int unsigned VLEN    = 32768; // raised from 4096 (MONTMUL) so
                                            // one register's per-lane
                                            // capacity (128 ELEN words)
                                            // comfortably covers POLYMUL's
                                            // 64-word gather/scatter.
  localparam type vlen_t      = logic [$clog2(VLEN+1)-1:0];
  localparam type exception_t = logic;

  `include "ara/ara_typedef.svh"

  localparam int unsigned PE_REQ_BITS  = $bits(pe_req_t);
  localparam int unsigned PE_RESP_BITS = $bits(pe_resp_t);

  localparam int unsigned VLENB           = VLEN / 8;
  localparam int unsigned MaxVLenBPerLane = VLENB / NrLanes;
  localparam int unsigned VRFBSizePerLane = MaxVLenBPerLane * 32;
  typedef logic [$clog2(VRFBSizePerLane)-1:0] vaddr_t;
  typedef logic [$bits(elen_t)/8-1:0] strb_t;

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic scan_data_o;
  logic [$clog2(NrLanes)-1:0] lane_id_i;
  logic vxsat_flag_o;
  logic [4:0] fflags_ex_o;
  logic fflags_ex_valid_o;
  logic lsu_ex_flush_o;

  pe_req_t  pe_req;
  logic [PE_REQ_BITS-1:0] pe_req_i_bits;
  logic pe_req_valid_i;
  logic [NrVInsn-1:0] pe_vinsn_running_i;
  logic pe_req_ready_o;
  logic [PE_RESP_BITS-1:0] pe_resp_o_bits;
  pe_resp_t pe_resp;
  logic alu_vinsn_done_o, mfpu_vinsn_done_o, pqc_vinsn_done_o;
  logic [NrVInsn-1:0][NrVInsn-1:0] global_hazard_table_i;

  elen_t stu_operand_o;
  logic  stu_operand_valid_o;
  elen_t sldu_addrgen_operand_o;
  logic  sldu_operand_valid_o, addrgen_operand_valid_o;
  sldu_mux_e sldu_mux_sel_i;

  logic   sldu_result_req_i;
  vid_t   sldu_result_id_i;
  vaddr_t sldu_result_addr_i;
  elen_t  sldu_result_wdata_i;
  strb_t  sldu_result_be_i;
  logic   sldu_result_gnt_o;
  logic   sldu_red_valid_i;
  logic   sldu_result_final_gnt_o;

  logic   ldu_result_req_i;
  vid_t   ldu_result_id_i;
  vaddr_t ldu_result_addr_i;
  elen_t  ldu_result_wdata_i;
  strb_t  ldu_result_be_i;
  logic   ldu_result_gnt_o, ldu_result_final_gnt_o;

  elen_t [NrMaskFUnits+2-1:0] mask_operand_o;
  logic  [NrMaskFUnits+2-1:0] mask_operand_valid_o;
  logic  [NrMaskFUnits+2-1:0] mask_operand_ready_i;
  logic   masku_result_req_i;
  vid_t   masku_result_id_i;
  vaddr_t masku_result_addr_i;
  elen_t  masku_result_wdata_i;
  strb_t  masku_result_be_i;
  logic   masku_result_gnt_o, masku_result_final_gnt_o;
  logic   masku_vrgat_req_valid_i;
  logic   masku_vrgat_req_ready_o;
  vrgat_req_t masku_vrgat_req_i;

  strb_t mask_i;
  logic  mask_valid_i;
  logic  mask_ready_o;

  initial begin
    lane_id_i               = '0;
    pe_req_valid_i           = 1'b0;
    pe_vinsn_running_i        = '0;
    global_hazard_table_i     = '0;
    sldu_mux_sel_i            = NO_RED;
    sldu_result_req_i         = 1'b0;
    sldu_result_id_i          = '0;
    sldu_result_addr_i        = '0;
    sldu_result_wdata_i       = '0;
    sldu_result_be_i          = '0;
    sldu_red_valid_i          = 1'b0;
    ldu_result_req_i          = 1'b0;
    ldu_result_id_i           = '0;
    ldu_result_addr_i         = '0;
    ldu_result_wdata_i        = '0;
    ldu_result_be_i           = '0;
    mask_operand_ready_i      = '1;
    masku_result_req_i        = 1'b0;
    masku_result_id_i         = '0;
    masku_result_addr_i       = '0;
    masku_result_wdata_i      = '0;
    masku_result_be_i         = '0;
    masku_vrgat_req_valid_i   = 1'b0;
    masku_vrgat_req_i         = '0;
    mask_i                    = '0;
    mask_valid_i              = 1'b0;
    pe_req                    = '0;
  end

  lane #(
    .NrLanes       (NrLanes),
    .VLEN          (VLEN),
    .pe_req_t_bits (PE_REQ_BITS),
    .pe_resp_t_bits(PE_RESP_BITS)
  ) dut (
    .clk_i                   (clk),
    .rst_ni                  (rst_n),
    .scan_enable_i            (1'b0),
    .scan_data_i              (1'b0),
    .scan_data_o              (scan_data_o),
    .lane_id_i                (lane_id_i),
    .vxsat_flag_o              (vxsat_flag_o),
    .alu_vxrm_i                (2'b00),
    .fflags_ex_o               (fflags_ex_o),
    .fflags_ex_valid_o         (fflags_ex_valid_o),
    .lsu_ex_flush_i            (1'b0),
    .lsu_ex_flush_o            (lsu_ex_flush_o),
    .pe_req_i                  (pe_req_i_bits),
    .pe_req_valid_i            (pe_req_valid_i),
    .pe_vinsn_running_i        (pe_vinsn_running_i),
    .pe_req_ready_o            (pe_req_ready_o),
    .pe_resp_o                 (pe_resp_o_bits),
    .alu_vinsn_done_o          (alu_vinsn_done_o),
    .mfpu_vinsn_done_o         (mfpu_vinsn_done_o),
    .pqc_vinsn_done_o          (pqc_vinsn_done_o),
    .global_hazard_table_i     (global_hazard_table_i),
    .stu_operand_o             (stu_operand_o),
    .stu_operand_valid_o       (stu_operand_valid_o),
    .stu_operand_ready_i       (1'b1),
    .sldu_addrgen_operand_o    (sldu_addrgen_operand_o),
    .sldu_operand_valid_o      (sldu_operand_valid_o),
    .addrgen_operand_valid_o   (addrgen_operand_valid_o),
    .sldu_operand_ready_i      (1'b1),
    .sldu_mux_sel_i            (sldu_mux_sel_i),
    .addrgen_operand_ready_i   (1'b1),
    .sldu_result_req_i         (sldu_result_req_i),
    .sldu_result_id_i          (sldu_result_id_i),
    .sldu_result_addr_i        (sldu_result_addr_i),
    .sldu_result_wdata_i       (sldu_result_wdata_i),
    .sldu_result_be_i          (sldu_result_be_i),
    .sldu_result_gnt_o         (sldu_result_gnt_o),
    .sldu_red_valid_i          (sldu_red_valid_i),
    .sldu_result_final_gnt_o   (sldu_result_final_gnt_o),
    .ldu_result_req_i          (ldu_result_req_i),
    .ldu_result_id_i           (ldu_result_id_i),
    .ldu_result_addr_i         (ldu_result_addr_i),
    .ldu_result_wdata_i        (ldu_result_wdata_i),
    .ldu_result_be_i           (ldu_result_be_i),
    .ldu_result_gnt_o          (ldu_result_gnt_o),
    .ldu_result_final_gnt_o    (ldu_result_final_gnt_o),
    .mask_operand_o            (mask_operand_o),
    .mask_operand_valid_o      (mask_operand_valid_o),
    .mask_operand_ready_i      (mask_operand_ready_i),
    .masku_result_req_i        (masku_result_req_i),
    .masku_result_id_i         (masku_result_id_i),
    .masku_result_addr_i       (masku_result_addr_i),
    .masku_result_wdata_i      (masku_result_wdata_i),
    .masku_result_be_i         (masku_result_be_i),
    .masku_result_gnt_o        (masku_result_gnt_o),
    .masku_result_final_gnt_o  (masku_result_final_gnt_o),
    .masku_vrgat_req_valid_i   (masku_vrgat_req_valid_i),
    .masku_vrgat_req_ready_o   (masku_vrgat_req_ready_o),
    .masku_vrgat_req_i         (masku_vrgat_req_i),
    .mask_i                    (mask_i),
    .mask_valid_i              (mask_valid_i),
    .mask_ready_o              (mask_ready_o)
  );

  assign pe_req_i_bits = pe_req;
  assign pe_resp       = pe_resp_o_bits;


  // ---------------------------------------------------------------
  // Independent references, same reasoning as tb_lane_vpqc_montmul.sv
  // (a plain SV re-implementation of the formula for BARRETT, matching
  // montgomery_reduce's ref_montgomery pattern there) plus, for the
  // whole-register ops, the exact SAME real, independently-instantiated
  // reference modules and fixed test vectors already used and verified
  // in the standalone Icarus tests (tb_vfu_pqc_keccak_cbd.sv,
  // tb_vfu_pqc_polymul.sv) -- reused here, not re-derived, so this test
  // is checking the real wired-in lane.sv against the same known-good
  // reference data, not a freshly-invented one.
  // ---------------------------------------------------------------
  function automatic signed [15:0] ref_barrett(input signed [15:0] a);
    reg signed [31:0] prod, t_shift, t_full;
    localparam signed [31:0] V = 32'sd20159;
    begin
      prod    = V * a;
      t_shift = (prod + 32'sd33554432) >>> 26;
      t_full  = t_shift * 32'sd3329;
      ref_barrett = a - t_full[15:0];
    end
  endfunction

  reg  [1599:0] ref_keccak_in;
  reg           ref_keccak_start;
  wire [1599:0] ref_keccak_out;
  wire          ref_keccak_done;
  keccak_f1600 ref_keccak (.clk(clk), .rst_n(rst_n), .start(ref_keccak_start),
                            .state_in(ref_keccak_in), .state_out(ref_keccak_out), .done(ref_keccak_done));

  reg  [1023:0] ref_cbd_in;
  reg           ref_cbd_start;
  wire [4095:0] ref_cbd_out;
  wire          ref_cbd_done;
  poly_cbd_eta2 ref_cbd (.clk(clk), .rst_n(rst_n), .start_i(ref_cbd_start),
                          .buf_in(ref_cbd_in), .coeffs_out(ref_cbd_out), .done(ref_cbd_done));

  // Real captured Kyber-768 (Q=3329, N=256) a/b polynomials, same file
  // tb_vfu_pqc_polymul.sv already verified vfu_pqc.sv standalone against.
  integer pmfd, pmr, pmi;
  integer real_a[0:255], real_b[0:255], real_a_ntt_unused[0:255], real_b_ntt_unused[0:255], real_c[0:255];

  // ---------------------------------------------------------------
  // Real VRF preload (sldu_result_* port) / passive readback (bank-aware
  // tc_sram peek). See this file's header comment for why the readback
  // needs to be bank-aware here (unlike tb_lane_vpqc_montmul.sv's single
  // hardcoded gen_banks[0]).
  // ---------------------------------------------------------------
  task automatic sldu_preload(input vaddr_t addr, input elen_t data);
    begin
      sldu_result_id_i    = '0;
      sldu_result_addr_i  = addr;
      sldu_result_wdata_i = data;
      sldu_result_be_i    = '1;
      sldu_result_req_i   = 1'b1;
      while (!sldu_result_gnt_o) @(negedge clk);
      @(negedge clk);
      sldu_result_req_i   = 1'b0;
    end
  endtask

  task automatic vrf_write_block(input [4:0] vid, input integer n, input elen_t words [0:127]);
    integer w;
    begin
      for (w = 0; w < n; w = w + 1)
        sldu_preload(vaddr_t'(ara_pkg::vaddr(vid, NrLanes, VLEN) + w), words[w]);
    end
  endtask

  function automatic elen_t vrf_peek(input [4:0] vid, input integer w);
    integer addr, bank, row;
    begin
      addr = ara_pkg::vaddr(vid, NrLanes, VLEN) + w;
      bank = addr % 8;
      row  = addr / 8;
      case (bank)
        0: vrf_peek = dut.i_vrf.gen_banks[0].data_sram.sram[row];
        1: vrf_peek = dut.i_vrf.gen_banks[1].data_sram.sram[row];
        2: vrf_peek = dut.i_vrf.gen_banks[2].data_sram.sram[row];
        3: vrf_peek = dut.i_vrf.gen_banks[3].data_sram.sram[row];
        4: vrf_peek = dut.i_vrf.gen_banks[4].data_sram.sram[row];
        5: vrf_peek = dut.i_vrf.gen_banks[5].data_sram.sram[row];
        6: vrf_peek = dut.i_vrf.gen_banks[6].data_sram.sram[row];
        7: vrf_peek = dut.i_vrf.gen_banks[7].data_sram.sram[row];
      endcase
    end
  endfunction

  // ---------------------------------------------------------------
  // Generic dispatch: issue a real VPQC_* pe_req_i and wait (checking
  // pe_resp.vinsn_done[0] EVERY cycle, same reasoning as
  // tb_lane_vpqc_montmul.sv -- it is a plain one-cycle pulse, not a
  // sticky level) for it to complete. LOOPMAX is generously large for
  // the whole-register ops: gather (up to 64 cycles) + the downstream
  // engine's own compute latency (keccak_f1600's 24 rounds /
  // poly_cbd_eta2 / kyber_poly_mul_top's NTT pipeline, all already
  // independently cycle-count-verified elsewhere in this project, but
  // not re-derived here) + scatter (up to 64 cycles) can together run
  // well past MONTMUL's single-word ~10-cycle latency.
  // ---------------------------------------------------------------
  integer li;
  task automatic dispatch_and_wait(
      input ara_op_e op, input [4:0] vs2, input [4:0] vs1, input [4:0] vd,
      input use_vs1_i, input rvv_pkg::vew_e eew_vs2, input rvv_pkg::vew_e eew_vs1,
      input vlen_t vl);
    begin
      pe_req              = '0;
      pe_req.id            = vid_t'(0);
      pe_req.op             = op;
      pe_req.vfu              = VFU_Pqc;
      pe_req.vm                 = 1'b1;
      pe_req.vs2                 = vs2;
      pe_req.use_vs2               = 1'b1;
      pe_req.eew_vs2                 = eew_vs2;
      pe_req.vs1                       = vs1;
      pe_req.use_vs1                     = use_vs1_i;
      pe_req.eew_vs1                       = eew_vs1;
      pe_req.vd                              = vd;
      pe_req.use_vd                           = 1'b1;
      pe_req.vl                                = vl;
      pe_req.vstart                             = vlen_t'(0);
      pe_req.vtype.vsew                          = eew_vs2;
      pe_req.vtype.vlmul                          = LMUL_1;

      pe_req_valid_i = 1'b1;
      for (li = 0; li < 20000; li = li + 1) begin
        @(negedge clk);
        if (li == 4) pe_req_valid_i = 1'b0;
        if (pe_resp.vinsn_done[0]) li = 1000000;
      end
      if (li < 1000000) begin
        $display("RESULT: FAIL -- lane.sv never reported vinsn_done for op=%0d (hang or plumbing bug)", op);
        $finish;
      end
      repeat (2) @(negedge clk);
    end
  endtask

  integer i, w, errors, total_errors;
  reg signed [15:0] barrett_a [0:3];
  reg signed [15:0] barrett_exp [0:3];
  reg [63:0] barrett_word, got_word;
  elen_t words_buf [0:127];
  reg [1599:0] keccak_scattered;
  reg [4095:0] cbd_scattered;
  reg [4095:0] polymul_scattered;

  initial begin
    total_errors = 0;
    rst_n = 1'b0;
    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    // =================================================================
    // VPQC_BARRETT -- elementwise, single operand (vs2 only), same shape
    // as VPQC_MONTMUL's already-verified EW_RUN path minus the second
    // multiplicand.
    // =================================================================
    barrett_a[0] = 100; barrett_a[1] = -500; barrett_a[2] = 3328; barrett_a[3] = 1;
    for (i = 0; i < 4; i = i + 1) barrett_exp[i] = ref_barrett(barrett_a[i]);
    barrett_word = {barrett_a[3], barrett_a[2], barrett_a[1], barrett_a[0]};

    sldu_preload(vaddr_t'(ara_pkg::vaddr(5'd8, NrLanes, VLEN)), barrett_word);
    repeat (4) @(negedge clk);

    dispatch_and_wait(VPQC_BARRETT, 5'd8, 5'd0, 5'd9, 1'b0, EW16, EW16, vlen_t'(4));

    got_word = vrf_peek(5'd9, 0);
    errors = 0;
    for (i = 0; i < 4; i = i + 1)
      if (got_word[16*i +: 16] !== barrett_exp[i]) begin
        errors = errors + 1;
        $display("BARRETT LANE FAIL[%0d]: got=%0d exp=%0d", i, $signed(got_word[16*i +: 16]), barrett_exp[i]);
      end
    if (errors == 0)
      $display("RESULT: real lane.sv computed VPQC_BARRETT = barrett_reduce(v1) correctly through the real pe_req_i -> lane_sequencer -> operand_requester -> vfu_pqc -> VRF write path, matching an independent reference on all 4 packed lanes.");
    else
      $display("RESULT: FAIL -- VPQC_BARRETT (%0d/4 lane mismatches)", errors);
    total_errors = total_errors + errors;

    // =================================================================
    // VPQC_KECCAKPERM -- whole-register gather(25)/compute/scatter(25).
    // Same fixed test vector already verified against this same
    // directly-instantiated keccak_f1600 reference in
    // tb_vfu_pqc_keccak_cbd.sv (standalone vfu_pqc.sv, not the real
    // lane.sv) -- reused here to check the real wired-in lane against
    // the identical known-good expected output.
    // =================================================================
    ref_keccak_in = 1600'h0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef;
    ref_keccak_start = 1; @(negedge clk); ref_keccak_start = 0;
    wait (ref_keccak_done); @(negedge clk);

    for (w = 0; w < 25; w = w + 1) words_buf[w] = ref_keccak_in[64*w +: 64];
    vrf_write_block(5'd10, 25, words_buf);
    repeat (4) @(negedge clk);

    // pe_req.vl is the GLOBAL architectural vl; lane_sequencer.sv divides
    // it by NrLanes internally (vfu_operation_d.vl = pe_req.vl / NrLanes)
    // to get THIS lane's local share, since normal Ara ops stripe a
    // vector register's elements across all lanes. This single-lane
    // testbench only drives lane 0's local operand queue, so pe_req.vl
    // is set to NrLanes times the local word count vfu_pqc.sv's FSM
    // actually needs (25/16/64), each an exact multiple of NrLanes here
    // to keep the division exact (no remainder-driven +1 on lane 0).
    dispatch_and_wait(VPQC_KECCAKPERM, 5'd10, 5'd0, 5'd11, 1'b0, EW64, EW64, vlen_t'(25 * NrLanes));

    errors = 0;
    for (w = 0; w < 25; w = w + 1) begin
      keccak_scattered[64*w +: 64] = vrf_peek(5'd11, w);
      if (keccak_scattered[64*w +: 64] !== ref_keccak_out[64*w +: 64]) begin
        errors = errors + 1;
        if (errors <= 5) $display("KECCAKPERM LANE FAIL[%0d]: got=%h exp=%h", w, keccak_scattered[64*w +: 64], ref_keccak_out[64*w +: 64]);
      end
    end
    if (errors == 0)
      $display("RESULT: real lane.sv computed VPQC_KECCAKPERM (gather 25 words -> keccak_f1600 -> scatter 25 words) correctly through the real pe_req_i -> lane_sequencer -> operand_requester -> vfu_pqc -> VRF write path, matching an independent reference keccak_f1600.v run bit-exact on all 1600 bits.");
    else
      $display("RESULT: FAIL -- VPQC_KECCAKPERM (%0d/25 word mismatches)", errors);
    total_errors = total_errors + errors;

    // =================================================================
    // VPQC_CBD2 -- whole-register gather(16)/compute/scatter(64).
    // Same fixed test vector as tb_vfu_pqc_keccak_cbd.sv.
    // =================================================================
    ref_cbd_in = 1024'hfedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210;
    ref_cbd_start = 1; @(negedge clk); ref_cbd_start = 0;
    wait (ref_cbd_done); @(negedge clk);

    for (w = 0; w < 16; w = w + 1) words_buf[w] = ref_cbd_in[64*w +: 64];
    vrf_write_block(5'd12, 16, words_buf);
    repeat (4) @(negedge clk);

    dispatch_and_wait(VPQC_CBD2, 5'd12, 5'd0, 5'd13, 1'b0, EW64, EW64, vlen_t'(16 * NrLanes));

    errors = 0;
    for (w = 0; w < 64; w = w + 1) begin
      cbd_scattered[64*w +: 64] = vrf_peek(5'd13, w);
      if (cbd_scattered[64*w +: 64] !== ref_cbd_out[64*w +: 64]) begin
        errors = errors + 1;
        if (errors <= 5) $display("CBD2 LANE FAIL[%0d]: got=%h exp=%h", w, cbd_scattered[64*w +: 64], ref_cbd_out[64*w +: 64]);
      end
    end
    if (errors == 0)
      $display("RESULT: real lane.sv computed VPQC_CBD2 (gather 16 words -> poly_cbd_eta2 -> scatter 64 words) correctly through the real pe_req_i -> lane_sequencer -> operand_requester -> vfu_pqc -> VRF write path, matching an independent reference poly_cbd_eta2.v run bit-exact on all 256 coefficients.");
    else
      $display("RESULT: FAIL -- VPQC_CBD2 (%0d/64 word mismatches)", errors);
    total_errors = total_errors + errors;

    // =================================================================
    // VPQC_POLYMUL -- whole-register gather(64+64)/compute/scatter(64),
    // checked against the real captured Kyber-768 a*b mod (X^256+1) mod
    // 3329 vector, same file tb_vfu_pqc_polymul.sv already verified
    // vfu_pqc.sv standalone against.
    // =================================================================
    pmfd = $fopen("poly_mul_ntt_real.txt", "r");
    for (pmi = 0; pmi < 256; pmi = pmi + 1) pmr = $fscanf(pmfd, "%d", real_a[pmi]);
    for (pmi = 0; pmi < 256; pmi = pmi + 1) pmr = $fscanf(pmfd, "%d", real_b[pmi]);
    for (pmi = 0; pmi < 256; pmi = pmi + 1) pmr = $fscanf(pmfd, "%d", real_a_ntt_unused[pmi]);
    for (pmi = 0; pmi < 256; pmi = pmi + 1) pmr = $fscanf(pmfd, "%d", real_b_ntt_unused[pmi]);
    for (pmi = 0; pmi < 256; pmi = pmi + 1) pmr = $fscanf(pmfd, "%d", real_c[pmi]);
    $fclose(pmfd);

    for (w = 0; w < 64; w = w + 1)
      words_buf[w] = {real_a[4*w+3][15:0], real_a[4*w+2][15:0], real_a[4*w+1][15:0], real_a[4*w+0][15:0]};
    vrf_write_block(5'd14, 64, words_buf);   // a -> vs2 (PqcA)
    for (w = 0; w < 64; w = w + 1)
      words_buf[w] = {real_b[4*w+3][15:0], real_b[4*w+2][15:0], real_b[4*w+1][15:0], real_b[4*w+0][15:0]};
    vrf_write_block(5'd15, 64, words_buf);   // b -> vs1 (PqcB)
    repeat (4) @(negedge clk);

    dispatch_and_wait(VPQC_POLYMUL, 5'd14, 5'd15, 5'd16, 1'b1, EW64, EW64, vlen_t'(64 * NrLanes));

    errors = 0;
    for (w = 0; w < 64; w = w + 1)
      polymul_scattered[64*w +: 64] = vrf_peek(5'd16, w);
    for (i = 0; i < 256; i = i + 1) begin
      if ($signed(polymul_scattered[16*i +: 16]) !== real_c[i]) begin
        errors = errors + 1;
        if (errors <= 5) $display("POLYMUL LANE FAIL[%0d]: got=%0d exp=%0d", i, $signed(polymul_scattered[16*i +: 16]), real_c[i]);
      end
    end
    if (errors == 0)
      $display("RESULT: real lane.sv computed VPQC_POLYMUL (gather 64+64 words -> kyber_poly_mul_top -> scatter 64 words) correctly through the real pe_req_i -> lane_sequencer -> operand_requester -> vfu_pqc -> VRF write path, matching the real captured Kyber-768 (Q=3329,N=256) a*b mod (X^256+1) mod 3329 result bit-exact on all 256 coefficients.");
    else
      $display("RESULT: FAIL -- VPQC_POLYMUL (%0d/256 coefficient mismatches)", errors);
    total_errors = total_errors + errors;

    if (total_errors == 0)
      $display("RESULT: ALL FOUR (VPQC_BARRETT, VPQC_KECCAKPERM, VPQC_CBD2, VPQC_POLYMUL) pass through the real, wired-in lane.sv hierarchy bit-exact, completing lane-level simulation coverage for all five PQC ops (VPQC_MONTMUL already covered by tb_lane_vpqc_montmul.sv).");
    else
      $display("RESULT: OVERALL FAIL -- %0d total mismatches across the four ops", total_errors);

    $finish;
  end

endmodule
