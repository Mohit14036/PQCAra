`timescale 1ns/1ps
// tb_sha3_512_real.sv -- checks keccak_sponge.v configured as SHA3-512
// (rate=72 bytes, pad=0x06) against real hash_g() calls: call0 is the
// 33-byte (coins||K) seed-expansion inside keypair generation, call1
// is the 64-byte (m||H(pk)) call inside encaps.

module tb_sha3_512_real;

  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  // call0: 33-byte input
  reg  [8*33-1:0] in0;
  wire [511:0]    out0;
  reg             start0;
  wire            done0;
  keccak_sponge #(.RATE_BYTES(72), .IN_LEN(33), .OUT_LEN(64), .PAD_BYTE(8'h06))
    dut0 (.clk(clk), .rst_n(rst_n), .start_i(start0), .in_bytes(in0), .out_bytes(out0), .done(done0));

  // call1: 64-byte input
  reg  [8*64-1:0] in1;
  wire [511:0]    out1;
  reg             start1;
  wire            done1;
  keccak_sponge #(.RATE_BYTES(72), .IN_LEN(64), .OUT_LEN(64), .PAD_BYTE(8'h06))
    dut1 (.clk(clk), .rst_n(rst_n), .start_i(start1), .in_bytes(in1), .out_bytes(out1), .done(done1));

  integer fd, r, i, errors, tot_errors, tmpv, inlen_check;
  integer real_in0[0:32], real_out0[0:63];
  integer real_in1[0:63], real_out1[0:63];
  reg [7:0] gotb;

  initial begin
    fd = $fopen("vecs_hash/sha3_512_call0_real.txt", "r");
    r = $fscanf(fd, "%d", inlen_check);
    for (i = 0; i < 33; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_in0[i] = tmpv; end
    for (i = 0; i < 64; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_out0[i] = tmpv; end
    $fclose(fd);

    fd = $fopen("vecs_hash/sha3_512_call1_real.txt", "r");
    r = $fscanf(fd, "%d", inlen_check);
    for (i = 0; i < 64; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_in1[i] = tmpv; end
    for (i = 0; i < 64; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_out1[i] = tmpv; end
    $fclose(fd);

    in0 = 0; for (i = 0; i < 33; i = i + 1) in0[8*i +: 8] = real_in0[i][7:0];
    in1 = 0; for (i = 0; i < 64; i = i + 1) in1[8*i +: 8] = real_in1[i][7:0];

    start0 = 0; start1 = 0; rst_n = 0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);
    tot_errors = 0;

    start0 = 1; @(negedge clk); start0 = 0;
    wait (done0 == 1'b1); @(negedge clk);
    errors = 0;
    for (i = 0; i < 64; i = i + 1) begin
      gotb = out0[8*i +: 8];
      if (gotb !== real_out0[i][7:0]) begin errors = errors + 1; $display("call0 BYTE FAIL[%0d]: got=%0d exp=%0d", i, gotb, real_out0[i]); end
    end
    $display("sha3_512 call0 (33B in, keypair seed-expand hash_g): mismatches=%0d/64", errors);
    tot_errors = tot_errors + errors;

    start1 = 1; @(negedge clk); start1 = 0;
    wait (done1 == 1'b1); @(negedge clk);
    errors = 0;
    for (i = 0; i < 64; i = i + 1) begin
      gotb = out1[8*i +: 8];
      if (gotb !== real_out1[i][7:0]) begin errors = errors + 1; $display("call1 BYTE FAIL[%0d]: got=%0d exp=%0d", i, gotb, real_out1[i]); end
    end
    $display("sha3_512 call1 (64B in, encaps hash_g -> kr): mismatches=%0d/64", errors);
    tot_errors = tot_errors + errors;

    if (tot_errors == 0)
      $display("RESULT: keccak_sponge.v as SHA3-512 matches real hash_g() exactly on both real calls (33B keypair seed-expand and 64B encaps kr derivation).");
    else
      $display("RESULT: FAIL (%0d total mismatches)", tot_errors);

    $finish;
  end

endmodule
