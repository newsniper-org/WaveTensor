# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

"""ALU_Extended cocotb testbench.

Covers:
  * Cfloat32 multiplication with signed values (the reason cfloat32_mul was
    rewritten with explicit `signed` declarations).
  * Each supported precision mode: Int4 (0x01), Int128 packed (0x0A),
    Cfloat32 (0x20), Qfloat64 (0x30), Gauss8 (0x40).
  * Each unary FP opcode (FLOOR/ROUND/CEIL/EUCLID_NORM/CONJUGATE).
  * The arbitration rule: when opcode is in 0x40..0x44 the unary path wins;
    otherwise the precision-mode path drives the result.
  * Unrecognized precision mode produces zero, not stale data.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

MASK64 = (1 << 64) - 1
MASK32 = (1 << 32) - 1


def pack_complex(re, im):
    """Pack signed (re, im) 32-bit values into a 64-bit complex word."""
    return (((re & MASK32) << 32) | (im & MASK32)) & MASK64


async def reset(dut):
    dut.rst.value = 1
    dut.opcode.value = 0
    dut.precision_mode.value = 0
    dut.input_a.value = 0
    dut.input_b.value = 0
    await Timer(15, units="ns")
    dut.rst.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")


async def drive(dut, opcode, precision_mode, a, b=0):
    dut.opcode.value = opcode
    dut.precision_mode.value = precision_mode
    dut.input_a.value = a
    dut.input_b.value = b
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")


# =============================================================================
# Precision-mode binary arithmetic
# =============================================================================

@cocotb.test()
async def test_int4_add(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    await drive(dut, opcode=0x10, precision_mode=0x01, a=7, b=5)
    assert int(dut.result.value) == 12
    assert dut.alu_valid.value == 1


@cocotb.test()
async def test_int128_packed_add(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a = (1 << 32) | 0x10
    b = (2 << 32) | 0x20
    await drive(dut, opcode=0x10, precision_mode=0x0A, a=a, b=b)
    expected = (3 << 32) | 0x30
    assert int(dut.result.value) == expected


@cocotb.test()
async def test_cfloat32_mul_positive(dut):
    """(1 + 2i) * (3 + 4i) = (3 - 8) + (4 + 6)i = -5 + 10i."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a = pack_complex(1, 2)
    b = pack_complex(3, 4)
    await drive(dut, opcode=0x12, precision_mode=0x20, a=a, b=b)
    expected = pack_complex(-5, 10)
    got = int(dut.result.value)
    assert got == expected, \
        f"Cfloat32 MUL got 0x{got:016x}, want 0x{expected:016x}"


@cocotb.test()
async def test_cfloat32_mul_signed_negative(dut):
    """(-2 + 0i) * (3 + 0i) = -6 + 0i. Validates signed multiply path."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a = pack_complex(-2, 0)
    b = pack_complex(3, 0)
    await drive(dut, opcode=0x12, precision_mode=0x20, a=a, b=b)
    expected = pack_complex(-6, 0)
    got = int(dut.result.value)
    assert got == expected, \
        f"Signed Cfloat32 got 0x{got:016x}, want 0x{expected:016x}"


@cocotb.test()
async def test_cfloat32_mul_pure_imag(dut):
    """(0 + 2i) * (0 + 3i) = -6 + 0i. Imaginary-only path."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a = pack_complex(0, 2)
    b = pack_complex(0, 3)
    await drive(dut, opcode=0x12, precision_mode=0x20, a=a, b=b)
    expected = pack_complex(-6, 0)
    assert int(dut.result.value) == expected


@cocotb.test()
async def test_qfloat64_add(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    await drive(dut, opcode=0x10, precision_mode=0x30,
                a=0x1111_2222_3333_4444, b=0x1000_0000_0000_0001)
    assert int(dut.result.value) == 0x2111_2222_3333_4445


@cocotb.test()
async def test_gauss8_add(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    await drive(dut, opcode=0x10, precision_mode=0x40, a=10, b=15)
    assert int(dut.result.value) == 25


@cocotb.test()
async def test_unsupported_precision_yields_zero(dut):
    """Unknown precision_mode must produce 0, not stale state."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    await drive(dut, opcode=0x10, precision_mode=0x77, a=99, b=88)
    assert int(dut.result.value) == 0


# =============================================================================
# Unary FP opcodes
# =============================================================================

@cocotb.test()
async def test_floor_passthrough(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    await drive(dut, opcode=0x40, precision_mode=0x12, a=5, b=0)
    assert int(dut.result.value) == 5


@cocotb.test()
async def test_round_passthrough(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    await drive(dut, opcode=0x41, precision_mode=0, a=42, b=0)
    assert int(dut.result.value) == 42


@cocotb.test()
async def test_ceil_passthrough(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    await drive(dut, opcode=0x42, precision_mode=0, a=7, b=0)
    assert int(dut.result.value) == 7


@cocotb.test()
async def test_euclid_norm_squared(dut):
    """re² + im² for a 32+32 complex. (3, 4) → 9 + 16 = 25."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a = pack_complex(3, 4)
    await drive(dut, opcode=0x43, precision_mode=0, a=a, b=0)
    assert int(dut.result.value) == 25


@cocotb.test()
async def test_euclid_norm_signed(dut):
    """(-3)² + (-4)² = 25. Validates the signed * signed inside euclid_norm."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a = pack_complex(-3, -4)
    await drive(dut, opcode=0x43, precision_mode=0, a=a, b=0)
    assert int(dut.result.value) == 25


@cocotb.test()
async def test_conjugate_negates_imag(dut):
    """conj(3 + 4i) = 3 - 4i."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a = pack_complex(3, 4)
    expected = pack_complex(3, -4)
    await drive(dut, opcode=0x44, precision_mode=0, a=a, b=0)
    assert int(dut.result.value) == expected


@cocotb.test()
async def test_conjugate_zero_imag(dut):
    """conj(5 + 0i) = 5 - 0i = 5 + 0i. Negation of zero must remain zero."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a = pack_complex(5, 0)
    await drive(dut, opcode=0x44, precision_mode=0, a=a, b=0)
    assert int(dut.result.value) == pack_complex(5, 0)


# =============================================================================
# Arbitration: unary opcodes win over precision_mode path
# =============================================================================

@cocotb.test()
async def test_unary_wins_over_precision(dut):
    """When opcode == 0x44 (CONJUGATE) and precision_mode == 0x01 (Int4 ADD),
    the unary path must win — earlier the second `case` in the always block
    silently overrode the first, but only by accident; the new arbitration
    is explicit."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a = pack_complex(7, 11)
    await drive(dut, opcode=0x44, precision_mode=0x01, a=a, b=99)
    assert int(dut.result.value) == pack_complex(7, -11)
