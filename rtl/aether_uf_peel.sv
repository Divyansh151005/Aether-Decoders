// Aether UF peel FSM — multi-cycle + 1-neighbor/cycle expand (M60/M63).
// Packed buses (M59). Spec: Docs/Peel_Multicycle_M60, Docs/Peel_N16_M63.
// M10 boundary-root; Das-style Corr staging.

`timescale 1ns / 1ps

module aether_uf_peel #(
    parameter int MAX_N   = 4,
    parameter int MAX_E   = 4,
    parameter int MAX_DEG = 8,
    parameter int IDX_W   = 8
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       start,
    input  wire [IDX_W-1:0]           num_nodes,
    input  wire [IDX_W-1:0]           num_edges,
    input  wire [MAX_E-1:0]           solid_bits,
    input  wire [8*MAX_N-1:0]         syn_mem,
    input  wire [8*MAX_N-1:0]         bnd_mem,
    input  wire [IDX_W*MAX_E-1:0]     eu_mem,
    input  wire [IDX_W*MAX_E-1:0]     ev_mem,
    output reg                        done,
    output reg  [MAX_E-1:0]           corr_bits,
    output reg  [31:0]                peel_ops
);
    localparam S_IDLE       = 5'd0;
    localparam S_BUILD_CLR  = 5'd1;
    localparam S_BUILD_ECLR = 5'd2;
    localparam S_BUILD_E    = 5'd3;
    localparam S_F_SEEK     = 5'd4;
    localparam S_F_POP      = 5'd5;
    localparam S_F_EXP      = 5'd6;
    localparam S_R_CLR      = 5'd7;
    localparam S_R_SEEK     = 5'd8;
    localparam S_R_POP      = 5'd9;
    localparam S_R_EXP      = 5'd10;
    localparam S_R_SCAN_BND = 5'd11;
    localparam S_R_SCAN_DEG = 5'd12;
    localparam S_R_ASSIGN   = 5'd13;
    localparam S_SEED_REM   = 5'd14;
    localparam S_SEED_ENQ   = 5'd15;
    localparam S_PEEL_TAKE  = 5'd16;
    localparam S_PEEL_FIND  = 5'd17;
    localparam S_PEEL_APPLY = 5'd18;
    localparam S_DONE       = 5'd19;

    reg [4:0] state;
    reg [IDX_W-1:0] n_nodes, n_edges;

    reg [IDX_W-1:0] edge_u [0:MAX_E-1];
    reg [IDX_W-1:0] edge_v [0:MAX_E-1];
    reg             is_bnd [0:MAX_N-1];
    reg             syn_w  [0:MAX_N-1];
    reg             solid  [0:MAX_E-1];

    reg [IDX_W-1:0] sadj_n [0:MAX_N-1][0:MAX_DEG-1];
    reg [IDX_W-1:0] sadj_e [0:MAX_N-1][0:MAX_DEG-1];
    reg [7:0]       sdeg   [0:MAX_N-1];

    reg [IDX_W-1:0] fadj_n [0:MAX_N-1][0:MAX_DEG-1];
    reg [IDX_W-1:0] fadj_e [0:MAX_N-1][0:MAX_DEG-1];
    reg [7:0]       fdeg   [0:MAX_N-1];

    reg visited [0:MAX_N-1];
    reg [IDX_W-1:0] bfs_q [0:MAX_N-1];
    reg [IDX_W-1:0] q_hd, q_tl;

    reg [IDX_W-1:0] peel_root [0:MAX_N-1];
    reg [7:0] remaining [0:MAX_N-1];
    reg peeled_edge [0:MAX_E-1];

    reg [IDX_W-1:0] peel_q [0:MAX_N-1];
    reg [IDX_W-1:0] pq_hd, pq_tl;

    reg [IDX_W-1:0] idx;
    reg [IDX_W-1:0] cur_u;
    reg [7:0]       deg_i;
    reg [IDX_W-1:0] sp;
    reg [IDX_W-1:0] root_cand;
    reg             found_leaf;
    reg             got_nbr;
    reg [IDX_W-1:0] p_node, e_id;

    integer i, e, u, v, w;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done <= 1'b0;
            peel_ops <= 32'd0;
            for (e = 0; e < MAX_E; e = e + 1)
                corr_bits[e] <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        n_nodes <= num_nodes;
                        n_edges <= num_edges;
                        peel_ops <= 32'd0;
                        for (e = 0; e < MAX_E; e = e + 1) begin
                            corr_bits[e] <= 1'b0;
                            solid[e] <= (e < num_edges) ? solid_bits[e] : 1'b0;
                        end
                        for (i = 0; i < MAX_N; i = i + 1) begin
                            if (i < num_nodes) begin
                                is_bnd[i] <= bnd_mem[i*8];
                                syn_w[i]  <= syn_mem[i*8];
                            end
                        end
                        for (e = 0; e < MAX_E; e = e + 1) begin
                            if (e < num_edges) begin
                                edge_u[e] <= eu_mem[e*IDX_W +: IDX_W];
                                edge_v[e] <= ev_mem[e*IDX_W +: IDX_W];
                            end
                        end
                        idx <= {IDX_W{1'b0}};
                        state <= S_BUILD_CLR;
                    end
                end

                S_BUILD_CLR: begin
                    if (idx < MAX_N[IDX_W-1:0]) begin
                        sdeg[idx] = 8'd0;
                        fdeg[idx] = 8'd0;
                        visited[idx] = 1'b0;
                        remaining[idx] = 8'd0;
                        peel_root[idx] = idx;
                        idx <= idx + 1'b1;
                    end else begin
                        idx <= {IDX_W{1'b0}};
                        state <= S_BUILD_ECLR;
                    end
                end

                S_BUILD_ECLR: begin
                    if (idx < MAX_E[IDX_W-1:0]) begin
                        peeled_edge[idx] = 1'b0;
                        idx <= idx + 1'b1;
                    end else begin
                        idx <= {IDX_W{1'b0}};
                        state <= S_BUILD_E;
                    end
                end

                S_BUILD_E: begin
                    if (idx >= n_edges) begin
                        idx <= {IDX_W{1'b0}};
                        state <= S_F_SEEK;
                    end else begin
                        if (solid[idx]) begin
                            u = edge_u[idx];
                            v = edge_v[idx];
                            if (sdeg[u] < MAX_DEG) begin
                                sadj_n[u][sdeg[u]] = v;
                                sadj_e[u][sdeg[u]] = idx;
                                sdeg[u] = sdeg[u] + 8'd1;
                            end
                            if (sdeg[v] < MAX_DEG) begin
                                sadj_n[v][sdeg[v]] = u;
                                sadj_e[v][sdeg[v]] = idx;
                                sdeg[v] = sdeg[v] + 8'd1;
                            end
                        end
                        idx <= idx + 1'b1;
                    end
                end

                S_F_SEEK: begin
                    if (idx >= n_nodes) begin
                        idx <= {IDX_W{1'b0}};
                        state <= S_R_CLR;
                    end else if (!visited[idx]) begin
                        visited[idx] = 1'b1;
                        bfs_q[0] = idx;
                        q_hd = {IDX_W{1'b0}};
                        q_tl = {{(IDX_W-1){1'b0}}, 1'b1};
                        state <= S_F_POP;
                    end else begin
                        idx <= idx + 1'b1;
                    end
                end

                S_F_POP: begin
                    if (q_hd == q_tl) begin
                        idx <= idx + 1'b1;
                        state <= S_F_SEEK;
                    end else begin
                        cur_u = bfs_q[q_hd];
                        q_hd = q_hd + 1'b1;
                        deg_i = 8'd0;
                        state <= S_F_EXP;
                    end
                end

                S_F_EXP: begin
                    if (deg_i >= sdeg[cur_u] || deg_i >= MAX_DEG[7:0]) begin
                        state <= S_F_POP;
                    end else begin
                        w = sadj_n[cur_u][deg_i];
                        e = sadj_e[cur_u][deg_i];
                        if (!visited[w]) begin
                            visited[w] = 1'b1;
                            if (fdeg[cur_u] < MAX_DEG) begin
                                fadj_n[cur_u][fdeg[cur_u]] = w[IDX_W-1:0];
                                fadj_e[cur_u][fdeg[cur_u]] = e[IDX_W-1:0];
                                fdeg[cur_u] = fdeg[cur_u] + 8'd1;
                            end
                            if (fdeg[w] < MAX_DEG) begin
                                fadj_n[w][fdeg[w]] = cur_u;
                                fadj_e[w][fdeg[w]] = e[IDX_W-1:0];
                                fdeg[w] = fdeg[w] + 8'd1;
                            end
                            bfs_q[q_tl] = w[IDX_W-1:0];
                            q_tl = q_tl + 1'b1;
                        end
                        deg_i = deg_i + 8'd1;
                    end
                end

                S_R_CLR: begin
                    if (idx < MAX_N[IDX_W-1:0]) begin
                        visited[idx] = 1'b0;
                        idx <= idx + 1'b1;
                    end else begin
                        idx <= {IDX_W{1'b0}};
                        state <= S_R_SEEK;
                    end
                end

                S_R_SEEK: begin
                    if (idx >= n_nodes) begin
                        idx <= {IDX_W{1'b0}};
                        state <= S_SEED_REM;
                    end else if (!visited[idx]) begin
                        bfs_q[0] = idx;
                        q_hd = {{(IDX_W-1){1'b0}}, 1'b1};
                        visited[idx] = 1'b1;
                        q_tl = {IDX_W{1'b0}};
                        state <= S_R_POP;
                    end else begin
                        idx <= idx + 1'b1;
                    end
                end

                S_R_POP: begin
                    if (q_hd == 0) begin
                        root_cand = (q_tl != 0) ? peel_q[0] : idx;
                        found_leaf = 1'b0;
                        deg_i = 8'd0; // reuse as peel_q scan index
                        state <= S_R_SCAN_BND;
                    end else begin
                        sp = q_hd - 1;
                        cur_u = bfs_q[sp];
                        peel_q[q_tl] = cur_u;
                        q_tl = q_tl + 1'b1;
                        deg_i = 8'd0;
                        state <= S_R_EXP;
                    end
                end

                S_R_EXP: begin
                    if (deg_i >= fdeg[cur_u] || deg_i >= MAX_DEG[7:0]) begin
                        q_hd = sp;
                        state <= S_R_POP;
                    end else begin
                        w = fadj_n[cur_u][deg_i];
                        if (!visited[w]) begin
                            visited[w] = 1'b1;
                            bfs_q[sp] = w[IDX_W-1:0];
                            sp = sp + 1;
                        end
                        deg_i = deg_i + 8'd1;
                    end
                end

                S_R_SCAN_BND: begin
                    if (deg_i >= q_tl) begin
                        deg_i = 8'd0;
                        state <= found_leaf ? S_R_ASSIGN : S_R_SCAN_DEG;
                    end else begin
                        if (is_bnd[peel_q[deg_i]]) begin
                            root_cand = peel_q[deg_i];
                            found_leaf = 1'b1;
                            deg_i = q_tl[7:0]; // force done next
                        end else
                            deg_i = deg_i + 8'd1;
                    end
                end

                S_R_SCAN_DEG: begin
                    if (deg_i >= q_tl) begin
                        deg_i = 8'd0;
                        state <= S_R_ASSIGN;
                    end else begin
                        if (fdeg[peel_q[deg_i]] == 8'd1) begin
                            root_cand = peel_q[deg_i];
                            found_leaf = 1'b1;
                            deg_i = q_tl[7:0];
                        end else
                            deg_i = deg_i + 8'd1;
                    end
                end

                S_R_ASSIGN: begin
                    if (deg_i >= q_tl) begin
                        idx <= idx + 1'b1;
                        state <= S_R_SEEK;
                    end else begin
                        peel_root[peel_q[deg_i]] = root_cand;
                        deg_i = deg_i + 8'd1;
                    end
                end

                S_SEED_REM: begin
                    if (idx >= n_nodes) begin
                        pq_hd = {IDX_W{1'b0}};
                        pq_tl = {IDX_W{1'b0}};
                        idx <= {IDX_W{1'b0}};
                        state <= S_SEED_ENQ;
                    end else begin
                        remaining[idx] = fdeg[idx];
                        idx <= idx + 1'b1;
                    end
                end

                S_SEED_ENQ: begin
                    if (idx >= n_nodes) begin
                        state <= S_PEEL_TAKE;
                    end else begin
                        if (remaining[idx] == 8'd1 && idx != peel_root[idx]) begin
                            peel_q[pq_tl] = idx;
                            pq_tl = pq_tl + 1'b1;
                        end
                        idx <= idx + 1'b1;
                    end
                end

                S_PEEL_TAKE: begin
                    if (pq_hd == pq_tl) begin
                        state <= S_DONE;
                        done <= 1'b1;
                    end else begin
                        cur_u = peel_q[pq_hd];
                        pq_hd = pq_hd + 1'b1;
                        if (remaining[cur_u] != 8'd0 && cur_u != peel_root[cur_u]) begin
                            got_nbr = 1'b0;
                            p_node = {IDX_W{1'b0}};
                            e_id = {IDX_W{1'b0}};
                            deg_i = 8'd0;
                            state <= S_PEEL_FIND;
                        end
                    end
                end

                S_PEEL_FIND: begin
                    if (got_nbr || deg_i >= fdeg[cur_u] || deg_i >= MAX_DEG[7:0]) begin
                        state <= got_nbr ? S_PEEL_APPLY : S_PEEL_TAKE;
                    end else begin
                        if (!peeled_edge[fadj_e[cur_u][deg_i]]) begin
                            got_nbr = 1'b1;
                            p_node = fadj_n[cur_u][deg_i];
                            e_id = fadj_e[cur_u][deg_i];
                        end
                        deg_i = deg_i + 8'd1;
                    end
                end

                S_PEEL_APPLY: begin
                    peeled_edge[e_id] = 1'b1;
                    remaining[cur_u] = remaining[cur_u] - 8'd1;
                    peel_ops <= peel_ops + 32'd1;
                    if (syn_w[cur_u])
                        corr_bits[e_id] <= 1'b1;
                    syn_w[p_node] = syn_w[p_node] ^ syn_w[cur_u];
                    syn_w[cur_u] = 1'b0;
                    remaining[p_node] = remaining[p_node] - 8'd1;
                    if (remaining[p_node] == 8'd1 && p_node != peel_root[p_node]) begin
                        peel_q[pq_tl] = p_node;
                        pq_tl = pq_tl + 1'b1;
                    end
                    state <= S_PEEL_TAKE;
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
