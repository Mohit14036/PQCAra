#!/usr/bin/env python3
"""Cross-check the C-reference vectors against an INDEPENDENT pure-Python
ML-KEM-768 (FIPS 203) implementation (pip install kyber-py). Confirms that the
vectors the RTL is tested against are standard ML-KEM-768 values, not just
whatever the C reference happens to output."""
import subprocess, sys, os
from kyber_py.ml_kem import ML_KEM_768 as K
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
exe = sys.argv[1] if len(sys.argv) > 1 else None
assert exe, "usage: crosscheck_fips203.py /path/to/harness_kem [N]"
n = int(sys.argv[2]) if len(sys.argv) > 2 else 6
ok = True
for s in range(1, n + 1):
    out = subprocess.run([exe, str(s)], capture_output=True, text=True).stdout
    v = {l.split()[0]: bytes.fromhex(l.split()[1]) for l in out.strip().split("\n")}
    ek, dk = K._keygen_internal(v["COINS"][:32], v["COINS"][32:])
    key, c = K._encaps_internal(ek, v["M"])
    res = dict(pk=ek == v["PK"], sk=dk == v["SK"], ct=c == v["CT"], ss=key == v["SS"],
               dec=K.decaps(dk, v["CT"]) == v["SSDEC"],
               reject1=K.decaps(dk, v["CTBAD"]) == v["SSBAD"],
               reject2=K.decaps(dk, v["CTBAD2"]) == v["SSBAD2"])
    print(s, res); ok &= all(res.values())
print("ALL MATCH FIPS-203 (kyber-py):", ok); sys.exit(0 if ok else 1)
