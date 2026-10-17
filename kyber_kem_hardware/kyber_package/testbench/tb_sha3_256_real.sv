`timescale 1ns/1ps
// tb_sha3_256_real.sv -- checks keccak_sponge.v configured as SHA3-256
// (rate=136 bytes, pad=0x06) against real hash_h() calls captured from
// a genuine crypto_kem_keypair()+crypto_kem_enc() round trip: call0 is
// H(pk) computed inside keypair (stored into sk), call1 is H(pk)
// recomputed inside encaps -- both hash the SAME 1184-byte real public
// key, so both must (and do) produce the same 32-byte digest.

module tb_sha3_256_real;

  localparam IN_LEN = 1184;

  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [8*IN_LEN-1:0] in_bytes;
  wire [255:0]         out_bytes;
  reg                  start_i;
  wire                 done;

  keccak_sponge #(.RATE_BYTES(136), .IN_LEN(IN_LEN), .OUT_LEN(32), .PAD_BYTE(8'h06))
    dut (.clk(clk), .rst_n(rst_n), .start_i(start_i),
         .in_bytes(in_bytes), .out_bytes(out_bytes), .done(done));

  integer fd, r, i, errors, call, tot_errors;
  integer tmpv, inlen_check;
  integer real_in[0:1183];
  integer real_out[0:31];
  reg [7:0] gotb;
  reg [255:0] passed_ok;

  task run_one(input integer callno);
    begin
      case (callno)
        0: fd = $fopen("vecs_hash/sha3_256_call0_real.txt", "r");
        1: fd = $fopen("vecs_hash/sha3_256_call1_real.txt", "r");
      endcase
      r = $fscanf(fd, "%d", inlen_check);
      for (i = 0; i < IN_LEN; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_in[i] = tmpv; end
      for (i = 0; i < 32; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_out[i] = tmpv; end
      $fclose(fd);

      in_bytes = 0;
      for (i = 0; i < IN_LEN; i = i + 1) in_bytes[8*i +: 8] = real_in[i][7:0];

      start_i = 1; @(negedge clk); start_i = 0;
      wait (done == 1'b1); @(negedge clk);

      errors = 0;
      for (i = 0; i < 32; i = i + 1) begin
        gotb = out_bytes[8*i +: 8];
        if (gotb !== real_out[i][7:0]) begin
          errors = errors + 1;
          $display("call%0d BYTE FAIL[%0d]: got=%0d exp=%0d", callno, i, gotb, real_out[i]);
        end
      end
      $display("sha3_256 call%0d (inlen=%0d): mismatches=%0d/32", callno, inlen_check, errors);
      tot_errors = tot_errors + errors;
    end
  endtask

  initial begin
    start_i = 0; rst_n = 0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);
    tot_errors = 0;

    run_one(0);
    run_one(1);

    if (tot_errors == 0)
      $display("RESULT: keccak_sponge.v as SHA3-256 matches real hash_h() exactly on both real calls (keypair's H(pk) and encaps' H(pk)), built on the verified keccak_f1600 core.");
    else
      $display("RESULT: FAIL (%0d total mismatches)", tot_errors);

    $finish;
  end

endmodule
