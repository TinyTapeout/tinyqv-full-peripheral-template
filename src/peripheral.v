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
 //       | b7           | b6  | b5 | b4 | b3 | b2  | b1 | b0 |
 //       | Enhanced APU |     |    |    | CS | PAL | US | CE |
 //
 //    0x21 - Configuration1 - Read/Write
 //       | b7                  | b6 | b5 | b4 | b3 | b2 | b1 | b0 |
 //       | PMOD PWM Out enable |  |  |  |  |  | isMMC5 | APU Mapper saturates |
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

    localparam CONFIGURATION0_REG_ADDR = 6'h20; // Address for configuration0 register
    localparam CONFIGURATION1_REG_ADDR = 6'h21; // Address for configuration1 register
    localparam STATUS1_REG_ADDR = 6'h22; // Address for status0 register
    localparam DATA_INPUT_REG_ADDR = 6'h23; // Address for data input register
    localparam DATA_OUTPUT_MSB_REG_ADDR = 6'h24; // Address for data output MSB register
    localparam DATA_OUTPUT_LSB_REG_ADDR = 6'h25; // Address for data output LSB register
    
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
    initial reg_configuration0 = 8'h00;     // Initialize configuration register to 0
    initial reg_configuration1 = 8'h00;     // Initialize configuration register to 0
    initial reg_data_input = 8'h00;        // Initialize data input register to 0
    initial reg_data_output_msb = 8'hFF;   // Initialize data output MSB register to 0
    initial reg_data_output_lsb = 8'h00;   // Initialize data output L
    initial reg_status0 = 8'h00;            // Initialize status register to 0

    /* --- Internal Wires/Signals --- */
    // Signals extracted from Configuration0 (for APU module)
    wire apu_pal                    = reg_configuration0[1];
    wire apu_us                     = reg_configuration0[2];
    wire apu_enhanced               = reg_configuration0[7];

    // Signals extracted from Configuration1 (for APU module)
    wire apu_mapper_saturates       = reg_configuration1[0];
    wire apu_is_mmc5                = reg_configuration1[1];
    wire [4:0] apu_audio_channels   = reg_configuration1[6:2];
    // PMOD PWM output
    // wire apu_pmod_pwm_out_enable = reg_configuration1[7];

    // APU internal signals (outputs from APU module)
    wire [7:0] apu_data_out;
    wire [15:0] apu_internal_sample_wire;
    wire apu_data_output_ready;         // APU's output enable (APU.o_ce)
    
    /* --- apu_IRQ --- */
    wire apu_IRQ;
    
    /* --- Clock magic --- */

    // odd or even apu cycle, AKA div_apu or apu_/clk2. This is actually not 50% duty cycle. It is high for 18
    // master cycles and low for 6 master cycles. It is considered active when low or "even".
    reg apu_odd_or_even; // 1 == odd, 0 == even
    initial apu_odd_or_even = 1'b1;

    // XXX: Because we are using div4 clock divider for PAL, master clock should be 21.2813696
    // Clock Dividers
    wire [4:0] div_cpu_n = 5'd12;
    wire [2:0] div_ppu_n = 3'd4;

    // Counters
    reg [4:0] div_cpu;
    initial div_cpu = 5'd1;
    reg [2:0] div_ppu;
    initial div_ppu = 3'd1;
    reg [1:0] div_sys;
    initial div_sys = 2'd0;

    // CE's
    wire cpu_ce  = (div_cpu == div_cpu_n);
    wire ppu_ce  = (div_ppu == div_ppu_n);
    wire apu_phi2_clk = (div_cpu > 4 && div_cpu < div_cpu_n);
    wire apu_ce = cpu_ce;
    wire apu_cs = (address >= 'h00)&&(address < 'h18);

    //  The infamous NES jitter is important for accuracy, but wreks havok on modern devices and scalers,
    // so what I do here is pause the whole system for one PPU clock and insert a "fake" ppu clock to
    // replace the missing pixel. Thus the system runs accurately (ableit a few nanoseconds per frame slower)
    // but all video devices stay happy.

    wire skip_pixel;
    reg freeze_clocks;
    initial freeze_clocks = 0;
    reg [4:0] faux_pixel_cnt;
    initial faux_pixel_cnt = 0;

    wire use_fake_h = freeze_clocks && faux_pixel_cnt < 6;
    reg [1:0] ppu_tick = 0;
    initial ppu_tick = 0;

    reg last_apu_pal;
    initial last_apu_pal = 0;
    reg [2:0] cpu_tick_count;
    initial cpu_tick_count = 0;
    wire skip_ppu_cycle = (cpu_tick_count == 4) && (ppu_tick == 0);

    // cpu_tick_count
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            cpu_tick_count <= 0;
        end else begin
            if ((cpu_ce) && (apu_pal)) begin
                cpu_tick_count <= cpu_tick_count[2] ? 3'd0 : cpu_tick_count + 1'b1;
            end
            if (last_apu_pal != apu_pal) begin
                cpu_tick_count <= 0;
            end
        end
    end
    // last_apu_pal
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            last_apu_pal <= 0;
        end else begin
            last_apu_pal <= apu_pal;
        end
    end
    // ppu_tick
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            ppu_tick <= 0;
        end else begin
            if (~freeze_clocks | ~(div_ppu == (div_ppu_n - 1'b1))) begin
                if (cpu_ce) begin
                    ppu_tick <= 0;
                end else if (ppu_ce) begin
                    ppu_tick <= ppu_tick + 1'b1;
                end
            end
        end
    end
    // div_ppu
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            div_ppu <= 0;
        end else begin
            if (~freeze_clocks | ~(div_ppu == (div_ppu_n - 1'b1))) begin
                div_ppu <= ppu_ce ? 1'b1 : div_ppu + 1'b1;
            end
            if (last_apu_pal != apu_pal) begin
                div_ppu <= 3'd1;
            end
        end
    end
    // div_cpu
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            div_cpu <= 0;
        end else begin
            if (~freeze_clocks | ~(div_ppu == (div_ppu_n - 1'b1))) begin
                if (~skip_ppu_cycle) begin
                    div_cpu <= cpu_ce || (ppu_ce && div_cpu > div_cpu_n) ? 1'b1 : div_cpu + 1'b1;
                end
            end
            if (last_apu_pal != apu_pal) begin
                div_cpu <= 5'd1;
            end
        end
    end
    // div_sys
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            div_sys <= 0;
        end else begin
            div_sys <= div_sys + 1'b1;
            if (last_apu_pal != apu_pal) begin
                div_sys <= 0;
            end
        end
    end

    // De-Jitter shenanigans
    // apu_odd_or_even
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            apu_odd_or_even <= 1'b1;
        end else begin
            if ((~freeze_clocks)|(~(div_ppu == (div_ppu_n - 1'b1)))) begin
                if (cpu_ce) begin
                    apu_odd_or_even <= ~apu_odd_or_even;
                end
            end
        end
    end
    // faux_pixel_cnt
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            faux_pixel_cnt <= 0;
        end else begin
            if ((~freeze_clocks)|(~(div_ppu == (div_ppu_n - 1'b1)))) begin
                if (|faux_pixel_cnt) begin
                    faux_pixel_cnt <= faux_pixel_cnt - 1'b1;
                end
                // TODO: Fix offender
                if ((skip_pixel)&&(faux_pixel_cnt == 0)) begin
                    faux_pixel_cnt <= {div_ppu_n - 1'b1, 1'b0} + 1'b1;
                end
            end
        end
    end
    // freeze_clocks
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            freeze_clocks <= 0;
        end else begin
            if (~freeze_clocks | ~(div_ppu == (div_ppu_n - 1'b1))) begin
                if (faux_pixel_cnt == 3) begin
                    freeze_clocks <= 1'b0;
                end
                if (skip_pixel && (faux_pixel_cnt == 0)) begin
                    freeze_clocks <= 1'b1;
                end
            end
        end
    end

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

    wire apu_rw = (apu_wr_signal_RVdomain) ? 1'b0 : 1'b1;

    // APU.CS: Asserted when APU chip select from config is high AND the peripheral address targets APU registers.
    wire apu_cs_signal_DA = apu_cs && (address <= 6'h20);

    /* --- APU address --- */
    wire [4:0] apu_address;
    assign apu_address = (address <= 6'h20) ? address[4:0] : 5'h00; // Use lower 5 bits of address for APU registers

    /* --- APU Sample Output --- */
    wire [15:0] apu_output_sample_16b;
    always @(posedge clk) begin
        if(!rst_n)
            reg_data_output_msb <= 8'h00;
        else
            reg_data_output_msb <= apu_output_sample_16b[15:8];
    end
    always @(posedge clk) begin
        if(!rst_n)
            reg_data_output_lsb <= 8'h00;
        else
            reg_data_output_lsb <= apu_output_sample_16b[7:0];
    end

    /* --- NES APU Instance --- */
    APU apu(
        .MMC5(apu_is_mmc5),
        .clk(clk),
        .PHI2(apu_phi2_clk),
        .ce(apu_ce),
        .reset(1'b0),
        .cold_reset(1'b0),
        .allow_us(1'b0),
        .PAL(1'b0),
        .ADDR(address),
        .DIN(data_in),
        .RW(apu_rw), // 0 - Write, 1 - Read
        .CS(apu_cs),
        .audio_channels(5'b11111),
        .DmaData(),         // Stubbed input
        .odd_or_even(apu_odd_or_even),
        .DmaAck(),          // Stubbed input
        .DOUT(),
        .Sample(apu_output_sample_16b),
        .DmaReq(),          // Output, but ignored for now
        .DmaAddr(),         // Output, but ignored for now
        .IRQ(apu_IRQ),      // Captured in status register
        .apu_enhanced_ce(1'b0),
        .apu_mapper_saturates(1'b0),
        .o_ce()             // APU's output enable (when Sample is valid)
    );

    /* --- APU Registers Write Logic --- */
    // This block handles writing to the reg_apu array, which mirrors the APU's internal registers.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize all elements of reg_apu to 0 on reset
            for (int i = 0; i <= 30; i = i + 1) begin
                reg_apu[i] <= 8'h00;
            end
        end else begin
            // Only write if an 8-bit write operation is active
            // and the address is within the intended APU register range (0x00 to 0x17)
            if (data_write_n == 2'b00) begin // 2'b00 indicates an 8-bit write
                if (address >= 6'h00 && address < 6'h20) begin
                    reg_apu[address] <= data_in[7:0];
                end
            end
        end
    end
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
    assign uo_out[7:4] = ui_in[7:4];
    assign uo_out[3]   = apu_phi2_clk;
    assign uo_out[2:0] = ui_in[2:0];                

    // configuration0 register
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

    // configuration1 register
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

    // data_in register
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

    // data_out
    assign data_out =   (address < 6'h20) ? {24'h0, reg_apu[address]} :
                        (address == CONFIGURATION0_REG_ADDR[5:0]) ? {24'h0, reg_configuration0} :
                        (address == CONFIGURATION1_REG_ADDR[5:0]) ? {24'h0, reg_configuration1} :
                        (address == STATUS1_REG_ADDR[5:0]) ? {24'h0, reg_status0} :
                        (address == DATA_INPUT_REG_ADDR[5:0]) ? {24'h0, reg_data_input} :
                        (address == DATA_OUTPUT_MSB_REG_ADDR[5:0]) ? {24'h0, reg_data_output_msb} :
                        (address == DATA_OUTPUT_LSB_REG_ADDR[5:0]) ? {24'h0, reg_data_output_lsb} :
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
