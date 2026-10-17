// Full real Kyber KEM round-trip: KeyGen -> Encaps -> Decaps, using the
// UNMODIFIED real pq-crystals/kyber ref/ source, checking Alice's and
// Bob's shared secrets actually match.
#include <stdio.h>
#include <string.h>
#include "ref/params.h"
#include "ref/kem.h"

int main(void) {
  unsigned char pk[KYBER_PUBLICKEYBYTES];
  unsigned char sk[KYBER_SECRETKEYBYTES];
  unsigned char ct[KYBER_CIPHERTEXTBYTES];
  unsigned char ss_bob[KYBER_SSBYTES];
  unsigned char ss_alice[KYBER_SSBYTES];

  int r1 = crypto_kem_keypair(pk, sk);          // Alice generates keypair
  int r2 = crypto_kem_enc(ct, ss_bob, pk);       // Bob encapsulates using Alice's pk
  int r3 = crypto_kem_dec(ss_alice, ct, sk);     // Alice decapsulates using her sk

  printf("keygen rc=%d  enc rc=%d  dec rc=%d\n", r1, r2, r3);
  printf("KYBER_K=%d  pk=%dB sk=%dB ct=%dB ss=%dB\n",
         KYBER_K, KYBER_PUBLICKEYBYTES, KYBER_SECRETKEYBYTES, KYBER_CIPHERTEXTBYTES, KYBER_SSBYTES);

  int match = (memcmp(ss_bob, ss_alice, KYBER_SSBYTES) == 0);
  printf("ss_bob   = "); for (int i = 0; i < KYBER_SSBYTES; i++) printf("%02x", ss_bob[i]); printf("\n");
  printf("ss_alice = "); for (int i = 0; i < KYBER_SSBYTES; i++) printf("%02x", ss_alice[i]); printf("\n");
  printf("MATCH: %s\n", match ? "YES -- shared secrets agree" : "NO -- MISMATCH");
  return !match;
}
