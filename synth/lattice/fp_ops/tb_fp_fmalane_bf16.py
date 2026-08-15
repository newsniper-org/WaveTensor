# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""tb_fp_fmalane_bf16 — correctness sanity for FP_FmaLaneBf16 (the v2.0
TRAIN unified bf16/f16 fused-FMA lane, spec §23.1) BEFORE synthesis.

Bit-exactness authority: scripts/golden_fp32.py.
  * ref_fma_bf16 / ref_fma_f16 — the lane's numeric contract, itself a
    COMPOSITION of ref_widen_* (operand-load policy) and ref_fma (exact
    product, SINGLE RNE, flush-after-round FTZ, the IEEE special table).
  * naive_fma_narrow — the DELIBERATELY WRONG multiply-then-round-then-add
    model, used to prove the RTL implements the fused contract and not it.

Every stream is driven BACK-TO-BACK (new operands every cycle) through a
LATENCY-deep expectation queue, which simultaneously proves the exact
fixed latency and the 1-result-per-cycle always-flowing contract. The
dtype_bf16 selector is driven PER-VECTOR (and one test interleaves the two
formats cycle-by-cycle), so a globally-latched dtype would fail.

LATENCY is 6: S1 unpack/classify -> S2 11x11 multiply -> S3/S4/S5
FP_AddWide (stage A / B1 / B2) -> S6 special-case output mux.

-----------------------------------------------------------------------------
THE ROUND-ONCE DISCRIMINATORS (the point of this TB)
-----------------------------------------------------------------------------
A narrow x narrow product carries at most 22 (f16) / 16 (bf16) significand
bits, so it is EXACTLY fp32-representable whenever its exponent is in
fp32's normal range — in that band the fused result and a naive
round(a*b)-then-add are provably identical and NO vector separates them.
Saying "we tested the fused contract" on random in-range vectors would
therefore be an empty claim. The contract is observationally discriminated
only where a separate fp32 multiply would LOSE the product:

  * PRODUCT UNDERFLOW — |a*b| < 2^-126. Reachable in bf16 (product
    exponents span [-251, 255]). The naive path FTZ-flushes the product to
    zero and returns the addend unchanged; the fused lane still adds it.
    e.g. a = b = 2^-70 (bf16), c = 2^-126 (fp32 min normal):
        fused = 0x00800200   naive = 0x00800000   (512 ulps apart)
  * PRODUCT OVERFLOW — |a*b| >= 2^128. Reachable in bf16.  The naive path
    saturates the product to +/-Inf and the accumulate is stuck at Inf; the
    fused lane is pulled back into range by a large opposite-signed addend.
    e.g. a = b = 2^64 (bf16), c = -2^127:
        fused = 0x7F000000 (= 2^127)   naive = 0x7F800000 (= +Inf)

f16 CANNOT discriminate at all: its product exponents span only [-47, 31],
so the exact product is always a finite in-range fp32 and fused == naive
for every (a, b, c). round_once_bound_f16 asserts that null result
explicitly rather than leaving it implied — it bounds the claim, and it is
the reason the discriminator suite is bf16-only.
"""

import random
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "scripts"))
import golden_fp32 as G  # noqa: E402

LATENCY = 6

DT_F16 = G.DT_F16          # 0x2 -> dtype_bf16 = 0
DT_BF16 = G.DT_BF16        # 0x3 -> dtype_bf16 = 1

NUM_BF16_RANDOM = 20_000
NUM_F16_RANDOM = 20_000


# ---------------------------------------------------------------------------
# operand builders
# ---------------------------------------------------------------------------


def bf16(sign, e8, m7):
    return (sign << 15) | ((e8 & 0xFF) << 7) | (m7 & 0x7F)


def f16(sign, e5, m10):
    return (sign << 15) | ((e5 & 0x1F) << 10) | (m10 & 0x3FF)


def bf16_p2(k, sign=0):
    """bf16 value +/-2^k (k in [-126, 127])."""
    return bf16(sign, k + 127, 0)


def f32(sign, e, m23):
    return (sign << 31) | (((e + 127) & 0xFF) << 23) | (m23 & 0x7FFFFF)


def rand_f32_normal(emin=-126, emax=127):
    return ((random.getrandbits(1) << 31)
            | ((random.randint(emin, emax) + 127) << 23)
            | random.getrandbits(23))


def rand_bf16_finite():
    return bf16(random.getrandbits(1), random.randint(1, 254),
                random.getrandbits(7))


def rand_f16_finite():
    return f16(random.getrandbits(1), random.randint(1, 30),
               random.getrandbits(10))


# ---------------------------------------------------------------------------
# streaming driver (back-to-back, LATENCY-deep expectation queue)
# ---------------------------------------------------------------------------


def _apply(dut, a, b, c, dtype):
    dut.a_narrow.value = a
    dut.b_narrow.value = b
    dut.c_fp32.value = c
    dut.dtype_bf16.value = 1 if dtype == DT_BF16 else 0


async def _stream(dut, cases, label):
    """cases: (a, b, c, dtype). Expected value is computed from golden."""
    pending = []
    checked = 0

    def _check(vec, idx):
        a, b, c, dt = vec
        exp = G.ref_fma_narrow(a, b, c, dt)
        got = int(dut.result_fp32.value)
        assert got == exp, (
            f"{label}[{idx}]: a={a:#06x} b={b:#06x} c={c:#010x} "
            f"dtype={'bf16' if dt == DT_BF16 else 'f16'} -> got {got:#010x} "
            f"expected {exp:#010x}")

    for i, vec in enumerate(cases):
        if len(pending) == LATENCY:
            j, v0 = pending.pop(0)
            _check(v0, j)
            checked += 1
        _apply(dut, *vec)
        pending.append((i, vec))
        await FallingEdge(dut.clk)
    while pending:
        j, v0 = pending.pop(0)
        _check(v0, j)
        checked += 1
        await FallingEdge(dut.clk)

    dut._log.info("%s: %d vectors bit-exact", label, checked)
    return checked


async def _stream_capture(dut, cases, label):
    """Like _stream, but RETURNS the DUT's output word for every vector
    instead of asserting inside the drive loop — the caller owns the
    assertions. round_once_discriminator needs this because its claim is a
    property of the DUT OUTPUT against TWO models (== fused, != naive),
    and both halves must be measured on the captured RTL output rather
    than re-derived from the references."""
    pending = 0
    got = []
    for vec in cases:
        if pending == LATENCY:
            got.append(int(dut.result_fp32.value))
            pending -= 1
        _apply(dut, *vec)
        pending += 1
        await FallingEdge(dut.clk)
    while pending:
        got.append(int(dut.result_fp32.value))
        pending -= 1
        await FallingEdge(dut.clk)

    dut._log.info("%s: %d DUT outputs captured", label, len(got))
    return got


async def _start(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    _apply(dut, 0, 0, 0, DT_BF16)
    await FallingEdge(dut.clk)


# ---------------------------------------------------------------------------
# bf16 numeric path
# ---------------------------------------------------------------------------


@cocotb.test()
async def bf16_numeric(dut):
    random.seed(0xBF16)
    await _start(dut)

    cases = []
    # directed: exact cancellation a*b == -c -> +0
    cases += [(bf16_p2(1), bf16_p2(2), f32(1, 3, 0), DT_BF16),
              (bf16(0, 127, 0x40), bf16(0, 127, 0x20), 0xBFA50000, DT_BF16)]
    # directed: c = -RN(a*b) exactly -> the residual is 0 (products are exact)
    for _ in range(300):
        a, b = rand_bf16_finite(), rand_bf16_finite()
        c = G.ref_mul(G.ref_widen_bf16(a), G.ref_widen_bf16(b)) ^ 0x80000000
        if (c >> 23) & 0xFF in (0, 0xFF):
            continue
        cases.append((a, b, c, DT_BF16))
    # directed: addend far above / far below the product (sticky extremes)
    for _ in range(400):
        a, b = rand_bf16_finite(), rand_bf16_finite()
        c = rand_f32_normal(*random.choice(((-126, -90), (80, 127))))
        cases.append((a, b, c, DT_BF16))
    # directed: every alignment distance 0..55 against a fixed product
    for d in range(56):
        for m in (0x000000, 0x7FFFFF, 0x000001, 0x400000, 0x555555):
            for s in (0, 1):
                e = 20 - d
                if e < -126:
                    continue
                cases.append((bf16_p2(10), bf16_p2(10), f32(s, e, m),
                              DT_BF16))
    # directed: bf16 subnormal operands -> signed zero (COMMIT-0 pin 6)
    for m in (1, 0x40, 0x7F):
        for s in (0, 1):
            cases.append((bf16(s, 0, m), bf16_p2(3), 0x3F800000, DT_BF16))
            cases.append((bf16(s, 0, m), bf16(s ^ 1, 0, m), 0x00000000,
                          DT_BF16))
    # directed: exponent extremes (RNE overflow / flush-after-round FTZ)
    cases += [(bf16_p2(127), bf16_p2(127), 0x00000000, DT_BF16),
              (bf16_p2(-126), bf16_p2(-126), 0x00000000, DT_BF16),
              (bf16(0, 254, 0x7F), bf16(0, 254, 0x7F), 0xFF7FFFFF, DT_BF16)]
    # random
    for _ in range(NUM_BF16_RANDOM):
        cases.append((rand_bf16_finite(), rand_bf16_finite(),
                      rand_f32_normal(), DT_BF16))

    await _stream(dut, cases, "bf16_numeric")


# ---------------------------------------------------------------------------
# f16 numeric path — incl. the honored-subnormal asymmetry vs bf16
# ---------------------------------------------------------------------------


@cocotb.test()
async def f16_numeric(dut):
    random.seed(0x0F16)
    await _start(dut)

    cases = []
    # directed: EVERY f16 subnormal mantissa as operand a (all 1023 of them),
    # against a fixed normal b and a normal addend. These widen to fp32
    # NORMALS and must be honored EXACTLY (ref_widen_f16), unlike bf16's.
    for m in range(1, 1024):
        cases.append((f16(0, 0, m), f16(0, 15, 0), 0x3F800000, DT_F16))
    # directed: subnormal x subnormal (smallest reachable products)
    for ma in (1, 2, 3, 0x155, 0x3FF):
        for mb in (1, 0x200, 0x3FF):
            for s in (0, 1):
                cases.append((f16(s, 0, ma), f16(0, 0, mb), 0x00800000,
                              DT_F16))
    # directed: f16 min/max normal extremes
    cases += [(f16(0, 1, 0), f16(0, 1, 0), 0x00000000, DT_F16),
              (f16(0, 30, 0x3FF), f16(0, 30, 0x3FF), 0x00000000, DT_F16),
              (f16(1, 30, 0x3FF), f16(0, 30, 0x3FF), 0x7F7FFFFF, DT_F16)]
    # directed: c = -RN(a*b) -> exact cancellation
    for _ in range(300):
        a, b = rand_f16_finite(), rand_f16_finite()
        c = G.ref_mul(G.ref_widen_f16(a), G.ref_widen_f16(b)) ^ 0x80000000
        if (c >> 23) & 0xFF in (0, 0xFF):
            continue
        cases.append((a, b, c, DT_F16))
    # random, including subnormal operands
    for _ in range(NUM_F16_RANDOM):
        a = rand_f16_finite() if random.random() < 0.8 \
            else f16(random.getrandbits(1), 0, random.getrandbits(10))
        b = rand_f16_finite() if random.random() < 0.8 \
            else f16(random.getrandbits(1), 0, random.getrandbits(10))
        cases.append((a, b, rand_f32_normal(), DT_F16))

    await _stream(dut, cases, "f16_numeric")


# ---------------------------------------------------------------------------
# IEEE special-case table — the full cross product, both formats
# ---------------------------------------------------------------------------


@cocotb.test()
async def ieee_specials(dut):
    random.seed(0x5EC1)
    await _start(dut)

    cases = []
    for dt, mk, qnan_m, inf_e in ((DT_BF16, bf16, 0x40, 0xFF),
                                  (DT_F16, f16, 0x200, 0x1F)):
        narrow = []
        for s in (0, 1):
            narrow += [
                mk(s, inf_e, qnan_m),                    # qNaN
                mk(s, inf_e, 1),                         # sNaN
                mk(s, inf_e, 0),                         # Inf
                mk(s, 0, 0),                             # zero
                mk(s, 0, 1),                             # subnormal
                mk(s, 1, 0),                             # min normal
                mk(s, inf_e - 1, qnan_m - 1),            # large normal
            ]
        addend = [0x7FC00000, 0x7FC00001, 0xFFC00000,    # NaNs
                  0x7F800000, 0xFF800000,                # +/-Inf
                  0x00000000, 0x80000000,                # +/-0
                  0x00000001, 0x807FFFFF,                # DAZ subnormals
                  0x3F800000, 0xBF800000,                # +/-1
                  0x00800000, 0x7F7FFFFF]                # min normal / max
        for a in narrow:
            for b in narrow:
                for c in addend:
                    cases.append((a, b, c, dt))

    await _stream(dut, cases, "ieee_specials")


# ---------------------------------------------------------------------------
# THE ROUND-ONCE DISCRIMINATORS — fused vs multiply-then-round-then-add
# ---------------------------------------------------------------------------


@cocotb.test()
async def round_once_discriminator(dut):
    """Vectors on which the fused contract and the naive contract PROVABLY
    differ. The RTL must match the fused reference on every one of them,
    and must differ from the naive reference on every one of them."""
    random.seed(0x0FCE)
    await _start(dut)

    # ---- band 1: PRODUCT UNDERFLOW (naive FTZ-flushes the product) --------
    # The product is visible in the sum only when it reaches the addend's
    # round bit, i.e. |a*b| >= 2^(ce-24); it is lost by a separate fp32
    # multiply only when |a*b| < 2^-126. Both hold simultaneously exactly
    # when the addend exponent ce is below -102, so the band is swept
    # systematically over (ce, product exponent) rather than blindly.
    under = []
    # the exact worked example from the module header
    under.append((bf16_p2(-70), bf16_p2(-70), 0x00800000, DT_BF16))
    for ce in range(-126, -101):
        for pexp in range(ce - 26, -126):
            ka = pexp // 2
            kb = pexp - ka
            if not (-126 <= ka <= 127 and -126 <= kb <= 127):
                continue
            for cm in (0, 1, 0x7FFFFF, 0x400000):
                for cs in (0, 1):
                    for bs in (0, 1):
                        under.append((bf16_p2(ka), bf16_p2(kb, bs),
                                      f32(cs, ce, cm), DT_BF16))
    # randomized, with nontrivial operand and addend mantissas
    for _ in range(20_000):
        ce = random.randint(-126, -103)
        pexp = random.randint(ce - 26, -127)
        ka = pexp // 2
        kb = pexp - ka
        if not (-126 <= ka <= 127 and -126 <= kb <= 127):
            continue
        under.append((bf16(random.getrandbits(1), ka + 127,
                           random.getrandbits(7)),
                      bf16(random.getrandbits(1), kb + 127,
                           random.getrandbits(7)),
                      f32(random.getrandbits(1), ce, random.getrandbits(23)),
                      DT_BF16))

    # ---- band 2: PRODUCT OVERFLOW (naive saturates to +/-Inf) -------------
    # |a*b| >= 2^128 kills a separate multiply outright; the fused sum stays
    # finite only if a large opposite-signed addend pulls it back, so the
    # product exponent must sit in [128, 129) and |c| must be near fp32 max.
    over = [(bf16_p2(64), bf16_p2(64), 0xFF000000, DT_BF16)]
    for ka in range(1, 128):
        for dk in (0, 1):
            kb = 128 - ka - dk
            if not (-126 <= kb <= 127):
                continue
            for am in (0, 0x40, 0x7F):
                for bm in (0, 0x7F):
                    for bs in (0, 1):
                        for cm in (0, 0x400000, 0x7FFFFF):
                            over.append((bf16(0, ka + 127, am),
                                         bf16(bs, kb + 127, bm),
                                         f32(0 if bs else 1, 127, cm),
                                         DT_BF16))

    # VECTOR SELECTION (a property of the models, not of the DUT): keep
    # only the cases where the fused and naive contracts actually differ,
    # so every streamed vector is capable of discriminating the two. The
    # floor asserts guard against a TB regression that silently empties
    # the bands — they say nothing about the RTL yet.
    d_under = [v for v in under
               if G.ref_fma_narrow(*v) != G.naive_fma_narrow(*v)]
    d_over = [v for v in over
              if G.ref_fma_narrow(*v) != G.naive_fma_narrow(*v)]
    assert len(d_under) >= 5_000, (
        f"TB bug: only {len(d_under)} underflow-band discriminators")
    assert len(d_over) >= 500, (
        f"TB bug: only {len(d_over)} overflow-band discriminators")

    disc = d_under + d_over

    # THE MEASUREMENT (a property of the DUT): capture the RTL output for
    # every discriminator and check the CAPTURED word against both models —
    #   (1) got == fused reference: the lane implements the contract here;
    #   (2) got != naive model:     the lane is observably NOT a
    #       multiply-then-round-then-add — it lands on the fused side of
    #       the split on every vector where the two sides differ.
    # (2) is asserted on the DUT output, never re-derived from the filter
    # predicate above: a naive implementation fails (1) AND (2) on all of
    # these vectors, and a TB that only re-evaluated the references would
    # prove nothing about the RTL.
    got = await _stream_capture(dut, disc, "round_once_fused")
    assert len(got) == len(disc)
    for i, (vec, g) in enumerate(zip(disc, got)):
        a, b, c, dt = vec
        exp = G.ref_fma_narrow(*vec)
        nai = G.naive_fma_narrow(*vec)
        assert g == exp, (
            f"round_once[{i}]: a={a:#06x} b={b:#06x} c={c:#010x} -> DUT "
            f"{g:#010x} != fused reference {exp:#010x}")
        assert g != nai, (
            f"round_once[{i}]: a={a:#06x} b={b:#06x} c={c:#010x} -> DUT "
            f"{g:#010x} EQUALS the naive multiply-then-round-then-add "
            f"model on a vector where fused ({exp:#010x}) differs — the "
            f"lane is not on the fused side of the split here")
    dut._log.info(
        "round_once: %d discriminating vectors (%d product-underflow, "
        "%d product-overflow); the captured DUT output matched the FUSED "
        "reference AND differed from the naive model on every one",
        len(disc), len(d_under), len(d_over))


@cocotb.test()
async def round_once_bound_bf16(dut):
    """Bounds the claim above: OUTSIDE the product under/overflow bands the
    bf16 exact product is fp32-representable, so fused == naive and the
    contract is NOT observationally discriminable there. Asserted, not
    assumed — an implementation that rounded the product would still pass
    this test, which is exactly why round_once_discriminator exists."""
    random.seed(0xB0DE)
    await _start(dut)

    cases = []
    for _ in range(20_000):
        # keep both operand exponents moderate -> product exponent in
        # [-124, 126], comfortably inside fp32's normal range
        a = bf16(random.getrandbits(1), random.randint(65, 190),
                 random.getrandbits(7))
        b = bf16(random.getrandbits(1), random.randint(65, 190),
                 random.getrandbits(7))
        cases.append((a, b, rand_f32_normal(-100, 100), DT_BF16))

    same = sum(1 for v in cases
               if G.ref_fma_narrow(*v) == G.naive_fma_narrow(*v))
    assert same == len(cases), (
        f"in-range bf16 products should not discriminate, but {len(cases)-same}"
        " vectors did — the discrimination bound in the module header is wrong")
    await _stream(dut, cases, "round_once_bound_bf16")


@cocotb.test()
async def round_once_bound_f16(dut):
    """f16 product exponents span only [-47, 31], so the exact product is
    ALWAYS a finite in-range fp32 and the fused contract is not
    observationally discriminable in f16 AT ALL. Recorded explicitly so the
    bf16-only discriminator suite is not mistaken for an oversight."""
    random.seed(0xF0DE)
    await _start(dut)

    cases = []
    for _ in range(20_000):
        a = rand_f16_finite() if random.random() < 0.85 \
            else f16(random.getrandbits(1), 0, random.getrandbits(10))
        b = rand_f16_finite() if random.random() < 0.85 \
            else f16(random.getrandbits(1), 0, random.getrandbits(10))
        cases.append((a, b, rand_f32_normal(), DT_F16))

    diff = sum(1 for v in cases
               if G.ref_fma_narrow(*v) != G.naive_fma_narrow(*v))
    assert diff == 0, (
        f"{diff} f16 vectors discriminated fused from naive — the f16 "
        "product-range argument in the module header is wrong")
    await _stream(dut, cases, "round_once_bound_f16")


# ---------------------------------------------------------------------------
# per-vector dtype selection — the two formats interleaved cycle-by-cycle
# ---------------------------------------------------------------------------


@cocotb.test()
async def dtype_interleave(dut):
    """dtype_bf16 is a per-vector input, not a mode register: the lane must
    produce correct results with the format alternating every cycle while
    six vectors are in flight."""
    random.seed(0x1D7E)
    await _start(dut)

    cases = []
    for i in range(8_000):
        if i & 1:
            cases.append((rand_bf16_finite(), rand_bf16_finite(),
                          rand_f32_normal(), DT_BF16))
        else:
            cases.append((rand_f16_finite(), rand_f16_finite(),
                          rand_f32_normal(), DT_F16))

    await _stream(dut, cases, "dtype_interleave")
