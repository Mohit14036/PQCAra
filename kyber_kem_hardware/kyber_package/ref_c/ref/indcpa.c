#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include "params.h"

static int rej_uniform_dumped = 0;
static int keypair_dumped = 0;
static int enc_dumped = 0;
static int enc_call_count = 0;
static int enc2_dumped = 0;  // dumps the SECOND indcpa_enc() call (the re-encryption inside crypto_kem_dec's FO check)
static int dec_dumped = 0;
#include "indcpa.h"
#include "polyvec.h"
#include "poly.h"
#include "ntt.h"
#include "symmetric.h"
#include "randombytes.h"

/*************************************************
* Name:        pack_pk
*
* Description: Serialize the public key as concatenation of the
*              serialized vector of polynomials pk
*              and the public seed used to generate the matrix A.
*
* Arguments:   uint8_t *r: pointer to the output serialized public key
*              polyvec *pk: pointer to the input public-key polyvec
*              const uint8_t *seed: pointer to the input public seed
**************************************************/
static int pack_pk_dumped = 0;
static void pack_pk(uint8_t r[KYBER_INDCPA_PUBLICKEYBYTES],
                    polyvec *pk,
                    const uint8_t seed[KYBER_SYMBYTES])
{
  polyvec_tobytes(r, pk);
  memcpy(r+KYBER_POLYVECBYTES, seed, KYBER_SYMBYTES);

  if (!pack_pk_dumped) {
    FILE *f = fopen("/tmp/pack_pk_real.txt", "w");
    if (f) {
      unsigned int ii, c;
      for (ii = 0; ii < KYBER_K; ii++)
        for (c = 0; c < KYBER_N; c++) fprintf(f, "%d ", pk->vec[ii].coeffs[c]);
      fprintf(f, "\n");
      for (c = 0; c < KYBER_INDCPA_PUBLICKEYBYTES; c++) fprintf(f, "%u ", r[c]);
      fprintf(f, "\n");
      fclose(f);
    }
    pack_pk_dumped = 1;
  }
}

/*************************************************
* Name:        unpack_pk
*
* Description: De-serialize public key from a byte array;
*              approximate inverse of pack_pk
*
* Arguments:   - polyvec *pk: pointer to output public-key polynomial vector
*              - uint8_t *seed: pointer to output seed to generate matrix A
*              - const uint8_t *packedpk: pointer to input serialized public key
**************************************************/
static void unpack_pk(polyvec *pk,
                      uint8_t seed[KYBER_SYMBYTES],
                      const uint8_t packedpk[KYBER_INDCPA_PUBLICKEYBYTES])
{
  polyvec_frombytes(pk, packedpk);
  memcpy(seed, packedpk+KYBER_POLYVECBYTES, KYBER_SYMBYTES);
}

/*************************************************
* Name:        pack_sk
*
* Description: Serialize the secret key
*
* Arguments:   - uint8_t *r: pointer to output serialized secret key
*              - polyvec *sk: pointer to input vector of polynomials (secret key)
**************************************************/
static int pack_sk_dumped = 0;
static void pack_sk(uint8_t r[KYBER_INDCPA_SECRETKEYBYTES], polyvec *sk)
{
  polyvec_tobytes(r, sk);

  if (!pack_sk_dumped) {
    FILE *f = fopen("/tmp/pack_sk_real.txt", "w");
    if (f) {
      unsigned int ii, c;
      for (ii = 0; ii < KYBER_K; ii++)
        for (c = 0; c < KYBER_N; c++) fprintf(f, "%d ", sk->vec[ii].coeffs[c]);
      fprintf(f, "\n");
      for (c = 0; c < KYBER_INDCPA_SECRETKEYBYTES; c++) fprintf(f, "%u ", r[c]);
      fprintf(f, "\n");
      fclose(f);
    }
    pack_sk_dumped = 1;
  }
}

/*************************************************
* Name:        unpack_sk
*
* Description: De-serialize the secret key; inverse of pack_sk
*
* Arguments:   - polyvec *sk: pointer to output vector of polynomials (secret key)
*              - const uint8_t *packedsk: pointer to input serialized secret key
**************************************************/
static void unpack_sk(polyvec *sk, const uint8_t packedsk[KYBER_INDCPA_SECRETKEYBYTES])
{
  polyvec_frombytes(sk, packedsk);
}

/*************************************************
* Name:        pack_ciphertext
*
* Description: Serialize the ciphertext as concatenation of the
*              compressed and serialized vector of polynomials b
*              and the compressed and serialized polynomial v
*
* Arguments:   uint8_t *r: pointer to the output serialized ciphertext
*              poly *pk: pointer to the input vector of polynomials b
*              poly *v: pointer to the input polynomial v
**************************************************/
static void pack_ciphertext(uint8_t r[KYBER_INDCPA_BYTES], polyvec *b, poly *v)
{
  polyvec_compress(r, b);
  poly_compress(r+KYBER_POLYVECCOMPRESSEDBYTES, v);
}

/*************************************************
* Name:        unpack_ciphertext
*
* Description: De-serialize and decompress ciphertext from a byte array;
*              approximate inverse of pack_ciphertext
*
* Arguments:   - polyvec *b: pointer to the output vector of polynomials b
*              - poly *v: pointer to the output polynomial v
*              - const uint8_t *c: pointer to the input serialized ciphertext
**************************************************/
static void unpack_ciphertext(polyvec *b, poly *v, const uint8_t c[KYBER_INDCPA_BYTES])
{
  polyvec_decompress(b, c);
  poly_decompress(v, c+KYBER_POLYVECCOMPRESSEDBYTES);
}

/*************************************************
* Name:        rej_uniform
*
* Description: Run rejection sampling on uniform random bytes to generate
*              uniform random integers mod q
*
* Arguments:   - int16_t *r: pointer to output buffer
*              - unsigned int len: requested number of 16-bit integers (uniform mod q)
*              - const uint8_t *buf: pointer to input buffer (assumed to be uniformly random bytes)
*              - unsigned int buflen: length of input buffer in bytes
*
* Returns number of sampled 16-bit integers (at most len)
**************************************************/
static unsigned int rej_uniform(int16_t *r,
                                unsigned int len,
                                const uint8_t *buf,
                                unsigned int buflen)
{
  unsigned int ctr, pos;
  uint16_t val0, val1;

  ctr = pos = 0;
  while(ctr < len && pos + 3 <= buflen) {
    val0 = ((buf[pos+0] >> 0) | ((uint16_t)buf[pos+1] << 8)) & 0xFFF;
    val1 = ((buf[pos+1] >> 4) | ((uint16_t)buf[pos+2] << 4)) & 0xFFF;
    pos += 3;

    if(val0 < KYBER_Q)
      r[ctr++] = val0;
    if(ctr < len && val1 < KYBER_Q)
      r[ctr++] = val1;
  }

  if (!rej_uniform_dumped) {
    FILE *f = fopen("/tmp/rej_uniform_real.txt", "w");
    if (f) {
      unsigned int p;
      fprintf(f, "%u %u\n", len, buflen);
      for (p = 0; p < buflen; p++) fprintf(f, "%u ", buf[p]);
      fprintf(f, "\n");
      fprintf(f, "%u\n", ctr);
      for (p = 0; p < ctr; p++) fprintf(f, "%d ", r[p]);
      fprintf(f, "\n");
      fclose(f);
    }
    rej_uniform_dumped = 1;
  }

  return ctr;
}

#define gen_a(A,B)  gen_matrix(A,B,0)
#define gen_at(A,B) gen_matrix(A,B,1)

/*************************************************
* Name:        gen_matrix
*
* Description: Deterministically generate matrix A (or the transpose of A)
*              from a seed. Entries of the matrix are polynomials that look
*              uniformly random. Performs rejection sampling on output of
*              a XOF
*
* Arguments:   - polyvec *a: pointer to ouptput matrix A
*              - const uint8_t *seed: pointer to input seed
*              - int transposed: boolean deciding whether A or A^T is generated
**************************************************/
#if(XOF_BLOCKBYTES % 3)
#error "Implementation of gen_matrix assumes that XOF_BLOCKBYTES is a multiple of 3"
#endif

#define GEN_MATRIX_NBLOCKS ((12*KYBER_N/8*(1 << 12)/KYBER_Q + XOF_BLOCKBYTES)/XOF_BLOCKBYTES)
// Not static for benchmarking
void gen_matrix(polyvec *a, const uint8_t seed[KYBER_SYMBYTES], int transposed)
{
  unsigned int ctr, i, j;
  unsigned int buflen;
  uint8_t buf[GEN_MATRIX_NBLOCKS*XOF_BLOCKBYTES];
  xof_state state;

  for(i=0;i<KYBER_K;i++) {
    for(j=0;j<KYBER_K;j++) {
      if(transposed)
        xof_absorb(&state, seed, i, j);
      else
        xof_absorb(&state, seed, j, i);

      xof_squeezeblocks(buf, GEN_MATRIX_NBLOCKS, &state);
      buflen = GEN_MATRIX_NBLOCKS*XOF_BLOCKBYTES;
      ctr = rej_uniform(a[i].vec[j].coeffs, KYBER_N, buf, buflen);

      while(ctr < KYBER_N) {
        xof_squeezeblocks(buf, 1, &state);
        buflen = XOF_BLOCKBYTES;
        ctr += rej_uniform(a[i].vec[j].coeffs + ctr, KYBER_N - ctr, buf, buflen);
      }
    }
  }
}

/*************************************************
* Name:        indcpa_keypair_derand
*
* Description: Generates public and private key for the CPA-secure
*              public-key encryption scheme underlying Kyber
*
* Arguments:   - uint8_t *pk: pointer to output public key
*                             (of length KYBER_INDCPA_PUBLICKEYBYTES bytes)
*              - uint8_t *sk: pointer to output private key
*                             (of length KYBER_INDCPA_SECRETKEYBYTES bytes)
*              - const uint8_t *coins: pointer to input randomness
*                             (of length KYBER_SYMBYTES bytes)
**************************************************/
void indcpa_keypair_derand(uint8_t pk[KYBER_INDCPA_PUBLICKEYBYTES],
                           uint8_t sk[KYBER_INDCPA_SECRETKEYBYTES],
                           const uint8_t coins[KYBER_SYMBYTES])
{
  unsigned int i;
  uint8_t buf[2*KYBER_SYMBYTES];
  const uint8_t *publicseed = buf;
  const uint8_t *noiseseed = buf+KYBER_SYMBYTES;
  uint8_t nonce = 0;
  polyvec a[KYBER_K], e, pkpv, skpv;

  memcpy(buf, coins, KYBER_SYMBYTES);
  buf[KYBER_SYMBYTES] = KYBER_K;
  hash_g(buf, buf, KYBER_SYMBYTES+1);

  gen_a(a, publicseed);

  for(i=0;i<KYBER_K;i++)
    poly_getnoise_eta1(&skpv.vec[i], noiseseed, nonce++);
  for(i=0;i<KYBER_K;i++)
    poly_getnoise_eta1(&e.vec[i], noiseseed, nonce++);

  if (!keypair_dumped) {
    FILE *fpre = fopen("/tmp/indcpa_keypair_prentt_real.txt", "w");
    if (fpre) {
      unsigned int ii, c;
      for (ii = 0; ii < KYBER_K; ii++) {
        for (c = 0; c < KYBER_N; c++) fprintf(fpre, "%d ", skpv.vec[ii].coeffs[c]);
        fprintf(fpre, "\n");
      }
      for (ii = 0; ii < KYBER_K; ii++) {
        for (c = 0; c < KYBER_N; c++) fprintf(fpre, "%d ", e.vec[ii].coeffs[c]);
        fprintf(fpre, "\n");
      }
      fclose(fpre);
    }
  }

  polyvec_ntt(&skpv);
  polyvec_ntt(&e);

  // matrix-vector multiplication
  for(i=0;i<KYBER_K;i++) {
    polyvec_basemul_acc_montgomery(&pkpv.vec[i], &a[i], &skpv);
    poly_tomont(&pkpv.vec[i]);
  }

  polyvec_add(&pkpv, &pkpv, &e);
  polyvec_reduce(&pkpv);

  pack_sk(sk, &skpv);
  pack_pk(pk, &pkpv, publicseed);

  if (!keypair_dumped) {
    FILE *f = fopen("/tmp/indcpa_keypair_real.txt", "w");
    if (f) {
      unsigned int ii, jj;
      // matrix a[KYBER_K][KYBER_K] (post rej_uniform, pre-NTT)
      for (ii = 0; ii < KYBER_K; ii++)
        for (jj = 0; jj < KYBER_K; jj++) {
          unsigned int c;
          for (c = 0; c < KYBER_N; c++) fprintf(f, "%d ", a[ii].vec[jj].coeffs[c]);
          fprintf(f, "\n");
        }
      // skpv, e are ALREADY in NTT domain at this point (polyvec_ntt ran
      // in place before this dump); pkpv is the final NTT-domain,
      // montgomery-scaled, e-added, barrett-reduced public value.
      for (ii = 0; ii < KYBER_K; ii++) {
        unsigned int c;
        for (c = 0; c < KYBER_N; c++) fprintf(f, "%d ", skpv.vec[ii].coeffs[c]);
        fprintf(f, "\n");
      }
      for (ii = 0; ii < KYBER_K; ii++) {
        unsigned int c;
        for (c = 0; c < KYBER_N; c++) fprintf(f, "%d ", e.vec[ii].coeffs[c]);
        fprintf(f, "\n");
      }
      for (ii = 0; ii < KYBER_K; ii++) {
        unsigned int c;
        for (c = 0; c < KYBER_N; c++) fprintf(f, "%d ", pkpv.vec[ii].coeffs[c]);
        fprintf(f, "\n");
      }
      fclose(f);
    }
    keypair_dumped = 1;
  }
}


/*************************************************
* Name:        indcpa_enc
*
* Description: Encryption function of the CPA-secure
*              public-key encryption scheme underlying Kyber.
*
* Arguments:   - uint8_t *c: pointer to output ciphertext
*                            (of length KYBER_INDCPA_BYTES bytes)
*              - const uint8_t *m: pointer to input message
*                                  (of length KYBER_INDCPA_MSGBYTES bytes)
*              - const uint8_t *pk: pointer to input public key
*                                   (of length KYBER_INDCPA_PUBLICKEYBYTES)
*              - const uint8_t *coins: pointer to input random coins used as seed
*                                      (of length KYBER_SYMBYTES) to deterministically
*                                      generate all randomness
**************************************************/
void indcpa_enc(uint8_t c[KYBER_INDCPA_BYTES],
                const uint8_t m[KYBER_INDCPA_MSGBYTES],
                const uint8_t pk[KYBER_INDCPA_PUBLICKEYBYTES],
                const uint8_t coins[KYBER_SYMBYTES])
{
  unsigned int i;
  uint8_t seed[KYBER_SYMBYTES];
  uint8_t nonce = 0;
  polyvec sp, pkpv, ep, at[KYBER_K], b;
  poly v, k, epp;

  enc_call_count++;

  unpack_pk(&pkpv, seed, pk);
  poly_frommsg(&k, m);
  gen_at(at, seed);

  for(i=0;i<KYBER_K;i++)
    poly_getnoise_eta1(sp.vec+i, coins, nonce++);
  for(i=0;i<KYBER_K;i++)
    poly_getnoise_eta2(ep.vec+i, coins, nonce++);
  poly_getnoise_eta2(&epp, coins, nonce++);

  if (!enc_dumped) {
    FILE *fp = fopen("/tmp/indcpa_enc_prentt_real.txt", "w");
    if (fp) {
      unsigned int ii, c2;
      for (ii = 0; ii < KYBER_K; ii++) {
        for (c2 = 0; c2 < KYBER_N; c2++) fprintf(fp, "%d ", sp.vec[ii].coeffs[c2]);
        fprintf(fp, "\n");
      }
      for (ii = 0; ii < KYBER_K; ii++) {
        for (c2 = 0; c2 < KYBER_N; c2++) fprintf(fp, "%d ", ep.vec[ii].coeffs[c2]);
        fprintf(fp, "\n");
      }
      for (c2 = 0; c2 < KYBER_N; c2++) fprintf(fp, "%d ", epp.coeffs[c2]);
      fprintf(fp, "\n");
      fclose(fp);
    }
  }

  // sp/ep/epp for the SECOND call must be captured HERE (pre-NTT), since
  // polyvec_ntt(&sp) below mutates sp in place -- same lesson learned
  // when the analogous bug was caught for indcpa_dec's ciphertext b
  // (task #11): a dump placed after an in-place transform captures the
  // transformed value, not the original.
  if (enc_call_count == 2 && !enc2_dumped) {
    FILE *fp2 = fopen("/tmp/indcpa_enc2_prentt_real.txt", "w");
    if (fp2) {
      unsigned int ii, c2;
      for (ii = 0; ii < KYBER_K; ii++) {
        for (c2 = 0; c2 < KYBER_N; c2++) fprintf(fp2, "%d ", sp.vec[ii].coeffs[c2]);
        fprintf(fp2, "\n");
      }
      for (ii = 0; ii < KYBER_K; ii++) {
        for (c2 = 0; c2 < KYBER_N; c2++) fprintf(fp2, "%d ", ep.vec[ii].coeffs[c2]);
        fprintf(fp2, "\n");
      }
      for (c2 = 0; c2 < KYBER_N; c2++) fprintf(fp2, "%d ", epp.coeffs[c2]);
      fprintf(fp2, "\n");
      fclose(fp2);
    }
  }

  polyvec_ntt(&sp);

  // matrix-vector multiplication
  for(i=0;i<KYBER_K;i++)
    polyvec_basemul_acc_montgomery(&b.vec[i], &at[i], &sp);

  polyvec_basemul_acc_montgomery(&v, &pkpv, &sp);

  polyvec_invntt_tomont(&b);
  poly_invntt_tomont(&v);

  polyvec_add(&b, &b, &ep);
  poly_add(&v, &v, &epp);
  poly_add(&v, &v, &k);
  polyvec_reduce(&b);
  poly_reduce(&v);

  pack_ciphertext(c, &b, &v);

  if (!enc_dumped) {
    FILE *f = fopen("/tmp/indcpa_enc_real.txt", "w");
    if (f) {
      unsigned int ii, jj, c2;
      for (ii = 0; ii < KYBER_K; ii++)
        for (jj = 0; jj < KYBER_K; jj++) {
          for (c2 = 0; c2 < KYBER_N; c2++) fprintf(f, "%d ", at[ii].vec[jj].coeffs[c2]);
          fprintf(f, "\n");
        }
      for (ii = 0; ii < KYBER_K; ii++) {
        for (c2 = 0; c2 < KYBER_N; c2++) fprintf(f, "%d ", pkpv.vec[ii].coeffs[c2]);
        fprintf(f, "\n");
      }
      for (c2 = 0; c2 < KYBER_N; c2++) fprintf(f, "%d ", k.coeffs[c2]);
      fprintf(f, "\n");
      for (ii = 0; ii < KYBER_K; ii++) {
        for (c2 = 0; c2 < KYBER_N; c2++) fprintf(f, "%d ", b.vec[ii].coeffs[c2]);
        fprintf(f, "\n");
      }
      for (c2 = 0; c2 < KYBER_N; c2++) fprintf(f, "%d ", v.coeffs[c2]);
      fprintf(f, "\n");
      fclose(f);
    }
    enc_dumped = 1;
  }

  if (enc_call_count == 2 && !enc2_dumped) {
    FILE *f2 = fopen("/tmp/indcpa_enc2_real.txt", "w");
    if (f2) {
      unsigned int ii, jj, c2;
      for (ii = 0; ii < KYBER_K; ii++)
        for (jj = 0; jj < KYBER_K; jj++) {
          for (c2 = 0; c2 < KYBER_N; c2++) fprintf(f2, "%d ", at[ii].vec[jj].coeffs[c2]);
          fprintf(f2, "\n");
        }
      for (ii = 0; ii < KYBER_K; ii++) {
        for (c2 = 0; c2 < KYBER_N; c2++) fprintf(f2, "%d ", pkpv.vec[ii].coeffs[c2]);
        fprintf(f2, "\n");
      }
      for (c2 = 0; c2 < KYBER_N; c2++) fprintf(f2, "%d ", k.coeffs[c2]);
      fprintf(f2, "\n");
      for (ii = 0; ii < KYBER_K; ii++) {
        for (c2 = 0; c2 < KYBER_N; c2++) fprintf(f2, "%d ", b.vec[ii].coeffs[c2]);
        fprintf(f2, "\n");
      }
      for (c2 = 0; c2 < KYBER_N; c2++) fprintf(f2, "%d ", v.coeffs[c2]);
      fprintf(f2, "\n");
      for (c2 = 0; c2 < KYBER_INDCPA_BYTES; c2++) fprintf(f2, "%u ", c[c2]);
      fprintf(f2, "\n");
      fclose(f2);
    }
    enc2_dumped = 1;
  }
}

/*************************************************
* Name:        indcpa_dec
*
* Description: Decryption function of the CPA-secure
*              public-key encryption scheme underlying Kyber.
*
* Arguments:   - uint8_t *m: pointer to output decrypted message
*                            (of length KYBER_INDCPA_MSGBYTES)
*              - const uint8_t *c: pointer to input ciphertext
*                                  (of length KYBER_INDCPA_BYTES)
*              - const uint8_t *sk: pointer to input secret key
*                                   (of length KYBER_INDCPA_SECRETKEYBYTES)
**************************************************/
void indcpa_dec(uint8_t m[KYBER_INDCPA_MSGBYTES],
                const uint8_t c[KYBER_INDCPA_BYTES],
                const uint8_t sk[KYBER_INDCPA_SECRETKEYBYTES])
{
  polyvec b, skpv;
  poly v, mp;

  unpack_ciphertext(&b, &v, c);
  unpack_sk(&skpv, sk);

  if (!dec_dumped) {
    FILE *fp = fopen("/tmp/indcpa_dec_prentt_real.txt", "w");
    if (fp) {
      unsigned int ii, c2;
      for (ii = 0; ii < KYBER_K; ii++) {
        for (c2 = 0; c2 < KYBER_N; c2++) fprintf(fp, "%d ", b.vec[ii].coeffs[c2]);
        fprintf(fp, "\n");
      }
      fclose(fp);
    }
  }

  polyvec_ntt(&b);
  polyvec_basemul_acc_montgomery(&mp, &skpv, &b);
  poly_invntt_tomont(&mp);

  poly_sub(&mp, &v, &mp);
  poly_reduce(&mp);

  poly_tomsg(m, &mp);

  if (!dec_dumped) {
    FILE *f = fopen("/tmp/indcpa_dec_real.txt", "w");
    if (f) {
      unsigned int ii, c2;
      for (ii = 0; ii < KYBER_K; ii++) {
        for (c2 = 0; c2 < KYBER_N; c2++) fprintf(f, "%d ", b.vec[ii].coeffs[c2]);
        fprintf(f, "\n");
      }
      for (c2 = 0; c2 < KYBER_N; c2++) fprintf(f, "%d ", v.coeffs[c2]);
      fprintf(f, "\n");
      for (ii = 0; ii < KYBER_K; ii++) {
        for (c2 = 0; c2 < KYBER_N; c2++) fprintf(f, "%d ", skpv.vec[ii].coeffs[c2]);
        fprintf(f, "\n");
      }
      for (c2 = 0; c2 < KYBER_N; c2++) fprintf(f, "%d ", mp.coeffs[c2]);
      fprintf(f, "\n");
      for (c2 = 0; c2 < KYBER_INDCPA_MSGBYTES; c2++) fprintf(f, "%u ", m[c2]);
      fprintf(f, "\n");
      fclose(f);
    }
    dec_dumped = 1;
  }
}
