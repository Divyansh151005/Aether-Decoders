// TB: Helios-2 micro grow (M40) — H9 wired into grow.
// ctx0 = two_node (cycles=5,solid=1); ctx1 = boundary (cycles=10,solid=1);
// switch back → ctx0 solid/growth preserved without re-grow.

`timescale 1ns / 1ps

module tb_aether_uf_helios2_micro_grow;
    reg clk = 0;
    reg rst_n = 0;
    reg switch_pulse = 0;
    reg next_ctx = 0;
    reg start_grow = 0;
    reg [1:0] syn = 0;
    reg [1:0] is_bnd = 0;

    wire cur_ctx;
    wire done_grow;
    wire [15:0] cycles;
    wire solid0;
    wire [15:0] growth0;

    aether_uf_helios2_micro_grow dut (
        .clk(clk), .rst_n(rst_n),
        .switch_pulse(switch_pulse), .next_ctx(next_ctx),
        .start_grow(start_grow), .syn(syn), .is_bnd(is_bnd),
        .cur_ctx(cur_ctx), .done_grow(done_grow), .cycles(cycles),
        .solid0(solid0), .growth0(growth0)
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
            @(posedge clk); // settle S_DONE → S_IDLE
        end
    endtask

    initial begin
        rst_n = 0;
        #20;
        rst_n = 1;
        @(posedge clk);

        // --- ctx0: Blueprint two_node ---
        if (cur_ctx !== 1'b0) begin
            $display("FAIL start ctx=%0d", cur_ctx);
            $fatal(1);
        end
        do_grow(2'b11, 2'b00);
        if (cycles !== 16'd5 || solid0 !== 1'b1 || growth0 !== 16'd10) begin
            $display("FAIL ctx0 two_node cycles=%0d solid=%0b g=%0d (expect 5,1,10)",
                     cycles, solid0, growth0);
            $fatal(1);
        end
        $display("PASS ctx0 two_node cycles=%0d solid=%0b", cycles, solid0);

        // Switch to ctx1 (fresh), grow boundary job
        do_switch(1'b1);
        if (cur_ctx !== 1'b1) begin
            $display("FAIL switch ctx1 cur=%0d", cur_ctx);
            $fatal(1);
        end
        // Fresh bank: solid should be 0
        if (solid0 !== 1'b0) begin
            $display("FAIL ctx1 should start unsolid, got solid=%0b", solid0);
            $fatal(1);
        end

        do_grow(2'b01, 2'b10); // syn v0=1, bnd v1=1 → boundary golden
        if (cycles !== 16'd10 || solid0 !== 1'b1 || growth0 !== 16'd10) begin
            $display("FAIL ctx1 boundary cycles=%0d solid=%0b g=%0d (expect 10,1,10)",
                     cycles, solid0, growth0);
            $fatal(1);
        end
        $display("PASS ctx1 boundary cycles=%0d solid=%0b", cycles, solid0);

        // Switch back to ctx0 — must restore two_node solid without re-grow
        do_switch(1'b0);
        if (cur_ctx !== 1'b0 || solid0 !== 1'b1 || growth0 !== 16'd10 ||
            cycles !== 16'd5) begin
            $display("FAIL restore ctx0 after Helios-2: ctx=%0d solid=%0b g=%0d cyc=%0d",
                     cur_ctx, solid0, growth0, cycles);
            $fatal(1);
        end
        $display("PASS restore ctx0 solid/growth/cycles after multiplexed grow");
        $display("PASS helios2_micro_grow (H9 wired into grow)");
        $finish;
    end
endmodule
