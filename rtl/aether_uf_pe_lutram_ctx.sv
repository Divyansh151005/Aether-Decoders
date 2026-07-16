// Aether UF — Helios-n PE local context (H9 / M39).
// Models LUTRAM (distributed RAM) banks for multi-context PE state.
// Switch: one clock — store live → bank[cur], load bank[next] → live.
//
// Spec: Docs/Helios_n_H9; Hardware_Mapping H9; Helios arXiv:2406.08491
// (LUTRAM not BRAM; ≈1-cycle context switch). Not full Helios-n lattice.

`timescale 1ns / 1ps

module aether_uf_pe_lutram_ctx #(
    parameter int N_CTX = 2,
    parameter int IDX_W = 8,
    parameter int CTX_W = (N_CTX <= 2) ? 1 : $clog2(N_CTX)
) (
    input  wire                 clk,
    input  wire                 rst_n,
    // Load working (live) registers from TB / host (not a context switch).
    input  wire                 load_live,
    input  wire [IDX_W-1:0]     in_root,
    input  wire [15:0]          in_size,
    input  wire                 in_parity,
    input  wire                 in_cbound,
    input  wire                 in_is_root,
    input  wire [15:0]          in_growth,
    input  wire                 in_solid,
    // Helios-style context switch (1 cycle).
    input  wire                 switch_pulse,
    input  wire [CTX_W-1:0]     next_ctx,
    output reg  [CTX_W-1:0]     cur_ctx,
    output reg  [IDX_W-1:0]     root,
    output reg  [15:0]          size,
    output reg                  parity,
    output reg                  cbound,
    output reg                  is_root,
    output reg  [15:0]          growth,
    output reg                  solid
);
    // Shallow dual-port-style banks → map to LUTRAM/distributed RAM on FPGA.
    (* ram_style = "distributed" *) reg [IDX_W-1:0] bank_root    [0:N_CTX-1];
    (* ram_style = "distributed" *) reg [15:0]      bank_size    [0:N_CTX-1];
    (* ram_style = "distributed" *) reg             bank_parity  [0:N_CTX-1];
    (* ram_style = "distributed" *) reg             bank_cbound  [0:N_CTX-1];
    (* ram_style = "distributed" *) reg             bank_is_root [0:N_CTX-1];
    (* ram_style = "distributed" *) reg [15:0]      bank_growth  [0:N_CTX-1];
    (* ram_style = "distributed" *) reg             bank_solid   [0:N_CTX-1];

    integer c;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cur_ctx <= {CTX_W{1'b0}};
            root    <= {IDX_W{1'b0}};
            size    <= 16'd1;
            parity  <= 1'b0;
            cbound  <= 1'b0;
            is_root <= 1'b1;
            growth  <= 16'd0;
            solid   <= 1'b0;
            for (c = 0; c < N_CTX; c = c + 1) begin
                bank_root[c]    <= {IDX_W{1'b0}};
                bank_size[c]    <= 16'd1;
                bank_parity[c]  <= 1'b0;
                bank_cbound[c]  <= 1'b0;
                bank_is_root[c] <= 1'b1;
                bank_growth[c]  <= 16'd0;
                bank_solid[c]   <= 1'b0;
            end
        end else if (switch_pulse) begin
            // Store live into current context bank.
            bank_root[cur_ctx]    <= root;
            bank_size[cur_ctx]    <= size;
            bank_parity[cur_ctx]  <= parity;
            bank_cbound[cur_ctx]  <= cbound;
            bank_is_root[cur_ctx] <= is_root;
            bank_growth[cur_ctx]  <= growth;
            bank_solid[cur_ctx]   <= solid;
            // Load next context into live (same cycle as Helios).
            root    <= bank_root[next_ctx];
            size    <= bank_size[next_ctx];
            parity  <= bank_parity[next_ctx];
            cbound  <= bank_cbound[next_ctx];
            is_root <= bank_is_root[next_ctx];
            growth  <= bank_growth[next_ctx];
            solid   <= bank_solid[next_ctx];
            cur_ctx <= next_ctx;
        end else if (load_live) begin
            root    <= in_root;
            size    <= in_size;
            parity  <= in_parity;
            cbound  <= in_cbound;
            is_root <= in_is_root;
            growth  <= in_growth;
            solid   <= in_solid;
        end
    end
endmodule
