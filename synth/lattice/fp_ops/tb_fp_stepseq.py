# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""tb_fp_stepseq — bit-exactness + protocol validation of FP_StepSeq (the
v1.8.0c MU-hosted fp32 step-sequencer unit, spec §23.10) BEFORE synth
Gate 3, extended for the v1.8.0d OPS_CVT / OPS_ACCEW op classes (spec
§23.10.10) BEFORE synth Gate C3.

Bit-exactness authority: scripts/golden_fp32.py —
  * FSCALAR sub-ops vs micro_fscalar (FS_ADD/SUB/MUL/FMA are the
    correctly-rounded REFERENCE functions verbatim; FS_DIV is the
    sequencer-faithful micro_div step program),
  * FRSQRT32 vs micro_rsqrt, FEXP2_32 vs micro_exp2,
  * 0x77 CVT vs micro_cvt (== ref_cvt everywhere except the dtype-0x4
    I2F, whose sequencer twin is the pinned two-pass micro_i2f_acc),
  * 0x73 ACC_ELEMWISE vs micro_accew (== ref_fma / micro_fscalar(FS_FMA)).

v1.8.0d coverage plan (§23.10.10 + the design test plan): 20,000 random
vectors PER (sub-op x dtype) CVT form and per ACCEW, 2^14 sampled widen
per format (model-side widen coverage is exhaustive in the golden
sweeps) + directed exhaustive f16/bf16 subnormal and NaN-class rows,
narrow boundary slivers (per-ULP RNE ties, the 0x477FF000 overflow band,
the FTZ band incl. round-up-to-min-normal survivors, NaN
canonicalization, the 0x007FFF80-0x007FFFFF DAZ sliver), the bf16
exact-tie/sticky-disjointness set, the 62 I2F two-pass RTO-then-RNE
discriminators (bl 33..63, both signs — an RNE-then-RNE pass 1 fails
them), F2I tie/rail/Inf/NaN rows, the DAZ-bypass regression (I2F(5) must
be 5.0f, not 0 — the confirmed capture-mux bug — plus the converse
NARROW/F2I flush), cycle-bound + back-to-back asserts on every launch,
and the FULL existing v1.8.0c 12-suite set re-run unchanged (the op_sel
3->4 bit widening touches every case tree — Gate C3 re-proof).

The full v1.8.0c 12-suite regression set below is UNCHANGED except for
the launch() dtype plumbing (default 0) and the mixed back-to-back op
list gaining the new ops.

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

OPC_ACCEW = 0x73                # v1.8.0d §23.10.10(c)
OPC_FSCALAR = 0x74
OPC_FRSQRT = 0x75
OPC_FEXP2 = 0x76
OPC_CVT = 0x77                  # v1.8.0d §23.10.10(b)

FS = G.FSCALAR_OP_CODE          # {'FS_ADD':0,...} single-source table
CVT_WID = G.CVT_WIDEN_TO_F32    # golden pins == generated cvt_op_codes
CVT_NAR = G.CVT_NARROW_FROM_F32

# spec §23.10.6 + §23.10.10(e) normative cycle maxima (upper bounds,
# never exact counts)
MAXC_FSCALAR = {FS["FS_ADD"]: 6, FS["FS_SUB"]: 6, FS["FS_MUL"]: 6,
                FS["FS_FMA"]: 10, FS["FS_DIV"]: 32}
MAXC = {OPC_FSCALAR: MAXC_FSCALAR, OPC_FRSQRT: 34, OPC_FEXP2: 30,
        OPC_ACCEW: 10}
MAXC_CVT = 8                    # widen / narrow / I2F-small / F2I
MAXC_CVT_I64 = 10               # I2F dtype 0x4 (int64 two-pass)

NUM_RANDOM_PER_OP = 20_000

_worst_lat = {}


def _bound_of(opcode, subop, dtype):
    if opcode == OPC_FSCALAR:
        return MAXC_FSCALAR[subop]
    if opcode == OPC_CVT:
        return (MAXC_CVT_I64 if (subop == CVT_WID and dtype == 4)
                else MAXC_CVT)
    return MAXC[opcode]


# ---------------------------------------------------------------------------
# driver
# ---------------------------------------------------------------------------


async def _start_clock(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.start.value = 0
    dut.opcode_in.value = 0
    dut.subop_in.value = 0
    dut.dtype_in.value = 0
    dut.a_in.value = 0
    dut.b_in.value = 0
    dut.c_in.value = 0
    for _ in range(4):
        await FallingEdge(dut.clk)


async def launch(dut, opcode, subop, a, b=0, c=0, label="", dtype=0):
    """Launch one op back-to-back (start fires in the first idle cycle),
    enforce the §23.10.6/§23.10.10(e) bound + busy/done protocol, return
    the result."""
    bound = _bound_of(opcode, subop, dtype)
    assert int(dut.busy.value) == 0, f"{label}: busy before start"
    assert int(dut.done.value) == 0, f"{label}: stray done before start"
    dut.opcode_in.value = opcode
    dut.subop_in.value = subop
    dut.dtype_in.value = dtype
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
    if opcode == OPC_FSCALAR:
        key = (opcode, subop)
    elif opcode == OPC_CVT:
        key = (opcode, (subop << 4) | dtype)
    else:
        key = (opcode, 0)
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


async def check_cvt(dut, subop, dtype, payload, label=""):
    """0x77 CVT vs golden micro_cvt. The 64-bit payload_a row enters on
    the PINNED ingress split: payload[31:0] -> a_in, payload[63:32] ->
    c_in (§23.10.10(b), consumed only by the dtype-0x4 I2F; the other
    forms must IGNORE the high word — random payloads prove it). The
    unit returns the low 32 bits of the result payload row (f16/bf16
    zero-extend, f32 verbatim, ints int32 pattern); the sext64 row
    assembly is PE_Core's (integration stage), so the golden row's high
    word is checked model-side for sext consistency here."""
    payload &= (1 << 64) - 1
    row = G.micro_cvt(subop, dtype, payload)
    exp = row & 0xFFFFFFFF
    # model-side row-format consistency (int results sext64, fp zero-ext)
    if subop == CVT_NAR and dtype in (0, 1, 4):
        assert (row >> 32) == (0xFFFFFFFF if (exp >> 31) else 0), \
            f"{label}: golden F2I row not sext64"
    else:
        assert (row >> 32) == 0, f"{label}: golden row not zero-extended"
    got = await launch(dut, OPC_CVT, subop, payload & 0xFFFFFFFF, 0,
                       (payload >> 32) & 0xFFFFFFFF, label=label,
                       dtype=dtype)
    assert got == exp, (f"{label}: CVT sub={subop} dt={dtype} "
                        f"payload={payload:#018x} got {got:#010x} "
                        f"expected {exp:#010x}")
    return got


async def check_accew(dut, a, b_payload, label=""):
    """0x73 ACC_ELEMWISE (OPREF form) vs golden micro_accew ==
    ref_fma(a, B[63:32], B[31:0]): B rides b_in/c_in as B_hi/B_lo."""
    b_payload &= (1 << 64) - 1
    exp = G.micro_accew(a, b_payload)
    got = await launch(dut, OPC_ACCEW, 0, a, (b_payload >> 32) & 0xFFFFFFFF,
                       b_payload & 0xFFFFFFFF, label=label)
    assert got == exp, (f"{label}: ACCEW a={a:#010x} B={b_payload:#018x} "
                        f"got {got:#010x} expected {exp:#010x}")
    return got


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
    """v1.8.0d: the 0c mix gains every CVT form + ACCEW — cross-op state
    reuse of the shared temps (t_u/t_prod/y_r/n_q/sres_q/i64_q) is the
    thing this suite stresses, and the new classes share all of them."""
    await _start_clock(dut)
    rng = random.Random(0xB2B)
    ops = ([("FS", s) for s in FS.values()]
           + [("RSQRT", 0), ("EXP2", 0), ("ACCEW", 0)]
           + [("CVT", (CVT_WID, dt)) for dt in (0, 1, 2, 3, 4)]
           + [("CVT", (CVT_NAR, dt)) for dt in (0, 1, 2, 3, 4)])
    for i in range(3_000):
        kind, sel = rng.choice(ops)
        a, b = rand_fp(rng), rand_fp(rng)
        c = rand_fp(rng)
        if kind == "FS":
            await check_fscalar(dut, sel, a, b, c, label=f"b2b[{i}]")
        elif kind == "RSQRT":
            await check_rsqrt(dut, a, label=f"b2b[{i}]")
        elif kind == "EXP2":
            await check_exp2(dut, a, label=f"b2b[{i}]")
        elif kind == "ACCEW":
            await check_accew(dut, a, (b << 32) | c, label=f"b2b[{i}]")
        else:
            sub, dt = sel
            await check_cvt(dut, sub, dt, (c << 32) | a, label=f"b2b[{i}]")
    lat_str = ", ".join(f"{k}:{v}" for k, v in sorted(_worst_lat.items()))
    dut._log.info("back_to_back_mixed: 3000 mixed ops bit-exact; "
                  "worst latencies {%s}", lat_str)


# ===========================================================================
# v1.8.0d — 0x77 CVT / 0x73 ACC_ELEMWISE suites (spec §23.10.10, Gate C3)
# ===========================================================================


def _rand_payload64(rng):
    return rng.getrandbits(64)


def _rand_i64_stratified(rng):
    """int64 payloads stratified by magnitude bit-length so every
    normalize shift amount and both two-pass regimes (bl <= 32 exact,
    bl > 32 jammed) are exercised; plain 64-bit random alone almost
    always lands at bl 63-64."""
    bl = rng.randint(0, 63)
    mag = rng.getrandbits(bl) | (1 << bl if bl else 0)
    if rng.getrandbits(1):
        return (-mag) & ((1 << 64) - 1)
    return mag


@cocotb.test()
async def cvt_widen_f16_random_sampled(dut):
    """20,000 random 64-bit payloads (high 48 bits garbage — the widen
    form must ignore everything above [15:0]) + a 2^14 distinct-pattern
    sample + directed exhaustive subnormal/NaN-class rows (the model-side
    widen coverage is exhaustive in the golden sweeps)."""
    await _start_clock(dut)
    rng = random.Random(0xF16)
    for i in range(NUM_RANDOM_PER_OP):
        await check_cvt(dut, CVT_WID, 2, _rand_payload64(rng),
                        label=f"wf16_rand[{i}]")
    n = 0
    for h in rng.sample(range(1 << 16), 1 << 14):
        await check_cvt(dut, CVT_WID, 2, h, label=f"wf16_smp[{h:#06x}]")
        n += 1
    for m in range(1, 1 << 10):                  # ALL f16 subnormals, +/-
        await check_cvt(dut, CVT_WID, 2, m, label=f"wf16_sub[{m}]")
        await check_cvt(dut, CVT_WID, 2, 0x8000 | m, label=f"wf16_subn[{m}]")
        n += 2
    for h in (0x0000, 0x8000, 0x7C00, 0xFC00, 0x7C01, 0xFC01, 0x7E00,
              0x7FFF, 0xFFFF, 0x3C00, 0x0400, 0x8400, 0x7BFF, 0xFBFF):
        await check_cvt(dut, CVT_WID, 2, h, label=f"wf16_dir[{h:#06x}]")
        n += 1
    dut._log.info("cvt_widen_f16: %d random + %d sampled/directed bit-exact",
                  NUM_RANDOM_PER_OP, n)


@cocotb.test()
async def cvt_widen_bf16_random_sampled(dut):
    """Same plan for bf16, incl. ALL 254 subnormal patterns x both signs
    -> signed zero (§23.10.10(f) pin 6) and NaN canonicalization."""
    await _start_clock(dut)
    rng = random.Random(0xBF16)
    for i in range(NUM_RANDOM_PER_OP):
        await check_cvt(dut, CVT_WID, 3, _rand_payload64(rng),
                        label=f"wbf_rand[{i}]")
    n = 0
    for b in rng.sample(range(1 << 16), 1 << 14):
        await check_cvt(dut, CVT_WID, 3, b, label=f"wbf_smp[{b:#06x}]")
        n += 1
    for m in range(1, 1 << 7):                   # ALL bf16 subnormals, +/-
        await check_cvt(dut, CVT_WID, 3, m, label=f"wbf_sub[{m}]")
        await check_cvt(dut, CVT_WID, 3, 0x8000 | m, label=f"wbf_subn[{m}]")
        n += 2
    for b in (0x0000, 0x8000, 0x7F80, 0xFF80, 0x7F81, 0xFF81, 0x7FC0,
              0x7FFF, 0xFFFF, 0x3F80, 0x0080, 0x8080, 0x7F7F, 0xFF7F):
        await check_cvt(dut, CVT_WID, 3, b, label=f"wbf_dir[{b:#06x}]")
        n += 1
    dut._log.info("cvt_widen_bf16: %d random + %d sampled/directed bit-exact",
                  NUM_RANDOM_PER_OP, n)


@cocotb.test()
async def cvt_i2f_random(dut):
    """20,000 random per I2F dtype: int4/int8 with full-64-bit garbage
    payloads (only the low nibble/byte may matter), dtype 0x4 stratified
    by bit-length + full random + int32-shaped values."""
    await _start_clock(dut)
    rng = random.Random(0x12F)
    for i in range(NUM_RANDOM_PER_OP):
        await check_cvt(dut, CVT_WID, 0, _rand_payload64(rng),
                        label=f"i2f4_rand[{i}]")
    for i in range(NUM_RANDOM_PER_OP):
        await check_cvt(dut, CVT_WID, 1, _rand_payload64(rng),
                        label=f"i2f8_rand[{i}]")
    for i in range(NUM_RANDOM_PER_OP):
        r = rng.random()
        if r < 0.5:
            v = _rand_i64_stratified(rng)
        elif r < 0.75:
            v = rng.getrandbits(64)
        else:                                    # int32-shaped (sext64)
            v = rng.getrandbits(32)
            v = (v - (1 << 32)) & ((1 << 64) - 1) if (v >> 31) else v
        await check_cvt(dut, CVT_WID, 4, v, label=f"i2f64_rand[{i}]")
    dut._log.info("cvt_i2f: 3 x %d random bit-exact", NUM_RANDOM_PER_OP)


@cocotb.test()
async def cvt_i2f_int64_two_pass_discriminators(dut):
    """The 62 directed int64 vectors whose pass-1 rounding would
    manufacture a 24-bit midpoint: v = 2^(bl-1) + 2^(bl-24) + (2^(bl-25)
    - 1) for bl in 33..63, both signs (the golden micro_i2f_acc docstring
    counterexample generalized). A pass-1 RNE rounds the sub-midpoint
    field UP onto the midpoint and pass 2 resolves the manufactured tie
    upward — +1 ulp; the pinned pass-1 RTO jam keeps the field below the
    midpoint. Plus int32 exactness below 2^24 and extremes."""
    await _start_clock(dut)
    n = 0
    for bl in range(33, 64):
        v = (1 << (bl - 1)) + (1 << (bl - 24)) + ((1 << (bl - 25)) - 1)
        assert G.micro_i2f_acc(v) == G.ref_i2f(v, 4)     # model self-check
        await check_cvt(dut, CVT_WID, 4, v, label=f"i2f_disc[+{bl}]")
        await check_cvt(dut, CVT_WID, 4, (-v) & ((1 << 64) - 1),
                        label=f"i2f_disc[-{bl}]")
        n += 2
    assert n == 62
    directed = [0, 1, (1 << 64) - 1, 1 << 63, (1 << 63) - 1,
                (1 << 24) - 1, 1 << 24, (1 << 24) + 1,
                0xFFFFFFFF7FFFFFFF,                      # int32 min sext64
                0x000000007FFFFFFF, 0xFFFFFFFF80000000,
                (1 << 40) + (1 << 17) + 0xFFFF]          # docstring vector
    for v in directed:
        await check_cvt(dut, CVT_WID, 4, v, label=f"i2f_dir[{v:#x}]")
        n += 1
    for k in range(0, 24):                               # exact powers
        await check_cvt(dut, CVT_WID, 4, 1 << k, label=f"i2f_pow[{k}]")
        n += 1
    dut._log.info("cvt_i2f_int64 discriminators+directed: %d bit-exact", n)


@cocotb.test()
async def cvt_narrow_random(dut):
    """20,000 random per narrow dtype (fp32-biased low word via rand_fp +
    garbage high word), vs the ONE golden narrow authority
    ref_narrow_f32 (== the shared include/fp_narrow_f32.vh function —
    the 0x7C bit-identity clause's RTL-side sampled leg at the MU site)."""
    await _start_clock(dut)
    rng = random.Random(0x0A11)
    for i in range(NUM_RANDOM_PER_OP):
        p = (rng.getrandbits(32) << 32) | rand_fp(rng)
        await check_cvt(dut, CVT_NAR, 2, p, label=f"nf16_rand[{i}]")
    for i in range(NUM_RANDOM_PER_OP):
        p = (rng.getrandbits(32) << 32) | rand_fp(rng)
        await check_cvt(dut, CVT_NAR, 3, p, label=f"nbf_rand[{i}]")
    dut._log.info("cvt_narrow: 2 x %d random bit-exact", NUM_RANDOM_PER_OP)


@cocotb.test()
async def cvt_narrow_boundary_slivers(dut):
    """Enumerated closed sets (design test plan rows): f16 per-ULP RNE
    tie patterns (dropped field exactly half, kept-LSB even/odd, +/-1
    sticky neighbors), the overflow threshold band around 0x477FF000
    (>= 65520 -> Inf, never max-finite), the FTZ band (0, 2^-14) incl.
    the round-up-to-min-normal survivors at binade -15, NaN payload
    canonicalization (sign dropped, NaN never degrades to Inf), the
    subnormal-source DAZ sliver 0x007FFF80-0x007FFFFF (would otherwise
    round up to bf16 min-normal 0x0080), and the bf16 exact-tie /
    sticky-disjointness set (the 0x808000-class patterns random sampling
    essentially never hits — the confirmed round-half-up defect's home)."""
    await _start_clock(dut)
    n = 0
    # f16 ties: e in a spread of binades, dropped field {half-1, half,
    # half+1}, kept-LSB even/odd
    for e in (113, 116, 120, 127, 134, 140, 142):
        for keven in (0, 1):
            for drop in (0x0FFF, 0x1000, 0x1001):
                m = ((keven ^ 1) << 13) | drop           # kept-LSB parity
                for s in (0, 1):
                    bits = (s << 31) | (e << 23) | m
                    await check_cvt(dut, CVT_NAR, 2, bits,
                                    label=f"nf16_tie[{bits:#010x}]")
                    n += 1
    # f16 overflow band (65504 max-finite .. Inf threshold 65520)
    for off in range(-520, 521, 8):
        for s in (0, 1):
            bits = (s << 31) | ((0x477FF000 + off) & 0x7FFFFFFF)
            await check_cvt(dut, CVT_NAR, 2, bits,
                            label=f"nf16_ovf[{bits:#010x}]")
            n += 1
    # f16 FTZ band: min-normal 2^-14 (0x38800000), binade -15 incl. the
    # round-up survivors (0x387FF000 region), deep-subnormal-result band
    for base in (0x38800000, 0x38000000, 0x387FF000, 0x33800000):
        for off in range(-256, 257, 4):
            bits = (base + off) & 0xFFFFFFFF
            await check_cvt(dut, CVT_NAR, 2, bits,
                            label=f"nf16_ftz[{bits:#010x}]")
            await check_cvt(dut, CVT_NAR, 2, bits | 0x80000000,
                            label=f"nf16_ftzn[{bits:#010x}]")
            n += 2
    # NaN canonicalization rows, both dtypes (payload discarded, sign
    # dropped; sNaN quieted to the DESTINATION canonical pattern)
    for nan in (0x7F800001, 0x7FBFFFFF, 0x7FC00000, 0x7FC00001, 0x7FFFFFFF,
                0xFF800001, 0xFFC00000, 0xFFFFFFFF):
        got = await check_cvt(dut, CVT_NAR, 2, nan,
                              label=f"nf16_nan[{nan:#010x}]")
        assert got == 0x7E00, "f16 NaN narrow must be canonical 0x7E00"
        got = await check_cvt(dut, CVT_NAR, 3, nan,
                              label=f"nbf_nan[{nan:#010x}]")
        assert got == 0x7FC0, "bf16 NaN narrow must be canonical 0x7FC0"
        n += 2
    # DAZ sliver (pin 7): every pattern 0x007FFF80-0x007FFFFF, both signs,
    # both dtypes -> signed zero (min-normal neighbor 0x00800000 lives)
    for lo in range(0x007FFF80, 0x00800000):
        for s in (0, 0x80000000):
            got = await check_cvt(dut, CVT_NAR, 3, lo | s,
                                  label=f"nbf_daz[{lo | s:#010x}]")
            assert got == (0x8000 if s else 0), "DAZ sliver must flush"
            await check_cvt(dut, CVT_NAR, 2, lo | s,
                            label=f"nf16_daz[{lo | s:#010x}]")
            n += 2
    for s in (0, 0x80000000):
        await check_cvt(dut, CVT_NAR, 3, 0x00800000 | s, label="nbf_minn")
        n += 1
    # bf16 exact-tie set: low 16 bits == 0x8000, kept-LSB (bit 16) parity
    # swept across the mantissa and a spread of exponents, plus the
    # sticky-disjointness neighbors 0x7FFF / 0x8001
    for e in (1, 2, 64, 127, 128, 200, 253, 254):
        for k in range(0, 128, 1):
            m = (k << 16) | 0x8000
            bits = (e << 23) | m
            await check_cvt(dut, CVT_NAR, 3, bits,
                            label=f"nbf_tie[{bits:#010x}]")
            n += 1
        for m in ((3 << 16) | 0x7FFF, (3 << 16) | 0x8001,
                  (4 << 16) | 0x7FFF, (4 << 16) | 0x8001):
            bits = 0x80000000 | (e << 23) | m
            await check_cvt(dut, CVT_NAR, 3, bits,
                            label=f"nbf_stk[{bits:#010x}]")
            n += 1
    # bf16 max-finite ripple -> Inf (increment carries through exponent)
    for bits in (0x7F7FFFFF, 0xFF7FFFFF, 0x7F7F8000, 0x7F7F7FFF):
        await check_cvt(dut, CVT_NAR, 3, bits,
                        label=f"nbf_maxf[{bits:#010x}]")
        n += 1
    # round-trip identity E-row, RE-SCOPED (§23.10.10(b)): normals, +/-0,
    # +/-Inf, canonical qNaN survive half -> f32 -> half; f16 subnormals
    # fail BY DESIGN (FTZ pin) and are excluded
    rng = random.Random(0x1DE)
    for _ in range(2_000):
        h = rng.getrandbits(16)
        if 1 <= ((h >> 10) & 0x1F) <= 0x1E:              # f16 normals
            f = G.ref_widen_f16(h)
            got = await check_cvt(dut, CVT_NAR, 2, f, label=f"rt16[{h:#06x}]")
            assert got == h, f"f16 round-trip broke at {h:#06x}"
        b = rng.getrandbits(16)
        if 1 <= ((b >> 7) & 0xFF) <= 0xFE:               # bf16 normals
            f = G.ref_widen_bf16(b)
            got = await check_cvt(dut, CVT_NAR, 3, f, label=f"rtbf[{b:#06x}]")
            assert got == b, f"bf16 round-trip broke at {b:#06x}"
        n += 1
    for h, dt in ((0x0000, 2), (0x8000, 2), (0x7C00, 2), (0xFC00, 2),
                  (0x7E00, 2), (0x0000, 3), (0x8000, 3), (0x7F80, 3),
                  (0xFF80, 3), (0x7FC0, 3)):
        f = G.ref_widen_f16(h) if dt == 2 else G.ref_widen_bf16(h)
        got = await check_cvt(dut, CVT_NAR, dt, f, label=f"rt_sp[{h:#06x}]")
        assert got == h, f"special round-trip broke at {h:#06x}/dt{dt}"
        n += 1
    dut._log.info("cvt_narrow_boundary_slivers: %d directed bit-exact", n)


@cocotb.test()
async def cvt_f2i_directed_and_random(dut):
    """F2I rows: +/-0.5 and +/-1.5 ties per dtype, saturation edges at
    f32 granularity near +/-2^31 and the int4/int8 rails, +/-Inf ->
    min/max, NaN -> 0 (deterministic DATA), denormal source -> 0 (DAZ);
    plus 20,000 random per dtype."""
    await _start_clock(dut)
    n = 0
    ties = [0x3F000000, 0xBF000000, 0x3FC00000, 0xBFC00000,  # 0.5, 1.5
            0x40200000, 0xC0200000, 0x40A00000, 0xC0A00000,  # 2.5
            0x3F7FFFFF, 0xBF7FFFFF, 0x3F800000, 0x3E800000]
    rails4 = [0x40E00000, 0x40EFFFFF, 0x40F00000, 0x41000000,  # 7.x, 8
              0xC1000000, 0xC1080000, 0xC1100000,              # -8, -8.5, -9
              0x41080000]                                      # 8.5 tie->8sat
    rails8 = [0x42FE0000, 0x42FF0000, 0x43000000, 0xC3000000,  # 127,127.5,128
              0xC3008000, 0xC3010000]                          # -128.5, -129
    rails32 = [0x4EFFFFFF, 0x4F000000, 0x4F000001,             # 2^31-128, 2^31
               0xCF000000, 0xCF000001, 0xCEFFFFFF,             # -2^31 exact
               0x4F7FFFFF, 0xCF800000]
    spec = [0x7F800000, 0xFF800000, 0x7FC00000, 0x7F800001, 0xFFC00001,
            0x00000000, 0x80000000, 0x00000001, 0x807FFFFF, 0x00700000]
    for dt, extra in ((0, rails4), (1, rails8), (4, rails32)):
        for bits in ties + extra + spec:
            got = await check_cvt(dut, CVT_NAR, dt, bits,
                                  label=f"f2i{dt}[{bits:#010x}]")
            n += 1
        # rail identities pinned literally once per dtype (oracle-free)
        lo, hi = G.F2I_BOUNDS[{0: G.DT_INT4, 1: G.DT_INT8,
                               4: G.DT_ACC_INT}[dt]]
        got = await check_cvt(dut, CVT_NAR, dt, 0x7F800000, label=f"f2i{dt}+inf")
        assert got == (hi & 0xFFFFFFFF)
        got = await check_cvt(dut, CVT_NAR, dt, 0xFF800000, label=f"f2i{dt}-inf")
        assert got == (lo & 0xFFFFFFFF)
        got = await check_cvt(dut, CVT_NAR, dt, 0x7FC00000, label=f"f2i{dt}nan")
        assert got == 0
        n += 3
    rng = random.Random(0xF21)
    for dt in (0, 1, 4):
        for i in range(NUM_RANDOM_PER_OP):
            p = (rng.getrandbits(32) << 32) | rand_fp(rng)
            await check_cvt(dut, CVT_NAR, dt, p, label=f"f2i{dt}_rand[{i}]")
    dut._log.info("cvt_f2i: %d directed + 3 x %d random bit-exact",
                  n, NUM_RANDOM_PER_OP)


@cocotb.test()
async def cvt_daz_bypass_regression(dut):
    """The confirmed capture-mux bug this pin exists to kill: an
    UNCONDITIONAL operand-load DAZ flushes every non-fp32 CVT source
    whose bits look like an fp32 denormal — I2F(5) becomes I2F(0) = 0.0f
    instead of 5.0f, and every f16/bf16 pattern with a zero fp32 exponent
    field widens to zero. Asserts literal results (not just golden
    lockstep) so the row is oracle-independent; then the CONVERSE: the
    fp32 sources of NARROW/F2I ARE flushed at this site (pin 7)."""
    await _start_clock(dut)
    got = await check_cvt(dut, CVT_WID, 0, 5, label="daz_i2f4_5")
    assert got == 0x40A00000, "I2F(int4 5) must be 5.0f — DAZ bypass broken"
    got = await check_cvt(dut, CVT_WID, 1, 100, label="daz_i2f8_100")
    assert got == 0x42C80000, "I2F(int8 100) must be 100.0f"
    got = await check_cvt(dut, CVT_WID, 4, 1, label="daz_i2f64_1")
    assert got == 0x3F800000, "I2F(int64 1) must be 1.0f"
    got = await check_cvt(dut, CVT_WID, 2, 0x0001, label="daz_wf16_min")
    assert got == 0x33800000, "f16 min subnormal must widen exactly (2^-24)"
    got = await check_cvt(dut, CVT_WID, 2, 0x03FF, label="daz_wf16_maxsub")
    assert got == 0x387FC000, "f16 max subnormal must widen exactly"
    got = await check_cvt(dut, CVT_WID, 3, 0x0010, label="daz_wbf_sub")
    assert got == 0x00000000, "bf16 subnormal widens to SIGNED ZERO (pin 6)"
    got = await check_cvt(dut, CVT_WID, 3, 0x8010, label="daz_wbf_subn")
    assert got == 0x80000000, "bf16 subnormal keeps its sign through flush"
    # low-exponent NORMAL f16/bf16 patterns whose raw bits alias fp32
    # denormals (top exponent byte zero) — the exact aliasing class an
    # unconditional DAZ corrupts
    for h in (0x0400, 0x0401, 0x07FF, 0x1000):
        await check_cvt(dut, CVT_WID, 2, h, label=f"daz_wf16[{h:#06x}]")
    for b in (0x0080, 0x0081, 0x00FF, 0x0100):
        await check_cvt(dut, CVT_WID, 3, b, label=f"daz_wbf[{b:#06x}]")
    # converse: fp32 subnormal sources of NARROW/F2I are DAZ-flushed
    got = await check_cvt(dut, CVT_NAR, 2, 0x00000001, label="daz_nf16")
    assert got == 0x0000
    got = await check_cvt(dut, CVT_NAR, 3, 0x807FFFFF, label="daz_nbf")
    assert got == 0x8000
    got = await check_cvt(dut, CVT_NAR, 4, 0x007FFFFF, label="daz_f2i")
    assert got == 0
    dut._log.info("cvt_daz_bypass_regression: all rows bit-exact")


@cocotb.test()
async def accew_random_and_directed(dut):
    """0x73 OPREF form: 20,000 stratified random (a via rand_fp, B a
    64-bit pack of two rand_fp words) vs micro_accew == ref_fma — the
    round-once check lives in the golden FMA itself; plus specials and
    the gamma=1.0/beta=0.0 identity rows (a*1.0+0.0 == a post-DAZ for
    every normal/zero/Inf; NaN -> canonical qNaN)."""
    await _start_clock(dut)
    rng = random.Random(0xACCE)
    for i in range(NUM_RANDOM_PER_OP):
        a = rand_fp(rng)
        b_payload = (rand_fp(rng) << 32) | rand_fp(rng)
        await check_accew(dut, a, b_payload, label=f"accew_rand[{i}]")
    n = 0
    one_zero = (0x3F800000 << 32) | 0x00000000       # gamma=1.0, beta=0.0
    for a in (0x3F800000, 0xBF800000, 0x00000000, 0x80000000, 0x7F800000,
              0xFF800000, 0x00800000, 0x7F7FFFFF, 0x40490FDB, 0x00000001):
        got = await check_accew(dut, a, one_zero, label=f"accew_id[{a:#010x}]")
        exp_id = G.ref_fma(a, 0x3F800000, 0)
        assert got == exp_id, "identity row diverged"
        n += 1
    directed = [
        (0x3F800001, (0x3F800001 << 32) | 0xBF800002),   # fused single-RNE
        (0x7F800000, (0x00000000 << 32) | 0x40A00000),   # Inf*0+c -> qNaN
        (0x7F800000, (0x40000000 << 32) | 0xFF800000),   # Inf-Inf -> qNaN
        (0x3FC00000, (0x3FA00000 << 32) | 0xBFF00000),   # exact cancel -> +0
        (0xBF800000, (0x00000000 << 32) | 0x80000000),   # -0 sign rule
        (0x3F800000, (0x7FC00000 << 32) | 0x3F800000),   # NaN in B_hi
        (0x3F800000, (0x3F800000 << 32) | 0x7FC00000),   # NaN in B_lo
        (0x00000001, (0x4B800000 << 32) | 0x00000000),   # denormal a DAZ
    ]
    for a, bp in directed:
        await check_accew(dut, a, bp, label=f"accew_dir[{a:#010x}]")
        n += 1
    dut._log.info("accew: %d random + %d directed bit-exact",
                  NUM_RANDOM_PER_OP, n)


@cocotb.test()
async def cvt_accew_cycle_bounds_recorded(dut):
    """§23.10.10(e) completion-within-bound is enforced on EVERY launch
    by launch(); this suite additionally records the measured worst
    start->done latencies for the spec table (never asserting exactness)
    and pins the bound keys: CVT all forms <= 8, I2F int64 <= 10,
    ACC_ELEMWISE <= 10."""
    await _start_clock(dut)
    rng = random.Random(0xC1C)
    for _ in range(200):
        for dt in (0, 1, 2, 3, 4):
            await check_cvt(dut, CVT_WID, dt, rng.getrandbits(64),
                            label="cyc_wid")
            await check_cvt(dut, CVT_NAR, dt,
                            (rng.getrandbits(32) << 32) | rand_fp(rng),
                            label="cyc_nar")
        await check_accew(dut, rand_fp(rng),
                          (rand_fp(rng) << 32) | rand_fp(rng), label="cyc_ew")
    worst_cvt = {k: v for k, v in _worst_lat.items() if k[0] == OPC_CVT}
    worst_ew = _worst_lat.get((OPC_ACCEW, 0), 0)
    for (opc, key), v in worst_cvt.items():
        sub, dt = key >> 4, key & 0xF
        bound = MAXC_CVT_I64 if (sub == CVT_WID and dt == 4) else MAXC_CVT
        assert v <= bound
    assert worst_ew <= MAXC[OPC_ACCEW]
    dut._log.info("cycle maxima measured: CVT worst {%s} (bounds 8/10), "
                  "ACCEW worst %d (bound 10)",
                  ", ".join(f"sub{k >> 4}dt{k & 0xF}:{v}"
                            for (_, k), v in sorted(worst_cvt.items())),
                  worst_ew)
