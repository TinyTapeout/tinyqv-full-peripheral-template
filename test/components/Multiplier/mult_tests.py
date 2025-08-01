import cocotb
from cocotb.triggers import RisingEdge
from cocotb.clock import Clock
import numpy as np
import math

def float_to_half_bits(f):
    """Converts Python float to IEEE-754 half-precision bits (stored in lower 16 bits of 32-bit word)."""
    return int(np.float16(f).view(np.uint16)) & 0xFFFF

def half_bits_to_float(bits):
    """Converts lower 16 bits of 32-bit word to Python float (half-precision)."""
    return float(np.uint16(bits).view(np.float16))

async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.valid_in.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

async def apply_and_wait(dut, a_float, b_float):
    a_bits = float_to_half_bits(a_float)
    b_bits = float_to_half_bits(b_float)

    dut.a.value = a_bits  # packed in lower 16 bits
    dut.b.value = b_bits
    dut.valid_in.value = 1

    await RisingEdge(dut.clk)
    dut.valid_in.value = 0

    for _ in range(20):
        await RisingEdge(dut.clk)
        if dut.valid_out.value:
            break

    result_bits = int(dut.result.value) & 0xFFFF
    return half_bits_to_float(result_bits)

@cocotb.test()
async def test_fpu_mul_normal(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    tests = [
        (3.5, 1.25, 4.375),
        (2.0, 2.0, 4.0),
        (0.5, 0.5, 0.25),
        (1.0, 0.0001, 0.0001),
        (10.0, 0.1, 1.0),
        (5.0, 5.0, 25.0)
    ]
    for a, b, expected in tests:
        actual = await apply_and_wait(dut, a, b)
        assert abs(actual - expected) < 1e-2, f"FAIL: {a} * {b} = {actual}, expected {expected}"
        dut._log.info(f"PASS: {a} * {b} = {actual}")

@cocotb.test()
async def test_fpu_mul_with_signs(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    tests = [
        (-2.0, 2.0, -4.0),
        (-1.0, -1.0, 1.0),
        (1.5, -2.0, -3.0),
        (-3.0, -3.0, 9.0),
        (0.0, -10.0, 0.0),
        (-0.0, 0.0, 0.0),
    ]
    for a, b, expected in tests:
        actual = await apply_and_wait(dut, a, b)
        assert abs(actual - expected) < 1e-2, f"FAIL: {a} * {b} = {actual}, expected {expected}"
        dut._log.info(f"PASS: {a} * {b} = {actual}")

@cocotb.test()
async def test_fpu_mul_edge_cases(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    nan = float('nan')
    inf = float('inf')
    tests = [
        (inf, 1.0, inf),
        (1.0, inf, inf),
        (-1.0, inf, -inf),
        (inf, -1.0, -inf),
        (inf, inf, inf),
        (-inf, -inf, inf),
        (-inf, inf, -inf),
        (nan, 1.0, nan),
        (1.0, nan, nan),
        (0.0, inf, nan),
        (inf, 0.0, nan),
        (0.0, 0.0, 0.0)
    ]
    for a, b, expected in tests:
        actual = await apply_and_wait(dut, a, b)
        if math.isnan(expected):
            assert math.isnan(actual), f"FAIL: {a} * {b} = {actual}, expected NaN"
        elif math.isinf(expected):
            assert math.isinf(actual) and (math.copysign(1, actual) == math.copysign(1, expected)), \
                f"FAIL: {a} * {b} = {actual}, expected {expected}"
        else:
            assert abs(actual - expected) < 1e-2, f"FAIL: {a} * {b} = {actual}, expected {expected}"
        dut._log.info(f"PASS: {a} * {b} = {actual}")
