# Kyber / ML-KEM-768 on Ara — how to run

This fork adds a post-quantum (Kyber / ML-KEM-768, FIPS 203) vector functional
unit, `vfu_pqc`, to the Ara RISC-V vector processor, with 29 custom `VPQC_*`
vector opcodes. The full KeyGen / Encaps / Decaps flow runs as vector
instructions on the real `lane.sv` datapath.

For the architecture and data-flow overview, open
[`MLKEM768_Ara_Architecture.html`](MLKEM768_Ara_Architecture.html) in a browser,
or read [`hardware/tb/pqc/ARA_INTEGRATION.md`](hardware/tb/pqc/ARA_INTEGRATION.md).

## Prerequisites

| Tool | Used for | Notes |
|------|----------|-------|
| Icarus Verilog (`iverilog` ≥ 11, `-g2012`) | standalone block / KEM / NIST-KAT tests | `sudo apt install iverilog` |
| Verilator | lane-level simulation of the real `lane.sv` | expected at `install/verilator/bin/verilator` (build with `make verilator` from the repo root, or point `$VERILATOR` at your own) |
| Python 3 + `kyber-py` + `pycryptodome` | generating NIST KAT vectors | `pip install kyber-py pycryptodome` |
| RISC-V GCC toolchain | full-chip `riscv-tests` regression only | `make toolchain-gcc` from the repo root |

All commands below are run from the repository root.

## Layout

```
hardware/src/lane/vfu_pqc.sv          the PQC vector functional unit
hardware/src/pqc/*.v                  26 verified Kyber primitive blocks
hardware/tb/pqc/                      lane-level testbenches + run_lane_sim.sh
kyber_kem_hardware/kyber_package/     standalone Kyber RTL, reference, vectors, scripts
```

## 1. Standalone primitive block tests (Icarus)

Behavioral checks of each primitive block (Keccak, NTT, Montgomery, …) against
a reference:

```bash
bash kyber_kem_hardware/kyber_package/scripts/run_legacy_block_tests.sh
```

## 2. KEM top-level tests (Icarus)

Standalone keygen / encaps / decaps / full-loop RTL over the bundled vectors:

```bash
bash kyber_kem_hardware/kyber_package/scripts/run_kem_top_tests.sh
```

## 3. Generate the 100 NIST KAT vectors

Uses the NIST AES-256 CTR-DRBG and the `kyber-py` FIPS 203 reference to write
`vectors/vecs_kemtop_nist/kat_vec_{0..99}.txt`:

```bash
python3 kyber_kem_hardware/kyber_package/scripts/gen_nist_kat_100.py 100
```

(100 pre-generated vectors are already included in the repo.)

## 4. NIST KAT — standalone RTL (Icarus)

Run all 100 vectors through the chained keygen→encaps→decaps RTL:

```bash
cd kyber_kem_hardware/kyber_package
W=$(mktemp -d)
iverilog -g2012 -o "$W/fullloop.vvp" verilog/*.v testbench/tb_kem_fullloop.sv
for v in vectors/vecs_kemtop_nist/kat_vec_*.txt; do
  vvp "$W/fullloop.vvp" +vec="$v" | grep RESULT
done
cd -
```

## 5. Lane op tests on the real `lane.sv` (Verilator)

`run_lane_sim.sh <testbench> [--trace] [+plusargs]` builds the real lane
hierarchy (first run compiles; later runs are incremental) and simulates it:

```bash
# single-op datapath checks
bash hardware/tb/pqc/run_lane_sim.sh tb_lane_vpqc_montmul
bash hardware/tb/pqc/run_lane_sim.sh tb_lane_vpqc_pqc_full
```

## 6. Full ML-KEM-768 on the real `lane.sv` (Verilator)

Runs KeyGen → Encaps → Decaps (plus two tampered-ciphertext rejection checks)
as `VPQC_*` vector-instruction sequences on the real lane, byte-exact vs the
reference. Pass a vector with `+vec=`:

```bash
bash hardware/tb/pqc/run_lane_sim.sh tb_lane_kem_program \
  "+vec=$PWD/kyber_kem_hardware/kyber_package/vectors/vecs_kemtop_nist/kat_vec_0.txt"
```

### All 100 NIST KAT vectors on the real lane

Build once, then run the vectors in parallel:

```bash
NIST=$PWD/kyber_kem_hardware/kyber_package/vectors/vecs_kemtop_nist
bash hardware/tb/pqc/run_lane_sim.sh tb_lane_kem_program "+vec=$NIST/kat_vec_0.txt" >/dev/null
BIN=/tmp/pqc_lane_sim/tb_lane_kem_program/obj/tb_lane_kem_program
seq 0 99 | xargs -P"$(nproc)" -I{} sh -c \
  "\"$BIN\" \"+vec=$NIST/kat_vec_{}.txt\" | grep -q 'RESULT:.*PASS' && echo 'PASS {}' || echo 'FAIL {}'"
```

## 7. Full-chip Ara regression (optional)

Confirms the integration introduces no regressions in the base RVV test suite
(requires the RISC-V GCC toolchain; takes a while):

```bash
cd hardware
make verilate
make riscv_tests_simv
cd -
```

## Expected results

| Suite | Tool | Result |
|-------|------|--------|
| Primitive block tests | Icarus | 28 / 28 PASS |
| KEM top-level tests (6 vectors) | Icarus | 24 / 24 PASS |
| NIST KAT 100 — standalone RTL | Icarus | 100 / 100 PASS |
| Lane op tests (5 ops) | Verilator, real `lane.sv` | PASS, bit-exact |
| NIST KAT 100 — real lane (3-stage) | Verilator, real `lane.sv` | 100 / 100 PASS |
| Ara `riscv-tests` regression | Verilator | 272 / 272 PASS |
