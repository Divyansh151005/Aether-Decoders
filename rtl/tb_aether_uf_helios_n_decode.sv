// M74: Helios-n multiplexed grow (SV lattice) → peel vs M71/M72 oracle goldens.
// Goldens: gen/helios_n_cases.sv from gen_helios_n_rtl_vectors (Stage C + D gated).
// Spec: Docs/Helios_n_Rtl_M74.

`timescale 1ns / 1ps

module tb_aether_uf_helios_n_decode;
    localparam int MAX_N  = 128;
    localparam int MAX_E  = 128;
`ifndef HN_TB_NPHYS
`define HN_TB_NPHYS 16
`endif
`ifndef HN_TB_SLOTS
`define HN_TB_SLOTS 16
`endif
    localparam int N_PHYS = `HN_TB_NPHYS;
    localparam int N_CTX  = 16;
    localparam int SLOTS  = `HN_TB_SLOTS;
    localparam int IDX_W  = 8;
    localparam int PE_W   = 4;
    localparam int CTX_W  = 4;
    localparam int NS     = N_CTX * SLOTS;
    localparam int NW     = N_CTX * N_PHYS;

    reg clk = 0, rst_n = 0, start_gm = 0, start_peel = 0;
    reg [IDX_W-1:0] num_nodes = 0, num_edges = 0;
    reg [CTX_W:0]   num_parts = 0;

    reg [7:0]  syn_mem [0:MAX_N-1];
    reg [7:0]  bnd_mem [0:MAX_N-1];
    reg [15:0] eu_mem  [0:MAX_E-1];
    reg [15:0] ev_mem  [0:MAX_E-1];
    reg [15:0] cap_mem [0:MAX_E-1];
    reg        exp_solid [0:MAX_E-1];
    reg        exp_corr  [0:MAX_E-1];
    reg        sl_valid [0:NS-1];
    reg [15:0] sl_edge  [0:NS-1];
    reg [7:0]  sl_pu    [0:NS-1];
    reg [7:0]  sl_cu    [0:NS-1];
    reg [7:0]  sl_pv    [0:NS-1];
    reg [7:0]  sl_cv    [0:NS-1];
    reg        wb_valid [0:NW-1];
    reg [15:0] wb_virt  [0:NW-1];

    reg [MAX_N-1:0]       syn_vec = 0, bnd_vec = 0;
    reg [IDX_W*MAX_E-1:0] eu_bus = 0, ev_bus = 0;
    reg [NS-1:0]          sl_valid_bus = 0;
    reg [IDX_W*NS-1:0]    sl_edge_bus = 0;
    reg [PE_W*NS-1:0]     sl_pu_bus = 0, sl_pv_bus = 0;
    reg [CTX_W*NS-1:0]    sl_cu_bus = 0, sl_cv_bus = 0;
    reg [16*NS-1:0]       sl_cap_bus = 0;
    reg [NW-1:0]          wb_valid_bus = 0;
    reg [IDX_W*NW-1:0]    wb_virt_bus = 0;

    wire done_gm, done_peel;
    wire [31:0] iters, clk_cycles, peel_ops;
    wire [MAX_E-1:0] solid_pack;
    wire [MAX_E-1:0] corr_bits;
    wire [8*MAX_N-1:0]     peel_syn_mem;
    wire [8*MAX_N-1:0]     peel_bnd_mem;
    wire [IDX_W*MAX_E-1:0] peel_eu_mem;
    wire [IDX_W*MAX_E-1:0] peel_ev_mem;
    wire solid_arr [0:MAX_E-1];
    wire [MAX_E-1:0] peel_solid_unused;
    reg [IDX_W-1:0] eu_peel [0:MAX_E-1];
    reg [IDX_W-1:0] ev_peel [0:MAX_E-1];

    integer k, src, dst, fails, mismatch, guard;
    longint total_clk;
    genvar gi;

    `include "gen/helios_n_cases.sv"

    aether_uf_helios_n_grow #(
        .V(MAX_N), .E(MAX_E), .N_PHYS(N_PHYS), .N_CTX(N_CTX), .SLOTS(SLOTS),
        .IDX_W(IDX_W), .PE_W(PE_W), .CTX_W(CTX_W)
    ) u_hn (
        .clk(clk), .rst_n(rst_n), .start(start_gm),
        .num_nodes(num_nodes), .num_parts(num_parts),
        .syn(syn_vec), .is_bnd(bnd_vec),
        .eu_bus(eu_bus), .ev_bus(ev_bus),
        .sl_valid(sl_valid_bus), .sl_edge(sl_edge_bus),
        .sl_pu(sl_pu_bus), .sl_cu(sl_cu_bus), .sl_pv(sl_pv_bus), .sl_cv(sl_cv_bus),
        .sl_cap(sl_cap_bus),
        .wb_valid(wb_valid_bus), .wb_virt(wb_virt_bus),
        .done(done_gm), .solid_bits(solid_pack),
        .iters(iters), .clk_cycles(clk_cycles)
    );

    generate
        for (gi = 0; gi < MAX_E; gi = gi + 1) begin : g_solid_arr
            assign solid_arr[gi] = solid_pack[gi];
        end
    endgenerate

    aether_uf_tb_pack_peel_in #(.MAX_N(MAX_N), .MAX_E(MAX_E), .IDX_W(IDX_W)) u_pack (
        .solid_arr(solid_arr),
        .syn_arr(syn_mem), .bnd_arr(bnd_mem),
        .eu_arr(eu_peel), .ev_arr(ev_peel),
        .solid_bits(peel_solid_unused),
        .syn_mem(peel_syn_mem), .bnd_mem(peel_bnd_mem),
        .eu_mem(peel_eu_mem), .ev_mem(peel_ev_mem)
    );

    aether_uf_peel #(
        .MAX_N(MAX_N), .MAX_E(MAX_E), .MAX_DEG(16), .IDX_W(IDX_W)
    ) u_peel (
        .clk(clk), .rst_n(rst_n), .start(start_peel),
        .num_nodes(num_nodes), .num_edges(num_edges),
        .solid_bits(solid_pack),
        .syn_mem(peel_syn_mem), .bnd_mem(peel_bnd_mem),
        .eu_mem(peel_eu_mem), .ev_mem(peel_ev_mem),
        .done(done_peel), .corr_bits(corr_bits), .peel_ops(peel_ops)
    );

    always #5 clk = ~clk;

    task automatic clear_tables;
        begin
            for (k = 0; k < MAX_N; k = k + 1) begin syn_mem[k] = 0; bnd_mem[k] = 0; end
            for (k = 0; k < MAX_E; k = k + 1) begin
                eu_mem[k] = 0; ev_mem[k] = 0; cap_mem[k] = 0;
            end
            for (k = 0; k < NS; k = k + 1) begin
                sl_valid[k] = 0; sl_edge[k] = 0;
                sl_pu[k] = 0; sl_cu[k] = 0; sl_pv[k] = 0; sl_cv[k] = 0;
            end
            for (k = 0; k < NW; k = k + 1) begin wb_valid[k] = 0; wb_virt[k] = 0; end
        end
    endtask

    task automatic clear_case;
        begin
            for (k = 0; k < MAX_N; k = k + 1) syn_mem[k] = 0;
            for (k = 0; k < MAX_E; k = k + 1) begin
                exp_solid[k] = 0;
                exp_corr[k] = 0;
            end
        end
    endtask

    task automatic pack_tables;
        begin
            eu_bus = 0; ev_bus = 0; bnd_vec = 0;
            for (k = 0; k < HN_V; k = k + 1) bnd_vec[k] = bnd_mem[k][0];
            for (k = 0; k < HN_E; k = k + 1) begin
                eu_bus[k*IDX_W +: IDX_W] = eu_mem[k][IDX_W-1:0];
                ev_bus[k*IDX_W +: IDX_W] = ev_mem[k][IDX_W-1:0];
                eu_peel[k] = eu_mem[k][IDX_W-1:0];
                ev_peel[k] = ev_mem[k][IDX_W-1:0];
            end
            // Generator rows are k*HN_SLOTS+s / k*HN_NPHYS+p; DUT rows are k*SLOTS+s / k*N_PHYS+p.
            sl_valid_bus = 0; sl_edge_bus = 0; sl_pu_bus = 0; sl_pv_bus = 0;
            sl_cu_bus = 0; sl_cv_bus = 0; sl_cap_bus = 0; wb_valid_bus = 0; wb_virt_bus = 0;
            for (k = 0; k < HN_NPARTS * HN_SLOTS; k = k + 1) begin
                src = k;
                dst = (k / HN_SLOTS) * SLOTS + (k % HN_SLOTS);
                sl_valid_bus[dst] = sl_valid[src];
                sl_edge_bus[dst*IDX_W +: IDX_W] = sl_edge[src][IDX_W-1:0];
                sl_pu_bus[dst*PE_W +: PE_W] = sl_pu[src][PE_W-1:0];
                sl_pv_bus[dst*PE_W +: PE_W] = sl_pv[src][PE_W-1:0];
                sl_cu_bus[dst*CTX_W +: CTX_W] = sl_cu[src][CTX_W-1:0];
                sl_cv_bus[dst*CTX_W +: CTX_W] = sl_cv[src][CTX_W-1:0];
                sl_cap_bus[dst*16 +: 16] = sl_valid[src] ? cap_mem[sl_edge[src]] : 16'd0;
            end
            for (k = 0; k < HN_NPARTS * HN_NPHYS; k = k + 1) begin
                src = k;
                dst = (k / HN_NPHYS) * N_PHYS + (k % HN_NPHYS);
                wb_valid_bus[dst] = wb_valid[src];
                wb_virt_bus[dst*IDX_W +: IDX_W] = wb_virt[src][IDX_W-1:0];
            end
        end
    endtask

    task automatic run_case;
        input integer idx;
        input integer exp_iters;
        input integer exp_peel_ops;
        begin
            syn_vec = 0;
            for (k = 0; k < HN_V; k = k + 1) syn_vec[k] = syn_mem[k][0];
            start_gm = 0; start_peel = 0; @(posedge clk);
            start_gm = 1; @(posedge clk); start_gm = 0;
            guard = 0;
            while (!done_gm && guard < 64 * (exp_iters + 4) * (2 * HN_NPARTS + 2)) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (!done_gm) begin
                $display("FAIL case %0d grow watchdog iters=%0d exp=%0d", idx, iters, exp_iters);
                $fatal(1);
            end
            @(posedge clk);
            mismatch = 0;
            for (k = 0; k < HN_E; k = k + 1)
                if (solid_pack[k] !== exp_solid[k]) mismatch = mismatch + 1;
            if (iters != exp_iters[31:0] || mismatch != 0) begin
                $display("FAIL case %0d grow iters got=%0d exp=%0d solid_mismatches=%0d",
                         idx, iters, exp_iters, mismatch);
                fails = fails + 1;
            end
            // Peel samples packed syn after one settle edge (M59 lock).
            @(posedge clk);
            start_peel = 1; @(posedge clk); start_peel = 0;
            wait (done_peel); @(posedge clk);
            mismatch = 0;
            for (k = 0; k < HN_E; k = k + 1)
                if (corr_bits[k] !== exp_corr[k]) mismatch = mismatch + 1;
            if (mismatch != 0 || peel_ops != exp_peel_ops) begin
                $display("FAIL case %0d peel corr_mismatches=%0d peel_ops got=%0d exp=%0d",
                         idx, mismatch, peel_ops, exp_peel_ops);
                fails = fails + 1;
            end else
                $display("PASS case %0d iters=%0d clk_cycles=%0d peel_ops=%0d",
                         idx, iters, clk_cycles, peel_ops);
            total_clk = total_clk + clk_cycles;
            @(posedge clk); @(posedge clk);
        end
    endtask

    initial begin
        fails = 0; total_clk = 0; rst_n = 0; #20; rst_n = 1; #20;
        if (HN_V > MAX_N || HN_E > MAX_E || HN_NPHYS > N_PHYS ||
            HN_NPARTS > N_CTX || HN_SLOTS > SLOTS) begin
            $display("FAIL tables exceed DUT params V=%0d E=%0d phys=%0d parts=%0d slots=%0d",
                     HN_V, HN_E, HN_NPHYS, HN_NPARTS, HN_SLOTS);
            $fatal(1);
        end
        clear_tables();
        load_hn_graph();
        pack_tables();
        num_nodes = HN_V[IDX_W-1:0];
        num_edges = HN_E[IDX_W-1:0];
        num_parts = HN_NPARTS[CTX_W:0];
        `include "gen/helios_n_run.sv"
        if (fails) begin $display("TOTAL FAILS=%0d", fails); $fatal(1); end
        $display("ALL %0d HELIOS-N DECODE CASES PASS (V=%0d E=%0d parts=%0d phys=%0d slots=%0d) total_clk=%0d",
                 HN_NUM_CASES, HN_V, HN_E, HN_NPARTS, HN_NPHYS, HN_SLOTS, total_clk);
        $finish;
    end
endmodule
