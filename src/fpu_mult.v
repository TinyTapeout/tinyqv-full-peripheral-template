`timescale 1ns / 1ps
`default_nettype none

module fpu_mult (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire [15:0] a,
    input  wire [15:0] b,
    output reg         valid_out,
    output reg  [15:0] result
);

    // State definitions
    localparam IDLE      = 3'd0;
    localparam DECODE    = 3'd1;
    localparam MULTIPLY  = 3'd2;
    localparam NORMALIZE = 3'd3;
    localparam PACK      = 3'd4;

    reg [2:0] state;

    // Input registers
    reg [15:0] reg_a, reg_b;

    // Decoded values
    reg sign_a, sign_b;
    reg [9:0] mant_a, mant_b;
    reg [10:0] frac_a, frac_b;
    reg is_nan_a, is_nan_b;
    reg is_inf_a, is_inf_b;
    reg is_zero_a, is_zero_b;

    // Intermediate results
    reg [21:0] product;
    reg [5:0] raw_exp;
    reg result_sign;
    reg is_nan;
    reg [9:0] norm_mant;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            valid_out <= 1'b0;
            result <= 32'b0;
        end else begin
            case (state)
                IDLE: begin
                    valid_out <= 1'b0;
                    if (valid_in) begin
                        reg_a <= a;
                        reg_b <= b;
                        state <= DECODE;
                    end
                end

                DECODE: begin
                    // Decode input A
                    sign_a <= reg_a[15];
                    mant_a <= reg_a[9:0];
                    frac_a <= (reg_a[14:10] == 5'b0) ? {1'b0, reg_a[9:0]} : {1'b1, reg_a[9:0]};
                    is_nan_a <= (reg_a[14:10] == 5'b11111) && (reg_a[9:0] != 0);
                    is_inf_a <= (reg_a[14:10] == 5'b11111) && (reg_a[9:0] == 0);
                    is_zero_a <= (reg_a[14:10] == 5'b0) && (reg_a[9:0] == 0);

                    // Decode input B
                    sign_b <= reg_b[15];
                    mant_b <= reg_b[9:0];
                    frac_b <= (reg_b[14:10] == 5'b0) ? {1'b0, reg_b[9:0]} : {1'b1, reg_b[9:0]};
                    is_nan_b <= (reg_b[14:10] == 5'b11111) && (reg_b[9:0] != 0);
                    is_inf_b <= (reg_b[14:10] == 5'b11111) && (reg_b[9:0] == 0);
                    is_zero_b <= (reg_b[14:10] == 5'b0) && (reg_b[9:0] == 0);

                    state <= MULTIPLY;
                end

                MULTIPLY: begin
                    // Calculate product and exponent
                    product <= frac_a * frac_b;
                    raw_exp <= reg_a[14:10] + reg_b[14:10] - 5'd15; // Subtract bias
                    result_sign <= sign_a ^ sign_b;
                    is_nan <= is_nan_a | is_nan_b | ((is_inf_a | is_inf_b) & (is_zero_a | is_zero_b));

                    state <= NORMALIZE;
                end

                NORMALIZE: begin
                    // Normalize the product
                    if (product[21]) begin
                        // Product overflowed (bit 21 set)
                        norm_mant <= product[20:11];
                        raw_exp <= raw_exp + 1;
                    end else begin
                        // Normal product
                        norm_mant <= product[19:10];
                    end

                    state <= PACK;
                end

                PACK: begin
                    valid_out <= 1'b1;

                    if (is_nan) begin
                        result <= {16'h7E00}; // Quiet NaN
                    end else if (is_inf_a | is_inf_b) begin
                        result <= {{result_sign, 5'b11111, 10'b0}}; // Infinity
                    end else if (is_zero_a | is_zero_b) begin
                        result <= {{result_sign, 15'b0}}; // Zero
                    end else begin
                        // Normal/denormal result
                        result <= {{result_sign, raw_exp[4:0], norm_mant}};
                    end

                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
