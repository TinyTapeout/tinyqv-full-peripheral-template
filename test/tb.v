`default_nettype none
`timescale 1ns / 1ps
`define COCOTB_TESTING

/* This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.
*/
module tb ();

  // Dump the signals to a VCD file. You can view it with gtkwave or surfer.
  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
    #1;
  end

  // Wire up the inputs and outputs:
  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif
 `ifdef COCOTB_TESTING
    wire [15:0] o_apu_samples;
    wire [0:0]  o_apu_ce;  
    wire [0:0]  o_apu_cs;
    wire [0:0]  o_phi2;
    wire [0:0]  o_even;
    wire [4:0] o_Sq1Sample;
    wire [4:0] o_Sq2Sample;
    wire [3:0] o_TriSample;
    wire [4:0] o_enabled_buffer;
    wire [4:0] o_enabled_buffer1;
    wire [7:0] o_dout;
    wire [7:0] o_aclk1;
    wire [0:0]  o_ApuMW0;
    wire [0:0]  o_ApuMW1;
    wire [0:0]  o_ApuMW2;
    wire [0:0]  o_ApuMW3;
    wire [0:0]  o_ApuMW4;
    wire [0:0]  o_ApuMW5;
    wire [4:0]  o_enabled;
    wire [0:0]  o_ClkL;
    wire [0:0]  o_ClkE;
`endif 

  tt_um_tqv_peripheral_harness test_harness (

      // Include power ports for the Gate Level test:
`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
`endif

      .ui_in  (ui_in),    // Dedicated inputs
      .uo_out (uo_out),   // Dedicated outputs
      .uio_in (uio_in),   // IOs: Input path
      .uio_out(uio_out),  // IOs: Output path
      .uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
      .ena    (ena),      // enable - goes high when design is selected
      .clk    (clk),      // clock
      .rst_n  (rst_n)     // not reset
`ifdef COCOTB_TESTING
     ,.o_apu_samples(o_apu_samples),
      .o_apu_ce(o_apu_ce),  
      .o_apu_cs(o_apu_cs),
      .o_phi2(o_phi2),
      .o_even(o_even),
    // APU Debug
    .o_Sq1Sample(o_Sq1Sample),
    .o_Sq2Sample(o_Sq2Sample),
    .o_TriSample(o_TriSample),
    .o_enabled_buffer(o_enabled_buffer),
    .o_enabled_buffer1(o_enabled_buffer1),
    .o_enabled(o_enabled),
    .o_dout(o_dout),
    .o_aclk1(o_aclk1),
    .o_ApuMW0(o_ApuMW0),
    .o_ApuMW1(o_ApuMW1),
    .o_ApuMW2(o_ApuMW2),
    .o_ApuMW3(o_ApuMW3),
    .o_ApuMW4(o_ApuMW4),
    .o_ApuMW5(o_ApuMW5),
    .o_ClkL(o_ClkL),
    .o_ClkE(o_ClkE)
`endif
  );

endmodule
