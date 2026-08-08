// TB-only: pack array memories into aether_uf_peel (M59) buses.
// Not for FPGA synth (unpacked array ports). Spec: Docs/Peel_Packed_M59.

`timescale 1ns / 1ps

module aether_uf_tb_pack_peel_in #(
    parameter int MAX_N = 8,
    parameter int MAX_E = 8,
    parameter int IDX_W = 16
) (
    input  wire             solid_arr [0:MAX_E-1],
    input  wire [7:0]       syn_arr   [0:MAX_N-1],
    input  wire [7:0]       bnd_arr   [0:MAX_N-1],
    input  wire [IDX_W-1:0] eu_arr    [0:MAX_E-1],
    input  wire [IDX_W-1:0] ev_arr    [0:MAX_E-1],
    output wire [MAX_E-1:0]           solid_bits,
    output wire [8*MAX_N-1:0]         syn_mem,
    output wire [8*MAX_N-1:0]         bnd_mem,
    output wire [IDX_W*MAX_E-1:0]     eu_mem,
    output wire [IDX_W*MAX_E-1:0]     ev_mem
);
    genvar i, e;
    generate
        for (e = 0; e < MAX_E; e = e + 1) begin : g_s
            assign solid_bits[e] = solid_arr[e];
            assign eu_mem[e*IDX_W +: IDX_W] = eu_arr[e];
            assign ev_mem[e*IDX_W +: IDX_W] = ev_arr[e];
        end
        for (i = 0; i < MAX_N; i = i + 1) begin : g_v
            assign syn_mem[i*8 +: 8] = syn_arr[i];
            assign bnd_mem[i*8 +: 8] = bnd_arr[i];
        end
    endgenerate
endmodule
