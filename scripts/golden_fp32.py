#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""v1.8.0c — bit-exact fp32 golden model (the single reference for all fp
tests: directed vectors, random sweeps, release-gate exhaustive sweeps).

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
