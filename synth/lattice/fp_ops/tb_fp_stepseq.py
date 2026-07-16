# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""tb_fp_stepseq — bit-exactness + protocol validation of FP_StepSeq (the
v1.8.0c MU-hosted fp32 step-sequencer unit, spec §23.10) BEFORE synth
Gate 3.

Bit-exactness authority: scripts/golden_fp32.py —
  * FSCALAR sub-ops vs micro_fscalar (FS_ADD/SUB/MUL/FMA are the
    correctly-rounded REFERENCE functions verbatim; FS_DIV is the
    sequencer-faithful micro_div step program),
  * FRSQRT32 vs micro_rsqrt, FEXP2_32 vs micro_exp2.

Every launch also asserts the §23.10.6 protocol: done arrives within the
normative cycle maximum (never asserting an exact count), busy rises with
start and holds through the done cycle, done is a 1-cycle pulse with the
result valid exactly then, and ops launch BACK-TO-BACK (each launch fires
start in the first busy==0 cycle after the previous done — zero idle
cycles between ops).

Directed IEEE coverage: every row of the spec §23.10.5 normative table is
encoded as one or more cells (51 cells / 36 rows), with expected values
taken from the golden entry points, never retyped. NOTE: the referenced
directed set in scripts/fp_release_sweep.py is its 7-vector FEXP2
boundary list (a function-local, and that module needs numpy which the
cocotb venv lacks), so those 7 vectors and the midpoint-adjacent FDIV
recipe are reproduced here with attribution instead of imported.

FRSQRT margin coverage: include/generated/fp_validation_report.json
records only aggregate worst-ulp figures (no per-input list), so per the
task fallback this TB ranks 100k random (parity, mantissa) classes by
float64 error against 1/sqrt and drives the worst 1,000 at random even
exponent offsets (the pinned range reduction makes classes scale-
covariant), plus x = 4^k directed for every k in [-63, 63], plus the
step-order regression canary:

  CANARY 0x55F05DF5 -> 0x343AD02D. Swapping the pinned NR operand order
  (t1 = h*y first) to y*y-first flips the result to 0x343AD02C — a
  1-ulp silent margin eater (§23.10.9 risk 5). Verified against the
  golden model with a deliberately deviated twin before RTL entry.
"""

import math
import random
import struct
import sys
from fractions import Fraction
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "scripts"))
import golden_fp32 as G  # noqa: E402

OPC_FSCALAR = 0x74
OPC_FRSQRT = 0x75
OPC_FEXP2 = 0x76

FS = G.FSCALAR_OP_CODE          # {'FS_ADD':0,...} single-source table

# spec §23.10.6 normative cycle maxima (upper bounds, never exact counts)
MAXC_FSCALAR = {FS["FS_ADD"]: 6, FS["FS_SUB"]: 6, FS["FS_MUL"]: 6,
                FS["FS_FMA"]: 10, FS["FS_DIV"]: 32}
MAXC = {OPC_FSCALAR: MAXC_FSCALAR, OPC_FRSQRT: 34, OPC_FEXP2: 30}

NUM_RANDOM_PER_OP = 20_000

_worst_lat = {}


# ---------------------------------------------------------------------------
# driver
# ---------------------------------------------------------------------------


async def _start_clock(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.start.value = 0
    dut.opcode_in.value = 0
    dut.subop_in.value = 0
    dut.a_in.value = 0
    dut.b_in.value = 0
    dut.c_in.value = 0
    for _ in range(4):
        await FallingEdge(dut.clk)


async def launch(dut, opcode, subop, a, b=0, c=0, label=""):
    """Launch one op back-to-back (start fires in the first idle cycle),
    enforce the §23.10.6 bound + busy/done protocol, return the result."""
    bound = MAXC[opcode] if opcode != OPC_FSCALAR else MAXC_FSCALAR[subop]
    assert int(dut.busy.value) == 0, f"{label}: busy before start"
    assert int(dut.done.value) == 0, f"{label}: stray done before start"
    dut.opcode_in.value = opcode
    dut.subop_in.value = subop
    dut.a_in.value = a
    dut.b_in.value = b
    dut.c_in.value = c
    dut.start.value = 1
    lat = 0
    result = None
    while True:
        await FallingEdge(dut.clk)
        lat += 1
        dut.start.value = 0
        assert int(dut.busy.value) == 1, f"{label}: busy dropped mid-op"
        if int(dut.done.value):
            result = int(dut.result.value)
            break
        assert lat <= bound, (
            f"{label}: no done within the normative bound {bound}")
    assert lat <= bound, f"{label}: done at {lat} > bound {bound}"
    key = (opcode, subop if opcode == OPC_FSCALAR else 0)
    _worst_lat[key] = max(_worst_lat.get(key, 0), lat)
    # done must be a 1-cycle pulse; busy must free in the very next cycle
    await FallingEdge(dut.clk)
    assert int(dut.done.value) == 0, f"{label}: done wider than 1 cycle"
    assert int(dut.busy.value) == 0, f"{label}: busy stuck after done"
    return result


async def check_fscalar(dut, subop, a, b, c=0, label=""):
    exp = G.micro_fscalar(subop, a, b, c)
    got = await launch(dut, OPC_FSCALAR, subop, a, b, c, label)
    assert got == exp, (f"{label}: FSCALAR sub {subop} a={a:#010x} "
                        f"b={b:#010x} c={c:#010x} got {got:#010x} "
                        f"expected {exp:#010x}")


async def check_rsqrt(dut, a, label=""):
    exp = G.micro_rsqrt(a)
    got = await launch(dut, OPC_FRSQRT, 0, a, label=label)
    assert got == exp, (f"{label}: FRSQRT32 a={a:#010x} got {got:#010x} "
                        f"expected {exp:#010x}")
    return got


async def check_exp2(dut, a, label=""):
    exp = G.micro_exp2(a)
    got = await launch(dut, OPC_FEXP2, 0, a, label=label)
    assert got == exp, (f"{label}: FEXP2_32 a={a:#010x} got {got:#010x} "
                        f"expected {exp:#010x}")


def _f2b(x):
    return int.from_bytes(struct.pack(">f", float(x)), "big")


def rand_fp(rng):
    """Random fp32 bit pattern biased toward specials, denormals and
    boundary exponents (golden handles every class)."""
    r = rng.random()
    if r < 0.55:
        return rng.getrandbits(32)
    if r < 0.70:                                    # denormals / zeros
        return (rng.getrandbits(1) << 31) | rng.getrandbits(23)
    if r < 0.80:                                    # Inf / NaN (sNaN too)
        m = rng.getrandbits(23) if rng.random() < 0.5 else 0
        return (rng.getrandbits(1) << 31) | (0xFF << 23) | m
    if r < 0.92:                                    # boundary binades
        e = rng.choice([1, 2, 126, 127, 128, 253, 254])
        return (rng.getrandbits(1) << 31) | (e << 23) | rng.getrandbits(23)
    return rng.choice([0x00000000, 0x80000000, 0x00800000, 0x80800000,
                       0x3F800000, 0xBF800000, 0x7F7FFFFF, 0xFF7FFFFF,
                       0x7F800000, 0xFF800000, 0x7FC00000, 0x7F800001,
                       0x00000001, 0x807FFFFF, 0x3FFFFFFF])


# ---------------------------------------------------------------------------
# directed IEEE table — one or more cells per spec §23.10.5 row (row ids in
# comments; expected values always from the golden entry points)
# ---------------------------------------------------------------------------

QNAN = 0x7FC00000
PINF = 0x7F800000
NINF = 0xFF800000
SNAN = 0x7F800001
FMAX = 0x7F7FFFFF

IEEE_CELLS = [
    # (row, subop-or-None, a, b, c) — None subop means unary rows use 'op'
    ("A1a", FS["FS_ADD"], PINF, PINF, 0),
    ("A1b", FS["FS_ADD"], NINF, NINF, 0),
    ("A2",  FS["FS_ADD"], PINF, NINF, 0),
    ("A3",  FS["FS_ADD"], 0x00000000, 0x80000000, 0),
    ("A4",  FS["FS_ADD"], 0x40490FDB, 0xC0490FDB, 0),
    ("A5a", FS["FS_ADD"], QNAN, 0x3F800000, 0),
    ("A5b", FS["FS_ADD"], SNAN, 0x3F800000, 0),        # sNaN quieted
    ("A5c", FS["FS_MUL"], 0x40000000, QNAN, 0),
    ("A5d", FS["FS_MUL"], SNAN, 0x40000000, 0),
    ("A6a", FS["FS_ADD"], FMAX, FMAX, 0),              # RNE overflow -> +Inf
    ("A6b", FS["FS_MUL"], FMAX, FMAX, 0),
    ("M1a", FS["FS_MUL"], PINF, 0x00000000, 0),
    ("M1b", FS["FS_MUL"], 0x00000000, NINF, 0),
    ("M2",  FS["FS_MUL"], NINF, 0x40400000, 0),
    ("M3",  FS["FS_MUL"], 0x80000000, 0x40400000, 0),  # (-0)*(+3) = -0
    ("Z1a", FS["FS_ADD"], 0x00000001, 0x3F800000, 0),  # denormal DAZ
    ("Z1b", FS["FS_MUL"], 0x00800000, 0x3F800000, 0),  # min_normal passes
    ("Z1c", FS["FS_MUL"], 0x807FFFFF, 0x40000000, 0),  # (-denorm)*2 = -0
    ("F1",  FS["FS_FMA"], 0x3F800001, 0x3F800001, 0xBF800002),  # fused RNE
    ("F2a", FS["FS_FMA"], PINF, 0x00000000, 0x40A00000),
    ("F2b", FS["FS_FMA"], PINF, 0x00000000, QNAN),     # NaN rule wins
    ("F3",  FS["FS_FMA"], PINF, 0x40000000, NINF),
    ("F4",  FS["FS_FMA"], 0x3FC00000, 0x3FA00000, 0xBFF00000),  # -> +0
    ("F5",  FS["FS_FMA"], 0xBF800000, 0x00000000, 0x80000000),  # -0 sign
    ("F5b", FS["FS_FMA"], 0x3F800000, 0x3F800000, QNAN),
    ("V1a", FS["FS_DIV"], 0x40400000, 0x00000000, 0),
    ("V1b", FS["FS_DIV"], 0xC0400000, 0x00000000, 0),
    ("V2",  FS["FS_DIV"], 0x00000000, 0x80000000, 0),
    ("V3",  FS["FS_DIV"], PINF, NINF, 0),
    ("V4",  FS["FS_DIV"], 0x40400000, NINF, 0),
    ("V5",  FS["FS_DIV"], NINF, 0x40000000, 0),
    ("V6",  FS["FS_DIV"], 0xC0C00000, 0x40000000, 0),  # -6/2 = -3 sign-XOR
    ("V7",  FS["FS_DIV"], 0x3F800000, 0x00000001, 0),  # x/denormal (DAZ)
]

IEEE_RSQRT = [
    ("R1", 0x00000000),
    ("R2", 0x80000000),
    ("R3a", 0xBF800000),
    ("R3b", NINF),
    ("R4", PINF),
    ("R5", QNAN),
    ("R6", 0x40800000),                                # rsqrt(4) = 0.5
]

IEEE_EXP2 = [
    ("E1", QNAN),
    ("E2", 0x43000000),                                # 128.0 -> +Inf
    ("E3", 0x40E00000),                                # 7.0 -> 128 exact
    ("E4", 0xC2FE0000),                                # -127 -> +0 (FTZ)
    ("E5a", 0x00000000),
    ("E5b", 0x80000000),
    ("E6a", 0xC2FC0001),                               # just below -126
    ("E6b", 0xC2FBFFFF),                               # just above -126
    ("E7a", 0xC3160000),                               # -150 -> +0
    ("E7b", 0xC315FFFF),                               # just above -150
    ("E8", 0x42FFFFFF),                                # just below 128
]


@cocotb.test()
async def directed_ieee_table(dut):
    await _start_clock(dut)
    n = 0
    for row, sub, a, b, c in IEEE_CELLS:
        await check_fscalar(dut, sub, a, b, c, label=f"IEEE {row}")
        n += 1
    for row, a in IEEE_RSQRT:
        await check_rsqrt(dut, a, label=f"IEEE {row}")
        n += 1
    for row, a in IEEE_EXP2:
        await check_exp2(dut, a, label=f"IEEE {row}")
        n += 1
    dut._log.info("directed IEEE table: %d cells bit-exact "
                  "(all 36 spec rows covered)", n)
    assert n == len(IEEE_CELLS) + len(IEEE_RSQRT) + len(IEEE_EXP2)


# ---------------------------------------------------------------------------
# per-op random sweeps (20,000 each) vs the golden entry points
# ---------------------------------------------------------------------------


async def _fscalar_sweep(dut, subop, seed, name, use_c=False):
    rng = random.Random(seed)
    for i in range(NUM_RANDOM_PER_OP):
        a, b = rand_fp(rng), rand_fp(rng)
        c = rand_fp(rng) if use_c else 0
        await check_fscalar(dut, subop, a, b, c, label=f"{name}[{i}]")
    dut._log.info("%s: %d random vectors bit-exact (worst latency %d)",
                  name, NUM_RANDOM_PER_OP,
                  _worst_lat[(OPC_FSCALAR, subop)])


@cocotb.test()
async def fscalar_add_random(dut):
    await _start_clock(dut)
    await _fscalar_sweep(dut, FS["FS_ADD"], 0xADD1, "fs_add")


@cocotb.test()
async def fscalar_sub_random(dut):
    await _start_clock(dut)
    await _fscalar_sweep(dut, FS["FS_SUB"], 0x5AB1, "fs_sub")


@cocotb.test()
async def fscalar_mul_random(dut):
    await _start_clock(dut)
    await _fscalar_sweep(dut, FS["FS_MUL"], 0x3A11, "fs_mul")


@cocotb.test()
async def fscalar_fma_random(dut):
    await _start_clock(dut)
    await _fscalar_sweep(dut, FS["FS_FMA"], 0xF3A1, "fs_fma", use_c=True)


@cocotb.test()
async def fscalar_div_random(dut):
    await _start_clock(dut)
    await _fscalar_sweep(dut, FS["FS_DIV"], 0xD1F1, "fs_div")


@cocotb.test()
async def fdiv_adversarial(dut):
    """Midpoint-adjacent quotients (recipe reproduced from
    scripts/fp_release_sweep.py sweep_fdiv — a = RN32(b*(2M+1)*2^-24) so
    a/b sits ~2^-25 from an RNE midpoint, where random sampling has no
    power) + x/x (the q24 -> 2^24 carry path) + exponent-extreme packs."""
    await _start_clock(dut)
    rng = random.Random(0xD1F)
    n = 0
    for i in range(2_000):
        eb = rng.randint(-60, 60)
        b = ((eb + 127) << 23) | rng.getrandbits(23)
        mq = (1 << 23) + rng.getrandbits(23)
        qmid = Fraction(2 * mq + 1, 1 << 24)
        a = G.pack_rne_ftz(0, G.bits_to_frac(b) * qmid)
        await check_fscalar(dut, FS["FS_DIV"], a, b, label=f"div_mid[{i}]")
        n += 1
    for i in range(500):
        x = ((rng.getrandbits(1) << 31) | (rng.randint(1, 254) << 23)
             | rng.getrandbits(23))
        await check_fscalar(dut, FS["FS_DIV"], x, x, label=f"div_xx[{i}]")
        n += 1
    for i in range(1_000):                       # overflow/FTZ at pack only
        ea = rng.choice([rng.randint(1, 30), rng.randint(224, 254)])
        eb = rng.choice([rng.randint(1, 30), rng.randint(224, 254)])
        a = (rng.getrandbits(1) << 31) | (ea << 23) | rng.getrandbits(23)
        b = (rng.getrandbits(1) << 31) | (eb << 23) | rng.getrandbits(23)
        await check_fscalar(dut, FS["FS_DIV"], a, b, label=f"div_ext[{i}]")
        n += 1
    dut._log.info("fdiv_adversarial: %d vectors bit-exact", n)


@cocotb.test()
async def frsqrt_random(dut):
    await _start_clock(dut)
    rng = random.Random(0x55EE)
    for i in range(NUM_RANDOM_PER_OP):
        await check_rsqrt(dut, rand_fp(rng), label=f"rsqrt_rand[{i}]")
    dut._log.info("frsqrt_random: %d vectors bit-exact (worst latency %d)",
                  NUM_RANDOM_PER_OP, _worst_lat[(OPC_FRSQRT, 0)])


@cocotb.test()
async def frsqrt_margin_pow4_canary(dut):
    """1,000 near-worst classes (fp_validation_report.json carries no
    per-input worst list, so rank 100k random classes by float64 error —
    task fallback), x = 4^k bit-exact for every k, and the pinned
    step-order canary (see module docstring)."""
    await _start_clock(dut)
    rng = random.Random(0x9A61)

    ranked = []
    for _ in range(100_000):
        cls = rng.randrange(1 << 24)
        par, m = cls >> 23, cls & 0x7FFFFF
        bits = ((127 + par) << 23) | m
        res = G.micro_rsqrt(bits)
        val = math.ldexp((res & 0x7FFFFF) + (1 << 23),
                         ((res >> 23) & 0xFF) - 150)
        xprime = math.ldexp((1 << 23) + m, par - 23)
        err = abs(val - 1.0 / math.sqrt(xprime)) * (1 << 24)
        ranked.append((err, par, m))
    ranked.sort(reverse=True)

    n = 0
    for err, par, m in ranked[:1000]:
        j = rng.randint(-62, 62)                 # scale-covariant offset
        e = 127 + par + 2 * j
        if not 1 <= e <= 254:
            e = 127 + par
        a = (e << 23) | m
        await check_rsqrt(dut, a, label=f"rsqrt_worst[{n}]")
        n += 1
    dut._log.info("frsqrt near-worst classes: %d bit-exact "
                  "(worst sampled model error %.4f ulp)", n, ranked[0][0])

    for k in range(-63, 64):                     # R6: 4^k -> exact 2^-k
        a = (2 * k + 127) << 23
        got = await check_rsqrt(dut, a, label=f"rsqrt_pow4[{k}]")
        assert got == ((-k + 127) << 23), f"4^{k} not bit-exact 2^-{k}"
    dut._log.info("frsqrt 4^k: 127 bit-exact power cells")

    got = await check_rsqrt(dut, 0x55F05DF5, label="rsqrt_canary")
    assert got == 0x343AD02D, (
        f"step-order canary got {got:#010x}: 0x343AD02C means the NR body "
        f"ran y*y before h*y — the pinned order is t1 = h*y FIRST")
    dut._log.info("frsqrt step-order canary: pinned h*y-first confirmed")


@cocotb.test()
async def fexp2_random(dut):
    await _start_clock(dut)
    rng = random.Random(0xE412)
    for i in range(NUM_RANDOM_PER_OP):
        await check_exp2(dut, rand_fp(rng), label=f"exp2_rand[{i}]")
    dut._log.info("fexp2_random: %d vectors bit-exact (worst latency %d)",
                  NUM_RANDOM_PER_OP, _worst_lat[(OPC_FEXP2, 0)])


@cocotb.test()
async def fexp2_boundaries(dut):
    """Both boundary windows directed (spec E6/E8: the underflow sliver
    below -126 is FTZ(RN_unbounded), the overflow side goes through the
    pack's RNE) + ALL integers in [-150, 128] (E3/E4 bypass) + the seven
    directed boundary vectors reproduced from fp_release_sweep.py."""
    await _start_clock(dut)
    n = 0
    for base in (0xC2FC0000, 0x43000000):        # windows around -126, 128
        for off in range(-512, 513):
            await check_exp2(dut, (base + off) & 0xFFFFFFFF,
                             label=f"exp2_win[{base:#x}{off:+d}]")
            n += 1
    for k in range(-150, 129):
        await check_exp2(dut, _f2b(k), label=f"exp2_int[{k}]")
        n += 1
    directed = [0xC2FC0000, 0xC2FC0001, 0xC2FBFFFF, 0x43000000,
                0x42FFFFFF, 0xC3160000, 0xC315FFFF]  # fp_release_sweep set
    for a in directed:
        await check_exp2(dut, a, label=f"exp2_dir[{a:#010x}]")
        n += 1
    dut._log.info("fexp2_boundaries: %d directed vectors bit-exact", n)


# ---------------------------------------------------------------------------
# protocol: back-to-back mixed ops (launch() itself proves zero-idle-cycle
# relaunch; this stresses cross-op state reuse of the shared temps)
# ---------------------------------------------------------------------------


@cocotb.test()
async def back_to_back_mixed(dut):
    await _start_clock(dut)
    rng = random.Random(0xB2B)
    ops = ([(OPC_FSCALAR, s) for s in FS.values()]
           + [(OPC_FRSQRT, 0), (OPC_FEXP2, 0)])
    for i in range(2_000):
        opc, sub = rng.choice(ops)
        a, b = rand_fp(rng), rand_fp(rng)
        c = rand_fp(rng)
        if opc == OPC_FSCALAR:
            await check_fscalar(dut, sub, a, b, c, label=f"b2b[{i}]")
        elif opc == OPC_FRSQRT:
            await check_rsqrt(dut, a, label=f"b2b[{i}]")
        else:
            await check_exp2(dut, a, label=f"b2b[{i}]")
    lat_str = ", ".join(f"{k}:{v}" for k, v in sorted(_worst_lat.items()))
    dut._log.info("back_to_back_mixed: 2000 mixed ops bit-exact; "
                  "worst latencies {%s}", lat_str)
