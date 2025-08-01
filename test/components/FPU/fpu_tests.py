import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock
import numpy as np
import math
import struct

def float_to_f16_hex(f):
    """Convert Python float to 32-bit word with f16 in lower 16 bits."""
    f16 = np.float16(f)
    return int(f16.view(np.uint16))

def f16_hex_to_float(h16):
    """Correctly convert 16-bit int to Python float using little-endian byte order."""
    return float(np.frombuffer(struct.pack('<H', h16 & 0xFFFF), dtype=np.float16)[0])

async def write(dut, addr, data):
    dut.address.value = addr
    dut.data_in.value = data
    dut.data_write_n.value = 0b10
    await RisingEdge(dut.clk)
    dut.data_write_n.value = 0b11
    await RisingEdge(dut.clk)

async def read(dut, addr):
    dut.address.value = addr
    dut.data_read_n.value = 0b10
    await RisingEdge(dut.clk)
    dut.data_read_n.value = 0b11
    await RisingEdge(dut.clk)
    return int(dut.data_out.value)

@cocotb.test()
async def test_add_mul_sub_half_precision(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units='ns').start())

    # Reset
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.data_write_n.value = 0b11
    dut.data_read_n.value = 0b11
    await Timer(20, units='ns')
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    tests = [
        (3.5, 1.25),
        (-2.0, 5.0),
        (0.0, 0.0),
        (float('inf'), 1.0),
        (float('-inf'), float('inf')),
        (float('inf'), float('-inf')),
        (float('nan'), 1.0),
        (1.0, float('nan')),
        (1.0, 0.0),
        (0.0, 1.0),
        (33.33, 1.0)
    ]

    for a, b in tests:
        a_hex = float_to_f16_hex(a)
        b_hex = float_to_f16_hex(b)

        async def perform_op(ctrl, op_str):
            await write(dut, ctrl, (a_hex & 0xFFFF))  # Make sure MSB is zero
            await write(dut, ctrl + 1, (b_hex & 0xFFFF))

            for _ in range(20):
                await RisingEdge(dut.clk)
                if (dut.data_ready.value == 1):
                    break

            result = await read(dut, 0x0C)
            actual = f16_hex_to_float(result)

            a16 = np.float16(a)
            b16 = np.float16(b)

            expected = {
                0x00: a16 + b16,
                0x04: a16 - b16,
                0x08: a16 * b16
            }[ctrl]

            if math.isnan(expected):
                assert math.isnan(actual), f"{op_str} FAIL: {a} ? {b} = {actual}, expected NaN"
            elif math.isinf(expected):
                assert math.isinf(actual) and (actual == float(expected)), f"{op_str} FAIL: {a} ? {b} = {actual}, expected {expected}"
            else:
                assert abs(actual - float(expected)) < 1e-2, f"{op_str} FAIL: {a} ? {b} = {actual}, expected {expected}"

            dut._log.info(f"PASS {op_str}: {a} ? {b} = {actual}")

        await perform_op(0x00, "ADD")
        await perform_op(0x04, "SUB")
        await perform_op(0x08, "MUL")
