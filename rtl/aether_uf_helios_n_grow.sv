// Aether UF — Helios-n multiplexed grow (M74).
//
// Physical lattice (`aether_uf_helios_n_lattice`): N_PHYS PEs x N_CTX LUTRAM
// contexts of {cid, cluster_active} per virtual node, plus per-(part, slot)
// growth banks. One part is grown per clock (context = part index, Helios
// 1-cycle switch); cross-cut edges read the colocated neighbor context on the
// same physical PE (M70 map).
// Merge stays a central ordered union-by-size over the virtual SoA (same order
// and tie rule as `DecoderGraph::union`); cid/active are written back to the
// lattice one part per clock.
//
// Golden: M71/M72 software oracle (`src/helios_n_pe.rs`).
// Spec: Docs/Helios_n_Rtl_M74; Docs/Helios_n_Schedule_M69; Helios arXiv:2406.08491.

`timescale 1ns / 1ps

module aether_uf_helios_n_grow #(
    parameter int V      = 128,
    parameter int E      = 128,
    parameter int N_PHYS = 16,
    parameter int N_CTX  = 16,
    parameter int SLOTS  = 16,
    parameter int IDX_W  = 8,
    parameter int PE_W   = (N_PHYS <= 2) ? 1 : $clog2(N_PHYS),
    parameter int CTX_W  = (N_CTX <= 2) ? 1 : $clog2(N_CTX),
    parameter int NS     = N_CTX * SLOTS,
    parameter int NW     = N_CTX * N_PHYS
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  start,
    input  wire [IDX_W-1:0]      num_nodes,
    input  wire [CTX_W:0]        num_parts,
    input  wire [V-1:0]          syn,
    input  wire [V-1:0]          is_bnd,
    input  wire [IDX_W*E-1:0]    eu_bus,
    input  wire [IDX_W*E-1:0]    ev_bus,
    // Static schedule tables (compiled from the M70 map; BRAM/ROM class).
    input  wire [NS-1:0]         sl_valid,
    input  wire [IDX_W*NS-1:0]   sl_edge,
    input  wire [PE_W*NS-1:0]    sl_pu,
    input  wire [CTX_W*NS-1:0]   sl_cu,
    input  wire [PE_W*NS-1:0]    sl_pv,
    input  wire [CTX_W*NS-1:0]   sl_cv,
    input  wire [16*NS-1:0]      sl_cap,
    input  wire [NW-1:0]         wb_valid,
    input  wire [IDX_W*NW-1:0]   wb_virt,
    output reg                   done,
    output wire [E-1:0]          solid_bits,
    output reg  [31:0]           iters,
    output reg  [31:0]           clk_cycles
);
    localparam S_IDLE  = 3'd0;
    localparam S_INIT  = 3'd1;
    localparam S_WB    = 3'd2;
    localparam S_CHECK = 3'd3;
    localparam S_GROW  = 3'd4;
    localparam S_MERGE = 3'd5;
    localparam S_DONE  = 3'd6;

    reg [2:0]       state;
    reg [CTX_W-1:0] cur_k;
    wire last_part = ({1'b0, cur_k} == num_parts - 1'b1);

    // ---- Central merge unit (virtual SoA) ----
    reg [IDX_W-1:0] root    [0:V-1];
    reg [15:0]      size    [0:V-1];
    reg             parity  [0:V-1];
    reg             cbound  [0:V-1];
    reg             is_root [0:V-1];
    reg [IDX_W-1:0] froot   [0:V-1];
    reg             fact    [0:V-1];
    reg             new_solid [0:E-1];
    reg             solid_g   [0:E-1];

    genvar gi;
    generate
        for (gi = 0; gi < E; gi = gi + 1) begin : g_solid_out
            assign solid_bits[gi] = solid_g[gi];
        end
    endgenerate

    wire [V-1:0] act_bus;
    generate
        for (gi = 0; gi < V; gi = gi + 1) begin : g_act
            assign act_bus[gi] = is_root[gi] && parity[gi] && !cbound[gi] &&
                                 (gi[IDX_W-1:0] < num_nodes);
        end
    endgenerate
    wire any_active = |act_bus;

    // ---- Physical lattice (context banks + slot growth) ----
    wire [N_PHYS-1:0]       wb_we;
    wire [IDX_W*N_PHYS-1:0] wb_cid;
    wire [N_PHYS-1:0]       wb_act;
    generate
        for (gi = 0; gi < N_PHYS; gi = gi + 1) begin : g_wb
            wire [CTX_W+15:0] wi = cur_k * N_PHYS + gi;
            wire [IDX_W-1:0]  wr = wb_virt[wi*IDX_W +: IDX_W];
            assign wb_we[gi] = wb_valid[wi];
            assign wb_cid[gi*IDX_W +: IDX_W] = froot[wr];
            assign wb_act[gi] = fact[wr];
        end
    endgenerate

    wire [SLOTS-1:0]       s_solid_now;
    wire [IDX_W*SLOTS-1:0] s_edge_out;
    aether_uf_helios_n_lattice #(
        .N_PHYS(N_PHYS), .N_CTX(N_CTX), .SLOTS(SLOTS), .IDX_W(IDX_W),
        .PE_W(PE_W), .CTX_W(CTX_W), .NS(NS)
    ) u_lattice (
        .clk(clk), .rst_n(rst_n),
        .clear(state == S_INIT),
        .ctx(cur_k),
        .wb_en(state == S_WB), .wb_we(wb_we), .wb_cid(wb_cid), .wb_act(wb_act),
        .grow_en(state == S_GROW),
        .sl_valid(sl_valid), .sl_edge(sl_edge), .sl_pu(sl_pu), .sl_cu(sl_cu),
        .sl_pv(sl_pv), .sl_cv(sl_cv), .sl_cap(sl_cap),
        .s_solid_now(s_solid_now), .s_edge_out(s_edge_out)
    );

    // ---- Merge helpers (blocking work copies) ----
    reg [IDX_W-1:0] w_root    [0:V-1];
    reg [15:0]      w_size    [0:V-1];
    reg             w_parity  [0:V-1];
    reg             w_cbound  [0:V-1];
    reg             w_is_root [0:V-1];
    integer i, e, s, r;

    task automatic find_root;
        input integer v;
        output integer rr;
        integer guard;
        begin
            rr = v;
            for (guard = 0; guard < V; guard = guard + 1) begin
                if (w_is_root[rr]) guard = V;
                else rr = w_root[rr];
            end
        end
    endtask

    task automatic do_union;
        input integer uu;
        input integer vv;
        integer ru, rv, tmp;
        begin
            find_root(uu, ru);
            find_root(vv, rv);
            if (ru != rv) begin
                if (w_size[ru] < w_size[rv]) begin
                    tmp = ru; ru = rv; rv = tmp;
                end
                w_root[rv]    = ru[IDX_W-1:0];
                w_is_root[rv] = 1'b0;
                w_size[ru]    = w_size[ru] + w_size[rv];
                w_parity[ru]  = w_parity[ru] ^ w_parity[rv];
                w_cbound[ru]  = w_cbound[ru] | w_cbound[rv];
                w_parity[rv]  = 1'b0;
                w_cbound[rv]  = 1'b0;
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done <= 1'b0;
            cur_k <= {CTX_W{1'b0}};
            iters <= 32'd0;
            clk_cycles <= 32'd0;
            for (i = 0; i < V; i = i + 1) begin
                root[i] <= i[IDX_W-1:0];
                size[i] <= 16'd1;
                parity[i] <= 1'b0;
                cbound[i] <= 1'b0;
                is_root[i] <= 1'b0;
                froot[i] <= i[IDX_W-1:0];
                fact[i] <= 1'b0;
            end
            for (e = 0; e < E; e = e + 1) begin
                new_solid[e] <= 1'b0;
                solid_g[e] <= 1'b0;
            end
        end else begin
            if (state != S_IDLE && state != S_DONE)
                clk_cycles <= clk_cycles + 32'd1;
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        iters <= 32'd0;
                        clk_cycles <= 32'd0;
                        state <= S_INIT;
                    end
                end
                S_INIT: begin
                    for (i = 0; i < V; i = i + 1) begin
                        root[i] <= i[IDX_W-1:0];
                        size[i] <= 16'd1;
                        froot[i] <= i[IDX_W-1:0];
                        if (i[IDX_W-1:0] < num_nodes) begin
                            parity[i] <= syn[i];
                            cbound[i] <= is_bnd[i];
                            is_root[i] <= 1'b1;
                            fact[i] <= syn[i] && !is_bnd[i];
                        end else begin
                            parity[i] <= 1'b0;
                            cbound[i] <= 1'b0;
                            is_root[i] <= 1'b0;
                            fact[i] <= 1'b0;
                        end
                    end
                    for (e = 0; e < E; e = e + 1) begin
                        new_solid[e] <= 1'b0;
                        solid_g[e] <= 1'b0;
                    end
                    cur_k <= {CTX_W{1'b0}};
                    state <= S_WB;
                end
                S_WB: begin
                    // Lattice writes cid / cluster-active into context cur_k of every PE.
                    if (last_part) begin
                        cur_k <= {CTX_W{1'b0}};
                        state <= S_CHECK;
                    end else
                        cur_k <= cur_k + 1'b1;
                end
                S_CHECK: begin
                    if (!any_active) begin
                        done <= 1'b1;
                        state <= S_DONE;
                    end else begin
                        iters <= iters + 32'd1;
                        cur_k <= {CTX_W{1'b0}};
                        state <= S_GROW;
                    end
                end
                S_GROW: begin
                    for (s = 0; s < SLOTS; s = s + 1) begin
                        if (s_solid_now[s]) begin
                            new_solid[s_edge_out[s*IDX_W +: IDX_W]] <= 1'b1;
                            solid_g[s_edge_out[s*IDX_W +: IDX_W]] <= 1'b1;
                        end
                    end
                    if (last_part) begin
                        cur_k <= {CTX_W{1'b0}};
                        state <= S_MERGE;
                    end else
                        cur_k <= cur_k + 1'b1;
                end
                S_MERGE: begin
                    for (i = 0; i < V; i = i + 1) begin
                        w_root[i]    = root[i];
                        w_size[i]    = size[i];
                        w_parity[i]  = parity[i];
                        w_cbound[i]  = cbound[i];
                        w_is_root[i] = is_root[i];
                    end
                    for (e = 0; e < E; e = e + 1) begin
                        if (new_solid[e])
                            do_union(eu_bus[e*IDX_W +: IDX_W], ev_bus[e*IDX_W +: IDX_W]);
                        new_solid[e] <= 1'b0;
                    end
                    for (i = 0; i < V; i = i + 1) begin
                        root[i]    <= w_root[i];
                        size[i]    <= w_size[i];
                        parity[i]  <= w_parity[i];
                        cbound[i]  <= w_cbound[i];
                        is_root[i] <= w_is_root[i];
                        if (i[IDX_W-1:0] < num_nodes) begin
                            find_root(i, r);
                            froot[i] <= r[IDX_W-1:0];
                            fact[i]  <= w_parity[r] && !w_cbound[r];
                        end
                    end
                    cur_k <= {CTX_W{1'b0}};
                    state <= S_WB;
                end
                S_DONE: begin
                    done <= 1'b1;
                    if (!start)
                        state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
