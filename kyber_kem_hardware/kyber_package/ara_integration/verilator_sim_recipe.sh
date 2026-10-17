#!/usr/bin/env bash
# verilator_sim_recipe.sh -- builds and runs tb_lane_vpqc_montmul.sv: a real
# Verilator *simulation* (not --lint-only elaboration) of the actual,
# wired-in hardware/src/lane/lane.sv hierarchy, driven through its real
# pe_req_i instruction interface with a real VPQC_MONTMUL instruction.
#
# This is the direct behavioral counterpart of verilator_build_recipe.sh
# (which only proves the wiring elaborates cleanly). It proves the wiring
# actually computes the right answer end-to-end through the real:
#   lane.sv -> lane_sequencer.sv -> operand_requester.sv ->
#   operand_queues_stage.sv -> vfu_pqc.sv -> operand_requester.sv (VRF
#   write arbiter) -> vector_regfile.sv
# path -- not vfu_pqc.sv standalone, and not a mock package. See
# tb_lane_vpqc_montmul.sv's own header comment for the exact technique
# (real sldu_result_* port used to preload source operands; a passive,
# read-only peek at vector_regfile.sv's real tc_sram array used to read
# back the destination -- no backdoor force/poke of DUT state anywhere).
#
# Same repo pins as verilator_build_recipe.sh (see that file for the exact
# upstream commits, all read directly out of Ara's own Bender.lock).
set -euo pipefail

WORK=/tmp/verilator_work   # adjust as needed; must be writable, Verilator's
                            # --binary build products (obj_dir/) land here
ARA=/tmp/ara_src
CC=/tmp/common_cells_src
FPU=/tmp/cvfpu_src
TCG=/tmp/tech_cells_generic_src
DIVSQRT=/tmp/fpu_div_sqrt_mvp_src
KYBER=/tmp/kyber_package/verilog
PQC=/tmp/kyber_package/ara_integration

mkdir -p "$WORK"
cat > "$WORK/filelist_sim.f" << EOF
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

cp "$PQC/stub_cva6_config_pkg.sv" "$PQC/stub_serdiv.sv" "$PQC/tb_lane_vpqc_montmul.sv" "$WORK/"

cd "$WORK"
verilator --binary -Wno-fatal -Wno-ENUMVALUE -Wno-BLKANDNBLK -Wno-BLKLOOPINIT --timing -sv --error-limit 100 \
  -f filelist_sim.f \
  "$PQC/stub_riscv_axi_pkg.sv" stub_cva6_config_pkg.sv stub_serdiv.sv \
  "$ARA/hardware/include/rvv_pkg.sv" "$CC/src/cf_math_pkg.sv" \
  "$DIVSQRT/hdl/defs_div_sqrt_mvp.sv" "$FPU/src/fpnew_pkg.sv" \
  "$ARA/hardware/include/ara_pkg.sv" "$TCG/src/rtl/tc_clk.sv" \
  $(ls "$KYBER"/*.v | grep -v /kem_ | tr '\n' ' ') \
  "$PQC/vfu_pqc.sv" "$ARA/hardware/src/lane/lane.sv" \
  tb_lane_vpqc_montmul.sv \
  --top-module tb_lane_vpqc_montmul -o tb_lane_vpqc_montmul

echo "=== running the built simulation ==="
"$WORK/obj_dir/tb_lane_vpqc_montmul"

# --binary (a real, full behavioral simulation build) is used here instead
# of --lint-only (elaboration only, as in verilator_build_recipe.sh)
# because this recipe needs to actually run the testbench's clock/stimulus
# and check pe_resp_o.vinsn_done and the VRF's written-back content, not
# just confirm the module hierarchy connects. --timing is required (the
# original clocking/timing-control constructs, e.g. `always #5 clk =
# ~clk;`, are otherwise rejected by Verilator's default non-timing mode).
# The same -Wno-ENUMVALUE/-Wno-BLKANDNBLK/-Wno-BLKLOOPINIT suppressions as
# verilator_build_recipe.sh apply for the same reasons (see that file);
# none of them affect the PQC-path code this recipe actually exercises at
# runtime.
