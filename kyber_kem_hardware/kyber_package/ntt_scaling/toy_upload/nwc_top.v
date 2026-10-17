`timescale 1ns / 1ps
//------------------------------------------------------------------------
// nwc_top.v
// Negative Wrapped Convolution (VPQC Algo 1):
//   c(x) = a(x) * b(x) mod (x^N + 1), mod Q
//
// Matches negative_wrapped_convolution() in python/nwc_ntt_ref.py:
//   1. a_tw[i] = a[i] * psi^i ,  b_tw[i] = b[i] * psi^i
//   2. A = NTT(a_tw), B = NTT(b_tw)         (bit-reversed order out)
//   3. C[i] = A[i]*B[i] mod Q               (still bit-reversed)
//   4. c_tw = INTT(C)                       (-> natural order)
//   5. c[i] = c_tw[i] * (psi^-i * N^-1) mod Q
//
// Step 5's N^-1 is pre-folded into psi_inv_pow_scaled.mem so the
// intt_engine itself does NOT need to apply N^-1 -- one shared multiplier
// does the whole job. This is a simple, fully-sequential controller meant
// for first bring-up / matching the Python model cycle-by-cycle in your
// waveform viewer, not a performance-optimized datapath.
//------------------------------------------------------------------------
module nwc_top #(
    parameter Q     = 17,
    parameter WIDTH = 5,
    parameter N     = 8,
    parameter LOGN  = 3
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,
    output reg                  done,

    input  wire                 a_wr_en,
    input  wire [LOGN-1:0]      a_wr_addr,
    input  wire [WIDTH-1:0]     a_wr_data,

    input  wire                 b_wr_en,
    input  wire [LOGN-1:0]      b_wr_addr,
    input  wire [WIDTH-1:0]     b_wr_data,

    input  wire [LOGN-1:0]      c_rd_addr,
    output wire [WIDTH-1:0]     c_rd_data
);

    // ---------------- input registers (natural order) ----------------
    reg [WIDTH-1:0] a_reg [0:N-1];
    reg [WIDTH-1:0] b_reg [0:N-1];
    always @(posedge clk) begin
        if (a_wr_en) a_reg[a_wr_addr] <= a_wr_data;
        if (b_wr_en) b_reg[b_wr_addr] <= b_wr_data;
    end

    // ---------------- twiddle / twist ROMs ----------------
    reg [WIDTH-1:0] psi_pow_rom          [0:N-1];
    reg [WIDTH-1:0] psi_inv_pow_scaled   [0:N-1];   // psi^-i * N^-1  (pre-folded)
    initial $readmemb("psi_pow.mem",            psi_pow_rom);
    initial $readmemb("psi_inv_pow_scaled.mem", psi_inv_pow_scaled);

    // ---------------- shared modular multiplier ----------------
    reg  [WIDTH-1:0] mul_a, mul_b;
    wire [WIDTH-1:0] mul_p;
    modq_mul #(.Q(Q), .WIDTH(WIDTH)) shared_mul (.a(mul_a), .b(mul_b), .prod_mod_q(mul_p));

    // ---------------- two forward NTT engines + one inverse NTT ----------------
    reg              ntt_a_start, ntt_b_start, intt_start;
    wire             ntt_a_done,  ntt_b_done,  intt_done;
    reg              ntt_a_ld_en, ntt_b_ld_en, intt_ld_en;
    reg  [LOGN-1:0]  ntt_a_ld_addr, ntt_b_ld_addr, intt_ld_addr;
    reg  [WIDTH-1:0] ntt_a_ld_data, ntt_b_ld_data, intt_ld_data;
    reg  [LOGN-1:0]  ntt_a_rd_addr, ntt_b_rd_addr, intt_rd_addr;
    wire [WIDTH-1:0] ntt_a_rd_data, ntt_b_rd_data, intt_rd_data;

    ntt_engine #(.Q(Q), .WIDTH(WIDTH), .N(N), .LOGN(LOGN), .TWFILE("tw_ct.mem")) u_ntt_a (
        .clk(clk), .rst_n(rst_n), .start(ntt_a_start), .done(ntt_a_done),
        .ld_en(ntt_a_ld_en), .ld_addr(ntt_a_ld_addr), .ld_data(ntt_a_ld_data),
        .rd_addr(ntt_a_rd_addr), .rd_data(ntt_a_rd_data)
    );
    ntt_engine #(.Q(Q), .WIDTH(WIDTH), .N(N), .LOGN(LOGN), .TWFILE("tw_ct.mem")) u_ntt_b (
        .clk(clk), .rst_n(rst_n), .start(ntt_b_start), .done(ntt_b_done),
        .ld_en(ntt_b_ld_en), .ld_addr(ntt_b_ld_addr), .ld_data(ntt_b_ld_data),
        .rd_addr(ntt_b_rd_addr), .rd_data(ntt_b_rd_data)
    );
    intt_engine #(.Q(Q), .WIDTH(WIDTH), .N(N), .LOGN(LOGN), .TWFILE("tw_gs.mem")) u_intt (
        .clk(clk), .rst_n(rst_n), .start(intt_start), .done(intt_done),
        .ld_en(intt_ld_en), .ld_addr(intt_ld_addr), .ld_data(intt_ld_data),
        .rd_addr(intt_rd_addr), .rd_data(intt_rd_data)
    );

    // final result (natural order)
    reg [WIDTH-1:0] c_reg [0:N-1];
    assign c_rd_data = c_reg[c_rd_addr];

    // ---------------- sequencer ----------------
    localparam S_IDLE      = 4'd0,
               S_TWIST_A   = 4'd1,
               S_TWIST_B   = 4'd2,
               S_START_NTT = 4'd3,
               S_WAIT_NTT  = 4'd4,
               S_PTMUL     = 4'd5,
               S_START_INTT= 4'd6,
               S_WAIT_INTT = 4'd7,
               S_UNTWIST   = 4'd8,
               S_DONE      = 4'd9;

    reg [3:0]      state;
    reg [LOGN-1:0] i;

    // combinational operand mux for the shared multiplier: depends only
    // on current state + index i, so mul_p is valid and consumable in the
    // SAME cycle -- no extra pipeline bookkeeping needed.
    always @(*) begin
        mul_a = {WIDTH{1'b0}};
        mul_b = {WIDTH{1'b0}};
        case (state)
            S_TWIST_A: begin mul_a = a_reg[i];        mul_b = psi_pow_rom[i]; end
            S_TWIST_B: begin mul_a = b_reg[i];        mul_b = psi_pow_rom[i]; end
            S_PTMUL:   begin mul_a = ntt_a_rd_data;   mul_b = ntt_b_rd_data;  end
            S_UNTWIST: begin mul_a = intt_rd_data;    mul_b = psi_inv_pow_scaled[i]; end
            default:   begin mul_a = {WIDTH{1'b0}};   mul_b = {WIDTH{1'b0}};  end
        endcase
    end

    // combinational read-address mux (registered engines' read ports)
    always @(*) begin
        ntt_a_rd_addr = i;
        ntt_b_rd_addr = i;
        intt_rd_addr  = i;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; done <= 1'b0; i <= 0;
            ntt_a_start <= 0; ntt_b_start <= 0; intt_start <= 0;
            ntt_a_ld_en <= 0; ntt_b_ld_en <= 0; intt_ld_en <= 0;
        end else begin
            // pulsed control defaults
            ntt_a_start <= 1'b0;
            ntt_b_start <= 1'b0;
            intt_start  <= 1'b0;
            ntt_a_ld_en <= 1'b0;
            ntt_b_ld_en <= 1'b0;
            intt_ld_en  <= 1'b0;

            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin i <= 0; state <= S_TWIST_A; end
                end

                // mul_p = a_reg[i]*psi^i  (combinational, see mux above)
                S_TWIST_A: begin
                    ntt_a_ld_en   <= 1'b1;
                    ntt_a_ld_addr <= i;
                    ntt_a_ld_data <= mul_p;
                    if (i == N-1) begin i <= 0; state <= S_TWIST_B; end
                    else          i <= i + 1'b1;
                end

                // mul_p = b_reg[i]*psi^i
                S_TWIST_B: begin
                    ntt_b_ld_en   <= 1'b1;
                    ntt_b_ld_addr <= i;
                    ntt_b_ld_data <= mul_p;
                    if (i == N-1) begin i <= 0; state <= S_START_NTT; end
                    else          i <= i + 1'b1;
                end

                S_START_NTT: begin
                    ntt_a_start <= 1'b1;
                    ntt_b_start <= 1'b1;
                    state <= S_WAIT_NTT;
                end

                S_WAIT_NTT: begin
                    if (ntt_a_done && ntt_b_done) begin i <= 0; state <= S_PTMUL; end
                end

                // mul_p = A[i]*B[i] ; read ports already point at i (mux above)
                S_PTMUL: begin
                    intt_ld_en   <= 1'b1;
                    intt_ld_addr <= i;
                    intt_ld_data <= mul_p;
                    if (i == N-1) begin i <= 0; state <= S_START_INTT; end
                    else          i <= i + 1'b1;
                end

                S_START_INTT: begin
                    intt_start <= 1'b1;
                    state <= S_WAIT_INTT;
                end

                S_WAIT_INTT: begin
                    if (intt_done) begin i <= 0; state <= S_UNTWIST; end
                end

                // mul_p = intt_out[i] * (psi^-i * N^-1)
                S_UNTWIST: begin
                    c_reg[i] <= mul_p;
                    if (i == N-1) state <= S_DONE;
                    else          i <= i + 1'b1;
                end

                S_DONE: begin
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
