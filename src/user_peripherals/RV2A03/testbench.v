`timescale 1ns / 1ps

module testbench();

    // Parameters for APU register addresses (from the peripheral.v comments)
    parameter APU_SQ1_REG0_ADDR = 5'h00;
    parameter APU_SQ1_REG1_ADDR = 5'h01;
    parameter APU_SQ1_REG2_ADDR = 5'h02;
    parameter APU_SQ1_REG3_ADDR = 5'h03;
    parameter APU_STATUS_REG_ADDR = 5'h15;
    parameter APU_FRAME_COUNTER_REG_ADDR = 5'h17;

    // Calculated Timer Period for Square Channels (440Hz)
    // Timer Period = 126 = 0x7E
    parameter SQ_TIMER_PERIOD_LOW = 8'h7E;
    parameter SQ_TIMER_PERIOD_HIGH = 3'h0; // Upper 3 bits of 126 is 0

    // Length Counter Load Value (e.g., for a long note)
    parameter LENGTH_COUNTER_LOAD_VALUE = 8'hF0; // Used for bits 7-3 of reg3

    // Testbench variables (inputs to the APU module)
    reg clk;
    reg PHI2;
    reg ce;
    reg reset; // Active high reset for APU module
    reg cold_reset; // Active high cold reset for APU module
    reg allow_us;
    reg PAL;
    reg [4:0] ADDR;
    reg [7:0] DIN;
    reg RW;
    reg CS;
    reg [4:0] audio_channels;
    reg [7:0] DmaData;
    reg odd_or_even;
    reg DmaAck;
    reg apu_enhanced_ce;
    reg apu_mapper_saturates;

    // Wires (outputs from the APU module)
    wire [7:0] DOUT;
    wire signed [15:0] Sample;
    wire DmaReq;
    wire [15:0] DmaAddr;
    wire IRQ;
    wire o_ce;

    // Instantiate the APU module
    APU dut (
        .MMC5(1'b0), // Assuming no MMC5 for this basic test
        .clk(clk),
        .PHI2(PHI2),
        .ce(ce),
        .reset(reset),
        .cold_reset(cold_reset),
        .allow_us(allow_us),
        .PAL(PAL),
        .ADDR(ADDR),
        .DIN(DIN),
        .RW(RW),
        .CS(CS),
        .audio_channels(audio_channels),
        .DmaData(8'h00), // Not used for basic tone generation
        .odd_or_even(odd_or_even),
        .DmaAck(1'b0), // Not used for basic tone generation
        .DOUT(DOUT),
        .Sample(Sample),
        .DmaReq(DmaReq),
        .DmaAddr(DmaAddr),
        .IRQ(IRQ),
        .apu_enhanced_ce(apu_enhanced_ce),
        .apu_mapper_saturates(apu_mapper_saturates),
        .o_ce(o_ce)
    );

    // Clock generation
    // Using a 50ns period for clk, which is 20MHz. This is a simplified clock
    // for the APU module, as the actual NES clocking is more complex.
    parameter CLK_PERIOD = 50; // 50ns for 20MHz clock

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Simplified PHI2, CE, and odd_or_even generation
    // These signals are generated to provide basic operational clocks to the APU.
    initial begin
        PHI2 = 0;
        ce = 0; // Will be set high after reset
        odd_or_even = 0;
        forever @(posedge clk) begin
            // PHI2 derived from clk, simplified to toggle every 2 clk cycles
            // This is a rough approximation of a slower clock for APU.
            if (clk) PHI2 = ~PHI2; // Toggle PHI2 on positive edge of clk
            
            // ce always high after reset to continuously enable the APU
            if (reset == 1'b0) ce = 1'b1;
            
            // odd_or_even toggles on positive edge of clk
            odd_or_even = ~odd_or_even;
        end
    end

    // Task to perform a write operation to an APU register
    task apu_write_reg;
        input [4:0] addr; // 5-bit address for APU internal registers
        input [7:0] data; // 8-bit data to write
        begin
            @(posedge clk); // Synchronize to clock edge
            CS = 1'b1;     // Assert Chip Select
            RW = 1'b0;     // Set Read/Write to Write mode
            ADDR = addr;   // Set address
            DIN = data;    // Set data input
            @(posedge clk); // Wait one more clock cycle for the write to take effect
            CS = 1'b0;     // De-assert Chip Select
            RW = 1'b1;     // Default back to Read mode
            ADDR = 5'h00;  // Default address
            DIN = 8'h00;   // Default data
        end
    endtask

    // Main test sequence
    initial begin
        // Dump waveform to VCD file for visualization
        $dumpfile("apu_testbench.vcd");
        $dumpvars(0, dut);

        // Initialize testbench inputs
        reset = 1'b1;       // Assert reset (active high for APU module)
        cold_reset = 1'b1;  // Assert cold reset (active high for APU module)
        allow_us = 1'b1;    // Allow ultrasonic frequencies
        PAL = 1'b0;         // NTSC mode
        audio_channels = 5'b00000; // All channels disabled initially
        DmaData = 8'h00;
        DmaAck = 1'b0;
        apu_enhanced_ce = 1'b0;     // Enhanced APU disabled
        apu_mapper_saturates = 1'b0; // Mapper saturation disabled
        CS = 1'b0; // Ensure CS is low initially
        RW = 1'b1; // Default to read mode

        // Release reset after some time to allow the DUT to stabilize
        # (CLK_PERIOD * 10);
        reset = 1'b0;
        cold_reset = 1'b0;
        $display("Reset released.");

        // --- Configure APU for 440Hz Square Wave on Channel 1 ---
        $display("Configuring APU for 440Hz Square Wave on Channel 1...");

        // 1. Disable all channels and reset frame counter (good practice before configuring)
        // Write 0 to APU Status Register (0x15) to disable all channels
        apu_write_reg(APU_STATUS_REG_ADDR, 8'h00);
        // Write 0 to APU Frame Counter Register (0x17) to reset frame counter (4-step mode)
        apu_write_reg(APU_FRAME_COUNTER_REG_ADDR, 8'h00);

        // --- Configure Square Channel 1 ---
        // Register $4000 (APU_SQ1_REG0_ADDR): Duty Cycle, Length Counter Halt, Constant Volume, Volume/Envelope Decay
        // Value: 0x9F (10% duty, Length Counter Halt, Constant Volume, Max Volume)
        apu_write_reg(APU_SQ1_REG0_ADDR, 8'h9F);

        // Register $4001 (APU_SQ1_REG1_ADDR): Sweep Unit (disabled)
        // Value: 0x00
        apu_write_reg(APU_SQ1_REG1_ADDR, 8'h00);

        // Register $4002 (APU_SQ1_REG2_ADDR): Timer Low Byte
        // Value: SQ_TIMER_PERIOD_LOW (0x7E)
        apu_write_reg(APU_SQ1_REG2_ADDR, 8'h7E);

        // Register $4003 (APU_SQ1_REG3_ADDR): Length Counter Load, Timer High Byte
        // Value: (LENGTH_COUNTER_LOAD_VALUE | SQ_TIMER_PERIOD_HIGH) = (0xF0 | 0x0) = 0xF0
        apu_write_reg(APU_SQ1_REG3_ADDR, 8'hF0);

        // --- Enable Square Channel 1 ---
        // Register $4015 (APU_STATUS_REG_ADDR): Enable Square 1 (bit 0)
        // Value: 0x01
        apu_write_reg(APU_STATUS_REG_ADDR, 8'h01);

        // --- Start Frame Counter ---
        // Register $4017 (APU_FRAME_COUNTER_REG_ADDR): Start Frame Counter (4-step sequence)
        // Value: 0x00
        apu_write_reg(APU_FRAME_COUNTER_REG_ADDR, 8'h00);

        $display("APU configuration complete. Monitoring Sample output.");

        // --- Self-Checking Logic ---
        // Monitor Sample output and o_ce for a fixed duration
        integer sample_count = 0;
        reg signed [15:0] last_sample = 16'hFFFF; // Initialize to a value that will guarantee a change
        integer changes = 0;
        integer zero_samples = 0;
        integer non_zero_samples = 0;
        integer x_samples = 0;

        // Wait for some time to allow APU to start producing stable samples
        # (CLK_PERIOD * 100);

        // Capture and check samples for a duration (e.g., 20000 APU clock cycles)
        for (int i = 0; i < 20000; i = i + 1) begin
            @(posedge clk);
            if (o_ce) begin // Only check when o_ce is high, indicating a valid sample
                sample_count = sample_count + 1;
                if (Sample === 16'hx) begin // Check for 'x' values
                    x_samples = x_samples + 1;
                    $display("Time %0t: WARNING: Sample is 'x'!", $time);
                end else begin
                    if (Sample != last_sample) begin
                        changes = changes + 1;
                        last_sample = Sample;
                    end
                    if (Sample == 16'h0000) begin
                        zero_samples = zero_samples + 1;
                    end else begin
                        non_zero_samples = non_zero_samples + 1;
                    end
                    // Uncomment the line below to see sample values during simulation
                    // $display("Time %0t: Sample = %d (0x%h), o_ce = %b", $time, Sample, Sample, o_ce);
                end
            end
        end

        $display("--- Self-Check Results ---");
        $display("Total samples captured when o_ce was high: %0d", sample_count);
        $display("Number of times Sample value changed: %0d", changes);
        $display("Number of zero samples: %0d", zero_samples);
        $display("Number of non-zero samples: %0d", non_zero_samples);
        $display("Number of 'x' samples: %0d", x_samples);

        // Basic assertions for self-checking
        if (sample_count > 0) begin
            $display("ASSERTION PASSED: APU produced samples when o_ce was high.");
        end else begin
            $error("ASSERTION FAILED: APU did not produce any samples when o_ce was high.");
        end

        if (changes > 10) begin // Expect more than 10 changes for a continuous tone
            $display("ASSERTION PASSED: Sample output shows significant changes (waveform activity).");
        end else begin
            $error("ASSERTION FAILED: Sample output did not show enough waveform activity.");
        end

        if (x_samples == 0) begin
            $display("ASSERTION PASSED: No 'x' values observed in Sample output.");
        end else begin
            $error("ASSERTION FAILED: Encountered 'x' values in Sample output.");
        end

        if (non_zero_samples > 0) begin
            $display("ASSERTION PASSED: Non-zero samples observed.");
        end else begin
            $error("ASSERTION FAILED: Only zero samples observed.");
        end

        $display("Testbench finished.");
        $finish; // End the simulation
    end

endmodule
