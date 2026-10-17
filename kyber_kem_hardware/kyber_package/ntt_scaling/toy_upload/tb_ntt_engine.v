`timescale 1ns / 1ps
module tb_ntt_engine;
    localparam Q = 17, WIDTH = 5, N = 8, LOGN = 3;

    reg clk = 0, rst_n = 0, start = 0;
    wire done;
    reg ld_en = 0;
    reg [LOGN-1:0] ld_addr;
    reg [WIDTH-1:0] ld_data;
    reg [LOGN-1:0] rd_addr;
    wire [WIDTH-1:0] rd_data;

    ntt_engine #(.Q(Q), .WIDTH(WIDTH), .N(N), .LOGN(LOGN), .TWFILE("tw_ct.mem")) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .done(done),
        .ld_en(ld_en), .ld_addr(ld_addr), .ld_data(ld_data),
        .rd_addr(rd_addr), .rd_data(rd_data)
    );

    always #5 clk = ~clk;

    reg [WIDTH-1:0] a_in       [0:N-1];
    reg [WIDTH-1:0] expected   [0:N-1];
    integer i;
    integer errors = 0;

    initial begin
        $readmemb("a_in.mem", a_in);
        $readmemb("ntt_a_expected.mem", expected);

        rst_n = 0; #12; rst_n = 1;

        // load input
        @(negedge clk);
        for (i = 0; i < N; i = i + 1) begin
            ld_en = 1; ld_addr = i[LOGN-1:0]; ld_data = a_in[i];
            @(negedge clk);
        end
        ld_en = 0;

        start = 1; @(negedge clk); start = 0;
        wait (done == 1);
        @(negedge clk);

        for (i = 0; i < N; i = i + 1) begin
            rd_addr = i[LOGN-1:0];
            #1;
            if (rd_data !== expected[i]) begin
                $display("MISMATCH idx=%0d got=%0d expected=%0d", i, rd_data, expected[i]);
                errors = errors + 1;
            end else begin
                $display("OK      idx=%0d got=%0d expected=%0d", i, rd_data, expected[i]);
            end
        end

        if (errors == 0) $display("*** NTT ENGINE TEST PASSED ***");
        else              $display("*** NTT ENGINE TEST FAILED: %0d errors ***", errors);

        $finish;
    end
endmodule
