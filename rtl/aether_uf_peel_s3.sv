// S3: peel sized for phenom d=3 r=1 (V=16 E=18). Spec: Docs/S3_Synth_M61.

`timescale 1ns / 1ps

module aether_uf_peel_s3 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [7:0]   num_nodes,
    input  wire [7:0]   num_edges,
    input  wire [17:0]  solid_bits,
    input  wire [127:0] syn_mem,
    input  wire [127:0] bnd_mem,
    input  wire [143:0] eu_mem,
    input  wire [143:0] ev_mem,
    output wire         done,
    output wire [17:0]  corr_bits,
    output wire [31:0]  peel_ops
);
    aether_uf_peel #(
        .MAX_N(16), .MAX_E(18), .MAX_DEG(16), .IDX_W(8)
    ) u_peel (
        .clk(clk), .rst_n(rst_n), .start(start),
        .num_nodes(num_nodes), .num_edges(num_edges),
        .solid_bits(solid_bits),
        .syn_mem(syn_mem), .bnd_mem(bnd_mem),
        .eu_mem(eu_mem), .ev_mem(ev_mem),
        .done(done), .corr_bits(corr_bits), .peel_ops(peel_ops)
    );
endmodule
