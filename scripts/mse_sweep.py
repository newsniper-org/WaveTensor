#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""v1.8.0e norm MSE release-gate harness (0e1) — the REPAIRED harness of
the "hybrid-minimal (repaired)" design, model-only (COMMIT 1,
golden-before-RTL): proves at MODEL level that the MSE contract is
achievable BEFORE any RTL exists, by running the FULL rewritten RMSNORM
macro chain golden model (golden_fp32.rmsnorm_chain_0e — L2SQ -> fp
insert -> 0x6B gamma stage -> DEQUANT bf16 tail) against the exact
reference. The identical harness re-runs against TB captures when the
0e1 RTL lands.

The seven harness repairs, all implemented here:
  eps-INCLUSIVE exact reference   exact_i = gamma_i * x_i /
      sqrt(mean(x^2) + eps), mpmath 192-bit — eps is INSIDE the sqrt of
      the reference, never dropped (the old Q8.8-absorption rationale is
      retired; the assembler eps >= 2^-13 guard itself is retained).
  ratio criterion                 per-tensor MSE(chain, exact) /
      MSE(RNE_bf16(exact), exact) <= 1.05, where the denominator is the
      bf16 DTYPE FLOOR computed by exact-value RNE (criterion 3 is
      scoped to narrowed output dtypes — bf16 — and to the RMSNORM macro
      end-to-end incl. per-lane gamma).
  denominator-floor rule          rows whose empirical bf16 floor is ~0
      (exact_i (nearly) exactly representable) fall back to an ABSOLUTE
      criterion — chain MSE <= the generic uniform-residual floor
      mean((ulp/2)^2)/3 — instead of the ratio (no 0/0, no vacuous
      pass). Exercised by directed representable rows.
  pinned tensor generation        int4 LANES with a per-tensor
      power-of-two fp32 scale swept across binades 2^-8..2^8 against
      FIXED int-lane distributions (x_real = x_int * 2^e). A real-value
      data-binade sweep alone quantizes to all-zero int rows — pinned
      away. The scale folds into the chain exactly (exponent shifts:
      4^e into the 1/N producer constant, 2^e into the DEQUANT scale).
  gamma-variation tensors         per-lane random int4 gamma INCLUDING
      sign flips — the tensor class that catches any broadcast-gamma
      (s_c = s * gamma_c) implementation, the fatal refutation the 0x6B
      repair exists to close.
  int-lane tensor families        Gaussian, lognormal heavy-tail,
      outlier-injected, near-constant, eps-boundary rows (mean(x^2)
      driven at/below eps across the binade sweep).
  round-once enforcement          the MSE ratio is PROVABLY BLIND to
      round-once-vs-double-round (the defect moves single outputs by
      <= 1 ulp on measure-zero cells), so rounding definition (a) is
      enforced by golden/TB BIT-EQUIVALENCE on directed tie vectors:
      this module constructs the discriminator cells (a double-rounding
      RNE24-then-RNE8 twin provably differs on every one) and the
      exact-tie cells, and asserts micro == ref == exact oracle on all
      of them. fp_release_sweep.py imports the same generators for the
      DEQUANT directed sweep.

BLOCKED policy: if any tensor misses its criterion, main() exits
nonzero and prints the offending tensors WITH THE NUMBERS — the 0e1
release is blocked, per the locked gate.

Deterministic: fixed seeds, no timestamps. Standalone: python3
scripts/mse_sweep.py. The machine-readable section is embedded in
include/generated/fp_validation_report.json by fp_release_sweep.py
(which imports run_gate())."""

import math
import random
import sys
from fractions import Fraction
from pathlib import Path

import mpmath

sys.path.insert(0, str(Path(__file__).resolve().parent))
import golden_fp32 as g  # noqa: E402

RATIO_GATE = 1.05
BINADES = list(range(-8, 9))          # per-tensor scale 2^-8 .. 2^8
GAMMA_K = 3                           # pinned harness convention: Q1.3 gamma
EPS_DEFAULT = g.RMSNORM_EPS_DEFAULT_BITS
_MPPREC = 192


# ---------------------------------------------------------------------------
# exact-value bf16 RNE (the dtype-floor authority) + mpf/Fraction bridges
# ---------------------------------------------------------------------------


def _bf16_rne_from_frac(a):
    """RNE of a POSITIVE exact Fraction to bf16 magnitude bits: one
    8-bit round in the unbounded-exponent domain, overflow -> Inf.
    Value-level (Fraction) formulation — no bit tricks shared with
    ref_narrow_f32's disjoint-round/sticky path. Harness domain never
    reaches the subnormal band (asserted)."""
    assert a > 0
    num, den = a.numerator, a.denominator
    e = g._binade(num, den)
    sh = 7 - e
    m = g._rne_rat(num << sh, den) if sh >= 0 else g._rne_rat(num, den << -sh)
    if m == (1 << 8):
        m = 1 << 7
        e += 1
    if e > 127:
        return g.BF16_PINF
    assert e >= -126, "harness domain never reaches bf16 subnormals"
    return ((e + 127) << 7) | (m - (1 << 7))


def _mpf_to_frac(x):
    """Exact Fraction of an mpmath mpf (mpf values are dyadic)."""
    sign, man, expo, _ = x._mpf_
    if man == 0:
        assert x == 0
        return Fraction(0)
    f = Fraction(man, 1) * Fraction(2) ** expo
    return -f if sign else f


def _frac_to_mpf(f):
    return mpmath.mpf(f.numerator) / mpmath.mpf(f.denominator)


# ---------------------------------------------------------------------------
# round-once tie vectors (shared with fp_release_sweep's DEQUANT sweep)
# ---------------------------------------------------------------------------


def dequant_double_round(field, scale, dtype):
    """The FORBIDDEN rounding definition (b): RNE the exact product to
    fp32 first (ref_mul of the exact int injection), then narrow to
    bf16 — TWO roundings. Exists only to prove the discriminator cells
    have power; specials rows coincide with ref by construction."""
    return g.ref_narrow_f32(g.ref_mul(g.ref_i2f(field, dtype), scale),
                            g.DT_BF16)


def dequant_tie_cells():
    """Constructive, exactly-verified directed cells (field, scale_bits,
    dtype), split (discriminators, exact_ties):

    DISCRIMINATORS — the exact product P sits strictly on one side of a
    bf16 rounding midpoint M*2^d (M = (Q<<16)|0x8000 in the 24-bit
    domain) but within one 24-bit-RNE step of it, so a first-pass RNE24
    lands EXACTLY ON the midpoint and the second rounding resolves the
    manufactured tie to even — +-1 ulp off round-once definition (a):
      below cell  P = M*2^d - delta (0 < delta < 2^(d-1)): direct -> Q
                  (down), double-round -> Q+1 — discriminates iff Q odd;
      above cell  P = M*2^d + delta: direct -> Q+1 (up), double-round
                  -> Q — discriminates iff Q even.
    delta is forced by P ≡ 0 (mod |k|) so the scale significand
    m_s = P/|k| is an integer in [2^23, 2^24).

    EXACT TIES — P = M*2^d exactly (round bit 1, sticky 0): pins
    ties-to-even in ref/micro; double-round coincides (no pass-1 error).

    A few cells are re-based to extreme scale exponents (the rounding
    pattern is exponent-invariant until overflow)."""
    disc, ties = [], []
    for dtype, ks in ((g.DT_INT4, (3, 5, 7, -3, -5, -7)),
                      (g.DT_INT8, (3, 5, 7, 11, 25, 89, 127,
                                   -3, -89, -127))):
        mask = 0xF if dtype == g.DT_INT4 else 0xFF
        for k in ks:
            ka = abs(k)
            got_dn = got_up = got_tie = 0
            for q in range(128, 256):
                m_mid = (q << 16) | 0x8000
                for d in (ka.bit_length() - 1, ka.bit_length()):
                    if d < 1:
                        continue
                    base = m_mid << d
                    half = 1 << (d - 1)
                    delta = base % ka
                    if (q & 1) and 1 <= delta < half and got_dn < 3:
                        ms = (base - delta) // ka
                        if (1 << 23) <= ms < (1 << 24):
                            disc.append((k & mask,
                                         0x3F800000 | (ms - (1 << 23)), dtype))
                            got_dn += 1
                    delta2 = (-base) % ka
                    if not (q & 1) and 1 <= delta2 < half and got_up < 3:
                        ms = (base + delta2) // ka
                        if (1 << 23) <= ms < (1 << 24):
                            disc.append((k & mask,
                                         0x3F800000 | (ms - (1 << 23)), dtype))
                            got_up += 1
                    if delta == 0 and got_tie < 3:
                        ms = base // ka
                        if (1 << 23) <= ms < (1 << 24):
                            ties.append((k & mask,
                                         0x3F800000 | (ms - (1 << 23)), dtype))
                            got_tie += 1
    # exponent-rebased variants (never overflow: e_s -120/+90, |k| <= 127)
    disc += [(f, g.f32_exp_shift(s, dk), dt)
             for (f, s, dt) in disc[:4] for dk in (-120, 90)]
    ties += [(f, g.f32_exp_shift(s, dk), dt)
             for (f, s, dt) in ties[:2] for dk in (-120, 90)]
    return disc, ties


def dequant_exact_oracle(field, scale, dtype):
    """INDEPENDENT exact-Fraction value-level DEQUANT oracle: exact
    product, one RNE to bf16 via _bf16_rne_from_frac. Specials rows are
    the pinned semantics (shared by definition, not by code path)."""
    k = g._i2f_operand(field, dtype)
    s_sign, s_kind, s_val = g.decode(scale)
    sign = (1 if k < 0 else 0) ^ s_sign
    if s_kind == "nan":
        return g.BF16_QNAN
    if s_kind == "inf":
        return g.BF16_QNAN if k == 0 else (sign << 15) | g.BF16_PINF
    if s_kind == "zero" or k == 0:
        return sign << 15
    return (sign << 15) | _bf16_rne_from_frac(abs(k * s_val))


def check_round_once_cells():
    """Golden bit-equivalence over the tie vectors (the TB re-runs the
    same cells against RTL): ref == micro == exact oracle on ALL cells;
    the double-round twin differs on EVERY discriminator (power proof)
    and coincides on exact ties."""
    disc, ties = dequant_tie_cells()
    bad = caught = tie_bad = 0
    for f, s, dt in disc:
        r = g.ref_dequant_lane(f, s, dt)
        if (g.micro_dequant_lane(f, s, dt) != r
                or dequant_exact_oracle(f, s, dt) != r):
            bad += 1
        if dequant_double_round(f, s, dt) != r:
            caught += 1
    for f, s, dt in ties:
        r = g.ref_dequant_lane(f, s, dt)
        if (g.micro_dequant_lane(f, s, dt) != r
                or dequant_exact_oracle(f, s, dt) != r
                or dequant_double_round(f, s, dt) != r):
            tie_bad += 1
    return {
        "discriminators": len(disc),
        "discriminators_bad": bad,
        "double_round_caught": caught,
        "exact_ties": len(ties),
        "exact_ties_bad": tie_bad,
        "note": "MSE ratio is provably blind to round-once-vs-double-"
                "round; these cells are the enforcement point (golden "
                "now, golden/TB bit-equivalence at the 0e1 RTL commit)",
    }, bad == 0 and tie_bad == 0 and caught == len(disc)


# ---------------------------------------------------------------------------
# tensor families (pinned int4-lane generation)
# ---------------------------------------------------------------------------


def _clip4(v):
    return max(-8, min(7, int(v)))


def _fields(vals):
    return [v & 0xF for v in vals]


def _gen_tensors():
    """Yields (family, x_fields, gamma_fields, k, eps_bits, e, n).
    Deterministic (one fixed-seed generator, consumed in a fixed order)."""
    rng = random.Random(0xE0E5)

    def rnd_gamma(n):
        return _fields([rng.randint(-8, 7) for _ in range(n)])

    for n in (16, 32):
        for e in BINADES:
            x = _fields([_clip4(round(rng.gauss(0, 2.5))) for _ in range(n)])
            yield ("gaussian", x, rnd_gamma(n), GAMMA_K, EPS_DEFAULT, e, n)

            v = [_clip4(rng.choice((-1, 1)) * round(rng.lognormvariate(0.0, 0.8)))
                 for _ in range(n)]
            yield ("lognormal_heavy_tail", _fields(v), rnd_gamma(n),
                   GAMMA_K, EPS_DEFAULT, e, n)

            v = [_clip4(round(rng.gauss(0, 1.0))) for _ in range(n)]
            for pos in rng.sample(range(n), 2):
                v[pos] = rng.choice((-8, 7))
            yield ("outlier_injected", _fields(v), rnd_gamma(n),
                   GAMMA_K, EPS_DEFAULT, e, n)

            c = rng.choice((2, 3, -3, 5, -6))
            v = [c] * n
            v[rng.randrange(n)] = _clip4(c + 1)
            yield ("near_constant", _fields(v), rnd_gamma(n),
                   GAMMA_K, EPS_DEFAULT, e, n)

    # per-lane GAMMA-VARIATION tensors — the broadcast-gamma catcher:
    # every variant has lane-to-lane gamma structure incl. sign flips
    ramp16 = list(range(-8, 8))
    variants = [
        [7 if i % 2 == 0 else -7 for i in range(32)],
        (ramp16 * 2),
        [(-1) ** i * ((i % 8) + 1) for i in range(32)],
        [-8] * 32,
        [rng.randint(-8, 7) if i % 3 else 0 for i in range(32)],
        [-v for v in ramp16 * 2],
    ]
    xg = [_clip4(round(rng.gauss(0, 2.5))) for _ in range(32)]
    for n in (16, 32):
        for e in (-8, 0, 8):
            for k in (GAMMA_K, 0):
                for gv in variants:
                    yield ("gamma_variation", _fields(xg[:n]),
                           _fields(gv[:n]), k, EPS_DEFAULT, e, n)

    # eps-boundary rows: mean(x^2)*4^e driven at/below eps
    eps_set = (EPS_DEFAULT, 0x3C800000, 0x3F800000, 0x42800000)  # 2^-13..64
    for n in (16, 32):
        for e in (-8, 0, 8):
            for eps in eps_set:
                for nz in (0, 1, 2, 4):
                    v = [0] * n
                    for pos in rng.sample(range(n), nz):
                        v[pos] = rng.choice((-2, -1, 1, 2))
                    yield ("eps_boundary", _fields(v), rnd_gamma(n),
                           GAMMA_K, eps, e, n)

    # directed representable rows — exercise the denominator-floor rule
    # (exact_i exactly bf16-representable -> empirical floor == 0)
    alt = _fields([1 if i % 2 == 0 else -1 for i in range(16)])
    two = _fields([2 if i % 2 == 0 else -2 for i in range(16)])
    grmp = _fields(ramp16)
    yield ("floor_directed", alt, grmp, 3, 0x40400000, 0, 16)   # rms = 2
    yield ("floor_directed", two, grmp, 3, 0x41400000, 0, 16)   # rms = 4
    yield ("floor_directed", alt * 2, grmp * 2, 3, 0x40400000, 0, 32)
    yield ("floor_directed", _fields([0] * 16), grmp, 3, EPS_DEFAULT, 0, 16)


# ---------------------------------------------------------------------------
# per-tensor evaluation against the eps-inclusive exact reference
# ---------------------------------------------------------------------------


def _eval_tensor(family, x, gam, k, eps_bits, e, n):
    y, _ = g.rmsnorm_chain_0e(x, gam, gamma_frac_bits=k,
                              eps_bits=eps_bits, scale_exp=e)
    with mpmath.workprec(_MPPREC):
        eps_v = g.bits_to_frac(eps_bits)
        xv = [g._i2f_operand(f, g.DT_INT4) for f in x]
        gv = [g._i2f_operand(f, g.DT_INT4) for f in gam]
        ms = (Fraction(sum(v * v for v in xv), n) * Fraction(4) ** e) + eps_v
        rt = mpmath.sqrt(_frac_to_mpf(ms))       # eps-INCLUSIVE reference
        num = den = floor_ref = ref_pow = mpmath.mpf(0)
        for i in range(n):
            gx = Fraction(gv[i], 1 << k) * Fraction(xv[i]) * Fraction(2) ** e
            exact = _frac_to_mpf(gx) / rt if gx else mpmath.mpf(0)
            num += (_frac_to_mpf(g.bf16_to_frac(y[i])) - exact) ** 2
            if exact != 0:
                ex_frac = _mpf_to_frac(exact)
                mag = g.bf16_to_frac(_bf16_rne_from_frac(abs(ex_frac)))
                den += (_frac_to_mpf(mag if ex_frac > 0 else -mag)
                        - exact) ** 2
                _, be = mpmath.frexp(exact)
                floor_ref += mpmath.mpf(4) ** (be - 1 - 8) / 3
                ref_pow += exact ** 2
        num_f = float(num / n)
        den_f = float(den / n)
        flo_f = float(floor_ref / n)
        pow_f = float(ref_pow / n)
    if den_f > 0.05 * flo_f and den_f > 0.0:
        ratio = num_f / den_f
        ok = ratio <= RATIO_GATE
        mode = "ratio"
    else:
        ratio = None
        ok = (num_f <= flo_f) if flo_f > 0.0 else (num_f == 0.0)
        mode = "floor"
    rel_rms = math.sqrt(num_f / pow_f) if pow_f > 0.0 else 0.0
    return {"family": family, "n": n, "binade": e, "k": k,
            "eps_bits": "0x%08X" % eps_bits, "mode": mode,
            "ratio": ratio, "mse_chain": num_f, "mse_bf16_floor": den_f,
            "generic_floor": flo_f, "rel_rms": rel_rms, "pass": ok}


def run_gate():
    """Full release-gate sweep. Returns (ok, machine-readable report)."""
    print("[mse gate 0e1] RMSNORM chain vs eps-inclusive mpmath exact "
          "reference...")
    tie_rep, tie_ok = check_round_once_cells()
    rows = [_eval_tensor(*t) for t in _gen_tensors()]
    fams = {}
    worst = None
    rels = []
    failures = []
    for i, r in enumerate(rows):
        f = fams.setdefault(r["family"], {
            "tensors": 0, "ratio_rows": 0, "floor_rows": 0,
            "worst_ratio": 0.0, "all_pass": True})
        f["tensors"] += 1
        rels.append(r["rel_rms"])
        if r["mode"] == "ratio":
            f["ratio_rows"] += 1
            f["worst_ratio"] = max(f["worst_ratio"], r["ratio"])
            if worst is None or r["ratio"] > worst[1]:
                worst = (i, r["ratio"])
        else:
            f["floor_rows"] += 1
        if not r["pass"]:
            f["all_pass"] = False
            failures.append(r)
    rels.sort()
    ok = tie_ok and not failures
    worst_row = dict(rows[worst[0]]) if worst else None
    n_floor = sum(f["floor_rows"] for f in fams.values())
    for name, f in sorted(fams.items()):
        print(f"  {name}: {f['tensors']} tensors, worst ratio "
              f"{f['worst_ratio']:.9f}, floor-rule rows {f['floor_rows']}, "
              f"pass={f['all_pass']}")
    print(f"  WORST RATIO {worst[1]:.9f} (gate {RATIO_GATE}), "
          f"chain rel-RMS worst {rels[-1]:.3e} / median "
          f"{rels[len(rels) // 2]:.3e}, round-once cells "
          f"{tie_rep['discriminators']} disc (caught "
          f"{tie_rep['double_round_caught']}) + {tie_rep['exact_ties']} ties")
    rep = {
        "gate": "per-tensor MSE(chain, exact) / MSE(RNE_bf16(exact), "
                "exact) <= 1.05 (criterion 3, scoped bf16-out + RMSNORM "
                "end-to-end incl. per-lane gamma)",
        "reference": "mpmath %d-bit exact, eps-INCLUSIVE: exact_i = "
                     "gamma_i * x_i / sqrt(mean(x^2) + eps)" % _MPPREC,
        "chain": "golden rmsnorm_chain_0e: L2SQ -> I2F -> FS_MUL(1/N "
                 "fold) -> FS_ADD(eps) -> FRSQRT32 -> exact exponent "
                 "folds -> 0x6B -> DEQUANT int8-16 bf16 (round-once)",
        "tensor_generation": "pinned int4 lanes x per-tensor power-of-"
                             "two fp32 scale, binades 2^-8..2^8; fixed "
                             "int-lane distributions (a data-binade "
                             "sweep alone quantizes to all-zero rows)",
        "gamma_convention": "int4 gamma, implicit 2^-k (k=%d pinned, "
                            "k=0 variants swept), folded into the "
                            "DEQUANT scale as an exact exponent shift"
                            % GAMMA_K,
        "tensors": len(rows),
        "families": {k: v for k, v in sorted(fams.items())},
        "worst_ratio": worst[1],
        "worst_ratio_tensor": worst_row,
        "ratio_gate": RATIO_GATE,
        "denominator_floor_rule": "rows with empirical bf16 floor < 5% "
                                  "of the generic uniform-residual floor "
                                  "mean((ulp/2)^2)/3 use the absolute "
                                  "criterion MSE(chain) <= generic floor",
        "floor_fallback_rows": n_floor,
        "chain_rel_rms_worst": rels[-1],
        "chain_rel_rms_median": rels[len(rels) // 2],
        "round_once_enforcement": tie_rep,
        "failures": [dict(f) for f in failures[:16]],
        "pass": ok,
    }
    return ok, rep


def main():
    ok, rep = run_gate()
    if not ok:
        print("BLOCKED: MSE release gate failed — offending tensors:",
              file=sys.stderr)
        for f in rep["failures"]:
            print("  %r" % (f,), file=sys.stderr)
        return 1
    print("mse_sweep: PASS (worst ratio %.9f <= %s)"
          % (rep["worst_ratio"], RATIO_GATE))
    return 0


if __name__ == "__main__":
    sys.exit(main())
