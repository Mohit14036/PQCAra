`timescale 1ns/1ps
module tb_polyvec_decompress_real;
  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [7679:0] bytes_in;
  wire [4095:0] r0_out, r1_out, r2_out;
  reg           start_i;
  wire          done;

  polyvec_decompress dut (.clk(clk), .rst_n(rst_n), .start_i(start_i),
                           .bytes_in(bytes_in),
                           .r0_out(r0_out), .r1_out(r1_out), .r2_out(r2_out), .done(done));

  integer fd, r, i, errors;
  integer real_in[0:959];
  integer real_r0[0:255], real_r1[0:255], real_r2[0:255];
  reg signed [15:0] got;

  initial begin
    fd = $fopen("vecs_cmp/polyvec_decompress_real.txt", "r");
    for (i = 0; i < 960; i = i + 1) r = $fscanf(fd, "%d", real_in[i]);
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_r0[i]);
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_r1[i]);
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_r2[i]);
    $fclose(fd);

    bytes_in = 0;
    for (i = 0; i < 960; i = i + 1) bytes_in[8*i +: 8] = real_in[i][7:0];

    start_i = 0; rst_n = 0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);
    start_i = 1; @(negedge clk); start_i = 0;
    wait (done == 1'b1); @(negedge clk);

    errors = 0;
    for (i = 0; i < 256; i = i + 1) begin
      got = r0_out[16*i +: 16];
      if (got !== real_r0[i][15:0]) begin
        errors = errors + 1;
        if (errors <= 10) $display("POLYVEC-DECOMPRESS FAIL r0[%0d]: got=%0d exp=%0d", i, $signed(got), real_r0[i]);
      end
    end
    for (i = 0; i < 256; i = i + 1) begin
      got = r1_out[16*i +: 16];
      if (got !== real_r1[i][15:0]) begin
        errors = errors + 1;
        if (errors <= 10) $display("POLYVEC-DECOMPRESS FAIL r1[%0d]: got=%0d exp=%0d", i, $signed(got), real_r1[i]);
      end
    end
    for (i = 0; i < 256; i = i + 1) begin
      got = r2_out[16*i +: 16];
      if (got !== real_r2[i][15:0]) begin
        errors = errors + 1;
        if (errors <= 10) $display("POLYVEC-DECOMPRESS FAIL r2[%0d]: got=%0d exp=%0d", i, $signed(got), real_r2[i]);
      end
    end
    if (errors == 0)
      $display("RESULT: polyvec_decompress.v matches real polyvec_decompress() exactly on all 768 coefficients (real crypto_kem round trip)");
    else
      $display("RESULT: FAIL (%0d/768 mismatches)", errors);
    $finish;
  end
endmodule
