# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

"""PE.v wrapper testbench.

Confirms that the thin PE wrapper exposes the underlying ISA_Decoder
behavior unchanged: ADD, EINSUM matmul kernel, error_flag and
lower_required all propagate from the inner decoder out to the PE
boundary. This guarantees Cluster.v can instantiate PE.v without losing
any decoder semantics.
"""

import os
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

_REPO = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_REPO, 'asm'))
from wavetensor_asm import assemble_one  # noqa: E402

from test_isa_decoder import (  # noqa: E402
    eh_port, eh_imm16, eh_subscript, eh_opref, axes,
    encode_instr, make_tag, pack16, F_HAS_OPB,
)


PORT_MASK = 0x01
PORT_OUT  = 0x00


def _std_tag(dim=0):
    return make_tag(port_context_id=0, dimension_sizes=dim)


async def _reset(dut):
    dut.rst.value = 1
    dut.in_valid.value = 0
    dut.in_b_valid.value = 0
    dut.in_instruction.value = 0
    dut.in_tag.value = 0
    dut.in_payload.value = 0
    dut.in_b_payload.value = 0
    await Timer(15, units="ns")
    dut.rst.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")


async def _fire(dut, instr, tag, payload_a=0, payload_b=0, payload_b_valid=0):
    dut.in_instruction.value = instr
    dut.in_tag.value = tag
    dut.in_payload.value = payload_a
    dut.in_b_payload.value = payload_b
    dut.in_b_valid.value = payload_b_valid
    dut.in_valid.value = 1
    await RisingEdge(dut.clk)
    dut.in_valid.value = 0
    # Poll for completion: chain walk + dispatch + optional multi-cycle pipe.
    for _ in range(80):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if (int(dut.out_valid.value) == 1
                or int(dut.error_flag.value) == 1
                or int(dut.lower_required.value) == 1):
            break


@cocotb.test()
async def test_pe_add_passthrough(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    instr = assemble_one(
        f".default_port mask={PORT_MASK:#x} out={PORT_OUT}\n"
        "ADD .imm16 5\n"
    )
    await _fire(dut, instr, _std_tag(), payload_a=10)

    assert dut.out_valid.value == 1
    assert int(dut.out_payload.value) == 15
    assert dut.error_flag.value == 0
    assert dut.lower_required.value == 0


@cocotb.test()
async def test_pe_einsum_matmul(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    a = pack16(1, 2, 3, 4)
    b = pack16(5, 6, 7, 8)
    expected = pack16(19, 22, 43, 50)

    instr = assemble_one(
        f".default_port mask={PORT_MASK:#x} out={PORT_OUT}\n"
        "EINSUM opb .subscript A=i,j B=j,k O=i,k .opref\n"
    )
    await _fire(dut, instr, _std_tag(dim=0x05),
                payload_a=a, payload_b=b, payload_b_valid=1)
    assert dut.out_valid.value == 1
    assert int(dut.out_payload.value) == expected


@cocotb.test()
async def test_pe_lower_required_propagates(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    # An unsupported subscript (all label-d, axes(4)) raises lower_required
    instr = encode_instr(
        0x32,
        eh_port(PORT_MASK, PORT_OUT),
        eh_subscript(axes(4), axes(4), axes(4)),
        eh_opref(),
        flags=F_HAS_OPB,
    )
    await _fire(dut, instr, _std_tag(),
                payload_a=0, payload_b=0, payload_b_valid=1)
    assert dut.lower_required.value == 1
    assert dut.error_flag.value == 0


@cocotb.test()
async def test_pe_error_flag_propagates(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    instr = assemble_one(
        f".default_port mask={PORT_MASK:#x} out={PORT_OUT}\n"
        "DIV .imm16 0\n"
    )
    await _fire(dut, instr, _std_tag(), payload_a=42)
    assert dut.error_flag.value == 1
    assert dut.out_valid.value == 0
