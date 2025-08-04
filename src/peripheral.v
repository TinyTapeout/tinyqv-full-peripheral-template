/*
 * Copyright (c) 2025 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

 // IO
 //
 // The TinyQV project uses a PMOD connector for input and output.
 // The PMOD connector has 8 pins, which are used as follows:
 //   - ui_in[0] to ui_in[7]: Input PMOD, always available. Note that ui_in[7] is normally used for UART RX.
 //     The inputs are synchronized to the clock, note this will introduce 2 cycles of delay on the inputs.
 //   - uo_out[0] to uo_out[7]: Output PMOD, only connected if this peripheral is selected.
 //     ⚠ Note that uo_out[0] is normally used for UART TX.
 //       +uo_out[1]: Audio PWM output Left Channel.
 //       +uo_out[2]: Audio PWM output Right Channel.
 //       +uo_out[3]: apu_phi2_clk - 21.477MHz.
 //       +uo_out[4]: apu_IRQ

 // Memory Mapped Registers
 //
 //    0x00 - Example Register - Read/Write
 //    0x01 - 0x0F - APU Register Direct Access (Pass-through for NES APU registers 0x4001-0x400F) - Read/Write
 //
 //    0x20 - Configuration0 - Read/Write
 //      | b7          | b6  | b5 |    b4   | b3 | b2  | b1 | b0 |
 //      | Enhanced APU |     |    |   isCh2  | CS |     | US | CE |
 //
 //    0x21 - Configuration1 - Read/Write
 //      | b7                     | b6 | b5 | b4 | b3 | b2 | b1 | b0 |
 //      | PMOD PWM Out enable |  |  |  |  |  | isMMC5 | APU Mapper saturates |
 //
 //    0x22 - Status0 - Read
 //      | b7 |       b6        |       b5          |       b4         |          b3       |          b2        | b1  |          b0       |
 //      |    | Audio Channel[4]  |   Audio Channel[3]  |   Audio Channel[2]   |   Audio Channel[1]   |   Audio Channel[0]   | IRQ | Data Output Ready |
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

module tqvp_fjpolo_rv2a03 (
    input          clk,           // Clock - the TinyQV project clock is normally set to 64MHz.
    input          rst_n,         // Reset_n - low to reset.

    input    [7:0] ui_in,         // The input PMOD, always available. Note that ui_in[7] is normally used for UART RX.
                                  // The inputs are synchronized to the clock, note this will introduce 2 cycles of delay on the inputs.

    output   [7:0] uo_out,        // The output PMOD. Each wire is only connected if this peripheral is selected.
                                  // Note that uo_out[0] is normally used for UART TX.

    input    [5:0] address,       // Address within this peripheral's address space
    input   [31:0] data_in,       // Data in to the peripheral, bottom 8, 16 or all 32 bits are valid on write.

    // Data read and write requests from the TinyQV core.
    input    [1:0] data_write_n,  // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input    [1:0] data_read_n,   // 11 = no read, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    
    output  [31:0] data_out,      // Data out from the peripheral, bottom 8, 16 or all 32 bits are valid on read when data_ready is high.
    output         data_ready,

    output         user_interrupt // Dedicated interrupt request for this peripheral
);

    wire [7:0] apu_dout;

    localparam CONFIGURATION0_REG_ADDR = 6'h20; // Address for configuration0 register
    localparam CONFIGURATION1_REG_ADDR = 6'h21; // Address for configuration1 register
    localparam STATUS1_REG_ADDR = 6'h22; // Address for status0 register
    localparam DATA_INPUT_REG_ADDR = 6'h23; // Address for data input register
    localparam DATA_OUTPUT_MSB_REG_ADDR = 6'h24; // Address for data output MSB register
    localparam DATA_OUTPUT_LSB_REG_ADDR = 6'h25; // Address for data output LSB register
    localparam APU_STATUS_REG_ADDRESS  = 6'h15;
    localparam APU_FRAME_COUNTER_REG_ADDRESS  = 6'h17;

    
    /* --- APU Registers --- */
    reg [7:0] reg_apu [30:0];

    /* --- Registers --- */
    reg [7:0] reg_configuration0;
    reg [7:0] reg_configuration1;
    reg [7:0] reg_data_input;
    reg [7:0] reg_data_output_msb;
    reg [7:0] reg_data_output_lsb;
    reg [7:0] reg_status0;

    /* --- Initial Values for Registers --- */
    // Initializing with flags disabled to save resources by default
    initial reg_configuration0 = 8'h00;      
    initial reg_configuration1 = 8'h00;      
    initial reg_data_input = 8'h00;          
    initial reg_data_output_msb = 8'hFF;     
    initial reg_data_output_lsb = 8'h00;     
    initial reg_status0 = 8'h00;             

    /* --- Internal Wires/Signals --- */
    // Signals extracted from Configuration0 (for APU module)
    wire apu_us = reg_configuration0[2];
    // Disable enhanced APU features by default to save resources
    wire apu_enhanced = 1'b0; // reg_configuration0[7];
    // The isCh2 and CS flags are commented out as they are unused for now.
    // wire apu_is_ch2 = reg_configuration0[4];
    // wire apu_cs_conf0 = reg_configuration0[3];

    // Signals extracted from Configuration1 (for APU module)
    wire apu_mapper_saturates = reg_configuration1[0];
    // Disable MMC5 mapper to save resources
    wire apu_is_mmc5 = 1'b0; // reg_configuration1[1];
    wire [4:0] apu_audio_channels = reg_configuration1[6:2];

    // APU internal signals (outputs from APU module)
    wire [7:0] apu_data_out;
    wire [15:0] apu_internal_sample_wire;
    wire apu_data_output_ready;         
    
    /* --- apu_IRQ --- */
    wire apu_IRQ;
    
    /* --- Clock logic --- */
    // All clocking is now fixed for NTSC.
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
    
    // The apu_phi2_clk signal for the PMOD output pin.
    // This is NOT used as a clock for any internal logic,
    // which is the source of the high resource utilization.
    wire apu_phi2_clk = (div_cpu_cnt >= 4'd4);

    // The new clock enable signal for the APU module,
    // clocked by the main `clk`. This is the correct ASIC design pattern.
    wire apu_phi2_ce = (div_cpu_cnt >= 4'd4);
    
    wire apu_cs = (address >= 'h00)&&(address < APU_FRAME_COUNTER_REG_ADDRESS);

    always @(posedge clk) begin
        if (!rst_n) begin
            div_cpu_cnt <= 4'd0;
            div_ppu_cnt <= 2'd0;
            div_sys     <= 2'd0;
            odd_or_even <= 1'b1;
        end else begin
            div_cpu_cnt <= cpu_ce ? 4'd0 : div_cpu_cnt + 4'd1;
            div_ppu_cnt <= ppu_ce ? 2'd0 : div_ppu_cnt + 2'd1;
            div_sys     <= div_sys + 2'd1;
            
            if (cpu_ce) 
                odd_or_even <= ~odd_or_even;
        end
    end

    wire apu_wr_signal_RVdomain =   (data_write_n == 2'b10) ? 1'b1 :     
                                    (data_write_n == 2'b01) ? 1'b1 :     
                                    (data_write_n == 2'b00) ? 1'b1 :     
                                    1'b0;                    

    wire apu_rw_signal_RVdomain =   (data_read_n == 2'b10) ? 1'b1 :     
                                    (data_read_n == 2'b01) ? 1'b1 :     
                                    (data_read_n == 2'b00) ? 1'b1 :     
                                    1'b0;                     

    wire apu_rw = (apu_wr_signal_RVdomain) ? 1'b0 : 1'b1;

    wire [15:0] apu_output_sample_16b;
    
    // Correctly capture the APU sample when `o_ce` is high.
    always @(posedge clk) begin
        if(!rst_n) begin
            reg_data_output_msb <= 8'h00;
            reg_data_output_lsb <= 8'h00;
        end else if (apu_data_output_ready) begin
            reg_data_output_msb <= apu_output_sample_16b[15:8];
            reg_data_output_lsb <= apu_output_sample_16b[7:0];
        end
    end

    // The APU module should be modified to take a clock enable,
    // rather than the derived clock signal.
    APU apu(
        .MMC5(apu_is_mmc5),
        .clk(clk),
        .PHI2(apu_phi2_ce), // Assumes the APU module has a clock enable port.
        .ce(apu_ce),
        .reset(~rst_n),
        .cold_reset(~rst_n),
        .allow_us(apu_us),
        .ADDR(address[4:0]),
        .DIN(data_in[7:0]),
        .RW(apu_rw), 
        .CS(apu_cs),
        .audio_channels(apu_audio_channels),
        .DmaData(),       
        .odd_or_even(odd_or_even),
        .DmaAck(),        
        .DOUT(apu_dout),
        .Sample(apu_output_sample_16b),
        .DmaReq(),        
        .DmaAddr(),       
        .IRQ(apu_IRQ),    
        .apu_enhanced_ce(apu_enhanced),
        .apu_mapper_saturates(apu_mapper_saturates),
        .o_ce(apu_data_output_ready) // Now connected and used to gate the sample capture
    );

    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i <= 30; i = i + 1) begin
                reg_apu[i] <= 8'h00;
            end
        end else begin
            if (data_write_n == 2'b00) begin
                if (address >= 6'h00 && address < 6'h20) begin
                    reg_apu[address[4:0]] <= data_in[7:0];
                end
            end
        end
    end
    
    assign uo_out[7:5] = ui_in[7:5];
    assign uo_out[4]   = apu_IRQ;
    assign uo_out[3]   = apu_phi2_clk;
    assign uo_out[2:0] = ui_in[2:0];                

    always @(posedge clk) begin
        if (!rst_n) begin
            reg_configuration0 <= 0;
        end else begin
            if (address == CONFIGURATION0_REG_ADDR[5:0]) begin
                if (data_write_n != 2'b11)
                    reg_configuration0 <= data_in[7:0];
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            reg_configuration1 <= 0;
        end else begin
            if (address == CONFIGURATION1_REG_ADDR[5:0]) begin
                if (data_write_n != 2'b11)
                    reg_configuration1 <= data_in[7:0];
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            reg_data_input <= 0;
        end else begin
            if (address == DATA_INPUT_REG_ADDR) begin
                if (data_write_n != 2'b11)
                    reg_data_input <= data_in[7:0];
            end
        end
    end

    reg [31:0] data_out_reg;
    always_comb begin
        case (address)
            6'h00: data_out_reg = {24'h0, reg_apu[0]};
            CONFIGURATION0_REG_ADDR: data_out_reg = {24'h0, reg_configuration0};
            CONFIGURATION1_REG_ADDR: data_out_reg = {24'h0, reg_configuration1};
            STATUS1_REG_ADDR: data_out_reg = {24'h0, reg_status0};
            DATA_INPUT_REG_ADDR: data_out_reg = {24'h0, reg_data_input};
            DATA_OUTPUT_MSB_REG_ADDR: data_out_reg = {24'h0, reg_data_output_msb};
            DATA_OUTPUT_LSB_REG_ADDR: data_out_reg = {24'h0, reg_data_output_lsb};
            APU_STATUS_REG_ADDRESS: data_out_reg = {24'h0, apu_dout};
            APU_FRAME_COUNTER_REG_ADDRESS: data_out_reg = {24'h0, apu_dout};
            default: begin
                if (address >= 6'h00 && address < 6'h20) begin
                    data_out_reg = {24'h0, reg_apu[address]};
                end else begin
                    data_out_reg = 32'h0;
                end
            end
        endcase
    end
    assign data_out = data_out_reg;

    assign data_ready = 1;
    
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

    wire _unused = &{data_read_n, 1'b0};

endmodule
