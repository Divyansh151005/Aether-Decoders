// Aether UF — parameterized edge-list PE mesh grow (M37/M38).
// Neighbor-endpoint growth δ (cluster-active at DSU roots); ordered SoA merges.
// M38: runtime num_nodes/num_edges for multi-case grow→peel.
//
// Spec: Docs/Pe_Mesh_Graph, Docs/Pe_Mesh_Decode; Hardware_Mapping H1–H5;
// Helios arXiv:2406.08491 / 2301.08419 §IV. Not Helios-n (H9).

`timescale 1ns / 1ps

module aether_uf_pe_graph_grow #(
    parameter int N     = 4,
    parameter int M     = 4,
    parameter int CAP   = 10,
    parameter int IDX_W = 8
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,
    input  wire [IDX_W-1:0]     num_nodes,
    input  wire [IDX_W-1:0]     num_edges,
    input  wire [N-1:0]         syn,
    input  wire [N-1:0]         is_bnd,
    input  wire [IDX_W*M-1:0]   eu_bus,
    input  wire [IDX_W*M-1:0]   ev_bus,
    input  wire [16*M-1:0]      cap_bus,
    output reg                  done,
    output wire [M-1:0]         solid_bits,
    output wire [16*M-1:0]      growth_bus,
    output reg  [31:0]          cycles
);
    localparam S_IDLE = 2'd0;
    localparam S_INIT = 2'd1;
    localparam S_RUN  = 2'd2;
    localparam S_DONE = 2'd3;

    reg [1:0] state;

    reg [IDX_W-1:0] root    [0:N-1];
    reg [15:0]      size    [0:N-1];
    reg             parity  [0:N-1];
    reg             cbound  [0:N-1];
    reg             is_root [0:N-1];

    reg [15:0] growth [0:M-1];
    reg        solid  [0:M-1];

    wire [IDX_W-1:0] eu  [0:M-1];
    wire [IDX_W-1:0] ev  [0:M-1];
    wire [15:0]      cap [0:M-1];
    genvar gi;
    generate
        for (gi = 0; gi < M; gi = gi + 1) begin : g_ep
            assign eu[gi]  = eu_bus[gi*IDX_W +: IDX_W];
            assign ev[gi]  = ev_bus[gi*IDX_W +: IDX_W];
            assign cap[gi] = cap_bus[gi*16 +: 16];
        end
    endgenerate

    wire act [0:N-1];
    wire ca  [0:N-1];
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : g_act
            assign act[gi] = is_root[gi] && parity[gi] && !cbound[gi];
            assign ca[gi] =
                is_root[root[gi]] && parity[root[gi]] && !cbound[root[gi]];
        end
    endgenerate

    wire [N-1:0] act_bus;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : g_ab
            assign act_bus[gi] = act[gi] && (gi[IDX_W-1:0] < num_nodes);
        end
    endgenerate
    wire any_active = |act_bus;

    wire [15:0] delta     [0:M-1];
    wire [15:0] g_next    [0:M-1];
    wire        solidify  [0:M-1];
    wire        solid_now [0:M-1];
    wire        edge_live [0:M-1];
    generate
        for (gi = 0; gi < M; gi = gi + 1) begin : g_edge
            assign edge_live[gi] = (gi[IDX_W-1:0] < num_edges);
            wire same = (root[eu[gi]] == root[ev[gi]]);
            assign delta[gi] = edge_live[gi] ?
                ({15'd0, (ca[eu[gi]] & ~same)} + {15'd0, (ca[ev[gi]] & ~same)}) :
                16'd0;
            assign g_next[gi] = growth[gi] + delta[gi];
            assign solidify[gi] =
                edge_live[gi] && !solid[gi] && (delta[gi] != 0) &&
                (g_next[gi] >= cap[gi]);
            assign solid_now[gi] = solid[gi] | solidify[gi];
            assign solid_bits[gi] = solid[gi];
            assign growth_bus[gi*16 +: 16] = growth[gi];
        end
    endgenerate

    reg [IDX_W-1:0] w_root    [0:N-1];
    reg [15:0]      w_size    [0:N-1];
    reg             w_parity  [0:N-1];
    reg             w_cbound  [0:N-1];
    reg             w_is_root [0:N-1];
    integer i, e;

    task automatic find_root;
        input integer v;
        output integer r;
        integer guard;
        begin
            r = v;
            for (guard = 0; guard < N; guard = guard + 1) begin
                if (w_is_root[r]) begin
                    guard = N;
                end else begin
                    r = w_root[r];
                end
            end
        end
    endtask

    task automatic do_union;
        input integer uu;
        input integer vv;
        integer ru, rv, winner, loser;
        begin
            find_root(uu, ru);
            find_root(vv, rv);
            if (ru != rv) begin
                if ((w_size[ru] > w_size[rv]) ||
                    (w_size[ru] == w_size[rv] && ru < rv)) begin
                    winner = ru; loser = rv;
                end else begin
                    winner = rv; loser = ru;
                end
                w_root[loser]    = winner[IDX_W-1:0];
                w_is_root[loser] = 1'b0;
                w_parity[winner] = w_parity[winner] ^ w_parity[loser];
                w_cbound[winner] = w_cbound[winner] | w_cbound[loser];
                w_size[winner]   = w_size[winner] + w_size[loser];
                w_parity[loser]  = 1'b0;
                w_cbound[loser]  = 1'b0;
                w_size[loser]    = 16'd0;
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done <= 1'b0;
            cycles <= 32'd0;
            for (i = 0; i < N; i = i + 1) begin
                root[i] <= i[IDX_W-1:0];
                size[i] <= 16'd1;
                parity[i] <= 1'b0;
                cbound[i] <= 1'b0;
                is_root[i] <= 1'b1;
            end
            for (e = 0; e < M; e = e + 1) begin
                growth[e] <= 16'd0;
                solid[e] <= 1'b0;
            end
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        cycles <= 32'd0;
                        state <= S_INIT;
                    end
                end
                S_INIT: begin
                    for (i = 0; i < N; i = i + 1) begin
                        root[i] <= i[IDX_W-1:0];
                        size[i] <= 16'd1;
                        if (i[IDX_W-1:0] < num_nodes) begin
                            parity[i] <= syn[i];
                            cbound[i] <= is_bnd[i];
                            is_root[i] <= 1'b1;
                        end else begin
                            parity[i] <= 1'b0;
                            cbound[i] <= 1'b0;
                            is_root[i] <= 1'b0;
                        end
                    end
                    for (e = 0; e < M; e = e + 1) begin
                        growth[e] <= 16'd0;
                        solid[e] <= 1'b0;
                    end
                    state <= S_RUN;
                end
                S_RUN: begin
                    if (!any_active) begin
                        state <= S_DONE;
                        done <= 1'b1;
                    end else begin
                        cycles <= cycles + 32'd1;
                        for (e = 0; e < M; e = e + 1) begin
                            if (edge_live[e] && !solid[e] && delta[e] != 0) begin
                                growth[e] <= g_next[e];
                                if (solidify[e]) solid[e] <= 1'b1;
                            end
                        end
                        for (i = 0; i < N; i = i + 1) begin
                            w_root[i]    = root[i];
                            w_size[i]    = size[i];
                            w_parity[i]  = parity[i];
                            w_cbound[i]  = cbound[i];
                            w_is_root[i] = is_root[i];
                        end
                        for (e = 0; e < M; e = e + 1) begin
                            if (edge_live[e] && solid_now[e])
                                do_union(eu[e], ev[e]);
                        end
                        for (i = 0; i < N; i = i + 1) begin
                            root[i]    <= w_root[i];
                            size[i]    <= w_size[i];
                            parity[i]  <= w_parity[i];
                            cbound[i]  <= w_cbound[i];
                            is_root[i] <= w_is_root[i];
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
