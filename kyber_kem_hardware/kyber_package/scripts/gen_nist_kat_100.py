#!/usr/bin/env python3
"""
Generate 100 NIST KAT vectors for ML-KEM-768 (FIPS 203) using the official
NIST AES-256 CTR-DRBG (no derivation function), matching the KAT process
from the NIST PQC standardization submission.

Output: vectors/vecs_kemtop/kat_vec_{count}.txt (count = 0..99)
Each file has the same COINS/M/PK/SK/CT/SS/SSDEC/CTBAD/SSBAD/CTBAD2/SSBAD2
format as the existing kem_vec_N.txt files (bytes reversed for Verilog $fscanf).

Requires: pip install kyber-py pycryptodome
"""

import os, struct, sys
from Crypto.Cipher import AES
from kyber_py.ml_kem import ML_KEM_768 as K

# ── NIST AES-256 CTR-DRBG (no DF) ─────────────────────────────────────────

class NIST_CTR_DRBG:
    """AES-256 CTR-DRBG without derivation function (NIST SP 800-90A)."""

    def __init__(self):
        self.key = b'\x00' * 32
        self.v   = b'\x00' * 16  # 128-bit counter

    def _inc_v(self):
        v = int.from_bytes(self.v, 'big')
        v = (v + 1) & ((1 << 128) - 1)
        self.v = v.to_bytes(16, 'big')

    def _update(self, provided_data: bytes | None = None):
        """CTR_DRBG_Update — absorbs 48 bytes of provided_data (or zeros)."""
        temp = b''
        while len(temp) < 48:
            self._inc_v()
            temp += AES.new(self.key, AES.MODE_ECB).encrypt(self.v)
        temp = temp[:48]
        if provided_data:
            temp = bytes(a ^ b for a, b in zip(temp, provided_data))
        self.key = temp[:32]
        self.v   = temp[32:48]

    def instantiate(self, entropy_input: bytes):
        """Instantiate from 48-byte entropy input."""
        assert len(entropy_input) == 48
        self.key = b'\x00' * 32
        self.v   = b'\x00' * 16
        self._update(entropy_input)

    def generate(self, num_bytes: int) -> bytes:
        """Generate num_bytes of pseudorandom output, then update state."""
        out = b''
        while len(out) < num_bytes:
            self._inc_v()
            out += AES.new(self.key, AES.MODE_ECB).encrypt(self.v)
        self._update()        # reseed with null
        return out[:num_bytes]


# ── vector helpers ─────────────────────────────────────────────────────────

def rev_hex(b: bytes) -> str:
    """Reverse byte order so Verilog $fscanf('%h') places byte[i] at bits[8*i +: 8]."""
    return b[::-1].hex()

def write_vec(path: str, coins: bytes, m: bytes,
              pk: bytes, sk: bytes, ct: bytes, ss: bytes, ss2: bytes,
              ct_bad: bytes, ss_bad: bytes, ct_bad2: bytes, ss_bad2: bytes):
    with open(path, 'w') as f:
        f.write(f"COINS {rev_hex(coins)}\n")
        f.write(f"M {rev_hex(m)}\n")
        f.write(f"PK {rev_hex(pk)}\n")
        f.write(f"SK {rev_hex(sk)}\n")
        f.write(f"CT {rev_hex(ct)}\n")
        f.write(f"SS {rev_hex(ss)}\n")
        f.write(f"SSDEC {rev_hex(ss2)}\n")
        f.write(f"CTBAD {rev_hex(ct_bad)}\n")
        f.write(f"SSBAD {rev_hex(ss_bad)}\n")
        f.write(f"CTBAD2 {rev_hex(ct_bad2)}\n")
        f.write(f"SSBAD2 {rev_hex(ss_bad2)}\n")


# ── main ───────────────────────────────────────────────────────────────────

def main():
    root   = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    outdir = os.path.join(root, "vectors", "vecs_kemtop_nist")
    os.makedirs(outdir, exist_ok=True)

    n = int(sys.argv[1]) if len(sys.argv) > 1 else 100

    # Outer DRBG: initial seed = [0,1,2,...,47] (NIST standard PQC KAT initial seed)
    outer = NIST_CTR_DRBG()
    outer.instantiate(bytes(range(48)))

    for count in range(n):
        # Inner seed: 48 bytes from outer DRBG
        entropy_input = outer.generate(48)

        # Inner DRBG: generates the keying material for this test case
        inner = NIST_CTR_DRBG()
        inner.instantiate(entropy_input)

        coins = inner.generate(64)   # d (32B) || z (32B)
        m     = inner.generate(32)   # encaps randomness

        d, z = coins[:32], coins[32:]

        # ML-KEM-768 operations (FIPS 203 internal APIs for deterministic testing)
        pk, sk = K._keygen_internal(d, z)
        ss,  ct = K._encaps_internal(pk, m)
        ss2     = K.decaps(sk, ct)

        # Tampered ciphertexts for implicit-rejection check
        ct_bad  = bytearray(ct); ct_bad[100]  ^= 0x01; ct_bad  = bytes(ct_bad)
        ct_bad2 = bytearray(ct); ct_bad2[500] ^= 0x80; ct_bad2 = bytes(ct_bad2)
        ss_bad  = K.decaps(sk, ct_bad)
        ss_bad2 = K.decaps(sk, ct_bad2)

        assert ss == ss2, f"KEM correctness failure at count={count}"

        path = os.path.join(outdir, f"kat_vec_{count}.txt")
        write_vec(path, coins, m, pk, sk, ct, ss, ss2, ct_bad, ss_bad, ct_bad2, ss_bad2)

        if (count + 1) % 10 == 0:
            print(f"  {count+1}/{n} vectors written")

    print(f"Wrote {n} NIST KAT vectors to {outdir}")


if __name__ == "__main__":
    main()
