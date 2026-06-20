// M42: Stim phenom d=3 r=1 → PE-mesh edge-list grow (not SoA grow_merge).
// Goldens: helios_pe cycles + solid bits via gen_stim_rtl_vectors.
// Spec: Docs/Pe_Mesh_Stim.

`timescale 1ns / 1ps

module tb_aether_uf_pe_mesh_stim;
    localparam int MAX_N = 128;
    localparam int MAX_E = 128;
    localparam int IDX_W = 8;

    reg clk = 0, rst_n = 0, start_gm = 0;
    reg [IDX_W-1:0] num_nodes = 0, num_edges = 0;
    reg [7:0]       syn_mem [0:MAX_N-1];
    reg [7:0]       bnd_mem [0:MAX_N-1];
    reg [15:0]      eu_mem  [0:MAX_E-1];
    reg [15:0]      ev_mem  [0:MAX_E-1];
    reg [15:0]      cap_mem [0:MAX_E-1];
    reg             exp_solid [0:MAX_E-1];
    reg             exp_corr  [0:MAX_E-1];

    reg [MAX_N-1:0] syn_vec = 0, bnd_vec = 0;
    reg [IDX_W*MAX_E-1:0] eu_bus = 0, ev_bus = 0;
    reg [16*MAX_E-1:0] cap_bus = 0;

    wire done_gm;
    wire [31:0] cycles;
    wire [MAX_E-1:0] solid_pack;
    wire [16*MAX_E-1:0] growth_bus;

    integer k, fails, mismatch;

    `include "gen/stim_cases.sv"

    aether_uf_pe_graph_grow #(
        .N(MAX_N), .M(MAX_E), .CAP(10), .IDX_W(IDX_W)
    ) u_gm (
        .clk(clk), .rst_n(rst_n), .start(start_gm),
        .num_nodes(num_nodes), .num_edges(num_edges),
        .syn(syn_vec), .is_bnd(bnd_vec),
        .eu_bus(eu_bus), .ev_bus(ev_bus), .cap_bus(cap_bus),
        .done(done_gm), .solid_bits(solid_pack),
        .growth_bus(growth_bus), .cycles(cycles)
    );

    always #5 clk = ~clk;

    task automatic clear_syn;
        begin
            for (k = 0; k < MAX_N; k = k + 1) syn_mem[k] = 0;
            for (k = 0; k < MAX_E; k = k + 1) begin
                exp_solid[k] = 0;
                exp_corr[k] = 0;
            end
            syn_vec = 0;
        end
    endtask

    task automatic pack_graph;
        begin
            syn_vec = 0; bnd_vec = 0; eu_bus = 0; ev_bus = 0; cap_bus = 0;
            for (k = 0; k < STIM_N; k = k + 1) begin
                syn_vec[k] = syn_mem[k][0];
                bnd_vec[k] = bnd_mem[k][0];
            end
            for (k = 0; k < STIM_M; k = k + 1) begin
                eu_bus[k*IDX_W +: IDX_W] = eu_mem[k][IDX_W-1:0];
                ev_bus[k*IDX_W +: IDX_W] = ev_mem[k][IDX_W-1:0];
                cap_bus[k*16 +: 16] = cap_mem[k];
            end
        end
    endtask

    task automatic run_shot_grow;
        input integer exp_cycles;
        input integer exp_peel_ops_ignored;
        begin
            start_gm = 0; @(posedge clk);
            num_nodes = STIM_N[IDX_W-1:0];
            num_edges = STIM_M[IDX_W-1:0];
            pack_graph();
            start_gm = 1; @(posedge clk); start_gm = 0;
            wait (done_gm); @(posedge clk);
            mismatch = 0;
            for (k = 0; k < STIM_M; k = k + 1)
                if (solid_pack[k] !== exp_solid[k]) mismatch = mismatch + 1;
            if (cycles != exp_cycles[31:0] || mismatch != 0) begin
                $display("FAIL PE-mesh grow cycles got=%0d exp=%0d solid_mismatches=%0d",
                         cycles, exp_cycles, mismatch);
                fails = fails + 1;
            end else
                $display("PASS PE-mesh grow cycles=%0d (V=%0d E=%0d)",
                         cycles, STIM_N, STIM_M);
            @(posedge clk); @(posedge clk);
        end
    endtask

    // Alias for stim_run.sv which calls run_shot(...)
    task automatic run_shot;
        input integer exp_cycles;
        input integer exp_peel_ops;
        begin
            run_shot_grow(exp_cycles, exp_peel_ops);
        end
    endtask

    initial begin
        fails = 0; rst_n = 0; #20; rst_n = 1; #20;
        if (STIM_N > MAX_N || STIM_M > MAX_E) begin
            $display("FAIL graph V=%0d E=%0d exceeds PE-mesh MAX %0d/%0d",
                     STIM_N, STIM_M, MAX_N, MAX_E);
            $fatal(1);
        end
        load_stim_graph();
        pack_graph();
        `include "gen/stim_run.sv"
        if (fails) begin $display("TOTAL FAILS=%0d", fails); $fatal(1); end
        $display("ALL %0d PE-MESH STIM GROW CASES PASS (V=%0d E=%0d)",
                 STIM_NUM_CASES, STIM_N, STIM_M);
        $finish;
    end
endmodule
