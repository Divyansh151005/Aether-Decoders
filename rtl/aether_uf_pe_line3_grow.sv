// Thin wrapper: Blueprint line3 on parameterized line mesh (M36).

`timescale 1ns / 1ps

module aether_uf_pe_line3_grow (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        syn0,
    input  wire        syn1,
    input  wire        syn2,
    output wire        done,
    output wire [1:0]  solid_bits,
    output wire [15:0] growth0,
    output wire [15:0] growth1,
    output wire [15:0] cycles
);
    wire [31:0] growth_bus;
    aether_uf_pe_line_grow #(.N(3), .CAP(10)) u_line (
        .clk(clk), .rst_n(rst_n), .start(start),
        .syn({syn2, syn1, syn0}),
        .done(done), .solid_bits(solid_bits),
        .growth_bus(growth_bus), .cycles(cycles)
    );
    assign growth0 = growth_bus[15:0];
    assign growth1 = growth_bus[31:16];
endmodule
