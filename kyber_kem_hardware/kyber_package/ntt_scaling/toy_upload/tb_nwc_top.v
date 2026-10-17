`timescale 1ns / 1ps
module tb_nwc_top;
    localparam Q = 17, WIDTH = 5, N = 8, LOGN = 3;

    reg clk = 0, rst_n = 0, start = 0;
    wire done;
    reg a_wr_en = 0, b_wr_en = 0;
    reg [LOGN-1:0] a_wr_addr, b_wr_addr, c_rd_addr;
    reg [WIDTH-1:0] a_wr_data, b_wr_data;
    wire [WIDTH-1:0] c_rd_data;

    nwc_top #(.Q(Q), .WIDTH(WIDTH), .N(N), .LOGN(LOGN)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .done(done),
        .a_wr_en(a_wr_en), .a_wr_addr(a_wr_addr), .a_wr_data(a_wr_data),
        .b_wr_en(b_wr_en), .b_wr_addr(b_wr_addr), .b_wr_data(b_wr_data),
        .c_rd_addr(c_rd_addr), .c_rd_data(c_rd_data)
    );

    always #5 clk = ~clk;

    reg [WIDTH-1:0] a_in     [0:N-1];
    reg [WIDTH-1:0] b_in     [0:N-1];
    reg [WIDTH-1:0] expected [0:N-1];
    integer i;
    integer errors = 0;

    initial begin
        $readmemb("a_in.mem", a_in);
        $readmemb("b_in.mem", b_in);
        $readmemb("nwc_expected.mem", expected);

        rst_n = 0; #12; rst_n = 1;

        @(negedge clk);
        for (i = 0; i < N; i = i + 1) begin
            a_wr_en = 1; a_wr_addr = i[LOGN-1:0]; a_wr_data = a_in[i];
            b_wr_en = 1; b_wr_addr = i[LOGN-1:0]; b_wr_data = b_in[i];
            @(negedge clk);
        end
        a_wr_en = 0; b_wr_en = 0;

        start = 1; @(negedge clk); start = 0;
        wait (done == 1);
        @(negedge clk);

        for (i = 0; i < N; i = i + 1) begin
            c_rd_addr = i[LOGN-1:0];
            #1;
            if (c_rd_data !== expected[i]) begin
                $display("MISMATCH idx=%0d got=%0d expected=%0d", i, c_rd_data, expected[i]);
                errors = errors + 1;
            end else begin
                $display("OK      idx=%0d got=%0d expected=%0d", i, c_rd_data, expected[i]);
            end
        end

        if (errors == 0) $display("*** NEGATIVE WRAPPED CONVOLUTION TEST PASSED ***");
        else              $display("*** NEGATIVE WRAPPED CONVOLUTION TEST FAILED: %0d errors ***", errors);

        $finish;
    end
endmodule
