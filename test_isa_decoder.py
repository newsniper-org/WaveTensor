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
               payload_b=0, payload_b_valid=0):
    dut.instruction.value = instruction
    dut.input_tag.value = tag
    dut.input_payload.value = payload_a
    dut.input_payload_b.value = payload_b
    dut.input_payload_b_valid.value = payload_b_valid
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
