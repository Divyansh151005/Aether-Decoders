// Aether UF — PE vertex with one neighbor port + S3 growth + local merge (M34).
// Pair mesh uses this. Line3 (M35) uses aether_uf_pe_line3_grow (multi-edge ordered merge).

`timescale 1ns / 1ps

module aether_uf_pe_vertex #(
    parameter int MY_ID = 0,
    parameter int IDX_W = 8
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             start,
    input  wire             syn,
    input  wire             is_bnd,
    input  wire [IDX_W-1:0] neigh_id,
    input  wire [15:0]      capacity,
    input  wire [IDX_W-1:0] nbr_root,
    input  wire             nbr_active,
    input  wire [15:0]      nbr_size,
    input  wire             nbr_parity,
    input  wire             nbr_cbound,
    input  wire             nbr_is_root,
    input  wire             edge_solid_in,
    output reg  [IDX_W-1:0] root,
    output wire             active,
    output reg  [15:0]      size,
    output reg              parity,
    output reg              cbound,
    output reg              is_root,
    output reg  [15:0]      growth,
    output reg              solid,
    output wire             owns_edge,
    output wire             edge_solid_now,
    input  wire             pulse_step
);
    localparam [IDX_W-1:0] ME = MY_ID[IDX_W-1:0];

    assign owns_edge = (ME < neigh_id);
    assign active    = is_root && parity && !cbound;

    wire same_root = (root == nbr_root);
    wire [15:0] delta =
        {15'd0, (active & ~same_root)} + {15'd0, (nbr_active & ~same_root)};

    wire [15:0] growth_next = growth + delta;
    wire        solidify    = owns_edge && !solid && (delta != 0) && (growth_next >= capacity);

    assign edge_solid_now = owns_edge ? (solid | solidify) : edge_solid_in;

    wire do_merge = edge_solid_now && !same_root && is_root && nbr_is_root;
    wire i_win = do_merge &&
                 ((size > nbr_size) || (size == nbr_size && root < nbr_root));
    wire i_lose = do_merge && !i_win;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            root    <= ME;
            size    <= 16'd1;
            parity  <= 1'b0;
            cbound  <= 1'b0;
            is_root <= 1'b1;
            growth  <= 16'd0;
            solid   <= 1'b0;
        end else if (start) begin
            root    <= ME;
            size    <= 16'd1;
            parity  <= syn;
            cbound  <= is_bnd;
            is_root <= 1'b1;
            growth  <= 16'd0;
            solid   <= 1'b0;
        end else if (pulse_step) begin
            if (owns_edge && !solid && (delta != 0)) begin
                growth <= growth_next;
                if (solidify)
                    solid <= 1'b1;
            end
            if (i_win) begin
                size   <= size + nbr_size;
                parity <= parity ^ nbr_parity;
                cbound <= cbound | nbr_cbound;
            end else if (i_lose) begin
                root    <= nbr_root;
                is_root <= 1'b0;
                parity  <= 1'b0;
                cbound  <= 1'b0;
                size    <= 16'd0;
            end
        end
    end
endmodule
