`timescale 1ns/1ps
// tb_shake128_xof_real.sv -- checks keccak_sponge.v configured as
// SHAKE128 (rate=168 bytes, pad=0x1F) against a real kyber_shake128_absorb
// + xof_squeezeblocks call from gen_a() (matrix generation): 34-byte
// (seed(32)||x||y) input, 504-byte (3-block) squeezed output -- the
// same real XOF byte stream that rej_uniform.v (task #7) was already
// independently verified against, so this closes the loop: the real
// matrix-generation XOF hardware now produces the exact bytes that feed
// the already-verified rejection-sampling hardware.

module tb_shake128_xof_real;

  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [8*34-1:0] in_bytes;
  wire [8*504-1:0] out_bytes;
  reg              start_i;
  wire             done;

  keccak_sponge #(.RATE_BYTES(168), .IN_LEN(34), .OUT_LEN(504), .PAD_BYTE(8'h1F))
    dut (.clk(clk), .rst_n(rst_n), .start_i(start_i), .in_bytes(in_bytes), .out_bytes(out_bytes), .done(done));

  integer fd, r, i, errors, tmpv;
  integer real_in[0:33];
  integer real_out[0:503];
  reg [7:0] gotb;

  initial begin
    fd = $fopen("vecs_hash/shake128_xof_in_real.txt", "r");
    for (i = 0; i < 34; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_in[i] = tmpv; end
    $fclose(fd);
    fd = $fopen("vecs_hash/shake128_xof_out_real.txt", "r");
    for (i = 0; i < 504; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_out[i] = tmpv; end
    $fclose(fd);

    in_bytes = 0;
    for (i = 0; i < 34; i = i + 1) in_bytes[8*i +: 8] = real_in[i][7:0];

    start_i = 0; rst_n = 0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

    start_i = 1; @(negedge clk); start_i = 0;
    wait (done == 1'b1); @(negedge clk);

    errors = 0;
    for (i = 0; i < 504; i = i + 1) begin
      gotb = out_bytes[8*i +: 8];
      if (gotb !== real_out[i][7:0]) begin errors = errors + 1; if (errors <= 5) $display("XOF BYTE FAIL[%0d]: got=%0d exp=%0d", i, gotb, real_out[i]); end
    end
    $display("shake128 XOF (34B in, 504B/3-block out): mismatches=%0d/504", errors);

    if (errors == 0)
      $display("RESULT: keccak_sponge.v as SHAKE128 matches the real matrix-generation XOF exactly across 3 squeezed blocks, built on the verified keccak_f1600 core -- these are the same bytes rej_uniform.v was independently verified against.");
    else
      $display("RESULT: FAIL (%0d mismatches)", errors);

    $finish;
  end

endmodule
