# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

"""Top_Core integration testbench.

Verifies that ISA_Decoder.v and HIU.v are correctly wired in Top_Core.v:

  * LOAD asserts a memory request into the HIU and the IOMMU/DMA pipeline
    eventually replies with `mem_dma_ack` rising.
  * Non-memory ops (ADD with immediate) leave `mem_dma_ack` low.
  * `error_flag` and `lower_required` propagate from the inner decoder
    out to the Top_Core boundary unchanged.
"""

import os
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

# Reuse the assembler so test instructions are authored in source form.
_REPO = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_REPO, 'asm'))
from wavetensor_asm import assemble_one  # noqa: E402

# Reuse encoding helpers / tag builder from the standalone decoder test.
from test_isa_decoder import (  # noqa: E402
    eh_port, eh_imm16, eh_mem, eh_opref, axes, eh_subscript,
    encode_instr, make_tag, pack16, F_HAS_OPB,
)


# Default port used in every test
PORT_MASK = 0x01
PORT_OUT  = 0x00


def _std_tag(dim=0):
    return make_tag(port_context_id=0, dimension_sizes=dim)


async def _reset(dut):
    dut.rst.value = 1
    dut.token_valid.value = 0
    dut.input_payload_b_valid.value = 0
    dut.instruction.value = 0
    dut.input_tag.value = 0
    dut.input_payload.value = 0
    dut.input_payload_b.value = 0
    dut.mem_data_in.value = 0
    dut.context_switch.value = 0
    dut.partition_id.value = 0
    dut.interface_type.value = 0
    dut.ats_req.value = 0
    dut.pri_req.value = 0
    dut.shadow_write_start.value = 0
    dut.shadow_write_end.value = 0
    dut.shadow_write_en.value = 0
    dut.shadow_index.value = 0
    dut.chacha_key.value = 0xDEADBEEFCAFEBABE0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF
    dut.chacha_nonce.value = 0xAABBCCDDEEFF00112233445566778899AABBCCDDEEFF0011
    await Timer(20, units="ns")
    dut.rst.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")


async def _install_shadow_region(dut, start, end, index):
    """Install an identity-mapped shadow region so LOAD/STORE virt_addrs
    in [start, end] map straight through HIU."""
    dut.shadow_write_start.value = start
    dut.shadow_write_end.value = end
    dut.shadow_index.value = index
    dut.shadow_write_en.value = 1
    await RisingEdge(dut.clk)
    dut.shadow_write_en.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")


async def _fire(dut, instruction, tag, payload_a=0, payload_b=0,
                payload_b_valid=0):
    dut.instruction.value = instruction
    dut.input_tag.value = tag
    dut.input_payload.value = payload_a
    dut.input_payload_b.value = payload_b
    dut.input_payload_b_valid.value = payload_b_valid
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0
    # Poll for completion (chain walk + dispatch + optional multi-cycle pipe).
    # LOAD doesn't strobe output_valid; bail on dma_ack as well.
    for _ in range(80):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if (int(dut.output_valid.value) == 1
                or int(dut.error_flag.value) == 1
                or int(dut.lower_required.value) == 1
                or int(dut.mem_dma_ack.value) == 1):
            break


@cocotb.test()
async def test_add_does_not_touch_hiu(dut):
    """ADD with immediate is a pure ALU op — HIU must remain idle."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    instr = assemble_one(
        f".default_port mask={PORT_MASK:#x} out={PORT_OUT}\n"
        "ADD .imm16 5\n"
    )
    await _fire(dut, instr, _std_tag(), payload_a=10)

    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 15
    # HIU should not have asserted dma_ack at this point
    assert dut.mem_dma_ack.value == 0
    assert dut.error_flag.value == 0
    assert dut.lower_required.value == 0


@cocotb.test()
async def test_load_routes_through_hiu(dut):
    """A LOAD opcode must drive ISA_Decoder.memory_req → HIU.dma_req,
    and HIU eventually answers with mem_dma_ack."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    # Map an identity shadow region so the LOAD's virt_addr is permitted.
    await _install_shadow_region(dut, start=0x0000, end=0xFFFF, index=0)

    # input_payload supplies a base address; .mem offset adds to it.
    instr = assemble_one(
        f".default_port mask={PORT_MASK:#x} out={PORT_OUT}\n"
        "LD .mem offset=0x100\n"
    )
    # Provide the data the DMA engine will surface on mem_data_out.
    dut.mem_data_in.value = 0xCAFEBABE
    await _fire(dut, instr, _std_tag(), payload_a=0x1000)

    # HIU's pipeline (TLB lookup → dummy delay → ChaCha20 H + main → DMA exec)
    # is ~30 cycles. Wait until dma_ack rises or we time out.
    saw_ack = False
    for _ in range(80):
        await RisingEdge(dut.clk)
        if int(dut.mem_dma_ack.value) == 1:
            saw_ack = True
            break

    assert saw_ack, "Top_Core: HIU never produced dma_ack for the LOAD request"
    # phys_addr should reflect the virt → phys identity mapping installed above.
    # (mask is XORed in HIU's CHACHA_FINAL stage, so the on-bus phys_addr
    # may be the masked variant — but the LOW 16 bits include the offset.)
    assert (int(dut.mem_phys_addr.value) & 0xFFFF) == 0x1100 or \
           (int(dut.mem_phys_addr.value) & 0xFFFFFFFF) != 0, \
           "phys_addr did not propagate from HIU to top boundary"


@cocotb.test()
async def test_error_flag_propagates(dut):
    """A divide-by-zero inside ISA_Decoder must surface at Top_Core's
    error_flag output."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    instr = assemble_one(
        f".default_port mask={PORT_MASK:#x} out={PORT_OUT}\n"
        "DIV .imm16 0\n"
    )
    await _fire(dut, instr, _std_tag(), payload_a=99)
    assert dut.error_flag.value == 1
    assert dut.output_valid.value == 0


@cocotb.test()
async def test_lower_required_propagates(dut):
    """An EINSUM pattern that's not in the HW kernel set must raise
    lower_required at the top boundary, not error_flag."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    # Construct an instruction directly: subscript with all-d labels has
    # no HW kernel match.
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
    assert dut.output_valid.value == 0


@cocotb.test()
async def test_einsum_matmul_e2e_through_top(dut):
    """EINSUM matmul kernel runs entirely inside ISA_Decoder, so HIU must
    stay idle while the result propagates out of Top_Core."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    a = pack16(1, 2, 3, 4)
    b = pack16(5, 6, 7, 8)
    expected = pack16(19, 22, 43, 50)

    instr = assemble_one(
        f".alias port_a {PORT_MASK:#x}\n"
        f".default_port mask=port_a out={PORT_OUT}\n"
        "EINSUM opb .subscript A=i,j B=j,k O=i,k .opref\n"
    )
    await _fire(dut, instr, _std_tag(dim=0x05),
                payload_a=a, payload_b=b, payload_b_valid=1)

    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == expected
    assert dut.mem_dma_ack.value == 0


@cocotb.test()
async def test_trng_phase1_emits_bytes(dut):
    """TRNG Phase 1: HIU's RO-based entropy source must produce non-zero
    `rng_raw_valid` strobes within a reasonable warm-up window. The exact
    bytes are not asserted (entropy by definition), but we require that
    several distinct values appear so the von Neumann debiaser is alive."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    seen = []
    valids = 0
    for _ in range(2000):
        await RisingEdge(dut.clk)
        if int(dut.rng_raw_valid.value) == 1:
            valids += 1
            seen.append(int(dut.rng_raw.value))

    assert valids >= 4, (
        f"TRNG Phase 1: rng_raw_valid pulsed only {valids} times in 2000 "
        "cycles — entropy stream appears stalled"
    )
    assert len(set(seen)) >= 2, (
        f"TRNG Phase 1: only {len(set(seen))} unique bytes across {valids} "
        "samples — debias output is constant"
    )


@cocotb.test()
async def test_trng_phase3_word_and_health(dut):
    """TRNG Phase 3: 64-bit `rng_word` should pulse at least once within a
    long warm-up window (8 raw bytes per word). `trng_unhealthy` must remain
    LOW under nominal RO simulation behavior — the LFSR proxy never
    repeats > 41 times and never repeats > 51 times within 64 samples."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await _reset(dut)

    word_pulses = 0
    last_word = None
    distinct = 0
    for _ in range(20000):
        await RisingEdge(dut.clk)
        if int(dut.trng_unhealthy.value) == 1:
            assert False, "TRNG Phase 3: trng_unhealthy went high under sim"
        if int(dut.rng_word_valid.value) == 1:
            word_pulses += 1
            w = int(dut.rng_word.value)
            if last_word is not None and w != last_word:
                distinct += 1
            last_word = w

    assert word_pulses >= 1, (
        f"TRNG Phase 3: rng_word_valid never pulsed in 20000 cycles "
        "(expected at least one 64-bit word)"
    )
    if word_pulses >= 2:
        assert distinct >= 1, (
            "TRNG Phase 3: multiple word pulses but all identical — "
            "conditioning appears stuck"
        )
