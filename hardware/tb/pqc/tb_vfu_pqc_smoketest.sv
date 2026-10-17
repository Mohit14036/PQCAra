`timescale 1ns/1ps
// tb_vfu_pqc_smoketest.sv -- standalone plumbing smoke test for vfu_pqc.sv.
// It checks that (a) the FSM does not hang/deadlock and (b) the
// VPQC_MONTMUL elementwise datapath produces results matching a plain
// reference computation of montgomery_reduce(a*b) for 4 packed lanes.
// Full lane-level verification is done separately by the tb_lane_* benches
// that drive the real lane.sv.

module tb_vfu_pqc_smoketest;
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
  reg [ELEN-1:0] pqc_operand_i [0:1];
  reg [1:0] pqc_operand_valid_i;
  wire [1:0] pqc_operand_ready_o;
  wire pqc_result_req_o;
  wire vid_t pqc_result_id_o;
  wire vaddr_t pqc_result_addr_o;
  wire [ELEN-1:0] pqc_result_wdata_o;
  wire [7:0] pqc_result_be_o;
  reg pqc_result_gnt_i;

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

  function automatic signed [15:0] ref_montgomery;
    input signed [31:0] a;
    reg signed [15:0] t;
    localparam signed [15:0] QINV = -16'sd3327;
    localparam signed [31:0] Q = 32'sd3329;
    begin
      t = a[15:0] * QINV;
      ref_montgomery = (a - t * Q) >>> 16;
    end
  endfunction

  integer i, errors;
  reg signed [15:0] a_lanes [0:3];
  reg signed [15:0] b_lanes [0:3];
  reg signed [15:0] exp_lanes [0:3];
  reg [63:0] got_word;

  initial begin
    rst_n = 0; vfu_operation_valid_i = 0; pqc_operand_valid_i = 0; pqc_result_gnt_i = 0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

    a_lanes[0] = 100;  a_lanes[1] = -500; a_lanes[2] = 3328; a_lanes[3] = 1;
    b_lanes[0] = 2285;  // real Kyber zeta-ish sample values, arbitrary but in range
    b_lanes[1] = 1;
    b_lanes[2] = -1;
    b_lanes[3] = 1729;
    for (i = 0; i < 4; i = i + 1)
      exp_lanes[i] = ref_montgomery(a_lanes[i] * b_lanes[i]);

    pqc_operand_i[0] = {a_lanes[3], a_lanes[2], a_lanes[1], a_lanes[0]};
    pqc_operand_i[1] = {b_lanes[3], b_lanes[2], b_lanes[1], b_lanes[0]};

    vfu_operation_i.op = VPQC_MONTMUL;
    vfu_operation_i.id = 0;
    vfu_operation_valid_i = 1;
    pqc_operand_valid_i = 2'b11;
    pqc_result_gnt_i = 1;

    // give it a bounded number of cycles -- fail (not hang) if it never
    // asserts pqc_result_req_o
    for (i = 0; i < 20; i = i + 1) begin
      @(negedge clk);
      if (pqc_result_req_o) begin
        got_word = pqc_result_wdata_o;
        i = 1000; // break
      end
    end

    if (got_word === 64'bx || pqc_result_req_o !== 1'b1) begin
      $display("RESULT: FAIL -- vfu_pqc.sv never produced a result (FSM hang or plumbing bug)");
      $finish;
    end

    errors = 0;
    for (i = 0; i < 4; i = i + 1) begin
      if (got_word[16*i +: 16] !== exp_lanes[i]) begin
        errors = errors + 1;
        $display("LANE FAIL[%0d]: got=%0d exp=%0d", i, $signed(got_word[16*i +: 16]), exp_lanes[i]);
      end
    end

    if (errors == 0)
      $display("RESULT: vfu_pqc.sv smoke test passed -- VPQC_MONTMUL elementwise datapath (operand queues -> 4x montgomery_reduce.v -> packed result word) is self-consistent. This is a standalone plumbing smoke test; full lane-level verification is done by the tb_lane_* benches on the real lane.sv.");
    else
      $display("RESULT: FAIL (%0d/4 lane mismatches)", errors);

    $finish;
  end
endmodule
