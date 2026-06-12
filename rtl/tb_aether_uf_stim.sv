// Stim UF co-sim M24: circuit d=3 r=3 (V=392 E=556, max_deg=63). MAX_N/E=600, IDX_W=16, peel MAX_DEG=64.

`timescale 1ns / 1ps

module tb_aether_uf_stim;
    localparam int MAX_N = 600;
    localparam int MAX_E = 600;
    localparam int IDX_W = 16;

    reg clk = 0, rst_n = 0, start_gm = 0, start_peel = 0;
    reg [IDX_W-1:0] num_nodes = 0, num_edges = 0;
    reg [7:0]       syn_mem [0:MAX_N-1];
    reg [7:0]       bnd_mem [0:MAX_N-1];
    reg [IDX_W-1:0] eu_mem  [0:MAX_E-1];
    reg [IDX_W-1:0] ev_mem  [0:MAX_E-1];
    reg [15:0]      cap_mem [0:MAX_E-1];
    reg             exp_solid [0:MAX_E-1];
    reg             exp_corr  [0:MAX_E-1];

    wire done_gm, done_peel;
    wire [31:0] cycles, peel_ops;
    wire solid_bits [0:MAX_E-1];
    wire [MAX_E-1:0] corr_bits;
    wire [MAX_E-1:0]       peel_solid_bits;
    wire [8*MAX_N-1:0]     peel_syn_mem;
    wire [8*MAX_N-1:0]     peel_bnd_mem;
    wire [IDX_W*MAX_E-1:0] peel_eu_mem;
    wire [IDX_W*MAX_E-1:0] peel_ev_mem;

    integer k, fails, mismatch;

    `include "gen/stim_cases.sv"

    aether_uf_grow_merge #(.MAX_N(MAX_N), .MAX_E(MAX_E), .IDX_W(IDX_W)) u_gm (
        .clk(clk), .rst_n(rst_n), .start(start_gm),
        .num_nodes(num_nodes), .num_edges(num_edges),
        .syn_mem(syn_mem), .bnd_mem(bnd_mem),
        .eu_mem(eu_mem), .ev_mem(ev_mem), .cap_mem(cap_mem),
        .done(done_gm), .cycles(cycles), .solid_bits(solid_bits)
    );
    aether_uf_tb_pack_peel_in #(.MAX_N(MAX_N), .MAX_E(MAX_E), .IDX_W(IDX_W)) u_pack (
        .solid_arr(solid_bits),
        .syn_arr(syn_mem), .bnd_arr(bnd_mem),
        .eu_arr(eu_mem), .ev_arr(ev_mem),
        .solid_bits(peel_solid_bits),
        .syn_mem(peel_syn_mem), .bnd_mem(peel_bnd_mem),
        .eu_mem(peel_eu_mem), .ev_mem(peel_ev_mem)
    );
    aether_uf_peel #(.MAX_N(MAX_N), .MAX_E(MAX_E), .MAX_DEG(64), .IDX_W(IDX_W)) u_peel (
        .clk(clk), .rst_n(rst_n), .start(start_peel),
        .num_nodes(num_nodes), .num_edges(num_edges),
        .solid_bits(peel_solid_bits),
        .syn_mem(peel_syn_mem), .bnd_mem(peel_bnd_mem),
        .eu_mem(peel_eu_mem), .ev_mem(peel_ev_mem),
        .done(done_peel), .corr_bits(corr_bits), .peel_ops(peel_ops)
    );

    always #5 clk = ~clk;

    task automatic clear_syn;
        begin
            for (k = 0; k < MAX_N; k = k + 1) syn_mem[k] = 0;
            for (k = 0; k < MAX_E; k = k + 1) begin exp_solid[k]=0; exp_corr[k]=0; end
        end
    endtask

    task automatic run_shot;
        input integer exp_cycles;
        input integer exp_peel_ops;
        begin
            start_gm = 0; start_peel = 0; @(posedge clk);
            num_nodes = STIM_N[IDX_W-1:0];
            num_edges = STIM_M[IDX_W-1:0];
            start_gm = 1; @(posedge clk); start_gm = 0;
            wait (done_gm); @(posedge clk);
            mismatch = 0;
            for (k = 0; k < STIM_M; k = k + 1)
                if (solid_bits[k] !== exp_solid[k]) mismatch = mismatch + 1;
            if (cycles != exp_cycles || mismatch != 0) begin
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
            end else $display("PASS cycles=%0d peel_ops=%0d (V=%0d E=%0d)",
                              cycles, peel_ops, STIM_N, STIM_M);
            @(posedge clk); @(posedge clk);
        end
    endtask

    initial begin
        fails = 0; rst_n = 0; #20; rst_n = 1; #20;
        load_stim_graph();
        `include "gen/stim_run.sv"
        if (fails) begin $display("TOTAL FAILS=%0d", fails); $fatal(1); end
        $display("ALL %0d STIM RTL CASES PASS (V=%0d E=%0d)", STIM_NUM_CASES, STIM_N, STIM_M);
        $finish;
    end
endmodule
