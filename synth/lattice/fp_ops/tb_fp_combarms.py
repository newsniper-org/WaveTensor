# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""tb_fp_combarms — bit-exactness of the v1.8.0e 0e1 combinational
MU-arm datapaths (spec §25.2.1 0x79 FMINMAX / §25.2.3 0x6B GAMMA_MUL_W)
against scripts/golden_fp32.py, via the FP_CombArms unit top that
instantiates THE single-source functions of include/fp_comb_arms.vh —
the same functions the PE_Core.v dispatch arms slice.

FMINMAX coverage (the six frozen §25.2.1 rows, every one by name):
  * the pinned 16-pattern total-order ladder (reproduced with
    attribution from scripts/fp_release_sweep.py FMM_LADDER — that
    module needs numpy which this venv lacks): ALL 256 ordered pairs x
    both sub-ops, packed 4 lanes/vector — rows 1 (-0/+0 both
    directions), 5 (offset-transform total order) and 6 (denormal cells
    BIT-PATTERN-PRESERVING, DAZ-EXEMPT: the ladder's four denormal
    patterns must come back bit-identical, which any DAZ stage would
    flush);
  * the NaN pool (qNaN/sNaN, both signs, payload spread) x every ladder
    number, both operand orders and both sub-ops — row 2 (one NaN ->
    the NUMBER, bit pattern unchanged, a lone sNaN still loses);
  * NaN x NaN pool exhaustive — rows 3+4 (canonical 0x7FC00000, sNaN
    quieted, sign dropped);
  * 20,000 random 4-lane vectors x random broadcast B x random sub-op
    vs golden fminmax_frags (per-lane independence: four DIFFERENT
    patterns per vector).

GAMMA_MUL_W coverage:
  * ALL 256 (a4, g4) pairs EXACT — 16 vectors, vector j driving lane i
    with (a4 = i, g4 = j), so the exhaustive product table and the lane
    map are proven together;
  * the lane-order pin directed cell (distinct per-lane values, result
    lane i asserted at bits [8i+7:8i] against ref_gamma_mul_w_lane);
  * range-proof extremes ((-8)x(-8) = +64, (-8)x7 = -56, 7x7 = 49);
  * 20,000 random (a64, g64) pairs vs golden gamma_mul_w_frags.
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

FMM_MIN = G.FMINMAX_OP_CODE["MINIMUMNUM"]
FMM_MAX = G.FMINMAX_OP_CODE["MAXIMUMNUM"]

# the pinned total-order ladder + NaN pool — reproduced with attribution
# from scripts/fp_release_sweep.py (see module docstring)
FMM_LADDER = [
    0xFF800000, 0xFF7FFFFF, 0xC0490FDB, 0xBF800000,
    0x80800000, 0x807FFFFF, 0x80000001, 0x80000000,
    0x00000000, 0x00000001, 0x007FFFFF, 0x00800000,
    0x3F800000, 0x40490FDB, 0x7F7FFFFF, 0x7F800000,
]
FMM_NAN_POOL = [0x7FC00000, 0xFFC00000, 0x7F800001, 0xFF800001,
                0x7FFFFFFF, 0x7FBFFFFF]


async def _start_clock(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.fmm_a.value = 0
    dut.fmm_b.value = 0
    dut.fmm_max.value = 0
    dut.gmw_a.value = 0
    dut.gmw_g.value = 0
    for _ in range(2):
        await FallingEdge(dut.clk)


async def fmm_vec(dut, lanes, b, subop, label=""):
    """Drive one 4-lane FMINMAX vector, return the 4 result lanes;
    checked against golden ref_fminmax + the fragment wrapper."""
    a = 0
    for i, lane in enumerate(lanes):
        a |= (lane & 0xFFFFFFFF) << (32 * i)
    dut.fmm_a.value = a
    dut.fmm_b.value = b
    dut.fmm_max.value = 1 if subop == FMM_MAX else 0
    await FallingEdge(dut.clk)
    got = int(dut.fmm_y.value)
    got_lanes = [(got >> (32 * i)) & 0xFFFFFFFF for i in range(4)]
    exp_lanes = G.ref_fminmax(lanes, b, subop)
    assert got_lanes == exp_lanes, (
        f"{label}: lanes={[hex(x) for x in lanes]} b={b:#010x} sub={subop} "
        f"got={[hex(x) for x in got_lanes]} exp={[hex(x) for x in exp_lanes]}")
    # fragment wrapper lockstep (lane map pin, 2 frags in = 2 out)
    frags = G.fminmax_frags(G.lanes_to_frags(lanes, 32), b, subop)
    assert got == (frags[1] << 64) | frags[0], f"{label}: frag map diverged"
    return got_lanes


async def gmw_vec(dut, a_lanes, g_lanes, label=""):
    """Drive one 16-lane GAMMA_MUL_W vector, return the 16 int8 result
    lanes; checked against golden ref_gamma_mul_w + the frag wrapper."""
    a = g = 0
    for i in range(16):
        a |= (a_lanes[i] & 0xF) << (4 * i)
        g |= (g_lanes[i] & 0xF) << (4 * i)
    dut.gmw_a.value = a
    dut.gmw_g.value = g
    await FallingEdge(dut.clk)
    got = int(dut.gmw_y.value)
    got_lanes = [(got >> (8 * i)) & 0xFF for i in range(16)]
    exp_lanes = G.ref_gamma_mul_w(a_lanes, g_lanes)
    assert got_lanes == exp_lanes, (
        f"{label}: a={[hex(x) for x in a_lanes]} g={[hex(x) for x in g_lanes]}"
        f" got={[hex(x) for x in got_lanes]} exp={[hex(x) for x in exp_lanes]}")
    frags = G.gamma_mul_w_frags(a, g)
    assert got == (frags[1] << 64) | frags[0], f"{label}: frag map diverged"
    return got_lanes


# ---------------------------------------------------------------------------
# 0x79 FMINMAX
# ---------------------------------------------------------------------------


@cocotb.test()
async def fminmax_ladder_total_order(dut):
    """Rows 1/5/6: all 256 ordered ladder pairs x both sub-ops. Expected
    = the ladder-lower/upper pattern BIT-EXACTLY (asserted literally
    from the ladder index, oracle-free, on top of the golden lockstep in
    fmm_vec) — the denormal pairs are the DAZ-EXEMPT proof."""
    await _start_clock(dut)
    n = 0
    for j, b in enumerate(FMM_LADDER):
        for sub in (FMM_MIN, FMM_MAX):
            # pack 4 ladder entries per vector: lanes i..i+3 vs b
            for base in range(0, 16, 4):
                lanes = FMM_LADDER[base:base + 4]
                got = await fmm_vec(dut, lanes, b, sub,
                                    label=f"ladder[{base}/{j}/{sub}]")
                for k, lane in enumerate(lanes):
                    i = base + k
                    exp = FMM_LADDER[min(i, j) if sub == FMM_MIN
                                     else max(i, j)]
                    assert got[k] == exp, (
                        f"total order broke at ladder pair ({i},{j}) "
                        f"sub={sub}: got {got[k]:#010x} exp {exp:#010x}")
                    n += 1
    dut._log.info("fminmax ladder: %d ordered-pair cells bit-exact "
                  "(rows 1/5/6 incl. denormal bit-preservation)", n)
    assert n == 16 * 16 * 2


@cocotb.test()
async def fminmax_nan_rows(dut):
    """Rows 2/3/4: one-NaN -> the number (bit-preserved, both operand
    orders — lanes carry the NaN side, B the number side and vice
    versa); both-NaN -> canonical 0x7FC00000 (sNaN quieted, sign
    dropped)."""
    await _start_clock(dut)
    n = 0
    for nn in FMM_NAN_POOL:
        for sub in (FMM_MIN, FMM_MAX):
            for base in range(0, 16, 4):
                nums = FMM_LADDER[base:base + 4]
                got = await fmm_vec(dut, [nn] * 4, nums[0], sub,
                                    label=f"nan_a[{nn:#x}]")
                assert got == [nums[0]] * 4, "NaN lane must lose to B"
                got = await fmm_vec(dut, nums, nn, sub,
                                    label=f"nan_b[{nn:#x}]")
                assert got == nums, "NaN B must lose, numbers bit-preserved"
                n += 8
        for nb in FMM_NAN_POOL:
            for sub in (FMM_MIN, FMM_MAX):
                got = await fmm_vec(dut, [nn] * 4, nb, sub,
                                    label=f"nan_nan[{nn:#x}/{nb:#x}]")
                assert got == [0x7FC00000] * 4, \
                    "both-NaN must give canonical qNaN"
                n += 4
    dut._log.info("fminmax NaN rows: %d cells bit-exact", n)


@cocotb.test()
async def fminmax_random(dut):
    """20,000 random 4-lane vectors (specials-biased pool mixed with raw
    32-bit random, DIFFERENT pattern per lane) x random B x random
    sub-op vs golden."""
    await _start_clock(dut)
    rng = random.Random(0xF79A)
    pool = FMM_LADDER + FMM_NAN_POOL + [0x00000005, 0x80000005]

    def rnd32():
        return rng.choice(pool) if rng.random() < 0.20 else rng.getrandbits(32)

    for i in range(20_000):
        lanes = [rnd32() for _ in range(4)]
        await fmm_vec(dut, lanes, rnd32(), rng.choice((FMM_MIN, FMM_MAX)),
                      label=f"fmm_rand[{i}]")
    dut._log.info("fminmax random: 20000 4-lane vectors bit-exact")


# ---------------------------------------------------------------------------
# 0x6B GAMMA_MUL_W
# ---------------------------------------------------------------------------


@cocotb.test()
async def gamma_exhaustive_256_and_lane_pin(dut):
    """ALL 256 (a4, g4) pairs exact — 16 vectors, vector j drives lane i
    with (a4 = i, g4 = j) so the product table and the lane map are
    proven together; plus the lane-order directed cell and the
    range-proof extremes asserted literally."""
    await _start_clock(dut)
    for j in range(16):
        await gmw_vec(dut, list(range(16)), [j] * 16, label=f"exh[g={j}]")
    # lane-order pin: distinct per-lane values, literal expectations
    a_l = [(3 * i + 1) % 16 for i in range(16)]
    g_l = [(5 * i + 7) % 16 for i in range(16)]
    got = await gmw_vec(dut, a_l, g_l, label="lane_pin")
    for i in range(16):
        assert got[i] == G.ref_gamma_mul_w_lane(a_l[i], g_l[i]), \
            f"lane {i} not at bits [{8 * i + 7}:{8 * i}]"
    # extremes: (-8)x(-8)=+64, (-8)x7=-56, 7x7=49 (int8 fields)
    got = await gmw_vec(dut, [0x8, 0x8, 0x7, 0x0] * 4,
                        [0x8, 0x7, 0x7, 0x8] * 4, label="extremes")
    assert got[0] == 64 and got[1] == ((-56) & 0xFF) and got[2] == 49 \
        and got[3] == 0, "range-proof extremes broke"
    dut._log.info("gamma exhaustive 256 pairs + lane pin + extremes exact")


@cocotb.test()
async def gamma_random(dut):
    """20,000 random 64b x 64b lane vectors vs golden."""
    await _start_clock(dut)
    rng = random.Random(0x6BA)
    for i in range(20_000):
        a = rng.getrandbits(64)
        g = rng.getrandbits(64)
        await gmw_vec(dut, [(a >> (4 * k)) & 0xF for k in range(16)],
                      [(g >> (4 * k)) & 0xF for k in range(16)],
                      label=f"gmw_rand[{i}]")
    dut._log.info("gamma random: 20000 vectors bit-exact")
