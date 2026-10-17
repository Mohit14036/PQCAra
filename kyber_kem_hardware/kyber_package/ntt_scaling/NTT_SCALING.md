# Scaling the uploaded NTT/NWC design to real Kyber parameters (Q=3329, N=256)

This documents what happened to the uploaded toy NTT/negative-wrapped-
convolution design (`toy_upload/`: `modq_arith.v`, `butterfly_ct.v`,
`ntt_engine.v`, `intt_engine.v`, `nwc_top.v`, at Q=17, N=8) when scaled to
Kyber's real parameters, and why the result is not a literal 1:1 port.

## Step 1 — verifying the upload as given

Both of the uploaded testbenches were actually run (Icarus Verilog), not
just read:

```
*** NTT ENGINE TEST PASSED ***
*** NEGATIVE WRAPPED CONVOLUTION TEST PASSED ***
```

The NWC result was also independently cross-checked against brute-force
polynomial multiplication mod `(X^8+1)` mod 17 in Python (not just
compared to the upload's own `nwc_expected.mem` — an independent
recomputation): it matches exactly. So the upload was real, working RTL
before any scaling began.

## Step 2 — why this can't be scaled up as a literal port

The toy's `nwc_top.v` computes `c(x) = a(x)*b(x) mod (X^N+1) mod Q` as:
twist by `psi^i` → complete N-point NTT of both operands → pointwise
scalar multiply → complete N-point inverse NTT → untwist by `psi^-i *
N^-1`. That structure requires a primitive `2N`-th root of unity mod `Q`,
i.e. `2N | (Q-1)`. For the toy: `Q=17`, `N=8`, `2N=16`, and `Q-1=16` — so
`16 | 16`, exactly divisible, and a complete negacyclic NTT exists.

For real Kyber, `Q=3329` and `N=256`, so `2N=512`. But `Q-1 = 3328 = 2^8 ×
13`, and `3328 / 512 = 6.5` — **not an integer**. `512` does not divide
`3328`, so **no primitive 512th root of unity exists mod 3329, and a
complete 256-point negacyclic NTT does not exist for Kyber's parameters.**
This is a real mathematical fact about Kyber's chosen modulus, not an
implementation limitation — it's the actual reason the real Kyber
specification uses an *incomplete* NTT (only 7 of the 8 possible radix-2
layers, using a primitive **256th** root of unity, which does exist since
`256 | 3328`) plus a different pointwise step: multiplying pairs of
degree-1 "leaves" as elements of `Fq[X]/(X^2-zeta)` (`basemul`), not a
plain scalar product. So the toy's `nwc_top.v` architecture — twist / full
NTT / scalar pointwise-multiply / full INTT / untwist — cannot be
re-parameterized to Q=3329, N=256 and still compute the right answer; the
algorithm itself has to change to Kyber's real one.

## Step 3 — what already existed, what's new

This project already had real, Kyber-scale (Q=3329, N=256), Montgomery-
domain forward/inverse NTT engines (`../verilog/ntt_fwd.v`,
`../verilog/ntt_inv.v`), each independently verified bit-exact against a
real `ref/ntt.c` execution from an earlier stage of this project. Re-run
today to confirm they still pass:

```
RESULT: ntt_fwd.v matches real ntt() exactly on all 256 coefficients
RESULT: ntt_inv.v matches real invntt() exactly on all 256 coefficients
```

There was also an existing Montgomery-domain pointwise-multiply-and-
accumulate module for the K=3 matrix-vector product
(`../verilog/polyvec_basemul_acc.v`), but nothing chaining a single
NTT → pointwise-multiply → INTT pipeline end-to-end, which is the direct
Kyber-scale counterpart of the toy's `nwc_top.v`. That's what's new here:

- **`../verilog/poly_basemul_montgomery.v`** — a single-pair (not K=3
  accumulated) Montgomery `basemul`, extracted from the already-verified
  per-group datapath inside `polyvec_basemul_acc.v`, matching
  `ref/poly.c`'s `poly_basemul_montgomery()` exactly.
- **`../verilog/kyber_poly_mul_top.v`** — the top-level orchestrator, in
  the same spirit as the uploaded `nwc_top.v` (one FSM sequencing shared
  sub-engines through NTT → pointwise-multiply → INTT), but implementing
  Kyber's real pipeline: `poly_ntt(a)` (NTT + barrett-reduce) →
  `poly_ntt(b)` → `poly_basemul_montgomery` → `poly_invntt_tomont`.

## Step 4 — verification of the new, real-scale pipeline

1. **A real reference vector**, captured by actually compiling and
   running Kyber's real C source (`../ref_c/harness_poly_mul.c`, linked
   against the unmodified `ref/poly.c`, `ref/ntt.c`, `ref/reduce.c`,
   etc. already in this project): two deterministic test polynomials are
   multiplied via `poly_ntt` → `poly_basemul_montgomery` →
   `poly_invntt_tomont`, with every intermediate stage dumped to
   `../vectors/vecs_poly_mul/poly_mul_ntt_real.txt`.

2. **Independent cross-check**, done *before* any RTL for this stage was
   written: the same two input polynomials were multiplied via plain
   brute-force schoolbook negacyclic convolution mod `(X^256+1)` mod 3329
   in Python — with no NTT, no Montgomery arithmetic, nothing shared with
   the C or RTL implementation — and compared to the C harness's output.
   **They match exactly.** This is the real-scale equivalent of the
   brute-force check done on the toy in Step 1, and it's the strongest
   evidence available that Kyber's NTT-domain multiplication pipeline
   really does compute polynomial multiplication mod `(X^256+1)` mod
   `3329`, independent of any single implementation of it.

3. **RTL verification**: `kyber_poly_mul_top.v`, driven by
   `../testbench/tb_kyber_poly_mul_top.sv` with the real captured
   `a`/`b` inputs, produces the real captured `c` output bit-exact on all
   256 coefficients, first run, no fixes needed:

   ```
   RESULT: kyber_poly_mul_top.v matches the real poly_ntt->
   poly_basemul_montgomery->poly_invntt_tomont pipeline exactly on all
   256 coefficients (real Kyber-768 Q=3329, N=256), which was
   independently cross-checked against brute-force negacyclic
   convolution.
   ```

## Bottom line

The uploaded toy design was real and verified at its own scale (Q=17).
It could not be re-parameterized 1:1 to Kyber's real Q=3329/N=256 because
Kyber's modulus does not support a complete negacyclic NTT at that
length — that's a property of the number, not a coding gap. What *is*
now in this repo, verified the same way (bit-exact against real reference
execution, plus an independent brute-force cross-check), is the
mathematically correct Kyber-scale counterpart: a single top-level
orchestrator (`kyber_poly_mul_top.v`) that actually multiplies two
degree-256 polynomials mod `(X^256+1)` mod `3329`, built from the same
kind of shared, FSM-sequenced sub-engines the toy used, reusing every
already-verified arithmetic core in this project (`montgomery_reduce.v`,
`barrett_fixed.v`, `ntt_fwd.v`, `ntt_inv.v`) rather than duplicating them.

**Update**: this module is now wired into the Ara VFU integration as a new
op, `VPQC_POLYMUL` — see `../ARA_INTEGRATION.md` for the full wiring (enum/
decode changes, the `vfu_pqc.sv` FSM extension that gathers two full
256-coefficient polynomial operands, instantiates this module, and
scatters its result) and for the real behavioral (not just elaboration)
verification that followed, which caught and fixed two genuine bugs in
the shared gather/scatter FSM shape. Kyber's real polynomial
multiplication now has a path onto the RVV VFU alongside the sub-primitives
`VPQC_MONTMUL`/`VPQC_BARRETT`/`VPQC_KECCAKPERM`/`VPQC_CBD2` that were
already wired in.
