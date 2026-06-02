// Aether UF — first RTL slice (M17): two-node one-edge grow+merge.
//
// Spec: Docs/Hardware_Mapping; schedule matches src/helios_pe.rs /
// src/cycle_model.rs for Blueprint test 1 (W=10, syndrome [1,1]).
// Expected: cycles==5, solid0==1 when done.
//
// Helios reference (behavior, not copied RTL): STAGE_GROW_BOUNDARY and
 // odd&&!boundary active (arXiv:2406.08491; yale-paragon/Helios_scalable_QEC).
//
 // Simulate with Verilator/Icarus when available:
 //   verilator --binary --top-module tb_aether_uf_two_node rtl/*.sv
 // CI golden check is Rust `helios_pe` (Verilator not required).

`timescale 1ns / 1ps

module aether_uf_two_node_grow_merge (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        syn0,
    input  wire        syn1,
    output reg         done,
    output reg         solid0,
    output reg  [15:0] growth0,
    output reg  [15:0] cycles
);
    localparam [15:0] CAP0 = 16'd10;

    localparam S_IDLE = 2'd0;
    localparam S_RUN  = 2'd1;
    localparam S_DONE = 2'd2;

    reg [1:0]  state;
    // DSU for 2 nodes: root_id[v] in {0,1}; parity/size/cbound stored per root index.
    reg        root_of0; // root id of node 0
    reg        root_of1;
    reg [15:0] size_r0, size_r1;
    reg        parity_r0, parity_r1;
    reg        cbound_r0, cbound_r1;

    wire act_r0 = parity_r0 & ~cbound_r0;
    wire act_r1 = parity_r1 & ~cbound_r1;
    wire any_active = act_r0 | act_r1;
    wire same_root = (root_of0 == root_of1);

    wire grow0 = act_r0 & ~same_root;
    wire grow1 = act_r1 & ~same_root;
    wire [15:0] delta = {15'd0, grow0} + {15'd0, grow1};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done <= 1'b0;
            solid0 <= 1'b0;
            growth0 <= 16'd0;
            cycles <= 16'd0;
            root_of0 <= 1'b0;
            root_of1 <= 1'b1;
            size_r0 <= 16'd1;
            size_r1 <= 16'd1;
            parity_r0 <= 1'b0;
            parity_r1 <= 1'b0;
            cbound_r0 <= 1'b0;
            cbound_r1 <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        solid0 <= 1'b0;
                        growth0 <= 16'd0;
                        cycles <= 16'd0;
                        root_of0 <= 1'b0;
                        root_of1 <= 1'b1;
                        size_r0 <= 16'd1;
                        size_r1 <= 16'd1;
                        parity_r0 <= syn0;
                        parity_r1 <= syn1;
                        cbound_r0 <= 1'b0;
                        cbound_r1 <= 1'b0;
                        state <= S_RUN;
                    end
                end
                S_RUN: begin
                    if (!any_active) begin
                        state <= S_DONE;
                        done <= 1'b1;
                    end else if (!solid0) begin
                        growth0 <= growth0 + delta;
                        cycles <= cycles + 16'd1;
                        if ((growth0 + delta) >= CAP0) begin
                            solid0 <= 1'b1;
                            // union-by-size
                            if (!same_root) begin
                                if (size_r0 >= size_r1) begin
                                    root_of1 <= root_of0;
                                    parity_r0 <= parity_r0 ^ parity_r1;
                                    cbound_r0 <= cbound_r0 | cbound_r1;
                                    size_r0 <= size_r0 + size_r1;
                                    parity_r1 <= 1'b0;
                                    cbound_r1 <= 1'b0;
                                end else begin
                                    root_of0 <= root_of1;
                                    parity_r1 <= parity_r0 ^ parity_r1;
                                    cbound_r1 <= cbound_r0 | cbound_r1;
                                    size_r1 <= size_r0 + size_r1;
                                    parity_r0 <= 1'b0;
                                    cbound_r0 <= 1'b0;
                                end
                            end
                        end
                    end else begin
                        // solid but still active should not happen for [1,1]
                        state <= S_DONE;
                        done <= 1'b1;
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
