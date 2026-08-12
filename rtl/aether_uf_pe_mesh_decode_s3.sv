// M64: S3 combined grow→peel (phenom d=3 r=1, V=16 E=18).
// Spec: Docs/S3_Combined_M64.

`timescale 1ns / 1ps

module aether_uf_pe_mesh_decode_s3 (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start_grow,
    input  wire          start_peel,
    input  wire [7:0]    num_nodes,
    input  wire [7:0]    num_edges,
    input  wire [15:0]   syn,
    input  wire [15:0]   is_bnd,
    input  wire [143:0]  eu_bus,
    input  wire [143:0]  ev_bus,
    input  wire [287:0]  cap_bus,
    input  wire [127:0]  syn_mem,
    input  wire [127:0]  bnd_mem,
    output wire          done_grow,
    output wire          done_peel,
    output wire [17:0]   solid_bits,
    output wire [17:0]   corr_bits,
    output wire [31:0]   cycles,
    output wire [31:0]   peel_ops
);
    wire [287:0] growth_bus;

    aether_uf_pe_graph_grow #(
        .N(16), .M(18), .CAP(10), .IDX_W(8)
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
        .MAX_N(16), .MAX_E(18), .MAX_DEG(16), .IDX_W(8)
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
