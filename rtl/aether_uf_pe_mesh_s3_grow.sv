// S3: phenom d=3 r=1 PE-mesh grow (V=16 E=18). Spec: Docs/S3_Synth_M61.

`timescale 1ns / 1ps

module aether_uf_pe_mesh_s3_grow (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [7:0]    num_nodes,
    input  wire [7:0]    num_edges,
    input  wire [15:0]   syn,
    input  wire [15:0]   is_bnd,
    input  wire [143:0]  eu_bus,
    input  wire [143:0]  ev_bus,
    input  wire [287:0]  cap_bus,
    output wire          done,
    output wire [17:0]   solid_bits,
    output wire [287:0]  growth_bus,
    output wire [31:0]   cycles
);
    aether_uf_pe_graph_grow #(
        .N(16), .M(18), .CAP(10), .IDX_W(8)
    ) u_gm (
        .clk(clk), .rst_n(rst_n), .start(start),
        .num_nodes(num_nodes), .num_edges(num_edges),
        .syn(syn), .is_bnd(is_bnd),
        .eu_bus(eu_bus), .ev_bus(ev_bus), .cap_bus(cap_bus),
        .done(done), .solid_bits(solid_bits),
        .growth_bus(growth_bus), .cycles(cycles)
    );
endmodule
