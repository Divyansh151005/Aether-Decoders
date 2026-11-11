// Aether UF — Helios-n physical lattice (M74).
//
// N_PHYS PEs, each with an N_CTX-deep context bank of {cid, cluster_active}
// (one write port: writeback of context `ctx`). Per-slot growth banks are
// N_CTX deep (one write per clock: the part on the lattice). Growth/solid are
// cleared in one cycle via FF masks (`touched`, `solid`), so the banks carry no
// reset and stay LUTRAM-class. Cross-cut edges read the colocated neighbor
// context (pv, cv) on the same physical PE (M70 map).
//
// Spec: Docs/Helios_n_Rtl_M74; Helios arXiv:2406.08491 (multi-context PEs).

`timescale 1ns / 1ps

module aether_uf_helios_n_lattice #(
    parameter int N_PHYS = 16,
    parameter int N_CTX  = 16,
    parameter int SLOTS  = 16,
    parameter int IDX_W  = 8,
    parameter int PE_W   = (N_PHYS <= 2) ? 1 : $clog2(N_PHYS),
    parameter int CTX_W  = (N_CTX <= 2) ? 1 : $clog2(N_CTX),
    parameter int NS     = N_CTX * SLOTS
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear,
    input  wire [CTX_W-1:0]         ctx,
    input  wire                     wb_en,
    input  wire [N_PHYS-1:0]        wb_we,
    input  wire [IDX_W*N_PHYS-1:0]  wb_cid,
    input  wire [N_PHYS-1:0]        wb_act,
    input  wire                     grow_en,
    input  wire [NS-1:0]            sl_valid,
    input  wire [IDX_W*NS-1:0]      sl_edge,
    input  wire [PE_W*NS-1:0]       sl_pu,
    input  wire [CTX_W*NS-1:0]      sl_cu,
    input  wire [PE_W*NS-1:0]       sl_pv,
    input  wire [CTX_W*NS-1:0]      sl_cv,
    input  wire [16*NS-1:0]         sl_cap,
    output wire [SLOTS-1:0]         s_solid_now,
    output wire [IDX_W*SLOTS-1:0]   s_edge_out
);
    genvar gp, gs;

    // ---- Context banks: per PE, per slot read port pair ----
    wire [IDX_W-1:0] rd_cid_u [0:N_PHYS-1][0:SLOTS-1];
    wire [IDX_W-1:0] rd_cid_v [0:N_PHYS-1][0:SLOTS-1];
    wire             rd_act_u [0:N_PHYS-1][0:SLOTS-1];
    wire             rd_act_v [0:N_PHYS-1][0:SLOTS-1];

    generate
        for (gp = 0; gp < N_PHYS; gp = gp + 1) begin : g_pe
            (* ram_style = "distributed" *) reg [IDX_W:0] bank [0:N_CTX-1];
            integer k;
            initial for (k = 0; k < N_CTX; k = k + 1) bank[k] = '0;
            always @(posedge clk)
                if (wb_en && wb_we[gp])
                    bank[ctx] <= {wb_act[gp], wb_cid[gp*IDX_W +: IDX_W]};
            for (gs = 0; gs < SLOTS; gs = gs + 1) begin : g_rd
                wire [CTX_W-1:0] cu = sl_cu[(ctx*SLOTS + gs)*CTX_W +: CTX_W];
                wire [CTX_W-1:0] cv = sl_cv[(ctx*SLOTS + gs)*CTX_W +: CTX_W];
                assign {rd_act_u[gp][gs], rd_cid_u[gp][gs]} = bank[cu];
                assign {rd_act_v[gp][gs], rd_cid_v[gp][gs]} = bank[cv];
            end
        end
    endgenerate

    // ---- Growth banks (per slot) + one-cycle clear masks ----
    reg [NS-1:0] touched;
    reg [NS-1:0] solid;
    wire [SLOTS-1:0] s_grow;
    wire [15:0]      s_gnext [0:SLOTS-1];

    generate
        for (gs = 0; gs < SLOTS; gs = gs + 1) begin : g_slot
            (* ram_style = "distributed" *) reg [15:0] gbank [0:N_CTX-1];
            integer k;
            initial for (k = 0; k < N_CTX; k = k + 1) gbank[k] = 16'd0;

            wire [CTX_W+15:0] idx = ctx * SLOTS + gs;
            wire [PE_W-1:0]  pu  = sl_pu[idx*PE_W +: PE_W];
            wire [PE_W-1:0]  pv  = sl_pv[idx*PE_W +: PE_W];
            wire [15:0]      cap = sl_cap[idx*16 +: 16];
            wire [IDX_W-1:0] cid_u = rd_cid_u[pu][gs];
            wire [IDX_W-1:0] cid_v = rd_cid_v[pv][gs];
            wire             act_u = rd_act_u[pu][gs];
            wire             act_v = rd_act_v[pv][gs];
            wire same = (cid_u == cid_v);
            wire [1:0] delta = {1'b0, act_u & ~same} + {1'b0, act_v & ~same};
            wire [15:0] gcur = touched[idx] ? gbank[ctx] : 16'd0;

            assign s_grow[gs]  = sl_valid[idx] && !solid[idx] && (delta != 2'd0);
            assign s_gnext[gs] = gcur + {14'd0, delta};
            assign s_solid_now[gs] = s_grow[gs] && (s_gnext[gs] >= cap);
            assign s_edge_out[gs*IDX_W +: IDX_W] = sl_edge[idx*IDX_W +: IDX_W];

            always @(posedge clk)
                if (grow_en && s_grow[gs])
                    gbank[ctx] <= s_gnext[gs];
        end
    endgenerate

    integer s;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            touched <= '0;
            solid   <= '0;
        end else if (clear) begin
            touched <= '0;
            solid   <= '0;
        end else if (grow_en) begin
            for (s = 0; s < SLOTS; s = s + 1)
                if (s_grow[s]) begin
                    touched[ctx*SLOTS + s] <= 1'b1;
                    if (s_solid_now[s])
                        solid[ctx*SLOTS + s] <= 1'b1;
                end
        end
    end
endmodule
