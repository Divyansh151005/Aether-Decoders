// Self-checking testbench for aether_uf_two_node_grow_merge.
 // Expected (Blueprint test 1): after start with syn0=syn1=1 → done, cycles=5, solid0=1.

`timescale 1ns / 1ps

module tb_aether_uf_two_node;
    reg clk = 0;
    reg rst_n = 0;
    reg start = 0;
    reg syn0 = 1;
    reg syn1 = 1;
    wire done;
    wire solid0;
    wire [15:0] growth0;
    wire [15:0] cycles;

    aether_uf_two_node_grow_merge dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .syn0(syn0),
        .syn1(syn1),
        .done(done),
        .solid0(solid0),
        .growth0(growth0),
        .cycles(cycles)
    );

    always #5 clk = ~clk;

    initial begin
        rst_n = 0;
        #20;
        rst_n = 1;
        #20;
        start = 1;
        #10;
        start = 0;
        wait (done);
        #10;
        if (cycles !== 16'd5 || solid0 !== 1'b1) begin
            $display("FAIL cycles=%0d solid0=%0b growth0=%0d", cycles, solid0, growth0);
            $fatal(1);
        end
        $display("PASS cycles=%0d solid0=%0b growth0=%0d", cycles, solid0, growth0);
        $finish;
    end
endmodule
