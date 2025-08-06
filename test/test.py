# SPDX-FileCopyrightText: © 2025 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from cocotb.triggers import Timer

from tqv import TinyQV

CONFIGURATION0_REG_ADDR = 0x20
CONFIGURATION1_REG_ADDR = 0x21
DATA_INPUT_REG_ADDR = 0x23

# New register addresses for APU output sample
DATA_OUTPUT_MSB_REG_ADDR = 0x24
DATA_OUTPUT_LSB_REG_ADDR = 0x25

APU_SQ1_REG0_ADDRESS = 0x00
APU_SQ1_REG1_ADDRESS = 0x01
APU_SQ1_REG2_ADDRESS = 0x02
APU_SQ1_REG3_ADDRESS = 0x03

APU_SQ2_REG0_ADDRESS = 0x04
APU_SQ2_REG1_ADDRESS = 0x05
APU_SQ2_REG2_ADDRESS = 0x06
APU_SQ2_REG3_ADDRESS = 0x07

APU_TRI_REG0_ADDRESS = 0x08
APU_TRI_REG1_ADDRESS = 0x09
APU_TRI_REG2_ADDRESS = 0x0A
APU_TRI_REG3_ADDRESS = 0x0B

APU_STATUS_REG_ADDRESS = 0x15
APU_FRAME_COUNTER_REG_ADDRESS = 0x17

# Calculated Timer Period for Square Channels (440Hz)
# Timer Period = 126 = 0x7E
SQ_TIMER_PERIOD_LOW = (0x7E) & (0xFF)
SQ_TIMER_PERIOD_HIGH = (0x7E >> 8) & (0x07)

# Calculated Timer Period for Triangle Channel (440Hz)
# Timer Period = 62 = 0x3E
TRI_TIMER_PERIOD_LOW = (0x3E) & (0xFF)
TRI_TIMER_PERIOD_HIGH = (0x3E >> 8) & (0x07)

# Length Counter Load Value (e.g., for a long note)
LENGTH_COUNTER_LOAD_VALUE = 0xF0

# --- Helper Functions ---
async def disable_all_channels(tqv):
    """Disables all APU channels and resets the frame counter."""
    await tqv.write_byte_reg(APU_STATUS_REG_ADDRESS, 0x00)
    await tqv.write_byte_reg(APU_FRAME_COUNTER_REG_ADDRESS, 0x00)

async def configure_sq1(tqv):
    """Configures Square Channel 1."""
    await tqv.write_byte_reg(APU_SQ1_REG0_ADDRESS, 0x9F)
    await tqv.write_byte_reg(APU_SQ1_REG1_ADDRESS, 0x00)
    await tqv.write_byte_reg(APU_SQ1_REG2_ADDRESS, SQ_TIMER_PERIOD_LOW)
    await tqv.write_byte_reg(APU_SQ1_REG3_ADDRESS, (LENGTH_COUNTER_LOAD_VALUE | SQ_TIMER_PERIOD_HIGH))

async def configure_sq2(tqv):
    """Configures Square Channel 2."""
    await tqv.write_byte_reg(APU_SQ2_REG0_ADDRESS, 0x9F)
    await tqv.write_byte_reg(APU_SQ2_REG1_ADDRESS, 0x00)
    await tqv.write_byte_reg(APU_SQ2_REG2_ADDRESS, SQ_TIMER_PERIOD_LOW)
    await tqv.write_byte_reg(APU_SQ2_REG3_ADDRESS, (LENGTH_COUNTER_LOAD_VALUE | SQ_TIMER_PERIOD_HIGH))

async def configure_tri(tqv):
    """Configures Triangle Channel."""
    await tqv.write_byte_reg(APU_TRI_REG0_ADDRESS, 0xFF)
    await tqv.write_byte_reg(APU_TRI_REG1_ADDRESS, 0x00)
    await tqv.write_byte_reg(APU_TRI_REG2_ADDRESS, TRI_TIMER_PERIOD_LOW)
    await tqv.write_byte_reg(APU_TRI_REG3_ADDRESS, (LENGTH_COUNTER_LOAD_VALUE | TRI_TIMER_PERIOD_HIGH))

async def capture_samples(tqv, dut, num_cycles):
    """Captures APU output samples for a given number of cycles."""
    samples = []
    # I remember you requested that the testbench should account for o_ce
    for _ in range(num_cycles):
        msb_value = await tqv.read_byte_reg(DATA_OUTPUT_MSB_REG_ADDR)
        lsb_value = await tqv.read_byte_reg(DATA_OUTPUT_LSB_REG_ADDR)
        combined_sample = (msb_value << 8) | lsb_value
        
        if combined_sample & 0x8000:
            signed_sample = combined_sample - 0x10000
        else:
            signed_sample = combined_sample
        
        samples.append(signed_sample)
    return samples

# --- Test Function 1 (Original) ---
async def test_all_channels_simultaneously(tqv, dut):
    """
    Test Phase 1: Configures and runs all three channels simultaneously.
    """
    dut._log.info("--- Test Phase 1: All channels together (Normal Mixer) ---")

    # Enable channels: Sq1, Sq2, Tri
    await tqv.write_byte_reg(APU_STATUS_REG_ADDRESS, 0x07)
    
    await configure_sq1(tqv)
    await configure_sq2(tqv)
    await configure_tri(tqv)

    # Add a short delay to allow the linear counter to stabilize
    await ClockCycles(dut.clk, 50000)

    # Capture output and generate plot
    output_samples = []
    NUM_CYCLES_TO_CAPTURE = 100
    for i in range(NUM_CYCLES_TO_CAPTURE):
        msb_value = await tqv.read_byte_reg(DATA_OUTPUT_MSB_REG_ADDR)
        lsb_value = await tqv.read_byte_reg(DATA_OUTPUT_LSB_REG_ADDR)
        combined_sample = (msb_value << 8) | lsb_value
        if combined_sample & 0x8000:
            signed_sample = combined_sample - 0x10000
        else:
            signed_sample = combined_sample
        output_samples.append(signed_sample)

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())
    tqv = TinyQV(dut)

    await tqv.reset()
    await ClockCycles(dut.clk, 10)
    dut._log.info("Test project behavior")
    
    # --- GLOBAL APU RESET ---
    dut._log.info("Performing a global APU reset before starting tests.")
    await disable_all_channels(tqv)
    
    # Configure the APU for the normal mixer test
    await tqv.write_byte_reg(CONFIGURATION0_REG_ADDR, 0x01)
    await tqv.write_byte_reg(CONFIGURATION0_REG_ADDR, 0x01)

    # Call the test function for the normal mixer
    await test_all_channels_simultaneously(tqv, dut)

    dut._log.info("Test finished.")