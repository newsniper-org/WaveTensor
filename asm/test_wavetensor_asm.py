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

# v1.8.0a COMMIT 1 — frozen from pre-migration HEAD (042f08e), keep forever.
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
    0x66: {'required': ['port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x67: {'required': ['port'], 'forbidden': ['mem', 'subscript'], 'allow_imm_xor_opref': True, 'require_opb_flag': False, 'require_imm16': False},
    0x68: {'required': ['port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x69: {'required': ['port'], 'forbidden': ['mem', 'subscript'], 'allow_imm_xor_opref': True, 'require_opb_flag': False, 'require_imm16': False},
    0x6A: {'required': ['port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
    0x6B: {'required': ['port'], 'forbidden': ['mem', 'subscript'], 'allow_imm_xor_opref': True, 'require_opb_flag': False, 'require_imm16': False},
    0x6C: {'required': ['port'], 'forbidden': ['imm16', 'imm32', 'imm64', 'mem', 'opref', 'subscript'], 'allow_imm_xor_opref': False, 'require_opb_flag': False, 'require_imm16': False},
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
INSTR_WORDS_REAL = 13


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
    def fn(nh):
        upper = ((noc_route & 0xFF) << 8) | ((port_id & 0xF) << 4) | (src_kind & 0xF)
        return [(upper << 16) | (nh << 12) | (EH_OPREF << 8) | 1]
    return _EH(EH_OPREF, 1, fn)


def _axes(*labels):
    v = 0
    for i, l in enumerate(labels):
        v |= (l & 0xF) << (i * 4)
    return v


def _encode_instr(opcode, *exts, flags=0):
    chained = []
    nh = EH_END
    for eh in reversed(exts):
        chained.insert(0, (eh, nh))
        nh = eh.type
    bh_len = 1 + sum(eh.words for eh, _ in chained)
    base = ((opcode & 0xFF) << 24) | ((nh & 0xF) << 20) \
         | ((flags & 0xF) << 16) | (bh_len & 0xFF)
    words = [base]
    for eh, nh_v in chained:
        words.extend(eh.emit(nh_v))
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
    axes          = staticmethod(_axes)
    F_HAS_OPB     = F_HAS_OPB


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
        prog = parse(".default_port mask=0x01 out=0\n")
        self.assertIsInstance(prog.stmts[0], DefaultDecl)
        self.assertEqual(prog.stmts[0].kind, 'port')
        self.assertEqual(prog.stmts[0].args, {'mask': 1, 'out': 0})

    def test_simple_instruction(self):
        prog = parse("ADD .port mask=0x01 out=0 .imm16 5\n")
        inst = prog.stmts[0]
        self.assertIsInstance(inst, Instruction)
        self.assertEqual(inst.mnemonic, 'ADD')
        self.assertEqual(inst.flags, set())
        self.assertEqual(len(inst.eh_list), 2)
        self.assertEqual(inst.eh_list[0].kind, 'port')
        self.assertEqual(inst.eh_list[1].kind, 'imm16')
        self.assertEqual(inst.eh_list[1].args, {'_pos': [5]})

    def test_instruction_with_flags(self):
        prog = parse("MATMUL opb .port mask=0x01 out=0 .opref\n")
        inst = prog.stmts[0]
        self.assertEqual(inst.flags, {'opb'})

    def test_subscript_parsing(self):
        prog = parse("EINSUM opb .port mask=1 out=0 "
                     ".subscript A=i,j B=j,k O=i,k .opref\n")
        sub = prog.stmts[0].eh_list[1]
        self.assertEqual(sub.kind, 'subscript')
        self.assertEqual(sub.args['A'], ['i', 'j'])
        self.assertEqual(sub.args['B'], ['j', 'k'])
        self.assertEqual(sub.args['O'], ['i', 'k'])

    def test_label(self):
        prog = parse("loop:\nADD .port mask=1 out=0 .imm16 1\n")
        self.assertEqual(prog.stmts[0].name, 'loop')


# =============================================================================
# Stage 2 — alias resolution
# =============================================================================

class TestAliasPass(unittest.TestCase):

    def test_resolves_kw_arg(self):
        prog = parse(".alias port_a 0x01\n"
                     "ADD .port mask=port_a out=0 .imm16 5\n")
        out = alias_pass(prog)
        # AliasDecl is consumed; only Instruction remains.
        self.assertEqual(len(out.stmts), 1)
        port_eh = out.stmts[0].eh_list[0]
        self.assertEqual(port_eh.args['mask'], 1)

    def test_undefined_alias_raises(self):
        prog = parse("ADD .port mask=undefined_alias out=0 .imm16 5\n")
        # Note: at the parser stage we don't know it's an alias yet — it's
        # treated as a string. The encoder-level check fires.
        with self.assertRaises(AssemblerError):
            assemble("ADD .port mask=undefined_alias out=0 .imm16 5\n")

    def test_subscript_labels_are_not_resolved(self):
        # `i, j` are subscript labels, not aliases — must survive alias_pass.
        prog = parse(".alias i 99\n"
                     "EINSUM opb .port mask=1 out=0 "
                     ".subscript A=i,j B=j,k O=i,k .opref\n")
        out = alias_pass(prog)
        sub = out.stmts[0].eh_list[1]
        self.assertEqual(sub.args['A'], ['i', 'j'])


# =============================================================================
# Stage 3 — default fills
# =============================================================================

class TestDefaultPass(unittest.TestCase):

    def test_default_port_filled_when_missing(self):
        prog = parse(".default_port mask=0x01 out=0\n"
                     "ADD .imm16 5\n")
        out = default_pass(alias_pass(prog))
        eh_kinds = [eh.kind for eh in out.stmts[0].eh_list]
        self.assertEqual(eh_kinds, ['port', 'imm16'])

    def test_explicit_port_overrides_default(self):
        prog = parse(".default_port mask=0x01 out=0\n"
                     "ADD .port mask=0x04 out=2 .imm16 5\n")
        out = default_pass(alias_pass(prog))
        port_eh = out.stmts[0].eh_list[0]
        self.assertEqual(port_eh.args, {'mask': 4, 'out': 2})

    def test_nop_does_not_get_default_port(self):
        prog = parse(".default_port mask=0x01 out=0\nNOP\n")
        out = default_pass(alias_pass(prog))
        self.assertEqual(out.stmts[0].eh_list, [])

    def test_default_precision_sets_prec_flag(self):
        prog = parse(".default_precision mode=0x12\n"
                     "FLOOR .port mask=1 out=0\n")
        out = default_pass(alias_pass(prog))
        self.assertIn('prec', out.stmts[0].flags)
        self.assertEqual(out.stmts[0].eh_list[-1].kind, 'precision')

    def test_default_precision_dim_only_sets_dim_ovr(self):
        prog = parse(".default_precision dim=0x05\n"
                     "FLOOR .port mask=1 out=0\n")
        out = default_pass(alias_pass(prog))
        self.assertIn('dim_ovr', out.stmts[0].flags)
        self.assertNotIn('prec', out.stmts[0].flags)

    def test_default_precision_both_sets_both_flags(self):
        prog = parse(".default_precision mode=0x12 dim=0x05\n"
                     "FLOOR .port mask=1 out=0\n")
        out = default_pass(alias_pass(prog))
        self.assertIn('prec', out.stmts[0].flags)
        self.assertIn('dim_ovr', out.stmts[0].flags)


# =============================================================================
# Stage 4 — macro expansion
# =============================================================================

class TestMacroPass(unittest.TestCase):

    def test_reshape_lowers_to_view(self):
        src = ".default_port mask=0x01 out=0\nRESHAPE .from 0x03 .to 0x05\n"
        prog = legality_pass(macro_pass(default_pass(alias_pass(parse(src)))))
        self.assertEqual(len(prog.stmts), 1)
        self.assertEqual(prog.stmts[0].mnemonic, 'VIEW')
        eh_kinds = [eh.kind for eh in prog.stmts[0].eh_list]
        self.assertIn('imm16', eh_kinds)
        self.assertIn('port', eh_kinds)

    def test_reshape_count_mismatch_raises(self):
        src = ".default_port mask=1 out=0\nRESHAPE .from 0x03 .to 0x0A\n"
        # 0x03 → 4 elems; 0x0A = 0b1010 → axis sizes 3,3 → 9 elems
        with self.assertRaises(AssemblerError):
            assemble(src)

    def test_non_macro_passes_through(self):
        src = "ADD .port mask=1 out=0 .imm16 5\n"
        out = macro_pass(default_pass(alias_pass(parse(src))))
        self.assertEqual(out.stmts[0].mnemonic, 'ADD')


# =============================================================================
# Stage 5 — legality
# =============================================================================

class TestLegalityPass(unittest.TestCase):

    def test_unknown_mnemonic_raises(self):
        with self.assertRaises(AssemblerError):
            assemble("FROBNICATE .port mask=1 out=0\n")

    def test_matmul_without_opb_flag_raises(self):
        with self.assertRaises(AssemblerError):
            assemble("MATMUL .port mask=1 out=0 .opref\n")

    def test_matmul_with_subscript_forbidden(self):
        with self.assertRaises(AssemblerError):
            assemble("MATMUL opb .port mask=1 out=0 .opref "
                     ".subscript A=i,j B=j,k O=i,k\n")

    def test_alu_binary_neither_imm_nor_opref_raises(self):
        with self.assertRaises(AssemblerError):
            assemble("ADD .port mask=1 out=0\n")

    def test_alu_binary_both_imm_and_opref_raises(self):
        with self.assertRaises(AssemblerError):
            assemble("ADD opb .port mask=1 out=0 .imm16 5 .opref\n")

    def test_shape_op_without_imm16_raises(self):
        with self.assertRaises(AssemblerError):
            assemble("SQZ .port mask=1 out=0\n")

    def test_prec_flag_without_precision_eh_raises(self):
        with self.assertRaises(AssemblerError):
            assemble("ADD prec .port mask=1 out=0 .imm16 5\n")

    def test_dim_ovr_flag_without_precision_eh_raises(self):
        with self.assertRaises(AssemblerError):
            assemble("ADD dim_ovr .port mask=1 out=0 .imm16 5\n")

    def test_prec_flag_with_precision_eh_passes(self):
        # Should not raise
        assemble("ADD prec .port mask=1 out=0 .imm16 5 .precision mode=0x12\n")

    def test_dim_ovr_flag_with_precision_eh_passes(self):
        # Should not raise
        assemble("ADD dim_ovr .port mask=1 out=0 .imm16 5 .precision dim=0x05\n")


# =============================================================================
# Stage 6 — encoder & roundtrip against test_isa_decoder.encode_instr
# =============================================================================

class TestEncoderRoundtrip(unittest.TestCase):
    """Each test asserts: assemble(HL_text) == encode_instr(...) bits."""

    def _assert_eq(self, asm_text, expected_int):
        got = assemble_one(asm_text)
        self.assertEqual(
            got, expected_int,
            f"\nasm:      0x{got:0104x}\nexpected: 0x{expected_int:0104x}",
        )

    # --- legacy opcodes ----------------------------------------------------

    def test_wave_advance(self):
        self._assert_eq(
            "WADV .port mask=0x01 out=0\n",
            ref.encode_instr(0x01, ref.eh_port(0x01, 0)),
        )

    def test_steer(self):
        self._assert_eq(
            "STEER .port mask=0x01 out=0\n",
            ref.encode_instr(0x02, ref.eh_port(0x01, 0)),
        )

    def test_load_with_mem(self):
        self._assert_eq(
            "LD .port mask=0x01 out=0 .mem offset=0x100\n",
            ref.encode_instr(0x04, ref.eh_port(0x01, 0), ref.eh_mem(0x100)),
        )

    def test_add_with_imm(self):
        self._assert_eq(
            "ADD .port mask=0x01 out=0 .imm16 5\n",
            ref.encode_instr(0x10, ref.eh_port(0x01, 0), ref.eh_imm16(5)),
        )

    def test_add_with_opref(self):
        self._assert_eq(
            "ADD opb .port mask=0x01 out=0 .opref\n",
            ref.encode_instr(0x10, ref.eh_port(0x01, 0), ref.eh_opref(),
                             flags=ref.F_HAS_OPB),
        )

    def test_shift_left(self):
        self._assert_eq(
            "SHL .port mask=0x01 out=0 .imm16 4\n",
            ref.encode_instr(0x17, ref.eh_port(0x01, 0), ref.eh_imm16(4)),
        )

    def test_bits_reverse(self):
        self._assert_eq(
            "BITREV .port mask=0x01 out=0\n",
            ref.encode_instr(0x1F, ref.eh_port(0x01, 0)),
        )

    # --- shape ops ---------------------------------------------------------

    def test_squeeze(self):
        self._assert_eq(
            "SQZ .port mask=0x01 out=0 .imm16 0\n",
            ref.encode_instr(0x20, ref.eh_port(0x01, 0), ref.eh_imm16(0)),
        )

    def test_view(self):
        self._assert_eq(
            "VIEW .port mask=0x01 out=0 .imm16 0x05\n",
            ref.encode_instr(0x22, ref.eh_port(0x01, 0), ref.eh_imm16(0x05)),
        )

    def test_perm_2x2(self):
        self._assert_eq(
            "PERM .port mask=0x01 out=0 .imm16 0x01\n",
            ref.encode_instr(0x23, ref.eh_port(0x01, 0), ref.eh_imm16(1)),
        )

    def test_red_axis_sum(self):
        self._assert_eq(
            "RED .port mask=0x01 out=0 .imm16 0x00\n",
            ref.encode_instr(0x25, ref.eh_port(0x01, 0), ref.eh_imm16(0)),
        )

    # --- tensor ops --------------------------------------------------------

    def test_matmul(self):
        self._assert_eq(
            "MATMUL opb .port mask=0x01 out=0 .opref\n",
            ref.encode_instr(0x30, ref.eh_port(0x01, 0), ref.eh_opref(),
                             flags=ref.F_HAS_OPB),
        )

    def test_einsum_matmul_pattern(self):
        self._assert_eq(
            "EINSUM opb .port mask=0x01 out=0 "
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
            "EINSUM opb .port mask=0x01 out=0 "
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
            ".default_port mask=port_a out=0\n"
            "ADD .imm16 7\n"
        )
        explicit = ref.encode_instr(
            0x10, ref.eh_port(0x01, 0), ref.eh_imm16(7),
        )
        self.assertEqual(with_defaults, explicit)

    def test_reshape_macro_yields_view_bits(self):
        macroed = assemble_one(
            ".default_port mask=0x01 out=0\n"
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
            ".default_port mask=0x01 out=0\n"
            "RESHAPE .from 0x03 .to 0x05\n"
        )
        ll = lower_to_ll(src)
        self.assertIn('VIEW', ll)
        self.assertNotIn('RESHAPE', ll)

    def test_idempotent_on_pure_ll(self):
        src = "ADD .port mask=0x01 out=0 .imm16 5\n"
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
            ".default_port mask=0x01 out=0\n"
            "EINSUM opb .subscript A=i,j B=j,k O=i,k .opref\n"
        )
        self.assertEqual(self._mnemonics(src), ['EINSUM'])

    def test_hw_direct_passthrough_relabeled(self):
        # pq,qr->pr is alpha-equivalent to ij,jk->ik
        src = (
            ".default_port mask=0x01 out=0\n"
            "EINSUM opb .subscript A=p,q B=q,r O=p,r .opref\n"
        )
        self.assertEqual(self._mnemonics(src), ['EINSUM'])

    def test_hw_direct_dot_passthrough(self):
        src = (
            ".default_port mask=0x01 out=0\n"
            "EINSUM opb .subscript A=i B=i O= .opref\n"
        )
        self.assertEqual(self._mnemonics(src), ['EINSUM'])

    def test_lower_ji_jk_to_ik(self):
        # ji,jk->ik needs A transposed before matmul, no other rewriting
        src = (
            ".default_port mask=0x01 out=0\n"
            "EINSUM opb .subscript A=j,i B=j,k O=i,k .opref\n"
        )
        ms = self._mnemonics(src)
        # Expect: PERM A → VIEW A → VIEW B → EINSUM(matmul)
        self.assertEqual(ms, ['PERM', 'VIEW', 'VIEW', 'EINSUM'])

    def test_lower_ij_jk_to_ki(self):
        # output transposed: still a kernel A=ij B=jk so A and B straight,
        # but result needs final PERM
        src = (
            ".default_port mask=0x01 out=0\n"
            "EINSUM opb .subscript A=i,j B=j,k O=k,i .opref\n"
        )
        ms = self._mnemonics(src)
        # PERM A skipped (i,j already correct order for matmul), VIEW A,
        # VIEW B, EINSUM, VIEW result, PERM result.
        self.assertEqual(ms, ['VIEW', 'VIEW', 'EINSUM', 'PERM'])

    def test_lower_4d_3d_einsum(self):
        # ijkl,jkm->iml — the canonical "needs full lowering" example
        src = (
            ".default_port mask=0x01 out=0\n"
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
            ".default_port mask=0x01 out=0\n"
            "EINSUM opb .subscript A=i,i B=k O= .opref .shape i=2 k=2\n"
        )
        with self.assertRaises(AssemblerError):
            assemble(src)

    def test_broadcast_in_o_size_gt_1_raises(self):
        """Non-trivial broadcast (size > 1) requires runtime constant vector
        splat that WT64v1 lacks — must raise with pointer to analysis memo."""
        # Label 'q' in O but not in A or B, size 2 → non-trivial
        src = (
            ".default_port mask=0x01 out=0\n"
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
            ".default_port mask=0x01 out=0\n"
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
            ".default_port mask=0x01 out=0\n"
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
            ".default_port mask=0x01 out=0\n"
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
            ".default_port mask=0x01 out=0\n"
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
            ".default_port mask=0x01 out=0\n"
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
            ".default_port mask=0x01 out=0\n"
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
            ".default_port mask=0x01 out=0\n"
            "EINSUM opb .subscript A=a,b,c,i,j B=a,b,c,j,k O=a,b,c,i,k .opref "
            ".shape a=2 b=2 c=2 i=2 j=2 k=2\n"
        )
        insts = assemble(src)
        opcodes = [(w >> 24) & 0xFF for w in insts]
        self.assertEqual(opcodes, [0x32],
                         f"expected single EINSUM, got {[hex(o) for o in opcodes]}")
        # Verify two SUBSCRIPT EHs are present in the emitted instruction.
        # Walk the chain: base header + PORT + SUBSCRIPT_low + SUBSCRIPT_hi + OPREF.
        val = insts[0]
        words = [(val >> (i * 32)) & 0xFFFFFFFF for i in range(13)]
        # base word 0: next_hdr in [23:20] = 0x1 (PORT)
        self.assertEqual((words[0] >> 20) & 0xF, 0x1, "base.next_hdr must be PORT")
        # PORT (word 1): next_hdr = SUBSCRIPT (0x6)
        self.assertEqual((words[1] >> 12) & 0xF, 0x6, "PORT.next_hdr must be SUBSCRIPT")
        # SUBSCRIPT_low (word 2): next_hdr = SUBSCRIPT (0x6) — chained SUBSCRIPT
        self.assertEqual((words[2] >> 12) & 0xF, 0x6,
                         "first SUBSCRIPT.next_hdr must be SUBSCRIPT (chained multi)")
        self.assertEqual((words[2] >> 8) & 0xF, 0x6, "type must be SUBSCRIPT")
        # SUBSCRIPT_hi (word 4): next_hdr = OPREF (0x7)
        self.assertEqual((words[4] >> 12) & 0xF, 0x7,
                         "second SUBSCRIPT.next_hdr must be OPREF")
        self.assertEqual((words[4] >> 8) & 0xF, 0x6, "type must still be SUBSCRIPT")

    def test_4_batch_dims_still_raises_beyond_v1_3(self):
        """Beyond v1.3 §16: 4 batch axes would give 7-axis A/B/O tensors,
        exceeding _pack_axes_multi's 8-axis limit only if very rank-heavy.
        For `abcdij,abcdjk->abcdik` it's 6 axes / group — encoding fits
        (multi-SUBSCRIPT), BUT signature isn't in
        HW_DIRECT_EINSUM_SIGS_MULTI, so falls through to _lower_einsum_general
        which raises on batched contraction."""
        src = (
            ".default_port mask=0x01 out=0\n"
            "EINSUM opb .subscript A=a,b,c,d,i,j B=a,b,c,d,j,k O=a,b,c,d,i,k "
            ".opref .shape a=2 b=2 c=2 d=2 i=2 j=2 k=2\n"
        )
        with self.assertRaises(AssemblerError):
            assemble(src)

    def test_lowered_matmul_produces_executable_bits(self):
        """The lowered chain must encode through stage 5 / 6 cleanly,
        even if the resulting tensor sizes are above the single-PE limit."""
        src = (
            ".default_port mask=0x01 out=0\n"
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
            ".default_port mask=port_a out=0\n"
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
            ".default_port mask=0x01 out=0\n"
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
            ".default_port mask=0x01 out=0\n"
            "BATCHNORM_INFER opb .k2 0xAAAA\n"
        )
        with self.assertRaises(wta.AssemblerError) as ctx:
            wta.assemble(src)
        self.assertIn('k1', str(ctx.exception))

    def test_rmsnorm_expansion(self):
        """RMSNORM → 4-primitive chain: EINSUM(L2SQ)+SCALAR_RSQRT+MUL_WIDE_SCALAR+MUL_WIDE_VEC.
        v1.6.7: scale mul now uses Q8.8 (0x69), not Q4.4 (0x67)."""
        src = (
            ".default_port mask=0x01 out=0\n"
            "RMSNORM opb .gamma 0xDEAD_BEEF_CAFE_BABE\n"
        )
        insts = wta.assemble(src)
        opcodes = [(w >> 24) & 0xFF for w in insts]
        self.assertEqual(opcodes, [0x32, 0x66, 0x69, 0x65],
                         f"expected [EINSUM=0x32, SCALAR_RSQRT=0x66, MUL_WIDE_Q8_8_SCALAR=0x69, MUL_WIDE_VEC=0x65], got {[hex(o) for o in opcodes]}")

    def test_layernorm_expansion(self):
        """LAYERNORM → 8-primitive chain per §22.3/§22.16 (v1.6.5c:
        CACHE_LOAD_WIDE reload of step 2's cached xc instead of re-
        emission; v1.6.7: scale mul now uses Q8.8 (0x69), not Q4.4 (0x67))."""
        src = (
            ".default_port mask=0x01 out=0\n"
            "LAYERNORM opb .gamma 0x1111_2222_3333_4444 "
            ".beta 0x5555_6666_7777_8888\n"
        )
        insts = wta.assemble(src)
        opcodes = [(w >> 24) & 0xFF for w in insts]
        # Expected sequence: EINSUM(MEAN), SUB_VEC, EINSUM(L2SQ), RSQRT,
        # CACHE_LOAD_WIDE (v1.6.5c reload), MUL_Q8_8_SCALAR (v1.6.7), MUL_VEC, ADD_VEC
        expected = [0x32, 0x64, 0x32, 0x66, 0x68, 0x69, 0x65, 0x63]
        self.assertEqual(opcodes, expected,
                         f"expected {[hex(o) for o in expected]}, got {[hex(o) for o in opcodes]}")

    def test_layernorm_step5_cache_load_wide_precision_guard(self):
        """v1.6.5c §22.16 tag-stability: step 5 (CACHE_LOAD_WIDE) must carry
        a .precision dim=0x55 EH + dim_ovr flag, pinning its dispatch tag's
        dim_sizes to match step 2's stored producer tag (which inherits
        0x55 from step 1's OP_MEAN) independent of step 4's SCALAR_RSQRT
        hardcoding its own output dim_sizes to 0x00."""
        src = (
            ".default_port mask=0x01 out=0\n"
            "LAYERNORM opb .gamma 0x1111_2222_3333_4444 "
            ".beta 0x5555_6666_7777_8888\n"
        )
        insts = wta.assemble(src)
        step5 = insts[4]
        opcode = (step5 >> 24) & 0xFF
        self.assertEqual(opcode, 0x68)
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
            ".default_port mask=0x01 out=0\n"
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
        # LAYERNORM call, via the real _lower_layernorm().
        steps = wta._lower_layernorm(layernorm_call)
        step5 = steps[4]
        self.assertEqual(step5.mnemonic, 'CACHE_LOAD_WIDE')
        step5_prec = next(eh for eh in step5.eh_list if eh.kind == 'precision')
        self.assertEqual(prec_eh.args['dim'], step5_prec.args['dim'],
                         "abort-cleanup dim literal diverged from step 5's")
        self.assertEqual('dim_ovr' in cleanup_inst.flags, 'dim_ovr' in step5.flags)

    def test_layernorm_abort_cleanup_assembles_to_frag_inval(self):
        """The abort-cleanup instruction must actually assemble (legality-
        pass + encode) to opcode 0x6A, end to end through encode_pass."""
        src = (
            ".default_port mask=0x01 out=0\n"
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
            ".default_port mask=0x01 out=0\n"
            "LAYERNORM opb .gamma 0xAAAA\n"
        )
        with self.assertRaises(wta.AssemblerError) as ctx:
            wta.assemble(src)
        self.assertIn('beta', str(ctx.exception))

    def test_primitive_simd_add_wide_scalar_legality(self):
        """SIMD_ADD_WIDE_SCALAR: binary-ALU (IMM XOR OPREF)."""
        src = (
            ".default_port mask=0x01 out=0\n"
            "SIMD_ADD_WIDE_SCALAR .imm16 5\n"
        )
        insts = wta.assemble(src)
        self.assertEqual((insts[0] >> 24) & 0xFF, 0x60)

    def test_primitive_scalar_rsqrt_legality(self):
        """SCALAR_RSQRT: pure unary, no imm/opref."""
        src = (
            ".default_port mask=0x01 out=0\n"
            "SCALAR_RSQRT\n"
        )
        insts = wta.assemble(src)
        self.assertEqual((insts[0] >> 24) & 0xFF, 0x66)

    def test_primitive_scalar_rsqrt_rejects_imm(self):
        """SCALAR_RSQRT with .imm16 must raise (pure unary)."""
        src = (
            ".default_port mask=0x01 out=0\n"
            "SCALAR_RSQRT .imm16 5\n"
        )
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(src)

    def test_primitive_simd_mul_wide_q4_4_scalar_legality(self):
        """v1.6.5a: SIMD_MUL_WIDE_Q4_4_SCALAR (0x67) — same legality as
        SIMD_MUL_WIDE_SCALAR (binary-ALU IMM XOR OPREF)."""
        src = (
            ".default_port mask=0x01 out=0\n"
            "SIMD_MUL_WIDE_Q4_4_SCALAR .imm16 0x18\n"   # Q4.4 = 1.5
        )
        insts = wta.assemble(src)
        self.assertEqual((insts[0] >> 24) & 0xFF, 0x67)

    def test_primitive_simd_mul_wide_q8_8_scalar_legality(self):
        """v1.6.7: SIMD_MUL_WIDE_Q8_8_SCALAR (0x69) — same legality as
        SIMD_MUL_WIDE_SCALAR (binary-ALU IMM XOR OPREF); full 16-bit IMM16
        maps directly onto the Q8.8 B operand (dec_eff_b_value[15:0])."""
        src = (
            ".default_port mask=0x01 out=0\n"
            "SIMD_MUL_WIDE_Q8_8_SCALAR .imm16 0x0180\n"   # Q8.8 = 1.5
        )
        insts = wta.assemble(src)
        self.assertEqual((insts[0] >> 24) & 0xFF, 0x69)

    def test_primitive_cache_load_wide_legality(self):
        """v1.6.5c §22.16: CACHE_LOAD_WIDE (0x68) — pure Cluster-buffer CAM
        passthrough, no B operand (mirrors SCALAR_RSQRT's no-data-EH
        shape). A .precision EH is legal (not in _ALL_DATA_EHS)."""
        src = (
            ".default_port mask=0x01 out=0\n"
            "CACHE_LOAD_WIDE .precision dim=0x55\n"
        )
        insts = wta.assemble(src)
        self.assertEqual((insts[0] >> 24) & 0xFF, 0x68)

    def test_primitive_cache_load_wide_rejects_imm(self):
        """CACHE_LOAD_WIDE with .imm16 must raise (no B operand at all)."""
        src = (
            ".default_port mask=0x01 out=0\n"
            "CACHE_LOAD_WIDE .imm16 5\n"
        )
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(src)

    def test_primitive_cache_load_wide_dim_ovr_requires_precision_eh(self):
        """dim_ovr flag without a .precision EH must raise at compile time
        (mirrors the existing prec/dim_ovr-without-EH check)."""
        src = (
            ".default_port mask=0x01 out=0\n"
            "CACHE_LOAD_WIDE dim_ovr\n"
        )
        with self.assertRaises(wta.AssemblerError) as ctx:
            wta.assemble(src)
        self.assertIn('dim_ovr', str(ctx.exception))

    def test_primitive_frag_inval_legality(self):
        """v1.6.5d §22.17: FRAG_INVAL (0x6A) — explicit Cluster-buffer
        slot invalidate-by-tag, same no-B shape as 0x66/0x68."""
        src = (
            ".default_port mask=0x01 out=0\n"
            "FRAG_INVAL\n"
        )
        insts = wta.assemble(src)
        self.assertEqual((insts[0] >> 24) & 0xFF, 0x6A)

    def test_primitive_frag_inval_rejects_imm(self):
        """FRAG_INVAL with .imm16 must raise (no B operand at all)."""
        src = (
            ".default_port mask=0x01 out=0\n"
            "FRAG_INVAL .imm16 5\n"
        )
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(src)

    def test_primitive_widen_legality(self):
        """v1.7 §22.18: SIMD_MUL_WIDE_Q4_4_SCALAR_128_WIDEN (0x6B) — same
        ALU-binary (IMM XOR OPREF) shape as 0x67/0x69."""
        src = (
            ".default_port mask=0x01 out=0\n"
            "SIMD_MUL_WIDE_Q4_4_SCALAR_128_WIDEN .imm16 0x08\n"
        )
        insts = wta.assemble(src)
        self.assertEqual((insts[0] >> 24) & 0xFF, 0x6B)

    def test_primitive_widen_requires_imm_xor_opref(self):
        """WIDEN with neither IMM nor OPREF must raise."""
        src = (
            ".default_port mask=0x01 out=0\n"
            "SIMD_MUL_WIDE_Q4_4_SCALAR_128_WIDEN\n"
        )
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(src)

    def test_primitive_requantize_legality(self):
        """v1.7 §22.18: SIMD_REQUANTIZE_Q4_4_TO_INT4 (0x6C) — no B
        operand at all, same no-data-EH shape as 0x66/0x68/0x6A (NOT the
        ALU-binary shape 0x6B uses)."""
        src = (
            ".default_port mask=0x01 out=0\n"
            "SIMD_REQUANTIZE_Q4_4_TO_INT4\n"
        )
        insts = wta.assemble(src)
        self.assertEqual((insts[0] >> 24) & 0xFF, 0x6C)

    def test_primitive_requantize_rejects_imm_and_opref(self):
        """REQUANTIZE with .imm16 or .opref must raise (no B operand)."""
        src_imm = (
            ".default_port mask=0x01 out=0\n"
            "SIMD_REQUANTIZE_Q4_4_TO_INT4 .imm16 5\n"
        )
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(src_imm)
        src_opref = (
            ".default_port mask=0x01 out=0\n"
            "SIMD_REQUANTIZE_Q4_4_TO_INT4 opb .opref\n"
        )
        with self.assertRaises(wta.AssemblerError):
            wta.assemble(src_opref)

    def test_widen_requantize_opcode_table_matches_hardware(self):
        """v1.7 §22.18: direct regression guard against the exact class
        of asm.py-vs-EHDecode.v drift that silently broke 0x63/64/65
        previously (wt64v1_spec.md §22.16.0) -- pins the opcode numbers
        and legality shapes asm.py assigns to WIDEN/REQUANTIZE."""
        self.assertEqual(wta.MNEMONIC_TO_OPCODE['SIMD_MUL_WIDE_Q4_4_SCALAR_128_WIDEN'], 0x6B)
        self.assertEqual(wta.MNEMONIC_TO_OPCODE['SIMD_REQUANTIZE_Q4_4_TO_INT4'], 0x6C)
        widen_rules = wta._LEGAL[0x6B]
        self.assertTrue(widen_rules['allow_imm_xor_opref'])
        self.assertEqual(widen_rules['forbidden'], {'subscript', 'mem'})
        requantize_rules = wta._LEGAL[0x6C]
        self.assertFalse(requantize_rules['allow_imm_xor_opref'])
        self.assertEqual(requantize_rules['forbidden'], wta._ALL_DATA_EHS)


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
        # Invalid wide_bits raises
        with self.assertRaises(wta.AssemblerError):
            wta.wave_fragments(0, 96)   # not in {0,64,128,192,256}
        with self.assertRaises(wta.AssemblerError):
            wta.wave_fragments(0, 512)  # too large

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
            code=0x7A, mnemonic="GHOST", legal_dtypes=[4],
            legal_acc=[1], legal_rnd=[0]))              # fp op w/o opcodes[] row
        with self.assertRaises(gen.SchemaError):
            gen.validate(bad)

    def test_legacy_legality_snapshot_equivalence(self):
        """Frozen literal snapshot of all 57 legacy ops' legality shapes,
        transcribed ONCE from pre-migration HEAD (042f08e) — the migration
        gate. Kept forever as the third independent leg (hand-pinned
        literal <- generated table -> JSON source). Compares exact set
        CONTENTS and key/value TYPES."""
        # New (post-0x6C) opcodes may be ADDED (v1.8.0a COMMIT 2 fp block);
        # the frozen 57 legacy keys must all still exist unchanged.
        self.assertTrue(set(_PREMIGRATION_LEGAL_SNAPSHOT) <= set(wta._LEGAL),
                        "a frozen legacy opcode disappeared from _LEGAL")
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
    """v1.8.0a COMMIT 2 §23.6a — FP-block (0x70-0x7F) mode-byte legality.

    The spec-row pins below are transcribed character-for-character from
    the NORMATIVE §23.6a table, which landed and was reviewed in a
    SEPARATE prior commit (042f08e) — a genuinely independent anchor, not
    a same-author-same-commit circular check.
    """

    _FP_OPS = {
        0x70: 'VFMA_ACC', 0x71: 'VDOT_ACC', 0x72: 'ACC_REDUCE',
        0x73: 'ACC_ELEMWISE', 0x74: 'FSCALAR', 0x75: 'FRSQRT32',
        0x76: 'FEXP2_32', 0x77: 'CVT', 0x78: 'DEQUANT', 0x79: 'FMINMAX',
        0x7C: 'STORE_QUANT', 0x7D: 'ACC_SPILL_FILL', 0x7E: 'FP_ACC_CTRL',
    }

    def test_fp_block_opcode_pins(self):
        """All 13 mnemonic->opcode literal pins — catches careless JSON
        renumbering that regen-and-diff structurally cannot."""
        from generated_isa_tables import FP_MODE_LEGAL, STUB_OPS_V18
        for code, mnem in self._FP_OPS.items():
            self.assertEqual(wta.MNEMONIC_TO_OPCODE[mnem], code)
        self.assertEqual(set(FP_MODE_LEGAL), set(self._FP_OPS))
        # v1.8.0b: 0x71 VDOT_ACC / 0x72 ACC_REDUCE / 0x7C STORE_QUANT
        # graduated from stubs to real datapaths.
        self.assertEqual(STUB_OPS_V18,
                         frozenset(self._FP_OPS) - {0x71, 0x72, 0x7C})
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
        SPEC_ROWS = {
            0x70: [0, 1], 0x71: [0, 1], 0x72: [0, 1], 0x73: [4],
            0x74: [4], 0x75: [4], 0x76: [4], 0x77: [2, 3], 0x78: [0, 1],
            0x79: [4], 0x7C: [0, 1, 2, 3], 0x7D: [4], 0x7E: [4],
        }
        for code, dtypes in SPEC_ROWS.items():
            self.assertEqual(FP_MODE_LEGAL[code]['legal_dtypes'], dtypes,
                             f"0x{code:02X} dtype row diverged from spec §23.6a")
        total = sum(len(l['legal_dtypes']) * len(l['legal_acc']) * len(l['legal_rnd'])
                    for l in FP_MODE_LEGAL.values())
        self.assertEqual(total, 21, "legal-row count diverged from spec §23.6a")

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
                wta.assemble(f".default_port mask=0x01 out=0\n{mnem}{scaffold}\n")

    def test_asm_mode_check_equivalence_with_golden_table(self):
        """Exhaustive 13x256: assembler accept <=> FP_MODE_LEGAL legal.
        Catches implementation bugs in legality_pass's bit split (the RTL
        sweep separately validates ROM == FP_MODE_LEGAL, so together these
        machine-check asm-legal ⊆ RTL-legal)."""
        from generated_isa_tables import FP_MODE_LEGAL
        for code, mnem in self._FP_OPS.items():
            legal = FP_MODE_LEGAL[code]
            scaffold = ''
            if wta._LEGAL[code]['allow_imm_xor_opref']:
                scaffold = ' .imm16 1'
            elif 'mem' in wta._LEGAL[code]['required']:
                scaffold = ' .mem offset=0'
            for mode in range(256):
                dtype, acc, rnd = mode & 0xF, (mode >> 4) & 0x3, (mode >> 6) & 0x3
                expect_ok = (dtype in legal['legal_dtypes']
                             and acc in legal['legal_acc']
                             and rnd in legal['legal_rnd'])
                src = (f".default_port mask=0x01 out=0\n"
                       f"{mnem} prec{scaffold} .precision mode={mode}\n")
                if expect_ok:
                    wta.assemble(src)   # must not raise
                else:
                    with self.assertRaises(wta.AssemblerError,
                                           msg=f"{mnem} mode=0x{mode:02X}"):
                        wta.assemble(src)
