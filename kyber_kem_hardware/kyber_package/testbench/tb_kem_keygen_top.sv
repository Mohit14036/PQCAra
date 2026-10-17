`timescale 1ns/1ps
// tb_kem_keygen_top.sv -- END-TO-END KeyGen check. The only inputs are the
// 64 coin bytes (d || z); everything else (rho/sigma, matrix A, noise,
// NTT arithmetic, packing, H(pk)) is computed by kem_keygen_top.v, and the
// resulting pk (1184 B) and sk (2400 B) are compared byte-for-byte with the
// pq-crystals reference crypto_kem_keypair_derand() on the same coins.
// Usage: vvp sim +vec=vectors/vecs_kemtop/kem_vec_N.txt
module tb_kem_keygen_top;
  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [255:0] d, z;
  reg          start;
  wire [8*1184-1:0] pk;
  wire [8*2400-1:0] sk;
  wire a_fail, done;
  kem_keygen_top dut (.clk(clk), .rst_n(rst_n), .start_i(start), .d_in(d), .z_in(z),
                      .pk_out(pk), .sk_out(sk), .a_fail_o(a_fail), .done(done));

  reg [511:0]       coins;
  reg [8*1184-1:0]  exp_pk;
  reg [8*2400-1:0]  exp_sk;
  reg [8*1088-1:0]  dummy_ct;
  reg [255:0]       dummy32;
  reg [8*64-1:0]    tmp64;
  reg [8*100-1:0]   tag;
  reg [8*200-1:0]   vecfile;
  integer fd, r, i, errs, first_bad;

  initial begin
    if (!$value$plusargs("vec=%s", vecfile)) vecfile = "vectors/vecs_kemtop/kem_vec_1.txt";
    fd = $fopen(vecfile, "r");
    if (fd == 0) begin $display("RESULT: FAIL -- cannot open %0s", vecfile); $finish; end
    while (!$feof(fd)) begin
      r = $fscanf(fd, "%s", tag);
      if      (tag == "COINS") r = $fscanf(fd, "%h", coins);
      else if (tag == "PK")    r = $fscanf(fd, "%h", exp_pk);
      else if (tag == "SK")    r = $fscanf(fd, "%h", exp_sk);
      else if (tag == "CT" || tag == "CTBAD") r = $fscanf(fd, "%h", dummy_ct);
      else                     r = $fscanf(fd, "%h", dummy32);
    end
    $fclose(fd);

    d = coins[255:0]; z = coins[511:256];
    start = 0;
    repeat (4) @(negedge clk);
    rst_n = 1;
    repeat (2) @(negedge clk);
    start = 1; @(negedge clk); start = 0;

    fork
      begin wait (done === 1'b1); end
      begin repeat (3000000) @(negedge clk); $display("RESULT: FAIL -- keygen timeout"); $finish; end
    join_any
    disable fork;
    @(negedge clk);

    errs = 0; first_bad = -1;
    for (i = 0; i < 1184; i = i + 1)
      if (pk[8*i +: 8] !== exp_pk[8*i +: 8]) begin errs = errs + 1; if (first_bad < 0) first_bad = i; end
    if (errs) $display("pk: %0d byte mismatches (first at byte %0d)", errs, first_bad);
    else      $display("pk: all 1184 bytes match");
    first_bad = -1;
    for (i = 0; i < 2400; i = i + 1)
      if (sk[8*i +: 8] !== exp_sk[8*i +: 8]) begin errs = errs + 1; if (first_bad < 0) first_bad = i; end
    if (first_bad >= 0) $display("sk: mismatches, first at byte %0d", first_bad);
    else                $display("sk: all 2400 bytes match");
    if (a_fail) begin errs = errs + 1; $display("a_fail raised"); end

    if (errs == 0)
      $display("RESULT: kem_keygen_top PASS -- coins(64B) -> pk(1184B) and sk(2400B) byte-exact vs. reference crypto_kem_keypair_derand (%0s)", vecfile);
    else
      $display("RESULT: kem_keygen_top FAIL -- %0d mismatches (%0s)", errs, vecfile);
    $finish;
  end
endmodule
