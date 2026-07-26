// M53: H10 ring → PE-mesh grow→peel → obs egress (phenom d=3 r=1).
// Goldens: cycles/solid/corr/peel_ops + C*_OBS ≡ decode_observables.
// Spec: Docs/H10_Obs_Egress.

`timescale 1ns / 1ps

`define STIM_WITH_OBS

module tb_aether_uf_h10_obs_stim;
    localparam int MAX_N = 128;
    localparam int MAX_E = 128;
    localparam int IDX_W = 8;
    localparam int DEPTH = 2;

    reg clk = 0, rst_n = 0, start_gm = 0, start_peel = 0, start_obs = 0;
    reg [IDX_W-1:0] num_nodes = 0, num_edges = 0;
    reg [7:0]       syn_mem [0:MAX_N-1];
    reg [7:0]       bnd_mem [0:MAX_N-1];
    reg [15:0]      eu_mem  [0:MAX_E-1];
    reg [15:0]      ev_mem  [0:MAX_E-1];
    reg [15:0]      cap_mem [0:MAX_E-1];
    reg [63:0]      obs_mask_mem [0:MAX_E-1];
    reg             exp_solid [0:MAX_E-1];
    reg             exp_corr  [0:MAX_E-1];

    reg [MAX_N-1:0] syn_vec = 0, bnd_vec = 0;
    reg [IDX_W*MAX_E-1:0] eu_bus = 0, ev_bus = 0;
    reg [16*MAX_E-1:0] cap_bus = 0;

    wire done_gm, done_peel, done_obs;
    wire [31:0] cycles, peel_ops;
    wire [MAX_E-1:0] solid_pack;
    wire [16*MAX_E-1:0] growth_bus;
    wire [MAX_E-1:0] corr_bits;
    wire [8*MAX_N-1:0]     peel_syn_mem;
    wire [8*MAX_N-1:0]     peel_bnd_mem;
    wire [IDX_W*MAX_E-1:0] peel_eu_mem;
    wire [IDX_W*MAX_E-1:0] peel_ev_mem;
    wire solid_arr [0:MAX_E-1];
    wire [MAX_E-1:0] peel_solid_unused;
    reg [IDX_W-1:0] eu_peel [0:MAX_E-1];
    reg [IDX_W-1:0] ev_peel [0:MAX_E-1];

    reg             wr_valid = 0, rd_ready = 0, obs_ready = 0;
    reg [MAX_N-1:0] wr_data = 0;
    wire            wr_ready, rd_valid, obs_valid;
    wire [MAX_N-1:0] rd_data;
    wire [7:0]      fill_count;
    wire [63:0]     obs_word;
    wire [31:0]     status_peel_ops;
    wire            status_timeout;

    integer k, fails, mismatch;
    genvar gi;

    `include "gen/stim_cases.sv"

    aether_uf_syndrome_ring #(.WIDTH(MAX_N), .DEPTH(DEPTH)) u_ring (
        .clk(clk), .rst_n(rst_n),
        .wr_valid(wr_valid), .wr_ready(wr_ready), .wr_data(wr_data),
        .rd_valid(rd_valid), .rd_ready(rd_ready), .rd_data(rd_data),
        .fill_count(fill_count)
    );

    aether_uf_pe_graph_grow #(.N(MAX_N), .M(MAX_E), .CAP(10), .IDX_W(IDX_W)) u_gm (
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

    aether_uf_peel #(.MAX_N(MAX_N), .MAX_E(MAX_E), .MAX_DEG(16), .IDX_W(IDX_W)) u_peel (
        .clk(clk), .rst_n(rst_n), .start(start_peel),
        .num_nodes(num_nodes), .num_edges(num_edges),
        .solid_bits(solid_pack),
        .syn_mem(peel_syn_mem), .bnd_mem(peel_bnd_mem),
        .eu_mem(peel_eu_mem), .ev_mem(peel_ev_mem),
        .done(done_peel), .corr_bits(corr_bits), .peel_ops(peel_ops)
    );

    aether_uf_obs_egress #(.MAX_E(MAX_E), .IDX_W(IDX_W)) u_obs (
        .clk(clk), .rst_n(rst_n), .start(start_obs),
        .num_edges(num_edges),
        .corr_bits(corr_bits),
        .obs_mask_mem(obs_mask_mem),
        .peel_ops_in(peel_ops),
        .status_timeout_in(1'b0),
        .obs_ready(obs_ready),
        .obs_valid(obs_valid),
        .obs_word(obs_word),
        .status_peel_ops(status_peel_ops),
        .status_timeout(status_timeout),
        .done(done_obs)
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

    task automatic pack_static;
        begin
            bnd_vec = 0; eu_bus = 0; ev_bus = 0; cap_bus = 0;
            for (k = 0; k < STIM_N; k = k + 1)
                bnd_vec[k] = bnd_mem[k][0];
            for (k = 0; k < STIM_M; k = k + 1) begin
                eu_bus[k*IDX_W +: IDX_W] = eu_mem[k][IDX_W-1:0];
                ev_bus[k*IDX_W +: IDX_W] = ev_mem[k][IDX_W-1:0];
                cap_bus[k*16 +: 16] = cap_mem[k];
                eu_peel[k] = eu_mem[k][IDX_W-1:0];
                ev_peel[k] = ev_mem[k][IDX_W-1:0];
            end
        end
    endtask

    task automatic pack_syn_from_mem;
        output reg [MAX_N-1:0] bits;
        begin
            bits = 0;
            for (k = 0; k < STIM_N; k = k + 1)
                bits[k] = syn_mem[k][0];
        end
    endtask

    task automatic host_push_frame;
        input [MAX_N-1:0] frame;
        begin
            @(posedge clk);
            while (!wr_ready) @(posedge clk);
            wr_data = frame;
            wr_valid = 1;
            @(posedge clk);
            wr_valid = 0;
            @(posedge clk);
        end
    endtask

    task automatic decoder_pop_syn;
        begin
            @(posedge clk);
            while (!rd_valid) @(posedge clk);
            syn_vec = rd_data;
            for (k = 0; k < MAX_N; k = k + 1)
                syn_mem[k] = {7'd0, syn_vec[k]};
            rd_ready = 1;
            @(posedge clk);
            rd_ready = 0;
        end
    endtask

    task automatic run_shot;
        input integer exp_cycles;
        input integer exp_peel_ops;
        input [63:0] exp_obs;
        begin
            start_gm = 0; start_peel = 0; start_obs = 0; obs_ready = 0;
            num_nodes = STIM_N[IDX_W-1:0];
            num_edges = STIM_M[IDX_W-1:0];
            decoder_pop_syn();
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
            end
            start_obs = 1; @(posedge clk); start_obs = 0;
            wait (obs_valid); @(posedge clk);
            if (obs_word !== exp_obs || status_timeout !== 1'b0 ||
                status_peel_ops != exp_peel_ops) begin
                $display("FAIL obs got=%h exp=%h timeout=%0d peel_ops=%0d exp_peel=%0d",
                         obs_word, exp_obs, status_timeout, status_peel_ops, exp_peel_ops);
                fails = fails + 1;
            end else begin
                obs_ready = 1; @(posedge clk); obs_ready = 0;
                wait (done_obs); @(posedge clk);
                $display("PASS H10-obs cycles=%0d peel_ops=%0d obs=%h",
                         cycles, peel_ops, obs_word);
            end
            @(posedge clk); @(posedge clk);
        end
    endtask

    reg [MAX_N-1:0] frame0, frame1, frame2, frame3;

    initial begin
        fails = 0;
        rst_n = 0; #20; rst_n = 1; #20;
        if (STIM_N > MAX_N || STIM_M > MAX_E) $fatal(1);
        if (STIM_NUM_CASES < 4) begin
            $display("FAIL need 4 Stim cases");
            $fatal(1);
        end
        load_stim_graph();
        pack_static();

        clear_syn(); load_stim_shot_0(); pack_syn_from_mem(frame0);
        clear_syn(); load_stim_shot_1(); pack_syn_from_mem(frame1);
        clear_syn(); load_stim_shot_2(); pack_syn_from_mem(frame2);
        clear_syn(); load_stim_shot_3(); pack_syn_from_mem(frame3);

        host_push_frame(frame0);
        host_push_frame(frame1);
        // Drain with overlap already filled
        clear_syn(); load_exp_0();
        run_shot(C0_CYCLES, C0_PEEL_OPS, C0_OBS);
        clear_syn(); load_exp_1();
        run_shot(C1_CYCLES, C1_PEEL_OPS, C1_OBS);

        host_push_frame(frame2);
        host_push_frame(frame3);
        clear_syn(); load_exp_2();
        run_shot(C2_CYCLES, C2_PEEL_OPS, C2_OBS);
        clear_syn(); load_exp_3();
        run_shot(C3_CYCLES, C3_PEEL_OPS, C3_OBS);

        if (fails) begin $display("TOTAL FAILS=%0d", fails); $fatal(1); end
        $display("ALL H10 OBS STIM CASES PASS (V=%0d E=%0d NUM_OBS=%0d)",
                 STIM_N, STIM_M, STIM_NUM_OBS);
        $finish;
    end
endmodule
