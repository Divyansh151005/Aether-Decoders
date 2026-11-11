// Aether UF — H10 observable egress stub (M53; synthesizable M75).
// XOR obs_mask on correction edges → 64-bit obs word; ready/valid + status.
// One correction edge per clock (num_edges cycles in S_CALC), packed mask bus.
// Spec: Docs/Host_IO_H10 §3.2; Docs/H10_Obs_Egress. Not PCIe.

`timescale 1ns / 1ps

module aether_uf_obs_egress #(
    parameter int MAX_E = 128,
    parameter int IDX_W = 8
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,
    input  wire [IDX_W-1:0]   num_edges,
    input  wire [MAX_E-1:0]   corr_bits,
    input  wire [64*MAX_E-1:0] obs_mask_bus,
    input  wire [31:0]        peel_ops_in,
    input  wire               status_timeout_in, // H11 stub: 0 when UF completed
    input  wire               obs_ready,
    output reg                obs_valid,
    output reg  [63:0]        obs_word,
    output reg  [31:0]        status_peel_ops,
    output reg                status_timeout,
    output reg                done
);
    localparam S_IDLE = 2'd0;
    localparam S_CALC = 2'd1;
    localparam S_WAIT = 2'd2;

    reg [1:0]       state;
    reg [IDX_W:0]   e_idx;
    wire            e_last = (e_idx + 1'b1 >= {1'b0, num_edges});
    wire [63:0]     e_mask = obs_mask_bus[e_idx[IDX_W-1:0]*64 +: 64];
    wire            e_hit  = corr_bits[e_idx[IDX_W-1:0]];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            e_idx <= '0;
            obs_valid <= 1'b0;
            obs_word <= 64'd0;
            status_peel_ops <= 32'd0;
            status_timeout <= 1'b0;
            done <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    obs_valid <= 1'b0;
                    if (start) begin
                        obs_word <= 64'd0;
                        e_idx <= '0;
                        status_peel_ops <= peel_ops_in;
                        status_timeout <= status_timeout_in;
                        if (num_edges == '0) begin
                            obs_valid <= 1'b1;
                            state <= S_WAIT;
                        end else
                            state <= S_CALC;
                    end
                end
                S_CALC: begin
                    // Sequential XOR over correction edges (matches SW observables_from_corrections).
                    if (e_hit)
                        obs_word <= obs_word ^ e_mask;
                    e_idx <= e_idx + 1'b1;
                    if (e_last) begin
                        obs_valid <= 1'b1;
                        state <= S_WAIT;
                    end
                end
                S_WAIT: begin
                    if (obs_valid && obs_ready) begin
                        obs_valid <= 1'b0;
                        done <= 1'b1;
                        state <= S_IDLE;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
