# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

"""Pod.v testbench.

Default geometry is (CLUSTER_ROWS=2, CLUSTER_COLS=2) × (PE_ROWS=2,
PE_COLS=2) = 16 PEs/Pod, sufficient to exercise:

  * Routing of an external token to a specific Cluster via tag's
    port_context_id[7:4].
  * Routing within the selected Cluster via port_context_id[3:0].
  * Aggregation of error_flag and lower_required across Clusters.

The same binary that addresses Cluster 0 / PE 0 (port_context_id=0x00)
will route to Cluster 3 / PE 2 simply by setting port_context_id=0x32 —
demonstrating topology-independence at the binary level.
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
    # Phase 2: drive a stable RNG word for tests that don't exercise OPREF.
    # Tests that use src_kind=2 will override this before _fire().
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
async def test_pod_routes_to_cluster0_pe0(dut):
    """port_context_id = 0x00 → Cluster 0, PE 0 → ADD fires there."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    instr = encode_instr(0x10,
                         eh_port(input_port_mask=0x01, output_port_id=0),
                         eh_imm16(5))
    await _fire(dut, instr, _tag(port_context_id=0x00), payload_a=10)
    assert dut.ext_out_valid.value == 1
    assert int(dut.ext_out_payload.value) == 15


@cocotb.test()
async def test_pod_routes_to_cluster1_pe2(dut):
    """port_context_id = 0x12 → Cluster 1, PE 2."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    # mask=0x04 picks pcid[3:0]==2 inside the chosen Cluster.
    instr = encode_instr(0x10,
                         eh_port(input_port_mask=0x04, output_port_id=2),
                         eh_imm16(7))
    await _fire(dut, instr, _tag(port_context_id=0x12), payload_a=20)
    assert dut.ext_out_valid.value == 1
    assert int(dut.ext_out_payload.value) == 27


@cocotb.test()
async def test_pod_routes_to_cluster3_pe3(dut):
    """port_context_id = 0x33 → Cluster 3, PE 3 (extreme corner)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    instr = encode_instr(0x10,
                         eh_port(input_port_mask=0x08, output_port_id=3),
                         eh_imm16(11))
    await _fire(dut, instr, _tag(port_context_id=0x33), payload_a=100)
    assert dut.ext_out_valid.value == 1
    assert int(dut.ext_out_payload.value) == 111


@cocotb.test()
async def test_pod_outside_cluster_drops(dut):
    """A cluster index outside the configured grid leaves output silent."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    instr = encode_instr(0x10,
                         eh_port(input_port_mask=0x01, output_port_id=0),
                         eh_imm16(5))
    # cluster_idx = 5, but only 4 clusters exist in default 2x2 grid
    await _fire(dut, instr, _tag(port_context_id=0x50), payload_a=10)
    assert dut.ext_out_valid.value == 0


@cocotb.test()
async def test_pod_einsum_matmul_e2e(dut):
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
    await _fire(dut, instr, _tag(port_context_id=0x00, dim=0x05),
                payload_a=a, payload_b=b, payload_b_valid=1)
    assert dut.ext_out_valid.value == 1
    assert int(dut.ext_out_payload.value) == expected


@cocotb.test()
async def test_pod_error_flag_aggregates(dut):
    """An error in any PE in any Cluster surfaces at the Pod boundary."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    # DIV by zero on Cluster 2, PE 0
    instr = encode_instr(0x13,
                         eh_port(input_port_mask=0x01, output_port_id=0),
                         eh_imm16(0))
    await _fire(dut, instr, _tag(port_context_id=0x20), payload_a=99)
    assert dut.any_error_flag.value == 1


@cocotb.test()
async def test_pod_lower_required_aggregates(dut):
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
    await _fire(dut, instr, _tag(port_context_id=0x10),
                payload_a=0, payload_b=0, payload_b_valid=1)
    assert dut.any_lower_required.value == 1
    assert dut.any_error_flag.value == 0
