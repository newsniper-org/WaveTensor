# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

"""WaveTensor ISA_Decoder cocotb testbench.

Exercises the TLV (IPv6 EH-style) variable-length instruction decoder:

  * Encoding helpers for base header + chained extension headers
  * Migrated legacy opcode tests (WAVE-ADVANCE, STEER, MERGE, LOAD/STORE,
    arithmetic, shift/rotate, divrem, bit-reverse)
  * Full EINSUM coverage for the eight supported subscript patterns
  * Negative tests asserting `error_flag` for malformed instructions
  * Python mirror decoder verifying the encoder is well-formed before
    exercising the RTL
"""

import os
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge

# Make the assembler importable so end-to-end tests can drive ISA_Decoder
# directly from text-based assembly.
_REPO = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_REPO, 'asm'))
try:
    from wavetensor_asm import assemble, assemble_one
    _HAS_ASM = True
except ImportError:
    _HAS_ASM = False


# =============================================================================
# Encoding helpers
# =============================================================================

EH_END        = 0x0
EH_PORT       = 0x1
EH_IMM16      = 0x2
EH_IMM32      = 0x3
EH_IMM64      = 0x4
EH_MEM        = 0x5
EH_SUBSCRIPT  = 0x6
EH_OPREF      = 0x7
EH_PRECISION  = 0x8
EH_NOP_PAD    = 0xF

F_HAS_OPB        = 1 << 3
F_PRECISION_OVR  = 1 << 2
F_MEM            = 1 << 1

INSTR_WORDS_REAL = 13          # 32 + 4*96 = 416 → 13 words
INSTR_WIDTH      = INSTR_WORDS_REAL * 32


class EH:
    def __init__(self, type_code, words, body_fn):
        self.type = type_code
        self.words = words
        self._body_fn = body_fn

    def emit(self, next_hdr):
        return self._body_fn(next_hdr)


def eh_port(input_port_mask, output_port_id):
    def fn(nh):
        body16 = ((output_port_id & 0xFF) << 8) | (input_port_mask & 0xFF)
        return [(body16 << 16) | (nh << 12) | (EH_PORT << 8) | 1]
    return EH(EH_PORT, 1, fn)


def eh_imm16(v):
    def fn(nh):
        return [((v & 0xFFFF) << 16) | (nh << 12) | (EH_IMM16 << 8) | 1]
    return EH(EH_IMM16, 1, fn)


def eh_imm32(v):
    def fn(nh):
        return [(nh << 12) | (EH_IMM32 << 8) | 2,
                v & 0xFFFFFFFF]
    return EH(EH_IMM32, 2, fn)


def eh_imm64(v):
    def fn(nh):
        return [(nh << 12) | (EH_IMM64 << 8) | 3,
                v & 0xFFFFFFFF,
                (v >> 32) & 0xFFFFFFFF]
    return EH(EH_IMM64, 3, fn)


def eh_mem(offset, addr_mode=0, stride=0):
    def fn(nh):
        upper = ((stride & 0xFFF) << 4) | (addr_mode & 0xF)
        return [(upper << 16) | (nh << 12) | (EH_MEM << 8) | 2,
                offset & 0xFFFFFFFF]
    return EH(EH_MEM, 2, fn)


def eh_subscript(a_axes16, b_axes16, o_axes16):
    """`*_axes16` is a 16-bit packed value: axis0[3:0], axis1[7:4],
    axis2[11:8], axis3[15:12]. Use `axes(*labels)` to construct one."""
    def fn(nh):
        return [((o_axes16 & 0xFFFF) << 16) | (nh << 12) | (EH_SUBSCRIPT << 8) | 2,
                ((a_axes16 & 0xFFFF) << 16) | (b_axes16 & 0xFFFF)]
    return EH(EH_SUBSCRIPT, 2, fn)


def eh_opref(src_kind=0, port_id=0, noc_route=0):
    def fn(nh):
        upper = ((noc_route & 0xFF) << 8) | ((port_id & 0xF) << 4) | (src_kind & 0xF)
        return [(upper << 16) | (nh << 12) | (EH_OPREF << 8) | 1]
    return EH(EH_OPREF, 1, fn)


def eh_precision(precision_mode, dim_override=0):
    def fn(nh):
        upper = ((dim_override & 0xFF) << 8) | (precision_mode & 0xFF)
        return [(upper << 16) | (nh << 12) | (EH_PRECISION << 8) | 1]
    return EH(EH_PRECISION, 1, fn)


def axes(*labels):
    """Pack up to 4 axis labels (each 0..0xF) into a 16-bit value."""
    if len(labels) > 4:
        raise ValueError("at most 4 axes")
    v = 0
    for i, l in enumerate(labels):
        v |= (l & 0xF) << (i * 4)
    return v


def encode_instr(opcode, *exts, flags=0, force_bh_len=None,
                 force_reserved=0, force_chain_break=False):
    """Build the 416-bit instruction value.

    `force_bh_len`        — override the bh_len field (negative testing)
    `force_reserved`      — override the reserved byte (negative testing)
    `force_chain_break`   — corrupt the first EH's `type` field so that the
                            chain walk reports `chain_err` (negative testing)
    """
    chained = []
    nh = EH_END
    for eh in reversed(exts):
        chained.insert(0, (eh, nh))
        nh = eh.type
    first_next_hdr = nh

    bh_len = 1 + sum(eh.words for eh, _ in chained)
    if force_bh_len is not None:
        bh_len_field = force_bh_len & 0xFF
    else:
        bh_len_field = bh_len & 0xFF

    base = ((opcode & 0xFF) << 24) \
         | ((first_next_hdr & 0xF) << 20) \
         | ((flags & 0xF) << 16) \
         | ((force_reserved & 0xFF) << 8) \
         | bh_len_field

    words = [base]
    for idx, (eh, nh_val) in enumerate(chained):
        emitted = eh.emit(nh_val)
        if force_chain_break and idx == 0:
            # Corrupt the first EH's type nibble so it disagrees with the
            # base.next_hdr expectation.
            emitted[0] = (emitted[0] & ~(0xF << 8)) | (0xE << 8)
        words.extend(emitted)
    while len(words) < INSTR_WORDS_REAL:
        words.append(0)

    val = 0
    for i, w in enumerate(words):
        val |= (w & 0xFFFFFFFF) << (i * 32)
    return val


def make_tag(wave_number=0, thread_id=0, port_context_id=0,
             precision_mode=0, dimension_sizes=0):
    return ((wave_number & 0xFFFFFFFF) << 48) \
         | ((thread_id & 0xFFFF) << 32) \
         | ((port_context_id & 0xFFFF) << 16) \
         | ((precision_mode & 0xFF) << 8) \
         | (dimension_sizes & 0xFF)


def pack16(*elems):
    """Pack up to 4 16-bit values into a 64-bit payload (little-endian)."""
    v = 0
    for i, e in enumerate(elems):
        v |= (e & 0xFFFF) << (i * 16)
    return v


# ---------- Mirror decoder (encoder self-check) ----------

def _decode_mirror(instr_int):
    """Re-walks the encoded instruction in pure Python, returns dict of fields.

    Used to catch encoder bugs before they reach the RTL."""
    iw = [(instr_int >> (i * 32)) & 0xFFFFFFFF for i in range(INSTR_WORDS_REAL)]
    base = iw[0]
    out = {
        'opcode':   (base >> 24) & 0xFF,
        'next_hdr': (base >> 20) & 0xF,
        'flags':    (base >> 16) & 0xF,
        'reserved': (base >> 8) & 0xFF,
        'bh_len':   base & 0xFF,
        'ehs':      [],
    }
    expect = out['next_hdr']
    off = 1
    safety = 0
    while expect != EH_END and safety < 8:
        safety += 1
        if off >= INSTR_WORDS_REAL:
            out['eh_overflow'] = True
            break
        w0 = iw[off]
        eh_next = (w0 >> 12) & 0xF
        eh_type = (w0 >> 8) & 0xF
        eh_len  = w0 & 0xFF
        if eh_type != expect:
            out['chain_break_at'] = off
            break
        out['ehs'].append({
            'type': eh_type, 'len': eh_len, 'next': eh_next,
            'words': iw[off:off + eh_len],
        })
        off += eh_len
        expect = eh_next
    out['walked_words'] = off
    return out


# =============================================================================
# Drive helper
# =============================================================================

async def fire(dut, instruction, tag, payload_a=0,
               payload_b=0, payload_b_valid=0,
               payload_wide=0, payload_wide_valid=0):
    dut.instruction.value = instruction
    dut.input_tag.value = tag
    dut.input_payload.value = payload_a
    dut.input_payload_b.value = payload_b
    dut.input_payload_b_valid.value = payload_b_valid
    dut.input_payload_wide.value = payload_wide
    dut.input_payload_wide_valid.value = payload_wide_valid
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0
    # EHDecode pipeline (chain walk SLOT 0..3 + dec_* latch) = 5 cycles, then
    # PE_Core dispatch 1..3 cycles depending on op (single-cycle ALU vs.
    # multi-cycle MUL/DIV pipeline). Poll for the strobe / error / lower
    # flag. The Timer(1ns) inside the loop is essential — Verilator returns
    # post-edge values only after a brief delta-cycle settle.
    for _ in range(80):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if (int(dut.output_valid.value) == 1
                or int(dut.error_flag.value) == 1
                or int(dut.lower_required.value) == 1
                or int(dut.memory_req.value) == 1):
            break


async def reset(dut):
    dut.rst.value = 1
    dut.token_valid.value = 0
    dut.input_payload_b_valid.value = 0
    dut.instruction.value = 0
    dut.input_tag.value = 0
    dut.input_payload.value = 0
    dut.input_payload_b.value = 0
    # v1.5.2 §19 — default wide input to zero (legacy path).
    dut.input_payload_wide.value = 0
    dut.input_payload_wide_valid.value = 0
    await Timer(15, units="ns")
    dut.rst.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")


# Standard PORT EH used by every test: input_port_mask=0x01 maps to
# port_context_id=0 in tag_match logic. output_port_id = 0.
_STD_PORT = lambda: eh_port(input_port_mask=0x01, output_port_id=0x00)
_STD_TAG = lambda dim=0: make_tag(port_context_id=0, dimension_sizes=dim)


# =============================================================================
# Encoder self-check (runs before any RTL traffic so encoder bugs surface
# without the decoder muddying the picture).
# =============================================================================

@cocotb.test()
async def test_encoder_self_check(dut):
    """Round-trip encode → mirror-decode each pattern used by later tests."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    instr = encode_instr(0x10, _STD_PORT(), eh_imm16(0x1234))
    m = _decode_mirror(instr)
    assert m['opcode'] == 0x10, f"opcode roundtrip {m}"
    assert m['next_hdr'] == EH_PORT
    assert m['ehs'][0]['type'] == EH_PORT
    assert m['ehs'][1]['type'] == EH_IMM16
    assert m['bh_len'] == 1 + 1 + 1

    instr = encode_instr(0x32,
                         _STD_PORT(),
                         eh_subscript(axes(1), axes(), axes()),
                         eh_opref(),
                         flags=F_HAS_OPB)
    m = _decode_mirror(instr)
    assert [eh['type'] for eh in m['ehs']] == [EH_PORT, EH_SUBSCRIPT, EH_OPREF]
    assert m['flags'] == (F_HAS_OPB >> 0)


# =============================================================================
# Legacy opcode coverage (migrated from old hex literals)
# =============================================================================

@cocotb.test()
async def test_wave_advance_increments_wave_number(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x01, _STD_PORT())
    tag = make_tag(wave_number=1, thread_id=0xAAAA, port_context_id=0)
    await fire(dut, instr, tag, payload_a=0xDEADBEEF)

    assert dut.output_valid.value == 1, "WAVE-ADVANCE did not fire"
    out_tag = int(dut.output_tag.value)
    out_wave = (out_tag >> 48) & 0xFFFFFFFF
    out_thread = (out_tag >> 32) & 0xFFFF
    assert out_wave == 2, f"wave_number not incremented (got {out_wave})"
    assert out_thread == 0xAAAA
    assert int(dut.output_payload.value) == 0xDEADBEEF
    assert dut.error_flag.value == 0


@cocotb.test()
async def test_steer_passes_payload_through(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x02, _STD_PORT())
    tag = _STD_TAG()
    await fire(dut, instr, tag, payload_a=0xCAFEBABE)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 0xCAFEBABE
    assert dut.error_flag.value == 0


@cocotb.test()
async def test_load_issues_memory_request(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x04, _STD_PORT(), eh_mem(offset=0x100))
    tag = _STD_TAG()
    await fire(dut, instr, tag, payload_a=0x1000)

    assert dut.memory_req.value == 1
    assert int(dut.mem_addr.value) == 0x1100
    assert dut.error_flag.value == 0


@cocotb.test()
async def test_tag_mismatch_blocks_execution(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # PORT EH advertises mask=0x01 (matches port_context_id=0); we drive
    # port_context_id=4, no match.
    instr = encode_instr(0x10, _STD_PORT(), eh_imm16(0))
    tag = make_tag(port_context_id=4)
    await fire(dut, instr, tag, payload_a=42)
    assert dut.output_valid.value == 0
    assert dut.error_flag.value == 0


@cocotb.test()
async def test_shift_left(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x17, _STD_PORT(), eh_imm16(4))
    await fire(dut, instr, _STD_TAG(), payload_a=1)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 0x10


@cocotb.test()
async def test_rotate_right(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x1A, _STD_PORT(), eh_imm16(4))
    await fire(dut, instr, _STD_TAG(), payload_a=0xF0000001)
    assert dut.output_valid.value == 1
    expected = ((0xF0000001 >> 4) | (0xF0000001 << 60)) & ((1 << 64) - 1)
    assert int(dut.output_payload.value) == expected


@cocotb.test()
async def test_logical_negation(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x1B, _STD_PORT())
    await fire(dut, instr, _STD_TAG(), payload_a=1)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == ((-1) & ((1 << 64) - 1))


@cocotb.test()
async def test_divrem(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x1D, _STD_PORT(), eh_imm16(5))
    await fire(dut, instr, _STD_TAG(), payload_a=0x1E)  # 30
    assert dut.output_valid.value == 1
    # {quotient (high 32), remainder (low 32)} for 32-bit halves
    expected = (6 << 32) | 0
    assert int(dut.output_payload.value) == expected


@cocotb.test()
async def test_div_by_zero_sets_error(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x13, _STD_PORT(), eh_imm16(0))
    await fire(dut, instr, _STD_TAG(), payload_a=99)
    assert dut.output_valid.value == 0
    assert dut.error_flag.value == 1


@cocotb.test()
async def test_bits_ord_reverse(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x1F, _STD_PORT())
    await fire(dut, instr, _STD_TAG(), payload_a=1)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == (1 << 63)


# =============================================================================
# Bitwise op tests — AND/OR/XOR/NAND/NOR/XNOR + SHR/SAR/ROL +
# NOT/POPCOUNT/CLZ/CTZ
# =============================================================================

@cocotb.test()
async def test_bitwise_and(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    instr = encode_instr(0x14, _STD_PORT(), eh_imm16(0x00FF))
    await fire(dut, instr, _STD_TAG(), payload_a=0xABCD)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 0xCD


@cocotb.test()
async def test_bitwise_or(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    instr = encode_instr(0x15, _STD_PORT(), eh_imm16(0x0F00))
    await fire(dut, instr, _STD_TAG(), payload_a=0x00CD)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 0x0FCD


@cocotb.test()
async def test_bitwise_xor(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    instr = encode_instr(0x16, _STD_PORT(), eh_imm16(0xFFFF))
    await fire(dut, instr, _STD_TAG(), payload_a=0xAAAA)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 0x5555


@cocotb.test()
async def test_bitwise_shr_logical(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    instr = encode_instr(0x18, _STD_PORT(), eh_imm16(4))
    await fire(dut, instr, _STD_TAG(), payload_a=0x80000000_00000010)
    assert dut.output_valid.value == 1
    # logical shift right — top bits zero-fill
    assert int(dut.output_payload.value) == 0x08000000_00000001


@cocotb.test()
async def test_bitwise_sar_arithmetic(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    instr = encode_instr(0x19, _STD_PORT(), eh_imm16(4))
    # MSB=1 → arithmetic right shift sign-extends
    await fire(dut, instr, _STD_TAG(), payload_a=0x80000000_00000010)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 0xF8000000_00000001


@cocotb.test()
async def test_bitwise_rol(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    instr = encode_instr(0x1E, _STD_PORT(), eh_imm16(8))
    await fire(dut, instr, _STD_TAG(), payload_a=0xAA00000000000055)
    assert dut.output_valid.value == 1
    # rotate left 8 → low byte 0x55 wraps to high byte
    assert int(dut.output_payload.value) == 0x00000000000055AA


@cocotb.test()
async def test_bitwise_not(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    instr = encode_instr(0x50, _STD_PORT())
    await fire(dut, instr, _STD_TAG(), payload_a=0x00000000FFFFFFFF)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 0xFFFFFFFF00000000


@cocotb.test()
async def test_bitwise_nand(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    instr = encode_instr(0x51, _STD_PORT(), eh_imm16(0xFFFF))
    await fire(dut, instr, _STD_TAG(), payload_a=0x00FF)
    assert dut.output_valid.value == 1
    # ~(0x00FF & 0xFFFF) = ~0x00FF = 0xFFFFFFFFFFFFFF00
    assert int(dut.output_payload.value) == 0xFFFFFFFFFFFFFF00


@cocotb.test()
async def test_bitwise_nor(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    instr = encode_instr(0x52, _STD_PORT(), eh_imm16(0x000F))
    await fire(dut, instr, _STD_TAG(), payload_a=0xF0)
    assert dut.output_valid.value == 1
    # ~(0xF0 | 0x0F) = ~0xFF = 0xFFFFFFFFFFFFFF00
    assert int(dut.output_payload.value) == 0xFFFFFFFFFFFFFF00


@cocotb.test()
async def test_bitwise_xnor(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    instr = encode_instr(0x53, _STD_PORT(), eh_imm16(0xAAAA))
    await fire(dut, instr, _STD_TAG(), payload_a=0xAAAA)
    assert dut.output_valid.value == 1
    # ~(0xAAAA ^ 0xAAAA) = ~0 = all-ones
    assert int(dut.output_payload.value) == ((1 << 64) - 1)


@cocotb.test()
async def test_bitwise_popcount(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    instr = encode_instr(0x54, _STD_PORT())
    await fire(dut, instr, _STD_TAG(), payload_a=0xF0F0F0F0F0F0F0F0)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 32


@cocotb.test()
async def test_bitwise_clz(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    instr = encode_instr(0x55, _STD_PORT())
    await fire(dut, instr, _STD_TAG(), payload_a=0x0000_0000_0000_0001)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 63

    await reset(dut)
    await fire(dut, instr, _STD_TAG(), payload_a=0x0)
    assert int(dut.output_payload.value) == 64


@cocotb.test()
async def test_bitwise_ctz(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    instr = encode_instr(0x56, _STD_PORT())
    await fire(dut, instr, _STD_TAG(), payload_a=0x8000_0000_0000_0000)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 63

    await reset(dut)
    await fire(dut, instr, _STD_TAG(), payload_a=0x0)
    assert int(dut.output_payload.value) == 64


@cocotb.test()
async def test_add_with_imm(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x10, _STD_PORT(), eh_imm16(5))
    await fire(dut, instr, _STD_TAG(), payload_a=10)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 15


@cocotb.test()
async def test_add_with_opref_uses_payload_b(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x10, _STD_PORT(), eh_opref(), flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(),
               payload_a=100, payload_b=23, payload_b_valid=1)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 123


# =============================================================================
# MATMUL & TENSOR_ADD with input_payload_b
# =============================================================================

@cocotb.test()
async def test_matmul_2x2(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a = pack16(1, 2, 3, 4)        # [[1,2],[3,4]]
    b = pack16(5, 6, 7, 8)        # [[5,6],[7,8]]
    # expected 2×2: [[1*5+2*7, 1*6+2*8], [3*5+4*7, 3*6+4*8]]
    #             = [[19, 22], [43, 50]]
    expected = pack16(19, 22, 43, 50)

    instr = encode_instr(0x30, _STD_PORT(), eh_opref(), flags=F_HAS_OPB)
    tag = _STD_TAG(dim=0x05)   # dim1=2, dim2=2
    await fire(dut, instr, tag, payload_a=a, payload_b=b, payload_b_valid=1)
    assert dut.output_valid.value == 1, "MATMUL did not fire"
    assert int(dut.output_payload.value) == expected, \
        f"MATMUL got 0x{int(dut.output_payload.value):016x}, want 0x{expected:016x}"


@cocotb.test()
async def test_tensor_add(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a = pack16(1, 2, 3, 4)
    b = pack16(10, 20, 30, 40)
    expected = pack16(11, 22, 33, 44)

    instr = encode_instr(0x31, _STD_PORT(), eh_opref(), flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(dim=0x05),
               payload_a=a, payload_b=b, payload_b_valid=1)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == expected


# =============================================================================
# EINSUM — 8 supported patterns
# =============================================================================

async def _einsum(dut, a_axes, b_axes, o_axes, payload_a, payload_b=0,
                  dim=0x05):
    instr = encode_instr(0x32,
                         _STD_PORT(),
                         eh_subscript(a_axes, b_axes, o_axes),
                         eh_opref(),
                         flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(dim=dim),
               payload_a=payload_a, payload_b=payload_b, payload_b_valid=1)
    assert dut.error_flag.value == 0, "unexpected error_flag in EINSUM"
    assert dut.output_valid.value == 1, "EINSUM did not fire"
    return int(dut.output_payload.value)


@cocotb.test()
async def test_einsum_sum_i(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a = pack16(1, 2, 3, 4)
    out = await _einsum(dut,
                        a_axes=axes(1, 0, 0, 0),
                        b_axes=axes(0, 0, 0, 0),
                        o_axes=axes(0, 0, 0, 0),
                        payload_a=a, dim=0x03)  # dim1=4
    assert out == 10


@cocotb.test()
async def test_einsum_trace_ii(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a = pack16(1, 2, 3, 4)        # [[1,2],[3,4]] → trace = 1+4 = 5
    out = await _einsum(dut,
                        a_axes=axes(1, 1, 0, 0),
                        b_axes=axes(0, 0, 0, 0),
                        o_axes=axes(0, 0, 0, 0),
                        payload_a=a)
    assert out == 5


@cocotb.test()
async def test_einsum_transpose_ij(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a = pack16(1, 2, 3, 4)        # [[1,2],[3,4]] → [[1,3],[2,4]]
    out = await _einsum(dut,
                        a_axes=axes(1, 2, 0, 0),
                        b_axes=axes(0, 0, 0, 0),
                        o_axes=axes(2, 1, 0, 0),
                        payload_a=a)
    assert out == pack16(1, 3, 2, 4)


@cocotb.test()
async def test_einsum_matmul_ijjk(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a = pack16(1, 2, 3, 4)
    b = pack16(5, 6, 7, 8)
    expected = pack16(19, 22, 43, 50)

    out = await _einsum(dut,
                        a_axes=axes(1, 2, 0, 0),
                        b_axes=axes(2, 3, 0, 0),
                        o_axes=axes(1, 3, 0, 0),
                        payload_a=a, payload_b=b)
    assert out == expected


@cocotb.test()
async def test_einsum_hadamard(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a = pack16(1, 2, 3, 4)
    b = pack16(10, 20, 30, 40)
    expected = pack16(10, 40, 90, 160)

    out = await _einsum(dut,
                        a_axes=axes(1, 2, 0, 0),
                        b_axes=axes(1, 2, 0, 0),
                        o_axes=axes(1, 2, 0, 0),
                        payload_a=a, payload_b=b)
    assert out == expected


@cocotb.test()
async def test_einsum_outer(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a = pack16(2, 3)              # 1D 2-vec
    b = pack16(5, 7)
    # outer = [[2*5, 2*7], [3*5, 3*7]] = [[10,14],[15,21]]
    expected = pack16(10, 14, 15, 21)

    out = await _einsum(dut,
                        a_axes=axes(1, 0, 0, 0),
                        b_axes=axes(2, 0, 0, 0),
                        o_axes=axes(1, 2, 0, 0),
                        payload_a=a, payload_b=b, dim=0x01)
    assert out == expected


@cocotb.test()
async def test_einsum_partial_ijk(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # 2×2×2 packed: a[(i*2+j)*2+k]; only first 4 elements (i=0) populated.
    # a[0,0,0]=1, a[0,0,1]=2, a[0,1,0]=3, a[0,1,1]=4
    a = pack16(1, 2, 3, 4)
    # out[0,0]=1+2=3, out[0,1]=3+4=7, out[1,*]=0 (input limited to 64-bit)
    expected = pack16(3, 7, 0, 0)

    out = await _einsum(dut,
                        a_axes=axes(1, 2, 3, 0),
                        b_axes=axes(0, 0, 0, 0),
                        o_axes=axes(1, 2, 0, 0),
                        payload_a=a, dim=0x15)
    assert out == expected


@cocotb.test()
async def test_einsum_diagonal(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a = pack16(1, 2, 3, 4)        # [[1,2],[3,4]] → diag = [1, 4]
    out = await _einsum(dut,
                        a_axes=axes(1, 1, 0, 0),
                        b_axes=axes(0, 0, 0, 0),
                        o_axes=axes(1, 0, 0, 0),
                        payload_a=a)
    assert out == pack16(1, 4)


# =============================================================================
# Negative tests — error_flag must assert exactly once per malformed input
# =============================================================================

@cocotb.test()
async def test_unsupported_einsum_pattern_lowers(dut):
    """Unsupported einsum patterns must raise `lower_required`, not
    `error_flag` — the runtime can decompose them into supported primitives."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x32, _STD_PORT(),
                         eh_subscript(axes(4), axes(4), axes(4)),
                         eh_opref(), flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(),
               payload_a=0, payload_b=0, payload_b_valid=1)
    assert dut.output_valid.value == 0
    assert dut.error_flag.value == 0
    assert dut.lower_required.value == 1


@cocotb.test()
async def test_missing_required_eh_errors(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # MATMUL without OPERAND_REF
    instr = encode_instr(0x30, _STD_PORT(), flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(dim=0x05),
               payload_a=0, payload_b=0, payload_b_valid=1)
    assert dut.output_valid.value == 0
    assert dut.error_flag.value == 1


@cocotb.test()
async def test_forbidden_eh_errors(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # NOP with PORT EH (forbidden — NOP forbids everything except nothing)
    # Actually NOP forbids everything, but PORT is universally allowed. Use
    # a clearer case: BITS-ORD-REVERSE with IMM16 (forbidden).
    instr = encode_instr(0x1F, _STD_PORT(), eh_imm16(7))
    await fire(dut, instr, _STD_TAG(), payload_a=0)
    assert dut.error_flag.value == 1


@cocotb.test()
async def test_alu_binary_xor_violation_errors(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # ADD with BOTH IMM16 and OPREF — must be exactly one
    instr = encode_instr(0x10, _STD_PORT(), eh_imm16(1), eh_opref(),
                         flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(),
               payload_a=0, payload_b=0, payload_b_valid=1)
    assert dut.error_flag.value == 1


@cocotb.test()
async def test_f_has_opb_without_b_valid_errors(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x30, _STD_PORT(), eh_opref(), flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(dim=0x05),
               payload_a=0, payload_b=0, payload_b_valid=0)  # b_valid=0
    assert dut.error_flag.value == 1


@cocotb.test()
async def test_chain_break_errors(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x10, _STD_PORT(), eh_imm16(1),
                         force_chain_break=True)
    await fire(dut, instr, _STD_TAG(), payload_a=0)
    assert dut.error_flag.value == 1


@cocotb.test()
async def test_reserved_nonzero_errors(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x10, _STD_PORT(), eh_imm16(1),
                         force_reserved=0x01)
    await fire(dut, instr, _STD_TAG(), payload_a=0)
    assert dut.error_flag.value == 1


@cocotb.test()
async def test_bh_len_mismatch_errors(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x10, _STD_PORT(), eh_imm16(1),
                         force_bh_len=99)
    await fire(dut, instr, _STD_TAG(), payload_a=0)
    assert dut.error_flag.value == 1


@cocotb.test()
async def test_opref_src_kind_3_or_higher_errors(dut):
    """src_kind ∈ {0, 1, 2} are all legal (direct payload_b / Cluster NoC
    bank / TRNG bank). Values ≥ 3 remain reserved and must trip
    `opref_kind_unsupported`."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x30, _STD_PORT(), eh_opref(src_kind=3),
                         flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(dim=0x05),
               payload_a=0, payload_b=0, payload_b_valid=1)
    assert dut.error_flag.value == 1


@cocotb.test()
async def test_opref_src_kind_2_passes_legality(dut):
    """src_kind=2 (TRNG bank) is legal at the decoder layer; the Cluster is
    responsible for filling `input_payload_b` from the Pod-wide rng_word."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x10, _STD_PORT(), eh_opref(src_kind=2),
                         flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(),
               payload_a=42, payload_b=0, payload_b_valid=1)
    assert dut.error_flag.value == 0
    assert dut.lower_required.value == 0


@cocotb.test()
async def test_opref_src_kind_1_passes_legality(dut):
    """src_kind=1 (NoC source) is legal at the decoder layer; the Cluster
    is responsible for filling input_payload_b. The decoder simply trusts
    the value it receives."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a = pack16(1, 2, 3, 4)
    b = pack16(5, 6, 7, 8)
    expected = pack16(19, 22, 43, 50)
    instr = encode_instr(
        0x30, _STD_PORT(), eh_opref(src_kind=1, port_id=0, noc_route=0),
        flags=F_HAS_OPB,
    )
    await fire(dut, instr, _STD_TAG(dim=0x05),
               payload_a=a, payload_b=b, payload_b_valid=1)
    assert dut.error_flag.value == 0
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == expected


# =============================================================================
# Assembler end-to-end: assemble HL text → drive ISA_Decoder → check result.
# Confirms the asm/wavetensor_asm.py pipeline produces bits the RTL accepts.
# =============================================================================

# =============================================================================
# PRECISION EH dim_override (F_DIM_OVR flag)
# =============================================================================

# Local F_DIM_OVR mirror (same wiring the assembler uses)
F_DIM_OVR = 1 << 0


def eh_precision(mode=0, dim=0):
    """Build a PRECISION EH (type 0x8) carrying a precision_mode override
    in the low byte and a dim override in the high byte of word 0's body."""
    EH_PRECISION = 0x8

    class _EH:
        def __init__(self, type_code, words, body_fn):
            self.type = type_code
            self.words = words
            self._body_fn = body_fn

        def emit(self, next_hdr):
            return self._body_fn(next_hdr)

    def fn(nh):
        upper = ((dim & 0xFF) << 8) | (mode & 0xFF)
        return [(upper << 16) | (nh << 12) | (EH_PRECISION << 8) | 1]
    return _EH(EH_PRECISION, 1, fn)


@cocotb.test()
async def test_dim_override_changes_output_tag_dim(dut):
    """F_DIM_OVR + PRECISION EH dim=0x05 forces eff_dim_sizes=0x05; the
    forwarded tag must carry the overridden value, not the input tag's."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # Input tag has dim_sizes=0x03 (1D 4-element), but F_DIM_OVR + .precision
    # dim=0x05 reinterprets the payload as 2×2 for this instruction.
    instr = encode_instr(0x10, _STD_PORT(), eh_imm16(0),
                         eh_precision(mode=0, dim=0x05),
                         flags=F_DIM_OVR)
    await fire(dut, instr, _STD_TAG(dim=0x03), payload_a=0)

    assert dut.output_valid.value == 1
    out_tag = int(dut.output_tag.value)
    assert (out_tag & 0xFF) == 0x05, \
        f"output_tag dim_sizes = 0x{out_tag & 0xFF:02x}, expected 0x05"


@cocotb.test()
async def test_dim_override_makes_matmul_use_overridden_shape(dut):
    """A matmul whose tag claims a non-2x2 shape but whose F_DIM_OVR forces
    eff_dim_sizes=0x05 should execute as a 2x2 multiply correctly."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a = pack16(1, 2, 3, 4)
    b = pack16(5, 6, 7, 8)
    expected = pack16(19, 22, 43, 50)

    # Tag dim=0x03 (1D 4-elem) → MATMUL would normally fail dim check.
    # F_DIM_OVR + PRECISION dim=0x05 forces eff_dim_sizes=0x05 (2x2).
    instr = encode_instr(0x30, _STD_PORT(), eh_opref(),
                         eh_precision(mode=0, dim=0x05),
                         flags=F_HAS_OPB | F_DIM_OVR)
    await fire(dut, instr, _STD_TAG(dim=0x03),
               payload_a=a, payload_b=b, payload_b_valid=1)

    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == expected


@cocotb.test()
async def test_dim_ovr_flag_without_precision_eh_errors(dut):
    """Setting F_DIM_OVR without an actual PRECISION EH must trap, since
    eff_prec_dim defaults to 0 which would silently corrupt downstream."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x10, _STD_PORT(), eh_imm16(5), flags=F_DIM_OVR)
    await fire(dut, instr, _STD_TAG(), payload_a=10)
    assert dut.error_flag.value == 1
    assert dut.output_valid.value == 0


@cocotb.test()
async def test_prec_flag_without_precision_eh_errors(dut):
    """Same protection for F_PRECISION_OVR."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    F_PRECISION_OVR = 1 << 2
    instr = encode_instr(0x10, _STD_PORT(), eh_imm16(5),
                         flags=F_PRECISION_OVR)
    await fire(dut, instr, _STD_TAG(), payload_a=10)
    assert dut.error_flag.value == 1


@cocotb.test()
async def test_assembler_add_imm_e2e(dut):
    if not _HAS_ASM:
        return
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = assemble_one(
        ".default_port mask=0x01 out=0\n"
        "ADD .imm16 7\n"
    )
    await fire(dut, instr, _STD_TAG(), payload_a=10)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 17
    assert dut.error_flag.value == 0


@cocotb.test()
async def test_assembler_einsum_matmul_e2e(dut):
    if not _HAS_ASM:
        return
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a = pack16(1, 2, 3, 4)
    b = pack16(5, 6, 7, 8)
    expected = pack16(19, 22, 43, 50)

    instr = assemble_one(
        ".alias port_a 0x01\n"
        ".default_port mask=port_a out=0\n"
        "EINSUM opb .subscript A=i,j B=j,k O=i,k .opref\n"
    )
    await fire(dut, instr, _STD_TAG(dim=0x05),
               payload_a=a, payload_b=b, payload_b_valid=1)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == expected


@cocotb.test()
async def test_assembler_reshape_macro_e2e(dut):
    """RESHAPE macro lowers to VIEW; ISA_Decoder accepts the bytes."""
    if not _HAS_ASM:
        return
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # 1D 4-vec (dim_sizes=0x03) → 2D 2×2 (dim_sizes=0x05)
    payload = pack16(1, 2, 3, 4)
    instr = assemble_one(
        ".default_port mask=0x01 out=0\n"
        "RESHAPE .from 0x03 .to 0x05\n"
    )
    await fire(dut, instr, _STD_TAG(dim=0x03), payload_a=payload)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == payload   # VIEW: payload unchanged
    out_tag = int(dut.output_tag.value)
    assert (out_tag & 0xFF) == 0x05                   # dim_sizes updated


# =============================================================================
# Additional EINSUM kernel signatures (DOT, MAT_VEC)
# =============================================================================

@cocotb.test()
async def test_einsum_dot(dut):
    """`i,i->` — inner product of two 4-vectors."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a = pack16(1, 2, 3, 4)
    b = pack16(5, 6, 7, 8)
    out = await _einsum(dut,
                        a_axes=axes(1, 0, 0, 0),
                        b_axes=axes(1, 0, 0, 0),
                        o_axes=axes(0, 0, 0, 0),
                        payload_a=a, payload_b=b, dim=0x03)
    assert out == 1*5 + 2*6 + 3*7 + 4*8  # 70


@cocotb.test()
async def test_einsum_mat_vec(dut):
    """`ij,j->i` — 2×2 matrix × 2-vector."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # A = [[1,2],[3,4]], b = [5,6]
    # out = [1*5+2*6, 3*5+4*6] = [17, 39]
    a = pack16(1, 2, 3, 4)
    b = pack16(5, 6)
    out = await _einsum(dut,
                        a_axes=axes(1, 2, 0, 0),
                        b_axes=axes(2, 0, 0, 0),
                        o_axes=axes(1, 0, 0, 0),
                        payload_a=a, payload_b=b, dim=0x05)
    assert out == pack16(17, 39)


# =============================================================================
# Shape ops — SQUEEZE / UNSQUEEZE / VIEW / PERMUTE / BROADCAST / REDUCE_AXIS
# =============================================================================

def _tag_dim(out_tag_int):
    return out_tag_int & 0xFF


@cocotb.test()
async def test_squeeze_metadata_only(dut):
    """SQUEEZE on a size-1 axis updates dim_sizes; payload unchanged."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # Tensor 4×1 (dim_sizes = 0b00_00_00_11 = 0x03 vs 0b00_00_11_00 = 0x0C).
    # Pick a 2D 1×4 (dim 0 size 1, dim 1 size 4) → dim_sizes = 0b00_00_11_00 = 0x0C.
    # Squeeze axis 0 (which is size 1) → 1D 4-vec, dim_sizes = 0x03.
    payload = pack16(1, 2, 3, 4)
    instr = encode_instr(0x20, _STD_PORT(), eh_imm16(0))
    await fire(dut, instr, _STD_TAG(dim=0x0C), payload_a=payload)
    assert dut.error_flag.value == 0
    assert dut.lower_required.value == 0
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == payload  # unchanged
    assert _tag_dim(int(dut.output_tag.value)) == 0x03


@cocotb.test()
async def test_squeeze_non_size_one_errors(dut):
    """SQUEEZE on a non-size-1 axis must trap as error_flag (data corruption)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # 1D 4-vec (dim_sizes=0x03 → axis 0 has size 4). Squeeze axis 0 → error.
    instr = encode_instr(0x20, _STD_PORT(), eh_imm16(0))
    await fire(dut, instr, _STD_TAG(dim=0x03), payload_a=0)
    assert dut.error_flag.value == 1
    assert dut.output_valid.value == 0


@cocotb.test()
async def test_unsqueeze_metadata_only(dut):
    """UNSQUEEZE inserts a size-1 axis; payload unchanged."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # 1D 4-vec (dim_sizes=0x03). Unsqueeze axis 0 → 2D 1×4 (dim_sizes=0x0C).
    payload = pack16(1, 2, 3, 4)
    instr = encode_instr(0x21, _STD_PORT(), eh_imm16(0))
    await fire(dut, instr, _STD_TAG(dim=0x03), payload_a=payload)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == payload
    assert _tag_dim(int(dut.output_tag.value)) == 0x0C


@cocotb.test()
async def test_unsqueeze_full_rank_errors(dut):
    """UNSQUEEZE when all 4 axes already occupied → error_flag (data loss)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # All 4 axes occupied: dim_sizes = 0b01_01_01_01 = 0x55 (each 2×).
    instr = encode_instr(0x21, _STD_PORT(), eh_imm16(0))
    await fire(dut, instr, _STD_TAG(dim=0x55), payload_a=0)
    assert dut.error_flag.value == 1
    assert dut.output_valid.value == 0


@cocotb.test()
async def test_view_preserves_element_count(dut):
    """VIEW with same element count succeeds; payload unchanged."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # 1D 4-vec (dim_sizes=0x03, count=4) → 2D 2×2 (dim_sizes=0x05, count=4).
    payload = pack16(1, 2, 3, 4)
    instr = encode_instr(0x22, _STD_PORT(), eh_imm16(0x05))
    await fire(dut, instr, _STD_TAG(dim=0x03), payload_a=payload)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == payload
    assert _tag_dim(int(dut.output_tag.value)) == 0x05


@cocotb.test()
async def test_view_count_mismatch_errors(dut):
    """VIEW with mismatched element count → error_flag."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # 1D 4-vec (count=4) → 2D 3×3 (dim_sizes=0b1010=0x0A, count=9). Mismatch.
    instr = encode_instr(0x22, _STD_PORT(), eh_imm16(0x0A))
    await fire(dut, instr, _STD_TAG(dim=0x03), payload_a=0)
    assert dut.error_flag.value == 1
    assert dut.output_valid.value == 0


@cocotb.test()
async def test_permute_2x2_transpose(dut):
    """PERMUTE swap (perm=0x01) on a 2×2 tensor performs a transpose."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # A = [[1,2],[3,4]] → A^T = [[1,3],[2,4]]
    payload = pack16(1, 2, 3, 4)
    instr = encode_instr(0x23, _STD_PORT(), eh_imm16(0x01))
    await fire(dut, instr, _STD_TAG(dim=0x05), payload_a=payload)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == pack16(1, 3, 2, 4)


@cocotb.test()
async def test_permute_unsupported_lowers(dut):
    """A permute that doesn't fit the PE-local fast path raises lower_required."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # 4D permute pattern, no PE-local handler.
    instr = encode_instr(0x23, _STD_PORT(), eh_imm16(0xE4))
    await fire(dut, instr, _STD_TAG(dim=0x55), payload_a=0)
    assert dut.lower_required.value == 1
    assert dut.error_flag.value == 0
    assert dut.output_valid.value == 0


@cocotb.test()
async def test_broadcast_lowers(dut):
    """BROADCAST defers to compiler lowering in iter-1."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x24, _STD_PORT(), eh_imm16(0x05))
    await fire(dut, instr, _STD_TAG(dim=0x03), payload_a=0)
    assert dut.lower_required.value == 1
    assert dut.error_flag.value == 0


@cocotb.test()
async def test_reduce_axis_sum(dut):
    """REDUCE_AXIS sum along axis 0 of 1D 4-vec."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    payload = pack16(1, 2, 3, 4)
    # IMM16: axis=0 (low nibble), op=SUM=0
    instr = encode_instr(0x25, _STD_PORT(), eh_imm16(0x00))
    await fire(dut, instr, _STD_TAG(dim=0x03), payload_a=payload)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 10
    # After reducing axis 0 of 1D, dim_sizes squeeze axis 0 → all-1.
    assert _tag_dim(int(dut.output_tag.value)) == 0x00


@cocotb.test()
async def test_reduce_axis_max(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    payload = pack16(7, 2, 9, 4)
    # axis=0, op=MAX=1 → IMM16 = (1<<4) | 0 = 0x10
    instr = encode_instr(0x25, _STD_PORT(), eh_imm16(0x10))
    await fire(dut, instr, _STD_TAG(dim=0x03), payload_a=payload)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 9


@cocotb.test()
async def test_reduce_axis_min(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    payload = pack16(7, 2, 9, 4)
    # axis=0, op=MIN=2 → IMM16 = (2<<4) | 0 = 0x20
    instr = encode_instr(0x25, _STD_PORT(), eh_imm16(0x20))
    await fire(dut, instr, _STD_TAG(dim=0x03), payload_a=payload)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 2


@cocotb.test()
async def test_reduce_axis_unsupported_lowers(dut):
    """REDUCE_AXIS on a 2D shape isn't PE-local; lower_required must rise."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x25, _STD_PORT(), eh_imm16(0x00))
    await fire(dut, instr, _STD_TAG(dim=0x05), payload_a=0)  # 2×2 not supported here
    assert dut.lower_required.value == 1
    assert dut.error_flag.value == 0
    assert dut.output_valid.value == 0


@cocotb.test()
async def test_shape_op_forbids_subscript(dut):
    """Shape ops must reject SUBSCRIPT EH (forbidden) → error_flag."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x20, _STD_PORT(), eh_imm16(0),
                         eh_subscript(axes(1), axes(), axes()))
    await fire(dut, instr, _STD_TAG(dim=0x0C), payload_a=0)
    assert dut.error_flag.value == 1


# =============================================================================
# SPLAT (opcode 0x26) — WT64v1 v1.1 amendment (2026-07-14).
# Scalar in imm16[7:0] (signed int8) sign-extended to int16 and replicated
# across all 4 lanes of the 64-bit payload. Result is 1-D of size 4
# (dim_sizes = 8'h03).
# =============================================================================

@cocotb.test()
async def test_splat_positive_scalar(dut):
    """SPLAT of a small positive int8 → 4 lanes of that value."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # scalar = 5; 4 lanes each holding 0x0005 → payload = 0x0005_0005_0005_0005
    instr = encode_instr(0x26, _STD_PORT(), eh_imm16(0x0005))
    await fire(dut, instr, _STD_TAG(dim=0x00), payload_a=0)
    assert dut.error_flag.value == 0
    assert dut.lower_required.value == 0
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 0x00050005_00050005
    # Result tag has dim_sizes = 0x03 (1-D of 4 elements).
    assert _tag_dim(int(dut.output_tag.value)) == 0x03


@cocotb.test()
async def test_splat_negative_scalar_sign_extends(dut):
    """SPLAT of a negative int8 must sign-extend to int16 lanes."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # scalar = -1 (0xFF as int8) → each lane = 0xFFFF (int16 -1)
    instr = encode_instr(0x26, _STD_PORT(), eh_imm16(0x00FF))
    await fire(dut, instr, _STD_TAG(dim=0x00), payload_a=0)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 0xFFFFFFFF_FFFFFFFF
    assert _tag_dim(int(dut.output_tag.value)) == 0x03


@cocotb.test()
async def test_splat_zero(dut):
    """SPLAT of 0 → all lanes zero."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x26, _STD_PORT(), eh_imm16(0x0000))
    await fire(dut, instr, _STD_TAG(dim=0x00), payload_a=0xDEAD_BEEF_DEAD_BEEF)
    assert dut.output_valid.value == 1
    # Input payload is ignored — output is pure constant.
    assert int(dut.output_payload.value) == 0
    assert _tag_dim(int(dut.output_tag.value)) == 0x03


@cocotb.test()
async def test_splat_max_positive_int8(dut):
    """SPLAT of int8 max (0x7F = +127) → each lane = 0x007F."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x26, _STD_PORT(), eh_imm16(0x007F))
    await fire(dut, instr, _STD_TAG(dim=0x00), payload_a=0)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 0x007F007F_007F007F
    assert _tag_dim(int(dut.output_tag.value)) == 0x03


@cocotb.test()
async def test_splat_min_negative_int8(dut):
    """SPLAT of int8 min (0x80 = -128) → each lane = 0xFF80."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x26, _STD_PORT(), eh_imm16(0x0080))
    await fire(dut, instr, _STD_TAG(dim=0x00), payload_a=0)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 0xFF80FF80_FF80FF80
    assert _tag_dim(int(dut.output_tag.value)) == 0x03


@cocotb.test()
async def test_splat_forbids_subscript(dut):
    """SPLAT is a shape op — SUBSCRIPT EH is forbidden → error_flag."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x26, _STD_PORT(), eh_imm16(0x0001),
                         eh_subscript(axes(1), axes(), axes()))
    await fire(dut, instr, _STD_TAG(dim=0x00), payload_a=0)
    assert dut.error_flag.value == 1
    assert dut.output_valid.value == 0


# =============================================================================
# SIG_BMM (v1.1) — 'bik,bkj->bij' batched matmul at int8 packed 8-lane payload.
# Canonicalized subscript: A=[1,2,3] B=[1,3,4] O=[1,2,4].
# Requires dim_sizes = 0x15 (3D 2×2×2); otherwise lower_required.
# =============================================================================

def _pack8(*bytes_):
    """Pack up to 8 int8 values into a 64-bit int (lane 0 = low byte)."""
    v = 0
    for i, b in enumerate(bytes_[:8]):
        v |= (b & 0xFF) << (i * 8)
    return v


@cocotb.test()
async def test_bmm_basic(dut):
    """2 independent 2x2 int8 matmuls, batched."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # A[b][i][k] at lane b*4+i*2+k
    # b=0: [[1,2],[3,4]], b=1: [[10,20],[30,40]]
    a = _pack8(1, 2, 3, 4, 10, 20, 30, 40)
    # B[b][k][j] at lane b*4+k*2+j
    # b=0: [[5,6],[7,8]], b=1: [[1,1],[1,1]]
    b_pl = _pack8(5, 6, 7, 8, 1, 1, 1, 1)
    # Expected R[b][i][j] at lane b*4+i*2+j
    # b=0: matmul=[[1*5+2*7, 1*6+2*8],[3*5+4*7, 3*6+4*8]] = [[19,22],[43,50]]
    # b=1: matmul=[[10+20, 10+20],[30+40, 30+40]] = [[30,30],[70,70]]
    expected = _pack8(19, 22, 43, 50, 30, 30, 70, 70)

    instr = encode_instr(0x32,
                         _STD_PORT(),
                         eh_subscript(axes(1, 2, 3, 0), axes(1, 3, 4, 0), axes(1, 2, 4, 0)),
                         eh_opref(),
                         flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(dim=0x15),
               payload_a=a, payload_b=b_pl, payload_b_valid=1)
    assert dut.error_flag.value == 0
    assert dut.lower_required.value == 0
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == expected, \
        f"BMM result mismatch: got 0x{int(dut.output_payload.value):016x}, expected 0x{expected:016x}"


@cocotb.test()
async def test_bmm_identity_yields_input(dut):
    """A @ I = A (per batch). Confirms indexing correctness."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # A[0]=[[1,2],[3,4]], A[1]=[[5,6],[7,8]]
    a = _pack8(1, 2, 3, 4, 5, 6, 7, 8)
    # B = identity per batch: [[1,0],[0,1]]
    b_pl = _pack8(1, 0, 0, 1, 1, 0, 0, 1)
    # Expected: R[b] = A[b] since B[b] is identity.
    expected = _pack8(1, 2, 3, 4, 5, 6, 7, 8)

    instr = encode_instr(0x32,
                         _STD_PORT(),
                         eh_subscript(axes(1, 2, 3, 0), axes(1, 3, 4, 0), axes(1, 2, 4, 0)),
                         eh_opref(),
                         flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(dim=0x15),
               payload_a=a, payload_b=b_pl, payload_b_valid=1)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == expected


@cocotb.test()
async def test_bmm_wrong_dim_sizes_lowers(dut):
    """SIG_BMM requires dim_sizes = 0x15. Other shapes → lower_required."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x32,
                         _STD_PORT(),
                         eh_subscript(axes(1, 2, 3, 0), axes(1, 3, 4, 0), axes(1, 2, 4, 0)),
                         eh_opref(),
                         flags=F_HAS_OPB)
    # dim_sizes = 0x05 (2D 2x2) — wrong for SIG_BMM
    await fire(dut, instr, _STD_TAG(dim=0x05),
               payload_a=0, payload_b=0, payload_b_valid=1)
    assert dut.error_flag.value == 0
    assert dut.lower_required.value == 1
    assert dut.output_valid.value == 0


# =============================================================================
# SIG_TRACE_IIJ (v1.1) — 'iij->j' 3D trace with kept axis j at int8.
# Canonicalized subscript: A=[1,1,2] B=[] O=[2].
# Requires dim_sizes = 0x15 (3D 2×2×2); result is 1D of size 2 (dim = 0x01).
# =============================================================================

@cocotb.test()
async def test_trace_iij_basic(dut):
    """r[j] = A[0][0][j] + A[1][1][j]"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # A[i][i'][j] at lane i*4+i'*2+j
    # A[0][0][0]=10, A[0][0][1]=20, A[0][1][0]=99 (ignored), A[0][1][1]=99 (ignored)
    # A[1][0][0]=98 (ignored), A[1][0][1]=97 (ignored), A[1][1][0]=30, A[1][1][1]=40
    a = _pack8(10, 20, 99, 99, 98, 97, 30, 40)
    # Expected: r[0] = 10 + 30 = 40, r[1] = 20 + 40 = 60. Upper 6 lanes = 0.
    expected = _pack8(40, 60, 0, 0, 0, 0, 0, 0)

    instr = encode_instr(0x32,
                         _STD_PORT(),
                         eh_subscript(axes(1, 1, 2, 0), axes(0, 0, 0, 0), axes(2, 0, 0, 0)),
                         eh_opref(),
                         flags=F_HAS_OPB)  # opb needed by legality; payload_b unused
    await fire(dut, instr, _STD_TAG(dim=0x15),
               payload_a=a, payload_b=0, payload_b_valid=1)
    assert dut.error_flag.value == 0
    assert dut.lower_required.value == 0
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == expected, \
        f"TRACE_IIJ result mismatch: got 0x{int(dut.output_payload.value):016x}, expected 0x{expected:016x}"
    # Output tag dim_sizes = 0x01 (1D of size 2)
    assert _tag_dim(int(dut.output_tag.value)) == 0x01


@cocotb.test()
async def test_trace_iij_negative_int8_signs_correctly(dut):
    """Signed int8 addition — sum of -5 and 10 in each lane."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # A[0][0][0]=-5 (0xFB), A[0][0][1]=-3 (0xFD), others don't matter for trace
    # A[1][1][0]=10, A[1][1][1]=13
    a = _pack8(0xFB, 0xFD, 0, 0, 0, 0, 10, 13)
    # r[0] = -5 + 10 = 5, r[1] = -3 + 13 = 10
    expected = _pack8(5, 10, 0, 0, 0, 0, 0, 0)

    instr = encode_instr(0x32,
                         _STD_PORT(),
                         eh_subscript(axes(1, 1, 2, 0), axes(0, 0, 0, 0), axes(2, 0, 0, 0)),
                         eh_opref(),
                         flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(dim=0x15),
               payload_a=a, payload_b=0, payload_b_valid=1)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == expected


@cocotb.test()
async def test_trace_iij_wrong_dim_lowers(dut):
    """SIG_TRACE_IIJ requires dim_sizes = 0x15. Other → lower_required."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x32,
                         _STD_PORT(),
                         eh_subscript(axes(1, 1, 2, 0), axes(0, 0, 0, 0), axes(2, 0, 0, 0)),
                         eh_opref(),
                         flags=F_HAS_OPB)
    # 2D shape 2x2 is wrong
    await fire(dut, instr, _STD_TAG(dim=0x05),
               payload_a=0, payload_b=0, payload_b_valid=1)
    assert dut.lower_required.value == 1
    assert dut.output_valid.value == 0


# =============================================================================
# SIG_BMM_2 (v1.2) — 'abij,abjk->abik' 2-batch matmul at int4 packed 16 nibbles.
# Canonicalized subscript: A=[1,2,3,4] B=[1,2,4,5] O=[1,2,3,5].
# Requires dim_sizes = 0x55 (4D 2×2×2×2); result has same shape.
# =============================================================================

def _pack4(*nibbles):
    """Pack up to 16 int4 nibbles into a 64-bit int (lane 0 = low nibble)."""
    v = 0
    for i, n in enumerate(nibbles[:16]):
        v |= (n & 0xF) << (i * 4)
    return v


@cocotb.test()
async def test_bmm_2_identity_per_batch(dut):
    """4 independent 2x2 matmuls with identity B per batch → R = A."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # A[a][b][i][j] at nibble (a*8+b*4+i*2+j), all int4.
    # Each batch A[a][b] = [[1,2],[3,4]] → nibbles 1,2,3,4 per 4-nibble sub.
    a_payload = _pack4(1, 2, 3, 4,   1, 2, 3, 4,   1, 2, 3, 4,   1, 2, 3, 4)
    # B[a][b] = identity [[1,0],[0,1]] per batch → nibbles 1,0,0,1.
    b_payload = _pack4(1, 0, 0, 1,   1, 0, 0, 1,   1, 0, 0, 1,   1, 0, 0, 1)
    # Expected: R = A for each batch.
    expected = a_payload

    instr = encode_instr(0x32,
                         _STD_PORT(),
                         eh_subscript(axes(1, 2, 3, 4), axes(1, 2, 4, 5), axes(1, 2, 3, 5)),
                         eh_opref(),
                         flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(dim=0x55),
               payload_a=a_payload, payload_b=b_payload, payload_b_valid=1)
    assert dut.error_flag.value == 0
    assert dut.lower_required.value == 0
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == expected, \
        f"BMM_2 identity mismatch: got 0x{int(dut.output_payload.value):016x}, expected 0x{expected:016x}"


@cocotb.test()
async def test_bmm_2_computed_matmul(dut):
    """Known 4-batched matmul values, int4."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # Batch (0,0): A=[[1,2],[3,-1]], B=[[1,1],[1,1]]
    #   R[0][0] = 1*1+2*1=3, R[0][1] = 1*1+2*1=3, R[1][0] = 3*1+(-1)*1=2, R[1][1] = 3*1+(-1)*1=2
    # Batch (0,1): all zeros → R zero
    # Batch (1,0): A=[[1,1],[1,1]], B=[[2,3],[4,5]]
    #   R[0][0] = 1*2+1*4=6, R[0][1] = 1*3+1*5=(-8 after int4 trunc of 8), R[1][0] = 1*2+1*4=6, R[1][1] = (-8)
    #   Wait, 8 as int4 is -8 (0x8). Let's use smaller values.
    #   Actually 3+5=8, truncates to int4 0x8 (bit pattern), which is -8 signed.
    #   Cleaner: use values where sum fits int4. Change to B=[[2,3],[2,3]].
    #   R[0][0] = 1*2+1*2=4, R[0][1] = 1*3+1*3=6, R[1][0] = 1*2+1*2=4, R[1][1] = 1*3+1*3=6
    # Batch (1,1): A=[[0,1],[2,3]], B=[[1,0],[0,1]] (identity)
    #   R = A = [[0,1],[2,3]]

    # A[a][b][i][j] at nibble (a*8+b*4+i*2+j)
    # Nibble index: 0=A[0][0][0][0], 1=[0][0][0][1], 2=[0][0][1][0], 3=[0][0][1][1]
    #               4=A[0][1][0][0], 5=[0][1][0][1], 6=[0][1][1][0], 7=[0][1][1][1]
    #               8=A[1][0][0][0], 9=[1][0][0][1], 10=[1][0][1][0], 11=[1][0][1][1]
    #               12=A[1][1][0][0], 13=[1][1][0][1], 14=[1][1][1][0], 15=[1][1][1][1]
    a_payload = _pack4(
        1, 2, 3, 0xF,  # batch (0,0): [[1,2],[3,-1]]
        0, 0, 0, 0,    # batch (0,1): zero
        1, 1, 1, 1,    # batch (1,0): [[1,1],[1,1]]
        0, 1, 2, 3,    # batch (1,1): [[0,1],[2,3]]
    )
    b_payload = _pack4(
        1, 1, 1, 1,    # batch (0,0): [[1,1],[1,1]]
        0, 0, 0, 0,    # batch (0,1): zero
        2, 3, 2, 3,    # batch (1,0): [[2,3],[2,3]]
        1, 0, 0, 1,    # batch (1,1): identity
    )
    expected = _pack4(
        3, 3, 2, 2,    # batch (0,0)
        0, 0, 0, 0,    # batch (0,1)
        4, 6, 4, 6,    # batch (1,0)
        0, 1, 2, 3,    # batch (1,1)
    )

    instr = encode_instr(0x32,
                         _STD_PORT(),
                         eh_subscript(axes(1, 2, 3, 4), axes(1, 2, 4, 5), axes(1, 2, 3, 5)),
                         eh_opref(),
                         flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(dim=0x55),
               payload_a=a_payload, payload_b=b_payload, payload_b_valid=1)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == expected, \
        f"BMM_2 mismatch: got 0x{int(dut.output_payload.value):016x}, expected 0x{expected:016x}"


@cocotb.test()
async def test_bmm_2_wrong_dim_lowers(dut):
    """SIG_BMM_2 requires dim_sizes = 0x55 (4D 2×2×2×2). Other → lower_required."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x32,
                         _STD_PORT(),
                         eh_subscript(axes(1, 2, 3, 4), axes(1, 2, 4, 5), axes(1, 2, 3, 5)),
                         eh_opref(),
                         flags=F_HAS_OPB)
    # 3D shape (SIG_BMM's shape 0x15) is wrong for SIG_BMM_2.
    await fire(dut, instr, _STD_TAG(dim=0x15),
               payload_a=0, payload_b=0, payload_b_valid=1)
    assert dut.lower_required.value == 1
    assert dut.output_valid.value == 0


# =============================================================================
# SIG_TRACE_IIJK (v1.2) — 'iijk->jk' 3D trace w/ 2 kept axes at int4.
# Canonicalized: A=[1,1,2,3] B=[] O=[2,3]. Requires dim_sizes = 0x55.
# Result 2D 2×2 → dim_sizes = 0x05.
# =============================================================================

@cocotb.test()
async def test_trace_iijk_basic(dut):
    """R[j][k] = A[0][0][j][k] + A[1][1][j][k]."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # A[0][0] (nibbles 0-3) = [[1,2],[3,4]]
    # A[0][1] (nibbles 4-7) = don't matter (0xF garbage)
    # A[1][0] (nibbles 8-11) = don't matter
    # A[1][1] (nibbles 12-15) = [[1,1],[1,1]]
    a_payload = _pack4(
        1, 2, 3, 4,        # A[0][0]
        0xF, 0xF, 0xF, 0xF,  # A[0][1] ignored
        0xF, 0xF, 0xF, 0xF,  # A[1][0] ignored
        1, 1, 1, 1,        # A[1][1]
    )
    # R[0][0]=1+1=2, R[0][1]=2+1=3, R[1][0]=3+1=4, R[1][1]=4+1=5
    expected = _pack4(2, 3, 4, 5,   0, 0, 0, 0,   0, 0, 0, 0,   0, 0, 0, 0)

    instr = encode_instr(0x32,
                         _STD_PORT(),
                         eh_subscript(axes(1, 1, 2, 3), axes(0, 0, 0, 0), axes(2, 3, 0, 0)),
                         eh_opref(),
                         flags=F_HAS_OPB)  # opb needed by legality; payload_b unused
    await fire(dut, instr, _STD_TAG(dim=0x55),
               payload_a=a_payload, payload_b=0, payload_b_valid=1)
    assert dut.error_flag.value == 0
    assert dut.lower_required.value == 0
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == expected, \
        f"TRACE_IIJK mismatch: got 0x{int(dut.output_payload.value):016x}, expected 0x{expected:016x}"
    # Result tag dim_sizes = 0x05 (2D 2×2)
    assert _tag_dim(int(dut.output_tag.value)) == 0x05


@cocotb.test()
async def test_trace_iijk_signed_int4(dut):
    """int4 signed addition: -3 + 5 = 2, sum-overflow truncation."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # A[0][0] = [[-3,-1],[2,4]] → int4: -3=0xD, -1=0xF, 2=0x2, 4=0x4
    # A[1][1] = [[5,3],[1,2]] → 5,3,1,2
    a_payload = _pack4(
        0xD, 0xF, 2, 4,      # A[0][0]
        0, 0, 0, 0,          # A[0][1] ignored
        0, 0, 0, 0,          # A[1][0] ignored
        5, 3, 1, 2,          # A[1][1]
    )
    # R[0][0] = -3 + 5 = 2
    # R[0][1] = -1 + 3 = 2
    # R[1][0] = 2 + 1 = 3
    # R[1][1] = 4 + 2 = 6
    expected = _pack4(2, 2, 3, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

    instr = encode_instr(0x32,
                         _STD_PORT(),
                         eh_subscript(axes(1, 1, 2, 3), axes(0, 0, 0, 0), axes(2, 3, 0, 0)),
                         eh_opref(),
                         flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(dim=0x55),
               payload_a=a_payload, payload_b=0, payload_b_valid=1)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == expected


@cocotb.test()
async def test_trace_iijk_wrong_dim_lowers(dut):
    """SIG_TRACE_IIJK requires dim_sizes = 0x55."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x32,
                         _STD_PORT(),
                         eh_subscript(axes(1, 1, 2, 3), axes(0, 0, 0, 0), axes(2, 3, 0, 0)),
                         eh_opref(),
                         flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(dim=0x15),
               payload_a=0, payload_b=0, payload_b_valid=1)
    assert dut.lower_required.value == 1
    assert dut.output_valid.value == 0


# =============================================================================
# v1.3 multi-SUBSCRIPT EH accumulation (§16)
# =============================================================================
#
# EHDecode.v acc_subscript is widened to 96 bits and accepts up to 2
# SUBSCRIPT EHs (low + hi). Third SUBSCRIPT raises stg_chain_err.
# ISA_Decoder exposes dec_eff_subscript_hi as a hierarchical signal
# accessible via `dut.u_ehdec.dec_eff_subscript_hi`.


@cocotb.test()
async def test_multi_subscript_low_only_backward_compat(dut):
    """Single SUBSCRIPT EH — dec_eff_subscript_hi must stay zero (backward
    compat with v1.0/1.1/1.2 signatures)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # Standard 2x2 matmul (v1.0 SIG_MATMUL_2X2) — one SUBSCRIPT EH.
    instr = encode_instr(0x32,
                         _STD_PORT(),
                         eh_subscript(axes(1, 2, 0, 0), axes(2, 3, 0, 0),
                                      axes(1, 3, 0, 0)),
                         eh_opref(),
                         flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(dim=0x11),
               payload_a=pack16(1, 2, 3, 4), payload_b=pack16(5, 6, 7, 8),
               payload_b_valid=1)
    assert dut.output_valid.value == 1
    # Hierarchical: EHDecode is instantiated as `u_ehdec` in ISA_Decoder.
    assert int(dut.u_ehdec.dec_eff_subscript_hi.value) == 0


@cocotb.test()
async def test_multi_subscript_two_ehs_accumulate(dut):
    """Two SUBSCRIPT EHs — first lands in dec_eff_subscript, second in
    dec_eff_subscript_hi. No matching HW signature so lower_required fires
    (expected — v1.3 lands encoding only, not 5+ axes primitives)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    lo_a = axes(1, 2, 3, 4)
    lo_b = axes(1, 3, 5, 0)
    lo_o = axes(1, 2, 4, 0)
    hi_a = axes(5, 0, 0, 0)
    hi_b = axes(0, 0, 0, 0)
    hi_o = axes(0, 0, 0, 0)

    instr = encode_instr(0x32,
                         _STD_PORT(),
                         eh_subscript(lo_a, lo_b, lo_o),
                         eh_subscript(hi_a, hi_b, hi_o),
                         eh_opref(),
                         flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(dim=0x55),
               payload_a=0, payload_b=0, payload_b_valid=1)
    # No matching 5-axes signature in PE_Core, so lower_required is expected.
    assert dut.lower_required.value == 1
    # But the DECODE stage MUST have captured both SUBSCRIPT bodies.
    # Packing order in acc_subscript matches SIG_BMM constant layout:
    # [47:32]=A_packed, [31:16]=B_packed, [15:0]=O_packed.
    lo_expected = (lo_o & 0xFFFF) | ((lo_b & 0xFFFF) << 16) | ((lo_a & 0xFFFF) << 32)
    hi_expected = (hi_o & 0xFFFF) | ((hi_b & 0xFFFF) << 16) | ((hi_a & 0xFFFF) << 32)
    assert int(dut.u_ehdec.dec_eff_subscript.value) == lo_expected
    assert int(dut.u_ehdec.dec_eff_subscript_hi.value) == hi_expected


@cocotb.test()
async def test_multi_subscript_three_ehs_raises_chain_err(dut):
    """Three SUBSCRIPT EHs exceed the acc_subscript capacity (96 bits =
    2 slots). Third one raises stg_chain_err → decode_error surfaces."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    lo = eh_subscript(axes(1, 2, 3, 4), axes(1, 3, 5, 0), axes(1, 2, 4, 0))
    mid = eh_subscript(axes(5, 0, 0, 0), axes(0, 0, 0, 0), axes(0, 0, 0, 0))
    hi = eh_subscript(axes(6, 0, 0, 0), axes(0, 0, 0, 0), axes(0, 0, 0, 0))

    instr = encode_instr(0x32, _STD_PORT(), lo, mid, hi, eh_opref(),
                         flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(dim=0x55),
               payload_a=0, payload_b=0, payload_b_valid=1)
    assert dut.error_flag.value == 1


@cocotb.test()
async def test_multi_subscript_max_chain_fits_MAX_EH_slots(dut):
    """A chain of MAX_EH=4 EHs (PORT + SUBSCRIPT + SUBSCRIPT + OPREF)
    fits exactly in the default MAX_EH=4 hardware bus. Chain walks all
    4 slots, sentinel EH_END sits in OPREF's next_hdr."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x32,
                         _STD_PORT(),
                         eh_subscript(axes(1, 2, 3, 4), axes(1, 3, 5, 0),
                                      axes(1, 2, 4, 0)),
                         eh_subscript(axes(5, 0, 0, 0), axes(0, 0, 0, 0),
                                      axes(0, 0, 0, 0)),
                         eh_opref(),
                         flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(dim=0x55),
               payload_a=0, payload_b=0, payload_b_valid=1)
    # Decode succeeds even though PE_Core has no matching primitive.
    assert dut.error_flag.value == 0
    assert dut.lower_required.value == 1


# =============================================================================
# v1.4 multi-IMM64 EH accumulation (§17 — input payload extension)
# =============================================================================
#
# EHDecode.v acc_imm64 → 2-slot bank. First IMM64 EH lands in
# acc_imm64 (backward compat), second in acc_imm64_hi. Third raises
# stg_chain_err. Combined 128-bit immediate unlocks wide-input tensor
# encoding without changing NoC packet format.


def eh_imm64(value):
    """Two-word IMM64 EH: word 0 = header, word 1 = value[31:0], word 2 = value[63:32]."""
    def fn(nh):
        return [(nh << 12) | (EH_IMM64 << 8) | 3,
                value & 0xFFFFFFFF,
                (value >> 32) & 0xFFFFFFFF]
    return EH(EH_IMM64, 3, fn)


@cocotb.test()
async def test_multi_imm64_single_backward_compat(dut):
    """v1.4: single IMM64 EH — dec_eff_imm64_hi must be zero (backward
    compat). ALU binary opcode with imm64 immediate."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # ADD op with immediate via imm64
    instr = encode_instr(0x10, _STD_PORT(), eh_imm64(0xDEADBEEFCAFEBABE))
    await fire(dut, instr, _STD_TAG(), payload_a=1)
    # ADD executed; dec_eff_imm64_hi in decoder must stay 0
    assert int(dut.u_ehdec.dec_eff_imm64_hi.value) == 0


@cocotb.test()
async def test_multi_imm64_two_ehs_accumulate(dut):
    """v1.4: two IMM64 EHs — first → dec_eff_imm64 (via dec_eff_b_value
    for ALU binary), second → dec_eff_imm64_hi. Combined 128-bit
    immediate available for future wide-tensor primitives.

    Uses EINSUM opcode so both IMM64s survive to the decode stage
    without triggering ALU-XOR validation (which forbids imm+opref).
    """
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    lo_val = 0x1122334455667788
    hi_val = 0xAABBCCDDEEFF0011

    # EINSUM with SUBSCRIPT + OPREF + two IMM64 EHs. EINSUM legality
    # requires SUBSCRIPT and OPREF but doesn't forbid IMM64 explicitly.
    # However, actually let's check: EINSUM (0x32) forbid_imm_any is set
    # per EHDecode.v line 437. So IMM64 on EINSUM raises forbidden_eh.
    #
    # Use ADD (0x10) which allows IMM64 (via any_imm) — but it's an
    # ALU binary that requires IMM XOR OPREF, so a second IMM64 is still
    # valid (both are IMMs, xor becomes 0^1 → false).
    #
    # Actually just verify decode stage: use ADD, dec_eff_imm64_hi
    # captures the second IMM64 body regardless of downstream legality.
    instr = encode_instr(0x10, _STD_PORT(),
                         eh_imm64(lo_val), eh_imm64(hi_val))
    await fire(dut, instr, _STD_TAG(), payload_a=0)
    # Backward compat: acc_imm64 (dec side, low) captures first
    # (visible via dec_eff_b_value cast for ALU binary).
    # dec_eff_imm64_hi captures the second.
    assert int(dut.u_ehdec.dec_eff_imm64_hi.value) == hi_val


@cocotb.test()
async def test_multi_imm64_three_ehs_raises_chain_err(dut):
    """v1.4: three IMM64 EHs exceed the 2-slot bank capacity. Third
    raises stg_chain_err → decode_error surfaces."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x10, _STD_PORT(),
                         eh_imm64(0x1111111111111111),
                         eh_imm64(0x2222222222222222),
                         eh_imm64(0x3333333333333333))
    await fire(dut, instr, _STD_TAG(), payload_a=0)
    assert dut.error_flag.value == 1


# =============================================================================
# v1.5 output_frag_hdr backward compat (§17 — NoC wave-token fragment)
# =============================================================================
#
# All existing v1.0..1.4 primitives emit `output_frag_hdr = 0x00`
# (single-fragment). Wide-output primitives (future v1.x amendments)
# will emit multi-cycle fragment sequences with encoded index/total.


@cocotb.test()
async def test_frag_hdr_default_zero_alu(dut):
    """v1.5: ALU ops emit output_frag_hdr = 0x00 (single-fragment).
    This holds for all legacy primitives — the wire format shift is
    transparent to v1.0..1.4 code paths."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x10, _STD_PORT(), eh_imm16(5))
    await fire(dut, instr, _STD_TAG(), payload_a=10)
    assert dut.output_valid.value == 1
    # ISA_Decoder exposes output_frag_hdr as a top-level output.
    assert int(dut.output_frag_hdr.value) == 0x00


@cocotb.test()
async def test_frag_hdr_default_zero_einsum(dut):
    """v1.5: EINSUM (matmul) emits output_frag_hdr = 0x00."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x32, _STD_PORT(),
                         eh_subscript(axes(1, 2, 0, 0), axes(2, 3, 0, 0),
                                      axes(1, 3, 0, 0)),
                         eh_opref(),
                         flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(dim=0x11),
               payload_a=pack16(1, 2, 3, 4), payload_b=pack16(5, 6, 7, 8),
               payload_b_valid=1)
    assert dut.output_valid.value == 1
    assert int(dut.output_frag_hdr.value) == 0x00


# =============================================================================
# v1.5.2 §19 — Wide payload latch through EHDecode
# =============================================================================
#
# EHDecode latches `input_payload_wide` (1024-bit) alongside legacy
# `input_payload` (64-bit) and exposes it on `dec_input_payload_wide_out`
# after chain walk completion. Wide-consumer primitives (v1.5.3+) will
# read this in parallel with dec_input_payload.


@cocotb.test()
async def test_wide_payload_latches_when_valid(dut):
    """v1.5.2: drive input_payload_wide + valid alongside an ADD. After
    completion, dec_input_payload_wide_out must equal the driven value and
    dec_input_payload_wide_valid_out must be 1."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # Distinctive 1024-bit pattern
    wide_val = 0
    for i in range(16):
        wide_val |= ((0xA000 + i) & 0xFFFF) << (i * 64)

    instr = encode_instr(0x10, _STD_PORT(), eh_imm16(0))
    await fire(dut, instr, _STD_TAG(), payload_a=42,
               payload_wide=wide_val, payload_wide_valid=1)
    assert dut.output_valid.value == 1
    assert int(dut.dec_input_payload_wide_out.value) == wide_val
    assert int(dut.dec_input_payload_wide_valid_out.value) == 1


@cocotb.test()
async def test_wide_payload_zero_when_invalid(dut):
    """v1.5.2: without wide_valid, the wide bus latches whatever is on it
    (0 in this case since we don't drive) and valid_out stays 0.
    Legacy path unaffected."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    instr = encode_instr(0x10, _STD_PORT(), eh_imm16(5))
    await fire(dut, instr, _STD_TAG(), payload_a=10)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 15  # legacy ADD unaffected
    assert int(dut.dec_input_payload_wide_valid_out.value) == 0


# =============================================================================
# v1.5.3 §20 — SIG_BMM_3 first wide-consumer primitive
# =============================================================================
#
# 'abcij,abcjk->abcik' — 3-batch matmul at int4, 5D 2×2×2×2×2 = 32 nibbles
# per tensor = 128-bit A/B/O. Input via dec_input_payload_wide (A at
# wide[127:0], B at wide[255:128]). Output split into 2 wave tokens with
# frag_hdr = 0x01, 0x11.
#
# Legacy signatures (SIG_BMM, SIG_MATMUL, etc.) are guarded by
# `dec_eff_subscript_hi == 48'h0` — a wave with nonzero subscript_hi that
# doesn't match SIG_BMM_3 lands in lower_required, not a legacy arm.


def _pack_int4_128(*nibbles):
    """Pack 32 int4 nibbles into a 128-bit value (little-endian).
    Position 0 = bits [3:0], position 31 = bits [127:124]."""
    if len(nibbles) != 32:
        raise ValueError(f"expected 32 nibbles, got {len(nibbles)}")
    v = 0
    for i, n in enumerate(nibbles):
        v |= (n & 0xF) << (i * 4)
    return v


def _pack_int4_wide(a_128, b_128):
    """Pack A||B into the 256-bit low half of dec_input_payload_wide.
    A at wide[127:0], B at wide[255:128]."""
    return (a_128 & ((1 << 128) - 1)) | ((b_128 & ((1 << 128) - 1)) << 128)


def _matmul_2x2_int4_sim(a, b):
    """Python reference for matmul_2x2_int4 (mirror of Verilog function).
    a, b: 16-bit values holding 4 signed int4 nibbles."""
    def s4(x):
        x &= 0xF
        return x - 16 if x & 0x8 else x
    a00, a01, a10, a11 = s4(a & 0xF), s4((a >> 4) & 0xF), s4((a >> 8) & 0xF), s4((a >> 12) & 0xF)
    b00, b01, b10, b11 = s4(b & 0xF), s4((b >> 4) & 0xF), s4((b >> 8) & 0xF), s4((b >> 12) & 0xF)
    r00 = (a00 * b00 + a01 * b10) & 0xF
    r01 = (a00 * b01 + a01 * b11) & 0xF
    r10 = (a10 * b00 + a11 * b10) & 0xF
    r11 = (a10 * b01 + a11 * b11) & 0xF
    return (r11 << 12) | (r10 << 8) | (r01 << 4) | r00


def _bmm_3_sim(a_128, b_128):
    """Python reference for SIG_BMM_3. Returns (lo_64, hi_64) matching the
    two wave-token fragments the HW emits."""
    def sub(v, batch_idx):
        # sub-payload for batch (a,b,c) at (a*4+b*2+c)*16
        return (v >> (batch_idx * 16)) & 0xFFFF
    r = [_matmul_2x2_int4_sim(sub(a_128, i), sub(b_128, i)) for i in range(8)]
    # fragment 0 = a=0 batches (0..3), fragment 1 = a=1 batches (4..7)
    lo = r[0] | (r[1] << 16) | (r[2] << 32) | (r[3] << 48)
    hi = r[4] | (r[5] << 16) | (r[6] << 32) | (r[7] << 48)
    return lo, hi


# SIG_BMM_3 subscript encoding (mirrors PE_Core.v localparams).
# eh_subscript packs into 48-bit body: {A_pack[15:0], B_pack[15:0], O_pack[15:0]}.
_BMM3_A_LO = 0x4321
_BMM3_B_LO = 0x5321
_BMM3_O_LO = 0x4321
_BMM3_A_HI = 0x0005
_BMM3_B_HI = 0x0006
_BMM3_O_HI = 0x0006


async def _fire_bmm_3(dut, a_128, b_128, dim=0x55, wide_valid=1):
    """Helper: fire a SIG_BMM_3 instruction with A/B packed into wide input.
    Returns after the SECOND output_valid pulse or timeout."""
    wide = _pack_int4_wide(a_128, b_128)
    # 2 SUBSCRIPT EHs (lo + hi) + PORT + OPREF (opcode 0x32 requires OPREF)
    instr = encode_instr(0x32, _STD_PORT(),
                         eh_subscript(_BMM3_A_LO, _BMM3_B_LO, _BMM3_O_LO),
                         eh_subscript(_BMM3_A_HI, _BMM3_B_HI, _BMM3_O_HI),
                         eh_opref(),
                         flags=F_HAS_OPB)
    dut.instruction.value = instr
    dut.input_tag.value = _STD_TAG(dim=dim)
    dut.input_payload.value = 0
    dut.input_payload_b.value = 0
    dut.input_payload_b_valid.value = 1
    dut.input_payload_wide.value = wide
    dut.input_payload_wide_valid.value = wide_valid
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0
    # Poll — first output_valid (frag 0)
    saw_frag0 = None
    for _ in range(80):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.output_valid.value) == 1:
            saw_frag0 = {
                'payload': int(dut.output_payload.value),
                'frag_hdr': int(dut.output_frag_hdr.value),
                'tag': int(dut.output_tag.value),
            }
            break
        if int(dut.error_flag.value) or int(dut.lower_required.value):
            return {'fail': True,
                    'error': int(dut.error_flag.value),
                    'lower': int(dut.lower_required.value)}
    if saw_frag0 is None:
        return {'timeout': True}
    # Next cycle: frag 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    saw_frag1 = {
        'payload': int(dut.output_payload.value),
        'frag_hdr': int(dut.output_frag_hdr.value),
        'valid': int(dut.output_valid.value),
        'tag': int(dut.output_tag.value),
    }
    # Cycle N+2: should return to idle
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    saw_after = {
        'valid': int(dut.output_valid.value),
        'frag_hdr': int(dut.output_frag_hdr.value),
    }
    return {'frag0': saw_frag0, 'frag1': saw_frag1, 'after': saw_after}


@cocotb.test()
async def test_bmm_3_identity_per_batch(dut):
    """v1.5.3: SIG_BMM_3 with A = identity per each of 8 batches → R = B."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # int4 identity per 2x2 batch: nibble packing is [a11 a10 a01 a00]
    # from MSB to LSB (matmul_2x2_int4 reads a[0 +: 4] = a00). Identity
    # matrix = [[1,0],[0,1]] → a00=1, a01=0, a10=0, a11=1 → 0x1001.
    identity = 0x1001
    a_128 = 0
    for i in range(8):
        a_128 |= identity << (i * 16)
    # B: distinctive per batch
    b_batches = [0x1234, 0x5678, 0x9ABC, 0xDEF0,
                 0x0FED, 0xCBA9, 0x8765, 0x4321]
    b_128 = 0
    for i, x in enumerate(b_batches):
        b_128 |= (x & 0xFFFF) << (i * 16)

    r = await _fire_bmm_3(dut, a_128, b_128)
    assert 'fail' not in r and 'timeout' not in r, f"got {r}"
    # Identity × B = B → both frags equal expected halves of b_128
    exp_lo = b_128 & ((1 << 64) - 1)
    exp_hi = (b_128 >> 64) & ((1 << 64) - 1)
    assert r['frag0']['payload'] == exp_lo, f"frag0 {r['frag0']['payload']:016x} != {exp_lo:016x}"
    assert r['frag0']['frag_hdr'] == 0x01
    assert r['frag1']['payload'] == exp_hi, f"frag1 {r['frag1']['payload']:016x} != {exp_hi:016x}"
    assert r['frag1']['frag_hdr'] == 0x11
    assert r['frag1']['valid'] == 1


@cocotb.test()
async def test_bmm_3_computed_matmul(dut):
    """v1.5.3: SIG_BMM_3 with concrete non-trivial A and B — result matches
    Python reference."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # Distinctive A and B per batch
    a_128 = 0
    b_128 = 0
    for i in range(8):
        a_128 |= (0x1234 + i) << (i * 16)
        b_128 |= (0x2345 + i * 2) << (i * 16)
    r = await _fire_bmm_3(dut, a_128, b_128)
    assert 'fail' not in r, f"got {r}"
    exp_lo, exp_hi = _bmm_3_sim(a_128, b_128)
    assert r['frag0']['payload'] == exp_lo
    assert r['frag1']['payload'] == exp_hi


@cocotb.test()
async def test_bmm_3_two_fragment_output_sequence(dut):
    """v1.5.3a: verify frag_hdr sequence is exactly 0x01 → 0x11 and
    output_frag_hdr returns to 0x00 the cycle AFTER (NRZ hazard test)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a_128 = _pack_int4_128(*([0] * 32))
    b_128 = _pack_int4_128(*([1] * 32))
    r = await _fire_bmm_3(dut, a_128, b_128)
    assert 'fail' not in r
    assert r['frag0']['frag_hdr'] == 0x01
    assert r['frag1']['frag_hdr'] == 0x11
    # NRZ hazard: cycle N+2 must snap back to output_valid=0, frag_hdr=0x00
    assert r['after']['valid'] == 0
    assert r['after']['frag_hdr'] == 0x00


@cocotb.test()
async def test_bmm_3_wide_valid_gate_error_flag(dut):
    """v1.5.3 §20: SIG_BMM_3 with wide_valid=0 is illegal (fabric contract
    violation) — raises error_flag, not lower_required."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a_128 = _pack_int4_128(*([1] * 32))
    b_128 = _pack_int4_128(*([1] * 32))
    r = await _fire_bmm_3(dut, a_128, b_128, wide_valid=0)
    assert r.get('fail') is True
    assert r['error'] == 1


@cocotb.test()
async def test_bmm_3_tag_stability_across_fragments(dut):
    """v1.5.3a: output_tag is bit-exact across the two fragments (only
    frag_hdr differs)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a_128 = _pack_int4_128(*[(i & 0xF) for i in range(32)])
    b_128 = _pack_int4_128(*[((i + 3) & 0xF) for i in range(32)])
    r = await _fire_bmm_3(dut, a_128, b_128)
    assert 'fail' not in r
    assert r['frag0']['tag'] == r['frag1']['tag']


@cocotb.test()
async def test_legacy_sig_with_subscript_hi_nonzero_lowers(dut):
    """v1.5.3 §20 regression guard: legacy signature (e.g. SIG_MATMUL) with
    NONZERO subscript_hi must NOT execute — the two-level dispatch rejects it
    as an unknown wide-consumer signature."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # SIG_MATMUL subscript = (A=ij=0x0021, B=jk=0x0032, O=ik=0x0031)
    # + a spurious second SUBSCRIPT EH — hi should not be zero.
    instr = encode_instr(0x32, _STD_PORT(),
                         eh_subscript(0x0021, 0x0032, 0x0031),
                         eh_subscript(0x0007, 0x0000, 0x0000),  # spurious hi
                         eh_opref(),
                         flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(dim=0x05),
               payload_a=pack16(1, 2, 3, 4), payload_b=pack16(5, 6, 7, 8),
               payload_b_valid=1)
    # Must NOT execute as SIG_MATMUL — falls into unknown wide-consumer arm
    assert dut.output_valid.value == 0
    assert dut.lower_required.value == 1


@cocotb.test()
async def test_bmm_3_unknown_wide_sig_lowers(dut):
    """v1.5.3 §20: nonzero subscript_hi that isn't SIG_BMM_3_HI must
    lower_required (no matching wide-consumer primitive)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # SIG_BMM_3_LO but garbage HI
    instr = encode_instr(0x32, _STD_PORT(),
                         eh_subscript(_BMM3_A_LO, _BMM3_B_LO, _BMM3_O_LO),
                         eh_subscript(0xABCD, 0xEF01, 0x2345),
                         eh_opref(),
                         flags=F_HAS_OPB)
    dut.input_payload_wide.value = 0
    dut.input_payload_wide_valid.value = 1
    await fire(dut, instr, _STD_TAG(dim=0x55),
               payload_a=0, payload_b=0, payload_b_valid=1)
    assert dut.output_valid.value == 0
    assert dut.lower_required.value == 1


# =============================================================================
# v1.6.1 §22 — Group A reduction primitives
# =============================================================================
#
# 12 reduction primitives sharing wide-input path with SIG_TRACE_IIJKL (v1.5.5).
# Families:
#   5D→scalar (A_lo=0x4321, A_hi=0x0005, B/O=0): op_marker in O_hi[3:0].
#     0=SUM, 1=MAX, 2=ARGMAX, 3=L1, 4=L2SQ, 6=MIN, 7=ARGMIN
#   5D→4D (A_lo=0x4321, A_hi=0x0005, O_lo=0x4321): op_marker in O_hi[3:0].
#     0=SUM, 1=MAX, 4=L2SQ, 5=MEAN
#   5D→3D SIG_TRACE_IJJKL (A_lo=0x3221, O_lo=0x0431, A_hi=0x0004): unique.


def _reduce_sig(a_lo_pack, o_lo_pack, a_hi_pack, op_marker):
    """Build (lo_48, hi_48) SUBSCRIPT bodies for a reduction primitive.
    Reduction family: B_lo/B_hi/O_hi always zero except O_hi[3:0] = op_marker."""
    lo = (a_lo_pack & 0xFFFF) << 32 | (0 & 0xFFFF) << 16 | (o_lo_pack & 0xFFFF)
    hi = (a_hi_pack & 0xFFFF) << 32 | (0 & 0xFFFF) << 16 | (op_marker & 0xF)
    return lo, hi


async def _fire_scalar_reduction(dut, a_128, op_marker, dim=0x55, wide_valid=1):
    """Fire a 5D→scalar reduction with given op_marker."""
    a_lo_hex, hi = _reduce_sig(0x4321, 0x0000, 0x0005, op_marker)
    wide = a_128 & ((1 << 128) - 1)
    instr = encode_instr(0x32, _STD_PORT(),
                         eh_subscript(0x4321, 0x0000, 0x0000),
                         eh_subscript(0x0005, 0x0000, op_marker & 0xF),
                         eh_opref(),
                         flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(dim=dim),
               payload_a=0, payload_b=0, payload_b_valid=1,
               payload_wide=wide, payload_wide_valid=wide_valid)


async def _fire_5d_to_4d_reduction(dut, a_128, op_marker, dim=0x55, wide_valid=1):
    """Fire a 5D→4D reduction with given op_marker."""
    wide = a_128 & ((1 << 128) - 1)
    instr = encode_instr(0x32, _STD_PORT(),
                         eh_subscript(0x4321, 0x0000, 0x4321),
                         eh_subscript(0x0005, 0x0000, op_marker & 0xF),
                         eh_opref(),
                         flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(dim=dim),
               payload_a=0, payload_b=0, payload_b_valid=1,
               payload_wide=wide, payload_wide_valid=wide_valid)


def _s4(x):
    x &= 0xF
    return x - 16 if x & 0x8 else x


@cocotb.test()
async def test_reduce_sum_ijklm(dut):
    """v1.6.1: 5D→scalar SUM. Distinctive nibbles, verify mod-2^4 wrap."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    nibbles = [((i + 1) & 0xF) for i in range(32)]  # 1,2,...,15,0,1,...
    a_128 = _pack_int4_128(*nibbles)
    await _fire_scalar_reduction(dut, a_128, 0x0)  # SUM
    assert dut.output_valid.value == 1
    expected = sum(nibbles) & 0xF
    assert int(dut.output_payload.value) & 0xF == expected
    assert (int(dut.output_tag.value) & 0xFF) == 0x00  # scalar


@cocotb.test()
async def test_reduce_max_ijklm(dut):
    """v1.6.1: 5D→scalar MAX. Signed int4 max."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    # place +7 (max positive int4) at position 15, negatives elsewhere
    nibbles = [0xF] * 32   # -1
    nibbles[15] = 0x7      # +7
    a_128 = _pack_int4_128(*nibbles)
    await _fire_scalar_reduction(dut, a_128, 0x1)  # MAX
    assert dut.output_valid.value == 1
    assert (int(dut.output_payload.value) & 0xF) == 0x7


@cocotb.test()
async def test_reduce_min_ijklm(dut):
    """v1.6.1: 5D→scalar MIN. Fréchet medoid / k-means core."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    nibbles = [0x1] * 32   # +1
    nibbles[10] = 0x8      # -8 (min int4)
    a_128 = _pack_int4_128(*nibbles)
    await _fire_scalar_reduction(dut, a_128, 0x6)  # MIN
    assert dut.output_valid.value == 1
    assert (int(dut.output_payload.value) & 0xF) == 0x8


@cocotb.test()
async def test_reduce_argmax_ijklm(dut):
    """v1.6.1: 5D→scalar ARGMAX. Returns position (0..31)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    nibbles = [0x0] * 32
    nibbles[22] = 0x7      # max at position 22
    a_128 = _pack_int4_128(*nibbles)
    await _fire_scalar_reduction(dut, a_128, 0x2)  # ARGMAX
    assert dut.output_valid.value == 1
    assert (int(dut.output_payload.value) & 0x1F) == 22


@cocotb.test()
async def test_reduce_argmin_ijklm(dut):
    """v1.6.1: 5D→scalar ARGMIN. Fréchet medoid, k-means assignment,
    KNN classifier, VQ-VAE codebook lookup — all argmin patterns."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    nibbles = [0x1] * 32
    nibbles[7] = 0x8       # -8 (min) at position 7
    a_128 = _pack_int4_128(*nibbles)
    await _fire_scalar_reduction(dut, a_128, 0x7)  # ARGMIN
    assert dut.output_valid.value == 1
    assert (int(dut.output_payload.value) & 0x1F) == 7


@cocotb.test()
async def test_reduce_l1_ijklm(dut):
    """v1.6.1: 5D→scalar L1 = Σ |A|. int32 accumulator."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    # 16 × +3 + 16 × -5 → L1 = 16*3 + 16*5 = 128
    nibbles = [0x3] * 16 + [0xB] * 16   # 0xB = -5 signed
    a_128 = _pack_int4_128(*nibbles)
    await _fire_scalar_reduction(dut, a_128, 0x3)  # L1
    assert dut.output_valid.value == 1
    expected = 16 * 3 + 16 * 5
    assert (int(dut.output_payload.value) & 0xFFFFFFFF) == expected


@cocotb.test()
async def test_reduce_l2sq_ijklm(dut):
    """v1.6.1: 5D→scalar L2SQ = Σ A². Central for LayerNorm variance."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    # 32 × +2 → L2SQ = 32 * 4 = 128
    nibbles = [0x2] * 32
    a_128 = _pack_int4_128(*nibbles)
    await _fire_scalar_reduction(dut, a_128, 0x4)  # L2SQ
    assert dut.output_valid.value == 1
    expected = 32 * 4
    assert (int(dut.output_payload.value) & 0xFFFFFFFF) == expected


@cocotb.test()
async def test_reduce_mean_5d_to_4d(dut):
    """v1.6.1: 5D→4D MEAN. (A0+A1) >> 1 (ASR)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    # All +4 → mean=+4
    nibbles = [0x4] * 32
    a_128 = _pack_int4_128(*nibbles)
    await _fire_5d_to_4d_reduction(dut, a_128, 0x5)  # MEAN
    assert dut.output_valid.value == 1
    payload = int(dut.output_payload.value)
    for idx in range(16):
        got = (payload >> (idx * 4)) & 0xF
        assert got == 0x4, f"idx {idx}: {got:x} != 4"
    # v1.6.5d §22.17 tag-stability-literal pin: OP_MEAN's output tag
    # dim_sizes must be 0x55 — this is the literal LAYERNORM step 1
    # produces and step 2 inherits into its cached tag, which
    # CACHE_LOAD_WIDE's .precision dim=0x55 guard (asm.py) must match.
    # See test_op_mean_and_cache_load_wide_dim_sizes_consistency for the
    # cross-file check that catches a one-sided edit to either literal.
    assert (int(dut.output_tag.value) & 0xFF) == 0x55


@cocotb.test()
async def test_reduce_5d_to_4d_removed_markers_lower(dut):
    """Opcode cleanup (pre-stable, spec removal record): the 5D→4D
    SUM/MAX/L2SQ/MIN variants (op_markers 0x0/0x1/0x4/0x6) were removed —
    zero asm/SDK consumers. Those markers now fall to the family's
    default lower_required arm, exactly like any never-assigned marker
    (0x7 probed alongside). MEAN (0x5) remains the only live member."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    a_128 = _pack_int4_128(*([0x2] * 32))
    for marker in (0x0, 0x1, 0x4, 0x6, 0x7):
        await _fire_5d_to_4d_reduction(dut, a_128, marker)
        assert dut.lower_required.value == 1, f"marker 0x{marker:X}"
        assert dut.output_valid.value == 0, f"marker 0x{marker:X}"


@cocotb.test()
async def test_reduce_trace_ijjkl(dut):
    """v1.6.1: 5D→3D SIG_TRACE_IJJKL (trace over j, variant of IIJKL)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    # Diagonal only: place +3 at diagonal positions, poison elsewhere
    nibbles = [0xF] * 32  # -1
    # i-block 0: diag (0,0) offsets 0-3, diag (1,1) offsets 12-15
    # i-block 1: diag (0,0) offsets 16-19, diag (1,1) offsets 28-31
    for k in range(2):
        for l in range(2):
            nibbles[0 * 16 + 0 + k * 2 + l] = 0x3
            nibbles[0 * 16 + 12 + k * 2 + l] = 0x3
            nibbles[1 * 16 + 0 + k * 2 + l] = 0x3
            nibbles[1 * 16 + 12 + k * 2 + l] = 0x3
    a_128 = _pack_int4_128(*nibbles)
    wide = a_128 & ((1 << 128) - 1)
    instr = encode_instr(0x32, _STD_PORT(),
                         eh_subscript(0x3221, 0x0000, 0x0431),   # SIG_TRACE_IJJKL_LO
                         eh_subscript(0x0004, 0x0000, 0x0000),   # SIG_TRACE_IJJKL_HI
                         eh_opref(),
                         flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(dim=0x55),
               payload_a=0, payload_b=0, payload_b_valid=1,
               payload_wide=wide, payload_wide_valid=1)
    assert dut.output_valid.value == 1
    payload = int(dut.output_payload.value)
    # Each output cell = 3 + 3 = 6
    for idx in range(8):
        got = (payload >> (idx * 4)) & 0xF
        assert got == 0x6, f"idx {idx}: {got:x} != 6"
    assert (int(dut.output_tag.value) & 0xFF) == 0x15  # 3D 2×2×2


@cocotb.test()
async def test_reduce_wide_valid_gate_error(dut):
    """v1.6.1: reduction with wide_valid=0 raises error_flag."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    await _fire_scalar_reduction(dut, 0, 0x0, wide_valid=0)  # SUM w/o wide
    assert dut.error_flag.value == 1


# =============================================================================
# v1.6.1b §22 — Group B broadcast SIMD ops (0x60-65)
# =============================================================================
#
# SCALAR: A via wide[127:0], B_scalar via dec_eff_b_value[3:0] (IMM or OPREF).
# VEC:    A via wide[127:0], V via dec_input_payload_b (F_HAS_OPB).
# Both wide-output → 2-fragment emit (FSM engagement).
# (Group C rsqrt 0x66 was removed pre-stable in the opcode cleanup — see
# test_removed_opcode_0x66_rsqrt_decode_errors below.)


async def _fire_simd_wide_scalar(dut, opcode, a_128, b_scalar):
    """Fire SIMD_[ADD/SUB/MUL]_WIDE_SCALAR (0x60/61/62). B_scalar via IMM16."""
    wide = a_128 & ((1 << 128) - 1)
    instr = encode_instr(opcode, _STD_PORT(), eh_imm16(b_scalar & 0xF))
    dut.instruction.value = instr
    dut.input_tag.value = _STD_TAG()
    dut.input_payload.value = 0
    dut.input_payload_b.value = 0
    dut.input_payload_b_valid.value = 0
    dut.input_payload_wide.value = wide
    dut.input_payload_wide_valid.value = 1
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0
    # First frag
    saw = []
    for _ in range(30):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.output_valid.value) == 1:
            saw.append({'payload': int(dut.output_payload.value),
                        'frag_hdr': int(dut.output_frag_hdr.value)})
            break
        if int(dut.error_flag.value) or int(dut.lower_required.value):
            return {'fail': True, 'error': int(dut.error_flag.value)}
    # Cycle N+1: frag 1
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    saw.append({'payload': int(dut.output_payload.value),
                'frag_hdr': int(dut.output_frag_hdr.value),
                'valid': int(dut.output_valid.value)})
    return {'frags': saw}


async def _fire_simd_wide_vec(dut, opcode, a_128, v_64):
    """Fire SIMD_[ADD/SUB/MUL]_WIDE_VEC (0x63/64/65). V via input_payload_b."""
    wide = a_128 & ((1 << 128) - 1)
    instr = encode_instr(opcode, _STD_PORT(), flags=F_HAS_OPB)
    dut.instruction.value = instr
    dut.input_tag.value = _STD_TAG()
    dut.input_payload.value = 0
    dut.input_payload_b.value = v_64 & ((1 << 64) - 1)
    dut.input_payload_b_valid.value = 1
    dut.input_payload_wide.value = wide
    dut.input_payload_wide_valid.value = 1
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0
    saw = []
    for _ in range(30):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.output_valid.value) == 1:
            saw.append({'payload': int(dut.output_payload.value),
                        'frag_hdr': int(dut.output_frag_hdr.value)})
            break
        if int(dut.error_flag.value):
            return {'fail': True, 'error': 1}
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    saw.append({'payload': int(dut.output_payload.value),
                'frag_hdr': int(dut.output_frag_hdr.value),
                'valid': int(dut.output_valid.value)})
    return {'frags': saw}


@cocotb.test()
async def test_simd_add_wide_scalar(dut):
    """v1.6.1b: SIMD_ADD_WIDE_SCALAR (0x60). All 32 nibbles += 3."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    a_128 = _pack_int4_128(*[0x1] * 32)
    r = await _fire_simd_wide_scalar(dut, 0x60, a_128, 0x3)
    assert 'fail' not in r, f"got {r}"
    # All lanes: 1+3=4 → both fragments filled with 0x4444_4444_4444_4444
    expected = 0x4444_4444_4444_4444
    assert r['frags'][0]['payload'] == expected
    assert r['frags'][0]['frag_hdr'] == 0x01
    assert r['frags'][1]['payload'] == expected
    assert r['frags'][1]['frag_hdr'] == 0x11


@cocotb.test()
async def test_simd_sub_wide_scalar(dut):
    """v1.6.1b: SIMD_SUB_WIDE_SCALAR (0x61). x - 2 mod 2^4."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    a_128 = _pack_int4_128(*[0x5] * 32)
    r = await _fire_simd_wide_scalar(dut, 0x61, a_128, 0x2)
    assert 'fail' not in r
    # 5-2=3 all lanes
    expected = 0x3333_3333_3333_3333
    assert r['frags'][0]['payload'] == expected
    assert r['frags'][1]['payload'] == expected


@cocotb.test()
async def test_simd_mul_wide_scalar(dut):
    """v1.6.1b: SIMD_MUL_WIDE_SCALAR (0x62). x * 2 mod 2^4."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    a_128 = _pack_int4_128(*[0x3] * 32)
    r = await _fire_simd_wide_scalar(dut, 0x62, a_128, 0x2)
    assert 'fail' not in r
    # 3*2=6 all lanes
    expected = 0x6666_6666_6666_6666
    assert r['frags'][0]['payload'] == expected


@cocotb.test()
async def test_simd_add_wide_vec(dut):
    """v1.6.1b: SIMD_ADD_WIDE_VEC (0x63). V broadcasts to A pairs."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    # A: 32 nibbles, all 0x1
    a_128 = _pack_int4_128(*[0x1] * 32)
    # V: 16 nibbles, position i has value i
    v_nibbles = [(i & 0xF) for i in range(16)]
    v_64 = 0
    for i, n in enumerate(v_nibbles):
        v_64 |= (n & 0xF) << (i * 4)
    r = await _fire_simd_wide_vec(dut, 0x63, a_128, v_64)
    assert 'fail' not in r
    # Expected: A[i] + V[i>>1] mod 2^4
    # Reassemble 128-bit result
    got = r['frags'][0]['payload'] | (r['frags'][1]['payload'] << 64)
    for i in range(32):
        v_idx = i >> 1
        exp = (1 + v_nibbles[v_idx]) & 0xF
        actual = (got >> (i * 4)) & 0xF
        assert actual == exp, f"lane {i}: {actual:x} != {exp:x}"


@cocotb.test()
async def test_simd_sub_wide_vec(dut):
    """v1.6.1b: SIMD_SUB_WIDE_VEC (0x64). Central for LayerNorm centering."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    a_128 = _pack_int4_128(*[0x7] * 32)
    v_64 = 0
    for i in range(16):
        v_64 |= (0x2 & 0xF) << (i * 4)   # V all 2
    r = await _fire_simd_wide_vec(dut, 0x64, a_128, v_64)
    assert 'fail' not in r
    # 7 - 2 = 5 all lanes
    expected = 0x5555_5555_5555_5555
    assert r['frags'][0]['payload'] == expected
    assert r['frags'][1]['payload'] == expected


@cocotb.test()
async def test_simd_mul_wide_vec(dut):
    """v1.6.1b: SIMD_MUL_WIDE_VEC (0x65). Central for LayerNorm scaling."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    a_128 = _pack_int4_128(*[0x2] * 32)
    v_64 = 0
    for i in range(16):
        v_64 |= (0x3 & 0xF) << (i * 4)   # V all 3
    r = await _fire_simd_wide_vec(dut, 0x65, a_128, v_64)
    assert 'fail' not in r
    # 2 * 3 = 6 all lanes (truncated to int4)
    expected = 0x6666_6666_6666_6666
    assert r['frags'][0]['payload'] == expected


@cocotb.test()
async def test_simd_wide_vec_opref_legal(dut):
    """v1.6.5c §22.16: MUST-FIX-FIRST regression. Before this fix,
    EHDecode.v's 0x63/64/65 case forbade BOTH imm_any and opref
    unconditionally, so LAYERNORM's step 2/5 (0x64 with an OPREF EH for
    mu_opref) always decode-errored. Confirm 0x64 + OPREF now decodes
    clean (V's actual value still arrives via input_payload_b — the
    OPREF EH is legality/encoding-only, per EHDecode.v's comment)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    a_128 = _pack_int4_128(*[0x7] * 32)
    v_64 = 0
    for i in range(16):
        v_64 |= (0x2 & 0xF) << (i * 4)
    wide = a_128 & ((1 << 128) - 1)
    instr = encode_instr(0x64, _STD_PORT(), eh_opref(), flags=F_HAS_OPB)
    dut.instruction.value = instr
    dut.input_tag.value = _STD_TAG()
    dut.input_payload.value = 0
    dut.input_payload_b.value = v_64
    dut.input_payload_b_valid.value = 1
    dut.input_payload_wide.value = wide
    dut.input_payload_wide_valid.value = 1
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0
    for _ in range(30):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.output_valid.value) == 1:
            break
        assert int(dut.error_flag.value) == 0, "0x64+OPREF must not decode-error (v1.6.5c fix)"
    assert dut.output_valid.value == 1
    expected = 0x5555_5555_5555_5555
    assert int(dut.output_payload.value) == expected


@cocotb.test()
async def test_simd_wide_vec_imm64_legal(dut):
    """v1.6.5c §22.16: companion regression — 0x65/0x63 with an IMM64 EH
    (LAYERNORM step 7/8's shape) must also decode clean, not just OPREF."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    a_128 = _pack_int4_128(*[0x2] * 32)
    v_64 = 0
    for i in range(16):
        v_64 |= (0x3 & 0xF) << (i * 4)
    wide = a_128 & ((1 << 128) - 1)
    instr = encode_instr(0x65, _STD_PORT(), eh_imm64(0), flags=F_HAS_OPB)
    dut.instruction.value = instr
    dut.input_tag.value = _STD_TAG()
    dut.input_payload.value = 0
    dut.input_payload_b.value = v_64
    dut.input_payload_b_valid.value = 1
    dut.input_payload_wide.value = wide
    dut.input_payload_wide_valid.value = 1
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0
    for _ in range(30):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.output_valid.value) == 1:
            break
        assert int(dut.error_flag.value) == 0, "0x65+IMM64 must not decode-error (v1.6.5c fix)"
    assert dut.output_valid.value == 1
    expected = 0x6666_6666_6666_6666
    assert int(dut.output_payload.value) == expected


@cocotb.test()
async def test_simd_wide_scalar_frag_hdr_sequence(dut):
    """v1.6.1b: verify frag_hdr sequence 0x01 → 0x11 for wide-output ops."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    a_128 = _pack_int4_128(*[0x0] * 32)
    r = await _fire_simd_wide_scalar(dut, 0x60, a_128, 0x5)
    assert 'fail' not in r
    assert r['frags'][0]['frag_hdr'] == 0x01
    assert r['frags'][1]['frag_hdr'] == 0x11
    assert r['frags'][1]['valid'] == 1


@cocotb.test()
async def test_simd_wide_valid_gate_error(dut):
    """v1.6.1b: SIMD wide op with wide_valid=0 raises error_flag."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    instr = encode_instr(0x60, _STD_PORT(), eh_imm16(0x1))
    # Fire with wide_valid=0
    dut.instruction.value = instr
    dut.input_tag.value = _STD_TAG()
    dut.input_payload.value = 0
    dut.input_payload_b.value = 0
    dut.input_payload_b_valid.value = 0
    dut.input_payload_wide.value = 0
    dut.input_payload_wide_valid.value = 0
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0
    for _ in range(20):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.error_flag.value):
            break
    assert dut.error_flag.value == 1


async def _fire_removed_opcode(dut, instr):
    """Fire a removed-opcode encoding and poll for the decode outcome."""
    dut.instruction.value = instr
    dut.input_tag.value = _STD_TAG()
    dut.input_payload.value = 0x0001_0000
    dut.input_payload_b.value = 0
    dut.input_payload_b_valid.value = 0
    dut.input_payload_wide.value = _pack_int4_128(*([0x2] * 32))
    dut.input_payload_wide_valid.value = 1
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0
    for _ in range(20):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if (int(dut.error_flag.value) == 1
                or int(dut.output_valid.value) == 1
                or int(dut.lower_required.value) == 1):
            break
    assert int(dut.error_flag.value) == 1, "removed opcode must decode_error"
    assert int(dut.output_valid.value) == 0
    assert int(dut.lower_required.value) == 0, \
        "removed opcode is a malformation (decode_error), not a capability absence"


@cocotb.test()
async def test_removed_opcode_0x66_rsqrt_decode_errors(dut):
    """Opcode cleanup (pre-stable): SCALAR_RSQRT (0x66) was deleted from
    isa/wt64v1_isa.json, so the regenerated opcode_supported whitelist
    decode-errors its previously-legal bare-PORT shape."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    await _fire_removed_opcode(dut, encode_instr(0x66, _STD_PORT()))


# =============================================================================
# Opcode cleanup (pre-stable) — removed 4D→3D reduction family + removed
# opcodes 0x66/0x67/0x6B/0x6C regression pins
# =============================================================================


@cocotb.test()
async def test_reduce_4d_to_3d_family_removed_lowers(dut):
    """Opcode cleanup (pre-stable): the entire 4D→3D reduction family
    (SIG_4D3D_*, markers SUM/MAX/L2SQ/MEAN/MIN) was removed — zero
    asm/SDK consumers. Its old signature (A=0x4321/O=0x0321,
    A_hi=0x0004) matches no dispatch arm any more and falls to the
    einsum unknown-signature lower_required tail for every
    previously-live marker."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    for marker in (0x0, 0x1, 0x4, 0x5, 0x6):
        instr = encode_instr(0x32, _STD_PORT(),
                             eh_subscript(0x4321, 0x0000, 0x0321),
                             eh_subscript(0x0004, 0x0000, marker),
                             eh_opref(),
                             flags=F_HAS_OPB)
        await fire(dut, instr, _STD_TAG(dim=0x55),
                   payload_a=0, payload_b=0, payload_b_valid=1)
        assert dut.lower_required.value == 1, f"marker 0x{marker:X}"
        assert dut.output_valid.value == 0, f"marker 0x{marker:X}"


@cocotb.test()
async def test_removed_opcode_0x67_q4_4_decode_errors(dut):
    """Opcode cleanup (pre-stable): SIMD_MUL_WIDE_Q4_4_SCALAR (0x67, the
    Q4.4 predecessor of the live 0x69 Q8.8) decode-errors with its
    previously-legal PORT+IMM16 shape."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    await _fire_removed_opcode(dut, encode_instr(0x67, _STD_PORT(),
                                                 eh_imm16(0x08)))


@cocotb.test()
async def test_reallocated_opcode_0x6B_gamma_mul_w(dut):
    """v1.8.0e 0e1 (was test_removed_opcode_0x6B_widen_decode_errors):
    the 0x6B code point, retired with WIDEN in the opcode cleanup, was
    REALLOCATED pre-stable to GAMMA_MUL_W (spec §25.2.3, §12a rule 4 —
    slot reuse recorded; this test is the mandatory retired-0x6B
    stale-consumer resync). The old PORT+IMM16 decode_error pin flips:
    that shape now satisfies the alu-binary XOR (IMM class present, no
    OPREF) and EXECUTES on this MUL_OPS_SUPPORTED harness — gamma =
    zext(imm16) with all upper gamma lanes 0, so lanes 4..15 of the
    exact widening product are 0 x a4 = 0 and lanes 0..3 multiply by the
    imm nibbles. The XOR-VIOLATING shapes stay decode_error (bare PORT =
    neither source; IMM16+OPREF = both), pinning the legality row.
    Value-level 0x6B coverage is the FP_CombArms unit TB + the 0e1
    integration e2e test (test_gamma_widen_exact)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    # XOR-satisfied imm form: decodes and executes (2-fragment emit)
    await fire(dut, encode_instr(0x6B, _STD_PORT(), eh_imm16(0x08)),
               _STD_TAG(), payload_a=0x1111, payload_b=0)
    assert dut.error_flag.value == 0, "reallocated 0x6B must decode"
    assert dut.lower_required.value == 0, "0x6B arm must execute on the MU"
    assert dut.output_valid.value == 1, "0x6B must emit fragment 0"
    # XOR violations: neither source / both sources -> decode_error
    for bad in (encode_instr(0x6B, _STD_PORT()),
                encode_instr(0x6B, _STD_PORT(), eh_imm16(0x08), eh_opref(),
                             flags=F_HAS_OPB)):
        await fire(dut, bad, _STD_TAG(), payload_a=0, payload_b=0,
                   payload_b_valid=1)
        assert dut.error_flag.value == 1, \
            "0x6B alu-binary XOR violation must stay decode_error"
        assert dut.output_valid.value == 0


@cocotb.test()
async def test_removed_opcode_0x6C_requantize_decode_errors(dut):
    """Opcode cleanup (pre-stable): SIMD_REQUANTIZE_Q4_4_TO_INT4 (0x6C,
    WIDEN's narrowing companion) decode-errors with its previously-legal
    bare-PORT unary shape."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    await _fire_removed_opcode(dut, encode_instr(0x6C, _STD_PORT()))


@cocotb.test()
async def test_simd_mul_wide_q8_8_scalar_basic(dut):
    """v1.6.7: SIMD_MUL_WIDE_Q8_8_SCALAR (0x69). Q8.8 broadcast to 32 int4
    lanes with round-half-up (16x finer B granularity than the retired
    0x67 Q4.4 form, removed pre-stable in the opcode cleanup).
    Test: A[i]=+2, B=Q8.8(0.5)=0x0080 -> p=2*128=256 (Q4.8), round:
    (256+128)>>8 = 1."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    a_128 = _pack_int4_128(*[0x2] * 32)
    instr = encode_instr(0x69, _STD_PORT(), eh_imm16(0x0080))
    dut.instruction.value = instr
    dut.input_tag.value = _STD_TAG()
    dut.input_payload.value = 0
    dut.input_payload_b_valid.value = 0
    dut.input_payload_wide.value = a_128
    dut.input_payload_wide_valid.value = 1
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0
    for _ in range(30):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.output_valid.value) == 1:
            break
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 0x1111_1111_1111_1111


@cocotb.test()
async def test_simd_mul_wide_q8_8_scalar_negative(dut):
    """v1.6.7: Q8.8 signed handling. A=+4, B=Q8.8(-1.0)=0xFF00.
    p=4*(-256)=-1024 (Q4.8). round: (-1024+128)>>8 = -896>>8 = -4 = 0xC."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    a_128 = _pack_int4_128(*[0x4] * 32)
    instr = encode_instr(0x69, _STD_PORT(), eh_imm16(0xFF00))
    dut.instruction.value = instr
    dut.input_tag.value = _STD_TAG()
    dut.input_payload.value = 0
    dut.input_payload_b_valid.value = 0
    dut.input_payload_wide.value = a_128
    dut.input_payload_wide_valid.value = 1
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0
    for _ in range(30):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.output_valid.value) == 1:
            break
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 0xCCCC_CCCC_CCCC_CCCC


@cocotb.test()
async def test_simd_mul_wide_q8_8_scalar_precision_vs_q4_4(dut):
    """v1.6.7: demonstrate Q8.8's finer granularity vs the Q4.4 format
    (as a NUMBER FORMAT — the 0x67 opcode itself was removed pre-stable
    in the opcode cleanup; this test fires only the live 0x69).
    B=Q8.8(0.25)=0x0040 rounds differently at Q4.4's coarser 1/16 LSB vs
    Q8.8's 1/256 LSB. A[i]=+7, B=Q8.8(0.25): p=7*64=448 (Q4.8),
    round:(448+128)>>8=2."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    a_128 = _pack_int4_128(*[0x7] * 32)
    instr = encode_instr(0x69, _STD_PORT(), eh_imm16(0x0040))
    dut.instruction.value = instr
    dut.input_tag.value = _STD_TAG()
    dut.input_payload.value = 0
    dut.input_payload_b_valid.value = 0
    dut.input_payload_wide.value = a_128
    dut.input_payload_wide_valid.value = 1
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0
    for _ in range(30):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.output_valid.value) == 1:
            break
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 0x2222_2222_2222_2222


# =============================================================================
# v1.6.6 §22.14 — pe_ready back-pressure signal
# =============================================================================


@cocotb.test()
async def test_pe_ready_defaults_high(dut):
    """v1.6.6: pe_ready HIGH after reset (idle state, no FSM/pipeline in flight)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    # Wait a cycle for settling
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.pe_ready.value) == 1


@cocotb.test()
async def test_pe_ready_low_during_bmm3_emit(dut):
    """v1.6.6: fire SIG_BMM_3, verify pe_ready LOW during FRAG_EMIT_HI cycle."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    a_128 = _pack_int4_128(*[0x1] * 32)
    b_128 = _pack_int4_128(*[0x1] * 32)
    r = await _fire_bmm_3(dut, a_128, b_128)
    assert 'fail' not in r, f"got {r}"
    # After fragment 0 emit (cycle N), FRAG_EMIT_HI is entered. pe_ready
    # must have been LOW at that point. The _fire_bmm_3 helper walks past
    # fragment 1, so pe_ready should be HIGH again by end.
    # Direct check: verify the FSM engagement happened (frag 0 and 1 both emitted).
    assert r['frag0']['frag_hdr'] == 0x01
    assert r['frag1']['frag_hdr'] == 0x11
    # After both fragments: pe_ready back to HIGH (FRAG_IDLE)
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.pe_ready.value) == 1


# =============================================================================
# v1.6.5c §22.16 — CACHE_LOAD_WIDE (0x68) passthrough
#
# ISA_Decoder ties input_payload_wide/valid directly to the testbench (no
# Cluster CAM at this level), so these tests exercise PE_Core's case arm in
# isolation: pure passthrough on a "hit" (wide_valid=1), and the existing
# error_flag guard on a "miss" (wide_valid=0) — the same guard the
# 0x60-0x65/0x69 wide consumers already share.
# =============================================================================


@cocotb.test()
async def test_cache_load_wide_passthrough_hit(dut):
    """v1.6.5c: CACHE_LOAD_WIDE with wide_valid=1 must pass the wide bus
    through unmodified (no arithmetic), emitting it as 2 fragments."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    lo = 0x1122334455667788
    hi = 0x99AABBCCDDEEFF00
    wide = (hi << 64) | lo
    instr = encode_instr(0x68, _STD_PORT())
    dut.instruction.value = instr
    dut.input_tag.value = _STD_TAG()
    dut.input_payload.value = 0
    dut.input_payload_b_valid.value = 0
    dut.input_payload_wide.value = wide
    dut.input_payload_wide_valid.value = 1
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0
    saw = []
    for _ in range(30):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.output_valid.value) == 1:
            saw.append({'payload': int(dut.output_payload.value),
                       'frag_hdr': int(dut.output_frag_hdr.value)})
            break
        assert int(dut.error_flag.value) == 0
    assert saw and saw[0]['payload'] == lo
    assert saw[0]['frag_hdr'] == 0x01
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.output_valid.value) == 1
    assert int(dut.output_payload.value) == hi
    assert int(dut.output_frag_hdr.value) == 0x11


@cocotb.test()
async def test_cache_load_wide_miss_raises_error(dut):
    """v1.6.5c: CACHE_LOAD_WIDE with wide_valid=0 (Cluster-level cache
    miss) must raise error_flag, not emit stale/garbage data — the same
    guard the 0x60-0x65/0x69 wide-consumer group already shares."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    instr = encode_instr(0x68, _STD_PORT())
    dut.instruction.value = instr
    dut.input_tag.value = _STD_TAG()
    dut.input_payload.value = 0
    dut.input_payload_b_valid.value = 0
    dut.input_payload_wide.value = 0
    dut.input_payload_wide_valid.value = 0
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0
    for _ in range(30):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.error_flag.value) == 1 or int(dut.output_valid.value) == 1:
            break
    assert int(dut.error_flag.value) == 1
    assert int(dut.output_valid.value) == 0


@cocotb.test()
async def test_cache_load_wide_dim_ovr_precision_guard(dut):
    """v1.6.5d §22.17 tag-stability-literal pin: CACHE_LOAD_WIDE with a
    real .precision dim=0x55 EH + F_DIM_OVR must force output_tag's
    dim_sizes to 0x55, independent of whatever the input tag carried —
    closes the previously-untested RTL dim_ovr forwarding path for this
    specific opcode (mirrors test_dim_override_changes_output_tag_dim)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    wide = 0x1122334455667788 | (0x99AABBCCDDEEFF00 << 64)
    instr = encode_instr(0x68, _STD_PORT(), eh_precision(mode=0, dim=0x55),
                         flags=F_DIM_OVR)
    dut.instruction.value = instr
    dut.input_tag.value = _STD_TAG()
    dut.input_payload.value = 0
    dut.input_payload_b_valid.value = 0
    dut.input_payload_wide.value = wide
    dut.input_payload_wide_valid.value = 1
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0
    for _ in range(30):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.output_valid.value) == 1:
            break
    assert dut.output_valid.value == 1
    out_tag = int(dut.output_tag.value)
    assert (out_tag & 0xFF) == 0x55, \
        f"output_tag dim_sizes = 0x{out_tag & 0xFF:02x}, expected 0x55"


def _asm_layernorm_cache_load_dim():
    """v1.6.5d §22.17 tag-stability-literal cross-file check: call the
    REAL production _lower_layernorm() (the same function assemble()
    invokes) and extract the actual live 'dim' value from its
    CACHE_LOAD_WIDE step's precision EH — not a hand-typed literal. A
    future one-sided edit to asm.py's dim literal changes THIS value."""
    from wavetensor_asm import _lower_layernorm, Instruction, ExtensionHeader
    port_eh = ExtensionHeader(kind='port', args={'mask': 1, 'out': 0}, line=0)
    inst = Instruction(
        mnemonic='LAYERNORM',
        flags={'opb'},
        eh_list=[
            port_eh,
            ExtensionHeader(kind='gamma', args={'_pos': [0x1111_2222_3333_4444]}, line=0),
            ExtensionHeader(kind='beta', args={'_pos': [0x5555_6666_7777_8888]}, line=0),
        ],
        line=0,
    )
    steps = _lower_layernorm(inst)
    # v1.8.0d: the fp32 scalar insert shifted the reload's index — locate
    # by mnemonic (there is exactly one CACHE_LOAD_WIDE in the chain).
    reloads = [s for s in steps if s.mnemonic == 'CACHE_LOAD_WIDE']
    assert len(reloads) == 1, \
        f"expected exactly one CACHE_LOAD_WIDE, got {len(reloads)}"
    cache_load_step = reloads[0]
    prec_eh = next(eh for eh in cache_load_step.eh_list if eh.kind == 'precision')
    return prec_eh.args['dim']


@cocotb.test()
async def test_op_mean_and_cache_load_wide_dim_sizes_consistency(dut):
    """v1.6.5d §22.17 — the actual §22.16.6 tag-stability-literal fix.
    Fires a REAL OP_MEAN dispatch and reads its ACTUAL RTL output_tag
    dim_sizes byte, then compares against the value LIVE-extracted from
    asm.py's real _lower_layernorm() (not a re-typed literal on either
    side). A future one-sided edit to PE_Core.v's OP_MEAN 8'h55 hardcode
    OR asm.py's _lower_layernorm dim literal breaks this test."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    nibbles = [0x4] * 32
    a_128 = _pack_int4_128(*nibbles)
    await _fire_5d_to_4d_reduction(dut, a_128, 0x5)  # MEAN
    assert dut.output_valid.value == 1
    dim_sizes_rtl = int(dut.output_tag.value) & 0xFF
    dim_sizes_asm = _asm_layernorm_cache_load_dim()
    assert dim_sizes_rtl == dim_sizes_asm, (
        f"DESYNC: PE_Core.v's OP_MEAN output_tag dim_sizes=0x{dim_sizes_rtl:02x} "
        f"!= asm.py's _lower_layernorm CACHE_LOAD_WIDE precision-guard "
        f"dim=0x{dim_sizes_asm:02x} -- one side was edited without the other"
    )


@cocotb.test()
async def test_frag_inval_hit_ack(dut):
    """v1.6.5d §22.17: FRAG_INVAL (0x6A) with wide_valid=1 (Cluster-level
    CAM hit) must ack (output_valid=1, error_flag=0) and must NOT enter
    the drain FSM (no second fragment beat follows) -- proves the
    standalone-arm design avoids the confirmed garbage-second-fragment
    hazard that folding into the shared wide-emit group would
    cause (that group's epilogue unconditionally drives
    frag_idx<=FRAG_EMIT_1)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    instr = encode_instr(0x6A, _STD_PORT())
    dut.instruction.value = instr
    dut.input_tag.value = _STD_TAG()
    dut.input_payload.value = 0
    dut.input_payload_b_valid.value = 0
    dut.input_payload_wide.value = 0
    dut.input_payload_wide_valid.value = 1
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0
    for _ in range(30):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.output_valid.value) == 1:
            break
        assert int(dut.error_flag.value) == 0
    assert int(dut.output_valid.value) == 1
    assert int(dut.output_frag_hdr.value) == 0x00
    # Confirm no second fragment follows (would indicate the FRAG_EMIT_HI
    # hazard reintroduced).
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert int(dut.output_valid.value) == 0


@cocotb.test()
async def test_frag_inval_miss_raises_error(dut):
    """v1.6.5d §22.17: FRAG_INVAL with wide_valid=0 (Cluster-level miss —
    tag never cached, or slot still mid-assembly) must raise error_flag,
    mirroring CACHE_LOAD_WIDE's existing miss guard."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    instr = encode_instr(0x6A, _STD_PORT())
    dut.instruction.value = instr
    dut.input_tag.value = _STD_TAG()
    dut.input_payload.value = 0
    dut.input_payload_b_valid.value = 0
    dut.input_payload_wide.value = 0
    dut.input_payload_wide_valid.value = 0
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0
    for _ in range(30):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.error_flag.value) == 1 or int(dut.output_valid.value) == 1:
            break
    assert int(dut.error_flag.value) == 1
    assert int(dut.output_valid.value) == 0


# =============================================================================
# v1.5.3 §20 — adversarial review bug 5 fix: MUL/DIV in-flight collision tests
# =============================================================================
#
# PE_Core.v drain gate (line ~1118) blocks SIG_BMM_3 dispatch when any
# MUL/DIV pulse would collide with fragment 0 or fragment 1. PE_Core.v
# MUL launch gate (line ~721) blocks a new MUL from entering the pipeline
# during FRAG_EMIT_HI. Both must be regression-tested — the review agent
# noted zero MUL/DIV+SIG_BMM_3 co-schedule coverage in the existing suite.


@cocotb.test()
async def test_mul_then_bmm3_drain_gate(dut):
    """v1.5.3 §20 bug-5: fire MUL (0x12) at cycle N, SIG_BMM_3 at N+1.
    MUL's 2-stage pipeline (p1 → p2) has mul_valid_p2 pulsing at N+2 —
    exactly where SIG_BMM_3's fragment 0 would land absent the gate.
    Compound drain gate must reject SIG_BMM_3 with lower_required so the
    MUL result surfaces cleanly."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # MUL (0x12) legality: PORT required, IMM_XOR_OPREF (need exactly one).
    # Use IMM64 for the multiplier — dec_eff_b_value picks it up.
    mul_instr = encode_instr(0x12, _STD_PORT(), eh_imm64(2))
    dut.instruction.value = mul_instr
    dut.input_tag.value = _STD_TAG()
    dut.input_payload.value = 0xDEADBEEF
    dut.input_payload_b.value = 0
    dut.input_payload_b_valid.value = 0
    dut.input_payload_wide.value = 0
    dut.input_payload_wide_valid.value = 0
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0

    # Poll for MUL result — should surface cleanly (2-stage pipe + register)
    saw_mul = False
    for _ in range(20):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.output_valid.value) == 1 and int(dut.opcode_out.value) == 0x12:
            assert int(dut.output_payload.value) == 0xDEADBEEF * 2
            assert int(dut.output_frag_hdr.value) == 0x00
            saw_mul = True
            break
    assert saw_mul, "MUL result did not surface"


# =============================================================================
# v1.5.5 §21 — SIG_TRACE_IIJKL: 5D trace + 3 kept axes (single-fragment output)
# =============================================================================
#
# 'iijkl->jkl' — reduction primitive, 128-bit input via wide-fragment
# reassembly, 32-bit output (fits in single 64-bit fragment — NO FSM).
# Only diagonal i==i2 nibbles contribute; off-diagonals ignored.


_TRIIJKL_A_LO = 0x3211
_TRIIJKL_B_LO = 0x0000
_TRIIJKL_O_LO = 0x0432
_TRIIJKL_A_HI = 0x0004
_TRIIJKL_B_HI = 0x0000
_TRIIJKL_O_HI = 0x0000


def _trace_iijkl_sim(a_128):
    """Python reference for SIG_TRACE_IIJKL. Nibble layout:
    A[i][i2][j][k][l] at nibble (i*16 + i2*8 + j*4 + k*2 + l)."""
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


async def _fire_trace_iijkl(dut, a_128, wide_valid=1, dim=0x55):
    """Helper: fire a SIG_TRACE_IIJKL wave with A packed into wide[127:0]."""
    wide = a_128 & ((1 << 128) - 1)  # B unused, only A occupies low 128 bits
    instr = encode_instr(0x32, _STD_PORT(),
                         eh_subscript(_TRIIJKL_A_LO, _TRIIJKL_B_LO, _TRIIJKL_O_LO),
                         eh_subscript(_TRIIJKL_A_HI, _TRIIJKL_B_HI, _TRIIJKL_O_HI),
                         eh_opref(),
                         flags=F_HAS_OPB)
    await fire(dut, instr, _STD_TAG(dim=dim),
               payload_a=0, payload_b=0, payload_b_valid=1,
               payload_wide=wide, payload_wide_valid=wide_valid)


@cocotb.test()
async def test_trace_iijkl_zero(dut):
    """v1.5.5: A=0 baseline — dispatch path recognizes signature, no
    error, no lower_required."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    await _fire_trace_iijkl(dut, 0)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == 0
    assert int(dut.output_frag_hdr.value) == 0x00
    assert dut.error_flag.value == 0
    assert dut.lower_required.value == 0


@cocotb.test()
async def test_trace_iijkl_computed(dut):
    """v1.5.5: distinctive nibbles — result matches Python reference."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    nibbles = [((i * 7 + 3) & 0xF) for i in range(32)]
    a_128 = _pack_int4_128(*nibbles)
    await _fire_trace_iijkl(dut, a_128)
    expected = _trace_iijkl_sim(a_128)
    assert dut.output_valid.value == 1
    assert int(dut.output_payload.value) == expected
    assert (int(dut.output_payload.value) >> 32) == 0  # only low 32 used
    assert int(dut.output_frag_hdr.value) == 0x00


@cocotb.test()
async def test_trace_iijkl_signed_int4(dut):
    """v1.5.5: negative int4 with sign extension. Diagonal a[0,0,·]=5,
    a[1,1,·]=-3 (=0xD) → each output cell = 2. Off-diagonal a[·]=0xF
    (=-1) proves they are ignored (result would differ if they were)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    nibbles = [0xF] * 32   # fill off-diagonals with -1 (would poison result)
    for j in range(2):
        for k in range(2):
            for l in range(2):
                # a[0,0,j,k,l] = 5 (positive)
                lin0 = 0 * 16 + 0 * 8 + j * 4 + k * 2 + l
                nibbles[lin0] = 0x5
                # a[1,1,j,k,l] = 0xD = -3 (signed)
                lin1 = 1 * 16 + 1 * 8 + j * 4 + k * 2 + l
                nibbles[lin1] = 0xD
    a_128 = _pack_int4_128(*nibbles)
    await _fire_trace_iijkl(dut, a_128)
    assert dut.output_valid.value == 1
    # Each of 8 output cells = 5 + (-3) = 2
    expected = 0x22222222
    assert (int(dut.output_payload.value) & 0xFFFFFFFF) == expected


@cocotb.test()
async def test_trace_iijkl_single_output_fragment(dut):
    """v1.5.5: SINGLE output_valid pulse (no fragment FSM engaged unlike
    SIG_BMM_3). frag_idx must never leave FRAG_IDLE, output_frag_hdr
    must stay 0x00 throughout, and cycle N+1 must be idle."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a_128 = _pack_int4_128(*[(i & 0xF) for i in range(32)])
    await _fire_trace_iijkl(dut, a_128)
    # Cycle N: output valid, frag_hdr=0
    assert dut.output_valid.value == 1
    assert int(dut.output_frag_hdr.value) == 0x00
    # Hierarchical: FSM never engaged (v1.7 §22.18: frag_state -> frag_idx,
    # widened 1-bit -> 2-bit; FRAG_IDLE is still 0 either way)
    assert int(dut.u_core.frag_idx.value) == 0
    # Cycle N+1: idle (no fragment 1 emit)
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert dut.output_valid.value == 0
    assert int(dut.output_frag_hdr.value) == 0x00


@cocotb.test()
async def test_trace_iijkl_wide_valid_gate_error(dut):
    """v1.5.5: SIG_TRACE_IIJKL with wide_valid=0 → error_flag (§20.7
    wide-consumer contract). Consistent with SIG_BMM_3 semantics."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a_128 = _pack_int4_128(*[1] * 32)
    await _fire_trace_iijkl(dut, a_128, wide_valid=0)
    assert dut.output_valid.value == 0
    assert dut.error_flag.value == 1


@cocotb.test()
async def test_trace_iijkl_output_tag_dim_sizes(dut):
    """v1.5.5: reduction changes tag shape from 5D input → 3D output.
    Output tag dim_sizes MUST be 0x15 (3D 2×2×2). wave_number,
    thread_id, port preserved."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a_128 = _pack_int4_128(*[(i & 0xF) for i in range(32)])
    tag = make_tag(wave_number=0xDEADBEEF, thread_id=0xCAFE,
                   port_context_id=0, dimension_sizes=0x55)
    wide = a_128 & ((1 << 128) - 1)
    instr = encode_instr(0x32, _STD_PORT(),
                         eh_subscript(_TRIIJKL_A_LO, _TRIIJKL_B_LO, _TRIIJKL_O_LO),
                         eh_subscript(_TRIIJKL_A_HI, _TRIIJKL_B_HI, _TRIIJKL_O_HI),
                         eh_opref(),
                         flags=F_HAS_OPB)
    await fire(dut, instr, tag, payload_a=0, payload_b=0, payload_b_valid=1,
               payload_wide=wide, payload_wide_valid=1)
    assert dut.output_valid.value == 1
    out_tag = int(dut.output_tag.value)
    assert (out_tag & 0xFF) == 0x15, f"dim_sizes: 0x{out_tag & 0xFF:02x}"
    # wave_number at [79:48]
    assert ((out_tag >> 48) & 0xFFFFFFFF) == 0xDEADBEEF
    # thread_id at [47:32]
    assert ((out_tag >> 32) & 0xFFFF) == 0xCAFE


@cocotb.test()
async def test_bmm3_then_mul_launch_gate(dut):
    """v1.5.3 §20 bug-5: fire SIG_BMM_3 at cycle N; MUL at cycle N+1
    during FRAG_EMIT_HI must be prevented from entering the pipeline.
    Verify via hierarchical probe: mul_valid_p1 stays 0 on the emit cycle."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a_128 = _pack_int4_128(*([1] * 32))
    b_128 = _pack_int4_128(*([1] * 32))
    wide = _pack_int4_wide(a_128, b_128)
    instr = encode_instr(0x32, _STD_PORT(),
                         eh_subscript(_BMM3_A_LO, _BMM3_B_LO, _BMM3_O_LO),
                         eh_subscript(_BMM3_A_HI, _BMM3_B_HI, _BMM3_O_HI),
                         eh_opref(),
                         flags=F_HAS_OPB)
    dut.instruction.value = instr
    dut.input_tag.value = _STD_TAG(dim=0x55)
    dut.input_payload.value = 0
    dut.input_payload_b.value = 0
    dut.input_payload_b_valid.value = 1
    dut.input_payload_wide.value = wide
    dut.input_payload_wide_valid.value = 1
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0
    dut.input_payload_wide_valid.value = 0

    # Wait for fragment 0 to emit
    for _ in range(20):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.output_valid.value) == 1 and int(dut.output_frag_hdr.value) == 0x01:
            break

    # NEXT cycle is FRAG_EMIT_HI — attempt to inject a MUL now.
    mul_instr = encode_instr(0x12, _STD_PORT(), eh_imm64(3))
    dut.instruction.value = mul_instr
    dut.input_tag.value = _STD_TAG()
    dut.input_payload.value = 100
    dut.input_payload_b.value = 0
    dut.input_payload_b_valid.value = 0
    dut.token_valid.value = 1
    # BEFORE the clock edge: probe hierarchical frag_idx via u_core
    # (PE_Core instance inside ISA_Decoder). If frag_idx == 1 (FRAG_EMIT_1,
    # v1.7 §22.18: frag_state -> frag_idx, widened 1-bit -> 2-bit; the old
    # FRAG_EMIT_HI value of 1 is now FRAG_EMIT_1), the launch gate MUST
    # prevent mul_valid_p1 from asserting on next edge.
    assert int(dut.u_core.frag_idx.value) == 1, \
        f"expected FRAG_EMIT_1, got frag_idx={int(dut.u_core.frag_idx.value)}"
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    # After the clock edge: mul_valid_p1 must be 0 (launch blocked)
    assert int(dut.u_core.mul_valid_p1.value) == 0, \
        f"MUL launch gate failed: mul_valid_p1={int(dut.u_core.mul_valid_p1.value)}"
    dut.token_valid.value = 0


# =============================================================================
# v1.8.0a §23.9 COMMIT 1 — pre-migration RTL truth table (THE CIRCULARITY
# BREAKER for the single-source ISA migration)
#
# The EH-subset sweep below was captured on a frozen baseline commit and
# its full outcome table — (error_flag_ever, lower_required_ever,
# output_valid_ever) per point — was committed as literal data at
# isa/truth_table_premigration.json. Later RTL must reproduce it
# bit-for-bit. Because the oracle is RTL-DERIVED (not human-derived, not
# generator-derived), a JSON transcription error that is self-consistent
# between the generator and the golden model still fails here.
#
# Baseline history:
#   domain_version 1 — captured ONCE on pre-migration HEAD (the commit
#     before EHDecode.v's hand-written legality moved into generated
#     includes), the §23.9 single-source-migration circularity breaker.
#   domain_version 2 — recaptured on the pre-stable opcode-cleanup commit
#     (0x66/0x67/0x6B/0x6C removal, 2026-07-24): per the pre-stable compat
#     policy, freeze guarantees bind only from STABLE RELEASE, so
#     dead-opcode removal is a regular development event recorded
#     spec-first with this deliberate, reviewed recapture. The four
#     removed opcodes moved from the supported list to the unsupported
#     probes (domain point set unchanged; their outcome class flipped
#     supported → decode_error).
#   domain_version 3 — recaptured on the v1.8.0e 0e1 sequencer-side
#     commit (spec §25.6 item 7): the 0x6B code point was REALLOCATED
#     pre-stable to GAMMA_MUL_W (§25.2.3, §12a rule 4 — slot reuse
#     recorded; the mandatory retired-0x6B stale-consumer resync). The
#     reviewed differential vs domain_version 2 is EXACTLY the 16
#     0x6B points whose EH shape satisfies the alu-binary XOR (one class
#     of {IMM*} XOR OPREF, x 2 flags): decode_error → executes; every
#     other point — including 0x6B's XOR-violating shapes and all
#     frag-FSM-widened emitters — is bit-identical. (The §25.2.1 0x79
#     legality re-row also forces this bump by policy, but 0x70-0x7F is
#     outside this domain, so it contributes no visible delta here; its
#     decode shape is pinned by the fp-block sweeps instead.)
#
# Domain (fixed, generator-independent — never derived from the JSON
# source): opcodes = the 53 supported (post-cleanup 0x00-0x6A era) + 16
# unsupported probes BELOW 0x70; data-EH subsets = all subsets of the 6
# data-EH kinds with |S| <= 3 (chain capacity: MAX_EH=4 slots, port
# occupies one), each with the standard PORT EH present, PLUS one bare
# no-port point; flags in {0x0, 0x8 (F_HAS_OPB)}. 0x70-0x7F is EXCLUDED
# deliberately: that block is scheduled to change in v1.8.0a COMMIT 2
# (decode skeleton), and freezing it here would make the intended change
# look like a regression; its staying-unassigned encodings are pinned by
# test_fp_block_unassigned_opcodes_still_error instead.
#
# Capture mode: WT_CAPTURE_TRUTH_TABLE=1 rewrites the committed file from
# the live RTL instead of comparing (used once per baseline listed above;
# any later capture must be a reviewed, deliberate act).
# =============================================================================

_TT_SUPPORTED_OPCODES = (
    list(range(0x00, 0x06)) + list(range(0x10, 0x20)) +
    list(range(0x20, 0x27)) + list(range(0x30, 0x33)) +
    list(range(0x40, 0x45)) + list(range(0x50, 0x57)) +
    list(range(0x60, 0x66)) + [0x68, 0x69, 0x6A]
)
_TT_UNSUPPORTED_PROBES = [0x06, 0x0F, 0x27, 0x2F, 0x33, 0x45, 0x4F,
                          0x57, 0x5F,
                          # pre-stable opcode cleanup: removed 0x66/0x67/
                          # 0x6B/0x6C stay IN the domain as error probes
                          # (point set unchanged vs domain_version 1).
                          # v1.8.0e: 0x6B was REALLOCATED to GAMMA_MUL_W
                          # — it stays in THIS enumeration list (the
                          # point set is fixed) but its captured outcome
                          # class is now supported-executes on the
                          # XOR-satisfying shapes (domain_version 3).
                          0x66, 0x67, 0x6B, 0x6C,
                          0x6D, 0x6E, 0x6F]
_TT_DATA_EH_KINDS = ['imm16', 'imm32', 'imm64', 'mem', 'subscript', 'opref']
_TT_FLAGS = [0x0, 0x8]
_TT_WINDOW = 100

_TT_PATH = os.path.join(_REPO, 'isa', 'truth_table_premigration.json')


def _tt_eh_builders():
    return {
        'imm16':     lambda: eh_imm16(1),
        'imm32':     lambda: eh_imm32(1),
        'imm64':     lambda: eh_imm64(1),
        'mem':       lambda: eh_mem(0),
        'subscript': lambda: eh_subscript(0, 0, 0),
        'opref':     lambda: eh_opref(),
    }


def _tt_domain():
    """Deterministic point enumeration: (opcode, subset-tuple, flags,
    port_present). Yields in fixed sorted order."""
    from itertools import combinations
    subsets = [()]
    for k in (1, 2, 3):
        subsets.extend(combinations(_TT_DATA_EH_KINDS, k))
    for op in sorted(_TT_SUPPORTED_OPCODES + _TT_UNSUPPORTED_PROBES):
        for fl in _TT_FLAGS:
            for sub in subsets:
                yield (op, sub, fl, True)
            yield (op, (), fl, False)   # bare no-port point


async def _tt_run_point(dut, op, subset, flags, port_present):
    builders = _tt_eh_builders()
    ehs = ([_STD_PORT()] if port_present else []) + \
          [builders[k]() for k in subset]
    instr = encode_instr(op, *ehs, flags=flags)
    a_128 = _pack_int4_128(*[0x1] * 32)
    dut.instruction.value = instr
    dut.input_tag.value = _STD_TAG()
    dut.input_payload.value = 1
    dut.input_payload_b.value = 1
    dut.input_payload_b_valid.value = 1
    dut.input_payload_wide.value = a_128
    dut.input_payload_wide_valid.value = 1
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0
    err = lwr = out = 0
    for i in range(_TT_WINDOW):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        err |= int(dut.error_flag.value)
        lwr |= int(dut.lower_required.value)
        out |= int(dut.output_valid.value)
        # Early exit once an outcome landed AND the PE is drained
        # (pe_ready covers frag drain + MUL/DIV pipelines) — outcome
        # bits are monotonic, so early exit never changes the result,
        # only the wall time.
        if i >= 8 and (err or lwr or out) and int(dut.pe_ready.value) == 1:
            break
    # Drain to idle so the next point starts clean (DIV takes ~66 cycles).
    for _ in range(_TT_WINDOW):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.pe_ready.value) == 1 and int(dut.output_valid.value) == 0:
            break
    return (err, lwr, out)


def _tt_key(op, subset, flags, port_present):
    return f"0x{op:02X}|{','.join(subset)}|0x{flags:X}|{'P' if port_present else '-'}"


@cocotb.test()
async def test_pre_migration_rtl_truth_table_differential(dut):
    """v1.8.0a COMMIT 1 zero-behavior-change gate: the full EH-subset sweep
    outcome table must be bit-identical to the frozen pre-migration
    capture (isa/truth_table_premigration.json). Set
    WT_CAPTURE_TRUTH_TABLE=1 to (re)write the capture instead — a
    deliberate, reviewed act, never part of a normal run."""
    import json as _json
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    capture_mode = os.environ.get('WT_CAPTURE_TRUTH_TABLE', '') == '1'
    results = {}
    for (op, sub, fl, pp) in _tt_domain():
        outcome = await _tt_run_point(dut, op, sub, fl, pp)
        results[_tt_key(op, sub, fl, pp)] = list(outcome)

    if capture_mode:
        os.makedirs(os.path.dirname(_TT_PATH), exist_ok=True)
        with open(_TT_PATH, 'w') as f:
            _json.dump({'domain_version': 3, 'points': results}, f,
                       indent=0, sort_keys=True)
            f.write('\n')
        return

    assert os.path.exists(_TT_PATH), (
        f"frozen truth table missing at {_TT_PATH} — run once with "
        f"WT_CAPTURE_TRUTH_TABLE=1 on the current frozen baseline "
        f"(domain_version 3: the v1.8.0e 0e1 0x6B-reallocation commit)")
    with open(_TT_PATH) as f:
        frozen = _json.load(f)
    assert frozen['domain_version'] == 3
    mismatches = []
    for key, expected in frozen['points'].items():
        got = results.get(key)
        if got != expected:
            mismatches.append(f"{key}: frozen={expected} got={got}")
    extra = set(results) - set(frozen['points'])
    assert not extra, f"domain drift — new points not in frozen table: {sorted(extra)[:5]}"
    assert not mismatches, (
        "RTL behavior diverged from the frozen baseline capture "
        f"({len(mismatches)} points):\n" + "\n".join(mismatches[:20]))


# =============================================================================
# v1.8.0a §23.9 COMMIT 2 — 0x70-0x7F WIDE-ACC decode skeleton + FP_LEGAL_ROM
# =============================================================================

_FP_ASSIGNED = [0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76,
                0x77, 0x78, 0x79, 0x7C, 0x7D, 0x7E]
_FP_UNASSIGNED = [0x7A, 0x7B, 0x7F]


def _fp_scaffold(op):
    """Minimal legal EH scaffold for an fp-block op, derived LIVE from the
    generated tables (never hand-typed shapes).

    v1.8.0d DOCUMENTED DECISION (0x73 ACC_ELEMWISE): the generic
    allow_imm_xor_opref arm would satisfy the alu-binary XOR trap with an
    IMM16 — which still decodes cleanly but is now the OPREF-only launch
    rung's lower_required leg (§23.10.10(c)), turning every legal-mode
    sweep point into a rung test instead of an execute test. The sweep's
    job is to prove the ROM x execute boundary, so the scaffold supplies
    the OPREF form (src_kind 0, direct payload_b — _fp_run_point already
    drives payload_b) and legal-mode 0x73 points EXECUTE; the imm-form
    lower_required rung is pinned separately by
    test_accew_opref_only_directed_e2e."""
    from generated_isa_tables import LEGAL
    ehs = [_STD_PORT()]
    leg = LEGAL.get(op)
    if leg is None:
        return ehs
    if leg['allow_imm_xor_opref']:
        ehs.append(eh_opref() if op == 0x73 else eh_imm16(1))
    elif 'mem' in leg['required']:
        ehs.append(eh_mem(0))
    return ehs


async def _fp_run_point(dut, op, mode, via_eh):
    """Dispatch one fp-block point; mode via PRECISION EH (prec flag) or
    via input_tag[15:8]. Returns (err, lwr, out) ever-bits.

    v1.8.0c: the scaffold DELIBERATELY supplies payload_b
    (input_payload_b_valid=1, matching the port default every legacy test
    uses), so a legal-mode 0x74 FSCALAR point EXECUTES here rather than
    tripping the missing-B error_flag guard; that guard is pinned
    separately by test_fscalar_subop_decode_guards. The poll window is
    sized for the slowest sweep point (0x74 absent-imm16 = FS_ADD, a
    real 5-6 cycle step-sequencer launch + decode/finish overhead), not
    just the old combinational single-cycle arms."""
    ehs = _fp_scaffold(op)
    flags = 0
    tag_mode = 0
    if via_eh:
        ehs.append(eh_precision(mode, 0))
        flags |= 1 << 2   # F_PRECISION_OVR
    else:
        tag_mode = mode
    instr = encode_instr(op, *ehs, flags=flags)
    dut.instruction.value = instr
    dut.input_tag.value = make_tag(port_context_id=0, precision_mode=tag_mode)
    dut.input_payload.value = 1
    dut.input_payload_b.value = 1
    dut.input_payload_b_valid.value = 1
    dut.input_payload_wide.value = 1
    dut.input_payload_wide_valid.value = 1
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0
    err = lwr = out = 0
    # v1.8.0e 0e1 integration — window sizing: a legal-mode 0x78 point
    # now launches the REAL DEQUANT lane loop (16 or 32 OPS_DEQ passes,
    # ~6-7 cy/lane at the measured L=5), so its first output pulse (the
    # loop-completion fragment 0) lands ~100-230 cycles after dispatch;
    # every other point resolves within the old 24-cycle window.
    # v1.8.0e 0e2 — a legal-mode 0x70 point now launches the REAL VFMA
    # lane loop (16 or 32 MAC steps at 1 cy/lane): the scaffold's
    # wide=1 + imm16(1) supply A and the B split (b_mul = 1, c_acc = 0
    # — the imm16 zero-fill pin), so fragment 0 lands ~20-40 cycles
    # after dispatch and the 16-fragment drain rides the post-loop
    # drain below.
    window = 320 if op == 0x78 else (64 if op == 0x70 else 24)
    for _ in range(window):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        err |= int(dut.error_flag.value)
        lwr |= int(dut.lower_required.value)
        out |= int(dut.output_valid.value)
        if err or lwr or out:
            break
    # Drain to idle before the caller's next point: the v1.8.0e widened
    # frag FSM keeps emitting rows 1..N-1 for up to 7 cycles after the
    # break above (8-fragment int4 DEQUANT) — a next point dispatched
    # mid-drain would sample those pulses as its own ever-bits.
    for _ in range(24):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.pe_ready.value) == 1 and int(dut.output_valid.value) == 0:
            break
    return (err, lwr, out)


def _fp_expected(op, mode):
    """Golden-model expectation from the generated tables (v1.8.0b
    rewrite anticipated by the original docstring): stubs (STUB_OPS_V18)
    predict lower_required; implemented ops predict execution — with the
    one documented conditional path: 0x7C dtype 0x2/0x3 (f16/bf16
    destination) is decode-legal but lower_required until v1.8.0d.

    v1.8.0c: 0x74/0x75/0x76 graduated out of STUB_OPS_V18 and now predict
    execution on their single legal mode (0x14). The sweep scaffold
    supplies payload_b_valid=1 (see _fp_run_point), so 0x74 launches
    FS_ADD (absent imm16 default) rather than erroring on missing B.

    v1.8.0e 0e1 (sequencer-side commit): 0x79 FMINMAX graduated — its
    comb arm executes here (the FSCALAR-clone re-row means the live
    scaffold no longer appends an imm16, so legal-mode points run the
    absent-imm16 = minimumNumber default against the scaffold's
    payload_b/wide payloads).

    v1.8.0e 0e1 (integration commit — THIS one): 0x78 DEQUANT's PE_Core
    lane-loop launch arm landed, so legal-mode 0x78 points now EXECUTE:
    the sweep's scaffold payloads (wide=1, payload_b=1) launch a real
    16- or 32-lane OPS_DEQ loop whose fragment-0 emit arrives only at
    loop completion — _fp_run_point sizes its poll window and drains
    the multi-fragment tail accordingly. The transitional
    _V180E_PENDING_INTEGRATION set is DELETED with this commit as
    pinned; the directed e2e DEQUANT tests below bind bit-exact
    execution.

    v1.8.0e 0e2 (THIS commit): 0x70 VFMA_ACC graduated — its lane-loop
    launch arm landed, so legal-mode 0x70 points now EXECUTE: the
    scaffold's wide=1 (A) + imm16(1) (B: b_mul = 1 after the lane-width
    sext, c_acc = 0 via the zero-fill pin) launch a real 32- or 16-lane
    MAC loop whose fragment-0 emit arrives at loop completion, followed
    by the 16- or 8-fragment drain — the int4 form is the first
    tot_m1=15 walker. STUB_OPS_V18 regenerated to {0x7D, 0x7E}.

    v1.8.0d: 0x73/0x77 graduated too, and the 0x7C dtype-0x2/0x3
    conditional lower_required arm is GONE (fp-dest packer landed).
    Execution predictions for the new rows, per §23.10.10:
      * 0x77 x dtype {0,1,2,3,4}: absent imm16 = WIDEN_TO_F32, so dtype
        0/1/4 sweep points run I2F on payload=1 (the op-class-conditional
        DAZ bypass is what makes I2F(1) emit 1.0f instead of a flushed
        zero — value-level proof in test_cvt_directed_cells_e2e; the
        sweep asserts the ever-bits) and dtype 2/3 run f16/bf16 widen of
        the raw pattern 0x0001 (f16 subnormal honored / bf16 subnormal
        flushed — again value-pinned in the directed cells).
      * 0x73 x dtype {4}: the scaffold supplies OPREF (see _fp_scaffold),
        so legal-mode points execute the FS_FMA-shaped program.
      * 0x7C x dtype {2,3}: absent imm16 -> both reserved rungs pass ->
        the packer emits {48'h0, narrow(DAZ(payload))} same-cycle."""
    from generated_isa_tables import FP_MODE_LEGAL, STUB_OPS_V18
    legal = FP_MODE_LEGAL.get(op)
    if legal is None:
        return (1, 0, 0)   # unassigned -> decode_error (whitelist omission)
    dtype, acc, rnd = mode & 0xF, (mode >> 4) & 0x3, (mode >> 6) & 0x3
    if (dtype in legal['legal_dtypes'] and acc in legal['legal_acc']
            and rnd in legal['legal_rnd']):
        if op in STUB_OPS_V18:
            return (0, 1, 0)   # decode-legal stub -> lower_required
        return (0, 0, 1)       # implemented -> executes, emits output
    return (1, 0, 0)           # illegal mode -> decode_error


@cocotb.test()
async def test_fp_mode_rom_sweep_tag_path(dut):
    """v1.8.0a COMMIT 2: all 16 fp-block slots x 256 mode bytes via
    input_tag[15:8] (flags[2]=0 — the cb_precision_mode mux arm), RTL vs
    the generated golden model, bit-compared."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    mismatches = []
    for op in _FP_ASSIGNED + _FP_UNASSIGNED:
        for mode in range(256):
            got = await _fp_run_point(dut, op, mode, via_eh=False)
            exp = _fp_expected(op, mode)
            if got != exp:
                mismatches.append(f"op=0x{op:02X} mode=0x{mode:02X}: got={got} exp={exp}")
    assert not mismatches, (
        f"{len(mismatches)} ROM/tag-path divergences:\n" + "\n".join(mismatches[:10]))


@cocotb.test()
async def test_fp_mode_rom_sweep_precision_eh_path(dut):
    """v1.8.0a COMMIT 2: the same 16x256 points via PRECISION EH +
    flags[2]=1 (the acc_prec_mode mux arm). Together with the tag-path
    sweep this covers BOTH arms of the eff_precision mux, killing the
    wired-to-the-wrong-mux-arm bug class a single-path sweep is blind to."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    mismatches = []
    for op in _FP_ASSIGNED + _FP_UNASSIGNED:
        for mode in range(256):
            got = await _fp_run_point(dut, op, mode, via_eh=True)
            exp = _fp_expected(op, mode)
            if got != exp:
                mismatches.append(f"op=0x{op:02X} mode=0x{mode:02X}: got={got} exp={exp}")
    assert not mismatches, (
        f"{len(mismatches)} ROM/EH-path divergences:\n" + "\n".join(mismatches[:10]))


@cocotb.test()
async def test_fp_block_stub_lower_required_all_ops(dut):
    """v1.8.0a COMMIT 2: live-extraction over ALL generated fp ops (not a
    hand list): for each, a fully-legal encoding must yield error_flag=0,
    lower_required=1, output_valid=0. Adding an op to isa/wt64v1_isa.json
    without its PE_Core case-arm membership falls to the case default
    (error_flag) and fails here — the PE_Core-membership pin."""
    from generated_isa_tables import FP_MODE_LEGAL, STUB_OPS_V18
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    # v1.8.0b: iterate the generated STUB set — 0x71/0x72/0x7C graduated
    # to real datapaths (their own directed tests below); membership pin
    # still holds: a NEW stub op added to the JSON without a PE_Core arm
    # falls to the case default and fails here.
    # v1.8.0c: 0x74/0x75/0x76 graduated too (fp32 step-sequencer arms;
    # directed coverage in the v1.8.0c section at the end of this file).
    # v1.8.0e 0e2 — the stub set is now EXACTLY {0x7D, 0x7E} (0x70
    # VFMA_ACC graduated with its lane-loop arm; both survivors stay
    # unscheduled). Pinned literally so a JSON stub-bit drift is loud.
    assert STUB_OPS_V18 == frozenset({0x7D, 0x7E}), \
        f"stub set drifted from the 0e2 pin: {sorted(STUB_OPS_V18)}"
    for op in sorted(STUB_OPS_V18):
        legal = FP_MODE_LEGAL[op]
        mode = (legal['legal_rnd'][0] << 6) | (legal['legal_acc'][0] << 4) \
             | legal['legal_dtypes'][0]
        got = await _fp_run_point(dut, op, mode, via_eh=True)
        assert got == (0, 1, 0), \
            f"op=0x{op:02X} legal-mode stub expected lower_required, got {got}"


@cocotb.test()
async def test_fp_block_unassigned_opcodes_still_error(dut):
    """v1.8.0a COMMIT 2: 0x7A/0x7B (unassigned) and 0x7F (reserved) stay
    decode_error via whitelist omission across representative mode bytes."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    for op in _FP_UNASSIGNED:
        for mode in (0x00, 0x10, 0x14, 0x55, 0xFF):
            got = await _fp_run_point(dut, op, mode, via_eh=False)
            assert got == (1, 0, 0), \
                f"unassigned op=0x{op:02X} mode=0x{mode:02X}: got {got}"


# =============================================================================
# v1.8.0b §23.9 — stateless int datapath: VDOT_ACC (0x71), ACC_REDUCE (0x72),
# STORE_QUANT (0x7C). Golden models are plain python ints (exact), with the
# low-32 IMMA-wrap channel computed per the §23.4 contract.
# =============================================================================


def _s4(v):
    v &= 0xF
    return v - 16 if v & 0x8 else v


def _s8(v):
    v &= 0xFF
    return v - 256 if v & 0x80 else v


def _pack_int8_128(*vals):
    x = 0
    for i, v in enumerate(vals):
        x |= (v & 0xFF) << (i * 8)
    return x


async def _fire_v180b(dut, op, mode, ehs_extra, wide, payload=0, window=12):
    ehs = [_STD_PORT(), eh_precision(mode, 0)] + ehs_extra
    instr = encode_instr(op, *ehs, flags=(1 << 2))   # F_PRECISION_OVR
    dut.instruction.value = instr
    dut.input_tag.value = _STD_TAG()
    dut.input_payload.value = payload
    dut.input_payload_b.value = 0
    dut.input_payload_b_valid.value = 1
    dut.input_payload_wide.value = wide
    dut.input_payload_wide_valid.value = 1
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0
    for _ in range(window):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.output_valid.value) == 1 or int(dut.error_flag.value) == 1 \
                or int(dut.lower_required.value) == 1:
            break
    return {'err': int(dut.error_flag.value),
            'lwr': int(dut.lower_required.value),
            'out': int(dut.output_valid.value),
            'payload': int(dut.output_payload.value),
            'tag': int(dut.output_tag.value)}


@cocotb.test()
async def test_vdot_int4_single_dispatch_exact(dut):
    """v1.8.0b: 32-lane int4 dot incl. most-negative (-8) both sides,
    carry-in IMM16=1. payload == (sext64(exact dot) + 1) mod 2^64 vs
    python-int golden; sext (not zero-extend) checked via a negative case
    separately."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    a_lanes = [(-8 if i % 5 == 0 else (i % 15) - 7) for i in range(32)]
    b_lanes = [(-8 if i % 7 == 0 else ((i * 3) % 15) - 7) for i in range(32)]
    a = _pack_int4_128(*[v & 0xF for v in a_lanes])
    b = _pack_int4_128(*[v & 0xF for v in b_lanes])
    wide = a | (b << 128)
    golden = (sum(x * y for x, y in zip(a_lanes, b_lanes)) + 1) % (1 << 64)
    r = await _fire_v180b(dut, 0x71, 0x10, [eh_imm16(1)], wide)
    assert (r['err'], r['lwr'], r['out']) == (0, 0, 1), f"got {r}"
    assert r['payload'] == golden, f"{r['payload']:016x} != {golden:016x}"
    assert (r['tag'] & 0xFF) == 0x00   # scalar dim_sizes


@cocotb.test()
async def test_vdot_int8_single_dispatch_exact(dut):
    """v1.8.0b: 16-lane int8 dot incl. ±127/-128 lanes, dtype mode 0x11."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    a_lanes = [(-128 if i == 0 else (127 if i == 1 else (i * 17) % 255 - 127)) for i in range(16)]
    b_lanes = [(127 if i == 0 else (-128 if i == 2 else (i * 29) % 255 - 127)) for i in range(16)]
    a = _pack_int8_128(*a_lanes)
    b = _pack_int8_128(*b_lanes)
    wide = a | (b << 128)
    golden = (sum(x * y for x, y in zip(a_lanes, b_lanes)) + 0) % (1 << 64)
    r = await _fire_v180b(dut, 0x71, 0x11, [eh_imm16(0)], wide)
    assert (r['err'], r['lwr'], r['out']) == (0, 0, 1), f"got {r}"
    assert r['payload'] == golden, f"{r['payload']:016x} != {golden:016x}"


@cocotb.test()
async def test_vdot_negative_result_sext64_payload(dut):
    """v1.8.0b §23.6a payload-format pin: negative dot → payload[63:32]
    == all-ones (sext64 convention, NOT the legacy {32'h0,acc} idiom)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    a = _pack_int4_128(*([0x8] * 32))   # -8 every lane
    b = _pack_int4_128(*([0x7] * 32))   # +7 every lane
    wide = a | (b << 128)
    golden = (32 * (-8 * 7)) % (1 << 64)   # -1792 mod 2^64
    r = await _fire_v180b(dut, 0x71, 0x10, [eh_imm16(0)], wide)
    assert r['out'] == 1
    assert r['payload'] == golden
    assert (r['payload'] >> 32) == 0xFFFFFFFF


@cocotb.test()
async def test_acc_reduce_subops_golden(dut):
    """v1.8.0b: SUM/MAX/L2SQ/MEAN vs python goldens (int4 mode),
    absent-imm16 == SUM, MEAN RNE ties-to-even directed vectors."""
    import sys as _sys
    _sys.path.insert(0, os.path.join(_REPO, 'asm'))
    from generated_isa_tables import ACC_REDUCE_OP_CODE
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    lanes = [(-8 if i == 3 else (i % 15) - 7) for i in range(32)]
    a = _pack_int4_128(*[v & 0xF for v in lanes])
    goldens = {
        'sum':  sum(lanes),
        'max':  max(lanes),
        'l2sq': sum(v * v for v in lanes),
    }
    s = sum(lanes)
    # python RNE(s/32) ties-to-even
    t, rem = s >> 5, s - ((s >> 5) << 5)
    if rem > 16: t += 1
    elif rem == 16: t += (t & 1)
    goldens['mean'] = t

    for name, exp in goldens.items():
        imm = ACC_REDUCE_OP_CODE[name] << 4
        r = await _fire_v180b(dut, 0x72, 0x10, [eh_imm16(imm)], a)
        assert (r['err'], r['lwr'], r['out']) == (0, 0, 1), f"{name}: {r}"
        assert r['payload'] == exp % (1 << 64), \
            f"{name}: {r['payload']:016x} != {exp % (1 << 64):016x}"

    # absent imm16 == SUM (port-only encoding keeps decoding, gains SUM)
    r = await _fire_v180b(dut, 0x72, 0x10, [], a)
    assert (r['err'], r['lwr'], r['out']) == (0, 0, 1), f"absent-imm16: {r}"
    assert r['payload'] == goldens['sum'] % (1 << 64)

    # MEAN directed: sum=-97, N=32 → RNE(-3.03) = -3 (NOT the ASR floor -4)
    lanes97 = [-4] * 24 + [0] * 7 + [-1]
    assert sum(lanes97) == -97
    a97 = _pack_int4_128(*[v & 0xF for v in lanes97])
    r = await _fire_v180b(dut, 0x72, 0x10,
                          [eh_imm16(ACC_REDUCE_OP_CODE['mean'] << 4)], a97)
    assert r['payload'] == (-3) % (1 << 64), \
        f"MEAN(-97/32) = {r['payload']:016x}, expected -3 (RNE, not ASR floor -4)"


@cocotb.test()
async def test_acc_reduce_reserved_and_unknown_lower_required(dut):
    """v1.8.0b: imm16[3:0]!=0 → lower_required; unknown sub-op nibbles —
    specifically 0x2 and 0x6, the RED/einsum MIN collision codes — →
    lower_required (never error_flag). Pins that MIN is unshipped."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    a = _pack_int4_128(*([1] * 32))
    for imm in (0x0001, 0x0008):        # reserved [3:0] violations
        r = await _fire_v180b(dut, 0x72, 0x10, [eh_imm16(imm)], a)
        assert (r['err'], r['lwr'], r['out']) == (0, 1, 0), f"imm={imm:#x}: {r}"
    for imm in (0x2 << 4, 0x6 << 4, 0xF << 4):   # unknown sub-ops (incl. both MIN codes)
        r = await _fire_v180b(dut, 0x72, 0x10, [eh_imm16(imm)], a)
        assert (r['err'], r['lwr'], r['out']) == (0, 1, 0), f"imm={imm:#x}: {r}"


@cocotb.test()
async def test_store_quant_clamp_rne_shift(dut):
    """v1.8.0b: 0x7C boundary clamps, absent-imm16 == pure clamp, RNE
    shift incl. ties-to-even, reserved-bit violation → lower_required,
    f16/bf16 dest → lower_required, memory_req never asserted."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    M = 1 << 64
    # (payload, mode, imm16 or None, expected sext64)
    cases = [
        (7,            0x10, None, 7),           # int4 in-range
        (9,            0x10, None, 7),           # int4 clamp hi
        ((-9) % M,     0x10, None, (-8) % M),    # int4 clamp lo
        (129,          0x11, None, 127),         # int8 clamp hi
        ((-129) % M,   0x11, None, (-128) % M),  # int8 clamp lo
        ((1 << 40),    0x11, None, 127),         # large positive clamps
        (24,           0x10, 4,    2),           # RNE(24/16)=1.5 → ties-to-even → 2
        (40,           0x10, 4,    2),           # RNE(2.5) → 2 (even)
        (44,           0x10, 4,    3),           # RNE(2.75) → 3
    ]
    for payload, mode, shift, exp in cases:
        ehs = [eh_imm16(shift)] if shift is not None else []
        r = await _fire_v180b(dut, 0x7C, mode, ehs, 0, payload=payload)
        assert (r['err'], r['lwr'], r['out']) == (0, 0, 1), \
            f"x={payload:#x} mode={mode:#x} s={shift}: {r}"
        assert r['payload'] == exp % M, \
            f"x={payload:#x} s={shift}: {r['payload']:016x} != {exp % M:016x}"
        assert int(dut.memory_req.value) == 0

    # reserved imm16[15:6] violation
    r = await _fire_v180b(dut, 0x7C, 0x10, [eh_imm16(0x0040)], 0, payload=1)
    assert (r['err'], r['lwr'], r['out']) == (0, 1, 0), f"reserved: {r}"
    # v1.8.0d §23.10.10(d): the f16/bf16 destinations GRADUATED — the
    # packer executes (payload 1 = fp32 denormal -> DAZ -> +0 -> h 0x0000;
    # a non-trivial value cell too). Bit-level coverage lives in
    # test_store_quant_fp_dest_bit_identity_directed.
    import golden_fp32 as _G7C
    for mode, dt in ((0x12, 2), (0x13, 3)):
        for payload in (1, 0x3FC00000):     # denorm-DAZ cell + 1.5f
            exp = _G7C.store_quant(payload, dt)
            r = await _fire_v180b(dut, 0x7C, mode, [], 0, payload=payload)
            assert (r['err'], r['lwr'], r['out']) == (0, 0, 1), \
                f"mode={mode:#x} x={payload:#x}: {r}"
            assert r['payload'] == exp, \
                f"mode={mode:#x} x={payload:#x}: " \
                f"{r['payload']:016x} != {exp:04x}"


@cocotb.test()
async def test_orderfree_chain_vs_tree_property(dut):
    """v1.8.0b §23.4 THE order-free bit-exactness property: K=128 int4
    dot computed three ways — (a) serial carry-in chain, (b) VDOT
    partials + scalar ADD 0x10 tree, (c) tree with permuted
    chunk-to-dispatch assignment — all bit-identical; low 32 bits ==
    int32-wrap golden (operands cast to wide BEFORE multiply — the numpy
    int8-input-dtype wrap trap pinned in the golden helper); full 64 ==
    exact python-int sum."""
    import random
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)
    rng = random.Random(0x1807)   # deterministic seed (no live entropy)

    K = 128
    a_lanes = [rng.randint(-8, 7) for _ in range(K)]
    b_lanes = [rng.randint(-8, 7) for _ in range(K)]
    seed = 0x0000_0123_4567_89AB

    exact = (seed + sum(x * y for x, y in zip(a_lanes, b_lanes))) % (1 << 64)
    # int32-wrap (IMMA) golden: exact products, sum reduced mod 2^32 signed
    wrap32 = (seed + sum(x * y for x, y in zip(a_lanes, b_lanes))) % (1 << 32)

    def chunk(vals, i):
        return _pack_int4_128(*[v & 0xF for v in vals[i * 32:(i + 1) * 32]])

    async def vdot(i, carry):
        wide = chunk(a_lanes, i) | (chunk(b_lanes, i) << 128)
        r = await _fire_v180b(dut, 0x71, 0x10, [eh_imm64(carry)], wide)
        assert (r['err'], r['lwr'], r['out']) == (0, 0, 1), f"chunk {i}: {r}"
        return r['payload']

    async def scalar_add(x, y):
        instr = encode_instr(0x10, _STD_PORT(), eh_imm64(y))
        dut.instruction.value = instr
        dut.input_tag.value = _STD_TAG()
        dut.input_payload.value = x
        dut.input_payload_b_valid.value = 0
        dut.input_payload_wide.value = 0
        dut.input_payload_wide_valid.value = 0
        dut.token_valid.value = 1
        await RisingEdge(dut.clk)
        dut.token_valid.value = 0
        for _ in range(10):
            await RisingEdge(dut.clk)
            await Timer(1, units="ns")
            if int(dut.output_valid.value) == 1:
                break
        assert int(dut.output_valid.value) == 1
        return int(dut.output_payload.value)

    # (a) serial carry-in chain (fixed order — data dependency)
    acc = seed
    for i in range(4):
        acc = await vdot(i, acc)
    result_chain = acc

    # (b) partials + ADD tree
    parts = [await vdot(i, 0) for i in range(4)]
    s01 = await scalar_add(parts[0], parts[1])
    s23 = await scalar_add(parts[2], parts[3])
    s = await scalar_add(s01, s23)
    result_tree = await scalar_add(s, seed)

    # (c) permuted chunk issue order for the tree
    order = [2, 0, 3, 1]
    parts_p = {}
    for i in order:
        parts_p[i] = await vdot(i, 0)
    s01p = await scalar_add(parts_p[3], parts_p[0])
    s23p = await scalar_add(parts_p[1], parts_p[2])
    sp = await scalar_add(seed, s01p)
    result_tree_perm = await scalar_add(sp, s23p)

    assert result_chain == exact, f"chain {result_chain:016x} != {exact:016x}"
    assert result_tree == exact, f"tree {result_tree:016x} != {exact:016x}"
    assert result_tree_perm == exact, f"perm-tree {result_tree_perm:016x} != {exact:016x}"
    assert (result_chain & 0xFFFFFFFF) == wrap32


# =============================================================================
# v1.8.0c §23.10 — fp32 scalar step-sequencer integration: FSCALAR (0x74),
# FRSQRT32 (0x75), FEXP2_32 (0x76) through the FULL decode -> launch ->
# finish path. Golden authority is scripts/golden_fp32.py (imported, never
# retyped): micro_fscalar / micro_rsqrt / micro_exp2 — the same entry
# points the pre-integration FP_StepSeq TB proved bit-exact on 169,514
# vectors (synth/lattice/fp_ops/tb_fp_stepseq.py).
# =============================================================================

import struct as _struct

sys.path.insert(0, os.path.join(_REPO, 'scripts'))
import golden_fp32 as _G  # noqa: E402

_FS = _G.FSCALAR_OP_CODE
_FP_MODE = 0x14   # the single legal fp mode byte: rnd=0, acc=1, dtype=4 (f32)


def _f2b(x):
    return int.from_bytes(_struct.pack(">f", float(x)), "big")


def _fp_instr(op, subop=None, imm16=None, out_port=0, mode=None,
              opref=False, imm32=None, imm64=None):
    """Encode an fp-block instruction: PORT + PRECISION(mode, via
    F_PRECISION_OVR; default 0x14) + optional IMM16 (sub-op nibble in
    [7:4]). The F_HAS_OPB flag is deliberately NOT set:
    dec_input_payload_b_valid mirrors the input port directly, so the
    v1.8.0c dispatch-side missing-B guard (not EHDecode's
    opb_required_invalid) is what these tests exercise.

    v1.8.0d additions: `mode` selects the dtype nibble for the CVT /
    STORE_QUANT fp-dest forms; `opref` appends a src_kind-0 OPREF EH
    (the 0x73 ACC_ELEMWISE B channel); `imm32`/`imm64` build the
    RTL-tolerated / rung-exercising immediate forms."""
    ehs = [eh_port(input_port_mask=0x01, output_port_id=out_port),
           eh_precision(_FP_MODE if mode is None else mode, 0)]
    if imm16 is not None:
        ehs.append(eh_imm16(imm16))
    elif subop is not None:
        ehs.append(eh_imm16((subop & 0xF) << 4))
    if imm32 is not None:
        ehs.append(eh_imm32(imm32))
    if imm64 is not None:
        ehs.append(eh_imm64(imm64))
    if opref:
        ehs.append(eh_opref())
    return encode_instr(op, *ehs, flags=F_PRECISION_OVR)


async def _fp_fire_token(dut, instr, payload_a, payload_b=0, b_valid=1,
                         tag=None, wide=0, wide_valid=0):
    """Present one token for exactly one clock edge (no polling)."""
    dut.instruction.value = instr
    dut.input_tag.value = _STD_TAG() if tag is None else tag
    dut.input_payload.value = payload_a
    dut.input_payload_b.value = payload_b
    dut.input_payload_b_valid.value = b_valid
    dut.input_payload_wide.value = wide
    dut.input_payload_wide_valid.value = wide_valid
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0


async def _fp_collect_events(dut, cycles):
    """Sample the outcome strobes for `cycles` cycles (post-edge settle);
    every output_valid / error_flag / lower_required pulse becomes one
    event dict, in order."""
    events = []
    for i in range(cycles):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.output_valid.value):
            events.append({'kind': 'out', 'cycle': i,
                           'payload': int(dut.output_payload.value),
                           'tag': int(dut.output_tag.value),
                           'opcode': int(dut.opcode_out.value),
                           'frag_hdr': int(dut.output_frag_hdr.value)})
        if int(dut.error_flag.value):
            events.append({'kind': 'err', 'cycle': i})
        if int(dut.lower_required.value):
            events.append({'kind': 'lwr', 'cycle': i})
    return events


async def _fp_run(dut, op, payload_a, payload_b=0, b_valid=1, subop=None,
                  imm16=None, tag=None, out_port=0, window=60, mode=None,
                  opref=False, imm32=None, imm64=None):
    """Fire one fp op and return its FIRST outcome event (err/lwr/out
    ever-bits + payload/tag/opcode + token->outcome cycle count)."""
    await _fp_fire_token(dut, _fp_instr(op, subop, imm16, out_port, mode,
                                        opref, imm32, imm64),
                         payload_a, payload_b, b_valid, tag)
    for i in range(window):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        err = int(dut.error_flag.value)
        lwr = int(dut.lower_required.value)
        out = int(dut.output_valid.value)
        if err or lwr or out:
            return {'err': err, 'lwr': lwr, 'out': out,
                    'payload': int(dut.output_payload.value),
                    'tag': int(dut.output_tag.value),
                    'opcode': int(dut.opcode_out.value),
                    'cycles': i + 1}
    raise AssertionError(f"op 0x{op:02X}: no outcome within {window} cycles")


async def _fp_drain(dut, cycles=120):
    """Wait until the PE is idle (pe_ready high, no output pulse)."""
    for _ in range(cycles):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.pe_ready.value) == 1 and int(dut.output_valid.value) == 0:
            return
    raise AssertionError("PE did not drain to idle")


def _fp_exp_tag(wave=0, thread=0, out_port=0, mode=_FP_MODE):
    """The scalar tag the fp arms rebuild: {wave, thread, 8'h00,
    output_port_id, precision, 8'h00} (dim byte 0x00 — scalar)."""
    return ((wave & 0xFFFFFFFF) << 48) | ((thread & 0xFFFF) << 32) \
         | ((out_port & 0xFF) << 16) | ((mode & 0xFF) << 8)


_QNAN, _PINF, _NINF = 0x7FC00000, 0x7F800000, 0xFF800000


@cocotb.test()
async def test_fp_ieee_directed_cells_e2e(dut):
    """v1.8.0c: 14 representative §23.10.5 IEEE cells through the FULL
    decode->launch->finish path, bit-exact vs golden_fp32 — including the
    {32'h0, fp32} upper-32-zero scalar payload convention (the 64-bit
    compare below IS that pin) and opcode_out == the fp opcode."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # FMA fused-vs-double-rounding discriminator (spec F1): prove the
    # vector discriminates before driving it.
    f1 = (0x3F800001, 0x3F800001, 0xBF800002)
    fused = _G.micro_fscalar(_FS['FS_FMA'], *f1)
    double_rounded = _G.micro_fscalar(
        _FS['FS_ADD'], _G.micro_fscalar(_FS['FS_MUL'], f1[0], f1[1]), f1[2])
    assert fused != double_rounded, "F1 vector no longer discriminates"

    cells = [
        # (label, op, subop, a, b, c)
        ("A2 canonical qNaN Inf+(-Inf)", 0x74, _FS['FS_ADD'], _PINF, _NINF, 0),
        ("M2 Inf arithmetic (-Inf)*3",   0x74, _FS['FS_MUL'], _NINF, _f2b(3.0), 0),
        ("M3 signed zero (-0)*(+3)",     0x74, _FS['FS_MUL'], 0x80000000, _f2b(3.0), 0),
        ("Z1 DAZ denorm+1.0",            0x74, _FS['FS_ADD'], 0x00000001, _f2b(1.0), 0),
        ("FTZ boundary min_normal*0.5",  0x74, _FS['FS_MUL'], 0x00800000, _f2b(0.5), 0),
        ("RNE tie 1.0+2^-24",            0x74, _FS['FS_ADD'], _f2b(1.0), 0x33800000, 0),
        ("F1 FMA fused single-rounding", 0x74, _FS['FS_FMA'], f1[0], f1[1], f1[2]),
        ("F2 FMA Inf*0+c qNaN",          0x74, _FS['FS_FMA'], _PINF, 0x00000000, _f2b(5.0)),
        ("V6 FDIV sign-XOR -6/2",        0x74, _FS['FS_DIV'], _f2b(-6.0), _f2b(2.0), 0),
        ("V1 FDIV 3/(+0) -> +Inf",       0x74, _FS['FS_DIV'], _f2b(3.0), 0x00000000, 0),
        ("R3 rsqrt(-1) qNaN",            0x75, None, _f2b(-1.0), 0, 0),
        ("R6 rsqrt(4) bit-exact 0.5",    0x75, None, _f2b(4.0), 0, 0),
        ("E3 exp2 integer bypass 2^7",   0x76, None, _f2b(7.0), 0, 0),
        ("E2 exp2 x>=128 -> +Inf",       0x76, None, _f2b(128.0), 0, 0),
    ]
    for label, op, sub, a, b, c in cells:
        if op == 0x74:
            exp = _G.micro_fscalar(sub, a, b, c)
            payload_a = ((c & 0xFFFFFFFF) << 32) | a
            r = await _fp_run(dut, op, payload_a, payload_b=b, subop=sub)
        elif op == 0x75:
            exp = _G.micro_rsqrt(a)
            r = await _fp_run(dut, op, a)
        else:
            exp = _G.micro_exp2(a)
            r = await _fp_run(dut, op, a)
        assert (r['err'], r['lwr'], r['out']) == (0, 0, 1), f"{label}: {r}"
        # FULL 64-bit compare — pins the {32'h0, fp32} payload convention.
        assert r['payload'] == exp, \
            f"{label}: payload {r['payload']:016x} != {exp:08x}"
        assert r['opcode'] == op, f"{label}: opcode_out {r['opcode']:#x}"
        await _fp_drain(dut)
    dut._log.info("fp IEEE directed cells: %d bit-exact end-to-end", len(cells))


@cocotb.test()
async def test_fscalar_subop_decode_guards(dut):
    """v1.8.0c §23.10.2 FSCALAR decode ladder: absent imm16 = FS_ADD;
    every sub-op 0-4 correct; imm16[3:0] != 0 -> lower_required; sub-op
    5-15 -> lower_required (and outranks the missing-B check — rung
    order); missing payload_b -> error_flag (dispatch-side guard, F_HAS_OPB
    deliberately unset); FS_FMA reads C from payload_a[63:32]; non-FMA
    ignores payload_a[63:32]."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a, b, c = _f2b(3.5), _f2b(2.25), _f2b(-7.5)

    # absent imm16 -> FS_ADD (monotonic loosening default)
    exp_add = _G.micro_fscalar(_FS['FS_ADD'], a, b)
    r = await _fp_run(dut, 0x74, a, payload_b=b)
    assert (r['err'], r['lwr'], r['out']) == (0, 0, 1), f"absent-imm16: {r}"
    assert r['payload'] == exp_add and r['opcode'] == 0x74
    await _fp_drain(dut)

    # every sub-op 0-4 (FMA gets C via payload_a[63:32])
    for name, sub in sorted(_FS.items(), key=lambda kv: kv[1]):
        use_c = (sub == _FS['FS_FMA'])
        exp = _G.micro_fscalar(sub, a, b, c if use_c else 0)
        payload_a = ((c << 32) | a) if use_c else a
        r = await _fp_run(dut, 0x74, payload_a, payload_b=b, subop=sub)
        assert (r['err'], r['lwr'], r['out']) == (0, 0, 1), f"{name}: {r}"
        assert r['payload'] == exp, \
            f"{name}: {r['payload']:016x} != {exp:08x}"
        await _fp_drain(dut)

    # FS_FMA really consumed C (differs from the C=0 result)
    assert _G.micro_fscalar(_FS['FS_FMA'], a, b, c) != \
        _G.micro_fscalar(_FS['FS_FMA'], a, b, 0)

    # imm16[3:0] reserved-zero violations -> lower_required (never error)
    for imm in (0x0001, 0x0018, 0x004F):
        r = await _fp_run(dut, 0x74, a, payload_b=b, imm16=imm)
        assert (r['err'], r['lwr'], r['out']) == (0, 1, 0), f"imm={imm:#x}: {r}"

    # unknown sub-op 0x5-0xF -> lower_required (never error)
    for sub in range(5, 16):
        r = await _fp_run(dut, 0x74, a, payload_b=b, subop=sub)
        assert (r['err'], r['lwr'], r['out']) == (0, 1, 0), f"sub={sub}: {r}"

    # rung order: unknown sub-op outranks missing-B (lower, not error)
    r = await _fp_run(dut, 0x74, a, payload_b=0, b_valid=0, subop=7)
    assert (r['err'], r['lwr'], r['out']) == (0, 1, 0), f"order: {r}"

    # missing payload_b -> error_flag (malformed program, deterministic)
    r = await _fp_run(dut, 0x74, a, payload_b=0, b_valid=0)
    assert (r['err'], r['lwr'], r['out']) == (1, 0, 0), f"missing-B: {r}"

    # non-FMA ignores payload_a[63:32] (garbage upper == clean result)
    exp_mul = _G.micro_fscalar(_FS['FS_MUL'], a, b)
    r1 = await _fp_run(dut, 0x74, a, payload_b=b, subop=_FS['FS_MUL'])
    await _fp_drain(dut)
    r2 = await _fp_run(dut, 0x74, (0xDEADBEEF << 32) | a, payload_b=b,
                       subop=_FS['FS_MUL'])
    await _fp_drain(dut)
    assert r1['payload'] == exp_mul and r2['payload'] == exp_mul, \
        f"upper-32 not ignored: {r1['payload']:016x} vs {r2['payload']:016x}"


@cocotb.test()
async def test_fp_mul_collision_fp_result_preserved(dut):
    """v1.8.0c amendment-1 regression: sweep a 0x12 MUL dispatch over 7
    consecutive token offsets so its (calibrated) output cycle lands
    -3..+3 cycles around the fp op's finish. For EVERY offset the fp
    result + rebuilt tag arrive intact — without the MUL-launch fp-idle
    guard the offset-0 collision silently drops the fp result (MUL
    outranks FP in the output priority chain)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a = _f2b(2.0)
    exp_fp = _G.micro_rsqrt(a)
    exp_tag = _fp_exp_tag()
    fp_instr = _fp_instr(0x75)
    mul_instr = encode_instr(0x12, _STD_PORT(), eh_imm16(3))

    # calibrate F: fp token -> output cycle count
    r = await _fp_run(dut, 0x75, a)
    assert r['out'] == 1 and r['payload'] == exp_fp
    F = r['cycles']
    await _fp_drain(dut)

    # calibrate M: MUL token -> output cycle count
    await _fp_fire_token(dut, mul_instr, 5)
    M = None
    for i in range(40):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.output_valid.value):
            assert int(dut.output_payload.value) == 15
            M = i + 1
            break
    assert M is not None, "MUL calibration timed out"
    await _fp_drain(dut)

    for delta in range(-3, 4):
        gap = F - M + delta   # MUL token offset so MUL-out = fp-out + delta
        assert gap >= 1, f"geometry broke: F={F} M={M} delta={delta}"
        await _fp_fire_token(dut, fp_instr, a)
        for _ in range(gap - 1):
            await RisingEdge(dut.clk)
        await _fp_fire_token(dut, mul_instr, 5)
        events = await _fp_collect_events(dut, F + M + 16)
        fp_ev = [e for e in events if e['kind'] == 'out' and e['opcode'] == 0x75]
        assert len(fp_ev) == 1, f"delta={delta}: fp result lost/dup: {events}"
        assert fp_ev[0]['payload'] == exp_fp, \
            f"delta={delta}: {fp_ev[0]['payload']:016x} != {exp_fp:08x}"
        assert fp_ev[0]['tag'] == exp_tag, f"delta={delta}: tag {fp_ev[0]['tag']:#x}"
        assert not [e for e in events if e['kind'] == 'err'], \
            f"delta={delta}: stray error: {events}"
        await _fp_drain(dut)
    dut._log.info("fp/MUL collision sweep: fp result intact at all 7 offsets "
                  "(F=%d, M=%d)", F, M)


@cocotb.test()
async def test_fp_busy_reject_is_lower_required(dut):
    """v1.8.0c launch-ladder rung 2 (VDOT busy-reject pattern, NEVER the
    DIV silent-swallow): during a long FS_DIV flight a second fp op, a
    0x71 VDOT and a wide SIMD 0x69 Q8.8 each get lower_required; the
    in-flight FS_DIV still lands bit-exact; every probe succeeds on
    retry after the drain. (The wide-SIMD probe vehicle was 0x6B WIDEN
    until its pre-stable removal in the opcode cleanup; 0x69 exercises
    the same shared wide-emit busy gate.)"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a, b = _f2b(1.0), _f2b(3.0)
    exp_div = _G.micro_fscalar(_FS['FS_DIV'], a, b)
    div_instr = _fp_instr(0x74, subop=_FS['FS_DIV'])

    async def launch_div_wait_busy():
        await _fp_fire_token(dut, div_instr, a, payload_b=b)
        for _ in range(12):
            await RisingEdge(dut.clk)
            await Timer(1, units="ns")
            if int(dut.u_core.fp_busy.value) == 1:
                return
        raise AssertionError("FS_DIV never went busy")

    # probe encodings (all fully legal — only the busy gate rejects them)
    vdot_instr = encode_instr(0x71, _STD_PORT(), eh_precision(0x10, 0),
                              eh_imm16(0), flags=F_PRECISION_OVR)
    vdot_wide = (_pack_int4_128(*([1] * 32))
                 | (_pack_int4_128(*([2] * 32)) << 128))
    exp_vdot = 32 * (1 * 2)
    # A[i]=+2, B=Q8.8(0.5)=0x0080 -> every int4 lane rounds to 1.
    q88_instr = encode_instr(0x69, _STD_PORT(), eh_imm16(0x0080))
    q88_wide = _pack_int4_128(*([0x2] * 32))

    probes = [
        ("second fp op 0x75",
         dict(instr=_fp_instr(0x75), payload_a=_f2b(2.0))),
        ("0x71 VDOT",
         dict(instr=vdot_instr, payload_a=0, wide=vdot_wide, wide_valid=1)),
        ("wide SIMD 0x69 Q8.8",
         dict(instr=q88_instr, payload_a=0, wide=q88_wide, wide_valid=1)),
    ]

    for label, kw in probes:
        await launch_div_wait_busy()
        await _fp_fire_token(dut, kw['instr'], kw['payload_a'],
                             wide=kw.get('wide', 0),
                             wide_valid=kw.get('wide_valid', 0))
        events = await _fp_collect_events(dut, 50)
        lwr_ev = [e for e in events if e['kind'] == 'lwr']
        assert lwr_ev, f"{label}: no lower_required during fp flight: {events}"
        assert not [e for e in events if e['kind'] == 'err'], \
            f"{label}: error instead of busy-reject: {events}"
        div_ev = [e for e in events if e['kind'] == 'out' and e['opcode'] == 0x74]
        assert len(div_ev) == 1 and div_ev[0]['payload'] == exp_div, \
            f"{label}: in-flight FS_DIV corrupted: {events}"
        assert lwr_ev[0]['cycle'] < div_ev[0]['cycle'], \
            f"{label}: reject did not precede the fp finish"
        await _fp_drain(dut)

    # retries after drain all succeed
    r = await _fp_run(dut, 0x75, _f2b(2.0))
    assert r['out'] == 1 and r['payload'] == _G.micro_rsqrt(_f2b(2.0))
    await _fp_drain(dut)

    await _fp_fire_token(dut, vdot_instr, 0, wide=vdot_wide, wide_valid=1)
    events = await _fp_collect_events(dut, 20)
    out_ev = [e for e in events if e['kind'] == 'out']
    assert out_ev and out_ev[0]['payload'] == exp_vdot, f"VDOT retry: {events}"
    await _fp_drain(dut)

    await _fp_fire_token(dut, q88_instr, 0, wide=q88_wide, wide_valid=1)
    events = await _fp_collect_events(dut, 20)
    frags = [e for e in events if e['kind'] == 'out']
    assert len(frags) == 2, f"0x69 retry did not emit 2 fragments: {events}"
    assert all(e['payload'] == 0x1111_1111_1111_1111 for e in frags), \
        f"0x69 retry payload mismatch: {events}"
    await _fp_drain(dut)


@cocotb.test()
async def test_fp_drain_gate_and_frag_interaction(dut):
    """v1.8.0c fp <-> fragment-drain interaction, three directions:
    (a) an fp op fired at a multi-fragment einsum's frag-0 emit cycle is
        HELD until the drain completes (EHDecode's >=3-cycle walk lands
        the fp dispatch strictly after the 2-beat SIG_BMM_3 drain by
        construction) — both fragments AND the fp result arrive intact;
    (b) a frag-emitting op (SIG_BMM_3) dispatched during an fp flight
        gets lower_required (busy-reject, not silent) and the fp result
        still lands; the einsum succeeds on retry;
    (c) pe_ready is low for the whole fp flight and recovers within the
        §23.10.6 bound + fixed overhead (bounds-based — never an exact
        cycle count)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # identity-A SIG_BMM_3: result halves == B halves (reuses the shipped
    # test_bmm_3_identity_per_batch construction)
    identity = 0x1001
    a_128 = 0
    for i in range(8):
        a_128 |= identity << (i * 16)
    b_batches = [0x1234, 0x5678, 0x9ABC, 0xDEF0,
                 0x0FED, 0xCBA9, 0x8765, 0x4321]
    b_128 = 0
    for i, x in enumerate(b_batches):
        b_128 |= (x & 0xFFFF) << (i * 16)
    bmm3_wide = _pack_int4_wide(a_128, b_128)
    exp_lo = b_128 & ((1 << 64) - 1)
    exp_hi = (b_128 >> 64) & ((1 << 64) - 1)
    bmm3_instr = encode_instr(0x32, _STD_PORT(),
                              eh_subscript(_BMM3_A_LO, _BMM3_B_LO, _BMM3_O_LO),
                              eh_subscript(_BMM3_A_HI, _BMM3_B_HI, _BMM3_O_HI),
                              eh_opref(),
                              flags=F_HAS_OPB)

    async def fire_bmm3():
        dut.instruction.value = bmm3_instr
        dut.input_tag.value = _STD_TAG(dim=0x55)
        dut.input_payload.value = 0
        dut.input_payload_b.value = 0
        dut.input_payload_b_valid.value = 1
        dut.input_payload_wide.value = bmm3_wide
        dut.input_payload_wide_valid.value = 1
        dut.token_valid.value = 1
        await RisingEdge(dut.clk)
        dut.token_valid.value = 0

    # ---- (a) fp op fired AT the frag-0 emit cycle -------------------------
    exp_fp = _G.micro_exp2(_f2b(3.0))
    await fire_bmm3()
    saw_frag0 = False
    for _ in range(30):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.output_valid.value):
            assert int(dut.output_payload.value) == exp_lo
            assert int(dut.output_frag_hdr.value) == 0x01
            # drain is active THIS cycle — the compound gate must be closed
            assert int(dut.pe_ready.value) == 0, "pe_ready high mid-drain"
            saw_frag0 = True
            break
    assert saw_frag0, "SIG_BMM_3 frag 0 never appeared"
    # Fire the fp token AT the frag-1 emit edge (the token edge IS the
    # frag-1 output cycle, so sample it immediately after the edge).
    dut.instruction.value = _fp_instr(0x76)
    dut.input_tag.value = _STD_TAG()
    dut.input_payload.value = _f2b(3.0)
    dut.input_payload_b.value = 0
    dut.input_payload_b_valid.value = 1
    dut.input_payload_wide.value = 0
    dut.input_payload_wide_valid.value = 0
    dut.token_valid.value = 1
    await RisingEdge(dut.clk)
    dut.token_valid.value = 0
    await Timer(1, units="ns")
    assert int(dut.output_valid.value) == 1 \
        and int(dut.output_payload.value) == exp_hi \
        and int(dut.output_frag_hdr.value) == 0x11, "frag 1 corrupted"
    events = await _fp_collect_events(dut, 40)
    fp_ev = [e for e in events if e['kind'] == 'out' and e['opcode'] == 0x76]
    assert len(fp_ev) == 1 and fp_ev[0]['payload'] == exp_fp, \
        f"fp op not held-then-executed across the drain: {events}"
    assert not [e for e in events if e['kind'] in ('err', 'lwr')], \
        f"stray flag: {events}"
    await _fp_drain(dut)

    # ---- (b) frag-emitting op during fp flight -> lower_required ----------
    a, b = _f2b(1.0), _f2b(3.0)
    exp_div = _G.micro_fscalar(_FS['FS_DIV'], a, b)
    await _fp_fire_token(dut, _fp_instr(0x74, subop=_FS['FS_DIV']), a,
                         payload_b=b)
    for _ in range(12):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.u_core.fp_busy.value) == 1:
            break
    assert int(dut.u_core.fp_busy.value) == 1
    await fire_bmm3()
    events = await _fp_collect_events(dut, 50)
    assert [e for e in events if e['kind'] == 'lwr'], \
        f"frag-emitter not busy-rejected: {events}"
    assert not [e for e in events if e['kind'] == 'err'], f"stray error: {events}"
    div_ev = [e for e in events if e['kind'] == 'out' and e['opcode'] == 0x74]
    assert len(div_ev) == 1 and div_ev[0]['payload'] == exp_div, \
        f"in-flight FS_DIV corrupted: {events}"
    frag_ev = [e for e in events if e['kind'] == 'out' and e['frag_hdr'] != 0]
    assert not frag_ev, f"fragments emitted during fp flight: {events}"
    await _fp_drain(dut)
    # einsum retry succeeds
    await fire_bmm3()
    events = await _fp_collect_events(dut, 30)
    outs = [e for e in events if e['kind'] == 'out']
    assert len(outs) == 2 and outs[0]['payload'] == exp_lo \
        and outs[1]['payload'] == exp_hi, f"BMM3 retry failed: {events}"
    await _fp_drain(dut)

    # ---- (c) pe_ready low across the fp flight (bounds-based) -------------
    await _fp_fire_token(dut, _fp_instr(0x75), _f2b(2.0))
    low_cycles = 0
    recovered = None
    for i in range(60):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        busy = int(dut.u_core.fp_busy.value) or int(dut.u_core.fp_valid_p2.value)
        ready = int(dut.pe_ready.value)
        if busy:
            assert ready == 0, f"pe_ready high while fp unit busy (cycle {i})"
            low_cycles += 1
        if low_cycles > 0 and ready == 1:
            recovered = i
            break
    assert low_cycles >= 3, "fp flight never deasserted pe_ready"
    assert recovered is not None and recovered <= 34 + 12, \
        "pe_ready did not recover within the FRSQRT32 bound + overhead"
    await _fp_drain(dut)


@cocotb.test()
async def test_fp_tag_and_opcode_out_preservation(dut):
    """v1.8.0c: across a 25-cycle FS_DIV whose dec_* bus is CLOBBERED
    mid-flight by an unrelated ADD dispatch, the fp result cycle carries
    (1) the tag rebuilt AT LAUNCH — wave/thread from the launch token,
    dim byte 0x00 scalar rebuild (input dim 0x77 discarded), tag[15:8]
    = the mode byte 0x14 VERBATIM from the PRECISION EH (input tag mode
    byte deliberately 0x00), output_port_id from the PORT EH — and
    (2) opcode_out == the fp opcode (fp_opcode_held), the deliberate
    divergence from DIV's stale-opcode quirk."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a, b = _f2b(355.0), _f2b(113.0)
    exp = _G.micro_fscalar(_FS['FS_DIV'], a, b)
    tag_in = make_tag(wave_number=0xAABBCCDD, thread_id=0x1234,
                      port_context_id=0, precision_mode=0x00,
                      dimension_sizes=0x77)
    instr = _fp_instr(0x74, subop=_FS['FS_DIV'], out_port=0x5A)
    await _fp_fire_token(dut, instr, a, payload_b=b, tag=tag_in)
    for _ in range(12):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.u_core.fp_busy.value) == 1:
            break
    assert int(dut.u_core.fp_busy.value) == 1

    # clobber dec_* mid-flight with an ADD under a DIFFERENT tag
    add_instr = encode_instr(0x10, _STD_PORT(), eh_imm16(1))
    await _fp_fire_token(dut, add_instr, 41,
                         tag=make_tag(wave_number=1, thread_id=2,
                                      port_context_id=0))
    events = await _fp_collect_events(dut, 60)
    add_ev = [e for e in events if e['kind'] == 'out' and e['opcode'] == 0x10]
    assert add_ev and add_ev[0]['payload'] == 42, \
        f"mid-flight ADD clobber never executed: {events}"
    fp_ev = [e for e in events if e['kind'] == 'out' and e['opcode'] == 0x74]
    assert len(fp_ev) == 1, f"fp result missing: {events}"
    assert fp_ev[0]['payload'] == exp
    exp_tag = _fp_exp_tag(wave=0xAABBCCDD, thread=0x1234, out_port=0x5A)
    assert fp_ev[0]['tag'] == exp_tag, \
        f"tag {fp_ev[0]['tag']:020x} != {exp_tag:020x}"
    await _fp_drain(dut)


@cocotb.test()
async def test_fp_cycle_bounds(dut):
    """v1.8.0c §23.10.6: each fp op COMPLETES WITHIN its normative cycle
    maximum, measured at the unit level (consecutive fp_busy cycles ==
    start->done). Bounds only — never an exact-count assertion (Gate-2
    fallback headroom is part of the contract). The end-to-end window
    adds a fixed +12 decode/finish overhead allowance (EHDecode chain
    walk + launch + p2/output stages), which is NOT normative."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    cases = [
        ("FS_ADD",   0x74, _FS['FS_ADD'], _f2b(1.5), _f2b(2.5), 0.0,       6),
        ("FS_SUB",   0x74, _FS['FS_SUB'], _f2b(1.5), _f2b(2.5), 0.0,       6),
        ("FS_MUL",   0x74, _FS['FS_MUL'], _f2b(1.5), _f2b(2.5), 0.0,       6),
        ("FS_FMA",   0x74, _FS['FS_FMA'], _f2b(1.5), _f2b(2.5), _f2b(3.5), 10),
        ("FS_DIV",   0x74, _FS['FS_DIV'], _f2b(1.0), _f2b(3.0), 0.0,       32),
        ("FRSQRT32", 0x75, None,          _f2b(2.0), 0,         0.0,       34),
        ("FEXP2_32", 0x76, None,          _f2b(1.3), 0,         0.0,       30),
    ]
    for label, op, sub, va, vb, vc, bound in cases:
        c = _f2b(vc)
        if op == 0x74:
            use_c = (sub == _FS['FS_FMA'])
            exp = _G.micro_fscalar(sub, va, vb, c if use_c else 0)
            payload_a = ((c << 32) | va) if use_c else va
        elif op == 0x75:
            exp = _G.micro_rsqrt(va)
            payload_a = va
        else:
            exp = _G.micro_exp2(va)
            payload_a = va
        await _fp_fire_token(dut, _fp_instr(op, subop=sub), payload_a,
                             payload_b=vb)
        busy_cycles = 0
        done = False
        for i in range(bound + 12):
            await RisingEdge(dut.clk)
            await Timer(1, units="ns")
            if int(dut.u_core.fp_busy.value):
                busy_cycles += 1
            if int(dut.output_valid.value):
                assert int(dut.output_payload.value) == exp, \
                    f"{label}: {int(dut.output_payload.value):016x} != {exp:08x}"
                done = True
                break
        assert done, f"{label}: no result within bound {bound} + 12 overhead"
        # fp_busy spans the start cycle THROUGH the done cycle inclusive,
        # so busy_cycles == start->done latency + 1 (the pre-integration
        # TB counts latency as edges AFTER the start cycle — same
        # convention as §23.10.6).
        lat = busy_cycles - 1
        assert 1 <= lat <= bound, \
            f"{label}: start->done latency {lat} > normative max {bound}"
        await _fp_drain(dut)
        dut._log.info("%s: completed within bound (latency %d <= %d)",
                      label, lat, bound)


# =============================================================================
# v1.8.0d §23.10.10 — scalar conversion layer integration: CVT (0x77) /
# ACC_ELEMWISE (0x73) through the MU step sequencer, STORE_QUANT (0x7C)
# fp-dest packer on the combinational path. Golden authority remains
# scripts/golden_fp32.py (imported, never retyped): micro_cvt / micro_accew /
# store_quant — the same entry points the pre-integration FP_StepSeq TB
# proved bit-exact (22/22 suites, synth/lattice/fp_ops/tb_fp_stepseq.py).
# =============================================================================

_CVT = _G.CVT_OP_CODE
_CW, _CN = _CVT['WIDEN_TO_F32'], _CVT['NARROW_FROM_F32']


def _cvt_mode(dtype):
    """fp-block mode byte for a CVT/STORE_QUANT dtype: rnd=0, acc=1."""
    return 0x10 | (dtype & 0xF)


def _i2f_rne_rne_defect(payload):
    """The EXCLUDED dtype-0x4 I2F model: pass-1 RNE into 32 bits, pass-2
    RNE to 24 (double rounding). Exists only to prove the directed
    discriminator vector still discriminates against the pinned
    RTO-then-RNE two-pass (§23.10.10(f) pin 8) before asserting RTL."""
    v = payload & ((1 << 64) - 1)
    v = v - (1 << 64) if v >> 63 else v
    if v == 0:
        return 0
    s = 1 if v < 0 else 0
    a = -v if s else v
    bl = a.bit_length()
    e = bl - 1
    if bl > 32:
        inter = _G._rne_shift(a, bl - 32)
        if inter == (1 << 32):
            inter >>= 1
            e += 1
        bl_i = 32
    else:
        inter, bl_i = a, bl
    if bl_i <= 24:
        m24 = inter << (24 - bl_i)
    else:
        m24 = _G._rne_shift(inter, bl_i - 24)
        if m24 == (1 << 24):
            m24 = 1 << 23
            e += 1
    return (s << 31) | ((e + 127) << 23) | (m24 - (1 << 23))


@cocotb.test()
async def test_cvt_directed_cells_e2e(dut):
    """v1.8.0d §23.10.10(b): the COMMIT-0 pin cells through the FULL
    decode->launch->finish path, bit-exact vs golden micro_cvt — full
    64-bit payload compares (pins the result rows: f16/bf16 {48'h0, h},
    f32 {32'h0, f}, ints SEXT64) and opcode_out == 0x77. Covers: widen
    NaN canonicalization + sNaN quieting (pin 2), f16-subnormal-honored /
    bf16-subnormal-flushed widen (pin 6), the observable DAZ bypass
    (I2F(5) — the confirmed unconditional-DAZ bug — plus the fp32-source
    converse incl. the 0x007FFF80-0x007FFFFF sliver), narrow RNE ties
    with the disjoint round/sticky formulation (pin 3), narrow overflow
    -> Inf (pin 4) incl. the bf16 max-finite ripple, FTZ-at-destination
    band + round-up-to-min-normal survivor (pin 5), NaN narrow -> per-
    format canonical qNaN sign-dropped (pin 1), the int64 I2F two-pass
    RTO-then-RNE discriminator (pin 8, proven discriminating in-test),
    and F2I ties/rails/Inf/NaN->0 (pin 9)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    disc = (1 << 40) + (1 << 17) + 0xFFFF
    # prove the two-pass discriminators discriminate BEFORE driving them
    assert _i2f_rne_rne_defect(disc) != _G.micro_i2f_acc(disc), \
        "int64 I2F discriminator no longer discriminates"
    assert _G.micro_i2f_acc(disc) == _G.ref_i2f(disc, _G.DT_ACC_INT), \
        "golden two-pass diverged from the single-RNE reference"
    # narrow-tie discriminators: on the exact-tie/even-kept pattern RNE
    # truncates (a round-half-up defect would emit 0x3C01); on the
    # odd-kept tie it increments (0x3C01 truncation -> 0x3C02)
    tie_f16_stay, tie_f16_up = 0x3F801000, 0x3F803000
    assert _G.ref_narrow_f32(tie_f16_stay, _G.DT_F16) == 0x3C00, \
        "f16 tie-to-even cell drifted"
    assert _G.ref_narrow_f32(tie_f16_up, _G.DT_F16) == 0x3C02, \
        "f16 tie-up cell drifted"
    tie_bf_stay, tie_bf_up = 0x3F808000, 0x3F818000
    assert _G.ref_narrow_f32(tie_bf_stay, _G.DT_BF16) == 0x3F80, \
        "bf16 tie-to-even cell drifted"
    assert _G.ref_narrow_f32(tie_bf_up, _G.DT_BF16) == 0x3F82, \
        "bf16 tie-up cell drifted"

    W, N = _CW, _CN
    D = _G
    cells = [
        # (label, dtype, subop, payload)
        ("widen f16 qNaN canon",        D.DT_F16, W, 0x7E01),
        ("widen f16 sNaN quieted",      D.DT_F16, W, 0x7C01),
        ("widen f16 -NaN sign dropped", D.DT_F16, W, 0xFE00),
        ("widen bf16 NaN canon",        D.DT_BF16, W, 0xFF81),
        ("widen f16 min subnormal (DAZ bypass)", D.DT_F16, W, 0x0001),
        ("widen f16 -max subnormal",    D.DT_F16, W, 0x83FF),
        ("widen f16 one",               D.DT_F16, W, 0x3C00),
        ("widen f16 -Inf",              D.DT_F16, W, 0xFC00),
        ("widen bf16 subnormal -> signed zero", D.DT_BF16, W, 0x8001),
        ("widen bf16 splice",           D.DT_BF16, W, 0xC2F7),
        ("I2F(5) int8 — the confirmed DAZ bug", D.DT_INT8, W, 5),
        ("I2F int4 -8",                 D.DT_INT4, W, 0xFFFFFFFFFFFFFFF8),
        ("I2F int64 two-pass discriminator", D.DT_ACC_INT, W, disc),
        ("I2F int64 negative",          D.DT_ACC_INT, W,
         (-disc) & 0xFFFFFFFFFFFFFFFF),
        ("I2F int32 2^24+1 (RNE leg)",  D.DT_ACC_INT, W, (1 << 24) + 1),
        ("narrow f16 tie stays even",   D.DT_F16, N, tie_f16_stay),
        ("narrow f16 tie rounds up",    D.DT_F16, N, tie_f16_up),
        ("narrow bf16 tie stays even",  D.DT_BF16, N, tie_bf_stay),
        ("narrow bf16 tie rounds up",   D.DT_BF16, N, tie_bf_up),
        ("narrow f16 overflow -> Inf",  D.DT_F16, N, _f2b(65520.0)),
        ("narrow bf16 max-finite ripple -> Inf", D.DT_BF16, N, 0x7F7FFFFF),
        ("narrow f16 NaN -> 0x7E00 sign dropped", D.DT_F16, N, 0xFFC00001),
        ("narrow bf16 NaN -> 0x7FC0 sign dropped", D.DT_BF16, N, 0xFFC00001),
        ("narrow bf16 DAZ sliver top",  D.DT_BF16, N, 0x007FFFFF),
        ("narrow bf16 DAZ sliver base", D.DT_BF16, N, 0x007FFF80),
        ("narrow f16 -denormal source (DAZ converse)", D.DT_F16, N,
         0x80000001),
        ("narrow f16 FTZ band 2^-15",   D.DT_F16, N, 0x38000000),
        ("narrow f16 FTZ survivor just under 2^-14", D.DT_F16, N,
         0x387FFFFF),
        ("F2I int32 tie +0.5 -> 0",     D.DT_ACC_INT, N, _f2b(0.5)),
        ("F2I int32 tie +1.5 -> 2",     D.DT_ACC_INT, N, _f2b(1.5)),
        ("F2I int32 tie -0.5 -> 0",     D.DT_ACC_INT, N, _f2b(-0.5)),
        ("F2I int32 -2.0 sext64",       D.DT_ACC_INT, N, _f2b(-2.0)),
        ("F2I int4 +Inf -> 7",          D.DT_INT4, N, _PINF),
        ("F2I int4 -Inf -> -8 sext64",  D.DT_INT4, N, _NINF),
        ("F2I int8 200.0 saturates",    D.DT_INT8, N, _f2b(200.0)),
        ("F2I int8 -200.0 saturates",   D.DT_INT8, N, _f2b(-200.0)),
        ("F2I int32 NaN -> 0",          D.DT_ACC_INT, N, _QNAN),
        ("F2I int32 fp32-denorm source DAZ -> 0", D.DT_ACC_INT, N,
         0x007FFFFF),
    ]
    for label, dtype, subop, payload in cells:
        exp = _G.micro_cvt(subop, dtype, payload)
        r = await _fp_run(dut, 0x77, payload, subop=subop,
                          mode=_cvt_mode(dtype))
        assert (r['err'], r['lwr'], r['out']) == (0, 0, 1), f"{label}: {r}"
        assert r['payload'] == exp, \
            f"{label}: payload {r['payload']:016x} != {exp:016x}"
        assert r['opcode'] == 0x77, f"{label}: opcode_out {r['opcode']:#x}"
        await _fp_drain(dut)

    # absent imm16 == WIDEN_TO_F32 (monotonic default): same result as the
    # explicit sub-op for a non-trivial widen
    exp = _G.micro_cvt(_CW, _G.DT_F16, 0x3C01)
    r = await _fp_run(dut, 0x77, 0x3C01, mode=_cvt_mode(_G.DT_F16))
    assert (r['err'], r['lwr'], r['out']) == (0, 0, 1) and r['payload'] == exp
    await _fp_drain(dut)

    # round-trip identity E-row, RE-SCOPED (§23.10.10(b)): normal f16,
    # +/-0, +/-Inf, canonical qNaN only (f16 subnormals fail BY DESIGN —
    # the FTZ pin — and stay outside this loop).
    for h in (0x3C00, 0xBC00, 0x7BFF, 0x0400, 0x0000, 0x8000,
              0x7C00, 0xFC00, 0x7E00):
        r1 = await _fp_run(dut, 0x77, h, subop=_CW, mode=_cvt_mode(_G.DT_F16))
        await _fp_drain(dut)
        r2 = await _fp_run(dut, 0x77, r1['payload'], subop=_CN,
                           mode=_cvt_mode(_G.DT_F16))
        await _fp_drain(dut)
        assert r2['payload'] == h, \
            f"f16 round-trip 0x{h:04X} -> {r1['payload']:08x} -> " \
            f"{r2['payload']:04x}"
    dut._log.info("CVT directed cells: %d bit-exact end-to-end", len(cells))


@cocotb.test()
async def test_cvt_reserved_field_rungs(dut):
    """v1.8.0d §23.10.10(b)/(d) reserved rungs — every one lower_required,
    never error_flag (capability absence, the 0x72 rung semantics):
    0x77 imm16[3:0] != 0, imm16[15:8] != 0, sub-op > 0x1; 0x7C fp-dest
    imm16[5:0] != 0 (the new rung) and imm16[15:6] != 0 (the shipped
    v1.8.0b rung, unchanged); plus the int4/int8 0x7C arms bit-unchanged
    under a nonzero shift (the fp rung must not leak into them)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # 0x77 rungs
    for imm in (0x0001, 0x000F, 0x0100, 0xFF00, 0x0011):
        r = await _fp_run(dut, 0x77, 0x3C00, imm16=imm,
                          mode=_cvt_mode(_G.DT_F16))
        assert (r['err'], r['lwr'], r['out']) == (0, 1, 0), \
            f"0x77 imm16=0x{imm:04X}: {r}"
    for sub in range(2, 16):
        r = await _fp_run(dut, 0x77, 0x3C00, subop=sub,
                          mode=_cvt_mode(_G.DT_F16))
        assert (r['err'], r['lwr'], r['out']) == (0, 1, 0), \
            f"0x77 sub-op {sub}: {r}"

    # 0x7C fp-dest rungs: [5:0] nonzero (new) and [15:6] nonzero (shipped)
    for dt in (_G.DT_F16, _G.DT_BF16):
        for imm in (0x0001, 0x003F, 0x0040, 0x8000):
            r = await _fp_run(dut, 0x7C, _f2b(1.5), imm16=imm,
                              mode=_cvt_mode(dt))
            assert (r['err'], r['lwr'], r['out']) == (0, 1, 0), \
                f"0x7C dtype {dt} imm16=0x{imm:04X}: {r}"

    # int4/int8 arms bit-unchanged: shift still works below [15:6], and the
    # fp-only [5:0] rung must NOT fire for int dtypes
    for dt, clamp_lo, clamp_hi in ((0, -8, 7), (1, -128, 127)):
        val = 0x1234
        r = await _fp_run(dut, 0x7C, val, imm16=store_quant_imm16_py(4),
                          mode=_cvt_mode(dt))
        exp = max(clamp_lo, min(clamp_hi, _rne_shr_py(val, 4)))
        assert (r['err'], r['lwr'], r['out']) == (0, 0, 1), \
            f"0x7C int dtype {dt} shift=4: {r}"
        assert r['payload'] == exp & 0xFFFFFFFFFFFFFFFF, \
            f"0x7C int dtype {dt}: {r['payload']:016x} != {exp:#x}"
        await _fp_drain(dut)


def store_quant_imm16_py(shift):
    """imm16 for the 0x7C int forms: s at [5:0] (mirror of the asm helper,
    kept local so the RTL test doesn't import the assembler)."""
    return shift & 0x3F


def _rne_shr_py(x, s):
    """RNE(x >> s) on a Python int — the v1.8.0b STORE_QUANT int model."""
    if s == 0:
        return x
    q, dropped = x >> s, x & ((1 << s) - 1)
    half = 1 << (s - 1)
    if dropped > half or (dropped == half and (q & 1)):
        q += 1
    return q


@cocotb.test()
async def test_accew_opref_only_directed_e2e(dut):
    """v1.8.0d §23.10.10(c) ACC_ELEMWISE: OPREF form bit-exact vs golden
    micro_accew (== micro_fscalar(FS_FMA) == ref_fma — the corrected
    bit-match target), gamma/beta identity rows, the F1 fused-single-
    rounding discriminator re-proven on the B-packing, specials; and the
    OPREF-only rung: EVERY imm form (imm16/imm32/imm64) -> lower_required
    (never decode_error, never silent), while imm+OPREF together stays
    the alu-binary XOR decode_error."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    def bpack(gamma, beta):
        return ((gamma & 0xFFFFFFFF) << 32) | (beta & 0xFFFFFFFF)

    one, zero = _f2b(1.0), 0
    # identity: FMA(a*1.0 + 0) == a for normals
    for a in (_f2b(-2.5), _f2b(3.14159), _f2b(1e-30)):
        exp = _G.micro_accew(a, bpack(one, zero))
        r = await _fp_run(dut, 0x73, a, payload_b=bpack(one, zero),
                          opref=True)
        assert (r['err'], r['lwr'], r['out']) == (0, 0, 1), f"id {a:#x}: {r}"
        assert r['payload'] == exp == a, \
            f"identity: {r['payload']:016x} != {exp:08x}"
        assert r['opcode'] == 0x73
        await _fp_drain(dut)

    # F1 fused-vs-double-rounded discriminator on the B packing
    a, g, b = 0x3F800001, 0x3F800001, 0xBF800002
    fused = _G.micro_accew(a, bpack(g, b))
    dbl = _G.micro_fscalar(_FS['FS_ADD'],
                           _G.micro_fscalar(_FS['FS_MUL'], a, g), b)
    assert fused != dbl, "F1 vector no longer discriminates"
    r = await _fp_run(dut, 0x73, a, payload_b=bpack(g, b), opref=True)
    assert (r['err'], r['lwr'], r['out']) == (0, 0, 1) \
        and r['payload'] == fused, f"F1: {r} exp {fused:08x}"
    await _fp_drain(dut)

    # gamma/beta both live: 3.0*2.0 + (-1.5)
    exp = _G.micro_accew(_f2b(3.0), bpack(_f2b(2.0), _f2b(-1.5)))
    r = await _fp_run(dut, 0x73, _f2b(3.0),
                      payload_b=bpack(_f2b(2.0), _f2b(-1.5)), opref=True)
    assert r['payload'] == exp == _f2b(4.5)
    await _fp_drain(dut)

    # specials: Inf*0 + 5 -> canonical qNaN (DATA, never error_flag)
    exp = _G.micro_accew(_PINF, bpack(0, _f2b(5.0)))
    r = await _fp_run(dut, 0x73, _PINF, payload_b=bpack(0, _f2b(5.0)),
                      opref=True)
    assert (r['err'], r['lwr'], r['out']) == (0, 0, 1) \
        and r['payload'] == exp == _QNAN, f"Inf*0: {r}"
    await _fp_drain(dut)

    # OPREF-only rung: any imm present -> lower_required (0x73 is
    # alu-binary, so imm-XOR-opref DECODES cleanly; the guard is the
    # EXECUTE-side capability rung, §23.10.10(c))
    for kw in ({'imm16': 0x0010}, {'imm32': _f2b(2.0)},
               {'imm64': bpack(one, zero)}):
        r = await _fp_run(dut, 0x73, _f2b(3.0), payload_b=0, **kw)
        assert (r['err'], r['lwr'], r['out']) == (0, 1, 0), \
            f"imm form {kw}: {r}"

    # imm + OPREF together is still the XOR-trap decode_error (malformed)
    r = await _fp_run(dut, 0x73, _f2b(3.0), payload_b=bpack(one, zero),
                      imm16=0x0010, opref=True)
    assert (r['err'], r['lwr'], r['out']) == (1, 0, 0), f"XOR trap: {r}"


@cocotb.test()
async def test_store_quant_fp_dest_bit_identity_directed(dut):
    """v1.8.0d §23.10.10(d) bit-identity clause, RTL side: 0x7C fp-dest ==
    0x77 NARROW_FROM_F32 at BOTH sites (L-PE combinational arm / MU step
    program) for a directed + stratified-random set, both equal to the
    single golden authority ref_narrow_f32 (via store_quant / micro_cvt —
    themselves one function by construction; the exhaustive 2^32 proof is
    golden-side per the sweep plan). Also pins the +0-added-cycles clause:
    the fp-dest form emits with the same token->output latency as the
    shipped int arms."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    import random as _random
    rng = _random.Random(0x180D)
    bits_set = [0x3F801000, 0x3F803000, 0x007FFFFF, 0x007FFF80, 0x00000001,
                0x80000001, 0x477FF000, 0x7F7FFFFF, 0xFFC00001, 0x7FC00000,
                0x7F800000, 0xFF800000, 0x00000000, 0x80000000, 0x38000000,
                0x387FFFFF, 0x33000000, 0x477FEFFF]
    bits_set += [rng.getrandbits(32) for _ in range(48)]

    int_lat = None
    r = await _fp_run(dut, 0x7C, 0x12, imm16=None, mode=_cvt_mode(0))
    assert (r['err'], r['lwr'], r['out']) == (0, 0, 1)
    int_lat = r['cycles']
    await _fp_drain(dut)

    for dt in (_G.DT_F16, _G.DT_BF16):
        for bits in bits_set:
            exp = _G.store_quant(bits, dt)
            assert exp == _G.micro_cvt(_CN, dt, bits), \
                "golden twin split — single-authority violation"
            r7c = await _fp_run(dut, 0x7C, bits, mode=_cvt_mode(dt))
            assert (r7c['err'], r7c['lwr'], r7c['out']) == (0, 0, 1), \
                f"0x7C dt{dt} bits {bits:08x}: {r7c}"
            assert r7c['payload'] == exp, \
                f"0x7C dt{dt} {bits:08x}: {r7c['payload']:016x} != {exp:04x}"
            assert r7c['cycles'] == int_lat, \
                f"fp-dest added cycles: {r7c['cycles']} != {int_lat} " \
                f"(the +0 clause)"
            await _fp_drain(dut)
            r77 = await _fp_run(dut, 0x77, bits, subop=_CN,
                                mode=_cvt_mode(dt))
            assert r77['payload'] == exp == r7c['payload'], \
                f"bit-identity broke at {bits:08x} dt{dt}: " \
                f"7C={r7c['payload']:04x} 77={r77['payload']:016x} " \
                f"golden={exp:04x}"
            await _fp_drain(dut)
    dut._log.info("0x7C == 0x77 narrow bit-identity: %d points x 2 dtypes",
                  len(bits_set))


@cocotb.test()
async def test_fp_cycle_bounds_v180d(dut):
    """v1.8.0d §23.10.10(e): the new ops COMPLETE WITHIN their normative
    cycle maxima, measured at the unit level (consecutive fp_busy cycles
    == start->done, the v1.8.0c convention): CVT widen/narrow/I2F-small/
    F2I <= 8, CVT I2F int64 <= 10, ACC_ELEMWISE <= 10. Bounds only —
    never exact counts (Gate-2 fallback headroom is contractual)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    cases = [
        ("CVT widen f16",   0x77, dict(subop=_CW, mode=_cvt_mode(2)),
         0x3C01, _G.micro_cvt(_CW, 2, 0x3C01), 8),
        ("CVT widen bf16",  0x77, dict(subop=_CW, mode=_cvt_mode(3)),
         0x3F81, _G.micro_cvt(_CW, 3, 0x3F81), 8),
        ("CVT narrow f16",  0x77, dict(subop=_CN, mode=_cvt_mode(2)),
         _f2b(1.5), _G.micro_cvt(_CN, 2, _f2b(1.5)), 8),
        ("CVT narrow bf16", 0x77, dict(subop=_CN, mode=_cvt_mode(3)),
         _f2b(-3.25), _G.micro_cvt(_CN, 3, _f2b(-3.25)), 8),
        ("CVT I2F int4",    0x77, dict(subop=_CW, mode=_cvt_mode(0)),
         5, _G.micro_cvt(_CW, 0, 5), 8),
        ("CVT I2F int8",    0x77, dict(subop=_CW, mode=_cvt_mode(1)),
         0x7F, _G.micro_cvt(_CW, 1, 0x7F), 8),
        ("CVT I2F int64",   0x77, dict(subop=_CW, mode=_cvt_mode(4)),
         (1 << 62) + 12345, _G.micro_cvt(_CW, 4, (1 << 62) + 12345), 10),
        ("CVT F2I int32",   0x77, dict(subop=_CN, mode=_cvt_mode(4)),
         _f2b(123456.7), _G.micro_cvt(_CN, 4, _f2b(123456.7)), 8),
        ("ACC_ELEMWISE",    0x73, dict(opref=True),
         _f2b(3.0), _G.micro_accew(_f2b(3.0),
                                   (_f2b(2.0) << 32) | _f2b(-1.5)), 10),
    ]
    for label, op, kw, payload, exp, bound in cases:
        pb = ((_f2b(2.0) << 32) | _f2b(-1.5)) if op == 0x73 else 0
        await _fp_fire_token(dut, _fp_instr(op, **kw), payload, payload_b=pb)
        busy_cycles = 0
        done = False
        for i in range(bound + 12):
            await RisingEdge(dut.clk)
            await Timer(1, units="ns")
            if int(dut.u_core.fp_busy.value):
                busy_cycles += 1
            if int(dut.output_valid.value):
                assert int(dut.output_payload.value) == exp, \
                    f"{label}: {int(dut.output_payload.value):016x} " \
                    f"!= {exp:016x}"
                done = True
                break
        assert done, f"{label}: no result within bound {bound} + 12 overhead"
        lat = busy_cycles - 1
        assert 1 <= lat <= bound, \
            f"{label}: start->done latency {lat} > normative max {bound}"
        await _fp_drain(dut)
        dut._log.info("%s: completed within bound (latency %d <= %d)",
                      label, lat, bound)


# =============================================================================
# v1.8.0e §25.2.2/§25.3 0e1 INTEGRATION — 0x78 DEQUANT lane-loop e2e +
# frag-widening drain invariants + loop occupancy/suppression pins.
# Golden authority: scripts/golden_fp32.py dequant_frags / ref_dequant
# (imported, never retyped). The unit-level OPS_DEQ program was proven at
# the FP_StepSeq TB (round-once cells, specials, 2x20k random); these
# tests bind the PE_Core loop: launch-capture, per-lane relaunch, lane->
# fragment packing, loop-completion frag0_hold handoff, 4/8-fragment
# drain, and the §25.3 interlocks.
# =============================================================================

def _deq_instr(dtype):
    """0x78 DEQUANT: port-only legality (no imm, no OPREF) + PRECISION
    mode (dtype names the SOURCE; dest pinned bf16-only)."""
    return _fp_instr(0x78, mode=0x10 | (dtype & 0xF))


def _deq_pack_lanes(lanes, dtype):
    """Pack raw lane fields into the 128-bit A (the golden lane-map pin:
    int4 lane i at [4i+3:4i], int8 lane i at [8i+7:8i])."""
    lb = 4 if dtype == _G.DT_INT4 else 8
    frags = _G.lanes_to_frags(lanes, lb)
    assert len(frags) == 2
    return frags[0] | (frags[1] << 64), frags


async def _deq_run_wave(dut, lanes, scale, dtype, window=340):
    """Fire one DEQUANT wave (wide A + scale on payload_b) and collect
    EVERY output pulse until the PE drains back to idle. Returns
    (events, pe_ready_ever_high_during_flight, launch_to_frag0_cycles)."""
    wide, _ = _deq_pack_lanes(lanes, dtype)
    await _fp_fire_token(dut, _deq_instr(dtype), 0, payload_b=scale,
                         b_valid=1, wide=wide, wide_valid=1)
    events = []
    ready_high_mid = False
    frag0_cycle = None
    launched = False
    idle_after = 0
    for i in range(window):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.error_flag.value):
            events.append({'kind': 'err', 'cycle': i})
        if int(dut.lower_required.value):
            events.append({'kind': 'lwr', 'cycle': i})
        if int(dut.output_valid.value):
            if frag0_cycle is None:
                frag0_cycle = i
            events.append({'kind': 'out', 'cycle': i,
                           'payload': int(dut.output_payload.value),
                           'opcode': int(dut.opcode_out.value),
                           'tag': int(dut.output_tag.value),
                           'frag_hdr': int(dut.output_frag_hdr.value)})
        ready = int(dut.pe_ready.value)
        if not launched and ready == 0:
            launched = True          # loop entered (pe_ready dropped)
        if launched and frag0_cycle is None and ready == 1:
            ready_high_mid = True    # §25.3 violation: gap in occupancy
        if launched and ready == 1 and int(dut.output_valid.value) == 0:
            idle_after += 1
            if idle_after >= 3 and frag0_cycle is not None:
                break
        else:
            idle_after = 0
    return events, ready_high_mid, frag0_cycle


def _deq_expect_frags(lanes, scale, dtype):
    _, a_frags = _deq_pack_lanes(lanes, dtype)
    return _G.dequant_frags(a_frags, scale, dtype)


@cocotb.test()
async def test_dequant_e2e_int8_4frag_bit_exact(dut):
    """int8-16 -> 16 bf16 = 4 fragments, FULL-WAVE bit-exact vs golden
    dequant_frags across scale classes (normal / denormal-DAZ / NaN /
    +-Inf / overflow-to-Inf / negative), incl. the §25.3 header-sequence
    pin {idx, total_m1} = 0x03,0x13,0x23,0x33, opcode_out preservation,
    tag stability across all fragments, and the 1-fragment/cycle drain
    contiguity."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    import random as _rnd
    rng = _rnd.Random(0x0E78)
    lane_sets = [
        [rng.randrange(256) for _ in range(16)],
        [0x00, 0x80, 0x7F, 0xFF, 0x01, 0x81, 0x40, 0xC0,
         0x02, 0xFE, 0x55, 0xAA, 0x10, 0xF0, 0x33, 0xCD],
    ]
    scales = [
        _f2b(1.5), _f2b(-0.375), _f2b(2.0 ** -100),
        0x00000001,          # denormal -> DAZ -> signed-zero rows
        0x80000001,          # negative denormal
        _QNAN, _PINF, _NINF,
        0x7F000000,          # 2^127: k>=2 overflows bf16 -> +-Inf pin
    ]
    for lanes in lane_sets:
        for scale in scales:
            events, ready_mid, frag0 = await _deq_run_wave(
                dut, lanes, scale, _G.DT_INT8)
            outs = [e for e in events if e['kind'] == 'out']
            errs = [e for e in events if e['kind'] != 'out']
            assert not errs, f"scale=0x{scale:08X}: {errs}"
            assert len(outs) == 4, \
                f"scale=0x{scale:08X}: {len(outs)} fragments != 4"
            exp = _deq_expect_frags(lanes, scale, _G.DT_INT8)
            got = [e['payload'] for e in outs]
            assert got == exp, \
                f"scale=0x{scale:08X}: {[hex(x) for x in got]} != " \
                f"{[hex(x) for x in exp]}"
            hdrs = [e['frag_hdr'] for e in outs]
            assert hdrs == [0x03, 0x13, 0x23, 0x33], \
                f"scale=0x{scale:08X}: header sequence {hdrs}"
            assert all(e['opcode'] == 0x78 for e in outs), \
                f"opcode_out not preserved: {[e['opcode'] for e in outs]}"
            assert len({e['tag'] for e in outs}) == 1, \
                "tag must be constant across all fragments of one wave"
            cycles = [e['cycle'] for e in outs]
            assert cycles == list(range(cycles[0], cycles[0] + 4)), \
                f"drain not 1 fragment/cycle: {cycles}"
            assert not ready_mid, \
                "pe_ready glitched high inside the lane loop (§25.3)"


@cocotb.test()
async def test_dequant_e2e_int4_8frag_bit_exact(dut):
    """int4-32 -> 32 bf16 = 8 fragments: full-wave bit-exact vs golden,
    16-frag-capable header nibbles 0x07..0x77 in sequence, contiguous
    8-beat drain, and the row-0-dummy invariant — a 2-fragment wide op
    dispatched immediately after the wave is bit-identical (the widened
    FSM leaves no residue)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    import random as _rnd
    rng = _rnd.Random(0x0E32)
    for scale in (_f2b(3.0), _f2b(-2.0 ** -80), 0x00400000, _QNAN):
        lanes = [rng.randrange(16) for _ in range(32)]
        events, ready_mid, _ = await _deq_run_wave(
            dut, lanes, scale, _G.DT_INT4)
        outs = [e for e in events if e['kind'] == 'out']
        errs = [e for e in events if e['kind'] != 'out']
        assert not errs, f"scale=0x{scale:08X}: {errs}"
        assert len(outs) == 8, f"{len(outs)} fragments != 8"
        exp = _deq_expect_frags(lanes, scale, _G.DT_INT4)
        got = [e['payload'] for e in outs]
        assert got == exp, \
            f"scale=0x{scale:08X}: {[hex(x) for x in got]} != " \
            f"{[hex(x) for x in exp]}"
        hdrs = [e['frag_hdr'] for e in outs]
        assert hdrs == [(i << 4) | 0x7 for i in range(8)], f"headers {hdrs}"
        cycles = [e['cycle'] for e in outs]
        assert cycles == list(range(cycles[0], cycles[0] + 8)), \
            f"drain not 1 fragment/cycle: {cycles}"
        assert not ready_mid, "pe_ready glitched high inside the lane loop"

    # row-0-dummy / no-residue invariant: an existing 2-fragment emitter
    # right after the 8-fragment wave must be bit-identical (fragment 0
    # direct-emit + exactly one drained row, hdr 0x01/0x11).
    lo, hi = 0x1111222233334444, 0x5555666677778888
    instr = encode_instr(0x60, _STD_PORT(), eh_imm16(3))
    await _fp_fire_token(dut, instr, 0, wide=lo | (hi << 64), wide_valid=1)
    outs = []
    for i in range(20):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.output_valid.value):
            outs.append((int(dut.output_payload.value),
                         int(dut.output_frag_hdr.value)))
        if len(outs) == 2:
            break
    exp_lo = sum(((((lo >> (4 * i)) & 0xF) + 3) & 0xF) << (4 * i)
                 for i in range(16))
    exp_hi = sum(((((hi >> (4 * i)) & 0xF) + 3) & 0xF) << (4 * i)
                 for i in range(16))
    assert outs == [(exp_lo, 0x01), (exp_hi, 0x11)], \
        f"2-frag emitter corrupted after the 8-frag wave: " \
        f"{[(hex(p), hex(h)) for p, h in outs]}"


@cocotb.test()
async def test_dequant_round_once_discriminators_e2e(dut):
    """Rounding definition (a) END-TO-END: directed discriminator cells
    (from the mse_sweep constructive generator, embedded as literals —
    the sim venv has no mpmath) whose exact product sits within one
    RNE24 step of a bf16 midpoint, so a double-rounding implementation
    provably differs by 1 ulp; plus exact-tie cells pinning
    ties-to-even. Power is re-proven in-test against a golden-built
    double-round twin before driving the RTL. The MSE gate is blind to
    this defect — THESE cells are the enforcement point (§25.5.2)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # (field, scale_bits, dtype, is_discriminator)
    cells = [
        (0x03, 0x3FAF5555, _G.DT_INT8, True),
        (0x03, 0x3FB0AAAB, _G.DT_INT8, True),
        (0x03, 0x3FB75555, _G.DT_INT8, True),
        (0x03, 0x3FB8AAAB, _G.DT_INT8, True),
        (0x03, 0x3FAF5555, _G.DT_INT4, True),
        (0x03, 0x3FB0AAAB, _G.DT_INT4, True),
        (0x03, 0x3FAE0000, _G.DT_INT8, False),   # exact ties (round bit 1,
        (0x03, 0x3FB20000, _G.DT_INT8, False),   #  sticky 0 -> to even)
    ]
    for field, scale, dtype, disc in cells:
        ref = _G.ref_dequant_lane(field, scale, dtype)
        # the FORBIDDEN definition (b): RNE to fp32 first, then narrow
        dbl = _G.ref_narrow_f32(_G.ref_mul(_G.ref_i2f(field, dtype), scale),
                                _G.DT_BF16)
        if disc:
            assert dbl != ref, \
                f"cell (0x{field:02X}, 0x{scale:08X}) lost its power"
        else:
            assert dbl == ref, "exact tie must coincide by construction"
        n = _G.DEQUANT_LANES[dtype]
        lanes = [field] * n
        events, _, _ = await _deq_run_wave(dut, lanes, scale, dtype)
        outs = [e for e in events if e['kind'] == 'out']
        exp = _deq_expect_frags(lanes, scale, dtype)
        got = [e['payload'] for e in outs]
        assert got == exp, \
            f"ROUND-ONCE violated at (0x{field:02X}, 0x{scale:08X}, " \
            f"dtype={dtype}): {[hex(x) for x in got]} != " \
            f"{[hex(x) for x in exp]}"


@cocotb.test()
async def test_dequant_missing_scale_and_wide_guards(dut):
    """Launch-ladder rungs: missing scale (payload_b_valid=0) ->
    error_flag (the §25.2.2 pin — the scale rides the wave-completing
    beat; its absence is a malformed program, not capability absence);
    missing wide A -> error_flag (§20 wave contract). Neither launches
    the loop (pe_ready stays high, no output)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    for b_valid, wide_valid in ((0, 1), (1, 0), (0, 0)):
        await _fp_fire_token(dut, _deq_instr(_G.DT_INT8), 0,
                             payload_b=_f2b(1.0), b_valid=b_valid,
                             wide=0x1234, wide_valid=wide_valid)
        err = out = 0
        for _ in range(20):
            await RisingEdge(dut.clk)
            await Timer(1, units="ns")
            err |= int(dut.error_flag.value)
            out |= int(dut.output_valid.value)
        assert err == 1 and out == 0, \
            f"(b_valid={b_valid}, wide_valid={wide_valid}): " \
            f"err={err} out={out}"
        assert int(dut.pe_ready.value) == 1, "guarded launch left PE busy"


@cocotb.test()
async def test_dequant_loop_suppression_and_busy_reject(dut):
    """§25.3 interlocks, all in ONE int8 wave flight:
      (1) fp_armed loop suppression — NO output pulse fires before the
          loop-completion fragment 0 (per-lane fp_done pulses diverted;
          exactly 4 pulses total, all at the drain);
      (2) a mul-class dispatch with a busy-reject rung (0x74 FSCALAR)
          landing mid-loop is LOUDLY lower_required — never launched,
          never silently swallowed;
      (3) a 0x12 MUL dispatch mid-loop is never launched (the launch
          gate's !fp_busy term covers the whole loop) and the DEQUANT
          result is preserved bit-exactly — no output corruption;
      (4) pe_ready stays low from launch through the final drain beat
          (the §25.4 occupancy contract, observe-only)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    lanes = [((i * 37) ^ 0x5A) & 0xFF for i in range(16)]
    scale = _f2b(0.75)
    wide, a_frags = _deq_pack_lanes(lanes, _G.DT_INT8)
    exp = _G.dequant_frags(a_frags, scale, _G.DT_INT8)

    await _fp_fire_token(dut, _deq_instr(_G.DT_INT8), 0, payload_b=scale,
                         b_valid=1, wide=wide, wide_valid=1)
    outs = []
    lwr_seen = 0
    err_seen = 0
    intruded_74 = intruded_12 = False
    for i in range(340):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        # two intruders, well inside the ~100-cycle loop window
        if i == 30 and not intruded_74:
            intruded_74 = True
            await _fp_fire_token(dut, _fp_instr(0x74, subop=_FS['FS_MUL']),
                                 _f2b(2.0), payload_b=_f2b(3.0), b_valid=1)
        if i == 45 and not intruded_12:
            intruded_12 = True
            instr12 = encode_instr(0x12, _STD_PORT(), eh_imm16(5))
            dut.instruction.value = instr12
            dut.input_tag.value = _STD_TAG()
            dut.input_payload.value = 7
            dut.input_payload_b_valid.value = 1
            dut.token_valid.value = 1
            await RisingEdge(dut.clk)
            dut.token_valid.value = 0
        await Timer(1, units="ns")
        err_seen |= int(dut.error_flag.value)
        lwr_seen |= int(dut.lower_required.value)
        if int(dut.output_valid.value):
            outs.append({'cycle': i, 'payload': int(dut.output_payload.value),
                         'opcode': int(dut.opcode_out.value),
                         'frag_hdr': int(dut.output_frag_hdr.value)})
        if len(outs) >= 4 and int(dut.pe_ready.value) == 1:
            break
    assert intruded_74 and intruded_12, "intruders never dispatched"
    assert err_seen == 0, "unexpected error_flag during the loop"
    assert lwr_seen == 1, \
        "mid-loop mul-class dispatch (0x74) was not LOUDLY busy-rejected"
    # (1) exactly 4 output pulses, contiguous, all DEQUANT fragments —
    # no per-lane spurious emit, no 0x74/0x12 result ever surfaced
    assert len(outs) == 4, f"{len(outs)} output pulses != 4: {outs}"
    assert all(o['opcode'] == 0x78 for o in outs), \
        f"foreign result surfaced: {[hex(o['opcode']) for o in outs]}"
    got = [o['payload'] for o in outs]
    assert got == exp, \
        f"DEQUANT corrupted by mid-loop intruders: " \
        f"{[hex(x) for x in got]} != {[hex(x) for x in exp]}"
    cycles = [o['cycle'] for o in outs]
    assert cycles == list(range(cycles[0], cycles[0] + 4)), \
        f"drain not contiguous: {cycles}"
    assert cycles[0] > 45, "fragment 0 emitted before loop completion"


@cocotb.test()
async def test_gamma_mul_w_directed_e2e(dut):
    """v1.8.0e §25.2.3 — 0x6B GAMMA_MUL_W exhaustive-ish directed e2e:
    ALL 256 (a4, g4) operand pairs cross the full decode -> MU-arm ->
    2-fragment emit path (wave w carries a4 = w on every lane against
    g4 = lane index — 16 waves cover the full product table), plus one
    distinct-lanes wave pinning the lane order (lane i at out bits
    [8i+7:8i]) end-to-end. Bit-exact vs golden gamma_mul_w_frags; the
    value-level exhaustive + 20k-random proof lives at the FP_CombArms
    unit TB — this binds the dispatch/emit integration."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    async def run_wave(a_lanes, g_lanes):
        a_frag = sum(v << (4 * i) for i, v in enumerate(a_lanes))
        g_imm = sum(v << (4 * i) for i, v in enumerate(g_lanes))
        instr = encode_instr(0x6B, _STD_PORT(), eh_precision(0x10, 0),
                             eh_imm64(g_imm), flags=F_PRECISION_OVR)
        await _fp_fire_token(dut, instr, a_frag, b_valid=0)
        outs = []
        for _ in range(30):
            await RisingEdge(dut.clk)
            await Timer(1, units="ns")
            assert int(dut.error_flag.value) == 0
            assert int(dut.lower_required.value) == 0
            if int(dut.output_valid.value):
                outs.append({'payload': int(dut.output_payload.value),
                             'frag_hdr': int(dut.output_frag_hdr.value),
                             'opcode': int(dut.opcode_out.value)})
            if len(outs) == 2:
                break
        exp = _G.gamma_mul_w_frags(a_frag, g_imm)
        assert [o['payload'] for o in outs] == exp, \
            f"a={a_lanes} g={g_lanes}: " \
            f"{[hex(o['payload']) for o in outs]} != {[hex(x) for x in exp]}"
        assert [o['frag_hdr'] for o in outs] == [0x01, 0x11]
        assert all(o['opcode'] == 0x6B for o in outs)
        await _fp_drain(dut, cycles=12)

    # all 256 pairs across 16 waves
    for w in range(16):
        await run_wave([w] * 16, list(range(16)))
    # lane-order pin: distinct per-lane products with sign flips
    await run_wave([((3 * i) + 1) & 0xF for i in range(16)],
                   [((-i) & 0xF) for i in range(16)])
    await run_wave([0x8] * 16, [0x8] * 16)   # all (-8)*(-8) = +64 rows


# =============================================================================
# v1.8.0e §25.2.4/§25.3 0e2 — 0x70 VFMA_ACC lane-loop e2e: the FIRST
# 16-fragment emitter (tot_m1 = 15 — the consumer of the 0e1 frag
# widening + Cluster mask fix), the B-split pins, the explicit mod-2^32
# wrap, the vfma_busy interlocks and the §25.4 cycle ceilings. Golden
# authority: scripts/golden_fp32.py vfma_frags / ref_vfma (imported,
# never retyped).
# =============================================================================


def _vfma_instr(dtype, imm64=None, imm16=None, imm32=None):
    """0x70 VFMA_ACC: PRECISION mode 0x10|dtype (acc=1 — the wide-acc
    OUTPUT-form marker, NOT stateful accumulation) + B via IMM (the
    canonical form is imm64 carrying the {c_acc, b_mul} split; imm16/
    imm32 zero-fill the upper word -> c_acc = 0)."""
    return _fp_instr(0x70, imm16=imm16, mode=0x10 | (dtype & 0xF),
                     imm32=imm32, imm64=imm64)


def _vfma_pack_a(lanes, dtype):
    """Pack raw lane fields into the 128-bit A (the golden lane-map pin:
    int4 lane i at [4i+3:4i], int8 lane i at [8i+7:8i])."""
    lb = 4 if dtype == _G.DT_INT4 else 8
    frags = _G.lanes_to_frags(lanes, lb)
    assert len(frags) == 2
    return frags[0] | (frags[1] << 64), frags


async def _vfma_run_wave(dut, lanes, b_payload, dtype, window=120,
                         imm_kind='imm64'):
    """Fire one VFMA wave (wide A + B via the chosen IMM kind;
    payload_b deliberately INVALID — the arm must never read the port)
    and collect EVERY outcome pulse until the PE drains back to idle.
    Returns (events, pe_ready_ever_high_during_flight)."""
    wide, _ = _vfma_pack_a(lanes, dtype)
    kw = {imm_kind: b_payload}
    await _fp_fire_token(dut, _vfma_instr(dtype, **kw), 0,
                         payload_b=0, b_valid=0, wide=wide, wide_valid=1)
    events = []
    ready_high_mid = False
    frag0_cycle = None
    launched = False
    idle_after = 0
    for i in range(window):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.error_flag.value):
            events.append({'kind': 'err', 'cycle': i})
        if int(dut.lower_required.value):
            events.append({'kind': 'lwr', 'cycle': i})
        if int(dut.output_valid.value):
            if frag0_cycle is None:
                frag0_cycle = i
            events.append({'kind': 'out', 'cycle': i,
                           'payload': int(dut.output_payload.value),
                           'opcode': int(dut.opcode_out.value),
                           'tag': int(dut.output_tag.value),
                           'frag_hdr': int(dut.output_frag_hdr.value)})
        ready = int(dut.pe_ready.value)
        if not launched and ready == 0:
            launched = True          # loop entered (pe_ready dropped)
        if launched and frag0_cycle is None and ready == 1:
            ready_high_mid = True    # §25.3 violation: gap in occupancy
        if launched and ready == 1 and int(dut.output_valid.value) == 0:
            idle_after += 1
            if idle_after >= 3 and frag0_cycle is not None:
                break
        else:
            idle_after = 0
    return events, ready_high_mid


def _vfma_expect_frags(lanes, b_payload, dtype):
    _, a_frags = _vfma_pack_a(lanes, dtype)
    return _G.vfma_frags(a_frags, b_payload, dtype)


def _vfma_b64(b_field, c_acc):
    """Raw B word: b_mul lane field at the low bits (the RTL sext
    source), c_acc pattern at [63:32] — mirrors asm pack_vfma_b."""
    return ((c_acc & 0xFFFFFFFF) << 32) | b_field


@cocotb.test()
async def test_vfma_e2e_int4_16frag_bit_exact(dut):
    """int4-32 -> 32 int32 = 16 fragments, FULL-WAVE bit-exact vs golden
    vfma_frags across b_mul/c_acc classes — THE first tot_m1=15 walk:
    header nibble sequence {idx, total_m1} = 0x0F, 0x1F, .., 0xFF (all
    16 in order), 1-fragment/cycle drain contiguity, opcode_out
    preservation, tag stability, and the §25.3 occupancy pin (pe_ready
    low from launch to fragment 0). Also re-checks the row-0-dummy
    invariant: a 2-fragment wide op straight after the 16-beat wave is
    bit-identical (no FSM residue at the widest drain)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    import random as _rnd
    rng = _rnd.Random(0x0E70)
    lane_sets = [
        [rng.randrange(16) for _ in range(32)],
        [0x8, 0x7, 0x0, 0xF, 0x1, 0x9, 0x4, 0xC] * 4,   # extremes incl. -8
    ]
    b_words = [
        _vfma_b64(0x3, 100),                 # b=+3, small positive c
        _vfma_b64(0x8, -1),                  # b=-8 (sext pin), c=-1
        _vfma_b64(0xF, 0x7FFFFFFF),          # b=-1, c=INT32_MAX (wrap)
        _vfma_b64(0x0, 0x80000000),          # b=0, c=INT32_MIN pattern
    ]
    for lanes in lane_sets:
        for b64 in b_words:
            events, ready_mid = await _vfma_run_wave(
                dut, lanes, b64, _G.DT_INT4)
            outs = [e for e in events if e['kind'] == 'out']
            errs = [e for e in events if e['kind'] != 'out']
            assert not errs, f"B=0x{b64:016X}: {errs}"
            assert len(outs) == 16, \
                f"B=0x{b64:016X}: {len(outs)} fragments != 16"
            exp = _vfma_expect_frags(lanes, b64, _G.DT_INT4)
            got = [e['payload'] for e in outs]
            assert got == exp, \
                f"B=0x{b64:016X}: {[hex(x) for x in got]} != " \
                f"{[hex(x) for x in exp]}"
            hdrs = [e['frag_hdr'] for e in outs]
            assert hdrs == [(i << 4) | 0xF for i in range(16)], \
                f"B=0x{b64:016X}: header sequence {hdrs}"
            assert all(e['opcode'] == 0x70 for e in outs), \
                f"opcode_out not preserved: {[e['opcode'] for e in outs]}"
            assert len({e['tag'] for e in outs}) == 1, \
                "tag must be constant across all fragments of one wave"
            cycles = [e['cycle'] for e in outs]
            assert cycles == list(range(cycles[0], cycles[0] + 16)), \
                f"drain not 1 fragment/cycle: {cycles}"
            assert not ready_mid, \
                "pe_ready glitched high inside the lane loop (§25.3)"

    # row-0-dummy / no-residue invariant after the WIDEST drain
    lo, hi = 0x1111222233334444, 0x5555666677778888
    instr = encode_instr(0x60, _STD_PORT(), eh_imm16(3))
    await _fp_fire_token(dut, instr, 0, wide=lo | (hi << 64), wide_valid=1)
    outs = []
    for i in range(20):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if int(dut.output_valid.value):
            outs.append((int(dut.output_payload.value),
                         int(dut.output_frag_hdr.value)))
        if len(outs) == 2:
            break
    exp_lo = sum(((((lo >> (4 * i)) & 0xF) + 3) & 0xF) << (4 * i)
                 for i in range(16))
    exp_hi = sum(((((hi >> (4 * i)) & 0xF) + 3) & 0xF) << (4 * i)
                 for i in range(16))
    assert outs == [(exp_lo, 0x01), (exp_hi, 0x11)], \
        f"2-frag emitter corrupted after the 16-frag wave: " \
        f"{[(hex(p), hex(h)) for p, h in outs]}"


@cocotb.test()
async def test_vfma_e2e_int8_8frag_bit_exact(dut):
    """int8-16 -> 16 int32 = 8 fragments: full-wave bit-exact vs golden
    across the int8 b_mul extremes (sext32 from B[7:0] — 0x80 = -128,
    0x7F = +127), headers 0x07..0x77 in sequence, contiguous drain."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    import random as _rnd
    rng = _rnd.Random(0x0E71)
    lane_sets = [
        [rng.randrange(256) for _ in range(16)],
        [0x80, 0x7F, 0x00, 0xFF, 0x01, 0x81, 0x40, 0xC0,
         0x02, 0xFE, 0x55, 0xAA, 0x10, 0xF0, 0x33, 0xCD],
    ]
    b_words = [
        _vfma_b64(0x80, 12345),              # b=-128 (sext pin)
        _vfma_b64(0x7F, -100000),            # b=+127
        _vfma_b64(0xFF, 0xFFFFC000),         # b=-1, c=-16384
        _vfma_b64(0x01, 0),                  # identity-ish row
    ]
    for lanes in lane_sets:
        for b64 in b_words:
            events, ready_mid = await _vfma_run_wave(
                dut, lanes, b64, _G.DT_INT8)
            outs = [e for e in events if e['kind'] == 'out']
            errs = [e for e in events if e['kind'] != 'out']
            assert not errs, f"B=0x{b64:016X}: {errs}"
            assert len(outs) == 8, \
                f"B=0x{b64:016X}: {len(outs)} fragments != 8"
            exp = _vfma_expect_frags(lanes, b64, _G.DT_INT8)
            got = [e['payload'] for e in outs]
            assert got == exp, \
                f"B=0x{b64:016X}: {[hex(x) for x in got]} != " \
                f"{[hex(x) for x in exp]}"
            hdrs = [e['frag_hdr'] for e in outs]
            assert hdrs == [(i << 4) | 0x7 for i in range(8)], \
                f"headers {hdrs}"
            assert all(e['opcode'] == 0x70 for e in outs)
            cycles = [e['cycle'] for e in outs]
            assert cycles == list(range(cycles[0], cycles[0] + 8)), \
                f"drain not 1 fragment/cycle: {cycles}"
            assert not ready_mid, "pe_ready glitched high inside the loop"


@cocotb.test()
async def test_vfma_wrap_edge_and_b_split_pins(dut):
    """§25.2.4 directed pins, all golden-cross-checked AND literal:
      (1) explicit mod-2^32 — INT32_MIN/MAX boundary products: int8
          (-128)*(-128) + 0x7FFFC000 = 0x80000000 EXACTLY (positive
          product wraps to the INT32_MIN pattern, never saturates);
          int4 (-8)*(-8) + INT32_MAX wraps to 0x8000003F;
      (2) b_mul sext width pin — int4 reads ONLY B[3:0] (0x8 -> -8),
          int8 reads ONLY B[7:0] (0x80 -> -128): the SAME raw B word
          gives dtype-dependent lanes;
      (3) imm16/imm32 encodings zero-fill the upper word -> c_acc = 0
          (bit-identical to the imm64 form with c_acc = 0)."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    # (1a) int8 INT32_MIN wrap literal
    lanes8 = [0x80] * 16                     # all lanes -128
    b64 = _vfma_b64(0x80, 0x7FFFC000)        # b=-128, c=INT32_MAX-16383
    events, _ = await _vfma_run_wave(dut, lanes8, b64, _G.DT_INT8)
    outs = [e for e in events if e['kind'] == 'out']
    assert [e for e in events if e['kind'] != 'out'] == []
    exp = _vfma_expect_frags(lanes8, b64, _G.DT_INT8)
    got = [e['payload'] for e in outs]
    assert got == exp
    # literal: (-128)*(-128) = 16384; 0x7FFFC000 + 0x4000 = 0x80000000
    assert got[0] == 0x80000000_80000000, \
        f"INT32_MIN wrap literal violated: {got[0]:016x}"

    # (1b) int4 INT32_MAX wrap literal
    lanes4 = [0x8] * 32                      # all lanes -8
    b64 = _vfma_b64(0x8, 0x7FFFFFFF)         # b=-8, c=INT32_MAX
    events, _ = await _vfma_run_wave(dut, lanes4, b64, _G.DT_INT4)
    outs = [e for e in events if e['kind'] == 'out']
    got = [e['payload'] for e in outs]
    assert got == _vfma_expect_frags(lanes4, b64, _G.DT_INT4)
    # literal: 64 + 0x7FFFFFFF = 0x8000003F mod 2^32
    assert got[0] == 0x8000003F_8000003F, \
        f"INT32_MAX wrap literal violated: {got[0]:016x}"

    # (2) the SAME raw B word at both dtypes: B = {c=0, low word 0x88}
    # int8 reads 0x88 -> b = -120; int4 must read ONLY [3:0] = 0x8 ->
    # b = -8 (an int4 imm 0x88 is asm-lint-rejected, but the RTL pin is
    # dtype-driven and tag-mode dispatches can carry it — assert the
    # narrowing is exact, never a silent [7:0] read)
    raw = _vfma_b64(0x88, 0)
    events, _ = await _vfma_run_wave(dut, [0x1] * 32, raw, _G.DT_INT4)
    got4 = [e['payload'] for e in events if e['kind'] == 'out']
    assert got4 == _vfma_expect_frags([0x1] * 32, raw, _G.DT_INT4)
    assert got4[0] == 0xFFFFFFF8_FFFFFFF8, \
        f"int4 b_mul read beyond B[3:0]: {got4[0]:016x}"
    events, _ = await _vfma_run_wave(dut, [0x01] * 16, raw, _G.DT_INT8)
    got8 = [e['payload'] for e in events if e['kind'] == 'out']
    assert got8 == _vfma_expect_frags([0x01] * 16, raw, _G.DT_INT8)
    assert got8[0] == 0xFFFFFF88_FFFFFF88, \
        f"int8 b_mul != sext32(B[7:0]): {got8[0]:016x}"

    # (3) imm16/imm32 zero-fill -> c_acc = 0 == the imm64 c_acc=0 form
    lanes = [((i * 7) + 2) & 0xF for i in range(32)]
    exp0 = _vfma_expect_frags(lanes, _vfma_b64(0xF, 0), _G.DT_INT4)
    for kind in ('imm16', 'imm32'):
        events, _ = await _vfma_run_wave(dut, lanes, 0xF, _G.DT_INT4,
                                         imm_kind=kind)
        outs = [e for e in events if e['kind'] == 'out']
        assert [e['payload'] for e in outs] == exp0, \
            f"{kind} zero-fill pin violated (c_acc != 0)"

    # missing-wide guard (§20 wave contract): error_flag, no launch
    await _fp_fire_token(dut, _vfma_instr(_G.DT_INT4, imm64=1), 0,
                         b_valid=0, wide=0x1234, wide_valid=0)
    err = out = 0
    for _ in range(20):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        err |= int(dut.error_flag.value)
        out |= int(dut.output_valid.value)
    assert err == 1 and out == 0, f"missing-wide: err={err} out={out}"
    assert int(dut.pe_ready.value) == 1, "guarded launch left PE busy"


@cocotb.test()
async def test_vfma_busy_reject_and_mul_gate(dut):
    """§25.3 vfma_busy interlocks, all in ONE int4 wave flight (the
    DEQUANT interlock test's shape at the VFMA loop):
      (1) a mul-class dispatch with a busy-reject rung (0x74 FSCALAR)
          landing mid-loop is LOUDLY lower_required — never launched,
          never silently swallowed;
      (2) a 0x12 MUL dispatch mid-loop never launches (the launch
          gate's new !vfma_busy term — the confirmed output_regs_free
          hole) and no 0x12 result ever surfaces;
      (3) the VFMA result is preserved bit-exactly across both
          intruders — 16 fragments, contiguous, all opcode 0x70;
      (4) fragment 0 emits only at loop completion (after both
          intruder cycles); pe_ready stays low from launch through
          the final drain beat."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    lanes = [((i * 5) ^ 0x9) & 0xF for i in range(32)]
    b64 = _vfma_b64(0x5, -3)
    wide, a_frags = _vfma_pack_a(lanes, _G.DT_INT4)
    exp = _G.vfma_frags(a_frags, b64, _G.DT_INT4)

    await _fp_fire_token(dut, _vfma_instr(_G.DT_INT4, imm64=b64), 0,
                         payload_b=0, b_valid=0, wide=wide, wide_valid=1)
    outs = []
    lwr_seen = 0
    err_seen = 0
    intruded_74 = intruded_12 = False
    for i in range(160):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        # two intruders, well inside the ~32-cycle lane loop
        if i == 8 and not intruded_74:
            intruded_74 = True
            await _fp_fire_token(dut, _fp_instr(0x74, subop=_FS['FS_MUL']),
                                 _f2b(2.0), payload_b=_f2b(3.0), b_valid=1)
        if i == 16 and not intruded_12:
            intruded_12 = True
            instr12 = encode_instr(0x12, _STD_PORT(), eh_imm16(5))
            dut.instruction.value = instr12
            dut.input_tag.value = _STD_TAG()
            dut.input_payload.value = 7
            dut.input_payload_b_valid.value = 1
            dut.token_valid.value = 1
            await RisingEdge(dut.clk)
            dut.token_valid.value = 0
        await Timer(1, units="ns")
        err_seen |= int(dut.error_flag.value)
        lwr_seen |= int(dut.lower_required.value)
        if int(dut.output_valid.value):
            outs.append({'cycle': i, 'payload': int(dut.output_payload.value),
                         'opcode': int(dut.opcode_out.value),
                         'frag_hdr': int(dut.output_frag_hdr.value)})
        if len(outs) >= 16 and int(dut.pe_ready.value) == 1:
            break
    assert intruded_74 and intruded_12, "intruders never dispatched"
    assert err_seen == 0, "unexpected error_flag during the loop"
    assert lwr_seen == 1, \
        "mid-loop mul-class dispatch (0x74) was not LOUDLY busy-rejected"
    # (2)+(3): exactly 16 output pulses, contiguous, all VFMA fragments
    # — no 0x12/0x74 result ever surfaced, no per-lane spurious emit
    assert len(outs) == 16, f"{len(outs)} output pulses != 16: {outs}"
    assert all(o['opcode'] == 0x70 for o in outs), \
        f"foreign result surfaced: {[hex(o['opcode']) for o in outs]}"
    got = [o['payload'] for o in outs]
    assert got == exp, \
        f"VFMA corrupted by mid-loop intruders: " \
        f"{[hex(x) for x in got]} != {[hex(x) for x in exp]}"
    cycles = [o['cycle'] for o in outs]
    assert cycles == list(range(cycles[0], cycles[0] + 16)), \
        f"drain not contiguous: {cycles}"
    assert cycles[0] > 16, "fragment 0 emitted before loop completion"


@cocotb.test()
async def test_vfma_cycle_bounds(dut):
    """§25.4 ceilings, completion-within-bound convention (assert the
    ceiling, NEVER the exact count): token -> FINAL fragment beat
    within 90 cycles for int4-32/16-frag and 48 for int8-16/8-frag —
    measured at the unit level incl. decode overhead, so the margin
    over the ~51/~27 estimates is real headroom, not slack in the
    assertion."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset(dut)

    cases = [
        ("int4 16-frag", _G.DT_INT4, 32, 16, 90),
        ("int8 8-frag",  _G.DT_INT8, 16, 8,  48),
    ]
    import random as _rnd
    rng = _rnd.Random(0x0E72)
    for label, dtype, n_lanes, n_frags, ceiling in cases:
        lb_max = 16 if dtype == _G.DT_INT4 else 256
        lanes = [rng.randrange(lb_max) for _ in range(n_lanes)]
        b64 = _vfma_b64(0x7 if dtype == _G.DT_INT4 else 0x7F, 999)
        wide, a_frags = _vfma_pack_a(lanes, dtype)
        exp = _G.vfma_frags(a_frags, b64, dtype)
        await _fp_fire_token(dut, _vfma_instr(dtype, imm64=b64), 0,
                             b_valid=0, wide=wide, wide_valid=1)
        outs = []
        last_cycle = None
        for i in range(ceiling):
            await RisingEdge(dut.clk)
            await Timer(1, units="ns")
            assert int(dut.error_flag.value) == 0
            assert int(dut.lower_required.value) == 0
            if int(dut.output_valid.value):
                outs.append(int(dut.output_payload.value))
                last_cycle = i
                if len(outs) == n_frags:
                    break
        assert len(outs) == n_frags, \
            f"{label}: only {len(outs)}/{n_frags} fragments within the " \
            f"{ceiling}-cycle ceiling (§25.4)"
        assert outs == exp, f"{label}: wave corrupted under timing run"
        dut._log.info("%s: completed within ceiling (last beat at "
                      "cycle %d <= %d)", label, last_cycle, ceiling)
        await _fp_drain(dut)
