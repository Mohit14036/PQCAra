#!/usr/bin/env bash
# Build and run a lane-level PQC testbench against this repo's real lane.sv.
# Usage: run_lane_sim.sh <tb_top> [--trace] [plusargs...]
#   tb_top: tb_lane_vpqc_montmul | tb_lane_vpqc_pqc_full | tb_lane_kem_program
# Build products go to $WORK (default /tmp/pqc_lane_sim/<tb_top>).
set -euo pipefail

TB=${1:?usage: run_lane_sim.sh <tb_top> [--trace] [plusargs...]}; shift
TRACE=()
if [ "${1:-}" = "--trace" ]; then TRACE=(--trace-fst -Wno-INSECURE); shift; fi

PQC=$(cd "$(dirname "$0")" && pwd)
ARA=$(cd "$PQC/../../.." && pwd)
DEPS=$ARA/hardware/deps
VERILATOR=${VERILATOR:-$ARA/install/verilator/bin/verilator}
WORK=${WORK:-/tmp/pqc_lane_sim/$TB}
mkdir -p "$WORK"

cat > "$WORK/filelist.f" << EOF
+incdir+$ARA/hardware/include
+incdir+$ARA/hardware/include/ara
+incdir+$DEPS/common_cells/include
-y $ARA/hardware/src/lane
-y $DEPS/common_cells/src
-y $DEPS/common_cells/src/deprecated
-y $DEPS/fpnew/src
-y $DEPS/tech_cells_generic/src/rtl
-y $DEPS/tech_cells_generic/src/deprecated
-y $DEPS/fpu_div_sqrt_mvp/hdl
EOF

# These rely on a file-scope `import defs_div_sqrt_mvp::*`, which does not take effect when
# Verilator pulls them in via -y auto-discovery, so list them explicitly after their package.
D=$DEPS/fpu_div_sqrt_mvp/hdl
DIVSQRT_SRCS=("$D/defs_div_sqrt_mvp.sv" "$D/iteration_div_sqrt_mvp.sv" "$D/control_mvp.sv"
  "$D/norm_div_sqrt_mvp.sv" "$D/preprocess_mvp.sv" "$D/nrbd_nrsc_mvp.sv" "$D/div_sqrt_top_mvp.sv")

# Rebuild only when sources are newer than the binary.
BIN=$WORK/obj/$TB
if [ ! -x "$BIN" ] || [ -n "$(find "$ARA/hardware/src" "$ARA/hardware/include" "$PQC" -newer "$BIN" -name '*.*v' -print -quit)" ]; then
  echo "building $TB ..."
  rm -rf "$WORK/obj"
  "$VERILATOR" --binary -Wno-fatal -Wno-ENUMVALUE -Wno-BLKANDNBLK -Wno-BLKLOOPINIT --timing -sv \
    --error-limit 100 -j "$(nproc)" "${TRACE[@]}" --Mdir "$WORK/obj" -f "$WORK/filelist.f" \
    "$PQC/stub_riscv_axi_pkg.sv" "$PQC/stub_cva6_config_pkg.sv" "$PQC/stub_serdiv.sv" \
    "$ARA/hardware/include/rvv_pkg.sv" "$DEPS/common_cells/src/cf_math_pkg.sv" \
    "${DIVSQRT_SRCS[@]}" "$DEPS/fpnew/src/fpnew_pkg.sv" \
    "$ARA/hardware/include/ara_pkg.sv" "$DEPS/tech_cells_generic/src/rtl/tc_clk.sv" \
    "$ARA"/hardware/src/pqc/*.v \
    "$ARA/hardware/src/lane/vfu_pqc.sv" "$ARA/hardware/src/lane/lane.sv" \
    "$PQC/$TB.sv" --top-module "$TB" -o "$TB" > "$WORK/build.log" 2>&1 \
    || { tail -40 "$WORK/build.log"; exit 1; }
fi

# Run from $WORK so any $dumpfile lands there; testbench plusargs are passed through.
cp "$PQC/poly_mul_ntt_real.txt" "$WORK/"
cd "$WORK" && "$BIN" "$@"
