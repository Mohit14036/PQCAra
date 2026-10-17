// harness_poly_mul.c -- standalone test harness reusing the real ref/
// Kyber-768 source already in this project. Computes a real polynomial
// multiplication in R_q = Z_q[X]/(X^256+1) via Kyber's actual NTT-domain
// pipeline (poly_ntt -> poly_basemul_montgomery -> poly_invntt_tomont),
// and dumps the two input polynomials plus the real result to a plain
// text vector file for RTL comparison and independent Python
// cross-checking.
#include <stdio.h>
#include <stdint.h>
#include "params.h"
#include "poly.h"
#include "ntt.h"
#include "reduce.h"

int main(void) {
    poly a, b, a_ntt, b_ntt, r;
    int i;

    // Deterministic, non-trivial test polynomials (not all-zero/all-one,
    // spanning the centered range) -- reproducible so the Python
    // cross-check below is comparing against the exact same inputs.
    for (i = 0; i < KYBER_N; i++) {
        a.coeffs[i] = (int16_t)(((i * 37 + 5) % KYBER_Q) - KYBER_Q/2);
        b.coeffs[i] = (int16_t)(((i * 101 + 991) % KYBER_Q) - KYBER_Q/2);
    }

    a_ntt = a;
    b_ntt = b;
    poly_ntt(&a_ntt);   // = ntt(a); poly_reduce(a)  (barrett_reduce every coeff)
    poly_ntt(&b_ntt);

    poly_basemul_montgomery(&r, &a_ntt, &b_ntt);
    poly_invntt_tomont(&r);

    FILE *f = fopen("/tmp/poly_mul_ntt_real.txt", "w");
    for (i = 0; i < KYBER_N; i++) fprintf(f, "%d ", a.coeffs[i]);
    fprintf(f, "\n");
    for (i = 0; i < KYBER_N; i++) fprintf(f, "%d ", b.coeffs[i]);
    fprintf(f, "\n");
    for (i = 0; i < KYBER_N; i++) fprintf(f, "%d ", a_ntt.coeffs[i]);
    fprintf(f, "\n");
    for (i = 0; i < KYBER_N; i++) fprintf(f, "%d ", b_ntt.coeffs[i]);
    fprintf(f, "\n");
    for (i = 0; i < KYBER_N; i++) fprintf(f, "%d ", r.coeffs[i]);
    fprintf(f, "\n");
    fclose(f);

    printf("wrote /tmp/poly_mul_ntt_real.txt\n");
    return 0;
}
