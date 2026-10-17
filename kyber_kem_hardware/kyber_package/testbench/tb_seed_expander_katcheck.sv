`timescale 1ns/1ps
// tb_seed_expander_katcheck.sv -- NOT a "real hardware RNG" test (that is
// impossible by definition: you cannot deterministically verify true
// entropy against a captured reference without destroying the entropy).
//
// What this checks: a keccak_sponge.v instance configured as SHAKE256
// with a 32-byte input and 96-byte output -- i.e. a deterministic seed
// expander, the only piece of "randomness handling" that can be
// meaningfully hardware-verified -- reproduces the same output as
// Python's hashlib.shake_256 (an independent, trusted SHAKE256
// implementation) for a fixed known-answer seed. This proves the
// EXPANSION is byte-correct; it says nothing about, and cannot say
// anything about, where the 32-byte seed itself comes from. In a real
// device that seed must come from a physical entropy source (a TRNG),
// which is explicitly NOT built or claimed here.

module tb_seed_expander_katcheck;

  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [255:0] seed_in;
  wire [767:0] expanded_out; // 96 bytes = d(32) || z(32) || m(32)
  reg          start_i;
  wire         done;

  keccak_sponge #(.RATE_BYTES(136), .IN_LEN(32), .OUT_LEN(96), .PAD_BYTE(8'h1F))
    dut (.clk(clk), .rst_n(rst_n), .start_i(start_i), .in_bytes(seed_in), .out_bytes(expanded_out), .done(done));

  integer fd, r, i, errors;
  integer known_seed[0:31];
  integer known_out[0:95];
  reg [7:0] gotb;

  initial begin
    // known-answer seed/output pair, generated independently by Python's
    // hashlib.shake_256 (NOT from the Kyber reference C code -- this is
    // a generic SHAKE256 KAT, not a Kyber-specific real-execution capture).
    fd = $fopen("vecs_hash/seed_expander_kat.txt", "r");
    for (i = 0; i < 32; i = i + 1) begin r = $fscanf(fd, "%d", known_seed[i]); end
    for (i = 0; i < 96; i = i + 1) begin r = $fscanf(fd, "%d", known_out[i]); end
    $fclose(fd);

    seed_in = 0;
    for (i = 0; i < 32; i = i + 1) seed_in[8*i +: 8] = known_seed[i][7:0];

    start_i = 0; rst_n = 0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

    start_i = 1; @(negedge clk); start_i = 0;
    wait (done == 1'b1); @(negedge clk);

    errors = 0;
    for (i = 0; i < 96; i = i + 1) begin
      gotb = expanded_out[8*i +: 8];
      if (gotb !== known_out[i][7:0]) begin errors = errors + 1; $display("BYTE FAIL[%0d]: got=%0d exp=%0d", i, gotb, known_out[i]); end
    end
    $display("seed expander (SHAKE256, 32B seed -> 96B d||z||m) vs independent Python KAT: mismatches=%0d/96", errors);

    if (errors == 0)
      $display("RESULT: the deterministic seed-EXPANSION hardware is byte-correct. This says nothing about entropy quality or the seed source -- a real device needs a physical TRNG to generate the 32-byte seed itself, which is explicitly out of scope and not built here.");
    else
      $display("RESULT: FAIL (%0d mismatches)", errors);

    $finish;
  end

endmodule
