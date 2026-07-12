// TB: parameterized line mesh Blueprint line4 (M36).
// syn=[1,0,0,1], 3 edges W=10 → cycles=15, solid=3'b111.

`timescale 1ns / 1ps

module tb_aether_uf_pe_line4_grow;
    reg clk = 0;
    reg rst_n = 0;
    reg start = 0;
    reg [3:0] syn = 4'b1001;
    wire done;
    wire [2:0] solid_bits;
    wire [47:0] growth_bus;
    wire [15:0] cycles;

    aether_uf_pe_line_grow #(.N(4), .CAP(10)) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .syn(syn), .done(done), .solid_bits(solid_bits),
        .growth_bus(growth_bus), .cycles(cycles)
    );

    always #5 clk = ~clk;

    initial begin
        rst_n = 0;
        #20;
        rst_n = 1;
        #20;
        start = 1;
        #10;
        start = 0;
        wait (done);
        #10;
        if (cycles !== 16'd15 || solid_bits !== 3'b111 ||
            growth_bus[15:0] !== 16'd10 || growth_bus[31:16] !== 16'd10 ||
            growth_bus[47:32] !== 16'd10) begin
            $display("FAIL cycles=%0d solid=%b g=%0d/%0d/%0d (expect 15,111,10,10,10)",
                     cycles, solid_bits, growth_bus[15:0], growth_bus[31:16], growth_bus[47:32]);
            $fatal(1);
        end
        $display("PASS pe_line4_grow cycles=%0d solid=%b (≡ helios_pe line4)",
                 cycles, solid_bits);
        $finish;
    end
endmodule
