`timescale 1ns/1ps
module tb_poly_compress_real;
  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [4095:0] coeffs_in;
  wire [1023:0] bytes_out;
  reg           start_i;
  wire          done;

  poly_compress dut (.clk(clk), .rst_n(rst_n), .start_i(start_i),
                      .coeffs_in(coeffs_in), .bytes_out(bytes_out), .done(done));

  integer fd, r, i, errors;
  integer real_in[0:255];
  integer real_out[0:127];
  reg [7:0] got;

  initial begin
    fd = $fopen("vecs_cmp/poly_compress_real.txt", "r");
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_in[i]);
    for (i = 0; i < 128; i = i + 1) r = $fscanf(fd, "%d", real_out[i]);
    $fclose(fd);

    coeffs_in = 0;
    for (i = 0; i < 256; i = i + 1) coeffs_in[16*i +: 16] = real_in[i][15:0];

    start_i = 0; rst_n = 0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);
    start_i = 1; @(negedge clk); start_i = 0;
    wait (done == 1'b1); @(negedge clk);

    errors = 0;
    for (i = 0; i < 128; i = i + 1) begin
      got = bytes_out[8*i +: 8];
      if (got !== real_out[i][7:0]) begin
        errors = errors + 1;
        if (errors <= 10) $display("POLY-COMPRESS FAIL[%0d]: got=%0d exp=%0d", i, got, real_out[i]);
      end
    end
    if (errors == 0)
      $display("RESULT: poly_compress.v matches real poly_compress() exactly on all 128 bytes (real crypto_kem round trip)");
    else
      $display("RESULT: FAIL (%0d/128 mismatches)", errors);
    $finish;
  end
endmodule
