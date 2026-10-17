`timescale 1ns/1ps
// tb_key_serialization_real.sv -- checks polyvec_tobytes.v (12-bit,
// full-precision key packing) against the real pack_sk()/pack_pk() output
// captured from indcpa.c during a genuine crypto_kem_keypair() call:
//   sk: polyvec_tobytes(skpv) alone -> 1152 real secret-key bytes
//   pk: polyvec_tobytes(pkpv) ++ publicseed(32) -> 1184 real public-key bytes
// (the seed concatenation is a plain wire append, not separate logic --
// the seed bytes checked here are the real ones captured in pack_pk_real.txt).

module tb_key_serialization_real;

  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  // ---- sk: polyvec_tobytes(skpv) ----
  reg  [4095:0] sk0, sk1, sk2;
  wire [9215:0] sk_bytes;
  reg           sk_start;
  wire          sk_done;
  polyvec_tobytes u_sk (.clk(clk), .rst_n(rst_n), .start_i(sk_start),
                         .a0_in(sk0), .a1_in(sk1), .a2_in(sk2),
                         .bytes_out(sk_bytes), .done(sk_done));

  // ---- pk: polyvec_tobytes(pkpv) ++ seed ----
  reg  [4095:0] pk0, pk1, pk2;
  wire [9215:0] pk_vec_bytes;
  reg           pk_start;
  wire          pk_done;
  polyvec_tobytes u_pk (.clk(clk), .rst_n(rst_n), .start_i(pk_start),
                         .a0_in(pk0), .a1_in(pk1), .a2_in(pk2),
                         .bytes_out(pk_vec_bytes), .done(pk_done));

  integer fd, r, i, errors, tot_errors, tmpv;
  integer real_sk_coeffs[0:767];
  integer real_sk_bytes[0:1151];
  integer real_pk_coeffs[0:767];
  integer real_pk_bytes[0:1183];
  reg [7:0] gotb;
  reg [8*1184-1:0] pk_full;

  initial begin
    fd = $fopen("vecs_hash/pack_sk_real.txt", "r");
    for (i = 0; i < 768; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_sk_coeffs[i] = tmpv; end
    for (i = 0; i < 1152; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_sk_bytes[i] = tmpv; end
    $fclose(fd);

    fd = $fopen("vecs_hash/pack_pk_real.txt", "r");
    for (i = 0; i < 768; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_pk_coeffs[i] = tmpv; end
    for (i = 0; i < 1184; i = i + 1) begin r = $fscanf(fd, "%d", tmpv); real_pk_bytes[i] = tmpv; end
    $fclose(fd);

    sk0 = 0; sk1 = 0; sk2 = 0;
    pk0 = 0; pk1 = 0; pk2 = 0;
    for (i = 0; i < 256; i = i + 1) begin
      sk0[16*i +: 16] = real_sk_coeffs[i][15:0];
      sk1[16*i +: 16] = real_sk_coeffs[256+i][15:0];
      sk2[16*i +: 16] = real_sk_coeffs[512+i][15:0];
      pk0[16*i +: 16] = real_pk_coeffs[i][15:0];
      pk1[16*i +: 16] = real_pk_coeffs[256+i][15:0];
      pk2[16*i +: 16] = real_pk_coeffs[512+i][15:0];
    end

    sk_start = 0; pk_start = 0; rst_n = 0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);
    tot_errors = 0;

    sk_start = 1; @(negedge clk); sk_start = 0;
    wait (sk_done == 1'b1); @(negedge clk);
    errors = 0;
    for (i = 0; i < 1152; i = i + 1) begin
      gotb = sk_bytes[8*i +: 8];
      if (gotb !== real_sk_bytes[i][7:0]) begin errors = errors + 1; if (errors <= 5) $display("SK BYTE FAIL[%0d]: got=%0d exp=%0d", i, gotb, real_sk_bytes[i]); end
    end
    $display("polyvec_tobytes.v (pack_sk, 768 coeffs -> 1152 bytes): mismatches=%0d/1152", errors);
    tot_errors = tot_errors + errors;

    pk_start = 1; @(negedge clk); pk_start = 0;
    wait (pk_done == 1'b1); @(negedge clk);

    // append the real captured seed bytes (pk bytes[1152:1184]) -- a plain
    // wire concatenation, exactly matching pack_pk()'s memcpy of the seed
    // after polyvec_tobytes(pk).
    pk_full = 0;
    pk_full[8*1152-1:0] = pk_vec_bytes;
    for (i = 0; i < 32; i = i + 1)
      pk_full[8*(1152+i) +: 8] = real_pk_bytes[1152+i][7:0];

    errors = 0;
    for (i = 0; i < 1184; i = i + 1) begin
      gotb = pk_full[8*i +: 8];
      if (gotb !== real_pk_bytes[i][7:0]) begin errors = errors + 1; if (errors <= 5) $display("PK BYTE FAIL[%0d]: got=%0d exp=%0d", i, gotb, real_pk_bytes[i]); end
    end
    $display("polyvec_tobytes.v ++ seed (pack_pk, 768 coeffs + 32-byte seed -> 1184 bytes): mismatches=%0d/1184", errors);
    tot_errors = tot_errors + errors;

    if (tot_errors == 0)
      $display("RESULT: polyvec_tobytes.v matches the real pack_sk()/pack_pk() wire-format serialization exactly (12-bit, full-precision key packing, distinct from the lossy ciphertext compression).");
    else
      $display("RESULT: FAIL (%0d total mismatches)", tot_errors);

    $finish;
  end

endmodule
