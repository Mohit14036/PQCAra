`timescale 1ns/1ps
// tb_kem_fullloop.sv -- the three RTL top-levels chained with NO reference
// data between them:
//     coins(64 B) --kem_keygen_top--> pk, sk
//     (pk, m)     --kem_encaps_top--> ct, ss_enc
//     (sk, ct)    --kem_decaps_top--> ss_dec
// Checks: ss_dec == ss_enc (the KEM correctness property), and, against the
// pq-crystals reference for the same coins/m, that pk, sk, ct and ss are all
// byte-exact. Then a tampered ct must give a different key (implicit reject).
// Usage: vvp sim +vec=vectors/vecs_kemtop/kem_vec_N.txt
module tb_kem_fullloop;
  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [255:0] d, z, m;
  reg          kg_start = 0, en_start = 0, de_start = 0;
  wire [8*1184-1:0] pk;   wire [8*2400-1:0] sk;   wire kg_fail, kg_done;
  wire [8*1088-1:0] ct;   wire [255:0] ss_enc;    wire en_fail, en_done;
  wire [255:0] ss_dec;    wire reject, de_fail, de_done;
  reg  [8*1088-1:0] ct_in;

  kem_keygen_top kg (.clk(clk), .rst_n(rst_n), .start_i(kg_start), .d_in(d), .z_in(z),
                     .pk_out(pk), .sk_out(sk), .a_fail_o(kg_fail), .done(kg_done));
  kem_encaps_top en (.clk(clk), .rst_n(rst_n), .start_i(en_start), .pk_in(pk), .m_in(m),
                     .ct_out(ct), .ss_out(ss_enc), .a_fail_o(en_fail), .done(en_done));
  kem_decaps_top de (.clk(clk), .rst_n(rst_n), .start_i(de_start), .sk_in(sk), .ct_in(ct_in),
                     .ss_out(ss_dec), .reject_o(reject), .a_fail_o(de_fail), .done(de_done));

  reg [511:0] coins;
  reg [8*1184-1:0] r_pk;  reg [8*2400-1:0] r_sk;  reg [8*1088-1:0] r_ct, r_ctbad, r_ctbad2;
  reg [255:0] r_m, r_ss, r_ssdec, r_ssbad, r_ssbad2;
  reg [8*100-1:0] tag;  reg [8*200-1:0] vecfile;
  integer fd, r, errs;

  task pulse_wait_kg; begin kg_start = 1; @(negedge clk); kg_start = 0; wait (kg_done === 1'b1); @(negedge clk); end endtask
  task pulse_wait_en; begin en_start = 1; @(negedge clk); en_start = 0; wait (en_done === 1'b1); @(negedge clk); end endtask
  task pulse_wait_de; begin de_start = 1; @(negedge clk); de_start = 0; wait (de_done === 1'b1); @(negedge clk); end endtask

  initial begin
    if (!$value$plusargs("vec=%s", vecfile)) vecfile = "vectors/vecs_kemtop/kem_vec_1.txt";
    fd = $fopen(vecfile, "r");
    while (!$feof(fd)) begin
      r = $fscanf(fd, "%s", tag);
      if      (tag == "COINS")  r = $fscanf(fd, "%h", coins);
      else if (tag == "M")      r = $fscanf(fd, "%h", r_m);
      else if (tag == "PK")     r = $fscanf(fd, "%h", r_pk);
      else if (tag == "SK")     r = $fscanf(fd, "%h", r_sk);
      else if (tag == "CT")     r = $fscanf(fd, "%h", r_ct);
      else if (tag == "SS")     r = $fscanf(fd, "%h", r_ss);
      else if (tag == "SSDEC")  r = $fscanf(fd, "%h", r_ssdec);
      else if (tag == "CTBAD2") r = $fscanf(fd, "%h", r_ctbad2);
      else if (tag == "CTBAD")  r = $fscanf(fd, "%h", r_ctbad);
      else if (tag == "SSBAD2") r = $fscanf(fd, "%h", r_ssbad2);
      else if (tag == "SSBAD")  r = $fscanf(fd, "%h", r_ssbad);
    end
    $fclose(fd);
    d = coins[255:0]; z = coins[511:256]; m = r_m;
    errs = 0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

    pulse_wait_kg;
    if (pk !== r_pk || sk !== r_sk) begin errs = errs + 1; $display("keygen output != reference"); end
    pulse_wait_en;                      // encaps consumes the RTL keygen's pk directly
    if (ct !== r_ct || ss_enc !== r_ss) begin errs = errs + 1; $display("encaps output != reference"); end
    ct_in = ct;
    pulse_wait_de;                      // decaps consumes the RTL keygen's sk + RTL encaps' ct
    if (ss_dec !== ss_enc || reject !== 1'b0) begin errs = errs + 1; $display("ss_dec != ss_enc (reject=%b)", reject); end
    if (ss_dec !== r_ssdec) begin errs = errs + 1; $display("ss_dec != reference"); end
    if (kg_fail || en_fail || de_fail) begin errs = errs + 1; $display("a_fail raised"); end

    ct_in = r_ctbad;                    // tampered ciphertext
    pulse_wait_de;
    if (ss_dec === ss_enc || ss_dec !== r_ssbad || reject !== 1'b1) begin errs = errs + 1; $display("tampered ct handling wrong"); end

    if (errs == 0)
      $display("RESULT: full KEM loop PASS -- RTL keygen -> RTL encaps -> RTL decaps: ss_dec == ss_enc, pk/sk/ct/ss byte-exact vs. reference, tampered ct implicitly rejected (%0s)", vecfile);
    else
      $display("RESULT: full KEM loop FAIL -- %0d problems (%0s)", errs, vecfile);
    $finish;
  end
endmodule
