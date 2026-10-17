// mock_ara_pkg.sv -- STANDALONE UNIT-TEST STAND-IN, NOT part of the design
// or of the Verilator elaboration (that uses the real, unmodified
// hardware/include/ara_pkg.sv from a real ara clone -- see
// ../ara_integration/verilator_build_recipe.sh / verilator_lane_elaboration.log,
// which already elaborates cleanly, exit code 0, against the real package).
//
// Icarus Verilog cannot parse fpnew_pkg.sv (a real transitive dependency of
// the real ara_pkg.sv, pulled in for unrelated FPU types), so it cannot be
// used to *simulate* vfu_pqc.sv against the real package. This file exists
// only to let Icarus run a behavioral (not just elaboration) test of
// vfu_pqc.sv's new VPQC_POLYMUL gather/compute/scatter FSM logic, by
// reproducing -- byte for byte, verified by direct grep against the real
// file -- the handful of real ara_pkg declarations vfu_pqc.sv actually
// uses: NrVInsn, vid_t, elen_t, and the 5 ara_op_e values it references.
package ara_pkg;
  localparam int unsigned ELEN    = 64;
  localparam int unsigned NrVInsn = 8;
  typedef logic [$clog2(NrVInsn)-1:0] vid_t;
  typedef logic [ELEN-1:0] elen_t;

  typedef enum logic [5:0] {
    VPQC_MONTMUL, VPQC_BARRETT,
    VPQC_KECCAKPERM, VPQC_CBD2,
    VPQC_POLYMUL,
    VPQC_SHA3_512_33, VPQC_SHA3_512_64, VPQC_SHA3_256_PK,
    VPQC_SHAKE128_XOF, VPQC_SHAKE256_PRF, VPQC_SHAKE256_RK,
    VPQC_NTT, VPQC_INVNTT, VPQC_REDUCE, VPQC_TOMONT,
    VPQC_PADD, VPQC_PSUB, VPQC_BASEMUL_ACC, VPQC_REJ,
    VPQC_TOBYTES, VPQC_FROMBYTES, VPQC_PVCOMP, VPQC_PVDECOMP,
    VPQC_PCOMP, VPQC_PDECOMP, VPQC_FROMMSG, VPQC_TOMSG,
    VPQC_CTVERIFY, VPQC_CMOV
  } ara_op_e;

  function logic pqc_uses_vs1(ara_op_e op);
    pqc_uses_vs1 = (op == VPQC_MONTMUL) || (op == VPQC_POLYMUL) || (op == VPQC_PADD) ||
                   (op == VPQC_PSUB) || (op == VPQC_BASEMUL_ACC) || (op == VPQC_CTVERIFY) ||
                   (op == VPQC_CMOV);
  endfunction

  // vaddr() -- copied VERBATIM from the real hardware/include/ara_pkg.sv
  // (grep-verified, not reconstructed from memory), needed because
  // vfu_pqc.sv now computes its real VRF destination address via
  // ara_pkg::vaddr(vd, NrLanes, VLEN) instead of the old elem_cnt-only
  // placeholder (see vfu_pqc.sv's pqc_result_addr_o comment -- that was a
  // real bug this session's lane.sv-level Verilator simulation caught).
  // NOT declared `automatic` here (the real ara_pkg.sv's vaddr() IS
  // automatic -- that real, unmodified declaration is what the Verilator
  // lane.sv-level simulation actually exercises and verified bit-exact;
  // see tb_lane_vpqc_montmul.sv). This mock copy drops `automatic`
  // purely as an Icarus Verilog (5.020) workaround: a minimal, isolated
  // repro (an `automatic` function with a 64-bit return calling another
  // `int`-typed local, invoked from a clocked or even purely
  // combinational context) reproducibly crashes vvp with
  // "vthread.cc:5451: bool of_RET_VEC4(...): Assertion `index <
  // get_max(fun_thr, val)' failed" -- a real Icarus simulator bug/
  // limitation, not an RTL bug (the static/non-automatic version below
  // computes the identical, correct result: vaddr(3,4,1024)=12).
  function logic [63:0] vaddr(logic [4:0] vid, int NrLanes, int vlen);
    int vlenb;
    begin
      vlenb = vlen / 8;
      vaddr = vid * (vlenb / NrLanes / 8);
    end
  endfunction: vaddr
endpackage
