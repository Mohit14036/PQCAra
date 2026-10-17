`timescale 1ns/1ps
// tb_lane_vpqc_montmul.sv -- drives the REAL, wired-in hardware/src/lane/
// lane.sv (not vfu_pqc.sv standalone, and not a stand-in package) with a
// real pe_req_i VPQC_MONTMUL instruction, through the real
// lane_sequencer.sv -> operand_requester.sv -> operand_queues_stage.sv ->
// vfu_pqc.sv -> operand_requester.sv (VRF write arbiter) -> vector_regfile.sv
// path, and checks the destination register's content against an
// independent reference computation of montgomery_reduce(a*b) for 4
// packed 16-bit lanes.
//
// This closes the specific gap ARA_INTEGRATION.md calls out under "Not a
// simulation of the real lane.sv hierarchy": every previous check either
// elaborated the real lane.sv (Verilator --lint-only, structural only)
// or behaviorally simulated vfu_pqc.sv standalone (Icarus, against
// mock_ara_pkg.sv, not the real ara_pkg.sv/lane.sv). This is Verilator
// *simulation* (not --lint-only) of the actual real, unmodified (other
// than this session's PQC wiring) lane.sv, driven through its real
// pe_req_i instruction interface.
//
// Two real, boundary-level techniques are used instead of any backdoor
// force/poke of DUT state:
//  - Preloading vs1/vs2 uses lane.sv's own sldu_result_req_i/addr_i/
//    wdata_i/be_i input ports (the real "slide unit writes a result
//    into the VRF" interface) to write source data into the VRF before
//    issuing the VPQC_MONTMUL instruction, through the SAME VRF-write
//    arbitration path (operand_requester.sv's low-priority rr_arb_tree)
//    a real slide-unit result would use.
//  - The destination register's content is read back via a plain SV
//    hierarchical reference into vector_regfile.sv's real tc_sram
//    instance (dut.i_vrf.gen_banks[bank].data_sram.sram[word_addr]) --
//    a passive, read-only peek at the real memory array, not a force or
//    write.
// The VRF address for each register is computed with the real
// ara_pkg::vaddr() function (the exact function operand_requester.sv
// itself calls), so it matches the DUT's own internal addressing by
// construction rather than by a separately-reverse-engineered formula.

module tb_lane_vpqc_montmul;
  import ara_pkg::*;
  import rvv_pkg::*;

  localparam int unsigned NrLanes = 4;
  localparam int unsigned VLEN    = 4096; // NrLanes*1024, ara_pkg::vaddr()'s
                                           // own documented reference config
  localparam type vlen_t      = logic [$clog2(VLEN+1)-1:0];
  localparam type exception_t = logic;    // unused by the PQC path

  `include "ara/ara_typedef.svh"

  localparam int unsigned PE_REQ_BITS  = $bits(pe_req_t);
  localparam int unsigned PE_RESP_BITS = $bits(pe_resp_t);

  // Same vaddr_t lane.sv itself derives (VRFBSizePerLane-based), computed
  // identically here so the port types match exactly.
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
  // Reference computation, independent of the RTL: plain montgomery_
  // reduce(a*b) for 4 packed 16-bit lanes, same formula as
  // montgomery_reduce.v / ref/reduce.c's montgomery_reduce(), computed
  // here directly in SV rather than by re-reading the RTL's own output.
  // ---------------------------------------------------------------
  function automatic signed [15:0] ref_montgomery(input signed [31:0] a);
    reg signed [15:0] t;
    localparam signed [15:0] QINV = -16'sd3327;
    localparam signed [31:0] Q    = 32'sd3329;
    begin
      t = a[15:0] * QINV;
      ref_montgomery = (a - t * Q) >>> 16;
    end
  endfunction

  integer i, errors;
  reg signed [15:0] a_lanes [0:3];
  reg signed [15:0] b_lanes [0:3];
  reg signed [15:0] exp_lanes [0:3];
  reg [63:0] a_word, b_word, got_word;

  task automatic sldu_preload(input vaddr_t addr, input elen_t data);
    begin
      sldu_result_id_i    = '0;
      sldu_result_addr_i  = addr;
      sldu_result_wdata_i = data;
      sldu_result_be_i    = '1;
      sldu_result_req_i   = 1'b1;
      // Hold until the real VRF write arbiter grants it (same handshake
      // a real slide-unit result would use).
      while (!sldu_result_gnt_o) @(negedge clk);
      @(negedge clk);
      sldu_result_req_i   = 1'b0;
    end
  endtask

  initial begin
    rst_n = 1'b0;
    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    // v1 = a_lanes, v2 = b_lanes (register indices 1 and 2), one ELEN
    // word each (4 packed 16-bit Zq coefficients), at vstart=0.
    a_lanes[0] = 100;   a_lanes[1] = -500;  a_lanes[2] = 3328; a_lanes[3] = 1;
    b_lanes[0] = 2285;  b_lanes[1] = 1;     b_lanes[2] = -1;   b_lanes[3] = 1729;
    for (i = 0; i < 4; i = i + 1)
      exp_lanes[i] = ref_montgomery(a_lanes[i] * b_lanes[i]);
    a_word = {a_lanes[3], a_lanes[2], a_lanes[1], a_lanes[0]};
    b_word = {b_lanes[3], b_lanes[2], b_lanes[1], b_lanes[0]};

    sldu_preload(vaddr_t'(ara_pkg::vaddr(5'd1, NrLanes, VLEN)), a_word);
    sldu_preload(vaddr_t'(ara_pkg::vaddr(5'd2, NrLanes, VLEN)), b_word);
    repeat (4) @(negedge clk);

    // Real VPQC_MONTMUL instruction: v3 = montgomery_reduce(v1 * v2),
    // vl=4 elements at EEW=16 (exactly one ELEN word), vstart=0.
    pe_req                 = '0;
    pe_req.id               = vid_t'(0);
    pe_req.op                = VPQC_MONTMUL;
    pe_req.vfu                = VFU_Pqc;
    pe_req.vm                  = 1'b1; // unmasked
    pe_req.vs1                  = 5'd1;
    pe_req.use_vs1                = 1'b1;
    pe_req.eew_vs1                  = EW16;
    pe_req.vs2                        = 5'd2;
    pe_req.use_vs2                     = 1'b1;
    pe_req.eew_vs2                       = EW16;
    pe_req.vd                              = 5'd3;
    pe_req.use_vd                           = 1'b1;
    pe_req.vl                                = vlen_t'(4);
    pe_req.vstart                             = vlen_t'(0);
    pe_req.vtype.vsew                          = EW16;
    pe_req.vtype.vlmul                          = LMUL_1;

    pe_req_valid_i = 1'b1;

    // Hold pe_req_valid_i asserted for several cycles (as the real
    // ara_dispatcher would, broadcasting to all lanes until each one
    // samples it), then drop it -- but keep checking pe_resp.vinsn_done[0]
    // in the SAME loop, every cycle, from t=0 onward. pe_resp_o.vinsn_done
    // is a plain one-cycle-wide pulse (lane_sequencer.sv's
    // vinsn_done_d = alu_vinsn_done_i | mfpu_vinsn_done_i | pqc_vinsn_done_i,
    // not a sticky/latched level), so splitting "assert valid" and "wait
    // for done" into two separate sequential loops -- as an earlier
    // version of this testbench did -- can miss the pulse entirely if it
    // fires while still in the first loop, which is exactly what
    // happened here (vinsn_done pulsed a few cycles after dispatch,
    // before the old code ever lowered pe_req_valid_i and started
    // watching for it).
    for (i = 0; i < 200; i = i + 1) begin
      @(negedge clk);
      if (i == 4) pe_req_valid_i = 1'b0;
      if (pe_resp.vinsn_done[0]) i = 100000;
    end
    if (i < 100000) begin
      $display("RESULT: FAIL -- lane.sv never reported vinsn_done for the VPQC_MONTMUL instruction (hang or plumbing bug)");
      $finish;
    end
    repeat (2) @(negedge clk);

    // Read back v3's content: a passive peek at the real VRF memory
    // (dut.i_vrf, the same vector_regfile.sv the real lane_sequencer/
    // operand_requester/vfu_pqc path just wrote through), at the exact
    // address+bank ara_pkg::vaddr() computes for register 3.
    got_word = dut.i_vrf.gen_banks[0].data_sram.sram[
      (ara_pkg::vaddr(5'd3, NrLanes, VLEN)) >> $clog2(8)
    ];

    errors = 0;
    for (i = 0; i < 4; i = i + 1) begin
      if (got_word[16*i +: 16] !== exp_lanes[i]) begin
        errors = errors + 1;
        $display("LANE FAIL[%0d]: got=%0d exp=%0d", i, $signed(got_word[16*i +: 16]), exp_lanes[i]);
      end
    end

    if (errors == 0)
      $display("RESULT: real lane.sv (real lane_sequencer.sv -> operand_requester.sv -> operand_queues_stage.sv -> vfu_pqc.sv -> operand_requester.sv -> vector_regfile.sv, driven through the real pe_req_i instruction interface, with source operands preloaded via the real sldu_result_* VRF-write port) computed VPQC_MONTMUL = montgomery_reduce(v1*v2) correctly, matching an independent reference computation on all 4 packed lanes.");
    else
      $display("RESULT: FAIL (%0d/4 lane mismatches)", errors);

    $finish;
  end

endmodule
