#!/usr/bin/env bash
# Runs the per-block testbenches (testbench/tb_*_real.sv etc.) with the working
# directory they expect (vectors/, or vectors/vecs_poly_mul for the poly-mul
# top). Flags any run that printed a $fopen/$fscanf error, since those make
# comparisons vacuous (X !== X is false). Skips the very slow monolithic
# tb_kem_decaps_real (superseded by tb_kem_decaps_partA/partB and tb_kem_decaps_top).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; W="$(mktemp -d)"; bad=0
for tb in "$ROOT"/testbench/tb_*.sv; do
  n=$(basename "$tb" .sv)
  case "$n" in tb_kem_keygen_top|tb_kem_encaps_top|tb_kem_decaps_top|tb_kem_fullloop|tb_kem_decaps_real) continue;; esac
  iverilog -g2012 -o "$W/$n.vvp" "$ROOT"/verilog/*.v "$tb" || { echo "COMPILE FAIL $n"; bad=1; continue; }
  d="$ROOT/vectors"; [ "$n" = tb_kyber_poly_mul_top ] && d="$ROOT/vectors/vecs_poly_mul"
  out=$(cd "$d" && timeout 600 vvp "$W/$n.vvp" 2>&1)
  if echo "$out" | grep -q "invalid file descriptor"; then echo "VACUOUS (file not found) $n"; bad=1
  elif echo "$out" | grep "RESULT" | grep -q "FAIL"; then echo "FAIL  $n"; bad=1
  elif echo "$out" | grep -q "RESULT"; then echo "PASS  $n"
  else echo "NO RESULT $n"; bad=1; fi
done
exit $bad
