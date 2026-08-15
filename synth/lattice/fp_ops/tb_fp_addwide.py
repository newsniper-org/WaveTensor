# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""tb_fp_addwide — correctness sanity for FP_AddWide (v1.8.0c shared wide
FMA-capable adder, spec §23.10.7 Gate 2) BEFORE synthesis.

Bit-exactness authority: scripts/golden_fp32.py.
  * FINAL pack path  vs the REFERENCE layer (ref_add / ref_mul / ref_fma —
    exact arithmetic, single RNE, flush-after-round FTZ, unbounded-exponent
    overflow). Specials (NaN/Inf/zero operands) never reach the block —
    the sequencer's CLASSIFY filters them — so vectors use finite NONZERO
    operands only (normals; DAZ is an operand-load concern upstream).
  * WIDE pack path   vs the SEQUENCER-FAITHFUL round-to-odd helper
    (golden _rto): the exact sum, normalized and jammed to the 48-bit
    internal width, DAZ/FTZ-exempt (no exponent clamping). Exact
    cancellation emits the CANONICAL ZERO encoding (sign=0, exp=-1024,
    sig=0 — the module's own zero-OPERAND convention, v2.0 format
    closure): the fields are NORMATIVE, no longer don't-care, and a
    PACK_WIDE zero feeds back as a zero operand with no translation
    (asserted by wide_zero_canonical_and_closure below).

Operand conventions (the pinned FP_AddWide interface contract):
  value = (-1)^sign * sig * 2^(exp-47)
  P as product : p_sig = ma*mb (raw 48-bit), p_exp = ea+eb+1, p_sign=sa^sb
  C as addend  : c_sig = m24 << 24 (left-aligned), c_exp = e, c_sign = s
  zero operand : sig = 0, exp = -1024 (never anchors)

All streams are driven BACK-TO-BACK (new operands every cycle) with a
LATENCY-deep expectation queue — this simultaneously proves the exact
fixed latency and the 1-result-per-cycle always-flowing contract.

LATENCY is 3: the pre-approved Gate 2 fallback (spec §23.10.7) split the
original single-cycle stage B (24.59 MHz measured, below the 40 MHz gate)
into B1 (add/sub + LZC) and B2 (normalize + round + pack).
"""

import random
import sys
from fractions import Fraction
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "scripts"))
import golden_fp32 as G  # noqa: E402

PACK_WIDE = 0
PACK_FINAL = 1
LATENCY = 3

NUM_ADD_RANDOM = 10_000
NUM_FMA_RANDOM = 10_000
NUM_MUL_RANDOM = 3_000
NUM_WIDE_RANDOM = 1_000


# ---------------------------------------------------------------------------
# operand builders (what the step sequencer will present)
# ---------------------------------------------------------------------------


def split_normal(bits):
    """fp32 normal -> (sign, unbiased exp, 24-bit significand w/ hidden bit)."""
    s = (bits >> 31) & 1
    e = (bits >> 23) & 0xFF
    m = (bits & 0x7FFFFF) | (1 << 23)
    assert 1 <= e <= 254, "TB bug: operand must be a normal"
    return s, e - 127, m


def op_addend(bits):
    """Left-aligned 24-bit significand operand (FADD operand / FMA addend)."""
    s, e, m = split_normal(bits)
    return (s, e, m << 24)


def op_product(a_bits, b_bits):
    """Unrounded 24x24 product operand P."""
    sa, ea, ma = split_normal(a_bits)
    sb, eb, mb = split_normal(b_bits)
    return (sa ^ sb, ea + eb + 1, ma * mb)


OP_ZERO = (0, -1024, 0)

# The PACK_WIDE canonical zero ENCODING equals the zero-OPERAND convention
# (that identity IS the v2.0 format-closure contract being tested).
CANON_ZERO = OP_ZERO


def rand_normal(emin=-126, emax=127):
    return ((random.getrandbits(1) << 31)
            | ((random.randint(emin, emax) + 127) << 23)
            | random.getrandbits(23))


def rand_normal_pair_close(dmax):
    """Two normals whose exponents differ by at most dmax (alignment /
    cancellation coverage)."""
    a = rand_normal(-120, 120)
    ea = ((a >> 23) & 0xFF) - 127
    eb = max(-126, min(127, ea + random.randint(-dmax, dmax)))
    b = ((random.getrandbits(1) << 31) | ((eb + 127) << 23)
         | random.getrandbits(23))
    return a, b


# ---------------------------------------------------------------------------
# golden references
# ---------------------------------------------------------------------------


def wide_ref(p_op, c_op):
    """Exact sum -> (sign, exp, 48-bit round-to-odd significand) or None for
    exact cancellation (which _check_wide maps to the canonical zero
    encoding). The jam uses golden's sequencer-faithful _rto."""
    (ps, pe, psig), (cs, ce, csig) = p_op, c_op
    v = ((-1 if ps else 1) * psig * Fraction(2) ** (pe - 47)
         + (-1 if cs else 1) * csig * Fraction(2) ** (ce - 47))
    if v == 0:
        return None
    s = 0 if v > 0 else 1
    a = abs(v)
    num, den = a.numerator, a.denominator      # den is a power of two
    k = den.bit_length() - 1
    e = G._binade(num, den)
    sh = k + e - 47                            # a * 2^(47-e) == num / 2^sh
    sig48 = (num << -sh) if sh <= 0 else G._rto(num, sh)
    assert (1 << 47) <= sig48 < (1 << 48)
    return s, e, sig48


# ---------------------------------------------------------------------------
# streaming driver (back-to-back, 2-deep expectation queue)
# ---------------------------------------------------------------------------


def _apply(dut, p_op, c_op, mode):
    (ps, pe, psig), (cs, ce, csig) = p_op, c_op
    dut.p_sign.value = ps
    dut.p_exp.value = pe & 0x7FF
    dut.p_sig.value = psig
    dut.c_sign.value = cs
    dut.c_exp.value = ce & 0x7FF
    dut.c_sig.value = csig
    dut.pack_mode.value = mode


def _check_final(dut, exp_bits, label):
    got = int(dut.final_fp32.value)
    assert got == exp_bits, (
        f"{label}: final_fp32 got {got:#010x} expected {exp_bits:#010x}")


def _check_wide(dut, exp, label):
    zero = int(dut.wide_zero.value)
    if exp is None:
        # format-closure contract: exact cancellation emits the CANONICAL
        # ZERO encoding — the fields are normative, no longer don't-care
        assert zero == 1, f"{label}: expected wide_zero"
        exp = CANON_ZERO
    else:
        assert zero == 0, f"{label}: unexpected wide_zero"
    s, e, sig = exp
    we = int(dut.wide_exp.value)
    if we >= 2048:
        we -= 4096
    assert int(dut.wide_sign.value) == s, f"{label}: wide_sign"
    assert we == e, f"{label}: wide_exp got {we} expected {e}"
    got = int(dut.wide_sig.value)
    assert got == sig, (
        f"{label}: wide_sig got {got:#014x} expected {sig:#014x}")


async def _stream(dut, cases, mode, checker, label):
    """cases: list of (p_op, c_op, expected). Returns #checked."""
    pending = []
    checked = 0
    for i, (p_op, c_op, exp) in enumerate(cases):
        if len(pending) == LATENCY:
            j, e0 = pending.pop(0)
            checker(dut, e0, f"{label}[{j}]")
            checked += 1
        _apply(dut, p_op, c_op, mode)
        pending.append((i, exp))
        await FallingEdge(dut.clk)
    while pending:
        j, e0 = pending.pop(0)
        checker(dut, e0, f"{label}[{j}]")
        checked += 1
        await FallingEdge(dut.clk)
    dut._log.info("%s: %d vectors bit-exact", label, checked)
    return checked


async def _start(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    _apply(dut, OP_ZERO, OP_ZERO, PACK_FINAL)
    await FallingEdge(dut.clk)


# ---------------------------------------------------------------------------
# FINAL path — plain FADD (bit-exact vs golden ref_add)
# ---------------------------------------------------------------------------


@cocotb.test()
async def final_add(dut):
    random.seed(0xADD0)
    await _start(dut)

    pairs = []
    # directed: every alignment distance 0..55 x mantissa G/R/S patterns
    for d in range(56):
        for mb in (0x000000, 0x7FFFFF, 0x000001, 0x400000, 0x400001,
                   0x3FFFFF, 0x555555):
            for sb in (0, 1):
                ea = 20
                eb = ea - d
                if eb < -126:
                    continue
                a = ((ea + 127) << 23) | 0x000000
                b = (sb << 31) | ((eb + 127) << 23) | mb
                pairs.append((a, b))
    # directed: RNE ties (1.0 + 2^-24 -> 1.0 ; (1+2^-23) + 2^-24 -> 1+2^-22)
    pairs += [(0x3F800000, 0x33800000), (0x3F800001, 0x33800000)]
    # directed: exact cancellation x + (-x) -> +0 (A4)
    for _ in range(20):
        x = rand_normal()
        pairs.append((x, x ^ 0x80000000))
    # directed: near-total cancellation between close operands
    for _ in range(200):
        pairs.append(rand_normal_pair_close(1))
    # directed: subnormal-magnitude results -> flush-after-round FTZ (both signs)
    for _ in range(200):
        ea = random.randint(-126, -120)
        a = (random.getrandbits(1) << 31) | ((ea + 127) << 23) \
            | random.getrandbits(23)
        b = ((a ^ 0x80000000) & 0xFF800000) | random.getrandbits(23)
        pairs.append((a, b))
    # directed: RNE overflow -> +/-Inf (A6)
    pairs += [(0x7F7FFFFF, 0x7F7FFFFF), (0xFF7FFFFF, 0xFF7FFFFF),
              (0x7F7FFFFF, 0x73000000)]
    # random: uniform + close-exponent + mid-distance mixes
    for _ in range(NUM_ADD_RANDOM // 2):
        pairs.append((rand_normal(), rand_normal()))
    for _ in range(NUM_ADD_RANDOM // 4):
        pairs.append(rand_normal_pair_close(3))
    for _ in range(NUM_ADD_RANDOM // 4):
        pairs.append(rand_normal_pair_close(30))

    cases = [(op_addend(a), op_addend(b), G.ref_add(a, b)) for a, b in pairs]
    await _stream(dut, cases, PACK_FINAL, _check_final, "final_add")


# ---------------------------------------------------------------------------
# FINAL path — FMA (bit-exact vs golden ref_fma; F1 single-rounding, F4
# exact cancellation)
# ---------------------------------------------------------------------------


@cocotb.test()
async def final_fma(dut):
    random.seed(0xF3A0)
    await _start(dut)

    triples = []
    # directed: exact cancellation a*b == -c -> +0 (F4)
    triples += [(0x3FC00000, 0x3FA00000, 0xBFF00000),   # 1.5*1.25 - 1.875
                (0x40000000, 0x3F800000, 0xC0000000),   # 2*1 - 2
                (0xC0400000, 0x3E800000, 0x3F400000)]   # -3*0.25 + 0.75
    # directed: c = -RN(a*b) — deep product-vs-addend cancellation (the
    # Markstein-correction shape; result is the tiny rounding residual)
    for _ in range(300):
        a, b = rand_normal(-30, 30), rand_normal(-30, 30)
        c = G.ref_mul(a, b) ^ 0x80000000
        if (c >> 23) & 0xFF in (0, 0xFF):
            continue
        triples.append((a, b, c))
    # directed: addend far above / far below the product (sticky extremes)
    for _ in range(300):
        a, b = rand_normal(-10, 10), rand_normal(-10, 10)
        c = rand_normal(*random.choice(((-126, -90), (80, 127))))
        triples.append((a, b, c))
    # random
    for _ in range(NUM_FMA_RANDOM):
        triples.append((rand_normal(-63, 63), rand_normal(-63, 63),
                        rand_normal()))

    cases = [(op_product(a, b), op_addend(c), G.ref_fma(a, b, c))
             for a, b, c in triples]
    await _stream(dut, cases, PACK_FINAL, _check_final, "final_fma")


# ---------------------------------------------------------------------------
# FINAL path — FMUL pack-only pass (product P + zero C; vs golden ref_mul)
# ---------------------------------------------------------------------------


@cocotb.test()
async def final_mul_pack(dut):
    random.seed(0x3712)
    await _start(dut)

    pairs = []
    # directed: overflow / flush-after-round-FTZ exponent extremes,
    # incl. min_normal*0.5 -> +/-0 and the tie at 2^-127*1.FFFFFF
    pairs += [(0x00800000, 0x3F000000), (0x80800000, 0x3F000000),
              (0x00FFFFFF, 0x3F000000), (0x7F7FFFFF, 0x7F7FFFFF),
              (0x7F000000, 0x40000000), (0xFF7FFFFF, 0x7F000000)]
    for _ in range(400):
        pairs.append((rand_normal(-126, -60), rand_normal(-126, -60)))
        pairs.append((rand_normal(60, 127), rand_normal(60, 127)))
    for _ in range(NUM_MUL_RANDOM):
        pairs.append((rand_normal(), rand_normal()))

    cases = [(op_product(a, b), OP_ZERO, G.ref_mul(a, b)) for a, b in pairs]
    await _stream(dut, cases, PACK_FINAL, _check_final, "final_mul_pack")


# ---------------------------------------------------------------------------
# WIDE path — round-to-odd to the 48-bit internal width, flush-exempt
# (vs the golden sequencer-faithful _rto helper on the exact sum)
# ---------------------------------------------------------------------------


@cocotb.test()
async def wide_round_to_odd(dut):
    random.seed(0x33DE)
    await _start(dut)

    def rand_sig():
        return random.getrandbits(48) | (1 << 46)   # in [2^46, 2^48)

    cases = []
    # exact cancellation -> wide_zero + canonical zero fields
    for _ in range(20):
        s = random.getrandbits(1)
        sig, e = rand_sig(), random.randint(-140, 140)
        cases.append(((s, e, sig), (s ^ 1, e, sig), None))
    # Markstein-correction shape: q0 (left-aligned 24-bit) vs a wide
    # opposite-sign product a hair away — deep cancellation, wide result
    for _ in range(200):
        a, b = rand_normal(-30, 30), rand_normal(-30, 30)
        q = G.ref_mul(a, b)
        if (q >> 23) & 0xFF in (0, 0xFF):
            continue
        p_op = op_product(a, b)
        c_op = op_addend(q ^ 0x80000000)
        cases.append((p_op, c_op, wide_ref(p_op, c_op)))
    # far-sticky wide adds (exponent gap beyond the alignment window)
    for _ in range(200):
        p_op = (random.getrandbits(1), random.randint(-40, 40), rand_sig())
        c_op = (random.getrandbits(1),
                p_op[1] - random.randint(45, 120), rand_sig())
        cases.append((p_op, c_op, wide_ref(p_op, c_op)))
    # generic random wide operands (incl. flush-exempt exponents far
    # outside fp32 range — DAZ/FTZ exemption means no clamping anywhere)
    for _ in range(NUM_WIDE_RANDOM):
        p_op = (random.getrandbits(1), random.randint(-300, 300), rand_sig())
        c_op = (random.getrandbits(1),
                p_op[1] + random.randint(-52, 52), rand_sig())
        cases.append((p_op, c_op, wide_ref(p_op, c_op)))

    await _stream(dut, cases, PACK_WIDE, _check_wide, "wide_rto")


# ---------------------------------------------------------------------------
# WIDE path — canonical zero encoding + I/O closure (v2.0 format closure:
# exact cancellation emits (sign=0, exp=-1024, sig=0), the module's own
# zero-OPERAND convention, so a PACK_WIDE zero feeds back with no
# translation and never anchors alignment)
# ---------------------------------------------------------------------------


@cocotb.test()
async def wide_zero_canonical_and_closure(dut):
    random.seed(0xC104)
    await _start(dut)

    # -- 1. directed exact cancellations a + (-a): fields must BE canonical
    sig_extremes = (1 << 46, (1 << 46) + 1, (1 << 47) - 1, 1 << 47,
                    (1 << 47) + 1, (1 << 48) - 2, (1 << 48) - 1)
    cases = []
    for sig in sig_extremes:
        for e in (-1000, -300, -126, -1, 0, 1, 127, 300, 1000):
            for s in (0, 1):
                cases.append(((s, e, sig), (s ^ 1, e, sig), None))
    # FMA-shaped exact cancellation: b a power of two makes the raw product
    # exact, so P + (-RN(a*b) as addend) cancels exactly through alignment
    for _ in range(50):
        a = rand_normal(-30, 30)
        b = ((random.getrandbits(1) << 31)
             | ((random.randint(-30, 30) + 127) << 23))
        q = G.ref_mul(a, b)
        cases.append((op_product(a, b), op_addend(q ^ 0x80000000), None))
    # zero + zero: the canonical zero is itself closed
    cases.append((OP_ZERO, OP_ZERO, None))
    await _stream(dut, cases, PACK_WIDE, _check_wide, "wide_canon")

    # -- 2. I/O closure: capture the DUT's OWN wide-zero output fields and
    # feed them back VERBATIM as a zero operand (no translation) — this is
    # the closure property itself, not a re-encoding by the TB
    x = rand_normal()
    _apply(dut, op_addend(x), op_addend(x ^ 0x80000000), PACK_WIDE)
    await FallingEdge(dut.clk)
    _apply(dut, OP_ZERO, OP_ZERO, PACK_FINAL)   # don't touch the wide group
    for _ in range(LATENCY - 1):
        await FallingEdge(dut.clk)
    assert int(dut.wide_zero.value) == 1, "closure: expected wide_zero"
    we = int(dut.wide_exp.value)
    if we >= 2048:
        we -= 4096
    z_op = (int(dut.wide_sign.value), we, int(dut.wide_sig.value))
    assert z_op == CANON_ZERO, (
        f"closure: captured wide-zero fields {z_op} != canonical "
        f"{CANON_ZERO} (== the zero-operand input convention)")

    def rand_sig():
        return random.getrandbits(48) | (1 << 46)   # in [2^46, 2^48)

    closure = []
    # both operand slots, assorted partners across the flush-exempt range
    for _ in range(400):
        w = (random.getrandbits(1), random.randint(-1000, 1000), rand_sig())
        closure.append((z_op, w, wide_ref(z_op, w)))
        closure.append((w, z_op, wide_ref(w, z_op)))
    # alignment-anchor hazard band: partners with TINY negative exponents —
    # an exp-0 zero would anchor ABOVE these and corrupt the result; the
    # canonical exp=-1024 must never anchor (strictly below every partner)
    for e in range(-1023, -990):
        w = (random.getrandbits(1), e, rand_sig())
        closure.append((z_op, w, wide_ref(z_op, w)))
        closure.append((w, z_op, wide_ref(w, z_op)))
    closure.append((z_op, z_op, None))
    await _stream(dut, closure, PACK_WIDE, _check_wide, "wide_closure")

    # -- 3. the same fed-back zero through the FINAL pack (the FMUL
    # pack-only operand convention): P = zero + addend c packs c verbatim
    finals = []
    for _ in range(100):
        c = rand_normal()
        finals.append((z_op, op_addend(c), G.ref_add(c, 0)))
    await _stream(dut, finals, PACK_FINAL, _check_final, "wide_closure_final")


# ---------------------------------------------------------------------------
# pack_mode gating — each output group updates only on its own mode
# ---------------------------------------------------------------------------


@cocotb.test()
async def pack_mode_hold(dut):
    random.seed(0x401D)
    await _start(dut)

    a1, b1 = rand_normal(), rand_normal()
    a2, b2 = rand_normal(), rand_normal()
    f1 = G.ref_add(a1, b1)
    f2 = G.ref_add(a2, b2)
    pw = (0, 10, (1 << 47) | 0xABCDEF)
    cw = (0, 5, (1 << 47) | 0x123456)
    w1 = wide_ref(pw, cw)

    # F0: f1 (FINAL) -> visible after LATENCY=3 edges (at F3)
    _apply(dut, op_addend(a1), op_addend(b1), PACK_FINAL)
    await FallingEdge(dut.clk)
    # F1: w1 (WIDE) -> visible at F4
    _apply(dut, pw, cw, PACK_WIDE)
    await FallingEdge(dut.clk)
    # F2: f2 (FINAL) -> visible at F5 (inputs then hold f2/FINAL, which
    # only re-latches the same FINAL value afterwards)
    _apply(dut, op_addend(a2), op_addend(b2), PACK_FINAL)
    await FallingEdge(dut.clk)
    # F3: f1 result must be visible NOW
    _check_final(dut, f1, "hold.f1")
    await FallingEdge(dut.clk)
    # F4: w1 visible; final_fp32 must still HOLD f1 (the completing op at
    # this edge was WIDE and must not touch the FINAL group)
    _check_final(dut, f1, "hold.f1-held")
    _check_wide(dut, w1, "hold.w1")
    await FallingEdge(dut.clk)
    # F5: f2 visible; wide group must still hold w1 (completing op FINAL)
    _check_final(dut, f2, "hold.f2")
    _check_wide(dut, w1, "hold.w1-held")
    dut._log.info("pack_mode_hold: output-group gating verified")
