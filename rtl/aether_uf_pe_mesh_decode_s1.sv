// M59: Yosys-friendly Blueprint grow→peel top (N=4 M=4).
// Spec: Docs/Peel_Packed_M59.

`timescale 1ns / 1ps

module aether_uf_pe_mesh_decode_s1 #(
    parameter int N     = 4,
    parameter int M     = 4,
    parameter int IDX_W = 8,
    parameter int CAP   = 10
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start_grow,
    input  wire                 start_peel,
    input  wire [IDX_W-1:0]     num_nodes,
    input  wire [IDX_W-1:0]     num_edges,
    input  wire [N-1:0]         syn,
    input  wire [N-1:0]         is_bnd,
    input  wire [IDX_W*M-1:0]   eu_bus,
    input  wire [IDX_W*M-1:0]   ev_bus,
    input  wire [16*M-1:0]      cap_bus,
    input  wire [8*N-1:0]       syn_mem,
    input  wire [8*N-1:0]       bnd_mem,
    output wire                 done_grow,
    output wire                 done_peel,
    output wire [M-1:0]         solid_bits,
    output wire [M-1:0]         corr_bits,
    output wire [31:0]          cycles,
    output wire [31:0]          peel_ops
);
    wire [16*M-1:0] growth_bus;

    aether_uf_pe_graph_grow #(
        .N(N), .M(M), .CAP(CAP), .IDX_W(IDX_W)
    ) u_gm (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_grow),
        .num_nodes(num_nodes),
        .num_edges(num_edges),
        .syn(syn),
        .is_bnd(is_bnd),
        .eu_bus(eu_bus),
        .ev_bus(ev_bus),
        .cap_bus(cap_bus),
        .done(done_grow),
        .solid_bits(solid_bits),
        .growth_bus(growth_bus),
        .cycles(cycles)
    );

    aether_uf_peel #(
        .MAX_N(N), .MAX_E(M), .MAX_DEG(8), .IDX_W(IDX_W)
    ) u_peel (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_peel),
        .num_nodes(num_nodes),
        .num_edges(num_edges),
        .solid_bits(solid_bits),
        .syn_mem(syn_mem),
        .bnd_mem(bnd_mem),
        .eu_mem(eu_bus),
        .ev_mem(ev_bus),
        .done(done_peel),
        .corr_bits(corr_bits),
        .peel_ops(peel_ops)
    );
endmodule
