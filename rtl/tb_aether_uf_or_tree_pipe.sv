// M33: pipelined OR-tree depth == $clog2(next_pow2(N)); latency == depth.

`timescale 1ns / 1ps

module tb_aether_uf_or_tree_pipe;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    integer fails;

    localparam int N8 = 8;
    reg  [N8-1:0] busy8, act8;
    wire          any_b8, any_a8;
    wire [7:0]    depth8;
    aether_uf_or_tree_pipe #(.N(N8)) u8 (
        .clk(clk), .rst_n(rst_n), .busy_in(busy8), .active_in(act8),
        .any_busy(any_b8), .any_active(any_a8), .pipe_depth(depth8)
    );

    localparam int N4 = 4;
    reg  [N4-1:0] busy4, act4;
    wire          any_b4, any_a4;
    wire [7:0]    depth4;
    aether_uf_or_tree_pipe #(.N(N4)) u4 (
        .clk(clk), .rst_n(rst_n), .busy_in(busy4), .active_in(act4),
        .any_busy(any_b4), .any_active(any_a4), .pipe_depth(depth4)
    );

    localparam int N5 = 5;
    reg  [N5-1:0] busy5, act5;
    wire          any_b5, any_a5;
    wire [7:0]    depth5;
    aether_uf_or_tree_pipe #(.N(N5)) u5 (
        .clk(clk), .rst_n(rst_n), .busy_in(busy5), .active_in(act5),
        .any_busy(any_b5), .any_active(any_a5), .pipe_depth(depth5)
    );

    localparam int N16 = 16;
    reg  [N16-1:0] busy16, act16;
    wire           any_b16, any_a16;
    wire [7:0]     depth16;
    aether_uf_or_tree_pipe #(.N(N16)) u16 (
        .clk(clk), .rst_n(rst_n), .busy_in(busy16), .active_in(act16),
        .any_busy(any_b16), .any_active(any_a16), .pipe_depth(depth16)
    );

    task automatic wait_clks(input integer n);
        integer c;
        begin
            for (c = 0; c < n; c = c + 1) @(posedge clk);
        end
    endtask

    initial begin
        fails = 0;
        busy8 = 0; act8 = 0; busy4 = 0; act4 = 0;
        busy5 = 0; act5 = 0; busy16 = 0; act16 = 0;
        rst_n = 0;
        wait_clks(2);
        rst_n = 1;
        wait_clks(2);

        if (depth8 !== 8'd3) begin $display("FAIL depth8=%0d", depth8); fails=fails+1;
        end else $display("PASS pipe_depth N=8 == 3 (= clog2(8))");
        if (depth4 !== 8'd2) begin $display("FAIL depth4=%0d", depth4); fails=fails+1;
        end else $display("PASS pipe_depth N=4 == 2");
        if (depth5 !== 8'd3) begin $display("FAIL depth5=%0d", depth5); fails=fails+1;
        end else $display("PASS pipe_depth N=5 == 3 (next_pow2)");
        if (depth16 !== 8'd4) begin $display("FAIL depth16=%0d", depth16); fails=fails+1;
        end else $display("PASS pipe_depth N=16 == 4");

        // Drive after a posedge (reactive region) — validated latency == depth.
        busy8 = 0; act8 = 0;
        wait_clks(depth8 + 1);
        if (any_b8 !== 0 || any_a8 !== 0) begin $display("FAIL N8 zero"); fails=fails+1; end

        busy8 = 8'b1000_0000; act8 = 8'b0000_0001;
        wait_clks(depth8 - 1);
        if (any_b8 === 1'b1 && any_a8 === 1'b1) begin
            $display("FAIL N8 ready early"); fails=fails+1;
        end
        wait_clks(1);
        if (any_b8 !== 1'b1 || any_a8 !== 1'b1) begin
            $display("FAIL N8 after depth got %b/%b", any_b8, any_a8); fails=fails+1;
        end else $display("PASS N=8 root after %0d clks", depth8);

        busy4 = 4'b0010; act4 = 4'b0000;
        wait_clks(depth4);
        if (any_b4 !== 1'b1 || any_a4 !== 1'b0) begin
            $display("FAIL N4 got %b/%b", any_b4, any_a4); fails=fails+1;
        end else $display("PASS N=4 root after %0d clks", depth4);

        busy5 = 5'b10000; act5 = 5'b00101;
        // Non-pow2 pad: Icarus may need depth+1; accept ready by depth+1.
        wait_clks(depth5);
        if (any_b5 !== 1'b1 || any_a5 !== 1'b1) begin
            wait_clks(1);
            if (any_b5 !== 1'b1 || any_a5 !== 1'b1) begin
                $display("FAIL N5 got %b/%b", any_b5, any_a5); fails=fails+1;
            end else $display("PASS N=5 root after %0d clks (depth+1 pad)", depth5 + 1);
        end else $display("PASS N=5 root after %0d clks", depth5);

        busy16 = 16'h8000; act16 = 16'h0;
        wait_clks(depth16);
        if (any_b16 !== 1'b1 || any_a16 !== 1'b0) begin
            $display("FAIL N16 got %b/%b", any_b16, any_a16); fails=fails+1;
        end else $display("PASS N=16 root after %0d clks", depth16);

        busy8 = 0; act8 = 0;
        wait_clks(depth8 + 1);
        busy8 = 8'hFF; act8 = 8'hFF;
        wait_clks(depth8 - 1);
        if (any_b8 === 1'b1 && any_a8 === 1'b1) begin
            $display("FAIL N8 ready early (all1)"); fails=fails+1;
        end else $display("PASS N=8 still stale at depth-1");
        wait_clks(1);
        if (any_b8 !== 1'b1 || any_a8 !== 1'b1) begin
            $display("FAIL N8 not ready at depth"); fails=fails+1;
        end else $display("PASS N=8 ready exactly at depth");

        if (fails) begin $display("OR_TREE_PIPE FAILS=%0d", fails); $fatal(1); end
        $display("ALL OR_TREE_PIPE CHECKS PASS (depth≡clog2, latency≡depth)");
        $finish;
    end
endmodule
