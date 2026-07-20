// M43/M45: Stim PE-mesh grow → peel (phenom d=3 r=1 or r=3 via stim_cases).
// Goldens: helios_pe cycles/solid + decode_cosim corr/peel_ops.
// Spec: Docs/Pe_Mesh_Stim_Decode; Docs/Pe_Mesh_Stim_R3_Decode (r=3).

`timescale 1ns / 1ps

module tb_aether_uf_pe_mesh_stim_decode;
    localparam int MAX_N = 128;
    localparam int MAX_E = 128;
    localparam int IDX_W = 8;

    reg clk = 0, rst_n = 0, start_gm = 0, start_peel = 0;
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

    wire done_gm, done_peel;
    wire [31:0] cycles;
    wire [31:0] peel_ops;
    wire [MAX_E-1:0] solid_pack;
    wire [16*MAX_E-1:0] growth_bus;
    wire [MAX_E-1:0] corr_bits;
    wire [8*MAX_N-1:0]     peel_syn_mem;
    wire [8*MAX_N-1:0]     peel_bnd_mem;
    wire [IDX_W*MAX_E-1:0] peel_eu_mem;
    wire [IDX_W*MAX_E-1:0] peel_ev_mem;
    wire solid_arr [0:MAX_E-1];
    wire [MAX_E-1:0] peel_solid_unused;

    // Peel endpoint memories (IDX_W-wide)
    reg [IDX_W-1:0] eu_peel [0:MAX_E-1];
    reg [IDX_W-1:0] ev_peel [0:MAX_E-1];

    integer k, fails, mismatch;
    genvar gi;

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
                eu_peel[k] = eu_mem[k][IDX_W-1:0];
                ev_peel[k] = ev_mem[k][IDX_W-1:0];
            end
        end
    endtask

    task automatic run_shot;
        input integer exp_cycles;
        input integer exp_peel_ops;
        begin
            start_gm = 0; start_peel = 0; @(posedge clk);
            num_nodes = STIM_N[IDX_W-1:0];
            num_edges = STIM_M[IDX_W-1:0];
            pack_graph();
            start_gm = 1; @(posedge clk); start_gm = 0;
            wait (done_gm); @(posedge clk);
            mismatch = 0;
            for (k = 0; k < STIM_M; k = k + 1)
                if (solid_pack[k] !== exp_solid[k]) mismatch = mismatch + 1;
            if (cycles != exp_cycles[31:0] || mismatch != 0) begin
                $display("FAIL grow cycles got=%0d exp=%0d solid_mismatches=%0d",
                         cycles, exp_cycles, mismatch);
                fails = fails + 1;
            end
            start_peel = 1; @(posedge clk); start_peel = 0;
            wait (done_peel); @(posedge clk);
            mismatch = 0;
            for (k = 0; k < STIM_M; k = k + 1)
                if (corr_bits[k] !== exp_corr[k]) mismatch = mismatch + 1;
            if (mismatch != 0 || peel_ops != exp_peel_ops) begin
                $display("FAIL peel corr_mismatches=%0d peel_ops got=%0d exp=%0d",
                         mismatch, peel_ops, exp_peel_ops);
                fails = fails + 1;
            end else
                $display("PASS PE-mesh decode cycles=%0d peel_ops=%0d (V=%0d E=%0d)",
                         cycles, peel_ops, STIM_N, STIM_M);
            @(posedge clk); @(posedge clk);
        end
    endtask

    initial begin
        fails = 0; rst_n = 0; #20; rst_n = 1; #20;
        if (STIM_N > MAX_N || STIM_M > MAX_E) begin
            $display("FAIL graph V=%0d E=%0d exceeds MAX %0d/%0d",
                     STIM_N, STIM_M, MAX_N, MAX_E);
            $fatal(1);
        end
        load_stim_graph();
        pack_graph();
        `include "gen/stim_run.sv"
        if (fails) begin $display("TOTAL FAILS=%0d", fails); $fatal(1); end
        $display("ALL %0d PE-MESH STIM DECODE CASES PASS (V=%0d E=%0d)",
                 STIM_NUM_CASES, STIM_N, STIM_M);
        $finish;
    end
endmodule
