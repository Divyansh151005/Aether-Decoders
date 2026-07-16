// TB: Helios-2 LUTRAM context switch (H9 / M39).
// Prove 1-cycle store/load restores PE state bit-identically.
// Spec: Docs/Helios_n_H9; Helios arXiv:2406.08491.

`timescale 1ns / 1ps

module tb_aether_uf_pe_lutram_ctx;
    reg clk = 0;
    reg rst_n = 0;
    reg load_live = 0;
    reg switch_pulse = 0;
    reg next_ctx = 0;
    reg [7:0]  in_root = 0;
    reg [15:0] in_size = 0;
    reg        in_parity = 0;
    reg        in_cbound = 0;
    reg        in_is_root = 0;
    reg [15:0] in_growth = 0;
    reg        in_solid = 0;

    wire       cur_ctx;
    wire [7:0] root;
    wire [15:0] size;
    wire       parity, cbound, is_root, solid;
    wire [15:0] growth;

    aether_uf_pe_lutram_ctx #(.N_CTX(2), .IDX_W(8)) dut (
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

    task automatic do_load;
        input [7:0] r;
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
        input nxt;
        begin
            next_ctx = nxt;
            switch_pulse = 1;
            @(posedge clk);
            switch_pulse = 0;
            // State must be valid immediately after this one edge (Helios 1-cycle).
        end
    endtask

    initial begin
        rst_n = 0;
        #20;
        rst_n = 1;
        @(posedge clk);

        // --- ctx0 := state A ---
        do_load(8'd3, 16'd7, 1'b1, 1'b0, 1'b1, 16'd10, 1'b1);
        if (cur_ctx !== 1'b0 || root !== 8'd3 || size !== 16'd7 ||
            parity !== 1'b1 || growth !== 16'd10 || solid !== 1'b1) begin
            $display("FAIL after load A: ctx=%0d root=%0d size=%0d",
                     cur_ctx, root, size);
            $fatal(1);
        end

        // Switch to ctx1 (empty/reset bank) in one cycle; A stored in bank0.
        do_switch(1'b1);
        if (cur_ctx !== 1'b1) begin
            $display("FAIL switch to ctx1: cur=%0d", cur_ctx);
            $fatal(1);
        end
        // Fresh ctx1 defaults from reset banks.
        if (root !== 8'd0 || size !== 16'd1 || parity !== 1'b0 ||
            growth !== 16'd0 || solid !== 1'b0) begin
            $display("FAIL ctx1 default root=%0d size=%0d g=%0d",
                     root, size, growth);
            $fatal(1);
        end

        // --- ctx1 := state B ---
        do_load(8'd5, 16'd2, 1'b0, 1'b1, 1'b0, 16'd4, 1'b0);
        if (root !== 8'd5 || size !== 16'd2 || cbound !== 1'b1 ||
            growth !== 16'd4) begin
            $display("FAIL after load B");
            $fatal(1);
        end

        // Switch back to ctx0 — must restore A in **one** cycle.
        do_switch(1'b0);
        if (cur_ctx !== 1'b0 || root !== 8'd3 || size !== 16'd7 ||
            parity !== 1'b1 || cbound !== 1'b0 || is_root !== 1'b1 ||
            growth !== 16'd10 || solid !== 1'b1) begin
            $display("FAIL restore A after 1-cycle switch: ctx=%0d root=%0d size=%0d p=%0b g=%0d s=%0b",
                     cur_ctx, root, size, parity, growth, solid);
            $fatal(1);
        end
        $display("PASS restore ctx0 (A) in 1 cycle");

        // Switch to ctx1 — restore B in one cycle.
        do_switch(1'b1);
        if (cur_ctx !== 1'b1 || root !== 8'd5 || size !== 16'd2 ||
            parity !== 1'b0 || cbound !== 1'b1 || is_root !== 1'b0 ||
            growth !== 16'd4 || solid !== 1'b0) begin
            $display("FAIL restore B: ctx=%0d root=%0d size=%0d",
                     cur_ctx, root, size);
            $fatal(1);
        end
        $display("PASS restore ctx1 (B) in 1 cycle");
        $display("PASS pe_lutram_ctx Helios-2 H9 (≡ Pe_Mesh_Decode §2 plan)");
        $finish;
    end
endmodule
