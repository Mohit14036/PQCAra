`timescale 1ns/1ps
// tb_indcpa_keypair_real.sv -- checks indcpa_keypair_arith.v (which
// chains ntt_fwd + polyvec_basemul_acc + poly_tomont + poly_add +
// poly_barrett_pass) against REAL data captured from an actual
// ref/indcpa.c indcpa_keypair_derand() call:
//   vecs_keypair/indcpa_keypair_prentt_real.txt: 6 lines (skpv[0..2],
//     e[0..2], all 256 coeffs, PRE-ntt)
//   vecs_keypair/indcpa_keypair_real.txt: 18 lines (a[0][0..2],
//     a[1][0..2], a[2][0..2], skpv_ntt[0..2], e_ntt[0..2], pkpv[0..2])
// Checks two checkpoints: the NTT outputs (skpv_ntt/e_ntt) match the
// real post-polyvec_ntt values, AND the final pkpv matches the real
// public-key polyvec exactly.

module tb_indcpa_keypair_real;

  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [4095:0] a00,a01,a02, a10,a11,a12, a20,a21,a22;
  reg  [4095:0] skpv0,skpv1,skpv2, e0,e1,e2;
  wire [4095:0] skpv_ntt0,skpv_ntt1,skpv_ntt2;
  wire [4095:0] e_ntt0,e_ntt1,e_ntt2;
  wire [4095:0] pkpv0,pkpv1,pkpv2;
  reg           start_i;
  wire          done;

  indcpa_keypair_arith dut (
      .clk(clk), .rst_n(rst_n), .start_i(start_i),
      .a00_in(a00), .a01_in(a01), .a02_in(a02),
      .a10_in(a10), .a11_in(a11), .a12_in(a12),
      .a20_in(a20), .a21_in(a21), .a22_in(a22),
      .skpv0_in(skpv0), .skpv1_in(skpv1), .skpv2_in(skpv2),
      .e0_in(e0), .e1_in(e1), .e2_in(e2),
      .skpv_ntt0_out(skpv_ntt0), .skpv_ntt1_out(skpv_ntt1), .skpv_ntt2_out(skpv_ntt2),
      .e_ntt0_out(e_ntt0), .e_ntt1_out(e_ntt1), .e_ntt2_out(e_ntt2),
      .pkpv0_out(pkpv0), .pkpv1_out(pkpv1), .pkpv2_out(pkpv2),
      .done(done)
  );

  integer fd, r, i, errors;
  integer real_skpv_pre[0:2][0:255];
  integer real_e_pre[0:2][0:255];
  integer real_a[0:2][0:2][0:255];
  integer real_skpv_ntt[0:2][0:255];
  integer real_e_ntt[0:2][0:255];
  integer real_pkpv[0:2][0:255];
  reg signed [15:0] got;

  integer p, q, tmpv;

  initial begin
    fd = $fopen("vecs_keypair/indcpa_keypair_prentt_real.txt", "r");
    for (p = 0; p < 3; p = p + 1)
      for (q = 0; q < 256; q = q + 1) begin
        r = $fscanf(fd, "%d", tmpv); real_skpv_pre[p][q] = tmpv;
      end
    for (p = 0; p < 3; p = p + 1)
      for (q = 0; q < 256; q = q + 1) begin
        r = $fscanf(fd, "%d", tmpv); real_e_pre[p][q] = tmpv;
      end
    $fclose(fd);

    fd = $fopen("vecs_keypair/indcpa_keypair_real.txt", "r");
    for (p = 0; p < 3; p = p + 1)
      for (i = 0; i < 3; i = i + 1)
        for (q = 0; q < 256; q = q + 1) begin
          r = $fscanf(fd, "%d", tmpv); real_a[p][i][q] = tmpv;
        end
    for (p = 0; p < 3; p = p + 1)
      for (q = 0; q < 256; q = q + 1) begin
        r = $fscanf(fd, "%d", tmpv); real_skpv_ntt[p][q] = tmpv;
      end
    for (p = 0; p < 3; p = p + 1)
      for (q = 0; q < 256; q = q + 1) begin
        r = $fscanf(fd, "%d", tmpv); real_e_ntt[p][q] = tmpv;
      end
    for (p = 0; p < 3; p = p + 1)
      for (q = 0; q < 256; q = q + 1) begin
        r = $fscanf(fd, "%d", tmpv); real_pkpv[p][q] = tmpv;
      end
    $fclose(fd);

    a00 = 0; a01 = 0; a02 = 0; a10 = 0; a11 = 0; a12 = 0; a20 = 0; a21 = 0; a22 = 0;
    skpv0 = 0; skpv1 = 0; skpv2 = 0; e0 = 0; e1 = 0; e2 = 0;
    for (i = 0; i < 256; i = i + 1) begin
      a00[16*i +: 16] = real_a[0][0][i][15:0];
      a01[16*i +: 16] = real_a[0][1][i][15:0];
      a02[16*i +: 16] = real_a[0][2][i][15:0];
      a10[16*i +: 16] = real_a[1][0][i][15:0];
      a11[16*i +: 16] = real_a[1][1][i][15:0];
      a12[16*i +: 16] = real_a[1][2][i][15:0];
      a20[16*i +: 16] = real_a[2][0][i][15:0];
      a21[16*i +: 16] = real_a[2][1][i][15:0];
      a22[16*i +: 16] = real_a[2][2][i][15:0];
      skpv0[16*i +: 16] = real_skpv_pre[0][i][15:0];
      skpv1[16*i +: 16] = real_skpv_pre[1][i][15:0];
      skpv2[16*i +: 16] = real_skpv_pre[2][i][15:0];
      e0[16*i +: 16] = real_e_pre[0][i][15:0];
      e1[16*i +: 16] = real_e_pre[1][i][15:0];
      e2[16*i +: 16] = real_e_pre[2][i][15:0];
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

    begin
      integer cnt0, cnt1, cnt2, cnte0, cnte1, cnte2;
      cnt0=0; cnt1=0; cnt2=0; cnte0=0; cnte1=0; cnte2=0;
      for (i = 0; i < 256; i = i + 1) begin
        if (skpv_ntt0[16*i +: 16] !== real_skpv_ntt[0][i][15:0]) cnt0=cnt0+1;
        if (skpv_ntt1[16*i +: 16] !== real_skpv_ntt[1][i][15:0]) cnt1=cnt1+1;
        if (skpv_ntt2[16*i +: 16] !== real_skpv_ntt[2][i][15:0]) cnt2=cnt2+1;
        if (e_ntt0[16*i +: 16] !== real_e_ntt[0][i][15:0]) cnte0=cnte0+1;
        if (e_ntt1[16*i +: 16] !== real_e_ntt[1][i][15:0]) cnte1=cnte1+1;
        if (e_ntt2[16*i +: 16] !== real_e_ntt[2][i][15:0]) cnte2=cnte2+1;
      end
      $display("mismatch counts: skpv_ntt0=%0d skpv_ntt1=%0d skpv_ntt2=%0d e_ntt0=%0d e_ntt1=%0d e_ntt2=%0d",
                cnt0, cnt1, cnt2, cnte0, cnte1, cnte2);
      errors = errors + cnt0+cnt1+cnt2+cnte0+cnte1+cnte2;
    end

    if (errors == 0)
      $display("CHECKPOINT 1 PASS: skpv_ntt/e_ntt match real polyvec_ntt() output exactly (768+768 coeffs)");
    else
      $display("CHECKPOINT 1 FAIL: %0d mismatches", errors);

    for (i = 0; i < 256; i = i + 1) begin
      got = pkpv0[16*i +: 16];
      if (got !== real_pkpv[0][i][15:0]) begin errors=errors+1; if(errors<=10) $display("PKPV0 FAIL[%0d]: got=%0d exp=%0d",i,$signed(got),real_pkpv[0][i]); end
      got = pkpv1[16*i +: 16];
      if (got !== real_pkpv[1][i][15:0]) begin errors=errors+1; if(errors<=10) $display("PKPV1 FAIL[%0d]: got=%0d exp=%0d",i,$signed(got),real_pkpv[1][i]); end
      got = pkpv2[16*i +: 16];
      if (got !== real_pkpv[2][i][15:0]) begin errors=errors+1; if(errors<=10) $display("PKPV2 FAIL[%0d]: got=%0d exp=%0d",i,$signed(got),real_pkpv[2][i]); end
    end

    if (errors == 0)
      $display("RESULT: indcpa_keypair_arith.v matches real indcpa_keypair_derand() exactly (skpv_ntt, e_ntt, and final pkpv, all 256 coeffs x3 each, from a real crypto_kem_keypair round trip)");
    else
      $display("RESULT: FAIL (%0d total mismatches)", errors);

    $finish;
  end

endmodule
