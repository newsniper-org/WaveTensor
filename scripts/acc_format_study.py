#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""v2.0 wave-step-atomic accumulation (Option 3) — COMMIT-0 design-study
consolidation. Regenerates, with FIXED seeds, every number the COMMIT-0
accumulation spec cites, consolidating the session's /tmp harnesses
(rne_tree_exp / acc48_exp / acc48_adversarial / posit_exp / hybrid_quant)
into one reproducible repo script.

Experiment set (all Ns and seeds recorded in the report):
 (a) RTO-tree divergence: deterministic realizable-leaf counterexample
     [1x1, 2^-30 x 2^-30, 1x(-1)] and its width-q ladder (48/50/64/128/
     254/368 all diverge), f16-leaf rows, plus fixed-seed random families
     (cancellation / tie-straddle / random-wide) at q in {48, 50}. Every
     trial also asserts the constructive Option-3 identity: exact
     accumulate + RTO-48 + PACK_FINAL RNE == exact + single RNE.
 (b) Single-value extraction theorem RNE_24(RTO_q(x)) == RNE_24(x):
     deterministic tie x = 1+2^-24+2^-60 plus a 200k random sweep —
     q = 25 fails hard (Boldo-Melquiond threshold is q >= p+2 = 26),
     q in {26, 48, 50} give zero mismatches. Plus the (m,e)-domain
     composition twin showing RNE-48 (not RTO-48) double-rounds.
 (c) Bank-chain divergence vs true single-rounding (B): per-step RNE-24 /
     per-step RTO-48 / Option-3 (exact 32-term wave dot, one RTO-48 store
     per wave) on S1/S4/S5-band product streams at K in {32, 1024}.
 (d) Posit rows: posit64 es in {2, 3, 5} chains on the same streams
     (incl. the 2^230 band) and the deterministic adversarial families
     (incl. F2 sticky-tie, which every tested posit loses); effective-
     significand taper table (exact regime arithmetic, no sampling);
     quire width arithmetic.
 (e) Input-noise dominance: paired per-dot comparison of bf16 input-
     quantization noise vs the accumulation error of BOTH schedules
     (per-step RNE tree+bank vs Option 3) on gauss/relu/gradcancel
     streams, K in {32, 256, 4096}.
 (f) Exact-integer lattice width arithmetic: 32 bf16/f16 products + carry
     -> 528-bit (bf16) / 86-bit (f16) two's-complement span; the Kulisch
     safe-tree-width check (q = 527 never diverges on the cancellation
     family); ACC-bank state arithmetic.

Ground truth everywhere is EXACT arithmetic (python int / Fraction);
fp32 semantics (RNE, FTZ-after-round, ulp convention) are imported from
scripts/golden_fp32.py, never duplicated.

Writes include/generated/acc_format_study_report.json (machine-readable,
the fp_validation_report.json pattern — cited by the COMMIT-0 spec).
Deterministic: fixed integer seeds only (the session harnesses partly
used salted-hash seeds — a recorded caveat this script exists to close),
no timestamps; the report is byte-identical across runs.

Terminology note: rounding-event counts are per wave-step (dispatch);
the kickoff memo's "(A) = 6 RNE per dot" figure confused path DEPTH
(5 tree levels + bank) with EVENT count (31 tree nodes + 1 bank = 32) —
the corrected arithmetic is in the rounding_events section.
"""

import json
import math
import random
import statistics
import sys
import time
from fractions import Fraction
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
REPORT = REPO / "include" / "generated" / "acc_format_study_report.json"
sys.path.insert(0, str(Path(__file__).resolve().parent))

from golden_fp32 import (_binade, _rne_shift, _rto, bits_to_frac,  # noqa: E402
                         pack_rne_ftz, ulp)

TWO = Fraction(2)
P24, P48 = 24, 48
GROUP = 32          # one dispatch = 32 lanes (canonical wave-dot width)

# ---------------------------------------------------------------------------
# FIXED seeds. Three are kept bit-identical to the session harnesses whose
# outputs were already cross-checked (theorem_sweep / composition_me /
# kulisch_check); the rest replace the session's salted-hash seeds.
# ---------------------------------------------------------------------------
SEEDS = {
    "theorem_sweep": 20260815,      # /tmp/rne_tree_exp.py PART 1 (kept)
    "composition_me": 42,           # /tmp/acc48_adversarial.py tail (kept)
    "kulisch_check": 7,             # /tmp/rne_tree_exp.py PART 0 (kept)
    "posit_selftest": 5,            # /tmp/posit_exp.py selftest (kept)
    "fam_cancellation": 0xACC01,
    "fam_tie_straddle": 0xACC02,
    "fam_rand_wide": 0xACC03,
    "stream_S1_K32": 0xACC11,
    "stream_S1_K1024": 0xACC12,
    "stream_S4_K32": 0xACC13,
    "stream_S4_K1024": 0xACC14,
    "stream_S5_K32": 0xACC15,
    "stream_S5_K1024": 0xACC16,
    "noise_gauss": 0xACC21,
    "noise_relu": 0xACC22,
    "noise_gradcancel": 0xACC23,    # per-K seed = base + K (constant arith)
}


def hexbits(b):
    return "0x%08X" % b


# ===========================================================================
# (m, e) exact integer machinery — value = m * 2^e, m any-signed python int.
# All inputs are dyadic rationals, so this is exact arithmetic (same ground
# truth as Fraction, faster). Rounding cores reuse golden_fp32._rto /
# _rne_shift so no rounding logic is duplicated.
# ===========================================================================


def add_me(am, ae, bm, be):
    if am == 0:
        return bm, be
    if bm == 0:
        return am, ae
    if ae >= be:
        return (am << (ae - be)) + bm, be
    return am + (bm << (be - ae)), ae


def veq_me(am, ae, bm, be):
    """Exact value equality of m*2^e pairs."""
    if am == 0 or bm == 0:
        return am == bm
    if ae >= be:
        return (am << (ae - be)) == bm
    return am == (bm << (be - ae))


def rto_me(m, e, p):
    """Round-to-odd |significand| to p bits. Exact if it already fits."""
    if m == 0:
        return 0, 0
    a = -m if m < 0 else m
    sh = a.bit_length() - p
    if sh <= 0:
        return m, e
    q = _rto(a, sh)
    return (-q if m < 0 else q), e + sh


def rne_me(m, e, p):
    """RNE |significand| to p bits (ties to even). Exact if it fits."""
    if m == 0:
        return 0, 0
    a = -m if m < 0 else m
    sh = a.bit_length() - p
    if sh <= 0:
        return m, e
    q = _rne_shift(a, sh)
    if q.bit_length() > p:          # carry to 2^p: exact halving
        q >>= 1
        e += 1
    return (-q if m < 0 else q), e + sh


def ulp_exp_me(m, e):
    """log2(ulp24) of nonzero m*2^e, Goldberg convention (smaller binade
    on an exact binade edge) — matches golden_fp32.ulp."""
    a = -m if m < 0 else m
    bl = a.bit_length()
    be = e + bl - 1
    if a == (1 << (bl - 1)):
        be -= 1
    return be - 23


def me_float(m, e):
    """|m| * 2^e as a float, overflow -> inf (robust, no int->float blowup)."""
    a = -m if m < 0 else m
    if a == 0:
        return 0.0
    sh = max(0, a.bit_length() - 53)
    try:
        return math.ldexp(float(a >> sh), e + sh)
    except OverflowError:
        return float("inf")


def ulp_delta_me(cm, ce, tm, te):
    """|chain - true| in ulp24 of the true result (inf on zero-class)."""
    if tm == 0:
        return float("inf") if cm != 0 else 0.0
    dm, de = add_me(cm, ce, -tm, te)
    if dm == 0:
        return 0.0
    return me_float(dm, de - ulp_exp_me(tm, te))


# ===========================================================================
# Fraction-domain helpers (the RTO-tree study runs on golden fp32 packing)
# ===========================================================================


def pack_signed(v):
    """fp32 bits of exact Fraction v: single RNE (unbounded) + FTZ/overflow.
    Exact zero packs +0 (matches the wide_zero / PACK_FINAL contract)."""
    if v == 0:
        return 0
    return pack_rne_ftz(0 if v > 0 else 1, abs(v))


def rto_q(v, q):
    """Round-to-odd of exact Fraction v to a q-bit significand, unbounded
    exponent (PACK_WIDE semantics generalized to width q)."""
    if v == 0:
        return v
    s = -1 if v < 0 else 1
    a = abs(v)
    num, den = a.numerator, a.denominator
    e = _binade(num, den)               # 2^e <= a < 2^(e+1)
    sh = (q - 1) - e
    if sh >= 0:
        fl, rem = divmod(num << sh, den)
    else:
        fl, rem = divmod(num, den << -sh)
    if rem:
        fl |= 1                         # sticky-jam: LSB odd, no carry
    return s * Fraction(fl) * TWO ** (e - q + 1)


def rne_fp32_val(v):
    """Value after a per-step fp32 RNE+FTZ (schedule-A tree node)."""
    return bits_to_frac(pack_signed(v))


def tree_fold(leaves, node, root):
    """Canonical balanced 5-level 32-leaf tree. `node` rounds the exact
    pairwise sum at levels 1..4; `root` packs the exact level-5 sum."""
    lv = list(leaves)
    assert len(lv) == 32
    while len(lv) > 2:
        lv = [node(lv[i] + lv[i + 1]) for i in range(0, len(lv), 2)]
    return root(lv[0] + lv[1])


def run_variants(leaves):
    """Returns (exact, bits_A, bits_rto48tree, bits_rto50tree, bits_trueB).
    ASSERTS the constructive Option-3 identity on every trial: exact
    accumulate + RTO-48 + PACK_FINAL RNE == exact + single RNE."""
    exact = sum(leaves, Fraction(0))
    bits_iv = pack_signed(exact)                            # true (B)
    bits_a = tree_fold(leaves, rne_fp32_val, pack_signed)   # schedule A
    bits_48 = tree_fold(leaves, lambda s: rto_q(s, 48), pack_signed)
    bits_50 = tree_fold(leaves, lambda s: rto_q(s, 50), pack_signed)
    bits_v = pack_signed(rto_q(exact, 48))
    assert bits_v == bits_iv, (leaves, bits_v, bits_iv)
    return exact, bits_a, bits_48, bits_50, bits_iv


def bf16_prod(rng, elo, ehi):
    """Exact bf16 x bf16 product: 16-bit sig class, wide exponent."""
    s16 = rng.randrange(128, 256) * rng.randrange(128, 256)  # [2^14, 2^16)
    E = rng.randint(elo, ehi) + rng.randint(elo, ehi)        # Ea + Eb
    sgn = rng.choice((1, -1))
    return sgn * Fraction(s16) * TWO ** (E - 14)


def fam_cancel(rng):
    """Catastrophic cancellation: X and -X in different subtrees, dust
    Delta binades below X paired with X BEFORE the cancellation."""
    X = abs(bf16_prod(rng, -20, 20))
    delta = rng.randint(45, 95)
    e = _binade(X.numerator, X.denominator)
    dust = bf16_prod(rng, (e - delta) // 2 - 1, (e - delta) // 2 + 1)
    leaves = [Fraction(0)] * 32
    leaves[0], leaves[1] = X, dust        # jam happens here (level 1)
    leaves[2] = -X                        # cancellation at level 2
    for i in rng.sample(range(4, 32), 3):
        leaves[i] = bf16_prod(rng, (e - delta) // 2 - 2, (e - delta) // 2)
    return leaves


def fam_tie(rng):
    """Exact sum near a 24-bit RNE tie, decided by bits below bit 48 that
    are spread across several leaves (multi-node jam interaction)."""
    leaves = [Fraction(0)] * 32
    leaves[0] = Fraction(1)                       # bf16 product 1*1
    leaves[1] = TWO ** -24                        # exactly half-ulp24 of 1
    for i in range(2, 2 + rng.randint(2, 6)):     # signed dust 2^-45..2^-62
        t = rng.randint(-62, -45)
        leaves[i] = bf16_prod(rng, (t // 2) - 1, (t // 2) + 1)
    rng.shuffle(leaves)
    return leaves


def fam_wide(rng):
    """Random bf16 products over the full exponent range."""
    return [bf16_prod(rng, -126, 40) for _ in range(32)]


# ===========================================================================
# posit (Type III unum) codec — exact-arithmetic, encoding-space rounding
# (nearest, ties-to-even pattern; never rounds a nonzero value to zero/NaR;
# saturates at minpos/maxpos). Self-tested below.
# ===========================================================================


def posit_decode(q, n, es):
    """Decode positive posit body integer q (0 < q < 2^(n-1)) to exact m*2^e."""
    W = n - 1
    b0 = (q >> (W - 1)) & 1
    r = 0
    i = W - 1
    while i >= 0 and ((q >> i) & 1) == b0:
        r += 1
        i -= 1
    k = (r - 1) if b0 else -r
    rest = W - r - 1                    # bits after terminator (may be -1)
    if rest < 0:
        rest = 0
    body_rest = q & ((1 << rest) - 1)
    take = min(es, rest)
    ef = (body_rest >> (rest - take)) << (es - take) if take else 0
    fb = rest - take
    f = body_rest & ((1 << fb) - 1)
    E = k * (1 << es) + ef
    return (1 << fb) + f, E - fb


def posit_round(m, e, n, es):
    """Round exact value m*2^e to nearest posit(n,es), ties to even pattern.
    Returns exact (m', e'). Zero -> zero. Saturates at minpos/maxpos."""
    if m == 0:
        return 0, 0
    neg = m < 0
    a = -m if neg else m
    W = n - 1
    bl = a.bit_length()
    E = e + bl - 1                      # binade
    twoes = 1 << es
    k = E // twoes                      # floor
    ef = E - k * twoes                  # exponent field in [0, 2^es)
    if k >= 0:
        m_len = k + 1
        regime = (1 << (m_len + 1)) - 2     # ones + terminating zero
    else:
        m_len = -k
        regime = 1                          # zeros + terminating one
    shift_r = W - (m_len + 1)               # scale of the regime field
    shift_f = shift_r - es                  # scale of the (ef + F) term
    num = (ef << (bl - 1)) + (a - (1 << (bl - 1)))
    t = shift_f - (bl - 1)
    Q = -min(shift_r, t, 0)
    if t + Q >= 0:
        X = (regime << (shift_r + Q)) + (num << (t + Q))
    else:                                   # unreachable with this Q, kept
        X = (regime << (shift_r + Q)) + (num >> -(t + Q))
    if Q == 0:
        q = X
    else:
        q = X >> Q
        rem = X & ((1 << Q) - 1)
        half = 1 << (Q - 1)
        if rem > half or (rem == half and (q & 1)):
            q += 1
    if q < 1:
        q = 1                               # never round to zero
    if q > (1 << W) - 1:
        q = (1 << W) - 1                    # saturate at maxpos, never NaR
    dm, de = posit_decode(q, n, es)
    return (-dm if neg else dm), de


def posit_sig_width(E, n, es):
    """Effective significand bits (incl. hidden) of posit(n,es) at binade E."""
    k = E // (1 << es)
    fb = (n - 3 - es - k) if k >= 0 else (n - 2 - es + k)
    return max(fb, 0) + 1


def posit_selftest():
    assert veq_me(*posit_round(1, 0, 64, 3), 1, 0)      # 1.0 exact
    assert veq_me(*posit_round(3, -1, 64, 3), 3, -1)    # 1.5 exact
    rng = random.Random(SEEDS["posit_selftest"])
    n_trials = 20000
    for _ in range(n_trials):
        n, es = 64, rng.choice([2, 3, 4, 5])
        mm = rng.randrange(1, 1 << rng.randint(1, 70))
        ee = rng.randint(-300, 300)
        rm, re = posit_round(mm, ee, n, es)
        r2 = posit_round(rm, re, n, es)     # idempotence
        assert veq_me(*r2, rm, re), (mm, ee, es)
    assert posit_sig_width(0, 64, 3) == 59
    assert posit_sig_width(-252, 64, 3) == 28
    assert posit_sig_width(255, 64, 3) == 28
    return {"roundtrip_idempotence_trials": n_trials,
            "seed": SEEDS["posit_selftest"],
            "known_patterns_ok": True, "taper_spot_checks_ok": True,
            "verdict": "PASS"}


# ===========================================================================
# (a) RTO-tree divergence
# ===========================================================================


def rto_tree_deterministic():
    leaves = [Fraction(0)] * 32
    leaves[0], leaves[1], leaves[2] = Fraction(1), TWO ** -60, Fraction(-1)
    exact, b_a, b48, b50, b_iv = run_variants(leaves)
    ladder = []
    for q in (48, 50, 64, 128, 254, 368):
        K = max(0, q - 114)     # keeps the survivor in fp32 normal range
        lv = [Fraction(0)] * 32
        lv[0], lv[1], lv[2] = TWO ** K, TWO ** (K - q - 12), -(TWO ** K)
        got = tree_fold(lv, lambda s, q=q: rto_q(s, q), pack_signed)
        want = pack_signed(sum(lv, Fraction(0)))
        ladder.append({"q": q, "K": K, "tree": hexbits(got),
                       "exact": hexbits(want), "diverges": got != want})
    f16_rows = []
    for q, lv3 in ((48, (Fraction(1), TWO ** -48, Fraction(-1))),
                   (50, (TWO ** 30, TWO ** -48, -(TWO ** 30)))):
        lv = [Fraction(0)] * 32
        lv[0], lv[1], lv[2] = lv3
        got = tree_fold(lv, lambda s, q=q: rto_q(s, q), pack_signed)
        want = pack_signed(sum(lv, Fraction(0)))
        f16_rows.append({"q": q, "tree": hexbits(got), "exact": hexbits(want),
                         "diverges": got != want})
    return {
        "leaves": "[1x1, 2^-30 x 2^-30, 1x(-1), 0 x 29] — realizable bf16 "
                  "products; exact sum = 2^-60",
        "per_step_rne_A": hexbits(b_a),
        "rto48_tree": hexbits(b48),
        "rto50_tree": hexbits(b50),
        "exact_single_rne": hexbits(b_iv),
        "width_q_ladder": ladder,
        "width_q_ladder_leaves": "[2^K, 2^(K-q-12), -2^K] realizable bf16 "
                                 "products, K = max(0, q-114)",
        "f16_product_leaves": f16_rows,
        "verdict": "RTO-tree DIVERGES at every tested width (48/50/64/128/"
                   "254/368) for bf16 leaves and at 48/50 for f16 leaves",
    }


def rto_tree_families():
    fams = [
        ("cancellation", fam_cancel, 10000, SEEDS["fam_cancellation"]),
        ("tie_straddle", fam_tie, 10000, SEEDS["fam_tie_straddle"]),
        ("rand_bf16_wide", fam_wide, 10000, SEEDS["fam_rand_wide"]),
    ]
    out = {}
    for name, gen, n_trials, seed in fams:
        rng = random.Random(seed)
        d_a = d48 = d50 = 0
        worst48 = Fraction(0)
        for _ in range(n_trials):
            leaves = gen(rng)
            exact, b_a, b48, b50, b_iv = run_variants(leaves)
            d_a += b_a != b_iv
            d48 += b48 != b_iv
            d50 += b50 != b_iv
            if b48 != b_iv and exact != 0 and ((b48 >> 23) & 0xFF) != 0xFF:
                err = abs(bits_to_frac(b48) - exact) / ulp(abs(exact))
                worst48 = max(worst48, err)
        out[name] = {
            "N": n_trials, "seed": seed,
            "per_step_rne_A_diverge": d_a,
            "rto48_tree_diverge": d48,
            "rto48_tree_diverge_pct": round(100.0 * d48 / n_trials, 4),
            "rto50_tree_diverge": d50,
            "rto50_tree_diverge_pct": round(100.0 * d50 / n_trials, 4),
            "rto48_tree_worst_ulp_of_exact": float(worst48),
            "exact_rto48_store_equals_true_B_asserted_trials": n_trials,
        }
    return out


def kulisch_safe_width_check():
    rng = random.Random(SEEDS["kulisch_check"])
    n_trials, bad = 2000, 0
    for _ in range(n_trials):
        lvs = fam_cancel(rng)
        if tree_fold(lvs, lambda s: rto_q(s, 527), pack_signed) \
           != pack_signed(sum(lvs, Fraction(0))):
            bad += 1
    return {
        "q": 527, "family": "cancellation", "trials": n_trials,
        "seed": SEEDS["kulisch_check"], "diverge": bad,
        "verdict": "PASS" if bad == 0 else "FAIL",
        "note": "bf16 full-lattice span: q >= 527 is exact in any order "
                "(the jam never fires) — the width at which the RTO tree "
                "stops being a tree of roundings and IS the exact (Kulisch) "
                "accumulator. Tree-interior nodes sum <= 16 products (span "
                "<= 526) so q >= 526 is exact for THIS topology; q = 525 is "
                "analytically still unsafe. f16: q >= 85 (tree-interior 84).",
    }


# ===========================================================================
# (b) extraction theorem
# ===========================================================================


def extraction_theorem():
    x = 1 + TWO ** -24 + TWO ** -60
    det = []
    for q in (25, 26, 48, 50):
        a, b = pack_signed(rto_q(x, q)), pack_signed(x)
        det.append({"q": q, "rne_of_rto_q": hexbits(a),
                    "single_rne": hexbits(b), "equal": a == b})
    rng = random.Random(SEEDS["theorem_sweep"])
    n_sweep = 200000
    fails = {25: 0, 26: 0, 48: 0, 50: 0}
    nonzero = 0
    for _ in range(n_sweep):
        xx = sum(bf16_prod(rng, -15, 15) for _ in range(4))
        if xx == 0:
            continue
        nonzero += 1
        b = pack_signed(xx)
        for q in fails:
            if pack_signed(rto_q(xx, q)) != b:
                fails[q] += 1
    return {
        "statement": "RNE_24(RTO_q(x)) == RNE_24(x) for a SINGLE value x; "
                     "Boldo-Melquiond threshold q >= p+2 = 26 (PACK_WIDE "
                     "q = 48 carries 22 bits of margin)",
        "deterministic_tie_x": "1 + 2^-24 + 2^-60",
        "deterministic_tie_rows": det,
        "random_sweep": {
            "N": n_sweep, "nonzero_sums": nonzero,
            "seed": SEEDS["theorem_sweep"],
            "generator": "exact sums of 4 random bf16 products (long "
                         "significands, tie-adjacent), fp32 RNE+FTZ pack",
            "mismatches": {("q%d" % q): c for q, c in fails.items()},
            "q25_fail_pct": round(100.0 * fails[25] / n_sweep, 4),
        },
        "verdict": ("PASS" if fails[26] == 0 and fails[48] == 0
                    and fails[50] == 0 and fails[25] > 0 else "FAIL"),
    }


def composition_me_check():
    """(m,e)-domain composition twin: RTO-48 then RNE-24 never double-rounds
    (theorem); RNE-48 then RNE-24 DOES (why the bank store is RTO, not RNE).
    The RNE-48 failure needs a manufactured 24-bit tie (~2^-24 probability
    per random value — invisible to sampling), so it is proven by a DIRECTED
    counterexample; the random sweep is the RTO-48 zero-mismatch evidence."""
    rng = random.Random(SEEDS["composition_me"])
    n_sweep = 200000
    bad_rto = bad_rne = 0
    for _ in range(n_sweep):
        bl = rng.randint(1, 80)
        m = rng.randrange(1 << (bl - 1), 1 << bl) if bl > 1 else 1
        e = rng.randint(-40, 40)
        t = rne_me(m, e, P24)
        if not veq_me(*rne_me(*rto_me(m, e, P48), P24), *t):
            bad_rto += 1
        if not veq_me(*rne_me(*rne_me(m, e, P48), P24), *t):
            bad_rne += 1
    # directed: x = 2^48 + 2^24 + 1 (49 significant bits). RNE-48 ties at
    # the dropped LSB, keeps the even quotient, and lands EXACTLY on the
    # 24-bit midpoint; the final RNE-24 then resolves the manufactured tie
    # to even -> 2^48 (1 ulp LOW). True single RNE-24 rounds UP (dropped
    # field 2^24+1 > midpoint) -> 2^48 + 2^25. RTO-48 jams the sticky LSB
    # and stays above the midpoint -> correct.
    xm, xe = (1 << 48) + (1 << 24) + 1, 0
    t = rne_me(xm, xe, P24)
    rne48_path = rne_me(*rne_me(xm, xe, P48), P24)
    rto48_path = rne_me(*rto_me(xm, xe, P48), P24)
    assert veq_me(*t, (1 << 23) + 1, 25)            # 2^48 + 2^25
    assert veq_me(*rne48_path, 1 << 23, 25)         # 2^48 (wrong, 1 ulp low)
    assert veq_me(*rto48_path, *t)
    return {
        "N": n_sweep, "seed": SEEDS["composition_me"],
        "generator": "random wide values, significand 1..80 bits, "
                     "exponent -40..40",
        "rne24_of_rto48_mismatches": bad_rto,
        "rne24_of_rne48_mismatches": bad_rne,
        "rne48_random_rate_note": "an RNE-48 double-rounding event needs a "
                                  "manufactured exact 24-bit tie (~2^-24 "
                                  "per random value): 0 hits in 200k is the "
                                  "expected sampling outcome, not safety",
        "rne48_directed_counterexample": {
            "x": "2^48 + 2^24 + 1",
            "single_rne24": "2^48 + 2^25",
            "rne24_of_rne48": "2^48 (1 ulp LOW — double rounding)",
            "rne24_of_rto48": "2^48 + 2^25 (correct)",
            "asserted": True,
        },
        "verdict": "PASS" if bad_rto == 0 else "FAIL",
    }


# ===========================================================================
# (c) + (d) bank-chain divergence on S1/S4/S5 streams (with posit rows)
# ===========================================================================

STREAMS = [
    # (tag, band note, center, K, trials, seed key)
    ("S1_near1", "values ~2^0 (posit sweet spot)", 0, 32, 2000,
     "stream_S1_K32"),
    ("S1_near1", "values ~2^0 (posit sweet spot)", 0, 1024, 300,
     "stream_S1_K1024"),
    ("S4_hi_band", "values ~2^230 (bf16 headroom band)", 244, 32, 2000,
     "stream_S4_K32"),
    ("S4_hi_band", "values ~2^230 (bf16 headroom band)", 244, 1024, 300,
     "stream_S4_K1024"),
    ("S5_mid_band", "values ~2^90", 104, 32, 2000, "stream_S5_K32"),
    ("S5_mid_band", "values ~2^90", 104, 1024, 300, "stream_S5_K1024"),
]

ES_LIST = (2, 3, 5)


def run_stream(center, K, trials, seed, spread=4):
    rng = random.Random(seed)
    keys = ["A24", "RTO48", "OPT3"] + ["P64e%d" % es for es in ES_LIST]
    div = {k: 0 for k in keys}
    mx = {k: 0.0 for k in keys}
    infc = {k: 0 for k in keys}
    theorem_checks = 0
    for _ in range(trials):
        acc = {k: (0, 0) for k in keys}
        gm, ge, gcnt = 0, 0, 0
        xm, xe = 0, 0
        for _ in range(K):
            pm = rng.randrange(1 << 7, 1 << 8) * rng.randrange(1 << 7, 1 << 8)
            pe = (rng.randint(-spread, spread) + rng.randint(-spread, spread)
                  - 14 + center)
            if rng.random() < 0.5:
                pm = -pm
            xm, xe = add_me(xm, xe, pm, pe)
            m, e = acc["A24"]
            acc["A24"] = rne_me(*add_me(m, e, pm, pe), P24)
            m, e = acc["RTO48"]
            acc["RTO48"] = rto_me(*add_me(m, e, pm, pe), P48)
            gm, ge = add_me(gm, ge, pm, pe)
            gcnt += 1
            if gcnt == GROUP:               # Option 3: one RTO-48 per wave
                m, e = acc["OPT3"]
                acc["OPT3"] = rto_me(*add_me(m, e, gm, ge), P48)
                gm, ge, gcnt = 0, 0, 0
            for es in ES_LIST:
                kk = "P64e%d" % es
                m, e = acc[kk]
                acc[kk] = posit_round(*add_me(m, e, pm, pe), 64, es)
        if gcnt:
            m, e = acc["OPT3"]
            acc["OPT3"] = rto_me(*add_me(m, e, gm, ge), P48)
        t = rne_me(xm, xe, P24)
        for kk in keys:
            r = rne_me(*acc[kk], P24)
            if not veq_me(*r, *t):
                div[kk] += 1
                d = ulp_delta_me(*r, *t)
                if d == float("inf"):
                    infc[kk] += 1
                elif d > mx[kk]:
                    mx[kk] = d
        if K == GROUP:      # single wave: OPT3 == true B (theorem, asserted)
            assert veq_me(*rne_me(*acc["OPT3"], P24), *t)
            theorem_checks += 1
    chains = {}
    for kk in keys:
        chains[kk] = {"diverge": div[kk],
                      "diverge_pct": round(100.0 * div[kk] / trials, 4),
                      "max_ulp_of_B": mx[kk],
                      "zero_or_sign_class": infc[kk]}
    return chains, theorem_checks


def bank_chain_table():
    rows = []
    for tag, band, center, K, trials, seedkey in STREAMS:
        chains, checks = run_stream(center, K, trials, SEEDS[seedkey])
        rows.append({
            "stream": tag, "band": band, "center_2exp": center - 14,
            "K": K, "trials": trials, "seed": SEEDS[seedkey],
            "chains": chains,
            "opt3_single_wave_equals_true_B_asserted": checks,
        })
    return {
        "products": "random-sign bf16 x bf16 exact products, per-factor "
                    "exponent spread +-4 around the band center",
        "chains_doc": {
            "A24": "per-step RNE-24 bank chain (reading A)",
            "RTO48": "per-step RTO-48 wide-bank chain (one store per "
                     "product — option 2 shape)",
            "OPT3": "exact 32-term wave dot, ONE RTO-48 bank store per "
                    "wave-step, final RNE-24 (wave-step-atomic contract)",
            "P64e*": "per-step posit64(es) bank chain",
        },
        "comparison": "final values compared exactly vs true (B) = exact "
                      "sum + single RNE-24; unbounded-exponent domain "
                      "(accumulator fidelity, before the fp32 drain pack)",
        "sampling_note": "zero measured divergence for the 48-bit-store "
                         "chains at these K matches the ~K x 2^-24 "
                         "divergence-rate scaling and is NOT a formal (B) "
                         "claim across waves — the bank_store_jam_families "
                         "section proves the cross-wave limitation "
                         "constructively",
        "scenarios": rows,
    }


# ===========================================================================
# (d) deterministic adversarial families
# ===========================================================================

# per-write bank chains (each product = one bank store; the wave granularity
# that exposes the RTO-48 store jam — the honest cross-wave limitation)
JAM_FAMILIES = [
    ("F1_cancellation", "[+1, +2^-60, -1] (true 2^-60)",
     [(1 << 14, -14), (1 << 14, -74), (-(1 << 14), -14)]),
    ("F2_tie_straddler", "[+1, +2^-24, +2^-70] (true 1+2^-23)",
     [(1 << 14, -14), (1 << 14, -38), (1 << 14, -84)]),
    ("F3_double_round", "[+1, +2^-24, +2^-49] (true 1+2^-23)",
     [(1 << 14, -14), (1 << 14, -38), (1 << 14, -63)]),
    ("F4_park_plus_cancel", "[+1, +2^-60, -1, +2^-47] (true 2^-47+2^-60)",
     [(1 << 14, -14), (1 << 14, -74), (-(1 << 14), -14), (1 << 14, -61)]),
    ("F5a_tie_true_above", "[+1, +2^-24, +2^-70, +2^-70] (true above tie)",
     [(1 << 14, -14), (1 << 14, -38), (1 << 14, -84), (1 << 14, -84)]),
    ("F5b_tie_net_zero", "[+1, +2^-24, +2^-70, -2^-70] (true = exact tie)",
     [(1 << 14, -14), (1 << 14, -38), (1 << 14, -84), (-(1 << 14), -84)]),
    ("F6_tie_net_negative", "[+1, +2^-24, +2^-70, -2^-69] (true below tie)",
     [(1 << 14, -14), (1 << 14, -38), (1 << 14, -84), (-(1 << 14), -83)]),
]

# posit adversarial set (adds the band-extreme families)
POSIT_FAMILIES = [
    JAM_FAMILIES[0], JAM_FAMILIES[1], JAM_FAMILIES[2],
    ("F7_tie_at_2p96", "[+2^96, +2^72, +2^47] (true 2^96+2^73)",
     [(1 << 14, 82), (1 << 14, 58), (1 << 14, 33)]),
    ("F8_range_extreme_cancel", "[+2^250, +1, -2^250] (true 1)",
     [(1 << 15, 235), (1 << 14, -14), (-(1 << 15), 235)]),
    ("F9_taper_tie_at_2p230", "[+2^230, +2^206, +2^181] (true 2^230+2^207)",
     [(1 << 14, 216), (1 << 14, 192), (1 << 14, 167)]),
]


def chain_perwrite(products, mode):
    """mode: 'A24' / 'RTO48' / 'RNE48' per-write chains, or posit 'P64e<es>'.
    Final RNE-24 drain."""
    am, ae = 0, 0
    for pm, pe in products:
        am, ae = add_me(am, ae, pm, pe)
        if mode == "A24":
            am, ae = rne_me(am, ae, P24)
        elif mode == "RTO48":
            am, ae = rto_me(am, ae, P48)
        elif mode == "RNE48":
            am, ae = rne_me(am, ae, P48)
        else:
            es = int(mode[4:])
            am, ae = posit_round(am, ae, 64, es)
    return rne_me(am, ae, P24)


def true_b(products):
    xm, xe = 0, 0
    for pm, pe in products:
        xm, xe = add_me(xm, xe, pm, pe)
    return rne_me(xm, xe, P24), (xm, xe)


def family_rows(families, modes, check_opt3_wave):
    rows = []
    for name, doc, prods in families:
        t, (xm, xe) = true_b(prods)
        row = {"family": name, "products": doc,
               "true_B": {"m": t[0], "e": t[1]}}
        for mode in modes:
            r = chain_perwrite(prods, mode)
            ok = veq_me(*r, *t)
            cell = {"equals_true_B": ok}
            if not ok:
                d = ulp_delta_me(*r, *t)
                cell["delta_ulp_of_B"] = ("zero_or_sign_class"
                                          if d == float("inf") else d)
            row[mode] = cell
        if check_opt3_wave:
            # all products fit one wave-dot: Option 3 = RTO-48 of the exact
            # dot, then RNE-24 — equals true B by the extraction theorem
            o = rne_me(*rto_me(xm, xe, P48), P24)
            assert veq_me(*o, *t), name
            row["OPT3_single_wave"] = {"equals_true_B": True,
                                       "by": "extraction theorem"}
        rows.append(row)
    return rows


# ===========================================================================
# (d) posit taper table + quire arithmetic (exact regime arithmetic)
# ===========================================================================

TAPER_BINADES = [-992, -266, -252, -128, -64, -32, -16, -1, 0,
                 16, 32, 64, 96, 128, 230, 255, 279]


def taper_table():
    rows = []
    for E in TAPER_BINADES:
        rows.append({"binade": E,
                     **{("posit64_es%d" % es): posit_sig_width(E, 64, es)
                        for es in (2, 3, 4, 5)},
                     "pack_wide": 48})
    return {
        "doc": "effective significand bits (incl. hidden) of posit64 vs "
               "binade; PACK_WIDE is flat 48 over the whole signed-11 "
               "exponent range; exact regime arithmetic, no sampling",
        "rows": rows,
        "posit64_es2_bits_at_bf16_product_extremes": {
            "binade_-252": posit_sig_width(-252, 64, 2),
            "binade_+255": posit_sig_width(255, 64, 2),
        },
    }


def quire_arithmetic():
    n = 64
    quire_bits = 16 * n                     # posit standard (2022): 16n
    lanes = 8                               # quarter-op = 8 lanes
    frag_bits = 64
    return {
        "posit64_quire_bits_per_lane": quire_bits,
        "quarter_op_spill_bits": lanes * quire_bits,
        "quarter_op_spill_fragments_64b": lanes * quire_bits // frag_bits,
        "frag_max": 16,
        "pack_wide_bank_quarter_op_bits": lanes * 64,
        "pack_wide_bank_quarter_op_fragments": lanes * 64 // frag_bits,
        "note": "the quire (Kulisch register) is the posit ecosystem's own "
                "exact-accumulation answer; its spill image is 8x over "
                "FRAG_MAX where the fp64-encoded PACK_WIDE bank word is 8 "
                "fragments (within FRAG_MAX)",
    }


# ===========================================================================
# (e) input-noise dominance (paired per-dot)
# ===========================================================================


def float_me(v):
    num, den = v.as_integer_ratio()         # den is a power of two
    return num, 1 - den.bit_length()


def quant_bf16_me(v):
    """bf16 quantization: RNE to 8-bit significand (normal range for these
    unit-variance streams — DAZ pin makes bf16 operands normal-only)."""
    return rne_me(*float_me(v), 8)


def tree_rne24(items):
    """Schedule-A wave dot: balanced tree, per-NODE RNE-24 (31 events)."""
    lvl = items
    while len(lvl) > 1:
        lvl = [rne_me(*add_me(*lvl[i], *lvl[i + 1]), P24)
               for i in range(0, len(lvl), 2)]
    return lvl[0]


def err_vs_exact(cm, ce, xm, xe, ue):
    dm, de = add_me(cm, ce, -xm, xe)
    if dm == 0:
        return 0.0
    return me_float(dm, de - ue)


def run_noise(dist, K, trials, seed):
    rng = random.Random(seed)
    waves = K // GROUP
    a_ne = b_ne = 0
    err_a, err_b, quant_n = [], [], []
    ratios, n_inf, n_viol = [], 0, 0
    for _ in range(trials):
        if dist == "gauss":
            a64 = [rng.gauss(0.0, 1.0) for _ in range(K)]
            w64 = [rng.gauss(0.0, 1.0) for _ in range(K)]
        elif dist == "relu":
            a64 = [abs(rng.gauss(0.0, 1.0)) for _ in range(K)]
            w64 = [rng.gauss(0.0, 1.0) for _ in range(K)]
        else:                               # gradcancel: near-converged
            a64 = [rng.gauss(0.0, 1.0) for _ in range(K)]
            w64 = [-a64[i] + 1e-3 * rng.gauss(0.0, 1.0) for i in range(K)]
        aq = [quant_bf16_me(v) for v in a64]
        wq = [quant_bf16_me(v) for v in w64]
        prods = [(aq[i][0] * wq[i][0], aq[i][1] + wq[i][1]) for i in range(K)]
        xm, xe = 0, 0
        for pm, pe in prods:
            xm, xe = add_me(xm, xe, pm, pe)
        iv = rne_me(xm, xe, P24)
        acc_a = (0, 0)
        acc_b = (0, 0)
        for wv in range(waves):
            chunk = prods[wv * GROUP:(wv + 1) * GROUP]
            t_a = tree_rne24(chunk)                     # 31 RNE events
            acc_a = rne_me(*add_me(*acc_a, *t_a), P24)  # + 1 bank RNE
            sm, se = 0, 0
            for pm, pe in chunk:                        # exact wave dot
                sm, se = add_me(sm, se, pm, pe)
            acc_b = rto_me(*add_me(*acc_b, sm, se), P48)  # 1 RTO-48 store
        acc_b24 = rne_me(*acc_b, P24)                     # drain RNE-24
        if K == GROUP:
            assert veq_me(*acc_b24, *iv)    # single wave == true B (theorem)
        a_ne += not veq_me(*acc_a, *iv)
        b_ne += not veq_me(*acc_b24, *iv)
        ue = ulp_exp_me(xm, xe) if xm else -23
        e_a = err_vs_exact(*acc_a, xm, xe, ue)
        e_b = err_vs_exact(*acc_b24, xm, xe, ue)
        fm, fe = 0, 0                       # exact float64-input dot
        for i in range(K):
            m1, e1 = float_me(a64[i])
            m2, e2 = float_me(w64[i])
            fm, fe = add_me(fm, fe, m1 * m2, e1 + e2)
        q = err_vs_exact(fm, fe, xm, xe, ue)
        err_a.append(e_a)
        err_b.append(e_b)
        quant_n.append(q)
        worst_acc = max(e_a, e_b)
        if worst_acc == 0.0:
            n_inf += 1                      # accumulation exact: dominance
        else:
            r = q / worst_acc
            if math.isinf(r):
                n_inf += 1
            else:
                ratios.append(r)
                if q <= worst_acc:
                    n_viol += 1
    return {
        "dist": dist, "K": K, "trials": trials, "seed": seed,
        "A_ne_trueB": a_ne, "OPT3_ne_trueB": b_ne,
        "err_A_mean_ulp": statistics.fmean(err_a),
        "err_A_max_ulp": max(err_a),
        "err_OPT3_mean_ulp": statistics.fmean(err_b),
        "err_OPT3_max_ulp": max(err_b),
        "bf16_quant_noise_mean_ulp": statistics.fmean(quant_n),
        "pairs": trials,
        "pairs_quant_noise_dominates": trials - n_viol,
        "pairs_violating_dominance": n_viol,
        "min_finite_ratio": min(ratios) if ratios else None,
        "median_finite_ratio": statistics.median(ratios) if ratios else None,
        "pairs_accumulation_exact": n_inf,
    }


def input_noise_dominance():
    plan = [(32, 400), (256, 200), (4096, 40)]
    rows, total_pairs, total_viol = [], 0, 0
    min_ratio = None
    for dist, seedkey in (("gauss", "noise_gauss"), ("relu", "noise_relu"),
                          ("gradcancel", "noise_gradcancel")):
        for K, trials in plan:
            row = run_noise(dist, K, trials, SEEDS[seedkey] + K)
            rows.append(row)
            total_pairs += row["pairs"]
            total_viol += row["pairs_violating_dominance"]
            r = row["min_finite_ratio"]
            if r is not None and (min_ratio is None or r < min_ratio):
                min_ratio = r
    return {
        "doc": "paired per-dot comparison on the SAME dot: bf16 input-"
               "quantization noise |dot(f64) - dot(bf16)| vs the WORSE of "
               "the two accumulation errors (schedule-A tree+bank vs "
               "Option 3), both in ulp24 of the exact bf16-product dot; "
               "stdlib Gaussian streams (regenerated — the session run "
               "used numpy + salted-hash seeds)",
        "scenarios": rows,
        "total_pairs": total_pairs,
        "pairs_quant_noise_dominates": total_pairs - total_viol,
        "pairs_violating_dominance": total_viol,
        "min_finite_ratio_overall": min_ratio,
        "verdict": "PASS" if total_viol == 0 else "FAIL",
        "conclusion": "input quantization noise exceeds every measured "
                      "accumulation scheme's error on every paired dot — "
                      "Option 3 is adopted for contract strength + "
                      "throughput + verification-surface reduction, not "
                      "raw accuracy",
    }


# ===========================================================================
# (f) lattice width arithmetic + rounding-event count
# ===========================================================================


def lattice_width():
    # bf16: operands normal-only (DAZ pin). value = s8 * 2^(e-7), s8 in
    # [2^7, 2^8), e in [-126, 127]. product = s16 * 2^(E-14), s16 in
    # [2^14, 2^16), E = ea + eb in [-252, 254].
    lsb_bf = (-252) - 14                    # weight 2^-266
    msb_bf = 255                            # product < 2^256
    span_bf = msb_bf - lsb_bf + 1
    tot_bf = span_bf + 5 + 1                # + log2(32) carry + sign
    # f16: subnormals honored. every f16 = k * 2^-24, |value| < 2^16.
    lsb_f16 = -48
    msb_f16 = 31                            # product < 2^32
    span_f16 = msb_f16 - lsb_f16 + 1
    tot_f16 = span_f16 + 5 + 1
    assert Fraction(1 << 14) * TWO ** (-252 - 14) == TWO ** -252
    assert tot_bf == 528 and tot_f16 == 86
    # adopted weight-span formulation: 2^-266 .. 2^260 inclusive + sign
    weight_span = 260 - (-266) + 1
    assert weight_span + 1 == 528
    return {
        "bf16": {"product_lsb_weight_2exp": lsb_bf,
                 "product_msb_bound_2exp": msb_bf + 1,
                 "span_bits": span_bf, "carry_bits_log2_32": 5,
                 "sign_bits": 1, "total_bits": tot_bf},
        "f16": {"product_lsb_weight_2exp": lsb_f16,
                "product_msb_bound_2exp": msb_f16 + 1,
                "span_bits": span_f16, "carry_bits_log2_32": 5,
                "sign_bits": 1, "total_bits": tot_f16},
        "adopted_lattice": "528-bit two's-complement segmented carry-save "
                           "lattice, weights 2^-266..2^260 (527) + sign = "
                           "528; 529 was 1 bit over-provisioned",
        "checks": {
            "min_bf16_product_is_2^-252": True,
            # max product = (2^8-1)^2 * 2^(254-14): s16 < 2^16, E_max = 254
            "32x_max_bf16_product_below_2^261": (32 * ((1 << 8) - 1) ** 2
                                                 * 2 ** (254 - 14)
                                                 < 2 ** 261),
            "exponent_260_fits_signed_11": -1024 <= 260 <= 1023,
            "32x_max_f16_product_below_2^37": 32 * (2 ** 32 - 1) < 2 ** 37,
        },
        "acc_bank_state_bits_2banks_x_32lanes": {
            "fp32_bank": 2 * 32 * 32,
            "pack_wide_fp64_encoded_bank": 2 * 32 * 64,
            "f16_kulisch": 2 * 32 * tot_f16,
            "bf16_kulisch": 2 * 32 * tot_bf,
        },
    }


def rounding_events():
    tree_nodes = 16 + 8 + 4 + 2 + 1
    return {
        "schedule_A_per_dispatch": {"tree_node_rne24": tree_nodes,
                                    "bank_store_rne24": 1,
                                    "total": tree_nodes + 1},
        "option3_per_dispatch": {"in_dot": 0,
                                 "bank_store_rto48": 1, "total": 1},
        "drain": {"pack_final_rne24": 1},
        "correction": "the kickoff memo's '(A) = 6 RNE per dot' confused "
                      "path DEPTH (5 tree levels + bank) with EVENT count: "
                      "a 32-leaf tree performs 31 node roundings + 1 bank "
                      "store = 32 rounding events per dispatch",
    }


# ===========================================================================
# main
# ===========================================================================


def main():
    t_start = time.time()

    def stamp(tag, t0):
        print("  [%6.1fs] %s" % (time.time() - t0, tag))
        sys.stdout.flush()

    print("acc_format_study: v2.0 wave-step-atomic accumulation COMMIT-0 "
          "design-study regeneration (fixed seeds)")

    t0 = time.time()
    selftest = posit_selftest()
    stamp("posit codec self-test", t0)

    t0 = time.time()
    tree_det = rto_tree_deterministic()
    stamp("RTO-tree deterministic counterexamples + width ladder", t0)

    t0 = time.time()
    tree_fams = rto_tree_families()
    stamp("RTO-tree random families (3 x 10000)", t0)

    t0 = time.time()
    kulisch = kulisch_safe_width_check()
    stamp("Kulisch safe-width check (q=527)", t0)

    t0 = time.time()
    theorem = extraction_theorem()
    stamp("extraction theorem sweep (200k)", t0)

    t0 = time.time()
    composition = composition_me_check()
    stamp("RTO-48 vs RNE-48 composition sweep (200k)", t0)

    t0 = time.time()
    chains = bank_chain_table()
    stamp("bank-chain streams S1/S4/S5 x K in {32,1024} (incl. posit)", t0)

    t0 = time.time()
    jam_rows = family_rows(JAM_FAMILIES, ("A24", "RTO48", "RNE48"),
                           check_opt3_wave=True)
    posit_rows = family_rows(
        POSIT_FAMILIES, ("A24", "RTO48", "P64e2", "P64e3", "P64e5"),
        check_opt3_wave=True)
    stamp("deterministic adversarial families", t0)

    t0 = time.time()
    noise = input_noise_dominance()
    stamp("input-noise dominance paired measurement", t0)

    taper = taper_table()
    quire = quire_arithmetic()
    width = lattice_width()
    events = rounding_events()

    f2_es5_loses = not posit_rows[1]["P64e5"]["equals_true_B"]
    report = {
        "_doc": "v2.0 wave-step-atomic accumulation (Option 3: exact-"
                "integer in-dot lattice + wide ACC bank, RTO-48 store per "
                "wave-step, single RNE-24 at drain; Option 3a FDOT32_CR "
                "0x7A committed follow-up) — COMMIT-0 design-study numbers, "
                "regenerated with FIXED seeds by scripts/acc_format_study.py"
                " (consolidates the session /tmp harnesses). Ground truth "
                "is exact integer/Fraction arithmetic; fp32 semantics from "
                "scripts/golden_fp32.py. Deterministic: byte-identical "
                "across runs, no timestamps.",
        "determinism": {
            "seeds": SEEDS,
            "note": "seeds theorem_sweep/composition_me/kulisch_check/"
                    "posit_selftest are bit-identical to the session "
                    "harnesses (their numbers reproduce exactly); family/"
                    "stream/noise seeds replace the session's salted-hash "
                    "seeds, so those counts are regenerated (direction-"
                    "confirming) rather than bit-identical",
        },
        "rto_tree": {
            "deterministic": tree_det,
            "random_families_q48_q50": tree_fams,
            "kulisch_safe_width": kulisch,
        },
        "extraction_theorem": theorem,
        "rto48_vs_rne48_composition": composition,
        "bank_chains": chains,
        "bank_store_jam_families": {
            "doc": "per-write wide-bank chains (each product = one bank "
                    "store): the granularity that exposes the RTO-48 "
                    "store jam under cross-wave cancellation — the honest "
                    "limitation of the wave-step-atomic contract (formal "
                    "single-rounding holds WITHIN a wave-step, not across "
                    "the full K horizon). F3 shows RNE-48 double-rounding "
                    "on a single store (why the store is RTO); F5b/F6 "
                    "show the jam-parking limitation of RTO-48 itself.",
            "families": jam_rows,
        },
        "posit": {
            "codec_selftest": selftest,
            "taper_table": taper,
            "adversarial_families": posit_rows,
            "quire_arithmetic": quire,
        },
        "input_noise_dominance": noise,
        "lattice_width": width,
        "rounding_events": events,
        "verdicts": {
            "rto_tree_diverges_at_all_tested_widths": all(
                r["diverges"] for r in tree_det["width_q_ladder"]),
            "extraction_theorem_q26_and_48_zero_mismatch":
                theorem["verdict"] == "PASS",
            "rne48_store_double_rounds_rto48_does_not":
                composition["verdict"] == "PASS",
            "exact_dot_plus_rto48_store_equals_true_B_within_wave": True,
            "posit_es5_loses_F2_sticky_tie": f2_es5_loses,
            "input_noise_dominates_all_paired_dots":
                noise["verdict"] == "PASS",
            "lattice_width_bits": {"bf16": 528, "f16": 86},
        },
    }
    REPORT.write_text(json.dumps(report, indent=1, allow_nan=False) + "\n")
    print("wrote %s" % REPORT)
    print("total %.1fs" % (time.time() - t_start))

    # headline echo (stdout only — not part of the report)
    print("headlines:")
    print("  theorem q25 fails: %s/200000 (%.2f%%); q26/q48/q50: %d/%d/%d" % (
        theorem["random_sweep"]["mismatches"]["q25"],
        theorem["random_sweep"]["q25_fail_pct"],
        theorem["random_sweep"]["mismatches"]["q26"],
        theorem["random_sweep"]["mismatches"]["q48"],
        theorem["random_sweep"]["mismatches"]["q50"]))
    for name, fam in tree_fams.items():
        print("  RTO-tree %s: q48 %.2f%%, q50 %.2f%%" % (
            name, fam["rto48_tree_diverge_pct"],
            fam["rto50_tree_diverge_pct"]))
    print("  composition: rto48 %d, rne48 %d mismatches" % (
        composition["rne24_of_rto48_mismatches"],
        composition["rne24_of_rne48_mismatches"]))
    print("  noise dominance: %d/%d pairs, min finite ratio %s" % (
        noise["pairs_quant_noise_dominates"], noise["total_pairs"],
        noise["min_finite_ratio_overall"]))


if __name__ == "__main__":
    main()
