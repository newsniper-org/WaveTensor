# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

"""Cluster.v cocotb testbench.

Default geometry is (PE_ROWS=2, PE_COLS=2) → 4 PEs. The tests verify:

  * A token whose tag.port_context_id selects PE n is executed by exactly
    that PE; results land at the Cluster boundary.
  * Each of the 4 PEs in the default 2×2 grid can be addressed.
  * Aggregated diagnostics (any_error_flag, any_lower_required) propagate.

Topology-independence is exercised implicitly: the same assembled binary
addresses different PEs purely by changing the tag's port_context_id.
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
    encode_instr, eh_port, eh_imm16, eh_subscript, eh_opref, axes,
    make_tag, pack16, F_HAS_OPB,
)


def _tag(port_context_id, dim=0):
    return make_tag(port_context_id=port_context_id, dimension_sizes=dim)


async def _reset(dut):
    dut.rst.value = 1
    dut.ext_valid.value = 0
    dut.ext_payload_b_valid.value = 0
    dut.ext_instruction.value = 0
    dut.ext_tag.value = 0
    dut.ext_payload.value = 0
    dut.ext_payload_b.value = 0
    # Phase 2 RNG broadcast inputs — tests overriding OPREF.src_kind=2
    # set rng_word/rng_word_valid before _fire().
    dut.rng_word.value = 0
    dut.rng_word_valid.value = 0
    await Timer(15, units="ns")
    dut.rst.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")


async def _fire(dut, instr, tag, payload_a=0, payload_b=0, payload_b_valid=0):
    dut.ext_instruction.value = instr
    dut.ext_tag.value = tag
    dut.ext_payload.value = payload_a
    dut.ext_payload_b.value = payload_b
    dut.ext_payload_b_valid.value = payload_b_valid
    dut.ext_valid.value = 1
    await RisingEdge(dut.clk)
    dut.ext_valid.value = 0
    for _ in range(80):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if (int(dut.ext_out_valid.value) == 1
                or int(dut.any_error_flag.value) == 1
                or int(dut.any_lower_required.value) == 1):
            break


@cocotb.test()
async def test_cluster_routes_to_pe0(dut):
    """port_context_id=0 must hit PE(0,0) which fires the ADD."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    # Build an instruction with PORT mask matching pcid=0
    instr = encode_instr(0x10, eh_port(input_port_mask=0x01, output_port_id=0),
                         eh_imm16(5))
    await _fire(dut, instr, _tag(port_context_id=0), payload_a=10)

    assert dut.ext_out_valid.value == 1
    assert int(dut.ext_out_payload.value) == 15


@cocotb.test()
async def test_cluster_routes_to_pe1(dut):
    """port_context_id=1 must hit PE(1,0). Same binary, different tag."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    # mask=0x02 (bit 1) matches pcid=1
    instr = encode_instr(0x10, eh_port(input_port_mask=0x02, output_port_id=1),
                         eh_imm16(7))
    await _fire(dut, instr, _tag(port_context_id=1), payload_a=20)

    assert dut.ext_out_valid.value == 1
    assert int(dut.ext_out_payload.value) == 27


@cocotb.test()
async def test_cluster_routes_to_pe2_and_pe3(dut):
    """All four PEs in a 2×2 grid are reachable purely by addressing."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    # PE 2 (PE_X=0, PE_Y=1, idx=2)
    instr2 = encode_instr(0x10, eh_port(input_port_mask=0x04, output_port_id=2),
                          eh_imm16(11))
    await _fire(dut, instr2, _tag(port_context_id=2), payload_a=100)
    assert int(dut.ext_out_payload.value) == 111

    # PE 3 (PE_X=1, PE_Y=1, idx=3)
    instr3 = encode_instr(0x10, eh_port(input_port_mask=0x08, output_port_id=3),
                          eh_imm16(1))
    await _fire(dut, instr3, _tag(port_context_id=3), payload_a=42)
    assert int(dut.ext_out_payload.value) == 43


@cocotb.test()
async def test_cluster_outside_pcid_silently_drops(dut):
    """A tag.port_context_id outside the grid (e.g., 7 in a 4-PE cluster) hits
    no PE, leaving ext_out_valid low."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    instr = encode_instr(0x10, eh_port(input_port_mask=0x80, output_port_id=7),
                         eh_imm16(5))
    await _fire(dut, instr, _tag(port_context_id=7), payload_a=10)
    assert dut.ext_out_valid.value == 0


@cocotb.test()
async def test_cluster_einsum_matmul_runs_on_pe0(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    a = pack16(1, 2, 3, 4)
    b = pack16(5, 6, 7, 8)
    expected = pack16(19, 22, 43, 50)

    instr = assemble_one(
        ".default_port mask=0x01 out=0\n"
        "EINSUM opb .subscript A=i,j B=j,k O=i,k .opref\n"
    )
    await _fire(dut, instr, _tag(port_context_id=0, dim=0x05),
                payload_a=a, payload_b=b, payload_b_valid=1)

    assert dut.ext_out_valid.value == 1
    assert int(dut.ext_out_payload.value) == expected


@cocotb.test()
async def test_cluster_error_flag_propagates(dut):
    """An error in any PE should surface at any_error_flag."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    # DIV by zero on PE 0
    instr = assemble_one(
        ".default_port mask=0x01 out=0\n"
        "DIV .imm16 0\n"
    )
    await _fire(dut, instr, _tag(port_context_id=0), payload_a=99)
    assert dut.any_error_flag.value == 1
    assert dut.ext_out_valid.value == 0


@cocotb.test()
async def test_cluster_lower_required_propagates(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    instr = encode_instr(
        0x32,
        eh_port(input_port_mask=0x01, output_port_id=0),
        eh_subscript(axes(4), axes(4), axes(4)),
        eh_opref(),
        flags=F_HAS_OPB,
    )
    await _fire(dut, instr, _tag(port_context_id=0),
                payload_a=0, payload_b=0, payload_b_valid=1)
    assert dut.any_lower_required.value == 1
    assert dut.any_error_flag.value == 0


# =============================================================================
# Stage-21 — NoC routing for OPERAND_REF src_kind=1
# =============================================================================

@cocotb.test()
async def test_cluster_noc_routing_pe0_to_pe1(dut):
    """PE 0 produces a value in cycle T; PE 1 consumes it from bank[0] in
    cycle T+1 via OPREF.src_kind=1, OPREF.noc_route=0.
    No physical PE coordinate is ever named in the binary — the routing is
    decided entirely by the Cluster's bank-lookup."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    # ----- Cycle T: PE 0 fires ADD .imm16 5 with payload_a=10 → output 15
    instr_p = encode_instr(0x10,
                           eh_port(input_port_mask=0x01, output_port_id=0),
                           eh_imm16(5))
    await _fire(dut, instr_p, _tag(port_context_id=0), payload_a=10)
    # Sanity: PE 0's output appears at the cluster boundary
    assert int(dut.ext_out_payload.value) == 15

    # ----- Cycle T+1: PE 1 reads bank[0] (= PE 0's output, now 15) as B
    # ADD with OPREF.src_kind=1, OPREF.noc_route=0 → in_b_payload = bank[0] = 15
    instr_c = encode_instr(0x10,
                           eh_port(input_port_mask=0x02, output_port_id=1),
                           eh_opref(src_kind=1, noc_route=0),
                           flags=F_HAS_OPB)
    # Drive ext_payload_b with garbage to verify it's NOT used
    await _fire(dut, instr_c, _tag(port_context_id=1),
                payload_a=100, payload_b=0xDEAD, payload_b_valid=0)
    assert dut.ext_out_valid.value == 1
    # 100 + 15 (from bank[0]) = 115
    assert int(dut.ext_out_payload.value) == 115


@cocotb.test()
async def test_cluster_noc_routing_topology_independent(dut):
    """Same producer→consumer chain runs unchanged regardless of which
    physical PE pair is chosen. Here we use (PE 2 → PE 3) instead of
    (PE 0 → PE 1) and verify identical end-to-end behavior."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    # Producer on PE 2: ADD .imm16 7 with payload_a=20 → 27
    instr_p = encode_instr(0x10,
                           eh_port(input_port_mask=0x04, output_port_id=2),
                           eh_imm16(7))
    await _fire(dut, instr_p, _tag(port_context_id=2), payload_a=20)
    assert int(dut.ext_out_payload.value) == 27

    # Consumer on PE 3: ADD opb .opref kind=1 route=2 → reads bank[2] = 27
    instr_c = encode_instr(0x10,
                           eh_port(input_port_mask=0x08, output_port_id=3),
                           eh_opref(src_kind=1, noc_route=2),
                           flags=F_HAS_OPB)
    await _fire(dut, instr_c, _tag(port_context_id=3),
                payload_a=200, payload_b=0xBAD, payload_b_valid=0)
    assert dut.ext_out_valid.value == 1
    # 200 + 27 = 227
    assert int(dut.ext_out_payload.value) == 227


@cocotb.test()
async def test_cluster_src_kind_0_unaffected(dut):
    """When src_kind=0, the Cluster must use ext_payload_b directly,
    bypassing the bank entirely."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    instr = encode_instr(0x10,
                         eh_port(input_port_mask=0x01, output_port_id=0),
                         eh_opref(src_kind=0),
                         flags=F_HAS_OPB)
    await _fire(dut, instr, _tag(port_context_id=0),
                payload_a=10, payload_b=33, payload_b_valid=1)
    assert int(dut.ext_out_payload.value) == 43


# =============================================================================
# Phase 2 — OPREF.src_kind=2 (TRNG bank)
# =============================================================================

@cocotb.test()
async def test_cluster_src_kind_2_pulls_rng(dut):
    """OPREF.src_kind=2 → cluster reads `rng_word` for the B operand.
    ADD with payload_a=100 + rng_word=0x55 should produce 100 + 0x55 = 0x99
    on PE 0, regardless of ext_payload_b."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    # Drive a known RNG word — XOR'd with garbage ext_payload_b to verify
    # ext_payload_b is *not* consulted on src_kind=2.
    dut.rng_word.value = 0x55
    dut.rng_word_valid.value = 1

    instr = encode_instr(0x10,
                         eh_port(input_port_mask=0x01, output_port_id=0),
                         eh_opref(src_kind=2),
                         flags=F_HAS_OPB)
    await _fire(dut, instr, _tag(port_context_id=0),
                payload_a=100, payload_b=0xDEAD, payload_b_valid=0)
    assert dut.ext_out_valid.value == 1
    assert int(dut.ext_out_payload.value) == (100 + 0x55)


@cocotb.test()
async def test_cluster_src_kind_3_rejected(dut):
    """src_kind=3 (and beyond) must trip `opref_kind_unsupported` →
    error_flag rises, no output."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    instr = encode_instr(0x10,
                         eh_port(input_port_mask=0x01, output_port_id=0),
                         eh_opref(src_kind=3),
                         flags=F_HAS_OPB)
    await _fire(dut, instr, _tag(port_context_id=0),
                payload_a=10, payload_b=20, payload_b_valid=1)
    assert dut.any_error_flag.value == 1
    assert dut.ext_out_valid.value == 0
