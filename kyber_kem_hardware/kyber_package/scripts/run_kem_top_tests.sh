#!/usr/bin/env bash
# Builds and runs the three end-to-end KEM top-level testbenches and the
# chained full-loop testbench over all vectors in vectors/vecs_kemtop/.
# Requires: iverilog (-g2012). Run from anywhere.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
W="$(mktemp -d)"; fail=0
for tb in keygen_top encaps_top decaps_top fullloop; do
  iverilog -g2012 -o "$W/$tb.vvp" verilog/*.v "testbench/tb_kem_$tb.sv" || { echo "COMPILE FAIL $tb"; exit 2; }
  for v in vectors/vecs_kemtop/kem_vec_*.txt; do
    r=$(vvp "$W/$tb.vvp" +vec="$v" | grep RESULT | head -1)
    case "$r" in *PASS*) echo "PASS  $tb  $(basename $v)";; *) echo "FAIL  $tb  $(basename $v): $r"; fail=1;; esac
  done
done
exit $fail
