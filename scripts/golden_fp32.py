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

v1.8.0e WIDE-VECTOR LAYER (COMMIT 1, golden-before-RTL) — reference
semantics for the 0e wide package under the "hybrid-minimal (repaired)"
design pins (0x70 is 0e2: authored now, consumed by RTL later):
  ref_fminmax[_lane]           0x79 frozen IEEE-2019 minimumNumber/
                               maximumNumber, six pinned rows, offset-
                               comparator key, DAZ-EXEMPT raw-bit rows.
  ref_dequant[_lane] /         0x78 int4/int8 x fp32 scale -> bf16,
  micro_dequant[_lane]         ROUND-ONCE definition (a) — one RNE from
                               the exact <= 31-bit product; ref reuses
                               the single narrow authority through a
                               sticky-preserving (round-to-odd) 24-bit
                               intermediate, micro is the OPS_DEQ
                               disjoint-round/sticky bf16-pack twin.
  ref_gamma_mul_w[_lane]       0x6B exact widening int4 x int4 -> int8
                               (range [-56, 64] — proof in docstring).
  ref_vfma[_lane] /            0x70 per-lane (sext32(a)*b_mul + c_acc)
  vfma_b_split                 mod 2^32 explicit, B-split pin.
  lanes_to_frags / frags_to_lanes  THE lane<->fragment packing pin.
  rmsnorm_chain_0e             the FULL rewritten RMSNORM macro chain
                               (L2SQ -> fp insert -> 0x6B -> DEQUANT),
                               model-level target of the MSE release
                               gate (scripts/mse_sweep.py).

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
# COMMIT 2 landed the generated cvt_op_codes table (single-source in
# isa/wt64v1_isa.json -> asm/generated_isa_tables.py CVT_OP_CODE); the
# pinned transcription below is asserted against it, per the COMMIT-1
# freshness clause.
CVT_WIDEN_TO_F32 = 0x0
CVT_NARROW_FROM_F32 = 0x1
from generated_isa_tables import CVT_OP_CODE  # noqa: E402
assert CVT_OP_CODE == {"WIDEN_TO_F32": CVT_WIDEN_TO_F32,
                       "NARROW_FROM_F32": CVT_NARROW_FROM_F32}, (
    "generated cvt_op_codes diverged from the golden pinned transcription")

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


# ===========================================================================
# v1.8.0e WIDE-VECTOR LAYER (COMMIT 1, golden-before-RTL) — 0x79 FMINMAX /
# 0x78 DEQUANT / 0x6B GAMMA_MUL_W / 0x70 VFMA_ACC (0e2) + the pinned
# lane<->fragment packing + the rewritten RMSNORM macro chain model
# ===========================================================================
#
# Authoritative design: v1.8.0e "hybrid-minimal (repaired)" — all semantics
# below transcribe its opcode_semantics_final pins. Every function here is
# authored and swept BEFORE any RTL exists (golden-before-RTL, locked).
# 0x70 VFMA is a 0e2 op — its golden is authored NOW (this commit) and
# consumed by the 0e2 RTL later.

BF16_MIN_NORMAL = 0x0080

# 0x79 FMINMAX sub-op nibble (imm16[7:4]; [3:0] and [15:8] reserved-zero ->
# lower_required at decode — a legality rung, not modeled by these DATA
# functions). Pinned transcription; asserted against the generated table
# the moment the 0e ISA regen lands (COMMIT-1 freshness clause — the exact
# CVT_OP_CODE precedent above).
FMINMAX_OP_CODE = {"MINIMUMNUM": 0x0, "MAXIMUMNUM": 0x1}
try:
    from generated_isa_tables import FMINMAX_OP_CODE as _GEN_FMINMAX  # noqa: E402
    assert _GEN_FMINMAX == FMINMAX_OP_CODE, (
        "generated fminmax sub-op table diverged from the golden pinned "
        "transcription")
except ImportError:
    pass          # 0e ISA regen not landed yet — golden-before-RTL ordering

FMINMAX_LANES = 4                        # 4 f32 = 128b in = 2 frags; out same
GAMMA_LANES = 16                         # 16 int4 in (1 frag) -> 16 int8 (2)
DEQUANT_LANES = {DT_INT4: 32, DT_INT8: 16}
DEQUANT_OUT_FRAGS = {DT_INT4: 8, DT_INT8: 4}   # bf16-ONLY dest in 0e (pin)
VFMA_LANES = {DT_INT4: 32, DT_INT8: 16}
VFMA_OUT_FRAGS = {DT_INT4: 16, DT_INT8: 8}     # int4 form = the 16-frag consumer


# ---------------------------------------------------------------------------
# lane <-> fragment packing (pinned in spec + golden + SDK TOGETHER)
# ---------------------------------------------------------------------------


def lanes_to_frags(lanes, lane_bits):
    """THE lane->fragment packing pin: lane i occupies bits
    [lane_bits*i +: lane_bits] of the flat result vector; fragment f is
    flat[64*f +: 64] (low fragment first), so one 64-bit fragment word
    holds 64/lane_bits consecutive lanes — 16 int4/word, 8 int8/word,
    4 bf16/word, 2 int32-or-f32/word (the hybrid submission's '2 bf16/
    word' prose error is corrected to 4 here, per the repaired design).
    Fragment 0 is the frag0_hold word (always emitted directly at the arm
    cycle); words 1..N-1 are the frag_pending rows drained 1/cycle."""
    assert 64 % lane_bits == 0
    per = 64 // lane_bits
    assert len(lanes) % per == 0
    frags = []
    for f in range(len(lanes) // per):
        w = 0
        for j, lane in enumerate(lanes[f * per:(f + 1) * per]):
            assert 0 <= lane < (1 << lane_bits), "lane must be a raw field"
            w |= lane << (lane_bits * j)
        frags.append(w)
    return frags


def frags_to_lanes(frags, lane_bits, n_lanes):
    """Inverse of lanes_to_frags (same pin), for unpacking payload_a
    fragment words into raw lane fields."""
    per = 64 // lane_bits
    assert len(frags) * per == n_lanes
    lanes = []
    for w in frags:
        assert 0 <= w <= _M64
        for j in range(per):
            lanes.append((w >> (lane_bits * j)) & ((1 << lane_bits) - 1))
    return lanes


# ---------------------------------------------------------------------------
# 0x79 FMINMAX (0e1) — frozen IEEE-2019 minimumNumber / maximumNumber
# ---------------------------------------------------------------------------


def f32_total_order_key(bits):
    """The pinned 0x79 comparator key: a[31] ? ~a : (a ^ 0x80000000), then
    ONE unsigned 32-bit compare (signed-int-tree reuse stays forbidden).
    Gives the IEEE-754 total order on ALL non-NaN patterns: frozen row 5
    (offset-transform total order), row 1 (-0 < +0 natively: key(-0) =
    0x7FFFFFFF < key(+0) = 0x80000000) and row 6 (denormals ordered by
    raw bit pattern). DAZ-EXEMPT by construction — never touches
    decode()."""
    bits &= 0xFFFFFFFF
    return (~bits) & 0xFFFFFFFF if bits >> 31 else bits ^ 0x80000000


def _f32_nan(bits):
    return (bits & 0x7F800000) == 0x7F800000 and (bits & 0x7FFFFF) != 0


def ref_fminmax_lane(a, b, subop):
    """One 0x79 lane — frozen IEEE-2019 semantics, six pinned rows:
      (1) -0 < +0 natively (via the offset key);
      (2) one NaN -> the NUMBER (NaN loses), the number's bit pattern
          returned UNCHANGED — including denormal numbers (row 6);
      (3) both NaN -> canonical qNaN 0x7FC00000;
      (4) sNaN quieted to canonical (any NaN-producing cell emits the
          canonical pattern; no trap, DATA — and a lone sNaN against a
          number still loses per row 2);
      (5) offset-transform total order (f32_total_order_key, one
          unsigned compare);
      (6) denormal cells BIT-PATTERN-PRESERVING and DAZ-EXEMPT — this
          function is NOT built on golden decode() (pinned).
    B legality (missing-B -> error_flag, imm16 reserved-zero ->
    lower_required, FSCALAR-clone re-row) is decode-level, not data."""
    a &= 0xFFFFFFFF
    b &= 0xFFFFFFFF
    an, bn = _f32_nan(a), _f32_nan(b)
    if an and bn:
        return F32_QNAN                       # rows 3+4
    if an:
        return b                              # row 2 (b bit-preserved)
    if bn:
        return a
    ka, kb = f32_total_order_key(a), f32_total_order_key(b)
    if subop == FMINMAX_OP_CODE["MINIMUMNUM"]:
        return a if ka <= kb else b
    if subop == FMINMAX_OP_CODE["MAXIMUMNUM"]:
        return a if ka >= kb else b
    raise ValueError("lower_required: FMINMAX sub-op 0x%X" % subop)


def ref_fminmax(a_lanes, b, subop):
    """0x79 vector entry: 4 f32 lanes (128b = 2-frag wave) against ONE
    broadcast B scalar (f32 bits from dec_input_payload_b[31:0] — the
    0x74 FSCALAR low-word convention, cloned verbatim). Returns the 4
    result lanes (128b out = 2 frags via today's FSM)."""
    assert len(a_lanes) == FMINMAX_LANES
    return [ref_fminmax_lane(a, b, subop) for a in a_lanes]


def fminmax_frags(a_frags, b, subop):
    """Fragment-level 0x79 wrapper pinning the 32-bit lane map (lane i at
    flat bits [32i+31:32i], 2 lanes/word, 2 fragments in/out)."""
    lanes = frags_to_lanes(a_frags, 32, FMINMAX_LANES)
    return lanes_to_frags(ref_fminmax(lanes, b, subop), 32)


# ---------------------------------------------------------------------------
# 0x78 DEQUANT (0e1) — int4/int8 x fp32 broadcast scale -> bf16, ROUND-ONCE
# ---------------------------------------------------------------------------


def ref_dequant_lane(field, scale, dtype):
    """One 0x78 DEQUANT lane: signed int lane k (int4/int8 raw field —
    dtype names the SOURCE per the conversion-dtype rule; dest is pinned
    bf16-ONLY in 0e) times the fp32 broadcast scale, ROUND-ONCE
    definition (a): ONE RNE from the exact product directly to bf16.

    EXACTNESS PROOF (the reason one rounding suffices): |k| <= 128 = 2^7
    fits the 24-bit fp32 significand trivially (int4/int8 magnitudes are
    exact fp32 values), and the scale's significand m_s < 2^24, so the
    integer product P = |k| * m_s < 2^31 is held EXACTLY (<= 31 bits) —
    nothing is rounded before the single RNE-to-bf16.

    ROUND-ONCE VIA THE SINGLE NARROW AUTHORITY: the exact product is
    packed to a 24-bit fp32-format intermediate with ROUND-TO-ODD
    (sticky-preserving jam — never carries), then handed to
    ref_narrow_f32, THE one f32->bf16 authority — so bit-identity with
    the CVT narrow path holds BY CONSTRUCTION. RTO into 24 bits
    preserves the below/at/above-midpoint class of every 8-bit rounding
    decision (the jam bit sits 15 positions below the bf16 round bit and
    never carries — the micro_i2f_acc theorem, margin 24 >= 8+2), so
    narrow(RTO24(v)) == RNE_bf16(v) for ALL v. What is FORBIDDEN is
    ref_mul-then-ref_narrow_f32: a first-pass RNE24 can land the product
    exactly ON a bf16 midpoint and the second rounding resolves the
    manufactured tie to even — ±1 ulp off definition (a). The MSE gate
    is provably blind to that defect; golden/TB BIT-EQUIVALENCE on the
    directed tie vectors is the enforcement point.

    Pinned specials cells (all enumerated in the directed sweep):
      scale denormal    -> DAZ at operand load (-> signed-zero rows);
      scale NaN         -> canonical bf16 qNaN (propagates mul->narrow);
      scale +-Inf       -> +-Inf by sign XOR; k == 0 against Inf -> qNaN;
      k == 0 / scale 0  -> SIGNED zero, sign = sign(k) XOR sign(scale);
      product overflow  -> +-Inf, never max-finite;
      product < bf16 min-normal -> FTZ to signed zero at destination
        pack — UNREACHABLE for nonzero operands (|k| >= 1 and the DAZ'd
        |scale| >= 2^-126 give |product| >= 2^-126 = bf16 min-normal;
        the cell is pinned for the pack logic, asserted vacuous here).

    Transport (not modeled): the fp32 scale rides ext_payload_b WITH
    ext_payload_b_valid on the wave-COMPLETING fragment beat (0x63-65
    precedent); missing scale -> error_flag; launch-cycle capture of
    A(128b)+B(64b)+tag into MU-local regs (0x74 idiom)."""
    if dtype not in (DT_INT4, DT_INT8):
        raise ValueError("DEQUANT source dtype must be 0x0/0x1")
    k = _i2f_operand(field, dtype)
    s_sign, s_kind, _ = decode(scale)         # DAZ at operand load (pinned)
    sign = (1 if k < 0 else 0) ^ s_sign
    if s_kind == "nan":
        return BF16_QNAN
    if s_kind == "inf":
        return BF16_QNAN if k == 0 else (sign << 15) | BF16_PINF
    if s_kind == "zero" or k == 0:
        return sign << 15                     # signed zero (sign-XOR pin)
    m_s = (scale & 0x7FFFFF) | (1 << 23)
    e_s = ((scale >> 23) & 0xFF) - 127
    P = abs(k) * m_s                          # EXACT, <= 31 bits (see proof)
    bl = P.bit_length()                       # >= 24 (|k| >= 1)
    e_u = e_s + bl - 24                       # binade exponent of the product
    if e_u > 127:
        # product >= 2^128: max-finite-with-sticky substitute — the narrow
        # authority's increment ripples 0x7F7F -> 0x7F80 = Inf (overflow ->
        # Inf, never max-finite, pinned)
        inter = (sign << 31) | 0x7F7FFFFF
    else:
        assert e_u >= -126                    # FTZ-at-dest cell vacuous (pin)
        m24 = _rto(P, bl - 24) if bl > 24 else P << (24 - bl)
        inter = (sign << 31) | ((e_u + 127) << 23) | (m24 - (1 << 23))
    return ref_narrow_f32(inter, DT_BF16)


def ref_dequant(lanes, scale_fp32, src_dtype):
    """0x78 vector entry — the two pinned 0e forms ONLY: int4 32-lane
    (128b = 2-frag A) -> 32 bf16 = 512b = 8 frags; int8 16-lane -> 16
    bf16 = 256b = 4 frags (dest bf16-ONLY; the 16-frag DEQUANT form is
    deleted by the bf16 pin). Slice-select imm16[7:4] and f32-dest
    imm16[3:0] are CLOSED-DEFERRED carriers, not 0e semantics."""
    assert len(lanes) == DEQUANT_LANES[src_dtype]
    return [ref_dequant_lane(f, scale_fp32, src_dtype) for f in lanes]


def dequant_frags(a_frags, scale_fp32, src_dtype):
    """Fragment-level 0x78 wrapper pinning the lane maps: int4 lane i at
    A-flat [4i+3:4i] (2 frags), int8 lane i at [8i+7:8i] (2 frags); bf16
    result lane i at flat [16i+15:16i] (4 lanes/word -> 8 or 4 frags)."""
    n = DEQUANT_LANES[src_dtype]
    lanes = frags_to_lanes(a_frags, 4 if src_dtype == DT_INT4 else 8, n)
    out = lanes_to_frags(ref_dequant(lanes, scale_fp32, src_dtype), 16)
    assert len(out) == DEQUANT_OUT_FRAGS[src_dtype]
    return out


def micro_dequant_lane(field, scale, dtype):
    """SEQUENCER-FAITHFUL 0x78 twin — models the fused OPS_DEQ step
    program (OPS_DEQ = 4'd9): launch-captured operands, exact I2F folded
    into the FS_MUL-shape tail through FP_Mul36 (|k| enters as an
    UNNORMALIZED significand — the product register holds <= 31
    significant bits of the 48-bit product, unrounded), then the bf16-
    pack variant of the pin-3 DISJOINT round/sticky epilogue: round bit
    R = MSB of the dropped field, sticky S = OR(dropped minus R),
    increment iff R & (S | kept-LSB); significand carry bumps the
    exponent; overflow -> Inf at pack; FTZ-at-destination cell vacuous
    (same proof as ref_dequant_lane). Bit-equivalence micro == ref over
    lanes x scales INCLUDING the round-once discriminator ties is THE
    enforcement point of rounding definition (a)."""
    if dtype not in (DT_INT4, DT_INT8):
        raise ValueError("DEQUANT source dtype must be 0x0/0x1")
    k = _i2f_operand(field, dtype)
    s_sign, s_kind, _ = decode(scale)
    sign = (1 if k < 0 else 0) ^ s_sign
    if s_kind == "nan":
        return BF16_QNAN
    if s_kind == "inf":
        return BF16_QNAN if k == 0 else (sign << 15) | BF16_PINF
    if s_kind == "zero" or k == 0:
        return sign << 15
    m_s = (scale & 0x7FFFFF) | (1 << 23)
    e_s = ((scale >> 23) & 0xFF) - 127
    P = abs(k) * m_s
    bl = P.bit_length()
    e_u = e_s + bl - 24
    sh = bl - 8                               # >= 16: dropped-field width
    q = P >> sh
    r_bit = (P >> (sh - 1)) & 1
    s_bit = 1 if P & ((1 << (sh - 1)) - 1) else 0
    q += r_bit & (s_bit | (q & 1))
    if q == (1 << 8):
        q = 1 << 7
        e_u += 1
    if e_u > 127:
        return (sign << 15) | BF16_PINF       # overflow -> Inf, never max-finite
    assert e_u >= -126
    return (sign << 15) | ((e_u + 127) << 7) | (q - (1 << 7))


def micro_dequant(lanes, scale_fp32, src_dtype):
    assert len(lanes) == DEQUANT_LANES[src_dtype]
    return [micro_dequant_lane(f, scale_fp32, src_dtype) for f in lanes]


# ---------------------------------------------------------------------------
# 0x6B GAMMA_MUL_W (0e1) — exact widening int4 x int4 -> int8, MU-hosted
# ---------------------------------------------------------------------------


def ref_gamma_mul_w_lane(a4, g4):
    """out = sext8(a4) * sext8(g4) — EXACT widening per lane. RANGE
    PROOF: int4 operands lie in [-8, 7], so products lie in [-56, +64]
    (minimum (-8)*7 = 7*(-8) = -56; maximum (-8)*(-8) = +64; positive-
    operand maximum 7*7 = 49) — trivially inside int8 [-128, 127]:
    rounding-free AND saturation-free. Returns the int8 result field."""
    va = _i2f_operand(a4, DT_INT4)
    vg = _i2f_operand(g4, DT_INT4)
    return (va * vg) & 0xFF


def ref_gamma_mul_w(x_lanes_int4, gamma_lanes_int4):
    """0x6B GAMMA_MUL_W vector entry (0e1, NEW — pre-stable reallocation
    of the retired WIDEN code): A = 16 int4 lanes = 64b single-fragment
    payload_a; gamma = 16 int4 lanes via imm64 XOR OPREF (alu-binary XOR
    satisfied — both/neither is decode_error, a legality rung). Result
    lane i at bits [8i+7:8i] of the 128-bit output (2 frags) — the lane
    order pin, held in spec + golden + SDK together. MU-HOSTED: the arm
    lives inside the parameter-gated region so 16 L-PEs synthesize
    nothing (~200-300 LUT once, not 16x). Gamma fixed-point convention:
    gamma int4 carries an implicit 2^-k; the 2^-k folds into the DEQUANT
    broadcast scale as an EXACT exponent shift (see rmsnorm_chain_0e)."""
    assert len(x_lanes_int4) == GAMMA_LANES
    assert len(gamma_lanes_int4) == GAMMA_LANES
    return [ref_gamma_mul_w_lane(a, gg)
            for a, gg in zip(x_lanes_int4, gamma_lanes_int4)]


def gamma_mul_w_frags(a_frag, gamma_imm64):
    """Fragment-level 0x6B wrapper: one 64-bit A fragment + the 64-bit
    gamma vector -> the 2 output fragment words (8 int8 lanes/word)."""
    a_lanes = frags_to_lanes([a_frag], 4, GAMMA_LANES)
    g_lanes = frags_to_lanes([gamma_imm64], 4, GAMMA_LANES)
    return lanes_to_frags(ref_gamma_mul_w(a_lanes, g_lanes), 8)


# ---------------------------------------------------------------------------
# 0x70 VFMA_ACC (0e2 — authored now, golden-before-RTL) — int32 wrap FMA
# ---------------------------------------------------------------------------


def vfma_b_split(b_payload, dtype):
    """The 0x70 B-split pin (spec-first): c_acc = B[63:32], ONE broadcast
    int32 addend; b_mul = sext32 from B[3:0] (int4 dtype) / B[7:0]
    (int8). The datapath reads ONLY those low bits — asm-lint (not this
    model) LOUDLY rejects imm encodings with nonzero bits in b_mul above
    the lane width, so no silent truncation is observable from legal
    programs. imm16/imm32 encodings zero-fill the upper word -> c_acc=0.
    STATELESS pin: the ROM-shipped mode-byte acc bit = 1 marks the
    wide-acc OUTPUT form, NOT stateful accumulation (the lane-engine
    polarity error is corrected). Returns (b_mul, c_acc) as signed ints."""
    if dtype not in (DT_INT4, DT_INT8):
        raise ValueError("VFMA dtype must be 0x0/0x1")
    b_payload &= _M64
    c = (b_payload >> 32) & 0xFFFFFFFF
    c_acc = c - (1 << 32) if c >> 31 else c
    return _i2f_operand(b_payload, dtype), c_acc


def ref_vfma_lane(a_field, b_mul, c_acc, dtype):
    """One 0x70 lane: out = (sext32(a) * b_mul + c_acc) mod 2^32 —
    EXPLICIT wrap (c_acc can sit exactly at the wrap boundary). Returns
    the int32 result lane pattern."""
    if dtype not in (DT_INT4, DT_INT8):
        raise ValueError("VFMA dtype must be 0x0/0x1")
    return (_i2f_operand(a_field, dtype) * b_mul + c_acc) & 0xFFFFFFFF


def ref_vfma(lanes, b_mul, c_acc, dtype):
    """0x70 vector entry: int4 -> 32 lanes -> 32 int32 = 16 frags (the
    frag-widening + Cluster mask-fix consumer); int8 -> 16 lanes -> 8
    frags. Result lane i at flat bits [32i+31:32i] (2 lanes/word).
    Compute is a shared sequential LUT-mapped signed 8x8 MAC (never the
    fp step sequencer, 0 MULT18) — irrelevant to the exact semantics."""
    assert len(lanes) == VFMA_LANES[dtype]
    return [ref_vfma_lane(a, b_mul, c_acc, dtype) for a in lanes]


def vfma_frags(a_frags, b_payload, dtype):
    """Fragment-level 0x70 wrapper: A fragment words -> result fragment
    words (16 for int4 / 8 for int8), B split per vfma_b_split."""
    n = VFMA_LANES[dtype]
    lanes = frags_to_lanes(a_frags, 4 if dtype == DT_INT4 else 8, n)
    b_mul, c_acc = vfma_b_split(b_payload, dtype)
    out = lanes_to_frags(ref_vfma(lanes, b_mul, c_acc, dtype), 32)
    assert len(out) == VFMA_OUT_FRAGS[dtype]
    return out


# ---------------------------------------------------------------------------
# the rewritten RMSNORM macro chain (0e1) — golden model
# ---------------------------------------------------------------------------

RMSNORM_EPS_DEFAULT_BITS = 0x39000000     # 2^-13 — the assembler guard floor


def bf16_to_frac(h):
    """Exact Fraction value of a finite bf16 pattern (subnormals exact —
    measurement helper for the MSE harness, not an operand loader)."""
    h &= 0xFFFF
    s = (h >> 15) & 1
    e = (h >> 7) & 0xFF
    m = h & 0x7F
    assert e != 0xFF
    if e == 0:
        v = Fraction(m, 1 << 7) * Fraction(2) ** (-126)
    else:
        v = Fraction((1 << 7) + m, 1 << 7) * Fraction(2) ** (e - 127)
    return -v if s else v


def f32_exp_shift(bits, dk):
    """EXACT power-of-two rescale of a NORMAL fp32 pattern (exponent-
    field add). The gamma fixed-point 2^-k fold and the per-tensor-scale
    fold are pinned as exact exponent shifts — leaving the normal range
    would make the fold inexact, so it is asserted, never rounded or
    flushed."""
    e = (bits >> 23) & 0xFF
    assert 0 < e < 0xFF, "exp-shift input must be a normal fp32 pattern"
    e += dk
    assert 0 < e < 0xFF, "exp-shift fold left the normal range"
    return (bits & 0x807FFFFF) | (e << 23)


def rmsnorm_chain_0e(x_lanes, gamma_lanes, gamma_frac_bits=3,
                     eps_bits=RMSNORM_EPS_DEFAULT_BITS, scale_exp=0):
    """GOLDEN MODEL of the FULL rewritten v1.8.0e RMSNORM macro chain
    (the _lower_rmsnorm rewrite: the x256/F2I/Q8.8/int-gamma tail is
    deleted). Numerically relevant dispatches only (the FSCALAR
    B-constant producers carry constants and do not round):

      1) SIG_L2SQ   ssq = sum(x_i^2)          exact int (<= 32*64 = 2048)
      2) CVT I2F    sq_f = f32(ssq)           EXACT (< 2^24)
      3) FS_MUL     m  = RNE(sq_f * c)        c = 4^scale_exp / N: the
         harness tensor convention is x_real = x_int * 2^scale_exp, so
         mean(x_real^2) = ssq * 4^scale_exp / N — folding 4^scale_exp
         into the EXISTING 1/N producer constant is an exact exponent
         shift (N a power of two), no extra dispatch
      4) FS_ADD     me = RNE(m + eps)         eps REAL-domain, assembler
         guard eps >= 2^-13 retained (rationale restated in 0e: the
         mpmath exact reference is eps-INCLUSIVE — the old Q8.8-
         absorption rationale is retired)
      5) FRSQRT32   r  = micro_rsqrt(me)      <= 2 ulp, step-faithful
      6) (fold)     s  = r * 2^(scale_exp - k) EXACT exponent shift —
         the gamma fixed-point 2^-k and the tensor scale fold into the
         DEQUANT broadcast scale; the FSCALAR gamma-fold step of the
         as-submitted hybrid is deleted (gamma exponent folds free)
      7) 0x6B       w  = x (.) gamma          exact int8, per 16-lane row
      8) 0x78       y_i = RNE_bf16(w_i * s)   int8-16 DEQUANT — the ONE
         output narrowing, round-once definition (a)

    Steps 3+4 ride the v1.8.0c wide-exact-round-once step programs, so
    ref IS micro for them; total roundings after the exact integer core:
    one FS_MUL RNE, one FS_ADD RNE, the <= 2-ulp rsqrt, ONE output RNE
    per lane — chain relative RMS ~2^-21.9 against the exact reference,
    which the MSE release gate measures (must be <= 1.05x the bf16
    dtype floor per tensor).

    N = 16 or 32 int4 lanes; N = 32 lowers as two 16-lane 0x6B + DEQUANT
    pairs sharing one s (same lane map). LAYERNORM/BATCHNORM stay 0d
    Q8.8 form in 0e (beta has no fp-vector-add home) — scoped, not
    hidden. Returns (bf16_lanes, trace-dict)."""
    n = len(x_lanes)
    assert n in (16, 32) and len(gamma_lanes) == n
    ssq = 0
    for x in x_lanes:
        v = _i2f_operand(x, DT_INT4)
        ssq += v * v
    sq_f = ref_i2f(ssq & _M64, DT_ACC_INT)                # exact
    c_bits = f32_exp_shift((127 - (n.bit_length() - 1)) << 23, 2 * scale_exp)
    m = ref_mul(sq_f, c_bits)                             # FS_MUL == micro
    me = ref_add(m, eps_bits)                             # FS_ADD == micro
    r = micro_rsqrt(me)                                   # FRSQRT32
    s_deq = f32_exp_shift(r, scale_exp - gamma_frac_bits)
    y = []
    for h in range(n // 16):
        w = ref_gamma_mul_w(x_lanes[16 * h:16 * h + 16],
                            gamma_lanes[16 * h:16 * h + 16])
        y += ref_dequant(w, s_deq, DT_INT8)
    return y, {"ssq": ssq, "mean_eps_bits": me, "rsqrt_bits": r,
               "scale_bits": s_deq}
