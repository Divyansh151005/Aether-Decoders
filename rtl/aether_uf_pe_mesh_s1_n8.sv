// S1 headroom synth top (M57): pe_graph_grow N=8 M=8 (Fpga_Bringup_Prep N≤8).

`timescale 1ns / 1ps

module aether_uf_pe_mesh_s1_n8 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [7:0]   num_nodes,
    input  wire [7:0]   num_edges,
    input  wire [7:0]   syn,
    input  wire [7:0]   is_bnd,
    input  wire [63:0]  eu_bus,
    input  wire [63:0]  ev_bus,
    input  wire [127:0] cap_bus,
    output wire         done,
    output wire [7:0]   solid_bits,
    output wire [127:0] growth_bus,
    output wire [31:0]  cycles
);
    aether_uf_pe_graph_grow #(
        .N(8), .M(8), .CAP(10), .IDX_W(8)
    ) u_gm (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .num_nodes(num_nodes),
        .num_edges(num_edges),
        .syn(syn),
        .is_bnd(is_bnd),
        .eu_bus(eu_bus),
        .ev_bus(ev_bus),
        .cap_bus(cap_bus),
        .done(done),
        .solid_bits(solid_bits),
        .growth_bus(growth_bus),
        .cycles(cycles)
    );
endmodule
