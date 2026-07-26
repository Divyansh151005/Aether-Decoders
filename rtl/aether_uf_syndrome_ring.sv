// Aether UF — H10 depth-2 syndrome frame ring (M50).
// Host writes frozen syndrome bitvectors; decoder pops one frame per shot.
// Spec: Docs/Host_IO_H10, Docs/H10_Ring_Rtl. Not PE state (LUTRAM/H9).

`timescale 1ns / 1ps

module aether_uf_syndrome_ring #(
    parameter int WIDTH = 16,
    parameter int DEPTH = 2
) (
    input  wire             clk,
    input  wire             rst_n,
    // Host → ring
    input  wire             wr_valid,
    output wire             wr_ready,
    input  wire [WIDTH-1:0] wr_data,
    // Ring → decoder
    output wire             rd_valid,
    input  wire             rd_ready,
    output wire [WIDTH-1:0] rd_data,
    output wire [7:0]       fill_count
);
    // DEPTH must be ≥2 for streaming (Host_IO_H10 §4).
    localparam int PTR_W = (DEPTH <= 2) ? 1 : $clog2(DEPTH);

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [PTR_W:0]   wr_ptr; // one extra bit for full/empty
    reg [PTR_W:0]   rd_ptr;

    wire [PTR_W:0] wr_idx = wr_ptr;
    wire [PTR_W:0] rd_idx = rd_ptr;
    // Count = wr_ptr - rd_ptr in modular DEPTH*2 space when PTR has extra bit
    // Simpler: keep count explicitly.
    reg [7:0] count;

    assign fill_count = count;
    assign wr_ready = (count < DEPTH[7:0]);
    assign rd_valid = (count != 8'd0);
    assign rd_data  = mem[rd_ptr[PTR_W-1:0]];

    wire do_wr = wr_valid && wr_ready;
    wire do_rd = rd_valid && rd_ready;

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {(PTR_W+1){1'b0}};
            rd_ptr <= {(PTR_W+1){1'b0}};
            count  <= 8'd0;
            for (i = 0; i < DEPTH; i = i + 1)
                mem[i] <= {WIDTH{1'b0}};
        end else begin
            if (do_wr) begin
                mem[wr_ptr[PTR_W-1:0]] <= wr_data;
                wr_ptr <= wr_ptr + {{PTR_W{1'b0}}, 1'b1};
            end
            if (do_rd) begin
                rd_ptr <= rd_ptr + {{PTR_W{1'b0}}, 1'b1};
            end
            case ({do_wr, do_rd})
                2'b10: count <= count + 8'd1;
                2'b01: count <= count - 8'd1;
                default: count <= count;
            endcase
        end
    end
endmodule
