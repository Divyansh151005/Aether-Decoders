// TB: Helios-n H9 with N_CTX=6 (M69) — 1-cycle switch through M68's n=6 banks.
// Spec: Docs/Helios_n_Schedule_M69; Helios arXiv:2406.08491.

`timescale 1ns / 1ps

module tb_aether_uf_pe_lutram_ctx_n6;
    localparam int N_CTX = 6;
    localparam int CTX_W = 3;
    localparam int IDX_W = 8;

    reg clk = 0;
    reg rst_n = 0;
    reg load_live = 0;
    reg switch_pulse = 0;
    reg [CTX_W-1:0] next_ctx = 0;
    reg [IDX_W-1:0] in_root = 0;
    reg [15:0]      in_size = 0;
    reg             in_parity = 0;
    reg             in_cbound = 0;
    reg             in_is_root = 0;
    reg [15:0]      in_growth = 0;
    reg             in_solid = 0;

    wire [CTX_W-1:0] cur_ctx;
    wire [IDX_W-1:0] root;
    wire [15:0]      size;
    wire             parity, cbound, is_root, solid;
    wire [15:0]      growth;

    aether_uf_pe_lutram_ctx #(.N_CTX(N_CTX), .IDX_W(IDX_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .load_live(load_live),
        .in_root(in_root), .in_size(in_size),
        .in_parity(in_parity), .in_cbound(in_cbound),
        .in_is_root(in_is_root), .in_growth(in_growth), .in_solid(in_solid),
        .switch_pulse(switch_pulse), .next_ctx(next_ctx),
        .cur_ctx(cur_ctx),
        .root(root), .size(size), .parity(parity), .cbound(cbound),
        .is_root(is_root), .growth(growth), .solid(solid)
    );

    always #5 clk = ~clk;

    reg [IDX_W-1:0] exp_root   [0:N_CTX-1];
    reg [15:0]      exp_size   [0:N_CTX-1];
    reg             exp_parity [0:N_CTX-1];
    reg             exp_cbound [0:N_CTX-1];
    reg             exp_is_root[0:N_CTX-1];
    reg [15:0]      exp_growth [0:N_CTX-1];
    reg             exp_solid  [0:N_CTX-1];

    integer k;

    task automatic do_load;
        input [IDX_W-1:0] r;
        input [15:0] sz;
        input p, cb, ir;
        input [15:0] g;
        input s;
        begin
            in_root = r; in_size = sz; in_parity = p; in_cbound = cb;
            in_is_root = ir; in_growth = g; in_solid = s;
            load_live = 1;
            @(posedge clk);
            load_live = 0;
            @(posedge clk);
        end
    endtask

    task automatic do_switch;
        input [CTX_W-1:0] nxt;
        begin
            next_ctx = nxt;
            switch_pulse = 1;
            @(posedge clk);
            switch_pulse = 0;
        end
    endtask

    task automatic check_live;
        input [CTX_W-1:0] ctx;
        begin
            if (cur_ctx !== ctx ||
                root !== exp_root[ctx] || size !== exp_size[ctx] ||
                parity !== exp_parity[ctx] || cbound !== exp_cbound[ctx] ||
                is_root !== exp_is_root[ctx] || growth !== exp_growth[ctx] ||
                solid !== exp_solid[ctx]) begin
                $display("FAIL ctx=%0d cur=%0d root=%0d/%0d size=%0d/%0d g=%0d/%0d",
                         ctx, cur_ctx, root, exp_root[ctx], size, exp_size[ctx],
                         growth, exp_growth[ctx]);
                $fatal(1);
            end
        end
    endtask

    initial begin
        rst_n = 0;
        #20;
        rst_n = 1;
        @(posedge clk);

        // Distinct state per context 0..5 (M68 n=6).
        for (k = 0; k < N_CTX; k = k + 1) begin
            if (k != 0)
                do_switch(k[CTX_W-1:0]);
            exp_root[k]    = k[IDX_W-1:0] + 8'd10;
            exp_size[k]    = 16'd1 + k[15:0];
            exp_parity[k]  = k[0];
            exp_cbound[k]  = ~k[0];
            exp_is_root[k] = 1'b1;
            exp_growth[k]  = 16'd100 + k[15:0];
            exp_solid[k]   = k[0];
            do_load(exp_root[k], exp_size[k], exp_parity[k], exp_cbound[k],
                    exp_is_root[k], exp_growth[k], exp_solid[k]);
            check_live(k[CTX_W-1:0]);
        end

        // Walk back 5→0: each switch is 1 cycle; prior banks restored bit-identically.
        for (k = N_CTX - 2; k >= 0; k = k - 1) begin
            do_switch(k[CTX_W-1:0]);
            check_live(k[CTX_W-1:0]);
        end

        // Forward 0→5 again.
        for (k = 1; k < N_CTX; k = k + 1) begin
            do_switch(k[CTX_W-1:0]);
            check_live(k[CTX_W-1:0]);
        end

        $display("PASS Helios-n H9 N_CTX=6 1-cycle switch restore (M69)");
        $finish;
    end
endmodule
