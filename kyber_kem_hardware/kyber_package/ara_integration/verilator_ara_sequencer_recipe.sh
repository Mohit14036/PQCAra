#!/usr/bin/env bash
# verilator_ara_sequencer_recipe.sh -- elaborates the real, unmodified
# (except for this session's pqc_vinsn_done_i / insn_queue_done[VFU_Pqc]
# addition) hardware/src/ara_sequencer.sv standalone under Verilator.
#
# ara_sequencer.sv is a real dependency of ara.sv (the full chip top
# level), which is out of scope to elaborate in this session (it pulls in
# vlsu/sldu/masku/ara_dispatcher -- see ARA_INTEGRATION.md's "remaining
# scope"). This instead elaborates ara_sequencer.sv on its own, using
# ara_sequencer_elab_harness.sv (NOT part of the design) to supply the
# same pe_req_t/pe_resp_t/ara_req_t/ara_resp_t/exception_t struct types
# the real ara.sv builds for it -- pe_req_t/pe_resp_t via the real,
# unmodified `hardware/include/ara/ara_typedef.svh`, and ara_req_t/
# ara_resp_t copied verbatim from ara.sv's own local typedef block
# (lines 85-174 there), because ara_sequencer.sv's body reads specific
# fields off both that a placeholder struct shape wouldn't have.
#
# This exists specifically to prove the new pqc_vinsn_done_i port and
# insn_queue_done[VFU_Pqc] assignment (added this session -- see
# ARA_INTEGRATION.md's "Threading pqc_vinsn_done to the scoreboard"
# section) are structurally sound: without insn_queue_done[VFU_Pqc]
# being driven, VPQC_* instructions would be counted into the sequencer's
# per-VFU instruction queue but never counted back out, eventually
# blocking all further PQC issue -- a real, previously-unwired gap this
# fixes.
set -euo pipefail

WORK=/tmp/verilator_work
ARA=/tmp/ara_src
CC=/tmp/common_cells_src
FPU=/tmp/cvfpu_src
DIVSQRT=/tmp/fpu_div_sqrt_mvp_src
PQC=/tmp/kyber_package/ara_integration

verilator --lint-only -Wno-fatal -Wno-ENUMVALUE -Wno-BLKANDNBLK -Wno-BLKLOOPINIT --timing -sv --error-limit 200 \
  +incdir+"$ARA/hardware/include" \
  +incdir+"$ARA/hardware/include/ara" \
  +incdir+"$CC/include" \
  -y "$CC/src" \
  -y "$CC/src/deprecated" \
  "$PQC/stub_riscv_axi_pkg.sv" \
  "$ARA/hardware/include/rvv_pkg.sv" \
  "$CC/src/cf_math_pkg.sv" \
  "$DIVSQRT/hdl/defs_div_sqrt_mvp.sv" \
  "$FPU/src/fpnew_pkg.sv" \
  "$ARA/hardware/include/ara_pkg.sv" \
  "$ARA/hardware/src/ara_sequencer.sv" \
  "$PQC/ara_sequencer_elab_harness.sv" \
  --top-module ara_sequencer_elab_harness
