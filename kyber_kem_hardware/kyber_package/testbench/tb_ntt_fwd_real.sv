`timescale 1ns/1ps
// tb_ntt_fwd_real.sv -- checks ntt_fwd.v against a REAL (input,output)
// pair captured from ref/ntt.c's real ntt() call during an actual
// crypto_kem_keypair()+enc+dec round trip (see /tmp/ntt_real.txt via
// vecs_ntt/ntt_real.txt).

module tb_ntt_fwd_real;

  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [4095:0] coeffs_in;
  wire [4095:0] coeffs_out;
  reg           start_i;
  wire          done;

  ntt_fwd dut (.clk(clk), .rst_n(rst_n), .start_i(start_i),
               .coeffs_in(coeffs_in), .coeffs_out(coeffs_out), .done(done));

  integer fd, r, i;
  integer real_in [0:255];
  integer real_out [0:255];
  integer errors;

  initial begin
    fd = $fopen("vecs_ntt/ntt_real.txt", "r");
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_in[i]);
    for (i = 0; i < 256; i = i + 1) r = $fscanf(fd, "%d", real_out[i]);
    $fclose(fd);

    coeffs_in = 0;
    for (i = 0; i < 256; i = i + 1)
      coeffs_in[16*i +: 16] = real_in[i][15:0];

    start_i = 0;
    rst_n = 0;
    repeat (4) @(negedge clk);
    rst_n = 1;
    repeat (2) @(negedge clk);

    start_i = 1;
    @(negedge clk);
    start_i = 0;

    wait (done == 1'b1);
    @(negedge clk);

    errors = 0;
    for (i = 0; i < 256; i = i + 1) begin
      reg signed [15:0] got;
      got = coeffs_out[16*i +: 16];
      if (got !== real_out[i][15:0]) begin
        errors = errors + 1;
        if (errors <= 10)
          $display("NTT-FWD FAIL[%0d]: got=%0d exp=%0d", i, $signed(got), real_out[i]);
      end
    end

    if (errors == 0)
      $display("RESULT: ntt_fwd.v matches real ntt() exactly on all 256 coefficients (from a real crypto_kem_keypair round trip)");
    else
      $display("RESULT: FAIL (%0d/256 mismatches)", errors);

    $finish;
  end

endmodule
