`timescale 1ns/1ps
// tb_polyvec_basemul_real.sv -- checks polyvec_basemul_acc.v against a
// REAL (a_vec, b_vec, r_output) triple captured from ref/polyvec.c's
// real polyvec_basemul_acc_montgomery() call during an actual
// crypto_kem_keypair()+enc+dec round trip (K=3 / Kyber-768).
// File layout (vecs_polyvec/polyvec_basemul_real.txt): 7 lines of
// 256 ints each: a[0],a[1],a[2],b[0],b[1],b[2],r_out.

module tb_polyvec_basemul_real;

  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [4095:0] a0_in, a1_in, a2_in;
  reg  [4095:0] b0_in, b1_in, b2_in;
  wire [4095:0] r_out;
  reg           start_i;
  wire          done;

  polyvec_basemul_acc dut (
      .clk(clk), .rst_n(rst_n), .start_i(start_i),
      .a0_in(a0_in), .a1_in(a1_in), .a2_in(a2_in),
      .b0_in(b0_in), .b1_in(b1_in), .b2_in(b2_in),
      .r_out(r_out), .done(done)
  );

  integer fd, r, i;
  integer real_a0[0:255], real_a1[0:255], real_a2[0:255];
  integer real_b0[0:255], real_b1[0:255], real_b2[0:255];
  integer real_r [0:255];
  integer errors;
  reg signed [15:0] got;

  initial begin
    fd = $fopen("vecs_polyvec/polyvec_basemul_real.txt", "r");
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_a0[i]);
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_a1[i]);
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_a2[i]);
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_b0[i]);
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_b1[i]);
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_b2[i]);
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_r[i]);
    $fclose(fd);

    a0_in = 0; a1_in = 0; a2_in = 0;
    b0_in = 0; b1_in = 0; b2_in = 0;
    for (i = 0; i < 256; i = i + 1) begin
      a0_in[16*i +: 16] = real_a0[i][15:0];
      a1_in[16*i +: 16] = real_a1[i][15:0];
      a2_in[16*i +: 16] = real_a2[i][15:0];
      b0_in[16*i +: 16] = real_b0[i][15:0];
      b1_in[16*i +: 16] = real_b1[i][15:0];
      b2_in[16*i +: 16] = real_b2[i][15:0];
    end

    start_i = 0;
    rst_n = 0;
    repeat (4) @(negedge clk);
    rst_n = 1;
    repeat (2) @(negedge clk);

    start_i = 1;
    @(negedge clk);
    start_i = 0;

    wait (done == 1'b1);
    @(negedge clk);

    errors = 0;
    for (i = 0; i < 256; i = i + 1) begin
      got = r_out[16*i +: 16];
      if (got !== real_r[i][15:0]) begin
        errors = errors + 1;
        if (errors <= 10)
          $display("POLYVEC-BASEMUL FAIL[%0d]: got=%0d exp=%0d", i, $signed(got), real_r[i]);
      end
    end

    if (errors == 0)
      $display("RESULT: polyvec_basemul_acc.v matches real polyvec_basemul_acc_montgomery() exactly on all 256 coefficients (from a real crypto_kem_keypair round trip)");
    else
      $display("RESULT: FAIL (%0d/256 mismatches)", errors);

    $finish;
  end

endmodule
