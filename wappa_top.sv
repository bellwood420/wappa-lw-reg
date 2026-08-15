`default_nettype none

module wappa_top (
    input wire FPGA_CLK1_50
);

    wappa_axi_reg u0 (
        .clk (FPGA_CLK1_50)
    );

endmodule

`default_nettype wire