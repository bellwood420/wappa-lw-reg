// wappa_axi_reg.sv
//
// Minimal direct AXI3 slave for the Cyclone V Lightweight HPS-to-FPGA bridge.
//
// No Qsys / Platform Designer interconnect is used.
// The only implemented slave registers are:
//
//   HPS physical address 0xFF200000  <->  reg0[31:0]
//   HPS physical address 0xFF200004  <->  reg1[31:0]
//
// Intended access:
//   devmem 0xFF200000 32
//   devmem 0xFF200000 32 0x12345678
//
// This deliberately supports only a single 32-bit AXI beat.
// FPGA configuration initializes all local state; there is no separate
// fabric reset input in this minimal experiment.

`default_nettype none

module wappa_axi_reg (
    input wire clk
);

    // ------------------------------------------------------------------------
    // Signals driven by the HPS Lightweight AXI master
    // ------------------------------------------------------------------------

    wire [11:0] awid;
    wire [20:0] awaddr;
    wire  [3:0] awlen;
    wire  [2:0] awsize;
    wire        awvalid;

    wire [31:0] wdata;
    wire  [3:0] wstrb;
    wire        wlast;
    wire        wvalid;

    wire        bready;

    wire [11:0] arid;
    wire [20:0] araddr;
    wire  [3:0] arlen;
    wire  [2:0] arsize;
    wire        arvalid;

    wire        rready;


    // ------------------------------------------------------------------------
    // Signals returned to the HPS Lightweight AXI master
    // ------------------------------------------------------------------------

    wire        awready;
    wire        wready;
    wire        arready;

    reg  [11:0] bid    = 12'b0;
    reg   [1:0] bresp  = 2'b00;
    reg         bvalid = 1'b0;

    reg  [11:0] rid    = 12'b0;
    reg  [31:0] rdata  = 32'b0;
    reg   [1:0] rresp  = 2'b00;
    reg         rlast  = 1'b0;
    reg         rvalid = 1'b0;


    // ------------------------------------------------------------------------
    // The two Wappa registers
    // ------------------------------------------------------------------------

    reg [31:0] reg0 = 32'b0;
    reg [31:0] reg1 = 32'b0;


    // ------------------------------------------------------------------------
    // Write transaction holding registers
    //
    // AXI address and data channels are independent, so AW and W are captured
    // separately.  The actual register write happens after both have arrived.
    // ------------------------------------------------------------------------

    reg        aw_pending = 1'b0;
    reg [11:0] awid_hold  = 12'b0;
    reg [20:0] awaddr_hold = 21'b0;
    reg        aw_bad     = 1'b0;

    reg        w_pending  = 1'b0;
    reg [31:0] wdata_hold = 32'b0;
    reg  [3:0] wstrb_hold = 4'b0;
    reg        w_bad      = 1'b0;

    assign awready = !aw_pending && !bvalid;
    assign wready  = !w_pending  && !bvalid;
    assign arready = !rvalid;

    always @(posedge clk) begin
        // Capture write address.
        if (awvalid && awready) begin
            aw_pending <= 1'b1;
            awid_hold  <= awid;
            awaddr_hold <= awaddr;

            // Only address 0 and 4, one beat, 32-bit transfer is implemented.
            aw_bad <= (awaddr != 21'h0 && awaddr != 21'h4) ||
                      (awlen          != 4'b0000) ||
                      (awsize         != 3'b010);
        end

        // Capture write data.
        if (wvalid && wready) begin
            w_pending  <= 1'b1;
            wdata_hold <= wdata;
            wstrb_hold <= wstrb;
            w_bad      <= !wlast;
        end

        // Complete a write once both independent channels have arrived.
        if (aw_pending && w_pending && !bvalid) begin
            bid <= awid_hold;

            if (aw_bad || w_bad) begin
                // SLVERR
                bresp <= 2'b10;
            end
            else begin
                // Apply AXI byte strobes.
                if (awaddr_hold == 21'h0) begin
                    if (wstrb_hold[0]) reg0[ 7: 0] <= wdata_hold[ 7: 0];
                    if (wstrb_hold[1]) reg0[15: 8] <= wdata_hold[15: 8];
                    if (wstrb_hold[2]) reg0[23:16] <= wdata_hold[23:16];
                    if (wstrb_hold[3]) reg0[31:24] <= wdata_hold[31:24];
                end else begin
                    if (wstrb_hold[0]) reg1[ 7: 0] <= wdata_hold[ 7: 0];
                    if (wstrb_hold[1]) reg1[15: 8] <= wdata_hold[15: 8];
                    if (wstrb_hold[2]) reg1[23:16] <= wdata_hold[23:16];
                    if (wstrb_hold[3]) reg1[31:24] <= wdata_hold[31:24];
                end

                // OKAY
                bresp <= 2'b00;
            end

            bvalid     <= 1'b1;
            aw_pending <= 1'b0;
            w_pending  <= 1'b0;
        end

        // HPS accepted the write response.
        if (bvalid && bready)
            bvalid <= 1'b0;


        // --------------------------------------------------------------------
        // Read transaction
        // --------------------------------------------------------------------

        if (arvalid && arready) begin
            rid   <= arid;
            rlast <= 1'b1;

            if ((araddr != 21'h0 && araddr != 21'h4) ||
                (arlen         != 4'b0000) ||
                (arsize        != 3'b010)) begin

                rdata <= 32'b0;

                // SLVERR
                rresp <= 2'b10;
            end
            else begin
                if (araddr == 21'h0)
                    rdata <= reg0;
                else
                    rdata <= reg1;

                // OKAY
                rresp <= 2'b00;
            end

            rvalid <= 1'b1;
        end

        // HPS accepted the read response.
        if (rvalid && rready) begin
            rvalid <= 1'b0;
            rlast  <= 1'b0;
        end
    end


    // ------------------------------------------------------------------------
    // Cyclone V hard Lightweight HPS-to-FPGA AXI interface
    // ------------------------------------------------------------------------

    cyclonev_hps_interface_hps2fpga_light_weight hps2fpga_light_weight (
        .clk     (clk),

        // Write address channel: HPS -> FPGA
        .awid    (awid),
        .awaddr  (awaddr),
        .awlen   (awlen),
        .awsize  (awsize),
        .awvalid (awvalid),
        .awready (awready),

        // Write data channel: HPS -> FPGA
        .wdata   (wdata),
        .wstrb   (wstrb),
        .wlast   (wlast),
        .wvalid  (wvalid),
        .wready  (wready),

        // Write response channel: FPGA -> HPS
        .bid     (bid),
        .bresp   (bresp),
        .bvalid  (bvalid),
        .bready  (bready),

        // Read address channel: HPS -> FPGA
        .arid    (arid),
        .araddr  (araddr),
        .arlen   (arlen),
        .arsize  (arsize),
        .arvalid (arvalid),
        .arready (arready),

        // Read data channel: FPGA -> HPS
        .rid     (rid),
        .rdata   (rdata),
        .rresp   (rresp),
        .rlast   (rlast),
        .rvalid  (rvalid),
        .rready  (rready)
    );

endmodule

`default_nettype wire
