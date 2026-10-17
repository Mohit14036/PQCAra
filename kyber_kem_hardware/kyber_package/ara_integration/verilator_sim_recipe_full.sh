#!/usr/bin/env bash
set -euo pipefail
WORK=${WORK:-/tmp/verilator_work}
ARA=/tmp/ara_src
PQC=/tmp/kyber_package/ara_integration
cd "$WORK"
verilator --binary -Wno-fatal -Wno-ENUMVALUE -Wno-BLKANDNBLK -Wno-BLKLOOPINIT --timing -sv --error-limit 100 \
  -f filelist_sim.f \
  "$PQC/stub_riscv_axi_pkg.sv" stub_cva6_config_pkg.sv stub_serdiv.sv \
  "$ARA/hardware/include/rvv_pkg.sv" /tmp/common_cells_src/src/cf_math_pkg.sv \
  /tmp/fpu_div_sqrt_mvp_src/hdl/defs_div_sqrt_mvp.sv /tmp/cvfpu_src/src/fpnew_pkg.sv \
  "$ARA/hardware/include/ara_pkg.sv" /tmp/tech_cells_generic_src/src/rtl/tc_clk.sv \
  $(ls /tmp/kyber_package/verilog/*.v | grep -v /kem_ | tr '\n' ' ') \
  "$PQC/vfu_pqc.sv" "$ARA/hardware/src/lane/lane.sv" \
  tb_lane_vpqc_pqc_full.sv \
  --top-module tb_lane_vpqc_pqc_full -o tb_lane_vpqc_pqc_full
