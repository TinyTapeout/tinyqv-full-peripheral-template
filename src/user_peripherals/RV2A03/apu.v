// Rewritten 6/4/2020 by Kitrinx
// This code is GPLv3.
`define COCOTB_TESTING

module LenCounterUnit (
        clk,
        reset,
        cold_reset,
        len_clk,
        aclk1,
        aclk1_d,
        load_value,
        halt_in,
        addr,
        is_triangle,
        write,
        enabled,
        lc_on
);
        input wire clk;
        input wire reset;
        input wire cold_reset;
        input wire len_clk;
        input wire aclk1;
        input wire aclk1_d;
        input wire [7:0] load_value;
        input wire halt_in;
        input wire addr;
        input wire is_triangle;
        input wire write;
        input wire enabled;
        output reg lc_on;
        reg lc_on_1;
        reg clear_next;
        reg [7:0] len_counter_int;
        reg halt;
        wire halt_next;
        reg [7:0] len_counter_next;
        always @(posedge clk) begin : lenunit
                if (aclk1_d) begin
                        if (~enabled)
                                lc_on <= 0;
                end
                if (aclk1) begin
                        lc_on_1 <= lc_on;
                        len_counter_next <= (halt || ~|len_counter_int ? len_counter_int : len_counter_int - 1'd1);
                        clear_next <= ~halt && ~|len_counter_int;
                end
                if (write) begin
                        if (~addr)
                                halt <= halt_in;
                        else begin
                                lc_on <= 1;
                                len_counter_int <= load_value;
                        end
                end
                if (len_clk && lc_on_1) begin
                        len_counter_int <= (halt ? len_counter_int : len_counter_next);
                        if (clear_next)
                                lc_on <= 0;
                end
                if (reset) begin
                        if (~is_triangle || cold_reset)
                                halt <= 0;
                        lc_on <= 0;
                        len_counter_int <= 0;
                        len_counter_next <= 0;
                end
        end
endmodule
module EnvelopeUnit (
        clk,
        reset,
        env_clk,
        din,
        addr,
        write,
        envelope
);
        input wire clk;
        input wire reset;
        input wire env_clk;
        input wire [5:0] din;
        input wire addr;
        input wire write;
        output wire [3:0] envelope;
        reg [3:0] env_count;
        reg [3:0] env_vol;
        reg env_disabled;
        assign envelope = (env_disabled ? env_vol : env_count);
        always @(posedge clk) begin : envunit
                reg [3:0] env_div;
                reg env_reload;
                reg env_loop;
                reg env_reset;
                if (env_clk) begin
                        if (~env_reload) begin
                                env_div <= env_div - 1'd1;
                                if (~|env_div) begin
                                        env_div <= env_vol;
                                        if (|env_count || env_loop)
                                                env_count <= env_count - 1'd1;
                                end
                        end
                        else begin
                                env_div <= env_vol;
                                env_count <= 4'hf;
                                env_reload <= 1'b0;
                        end
                end
                if (write) begin
                        if (~addr)
                                {env_loop, env_disabled, env_vol} <= din;
                        if (addr)
                                env_reload <= 1;
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
        MMC5,
        clk,
        ce,
        aclk1,
        aclk1_d,
        reset,
        cold_reset,
        allow_us,
        sq2,
        Addr,
        DIN,
        write,
        lc_load,
        LenCtr_Clock,
        Env_Clock,
        odd_or_even,
        Enabled,
        Sample,
        IsNonZero
);
        reg _sv2v_0;
        input wire MMC5;
        input wire clk;
        input wire ce;
        input wire aclk1;
        input wire aclk1_d;
        input wire reset;
        input wire cold_reset;
        input wire allow_us;
        input wire sq2;
        input wire [1:0] Addr;
        input wire [7:0] DIN;
        input wire write;
        input wire [7:0] lc_load;
        input wire LenCtr_Clock;
        input wire Env_Clock;
        input wire odd_or_even;
        input wire Enabled;
        output wire [3:0] Sample;
        output wire IsNonZero;
        reg [1:0] Duty;
        reg SweepEnable;
        reg SweepNegate;
        reg SweepReset;
        reg [2:0] SweepPeriod;
        reg [2:0] SweepDivider;
        reg [2:0] SweepShift;
        reg [10:0] Period;
        reg [11:0] TimerCtr;
        reg [2:0] SeqPos;
        wire [10:0] ShiftedPeriod;
        wire [10:0] PeriodRhs;
        wire [11:0] NewSweepPeriod;
        wire ValidFreq;
        wire subunit_write;
        wire [3:0] Envelope;
        wire lc;
        wire DutyEnabledUsed;
        reg DutyEnabled;
        assign DutyEnabledUsed = MMC5 ^ DutyEnabled;
        assign ShiftedPeriod = Period >> SweepShift;
        assign PeriodRhs = (SweepNegate ? ~ShiftedPeriod + {10'b0000000000, sq2} : ShiftedPeriod);
        assign NewSweepPeriod = Period + PeriodRhs;
        assign subunit_write = ((Addr == 0) || (Addr == 3)) & write;
        assign IsNonZero = lc;
        assign ValidFreq = (MMC5 && allow_us) || (|Period[10:3] && (SweepNegate || ~NewSweepPeriod[11]));
        assign Sample = ((~lc | ~ValidFreq) | ~DutyEnabledUsed ? 4'd0 : Envelope);
        LenCounterUnit LenSq(
                .clk(clk),
                .reset(reset),
                .cold_reset(cold_reset),
                .aclk1(aclk1),
                .aclk1_d(aclk1_d),
                .len_clk((MMC5 ? Env_Clock : LenCtr_Clock)),
                .load_value(lc_load),
                .halt_in(DIN[5]),
                .addr(Addr[0]),
                .is_triangle(1'b0),
                .write(subunit_write),
                .enabled(Enabled),
                .lc_on(lc)
        );
        EnvelopeUnit EnvSq(
                .clk(clk),
                .reset(reset),
                .env_clk(Env_Clock),
                .din(DIN[5:0]),
                .addr(Addr[0]),
                .write(subunit_write),
                .envelope(Envelope)
        );
        always @(*) begin
                if (_sv2v_0)
                        ;
                case (Duty)
                        0: DutyEnabled = SeqPos == 7;
                        1: DutyEnabled = SeqPos >= 6;
                        2: DutyEnabled = SeqPos >= 4;
                        3: DutyEnabled = SeqPos < 6;
                endcase
        end
        always @(posedge clk) begin : sqblock
                if (aclk1_d) begin
                        if (TimerCtr == 0) begin
                                TimerCtr <= {1'b0, Period};
                                SeqPos <= SeqPos - 1'd1;
                        end
                        else
                                TimerCtr <= TimerCtr - 1'd1;
                end
                if (LenCtr_Clock) begin
                        if (SweepDivider == 0) begin
                                SweepDivider <= SweepPeriod;
                                if ((SweepEnable && (SweepShift != 0)) && ValidFreq)
                                        Period <= NewSweepPeriod[10:0];
                        end
                        else
                                SweepDivider <= SweepDivider - 1'd1;
                        if (SweepReset)
                                SweepDivider <= SweepPeriod;
                        SweepReset <= 0;
                end
                if (write)
                        case (Addr)
                                0: Duty <= DIN[7:6];
                                1:
                                        if (~MMC5) begin
                                                {SweepEnable, SweepPeriod, SweepNegate, SweepShift} <= DIN;
                                                SweepReset <= 1;
                                        end
                                2: Period[7:0] <= DIN;
                                3: begin
                                        Period[10:8] <= DIN[2:0];
                                        SeqPos <= 0;
                                end
                        endcase
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
        initial _sv2v_0 = 0;
endmodule
module TriangleChan (
        clk,
        phi1,
        aclk1,
        aclk1_d,
        reset,
        cold_reset,
        allow_us,
        Addr,
        DIN,
        write,
        lc_load,
        LenCtr_Clock,
        LinCtr_Clock,
        Enabled,
        Sample,
        IsNonZero
);
        input wire clk;
        input wire phi1;
        input wire aclk1;
        input wire aclk1_d;
        input wire reset;
        input wire cold_reset;
        input wire allow_us;
        input wire [1:0] Addr;
        input wire [7:0] DIN;
        input wire write;
        input wire [7:0] lc_load;
        input wire LenCtr_Clock;
        input wire LinCtr_Clock;
        input wire Enabled;
        output wire [3:0] Sample;
        output wire IsNonZero;
        reg [10:0] Period;
        reg [10:0] applied_period;
        reg [10:0] TimerCtr;
        initial Period = 'h3e;
        reg [4:0] SeqPos;
        reg [6:0] LinCtrPeriod;
        reg [6:0] LinCtrPeriod_1;
        reg [6:0] LinCtr;
        reg LinCtrl;
        reg line_reload;
        wire LinCtrZero;
        wire lc;
        wire LenCtrZero;
        wire subunit_write;
        reg [3:0] sample_latch;
        assign LinCtrZero = ~|LinCtr;
        assign IsNonZero = lc;
        assign subunit_write = ((Addr == 0) || (Addr == 3)) & write;
        assign Sample = ((applied_period > 1) || allow_us ? SeqPos[3:0] ^ {4 {~SeqPos[4]}} : sample_latch);
        LenCounterUnit LenTri(
                .clk(clk),
                .reset(reset),
                .cold_reset(cold_reset),
                .aclk1(aclk1),
                .aclk1_d(aclk1_d),
                .len_clk(LenCtr_Clock),
                .load_value(lc_load),
                .halt_in(DIN[7]),
                .addr(Addr[0]),
                .is_triangle(1'b1),
                .write(subunit_write),
                .enabled(Enabled),
                .lc_on(lc)
        );
        always @(posedge clk) begin
                if (phi1) begin
                        if (TimerCtr == 0) begin
                                TimerCtr <= Period;
                                applied_period <= Period;
                                if (IsNonZero & ~LinCtrZero)
                                        SeqPos <= SeqPos + 1'd1;
                        end
                        else
                                TimerCtr <= TimerCtr - 1'd1;
                end
                if (aclk1)
                        LinCtrPeriod_1 <= LinCtrPeriod;
                if (LinCtr_Clock) begin
                        if (line_reload)
                                LinCtr <= LinCtrPeriod_1;
                        else if (!LinCtrZero)
                                LinCtr <= LinCtr - 1'd1;
                        if (!LinCtrl)
                                line_reload <= 0;
                end
                if (write)
                        case (Addr)
                                0: begin
                                        LinCtrl <= DIN[7];
                                        LinCtrPeriod <= DIN[6:0];
                                end
                                2: Period[7:0] <= DIN;
                                3: begin
                                        Period[10:8] <= DIN[2:0];
                                        line_reload <= 1;
                                end
                        endcase
                if (reset) begin
                        sample_latch <= 4'hf;
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
module TriangleChan_enhanced_6b (
        clk,
        phi1,
        aclk1,
        aclk1_d,
        reset,
        cold_reset,
        allow_us,
        Addr,
        DIN,
        write,
        lc_load,
        LenCtr_Clock,
        LinCtr_Clock,
        Enabled,
        Sample,
        IsNonZero
);
        input wire clk;
        input wire phi1;
        input wire aclk1;
        input wire aclk1_d;
        input wire reset;
        input wire cold_reset;
        input wire allow_us;
        input wire [1:0] Addr;
        input wire [7:0] DIN;
        input wire write;
        input wire [7:0] lc_load;
        input wire LenCtr_Clock;
        input wire LinCtr_Clock;
        input wire Enabled;
        output wire [5:0] Sample;
        output wire IsNonZero;
        reg [10:0] Period;
        reg [10:0] applied_period;
        reg [10:0] TimerCtr;
        reg [5:0] SeqPos;
        reg [6:0] LinCtrPeriod;
        reg [6:0] LinCtrPeriod_1;
        reg [6:0] LinCtr;
        reg LinCtrl;
        reg line_reload;
        wire LinCtrZero;
        wire lc;
        wire LenCtrZero;
        wire subunit_write;
        reg [5:0] sample_latch;
        assign LinCtrZero = ~|LinCtr;
        assign IsNonZero = lc;
        assign subunit_write = ((Addr == 0) || (Addr == 3)) & write;
        assign Sample = ((applied_period > 1) || allow_us ? SeqPos ^ {6 {~SeqPos[5]}} : sample_latch);
        LenCounterUnit LenTri(
                .clk(clk),
                .reset(reset),
                .cold_reset(cold_reset),
                .aclk1(aclk1),
                .aclk1_d(aclk1_d),
                .len_clk(LenCtr_Clock),
                .load_value(lc_load),
                .halt_in(DIN[7]),
                .addr(Addr[0]),
                .is_triangle(1'b1),
                .write(subunit_write),
                .enabled(Enabled),
                .lc_on(lc)
        );
        always @(posedge clk) begin
                if (phi1) begin
                        if (TimerCtr == 0) begin
                                TimerCtr <= Period;
                                applied_period <= Period;
                                if (IsNonZero & ~LinCtrZero)
                                        SeqPos <= SeqPos + 1'd1;
                        end
                        else
                                TimerCtr <= TimerCtr - 1'd1;
                end
                if (aclk1)
                        LinCtrPeriod_1 <= LinCtrPeriod;
                if (LinCtr_Clock) begin
                        if (line_reload)
                                LinCtr <= LinCtrPeriod_1;
                        else if (!LinCtrZero)
                                LinCtr <= LinCtr - 1'd1;
                        if (!LinCtrl)
                                line_reload <= 0;
                end
                if (write)
                        case (Addr)
                                0: begin
                                        LinCtrl <= DIN[7];
                                        LinCtrPeriod <= DIN[6:0];
                                end
                                2: Period[7:0] <= DIN;
                                3: begin
                                        Period[10:8] <= DIN[2:0];
                                        line_reload <= 1;
                                end
                        endcase
                if (reset) begin
                        sample_latch <= 6'h3f;
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
module NoiseChan (
        clk,
        ce,
        aclk1,
        aclk1_d,
        reset,
        cold_reset,
        Addr,
        DIN,
        write,
        lc_load,
        LenCtr_Clock,
        Env_Clock,
        Enabled,
        Sample,
        IsNonZero
);
        input wire clk;
        input wire ce;
        input wire aclk1;
        input wire aclk1_d;
        input wire reset;
        input wire cold_reset;
        input wire [1:0] Addr;
        input wire [7:0] DIN;
        input wire write;
        input wire [7:0] lc_load;
        input wire LenCtr_Clock;
        input wire Env_Clock;
        input wire Enabled;
        output wire [3:0] Sample;
        output wire IsNonZero;
        reg ShortMode;
        reg [14:0] Shift;
        reg [3:0] Period;
        wire [11:0] NoisePeriod;
        wire [11:0] TimerCtr;
        wire [3:0] Envelope;
        wire subunit_write;
        wire lc;
        assign IsNonZero = lc;
        assign subunit_write = ((Addr == 0) || (Addr == 3)) & write;
        assign Sample = (~lc || Shift[14] ? 4'd0 : Envelope);
        LenCounterUnit LenNoi(
                .clk(clk),
                .reset(reset),
                .cold_reset(cold_reset),
                .aclk1(aclk1),
                .aclk1_d(aclk1_d),
                .len_clk(LenCtr_Clock),
                .load_value(lc_load),
                .halt_in(DIN[5]),
                .addr(Addr[0]),
                .is_triangle(1'b0),
                .write(subunit_write),
                .enabled(Enabled),
                .lc_on(lc)
        );
        EnvelopeUnit EnvNoi(
                .clk(clk),
                .reset(reset),
                .env_clk(Env_Clock),
                .din(DIN[5:0]),
                .addr(Addr[0]),
                .write(subunit_write),
                .envelope(Envelope)
        );
        reg [10:0] noise_ntsc_lut [0:15];
        initial begin
                noise_ntsc_lut[0] = 11'h200;
                noise_ntsc_lut[1] = 11'h280;
                noise_ntsc_lut[2] = 11'h2a8;
                noise_ntsc_lut[3] = 11'h6ea;
                noise_ntsc_lut[4] = 11'h4e4;
                noise_ntsc_lut[5] = 11'h674;
                noise_ntsc_lut[6] = 11'h630;
                noise_ntsc_lut[7] = 11'h730;
                noise_ntsc_lut[8] = 11'h4ac;
                noise_ntsc_lut[9] = 11'h304;
                noise_ntsc_lut[10] = 11'h722;
                noise_ntsc_lut[11] = 11'h230;
                noise_ntsc_lut[12] = 11'h213;
                noise_ntsc_lut[13] = 11'h782;
                noise_ntsc_lut[14] = 11'h006;
                noise_ntsc_lut[15] = 11'h014;
        end
        reg [10:0] noise_timer;
        reg noise_clock;
        always @(posedge clk) begin
                if (aclk1_d) begin
                        noise_timer <= {noise_timer[9:0], (noise_timer[10] ^ noise_timer[8]) | ~|noise_timer};
                        if (noise_clock) begin
                                noise_clock <= 0;
                                noise_timer <= noise_ntsc_lut[Period];
                                Shift <= {Shift[13:0], (Shift[14] ^ (ShortMode ? Shift[8] : Shift[13])) | ~|Shift};
                        end
                end
                if (aclk1) begin
                        if (noise_timer == 'h400)
                                noise_clock <= 1;
                end
                if (write && (Addr == 2)) begin
                        ShortMode <= DIN[7];
                        Period <= DIN[3:0];
                end
                if (reset) begin
                        if (|noise_timer)
                                noise_timer <= noise_ntsc_lut[0];
                        ShortMode <= 0;
                        Shift <= 0;
                        Period <= 0;
                end
                if (cold_reset)
                        noise_timer <= 0;
        end
endmodule
module FrameCtr (
        clk,
        aclk1,
        aclk2,
        reset,
        cold_reset,
        write,
        read,
        write_ce,
        din,
        addr,
        MMC5,
        irq,
        irq_flag,
        frame_half,
        frame_quarter
);
        reg _sv2v_0;
        input wire clk;
        input wire aclk1;
        input wire aclk2;
        input wire reset;
        input wire cold_reset;
        input wire write;
        input wire read;
        input wire write_ce;
        input wire [7:0] din;
        input wire [1:0] addr;
        input wire MMC5;
        output wire irq;
        output wire irq_flag;
        output wire frame_half;
        output wire frame_quarter;
        wire frame_reset;
        reg frame_interrupt_buffer;
        wire frame_int_disabled;
        reg FrameInterrupt;
        wire set_irq;
        reg FrameSeqMode_2;
        reg frame_reset_2;
        reg w4017_1;
        reg w4017_2;
        reg [14:0] frame;
        reg [14:0] frame_next;
        reg frame_half_reg;
        reg frame_quarter_reg;
        assign frame_half = frame_half_reg;
        assign frame_quarter = frame_quarter_reg;
        reg DisableFrameInterrupt;
        reg FrameSeqMode;
        assign frame_int_disabled = DisableFrameInterrupt;
        assign irq = FrameInterrupt && ~DisableFrameInterrupt;
        assign irq_flag = frame_interrupt_buffer;
        wire seq_mode;
        assign seq_mode = (aclk1 ? FrameSeqMode : FrameSeqMode_2);
        wire frm_a;
        wire frm_b;
        wire frm_c;
        wire frm_d;
        wire frm_e;
        assign frm_a = 15'b001000001100001 == frame;
        assign frm_b = 15'b011011000000011 == frame;
        assign frm_c = 15'b010110011010011 == frame;
        assign frm_d = (15'b000101000011111 == frame) && ~seq_mode;
        assign frm_e = 15'b111000110000101 == frame;
        assign set_irq = frm_d & ~FrameSeqMode;
        assign frame_reset = (frm_d | frm_e) | w4017_2;
        always @(*) begin
                if (_sv2v_0)
                        ;
                frame_next = (frame_reset_2 ? 15'h7fff : {frame[13:0], (frame[14] ^ frame[13]) | ~|frame});
        end
        always @(posedge clk or posedge reset) begin : apu_block
                if (reset) begin
                        FrameInterrupt <= 0;
                        frame_interrupt_buffer <= 0;
                        w4017_1 <= 0;
                        w4017_2 <= 0;
                        DisableFrameInterrupt <= 0;
                        FrameSeqMode <= 0;
                        frame <= 15'h7fff;
                        frame_half_reg <= 0;
                        frame_quarter_reg <= 0;
                        frame_reset_2 <= 0;
                end
                else begin
                        if (aclk1) begin
                                frame <= frame_next;
                                w4017_2 <= w4017_1;
                                w4017_1 <= 0;
                                if (cold_reset)
                                        FrameSeqMode_2 <= 0;
                                else
                                        FrameSeqMode_2 <= FrameSeqMode;
                                frame_half_reg <= ((frm_b | frm_d) | frm_e) | (w4017_2 & seq_mode);
                                frame_quarter_reg <= ((((frm_a | frm_b) | frm_c) | frm_d) | frm_e) | (w4017_2 & seq_mode);
                                frame_reset_2 <= aclk2 & frame_reset;
                        end
                        if (set_irq & ~frame_int_disabled) begin
                                FrameInterrupt <= 1;
                                frame_interrupt_buffer <= 1;
                        end
                        else if ((addr == 2'h1) && read)
                                FrameInterrupt <= 0;
                        else
                                frame_interrupt_buffer <= FrameInterrupt;
                        if (frame_int_disabled)
                                FrameInterrupt <= 0;
                        if ((write_ce && (addr == 3)) && ~MMC5) begin
                                FrameSeqMode <= din[7];
                                DisableFrameInterrupt <= din[6];
                                w4017_1 <= 1;
                        end
                end
        end
        initial _sv2v_0 = 0;
endmodule
module APU (
        MMC5,
        clk,
        PHI2,
        ce,
        reset,
        cold_reset,
        allow_us,
        ADDR,
        DIN,
        RW,
        CS,
        audio_channels,
        DmaData,
        odd_or_even,
        DmaAck,
        DOUT,
        Sample,
        DmaReq,
        DmaAddr,
        IRQ,
        o_ce
);
        input wire MMC5;
        input wire clk;
        input wire PHI2;
        input wire ce;
        input wire reset;
        input wire cold_reset;
        input wire allow_us;
        input wire [4:0] ADDR;
        input wire [7:0] DIN;
        input wire RW;
        input wire CS;
        input wire [4:0] audio_channels;
        input wire [7:0] DmaData;
        input wire odd_or_even;
        input wire DmaAck;
        output wire [7:0] DOUT;
        output wire [15:0] Sample;
        output wire DmaReq;
        output wire [15:0] DmaAddr;
        output wire IRQ;
        output wire o_ce;
        reg [7:0] len_counter_lut [0:31];
        initial begin
                len_counter_lut[0] = 8'h09;
                len_counter_lut[1] = 8'hfd;
                len_counter_lut[2] = 8'h13;
                len_counter_lut[3] = 8'h01;
                len_counter_lut[4] = 8'h27;
                len_counter_lut[5] = 8'h03;
                len_counter_lut[6] = 8'h4f;
                len_counter_lut[7] = 8'h05;
                len_counter_lut[8] = 8'h9f;
                len_counter_lut[9] = 8'h07;
                len_counter_lut[10] = 8'h3b;
                len_counter_lut[11] = 8'h09;
                len_counter_lut[12] = 8'h0d;
                len_counter_lut[13] = 8'h0b;
                len_counter_lut[14] = 8'h19;
                len_counter_lut[15] = 8'h0d;
                len_counter_lut[16] = 8'h0b;
                len_counter_lut[17] = 8'h0f;
                len_counter_lut[18] = 8'h17;
                len_counter_lut[19] = 8'h11;
                len_counter_lut[20] = 8'h2f;
                len_counter_lut[21] = 8'h13;
                len_counter_lut[22] = 8'h5f;
                len_counter_lut[23] = 8'h15;
                len_counter_lut[24] = 8'hbf;
                len_counter_lut[25] = 8'h17;
                len_counter_lut[26] = 8'h47;
                len_counter_lut[27] = 8'h19;
                len_counter_lut[28] = 8'h0f;
                len_counter_lut[29] = 8'h1b;
                len_counter_lut[30] = 8'h1f;
                len_counter_lut[31] = 8'h1d;
        end
        wire [7:0] lc_load;
        assign lc_load = len_counter_lut[DIN[7:3]];
        wire read;
        wire write;
        wire write_ce;
        reg apu_ce_sync;
        always @(posedge clk) apu_ce_sync <= PHI2;
        assign read = RW & CS;
        assign write = ~RW & CS;
        assign write_ce = write & apu_ce_sync;
        wire aclk1;
        wire aclk2;
        wire aclk1_delayed;
        wire phi1;
        assign aclk1 = odd_or_even;
        assign aclk2 = ~odd_or_even & apu_ce_sync;
        assign aclk1_delayed = ~odd_or_even & ce;
        assign phi1 = ce;
        wire [4:0] Enabled;
        wire [3:0] Sq1Sample;
        wire [3:0] Sq2Sample;
        wire [3:0] TriSample;
        wire [3:0] NoiSample;
        wire [4:0] TriSample_enhanced;
        wire [6:0] DmcSample;
        wire DmcIrq;
        wire IsDmcActive;
        wire irq_flag;
        wire frame_irq;
        wire ApuMW0;
        wire ApuMW1;
        wire ApuMW2;
        wire ApuMW3;
        wire ApuMW4;
        wire ApuMW5;
        assign ApuMW0 = ADDR[4:2] == 0;
        assign ApuMW1 = ADDR[4:2] == 1;
        assign ApuMW2 = ADDR[4:2] == 2;
        assign ApuMW3 = ADDR[4:2] == 3;
        assign ApuMW4 = ADDR[4:2] >= 4;
        assign ApuMW5 = ADDR[4:2] == 5;
        wire Sq1NonZero;
        wire Sq2NonZero;
        wire TriNonZero;
        wire TriNonZero_enhanced;
        wire NoiNonZero;
        wire ClkE;
        wire ClkL;
        wire frame_quarter;
        wire frame_half;
        assign ClkE = frame_quarter & aclk1_delayed;
        assign ClkL = frame_half & aclk1_delayed;
        reg [4:0] enabled_buffer;
        always @(posedge clk or posedge reset)
                if (reset)
                        enabled_buffer <= 0;
                else if (((apu_ce_sync && ApuMW5) && write) && (ADDR[1:0] == 1))
                        enabled_buffer <= DIN[4:0];
        assign Enabled = enabled_buffer;
        assign DOUT = {DmcIrq, irq_flag, 1'b0, IsDmcActive, NoiNonZero, TriNonZero, Sq2NonZero, Sq1NonZero};
        assign IRQ = frame_irq || DmcIrq;
        SquareChan Squ1(
                .MMC5(MMC5),
                .clk(clk),
                .ce(apu_ce_sync),
                .aclk1(aclk1),
                .aclk1_d(aclk1_delayed),
                .reset(reset),
                .cold_reset(cold_reset),
                .allow_us(allow_us),
                .sq2(1'b0),
                .Addr(ADDR[1:0]),
                .DIN(DIN),
                .write(ApuMW0 && write),
                .lc_load(lc_load),
                .LenCtr_Clock(ClkL),
                .Env_Clock(ClkE),
                .odd_or_even(odd_or_even),
                .Enabled(Enabled[0]),
                .Sample(Sq1Sample),
                .IsNonZero(Sq1NonZero)
        );
        SquareChan Squ2(
                .MMC5(MMC5),
                .clk(clk),
                .ce(apu_ce_sync),
                .aclk1(aclk1),
                .aclk1_d(aclk1_delayed),
                .reset(reset),
                .cold_reset(cold_reset),
                .allow_us(allow_us),
                .sq2(1'b1),
                .Addr(ADDR[1:0]),
                .DIN(DIN),
                .write(ApuMW1 && write),
                .lc_load(lc_load),
                .LenCtr_Clock(ClkL),
                .Env_Clock(ClkE),
                .odd_or_even(odd_or_even),
                .Enabled(Enabled[1]),
                .Sample(Sq2Sample),
                .IsNonZero(Sq2NonZero)
        );
        TriangleChan Tri(
                .clk(clk),
                .phi1(phi1),
                .aclk1(aclk1),
                .aclk1_d(aclk1_delayed),
                .reset(reset),
                .cold_reset(cold_reset),
                .allow_us(allow_us),
                .Addr(ADDR[1:0]),
                .DIN(DIN),
                .write(ApuMW2 && write),
                .lc_load(lc_load),
                .LenCtr_Clock(ClkE),
                .LinCtr_Clock(ClkL),
                .Enabled(Enabled[2]),
                .Sample(TriSample),
                .IsNonZero(TriNonZero)
        );
        NoiseChan Noi(
                .clk(clk),
                .ce(apu_ce_sync),
                .aclk1(aclk1),
                .aclk1_d(aclk1_delayed),
                .reset(reset),
                .cold_reset(cold_reset),
                .Addr(ADDR[1:0]),
                .DIN(DIN),
                .write(ApuMW3 && write),
                .lc_load(lc_load),
                .LenCtr_Clock(ClkL),
                .Env_Clock(ClkE),
                .Enabled(Enabled[3]),
                .Sample(NoiSample),
                .IsNonZero(NoiNonZero)
        );
        APUMixer mixer(
                .square1(Sq1Sample),
                .square2(Sq2Sample),
                .noise(NoiSample),
                .triangle(TriSample),
                .dmc(DmcSample),
                .sample(Sample)
        );
        FrameCtr frame_counter(
                .clk(clk),
                .aclk1(aclk1),
                .aclk2(aclk2),
                .reset(reset),
                .cold_reset(cold_reset),
                .write(ApuMW5 & write),
                .read(ApuMW5 & read),
                .write_ce(ApuMW5 & write_ce),
                .addr(ADDR[1:0]),
                .din(DIN),
                .MMC5(MMC5),
                .irq(frame_irq),
                .irq_flag(irq_flag),
                .frame_half(frame_half),
                .frame_quarter(frame_quarter)
        );
        assign o_ce = apu_ce_sync;
endmodule
module APUMixer (
        square1,
        square2,
        triangle,
        noise,
        dmc,
        sample
);
        input wire [3:0] square1;
        input wire [3:0] square2;
        input wire [3:0] triangle;
        input wire [3:0] noise;
        input wire [6:0] dmc;
        output wire [15:0] sample;
        reg [5:0] noise_lut [0:15];
        initial begin
                noise_lut[0] = 6'h00;
                noise_lut[1] = 6'h03;
                noise_lut[2] = 6'h05;
                noise_lut[3] = 6'h08;
                noise_lut[4] = 6'h0b;
                noise_lut[5] = 6'h0d;
                noise_lut[6] = 6'h10;
                noise_lut[7] = 6'h13;
                noise_lut[8] = 6'h15;
                noise_lut[9] = 6'h18;
                noise_lut[10] = 6'h1b;
                noise_lut[11] = 6'h1d;
                noise_lut[12] = 6'h20;
                noise_lut[13] = 6'h23;
                noise_lut[14] = 6'h25;
                noise_lut[15] = 6'h28;
        end
        wire [15:0] ch1_output = {12'b000000000000, square1} + {12'b000000000000, square2};
        wire [15:0] tri_normal_output_scaled = {10'b0000000000, triangle << 2};
        wire [15:0] noise_output_scaled = {10'b0000000000, noise_lut[noise]};
        assign sample = (ch1_output + tri_normal_output_scaled) + noise_output_scaled;
endmodule