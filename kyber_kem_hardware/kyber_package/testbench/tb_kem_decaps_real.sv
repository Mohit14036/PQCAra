`timescale 1ns/1ps
// tb_kem_decaps_real.sv -- the full-chain check for crypto_kem_dec(),
// i.e. the complete Fujisaki-Okamoto Decapsulation, built ENTIRELY from
// already-independently-verified modules (this session's tasks #6-11
// plus ct_verify.v/cmov_bytes.v built for task #12), driven with real
// data captured from a single real crypto_kem_keypair+enc+dec() run:
//
//   indcpa_dec(buf, ct, sk)              -- indcpa_dec_arith.v + poly_tomsg.v (task #11)
//   [hash_g(kr, buf||H(pk))]             -- REAL captured kr (SHA3-512 hardware not built; see note)
//   k = poly_frommsg(buf)                -- poly_frommsg.v (task #9)
//   cmp_polys = indcpa_enc(buf, pk, kr+32) -- indcpa_enc_arith.v (task #11)
//   cmp_bytes = pack_ciphertext(cmp_polys) -- poly_compress.v + polyvec_compress.v (task #9)
//   fail = verify(ct, cmp_bytes)          -- ct_verify.v (task #12)
//   [rkprf(...)]                          -- REAL captured pseudo-random reject key (SHAKE256-PRF hardware not built)
//   ss = cmov(rkprf_ss, kr, !fail)        -- cmov_bytes.v (task #12)
//
// NOTE on scope: SHA3-512 (hash_g) and the SHAKE256-based rkprf are NOT
// built as RTL in this project -- their real outputs are taken as
// captured inputs at the module boundary (same treatment as the
// already-verified matrix-generation XOF bytes in task #7). Every other
// step -- the IND-CPA decrypt, the re-encryption, the ciphertext pack,
// the constant-time compare, and the constant-time implicit-rejection
// select -- is real, independently-verified RTL, chained together and
// checked end-to-end against a real crypto_kem_dec() call.

module tb_kem_decaps_real;

  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  // ---- step 1: indcpa_dec_arith + poly_tomsg -> buf (decrypted msg bytes) ----
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

  // ---- step 2: poly_frommsg(buf) -> k ----
  reg           frommsg_start;
  wire [4095:0] k_poly;
  wire          frommsg_done;
  poly_frommsg u_frommsg (.clk(clk), .rst_n(rst_n), .start_i(frommsg_start),
                           .msg_in(buf_msg), .coeffs_out(k_poly), .done(frommsg_done));

  // ---- step 3: indcpa_enc_arith (re-encryption) -> cmp b/v polys ----
  reg  [4095:0] at00,at01,at02, at10,at11,at12, at20,at21,at22;
  reg  [4095:0] pkpv0,pkpv1,pkpv2;
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
      .k_in(k_poly),
      .sp0_in(sp0), .sp1_in(sp1), .sp2_in(sp2),
      .ep0_in(ep0), .ep1_in(ep1), .ep2_in(ep2),
      .epp_in(epp_r),
      .sp_ntt0_out(sp_ntt0), .sp_ntt1_out(sp_ntt1), .sp_ntt2_out(sp_ntt2),
      .b0_out(cmp_b0), .b1_out(cmp_b1), .b2_out(cmp_b2), .v_out(cmp_v),
      .done(enc_done));

  // ---- step 4: pack cmp_b/cmp_v -> cmp bytes ----
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

  // ---- step 5: ct_verify(ct, cmp) ----
  localparam CTBYTES = 1088;
  reg  [8*CTBYTES-1:0] ct_real;
  reg  [8*CTBYTES-1:0] cmp_full;
  reg           vstart;
  wire          vfail, vdone;
  ct_verify #(.CTBYTES(CTBYTES)) u_verify (.clk(clk), .rst_n(rst_n), .start_i(vstart),
      .ct_a_in(ct_real), .ct_b_in(cmp_full), .fail_out(vfail), .done(vdone));

  // ---- step 6: cmov(rkprf_ss, kr, !fail) -> final ss ----
  reg  [255:0] rkprf_ss_r, kr_r;
  reg          mstart;
  wire [255:0] ss_out;
  wire         mdone;
  cmov_bytes #(.NBYTES(32)) u_cmov (.clk(clk), .rst_n(rst_n), .start_i(mstart),
      .r_in(rkprf_ss_r), .x_in(kr_r), .sel_in(!vfail), .r_out(ss_out), .done(mdone));

  // ---- real data loading ----
  integer fd, r, i, p, q, tmpv, errors;
  integer real_b_pre[0:2][0:255];
  integer real_skpv[0:2][0:255];
  integer real_v[0:255];
  integer real_msg_expected[0:31];   // from vecs_dec (task11-style, same run)

  integer real_at2[0:2][0:2][0:255];
  integer real_pkpv2[0:2][0:255];
  integer real_k2[0:255];
  integer real_sp2[0:2][0:255], real_ep2[0:2][0:255], real_epp2[0:255];
  integer real_cmpbytes_expected[0:1087];

  integer real_ct[0:1087], real_cmp_check[0:1087];
  integer real_fail;
  integer real_kr[0:63];
  integer real_rkprf_ss[0:31];
  integer real_final_ss[0:31];

  reg signed [15:0] got;
  reg [7:0] gotb;

  initial begin
    // --- indcpa_dec inputs (real b pre-NTT, skpv, v; same run as vecs_kem) ---
    fd = $fopen("vecs_dec/indcpa_dec_prentt_real.txt", "r");
    for (i = 0; i < 3; i = i + 1)
      for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_b_pre[i][q]=tmpv; end
    $fclose(fd);
    fd = $fopen("vecs_dec/indcpa_dec_real.txt", "r");
    for (i = 0; i < 3; i = i + 1)  // b_ntt checkpoint (skip)
      for (q = 0; q < 256; q = q + 1) r = $fscanf(fd,"%d",tmpv);
    for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_v[q]=tmpv; end
    for (i = 0; i < 3; i = i + 1)
      for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_skpv[i][q]=tmpv; end
    for (q = 0; q < 256; q = q + 1) r = $fscanf(fd,"%d",tmpv);   // mp (skip, re-derived)
    for (q = 0; q < 32; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_msg_expected[q]=tmpv; end
    $fclose(fd);

    // --- indcpa_enc2 inputs (real at, pkpv, sp/ep/epp for the RE-ENCRYPTION) ---
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
    for (p = 0; p < 3; p = p + 1)  // b (skip, re-derived)
      for (q = 0; q < 256; q = q + 1) r = $fscanf(fd,"%d",tmpv);
    for (q = 0; q < 256; q = q + 1) r = $fscanf(fd,"%d",tmpv);   // v (skip, re-derived)
    for (q = 0; q < 1088; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_cmpbytes_expected[q]=tmpv; end
    $fclose(fd);

    // --- top-level KEM decaps boundary values ---
    fd = $fopen("vecs_kem/kem_dec_real.txt", "r");
    for (i = 0; i < 1088; i = i + 1) begin r=$fscanf(fd,"%d",tmpv); real_ct[i]=tmpv; end
    for (i = 0; i < 1088; i = i + 1) begin r=$fscanf(fd,"%d",tmpv); real_cmp_check[i]=tmpv; end
    r = $fscanf(fd, "%d", real_fail);
    for (i = 0; i < 64; i = i + 1) begin r=$fscanf(fd,"%d",tmpv); real_kr[i]=tmpv; end
    for (i = 0; i < 32; i = i + 1) begin r=$fscanf(fd,"%d",tmpv); real_rkprf_ss[i]=tmpv; end
    for (i = 0; i < 32; i = i + 1) begin r=$fscanf(fd,"%d",tmpv); real_final_ss[i]=tmpv; end
    $fclose(fd);

    // --- drive inputs ---
    b0=0;b1=0;b2=0;v_r=0;skpv0=0;skpv1=0;skpv2=0;
    at00=0;at01=0;at02=0;at10=0;at11=0;at12=0;at20=0;at21=0;at22=0;
    pkpv0=0;pkpv1=0;pkpv2=0;sp0=0;sp1=0;sp2=0;ep0=0;ep1=0;ep2=0;epp_r=0;
    for (i = 0; i < 256; i = i + 1) begin
      b0[16*i+:16]=real_b_pre[0][i][15:0]; b1[16*i+:16]=real_b_pre[1][i][15:0]; b2[16*i+:16]=real_b_pre[2][i][15:0];
      v_r[16*i+:16]=real_v[i][15:0];
      skpv0[16*i+:16]=real_skpv[0][i][15:0]; skpv1[16*i+:16]=real_skpv[1][i][15:0]; skpv2[16*i+:16]=real_skpv[2][i][15:0];
      at00[16*i+:16]=real_at2[0][0][i][15:0]; at01[16*i+:16]=real_at2[0][1][i][15:0]; at02[16*i+:16]=real_at2[0][2][i][15:0];
      at10[16*i+:16]=real_at2[1][0][i][15:0]; at11[16*i+:16]=real_at2[1][1][i][15:0]; at12[16*i+:16]=real_at2[1][2][i][15:0];
      at20[16*i+:16]=real_at2[2][0][i][15:0]; at21[16*i+:16]=real_at2[2][1][i][15:0]; at22[16*i+:16]=real_at2[2][2][i][15:0];
      pkpv0[16*i+:16]=real_pkpv2[0][i][15:0]; pkpv1[16*i+:16]=real_pkpv2[1][i][15:0]; pkpv2[16*i+:16]=real_pkpv2[2][i][15:0];
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

    dec_start=0; tomsg_start=0; frommsg_start=0; enc_start=0;
    pvc_start=0; pc_start=0; vstart=0; mstart=0;
    rst_n = 0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

    errors = 0;

    // step 1
    dec_start = 1; @(negedge clk); dec_start = 0;
    wait (dec_done == 1'b1); @(negedge clk);
    tomsg_start = 1; @(negedge clk); tomsg_start = 0;
    wait (tomsg_done == 1'b1); @(negedge clk);
    for (i = 0; i < 32; i = i + 1) begin
      gotb = buf_msg[8*i+:8];
      if (gotb !== real_msg_expected[i][7:0]) begin errors=errors+1; $display("BUF FAIL[%0d]: got=%0d exp=%0d",i,gotb,real_msg_expected[i]); end
    end
    $display("step1 (indcpa_dec): buf msg mismatches=%0d/32", errors);

    // step 2
    frommsg_start = 1; @(negedge clk); frommsg_start = 0;
    wait (frommsg_done == 1'b1); @(negedge clk);
    begin
      integer kerr; kerr = 0;
      for (i = 0; i < 256; i = i + 1) begin
        got = k_poly[16*i+:16];
        if (got !== real_k2[i][15:0]) kerr = kerr + 1;
      end
      $display("step2 (poly_frommsg): k mismatches=%0d/256 (cross-checks against real indcpa_enc2's k)", kerr);
      errors = errors + kerr;
    end

    // step 3
    enc_start = 1; @(negedge clk); enc_start = 0;
    wait (enc_done == 1'b1); @(negedge clk);

    // step 4
    pvc_start = 1; @(negedge clk); pvc_start = 0;
    pc_start  = 1; @(negedge clk); pc_start  = 0;
    wait (pvc_done == 1'b1 && pc_done == 1'b1); @(negedge clk);

    cmp_full = 0;
    cmp_full[8*960-1:0] = cmp_bvec_bytes;
    cmp_full[8*1088-1 : 8*960] = cmp_v_bytes;

    begin
      integer cerr; cerr = 0;
      for (i = 0; i < 1088; i = i + 1) begin
        gotb = cmp_full[8*i+:8];
        if (gotb !== real_cmpbytes_expected[i][7:0]) cerr = cerr + 1;
      end
      $display("step3+4 (indcpa_enc re-encrypt + pack): cmp bytes mismatches=%0d/1088", cerr);
      errors = errors + cerr;
    end

    // step 5
    vstart = 1; @(negedge clk); vstart = 0;
    wait (vdone == 1'b1); @(negedge clk);
    if (vfail !== real_fail[0]) begin
      errors = errors + 1;
      $display("step5 (ct_verify) FAIL: got fail=%0d exp=%0d", vfail, real_fail);
    end else
      $display("step5 (ct_verify): fail=%0d (matches real verify())", vfail);

    // step 6
    mstart = 1; @(negedge clk); mstart = 0;
    wait (mdone == 1'b1); @(negedge clk);
    begin
      integer serr; serr = 0;
      for (i = 0; i < 32; i = i + 1) begin
        gotb = ss_out[8*i+:8];
        if (gotb !== real_final_ss[i][7:0]) serr = serr + 1;
      end
      $display("step6 (cmov_bytes): final ss mismatches=%0d/32", serr);
      errors = errors + serr;
    end

    if (errors == 0)
      $display("RESULT: FULL crypto_kem_dec() Decapsulation (IND-CPA decrypt -> re-encrypt -> pack -> constant-time compare -> constant-time implicit-rejection select) matches the real reference EXACTLY end-to-end, built entirely from independently-verified RTL (SHA3-512/SHAKE256-PRF hash outputs taken as real captured boundary data)");
    else
      $display("RESULT: FAIL (%0d total mismatches)", errors);

    $finish;
  end

endmodule
