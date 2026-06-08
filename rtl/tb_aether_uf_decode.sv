// Blueprint grow→peel TB (M23): 16-bit indices.

`timescale 1ns / 1ps

module tb_aether_uf_decode;
    localparam int MAX_N = 8;
    localparam int MAX_E = 8;
    localparam int IDX_W = 16;

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

    integer k, fails;
    reg [63:0] solid_pack, corr_pack;

    `include "gen/blueprint_cases.sv"

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

    task automatic pack_bits;
        input integer m;
        begin
            solid_pack = 0; corr_pack = 0;
            for (k = 0; k < MAX_E; k = k + 1) begin
                if (k < m && solid_bits[k]) solid_pack[k] = 1'b1;
                if (k < m && corr_bits[k])  corr_pack[k]  = 1'b1;
            end
        end
    endtask

    task automatic run_decode_case;
        input integer n, m, exp_cycles, exp_solid, exp_corr, exp_peel_ops;
        begin
            start_gm = 0; start_peel = 0; @(posedge clk);
            num_nodes = n[IDX_W-1:0]; num_edges = m[IDX_W-1:0];
            start_gm = 1; @(posedge clk); start_gm = 0;
            wait (done_gm); @(posedge clk);
            pack_bits(m);
            if (cycles != exp_cycles || solid_pack != exp_solid) begin
                $display("FAIL grow cycles=%0d/%0d solid=%0h/%0h", cycles, exp_cycles, solid_pack, exp_solid);
                fails = fails + 1;
            end
            start_peel = 1; @(posedge clk); start_peel = 0;
            wait (done_peel); @(posedge clk);
            pack_bits(m);
            if (corr_pack != exp_corr || peel_ops != exp_peel_ops) begin
                $display("FAIL peel corr=%0h/%0h ops=%0d/%0d", corr_pack, exp_corr, peel_ops, exp_peel_ops);
                fails = fails + 1;
            end else $display("PASS cycles=%0d solid=%0h corr=%0h peel_ops=%0d",
                              cycles, solid_pack, corr_pack, peel_ops);
            @(posedge clk); @(posedge clk);
        end
    endtask

    initial begin
        fails = 0; rst_n = 0; #20; rst_n = 1; #20;
        clear_mem(); load_case_0(); run_decode_case(C0_N,C0_M,C0_CYCLES,C0_SOLID,C0_CORR,C0_PEEL_OPS);
        clear_mem(); load_case_1(); run_decode_case(C1_N,C1_M,C1_CYCLES,C1_SOLID,C1_CORR,C1_PEEL_OPS);
        clear_mem(); load_case_2(); run_decode_case(C2_N,C2_M,C2_CYCLES,C2_SOLID,C2_CORR,C2_PEEL_OPS);
        clear_mem(); load_case_3(); run_decode_case(C3_N,C3_M,C3_CYCLES,C3_SOLID,C3_CORR,C3_PEEL_OPS);
        clear_mem(); load_case_4(); run_decode_case(C4_N,C4_M,C4_CYCLES,C4_SOLID,C4_CORR,C4_PEEL_OPS);
        clear_mem(); load_case_5(); run_decode_case(C5_N,C5_M,C5_CYCLES,C5_SOLID,C5_CORR,C5_PEEL_OPS);
        clear_mem(); load_case_6(); run_decode_case(C6_N,C6_M,C6_CYCLES,C6_SOLID,C6_CORR,C6_PEEL_OPS);
        clear_mem(); load_case_7(); run_decode_case(C7_N,C7_M,C7_CYCLES,C7_SOLID,C7_CORR,C7_PEEL_OPS);
        if (fails) begin $display("TOTAL FAILS=%0d", fails); $fatal(1); end
        $display("ALL %0d DECODE CASES PASS", NUM_CASES);
        $finish;
    end
endmodule
