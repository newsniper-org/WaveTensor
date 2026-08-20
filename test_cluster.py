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
    encode_instr, eh_port, eh_imm16, eh_mem, eh_subscript, eh_opref, axes,
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
    # v1.5.1 §18 — default single-fragment for all legacy tests.
    dut.ext_frag_hdr.value = 0
    # Phase 2 RNG broadcast inputs — tests overriding OPREF.src_kind=2
    # set rng_word/rng_word_valid before _fire().
    dut.rng_word.value = 0
    dut.rng_word_valid.value = 0
    await Timer(15, units="ns")
    dut.rst.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")


async def _fire(dut, instr, tag, payload_a=0, payload_b=0, payload_b_valid=0,
                frag_hdr=0):
    dut.ext_instruction.value = instr
    dut.ext_tag.value = tag
    dut.ext_payload.value = payload_a
    dut.ext_payload_b.value = payload_b
    dut.ext_payload_b_valid.value = payload_b_valid
    dut.ext_frag_hdr.value = frag_hdr
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
        ".default_port dest=0x01\n"
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
        ".default_port dest=0x01\n"
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


# =============================================================================
# v1.5.1 §18 — Fragment reassembly buffer
# =============================================================================
#
# Cluster.v hosts a single-slot fragment buffer. Legacy single-fragment
# (ext_frag_hdr = 0x00) bypasses; multi-fragment sequences accumulate and
# the wide payload assembles combinationally on the last fragment's cycle.
# Downstream is not yet consuming — v1.5.2 will thread `frag_reass_wide`
# into EHDecode's dec_input_payload path.


async def _drive_fragment(dut, tag, payload, frag_hdr, instruction=0):
    """Drive one wave-token fragment for one cycle. Instruction is
    irrelevant for the buffer under test but must be a legitimate value
    (an ADD op) so that op-classifiers don't glitch."""
    dut.ext_instruction.value = instruction
    dut.ext_tag.value = tag
    dut.ext_payload.value = payload
    dut.ext_payload_b.value = 0
    dut.ext_payload_b_valid.value = 0
    dut.ext_frag_hdr.value = frag_hdr
    dut.ext_valid.value = 1
    await RisingEdge(dut.clk)
    dut.ext_valid.value = 0


@cocotb.test()
async def test_frag_buffer_single_fragment_bypasses(dut):
    """Legacy single-fragment (frag_hdr=0x00) must not touch the buffer.
    frag_active must remain 0 throughout the operation."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    instr = encode_instr(0x10, eh_port(input_port_mask=0x01, output_port_id=0),
                         eh_imm16(5))
    await _fire(dut, instr, _tag(port_context_id=0), payload_a=10)
    assert dut.ext_out_valid.value == 1
    # Buffer state MUST be untouched (frag_hdr defaults to 0 in _fire)
    assert int(dut.frag_active.value) == 0


@cocotb.test()
async def test_frag_buffer_two_fragments_assemble(dut):
    """Send two fragments of a 2-fragment wave. On the second fragment's
    cycle, frag_reass_valid must pulse and frag_reass_wide must hold
    {frag1_payload, frag0_payload} in the low 128 bits."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    frag0 = 0x1122334455667788
    frag1 = 0xAABBCCDDEEFF0011
    tag = _tag(port_context_id=0)

    # Fragment 0 of 2: idx=0, total-1=1 → frag_hdr = 0x01
    await _drive_fragment(dut, tag, frag0, frag_hdr=0x01)
    await Timer(1, units="ns")
    # After the cycle: buffer active, mask = bit 0 set
    assert int(dut.frag_active.value) == 1
    # v1.6.5c: frag_mask is now a per-slot array (FRAG_SLOTS-indexed);
    # slot 0 at the default FRAG_SLOTS=1.
    assert int(dut.frag_mask[0].value) == 0b0001

    # Fragment 1 of 2: idx=1, total-1=1 → frag_hdr = 0x11
    dut.ext_instruction.value = 0
    dut.ext_tag.value = tag
    dut.ext_payload.value = frag1
    dut.ext_payload_b.value = 0
    dut.ext_payload_b_valid.value = 0
    dut.ext_frag_hdr.value = 0x11
    dut.ext_valid.value = 1
    # Sample frag_reass_valid combinationally BEFORE the edge (it's a wire
    # that reflects the arriving fragment). Wait a delta to settle.
    await Timer(1, units="ns")
    assert int(dut.frag_reass_valid.value) == 1
    wide = int(dut.frag_reass_wide.value)
    assert (wide & ((1 << 64) - 1)) == frag0
    assert ((wide >> 64) & ((1 << 64) - 1)) == frag1
    # Upper slots must be zero (unused)
    assert (wide >> 128) == 0

    await RisingEdge(dut.clk)
    dut.ext_valid.value = 0
    dut.ext_frag_hdr.value = 0
    await Timer(1, units="ns")
    # v1.6.5c §22.16: at FRAG_SLOTS=1 (default) completion still
    # unconditionally clears (byte-for-byte v1.5.1 behavior). At
    # FRAG_SLOTS>1 the slot instead persists (frag_ready) — see
    # test_frag_slots_persistent_no_clear for that assertion.
    if len(dut.frag_active.value) == 1:
        assert int(dut.frag_active.value) == 0
        assert int(dut.frag_mask[0].value) == 0


@cocotb.test()
async def test_frag_buffer_out_of_order_arrival(dut):
    """IPv6-style fragmentation allows out-of-order arrival. Send fragment
    idx=1 first, then idx=0. Reassembly must still produce the correct
    ordered payload."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    lo = 0xDEADBEEF12345678
    hi = 0xCAFEBABE87654321
    tag = _tag(port_context_id=0)

    # Send fragment 1 (idx=1) first
    await _drive_fragment(dut, tag, hi, frag_hdr=0x11)
    await Timer(1, units="ns")
    assert int(dut.frag_active.value) == 1
    assert int(dut.frag_mask[0].value) == 0b0010  # bit 1 set

    # Then fragment 0 — completes the wave
    dut.ext_instruction.value = 0
    dut.ext_tag.value = tag
    dut.ext_payload.value = lo
    dut.ext_frag_hdr.value = 0x01
    dut.ext_valid.value = 1
    await Timer(1, units="ns")
    assert int(dut.frag_reass_valid.value) == 1
    wide = int(dut.frag_reass_wide.value)
    # Ordered payload: idx 0 in low, idx 1 in high
    assert (wide & ((1 << 64) - 1)) == lo
    assert ((wide >> 64) & ((1 << 64) - 1)) == hi

    await RisingEdge(dut.clk)
    dut.ext_valid.value = 0


@cocotb.test()
async def test_frag_buffer_four_fragments_assemble(dut):
    """4-fragment wave (total-1=3) — verify the mask accumulates correctly
    and the reassembly window opens on the 4th arrival."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    frags = [0x0000000000000000 | (i << 56) | i
             for i in range(1, 5)]  # 4 distinctive 64-bit values
    tag = _tag(port_context_id=0)

    for idx in range(4):
        # frag_hdr = idx << 4 | (total-1=3)
        frag_hdr = (idx << 4) | 0x3
        dut.ext_instruction.value = 0
        dut.ext_tag.value = tag
        dut.ext_payload.value = frags[idx]
        dut.ext_payload_b.value = 0
        dut.ext_payload_b_valid.value = 0
        dut.ext_frag_hdr.value = frag_hdr
        dut.ext_valid.value = 1
        await Timer(1, units="ns")
        if idx == 3:
            # Last fragment: reassembly must pulse this cycle
            assert int(dut.frag_reass_valid.value) == 1
            wide = int(dut.frag_reass_wide.value)
            for j in range(4):
                slot = (wide >> (j * 64)) & ((1 << 64) - 1)
                assert slot == frags[j], f"slot {j}: {slot:016x} != {frags[j]:016x}"
        await RisingEdge(dut.clk)

    dut.ext_valid.value = 0
    dut.ext_frag_hdr.value = 0
    await Timer(1, units="ns")
    # v1.6.5c §22.16: FRAG_SLOTS=1-specific destructive-clear; at
    # FRAG_SLOTS>1 the slot persists instead (see
    # test_frag_slots_persistent_no_clear).
    if len(dut.frag_active.value) == 1:
        assert int(dut.frag_active.value) == 0


# =============================================================================
# v1.5.2 §19 — Fragment buffer → EHDecode wide-payload threading
# =============================================================================
#
# frag_reass_wide + frag_reass_valid feed EHDecode's input_payload_wide.
# EHDecode's in_valid is now gated by `wave_complete = (frag_hdr==0x00) ||
# frag_reass_valid`, so intermediate fragments no longer trigger chain
# walk. Legacy single-fragment path is unchanged.


@cocotb.test()
async def test_wave_complete_gates_intermediate_fragments(dut):
    """v1.5.2: intermediate fragments (frag_reass_valid=0) must NOT trigger
    EHDecode's chain walk. Verify u_ehdec.stg_active stays 0 during
    fragment accumulation."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    tag = _tag(port_context_id=0)
    instr = encode_instr(0x10, eh_port(input_port_mask=0x01, output_port_id=0),
                         eh_imm16(0))
    frag0 = 0x1111222233334444

    # Fragment 0 of 2 — buffer captures but EHDecode MUST NOT start walking
    await _drive_fragment(dut, tag, frag0, frag_hdr=0x01, instruction=instr)
    await Timer(1, units="ns")
    assert int(dut.u_ehdec.stg_active.value) == 0


@cocotb.test()
async def test_fragment_completion_feeds_ehdecode_wide(dut):
    """v1.5.2: send 2-fragment wave. After completion EHDecode's chain walk
    fires and dec_input_payload_wide latches the reassembled wide payload."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    tag = _tag(port_context_id=0)
    instr = encode_instr(0x10, eh_port(input_port_mask=0x01, output_port_id=0),
                         eh_imm16(0))
    frag0 = 0xAAAAA5A5CAFEBABE
    frag1 = 0x5555F0F0DEADBEEF

    # Fragment 0
    await _drive_fragment(dut, tag, frag0, frag_hdr=0x01, instruction=instr)
    # Fragment 1 — completes the wave and triggers EHDecode
    dut.ext_instruction.value = instr
    dut.ext_tag.value = tag
    dut.ext_payload.value = frag1
    dut.ext_payload_b.value = 0
    dut.ext_payload_b_valid.value = 0
    dut.ext_frag_hdr.value = 0x11
    dut.ext_valid.value = 1
    await RisingEdge(dut.clk)
    dut.ext_valid.value = 0
    dut.ext_frag_hdr.value = 0

    # Wait for chain walk + PE dispatch (~7 cycles)
    for _ in range(20):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.ext_out_valid.value) == 1:
            break

    wide = int(dut.u_ehdec.dec_input_payload_wide.value)
    assert (wide & ((1 << 64) - 1)) == frag0, \
        f"slot0: {wide & ((1<<64)-1):016x} != {frag0:016x}"
    assert ((wide >> 64) & ((1 << 64) - 1)) == frag1, \
        f"slot1: {(wide>>64) & ((1<<64)-1):016x} != {frag1:016x}"
    assert int(dut.u_ehdec.dec_input_payload_wide_valid.value) == 1


# =============================================================================
# v1.5.3b §20 — SIG_BMM_3 end-to-end via Cluster fabric
# =============================================================================
#
# Cluster fragment buffer reassembles 4 input fragments (A_lo, A_hi, B_lo,
# B_hi) into dec_input_payload_wide[255:0]. PE_Core (MU instance since 0x32
# is a mul_op) dispatches SIG_BMM_3 and emits 2 output fragments through
# the OR-merge to ext_out_*.


_BMM3_A_LO_S = 0x4321
_BMM3_B_LO_S = 0x5321
_BMM3_O_LO_S = 0x4321
_BMM3_A_HI_S = 0x0005
_BMM3_B_HI_S = 0x0006
_BMM3_O_HI_S = 0x0006


def _bmm_3_expected(a_128, b_128):
    """Python reference matching PE_Core.v matmul_2x2_int4 for SIG_BMM_3."""
    def s4(x):
        x &= 0xF
        return x - 16 if x & 0x8 else x
    def mm_2x2(a, b):
        a00, a01, a10, a11 = s4(a & 0xF), s4((a >> 4) & 0xF), s4((a >> 8) & 0xF), s4((a >> 12) & 0xF)
        b00, b01, b10, b11 = s4(b & 0xF), s4((b >> 4) & 0xF), s4((b >> 8) & 0xF), s4((b >> 12) & 0xF)
        r00 = (a00 * b00 + a01 * b10) & 0xF
        r01 = (a00 * b01 + a01 * b11) & 0xF
        r10 = (a10 * b00 + a11 * b10) & 0xF
        r11 = (a10 * b01 + a11 * b11) & 0xF
        return (r11 << 12) | (r10 << 8) | (r01 << 4) | r00
    def sub(v, i):
        return (v >> (i * 16)) & 0xFFFF
    r = [mm_2x2(sub(a_128, i), sub(b_128, i)) for i in range(8)]
    lo = r[0] | (r[1] << 16) | (r[2] << 32) | (r[3] << 48)
    hi = r[4] | (r[5] << 16) | (r[6] << 32) | (r[7] << 48)
    return lo, hi


@cocotb.test()
async def test_bmm_3_end_to_end_via_cluster(dut):
    """v1.5.3b: send 4 input fragments (A_lo,A_hi,B_lo,B_hi) into Cluster,
    verify 2 output fragments (0x01, 0x11) exit ext_out with correct payload
    and matching tag."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    # Distinctive A and B per-batch
    a_128 = 0
    b_128 = 0
    for i in range(8):
        a_128 |= ((0x2100 + i) & 0xFFFF) << (i * 16)
        b_128 |= ((0x1200 + i * 3) & 0xFFFF) << (i * 16)

    tag = _tag(port_context_id=0)
    # SIG_BMM_3 instruction with 2 SUBSCRIPT EHs + OPREF
    instr = encode_instr(0x32,
                         eh_port(input_port_mask=0x01, output_port_id=0),
                         eh_subscript(_BMM3_A_LO_S, _BMM3_B_LO_S, _BMM3_O_LO_S),
                         eh_subscript(_BMM3_A_HI_S, _BMM3_B_HI_S, _BMM3_O_HI_S),
                         eh_opref(),
                         flags=F_HAS_OPB)

    # Emit 4 fragments (idx 0..3, total-1 = 3):
    #   idx 0 → wide[63:0]    = A[63:0]
    #   idx 1 → wide[127:64]  = A[127:64]
    #   idx 2 → wide[191:128] = B[63:0]
    #   idx 3 → wide[255:192] = B[127:64]
    payloads = [
        a_128 & ((1 << 64) - 1),
        (a_128 >> 64) & ((1 << 64) - 1),
        b_128 & ((1 << 64) - 1),
        (b_128 >> 64) & ((1 << 64) - 1),
    ]
    for idx in range(4):
        frag_hdr = (idx << 4) | 0x3
        dut.ext_instruction.value = instr
        dut.ext_tag.value = tag
        dut.ext_payload.value = payloads[idx]
        dut.ext_payload_b.value = 0
        dut.ext_payload_b_valid.value = 1
        dut.ext_frag_hdr.value = frag_hdr
        dut.ext_valid.value = 1
        await RisingEdge(dut.clk)
    dut.ext_valid.value = 0
    dut.ext_frag_hdr.value = 0

    # Wait for first ext_out fragment
    saw_frag0 = None
    for _ in range(30):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.ext_out_valid.value) == 1:
            saw_frag0 = {
                'payload': int(dut.ext_out_payload.value),
                'frag_hdr': int(dut.ext_out_frag_hdr.value),
                'tag': int(dut.ext_out_tag.value),
            }
            break
    assert saw_frag0 is not None, "no ext_out fragment observed"
    assert saw_frag0['frag_hdr'] == 0x01, f"frag0 hdr {saw_frag0['frag_hdr']:02x}"

    # Next cycle: fragment 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    saw_frag1 = {
        'payload': int(dut.ext_out_payload.value),
        'frag_hdr': int(dut.ext_out_frag_hdr.value),
        'valid': int(dut.ext_out_valid.value),
        'tag': int(dut.ext_out_tag.value),
    }
    assert saw_frag1['valid'] == 1
    assert saw_frag1['frag_hdr'] == 0x11

    # Verify math
    exp_lo, exp_hi = _bmm_3_expected(a_128, b_128)
    assert saw_frag0['payload'] == exp_lo, \
        f"frag0 {saw_frag0['payload']:016x} != {exp_lo:016x}"
    assert saw_frag1['payload'] == exp_hi, \
        f"frag1 {saw_frag1['payload']:016x} != {exp_hi:016x}"

    # Tag stability: both fragments share the same tag bits
    assert saw_frag0['tag'] == saw_frag1['tag']


@cocotb.test()
async def test_bmm_3_cluster_frag_hdr_returns_to_zero(dut):
    """v1.5.3b: after fragment 1, ext_out_frag_hdr must snap back to 0x00
    (NRZ hazard) — otherwise a following legacy single-frag primitive
    would surface with a stale 0x11 header."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    a_128 = 0
    b_128 = 0
    for i in range(8):
        a_128 |= 0x1111 << (i * 16)
        b_128 |= 0x2222 << (i * 16)

    tag = _tag(port_context_id=0)
    instr = encode_instr(0x32,
                         eh_port(input_port_mask=0x01, output_port_id=0),
                         eh_subscript(_BMM3_A_LO_S, _BMM3_B_LO_S, _BMM3_O_LO_S),
                         eh_subscript(_BMM3_A_HI_S, _BMM3_B_HI_S, _BMM3_O_HI_S),
                         eh_opref(),
                         flags=F_HAS_OPB)
    payloads = [a_128 & ((1<<64)-1), (a_128>>64) & ((1<<64)-1),
                b_128 & ((1<<64)-1), (b_128>>64) & ((1<<64)-1)]
    for idx in range(4):
        dut.ext_instruction.value = instr
        dut.ext_tag.value = tag
        dut.ext_payload.value = payloads[idx]
        dut.ext_payload_b.value = 0
        dut.ext_payload_b_valid.value = 1
        dut.ext_frag_hdr.value = (idx << 4) | 0x3
        dut.ext_valid.value = 1
        await RisingEdge(dut.clk)
    dut.ext_valid.value = 0
    dut.ext_frag_hdr.value = 0

    # Advance until frag0 seen
    for _ in range(30):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.ext_out_valid.value) == 1:
            break
    assert int(dut.ext_out_frag_hdr.value) == 0x01
    # Cycle N+1: frag1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.ext_out_frag_hdr.value) == 0x11
    # Cycle N+2: NRZ back to 0x00
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.ext_out_valid.value) == 0
    assert int(dut.ext_out_frag_hdr.value) == 0x00


# =============================================================================
# v1.5.5 §21 — SIG_TRACE_IIJKL end-to-end via Cluster fabric
# =============================================================================
#
# 2 input fragments (A_lo, A_hi) → Cluster fragment buffer reassembles
# into wide[127:0] → PE_Core (MU) dispatches SIG_TRACE_IIJKL → 1 output
# fragment (frag_hdr=0x00, no FSM). Result payload is 32-bit (upper 32
# bits = 0), output_tag carries dim_sizes=0x15 (3D 2×2×2).


_TRIIJKL_A_LO_S = 0x3211
_TRIIJKL_B_LO_S = 0x0000
_TRIIJKL_O_LO_S = 0x0432
_TRIIJKL_A_HI_S = 0x0004
_TRIIJKL_B_HI_S = 0x0000
_TRIIJKL_O_HI_S = 0x0000


def _trace_iijkl_expected(a_128):
    """Python reference for SIG_TRACE_IIJKL (mirror of PE_Core.v)."""
    def s4(x):
        x &= 0xF
        return x - 16 if x & 0x8 else x
    r = [0] * 8
    for j in range(2):
        for k in range(2):
            for l in range(2):
                acc = 0
                for i in range(2):
                    lin = i * 16 + i * 8 + j * 4 + k * 2 + l
                    acc += s4((a_128 >> (lin * 4)) & 0xF)
                r[j * 4 + k * 2 + l] = acc & 0xF
    out = 0
    for idx, n in enumerate(r):
        out |= (n & 0xF) << (idx * 4)
    return out


@cocotb.test()
async def test_trace_iijkl_end_to_end_via_cluster(dut):
    """v1.5.5: send 2 input fragments (A_lo, A_hi) carrying the 128-bit
    5D A tensor. Cluster reassembles, MU dispatches SIG_TRACE_IIJKL,
    output emerges as SINGLE ext_out fragment (frag_hdr=0x00) with
    32-bit reduction result and dim_sizes=0x15 in the tag."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    # Distinctive nibbles across 128-bit A
    a_128 = 0
    for lin in range(32):
        a_128 |= ((lin * 5 + 2) & 0xF) << (lin * 4)

    tag = _tag(port_context_id=0)
    instr = encode_instr(0x32,
                         eh_port(input_port_mask=0x01, output_port_id=0),
                         eh_subscript(_TRIIJKL_A_LO_S, _TRIIJKL_B_LO_S, _TRIIJKL_O_LO_S),
                         eh_subscript(_TRIIJKL_A_HI_S, _TRIIJKL_B_HI_S, _TRIIJKL_O_HI_S),
                         eh_opref(),
                         flags=F_HAS_OPB)

    # Emit 2 fragments (idx 0..1, total-1 = 1):
    #   idx 0 → wide[63:0]   = A[63:0]
    #   idx 1 → wide[127:64] = A[127:64]
    payloads = [a_128 & ((1 << 64) - 1), (a_128 >> 64) & ((1 << 64) - 1)]
    for idx in range(2):
        dut.ext_instruction.value = instr
        dut.ext_tag.value = tag
        dut.ext_payload.value = payloads[idx]
        dut.ext_payload_b.value = 0
        dut.ext_payload_b_valid.value = 1
        dut.ext_frag_hdr.value = (idx << 4) | 0x1   # total-1 = 1
        dut.ext_valid.value = 1
        await RisingEdge(dut.clk)
    dut.ext_valid.value = 0
    dut.ext_frag_hdr.value = 0

    # Wait for the SINGLE output fragment
    saw = None
    for _ in range(30):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.ext_out_valid.value) == 1:
            saw = {
                'payload':  int(dut.ext_out_payload.value),
                'frag_hdr': int(dut.ext_out_frag_hdr.value),
                'tag':      int(dut.ext_out_tag.value),
            }
            break

    assert saw is not None, "no ext_out fragment observed"
    # Single-fragment output — NOT 0x01 (that would indicate FSM engagement)
    assert saw['frag_hdr'] == 0x00, f"expected single frag_hdr 0x00, got 0x{saw['frag_hdr']:02x}"
    # Math matches Python reference
    expected = _trace_iijkl_expected(a_128)
    assert (saw['payload'] & 0xFFFFFFFF) == expected, \
        f"payload {saw['payload'] & 0xFFFFFFFF:08x} != {expected:08x}"
    # Only low 32 bits used
    assert (saw['payload'] >> 32) == 0
    # Output tag carries 3D dim_sizes = 0x15
    assert (saw['tag'] & 0xFF) == 0x15

    # NRZ: cycle N+1 must snap back to idle (no phantom fragment 1)
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.ext_out_valid.value) == 0
    assert int(dut.ext_out_frag_hdr.value) == 0x00

    # Cluster diagnostics clean (no error, no lower)
    assert int(dut.any_error_flag.value) == 0
    assert int(dut.any_lower_required.value) == 0


# =============================================================================
# v1.5.3 §20 (adversarial review bug 3+4) — 출력 충돌 `any_output_collision`
#
# Cluster.v 의 출력 병합은 **원자적 우선순위 중재**다: MU > DU > L-PE[0..N-1].
# 한 사이클에 둘 이상의 소스가 요청하면 승자 하나만 데이터 채널과 메모리
# 채널을 **함께** 구동하고, 패배한 소스는 `m_output_collision` 을 올리며
# 그것이 다시 `any_error_flag` 로 폴딩된다 (Cluster.v: `m_err = m_err |
# m_output_collision`).
#
# 왜 다시 썼는가
# --------------
# 구 테스트 `test_bmm_3_lpe_collision_raises_output_collision` 은 이 폴딩을
# **한 번도 검증하지 못했다**. 함수 전체에 assert 가 0건이었고 30 사이클
# 폴링 뒤 `if saw_collision: pass` 로 끝났다 — DUT 가 `any_output_collision`
# 을 0 에 묶어도 그대로 통과하는, 조용히 통과하는 검사였다.
#
# 게다가 그 테스트가 만들려던 정렬(MU 조각 방출 창 ↔ L-PE ADD 완료)은
# **이 지오메트리에서 도달 자체가 불가능**하다. 실측 근거:
#
#   * L-PE 의 비-mul·비-div 연산은 전부 지연이 7 사이클로 동일하다
#     (주입 에지 기준; ADD/SUB/AND/SHL/0x20/0x21/0x51/0x52 … 전수 확인).
#   * MU 의 SIG_BMM_3 는 마지막 입력 조각 에지 기준 +7 / +8 두 사이클에
#     조각 0x01 / 0x11 을 방출한다.
#   * ⇒ 두 출력을 같은 사이클에 놓으려면 ADD 를 4-조각 버스트가 점유 중인
#     사이클에 주입해야 하는데, ext 포트는 사이클당 명령 1개만 받는다.
#     구 테스트를 주입 지연 0..15 로 전수 스윕해도 충돌은 **0건**이었다.
#
# 무엇을 지렛대로 쓰는가
# ----------------------
# **DU(제산기)의 지연이 비대칭적으로 길다** — 0x13 DIV = 73 사이클,
# 0x1D DIVMOD = 41 (실측). 이 비대칭이 충돌을 결정론적으로 강제한다:
#
#   * MU 대 DU  : DIV 를 먼저 띄우고, DIV 완료 사이클에 MU 조각 0x01 이
#                 오도록 버스트를 배치 → MU 승 / DU 패 → collision.
#   * DU 대 L-PE: DIV 를 먼저 띄우고, DIV 완료 사이클에 ADD 완료가 오도록
#                 배치 → DU 승 / L-PE 패 → collision.
#
# 아래 세 테스트가 각각 (1) DU 패배 팔, (2) L-PE 패배 팔, (3) 트래픽이
# 겹치지 않을 때 **거짓 충돌이 나지 않을 것**(신호를 1 에 묶는 반대 방향의
# 축퇴)을 hard assert 한다. 지연 상수는 하드코딩하지 않고 매 실행마다
# 실측(calibration)해서 쓴다 — 숫자가 낡아 조용히 빗나가는 것이 바로 구
# 테스트를 무력화한 기전이기 때문이다.
# =============================================================================

_DIV_A = 100        # DIV 피제수
_DIV_B = 3          # DIV 제수 → 몫 33
_ADD_A = 42         # ADD 피가수
_ADD_IMM = 7        # ADD imm16 → 합 49


def _bmm3_stimulus():
    """SIG_BMM_3 (0x32) 명령 + 4개 입력 조각 + 원본 A/B 를 돌려준다."""
    a_128 = 0
    b_128 = 0
    for i in range(8):
        a_128 |= 0x1111 << (i * 16)
        b_128 |= 0x2222 << (i * 16)
    instr = encode_instr(0x32,
                         eh_port(input_port_mask=0x01, output_port_id=0),
                         eh_subscript(_BMM3_A_LO_S, _BMM3_B_LO_S, _BMM3_O_LO_S),
                         eh_subscript(_BMM3_A_HI_S, _BMM3_B_HI_S, _BMM3_O_HI_S),
                         eh_opref(),
                         flags=F_HAS_OPB)
    payloads = [a_128 & ((1 << 64) - 1), (a_128 >> 64) & ((1 << 64) - 1),
                b_128 & ((1 << 64) - 1), (b_128 >> 64) & ((1 << 64) - 1)]
    return instr, payloads, a_128, b_128


def _coll_div_instr(pcid):
    return encode_instr(0x13, eh_port(input_port_mask=(1 << pcid),
                                      output_port_id=pcid),
                        eh_imm16(_DIV_B), flags=F_HAS_OPB)


def _coll_add_instr(pcid):
    return encode_instr(0x10, eh_port(input_port_mask=(1 << pcid),
                                      output_port_id=pcid),
                        eh_imm16(_ADD_IMM))


async def _inject_single(dut, instr, tag, pa, pb=0, pbv=0):
    """단일 조각 명령 하나를 넣는다 (호출 반환 시점 = 주입 에지 직후)."""
    dut.ext_instruction.value = instr
    dut.ext_tag.value = tag
    dut.ext_payload.value = pa
    dut.ext_payload_b.value = pb
    dut.ext_payload_b_valid.value = pbv
    dut.ext_frag_hdr.value = 0
    dut.ext_valid.value = 1
    await RisingEdge(dut.clk)
    dut.ext_valid.value = 0


async def _calib_single_latency(dut, instr, tag, pa, pb=0, pbv=0, horizon=160):
    """주입 에지 → 첫 `ext_out_valid` 까지의 사이클 수를 실측한다."""
    await _reset(dut)
    await _inject_single(dut, instr, tag, pa, pb, pbv)
    for c in range(1, horizon):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.ext_out_valid.value) == 1:
            return c
    return None


async def _calib_bmm3_emit_offset(dut, instr, payloads, tag, horizon=60):
    """SIG_BMM_3 의 **마지막 입력 조각 에지** → 첫 출력 조각까지의 사이클 수."""
    await _reset(dut)
    for idx in range(4):
        dut.ext_instruction.value = instr
        dut.ext_tag.value = tag
        dut.ext_payload.value = payloads[idx]
        dut.ext_payload_b.value = 0
        dut.ext_payload_b_valid.value = 1
        dut.ext_frag_hdr.value = (idx << 4) | 0x3
        dut.ext_valid.value = 1
        await RisingEdge(dut.clk)     # idx==3 에지가 기준점(사이클 0)
    dut.ext_valid.value = 0
    dut.ext_frag_hdr.value = 0
    for c in range(1, horizon):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.ext_out_valid.value) == 1:
            return c
    return None


@cocotb.test()
async def test_output_collision_mu_beats_du_and_folds_into_error(dut):
    """v1.5.3 §20 — MU 대 DU 충돌을 **강제**한다.

    긴 DIV(DU) 를 먼저 띄우고, 그 완료 사이클에 SIG_BMM_3 의 조각 0x01
    방출이 겹치도록 4-조각 버스트를 배치한다. 원자적 중재는
      * MU(최우선)의 조각을 그대로 내보내고,
      * 패배한 DU 때문에 `any_output_collision` 을 올리며,
      * 그것을 `any_error_flag` 로 폴딩해야 한다.
    셋 중 하나라도 죽으면 FAIL 한다 (신호를 0 에 묶는 축퇴 차단)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    bmm3_instr, payloads, a_128, b_128 = _bmm3_stimulus()
    div_instr = _coll_div_instr(1)
    tag_div = _tag(port_context_id=1)
    tag_mu = _tag(port_context_id=0)

    # ---- calibration: 상수를 하드코딩하지 않는다 ----
    lat_div = await _calib_single_latency(dut, div_instr, tag_div,
                                          _DIV_A, _DIV_B, 1)
    assert lat_div is not None, "DIV(0x13)가 출력하지 않았다 — calibration 실패"
    emit = await _calib_bmm3_emit_offset(dut, bmm3_instr, payloads, tag_mu)
    assert emit is not None, "SIG_BMM_3 이 출력하지 않았다 — calibration 실패"
    assert lat_div - emit >= 4, (
        f"DIV 지연({lat_div})이 MU 방출 오프셋({emit})보다 충분히 길지 않아 "
        "버스트를 DIV 뒤에 배치할 수 없다 — 강제 정렬 전제가 깨졌다")

    # ---- 강제 정렬: DIV 를 사이클 0 에, MU 조각 0x01 이 +lat_div 에 오도록 ----
    burst_last = lat_div - emit
    burst_start = burst_last - 3

    await _reset(dut)
    await _inject_single(dut, div_instr, tag_div, _DIV_A, _DIV_B, 1)  # 사이클 0

    at_hit = None
    at_next = None
    collision_cycles = []
    for c in range(1, lat_div + 8):
        if burst_start <= c < burst_start + 4:
            idx = c - burst_start
            dut.ext_instruction.value = bmm3_instr
            dut.ext_tag.value = tag_mu
            dut.ext_payload.value = payloads[idx]
            dut.ext_payload_b.value = 0
            dut.ext_payload_b_valid.value = 1
            dut.ext_frag_hdr.value = (idx << 4) | 0x3
            dut.ext_valid.value = 1
        await RisingEdge(dut.clk)
        dut.ext_valid.value = 0
        dut.ext_frag_hdr.value = 0
        await Timer(1, units="ns")
        snap = {
            'valid': int(dut.ext_out_valid.value),
            'frag_hdr': int(dut.ext_out_frag_hdr.value),
            'payload': int(dut.ext_out_payload.value),
            'collision': int(dut.any_output_collision.value),
            'error': int(dut.any_error_flag.value),
        }
        if snap['collision'] == 1:
            collision_cycles.append(c)
        if c == lat_div:
            at_hit = snap
        elif c == lat_div + 1:
            at_next = snap

    exp_lo, exp_hi = _bmm_3_expected(a_128, b_128)

    assert at_hit is not None, "관측 창이 DIV 완료 사이클을 담지 못했다"
    assert at_hit['collision'] == 1, (
        f"사이클 {lat_div} 에서 MU 조각 0x01 과 DU 몫이 동시에 요청하도록 "
        f"강제했는데 any_output_collision 이 뜨지 않았다 — 충돌 검출이 죽어 "
        f"있다 (충돌 관측 사이클: {collision_cycles})")
    assert at_hit['error'] == 1, (
        "any_output_collision 이 any_error_flag 로 폴딩되지 않았다 "
        "(Cluster.v `m_err = m_err | m_output_collision`)")
    assert at_hit['valid'] == 1, "충돌 사이클에 출력이 통째로 사라졌다"
    assert at_hit['frag_hdr'] == 0x01, (
        f"우선순위 위반: MU(조각 0x01)가 이겨야 하는데 "
        f"frag_hdr={at_hit['frag_hdr']:02x}")
    assert at_hit['payload'] == exp_lo, (
        f"승자의 데이터 채널이 원자적이지 않다: payload "
        f"{at_hit['payload']:016x} != MU 조각0 {exp_lo:016x}")

    # 충돌은 정렬시킨 그 한 사이클에서만 나야 한다 — 신호를 1 에 묶는
    # 반대 방향의 축퇴를 여기서 막는다.
    assert collision_cycles == [lat_div], (
        f"충돌은 사이클 {lat_div} 단 한 번이어야 한다 — 관측 {collision_cycles}")

    # 바로 다음 사이클엔 MU 조각 0x11 이 충돌 없이 나온다.
    assert at_next is not None and at_next['valid'] == 1, \
        "MU 두 번째 조각이 나오지 않았다"
    assert at_next['frag_hdr'] == 0x11, \
        f"두 번째 조각 헤더 {at_next['frag_hdr']:02x} != 0x11"
    assert at_next['payload'] == exp_hi, (
        f"두 번째 조각 payload {at_next['payload']:016x} != {exp_hi:016x}")
    assert at_next['collision'] == 0, \
        "충돌이 다음 사이클까지 끌린다 — 1-사이클 펄스가 아니다"


@cocotb.test()
async def test_output_collision_du_beats_lpe_and_drops_loser(dut):
    """v1.5.3 §20 — DU 대 L-PE 충돌을 **강제**한다 (L-PE 패배 팔).

    긴 DIV(DU) 와 L-PE ADD 의 완료 사이클을 겹치도록 배치한다. DU 가
    우선순위상 이기므로 ADD 의 결과는 **버려져야** 하고, 바로 그 사실을
    알리기 위해 `any_output_collision` 이 떠야 한다. 패배자의 값이
    끝까지 한 번도 나타나지 않는 것까지 확인한다 — 충돌 플래그의 존재
    이유가 '조용히 버려진 출력'을 소프트웨어가 알아채게 하는 것이므로."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    div_instr = _coll_div_instr(1)
    add_instr = _coll_add_instr(2)
    tag_div = _tag(port_context_id=1)
    tag_add = _tag(port_context_id=2)

    lat_div = await _calib_single_latency(dut, div_instr, tag_div,
                                          _DIV_A, _DIV_B, 1)
    assert lat_div is not None, "DIV(0x13)가 출력하지 않았다 — calibration 실패"
    lat_add = await _calib_single_latency(dut, add_instr, tag_add, _ADD_A)
    assert lat_add is not None, "ADD(0x10)가 출력하지 않았다 — calibration 실패"
    assert lat_div > lat_add, (
        f"DIV({lat_div}) 가 ADD({lat_add}) 보다 길어야 정렬을 강제할 수 있다")

    add_at = lat_div - lat_add          # 두 완료가 같은 사이클에 오도록
    await _reset(dut)
    await _inject_single(dut, div_instr, tag_div, _DIV_A, _DIV_B, 1)  # 사이클 0

    at_hit = None
    collision_cycles = []
    payloads_seen = []
    for c in range(1, lat_div + 12):
        if c == add_at:
            dut.ext_instruction.value = add_instr
            dut.ext_tag.value = tag_add
            dut.ext_payload.value = _ADD_A
            dut.ext_payload_b.value = 0
            dut.ext_payload_b_valid.value = 0
            dut.ext_frag_hdr.value = 0
            dut.ext_valid.value = 1
        await RisingEdge(dut.clk)
        dut.ext_valid.value = 0
        await Timer(1, units="ns")
        snap = {
            'valid': int(dut.ext_out_valid.value),
            'payload': int(dut.ext_out_payload.value),
            'collision': int(dut.any_output_collision.value),
            'error': int(dut.any_error_flag.value),
        }
        if snap['collision'] == 1:
            collision_cycles.append(c)
        if snap['valid'] == 1:
            payloads_seen.append(snap['payload'])
        if c == lat_div:
            at_hit = snap

    exp_div = _DIV_A // _DIV_B          # 33
    exp_add = _ADD_A + _ADD_IMM         # 49

    assert at_hit is not None, "관측 창이 DIV 완료 사이클을 담지 못했다"
    assert at_hit['collision'] == 1, (
        f"사이클 {lat_div} 에서 DU 몫과 L-PE ADD 결과가 동시에 요청하도록 "
        f"강제했는데 any_output_collision 이 뜨지 않았다 (충돌 관측: "
        f"{collision_cycles})")
    assert at_hit['error'] == 1, \
        "any_output_collision 이 any_error_flag 로 폴딩되지 않았다"
    assert at_hit['valid'] == 1, "충돌 사이클에 출력이 통째로 사라졌다"
    assert at_hit['payload'] == exp_div, (
        f"우선순위 위반: DU(몫 {exp_div})가 L-PE 를 이겨야 하는데 "
        f"payload={at_hit['payload']}")
    assert collision_cycles == [lat_div], (
        f"충돌은 사이클 {lat_div} 단 한 번이어야 한다 — 관측 {collision_cycles}")
    assert exp_add not in payloads_seen, (
        f"패배한 L-PE 결과 {exp_add} 가 출력에 나타났다 — 충돌 시나리오가 "
        f"성립하지 않았다 (관측 payload: {payloads_seen})")


@cocotb.test()
async def test_output_collision_stays_low_when_traffic_is_disjoint(dut):
    """v1.5.3 §20 — 거짓 충돌 금지 (반대 방향의 축퇴 차단).

    MU 의 SIG_BMM_3 두 조각과 L-PE ADD 의 결과가 **서로 다른 사이클**에
    나오는 배치에서는 `any_output_collision` 이 한 번도 뜨면 안 된다.
    위 두 테스트가 '신호를 0 에 묶는' 축퇴를 막는다면, 이 테스트는
    '신호를 1 에 묶는' 축퇴를 막는다. 세 출력이 전부 관측되는지까지
    확인하므로 자극이 사라져도 조용히 통과하지 않는다."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    bmm3_instr, payloads, a_128, b_128 = _bmm3_stimulus()
    add_instr = _coll_add_instr(1)
    tag_mu = _tag(port_context_id=0)
    tag_add = _tag(port_context_id=1)
    exp_lo, exp_hi = _bmm_3_expected(a_128, b_128)
    exp_add = _ADD_A + _ADD_IMM

    # NOTE(수리됨 — v1.9.2 §22.14b-3): 주입 지연 0..3 구간은 예전에 이
    # 스윕에서 **제외**돼 있었다. 그 구간에서는 `cluster_ready` 가 1 인데도
    # ADD 가 출력을 전혀 내지 않았기 때문이다 — 공유 EHDecode 체인 워크가
    # SIG_BMM_3 파동에 점유된 동안(MAX_EH=4 에지) 뒤따르는 명령이 배압도
    # 에러 비트도 없이 **소실**됐다. 그 회피 한정(`range(4, 16)`)은 결함을
    # 우회했을 뿐 아니라, 결함이 고쳐졌는지도 영원히 볼 수 없게 만들었다.
    #
    # Cluster 입력단 skid buffer 1단이 착지해 소실이 구조적으로 0 이
    # 됐으므로 **전 구간(0..15)을 복원한다.** 이제 delay 0..3 은 "출력이
    # 없다" 가 아니라 "보류 후 투입되어 정확히 1건 출력한다" 를 뜻하며,
    # 아래 by_hdr 검사(각 hdr 정확히 1건 + payload 일치)가 그것을 그대로
    # 강제한다.
    for delay in range(0, 16):
        await _reset(dut)
        for idx in range(4):
            dut.ext_instruction.value = bmm3_instr
            dut.ext_tag.value = tag_mu
            dut.ext_payload.value = payloads[idx]
            dut.ext_payload_b.value = 0
            dut.ext_payload_b_valid.value = 1
            dut.ext_frag_hdr.value = (idx << 4) | 0x3
            dut.ext_valid.value = 1
            await RisingEdge(dut.clk)     # idx==3 에지 = 사이클 0
        dut.ext_valid.value = 0
        dut.ext_frag_hdr.value = 0

        outs = []            # (cycle, frag_hdr, payload)
        collision_cycles = []
        for c in range(1, delay + 24):
            if c == delay + 1:
                dut.ext_instruction.value = add_instr
                dut.ext_tag.value = tag_add
                dut.ext_payload.value = _ADD_A
                dut.ext_payload_b.value = 0
                dut.ext_payload_b_valid.value = 0
                dut.ext_frag_hdr.value = 0
                dut.ext_valid.value = 1
            await RisingEdge(dut.clk)
            dut.ext_valid.value = 0
            await Timer(1, units="ns")
            if int(dut.any_output_collision.value) == 1:
                collision_cycles.append(c)
            if int(dut.ext_out_valid.value) == 1:
                outs.append((c, int(dut.ext_out_frag_hdr.value),
                             int(dut.ext_out_payload.value)))

        assert collision_cycles == [], (
            f"delay={delay}: 겹치지 않는 트래픽인데 any_output_collision 이 "
            f"떴다 (사이클 {collision_cycles}, 출력 {outs})")

        by_hdr = {}
        for cyc, hdr, pay in outs:
            by_hdr.setdefault(hdr, []).append((cyc, pay))
        for hdr, exp_pay in ((0x01, exp_lo), (0x11, exp_hi), (0x00, exp_add)):
            got = by_hdr.get(hdr, [])
            assert len(got) == 1, (
                f"delay={delay}: frag_hdr=0x{hdr:02x} 출력이 1건이어야 하는데 "
                f"{len(got)}건 (전체 {outs})")
            assert got[0][1] == exp_pay, (
                f"delay={delay}: frag_hdr=0x{hdr:02x} payload "
                f"{got[0][1]:#x} != {exp_pay:#x}")

        cycles = sorted(c for c, _, _ in outs)
        assert len(set(cycles)) == 3, (
            f"delay={delay}: 세 출력이 서로 다른 사이클이어야 한다 — {outs}")


# =============================================================================
# v1.9.2 §22.14b-3 — Cluster 입력단 skid buffer 1단.
#
# 무엇을 pin 하는가:
#   (a) test_skid_no_drop_during_ehdecode_blackout
#       공유 EHDecode 가 점유된 blackout 구간(kick 후 MAX_EH 에지)에 주입된
#       명령이 **소실되지 않는다**. 지연 0..MAX_EH 전 구간을 스윕하고, 각
#       지연에서 두 명령이 **각각 정확히 1회** 자기 값으로 나오는지 본다.
#       보류된 값이 live 값과 섞였는지도 payload 로 구분된다 (bit-identical).
#       기전(`cluster_ready` 가 보류 중 0, skid 점유)도 직접 확인한다 —
#       결과만 보면 "우연히 맞았다" 와 구분되지 않기 때문이다.
#   (b) test_skid_overflow_raises_sticky_fault
#       1단 skid 가 이미 점유된 상태에서 또 하나가 도착하면 **loud sticky
#       fault**. 조용히 사라지는 경로가 없다는 것이 이 수리의 요점이므로,
#       버려지는 경우까지 소리가 나는지 직접 본다.
#
# 왜 (a) 만으로 부족한가: (a) 는 skid 를 제거해도 "delay=4 만 통과" 로
# 부분 통과할 수 있는 형태가 아니어야 한다. 그래서 (a) 는 지연 0 부터
# 스윕하고 **모든** 지연에서 hard assert 한다. 반대로 (b) 가 없으면
# "보류 대신 그냥 버리되 조용히" 라는 축퇴가 (a) 를 통과할 수 있다
# (지연 1건만 보류해도 (a) 는 통과하므로).
# =============================================================================

_SKID_MAX_EH = 4        # Cluster 기본 파라미터. blackout 폭 = MAX_EH 에지.
_SKID_A_PAY = 42        # 선행 파동 payload → 결과 49
_SKID_B_PAY = 100       # ADD 기반 후행 파동 payload → 결과 107 (overflow 테스트)
_SKID_C_PAY = 61        # overflow 로 버려질 세 번째 파동 → 결과 68

# ---- 보류 대상 파동은 payload_b 를 **실제로 소비**해야 한다 ----------------
# 2026-08-18 적대 검증 항 1 이 실증한 사각: 보류 저장소 1,659b 중 1,585b 가
# 변이 사각이었다. 원인은 둘이었고 둘 다 자극의 문제였다.
#   (1) 주입 펄스 뒤 `ext_*` 버스를 **그대로 방치**해서, 투입 에지의 live
#       버스 값이 보류 값과 같아졌다 — 보류분을 쓰든 live 를 쓰든 결과가
#       같으므로 원리적으로 구분 불가였다 (변이 M5/M6/M7/M13/M14 생존).
#   (2) 두 파동이 모두 ADD-imm 이라 `payload_b` / `payload_b_valid` 를 아무도
#       읽지 않았다 — 그 65 비트는 자극 자체가 만들어 낸 적이 없었다.
# 아래 상수/헬퍼가 그 둘을 동시에 닫는다: 후행 파동은 TENSOR_ADD(0x31)로
# payload_b 를 소비하고, 주입 직후 버스는 **미끼 값**으로 덮인다.
_SKID_B_PCID = 1
_SKID_B_A = pack16(1, 2, 3, 4)
_SKID_B_B = pack16(10, 20, 30, 40)
_SKID_B_EXP = pack16(11, 22, 33, 44)

# ---- 미끼(decoy) ------------------------------------------------------------
# 주입 펄스 직후 `ext_*` 전 필드를 덮는 값. 구현이 보류분 대신 투입 시점의
# live 버스를 읽으면 그 오염이 결과/라우팅 태그로 **직접 관측**된다.
#   * instruction : **다른 opcode**(ADD 0x10)여야 한다. 같은 0x31 을 쓰면
#                   포트 필드만 달라져 결과값이 그대로여서 M5 가 산다.
#   * tag         : 다른 port_context_id → 라우팅/출력 태그가 갈린다 (M6).
#   * payload_b   : 다른 값 (M7).
#   * payload_b_valid : 보류분과 **반대 값** (M13). 이 1비트는 값이 아니라
#                   유효성이라 반대 값이 아니면 구분되지 않는다.
_SKID_DECOY_PCID = 3
_SKID_DECOY_A = 0xDEADBEEF0BADF00D
_SKID_DECOY_B = 0x1111222233334444


def _skid_tadd_instr(pcid):
    """TENSOR_ADD(0x31) — `input_payload_b` 를 실제로 읽는 명령."""
    return encode_instr(0x31, eh_port(input_port_mask=(1 << pcid),
                                      output_port_id=pcid),
                        eh_opref(), flags=F_HAS_OPB)


def _skid_decoy(dut):
    """`ext_*` 버스를 미끼로 덮는다 (ext_valid 는 0).

    **모든** 주입 펄스 뒤에 반드시 불러야 한다. 이것을 빠뜨리면 보류
    저장소의 대부분이 다시 변이 사각으로 돌아간다 (항 1)."""
    dut.ext_instruction.value = _coll_add_instr(_SKID_DECOY_PCID)
    dut.ext_tag.value = _tag(port_context_id=_SKID_DECOY_PCID, dim=0x05)
    dut.ext_payload.value = _SKID_DECOY_A
    dut.ext_payload_b.value = _SKID_DECOY_B
    dut.ext_payload_b_valid.value = 0
    dut.ext_frag_hdr.value = 0
    dut.ext_valid.value = 0


def _out_pcid(dut):
    """출력 태그의 port_context_id 하위 4비트 (= 라우팅 목적지)."""
    return (int(dut.ext_out_tag.value) >> 16) & 0xF


async def _skid_pulse(dut, instr, tag, payload, payload_b=0,
                      payload_b_valid=0):
    """ext_valid 를 **정확히 1 사이클**만 세워 한 파동을 주입하고, 그 직후
    버스를 미끼로 덮는다."""
    dut.ext_instruction.value = instr
    dut.ext_tag.value = tag
    dut.ext_payload.value = payload
    dut.ext_payload_b.value = payload_b
    dut.ext_payload_b_valid.value = payload_b_valid
    dut.ext_frag_hdr.value = 0
    dut.ext_valid.value = 1
    await RisingEdge(dut.clk)
    _skid_decoy(dut)


@cocotb.test()
async def test_skid_no_drop_during_ehdecode_blackout(dut):
    """v1.9.2 §22.14b-3 — blackout 구간 주입이 **소실되지 않는다**.

    구 RTL 에서는 `EHDecode` 체인 워크 중(`stg_active==1`) 도착한 명령이
    `EHDecode.v:195`/`:350` 양쪽 가드에 걸려 **어느 arm 에서도 읽히지
    않았다** — 큐 0 · 홀드 0 · 에러 비트 0 의 순수 소실. `cluster_ready`
    는 출력단만 보므로 그 순간에도 1 이었다.

    이 테스트는 지연 0..MAX_EH 전 구간에서 두 번째 명령이 **정확히 1회**
    자기 payload 로 나오는지 hard assert 한다. skid 를 제거하면 지연
    0..3 이 전부 "출력 1건 누락" 으로 사멸한다.

    **bit-identical 검사 (2026-08-18 항 1 수리)**: 주입 펄스 직후 버스를
    미끼로 덮으므로(`_skid_decoy`), 보류분 대신 투입 시점의 live 버스를
    읽는 구현은 값(payload_a / payload_b / payload_b_valid / opcode)이나
    라우팅 태그가 어긋나 여기서 죽는다. 후행 파동을 TENSOR_ADD 로 고른
    것도 같은 이유다 — ADD-imm 은 `payload_b` 65 비트를 읽지 않는다.

    **투입 시점 pin**: 지연 0..MAX_EH 의 **모든** 값에서 후행 파동의 출력
    사이클이 같아야 한다. 지연 MAX_EH 는 보류 없이 bypass 로 통과하는
    기준점이므로, 보류분 투입에 거품이 1 에지라도 끼면 그 기준점과
    어긋나 여기서 잡힌다 (= "in_ready 가 서는 **최초** 에지" 규범)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    instr_a = _coll_add_instr(0)
    instr_b = _skid_tadd_instr(_SKID_B_PCID)
    exp_a = _SKID_A_PAY + _ADD_IMM
    exp_b = _SKID_B_EXP
    assert exp_a != exp_b

    out_cycle_b = {}
    for delay in range(0, _SKID_MAX_EH + 1):
        await _reset(dut)
        # 선행 파동: 이 에지가 EHDecode kick (= 사이클 0 의 시작).
        await _skid_pulse(dut, instr_a, _tag(port_context_id=0), _SKID_A_PAY)

        outs = []
        ready_low_seen = False
        skid_held_seen = False
        for c in range(0, delay + 40):
            if c == delay:
                dut.ext_instruction.value = instr_b
                dut.ext_tag.value = _tag(port_context_id=_SKID_B_PCID,
                                         dim=0x05)
                dut.ext_payload.value = _SKID_B_A
                dut.ext_payload_b.value = _SKID_B_B
                dut.ext_payload_b_valid.value = 1
                dut.ext_frag_hdr.value = 0
                dut.ext_valid.value = 1
            await RisingEdge(dut.clk)
            # 주입 에지 직후 즉시 미끼로 덮는다 — 이 한 줄이 보류 저장소
            # 1,585 비트의 변이 사각을 없앤다 (항 1).
            _skid_decoy(dut)
            await Timer(1, units="ns")
            if int(dut.cluster_ready.value) == 0:
                ready_low_seen = True
            if int(dut.skid_valid.value) == 1:
                skid_held_seen = True
            if int(dut.ext_out_valid.value) == 1:
                outs.append((c, int(dut.ext_out_payload.value),
                             _out_pcid(dut)))

        got = [p for _, p, _ in outs]
        assert got.count(exp_a) == 1, (
            f"delay={delay}: 선행 파동 결과 {exp_a} 가 정확히 1회여야 하는데 "
            f"{got.count(exp_a)}회 (관측 {outs})")
        assert got.count(exp_b) == 1, (
            f"delay={delay}: **후행 파동이 소실/오염됐다** — 결과 "
            f"{exp_b:#x} 가 {got.count(exp_b)}회 (관측 "
            f"{[(c, hex(p), t) for c, p, t in outs]}). §22.14b-3 skid 보류가 "
            f"동작하지 않으면 delay 0..{_SKID_MAX_EH - 1} 이 여기서 죽고, "
            f"보류가 **부분적**이면 미끼 값이 섞여 여기서 죽는다")
        assert len(got) == 2, (
            f"delay={delay}: 출력이 정확히 2건이어야 한다 (중복 투입 금지) "
            f"— 관측 {[(c, hex(p), t) for c, p, t in outs]}")
        assert [p for _, p, _ in sorted(outs)] == [exp_a, exp_b], (
            f"delay={delay}: 프로그램 순서가 뒤집혔다 — {outs}")
        # 라우팅 태그까지 본다 — 값만 보면 `ehdec_tag` 보류가 사각이 된다
        # (미끼 태그로 라우팅되어도 산술 결과는 같을 수 있다).
        by_pay = {p: (c, t) for c, p, t in outs}
        assert by_pay[exp_a][1] == 0, (
            f"delay={delay}: 선행 파동이 pcid 0 이 아닌 "
            f"{by_pay[exp_a][1]} 로 나왔다 — {outs}")
        assert by_pay[exp_b][1] == _SKID_B_PCID, (
            f"delay={delay}: 보류 파동이 자기 태그가 아니라 미끼 태그로 "
            f"라우팅됐다 (pcid {by_pay[exp_b][1]}, 기대 {_SKID_B_PCID}) — "
            f"`ehdec_tag` 보류가 빠졌다는 뜻이다")
        assert int(dut.input_skid_overflow_error.value) == 0, (
            f"delay={delay}: 정상 보류인데 overflow fault 가 떴다")
        assert int(dut.any_error_flag.value) == 0, (
            f"delay={delay}: 정상 경로인데 any_error_flag 가 섰다")

        out_cycle_b[delay] = by_pay[exp_b][0]

        # 기전 직접 확인 — 결과만 보면 "우연히 맞았다" 와 구분이 안 된다.
        if delay < _SKID_MAX_EH:
            assert skid_held_seen, (
                f"delay={delay}: blackout 구간 주입인데 skid 가 한 번도 "
                f"점유되지 않았다 — bypass 로 통과했다면 EHDecode 가 "
                f"그것을 버렸어야 한다")
            assert ready_low_seen, (
                f"delay={delay}: skid 점유 중 cluster_ready 가 0 으로 "
                f"내려가지 않았다 — §22.14b-3 이 부여한 새 의미가 "
                f"배선되지 않았다")
        else:
            # §22.14b-3 규범: EHDecode 가 비어 있으면 파동은 **그대로
            # 통과**한다 (bypass mux — latency 델타 0). 상시 경유 레지스터
            # (cut ladder rung 2)로 축퇴하면 여기서 죽는다.
            assert not skid_held_seen, (
                f"delay={delay}: EHDecode 가 비어 있는 에지의 도착인데 skid 를 "
                f"경유했다 — §22.14b-3 의 bypass 규범 위반")

    # 투입 시점 pin — 보류분은 `in_ready` 가 서는 **최초** 에지에 들어간다.
    assert len(set(out_cycle_b.values())) == 1, (
        f"보류 파동의 출력 사이클이 지연에 따라 달라졌다: {out_cycle_b}. "
        f"delay={_SKID_MAX_EH} 는 보류 없이 통과하는 기준점이므로, 값이 "
        f"갈렸다는 것은 보류 경로가 거품을 1 에지 이상 넣었다는 뜻이다 "
        f"(§22.14b-3 은 '최초 에지' 를 규범으로 정한다)")


@cocotb.test()
async def test_skid_overflow_raises_sticky_fault(dut):
    """v1.9.2 §22.14b-3 — skid 2개째 도착 = **loud sticky fault**.

    1단 skid 는 blackout 창(MAX_EH 에지) 안에 도착하는 파동 1건까지만
    담는다. 그 상태에서 또 하나가 오면 담을 자리가 없다. 그 파동은
    버려지지만 **조용히 버려지지 않는다** — 이 수리의 요점이 "소실을
    없앨 수 없는 경계에서는 최소한 소리를 낸다" 이기 때문이다.

    검사 4건: (1) 두 번째까지는 fault 0, (2) 세 번째에서 1, (3) sticky
    (이후 계속 1) + `any_error_flag` 폴딩, (4) 리셋으로만 지워진다."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    instr_a = _coll_add_instr(0)
    instr_b = _coll_add_instr(1)
    instr_c = _coll_add_instr(2)
    exp_a = _SKID_A_PAY + _ADD_IMM
    exp_c = _SKID_C_PAY + _ADD_IMM

    await _reset(dut)
    assert int(dut.input_skid_overflow_error.value) == 0, \
        "리셋 직후 fault 가 이미 서 있다"

    # 사이클 0 의 시작 = kick. 이후 MAX_EH 에지 동안 in_ready=0.
    await _skid_pulse(dut, instr_a, _tag(port_context_id=0), _SKID_A_PAY)

    # 사이클 0: skid 로 보류된다 (아직 fault 없음).
    await _skid_pulse(dut, instr_b, _tag(port_context_id=1), _SKID_B_PAY)
    await Timer(1, units="ns")
    assert int(dut.skid_valid.value) == 1, \
        "두 번째 파동이 skid 에 보류되지 않았다 — 전제가 성립하지 않는다"
    assert int(dut.input_skid_overflow_error.value) == 0, \
        "보류 1건만으로 overflow fault 가 떴다 (신호가 1 에 묶인 축퇴)"
    assert int(dut.cluster_ready.value) == 0, \
        "skid 점유 중인데 cluster_ready 가 1 이다 — 바로 그 거짓말을 " \
        "§22.14b-3 이 없앴어야 한다"

    # 사이클 1: skid 가 이미 점유 → 3번째는 담을 자리가 없다.
    await _skid_pulse(dut, instr_c, _tag(port_context_id=2), _SKID_C_PAY)
    await Timer(1, units="ns")
    assert int(dut.input_skid_overflow_error.value) == 1, \
        "skid 가 찬 상태에서 도착한 파동이 **조용히** 사라졌다 — " \
        "loud-fault-never-silent 위반"
    assert int(dut.any_error_flag.value) == 1, \
        "overflow fault 가 any_error_flag 로 폴딩되지 않았다"

    # sticky: 이후 전 구간에서 1 을 유지하고, 버려진 파동은 실제로 안 나온다.
    outs = []
    for _ in range(60):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        assert int(dut.input_skid_overflow_error.value) == 1, \
            "fault 가 sticky 가 아니다 — 다음 idle 사이클에 흡수됐다"
        if int(dut.ext_out_valid.value) == 1:
            outs.append(int(dut.ext_out_payload.value))
    assert exp_c not in outs, (
        f"overflow 로 보고한 파동이 실제로는 실행됐다 — fault 가 거짓 "
        f"경보다 (관측 {outs})")
    # overflow 는 **버려지는 쪽**만 버린다 — 이미 보류돼 있던 파동은
    # 그대로 살아 나와야 한다. 이것이 없으면 "overflow 때 skid 를 통째로
    # 버린다" 는 축퇴가 통과한다.
    exp_b = _SKID_B_PAY + _ADD_IMM
    assert outs.count(exp_b) == 1, (
        f"overflow 사이클이 **이미 보류된** 파동까지 죽였다 — 기대 "
        f"{exp_b} 가 {outs.count(exp_b)}회 (관측 {outs})")
    assert outs.count(exp_a) == 1, (
        f"선행 파동 결과 {exp_a} 가 {outs.count(exp_a)}회 (관측 {outs})")

    # 리셋으로만 지워진다.
    await _reset(dut)
    assert int(dut.input_skid_overflow_error.value) == 0, \
        "리셋이 sticky fault 를 지우지 못했다"


def _bmm3_payloads(a_nib, b_nib):
    """SIG_BMM_3 용 A/B 를 임의 nibble 패턴으로 만든다 (조각 4개 + 원본)."""
    a_128 = 0
    b_128 = 0
    for i in range(8):
        a_128 |= (a_nib & 0xFFFF) << (i * 16)
        b_128 |= (b_nib & 0xFFFF) << (i * 16)
    payloads = [a_128 & ((1 << 64) - 1), (a_128 >> 64) & ((1 << 64) - 1),
                b_128 & ((1 << 64) - 1), (b_128 >> 64) & ((1 << 64) - 1)]
    return payloads, a_128, b_128


async def _skid_frag_beat(dut, instr, tag, payload, frag_hdr,
                          payload_b_valid=0):
    """조각 1개를 한 에지에 주입한다 (버스 정리는 호출자 몫)."""
    dut.ext_instruction.value = instr
    dut.ext_tag.value = tag
    dut.ext_payload.value = payload
    dut.ext_payload_b.value = 0
    dut.ext_payload_b_valid.value = payload_b_valid
    dut.ext_frag_hdr.value = frag_hdr
    dut.ext_valid.value = 1
    await RisingEdge(dut.clk)


async def _bmm3_beat(dut, instr, tag, payload, idx):
    """SIG_BMM_3 조각 1개를 한 에지에 주입한다 (버스는 호출자가 정리)."""
    await _skid_frag_beat(dut, instr, tag, payload, (idx << 4) | 0x3,
                          payload_b_valid=1)


def _skid_slot_of(dut, tag):
    """`tag` 를 담고 있는 CAM 슬롯 인덱스 (없으면 None)."""
    for i in range(_slots(dut)):
        if int(dut.frag_tag_reg[i].value) == tag:
            return i
    return None


def _skid_slot_released(dut, slot):
    """§22.14b-4 의 '철거' 가 실제로 일어났는가 — 빌드별 정의.

    FRAG_SLOTS=1 은 즉시 철거(`frag_active=0`), FRAG_SLOTS>1 은 persistent
    캐시로 승격(`frag_ready=1`)이 완료 형태다 (CAM always 블록의 두 갈래와
    문자 그대로 같다). 어느 쪽도 '아무것도 검사하지 않음' 이 아니다."""
    if _slots(dut) > 1:
        return (int(dut.frag_ready.value) >> slot) & 1 == 1
    return (int(dut.frag_active.value) >> slot) & 1 == 0


async def _bmm3_burst(dut, instr, tag, payloads):
    """4 조각을 연속 에지에 주입하고 버스를 **미끼로 덮는다**.

    미끼가 없으면 투입 에지에 `ext_tag` 가 아직 이 파동의 태그라서
    `hit_continue` 가 그대로 맞고, live `final_wide` 가 보류분과 같은
    값이 되어 `ehdec_wide` 1,024 비트가 통째로 변이 사각이 된다
    (2026-08-18 항 1 의 M14)."""
    for idx in range(4):
        await _bmm3_beat(dut, instr, tag, payloads[idx], idx)
    _skid_decoy(dut)


@cocotb.test()
async def test_skid_deferred_wave_releases_cam_slot(dut):
    """v1.9.2 §22.14b-4 — 보류된 다중 조각 파동의 **CAM 슬롯 회계**.

    철거를 accept 에 종속시키는 것만으로는 절반이다: accept 이 미뤄지면
    슬롯이 "완성됐는데 철거되지 않은" 상태로 남고, **같은 tag 로 재전송된
    파동의 첫 조각이 가득 찬 mask 에 병합돼 즉시 거짓 완성**한다 — 오늘
    존재하지 않는 오염이 새로 생긴다. 그래서 투입 에지에 deferred commit
    이 슬롯을 정확히 같은 형태로 처리해야 한다.

    자극: 선행 파동으로 EHDecode 를 점유시킨 뒤, blackout 창 안에서
    4-조각 SIG_BMM_3 를 완성시킨다 (→ 보류). 투입 후 **같은 tag** 로
    값이 다른 두 번째 SIG_BMM_3 를 재전송하고, 두 파동 모두 자기 값으로
    나오는지 본다. 슬롯 회계가 틀리면 두 번째가 첫 번째의 잔재와 섞여
    다른 값을 내거나 조각 수가 맞지 않는다."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    bmm3_instr, _, _, _ = _bmm3_stimulus()
    tag_mu = _tag(port_context_id=0)
    pay1, a1, b1 = _bmm3_payloads(0x1111, 0x2222)
    pay2, a2, b2 = _bmm3_payloads(0x3131, 0x1212)
    exp1 = _bmm_3_expected(a1, b1)
    exp2 = _bmm_3_expected(a2, b2)
    assert exp1 != exp2, "두 파동의 기대값이 같으면 오염을 구분할 수 없다"

    await _reset(dut)
    # 선행 파동(단일 조각 ADD)으로 EHDecode 를 점유시킨다.
    await _skid_pulse(dut, _coll_add_instr(1), _tag(port_context_id=1),
                      _SKID_A_PAY)
    # 사이클 0..3 = blackout. 4 조각이 그 안에서 완성된다 → 보류.
    await _bmm3_burst(dut, bmm3_instr, tag_mu, pay1)
    await Timer(1, units="ns")
    assert int(dut.skid_valid.value) == 1, \
        "완성 조각이 blackout 안에서 도착했는데 보류되지 않았다 — " \
        "자극의 타이밍 전제가 깨졌다"

    # ---- 기전 pin: 철거가 **투입 에지에** 실제로 일어나는가 ----
    # 결과값만 보면 §22.14b-4b(b)(완성 보류 슬롯 병합 금지)가 오염을 대신
    # 막아 주기 때문에 deferred commit 을 통째로 지워도 통과한다 (실측:
    # `skid_commit_now ≡ 0` 변이가 결과 검사만으로는 생존). 두 방어가
    # 서로를 가리므로 **각각을 기전으로** 못박는다.
    slot = _skid_slot_of(dut, tag_mu)
    assert slot is not None, "보류 파동의 CAM 슬롯을 찾지 못했다"
    assert not _skid_slot_released(dut, slot), (
        f"슬롯 {slot} 이 accept 전에 이미 철거됐다 — §22.14b-4 의 "
        f"accept 종속이 배선되지 않았다")
    await RisingEdge(dut.clk)               # = 보류분 투입 에지
    await Timer(1, units="ns")
    assert int(dut.skid_valid.value) == 0, \
        "전제 붕괴: 이 에지가 투입 에지가 아니다"
    assert _skid_slot_released(dut, slot), (
        f"투입 에지에 deferred CAM commit 이 일어나지 않았다 — 슬롯 "
        f"{slot} 이 '완성됐는데 철거되지 않은' 상태로 남았다. 재시도 경로가 "
        f"없으므로 이 상태는 영구다 (§22.14b-4b)")

    outs1 = []
    for _ in range(59):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.ext_out_valid.value) == 1:
            outs1.append((int(dut.ext_out_frag_hdr.value),
                          int(dut.ext_out_payload.value)))
    by1 = dict(outs1)
    assert by1.get(0x01) == exp1[0] and by1.get(0x11) == exp1[1], (
        f"보류된 SIG_BMM_3 가 자기 값으로 나오지 않았다 — 관측 {outs1}, "
        f"기대 lo={exp1[0]:#x} hi={exp1[1]:#x}")

    # 같은 tag 로 값만 다른 재전송. 슬롯이 남아 있으면 첫 조각에서
    # 거짓 완성해 exp1 잔재가 섞인다.
    await _bmm3_burst(dut, bmm3_instr, tag_mu, pay2)
    outs2 = []
    for _ in range(60):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.ext_out_valid.value) == 1:
            outs2.append((int(dut.ext_out_frag_hdr.value),
                          int(dut.ext_out_payload.value)))
    by2 = dict(outs2)
    assert len(outs2) == 2, (
        f"재전송 파동의 출력 조각이 2건이어야 한다 — 관측 {outs2}. "
        f"거짓 완성이 일어나면 조각 수부터 어긋난다")
    assert by2.get(0x01) == exp2[0] and by2.get(0x11) == exp2[1], (
        f"재전송 파동이 앞선 보류 파동의 CAM 잔재와 섞였다 — 관측 "
        f"{outs2}, 기대 lo={exp2[0]:#x} hi={exp2[1]:#x}")
    assert int(dut.input_skid_overflow_error.value) == 0, \
        "정상 경로인데 overflow fault 가 떴다"


# =============================================================================
# v1.9.2 §22.14b-4b — deferred CAM commit 의 **기아(starvation) 봉쇄**와
# 완성 보류 슬롯의 **병합 금지**.
#
# 왜 두 건이 더 필요한가 (2026-08-18 적대 검증 항 3):
#   §22.14b-4 의 accept-종속 철거는 HEAD 에 없던 상태 — "완성됐는데 아직
#   철거되지 않은 슬롯" — 를 **새로 만든다**. spec §22.14b-6(4)가 그 위험을
#   축소 없이 공개했지만 **회귀 pin 이 0건**이었고, 초판 구현에는 실제로
#   도달 경로가 두 갈래 있었다:
#     (i)  deferred commit 이 CAM always 사슬의 마지막 arm 이라, 투입 에지에
#          `cache_hit`(다른 tag 의 0x68) 하나만 겹쳐도 **영구 누락**됐다.
#     (ii) 그렇게 남은 슬롯에 같은 tag 의 조각이 도착하면 가득 찬 mask 에
#          병합돼 **즉시 거짓 완성** → stale wide 를 실행했다.
#   아래 두 테스트가 각각을 직접 pin 한다. (i) 은 다중 슬롯 빌드에서만
#   구성 가능하다 — FRAG_SLOTS=1 에는 `frag_ready` 가 서지 않아 `cache_hit`
#   자체가 존재하지 않기 때문이다. (ii) 는 양 빌드에서 성립한다.
# =============================================================================

@cocotb.test()
async def test_skid_deferred_commit_survives_concurrent_cache_load(dut):
    """v1.9.2 §22.14b-4b — 투입 에지에 0x68 이 겹쳐도 deferred commit 이
    **밀리지 않는다**.

    초판에서는 deferred CAM commit 이 `frag_in_multi`/`cache_hit`/`inval_hit`
    뒤의 마지막 else-if 였다. 재시도 경로가 없으므로 그 사이클에 다른 tag 의
    `CACHE_LOAD_WIDE`(0x68) 하나만 겹치면 commit 은 지연이 아니라 **영구
    누락**이 되고, 슬롯은 "완성 + full mask + frag_ready=0" 으로 남아 다음
    같은-tag 파동을 거짓 완성시킨다.

    자극은 계약 위반 영역이다 (`cluster_ready==0` 인 사이클에 0x68 주입) —
    그래서 overflow fault 가 뜨는 것이 **정상**이고, 이 테스트가 보는 것은
    "그 계약 위반 뒤에도 CAM 회계가 온전한가" 다. 그것이 loud-fault-never-
    silent 의 요구다: 소리를 낸 다음에도 조용한 오염을 남기지 않는다.

    FRAG_SLOTS=1 에서는 `frag_ready` 가 구조적으로 서지 않아 `cache_hit`
    자체가 없다 — 즉 이 기아 경로는 다중 슬롯 빌드에만 존재한다."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)
    if _skip_unless_multislot(dut):
        return

    consumer = encode_instr(0x60, eh_port(input_port_mask=0x01,
                                          output_port_id=0), eh_imm16(1))
    tag_cached = make_tag(wave_number=0x77, port_context_id=0)
    # 0x68 이 hit 할 ready 슬롯을 하나 만들어 둔다 (다른 tag).
    await _complete_wide_wave(dut, tag_cached, 0xA1A1A1A1A1A1A1A1,
                              0xB2B2B2B2B2B2B2B2, consumer)
    await _drain_output(dut)
    for _ in range(12):
        await RisingEdge(dut.clk)
    _skid_decoy(dut)
    await Timer(1, units="ns")

    n = _slots(dut)
    ready_bits = int(dut.frag_ready.value)
    assert ready_bits != 0, \
        "전제 붕괴: 0x68 이 hit 할 ready 슬롯이 만들어지지 않았다"

    bmm3_instr, _, _, _ = _bmm3_stimulus()
    tag_w = _tag(port_context_id=0)
    assert tag_w != tag_cached
    pay1, a1, b1 = _bmm3_payloads(0x1111, 0x2222)
    pay2, a2, b2 = _bmm3_payloads(0x3131, 0x1212)
    exp1 = _bmm_3_expected(a1, b1)
    exp2 = _bmm_3_expected(a2, b2)
    assert exp1 != exp2

    # EHDecode 를 점유시킨 뒤 blackout 안에서 4-조각 파동을 완성 → 보류.
    await _skid_pulse(dut, _coll_add_instr(1), _tag(port_context_id=1),
                      _SKID_A_PAY)
    await _bmm3_burst(dut, bmm3_instr, tag_w, pay1)
    await Timer(1, units="ns")
    assert int(dut.skid_valid.value) == 1, \
        "전제 붕괴: 완성 조각이 blackout 안에서 보류되지 않았다"
    slot_w = None
    for i in range(n):
        if int(dut.frag_tag_reg[i].value) == tag_w:
            slot_w = i
            break
    assert slot_w is not None, "보류 파동의 CAM 슬롯을 찾지 못했다"
    assert (int(dut.frag_ready.value) >> slot_w) & 1 == 0, \
        "전제 붕괴: 철거가 accept 에 종속되지 않았다 (이미 ready)"

    # ---- 투입 에지에 **다른 tag 의 0x68** 을 겹친다 ----
    cache_instr = encode_instr(0x68, eh_port(input_port_mask=0x01,
                                             output_port_id=0))
    dut.ext_instruction.value = cache_instr
    dut.ext_tag.value = tag_cached
    dut.ext_payload.value = 0
    dut.ext_payload_b.value = 0
    dut.ext_payload_b_valid.value = 0
    dut.ext_frag_hdr.value = 0
    dut.ext_valid.value = 1
    await RisingEdge(dut.clk)          # = 보류분 투입 에지
    _skid_decoy(dut)
    await Timer(1, units="ns")

    assert int(dut.skid_valid.value) == 0, \
        "전제 붕괴: 이 에지가 투입 에지가 아니다"
    # 기전 직접 pin — 결과만 보면 뒤의 (ii) 방어가 가려 준다.
    assert (int(dut.frag_ready.value) >> slot_w) & 1 == 1, (
        f"deferred CAM commit 이 동시 발생한 cache_hit 에 **밀렸다** — "
        f"슬롯 {slot_w} 이 '완성됐는데 철거되지 않은' 상태로 남았다. "
        f"재시도 경로가 없으므로 이 상태는 영구다 (§22.14b-4b)")
    assert int(dut.input_skid_overflow_error.value) == 1, \
        "cluster_ready==0 인 사이클의 주입인데 loud fault 가 없다"

    outs1 = []
    for _ in range(60):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.ext_out_valid.value) == 1:
            outs1.append((int(dut.ext_out_frag_hdr.value),
                          int(dut.ext_out_payload.value)))
    by1 = dict(outs1)
    assert by1.get(0x01) == exp1[0] and by1.get(0x11) == exp1[1], (
        f"보류된 파동이 자기 값으로 나오지 않았다 — 관측 {outs1}")

    # 같은 tag 재전송이 잔재와 섞이지 않아야 한다.
    await _bmm3_burst(dut, bmm3_instr, tag_w, pay2)
    outs2 = []
    for _ in range(60):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.ext_out_valid.value) == 1:
            outs2.append((int(dut.ext_out_frag_hdr.value),
                          int(dut.ext_out_payload.value)))
    by2 = dict(outs2)
    assert len(outs2) == 2, (
        f"재전송 파동의 출력 조각이 2건이어야 한다 — 관측 {outs2}")
    assert by2.get(0x01) == exp2[0] and by2.get(0x11) == exp2[1], (
        f"재전송 파동이 CAM 잔재와 섞였다 — 관측 {outs2}, 기대 "
        f"lo={exp2[0]:#x} hi={exp2[1]:#x}")


@cocotb.test()
async def test_skid_completed_slot_never_merges_new_fragment(dut):
    """v1.9.2 §22.14b-4b — 완성 보류 슬롯은 **병합 대상이 아니다**.

    §22.14b-4 가 새로 만든 상태("완성 + full mask + `frag_ready=0`")에
    같은 tag 의 조각이 도착하면, 가득 찬 mask 와 OR 되어 그 자리에서
    `frag_reass_valid` 가 서고 **stale wide 가 즉시 실행**된다. 그것이
    §22.14b-6(4)가 공개한 '조용한' 하위 케이스다.

    도달 경로: 보류분 투입 에지에 **같은 tag 의 새 조각 0번**을 겹치면
    deferred commit 이 취소되고(`skid_slot_taken`), 슬롯은 완성 상태
    그대로 남는다. 병합 금지가 없으면 그 조각이 즉시 거짓 완성해
    **여분의 잘못된 출력**을 내고, 이후 조각들이 다시 겹치면서 파동 수와
    값이 모두 어긋난다.

    이 자극은 계약 위반 영역이지만(`cluster_ready==0` 에 주입) 조각 beat
    자체는 완성 펄스가 아니므로 **overflow fault 가 뜨지 않는다** — 즉
    수리 전에는 완전히 조용한 오염이었다. 그래서 여기서 fault 0 까지
    hard assert 한다.

    부수 확인: 이 시나리오에서 슬롯의 `frag_data` 는 새 파동에게
    덮이는데도 보류분이 정확히 나온다 — §22.14b-3 이 wide 1,024b 를
    슬롯 재독출이 아니라 **복제 보관**으로 정한 결정이 여기서 값을
    한다 (cut ladder rung 1 은 이 성질을 잃는다)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    bmm3_instr, _, _, _ = _bmm3_stimulus()
    tag_w = _tag(port_context_id=0)
    pay1, a1, b1 = _bmm3_payloads(0x1111, 0x2222)
    pay2, a2, b2 = _bmm3_payloads(0x3131, 0x1212)
    exp1 = _bmm_3_expected(a1, b1)
    exp2 = _bmm_3_expected(a2, b2)
    assert exp1 != exp2

    # EHDecode 점유 → blackout 안에서 파동 1 완성 → 보류.
    await _skid_pulse(dut, _coll_add_instr(1), _tag(port_context_id=1),
                      _SKID_A_PAY)
    await _bmm3_burst(dut, bmm3_instr, tag_w, pay1)
    await Timer(1, units="ns")
    assert int(dut.skid_valid.value) == 1, \
        "전제 붕괴: 완성 조각이 blackout 안에서 보류되지 않았다"

    # ---- 투입 에지에 **같은 tag 의 새 조각 0번**을 겹친다 ----
    await _bmm3_beat(dut, bmm3_instr, tag_w, pay2[0], 0)
    _skid_decoy(dut)
    await Timer(1, units="ns")
    assert int(dut.skid_valid.value) == 0, \
        "전제 붕괴: 이 에지가 투입 에지가 아니다"
    assert int(dut.input_skid_overflow_error.value) == 0, (
        "조각 beat 는 완성 펄스가 아니므로 overflow 가 아니다 — 여기서 "
        "1 이면 완성 보류 슬롯에 **병합**돼 거짓 완성했다는 뜻이다 "
        "(§22.14b-4b 가 금지하는 바로 그 경로)")

    # 나머지 조각 3개.
    for idx in range(1, 4):
        await _bmm3_beat(dut, bmm3_instr, tag_w, pay2[idx], idx)
    _skid_decoy(dut)

    outs = []
    for _ in range(90):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.ext_out_valid.value) == 1:
            outs.append((int(dut.ext_out_frag_hdr.value),
                         int(dut.ext_out_payload.value)))

    assert int(dut.input_skid_overflow_error.value) == 0, (
        f"거짓 완성이 일어나 파동이 겹쳤다 (overflow fault) — 관측 "
        f"{[(hex(h), hex(p)) for h, p in outs]}")
    assert len(outs) == 4, (
        f"출력이 정확히 4건(파동 2개 × 조각 2개)이어야 한다 — 관측 "
        f"{[(hex(h), hex(p)) for h, p in outs]}. 완성 보류 슬롯에 병합이 "
        f"일어나면 여분의 거짓 완성 출력이 섞인다")
    lo_outs = [p for h, p in outs if h == 0x01]
    hi_outs = [p for h, p in outs if h == 0x11]
    assert lo_outs == [exp1[0], exp2[0]], (
        f"lo 조각이 순서대로 파동1·파동2 여야 한다 — 관측 "
        f"{[hex(p) for p in lo_outs]}, 기대 "
        f"{[hex(exp1[0]), hex(exp2[0])]}")
    assert hi_outs == [exp1[1], exp2[1]], (
        f"hi 조각이 순서대로 파동1·파동2 여야 한다 — 관측 "
        f"{[hex(p) for p in hi_outs]}, 기대 "
        f"{[hex(exp1[1]), hex(exp2[1])]}")


@cocotb.test()
async def test_skid_deferred_commit_cancelled_when_slot_retaken(dut):
    """v1.9.2 §22.14b-4b(a) — 보류 창 동안 슬롯을 뺏기면 deferred commit 은
    **취소**돼야 한다 (밀리는 것이 아니라 없어진다).

    deferred commit 의 가드는 `frag_active[slot] && tag 일치` 였다. 그 tag
    비교는 **다른** tag 의 재할당만 걸러낸다 — **같은 tag 로 재전송**된
    파동이 그 슬롯을 새로 가져간 경우에는 비교가 그대로 통과하므로, 투입
    에지에 commit 이 실행되어 **새 주인의 슬롯을 철거**한다. FRAG_SLOTS=1
    에서는 그것이 곧 재전송 파동의 **무언 소실**이다 (조각 0 이 사라져
    영원히 완성되지 않는다).

    자극: 2-조각 파동 1 을 blackout 초반(에지 0..1)에 완성시켜 보류시키고,
    아직 투입되지 않은 에지 2 에 **같은 tag 로 파동 2 의 조각 0** 을
    보낸다. 그 beat 는 완성 펄스가 아니므로 overflow fault 도 뜨지 않는다
    — 취소가 없으면 완전히 조용한 손실이다. 두 파동이 **모두** 자기 값으로
    나와야 한다.

    (FRAG_SLOTS>1 에서는 그 beat 가 빈 슬롯으로 가므로 이 경로 자체가
    생기지 않는다. 그래도 이 테스트는 양 빌드에서 '두 파동 모두 정상' 을
    검사하므로 어느 쪽에서도 vacuous 하지 않다.)"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    imm = 5
    instr = encode_instr(0x10, eh_port(input_port_mask=0x01,
                                       output_port_id=0), eh_imm16(imm))
    tag = _tag(port_context_id=0)
    p1_lo, p1_hi = 0x41, 0xF1F1F1F1F1F1F1F1
    p2_lo, p2_hi = 0x52, 0xF2F2F2F2F2F2F2F2
    exp1 = p1_lo + imm
    exp2 = p2_lo + imm
    assert exp1 != exp2

    # 점유 (이 에지가 kick → 에지 0..3 이 blackout).
    await _skid_pulse(dut, _coll_add_instr(1), _tag(port_context_id=1),
                      _SKID_A_PAY)
    # 에지 0·1 — 파동 1 의 두 조각. 에지 1 이 완성 에지 → 보류.
    await _skid_frag_beat(dut, instr, tag, p1_lo, 0x01)
    await _skid_frag_beat(dut, instr, tag, p1_hi, 0x11)
    _skid_decoy(dut)
    await Timer(1, units="ns")
    assert int(dut.skid_valid.value) == 1, \
        "전제 붕괴: 파동 1 이 blackout 안에서 보류되지 않았다"
    slot1 = _skid_slot_of(dut, tag)
    assert slot1 is not None

    # 에지 2 — **아직 투입 전**에 같은 tag 로 파동 2 의 조각 0.
    await _skid_frag_beat(dut, instr, tag, p2_lo, 0x01)
    _skid_decoy(dut)
    await Timer(1, units="ns")
    assert int(dut.skid_valid.value) == 1, \
        "전제 붕괴: 파동 1 이 이 시점에 이미 투입됐다 (창이 없다)"
    assert int(dut.input_skid_overflow_error.value) == 0, (
        "조각 beat 는 완성 펄스가 아니므로 overflow 가 아니다 — 1 이면 "
        "완성 보류 슬롯에 병합돼 거짓 완성했다는 뜻이다 (§22.14b-4b(b))")

    # 에지 3 (idle) → 에지 4 (투입).
    await RisingEdge(dut.clk)
    _skid_decoy(dut)
    await RisingEdge(dut.clk)
    _skid_decoy(dut)
    await Timer(1, units="ns")
    assert int(dut.skid_valid.value) == 0, \
        "전제 붕괴: 에지 4 가 투입 에지가 아니다"

    # 에지 5 — 파동 2 의 조각 1 (완성).
    await _skid_frag_beat(dut, instr, tag, p2_hi, 0x11)
    _skid_decoy(dut)

    outs = []
    for _ in range(90):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.ext_out_valid.value) == 1:
            outs.append(int(dut.ext_out_payload.value))

    # 관측 창이 점유 파동(단일 조각 ADD)의 출력까지 포함하므로 3건이다.
    exp_occ = _SKID_A_PAY + _ADD_IMM
    assert outs.count(exp1) == 1, (
        f"보류된 파동 1 의 결과 {exp1} 가 {outs.count(exp1)}회 — 관측 "
        f"{[hex(p) for p in outs]}")
    assert outs.count(exp2) == 1, (
        f"**재전송 파동 2 가 조용히 사라졌다** — 결과 {exp2} 가 "
        f"{outs.count(exp2)}회 (관측 {[hex(p) for p in outs]}). 취소가 없으면 "
        f"투입 에지의 deferred commit 이 파동 2 의 슬롯을 철거해 조각 0 이 "
        f"사라지고, 그 파동은 영원히 완성되지 않는다 (§22.14b-4b(a))")
    assert sorted(outs) == sorted([exp_occ, exp1, exp2]), (
        f"출력이 정확히 3건(점유 파동 + 파동1 + 파동2)이어야 한다 — 관측 "
        f"{[hex(p) for p in outs]}, 기대 "
        f"{[hex(p) for p in sorted([exp_occ, exp1, exp2])]}")
    assert int(dut.input_skid_overflow_error.value) == 0, \
        "정상 경로인데 overflow fault 가 떴다"


# =============================================================================
# v1.6.5c §22.16 — multi-slot fragment buffer + CACHE_LOAD_WIDE (0x68)
#
# Tests below run under BOTH the default (`make MOD=Cluster`, FRAG_SLOTS=1)
# and the multi-slot (`make MOD=Cluster FRAG_SLOTS=4`) builds. Persistence/
# LRU/cold-fill tests only apply at FRAG_SLOTS>1 and self-skip otherwise,
# proven via the actual elaborated width of frag_active rather than a
# hardcoded assumption. The cache-load roundtrip test exercises BOTH
# regimes: safe MISS at FRAG_SLOTS=1 (no persistence to hit), real HIT at
# FRAG_SLOTS>1.
#
# self-skip 의 위험과 그 봉쇄 (P0-2)
# -----------------------------------
# 기본 빌드는 FRAG_SLOTS=1 이다. 그 빌드에서 아래 6건은 값 검사를 **0건**
# 수행하고도 PASS 로 집계된다 — "돌렸다"와 "검증했다"가 구분되지 않는다.
# 실제로 두 빌드를 모두 돌리도록 강제하는 장치가 CI·hook·lint 어디에도
# 없었다. 두 가지로 막는다:
#
#   (i)  self-skip 은 반드시 `_skip_unless_multislot()` 을 거치며, 이것이
#        WARNING 을 남긴다. 조용히 지나가는 경로가 없다.
#   (ii) `make test-cluster-both` 가 두 빌드를 하나의 진입점으로 묶고,
#        FRAG_SLOTS=1 에서 self-skip 이 정확히 7건, FRAG_SLOTS=4 에서
#        정확히 0건인지까지 대조한다 (scripts/run_cluster_dual.py).
#        `scripts/lint_frag_slots_dual_run.py` 가 (i)/(ii)의 형태를
#        기계적으로 강제하므로 조용한 self-skip 을 새로 들여올 수 없다.
# =============================================================================


def _slots(dut):
    """Number of elaborated fragment-buffer slots (FRAG_SLOTS build param)."""
    return len(dut.frag_active.value)


# `make test-cluster-both` / lint 이 로그에서 세는 고정 표식. 바꾸면
# scripts/run_cluster_dual.py 와 scripts/lint_frag_slots_dual_run.py 도
# 같이 바꿔야 한다 (lint 이 불일치를 잡는다).
_MULTISLOT_SKIP_MARK = "FRAG_SLOTS-SELF-SKIP"


def _skip_unless_multislot(dut):
    """FRAG_SLOTS>1 전용 테스트의 **loud** self-skip 게이트.

    True 를 돌려주면 호출자는 즉시 return 해야 한다. 조용히 넘어가지
    않도록 반드시 WARNING 을 남긴다 — 이 부류의 PASS 는 '검증됨'이
    아니라 '해당 없음'이기 때문이다."""
    n = _slots(dut)
    if n <= 1:
        dut._log.warning(
            "%s: FRAG_SLOTS=%d 빌드에서는 이 테스트가 값 검사를 0건 "
            "수행한다. 이 PASS 는 '검증됨'이 아니라 '해당 없음'이다 — "
            "다중 슬롯 검증은 `make test-cluster-both` 로 확보하라.",
            _MULTISLOT_SKIP_MARK, n)
        return True
    return False


async def _complete_wide_wave(dut, tag, lo, hi, consumer_instr):
    """Drive a 2-fragment wide-consumer wave (idx0=lo, idx1=hi); the real
    consumer instruction is presented on the completing (idx1) beat, per
    the existing single-slot convention (see test_fragment_completion_
    feeds_ehdecode_wide). Leaves ext_valid/ext_frag_hdr deasserted on
    return, one cycle after the completion pulse."""
    dut.ext_instruction.value = 0
    dut.ext_tag.value = tag
    dut.ext_payload.value = lo
    dut.ext_payload_b.value = 0
    dut.ext_payload_b_valid.value = 0
    dut.ext_frag_hdr.value = 0x01
    dut.ext_valid.value = 1
    await RisingEdge(dut.clk)
    dut.ext_instruction.value = consumer_instr
    dut.ext_payload.value = hi
    dut.ext_frag_hdr.value = 0x11
    await RisingEdge(dut.clk)
    dut.ext_valid.value = 0
    dut.ext_frag_hdr.value = 0
    await Timer(1, units="ns")


async def _drain_output(dut, cycles=20):
    """Advance until ext_out_valid pulses (producer's own output), so it
    doesn't linger and confuse a subsequent dispatch's observation window."""
    for _ in range(cycles):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.ext_out_valid.value) == 1:
            break


async def _fire_cache_load_wide(dut, tag, port_context_id=0):
    """Fire a single-beat CACHE_LOAD_WIDE (0x68) dispatch with the given
    tag and wait for the pipeline to produce an output or error."""
    instr = encode_instr(0x68, eh_port(input_port_mask=(1 << port_context_id),
                                       output_port_id=port_context_id))
    dut.ext_instruction.value = instr
    dut.ext_tag.value = tag
    dut.ext_payload.value = 0
    dut.ext_payload_b.value = 0
    dut.ext_payload_b_valid.value = 0
    dut.ext_frag_hdr.value = 0
    dut.ext_valid.value = 1
    await RisingEdge(dut.clk)
    dut.ext_valid.value = 0
    for _ in range(30):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.ext_out_valid.value) == 1 or int(dut.any_error_flag.value) == 1:
            break


async def _fire_frag_inval(dut, tag, port_context_id=0):
    """v1.6.5d §22.17: fire a single-beat FRAG_INVAL (0x6A) dispatch with
    the given tag and wait for an ack or error."""
    instr = encode_instr(0x6A, eh_port(input_port_mask=(1 << port_context_id),
                                       output_port_id=port_context_id))
    dut.ext_instruction.value = instr
    dut.ext_tag.value = tag
    dut.ext_payload.value = 0
    dut.ext_payload_b.value = 0
    dut.ext_payload_b_valid.value = 0
    dut.ext_frag_hdr.value = 0
    dut.ext_valid.value = 1
    await RisingEdge(dut.clk)
    dut.ext_valid.value = 0
    for _ in range(30):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.ext_out_valid.value) == 1 or int(dut.any_error_flag.value) == 1:
            break


@cocotb.test()
async def test_cache_load_wide_roundtrip(dut):
    """v1.6.5c §22.16: cache a 2-fragment wide wave via a real wide-
    consumer op (SIMD_ADD_WIDE_SCALAR), then reload the RAW cached INPUT
    (not the arithmetic result) via CACHE_LOAD_WIDE with the same tag.

    FRAG_SLOTS=1 (default): no persistence exists — completion clears the
    slot immediately, so this MUST miss (error_flag, no output) — proving
    the capability-gated safe-miss behavior for legacy/non-caching
    targets.

    FRAG_SLOTS>1: MUST hit and return the exact original input bytes,
    unprocessed by SIMD_ADD_WIDE_SCALAR's own arithmetic."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    tag = _tag(port_context_id=0)
    lo = 0x1111111111111111
    hi = 0x2222222222222222
    consumer = encode_instr(0x60, eh_port(input_port_mask=0x01, output_port_id=0),
                            eh_imm16(5))
    await _complete_wide_wave(dut, tag, lo, hi, consumer)
    await _drain_output(dut)

    await _fire_cache_load_wide(dut, tag)

    if _slots(dut) == 1:
        assert int(dut.any_error_flag.value) == 1, \
            "FRAG_SLOTS=1 must MISS (no persistence) — got no error"
        assert int(dut.ext_out_valid.value) == 0
    else:
        assert int(dut.any_error_flag.value) == 0, "unexpected miss/error at FRAG_SLOTS>1"
        assert int(dut.ext_out_valid.value) == 1
        got_lo = int(dut.ext_out_payload.value)
        assert int(dut.ext_out_frag_hdr.value) == 0x01
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        got_hi = int(dut.ext_out_payload.value)
        assert int(dut.ext_out_frag_hdr.value) == 0x11
        assert got_lo == lo, f"lo: {got_lo:016x} != {lo:016x}"
        assert got_hi == hi, f"hi: {got_hi:016x} != {hi:016x}"


@cocotb.test()
async def test_cache_load_wide_never_cached_misses(dut):
    """v1.6.5c §22.16: CACHE_LOAD_WIDE against a tag that was never
    produced anywhere must always miss — regardless of FRAG_SLOTS."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    never_used_tag = _tag(port_context_id=0)
    await _fire_cache_load_wide(dut, never_used_tag)
    assert int(dut.any_error_flag.value) == 1
    assert int(dut.ext_out_valid.value) == 0


@cocotb.test()
async def test_frag_slots_persistent_no_clear(dut):
    """v1.6.5c §22.16: at FRAG_SLOTS>1, wave completion sets frag_ready
    (persistent, non-destructive) instead of clearing frag_active — the
    opposite of FRAG_SLOTS=1's unconditional clear. Trivially passes
    (self-skips) at the default FRAG_SLOTS=1 build."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)
    if _skip_unless_multislot(dut):
        return

    tag = _tag(port_context_id=0)
    consumer = encode_instr(0x60, eh_port(input_port_mask=0x01, output_port_id=0),
                            eh_imm16(1))
    await _complete_wide_wave(dut, tag, 0x1, 0x2, consumer)

    found = None
    for i in range(_slots(dut)):
        if int(dut.frag_tag_reg[i].value) == tag:
            found = i
            break
    assert found is not None, "producer tag not resident in any slot"
    # frag_active/frag_ready are PACKED vectors (not unpacked arrays like
    # frag_tag_reg/frag_age) — cocotb requires bit-slicing the whole value
    # rather than handle indexing.
    active_bits = int(dut.frag_active.value)
    ready_bits  = int(dut.frag_ready.value)
    assert (active_bits >> found) & 1 == 1, "slot must stay active (persistent)"
    assert (ready_bits >> found) & 1 == 1, "slot must be marked ready (cacheable)"


@cocotb.test()
async def test_frag_slots_coldfill_monotonic_age_and_lru_eviction(dut):
    """v1.6.5c §22.16: sequential cold-fill from reset gets strictly
    increasing, pairwise-distinct ages — a regression guard against a
    rank-permutation LRU scheme's cold-fill tie (every never-touched slot
    at age=0 is ambiguous with a valid rank of 0). A subsequent wave
    beyond capacity must evict the TRUE oldest slot, not an arbitrary one.
    Trivially passes (self-skips) at the default FRAG_SLOTS=1 build."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)
    if _skip_unless_multislot(dut):
        return
    n = _slots(dut)

    consumer = encode_instr(0x60, eh_port(input_port_mask=0x01, output_port_id=0),
                            eh_imm16(1))
    tags = [make_tag(wave_number=i + 1, port_context_id=0) for i in range(n)]
    for i, t in enumerate(tags):
        await _complete_wide_wave(dut, t, 0x10 + i, 0x20 + i, consumer)
        await _drain_output(dut)

    ages = [int(dut.frag_age[i].value) for i in range(n)]
    assert len(set(ages)) == n, f"ages not pairwise distinct: {ages}"
    assert ages == sorted(ages), \
        f"ages not monotonically increasing in allocation order: {ages}"

    # One more distinct wave forces eviction of the truly oldest slot
    # (the one holding tags[0], allocated first).
    evictor_tag = make_tag(wave_number=99, port_context_id=0)
    await _complete_wide_wave(dut, evictor_tag, 0x99, 0x9A, consumer)
    await _drain_output(dut)

    tag_regs = [int(dut.frag_tag_reg[i].value) for i in range(n)]
    assert evictor_tag in tag_regs, "evictor wave not resident anywhere after eviction"
    assert tags[0] not in tag_regs, "oldest slot should have been evicted, but survived"
    for i in range(1, n):
        assert tags[i] in tag_regs, f"younger slot tags[{i}] should survive eviction"


@cocotb.test()
async def test_frag_slots_tag_reuse_collision_safe_realloc(dut):
    """v1.6.5c §22.16: a NEW fragment beat whose tag matches an already-
    cached (ready) slot must safely REALLOCATE (fresh mask, new data) —
    never silently OR-merge stale cached bits into the new wave.
    Trivially passes (self-skips) at the default FRAG_SLOTS=1 build,
    since persistence (and hence a collidable ready slot) doesn't exist
    there."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)
    if _skip_unless_multislot(dut):
        return

    tag = _tag(port_context_id=0)
    consumer = encode_instr(0x60, eh_port(input_port_mask=0x01, output_port_id=0),
                            eh_imm16(1))
    await _complete_wide_wave(dut, tag, 0xAAAAAAAAAAAAAAAA, 0xBBBBBBBBBBBBBBBB, consumer)
    await _drain_output(dut)

    # Reuse the SAME tag with DIFFERENT payload data.
    await _complete_wide_wave(dut, tag, 0xCCCCCCCCCCCCCCCC, 0xDDDDDDDDDDDDDDDD, consumer)
    await _drain_output(dut)

    await _fire_cache_load_wide(dut, tag)
    assert int(dut.any_error_flag.value) == 0
    assert int(dut.ext_out_valid.value) == 1
    got_lo = int(dut.ext_out_payload.value)
    assert got_lo == 0xCCCCCCCCCCCCCCCC, \
        f"expected NEW data (safe realloc), got {got_lo:016x} — stale merge bug"


@cocotb.test()
async def test_frag_inval_hit_frees_slot_immediately(dut):
    """v1.6.5d §22.17: caching a wave then FRAG_INVAL-ing its tag acks
    successfully, clears that slot's frag_active bit, and a subsequent
    CACHE_LOAD_WIDE on the same tag now misses. Trivially passes (self-
    skips) at the default FRAG_SLOTS=1 build (no persistence to
    invalidate there)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)
    if _skip_unless_multislot(dut):
        return

    tag = _tag(port_context_id=0)
    consumer = encode_instr(0x60, eh_port(input_port_mask=0x01, output_port_id=0),
                            eh_imm16(1))
    await _complete_wide_wave(dut, tag, 0x1, 0x2, consumer)
    await _drain_output(dut)

    found = None
    for i in range(_slots(dut)):
        if int(dut.frag_tag_reg[i].value) == tag:
            found = i
            break
    assert found is not None, "producer tag not resident in any slot"

    await _fire_frag_inval(dut, tag)
    assert int(dut.any_error_flag.value) == 0, "FRAG_INVAL on a cached tag must ack, not miss"
    assert int(dut.ext_out_valid.value) == 1

    active_bits = int(dut.frag_active.value)
    assert (active_bits >> found) & 1 == 0, "slot must be freed (frag_active cleared)"

    await _fire_cache_load_wide(dut, tag)
    assert int(dut.any_error_flag.value) == 1, "CACHE_LOAD_WIDE on an invalidated tag must miss"
    assert int(dut.ext_out_valid.value) == 0


@cocotb.test()
async def test_frag_inval_never_cached_misses(dut):
    """v1.6.5d §22.17: FRAG_INVAL against a tag that was never produced
    anywhere must always miss — regardless of FRAG_SLOTS."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    never_used_tag = _tag(port_context_id=0)
    await _fire_frag_inval(dut, never_used_tag)
    assert int(dut.any_error_flag.value) == 1
    assert int(dut.ext_out_valid.value) == 0


@cocotb.test()
async def test_frag_inval_freed_slot_reclaimed_by_free_priority_not_evict(dut):
    """v1.6.5d §22.17: after filling all slots and invalidating a non-LRU
    (youngest) slot, the next new wave reuses the freed slot rather than
    triggering an LRU-evict of the true oldest slot — proves any_free is
    checked ahead of evict_idx for an invalidate-freed slot, not just by
    inspection. Trivially passes (self-skips) at FRAG_SLOTS=1."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)
    if _skip_unless_multislot(dut):
        return
    n = _slots(dut)

    consumer = encode_instr(0x60, eh_port(input_port_mask=0x01, output_port_id=0),
                            eh_imm16(1))
    tags = [make_tag(wave_number=i + 1, port_context_id=0) for i in range(n)]
    for i, t in enumerate(tags):
        await _complete_wide_wave(dut, t, 0x10 + i, 0x20 + i, consumer)
        await _drain_output(dut)

    # Invalidate the YOUNGEST (last-allocated, i.e. non-LRU) slot's tag.
    await _fire_frag_inval(dut, tags[-1])
    assert int(dut.any_error_flag.value) == 0

    # One more distinct wave should reclaim the just-freed slot, NOT evict
    # the true oldest (tags[0]).
    newcomer_tag = make_tag(wave_number=100, port_context_id=0)
    await _complete_wide_wave(dut, newcomer_tag, 0xAA, 0xBB, consumer)
    await _drain_output(dut)

    tag_regs = [int(dut.frag_tag_reg[i].value) for i in range(n)]
    assert newcomer_tag in tag_regs, "newcomer wave not resident anywhere"
    assert tags[0] in tag_regs, \
        "true LRU-oldest slot must survive — newcomer should reuse the freed slot, not evict it"
    for i in range(1, n - 1):
        assert tags[i] in tag_regs, f"unrelated slot tags[{i}] should be undisturbed"


@cocotb.test()
async def test_frag_inval_midassembly_slot_reports_miss_not_cancel(dut):
    """v1.6.5d §22.17: FRAG_INVAL against a tag whose slot is mid-assembly
    (frag_active && !frag_ready, i.e. not all fragments have arrived yet)
    must report a miss (error_flag), not a cancel — this is the
    documented scope limit: FRAG_INVAL reclaims a completed cached slot,
    it is not an in-flight-fragment-abort primitive. Trivially passes
    (self-skips) at FRAG_SLOTS=1."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)
    if _skip_unless_multislot(dut):
        return

    tag = _tag(port_context_id=0)
    # Send only fragment 0 of a 2-fragment wave — never completes.
    dut.ext_instruction.value = 0
    dut.ext_tag.value = tag
    dut.ext_payload.value = 0x1
    dut.ext_payload_b.value = 0
    dut.ext_payload_b_valid.value = 0
    dut.ext_frag_hdr.value = 0x01
    dut.ext_valid.value = 1
    await RisingEdge(dut.clk)
    dut.ext_valid.value = 0
    dut.ext_frag_hdr.value = 0
    await Timer(1, units="ns")

    found = None
    for i in range(_slots(dut)):
        if int(dut.frag_tag_reg[i].value) == tag:
            found = i
            break
    assert found is not None, "mid-assembly slot not found"
    active_before = (int(dut.frag_active.value) >> found) & 1
    assert active_before == 1, "slot must be active (allocated) but not yet complete"

    await _fire_frag_inval(dut, tag)
    assert int(dut.any_error_flag.value) == 1, \
        "FRAG_INVAL on a mid-assembly (not-yet-ready) slot must miss, not cancel"
    assert int(dut.ext_out_valid.value) == 0

    active_after = (int(dut.frag_active.value) >> found) & 1
    assert active_after == 1, "mid-assembly slot must be UNCHANGED after a miss"


# =============================================================================
# v1.8.0b §23.9 — VDOT_ACC (0x71) MU routing + fragment-order permutations
# =============================================================================


def _v180b_pack_int4(*vals):
    x = 0
    for i, v in enumerate(vals):
        x |= (v & 0xF) << (i * 4)
    return x


async def _fire_vdot_wave(dut, a_128, b_128, carry_in, frag_order=(0, 1, 2, 3)):
    """Drive one 4-fragment VDOT_ACC wave in the given fragment arrival
    order. Instruction + EH chain (incl. PRECISION mode + IMM16 carry-in)
    replicated on EVERY fragment per the §23.6a SDK contract."""
    from test_isa_decoder import eh_precision as _ehp
    wide = (a_128 & ((1 << 128) - 1)) | ((b_128 & ((1 << 128) - 1)) << 128)
    payloads = [(wide >> (64 * i)) & ((1 << 64) - 1) for i in range(4)]
    instr = encode_instr(0x71,
                         eh_port(input_port_mask=0x01, output_port_id=0),
                         _ehp(0x10, 0),          # mode: dtype=int4, acc=1, rnd=0
                         eh_imm16(carry_in),
                         flags=(1 << 2))          # F_PRECISION_OVR
    tag = _tag(port_context_id=0)
    for idx in frag_order:
        dut.ext_instruction.value = instr
        dut.ext_tag.value = tag
        dut.ext_payload.value = payloads[idx]
        dut.ext_payload_b.value = 0
        dut.ext_payload_b_valid.value = 1
        dut.ext_frag_hdr.value = (idx << 4) | 0x3
        dut.ext_valid.value = 1
        await RisingEdge(dut.clk)
    dut.ext_valid.value = 0
    dut.ext_frag_hdr.value = 0
    for _ in range(30):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.ext_out_valid.value) == 1 or int(dut.any_error_flag.value) == 1:
            break
    return {'out': int(dut.ext_out_valid.value),
            'err': int(dut.any_error_flag.value),
            'payload': int(dut.ext_out_payload.value)}


@cocotb.test()
async def test_vdot_mu_routing_end_to_end(dut):
    """v1.8.0b twin-classifier check: a 0x71 wave routes to the
    MATMUL_UNIT via is_mul_op and EXECUTES (emits the dot) — kills the
    single-list dead-end where only one classifier is updated and the op
    lowers forever. v1.8.0c extends the same reachability pin to the
    three fp opcodes 0x74/0x75/0x76 in test_fp_mu_routing_end_to_end
    below (same failure mode, same commit as the classifier edit)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)
    a_lanes = [(i % 15) - 7 for i in range(32)]
    b_lanes = [((i * 3) % 15) - 7 for i in range(32)]
    a = _v180b_pack_int4(*[v & 0xF for v in a_lanes])
    b = _v180b_pack_int4(*[v & 0xF for v in b_lanes])
    golden = (sum(x * y for x, y in zip(a_lanes, b_lanes)) + 5) % (1 << 64)
    r = await _fire_vdot_wave(dut, a, b, carry_in=5)
    assert r['err'] == 0 and r['out'] == 1, f"got {r}"
    assert r['payload'] == golden, f"{r['payload']:016x} != {golden:016x}"


@cocotb.test()
async def test_vdot_fragment_order_permutations_with_carry_in(dut):
    """v1.8.0b §23.4 order-free property at the fragment level: all 24
    arrival permutations of one 4-fragment 0x71 wave, NONZERO carry-in
    replicated on every fragment — bit-identical result for every
    permutation (extends the shipped out-of-order-arrival precedent)."""
    from itertools import permutations
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)
    a_lanes = [(-8 if i % 6 == 0 else (i % 15) - 7) for i in range(32)]
    b_lanes = [((i * 7) % 15) - 7 for i in range(32)]
    a = _v180b_pack_int4(*[v & 0xF for v in a_lanes])
    b = _v180b_pack_int4(*[v & 0xF for v in b_lanes])
    golden = (sum(x * y for x, y in zip(a_lanes, b_lanes)) + 0x1234) % (1 << 64)
    for order in permutations(range(4)):
        r = await _fire_vdot_wave(dut, a, b, carry_in=0x1234, frag_order=order)
        assert r['err'] == 0 and r['out'] == 1, f"order={order}: {r}"
        assert r['payload'] == golden, \
            f"order={order}: {r['payload']:016x} != {golden:016x}"


# =============================================================================
# v1.8.0c §23.10 — fp32 scalar ops (0x74 FSCALAR / 0x75 FRSQRT32 / 0x76
# FEXP2_32) MU routing. Twin-classifier reachability: each op must return
# a RESULT through the full Cluster — a missed classifier side (Cluster
# is_mul_op OR PE_Core dec_is_mul_op) shows up here as either a
# lower_required dead-end (L-PE got it / MU prologue lowered it) or a
# silent timeout, never as a wrong-value pass. Golden authority is
# scripts/golden_fp32.py (imported, never retyped).
# =============================================================================

import struct as _struct

sys.path.insert(0, os.path.join(_REPO, 'scripts'))
import golden_fp32 as _G  # noqa: E402

_FS = _G.FSCALAR_OP_CODE
_FP_MODE = 0x14   # the single legal fp mode byte: rnd=0, acc=1, dtype=4


def _f2b(x):
    return int.from_bytes(_struct.pack(">f", float(x)), "big")


def _fp_cluster_instr(op, subop=None, mode=None, opref=False):
    from test_isa_decoder import eh_precision as _ehp, eh_opref as _eho
    ehs = [eh_port(input_port_mask=0x01, output_port_id=0),
           _ehp(_FP_MODE if mode is None else mode, 0)]
    if subop is not None:
        ehs.append(eh_imm16((subop & 0xF) << 4))
    if opref:
        ehs.append(_eho())   # src_kind 0 — direct payload_b (0x73 B channel)
    return encode_instr(op, *ehs, flags=(1 << 2))   # F_PRECISION_OVR


async def _fire_fp_cluster(dut, op, payload_a, payload_b=0, b_valid=0,
                           subop=None, mode=None, opref=False):
    await _fire(dut, _fp_cluster_instr(op, subop, mode, opref),
                _tag(port_context_id=0),
                payload_a=payload_a, payload_b=payload_b,
                payload_b_valid=b_valid)
    return {'out': int(dut.ext_out_valid.value),
            'err': int(dut.any_error_flag.value),
            'lwr': int(dut.any_lower_required.value),
            'payload': int(dut.ext_out_payload.value),
            'opcode': int(dut.ext_out_opcode.value)}


@cocotb.test()
async def test_fp_mu_routing_end_to_end(dut):
    """v1.8.0c twin-classifier reachability: 0x74 (with opb), 0x75 and
    0x76 each route to the MATMUL_UNIT via is_mul_op, EXECUTE on the fp
    step sequencer, and return a bit-exact RESULT ({32'h0, fp32}) at the
    Cluster boundary with opcode_out preserved."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    # 0x74 FSCALAR FS_MUL with B on the payload_b port
    a, b = _f2b(3.0), _f2b(1.5)
    exp = _G.micro_fscalar(_FS['FS_MUL'], a, b)
    r = await _fire_fp_cluster(dut, 0x74, a, payload_b=b, b_valid=1,
                               subop=_FS['FS_MUL'])
    assert (r['err'], r['lwr'], r['out']) == (0, 0, 1), f"0x74: {r}"
    assert r['payload'] == exp, f"0x74: {r['payload']:016x} != {exp:08x}"
    assert r['opcode'] == 0x74, f"0x74: opcode_out {r['opcode']:#x}"

    # 0x75 FRSQRT32 (strictly port-only unary)
    a = _f2b(4.0)
    exp = _G.micro_rsqrt(a)
    r = await _fire_fp_cluster(dut, 0x75, a)
    assert (r['err'], r['lwr'], r['out']) == (0, 0, 1), f"0x75: {r}"
    assert r['payload'] == exp, f"0x75: {r['payload']:016x} != {exp:08x}"
    assert r['opcode'] == 0x75, f"0x75: opcode_out {r['opcode']:#x}"

    # 0x76 FEXP2_32 (strictly port-only unary)
    a = _f2b(7.0)
    exp = _G.micro_exp2(a)
    r = await _fire_fp_cluster(dut, 0x76, a)
    assert (r['err'], r['lwr'], r['out']) == (0, 0, 1), f"0x76: {r}"
    assert r['payload'] == exp, f"0x76: {r['payload']:016x} != {exp:08x}"
    assert r['opcode'] == 0x76, f"0x76: opcode_out {r['opcode']:#x}"

    # v1.8.0d — 0x77 CVT (I2F dtype 0x4: also crosses the DAZ-bypass pin
    # end-to-end — a flushing capture would emit 0.0f, not 5.0f)
    _CVT = _G.CVT_OP_CODE
    exp = _G.micro_cvt(_CVT['WIDEN_TO_F32'], _G.DT_ACC_INT, 5)
    r = await _fire_fp_cluster(dut, 0x77, 5,
                               subop=_CVT['WIDEN_TO_F32'], mode=0x14)
    assert (r['err'], r['lwr'], r['out']) == (0, 0, 1), f"0x77: {r}"
    assert r['payload'] == exp, f"0x77: {r['payload']:016x} != {exp:08x}"
    assert r['opcode'] == 0x77, f"0x77: opcode_out {r['opcode']:#x}"

    # v1.8.0d — 0x77 CVT narrow f32->f16 (mode dtype nibble 0x2 rides the
    # same MU route: the classifier term is OPCODE-ONLY, no dtype leg)
    a = _f2b(1.5)
    exp = _G.micro_cvt(_CVT['NARROW_FROM_F32'], _G.DT_F16, a)
    r = await _fire_fp_cluster(dut, 0x77, a,
                               subop=_CVT['NARROW_FROM_F32'], mode=0x12)
    assert (r['err'], r['lwr'], r['out']) == (0, 0, 1), f"0x77 narrow: {r}"
    assert r['payload'] == exp, \
        f"0x77 narrow: {r['payload']:016x} != {exp:04x}"

    # v1.8.0d — 0x73 ACC_ELEMWISE, OPREF form (src_kind 0 direct payload_b:
    # B = {gamma, beta} on the payload_b port)
    a, g, b = _f2b(3.0), _f2b(2.0), _f2b(-1.5)
    bpack = (g << 32) | b
    exp = _G.micro_accew(a, bpack)
    r = await _fire_fp_cluster(dut, 0x73, a, payload_b=bpack, b_valid=1,
                               opref=True)
    assert (r['err'], r['lwr'], r['out']) == (0, 0, 1), f"0x73: {r}"
    assert r['payload'] == exp == _f2b(4.5), \
        f"0x73: {r['payload']:016x} != {exp:08x}"
    assert r['opcode'] == 0x73, f"0x73: opcode_out {r['opcode']:#x}"


@cocotb.test()
async def test_twin_classifier_lockstep_static(dut):
    """v1.8.0d §23.10.10(c) twin-classifier lockstep pin, STATIC side
    (the e2e side is test_fp_mu_routing_end_to_end above): the opcode
    literal sets inside Cluster.v `is_mul_op` and PE_Core.v
    `dec_is_mul_op` are extracted from the RTL TEXT and must be EQUAL —
    a one-sided edit is the silent permanent lower_required dead-end the
    v1.8.0b design workflow verified. Also pins 0x73/0x77 IN and 0x7C
    OUT (the no-dtype-conditionality clause of §23.10.10(d))."""
    import re

    def _classifier_set(path, anchor):
        text = open(path).read()
        idx = text.index(anchor)
        # The classifier is one continuous wire assignment ending at ';'.
        # v1.8.0e 3a-C4 — strip // comments FIRST. Without this the scan
        # stops at any ';' that happens to sit inside an explanatory
        # comment between two OR terms, silently truncating the extracted
        # set and reporting a twin-classifier divergence that does not
        # exist (observed while landing 0x7A). A test whose extractor can
        # lie about the RTL is worse than no test.
        body = text[idx:]
        stripped = '\n'.join(ln.split('//')[0] for ln in body.splitlines())
        expr = stripped[:stripped.index(';')]
        return set(int(m, 16) for m in re.findall(r"8'h([0-9A-Fa-f]{2})",
                                                  expr))
    here = os.path.dirname(os.path.abspath(__file__))
    clu = _classifier_set(os.path.join(here, 'Cluster.v'),
                          'wire is_mul_op')
    pec = _classifier_set(os.path.join(here, 'PE_Core.v'),
                          'wire dec_is_mul_op')
    assert clu == pec, \
        f"twin classifiers diverged: Cluster-only " \
        f"{sorted(hex(x) for x in clu - pec)}, PE_Core-only " \
        f"{sorted(hex(x) for x in pec - clu)}"
    assert {0x73, 0x77} <= clu, "0x73/0x77 missing from the twin classifiers"
    # v1.8.0e §25.6 item 6 — 0x6B GAMMA_MUL_W / 0x78 DEQUANT / 0x79
    # FMINMAX joined in lockstep with the 0e1 integration commit.
    # v1.8.0e 0e2 — 0x70 VFMA_ACC joined WITH its lane-loop arm (this
    # commit; spec §25.2.4): the staged-out pin flips to IN.
    assert {0x6B, 0x78, 0x79} <= clu, \
        "0x6B/0x78/0x79 missing from the twin classifiers (v1.8.0e 0e1)"
    assert 0x70 in clu, \
        "0x70 missing from the twin classifiers — the 0e2 arm landed, " \
        "so a staged-out 0x70 is now the silent lower_required " \
        "dead-end (spec §25.2.4 / §25.3 lockstep pin)"
    # v1.8.0e 3a-C4 §35.1 — 0x7A FDOT32_CR joined WITH its PE_Core arm,
    # its ingress driver and the decode_reserved flip, all in ONE commit.
    # It is MU-hosted (the FDOT32_CR step program lives in the MU's
    # FP_StepSeq), and the MU carries NON_MUL_OPS_SUPPORTED=0, so a
    # missing classifier entry cuts 0x7A BEFORE the case block is entered
    # -> permanent lower_required, silently.
    assert 0x7A in clu, \
        "0x7A missing from the twin classifiers — the 3a-C4 arm landed, " \
        "so an unclassified 0x7A is the silent permanent lower_required " \
        "dead-end (spec §35.1 intermediate-state table row (ii))"
    assert 0x7C not in clu, \
        "0x7C entered is_mul_op — violates the §23.10.10(d) " \
        "twin-classifier-untouched clause (L-PE for ALL dtypes)"


@cocotb.test()
async def test_fp_lpe_direct_dispatch_lower_required(dut):
    """v1.8.0c launch-ladder rung 1 at the L-PE (MUL_OPS_SUPPORTED=0):
    the Cluster classifier never routes an fp opcode to an L-PE, so the
    test forces the scenario by depositing a 1-cycle pulse on the
    pe_active_lpe_s6 pipeline register during the fp wave's dec_valid
    cycle — the L-PE then sees an active 0x76 dispatch and must raise
    lower_required (capability absence), NEVER error_flag, while the
    MATMUL_UNIT (activated by the real routing) still returns the
    correct result."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    a = _f2b(7.0)
    exp = _G.micro_exp2(a)
    dut.ext_instruction.value = _fp_cluster_instr(0x76)
    dut.ext_tag.value = _tag(port_context_id=0)
    dut.ext_payload.value = a
    dut.ext_payload_b.value = 0
    dut.ext_payload_b_valid.value = 0
    dut.ext_frag_hdr.value = 0
    dut.ext_valid.value = 1
    await RisingEdge(dut.clk)
    dut.ext_valid.value = 0

    forced = False
    saw_lwr = saw_err = saw_out = 0
    payload = opcode = None
    for _ in range(80):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if (not forced and int(dut.dec_valid.value) == 1
                and int(dut.dec_opcode.value) == 0x76):
            # deposit: L-PE 0 active for exactly this dispatch cycle (the
            # register is rewritten from s5 at the next edge)
            dut.pe_active_lpe_s6.value = 1
            forced = True
        saw_lwr |= int(dut.any_lower_required.value)
        saw_err |= int(dut.any_error_flag.value)
        if int(dut.ext_out_valid.value) == 1:
            saw_out = 1
            payload = int(dut.ext_out_payload.value)
            opcode = int(dut.ext_out_opcode.value)
            break
    assert forced, "fp dec_valid cycle never observed"
    assert saw_lwr == 1, "L-PE did not raise lower_required for the fp op"
    assert saw_err == 0, "L-PE raised error_flag instead of lower_required"
    assert saw_out == 1 and payload == exp and opcode == 0x76, \
        f"MU result corrupted by the forced L-PE dispatch: " \
        f"out={saw_out} payload={payload} opcode={opcode}"


# =============================================================================
# v1.8.0e §25.3/§25.2 0e1 INTEGRATION — twin-classifier reachability for
# the 0e opcodes (0x6B/0x78/0x79), the frag_mask_full 5-bit-shift
# latent-bug fix regression (16-fragment reassembly), and the widened
# 4-fragment DEQUANT drain through the full Cluster merge. Golden
# authority: scripts/golden_fp32.py fragment-level wrappers (imported,
# never retyped).
# =============================================================================


async def _fire_frag_wave(dut, instr, tag, payloads, payload_b=0,
                          b_valid_last=0):
    """Drive one multi-fragment input wave in index order, instruction +
    EH chain replicated on EVERY beat (the §23.6a SDK contract); the
    payload_b (+valid) rides ONLY the wave-completing beat (the 0x63-65
    / DEQUANT scale-beat contract). len(payloads) = fragment count."""
    tot_m1 = len(payloads) - 1
    assert 1 <= tot_m1 <= 15
    for idx, pl in enumerate(payloads):
        last = (idx == tot_m1)
        dut.ext_instruction.value = instr
        dut.ext_tag.value = tag
        dut.ext_payload.value = pl
        dut.ext_payload_b.value = payload_b if last else 0
        dut.ext_payload_b_valid.value = (b_valid_last if last else 0)
        dut.ext_frag_hdr.value = (idx << 4) | tot_m1
        dut.ext_valid.value = 1
        await RisingEdge(dut.clk)
    dut.ext_valid.value = 0
    dut.ext_frag_hdr.value = 0
    dut.ext_payload_b_valid.value = 0


async def _collect_out_beats(dut, n_beats, window):
    """Collect up to n_beats output pulses (payload/opcode/frag_hdr/tag)
    within `window` cycles; also OR-accumulates the error/lower flags."""
    beats, err, lwr = [], 0, 0
    for i in range(window):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        err |= int(dut.any_error_flag.value)
        lwr |= int(dut.any_lower_required.value)
        if int(dut.ext_out_valid.value):
            beats.append({'cycle': i,
                          'payload': int(dut.ext_out_payload.value),
                          'opcode': int(dut.ext_out_opcode.value),
                          'frag_hdr': int(dut.ext_out_frag_hdr.value),
                          'tag': int(dut.ext_out_tag.value)})
            if len(beats) == n_beats:
                break
    return beats, err, lwr


@cocotb.test()
async def test_cluster_frag_reass_16(dut):
    """v1.8.0e §25.3 mask-fix pin (mandatory repair 2): fragment
    reassembly completes at tot_m1 = 7, 14 AND 15. Pre-fix, the 4-bit
    self-determined shift wrapped 15+1 to 0 (frag_mask_full = 0x0000),
    so a 16-fragment wave NEVER completed — silent CAM-slot rot; the
    widened 5-bit shift yields 0xFFFF. Consumer is a plain ADD .imm16
    (instruction replicated per beat; the completing beat's payload is
    the one dispatched), and intermediate beats must produce NO
    output/error."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    instr = encode_instr(0x10, eh_port(input_port_mask=0x01,
                                       output_port_id=0), eh_imm16(5))
    for wave_no, tot_m1 in ((1, 7), (2, 14), (3, 15)):
        tag = make_tag(wave_number=wave_no, port_context_id=0)
        payloads = [0x1000 * (i + 1) for i in range(tot_m1 + 1)]
        await _fire_frag_wave(dut, instr, tag, payloads)
        beats, err, lwr = await _collect_out_beats(dut, 1, 40)
        assert err == 0 and lwr == 0, \
            f"tot_m1={tot_m1}: err={err} lwr={lwr}"
        assert len(beats) == 1, \
            f"tot_m1={tot_m1}: wave never completed (the pre-fix " \
            f"tot_m1=15 silent-rot signature) — beats={beats}"
        exp = payloads[0] + 5
        assert beats[0]['payload'] == exp, \
            f"tot_m1={tot_m1}: {beats[0]['payload']:#x} != {exp:#x}"


@cocotb.test()
async def test_fp_mu_routing_end_to_end_0e(dut):
    """v1.8.0e §25.3 twin-classifier reachability (the 0e1 lockstep
    edit): 0x6B GAMMA_MUL_W, 0x79 FMINMAX and 0x78 DEQUANT each route
    to the MATMUL_UNIT via is_mul_op and EXECUTE end-to-end through the
    Cluster, bit-exact vs the golden fragment wrappers — a missed twin
    side shows up as a lower_required dead-end or a silent timeout,
    never a wrong-value pass. The FMINMAX cells cross frozen rows 1/2/6
    (-0 vs +0, NaN loses, denormal B bit-preserved DAZ-exempt)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)
    from test_isa_decoder import eh_precision as _ehp, eh_imm64 as _ehi64

    # ---- 0x6B GAMMA_MUL_W: single-beat, gamma via IMM64, 2 frags out
    x_lanes = [((i * 7) + 3) & 0xF for i in range(16)]
    g_lanes = [((-i) & 0xF) for i in range(16)]
    a_frag = sum(v << (4 * i) for i, v in enumerate(x_lanes))
    g_imm = sum(v << (4 * i) for i, v in enumerate(g_lanes))
    instr = encode_instr(0x6B,
                         eh_port(input_port_mask=0x01, output_port_id=0),
                         _ehp(0x10, 0), _ehi64(g_imm),
                         flags=(1 << 2))
    dut.ext_instruction.value = instr
    dut.ext_tag.value = _tag(port_context_id=0)
    dut.ext_payload.value = a_frag
    dut.ext_payload_b.value = 0
    dut.ext_payload_b_valid.value = 0
    dut.ext_frag_hdr.value = 0
    dut.ext_valid.value = 1
    await RisingEdge(dut.clk)
    dut.ext_valid.value = 0
    beats, err, lwr = await _collect_out_beats(dut, 2, 40)
    exp = _G.gamma_mul_w_frags(a_frag, g_imm)
    assert (err, lwr) == (0, 0), f"0x6B: err={err} lwr={lwr}"
    assert [b['payload'] for b in beats] == exp, \
        f"0x6B: {[hex(b['payload']) for b in beats]} != " \
        f"{[hex(x) for x in exp]}"
    assert [b['frag_hdr'] for b in beats] == [0x01, 0x11]
    assert all(b['opcode'] == 0x6B for b in beats)

    # ---- 0x79 FMINMAX: 2-frag A wave, broadcast B on the completing
    # beat, sub-op MINIMUMNUM (absent imm16 default), 2 frags out
    lanes = [0x80000000, 0x00000000, 0x00000001, 0x7FC00000]
    b_bits = 0x00000001            # +denormal B — row-6 DAZ-exempt probe
    a_frags = _G.lanes_to_frags(lanes, 32)
    instr = encode_instr(0x79,
                         eh_port(input_port_mask=0x01, output_port_id=0),
                         _ehp(0x14, 0),
                         flags=(1 << 3) | (1 << 2))   # opb | prec
    tag = make_tag(wave_number=7, port_context_id=0)
    await _fire_frag_wave(dut, instr, tag, a_frags,
                          payload_b=b_bits, b_valid_last=1)
    beats, err, lwr = await _collect_out_beats(dut, 2, 40)
    exp = _G.fminmax_frags(a_frags, b_bits,
                           _G.FMINMAX_OP_CODE['MINIMUMNUM'])
    assert (err, lwr) == (0, 0), f"0x79: err={err} lwr={lwr}"
    assert [b['payload'] for b in beats] == exp, \
        f"0x79: {[hex(b['payload']) for b in beats]} != " \
        f"{[hex(x) for x in exp]}"
    assert [b['frag_hdr'] for b in beats] == [0x01, 0x11]
    assert all(b['opcode'] == 0x79 for b in beats)

    # ---- 0x78 DEQUANT int8-16: 2-frag A wave, fp32 scale on the
    # completing beat (the pinned scale-beat contract), 4 frags out
    lanes8 = [((i * 29) ^ 0xA5) & 0xFF for i in range(16)]
    a_frags = _G.lanes_to_frags(lanes8, 8)
    scale = _f2b(1.25)
    instr = encode_instr(0x78,
                         eh_port(input_port_mask=0x01, output_port_id=0),
                         _ehp(0x11, 0),
                         flags=(1 << 2))
    tag = make_tag(wave_number=9, port_context_id=0)
    await _fire_frag_wave(dut, instr, tag, a_frags,
                          payload_b=scale, b_valid_last=1)
    beats, err, lwr = await _collect_out_beats(dut, 4, 340)
    exp = _G.dequant_frags(a_frags, scale, _G.DT_INT8)
    assert (err, lwr) == (0, 0), f"0x78: err={err} lwr={lwr}"
    assert len(beats) == 4, f"0x78: {len(beats)} fragments != 4"
    assert [b['payload'] for b in beats] == exp, \
        f"0x78: {[hex(b['payload']) for b in beats]} != " \
        f"{[hex(x) for x in exp]}"
    assert [b['frag_hdr'] for b in beats] == [0x03, 0x13, 0x23, 0x33]
    assert all(b['opcode'] == 0x78 for b in beats)
    # drain contiguity survives the Cluster output merge (1 beat/cycle)
    cyc = [b['cycle'] for b in beats]
    assert cyc == list(range(cyc[0], cyc[0] + 4)), \
        f"0x78 drain not contiguous through the merge: {cyc}"


@cocotb.test()
async def test_dequant_cluster_int4_8frag_drain(dut):
    """v1.8.0e §25.3 widened-drain invariants through the FULL Cluster:
    the int4-32 DEQUANT form emits 8 fragments with the 4-bit header
    nibbles 0x07..0x77 in order, 1 beat/cycle through the output merge,
    bit-exact vs golden; tag constant across the wave; and a subsequent
    2-fragment wide op is bit-identical (no FSM residue downstream of
    an 8-beat drain)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)
    from test_isa_decoder import eh_precision as _ehp

    lanes4 = [((i * 5) + 1) & 0xF for i in range(32)]
    a_frags = _G.lanes_to_frags(lanes4, 4)
    scale = _f2b(-0.5)
    instr = encode_instr(0x78,
                         eh_port(input_port_mask=0x01, output_port_id=0),
                         _ehp(0x10, 0),
                         flags=(1 << 2))
    tag = make_tag(wave_number=11, port_context_id=0)
    await _fire_frag_wave(dut, instr, tag, a_frags,
                          payload_b=scale, b_valid_last=1)
    beats, err, lwr = await _collect_out_beats(dut, 8, 400)
    exp = _G.dequant_frags(a_frags, scale, _G.DT_INT4)
    assert (err, lwr) == (0, 0), f"err={err} lwr={lwr}"
    assert len(beats) == 8, f"{len(beats)} fragments != 8"
    assert [b['payload'] for b in beats] == exp, \
        f"{[hex(b['payload']) for b in beats]} != {[hex(x) for x in exp]}"
    assert [b['frag_hdr'] for b in beats] == \
        [(i << 4) | 0x7 for i in range(8)]
    assert len({b['tag'] for b in beats}) == 1
    cyc = [b['cycle'] for b in beats]
    assert cyc == list(range(cyc[0], cyc[0] + 8)), f"drain gap: {cyc}"

    # no-residue: an existing 2-fragment emitter right after
    lo, hi = 0x0123456789ABCDEF, 0xFEDCBA9876543210
    consumer = encode_instr(0x60, eh_port(input_port_mask=0x01,
                                          output_port_id=0), eh_imm16(2))
    tag2 = make_tag(wave_number=12, port_context_id=0)
    await _complete_wide_wave(dut, tag2, lo, hi, consumer)
    beats2, err, lwr = await _collect_out_beats(dut, 2, 30)
    exp_lo = sum(((((lo >> (4 * i)) & 0xF) + 2) & 0xF) << (4 * i)
                 for i in range(16))
    exp_hi = sum(((((hi >> (4 * i)) & 0xF) + 2) & 0xF) << (4 * i)
                 for i in range(16))
    assert (err, lwr) == (0, 0)
    assert [(b['payload'], b['frag_hdr']) for b in beats2] == \
        [(exp_lo, 0x01), (exp_hi, 0x11)], \
        "2-frag emitter corrupted after the 8-beat drain"


# =============================================================================
# v1.8.0e §25.2.4/§25.3 0e2 — 0x70 VFMA_ACC through the FULL Cluster:
# twin-classifier reachability (the 0e2 lockstep edit), the FIRST
# 16-fragment emit through the output merge, and the 16-fragment
# REASSEMBLY round-trip — the emitted wave fed back as an input wave
# closes the loop on the frag_mask_full 5-bit-shift fix (pre-fix,
# tot_m1=15 input waves silently rotted in the CAM). Golden authority:
# scripts/golden_fp32.py vfma_frags (imported, never retyped).
# =============================================================================


@cocotb.test()
async def test_vfma_cluster_16frag_roundtrip(dut):
    """v1.8.0e 0e2: (a) a 0x70 int4 wave (2-frag A in, B via IMM64
    replicated per beat — the VDOT instruction-replication contract)
    routes to the MATMUL_UNIT via is_mul_op, runs the lane loop, and
    emits 16 fragments through the Cluster merge — bit-exact vs golden
    vfma_frags, headers 0x0F..0xFF in order, 1 beat/cycle contiguous,
    tag constant; (b) the EMITTED 16-fragment wave is fed back as an
    input wave to a plain ADD .imm16 consumer and REASSEMBLES (the
    tot_m1=15 mask-fix consumer round-trip — this dispatch never
    completes on pre-fix RTL); (c) an int8 0x70 wave then emits 8
    fragments bit-exact (both forms cross the merge)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)
    from test_isa_decoder import eh_precision as _ehp, eh_imm64 as _ehi64

    # ---- (a) int4-32: 2-frag A wave in -> 16 fragments out
    lanes4 = [((i * 11) + 3) & 0xF for i in range(32)]
    a_frags = _G.lanes_to_frags(lanes4, 4)
    b64 = ((0x7FFFFFF0 & 0xFFFFFFFF) << 32) | 0xE     # b=-2, c near MAX
    instr = encode_instr(0x70,
                         eh_port(input_port_mask=0x01, output_port_id=0),
                         _ehp(0x10, 0), _ehi64(b64),
                         flags=(1 << 2))              # prec (B is imm)
    tag = make_tag(wave_number=21, port_context_id=0)
    await _fire_frag_wave(dut, instr, tag, a_frags)
    beats, err, lwr = await _collect_out_beats(dut, 16, 200)
    exp = _G.vfma_frags(a_frags, b64, _G.DT_INT4)
    assert (err, lwr) == (0, 0), f"0x70 int4: err={err} lwr={lwr}"
    assert len(beats) == 16, \
        f"0x70 int4: {len(beats)} fragments != 16 (twin-classifier " \
        f"dead-end or drain truncation)"
    assert [b['payload'] for b in beats] == exp, \
        f"0x70 int4: {[hex(b['payload']) for b in beats]} != " \
        f"{[hex(x) for x in exp]}"
    assert [b['frag_hdr'] for b in beats] == \
        [(i << 4) | 0xF for i in range(16)], \
        f"header sequence {[hex(b['frag_hdr']) for b in beats]}"
    assert all(b['opcode'] == 0x70 for b in beats)
    assert len({b['tag'] for b in beats}) == 1
    cyc = [b['cycle'] for b in beats]
    assert cyc == list(range(cyc[0], cyc[0] + 16)), \
        f"16-frag drain not contiguous through the merge: {cyc}"

    # ---- (b) ROUND-TRIP: the emitted 16-fragment wave becomes an
    # INPUT wave (tot_m1 = 15) to a plain ADD .imm16 — reassembly at
    # the fixed frag_mask_full completes and dispatches (fragment 0's
    # payload is the dispatched word, the frag-reass contract pinned by
    # test_cluster_frag_reass_16)
    payloads = [b['payload'] for b in beats]
    consumer = encode_instr(0x10, eh_port(input_port_mask=0x01,
                                          output_port_id=0), eh_imm16(5))
    tag2 = make_tag(wave_number=22, port_context_id=0)
    await _fire_frag_wave(dut, consumer, tag2, payloads)
    beats2, err, lwr = await _collect_out_beats(dut, 1, 40)
    assert (err, lwr) == (0, 0), f"round-trip: err={err} lwr={lwr}"
    assert len(beats2) == 1, \
        "16-fragment VFMA output wave never reassembled on re-entry " \
        "(the pre-fix tot_m1=15 silent-CAM-rot signature)"
    exp_rt = (payloads[0] + 5) & ((1 << 64) - 1)
    assert beats2[0]['payload'] == exp_rt, \
        f"round-trip: {beats2[0]['payload']:#x} != {exp_rt:#x}"

    # ---- (c) int8-16 -> 8 fragments through the same path
    lanes8 = [((i * 29) ^ 0x5C) & 0xFF for i in range(16)]
    a8_frags = _G.lanes_to_frags(lanes8, 8)
    b64_8 = ((0x80000000 & 0xFFFFFFFF) << 32) | 0x80  # b=-128, c=MIN
    instr8 = encode_instr(0x70,
                          eh_port(input_port_mask=0x01, output_port_id=0),
                          _ehp(0x11, 0), _ehi64(b64_8),
                          flags=(1 << 2))
    tag3 = make_tag(wave_number=23, port_context_id=0)
    await _fire_frag_wave(dut, instr8, tag3, a8_frags)
    beats3, err, lwr = await _collect_out_beats(dut, 8, 120)
    exp8 = _G.vfma_frags(a8_frags, b64_8, _G.DT_INT8)
    assert (err, lwr) == (0, 0), f"0x70 int8: err={err} lwr={lwr}"
    assert len(beats3) == 8, f"0x70 int8: {len(beats3)} fragments != 8"
    assert [b['payload'] for b in beats3] == exp8, \
        f"0x70 int8: {[hex(b['payload']) for b in beats3]} != " \
        f"{[hex(x) for x in exp8]}"
    assert [b['frag_hdr'] for b in beats3] == \
        [(i << 4) | 0x7 for i in range(8)]


# =============================================================================
# v1.9 §26.7 — new directed tests for the tag-indexed MU/DU bank-fix
# (test_plan items 11, 12, 13, 15).
# =============================================================================

# eh_imm64 isn't in this module's top-level import list; pull it in once.
from test_isa_decoder import eh_imm64 as eh_imm64_local  # noqa: E402


def _mul_instr(mask, pcid, imm64):
    return encode_instr(0x12, eh_port(input_port_mask=mask, output_port_id=pcid),
                        eh_imm64_local(imm64))


def _div_instr(mask, pcid, imm64):
    return encode_instr(0x13, eh_port(input_port_mask=mask, output_port_id=pcid),
                        eh_imm64_local(imm64))


@cocotb.test()
async def test_bank_tag_latch_no_intervening_hazard(dut):
    """NEW v1.9 §26.7 item 11 (positive proof, MU depth-2 / DU depth-1):
    dispatch 2 DIFFERENT-target mu_out_valid-routed ops in close
    succession — tighter than the retired SDK "no intervening mul-class
    dispatch" software rule ever required — and confirm BOTH route to
    their OWN target bank via TAG MATCH, with zero cross-contamination.
    This is the replacement design's core regression: the OLD positional
    shift-tap assumed a fixed dispatch-to-completion latency and would
    silently misroute a later dispatch's target onto an earlier
    dispatch's completion (or vice versa) once case_result_s2's own +1
    cycle broke that fixed-latency assumption.

    (a) DU (depth-1): fire DIV0 (pcid=0), let it fully drain, then fire
    DIV1 (pcid=1) immediately (no artificial extra idle padding) —
    confirm DIV1 lands in bank 1 with the RIGHT value, not bank 0's
    stale residue.

    (b) MU (depth-2): fire two 0x12 MUL dispatches to DIFFERENT targets
    (pcid=0, pcid=1) as close together as the shared EHDecode's own
    accept-timing allows (empirically the earliest a second token is
    reliably accepted, NOT an arbitrarily generous gap) — confirm BOTH
    results land bit-exact in their OWN target bank, in the OWN arrival
    order, with no swap/cross-write. (Genuine simultaneous ROW occupancy
    for two MULs was checked separately and found NOT reachable via
    front-door dispatch with this EHDecode's actual timing — MUL's own
    busy window, ~3 cycles, clears before the shared EHDecode can accept
    a second token, ~9-10 cycles minimum — so this sub-test instead
    proves the achievable, and actually regression-relevant, property:
    correct tag-keyed routing under back-to-back dispatch, not stale
    positional bleed.)"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # ---- (a) DU depth-1 ---------------------------------------------------
    await _reset(dut)
    dut.ext_instruction.value = _div_instr(0x01, 0, 3)
    dut.ext_tag.value = _tag(port_context_id=0)
    dut.ext_payload.value = 100
    dut.ext_payload_b_valid.value = 0
    dut.ext_valid.value = 1
    await RisingEdge(dut.clk)
    dut.ext_valid.value = 0
    beats0, err0, lwr0 = await _collect_out_beats(dut, 1, 90)
    assert (err0, lwr0) == (0, 0) and len(beats0) == 1, \
        f"DIV0 (pcid=0) did not drain cleanly: err={err0} lwr={lwr0} {beats0}"
    assert beats0[0]['payload'] == 100 // 3

    dut.ext_instruction.value = _div_instr(0x02, 1, 7)
    dut.ext_tag.value = _tag(port_context_id=1)
    dut.ext_payload.value = 200
    dut.ext_payload_b_valid.value = 0
    dut.ext_valid.value = 1
    await RisingEdge(dut.clk)
    dut.ext_valid.value = 0
    beats1, err1, lwr1 = await _collect_out_beats(dut, 1, 90)
    assert (err1, lwr1) == (0, 0) and len(beats1) == 1, \
        f"DIV1 (pcid=1) did not drain cleanly: err={err1} lwr={lwr1} {beats1}"
    assert beats1[0]['payload'] == 200 // 7, \
        f"DIV1 misrouted/corrupted: {beats1[0]['payload']} != {200 // 7} " \
        f"-- stale DU-row residue from DIV0 would show up here"

    # ---- (b) MU depth-2, back-to-back different-target MUL dispatch ------
    await _reset(dut)
    dut.ext_instruction.value = _mul_instr(0x01, 0, 2)
    dut.ext_tag.value = _tag(port_context_id=0)
    dut.ext_payload.value = 100
    dut.ext_payload_b_valid.value = 0
    dut.ext_valid.value = 1
    await RisingEdge(dut.clk)   # P0 -- MUL0's own token pulse edge
    # v1.9.2 §22.14b-3 자극 정정: 여기서 ext_valid 를 **내려야** 한다.
    # 원래 이 줄이 없어서 ext_valid 가 P0 부터 P1 까지 5 사이클 연속으로
    # 서 있었고, 그것은 "토큰 1건" 이 아니라 **같은 파동 5건 주입**이다.
    # 구 RTL 은 그 4건을 조용히 삼켰기 때문에(§22.14b-1 결함 그 자체)
    # 자극의 오류가 드러나지 않았다. skid 착지 후에는 2번째가 보류돼
    # 재투입되고 3번째부터는 loud overflow fault 가 뜬다 — 즉 이 정정은
    # 검사를 약화시키는 것이 아니라, 테스트가 의도한 자극("2건 디스패치")
    # 을 처음으로 실제로 주는 것이다.
    dut.ext_valid.value = 0
    # Empirically the earliest the shared EHDecode reliably accepts a
    # SECOND, independent token after this one (see session notes: the
    # standalone ISA_Decoder chain-walk needs ~5 edges before dec_valid,
    # and the Cluster-level EHDecode frees up ~1 edge ahead of its own
    # dec_valid). v1.9.2 이후 더 이른 주입은 **소실되지 않고 보류**된다
    # (§22.14b-3) — 그 성질은 test_skid_no_drop_delay_sweep 가 직접 pin
    # 하며, 여기서는 원래의 back-to-back 라우팅 성질만 본다.
    for _ in range(4):
        await RisingEdge(dut.clk)
    dut.ext_instruction.value = _mul_instr(0x02, 1, 3)
    dut.ext_tag.value = _tag(port_context_id=1)
    dut.ext_payload.value = 200
    dut.ext_valid.value = 1
    await RisingEdge(dut.clk)   # P1 -- MUL1's own token pulse edge
    dut.ext_valid.value = 0
    beats, err, lwr = await _collect_out_beats(dut, 2, 30)
    assert (err, lwr) == (0, 0), f"err={err} lwr={lwr} beats={beats}"
    assert len(beats) == 2, f"expected 2 MUL results, got {beats}"
    exp0, exp1 = 100 * 2, 200 * 3
    assert beats[0]['payload'] == exp0, \
        f"MUL0 (pcid=0): {beats[0]['payload']} != {exp0}"
    assert beats[1]['payload'] == exp1, \
        f"MUL1 (pcid=1): {beats[1]['payload']} != {exp1} " \
        f"-- stale MU-row residue from MUL0 would show up here"
    assert ((beats[0]['tag'] >> 16) & 0xFFFF) != ((beats[1]['tag'] >> 16) & 0xFFFF), \
        "both results carry the same port_context_id in the forwarded " \
        "tag -- routing collapsed"


@cocotb.test()
async def test_bank_tag_collision_interlock(dut):
    """NEW v1.9 §26.7 item 12: force a table row to be reused while still
    busy and confirm the synthesizable STICKY `bank_tag_collision_error`
    status bit fires -- a real hardware fault, not a sim-only assertion
    (closing exactly the correctness-lens gap the spec names).

    (a) DU (depth-1, the clean/unambiguous case): fire a long DIV0
    (pcid=0), and WHILE it is still busy (DIV's ~68-cycle bit-serial FSM
    vastly outlasts the shared EHDecode's own ~5-10 cycle re-accept
    latency, so this is trivially reachable — unlike MU-MUL/MU-MUL
    overlap) fire a second DIV1 (pcid=1). Assert: the collision bit
    fires: it stays STICKY well past DIV0's own natural completion (does
    NOT self-clear); and DIV0's own result is still delivered bit-exact
    to its own (pcid=0) bank, undisturbed by the rejected DIV1 attempt.
    du_launch is untouched by the residual-risk-11 fix (DIV bypasses
    case_result_s2, confirmed via PE_Core.v's DIV_IDLE launch check —
    see the Cluster.v header comment), so this sub-test's behavior is
    unchanged from the original v1.9 landing.

    (b) MU, residual-risk-11 CLOSING PROOF (§26.8 item 11): this is the
    EXACT scenario that originally revealed the gap -- three long
    MU-hosted ops (0x74 FSCALAR FS_DIV, pcid=0/1/2), each timed to land
    while the previous one(s) are still busy. Pre-fix, Cluster's
    un-gated `mu_launch` allocated a table row for ops 1 and 2 even
    though PE_Core's own T+1 stage-2 busy-check (`cr_needs_regs_free &&
    !output_regs_free`) silently rejected both (fp_busy from op0 still
    held) -- 2 PHANTOM rows, so this test's original assertion
    (`saw_collision`) passed, but for the WRONG reason (table exhaustion
    from phantom occupancy, not a genuine tag reuse). Post-fix,
    `mu_launch_other_now`'s row commit is deferred one cycle and gated
    on live `mu_pe_ready`, so a busy-rejected dispatch allocates
    NOTHING. Re-running this UNCHANGED stimulus must therefore show: NO
    collision at all; `mu_row1` never goes busy (row0, held by op0, is
    the only row ever touched); both rejected attempts (op1, op2) raise
    `lower_required`; and op0's own result is delivered undisturbed.
    This IS the closing proof for residual risk 11 — the phantom-row
    exhaustion this scenario used to trigger no longer occurs."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # ---- (a) DU depth-1 collision ------------------------------------------
    await _reset(dut)
    dut.ext_instruction.value = _div_instr(0x01, 0, 3)
    dut.ext_tag.value = _tag(port_context_id=0)
    dut.ext_payload.value = 100
    dut.ext_payload_b_valid.value = 0
    dut.ext_valid.value = 1
    fired1 = False
    pending = [True, False]
    saw_collision = False
    saw_out0 = None
    for i in range(90):
        await RisingEdge(dut.clk)
        for k in range(2):
            if pending[k]:
                dut.ext_valid.value = 0
                pending[k] = False
        await Timer(1, units="ns")
        if i == 9 and not fired1:
            fired1 = True
            dut.ext_instruction.value = _div_instr(0x02, 1, 7)
            dut.ext_tag.value = _tag(port_context_id=1)
            dut.ext_payload.value = 999
            dut.ext_payload_b_valid.value = 0
            dut.ext_valid.value = 1
            pending[1] = True
        if int(dut.bank_tag_collision_error.value):
            saw_collision = True
        if int(dut.ext_out_valid.value):
            saw_out0 = int(dut.ext_out_payload.value)
    assert saw_collision, "DU depth-1 collision never fired"
    assert int(dut.bank_tag_collision_error.value) == 1, \
        "bank_tag_collision_error did not stay sticky through the end of " \
        "the run (well past both ops' natural busy windows)"
    assert saw_out0 == 100 // 3, \
        f"DIV0's own result corrupted by the rejected DIV1 attempt: {saw_out0}"

    # ---- (b) MU residual-risk-11 closing proof (unchanged stimulus) -------
    await _reset(dut)
    from test_isa_decoder import eh_precision as _ehp

    def _fs_div_instr(mask, pcid):
        return encode_instr(0x74, eh_port(input_port_mask=mask, output_port_id=pcid),
                            _ehp(0x14, 0), eh_imm16((_FS['FS_DIV'] & 0xF) << 4),
                            flags=(1 << 2))

    a, b = _f2b(355.0), _f2b(113.0)
    dut.ext_instruction.value = _fs_div_instr(0x01, 0)
    dut.ext_tag.value = _tag(port_context_id=0)
    dut.ext_payload.value = a
    dut.ext_payload_b.value = b
    dut.ext_payload_b_valid.value = 1
    dut.ext_valid.value = 1
    fired = [False, False]
    pending = [True, False, False]
    saw_collision = False
    row1_ever_busy = False
    saw_lower = False
    out0 = None
    for i in range(60):
        await RisingEdge(dut.clk)
        for k in range(3):
            if pending[k]:
                dut.ext_valid.value = 0
                pending[k] = False
        await Timer(1, units="ns")
        if i == 10 and not fired[0]:
            fired[0] = True
            dut.ext_instruction.value = _fs_div_instr(0x02, 1)
            dut.ext_tag.value = _tag(port_context_id=1)
            dut.ext_payload.value = a
            dut.ext_payload_b.value = b
            dut.ext_payload_b_valid.value = 1
            dut.ext_valid.value = 1
            pending[1] = True
        if i == 20 and not fired[1]:
            fired[1] = True
            dut.ext_instruction.value = _fs_div_instr(0x04, 2)
            dut.ext_tag.value = _tag(port_context_id=2)
            dut.ext_payload.value = a
            dut.ext_payload_b.value = b
            dut.ext_payload_b_valid.value = 1
            dut.ext_valid.value = 1
            pending[2] = True
        if int(dut.bank_tag_collision_error.value):
            saw_collision = True
        if int(dut.mu_row1_busy.value):
            row1_ever_busy = True
        if int(dut.any_lower_required.value):
            saw_lower = True
        if int(dut.ext_out_valid.value) and out0 is None:
            out0 = int(dut.ext_out_payload.value)
    assert not saw_collision, \
        "bank_tag_collision_error fired -- residual risk 11 regressed: " \
        "a busy-rejected FS_DIV dispatch phantom-allocated a table row"
    assert not row1_ever_busy, \
        "mu_row1 went busy at some point during this run -- a " \
        "busy-rejected dispatch (op1 pcid=1 or op2 pcid=2) consumed a " \
        "table row it never should have touched (op0 alone should hold " \
        "row0 for the entire run)"
    assert saw_lower, \
        "neither busy-rejected FS_DIV dispatch (pcid=1/2) ever raised " \
        "any_lower_required -- PE_Core's own T+1 busy-check should still " \
        "fire for each even though Cluster no longer allocates for them"
    exp0 = _G.micro_fscalar(_FS['FS_DIV'], a, b)
    assert out0 == exp0, \
        f"op0's own FS_DIV result corrupted: {out0:#x} != {exp0:#x}"


@cocotb.test()
async def test_mu_busy_reject_no_phantom_row(dut):
    """NEW residual-risk-11 closing fix (§26.8 item 11 / Cluster.v
    `mu_launch_mul` + `mu_launch_other_now` timing split): a non-MUL
    dispatch that PE_Core busy-rejects at its real T+1 stage-2 decision
    must NOT consume a MU-table row.

    Fire op0 (0x74 FSCALAR FS_DIV, pcid=0) -- takes row0 for its fp
    flight. WHILE op0 is still busy, fire op1 (a DIFFERENT non-MUL
    dispatch, another FS_DIV, pcid=1) -- PE_Core busy-rejects it
    (lower_required); row1 must NEVER go busy in response (asserted by
    direct per-cycle polling, not inferred from a later side effect).
    AFTER op0 fully drains, fire op2 (a third, DIFFERENT-target FS_DIV,
    pcid=2) as corroborating evidence: it lands in row0, not row1 -- the
    proof the task calls for that row1 was never phantom-occupied by
    op1's rejected attempt (this alone is not conclusive, since row0 is
    always preferred when free either way, which is exactly why the
    direct per-cycle poll above is the primary assertion)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)
    from test_isa_decoder import eh_precision as _ehp

    def _fs_div_instr(mask, pcid):
        return encode_instr(0x74, eh_port(input_port_mask=mask, output_port_id=pcid),
                            _ehp(0x14, 0), eh_imm16((_FS['FS_DIV'] & 0xF) << 4),
                            flags=(1 << 2))

    a, b = _f2b(355.0), _f2b(113.0)
    dut.ext_instruction.value = _fs_div_instr(0x01, 0)
    dut.ext_tag.value = _tag(port_context_id=0)
    dut.ext_payload.value = a
    dut.ext_payload_b.value = b
    dut.ext_payload_b_valid.value = 1
    dut.ext_valid.value = 1
    fired1 = False
    pending = [True, False]
    row1_ever_busy = False
    saw_lower_op1 = False
    out0 = None
    for i in range(60):
        await RisingEdge(dut.clk)
        for k in range(2):
            if pending[k]:
                dut.ext_valid.value = 0
                pending[k] = False
        await Timer(1, units="ns")
        if i == 5 and not fired1:
            fired1 = True
            dut.ext_instruction.value = _fs_div_instr(0x02, 1)
            dut.ext_tag.value = _tag(port_context_id=1)
            dut.ext_payload.value = a
            dut.ext_payload_b.value = b
            dut.ext_payload_b_valid.value = 1
            dut.ext_valid.value = 1
            pending[1] = True
        if int(dut.mu_row1_busy.value):
            row1_ever_busy = True
        if int(dut.any_lower_required.value):
            saw_lower_op1 = True
        if int(dut.ext_out_valid.value) and out0 is None:
            out0 = int(dut.ext_out_payload.value)
    assert saw_lower_op1, \
        "the busy-rejected op1 (FS_DIV pcid=1, dispatched mid-flight) " \
        "never raised any_lower_required -- PE_Core's own T+1 busy-check " \
        "should still fire"
    assert not row1_ever_busy, \
        "mu_row1 went busy in response to a busy-rejected dispatch -- " \
        "phantom row allocated (residual risk 11 regression)"
    exp0 = _G.micro_fscalar(_FS['FS_DIV'], a, b)
    assert out0 == exp0, \
        f"op0's own FS_DIV result corrupted by op1's rejected attempt: " \
        f"{out0:#x} != {exp0:#x}"

    # ---- corroborating: a subsequent, genuinely-free-MU dispatch fills
    # row0, not row1 (same run, no reset — op0 has fully drained by now,
    # op1's rejected attempt left nothing behind to collide with).
    dut.ext_instruction.value = _fs_div_instr(0x04, 2)
    dut.ext_tag.value = _tag(port_context_id=2)
    dut.ext_payload.value = a
    dut.ext_payload_b.value = b
    dut.ext_payload_b_valid.value = 1
    dut.ext_valid.value = 1
    await RisingEdge(dut.clk)
    dut.ext_valid.value = 0
    used_row0, used_row1, out2 = False, False, None
    for _ in range(80):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.mu_row0_busy.value):
            used_row0 = True
        if int(dut.mu_row1_busy.value):
            used_row1 = True
        if int(dut.ext_out_valid.value):
            out2 = int(dut.ext_out_payload.value)
            break
    assert used_row0 and not used_row1, \
        f"op2 (pcid=2) should land in row0 (row1 free but unused) -- " \
        f"used_row0={used_row0} used_row1={used_row1}"
    assert out2 == exp0, f"op2's FS_DIV result: {out2:#x} != {exp0:#x}"


@cocotb.test()
async def test_vdot_acc_reduce_rides_mu_bank(dut):
    """NEW v1.9 §26.7 item 13 (0x71/0x72 scope-check): confirm --directly,
    not by inference-- WHICH path VDOT_ACC (0x71) and ACC_REDUCE (0x72)
    actually take through Cluster.v.

    This test's assertion direction is the OPPOSITE of what spec §26.5's
    scope-exclusion item (a) and the mandate's own item 2(c) phrasing
    ("bank-table exclusion OR inclusion, per whatever the RTL stage
    found") both flag as unresolved-by-inference: Cluster.v's own §26.5
    comment block (this repo, "Independently verified (not assumed)")
    already determined, by direct RTL inspection, that 0x71/0x72 ARE
    ordinary MU-hosted compute-inline case arms whose PE_Core
    output_payload/output_valid IS literally what Cluster.v renames to
    mu_out_payload/mu_out_valid for the MU instance -- there is no
    alternate "stays inside PE_Core, never surfaces" path for them to
    take. This test re-confirms that RTL-level finding dynamically
    (not by re-reading the comment) and, since it means 0x71/0x72 DO
    consume MU-table capacity like every other MU-hosted opcode, also
    confirms the bank-fix routes their (non-MUL, single-flight) rows
    correctly."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    # ---- 0x71 VDOT_ACC ------------------------------------------------
    await _reset(dut)
    a_lanes = [(i % 15) - 7 for i in range(32)]
    b_lanes = [((i * 3) % 15) - 7 for i in range(32)]
    a = _v180b_pack_int4(*[v & 0xF for v in a_lanes])
    b = _v180b_pack_int4(*[v & 0xF for v in b_lanes])
    golden = (sum(x * y for x, y in zip(a_lanes, b_lanes)) + 5) % (1 << 64)
    wide = (a & ((1 << 128) - 1)) | ((b & ((1 << 128) - 1)) << 128)
    payloads = [(wide >> (64 * i)) & ((1 << 64) - 1) for i in range(4)]
    from test_isa_decoder import eh_precision as _ehp
    instr71 = encode_instr(0x71, eh_port(input_port_mask=0x01, output_port_id=0),
                           _ehp(0x10, 0), eh_imm16(5), flags=(1 << 2))
    tag71 = _tag(port_context_id=0)
    mu_out_valid_seen_71 = False
    mu_row_is_mul_71 = None
    for idx in range(4):
        dut.ext_instruction.value = instr71
        dut.ext_tag.value = tag71
        dut.ext_payload.value = payloads[idx]
        dut.ext_payload_b.value = 0
        dut.ext_payload_b_valid.value = 1
        dut.ext_frag_hdr.value = (idx << 4) | 0x3
        dut.ext_valid.value = 1
        await RisingEdge(dut.clk)
        if int(dut.mu_row0_busy.value):
            mu_row_is_mul_71 = int(dut.mu_row0_is_mul.value)
        if int(dut.mu_out_valid.value):
            mu_out_valid_seen_71 = True
    dut.ext_valid.value = 0
    dut.ext_frag_hdr.value = 0
    out71 = None
    for _ in range(30):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.mu_row0_busy.value) and mu_row_is_mul_71 is None:
            mu_row_is_mul_71 = int(dut.mu_row0_is_mul.value)
        if int(dut.mu_out_valid.value):
            mu_out_valid_seen_71 = True
        if int(dut.ext_out_valid.value) == 1:
            out71 = int(dut.ext_out_payload.value)
            break
    assert out71 == golden, f"0x71 VDOT_ACC: {out71} != {golden}"
    assert mu_out_valid_seen_71, \
        "0x71 VDOT_ACC never asserted mu_out_valid -- contradicts the " \
        "RTL-verified finding (Cluster.v §26.5 comment) that it rides " \
        "the same MU path as every other MU-hosted opcode"
    assert mu_row_is_mul_71 == 0, \
        "0x71 VDOT_ACC's MU-table row was tagged row_is_mul=1 -- it " \
        "must be classified non-MUL (dec_opcode != 8'h12 at launch)"

    # ---- 0x72 ACC_REDUCE (SUM) -----------------------------------------
    await _reset(dut)
    lanes = [(-8 if i == 3 else (i % 15) - 7) for i in range(32)]
    a_wide = _v180b_pack_int4(*[v & 0xF for v in lanes])
    exp_sum = sum(lanes) % (1 << 64)
    payloads72 = [(a_wide >> (64 * i)) & ((1 << 64) - 1) for i in range(2)]
    from generated_isa_tables import ACC_REDUCE_OP_CODE
    instr72 = encode_instr(0x72, eh_port(input_port_mask=0x01, output_port_id=0),
                           _ehp(0x10, 0), eh_imm16(ACC_REDUCE_OP_CODE['sum'] << 4),
                           flags=(1 << 2))
    tag72 = _tag(port_context_id=0)
    mu_out_valid_seen_72 = False
    for idx, pl in enumerate(payloads72):
        dut.ext_instruction.value = instr72
        dut.ext_tag.value = tag72
        dut.ext_payload.value = pl
        dut.ext_payload_b_valid.value = 0
        dut.ext_frag_hdr.value = (idx << 4) | 0x1
        dut.ext_valid.value = 1
        await RisingEdge(dut.clk)
        if int(dut.mu_out_valid.value):
            mu_out_valid_seen_72 = True
    dut.ext_valid.value = 0
    dut.ext_frag_hdr.value = 0
    out72 = None
    for _ in range(30):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.mu_out_valid.value):
            mu_out_valid_seen_72 = True
        if int(dut.ext_out_valid.value) == 1:
            out72 = int(dut.ext_out_payload.value)
            break
    assert out72 == exp_sum, f"0x72 ACC_REDUCE: {out72} != {exp_sum}"
    assert mu_out_valid_seen_72, \
        "0x72 ACC_REDUCE never asserted mu_out_valid -- contradicts the " \
        "RTL-verified finding (Cluster.v §26.5 comment) that it rides " \
        "the same MU path as every other MU-hosted opcode"


@cocotb.test()
async def test_twin_classifier_mu_bank_coverage(dut):
    """NEW v1.9 §26.7 item 15: the final defense line against a silent MU
    bank-table under-fill. Two halves:

    (a) POSITIVE — every opcode the twin classifier (extracted from
    Cluster.v `is_mul_op`, same technique as
    test_twin_classifier_lockstep_static) actually claims MUST really
    assert mu_out_valid at some point when dispatched -- a classified-
    but-unreachable opcode would be just as dangerous a gap as an
    unclassified-but-reachable one (dead table capacity masking a real
    miss elsewhere). This also directly confirms (not assumes) that
    is_mul_op routes 0x32 EINSUM on the RAW OPCODE ALONE, before any
    EH/subscript decode -- so even a narrow, non-wide signature
    (SIG_MATMUL_2X2) is unconditionally sent to the MU-hosted PE and
    consumes table capacity, same as the wide sub-tree forms.

    (b) NEGATIVE — a representative sample of opcodes NOT in the
    classifier set (plain ALU, the wide-SIMD family via 0x69, and 0x7C
    -- which test_twin_classifier_lockstep_static already pins OUT by
    name) must NEVER assert mu_out_valid — a full 0x00-0xFF sweep is not
    attempted here (most encodings would only exercise decode-error
    paths, not the dispatch logic this test actually cares about); this
    is a targeted, not exhaustive, negative check."""
    import re
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, 'Cluster.v')) as _f:
        text = _f.read()
    idx = text.index('wire is_mul_op')
    # comment-stripped scan — see _classifier_set in
    # test_twin_classifier_lockstep_static for why.
    _body = text[idx:]
    _stripped = '\n'.join(ln.split('//')[0] for ln in _body.splitlines())
    expr = _stripped[:_stripped.index(';')]
    classified = set(int(m, 16) for m in re.findall(r"8'h([0-9A-Fa-f]{2})", expr))
    assert classified, "failed to extract is_mul_op from Cluster.v"

    from test_isa_decoder import eh_precision as _ehp

    async def _saw_mu(dut, drive_coro, cycles=400):
        """Run `drive_coro` (an async callable taking dut) concurrently
        with a mu_out_valid watcher and report whether it ever pulsed.
        The watcher is JOINED (awaited to completion), not merely
        started-then-killed-early -- the full window covers even the
        slowest classified op (0x78 DEQUANT int8-16, mu_out_valid doesn't
        pulse until ~100+ cycles in; a short post-drive grace period
        would silently under-cover it and misreport it as unreachable).

        v1.8.0e 3a-C4 (spec §35.9 C-4): the window is now a PARAMETER.
        0x7A FDOT32_CR runs 600-900 cycles measured (hard ceiling 10,000),
        so the fixed 400 would have reported the newest classified opcode
        as classified-but-unreachable -- i.e. a real FAIL for the wrong
        reason, which is exactly how a coverage window turns into a lie."""
        seen = False

        async def _watch():
            nonlocal seen
            for _ in range(cycles):
                await RisingEdge(dut.clk)
                if int(dut.mu_out_valid.value):
                    seen = True
        watcher = cocotb.start_soon(_watch())
        await drive_coro(dut)
        await watcher
        return seen

    # ---- (a) positive: every classified opcode reaches mu_out_valid ------
    async def _drive_mul(dut):
        await _reset(dut)
        dut.ext_instruction.value = _mul_instr(0x01, 0, 2)
        dut.ext_tag.value = _tag(port_context_id=0)
        dut.ext_payload.value = 5
        dut.ext_payload_b_valid.value = 0
        dut.ext_valid.value = 1
        await RisingEdge(dut.clk)
        dut.ext_valid.value = 0

    async def _drive_fp(op):
        async def _inner(dut):
            await _reset(dut)
            instr = encode_instr(op, eh_port(input_port_mask=0x01, output_port_id=0),
                                 _ehp(0x14, 0), flags=(1 << 2))
            dut.ext_instruction.value = instr
            dut.ext_tag.value = _tag(port_context_id=0)
            dut.ext_payload.value = _f2b(2.0)
            dut.ext_payload_b.value = _f2b(3.0)
            dut.ext_payload_b_valid.value = 1
            dut.ext_valid.value = 1
            await RisingEdge(dut.clk)
            dut.ext_valid.value = 0
        return _inner

    checks = {0x12: _drive_mul}
    # per-opcode watcher window; anything absent uses the 400 default.
    windows = {}
    for op in (0x74, 0x75, 0x76, 0x77):
        if op in classified:
            checks[op] = await _drive_fp(op)
    if 0x6B in classified:
        # 0x6B carries gamma via IMM64 not a wide fragment payload -- use
        # the same direct single-beat construction the e2e test uses.
        async def _drive_gamma(dut):
            await _reset(dut)
            x_lanes = [((i * 7) + 3) & 0xF for i in range(16)]
            g_lanes = [((-i) & 0xF) for i in range(16)]
            a_frag = sum(v << (4 * i) for i, v in enumerate(x_lanes))
            g_imm = sum(v << (4 * i) for i, v in enumerate(g_lanes))
            instr = encode_instr(0x6B, eh_port(input_port_mask=0x01, output_port_id=0),
                                 _ehp(0x10, 0), eh_imm64_local(g_imm),
                                 flags=(1 << 2))
            dut.ext_instruction.value = instr
            dut.ext_tag.value = _tag(port_context_id=0)
            dut.ext_payload.value = a_frag
            dut.ext_payload_b_valid.value = 0
            dut.ext_valid.value = 1
            await RisingEdge(dut.clk)
            dut.ext_valid.value = 0
        checks[0x6B] = _drive_gamma
    if 0x79 in classified:
        # 0x79 FMINMAX needs the F_HAS_OPB B-channel (broadcast operand) on
        # the wave-completing beat.
        async def _drive_fminmax(dut):
            await _reset(dut)
            lanes = [0x80000000, 0x00000000, 0x00000001, 0x7FC00000]
            a_frags = _G.lanes_to_frags(lanes, 32)
            instr = encode_instr(0x79, eh_port(input_port_mask=0x01, output_port_id=0),
                                 _ehp(0x14, 0), flags=(1 << 3) | (1 << 2))
            await _fire_frag_wave(dut, instr, _tag(port_context_id=0), a_frags,
                                  payload_b=0x00000001, b_valid_last=1)
        checks[0x79] = _drive_fminmax
    if 0x78 in classified:
        # 0x78 DEQUANT needs the fp32 scale on the completing beat via the
        # same B-channel contract.
        async def _drive_dequant(dut):
            await _reset(dut)
            lanes8 = [((i * 29) ^ 0xA5) & 0xFF for i in range(16)]
            a_frags = _G.lanes_to_frags(lanes8, 8)
            instr = encode_instr(0x78, eh_port(input_port_mask=0x01, output_port_id=0),
                                 _ehp(0x11, 0), flags=(1 << 2))
            await _fire_frag_wave(dut, instr, _tag(port_context_id=0), a_frags,
                                  payload_b=_f2b(1.25), b_valid_last=1)
        checks[0x78] = _drive_dequant
    if 0x70 in classified:
        async def _drive_vfma(dut):
            await _reset(dut)
            from test_isa_decoder import eh_imm64 as _ehi64
            lanes4 = [((i * 11) + 3) & 0xF for i in range(32)]
            a_frags = _G.lanes_to_frags(lanes4, 4)
            b64 = ((0x7FFFFFF0 & 0xFFFFFFFF) << 32) | 0xE
            instr = encode_instr(0x70, eh_port(input_port_mask=0x01, output_port_id=0),
                                 _ehp(0x10, 0), _ehi64(b64), flags=(1 << 2))
            await _fire_frag_wave(dut, instr, _tag(port_context_id=0), a_frags)
        checks[0x70] = _drive_vfma
    if 0x7A in classified:
        # v1.8.0e 3a-C4 — 0x7A FDOT32_CR: a full 16-fragment 1,024b A||B
        # wave (the operand IS the wave; there is no payload_b). Without
        # this entry the `checks` dict silently skips the newest
        # classified opcode: nothing in this test asserts
        # `set(checks) >= classified`, so adding 0x7A to is_mul_op would
        # have left the test green while never poking 0x7A once.
        async def _drive_fdotcr(dut):
            await _reset(dut)
            wide = 0
            for i in range(32):
                wide |= 0x3F80 << (16 * i)          # A = bf16 1.0
                wide |= 0x4000 << (512 + 16 * i)    # B = bf16 2.0
            frags = [(wide >> (64 * i)) & ((1 << 64) - 1) for i in range(16)]
            instr = encode_instr(0x7A,
                                 eh_port(input_port_mask=0x01, output_port_id=0),
                                 _ehp(0x13, 0), flags=(1 << 2))
            await _fire_frag_wave(dut, instr, _tag(port_context_id=0), frags)
        checks[0x7A] = _drive_fdotcr
        windows[0x7A] = 1600
    if 0x32 in classified:
        # 0x32 EINSUM: is_mul_op routes it on the RAW opcode alone (before
        # any EH/subscript decode), so even a narrow, non-wide signature
        # (SIG_MATMUL_2X2 here) is unconditionally sent to the MU-hosted
        # PE and consumes MU-table capacity -- worth confirming directly
        # rather than assuming only the wide sub-tree forms do.
        async def _drive_matmul2x2(dut):
            await _reset(dut)
            instr = encode_instr(0x32, eh_port(input_port_mask=0x01, output_port_id=0),
                                 eh_subscript(axes(1, 2, 0, 0), axes(2, 3, 0, 0),
                                              axes(1, 3, 0, 0)),
                                 eh_opref(), flags=(1 << 3))
            dut.ext_instruction.value = instr
            dut.ext_tag.value = _tag(port_context_id=0, dim=0x11)
            dut.ext_payload.value = 0x0001000200030004
            dut.ext_payload_b.value = 0x0005000600070008
            dut.ext_payload_b_valid.value = 1
            dut.ext_valid.value = 1
            await RisingEdge(dut.clk)
            dut.ext_valid.value = 0
        checks[0x32] = _drive_matmul2x2

    # v1.8.0e 3a-C4 (spec §35.9 C-4) — THE MISSING INVARIANT. Until this
    # commit nothing required `checks` to cover the classified set, so a
    # newly classified opcode could sit unexercised behind a green test:
    # adding it to is_mul_op changed nothing here and the coverage claim in
    # this docstring quietly became false for it. That is exactly how 0x7A
    # would have slipped through.
    #
    # Turning the invariant on EXPOSED a pre-existing gap (it did not
    # create one): five classified opcodes have never had a driver here.
    # They are listed BY NAME rather than waved away, so the hole is
    # visible in the source instead of implicit in an absent assertion.
    # Closing them is recorded carry-over, out of 3a-C4's scope.
    #
    #   0x30 MATMUL   — needs a 2x2 subscript + wide operand setup
    #   0x43          — reduction family, needs its own EH shape
    #   0x71 VDOT_ACC / 0x72 ACC_REDUCE — MU-bank reachability IS proven,
    #                   just by a different test in this file
    #                   (test_vdot_acc_reduce_rides_mu_bank)
    #   0x73 ACC_ELEMWISE — needs the OPREF-only form (the imm form takes
    #                   the §23.10.10(c) lower_required rung and never
    #                   reaches mu_out_valid)
    _KNOWN_UNDRIVEN = {0x30, 0x43, 0x71, 0x72, 0x73}
    missing = sorted(classified - set(checks) - _KNOWN_UNDRIVEN)
    assert not missing, (
        f"classified opcodes with no driver in `checks`: "
        f"{[hex(x) for x in missing]} — this test would have stayed GREEN "
        f"while never dispatching them once. Add a driver, or add the "
        f"opcode to _KNOWN_UNDRIVEN with the reason spelled out.")
    stale = sorted(_KNOWN_UNDRIVEN - classified)
    assert not stale, (
        f"_KNOWN_UNDRIVEN lists opcodes that are no longer classified: "
        f"{[hex(x) for x in stale]} — an allowlist that outlives its "
        f"subject starts hiding the next gap")
    both = sorted(_KNOWN_UNDRIVEN & set(checks))
    assert not both, (
        f"{[hex(x) for x in both]} are both allow-listed AND driven — "
        f"drop them from _KNOWN_UNDRIVEN so the list keeps meaning "
        f"'not covered here'")

    for op, drive in checks.items():
        seen = await _saw_mu(dut, drive, cycles=windows.get(op, 400))
        assert seen, \
            f"classified opcode 0x{op:02X} never asserted mu_out_valid " \
            f"-- classified-but-unreachable, a dead-capacity gap in the " \
            f"MU bank table"

    # ---- (b) negative: representative non-classified opcodes never do ----
    async def _drive_add(dut):
        await _reset(dut)
        instr = encode_instr(0x10, eh_port(input_port_mask=0x01, output_port_id=0),
                             eh_imm16(5))
        dut.ext_instruction.value = instr
        dut.ext_tag.value = _tag(port_context_id=0)
        dut.ext_payload.value = 7
        dut.ext_payload_b_valid.value = 0
        dut.ext_valid.value = 1
        await RisingEdge(dut.clk)
        dut.ext_valid.value = 0

    async def _drive_7c(dut):
        # 0x7C: pinned OUT of is_mul_op by test_twin_classifier_lockstep_static
        # (L-PE for ALL dtypes, no dtype-conditionality clause). Fire it
        # with a generous encoding; a decode-error/lower_required outcome
        # is fine -- only mu_out_valid reachability is under test here.
        await _reset(dut)
        instr = encode_instr(0x7C, eh_port(input_port_mask=0x01, output_port_id=0),
                             _ehp(0x14, 0), flags=(1 << 2))
        dut.ext_instruction.value = instr
        dut.ext_tag.value = _tag(port_context_id=0)
        dut.ext_payload.value = _f2b(1.0)
        dut.ext_payload_b.value = _f2b(1.0)
        dut.ext_payload_b_valid.value = 1
        dut.ext_valid.value = 1
        await RisingEdge(dut.clk)
        dut.ext_valid.value = 0

    async def _drive_simd_wide_0x69(dut):
        # 0x69 SIMD_MUL_WIDE (Q8.8): representative of the wide-SIMD
        # 0x60-0x69 family, NOT in is_mul_op -- always L-PE hosted.
        await _reset(dut)
        instr = encode_instr(0x69, eh_port(input_port_mask=0x01, output_port_id=0),
                             eh_imm16(0x0080))
        wide = _v180b_pack_int4(*([0x2] * 32))
        payloads = [(wide >> (64 * i)) & ((1 << 64) - 1) for i in range(2)]
        await _fire_frag_wave(dut, instr, _tag(port_context_id=0), payloads)

    negative_checks = {0x10: _drive_add, 0x69: _drive_simd_wide_0x69}
    if 0x7C not in classified:
        negative_checks[0x7C] = _drive_7c
    for op, drive in negative_checks.items():
        seen = await _saw_mu(dut, drive)
        assert not seen, \
            f"UNCLASSIFIED opcode 0x{op:02X} asserted mu_out_valid -- " \
            f"a real silent MU-table under-fill gap"


# =============================================================================
# v1.9.1 §31.14 — NoC bank (OPREF.src_kind=1) 저장소 의미론 pin.
#
# 무엇이 뒤집혔는가
# -----------------
# §31.13.3 은 D6/D11 착지본과 v1.9 기준본의 `output_payload` 차이를 "자격자가
# 양쪽 0 인 masked 사이클(SOFT)" 로 분류했다. **이 소비자에게는 masked 가
# 아니다.** `Cluster.v` 의 bank mux 는 L-PE 슬롯을 위해 전용 뱅크 레지스터를
# 두지 않고 `PE_Core.output_payload` 를 **저장소로 재사용**하며 `pe_out_valid`
# 게이트 없이 조합적으로 읽는다 (MU/DU 는 valid-게이트 레지스터를 따로 둔다).
# 따라서 토큰을 내지 않는 명령이 그 레지스터를 움직이면 다음 소비자의 B
# 피연산자가 바뀐다.
#
# 기존 `test_cluster_noc_routing_*` 3종은 **생산자 직후 1 사이클만** 보므로
# 두 형태 모두 통과한다 — 즉 뱅크의 "유지(hold)" 의미론을 pin 한 테스트가
# 0건이었다. 아래 두 케이스가 그 공백을 메운다. 둘 다 v1.9 기준
# `PE_Core.v` 로 되돌리면 FAIL 한다 (검출력 실증: spec §31.14.2).
#
# 미검사 자극 축 (§28.4 항 8(c)): MU/DU 가 같은 슬롯을 덮은 뒤의 우선순위
# (그건 `last_was_mu/du` 가 규정하고 별도 테스트군이 있다), 다중 fragment
# wave 의 뱅크 의미론이 ISA 로 규정되지 않았다는 사실 자체 (§31.14.5 이월).
# =============================================================================

async def _fire_collect(dut, instr, tag, payload_a=0, payload_b=0,
                        payload_b_valid=0, cycles=16):
    """고정 사이클 수만큼 굴리며 토큰 beat 를 모은다.

    조기 종료(`_fire` 의 break)는 뒤따르는 fragment beat 를 놓치므로 여기서는
    쓰지 않는다 — 이 테스트가 보는 것이 바로 "마지막 beat" 다.
    """
    dut.ext_instruction.value = instr
    dut.ext_tag.value = tag
    dut.ext_payload.value = payload_a
    dut.ext_payload_b.value = payload_b
    dut.ext_payload_b_valid.value = payload_b_valid
    dut.ext_frag_hdr.value = 0
    dut.ext_valid.value = 1
    await RisingEdge(dut.clk)
    dut.ext_valid.value = 0
    dut.ext_payload_b_valid.value = 0
    beats = []
    for _ in range(cycles):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.ext_out_valid.value) == 1:
            beats.append((int(dut.ext_out_payload.value),
                          int(dut.ext_out_frag_hdr.value)))
    return beats


@cocotb.test()
async def test_cluster_store_token_payload_deterministic_and_bank(dut):
    """§31.13.4 D11′ — ST(0x05) 토큰 payload 는 **결정적 0** 이다.

    `0x05` arm 은 `cr_memory_req <= 1` + `cr_valid_out <= 1` 을 세우면서
    `cr_payload` 를 기입하지 않는다. stage-2 가 payload 를 무조건 복사하던
    v1.9 기준 RTL 에서는 **직전 명령의 payload 가 `output_valid=1` 인 토큰에
    실려** 클러스터 경계로 나갔다 — 자격자를 통과해 새는 클래스라 X 탐지로는
    보이지 않았다 (§31.13.4 가 §31.4 를 정정한 지점).

    §31.13.4 는 이 값을 "직전 명령의 값 → 결정적 0" 으로 바꾼다고 **관측 가능한
    동작 변경**으로 선언했으나 그것을 pin 하는 테스트가 0건이었다. 여기서
    두 결과를 동시에 본다:

      (a) ST 토큰의 payload 가 0 이다.
      (b) 그 뒤 bank[0] 도 0 이다 — ST 는 토큰을 내므로 불변식 H1 하에서
          뱅크를 **정당하게** 갱신한다 (§31.14 H1 은 "토큰 없는 명령" 만
          막는다). 뱅크 계약이 "마지막으로 발행한 토큰의 payload" 임을 이
          방향에서도 확인한다.

    **정직 명기:** ST 토큰 payload 의 의미론은 ISA 미규정이다 (§31.13.8 항 2).
    이 테스트는 0 이 옳다고 주장하지 않고 **현행 결정을 pin** 한다 — ISA 가
    다른 값을 규정하면 이 테스트가 그 결정을 강제로 다시 열게 된다.
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    # 1) PE0 생산자 — ADD .imm16 5, payload_a=10 → 토큰 payload 15
    instr_p = encode_instr(0x10,
                           eh_port(input_port_mask=0x01, output_port_id=0),
                           eh_imm16(5))
    beats_p = await _fire_collect(dut, instr_p, _tag(0), payload_a=10)
    assert beats_p and beats_p[-1][0] == 15, (
        f"생산자 토큰이 15 가 아니다: {beats_p}"
    )

    # 2) 같은 PE0 에 ST(0x05) — 토큰 + memory_req 를 함께 낸다
    instr_s = encode_instr(0x05,
                           eh_port(input_port_mask=0x01, output_port_id=0),
                           eh_mem(offset=0x40))
    beats_s = await _fire_collect(dut, instr_s, _tag(0),
                                  payload_a=0x0000_0000_0000_0200, cycles=10)
    assert beats_s, "ST(0x05) 가 토큰을 내지 않았다 — 케이스 전제가 깨졌다"
    st_payload = beats_s[0][0]
    assert st_payload == 0, (
        f"§31.13.4 D11′ 회귀 — ST 토큰 payload 가 {st_payload:#x} 다. "
        "결정적 0 이어야 한다. 0 이 아니면 직전 명령의 payload 가 자격자를 "
        "통과해 새고 있다는 뜻이다 (15 가 나오면 정확히 그 회귀다)."
    )

    # 3) PE1 이 bank[0] 을 읽는다 — ST 가 낸 토큰이 마지막이므로 0 이어야 한다
    instr_c = encode_instr(0x10,
                           eh_port(input_port_mask=0x02, output_port_id=1),
                           eh_opref(src_kind=1, noc_route=0),
                           flags=F_HAS_OPB)
    beats_c = await _fire_collect(dut, instr_c, _tag(1), payload_a=7,
                                  cycles=12)
    assert beats_c, "소비자가 토큰을 내지 않았다"
    observed = beats_c[0][0]
    assert observed == 7, (
        f"§31.14 NoC bank — 소비자 결과가 {observed} 다. bank[0] 은 마지막 "
        "발행 토큰(ST, payload 0)이어야 하므로 7 + 0 = 7 이 기대값이다. "
        f"22 가 나오면 뱅크에 ADD 의 15 가 남아 있다는 뜻이다."
    )


@cocotb.test()
async def test_cluster_noc_bank_multifragment_last_beat(dut):
    """다중 fragment wave 뒤의 bank[k] 는 **마지막 beat** 의 payload 다.

    PE0 에 2-fragment 입력 wave 로 0x63 (SIMD_ADD_WIDE_VEC) 을 태우면 2 beat
    가 나온다. 그 뒤 토큰 없는 LD(0x04) 를 같은 PE 에 태우고 PE1 이 bank[0]
    을 읽는다 — 읽히는 값은 **두 번째(마지막) beat** 여야 한다.

    이것이 적대 검증이 잡은 바로 그 수열이다 (spec §31.14.2): v1.9 기준
    RTL 은 LD 의 stage-2 가 `cr_payload`(= fragment 0 값)로 되돌려 놓아
    소비자가 읽는 값이 마지막 beat 가 아니라 **첫 beat** 로 바뀐다.

    **정직 명기:** 뱅크 슬롯은 64-bit 이고 wave 는 다중 fragment 일 수 있다.
    "마지막 fragment" 가 정답인지는 ISA 가 규정한 바 없다 (§31.14.5 이월).
    이 테스트는 **현행 의미론을 pin** 할 뿐 그것이 옳다고 주장하지 않는다.
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    A = 0x1111_2222_3333_4444
    B = 0x5555_6666_7777_8888
    tot_m1 = 1

    instr_p = encode_instr(0x63,
                           eh_port(input_port_mask=0x01, output_port_id=0),
                           eh_opref(), flags=F_HAS_OPB)
    for idx, pl in enumerate((A, B)):
        last = (idx == tot_m1)
        dut.ext_instruction.value = instr_p
        dut.ext_tag.value = _tag(0)
        dut.ext_payload.value = pl
        dut.ext_payload_b.value = 0x2222_2222_2222_2222 if last else 0
        dut.ext_payload_b_valid.value = 1 if last else 0
        dut.ext_frag_hdr.value = (idx << 4) | tot_m1
        dut.ext_valid.value = 1
        await RisingEdge(dut.clk)
    dut.ext_valid.value = 0
    dut.ext_frag_hdr.value = 0
    dut.ext_payload_b_valid.value = 0

    beats = []
    for _ in range(14):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.ext_out_valid.value) == 1:
            beats.append((int(dut.ext_out_payload.value),
                          int(dut.ext_out_frag_hdr.value)))
    assert len(beats) == 2, f"2-fragment wave 가 2 beat 를 내지 않았다: {beats}"
    last_beat = beats[-1][0]

    # 토큰 없는 LD 를 같은 PE 에 태운다 — 뱅크는 움직여선 안 된다.
    instr_n = encode_instr(0x04,
                           eh_port(input_port_mask=0x01, output_port_id=0),
                           eh_mem(offset=0x100))
    beats_n = await _fire_collect(dut, instr_n, _tag(0), cycles=8)
    assert not beats_n, f"LD(0x04) 가 토큰을 냈다: {beats_n}"

    instr_c = encode_instr(0x10,
                           eh_port(input_port_mask=0x02, output_port_id=1),
                           eh_opref(src_kind=1, noc_route=0),
                           flags=F_HAS_OPB)
    beats_c = await _fire_collect(dut, instr_c, _tag(1), payload_a=0,
                                  cycles=12)
    assert beats_c, "소비자가 토큰을 내지 않았다"
    observed = beats_c[0][0]
    assert observed == last_beat, (
        f"§31.14 NoC bank 계약 위반 — bank[0] 이 {observed:#016x}, 기대값은 "
        f"마지막 beat {last_beat:#016x} (beats={[hex(b[0]) for b in beats]}). "
        "첫 beat 값이 돌아왔다면 토큰 없는 LD 의 stage-2 가 뱅크를 되돌린 "
        "것이다 — 불변식 H1 위반."
    )


# =============================================================================
# v1.9.2 §22.14b-3 — 적대 감사(2026-08-18)가 생존시킨 변이 2종을 닫는다.
#
# 두 변이 모두 **RTL 은 옳은데 그 옳음을 붙잡는 테스트가 0건**이었다. 이
# 세션이 반복해서 청산한 바로 그 형태(조용히 통과하는 검사)이므로, 규범이
# 확정한 경계마다 회귀 pin 을 둔다.
#
#   m7  `skid_overflow_now = wave_complete && skid_valid`
#       → `... && !ehdec_in_ready` 로 약화해도 전건 통과했다.
#       차이는 **투입 에지**(`skid_valid && ehdec_in_ready`)에서만 난다:
#       그 에지에 도착한 파동은 `skid_load`(!skid_valid 요구)에도
#       `wave_accept`(보류분을 투입 중)에도 걸리지 않아 **양쪽 모두 드롭**
#       된다. 무변이는 fault=1(loud drop), m7 은 fault=0(무언 소실).
#       spec §22.14b-6(2) 가 "`skid_valid` 가 서 있는 사이클의 도착은 투입이
#       같은 사이클에 일어나는지와 **무관하게** overflow fault" 로 확정한
#       경계다.
#
#   m12 `in_pcid = ehdec_tag[31:16]` → `ext_tag[31:16]` 로 되돌려도 전건
#       통과했다. 보류분이 **미끼 태그의 PE 로 디스패치**되는데(무변이
#       `pe_active_lpe_s1=0b10` vs m12 `0b1000`), 기존 라우팅 assert 는
#       `ext_out_tag`(= PE 출력 tag, EHDecode 래치 경로)를 읽어 `target_idx`
#       (`in_pcid` 의 유일 소비자)와 **다른 경로**를 본다. 그래서 tag 를
#       통째로 되돌리는 변이는 죽지만 라우팅 소비자만 되돌리는 변이는 산다.
# =============================================================================


@cocotb.test()
async def test_skid_overflow_fires_on_the_inject_edge(dut):
    """§22.14b-6(2) — **투입 에지** 도착도 overflow fault 를 낸다.

    `skid_valid` 가 서 있는 사이클의 도착은 그 사이클에 보류분 투입이
    함께 일어나든 아니든 담을 자리가 없다. 그 파동은 버려지고, 버려지는
    이상 **소리가 나야 한다** — 조건에 `!ehdec_in_ready` 를 얹으면 정확히
    이 한 에지에서만 조용해진다.
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    instr_a = _coll_add_instr(0)
    instr_b = _coll_add_instr(1)
    instr_c = _coll_add_instr(2)
    exp_a = _SKID_A_PAY + _ADD_IMM
    exp_b = _SKID_B_PAY + _ADD_IMM
    exp_c = _SKID_C_PAY + _ADD_IMM

    await _reset(dut)

    # 선행 파동 → EHDecode blackout 시작.
    await _skid_pulse(dut, instr_a, _tag(port_context_id=0), _SKID_A_PAY)
    # blackout 안에서 한 건 보류.
    await _skid_pulse(dut, instr_b, _tag(port_context_id=1), _SKID_B_PAY)
    await Timer(1, units="ns")
    assert int(dut.skid_valid.value) == 1, \
        "전제 불성립 — 두 번째 파동이 보류되지 않았다"
    assert int(dut.input_skid_overflow_error.value) == 0, \
        "보류 1건만으로 fault 가 떴다"

    # 투입 에지를 **찾아서** 그 에지에 세 번째를 인가한다. 에지 번호를
    # 하드코딩하지 않는 이유: MAX_EH 가 바뀌면 위치가 움직이는데, 그때
    # 테스트가 조용히 다른 에지를 때리면 이 pin 이 무력해진다.
    inject_edge_seen = False
    outs = []
    for _ in range(60):
        drain_now = (int(dut.skid_valid.value) == 1
                     and int(dut.ehdec_in_ready.value) == 1)
        if drain_now and not inject_edge_seen:
            inject_edge_seen = True
            dut.ext_instruction.value = instr_c
            dut.ext_tag.value = _tag(port_context_id=2)
            dut.ext_payload.value = _SKID_C_PAY
            dut.ext_payload_b.value = 0
            dut.ext_payload_b_valid.value = 0
            dut.ext_frag_hdr.value = 0
            dut.ext_valid.value = 1
        await RisingEdge(dut.clk)
        _skid_decoy(dut)
        await Timer(1, units="ns")
        if int(dut.ext_out_valid.value) == 1:
            outs.append(int(dut.ext_out_payload.value))

    assert inject_edge_seen, (
        "투입 에지(`skid_valid && ehdec_in_ready`)를 한 번도 관측하지 "
        "못했다 — 자극이 이 경계를 밟지 못했으므로 이 테스트는 아무것도 "
        "검사하지 않았다")
    assert int(dut.input_skid_overflow_error.value) == 1, (
        "투입 에지에 도착한 파동이 **조용히** 사라졌다 — "
        "loud-fault-never-silent 위반이자 §22.14b-6(2) 위반")
    assert int(dut.any_error_flag.value) == 1, \
        "overflow fault 가 any_error_flag 로 폴딩되지 않았다"
    assert exp_c not in outs, (
        f"fault 를 냈는데 그 파동이 실제로는 실행됐다 — 거짓 경보 "
        f"(관측 {outs})")
    # 버려지는 쪽만 버린다 — 선행/보류분은 온전해야 한다.
    assert outs.count(exp_a) == 1, f"선행 파동 소실 (관측 {outs})"
    assert outs.count(exp_b) == 1, f"보류 파동 소실 (관측 {outs})"


@cocotb.test()
async def test_skid_inject_routes_by_held_tag_not_live_bus(dut):
    """§22.14b-7(A) — 보류분은 **자기 태그**의 PE 로 라우팅된다.

    `target_idx` 는 `in_pcid` 하나만 소비하고, `in_pcid` 는 투입 시점의
    live `ext_tag` 가 아니라 보류된 `ehdec_tag` 에서 와야 한다. 이 경계는
    출력 태그로 관측되지 **않는다** — `ext_out_tag` 는 PE 출력 tag 라
    라우팅과 다른 경로다. 그래서 여기서는 디스패치 원핫
    (`pe_active_lpe_s1`)을 직접 본다.
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    n_pes = len(dut.pe_active_lpe_s1.value)
    held_pcid = _SKID_B_PCID % n_pes
    decoy_pcid = _SKID_DECOY_PCID % n_pes
    assert held_pcid != decoy_pcid, (
        f"자극이 두 PE 를 구분하지 못한다 (held={held_pcid} "
        f"decoy={decoy_pcid}, NUM_PES={n_pes}) — 이 지오메트리에서는 "
        f"이 테스트가 아무것도 판별하지 못하므로 자극을 고쳐야 한다")

    instr_a = _coll_add_instr(0)
    instr_b = _coll_add_instr(1)

    await _reset(dut)
    await _skid_pulse(dut, instr_a, _tag(port_context_id=0), _SKID_A_PAY)
    # 보류분: held_pcid 를 겨냥. 주입 직후 버스는 decoy_pcid 로 덮인다
    # (`_skid_pulse` 가 `_skid_decoy` 를 호출).
    await _skid_pulse(dut, instr_b, _tag(port_context_id=held_pcid),
                      _SKID_B_PAY)
    await Timer(1, units="ns")
    assert int(dut.skid_valid.value) == 1, \
        "전제 불성립 — 보류가 일어나지 않았다"

    # 투입이 실제로 디스패치로 이어지는 에지에서 원핫을 포착한다.
    seen = None
    for _ in range(40):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        act = int(dut.pe_active_lpe_s1.value)
        if act != 0:
            seen = act
            break

    assert seen is not None, \
        "보류분이 어느 PE 로도 디스패치되지 않았다"
    assert seen == (1 << held_pcid), (
        f"보류 파동이 **미끼 태그**의 PE 로 라우팅됐다 — 기대 "
        f"0b{1 << held_pcid:0{n_pes}b} (pcid {held_pcid}), 관측 "
        f"0b{seen:0{n_pes}b}. `in_pcid` 가 보류된 `ehdec_tag` 가 아니라 "
        f"투입 시점의 live `ext_tag` 를 읽고 있다")


# =============================================================================
# v1.8.0e 3a-C4 §27.7a.3 / §35.3 — FDOT32_CR sticky status, TWO SIGNALS THAT
# MUST STAY SEPARATE.
#
#   fdotcr_special_status   = NORMAL DATA EVENT. A NaN/Inf/sNaN operand lane
#                             was received, so the unit returned canonical
#                             qNaN instead of entering the EFT (§27.7a.1
#                             (iii)). The SDK audit program feeds such
#                             operands ON PURPOSE and compares sticky
#                             presence across the two datapaths — that is
#                             §27.7a.3 check (i). It must NEVER reach
#                             any_error_flag.
#   fdotcr_unit_fault_error = RTL DEFECT. One of the four §27.7a.2b
#                             amendment-11 invariants collapsed. THIS one is
#                             folded into any_error_flag, and promoted here
#                             to §26.5 grade (reset-clearable only) because
#                             FP_StepSeq is a reset-free block and can only
#                             hold a per-op latch.
#
# The negative half (special NOT in any_error_flag) is the load-bearing one:
# a purely positive test suite would stay green if someone "simplified" the
# two ports into one, and the loss would be irreversible — Cluster's error
# fold is a pure OR-reduce.
# =============================================================================

def _fdotcr_wave_frags(a_lanes, b_lanes):
    wide = 0
    for i in range(32):
        wide |= (a_lanes[i] & 0xFFFF) << (16 * i)
        wide |= (b_lanes[i] & 0xFFFF) << (512 + 16 * i)
    assert wide.bit_length() <= 1024
    return [(wide >> (64 * i)) & ((1 << 64) - 1) for i in range(16)]


async def _fdotcr_dispatch(dut, a_lanes, b_lanes, mode=0x13, limit=4000):
    """Fire one FDOT32_CR through the Cluster and return
    (payload, err, lwr, special, fault)."""
    from test_isa_decoder import eh_precision as _ehp
    instr = encode_instr(0x7A,
                         eh_port(input_port_mask=0x01, output_port_id=0),
                         _ehp(mode, 0), flags=(1 << 2))
    await _fire_frag_wave(dut, instr, _tag(port_context_id=0),
                          _fdotcr_wave_frags(a_lanes, b_lanes))
    payload, err, lwr = None, 0, 0
    for _ in range(limit):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        err |= int(dut.any_error_flag.value)
        lwr |= int(dut.any_lower_required.value)
        if int(dut.ext_out_valid.value):
            payload = int(dut.ext_out_payload.value)
            break
        if err or lwr:
            break
    return (payload, err, lwr,
            int(dut.fdotcr_special_status.value),
            int(dut.fdotcr_unit_fault_error.value))


@cocotb.test()
async def test_fdotcr_special_status_is_data_not_error(dut):
    """§27.7a.3 check (i) — the special sticky is observable at the Cluster
    boundary AND is not an error.

    Quoting §27.7a.3 verbatim: "audit 프로그램 (SDK) 이 동일 operand 로 양
    경로를 발사하고 (결과, sticky/status) 쌍을 회수해 검사한다: (i)
    special-sticky 유무 불일치 → 결함". So running the audit REQUIRES
    feeding special operands and reading the sticky back. If the sticky were
    folded into any_error_flag, (a) performing the audit would raise a
    cluster-wide error every single run, and (b) the fold is a pure
    OR-reduce, so "a special operand was seen" and "the RTL broke" would be
    indistinguishable forever after.

    Three points, and the NEGATIVE ones matter most:
      clean wave  -> status 0, error 0, exact value
      NaN lane    -> status 1, error 0 (!), canonical qNaN
      after reset -> status back to 0 (it is per-op, not sticky-to-reset)
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    clean_a = [0x3F80] * 32          # bf16 1.0
    clean_b = [0x4000] * 32          # bf16 2.0
    pay, err, lwr, spec, flt = await _fdotcr_dispatch(dut, clean_a, clean_b)
    assert (err, lwr) == (0, 0), f"clean FDOT32_CR raised err={err} lwr={lwr}"
    assert pay == 0x42800000, \
        f"clean bf16 32x(1.0*2.0) = 64.0 expected, got {pay!r}"
    assert spec == 0, "clean wave set the special status"
    assert flt == 0, "clean wave set the unit fault"

    await _reset(dut)
    assert int(dut.fdotcr_special_status.value) == 0, \
        "special status is high straight out of reset"

    nan_a = [0x7FC0] + [0x3F80] * 31   # bf16 qNaN in lane 0
    pay, err, lwr, spec, flt = await _fdotcr_dispatch(dut, nan_a, clean_b)
    assert pay == 0x7FC00000, (
        f"§27.7a.1 (iii): a NaN operand must yield canonical qNaN, "
        f"got {pay!r}")
    assert spec == 1, \
        "the special sticky did not reach the Cluster boundary"
    assert flt == 0, \
        "a special OPERAND is not an RTL fault — fd_fault must stay low"
    assert err == 0, (
        "REGRESSION OF THE WHOLE DESIGN: fdotcr_special_status reached "
        "any_error_flag. §27.7a.3 check (i) becomes impossible to run — "
        "the audit's own stimulus would raise a cluster error, and the "
        "OR-reduce makes 'special seen' and 'RTL broke' indistinguishable")
    assert lwr == 0, "a special-operand FDOT32_CR must still complete"

    # per-op, not sticky: a clean wave after a special one clears it.
    await _reset(dut)
    pay, err, lwr, spec, flt = await _fdotcr_dispatch(dut, clean_a, clean_b)
    assert spec == 0, (
        "the special status stayed high across a subsequent clean op — it "
        "is a PER-OP latch (§27.7a.3 recovers (result, sticky) pairs per "
        "op); promoting it to reset-clearable would lose the attribution")


@cocotb.test()
async def test_fdotcr_special_status_never_folded_static(dut):
    """Static twin of the test above: `fdotcr_special_status` /
    `m_fd_spec` must not appear in Cluster.v's `m_err` OR-reduce.

    The runtime test can only prove the fold is absent for the stimuli it
    happens to drive. This one reads the RTL text and proves it structurally,
    which is what makes a future "simplification" loud instead of subtle."""
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, 'Cluster.v')) as f:
        text = f.read()
    fold_lines = [ln for ln in text.splitlines()
                  if 'm_err' in ln and '=' in ln and not ln.strip().startswith('//')]
    assert fold_lines, "failed to locate the m_err OR-reduce in Cluster.v"
    offenders = [ln.strip() for ln in fold_lines
                 if 'm_fd_spec' in ln or 'fdotcr_special_status' in ln]
    assert not offenders, (
        "the FDOT32_CR special status was folded into any_error_flag "
        f"(§35.3 pin 1 forbids this): {offenders}")
    assert any('fdotcr_unit_fault_r' in ln for ln in fold_lines), (
        "the FDOT32_CR unit fault is NOT folded into any_error_flag — "
        "§35.3 pin 1 requires exactly this one of the two")


@cocotb.test()
async def test_fdotcr_unit_fault_promoted_and_folded(dut):
    """§35.3 pin 2 / §26.5 — the unit fault's promotion to a
    reset-clearable sticky, proved by directed poke.

    The four `fd_fault` set sites are UNREACHABLE by legal input — that is
    the entire point of an RTL-invariant assert. They are exercised at the
    unit axis by the 3a-C3 TB (synth/lattice/fp_ops/tb_fp_stepseq.py
    fdotcr_loud_fault_paths, which asserts the STATE each fault was raised
    from). What the Cluster axis owes is different and cannot be shown
    there: that the fault (a) reaches this boundary at all, (b) is folded
    into any_error_flag, and (c) SURVIVES the unit latch clearing.

    (c) is the load-bearing one. FP_StepSeq has no reset port, so its
    fd_fault is a per-op latch that the next launch overwrites. If this
    Cluster promotion register did not exist, the port would be a "sticky"
    in name only: a pulse that the next FDOT32_CR silently erases."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)
    assert int(dut.fdotcr_unit_fault_error.value) == 0
    assert int(dut.any_error_flag.value) == 0

    unit_fault = dut.u_matmul_unit.g_v180c_fp.u_fp_stepseq.fd_fault
    unit_fault.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.fdotcr_unit_fault_error.value) == 1, \
        "the unit fault did not reach the Cluster's dedicated port"
    assert int(dut.any_error_flag.value) == 1, \
        "the unit fault was not folded into any_error_flag (§35.3 pin 1)"

    # (c) the unit latch clears (as a fresh launch would clear it) —
    # the promoted sticky must NOT follow it down.
    unit_fault.value = 0
    for _ in range(8):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        assert int(dut.fdotcr_unit_fault_error.value) == 1, (
            "the promoted sticky followed the unit's per-op latch down — "
            "that is a pulse wearing the name 'sticky', and the next "
            "FDOT32_CR would erase the evidence silently (§35.3 pin 2)")
        assert int(dut.any_error_flag.value) == 1

    # reset-clearable ONLY (§26.5 grade, bank_tag_collision_error twin).
    await _reset(dut)
    assert int(dut.fdotcr_unit_fault_error.value) == 0, \
        "the sticky survived reset — §26.5 grade is reset-CLEARABLE"
    assert int(dut.any_error_flag.value) == 0


# =============================================================================
# v1.8.0e 3a-C4 INTEGRATION PHASE — the FDOT32_CR VALUE axis at the CLUSTER
# boundary.
#
# The landing commit proved the value axis at the ISA_Decoder boundary (450
# golden vectors) and proved the sticky PORTS at the Cluster boundary, but it
# never scored a Cluster-boundary RESULT against the golden model: the two
# Cluster value checks were hand-typed constants (0x42800000 and the canonical
# qNaN). Everything the Cluster adds on top of ISA_Decoder — the is_mul_op
# twin classifier routing 0x7A to the MATMUL_UNIT, the fragment-reassembly
# CAM that rebuilds the 1,024-bit wave from 16 ext beats, the output OR-merge
# across 17 PE instances, the skid buffer — sits BETWEEN the golden model and
# the number the SDK will actually read back. A mis-route (0x7A answered by an
# L-PE), a reassembly permutation, or an OR-merge collision are all silent at
# the ISA_Decoder axis and all produce a wrong fp32 here.
# =============================================================================

def _fdotcr_vectors_cluster():
    """Parse include/generated/fdotcr_vectors.hex per its own contract
    (include/generated/fdotcr_vec_contract.md): 272 hex chars = 1,088 bits
    MSB-first, META[1087:1056] / OPERANDS[1055:32] / RESULT[31:0]."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        'include', 'generated', 'fdotcr_vectors.hex')
    out = []
    with open(path, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('//'):
                continue
            assert len(line) == 272, \
                f"vector line is {len(line)} hex chars, contract says 272"
            v = int(line, 16)
            meta = (v >> 1056) & 0xFFFFFFFF
            out.append({'wide': (v >> 32) & ((1 << 1024) - 1),
                        'result': v & 0xFFFFFFFF,
                        'dtype': meta & 0xFF,
                        'special': (meta >> 8) & 1,
                        'family': (meta >> 24) & 0xFF})
    return out


def _fdotcr_cluster_slice(vecs):
    """A DERIVED slice, never a hand-listed one: every 15th vector, plus the
    first vector of any family that stride misses (family 0x0C has only two
    rows in the whole file and a plain stride drops it). Coverage is then
    asserted by the caller, so a regenerated vector file that reshuffles
    families cannot silently shrink this test."""
    picked = list(vecs[::15])
    have = {v['family'] for v in picked}
    for v in vecs:
        if v['family'] not in have:
            picked.append(v)
            have.add(v['family'])
    return picked


async def _fdotcr_dispatch_no_reset(dut, wide, mode, limit=4000):
    """One FDOT32_CR through the Cluster with NO reset before or after.

    MEASUREMENT BOUNDARY (Cluster axis): cycle 0 is the `clk` rising edge
    on which the WAVE-COMPLETING ext beat is sampled (`ext_valid` high with
    `ext_frag_hdr` = {15, 15} — the 16th and last fragment). The stop point
    is the rising edge on which `ext_out_valid` is first high. Returns
    (cycles, payload, err, lwr, special, fault)."""
    from test_isa_decoder import eh_precision as _ehp
    instr = encode_instr(0x7A,
                         eh_port(input_port_mask=0x01, output_port_id=0),
                         _ehp(mode, 0), flags=(1 << 2))
    frags = [(wide >> (64 * i)) & ((1 << 64) - 1) for i in range(16)]
    await _fire_frag_wave(dut, instr, _tag(port_context_id=0), frags)
    # <- the last edge inside _fire_frag_wave was cycle 0 of the boundary
    payload, err, lwr, n = None, 0, 0, 0
    spec, flt = 0, 0
    while n < limit:
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        n += 1
        err |= int(dut.any_error_flag.value)
        lwr |= int(dut.any_lower_required.value)
        if int(dut.ext_out_valid.value):
            payload = int(dut.ext_out_payload.value)
            spec = int(dut.fdotcr_special_status.value)
            flt = int(dut.fdotcr_unit_fault_error.value)
            break
        if err or lwr:
            break
    return n, payload, err, lwr, spec, flt


@cocotb.test()
async def test_fdotcr_cluster_boundary_golden_bit_exact_and_sticky(dut):
    """3a-C4 integration phase — FDOT32_CR scored against the GOLDEN MODEL
    at the Cluster boundary, value AND sticky together, over a derived
    all-family slice dispatched BACK TO BACK WITH NO RESET BETWEEN.

    Three properties, and the third is the one no other test in the tree
    can state:

      (1) VALUE. `ext_out_payload` bit-equals the golden result. Two
          independent oracles are cross-checked first (the RESULT field
          frozen into the vector file vs a live
          scripts/golden_fdotcr.fdotcr_ref call), so neither can drift
          alone. This is the first time the Cluster's own additions —
          is_mul_op routing to the MATMUL_UNIT, the 16-beat fragment
          reassembly CAM, the 17-instance output OR-merge — are scored
          against the golden model instead of against two hand-typed
          constants.

      (2) STICKY, PER OP. `fdotcr_special_status` equals the golden
          model's own `sticky` field on every point. The landing commit
          proved this for ONE hand-made NaN; here the classification comes
          from the golden model over every family, including the
          special-operand families 0x0A/0x0B and the finite families that
          must NOT raise it.

      (3) THE qNaN DISCRIMINATOR. `0x7FC00000` is the result of a special
          operand (§27.7a.1 (iii)) AND the result of a stale-`cr_fp_dtype`
          OPS_BAD decode AND the result of a loud unit fault. The VALUE
          therefore cannot tell those apart — only the (value, sticky)
          PAIR can, which is precisely why §27.7a.3 check (i) recovers
          pairs and why §35.3 keeps the two sticky ports separate. So this
          test asserts the biconditional in both directions:
              payload == 0x7FC00000  <=>  fdotcr_special_status == 1
          Verified against the golden model over all 450 rows before it is
          asserted here (qNaN count 128 == special count 128), so it is a
          property of the contract, not a coincidence of the slice.
          A stale-dtype defect that returned qNaN with the sticky LOW is
          caught by the left-to-right direction; a sticky stuck high is
          caught by the right-to-left one.

    NO RESET BETWEEN DISPATCHES is load-bearing for (2): `fd_spec` is a
    per-op latch inside a reset-free block, so the only way to prove it
    tracks the CURRENT op rather than sticking from an earlier one is to
    run specials and finites interleaved without clearing anything."""
    import sys as _sys
    _sys.path.insert(0, os.path.join(os.path.dirname(
        os.path.abspath(__file__)), 'scripts'))
    import golden_fdotcr as _GFD
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    vecs = _fdotcr_vectors_cluster()
    assert len(vecs) == 450, f"expected 450 golden vectors, got {len(vecs)}"
    picked = _fdotcr_cluster_slice(vecs)
    fams = {v['family'] for v in picked}
    assert len(fams) == len({v['family'] for v in vecs}) == 14, (
        f"the derived slice lost family coverage: {sorted(fams)}")
    assert {v['dtype'] for v in picked} == {0x2, 0x3}, "dtype coverage lost"
    n_special = sum(v['special'] for v in picked)
    assert n_special >= 3 and n_special < len(picked), (
        f"the slice must interleave special and finite waves "
        f"(specials={n_special} of {len(picked)})")

    fails = []
    worst = 0
    for i, v in enumerate(picked):
        dt = _GFD.DT_F16 if v['dtype'] == 0x2 else _GFD.DT_BF16
        a_lanes = [(v['wide'] >> (16 * k)) & 0xFFFF for k in range(32)]
        b_lanes = [(v['wide'] >> (512 + 16 * k)) & 0xFFFF for k in range(32)]
        ref = _GFD.fdotcr_ref(dt, list(zip(a_lanes, b_lanes)))
        assert ref['bits'] == v['result'], (
            f"point {i}: the frozen RESULT 0x{v['result']:08X} and the live "
            f"golden model 0x{ref['bits']:08X} disagree — the two oracles "
            f"are no longer independent evidence")
        assert bool(ref['sticky']) == bool(v['special'])
        mode = 0x12 if v['dtype'] == 0x2 else 0x13
        cyc, pay, err, lwr, spec, flt = await _fdotcr_dispatch_no_reset(
            dut, v['wide'], mode)
        worst = max(worst, cyc)
        ctx = (f"point {i} family=0x{v['family']:02X} dtype=0x{v['dtype']:X} "
               f"special={v['special']}")
        if (err, lwr) != (0, 0) or pay != v['result']:
            fails.append(f"{ctx}: err={err} lwr={lwr} payload="
                         f"{pay if pay is None else hex(pay)} expected "
                         f"0x{v['result']:08X}")
            if len(fails) >= 5:
                break
            continue
        assert flt == 0, f"{ctx}: a legal vector raised the UNIT FAULT"
        assert spec == int(ref['sticky']), (
            f"{ctx}: fdotcr_special_status={spec} but the golden model says "
            f"sticky={int(ref['sticky'])}")
        assert (pay == 0x7FC00000) == (spec == 1), (
            f"{ctx}: payload=0x{pay:016X} with special_status={spec}. "
            f"A canonical qNaN with the sticky LOW is the silent-failure "
            f"signature of §27.7a.1 (iii) — the value alone cannot "
            f"distinguish 'special operand' from 'stale cr_fp_dtype -> "
            f"OPS_BAD'; only the (value, sticky) pair can")
        assert cyc <= 10000, (
            f"{ctx}: {cyc} cycles > the §27.7a.2 hard ceiling 10,000 "
            f"(Cluster axis — wave-completing ext beat -> ext_out_valid). "
            f"NOTE: 실효 경계는 _fdotcr_dispatch_no_reset budget 4,000 (더 "
            f"엄격). 10,000 pin 은 test_isa_decoder.py 의 test_fdot32_cr_cycle_boundaries_measured (_measure limit=10001) 가 단독 소유한다")
    assert not fails, (
        f"{len(fails)} of {len(picked)} golden points diverged at the "
        f"Cluster boundary:\n" + "\n".join(fails))
    dut._log.info(
        f"FDOT32_CR Cluster boundary: {len(picked)} golden points "
        f"({len(fams)} families, {n_special} special) bit-exact with "
        f"matching per-op sticky, back to back with no reset. Worst "
        f"{worst} cycles on the CLUSTER axis (wave-completing ext beat -> "
        f"ext_out_valid), ceiling 10,000")


@cocotb.test()
async def test_fdotcr_cycle_measured_cluster_axis(dut):
    """3a-C4 integration phase (spec §35.5.3) — the FDOT32_CR cycle
    MEASUREMENT on the Cluster axis, with both ends of the interval named.

    MEASUREMENT BOUNDARY, stated so the number means something:
      START  the `clk` rising edge on which the WAVE-COMPLETING ext beat is
             sampled — `ext_valid` high with `ext_frag_hdr` = {idx 15,
             tot_m1 15}, i.e. the 16th of the 16 beats that carry the
             1,024-bit A||B wave into the Cluster. The 15 earlier beats are
             fragment transport, not execution, and are excluded on purpose:
             including them would make the number depend on how fast the
             SDK feeds the port rather than on the step program.
      STOP   the rising edge on which `ext_out_valid` is first high.

    This is NOT the §35.5.3 binding axis. Binding is the UNIT axis
    (FP_StepSeq `start` -> `done`), measured exhaustively by the 3a-C3 TB at
    synth/lattice/fp_ops/tb_fp_stepseq.py, whose extended family sweep
    reaches operands the 450-vector file does not contain. The Cluster axis
    is a MEASUREMENT axis: it is reported, and the hard ceiling 10,000 is
    asserted on it, but the ceiling itself is not re-defined here.

    Three operand classes are measured so a single accidental number
    cannot pass for the whole picture: uniform finite, the slowest vector
    in the file, and a special (which exits early)."""
    import sys as _sys
    _sys.path.insert(0, os.path.join(os.path.dirname(
        os.path.abspath(__file__)), 'scripts'))
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)
    vecs = _fdotcr_vectors_cluster()
    slowest = vecs[22]                       # measured worst of the 450
    special = next(v for v in vecs if v['special'])
    uni = 0
    for i in range(32):
        uni |= 0x3F80 << (16 * i)            # A = bf16 1.0
        uni |= 0x4000 << (512 + 16 * i)      # B = bf16 2.0
    points = [
        ('bf16 uniform 32x(1.0*2.0)', 0x13, uni, 0x42800000, 0),
        ('bf16 slowest golden vector', 0x13, slowest['wide'],
         slowest['result'], slowest['special']),
        ('special operand (early out)',
         0x12 if special['dtype'] == 0x2 else 0x13, special['wide'],
         special['result'], special['special']),
    ]
    measured = []
    for label, mode, wide, expect, sp in points:
        cyc, pay, err, lwr, spec, flt = await _fdotcr_dispatch_no_reset(
            dut, wide, mode)
        assert (err, lwr) == (0, 0), f"{label}: err={err} lwr={lwr}"
        assert pay == expect, \
            f"{label}: payload {pay if pay is None else hex(pay)} != " \
            f"0x{expect:08X}"
        assert spec == sp, f"{label}: special_status={spec}, expected {sp}"
        assert flt == 0, f"{label}: unit fault on a legal vector"
        assert cyc <= 10000, (
            f"{label}: {cyc} cycles > the §27.7a.2 hard ceiling 10,000 "
            f"(Cluster axis: wave-completing ext beat -> ext_out_valid). "
            f"NOTE: 실효 경계는 _fdotcr_dispatch_no_reset budget 4,000 (더 "
            f"엄격). 10,000 pin 은 test_isa_decoder.py 의 test_fdot32_cr_cycle_boundaries_measured (_measure limit=10001) 가 단독 소유한다")
        measured.append((label, cyc))
        dut._log.info(
            f"FDOT32_CR CLUSTER-axis cycles [{label}] = {cyc} "
            f"(START = wave-completing ext beat, STOP = ext_out_valid; "
            f"hard ceiling 10,000, headroom {10000 / cyc:.1f}x)")
    lat = [c for _, c in measured]
    assert min(lat) != max(lat), (
        "all three operand classes measured the SAME latency — the step "
        "program stopped depending on its data, or the stimulus collapsed")
    # THE ORDERING PIN — the only assertion in the tree that can see a
    # special operand being pushed through the EFT anyway.
    #
    # §27.7a.1 (iii) is not "specials return qNaN", it is "specials do NOT
    # ENTER the EFT": FP_StepSeq leaves FDS_LOAD straight for FDS_DONE with
    # FDR_QNAN. An RTL change that let the special wave walk the whole lane
    # loop and only forced qNaN at the end would be BIT-IDENTICAL at every
    # value assertion in this file and would still raise the sticky — it
    # would only cost ~25x the cycles and expose the special lanes to the
    # multiply/insert datapath. Latency ordering is what makes that visible.
    uni_cyc = dict(measured)['bf16 uniform 32x(1.0*2.0)']
    slow_cyc = dict(measured)['bf16 slowest golden vector']
    sp_cyc = dict(measured)['special operand (early out)']
    #
    # HONESTY NOTE (§28.4 item 8): this pin is DEFENCE IN DEPTH, not a
    # mutation-demonstrated kill. The minimal RTL mutation for it — sending
    # the special wave to FDS_PRIME instead of FDS_DONE — also destroys the
    # value (fd_rsel is overwritten downstream), so it is killed here by the
    # payload assertion above, and no value-PRESERVING mutation of this
    # class could be produced without writing new RTL. The pin is kept
    # because the failure it describes is real and nothing else in the tree
    # would see it; do not read it as a proven kill.
    assert sp_cyc < uni_cyc < slow_cyc, (
        f"latency ordering broke: special={sp_cyc} uniform={uni_cyc} "
        f"slowest={slow_cyc}. A special wave that costs as much as a "
        f"finite one has ENTERED the EFT — §27.7a.1 (iii) forbids exactly "
        f"that, and every value/sticky assertion in this file is blind to "
        f"it because the answer is canonical qNaN either way")


@cocotb.test()
async def test_fdotcr_ingress_buffer_holds_against_shared_bus_change(dut):
    """3a-C4 adversarial-repair phase — the ONLY Cluster-axis test that can
    see the MU-local ingress buffer (`PE_Core.fd_ing_q`, 1,024 FF) do its
    job, and the reason the buffer is not free silicon.

    WHY THIS TEST EXISTS. amendment-13 (§27.7a.2c) chose ingress form 3:
    PE_Core latches the whole 1,024-bit A||B wave into an MU-LOCAL buffer at
    dispatch and then streams 64 bits/cycle into FP_StepSeq for 16 cycles.
    The cheap-looking alternative is to skip the buffer and index the live
    `dec_input_payload_wide` bus. Adversarial verification measured that
    that mutation

        assign fd_ing_frag = dec_input_payload_wide[{fd_ing_idx, 6'b0} +: 64];

    passes 327 of the tree's 328 tests — including the 450-vector bit-exact
    census and every Cluster/Pod test — because in every other stimulus the
    bus simply never changes during the 15-cycle streaming window. One
    ISA_Decoder-level test killed it; the whole Cluster axis was blind.

    THE MECHANISM THAT MAKES IT KILLABLE HERE. A Cluster has ONE ISA_Decoder
    (Cluster.v:1005) whose `dec_input_payload_wide` fans out to all 17
    PE_Cores (Cluster.v:1246 / :1317 / :1385). So a token addressed to an
    L-PE — a plain ADD .imm16, not is_mul_op, no contention with the MU and
    no ownership-rung rejection — rewrites the bus the MU is streaming from.
    That is not a contrived poke: it is the normal case of two ports feeding
    one cluster.

    MEASURED STIMULUS GEOMETRY (do not treat these numbers as free
    parameters). The wide bus is a COMPLETED-WAVE register: it updates when
    a wave's last fragment is reassembled, ~5 cycles later, and an
    N-fragment wave overwrites only words 0..N-1, leaving the rest holding
    the previous wave. The MU reads word k at cycle 6+k. Measured
    consequence: an N-fragment disturber corrupts EXACTLY word N-1. So the
    sweep below is chosen to walk the corruption across both operand
    halves — words 5,7 (inside A) and 9,11,13,15 (inside B) — and each
    point independently kills the mutation with a different wrong payload.

    ANTI-SILENT-WEAKENING. Because the hit index depends on that timing, the
    test does not trust it: it watches `fd_ing_run`/`fd_ing_idx` and the bus
    and records which word was actually read from a CHANGED bus. If timing
    ever drifts so that nothing overlaps, the test FAILS loudly instead of
    passing as an empty ritual, and it demands a hit in each half."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    from test_isa_decoder import eh_precision as _ehp
    M64 = (1 << 64) - 1
    wide = 0
    for i in range(32):
        wide |= 0x3F80 << (16 * i)              # A = bf16 1.0, all 32 lanes
        wide |= 0x4000 << (512 + 16 * i)        # B = bf16 2.0, all 32 lanes
    EXPECT = 0x42800000                          # 32 * (1.0 * 2.0) = 64.0
    frags = [(wide >> (64 * i)) & M64 for i in range(16)]

    instr_a = encode_instr(0x7A,
                           eh_port(input_port_mask=0x01, output_port_id=0),
                           _ehp(0x13, 0), flags=(1 << 2))
    instr_b = encode_instr(0x10, eh_port(input_port_mask=0x01,
                                         output_port_id=0), eh_imm16(5))

    hit_words = set()
    for nb in (6, 8, 10, 12, 14, 16):
        await _reset(dut)
        await _fire_frag_wave(dut, instr_a, _tag(port_context_id=0), frags)

        async def _disturb(n=nb):
            # The L-PE-addressed disturber. Its payload words are nothing
            # like the FDOT32_CR wave, so a live read cannot coincidentally
            # produce the right answer.
            await _fire_frag_wave(
                dut, instr_b, make_tag(wave_number=2, port_context_id=1),
                [(0xDEADBEEF00000000 + i) for i in range(n)])

        cocotb.start_soon(_disturb())

        hot, err, lwr, payload, cyc = set(), 0, 0, None, 0
        for c in range(1, 4000):
            await RisingEdge(dut.clk)
            await Timer(1, units="ns")
            cyc = c
            err |= int(dut.any_error_flag.value)
            lwr |= int(dut.any_lower_required.value)
            if int(dut.u_matmul_unit.fd_ing_run.value):
                k = int(dut.u_matmul_unit.fd_ing_idx.value)
                live = (int(dut.dec_input_payload_wide.value) >> (64 * k)) & M64
                if live != frags[k]:
                    hot.add(k)
            if (int(dut.ext_out_valid.value)
                    and int(dut.ext_out_opcode.value) == 0x7A):
                payload = int(dut.ext_out_payload.value)
                break

        ctx = f"disturber={nb} fragments, corrupted-on-read words={sorted(hot)}"
        assert (err, lwr) == (0, 0), (
            f"{ctx}: err={err} lwr={lwr}. The disturber is a legal ADD to a "
            f"different PE; it must not raise anything")
        assert payload == EXPECT, (
            f"{ctx}: FDOT32_CR returned "
            f"{'no output' if payload is None else hex(payload)}, expected "
            f"0x{EXPECT:08X}. A word of the in-flight wave was taken from "
            f"the LIVE shared bus instead of the MU-local fd_ing_q buffer "
            f"— this is exactly the amendment-13 defect, and it is silent "
            f"everywhere else in the tree")
        assert int(dut.fdotcr_special_status.value) == 0, \
            f"{ctx}: a finite wave raised the special sticky"
        assert int(dut.fdotcr_unit_fault_error.value) == 0, \
            f"{ctx}: unit fault on a legal wave"
        assert cyc <= 10000, \
            f"{ctx}: {cyc} cycles > the §27.7a.2 hard ceiling 10,000 "\
            f"(NOTE: 실효 경계는 이 루프의 range(1, 4000) budget 3,999 로 더 "\
            f"엄격하다. 10,000 pin 은 test_isa_decoder.py 의 test_fdot32_cr_cycle_boundaries_measured (_measure limit=10001) 가 단독 소유한다)"
        hit_words |= hot
        dut._log.info(
            f"FDOT32_CR ingress-buffer pin [{ctx}] payload=0x{payload:08X} "
            f"cycles={cyc}")

    # --- the test must prove it actually tested something -----------------
    assert hit_words, (
        "NOT ONE fragment was read from a changed bus in any of the six "
        "points, so this test asserted nothing about fd_ing_q. The stimulus "
        "geometry documented in the docstring has drifted (the wide bus is "
        "a completed-wave register; an N-fragment disturber must land on "
        "word N-1 while fd_ing_run is high). Re-tune the sweep — do NOT "
        "delete this test, it is one of only two in the tree that can see "
        "the 1,024-FF buffer at all.")
    assert any(k <= 7 for k in hit_words) and any(k >= 8 for k in hit_words), (
        f"the corruption only reached words {sorted(hit_words)}. The buffer "
        f"holds A (words 0-7) and B (words 8-15) and both halves must be "
        f"shown to survive; a sweep that only hits one half would pass with "
        f"the other half wired to the live bus.")
    dut._log.info(
        f"FDOT32_CR ingress-buffer pin: words read from a CHANGED shared "
        f"bus = {sorted(hit_words)} (A half 0-7, B half 8-15)")
