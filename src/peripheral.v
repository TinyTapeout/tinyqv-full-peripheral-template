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
 //     Note that uo_out[0] is normally used for UART TX.
 //     uo_out[1] is proposed for Audio PWM output.

 // Memory Mapped Registers
 //
 //    0x00 - Example Register - Read/Write
 //    0x01 - 0x0F - APU Register Direct Access (Pass-through for NES APU registers 0x4001-0x400F) - Read/Write
 //    0x10 - Configuration0 - Read/Write
 //       | b7           | b6                  | b5                   | b4   | b3 | b2  | b1 | b0 |
 //       | Enhanced APU |  Audio Channels MSB | Audio Channels LSB   | Even | CS | PAL | US | CE |
 //
 //    0x11 - Configuration1 - Read/Write
 //       | b7                  | b6 | b5 | b4 | b3 | b2 | b1 | b0 |
 //       | PMOD PWM Out enable |  |  |  |  |  | isMMC5 | APU Mapper saturates |
 //
 //    0x12 - Status0 - Read
 //       | b7 | b6 | b5 | b4 | b3 | b2 | b1 | b0 |
 //       |    |    |    |    |    |    | IRQ | Data Output Ready |
 //
 //    0x20 - Data Input - Write/Read (Data to be written to APU's DIN port for commands/writes)
 //
 //    0x21 - Data Output MSB - Read (MSB of APU Sample)
 //
 //    0x22 - Data Output LSB - Read (LSB of APU Sample)
 //
 //    APU internal registers (0x4000-0x401F):
 //      Accessed via peripheral addresses 0x01-0x0F for direct read/write,
 //      or indirectly via 0x20 write for specific commands, and 0x21/0x22 read for audio sample.

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

    /* --- Registers --- */
    reg [7:0] reg_configuration0;
    reg [7:0] reg_configuration1;
    reg [7:0] reg_data_input;
    reg [7:0] reg_data_output_msb;
    reg [7:0] reg_data_output_lsb;
    reg [7:0] reg_status0;

    initial reg_configuration0 = 8'h00;     // Initialize configuration register to 0
    initial reg_configuration1 = 8'h00;     // Initialize configuration register to 0
    initial reg_data_input = 8'h00;        // Initialize data input register to 0
    initial reg_data_output_msb = 8'h00;   // Initialize data output MSB register to 0
    initial reg_data_output_lsb = 8'h00;   // Initialize data output L
    initial reg_status0 = 8'h00;            // Initialize status register to 0

    /* --- Internal Wires/Signals --- */
    // Signals extracted from Configuration0 (for APU module)
    wire apu_ce                     = reg_configuration0[0];
    wire apu_pal                    = reg_configuration0[1];
    wire apu_us                     = reg_configuration0[2];
    wire apu_cs                     = reg_configuration0[3];
    wire apu_even                   = reg_configuration0[4];  // TODO: Use after phi2 module is done
    wire [1:0] apu_audio_channels   = {reg_configuration0[6], reg_configuration0[5]};
    wire apu_enhanced               = reg_configuration0[7];

    // Signals extracted from Configuration1 (for APU module)
    wire apu_mapper_saturates = reg_configuration1[0];
    wire apu_is_mmc5          = reg_configuration1[1];
    // PMOD PWM output
    // wire apu_pmod_pwm_out_enable = reg_configuration1[7];

    // APU internal signals (outputs from APU module)
    wire [7:0] apu_data_out;
    wire [15:0] apu_internal_sample_wire;
    wire apu_data_output_ready;         // APU's output enable (APU.o_ce)

    /* --- Clock Divider for APU Sound Clock --- */
    logic apu_sound_clk;
    fractional_divider apu_clk_divider (
        .clk_in(clk),
        .rst_n(rst_n),
        .clk_out(apu_sound_clk) // 1.789773 MHz
    );

    /* --- Clock Divider for PHI2 Clock --- */
    logic apu_phi2_clk;
    fractional_divider phi2_clk_divider (
        .clk_in(clk),
        .rst_n(rst_n),
        .clk_out(apu_phi2_clk) // 1.789773 MHz
    );

    // /* --- APU Register Access Mapping --- */
    // // Ensure apu_address_for_module is 16-bit by padding 0x40 to 6 bits
    // wire [15:0] apu_address_for_module;
    // assign apu_address_for_module = ((address >= 6'h0)&&(address <= 6'hF)) ? {2'b0, 8'h40, address} : 16'h0000;

    // APU.WR: 1 for Write
    wire apu_wr_signal_RVdomain =   (data_write_n == 2'b10) ? 1'b1 :     // 32-bit write
                                    (data_write_n == 2'b01) ? 1'b1 :     // 16-bit write
                                    (data_write_n == 2'b00) ? 1'b1 :     // 8-bit write
                                    1'b0;                                // 2'b11 - No write

    // APU.RW: 1 for Read
    wire apu_rw_signal_RVdomain =   (data_read_n == 2'b10) ? 1'b1 :    // 32-bit read
                                    (data_read_n == 2'b01) ? 1'b1 :    // 16-bit read
                                    (data_read_n == 2'b00) ? 1'b1 :    // 8-bit read
                                    1'b0;                              // 2'b11 - No read


    // // APU.CS: Asserted when APU chip select from config is high AND the peripheral address targets APU registers.
    wire apu_cs_signal_DA = apu_cs && ((address >= 6'h0)&&(address <= 6'hF));

    /* ⚠⚠⚠ CDC ⚠⚠⚠ */
    // apu_wr_signal_RVdomain
    wire apu_wr_signal;
    logic apu_q1_synced_data_wr;
    logic apu_synced_data_wr;
    always @(posedge apu_phi2_clk or negedge rst_n) begin
        if (!rst_n) begin
            apu_q1_synced_data_wr <= 1'b0;
            apu_synced_data_wr <= 1'b0;
        end else begin
            // Synchronize apu_wr_signal_RVdomain from 64MHz domain to PHI2 domain
            {apu_synced_data_wr, apu_q1_synced_data_wr} <= {apu_q1_synced_data_wr, apu_wr_signal_RVdomain};
        end
    end
    assign apu_wr_signal = apu_synced_data_wr;

    // apu_rw_signal
    wire apu_rw_signal;
    logic apu_q1_synced_data_rw;
    logic apu_synced_data_rw;
    always @(posedge apu_phi2_clk or negedge rst_n) begin
        if (!rst_n) begin
            apu_q1_synced_data_rw <= 1'b0;
            apu_synced_data_rw <= 1'b0;
        end else begin
            // Synchronize apu_rw_signal_RVdomain from 64MHz domain to PHI2 domain
            {apu_synced_data_rw, apu_q1_synced_data_rw} <= {apu_q1_synced_data_rw, apu_rw_signal_RVdomain};
        end
    end
    assign apu_rw_signal = (apu_wr_signal) ? 1'b0 : 1'b1;  // Default to read

    // data_in
    logic [7:0] apu_q1_synced_data_in;
    logic [7:0] apu_synced_data_in;
    always @(posedge apu_phi2_clk or negedge rst_n) begin
        if (!rst_n) begin
            apu_q1_synced_data_in <= 8'h0;
            apu_synced_data_in <= 8'h0;
        end else begin
            // Synchronize data_in[7:0] from 64MHz domain to PHI2 domain
            {apu_synced_data_in, apu_q1_synced_data_in} <= {apu_q1_synced_data_in, data_in[7:0]};
        end
    end

    // address
    logic [5:0] apu_q1_synced_address;
    logic [5:0] apu_synced_address;
    always @(posedge apu_phi2_clk or negedge rst_n) begin
        if (!rst_n) begin
            apu_q1_synced_address <= 6'h0;
            apu_synced_address <= 6'h0;
        end else begin
            // Synchronize address from 64MHz domain to PHI2 domain
            {apu_synced_address, apu_q1_synced_address} <= {apu_q1_synced_address, address};
        end
    end

    // // reg_configuration0
    // logic [7:0] apu_q1_synced_configuration0;
    // logic [7:0] apu_synced_configuration0;
    // always @(posedge apu_phi2_clk or negedge rst_n) begin
    //     if (!rst_n) begin
    //         apu_q1_synced_configuration0 <= 8'h0;
    //         apu_synced_configuration0 <= 8'h0;
    //     end else begin
    //         // Synchronize reg_configuration0 from 64MHz domain to PHI2 domain
    //         {apu_synced_configuration0, apu_q1_synced_configuration0} <= {apu_q1_synced_configuration0, reg_configuration0};
    //     end
    // end

    // // reg_configuration1
    // logic [7:0] apu_q1_synced_configuration1;
    // logic [7:0] apu_synced_configuration1;
    // always @(posedge apu_phi2_clk or negedge rst_n) begin
    //     if (!rst_n) begin
    //         apu_q1_synced_configuration1 <= 8'h0;
    //         apu_synced_configuration1 <= 8'h0;
    //     end else begin
    //         // Synchronize reg_configuration1 from 64MHz domain to PHI2 domain
    //         {apu_synced_configuration1, apu_q1_synced_configuration1} <= {apu_q1_synced_configuration1, reg_configuration1};
    //     end
    // end

    // reg_data_input
    logic [7:0] apu_q1_synced_data_input;
    logic [7:0] apu_synced_data_input;
    always @(posedge apu_phi2_clk or negedge rst_n) begin
        if (!rst_n) begin
            apu_q1_synced_data_input <= 8'h0;
            apu_synced_data_input <= 8'h0;
        end else begin
            // Synchronize reg_data_input from 64MHz domain to PHI2 domain
            {apu_synced_data_input, apu_q1_synced_data_input} <= {apu_q1_synced_data_input, reg_data_input};
        end
    end

    /* --- NES APU Instance --- */
    APU apu(
        .MMC5(apu_is_mmc5),
        .clk(apu_sound_clk),
        .PHI2(apu_phi2_clk),
        .ce(apu_ce),
        .reset(!rst_n),
        .cold_reset(!rst_n),
        .allow_us(apu_us),
        .PAL(apu_pal),
        .ADDR(),
        .DIN(apu_synced_data_input),
        .RW(apu_rw_signal),
        .CS(apu_cs_signal_DA),
        .audio_channels(apu_audio_channels),
        .DmaData(),         // Stubbed input
        .odd_or_even(),
        .DmaAck(),          // Stubbed input
        .DOUT(),
        .Sample(),
        .DmaReq(),          // Output, but ignored for now
        .DmaAddr(),         // Output, but ignored for now
        .IRQ(),             // Captured in status register
        .apu_enhanced_ce(apu_enhanced),
        .apu_mapper_saturates(apu_mapper_saturates),
        .o_ce()             // APU's output enable (when Sample is valid)
    );

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
    assign uo_out = example_data[7:0] + ui_in;                    

    // configuration0 register
    always @(posedge clk) begin
        if (!rst_n) begin
            reg_configuration0 <= 0;
        end else begin
            if (address == 6'h11) begin
                if (data_write_n != 2'b11)
                    reg_configuration0 <= data_in[7:0];
            end
        end
    end

    // configuration1 register
    always @(posedge clk) begin
        if (!rst_n) begin
            reg_configuration1 <= 0;
        end else begin
            if (address == 6'h12) begin
                if (data_write_n != 2'b11)
                    reg_configuration1 <= data_in[7:0];
            end
        end
    end

    // data_in register
    always @(posedge clk) begin
        if (!rst_n) begin
            reg_data_input <= 0;
        end else begin
            if (address == 6'h20) begin
                if (data_write_n != 2'b11)
                    reg_data_input <= data_in[7:0];
            end
        end
    end

    // data_out
    assign data_out =   (address == 6'h0) ? example_data :
                        (address == 6'h11) ? {24'h0, reg_configuration0} :
                        (address == 6'h12) ? {24'h0, reg_configuration1} :
                        (address == 6'h13) ? {24'h0, reg_status0} :
                        (address == 6'h20) ? {24'h0, reg_data_input} :
                        (address == 6'h04) ? {24'h0, ui_in} :
                        32'h0;

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
