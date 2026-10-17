`timescale 1ns/1ps
// tb_kem_encaps_top.sv -- END-TO-END Encaps check. Inputs are only pk (1184 B)
// and the 32-byte message m; H(pk), kr = SHA3-512(m||H(pk)), matrix A^T,
// noise, encryption arithmetic, and ciphertext compression/packing are all
// computed by kem_encaps_top.v. ct (1088 B) and ss (32 B) are compared
// byte-for-byte with the pq-crystals reference crypto_kem_enc_derand().
// Usage: vvp sim +vec=vectors/vecs_kemtop/kem_vec_N.txt
module tb_kem_encaps_top;
  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [8*1184-1:0] pk;
  reg  [255:0]      m;
  reg               start;
  wire [8*1088-1:0] ct;
  wire [255:0]      ss;
  wire a_fail, done;
  kem_encaps_top dut (.clk(clk), .rst_n(rst_n), .start_i(start), .pk_in(pk), .m_in(m),
                      .ct_out(ct), .ss_out(ss), .a_fail_o(a_fail), .done(done));

  reg [8*1088-1:0] exp_ct;
  reg [255:0]      exp_ss;
  reg [511:0]      dummy64;
  reg [8*2400-1:0] dummy_sk;
  reg [8*1088-1:0] dummy_ct;
  reg [255:0]      dummy32;
  reg [8*100-1:0]  tag;
  reg [8*200-1:0]  vecfile;
  integer fd, r, i, errs, first_bad;

  initial begin
    if (!$value$plusargs("vec=%s", vecfile)) vecfile = "vectors/vecs_kemtop/kem_vec_1.txt";
    fd = $fopen(vecfile, "r");
    if (fd == 0) begin $display("RESULT: FAIL -- cannot open %0s", vecfile); $finish; end
    while (!$feof(fd)) begin
      r = $fscanf(fd, "%s", tag);
      if      (tag == "M")  r = $fscanf(fd, "%h", m);
      else if (tag == "PK") r = $fscanf(fd, "%h", pk);
      else if (tag == "CT") r = $fscanf(fd, "%h", exp_ct);
      else if (tag == "SS") r = $fscanf(fd, "%h", exp_ss);
      else if (tag == "COINS") r = $fscanf(fd, "%h", dummy64);
      else if (tag == "SK") r = $fscanf(fd, "%h", dummy_sk);
      else if (tag == "CTBAD") r = $fscanf(fd, "%h", dummy_ct);
      else r = $fscanf(fd, "%h", dummy32);
    end
    $fclose(fd);

    start = 0;
    repeat (4) @(negedge clk);
    rst_n = 1;
    repeat (2) @(negedge clk);
    start = 1; @(negedge clk); start = 0;

    fork
      begin wait (done === 1'b1); end
      begin repeat (3000000) @(negedge clk); $display("RESULT: FAIL -- encaps timeout"); $finish; end
    join_any
    disable fork;
    @(negedge clk);

    errs = 0; first_bad = -1;
    for (i = 0; i < 1088; i = i + 1)
      if (ct[8*i +: 8] !== exp_ct[8*i +: 8]) begin errs = errs + 1; if (first_bad < 0) first_bad = i; end
    if (errs) $display("ct: %0d byte mismatches (first at byte %0d)", errs, first_bad);
    else      $display("ct: all 1088 bytes match");
    if (ss !== exp_ss) begin errs = errs + 1; $display("ss MISMATCH"); end
    else $display("ss: all 32 bytes match");
    if (a_fail) begin errs = errs + 1; $display("a_fail raised"); end

    if (errs == 0)
      $display("RESULT: kem_encaps_top PASS -- (pk, m) -> ct(1088B), ss(32B) byte-exact vs. reference crypto_kem_enc_derand (%0s)", vecfile);
    else
      $display("RESULT: kem_encaps_top FAIL -- %0d mismatches (%0s)", errs, vecfile);
    $finish;
  end
endmodule
