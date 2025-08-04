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

// Note: The original non-linear pulse_lut has been removed.
// Square waves are now mixed with a simple linear sum.
// An input of '0' results in an 'OFF' state for the channel.

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
    // ... (mix_lut values remain unchanged)
    mix_lut[511] = 16'h0000;
end

// Square waves: A simple linear sum of the two channels.
wire [15:0] ch1_output = {12'b0, square1} + {12'b0, square2};

// Normal mixer path (now combinatorial linear)
// Widen smaller channel outputs to 16 bits for addition
wire [15:0] tri_normal_output_scaled = {10'b0, tri_lut[triangle]};
wire [15:0] noise_output_scaled = {10'b0, noise_lut[noise]};
wire [15:0] dmc_output_scaled = {8'b0, dmc_lut[dmc]};

// Sum all channels for the normal linear mixer output
wire [15:0] sample_normal_linear = ch1_output + tri_normal_output_scaled + noise_output_scaled + dmc_output_scaled;

// Enhanced mixer path (combinatorial linear with enhanced triangle)
// Use the enhanced triangle lookup table
wire [15:0] tri_enhanced_output_scaled = {10'b0, tri_lut_enhanced_5b[apu_triangle_enhanced]};

// Sum all channels for the enhanced linear mixer output
wire [15:0] sample_enhanced_linear = ch1_output + tri_enhanced_output_scaled + noise_output_scaled + dmc_output_scaled;

// Final sample selection based on apu_enhanced_ce
// The apu_mapper_saturates signal is no longer used in this simplified linear mixing scheme.
assign sample = apu_enhanced_ce ? sample_enhanced_linear : sample_normal_linear;
endmodule
