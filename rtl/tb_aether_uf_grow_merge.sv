// Grow-only Blueprint TB (M22/M23): 16-bit indices.

`timescale 1ns / 1ps

module tb_aether_uf_grow_merge;
    localparam int MAX_N = 8;
    localparam int MAX_E = 8;
    localparam int IDX_W = 16;

    reg clk = 0;
    reg rst_n = 0;
    reg start = 0;
    reg [IDX_W-1:0] num_nodes = 0;
    reg [IDX_W-1:0] num_edges = 0;
    reg [7:0]         syn_mem [0:MAX_N-1];
    reg [7:0]         bnd_mem [0:MAX_N-1];
    reg [IDX_W-1:0]   eu_mem  [0:MAX_E-1];
    reg [IDX_W-1:0]   ev_mem  [0:MAX_E-1];
    reg [15:0]        cap_mem [0:MAX_E-1];
    wire done;
    wire [31:0] cycles;
    wire solid_bits [0:MAX_E-1];

    integer k, fails;
    reg [63:0] solid_pack;

    `include "gen/blueprint_cases.sv"

    aether_uf_grow_merge #(.MAX_N(MAX_N), .MAX_E(MAX_E), .IDX_W(IDX_W)) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .num_nodes(num_nodes), .num_edges(num_edges),
        .syn_mem(syn_mem), .bnd_mem(bnd_mem),
        .eu_mem(eu_mem), .ev_mem(ev_mem), .cap_mem(cap_mem),
        .done(done), .cycles(cycles), .solid_bits(solid_bits)
    );

    always #5 clk = ~clk;

    task automatic clear_mem;
        begin
            for (k = 0; k < MAX_N; k = k + 1) begin syn_mem[k]=0; bnd_mem[k]=0; end
            for (k = 0; k < MAX_E; k = k + 1) begin eu_mem[k]=0; ev_mem[k]=0; cap_mem[k]=0; end
        end
    endtask

    task automatic pack_solid;
        input integer m;
        begin
            solid_pack = 0;
            for (k = 0; k < MAX_E; k = k + 1)
                if (k < m && solid_bits[k]) solid_pack[k] = 1'b1;
        end
    endtask

    task automatic run_case;
        input integer n, m, exp_cycles, exp_solid;
        begin
            start = 0; @(posedge clk);
            num_nodes = n[IDX_W-1:0]; num_edges = m[IDX_W-1:0];
            start = 1; @(posedge clk); start = 0;
            wait (done); @(posedge clk);
            pack_solid(m);
            if (cycles != exp_cycles || solid_pack != exp_solid) begin
                $display("FAIL cycles got=%0d exp=%0d solid got=%0h exp=%0h",
                         cycles, exp_cycles, solid_pack, exp_solid);
                fails = fails + 1;
            end else $display("PASS cycles=%0d solid=%0h", cycles, solid_pack);
            @(posedge clk); @(posedge clk);
        end
    endtask

    initial begin
        fails = 0; rst_n = 0; #20; rst_n = 1; #20;
        clear_mem(); load_case_0(); run_case(C0_N, C0_M, C0_CYCLES, C0_SOLID);
        clear_mem(); load_case_1(); run_case(C1_N, C1_M, C1_CYCLES, C1_SOLID);
        clear_mem(); load_case_2(); run_case(C2_N, C2_M, C2_CYCLES, C2_SOLID);
        clear_mem(); load_case_3(); run_case(C3_N, C3_M, C3_CYCLES, C3_SOLID);
        clear_mem(); load_case_4(); run_case(C4_N, C4_M, C4_CYCLES, C4_SOLID);
        clear_mem(); load_case_5(); run_case(C5_N, C5_M, C5_CYCLES, C5_SOLID);
        clear_mem(); load_case_6(); run_case(C6_N, C6_M, C6_CYCLES, C6_SOLID);
        clear_mem(); load_case_7(); run_case(C7_N, C7_M, C7_CYCLES, C7_SOLID);
        if (fails) begin $display("TOTAL FAILS=%0d", fails); $fatal(1); end
        $display("ALL %0d CASES PASS", NUM_CASES);
        $finish;
    end
endmodule
