/*
 * Copyright (c) 2025 fjpolo
 * SPDX-License-Identifier: Apache-2.0
 */
 // IO
 //
 // The TinyQV project uses a PMOD connector for input and output.
 // The PMOD connector has 8 pins, which are used as follows:
 //   - ui_in[0] to ui_in[7]: Input PMOD, always available. Note that ui_in[7] is normally used for UART RX.
 //     The inputs are synchronized to the clock, note this will introduce 2 cycles of delay on the inputs.
 //   - uo_out[0] to uo_out[7]: Output PMOD, only connected if this peripheral is selected.
 //      ⚠ Note that uo_out[0] is normally used for UART TX.
 //         +uo_out[1]: Audio PWM output Left Channel.
 //         +uo_out[2]: Audio PWM output Right Channel.
 //         +uo_out[3]: apu_phi2_clk - 21.477MHz.
 //         +uo_out[4]: apu_IRQ

 // Memory Mapped Registers
 //
 //    0x00 - Example Register - Read/Write
 //    0x01 - 0x0F - APU Register Direct Access (Pass-through for NES APU registers 0x4001-0x400F) - Read/Write
 //
 //    0x20 - Configuration0 - Read/Write
 //       | b7           | b6  | b5 | b4 | b3 | b2 | b1 | b0 |
 //       | Enhanced APU |     |    |    | CS |    | US | CE |
 //
 //    0x21 - Configuration1 - Read/Write
 //       | b7                  | b6 | b5 | b4 | b3 | b2 |   b1   |          b0          |
 //       | PMOD PWM Out enable |    |    |    |    |    | isMMC5 | APU Mapper saturates |
 //
 //    0x22 - Status0 - Read
 //       | b7 |          b6        |        b5          |       b4           |          b3        |         b2         | b1  |         b0        |
 //       |    |  Audio Channel[4]  |  Audio Channel[3]  |  Audio Channel[2]  |  Audio Channel[1]  |  Audio Channel[0]  | IRQ | Data Output Ready |
 //
 //    0x23 - Data Input - Write/Read (Data to be written to APU's DIN port for commands/writes)
 //
 //    0x24 - Data Output MSB - Read (MSB of APU Sample)
 //
 //    0x25 - Data Output LSB - Read (LSB of APU Sample)
 //
 //    APU internal registers (0x4000-0x401F):
 //      Accessed via peripheral addresses 0x01-0x0F for direct read/write,
 //      or indirectly via 0x23 write for specific commands, and 0x24/0x25 read for audio sample.

`default_nettype none

// Change the name of this module to something that reflects its functionality and includes your name for uniqueness
// For example tqvp_yourname_spi for an SPI peripheral.
// Then edit tt_wrapper.v line 41 and change tqvp_example to your chosen module name.
module tqvp_fjpolo_rv2a03 (
    input         clk,          // Clock - the TinyQV project clock is normally set to 64MHz.
    input         rst_n,        // Reset_n - low to reset.

    input  [7:0]  ui_in,        // The input PMOD, always available.  Note that ui_in[7] is normally used for UART RX.
                                // The inputs are synchronized to the clock, note this will introduce 2 cycles of delay on the inputs.

    output [7:0]  uo_out,       // The output PMOD.  Each wire is only connected if this peripheral is selected.
                                // Note that uo_out[0] is normally used for UART TX.

    input [5:0]   address,      // Address within this peripheral's address space
    input [31:0]  data_in,      // Data in to the peripheral, bottom 8, 16 or all 32 bits are valid on write.

    // Data read and write requests from the TinyQV core.
    input [1:0]   data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input [1:0]   data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    
    output [31:0] data_out,     // Data out from the peripheral, bottom 8, 16 or all 32 bits are valid on read when data_ready is high.
    output        data_ready,

    output        user_interrupt  // Dedicated interrupt request for this peripheral
);

    wire [7:0] apu_dout;
    wire apu_o_ce; // New wire to capture the clock enable from the APU

    localparam CONFIGURATION0_REG_ADDR = 6'h20;
    localparam CONFIGURATION1_REG_ADDR = 6'h21;
    localparam STATUS1_REG_ADDR = 6'h22;
    localparam DATA_INPUT_REG_ADDR = 6'h23;
    localparam DATA_OUTPUT_MSB_REG_ADDR = 6'h24;
    localparam DATA_OUTPUT_LSB_REG_ADDR = 6'h25;
    localparam APU_STATUS_REG_ADDRESS  = 6'h15;
    localparam APU_FRAME_COUNTER_REG_ADDRESS  = 6'h17;

    reg [7:0] reg_apu [30:0];
    reg [7:0] reg_configuration0;
    reg [7:0] reg_configuration1;
    reg [7:0] reg_data_input;
    reg [7:0] reg_data_output_msb;
    reg [7:0] reg_data_output_lsb;
    reg [7:0] reg_status0;

    initial reg_configuration0 = 8'h00;      
    initial reg_configuration1 = 8'h00;      
    initial reg_data_input = 8'h00;          
    initial reg_data_output_msb = 8'hFF;     
    initial reg_data_output_lsb = 8'h00;     
    initial reg_status0 = 8'h00;             

    wire apu_us = reg_configuration0[2];
    wire apu_enhanced = 1'b0;
    wire apu_mapper_saturates = reg_configuration1[0];
    wire apu_is_mmc5 = 1'b0;
    wire [4:0] apu_audio_channels = reg_configuration1[6:2];

    wire [7:0] apu_data_out;
    wire [15:0] apu_output_sample_16b;
    wire apu_data_output_ready;         
    
    wire apu_IRQ;
    
    reg odd_or_even = 1; 

    parameter CPU_DIV_N = 4'd11; 
    parameter PPU_DIV_N = 2'd3;  

    reg [3:0] div_cpu_cnt;
    initial div_cpu_cnt = 4'd0;
    reg [1:0] div_ppu_cnt;
    initial div_ppu_cnt = 2'd0;
    reg [1:0] div_sys;
    initial div_sys = 2'd0;

    wire cpu_ce = (div_cpu_cnt == CPU_DIV_N);
    wire ppu_ce = (div_ppu_cnt == PPU_DIV_N);
    wire apu_ce = cpu_ce;
    
    // The derived clock is now only for the output pin.
    wire apu_phi2_clk = (div_cpu_cnt >= 4'd4);
    
    // This is the new clock enable signal for the APU module.
    wire apu_phi2_ce = apu_phi2_clk;

    wire apu_cs = (address >= 'h00)&&(address < APU_FRAME_COUNTER_REG_ADDRESS);











    // Implement a 32-bit read/write register at address 0
    reg [31:0] example_data;
    always @(posedge clk) begin
        if (!rst_n) begin
            example_data <= 0;
        end else begin
            if (address == 6'h0) begin
                if (data_write_n != 2'b11)              example_data[7:0]   <= data_in[7:0];
                if (data_write_n[1] != data_write_n[0]) example_data[15:8]  <= data_in[15:8];
                if (data_write_n == 2'b10)              example_data[31:16] <= data_in[31:16];
            end
        end
    end

    // The bottom 8 bits of the stored data are added to ui_in and output to uo_out.
    assign uo_out = ui_in;

    // reg [31:0] data_out_reg;
    // always_comb begin
    //     case (address)
    //         6'h00: data_out_reg                         = {24'h0, reg_apu[0]};
    //         CONFIGURATION0_REG_ADDR: data_out_reg       = {24'h0, reg_configuration0};
    //         CONFIGURATION1_REG_ADDR: data_out_reg       = {24'h0, reg_configuration1};
    //         STATUS1_REG_ADDR: data_out_reg              = {24'h0, reg_status0};
    //         DATA_INPUT_REG_ADDR: data_out_reg           = {24'h0, reg_data_input};
    //         DATA_OUTPUT_MSB_REG_ADDR: data_out_reg      = {24'h0, reg_data_output_msb};
    //         DATA_OUTPUT_LSB_REG_ADDR: data_out_reg      = {24'h0, reg_data_output_lsb};
    //         APU_STATUS_REG_ADDRESS: data_out_reg        = {24'h0, apu_dout};
    //         APU_FRAME_COUNTER_REG_ADDRESS: data_out_reg     = {24'h0, apu_dout};
    //         default: begin
    //             if ((address >= 6'h00)&&(address < 6'h20)) begin
    //                 data_out_reg = {24'h0, reg_apu[address]};
    //             end else begin
    //                 data_out_reg = 32'h0;
    //             end
    //         end
    //     endcase
    // end
    // assign data_out = data_out_reg;
    assign data_out =   (address == 6'h00)                      ? {24'h0, reg_apu[0]} :
                        (address == 6'h01)                      ? {24'h0, reg_apu[1]} :
                        (address == 6'h02)                      ? {24'h0, reg_apu[2]} :
                        (address == 6'h03)                      ? {24'h0, reg_apu[3]} :
                        (address == 6'h04)                      ? {24'h0, reg_apu[4]} :
                        (address == 6'h04)                      ? {24'h0, reg_apu[5]} :
                        (address == 6'h05)                      ? {24'h0, reg_apu[6]} :
                        (address == 6'h06)                      ? {24'h0, reg_apu[7]} :
                        (address == 6'h07)                      ? {24'h0, reg_apu[8]} :
                        (address == 6'h08)                      ? {24'h0, reg_apu[9]} :
                        (address == 6'h09)                      ? {24'h0, reg_apu[10]} :
                        (address == 6'h0A)                      ? {24'h0, reg_apu[11]} :
                        (address == 6'h0B)                      ? {24'h0, reg_apu[12]} :
                        (address == 6'h0C)                      ? {24'h0, reg_apu[13]} :
                        (address == 6'h0D)                      ? {24'h0, reg_apu[14]} :
                        (address == 6'h0E)                      ? {24'h0, reg_apu[15]} :
                        (address == 6'h0F)                      ? {24'h0, reg_apu[16]} :
                        (address == 6'h11)                      ? {24'h0, reg_apu[17]} :
                        (address == 6'h12)                      ? {24'h0, reg_apu[18]} :
                        (address == 6'h13)                      ? {24'h0, reg_apu[19]} :
                        (address == 6'h14)                      ? {24'h0, reg_apu[20]} :
                        (address == 6'h15)                      ? {24'h0, reg_apu[21]} :
                        (address == 6'h16)                      ? {24'h0, reg_apu[22]} :
                        (address == 6'h17)                      ? {24'h0, reg_apu[23]} :
                        (address == CONFIGURATION0_REG_ADDR)    ? {24'h0, reg_configuration0} :
                        (address == CONFIGURATION1_REG_ADDR)    ? {24'h0, reg_configuration1} :
                        (address == STATUS1_REG_ADDR)           ? {24'h0, reg_configuration1} :
                        (address == DATA_INPUT_REG_ADDR)        ? {24'h0, reg_data_input} :
                        (address == DATA_OUTPUT_MSB_REG_ADDR)   ? {24'h0, reg_data_output_msb} :
                        (address == DATA_OUTPUT_LSB_REG_ADDR)   ? {24'h0, reg_data_output_lsb} :
                        (address == APU_STATUS_REG_ADDRESS)     ? {24'h0, apu_dout} :
                        'h0;

    // All reads complete in 1 clock
    assign data_ready = 1;
    
    // User interrupt is generated on rising edge of ui_in[6], and cleared by writing a 1 to the low bit of address 8.
    reg example_interrupt;
    reg last_ui_in_6;

    always @(posedge clk) begin
        if (!rst_n) begin
            example_interrupt <= 0;
        end

        if (ui_in[6] && !last_ui_in_6) begin
            example_interrupt <= 1;
        end else if (address == 6'h8 && data_write_n != 2'b11 && data_in[0]) begin
            example_interrupt <= 0;
        end

        last_ui_in_6 <= ui_in[6];
    end

    assign user_interrupt = example_interrupt;

    // List all unused inputs to prevent warnings
    // data_read_n is unused as none of our behaviour depends on whether
    // registers are being read.
    wire _unused = &{data_read_n, 1'b0};

endmodule
