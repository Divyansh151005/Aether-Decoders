// Aether UF — parameterized line PE mesh (M36).
// Neighbor-port growth (S3 on lower-id PE); ordered edge merges (SoA / helios_pe).
// Blueprint: line3 N=3 → cycles=10 solid=2'b11; line4 N=4 → cycles=15 solid=3'b111.
//
// Spec: Docs/Pe_Grow_Datapath; Hardware_Mapping H1–H5; Helios arXiv:2301.08419 §IV.

`timescale 1ns / 1ps

module aether_uf_pe_line_grow #(
    parameter int N     = 4,
    parameter int CAP   = 10,
    parameter int IDX_W = 8
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,
    input  wire [N-1:0]         syn,
    output reg                  done,
    output wire [N-2:0]         solid_bits,
    output wire [16*(N-1)-1:0]  growth_bus,
    output reg  [15:0]          cycles
);
    localparam int M = N - 1;

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

    wire act [0:N-1];
    wire ca  [0:N-1]; // cluster-active at endpoint's root (helios_pe / Aether H4)
    genvar gi;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : g_act
            assign act[gi] = is_root[gi] && parity[gi] && !cbound[gi];
            // After union, losers clear local parity; activity lives at the root PE.
            assign ca[gi] =
                is_root[root[gi]] && parity[root[gi]] && !cbound[root[gi]];
        end
    endgenerate

    // any_active OR-reduce over roots (equiv. OR of ca when every node points at a root)
    wire [N-1:0] act_bus;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : g_ab
            assign act_bus[gi] = act[gi];
        end
    endgenerate
    wire any_active = |act_bus;

    wire [15:0] delta     [0:M-1];
    wire [15:0] g_next    [0:M-1];
    wire        solidify  [0:M-1];
    wire        solid_now [0:M-1];
    generate
        for (gi = 0; gi < M; gi = gi + 1) begin : g_edge
            wire same = (root[gi] == root[gi+1]);
            assign delta[gi] =
                {15'd0, (ca[gi] & ~same)} + {15'd0, (ca[gi+1] & ~same)};
            assign g_next[gi] = growth[gi] + delta[gi];
            assign solidify[gi] =
                !solid[gi] && (delta[gi] != 0) && (g_next[gi] >= CAP[15:0]);
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
            cycles <= 16'd0;
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
                        cycles <= 16'd0;
                        state <= S_INIT;
                    end
                end
                S_INIT: begin
                    for (i = 0; i < N; i = i + 1) begin
                        root[i] <= i[IDX_W-1:0];
                        size[i] <= 16'd1;
                        parity[i] <= syn[i];
                        cbound[i] <= 1'b0;
                        is_root[i] <= 1'b1;
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
                        cycles <= cycles + 16'd1;
                        for (e = 0; e < M; e = e + 1) begin
                            if (!solid[e] && delta[e] != 0) begin
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
                            if (solid_now[e]) do_union(e, e + 1);
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
