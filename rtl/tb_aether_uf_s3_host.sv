// M75 G4: S3 host path (ring → grow → peel → obs) vs Stim goldens (phenom d=3 r=1).
// Same TB drives RTL or the Yosys synth_xilinx netlist (+ cells_sim.v).
// Spec: Docs/G4_S3_Netlist_M75.

`timescale 1ns / 1ps

`define STIM_WITH_OBS

module tb_aether_uf_s3_host;
    localparam int MAX_N = 16;
    localparam int MAX_E = 18;

    reg clk = 0, rst_n = 0;
    reg [7:0]  syn_mem [0:MAX_N-1];
    reg [7:0]  bnd_mem [0:MAX_N-1];
    reg [15:0] eu_mem  [0:MAX_E-1];
    reg [15:0] ev_mem  [0:MAX_E-1];
    reg [15:0] cap_mem [0:MAX_E-1];
    reg [63:0] obs_mask_mem [0:MAX_E-1];
    reg        exp_solid [0:MAX_E-1];
    reg        exp_corr  [0:MAX_E-1];

    reg  [15:0]   is_bnd = 0;
    reg  [143:0]  eu_bus = 0, ev_bus = 0;
    reg  [287:0]  cap_bus = 0;
    reg  [1151:0] obs_mask_bus = 0;
    reg           wr_valid = 0, obs_ready = 0;
    reg  [15:0]   wr_data = 0;
    wire          wr_ready, obs_valid;
    wire [63:0]   obs_word;
    wire [31:0]   status_peel_ops, status_cycles;
    wire [17:0]   status_corr;

    integer k, fails, mismatch, guard;

    `include "gen/s3_host_cases.sv"

    aether_uf_s3_host_top dut (
        .clk(clk), .rst_n(rst_n),
        .wr_valid(wr_valid), .wr_ready(wr_ready), .wr_data(wr_data),
        .num_nodes(STIM_N[7:0]), .num_edges(STIM_M[7:0]),
        .is_bnd(is_bnd), .eu_bus(eu_bus), .ev_bus(ev_bus), .cap_bus(cap_bus),
        .obs_mask_bus(obs_mask_bus),
        .obs_ready(obs_ready), .obs_valid(obs_valid), .obs_word(obs_word),
        .status_peel_ops(status_peel_ops), .status_cycles(status_cycles),
        .status_corr(status_corr)
    );

    always #5 clk = ~clk;

    task automatic clear_case;
        begin
            for (k = 0; k < MAX_N; k = k + 1) syn_mem[k] = 0;
            for (k = 0; k < MAX_E; k = k + 1) begin
                exp_solid[k] = 0;
                exp_corr[k] = 0;
            end
        end
    endtask

    task automatic pack_static;
        begin
            for (k = 0; k < STIM_N; k = k + 1) is_bnd[k] = bnd_mem[k][0];
            for (k = 0; k < STIM_M; k = k + 1) begin
                eu_bus[k*8 +: 8] = eu_mem[k][7:0];
                ev_bus[k*8 +: 8] = ev_mem[k][7:0];
                cap_bus[k*16 +: 16] = cap_mem[k];
                obs_mask_bus[k*64 +: 64] = obs_mask_mem[k];
            end
        end
    endtask

    task automatic run_shot;
        input integer idx;
        input integer exp_cycles;
        input integer exp_peel_ops;
        input [63:0] exp_obs;
        begin
            @(negedge clk);
            while (!wr_ready) @(negedge clk);
            for (k = 0; k < STIM_N; k = k + 1) wr_data[k] = syn_mem[k][0];
            wr_valid = 1;
            @(negedge clk);
            wr_valid = 0;
            guard = 0;
            while (!obs_valid && guard < 64 * exp_cycles + 4096) begin
                @(negedge clk);
                guard = guard + 1;
            end
            mismatch = 0;
            for (k = 0; k < STIM_M; k = k + 1)
                if (status_corr[k] !== exp_corr[k]) mismatch = mismatch + 1;
            if (!obs_valid || obs_word !== exp_obs || status_cycles != exp_cycles ||
                status_peel_ops != exp_peel_ops || mismatch != 0) begin
                $display("FAIL case %0d valid=%0d obs=%h exp=%h cycles=%0d exp=%0d peel_ops=%0d exp=%0d corr_mm=%0d",
                         idx, obs_valid, obs_word, exp_obs, status_cycles, exp_cycles,
                         status_peel_ops, exp_peel_ops, mismatch);
                fails = fails + 1;
            end else
                $display("PASS case %0d cycles=%0d peel_ops=%0d obs=%h",
                         idx, status_cycles, status_peel_ops, obs_word);
            obs_ready = 1;
            @(negedge clk);
            obs_ready = 0;
            repeat (4) @(negedge clk);
        end
    endtask

    initial begin
        fails = 0;
        rst_n = 0; #40; rst_n = 1; #20;
        if (STIM_N > MAX_N || STIM_M > MAX_E) begin
            $display("FAIL graph V=%0d E=%0d exceeds S3 top", STIM_N, STIM_M);
            $fatal(1);
        end
        load_stim_graph();
        pack_static();
        `include "gen/s3_host_run.sv"
        if (fails) begin $display("TOTAL FAILS=%0d", fails); $fatal(1); end
        $display("ALL %0d S3 HOST-PATH CASES PASS (V=%0d E=%0d)", STIM_NUM_CASES, STIM_N, STIM_M);
        $finish;
    end
endmodule
