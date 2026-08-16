// S4: circuit d=3 r=3 PE-mesh grow (V=392 E=556). Spec: Docs/S4_Synth_M65.
// Grow-only resource cliff; IDX_W=16 (M46).

`timescale 1ns / 1ps

module aether_uf_pe_mesh_s4_grow (
    input  wire           clk,
    input  wire           rst_n,
    input  wire           start,
    input  wire [15:0]    num_nodes,
    input  wire [15:0]    num_edges,
    input  wire [391:0]   syn,
    input  wire [391:0]   is_bnd,
    input  wire [8895:0]  eu_bus,
    input  wire [8895:0]  ev_bus,
    input  wire [8895:0]  cap_bus,
    output wire           done,
    output wire [555:0]   solid_bits,
    output wire [8895:0]  growth_bus,
    output wire [31:0]    cycles
);
    aether_uf_pe_graph_grow #(
        .N(392), .M(556), .CAP(10), .IDX_W(16)
    ) u_gm (
        .clk(clk), .rst_n(rst_n), .start(start),
        .num_nodes(num_nodes), .num_edges(num_edges),
        .syn(syn), .is_bnd(is_bnd),
        .eu_bus(eu_bus), .ev_bus(ev_bus), .cap_bus(cap_bus),
        .done(done), .solid_bits(solid_bits),
        .growth_bus(growth_bus), .cycles(cycles)
    );
endmodule
