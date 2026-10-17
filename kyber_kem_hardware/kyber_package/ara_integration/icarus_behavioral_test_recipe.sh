#!/usr/bin/env bash
# icarus_behavioral_test_recipe.sh -- reproducible commands for the
# behavioral (not just elaboration) tests of vfu_pqc.sv's gather/compute/
# scatter FSM: tb_vfu_pqc_polymul.sv (VPQC_POLYMUL, checked against the
# real captured Kyber-768 a*b mod (X^256+1) mod 3329 vector) and
# tb_vfu_pqc_keccak_cbd.sv (VPQC_KECCAKPERM/VPQC_CBD2, checked against
# directly-instantiated reference copies of keccak_f1600.v/
# poly_cbd_eta2.v). Also re-runs the pre-existing VPQC_MONTMUL smoke test
# (tb_vfu_pqc_smoketest.sv) as a regression check.
#
# These use mock_ara_pkg.sv, NOT the real hardware/include/ara_pkg.sv,
# because Icarus Verilog (5.020) cannot parse fpnew_pkg.sv, a real
# transitive dependency the real ara_pkg.sv pulls in for unrelated FPU
# types. mock_ara_pkg.sv reproduces only the handful of real ara_pkg
# declarations vfu_pqc.sv actually uses (NrVInsn, vid_t, elen_t, the 5
# ara_op_e values) -- see that file's header for the exact justification.
# The real, unmodified ara_pkg.sv IS used for the separate Verilator
# --lint-only elaboration of the actual wired-in lane.sv hierarchy (see
# verilator_build_recipe.sh) -- these two checks are complementary, not
# redundant: elaboration proves the real wiring is structurally sound;
# these prove the new FSM states compute the right answer.
set -euo pipefail

PQC=/tmp/kyber_package/ara_integration
KYBER=/tmp/kyber_package/verilog
WORK=/tmp/icarus_behavioral_work
mkdir -p "$WORK"
cp "$PQC/poly_mul_ntt_real.txt" "$WORK/"

COMMON_FILES=(
  "$PQC/mock_ara_pkg.sv"
  /tmp/common_cells_src/src/cf_math_pkg.sv   # real common_cells, for cf_math_pkg::idx_width
  $(ls "$KYBER"/*.v | grep -v /kem_)
  "$PQC/vfu_pqc.sv"
)

# NOTE (generic-engine rewrite): the standalone Icarus POLYMUL and KECCAKPERM/CBD2
# tests (tb_vfu_pqc_polymul.sv, tb_vfu_pqc_keccak_cbd.sv) are NOT run here any more.
# With the generic table-driven engine (24 compute blocks and 12288-bit wide
# buffers) Icarus needs > 4 minutes and did not finish them; those ops are
# covered, bit-exact, by the Verilator lane.sv-level tests instead
# (verilator_sim_recipe_full.sh -> tb_lane_vpqc_pqc_full.sv, plus the full ML-KEM
# program in verilator_kem_program_recipe.sh). The testbench files remain for reference.

echo "=== VPQC_MONTMUL smoke test (pre-existing, regression check) ==="
iverilog -g2012 -o "$WORK/montmul_smoke.vvp" "${COMMON_FILES[@]}" "$PQC/tb_vfu_pqc_smoketest.sv"
( cd "$WORK" && vvp montmul_smoke.vvp )
