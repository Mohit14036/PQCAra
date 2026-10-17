// ara_sequencer_elab_harness.sv -- minimal wrapper, NOT part of the
// design, that supplies ara_sequencer.sv the same pe_req_t/pe_resp_t/
// ara_req_t/ara_resp_t/exception_t struct types the real ara.sv builds
// for it (via the real, unmodified `ara/ara_typedef.svh`, plus the same
// inline ara_req_t/ara_resp_t typedefs ara.sv itself defines locally),
// so it can be elaborated standalone under Verilator without pulling in
// ara.sv's much larger dependency set (vlsu/sldu/masku/ara_dispatcher),
// which is out of scope for this session (see ARA_INTEGRATION.md). This
// exists only to prove the new pqc_vinsn_done_i port / insn_queue_done
// [VFU_Pqc] wiring added to ara_sequencer.sv this session is
// structurally sound.
module ara_sequencer_elab_harness import ara_pkg::*; import rvv_pkg::*; import cf_math_pkg::idx_width; #(
    parameter int unsigned NrLanes = 4,
    parameter int unsigned VLEN    = 1024,
    // ara_typedef.svh expects this to already be in scope as a param/
    // localparam type, exactly as ara.sv/ara_sequencer.sv/lane.sv each
    // declare it themselves before including the same file.
    localparam type        vlen_t  = logic [$clog2(VLEN+1)-1:0],
    // Same shape as ara.sv's own local params/parameters, needed by
    // ara_sequencer's port list (exception_t) and PE array sizing
    // (NrPEs = NrLanes + 4: NrLanes ALU/MFPU/PQC PEs + load/store/slide/mask).
    parameter type          exception_t = logic,
    localparam int unsigned NrPEs   = NrLanes + 4
  ) ();

  `include "ara/ara_typedef.svh"

  // ara_req_t / ara_resp_t, copied VERBATIM from hardware/src/ara.sv's
  // own local typedef block (lines 85-174 there) -- not reconstructed
  // from memory -- since ara_sequencer.sv's body reads specific fields
  // off both (eew_vmask, scale_vl, conversion_vs1/2, old_eew_vs1,
  // eew_vd_op on the request; resp/exception/fof_exception/
  // exception_vstart on the response) that a placeholder shape doesn't
  // have.
  typedef struct packed {
    ara_op_e op;
    logic scale_vl;
    logic vm;
    rvv_pkg::vew_e eew_vmask;
    logic [4:0] vs1;
    logic use_vs1;
    opqueue_conversion_e conversion_vs1;
    rvv_pkg::vew_e eew_vs1;
    rvv_pkg::vew_e old_eew_vs1;
    logic [4:0] vs2;
    logic use_vs2;
    opqueue_conversion_e conversion_vs2;
    rvv_pkg::vew_e eew_vs2;
    logic use_vd_op;
    rvv_pkg::vew_e eew_vd_op;
    elen_t scalar_op;
    logic use_scalar_op;
    elen_t stride;
    logic is_stride_np2;
    logic [4:0] vd;
    logic use_vd;
    logic swap_vs2_vd_op;
    rvv_pkg::vlmul_e emul;
    logic [2:0] nf;
    logic fault_only_first;
    fpnew_pkg::roundmode_e fp_rm;
    logic wide_fp_imm;
    resize_e cvt_resize;
    vlen_t vl;
    vlen_t vstart;
    rvv_pkg::vtype_t vtype;
    logic token;
  } ara_req_t;

  typedef struct packed {
    elen_t resp;
    exception_t exception;
    logic fof_exception;
    vlen_t exception_vstart;
  } ara_resp_dummy_t;

  logic clk_i, rst_ni;
  ara_req_t ara_req_i;
  logic ara_req_valid_i;
  logic ara_req_ready_o;
  ara_resp_dummy_t ara_resp_dummy_o;
  logic ara_resp_valid_o;
  logic ara_idle_o;
  pe_req_t pe_req_o;
  logic pe_req_valid_o;
  logic [NrVInsn-1:0] pe_vinsn_running_o;
  logic [NrPEs-1:0] pe_req_ready_i;
  pe_resp_t [NrPEs-1:0] pe_resp_i;
  logic alu_vinsn_done_i, mfpu_vinsn_done_i, pqc_vinsn_done_i;
  logic [NrVInsn-1:0][NrVInsn-1:0] global_hazard_table_o;
  elen_t pe_scalar_resp_i;
  logic pe_scalar_resp_valid_i;
  logic pe_scalar_resp_ready_o;
  logic addrgen_ack_i;
  exception_t addrgen_exception_i;
  vlen_t addrgen_exception_vstart_i;
  logic addrgen_fof_exception_i;
  logic lsu_current_burst_exception_i;

  // ara_resp_o's real type (ara_resp_t) isn't reproduced field-for-field
  // here (irrelevant to the pqc_vinsn_done_i wiring under test); bind it
  // via a wire of matching bit width instead of a duplicated struct.
  wire [$bits(ara_resp_dummy_t)-1:0] ara_resp_bits;

  ara_sequencer #(
    .NrLanes    (NrLanes   ),
    .VLEN       (VLEN      ),
    .ara_req_t  (ara_req_t ),
    .ara_resp_t (ara_resp_dummy_t),
    .pe_req_t   (pe_req_t  ),
    .pe_resp_t  (pe_resp_t ),
    .exception_t(exception_t)
  ) dut (
    .clk_i                 (clk_i),
    .rst_ni                (rst_ni),
    .ara_req_i             (ara_req_i),
    .ara_req_valid_i       (ara_req_valid_i),
    .ara_req_ready_o       (ara_req_ready_o),
    .ara_resp_o            (ara_resp_dummy_o),
    .ara_resp_valid_o      (ara_resp_valid_o),
    .ara_idle_o            (ara_idle_o),
    .pe_req_o              (pe_req_o),
    .pe_req_valid_o        (pe_req_valid_o),
    .pe_vinsn_running_o    (pe_vinsn_running_o),
    .pe_req_ready_i        (pe_req_ready_i),
    .pe_resp_i             (pe_resp_i),
    .alu_vinsn_done_i      (alu_vinsn_done_i),
    .mfpu_vinsn_done_i     (mfpu_vinsn_done_i),
    .pqc_vinsn_done_i      (pqc_vinsn_done_i),
    .global_hazard_table_o (global_hazard_table_o),
    .pe_scalar_resp_i      (pe_scalar_resp_i),
    .pe_scalar_resp_valid_i(pe_scalar_resp_valid_i),
    .pe_scalar_resp_ready_o(pe_scalar_resp_ready_o),
    .addrgen_ack_i         (addrgen_ack_i),
    .addrgen_exception_i   (addrgen_exception_i),
    .addrgen_exception_vstart_i(addrgen_exception_vstart_i),
    .addrgen_fof_exception_i(addrgen_fof_exception_i),
    .lsu_current_burst_exception_i(lsu_current_burst_exception_i)
  );

endmodule
