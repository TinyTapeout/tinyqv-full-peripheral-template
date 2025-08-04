// Rewritten 6/4/2020 by Kitrinx
// This code is GPLv3.
`define COCOTB_TESTING

module LenCounterUnit (
    input  logic       clk,
    input  logic       reset,
    input  logic       cold_reset,
    input  logic       len_clk,
    input  logic       aclk1,
    input  logic       aclk1_d,
    input  logic [7:0] load_value,
    input  logic       halt_in,
    input  logic       addr,
    input  logic       is_triangle,
    input  logic       write,
    input  logic       enabled,
    output logic       lc_on
);

    logic lc_on_1;
    logic clear_next;
    logic [7:0] len_counter_int;
    logic halt, halt_next;
    logic [7:0] len_counter_next;
    always_ff @(posedge clk) begin : lenunit
        if (aclk1_d)
            if (~enabled)
                lc_on <= 0;

        if (aclk1) begin
            lc_on_1 <= lc_on;
            len_counter_next <= halt || ~|len_counter_int ? len_counter_int : len_counter_int - 1'd1;
            clear_next <= ~halt && ~|len_counter_int;
        end

        if (write) begin
            if (~addr) begin
                halt <= halt_in;
            end else begin
                lc_on <= 1;
                len_counter_int <= load_value;
            end
        end

        // This deliberately can overwrite being loaded from writes
        if (len_clk && lc_on_1) begin
            len_counter_int <= halt ? len_counter_int : len_counter_next;
            if (clear_next)
                lc_on <= 0;
        end

        if (reset) begin
            if (~is_triangle || cold_reset) begin
                halt <= 0;
            end
            lc_on <= 0;
            len_counter_int <= 0;
            len_counter_next <= 0;
        end
    end

endmodule

module EnvelopeUnit (
    input  logic       clk,
    input  logic       reset,
    input  logic       env_clk,
    input  logic [5:0] din,
    input  logic       addr,
    input  logic       write,
    output logic [3:0] envelope
);

    logic [3:0] env_count, env_vol;
    logic env_disabled;

    assign envelope = env_disabled ? env_vol : env_count;

    always_ff @(posedge clk) begin : envunit
        logic [3:0] env_div;
        logic env_reload;
        logic env_loop;
        logic env_reset;

        if (env_clk) begin
            if (~env_reload) begin
                env_div <= env_div - 1'd1;
                if (~|env_div) begin
                    env_div <= env_vol;
                    if (|env_count || env_loop)
                        env_count <= env_count - 1'd1;
                end
            end else begin
                env_div <= env_vol;
                env_count <= 4'hF;
                env_reload <= 1'b0;
            end
        end

        if (write) begin
            if (~addr) {env_loop, env_disabled, env_vol} <= din;
            if (addr) env_reload <= 1;
        end

        if (reset) begin
            env_loop <= 0;
            env_div <= 0;
            env_vol <= 0;
            env_count <= 0;
            env_reload <= 0;
        end
    end

endmodule

module SquareChan (
    input  logic       MMC5,
    input  logic       clk,
    input  logic       ce,
    input  logic       aclk1,
    input  logic       aclk1_d,
    input  logic       reset,
    input  logic       cold_reset,
    input  logic       allow_us,
    input  logic       sq2,
    input  logic [1:0] Addr,
    input  logic [7:0] DIN,
    input  logic       write,
    input  logic [7:0] lc_load,
    input  logic       LenCtr_Clock,
    input  logic       Env_Clock,
    input  logic       odd_or_even,
    input  logic       Enabled,
    output logic [3:0] Sample,
    output logic       IsNonZero
);

    // Register 1
    logic [1:0] Duty;

    // Register 2
    logic SweepEnable, SweepNegate, SweepReset;
    logic [2:0] SweepPeriod, SweepDivider, SweepShift;
    logic [10:0] Period;
    logic [11:0] TimerCtr;
    logic [2:0] SeqPos;
    logic [10:0] ShiftedPeriod;
    logic [10:0] PeriodRhs;
    logic [11:0] NewSweepPeriod;

    logic ValidFreq;
    logic subunit_write;
    logic [3:0] Envelope;
    logic lc;
    logic DutyEnabledUsed;
    logic DutyEnabled;

    assign DutyEnabledUsed = MMC5 ^ DutyEnabled;
    assign ShiftedPeriod = (Period >> SweepShift);
    assign PeriodRhs = (SweepNegate ? (~ShiftedPeriod + {10'b0, sq2}) : ShiftedPeriod);
    assign NewSweepPeriod = Period + PeriodRhs;
    assign subunit_write = (Addr == 0 || Addr == 3) & write;
    assign IsNonZero = lc;

    assign ValidFreq = (MMC5 && allow_us) || ((|Period[10:3]) && (SweepNegate || ~NewSweepPeriod[11]));
    assign Sample = (~lc | ~ValidFreq | ~DutyEnabledUsed) ? 4'd0 : Envelope;

    LenCounterUnit LenSq (
        .clk            (clk),
        .reset          (reset),
        .cold_reset     (cold_reset),
        .aclk1          (aclk1),
        .aclk1_d        (aclk1_d),
        .len_clk        (MMC5 ? Env_Clock : LenCtr_Clock),
        .load_value     (lc_load),
        .halt_in        (DIN[5]),
        .addr           (Addr[0]),
        .is_triangle    (1'b0),
        .write          (subunit_write),
        .enabled        (Enabled),
        .lc_on          (lc)
    );

    EnvelopeUnit EnvSq (
        .clk            (clk),
        .reset          (reset),
        .env_clk        (Env_Clock),
        .din            (DIN[5:0]),
        .addr           (Addr[0]),
        .write          (subunit_write),
        .envelope       (Envelope)
    );

    always_comb begin
        // The wave forms nad barrel shifter are abstracted simply here
        case (Duty)
            0: DutyEnabled = (SeqPos == 7);
            1: DutyEnabled = (SeqPos >= 6);
            2: DutyEnabled = (SeqPos >= 4);
            3: DutyEnabled = (SeqPos < 6);
        endcase
    end

    always_ff @(posedge clk) begin : sqblock
        // Unusual to APU design, the square timers are clocked overlapping two phi2. This
        // means that writes can impact this operation as they happen, however because of the way
        // the results are presented, we can simply delay it rather than adding complexity for
        // the same results.

        if (aclk1_d) begin
            if (TimerCtr == 0) begin
                TimerCtr <= {1'b0, Period};
                SeqPos <= SeqPos - 1'd1;
            end else begin
                TimerCtr <= TimerCtr - 1'd1;
            end
        end

        // Sweep Unit
        if (LenCtr_Clock) begin
            if (SweepDivider == 0) begin
                SweepDivider <= SweepPeriod;
                if (SweepEnable && SweepShift != 0 && ValidFreq)
                    Period <= NewSweepPeriod[10:0];
            end else begin
                SweepDivider <= SweepDivider - 1'd1;
            end
            if (SweepReset)
                SweepDivider <= SweepPeriod;
            SweepReset <= 0;
        end

        if (write) begin
            case (Addr)
                0: Duty <= DIN[7:6];
                1: if (~MMC5) begin
                    {SweepEnable, SweepPeriod, SweepNegate, SweepShift} <= DIN;
                    SweepReset <= 1;
                end
                2: Period[7:0] <= DIN;
                3: begin
                    Period[10:8] <= DIN[2:0];
                    SeqPos <= 0;
                end
            endcase
        end

        if (reset) begin
            Duty <= 0;
            SweepEnable <= 0;
            SweepNegate <= 0;
            SweepReset <= 0;
            SweepPeriod <= 0;
            SweepDivider <= 0;
            SweepShift <= 0;
            Period <= 0;
            TimerCtr <= 0;
            SeqPos <= 0;
        end
    end

endmodule

module TriangleChan (
    input  logic       clk,
    input  logic       phi1,
    input  logic       aclk1,
    input  logic       aclk1_d,
    input  logic       reset,
    input  logic       cold_reset,
    input  logic       allow_us,
    input  logic [1:0] Addr,
    input  logic [7:0] DIN,
    input  logic       write,
    input  logic [7:0] lc_load,
    input  logic       LenCtr_Clock,
    input  logic       LinCtr_Clock,
    input  logic       Enabled,
    output logic [3:0] Sample,
    output logic       IsNonZero
);

    logic [10:0] Period, applied_period, TimerCtr;
    initial Period = 'h3E;
    logic [4:0] SeqPos;
    logic [6:0] LinCtrPeriod, LinCtrPeriod_1, LinCtr;
    logic LinCtrl, line_reload;
    logic LinCtrZero;
    logic lc;

    logic LenCtrZero;
    logic subunit_write;
    logic [3:0] sample_latch;
    // initial sample_latch = 'b1010;

    assign LinCtrZero = ~|LinCtr;
    assign IsNonZero = lc;
    assign subunit_write = (Addr == 0 || Addr == 3) & write;

    assign Sample = (applied_period > 1 || allow_us) ? (SeqPos[3:0] ^ {4{~SeqPos[4]}}) : sample_latch;
    // assign Sample = Period;

    LenCounterUnit LenTri (
        .clk            (clk),
        .reset          (reset),
        .cold_reset     (cold_reset),
        .aclk1          (aclk1),
        .aclk1_d        (aclk1_d),
        .len_clk        (LenCtr_Clock),
        .load_value     (lc_load),
        .halt_in        (DIN[7]),
        .addr           (Addr[0]),
        .is_triangle    (1'b1),
        .write          (subunit_write),
        .enabled        (Enabled),
        .lc_on          (lc)
    );

    always_ff @(posedge clk) begin
        if (phi1) begin
            if (TimerCtr == 0) begin
                TimerCtr <= Period;
                applied_period <= Period;
                if (IsNonZero & ~LinCtrZero)
                    SeqPos <= SeqPos + 1'd1;
            end else begin
                TimerCtr <= TimerCtr - 1'd1;
            end
        end

        if (aclk1) begin
            LinCtrPeriod_1 <= LinCtrPeriod;
        end

        if (LinCtr_Clock) begin
            if (line_reload)
                LinCtr <= LinCtrPeriod_1;
            else if (!LinCtrZero)
                LinCtr <= LinCtr - 1'd1;

            if (!LinCtrl)
                line_reload <= 0;
        end

        if (write) begin
            case (Addr)
                0: begin
                    LinCtrl <= DIN[7];
                    LinCtrPeriod <= DIN[6:0];
                end
                2: begin
                    Period[7:0] <= DIN;
                end
                3: begin
                    Period[10:8] <= DIN[2:0];
                    line_reload <= 1;
                end
            endcase
        end

        if (reset) begin
            sample_latch <= 4'hF;
            Period <= 0;
            TimerCtr <= 0;
            SeqPos <= 0;
            LinCtrPeriod <= 0;
            LinCtr <= 0;
            LinCtrl <= 0;
            line_reload <= 0;
        end

        if (applied_period > 1) 
            sample_latch <= Sample;
    end

endmodule

module TriangleChan_enhanced_5b (
    input  logic       clk,
    input  logic       phi1,
    input  logic       aclk1,
    input  logic       aclk1_d,
    input  logic       reset,
    input  logic       cold_reset,
    input  logic       allow_us,
    input  logic [1:0] Addr,
    input  logic [7:0] DIN,
    input  logic       write,
    input  logic [7:0] lc_load,
    input  logic       LenCtr_Clock,
    input  logic       LinCtr_Clock,
    input  logic       Enabled,
    output logic [4:0] Sample,       // Change output Sample to 5 bits
    output logic       IsNonZero
);
    logic [10:0] Period, applied_period, TimerCtr;
    initial Period = 'h3E;
    logic [4:0] SeqPos;              // Change SeqPos to 5 bits
    logic [6:0] LinCtrPeriod, LinCtrPeriod_1, LinCtr;
    logic LinCtrl, line_reload;
    logic LinCtrZero;
    logic lc;

    logic LenCtrZero;
    logic subunit_write;
    logic [4:0] sample_latch;        // Change sample_latch to 5 bits

    assign LinCtrZero = ~|LinCtr;
    assign IsNonZero = lc;
    assign subunit_write = (Addr == 0 || Addr == 3) & write;

    // Adjust Sample assignment for 5-bit output
    assign Sample = (applied_period > 1 || allow_us) ? (SeqPos[4:0] ^ {5{~SeqPos[4]}}) : sample_latch;

    LenCounterUnit LenTri (
        .clk            (clk),
        .reset          (reset),
        .cold_reset     (cold_reset),
        .aclk1          (aclk1),
        .aclk1_d        (aclk1_d),
        .len_clk        (LenCtr_Clock),
        .load_value     (lc_load),
        .halt_in        (DIN[7]),
        .addr           (Addr[0]),
        .is_triangle    (1'b1),
        .write          (subunit_write),
        .enabled        (Enabled),
        .lc_on          (lc)
    );

    always_ff @(posedge clk) begin
        if (phi1) begin
            if (TimerCtr == 0) begin
                TimerCtr <= Period;
                applied_period <= Period;
                if (IsNonZero & ~LinCtrZero)
                    SeqPos <= SeqPos + 1'd1;
            end else begin
                TimerCtr <= TimerCtr - 1'd1;
            end
        end

        if (aclk1) begin
            LinCtrPeriod_1 <= LinCtrPeriod;
        end

        if (LinCtr_Clock) begin
            if (line_reload)
                LinCtr <= LinCtrPeriod_1;
            else if (!LinCtrZero)
                LinCtr <= LinCtr - 1'd1;

            if (!LinCtrl)
                line_reload <= 0;
        end

        if (write) begin
            case (Addr)
                0: begin
                    LinCtrl <= DIN[7];
                    LinCtrPeriod <= DIN[6:0];
                end
                2: begin
                    Period[7:0] <= DIN;
                end
                3: begin
                    Period[10:8] <= DIN[2:0];
                    line_reload <= 1;
                end
            endcase
        end

        if (reset) begin
            sample_latch <= 5'h1F;   // Initialize to 5-bit value
            Period <= 0;
            TimerCtr <= 0;
            SeqPos <= 0;
            LinCtrPeriod <= 0;
            LinCtr <= 0;
            LinCtrl <= 0;
            line_reload <= 0;
        end

        if (applied_period > 1) sample_latch <= Sample;
    end
endmodule

module TriangleChan_enhanced_6b (
    input  logic       clk,
    input  logic       phi1,
    input  logic       aclk1,
    input  logic       aclk1_d,
    input  logic       reset,
    input  logic       cold_reset,
    input  logic       allow_us,
    input  logic [1:0] Addr,
    input  logic [7:0] DIN,
    input  logic       write,
    input  logic [7:0] lc_load,
    input  logic       LenCtr_Clock,
    input  logic       LinCtr_Clock,
    input  logic       Enabled,
    output logic [5:0] Sample,
    output logic       IsNonZero
);
    logic [10:0] Period, applied_period, TimerCtr;
    logic [5:0] SeqPos;
    logic [6:0] LinCtrPeriod, LinCtrPeriod_1, LinCtr;
    logic LinCtrl, line_reload;
    logic LinCtrZero;
    logic lc;

    logic LenCtrZero;
    logic subunit_write;
    logic [5:0] sample_latch;

    assign LinCtrZero = ~|LinCtr;
    assign IsNonZero = lc;
    assign subunit_write = (Addr == 0 || Addr == 3) & write;

    assign Sample = (applied_period > 1 || allow_us) ? (SeqPos ^ {6{~SeqPos[5]}}) : sample_latch;

    LenCounterUnit LenTri (
        .clk            (clk),
        .reset          (reset),
        .cold_reset     (cold_reset),
        .aclk1          (aclk1),
        .aclk1_d        (aclk1_d),
        .len_clk        (LenCtr_Clock),
        .load_value     (lc_load),
        .halt_in        (DIN[7]),
        .addr           (Addr[0]),
        .is_triangle    (1'b1),
        .write          (subunit_write),
        .enabled        (Enabled),
        .lc_on          (lc)
    );

    always_ff @(posedge clk) begin
        if (phi1) begin
            if (TimerCtr == 0) begin
                TimerCtr <= Period;
                applied_period <= Period;
                if (IsNonZero & ~LinCtrZero)
                    SeqPos <= SeqPos + 1'd1;
            end else begin
                TimerCtr <= TimerCtr - 1'd1;
            end
        end

        if (aclk1) begin
            LinCtrPeriod_1 <= LinCtrPeriod;
        end

        if (LinCtr_Clock) begin
            if (line_reload)
                LinCtr <= LinCtrPeriod_1;
            else if (!LinCtrZero)
                LinCtr <= LinCtr - 1'd1;

            if (!LinCtrl)
                line_reload <= 0;
        end

        if (write) begin
            case (Addr)
                0: begin
                    LinCtrl <= DIN[7];
                    LinCtrPeriod <= DIN[6:0];
                end
                2: begin
                    Period[7:0] <= DIN;
                end
                3: begin
                    Period[10:8] <= DIN[2:0];
                    line_reload <= 1;
                end
            endcase
        end

        if (reset) begin
            sample_latch <= 6'h3F;
            Period <= 0;
            TimerCtr <= 0;
            SeqPos <= 0;
            LinCtrPeriod <= 0;
            LinCtr <= 0;
            LinCtrl <= 0;
            line_reload <= 0;
        end

        if (applied_period > 1) sample_latch <= Sample;
    end

endmodule



module NoiseChan (
    input  logic       clk,
    input  logic       ce,
    input  logic       aclk1,
    input  logic       aclk1_d,
    input  logic       reset,
    input  logic       cold_reset,
    input  logic [1:0] Addr,
    input  logic [7:0] DIN,
    input  logic       PAL,
    input  logic       write,
    input  logic [7:0] lc_load,
    input  logic       LenCtr_Clock,
    input  logic       Env_Clock,
    input  logic       Enabled,
    output logic [3:0] Sample,
    output logic       IsNonZero
);
    logic ShortMode;
    logic [14:0] Shift;
    logic [3:0] Period;
    logic [11:0] NoisePeriod, TimerCtr;
    logic [3:0] Envelope;
    logic subunit_write;
    logic lc;

    assign IsNonZero = lc;
    assign subunit_write = (Addr == 0 || Addr == 3) & write;

    // Produce the output signal
    assign Sample = (~lc || Shift[14]) ? 4'd0 : Envelope;

    LenCounterUnit LenNoi (
        .clk            (clk),
        .reset          (reset),
        .cold_reset     (cold_reset),
        .aclk1          (aclk1),
        .aclk1_d        (aclk1_d),
        .len_clk        (LenCtr_Clock),
        .load_value     (lc_load),
        .halt_in        (DIN[5]),
        .addr           (Addr[0]),
        .is_triangle    (1'b0),
        .write          (subunit_write),
        .enabled        (Enabled),
        .lc_on          (lc)
    );

    EnvelopeUnit EnvNoi (
        .clk            (clk),
        .reset          (reset),
        .env_clk        (Env_Clock),
        .din            (DIN[5:0]),
        .addr           (Addr[0]),
        .write          (subunit_write),
        .envelope       (Envelope)
    );

    reg [10:0] noise_pal_lut[0:15];
    initial begin
        noise_pal_lut[0] = 11'h200;
        noise_pal_lut[1] = 11'h280;
        noise_pal_lut[2] = 11'h550;
        noise_pal_lut[3] = 11'h5D5;
        noise_pal_lut[4] = 11'h393;
        noise_pal_lut[5] = 11'h74F;
        noise_pal_lut[6] = 11'h61B;
        noise_pal_lut[7] = 11'h41F;
        noise_pal_lut[8] = 11'h661;
        noise_pal_lut[9] = 11'h1C5;
        noise_pal_lut[10] = 11'h6AE;
        noise_pal_lut[11] = 11'h093;
        noise_pal_lut[12] = 11'h4FE;
        noise_pal_lut[13] = 11'h12D;
        noise_pal_lut[14] = 11'h679;
        noise_pal_lut[15] = 11'h392;
    end

    // Values read directly from the netlist
    reg [10:0] noise_ntsc_lut[0:15];
    initial begin
        noise_ntsc_lut[0] = 11'h200;
        noise_ntsc_lut[1] = 11'h280;
        noise_ntsc_lut[2] = 11'h2A8;
        noise_ntsc_lut[3] = 11'h6EA;
        noise_ntsc_lut[4] = 11'h4E4;
        noise_ntsc_lut[5] = 11'h674;
        noise_ntsc_lut[6] = 11'h630;
        noise_ntsc_lut[7] = 11'h730;
        noise_ntsc_lut[8] = 11'h4AC;
        noise_ntsc_lut[9] = 11'h304;
        noise_ntsc_lut[10] = 11'h722;
        noise_ntsc_lut[11] = 11'h230;
        noise_ntsc_lut[12] = 11'h213;
        noise_ntsc_lut[13] = 11'h782;
        noise_ntsc_lut[14] = 11'h006;
        noise_ntsc_lut[15] = 11'h014;
    end

    logic [10:0] noise_timer;
    logic noise_clock;
    always_ff @(posedge clk) begin
        if (aclk1_d) begin
            noise_timer <= {noise_timer[9:0], (noise_timer[10] ^ noise_timer[8]) | ~|noise_timer};

            if (noise_clock) begin
                noise_clock <= 0;
                noise_timer <= PAL ? noise_pal_lut[Period] : noise_ntsc_lut[Period];
                Shift <= {Shift[13:0], ((Shift[14] ^ (ShortMode ? Shift[8] : Shift[13])) | ~|Shift)};
            end
        end

        if (aclk1) begin
            if (noise_timer == 'h400)
                noise_clock <= 1;
        end

        if (write && Addr == 2) begin
            ShortMode <= DIN[7];
            Period <= DIN[3:0];
        end

        if (reset) begin
            if (|noise_timer) noise_timer <= (PAL ? noise_pal_lut[0] : noise_ntsc_lut[0]);
            ShortMode <= 0;
            Shift <= 0;
            Period <= 0;
        end

        if (cold_reset)
            noise_timer <= 0;
    end
endmodule

module DmcChan (
    input  logic        MMC5,
    input  logic        clk,
    input  logic        aclk1,
    input  logic        aclk1_d,
    input  logic        reset,
    input  logic        cold_reset,
    input  logic  [2:0] ain,
    input  logic  [7:0] DIN,
    input  logic        write,
    input  logic        dma_ack,      // 1 when DMC byte is on DmcData. DmcDmaRequested should go low.
    input  logic  [7:0] dma_data,     // Input data to DMC from memory.
    input  logic        PAL,
    output logic [15:0] dma_address,     // Address DMC wants to read
    output logic        irq,
    output logic  [6:0] Sample,
    output logic        dma_req,      // 1 when DMC wants DMA
    output logic        enable
);
    logic irq_enable;
    logic loop;                 // Looping enabled
    logic [3:0] frequency;           // Current value of frequency register
    logic [7:0] sample_address;  // Base address of sample
    logic [7:0] sample_length;      // Length of sample
    logic [11:0] bytes_remaining;      // 12 bits bytes left counter 0 - 4081.
    logic [7:0] sample_buffer;    // Next value to be loaded into shift reg

    logic [8:0] dmc_lsfr;
    logic [7:0] dmc_volume, dmc_volume_next;
    logic dmc_silence;
    logic have_buffer;
    logic [7:0] sample_shift;
    logic [2:0] dmc_bits; // Simply an 8 cycle counter.
    logic enable_1, enable_2, enable_3;

    reg [8:0] pal_pitch_lut[0:15];
    initial begin
        pal_pitch_lut[0] = 9'h1D7;
        pal_pitch_lut[1] = 9'h067;
        pal_pitch_lut[2] = 9'h0D9;
        pal_pitch_lut[3] = 9'h143;
        pal_pitch_lut[4] = 9'h1E1;
        pal_pitch_lut[5] = 9'h07B;
        pal_pitch_lut[6] = 9'h05C;
        pal_pitch_lut[7] = 9'h132;
        pal_pitch_lut[8] = 9'h04A;
        pal_pitch_lut[9] = 9'h1A3;
        pal_pitch_lut[10] = 9'h1CF;
        pal_pitch_lut[11] = 9'h1CD;
        pal_pitch_lut[12] = 9'h02A;
        pal_pitch_lut[13] = 9'h11C;
        pal_pitch_lut[14] = 9'h11B;
        pal_pitch_lut[15] = 9'h157;
    end

    reg [8:0] ntsc_pitch_lut[0:15];
    initial begin
        ntsc_pitch_lut[0] = 9'h19D;
        ntsc_pitch_lut[1] = 9'h0A2;
        ntsc_pitch_lut[2] = 9'h185;
        ntsc_pitch_lut[3] = 9'h1B6;
        ntsc_pitch_lut[4] = 9'h0EF;
        ntsc_pitch_lut[5] = 9'h1F8;
        ntsc_pitch_lut[6] = 9'h17C;
        ntsc_pitch_lut[7] = 9'h117;
        ntsc_pitch_lut[8] = 9'h120;
        ntsc_pitch_lut[9] = 9'h076;
        ntsc_pitch_lut[10] = 9'h11E;
        ntsc_pitch_lut[11] = 9'h13E;
        ntsc_pitch_lut[12] = 9'h162;
        ntsc_pitch_lut[13] = 9'h123;
        ntsc_pitch_lut[14] = 9'h0E3;
        ntsc_pitch_lut[15] = 9'h0D5;
    end

    assign Sample = dmc_volume_next[6:0];
    assign dma_req = ~have_buffer & enable & enable_3;
    logic dmc_clock;


    logic reload_next;
    always_ff @(posedge clk) begin
        dma_address[15] <= 1;
        if (write) begin
            case (ain)
                0: begin  // $4010
                        irq_enable <= DIN[7];
                        loop <= DIN[6];
                        frequency <= DIN[3:0];
                        if (~DIN[7]) irq <= 0;
                    end
                1: begin  // $4011 Applies immediately, can be overwritten before aclk1
                        dmc_volume <= {MMC5 & DIN[7], DIN[6:0]};
                    end
                2: begin  // $4012
                        sample_address <= MMC5 ? 8'h00 : DIN[7:0];
                    end
                3: begin  // $4013
                        sample_length <= MMC5 ? 8'h00 : DIN[7:0];
                    end
                5: begin // $4015
                        irq <= 0;
                        enable <= DIN[4];

                        if (DIN[4] && ~enable) begin
                            dma_address[14:0] <= {1'b1, sample_address[7:0], 6'h00};
                            bytes_remaining <= {sample_length, 4'h0};
                        end
                    end
            endcase
        end

        if (aclk1_d) begin
            enable_1 <= enable;
            enable_2 <= enable_1;
            dmc_lsfr <= {dmc_lsfr[7:0], (dmc_lsfr[8] ^ dmc_lsfr[4]) | ~|dmc_lsfr};

            if (dmc_clock) begin
                dmc_clock <= 0;
                dmc_lsfr <= PAL ? pal_pitch_lut[frequency] : ntsc_pitch_lut[frequency];
                sample_shift <= {1'b0, sample_shift[7:1]};
                dmc_bits <= dmc_bits + 1'd1;

                if (&dmc_bits) begin
                    dmc_silence <= ~have_buffer;
                    sample_shift <= sample_buffer;
                    have_buffer <= 0;
                end

                if (~dmc_silence) begin
                    if (~sample_shift[0]) begin
                        if (|dmc_volume_next[6:1])
                            dmc_volume[6:1] <= dmc_volume_next[6:1] - 1'd1;
                    end else begin
                        if(~&dmc_volume_next[6:1])
                            dmc_volume[6:1] <= dmc_volume_next[6:1] + 1'd1;
                    end
                end
            end

            // The data is technically clocked at phi2, but because of our implementation, to
            // ensure the right data is latched, we do it on the falling edge of phi2.
            if (dma_ack) begin
                dma_address[14:0] <= dma_address[14:0] + 1'd1;
                have_buffer <= 1;
                sample_buffer <= dma_data;

                if (|bytes_remaining)
                    bytes_remaining <= bytes_remaining - 1'd1;
                else begin
                    dma_address[14:0] <= {1'b1, sample_address[7:0], 6'h0};
                    bytes_remaining <= {sample_length, 4'h0};
                    enable <= loop;
                    if (~loop & irq_enable)
                        irq <= 1;
                end
            end
        end

        // Volume adjustment is done on aclk1. Technically, the value written to 4011 is immediately
        // applied, but won't "stick" if it conflicts with a lsfr clocked do-adjust.
        if (aclk1) begin
            enable_1 <= enable;
            enable_3 <= enable_2;

            dmc_volume_next <= dmc_volume;

            if (dmc_lsfr == 9'h100) begin
                dmc_clock <= 1;
            end
        end

        if (reset) begin
            irq <= 0;
            dmc_volume <= {7'h0, dmc_volume[0]};
            dmc_volume_next <= {7'h0, dmc_volume[0]};
            sample_shift <= 8'h0;
            if (|dmc_lsfr) dmc_lsfr <= (PAL ? pal_pitch_lut[0] : ntsc_pitch_lut[0]);
            bytes_remaining <= 0;
            dmc_bits <= 0;
            sample_buffer <= 0;
            have_buffer <= 0;
            enable <= 0;
            enable_1 <= 0;
            enable_2 <= 0;
            enable_3 <= 0;
            dma_address[14:0] <= 15'h0000;
        end

        if (cold_reset) begin
            dmc_lsfr <= 0;
            loop <= 0;
            frequency <= 0;
            irq_enable <= 0;
            dmc_volume <= 0;
            dmc_volume_next <= 0;
            sample_address <= 0;
            sample_length <= 0;
        end

    end

endmodule

module FrameCtr (
    input  logic clk,
    input  logic aclk1,
    input  logic aclk2,
    input  logic reset,
    input  logic cold_reset,
    input  logic write,
    input  logic read,
    input  logic write_ce,
    input  logic [7:0] din,
    input  logic [1:0] addr,
    input  logic PAL,
    input  logic MMC5,
    output logic irq,
    output logic irq_flag,
    output logic frame_half,
    output logic frame_quarter
);

    // NTSC -- Confirmed
    // Binary Frame Value         Decimal  Cycle
    // 15'b001_0000_0110_0001,    04193    03713 -- Quarter
    // 15'b011_0110_0000_0011,    13827    07441 -- Half
    // 15'b010_1100_1101_0011,    11475    11170 -- 3 quarter
    // 15'b000_1010_0001_1111,    02591    14899 -- Reset w/o Seq/Interrupt
    // 15'b111_0001_1000_0101     29061    18625 -- Reset w/ seq

    // PAL -- Speculative
    // Binary Frame Value         Decimal  Cycle
    // 15'b001_1111_1010_0100     08100    04156
    // 15'b100_0100_0011_0000     17456    08313
    // 15'b101_1000_0001_0101     22549    12469
    // 15'b000_1011_1110_1000     03048    16625
    // 15'b000_0100_1111_1010     01274    20782

    logic frame_reset;
    logic frame_interrupt_buffer;
    logic frame_int_disabled;
    logic FrameInterrupt;
    logic frame_irq, set_irq;
    logic FrameSeqMode_2;
    logic frame_reset_2;
    logic w4017_1, w4017_2;
    logic [14:0] frame;

    // Register 4017
    logic DisableFrameInterrupt;
    logic FrameSeqMode;

    assign frame_int_disabled = DisableFrameInterrupt; // | (write && addr == 5'h17 && din[6]);
    assign irq = FrameInterrupt && ~DisableFrameInterrupt;
    assign irq_flag = frame_interrupt_buffer;

    // This is implemented from the original LSFR frame counter logic taken from the 2A03 netlists. The
    // PAL LFSR numbers are educated guesses based on existing observed cycle numbers, but they may not
    // be perfectly correct.

    logic seq_mode;
    assign seq_mode = aclk1 ? FrameSeqMode : FrameSeqMode_2;

    logic frm_a, frm_b, frm_c, frm_d, frm_e;
    assign frm_a = (PAL ? 15'b001_1111_1010_0100 : 15'b001_0000_0110_0001) == frame;
    assign frm_b = (PAL ? 15'b100_0100_0011_0000 : 15'b011_0110_0000_0011) == frame;
    assign frm_c = (PAL ? 15'b101_1000_0001_0101 : 15'b010_1100_1101_0011) == frame;
    assign frm_d = (PAL ? 15'b000_1011_1110_1000 : 15'b000_1010_0001_1111) == frame && ~seq_mode;
    assign frm_e = (PAL ? 15'b000_0100_1111_1010 : 15'b111_0001_1000_0101) == frame;

    assign set_irq = frm_d & ~FrameSeqMode;
    assign frame_reset = frm_d | frm_e | w4017_2;
    assign frame_half = (frm_b | frm_d | frm_e | (w4017_2 & seq_mode));
    assign frame_quarter = (frm_a | frm_b | frm_c | frm_d | frm_e | (w4017_2 & seq_mode));

    always_ff @(posedge clk) begin : apu_block

        if (aclk1) begin
            frame <= frame_reset_2 ? 15'h7FFF : {frame[13:0], ((frame[14] ^ frame[13]) | ~|frame)};
            w4017_2 <= w4017_1;
            w4017_1 <= 0;
            FrameSeqMode_2 <= FrameSeqMode;
            frame_reset_2 <= 0;
        end

        if (aclk2 & frame_reset)
            frame_reset_2 <= 1;

        // Continously update the Frame IRQ state and read buffer
        if (set_irq & ~frame_int_disabled) begin
            FrameInterrupt <= 1;
            frame_interrupt_buffer <= 1;
        end else if (addr == 2'h1 && read)
            FrameInterrupt <= 0;
        else
            frame_interrupt_buffer <= FrameInterrupt;

        if (frame_int_disabled)
            FrameInterrupt <= 0;

        if (write_ce && addr == 3 && ~MMC5) begin  // Register $4017
            FrameSeqMode <= din[7];
            DisableFrameInterrupt <= din[6];
            w4017_1 <= 1;
        end

        if (reset) begin
            FrameInterrupt <= 0;
            frame_interrupt_buffer <= 0;
            w4017_1 <= 0;
            w4017_2 <= 0;
            DisableFrameInterrupt <= 0;
            if (cold_reset) FrameSeqMode <= 0; // Don't reset this on warm reset
            frame <= 15'h7FFF;
        end
    end

endmodule

module APU (
    input  logic        MMC5,
    input  logic        clk,
    input  logic        PHI2,
    input  logic        ce,
    input  logic        reset,
    input  logic        cold_reset,
    input  logic        allow_us,       // Set to 1 to allow ultrasonic frequencies
    input  logic        PAL,
    input  logic  [4:0] ADDR,           // APU Address Line
    input  logic  [7:0] DIN,            // Data to APU
    input  logic        RW,
    input  logic        CS,
    input  logic  [4:0] audio_channels, // Enabled audio channels
    input  logic  [7:0] DmaData,        // Input data to DMC from memory.
    input  logic        odd_or_even,
    input  logic        DmaAck,         // 1 when DMC byte is on DmcData. DmcDmaRequested should go low.
    output logic  [7:0] DOUT,           // Data from APU
    output wire  [15:0] Sample,
    output logic        DmaReq,         // 1 when DMC wants DMA
    output logic [15:0] DmaAddr,        // Address DMC wants to read
    output logic        IRQ,            // IRQ asserted high == asserted
    // Enhanced APU
    input  logic        apu_enhanced_ce,
    input  logic        apu_mapper_saturates,
    output logic        o_ce
    );

    reg [7:0] len_counter_lut[0:31];

    initial begin
        len_counter_lut[0] = 8'h09;
        len_counter_lut[1] = 8'hFD;
        len_counter_lut[2] = 8'h13;
        len_counter_lut[3] = 8'h01;
        len_counter_lut[4] = 8'h27;
        len_counter_lut[5] = 8'h03;
        len_counter_lut[6] = 8'h4F;
        len_counter_lut[7] = 8'h05;
        len_counter_lut[8] = 8'h9F;
        len_counter_lut[9] = 8'h07;
        len_counter_lut[10] = 8'h3B;
        len_counter_lut[11] = 8'h09;
        len_counter_lut[12] = 8'h0D;
        len_counter_lut[13] = 8'h0B;
        len_counter_lut[14] = 8'h19;
        len_counter_lut[15] = 8'h0D;
        len_counter_lut[16] = 8'h0B;
        len_counter_lut[17] = 8'h0F;
        len_counter_lut[18] = 8'h17;
        len_counter_lut[19] = 8'h11;
        len_counter_lut[20] = 8'h2F;
        len_counter_lut[21] = 8'h13;
        len_counter_lut[22] = 8'h5F;
        len_counter_lut[23] = 8'h15;
        len_counter_lut[24] = 8'hBF;
        len_counter_lut[25] = 8'h17;
        len_counter_lut[26] = 8'h47;
        len_counter_lut[27] = 8'h19;
        len_counter_lut[28] = 8'h0F;
        len_counter_lut[29] = 8'h1B;
        len_counter_lut[30] = 8'h1F;
        len_counter_lut[31] = 8'h1D;
    end

    logic [7:0] lc_load;
    assign lc_load = len_counter_lut[DIN[7:3]];

    // APU reads and writes happen at Phi2 of the 6502 core. Note: Not M2.
    logic read, read_old;
    logic write, write_ce, write_old;
    logic phi2_old, phi2_ce;

    assign read = RW & CS;
    assign write = ~RW & CS;
    assign phi2_ce = PHI2 & ~phi2_old;
    assign write_ce = write & phi2_ce;

    // The APU has four primary clocking events that take place:
    // aclk1    -- Aligned with CPU phi1, but every other cpu tick. This drives the majority of the APU
    // aclk1_d  -- Aclk1, except delayed by 1 cpu cycle exactly. Drives he half/quarter signals and len counter
    // aclk2    -- Aligned with CPU phi2, also every other frame
    // write    -- Happens on CPU phi2 (Not M2!). Most of these are latched by one of the above clocks.
    logic aclk1, aclk2, aclk1_delayed, phi1; /* synthesis syn_keep=1 */ 
    // assign aclk1 = (ce)&(odd_or_even);              // Defined as the cpu tick when the frame counter increases
    assign aclk1 = (odd_or_even);              // Defined as the cpu tick when the frame counter increases
    assign aclk2 = phi2_ce & ~odd_or_even;          // Tick on odd cycles, not 50% duty cycle so it covers 2 cpu cycles
    assign aclk1_delayed = ce & ~odd_or_even;       // Ticks 1 cpu cycle after frame counter
    assign phi1 = ce;

    logic [4:0] Enabled;
    logic [3:0] Sq1Sample,Sq2Sample,TriSample,NoiSample;
    logic [4:0] TriSample_enhanced;
    logic [6:0] DmcSample;
    logic DmcIrq;
    logic IsDmcActive;

    logic irq_flag;
    logic frame_irq;

    // Generate internal memory write signals
    logic ApuMW0, ApuMW1, ApuMW2, ApuMW3, ApuMW4, ApuMW5;
    assign ApuMW0 = ADDR[4:2]==0; // SQ1
    assign ApuMW1 = ADDR[4:2]==1; // SQ2
    assign ApuMW2 = ADDR[4:2]==2; // TRI
    assign ApuMW3 = ADDR[4:2]==3; // NOI
    assign ApuMW4 = ADDR[4:2]>=4; // DMC
    assign ApuMW5 = ADDR[4:2]==5; // Control registers

    logic Sq1NonZero, Sq2NonZero, TriNonZero, TriNonZero_enhanced, NoiNonZero;
    logic ClkE, ClkL; /* synthesis syn_keep=1 */

    logic [4:0] enabled_buffer, enabled_buffer_1;
    assign Enabled = aclk1 ? enabled_buffer : enabled_buffer_1;

    // Assign the new o_ce output to aclk1
    assign o_ce = aclk1; // This will indicate when Sample is valid

    always_ff @(posedge clk) begin
        phi2_old <= PHI2;

        if (aclk1) begin
            enabled_buffer_1 <= enabled_buffer;
        end

        if (ApuMW5 && write && ADDR[1:0] == 1) begin
            enabled_buffer <= DIN[4:0]; // Register $4015
        end

        if (reset) begin
            enabled_buffer <= 0;
            enabled_buffer_1 <= 0;
        end
    end

    logic frame_quarter, frame_half; /* synthesis syn_keep=1 */
    assign ClkE = ((frame_quarter)&(aclk1_delayed));
    assign ClkL = ((frame_half)&(aclk1_delayed));

    // Generate bus output
    assign DOUT = {DmcIrq, irq_flag, 1'b0, IsDmcActive, NoiNonZero, TriNonZero, Sq2NonZero, Sq1NonZero};

    assign IRQ = frame_irq || DmcIrq;

    // Generate each channel
    SquareChan Squ1 (
        .MMC5         (MMC5),
        .clk          (clk),
        .ce           (ce),
        .aclk1        (aclk1),
        .aclk1_d      (aclk1_delayed),
        .reset        (reset),
        .cold_reset   (cold_reset),
        .allow_us     (allow_us),
        .sq2          (1'b0),
        .Addr         (ADDR[1:0]),
        .DIN          (DIN),
        .write        (ApuMW0 && write),
        .lc_load      (lc_load),
        .LenCtr_Clock (ClkL),
        .Env_Clock    (ClkE),
        .odd_or_even  (odd_or_even),
        .Enabled      (Enabled[0]),
        .Sample       (Sq1Sample),
        .IsNonZero    (Sq1NonZero)
    );

    SquareChan Squ2 (
        .MMC5         (MMC5),
        .clk          (clk),
        .ce           (ce),
        .aclk1        (aclk1),
        .aclk1_d      (aclk1_delayed),
        .reset        (reset),
        .cold_reset   (cold_reset),
        .allow_us     (allow_us),       // nand2mario
        .sq2          (1'b1),
        .Addr         (ADDR[1:0]),
        .DIN          (DIN),
        .write        (ApuMW1 && write),
        .lc_load      (lc_load),
        .LenCtr_Clock (ClkL),
        .Env_Clock    (ClkE),
        .odd_or_even  (odd_or_even),
        .Enabled      (Enabled[1]),
        .Sample       (Sq2Sample),
        .IsNonZero    (Sq2NonZero)
    );

    TriangleChan Tri (
        .clk          (clk),
        .phi1         (phi1),
        .aclk1        (aclk1),
        .aclk1_d      (aclk1_delayed),
        .reset        (reset),
        .cold_reset   (cold_reset),
        .allow_us     (allow_us),
        .Addr         (ADDR[1:0]),
        .DIN          (DIN),
        .write        ((ApuMW2)&&(write)),
        .lc_load      (lc_load),
        .LenCtr_Clock (ClkE),
        .LinCtr_Clock (ClkL),
        .Enabled      (Enabled[2]),
        .Sample       (TriSample),
        .IsNonZero    (TriNonZero)
    );

    TriangleChan_enhanced_5b Tri_enhanced (
        .clk          (clk),
        .phi1         (phi1),
        .aclk1        (aclk1),
        .aclk1_d      (aclk1_delayed),
        .reset        (reset),
        .cold_reset   (cold_reset),
        .allow_us     (allow_us),
        .Addr         (ADDR[1:0]),
        .DIN          (DIN),
        .write        (ApuMW2 && write),
        .lc_load      (lc_load),
        .LenCtr_Clock (ClkL),
        .LinCtr_Clock (ClkE),
        .Enabled      (Enabled[2]),
        .Sample       (TriSample_enhanced),
        .IsNonZero    (TriNonZero_enhanced)
    );

    NoiseChan Noi (
        .clk          (clk),
        .ce           (ce),
        .aclk1        (aclk1),
        .aclk1_d      (aclk1_delayed),
        .reset        (reset),
        .cold_reset   (cold_reset),
        .Addr         (ADDR[1:0]),
        .DIN          (DIN),
        .PAL          (PAL),
        .write        (ApuMW3 && write),
        .lc_load      (lc_load),
        .LenCtr_Clock (ClkL),
        .Env_Clock    (ClkE),
        .Enabled      (Enabled[3]),
        .Sample       (NoiSample),
        .IsNonZero    (NoiNonZero)
    );

    DmcChan Dmc (
        .MMC5        (MMC5),
        .clk         (clk),
        .aclk1       (aclk1),
        .aclk1_d     (aclk1_delayed),
        .reset       (reset),
        .cold_reset  (cold_reset),
        .ain         (ADDR[2:0]),
        .DIN         (DIN),
        .write       (write & ApuMW4),
        .dma_ack     (DmaAck),
        .dma_data    (DmaData),
        .PAL         (PAL),
        .dma_address (DmaAddr),
        .irq         (DmcIrq),
        .Sample      (DmcSample),
        .dma_req     (DmaReq),
        .enable      (IsDmcActive)
    );

    APUMixer mixer (
        .square1      (Sq1Sample),
        .square2      (Sq2Sample),
        .noise        (NoiSample),
        .triangle     (TriSample),
        .dmc          (DmcSample),
        .sample       (Sample),
        // Enhanced APU
        .apu_enhanced_ce(apu_enhanced_ce),
        .apu_triangle_enhanced(TriSample_enhanced),
        .apu_mapper_saturates(apu_mapper_saturates)
    );

    FrameCtr frame_counter (
        .clk          (clk),
        .aclk1        (aclk1),
        .aclk2        (aclk2),
        .reset        (reset),
        .cold_reset   (cold_reset),
        .write        (ApuMW5 & write),
        .read         (ApuMW5 & read),
        .write_ce     (ApuMW5 & write_ce),
        .addr         (ADDR[1:0]),
        .din          (DIN),
        .PAL          (PAL),
        .MMC5         (MMC5),
        .irq          (frame_irq),
        .irq_flag     (irq_flag),
        .frame_half   (frame_half),
        .frame_quarter(frame_quarter)
    );

endmodule

// http://wiki.nesdev.com/w/index.php/APU_Mixer
// I generated three LUT's for each mix channel entry and one lut for the squares, then a
// 284 entry lut for the mix channel. It's more accurate than the original LUT system listed on
// the NesDev page. In addition I boosted the square channel 10% and lowered the mix channel 10%
// to more closely match real systems.

module APUMixer (
    input  logic  [3:0] square1,
    input  logic  [3:0] square2,
    input  logic  [3:0] triangle,
    input  logic  [3:0] noise,
    input  logic  [6:0] dmc,
    output logic [15:0] sample,
    // Enhanced APU
    input  logic        apu_enhanced_ce,
    input  logic  [4:0] apu_triangle_enhanced,
    input  logic        apu_mapper_saturates
);

reg [15:0] pulse_lut[0:31];
initial begin
    pulse_lut[0] = 16'h0000;
    pulse_lut[1] = 16'h0331;
    pulse_lut[2] = 16'h064F;
    pulse_lut[3] = 16'h0959;
    pulse_lut[4] = 16'h0C52;
    pulse_lut[5] = 16'h0F38;
    pulse_lut[6] = 16'h120E;
    pulse_lut[7] = 16'h14D3;
    pulse_lut[8] = 16'h1788;
    pulse_lut[9] = 16'h1A2E;
    pulse_lut[10] = 16'h1CC6;
    pulse_lut[11] = 16'h1F4E;
    pulse_lut[12] = 16'h21C9;
    pulse_lut[13] = 16'h2437;
    pulse_lut[14] = 16'h2697;
    pulse_lut[15] = 16'h28EB;
    pulse_lut[16] = 16'h2B32;
    pulse_lut[17] = 16'h2D6E;
    pulse_lut[18] = 16'h2F9E;
    pulse_lut[19] = 16'h31C3;
    pulse_lut[20] = 16'h33DD;
    pulse_lut[21] = 16'h35EC;
    pulse_lut[22] = 16'h37F2;
    pulse_lut[23] = 16'h39ED;
    pulse_lut[24] = 16'h3BDF;
    pulse_lut[25] = 16'h3DC7;
    pulse_lut[26] = 16'h3FA6;
    pulse_lut[27] = 16'h417D;
    pulse_lut[28] = 16'h434B;
    pulse_lut[29] = 16'h4510;
    pulse_lut[30] = 16'h46CD;
    pulse_lut[31] = 16'h0000;
end

reg [5:0] tri_lut[0:15];
initial begin
    tri_lut[0] = 6'h00;
    tri_lut[1] = 6'h04;
    tri_lut[2] = 6'h08;
    tri_lut[3] = 6'h0C;
    tri_lut[4] = 6'h10;
    tri_lut[5] = 6'h14;
    tri_lut[6] = 6'h18;
    tri_lut[7] = 6'h1C;
    tri_lut[8] = 6'h20;
    tri_lut[9] = 6'h24;
    tri_lut[10] = 6'h28;
    tri_lut[11] = 6'h2C;
    tri_lut[12] = 6'h30;
    tri_lut[13] = 6'h34;
    tri_lut[14] = 6'h38;
    tri_lut[15] = 6'h3C;
end

// Enhanced APU
reg [5:0] tri_lut_enhanced_5b[0:31];
initial begin
    tri_lut_enhanced_5b[0] = 6'h00;
    tri_lut_enhanced_5b[1] = 6'h01;
    tri_lut_enhanced_5b[2] = 6'h02;
    tri_lut_enhanced_5b[3] = 6'h04;
    tri_lut_enhanced_5b[4] = 6'h06;
    tri_lut_enhanced_5b[5] = 6'h08;
    tri_lut_enhanced_5b[6] = 6'h0A;
    tri_lut_enhanced_5b[7] = 6'h0C;
    tri_lut_enhanced_5b[8] = 6'h0E;
    tri_lut_enhanced_5b[9] = 6'h10;
    tri_lut_enhanced_5b[10] = 6'h12;
    tri_lut_enhanced_5b[11] = 6'h14;
    tri_lut_enhanced_5b[12] = 6'h16;
    tri_lut_enhanced_5b[13] = 6'h18;
    tri_lut_enhanced_5b[14] = 6'h1A;
    tri_lut_enhanced_5b[15] = 6'h1C;
    tri_lut_enhanced_5b[16] = 6'h1E;
    tri_lut_enhanced_5b[17] = 6'h20;
    tri_lut_enhanced_5b[18] = 6'h22;
    tri_lut_enhanced_5b[19] = 6'h24;
    tri_lut_enhanced_5b[20] = 6'h26;
    tri_lut_enhanced_5b[21] = 6'h28;
    tri_lut_enhanced_5b[22] = 6'h2A;
    tri_lut_enhanced_5b[23] = 6'h2C;
    tri_lut_enhanced_5b[24] = 6'h2E;
    tri_lut_enhanced_5b[25] = 6'h30;
    tri_lut_enhanced_5b[26] = 6'h32;
    tri_lut_enhanced_5b[27] = 6'h34;
    tri_lut_enhanced_5b[28] = 6'h36;
    tri_lut_enhanced_5b[29] = 6'h38;
    tri_lut_enhanced_5b[30] = 6'h3A;
    tri_lut_enhanced_5b[31] = 6'h3C;
end

reg [5:0] noise_lut[0:15];
initial begin
    noise_lut[0] = 6'h00;
    noise_lut[1] = 6'h03;
    noise_lut[2] = 6'h05;
    noise_lut[3] = 6'h08;
    noise_lut[4] = 6'h0B;
    noise_lut[5] = 6'h0D;
    noise_lut[6] = 6'h10;
    noise_lut[7] = 6'h13;
    noise_lut[8] = 6'h15;
    noise_lut[9] = 6'h18;
    noise_lut[10] = 6'h1B;
    noise_lut[11] = 6'h1D;
    noise_lut[12] = 6'h20;
    noise_lut[13] = 6'h23;
    noise_lut[14] = 6'h25;
    noise_lut[15] = 6'h28;
end

reg [7:0] dmc_lut[0:127];
initial begin
    dmc_lut[0] = 8'h00;
    dmc_lut[1] = 8'h01;
    dmc_lut[2] = 8'h03;
    dmc_lut[3] = 8'h04;
    dmc_lut[4] = 8'h06;
    dmc_lut[5] = 8'h07;
    dmc_lut[6] = 8'h09;
    dmc_lut[7] = 8'h0A;
    dmc_lut[8] = 8'h0C;
    dmc_lut[9] = 8'h0D;
    dmc_lut[10] = 8'h0E;
    dmc_lut[11] = 8'h10;
    dmc_lut[12] = 8'h11;
    dmc_lut[13] = 8'h13;
    dmc_lut[14] = 8'h14;
    dmc_lut[15] = 8'h16;
    dmc_lut[16] = 8'h17;
    dmc_lut[17] = 8'h19;
    dmc_lut[18] = 8'h1A;
    dmc_lut[19] = 8'h1C;
    dmc_lut[20] = 8'h1D;
    dmc_lut[21] = 8'h1E;
    dmc_lut[22] = 8'h20;
    dmc_lut[23] = 8'h21;
    dmc_lut[24] = 8'h23;
    dmc_lut[25] = 8'h24;
    dmc_lut[26] = 8'h26;
    dmc_lut[27] = 8'h27;
    dmc_lut[28] = 8'h29;
    dmc_lut[29] = 8'h2A;
    dmc_lut[30] = 8'h2B;
    dmc_lut[31] = 8'h2D;
    dmc_lut[32] = 8'h2E;
    dmc_lut[33] = 8'h30;
    dmc_lut[34] = 8'h31;
    dmc_lut[35] = 8'h33;
    dmc_lut[36] = 8'h34;
    dmc_lut[37] = 8'h36;
    dmc_lut[38] = 8'h37;
    dmc_lut[39] = 8'h38;
    dmc_lut[40] = 8'h3A;
    dmc_lut[41] = 8'h3B;
    dmc_lut[42] = 8'h3D;
    dmc_lut[43] = 8'h3E;
    dmc_lut[44] = 8'h40;
    dmc_lut[45] = 8'h41;
    dmc_lut[46] = 8'h43;
    dmc_lut[47] = 8'h44;
    dmc_lut[48] = 8'h45;
    dmc_lut[49] = 8'h47;
    dmc_lut[50] = 8'h48;
    dmc_lut[51] = 8'h4A;
    dmc_lut[52] = 8'h4B;
    dmc_lut[53] = 8'h4D;
    dmc_lut[54] = 8'h4E;
    dmc_lut[55] = 8'h50;
    dmc_lut[56] = 8'h51;
    dmc_lut[57] = 8'h53;
    dmc_lut[58] = 8'h54;
    dmc_lut[59] = 8'h55;
    dmc_lut[60] = 8'h57;
    dmc_lut[61] = 8'h58;
    dmc_lut[62] = 8'h5A;
    dmc_lut[63] = 8'h5B;
    dmc_lut[64] = 8'h5D;
    dmc_lut[65] = 8'h5E;
    dmc_lut[66] = 8'h60;
    dmc_lut[67] = 8'h61;
    dmc_lut[68] = 8'h62;
    dmc_lut[69] = 8'h64;
    dmc_lut[70] = 8'h65;
    dmc_lut[71] = 8'h67;
    dmc_lut[72] = 8'h68;
    dmc_lut[73] = 8'h6A;
    dmc_lut[74] = 8'h6B;
    dmc_lut[75] = 8'h6D;
    dmc_lut[76] = 8'h6E;
    dmc_lut[77] = 8'h6F;
    dmc_lut[78] = 8'h71;
    dmc_lut[79] = 8'h72;
    dmc_lut[80] = 8'h74;
    dmc_lut[81] = 8'h75;
    dmc_lut[82] = 8'h77;
    dmc_lut[83] = 8'h78;
    dmc_lut[84] = 8'h7A;
    dmc_lut[85] = 8'h7B;
    dmc_lut[86] = 8'h7C;
    dmc_lut[87] = 8'h7E;
    dmc_lut[88] = 8'h7F;
    dmc_lut[89] = 8'h81;
    dmc_lut[90] = 8'h82;
    dmc_lut[91] = 8'h84;
    dmc_lut[92] = 8'h85;
    dmc_lut[93] = 8'h87;
    dmc_lut[94] = 8'h88;
    dmc_lut[95] = 8'h8A;
    dmc_lut[96] = 8'h8B;
    dmc_lut[97] = 8'h8C;
    dmc_lut[98] = 8'h8E;
    dmc_lut[99] = 8'h8F;
    dmc_lut[100] = 8'h91;
    dmc_lut[101] = 8'h92;
    dmc_lut[102] = 8'h94;
    dmc_lut[103] = 8'h95;
    dmc_lut[104] = 8'h97;
    dmc_lut[105] = 8'h98;
    dmc_lut[106] = 8'h99;
    dmc_lut[107] = 8'h9B;
    dmc_lut[108] = 8'h9C;
    dmc_lut[109] = 8'h9E;
    dmc_lut[110] = 8'h9F;
    dmc_lut[111] = 8'hA1;
    dmc_lut[112] = 8'hA2;
    dmc_lut[113] = 8'hA4;
    dmc_lut[114] = 8'hA5;
    dmc_lut[115] = 8'hA6;
    dmc_lut[116] = 8'hA8;
    dmc_lut[117] = 8'hA9;
    dmc_lut[118] = 8'hAB;
    dmc_lut[119] = 8'hAC;
    dmc_lut[120] = 8'hAE;
    dmc_lut[121] = 8'hAF;
    dmc_lut[122] = 8'hB1;
    dmc_lut[123] = 8'hB2;
    dmc_lut[124] = 8'hB3;
    dmc_lut[125] = 8'hB5;
    dmc_lut[126] = 8'hB6;
    dmc_lut[127] = 8'hB8;
end

reg [15:0] mix_lut[0:511];
initial begin
    mix_lut[0] = 16'h0000;
    mix_lut[1] = 16'h0128;
    mix_lut[2] = 16'h024F;
    mix_lut[3] = 16'h0374;
    mix_lut[4] = 16'h0497;
    mix_lut[5] = 16'h05B8;
    mix_lut[6] = 16'h06D7;
    mix_lut[7] = 16'h07F5;
    mix_lut[8] = 16'h0911;
    mix_lut[9] = 16'h0A2B;
    mix_lut[10] = 16'h0B44;
    mix_lut[11] = 16'h0C5B;
    mix_lut[12] = 16'h0D71;
    mix_lut[13] = 16'h0E84;
    mix_lut[14] = 16'h0F96;
    mix_lut[15] = 16'h10A7;
    mix_lut[16] = 16'h11B6;
    mix_lut[17] = 16'h12C3;
    mix_lut[18] = 16'h13CF;
    mix_lut[19] = 16'h14DA;
    mix_lut[20] = 16'h15E2;
    mix_lut[21] = 16'h16EA;
    mix_lut[22] = 16'h17EF;
    mix_lut[23] = 16'h18F4;
    mix_lut[24] = 16'h19F6;
    mix_lut[25] = 16'h1AF8;
    mix_lut[26] = 16'h1BF7;
    mix_lut[27] = 16'h1CF6;
    mix_lut[28] = 16'h1DF3;
    mix_lut[29] = 16'h1EEE;
    mix_lut[30] = 16'h1FE9;
    mix_lut[31] = 16'h20E1;
    mix_lut[32] = 16'h21D9;
    mix_lut[33] = 16'h22CF;
    mix_lut[34] = 16'h23C3;
    mix_lut[35] = 16'h24B7;
    mix_lut[36] = 16'h25A9;
    mix_lut[37] = 16'h2699;
    mix_lut[38] = 16'h2788;
    mix_lut[39] = 16'h2876;
    mix_lut[40] = 16'h2963;
    mix_lut[41] = 16'h2A4F;
    mix_lut[42] = 16'h2B39;
    mix_lut[43] = 16'h2C22;
    mix_lut[44] = 16'h2D09;
    mix_lut[45] = 16'h2DF0;
    mix_lut[46] = 16'h2ED5;
    mix_lut[47] = 16'h2FB9;
    mix_lut[48] = 16'h309B;
    mix_lut[49] = 16'h317D;
    mix_lut[50] = 16'h325D;
    mix_lut[51] = 16'h333C;
    mix_lut[52] = 16'h341A;
    mix_lut[53] = 16'h34F7;
    mix_lut[54] = 16'h35D3;
    mix_lut[55] = 16'h36AD;
    mix_lut[56] = 16'h3787;
    mix_lut[57] = 16'h385F;
    mix_lut[58] = 16'h3936;
    mix_lut[59] = 16'h3A0C;
    mix_lut[60] = 16'h3AE1;
    mix_lut[61] = 16'h3BB5;
    mix_lut[62] = 16'h3C87;
    mix_lut[63] = 16'h3D59;
    mix_lut[64] = 16'h3E29;
    mix_lut[65] = 16'h3EF9;
    mix_lut[66] = 16'h3FC7;
    mix_lut[67] = 16'h4095;
    mix_lut[68] = 16'h4161;
    mix_lut[69] = 16'h422C;
    mix_lut[70] = 16'h42F7;
    mix_lut[71] = 16'h43C0;
    mix_lut[72] = 16'h4488;
    mix_lut[73] = 16'h4550;
    mix_lut[74] = 16'h4616;
    mix_lut[75] = 16'h46DB;
    mix_lut[76] = 16'h47A0;
    mix_lut[77] = 16'h4863;
    mix_lut[78] = 16'h4925;
    mix_lut[79] = 16'h49E7;
    mix_lut[80] = 16'h4AA7;
    mix_lut[81] = 16'h4B67;
    mix_lut[82] = 16'h4C25;
    mix_lut[83] = 16'h4CE3;
    mix_lut[84] = 16'h4DA0;
    mix_lut[85] = 16'h4E5C;
    mix_lut[86] = 16'h4F17;
    mix_lut[87] = 16'h4FD1;
    mix_lut[88] = 16'h508A;
    mix_lut[89] = 16'h5142;
    mix_lut[90] = 16'h51F9;
    mix_lut[91] = 16'h52B0;
    mix_lut[92] = 16'h5365;
    mix_lut[93] = 16'h541A;
    mix_lut[94] = 16'h54CE;
    mix_lut[95] = 16'h5581;
    mix_lut[96] = 16'h5633;
    mix_lut[97] = 16'h56E5;
    mix_lut[98] = 16'h5795;
    mix_lut[99] = 16'h5845;
    mix_lut[100] = 16'h58F4;
    mix_lut[101] = 16'h59A2;
    mix_lut[102] = 16'h5A4F;
    mix_lut[103] = 16'h5AFC;
    mix_lut[104] = 16'h5BA7;
    mix_lut[105] = 16'h5C52;
    mix_lut[106] = 16'h5CFC;
    mix_lut[107] = 16'h5DA5;
    mix_lut[108] = 16'h5E4E;
    mix_lut[109] = 16'h5EF6;
    mix_lut[110] = 16'h5F9D;
    mix_lut[111] = 16'h6043;
    mix_lut[112] = 16'h60E8;
    mix_lut[113] = 16'h618D;
    mix_lut[114] = 16'h6231;
    mix_lut[115] = 16'h62D4;
    mix_lut[116] = 16'h6377;
    mix_lut[117] = 16'h6418;
    mix_lut[118] = 16'h64B9;
    mix_lut[119] = 16'h655A;
    mix_lut[120] = 16'h65F9;
    mix_lut[121] = 16'h6698;
    mix_lut[122] = 16'h6736;
    mix_lut[123] = 16'h67D4;
    mix_lut[124] = 16'h6871;
    mix_lut[125] = 16'h690D;
    mix_lut[126] = 16'h69A8;
    mix_lut[127] = 16'h6A43;
    mix_lut[128] = 16'h6ADD;
    mix_lut[129] = 16'h6B76;
    mix_lut[130] = 16'h6C0F;
    mix_lut[131] = 16'h6CA7;
    mix_lut[132] = 16'h6D3E;
    mix_lut[133] = 16'h6DD5;
    mix_lut[134] = 16'h6E6B;
    mix_lut[135] = 16'h6F00;
    mix_lut[136] = 16'h6F95;
    mix_lut[137] = 16'h7029;
    mix_lut[138] = 16'h70BD;
    mix_lut[139] = 16'h7150;
    mix_lut[140] = 16'h71E2;
    mix_lut[141] = 16'h7273;
    mix_lut[142] = 16'h7304;
    mix_lut[143] = 16'h7395;
    mix_lut[144] = 16'h7424;
    mix_lut[145] = 16'h74B4;
    mix_lut[146] = 16'h7542;
    mix_lut[147] = 16'h75D0;
    mix_lut[148] = 16'h765D;
    mix_lut[149] = 16'h76EA;
    mix_lut[150] = 16'h7776;
    mix_lut[151] = 16'h7802;
    mix_lut[152] = 16'h788D;
    mix_lut[153] = 16'h7917;
    mix_lut[154] = 16'h79A1;
    mix_lut[155] = 16'h7A2A;
    mix_lut[156] = 16'h7AB3;
    mix_lut[157] = 16'h7B3B;
    mix_lut[158] = 16'h7BC3;
    mix_lut[159] = 16'h7C4A;
    mix_lut[160] = 16'h7CD0;
    mix_lut[161] = 16'h7D56;
    mix_lut[162] = 16'h7DDB;
    mix_lut[163] = 16'h7E60;
    mix_lut[164] = 16'h7EE4;
    mix_lut[165] = 16'h7F68;
    mix_lut[166] = 16'h7FEB;
    mix_lut[167] = 16'h806E;
    mix_lut[168] = 16'h80F0;
    mix_lut[169] = 16'h8172;
    mix_lut[170] = 16'h81F3;
    mix_lut[171] = 16'h8274;
    mix_lut[172] = 16'h82F4;
    mix_lut[173] = 16'h8373;
    mix_lut[174] = 16'h83F2;
    mix_lut[175] = 16'h8471;
    mix_lut[176] = 16'h84EF;
    mix_lut[177] = 16'h856C;
    mix_lut[178] = 16'h85E9;
    mix_lut[179] = 16'h8666;
    mix_lut[180] = 16'h86E2;
    mix_lut[181] = 16'h875E;
    mix_lut[182] = 16'h87D9;
    mix_lut[183] = 16'h8853;
    mix_lut[184] = 16'h88CD;
    mix_lut[185] = 16'h8947;
    mix_lut[186] = 16'h89C0;
    mix_lut[187] = 16'h8A39;
    mix_lut[188] = 16'h8AB1;
    mix_lut[189] = 16'h8B29;
    mix_lut[190] = 16'h8BA0;
    mix_lut[191] = 16'h8C17;
    mix_lut[192] = 16'h8C8E;
    mix_lut[193] = 16'h8D03;
    mix_lut[194] = 16'h8D79;
    mix_lut[195] = 16'h8DEE;
    mix_lut[196] = 16'h8E63;
    mix_lut[197] = 16'h8ED7;
    mix_lut[198] = 16'h8F4A;
    mix_lut[199] = 16'h8FBE;
    mix_lut[200] = 16'h9030;
    mix_lut[201] = 16'h90A3;
    mix_lut[202] = 16'h9115;
    mix_lut[203] = 16'h9186;
    mix_lut[204] = 16'h91F7;
    mix_lut[205] = 16'h9268;
    mix_lut[206] = 16'h92D8;
    mix_lut[207] = 16'h9348;
    mix_lut[208] = 16'h93B8;
    mix_lut[209] = 16'h9427;
    mix_lut[210] = 16'h9495;
    mix_lut[211] = 16'h9503;
    mix_lut[212] = 16'h9571;
    mix_lut[213] = 16'h95DF;
    mix_lut[214] = 16'h964C;
    mix_lut[215] = 16'h96B8;
    mix_lut[216] = 16'h9724;
    mix_lut[217] = 16'h9790;
    mix_lut[218] = 16'h97FB;
    mix_lut[219] = 16'h9866;
    mix_lut[220] = 16'h98D1;
    mix_lut[221] = 16'h993B;
    mix_lut[222] = 16'h99A5;
    mix_lut[223] = 16'h9A0E;
    mix_lut[224] = 16'h9A77;
    mix_lut[225] = 16'h9AE0;
    mix_lut[226] = 16'h9B48;
    mix_lut[227] = 16'h9BB0;
    mix_lut[228] = 16'h9C18;
    mix_lut[229] = 16'h9C7F;
    mix_lut[230] = 16'h9CE6;
    mix_lut[231] = 16'h9D4C;
    mix_lut[232] = 16'h9DB2;
    mix_lut[233] = 16'h9E18;
    mix_lut[234] = 16'h9E7D;
    mix_lut[235] = 16'h9EE2;
    mix_lut[236] = 16'h9F47;
    mix_lut[237] = 16'h9FAB;
    mix_lut[238] = 16'hA00F;
    mix_lut[239] = 16'hA073;
    mix_lut[240] = 16'hA0D6;
    mix_lut[241] = 16'hA139;
    mix_lut[242] = 16'hA19B;
    mix_lut[243] = 16'hA1FD;
    mix_lut[244] = 16'hA25F;
    mix_lut[245] = 16'hA2C1;
    mix_lut[246] = 16'hA322;
    mix_lut[247] = 16'hA383;
    mix_lut[248] = 16'hA3E3;
    mix_lut[249] = 16'hA443;
    mix_lut[250] = 16'hA4A3;
    mix_lut[251] = 16'hA502;
    mix_lut[252] = 16'hA562;
    mix_lut[253] = 16'hA5C0;
    mix_lut[254] = 16'hA61F;
    mix_lut[255] = 16'hA67D;
    mix_lut[256] = 16'hA6DB;
    mix_lut[257] = 16'hA738;
    mix_lut[258] = 16'hA796;
    mix_lut[259] = 16'hA7F2;
    mix_lut[260] = 16'hA84F;
    mix_lut[261] = 16'hA8AB;
    mix_lut[262] = 16'hA907;
    mix_lut[263] = 16'hA963;
    mix_lut[264] = 16'hA9BE;
    mix_lut[265] = 16'hAA19;
    mix_lut[266] = 16'hAA74;
    mix_lut[267] = 16'hAACE;
    mix_lut[268] = 16'hAB28;
    mix_lut[269] = 16'hAB82;
    mix_lut[270] = 16'hABDB;
    mix_lut[271] = 16'hAC35;
    mix_lut[272] = 16'hAC8E;
    mix_lut[273] = 16'hACE6;
    mix_lut[274] = 16'hAD3E;
    mix_lut[275] = 16'hAD96;
    mix_lut[276] = 16'hADEE;
    mix_lut[277] = 16'hAE46;
    mix_lut[278] = 16'hAE9D;
    mix_lut[279] = 16'hAEF4;
    mix_lut[280] = 16'hAF4A;
    mix_lut[281] = 16'hAFA0;
    mix_lut[282] = 16'hAFF6;
    mix_lut[283] = 16'hB04C;
    mix_lut[284] = 16'hB0A2;
    mix_lut[285] = 16'hB0A2;
    mix_lut[286] = 16'hB0A2;
    mix_lut[287] = 16'hB0A2;
    mix_lut[288] = 16'hB0A2;
    mix_lut[289] = 16'h0000;
    mix_lut[290] = 16'h0000;
    mix_lut[291] = 16'h0000;
    mix_lut[292] = 16'h0000;
    mix_lut[293] = 16'h0000;
    mix_lut[294] = 16'h0000;
    mix_lut[295] = 16'h0000;
    mix_lut[296] = 16'h0000;
    mix_lut[297] = 16'h0000;
    mix_lut[298] = 16'h0000;
    mix_lut[299] = 16'h0000;
    mix_lut[300] = 16'h0000;
    mix_lut[301] = 16'h0000;
    mix_lut[302] = 16'h0000;
    mix_lut[303] = 16'h0000;
    mix_lut[304] = 16'h0000;
    mix_lut[305] = 16'h0000;
    mix_lut[306] = 16'h0000;
    mix_lut[307] = 16'h0000;
    mix_lut[308] = 16'h0000;
    mix_lut[309] = 16'h0000;
    mix_lut[310] = 16'h0000;
    mix_lut[311] = 16'h0000;
    mix_lut[312] = 16'h0000;
    mix_lut[313] = 16'h0000;
    mix_lut[314] = 16'h0000;
    mix_lut[315] = 16'h0000;
    mix_lut[316] = 16'h0000;
    mix_lut[317] = 16'h0000;
    mix_lut[318] = 16'h0000;
    mix_lut[319] = 16'h0000;
    mix_lut[320] = 16'h0000;
    mix_lut[321] = 16'h0000;
    mix_lut[322] = 16'h0000;
    mix_lut[323] = 16'h0000;
    mix_lut[324] = 16'h0000;
    mix_lut[325] = 16'h0000;
    mix_lut[326] = 16'h0000;
    mix_lut[327] = 16'h0000;
    mix_lut[328] = 16'h0000;
    mix_lut[329] = 16'h0000;
    mix_lut[330] = 16'h0000;
    mix_lut[331] = 16'h0000;
    mix_lut[332] = 16'h0000;
    mix_lut[333] = 16'h0000;
    mix_lut[334] = 16'h0000;
    mix_lut[335] = 16'h0000;
    mix_lut[336] = 16'h0000;
    mix_lut[337] = 16'h0000;
    mix_lut[338] = 16'h0000;
    mix_lut[339] = 16'h0000;
    mix_lut[340] = 16'h0000;
    mix_lut[341] = 16'h0000;
    mix_lut[342] = 16'h0000;
    mix_lut[343] = 16'h0000;
    mix_lut[344] = 16'h0000;
    mix_lut[345] = 16'h0000;
    mix_lut[346] = 16'h0000;
    mix_lut[347] = 16'h0000;
    mix_lut[348] = 16'h0000;
    mix_lut[349] = 16'h0000;
    mix_lut[350] = 16'h0000;
    mix_lut[351] = 16'h0000;
    mix_lut[352] = 16'h0000;
    mix_lut[353] = 16'h0000;
    mix_lut[354] = 16'h0000;
    mix_lut[355] = 16'h0000;
    mix_lut[356] = 16'h0000;
    mix_lut[357] = 16'h0000;
    mix_lut[358] = 16'h0000;
    mix_lut[359] = 16'h0000;
    mix_lut[360] = 16'h0000;
    mix_lut[361] = 16'h0000;
    mix_lut[362] = 16'h0000;
    mix_lut[363] = 16'h0000;
    mix_lut[364] = 16'h0000;
    mix_lut[365] = 16'h0000;
    mix_lut[366] = 16'h0000;
    mix_lut[367] = 16'h0000;
    mix_lut[368] = 16'h0000;
    mix_lut[369] = 16'h0000;
    mix_lut[370] = 16'h0000;
    mix_lut[371] = 16'h0000;
    mix_lut[372] = 16'h0000;
    mix_lut[373] = 16'h0000;
    mix_lut[374] = 16'h0000;
    mix_lut[375] = 16'h0000;
    mix_lut[376] = 16'h0000;
    mix_lut[377] = 16'h0000;
    mix_lut[378] = 16'h0000;
    mix_lut[379] = 16'h0000;
    mix_lut[380] = 16'h0000;
    mix_lut[381] = 16'h0000;
    mix_lut[382] = 16'h0000;
    mix_lut[383] = 16'h0000;
    mix_lut[384] = 16'h0000;
    mix_lut[385] = 16'h0000;
    mix_lut[386] = 16'h0000;
    mix_lut[387] = 16'h0000;
    mix_lut[388] = 16'h0000;
    mix_lut[389] = 16'h0000;
    mix_lut[390] = 16'h0000;
    mix_lut[391] = 16'h0000;
    mix_lut[392] = 16'h0000;
    mix_lut[393] = 16'h0000;
    mix_lut[394] = 16'h0000;
    mix_lut[395] = 16'h0000;
    mix_lut[396] = 16'h0000;
    mix_lut[397] = 16'h0000;
    mix_lut[398] = 16'h0000;
    mix_lut[399] = 16'h0000;
    mix_lut[400] = 16'h0000;
    mix_lut[401] = 16'h0000;
    mix_lut[402] = 16'h0000;
    mix_lut[403] = 16'h0000;
    mix_lut[404] = 16'h0000;
    mix_lut[405] = 16'h0000;
    mix_lut[406] = 16'h0000;
    mix_lut[407] = 16'h0000;
    mix_lut[408] = 16'h0000;
    mix_lut[409] = 16'h0000;
    mix_lut[410] = 16'h0000;
    mix_lut[411] = 16'h0000;
    mix_lut[412] = 16'h0000;
    mix_lut[413] = 16'h0000;
    mix_lut[414] = 16'h0000;
    mix_lut[415] = 16'h0000;
    mix_lut[416] = 16'h0000;
    mix_lut[417] = 16'h0000;
    mix_lut[418] = 16'h0000;
    mix_lut[419] = 16'h0000;
    mix_lut[420] = 16'h0000;
    mix_lut[421] = 16'h0000;
    mix_lut[422] = 16'h0000;
    mix_lut[423] = 16'h0000;
    mix_lut[424] = 16'h0000;
    mix_lut[425] = 16'h0000;
    mix_lut[426] = 16'h0000;
    mix_lut[427] = 16'h0000;
    mix_lut[428] = 16'h0000;
    mix_lut[429] = 16'h0000;
    mix_lut[430] = 16'h0000;
    mix_lut[431] = 16'h0000;
    mix_lut[432] = 16'h0000;
    mix_lut[433] = 16'h0000;
    mix_lut[434] = 16'h0000;
    mix_lut[435] = 16'h0000;
    mix_lut[436] = 16'h0000;
    mix_lut[437] = 16'h0000;
    mix_lut[438] = 16'h0000;
    mix_lut[439] = 16'h0000;
    mix_lut[440] = 16'h0000;
    mix_lut[441] = 16'h0000;
    mix_lut[442] = 16'h0000;
    mix_lut[443] = 16'h0000;
    mix_lut[444] = 16'h0000;
    mix_lut[445] = 16'h0000;
    mix_lut[446] = 16'h0000;
    mix_lut[447] = 16'h0000;
    mix_lut[448] = 16'h0000;
    mix_lut[449] = 16'h0000;
    mix_lut[450] = 16'h0000;
    mix_lut[451] = 16'h0000;
    mix_lut[452] = 16'h0000;
    mix_lut[453] = 16'h0000;
    mix_lut[454] = 16'h0000;
    mix_lut[455] = 16'h0000;
    mix_lut[456] = 16'h0000;
    mix_lut[457] = 16'h0000;
    mix_lut[458] = 16'h0000;
    mix_lut[459] = 16'h0000;
    mix_lut[460] = 16'h0000;
    mix_lut[461] = 16'h0000;
    mix_lut[462] = 16'h0000;
    mix_lut[463] = 16'h0000;
    mix_lut[464] = 16'h0000;
    mix_lut[465] = 16'h0000;
    mix_lut[466] = 16'h0000;
    mix_lut[467] = 16'h0000;
    mix_lut[468] = 16'h0000;
    mix_lut[469] = 16'h0000;
    mix_lut[470] = 16'h0000;
    mix_lut[471] = 16'h0000;
    mix_lut[472] = 16'h0000;
    mix_lut[473] = 16'h0000;
    mix_lut[474] = 16'h0000;
    mix_lut[475] = 16'h0000;
    mix_lut[476] = 16'h0000;
    mix_lut[477] = 16'h0000;
    mix_lut[478] = 16'h0000;
    mix_lut[479] = 16'h0000;
    mix_lut[480] = 16'h0000;
    mix_lut[481] = 16'h0000;
    mix_lut[482] = 16'h0000;
    mix_lut[483] = 16'h0000;
    mix_lut[484] = 16'h0000;
    mix_lut[485] = 16'h0000;
    mix_lut[486] = 16'h0000;
    mix_lut[487] = 16'h0000;
    mix_lut[488] = 16'h0000;
    mix_lut[489] = 16'h0000;
    mix_lut[490] = 16'h0000;
    mix_lut[491] = 16'h0000;
    mix_lut[492] = 16'h0000;
    mix_lut[493] = 16'h0000;
    mix_lut[494] = 16'h0000;
    mix_lut[495] = 16'h0000;
    mix_lut[496] = 16'h0000;
    mix_lut[497] = 16'h0000;
    mix_lut[498] = 16'h0000;
    mix_lut[499] = 16'h0000;
    mix_lut[500] = 16'h0000;
    mix_lut[501] = 16'h0000;
    mix_lut[502] = 16'h0000;
    mix_lut[503] = 16'h0000;
    mix_lut[504] = 16'h0000;
    mix_lut[505] = 16'h0000;
    mix_lut[506] = 16'h0000;
    mix_lut[507] = 16'h0000;
    mix_lut[508] = 16'h0000;
    mix_lut[509] = 16'h0000;
    mix_lut[510] = 16'h0000;
    mix_lut[511] = 16'h0000;
end

// Square waves
wire [4:0] squares = square1 + square2;
wire [15:0] ch1 = pulse_lut[squares];

// Normal mixer
wire [8:0] mix_normal = 9'(tri_lut[triangle]) + 9'(noise_lut[noise]) + 9'(dmc_lut[dmc]);
wire [15:0] ch2 = mix_lut[mix_normal];
wire [15:0] sample_normal = ch1 + ch2;

// Combinatorial linear mixer + enhanced triangle wave
wire [15:0] tri_enhanced_out = tri_lut_enhanced_5b[apu_triangle_enhanced];
wire [15:0] noise_out = 8'd0 + noise_lut[noise]; // Widen to 16 bits for addition
wire [15:0] dmc_out = 8'd0 + dmc_lut[dmc];     // Widen to 16 bits for addition

// The new linear mixer is a direct combinatorial sum
wire [15:0] mixed_channels_enhanced_linear = tri_enhanced_out + noise_out + dmc_out;
wire [15:0] ch2_enhanced_linear = mixed_channels_enhanced_linear;

// Re-assign sample_linear to use the new linear mixer result
wire [15:0] sample_linear = ch1 + ch2_enhanced_linear;

// Normal mixer + enhanced triangle wave
wire [8:0] mix_enhanced_normal_lut = 9'((tri_lut_enhanced_5b[apu_triangle_enhanced])) + 9'(noise_lut[noise]) + 9'(dmc_lut[dmc]);
wire [15:0] ch2_mix_normal_enhanced_tri = mix_lut[mix_enhanced_normal_lut];
wire [15:0] sample_mix_normal_enhanced_tri = ch1 + ch2_mix_normal_enhanced_tri;

assign sample = !apu_enhanced_ce ? sample_normal : 
                !apu_mapper_saturates ? sample_linear :
                sample_mix_normal_enhanced_tri;

endmodule
