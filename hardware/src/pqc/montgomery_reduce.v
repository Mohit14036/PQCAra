`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: montgomery_reduce
// Combinational Montgomery reduction, matching Kyber's reference
// int16_t montgomery_reduce(int32_t a) from pq-crystals/kyber ref/reduce.c
//
//   int16_t montgomery_reduce(int32_t a) {
//     int16_t t;
//     t = (int16_t)a*QINV;
//     t = (a - (int32_t)t*KYBER_Q) >> 16;
//     return t;
//   }
//////////////////////////////////////////////////////////////////////////////////
module montgomery_reduce(
    input  wire signed [31:0] a,
    output wire signed [15:0] r
    );

    localparam signed [15:0] QINV = -16'sd3327; // q^-1 mod 2^16
    localparam signed [31:0] Q    =  32'sd3329; // KYBER_Q

    // Step 1: t = (int16_t)a * QINV
    //   (int16_t)a truncates to the low 16 bits, sign-extended.
    wire signed [15:0] a_lo16 = a[15:0];             // truncate, still signed
    wire signed [31:0] prod1  = a_lo16 * QINV;        // widen for the multiply

    // C then assigns this 32-bit product back into an int16_t t, which
    // truncates to the low 16 bits (two's-complement wraparound) --
    // NOT a saturating or rounding truncation, just a bit-slice + sign-extend.
    wire signed [15:0] t = prod1[15:0];

    // Step 2: t = (a - (int32_t)t*KYBER_Q) >> 16   (arithmetic shift)
    wire signed [31:0] t_times_q = t * Q;
    wire signed [31:0] diff      = a - t_times_q;
    wire signed [31:0] shifted   = diff >>> 16;       // arithmetic (signed) shift

    assign r = shifted[15:0];

endmodule
