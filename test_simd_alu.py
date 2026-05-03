# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

"""SIMD_ALU cocotb testbench.

Exercises the lane-parallel scalar ALU at its actual instantiation width
(ADDR_WIDTH=64, SIMD_WIDTH=4 → 256-bit packed vector).  The earlier
testbench mistakenly treated each lane as 32-bit, producing values that
silently truncated against the 64-bit lane datapath.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

ADDR_WIDTH = 64
SIMD_WIDTH = 4
LANE_MASK  = (1 << ADDR_WIDTH) - 1


def pack_lanes(*lanes):
    """Pack up to SIMD_WIDTH 64-bit lane values into the wide vector."""
    if len(lanes) > SIMD_WIDTH:
        raise ValueError("too many lanes")
    v = 0
    for i, l in enumerate(lanes):
        v |= (l & LANE_MASK) << (i * ADDR_WIDTH)
    return v


def lane_at(vec, idx):
    return (vec >> (idx * ADDR_WIDTH)) & LANE_MASK


async def reset(dut):
    dut.rst.value = 1
    dut.opcode.value = 0
    dut.precision_mode.value = 0
    dut.input_payload_vec.value = 0
    dut.imm_offset.value = 0
    await Timer(15, units="ns")
    dut.rst.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")


async def drive(dut, opcode, vec, imm, precision_mode=0):
    dut.opcode.value = opcode
    dut.precision_mode.value = precision_mode
    dut.input_payload_vec.value = vec
    dut.imm_offset.value = imm
    # One rising edge captures inputs into the next-state combinational logic;
    # the second rising edge propagates the staged result onto the output.
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")


@cocotb.test()
async def test_simd_add(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    vec = pack_lanes(1, 2, 3, 4)
    await drive(dut, 0x10, vec, imm=5)
    out = int(dut.output_payload_vec.value)
    for i, expect in enumerate([6, 7, 8, 9]):
        assert lane_at(out, i) == expect, \
            f"ADD lane {i}: got {lane_at(out, i)}, want {expect}"
    assert dut.alu_valid.value == 1
    assert dut.div_zero_flag.value == 0


@cocotb.test()
async def test_simd_sub(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    vec = pack_lanes(100, 50, 20, 10)
    await drive(dut, 0x11, vec, imm=3)
    out = int(dut.output_payload_vec.value)
    for i, expect in enumerate([97, 47, 17, 7]):
        assert lane_at(out, i) == expect


@cocotb.test()
async def test_simd_mul_truncates_explicitly(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # Each lane × 7. 0x4000_0000_0000_0001 × 7 wraps across the 64-bit
    # boundary; verify that the explicit truncation matches Python's
    # 64-bit modular arithmetic.
    vec = pack_lanes(0x4000000000000001, 2, 3, 4)
    await drive(dut, 0x12, vec, imm=7)
    out = int(dut.output_payload_vec.value)
    expected = [(v * 7) & LANE_MASK for v in [0x4000000000000001, 2, 3, 4]]
    for i, e in enumerate(expected):
        assert lane_at(out, i) == e, \
            f"MUL lane {i}: got 0x{lane_at(out, i):016x}, want 0x{e:016x}"


@cocotb.test()
async def test_simd_div(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    vec = pack_lanes(100, 75, 50, 25)
    await drive(dut, 0x13, vec, imm=5)
    out = int(dut.output_payload_vec.value)
    for i, expect in enumerate([20, 15, 10, 5]):
        assert lane_at(out, i) == expect
    assert dut.div_zero_flag.value == 0


@cocotb.test()
async def test_simd_rem(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    vec = pack_lanes(101, 76, 51, 26)
    await drive(dut, 0x1C, vec, imm=5)
    out = int(dut.output_payload_vec.value)
    for i, expect in enumerate([1, 1, 1, 1]):
        assert lane_at(out, i) == expect


@cocotb.test()
async def test_simd_div_by_zero_is_safe(dut):
    """When imm_offset is zero, DIV/REM must produce 0 (not X) and the
    div_zero_flag must rise — no synthesis-unsafe behavior."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    vec = pack_lanes(100, 50, 25, 10)
    await drive(dut, 0x13, vec, imm=0)
    out = int(dut.output_payload_vec.value)
    for i in range(4):
        assert lane_at(out, i) == 0, f"DIV-by-0 lane {i} not zero"
    assert dut.div_zero_flag.value == 1
    assert dut.alu_valid.value == 1


@cocotb.test()
async def test_simd_rem_by_zero_is_safe(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    vec = pack_lanes(7, 8, 9, 10)
    await drive(dut, 0x1C, vec, imm=0)
    out = int(dut.output_payload_vec.value)
    for i in range(4):
        assert lane_at(out, i) == 0
    assert dut.div_zero_flag.value == 1


@cocotb.test()
async def test_simd_bit_reverse(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    vec = pack_lanes(1, 2, 4, 8)
    await drive(dut, 0x1F, vec, imm=0)
    out = int(dut.output_payload_vec.value)
    expected = [
        1 << 63,  # bit_reverse(1)
        1 << 62,  # bit_reverse(2)
        1 << 61,  # bit_reverse(4)
        1 << 60,  # bit_reverse(8)
    ]
    for i, e in enumerate(expected):
        assert lane_at(out, i) == e, \
            f"BITREV lane {i}: got 0x{lane_at(out, i):016x}, want 0x{e:016x}"


@cocotb.test()
async def test_simd_default_opcode_is_zero(dut):
    """Unrecognized opcodes must not propagate stale data."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    vec = pack_lanes(0xDEADBEEF, 0xCAFEBABE, 0x12345678, 0xABCDEF01)
    await drive(dut, 0xFF, vec, imm=0)
    out = int(dut.output_payload_vec.value)
    for i in range(4):
        assert lane_at(out, i) == 0
    assert dut.div_zero_flag.value == 0
