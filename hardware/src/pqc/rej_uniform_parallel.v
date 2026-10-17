`timescale 1ns/1ps
// rej_uniform_parallel -- hardware equivalent of rej_uniform_avx2's core idea:
// pull multiple 3-byte groups per cycle, extract two 12-bit candidates each,
// reject anything >= KYBER_Q, and COMPACT the survivors into contiguous
// output slots -- the real job _mm256_shuffle_epi8(f0, g0) does in software.
//
// This version processes 4 groups (12 bytes) per cycle -> up to 8 candidates,
// 0 to 8 of which survive. Scale NUM_GROUPS up for wider parallelism.
module rej_uniform_parallel #(
    parameter KYBER_Q = 3329
) (
    input  [11:0][7:0] buf_bytes,      // 4 groups * 3 bytes = 12 input bytes
    output [7:0][15:0] out_coeffs,     // up to 8 accepted coefficients, compacted
    output [3:0]        out_count       // how many of out_coeffs are actually valid (0..8)
);

    localparam NUM_GROUPS = 4;
    localparam NUM_CAND   = NUM_GROUPS * 2;   // 8 candidates total

    wire [11:0] cand   [0:NUM_CAND-1];
    wire        valid  [0:NUM_CAND-1];

    genvar g;
    generate
        for (g = 0; g < NUM_GROUPS; g = g + 1) begin : gen_group
            wire [7:0] b0 = buf_bytes[3*g + 0];
            wire [7:0] b1 = buf_bytes[3*g + 1];
            wire [7:0] b2 = buf_bytes[3*g + 2];

            wire [11:0] d1 = {b1[3:0], b0};
            wire [11:0] d2 = {b2, b1[7:4]};

            assign cand[2*g]     = d1;
            assign cand[2*g + 1] = d2;
            assign valid[2*g]     = (d1 < KYBER_Q);
            assign valid[2*g + 1] = (d2 < KYBER_Q);
        end
    endgenerate

    // ---- exclusive prefix sum of the valid flags ----
    // prefix[i] = number of valid candidates strictly before index i.
    // A valid candidate at index i belongs at output slot prefix[i].
    wire [3:0] prefix [0:NUM_CAND];
    assign prefix[0] = 4'd0;
    genvar k;
    generate
        for (k = 0; k < NUM_CAND; k = k + 1) begin : gen_prefix
            assign prefix[k+1] = prefix[k] + (valid[k] ? 4'd1 : 4'd0);
        end
    endgenerate

    assign out_count = prefix[NUM_CAND];

    // ---- compaction: for each output slot, find the one candidate (if any)
    // whose valid flag is set and whose prefix sum equals this slot index ----
    genvar s, i;
    generate
        for (s = 0; s < NUM_CAND; s = s + 1) begin : gen_slot
            wire [11:0] slot_val;
            wire [NUM_CAND-1:0] hit;
            for (i = 0; i < NUM_CAND; i = i + 1) begin : gen_hit
                assign hit[i] = valid[i] && (prefix[i] == s[3:0]);
            end
            // at most one hit[i] is ever set, by construction of prefix sums
            assign slot_val = hit[0] ? cand[0] : hit[1] ? cand[1] :
                               hit[2] ? cand[2] : hit[3] ? cand[3] :
                               hit[4] ? cand[4] : hit[5] ? cand[5] :
                               hit[6] ? cand[6] : hit[7] ? cand[7] : 12'd0;
            assign out_coeffs[s] = {4'b0, slot_val};
        end
    endgenerate

endmodule
