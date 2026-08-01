// S1 Blueprint PE-mesh synth top (M57): grow only, N=4 M=4.
// Spec: Docs/S1_Synth_M57. Peel stays Icarus/Verilator (Yosys rejects unpacked ports).

`timescale 1ns / 1ps

module aether_uf_pe_mesh_s1_top #(
    parameter int N     = 4,
    parameter int M     = 4,
    parameter int CAP   = 10,
    parameter int IDX_W = 8
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,
    input  wire [IDX_W-1:0]     num_nodes,
    input  wire [IDX_W-1:0]     num_edges,
    input  wire [N-1:0]         syn,
    input  wire [N-1:0]         is_bnd,
    input  wire [IDX_W*M-1:0]   eu_bus,
    input  wire [IDX_W*M-1:0]   ev_bus,
    input  wire [16*M-1:0]      cap_bus,
    output wire                 done,
    output wire [M-1:0]         solid_bits,
    output wire [16*M-1:0]      growth_bus,
    output wire [31:0]          cycles
);
    aether_uf_pe_graph_grow #(
        .N(N), .M(M), .CAP(CAP), .IDX_W(IDX_W)
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
