# SPDX-FileCopyrightText: © 2025 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from tqv import TinyQV

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
        await tqv.write_byte_reg(0x11, value)
        assert await tqv.read_byte_reg(0x11) == value

    # configuration1 - Test register write and read back
    for value in range(0x00, 0xFF):
        await tqv.write_byte_reg(0x12, value)
        assert await tqv.read_byte_reg(0x12) == value

    # reg_data_input - Test register write and read back
    for value in range(0x00, 0xFF):
        await tqv.write_byte_reg(0x20, value)
        assert await tqv.read_byte_reg(0x20) == value

    
