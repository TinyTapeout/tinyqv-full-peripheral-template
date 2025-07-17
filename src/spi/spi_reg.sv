/*
 * Copyright (c) 2024 Caio Alonso da Costa
 * Copyright (c) 2025 Michael Bell
 * SPDX-License-Identifier: Apache-2.0
 */

module spi_reg #(
    parameter int ADDR_W = 3,
    parameter int REG_W = 8
) (
    input  logic clk,
    input  logic rstb,
    input  logic ena,
    input  logic spi_mosi,
    output logic spi_miso,
    input  logic spi_clk,
    input  logic spi_cs_n,
    output logic [ADDR_W-1:0] reg_addr,
    input  logic [REG_W-1:0] reg_data_i,
    output logic [REG_W-1:0] reg_data_o,
    output logic reg_addr_v,
    output logic reg_data_o_dv,
    output logic reg_rw,
    output logic [1:0] txn_width,
    input  logic [7:0] status
);

  // Map to outputs
  assign reg_addr = addr;
  assign reg_data_o = data;
  assign reg_data_o_dv = dv;
  assign spi_miso = tx_buffer[REG_W-1];

  // Start of frame - negedge of spi_cs_n
  logic sof;
  // Pulse on start of frame
  falling_edge_detector falling_edge_detector_sof (.rstb(rstb), .clk(clk), .ena(ena), .data(spi_cs_n), .neg_edge(sof));
  // End of frame - posedge of spi_cs_n
  logic eof;
  // Pulse on end of frame
  rising_edge_detector rising_edge_detector_eof (.rstb(rstb), .clk(clk), .ena(ena), .data(spi_cs_n), .pos_edge(eof));

  // Pulses on rising and falling edge of spi_clk
  logic spi_clk_pos;
  logic spi_clk_neg;

  // Pulse on rising edge of spi_clk
  rising_edge_detector rising_edge_detector_spi_clk (.rstb(rstb), .clk(clk), .ena(ena), .data(spi_clk), .pos_edge(spi_clk_pos));
  // Pulse on falling edge of spi_clk
  falling_edge_detector falling_edge_detector_spi_clk (.rstb(rstb), .clk(clk), .ena(ena), .data(spi_clk), .neg_edge(spi_clk_neg));

  // Mask with spi_cs_n
  logic spi_clk_pos_gated;
  logic spi_clk_neg_gated;

  assign spi_clk_pos_gated = spi_clk_pos & ~spi_cs_n;
  assign spi_clk_neg_gated = spi_clk_neg & ~spi_cs_n;

  // Sample data
  logic spi_data_sample;
  // Change data
  logic spi_data_change;

  // Assume mode 00
  assign spi_data_sample = spi_clk_pos_gated;
  assign spi_data_change = spi_clk_neg_gated;

  // FSM states type
  typedef enum logic [2:0] {
    STATE_IDLE, STATE_ADDR, STATE_CMD, STATE_RX_DATA, STATE_TX_DATA
  } fsm_state;

  // FSM states
  fsm_state state, next_state;

  // Next state transition
  always_ff @(negedge(rstb) or posedge(clk)) begin
    if (!rstb) begin
      state <= STATE_IDLE;
    end else begin
      if (ena == 1'b1) begin
        state <= next_state;
      end
    end
  end

  // Sample addr and data
  logic tx_buffer_load;
  logic sample_addr;
  logic sample_data;

  assign reg_addr_v = tx_buffer_load;

  // Next state logic
  always_comb begin
    // default assignments
    next_state = state;
    tx_buffer_load = 1'b0;
    sample_addr = 1'b0;
    sample_data = 1'b0;

    case (state)
      STATE_IDLE : begin
        if (sof == 1'b1) begin
          next_state = STATE_ADDR;
        end
      end
      STATE_ADDR : begin
        if (buffer_counter == REG_W) begin
          sample_addr = 1'b1;
          next_state = STATE_CMD;
        end else if (eof == 1'b1) begin
          next_state = STATE_IDLE;
        end
      end
      STATE_CMD : begin
        if (reg_rw == 1'b0) begin
          next_state = STATE_TX_DATA;
        end else if (reg_rw == 1'b1) begin
          next_state = STATE_RX_DATA;
        end else if (eof == 1'b1) begin
          next_state = STATE_IDLE;
        end
      end
      STATE_RX_DATA : begin
        if (buffer_counter == REG_W) begin
          sample_data = 1'b1;
          next_state = STATE_IDLE;
        end else if (eof == 1'b1) begin
          next_state = STATE_IDLE;
        end
      end
      STATE_TX_DATA : begin
        if (buffer_counter == '0) begin
          tx_buffer_load = 1'b1;
        end else if (buffer_counter == REG_W) begin
          next_state = STATE_IDLE;
        end else if (eof == 1'b1) begin
          next_state = STATE_IDLE;
        end
      end
      default : begin
        next_state = STATE_IDLE;
      end
    endcase
  end

  // RX Buffer
  logic [REG_W-1:0] rx_buffer;

  // RX Buffer
  always_ff @(negedge(rstb) or posedge(clk)) begin
    if (!rstb) begin
      rx_buffer <= '0;
    end else begin
      if (ena == 1'b1) begin
        if (spi_data_sample == 1'b1) begin
          rx_buffer <= {rx_buffer[REG_W-2:0], spi_mosi};
        end
      end
    end
  end

  // General counter
  logic [5:0] buffer_counter;

  // Buffer Counter
  always_ff @(negedge(rstb) or posedge(clk)) begin
    if (!rstb) begin
      buffer_counter <= '0;
    end else begin
      if (ena == 1'b1) begin
        if (buffer_counter == REG_W) begin
          buffer_counter <= '0;
        end else if (spi_data_sample == 1'b1) begin
          buffer_counter <= buffer_counter + 1'b1;
        end
      end
    end
  end

  // Addr and Read/Write Command register
  logic [ADDR_W-1:0] addr;

  // Addr and Read/Write Command Registers
  always_ff @(negedge(rstb) or posedge(clk)) begin
    if (!rstb) begin
      addr <= '0;
      reg_rw <= '0;
      txn_width <= 2'b11;
    end else begin
      if (ena == 1'b1) begin
        if (sample_addr == 1'b1) begin
          addr <= rx_buffer[ADDR_W-1:0];
          reg_rw <= rx_buffer[REG_W-1];
          txn_width <= rx_buffer[REG_W-2:REG_W-3];
        end
      end
    end
  end

  // Data register and data valid strobe
  logic [REG_W-1:0] data;
  logic dv;

    // Data and DataValid (dv) Registers
  always_ff @(negedge(rstb) or posedge(clk)) begin
    if (!rstb) begin
      data <= '0;
      dv <= '0;
    end else begin
      if (ena == 1'b1) begin
        dv <= '0;
        if (sample_data == 1'b1) begin
          data <= rx_buffer;
          dv <= (1'b1 & reg_rw);
        end
      end
    end
  end

  // TX Buffer
  logic [REG_W-1:0] tx_buffer;

  // TX Buffer
  always_ff @(negedge(rstb) or posedge(clk)) begin
    if (!rstb) begin
      tx_buffer <= '0;
    end else begin
      if (ena == 1'b1) begin
        if (sof == 1'b1) begin
          tx_buffer <= status;
        end else if (tx_buffer_load == 1'b1) begin
          tx_buffer <= reg_data_i;
        end else if (spi_data_change == 1'b1) begin
          tx_buffer <= {tx_buffer[REG_W-2:0], 1'b0};
        end
      end
    end
  end

endmodule
