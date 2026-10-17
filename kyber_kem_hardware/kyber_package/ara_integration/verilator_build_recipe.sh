#!/usr/bin/env bash
# verilator_build_recipe.sh -- exact, real command used to elaborate the
# PQC-wired lane hierarchy with Verilator, plus the exact upstream commits
# it was checked against (all read directly out of Ara's own real
# Bender.lock at commit 34bd3bc152421b4601a7bf3d6e8e91ffb545c99e, not
# guessed). Re-running this from scratch reproduces the "EXIT CODE: 0"
# result recorded in verilator_lane_elaboration.log.
#
# This elaborates hardware/src/lane/lane.sv -- the lane containing the new
# vfu_pqc instantiation -- NOT the whole Ara chip (ara.sv/ara_dispatcher.sv/
# CVA6/the AXI SoC wrapper are out of scope; see ARA_INTEGRATION.md).
set -euo pipefail

WORK=/tmp/verilator_work   # adjust as needed
ARA=/tmp/ara_src           # git clone --depth 1 https://github.com/pulp-platform/ara.git, patched by
                            # ara_pqc_enum_decode.patch and ara_pqc_lane_wiring.patch
CC=/tmp/common_cells_src    # pulp-platform/common_cells @ c27bce39ebb2e6bae52f60960814a2afca7bd4cb (v1.37.0, Bender.lock-pinned)
FPU=/tmp/cvfpu_src          # pulp-platform/cvfpu       @ e5aa6a01b5bbe1675c3aa8872e1203413ded83d1        (Bender.lock-pinned)
TCG=/tmp/tech_cells_generic_src # pulp-platform/tech_cells_generic @ 7968dd6e6180df2c644636bc6d2908a49f2190cf (v0.2.13, Bender.lock-pinned)
DIVSQRT=/tmp/fpu_div_sqrt_mvp_src # pulp-platform/fpu_div_sqrt_mvp @ 86e1f558b3c95e91577c41b2fc452c86b04e85ac (v1.0.4, Bender.lock-pinned)
KYBER=/tmp/kyber_package/verilog  # the already hash/math-verified Kyber primitives from this repo
PQC=/tmp/kyber_package/ara_integration

cat > "$WORK/filelist.f" << EOF
+incdir+$ARA/hardware/include
+incdir+$ARA/hardware/include/ara
+incdir+$CC/include
-y $ARA/hardware/src/lane
-y $CC/src
-y $CC/src/deprecated
-y $FPU/src
-y $TCG/src/rtl
-y $TCG/src/deprecated
-y $DIVSQRT/hdl
EOF

verilator --lint-only -Wno-fatal -Wno-ENUMVALUE -Wno-BLKANDNBLK -Wno-BLKLOOPINIT --timing -sv --error-limit 500 \
  -f "$WORK/filelist.f" \
  "$PQC/stub_riscv_axi_pkg.sv" "$PQC/stub_cva6_config_pkg.sv" "$PQC/stub_serdiv.sv" \
  "$ARA/hardware/include/rvv_pkg.sv" \
  "$CC/src/cf_math_pkg.sv" \
  "$DIVSQRT/hdl/defs_div_sqrt_mvp.sv" \
  "$FPU/src/fpnew_pkg.sv" \
  "$ARA/hardware/include/ara_pkg.sv" \
  "$TCG/src/rtl/tc_clk.sv" \
  $(ls "$KYBER"/*.v | grep -v /kem_ | tr '\n' ' ') \
  "$PQC/vfu_pqc.sv" \
  "$ARA/hardware/src/lane/lane.sv" \
  --top-module lane

# -Wno-ENUMVALUE and -Wno-BLKANDNBLK are suppressed because they fire
# identically on pre-existing, unmodified upstream Ara/cvfpu code paths
# this PQC integration does not touch (see ARA_INTEGRATION.md for where
# each was confirmed to originate). Nothing about the PQC wiring itself
# relies on either suppression.
#
# -Wno-BLKLOOPINIT is suppressed for a real, narrower reason: Verilator
# (5.020) does not support a non-blocking (<=) assignment to an array
# element inside a `for` loop -- e.g. `for (i=0;i<256;i=i+1) mem[i] <=
# in[i];`, used by ntt_fwd.v/ntt_inv.v/poly_basemul_montgomery.v to load
# their 256-coefficient register-array inputs in one clocked block. This
# is a genuine Verilator lint-only elaboration limitation (their docs say
# non-delayed/blocking assignment is fine; only the delayed form inside a
# loop is unsupported), not a correctness bug -- Icarus Verilog simulates
# these same loops correctly, and all three modules are separately
# bit-exact-verified against real reference execution (see
# ../ntt_scaling/NTT_SCALING.md). It is suppressed here only because this
# recipe never simulates with Verilator, only elaborates (--lint-only);
# a real Verilator *simulation* build of these modules would need the
# loops rewritten (e.g. blocking assignment to a `next` array combined
# with a separate FF update, or an explicit per-element unroll) to avoid
# relying on this suppression.
#
# UPDATE: that prediction was confirmed the hard way when the full KEM program was simulated
# in Verilator: the original non-blocking load loops produced WRONG results there (ntt_fwd gave
# 0000/fb00 instead of f605/f464). All 15 affected modules in ../verilog now use blocking
# assignments in those load loops (Icarus regression re-run: 28/28 + 24/24 pass), so the
# suppression is no longer hiding a functional difference.
#
# stub_riscv_axi_pkg.sv / stub_cva6_config_pkg.sv / stub_serdiv.sv stand
# in for genuinely external repos (CVA6's riscv/config packages and its
# serdiv module) that Ara's real lane/ files reference for functionality
# the PQC path never exercises (CSR addresses, the FPU's CVA6Cfg passthrough,
# integer divide) and that were judged out of scope to clone/generate in
# full for this session -- see ARA_INTEGRATION.md for exactly what each
# stub fabricates and why.
