// TB: edge-list PE mesh Blueprint docs_peel branch (M37).
// syn=[1,0,1,0], edges 0-1,1-2,1-3 W=10 → cycles=10, solid=3'b011.

`timescale 1ns / 1ps

module tb_aether_uf_pe_docs_peel_grow;
    reg clk = 0;
    reg rst_n = 0;
    reg start = 0;
    reg [3:0] syn = 4'b0101; // v0=1, v1=0, v2=1, v3=0
    reg [3:0] is_bnd = 4'b0000;
    // edge0:(0,1) edge1:(1,2) edge2:(1,3)
    reg [23:0] eu_bus = {8'd1, 8'd1, 8'd0};
    reg [23:0] ev_bus = {8'd3, 8'd2, 8'd1};
    reg [47:0] cap_bus = {16'd10, 16'd10, 16'd10};
    wire done;
    wire [2:0] solid_bits;
    wire [47:0] growth_bus;
    wire [31:0] cycles;

    aether_uf_pe_graph_grow #(.N(4), .M(3), .CAP(10)) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .num_nodes(8'd4), .num_edges(8'd3),
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
        if (cycles !== 32'd10 || solid_bits !== 3'b011) begin
            $display("FAIL cycles=%0d solid=%b (expect 10, 3'b011)",
                     cycles, solid_bits);
            $fatal(1);
        end
        $display("PASS pe_docs_peel_grow cycles=%0d solid=%b (≡ helios_pe docs_peel)",
                 cycles, solid_bits);
        $finish;
    end
endmodule
