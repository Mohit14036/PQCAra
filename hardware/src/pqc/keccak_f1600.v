// =============================================================
// keccak_f1600.v -- Keccak-f[1600] permutation core
//
// One round per clock cycle: theta -> rho+pi -> chi -> iota,
// looping through the 1600-bit state register for 24 rounds.
// Matches the architecture diagram: State Register <-> theta ->
// rho/pi -> chi -> iota -> (back to State Register), with a
// round counter driving the round-constant ROM into iota.
//
// State layout: state[x][y] is a 64-bit lane, x,y in 0..4
// (the standard Keccak x,y,z coordinate convention).
//
// NOTE: round constants and rotation offsets below are transcribed
// from the standard FIPS 202 / Keccak reference tables from memory.
// Verify against FIPS 202 Appendix B before using in real hardware.
// =============================================================

module keccak_f1600 (
    input  wire            clk,
    input  wire            rst_n,
    input  wire            start,        // pulse: load state_in, begin 24 rounds
    input  wire [1599:0]   state_in,     // caller has already XORed in the rate bits
    output reg  [1599:0]   state_out,    // valid when done=1
    output reg              done
);

    // -----------------------------------------------------------
    // Round constants (24 rounds), FIPS 202 Appendix B
    // -----------------------------------------------------------
    reg [63:0] rc [0:23];
    initial begin
        rc[0]  = 64'h0000000000000001; rc[1]  = 64'h0000000000008082;
        rc[2]  = 64'h800000000000808A; rc[3]  = 64'h8000000080008000;
        rc[4]  = 64'h000000000000808B; rc[5]  = 64'h0000000080000001;
        rc[6]  = 64'h8000000080008081; rc[7]  = 64'h8000000000008009;
        rc[8]  = 64'h000000000000008A; rc[9]  = 64'h0000000000000088;
        rc[10] = 64'h0000000080008009; rc[11] = 64'h000000008000000A;
        rc[12] = 64'h000000008000808B; rc[13] = 64'h800000000000008B;
        rc[14] = 64'h8000000000008089; rc[15] = 64'h8000000000008003;
        rc[16] = 64'h8000000000008002; rc[17] = 64'h8000000000000080;
        rc[18] = 64'h000000000000800A; rc[19] = 64'h800000008000000A;
        rc[20] = 64'h8000000080008081; rc[21] = 64'h8000000000008080;
        rc[22] = 64'h0000000080000001; rc[23] = 64'h8000000080008008;
    end

    // -----------------------------------------------------------
    // Rho rotation offsets, indexed [x][y]
    // -----------------------------------------------------------
    function [7:0] rho_offset;
        input [2:0] x, y;
        begin
            case ({x, y})
                {3'd0,3'd0}: rho_offset = 0;   {3'd1,3'd0}: rho_offset = 1;
                {3'd2,3'd0}: rho_offset = 62;  {3'd3,3'd0}: rho_offset = 28;
                {3'd4,3'd0}: rho_offset = 27;
                {3'd0,3'd1}: rho_offset = 36;  {3'd1,3'd1}: rho_offset = 44;
                {3'd2,3'd1}: rho_offset = 6;   {3'd3,3'd1}: rho_offset = 55;
                {3'd4,3'd1}: rho_offset = 20;
                {3'd0,3'd2}: rho_offset = 3;   {3'd1,3'd2}: rho_offset = 10;
                {3'd2,3'd2}: rho_offset = 43;  {3'd3,3'd2}: rho_offset = 25;
                {3'd4,3'd2}: rho_offset = 39;
                {3'd0,3'd3}: rho_offset = 41;  {3'd1,3'd3}: rho_offset = 45;
                {3'd2,3'd3}: rho_offset = 15;  {3'd3,3'd3}: rho_offset = 21;
                {3'd4,3'd3}: rho_offset = 8;
                {3'd0,3'd4}: rho_offset = 18;  {3'd1,3'd4}: rho_offset = 2;
                {3'd2,3'd4}: rho_offset = 61;  {3'd3,3'd4}: rho_offset = 56;
                {3'd4,3'd4}: rho_offset = 14;
                default:     rho_offset = 0;
            endcase
        end
    endfunction

    function [63:0] rotl64;
        input [63:0] v;
        input [7:0]  n;
        begin
            rotl64 = (v << n) | (v >> (64 - n));
        end
    endfunction

    // -----------------------------------------------------------
    // State register: 25 lanes of 64 bits, indexed lane[x][y]
    // -----------------------------------------------------------
    reg [63:0] lane [0:4][0:4];
    reg [4:0]  round;   // 0..23

    integer xi, yi;

    // Unpack the flat 1600-bit vector into the lane array
    task unpack_state;
        input [1599:0] flat;
        integer x, y;
        begin
            for (x = 0; x < 5; x = x + 1)
                for (y = 0; y < 5; y = y + 1)
                    lane[x][y] = flat[ (5*y + x)*64 +: 64 ];
        end
    endtask

    // Pack the lane array back into a flat 1600-bit vector
    task pack_state;
        output [1599:0] flat;
        integer x, y;
        begin
            for (x = 0; x < 5; x = x + 1)
                for (y = 0; y < 5; y = y + 1)
                    flat[ (5*y + x)*64 +: 64 ] = lane[x][y];
        end
    endtask

    // -----------------------------------------------------------
    // Combinational round function: theta -> rho+pi -> chi -> iota
    // -----------------------------------------------------------
    reg [63:0] c_col   [0:4];        // theta: column parity
    reg [63:0] d_col   [0:4];
    reg [63:0] theta_out [0:4][0:4];
    reg [63:0] pi_out    [0:4][0:4]; // rho + pi combined
    reg [63:0] chi_out   [0:4][0:4];
    reg [63:0] iota_out  [0:4][0:4];

    always @(*) begin
        // ---- theta ----
        for (xi = 0; xi < 5; xi = xi + 1)
            c_col[xi] = lane[xi][0] ^ lane[xi][1] ^ lane[xi][2] ^ lane[xi][3] ^ lane[xi][4];
        for (xi = 0; xi < 5; xi = xi + 1)
            d_col[xi] = c_col[(xi+4)%5] ^ rotl64(c_col[(xi+1)%5], 1);
        for (xi = 0; xi < 5; xi = xi + 1)
            for (yi = 0; yi < 5; yi = yi + 1)
                theta_out[xi][yi] = lane[xi][yi] ^ d_col[xi];

        // ---- rho + pi ---- (rotate each lane, then permute position)
        // pi: lane'[y][2x+3y mod 5] = rho(lane[x][y])
        for (xi = 0; xi < 5; xi = xi + 1)
            for (yi = 0; yi < 5; yi = yi + 1)
                pi_out[yi][(2*xi + 3*yi) % 5] =
                    rotl64(theta_out[xi][yi], rho_offset(xi, yi));

        // ---- chi ---- (nonlinear mix within each row)
        for (xi = 0; xi < 5; xi = xi + 1)
            for (yi = 0; yi < 5; yi = yi + 1)
                chi_out[xi][yi] = pi_out[xi][yi] ^
                    ((~pi_out[(xi+1)%5][yi]) & pi_out[(xi+2)%5][yi]);

        // ---- iota ---- (XOR round constant into lane[0][0] only)
        for (xi = 0; xi < 5; xi = xi + 1)
            for (yi = 0; yi < 5; yi = yi + 1)
                iota_out[xi][yi] = chi_out[xi][yi];
        iota_out[0][0] = chi_out[0][0] ^ rc[round];
    end

    // -----------------------------------------------------------
    // Control FSM: load on start, advance one round per clock,
    // done pulses for one cycle after round 23 completes.
    // -----------------------------------------------------------
    localparam IDLE = 2'd0, RUN = 2'd1, DONE = 2'd2;
    reg [1:0] state_fsm;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_fsm <= IDLE;
            round     <= 5'd0;
            done      <= 1'b0;
        end else begin
            case (state_fsm)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        unpack_state(state_in);
                        round     <= 5'd0;
                        state_fsm <= RUN;
                    end
                end

                RUN: begin
                    for (xi = 0; xi < 5; xi = xi + 1)
                        for (yi = 0; yi < 5; yi = yi + 1)
                            lane[xi][yi] <= iota_out[xi][yi];

                    if (round == 5'd23) begin
                        state_fsm <= DONE;
                    end else begin
                        round <= round + 5'd1;
                    end
                end

                DONE: begin
                    pack_state(state_out);
                    done      <= 1'b1;
                    state_fsm <= IDLE;
                end

                default: state_fsm <= IDLE;
            endcase
        end
    end

endmodule
