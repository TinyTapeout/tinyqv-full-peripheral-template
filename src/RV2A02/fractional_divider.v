 `default_nettype none

module fractional_divider (
    input wire clk_in,    // 64 MHz input clock
    input wire rst_n,     // Asynchronous active-low reset
    output reg clk_out    // ~1.7897725 MHz output clock
);

    // Target division ratio: 64,000,000 / 1,789,772.5 = 35.75988...
    // To implement fractional division, we can use a "N/M" approach
    // We want to divide by approximately 35.75988
    // Let's approximate it with a ratio of integers: 35.75988 = 3575988 / 100000 = 893997 / 25000 (after simplification)
    // This means for every 25000 periods of the output, there are 893997 input clock periods.
    // We will divide by 36 (for 18997 cycles) and by 35 (for 6003 cycles).
    // Sum of these cycles: 18997 + 6003 = 25000.
    // Total input clocks: (18997 * 36) + (6003 * 35) = 683892 + 210105 = 893997.

    parameter DIV_N_HIGH = 36; // Divide by 36
    parameter DIV_N_LOW  = 35; // Divide by 35

    // Total cycles to achieve the ratio (denominator of the simplified fraction)
    // In our simplified fraction 893997/25000, this is 25000
    parameter CYCLES_IN_PERIOD_DENOMINATOR = 25000; 

    // Number of times to use DIV_N_HIGH (numerator of fractional part in simplified fraction)
    parameter NUM_HIGH_DIVS = 18997; 

    reg [$clog2(DIV_N_HIGH):0] counter; // Counter for the current output clock period
    reg [$clog2(CYCLES_IN_PERIOD_DENOMINATOR):0] freq_acc_counter; // Accumulator for the fractional part
    reg clk_out_internal;

    // Output clock generation
    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 0;
            freq_acc_counter <= 0;
            clk_out_internal <= 1'b0;
        end else begin
            if (counter == (DIV_N_HIGH - 1) && freq_acc_counter < NUM_HIGH_DIVS) begin
                // Divide by DIV_N_HIGH (36)
                counter <= 0;
                clk_out_internal <= ~clk_out_internal;
                freq_acc_counter <= freq_acc_counter + 1;
            end else if (counter == (DIV_N_LOW - 1) && freq_acc_counter >= NUM_HIGH_DIVS) begin
                // Divide by DIV_N_LOW (35)
                counter <= 0;
                clk_out_internal <= ~clk_out_internal;
                freq_acc_counter <= freq_acc_counter + 1;
            end else begin
                counter <= counter + 1;
            end

            // Reset fractional accumulator when a full 'period' is complete
            if (freq_acc_counter == CYCLES_IN_PERIOD_DENOMINATOR - 1) begin
                freq_acc_counter <= 0;
            end
        end
    end
    
    assign clk_out = clk_out_internal;

endmodule