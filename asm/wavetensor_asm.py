# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

"""WaveTensor assembler — high-level / low-level / machine-code lowering.

Levels
------
* **Low-level (LL)** — every statement maps **1:1** to a TLV-encoded
  machine instruction. No macros, no aliases, no implicit defaults. Reading
  a single LL line tells you exactly which bytes go on the bus.
* **High-level (HL)** — strict superset of LL. Adds:

      .alias name  value          – symbolic constant
      .default_port mask=N out=N  – auto-insert PORT EH where missing
      .default_precision mode=N   – auto-insert PRECISION EH + flag
      RESHAPE  .from N  .to N     – macro lowering to VIEW
      (future) RESHAPE/PERMUTE for non-PE-local shapes
      labels (`name:`) for branch targets (HW support pending)

  Every LL program is a valid HL program, i.e. running the HL pipeline on
  an LL source must return identical bytes.

Lowering pipeline
-----------------
The pipeline is a sequence of pure functions. Each consumes an AST and
returns an AST that is closer to LL (or, for `encode_pass`, the final
machine code list).

    Stage 1   parse           text     →  AST
    Stage 2   alias_pass      AST      →  AST  (alias names resolved)
    Stage 3   default_pass    AST      →  AST  (defaults filled in)
    Stage 4   macro_pass      AST      →  AST  (HL macros expanded)
    Stage 5   legality_pass   AST      →  AST  (errors raised on illegal
                                                 instructions; AST unchanged
                                                 if all OK)
    Stage 6   encode_pass     AST      →  List[int]  (each int is a 416-bit
                                                       instruction word)

The 416-bit integers produced by `encode_pass` are bit-identical to what
`test_isa_decoder.py:encode_instr(...)` emits, so the same bytes drive the
ISA_Decoder.v RTL.

Typical use
-----------
    >>> from wavetensor_asm import assemble
    >>> insts = assemble('''
    ...     .alias port_a 0x01
    ...     .default_port mask=port_a out=0
    ...     ADD .imm16 5
    ... ''')
    >>> hex(insts[0])
    '0x...'

Entry points
------------
    assemble(text)             → List[int]   (machine code)
    lower_to_ll(text)          → str         (lowered LL pretty-printed)
    parse / alias_pass / ...   → low-level pipeline access
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set, Tuple, Union

# =============================================================================
# Section 1 — Mnemonics, EH catalogue, flag bits, encoding constants
# =============================================================================

MNEMONIC_TO_OPCODE: Dict[str, int] = {
    'NOP':    0x00,  'WADV':   0x01,  'STEER':  0x02,  'MERGE':  0x03,
    'LD':     0x04,  'ST':     0x05,
    'ADD':    0x10,  'SUB':    0x11,  'MUL':    0x12,  'DIV':    0x13,
    'AND':    0x14,  'OR':     0x15,  'XOR':    0x16,
    'SHL':    0x17,  'SHR':    0x18,  'SAR':    0x19,  'ROR':    0x1A,
    'NEG':    0x1B,  'REM':    0x1C,  'DIVREM': 0x1D,  'ROL':    0x1E,
    'BITREV': 0x1F,
    'NOT':    0x50,  'NAND':   0x51,  'NOR':    0x52,  'XNOR':   0x53,
    'POPCNT': 0x54,  'CLZ':    0x55,  'CTZ':    0x56,
    'SQZ':    0x20,  'USQZ':   0x21,  'VIEW':   0x22,  'PERM':   0x23,
    'BCAST':  0x24,  'RED':    0x25,  'SPLAT':  0x26,  # v1.1 amendment
    'MATMUL': 0x30,  'TADD':   0x31,  'EINSUM': 0x32,
    'FLOOR':  0x40,  'ROUND':  0x41,  'CEIL':   0x42,  'ENORM':  0x43,
    'CONJ':   0x44,
    # v1.6.1b §22 — SIMD broadcast wide-consumer opcodes (RISC-ish norm).
    'SIMD_ADD_WIDE_SCALAR': 0x60, 'SIMD_SUB_WIDE_SCALAR': 0x61,
    'SIMD_MUL_WIDE_SCALAR': 0x62,
    'SIMD_ADD_WIDE_VEC':    0x63, 'SIMD_SUB_WIDE_VEC':    0x64,
    'SIMD_MUL_WIDE_VEC':    0x65,
    # v1.6.1b §22 — Scalar transcendental (rsqrt approximation).
    'SCALAR_RSQRT':         0x66,
}
OPCODE_TO_MNEMONIC: Dict[int, str] = {v: k for k, v in MNEMONIC_TO_OPCODE.items()}

# HL-only mnemonics (macro expansions take care of these)
# v1.6.4 §22.11 — RISC-ish normalization macros (SDK compositional decomp).
HL_ONLY_MNEMONICS = {'RESHAPE', 'BATCHNORM_INFER', 'RMSNORM', 'LAYERNORM'}

# Flag mnemonic → bit position in the base header's 4-bit `flags` field
FLAG_BITS: Dict[str, int] = {
    'opb':       3,  # F_HAS_OPB           — second operand on input_payload_b
    'prec':      2,  # F_PRECISION_OVR    — PRECISION EH overrides precision_mode
    'mem_hint':  1,  # F_MEM               — opcode performs memory access
    'dim_ovr':   0,  # F_DIM_OVR          — PRECISION EH overrides dim_sizes
}

# EH type codes (must mirror ISA_Decoder.v)
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

EH_NAME_TO_CODE: Dict[str, int] = {
    'port':       EH_PORT,
    'imm16':      EH_IMM16,
    'imm32':      EH_IMM32,
    'imm64':      EH_IMM64,
    'mem':        EH_MEM,
    'subscript':  EH_SUBSCRIPT,
    'opref':      EH_OPREF,
    'precision':  EH_PRECISION,
    'nop_pad':    EH_NOP_PAD,
}

# Reduce-op codes embedded in RED .imm16[7:4]
REDUCE_OP_CODE: Dict[str, int] = {'sum': 0, 'max': 1, 'min': 2}

INSTR_WORDS_REAL = 13
INSTR_WIDTH_BITS = INSTR_WORDS_REAL * 32   # = 416


# =============================================================================
# Section 2 — AST node types
# =============================================================================

@dataclass
class Token:
    kind: str
    value: str
    line: int


@dataclass
class ExtensionHeader:
    """Generic EH AST node. `kind` is the directive name (e.g. 'port',
    'imm16', 'subscript'). `args` carries kw=value pairs and/or a positional
    list under the special `_pos` key."""
    kind: str
    args: Dict[str, Union[int, str, list]] = field(default_factory=dict)
    line: int = 0


@dataclass
class Instruction:
    mnemonic: str
    flags: Set[str] = field(default_factory=set)
    eh_list: List[ExtensionHeader] = field(default_factory=list)
    line: int = 0


@dataclass
class AliasDecl:
    name: str
    value: int
    line: int = 0


@dataclass
class DefaultDecl:
    kind: str  # 'port' | 'precision'
    args: Dict[str, int] = field(default_factory=dict)
    line: int = 0


@dataclass
class Label:
    name: str
    line: int = 0


Statement = Union[AliasDecl, DefaultDecl, Label, Instruction]


@dataclass
class Program:
    stmts: List[Statement] = field(default_factory=list)


# =============================================================================
# Section 3 — Stage 1: lexer + parser  (text → AST)
# =============================================================================

_TOKEN_PATTERNS = [
    ('COMMENT',  r'\#[^\n]*'),
    ('NEWLINE',  r'\n'),
    ('SKIP',     r'[ \t\r]+'),
    ('NUM_HEX',  r'0[xX][0-9a-fA-F]+'),
    ('NUM_DEC',  r'-?[0-9]+'),
    ('IDENT',    r'[A-Za-z_][A-Za-z_0-9]*'),
    ('DOT',      r'\.'),
    ('EQ',       r'='),
    ('COMMA',    r','),
    ('COLON',    r':'),
]
_TOKEN_RE = re.compile('|'.join(f'(?P<{n}>{p})' for n, p in _TOKEN_PATTERNS))


class AssemblerError(Exception):
    """Raised for any HL/LL syntactic or semantic problem the assembler
    detects before binary emission."""


def tokenize(src: str) -> List[Token]:
    tokens: List[Token] = []
    line = 1
    pos = 0
    while pos < len(src):
        m = _TOKEN_RE.match(src, pos)
        if not m:
            raise AssemblerError(f"line {line}: unexpected character {src[pos]!r}")
        kind = m.lastgroup
        value = m.group()
        pos = m.end()
        if kind in ('SKIP', 'COMMENT'):
            continue
        if kind == 'NEWLINE':
            tokens.append(Token('NEWLINE', '\\n', line))
            line += 1
            continue
        tokens.append(Token(kind, value, line))
    tokens.append(Token('EOF', '', line))
    return tokens


class _Parser:
    def __init__(self, tokens: List[Token]) -> None:
        self.tokens = tokens
        self.pos = 0

    def peek(self, offset: int = 0) -> Token:
        return self.tokens[self.pos + offset]

    def at(self, kind: str) -> bool:
        return self.peek().kind == kind

    def eat(self, kind: Optional[str] = None) -> Token:
        tok = self.tokens[self.pos]
        if kind is not None and tok.kind != kind:
            raise AssemblerError(
                f"line {tok.line}: expected {kind}, got {tok.kind} "
                f"({tok.value!r})"
            )
        self.pos += 1
        return tok

    def eat_optional_newline(self) -> None:
        if self.at('NEWLINE'):
            self.eat()

    def parse_value(self) -> Union[int, str]:
        tok = self.peek()
        if tok.kind == 'NUM_HEX':
            self.eat()
            return int(tok.value, 16)
        if tok.kind == 'NUM_DEC':
            self.eat()
            return int(tok.value, 10)
        if tok.kind == 'IDENT':
            self.eat()
            return tok.value  # alias to be resolved later
        raise AssemblerError(
            f"line {tok.line}: expected value, got {tok.kind} ({tok.value!r})"
        )

    def parse_program(self) -> Program:
        prog = Program()
        while not self.at('EOF'):
            while self.at('NEWLINE'):
                self.eat()
            if self.at('EOF'):
                break
            stmt = self.parse_stmt()
            if stmt is not None:
                prog.stmts.append(stmt)
        return prog

    def parse_stmt(self) -> Optional[Statement]:
        tok = self.peek()
        if tok.kind == 'DOT':
            return self.parse_directive()
        if tok.kind == 'IDENT':
            nxt = self.peek(1)
            if nxt.kind == 'COLON':
                line = tok.line
                name = self.eat('IDENT').value
                self.eat('COLON')
                self.eat_optional_newline()
                return Label(name=name, line=line)
            return self.parse_instruction()
        raise AssemblerError(
            f"line {tok.line}: unexpected token {tok.kind} ({tok.value!r})"
        )

    def parse_directive(self) -> Statement:
        line = self.peek().line
        self.eat('DOT')
        name = self.eat('IDENT').value
        if name == 'alias':
            alias_name = self.eat('IDENT').value
            value = self.parse_value()
            self.eat_optional_newline()
            return AliasDecl(name=alias_name, value=value, line=line)
        if name in ('default_port', 'default_precision'):
            args = self._parse_kw_args()
            self.eat_optional_newline()
            return DefaultDecl(
                kind=name[len('default_'):],
                args=args, line=line,
            )
        raise AssemblerError(f"line {line}: unknown top-level directive .{name}")

    def parse_instruction(self) -> Instruction:
        line = self.peek().line
        mnemonic = self.eat('IDENT').value
        inst = Instruction(mnemonic=mnemonic, line=line)
        # Bare-IDENT flags (must be in FLAG_BITS) — appear before any EH
        while self.at('IDENT'):
            name = self.peek().value
            if name in FLAG_BITS:
                self.eat()
                inst.flags.add(name)
            else:
                raise AssemblerError(
                    f"line {self.peek().line}: unknown flag/operand {name!r} "
                    f"(known flags: {sorted(FLAG_BITS)})"
                )
        while self.at('DOT'):
            inst.eh_list.append(self.parse_eh())
        self.eat_optional_newline()
        return inst

    def parse_eh(self) -> ExtensionHeader:
        line = self.peek().line
        self.eat('DOT')
        name = self.eat('IDENT').value
        eh = ExtensionHeader(kind=name, line=line)
        if name == 'subscript':
            eh.args = self._parse_subscript_args()
        elif name in ('port', 'mem', 'opref', 'precision', 'shape'):
            eh.args = self._parse_kw_args()
        else:
            eh.args = self._parse_pos_or_kw_args()
        return eh

    def _parse_kw_args(self) -> Dict[str, Union[int, str]]:
        args: Dict[str, Union[int, str]] = {}
        while self.peek().kind == 'IDENT' and self.peek(1).kind == 'EQ':
            key = self.eat('IDENT').value
            self.eat('EQ')
            args[key] = self.parse_value()
        return args

    def _parse_pos_or_kw_args(self) -> Dict[str, Union[int, str, list]]:
        args: Dict[str, Union[int, str, list]] = {}
        positional: List[Union[int, str]] = []
        while self.peek().kind in ('NUM_HEX', 'NUM_DEC', 'IDENT'):
            if self.peek().kind == 'IDENT' and self.peek(1).kind == 'EQ':
                key = self.eat('IDENT').value
                self.eat('EQ')
                args[key] = self.parse_value()
            else:
                positional.append(self.parse_value())
        if positional:
            args['_pos'] = positional
        return args

    def _parse_subscript_args(self) -> Dict[str, list]:
        # Format:  A=i,j,k   B=j,k,m   O=i,m,l
        args: Dict[str, list] = {}
        while self.peek().kind == 'IDENT' and self.peek(1).kind == 'EQ':
            key = self.eat('IDENT').value
            self.eat('EQ')
            labels: List[str] = []
            while self.peek().kind == 'IDENT' and self.peek(1).kind != 'EQ':
                labels.append(self.eat('IDENT').value)
                if self.at('COMMA'):
                    self.eat('COMMA')
                else:
                    break
            args[key] = labels
        return args


def parse(src: str) -> Program:
    """Stage 1 — text → AST."""
    return _Parser(tokenize(src)).parse_program()


# =============================================================================
# Section 4 — Stage 2: alias resolution
# =============================================================================

def _resolve_value(v, aliases):
    if isinstance(v, str) and v in aliases:
        return aliases[v]
    if isinstance(v, list):
        return [aliases[x] if isinstance(x, str) and x in aliases else x for x in v]
    return v


def alias_pass(prog: Program) -> Program:
    """Stage 2 — resolve `.alias` declarations.

    Replaces alias name strings inside instruction EH args (and inside
    `.default_*` decl args) with their numeric values. Subscript label
    lists, which use single-letter labels by convention, are left alone."""
    aliases: Dict[str, int] = {}
    out_stmts: List[Statement] = []
    for stmt in prog.stmts:
        if isinstance(stmt, AliasDecl):
            value = stmt.value
            if isinstance(value, str):
                if value not in aliases:
                    raise AssemblerError(
                        f"line {stmt.line}: alias {value!r} used before defined"
                    )
                value = aliases[value]
            aliases[stmt.name] = value
            continue
        if isinstance(stmt, Instruction):
            new_ehs: List[ExtensionHeader] = []
            for eh in stmt.eh_list:
                if eh.kind == 'subscript':
                    new_ehs.append(eh)
                    continue
                new_args = {k: _resolve_value(v, aliases) for k, v in eh.args.items()}
                new_ehs.append(ExtensionHeader(kind=eh.kind, args=new_args, line=eh.line))
            out_stmts.append(Instruction(
                mnemonic=stmt.mnemonic, flags=set(stmt.flags),
                eh_list=new_ehs, line=stmt.line,
            ))
        elif isinstance(stmt, DefaultDecl):
            new_args = {k: _resolve_value(v, aliases) for k, v in stmt.args.items()}
            out_stmts.append(DefaultDecl(kind=stmt.kind, args=new_args, line=stmt.line))
        else:
            out_stmts.append(stmt)
    return Program(stmts=out_stmts)


# =============================================================================
# Section 5 — Stage 3: default fills
# =============================================================================

def default_pass(prog: Program) -> Program:
    """Stage 3 — apply `.default_port` and `.default_precision` to every
    instruction that doesn't already carry the corresponding EH.

    The defaults are scoped: they apply to all instructions that follow the
    declaration until either the end of the program or a re-declaration."""
    default_port: Optional[Dict[str, int]] = None
    default_prec: Optional[Dict[str, int]] = None
    out_stmts: List[Statement] = []
    for stmt in prog.stmts:
        if isinstance(stmt, DefaultDecl):
            if stmt.kind == 'port':
                default_port = dict(stmt.args)
            elif stmt.kind == 'precision':
                default_prec = dict(stmt.args)
            continue
        if isinstance(stmt, Instruction):
            stmt = _apply_defaults(stmt, default_port, default_prec)
        out_stmts.append(stmt)
    return Program(stmts=out_stmts)


def _apply_defaults(inst: Instruction,
                    default_port: Optional[Dict[str, int]],
                    default_prec: Optional[Dict[str, int]]) -> Instruction:
    has_port = any(eh.kind == 'port' for eh in inst.eh_list)
    has_prec = any(eh.kind == 'precision' for eh in inst.eh_list)
    new_ehs = list(inst.eh_list)
    new_flags = set(inst.flags)
    if not has_port and default_port is not None and inst.mnemonic != 'NOP':
        new_ehs.insert(0, ExtensionHeader(
            kind='port', args=dict(default_port), line=inst.line,
        ))
    if not has_prec and default_prec is not None:
        new_ehs.append(ExtensionHeader(
            kind='precision', args=dict(default_prec), line=inst.line,
        ))
        # Auto-set the override flag(s) for whichever fields the default
        # actually provides, so the user only declares `.default_precision
        # mode=N` (or `dim=M`, or both) without also remembering to flag
        # the instruction.
        if 'mode' in default_prec:
            new_flags.add('prec')
        if 'dim' in default_prec:
            new_flags.add('dim_ovr')
    return Instruction(
        mnemonic=inst.mnemonic, flags=new_flags,
        eh_list=new_ehs, line=inst.line,
    )


# =============================================================================
# Section 6 — Stage 4: macro expansion
# =============================================================================

def macro_pass(prog: Program) -> Program:
    """Stage 4 — expand HL-only macros into LL primitive sequences.

    Supported macros:
      * RESHAPE .from <old> .to <new>           → VIEW .imm16 <new>
      * EINSUM with non-HW-direct subscript     → PERMUTE+VIEW+EINSUM(matmul
                                                  kernel)+VIEW+PERMUTE chain.
        HW-direct patterns (those whose canonicalized signature already
        matches one of the SIG_* localparams in ISA_Decoder.v) pass through
        unchanged.
    """
    out_stmts: List[Statement] = []
    for stmt in prog.stmts:
        if isinstance(stmt, Instruction):
            out_stmts.extend(_expand_macro(stmt))
        else:
            out_stmts.append(stmt)
    return Program(stmts=out_stmts)


# Canonical signatures (a_axes, b_axes, o_axes) of the HW-direct EINSUM
# kernels — must mirror ISA_Decoder.v's SIG_* localparams.
HW_DIRECT_EINSUM_SIGS = frozenset([
    (0x0001, 0x0000, 0x0000),  # SIG_SUM_I       'i->'
    (0x0011, 0x0000, 0x0000),  # SIG_TRACE_II    'ii->'
    (0x0021, 0x0000, 0x0012),  # SIG_TRANSPOSE   'ij->ji'
    (0x0021, 0x0032, 0x0031),  # SIG_MATMUL      'ij,jk->ik'
    (0x0021, 0x0021, 0x0021),  # SIG_HADAMARD    'ij,ij->ij'
    (0x0001, 0x0002, 0x0021),  # SIG_OUTER       'i,j->ij'
    (0x0321, 0x0000, 0x0021),  # SIG_PARTIAL_IJK 'ijk->ij'
    (0x0011, 0x0000, 0x0001),  # SIG_DIAGONAL    'ii->i'
    (0x0001, 0x0001, 0x0000),  # SIG_DOT         'i,i->'
    (0x0021, 0x0002, 0x0001),  # SIG_MAT_VEC     'ij,j->i'
    # v1.1 amendment (2026-07-14) — EINSUM completeness. Both int8 packed
    # 8-lane payload. Requires dim_sizes = 0x15 (3D 2×2×2) at issue time.
    (0x0321, 0x0431, 0x0421),  # SIG_BMM         'bik,bkj->bij'
    (0x0211, 0x0000, 0x0002),  # SIG_TRACE_IIJ   'iij->j'
    # v1.2 amendment (2026-07-14) — 4D at int4 packed 16-nibble payload.
    # Requires dim_sizes = 0x55 (4D 2×2×2×2) at issue time.
    (0x4321, 0x5421, 0x5321),  # SIG_BMM_2       'abij,abjk->abik' (2-batch matmul)
    (0x3211, 0x0000, 0x0032),  # SIG_TRACE_IIJK  'iijk->jk' (3D trace, 2 kept axes)
])


# v1.3 §16 (2026-07-14) — 5+ axes patterns via multi-SUBSCRIPT EH chain.
# 6-tuple = (a_lo, b_lo, o_lo, a_hi, b_hi, o_hi). Encoded via 2 SUBSCRIPT
# EHs in the machine code. Currently NO matching PE_Core primitive: RTL
# will surface `lower_required` for these signatures — v1.3 lands the
# encoding infrastructure only. Execution requires a payload extension
# (>64-bit) which is a v2 scope. See `.claude-memos/eh_encoding_expansion.md`.
HW_DIRECT_EINSUM_SIGS_MULTI = frozenset([
    # SIG_BMM_3 candidate: 'abcij,abcjk->abcik' (3-batch matmul)
    #   Labels: a=1, b=2, c=3, i=4, j=5, k=6
    #   A = [a,b,c,i,j] → lo=0x4321, hi=0x0005
    #   B = [a,b,c,j,k] → lo=0x5321, hi=0x0006
    #   O = [a,b,c,i,k] → lo=0x4321, hi=0x0006
    (0x4321, 0x5321, 0x4321, 0x0005, 0x0006, 0x0006),
    # SIG_TRACE_IIJKL candidate: 'iijkl->jkl' (trace + 3 kept axes)
    #   Labels: i=1, j=2, k=3, l=4
    #   A = [i,i,j,k,l] → lo=0x3211, hi=0x0004
    #   B = []          → lo=0x0000, hi=0x0000
    #   O = [j,k,l]     → lo=0x0432, hi=0x0000  (wait: 3 axes fit in lo)
    # Correction: O = [j,k,l] labels [2,3,4] → lo=0x0432 (axis0=2,axis1=3,axis2=4).
    # But if O had 5+ axes, hi would be nonzero. Here O is 3 axes, all in lo.
    (0x3211, 0x0000, 0x0432, 0x0004, 0x0000, 0x0000),
])


def _einsum_signature_packed(a_codes, b_codes, o_codes):
    """Pack each canonicalized axis list to a 16-bit value (the same form
    that ends up in the SUBSCRIPT EH body). Only axes 0-3."""
    def pack(codes):
        v = 0
        for i, c in enumerate(codes[:4]):
            v |= (c & 0xF) << (i * 4)
        return v
    return (pack(a_codes), pack(b_codes), pack(o_codes))


def _einsum_signature_multi(a_codes, b_codes, o_codes):
    """v1.3 §16 — 6-tuple (lo_a, lo_b, lo_o, hi_a, hi_b, hi_o) for 5+ axes
    patterns. axes 0-3 → lo half, axes 4-7 → hi half. hi_* = 0 when the
    corresponding tensor has ≤4 axes."""
    def pack_hi(codes):
        if len(codes) <= 4:
            return 0
        v = 0
        for i, c in enumerate(codes[4:8]):
            v |= (c & 0xF) << (i * 4)
        return v
    lo_a, lo_b, lo_o = _einsum_signature_packed(a_codes, b_codes, o_codes)
    return (lo_a, lo_b, lo_o, pack_hi(a_codes), pack_hi(b_codes), pack_hi(o_codes))


def _elem_count(dim_sizes: int) -> int:
    return ((dim_sizes & 0x3) + 1) * (((dim_sizes >> 2) & 0x3) + 1) \
         * (((dim_sizes >> 4) & 0x3) + 1) * (((dim_sizes >> 6) & 0x3) + 1)


def _expand_macro(inst: Instruction) -> List[Instruction]:
    if inst.mnemonic == 'RESHAPE':
        return _expand_reshape(inst)
    if inst.mnemonic == 'EINSUM':
        return _maybe_lower_einsum(inst)
    # v1.6.4 §22.11 — RISC-ish normalization macros.
    if inst.mnemonic == 'BATCHNORM_INFER':
        return _lower_batchnorm_infer(inst)
    if inst.mnemonic == 'RMSNORM':
        return _lower_rmsnorm(inst)
    if inst.mnemonic == 'LAYERNORM':
        return _lower_layernorm(inst)
    return [inst]


# =============================================================================
# v1.6.4 §22.11 — RISC-ish normalization macro expansion pass
# =============================================================================
#
# Compositional decomposition of common normalization techniques into the
# Group A/B/C primitives landed in v1.6.1a/b + v1.6.2/3. SDK-level macro
# expansion (no new HW opcode). Users write ONE line; assembler emits the
# multi-primitive sequence.
#
# Design (workflow wsvd6rl41):
#   - Monolithic single-line macro syntax (mirrors RESHAPE .from/.to,
#     EINSUM .subscript style).
#   - Wide vector constants (γ, β, K1, K2 — 64-bit 4D int4) → .imm64.
#   - Scalar constants (eps, inv_n — Q16.16) → .imm32.
#   - Port EH carried from macro invocation to each expanded instruction.
#
# Dataflow note (spec §22.11): each expanded primitive fires as its own
# wave dispatch. Intermediate tensor flow (μ, xc, sq, scale) is a
# runtime/fabric concern. For LAYERNORM specifically, `xc` is consumed
# twice (steps 3+6) which requires SDK-side re-issuance (wave-token
# single-use rule). LAYERNORM landing documents this as an SDK contract.


def _get_macro_arg(inst: Instruction, kind: str, name: str) -> int:
    """Extract a scalar constant from a macro's EH list by kind+name.
    Raises AssemblerError if missing or ill-typed. Used for macro args
    that carry ONE numeric value per EH (e.g. .gamma <val>)."""
    for eh in inst.eh_list:
        if eh.kind == kind:
            v = _take_immediate(eh)
            return v
    raise AssemblerError(
        f"line {inst.line}: {inst.mnemonic} missing required .{kind} directive"
    )


def _macro_port_eh(inst: Instruction) -> ExtensionHeader:
    """Extract the PORT EH from a macro's EH list.
    Every macro requires exactly one .port directive to route the output
    (mirrors non-macro instruction convention)."""
    for eh in inst.eh_list:
        if eh.kind == 'port':
            return eh
    raise AssemblerError(
        f"line {inst.line}: {inst.mnemonic} missing required .port directive"
    )


def _make_eh(kind: str, args: dict, line: int) -> ExtensionHeader:
    """Convenience: build an ExtensionHeader with sane defaults."""
    return ExtensionHeader(kind=kind, args=args, line=line)


def _lower_batchnorm_infer(inst: Instruction) -> List[Instruction]:
    """BATCHNORM_INFER(x, K1, K2) → 2-primitive sequence (spec §22.5).

    Inference-path BatchNorm with SDK-precomputed constants:
      K1[e] = running_scale[e] · γ[e]   (per-feature scale, 4D int4 = 64-bit)
      K2[e] = β[e] - running_mean[e] · K1[e]   (per-feature bias)

    Recipe:
      1) SIMD_MUL_WIDE_VEC   x, K1  →  t   (opcode 0x65)
      2) SIMD_ADD_WIDE_VEC   t, K2  →  y   (opcode 0x63)

    Args: .k1 <64-bit int>, .k2 <64-bit int>, .port <mask/out>.
    """
    k1 = _get_macro_arg(inst, 'k1', 'k1')
    k2 = _get_macro_arg(inst, 'k2', 'k2')
    port_eh = _macro_port_eh(inst)
    return [
        Instruction(
            mnemonic='SIMD_MUL_WIDE_VEC',
            flags=set(inst.flags) | {'opb'},
            eh_list=[port_eh, _make_eh('imm64', {'value': k1}, inst.line)],
            line=inst.line,
        ),
        Instruction(
            mnemonic='SIMD_ADD_WIDE_VEC',
            flags=set(inst.flags) | {'opb'},
            eh_list=[port_eh, _make_eh('imm64', {'value': k2}, inst.line)],
            line=inst.line,
        ),
    ]


def _lower_rmsnorm(inst: Instruction) -> List[Instruction]:
    """RMSNORM(x, γ, eps) → 5-primitive sequence (spec §22.4 simplified).

    RMSNorm: y = γ · x / √(mean(x²) + eps). No centering step (LLaMA-style).

    Recipe (SDK pre-computes 1/N × eps offset so we can drop the separate
    scalar add; the scale is pre-baked):
      1) SIG_L2SQ_IJKLM         x          →  sq (int32 scalar)
      2) [SDK offline] eps and 1/N folded into the pre-computed rsqrt seed —
         omitted from emitted primitives for MVP simplicity.
      3) SCALAR_RSQRT           sq         →  scale (Q16.16)
      4) SIMD_MUL_WIDE_SCALAR   x, scale[3:0]  →  nrm (broadcast int4 scale)
      5) SIMD_MUL_WIDE_VEC      nrm, γ     →  y

    KNOWN PRECISION LOSS: step 4 truncates Q16.16 scale to int4 (dec_eff_b_value[3:0]).
    ~12-bit precision loss at exactly the multiplication step. Mitigation
    is a v1.6.5+ SIMD_MUL_WIDE_SCALAR variant that widens B to Q4.4 or int8.

    Args: .gamma <64-bit int>, .port <mask/out>. eps + inv_n are SDK-side
    (pre-folded into the rsqrt seed).
    """
    gamma = _get_macro_arg(inst, 'gamma', 'gamma')
    port_eh = _macro_port_eh(inst)
    # SIG_L2SQ_IJKLM: 5D→scalar, op_marker=0x4 in HI.O_hi[3:0].
    # 5D subscript with A_hi=0x0005 discriminator, O empty (scalar).
    #   A = [i,j,k,l,m] canonicalized: i=1,j=2,k=3,l=4,m=5
    #   Packed: A_lo = 0x4321, A_hi = 0x0005; B = O = 0; O_hi[3:0] = 0x4 (L2SQ)
    return [
        Instruction(
            mnemonic='EINSUM',
            flags=set(inst.flags) | {'opb'},
            eh_list=[
                port_eh,
                _make_eh('subscript',
                         {'A': ['i', 'j', 'k', 'l'], 'B': [], 'O': []},
                         inst.line),
                _make_eh('subscript',
                         {'A': ['m'], 'B': [], 'O': [0x4]},  # op_marker at position 0
                         inst.line),
                _make_eh('opref', {}, inst.line),
            ],
            line=inst.line,
        ),
        Instruction(
            mnemonic='SCALAR_RSQRT',
            flags=set(inst.flags),
            eh_list=[port_eh],
            line=inst.line,
        ),
        # scale is Q16.16; broadcast to int4 via SIMD_MUL_WIDE_SCALAR opref
        # (SDK routes the low nibble of the rsqrt output as B_scalar).
        Instruction(
            mnemonic='SIMD_MUL_WIDE_SCALAR',
            flags=set(inst.flags),
            eh_list=[port_eh, _make_eh('opref', {}, inst.line)],
            line=inst.line,
        ),
        Instruction(
            mnemonic='SIMD_MUL_WIDE_VEC',
            flags=set(inst.flags) | {'opb'},
            eh_list=[port_eh, _make_eh('imm64', {'value': gamma}, inst.line)],
            line=inst.line,
        ),
    ]


def _lower_layernorm(inst: Instruction) -> List[Instruction]:
    """LAYERNORM(x, γ, β, eps) → 6-primitive sequence (spec §22.3 abridged).

    SDK CONTRACT (fanout hazard, per workflow wsvd6rl41 verify):
      Step 2 emits `xc = x - μ` which is consumed BOTH by step 3 (L2SQ for
      variance) AND step 4 (final scaling). Wave-tokens are single-use, so
      the SDK/runtime must:
        (a) Re-issue x on step 4's fabric route (fanout via NoC broadcast),
            OR
        (b) Buffer xc on-Cluster (multi-slot fragment buffer, v1.6.5+),
            OR
        (c) Recompute xc via a second SIMD_SUB_WIDE_VEC dispatch (this
            macro's current strategy — emits SUB twice, cheapest for MVP).

    Recipe (MVP — SDK responsibility for eps/1_N folding into rsqrt seed):
      1) MEAN_5D_TO_4D    x            →  μ[abcd]
      2) SIMD_SUB_WIDE_VEC  x, μ       →  xc[abcde]   (first emission)
      3) L2SQ_IJKLM       xc           →  sq_scalar   (variance sum)
      4) SCALAR_RSQRT     sq_scalar    →  scale       (Q16.16)
      5) SIMD_SUB_WIDE_VEC  x, μ       →  xc[abcde]   (re-emission — SDK strat (c))
      6) SIMD_MUL_WIDE_SCALAR  xc, scale[3:0]  →  nrm
      7) SIMD_MUL_WIDE_VEC  nrm, γ     →  sc
      8) SIMD_ADD_WIDE_VEC  sc, β      →  y

    Args: .gamma, .beta (64-bit int4 vectors), .port.
    """
    gamma = _get_macro_arg(inst, 'gamma', 'gamma')
    beta = _get_macro_arg(inst, 'beta', 'beta')
    port_eh = _macro_port_eh(inst)
    # Placeholder for μ — SDK-provided vector reference. For MVP macro,
    # we emit the primitive with an .opref that the SDK later resolves.
    mu_opref = _make_eh('opref', {}, inst.line)
    return [
        # 1) MEAN_5D_TO_4D via EINSUM with op_marker=0x5 (5D→4D family)
        Instruction(
            mnemonic='EINSUM',
            flags=set(inst.flags) | {'opb'},
            eh_list=[
                port_eh,
                _make_eh('subscript',
                         {'A': ['i', 'j', 'k', 'l'], 'B': [],
                          'O': ['i', 'j', 'k', 'l']},
                         inst.line),
                _make_eh('subscript',
                         {'A': ['m'], 'B': [], 'O': [0x5]},  # MEAN op_marker at position 0
                         inst.line),
                _make_eh('opref', {}, inst.line),
            ],
            line=inst.line,
        ),
        # 2) SIMD_SUB_WIDE_VEC: x - μ (first emission)
        Instruction(
            mnemonic='SIMD_SUB_WIDE_VEC',
            flags=set(inst.flags) | {'opb'},
            eh_list=[port_eh, mu_opref],
            line=inst.line,
        ),
        # 3) L2SQ_IJKLM: 5D→scalar sum of squares
        Instruction(
            mnemonic='EINSUM',
            flags=set(inst.flags) | {'opb'},
            eh_list=[
                port_eh,
                _make_eh('subscript',
                         {'A': ['i', 'j', 'k', 'l'], 'B': [], 'O': []},
                         inst.line),
                _make_eh('subscript',
                         {'A': ['m'], 'B': [], 'O': [0, 0, 0, 0x4]},  # L2SQ marker
                         inst.line),
                _make_eh('opref', {}, inst.line),
            ],
            line=inst.line,
        ),
        # 4) SCALAR_RSQRT
        Instruction(
            mnemonic='SCALAR_RSQRT',
            flags=set(inst.flags),
            eh_list=[port_eh],
            line=inst.line,
        ),
        # 5) SIMD_SUB_WIDE_VEC: x - μ (re-emission — SDK strategy c)
        Instruction(
            mnemonic='SIMD_SUB_WIDE_VEC',
            flags=set(inst.flags) | {'opb'},
            eh_list=[port_eh, mu_opref],
            line=inst.line,
        ),
        # 6) SIMD_MUL_WIDE_SCALAR: xc × scale
        Instruction(
            mnemonic='SIMD_MUL_WIDE_SCALAR',
            flags=set(inst.flags),
            eh_list=[port_eh, _make_eh('opref', {}, inst.line)],
            line=inst.line,
        ),
        # 7) SIMD_MUL_WIDE_VEC: nrm × γ
        Instruction(
            mnemonic='SIMD_MUL_WIDE_VEC',
            flags=set(inst.flags) | {'opb'},
            eh_list=[port_eh, _make_eh('imm64', {'value': gamma}, inst.line)],
            line=inst.line,
        ),
        # 8) SIMD_ADD_WIDE_VEC: sc + β
        Instruction(
            mnemonic='SIMD_ADD_WIDE_VEC',
            flags=set(inst.flags) | {'opb'},
            eh_list=[port_eh, _make_eh('imm64', {'value': beta}, inst.line)],
            line=inst.line,
        ),
    ]


# -----------------------------------------------------------------------------
# Arbitrary EINSUM lowering
# -----------------------------------------------------------------------------

def _maybe_lower_einsum(inst: Instruction) -> List[Instruction]:
    """If the EINSUM's subscript matches a HW-direct kernel, return it
    unchanged (after stripping the optional .shape directive). Otherwise
    decompose it into a chain of HW-direct primitives."""
    sub_eh = next((eh for eh in inst.eh_list if eh.kind == 'subscript'), None)
    shape_eh = next((eh for eh in inst.eh_list if eh.kind == 'shape'), None)
    other_ehs = [eh for eh in inst.eh_list
                 if eh.kind not in ('subscript', 'shape')]

    if sub_eh is None:
        # legality_pass will diagnose this.
        return [inst]

    codes = _canonicalize_subscript(sub_eh)
    max_axes = max(len(codes['A']), len(codes['B']), len(codes['O']))
    sig = _einsum_signature_packed(codes['A'], codes['B'], codes['O'])
    matched = (max_axes <= 4 and sig in HW_DIRECT_EINSUM_SIGS)
    if not matched and max_axes > 4:
        # v1.3 §16 — 5+ axes patterns match via 6-tuple.
        sig_multi = _einsum_signature_multi(codes['A'], codes['B'], codes['O'])
        matched = sig_multi in HW_DIRECT_EINSUM_SIGS_MULTI
    if matched:
        if shape_eh is None:
            return [inst]
        # HW reads tensor shape from the token tag, not from .shape — drop
        # the directive for the LL form.
        return [Instruction(
            mnemonic=inst.mnemonic, flags=set(inst.flags),
            eh_list=[eh for eh in inst.eh_list if eh.kind != 'shape'],
            line=inst.line,
        )]
    return _lower_einsum_general(inst, sub_eh, shape_eh, other_ehs)


def _lower_einsum_general(inst: Instruction,
                          sub_eh: ExtensionHeader,
                          shape_eh: Optional[ExtensionHeader],
                          other_ehs: List[ExtensionHeader]
                          ) -> List[Instruction]:
    """Decompose a generic einsum 'A,B->O' into a sequence of HW-direct ops:

         PERM_A  → VIEW_A  (reshape A to 2D matrix)
         PERM_B  → VIEW_B  (reshape B to 2D matrix)
         EINSUM matmul (the HW-direct kernel)
         VIEW_R  → PERM_R  (reshape result back to N-D and reorder to O)

    Trace-style (duplicate label in one tensor), broadcast (label in O but
    not in A or B), and mixed contraction-broadcast patterns are not yet
    handled — they raise AssemblerError so the user knows to either rewrite
    or wait for a future expansion of this pass."""
    a_labels = list(sub_eh.args.get('A', []))
    b_labels = list(sub_eh.args.get('B', []))
    o_labels = list(sub_eh.args.get('O', []))

    # ---------- Shape map (label → size in 1..4) ----------
    shapes: Dict[str, int] = {}
    if shape_eh is not None:
        for k, v in shape_eh.args.items():
            if k == '_pos':
                continue
            if not isinstance(v, int) or not (1 <= v <= 4):
                raise AssemblerError(
                    f"line {shape_eh.line}: .shape size for label {k!r} "
                    f"must be 1..4, got {v!r}"
                )
            shapes[k] = v
    for lab in set(a_labels) | set(b_labels) | set(o_labels):
        shapes.setdefault(lab, 2)

    # ---------- Validation — patterns not lowerable by pure macro pass ----------
    # See `.claude-memos/einsum_trace_broadcast_analysis.md` for why these
    # patterns need HW support (batched-trace, batched-matmul, constant-vector
    # splat) rather than macro-level rewrites, and what proposals exist for
    # closing them in a future WT64v1-C extension.
    if len(a_labels) != len(set(a_labels)):
        raise AssemblerError(
            f"line {inst.line}: trace-style EINSUM (duplicate label in A) "
            f"is not lowerable by macro_pass — WT64v1 provides HW-direct "
            f"'ii->' (SIG_TRACE_II) and 'ii->i' (SIG_DIAGONAL) but no batched "
            f"trace over additional kept axes. "
            f"See `.claude-memos/einsum_trace_broadcast_analysis.md`."
        )
    if len(b_labels) != len(set(b_labels)):
        raise AssemblerError(
            f"line {inst.line}: trace-style EINSUM (duplicate label in B) "
            f"is not lowerable by macro_pass — same reason as trace-in-A. "
            f"See `.claude-memos/einsum_trace_broadcast_analysis.md`."
        )
    if len(o_labels) != len(set(o_labels)):
        raise AssemblerError(
            f"line {inst.line}: duplicate label in O subscript"
        )
    a_set, b_set, o_set = set(a_labels), set(b_labels), set(o_labels)
    mixed = (a_set & b_set) & o_set
    if mixed:
        raise AssemblerError(
            f"line {inst.line}: labels {sorted(mixed)} appear in A, B, and O "
            f"simultaneously (batched contraction) — WT64v1 has no batched-"
            f"matmul primitive to close this. Rewrite as a sequence of "
            f"per-batch matmuls or await WT64v1-C extension. "
            f"See `.claude-memos/einsum_trace_broadcast_analysis.md`."
        )

    # ---------- Broadcast handling (partial — size-1 axes only) ----------
    # Labels in O but absent from A and B are "broadcast" axes: the result
    # tensor has a dimension along which the value is replicated. WT64v1
    # can express this only when the axis size is 1 — then UNSQUEEZE (a
    # metadata-only op) suffices to add the axis. For size > 1 we'd need
    # a runtime constant-vector splat primitive which WT64v1 does not have.
    bcast_labels = list(o_set - a_set - b_set)
    non_trivial_bcast = [l for l in bcast_labels if shapes[l] != 1]
    if non_trivial_bcast:
        sizes = {l: shapes[l] for l in non_trivial_bcast}
        raise AssemblerError(
            f"line {inst.line}: broadcast labels {sorted(non_trivial_bcast)} "
            f"have sizes {sizes} — only size-1 broadcast is lowerable via "
            f"UNSQUEEZE (WT64v1 has no constant-vector splat primitive). "
            f"Add `.shape {sorted(non_trivial_bcast)[0]}=1` to indicate the "
            f"axis is a placeholder, or await WT64v1-C extension. "
            f"See `.claude-memos/einsum_trace_broadcast_analysis.md`."
        )
    # All broadcast labels are size-1; each becomes an UNSQUEEZE insertion
    # in Step 8 (post-matmul-chain).
    o_reduced = [l for l in o_labels if l not in bcast_labels]

    # ---------- Identify groups (using o_reduced — bcast labels are inserted post) ----
    o_reduced_set = set(o_reduced)
    contracted_set = (a_set & b_set) - o_reduced_set
    contracted = [l for l in a_labels if l in contracted_set]
    kept_a = [l for l in o_reduced if l in a_set]      # in A and o_reduced
    kept_b = [l for l in o_reduced if l in b_set
                                  and l not in a_set]  # B-only kept

    # ---------- Find PORT and OPREF EHs to replicate on each emitted op ----
    port_eh = next((eh for eh in other_ehs if eh.kind == 'port'), None)
    opref_eh = next((eh for eh in other_ehs if eh.kind == 'opref'), None)
    line = inst.line

    def make(mnemonic, flags, extras):
        ehs = []
        if port_eh is not None:
            ehs.append(port_eh)
        ehs.extend(extras)
        return Instruction(mnemonic=mnemonic, flags=set(flags),
                           eh_list=ehs, line=line)

    insts: List[Instruction] = []

    # ---------- Step 1: PERM A so that order is (kept_a, contracted) -------
    target_a = kept_a + contracted
    if a_labels != target_a:
        perm_a = _compute_perm_pattern(a_labels, target_a)
        insts.append(make('PERM', set(), [
            ExtensionHeader(kind='imm16', args={'_pos': [perm_a]}, line=line),
        ]))

    # ---------- Step 2: VIEW A as 2D (∏kept_a, ∏contracted) ----------------
    kept_a_size     = _prod(shapes[l] for l in kept_a) if kept_a     else 1
    contracted_size = _prod(shapes[l] for l in contracted) if contracted else 1
    a_2d = [kept_a_size, contracted_size]
    insts.append(make('VIEW', set(), [
        ExtensionHeader(kind='imm16',
                        args={'_pos': [_make_dim_sizes(a_2d)]}, line=line),
    ]))

    # ---------- Step 3: PERM B so that order is (contracted, kept_b) -------
    target_b = contracted + kept_b
    if b_labels != target_b:
        perm_b = _compute_perm_pattern(b_labels, target_b)
        insts.append(make('PERM', set(), [
            ExtensionHeader(kind='imm16', args={'_pos': [perm_b]}, line=line),
        ]))

    # ---------- Step 4: VIEW B as 2D (∏contracted, ∏kept_b) ----------------
    kept_b_size = _prod(shapes[l] for l in kept_b) if kept_b else 1
    b_2d = [contracted_size, kept_b_size]
    insts.append(make('VIEW', set(), [
        ExtensionHeader(kind='imm16',
                        args={'_pos': [_make_dim_sizes(b_2d)]}, line=line),
    ]))

    # ---------- Step 5: EINSUM matmul kernel (ij,jk->ik) -------------------
    matmul_ehs: List[ExtensionHeader] = [
        ExtensionHeader(kind='subscript', args={
            'A': ['_p', '_q'],
            'B': ['_q', '_r'],
            'O': ['_p', '_r'],
        }, line=line),
    ]
    if opref_eh is not None:
        matmul_ehs.append(opref_eh)
    else:
        # The lowered matmul still requires OPREF — synthesize a default
        # src_kind=0 OPREF since the source EINSUM was the binary form.
        matmul_ehs.append(ExtensionHeader(
            kind='opref', args={'kind': 0, 'port': 0, 'route': 0}, line=line,
        ))
    insts.append(make('EINSUM', {'opb'}, matmul_ehs))

    # ---------- Step 6: VIEW result from 2D back to N-D --------------------
    result_dims = ([shapes[l] for l in kept_a] +
                   [shapes[l] for l in kept_b])
    if len(result_dims) > 4:
        raise AssemblerError(
            f"line {line}: result tensor of arity {len(result_dims)} "
            f"exceeds the 4-axis hardware limit; deeper lowering required"
        )
    if len(result_dims) >= 2 and result_dims != a_2d:
        # Skip the 2D→2D no-op view (when there's only one kept axis on each
        # side and sizes already equal a_2d, the next view would be redundant)
        insts.append(make('VIEW', set(), [
            ExtensionHeader(kind='imm16',
                            args={'_pos': [_make_dim_sizes(result_dims)]},
                            line=line),
        ]))

    # ---------- Step 7: PERM result from (kept_a + kept_b) to o_reduced order ----
    # Note: uses o_reduced (not o_labels) — bcast dims are inserted at Step 8.
    intermediate_o = kept_a + kept_b
    if intermediate_o != o_reduced and len(intermediate_o) >= 2:
        perm_o = _compute_perm_pattern(intermediate_o, o_reduced)
        insts.append(make('PERM', set(), [
            ExtensionHeader(kind='imm16', args={'_pos': [perm_o]}, line=line),
        ]))

    # ---------- Step 8: UNSQUEEZE for each size-1 broadcast axis ----------
    # As we walk o_labels in order, insert USQZ at each broadcast label's
    # target position. Because we process in ascending o_labels order and
    # the current tag already contains all preceding non-bcast positions
    # in their final locations, the target position is exactly o_labels.index(lab).
    for pos, lab in enumerate(o_labels):
        if lab in bcast_labels:
            insts.append(make('USQZ', set(), [
                ExtensionHeader(kind='imm16', args={'_pos': [pos]}, line=line),
            ]))

    return insts


def _compute_perm_pattern(source: List[str], target: List[str]) -> int:
    """Returns an 8-bit perm pattern packed as (axis3<<6 | axis2<<4 |
    axis1<<2 | axis0), where axis_i is the source-axis-index that becomes
    the target's i-th axis. Padded with 0 for unused axis slots."""
    if len(target) > 4 or len(source) > 4:
        raise AssemblerError(
            f"permute pattern requires both source and target to have ≤4 "
            f"axes (source={source}, target={target})"
        )
    pattern = 0
    for new_idx, lab in enumerate(target):
        try:
            old_idx = source.index(lab)
        except ValueError:
            raise AssemblerError(
                f"permute target axis {lab!r} not found in source {source}"
            )
        pattern |= (old_idx & 0x3) << (new_idx * 2)
    return pattern


def _make_dim_sizes(sizes: List[int]) -> int:
    """Pack up to 4 axis sizes (each 1..4) into the 8-bit dim_sizes encoding
    used by the token tag and the VIEW EH (each axis encoded as size-1)."""
    if len(sizes) > 4:
        raise AssemblerError(f"dim_sizes packing supports up to 4 axes, "
                             f"got {len(sizes)}")
    val = 0
    for i, s in enumerate(sizes):
        if not isinstance(s, int) or not (1 <= s <= 4):
            raise AssemblerError(f"axis size out of range 1..4: {s!r}")
        val |= ((s - 1) & 0x3) << (i * 2)
    return val


def _prod(iterable) -> int:
    result = 1
    for x in iterable:
        result *= x
    return result


def _expand_reshape(inst: Instruction) -> List[Instruction]:
    from_arg: Optional[int] = None
    to_arg: Optional[int] = None
    other_ehs: List[ExtensionHeader] = []
    for eh in inst.eh_list:
        if eh.kind == 'from':
            from_arg = _take_singleton(eh, 'from', inst.line)
        elif eh.kind == 'to':
            to_arg = _take_singleton(eh, 'to', inst.line)
        else:
            other_ehs.append(eh)
    if to_arg is None:
        raise AssemblerError(
            f"line {inst.line}: RESHAPE requires '.to <new_dim_sizes>'"
        )
    if from_arg is not None and _elem_count(from_arg) != _elem_count(to_arg):
        raise AssemblerError(
            f"line {inst.line}: RESHAPE element count mismatch "
            f"({_elem_count(from_arg)} from {from_arg:#04x} vs "
            f"{_elem_count(to_arg)} to {to_arg:#04x})"
        )
    return [Instruction(
        mnemonic='VIEW', flags=set(inst.flags),
        eh_list=other_ehs + [ExtensionHeader(
            kind='imm16', args={'_pos': [to_arg]}, line=inst.line,
        )],
        line=inst.line,
    )]


def _take_singleton(eh: ExtensionHeader, name: str, line: int) -> int:
    if '_pos' in eh.args and eh.args['_pos']:
        v = eh.args['_pos'][0]
    elif eh.args:
        # Single kw arg
        v = next(iter(eh.args.values()))
    else:
        raise AssemblerError(f"line {line}: '.{name}' requires a value")
    if not isinstance(v, int):
        raise AssemblerError(
            f"line {line}: '.{name}' value must be numeric (got {v!r})"
        )
    return v


# =============================================================================
# Section 7 — Stage 5: legality / structural validation
# =============================================================================

# Per-opcode legality table (mirrors ISA_Decoder.v)
#   required:  EH names that MUST be present
#   forbidden: EH names that MUST NOT be present
#   allow_imm_xor_opref: True for binary ALU opcodes (one of {imm*, opref})
_LEGAL: Dict[int, Dict[str, object]] = {}


def _set_legal(opcodes, required=(), forbidden=(), allow_imm_xor_opref=False,
               require_opb_flag=False, require_imm16=False):
    for op in opcodes:
        _LEGAL[op] = dict(
            required=set(required), forbidden=set(forbidden),
            allow_imm_xor_opref=allow_imm_xor_opref,
            require_opb_flag=require_opb_flag,
            require_imm16=require_imm16,
        )


_ALL_DATA_EHS = {'imm16', 'imm32', 'imm64', 'mem', 'subscript', 'opref'}

# 0x00 NOP — everything forbidden
_set_legal([0x00], required=(), forbidden=_ALL_DATA_EHS)
# 0x01-0x03 control
_set_legal([0x01, 0x02, 0x03], required={'port'}, forbidden=_ALL_DATA_EHS)
# 0x04/0x05 LOAD/STORE
_set_legal([0x04, 0x05], required={'port', 'mem'},
           forbidden={'imm16', 'imm32', 'imm64', 'subscript', 'opref'})
# Binary ALU (XOR of imm/opref): arithmetic + bitwise binary.
_set_legal([0x10, 0x11, 0x12, 0x13,        # ADD/SUB/MUL/DIV
            0x14, 0x15, 0x16,              # AND/OR/XOR
            0x1C, 0x1D,                    # REM/DIVREM
            0x51, 0x52, 0x53],             # NAND/NOR/XNOR
           required={'port'}, forbidden={'subscript', 'mem'},
           allow_imm_xor_opref=True)
# Shift / rotate (require IMM16 for the shift amount).
_set_legal([0x17, 0x18, 0x19, 0x1A, 0x1E], required={'port'},
           forbidden={'subscript', 'mem', 'opref', 'imm32', 'imm64'},
           require_imm16=True)
# Pure unary scalar: NEG/BITREV + NOT/POPCOUNT/CLZ/CTZ.
_set_legal([0x1B, 0x1F,
            0x50, 0x54, 0x55, 0x56],
           required={'port'}, forbidden=_ALL_DATA_EHS)
# 0x20..0x26 shape ops (0x26 = SPLAT, v1.1 amendment)
_set_legal([0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26],
           required={'port', 'imm16'},
           forbidden={'subscript', 'mem', 'opref', 'imm32', 'imm64'})
# 0x30/0x31 MATMUL/TENSOR_ADD
_set_legal([0x30, 0x31], required={'port', 'opref'},
           forbidden={'subscript', 'mem', 'imm16', 'imm32', 'imm64'},
           require_opb_flag=True)
# 0x32 EINSUM
_set_legal([0x32], required={'port', 'subscript', 'opref'},
           forbidden={'mem', 'imm16', 'imm32', 'imm64'},
           require_opb_flag=True)
# 0x40..0x44 unary FP
_set_legal([0x40, 0x41, 0x42, 0x43, 0x44],
           required={'port'}, forbidden=_ALL_DATA_EHS)
# v1.6.1b §22 — SIMD_ADD/SUB/MUL_WIDE_SCALAR (0x60/61/62): binary-ALU
# style, B_scalar via imm16 XOR opref (dec_eff_b_value[3:0]).
_set_legal([0x60, 0x61, 0x62],
           required={'port'}, forbidden={'subscript', 'mem'},
           allow_imm_xor_opref=True)
# v1.6.1b §22 — SIMD_ADD/SUB/MUL_WIDE_VEC (0x63/64/65): V (64-bit 4D
# vector) via imm64 XOR opref. F_HAS_OPB flag required — V arrives on
# input_payload_b (either as compile-time IMM64 constant or as a prior
# wave via OPREF bank routing).
_set_legal([0x63, 0x64, 0x65],
           required={'port'}, forbidden={'subscript', 'mem', 'imm16', 'imm32'},
           allow_imm_xor_opref=True, require_opb_flag=True)
# v1.6.1b §22 — SCALAR_RSQRT (0x66): pure unary scalar on dec_input_payload
# (Q16.16 fixed-point). No B, no imm, no opref (mirrors 0x1B NEG shape).
_set_legal([0x66], required={'port'}, forbidden=_ALL_DATA_EHS)


def _check_no_unresolved_aliases(inst: Instruction) -> None:
    """Surface unresolved alias names as a friendly diagnostic instead of
    letting them slip into the encoder where they'd crash with TypeError.

    Subscript label lists legitimately hold strings (single-letter labels),
    so we exempt that EH kind from the scan."""
    for eh in inst.eh_list:
        if eh.kind == 'subscript':
            continue
        for k, v in eh.args.items():
            if isinstance(v, str):
                raise AssemblerError(
                    f"line {eh.line}: unresolved name {v!r} in .{eh.kind} "
                    f"({k}=...) — define it with `.alias {v} <value>` or "
                    f"replace with a numeric literal"
                )
            if isinstance(v, list):
                for item in v:
                    if isinstance(item, str):
                        raise AssemblerError(
                            f"line {eh.line}: unresolved name {item!r} in "
                            f".{eh.kind} ({k}=...)"
                        )


def legality_pass(prog: Program) -> Program:
    """Stage 5 — verify each instruction is legal under the same rules
    ISA_Decoder.v enforces, raising AssemblerError early so the user sees
    a textual error rather than a silent `error_flag` at simulation time."""
    for stmt in prog.stmts:
        if not isinstance(stmt, Instruction):
            continue
        _check_no_unresolved_aliases(stmt)
        if stmt.mnemonic in HL_ONLY_MNEMONICS:
            raise AssemblerError(
                f"line {stmt.line}: HL-only mnemonic {stmt.mnemonic!r} reached "
                f"the legality stage — macro_pass should have expanded it"
            )
        if stmt.mnemonic not in MNEMONIC_TO_OPCODE:
            raise AssemblerError(f"line {stmt.line}: unknown mnemonic {stmt.mnemonic!r}")
        opcode = MNEMONIC_TO_OPCODE[stmt.mnemonic]
        rules = _LEGAL.get(opcode)
        if rules is None:
            raise AssemblerError(
                f"line {stmt.line}: opcode 0x{opcode:02x} has no legality entry"
            )
        eh_kinds = {eh.kind for eh in stmt.eh_list}
        unknown = eh_kinds - set(EH_NAME_TO_CODE)
        if unknown:
            raise AssemblerError(
                f"line {stmt.line}: unknown EH directive(s) {sorted(unknown)}"
            )
        any_imm = bool(eh_kinds & {'imm16', 'imm32', 'imm64'})
        if rules['allow_imm_xor_opref']:
            any_opref = 'opref' in eh_kinds
            if any_imm == any_opref:
                raise AssemblerError(
                    f"line {stmt.line}: {stmt.mnemonic} requires exactly one of "
                    f"{{.imm16/.imm32/.imm64, .opref}}; got both or neither"
                )
        else:
            for need in rules['required']:
                if need not in eh_kinds:
                    raise AssemblerError(
                        f"line {stmt.line}: {stmt.mnemonic} requires .{need}"
                    )
        for forbid in rules['forbidden']:
            if forbid in eh_kinds:
                raise AssemblerError(
                    f"line {stmt.line}: {stmt.mnemonic} forbids .{forbid}"
                )
        if rules['require_imm16'] and 'imm16' not in eh_kinds:
            raise AssemblerError(
                f"line {stmt.line}: {stmt.mnemonic} requires .imm16"
            )
        if rules['require_opb_flag'] and 'opb' not in stmt.flags:
            raise AssemblerError(
                f"line {stmt.line}: {stmt.mnemonic} requires the 'opb' flag "
                f"(F_HAS_OPB) — its second operand is on input_payload_b"
            )
        # F_PRECISION_OVR / F_DIM_OVR draw their override values from the
        # PRECISION EH; without it, eff_prec_* default to zero and would
        # silently corrupt the instruction. Reject that combination at
        # compile time so the user sees a textual error instead of a
        # surprise `error_flag` at simulation time.
        if 'prec' in stmt.flags and 'precision' not in eh_kinds:
            raise AssemblerError(
                f"line {stmt.line}: 'prec' flag (F_PRECISION_OVR) requires "
                f"a .precision EH supplying mode=...; add `.precision mode=N`"
            )
        if 'dim_ovr' in stmt.flags and 'precision' not in eh_kinds:
            raise AssemblerError(
                f"line {stmt.line}: 'dim_ovr' flag (F_DIM_OVR) requires "
                f"a .precision EH supplying dim=...; add `.precision dim=N`"
            )
    return prog


# =============================================================================
# Section 8 — Stage 6: encoder (LL AST → 416-bit machine code)
# =============================================================================

def _canonicalize_subscript(eh: ExtensionHeader) -> Dict[str, List[int]]:
    """Map textual subscript labels to the 4-bit codes used by the SUBSCRIPT
    EH body, using **first-appearance order** scanning A → B → O.

    This matches the convention baked into ISA_Decoder.v's `SIG_*`
    localparams: `i,j,k`-style labels in `ij,jk->ik` get codes 1, 2, 3
    regardless of the actual letters used. So `pq,qr->pr` and `ij,jk->ik`
    encode to identical bytes — they're alpha-equivalent einsum patterns."""
    label_map: Dict[str, int] = {}
    next_code = 1
    out: Dict[str, List[int]] = {}
    for group in ('A', 'B', 'O'):
        labels = eh.args.get(group, [])
        codes: List[int] = []
        for lab in labels:
            # Numeric input (e.g. from a previous canonicalization) flows through.
            if isinstance(lab, int):
                codes.append(lab)
                continue
            if not isinstance(lab, str):
                raise AssemblerError(
                    f"line {eh.line}: subscript label must be a string or int, "
                    f"got {lab!r}"
                )
            if lab not in label_map:
                if next_code > 12:
                    raise AssemblerError(
                        f"line {eh.line}: too many distinct subscript labels "
                        f"(max 12, codes 1..0xC)"
                    )
                label_map[lab] = next_code
                next_code += 1
            codes.append(label_map[lab])
        out[group] = codes
    return out


def _pack_axes(codes: List[int]) -> int:
    """Pack up to 4 axis codes into a 16-bit value.

    v1.3: raises now indicate encoding overflow (>4 axes per SUBSCRIPT EH
    half). Callers targeting 5+ axes should chain 2 SUBSCRIPT EHs via
    `_pack_axes_multi` and emit both bodies (§16)."""
    if len(codes) > 4:
        raise AssemblerError(f"at most 4 subscript axes per group, got {codes}")
    v = 0
    for i, c in enumerate(codes):
        if not isinstance(c, int) or not (0 <= c <= 0xF):
            raise AssemblerError(
                f"axis label code out of range (must be 0..0xF), got {c!r}"
            )
        v |= (c & 0xF) << (i * 4)
    return v


def _pack_axes_multi(codes: List[int]) -> Tuple[int, int]:
    """v1.3 §16 — split up to 8 axis codes into (low_half, hi_half).

    Positions 0-3 go into low_half (axes 0-3), positions 4-7 into hi_half
    (axes 4-7). Returns (low16, hi16). 9+ axes raises."""
    if len(codes) > 8:
        raise AssemblerError(
            f"at most 8 subscript axes per group (v1.3 multi-SUBSCRIPT limit), "
            f"got {len(codes)}: {codes}"
        )
    lo = _pack_axes(codes[:4])
    hi = _pack_axes(codes[4:]) if len(codes) > 4 else 0
    return lo, hi


def _take_immediate(eh: ExtensionHeader) -> int:
    if '_pos' in eh.args and eh.args['_pos']:
        v = eh.args['_pos'][0]
    elif 'value' in eh.args:
        v = eh.args['value']
    elif eh.args:
        v = next(iter(eh.args.values()))
    else:
        raise AssemblerError(f"line {eh.line}: .{eh.kind} requires an immediate value")
    if not isinstance(v, int):
        raise AssemblerError(f"line {eh.line}: .{eh.kind} value must be numeric")
    return v


def _encode_eh(eh: ExtensionHeader) -> Tuple[int, List[int]]:
    """Returns (type_code, body_words). The body words include the EH common
    header in their first word but with `next_hdr` left as 0; encode_pass
    patches that in once the chain order is known."""
    kind = eh.kind
    a = eh.args
    if kind == 'port':
        mask = a.get('mask', 0)
        out = a.get('out', 0)
        body16 = ((out & 0xFF) << 8) | (mask & 0xFF)
        return EH_PORT, [(body16 << 16) | (EH_PORT << 8) | 1]
    if kind == 'imm16':
        v = _take_immediate(eh)
        return EH_IMM16, [((v & 0xFFFF) << 16) | (EH_IMM16 << 8) | 1]
    if kind == 'imm32':
        v = _take_immediate(eh)
        return EH_IMM32, [(EH_IMM32 << 8) | 2, v & 0xFFFFFFFF]
    if kind == 'imm64':
        v = _take_immediate(eh)
        return EH_IMM64, [
            (EH_IMM64 << 8) | 3,
            v & 0xFFFFFFFF,
            (v >> 32) & 0xFFFFFFFF,
        ]
    if kind == 'mem':
        offset = a.get('offset', 0)
        addr_mode = a.get('mode', 0)
        stride = a.get('stride', 0)
        upper = ((stride & 0xFFF) << 4) | (addr_mode & 0xF)
        return EH_MEM, [(upper << 16) | (EH_MEM << 8) | 2, offset & 0xFFFFFFFF]
    if kind == 'subscript':
        codes = _canonicalize_subscript(eh)
        a_axes = _pack_axes(codes.get('A', []))
        b_axes = _pack_axes(codes.get('B', []))
        o_axes = _pack_axes(codes.get('O', []))
        return EH_SUBSCRIPT, [
            ((o_axes & 0xFFFF) << 16) | (EH_SUBSCRIPT << 8) | 2,
            ((a_axes & 0xFFFF) << 16) | (b_axes & 0xFFFF),
        ]
    if kind == 'opref':
        src_kind = a.get('kind', 0)
        port_id = a.get('port', 0)
        noc_route = a.get('route', 0)
        upper = ((noc_route & 0xFF) << 8) | ((port_id & 0xF) << 4) | (src_kind & 0xF)
        return EH_OPREF, [(upper << 16) | (EH_OPREF << 8) | 1]
    if kind == 'precision':
        mode = a.get('mode', 0)
        dim_override = a.get('dim', 0)
        upper = ((dim_override & 0xFF) << 8) | (mode & 0xFF)
        return EH_PRECISION, [(upper << 16) | (EH_PRECISION << 8) | 1]
    if kind == 'nop_pad':
        return EH_NOP_PAD, [(EH_NOP_PAD << 8) | 1]
    raise AssemblerError(f"line {eh.line}: cannot encode EH kind {kind!r}")


def _encode_subscript_eh_multi(eh: ExtensionHeader) -> List[Tuple[int, List[int]]]:
    """v1.3 §16 — encode a `.subscript` ExtensionHeader as ONE or TWO
    SUBSCRIPT EHs based on axes count. Groups with ≤4 axes emit a single
    SUBSCRIPT EH (backward compat). Groups with 5-8 axes emit two — the
    first carries axes 0-3, the second axes 4-7 for all of A/B/O."""
    codes = _canonicalize_subscript(eh)
    a_lo, a_hi = _pack_axes_multi(codes.get('A', []))
    b_lo, b_hi = _pack_axes_multi(codes.get('B', []))
    o_lo, o_hi = _pack_axes_multi(codes.get('O', []))
    ehs: List[Tuple[int, List[int]]] = [(EH_SUBSCRIPT, [
        ((o_lo & 0xFFFF) << 16) | (EH_SUBSCRIPT << 8) | 2,
        ((a_lo & 0xFFFF) << 16) | (b_lo & 0xFFFF),
    ])]
    if a_hi or b_hi or o_hi:
        ehs.append((EH_SUBSCRIPT, [
            ((o_hi & 0xFFFF) << 16) | (EH_SUBSCRIPT << 8) | 2,
            ((a_hi & 0xFFFF) << 16) | (b_hi & 0xFFFF),
        ]))
    return ehs


def _encode_instruction(inst: Instruction) -> int:
    opcode = MNEMONIC_TO_OPCODE[inst.mnemonic]
    flags = 0
    for fname in inst.flags:
        flags |= 1 << FLAG_BITS[fname]
    encoded: List[Tuple[int, List[int]]] = []
    for eh in inst.eh_list:
        if eh.kind == 'subscript':
            encoded.extend(_encode_subscript_eh_multi(eh))
        else:
            encoded.append(_encode_eh(eh))
    bh_len = 1 + sum(len(words) for _, words in encoded)
    # Patch next_hdr fields walking from end backwards.
    next_hdr = EH_END
    chain_words: List[int] = []
    for type_code, words in reversed(encoded):
        words = list(words)
        words[0] = (words[0] & ~(0xF << 12)) | (next_hdr << 12)
        chain_words = words + chain_words
        next_hdr = type_code
    first_next_hdr = next_hdr
    base = ((opcode & 0xFF) << 24) \
         | ((first_next_hdr & 0xF) << 20) \
         | ((flags & 0xF) << 16) \
         | (bh_len & 0xFF)
    full_words = [base] + chain_words
    if len(full_words) > INSTR_WORDS_REAL:
        raise AssemblerError(
            f"line {inst.line}: instruction is {len(full_words)} words, "
            f"exceeds MAX={INSTR_WORDS_REAL}"
        )
    while len(full_words) < INSTR_WORDS_REAL:
        full_words.append(0)
    val = 0
    for i, w in enumerate(full_words):
        val |= (w & 0xFFFFFFFF) << (i * 32)
    return val


def encode_pass(prog: Program) -> List[int]:
    """Stage 6 — emit a list of 416-bit instruction integers, one per
    Instruction node. Non-instruction statements (labels) are skipped."""
    insts: List[int] = []
    for stmt in prog.stmts:
        if isinstance(stmt, Instruction):
            insts.append(_encode_instruction(stmt))
    return insts


# =============================================================================
# Section 9 — Pretty printer (LL AST → text)
# =============================================================================

def _print_value(v) -> str:
    if isinstance(v, int):
        if v < 0:
            return str(v)
        if v >= 0x10:
            return f'0x{v:x}'
        return str(v)
    return str(v)


def _print_eh(eh: ExtensionHeader) -> str:
    if eh.kind == 'subscript':
        return ('.subscript '
                + ' '.join(f'{k}={",".join(eh.args.get(k, []))}'
                           for k in ('A', 'B', 'O') if k in eh.args))
    parts = [f'.{eh.kind}']
    pos = eh.args.get('_pos', [])
    for v in pos:
        parts.append(_print_value(v))
    for k, v in eh.args.items():
        if k == '_pos':
            continue
        parts.append(f'{k}={_print_value(v)}')
    return ' '.join(parts)


def print_program(prog: Program) -> str:
    lines: List[str] = []
    for stmt in prog.stmts:
        if isinstance(stmt, AliasDecl):
            lines.append(f'.alias {stmt.name} {_print_value(stmt.value)}')
        elif isinstance(stmt, DefaultDecl):
            kw = ' '.join(f'{k}={_print_value(v)}' for k, v in stmt.args.items())
            lines.append(f'.default_{stmt.kind} {kw}')
        elif isinstance(stmt, Label):
            lines.append(f'{stmt.name}:')
        elif isinstance(stmt, Instruction):
            parts = [stmt.mnemonic]
            parts.extend(sorted(stmt.flags))
            for eh in stmt.eh_list:
                parts.append(_print_eh(eh))
            lines.append(' '.join(parts))
    return '\n'.join(lines) + '\n'


# =============================================================================
# Section 9b — v1.5.4 wave-token fragment emitter (wt64v1_spec §21)
# =============================================================================
#
# Since v1.5.1/1.5.2 the Cluster fragment buffer reassembles a wide input
# payload from multiple NoC wave tokens carrying `frag_hdr` = (idx << 4) |
# (total - 1). Wide-consumer primitives (SIG_BMM_3, SIG_TRACE_IIJKL, ...)
# rely on this — but user code (drivers, tests, SDK codegen) has had to
# hand-construct the fragment sequences.
#
# `wave_fragments(wide_payload, wide_bits)` is the canonical splitter:
# given a logical wide payload and its bit-width, it returns the ordered
# list of `(payload_64, frag_hdr)` tuples the fabric expects. Legacy
# single-fragment ops (wide_bits=64) get one element with frag_hdr=0x00
# (Cluster bypass path), so callers have ONE uniform API across all
# v1.0..v1.5.x primitives.
#
# API is intentionally wire-level (integer in, integers out). Tensor-shape
# validation is the caller's responsibility — tests already bit-pack via
# `_pack_int4_128` and similar helpers.


def wave_fragments(wide_payload: int, wide_bits: int) -> List[Tuple[int, int]]:
    """Split a logical wide payload into 64-bit NoC wave-token fragments.

    Returns a list of ``(payload_64, frag_hdr)`` tuples in emission order.
    ``frag_hdr = (idx << 4) | (total - 1)`` per wt64v1_spec.md §17.

    Legacy single-fragment ops: ``wide_bits=64`` returns one tuple with
    ``frag_hdr=0x00`` (Cluster fragment buffer bypasses on this value).

    Supported ``wide_bits``: 0 (empty wave), 64 (legacy), 128 (SIG_TRACE_IIJKL
    A-only), 192 (unused today), 256 (SIG_BMM_3 A+B).
    """
    if wide_bits == 0:
        return []
    if wide_bits not in (64, 128, 192, 256):
        raise AssemblerError(
            f"wave_fragments: wide_bits must be in {{0,64,128,192,256}}, "
            f"got {wide_bits}"
        )
    total_frags   = wide_bits // 64
    total_minus_1 = total_frags - 1
    result: List[Tuple[int, int]] = []
    for idx in range(total_frags):
        payload  = (wide_payload >> (idx * 64)) & ((1 << 64) - 1)
        frag_hdr = ((idx & 0xF) << 4) | (total_minus_1 & 0xF)
        result.append((payload, frag_hdr))
    return result


def wave_fragments_bmm3(a_128: int, b_128: int) -> List[Tuple[int, int]]:
    """Convenience: emit the 4-fragment SIG_BMM_3 wave (v1.5.3 §20.4).
    Layout: A at wide[127:0], B at wide[255:128]."""
    wide = (a_128 & ((1 << 128) - 1)) | ((b_128 & ((1 << 128) - 1)) << 128)
    return wave_fragments(wide, 256)


def wave_fragments_trace_iijkl(a_128: int) -> List[Tuple[int, int]]:
    """Convenience: emit the 2-fragment SIG_TRACE_IIJKL wave (v1.5.5 §21).
    Layout: A at wide[127:0], B unused."""
    return wave_fragments(a_128 & ((1 << 128) - 1), 128)


# =============================================================================
# Section 10 — Public API
# =============================================================================

def assemble(text: str) -> List[int]:
    """Run the full pipeline (Stages 1..6) and return a list of 416-bit
    machine-code integers."""
    prog = parse(text)
    prog = alias_pass(prog)
    prog = default_pass(prog)
    prog = macro_pass(prog)
    prog = legality_pass(prog)
    return encode_pass(prog)


def assemble_one(text: str) -> int:
    """Convenience for inputs that are guaranteed to contain exactly one
    instruction."""
    insts = assemble(text)
    if len(insts) != 1:
        raise AssemblerError(
            f"expected 1 instruction, got {len(insts)}"
        )
    return insts[0]


def lower_to_ll(text: str) -> str:
    """Run Stages 1..5 and pretty-print the resulting LL AST. Useful for
    inspecting what the macro/default passes produced before encoding."""
    prog = parse(text)
    prog = alias_pass(prog)
    prog = default_pass(prog)
    prog = macro_pass(prog)
    prog = legality_pass(prog)
    return print_program(prog)
