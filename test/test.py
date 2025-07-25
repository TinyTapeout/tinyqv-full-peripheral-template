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

    # # configuration0 - Test register write and read back
    # for value in range(0x00, 0xFF):
    #     await tqv.write_byte_reg(0x11, value)
    #     assert await tqv.read_byte_reg(0x11) == value

    # # 1 - Test register write and read back
    # for value in range(0x00, 0xFF):
    #     await tqv.write_word_reg(1, value)
    #     assert await tqv.read_byte_reg(1) == value 

    # # Set an input value, in the example this will be added to the register value
    # dut.ui_in.value = 30

    # # Wait for two clock cycles to see the output values, because ui_in is synchronized over two clocks,
    # # and a further clock is required for the output to propagate.
    # await ClockCycles(dut.clk, 3)

    # # The following assertion is just an example of how to check the output values.
    # # Change it to match the actual expected output of your module:
    # assert dut.uo_out.value == 0x96

    # # Input value should be read back from register 1
    # assert await tqv.read_byte_reg(4) == 30

    # # Zero should be read back from register 2
    # assert await tqv.read_word_reg(8) == 0

    # # A second write should work
    # await tqv.write_word_reg(0, 40)
    # assert dut.uo_out.value == 70

    # # Test the interrupt, generated when ui_in[6] goes high
    # dut.ui_in[6].value = 1
    # await ClockCycles(dut.clk, 1)
    # dut.ui_in[6].value = 0

    # # Interrupt asserted
    # await ClockCycles(dut.clk, 3)
    # assert dut.uio_out[0].value == 1

    # # Interrupt doesn't clear
    # await ClockCycles(dut.clk, 10)
    # assert dut.uio_out[0].value == 1
    
    # # Write bottom bit of address 8 high to clear
    # await tqv.write_byte_reg(8, 1)
    # assert dut.uio_out[0].value == 0
