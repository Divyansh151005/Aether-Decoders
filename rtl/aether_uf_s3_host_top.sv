// Aether UF — S3 host-path top (M75 G4): syndrome ring in → grow → peel → obs egress out.
// Phenom d=3 r=1 (V=16 E=18). Static graph tables are ports (ROM-class on a board).
// Spec: Docs/G4_S3_Netlist_M75; Docs/Fpga_Bringup_Prep G4; Docs/Host_IO_H10.

`timescale 1ns / 1ps

module aether_uf_s3_host_top (
    input  wire           clk,
    input  wire           rst_n,
    // Host syndrome ingress (H10 ring)
    input  wire           wr_valid,
    output wire           wr_ready,
    input  wire [15:0]    wr_data,
    // Static graph
    input  wire [7:0]     num_nodes,
    input  wire [7:0]     num_edges,
    input  wire [15:0]    is_bnd,
    input  wire [143:0]   eu_bus,
    input  wire [143:0]   ev_bus,
    input  wire [287:0]   cap_bus,
    input  wire [1151:0]  obs_mask_bus,
    // Host observable egress
    input  wire           obs_ready,
    output wire           obs_valid,
    output wire [63:0]    obs_word,
    output wire [31:0]    status_peel_ops,
    output wire [31:0]    status_cycles,
    output wire [17:0]    status_corr
);
    localparam S_IDLE = 3'd0;
    localparam S_GROW = 3'd1;
    localparam S_PEEL = 3'd2;
    localparam S_OBS  = 3'd3;
    localparam S_DRAIN = 3'd4;

    reg  [2:0]  state;
    reg  [15:0] syn;
    reg         start_grow, start_peel, start_obs;
    wire        rd_valid;
    wire [15:0] rd_data;
    wire [7:0]  fill_count;
    wire        rd_ready = (state == S_IDLE) && rd_valid;
    wire        done_grow, done_peel, done_obs;
    wire [17:0] solid_bits, corr_bits;
    wire [31:0] cycles, peel_ops;

    reg [127:0] syn_mem, bnd_mem;
    integer k;
    always @(*) begin
        for (k = 0; k < 16; k = k + 1) begin
            syn_mem[k*8 +: 8] = {7'd0, syn[k]};
            bnd_mem[k*8 +: 8] = {7'd0, is_bnd[k]};
        end
    end

    aether_uf_syndrome_ring #(.WIDTH(16), .DEPTH(2)) u_ring (
        .clk(clk), .rst_n(rst_n),
        .wr_valid(wr_valid), .wr_ready(wr_ready), .wr_data(wr_data),
        .rd_valid(rd_valid), .rd_ready(rd_ready), .rd_data(rd_data),
        .fill_count(fill_count)
    );

    aether_uf_pe_mesh_decode_s3 u_dec (
        .clk(clk), .rst_n(rst_n),
        .start_grow(start_grow), .start_peel(start_peel),
        .num_nodes(num_nodes), .num_edges(num_edges),
        .syn(syn), .is_bnd(is_bnd),
        .eu_bus(eu_bus), .ev_bus(ev_bus), .cap_bus(cap_bus),
        .syn_mem(syn_mem), .bnd_mem(bnd_mem),
        .done_grow(done_grow), .done_peel(done_peel),
        .solid_bits(solid_bits), .corr_bits(corr_bits),
        .cycles(cycles), .peel_ops(peel_ops)
    );

    aether_uf_obs_egress #(.MAX_E(18), .IDX_W(8)) u_obs (
        .clk(clk), .rst_n(rst_n), .start(start_obs),
        .num_edges(num_edges), .corr_bits(corr_bits),
        .obs_mask_bus(obs_mask_bus),
        .peel_ops_in(peel_ops), .status_timeout_in(1'b0),
        .obs_ready(obs_ready), .obs_valid(obs_valid), .obs_word(obs_word),
        .status_peel_ops(status_peel_ops), .status_timeout(),
        .done(done_obs)
    );

    assign status_cycles = cycles;
    assign status_corr   = corr_bits;

    // Sequencer: start pulses are one clock; each stage waits for the previous done
    // to drop (done stays high until the next start) before sampling it again.
    reg seen_low;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            syn <= 16'd0;
            start_grow <= 1'b0;
            start_peel <= 1'b0;
            start_obs <= 1'b0;
            seen_low <= 1'b0;
        end else begin
            start_grow <= 1'b0;
            start_peel <= 1'b0;
            start_obs <= 1'b0;
            case (state)
                S_IDLE: if (rd_valid) begin
                    syn <= rd_data;
                    start_grow <= 1'b1;
                    seen_low <= 1'b0;
                    state <= S_GROW;
                end
                S_GROW: begin
                    if (!done_grow) seen_low <= 1'b1;
                    if (seen_low && done_grow) begin
                        start_peel <= 1'b1;
                        seen_low <= 1'b0;
                        state <= S_PEEL;
                    end
                end
                S_PEEL: begin
                    if (!done_peel) seen_low <= 1'b1;
                    if (seen_low && done_peel) begin
                        start_obs <= 1'b1;
                        state <= S_OBS;
                    end
                end
                S_OBS: if (done_obs) state <= S_DRAIN;
                S_DRAIN: state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
