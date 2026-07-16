// M41: Helios-2 micro grow → peel (multiplexed decode).
// ctx0 two_node corr=1; ctx1 boundary corr=1; ctx0 solid restored after switch.
// Spec: Docs/Helios2_Micro_Decode; M10 peel; M40 grow.

`timescale 1ns / 1ps

module tb_aether_uf_helios2_micro_decode;
    localparam int MAX_N = 2;
    localparam int MAX_E = 1;
    localparam int IDX_W = 8;

    reg clk = 0;
    reg rst_n = 0;
    reg switch_pulse = 0;
    reg next_ctx = 0;
    reg start_grow = 0;
    reg start_peel = 0;
    reg [1:0] syn = 0;
    reg [1:0] is_bnd = 0;

    wire cur_ctx;
    wire done_grow, done_peel;
    wire [15:0] cycles;
    wire solid0;
    wire [15:0] growth0;
    wire [31:0] peel_ops;

    reg [7:0]       syn_mem [0:MAX_N-1];
    reg [7:0]       bnd_mem [0:MAX_N-1];
    reg [IDX_W-1:0] eu_mem  [0:MAX_E-1];
    reg [IDX_W-1:0] ev_mem  [0:MAX_E-1];
    // Dummy solid for packer; peel takes widened solid0 (MAX_E=1).
    wire solid_arr [0:MAX_E-1];
    wire [MAX_E-1:0] corr_bits;
    wire [MAX_E-1:0] peel_solid;
    wire [MAX_E-1:0] peel_solid_unused;
    wire [8*MAX_N-1:0]     peel_syn_mem;
    wire [8*MAX_N-1:0]     peel_bnd_mem;
    wire [IDX_W*MAX_E-1:0] peel_eu_mem;
    wire [IDX_W*MAX_E-1:0] peel_ev_mem;

    integer k;
    reg corr_pack;

    aether_uf_helios2_micro_grow u_grow (
        .clk(clk), .rst_n(rst_n),
        .switch_pulse(switch_pulse), .next_ctx(next_ctx),
        .start_grow(start_grow), .syn(syn), .is_bnd(is_bnd),
        .cur_ctx(cur_ctx), .done_grow(done_grow), .cycles(cycles),
        .solid0(solid0), .growth0(growth0)
    );

    assign solid_arr[0] = solid0;
    assign peel_solid = solid0;

    aether_uf_tb_pack_peel_in #(.MAX_N(MAX_N), .MAX_E(MAX_E), .IDX_W(IDX_W)) u_pack (
        .solid_arr(solid_arr),
        .syn_arr(syn_mem), .bnd_arr(bnd_mem),
        .eu_arr(eu_mem), .ev_arr(ev_mem),
        .solid_bits(peel_solid_unused),
        .syn_mem(peel_syn_mem), .bnd_mem(peel_bnd_mem),
        .eu_mem(peel_eu_mem), .ev_mem(peel_ev_mem)
    );

    aether_uf_peel #(
        .MAX_N(MAX_N), .MAX_E(MAX_E), .MAX_DEG(4), .IDX_W(IDX_W)
    ) u_peel (
        .clk(clk), .rst_n(rst_n), .start(start_peel),
        .num_nodes(8'd2), .num_edges(8'd1),
        .solid_bits(peel_solid),
        .syn_mem(peel_syn_mem), .bnd_mem(peel_bnd_mem),
        .eu_mem(peel_eu_mem), .ev_mem(peel_ev_mem),
        .done(done_peel), .corr_bits(corr_bits), .peel_ops(peel_ops)
    );

    always #5 clk = ~clk;

    task automatic do_switch;
        input nxt;
        begin
            next_ctx = nxt;
            switch_pulse = 1;
            @(posedge clk);
            switch_pulse = 0;
            @(posedge clk);
        end
    endtask

    task automatic do_grow;
        input [1:0] s;
        input [1:0] b;
        begin
            syn = s;
            is_bnd = b;
            start_grow = 1;
            @(posedge clk);
            start_grow = 0;
            wait (done_grow);
            @(posedge clk);
            @(posedge clk);
        end
    endtask

    task automatic load_peel_inputs;
        input [1:0] s;
        input [1:0] b;
        begin
            syn_mem[0] = {7'd0, s[0]};
            syn_mem[1] = {7'd0, s[1]};
            bnd_mem[0] = {7'd0, b[0]};
            bnd_mem[1] = {7'd0, b[1]};
            eu_mem[0] = 8'd0;
            ev_mem[0] = 8'd1;
        end
    endtask

    task automatic do_peel_check;
        input [1:0] s;
        input [1:0] b;
        input integer exp_corr;
        input integer exp_ops;
        begin
            load_peel_inputs(s, b);
            // Icarus: packer continuous assigns from unpacked arrays settle after
            // the blocking update region; wait one edge before asserting start.
            @(posedge clk);
            start_peel = 1;
            @(posedge clk);
            start_peel = 0;
            wait (done_peel);
            @(posedge clk);
            corr_pack = corr_bits[0];
            if (corr_pack !== exp_corr[0] || peel_ops !== exp_ops) begin
                $display("FAIL peel corr=%0b/%0d ops=%0d/%0d",
                         corr_pack, exp_corr, peel_ops, exp_ops);
                $fatal(1);
            end
        end
    endtask

    initial begin
        for (k = 0; k < MAX_N; k = k + 1) begin
            syn_mem[k] = 0; bnd_mem[k] = 0;
        end
        eu_mem[0] = 0; ev_mem[0] = 0;

        rst_n = 0;
        #20;
        rst_n = 1;
        @(posedge clk);

        // ctx0: two_node grow → peel
        do_grow(2'b11, 2'b00);
        if (cycles !== 16'd5 || solid0 !== 1'b1) begin
            $display("FAIL ctx0 grow cycles=%0d solid=%0b", cycles, solid0);
            $fatal(1);
        end
        do_peel_check(2'b11, 2'b00, 1, 1);
        $display("PASS ctx0 two_node grow→peel cycles=%0d corr=1", cycles);

        // ctx1: boundary grow → peel
        do_switch(1'b1);
        do_grow(2'b01, 2'b10);
        if (cycles !== 16'd10 || solid0 !== 1'b1) begin
            $display("FAIL ctx1 grow cycles=%0d solid=%0b", cycles, solid0);
            $fatal(1);
        end
        do_peel_check(2'b01, 2'b10, 1, 1);
        $display("PASS ctx1 boundary grow→peel cycles=%0d corr=1", cycles);

        // restore ctx0 solids, peel again
        do_switch(1'b0);
        if (solid0 !== 1'b1 || growth0 !== 16'd10 || cycles !== 16'd5) begin
            $display("FAIL restore ctx0 solid=%0b g=%0d cyc=%0d",
                     solid0, growth0, cycles);
            $fatal(1);
        end
        do_peel_check(2'b11, 2'b00, 1, 1);
        $display("PASS restore ctx0 peel after multiplex");
        $display("PASS helios2_micro_decode (Helios-2 grow→peel)");
        $finish;
    end
endmodule
