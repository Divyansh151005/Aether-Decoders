// Aether UF — two-PE grow/merge with neighbor ports (M34).
// Blueprint two_node: syn=[1,1], W=10 → cycles=5, solid=1 (helios_pe / M17).

`timescale 1ns / 1ps

module aether_uf_pe_pair_grow (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        syn0,
    input  wire        syn1,
    output reg         done,
    output wire        solid0,
    output wire [15:0] growth0,
    output reg  [15:0] cycles
);
    localparam int IDX_W = 8;
    localparam [15:0] CAP0 = 16'd10;

    localparam S_IDLE = 2'd0;
    localparam S_INIT = 2'd1;
    localparam S_RUN  = 2'd2;
    localparam S_DONE = 2'd3;

    reg [1:0] state;
    reg       start_pe;

    wire [IDX_W-1:0] root0, root1;
    wire act0, act1;
    wire [15:0] size0, size1;
    wire par0, par1, cb0, cb1;
    wire is_root0, is_root1;
    wire owns0, owns1;
    wire [15:0] g0, g1;
    wire solid_pe0, solid_pe1;
    wire edge_now0, edge_now1;

    wire any_active = act0 | act1;
    wire do_step = (state == S_RUN) && any_active;

    // Owner publishes edge_solid_now; both PEs use PE0's (lower-id) solid for merge.
    wire edge_solid_shared = edge_now0;

    aether_uf_pe_vertex #(.MY_ID(0), .IDX_W(IDX_W)) u_pe0 (
        .clk(clk), .rst_n(rst_n), .start(start_pe),
        .syn(syn0), .is_bnd(1'b0),
        .neigh_id(8'd1), .capacity(CAP0),
        .nbr_root(root1), .nbr_active(act1), .nbr_size(size1),
        .nbr_parity(par1), .nbr_cbound(cb1), .nbr_is_root(is_root1),
        .edge_solid_in(1'b0),
        .root(root0), .active(act0), .size(size0), .parity(par0),
        .cbound(cb0), .is_root(is_root0),
        .growth(g0), .solid(solid_pe0), .owns_edge(owns0),
        .edge_solid_now(edge_now0),
        .pulse_step(do_step)
    );

    aether_uf_pe_vertex #(.MY_ID(1), .IDX_W(IDX_W)) u_pe1 (
        .clk(clk), .rst_n(rst_n), .start(start_pe),
        .syn(syn1), .is_bnd(1'b0),
        .neigh_id(8'd0), .capacity(CAP0),
        .nbr_root(root0), .nbr_active(act0), .nbr_size(size0),
        .nbr_parity(par0), .nbr_cbound(cb0), .nbr_is_root(is_root0),
        .edge_solid_in(edge_solid_shared),
        .root(root1), .active(act1), .size(size1), .parity(par1),
        .cbound(cb1), .is_root(is_root1),
        .growth(g1), .solid(solid_pe1), .owns_edge(owns1),
        .edge_solid_now(edge_now1),
        .pulse_step(do_step)
    );

    assign solid0  = solid_pe0;
    assign growth0 = g0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done <= 1'b0;
            cycles <= 16'd0;
            start_pe <= 1'b0;
        end else begin
            start_pe <= 1'b0;
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        cycles <= 16'd0;
                        start_pe <= 1'b1;
                        state <= S_INIT;
                    end
                end
                S_INIT: begin
                    state <= S_RUN;
                end
                S_RUN: begin
                    if (!any_active) begin
                        state <= S_DONE;
                        done <= 1'b1;
                    end else begin
                        cycles <= cycles + 16'd1;
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
