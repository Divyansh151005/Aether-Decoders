// TB for PE line3 mesh (M35) vs Blueprint line3 / helios_pe.

`timescale 1ns / 1ps

module tb_aether_uf_pe_line3_grow;
    reg clk = 0;
    reg rst_n = 0;
    reg start = 0;
    reg syn0 = 1, syn1 = 0, syn2 = 1;
    wire done;
    wire [1:0] solid_bits;
    wire [15:0] growth0, growth1, cycles;

    aether_uf_pe_line3_grow dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .syn0(syn0), .syn1(syn1), .syn2(syn2),
        .done(done), .solid_bits(solid_bits),
        .growth0(growth0), .growth1(growth1), .cycles(cycles)
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
        if (cycles !== 16'd10 || solid_bits !== 2'b11 ||
            growth0 !== 16'd10 || growth1 !== 16'd10) begin
            $display("FAIL cycles=%0d solid=%b g0=%0d g1=%0d (expect 10,11,10,10)",
                     cycles, solid_bits, growth0, growth1);
            $fatal(1);
        end
        $display("PASS pe_line3_grow cycles=%0d solid=%b g0=%0d g1=%0d (≡ helios_pe line3)",
                 cycles, solid_bits, growth0, growth1);
        $finish;
    end
endmodule
