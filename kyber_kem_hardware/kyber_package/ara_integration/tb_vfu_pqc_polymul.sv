`timescale 1ns/1ps
// tb_vfu_pqc_polymul.sv -- behavioral (not just elaboration) test of the
// new VPQC_POLYMUL gather/compute/scatter FSM added to vfu_pqc.sv this
// session. Drives the real captured Kyber-768 (Q=3329, N=256) a/b
// polynomials from ../ntt_scaling/../vectors/vecs_poly_mul/poly_mul_ntt_real.txt
// (the same real reference vector already used to verify kyber_poly_mul_top.v
// standalone) in through PqcA/PqcB one 64-bit (4-coefficient) word per
// cycle -- exactly the shape the real lane_sequencer.sv/operand_queues_stage.sv
// wiring feeds a VFU -- and checks the scattered 64-word result against the
// real captured c = a*b mod (X^256+1) mod 3329, bit-exact on all 256
// coefficients. This is the direct behavioral counterpart of the
// elaboration-only proof in verilator_lane_elaboration.log: elaboration
// shows the new ports/wiring are structurally sound; this shows the new
// FSM states actually compute the right answer.
//
// Uses mock_ara_pkg.sv (a minimal, real-value-matching stand-in for
// hardware/include/ara_pkg.sv -- see that file's header comment for why)
// because Icarus cannot parse the real package's fpnew_pkg.sv dependency.

module tb_vfu_pqc_polymul;
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

  integer fd, r, i, w;
  integer real_a[0:255], real_b[0:255], real_a_ntt[0:255], real_b_ntt[0:255], real_c[0:255];
  reg [63:0] a_word, b_word;
  reg [4095:0] result_buf;
  integer errors;

  initial begin
    fd = $fopen("poly_mul_ntt_real.txt", "r");
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_a[i]);
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_b[i]);
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_a_ntt[i]);
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_b_ntt[i]);
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_c[i]);
    $fclose(fd);

    rst_n = 0; vfu_operation_valid_i = 0; pqc_operand_valid_i = 0; pqc_result_gnt_i = 0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

    vfu_operation_i.op = VPQC_POLYMUL;
    vfu_operation_i.id = 0;
    vfu_operation_valid_i = 1;
    pqc_result_gnt_i = 1;

    // Stream the 64 words (4 coeffs/word x 64 = 256 coeffs) of a and b in
    // together on PqcA/PqcB, respecting pqc_operand_ready_o (a real
    // valid/ready handshake, same as the real operand_queues_stage.sv:
    // an operand queue holds its word stable until the VFU asserts
    // ready, including across the IDLE->GATHER transition cycle, when
    // ready is still low).
    for (w = 0; w < 64; w = w + 1) begin
      a_word = {real_a[4*w+3][15:0], real_a[4*w+2][15:0], real_a[4*w+1][15:0], real_a[4*w+0][15:0]};
      b_word = {real_b[4*w+3][15:0], real_b[4*w+2][15:0], real_b[4*w+1][15:0], real_b[4*w+0][15:0]};
      pqc_operand_i[0] = a_word;
      pqc_operand_i[1] = b_word;
      pqc_operand_valid_i = 2'b11;
      // Wait until ready is already asserted going INTO a posedge (e.g.
      // the IDLE->GATHER bubble cycle, where ready is still low) before
      // crossing the edge that actually consumes this word -- checking
      // ready only *after* crossing an edge tells us about the *next*
      // edge, not the one just taken, which is the off-by-one this
      // fixes relative to an earlier, incorrect version of this loop.
      while (!(pqc_operand_ready_o[0] && pqc_operand_ready_o[1])) @(negedge clk);
      @(negedge clk);
    end
    pqc_operand_valid_i = 2'b00;
    vfu_operation_valid_i = 1; // op stays valid through compute/scatter, same as EW ops

    // Wait (bounded) for the 64-word scattered result.
    w = 0;
    for (i = 0; i < 8000; i = i + 1) begin
      @(negedge clk);
      if (pqc_result_req_o) begin
        result_buf[64*w +: 64] = pqc_result_wdata_o;
        w = w + 1;
        if (w == 64) i = 1000000; // break
      end
    end

    if (w != 64) begin
      $display("RESULT: FAIL -- vfu_pqc.sv VPQC_POLYMUL never scattered all 64 result words (got %0d/64, FSM hang or plumbing bug)", w);
      $finish;
    end

    errors = 0;
    for (i = 0; i < 256; i = i + 1) begin
      if ($signed(result_buf[16*i +: 16]) !== real_c[i]) begin
        errors = errors + 1;
        $display("MISMATCH idx=%0d got=%0d expected=%0d", i, $signed(result_buf[16*i +: 16]), real_c[i]);
      end
    end

    if (errors == 0)
      $display("RESULT: vfu_pqc.sv VPQC_POLYMUL gather->kyber_poly_mul_top->scatter FSM matches the real captured Kyber-768 (Q=3329,N=256) a*b mod (X^256+1) mod 3329 result bit-exact on all 256 coefficients, driven through the same PqcA/PqcB word-at-a-time protocol the real lane wiring uses.");
    else
      $display("RESULT: FAIL (%0d/256 mismatches)", errors);

    $finish;
  end
endmodule
