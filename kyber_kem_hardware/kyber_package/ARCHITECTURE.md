# Kyber-768 (ML-KEM) Hardware — Architecture

This describes the actual module hierarchy and data flow of the RTL in this
package, as verified — not an idealized textbook diagram. Every block below
is a real Verilog module, checked bit-exact against the real, unmodified
`pq-crystals/kyber` reference C code (see `ref_c/`) using real captured
intermediate values (see `vectors/`).

Parameters: KYBER_K=3, ETA1=ETA2=2, Q=3329, N=256 (Kyber-768 / ML-KEM-768).

## 1. Primitive layer (shared, reused sequentially)

```
montgomery_reduce.v   Montgomery reduction (R=2^16), used by NTT/basemul
barrett_fixed.v        Barrett reduction, used after NTT and for final polys
keccak_f1600.v          24-round Keccak-f[1600] permutation core (one shared
                        instance; every hash/XOF/PRF below is a control
                        wrapper around this same core)
```

## 2. Hashing / sponge layer

```
keccak_sponge.v   generic absorb -> pad -> permute -> squeeze FSM around
                  keccak_f1600.v. Instantiated per call site with compile-
                  time RATE_BYTES / IN_LEN / OUT_LEN / PAD_BYTE (Kyber only
                  ever calls each site with a fixed length, so this is a
                  fixed-function accelerator shape, not a generic streaming
                  core):

    SHA3-256  (rate=136, pad=0x06)  -- hash_h:  H(pk), 1184B -> 32B
    SHA3-512  (rate=72,  pad=0x06)  -- hash_g:  33B seed-expand -> 64B
                                                 64B (m||H(pk)) -> kr(64B)
    SHAKE256  (rate=136, pad=0x1F)  -- prf:     33B (seed||nonce) -> 128B
                                     -- rkprf:   1120B (z||ct) -> 32B
    SHAKE128  (rate=168, pad=0x1F)  -- xof:     34B (seed||i||j) -> 504B+
```

## 3. Noise / matrix generation

```
poly_cbd_eta2.v       centered binomial sampler (eta=2): 128B PRF output
                        -> 256 signed coefficients in {-2..2}
rej_uniform_parallel.v +
rej_uniform.v          rejection-sampling compaction: XOF bytes -> up to
                        256 accepted coefficients (matrix entry a[i][j])
```

## 4. Number-theoretic transform

```
ntt_fwd.v   forward NTT (7 layers) + poly_barrett_pass.v reduce pass
            (poly_ntt() == ntt() + poly_reduce() in the reference --
            this was a real bug caught and fixed during verification)
ntt_inv.v   inverse NTT (Montgomery-domain output, no extra reduce needed)
```

## 5. Polynomial arithmetic

```
polyvec_basemul_acc.v   NTT-domain pointwise multiply-accumulate (K=3)
poly_add.v / poly_sub.v  256-lane add/subtract
poly_tomont.v            Montgomery-domain conversion
poly_barrett_pass.v      Barrett reduction pass
```

## 6. Compression / message coding (ciphertext, lossy)

```
poly_compress.v / poly_decompress.v        4-bit/coeff  (v component)
polyvec_compress.v / polyvec_decompress.v  10-bit/coeff (u component, K=3)
poly_tomsg.v / poly_frommsg.v              256-bit message <-> polynomial
```

## 7. Key serialization (wire format, full precision -- distinct from #6)

```
poly_tobytes.v                12-bit/coeff single polynomial -> bytes
polyvec_tobytes.v (K=3)        -> pack_sk() (1152B), pack_pk() (+32B seed = 1184B)
polyvec_frombytes.v (K=3)      inverse (unpack)
```

## 8. IND-CPA orchestration (FSMs chaining the above)

```
indcpa_keypair_arith.v   gen_a (rej_uniform x9) -> noise (CBD x6) -> NTT ->
                          basemul -> pkpv = A.s + e
indcpa_enc_arith.v        NTT(s') -> basemul (u rows + v) -> invNTT ->
                          add noise -> u,v
indcpa_dec_arith.v        NTT(u) -> basemul(sk,u) -> invNTT -> v - u.s -> mp
```

## 9. KEM / FO-transform wrapper

```
ct_verify.v     constant-time ciphertext compare (XOR-OR tree)
cmov_bytes.v    constant-time select (implicit-rejection cmov)
```
Encapsulation:  pk -> indcpa_enc_arith -> compress/pack -> ct
                (hash_g gives kr; kr[0:32] = ss directly -- no separate
                KDF step, unlike some textbook FO-transform diagrams)
Decapsulation:  sk,ct -> indcpa_dec_arith -> tomsg/frommsg -> re-encrypt
                (indcpa_enc_arith again) -> pack -> ct_verify -> cmov_bytes
                -> ss (real key on match, rkprf pseudorandom key on mismatch)

## Data-flow summary

```
                         +------------------+
   entropy (TRNG, ---->  | seed expansion   |  32B seed -> d,z,m (SHAKE256;
   NOT built here)       | (keccak_sponge)  |  expansion verified, entropy
                         +--------+---------+  source explicitly out of scope)
                                  |
        +-------------------------------------------------+
        |                    KeyGen                        |
        |  hash_g(d||K) -> rho,sigma                        |
        |  rho  -> SHAKE128 -> rej_uniform  -> matrix A      |
        |  sigma-> SHAKE256 -> poly_cbd_eta2 -> s, e         |
        |  indcpa_keypair_arith: NTT, basemul -> pkpv        |
        |  polyvec_tobytes -> pk (1184B), sk (2400B incl.    |
        |    H(pk) via SHA3-256, z)                          |
        +-------------------------------------------------+
                                  |  pk
                                  v
        +-------------------------------------------------+
        |                   Encaps(pk)                      |
        |  m (32B) -> hash_h(pk)=H(pk) [SHA3-256]            |
        |  hash_g(m||H(pk)) -> kr = K || coins  [SHA3-512]   |
        |  coins -> SHAKE256 -> poly_cbd_eta2 -> s',e1,e2    |
        |  indcpa_enc_arith -> u,v -> compress/pack -> ct     |
        |  ss = kr[0:32]                                     |
        +-------------------------------------------------+
                                  |  ct
                                  v
        +-------------------------------------------------+
        |                   Decaps(sk,ct)                   |
        |  indcpa_dec_arith(sk,ct) -> mp -> poly_tomsg -> m'  |
        |  hash_g(m'||H(pk)) -> kr' = K'||coins'              |
        |  re-encrypt (indcpa_enc_arith again) -> ct'         |
        |  ct_verify(ct,ct') -> fail                          |
        |  rkprf(z,ct) -> pseudorandom reject key             |
        |  cmov_bytes(reject_key, kr', !fail) -> ss            |
        +-------------------------------------------------+
```

## 10. End-to-end KEM top-levels (seed in, keys / ciphertext / shared secret out)

Added after the per-block work above. These chain the verified blocks, hashes
included, so no intermediate value is taken from a captured reference file:

```
kem_keygen_top   coins d||z (64 B)          -> pk (1184 B), sk (2400 B)
kem_encaps_top   pk (1184 B), m (32 B)      -> ct (1088 B), ss (32 B)
kem_decaps_top   sk (2400 B), ct (1088 B)   -> ss (32 B)   [accept AND implicit-reject paths]
kem_indcpa_enc_top  (shared by encaps and decaps' re-encryption)
```

Each top is one FSM sharing a single instance of every sub-block (one XOF
sponge + rej_uniform, one PRF sponge + CBD, one hash_g, etc.), using the same
SET / GO / WAIT sequencing per call. The hash steps (SHA3-256 H(pk), SHA3-512
G, SHAKE128 matrix XOF, SHAKE256 PRF and rkprf) are now in the chain.

Verification (`scripts/run_kem_top_tests.sh`, 4 testbenches x 6 vectors):
- `tb_kem_keygen_top`: coins -> pk and sk, byte-exact vs. reference.
- `tb_kem_encaps_top`: (pk, m) -> ct and ss, byte-exact.
- `tb_kem_decaps_top`: valid ct -> ss equals reference decaps AND the encaps ss
  (reject_o = 0); a ct tampered in the u-part and one tampered in the v-part
  each give the reference implicit-rejection key (reject_o = 1), distinct per ct.
- `tb_kem_fullloop`: RTL keygen -> RTL encaps -> RTL decaps chained directly
  (no reference data between stages); ss_dec == ss_enc, and everything also
  byte-exact vs. reference.
- Negative controls: corrupting a coin / message / expected-key byte in the
  vector file makes the corresponding testbench report FAIL.
- Vectors come from the pq-crystals ref (`ref_c/harness_kem.c`, derand APIs;
  regenerate with `scripts/gen_kem_vectors.sh`). They were also cross-checked
  against an independent pure-Python ML-KEM-768 (`kyber-py`, FIPS 203) in
  `scripts/crosscheck_fips203.py`: pk, sk, ct, ss, decaps and both
  implicit-rejection keys match for all 6 vectors. This is agreement with a
  second implementation, not the NIST ACVP/KAT files (not used here).

Notes and limits:
- Matrix sampling squeezes a fixed 5-block (840 B) SHAKE128 window instead of
  the reference's 3 blocks + on-demand extra blocks. Rejection sampling over a
  stream is prefix-consistent, so the first 256 accepted coefficients are
  identical; `a_fail_o` is raised if 840 B ever fail to yield 256 (probability
  ~1e-90, never observed).
- `reject_o` on the decaps top is a verification observable; a real device must
  not expose it. The compare/select blocks are constant-time at RTL level, but
  no gate-level or physical side-channel analysis has been done.
- The entropy source is still out of scope: coins and m are inputs.
- These tops are standalone RTL blocks. They are NOT yet driven through the Ara
  custom-instruction path (see ARA_INTEGRATION.md): that path currently covers
  the arithmetic ops (Keccak-f, CBD, polynomial multiply, Montgomery, Barrett)
  at lane level only.
- Still no synthesis, timing closure, or FPGA/ASIC numbers.

### Running the older per-block testbenches (working-directory trap)
The pre-existing `testbench/tb_*_real.sv` files open `vecs_*/...` by RELATIVE
path, so they must be run with the working directory set to `vectors/`
(compile with `iverilog -g2012 verilog/*.v testbench/tb_X.sv`, then
`cd vectors && vvp ...`; `tb_kyber_poly_mul_top` needs `vectors/vecs_poly_mul`).
Run from anywhere else, `$fopen` fails, inputs and expected values both stay X,
and `X !== X` is false, so several of them print a vacuous "match". The new
`tb_kem_*_top` / `tb_kem_fullloop` testbenches use `vectors/vecs_kemtop/...`
relative to the package root and are driven by `scripts/run_kem_top_tests.sh`.

## Explicitly out of scope

- Synthesis / place-and-route / timing closure / FPGA or ASIC bring-up
- Integration into the Ara/RVV pipeline as custom instructions or a
  memory-mapped coprocessor
- Physical entropy source (TRNG) -- coins and m are inputs; only the
  deterministic expansion downstream of them is built and verified
- Side-channel (power/timing) hardening validation at the gate level --
  the constant-time logic (`ct_verify`/`cmov_bytes`) matches the reference
  *functionally* on both branches, which is not the same as a physical
  leakage analysis

## 11. Verilator note and the Ara lane-level KEM program

Fifteen blocks previously assigned their working arrays with non-blocking assignments inside `for`
loops. Icarus simulates that correctly, but Verilator (with `-Wno-BLKLOOPINIT`) does not; those load
loops now use blocking assignments (IDLE-state only, same behaviour). The full Icarus regression
(`scripts/run_legacy_block_tests.sh`, `scripts/run_kem_top_tests.sh`) was re-run after the change and
passes. The same blocks are now instantiated inside `ara_integration/vfu_pqc.sv`, and the full KEM
runs as a vector-instruction program on the real Ara `lane.sv`
(`ara_integration/verilator_kem_program_recipe.sh`; see ARA_INTEGRATION.md).
