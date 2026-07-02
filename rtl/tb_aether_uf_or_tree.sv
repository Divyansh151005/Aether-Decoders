// Self-checking TB for aether_uf_or_tree (H8).
// Goldens: any_* == |vector (software / combinatorial reference).

`timescale 1ns / 1ps

module tb_aether_uf_or_tree;
    localparam int N = 8;

    reg  [N-1:0] busy_in;
    reg  [N-1:0] active_in;
    wire         any_busy;
    wire         any_active;

    aether_uf_or_tree #(.N(N)) dut (
        .busy_in(busy_in),
        .active_in(active_in),
        .any_busy(any_busy),
        .any_active(any_active)
    );

    integer i;
    integer fails;
    reg expect_busy;
    reg expect_act;

    task automatic check(input [N-1:0] b, input [N-1:0] a, input string tag);
        begin
            busy_in   = b;
            active_in = a;
            #1;
            expect_busy = |b;
            expect_act  = |a;
            if (any_busy !== expect_busy || any_active !== expect_act) begin
                $display("FAIL %s busy_in=%b act_in=%b got busy=%b act=%b expect %b/%b",
                         tag, b, a, any_busy, any_active, expect_busy, expect_act);
                fails = fails + 1;
            end
        end
    endtask

    initial begin
        fails = 0;
        check(8'b0000_0000, 8'b0000_0000, "all_zero");
        check(8'b0000_0001, 8'b0000_0000, "busy_lsb");
        check(8'b1000_0000, 8'b0000_0000, "busy_msb");
        check(8'b0000_0000, 8'b0100_0000, "act_bit6");
        check(8'b1111_1111, 8'b1111_1111, "all_one");
        check(8'b1010_1010, 8'b0101_0101, "alt");
        // Exhaustive for lower 4 bits (upper 0) — cheap coverage.
        for (i = 0; i < 16; i = i + 1) begin
            check(i[7:0], 8'((i << 1) & 8'hFF), "exh4");
        end
        if (fails != 0) begin
            $display("OR_TREE FAILS=%0d", fails);
            $fatal(1);
        end
        $display("PASS aether_uf_or_tree N=%0d (%0d directed+exh checks)", N, 6 + 16);
        $finish;
    end
endmodule
