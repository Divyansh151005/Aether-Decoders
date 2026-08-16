// M66: intermediate-N grow scale (N=24 M=27). Spec: Docs/Grow_Scale_M66.

`timescale 1ns / 1ps

module aether_uf_pe_mesh_grow_n24 (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [7:0]    num_nodes,
    input  wire [7:0]    num_edges,
    input  wire [23:0]   syn,
    input  wire [23:0]   is_bnd,
    input  wire [215:0]  eu_bus,
    input  wire [215:0]  ev_bus,
    input  wire [431:0]  cap_bus,
    output wire          done,
    output wire [26:0]   solid_bits,
    output wire [431:0]  growth_bus,
    output wire [31:0]   cycles
);
    // IDX_W=8 → eu/ev = 8*27 = 216; cap/growth = 16*27 = 432
    aether_uf_pe_graph_grow #(
        .N(24), .M(27), .CAP(10), .IDX_W(8)
    ) u_gm (
        .clk(clk), .rst_n(rst_n), .start(start),
        .num_nodes(num_nodes), .num_edges(num_edges),
        .syn(syn), .is_bnd(is_bnd),
        .eu_bus(eu_bus), .ev_bus(ev_bus), .cap_bus(cap_bus),
        .done(done), .solid_bits(solid_bits),
        .growth_bus(growth_bus), .cycles(cycles)
    );
endmodule
