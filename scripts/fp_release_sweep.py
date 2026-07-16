#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""v1.8.0c — fp golden-model release sweeps (model-only; the RTL lockstep
sample and scale-covariance property test land with the PE_Core COMMIT F).

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
import sys
from fractions import Fraction
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import golden_fp32 as g  # noqa: E402

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
    import struct
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


def main():
    full = os.environ.get("WT_FULL_FP_SWEEP") == "1"
    ok1, rep1 = sweep_frsqrt()
    ok2, rep2 = sweep_fexp2(full)
    ok3, rep3 = sweep_fdiv()
    report = {
        "_doc": "v1.8.0c fp golden-model validation — generated by "
                "scripts/fp_release_sweep.py against the SHIPPED "
                "include/generated fp artifacts (model-only sweeps; RTL "
                "lockstep + scale-covariance tests land with COMMIT F).",
        "frsqrt32": rep1,
        "fexp2_32": rep2,
        "fdiv": rep3,
        "pass": ok1 and ok2 and ok3,
    }
    REPORT.write_text(json.dumps(report, indent=1) + "\n")
    print(f"wrote {REPORT}")
    if not (ok1 and ok2 and ok3):
        print("FAIL: at least one sweep missed its budget", file=sys.stderr)
        return 1
    print("fp_release_sweep: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
