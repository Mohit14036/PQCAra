`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: barrett  (fixed)
// Combinational Barrett reduction, matching Kyber's reference barrett_reduce()
// int16_t barrett_reduce(int16_t a) from pq-crystals/kyber ref/reduce.c
//////////////////////////////////////////////////////////////////////////////////
module barrett(
    input  wire signed [15:0] a,
    output wire signed [15:0] r
    );

    localparam signed [15:0] V = 16'sd20159; // (2^26 + 3329/2) / 3329, KYBER

    wire signed [31:0] prod;      // v*a needs up to ~31 bits, not 1
    wire signed [31:0] t_shift;   // rounded quotient estimate
    wire signed [31:0] t_full;    // t_shift * q

    assign prod     = V * a;                       // one expression per step,
    assign t_shift  = (prod + 32'sd33554432) >>> 26; // not two drivers on one net
    assign t_full   = t_shift * 32'sd3329;           // KYBER_Q = 3329
    assign r         = a - t_full[15:0];

endmodule
