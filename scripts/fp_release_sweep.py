#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""v1.8.0c core + v1.8.0d format layer — fp golden-model release sweeps
(model-only; RTL lockstep lands with the RTL commits).

Runs the mandatory validation of the shipped seed-ROM / coefficient
artifacts through the sequencer-faithful models and writes the measured
margins to include/generated/fp_validation_report.json (machine-readable,
cited by the spec). Deterministic: fixed seeds, no timestamps.

  FRSQRT32  exhaustive over all 2^24 (mantissa x binade-parity) classes —
            a proof, not a sample (valid for all finite x by the pinned
            range reduction: scale covariance by construction).
            PASS: worst <= 2.0 ulp AND monotonicity non-increasing AND
            x = 4^k bit-exact. ulp DISTANCE measured in float64 (np.sqrt
            and the divide are each <= 0.5 ulp64, so measurement error is
            ~2^-28 ulp32 — negligible vs the >1-ulp margin); the worst
            1000 points are re-checked with exact integer/Fraction
            arithmetic (isqrt to 2^-60, measurement error < 2^-36 ulp32).

  FEXP2_32  2^22 uniform-over-bit-pattern sample + exhaustive windows
            around both boundaries (x in [-127,-125] and [127,129]) +
            all integers in [-150,128].
            PASS: worst <= 2.0 ulp (unbounded-rounding domain — the FTZ /
            overflow pack decision is measured before flushing so the
            boundary slivers stay comparable), monotonic non-decreasing
            on the sample grid, integer bypass bit-exact, c0 == 1.0
            asserted against the shipped artifact.

  FDIV      10^5 random pairs + 10^4 constructed midpoint-adjacent
            quotients (a = RN32(b*(2M+1)*2^-24) so a/b sits within
            ~2^-25 of an RNE midpoint — random sampling has ~zero power
            there) vs the correctly-rounded reference.
            PASS: bit-exact everywhere (Markstein correct rounding).

v1.8.0d FORMAT-LAYER SWEEPS (COMMIT 1, golden-before-RTL — these are the
named merge-blocking sweep obligations of the v1.8.0d design):

  CVT WIDEN   f16->f32 and bf16->f32 EXHAUSTIVE 2^16 each, vs the
              INDEPENDENT ORACLES (numpy float16 / ml_dtypes bfloat16)
              with the pinned divergences masked and asserted both ways
              (NaN canonicalization; bf16-subnormal-widen signed-zero pin).
  CVT NARROW  f32->f16: exhaustive boundary slivers (denormal-band bottom
              2^-24, min-normal 2^-14 incl. round-up survivors,
              max-finite/65520 overflow threshold; both signs) + per-ULP
              RNE tie sets + 2^22 random. f32->bf16: 2^22 random + the
              even/odd-quotient exact-tie classes (mantissa 0x808000
              family) + sticky-disjointness vectors + the DAZ sliver
              0x007FFF80-0x007FFFFF (the only input band where DAZ is
              observable at a 16-bit destination). Every point is checked
              against an INDEPENDENT VALUE-LEVEL formulation (float64
              frexp + rint — no bit tricks shared with the golden
              authority) and, masked, against the numpy/ml_dtypes oracles.
              The 0x7C == 0x77 bit-identity clause is true by construction
              (one golden ref_narrow_f32); the store_quant/cvt wiring is
              pinned by sampled assertion.
  I2F         int4/int8 exhaustive (exactness proven); dtype-0x4 directed
              int32 rows; int64 two-pass discriminator family (vectors
              where a buggy RNE-then-RNE double-rounds; the pinned
              RTO-then-RNE must match the single-RNE reference on every
              one) + 2^20 random int64 vs the numpy int64->f32 oracle.
  F2I         directed (RNE ties, saturation rails at f32 granularity,
              +/-Inf -> rails, NaN -> 0, DAZ) + 2^20 random vs an
              independent float64 rint/clip/NaN->0 oracle composition.
  ACC_ELEMWISE 10^5 random (specials injected) — accew == ref_fma(a, B_hi,
              B_lo) == micro_fscalar(FS_FMA) wiring/alias identity, plus
              fused-vs-two-step discriminators (round-once proof) and
              gamma=1/beta=0 identity rows.
  ROUND-TRIP  E-row, exhaustive 2^16 per format: narrow(widen(x)) == x for
              the RE-SCOPED domain (normals, +/-0, +/-Inf, canonical qNaN
              ONLY); subnormals asserted to flush (FTZ pin, by design) and
              non-canonical NaNs asserted to canonicalize.

v1.8.0e WIDE-VECTOR LAYER SWEEPS (COMMIT 1, golden-before-RTL — the
directed sets of the "hybrid-minimal (repaired)" test plan, run at MODEL
level before any 0e RTL exists; the same cells re-run as golden/TB
bit-equivalence when the RTL lands):

  FMINMAX 0x79  ALL frozen cells: the 16-pattern pinned total-order
                ladder (incl. -0/+0 and four denormal patterns), all
                256 pairs x both sub-ops (rows 1/5/6); one-NaN x every
                ladder number x both orders (row 2 — number returned
                BIT-PRESERVED incl. denormals, the DAZ-EXEMPT proof);
                both-NaN -> 0x7FC00000 and sNaN quieting (rows 3/4);
                offset-comparator key asserted strictly monotone over
                the ladder; 10^5 random pairs vs an INDEPENDENT exact-
                Fraction value-level oracle (no DAZ, -0<+0 tie rule).
  DEQUANT 0x78  int4 ALL 16 fields x 2^13 pinned scales (specials +
                exponent-stratified all 256 binades both signs +
                random) and int8 sampled — every point ref == micro ==
                independent exact-Fraction oracle; the ROUND-ONCE
                discriminator/tie cells from mse_sweep (the double-
                rounding twin PROVABLY differs on every discriminator);
                enumerated specials cells (sign-XOR zero, DAZ scale,
                k=0 x Inf -> qNaN, overflow -> Inf never max-finite,
                FTZ-at-dest vacuity); lane->fragment order pins.
  GAMMA_MUL_W   exhaustive 256 (a4, g4) pairs vs an independent sext
  0x6B          oracle, exact range [-56, +64] asserted (int8 proof);
                16-lane order pin lane i = bits [8i+7:8i].
  VFMA 0x70     B-split pin rows (b_mul sext from B[3:0]/B[7:0], c_acc
  (0e2 golden)  = B[63:32], imm zero-fill -> c_acc = 0); mod-2^32 wrap
                edges (c_acc at both int32 rails, products straddling
                2^31) vs an independent int64-truncation oracle;
                int4 exhaustive a x b_mul x directed c_acc; 1.2x10^5
                random lanes; 16/8-fragment count pins.
  MSE GATE      scripts/mse_sweep.run_gate() (the repaired 0e1 release
                gate: eps-inclusive exact reference, denominator-floor
                rule, gamma-variation tensors, pinned int-lane tensor
                generation) — its machine-readable report is embedded
                as the norm_mse_gate_0e1 section.

Vectorized (numpy int64) models are used for volume; they are cross-
checked bit-exactly against the scalar golden models in
scripts/golden_fp32.py on random subsets, so the shipped scalar reference
and the sweep implementation cannot drift apart silently.

WT_FULL_FP_SWEEP=1 additionally runs the chunked 2^32 model-exhaustive
FEXP2 sweep (release gate; minutes, not hours, at int64 vector speed).
"""

import json
import math
import os
import random
import struct
import sys
from fractions import Fraction
from pathlib import Path

import ml_dtypes
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import golden_fp32 as g  # noqa: E402
import mse_sweep  # noqa: E402  (0e1 MSE release gate + shared tie-cell generators)

REPO = Path(__file__).resolve().parent.parent
REPORT = REPO / "include" / "generated" / "fp_validation_report.json"

I64 = np.int64
ULP_BUDGET = 2.0


# ---------------------------------------------------------------------------
# vectorized micro models (int64 twins of golden_fp32.micro_*)
# ---------------------------------------------------------------------------


def _vrto(p, shift):
    q = p >> shift
    q |= (p & ((I64(1) << shift) - I64(1))) != 0
    return q


def _vrne(x, shift):
    q = x >> shift
    rem = x & ((I64(1) << shift) - I64(1))
    half = I64(1) << (shift - 1)
    up = (rem > half) | ((rem == half) & ((q & 1) == 1))
    return q + up


def vrsqrt_classes(parity):
    """All 2^23 mantissa classes at one binade parity. Returns
    (result_bits_for_E=127+parity_input, result_value_float64)."""
    F = g.RSQRT_FRAC
    rom = np.asarray(g.FRSQRT_ROM, dtype=I64)
    m = np.arange(1 << 23, dtype=I64)
    biased_lsb = I64((127 + parity) & 1)
    y = rom[(biased_lsb << 7) | (m >> 16)] << (F - 9)
    xq = ((I64(1) << 23) + m) << (F - 23 + parity)
    h = xq >> 1
    for _ in range(3):
        t1 = _vrto(h * y, F)
        t2 = _vrto(t1 * y, F)
        y = _vrto(y * ((I64(3) << (F - 1)) - t2), F)
    ge1 = y >= (I64(1) << F)
    e_res = np.where(ge1, I64(0), I64(-1))
    frac = np.where(ge1, y, y << 1)
    m24 = _vrne(frac, F - 23)
    carry = m24 == (I64(1) << 24)
    m24 = np.where(carry, I64(1) << 23, m24)
    e_res = e_res + carry
    bits = ((e_res + 127) << 23) | (m24 - (I64(1) << 23))
    val = np.ldexp(m24.astype(np.float64), (e_res - 23).astype(np.int32))
    return bits, val


def vexp2(bits_u32):
    """Vectorized micro_exp2 over arbitrary bit patterns. Returns
    (result_bits, nan_mask, poly_mask, unbounded_val, e_val, m24)."""
    F = g.EXP2_FRAC
    C = [I64(c) for c in g.EXP2_COEFFS]
    b = bits_u32.astype(np.uint64).astype(I64)
    sign = (b >> 31) & 1
    E = (b >> 23) & 0xFF
    M = b & 0x7FFFFF
    nan = (E == 255) & (M != 0)
    pinf = (E == 255) & (M == 0) & (sign == 0)
    ninf = (E == 255) & (M == 0) & (sign == 1)
    Mfull = np.where(E > 0, M + (I64(1) << 23), I64(0))   # DAZ
    Mfull = np.where(E == 255, I64(0), Mfull)
    e_unb = E - 127
    sgn = 1 - 2 * sign
    xf = np.ldexp(Mfull.astype(np.float64), (e_unb - 23).astype(np.int32)) * sgn
    poly = (E != 255) & (xf < 128.0) & (xf > -150.0)
    Meff = np.where(poly, Mfull, I64(0))
    # e_unb-23+30; in-domain |x| < 150 => e_unb <= 7 => t <= 14; the low
    # clamp only affects |x| < 2^-56 where floor(x*2^30) is 0 or -1 anyway
    t = np.clip(e_unb + 7, -63, 14)
    x30 = np.where(t >= 0, (sgn * Meff) << np.maximum(t, 0),
                   (sgn * Meff) >> np.maximum(-t, 0))      # arithmetic >> = floor
    n = x30 >> 30
    Ff = x30 & ((I64(1) << 30) - I64(1))
    acc = np.full(b.shape, C[6], dtype=I64)
    for i in range(5, -1, -1):
        acc = _vrto(acc * Ff, F) + C[i]
    bl31 = acc >= (I64(1) << 31)
    m24 = _vrne(acc, np.where(bl31, I64(8), I64(7)))
    over = m24 == (I64(1) << 24)
    m24 = np.where(over, I64(1) << 23, m24)
    e_val = n + bl31 + over
    res = np.where(e_val > 127, I64(g.F32_PINF),
                   np.where(e_val < -126, I64(0),
                            ((e_val + 127) << 23) | (m24 - (I64(1) << 23))))
    # fast paths / specials override the poly path
    res = np.where((E != 255) & (xf >= 128.0), I64(g.F32_PINF), res)
    res = np.where((E != 255) & (xf <= -150.0), I64(0), res)
    res = np.where(pinf, I64(g.F32_PINF), res)
    res = np.where(ninf, I64(0), res)
    res = np.where(nan, I64(g.F32_QNAN), res)
    unb = np.ldexp(m24.astype(np.float64), (e_val - 23).astype(np.int32))
    return res, nan, poly, unb, e_val, m24


def _goldberg_ulp_exp(ref):
    """Exponent u with ulp(ref) = 2^u (smaller binade at edges)."""
    mant, ex = np.frexp(ref)
    return np.where(mant == 0.5, ex - 25, ex - 24)


# ---------------------------------------------------------------------------
# sweeps
# ---------------------------------------------------------------------------


def sweep_frsqrt():
    print("[frsqrt32] exhaustive 2^24 class sweep (Q2.%d, shipped ROM)..."
          % g.RSQRT_FRAC)
    worst = 0.0
    all_vals = []
    all_errs = []
    all_bits = []
    for p in (0, 1):
        bits, val = vrsqrt_classes(p)
        m = np.arange(1 << 23, dtype=I64)
        xprime = np.ldexp((m + (1 << 23)).astype(np.float64), p - 23)
        exact = 1.0 / np.sqrt(xprime)            # <=1.0 ulp64 measurement error
        err = np.abs(val - exact) * 2.0 ** 24    # ulp = 2^-24 on (0.5, 1]
        all_vals.append(val)
        all_errs.append(err)
        all_bits.append(bits)
        worst = max(worst, float(err.max()))
    vals = np.concatenate(all_vals)
    errs = np.concatenate(all_errs)
    bits = np.concatenate(all_bits)
    mono = bool(np.all(np.diff(vals) <= 0))
    cross = bool(vals[-1] >= vals[0] / 2)        # x'->4 vs next binade's x'=1
    pow4 = bool(vals[0] == 1.0)                  # class (p=0, m=0) == 1.0
    assert pow4 and g.micro_rsqrt(0x40800000) == 0x3F000000  # rsqrt(4)=0.5

    # cross-check vectorized vs scalar golden on random classes
    rng = random.Random(0x5EED)
    for _ in range(10000):
        i = rng.randrange(1 << 24)
        p, m = i >> 23, i & 0x7FFFFF
        inp = ((127 + p) << 23) | m
        assert g.micro_rsqrt(inp) == int(bits[i]), (p, m)

    # exact recheck of the worst 1000 points (isqrt to 2^-60)
    order = np.argsort(errs)[-1000:]
    worst_exact = Fraction(0)
    for i in order:
        i = int(i)
        p, m = i >> 23, i & 0x7FFFFF
        r_bits = int(bits[i])
        r = Fraction((r_bits & 0x7FFFFF) + (1 << 23), 1 << 23) \
            * Fraction(2) ** (((r_bits >> 23) & 0xFF) - 127)
        num, den = (1 << 23) + m << p, 1 << 23   # x' = num/den
        t60 = math.isqrt((den << 120) * num) // num   # floor(2^60/sqrt(x'))
        err = abs(r - Fraction(t60, 1 << 60)) * (1 << 24)
        worst_exact = max(worst_exact, err)
    worst_exact = float(worst_exact)

    print(f"  worst {worst:.6f} ulp (float64), worst-1000 exact recheck "
          f"{worst_exact:.6f} ulp, mono={mono}, cross-binade={cross}, 4^k={pow4}")
    ok = worst <= ULP_BUDGET and worst_exact <= ULP_BUDGET and mono and cross and pow4
    return ok, {
        "sweep": "exhaustive 2^24 mantissa x binade-parity classes, shipped seed ROM",
        "sweep_size": 1 << 24,
        "internal_format": f"Q2.{g.RSQRT_FRAC} round-to-odd, 3 NR iterations",
        "worst_ulp_float64_measured": round(worst, 6),
        "worst_ulp_exact_top1000": round(worst_exact, 6),
        "ulp_budget": ULP_BUDGET,
        "margin": round(ULP_BUDGET - worst, 6),
        "monotonic_nonincreasing": mono,
        "cross_binade_monotonic": cross,
        "pow4_bitexact": pow4,
        "scalar_vector_crosscheck": 10000,
        "measurement_note": "float64 distance measurement error ~2^-28 ulp32 "
                            "(sqrt and divide each correctly rounded in "
                            "float64) — negligible vs the recorded margin; "
                            "worst-1000 rechecked exactly (isqrt to 2^-60).",
    }


def _exp2_window(lo_bits, hi_bits):
    pats = np.arange(lo_bits, hi_bits + 1, dtype=np.uint32)
    res, nan, poly, unb, e_val, m24 = vexp2(pats)
    b = pats.astype(np.uint64).astype(I64)
    E = (b >> 23) & 0xFF
    M = b & 0x7FFFFF
    sgn = 1 - 2 * ((b >> 31) & 1)
    Mfull = np.where(E > 0, M + (I64(1) << 23), I64(0))
    xf = np.ldexp(Mfull.astype(np.float64), (E - 150).astype(np.int32)) * sgn
    sel = poly
    ref = np.exp2(xf[sel])
    err = np.abs(unb[sel] - ref) / np.exp2(
        _goldberg_ulp_exp(ref).astype(np.float64))
    return pats, xf, res, e_val, m24, poly, float(err.max()), int(sel.sum())


def sweep_fexp2(full):
    print("[fexp2_32] 2^22 uniform-over-bit-pattern sample + boundary windows...")
    assert g.EXP2_COEFFS[0] == 1 << 30           # c0 == 1.0 against shipped ROM

    rng = np.random.RandomState(0x77E4)
    pats = rng.randint(0, 2 ** 32, size=1 << 22, dtype=np.uint64).astype(np.uint32)
    res, nan, poly, unb, e_val, m24 = vexp2(pats)
    b = pats.astype(np.uint64).astype(I64)
    E = (b >> 23) & 0xFF
    M = b & 0x7FFFFF
    sgn = 1 - 2 * ((b >> 31) & 1)
    Mfull = np.where(E > 0, M + (I64(1) << 23), I64(0))
    Mfull = np.where(E == 255, I64(0), Mfull)
    xf = np.ldexp(Mfull.astype(np.float64), (E - 150).astype(np.int32)) * sgn
    sel = poly
    ref = np.exp2(xf[sel])
    err = np.abs(unb[sel] - ref) / np.exp2(
        _goldberg_ulp_exp(ref).astype(np.float64))
    worst = float(err.max())

    # monotonic non-decreasing over the sorted finite sample (as final
    # values; +Inf results mapped to a finite top sentinel so diffs stay
    # well-defined)
    keep = E != 255
    rv = np.where(res == g.F32_PINF, 2.0 ** 129,
                  np.ldexp((res & 0x7FFFFF).astype(np.float64) +
                           np.where(((res >> 23) & 0xFF) > 0, 1 << 23, 0),
                           (((res >> 23) & 0xFF) - 150).astype(np.int32)))
    xs = xf[keep]
    rs = rv[keep]
    o = np.argsort(xs, kind="stable")
    mono = bool(np.all((np.diff(rs[o]) >= 0) | (np.diff(xs[o]) <= 0)))

    # scalar/vector cross-check
    prng = random.Random(0xC0C0)
    idx = [prng.randrange(len(pats)) for _ in range(2000)]
    for i in idx:
        assert g.micro_exp2(int(pats[i])) == int(res[i]), hex(int(pats[i]))

    # exhaustive boundary windows (both slivers)
    w1 = _exp2_window(0xC2FA0000, 0xC2FE0000)    # x in [-127, -125]
    w2 = _exp2_window(0x42FE0000, 0x43010000)    # x in [127, 129]
    w1_worst, w1_n = w1[6], w1[7]
    w2_worst, w2_n = w2[6], w2[7]
    # occupancy: fp32 x < -126 whose RN_unbounded rounds UP to min_normal
    pats1, xf1, res1, e1, m241, poly1 = w1[0], w1[1], w1[2], w1[3], w1[4], w1[5]
    sliver_lo = int(np.sum((xf1 < -126.0) & poly1 &
                           (e1 == -126) & (m241 == (1 << 23))))
    # RNE pack overflow reachable from fp32 inputs below 128?
    xf2, e2, poly2 = w2[1], w2[3], w2[5]
    over_reach = int(np.sum((xf2 < 128.0) & poly2 & (e2 > 127)))

    # directed boundary vectors (scalar micro vs exact-rounded reference)
    directed = [0xC2FC0000,          # -126.0        -> min_normal (bypass)
                0xC2FC0001,          # one ulp below  -> +0 (FTZ)
                0xC2FBFFFF,          # one ulp above  -> normal
                0x43000000,          # 128.0          -> +Inf (fast path)
                0x42FFFFFF,          # just below 128 -> finite max-binade
                0xC3160000,          # -150.0         -> +0
                0xC315FFFF]          # just above -150 -> +0 (flush)
    for pat in directed:
        assert g.micro_exp2(pat) == g.ref_exp2(pat), hex(pat)
    assert g.micro_exp2(0xC2FC0000) == g.F32_MIN_NORMAL
    assert g.micro_exp2(0xC2FC0001) == 0
    assert g.micro_exp2(0x43000000) == g.F32_PINF

    # integers [-150, 128] bit-exact through the bypass
    for n in range(-150, 129):
        pat = int.from_bytes(struct.pack(">f", float(n)), "big")
        assert g.micro_exp2(pat) == g.ref_exp2(pat), n

    full_worst = None
    if full:
        print("  WT_FULL_FP_SWEEP: chunked 2^32 model-exhaustive...")
        full_worst = 0.0
        for base in range(0, 1 << 32, 1 << 24):
            pats_c = np.arange(base, base + (1 << 24), dtype=np.uint64).astype(np.uint32)
            res_c, nan_c, poly_c, unb_c, _, _ = vexp2(pats_c)
            bc = pats_c.astype(np.uint64).astype(I64)
            Ec = (bc >> 23) & 0xFF
            Mc = np.where(Ec > 0, (bc & 0x7FFFFF) + (I64(1) << 23), I64(0))
            Mc = np.where(Ec == 255, I64(0), Mc)
            sgnc = 1 - 2 * ((bc >> 31) & 1)
            xfc = np.ldexp(Mc.astype(np.float64), (Ec - 150).astype(np.int32)) * sgnc
            selc = poly_c & (Ec != 255)
            if selc.any():
                refc = np.exp2(xfc[selc])
                errc = np.abs(unb_c[selc] - refc) / np.exp2(
                    _goldberg_ulp_exp(refc).astype(np.float64))
                full_worst = max(full_worst, float(errc.max()))
        print(f"  full-exhaustive worst {full_worst:.6f} ulp")

    print(f"  worst {worst:.6f} ulp sampled ({int(sel.sum())} in-domain), "
          f"slivers: [-127,-125] worst {w1_worst:.6f} ({w1_n} pts), "
          f"[127,129] worst {w2_worst:.6f} ({w2_n} pts), mono={mono}")
    worst_all = max(worst, w1_worst, w2_worst, full_worst or 0.0)
    ok = worst_all <= ULP_BUDGET and mono
    rep = {
        "sample_sweep": "2^22 uniform-over-bit-pattern, seed 0x77E4",
        "sample_sweep_size": 1 << 22,
        "sample_in_domain": int(sel.sum()),
        "internal_format": f"Q1.30 coefficients, Q2.{g.EXP2_FRAC} Horner round-to-odd",
        "worst_ulp_sampled": round(worst, 6),
        "boundary_window_neg126": {
            "window": "[-127.0, -125.0] exhaustive", "points": w1_n,
            "worst_ulp_unbounded": round(w1_worst, 6),
            "fp32_points_below_neg126_rounding_up_to_min_normal": sliver_lo,
        },
        "boundary_window_128": {
            "window": "[127.0, 129.0] exhaustive", "points": w2_n,
            "worst_ulp_unbounded": round(w2_worst, 6),
            "rne_pack_overflow_reachable_below_128": over_reach,
        },
        "integers_bitexact_range": [-150, 128],
        "monotonic_nondecreasing": mono,
        "c0_exact_one": True,
        "ulp_budget": ULP_BUDGET,
        "margin": round(ULP_BUDGET - worst_all, 6),
        "scalar_vector_crosscheck": 2000,
    }
    if full_worst is not None:
        rep["full_exhaustive_worst_ulp"] = round(full_worst, 6)
        rep["full_exhaustive_size"] = 1 << 32
    return ok, rep


def sweep_fdiv():
    print("[fdiv] 10^5 random pairs + 10^4 midpoint-adjacent vs reference...")
    rng = random.Random(0xD1F)
    mism_rand = 0
    for _ in range(100000):
        a, b = rng.getrandbits(32), rng.getrandbits(32)
        if g.micro_div(a, b) != g.ref_div(a, b):
            mism_rand += 1
    mism_mid = 0
    for _ in range(10000):
        eb = rng.randint(-60, 60)
        b = ((eb + 127) << 23) | rng.getrandbits(23)
        Mq = (1 << 23) + rng.getrandbits(23)
        qmid = Fraction(2 * Mq + 1, 1 << 24)     # RNE midpoint in [1,2)
        a = g.pack_rne_ftz(0, g.bits_to_frac(b) * qmid)
        if g.micro_div(a, b) != g.ref_div(a, b):
            mism_mid += 1
    print(f"  random mismatches {mism_rand}, midpoint-adjacent mismatches {mism_mid}")
    ok = mism_rand == 0 and mism_mid == 0
    return ok, {
        "random_pairs": 100000, "random_mismatches": mism_rand,
        "midpoint_adjacent": 10000, "midpoint_mismatches": mism_mid,
        "internal_format": f"Q2.{g.DIV_FRAC} round-to-odd Newton reciprocal "
                           "(3 iterations) + exact Markstein correction",
        "bit_exact": ok,
        "seed": "0xD1F",
    }


# ===========================================================================
# v1.8.0d format-layer sweeps
# ===========================================================================

M64 = (1 << 64) - 1


def _f32_isnan(bits_i64):
    return ((bits_i64 & 0x7F800000) == 0x7F800000) & ((bits_i64 & 0x7FFFFF) != 0)


def vnarrow_bits(bits_u32, dtype):
    """Vectorized int64 twin of golden_fp32.ref_narrow_f32 (the bit-level
    disjoint round/sticky formulation), used for volume; cross-checked
    bit-exactly against the scalar authority on random subsets."""
    b = bits_u32.astype(np.uint64).astype(I64)
    s = (b >> 31) & 1
    E = (b >> 23) & 0xFF
    M = b & 0x7FFFFF
    nan = (E == 255) & (M != 0)
    inf = (E == 255) & (M == 0)
    zero = E == 0                            # DAZ pre-stage + true zero
    if dtype == g.DT_F16:
        m24 = M | (I64(1) << 23)
        rb = (m24 >> 12) & 1                 # R = MSB of the 13 dropped bits
        sb = ((m24 & 0xFFF) != 0).astype(I64)
        lb = (m24 >> 13) & 1                 # kept-LSB
        m11 = (m24 >> 13) + (rb & (sb | lb))
        e = E - 127
        carry = m11 == (I64(1) << 11)
        m11 = np.where(carry, I64(1) << 10, m11)
        e = e + carry
        res = (s << 15) | ((e + 15) << 10) | (m11 - (I64(1) << 10))
        res = np.where(e > 15, (s << 15) | I64(g.F16_PINF), res)
        res = np.where(e < -14, s << 15, res)          # FTZ-at-destination
        res = np.where(zero, s << 15, res)
        res = np.where(inf, (s << 15) | I64(g.F16_PINF), res)
        res = np.where(nan, I64(g.F16_QNAN), res)
    else:
        rb = (b >> 15) & 1
        sb = ((b & 0x7FFF) != 0).astype(I64)
        lb = (b >> 16) & 1
        res = ((b >> 16) + (rb & (sb | lb))) & 0xFFFF  # ripple -> Inf natively
        res = np.where(zero, s << 15, res)
        res = np.where(inf, (s << 15) | I64(g.BF16_PINF), res)
        res = np.where(nan, I64(g.BF16_QNAN), res)
    return res


def vnarrow_value_ref(bits_u32, dtype):
    """INDEPENDENT value-level formulation of the pinned narrow semantics
    (float64 frexp + rint — no bit tricks shared with the golden
    authority): DAZ, one 11/8-bit RNE in the unbounded-exponent domain,
    overflow -> Inf, FTZ-at-f16-destination, canonical qNaN. Exact by
    construction: f32->f64 is exact, the power-of-two scale is exact,
    np.rint rounds once with ties-to-even."""
    b = bits_u32.astype(np.uint64).astype(I64)
    s = (b >> 31) & 1
    E = (b >> 23) & 0xFF
    M = b & 0x7FFFFF
    nan = (E == 255) & (M != 0)
    inf = (E == 255) & (M == 0)
    zero = E == 0
    val = np.ldexp((M | (I64(1) << 23)).astype(np.float64),
                   (E - 150).astype(np.int32))
    val = np.where(zero | (E == 255), 1.0, val)        # dummy on masked lanes
    mant, ex = np.frexp(val)
    p = 11 if dtype == g.DT_F16 else 8                 # significand width
    q = np.rint(mant * (1 << p)).astype(I64)           # ONE rounding (RNE)
    carry = q == (I64(1) << p)
    q = np.where(carry, I64(1) << (p - 1), q)
    ue = ex.astype(I64) + carry.astype(I64) - 1        # unbounded exponent
    if dtype == g.DT_F16:
        bias, mw, pinf, qnan, emax, emin = 15, 10, g.F16_PINF, g.F16_QNAN, 15, -14
    else:
        bias, mw, pinf, qnan, emax, emin = 127, 7, g.BF16_PINF, g.BF16_QNAN, 127, -126
    res = (s << 15) | ((ue + bias) << mw) | (q - (I64(1) << (p - 1)))
    res = np.where(ue > emax, (s << 15) | I64(pinf), res)
    res = np.where(ue < emin, s << 15, res)
    res = np.where(zero, s << 15, res)
    res = np.where(inf, (s << 15) | I64(pinf), res)
    res = np.where(nan, I64(qnan), res)
    return res


def sweep_cvt_widen_f16():
    print("[cvt widen f16] exhaustive 2^16 vs numpy float16 oracle...")
    pats = np.arange(1 << 16, dtype=np.uint16)
    oracle = pats.view(np.float16).astype(np.float32).view(np.uint32) \
                 .astype(np.uint64).astype(I64)
    Eh = (pats.astype(I64) >> 10) & 0x1F
    Mh = pats.astype(I64) & 0x3FF
    nan = (Eh == 0x1F) & (Mh != 0)
    sub = (Eh == 0) & (Mh != 0)
    mism = nan_bad = 0
    for h in range(1 << 16):
        got = g.ref_widen_f16(h)
        if nan[h]:
            # documented divergence: golden canonicalizes EVERY NaN to
            # 0x7FC00000 (pin 2); numpy preserves payloads. Excluded from
            # the bit compare; both sides asserted NaN.
            if got != g.F32_QNAN or not _f32_isnan(int(oracle[h])):
                nan_bad += 1
        elif got != int(oracle[h]):
            mism += 1                        # incl. subnormals: exact both sides
    n_nan, n_sub = int(nan.sum()), int(sub.sum())
    ok = mism == 0 and nan_bad == 0
    print(f"  non-NaN mismatches {mism} ({(1 << 16) - n_nan} compared, "
          f"{n_sub} subnormals honored exactly), NaN rows bad {nan_bad}")
    return ok, {
        "sweep": "exhaustive 2^16 f16 patterns, exact-injection widen",
        "sweep_size": 1 << 16,
        "mismatches_vs_oracle": mism,
        "oracle": "numpy float16 -> float32 astype (independent, pin 13)",
        "oracle_compared": (1 << 16) - n_nan,
        "subnormal_inputs_honored_exact": n_sub,
        "nan_patterns_canonicalized_to_0x7FC00000": n_nan,
        "nan_rows_bad": nan_bad,
        "oracle_exclusion": "NaN payloads only — golden canonicalizes (sNaN "
                            "quieted); both sides asserted NaN. Subnormals "
                            "are IN the compare (exact on both sides).",
    }


def sweep_cvt_widen_bf16():
    print("[cvt widen bf16] exhaustive 2^16 vs ml_dtypes bfloat16 oracle...")
    pats = np.arange(1 << 16, dtype=np.uint16)
    oracle = pats.view(ml_dtypes.bfloat16).astype(np.float32).view(np.uint32) \
                 .astype(np.uint64).astype(I64)
    Eb = (pats.astype(I64) >> 7) & 0xFF
    Mb = pats.astype(I64) & 0x7F
    nan = (Eb == 0xFF) & (Mb != 0)
    sub = (Eb == 0) & (Mb != 0)
    mism = nan_bad = sub_bad = 0
    for bts in range(1 << 16):
        got = g.ref_widen_bf16(bts)
        if nan[bts]:
            if got != g.F32_QNAN or not _f32_isnan(int(oracle[bts])):
                nan_bad += 1
        elif sub[bts]:
            # documented divergence (pin 6): the exact splice lands in
            # fp32-SUBNORMAL space (ml_dtypes confirms: nonzero, exp==0);
            # golden flushes to signed zero, DAZ-consistent.
            o = int(oracle[bts])
            o_is_f32_subnormal = (o & 0x7F800000) == 0 and (o & 0x7FFFFF) != 0
            if got != ((bts >> 15) << 31) or not o_is_f32_subnormal:
                sub_bad += 1
        else:
            if got != int(oracle[bts]) or got != (bts << 16):
                mism += 1                    # exact splice, both checks
    n_nan, n_sub = int(nan.sum()), int(sub.sum())
    ok = mism == 0 and nan_bad == 0 and sub_bad == 0
    print(f"  splice mismatches {mism} ({(1 << 16) - n_nan - n_sub} compared), "
          f"subnormal-flush rows bad {sub_bad} (of {n_sub}), NaN rows bad {nan_bad}")
    return ok, {
        "sweep": "exhaustive 2^16 bf16 patterns, bit-splice widen",
        "sweep_size": 1 << 16,
        "mismatches_vs_oracle": mism,
        "oracle": "ml_dtypes bfloat16 -> float32 astype (independent, pin 13)",
        "oracle_compared": (1 << 16) - n_nan - n_sub,
        "subnormal_inputs_flushed_to_signed_zero": n_sub,
        "subnormal_rows_bad": sub_bad,
        "nan_patterns_canonicalized_to_0x7FC00000": n_nan,
        "nan_rows_bad": nan_bad,
        "oracle_exclusions": "NaN payloads (golden canonicalizes; both sides "
                             "asserted NaN) and the 254 bf16-subnormal inputs "
                             "(pinned signed-zero flush; oracle asserted to "
                             "land in fp32-subnormal space, proving the "
                             "splice-would-be-subnormal rationale).",
    }


F16_WINDOWS = [
    ("denormal_band_bottom_2^-24", 0x337F8000, 0x33808000),
    ("min_normal_2^-14", 0x387F8000, 0x38808000),
    ("max_finite_overflow_65504_65520", 0x477F8000, 0x47808000),
]


def _narrow_random(dtype, seed, size):
    """2^22 random narrow volume: bit-formulation twin vs the independent
    value-level formulation on EVERY point, plus the external oracle
    (numpy float16 / ml_dtypes bfloat16) with the pinned divergences
    masked, plus scalar/vector and store_quant==cvt wiring cross-checks."""
    rng = np.random.RandomState(seed)
    pats = rng.randint(0, 2 ** 32, size=size, dtype=np.uint64).astype(np.uint32)
    twin = vnarrow_bits(pats, dtype)
    vref = vnarrow_value_ref(pats, dtype)
    bit_vs_value = int((twin != vref).sum())
    b = pats.astype(np.uint64).astype(I64)
    in_nan = _f32_isnan(b)
    x32 = pats.view(np.float32)
    with np.errstate(over="ignore", invalid="ignore"):
        if dtype == g.DT_F16:
            o = x32.astype(np.float16).view(np.uint16).astype(I64)
            # FTZ-at-destination divergence band, defined on RESULTS: golden
            # flushed to +-0 while IEEE kept a nonzero value — this covers
            # both the subnormal results AND the [2^-14-2^-25, 2^-14-2^-26)
            # input sliver where IEEE rounds up to min-normal but the
            # unbounded-round flush decision (pin 5) still flushes.
            ftz = ((twin & 0x7FFF) == 0) & ((o & 0x7FFF) != 0)
            mask = in_nan | ftz
            ftz_div = int(ftz.sum())
            # masked rows asserted both ways
            bad_mask = int((in_nan & (twin != g.F16_QNAN)).sum())
            onan = ((o & 0x7C00) == 0x7C00) & ((o & 0x3FF) != 0)
            bad_mask += int((in_nan & ~onan).sum())
            # FTZ rows: signs agree and the IEEE magnitude is at most
            # min-normal (never beyond the documented band)
            bad_mask += int((ftz & ((o & 0x7FFF) > 0x0400)).sum())
            bad_mask += int((ftz & ((o >> 15) != (twin >> 15))).sum())
            daz_div = 0                      # fp32 denorms: both sides give +-0
        else:
            o = x32.astype(ml_dtypes.bfloat16).view(np.uint16).astype(I64)
            in_denorm = (((b >> 23) & 0xFF) == 0) & ((b & 0x7FFFFF) != 0)
            mask = in_nan | in_denorm        # NaN payloads + DAZ divergence
            ftz_div = 0
            daz_div = int(in_denorm.sum())
            bad_mask = int((in_nan & (twin != g.BF16_QNAN)).sum())
            bad_mask += int((in_denorm & (twin != ((b >> 31) << 15))).sum())
            onan = ((o & 0x7F80) == 0x7F80) & ((o & 0x7F) != 0)
            bad_mask += int((in_nan & ~onan).sum())
    oracle_mism = int(((twin != o) & ~mask).sum())
    # scalar authority / vectorized twin / store_quant wiring cross-check
    prng = random.Random(seed ^ 0x5CA1A)
    xchk_bad = 0
    for _ in range(10000):
        i = prng.randrange(size)
        pb = int(pats[i])
        r = g.ref_narrow_f32(pb, dtype)
        if r != int(twin[i]) or r != g.store_quant(pb, dtype) \
                or r != g.cvt(g.CVT_NARROW_FROM_F32, dtype, pb):
            xchk_bad += 1
    return {
        "random_sweep_size": size,
        "seed": hex(seed),
        "bit_vs_value_formulation_mismatches": bit_vs_value,
        "oracle_mismatches": oracle_mism,
        "oracle_compared": size - int(mask.sum()),
        "oracle_masked_rows_bad": bad_mask,
        "oracle_masked_ftz_band": ftz_div,
        "oracle_masked_daz_inputs": daz_div,
        "oracle_masked_nan": int(in_nan.sum()),
        "scalar_vector_storequant_crosscheck": 10000,
        "crosscheck_bad": xchk_bad,
    }, bit_vs_value == 0 and oracle_mism == 0 and bad_mask == 0 and xchk_bad == 0


def sweep_cvt_narrow_f16():
    print("[cvt narrow f16] boundary slivers exhaustive + ties + 2^22 random...")
    win_reports = []
    win_ok = True
    survivors = 0
    for name, lo, hi in F16_WINDOWS:
        for sgn in (0, 0x80000000):
            base = np.arange(lo, hi, dtype=np.uint64) | sgn
            pats = base.astype(np.uint32)
            twin = vnarrow_bits(pats, g.DT_F16)
            vref = vnarrow_value_ref(pats, g.DT_F16)
            bvv = int((twin != vref).sum())
            scal_bad = 0
            for i, pb in enumerate(pats.tolist()):
                if g.ref_narrow_f32(pb, g.DT_F16) != int(twin[i]):
                    scal_bad += 1
            # numpy oracle, FTZ band masked (the documented GPU divergence;
            # result-defined band — see _narrow_random)
            with np.errstate(over="ignore", invalid="ignore"):
                o = pats.view(np.float32).astype(np.float16) \
                        .view(np.uint16).astype(I64)
            ftzm = ((twin & 0x7FFF) == 0) & ((o & 0x7FFF) != 0)
            om = int(((twin != o) & ~ftzm).sum())
            om_band = int((ftzm & (((o & 0x7FFF) > 0x0400) |
                                   ((o >> 15) != (twin >> 15)))).sum())
            if name == "min_normal_2^-14" and sgn == 0:
                survivors = int(((pats < 0x38800000) & (twin == 0x0400)).sum())
            win_ok &= bvv == 0 and scal_bad == 0 and om == 0 and om_band == 0
            win_reports.append({
                "window": name, "sign": "-" if sgn else "+",
                "points": int(pats.size),
                "bit_vs_value_mismatches": bvv,
                "scalar_vs_vector_mismatches": scal_bad,
                "oracle_mismatches_unmasked": om,
                "oracle_ftz_band_masked": int(ftzm.sum()),
                "ftz_band_rows_bad": om_band,
            })
    # per-ULP RNE tie set: R=1, S=0 -> increment iff kept-LSB odd
    tie_bad = 0
    tie_n = 0
    for E in (0x71, 0x7E, 0x7F, 0x8E):       # e = -14, -1, 0, 15
        for sgn in (0, 1):
            for k in range(1024):
                bits = (sgn << 31) | (E << 23) | (k << 13) | 0x1000
                got = g.ref_narrow_f32(bits, g.DT_F16)
                m11 = (1 << 10) + k + (k & 1)
                e = E - 127
                if m11 == 1 << 11:
                    m11, e = 1 << 10, e + 1
                exp = ((sgn << 15) | g.F16_PINF) if e > 15 else \
                    ((sgn << 15) | ((e + 15) << 10) | (m11 - (1 << 10)))
                tie_n += 1
                if got != exp:
                    tie_bad += 1
    # overflow threshold directed (0x477FF000 == 65520.0 -> Inf, pin 4)
    thr_ok = (g.ref_narrow_f32(0x477FF000, g.DT_F16) == 0x7C00
              and g.ref_narrow_f32(0x477FEFFF, g.DT_F16) == 0x7BFF
              and g.ref_narrow_f32(0xC77FF000, g.DT_F16) == 0xFC00)
    # NaN canonicalization directed
    nan_ok = all(g.ref_narrow_f32(x, g.DT_F16) == g.F16_QNAN for x in
                 (0x7FC00000, 0xFFC00000, 0x7F800001, 0xFF800001, 0x7FFFFFFF))
    # DAZ sliver (for f16 the flush is oracle-invisible: numpy also gives
    # +-0 for fp32-denormal sources — recorded, not a divergence)
    daz_ok = all(g.ref_narrow_f32(x, g.DT_F16) == 0
                 for x in range(0x007FFF80, 0x00800000))
    rnd, rnd_ok = _narrow_random(g.DT_F16, 0xF16, 1 << 22)
    ok = win_ok and tie_bad == 0 and thr_ok and nan_ok and daz_ok and rnd_ok
    print(f"  windows ok={win_ok}, ties {tie_bad}/{tie_n} bad, "
          f"min-normal round-up survivors {survivors}, "
          f"random bit-vs-value {rnd['bit_vs_value_formulation_mismatches']}, "
          f"oracle {rnd['oracle_mismatches']} mismatches")
    return ok, {
        "boundary_windows": win_reports,
        "min_normal_roundup_survivors": survivors,
        "tie_set": {"points": tie_n, "bad": tie_bad,
                    "rule": "R & (S | kept-LSB), S==0 exact ties"},
        "overflow_threshold_65520_to_inf": thr_ok,
        "nan_canonicalization_0x7E00": nan_ok,
        "daz_sliver_0x007FFF80_0x007FFFFF_flushes": daz_ok,
        "random": rnd,
    }


def sweep_cvt_narrow_bf16():
    print("[cvt narrow bf16] exact-tie classes + sticky vectors + 2^22 random...")
    # even/odd-quotient exact ties: significand class 0x808000 + (k<<16)
    tie_bad = even_down = odd_up = 0
    for E in (0x01, 0x64, 0x7F, 0xC8, 0xFE):
        for sgn in (0, 1):
            for k in range(128):
                bits = (sgn << 31) | (E << 23) | (k << 16) | 0x8000
                got = g.ref_narrow_f32(bits, g.DT_BF16)
                exp = ((bits >> 16) + (k & 1)) & 0xFFFF
                if got != exp:
                    tie_bad += 1
                elif k & 1:
                    odd_up += 1
                else:
                    even_down += 1           # the round-half-up defect trap
    # sticky-disjointness directed vectors (R/S/L fully crossed)
    stk_bad = stk_n = 0
    for E in (0x01, 0x7F, 0xFE):
        for sgn in (0, 1):
            for k in (0, 1, 126, 127):
                for low in (0x8001, 0x7FFF, 0x0001, 0xFFFF, 0x4000, 0xC000):
                    bits = (sgn << 31) | (E << 23) | (k << 16) | low
                    rb, sb, lb = (low >> 15) & 1, 1 if low & 0x7FFF else 0, k & 1
                    exp = ((bits >> 16) + (rb & (sb | lb))) & 0xFFFF
                    stk_n += 1
                    if g.ref_narrow_f32(bits, g.DT_BF16) != exp:
                        stk_bad += 1
    # the DAZ sliver — the one band where DAZ is observable at a 16-bit
    # destination: without DAZ these would RNE UP to bf16 min-normal 0x0080
    sliver = np.arange(0x007FFF80, 0x00800000, dtype=np.uint32)
    with np.errstate(over="ignore", invalid="ignore"):
        o_sliver = sliver.view(np.float32).astype(ml_dtypes.bfloat16) \
                         .view(np.uint16).astype(I64)
    daz_flush_ok = all(g.ref_narrow_f32(int(x), g.DT_BF16) == 0
                       for x in sliver.tolist())
    would_round_up = int((o_sliver == 0x0080).sum())
    # max-finite -> Inf ripple + NaN canonicalization directed
    edge_ok = (g.ref_narrow_f32(0x7F7FFFFF, g.DT_BF16) == 0x7F80
               and g.ref_narrow_f32(0xFF7FFFFF, g.DT_BF16) == 0xFF80
               and g.ref_narrow_f32(0x7F7F7FFF, g.DT_BF16) == 0x7F7F)
    nan_ok = all(g.ref_narrow_f32(x, g.DT_BF16) == g.BF16_QNAN for x in
                 (0x7FC00000, 0xFFC00000, 0x7F800001, 0xFF800001, 0x7FFFFFFF))
    rnd, rnd_ok = _narrow_random(g.DT_BF16, 0xBF16, 1 << 22)
    ok = (tie_bad == 0 and stk_bad == 0 and daz_flush_ok
          and would_round_up == len(sliver) and edge_ok and nan_ok and rnd_ok)
    print(f"  exact ties {tie_bad} bad ({even_down} even-down / {odd_up} odd-up), "
          f"sticky vectors {stk_bad}/{stk_n} bad, DAZ sliver {len(sliver)} "
          f"flushed (oracle would round {would_round_up} up to 0x0080), "
          f"random oracle {rnd['oracle_mismatches']} mismatches")
    return ok, {
        "exact_tie_classes": {"points": 1280, "bad": tie_bad,
                              "even_quotient_down": even_down,
                              "odd_quotient_up": odd_up},
        "sticky_disjointness_vectors": {"points": stk_n, "bad": stk_bad},
        "daz_sliver": {"band": "0x007FFF80-0x007FFFFF", "points": len(sliver),
                       "golden_flushes_to_zero": daz_flush_ok,
                       "oracle_would_round_up_to_0x0080": would_round_up},
        "max_finite_ripple_to_inf": edge_ok,
        "nan_canonicalization_0x7FC0": nan_ok,
        "random": rnd,
    }


def sweep_narrow_full_2e32():
    """WT_FULL_FP_SWEEP=1 release gate: the chunked/vectorized 2^32
    EXHAUSTIVE narrow sweep for the bit-identity clause (COMMIT-0 pin 12,
    spec 23.10.10(d)). The 0x7C == 0x77 two-site identity is true by
    construction (one ref_narrow_f32), so the non-vacuous exhaustive
    obligation is proving that ONE shared authority correct for ALL 2^32
    inputs: the bit-level disjoint-round/sticky formulation vs the
    independent float64 frexp/rint value-level formulation, both formats."""
    print("[narrow 2^32] WT_FULL_FP_SWEEP: chunked exhaustive, f16 + bf16...")
    out = {}
    for name, dt in (("f16", g.DT_F16), ("bf16", g.DT_BF16)):
        mism = 0
        for base in range(0, 1 << 32, 1 << 22):
            pats = np.arange(base, base + (1 << 22),
                             dtype=np.uint64).astype(np.uint32)
            mism += int((vnarrow_bits(pats, dt)
                         != vnarrow_value_ref(pats, dt)).sum())
        print(f"  {name}: {mism} mismatches over 2^32")
        out[name] = mism
    ok = out["f16"] == 0 and out["bf16"] == 0
    return ok, {
        "sweep": "chunked exhaustive 2^32, bit-formulation vs independent "
                 "float64 frexp/rint value formulation (bit-identity clause "
                 "enforcement: two-site identity is by construction, single "
                 "shared authority proven exhaustively)",
        "sweep_size": 1 << 32,
        "f16_mismatches": out["f16"],
        "bf16_mismatches": out["bf16"],
    }


def _i2f_buggy_rne_rne(v):
    """The FORBIDDEN composition (pass-1 RNE, pass-2 RNE) — exists only to
    prove the directed discriminators have power."""
    if v == 0:
        return 0
    s = 1 if v < 0 else 0
    a = -v if s else v
    bl = a.bit_length()
    e = bl - 1
    if bl > 32:
        inter = g._rne_shift(a, bl - 32)
        if inter == 1 << 32:
            inter, e = 1 << 31, e + 1
        bl_i = 32
    else:
        inter, bl_i = a, bl
    if bl_i <= 24:
        m24 = inter << (24 - bl_i)
    else:
        m24 = g._rne_shift(inter, bl_i - 24)
        if m24 == 1 << 24:
            m24, e = 1 << 23, e + 1
    return (s << 31) | ((e + 127) << 23) | (m24 - (1 << 23))


def sweep_i2f():
    print("[i2f] int4/int8 exhaustive + int64 two-pass discriminators + 2^20 random...")
    # int4 / int8 exhaustive, exactness proven against struct
    small_bad = 0
    for dtype, lo, hi in ((g.DT_INT4, -8, 8), (g.DT_INT8, -128, 128)):
        for v in range(lo, hi):
            got = g.ref_i2f(v & M64, dtype)
            exact = int.from_bytes(struct.pack(">f", float(v)), "big")
            if got != exact or g.micro_cvt(0, dtype, v & M64) != exact:
                small_bad += 1
    # int32 directed rows (exact below 2^24, RNE above)
    d32 = [0, 1, -1, (1 << 24) - 1, 1 << 24, (1 << 24) + 1, (1 << 24) + 2,
           (1 << 24) + 3, -((1 << 24) + 1), 0x7FFFFFFF, -(1 << 31),
           0x7FFFFFC0, 0x7FFFFFBF]
    d32_bad = 0
    for v in d32:
        got = g.ref_i2f(v & M64, g.DT_ACC_INT)
        exact = int.from_bytes(struct.pack(">f", float(np.float32(v))), "big")
        if got != exact or g.micro_i2f_acc(v & M64) != got:
            d32_bad += 1
    # directed two-pass discriminator family: pass-1 RNE would round up
    # onto the 24-bit midpoint; kept-LSB odd resolves the manufactured tie
    # upward -> buggy is +1 ulp. RTO must match the single-RNE reference.
    disc = [(1 << 40) + (1 << 17) + 0xFFFF]  # the docstring counterexample
    for bl in range(34, 64):
        d, p = bl - 24, bl - 32
        field = (((1 << (d - 1 - p)) - 1) << p) | ((1 << (p - 1)) + 1)
        disc.append((1 << (bl - 1)) | (1 << d) | field)
    disc += [-v for v in disc]
    disc_bad = buggy_caught = 0
    for v in disc:
        r = g.ref_i2f(v & M64, g.DT_ACC_INT)
        if g.micro_i2f_acc(v & M64) != r:
            disc_bad += 1                    # two-pass pin broken -> BLOCKER
        if _i2f_buggy_rne_rne(v) != r:
            buggy_caught += 1                # discriminator has power
    # 2^20 random int64 (half full-range, half magnitude-stratified) vs the
    # numpy int64 -> float32 oracle (hardware cvt, RNE) and micro==ref
    rng = np.random.RandomState(0x12F)
    u = rng.randint(0, 2 ** 64, size=1 << 19, dtype=np.uint64)
    sh = rng.randint(0, 64, size=1 << 19).astype(np.uint64)
    vals = np.concatenate([u, rng.randint(0, 2 ** 64, size=1 << 19,
                                          dtype=np.uint64) >> sh]).view(np.int64)
    oracle = vals.astype(np.float32).view(np.uint32)
    rnd_bad = 0
    for i in range(vals.size):
        v = int(vals[i])
        r = g.ref_i2f(v & M64, g.DT_ACC_INT)
        if r != int(oracle[i]) or g.micro_i2f_acc(v & M64) != r:
            rnd_bad += 1
    two_pass_ok = disc_bad == 0 and rnd_bad == 0
    ok = (small_bad == 0 and d32_bad == 0 and two_pass_ok
          and buggy_caught == len(disc))
    print(f"  int4+int8 exhaustive bad {small_bad}, int32 directed bad {d32_bad}, "
          f"discriminators: two-pass bad {disc_bad}, RNE-RNE caught "
          f"{buggy_caught}/{len(disc)}, random bad {rnd_bad}/{vals.size}")
    return ok, {
        "int4_exhaustive": 16, "int8_exhaustive": 256,
        "small_exact_bad": small_bad,
        "int32_directed": len(d32), "int32_directed_bad": d32_bad,
        "int64_discriminators": len(disc),
        "two_pass_rto_rne_mismatches_vs_single_rne": disc_bad,
        "buggy_rne_rne_caught": buggy_caught,
        "int64_random": int(vals.size), "int64_random_bad": rnd_bad,
        "oracle": "numpy int64 -> float32 astype (hardware RNE cvt)",
        "seed": "0x12F",
    }


def sweep_f2i():
    print("[f2i] directed edges + 2^20 random vs rint/clip oracle...")
    N = M64
    directed = [
        # (f32 bits, dtype, expected sext64)
        (0x3F000000, g.DT_INT8, 0), (0xBF000000, g.DT_INT8, 0),      # +-0.5
        (0x3FC00000, g.DT_INT8, 2), (0xBFC00000, g.DT_INT8, (-2) & N),  # +-1.5
        (0x40200000, g.DT_INT8, 2),                                  # 2.5 -> 2
        (0x40D00000, g.DT_INT4, 6),                                  # 6.5 -> 6
        (0x40F00000, g.DT_INT4, 7),          # 7.5 -> RNE 8 -> clamp 7
        (0x41000000, g.DT_INT4, 7), (0x41000000, g.DT_INT8, 8),      # 8.0
        (0xC1080000, g.DT_INT4, (-8) & N),   # -8.5 -> RNE -8 (even), in range
        (0xC1100000, g.DT_INT4, (-8) & N),   # -9 -> clamp
        (0x42FF0000, g.DT_INT8, 127),        # 127.5 -> RNE 128 -> clamp
        (0x42FF0000, g.DT_ACC_INT, 128),
        (0xC3008000, g.DT_INT8, (-128) & N),  # -128.5 -> RNE -128 (even)
        (0xC3010000, g.DT_INT8, (-128) & N),  # -129 -> clamp
        (0x4EFFFFFF, g.DT_ACC_INT, 2147483520),   # largest f32 < 2^31
        (0x4F000000, g.DT_ACC_INT, (1 << 31) - 1),  # 2^31 -> clamp
        (0xCF000000, g.DT_ACC_INT, (-(1 << 31)) & N),  # -2^31 exact, in range
        (0xCF000001, g.DT_ACC_INT, (-(1 << 31)) & N),  # below -> clamp
        (0x3EFFFFFF, g.DT_ACC_INT, 0),       # 0.49999997 -> 0
        (0x3F000001, g.DT_ACC_INT, 1),       # just above 0.5 -> 1
        (0x00000001, g.DT_INT8, 0), (0x807FFFFF, g.DT_INT8, 0),      # DAZ
    ]
    for dt in (g.DT_INT4, g.DT_INT8, g.DT_ACC_INT):
        lo, hi = g.F2I_BOUNDS[dt]
        directed += [(0x7F800000, dt, hi & N), (0xFF800000, dt, lo & N),
                     (0x7FC00000, dt, 0), (0xFFC00000, dt, 0),
                     (0x7F800001, dt, 0)]    # sNaN -> 0, DATA not error
    dir_bad = sum(1 for bits, dt, exp in directed
                  if g.ref_f2i(bits, dt) != exp
                  or g.cvt(g.CVT_NARROW_FROM_F32, dt, bits) != exp)
    # 2^20 random split across dtypes, half uniform patterns, half scaled
    rng = np.random.RandomState(0xF21)
    rnd_bad = 0
    rnd_n = 0
    for dt, share in ((g.DT_INT4, 1 << 18), (g.DT_INT8, 1 << 18),
                      (g.DT_ACC_INT, 1 << 19)):
        lo, hi = g.F2I_BOUNDS[dt]
        pats_u = rng.randint(0, 2 ** 32, size=share // 2,
                             dtype=np.uint64).astype(np.uint32)
        scaled = ((rng.random_sample(share // 2) * 3.0 - 1.5) * hi) \
            .astype(np.float32).view(np.uint32)
        pats = np.concatenate([pats_u, scaled])
        with np.errstate(invalid="ignore"):
            x = pats.view(np.float32).astype(np.float64)  # sNaN cast quiets
            o = np.clip(np.rint(x), lo, hi)  # independent composition
            o = np.where(np.isnan(x), 0.0, o).astype(np.int64)
        for i in range(pats.size):
            if g.ref_f2i(int(pats[i]), dt) != (int(o[i]) & N):
                rnd_bad += 1
        rnd_n += int(pats.size)
    ok = dir_bad == 0 and rnd_bad == 0
    print(f"  directed bad {dir_bad}/{len(directed)}, random bad {rnd_bad}/{rnd_n}")
    return ok, {
        "directed": len(directed), "directed_bad": dir_bad,
        "random": rnd_n, "random_bad": rnd_bad,
        "oracle": "float64 rint (RNE) + clip + NaN->0 composition "
                  "(independent of the Fraction-based golden path)",
        "seed": "0xF21",
    }


def sweep_accew():
    print("[acc_elemwise] 10^5 random composition + fused discriminators...")
    rng = random.Random(0xACCE)
    pool = [0, 0x80000000, g.F32_PINF, g.F32_NINF, g.F32_QNAN, 0x7F800001,
            0x00000001, 0x007FFFFF, g.F32_MIN_NORMAL, 0x7F7FFFFF, g.F32_ONE]

    def rnd32():
        return rng.choice(pool) if rng.random() < 0.1 else rng.getrandbits(32)

    comp_bad = 0
    for _ in range(100000):
        a, hi, lo = rnd32(), rnd32(), rnd32()
        B = (hi << 32) | lo
        r = g.accew(a, B)
        if r != g.ref_fma(a, hi, lo) or g.micro_accew(a, B) != r:
            comp_bad += 1
    # gamma=1.0 / beta=+0 identity rows over random normals + specials
    ident_bad = 0
    ident_n = 0
    B1 = (g.F32_ONE << 32) | 0
    for _ in range(1000):
        a = rng.getrandbits(32)
        if g.decode(a)[1] != "fin":
            continue
        ident_n += 1
        if g.accew(a, B1) != a:
            ident_bad += 1
    ident_ok = (ident_bad == 0
                and g.accew(g.F32_PINF, B1) == g.F32_PINF
                and g.accew(g.F32_QNAN, B1) == g.F32_QNAN
                and g.accew(0x7F800001, B1) == g.F32_QNAN)
    # round-once proof: fused result differs from mul-then-add exactly
    # where the exact product carries a sub-ulp tail that the tiny addend
    # tips across the RNE midpoint
    fused_rows = [
        (0x3F800800, 0x3F800800, 0x2B800000, 0x3F801001, 0x3F801000),
        (0x3F800800, 0x3F800800, 0xAB800000, 0x3F801000, 0x3F801000),
    ]
    fused_bad = 0
    fused_discriminating = 0
    for a, hi, lo, want_fused, want_two in fused_rows:
        f = g.accew(a, (hi << 32) | lo)
        t = g.ref_add(g.ref_mul(a, hi), lo)
        if f != want_fused or t != want_two:
            fused_bad += 1
        if f != t:
            fused_discriminating += 1
    ok = (comp_bad == 0 and ident_ok and fused_bad == 0
          and fused_discriminating >= 1)
    print(f"  composition bad {comp_bad}/100000, identity bad {ident_bad}/"
          f"{ident_n}, fused rows bad {fused_bad} "
          f"(discriminating {fused_discriminating})")
    return ok, {
        "random": 100000, "composition_mismatches": comp_bad,
        "micro_equals_ref": True,
        "identity_rows": ident_n, "identity_bad": ident_bad,
        "fused_vs_two_step_rows": len(fused_rows),
        "fused_rows_bad": fused_bad,
        "fused_rows_discriminating": fused_discriminating,
        "bit_match_target": "ref_fma == micro_fscalar(FS_FMA) — pinned",
        "seed": "0xACCE",
    }


def sweep_roundtrip():
    print("[round-trip E-row] narrow(widen(x)) exhaustive 2^16 x {f16, bf16}...")
    reps = {}
    ok = True
    for name, dt, widen, qnan, ebits, mbits in (
            ("f16", g.DT_F16, g.ref_widen_f16, g.F16_QNAN, 5, 10),
            ("bf16", g.DT_BF16, g.ref_widen_bf16, g.BF16_QNAN, 8, 7)):
        emax = (1 << ebits) - 1
        in_scope = sub_flush = nan_canon = bad = 0
        for x in range(1 << 16):
            e = (x >> mbits) & emax
            m = x & ((1 << mbits) - 1)
            back = g.ref_narrow_f32(widen(x), dt)
            if e == emax and m:                      # NaN
                if x == qnan:
                    in_scope += 1                    # canonical qNaN: in scope
                    if back != x:
                        bad += 1
                else:
                    nan_canon += 1                   # re-scoped out (pin)
                    if back != qnan:
                        bad += 1
            elif e == 0 and m:                       # subnormal: fails BY DESIGN
                sub_flush += 1                       # (FTZ / widen-flush pins)
                if back != (x >> 15) << 15:
                    bad += 1
            else:                                    # normals, +-0, +-Inf
                in_scope += 1
                if back != x:
                    bad += 1
        ok &= bad == 0
        reps[name] = {"in_scope_identity": in_scope,
                      "subnormals_flushed_by_design": sub_flush,
                      "noncanonical_nan_canonicalized": nan_canon,
                      "bad": bad}
        print(f"  {name}: {in_scope} in-scope identical, {sub_flush} "
              f"subnormals flushed, {nan_canon} NaNs canonicalized, bad {bad}")
    reps["scope"] = ("normals/+-0/+-Inf/canonical-qNaN ONLY (re-scoped "
                     "E-row); f16 subnormals fail by the FTZ pin, bf16 "
                     "subnormals by the widen signed-zero pin — asserted, "
                     "not ignored")
    return ok, reps


# ===========================================================================
# v1.8.0e wide-vector layer sweeps (COMMIT 1, golden-before-RTL)
# ===========================================================================

# The pinned FMINMAX total-order ladder: 16 patterns spanning the full
# monotone chain {-Inf .. +Inf} INCLUDING -0/+0 (frozen row 1) and four
# denormal patterns (frozen row 6, DAZ-EXEMPT bit-pattern-preserving).
FMM_LADDER = [
    0xFF800000,  # -Inf
    0xFF7FFFFF,  # -max normal
    0xC0490FDB,  # -pi
    0xBF800000,  # -1
    0x80800000,  # -min normal
    0x807FFFFF,  # -max denormal   (row-6 cell)
    0x80000001,  # -min denormal   (row-6 cell)
    0x80000000,  # -0              (row-1 cell)
    0x00000000,  # +0              (row-1 cell)
    0x00000001,  # +min denormal   (row-6 cell)
    0x007FFFFF,  # +max denormal   (row-6 cell)
    0x00800000,  # +min normal
    0x3F800000,  # +1
    0x40490FDB,  # +pi
    0x7F7FFFFF,  # +max normal
    0x7F800000,  # +Inf
]

FMM_NAN_POOL = [0x7FC00000, 0xFFC00000,   # canonical qNaN both signs
                0x7F800001, 0xFF800001,   # sNaN min payload both signs
                0x7FFFFFFF,               # qNaN max payload
                0x7FBFFFFF]               # sNaN max payload

_FMM_MIN = g.FMINMAX_OP_CODE["MINIMUMNUM"]
_FMM_MAX = g.FMINMAX_OP_CODE["MAXIMUMNUM"]


def _fmm_is_nan(bits):
    return (bits & 0x7F800000) == 0x7F800000 and (bits & 0x7FFFFF) != 0


def _fmm_value_oracle(a, b, subop):
    """INDEPENDENT value-level FMINMAX oracle: exact Fraction compare
    with NO DAZ (denormals exact via bits_to_frac), +-Inf as sentinels
    beyond the finite range, the -0 < +0 rule applied at value ties
    (the ONLY distinct-pattern value tie in fp32), NaN rows from the
    frozen table — no bit tricks shared with the offset-comparator key."""
    an, bn = _fmm_is_nan(a), _fmm_is_nan(b)
    if an and bn:
        return g.F32_QNAN
    if an:
        return b
    if bn:
        return a

    def val(bits):
        if (bits & 0x7F800000) == 0x7F800000:            # +-Inf
            return Fraction(2) ** 200 * (-1 if bits >> 31 else 1)
        return g.bits_to_frac(bits)                      # exact, NO DAZ

    va, vb = val(a), val(b)
    if va != vb:
        lo, hi = (a, b) if va < vb else (b, a)
    elif a == b:
        lo = hi = a
    else:                                                # +-0: -0 < +0
        lo = a if a >> 31 else b
        hi = b if a >> 31 else a
    return lo if subop == _FMM_MIN else hi


def sweep_fminmax_0e():
    print("[fminmax 0x79] frozen-row cells (ladder/NaN/denormal) + 10^5 random...")
    # offset-comparator key strictly monotone over the pinned ladder (row 5)
    keys = [g.f32_total_order_key(x) for x in FMM_LADDER]
    key_mono = all(keys[i] < keys[i + 1] for i in range(len(keys) - 1))

    # rows 1 + 5 + 6: all 256 ladder pairs x both sub-ops; expected result is
    # the ladder-lower/upper pattern RETURNED BIT-EXACTLY (denormal pairs are
    # the row-6 DAZ-EXEMPT proof; the -0/+0 pair is row 1 both directions)
    order_bad = 0
    denorm_preserved = 0
    for i, a in enumerate(FMM_LADDER):
        for j, b in enumerate(FMM_LADDER):
            lo = FMM_LADDER[min(i, j)]
            hi = FMM_LADDER[max(i, j)]
            got_min = g.ref_fminmax_lane(a, b, _FMM_MIN)
            got_max = g.ref_fminmax_lane(a, b, _FMM_MAX)
            if got_min != lo or got_max != hi:
                order_bad += 1
            if (lo & 0x7F800000) == 0 and (lo & 0x7FFFFF) != 0 and got_min == lo:
                denorm_preserved += 1
    order_cells = len(FMM_LADDER) ** 2 * 2

    # row 2 (one NaN -> the number, bit-preserved) — every NaN x every ladder
    # number x both orders x both sub-ops; sNaN against a number still loses
    one_nan_bad = 0
    for nn in FMM_NAN_POOL:
        for x in FMM_LADDER:
            for sub in (_FMM_MIN, _FMM_MAX):
                if g.ref_fminmax_lane(nn, x, sub) != x:
                    one_nan_bad += 1
                if g.ref_fminmax_lane(x, nn, sub) != x:
                    one_nan_bad += 1
    one_nan_cells = len(FMM_NAN_POOL) * len(FMM_LADDER) * 4

    # rows 3 + 4 (both-NaN -> canonical 0x7FC00000; sNaN quieted to canonical)
    both_nan_bad = 0
    for na in FMM_NAN_POOL:
        for nb in FMM_NAN_POOL:
            for sub in (_FMM_MIN, _FMM_MAX):
                if g.ref_fminmax_lane(na, nb, sub) != g.F32_QNAN:
                    both_nan_bad += 1
    both_nan_cells = len(FMM_NAN_POOL) ** 2 * 2

    # random sweep vs the independent value-level oracle
    rng = random.Random(0xF79)
    pool = FMM_LADDER + FMM_NAN_POOL + [0x00000005, 0x80000005]

    def rnd32():
        return rng.choice(pool) if rng.random() < 0.15 else rng.getrandbits(32)

    rnd_bad = 0
    rnd_n = 100000
    for _ in range(rnd_n):
        a, b, sub = rnd32(), rnd32(), rng.choice((_FMM_MIN, _FMM_MAX))
        if g.ref_fminmax_lane(a, b, sub) != _fmm_value_oracle(a, b, sub):
            rnd_bad += 1

    # vector entry + fragment wrapper: 4 lanes vs broadcast B, lane i at
    # flat bits [32i+31:32i], 2 fragments in = 2 fragments out (today's FSM)
    lanes = [0x80000000, 0x7FC00000, 0x00000001, 0xC0490FDB]
    b_bc = 0x00000000
    frags_in = g.lanes_to_frags(lanes, 32)
    out = g.fminmax_frags(frags_in, b_bc, _FMM_MIN)
    vec_ok = (len(frags_in) == 2 and len(out) == 2
              and g.frags_to_lanes(out, 32, 4)
              == [g.ref_fminmax_lane(a, b_bc, _FMM_MIN) for a in lanes])

    ok = (key_mono and order_bad == 0 and one_nan_bad == 0
          and both_nan_bad == 0 and rnd_bad == 0 and vec_ok)
    print(f"  key monotone {key_mono}, order cells bad {order_bad}/{order_cells}, "
          f"one-NaN bad {one_nan_bad}/{one_nan_cells}, both-NaN bad "
          f"{both_nan_bad}/{both_nan_cells}, random bad {rnd_bad}/{rnd_n}")
    return ok, {
        "semantics": "frozen IEEE-2019 minimumNumber/maximumNumber, six "
                     "pinned rows; comparator key a[31] ? ~a : a^0x80000000, "
                     "ONE unsigned 32b compare; DATA functions only (the "
                     "FSCALAR-clone legality re-row is decode-level)",
        "comparator_key_strictly_monotone_on_ladder": key_mono,
        "total_order_cells": order_cells, "total_order_bad": order_bad,
        "ladder_patterns": len(FMM_LADDER),
        "denormal_min_cells_bit_preserved": denorm_preserved,
        "one_nan_cells": one_nan_cells, "one_nan_bad": one_nan_bad,
        "both_nan_cells": both_nan_cells, "both_nan_bad": both_nan_bad,
        "canonical_qnan": "0x7FC00000 (sNaN quieted to canonical)",
        "random": rnd_n, "random_bad": rnd_bad,
        "oracle": "independent exact-Fraction value-level compare, NO DAZ, "
                  "-0<+0 tie rule (disjoint from the offset-key formulation)",
        "vector_2frag_lane_order_pin": vec_ok,
        "daz_exempt_note": "ref_fminmax operates on RAW bit patterns, never "
                           "golden decode() — denormal cells returned "
                           "bit-identically (pinned row 6)",
        "seed": "0xF79",
    }


def _dequant_scale_set():
    """The pinned 2^13-scale set: directed specials, exponent-stratified
    coverage of ALL 256 exponent fields at both signs (mantissa 0 / 1 /
    max / random), the rest fixed-seed random bit patterns."""
    scales = [
        0x00000000, 0x80000000,              # +-0
        0x00000001, 0x80000001,              # +-min denormal (DAZ)
        0x007FFFFF, 0x807FFFFF,              # +-max denormal (DAZ)
        0x00800000, 0x80800000,              # +-min normal (never flushed)
        0x7F7FFFFF, 0xFF7FFFFF,              # +-max normal
        0x7F800000, 0xFF800000,              # +-Inf
        0x7FC00000, 0xFFC00000,              # +-canonical qNaN
        0x7F800001, 0xFF800001,              # +-sNaN
        0x7FFFFFFF,                          # qNaN max payload
        0x3F800000, 0xBF800000,              # +-1.0
        0x3F7FFFFF, 0x3F800001,              # 1.0 +- 1 ulp
    ]
    rng = random.Random(0xDE05)
    for e in range(256):
        for s in (0, 1):
            for m in (0, 1, 0x7FFFFF, rng.getrandbits(23)):
                scales.append((s << 31) | (e << 23) | m)
    while len(scales) < (1 << 13):
        scales.append(rng.getrandbits(32))
    return scales[:1 << 13]


def sweep_dequant_0e():
    print("[dequant 0x78] int4 exhaustive x 2^13 scales + int8 sampled + "
          "round-once cells...")
    scales = _dequant_scale_set()

    # int4: ALL 16 fields x all 2^13 scales — ref == micro == independent
    # exact-Fraction oracle on every point
    i4_rm = i4_ro = 0
    for f in range(16):
        for s in scales:
            r = g.ref_dequant_lane(f, s, g.DT_INT4)
            if g.micro_dequant_lane(f, s, g.DT_INT4) != r:
                i4_rm += 1
            if mse_sweep.dequant_exact_oracle(f, s, g.DT_INT4) != r:
                i4_ro += 1
    i4_n = 16 * len(scales)

    # int8: all 256 fields x a 128-scale stratified subsample, plus 2^15
    # random (field, scale) pairs
    sub = scales[::64]
    i8_rm = i8_ro = 0
    for f in range(256):
        for s in sub:
            r = g.ref_dequant_lane(f, s, g.DT_INT8)
            if g.micro_dequant_lane(f, s, g.DT_INT8) != r:
                i8_rm += 1
            if mse_sweep.dequant_exact_oracle(f, s, g.DT_INT8) != r:
                i8_ro += 1
    rng = random.Random(0xDE08)
    for _ in range(1 << 15):
        f, s = rng.getrandbits(8), rng.getrandbits(32)
        r = g.ref_dequant_lane(f, s, g.DT_INT8)
        if g.micro_dequant_lane(f, s, g.DT_INT8) != r:
            i8_rm += 1
        if mse_sweep.dequant_exact_oracle(f, s, g.DT_INT8) != r:
            i8_ro += 1
    i8_n = 256 * len(sub) + (1 << 15)

    # ROUND-ONCE narrow-tie cells (shared generators with mse_sweep — the
    # enforcement point of rounding definition (a); MSE ratio is blind)
    tie_rep, tie_ok = mse_sweep.check_round_once_cells()

    # enumerated specials cells (every pinned row exercised by name)
    sp = [
        # k = 0: signed zero by sign-XOR; k=0 x Inf -> qNaN
        (0x0, 0x3F800000, g.DT_INT4, 0x0000),
        (0x0, 0xBF800000, g.DT_INT4, 0x8000),
        (0x0, 0x7F800000, g.DT_INT4, g.BF16_QNAN),
        (0x0, 0xFF800000, g.DT_INT4, g.BF16_QNAN),
        # scale +-0 with k nonzero: signed zero by sign-XOR
        (0x7, 0x80000000, g.DT_INT4, 0x8000),
        (0x8, 0x00000000, g.DT_INT4, 0x8000),   # k=-8 x +0 -> -0
        (0x8, 0x80000000, g.DT_INT4, 0x0000),   # k=-8 x -0 -> +0
        # scale denormal -> DAZ at operand load -> signed-zero rows
        (0x7, 0x007FFFFF, g.DT_INT4, 0x0000),
        (0x7, 0x807FFFFF, g.DT_INT4, 0x8000),
        (0x80, 0x00000001, g.DT_INT8, 0x8000),  # k=-128 x DAZ(+denorm) -> -0
        # scale NaN (incl. sNaN) -> canonical bf16 qNaN
        (0x7, 0x7FC00000, g.DT_INT4, g.BF16_QNAN),
        (0x7, 0x7F800001, g.DT_INT4, g.BF16_QNAN),
        (0x0, 0xFFC00000, g.DT_INT4, g.BF16_QNAN),
        # scale +-Inf with k nonzero: sign-XOR Inf
        (0x1, 0x7F800000, g.DT_INT4, 0x7F80),
        (0x1, 0xFF800000, g.DT_INT4, 0xFF80),
        (0x9, 0x7F800000, g.DT_INT4, 0xFF80),   # k=-7 x +Inf -> -Inf
        # product overflow -> +-Inf, NEVER max-finite
        (0x7F, 0x7F000000, g.DT_INT8, 0x7F80),  # 127 * 2^127 -> +Inf
        (0x80, 0x7F000000, g.DT_INT8, 0xFF80),  # -128 * 2^127 -> -Inf
        (0x2, 0x7F7FFFFF, g.DT_INT4, 0x7F80),   # 2 * maxnormal -> +Inf
        # near-overflow max-finite kept (RNE does not overflow)
        (0x1, 0x7F7F0000, g.DT_INT8, 0x7F7F),
        # FTZ-at-dest vacuity: min nonzero product == bf16 min-normal
        (0x1, 0x00800000, g.DT_INT4, 0x0080),
        (0xF, 0x00800000, g.DT_INT4, 0x8080),   # k=-1 -> -min-normal
    ]
    sp_bad = 0
    for f, s, dt, want in sp:
        if (g.ref_dequant_lane(f, s, dt) != want
                or g.micro_dequant_lane(f, s, dt) != want):
            sp_bad += 1

    # vector forms + lane->fragment order pins (bf16 4 lanes/word):
    # int4 32-lane = 2 frags in -> 8 frags out; int8 16-lane -> 4 frags out
    rngv = random.Random(0xDEF2)
    vec_ok = True
    for dt, lb in ((g.DT_INT4, 4), (g.DT_INT8, 8)):
        n = g.DEQUANT_LANES[dt]
        lanes = [rngv.getrandbits(lb) for _ in range(n)]
        s = 0x3E99999A                        # 0.3, forces rounding activity
        out = g.dequant_frags(g.lanes_to_frags(lanes, lb), s, dt)
        vec_ok &= len(out) == g.DEQUANT_OUT_FRAGS[dt]
        got = g.frags_to_lanes(out, 16, n)
        vec_ok &= got == [g.ref_dequant_lane(f, s, dt) for f in lanes]

    ok = (i4_rm == 0 and i4_ro == 0 and i8_rm == 0 and i8_ro == 0
          and tie_ok and sp_bad == 0 and vec_ok)
    print(f"  int4 {i4_n} pts (ref-vs-micro bad {i4_rm}, oracle bad {i4_ro}), "
          f"int8 {i8_n} pts (bad {i8_rm}/{i8_ro}), ties: "
          f"{tie_rep['discriminators']} disc caught "
          f"{tie_rep['double_round_caught']}, specials bad {sp_bad}/{len(sp)}")
    return ok, {
        "semantics": "int4/int8 x fp32 broadcast scale -> bf16-ONLY (0e pin), "
                     "ROUND-ONCE definition (a): one RNE from the exact "
                     "<= 31-bit product (|k| <= 128 and m_s < 2^24 both fit "
                     "the wide product exactly — nothing rounds before the "
                     "single RNE-to-bf16)",
        "narrow_authority": "ref reuses ref_narrow_f32 (THE single f32->bf16 "
                            "authority) through a sticky-preserving round-to-"
                            "odd 24-bit intermediate — bit-identity with the "
                            "CVT narrow path by construction; micro is the "
                            "independent OPS_DEQ disjoint-round/sticky "
                            "bf16-pack twin",
        "int4_points": i4_n, "int4_scales": len(scales),
        "int4_ref_vs_micro_bad": i4_rm, "int4_vs_exact_oracle_bad": i4_ro,
        "int8_points": i8_n,
        "int8_ref_vs_micro_bad": i8_rm, "int8_vs_exact_oracle_bad": i8_ro,
        "scale_set": "pinned 2^13: directed specials + all 256 exponent "
                     "fields x both signs x {0,1,max,random} mantissas + "
                     "fixed-seed random fill (seeds 0xDE05/0xDE08)",
        "round_once_cells": tie_rep,
        "specials_cells": len(sp), "specials_bad": sp_bad,
        "ftz_at_dest_vacuity": "min nonzero |product| = 1 x 2^-126 = bf16 "
                               "min-normal exactly (asserted 0x0080/0x8080) "
                               "— the FTZ cell is pinned for the pack logic "
                               "and unreachable from valid operands",
        "vector_frag_pins_ok": vec_ok,
        "out_frags": {"int4_32": 8, "int8_16": 4},
    }


def sweep_gamma_mul_w_0e():
    print("[gamma_mul_w 0x6B] exhaustive 256 pairs + 16-lane order pin...")

    def sext4(v):
        v &= 0xF
        return v - 16 if v & 0x8 else v

    exh_bad = 0
    lo = hi = 0
    for a in range(16):
        for gm in range(16):
            p = sext4(a) * sext4(gm)          # independent formulation
            lo, hi = min(lo, p), max(hi, p)
            if g.ref_gamma_mul_w_lane(a, gm) != (p & 0xFF):
                exh_bad += 1
    range_ok = lo == -56 and hi == 64         # the int8 range proof, measured

    # 16-lane vector + the lane order pin (lane i at bits [8i+7:8i], 2 frags)
    a_lanes = list(range(16))                 # ramp: -8..-1 map to 0x8..0xF
    g_lanes = [(5 * i + 3) & 0xF for i in range(16)]
    a_frag = g.lanes_to_frags(a_lanes, 4)[0]
    g_imm = g.lanes_to_frags(g_lanes, 4)[0]
    out = g.gamma_mul_w_frags(a_frag, g_imm)
    order_ok = len(out) == 2
    flat = out[0] | (out[1] << 64)
    for i in range(16):
        want = g.ref_gamma_mul_w_lane(a_lanes[i], g_lanes[i])
        if (flat >> (8 * i)) & 0xFF != want:
            order_ok = False

    ok = exh_bad == 0 and range_ok and order_ok
    print(f"  exhaustive bad {exh_bad}/256, range [{lo},{hi}] "
          f"(int8 proof ok={range_ok}), lane-order pin ok={order_ok}")
    return ok, {
        "semantics": "out[i] = sext8(a4[i]) * sext8(g4[i]) — EXACT widening "
                     "int4 x int4 -> int8, MU-hosted (0e1, pre-stable "
                     "reallocation of the retired 0x6B code point)",
        "exhaustive_pairs": 256, "exhaustive_bad": exh_bad,
        "measured_range": [lo, hi],
        "int8_range_proof": "products in [-56, +64] subset [-128, 127] — "
                            "rounding-free AND saturation-free (measured "
                            "over all 256 cells, matches the docstring "
                            "proof: min (-8)*7 = -56, max (-8)*(-8) = +64)",
        "lane_order_pin_ok": order_ok,
        "lane_order": "lane i = bits [8i+7:8i] of the 128b output (2 frags), "
                      "pinned in spec + golden + SDK together",
        "gamma_transport": "imm64 XOR OPREF (legality rung, decode-level — "
                           "not modeled by the DATA functions)",
        "oracle": "independent inline sext4 multiply",
    }


def _wrap32_oracle(a_val, b_mul, c_acc):
    """Independent mod-2^32 formulation: int64 little-endian truncation
    (struct), no shared code with ref_vfma_lane's mask."""
    return struct.unpack("<I", struct.pack("<q", a_val * b_mul + c_acc)[:4])[0]


def sweep_vfma_0e2():
    print("[vfma 0x70 (0e2 golden)] B-split pins + wrap edges + 1.2x10^5 "
          "random lanes...")
    # B-split pin rows: b_mul = sext32(B[3:0]) int4 / sext32(B[7:0]) int8;
    # c_acc = B[63:32]; imm16/imm32 zero-fill -> c_acc = 0
    split_rows = [
        # (B payload, dtype, want_b_mul, want_c_acc)
        (0x80, g.DT_INT4, 0, 0),              # int4 reads [3:0] of 0x80 = 0
        (0x80, g.DT_INT8, -128, 0),
        (0x7F, g.DT_INT4, -1, 0),             # [3:0] = 0xF
        (0x7F, g.DT_INT8, 127, 0),
        (0xF8, g.DT_INT4, -8, 0),             # [3:0] = 0x8
        (0xF8, g.DT_INT8, -8, 0),
        (0x07, g.DT_INT4, 7, 0),
        ((0x7FFFFFFF << 32) | 0x01, g.DT_INT4, 1, (1 << 31) - 1),
        ((0x80000000 << 32) | 0x01, g.DT_INT8, 1, -(1 << 31)),
        ((0xFFFFFFFF << 32) | 0x02, g.DT_INT4, 2, -1),
        ((0xDEADBEEF << 32) | 0xF8, g.DT_INT8, -8, 0xDEADBEEF - (1 << 32)),
    ]
    split_bad = sum(1 for b, dt, wm, wc in split_rows
                    if g.vfma_b_split(b, dt) != (wm, wc))

    # explicit mod-2^32 wrap edges (c_acc at the rails, product straddling)
    wrap_rows = [
        # (a_field, b_mul, c_acc, dtype)
        (0x7, 1, (1 << 31) - 7, g.DT_INT4),          # lands exactly on 2^31
        (0x7, 1, (1 << 31) - 8, g.DT_INT4),          # one below the rail
        (0x8, -8, (1 << 31) - 1, g.DT_INT4),         # 64 + max -> wrap
        (0x1, -1, -(1 << 31), g.DT_INT4),            # -1 + min -> wrap down
        (0x8, (1 << 31) - 1, 0, g.DT_INT4),          # -8 * max
        (0x80, -(1 << 31), 0, g.DT_INT8),            # -128 * min (positive)
        (0x80, (1 << 31) - 1, -(1 << 31), g.DT_INT8),
        (0x7F, (1 << 31) - 1, (1 << 31) - 1, g.DT_INT8),
        (0x0, 0, -(1 << 31), g.DT_INT8),             # 0*0 + min
    ]
    wrap_bad = 0
    for f, bm, ca, dt in wrap_rows:
        a_val = g._i2f_operand(f, dt)
        if g.ref_vfma_lane(f, bm, ca, dt) != _wrap32_oracle(a_val, bm, ca):
            wrap_bad += 1

    # int4 exhaustive: 16 a-fields x 16 b_mul nibbles x directed c_acc rail set
    rails = [0, 1, -1, (1 << 31) - 1, -(1 << 31), (1 << 31) - 64,
             -(1 << 31) + 63, 0x55555555]
    exh_bad = 0
    for f in range(16):
        a_val = g._i2f_operand(f, g.DT_INT4)
        for bn in range(16):
            bm = bn - 16 if bn & 0x8 else bn
            for ca in rails:
                if g.ref_vfma_lane(f, bm, ca, g.DT_INT4) != \
                        _wrap32_oracle(a_val, bm, ca):
                    exh_bad += 1
    exh_n = 16 * 16 * len(rails)

    # 1.2 x 10^5 random full-path lanes (vfma_frags -> per-lane oracle),
    # both dtypes, incl. the 16-fragment int4 form (the mask-fix consumer)
    rng = random.Random(0x0E70)
    rnd_bad = 0
    frag_ok = True
    for dt, lb in ((g.DT_INT4, 4), (g.DT_INT8, 8)):
        n = g.VFMA_LANES[dt]
        for _ in range(2500):
            lanes = [rng.getrandbits(lb) for _ in range(n)]
            B = rng.getrandbits(64)
            out = g.vfma_frags(g.lanes_to_frags(lanes, lb), B, dt)
            frag_ok &= len(out) == g.VFMA_OUT_FRAGS[dt]
            bm, ca = g.vfma_b_split(B, dt)
            got = g.frags_to_lanes(out, 32, n)
            for i in range(n):
                if got[i] != _wrap32_oracle(g._i2f_operand(lanes[i], dt),
                                            bm, ca):
                    rnd_bad += 1
    rnd_n = 2500 * (g.VFMA_LANES[g.DT_INT4] + g.VFMA_LANES[g.DT_INT8])

    ok = (split_bad == 0 and wrap_bad == 0 and exh_bad == 0
          and rnd_bad == 0 and frag_ok)
    print(f"  B-split bad {split_bad}/{len(split_rows)}, wrap edges bad "
          f"{wrap_bad}/{len(wrap_rows)}, int4 exhaustive bad {exh_bad}/{exh_n}, "
          f"random lanes bad {rnd_bad}/{rnd_n}, frag counts ok={frag_ok}")
    return ok, {
        "staging": "0x70 is a 0e2 op — golden authored NOW (golden-before-"
                   "RTL), consumed by the 0e2 RTL commit",
        "semantics": "out[i] = (sext32(a[i]) * b_mul + c_acc) mod 2^32 "
                     "EXPLICIT; STATELESS (acc bit = 1 marks the wide-acc "
                     "OUTPUT form, not stateful accumulation)",
        "b_split_rows": len(split_rows), "b_split_bad": split_bad,
        "b_split_pin": "c_acc = B[63:32] broadcast int32; b_mul = "
                       "sext32(B[3:0]) int4 / sext32(B[7:0]) int8; "
                       "imm16/imm32 zero-fill -> c_acc = 0 (asm-lint "
                       "loudly rejects out-of-range b_mul imm encodings "
                       "— lint rule, not datapath)",
        "wrap_edge_rows": len(wrap_rows), "wrap_edge_bad": wrap_bad,
        "int4_exhaustive": exh_n, "int4_exhaustive_bad": exh_bad,
        "random_lanes": rnd_n, "random_bad": rnd_bad,
        "oracle": "independent int64 little-endian struct truncation "
                  "(no shared mask code)",
        "out_frags": {"int4_32": 16, "int8_16": 8},
        "frag_note": "int4 form = 16 fragments — the first consumer of the "
                     "frag-FSM widening + Cluster frag_mask_full fix",
        "seed": "0x0E70",
    }


def sweep_lane_frag_packing_0e():
    print("[lane<->frag packing] pinned map round-trips, all 0e shapes...")
    rng = random.Random(0x0EFA)
    shapes = [(4, 32), (4, 16), (8, 16), (8, 32), (16, 32), (16, 16),
              (32, 4), (32, 32), (32, 16)]
    bad = 0
    trips = 0
    for lb, n in shapes:
        for _ in range(500):
            lanes = [rng.getrandbits(lb) for _ in range(n)]
            frags = g.lanes_to_frags(lanes, lb)
            trips += 1
            if (len(frags) != n * lb // 64
                    or g.frags_to_lanes(frags, lb, n) != lanes):
                bad += 1
    # directed word-position pin: lane j of word f sits at bits
    # [lb*j +: lb] of frag f — spot-checked at every lane width
    directed_ok = (g.lanes_to_frags([0xA, 0xB] + [0] * 14, 4)[0] == 0xBA
                   and g.lanes_to_frags([0x11, 0x22] + [0] * 6, 8)[0] == 0x2211
                   and g.lanes_to_frags([0x1234, 0x5678] + [0] * 2, 16)[0]
                   == 0x56781234
                   and g.lanes_to_frags([0xDEADBEEF, 0xCAFEF00D], 32)[0]
                   == 0xCAFEF00DDEADBEEF)
    ok = bad == 0 and directed_ok
    print(f"  round-trips bad {bad}/{trips}, directed word-position pin "
          f"ok={directed_ok}")
    return ok, {
        "pin": "lane i at flat bits [lane_bits*i +: lane_bits]; fragment f "
               "= flat[64f +: 64] low-first; 16 int4 / 8 int8 / 4 bf16 / "
               "2 int32-or-f32 lanes per 64b word (spec+golden+SDK pin; "
               "the '2 bf16/word' prose error is corrected to 4)",
        "round_trips": trips, "round_trip_bad": bad,
        "directed_word_position_ok": directed_ok,
        "shapes": [f"{lb}b x {n}" for lb, n in shapes],
        "seed": "0x0EFA",
    }


def main():
    full = os.environ.get("WT_FULL_FP_SWEEP") == "1"
    ok1, rep1 = sweep_frsqrt()
    ok2, rep2 = sweep_fexp2(full)
    ok3, rep3 = sweep_fdiv()
    ok4, rep4 = sweep_cvt_widen_f16()
    ok5, rep5 = sweep_cvt_widen_bf16()
    ok6, rep6 = sweep_cvt_narrow_f16()
    ok7, rep7 = sweep_cvt_narrow_bf16()
    if full:
        okf, repf = sweep_narrow_full_2e32()
        ok6 &= okf
        ok7 &= okf
        rep6["full_exhaustive_2e32"] = repf
        rep7["full_exhaustive_2e32"] = repf
    ok8, rep8 = sweep_i2f()
    ok9, rep9 = sweep_f2i()
    ok10, rep10 = sweep_accew()
    ok11, rep11 = sweep_roundtrip()
    ok12, rep12 = sweep_fminmax_0e()
    ok13, rep13 = sweep_dequant_0e()
    ok14, rep14 = sweep_gamma_mul_w_0e()
    ok15, rep15 = sweep_vfma_0e2()
    ok16, rep16 = sweep_lane_frag_packing_0e()
    ok17, rep17 = mse_sweep.run_gate()
    all_ok = all((ok1, ok2, ok3, ok4, ok5, ok6, ok7, ok8, ok9, ok10, ok11,
                  ok12, ok13, ok14, ok15, ok16, ok17))
    report = {
        "_doc": "v1.8.0c core + v1.8.0d format layer + v1.8.0e wide-vector "
                "layer fp golden-model validation — generated by "
                "scripts/fp_release_sweep.py against the SHIPPED "
                "include/generated fp artifacts (model-only sweeps, "
                "COMMIT 1 golden-before-RTL; RTL lockstep tests land "
                "with the respective RTL commits; the 0e sections rerun "
                "as golden/TB bit-equivalence at the 0e1/0e2 RTL gates).",
        "frsqrt32": rep1,
        "fexp2_32": rep2,
        "fdiv": rep3,
        "cvt_widen_f16": rep4,
        "cvt_widen_bf16": rep5,
        "cvt_narrow_f16": rep6,
        "cvt_narrow_bf16": rep7,
        "i2f": rep8,
        "f2i": rep9,
        "acc_elemwise": rep10,
        "roundtrip_e_row": rep11,
        "fminmax_0e": rep12,
        "dequant_0e": rep13,
        "gamma_mul_w_0e": rep14,
        "vfma_0e2": rep15,
        "lane_frag_packing_0e": rep16,
        "norm_mse_gate_0e1": rep17,
        "bit_identity_0x7C_eq_0x77": "true by construction — one golden "
                                     "ref_narrow_f32 is the single authority "
                                     "called by both cvt(NARROW_FROM_F32) and "
                                     "store_quant; wiring pinned by 2x10^4 "
                                     "sampled assertions per format",
        "independent_oracle_policy": {
            "rule": "COMMIT-0 pin 13: golden narrow/widen/F2I cross-checked "
                    "against independent oracles BEFORE golden becomes sole "
                    "authority (guards the identically-wrong-shared-function "
                    "hole)",
            "oracles": ["numpy float16 (f16 widen exhaustive, narrow windows "
                        "+ 2^22 random)",
                        "ml_dtypes bfloat16 " + ml_dtypes.__version__ +
                        " (bf16 widen exhaustive, narrow 2^22 random)",
                        "numpy int64->float32 hardware cvt (I2F random)",
                        "float64 rint/clip composition (F2I random)",
                        "float64 frexp/rint value-level narrow formulation "
                        "(every narrow point, unmasked)"],
            "documented_divergences_masked": {
                "ftz_at_f16_destination": "(0, 2^-14) result band — golden "
                    "flushes (pin 5, documented GPU divergence), numpy "
                    "preserves f16 subnormals; masked rows asserted to flush "
                    "to signed zero on the golden side",
                "nan_payloads": "golden canonicalizes every NaN (pins 1-2); "
                    "oracles preserve/vary payloads; masked rows asserted "
                    "NaN on BOTH sides",
                "daz_bf16_narrow_inputs": "fp32-subnormal sources — golden "
                    "DAZ-flushes (pin 7); ml_dtypes rounds the "
                    "0x007FFF80-0x007FFFFF sliver up to bf16 min-normal "
                    "0x0080 (asserted: 128/128, proving DAZ is observable "
                    "and live)",
                "bf16_subnormal_widen": "254 inputs — golden flushes to "
                    "signed zero (pin 6); oracle asserted to land in "
                    "fp32-subnormal space (proving the splice rationale)",
            },
        },
        "pass": all_ok,
    }
    REPORT.write_text(json.dumps(report, indent=1) + "\n")
    print(f"wrote {REPORT}")
    if not all_ok:
        print("FAIL: at least one sweep missed its budget", file=sys.stderr)
        return 1
    print("fp_release_sweep: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
