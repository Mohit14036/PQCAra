`timescale 1ns / 1ps
//------------------------------------------------------------------------
// modq_arith.v
// Modular add / sub / mul for a small prime modulus Q.
// Written generically (parameter Q, WIDTH) so it is trivial to re-target
// from the toy example (Q=17) up to Kyber's Q=3329 (WIDTH=12) later on.
//
// Reference: reduction technique matches the "schoolbook" mod reduction
// used in eprint 2013/866; for Kyber-scale you would normally swap the
// mul reducer for a Barrett/Montgomery reducer (see RSA & Barrett /
// Montgomery reduction refs) instead of the plain '%' used here.
//------------------------------------------------------------------------

module modq_add #(
    parameter Q     = 17,
    parameter WIDTH = 5
)(
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    output wire [WIDTH-1:0] sum_mod_q
);
    wire [WIDTH:0] s = a + b;
    assign sum_mod_q = (s >= Q) ? (s - Q) : s[WIDTH-1:0];
endmodule


module modq_sub #(
    parameter Q     = 17,
    parameter WIDTH = 5
)(
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    output wire [WIDTH-1:0] diff_mod_q
);
    // a - b, wrapped into [0, Q)
    wire signed [WIDTH+1:0] d = $signed({1'b0, a}) - $signed({1'b0, b});
    assign diff_mod_q = (d < 0) ? (d + Q) : d[WIDTH-1:0];
endmodule


module modq_mul #(
    parameter Q     = 17,
    parameter WIDTH = 5
)(
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    output wire [WIDTH-1:0] prod_mod_q
);
    // Behavioral mod-reduce; Vivado will happily synthesize this for small
    // constant Q using a compare/subtract tree. For Kyber-scale Q this
    // should be replaced with a Barrett reducer (single reference in your
    // sheet: RSA & Barrett Reduction) to avoid an expensive hard divider.
    wire [2*WIDTH-1:0] p = a * b;
    assign prod_mod_q = p % Q;
endmodule
