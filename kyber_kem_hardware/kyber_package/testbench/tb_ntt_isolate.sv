`timescale 1ns/1ps
// tb_ntt_isolate.sv -- isolated ntt_fwd.v check against skpv_ntt[0] as
// captured in indcpa_keypair_real.txt.
//
// FIX (this session): this test originally compared ntt_fwd.v's raw
// output directly against indcpa_keypair_real.txt's skpv_ntt[0] values
// and failed on 135/256 coefficients -- but NOT because of an RTL bug.
// Every single mismatch was off by an exact multiple of Q=3329 (e.g.
// got=-1762 exp=1567, and -1762+3329=1567 exactly), which is the classic
// signature of comparing a PRE-reduction value against a POST-reduction
// one. ARCHITECTURE.md already documents why: "poly_ntt() == ntt() +
// poly_reduce()" -- the real reference's poly_ntt() (what
// indcpa_keypair_derand() actually calls, and what skpv_ntt[0] in the
// captured vector file is) runs ntt_fwd's 7 NTT layers AND THEN a
// Barrett-reduction pass (poly_barrett_pass.v) that this isolated test
// was never chaining in. The correctly-chained version of this exact
// comparison already exists and passes bit-exact in
// tb_indcpa_keypair_real.sv (which does include poly_barrett_pass.v)
// and in tb_ntt_fwd_real.sv (which compares ntt_fwd.v's raw output
// against the real bare ntt(), the correct reference for THAT
// comparison, with vecs_ntt/ntt_real.txt). This file is the odd one out:
// it grabbed the post-reduce reference value but only instantiated the
// pre-reduce module. Fixed here by chaining poly_barrett_pass.v after
// ntt_fwd.v, exactly like indcpa_keypair_arith.v does, so this isolated
// test now compares like-for-like and passes.
module tb_ntt_isolate;
  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [4095:0] coeffs_in;
  wire [4095:0] ntt_out;
  wire [4095:0] coeffs_out;
  reg           start_i;
  wire          done, reduce_done;
  reg           reduce_start;

  ntt_fwd dut (.clk(clk), .rst_n(rst_n), .start_i(start_i),
               .coeffs_in(coeffs_in), .coeffs_out(ntt_out), .done(done));

  poly_barrett_pass u_reduce (.clk(clk), .rst_n(rst_n), .start_i(reduce_start),
               .coeffs_in(ntt_out), .coeffs_out(coeffs_out), .done(reduce_done));

  integer fd, r, i, errors;
  integer real_in[0:255];
  integer real_out[0:255];
  reg signed [15:0] got;

  initial begin
    fd = $fopen("vecs_keypair/indcpa_keypair_prentt_real.txt", "r");
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_in[i]);
    $fclose(fd);
    fd = $fopen("vecs_keypair/indcpa_keypair_real.txt", "r");
    // skip 9 matrix rows (256 each)
    for (i = 0; i < 9*256; i = i + 1) begin integer junk; r = $fscanf(fd, "%d", junk); end
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_out[i]);  // skpv_ntt[0]
    $fclose(fd);

    coeffs_in = 0;
    for (i = 0; i < 256; i = i + 1) coeffs_in[16*i +: 16] = real_in[i][15:0];

    start_i = 0; reduce_start = 0; rst_n = 0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);
    start_i = 1; @(negedge clk); start_i = 0;
    wait (done == 1'b1); @(negedge clk);
    reduce_start = 1; @(negedge clk); reduce_start = 0;
    wait (reduce_done == 1'b1); @(negedge clk);

    errors = 0;
    for (i = 0; i < 256; i = i + 1) begin
      got = coeffs_out[16*i +: 16];
      if (got !== real_out[i][15:0]) begin
        errors = errors + 1;
        if (errors <= 5) $display("FAIL[%0d]: got=%0d exp=%0d", i, $signed(got), real_out[i]);
      end
    end
    $display("errors=%0d / 256", errors);
    if (errors == 0)
      $display("RESULT: ntt_fwd.v + poly_barrett_pass.v (i.e. poly_ntt() == ntt()+poly_reduce(), exactly as indcpa_keypair_arith.v chains them) matches the real skpv_ntt[0] captured value exactly, all 256 coefficients.");
    else
      $display("RESULT: FAIL (%0d/256 mismatches)", errors);
    $finish;
  end
endmodule
