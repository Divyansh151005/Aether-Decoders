// M28: Stim-scale DPI co-sim (circuit d=3 r=3 class). Live Rust goldens via aether_uf_dpi.

`timescale 1ns / 1ps

module tb_aether_uf_stim_dpi;
    localparam int MAX_N = 600;
    localparam int MAX_E = 600;
    localparam int IDX_W = 16;

    import "DPI-C" function int aether_dpi_stim_prepare(
        input string dem_path, input string shots_path, input int max_cases);
    import "DPI-C" function int aether_dpi_stim_num_cases();
    import "DPI-C" function int aether_dpi_stim_select(input int case_id);
    import "DPI-C" function int aether_dpi_stim_n();
    import "DPI-C" function int aether_dpi_stim_m();
    import "DPI-C" function int aether_dpi_stim_bnd(input int i);
    import "DPI-C" function int aether_dpi_stim_eu(input int e);
    import "DPI-C" function int aether_dpi_stim_ev(input int e);
    import "DPI-C" function int aether_dpi_stim_cap(input int e);
    import "DPI-C" function int aether_dpi_stim_syn(input int i);
    import "DPI-C" function int aether_dpi_stim_exp_cycles();
    import "DPI-C" function int aether_dpi_stim_exp_peel_ops();
    import "DPI-C" function int aether_dpi_stim_exp_solid_bit(input int e);
    import "DPI-C" function int aether_dpi_stim_exp_corr_bit(input int e);

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

    integer k, fails, mismatch, ncases, cid, n, m, exp_cycles, exp_peel;

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

    task automatic load_graph_from_dpi;
        begin
            n = aether_dpi_stim_n();
            m = aether_dpi_stim_m();
            if (n > MAX_N || m > MAX_E) begin
                $display("FAIL graph V=%0d E=%0d exceeds MAX", n, m);
                $fatal(1);
            end
            for (k = 0; k < n; k = k + 1) bnd_mem[k] = aether_dpi_stim_bnd(k);
            for (k = 0; k < m; k = k + 1) begin
                eu_mem[k]  = aether_dpi_stim_eu(k);
                ev_mem[k]  = aether_dpi_stim_ev(k);
                cap_mem[k] = aether_dpi_stim_cap(k);
            end
            num_nodes = n[IDX_W-1:0];
            num_edges = m[IDX_W-1:0];
        end
    endtask

    task automatic load_shot_from_dpi;
        begin
            for (k = 0; k < MAX_N; k = k + 1) syn_mem[k] = 0;
            for (k = 0; k < MAX_E; k = k + 1) begin exp_solid[k]=0; exp_corr[k]=0; end
            for (k = 0; k < n; k = k + 1) syn_mem[k] = aether_dpi_stim_syn(k);
            for (k = 0; k < m; k = k + 1) begin
                exp_solid[k] = aether_dpi_stim_exp_solid_bit(k)[0];
                exp_corr[k]  = aether_dpi_stim_exp_corr_bit(k)[0];
            end
            exp_cycles = aether_dpi_stim_exp_cycles();
            exp_peel   = aether_dpi_stim_exp_peel_ops();
        end
    endtask

    task automatic run_shot;
        begin
            start_gm = 0; start_peel = 0; @(posedge clk);
            start_gm = 1; @(posedge clk); start_gm = 0;
            wait (done_gm); @(posedge clk);
            mismatch = 0;
            for (k = 0; k < m; k = k + 1)
                if (solid_bits[k] !== exp_solid[k]) mismatch = mismatch + 1;
            if (cycles != exp_cycles || mismatch != 0) begin
                $display("FAIL case=%0d grow cycles=%0d/%0d solid_mismatches=%0d",
                         cid, cycles, exp_cycles, mismatch);
                fails = fails + 1;
            end
            start_peel = 1; @(posedge clk); start_peel = 0;
            wait (done_peel); @(posedge clk);
            mismatch = 0;
            for (k = 0; k < m; k = k + 1)
                if (corr_bits[k] !== exp_corr[k]) mismatch = mismatch + 1;
            if (mismatch != 0 || peel_ops != exp_peel) begin
                $display("FAIL case=%0d peel corr_mismatches=%0d ops=%0d/%0d",
                         cid, mismatch, peel_ops, exp_peel);
                fails = fails + 1;
            end else $display("PASS DPI-STIM case=%0d cycles=%0d peel_ops=%0d (V=%0d E=%0d)",
                              cid, cycles, peel_ops, n, m);
            @(posedge clk); @(posedge clk);
        end
    endtask

    initial begin
        fails = 0; rst_n = 0; #20; rst_n = 1; #20;
        // Paths relative to rtl/ (harness cwd).
        if (aether_dpi_stim_prepare("gen/dpi_stim_dem.json", "gen/dpi_stim_shots.txt", 2) != 0)
            $fatal(1, "DPI stim prepare failed");
        ncases = aether_dpi_stim_num_cases();
        if (ncases <= 0) $fatal(1, "no DPI stim cases");
        load_graph_from_dpi();
        for (cid = 0; cid < ncases; cid = cid + 1) begin
            if (aether_dpi_stim_select(cid) != 0) $fatal(1, "select %0d", cid);
            load_shot_from_dpi();
            run_shot();
        end
        if (fails) begin $display("TOTAL STIM DPI FAILS=%0d", fails); $fatal(1); end
        $display("ALL %0d STIM DPI CASES PASS (V=%0d E=%0d)", ncases, n, m);
        $finish;
    end
endmodule
