import cocotb
from cocotb.triggers import RisingEdge
from cocotb.clock import Clock
import struct
import math
import numpy as np

def float_to_half_bin(f):
    return struct.unpack('>H', struct.pack('>e', f))[0]

def half_bin_to_float(h):
    return struct.unpack('>e', struct.pack('>H', h & 0xFFFF))[0]

async def apply_and_wait(dut, a_float, b_float):
    a_bin = float_to_half_bin(a_float)
    b_bin = float_to_half_bin(b_float)
    dut.a.value = a_bin  # lower 16 bits
    dut.b.value = b_bin
    dut.valid_in.value = 1

    await RisingEdge(dut.clk)
    dut.valid_in.value = 0

    counter = 0

    # Wait for valid_out
    while dut.valid_out.value != 1:
        await RisingEdge(dut.clk)
        counter += 1
        if counter > 50:  # Timeout after 1000 cycles
            raise TimeoutError("FPU did not produce output in time")

    raw_result = int(dut.result.value) & 0xFFFF
    return half_bin_to_float(raw_result)

@cocotb.test()
async def test_fpu_add_normal(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units='ns').start())
    dut.rst_n.value = 0
    dut.valid_in.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    tests = [
        (0.0, 0.0),
        (1.0, 1.0),
        (0.01, 0.01),
        (100.0, 0.01),
        (3.5, 1.25),
        (1.0, 2.0),
        (0.5, 0.25),
        (100.0, 200.0)
    ]
    for a, b in tests:
        actual = await apply_and_wait(dut, a, b)
        expected = float(np.float16(a) + np.float16(b))
        assert abs(actual - expected) < 1e-2, f"FAIL: {a} + {b} = {actual}, expected {expected}"
        dut._log.info(f"PASS: {a} + {b} = {actual}")

@cocotb.test()
async def test_fpu_add_with_signs(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units='ns').start())
    dut.rst_n.value = 0
    dut.valid_in.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    tests = [
        (-1.0, -2.0),
        (5.0, -2.0),
        (-3.5, 1.25),
        (1.5, -1.5),
        (-1.5, 1.5),
        (100.00, 0.01),
        (100.0, -100.0),
        (-100.0, 100.0)
    ]
    for a, b in tests:
        actual = await apply_and_wait(dut, a, b)
        expected = float(np.float16(a) + np.float16(b))
        assert abs(actual - expected) < 1e-2, f"FAIL: {a} + {b} = {actual}, expected {expected}"
        dut._log.info(f"PASS: {a} + {b} = {actual}")

@cocotb.test()
async def test_fpu_subtraction(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units='ns').start())
    dut.rst_n.value = 0
    dut.valid_in.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    tests = [
        (5.0, 2.0),
        (2.0, 5.0),
        (-1.0, -1.0),
        (-2.5, -1.0),
        (3.5, 3.5),
        (100, 0.01),
    ]
    for a, b in tests:
        actual = await apply_and_wait(dut, a, -b)
        expected = float(np.float16(a) - np.float16(b))
        assert abs(actual - expected) < 1e-2, f"FAIL: {a} - {b} = {actual}, expected {expected}"
        dut._log.info(f"PASS: {a} - {b} = {actual}")

@cocotb.test()
async def test_fpu_edge_cases(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units='ns').start())
    dut.rst_n.value = 0
    dut.valid_in.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    nan = float('nan')
    inf = float('inf')
    tests = [
        (inf, inf, inf),
        (-inf, -inf, -inf),
        (inf, -inf, nan),
        (nan, 1.0, nan),
        (1.0, nan, nan),
        (0.0, -0.0, 0.0),
        (inf, 1.0, inf),
        (-1.0, inf, inf),
        (-inf, 1.0, -inf),
        (0.0, inf, inf),
        (0.0, nan, nan)
    ]
    for a, b, expected in tests:
        actual = await apply_and_wait(dut, a, b)

        if math.isnan(expected):
            assert math.isnan(actual), f"FAIL: {a} + {b} = {actual}, expected NaN"
        elif math.isinf(expected):
            assert math.isinf(actual) and (math.copysign(1, actual) == math.copysign(1, expected)), \
                f"FAIL: {a} + {b} = {actual}, expected {expected}"
        else:
            assert abs(actual - expected) < 1e-2, f"FAIL: {a} + {b} = {actual}, expected {expected}"

        dut._log.info(f"PASS: {a} + {b} = {actual}")
