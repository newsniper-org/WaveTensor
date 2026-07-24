#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""v1.8.0c core + v1.8.0d format layer — bit-exact fp32 golden model (the
single reference for all fp tests: directed vectors, random sweeps,
release-gate exhaustive sweeps).

TWO cleanly separated layers, all entry points take/return fp32 bit
patterns (python ints):

REFERENCE layer (ref_*): correctly-rounded fp32 add/sub/mul/fma/div and
reference rsqrt/exp2 under the pinned WT64v1 policy. Core arithmetic is
EXACT (python int/Fraction, round exactly once — the FMA golden does not
rest on float64 double-rounding luck; rsqrt RNE is decided by exact
integer square comparisons). ref_exp2 uses 192-bit mpmath for the
transcendental core (correct rounding would need the true 2^x within
2^-192 of a rounding boundary — far beyond every known binary32
hardest-to-round case), with exact fast paths for integers and the
overflow/underflow comparator cells.

SEQUENCER-FAITHFUL layer (micro_*): models the EXACT step sequences
of the v1.8.0c MU-hosted fp32 step sequencer in INTEGER arithmetic so it
is bit-predictive of RTL:
  micro_rsqrt  seed ROM {exp[0], mant[22:16]} from the SHIPPED sidecar
               include/generated/fp_frsqrt_seed_rom.json; h = x'/2 exact;
               THREE NR iterations y = y*(1.5 - h*y*y) in Q2.28
               (widened-significand, round-to-odd intermediates, h*y
               first); single final RNE pack; exponent -k assembled at
               pack (pinned range reduction x = x'*4^k, x' in [1,4)).
  micro_exp2   exact n+f split; integer bypass; degree-6 Horner in Q2.30
               with round-to-odd products over the SHIPPED Q1.30
               coefficients (fp_fexp2_coeffs.json, c0 == 1.0 exact);
               exponent n added at pack; FTZ(RN_unbounded) at pack.
  micro_div    scale-invariant Newton reciprocal (3 iterations, Q2.30
               round-to-odd, seed fp_fdiv_seed_rom.json) + Markstein
               correction q = RNE(q0 + r*(ma - q0*mb)) through the exact
               wide fused microstep; exponent ea-eb assembled once at
               pack, overflow/underflow only at pack.
  micro_fscalar FS_ADD/SUB/MUL/FMA are the reference functions verbatim:
               the RTL wide datapath holds the exact value (sticky-
               preserving) and rounds ONCE, which is bit-identical to the
               correctly-rounded reference. FS_DIV is micro_div.
INTERNAL micro-steps are exempt from DAZ/FTZ (pinned — otherwise
Markstein residuals flush and FDIV misrounds near underflow).

v1.8.0d FORMAT LAYER (COMMIT 1, golden-before-RTL) — reference semantics
for 0x77 CVT, 0x73 ACC_ELEMWISE (OPREF form) and the 0x7C STORE_QUANT
fp-dest packer, under the COMMIT-0 pins of the v1.8.0d spec:
  ref_widen_f16 / ref_widen_bf16   exact injections; widen of ANY f16/bf16
                                   NaN -> fp32 canonical qNaN 0x7FC00000
                                   (sNaN quieted); f16 subnormal inputs
                                   honored exactly (DAZ BYPASSED for
                                   non-fp32 CVT sources, op-class-
                                   conditional capture pin); bf16
                                   subnormal inputs -> SIGNED ZERO at the
                                   CVT output (DAZ-consistent pin).
  ref_narrow_f32                   THE single f32->f16/bf16 narrowing
                                   authority (0x7C == 0x77 bit-identity
                                   clause true BY CONSTRUCTION): disjoint
                                   round/sticky RNE, rebias, overflow ->
                                   +/-Inf (never max-finite), FTZ-at-f16-
                                   destination, per-format canonical qNaN
                                   (f16 0x7E00 / bf16 0x7FC0, sign
                                   dropped), DAZ pre-stage folded in
                                   (pinned identically at both RTL sites).
  ref_i2f / micro_i2f_acc          I2F int4/int8 exact; dtype-0x4 sext64
                                   (int32/int64) single-RNE reference plus
                                   the sequencer-faithful two-pass
                                   pass-1-RTO / pass-2-RNE ingress model.
  ref_f2i                          F2I RNE-then-saturate; NaN -> 0
                                   (deterministic DATA, CUDA cvt.sat
                                   precedent, knowledge-based label);
                                   +/-Inf -> dtype min/max; results sext64.
  cvt / micro_cvt                  0x77 entry point keyed by sub-op+dtype,
                                   64-bit payload rows in/out (f16/bf16
                                   {48'h0,h}; f32 {32'h0,f}; ints sext64).
  accew / micro_accew              0x73 fused single-rounding fp32
                                   a*B[63:32]+B[31:0] riding ref_fma /
                                   micro_fscalar(FS_FMA) verbatim.
  store_quant                      0x7C fp-dest {48'h0, narrow(f32)} —
                                   a direct call into ref_narrow_f32.

Pinned policy (spec v1.8.0c normative table):
  RNE only. DAZ: denormal OPERANDS flush to same-signed zero at load
  (min_normal 0x00800000 never flushed). FTZ: flush-AFTER-round with
  unbounded-exponent RNE — if |RN_unbounded(x)| < min_normal, replace
  with same-signed zero. Canonical qNaN 0x7FC00000 for every NaN-
  producing case (sNaN quieted to the canonical pattern, no trap).
  IEEE specials produce DATA, never error_flag.
  ulp(x) = 2^(e-23), e = exponent of the infinitely-precise result's
  binade (Goldberg; at binade edges use the smaller binade).
"""

import json
import math
import sys
from fractions import Fraction
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
_GEN = REPO / "include" / "generated"

sys.path.insert(0, str(REPO / "asm"))
from generated_isa_tables import FSCALAR_OP_CODE  # noqa: E402

F32_SIGN = 0x80000000
F32_QNAN = 0x7FC00000
F32_PINF = 0x7F800000
F32_NINF = 0xFF800000
F32_MIN_NORMAL = 0x00800000
F32_ONE = 0x3F800000

# ---------------------------------------------------------------------------
# shipped-artifact tables (the sweeps run against these, never reconstructions)
# ---------------------------------------------------------------------------

FRSQRT_ROM = json.loads((_GEN / "fp_frsqrt_seed_rom.json").read_text())["entries"]
FDIV_ROM = json.loads((_GEN / "fp_fdiv_seed_rom.json").read_text())["entries"]
EXP2_COEFFS = json.loads((_GEN / "fp_fexp2_coeffs.json").read_text())["coeffs_q30"]

RSQRT_FRAC = 28   # Q2.28 — widened-significand width of the rsqrt step sequence
DIV_FRAC = 30     # Q2.30 — reciprocal-iteration width of the div step sequence
EXP2_FRAC = 30    # Q2.30 — Horner width of the exp2 step sequence

# ---------------------------------------------------------------------------
# decode / rounding primitives
# ---------------------------------------------------------------------------


def decode(bits):
    """(sign, kind, value) with DAZ at operand load. kind in
    {'nan','inf','zero','fin'}; value is an exact Fraction for 'fin'.
    Denormals (exp field 0, mantissa != 0) flush to same-signed zero;
    min_normal is E=1 and never flushed."""
    s = (bits >> 31) & 1
    e = (bits >> 23) & 0xFF
    m = bits & 0x7FFFFF
    if e == 0xFF:
        return (s, "nan", None) if m else (s, "inf", None)
    if e == 0:
        return (s, "zero", None)          # true zero and DAZ-flushed denormal
    return (s, "fin", Fraction(((1 << 23) + m) * (-1 if s else 1), 1 << 23)
            * Fraction(2) ** (e - 127))


def _zero(sign):
    return sign << 31


def _inf(sign):
    return (sign << 31) | F32_PINF


def _rne_rat(num, den):
    """RNE of num/den (num>=0, den>0) to an integer, ties to even."""
    q, r = divmod(num, den)
    if 2 * r > den or (2 * r == den and (q & 1)):
        q += 1
    return q


def _binade(num, den):
    """e with 2^e <= num/den < 2^(e+1) for positive num/den.
    Bit-length bound gives 2^(e0-1) <= v < 2^(e0+1); one exact compare."""
    e = num.bit_length() - den.bit_length()
    ge = num >= (den << e) if e >= 0 else (num << -e) >= den
    return e if ge else e - 1


def rne_unbounded(v):
    """RN-even of positive Fraction v to a 24-bit significand with
    unbounded exponent. Returns (m24, e) with m24 in [2^23, 2^24),
    value = m24 * 2^(e-23)."""
    num, den = v.numerator, v.denominator
    e = _binade(num, den)
    sh = 23 - e
    m = _rne_rat(num << sh, den) if sh >= 0 else _rne_rat(num, den << -sh)
    if m == (1 << 24):
        m = 1 << 23
        e += 1
    return m, e


def pack_rne_ftz(sign, v):
    """RN_unbounded then FTZ/overflow: |RN(v)| >= 2^128 -> Inf,
    |RN(v)| < min_normal -> same-signed zero. v is a nonzero Fraction
    whose sign is carried separately (pass abs value)."""
    assert v > 0
    m, e = rne_unbounded(v)
    if e > 127:
        return _inf(sign)
    if e < -126:
        return _zero(sign)
    return (sign << 31) | ((e + 127) << 23) | (m - (1 << 23))


def _pack_signed(v):
    """pack_rne_ftz with the sign taken from the exact nonzero value."""
    return pack_rne_ftz(0 if v > 0 else 1, abs(v))


def ulp(v):
    """ulp of the infinitely-precise result magnitude v (Fraction > 0),
    per the pinned Goldberg convention: 2^(e-23) for the binade of v,
    the SMALLER binade when v sits exactly on a binade edge."""
    assert v > 0
    num, den = v.numerator, v.denominator
    e = _binade(num, den)
    on_edge = num == (den << e) if e >= 0 else (num << -e) == den
    if on_edge:
        e -= 1
    return Fraction(2) ** (e - 23)


def bits_to_frac(bits):
    """Exact Fraction value of a finite fp32 pattern (denormals exact,
    NO DAZ — measurement helper, not an operand loader)."""
    s = (bits >> 31) & 1
    e = (bits >> 23) & 0xFF
    m = bits & 0x7FFFFF
    assert e != 0xFF
    if e == 0:
        v = Fraction(m, 1 << 23) * Fraction(2) ** (-126)
    else:
        v = Fraction((1 << 23) + m, 1 << 23) * Fraction(2) ** (e - 127)
    return -v if s else v


# ---------------------------------------------------------------------------
# REFERENCE layer — correctly rounded, exact core
# ---------------------------------------------------------------------------


def ref_add(a, b):
    sa, ka, va = decode(a)
    sb, kb, vb = decode(b)
    if ka == "nan" or kb == "nan":
        return F32_QNAN
    if ka == "inf" and kb == "inf":
        return _inf(sa) if sa == sb else F32_QNAN
    if ka == "inf":
        return _inf(sa)
    if kb == "inf":
        return _inf(sb)
    if ka == "zero" and kb == "zero":
        return _zero(sa) if sa == sb else _zero(0)      # (+0)+(-0) = +0
    v = (va or 0) + (vb or 0)
    if v == 0:
        return _zero(0)                                 # x + (-x) = +0 (RNE)
    return _pack_signed(v)


def ref_sub(a, b):
    return ref_add(a, b ^ F32_SIGN)


def ref_mul(a, b):
    sa, ka, va = decode(a)
    sb, kb, vb = decode(b)
    sign = sa ^ sb                                      # XOR always, incl. zeros
    if ka == "nan" or kb == "nan":
        return F32_QNAN
    if ka == "inf" or kb == "inf":
        if ka == "zero" or kb == "zero":
            return F32_QNAN                             # Inf * 0
        return _inf(sign)
    if ka == "zero" or kb == "zero":
        return _zero(sign)
    return pack_rne_ftz(sign, abs(va * vb))


def ref_fma(a, b, c):
    """Fused a*b + c: exact product held wide, SINGLE final RNE."""
    sa, ka, va = decode(a)
    sb, kb, vb = decode(b)
    sc, kc, vc = decode(c)
    if ka == "nan" or kb == "nan" or kc == "nan":
        return F32_QNAN                                 # incl. Inf*0+NaN
    sp = sa ^ sb
    if ka == "inf" or kb == "inf":
        if ka == "zero" or kb == "zero":
            return F32_QNAN                             # Inf*0 + c
        if kc == "inf" and sc != sp:
            return F32_QNAN                             # (+Inf*x) + (-Inf)
        return _inf(sp)
    if kc == "inf":
        return _inf(sc)
    if ka == "zero" or kb == "zero":                    # exact (+-0) + c
        if kc == "zero":
            return _zero(sp) if sp == sc else _zero(0)
        return _pack_signed(vc)
    v = va * vb + (vc or 0)
    if v == 0:
        return _zero(0)                                 # exact cancellation
    return _pack_signed(v)


def ref_div(a, b):
    sa, ka, va = decode(a)
    sb, kb, vb = decode(b)
    sign = sa ^ sb
    if ka == "nan" or kb == "nan":
        return F32_QNAN
    if ka == "inf":
        return F32_QNAN if kb == "inf" else _inf(sign)  # Inf/Inf; Inf/finite
    if kb == "inf":
        return _zero(sign)                              # finite/Inf
    if kb == "zero":
        # 0/0 = qNaN; finite-nonzero/(+-0) = sign-XOR Inf (x/denormal lands
        # here through DAZ — pinned as its own row)
        return F32_QNAN if ka == "zero" else _inf(sign)
    if ka == "zero":
        return _zero(sign)
    return pack_rne_ftz(sign, abs(va / vb))


def _rne_sqrt_rat(num, den):
    """RNE of sqrt(num/den) (positive ints) to an integer, ties to even —
    exact via isqrt + half-point square comparison."""
    n0 = math.isqrt(num * den) // den
    lhs, rhs = 4 * num, den * (2 * n0 + 1) ** 2
    if lhs > rhs or (lhs == rhs and (n0 & 1)):
        return n0 + 1
    return n0


def ref_rsqrt(a):
    s, k, v = decode(a)
    if k == "nan":
        return F32_QNAN
    if k == "zero":
        return _inf(s)                                  # rsqrt(+-0) = +-Inf
    if s:
        return F32_QNAN                                 # x < 0 (incl. -Inf)
    if k == "inf":
        return _zero(0)                                 # rsqrt(+Inf) = +0
    # r = sqrt(den/num); binade by exact comparison r >= 2^t <=> den >= num*4^t
    num, den = v.numerator, v.denominator
    e = (den.bit_length() - num.bit_length()) // 2 - 1
    while (den >= (num << (2 * (e + 1))) if e + 1 >= 0
           else (den << (2 * -(e + 1))) >= num):
        e += 1
    sh = 23 - e
    m = (_rne_sqrt_rat(den << (2 * sh), num) if sh >= 0
         else _rne_sqrt_rat(den, num << (2 * -sh)))
    if m == (1 << 24):
        m = 1 << 23
        e += 1
    return ((e + 127) << 23) | (m - (1 << 23))          # always normal range


def _exp2_frac(v):
    """2^v as a Fraction, 192-bit mpmath core (see module docstring)."""
    import mpmath
    with mpmath.workprec(192):
        y = mpmath.power(2, mpmath.mpf(v.numerator) / mpmath.mpf(v.denominator))
        sign, man, exp, _ = y._mpf_
        assert sign == 0 and man > 0
        return Fraction(man, 1) * Fraction(2) ** exp


def ref_exp2(a):
    s, k, v = decode(a)
    if k == "nan":
        return F32_QNAN
    if k == "inf":
        return F32_PINF if s == 0 else _zero(0)         # exp2(-Inf) = +0
    if k == "zero":
        return F32_ONE                                  # exp2(+-0) = 1.0
    if v >= 128:
        return F32_PINF                                 # exact: >= RNE overflow
    if v <= -150:
        return _zero(0)
    if v.denominator == 1:                              # exact 2^n
        n = v.numerator
        return _zero(0) if n < -126 else ((n + 127) << 23)
    return pack_rne_ftz(0, _exp2_frac(v))


# ---------------------------------------------------------------------------
# SEQUENCER-FAITHFUL layer — integer models of the pinned step programs
# ---------------------------------------------------------------------------


def _rto(p, shift):
    """Round-to-odd (jamming): truncate, OR sticky into the LSB."""
    q = p >> shift
    if p & ((1 << shift) - 1):
        q |= 1
    return q


def _rne_shift(x, shift):
    """RNE of x * 2^-shift (x >= 0, shift >= 1) to an integer."""
    q = x >> shift
    rem = x & ((1 << shift) - 1)
    half = 1 << (shift - 1)
    if rem > half or (rem == half and (q & 1)):
        q += 1
    return q


def micro_rsqrt(a):
    F = RSQRT_FRAC
    s, k, v = decode(a)
    if k == "nan":
        return F32_QNAN
    if k == "zero":
        return _inf(s)
    if s:
        return F32_QNAN
    if k == "inf":
        return _zero(0)
    E = (a >> 23) & 0xFF
    m = a & 0x7FFFFF
    p = (E - 127) & 1                       # x' = 1.m * 2^p in [1,4)
    kk = ((E - 127) - p) >> 1               # x = x' * 4^kk
    y = FRSQRT_ROM[((E & 1) << 7) | (m >> 16)] << (F - 9)
    xq = ((1 << 23) + m) << (F - 23 + p)    # x' in Q2.F (exact)
    h = xq >> 1                             # h = x'/2 (exact)
    for _ in range(3):
        t1 = _rto(h * y, F)                 # h*y first (pinned order)
        t2 = _rto(t1 * y, F)
        y = _rto(y * ((3 << (F - 1)) - t2), F)
    if y >= (1 << F):
        e_res, frac = -kk, y
    else:
        e_res, frac = -kk - 1, y << 1       # normalize to [1,2), F frac bits
    m24 = _rne_shift(frac, F - 23)
    if m24 == (1 << 24):
        m24 = 1 << 23
        e_res += 1
    return ((e_res + 127) << 23) | (m24 - (1 << 23))    # always normal range


def micro_div(a, b):
    F = DIV_FRAC
    sa, ka, _ = decode(a)
    sb, kb, _ = decode(b)
    sign = sa ^ sb
    if ka == "nan" or kb == "nan":
        return F32_QNAN
    if ka == "inf":
        return F32_QNAN if kb == "inf" else _inf(sign)
    if kb == "inf":
        return _zero(sign)
    if kb == "zero":
        return F32_QNAN if ka == "zero" else _inf(sign)
    if ka == "zero":
        return _zero(sign)
    ma = (a & 0x7FFFFF) | (1 << 23)         # significands in [1,2), Q1.23
    mb = (b & 0x7FFFFF) | (1 << 23)
    ea = ((a >> 23) & 0xFF) - 127
    eb = ((b >> 23) & 0xFF) - 127
    r = FDIV_ROM[(b >> 15) & 0xFF] << (F - 9)           # Q2.F
    for _ in range(3):                       # r = r*(2 - mb*r)
        t = _rto(mb * r, 23)
        r = _rto(r * ((2 << F) - t), F)
    # q0 = RNE24(ma * r), value in (0.5, 2): binade split, then RNE
    p = ma * r                               # frac 23+F = 53
    qe = 0 if p >= (1 << (23 + F)) else -1   # value >= 1 ?
    q24 = _rne_shift(p, F + qe)              # 24-bit significand of q0
    if q24 == (1 << 24):
        q24 = 1 << 23
        qe += 1
    # Markstein: resid = ma - q0*mb (exact), q = RNE(q0 + resid*r) — single
    # rounding through the exact wide fused microstep, DAZ/FTZ-exempt
    resid = (ma << (23 - qe)) - q24 * mb     # * 2^(qe-46)
    T = (q24 << (23 + F)) + resid * r        # (q0 + resid*r) * 2^(qe-46-F)
    assert T > 0
    bl = T.bit_length()
    e_val = (bl - 1) + qe - 46 - F
    m24 = _rne_shift(T, bl - 24)
    if m24 == (1 << 24):
        m24 = 1 << 23
        e_val += 1
    e_final = ea - eb + e_val                # exponent assembled once at pack
    if e_final > 127:
        return _inf(sign)
    if e_final < -126:
        return _zero(sign)                   # FTZ at pack only
    return (sign << 31) | ((e_final + 127) << 23) | (m24 - (1 << 23))


def micro_exp2(a):
    F = EXP2_FRAC
    s, k, v = decode(a)
    if k == "nan":
        return F32_QNAN
    if k == "inf":
        return F32_PINF if s == 0 else _zero(0)
    if k == "zero":
        return F32_ONE
    if v >= 128:
        return F32_PINF                      # comparator fast path (exact)
    if v <= -150:
        return _zero(0)                      # the ONLY comparator path below
    n = v.numerator // v.denominator         # floor
    f = v - n                                # exact, in [0,1)
    if f == 0:                               # integer bypass (pinned)
        return _zero(0) if n < -126 else ((n + 127) << 23)
    f_fix = (f.numerator << F) // f.denominator          # floor(f * 2^F)
    acc = EXP2_COEFFS[6]
    for i in range(5, -1, -1):               # Horner, Q2.F round-to-odd
        acc = _rto(acc * f_fix, F) + EXP2_COEFFS[i]
    bl = acc.bit_length()                    # P(f) in [1, 2+eps)
    e_val = n + (bl - (F + 1))
    m24 = _rne_shift(acc, bl - 24)
    if m24 == (1 << 24):
        m24 = 1 << 23
        e_val += 1
    if e_val > 127:                          # RNE overflow at pack
        return F32_PINF
    if e_val < -126:                         # FTZ(RN_unbounded) at pack
        return _zero(0)
    return ((e_val + 127) << 23) | (m24 - (1 << 23))


# ---------------------------------------------------------------------------
# FSCALAR sub-op dispatch (imm16[7:4] per the single-source table)
# ---------------------------------------------------------------------------

_REF_FSCALAR = {
    FSCALAR_OP_CODE["FS_ADD"]: lambda a, b, c: ref_add(a, b),
    FSCALAR_OP_CODE["FS_SUB"]: lambda a, b, c: ref_sub(a, b),
    FSCALAR_OP_CODE["FS_MUL"]: lambda a, b, c: ref_mul(a, b),
    FSCALAR_OP_CODE["FS_FMA"]: lambda a, b, c: ref_fma(a, b, c),
    FSCALAR_OP_CODE["FS_DIV"]: lambda a, b, c: ref_div(a, b),
}

_MICRO_FSCALAR = dict(_REF_FSCALAR)
_MICRO_FSCALAR[FSCALAR_OP_CODE["FS_DIV"]] = lambda a, b, c: micro_div(a, b)


def ref_fscalar(subop, a, b, c=0):
    return _REF_FSCALAR[subop](a, b, c)


def micro_fscalar(subop, a, b, c=0):
    """FS_ADD/SUB/MUL/FMA: the RTL wide path is exact-then-round-once, so
    the reference IS the micro model. FS_DIV: Newton+Markstein step sequence."""
    return _MICRO_FSCALAR[subop](a, b, c)


# ===========================================================================
# v1.8.0d FORMAT LAYER — 0x77 CVT / 0x73 ACC_ELEMWISE / 0x7C fp-dest packer
# ===========================================================================

F16_QNAN = 0x7E00      # per-format canonical qNaN = fp32 0x7FC00000 top 16b
F16_PINF = 0x7C00
BF16_QNAN = 0x7FC0     # = fp32 canonical qNaN top 16 bits (truncation-
BF16_PINF = 0x7F80     #   consistent, COMMIT-0 pin 1)

# dtype codes — single-source transcription of isa/wt64v1_isa.json
# fp_block.dtype_codes. NOTE: the general table names 0x4 "f32"; AT 0x77 the
# pinned conversion-dtype rule extension (COMMIT-0 pin 10) makes dtype 0x4
# name the accumulator-format INTEGER endpoint (int32/int64 <-> fp32),
# direction from the sub-op. dtype 0x5 (f64) stays decode_error.
DT_INT4 = 0x0
DT_INT8 = 0x1
DT_F16 = 0x2
DT_BF16 = 0x3
DT_ACC_INT = 0x4

# 0x77 CVT sub-op codes (imm16[7:4]; absent imm16 defaults to WIDEN_TO_F32).
# COMMIT 2 emits these as the generated cvt_op_codes table (single-source in
# isa/wt64v1_isa.json); until then this is the pinned transcription and the
# freshness test of COMMIT 2 must assert equality against it.
CVT_WIDEN_TO_F32 = 0x0
CVT_NARROW_FROM_F32 = 0x1

# Golden intermediate width for the two-pass dtype-0x4 I2F ingress (see
# micro_i2f_acc): the a_in/c_in 32-bit FSCALAR-style split. Any RTL
# intermediate width >= 26 with a sticky-preserving pass-1 jam is
# bit-equivalent (both equal the single RNE from the exact integer).
I2F_PASS1_BITS = 32

F2I_BOUNDS = {
    DT_INT4: (-8, 7),
    DT_INT8: (-128, 127),
    DT_ACC_INT: (-(1 << 31), (1 << 31) - 1),   # F2I dtype 0x4 = int32
}

_M64 = (1 << 64) - 1


# ---------------------------------------------------------------------------
# widen (CVT sub-op 0x0): exact injections, DAZ bypassed at operand capture
# ---------------------------------------------------------------------------


def ref_widen_f16(h):
    """f16 -> f32 EXACT injection (CVT WIDEN, dtype 0x2). The FP_StepSeq
    operand-load DAZ is BYPASSED for non-fp32 CVT sources (op-class-
    conditional capture pin — the confirmed I2F(5)-flushes-to-zero bug
    fix), so f16 subnormals are honored and inject exactly: every f16
    value is fp32-representable (min subnormal 2^-24 >> fp32 min normal
    2^-126). Widen of ANY NaN (sNaN quieted) -> fp32 canonical qNaN
    0x7FC00000, sign dropped (COMMIT-0 pin 2)."""
    h &= 0xFFFF
    s = (h >> 15) & 1
    e = (h >> 10) & 0x1F
    m = h & 0x3FF
    if e == 0x1F:
        return F32_QNAN if m else _inf(s)
    if e == 0:
        if m == 0:
            return _zero(s)
        bl = m.bit_length()                  # value = m * 2^-24 exactly;
        return (s << 31) | ((bl + 102) << 23) | ((m << (24 - bl)) - (1 << 23))
    return (s << 31) | ((e + 112) << 23) | (m << 13)     # rebias 15 -> 127


def ref_widen_bf16(b):
    """bf16 -> f32 (CVT WIDEN, dtype 0x3): exact bit-splice for
    normals/zeros/Inf. bf16-subnormal input -> SIGNED ZERO at the CVT
    output (COMMIT-0 pin 6: the splice would land in fp32-subnormal
    space, and the machine is DAZ-consistent about fp32 subnormals —
    resolves the splice-vs-flush ambiguity; 254 such patterns). Any NaN
    -> fp32 canonical qNaN 0x7FC00000."""
    b &= 0xFFFF
    s = (b >> 15) & 1
    e = (b >> 7) & 0xFF
    m = b & 0x7F
    if e == 0xFF:
        return F32_QNAN if m else _inf(s)
    if e == 0:
        return _zero(s)                      # true zero and the 254 subnormals
    return b << 16


# ---------------------------------------------------------------------------
# narrow (CVT sub-op 0x1 dtype 0x2/0x3 == 0x7C fp-dest): the single authority
# ---------------------------------------------------------------------------


def ref_narrow_f32(bits, dtype):
    """THE single f32 -> f16/bf16 narrowing authority. The 0x7C == 0x77
    bit-identity clause (COMMIT-0 pin 12) is true BY CONSTRUCTION: both
    golden entry points (cvt NARROW_FROM_F32 and store_quant fp-dest)
    call this one function, mirroring the one shared Verilog function in
    include/fp_narrow_f32.vh. The DAZ pre-stage is pinned IDENTICALLY at
    both RTL capture sites (COMMIT-0 pin 7) and is therefore folded in
    here (fp32 denormal source -> same-signed zero; the visible
    discriminator is the 0x007FFF80-0x007FFFFF sliver, which would
    otherwise RNE up to bf16 min-normal 0x0080).

    RNE via the DISJOINT round/sticky formulation (COMMIT-0 pin 3): for
    the dropped field D with round bit R = MSB(D), sticky S = OR(D minus
    R); increment iff R & (S | kept-LSB) — never "sticky of all dropped
    bits" (the confirmed off-by-one).

      f16  R = source bit 12, S = OR(bits[11:0]), kept-LSB = bit 13;
           rebias 127 -> 15; overflow (unbounded-RNE exponent > 15, i.e.
           |x| >= 65520) -> +/-Inf, never max-finite (pin 4);
           FTZ-at-destination (pin 5): |RN_unbounded| < 2^-14 -> signed
           zero AFTER the unbounded-exponent round (round-up-to-min-
           normal survivors at binade -15 carry to -14 and live).
           DOCUMENTED GPU DIVERGENCE: CUDA cvt.rn.f16.f32 preserves f16
           subnormals — oracle harnesses mask the (0, 2^-14) result band.
      bf16 R = bit 15, S = OR(bits[14:0]), kept-LSB = bit 16; the
           increment ripples mantissa -> exponent so max-finite rounds
           to Inf natively; no bf16-subnormal result is reachable from a
           DAZ-flushed source (fp32 and bf16 share the exponent range),
           so bf16 needs no destination flush.

    NaN of any payload -> DESTINATION canonical qNaN, sign dropped
    (f16 0x7E00 / bf16 0x7FC0) — a NaN can never degrade to Inf (pin 1).
    Returns the 16-bit pattern (caller zero-extends per the result row)."""
    bits &= 0xFFFFFFFF
    s = (bits >> 31) & 1
    e_f = (bits >> 23) & 0xFF
    m_f = bits & 0x7FFFFF
    if dtype == DT_F16:
        if e_f == 0xFF:
            return F16_QNAN if m_f else (s << 15) | F16_PINF
        if e_f == 0:
            return s << 15                   # DAZ pre-stage (+ true zero)
        m24 = (1 << 23) | m_f
        r_bit = (m24 >> 12) & 1              # R = MSB of the 13 dropped bits
        s_bit = 1 if (m24 & 0xFFF) else 0    # S = OR of dropped minus R
        l_bit = (m24 >> 13) & 1              # kept-LSB
        m11 = (m24 >> 13) + (r_bit & (s_bit | l_bit))
        e = e_f - 127
        if m11 == (1 << 11):                 # significand carry
            m11 = 1 << 10
            e += 1
        if e > 15:
            return (s << 15) | F16_PINF      # overflow -> Inf (pin 4)
        if e < -14:
            return s << 15                   # FTZ-at-destination (pin 5)
        return (s << 15) | ((e + 15) << 10) | (m11 - (1 << 10))
    if dtype == DT_BF16:
        if e_f == 0xFF:
            return BF16_QNAN if m_f else (s << 15) | BF16_PINF
        if e_f == 0:
            return s << 15                   # DAZ pre-stage (+ true zero)
        r_bit = (bits >> 15) & 1
        s_bit = 1 if (bits & 0x7FFF) else 0
        l_bit = (bits >> 16) & 1
        # increment ripples through mantissa into the exponent field:
        # 0x7F7F.. -> 0x7F80 = Inf; NaN unreachable (carry clears mantissa)
        return ((bits >> 16) + (r_bit & (s_bit | l_bit))) & 0xFFFF
    raise ValueError("narrow dtype must be 0x2/0x3, got 0x%X" % dtype)


# ---------------------------------------------------------------------------
# I2F (CVT sub-op 0x0 dtype 0x0/0x1/0x4)
# ---------------------------------------------------------------------------


def _i2f_operand(payload, dtype):
    """Signed source extraction from the scalar-in-64 payload_a row."""
    if dtype == DT_INT4:
        v = payload & 0xF
        return v - 16 if v & 0x8 else v
    if dtype == DT_INT8:
        v = payload & 0xFF
        return v - 256 if v & 0x80 else v
    if dtype == DT_ACC_INT:
        v = payload & _M64
        return v - (1 << 64) if v >> 63 else v
    raise ValueError("I2F dtype must be 0x0/0x1/0x4, got 0x%X" % dtype)


def ref_i2f(payload, dtype):
    """I2F reference: signed int -> f32, ONE correctly-rounded RNE from
    the exact integer. int4/int8 always exact (|v| <= 128 < 2^24); dtype
    0x4 takes the sext64 payload and covers int32 (exact below 2^24, RNE
    above) and int64. Overflow impossible: |v| <= 2^63 <= 2^127 (pinned).
    DAZ bypassed by construction — the source is not fp32-format."""
    v = _i2f_operand(payload, dtype)
    if v == 0:
        return 0                             # +0
    s = 1 if v < 0 else 0
    a = -v if s else v
    bl = a.bit_length()
    e = bl - 1
    if bl <= 24:
        m24 = a << (24 - bl)                 # exact
    else:
        m24 = _rne_shift(a, bl - 24)
        if m24 == (1 << 24):
            m24 = 1 << 23
            e += 1
    return (s << 31) | ((e + 127) << 23) | (m24 - (1 << 23))


def micro_i2f_acc(payload):
    """SEQUENCER-FAITHFUL dtype-0x4 I2F ingress: payload[63:32] -> c_in,
    payload[31:0] -> a_in (FSCALAR-style split), then the PINNED two-pass
    normalize — pass 1 RTO (round-to-odd / sticky-preserving jam, the
    rto_jam path) into the 32-bit intermediate significand, pass 2 final
    RNE to 24 bits. No double rounding, by the round-to-odd theorem.

    WHY NOT RNE-THEN-RNE (the defect this pin exists to exclude):
    a first-pass RNE can round a value that lies strictly BELOW the
    24-bit rounding midpoint UP onto the midpoint exactly; pass 2 then
    resolves a manufactured tie and rounds up a second time — 1 ulp high
    vs the correct single rounding. Concrete counterexample (a directed
    discriminator in fp_release_sweep.py):
        v = 2^40 + 2^17 + 0xFFFF        (41 bits; pass 1 drops 9 bits)
      true 24-bit RNE:  dropped field bits[16:0] = 0x0FFFF < 0x10000
                        (midpoint) -> round DOWN -> m24 = 0x800001.
      RNE-32 pass 1:    dropped bits[8:0] = 0x1FF > 0x100 -> round UP ->
                        the intermediate's low 8 bits become 0x80 ==
                        exactly the 24-bit midpoint.
      RNE-24 pass 2:    tie; kept-LSB (bit 17 of v) = 1 (odd) -> round
                        UP -> m24 = 0x800002 (WRONG, +1 ulp).
      RTO pass 1:       truncate bits[8:0], jam their OR into the
                        intermediate LSB -> low 8 bits stay 0x7F < 0x80
                        -> pass 2 rounds DOWN -> m24 = 0x800001 (right).
    RTO into >= 24+2 bits preserves the below/at/above-midpoint class of
    every 24-bit rounding decision (the jam bit sits strictly below the
    pass-2 round bit and never carries), so RNE_24(RTO_32(v)) ==
    RNE_24(v) for ALL v — asserted bit-exactly against ref_i2f over the
    directed discriminator set and a 2^20 random sample in
    fp_release_sweep.py. Any RTL intermediate width >= 26 with the same
    sticky-preserving jam is bit-equivalent."""
    v = _i2f_operand(payload, DT_ACC_INT)
    if v == 0:
        return 0
    s = 1 if v < 0 else 0
    a = -v if s else v
    bl = a.bit_length()
    e = bl - 1
    if bl > I2F_PASS1_BITS:                  # pass 1: RTO jam (never carries)
        inter, bl_i = _rto(a, bl - I2F_PASS1_BITS), I2F_PASS1_BITS
    else:
        inter, bl_i = a, bl                  # exact, pass 1 is a no-op
    if bl_i <= 24:
        m24 = inter << (24 - bl_i)           # pass 2 exact
    else:
        m24 = _rne_shift(inter, bl_i - 24)   # pass 2: final RNE
        if m24 == (1 << 24):
            m24 = 1 << 23
            e += 1
    return (s << 31) | ((e + 127) << 23) | (m24 - (1 << 23))


# ---------------------------------------------------------------------------
# F2I (CVT sub-op 0x1 dtype 0x0/0x1/0x4)
# ---------------------------------------------------------------------------


def ref_f2i(bits, dtype):
    """F2I: fp32 -> signed int, RNE then saturate (COMMIT-0 pin 9). The
    fp32 SOURCE is DAZ-flushed (pin 7 — same load rule as CVT narrow).
    NaN -> 0 (deterministic DATA, never error_flag; knowledge-based CUDA
    cvt.sat precedent, labeled). +/-Inf -> dtype min/max. Clamp bounds:
    int4 [-8,7], int8 [-128,127], dtype 0x4 int32 [-2^31, 2^31-1].
    Returns the sext64 result payload row."""
    lo, hi = F2I_BOUNDS[dtype]
    s, k, v = decode(bits & 0xFFFFFFFF)      # DAZ at operand load (pinned)
    if k == "nan":
        return 0
    if k == "zero":
        return 0
    if k == "inf":
        n = lo if s else hi
    else:
        a = -v if s else v
        n = _rne_rat(a.numerator, a.denominator)
        n = -n if s else n
        n = lo if n < lo else (hi if n > hi else n)
    return n & _M64


# ---------------------------------------------------------------------------
# 0x77 CVT entry points (64-bit payload rows in/out)
# ---------------------------------------------------------------------------


def cvt(subop, dtype, payload):
    """0x77 CVT REFERENCE entry point, keyed by sub-op (imm16[7:4],
    absent-imm16 default = WIDEN_TO_F32) + dtype. Takes the 64-bit
    payload_a row, returns the 64-bit result payload row: f16/bf16
    {48'h0, h} zero-extend; f32 {32'h0, f}; ints sext64. Sub-op/dtype
    combinations outside the six pinned directions are lower_required at
    launch (capability absence — reserved-field rung, 0x72 semantics) and
    never reach the datapath; modeled here as ValueError."""
    payload &= _M64
    if subop == CVT_WIDEN_TO_F32:
        if dtype == DT_F16:
            return ref_widen_f16(payload & 0xFFFF)
        if dtype == DT_BF16:
            return ref_widen_bf16(payload & 0xFFFF)
        if dtype in (DT_INT4, DT_INT8, DT_ACC_INT):
            return ref_i2f(payload, dtype)
        raise ValueError("lower_required: CVT WIDEN dtype 0x%X" % dtype)
    if subop == CVT_NARROW_FROM_F32:
        if dtype in (DT_F16, DT_BF16):
            return ref_narrow_f32(payload & 0xFFFFFFFF, dtype)
        if dtype in (DT_INT4, DT_INT8, DT_ACC_INT):
            return ref_f2i(payload & 0xFFFFFFFF, dtype)
        raise ValueError("lower_required: CVT NARROW dtype 0x%X" % dtype)
    raise ValueError("lower_required: CVT sub-op 0x%X" % subop)


ref_cvt = cvt   # file-plan name; one object, no second implementation


def micro_cvt(subop, dtype, payload):
    """SEQUENCER-FAITHFUL 0x77: every conversion except the dtype-0x4 I2F
    is a single exact pass through the step program (K_INT/K_ADD only,
    zero multiplier passes), so the reference IS the micro model — same
    convention as FS_ADD/SUB/MUL/FMA. The int64/int32 ingress is the only
    CVT with a distinct step model (micro_i2f_acc two-pass)."""
    if subop == CVT_WIDEN_TO_F32 and dtype == DT_ACC_INT:
        return micro_i2f_acc(payload & _M64)
    return cvt(subop, dtype, payload)


# ---------------------------------------------------------------------------
# 0x73 ACC_ELEMWISE (OPREF form only)
# ---------------------------------------------------------------------------


def accew(a, b_payload):
    """0x73 ACC_ELEMWISE reference: fused SINGLE-ROUNDING fp32
    a * B[63:32] + B[31:0] with B via OPREF (any imm present ->
    lower_required, capability absence — not modeled here). Rides
    ref_fma verbatim: the golden bit-match target is
    micro_fscalar(FS_FMA) == ref_fma (NOT a separate FMA model)."""
    b_payload &= _M64
    return ref_fma(a, (b_payload >> 32) & 0xFFFFFFFF, b_payload & 0xFFFFFFFF)


ref_acc_elemwise = accew    # file-plan name


def micro_accew(a, b_payload):
    """Sequencer-faithful 0x73: the FS_FMA-shaped step program — the RTL
    wide datapath holds the exact product+addend and rounds ONCE, so the
    reference is the micro model (micro_fscalar(FS_FMA) verbatim)."""
    b_payload &= _M64
    return micro_fscalar(FSCALAR_OP_CODE["FS_FMA"], a,
                         (b_payload >> 32) & 0xFFFFFFFF,
                         b_payload & 0xFFFFFFFF)


# ---------------------------------------------------------------------------
# 0x7C STORE_QUANT fp-dest packer
# ---------------------------------------------------------------------------


def store_quant(bits, dtype):
    """0x7C STORE_QUANT fp-dest (dtype 0x2/0x3): {48'h0, narrow(f32)}.
    The bit-identity clause (0x7C fp-dest == 0x77 NARROW_FROM_F32 for all
    2^32 inputs INCLUDING the DAZ pre-stage) is true BY CONSTRUCTION:
    this is a direct call into ref_narrow_f32, the same single authority
    the CVT narrow path uses — one golden function, mirroring the one
    shared Verilog function (include/fp_narrow_f32.vh) instantiated at
    both RTL sites. The int4/int8 arms are the shipped v1.8.0b integer
    requant path, bit-unchanged and out of the fp format layer's scope."""
    if dtype not in (DT_F16, DT_BF16):
        raise ValueError("store_quant fp-dest dtype must be 0x2/0x3")
    return ref_narrow_f32(bits & 0xFFFFFFFF, dtype)
