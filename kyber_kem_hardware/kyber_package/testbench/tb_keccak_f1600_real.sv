`timescale 1ns/1ps
// tb_keccak_f1600_real.sv -- checks keccak_f1600.v (24-round Keccak-f[1600]
// permutation) against a REAL captured input/output state pair from
// KeccakF1600_StatePermute(), instrumented in the real, unmodified
// pq-crystals/kyber ref/fips202.c, taken from a genuine crypto_kem_keypair()
// call within a full real KEM round trip (this is the very first
// permutation call in that run -- part of the keypair's hash_g seed
// expansion).

module tb_keccak_f1600_real;

  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [1599:0] state_in;
  wire [1599:0] state_out;
  reg           start;
  wire          done;

  keccak_f1600 dut (.clk(clk), .rst_n(rst_n), .start(start),
                     .state_in(state_in), .state_out(state_out), .done(done));

  integer fd, r, i, errors;
  reg [63:0] real_in[0:24];
  reg [63:0] real_out[0:24];
  reg [63:0] tmpv;

  initial begin
    fd = $fopen("vecs_hash/keccak_perm_in_real.txt", "r");
    for (i = 0; i < 25; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_in[i] = tmpv; end
    $fclose(fd);
    fd = $fopen("vecs_hash/keccak_perm_out_real.txt", "r");
    for (i = 0; i < 25; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_out[i] = tmpv; end
    $fclose(fd);

    state_in = 0;
    for (i = 0; i < 25; i = i + 1)
      state_in[64*i +: 64] = real_in[i];

    start = 0; rst_n = 0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

    start = 1; @(negedge clk); start = 0;
    wait (done == 1'b1); @(negedge clk);

    errors = 0;
    for (i = 0; i < 25; i = i + 1) begin
      if (state_out[64*i +: 64] !== real_out[i]) begin
        errors = errors + 1;
        $display("LANE FAIL[%0d]: got=%h exp=%h", i, state_out[64*i +: 64], real_out[i]);
      end
    end

    if (errors == 0)
      $display("RESULT: keccak_f1600.v (24-round Keccak-f[1600] permutation) matches the real KeccakF1600_StatePermute() exactly on all 25 lanes (1600 bits), from a real crypto_kem_keypair call.");
    else
      $display("RESULT: FAIL (%0d/25 lane mismatches)", errors);

    $finish;
  end

endmodule
