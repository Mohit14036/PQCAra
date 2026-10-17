`timescale 1ns/1ps
// tb_kem_decaps_top.sv -- END-TO-END Decaps check, both FO branches.
// Inputs are only sk (2400 B) and a ciphertext. Everything between (unpack,
// decompress, IND-CPA decrypt, m' extraction, kr' = SHA3-512(m'||h),
// re-encryption, constant-time compare, rkprf, constant-time select) is
// computed by kem_decaps_top.v.
//   run 1: valid ct          -> ss must equal the reference AND the Encaps ss,
//                               reject_o must be 0
//   run 2: ct with one bit flipped (b part) -> ss must equal the reference implicit-
//                               rejection key (different from run 1), reject_o = 1
//   run 3: ct with one bit flipped (v part) -> its own distinct rejection key
// Usage: vvp sim +vec=vectors/vecs_kemtop/kem_vec_N.txt
module tb_kem_decaps_top;
  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [8*2400-1:0] sk;
  reg  [8*1088-1:0] ct;
  reg               start;
  wire [255:0]      ss;
  wire reject, a_fail, done;
  kem_decaps_top dut (.clk(clk), .rst_n(rst_n), .start_i(start), .sk_in(sk), .ct_in(ct),
                      .ss_out(ss), .reject_o(reject), .a_fail_o(a_fail), .done(done));

  reg [8*1088-1:0] ct_good, ct_bad, ct_bad2;
  reg [255:0]      ss_enc, ss_dec_ref, ss_bad_ref, ss_bad2_ref;
  reg [511:0]      dummy64;
  reg [8*1184-1:0] dummy_pk;
  reg [255:0]      dummy32;
  reg [8*100-1:0]  tag;
  reg [8*200-1:0]  vecfile;
  integer fd, r, errs;

  task run_dec;
    begin
      start = 1; @(negedge clk); start = 0;
      fork
        begin wait (done === 1'b1); end
        begin repeat (3000000) @(negedge clk); $display("RESULT: FAIL -- decaps timeout"); $finish; end
      join_any
      disable fork;
      @(negedge clk);
    end
  endtask

  initial begin
    if (!$value$plusargs("vec=%s", vecfile)) vecfile = "vectors/vecs_kemtop/kem_vec_1.txt";
    fd = $fopen(vecfile, "r");
    if (fd == 0) begin $display("RESULT: FAIL -- cannot open %0s", vecfile); $finish; end
    while (!$feof(fd)) begin
      r = $fscanf(fd, "%s", tag);
      if      (tag == "SK")    r = $fscanf(fd, "%h", sk);
      else if (tag == "CT")    r = $fscanf(fd, "%h", ct_good);
      else if (tag == "CTBAD2") r = $fscanf(fd, "%h", ct_bad2);
      else if (tag == "CTBAD") r = $fscanf(fd, "%h", ct_bad);
      else if (tag == "SS")    r = $fscanf(fd, "%h", ss_enc);
      else if (tag == "SSDEC") r = $fscanf(fd, "%h", ss_dec_ref);
      else if (tag == "SSBAD2") r = $fscanf(fd, "%h", ss_bad2_ref);
      else if (tag == "SSBAD") r = $fscanf(fd, "%h", ss_bad_ref);
      else if (tag == "COINS") r = $fscanf(fd, "%h", dummy64);
      else if (tag == "PK")    r = $fscanf(fd, "%h", dummy_pk);
      else                     r = $fscanf(fd, "%h", dummy32);
    end
    $fclose(fd);

    start = 0; errs = 0;
    repeat (4) @(negedge clk);
    rst_n = 1;
    repeat (2) @(negedge clk);

    // ---- run 1: valid ciphertext ----
    ct = ct_good;
    run_dec;
    if (ss === ss_dec_ref && ss === ss_enc && reject === 1'b0)
      $display("valid ct : ss matches reference decaps AND the encaps shared secret, reject_o=0");
    else begin errs = errs + 1; $display("valid ct : FAIL ss_match_ref=%0d ss_match_enc=%0d reject=%b",
                                          (ss === ss_dec_ref), (ss === ss_enc), reject); end
    if (a_fail) begin errs = errs + 1; $display("a_fail raised (valid)"); end

    // ---- run 2: tampered ciphertext -> implicit rejection ----
    ct = ct_bad;
    run_dec;
    if (ss === ss_bad_ref && ss !== ss_enc && reject === 1'b1)
      $display("tampered : ss matches reference implicit-rejection key, differs from real ss, reject_o=1");
    else begin errs = errs + 1; $display("tampered : FAIL ss_match_ref=%0d differs_from_real=%0d reject=%b",
                                          (ss === ss_bad_ref), (ss !== ss_enc), reject); end
    if (a_fail) begin errs = errs + 1; $display("a_fail raised (tampered)"); end

    // ---- run 3: ciphertext tampered inside the v (poly_compress) part ----
    ct = ct_bad2;
    run_dec;
    if (ss === ss_bad2_ref && ss !== ss_enc && ss !== ss_bad_ref && reject === 1'b1)
      $display("tampered2: v-part tamper -> reference implicit-rejection key (distinct per ct), reject_o=1");
    else begin errs = errs + 1; $display("tampered2: FAIL ss_match_ref=%0d reject=%b", (ss === ss_bad2_ref), reject); end
    if (a_fail) begin errs = errs + 1; $display("a_fail raised (tampered2)"); end

    if (errs == 0)
      $display("RESULT: kem_decaps_top PASS -- (sk, ct) -> ss for BOTH the accept path and the FO implicit-rejection path, byte-exact vs. reference crypto_kem_dec (%0s)", vecfile);
    else
      $display("RESULT: kem_decaps_top FAIL -- %0d failures (%0s)", errs, vecfile);
    $finish;
  end
endmodule
