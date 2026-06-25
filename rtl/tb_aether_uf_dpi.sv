// M26: DPI-driven Blueprint grow→peel co-sim (Verilator + Rust cdylib).
// Goldens from live aether_dpi_load → decode_cosim / helios_pe (Docs/Rtl_Dpi_Research).

`timescale 1ns / 1ps

module tb_aether_uf_dpi;
    localparam int MAX_N = 8;
    localparam int MAX_E = 8;
    localparam int IDX_W = 16;

    import "DPI-C" function int aether_dpi_num_cases();
    import "DPI-C" function int aether_dpi_load(input int case_id);
    import "DPI-C" function int aether_dpi_n();
    import "DPI-C" function int aether_dpi_m();
    import "DPI-C" function int aether_dpi_syn(input int i);
    import "DPI-C" function int aether_dpi_bnd(input int i);
    import "DPI-C" function int aether_dpi_eu(input int e);
    import "DPI-C" function int aether_dpi_ev(input int e);
    import "DPI-C" function int aether_dpi_cap(input int e);
    import "DPI-C" function int aether_dpi_exp_cycles();
    import "DPI-C" function int aether_dpi_exp_solid();
    import "DPI-C" function int aether_dpi_exp_corr();
    import "DPI-C" function int aether_dpi_exp_peel_ops();

    reg clk = 0, rst_n = 0, start_gm = 0, start_peel = 0;
    reg [IDX_W-1:0] num_nodes = 0, num_edges = 0;
    reg [7:0]       syn_mem [0:MAX_N-1];
    reg [7:0]       bnd_mem [0:MAX_N-1];
    reg [IDX_W-1:0] eu_mem  [0:MAX_E-1];
    reg [IDX_W-1:0] ev_mem  [0:MAX_E-1];
    reg [15:0]      cap_mem [0:MAX_E-1];

    wire done_gm, done_peel;
    wire [31:0] cycles, peel_ops;
    wire solid_bits [0:MAX_E-1];
    wire [MAX_E-1:0] corr_bits;
    wire [MAX_E-1:0]       peel_solid_bits;
    wire [8*MAX_N-1:0]     peel_syn_mem;
    wire [8*MAX_N-1:0]     peel_bnd_mem;
    wire [IDX_W*MAX_E-1:0] peel_eu_mem;
    wire [IDX_W*MAX_E-1:0] peel_ev_mem;

    integer k, fails, ncases, cid, n, m, exp_cycles, exp_solid, exp_corr, exp_peel;
    reg [63:0] solid_pack, corr_pack;

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
    aether_uf_peel #(.MAX_N(MAX_N), .MAX_E(MAX_E), .IDX_W(IDX_W)) u_peel (
        .clk(clk), .rst_n(rst_n), .start(start_peel),
        .num_nodes(num_nodes), .num_edges(num_edges),
        .solid_bits(peel_solid_bits),
        .syn_mem(peel_syn_mem), .bnd_mem(peel_bnd_mem),
        .eu_mem(peel_eu_mem), .ev_mem(peel_ev_mem),
        .done(done_peel), .corr_bits(corr_bits), .peel_ops(peel_ops)
    );

    always #5 clk = ~clk;

    task automatic clear_mem;
        begin
            for (k = 0; k < MAX_N; k = k + 1) begin syn_mem[k]=0; bnd_mem[k]=0; end
            for (k = 0; k < MAX_E; k = k + 1) begin eu_mem[k]=0; ev_mem[k]=0; cap_mem[k]=0; end
        end
    endtask

    task automatic load_from_dpi;
        begin
            n = aether_dpi_n();
            m = aether_dpi_m();
            for (k = 0; k < n; k = k + 1) begin
                syn_mem[k] = aether_dpi_syn(k);
                bnd_mem[k] = aether_dpi_bnd(k);
            end
            for (k = 0; k < m; k = k + 1) begin
                eu_mem[k]  = aether_dpi_eu(k);
                ev_mem[k]  = aether_dpi_ev(k);
                cap_mem[k] = aether_dpi_cap(k);
            end
            exp_cycles = aether_dpi_exp_cycles();
            exp_solid  = aether_dpi_exp_solid();
            exp_corr   = aether_dpi_exp_corr();
            exp_peel   = aether_dpi_exp_peel_ops();
        end
    endtask

    task automatic pack_bits;
        input integer mm;
        begin
            solid_pack = 0; corr_pack = 0;
            for (k = 0; k < MAX_E; k = k + 1) begin
                if (k < mm && solid_bits[k]) solid_pack[k] = 1'b1;
                if (k < mm && corr_bits[k])  corr_pack[k]  = 1'b1;
            end
        end
    endtask

    task automatic run_one;
        begin
            start_gm = 0; start_peel = 0; @(posedge clk);
            num_nodes = n[IDX_W-1:0]; num_edges = m[IDX_W-1:0];
            start_gm = 1; @(posedge clk); start_gm = 0;
            wait (done_gm); @(posedge clk);
            pack_bits(m);
            if (cycles != exp_cycles || solid_pack != exp_solid) begin
                $display("FAIL case=%0d grow cycles=%0d/%0d solid=%0h/%0h",
                         cid, cycles, exp_cycles, solid_pack, exp_solid);
                fails = fails + 1;
            end
            start_peel = 1; @(posedge clk); start_peel = 0;
            wait (done_peel); @(posedge clk);
            pack_bits(m);
            if (corr_pack != exp_corr || peel_ops != exp_peel) begin
                $display("FAIL case=%0d peel corr=%0h/%0h ops=%0d/%0d",
                         cid, corr_pack, exp_corr, peel_ops, exp_peel);
                fails = fails + 1;
            end else $display("PASS DPI case=%0d cycles=%0d solid=%0h corr=%0h peel_ops=%0d",
                              cid, cycles, solid_pack, corr_pack, peel_ops);
            @(posedge clk); @(posedge clk);
        end
    endtask

    initial begin
        fails = 0; rst_n = 0; #20; rst_n = 1; #20;
        ncases = aether_dpi_num_cases();
        if (ncases <= 0) begin
            $display("FAIL aether_dpi_num_cases=%0d", ncases);
            $fatal(1);
        end
        for (cid = 0; cid < ncases; cid = cid + 1) begin
            if (aether_dpi_load(cid) != 0) begin
                $display("FAIL aether_dpi_load(%0d)", cid);
                $fatal(1);
            end
            clear_mem();
            load_from_dpi();
            run_one();
        end
        if (fails) begin $display("TOTAL DPI FAILS=%0d", fails); $fatal(1); end
        $display("ALL %0d DPI DECODE CASES PASS", ncases);
        $finish;
    end
endmodule
