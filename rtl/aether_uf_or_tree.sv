// Aether UF — H8 controller OR-tree (PE-grid prep).
//
// Spec: Docs/Hardware_Mapping H8; Docs/Pe_Grid_Prep.
// Helios arXiv:2406.08491 §IV-B: tree of control nodes aggregates PE
// busy / odd status. Aether uses any_active = OR(odd ∧ ¬cluster_boundary)
// at the PE leaf; this module only reduces the leaf vectors.
//
// Topology: binary tree (pad to power-of-two), not a single flat OR bus,
// so later pipeline registers can sit on tree levels without redesign.

`timescale 1ns / 1ps

module aether_uf_or_tree #(
    parameter int N = 8
) (
    input  wire [N-1:0] busy_in,
    input  wire [N-1:0] active_in,
    output wire         any_busy,
    output wire         any_active
);
    localparam int LOG2 = (N <= 1) ? 0 : $clog2(N);
    localparam int PW   = 1 << LOG2;

    wire [PW-1:0] busy_pad;
    wire [PW-1:0] act_pad;

    genvar i;
    generate
        for (i = 0; i < PW; i = i + 1) begin : g_pad
            if (i < N) begin : g_leaf
                assign busy_pad[i] = busy_in[i];
                assign act_pad[i]  = active_in[i];
            end else begin : g_zero
                assign busy_pad[i] = 1'b0;
                assign act_pad[i]  = 1'b0;
            end
        end
    endgenerate

    generate
        if (PW == 1) begin : g_root1
            assign any_busy   = busy_pad[0];
            assign any_active = act_pad[0];
        end else begin : g_tree
            /* verilator lint_off DECLFILENAME */
            aether_uf_or_tree_level #(.W(PW)) u_red (
                .busy_in (busy_pad),
                .act_in  (act_pad),
                .any_busy(any_busy),
                .any_act (any_active)
            );
            /* verilator lint_on DECLFILENAME */
        end
    endgenerate
endmodule

/* verilator lint_off DECLFILENAME */
// Recursive binary OR reduction over a power-of-two vector.
module aether_uf_or_tree_level #(
    parameter int W = 8
) (
    input  wire [W-1:0] busy_in,
    input  wire [W-1:0] act_in,
    output wire         any_busy,
    output wire         any_act
);
    generate
        if (W == 1) begin : g_leaf
            assign any_busy = busy_in[0];
            assign any_act  = act_in[0];
        end else begin : g_pair
            localparam int H = W / 2;
            wire [H-1:0] busy_mid;
            wire [H-1:0] act_mid;
            genvar k;
            for (k = 0; k < H; k = k + 1) begin : g_or
                assign busy_mid[k] = busy_in[2*k] | busy_in[2*k+1];
                assign act_mid[k]  = act_in[2*k]  | act_in[2*k+1];
            end
            aether_uf_or_tree_level #(.W(H)) u_next (
                .busy_in (busy_mid),
                .act_in  (act_mid),
                .any_busy(any_busy),
                .any_act (any_act)
            );
        end
    endgenerate
endmodule
/* verilator lint_on DECLFILENAME */
