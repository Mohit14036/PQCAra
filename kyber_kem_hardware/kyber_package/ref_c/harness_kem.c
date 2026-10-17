// Deterministic KEM vector generator using the unmodified-logic pq-crystals ref
// (derand APIs). Writes hex vectors for the RTL testbenches.
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#include "ref/params.h"
#include "ref/kem.h"
static void hexline(FILE*f,const char*tag,const uint8_t*b,size_t n){fprintf(f,"%s ",tag);for(size_t i=0;i<n;i++)fprintf(f,"%02x",b[i]);fprintf(f,"\n");}
int main(int argc,char**argv){
  uint8_t ct_bad2[KYBER_CIPHERTEXTBYTES], ss_bad2[32], coins[64], m[32], pk[KYBER_PUBLICKEYBYTES], sk[KYBER_SECRETKEYBYTES], ct[KYBER_CIPHERTEXTBYTES], ss[32], ss2[32], ct_bad[KYBER_CIPHERTEXTBYTES], ss_bad[32];
  unsigned seed = argc>1?(unsigned)atoi(argv[1]):1;
  // simple deterministic byte stream from seed
  uint32_t x = 0x9e3779b9u*seed+12345u;
  for(int i=0;i<64;i++){x=x*1664525u+1013904223u;coins[i]=x>>24;}
  for(int i=0;i<32;i++){x=x*1664525u+1013904223u;m[i]=x>>24;}
  crypto_kem_keypair_derand(pk,sk,coins);
  crypto_kem_enc_derand(ct,ss,pk,m);
  crypto_kem_dec(ss2,ct,sk);
  memcpy(ct_bad,ct,sizeof ct); ct_bad[100]^=0x01;
  crypto_kem_dec(ss_bad,ct_bad,sk);
  memcpy(ct_bad2,ct,sizeof ct); ct_bad2[1050]^=0x80;
  crypto_kem_dec(ss_bad2,ct_bad2,sk);
  hexline(stdout,"COINS",coins,64);hexline(stdout,"M",m,32);
  hexline(stdout,"PK",pk,sizeof pk);hexline(stdout,"SK",sk,sizeof sk);
  hexline(stdout,"CT",ct,sizeof ct);hexline(stdout,"SS",ss,32);hexline(stdout,"SSDEC",ss2,32);
  hexline(stdout,"CTBAD",ct_bad,sizeof ct_bad);hexline(stdout,"SSBAD",ss_bad,32);
  hexline(stdout,"CTBAD2",ct_bad2,sizeof ct_bad2);hexline(stdout,"SSBAD2",ss_bad2,32);
  return memcmp(ss,ss2,32)!=0;
}
