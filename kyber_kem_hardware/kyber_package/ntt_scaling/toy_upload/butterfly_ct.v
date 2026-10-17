`timescale 1ns / 1ps
//------------------------------------------------------------------------
// butterfly_ct.v
// One Cooley-Tukey Decimation-In-Time (CT-DIT) butterfly, matching the
// Python model's inner loop:
//      u' = u + w*v   (mod q)
//      v' = u - w*v   (mod q)
// Reference: eprint 2013/866 ("Speeding up the Number Theoretic Transform
// for Faster Ideal Lattice-Based Cryptography").
//
// Combinational: mul -> add / sub. In a real pipeline you'd register the
// mul output; left combinational here for simplicity of the "initial
// stage" sim -- pipeline it once you close timing in Vivado.
//------------------------------------------------------------------------
module butterfly_ct #(
    parameter Q     = 17,
    parameter WIDTH = 5
)(
    input  wire [WIDTH-1:0] u_in,
    input  wire [WIDTH-1:0] v_in,
    input  wire [WIDTH-1:0] w_in,     // twiddle factor
    output wire [WIDTH-1:0] u_out,
    output wire [WIDTH-1:0] v_out
);
    wire [WIDTH-1:0] t;   // t = w * v mod q

    modq_mul #(.Q(Q), .WIDTH(WIDTH)) u_mul (
        .a(w_in), .b(v_in), .prod_mod_q(t)
    );

    modq_add #(.Q(Q), .WIDTH(WIDTH)) u_add (
        .a(u_in), .b(t), .sum_mod_q(u_out)
    );

    modq_sub #(.Q(Q), .WIDTH(WIDTH)) u_sub (
        .a(u_in), .b(t), .diff_mod_q(v_out)
    );

endmodule
