`timescale 1ns/1ps
module tb_poly_decompress_real;
  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [1023:0] bytes_in;
  wire [4095:0] coeffs_out;
  reg           start_i;
  wire          done;

  poly_decompress dut (.clk(clk), .rst_n(rst_n), .start_i(start_i),
                        .bytes_in(bytes_in), .coeffs_out(coeffs_out), .done(done));

  integer fd, r, i, errors;
  integer real_in[0:127];
  integer real_out[0:255];
  reg signed [15:0] got;

  initial begin
    fd = $fopen("vecs_cmp/poly_decompress_real.txt", "r");
    for (i = 0; i < 128; i = i + 1) r = $fscanf(fd, "%d", real_in[i]);
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_out[i]);
    $fclose(fd);

    bytes_in = 0;
    for (i = 0; i < 128; i = i + 1) bytes_in[8*i +: 8] = real_in[i][7:0];

    start_i = 0; rst_n = 0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);
    start_i = 1; @(negedge clk); start_i = 0;
    wait (done == 1'b1); @(negedge clk);

    errors = 0;
    for (i = 0; i < 256; i = i + 1) begin
      got = coeffs_out[16*i +: 16];
      if (got !== real_out[i][15:0]) begin
        errors = errors + 1;
        if (errors <= 10) $display("POLY-DECOMPRESS FAIL[%0d]: got=%0d exp=%0d", i, $signed(got), real_out[i]);
      end
    end
    if (errors == 0)
      $display("RESULT: poly_decompress.v matches real poly_decompress() exactly on all 256 coefficients (real crypto_kem round trip)");
    else
      $display("RESULT: FAIL (%0d/256 mismatches)", errors);
    $finish;
  end
endmodule
