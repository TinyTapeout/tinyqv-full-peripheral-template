# SPDX-FileCopyrightText: © 2025 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from tqv import TinyQV

CONFIGURATION0_REG_ADDR = 0x20
CONFIGURATION1_REG_ADDR = 0x21

APU_SQ1_REG0_ADDRESS    = 0x00
APU_SQ1_REG1_ADDRESS    = 0x01
APU_SQ1_REG2_ADDRESS    = 0x02
APU_SQ1_REG3_ADDRESS    = 0x03

APU_SQ2_REG0_ADDRESS    = 0x04
APU_SQ2_REG1_ADDRESS    = 0x05
APU_SQ2_REG2_ADDRESS    = 0x06
APU_SQ2_REG3_ADDRESS    = 0x07

APU_TRI_REG0_ADDRESS    = 0x08
APU_TRI_REG1_ADDRESS    = 0x09 # Unused
APU_TRI_REG2_ADDRESS    = 0x0A
APU_TRI_REG3_ADDRESS    = 0x0B

# APU_STATUS_REG_ADDRESS = 0x15
# APU_FRAME_COUNTER_REG_ADDRESS = 0x17

# Calculated Timer Period for Square Channels (440Hz)
# Timer Period = 126 = 0x7E
SQ_TIMER_PERIOD_LOW  = (0x7E)&(0xFF)      # Lower 8 bits
SQ_TIMER_PERIOD_HIGH = (0x7E >> 8)&(0x07) # Upper 3 bits

# Calculated Timer Period for Triangle Channel (440Hz)
# Timer Period = 62 = 0x3E
TRI_TIMER_PERIOD_LOW  = (0x3E)&(0xFF)      # Lower 8 bits
TRI_TIMER_PERIOD_HIGH = (0x3E >> 8)&(0x07) # Upper 3 bits

# Length Counter Load Value (e.g., for a long note)
# This value is an index into a lookup table. For a sustained note,
# you might want a large value or to disable the length counter.
# For simplicity, let's pick a value that gives a long duration.
# The length counter values are 5 bits, so 0-31.
# A value of 0 in the high 5 bits of $4003/$4007/$400B corresponds to a length of 10.
# A value of 0xFF (255) in the high 5 bits of $4003/$4007/$400B corresponds to a length of 255.
# For a sustained note, it's often easier to set the Length Counter Halt bit.
LENGTH_COUNTER_LOAD_VALUE = 0xF0

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 100 ns (10 MHz)
    clock = Clock(dut.clk, 100, units="ns")
    cocotb.start_soon(clock.start())

    # Interact with your design's registers through this TinyQV class.
    # This will allow the same test to be run when your design is integrated
    # with TinyQV - the implementation of this class will be replaces with a
    # different version that uses Risc-V instructions instead of the SPI 
    # interface to read and write the registers.
    tqv = TinyQV(dut)

    # Reset
    await tqv.reset()

    dut._log.info("Test project behavior")

    # Register @0x00 - Test register write and read back
    for value in range(0x00, 0xFF):
        await tqv.write_byte_reg(0x00, value)
        assert await tqv.read_byte_reg(0x00) == value

    # configuration0 - Test register write and read back
    for value in range(0x00, 0xFF):
        await tqv.write_byte_reg(CONFIGURATION0_REG_ADDR, value)
        assert await tqv.read_byte_reg(CONFIGURATION0_REG_ADDR) == value

    # configuration1 - Test register write and read back
    for value in range(0x00, 0xFF):
        await tqv.write_byte_reg(CONFIGURATION1_REG_ADDR, value)
        assert await tqv.read_byte_reg(CONFIGURATION1_REG_ADDR) == value

    # reg_data_input - Test register write and read back
    for value in range(0x00, 0xFF):
        await tqv.write_byte_reg(0x22, value)
        assert await tqv.read_byte_reg(0x22) == value

    #
    # Test 1 - Basic APU Configuration
    #

    # Configure APU
    configuration0_reg = 0x89
    configuration1_reg = 0x00
    await tqv.write_byte_reg(CONFIGURATION0_REG_ADDR, configuration0_reg)
    await tqv.write_byte_reg(CONFIGURATION1_REG_ADDR, configuration0_reg)


