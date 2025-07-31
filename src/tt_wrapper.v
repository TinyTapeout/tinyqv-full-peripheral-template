/*
 * Copyright (c) 2025 Michael Bell
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`define COCOTB_TESTING

/** TinyQV peripheral test using SPI */
module tt_um_tqv_peripheral_harness (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
`ifndef COCOTB_TESTING
    input  wire       rst_n     // reset_n - low to reset
`else
    input  wire        rst_n,     // reset_n - low to reset
    output wire [15:0] o_apu_samples,
    output wire [0:0]  o_apu_ce,  
    output wire [0:0]  o_apu_cs,
    output wire [0:0]  o_phi2,
    output wire [0:0]  o_even,
    // APU Debug
    output  wire [4:0]  o_Sq1Sample,
    output  wire [4:0]  o_Sq2Sample,
    output  wire [3:0]  o_TriSample,
    output  wire [4:0]  o_enabled_buffer,
    output  wire [4:0]  o_enabled_buffer1,
    output  wire [4:0]  o_enabled,
    output  wire [7:0]  o_dout,
    output  wire [7:0]  o_aclk1,
    output  wire [0:0]  o_ApuMW0,
    output  wire [0:0]  o_ApuMW1,
    output  wire [0:0]  o_ApuMW2,
    output  wire [0:0]  o_ApuMW3,
    output  wire [0:0]  o_ApuMW4,
    output  wire [0:0]  o_ApuMW5,
    output  wire [0:0]  o_ClkL,
    output  wire [0:0]  o_ClkE
`endif
);

  // SPI access to registers
  wire [5:0] address;
  wire [31:0] data_in;  // Data in to peripheral
  wire [31:0] data_out; // Data out from peripheral
  reg [1:0] data_write_n;
  reg [1:0] data_read_n;
  wire data_ready;
  wire user_interrupt;

  // Peripherals get synchronized ui_in.
  reg [7:0] ui_in_sync;
  synchronizer #(.STAGES(2), .WIDTH(8)) synchronizer_ui_in_inst (.clk(clk), .data_in(ui_in), .data_out(ui_in_sync));

  // Register reset as in TinyQV
  /* verilator lint_off SYNCASYNCNET */
  reg rst_reg_n;
  /* verilator lint_on SYNCASYNCNET */
  always @(negedge clk) rst_reg_n <= rst_n;

  // The peripheral under test.
  // **** Change the module name from tqvp_example to match your peripheral. ****
  tqvp_fjpolo_rv2a03 user_peripheral(
    .clk(clk),
    .rst_n(rst_reg_n),
    .ui_in(ui_in_sync),
    .uo_out(uo_out),
    .address(address),
    .data_in(data_in),
    .data_write_n(data_write_n),
    .data_read_n(data_read_n),
    .data_out(data_out),
    .data_ready(data_ready),
    .user_interrupt(user_interrupt)
`ifdef COCOTB_TESTING
    ,
    .o_apu_samples(o_apu_samples),
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

  // SPI data indications
  wire addr_valid;
  wire data_valid;
  wire data_rw;
  wire [1:0] txn_n;
  reg [31:0] data_out_masked;

  // SPI interface
  wire spi_cs_n;
  wire spi_clk;
  wire spi_miso;
  wire spi_mosi;

  // Synchronized SPI inputs
  wire spi_cs_n_sync;
  wire spi_clk_sync;
  wire spi_mosi_sync;

  assign spi_cs_n  = uio_in[4];
  assign spi_clk   = uio_in[5];
  assign spi_mosi  = uio_in[6];

  synchronizer #(.STAGES(2), .WIDTH(1)) synchronizer_spi_cs_n_inst (.clk(clk), .data_in(spi_cs_n), .data_out(spi_cs_n_sync));
  synchronizer #(.STAGES(2), .WIDTH(1)) synchronizer_spi_clk_inst  (.clk(clk), .data_in(spi_clk),  .data_out(spi_clk_sync));
  synchronizer #(.STAGES(2), .WIDTH(1)) synchronizer_spi_mosi_inst (.clk(clk), .data_in(spi_mosi), .data_out(spi_mosi_sync));  

  // The SPI instance
  spi_reg #(.ADDR_W(6), .REG_W(32)) i_spi_reg(
    .clk(clk),
    .rstb(rst_reg_n),
    .ena(1'b1),
    .spi_mosi(spi_mosi_sync),
    .spi_miso(spi_miso),
    .spi_clk(spi_clk_sync),
    .spi_cs_n(spi_cs_n_sync),
    .reg_addr(address),
    .reg_data_i(data_out_masked),
    .reg_data_o(data_in),
    .reg_addr_v(addr_valid),
    .reg_data_o_dv(data_valid),
    .reg_rw(data_rw),
    .txn_width(txn_n)
  );

  always @(*) begin
      data_write_n = 2'b11;
      data_read_n = 2'b11;

      if (data_valid && data_rw) begin
        data_write_n = txn_n;
      end
      if (addr_valid && !data_rw) begin
        data_read_n = txn_n;
      end

      data_out_masked = data_out;
      if (txn_n[1] == 1'b0) data_out_masked[31:16] = 0;
      if (txn_n == 2'b00) data_out_masked[15:8] = 0;
  end

  // Assign outputs
  assign uio_out[3] = spi_miso;
  assign uio_oe[3] = 1;
  assign uio_out[0] = user_interrupt;
  assign uio_oe[0] = 1;
  assign uio_out[1] = data_ready;
  assign uio_oe[1] = 1;

  assign uio_out[7:4] = 0;
  assign uio_out[2] = 0;
  assign uio_oe[7:4] = 0;
  assign uio_oe[2] = 0;

  // Ignore unused inputs
  wire _unused = &{ena, uio_in[7], uio_in[3:0], 1'b0};

endmodule
