`timescale 1ns/1ps
// tb_vfu_pqc_keccak_cbd.sv -- behavioral regression check for the
// VPQC_KECCAKPERM and VPQC_CBD2 gather/compute/scatter FSM. Both ops share
// the same FSM shape as the VPQC_POLYMUL path (LAUNCH -> GATHER -> COMPUTE
// -> SCATTER), so this guards the two timing-sensitive points in that FSM:
// the start pulse must not fire a cycle early, and elem_cnt must reset
// before SCATTER. It drives each op through vfu_pqc.sv with fixed input
// data and cross-checks the scattered result against a directly-
// instantiated reference copy of the same keccak_f1600.v / poly_cbd_eta2.v
// block, driven with identical inputs outside the VFU wrapper.

module tb_vfu_pqc_keccak_cbd;
  import ara_pkg::*;

  localparam int unsigned ELEN = 64;
  typedef logic [4:0] vaddr_t;
  typedef struct packed { vid_t id; ara_op_e op; logic [4:0] vd; } vfu_operation_t;

  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  vfu_operation_t vfu_operation_i;
  reg vfu_operation_valid_i;
  wire pqc_ready_o;
  wire [NrVInsn-1:0] pqc_vinsn_done_o;
  reg  [ELEN-1:0] pqc_operand_i [0:1];
  reg  [1:0] pqc_operand_valid_i;
  wire [1:0] pqc_operand_ready_o;
  wire pqc_result_req_o;
  wire vid_t pqc_result_id_o;
  wire vaddr_t pqc_result_addr_o;
  wire [ELEN-1:0] pqc_result_wdata_o;
  wire [7:0] pqc_result_be_o;
  reg  pqc_result_gnt_i;

  vfu_pqc #(4, 1024, vaddr_t, vfu_operation_t) dut (
    .clk_i(clk), .rst_ni(rst_n), .lane_id_i('0),
    .vfu_operation_i(vfu_operation_i), .vfu_operation_valid_i(vfu_operation_valid_i),
    .pqc_ready_o(pqc_ready_o), .pqc_vinsn_done_o(pqc_vinsn_done_o),
    .pqc_operand_i({pqc_operand_i[1], pqc_operand_i[0]}), .pqc_operand_valid_i(pqc_operand_valid_i),
    .pqc_operand_ready_o(pqc_operand_ready_o),
    .pqc_result_req_o(pqc_result_req_o), .pqc_result_id_o(pqc_result_id_o),
    .pqc_result_addr_o(pqc_result_addr_o), .pqc_result_wdata_o(pqc_result_wdata_o),
    .pqc_result_be_o(pqc_result_be_o), .pqc_result_gnt_i(pqc_result_gnt_i)
  );

  // Reference copies, driven independently and compared against.
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

  integer i, w, errors;
  reg [1599:0] keccak_result;
  reg [4095:0] cbd_result;

  task run_gather_scatter(input ara_op_e op, input integer n_gather, input integer n_scatter);
    begin
      vfu_operation_i.op = op;
      vfu_operation_i.id = 0;
      vfu_operation_valid_i = 1;
      pqc_result_gnt_i = 1;
      // Keep vfu_operation_valid_i asserted from dispatch through the
      // WHOLE gather loop, exactly like tb_vfu_pqc_polymul.sv's (already
      // passing, bit-exact) gather loop -- letting the loop's own first
      // while(!ready) wait naturally absorb the IDLE->GATHER bubble
      // cycle, rather than pre-consuming a separate edge for the
      // dispatch pulse first. That pre-consumed edge was tried in an
      // earlier version of this fix and, empirically, shifted the
      // ready/valid timing by one cycle relative to what GATHER's
      // capture logic expects, causing the FIRST word's data to get
      // captured twice (once "for free" on an edge the loop didn't
      // count) and the true LAST word to never be supplied -- the loop
      // would then hang forever waiting for a ready pulse that never
      // returns once GATHER has moved on. Clearing valid_i is instead
      // done right after the gather loop finishes below (state_q is by
      // then safely past IDLE, in LAUNCH/COMPUTE_WAIT/SCATTER, so op_q/
      // id_q -- already latched -- no longer depend on vfu_operation_i
      // staying valid) -- early enough to prevent the spurious
      // re-dispatch this task's OWN trailing wait cycles would otherwise
      // cause when back-to-back with a second run_gather_scatter call
      // (see CBD2 below), without perturbing the gather loop's timing.
      for (w = 0; w < n_gather; w = w + 1) begin
        if (op == VPQC_KECCAKPERM)
          pqc_operand_i[0] = ref_keccak_in[64*w +: 64];
        else
          pqc_operand_i[0] = ref_cbd_in[64*w +: 64];
        pqc_operand_valid_i = 2'b01;
        // Wait until ready is already asserted going INTO a posedge
        // before crossing the edge that consumes this word (same
        // reasoning as tb_vfu_pqc_polymul.sv's gather loop).
        while (!pqc_operand_ready_o[0]) @(negedge clk);
        @(negedge clk);
      end
      pqc_operand_valid_i = 2'b00;
      // Clear the dispatch-valid pulse here, right after the gather loop
      // finishes: by now state_q has already moved past IDLE (into
      // LAUNCH/COMPUTE_WAIT/SCATTER), and op_q/id_q were latched at the
      // original IDLE->dispatch edge, so they no longer depend on
      // vfu_operation_i/vfu_operation_valid_i staying asserted. Clearing
      // it now (instead of leaving it asserted all the way to the very
      // end of the task, as an earlier version of this test did)
      // prevents a spurious second dispatch from being read out of a
      // stale vfu_operation_i during this task's own trailing
      // wait-for-scatter loop, which matters once two ops are run
      // back-to-back (KECCAKPERM immediately followed by CBD2, below).
      vfu_operation_valid_i = 0;

      w = 0;
      for (i = 0; i < 3000; i = i + 1) begin
        @(negedge clk);
        if (pqc_result_req_o) begin
          if (op == VPQC_KECCAKPERM) keccak_result[64*w +: 64] = pqc_result_wdata_o;
          else                        cbd_result[64*w +: 64]    = pqc_result_wdata_o;
          w = w + 1;
          if (w == n_scatter) i = 1000000;
        end
      end
      if (w != n_scatter)
        $display("RESULT: FAIL -- op=%0d never scattered all %0d words (got %0d)", op, n_scatter, w);
      // let the FSM return fully to IDLE before the next op
      repeat (4) @(negedge clk);
      vfu_operation_valid_i = 0;
      repeat (2) @(negedge clk);
    end
  endtask

  initial begin
    rst_n = 0; vfu_operation_valid_i = 0; pqc_operand_valid_i = 0; pqc_result_gnt_i = 0;
    ref_keccak_start = 0; ref_cbd_start = 0;
    ref_keccak_in = 1600'h0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef;
    ref_cbd_in    = 1024'hfedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

    // Compute the independent reference results first.
    ref_keccak_start = 1; @(negedge clk); ref_keccak_start = 0;
    wait (ref_keccak_done); @(negedge clk);
    ref_cbd_start = 1; @(negedge clk); ref_cbd_start = 0;
    wait (ref_cbd_done); @(negedge clk);

    run_gather_scatter(VPQC_KECCAKPERM, 25, 25);
    run_gather_scatter(VPQC_CBD2, 16, 64);

    errors = 0;
    for (i = 0; i < 25; i = i + 1)
      if (keccak_result[64*i +: 64] !== ref_keccak_out[64*i +: 64]) begin
        errors = errors + 1;
        $display("KECCAK MISMATCH word=%0d got=%h exp=%h", i, keccak_result[64*i +: 64], ref_keccak_out[64*i +: 64]);
      end
    for (i = 0; i < 64; i = i + 1)
      if (cbd_result[64*i +: 64] !== ref_cbd_out[64*i +: 64]) begin
        errors = errors + 1;
        $display("CBD MISMATCH word=%0d got=%h exp=%h", i, cbd_result[64*i +: 64], ref_cbd_out[64*i +: 64]);
      end

    if (errors == 0)
      $display("RESULT: vfu_pqc.sv VPQC_KECCAKPERM and VPQC_CBD2 gather->compute->scatter both match directly-instantiated reference keccak_f1600.v/poly_cbd_eta2.v runs bit-exact, after the LAUNCH/elem_cnt-reset fix.");
    else
      $display("RESULT: FAIL (%0d mismatches)", errors);

    $finish;
  end
endmodule
