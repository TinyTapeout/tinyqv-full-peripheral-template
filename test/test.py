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

APU_STATUS_REG_ADDRESS          = 0x15
APU_FRAME_COUNTER_REG_ADDRESS   = 0x17

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
    # Test 1 - Basic APU Configuration and 440Hz Tone Generation
    #

    # Configure APU
    configuration0_reg = 0x89
    configuration1_reg = 0x00
    await tqv.write_byte_reg(CONFIGURATION0_REG_ADDR, configuration0_reg)
    await tqv.write_byte_reg(CONFIGURATION1_REG_ADDR, configuration0_reg)

    # 1. Disable all channels and reset frame counter (good practice before configuring)
    #    Writing 0 to 0x4015 disables all channels.
    #    Writing 0 to 0x4017 resets the frame counter and sets it to 4-step mode.
    # WRITE 0 TO APU_STATUS_REG
    await tqv.write_byte_reg(APU_STATUS_REG_ADDRESS, 0x00)
    # WRITE 0 TO APU_FRAME_COUNTER_REG
    await tqv.write_byte_reg(APU_FRAME_COUNTER_REG_ADDRESS, 0x00)

    #  --- Configure Square Channel 1 ---
    #  Register $4000: Duty Cycle, Length Counter Halt, Constant Volume, Volume/Envelope Decay
    #  Let's choose:
    #    - Duty Cycle: 10% (00) - often a good starting point, or 50% (01)
    #    - Length Counter Halt: 1 (halt, for sustained note)
    #    - Constant Volume: 1 (use constant volume)
    #    - Volume/Envelope Decay: 15 (max volume)
    #  Binary: %10011111 = $9F
    # WRITE $9F TO APU_SQ1_REG0
    await tqv.write_byte_reg(APU_SQ1_REG0_ADDRESS, 0x9F)

    # Register $4001: Sweep Unit (disabled for simple tone)
    # Set all bits to 0 to disable sweep.
    # WRITE $00 TO APU_SQ1_REG1
    await tqv.write_byte_reg(APU_SQ1_REG1_ADDRESS, 0x00)

    # Register $4002: Timer Low Byte
    # Write the lower 8 bits of the calculated timer period (126)
    # WRITE SQ_TIMER_PERIOD_LOW TO APU_SQ1_REG2
    await tqv.write_byte_reg(APU_SQ1_REG2_ADDRESS, SQ_TIMER_PERIOD_LOW)

    # Register $4003: Length Counter Load, Timer High Byte
    # Combine the length counter load value with the upper 3 bits of the timer period.
    # Length Counter Load (bits 7-3) | Timer High (bits 2-0)
    # For sustained note, the length counter halt bit in $4000 is more important.
    # We'll just put the timer high bits here.
    # WRITE (LENGTH_COUNTER_LOAD_VALUE | SQ_TIMER_PERIOD_HIGH) TO APU_SQ1_REG3
    await tqv.write_byte_reg(APU_SQ1_REG3_ADDRESS, (LENGTH_COUNTER_LOAD_VALUE | SQ_TIMER_PERIOD_HIGH))

    # --- Configure Square Channel 2 (similar to Square 1) ---
    # Register $4004: Duty Cycle, Length Counter Halt, Constant Volume, Volume/Envelope Decay
    # Same settings as Square 1 for simplicity
    # WRITE $9F TO APU_SQ2_REG0
    await tqv.write_byte_reg(APU_SQ2_REG0_ADDRESS, 0x9F)

    # Register $4005: Sweep Unit (disabled)
    # WRITE $00 TO APU_SQ2_REG1
    await tqv.write_byte_reg(APU_SQ2_REG1_ADDRESS, 0x00)

    # Register $4006: Timer Low Byte
    # WRITE SQ_TIMER_PERIOD_LOW TO APU_SQ2_REG2
    await tqv.write_byte_reg(APU_SQ2_REG2_ADDRESS, SQ_TIMER_PERIOD_LOW)

    # Register $4007: Length Counter Load, Timer High Byte
    # WRITE (LENGTH_COUNTER_LOAD_VALUE | SQ_TIMER_PERIOD_HIGH) TO APU_SQ2_REG3
    await tqv.write_byte_reg(APU_SQ2_REG3_ADDRESS, (LENGTH_COUNTER_LOAD_VALUE | SQ_TIMER_PERIOD_HIGH))

    # --- Configure Triangle Channel ---
    # Register $4008: Linear Counter Load, Linear Counter Control (Length Counter Halt for Triangle)
    # For a sustained triangle wave:
    #   - Linear Counter Control (Length Counter Halt): 1 (halt, for sustained note)
    #   - Linear Counter Load: 15 (max volume, or any non-zero value to keep it active)
    # Binary: %11111111 = $7F (bit 7 is linear counter control, bits 6-0 are load value)
    # Note: The triangle channel doesn't have a volume envelope like squares; its volume is fixed.
    # The linear counter acts like a length counter for the triangle.
    # WRITE $7F TO APU_TRI_REG0
    await tqv.write_byte_reg(APU_TRI_REG0_ADDRESS, 0x7F)

    # Register $4009: Unused (write $00)
    # WRITE $00 TO APU_TRI_REG1
    await tqv.write_byte_reg(APU_TRI_REG1_ADDRESS, 0x00)

    # Register $400A: Timer Low Byte
    # Write the lower 8 bits of the calculated timer period (62)
    # WRITE TRI_TIMER_PERIOD_LOW TO APU_TRI_REG2
    await tqv.write_byte_reg(APU_TRI_REG2_ADDRESS, TRI_TIMER_PERIOD_LOW)

    # Register $400B: Length Counter Load, Timer High Byte
    # Combine the length counter load value with the upper 3 bits of the timer period.
    # For sustained note, the linear counter control bit in $4008 is more important.
    # We'll just put the timer high bits here.
    # WRITE (LENGTH_COUNTER_LOAD_VALUE | TRI_TIMER_PERIOD_HIGH) TO APU_TRI_REG3
    await tqv.write_byte_reg(APU_TRI_REG3_ADDRESS, (LENGTH_COUNTER_LOAD_VALUE | TRI_TIMER_PERIOD_HIGH))

    # --- Enable Channels ---
    # Register $4015: APU Status / Channel Enable
    # Enable Square 1 (bit 0), Square 2 (bit 1), Triangle (bit 2)
    # Binary: %00000111 = $07
    # WRITE $07 TO APU_STATUS_REG
    await tqv.write_byte_reg(APU_STATUS_REG_ADDRESS, 0x07)

    # --- Start Frame Counter (Optional, but good for consistent behavior) ---
    # Writing to $4017 starts the frame counter.
    # $4017 = $00 for 4-step sequence (no IRQ)
    # $4017 = $40 for 4-step sequence (with IRQ)
    # $4017 = $80 for 5-step sequence (no IRQ)
    # $4017 = $C0 for 5-step sequence (with IRQ)
    # For continuous sound, 4-step (no IRQ) is common.
    # WRITE $00 TO APU_FRAME_COUNTER_REG
    await tqv.write_byte_reg(APU_FRAME_COUNTER_REG_ADDRESS, 0x00)

    # --- Time to test the output!!!