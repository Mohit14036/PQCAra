`timescale 1ns/1ps
// tb_indcpa_enc_real.sv -- checks indcpa_enc_arith.v against REAL data
// captured from an actual ref/indcpa.c indcpa_enc() call.
//   vecs_enc/indcpa_enc_prentt_real.txt: 7 lines (sp[0..2], ep[0..2],
//     epp), all 256 coeffs, pre-NTT
//   vecs_enc/indcpa_enc_real.txt: 17 lines (at[0][0..2], at[1][0..2],
//     at[2][0..2], pkpv[0..2], k, b[0..2], v)

module tb_indcpa_enc_real;

  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [4095:0] at00,at01,at02, at10,at11,at12, at20,at21,at22;
  reg  [4095:0] pkpv0,pkpv1,pkpv2, k_r;
  reg  [4095:0] sp0,sp1,sp2, ep0,ep1,ep2, epp_r;
  wire [4095:0] sp_ntt0,sp_ntt1,sp_ntt2;
  wire [4095:0] b0,b1,b2,v_o;
  reg           start_i;
  wire          done;

  indcpa_enc_arith dut (
      .clk(clk), .rst_n(rst_n), .start_i(start_i),
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
      .done(done)
  );

  integer fd, r, i, p, q, tmpv, errors;
  integer real_sp[0:2][0:255], real_ep[0:2][0:255], real_epp[0:255];
  integer real_at[0:2][0:2][0:255];
  integer real_pkpv[0:2][0:255];
  integer real_k[0:255];
  integer real_b[0:2][0:255], real_v[0:255];
  reg signed [15:0] got;

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
    for (p = 0; p < 3; p = p + 1)
      for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_b[p][q]=tmpv; end
    for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_v[q]=tmpv; end
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

    start_i = 0; rst_n = 0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);
    start_i = 1; @(negedge clk); start_i = 0;
    wait (done == 1'b1); @(negedge clk);

    errors = 0;
    for (i = 0; i < 256; i = i + 1) begin
      got = b0[16*i+:16]; if (got !== real_b[0][i][15:0]) begin errors=errors+1; if(errors<=10) $display("B0 FAIL[%0d]: got=%0d exp=%0d",i,$signed(got),real_b[0][i]); end
      got = b1[16*i+:16]; if (got !== real_b[1][i][15:0]) begin errors=errors+1; if(errors<=10) $display("B1 FAIL[%0d]: got=%0d exp=%0d",i,$signed(got),real_b[1][i]); end
      got = b2[16*i+:16]; if (got !== real_b[2][i][15:0]) begin errors=errors+1; if(errors<=10) $display("B2 FAIL[%0d]: got=%0d exp=%0d",i,$signed(got),real_b[2][i]); end
      got = v_o[16*i+:16]; if (got !== real_v[i][15:0]) begin errors=errors+1; if(errors<=10) $display("V FAIL[%0d]: got=%0d exp=%0d",i,$signed(got),real_v[i]); end
    end

    if (errors == 0)
      $display("RESULT: indcpa_enc_arith.v matches real indcpa_enc() exactly (b[0..2] and v, all 256 coeffs each, from a real crypto_kem_enc call)");
    else
      $display("RESULT: FAIL (%0d total mismatches)", errors);

    $finish;
  end

endmodule
