// Aether UF — Helios-2 micro grow (M40): H9 LUTRAM banks + 2-node grow datapath.
// Physical lattice: N=2, M=1, CAP=10. Two virtual contexts share one grow engine.
// Spec: Docs/Helios2_Micro_Grow; Helios arXiv:2406.08491; M39 H9.

`timescale 1ns / 1ps

module aether_uf_helios2_micro_grow #(
    parameter int IDX_W = 8,
    parameter int CAP   = 10
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             switch_pulse,
    input  wire             next_ctx,
    input  wire             start_grow,
    input  wire [1:0]       syn,
    input  wire [1:0]       is_bnd,
    output reg              cur_ctx,
    output reg              done_grow,
    output reg  [15:0]      cycles,
    output wire             solid0,
    output wire [15:0]      growth0
);
    localparam int N = 2;

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
    reg [15:0]      growth;
    reg             solid;
    reg [15:0]      cycles_live;

    (* ram_style = "distributed" *) reg [IDX_W-1:0] b_root    [0:1][0:N-1];
    (* ram_style = "distributed" *) reg [15:0]      b_size    [0:1][0:N-1];
    (* ram_style = "distributed" *) reg             b_parity  [0:1][0:N-1];
    (* ram_style = "distributed" *) reg             b_cbound  [0:1][0:N-1];
    (* ram_style = "distributed" *) reg             b_is_root [0:1][0:N-1];
    (* ram_style = "distributed" *) reg [15:0]      b_growth  [0:1];
    (* ram_style = "distributed" *) reg             b_solid   [0:1];
    (* ram_style = "distributed" *) reg [15:0]      b_cycles  [0:1];

    wire act0 = is_root[0] && parity[0] && !cbound[0];
    wire act1 = is_root[1] && parity[1] && !cbound[1];
    wire ca0  = is_root[root[0]] && parity[root[0]] && !cbound[root[0]];
    wire ca1  = is_root[root[1]] && parity[root[1]] && !cbound[root[1]];
    wire any_active = act0 | act1;

    wire same = (root[0] == root[1]);
    wire [15:0] delta =
        {15'd0, (ca0 & ~same)} + {15'd0, (ca1 & ~same)};
    wire [15:0] g_next = growth + delta;
    wire solidify = !solid && (delta != 0) && (g_next >= CAP[15:0]);
    wire solid_now = solid | solidify;

    assign solid0  = solid;
    assign growth0 = growth;

    reg [IDX_W-1:0] w_root    [0:N-1];
    reg [15:0]      w_size    [0:N-1];
    reg             w_parity  [0:N-1];
    reg             w_cbound  [0:N-1];
    reg             w_is_root [0:N-1];
    integer i, c;

    task automatic find_root;
        input integer v;
        output integer r;
        integer guard;
        begin
            r = v;
            for (guard = 0; guard < N; guard = guard + 1) begin
                if (w_is_root[r]) guard = N;
                else r = w_root[r];
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
            done_grow <= 1'b0;
            cur_ctx <= 1'b0;
            cycles <= 16'd0;
            cycles_live <= 16'd0;
            growth <= 16'd0;
            solid <= 1'b0;
            for (i = 0; i < N; i = i + 1) begin
                root[i] <= i[IDX_W-1:0];
                size[i] <= 16'd1;
                parity[i] <= 1'b0;
                cbound[i] <= 1'b0;
                is_root[i] <= 1'b1;
            end
            for (c = 0; c < 2; c = c + 1) begin
                b_growth[c] <= 16'd0;
                b_solid[c] <= 1'b0;
                b_cycles[c] <= 16'd0;
                for (i = 0; i < N; i = i + 1) begin
                    b_root[c][i] <= i[IDX_W-1:0];
                    b_size[c][i] <= 16'd1;
                    b_parity[c][i] <= 1'b0;
                    b_cbound[c][i] <= 1'b0;
                    b_is_root[c][i] <= 1'b1;
                end
            end
        end else if (switch_pulse && (state == S_IDLE || state == S_DONE)) begin
            // 1-cycle Helios switch: store live → bank[cur], load bank[next].
            for (i = 0; i < N; i = i + 1) begin
                b_root[cur_ctx][i]    <= root[i];
                b_size[cur_ctx][i]    <= size[i];
                b_parity[cur_ctx][i]  <= parity[i];
                b_cbound[cur_ctx][i]  <= cbound[i];
                b_is_root[cur_ctx][i] <= is_root[i];
                root[i]    <= b_root[next_ctx][i];
                size[i]    <= b_size[next_ctx][i];
                parity[i]  <= b_parity[next_ctx][i];
                cbound[i]  <= b_cbound[next_ctx][i];
                is_root[i] <= b_is_root[next_ctx][i];
            end
            b_growth[cur_ctx] <= growth;
            b_solid[cur_ctx]  <= solid;
            b_cycles[cur_ctx] <= cycles_live;
            growth      <= b_growth[next_ctx];
            solid       <= b_solid[next_ctx];
            cycles_live <= b_cycles[next_ctx];
            cycles      <= b_cycles[next_ctx];
            cur_ctx     <= next_ctx;
            done_grow   <= 1'b0;
            state       <= S_IDLE;
        end else begin
            case (state)
                S_IDLE: begin
                    done_grow <= 1'b0;
                    if (start_grow) begin
                        cycles_live <= 16'd0;
                        cycles <= 16'd0;
                        state <= S_INIT;
                    end
                end
                S_INIT: begin
                    for (i = 0; i < N; i = i + 1) begin
                        root[i] <= i[IDX_W-1:0];
                        size[i] <= 16'd1;
                        parity[i] <= syn[i];
                        cbound[i] <= is_bnd[i];
                        is_root[i] <= 1'b1;
                    end
                    growth <= 16'd0;
                    solid <= 1'b0;
                    state <= S_RUN;
                end
                S_RUN: begin
                    if (!any_active) begin
                        state <= S_DONE;
                        done_grow <= 1'b1;
                        cycles <= cycles_live;
                    end else begin
                        cycles_live <= cycles_live + 16'd1;
                        cycles <= cycles_live + 16'd1;
                        if (!solid && delta != 0) begin
                            growth <= g_next;
                            if (solidify) solid <= 1'b1;
                        end
                        for (i = 0; i < N; i = i + 1) begin
                            w_root[i]    = root[i];
                            w_size[i]    = size[i];
                            w_parity[i]  = parity[i];
                            w_cbound[i]  = cbound[i];
                            w_is_root[i] = is_root[i];
                        end
                        if (solid_now) do_union(0, 1);
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
                    done_grow <= 1'b1;
                    if (!start_grow)
                        state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
