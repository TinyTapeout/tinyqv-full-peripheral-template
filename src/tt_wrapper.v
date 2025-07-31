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
    output  wire [0:0]  o_ClkE,
    // Triangle wave
    output wire        o_apuTri_clk,
    output wire        o_apuTri_phi1,
    output wire        o_apuTri_aclk1,
    output wire        o_apuTri_aclk1_d,
    output wire        o_apuTri_reset,
    output wire        o_apuTri_cold_reset,
    output wire        o_apuTri_allow_us,
    output wire [1:0]  o_apuTri_Addr,
    output wire [7:0]  o_apuTri_DIN,
    output wire        o_apuTri_write,
    output wire [7:0]  o_apuTri_lc_load,
    output wire        o_apuTri_LenCtr_Clock,
    output wire        o_apuTri_LinCtr_Clock,
    output wire        o_apuTri_Enabled,
    output wire [10:0] o_apuTri_Period,
    output wire [10:0] o_apuTri_applied_period,
    output wire [10:0] o_apuTri_TimerCtr,
    output wire [4:0]  o_apuTri_SeqPos,
    output wire [6:0]  o_apuTri_LinCtrPeriod,
    output wire [6:0]  o_apuTri_LinCtrPeriod_1,
    output wire [6:0]  o_apuTri_LinCtr,
    output wire [0:0]  o_apuTri_LinCtrl,
    output wire [0:0]  o_apuTri_line_reload,
    output wire [0:0]  o_apuTri_LinCtrZero,
    output wire [0:0]  o_apuTri_lc,
    output wire [0:0]  o_apuTri_subunit_write,
    output wire [3:0]  o_apuTri_sample_latch

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
    .o_ClkE(o_ClkE),
    // Triangle wave
    .o_apuTri_clk(o_apuTri_clk),
    .o_apuTri_phi1(o_apuTri_phi1),
    .o_apuTri_aclk1(o_apuTri_aclk1),
    .o_apuTri_aclk1_d(o_apuTri_aclk1_d),
    .o_apuTri_reset(o_apuTri_reset),
    .o_apuTri_cold_reset(o_apuTri_cold_reset),
    .o_apuTri_allow_us(o_apuTri_allow_us),
    .o_apuTri_Addr(o_apuTri_Addr),
    .o_apuTri_DIN(o_apuTri_DIN),
    .o_apuTri_write(o_apuTri_write),
    .o_apuTri_lc_load(o_apuTri_lc_load),
    .o_apuTri_LenCtr_Clock(o_apuTri_LenCtr_Clock),
    .o_apuTri_LinCtr_Clock(o_apuTri_LinCtr_Clock),
    .o_apuTri_Enabled(o_apuTri_Enabled),
    .o_apuTri_Period(o_apuTri_Period),
    .o_apuTri_applied_period(o_apuTri_applied_period),
    .o_apuTri_TimerCtr(o_apuTri_TimerCtr),
    .o_apuTri_SeqPos(o_apuTri_SeqPos),
    .o_apuTri_LinCtrPeriod(o_apuTri_LinCtrPeriod),
    .o_apuTri_LinCtrPeriod_1(o_apuTri_LinCtrPeriod_1),
    .o_apuTri_LinCtr(o_apuTri_LinCtr),
    .o_apuTri_LinCtrl(o_apuTri_LinCtrl),
    .o_apuTri_line_reload(o_apuTri_line_reload),
    .o_apuTri_LinCtrZero(o_apuTri_LinCtrZero),
    .o_apuTri_lc(o_apuTri_lc),
    .o_apuTri_subunit_write(o_apuTri_subunit_write),
    .o_apuTri_sample_latch(o_apuTri_sample_latch)
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
