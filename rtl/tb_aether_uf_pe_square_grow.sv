// TB: edge-list PE mesh Blueprint square (M37).
// syn=[1,0,0,1], edges 0-1,1-2,2-3,3-0 W=10 → cycles=5, solid=4'b1000.

`timescale 1ns / 1ps

module tb_aether_uf_pe_square_grow;
    reg clk = 0;
    reg rst_n = 0;
    reg start = 0;
    reg [3:0] syn = 4'b1001;
    reg [3:0] is_bnd = 4'b0000;
    // eu = {e3,e2,e1,e0} packed little: edge0:(0,1) edge1:(1,2) edge2:(2,3) edge3:(3,0)
    reg [31:0] eu_bus = {8'd3, 8'd2, 8'd1, 8'd0};
    reg [31:0] ev_bus = {8'd0, 8'd3, 8'd2, 8'd1};
    reg [63:0] cap_bus = {16'd10, 16'd10, 16'd10, 16'd10};
    wire done;
    wire [3:0] solid_bits;
    wire [63:0] growth_bus;
    wire [31:0] cycles;

    aether_uf_pe_graph_grow #(.N(4), .M(4), .CAP(10)) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .num_nodes(8'd4), .num_edges(8'd4),
        .syn(syn), .is_bnd(is_bnd),
        .eu_bus(eu_bus), .ev_bus(ev_bus), .cap_bus(cap_bus),
        .done(done), .solid_bits(solid_bits),
        .growth_bus(growth_bus), .cycles(cycles)
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
        if (cycles !== 32'd5 || solid_bits !== 4'b1000) begin
            $display("FAIL cycles=%0d solid=%b (expect 5, 4'b1000)",
                     cycles, solid_bits);
            $fatal(1);
        end
        if (growth_bus[63:48] !== 16'd10) begin
            $display("FAIL edge3 growth=%0d (expect 10)", growth_bus[63:48]);
            $fatal(1);
        end
        $display("PASS pe_square_grow cycles=%0d solid=%b (≡ helios_pe square)",
                 cycles, solid_bits);
        $finish;
    end
endmodule
