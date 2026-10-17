`timescale 1ns/1ps
// tb_kem_decaps_partB.sv -- part B of the crypto_kem_dec() full-chain
// check: indcpa_enc_arith (re-encryption) + poly_compress/polyvec_compress
// (pack) + ct_verify (constant-time compare) + cmov_bytes (implicit-
// rejection select), taking the REAL k (already proven in part A to be
// exactly what indcpa_dec_arith+poly_tomsg+poly_frommsg produce) and the
// real at/pkpv/sp/ep/epp for the re-encryption, through to the final
// shared secret, checked against a real crypto_kem_dec() call.

module tb_kem_decaps_partB;

  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [4095:0] at00,at01,at02, at10,at11,at12, at20,at21,at22;
  reg  [4095:0] pkpv0,pkpv1,pkpv2, k_r;
  reg  [4095:0] sp0,sp1,sp2, ep0,ep1,ep2, epp_r;
  wire [4095:0] sp_ntt0,sp_ntt1,sp_ntt2;
  wire [4095:0] cmp_b0,cmp_b1,cmp_b2,cmp_v;
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
      .b0_out(cmp_b0), .b1_out(cmp_b1), .b2_out(cmp_b2), .v_out(cmp_v),
      .done(enc_done));

  reg           pvc_start;
  wire [7679:0] cmp_bvec_bytes;
  wire          pvc_done;
  polyvec_compress u_pvc (.clk(clk), .rst_n(rst_n), .start_i(pvc_start),
                           .a0_in(cmp_b0), .a1_in(cmp_b1), .a2_in(cmp_b2),
                           .bytes_out(cmp_bvec_bytes), .done(pvc_done));

  reg           pc_start;
  wire [1023:0] cmp_v_bytes;
  wire          pc_done;
  poly_compress u_pc (.clk(clk), .rst_n(rst_n), .start_i(pc_start),
                       .coeffs_in(cmp_v), .bytes_out(cmp_v_bytes), .done(pc_done));

  localparam CTBYTES = 1088;
  reg  [8*CTBYTES-1:0] ct_real;
  reg  [8*CTBYTES-1:0] cmp_full;
  reg           vstart;
  wire          vfail, vdone;
  ct_verify #(.CTBYTES(CTBYTES)) u_verify (.clk(clk), .rst_n(rst_n), .start_i(vstart),
      .ct_a_in(ct_real), .ct_b_in(cmp_full), .fail_out(vfail), .done(vdone));

  reg  [255:0] rkprf_ss_r, kr_r;
  reg          mstart;
  wire [255:0] ss_out;
  wire         mdone;
  cmov_bytes #(.NBYTES(32)) u_cmov (.clk(clk), .rst_n(rst_n), .start_i(mstart),
      .r_in(rkprf_ss_r), .x_in(kr_r), .sel_in(!vfail), .r_out(ss_out), .done(mdone));

  integer fd, r, i, p, q, tmpv, errors;
  integer real_at2[0:2][0:2][0:255];
  integer real_pkpv2[0:2][0:255];
  integer real_k2[0:255];
  integer real_sp2[0:2][0:255], real_ep2[0:2][0:255], real_epp2[0:255];
  integer real_cmpbytes_expected[0:1087];
  integer real_ct[0:1087];
  integer real_fail;
  integer real_kr[0:63];
  integer real_rkprf_ss[0:31];
  integer real_final_ss[0:31];
  reg signed [15:0] got;
  reg [7:0] gotb;

  initial begin
    fd = $fopen("vecs_kem/indcpa_enc2_prentt_real.txt", "r");
    for (i = 0; i < 3; i = i + 1)
      for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_sp2[i][q]=tmpv; end
    for (i = 0; i < 3; i = i + 1)
      for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_ep2[i][q]=tmpv; end
    for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_epp2[q]=tmpv; end
    $fclose(fd);

    fd = $fopen("vecs_kem/indcpa_enc2_real.txt", "r");
    for (p = 0; p < 3; p = p + 1)
      for (i = 0; i < 3; i = i + 1)
        for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_at2[p][i][q]=tmpv; end
    for (p = 0; p < 3; p = p + 1)
      for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_pkpv2[p][q]=tmpv; end
    for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_k2[q]=tmpv; end
    for (p = 0; p < 3; p = p + 1)
      for (q = 0; q < 256; q = q + 1) r = $fscanf(fd,"%d",tmpv);      // b (skip, re-derived)
    for (q = 0; q < 256; q = q + 1) r = $fscanf(fd,"%d",tmpv);         // v (skip, re-derived)
    for (q = 0; q < 1088; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_cmpbytes_expected[q]=tmpv; end
    $fclose(fd);

    fd = $fopen("vecs_kem/kem_dec_real.txt", "r");
    for (i = 0; i < 1088; i = i + 1) begin r=$fscanf(fd,"%d",tmpv); real_ct[i]=tmpv; end
    for (i = 0; i < 1088; i = i + 1) r = $fscanf(fd,"%d",tmpv);        // cmp (skip, re-derived)
    r = $fscanf(fd, "%d", real_fail);
    for (i = 0; i < 64; i = i + 1) begin r=$fscanf(fd,"%d",tmpv); real_kr[i]=tmpv; end
    for (i = 0; i < 32; i = i + 1) begin r=$fscanf(fd,"%d",tmpv); real_rkprf_ss[i]=tmpv; end
    for (i = 0; i < 32; i = i + 1) begin r=$fscanf(fd,"%d",tmpv); real_final_ss[i]=tmpv; end
    $fclose(fd);

    at00=0;at01=0;at02=0;at10=0;at11=0;at12=0;at20=0;at21=0;at22=0;
    pkpv0=0;pkpv1=0;pkpv2=0;k_r=0;sp0=0;sp1=0;sp2=0;ep0=0;ep1=0;ep2=0;epp_r=0;
    for (i = 0; i < 256; i = i + 1) begin
      at00[16*i+:16]=real_at2[0][0][i][15:0]; at01[16*i+:16]=real_at2[0][1][i][15:0]; at02[16*i+:16]=real_at2[0][2][i][15:0];
      at10[16*i+:16]=real_at2[1][0][i][15:0]; at11[16*i+:16]=real_at2[1][1][i][15:0]; at12[16*i+:16]=real_at2[1][2][i][15:0];
      at20[16*i+:16]=real_at2[2][0][i][15:0]; at21[16*i+:16]=real_at2[2][1][i][15:0]; at22[16*i+:16]=real_at2[2][2][i][15:0];
      pkpv0[16*i+:16]=real_pkpv2[0][i][15:0]; pkpv1[16*i+:16]=real_pkpv2[1][i][15:0]; pkpv2[16*i+:16]=real_pkpv2[2][i][15:0];
      k_r[16*i+:16]=real_k2[i][15:0];
      sp0[16*i+:16]=real_sp2[0][i][15:0]; sp1[16*i+:16]=real_sp2[1][i][15:0]; sp2[16*i+:16]=real_sp2[2][i][15:0];
      ep0[16*i+:16]=real_ep2[0][i][15:0]; ep1[16*i+:16]=real_ep2[1][i][15:0]; ep2[16*i+:16]=real_ep2[2][i][15:0];
      epp_r[16*i+:16]=real_epp2[i][15:0];
    end
    ct_real = 0;
    for (i = 0; i < 1088; i = i + 1) ct_real[8*i+:8] = real_ct[i][7:0];
    rkprf_ss_r = 0; kr_r = 0;
    for (i = 0; i < 32; i = i + 1) begin
      rkprf_ss_r[8*i+:8] = real_rkprf_ss[i][7:0];
      kr_r[8*i+:8]        = real_kr[i][7:0];
    end

    enc_start=0; pvc_start=0; pc_start=0; vstart=0; mstart=0; rst_n=0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

    errors = 0;

    enc_start = 1; @(negedge clk); enc_start = 0;
    wait (enc_done == 1'b1); @(negedge clk);

    pvc_start = 1; @(negedge clk); pvc_start = 0;
    wait (pvc_done == 1'b1); @(negedge clk);
    pc_start = 1; @(negedge clk); pc_start = 0;
    wait (pc_done == 1'b1); @(negedge clk);

    cmp_full = 0;
    cmp_full[8*960-1:0] = cmp_bvec_bytes;
    cmp_full[8*1088-1 : 8*960] = cmp_v_bytes;

    for (i = 0; i < 1088; i = i + 1) begin
      gotb = cmp_full[8*i+:8];
      if (gotb !== real_cmpbytes_expected[i][7:0]) begin errors=errors+1; if(errors<=5) $display("CMP FAIL[%0d]: got=%0d exp=%0d",i,gotb,real_cmpbytes_expected[i]); end
    end
    $display("re-encrypt+pack: cmp bytes mismatches=%0d/1088", errors);

    vstart = 1; @(negedge clk); vstart = 0;
    wait (vdone == 1'b1); @(negedge clk);
    if (vfail !== real_fail[0]) begin
      errors = errors + 1;
      $display("ct_verify FAIL: got fail=%0d exp=%0d", vfail, real_fail);
    end else
      $display("ct_verify: fail=%0d (matches real verify())", vfail);

    mstart = 1; @(negedge clk); mstart = 0;
    wait (mdone == 1'b1); @(negedge clk);
    for (i = 0; i < 32; i = i + 1) begin
      gotb = ss_out[8*i+:8];
      if (gotb !== real_final_ss[i][7:0]) begin errors=errors+1; $display("SS FAIL[%0d]: got=%0d exp=%0d",i,gotb,real_final_ss[i]); end
    end

    if (errors == 0)
      $display("RESULT PART B: re-encryption + pack + constant-time-compare + constant-time-select reproduce the real final shared secret exactly.");
    else
      $display("RESULT PART B: FAIL (%0d mismatches)", errors);

    $finish;
  end

endmodule
