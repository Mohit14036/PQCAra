`timescale 1ns/1ps
// tb_indcpa_dec_real.sv -- checks indcpa_dec_arith.v + poly_tomsg.v
// against REAL data captured from an actual ref/indcpa.c indcpa_dec()
// call. vecs_dec/indcpa_dec_real.txt: 9 lines (b[0..2], v, skpv[0..2],
// mp (final, post poly_sub+poly_reduce), msg (32 bytes)).

module tb_indcpa_dec_real;

  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [4095:0] b0,b1,b2, v_r, skpv0,skpv1,skpv2;
  wire [4095:0] b_ntt0,b_ntt1,b_ntt2;
  wire [4095:0] mp_o;
  reg           start_i;
  wire          done;

  indcpa_dec_arith dut (
      .clk(clk), .rst_n(rst_n), .start_i(start_i),
      .b0_in(b0), .b1_in(b1), .b2_in(b2), .v_in(v_r),
      .skpv0_in(skpv0), .skpv1_in(skpv1), .skpv2_in(skpv2),
      .b_ntt0_out(b_ntt0), .b_ntt1_out(b_ntt1), .b_ntt2_out(b_ntt2),
      .mp_out(mp_o), .done(done)
  );

  // chain into poly_tomsg (already verified standalone in task #9)
  reg           tomsg_start;
  wire [255:0]  msg_o;
  wire          tomsg_done;
  poly_tomsg u_tomsg (.clk(clk), .rst_n(rst_n), .start_i(tomsg_start),
                       .coeffs_in(mp_o), .msg_out(msg_o), .done(tomsg_done));

  integer fd, r, i, q, tmpv, errors;
  integer real_b_pre[0:2][0:255];   // pre-NTT (decompressed ciphertext b)
  integer real_b_ntt[0:2][0:255];   // post-NTT checkpoint
  integer real_v[0:255];
  integer real_skpv[0:2][0:255];
  integer real_mp[0:255];
  integer real_msg[0:31];
  reg signed [15:0] got;
  reg [7:0] gotb;

  initial begin
    fd = $fopen("vecs_dec/indcpa_dec_prentt_real.txt", "r");
    for (i = 0; i < 3; i = i + 1)
      for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_b_pre[i][q]=tmpv; end
    $fclose(fd);

    fd = $fopen("vecs_dec/indcpa_dec_real.txt", "r");
    for (i = 0; i < 3; i = i + 1)
      for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_b_ntt[i][q]=tmpv; end
    for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_v[q]=tmpv; end
    for (i = 0; i < 3; i = i + 1)
      for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_skpv[i][q]=tmpv; end
    for (q = 0; q < 256; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_mp[q]=tmpv; end
    for (q = 0; q < 32; q = q + 1) begin r=$fscanf(fd,"%d",tmpv); real_msg[q]=tmpv; end
    $fclose(fd);

    b0=0;b1=0;b2=0;v_r=0;skpv0=0;skpv1=0;skpv2=0;
    for (i = 0; i < 256; i = i + 1) begin
      b0[16*i+:16]=real_b_pre[0][i][15:0]; b1[16*i+:16]=real_b_pre[1][i][15:0]; b2[16*i+:16]=real_b_pre[2][i][15:0];
      v_r[16*i+:16]=real_v[i][15:0];
      skpv0[16*i+:16]=real_skpv[0][i][15:0]; skpv1[16*i+:16]=real_skpv[1][i][15:0]; skpv2[16*i+:16]=real_skpv[2][i][15:0];
    end

    start_i = 0; tomsg_start = 0; rst_n = 0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);
    start_i = 1; @(negedge clk); start_i = 0;

    wait (done == 1'b1); @(negedge clk);

    errors = 0;
    begin
      integer c0,c1,c2;
      c0=0;c1=0;c2=0;
      for (i = 0; i < 256; i = i + 1) begin
        if (b_ntt0[16*i+:16] !== real_b_ntt[0][i][15:0]) c0=c0+1;
        if (b_ntt1[16*i+:16] !== real_b_ntt[1][i][15:0]) c1=c1+1;
        if (b_ntt2[16*i+:16] !== real_b_ntt[2][i][15:0]) c2=c2+1;
      end
      $display("b_ntt mismatch counts: %0d %0d %0d", c0, c1, c2);
      errors = errors + c0+c1+c2;
    end
    for (i = 0; i < 256; i = i + 1) begin
      got = mp_o[16*i+:16];
      if (got !== real_mp[i][15:0]) begin errors=errors+1; if(errors<=10) $display("MP FAIL[%0d]: got=%0d exp=%0d",i,$signed(got),real_mp[i]); end
    end
    if (errors == 0) $display("CHECKPOINT: mp matches real (post poly_sub+poly_reduce) exactly");
    else              $display("CHECKPOINT FAIL: %0d mismatches in mp", errors);

    // feed mp_o into the already-verified poly_tomsg
    tomsg_start = 1; @(negedge clk); tomsg_start = 0;
    wait (tomsg_done == 1'b1); @(negedge clk);

    for (i = 0; i < 32; i = i + 1) begin
      gotb = msg_o[8*i+:8];
      if (gotb !== real_msg[i][7:0]) begin errors=errors+1; if(errors<=10) $display("MSG FAIL[%0d]: got=%0d exp=%0d",i,gotb,real_msg[i]); end
    end

    if (errors == 0)
      $display("RESULT: indcpa_dec_arith.v + poly_tomsg.v matches real indcpa_dec() exactly (mp, all 256 coeffs, AND final 32-byte decrypted message, from a real crypto_kem_dec call)");
    else
      $display("RESULT: FAIL (%0d total mismatches)", errors);

    $finish;
  end

endmodule
