#!/usr/bin/env bash
# verilator_kem_program_recipe.sh -- build and run the lane-level ML-KEM-768
# program (tb_lane_kem_program.sv): keygen, encaps, decaps (valid + 2 tampered
# ciphertexts) executed as sequences of VPQC_* vector instructions through the
# real Ara lane.sv (lane_sequencer -> operand_requester -> operand queues ->
# vfu_pqc.sv -> VRF), byte-exact against the pq-crystals reference vectors.
#
# Needs: Verilator >= 5.020, and the patched Ara checkout + dependency clones
# at the paths below (see ../ARA_INTEGRATION.md for how they were produced).
# Usage:  bash verilator_kem_program_recipe.sh [vector numbers, default 1..6]
set -euo pipefail
WORK=${WORK:-/tmp/verilator_work}
ARA=${ARA:-/tmp/ara_src}
PQC=$(cd "$(dirname "$0")" && pwd)
PKG=$(cd "$PQC/.." && pwd)
mkdir -p "$WORK"; cd "$WORK"
cp "$PQC/filelist_sim.f" "$PQC/stub_cva6_config_pkg.sv" "$PQC/stub_serdiv.sv" "$PQC/tb_lane_kem_program.sv" .
rm -rf obj_kem
verilator --binary -Wno-fatal -Wno-ENUMVALUE -Wno-BLKANDNBLK -Wno-BLKLOOPINIT --timing -sv --error-limit 100 \
  --Mdir obj_kem -f filelist_sim.f \
  "$PQC/stub_riscv_axi_pkg.sv" stub_cva6_config_pkg.sv stub_serdiv.sv \
  "$ARA/hardware/include/rvv_pkg.sv" /tmp/common_cells_src/src/cf_math_pkg.sv \
  /tmp/fpu_div_sqrt_mvp_src/hdl/defs_div_sqrt_mvp.sv /tmp/cvfpu_src/src/fpnew_pkg.sv \
  "$ARA/hardware/include/ara_pkg.sv" /tmp/tech_cells_generic_src/src/rtl/tc_clk.sv \
  $(ls "$PKG"/verilog/*.v | grep -v /kem_) \
  "$PQC/vfu_pqc.sv" "$ARA/hardware/src/lane/lane.sv" \
  tb_lane_kem_program.sv --top-module tb_lane_kem_program -o tb_lane_kem_program > build_kem.log 2>&1
echo "build OK"
cd "$PKG"   # vector paths are relative to the package root
VECS=${@:-1 2 3 4 5 6}
rc=0
for n in $VECS; do
  out=$("$WORK/obj_kem/tb_lane_kem_program" +vec=vectors/vecs_kemtop/kem_vec_$n.txt 2>&1)
  echo "$out" | grep -E "busy cycles|totals" | sed "s/^/  [vec $n] /"
  if echo "$out" | grep -q "RESULT: Ara lane KEM program PASS"; then echo "PASS  ara_kem_program  kem_vec_$n.txt"; else echo "FAIL  ara_kem_program  kem_vec_$n.txt"; echo "$out" | tail -15; rc=1; fi
done
exit $rc
