`timescale 1ns/1ps
// tb_poly_cbd_eta2_real.sv -- checks poly_cbd_eta2.v against real cbd2()
// output (vecs_hash/cbd2_real.txt: 128 real PRF bytes -> 256 real
// coefficients), AND composes it with the already-verified SHAKE256 PRF
// sponge (keccak_sponge.v) fed the real PRF call0 input, checking that
// PRF-hardware-output -> CBD-hardware-output reproduces the real skpv[0]
// noise polynomial exactly (the same skpv[0] that indcpa_keypair_arith.v
// was already independently verified to consume correctly) -- this closes
// the noise-generation loop end to end: real seed -> real PRF hardware ->
// real CBD hardware -> the exact noise polynomial the arithmetic core needs.

module tb_poly_cbd_eta2_real;

  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  // ---- direct cbd2 check ----
  reg  [1023:0] buf_in;
  wire [4095:0] coeffs_out;
  reg           cbd_start;
  wire          cbd_done;
  poly_cbd_eta2 dut (.clk(clk), .rst_n(rst_n), .start_i(cbd_start),
                      .buf_in(buf_in), .coeffs_out(coeffs_out), .done(cbd_done));

  // ---- composed check: real PRF seed+nonce -> keccak_sponge (SHAKE256) -> poly_cbd_eta2 ----
  reg  [8*33-1:0] prf_in;
  wire [1023:0]   prf_out;
  reg             prf_start;
  wire            prf_done;
  keccak_sponge #(.RATE_BYTES(136), .IN_LEN(33), .OUT_LEN(128), .PAD_BYTE(8'h1F))
    u_prf (.clk(clk), .rst_n(rst_n), .start_i(prf_start), .in_bytes(prf_in), .out_bytes(prf_out), .done(prf_done));

  reg           cbd2_start;
  wire [4095:0] cbd2_out;
  wire          cbd2_done;
  poly_cbd_eta2 dut2 (.clk(clk), .rst_n(rst_n), .start_i(cbd2_start),
                       .buf_in(prf_out), .coeffs_out(cbd2_out), .done(cbd2_done));

  integer fd, r, i, errors, tot_errors, tmpv;
  integer real_buf[0:127];
  integer real_coeffs[0:255];
  integer real_seed_nonce[0:32];
  integer real_skpv0[0:255];
  reg signed [15:0] got;

  initial begin
    // direct cbd2 check
    fd = $fopen("vecs_hash/cbd2_real.txt", "r");
    for (i = 0; i < 128; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_buf[i] = tmpv; end
    for (i = 0; i < 256; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_coeffs[i] = tmpv; end
    $fclose(fd);

    // composed check inputs: real PRF call0 input (should be skpv[0]'s noiseseed||nonce=0)
    fd = $fopen("vecs_hash/shake256_prf_call0_real.txt", "r");
    for (i = 0; i < 33; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_seed_nonce[i] = tmpv; end
    $fclose(fd);
    // real skpv[0] from the already-verified keypair pre-NTT capture
    fd = $fopen("vecs_keypair/indcpa_keypair_prentt_real.txt", "r");
    for (i = 0; i < 256; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_skpv0[i] = tmpv; end
    $fclose(fd);

    buf_in = 0;
    for (i = 0; i < 128; i = i + 1) buf_in[8*i +: 8] = real_buf[i][7:0];
    prf_in = 0;
    for (i = 0; i < 33; i = i + 1) prf_in[8*i +: 8] = real_seed_nonce[i][7:0];

    cbd_start = 0; prf_start = 0; cbd2_start = 0; rst_n = 0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);
    tot_errors = 0;

    // direct check
    cbd_start = 1; @(negedge clk); cbd_start = 0;
    wait (cbd_done == 1'b1); @(negedge clk);
    errors = 0;
    for (i = 0; i < 256; i = i + 1) begin
      got = coeffs_out[16*i +: 16];
      if (got !== real_coeffs[i][15:0]) begin errors = errors + 1; if (errors <= 5) $display("DIRECT FAIL[%0d]: got=%0d exp=%0d", i, $signed(got), real_coeffs[i]); end
    end
    $display("poly_cbd_eta2.v direct (128B real PRF bytes -> 256 coeffs): mismatches=%0d/256", errors);
    tot_errors = tot_errors + errors;

    // composed check: PRF hardware -> CBD hardware -> should equal real skpv[0]
    prf_start = 1; @(negedge clk); prf_start = 0;
    wait (prf_done == 1'b1); @(negedge clk);
    cbd2_start = 1; @(negedge clk); cbd2_start = 0;
    wait (cbd2_done == 1'b1); @(negedge clk);
    errors = 0;
    for (i = 0; i < 256; i = i + 1) begin
      got = cbd2_out[16*i +: 16];
      if (got !== real_skpv0[i][15:0]) begin errors = errors + 1; if (errors <= 5) $display("COMPOSED FAIL[%0d]: got=%0d exp=%0d", i, $signed(got), real_skpv0[i]); end
    end
    $display("PRF-hw -> CBD-hw composed (real seed -> real skpv[0]): mismatches=%0d/256", errors);
    tot_errors = tot_errors + errors;

    if (tot_errors == 0)
      $display("RESULT: poly_cbd_eta2.v matches real cbd2() exactly, AND the composed real-seed -> SHAKE256-PRF-hardware -> CBD-hardware chain reproduces the exact real skpv[0] noise polynomial that indcpa_keypair_arith.v was independently verified to consume -- the noise-generation chain is closed end to end.");
    else
      $display("RESULT: FAIL (%0d total mismatches)", tot_errors);

    $finish;
  end

endmodule
