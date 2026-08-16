// M66: intermediate-N grow scale (N=64 M=72). Spec: Docs/Grow_Scale_M66.

`timescale 1ns / 1ps

module aether_uf_pe_mesh_grow_n64 (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [7:0]    num_nodes,
    input  wire [7:0]    num_edges,
    input  wire [63:0]   syn,
    input  wire [63:0]   is_bnd,
    input  wire [575:0]  eu_bus,
    input  wire [575:0]  ev_bus,
    input  wire [1151:0] cap_bus,
    output wire          done,
    output wire [71:0]   solid_bits,
    output wire [1151:0] growth_bus,
    output wire [31:0]   cycles
);
    // IDX_W=8 → eu/ev = 8*72 = 576; cap/growth = 16*72 = 1152
    aether_uf_pe_graph_grow #(
        .N(64), .M(72), .CAP(10), .IDX_W(8)
    ) u_gm (
        .clk(clk), .rst_n(rst_n), .start(start),
        .num_nodes(num_nodes), .num_edges(num_edges),
        .syn(syn), .is_bnd(is_bnd),
        .eu_bus(eu_bus), .ev_bus(ev_bus), .cap_bus(cap_bus),
        .done(done), .solid_bits(solid_bits),
        .growth_bus(growth_bus), .cycles(cycles)
    );
endmodule
