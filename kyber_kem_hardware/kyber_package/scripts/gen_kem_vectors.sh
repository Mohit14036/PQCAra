#!/usr/bin/env bash
# Regenerates vectors/vecs_kemtop/kem_vec_N.txt from the pq-crystals reference
# (deterministic derand APIs). Each line is "TAG hex" with the bytes REVERSED so
# that Verilog's $fscanf("%h") puts byte i at bits [8*i +: 8].
# Usage: scripts/gen_kem_vectors.sh [N=6]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; N="${1:-6}"
W="$(mktemp -d)"; mkdir -p "$W/ref"
cp "$ROOT"/ref_c/ref/*.c "$ROOT"/ref_c/ref/*.h "$W/ref/"; cp "$ROOT/ref_c/harness_kem.c" "$W/"
( cd "$W" && gcc -O1 -DKYBER_K=3 -I. -o harness_kem harness_kem.c ref/kem.c ref/indcpa.c ref/polyvec.c \
    ref/poly.c ref/ntt.c ref/cbd.c ref/reduce.c ref/verify.c ref/fips202.c ref/symmetric-shake.c ref/randombytes.c )
mkdir -p "$ROOT/vectors/vecs_kemtop"
for s in $(seq 1 "$N"); do
  "$W/harness_kem" "$s" | python3 -c '
import sys
for line in sys.stdin:
    tag, h = line.split()
    print(tag, bytes.fromhex(h)[::-1].hex())' > "$ROOT/vectors/vecs_kemtop/kem_vec_$s.txt"
done
echo "wrote $N vectors to $ROOT/vectors/vecs_kemtop"
