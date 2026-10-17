`timescale 1ns/1ps
module tb_polyvec_compress_real;
  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [4095:0] a0_in, a1_in, a2_in;
  wire [7679:0] bytes_out;
  reg           start_i;
  wire          done;

  polyvec_compress dut (.clk(clk), .rst_n(rst_n), .start_i(start_i),
                         .a0_in(a0_in), .a1_in(a1_in), .a2_in(a2_in),
                         .bytes_out(bytes_out), .done(done));

  integer fd, r, i, errors;
  integer real_a0[0:255], real_a1[0:255], real_a2[0:255];
  integer real_out[0:959];
  reg [7:0] got;

  initial begin
    fd = $fopen("vecs_cmp/polyvec_compress_real.txt", "r");
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_a0[i]);
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_a1[i]);
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_a2[i]);
    for (i = 0; i < 960; i = i + 1) r = $fscanf(fd, "%d", real_out[i]);
    $fclose(fd);

    a0_in = 0; a1_in = 0; a2_in = 0;
    for (i = 0; i < 256; i = i + 1) begin
      a0_in[16*i +: 16] = real_a0[i][15:0];
      a1_in[16*i +: 16] = real_a1[i][15:0];
      a2_in[16*i +: 16] = real_a2[i][15:0];
    end

    start_i = 0; rst_n = 0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);
    start_i = 1; @(negedge clk); start_i = 0;
    wait (done == 1'b1); @(negedge clk);

    errors = 0;
    for (i = 0; i < 960; i = i + 1) begin
      got = bytes_out[8*i +: 8];
      if (got !== real_out[i][7:0]) begin
        errors = errors + 1;
        if (errors <= 10) $display("POLYVEC-COMPRESS FAIL[%0d]: got=%0d exp=%0d", i, got, real_out[i]);
      end
    end
    if (errors == 0)
      $display("RESULT: polyvec_compress.v matches real polyvec_compress() exactly on all 960 bytes (real crypto_kem round trip)");
    else
      $display("RESULT: FAIL (%0d/960 mismatches)", errors);
    $finish;
  end
endmodule
