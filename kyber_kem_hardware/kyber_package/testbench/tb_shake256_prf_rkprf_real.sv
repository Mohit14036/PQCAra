`timescale 1ns/1ps
// tb_shake256_prf_rkprf_real.sv -- checks keccak_sponge.v configured as
// SHAKE256 (rate=136 bytes, pad=0x1F) against two real usages:
//   1) kyber_shake256_prf: 33-byte (key||nonce) input -> 128-byte output
//      (this is the noise-generation PRF, eta=2: outlen = eta*256/4=128),
//      checked against several real calls from one genuine round trip.
//   2) kyber_shake256_rkprf: 1120-byte (key(32)||ct(1088)) input -> 32-byte
//      output (the implicit-rejection pseudorandom key).

module tb_shake256_prf_rkprf_real;

  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  // ---- PRF instance: 33B in, 128B out ----
  reg  [8*33-1:0] prf_in;
  wire [1023:0]   prf_out;
  reg             prf_start;
  wire            prf_done;
  keccak_sponge #(.RATE_BYTES(136), .IN_LEN(33), .OUT_LEN(128), .PAD_BYTE(8'h1F))
    u_prf (.clk(clk), .rst_n(rst_n), .start_i(prf_start), .in_bytes(prf_in), .out_bytes(prf_out), .done(prf_done));

  // ---- rkprf instance: 1120B in, 32B out ----
  reg  [8*1120-1:0] rk_in;
  wire [255:0]       rk_out;
  reg                rk_start;
  wire               rk_done;
  keccak_sponge #(.RATE_BYTES(136), .IN_LEN(1120), .OUT_LEN(32), .PAD_BYTE(8'h1F))
    u_rk (.clk(clk), .rst_n(rst_n), .start_i(rk_start), .in_bytes(rk_in), .out_bytes(rk_out), .done(rk_done));

  integer fd, r, i, c, errors, tot_errors, tmpv;
  integer real_prf_in[0:32], real_prf_out[0:127];
  integer real_rk_key[0:31], real_rk_input[0:1087], real_rk_out[0:31];
  reg [7:0] gotb;

  task run_prf(input integer callno);
    begin
      case (callno)
        0: fd = $fopen("vecs_hash/shake256_prf_call0_real.txt", "r");
        1: fd = $fopen("vecs_hash/shake256_prf_call1_real.txt", "r");
        2: fd = $fopen("vecs_hash/shake256_prf_call2_real.txt", "r");
        3: fd = $fopen("vecs_hash/shake256_prf_call3_real.txt", "r");
        4: fd = $fopen("vecs_hash/shake256_prf_call4_real.txt", "r");
      endcase
      for (i = 0; i < 33; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_prf_in[i] = tmpv; end
      for (i = 0; i < 128; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_prf_out[i] = tmpv; end
      $fclose(fd);

      prf_in = 0;
      for (i = 0; i < 33; i = i + 1) prf_in[8*i +: 8] = real_prf_in[i][7:0];

      prf_start = 1; @(negedge clk); prf_start = 0;
      wait (prf_done == 1'b1); @(negedge clk);

      errors = 0;
      for (i = 0; i < 128; i = i + 1) begin
        gotb = prf_out[8*i +: 8];
        if (gotb !== real_prf_out[i][7:0]) begin errors = errors + 1; if (errors <= 3) $display("prf call%0d BYTE FAIL[%0d]: got=%0d exp=%0d", callno, i, gotb, real_prf_out[i]); end
      end
      $display("shake256 PRF call%0d (33B->128B, CBD noise gen): mismatches=%0d/128", callno, errors);
      tot_errors = tot_errors + errors;
    end
  endtask

  initial begin
    prf_start = 0; rk_start = 0; rst_n = 0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);
    tot_errors = 0;

    run_prf(0);
    run_prf(1);
    run_prf(2);
    run_prf(3);
    run_prf(4);

    // ---- rkprf ----
    fd = $fopen("vecs_hash/shake256_rkprf_real.txt", "r");
    for (i = 0; i < 32; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_rk_key[i] = tmpv; end
    for (i = 0; i < 1088; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_rk_input[i] = tmpv; end
    for (i = 0; i < 32; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_rk_out[i] = tmpv; end
    $fclose(fd);

    rk_in = 0;
    for (i = 0; i < 32; i = i + 1) rk_in[8*i +: 8] = real_rk_key[i][7:0];
    for (i = 0; i < 1088; i = i + 1) rk_in[8*(32+i) +: 8] = real_rk_input[i][7:0];

    rk_start = 1; @(negedge clk); rk_start = 0;
    wait (rk_done == 1'b1); @(negedge clk);

    errors = 0;
    for (i = 0; i < 32; i = i + 1) begin
      gotb = rk_out[8*i +: 8];
      if (gotb !== real_rk_out[i][7:0]) begin errors = errors + 1; $display("rkprf BYTE FAIL[%0d]: got=%0d exp=%0d", i, gotb, real_rk_out[i]); end
    end
    $display("shake256 rkprf (1120B->32B, implicit-rejection PRF): mismatches=%0d/32", errors);
    tot_errors = tot_errors + errors;

    if (tot_errors == 0)
      $display("RESULT: keccak_sponge.v as SHAKE256 matches real kyber_shake256_prf() (5 real calls) and real kyber_shake256_rkprf() exactly, built on the verified keccak_f1600 core.");
    else
      $display("RESULT: FAIL (%0d total mismatches)", tot_errors);

    $finish;
  end

endmodule
