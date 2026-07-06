// Aether UF — H8 OR-tree with one register per binary OR level (M33).
//
// Spec: Docs/Pe_Grid_Prep; Helios arXiv:2406.08491 §IV-B.
// Combinational sibling: aether_uf_or_tree (Blueprint grow/decode — unchanged).
//
// Per-LOG2 always blocks (Icarus latency == clog2). Supported PW≤16.
// Do NOT wire into grow_merge_ctrl without new cycle goldens.

`timescale 1ns / 1ps

module aether_uf_or_tree_pipe #(
    parameter int N = 8
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [N-1:0] busy_in,
    input  wire [N-1:0] active_in,
    output reg          any_busy,
    output reg          any_active,
    output wire [7:0]   pipe_depth
);
    localparam int LOG2 = (N <= 1) ? 0 : $clog2(N);
    localparam int PW   = 1 << LOG2;

    assign pipe_depth = LOG2[7:0];

    // Pad to next power-of-two. For N==PW, Icarus latency == LOG2; for N<PW, TB allows LOG2+1.
    wire [PW-1:0] leaf_b = {{(PW - N){1'b0}}, busy_in};
    wire [PW-1:0] leaf_a = {{(PW - N){1'b0}}, active_in};

    generate
        if (LOG2 == 0) begin : d0
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin any_busy <= 0; any_active <= 0; end
                else begin any_busy <= leaf_b[0]; any_active <= leaf_a[0]; end
            end
        end else if (LOG2 == 1) begin : d1
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin any_busy <= 0; any_active <= 0; end
                else begin
                    any_busy   <= leaf_b[0] | leaf_b[1];
                    any_active <= leaf_a[0] | leaf_a[1];
                end
            end
        end else if (LOG2 == 2) begin : d2
            reg [1:0] s1_b, s1_a;
            integer k;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    s1_b <= 0; s1_a <= 0; any_busy <= 0; any_active <= 0;
                end else begin
                    for (k = 0; k < 2; k = k + 1) begin
                        s1_b[k] <= leaf_b[2*k] | leaf_b[2*k+1];
                        s1_a[k] <= leaf_a[2*k] | leaf_a[2*k+1];
                    end
                    any_busy   <= s1_b[0] | s1_b[1];
                    any_active <= s1_a[0] | s1_a[1];
                end
            end
        end else if (LOG2 == 3) begin : d3
            reg [3:0] s1_b, s1_a;
            reg [1:0] s2_b, s2_a;
            integer k;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    s1_b <= 0; s1_a <= 0; s2_b <= 0; s2_a <= 0;
                    any_busy <= 0; any_active <= 0;
                end else begin
                    for (k = 0; k < 4; k = k + 1) begin
                        s1_b[k] <= leaf_b[2*k] | leaf_b[2*k+1];
                        s1_a[k] <= leaf_a[2*k] | leaf_a[2*k+1];
                    end
                    for (k = 0; k < 2; k = k + 1) begin
                        s2_b[k] <= s1_b[2*k] | s1_b[2*k+1];
                        s2_a[k] <= s1_a[2*k] | s1_a[2*k+1];
                    end
                    any_busy   <= s2_b[0] | s2_b[1];
                    any_active <= s2_a[0] | s2_a[1];
                end
            end
        end else if (LOG2 == 4) begin : d4
            reg [7:0] s1_b, s1_a;
            reg [3:0] s2_b, s2_a;
            reg [1:0] s3_b, s3_a;
            integer k;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    s1_b <= 0; s1_a <= 0; s2_b <= 0; s2_a <= 0;
                    s3_b <= 0; s3_a <= 0; any_busy <= 0; any_active <= 0;
                end else begin
                    for (k = 0; k < 8; k = k + 1) begin
                        s1_b[k] <= leaf_b[2*k] | leaf_b[2*k+1];
                        s1_a[k] <= leaf_a[2*k] | leaf_a[2*k+1];
                    end
                    for (k = 0; k < 4; k = k + 1) begin
                        s2_b[k] <= s1_b[2*k] | s1_b[2*k+1];
                        s2_a[k] <= s1_a[2*k] | s1_a[2*k+1];
                    end
                    for (k = 0; k < 2; k = k + 1) begin
                        s3_b[k] <= s2_b[2*k] | s2_b[2*k+1];
                        s3_a[k] <= s2_a[2*k] | s2_a[2*k+1];
                    end
                    any_busy   <= s3_b[0] | s3_b[1];
                    any_active <= s3_a[0] | s3_a[1];
                end
            end
        end else begin : d_bad
            initial $error("aether_uf_or_tree_pipe: LOG2>4 not supported in M33");
        end
    endgenerate
endmodule
