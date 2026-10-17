`timescale 1ns/1ps
// tb_rej_uniform_real.sv -- checks rej_uniform.v against a REAL
// (buf, buflen, r_output, ctr) capture from ref/indcpa.c's real
// rej_uniform() call (first call inside gen_matrix(), during an
// actual crypto_kem_keypair() run). File layout
// (vecs_rej/rej_uniform_real.txt):
//   line1: len buflen
//   line2: buflen bytes
//   line3: ctr
//   line4: ctr int16 values (the accepted coefficients)

module tb_rej_uniform_real;

  localparam BUFLEN = 504;
  localparam LEN    = 256;

  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [8*BUFLEN-1:0] buf_in;
  wire [16*LEN-1:0]   r_out;
  wire [8:0]          ctr_out;
  reg                 start_i;
  wire                done;

  rej_uniform #(.BUFLEN(BUFLEN), .LEN(LEN)) dut (
      .clk(clk), .rst_n(rst_n), .start_i(start_i),
      .buf_in(buf_in), .r_out(r_out), .ctr_out(ctr_out), .done(done)
  );

  integer fd, r, i;
  integer real_len, real_buflen, real_ctr;
  integer real_buf [0:BUFLEN-1];
  integer real_r   [0:LEN-1];
  integer errors;
  reg [15:0] got;

  initial begin
    fd = $fopen("vecs_rej/rej_uniform_real.txt", "r");
    r = $fscanf(fd, "%d %d", real_len, real_buflen);
    for (i = 0; i < BUFLEN; i = i + 1) r = $fscanf(fd, "%d", real_buf[i]);
    r = $fscanf(fd, "%d", real_ctr);
    for (i = 0; i < real_ctr; i = i + 1) r = $fscanf(fd, "%d", real_r[i]);
    $fclose(fd);

    buf_in = 0;
    for (i = 0; i < BUFLEN; i = i + 1)
      buf_in[8*i +: 8] = real_buf[i][7:0];

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
    if (ctr_out !== real_ctr[8:0]) begin
      errors = errors + 1;
      $display("REJ-UNIFORM FAIL: ctr got=%0d exp=%0d", ctr_out, real_ctr);
    end
    for (i = 0; i < real_ctr; i = i + 1) begin
      got = r_out[16*i +: 16];
      if (got !== real_r[i][15:0]) begin
        errors = errors + 1;
        if (errors <= 10)
          $display("REJ-UNIFORM FAIL[%0d]: got=%0d exp=%0d", i, got, real_r[i]);
      end
    end

    if (errors == 0)
      $display("RESULT: rej_uniform.v matches real rej_uniform() exactly (ctr=%0d, all coefficients, from a real crypto_kem_keypair round trip)", real_ctr);
    else
      $display("RESULT: FAIL (%0d mismatches)", errors);

    $finish;
  end

endmodule
