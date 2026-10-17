# Kyber / ML-KEM-768 integration into Ara (RISC-V RVV)

This document describes how the verified Kyber / ML-KEM-768 (FIPS 203) RTL is
integrated into the Ara vector processor as a new per-lane functional unit,
`vfu_pqc`, driven by 29 custom `VPQC_*` vector opcodes. With these, the full
KeyGen / Encaps / Decaps flow runs as a straight-line sequence of vector
instructions on the real `lane.sv` datapath.

## Overview

`vfu_pqc` sits in the lane datapath alongside the ALU (`valu.sv`) and the
multiplier/FPU (`vmfpu.sv`) and shares their interface shape: it receives one
decoded vector instruction from the lane sequencer, reads its source operands
from the `PqcA`/`PqcB` operand queues, and writes results back through the VRF
write port. All Kyber arithmetic lives in the verified primitive blocks under
`hardware/src/pqc/*.v`; `vfu_pqc` feeds them operands from the VRF, runs the
selected block, and writes the outputs back.

## Package and datapath changes

| File | Change |
|------|--------|
| `hardware/include/ara_pkg.sv` | `NrVFUs` 7 → 8 with `VFU_Pqc` at index 2 of `vfu_e`; `NrOperandQueues` 9 → 11 with `PqcA`/`PqcB`; `PqcInsnQueueDepth = 4`; 29 `VPQC_*` entries added to `ara_op_e`; `pqc_uses_vs1()` helper. |
| `hardware/src/ara_sequencer.sv` | `InsnQueueDepth[NrVFUs]` extended to 8 entries with `PqcInsnQueueDepth` at index 2; `pqc_vinsn_done_i` input and `insn_queue_done[VFU_Pqc]` wiring. |
| `hardware/src/lane/operand_requester.sv` | `VFU_Pqc` added to the per-bank default-clear loop; `pqc_result_*` write-back port group; `NrGlobalMasters` 5 → 6. |
| `hardware/src/lane/vector_fus_stage.sv` | Instantiates `vfu_pqc`, passing the real `VLEN` so VRF destination addresses are computed correctly. |
| `hardware/src/lane/lane.sv`, `lane_sequencer.sv`, `operand_queues_stage.sv` | Thread the `PqcA`/`PqcB` operand queues and the `pqc_*` result signals through the lane hierarchy. |
| `hardware/src/ara.sv` | Propagates `pqc_vinsn_done` to the top-level scoreboard. |
| `Bender.yml` | Registers the 26 `hardware/src/pqc/*.v` primitives (Level 0) and `vfu_pqc.sv` (Level 2). |

## The `vfu_pqc` functional unit

`vfu_pqc` is a table-driven gather → compute → scatter engine. Each opcode
names, via the `n_in()` / `n_out()` tables, how many 64-bit words to gather
from the VRF and how many to scatter back. Two operand classes exist because
their arithmetic differs:

- **Elementwise** (`VPQC_MONTMUL`, `VPQC_BARRETT`): four 16-bit Z_q
  coefficients packed per 64-bit element, processed like an ALU op.
- **Gather / compute / scatter** (every other opcode): the op gathers a fixed
  number of consecutive words, runs one whole-block primitive — Keccak-f1600
  consumes all 25 state lanes at once, CBD consumes a full 128-byte PRF block —
  and scatters the result words back.

Two-operand ops (`pqc_uses_vs1()`: `MONTMUL`, `POLYMUL`, `PADD`, `PSUB`,
`BASEMUL_ACC`, `CTVERIFY`, `CMOV`) read a second operand from `vs1` → `PqcB` in
lock-step with `vs2` → `PqcA`.

## The 29 VPQC opcodes

```
MONTMUL  BARRETT  KECCAKPERM  CBD2  POLYMUL
SHA3_512_33  SHA3_512_64  SHA3_256_PK  SHAKE128_XOF  SHAKE256_PRF  SHAKE256_RK
NTT  INVNTT  REDUCE  TOMONT  PADD  PSUB  BASEMUL_ACC  REJ
TOBYTES  FROMBYTES  PVCOMP  PVDECOMP  PCOMP  PDECOMP  FROMMSG  TOMSG
CTVERIFY  CMOV
```

## ML-KEM-768 as a vector program

Each stage is a straight-line sequence of `VPQC_*` instructions; the round trip
closes on hardware (Encaps consumes KeyGen's `pk`, Decaps consumes the lane's
own `sk` and `ct`):

- **KeyGen** (`d‖z → pk, sk`): `SHA3_512_33` (G) → sample Â (`SHAKE128_XOF` +
  `REJ`) → sample s,e (`SHAKE256_PRF` + `CBD2`) → `NTT`/`REDUCE` → t̂ = Âŝ+ê
  (`BASEMUL_ACC`/`TOMONT`/`PADD`/`REDUCE`) → serialize (`TOBYTES`,
  `SHA3_256_PK` for H(pk)).
- **Encaps** (`pk, m → ct, ss`): `SHA3_256_PK` + `SHA3_512_64` (G(m‖H(pk))) →
  IND-CPA encrypt (`FROMBYTES`, `FROMMSG`, sample, `NTT`, `BASEMUL_ACC`,
  `INVNTT`, `PADD`, `REDUCE`) → compress (`PVCOMP`, `PCOMP`).
- **Decaps** (`sk, ct → ss`): `FROMBYTES` + `PVDECOMP`/`PDECOMP` → m′ = v − ŝᵀ·NTT(b)
  (`NTT`/`BASEMUL_ACC`/`INVNTT`/`PSUB`) → `TOMSG` → re-encrypt → `CTVERIFY` →
  `SHAKE256_RK` (reject key) → `CMOV` (constant-time select).

## Primitive blocks

`hardware/src/pqc/` holds the 26 verified Verilog primitives: `keccak_f1600`,
`keccak_sponge`, `ntt_fwd`, `ntt_inv`, `montgomery_reduce`, `barrett_fixed`,
`poly_cbd_eta2`, `rej_uniform`(+`_parallel`), `poly_basemul_montgomery`,
`polyvec_basemul_acc`, `poly_add`, `poly_sub`, `poly_tomont`,
`poly_barrett_pass`, `kyber_poly_mul_top`, `poly_compress`/`poly_decompress`,
`polyvec_compress`/`polyvec_decompress`, `polyvec_tobytes`/`polyvec_frombytes`,
`poly_frommsg`/`poly_tomsg`, `ct_verify`, `cmov_bytes`.

## Testing

Testbenches live in `hardware/tb/pqc/`; `run_lane_sim.sh` builds and runs the
lane-level benches against the real `lane.sv` under Verilator.

- `tb_lane_vpqc_montmul.sv` — `VPQC_MONTMUL` on the real lane.
- `tb_lane_vpqc_pqc_full.sv` — `VPQC_BARRETT`/`KECCAKPERM`/`CBD2`/`POLYMUL` on the real lane.
- `tb_lane_kem_program.sv` — full KeyGen/Encaps/Decaps as `VPQC_*` sequences on the real lane, byte-exact against a reference, including two tampered-ciphertext implicit-rejection checks. Takes `+vec=<vector file>`.

The standalone Kyber RTL and primitive-block benches live under
`kyber_kem_hardware/kyber_package/` with Icarus runner scripts
(`run_legacy_block_tests.sh`, `run_kem_top_tests.sh`).

### NIST KAT

`kyber_kem_hardware/kyber_package/scripts/gen_nist_kat_100.py` generates the 100
NIST Known-Answer-Test vectors for ML-KEM-768 using the NIST AES-256 CTR-DRBG
(SP 800-90A, no derivation function) and the `kyber-py` FIPS 203 reference,
writing them to `vectors/vecs_kemtop_nist/`. The vectors run through both the
standalone RTL (`tb_kem_fullloop`, Icarus) and the real lane
(`tb_lane_kem_program`, Verilator).

## Results

| Suite | Tool | Result |
|-------|------|--------|
| Primitive block tests | Icarus | 28 / 28 |
| KEM top-level tests (6 vectors) | Icarus | 24 / 24 |
| NIST KAT 100 — standalone RTL | Icarus | 100 / 100 |
| Lane op tests (5 ops) | Verilator, real `lane.sv` | pass, bit-exact |
| NIST KAT 100 — real lane (3-stage) | Verilator, real `lane.sv` | 100 / 100 |
| Ara riscv-tests regression | Verilator | 272 / 272 (no regressions) |

## Scope

The entropy source is external: the 32-byte seeds (`d`, `z`, `m`) are inputs to
the hardware, as in the ML-KEM specification. A deployed device supplies them
from a physical TRNG, which is out of scope for this RTL.
