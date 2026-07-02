// Aether UF grow+merge with H8 OR-tree controller (M31 PE-grid).
//
// Same grow/merge schedule as aether_uf_grow_merge (Blueprint N≤8), but
// any_active is reduced via aether_uf_or_tree (Helios §IV-B / Hardware_Mapping H8)
// instead of a sequential for-loop OR.
//
// Leaf active[i] = root i with (parity && !cbound); pad inactive for i≥n_nodes.
// busy leaf mirrors active for this slice (quiescent when !any_active).
// Combinational tree → same cycle counts as monolithic grow_merge.

`timescale 1ns / 1ps

module aether_uf_grow_merge_ctrl #(
    parameter int MAX_N = 8,
    parameter int MAX_E = 8,
    parameter int IDX_W = 16
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  start,
    input  wire [IDX_W-1:0]      num_nodes,
    input  wire [IDX_W-1:0]      num_edges,
    input  wire [7:0]            syn_mem  [0:MAX_N-1],
    input  wire [7:0]            bnd_mem  [0:MAX_N-1],
    input  wire [IDX_W-1:0]      eu_mem   [0:MAX_E-1],
    input  wire [IDX_W-1:0]      ev_mem   [0:MAX_E-1],
    input  wire [15:0]           cap_mem  [0:MAX_E-1],
    output reg                   done,
    output reg  [31:0]           cycles,
    output reg                   solid_bits [0:MAX_E-1],
    // Controller observability (Helios-style root aggregates).
    output wire                  ctrl_any_busy,
    output wire                  ctrl_any_active
);
    localparam S_IDLE = 2'd0;
    localparam S_INIT = 2'd1;
    localparam S_RUN  = 2'd2;
    localparam S_DONE = 2'd3;

    reg [1:0] state;

    reg [IDX_W-1:0] parent [0:MAX_N-1];
    reg [15:0]      size_a [0:MAX_N-1];
    reg             parity [0:MAX_N-1];
    reg             cbound [0:MAX_N-1];
    reg             is_bnd [0:MAX_N-1];
    reg             syn    [0:MAX_N-1];

    reg [IDX_W-1:0] edge_u   [0:MAX_E-1];
    reg [IDX_W-1:0] edge_v   [0:MAX_E-1];
    reg [15:0]      capacity [0:MAX_E-1];
    reg [15:0]      growth   [0:MAX_E-1];
    reg             solid    [0:MAX_E-1];

    reg [IDX_W-1:0] n_nodes;
    reg [IDX_W-1:0] n_edges;

    integer i, e, u, v, ru, rv;
    reg [15:0] delta;
    reg grew, merged;

    wire [MAX_N-1:0] active_leaves;
    wire [MAX_N-1:0] busy_leaves;

    genvar gi;
    generate
        for (gi = 0; gi < MAX_N; gi = gi + 1) begin : g_leaf
            // Aether active ⇔ odd ∧ ¬cluster_boundary at a DSU root.
            assign active_leaves[gi] =
                (gi < n_nodes) &&
                (parent[gi] == gi[IDX_W-1:0]) &&
                parity[gi] &&
                !cbound[gi];
            assign busy_leaves[gi] = active_leaves[gi];
        end
    endgenerate

    aether_uf_or_tree #(.N(MAX_N)) u_ctrl (
        .busy_in(busy_leaves),
        .active_in(active_leaves),
        .any_busy(ctrl_any_busy),
        .any_active(ctrl_any_active)
    );

    function automatic [IDX_W-1:0] find_root;
        input [IDX_W-1:0] x;
        reg [IDX_W-1:0] cur;
        integer guard;
        begin
            cur = x;
            for (guard = 0; guard < MAX_N; guard = guard + 1) begin
                if (parent[cur] == cur) begin
                    find_root = cur;
                    guard = MAX_N;
                end else begin
                    cur = parent[cur];
                    find_root = cur;
                end
            end
        end
    endfunction

    task automatic do_union;
        input [IDX_W-1:0] uu;
        input [IDX_W-1:0] vv;
        reg [IDX_W-1:0] a, b, t;
        begin
            a = find_root(uu);
            b = find_root(vv);
            if (a != b) begin
                if (size_a[a] < size_a[b]) begin
                    t = a; a = b; b = t;
                end
                parent[b] = a;
                size_a[a] = size_a[a] + size_a[b];
                parity[a] = parity[a] ^ parity[b];
                cbound[a] = cbound[a] | cbound[b];
                parity[b] = 1'b0;
                cbound[b] = 1'b0;
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done <= 1'b0;
            cycles <= 32'd0;
            n_nodes <= {IDX_W{1'b0}};
            n_edges <= {IDX_W{1'b0}};
            for (e = 0; e < MAX_E; e = e + 1)
                solid_bits[e] <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        n_nodes <= num_nodes;
                        n_edges <= num_edges;
                        cycles <= 32'd0;
                        for (e = 0; e < MAX_E; e = e + 1)
                            solid_bits[e] <= 1'b0;
                        state <= S_INIT;
                    end
                end
                S_INIT: begin
                    for (i = 0; i < MAX_N; i = i + 1) begin
                        if (i < n_nodes) begin
                            parent[i] <= i[IDX_W-1:0];
                            size_a[i] <= 16'd1;
                            syn[i] <= syn_mem[i][0];
                            parity[i] <= syn_mem[i][0];
                            is_bnd[i] <= bnd_mem[i][0];
                            cbound[i] <= bnd_mem[i][0];
                        end
                    end
                    for (e = 0; e < MAX_E; e = e + 1) begin
                        if (e < n_edges) begin
                            edge_u[e] <= eu_mem[e];
                            edge_v[e] <= ev_mem[e];
                            capacity[e] <= cap_mem[e];
                            growth[e] <= 16'd0;
                            solid[e] <= 1'b0;
                        end
                    end
                    state <= S_RUN;
                end
                S_RUN: begin
                    // Quiesce via H8 OR-tree (not sequential for-loop OR).
                    if (!ctrl_any_active) begin
                        for (e = 0; e < MAX_E; e = e + 1) begin
                            if (e < n_edges)
                                solid_bits[e] <= solid[e];
                            else
                                solid_bits[e] <= 1'b0;
                        end
                        state <= S_DONE;
                        done <= 1'b1;
                    end else begin
                        grew = 1'b0;
                        for (e = 0; e < MAX_E; e = e + 1) begin
                            if (e < n_edges && !solid[e]) begin
                                u = edge_u[e];
                                v = edge_v[e];
                                ru = find_root(u[IDX_W-1:0]);
                                rv = find_root(v[IDX_W-1:0]);
                                delta = 16'd0;
                                if (ru != rv) begin
                                    if (parity[ru] && !cbound[ru]) delta = delta + 16'd1;
                                    if (parity[rv] && !cbound[rv]) delta = delta + 16'd1;
                                end
                                if (delta != 0) begin
                                    growth[e] = growth[e] + delta;
                                    grew = 1'b1;
                                end
                            end
                        end
                        cycles <= cycles + 32'd1;

                        merged = 1'b0;
                        for (e = 0; e < MAX_E; e = e + 1) begin
                            if (e < n_edges && !solid[e] && growth[e] >= capacity[e]) begin
                                solid[e] = 1'b1;
                                do_union(edge_u[e], edge_v[e]);
                                merged = 1'b1;
                            end
                        end
                        if (!grew && !merged) begin
                            state <= S_DONE;
                            done <= 1'b1;
                        end
                    end
                end
                S_DONE: begin
                    done <= 1'b1;
                    if (!start)
                        state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
