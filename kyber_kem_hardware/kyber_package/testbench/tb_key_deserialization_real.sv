`timescale 1ns/1ps
// tb_key_deserialization_real.sv -- checks polyvec_frombytes.v against
// the real pack_sk()/pack_pk() output, in the DECODE direction: feed the
// real packed bytes in, check the coefficients out match the real
// pre-pack coefficients exactly (round-trip inverse of
// tb_key_serialization_real.sv, using the same real captured data).

module tb_key_deserialization_real;

  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [9215:0] bytes_in;
  wire [4095:0] a0_out, a1_out, a2_out;
  reg           start_i;
  wire          done;

  polyvec_frombytes dut (.clk(clk), .rst_n(rst_n), .start_i(start_i),
                          .bytes_in(bytes_in), .a0_out(a0_out), .a1_out(a1_out), .a2_out(a2_out),
                          .done(done));

  integer fd, r, i, errors, tot_errors, tmpv;
  integer real_sk_coeffs[0:767];
  integer real_sk_bytes[0:1151];
  reg signed [15:0] got;

  initial begin
    fd = $fopen("vecs_hash/pack_sk_real.txt", "r");
    for (i = 0; i < 768; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_sk_coeffs[i] = tmpv; end
    for (i = 0; i < 1152; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_sk_bytes[i] = tmpv; end
    $fclose(fd);

    bytes_in = 0;
    for (i = 0; i < 1152; i = i + 1) bytes_in[8*i +: 8] = real_sk_bytes[i][7:0];

    start_i = 0; rst_n = 0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);
    tot_errors = 0;

    start_i = 1; @(negedge clk); start_i = 0;
    wait (done == 1'b1); @(negedge clk);

    errors = 0;
    for (i = 0; i < 256; i = i + 1) begin
      got = a0_out[16*i +: 16];
      // note: frombytes recovers the POSITIVE representative (0..3328),
      // while the real captured coeffs may be the signed/negative
      // representative -- both are the same value mod KYBER_Q, so compare
      // mod 3329.
      if ((got % 16'sd3329 + 16'sd3329) % 16'sd3329 !== (real_sk_coeffs[i] % 3329 + 3329) % 3329) begin
        errors = errors + 1; if (errors <= 5) $display("A0 FAIL[%0d]: got=%0d exp=%0d", i, $signed(got), real_sk_coeffs[i]);
      end
    end
    for (i = 0; i < 256; i = i + 1) begin
      got = a1_out[16*i +: 16];
      if ((got % 16'sd3329 + 16'sd3329) % 16'sd3329 !== (real_sk_coeffs[256+i] % 3329 + 3329) % 3329) begin
        errors = errors + 1; if (errors <= 5) $display("A1 FAIL[%0d]: got=%0d exp=%0d", i, $signed(got), real_sk_coeffs[256+i]);
      end
    end
    for (i = 0; i < 256; i = i + 1) begin
      got = a2_out[16*i +: 16];
      if ((got % 16'sd3329 + 16'sd3329) % 16'sd3329 !== (real_sk_coeffs[512+i] % 3329 + 3329) % 3329) begin
        errors = errors + 1; if (errors <= 5) $display("A2 FAIL[%0d]: got=%0d exp=%0d", i, $signed(got), real_sk_coeffs[512+i]);
      end
    end

    $display("polyvec_frombytes.v (pack_sk bytes -> 768 coeffs, mod q): mismatches=%0d/768", errors);
    tot_errors = tot_errors + errors;

    if (tot_errors == 0)
      $display("RESULT: polyvec_frombytes.v correctly inverts the real key-serialization bytes back to the real secret-key coefficients (mod q) exactly.");
    else
      $display("RESULT: FAIL (%0d total mismatches)", tot_errors);

    $finish;
  end

endmodule
