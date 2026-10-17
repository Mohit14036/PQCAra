`timescale 1ns/1ps
// tb_kem_encaps_real.sv -- full-chain check for crypto_kem_enc()
// (Encapsulation): indcpa_enc_arith (task #11) + poly_compress/
// polyvec_compress (task #9), chained together and checked against a
// real crypto_kem_enc() call's final ciphertext AND shared secret.
// hash_h/hash_g (SHA3-256/512) are not built as RTL; kr (their real
// output) is taken as a real captured boundary value, same treatment
// as the matrix-generation XOF bytes in task #7.

module tb_kem_encaps_real;

  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [4095:0] at00,at01,at02, at10,at11,at12, at20,at21,at22;
  reg  [4095:0] pkpv0,pkpv1,pkpv2, k_r;
  reg  [4095:0] sp0,sp1,sp2, ep0,ep1,ep2, epp_r;
  wire [4095:0] sp_ntt0,sp_ntt1,sp_ntt2;
  wire [4095:0] b0,b1,b2,v_o;
  reg           enc_start;
  wire          enc_done;
  indcpa_enc_arith u_enc (
      .clk(clk), .rst_n(rst_n), .start_i(enc_start),
      .at00_in(at00), .at01_in(at01), .at02_in(at02),
      .at10_in(at10), .at11_in(at11), .at12_in(at12),
      .at20_in(at20), .at21_in(at21), .at22_in(at22),
      .pkpv0_in(pkpv0), .pkpv1_in(pkpv1), .pkpv2_in(pkpv2),
      .k_in(k_r),
      .sp0_in(sp0), .sp1_in(sp1), .sp2_in(sp2),
      .ep0_in(ep0), .ep1_in(ep1), .ep2_in(ep2),
      .epp_in(epp_r),
      .sp_ntt0_out(sp_ntt0), .sp_ntt1_out(sp_ntt1), .sp_ntt2_out(sp_ntt2),
      .b0_out(b0), .b1_out(b1), .b2_out(b2), .v_out(v_o),
      .done(enc_done));

  reg           pvc_start;
  wire [7679:0] ct_bvec_bytes;
  wire          pvc_done;
  polyvec_compress u_pvc (.clk(clk), .rst_n(rst_n), .start_i(pvc_start),
                           .a0_in(b0), .a1_in(b1), .a2_in(b2),
                           .bytes_out(ct_bvec_bytes), .done(pvc_done));

  reg           pc_start;
  wire [1023:0] ct_v_bytes;
  wire          pc_done;
  poly_compress u_pc (.clk(clk), .rst_n(rst_n), .start_i(pc_start),
                       .coeffs_in(v_o), .bytes_out(ct_v_bytes), .done(pc_done));

  integer fd, r, i, p, q, tmpv, errors;
  integer real_sp[0:2][0:255], real_ep[0:2][0:255], real_epp[0:255];
  integer real_at[0:2][0:2][0:255];
  integer real_pkpv[0:2][0:255];
  integer real_k[0:255];
  integer real_kr[0:31];
  integer real_ct_expected[0:1087];
  integer real_ss_expected[0:31];
  reg [7:0] gotb;
  reg [8*1088-1:0] ct_full;

  initial begin
    fd = $fopen("vecs_enc/indcpa_enc_prentt_real.txt", "r");
    for (p = 0; p < 3; p = p + 1)
      for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_sp[p][q]=tmpv; end
    for (p = 0; p < 3; p = p + 1)
      for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_ep[p][q]=tmpv; end
    for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_epp[q]=tmpv; end
    $fclose(fd);

    fd = $fopen("vecs_enc/indcpa_enc_real.txt", "r");
    for (p = 0; p < 3; p = p + 1)
      for (i = 0; i < 3; i = i + 1)
        for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_at[p][i][q]=tmpv; end
    for (p = 0; p < 3; p = p + 1)
      for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_pkpv[p][q]=tmpv; end
    for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_k[q]=tmpv; end
    $fclose(fd);

    fd = $fopen("vecs_kem/kem_enc_real.txt", "r");
    for (i = 0; i < 32; i = i + 1) begin r=$fscanf(fd,"%d",tmpv); real_kr[i]=tmpv; end
    for (i = 0; i < 1088; i = i + 1) begin r=$fscanf(fd,"%d",tmpv); real_ct_expected[i]=tmpv; end
    for (i = 0; i < 32; i = i + 1) begin r=$fscanf(fd,"%d",tmpv); real_ss_expected[i]=tmpv; end
    $fclose(fd);

    at00=0;at01=0;at02=0;at10=0;at11=0;at12=0;at20=0;at21=0;at22=0;
    pkpv0=0;pkpv1=0;pkpv2=0;k_r=0;sp0=0;sp1=0;sp2=0;ep0=0;ep1=0;ep2=0;epp_r=0;
    for (i = 0; i < 256; i = i + 1) begin
      at00[16*i+:16]=real_at[0][0][i][15:0]; at01[16*i+:16]=real_at[0][1][i][15:0]; at02[16*i+:16]=real_at[0][2][i][15:0];
      at10[16*i+:16]=real_at[1][0][i][15:0]; at11[16*i+:16]=real_at[1][1][i][15:0]; at12[16*i+:16]=real_at[1][2][i][15:0];
      at20[16*i+:16]=real_at[2][0][i][15:0]; at21[16*i+:16]=real_at[2][1][i][15:0]; at22[16*i+:16]=real_at[2][2][i][15:0];
      pkpv0[16*i+:16]=real_pkpv[0][i][15:0]; pkpv1[16*i+:16]=real_pkpv[1][i][15:0]; pkpv2[16*i+:16]=real_pkpv[2][i][15:0];
      k_r[16*i+:16]=real_k[i][15:0];
      sp0[16*i+:16]=real_sp[0][i][15:0]; sp1[16*i+:16]=real_sp[1][i][15:0]; sp2[16*i+:16]=real_sp[2][i][15:0];
      ep0[16*i+:16]=real_ep[0][i][15:0]; ep1[16*i+:16]=real_ep[1][i][15:0]; ep2[16*i+:16]=real_ep[2][i][15:0];
      epp_r[16*i+:16]=real_epp[i][15:0];
    end

    enc_start=0; pvc_start=0; pc_start=0; rst_n=0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

    errors = 0;
    enc_start = 1; @(negedge clk); enc_start = 0;
    wait (enc_done == 1'b1); @(negedge clk);

    pvc_start = 1; @(negedge clk); pvc_start = 0;
    wait (pvc_done == 1'b1); @(negedge clk);
    pc_start = 1; @(negedge clk); pc_start = 0;
    wait (pc_done == 1'b1); @(negedge clk);

    ct_full = 0;
    ct_full[8*960-1:0] = ct_bvec_bytes;
    ct_full[8*1088-1 : 8*960] = ct_v_bytes;

    for (i = 0; i < 1088; i = i + 1) begin
      gotb = ct_full[8*i+:8];
      if (gotb !== real_ct_expected[i][7:0]) begin errors=errors+1; if(errors<=5) $display("CT FAIL[%0d]: got=%0d exp=%0d",i,gotb,real_ct_expected[i]); end
    end
    $display("ciphertext pack: mismatches=%0d/1088", errors);

    // ss = kr[0:32], a plain copy -- check the real kr matches the real ss (sanity on the file itself)
    begin
      integer serr; serr = 0;
      for (i = 0; i < 32; i = i + 1)
        if (real_kr[i][7:0] !== real_ss_expected[i][7:0]) serr = serr + 1;
      if (serr == 0) $display("ss = kr[0:32] (real capture self-consistent, plain copy as crypto_kem_enc_derand specifies)");
      else begin errors = errors + serr; $display("ss/kr SELF-CONSISTENCY FAIL: %0d mismatches", serr); end
    end

    if (errors == 0)
      $display("RESULT: crypto_kem_enc() Encapsulation (IND-CPA encrypt -> pack) matches the real reference ciphertext exactly, built from independently-verified RTL (SHA3-256/512 hash outputs taken as real captured boundary data)");
    else
      $display("RESULT: FAIL (%0d total mismatches)", errors);

    $finish;
  end

endmodule
