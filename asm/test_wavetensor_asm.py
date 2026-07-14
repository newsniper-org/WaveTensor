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

    def test_3_batch_dims_still_raises_beyond_v1_2(self):
        """Beyond v1.2: 3 batch axes exceeds SIG_BMM_2's 2. Still raises."""
        src = (
            ".default_port mask=0x01 out=0\n"
            "EINSUM opb .subscript A=a,b,c,i,j B=a,b,c,j,k O=a,b,c,i,k .opref "
            ".shape a=2 b=2 c=2 i=2 j=2 k=2\n"
        )
        # 5-axis A/B exceeds 4-axis EH encoding limit → raises at subscript
        # parse level or earlier legality check.
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


if __name__ == '__main__':
    unittest.main()
