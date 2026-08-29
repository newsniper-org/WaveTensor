# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

"""Unit + roundtrip tests for the WaveTensor assembler.

Run with:    python -m unittest -v asm.test_wavetensor_asm
       or:   cd asm && python -m unittest -v test_wavetensor_asm

The roundtrip tests compare assembler output against the pre-existing
encode_instr() helpers in /home/ybi/WaveTensor/test_isa_decoder.py to
guarantee the assembler produces exactly the same bits the cocotb
testbench feeds to ISA_Decoder.v.
"""

from __future__ import annotations

import os
import sys
import unittest

# Make the assembler importable regardless of where the test is invoked.
_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)

import wavetensor_asm as wta

# v1.8.0a COMMIT 1 — frozen from pre-migration HEAD (042f08e).
# Pre-stable edit (opcode cleanup, 2026-07-24): the original "keep forever"
# wording predates the pre-stable compat policy being codified — freeze
# guarantees (frozen first-class, truth-table keep-forever, snapshot) bind
# only from STABLE RELEASE. Removing dead opcodes from this snapshot is
# therefore a regular development event, recorded spec-first (see
# wt64v1_spec.md removal record): 57 -> 53 keys, the four removed rows are
# annotated in place below.
_PREMIGRATION_LEGAL_SNAPSHOT = {
    0x00: {'required': [], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x01: {'required': ['port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x02: {'required': ['port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x03: {'required': ['port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x04: {'required': ['mem', 'port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x05: {'required': ['mem', 'port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x10: {'required': ['port'], 'forbidden': ['mem', 'subscript'], 'allow_imm_xor_opref': True, 'require_opb_flag': False, 'require_imm16': False},
    0x11: {'required': ['port'], 'forbidden': ['mem', 'subscript'], 'allow_imm_xor_opref': True, 'require_opb_flag': False, 'require_imm16': False},
    0x12: {'required': ['port'], 'forbidden': ['mem', 'subscript'], 'allow_imm_xor_opref': True, 'require_opb_flag': False, 'require_imm16': False},
    0x13: {'required': ['port'], 'forbidden': ['mem', 'subscript'], 'allow_imm_xor_opref': True, 'require_opb_flag': False, 'require_imm16': False},
    0x14: {'required': ['port'], 'forbidden': ['mem', 'subscript'], 'allow_imm_xor_opref': True, 'require_opb_flag': False, 'require_imm16': False},
    0x15: {'required': ['port'], 'forbidden': ['mem', 'subscript'], 'allow_imm_xor_opref': True, 'require_opb_flag': False, 'require_imm16': False},
    0x16: {'required': ['port'], 'forbidden': ['mem', 'subscript'], 'allow_imm_xor_opref': True, 'require_opb_flag': False, 'require_imm16': False},
    0x17: {'required': ['port'], 'forbidden': ['imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': True},
    0x18: {'required': ['port'], 'forbidden': ['imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': True},
    0x19: {'required': ['port'], 'forbidden': ['imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': True},
    0x1A: {'required': ['port'], 'forbidden': ['imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': True},
    0x1B: {'required': ['port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x1C: {'required': ['port'], 'forbidden': ['mem', 'subscript'], 'allow_imm_xor_opref': True, 'require_opb_flag': False, 'require_imm16': False},
    0x1D: {'required': ['port'], 'forbidden': ['mem', 'subscript'], 'allow_imm_xor_opref': True, 'require_opb_flag': False, 'require_imm16': False},
    0x1E: {'required': ['port'], 'forbidden': ['imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': True},
    0x1F: {'required': ['port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x20: {'required': ['imm16', 'port'], 'forbidden': ['imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x21: {'required': ['imm16', 'port'], 'forbidden': ['imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x22: {'required': ['imm16', 'port'], 'forbidden': ['imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x23: {'required': ['imm16', 'port'], 'forbidden': ['imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x24: {'required': ['imm16', 'port'], 'forbidden': ['imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x25: {'required': ['imm16', 'port'], 'forbidden': ['imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x26: {'required': ['imm16', 'port'], 'forbidden': ['imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x30: {'required': ['opref', 'port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': True, 'require_imm16': False},
    0x31: {'required': ['opref', 'port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': True, 'require_imm16': False},
    0x32: {'required': ['opref', 'port', 'subscript'], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem'], 'allow_imm_xor_opref': False, 'require_opb_flag': True, 'require_imm16': False},
    0x40: {'required': ['port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x41: {'required': ['port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x42: {'required': ['port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x43: {'required': ['port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x44: {'required': ['port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x50: {'required': ['port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x51: {'required': ['port'], 'forbidden': ['mem', 'subscript'], 'allow_imm_xor_opref': True, 'require_opb_flag': False, 'require_imm16': False},
    0x52: {'required': ['port'], 'forbidden': ['mem', 'subscript'], 'allow_imm_xor_opref': True, 'require_opb_flag': False, 'require_imm16': False},
    0x53: {'required': ['port'], 'forbidden': ['mem', 'subscript'], 'allow_imm_xor_opref': True, 'require_opb_flag': False, 'require_imm16': False},
    0x54: {'required': ['port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x55: {'required': ['port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x56: {'required': ['port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x60: {'required': ['port'], 'forbidden': ['mem', 'subscript'], 'allow_imm_xor_opref': True, 'require_opb_flag': False, 'require_imm16': False},
    0x61: {'required': ['port'], 'forbidden': ['mem', 'subscript'], 'allow_imm_xor_opref': True, 'require_opb_flag': False, 'require_imm16': False},
    0x62: {'required': ['port'], 'forbidden': ['mem', 'subscript'], 'allow_imm_xor_opref': True, 'require_opb_flag': False, 'require_imm16': False},
    0x63: {'required': ['port'], 'forbidden': ['imm16', 'imm32', 'mem', 'subscript'], 'allow_imm_xor_opref': True, 'require_opb_flag': True, 'require_imm16': False},
    0x64: {'required': ['port'], 'forbidden': ['imm16', 'imm32', 'mem', 'subscript'], 'allow_imm_xor_opref': True, 'require_opb_flag': True, 'require_imm16': False},
    0x65: {'required': ['port'], 'forbidden': ['imm16', 'imm32', 'mem', 'subscript'], 'allow_imm_xor_opref': True, 'require_opb_flag': True, 'require_imm16': False},
    # 0x66 SCALAR_RSQRT — removed in the pre-stable opcode cleanup (zero
    #   asm/SDK consumers; the norm recipes moved to the fp32 insert).
    # 0x67 SIMD_MUL_WIDE_Q4_4_SCALAR — removed (superseded by 0x69 Q8.8).
    0x68: {'required': ['port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x69: {'required': ['port'], 'forbidden': ['mem', 'subscript'], 'allow_imm_xor_opref': True, 'require_opb_flag': False, 'require_imm16': False},
    0x6A: {'required': ['port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    # 0x6B SIMD_MUL_WIDE_Q4_4_SCALAR_128_WIDEN — removed (v1.7 WIDEN pair
    #   had zero consumers; frag FSM widening stays for v1.8.0e).
    # 0x6C SIMD_REQUANTIZE_Q4_4_TO_INT4 — removed (WIDEN's companion).
}
from wavetensor_asm import (
    AssemblerError, Instruction, ExtensionHeader, AliasDecl, DefaultDecl,
    parse, alias_pass, default_pass, macro_pass, legality_pass, encode_pass,
    assemble, assemble_one, lower_to_ll,
)


# =============================================================================
# Inline reference encoder
#
# The cocotb test (../test_isa_decoder.py) imports cocotb at module load
# time, so we can't import it directly under plain Python. Instead, the
# helpers below mirror that file's encoding rules byte-for-byte. If you
# change one, change the other in lockstep — the encoder roundtrip tests
# below cross-check.
#
# ⚠ 인코딩 개정 파도 (W1~W8): 이 참조 인코더는 파도 후 의미론(12b opcode
# ·OPREF CRC-4·CH)으로 개정됐다. 루트 cocotb 하네스의 재캡처(록스텝 복원
# + truth_table_encwave.json 캡처)는 메인 루프 몫이다 — 그때까지 위
# 록스텝 문장은 「의무」의 기록이지 「현재 상태」의 기록이 아니다.
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

F_HAS_OPB        = 1 << 3
F_PRECISION_OVR  = 1 << 2
INSTR_WORDS_REAL = 14      # W8: 기본 헤더 1 + CH 1 + EH 예산 12 (448b)


# -----------------------------------------------------------------------------
# 참조측 CRC — wavetensor_asm.py 본체와 **독립** 구현 (교차 검증용).
#
# 본체는 비트-직렬 LFSR(crc4)·반사 비트루프(crc32c)다. 여기는 일부러 다른
# 형태로 짠다: crc4 는 16b 부호어 다항 장제법, crc32c 는 256-엔트리 표.
# 두 구현이 P1·P2 기지값 7종을 각자 통과해야 한다 (TestCrcReferenceValues).
# -----------------------------------------------------------------------------

def _ref_crc4(lbid, src_kind):
    """(M(x)·x⁴) mod G(x), G = x⁴+x+1, M = LBID[7..0] ∥ src_kind[3..0]
    (12b 논리 순서, MSB-first), init 0, xorout 없음 — 장제법 구현."""
    v = (((lbid & 0xFF) << 4) | (src_kind & 0xF)) << 4    # 16b 부호어 자리
    for i in range(15, 3, -1):
        if (v >> i) & 1:
            v ^= 0x13 << (i - 4)
    return v & 0xF


_CRC32C_TBL = []
for _n in range(256):
    _c = _n
    for _ in range(8):
        _c = (_c >> 1) ^ (0x82F63B78 if _c & 1 else 0)
    _CRC32C_TBL.append(_c)


def _ref_crc32c(data):
    """CRC-32C, RFC 3720 관례 (반사, init/xorout 0xFFFFFFFF) — 표 구현."""
    crc = 0xFFFFFFFF
    for b in data:
        crc = (crc >> 8) ^ _CRC32C_TBL[(crc ^ b) & 0xFF]
    return crc ^ 0xFFFFFFFF


class _EH:
    def __init__(self, type_code, words, body_fn):
        self.type = type_code
        self.words = words
        self._body_fn = body_fn

    def emit(self, next_hdr):
        return self._body_fn(next_hdr)


def _eh_port(input_port_mask, output_port_id):
    def fn(nh):
        body16 = ((output_port_id & 0xFF) << 8) | (input_port_mask & 0xFF)
        return [(body16 << 16) | (nh << 12) | (EH_PORT << 8) | 1]
    return _EH(EH_PORT, 1, fn)


def _eh_imm16(v):
    def fn(nh):
        return [((v & 0xFFFF) << 16) | (nh << 12) | (EH_IMM16 << 8) | 1]
    return _EH(EH_IMM16, 1, fn)


def _eh_mem(offset, addr_mode=0, stride=0):
    def fn(nh):
        upper = ((stride & 0xFFF) << 4) | (addr_mode & 0xF)
        return [(upper << 16) | (nh << 12) | (EH_MEM << 8) | 2,
                offset & 0xFFFFFFFF]
    return _EH(EH_MEM, 2, fn)


def _eh_subscript(a_axes16, b_axes16, o_axes16):
    def fn(nh):
        return [((o_axes16 & 0xFFFF) << 16) | (nh << 12) | (EH_SUBSCRIPT << 8) | 2,
                ((a_axes16 & 0xFFFF) << 16) | (b_axes16 & 0xFFFF)]
    return _EH(EH_SUBSCRIPT, 2, fn)


def _eh_opref(src_kind=0, port_id=0, noc_route=0):
    # W5: `[23:20]` 은 본문 12b(LBID ∥ src_kind)의 CRC-4 다 (§1.4.6).
    # port_id 인자는 폐지된 필드의 흔적 — 호출 호환으로만 남고 0 이어야
    # 한다 (참조 인코더가 조용히 CRC 자리를 덮어쓰는 일이 없도록 단언).
    assert port_id == 0, "opref [23:20] is the CRC-4 field (W5)"

    def fn(nh):
        crc = _ref_crc4(noc_route, src_kind)
        upper = ((noc_route & 0xFF) << 8) | (crc << 4) | (src_kind & 0xF)
        return [(upper << 16) | (nh << 12) | (EH_OPREF << 8) | 1]
    return _EH(EH_OPREF, 1, fn)


def _eh_precision(precision_mode, dim_override=0):
    def fn(nh):
        upper = ((dim_override & 0xFF) << 8) | (precision_mode & 0xFF)
        return [(upper << 16) | (nh << 12) | (EH_PRECISION << 8) | 1]
    return _EH(EH_PRECISION, 1, fn)


def _axes(*labels):
    v = 0
    for i, l in enumerate(labels):
        v |= (l & 0xF) << (i * 4)
    return v


def _decode_mirror(instr_int):
    """Pure-python re-walk of an encoded instruction (mirror of
    test_isa_decoder._decode_mirror) — the disassembly half of the
    assemble -> disassemble roundtrip."""
    iw = [(instr_int >> (i * 32)) & 0xFFFFFFFF for i in range(INSTR_WORDS_REAL)]
    base = iw[0]
    out = {
        # W1: opcode 는 12b — 하위 8b [31:24] + 확장 니블 [11:8].
        'opcode':   ((base >> 24) & 0xFF) | (((base >> 8) & 0xF) << 8),
        'next_hdr': (base >> 20) & 0xF,
        'flags':    (base >> 16) & 0xF,
        'reserved': (base >> 12) & 0xF,     # W1: [15:12] 로 협소화
        'bh_len':   base & 0xFF,
        'ehs':      [],
    }
    expect = out['next_hdr']
    off = 1
    # W8: next_hdr ≠ END 이면 word 1 은 CH(둘째 헤더)다 — EH 가 아니고
    # 순회 대상도 아니다. EH 순회는 word 2 에서 시작한다 (§4.2.1).
    # 재계산 대조: 메시지 = CH 를 제외한 전 워드(word 0, word 2‥bh_len−1).
    if expect != EH_END:
        out['ch'] = iw[1]
        bh_len = out['bh_len']
        msg_words = [iw[0]] + iw[2:max(2, min(bh_len, INSTR_WORDS_REAL))]
        msg = b''.join(w.to_bytes(4, 'little') for w in msg_words)
        out['ch_ok'] = (_ref_crc32c(msg) == iw[1])
        off = 2
    safety = 0
    while expect != EH_END and safety < 16:
        safety += 1
        if off >= INSTR_WORDS_REAL:
            out['eh_overflow'] = True
            break
        w0 = iw[off]
        eh_next = (w0 >> 12) & 0xF
        eh_type = (w0 >> 8) & 0xF
        eh_len = w0 & 0xFF
        if eh_type != expect:
            out['chain_break_at'] = off
            break
        out['ehs'].append({'type': eh_type, 'len': eh_len, 'next': eh_next,
                           'words': iw[off:off + eh_len]})
        off += eh_len
        expect = eh_next
    out['walked_words'] = off
    return out


def _encode_instr(opcode, *exts, flags=0):
    chained = []
    nh = EH_END
    for eh in reversed(exts):
        chained.insert(0, (eh, nh))
        nh = eh.type
    # W8: EH ≥ 1 (⇔ next_hdr ≠ END) 이면 word 1 이 CH 다. bh_len 은
    # CH 를 포함한 물리 워드 총수.
    has_ch = bool(chained)
    bh_len = 1 + (1 if has_ch else 0) + sum(eh.words for eh, _ in chained)
    # W1: opcode 12b — 하위 8b [31:24], 확장 니블 [11:8], [15:12] 예약 0.
    base = ((opcode & 0xFF) << 24) | ((nh & 0xF) << 20) \
         | ((flags & 0xF) << 16) | (((opcode >> 8) & 0xF) << 8) \
         | (bh_len & 0xFF)
    body = [base]
    for eh, nh_v in chained:
        body.extend(eh.emit(nh_v))
    if has_ch:
        # CH 메시지 = CH 자기 워드를 제외한 전 워드(word 0, word 2‥
        # bh_len−1), 워드 오름차순, 패딩 불포함, 워드당 리틀엔디언 4바이트.
        msg = b''.join((w & 0xFFFFFFFF).to_bytes(4, 'little') for w in body)
        words = [body[0], _ref_crc32c(msg)] + body[1:]
    else:
        words = body
    while len(words) < INSTR_WORDS_REAL:
        words.append(0)
    val = 0
    for i, w in enumerate(words):
        val |= (w & 0xFFFFFFFF) << (i * 32)
    return val


# Compact namespace for tests below — same call signatures as the cocotb file.
class ref:
    encode_instr  = staticmethod(_encode_instr)
    eh_port       = staticmethod(_eh_port)
    eh_imm16      = staticmethod(_eh_imm16)
    eh_mem        = staticmethod(_eh_mem)
    eh_subscript  = staticmethod(_eh_subscript)
    eh_opref      = staticmethod(_eh_opref)
    eh_precision  = staticmethod(_eh_precision)
    decode_mirror = staticmethod(_decode_mirror)
    axes          = staticmethod(_axes)
    F_HAS_OPB     = F_HAS_OPB
    F_PRECISION_OVR = F_PRECISION_OVR


# =============================================================================
# Stage 1 — parser
# =============================================================================

class TestParser(unittest.TestCase):

    def test_empty_program(self):
        prog = parse("")
        self.assertEqual(prog.stmts, [])

    def test_only_comments_and_blanks(self):
        prog = parse("# hello\n\n  # world\n\n")
        self.assertEqual(prog.stmts, [])

    def test_alias_decl(self):
        prog = parse(".alias port_a 0x01\n")
        self.assertEqual(len(prog.stmts), 1)
        self.assertIsInstance(prog.stmts[0], AliasDecl)
        self.assertEqual(prog.stmts[0].name, 'port_a')
        self.assertEqual(prog.stmts[0].value, 1)

    def test_default_port_decl(self):
        prog = parse(".default_port dest=0x01\n")
        self.assertIsInstance(prog.stmts[0], DefaultDecl)
        self.assertEqual(prog.stmts[0].kind, 'port')
        self.assertEqual(prog.stmts[0].args, {'dest': 1})

    def test_simple_instruction(self):
        prog = parse("ADD .port dest=0x01 .imm16 5\n")
        inst = prog.stmts[0]
        self.assertIsInstance(inst, Instruction)
        self.assertEqual(inst.mnemonic, 'ADD')
        self.assertEqual(inst.flags, set())
        self.assertEqual(len(inst.eh_list), 2)
        self.assertEqual(inst.eh_list[0].kind, 'port')
        self.assertEqual(inst.eh_list[1].kind, 'imm16')
        self.assertEqual(inst.eh_list[1].args, {'_pos': [5]})

    def test_instruction_with_flags(self):
        prog = parse("MATMUL opb .port dest=0x01 .opref\n")
        inst = prog.stmts[0]
        self.assertEqual(inst.flags, {'opb'})

    def test_subscript_parsing(self):
        prog = parse("EINSUM opb .port dest=1 "
                     ".subscript A=i,j B=j,k O=i,k .opref\n")
        sub = prog.stmts[0].eh_list[1]
        self.assertEqual(sub.kind, 'subscript')
        self.assertEqual(sub.args['A'], ['i', 'j'])
        self.assertEqual(sub.args['B'], ['j', 'k'])
        self.assertEqual(sub.args['O'], ['i', 'k'])

    def test_label(self):
        prog = parse("loop:\nADD .port dest=1 .imm16 1\n")
        self.assertEqual(prog.stmts[0].name, 'loop')


# =============================================================================
# Stage 2 — alias resolution
# =============================================================================

class TestAliasPass(unittest.TestCase):

    def test_resolves_kw_arg(self):
        prog = parse(".alias port_a 0x01\n"
                     "ADD .port dest=port_a .imm16 5\n")
        out = alias_pass(prog)
        # AliasDecl is consumed; only Instruction remains.
        self.assertEqual(len(out.stmts), 1)
        port_eh = out.stmts[0].eh_list[0]
        self.assertEqual(port_eh.args['dest'], 1)

    def test_undefined_alias_raises(self):
        prog = parse("ADD .port dest=undefined_alias .imm16 5\n")
        # Note: at the parser stage we don't know it's an alias yet — it's
        # treated as a string. The encoder-level check fires.
        with self.assertRaises(AssemblerError):
            assemble("ADD .port dest=undefined_alias .imm16 5\n")

    def test_subscript_labels_are_not_resolved(self):
        # `i, j` are subscript labels, not aliases — must survive alias_pass.
        prog = parse(".alias i 99\n"
                     "EINSUM opb .port dest=1 "
                     ".subscript A=i,j B=j,k O=i,k .opref\n")
        out = alias_pass(prog)
        sub = out.stmts[0].eh_list[1]
        self.assertEqual(sub.args['A'], ['i', 'j'])


# =============================================================================
# Stage 3 — default fills
# =============================================================================

class TestDefaultPass(unittest.TestCase):

    def test_default_port_filled_when_missing(self):
        prog = parse(".default_port dest=0x01\n"
                     "ADD .imm16 5\n")
        out = default_pass(alias_pass(prog))
        eh_kinds = [eh.kind for eh in out.stmts[0].eh_list]
        self.assertEqual(eh_kinds, ['port', 'imm16'])

    def test_explicit_port_overrides_default(self):
        prog = parse(".default_port dest=0x01\n"
                     "ADD .port dest=0x204 .imm16 5\n")
        out = default_pass(alias_pass(prog))
        port_eh = out.stmts[0].eh_list[0]
        self.assertEqual(port_eh.args, {'dest': 0x204})

    def test_nop_does_not_get_default_port(self):
        prog = parse(".default_port dest=0x01\nNOP\n")
        out = default_pass(alias_pass(prog))
        self.assertEqual(out.stmts[0].eh_list, [])

    def test_default_precision_sets_prec_flag(self):
        prog = parse(".default_precision mode=0x12\n"
                     "FLOOR .port dest=1\n")
        out = default_pass(alias_pass(prog))
        self.assertIn('prec', out.stmts[0].flags)
        self.assertEqual(out.stmts[0].eh_list[-1].kind, 'precision')

    def test_default_precision_dim_only_sets_dim_ovr(self):
        prog = parse(".default_precision dim=0x05\n"
                     "FLOOR .port dest=1\n")
        out = default_pass(alias_pass(prog))
        self.assertIn('dim_ovr', out.stmts[0].flags)
        self.assertNotIn('prec', out.stmts[0].flags)

    def test_default_precision_both_sets_both_flags(self):
        prog = parse(".default_precision mode=0x12 dim=0x05\n"
                     "FLOOR .port dest=1\n")
        out = default_pass(alias_pass(prog))
        self.assertIn('prec', out.stmts[0].flags)
        self.assertIn('dim_ovr', out.stmts[0].flags)


# =============================================================================
# Stage 4 — macro expansion
# =============================================================================

class TestMacroPass(unittest.TestCase):

    def test_reshape_lowers_to_view(self):
        src = ".default_port dest=0x01\nRESHAPE .from 0x03 .to 0x05\n"
        prog = legality_pass(macro_pass(default_pass(alias_pass(parse(src)))))
        self.assertEqual(len(prog.stmts), 1)
        self.assertEqual(prog.stmts[0].mnemonic, 'VIEW')
        eh_kinds = [eh.kind for eh in prog.stmts[0].eh_list]
        self.assertIn('imm16', eh_kinds)
        self.assertIn('port', eh_kinds)

    def test_reshape_count_mismatch_raises(self):
        src = ".default_port dest=1\nRESHAPE .from 0x03 .to 0x0A\n"
        # 0x03 → 4 elems; 0x0A = 0b1010 → axis sizes 3,3 → 9 elems
        with self.assertRaises(AssemblerError):
            assemble(src)

    def test_non_macro_passes_through(self):
        src = "ADD .port dest=1 .imm16 5\n"
        out = macro_pass(default_pass(alias_pass(parse(src))))
        self.assertEqual(out.stmts[0].mnemonic, 'ADD')


# =============================================================================
# Stage 5 — legality
# =============================================================================

class TestLegalityPass(unittest.TestCase):

    def test_unknown_mnemonic_raises(self):
        with self.assertRaises(AssemblerError):
            assemble("FROBNICATE .port dest=1\n")

    def test_matmul_without_opb_flag_raises(self):
        with self.assertRaises(AssemblerError):
            assemble("MATMUL .port dest=1 .opref\n")

    def test_matmul_with_subscript_forbidden(self):
        with self.assertRaises(AssemblerError):
            assemble("MATMUL opb .port dest=1 .opref "
                     ".subscript A=i,j B=j,k O=i,k\n")

    def test_alu_binary_neither_imm_nor_opref_raises(self):
        with self.assertRaises(AssemblerError):
            assemble("ADD .port dest=1\n")

    def test_alu_binary_both_imm_and_opref_raises(self):
        with self.assertRaises(AssemblerError):
            assemble("ADD opb .port dest=1 .imm16 5 .opref\n")

    def test_shape_op_without_imm16_raises(self):
        with self.assertRaises(AssemblerError):
            assemble("SQZ .port dest=1\n")

    def test_prec_flag_without_precision_eh_raises(self):
        with self.assertRaises(AssemblerError):
            assemble("ADD prec .port dest=1 .imm16 5\n")

    def test_dim_ovr_flag_without_precision_eh_raises(self):
        with self.assertRaises(AssemblerError):
            assemble("ADD dim_ovr .port dest=1 .imm16 5\n")

    def test_prec_flag_with_precision_eh_passes(self):
        # Should not raise
        assemble("ADD prec .port dest=1 .imm16 5 .precision mode=0x12\n")

    def test_dim_ovr_flag_with_precision_eh_passes(self):
        # Should not raise
        assemble("ADD dim_ovr .port dest=1 .imm16 5 .precision dim=0x05\n")


# =============================================================================
# Stage 6 — encoder & roundtrip against test_isa_decoder.encode_instr
# =============================================================================

class TestEncoderRoundtrip(unittest.TestCase):
    """Each test asserts: assemble(HL_text) == encode_instr(...) bits."""

    def _assert_eq(self, asm_text, expected_int):
        got = assemble_one(asm_text)
        self.assertEqual(
            got, expected_int,
            f"\nasm:      0x{got:0112x}\nexpected: 0x{expected_int:0112x}",
        )

    # --- legacy opcodes ----------------------------------------------------

    def test_wave_advance(self):
        self._assert_eq(
            "WADV .port dest=0x01\n",
            ref.encode_instr(0x01, ref.eh_port(0x01, 0)),
        )

    def test_steer(self):
        self._assert_eq(
            "STEER .port dest=0x01\n",
            ref.encode_instr(0x02, ref.eh_port(0x01, 0)),
        )

    def test_load_with_mem(self):
        self._assert_eq(
            "LD .port dest=0x01 .mem offset=0x100\n",
            ref.encode_instr(0x04, ref.eh_port(0x01, 0), ref.eh_mem(0x100)),
        )

    def test_add_with_imm(self):
        self._assert_eq(
            "ADD .port dest=0x01 .imm16 5\n",
            ref.encode_instr(0x10, ref.eh_port(0x01, 0), ref.eh_imm16(5)),
        )

    def test_add_with_opref(self):
        self._assert_eq(
            "ADD opb .port dest=0x01 .opref\n",
            ref.encode_instr(0x10, ref.eh_port(0x01, 0), ref.eh_opref(),
                             flags=ref.F_HAS_OPB),
        )

    def test_shift_left(self):
        self._assert_eq(
            "SHL .port dest=0x01 .imm16 4\n",
            ref.encode_instr(0x17, ref.eh_port(0x01, 0), ref.eh_imm16(4)),
        )

    def test_bits_reverse(self):
        self._assert_eq(
            "BITREV .port dest=0x01\n",
            ref.encode_instr(0x1F, ref.eh_port(0x01, 0)),
        )

    # --- shape ops ---------------------------------------------------------

    def test_squeeze(self):
        self._assert_eq(
            "SQZ .port dest=0x01 .imm16 0\n",
            ref.encode_instr(0x20, ref.eh_port(0x01, 0), ref.eh_imm16(0)),
        )

    def test_view(self):
        self._assert_eq(
            "VIEW .port dest=0x01 .imm16 0x05\n",
            ref.encode_instr(0x22, ref.eh_port(0x01, 0), ref.eh_imm16(0x05)),
        )

    def test_perm_2x2(self):
        self._assert_eq(
            "PERM .port dest=0x01 .imm16 0x01\n",
            ref.encode_instr(0x23, ref.eh_port(0x01, 0), ref.eh_imm16(1)),
        )

    def test_red_axis_sum(self):
        self._assert_eq(
            "RED .port dest=0x01 .imm16 0x00\n",
            ref.encode_instr(0x25, ref.eh_port(0x01, 0), ref.eh_imm16(0)),
        )

    # --- tensor ops --------------------------------------------------------

    def test_matmul(self):
        self._assert_eq(
            "MATMUL opb .port dest=0x01 .opref\n",
            ref.encode_instr(0x30, ref.eh_port(0x01, 0), ref.eh_opref(),
                             flags=ref.F_HAS_OPB),
        )

    def test_einsum_matmul_pattern(self):
        self._assert_eq(
            "EINSUM opb .port dest=0x01 "
            ".subscript A=i,j B=j,k O=i,k .opref\n",
            ref.encode_instr(
                0x32,
                ref.eh_port(0x01, 0),
                ref.eh_subscript(ref.axes(1, 2), ref.axes(2, 3), ref.axes(1, 3)),
                ref.eh_opref(),
                flags=ref.F_HAS_OPB,
            ),
        )

    def test_einsum_dot_pattern(self):
        self._assert_eq(
            "EINSUM opb .port dest=0x01 "
            ".subscript A=i B=i O= .opref\n",
            ref.encode_instr(
                0x32,
                ref.eh_port(0x01, 0),
                ref.eh_subscript(ref.axes(1), ref.axes(1), ref.axes()),
                ref.eh_opref(),
                flags=ref.F_HAS_OPB,
            ),
        )

    # --- pipeline-level: defaults + aliases roundtrip --------------------

    def test_default_port_yields_same_bits(self):
        with_defaults = assemble_one(
            ".alias port_a 0x01\n"
            ".default_port dest=port_a\n"
            "ADD .imm16 7\n"
        )
        explicit = ref.encode_instr(
            0x10, ref.eh_port(0x01, 0), ref.eh_imm16(7),
        )
        self.assertEqual(with_defaults, explicit)

    def test_reshape_macro_yields_view_bits(self):
        macroed = assemble_one(
            ".default_port dest=0x01\n"
            "RESHAPE .from 0x03 .to 0x05\n"
        )
        direct = ref.encode_instr(
            0x22, ref.eh_port(0x01, 0), ref.eh_imm16(0x05),
        )
        self.assertEqual(macroed, direct)


# =============================================================================
# lower_to_ll inspection
# =============================================================================

class TestLowerToLL(unittest.TestCase):

    def test_lowered_text_contains_view_after_reshape(self):
        src = (
            ".default_port dest=0x01\n"
            "RESHAPE .from 0x03 .to 0x05\n"
        )
        ll = lower_to_ll(src)
        self.assertIn('VIEW', ll)
        self.assertNotIn('RESHAPE', ll)

    def test_idempotent_on_pure_ll(self):
        src = "ADD .port dest=0x01 .imm16 5\n"
        ll = lower_to_ll(src)
        # Re-assembling the lowered text must produce the same bits.
        again = assemble_one(ll)
        once = assemble_one(src)
        self.assertEqual(again, once)


# =============================================================================
# Multi-line program
# =============================================================================

class TestEinsumLowering(unittest.TestCase):
    """macro_pass extension that turns non-HW-direct EINSUMs into a chain
    of PERM/VIEW/EINSUM(matmul)/VIEW/PERM primitives."""

    def _mnemonics(self, src):
        prog = legality_pass(macro_pass(default_pass(alias_pass(parse(src)))))
        return [s.mnemonic for s in prog.stmts if isinstance(s, Instruction)]

    def test_hw_direct_passthrough_matmul(self):
        # ij,jk->ik is the HW MATMUL kernel, must not lower
        src = (
            ".default_port dest=0x01\n"
            "EINSUM opb .subscript A=i,j B=j,k O=i,k .opref\n"
        )
        self.assertEqual(self._mnemonics(src), ['EINSUM'])

    def test_hw_direct_passthrough_relabeled(self):
        # pq,qr->pr is alpha-equivalent to ij,jk->ik
        src = (
            ".default_port dest=0x01\n"
            "EINSUM opb .subscript A=p,q B=q,r O=p,r .opref\n"
        )
        self.assertEqual(self._mnemonics(src), ['EINSUM'])

    def test_hw_direct_dot_passthrough(self):
        src = (
            ".default_port dest=0x01\n"
            "EINSUM opb .subscript A=i B=i O= .opref\n"
        )
        self.assertEqual(self._mnemonics(src), ['EINSUM'])

    def test_lower_ji_jk_to_ik(self):
        # ji,jk->ik needs A transposed before matmul, no other rewriting
        src = (
            ".default_port dest=0x01\n"
            "EINSUM opb .subscript A=j,i B=j,k O=i,k .opref\n"
        )
        ms = self._mnemonics(src)
        # Expect: PERM A → VIEW A → VIEW B → EINSUM(matmul)
        self.assertEqual(ms, ['PERM', 'VIEW', 'VIEW', 'EINSUM'])

    def test_lower_ij_jk_to_ki(self):
        # output transposed: still a kernel A=ij B=jk so A and B straight,
        # but result needs final PERM
        src = (
            ".default_port dest=0x01\n"
            "EINSUM opb .subscript A=i,j B=j,k O=k,i .opref\n"
        )
        ms = self._mnemonics(src)
        # PERM A skipped (i,j already correct order for matmul), VIEW A,
        # VIEW B, EINSUM, VIEW result, PERM result.
        self.assertEqual(ms, ['VIEW', 'VIEW', 'EINSUM', 'PERM'])

    def test_lower_4d_3d_einsum(self):
        # ijkl,jkm->iml — the canonical "needs full lowering" example
        src = (
            ".default_port dest=0x01\n"
            "EINSUM opb .subscript A=i,j,k,l B=j,k,m O=i,m,l .opref "
            ".shape i=2 j=2 k=2 l=2 m=2\n"
        )
        ms = self._mnemonics(src)
        # PERM A (ijkl→ilkj), VIEW A 2D, PERM B (jkm→jkm: skipped or no-op?),
        # VIEW B 2D, EINSUM matmul, VIEW result 3D, PERM result (ilm→iml).
        # B=jkm→target=jkm so no PERM B; no PERM A?
        # Actually a_labels=[i,j,k,l], target_a=[i,l]+[j,k]=[i,l,j,k] → permute.
        self.assertIn('EINSUM', ms)
        self.assertGreater(ms.count('PERM') + ms.count('VIEW'), 1)

    def test_trace_in_a_raises(self):
        src = (
            ".default_port dest=0x01\n"
            "EINSUM opb .subscript A=i,i B=k O= .opref .shape i=2 k=2\n"
        )
        with self.assertRaises(AssemblerError):
            assemble(src)

    def test_broadcast_in_o_size_gt_1_raises(self):
        """Non-trivial broadcast (size > 1) requires runtime constant vector
        splat that WT64v1 lacks — must raise with pointer to analysis memo."""
        # Label 'q' in O but not in A or B, size 2 → non-trivial
        src = (
            ".default_port dest=0x01\n"
            "EINSUM opb .subscript A=i B=j O=i,j,q .opref "
            ".shape i=2 j=2 q=2\n"
        )
        with self.assertRaisesRegex(AssemblerError, "size-1 broadcast"):
            assemble(src)

    def test_broadcast_size_1_lowers_via_unsqueeze(self):
        """Size-1 broadcast IS lowerable — via UNSQUEEZE (metadata-only).
        Result is matmul chain + UNSQUEEZE for each bcast dim."""
        # Label 'q' in O but not in A or B, size 1 → trivially lowerable
        src = (
            ".default_port dest=0x01\n"
            "EINSUM opb .subscript A=i,j B=j,k O=i,k,q .opref "
            ".shape i=2 j=2 k=2 q=1\n"
        )
        insts = assemble(src)
        # Should succeed without raising.
        self.assertGreater(len(insts), 0)
        # Should contain at least one USQZ (0x21) for the size-1 bcast axis.
        opcodes = [(w >> 24) & 0xFF for w in insts]
        self.assertIn(0x21, opcodes,
                      f"expected USQZ (0x21) in lowered chain, got {[hex(o) for o in opcodes]}")

    def test_broadcast_size_1_in_middle_of_O(self):
        """Broadcast label sandwiched between real labels — USQZ position
        must match the label's location in O."""
        # O = [i, q, j] where q is size 1 broadcast; i and j come from A, B.
        src = (
            ".default_port dest=0x01\n"
            "EINSUM opb .subscript A=i B=j O=i,q,j .opref "
            ".shape i=2 j=2 q=1\n"
        )
        insts = assemble(src)
        opcodes = [(w >> 24) & 0xFF for w in insts]
        self.assertIn(0x21, opcodes)

    def test_bmm_v1_1_hw_direct_pass_through(self):
        """v1.1 amendment: `bik,bkj->bij` batched matmul is now SIG_BMM,
        HW-direct pass-through (no macro lowering)."""
        src = (
            ".default_port dest=0x01\n"
            "EINSUM opb .subscript A=b,i,k B=b,k,j O=b,i,j .opref "
            ".shape b=2 i=2 k=2 j=2\n"
        )
        # Should pass through as a single EINSUM (opcode 0x32) rather than
        # a lowered chain.
        insts = assemble(src)
        opcodes = [(w >> 24) & 0xFF for w in insts]
        self.assertEqual(opcodes, [0x32], f"expected single EINSUM, got {[hex(o) for o in opcodes]}")

    def test_trace_iij_v1_1_hw_direct_pass_through(self):
        """v1.1 amendment: `iij->j` is now SIG_TRACE_IIJ, HW-direct."""
        src = (
            ".default_port dest=0x01\n"
            "EINSUM opb .subscript A=i,i,j B= O=j .opref "
            ".shape i=2 j=2\n"
        )
        insts = assemble(src)
        opcodes = [(w >> 24) & 0xFF for w in insts]
        self.assertEqual(opcodes, [0x32], f"expected single EINSUM, got {[hex(o) for o in opcodes]}")

    def test_bmm_2_v1_2_hw_direct_pass_through(self):
        """v1.2 amendment: `abij,abjk->abik` (2-batch matmul) is now
        SIG_BMM_2, HW-direct pass-through at int4."""
        src = (
            ".default_port dest=0x01\n"
            "EINSUM opb .subscript A=a,b,i,j B=a,b,j,k O=a,b,i,k .opref "
            ".shape a=2 b=2 i=2 j=2 k=2\n"
        )
        insts = assemble(src)
        opcodes = [(w >> 24) & 0xFF for w in insts]
        self.assertEqual(opcodes, [0x32], f"expected single EINSUM, got {[hex(o) for o in opcodes]}")

    def test_trace_iijk_v1_2_hw_direct_pass_through(self):
        """v1.2 amendment: `iijk->jk` (3D trace + 2 kept axes) is now
        SIG_TRACE_IIJK, HW-direct pass-through at int4."""
        src = (
            ".default_port dest=0x01\n"
            "EINSUM opb .subscript A=i,i,j,k B= O=j,k .opref "
            ".shape i=2 j=2 k=2\n"
        )
        insts = assemble(src)
        opcodes = [(w >> 24) & 0xFF for w in insts]
        self.assertEqual(opcodes, [0x32], f"expected single EINSUM, got {[hex(o) for o in opcodes]}")

    def test_3_batch_dims_v1_3_multi_subscript_pass_through(self):
        """v1.3 §16: `abcij,abcjk->abcik` (3-batch matmul) now matches
        SIG_BMM_3_CANDIDATE via multi-SUBSCRIPT encoding. Assembler emits
        the EINSUM opcode with two SUBSCRIPT EHs concatenated. RTL will
        `lower_required` (no matching PE primitive), but the encoding
        path itself is exercised — this closes the v1.2 raise."""
        src = (
            ".default_port dest=0x01\n"
            "EINSUM opb .subscript A=a,b,c,i,j B=a,b,c,j,k O=a,b,c,i,k .opref "
            ".shape a=2 b=2 c=2 i=2 j=2 k=2\n"
        )
        insts = assemble(src)
        opcodes = [(w >> 24) & 0xFF for w in insts]
        self.assertEqual(opcodes, [0x32],
                         f"expected single EINSUM, got {[hex(o) for o in opcodes]}")
        # Verify two SUBSCRIPT EHs are present in the emitted instruction.
        # Walk the chain (W8: word 1 은 CH — 둘째 헤더, EH 아님):
        # base + CH + PORT + SUBSCRIPT_low + SUBSCRIPT_hi + OPREF.
        val = insts[0]
        words = [(val >> (i * 32)) & 0xFFFFFFFF for i in range(14)]
        # base word 0: next_hdr in [23:20] = 0x1 (PORT)
        self.assertEqual((words[0] >> 20) & 0xF, 0x1, "base.next_hdr must be PORT")
        # PORT (word 2 — CH 다음): next_hdr = SUBSCRIPT (0x6)
        self.assertEqual((words[2] >> 12) & 0xF, 0x6, "PORT.next_hdr must be SUBSCRIPT")
        # SUBSCRIPT_low (word 3): next_hdr = SUBSCRIPT (0x6) — chained SUBSCRIPT
        self.assertEqual((words[3] >> 12) & 0xF, 0x6,
                         "first SUBSCRIPT.next_hdr must be SUBSCRIPT (chained multi)")
        self.assertEqual((words[3] >> 8) & 0xF, 0x6, "type must be SUBSCRIPT")
        # SUBSCRIPT_hi (word 5): next_hdr = OPREF (0x7)
        self.assertEqual((words[5] >> 12) & 0xF, 0x7,
                         "second SUBSCRIPT.next_hdr must be OPREF")
        self.assertEqual((words[5] >> 8) & 0xF, 0x6, "type must still be SUBSCRIPT")

    def test_4_batch_dims_still_raises_beyond_v1_3(self):
        """Beyond v1.3 §16: 4 batch axes would give 7-axis A/B/O tensors,
        exceeding _pack_axes_multi's 8-axis limit only if very rank-heavy.
        For `abcdij,abcdjk->abcdik` it's 6 axes / group — encoding fits
        (multi-SUBSCRIPT), BUT signature isn't in
        HW_DIRECT_EINSUM_SIGS_MULTI, so falls through to _lower_einsum_general
        which raises on batched contraction."""
        src = (
            ".default_port dest=0x01\n"
            "EINSUM opb .subscript A=a,b,c,d,i,j B=a,b,c,d,j,k O=a,b,c,d,i,k "
            ".opref .shape a=2 b=2 c=2 d=2 i=2 j=2 k=2\n"
        )
        with self.assertRaises(AssemblerError):
            assemble(src)

    def test_lowered_matmul_produces_executable_bits(self):
        """The lowered chain must encode through stage 5 / 6 cleanly,
        even if the resulting tensor sizes are above the single-PE limit."""
        src = (
            ".default_port dest=0x01\n"
            "EINSUM opb .subscript A=j,i B=j,k O=i,k .opref "
            ".shape i=2 j=2 k=2\n"
        )
        insts = assemble(src)
        self.assertGreater(len(insts), 1)
        # Each emitted instruction's opcode should be a valid one.
        valid_opcodes = {0x10, 0x12, 0x20, 0x21, 0x22, 0x23, 0x25, 0x30, 0x32}
        for word in insts:
            opcode = (word >> 24) & 0xFF
            self.assertIn(opcode, {0x22, 0x23, 0x32},
                          f"unexpected opcode 0x{opcode:02x} in lowered chain")


class TestMultiInstruction(unittest.TestCase):

    def test_three_instructions(self):
        src = (
            ".alias port_a 0x01\n"
            ".default_port dest=port_a\n"
            "ADD .imm16 5\n"
            "MATMUL opb .opref\n"
            "EINSUM opb .subscript A=i B=i O= .opref\n"
        )
        insts = assemble(src)
        self.assertEqual(len(insts), 3)
        # Spot-check the first instruction is an ADD.
        self.assertEqual((insts[0] >> 24) & 0xFF, 0x10)
        self.assertEqual((insts[1] >> 24) & 0xFF, 0x30)
        self.assertEqual((insts[2] >> 24) & 0xFF, 0x32)


class TestNormMacros(unittest.TestCase):
    """v1.6.4 §22.11 — RISC-ish normalization macros.

    Compositional decomposition of BatchNorm/RMSNorm/LayerNorm into
    Group A/B/C primitives (v1.6.1a/b + v1.6.2/3). Macro-level unit tests
    verify expansion count, opcode sequence, and constant propagation."""

    def test_batchnorm_infer_expansion(self):
        """BATCHNORM_INFER → 2 primitives (SIMD_MUL_WIDE_VEC + SIMD_ADD_WIDE_VEC)."""
        src = (
            ".default_port dest=0x01\n"
            "BATCHNORM_INFER opb .k1 0x1234_5678_9ABC_DEF0 "
            ".k2 0x0FED_CBA9_8765_4321\n"
        )
        insts = wta.assemble(src)
        opcodes = [(w >> 24) & 0xFF for w in insts]
        self.assertEqual(opcodes, [0x65, 0x63],
                         f"expected [SIMD_MUL_WIDE_VEC=0x65, SIMD_ADD_WIDE_VEC=0x63], got {[hex(o) for o in opcodes]}")

    def test_batchnorm_infer_missing_k1_raises(self):
        """Missing .k1 directive raises clear error."""
        src = (
            ".default_port dest=0x01\n"
            "BATCHNORM_INFER opb .k2 0xAAAA\n"
        )
        with self.assertRaises(wta.AssemblerError) as ctx:
            wta.assemble(src)
        self.assertIn('k1', str(ctx.exception))

    # v1.8.0d §23.10.10 — the hybrid norm rebuild's expected opcode chains.
    # The fp32 scalar insert (replacing SCALAR_RSQRT 0x66, which was later
    # fully removed from the ISA in the pre-stable opcode cleanup — the
    # NotIn(0x66) retirement asserts below remain valid): CVT(I2F) ->
    # ADD(1/N producer) -> FSCALAR(FS_MUL) -> [ADD(eps producer) ->
    # FSCALAR(FS_ADD)] -> FRSQRT32 -> ADD(256 producer) -> FSCALAR(FS_MUL)
    # -> CVT(F2I). eps=0 selects the int-scalar clamp fallback (OR 0x15
    # before the CVT, fp-eps pair dropped). LAYERNORM keeps this 0d form
    # VERBATIM (spec section 25.1 CLOSED-DEFERRED: beta has no
    # fp-vector-add home in 0e).
    _INSERT_FP = [0x77, 0x10, 0x74, 0x10, 0x74, 0x75, 0x10, 0x74, 0x77]
    _INSERT_CLAMP = [0x15, 0x77, 0x10, 0x74, 0x75, 0x10, 0x74, 0x77]
    # v1.8.0e §25.1 item 7 — the RMSNORM 0e insert STOPS at the FRSQRT32
    # fp32 scale (x256/F2I tail deleted); constants carry the gamma
    # exponent fold. Tail per 16-lane half: GAMMA_MUL_W(0x6B) +
    # DEQUANT(0x78).
    _INSERT_FP_0E = [0x77, 0x10, 0x74, 0x10, 0x74, 0x75]
    _INSERT_CLAMP_0E = [0x15, 0x77, 0x10, 0x74, 0x75]

    def test_rmsnorm_expansion(self):
        """RMSNORM → v1.8.0e fp-exact chain: EINSUM(L2SQ) + the 0e fp32
        scalar insert (stops at the FRSQRT32 scale — the 0d x256/F2I/
        Q8.8/int-gamma tail is DELETED) + the GAMMA_MUL_W/DEQUANT tail
        (one pair at .n 16). The two FSCALAR B-constant producer
        dispatches (ADD .imm64) are explicitly emitted and counted."""
        src = (
            ".default_port dest=0x01\n"
            "RMSNORM opb .gamma 0xDEADBEEFCAFEBABE\n"
        )
        insts = wta.assemble(src)
        opcodes = [(w >> 24) & 0xFF for w in insts]
        expected = [0x32] + self._INSERT_FP_0E + [0x6B, 0x78]
        self.assertEqual(opcodes, expected,
                         f"expected {[hex(o) for o in expected]}, got "
                         f"{[hex(o) for o in opcodes]}")
        self.assertNotIn(0x66, opcodes, "SCALAR_RSQRT must be retired")
        for gone, name in ((0x69, "Q8.8 tail"), (0x65, "int-gamma tail")):
            self.assertNotIn(gone, opcodes,
                             f"0d {name} must be deleted from RMSNORM-0e")
        self.assertEqual(opcodes.count(0x10), 2,
                         "2 B-constant producer dispatches on the fp path")

    def test_rmsnorm_eps_zero_clamp_fallback(self):
        """RMSNORM .eps 0 → the int-scalar clamp fallback: OR .imm64 1
        pins the L2SQ sum away from 0 (no Inf out of FRSQRT32) and the
        fp-eps producer/FS_ADD pair is dropped (1 producer remains on
        the 0e insert)."""
        src = (
            ".default_port dest=0x01\n"
            "RMSNORM opb .gamma 0xDEADBEEFCAFEBABE .eps 0\n"
        )
        insts = wta.assemble(src)
        opcodes = [(w >> 24) & 0xFF for w in insts]
        expected = [0x32] + self._INSERT_CLAMP_0E + [0x6B, 0x78]
        self.assertEqual(opcodes, expected,
                         f"expected {[hex(o) for o in expected]}, got "
                         f"{[hex(o) for o in opcodes]}")
        self.assertEqual(opcodes.count(0x10), 1,
                         "1 B-constant producer on the 0e clamp path")

    def test_rmsnorm_eps_guard_rejects_sub_2e13(self):
        """The eps >= 2^-13 assembler guard (spec §23.10.10 residual risk
        7): the common eps=1e-5 default is REJECTED with a textual error
        naming both escapes (raise eps / .eps 0 clamp fallback)."""
        src = (
            ".default_port dest=0x01\n"
            "RMSNORM opb .gamma 1 .eps %d\n" % wta.fp32_to_bits(1e-5)
        )
        with self.assertRaises(wta.AssemblerError) as ctx:
            wta.assemble(src)
        self.assertIn('2^-13', str(ctx.exception))
        self.assertIn('.eps 0', str(ctx.exception))
        # boundary: exactly 2^-13 passes
        ok = (
            ".default_port dest=0x01\n"
            "RMSNORM opb .gamma 1 .eps %d\n" % wta.fp32_to_bits(2.0 ** -13)
        )
        wta.assemble(ok)   # must not raise
        # non-finite / negative eps bits rejected
        for bad in (0x7F800000, 0x7FC00000, 0x80000000 | wta.fp32_to_bits(0.5)):
            with self.assertRaises(wta.AssemblerError):
                wta.assemble(
                    ".default_port dest=0x01\n"
                    "RMSNORM opb .gamma 1 .eps %d\n" % bad)

    @staticmethod
    def _expand(src):
        prog = wta.parse(src)
        prog = wta.alias_pass(prog)
        prog = wta.default_pass(prog)
        prog = wta.macro_pass(prog)
        return [s for s in prog.stmts if isinstance(s, wta.Instruction)]

    def test_norm_insert_fp_steps_carry_precision_mode_0x14(self):
        """Every fp-block step of the insert (CVT/FSCALAR/FRSQRT32) must
        carry .precision mode=0x14 + the 'prec' flag (require_precision_eh
        — the fp ops would otherwise be assembler-rejected), and the
        FSCALAR steps the 'opb' flag (B on payload_b from the producers).
        RMSNORM (0e insert, .n 16 default gfrac=3): 1 CVT + 2 FSCALAR +
        1 FRSQRT, and the folded 1/N producer carries bits(4^3/16) =
        bits(4.0) — the gamma-exponent fold. LAYERNORM (0d insert
        verbatim, .n 4): 2 CVT + 3 FSCALAR + 1 FRSQRT with the UNFOLDED
        bits(0.25) — .n plumbed through, no fold on the 0d path."""
        insts = self._expand(
            ".default_port dest=0x01\n"
            "RMSNORM opb .gamma 1 .n 16\n"
        )
        fp_steps = [i for i in insts
                    if i.mnemonic in ('CVT', 'FSCALAR', 'FRSQRT32')]
        self.assertEqual(len(fp_steps), 4)   # 1 CVT + 2 FSCALAR + 1 FRSQRT
        for step in fp_steps:
            self.assertIn('prec', step.flags, step.mnemonic)
            prec = next(eh for eh in step.eh_list if eh.kind == 'precision')
            self.assertEqual(prec.args['mode'], 0x14, step.mnemonic)
            if step.mnemonic == 'FSCALAR':
                self.assertIn('opb', step.flags)
        producers = [i for i in insts if i.mnemonic == 'ADD']
        self.assertEqual(len(producers), 2)
        inv_n = next(eh for eh in producers[0].eh_list if eh.kind == 'imm64')
        self.assertEqual(inv_n.args['value'], wta.fp32_to_bits(4.0),
                         "1/16 folded by 4^3 (default .gfrac 3) = 4.0f")
        eps_p = next(eh for eh in producers[1].eh_list if eh.kind == 'imm64')
        self.assertEqual(eps_p.args['value'],
                         wta.fp32_to_bits((2.0 ** -13) * 64.0),
                         "default eps folded by 4^3")
        fsc_subops = [
            (next(eh for eh in i.eh_list if eh.kind == 'imm16')
             .args['value'] >> 4) & 0xF
            for i in insts if i.mnemonic == 'FSCALAR']
        FS = wta.FSCALAR_OP_CODE
        self.assertEqual(fsc_subops, [FS['FS_MUL'], FS['FS_ADD']])
        cvts = [i for i in insts if i.mnemonic == 'CVT']
        self.assertEqual(len(cvts), 1, "the F2I CVT is deleted in 0e")
        self.assertFalse(any(eh.kind == 'imm16' for eh in cvts[0].eh_list),
                         "I2F CVT rides the absent-imm16 WIDEN default")

        # LAYERNORM: the 0d insert VERBATIM (deferral pin) — unfolded
        # constants, x256 producer + F2I retained, .n plumbed through.
        insts = self._expand(
            ".default_port dest=0x01\n"
            "LAYERNORM opb .gamma 1 .beta 2 .n 4\n"
        )
        fp_steps = [i for i in insts
                    if i.mnemonic in ('CVT', 'FSCALAR', 'FRSQRT32')]
        self.assertEqual(len(fp_steps), 6)   # 2 CVT + 3 FSCALAR + 1 FRSQRT
        producers = [i for i in insts if i.mnemonic == 'ADD']
        self.assertEqual(len(producers), 3)
        inv_n = next(eh for eh in producers[0].eh_list if eh.kind == 'imm64')
        self.assertEqual(inv_n.args['value'], wta.fp32_to_bits(0.25))
        x256 = next(eh for eh in producers[2].eh_list if eh.kind == 'imm64')
        self.assertEqual(x256.args['value'], wta.fp32_to_bits(256.0))
        cvts = [i for i in insts if i.mnemonic == 'CVT']
        imm = next(eh for eh in cvts[1].eh_list if eh.kind == 'imm16')
        self.assertEqual(imm.args['value'],
                         wta.cvt_subop_imm16('NARROW_FROM_F32'))

    def test_rmsnorm_tail_shape(self):
        """v1.8.0e §25.2.3/§25.2.2 — the RMSNORM tail pair: GAMMA_MUL_W
        carries 'prec' + .precision mode=0x10 (int4/acc=1/rnd=0) + the
        gamma .imm64 (IMM64 XOR OPREF — imm is the canonical asm form);
        DEQUANT carries 'prec' + mode=0x11 (SOURCE int8 — dest is pinned
        bf16-only, no dest carrier) + 'opb' (the scale rides payload_b
        on the completing beat) and NO imm/opref EH (port-only
        legality)."""
        insts = self._expand(
            ".default_port dest=0x01\n"
            "RMSNORM opb .gamma 0xDEADBEEFCAFEBABE\n"
        )
        gam = [i for i in insts if i.mnemonic == 'GAMMA_MUL_W']
        deq = [i for i in insts if i.mnemonic == 'DEQUANT']
        self.assertEqual((len(gam), len(deq)), (1, 1))
        g = gam[0]
        self.assertIn('prec', g.flags)
        prec = next(eh for eh in g.eh_list if eh.kind == 'precision')
        self.assertEqual(prec.args['mode'], 0x10)
        imm = next(eh for eh in g.eh_list if eh.kind == 'imm64')
        self.assertEqual(imm.args['value'], 0xDEAD_BEEF_CAFE_BABE)
        self.assertFalse(any(eh.kind == 'opref' for eh in g.eh_list),
                         "imm64 XOR opref — the macro emits the imm form")
        d = deq[0]
        self.assertIn('prec', d.flags)
        self.assertIn('opb', d.flags)
        prec = next(eh for eh in d.eh_list if eh.kind == 'precision')
        self.assertEqual(prec.args['mode'], 0x11)
        self.assertFalse(any(eh.kind in ('imm16', 'imm32', 'imm64', 'opref')
                             for eh in d.eh_list),
                         "DEQUANT is port-only (forbid_imm_any + "
                         "forbid_opref stand)")
        # whole-macro legality: the expansion must pass assemble() whole
        wta.assemble(".default_port dest=0x01\n"
                     "RMSNORM opb .gamma 0xDEADBEEFCAFEBABE\n")

    def test_rmsnorm_n32_two_pairs_share_scale(self):
        """.n 32 lowers as TWO 16-lane GAMMA_MUL_W/DEQUANT pairs (spec
        §25.2.3: the 32-lane 0x6B form is CLOSED-DEFERRED — N=32 = two
        16-lane dispatches sharing one s), gamma imm64 halves in lane
        order (low half = lanes 0-15). .n outside {16, 32} and oversized
        .gamma are textual errors."""
        gamma = (0xAAAA_BBBB_CCCC_DDDD << 64) | 0x1111_2222_3333_4444
        insts = self._expand(
            ".default_port dest=0x01\n"
            "RMSNORM opb .gamma 0x%x .n 32\n" % gamma
        )
        opcodes = [wta.MNEMONIC_TO_OPCODE[i.mnemonic] for i in insts]
        self.assertEqual(opcodes,
                         [0x32] + self._INSERT_FP_0E + [0x6B, 0x78,
                                                        0x6B, 0x78])
        gam = [i for i in insts if i.mnemonic == 'GAMMA_MUL_W']
        halves = [next(eh for eh in g.eh_list if eh.kind == 'imm64')
                  .args['value'] for g in gam]
        self.assertEqual(halves, [0x1111_2222_3333_4444,
                                  0xAAAA_BBBB_CCCC_DDDD])
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(".default_port dest=0x01\n"
                         "RMSNORM opb .gamma 1 .n 8\n")
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(".default_port dest=0x01\n"
                         "RMSNORM opb .gamma 0x%x .n 16\n" % (1 << 64))
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(".default_port dest=0x01\n"
                         "RMSNORM opb .gamma 1 .gfrac 9\n")

    def test_rmsnorm_gamma_fold_bit_equiv(self):
        """v1.8.0e §25.2.3 'folds free' pin — THE op-for-op match proof:
        simulating the macro-emitted chain (with ITS folded constants)
        through the golden primitives must be BIT-EQUAL to golden
        rmsnorm_chain_0e (which applies the gamma exponent as a
        post-rsqrt f32_exp_shift). Divergence here = the emitted chain
        no longer matches the model that proved MSE ratio 1.0 =
        release-blocked. Sweeps .gfrac (incl. 0), eps values, both N,
        and the clamp-fallback path."""
        import random
        sys.path.insert(0, os.path.join(_HERE, '..', 'scripts'))
        import golden_fp32 as g
        rng = random.Random(0xE0E1)
        checked = 0
        for n in (16, 32):
            for k in (0, 1, 3, 5):
                for eps in (0, g.RMSNORM_EPS_DEFAULT_BITS, 0x3C800000,
                            0x42800000):
                    x = [rng.randint(0, 15) for _ in range(n)]
                    gam = [rng.randint(0, 15) for _ in range(n)]
                    insts = self._expand(
                        ".default_port dest=0x01\n"
                        "RMSNORM opb .gamma 1 .n %d .gfrac %d .eps %d\n"
                        % (n, k, eps))
                    consts = [
                        next(eh for eh in i.eh_list
                             if eh.kind == 'imm64').args['value']
                        for i in insts if i.mnemonic == 'ADD']
                    clamp = any(i.mnemonic == 'OR' for i in insts)
                    self.assertEqual(clamp, eps == 0)
                    # replay the EMITTED chain through golden primitives
                    ssq = sum(g._i2f_operand(f, g.DT_INT4) ** 2 for f in x)
                    if clamp:
                        ssq |= 1
                    sq_f = g.ref_i2f(ssq, g.DT_ACC_INT)
                    m = g.ref_mul(sq_f, consts[0])
                    me = g.ref_add(m, consts[1]) if len(consts) > 1 else m
                    s = g.micro_rsqrt(me)
                    y_macro = []
                    for h in range(n // 16):
                        w = g.ref_gamma_mul_w(x[16 * h:16 * h + 16],
                                              gam[16 * h:16 * h + 16])
                        y_macro += g.ref_dequant(w, s, g.DT_INT8)
                    # golden model of the same call (clamp path: golden
                    # has no OR step — emulate via the eps=2^-13-default
                    # equivalence only on the fp-eps rows)
                    if clamp:
                        x_or = list(x)
                        ssq_g = ssq  # already OR'd — feed golden the
                        # identical post-clamp integer via a 1-lane tweak:
                        # rmsnorm_chain_0e recomputes ssq from lanes, so
                        # compare against the primitive replay with the
                        # UNFOLDED constant + post-shift instead.
                        c0 = g.f32_exp_shift(consts[0], -2 * k) if k else consts[0]
                        m2 = g.ref_mul(sq_f, c0)
                        s2 = g.f32_exp_shift(g.micro_rsqrt(m2), -k) \
                            if k else g.micro_rsqrt(m2)
                        y_gold = []
                        for h in range(n // 16):
                            w = g.ref_gamma_mul_w(x[16 * h:16 * h + 16],
                                                  gam[16 * h:16 * h + 16])
                            y_gold += g.ref_dequant(w, s2, g.DT_INT8)
                    else:
                        y_gold, _ = g.rmsnorm_chain_0e(
                            x, gam, gamma_frac_bits=k, eps_bits=eps,
                            scale_exp=0)
                    self.assertEqual(
                        y_macro, y_gold,
                        f"macro chain diverged from golden at n={n} "
                        f"k={k} eps=0x{eps:08X}")
                    checked += 1
        self.assertEqual(checked, 32)

    def test_layernorm_expansion(self):
        """LAYERNORM → v1.8.0d hybrid chain per §22.3/§22.16/§23.10.10:
        MEAN + SUB_VEC + L2SQ, then the SAME fp32 scalar insert RMSNORM
        uses (shared helper — drift-proof), then the v1.6.5c xc-reload
        tail bit-unchanged (CACHE_LOAD_WIDE + Q8.8 + MUL_VEC + ADD_VEC)."""
        src = (
            ".default_port dest=0x01\n"
            "LAYERNORM opb .gamma 0x1111_2222_3333_4444 "
            ".beta 0x5555_6666_7777_8888\n"
        )
        insts = wta.assemble(src)
        opcodes = [(w >> 24) & 0xFF for w in insts]
        expected = [0x32, 0x64, 0x32] + self._INSERT_FP \
                 + [0x68, 0x69, 0x65, 0x63]
        self.assertEqual(opcodes, expected,
                         f"expected {[hex(o) for o in expected]}, got "
                         f"{[hex(o) for o in opcodes]}")
        self.assertNotIn(0x66, opcodes, "SCALAR_RSQRT must be retired")

    def test_layernorm_step5_cache_load_wide_precision_guard(self):
        """v1.6.5c §22.16 tag-stability: step 5 (CACHE_LOAD_WIDE) must carry
        a .precision dim=0x55 EH + dim_ovr flag, pinning its dispatch tag's
        dim_sizes to match step 2's stored producer tag (which inherits
        0x55 from step 1's OP_MEAN) independent of step 4's SCALAR_RSQRT
        hardcoding its own output dim_sizes to 0x00."""
        src = (
            ".default_port dest=0x01\n"
            "LAYERNORM opb .gamma 0x1111_2222_3333_4444 "
            ".beta 0x5555_6666_7777_8888\n"
        )
        insts = wta.assemble(src)
        # v1.8.0d: the fp32 scalar insert shifted the reload's position —
        # locate it by opcode (exactly one CACHE_LOAD_WIDE in the chain).
        reloads = [w for w in insts if ((w >> 24) & 0xFF) == 0x68]
        self.assertEqual(len(reloads), 1)
        step5 = reloads[0]
        # Base header flags nibble is bits [19:16]; dim_ovr = bit 0.
        flags_nibble = (step5 >> 16) & 0xF
        self.assertEqual(flags_nibble & 0x1, 0x1, "dim_ovr flag must be set")

    def test_encode_precision_eh_word_dim_0x55(self):
        """Pure encoder unit test (mirrors EHDecode.v's is_precision_c
        capture: acc_prec_dim <= cur_w0[31:24]): _encode_eh on a
        .precision dim=0x55 EH must produce a word whose bits[31:24] ==
        0x55, matching CACHE_LOAD_WIDE's tag-stability guard literal."""
        eh = wta.ExtensionHeader('precision', {'dim': 0x55}, 0)
        type_code, words = wta._encode_eh(eh)
        self.assertEqual(type_code, wta.EH_PRECISION)
        self.assertEqual(len(words), 1)
        self.assertEqual((words[0] >> 24) & 0xFF, 0x55)

    def test_layernorm_abort_cleanup_matches_step5_shape(self):
        """v1.6.5d §22.17 SDK abort-cleanup contract: make_layernorm_
        abort_cleanup() must produce a FRAG_INVAL instruction with the
        EXACT SAME tag-addressing shape (flags + precision EH) as step
        5's CACHE_LOAD_WIDE — both now derive from the SAME shared
        _layernorm_xc_slot_addressing() helper, so this test also locks
        in that the refactor didn't silently diverge the two call sites."""
        src = (
            ".default_port dest=0x01\n"
            "LAYERNORM opb .gamma 0x1111_2222_3333_4444 "
            ".beta 0x5555_6666_7777_8888\n"
        )
        prog = wta.parse(src)
        prog = wta.alias_pass(prog)
        prog = wta.default_pass(prog)
        layernorm_call = next(
            s for s in prog.stmts
            if isinstance(s, wta.Instruction) and s.mnemonic == 'LAYERNORM'
        )
        cleanup_inst = wta.make_layernorm_abort_cleanup(layernorm_call)
        self.assertEqual(cleanup_inst.mnemonic, 'FRAG_INVAL')
        self.assertIn('dim_ovr', cleanup_inst.flags)
        prec_eh = next(eh for eh in cleanup_inst.eh_list if eh.kind == 'precision')
        self.assertEqual(prec_eh.args['dim'], 0x55)

        # Compare against step 5's actual emitted shape from the same
        # LAYERNORM call, via the real _lower_layernorm(). v1.8.0d: locate
        # by mnemonic (the fp32 scalar insert shifted the index).
        steps = wta._lower_layernorm(layernorm_call)
        step5 = next(s for s in steps if s.mnemonic == 'CACHE_LOAD_WIDE')
        step5_prec = next(eh for eh in step5.eh_list if eh.kind == 'precision')
        self.assertEqual(prec_eh.args['dim'], step5_prec.args['dim'],
                         "abort-cleanup dim literal diverged from step 5's")
        self.assertEqual('dim_ovr' in cleanup_inst.flags, 'dim_ovr' in step5.flags)

    def test_layernorm_abort_cleanup_assembles_to_frag_inval(self):
        """The abort-cleanup instruction must actually assemble (legality-
        pass + encode) to opcode 0x6A, end to end through encode_pass."""
        src = (
            ".default_port dest=0x01\n"
            "LAYERNORM opb .gamma 0x1111_2222_3333_4444 "
            ".beta 0x5555_6666_7777_8888\n"
        )
        prog = wta.parse(src)
        prog = wta.alias_pass(prog)
        prog = wta.default_pass(prog)
        layernorm_call = next(
            s for s in prog.stmts
            if isinstance(s, wta.Instruction) and s.mnemonic == 'LAYERNORM'
        )
        cleanup_inst = wta.make_layernorm_abort_cleanup(layernorm_call)
        checked = wta.legality_pass(wta.Program(stmts=[cleanup_inst]))
        encoded = wta.encode_pass(checked)
        self.assertEqual(len(encoded), 1)
        self.assertEqual((encoded[0] >> 24) & 0xFF, 0x6A)

    def test_layernorm_missing_beta_raises(self):
        """LAYERNORM missing .beta raises."""
        src = (
            ".default_port dest=0x01\n"
            "LAYERNORM opb .gamma 0xAAAA\n"
        )
        with self.assertRaises(wta.AssemblerError) as ctx:
            wta.assemble(src)
        self.assertIn('beta', str(ctx.exception))

    def test_primitive_simd_add_wide_scalar_legality(self):
        """SIMD_ADD_WIDE_SCALAR: binary-ALU (IMM XOR OPREF)."""
        src = (
            ".default_port dest=0x01\n"
            "SIMD_ADD_WIDE_SCALAR .imm16 5\n"
        )
        insts = wta.assemble(src)
        self.assertEqual((insts[0] >> 24) & 0xFF, 0x60)

    # (test_primitive_scalar_rsqrt_* and test_primitive_simd_mul_wide_
    # q4_4_scalar_legality deleted in the pre-stable opcode cleanup —
    # see TestRemovedOpcodes for the replacement rejection pins.)

    def test_primitive_simd_mul_wide_q8_8_scalar_legality(self):
        """v1.6.7: SIMD_MUL_WIDE_Q8_8_SCALAR (0x69) — same legality as
        SIMD_MUL_WIDE_SCALAR (binary-ALU IMM XOR OPREF); full 16-bit IMM16
        maps directly onto the Q8.8 B operand (dec_eff_b_value[15:0])."""
        src = (
            ".default_port dest=0x01\n"
            "SIMD_MUL_WIDE_Q8_8_SCALAR .imm16 0x0180\n"   # Q8.8 = 1.5
        )
        insts = wta.assemble(src)
        self.assertEqual((insts[0] >> 24) & 0xFF, 0x69)

    def test_primitive_cache_load_wide_legality(self):
        """v1.6.5c §22.16: CACHE_LOAD_WIDE (0x68) — pure Cluster-buffer CAM
        passthrough, no B operand (the no-data-EH shape, shared with
        FRAG_INVAL 0x6A). A .precision EH is legal (not in
        _ALL_DATA_EHS)."""
        src = (
            ".default_port dest=0x01\n"
            "CACHE_LOAD_WIDE .precision dim=0x55\n"
        )
        insts = wta.assemble(src)
        self.assertEqual((insts[0] >> 24) & 0xFF, 0x68)

    def test_primitive_cache_load_wide_rejects_imm(self):
        """CACHE_LOAD_WIDE with .imm16 must raise (no B operand at all)."""
        src = (
            ".default_port dest=0x01\n"
            "CACHE_LOAD_WIDE .imm16 5\n"
        )
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(src)

    def test_primitive_cache_load_wide_dim_ovr_requires_precision_eh(self):
        """dim_ovr flag without a .precision EH must raise at compile time
        (mirrors the existing prec/dim_ovr-without-EH check)."""
        src = (
            ".default_port dest=0x01\n"
            "CACHE_LOAD_WIDE dim_ovr\n"
        )
        with self.assertRaises(wta.AssemblerError) as ctx:
            wta.assemble(src)
        self.assertIn('dim_ovr', str(ctx.exception))

    def test_primitive_frag_inval_legality(self):
        """v1.6.5d §22.17: FRAG_INVAL (0x6A) — explicit Cluster-buffer
        slot invalidate-by-tag, same no-B shape as 0x68."""
        src = (
            ".default_port dest=0x01\n"
            "FRAG_INVAL\n"
        )
        insts = wta.assemble(src)
        self.assertEqual((insts[0] >> 24) & 0xFF, 0x6A)

    def test_primitive_frag_inval_rejects_imm(self):
        """FRAG_INVAL with .imm16 must raise (no B operand at all)."""
        src = (
            ".default_port dest=0x01\n"
            "FRAG_INVAL .imm16 5\n"
        )
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(src)

    # (test_primitive_widen_*, test_primitive_requantize_* and
    # test_widen_requantize_opcode_table_matches_hardware deleted in the
    # pre-stable opcode cleanup — see TestRemovedOpcodes.)


class TestRemovedOpcodes(unittest.TestCase):
    """Pre-stable opcode cleanup (spec removal record, 2026-07-24):
    0x66/0x67/0x6B/0x6C were deleted from isa/wt64v1_isa.json. The
    assembler consumes the regenerated tables, so each removed mnemonic
    must now be REJECTED (the asm-side mirror of the RTL decode_error the
    truth-table domain_version-2 capture pins), and the opcode numbers
    must be absent from every generated table."""

    def _assert_rejected(self, line):
        src = ".default_port dest=0x01\n" + line + "\n"
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(src)

    def test_removed_scalar_rsqrt_rejected(self):
        self._assert_rejected("SCALAR_RSQRT")
        self.assertNotIn(0x66, wta._LEGAL)
        self.assertNotIn('SCALAR_RSQRT', wta.MNEMONIC_TO_OPCODE)

    def test_removed_simd_mul_wide_q4_4_scalar_rejected(self):
        self._assert_rejected("SIMD_MUL_WIDE_Q4_4_SCALAR .imm16 0x18")
        self.assertNotIn(0x67, wta._LEGAL)
        self.assertNotIn('SIMD_MUL_WIDE_Q4_4_SCALAR', wta.MNEMONIC_TO_OPCODE)

    def test_removed_widen_rejected(self):
        # v1.8.0e 0e1: the 0x6B CODE POINT was reallocated pre-stable to
        # GAMMA_MUL_W (spec section 25.2.3, section 12a rule 4 — slot
        # reuse recorded; this is the mandatory retired-0x6B
        # stale-consumer resync). The removed WIDEN MNEMONIC stays
        # rejected forever; the code point is live again under the new
        # name.
        self._assert_rejected("SIMD_MUL_WIDE_Q4_4_SCALAR_128_WIDEN .imm16 0x08")
        self.assertIn(0x6B, wta._LEGAL)
        self.assertEqual(wta.MNEMONIC_TO_OPCODE['GAMMA_MUL_W'], 0x6B)
        self.assertNotIn('SIMD_MUL_WIDE_Q4_4_SCALAR_128_WIDEN',
                         wta.MNEMONIC_TO_OPCODE)

    def test_removed_requantize_rejected(self):
        self._assert_rejected("SIMD_REQUANTIZE_Q4_4_TO_INT4")
        self.assertNotIn(0x6C, wta._LEGAL)
        self.assertNotIn('SIMD_REQUANTIZE_Q4_4_TO_INT4',
                         wta.MNEMONIC_TO_OPCODE)


class TestWaveFragments(unittest.TestCase):
    """v1.5.4 §21 — wave-token fragment emitter helper.

    Splits a logical wide payload into 64-bit fragments with frag_hdr =
    (idx << 4) | (total - 1). Backs all v1.5.x wide-consumer primitives.
    """

    def test_wave_fragments_bmm3_layout(self):
        """SIG_BMM_3 (256-bit wide) → 4 fragments in emission order.
        Layout matches PE_Core.v SIG_BMM_3 dispatch: A at wide[127:0],
        B at wide[255:128]."""
        a_128 = 0xFEDCBA9876543210_0123456789ABCDEF
        b_128 = 0x5555555555555555_AAAAAAAAAAAAAAAA
        wide  = (a_128 & ((1 << 128) - 1)) | ((b_128 & ((1 << 128) - 1)) << 128)
        frags = wta.wave_fragments(wide, 256)
        self.assertEqual(len(frags), 4)
        self.assertEqual(frags[0], (a_128 & ((1 << 64) - 1),        0x03))
        self.assertEqual(frags[1], ((a_128 >> 64) & ((1 << 64) - 1), 0x13))
        self.assertEqual(frags[2], (b_128 & ((1 << 64) - 1),        0x23))
        self.assertEqual(frags[3], ((b_128 >> 64) & ((1 << 64) - 1), 0x33))
        # frag_hdr low nibble = total-1 = 3 uniformly
        self.assertTrue(all((h & 0x0F) == 0x03 for _, h in frags))
        # frag_hdr high nibble = strictly increasing index
        self.assertEqual([h >> 4 for _, h in frags], [0, 1, 2, 3])

    def test_wave_fragments_bmm3_convenience(self):
        """wave_fragments_bmm3(A, B) is a thin wrapper around
        wave_fragments(wide, 256) — verify layout agreement."""
        a_128 = 0x1111222233334444_5555666677778888
        b_128 = 0x9999AAAABBBBCCCC_DDDDEEEEFFFF0000
        via_helper  = wta.wave_fragments_bmm3(a_128, b_128)
        wide        = (a_128 & ((1 << 128) - 1)) | ((b_128 & ((1 << 128) - 1)) << 128)
        via_generic = wta.wave_fragments(wide, 256)
        self.assertEqual(via_helper, via_generic)

    def test_wave_fragments_trace_iijkl_layout(self):
        """SIG_TRACE_IIJKL (128-bit A, no B) → 2 fragments."""
        a_128 = 0x0011223344556677_8899AABBCCDDEEFF
        frags = wta.wave_fragments(a_128, 128)
        self.assertEqual(len(frags), 2)
        self.assertEqual(frags[0], (a_128 & ((1 << 64) - 1),        0x01))
        self.assertEqual(frags[1], ((a_128 >> 64) & ((1 << 64) - 1), 0x11))
        self.assertTrue(all((h & 0x0F) == 0x01 for _, h in frags))
        self.assertEqual([h >> 4 for _, h in frags], [0, 1])
        # Convenience helper agrees
        self.assertEqual(wta.wave_fragments_trace_iijkl(a_128), frags)

    def test_wave_fragments_legacy_single(self):
        """Legacy 64-bit payload → 1 fragment, frag_hdr=0x00 (Cluster
        bypass path). Empty wave (wide_bits=0) → []."""
        frags = wta.wave_fragments(0xDEADBEEFCAFEBABE, 64)
        self.assertEqual(len(frags), 1)
        self.assertEqual(frags[0], (0xDEADBEEFCAFEBABE, 0x00))
        # Empty wave
        self.assertEqual(wta.wave_fragments(0, 0), [])
        # Invalid wide_bits raises. v1.8.0e 3a-C2 widened the accepted
        # set to {0,64,128,192,256,512,1024} for FDOT32_CR's 16-fragment
        # A||B wave (§27.7a.1); 1024 is the FRAG_MAX ceiling, so the
        # too-large pin moves up with it.
        with self.assertRaises(wta.AssemblerError):
            wta.wave_fragments(0, 96)    # not a listed width
        with self.assertRaises(wta.AssemblerError):
            wta.wave_fragments(0, 512)   # no contract asks for 8-frag today
        with self.assertRaises(wta.AssemblerError):
            wta.wave_fragments(0, 2048)  # too large (FRAG_MAX = 16)

    def test_wave_fragments_bmm3_reassembly_matches_pe_core(self):
        """Round-trip: split with wave_fragments_bmm3, reassemble in the
        exact way Cluster.v's fragment buffer does (idx * 64 shift into
        1024-bit wide bus). Result must equal the input's expected wide
        layout: A at wide[127:0], B at wide[255:128]."""
        a_128 = 0
        b_128 = 0
        for i in range(32):
            a_128 |= ((i * 3 + 1) & 0xF) << (i * 4)
            b_128 |= ((i * 5 + 7) & 0xF) << (i * 4)
        expected = (a_128 & ((1 << 128) - 1)) | ((b_128 & ((1 << 128) - 1)) << 128)

        frags = wta.wave_fragments_bmm3(a_128, b_128)
        reassembled = 0
        for payload, hdr in frags:
            idx = hdr >> 4
            reassembled |= (payload & ((1 << 64) - 1)) << (idx * 64)
        self.assertEqual(reassembled, expected)
        # Sanity: A/B halves recover cleanly
        self.assertEqual(reassembled & ((1 << 128) - 1), a_128)
        self.assertEqual((reassembled >> 128) & ((1 << 128) - 1), b_128)


if __name__ == '__main__':
    unittest.main()


class TestGeneratedIsaTables(unittest.TestCase):
    """v1.8.0a §23.9 COMMIT 1 — single-source ISA codegen enforcement.

    These tests ride the commit-mandated `python -m unittest -q
    asm.test_wavetensor_asm` suite (CONTRIBUTING §), making them the
    strongest enforcement channel this no-CI repo has.
    """

    @staticmethod
    def _gen_module():
        import importlib.util
        repo = os.path.dirname(_HERE)
        spec = importlib.util.spec_from_file_location(
            "gen_isa_tables", os.path.join(repo, "scripts", "gen_isa_tables.py"))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod

    def test_generated_isa_tables_fresh(self):
        """Regenerate all five artifacts in-memory and byte-compare against
        the committed files — fails with a diff on drift in EITHER
        direction (JSON edited without regen, or artifact hand-edited)."""
        gen = self._gen_module()
        rendered = gen.render_all()
        for key, content in rendered.items():
            path = gen.ARTIFACTS[key]
            self.assertTrue(path.exists(), f"missing generated artifact {path}")
            committed = path.read_text()
            self.assertEqual(
                committed, content,
                f"STALE generated artifact {path} — edit isa/wt64v1_isa.json, "
                f"run scripts/gen_isa_tables.py generate, commit both")

    def test_generation_deterministic(self):
        """Two consecutive renders must be byte-identical (pins the
        sorted-iteration / fixed-formatting / no-timestamp contract the
        freshness check depends on)."""
        gen = self._gen_module()
        self.assertEqual(gen.render_all(), gen.render_all())

    def test_json_schema_strictness(self):
        """The generator must REJECT malformed sources: unknown keys,
        duplicate opcodes/mnemonics, fp_block cross-inconsistency, and
        all-illegal fp ops — closing the silent-permissive-generator hole
        (self-consistent wrong legality across all five artifacts)."""
        import copy
        import json as _json
        gen = self._gen_module()
        good = _json.loads(gen.SOURCE.read_text())

        bad = copy.deepcopy(good)
        bad["opcodes"][0]["legal_dtyes"] = []          # typo'd unknown key
        with self.assertRaises(gen.SchemaError):
            gen.validate(bad)

        bad = copy.deepcopy(good)
        bad["opcodes"][1]["code"] = bad["opcodes"][0]["code"]   # dup code
        with self.assertRaises(gen.SchemaError):
            gen.validate(bad)

        bad = copy.deepcopy(good)
        bad["opcodes"][1]["mnemonic"] = bad["opcodes"][0]["mnemonic"]
        with self.assertRaises(gen.SchemaError):
            gen.validate(bad)

        bad = copy.deepcopy(good)
        bad["fp_block"]["ops"].append(dict(
            code=0x7B, mnemonic="GHOST", legal_dtypes=[4],
            legal_acc=[1], legal_rnd=[0]))              # fp op w/o opcodes[] row
        with self.assertRaises(gen.SchemaError):
            gen.validate(bad)

        # v1.8.0e 3a-C2 (spec section 27.7a.4): the two staging bits are
        # mutually exclusive. stub_v18 = decode-LEGAL, execute-side
        # lower_required arm; decode_reserved = whitelist-omitted,
        # decode_error. A row claiming both is incoherent (which fault?)
        # and must be rejected, not silently resolved by emitter order.
        #
        # v1.8.0e 3a-C4: the mutation now sets BOTH bits explicitly. It
        # used to set stub_v18 only and rely on 0x7A already carrying
        # decode_reserved=true; when C4 cleared that bit the AND in
        # gen_isa_tables.validate() stopped firing and this assertRaises
        # started FAILING. Deleting the block would have been the easy
        # "fix" and would have silently retired the ONLY test covering
        # the XOR rule. Setting both bits keeps the rule covered no
        # matter which rows carry which staging bit — today, none.
        self.assertEqual(
            [op["code"] for op in good["opcodes"]
             if op.get("decode_reserved")], [],
            "no row is decode-reserved today; if one is added, this "
            "mutation must still set BOTH bits, never rely on the row")
        bad = copy.deepcopy(good)
        for op in bad["opcodes"]:
            if op["code"] == 0x7A:
                op["decode_reserved"] = True
                op["stub_v18"] = True
        with self.assertRaises(gen.SchemaError):
            gen.validate(bad)

    def test_legacy_legality_snapshot_equivalence(self):
        """Frozen literal snapshot of the legacy ops' legality shapes,
        transcribed ONCE from pre-migration HEAD (042f08e) as 57 keys —
        the migration gate's third independent leg (hand-pinned literal
        <- generated table -> JSON source). Pre-stable edit (opcode
        cleanup, 2026-07-24, recorded spec-first per the pre-stable
        compat policy): the 0x66/0x67/0x6B/0x6C rows were removed with
        their opcodes, 57 -> 53 keys. Compares exact set CONTENTS and
        key/value TYPES."""
        # New (post-cleanup) opcodes may be ADDED (v1.8.0a COMMIT 2 fp
        # block); the 53 remaining legacy keys must all still exist
        # unchanged.
        self.assertTrue(set(_PREMIGRATION_LEGAL_SNAPSHOT) <= set(wta._LEGAL),
                        "a frozen legacy opcode disappeared from _LEGAL")
        self.assertEqual(len(_PREMIGRATION_LEGAL_SNAPSHOT), 53)
        for code, frozen in _PREMIGRATION_LEGAL_SNAPSHOT.items():
            live = wta._LEGAL[code]
            self.assertIsInstance(code, int)
            self.assertIsInstance(live["required"], set)
            self.assertIsInstance(live["forbidden"], set)
            self.assertEqual(sorted(live["required"]), frozen["required"],
                             f"required drift at 0x{code:02X}")
            self.assertEqual(sorted(live["forbidden"]), frozen["forbidden"],
                             f"forbidden drift at 0x{code:02X}")
            for k in ("allow_imm_xor_opref", "require_opb_flag", "require_imm16"):
                self.assertEqual(live[k], frozen[k], f"{k} drift at 0x{code:02X}")




class TestFpBlockModeLegality(unittest.TestCase):
    """v1.8.0a COMMIT 2 §23.6a — FP-block (0x070-0x07F) mode-byte legality.

    The spec-row pins below are transcribed character-for-character from
    the NORMATIVE §23.6a table, which landed and was reviewed in a
    SEPARATE prior commit (042f08e) — a genuinely independent anchor, not
    a same-author-same-commit circular check.
    """

    _FP_OPS = {
        0x70: 'VFMA_ACC', 0x71: 'VDOT_ACC', 0x72: 'ACC_REDUCE',
        0x73: 'ACC_ELEMWISE', 0x74: 'FSCALAR', 0x75: 'FRSQRT32',
        0x76: 'FEXP2_32', 0x77: 'CVT', 0x78: 'DEQUANT', 0x79: 'FMINMAX',
        0x7A: 'FDOT32_CR',
        0x7C: 'STORE_QUANT', 0x7D: 'ACC_SPILL_FILL', 0x7E: 'FP_ACC_CTRL',
    }

    def test_fp_block_opcode_pins(self):
        """All 14 mnemonic->opcode literal pins — catches careless JSON
        renumbering that regen-and-diff structurally cannot.

        v1.8.0e 3a-C2 (spec section 27.7a): 0x7A FDOT32_CR joined as a
        DECODE-RESERVED row — transcribed into every table here, omitted
        from the RTL opcode_supported whitelist until 3a-C4."""
        from generated_isa_tables import (DECODE_RESERVED_OPS, FP_MODE_LEGAL,
                                          STUB_OPS_V18)
        for code, mnem in self._FP_OPS.items():
            self.assertEqual(wta.MNEMONIC_TO_OPCODE[mnem], code)
        self.assertEqual(set(FP_MODE_LEGAL), set(self._FP_OPS))
        # 3a-C2 had exactly one decode-reserved row (0x7A). 3a-C4 landed
        # its PE_Core arm + twin-classifier edit and cleared the bit in
        # the SAME commit, so the set is EMPTY again. The XOR invariant
        # is asserted unconditionally so it survives the empty set.
        self.assertEqual(DECODE_RESERVED_OPS, frozenset())
        self.assertEqual(DECODE_RESERVED_OPS & STUB_OPS_V18, frozenset())
        # v1.8.0b: 0x71 VDOT_ACC / 0x72 ACC_REDUCE / 0x7C STORE_QUANT
        # graduated from stubs to real datapaths.
        # v1.8.0c: 0x74 FSCALAR / 0x75 FRSQRT32 / 0x76 FEXP2_32 graduated
        # too (MU-hosted fp32 step sequencer, spec section 23.10).
        # v1.8.0d: 0x73 ACC_ELEMWISE / 0x77 CVT graduated (spec section
        # 23.10.10).
        # v1.8.0e 0e1: 0x78 DEQUANT / 0x79 FMINMAX graduated (spec
        # section 25 — dropped spec-first with the OPS_DEQ program and
        # the FMINMAX comb arm).
        # v1.8.0e 0e2: 0x70 VFMA_ACC graduated (spec section 25.2.4 —
        # stub_v18 dropped with the lane-loop launch arm in the same
        # commit); only 0x7D/0x7E remain, both unscheduled.
        # v1.8.0e 3a-C2: 0x7A FDOT32_CR is NOT a stub — it is
        # decode-reserved (whitelist-omitted -> decode_error), so it
        # leaves the stub set untouched.
        self.assertEqual(STUB_OPS_V18,
                         frozenset(self._FP_OPS)
                         - {0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76,
                            0x77, 0x78, 0x79, 0x7A, 0x7C})
        self.assertEqual(STUB_OPS_V18,
                         frozenset({0x7D, 0x7E}))
        # Shape spot-checks: 0x70 is ALU-binary-like, 0x7E is no-data-EH.
        self.assertTrue(wta._LEGAL[0x70]['allow_imm_xor_opref'])
        self.assertEqual(wta._LEGAL[0x7E]['forbidden'], wta._ALL_DATA_EHS)
        self.assertTrue(all(wta._LEGAL[c].get('require_precision_eh')
                            for c in self._FP_OPS))

    def test_fp_rom_global_invariants_literal(self):
        """Hand-pinned literals INDEPENDENT of the generator (closing the
        common-mode oracle gap): dtype 0x5 (f64, Lf-reserved) illegal for
        every op; dtype>0x7 illegal; rnd!=0 illegal in v1.8.0a (SR is a
        v2.0 loosening); acc!=1 illegal in v1.8.0a."""
        from generated_isa_tables import FP_MODE_LEGAL
        for code, legal in FP_MODE_LEGAL.items():
            self.assertNotIn(5, legal['legal_dtypes'],
                             f"0x{code:02X}: f64/Lf dtype must be illegal")
            self.assertTrue(all(d <= 7 for d in legal['legal_dtypes']))
            self.assertEqual(legal['legal_rnd'], [0],
                             f"0x{code:02X}: only RNE legal in v1.8.0a")
            self.assertEqual(legal['legal_acc'], [1],
                             f"0x{code:02X}: only wide-acc legal in v1.8.0a")

    def test_fp_mode_legality_matches_spec_rows(self):
        """Per-op legal-dtype rows transcribed from the §23.6a normative
        table (21 legal rows / 4096 total)."""
        from generated_isa_tables import FP_MODE_LEGAL
        # v1.8.0d §23.10.10(b): 0x77 CVT legal_dtypes [2,3] -> [0,1,2,3,4]
        # (monotonic illegal->legal loosening; dtype 0x4 = accumulator-format
        # integer endpoint per COMMIT-0 pin 10, dtype 0x5 stays decode_error).
        # v1.8.0e 3a-C2 §27.7a.1: 0x7A FDOT32_CR adds EXACTLY 2 rows —
        # dtype 0x2 (f16) / 0x3 (bf16), acc=1, rnd=0. dtype names the
        # WAVE dtype directly (the conversion-dtype rule does not apply),
        # and every other combination stays ILLEGAL (restrictive-first).
        SPEC_ROWS = {
            0x70: [0, 1], 0x71: [0, 1], 0x72: [0, 1], 0x73: [4],
            0x74: [4], 0x75: [4], 0x76: [4], 0x77: [0, 1, 2, 3, 4],
            0x78: [0, 1],
            0x79: [4], 0x7A: [2, 3], 0x7C: [0, 1, 2, 3], 0x7D: [4],
            0x7E: [4],
        }
        for code, dtypes in SPEC_ROWS.items():
            self.assertEqual(FP_MODE_LEGAL[code]['legal_dtypes'], dtypes,
                             f"0x{code:02X} dtype row diverged from spec §23.6a")
        total = sum(len(l['legal_dtypes']) * len(l['legal_acc']) * len(l['legal_rnd'])
                    for l in FP_MODE_LEGAL.values())
        self.assertEqual(total, 26,
                         "legal-row count diverged from spec §23.6a/§23.10.10/§27.7a.1")

    def test_asm_requires_precision_eh_on_fp_block(self):
        """Every fp-block mnemonic without .precision EH + prec flag must
        raise at assembly time."""
        for code, mnem in self._FP_OPS.items():
            scaffold = ''
            if wta._LEGAL[code]['allow_imm_xor_opref']:
                scaffold = ' .imm16 1'
            elif 'mem' in wta._LEGAL[code]['required']:
                scaffold = ' .mem offset=0'
            with self.assertRaises(wta.AssemblerError, msg=mnem):
                wta.assemble(f".default_port dest=0x01\n{mnem}{scaffold}\n")

    def test_asm_mode_check_equivalence_with_golden_table(self):
        """Exhaustive 13x256: assembler accept <=> FP_MODE_LEGAL legal.
        Catches implementation bugs in legality_pass's bit split (the RTL
        sweep separately validates ROM == FP_MODE_LEGAL).

        SCOPE NOTE (3a-C2, spec §27.7a.4): this equivalence is about the
        MODE ROM only.  It does NOT establish asm-legal ⊆ RTL-legal for
        0x7A: FDOT32_CR is `decode_reserved` until 3a-C4, so the RTL
        rejects every 0x7A mode with decode_error while the assembler
        accepts modes 0x12/0x13.  That asymmetry is the staged landing
        pinned by the spec, not a defect — see the third asymmetry listed
        in isa/wt64v1_isa.json `_doc`."""
        from generated_isa_tables import FP_MODE_LEGAL
        for code, mnem in self._FP_OPS.items():
            legal = FP_MODE_LEGAL[code]
            scaffold = ''
            if wta._LEGAL[code]['allow_imm_xor_opref']:
                # v1.8.0d: 0x73 is OPREF-form only (imm forms are asm-
                # rejected as execute-side dead-ends), so its XOR
                # scaffold must be the .opref side.
                scaffold = ' .opref' if code == 0x73 else ' .imm16 1'
            elif 'mem' in wta._LEGAL[code]['required']:
                scaffold = ' .mem offset=0'
            # v1.8.0c §23.10.2: FSCALAR requires F_HAS_OPB on every sub-op.
            # v1.8.0e §25.2.1/§25.2.2: FMINMAX (FSCALAR legality clone)
            # and DEQUANT (fp32 scale on payload_b, completing-beat SDK
            # contract) joined the hardcoded opb-required set.
            flags = ' prec opb' if code in (0x74, 0x78, 0x79) else ' prec'
            for mode in range(256):
                dtype, acc, rnd = mode & 0xF, (mode >> 4) & 0x3, (mode >> 6) & 0x3
                expect_ok = (dtype in legal['legal_dtypes']
                             and acc in legal['legal_acc']
                             and rnd in legal['legal_rnd'])
                src = (f".default_port dest=0x01\n"
                       f"{mnem}{flags}{scaffold} .precision mode={mode}\n")
                if expect_ok:
                    wta.assemble(src)   # must not raise
                else:
                    with self.assertRaises(wta.AssemblerError,
                                           msg=f"{mnem} mode=0x{mode:02X}"):
                        wta.assemble(src)


class TestFscalarV180cEncoding(unittest.TestCase):
    """v1.8.0c §23.10 — asm-layer encoding for 0x74 FSCALAR / 0x75
    FRSQRT32 / 0x76 FEXP2_32. Encoding-level only; the RTL datapath
    landed in the COMMIT F integration (MU-hosted FP_StepSeq) and is
    covered by the ISA_Decoder / Cluster testbenches.
    """

    # Only legal mode byte for 0x74/0x75/0x76: dtype=4 (f32), acc=1, rnd=0.
    _MODE_F32 = 0x14

    def test_fscalar_op_code_table_pin(self):
        """Literal pin of the generated fscalar_op_codes table (single
        source isa/wt64v1_isa.json) — catches careless renumbering that
        regen-and-diff structurally cannot."""
        from generated_isa_tables import FSCALAR_OP_CODE
        self.assertEqual(FSCALAR_OP_CODE, {
            'FS_ADD': 0, 'FS_SUB': 1, 'FS_MUL': 2, 'FS_FMA': 3, 'FS_DIV': 4,
        })

    def test_fscalar_subop_imm16_roundtrip(self):
        """All five FS_* sub-ops, by name AND by code: nibble lands at
        imm16[7:4], [3:0] stays reserved-zero. FS_ADD encodes to imm16 ==
        0x0000, matching the documented absent-imm16 default (an FSCALAR
        with NO imm16 EH decodes as FS_ADD)."""
        from generated_isa_tables import FSCALAR_OP_CODE
        for name, code in FSCALAR_OP_CODE.items():
            for subop in (name, code):
                imm16 = wta.fscalar_subop_imm16(subop)
                self.assertEqual((imm16 >> 4) & 0xF, code, subop)
                self.assertEqual(imm16 & 0xF, 0, "reserved [3:0] must be 0")
                self.assertEqual(imm16 & ~0xFF, 0)
        # absent imm16 == sub-op 0x0 == FS_ADD: pinned via the table.
        self.assertEqual(wta.fscalar_subop_imm16('FS_ADD'), 0x0000)

    def test_fscalar_subop_imm16_rejects_unknown(self):
        """Unknown names/codes are rejected — incl. a pre-shifted imm16
        (0x20) passed where a sub-op code belongs, and namespace strays
        from the ACC_REDUCE table."""
        for bad in ('FS_MIN', 'sum', 'fs_add', 5, 0xF, -1, 0x20, 1.0, None):
            with self.assertRaises(wta.AssemblerError, msg=repr(bad)):
                wta.fscalar_subop_imm16(bad)

    def test_fscalar_imm16_now_legal(self):
        """v1.8.0c loosening: imm16 forbidden -> optional on 0x74. Each
        sub-op assembles through the generic emit path with the helper-
        built imm16, F_HAS_OPB set in the flags nibble."""
        from generated_isa_tables import FSCALAR_OP_CODE, FLAG_BITS
        for name in FSCALAR_OP_CODE:
            imm16 = wta.fscalar_subop_imm16(name)
            src = (f".default_port dest=0x01\n"
                   f"FSCALAR opb prec .imm16 {imm16} "
                   f".precision mode={self._MODE_F32}\n")
            inst = wta.assemble_one(src)
            self.assertEqual((inst >> 24) & 0xFF, 0x74, name)
            flags_nibble = (inst >> 16) & 0xF
            self.assertTrue(flags_nibble & (1 << FLAG_BITS['opb']),
                            "F_HAS_OPB must be set")

    def test_fscalar_absent_imm16_assembles(self):
        """No imm16 EH at all is legal and documents FS_ADD (sub-op 0x0)."""
        src = (f".default_port dest=0x01\n"
               f"FSCALAR opb prec .precision mode={self._MODE_F32}\n")
        inst = wta.assemble_one(src)
        self.assertEqual((inst >> 24) & 0xFF, 0x74)

    def test_fscalar_requires_opb_flag(self):
        """§23.10.2: F_HAS_OPB is required for EVERY sub-op — B arrives on
        input_payload_b; missing B is a dispatch-side error_flag in RTL,
        so the assembler rejects it textually up front."""
        src = (f".default_port dest=0x01\n"
               f"FSCALAR prec .precision mode={self._MODE_F32}\n")
        with self.assertRaises(wta.AssemblerError) as ctx:
            wta.assemble(src)
        self.assertIn('opb', str(ctx.exception))

    def test_fscalar_reserved_low_nibble_rejected(self):
        """imm16[3:0] != 0 (RTL: lower_required) is an assembly-time error."""
        src = (f".default_port dest=0x01\n"
               f"FSCALAR opb prec .imm16 0x21 "
               f".precision mode={self._MODE_F32}\n")
        with self.assertRaises(wta.AssemblerError) as ctx:
            wta.assemble(src)
        self.assertIn('reserved', str(ctx.exception))

    def test_fscalar_unknown_subop_nibble_rejected(self):
        """Sub-op nibbles 0x5..0xF (RTL: lower_required) are assembly-time
        errors."""
        for nibble in (0x5, 0x9, 0xF):
            src = (f".default_port dest=0x01\n"
                   f"FSCALAR opb prec .imm16 {nibble << 4} "
                   f".precision mode={self._MODE_F32}\n")
            with self.assertRaises(wta.AssemblerError, msg=hex(nibble)):
                wta.assemble(src)

    def _data_eh_reject_check(self, mnemonic, kinds):
        """AST-level: each data EH kind alone must fail legality_pass."""
        for kind in kinds:
            inst = wta.Instruction(
                mnemonic=mnemonic, flags={'opb', 'prec'},
                eh_list=[
                    wta.ExtensionHeader('port', {'dest': 1}, 1),
                    wta.ExtensionHeader('precision',
                                        {'mode': self._MODE_F32}, 1),
                    wta.ExtensionHeader(kind, {'_pos': [0]}, 1),
                ], line=1)
            with self.assertRaises(wta.AssemblerError,
                                   msg=f"{mnemonic} .{kind}"):
                wta.legality_pass(wta.Program(stmts=[inst]))

    def test_fscalar_imm32_imm64_stay_asm_forbidden(self):
        """Pin the JSON forbidden list: imm32/imm64 stay ASM-FORBIDDEN on
        0x74 (RTL-tolerated per §23.10.2 — 0x72 forbid_imm_any semantics
        verbatim), and mem/opref/subscript stay forbidden too."""
        self.assertEqual(
            wta._LEGAL[0x74]['forbidden'],
            {'imm32', 'imm64', 'mem', 'opref', 'subscript'})
        self._data_eh_reject_check(
            'FSCALAR', ('imm32', 'imm64', 'mem', 'opref', 'subscript'))

    def test_frsqrt32_fexp2_32_strictly_port_only(self):
        """0x75/0x76: generic emit path assembles them (decode-legal since
        v1.8.0a — no bespoke encoder, matching sibling unary ops like
        SCALAR_RSQRT), and EVERY data EH is rejected."""
        for mnem, code in (('FRSQRT32', 0x75), ('FEXP2_32', 0x76)):
            src = (f".default_port dest=0x01\n"
                   f"{mnem} prec .precision mode={self._MODE_F32}\n")
            inst = wta.assemble_one(src)
            self.assertEqual((inst >> 24) & 0xFF, code, mnem)
            self.assertEqual(
                wta._LEGAL[code]['forbidden'], wta._ALL_DATA_EHS, mnem)

    # -------------------------------------------------------------------
    # v1.8.0d §23.10.10 — CVT (0x77) / ACC_ELEMWISE (0x73)
    # -------------------------------------------------------------------

    def test_cvt_op_code_table_pin(self):
        """Literal pin of the generated cvt_op_codes table (single source
        isa/wt64v1_isa.json)."""
        from generated_isa_tables import CVT_OP_CODE
        self.assertEqual(CVT_OP_CODE,
                         {'WIDEN_TO_F32': 0, 'NARROW_FROM_F32': 1})

    def test_cvt_subop_imm16_roundtrip(self):
        """Both CVT sub-ops, by name AND by code: nibble at imm16[7:4],
        [3:0] and [15:8] reserved-zero. WIDEN_TO_F32 encodes to 0x0000,
        matching the documented absent-imm16 default."""
        from generated_isa_tables import CVT_OP_CODE
        for name, code in CVT_OP_CODE.items():
            for subop in (name, code):
                imm16 = wta.cvt_subop_imm16(subop)
                self.assertEqual((imm16 >> 4) & 0xF, code, subop)
                self.assertEqual(imm16 & 0xF, 0)
                self.assertEqual(imm16 & 0xFF00, 0)
        self.assertEqual(wta.cvt_subop_imm16('WIDEN_TO_F32'), 0x0000)

    def test_cvt_subop_imm16_rejects_unknown(self):
        for bad in ('FS_ADD', 'widen', 2, 0xF, -1, 0x10, 1.0, None):
            with self.assertRaises(wta.AssemblerError, msg=repr(bad)):
                wta.cvt_subop_imm16(bad)

    def test_cvt_assembles_all_legal_dtypes(self):
        """0x77 assembles through the generic emit path for every legal
        dtype x both sub-ops (absent imm16 = WIDEN default too); the mode
        byte must carry the dtype nibble."""
        from generated_isa_tables import CVT_OP_CODE, FP_MODE_LEGAL
        for dtype in FP_MODE_LEGAL[0x77]['legal_dtypes']:
            mode = 0x10 | dtype
            for name in CVT_OP_CODE:
                imm16 = wta.cvt_subop_imm16(name)
                src = (f".default_port dest=0x01\n"
                       f"CVT prec .imm16 {imm16} .precision mode={mode}\n")
                inst = wta.assemble_one(src)
                self.assertEqual((inst >> 24) & 0xFF, 0x77, (dtype, name))
            src = (f".default_port dest=0x01\n"
                   f"CVT prec .precision mode={mode}\n")
            self.assertEqual((wta.assemble_one(src) >> 24) & 0xFF, 0x77)

    def test_cvt_reserved_imm16_fields_rejected(self):
        """imm16[3:0] or [15:8] nonzero and unknown sub-op nibbles (RTL:
        lower_required) are assembly-time errors."""
        for imm in (0x0001, 0x0100, 0x8000, 0x0011):
            src = (f".default_port dest=0x01\n"
                   f"CVT prec .imm16 {imm} "
                   f".precision mode={self._MODE_F32}\n")
            with self.assertRaises(wta.AssemblerError, msg=hex(imm)):
                wta.assemble(src)
        for nib in (0x2, 0x9, 0xF):
            src = (f".default_port dest=0x01\n"
                   f"CVT prec .imm16 {nib << 4} "
                   f".precision mode={self._MODE_F32}\n")
            with self.assertRaises(wta.AssemblerError, msg=hex(nib)):
                wta.assemble(src)

    def test_cvt_imm32_imm64_opref_stay_asm_forbidden(self):
        """Pin the JSON forbidden list on 0x77: imm32/imm64 asm-forbidden
        (RTL-tolerated, FSCALAR semantics — CVT never reads eff_b_value),
        opref/mem/subscript forbidden outright."""
        self.assertEqual(
            wta._LEGAL[0x77]['forbidden'],
            {'imm32', 'imm64', 'mem', 'opref', 'subscript'})
        self._data_eh_reject_check(
            'CVT', ('imm32', 'imm64', 'mem', 'opref', 'subscript'))

    def test_acc_elemwise_opref_form_assembles(self):
        """0x73 OPREF form (the only implemented form, §23.10.10(c))
        assembles; dtype row is [4] so mode 0x14."""
        src = (f".default_port dest=0x01\n"
               f"ACC_ELEMWISE opb prec .opref "
               f".precision mode={self._MODE_F32}\n")
        inst = wta.assemble_one(src)
        self.assertEqual((inst >> 24) & 0xFF, 0x73)

    def test_acc_elemwise_imm_forms_asm_rejected(self):
        """v1.8.0d asm-stricter-than-RTL: every imm form on 0x73 would be
        an execute-side lower_required dead-end (OPREF-only capability),
        so the assembler rejects it textually. Neither-imm-nor-opref is
        already the generic XOR error."""
        for imm_directive in ('.imm16 16', '.imm32 5', '.imm64 5'):
            src = (f".default_port dest=0x01\n"
                   f"ACC_ELEMWISE opb prec {imm_directive} "
                   f".precision mode={self._MODE_F32}\n")
            with self.assertRaises(wta.AssemblerError,
                                   msg=imm_directive) as ctx:
                wta.assemble(src)
            self.assertIn('OPREF-form only', str(ctx.exception))
        src = (f".default_port dest=0x01\n"
               f"ACC_ELEMWISE opb prec "
               f".precision mode={self._MODE_F32}\n")
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(src)
            self._data_eh_reject_check(
                mnem, ('imm16', 'imm32', 'imm64', 'mem', 'opref',
                       'subscript'))

    def test_pack_fscalar_payload_layout(self):
        """A at [31:0], C at [63:32]; C defaults to zero-fill (reserved
        for every non-FMA sub-op — hardware ignores [63:32] there)."""
        self.assertEqual(wta.pack_fscalar_payload(0x3F800000),
                         0x0000_0000_3F80_0000)
        self.assertEqual(
            wta.pack_fscalar_payload(0x40490FDB, c_fp32_bits=0xC0000000),
            0xC000_0000_4049_0FDB)

    def test_pack_fscalar_payload_bits_pass_through_untouched(self):
        """The assembler never interprets fp bits: negative zero and an
        sNaN pattern (quiet bit clear, nonzero payload) survive
        bit-exactly — no host-FPU round trip is involved."""
        neg_zero = 0x80000000
        snan = 0x7FA00001          # exp all-ones, MSB of mantissa clear
        self.assertEqual(wta.pack_fscalar_payload(neg_zero), neg_zero)
        self.assertEqual(wta.pack_fscalar_payload(snan, c_fp32_bits=snan),
                         (snan << 32) | snan)
        self.assertEqual(wta.pack_fscalar_payload(0, c_fp32_bits=neg_zero),
                         neg_zero << 32)

    def test_pack_fscalar_payload_rejects_non_bit_patterns(self):
        """Out-of-range ints and floats are rejected — inputs are raw
        binary32 bit patterns, not values (use fp32_to_bits first)."""
        for bad_a in (-1, 1 << 32, 1.0, None, True):
            with self.assertRaises(wta.AssemblerError, msg=repr(bad_a)):
                wta.pack_fscalar_payload(bad_a)
        with self.assertRaises(wta.AssemblerError):
            wta.pack_fscalar_payload(0, c_fp32_bits=1 << 32)

    def test_fp32_bit_conversion_utilities(self):
        """fp32_to_bits / bits_to_fp32: exact on canonical anchors incl.
        the sign of negative zero; asm stays self-contained (no import
        from scripts/)."""
        import math
        self.assertEqual(wta.fp32_to_bits(1.0), 0x3F800000)
        self.assertEqual(wta.fp32_to_bits(-2.0), 0xC0000000)
        self.assertEqual(wta.fp32_to_bits(0.0), 0x00000000)
        self.assertEqual(wta.fp32_to_bits(-0.0), 0x80000000)
        self.assertEqual(wta.fp32_to_bits(float('inf')), 0x7F800000)
        self.assertEqual(wta.bits_to_fp32(0x3F800000), 1.0)
        neg0 = wta.bits_to_fp32(0x80000000)
        self.assertEqual(neg0, 0.0)
        self.assertEqual(math.copysign(1.0, neg0), -1.0)
        # binary32 -> double is exact, so bits -> float -> bits round-trips
        # for every non-NaN pattern; spot-check across binades.
        for bits in (0x00000001, 0x00800000, 0x3DCCCCCD, 0x40490FDB,
                     0x7F7FFFFF, 0xFF800000):
            self.assertEqual(wta.fp32_to_bits(wta.bits_to_fp32(bits)), bits,
                             hex(bits))
        with self.assertRaises(wta.AssemblerError):
            wta.bits_to_fp32(1 << 32)
        with self.assertRaises(wta.AssemblerError):
            wta.bits_to_fp32(-1)


class TestV180e0e1Encoding(unittest.TestCase):
    """v1.8.0e 0e1 — 0x79 FMINMAX / 0x78 DEQUANT / 0x6B GAMMA_MUL_W
    assembler-side encoders and legality (spec sections 25.2.1-25.2.3):
    the fminmax_subop_imm16 helper, the hardcoded opb requirements (B /
    the fp32 scale ride input_payload_b), the 0x79 imm16 reserved-field
    checks, the 0x78 port-only legality and the 0x6B imm64-XOR-opref +
    hand-pinned mode-byte legality (0x06B sits outside the 0x070-0x07F
    in_fp_block gate, so it has no generated FP_MODE_LEGAL row)."""

    def test_fminmax_subop_imm16_helper(self):
        self.assertEqual(wta.fminmax_subop_imm16('MINIMUMNUM'), 0x00)
        self.assertEqual(wta.fminmax_subop_imm16('MAXIMUMNUM'), 0x10)
        self.assertEqual(wta.fminmax_subop_imm16(0), 0x00)
        self.assertEqual(wta.fminmax_subop_imm16(1), 0x10)
        for bad in ('MIN', 'FS_ADD', 2, 0x10, True, None):
            with self.assertRaises(wta.AssemblerError, msg=repr(bad)):
                wta.fminmax_subop_imm16(bad)

    def test_fminmax_legality(self):
        """0x79 is the FSCALAR legality clone: 'opb' required (B on
        payload_b ONLY), imm16 optional as CONTROL (reserved fields
        zero, sub-op from the generated table), imm32/imm64/opref
        forbidden."""
        ok = (".default_port dest=0x01\n"
              "FMINMAX opb prec .precision mode=0x14 .imm16 %d\n"
              % wta.fminmax_subop_imm16('MAXIMUMNUM'))
        wta.assemble(ok)   # must not raise
        # absent imm16 = MINIMUMNUM default — also legal
        wta.assemble(".default_port dest=0x01\n"
                     "FMINMAX opb prec .precision mode=0x14\n")
        # missing opb -> textual error
        with self.assertRaises(wta.AssemblerError) as ctx:
            wta.assemble(".default_port dest=0x01\n"
                         "FMINMAX prec .precision mode=0x14\n")
        self.assertIn('opb', str(ctx.exception))
        # reserved-zero fields
        for bad_imm in (0x0001, 0x0100, 0x0011):
            with self.assertRaises(wta.AssemblerError, msg=hex(bad_imm)):
                wta.assemble(".default_port dest=0x01\n"
                             "FMINMAX opb prec .precision mode=0x14 "
                             ".imm16 %d\n" % bad_imm)
        # unknown sub-op nibble (2..15)
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(".default_port dest=0x01\n"
                         "FMINMAX opb prec .precision mode=0x14 "
                         ".imm16 0x20\n")
        # opref-B is a recorded post-0e loosening — forbidden today
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(".default_port dest=0x01\n"
                         "FMINMAX opb prec .precision mode=0x14 .opref\n")
        # only mode 0x14 (f32/acc=1/rnd=0) is ROM-legal
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(".default_port dest=0x01\n"
                         "FMINMAX opb prec .precision mode=0x10\n")

    def test_dequant_legality(self):
        """0x78 port-only legality UNCHANGED (forbid_imm_any +
        forbid_opref stand); 'opb' hardcoded-required (the fp32 scale
        rides ext_payload_b on the wave-completing beat — the pinned
        SDK/NoC scale-beat contract); source dtypes int4/int8 only."""
        for mode in (0x10, 0x11):
            wta.assemble(".default_port dest=0x01\n"
                         "DEQUANT opb prec .precision mode=0x%02X\n" % mode)
        with self.assertRaises(wta.AssemblerError) as ctx:
            wta.assemble(".default_port dest=0x01\n"
                         "DEQUANT prec .precision mode=0x11\n")
        self.assertIn('opb', str(ctx.exception))
        for bad_eh in ('.imm16 1', '.imm32 1', '.imm64 1', '.opref'):
            with self.assertRaises(wta.AssemblerError, msg=bad_eh):
                wta.assemble(".default_port dest=0x01\n"
                             "DEQUANT opb prec .precision mode=0x11 "
                             "%s\n" % bad_eh)
        # dest-dtype carriers do not exist in 0e: f16/bf16/f32 source
        # nibbles are mode-ROM-illegal
        for bad_mode in (0x12, 0x13, 0x14):
            with self.assertRaises(wta.AssemblerError, msg=hex(bad_mode)):
                wta.assemble(".default_port dest=0x01\n"
                             "DEQUANT opb prec .precision mode=0x%02X\n"
                             % bad_mode)

    def test_gamma_mul_w_legality(self):
        """0x6B: gamma via IMM64 XOR OPREF (alu-binary — both/neither
        rejected); precision EH required with the hand-pinned mode 0x10
        (int4/acc=1/rnd=0 — no generated FP_MODE_LEGAL row since 0x6B is
        outside the in_fp_block gate; the asm check must NOT KeyError)."""
        wta.assemble(".default_port dest=0x01\n"
                     "GAMMA_MUL_W prec .precision mode=0x10 "
                     ".imm64 0x123456789ABCDEF0\n")
        wta.assemble(".default_port dest=0x01\n"
                     "GAMMA_MUL_W prec .precision mode=0x10 .opref\n")
        # XOR violations: neither / both
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(".default_port dest=0x01\n"
                         "GAMMA_MUL_W prec .precision mode=0x10\n")
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(".default_port dest=0x01\n"
                         "GAMMA_MUL_W prec .precision mode=0x10 "
                         ".imm64 1 .opref\n")
        # mode-byte pins: dtype must be int4, acc=1, rnd=0
        for bad_mode in (0x11, 0x14, 0x00, 0x50):
            with self.assertRaises(wta.AssemblerError, msg=hex(bad_mode)):
                wta.assemble(".default_port dest=0x01\n"
                             "GAMMA_MUL_W prec .precision mode=0x%02X "
                             ".imm64 1\n" % bad_mode)
        # precision EH + prec flag are required (asm row)
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(".default_port dest=0x01\n"
                         "GAMMA_MUL_W .imm64 1\n")

    def test_v180e_encoding_roundtrip(self):
        """Encoder roundtrip vs the mirror decoder: the three new-op
        encodings carry the expected opcode byte, flags nibble and EH
        chain kinds."""
        insts = wta.assemble(
            ".default_port dest=0x01\n"
            "GAMMA_MUL_W prec .precision mode=0x10 .imm64 0xAB\n"
            "DEQUANT opb prec .precision mode=0x11\n"
            "FMINMAX opb prec .precision mode=0x14 .imm16 0x10\n")
        ops = [(w >> 24) & 0xFF for w in insts]
        self.assertEqual(ops, [0x6B, 0x78, 0x79])
        # flags nibble at [19:16]: prec = F_PRECISION_OVR bit 2,
        # opb = F_HAS_OPB bit 3
        self.assertEqual((insts[0] >> 16) & 0xF, 0b0100)
        self.assertEqual((insts[1] >> 16) & 0xF, 0b1100)
        self.assertEqual((insts[2] >> 16) & 0xF, 0b1100)


class TestV180e0e2Vfma(unittest.TestCase):
    """v1.8.0e 0e2 — 0x70 VFMA_ACC assembler-side encoder + legality
    (spec section 25.2.4): the pack_vfma_b B-split helper, the LOUD
    b_mul lane-width lint (no silent truncation), the IMM-XOR-OPREF
    alu-binary legality and the ROM mode-byte pins (dtype {int4, int8},
    acc=1 wide-acc OUTPUT form marker, rnd=0)."""

    def test_pack_vfma_b_layout(self):
        """B split pin: c_acc at B[63:32], b_mul's RAW lane-width field
        at the low bits, NOTHING between (the RTL sign-extends from the
        field, so negative b_mul carries no sign bits above it)."""
        self.assertEqual(wta.pack_vfma_b(1), 0x1)
        self.assertEqual(wta.pack_vfma_b(7, 0, 0x0), 0x7)
        self.assertEqual(wta.pack_vfma_b(-1, 0, 0x0), 0xF)      # sext field
        self.assertEqual(wta.pack_vfma_b(-8, 0, 0x0), 0x8)
        self.assertEqual(wta.pack_vfma_b(-1, 0, 0x1), 0xFF)
        self.assertEqual(wta.pack_vfma_b(-128, 0, 0x1), 0x80)
        self.assertEqual(wta.pack_vfma_b(127, 0, 0x1), 0x7F)
        # c_acc: signed and raw forms, incl. the wrap-boundary cells
        self.assertEqual(wta.pack_vfma_b(1, -1, 0x0),
                         0xFFFFFFFF_00000001)
        self.assertEqual(wta.pack_vfma_b(1, 0x7FFFFFFF, 0x0),
                         0x7FFFFFFF_00000001)
        self.assertEqual(wta.pack_vfma_b(1, -(1 << 31), 0x0),
                         0x80000000_00000001)
        self.assertEqual(wta.pack_vfma_b(1, 0x80000000, 0x0),
                         0x80000000_00000001)   # raw == signed alias

    def test_pack_vfma_b_range_rejects(self):
        """LOUD rejects: b_mul outside the lane width, bad dtype, c_acc
        outside int32/raw-32 — never a silent mask."""
        for bad in (8, -9, 0x10, 128, True, None, 1.5):
            with self.assertRaises(wta.AssemblerError, msg=repr(bad)):
                wta.pack_vfma_b(bad, 0, 0x0)
        for bad in (128, -129, 0x100):
            with self.assertRaises(wta.AssemblerError, msg=repr(bad)):
                wta.pack_vfma_b(bad, 0, 0x1)
        with self.assertRaises(wta.AssemblerError):
            wta.pack_vfma_b(1, 1 << 32, 0x0)
        with self.assertRaises(wta.AssemblerError):
            wta.pack_vfma_b(1, -(1 << 31) - 1, 0x0)
        with self.assertRaises(wta.AssemblerError):
            wta.pack_vfma_b(1, 0, 0x4)

    def test_vfma_legality(self):
        """0x70 alu-binary legality: B via exactly one of {.imm*,
        .opref}; precision EH + prec flag required (fp block); ROM
        modes 0x10/0x11 only (acc=1 is the wide-acc OUTPUT-form marker
        — acc=0 modes are decode_error, the corrected polarity)."""
        for mode in (0x10, 0x11):
            wta.assemble(".default_port dest=0x01\n"
                         "VFMA_ACC prec .precision mode=0x%02X "
                         ".imm64 %d\n"
                         % (mode, wta.pack_vfma_b(1, 5, mode & 0xF)))
        wta.assemble(".default_port dest=0x01\n"
                     "VFMA_ACC prec .precision mode=0x10 .opref\n")
        # XOR violations: neither / both
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(".default_port dest=0x01\n"
                         "VFMA_ACC prec .precision mode=0x10\n")
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(".default_port dest=0x01\n"
                         "VFMA_ACC prec .precision mode=0x10 "
                         ".imm64 1 .opref\n")
        # mode-byte ROM pins: acc=0 forms, fp/f32 dtypes, rnd!=0 all
        # reject (dtype {0,1} x acc=1 x rnd=0 is the whole legal set)
        for bad_mode in (0x00, 0x01, 0x14, 0x12, 0x50, 0x20):
            with self.assertRaises(wta.AssemblerError, msg=hex(bad_mode)):
                wta.assemble(".default_port dest=0x01\n"
                             "VFMA_ACC prec .precision mode=0x%02X "
                             ".imm16 1\n" % bad_mode)
        # precision EH + prec flag are required (fp-block asm row)
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(".default_port dest=0x01\n"
                         "VFMA_ACC .imm16 1\n")

    def test_vfma_b_mul_range_lint(self):
        """The §25.2.4 asm-lint pin: imm encodings with nonzero LOW-WORD
        bits above the lane width are LOUDLY rejected (the RTL reads
        only B[3:0]/B[7:0] — silent truncation forbidden); the c_acc
        word B[63:32] is free."""
        # int4: B[3:0] legal, bit 4 and up loud
        wta.assemble(".default_port dest=0x01\n"
                     "VFMA_ACC prec .precision mode=0x10 .imm16 0xF\n")
        for bad in ("imm16 0x10", "imm16 0xFF", "imm32 0x100",
                    "imm64 0x10"):
            with self.assertRaises(wta.AssemblerError, msg=bad) as ctx:
                wta.assemble(".default_port dest=0x01\n"
                             "VFMA_ACC prec .precision mode=0x10 "
                             ".%s\n" % bad)
            self.assertIn('lane width', str(ctx.exception))
        # int8: B[7:0] legal, bit 8 and up loud
        wta.assemble(".default_port dest=0x01\n"
                     "VFMA_ACC prec .precision mode=0x11 .imm16 0xFF\n")
        for bad in ("imm16 0x100", "imm32 0x8000", "imm64 0x100"):
            with self.assertRaises(wta.AssemblerError, msg=bad):
                wta.assemble(".default_port dest=0x01\n"
                             "VFMA_ACC prec .precision mode=0x11 "
                             ".%s\n" % bad)
        # c_acc rides B[63:32] untouched — a full-scale imm64 upper word
        # with an in-range b_mul field is legal at both dtypes
        wta.assemble(".default_port dest=0x01\n"
                     "VFMA_ACC prec .precision mode=0x10 .imm64 %d\n"
                     % wta.pack_vfma_b(-8, 0xFFFFFFFF, 0x0))
        wta.assemble(".default_port dest=0x01\n"
                     "VFMA_ACC prec .precision mode=0x11 .imm64 %d\n"
                     % wta.pack_vfma_b(-128, -(1 << 31), 0x1))

    def test_vfma_encoding_roundtrip(self):
        """Encoder roundtrip: opcode byte 0x70, prec-only flags nibble
        (B is an immediate, NOT payload_b — no opb), and the .imm64
        body words carry the pack_vfma_b split {lo32 = b_mul field,
        hi32 = c_acc} verbatim as consecutive 32-bit words."""
        b64 = wta.pack_vfma_b(-3, 0x8000_0001, 0x0)
        insts = wta.assemble(
            ".default_port dest=0x01\n"
            "VFMA_ACC prec .precision mode=0x10 .imm64 %d\n"
            "VFMA_ACC prec .precision mode=0x11 .imm16 0x7F\n" % b64)
        ops = [(w >> 24) & 0xFF for w in insts]
        self.assertEqual(ops, [0x70, 0x70])
        self.assertEqual((insts[0] >> 16) & 0xF, 0b0100)   # prec only
        self.assertEqual((insts[1] >> 16) & 0xF, 0b0100)
        # the imm64 EH body {lo32, hi32} rides verbatim (b_mul raw
        # field 0xD = -3 sext source, c_acc pattern untouched)
        words = [(insts[0] >> (32 * i)) & 0xFFFFFFFF for i in range(14)]
        lo, hi = b64 & 0xFFFFFFFF, b64 >> 32
        self.assertEqual((lo, hi), (0x0000000D, 0x80000001))
        self.assertIn((lo, hi), list(zip(words, words[1:])),
                      f"imm64 body words not found: {words}")
        # the imm16 form's EH body carries the raw 0x7F field at the
        # imm16 body position (upper 16 bits of its EH word)
        words1 = [(insts[1] >> (32 * i)) & 0xFFFFFFFF for i in range(14)]
        self.assertTrue(any((w >> 16) == 0x007F and ((w >> 8) & 0xF) == 0x2
                            for w in words1),
                        f"imm16 body word not found: {words1}")


class TestFdot32CrIsa3aC2(unittest.TestCase):
    """v1.8.0e 3a-C2 — FDOT32_CR (0x7A) ISA row, spec §27.7a.

    C2 lands the ISA row + generated artifacts + assembler support ONLY;
    the RTL step program (3a-C3) and the PE_Core/EHDecode wiring +
    opcode_supported entry (3a-C4) follow. The row is therefore
    DECODE-RESERVED here: assembling 0x7A is legal, executing it still
    decode_errors on silicon — the spec-pinned staging state.

    Everything below is restrictive-first: exactly 2 legal mode rows
    ((dtype 0x2 f16 | 0x3 bf16) x acc 1 x rnd 0) and a port-only EH
    shape (forbid_imm_any + forbid_opref, the 0x78 DEQUANT precedent),
    with EVERY other combination LOUDLY rejected.
    """

    _SRC = ".default_port dest=0x01\n"
    _LEGAL_MODES = (0x12, 0x13)          # f16 / bf16, acc=1, rnd=0

    # ---- mode-byte legality (§27.7a.1 — the §23.6a 2-row transcription)

    def test_legal_rows_assemble(self):
        """The EXACT 2 legal rows assemble: (0x7A, dtype 0x2 f16, acc 1,
        rnd 0) and (0x7A, dtype 0x3 bf16, acc 1, rnd 0)."""
        for mode in self._LEGAL_MODES:
            insts = wta.assemble(self._SRC + "FDOT32_CR prec .precision "
                                 "mode=0x%02X\n" % mode)
            self.assertEqual(len(insts), 1)
            self.assertEqual((insts[0] >> 24) & 0xFF, 0x7A)

    def test_all_other_mode_bytes_rejected_exhaustive(self):
        """restrictive-first, PROVEN by enumeration: all 256 mode bytes
        are swept and exactly the 2 legal rows survive. This nails the
        whole illegal family in one place — dtype 0x0/0x1 (int4/int8),
        0x4 (f32), 0x5 (f64/Lf-reserved), 0x6/0x7 (q4_4/q8_8), dtype > 0x7,
        acc != 1 and rnd != 0."""
        accepted = []
        for mode in range(256):
            src = self._SRC + "FDOT32_CR prec .precision mode=%d\n" % mode
            try:
                wta.assemble(src)
                accepted.append(mode)
            except wta.AssemblerError:
                pass
        self.assertEqual(accepted, list(self._LEGAL_MODES),
                         f"restrictive-first violated: accepted {accepted}")

    def test_illegal_family_messages_are_loud(self):
        """Spot-check the named illegal axes individually so a future
        regression names the axis it broke, not just a count: dtype
        0x0/0x1 (the conversion-dtype rule does NOT apply — dtype names
        the WAVE dtype), acc=0, rnd != 0."""
        cases = {
            0x10: 'dtype 0x0 int4',
            0x11: 'dtype 0x1 int8',
            0x14: 'dtype 0x4 f32',
            0x15: 'dtype 0x5 f64/Lf-reserved',
            0x02: 'acc=0 with f16',
            0x03: 'acc=0 with bf16',
            0x52: 'rnd=1 (SR) with f16',
            0x93: 'rnd=2 with bf16',
            0xD3: 'rnd=3 with bf16',
            0x22: 'acc=2 with f16',
        }
        for mode, why in cases.items():
            with self.assertRaises(wta.AssemblerError, msg=why) as ctx:
                wta.assemble(self._SRC + "FDOT32_CR prec .precision "
                             "mode=0x%02X\n" % mode)
            self.assertIn('illegal', str(ctx.exception).lower(), why)

    def test_precision_eh_and_prec_flag_required(self):
        """fp-block row: the mode byte must be assembly-visible."""
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(self._SRC + "FDOT32_CR\n")
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(self._SRC + "FDOT32_CR .precision mode=0x13\n")
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(self._SRC + "FDOT32_CR prec\n")

    # ---- EH shape (§27.7a.1 — port-only, the 0x78 precedent) -----------

    def test_port_only_shape_rejects_every_data_eh(self):
        """EH shape = port-only: forbid_imm_any + forbid_opref (0x78
        DEQUANT clone). No sub-op nibble exists, and B rides the wide
        wave rather than payload_b, so there is no imm/opref channel to
        misuse — every data EH is LOUDLY rejected."""
        for extra in (".imm16 1", ".imm32 1", ".imm64 1", ".opref",
                      ".mem offset=0", ".subscript A=i,j B=j,k O=i,k"):
            with self.assertRaises(wta.AssemblerError, msg=extra):
                wta.assemble(self._SRC + "FDOT32_CR prec .precision "
                             "mode=0x13 %s\n" % extra)

    def test_port_eh_required(self):
        """required=['port'] — no .default_port, no .port EH, no deal."""
        with self.assertRaises(wta.AssemblerError):
            wta.assemble("FDOT32_CR prec .precision mode=0x13\n")

    def test_legality_row_shape_is_the_0x78_clone(self):
        """The generated legality row IS the 0x78 DEQUANT shape (the
        spec's named precedent), minus DEQUANT's payload_b requirement."""
        self.assertEqual(wta._LEGAL[0x7A]['required'],
                         wta._LEGAL[0x78]['required'])
        self.assertEqual(wta._LEGAL[0x7A]['forbidden'],
                         wta._LEGAL[0x78]['forbidden'])
        self.assertFalse(wta._LEGAL[0x7A]['allow_imm_xor_opref'])
        self.assertFalse(wta._LEGAL[0x7A]['require_imm16'])
        self.assertTrue(wta._LEGAL[0x7A]['require_precision_eh'])
        # port-only means EVERY data EH is out — the forbidden set is the
        # complete data-EH catalogue, same as 0x7E FP_ACC_CTRL.
        self.assertEqual(wta._LEGAL[0x7A]['forbidden'], wta._ALL_DATA_EHS)

    def test_rtl_legality_row_is_the_0x78_clone(self):
        """The rtl_legality half must ALSO be the 0x78 clone.

        While 0x7A is `decode_reserved` (until 3a-C4) the `!supported`
        term dominates decode_error, so these flags are invisible to the
        RTL sweeps — a silent drift here would only surface the moment
        C4 clears the whitelist bit and they become load-bearing.  This
        literal pin is the net for that window (adversarial-audit
        finding, 3a-C2)."""
        import importlib.util as _ilu
        import json as _json
        _spec = _ilu.spec_from_file_location(
            "gen_isa_tables",
            os.path.join(os.path.dirname(_HERE), "scripts", "gen_isa_tables.py"))
        _gen = _ilu.module_from_spec(_spec)
        _spec.loader.exec_module(_gen)
        with open(_gen.SOURCE, encoding='utf-8') as fh:
            rows = {o['code']: o for o in _json.load(fh)['opcodes']}
        self.assertEqual(rows[0x7A]['rtl_legality'], rows[0x78]['rtl_legality'])
        # spell the port-only contract out so the pin survives a 0x78 edit
        self.assertEqual(
            {k: v for k, v in rows[0x7A]['rtl_legality'].items() if v},
            {'req_port': True, 'forbid_subscript': True, 'forbid_mem': True,
             'forbid_imm_any': True, 'forbid_opref': True})

    # ---- encode / disassemble roundtrip --------------------------------

    def test_encoding_roundtrip(self):
        """assemble -> disassemble: opcode byte 0x7A, prec-ONLY flags
        nibble (no F_HAS_OPB — FDOT32_CR reads no payload_b), EH chain
        exactly [PORT, PRECISION], and bit-identical to the reference
        encoder."""
        for mode in self._LEGAL_MODES:
            got = wta.assemble_one(self._SRC + "FDOT32_CR prec .precision "
                                   "mode=0x%02X\n" % mode)
            expected = ref.encode_instr(0x7A, ref.eh_port(0x01, 0),
                                        ref.eh_precision(mode),
                                        flags=ref.F_PRECISION_OVR)
            self.assertEqual(got, expected,
                             f"\nasm:      0x{got:0112x}"
                             f"\nexpected: 0x{expected:0112x}")
            m = ref.decode_mirror(got)
            self.assertEqual(m['opcode'], 0x7A)
            self.assertEqual(m['flags'], 0b0100)          # prec only
            self.assertEqual([eh['type'] for eh in m['ehs']],
                             [EH_PORT, EH_PRECISION])
            self.assertNotIn('chain_break_at', m)
            # W8: bh_len = 기본 헤더 + CH + PORT + PRECISION, CH 재계산 대조
            self.assertEqual(m['bh_len'], 1 + 1 + 1 + 1)
            self.assertTrue(m['ch_ok'], "CH(word 1) 재계산 대조 실패")
            # the mode byte survives the roundtrip in the PRECISION body
            self.assertEqual((m['ehs'][1]['words'][0] >> 16) & 0xFF, mode)

    # ---- operand wave (§27.7a.1 — A||B, FRAG_MAX = 16 exactly) ---------

    def test_operand_wave_is_exactly_16_fragments(self):
        """A||B concatenated SINGLE wave: 1,024 bit = 16 fragments,
        frag_hdr tot_m1 = 15 uniformly and indices 0..15 — FRAG_MAX = 16
        EXACTLY consumed (the first 16-fragment INPUT wave)."""
        a = [(0x3C00 + i) & 0xFFFF for i in range(32)]
        b = [(0xBC00 + i) & 0xFFFF for i in range(32)]
        frags = wta.wave_fragments_fdot32_cr(a, b)
        self.assertEqual(len(frags), 16)
        self.assertTrue(all((h & 0x0F) == 0x0F for _, h in frags))
        self.assertEqual([h >> 4 for _, h in frags], list(range(16)))

    def test_operand_wave_lane_packing_pin(self):
        """§27.7a.1 / vec-contract §3: frag 0-7 = A, frag 8-15 = B, and
        lane i reads A = payload[16*i +: 16], B = payload[512 + 16*i +:
        16] (the golden_fp32.lanes_to_frags pin, lane_bits = 16).
        Reassemble the way Cluster.v's fragment buffer does and read the
        lanes back out."""
        a = [(0x1000 + i) & 0xFFFF for i in range(32)]
        b = [(0x2000 + i) & 0xFFFF for i in range(32)]
        frags = wta.wave_fragments_fdot32_cr(a, b)
        wide = 0
        for payload, hdr in frags:
            wide |= (payload & ((1 << 64) - 1)) << ((hdr >> 4) * 64)
        self.assertEqual(wide, wta.pack_fdot32_cr_operands(a, b))
        for i in range(32):
            self.assertEqual((wide >> (16 * i)) & 0xFFFF, a[i], f"A lane {i}")
            self.assertEqual((wide >> (512 + 16 * i)) & 0xFFFF, b[i],
                             f"B lane {i}")
        # halves: frag 0-7 carry A, frag 8-15 carry B
        self.assertEqual(wide & ((1 << 512) - 1),
                         wta.pack_fdot32_cr_operands(a, [0] * 32))
        self.assertEqual(wide >> 512,
                         wta.pack_fdot32_cr_operands(b, [0] * 32))

    def test_operand_wave_rejects_short_or_oversized_lanes(self):
        """LOUD rejects — a silently zero-padded short wave would make
        the dot reassemble stale slot data as operands (the SIG_BMM_3
        short-wave exposure), and a lane wider than 16 bit would
        silently overwrite its neighbour."""
        ok = [0] * 32
        for bad in ([0] * 31, [0] * 33, []):
            with self.assertRaises(wta.AssemblerError, msg=str(len(bad))):
                wta.wave_fragments_fdot32_cr(bad, ok)
            with self.assertRaises(wta.AssemblerError, msg=str(len(bad))):
                wta.wave_fragments_fdot32_cr(ok, bad)
        for bad_lane in (0x10000, -1, 1.5, None, True):
            lanes = [0] * 31 + [bad_lane]
            with self.assertRaises(wta.AssemblerError, msg=repr(bad_lane)):
                wta.wave_fragments_fdot32_cr(lanes, ok)
            with self.assertRaises(wta.AssemblerError, msg=repr(bad_lane)):
                wta.wave_fragments_fdot32_cr(ok, lanes)

    def test_operand_wave_matches_golden_vector_contract(self):
        """Cross-check against the 3a-C1 golden vectors (frozen, NOT
        touched by C2): take a directed line out of
        include/generated/fdotcr_vectors.hex, slice its 1,024-bit
        OPERANDS field the way the vec contract pins it, and prove the
        assembler's wave splitter reproduces that payload bit-for-bit
        from the lane fields. This is the C1<->C2 interface pin: if the
        asm packer and the golden packer ever disagree, the C3/C4 TB
        would feed the RTL a payload no assembler emits."""
        hexfile = os.path.join(os.path.dirname(_HERE), 'include',
                               'generated', 'fdotcr_vectors.hex')
        # `fdotcr_vectors.hex` 는 git 추적 파일(3a-C1 golden, frozen)이다.
        # 따라서 clean checkout 에서는 **항상** 존재하고, 부재는 skip 사유가
        # 아니라 결함이다 (golden 삭제 / 작업 트리 파손). skipTest 로 넘기면
        # 이 C1<->C2 인터페이스 핀이 조용히 사라져서, asm packer 와 golden
        # packer 가 어긋나도 아무도 알아채지 못한다 — 그래서 격상한다.
        self.assertTrue(
            os.path.exists(hexfile),
            f'3a-C1 golden vectors missing: {hexfile} — git 추적 파일이므로 '
            f'부재는 skip 사유가 아니라 결함이다')
        with open(hexfile, encoding='utf-8') as f:
            lines = [ln.strip() for ln in f
                     if ln.strip() and not ln.lstrip().startswith('//')]
        self.assertGreaterEqual(len(lines), 1)
        checked = 0
        for ln in lines[:8]:
            v = int(ln, 16)
            self.assertEqual(len(ln), 272, 'vec line width drifted')
            payload = (v >> 32) & ((1 << 1024) - 1)
            a = [(payload >> (16 * i)) & 0xFFFF for i in range(32)]
            b = [(payload >> (512 + 16 * i)) & 0xFFFF for i in range(32)]
            self.assertEqual(wta.pack_fdot32_cr_operands(a, b), payload)
            frags = wta.wave_fragments_fdot32_cr(a, b)
            self.assertEqual(len(frags), 16)
            reassembled = 0
            for p, h in frags:
                reassembled |= (p & ((1 << 64) - 1)) << ((h >> 4) * 64)
            self.assertEqual(reassembled, payload)
            # dtype byte of META must be one of the 2 legal rows
            meta = v >> (1024 + 32)
            self.assertIn(meta & 0xFF, (0x2, 0x3))
            checked += 1
        self.assertEqual(checked, 8)

    # ---- staging state (§27.7a.4) --------------------------------------

    def test_decode_reserved_cleared_at_wiring(self):
        """3a-C4 INVERSION of test_decode_reserved_until_wiring.

        Until 3a-C4 this test asserted the opposite: 0x7A was transcribed
        everywhere on the asm side but DELIBERATELY omitted from the RTL
        opcode_supported whitelist, so silicon answered decode_error for
        every mode byte (§27.7 reservation wording, §27.7a.4 landing
        order). 3a-C4 flipped `decode_reserved` in the JSON in the SAME
        COMMIT as the PE_Core 0x7A arm + the twin-classifier lockstep
        edit, so the assertions invert together.

        The whitelist membership check is kept (not deleted) because it
        is the only mechanical proof that the regeneration actually ran:
        editing the JSON without regenerating leaves 0x7A out of
        `opcode_supported` and every 0x7A dispatch keeps decode_erroring
        while the Python tables claim it is legal."""
        from generated_isa_tables import DECODE_RESERVED_OPS, STUB_OPS_V18
        self.assertNotIn(0x7A, DECODE_RESERVED_OPS)
        self.assertNotIn(0x7A, STUB_OPS_V18)
        self.assertIn('FDOT32_CR', wta.MNEMONIC_TO_OPCODE)
        self.assertEqual(wta.OPCODE_TO_MNEMONIC[0x7A], 'FDOT32_CR')
        wires = os.path.join(os.path.dirname(_HERE), 'include', 'generated',
                             'isa_opcode_wires.vh')
        with open(wires, encoding='utf-8') as f:
            text = f.read()
        supported = text.split('wire opcode_supported =')[1].split(';')[0]
        # W1/W7: whitelist 비교는 12비트 전폭({cb_opcode_ext, cb_opcode})
        # 이고 리터럴 표기는 12'h0## 3자리다.
        self.assertIn("12'h07A", supported,
                      "0x07A must be in opcode_supported from 3a-C4 on "
                      "(did you edit the JSON without regenerating?)")
        for other in ("12'h079", "12'h07C", "12'h07E"):
            self.assertIn(other, supported)
        # The staging-bit machinery itself must still be present and
        # honest: no row claims decode_reserved today.
        self.assertEqual(DECODE_RESERVED_OPS, frozenset())

    def test_frozen_truth_table_untouched(self):
        """§27.7a.4 finding, quoting the isa JSON 0x079 note VERBATIM:
        '0x070-0x07F is outside the truth-table domain' (W7 표기 이관을
        따라 동일 커밋에 재동기된 인용). premigration 캡처의 지위는
        인코딩 개정 파도 이후 「이관 전 HEAD(042f08e) 계보 전용 블랙박스
        오라클」로 **좁아졌다** — 동결 단언(domain_version 3, fp-block
        0점)은 계속 참이고, 현행 재생 대조는 isa/truth_table_encwave.json
        (domain_version 4)이 **승계했다**. 이 시험이 재는 것은 그 동결
        자체다: 재지향은 표를 옮기는 것이지 고치는 것이 아니므로, 이
        파일이 한 바이트라도 움직이면 여기서 울려야 한다."""
        import json as _json
        root = os.path.dirname(_HERE)
        with open(os.path.join(root, 'isa', 'wt64v1_isa.json'),
                  encoding='utf-8') as f:
            src = _json.load(f)
        note_79 = next(o['notes'] for o in src['opcodes'] if o['code'] == 0x79)
        self.assertIn('0x070-0x07F is outside the truth-table domain', note_79)
        with open(os.path.join(root, 'isa',
                               'truth_table_premigration.json'),
                  encoding='utf-8') as f:
            cap = _json.load(f)
        # the C2 consequence: NO bump (the 0e1 baseline stands)
        self.assertEqual(cap['domain_version'], 3)
        # the C2 premise: point keys are '0xOP|ehs|flags|port' (the 4th
        # field is the port-EH presence flag 'P'/'-'; the OUTCOME is the
        # 3-element value vector, not a key field) and no captured opcode
        # lives in the fp block, so an fp-block ISA row cannot move a
        # single frozen point. NOTE the 2-digit '0xOP' notation: W7's
        # 3-digit migration deliberately did NOT touch this file — it is
        # frozen, and the current-encoding table that DOES carry 0x0##
        # keys is isa/truth_table_encwave.json (see the consumer pin).
        ops = set()
        for key in cap['points']:
            ops.add(int(str(key).split('|')[0], 16))
        self.assertGreater(len(ops), 50, 'truth-table key parse broke')
        self.assertFalse([o for o in ops if 0x70 <= o <= 0x7F],
                         'frozen truth table unexpectedly covers the fp block')


class TestCrcReferenceValues(unittest.TestCase):
    """인코딩 개정 파도 (W5·W8) — CRC 기지값 7종 자기시험.

    본체(wavetensor_asm)와 이 파일의 참조 구현은 **독립**이다(LFSR/장제법,
    비트루프/표). 둘 다 아래 핀 명세 기지값을 각자 통과해야 하고, 표본
    구간에서 서로 일치해야 한다 — 같은 버그를 두 벌 복사하는 경로를 막는다.
    """

    # P1 — OPREF CRC-4: (LBID, src_kind) -> CRC
    _CRC4_PINS = [(0x00, 0, 0x0), (0x01, 1, 0x6), (0xA5, 2, 0x8),
                  (0xFF, 2, 0xA)]
    # P2 — CH CRC-32C (RFC 3720 시험 패턴)
    _CRC32C_PINS = [(b"123456789", 0xE3069283),
                    (bytes(32), 0x8A9136AA),
                    (bytes([0xFF] * 32), 0x62A8AB43)]

    def test_crc4_known_values_both_implementations(self):
        for lbid, sk, exp in self._CRC4_PINS:
            self.assertEqual(wta.crc4_opref(lbid, sk), exp,
                             f"asm crc4({lbid:#04x},{sk})")
            self.assertEqual(_ref_crc4(lbid, sk), exp,
                             f"ref crc4({lbid:#04x},{sk})")

    def test_crc32c_known_values_both_implementations(self):
        for data, exp in self._CRC32C_PINS:
            self.assertEqual(wta.crc32c(data), exp, f"asm crc32c({data!r})")
            self.assertEqual(_ref_crc32c(data), exp, f"ref crc32c({data!r})")

    def test_crc4_cross_agreement_exhaustive(self):
        """본문 12b 전 공간(4096점) 교차 일치 — 작아서 전수가 싸다."""
        for lbid in range(256):
            for sk in range(16):
                self.assertEqual(wta.crc4_opref(lbid, sk),
                                 _ref_crc4(lbid, sk), (lbid, sk))

    def test_crc32c_cross_agreement_samples(self):
        samples = [b"", b"\x00", b"a", bytes(range(256)),
                   b"WaveTensor CH", bytes([0x5A] * 56),
                   (0xDEADBEEF).to_bytes(4, 'little') * 13]
        for s in samples:
            self.assertEqual(wta.crc32c(s), _ref_crc32c(s), repr(s))


class TestEncodingWaveW1W8(unittest.TestCase):
    """인코딩 개정 파도 — W1(12b opcode)·W5(OPREF CRC-4)·W8(CH) 인코더 핀."""

    def test_eh0_instruction_has_no_ch_and_is_prewave_bit_identical_shape(self):
        """EH-0 (NOP, next_hdr = END): CH 없음 — bh_len = 1, word 1 = 0.
        W1 의 「기존 바이너리 무변경」 주장은 정확히 이 부류에 성립한다:
        확장 니블 0x0 + [15:12] 0 + CH 부재라 하위 416b 가 파도 전과 비트
        동일하고, 14워드째 패딩(상위 32b)은 0 이라 정수값도 같다."""
        val = assemble_one("NOP\n")
        words = [(val >> (32 * i)) & 0xFFFFFFFF for i in range(14)]
        self.assertEqual(words[0] & 0xFF, 1, "EH-0 bh_len must be 1")
        self.assertEqual((words[0] >> 20) & 0xF, 0x0, "next_hdr must be END")
        self.assertEqual(words[1], 0, "EH-0 has NO CH — word 1 stays padding")
        self.assertEqual((words[0] >> 8) & 0xFF, 0,
                         "[15:8] = reserved(0) + opcode_ext(0) for NOP")
        self.assertLess(val, 1 << 416,
                        "EH-0 padding keeps the integer inside 416b")

    def test_base_header_emits_extension_nibble_and_reserved_zero(self):
        """W1: [11:8] = opcode[11:8] 방출, [15:12] 는 항상 0. 현행 opcode
        는 전부 ≤ 0xFF 라 확장 니블 0x0 이 관측값이다 — 방출 *코드 경로*
        는 12b 마스크로 검사한다 (opcode > 0xFFF 는 인코더가 거부)."""
        for src, opc in (("ADD .port dest=1 .imm16 5\n", 0x010),
                         ("NOP\n", 0x000)):
            val = assemble_one(src)
            base = val & 0xFFFFFFFF
            self.assertEqual((base >> 12) & 0xF, 0, "[15:12] reserved-zero")
            self.assertEqual((base >> 8) & 0xF, (opc >> 8) & 0xF)
            self.assertEqual((base >> 24) & 0xFF, opc & 0xFF)
        wta.MNEMONIC_TO_OPCODE['__W1_RANGE_PROBE__'] = 0x1000
        try:
            bad = wta.Instruction(mnemonic='__W1_RANGE_PROBE__',
                                  flags=set(), eh_list=[], line=1)
            with self.assertRaises(AssemblerError):
                wta._encode_instruction(bad)
        finally:
            del wta.MNEMONIC_TO_OPCODE['__W1_RANGE_PROBE__']

    def test_ch_word_recomputation_matches_on_eh_instruction(self):
        """W8: EH ≥ 1 이면 word 1 = CH = 자기 워드 제외 전 워드(word 0,
        word 2‥bh_len−1, 오름차순, 리틀엔디언 직렬화)의 CRC-32C. 참조측
        독립 crc32c 로 재계산 대조한다."""
        val = assemble_one("ADD .port dest=1 .imm16 5\n")
        words = [(val >> (32 * i)) & 0xFFFFFFFF for i in range(14)]
        bh_len = words[0] & 0xFF
        self.assertEqual(bh_len, 4, "base + CH + PORT + IMM16")
        msg = b''.join(w.to_bytes(4, 'little')
                       for w in [words[0]] + words[2:bh_len])
        self.assertEqual(words[1], _ref_crc32c(msg),
                         "CH must equal the CRC-32C of every non-CH word")
        m = ref.decode_mirror(val)
        self.assertTrue(m['ch_ok'])
        self.assertEqual([eh['type'] for eh in m['ehs']],
                         [EH_PORT, EH_IMM16])

    def test_ch_absent_iff_next_hdr_end(self):
        """존재 유도 (W8): next_hdr ≠ END ⇔ word 1 = CH. 양방향을 EH-0
        (NOP)·EH-1+(ADD) 한 쌍으로 핀한다."""
        nop = assemble_one("NOP\n")
        add = assemble_one("ADD .port dest=1 .imm16 5\n")
        self.assertEqual((nop >> 20) & 0xF, 0x0)
        self.assertEqual((nop >> 32) & 0xFFFFFFFF, 0)
        self.assertNotEqual((add >> 20) & 0xF, 0x0)
        self.assertNotEqual((add >> 32) & 0xFFFFFFFF, 0,
                            "EH-bearing instruction must carry a CH word")

    def test_opref_emits_crc4_nibble(self):
        """W5: OPREF EH [23:20] = 본문 12b 의 CRC-4 (기지값으로 핀)."""
        for route, kind, crc in ((0x00, 0, 0x0), (0x01, 1, 0x6),
                                 (0xA5, 2, 0x8), (0xFF, 2, 0xA)):
            eh = wta.ExtensionHeader('opref',
                                     {'route': route, 'kind': kind}, 0)
            type_code, ws = wta._encode_eh(eh)
            self.assertEqual(type_code, wta.EH_OPREF)
            self.assertEqual(len(ws), 1)
            self.assertEqual((ws[0] >> 20) & 0xF, crc,
                             f"route={route:#04x} kind={kind}")
            self.assertEqual((ws[0] >> 24) & 0xFF, route)
            self.assertEqual((ws[0] >> 16) & 0xF, kind)

    def test_opref_user_crc_injection_rejected(self):
        """`.opref port=` 비0 거부 존치 — 근거는 개정됐다: [23:20] 은
        CRC-4 필드이고 CRC 는 어셈블러가 계산·주입한다 (사용자 주입 금지)."""
        eh = wta.ExtensionHeader('opref', {'port': 3}, 7)
        with self.assertRaises(AssemblerError) as ctx:
            wta._encode_eh(eh)
        self.assertIn('CRC', str(ctx.exception))

    def test_opref_roundtrip_through_full_pipeline(self):
        """어셈블러 전체 경로의 OPREF 도 같은 CRC 를 나른다 (EINSUM 합성
        경로 포함 — _encode_eh 단일 경로라 자동으로 얻지만, 전 경로에서
        한 번 관측해 둔다)."""
        val = assemble_one("ADD opb .port dest=1 .opref\n")
        m = ref.decode_mirror(val)
        opref_w = next(eh['words'][0] for eh in m['ehs']
                       if eh['type'] == EH_OPREF)
        self.assertEqual((opref_w >> 20) & 0xF, _ref_crc4(0, 0))
        self.assertTrue(m['ch_ok'])


class TestEncwaveTruthTableConsumerPin(unittest.TestCase):
    """P5 소비자 핀 — 인코딩 개정 파도의 현행 truth table (재생 게이트의 clean 측).

    파일 = `isa/truth_table_encwave.json`, domain_version = 4 (v4 정의의
    일부로 키 opcode 표기가 0x0## 3자리다). 캡처 자체는 격리 안(루트
    cocotb 모듈)에서 W1~W8 반영 RTL 로 전량 1회 이뤄졌고 — clean-room
    규약상 이 파일은 그 캡처 드라이버를 읽지 않는다 — 이 클래스는 그
    **산출물만** 받아 재검산한다. 파일 부재는 이제 skip 이 아니라
    **하드 실패**다: 캡처가 착지했고 현행 재생 대조가 여기로 재지향됐다.

    premigration 은 존치·동결이고 지위가 「이관 전 HEAD(042f08e) 계보
    전용 블랙박스 오라클」로 좁아졌다. 아래 두 대조는 그 표를
    **통과/실패를 받는 블랙박스로만** 쓴다 (키 집합과 판정 벡터의 대조
    — 명세로 읽지 않는다):

      · 축 무변경 — 표기 정규화 후 키 집합이 1:1 이어야 한다.
      · 판정 무변경 — 파도는 *바이너리*를 바꿨지 *디코드 판정*을 바꾸지
        않았다. 5,934점 전량 outcome 이 같아야 한다.

    그 둘이 참이라는 것은 곧 `points` 축의 **반증력이 0비트**라는 뜻이기도
    하다 (재캡처는 옳지만 새 오라클이 아니다). 반증력은 전적으로 새 축
    `ext_probes` 가 진다 — 확장 니블이 접히면(선택자·결선이 8비트로
    되돌아가면) 그 점들이 기본 영역 판정으로 발산한다.

    다만 **축이 존재한다는 것과 축이 반증력을 가진다는 것은 다른 명제다.**
    실측에서 207 탐침 중 발산하는 것은 60점뿐이고 나머지 147점은 접혀도
    같은 값을 낸다 — 축을 그 147점만으로 갈아치워도 아래 시험들이 전량
    통과한다. 그 구멍은 `test_ext_probes_retain_folding_discrimination`
    이 닫는다: 개수가 아니라 **접힘 대응점과의 차이**를 센다.
    """

    _PATH = os.path.join(os.path.dirname(_HERE), 'isa',
                         'truth_table_encwave.json')
    _FROZEN = os.path.join(os.path.dirname(_HERE), 'isa',
                           'truth_table_premigration.json')

    @staticmethod
    def _load(path):
        import json as _json
        with open(path, encoding='utf-8') as f:
            return _json.load(f)

    @classmethod
    def _norm_key(cls, key):
        """premigration 의 2자리 opcode 표기를 W7 의 3자리로 정규화한다.
        나머지 세 필드(EH 조합 · flags · port)는 손대지 않는다."""
        f = str(key).split('|')
        f[0] = '0x%03X' % int(f[0], 16)
        return '|'.join(f)

    @classmethod
    def _folded_key(cls, key):
        """확장 니블이 **상수 0 에 묶였을 때**(B1 결선) 그 탐침이 실제로
        밟게 되는 기본 영역 점의 키. 형상 세 필드(EH 조합 · flags · port)는
        그대로 두고 opcode 만 `0xNLL` → `0x0LL` 로 접는다."""
        f = str(key).split('|')
        f[0] = '0x%03X' % (int(f[0], 16) & 0xFF)
        return '|'.join(f)

    def _cap(self):
        self.assertTrue(
            os.path.exists(self._PATH),
            'isa/truth_table_encwave.json 부재 — 현행 재생 대조의 대상이다 '
            '(P5 에서 착지). premigration 은 이관 전 계보 전용으로 좁아졌으니 '
            '이 파일 없이는 현행 인코딩의 회귀 표가 아예 없다')
        return self._load(self._PATH)

    def _reject_outcome(self, cap):
        """「거부」 판정 벡터를 *데이터에서 유도*한다 — 벡터 표현을
        하드코딩하지 않는다. required EH 를 가진 opcode 의 EH-0 점
        (`0x0##||0x0|-`, 확장 헤더가 하나도 없는 형상)은 정의상 필수
        EH 결손이라 거부여야 하고, 그런 점 전부가 한 벡터로 모여야 한다."""
        from generated_isa_tables import LEGAL
        seen = {}
        for code, rule in LEGAL.items():
            if not rule['required']:
                continue
            key = '0x%03X||0x0|-' % code
            if key in cap['points']:
                seen.setdefault(tuple(cap['points'][key]), []).append(code)
        self.assertGreater(sum(len(v) for v in seen.values()), 20,
                           '거부 앵커 점을 충분히 찾지 못했다 — 키 문법 파손 의심')
        self.assertEqual(len(seen), 1,
                         f'필수 EH 결손 점들이 한 판정으로 모이지 않는다: '
                         f'{ {k: len(v) for k, v in seen.items()} }')
        return next(iter(seen))

    def test_domain_version_and_three_digit_notation(self):
        cap = self._cap()
        self.assertEqual(cap['domain_version'], 4,
                         'encwave 는 domain_version 4 다 (P5). premigration 의 '
                         '3 은 동결 유지 — 둘은 다른 파일의 다른 정의역이다')
        for axis in ('points', 'ext_probes'):
            self.assertIn(axis, cap, f'encwave 에 {axis} 축이 없다')
            for key in cap[axis]:
                fields = str(key).split('|')
                self.assertEqual(len(fields), 4,
                                 f'키는 4필드(op|ehs|flags|port)다: {key}')
                self.assertRegex(fields[0], r'^0x[0-9A-Fa-f]{3}$',
                                 f'{axis} 키 opcode 표기는 0x0## 3자리다: {key}')

    def test_axis_unchanged_against_frozen_premigration(self):
        """P5 항 3 「축 무변경」의 기계 확인 — 표기 정규화 후 키 집합 1:1."""
        cap = self._cap()
        frozen = self._load(self._FROZEN)
        got = set(cap['points'])
        want = {self._norm_key(k) for k in frozen['points']}
        self.assertEqual(len(want), len(frozen['points']),
                         '표기 정규화가 premigration 키를 충돌시켰다')
        self.assertGreater(len(want), 5000, '동결 표 파싱 붕괴 의심')
        self.assertEqual(got - want, set(),
                         'encwave 에 동결 도메인 밖의 점이 points 축에 섞였다 '
                         '(새 축은 ext_probes 다)')
        self.assertEqual(want - got, set(),
                         'encwave 가 동결 도메인의 점을 잃었다 — 전량 재캡처가 '
                         '아니다')

    def test_outcomes_match_frozen_premigration(self):
        """파도는 *바이너리*를 바꿨지 *디코드 판정*을 바꾸지 않았다.

        EH≥1 은 CH 삽입 + bh_len+1 로 인코딩이 달라지고 OPREF 는 CRC
        니블이 생겼지만, 어느 것도 합법성 판정을 뒤집지 않는다 — 전량
        일치가 그 명제의 기계 형태다. (이 대조가 참이라는 사실이 곧
        `points` 축의 반증력이 0비트라는 증거이기도 하다.)"""
        cap = self._cap()
        frozen = self._load(self._FROZEN)
        pre = {self._norm_key(k): v for k, v in frozen['points'].items()}
        diff = [k for k, v in cap['points'].items()
                if list(pre.get(k, [])) != list(v)]
        self.assertEqual(diff[:8], [],
                         f'동결 표와 판정이 갈리는 점 {len(diff)}건 — 파도는 '
                         f'인코딩만 바꿨어야 한다')

    def test_ext_probe_axis_is_present_and_rejecting(self):
        """새 축 `ext_probes` — 확장 니블이 살아 있다는 유일한 증거.

        W3: 미배정 opcode(확장 영역 전체 포함) = malformation. 이 점들이
        전부 거부여야 하고, 그 거부 벡터는 수용 벡터와 **달라야** 한다 —
        같으면 단언이 아무것도 배제하지 못한다(공허 방지)."""
        cap = self._cap()
        probes = cap['ext_probes']
        self.assertGreaterEqual(
            len(probes), 64,
            f'ext_probes 가 {len(probes)}점뿐 — 확장 니블 축이 사실상 '
            f'사라졌다. 이 축이 없으면 「니블을 선언만 하고 상수 0 에 묶는」 '
            f'결선을 어떤 그물도 잡지 못한다')
        reject = self._reject_outcome(cap)
        accept = tuple(cap['points']['0x001||0x0|P'])
        self.assertNotEqual(
            reject, accept,
            '거부 벡터와 수용 벡터가 같다 — 판정 축이 무너졌고 아래 단언이 '
            '공허해진다 (0x001 WADV 는 port 필수, 그 충족 점은 수용이다)')
        for key, outcome in probes.items():
            op = int(str(key).split('|')[0], 16)
            self.assertNotEqual(op >> 8, 0,
                                f'ext_probes 에 확장 니블 0 인 점이 있다: {key} '
                                f'— 이 축의 정의는 ext != 0 이다')
            self.assertEqual(tuple(outcome), reject,
                             f'{key} 가 거부가 아니다 — W3(미배정 opcode = '
                             f'malformation) 위반이거나 확장 니블이 접혔다')

    def test_ext_probes_retain_folding_discrimination(self):
        """탐침이 **접힘을 잡을 수 있는 점인가** — 축의 반증력 자체를 잰다.

        바로 위 시험이 축에 거는 것은 셋뿐이다: `len >= 64` · 전 점 ext≠0 ·
        전 점 == reject. **어느 것도 그 점들이 무엇을 배제하는지 묻지
        않는다.** 실측(재현): 207 탐침 중 147점은 접힘 대응점
        `points['0x0LL|<같은 형상>']` 도 거부라서, 확장 니블이 상수 0 에
        묶여도 **같은 값을 낸다** — 반증력 0인 점이다. 그 147점 중 64점만
        남긴 `ext_probes` 로 위 다섯 시험을 돌리면 전량 ok / rc=0 이고,
        격리 안 RTL 차등 시험도 같은 (얇아진) 표를 대조하므로 함께
        초록이 된다. 즉 「니블을 선언만 하고 상수 0 에 묶기」가 다시
        무방비가 된다 — 축이 사라지지 않고 *속만 비어도* 그렇다.

        그래서 여기서는 개수가 아니라 **차이**를 센다. 탐침 k 가 접힘을
        검출한다 ⟺ `probes[k] != points[fold(k)]`. 전 탐침이 거부인 한
        이것은 「접힘 대응점이 수용이다」와 같은 말이고, 그 점에서만 니블
        상수 결선이 판정을 뒤집는다.

        하한 셋은 전부 커밋된 JSON 에서 유도한 현행 실측이다(2026-08-29:
        검출력 60점 · low byte 20종 · 니블 0x1/0x4/0xF 각 20점). 하한이라
        축을 넓히는 커밋은 통과하고 **얇게 만드는 커밋은 그 자리에서
        죽는다.**
        """
        cap = self._cap()
        probes, points = cap['ext_probes'], cap['points']
        reject = self._reject_outcome(cap)

        missing = sorted(k for k in probes
                         if self._folded_key(k) not in points)
        self.assertEqual(
            missing[:8], [],
            f'접힘 대응점이 points 축에 없는 탐침 {len(missing)}건 — 탐침은 '
            f'동결 도메인 형상의 *확장 니블 들어올림*이어야 측정 가능하다. '
            f'대응점이 없으면 그 탐침의 반증력은 잴 수 없고, 잴 수 없는 '
            f'점은 이 축의 몫을 지지 못한다')

        detecting = [k for k, v in probes.items()
                     if list(points[self._folded_key(k)]) != list(v)]
        for k in detecting[:1]:
            # 위 시험의 전제(전 점 거부)를 이 시험 안에서도 한 번 못박는다 —
            # 그것이 참일 때만 「검출 = 대응점이 수용」이 성립한다.
            self.assertEqual(tuple(probes[k]), reject,
                             f'{k} 가 거부가 아니다 — 검출력 산술의 전제가 '
                             f'깨졌다')

        self.assertGreaterEqual(
            len(detecting), 60,
            f'접힘 검출력이 있는 탐침이 {len(detecting)}점뿐이다(전체 '
            f'{len(probes)}점). 나머지는 확장 니블이 상수 0 에 묶여도 같은 '
            f'값을 내므로 이 축은 그만큼 공허하다 — 현행 실측 하한은 60점')

        lows = {int(str(k).split('|')[0], 16) & 0xFF for k in detecting}
        self.assertGreaterEqual(
            len(lows), 20,
            f'검출력 있는 탐침의 low byte 가 {len(lows)}종뿐이다 — 한두 '
            f'opcode 에 몰린 검출력은 그 opcode 의 arm 만 지킨다. 현행 '
            f'실측 하한은 20종')

        per_nibble = {}
        for k in detecting:
            per_nibble.setdefault(int(str(k).split('|')[0], 16) >> 8,
                                  []).append(k)
        wide = sorted(n for n, ks in per_nibble.items() if len(ks) >= 20)
        self.assertGreaterEqual(
            len(wide), 3,
            f'검출력 20점 이상을 가진 확장 니블이 {len(wide)}개뿐이다 '
            f'({ {hex(n): len(v) for n, v in sorted(per_nibble.items())} }). '
            f'W1 의 세 영역 — 기존 0x0##–0x3## · 신규 확장 0x4##–0x7## · '
            f'예비 — 이 각각 검출력을 가져야 니블 상수 결선이 어느 영역에서 '
            f'접히든 잡힌다')

    def test_ext_probes_disjoint_from_frozen_domain(self):
        """ext_probes 는 *새 축*이지 동결 도메인의 재캡처가 아니다."""
        cap = self._cap()
        self.assertEqual(set(cap['ext_probes']) & set(cap['points']), set(),
                         'ext_probes 가 points 축과 겹친다 — 두 축의 정의역이 '
                         '섞이면 「전량 5,934점」 산술이 무너진다')


class TestExtNibbleGateArtifacts(unittest.TestCase):
    """수리 라운드 1 — W1/W2/W3 확장 니블 게이트의 상주 측정.

    배경(실측): 생성 .vh 의 12'h### case arm 은 8비트 case 선택자 아래서
    zero-extend 로 *조용히* 컴파일·매치된다 (verilator 5.048 — WIDTHEXPAND
    경고뿐, -Wno-fatal 아래 rc 0; ext=4'h4·op=8'h7A 가 12'h07A arm 에 매치).
    정확히 W2 가 경고한 0x47B→0x07B 공허 PASS 형태다. 수리로 case body 에
    never-match cb_opcode_ext 참조 arm(컴파일 강제 가드)을 심었고, 이
    클래스는 그 가드의 실재와 W2/W3 의미론을 상주로 잰다 — 종전에는 /tmp
    일회용 실측뿐이라 재생성이 게이트를 떨어뜨려도 어떤 상주 시험도 울리지
    않았다.
    """

    @staticmethod
    def _read(rel):
        with open(os.path.join(os.path.dirname(_HERE), *rel.split('/')),
                  encoding='utf-8') as f:
            return f.read()

    def test_case_body_w2_compile_forcing_guard(self):
        """case body 첫 arm = never-match cb_opcode_ext 참조 가드.

        확장 니블이 결선되지 않은 소비자는 이 가드에서 컴파일이 깨진다
        (undeclared identifier — verilator 실측 Error, -Wno-fatal 무관).
        12b 연접 선택자에서는 x == ~x 가 불가능해 행동 무변경이다
        (TB 실측: 0x07A arm 적중 · 0x47A default 적중 · 가드 비적중)."""
        body = self._read('include/generated/isa_ehshape_case_body.vh')
        guard = "(~{cb_opcode_ext, cb_opcode}): ;"
        self.assertIn(guard, body,
                      'W2 컴파일 강제 가드가 case body 에서 사라졌다 — '
                      '8b 선택자 소비자가 다시 조용히 컴파일된다')
        first_arm = body.index("12'h")
        self.assertLess(body.index(guard), first_arm,
                        'W2 가드는 첫 12b arm 앞에 있어야 한다')
        self.assertIn('default: begin', body, 'W3 default arm 부재')
        self.assertIn('미배정 opcode = malformation', body,
                      'W3 규범 문면이 산출물에서 사라졌다')

    def test_case_body_arms_are_12bit_fullwidth(self):
        import re
        body = self._read('include/generated/isa_ehshape_case_body.vh')
        arms = re.findall(r"12'h([0-9A-F]{3}):", body)
        self.assertGreater(len(arms), 40)
        codes = {int(a, 16) for a in arms}
        self.assertIn(0x07A, codes)
        # 8b 폭 arm(12'h 아닌 8'h)이 하나라도 섞이면 즉시 실패.
        self.assertNotRegex(body, r"8'h[0-9A-F]{2}:",
                            'case body 에 8비트 arm 이 섞였다')

    def _supported_codes(self):
        import re
        wires = self._read('include/generated/isa_opcode_wires.vh')
        m = re.search(r'wire opcode_supported =(.*?);', wires, re.S)
        self.assertIsNotNone(m, 'opcode_supported wire 부재')
        codes = {int(c, 16) for c in
                 re.findall(r"\{cb_opcode_ext, cb_opcode\} == 12'h([0-9A-F]{3})",
                            m.group(1))}
        self.assertGreater(len(codes), 40, 'opcode_supported 파싱 실패 의심')
        return codes

    def test_opcode_supported_w3_semantics(self):
        """opcode_supported 는 순수 등호-OR 이므로 집합 소속 평가가 곧
        행동 평가다: ext≠0 전 영역(0x47B·0x470·0x4##)과 예비 영역
        (0x800·0xF00)은 거부, 0x000·0x010·0x07A 는 수용. 0x07B/0x07F 는
        decode_reserved(실행 결선 선행 출하)라 whitelist 에 의도적으로
        부재다 — 여기 넣지 않는다."""
        codes = self._supported_codes()
        for bad in (0x47B, 0x470, 0x410, 0x800, 0xF00):
            self.assertNotIn(bad, codes,
                             f'0x{bad:03X} 가 opcode_supported 에 있다 — '
                             f'W3 미배정=malformation 위반')
        for good in (0x000, 0x010, 0x07A):
            self.assertIn(good, codes)
        self.assertTrue(all(c <= 0xFFF for c in codes))

    def test_assigned_codes_ext_nibble_zero_tripwire(self):
        """트립와이어: 현재 배정 opcode 전부 확장 니블 0 (0x0## 계보).

        0x4## 등 신규 영역이 실제로 claim 되면 이 핀은 의식적으로 갱신해야
        한다 — 그 커밋은 encwave truth table 축 개정(ext≠0 벡터)과 legacy
        결선 재확인을 함께 실어야 한다 (W3 영역 구획은 배정 절차 규범)."""
        codes = self._supported_codes()
        offenders = sorted(c for c in codes if c >> 8)
        self.assertEqual(offenders, [],
                         f'확장 니블 비0 opcode 배정 발견: '
                         f'{[hex(c) for c in offenders]} — 트립와이어 갱신 필요')

    def test_in_fp_block_w2_gate(self):
        """W2 실물 게이트의 문면 핀 + 의미 평가."""
        wires = self._read('include/generated/isa_opcode_wires.vh')
        pinned = ("wire in_fp_block = "
                  "(cb_opcode_ext == 4'h0) && (cb_opcode[7:4] == 4'h7);")
        self.assertIn(pinned, wires,
                      'W2 fp ROM 게이트(확장 니블 == 0x0 검사)가 산출물에서 '
                      '사라졌다 — 0x47B 가 0x07B 행에 얹히는 공허 PASS 재개')
        # 핀한 식의 의미 평가 (게이트 의미론의 이중 측정).
        def in_fp_block(ext, op):
            return ext == 0x0 and ((op >> 4) & 0xF) == 0x7
        self.assertTrue(in_fp_block(0x0, 0x7B))
        self.assertFalse(in_fp_block(0x4, 0x7B))
        self.assertFalse(in_fp_block(0x0, 0x6B))

    def test_wires_no_bare_8bit_compare(self):
        """wires 산출물의 opcode 비교 전부가 12b 전폭 연접이어야 한다."""
        import re
        wires = self._read('include/generated/isa_opcode_wires.vh')
        self.assertNotRegex(
            wires, r"\(cb_opcode ==",
            'cb_opcode 단독(8b) 비교 발견 — 확장 니블이 접힌다 (W2)')
        self.assertNotRegex(wires, r"== 12'h[0-9A-F]{2}\)",
                            '12b 리터럴이 3자리 미만이다')


class TestEhAcctgtTwoLayerTripwire(unittest.TestCase):
    """EH 0x9 (ACCTGT) 이층 분기 트립와이어 — 수리 라운드 1.

    실측된 분기: legacy eh 표(include/generated/isa_eh_codes.vh)에는 0x9
    행 자체가 없어 legacy 구조 판정은 0x9 를 미지 종류 후보로 처분하고,
    Spinal 재구현 카탈로그(DecodeWalk catalogWords)는 0x9 를 정의 종류
    (1워드·반복상한 1)로 순회한다. 0x9 를 나르는 명령의 구조 판정이 두
    층에서 갈릴 수 있는 창인데 truth table 은 acctgt 0점이고 encwave 계획도
    축 무변경이라 어떤 벡터도 이 창을 재지 않는다. 이 핀은 그 창을 *의식된
    상태*로 유지한다: eh_codes 0x9 배정(Di 실장 파도, 0x79 재행과 함께)은
    JSON eh_codes + legacy 표 재생성 + truth table 재캡처를 같은 커밋에
    실어야 하고, 그 커밋이 이 핀을 의식적으로 갱신한다 (P4 범위 제한)."""

    def test_eh_codes_0x9_unassigned_pin(self):
        import json as _json
        repo = os.path.dirname(_HERE)
        with open(os.path.join(repo, 'include', 'generated',
                               'isa_eh_codes.vh'), encoding='utf-8') as f:
            vh = f.read()
        self.assertNotIn('EH_ACCTGT', vh,
                         'legacy eh 표에 0x9 가 배정됐다 — 이 트립와이어와 '
                         'Spinal 카탈로그·재캡처의 록스텝을 확인하고 갱신하라')
        self.assertNotIn("4'h9", vh)
        with open(os.path.join(repo, 'isa', 'wt64v1_isa.json'),
                  encoding='utf-8') as f:
            isa = _json.load(f)
        self.assertNotIn(0x9, set(isa['eh_codes'].values()),
                         'JSON eh_codes 에 0x9 배정 — Di 실장 파도의 록스텝 '
                         '커밋(legacy 표 + 재캡처 동일 커밋)인지 확인하라')
