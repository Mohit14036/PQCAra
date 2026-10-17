`timescale 1ns/1ps
// tb_ct_verify_cmov_real.sv -- checks ct_verify.v and cmov_bytes.v
// against real data from ref/kem.c's crypto_kem_dec() (vecs_kem/kem_dec_real.txt:
// ct, cmp, fail, kr(64B), rkprf-ss(32B pre-cmov), final ss(32B post-cmov)),
// for BOTH branches of the FO transform:
//   1) the real captured (matching) case: ct==cmp, fail=0, ss=kr[0:32]
//   2) a deliberately corrupted ct (one byte flipped) fed through the
//      SAME verified modules, to exercise the mismatch/implicit-rejection
//      branch (ss stays the rkprf value, not kr) -- both branches are
//      real hardware logic, not just the common-case path.

module tb_ct_verify_cmov_real;

  localparam CTBYTES = 1088;

  reg clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  reg  [8*CTBYTES-1:0] ct_a, ct_b;
  reg                  vstart;
  wire                 vfail, vdone;
  ct_verify #(.CTBYTES(CTBYTES)) u_v (.clk(clk), .rst_n(rst_n), .start_i(vstart),
                                        .ct_a_in(ct_a), .ct_b_in(ct_b),
                                        .fail_out(vfail), .done(vdone));

  reg  [255:0] r_in, x_in;
  reg          sel_in, mstart;
  wire [255:0] r_out;
  wire         mdone;
  cmov_bytes #(.NBYTES(32)) u_m (.clk(clk), .rst_n(rst_n), .start_i(mstart),
                                   .r_in(r_in), .x_in(x_in), .sel_in(sel_in),
                                   .r_out(r_out), .done(mdone));

  integer fd, r, i, tmpv, errors;
  integer real_ct[0:1087], real_cmp[0:1087];
  integer real_fail;
  integer real_kr[0:63];
  integer real_rkprf_ss[0:31];
  integer real_final_ss[0:31];
  reg [7:0] gotb;

  initial begin
    fd = $fopen("vecs_kem/kem_dec_real.txt", "r");
    for (i = 0; i < 1088; i = i + 1) begin r=$fscanf(fd,"%d",tmpv); real_ct[i]=tmpv; end
    for (i = 0; i < 1088; i = i + 1) begin r=$fscanf(fd,"%d",tmpv); real_cmp[i]=tmpv; end
    r = $fscanf(fd, "%d", real_fail);
    for (i = 0; i < 64; i = i + 1) begin r=$fscanf(fd,"%d",tmpv); real_kr[i]=tmpv; end
    for (i = 0; i < 32; i = i + 1) begin r=$fscanf(fd,"%d",tmpv); real_rkprf_ss[i]=tmpv; end
    for (i = 0; i < 32; i = i + 1) begin r=$fscanf(fd,"%d",tmpv); real_final_ss[i]=tmpv; end
    $fclose(fd);

    ct_a = 0; ct_b = 0;
    for (i = 0; i < 1088; i = i + 1) begin
      ct_a[8*i +: 8] = real_ct[i][7:0];
      ct_b[8*i +: 8] = real_cmp[i][7:0];
    end

    vstart=0; mstart=0; rst_n = 0;
    repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

    errors = 0;

    // ---- scenario 1: real captured (matching) ct/cmp ----
    vstart = 1; @(negedge clk); vstart = 0;
    wait (vdone == 1'b1); @(negedge clk);
    if (vfail !== real_fail[0]) begin
      errors = errors + 1;
      $display("VERIFY FAIL (match case): got fail=%0d exp=%0d", vfail, real_fail);
    end else
      $display("ct_verify.v matches real verify(): fail=%0d (expected %0d, real ciphertexts matched)", vfail, real_fail);

    // feed real kr[0:32] as x_in, real rkprf ss as r_in, sel = !fail
    r_in = 0; x_in = 0;
    for (i = 0; i < 32; i = i + 1) begin
      r_in[8*i +: 8] = real_rkprf_ss[i][7:0];
      x_in[8*i +: 8] = real_kr[i][7:0];
    end
    sel_in = !vfail;
    mstart = 1; @(negedge clk); mstart = 0;
    wait (mdone == 1'b1); @(negedge clk);
    for (i = 0; i < 32; i = i + 1) begin
      gotb = r_out[8*i +: 8];
      if (gotb !== real_final_ss[i][7:0]) begin
        errors = errors + 1;
        if (errors <= 10) $display("CMOV FAIL[%0d]: got=%0d exp=%0d", i, gotb, real_final_ss[i]);
      end
    end
    if (errors == 0)
      $display("cmov_bytes.v matches real cmov(): final ss matches real crypto_kem_dec() output exactly (32/32 bytes)");

    // ---- scenario 2: deliberately corrupt ct (flip one byte) to
    // exercise the OTHER branch (mismatch -> implicit rejection) ----
    ct_a[7:0] = ct_a[7:0] ^ 8'hFF;
    vstart = 1; @(negedge clk); vstart = 0;
    wait (vdone == 1'b1); @(negedge clk);
    if (vfail !== 1'b1) begin
      errors = errors + 1;
      $display("VERIFY FAIL (corrupted case): expected fail=1, got fail=%0d", vfail);
    end else
      $display("ct_verify.v correctly detects a corrupted ciphertext: fail=1");

    // with fail=1, sel=!fail=0 -> cmov must KEEP r_in (the rkprf reject key), not take kr
    sel_in = !vfail;
    mstart = 1; @(negedge clk); mstart = 0;
    wait (mdone == 1'b1); @(negedge clk);
    errors = errors; // reuse counter below
    begin
      integer local_err;
      local_err = 0;
      for (i = 0; i < 32; i = i + 1) begin
        gotb = r_out[8*i +: 8];
        if (gotb !== real_rkprf_ss[i][7:0]) local_err = local_err + 1;
      end
      if (local_err == 0)
        $display("cmov_bytes.v correctly REJECTS on mismatch: ss stays the rkprf pseudo-random key (implicit rejection), not kr");
      else begin
        errors = errors + local_err;
        $display("CMOV REJECT-PATH FAIL: %0d/32 bytes wrong", local_err);
      end
    end

    if (errors == 0)
      $display("RESULT: ct_verify.v + cmov_bytes.v match the real Fujisaki-Okamoto verify()/cmov() logic exactly, on BOTH the accept and implicit-reject branches");
    else
      $display("RESULT: FAIL (%0d total mismatches)", errors);

    $finish;
  end

endmodule
