`timescale 1ns/1ps
// tb_kem_decaps_partA.sv -- part A of the crypto_kem_dec() full-chain
// check: indcpa_dec_arith + poly_tomsg + poly_frommsg, verifying the
// decrypted message bytes AND that re-encoding them reproduces the
// real message poly k used by the real re-encryption (indcpa_enc2).
// Split out from the monolithic tb_kem_decaps_real.sv purely because
// combining every module into one Icarus simulation was extremely slow;
// splitting into fast, independently-run stages proves the same chain.

module tb_kem_decaps_partA;

  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [4095:0] b0,b1,b2, v_r, skpv0,skpv1,skpv2;
  wire [4095:0] b_ntt0,b_ntt1,b_ntt2, mp_o;
  reg           dec_start;
  wire          dec_done;
  indcpa_dec_arith u_dec (.clk(clk), .rst_n(rst_n), .start_i(dec_start),
      .b0_in(b0), .b1_in(b1), .b2_in(b2), .v_in(v_r),
      .skpv0_in(skpv0), .skpv1_in(skpv1), .skpv2_in(skpv2),
      .b_ntt0_out(b_ntt0), .b_ntt1_out(b_ntt1), .b_ntt2_out(b_ntt2),
      .mp_out(mp_o), .done(dec_done));

  reg           tomsg_start;
  wire [255:0]  buf_msg;
  wire          tomsg_done;
  poly_tomsg u_tomsg (.clk(clk), .rst_n(rst_n), .start_i(tomsg_start),
                       .coeffs_in(mp_o), .msg_out(buf_msg), .done(tomsg_done));

  reg           frommsg_start;
  wire [4095:0] k_poly;
  wire          frommsg_done;
  poly_frommsg u_frommsg (.clk(clk), .rst_n(rst_n), .start_i(frommsg_start),
                           .msg_in(buf_msg), .coeffs_out(k_poly), .done(frommsg_done));

  integer fd, r, i, q, tmpv, errors;
  integer real_b_pre[0:2][0:255];
  integer real_skpv[0:2][0:255];
  integer real_v[0:255];
  integer real_msg_expected[0:31];
  integer real_k2[0:255];
  reg signed [15:0] got;
  reg [7:0] gotb;

  initial begin
    fd = $fopen("vecs_dec/indcpa_dec_prentt_real.txt", "r");
    for (i = 0; i < 3; i = i + 1)
      for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_b_pre[i][q]=tmpv; end
    $fclose(fd);
    fd = $fopen("vecs_dec/indcpa_dec_real.txt", "r");
    for (i = 0; i < 3; i = i + 1)
      for (q = 0; q < 256; q = q + 1) r = $fscanf(fd,"%d",tmpv);       // b_ntt checkpoint (skip)
    for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_v[q]=tmpv; end
    for (i = 0; i < 3; i = i + 1)
      for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_skpv[i][q]=tmpv; end
    for (q = 0; q < 256; q = q + 1) r = $fscanf(fd,"%d",tmpv);          // mp (skip, re-derived)
    for (q = 0; q < 32; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_msg_expected[q]=tmpv; end
    $fclose(fd);

    fd = $fopen("vecs_kem/indcpa_enc2_real.txt", "r");
    for (i = 0; i < 9; i = i + 1)
      for (q = 0; q < 256; q = q + 1) r = $fscanf(fd,"%d",tmpv);        // at2 (skip)
    for (i = 0; i < 3; i = i + 1)
      for (q = 0; q < 256; q = q + 1) r = $fscanf(fd,"%d",tmpv);        // pkpv2 (skip)
    for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_k2[q]=tmpv; end
    $fclose(fd);

    b0=0;b1=0;b2=0;v_r=0;skpv0=0;skpv1=0;skpv2=0;
    for (i = 0; i < 256; i = i + 1) begin
      b0[16*i+:16]=real_b_pre[0][i][15:0]; b1[16*i+:16]=real_b_pre[1][i][15:0]; b2[16*i+:16]=real_b_pre[2][i][15:0];
      v_r[16*i+:16]=real_v[i][15:0];
      skpv0[16*i+:16]=real_skpv[0][i][15:0]; skpv1[16*i+:16]=real_skpv[1][i][15:0]; skpv2[16*i+:16]=real_skpv[2][i][15:0];
    end

    dec_start=0; tomsg_start=0; frommsg_start=0; rst_n=0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

    errors = 0;
    dec_start = 1; @(negedge clk); dec_start = 0;
    wait (dec_done == 1'b1); @(negedge clk);
    tomsg_start = 1; @(negedge clk); tomsg_start = 0;
    wait (tomsg_done == 1'b1); @(negedge clk);
    for (i = 0; i < 32; i = i + 1) begin
      gotb = buf_msg[8*i+:8];
      if (gotb !== real_msg_expected[i][7:0]) begin errors=errors+1; $display("BUF FAIL[%0d]: got=%0d exp=%0d",i,gotb,real_msg_expected[i]); end
    end

    frommsg_start = 1; @(negedge clk); frommsg_start = 0;
    wait (frommsg_done == 1'b1); @(negedge clk);
    for (i = 0; i < 256; i = i + 1) begin
      got = k_poly[16*i+:16];
      if (got !== real_k2[i][15:0]) begin errors=errors+1; if(errors<=10) $display("K FAIL[%0d]: got=%0d exp=%0d",i,$signed(got),real_k2[i]); end
    end

    if (errors == 0)
      $display("RESULT PART A: indcpa_dec_arith + poly_tomsg + poly_frommsg reproduce the real decrypted message AND the real re-encryption's message polynomial k exactly -- confirms the dec-to-re-encrypt handoff is correct.");
    else
      $display("RESULT PART A: FAIL (%0d mismatches)", errors);

    $finish;
  end

endmodule
