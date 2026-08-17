# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""tb_fp_stepseq — bit-exactness + protocol validation of FP_StepSeq (the
v1.8.0c MU-hosted fp32 step-sequencer unit, spec §23.10) BEFORE synth
Gate 3, extended for the v1.8.0d OPS_CVT / OPS_ACCEW op classes (spec
§23.10.10) BEFORE synth Gate C3, and for the v1.8.0e OPS_DEQ fused
per-lane DEQUANT program (spec §25.2.2, 0e1) BEFORE the re-run of the
fp_stepseq unit synth gate.

v1.8.0e coverage plan (§25.2.2 + the 0e test plan): 20,000 random
vectors PER source dtype (int4/int8 — full-32-bit garbage lane words,
only the low nibble/byte may matter) vs golden ref_dequant_lane ==
micro_dequant_lane, directed enumerated specials cells (scale NaN/sNaN/
Inf/zero/denormal-DAZ x k = 0/+max/-min, overflow -> Inf never
max-finite, sign-XOR signed zeros), oracle-free EXACTNESS cells (every
lane value x power-of-two scales, value-level Fraction identity), and
the ROUND-ONCE discriminator/exact-tie cells (the dequant_tie_cells
constructive generator reproduced from scripts/mse_sweep.py with
attribution — that module needs mpmath which this venv lacks; a local
double-round twin composed from golden primitives proves every
discriminator has power, then RTL must match round-once). ALL existing
suites re-run unchanged in the same module — the locked full re-proof
of the 8 pre-0e step programs (§25.1 item 9). OPS_DEQ per-launch cycle
bound = 8 (the §25.4 L=8 ceiling; the measured count is logged so the
cycle table graduates estimate -> measured).

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
OPC_DEQUANT = 0x78              # v1.8.0e §25.2.2 (0e1)

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
MAXC_DEQ = 8                    # §25.4 per-lane L=8 ceiling (estimate
                                # L=6-7; measured count logged, never
                                # asserted exact)

NUM_RANDOM_PER_OP = 20_000

_worst_lat = {}


def _bound_of(opcode, subop, dtype):
    if opcode == OPC_FSCALAR:
        return MAXC_FSCALAR[subop]
    if opcode == OPC_CVT:
        return (MAXC_CVT_I64 if (subop == CVT_WID and dtype == 4)
                else MAXC_CVT)
    if opcode == OPC_DEQUANT:
        return MAXC_DEQ
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
    elif opcode == OPC_DEQUANT:
        key = (opcode, dtype)
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


async def check_dequant(dut, dtype, a_raw, scale, label=""):
    """0x78 OPS_DEQ one lane vs golden ref_dequant_lane (== the
    micro_dequant_lane sequencer twin — asserted in lockstep so the TB
    itself re-proves the model-side bit-equivalence on every vector).
    a_raw is the full 32-bit a_in word: only the low nibble/byte is the
    lane field, everything above is garbage the RTL must ignore. The
    result row is {16'h0, bf16} — the upper halfword is asserted zero."""
    field = a_raw & (0xF if dtype == 0 else 0xFF)
    exp = G.ref_dequant_lane(field, scale, dtype)
    assert G.micro_dequant_lane(field, scale, dtype) == exp, \
        f"{label}: golden micro/ref divergence (model bug)"
    got = await launch(dut, OPC_DEQUANT, 0, a_raw, scale, 0, label=label,
                       dtype=dtype)
    assert (got >> 16) == 0, (
        f"{label}: DEQ result upper halfword nonzero: {got:#010x}")
    assert got == exp, (f"{label}: DEQ dt={dtype} a={a_raw:#010x} "
                        f"scale={scale:#010x} got {got:#06x} "
                        f"expected {exp:#06x}")
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
           + [("CVT", (CVT_NAR, dt)) for dt in (0, 1, 2, 3, 4)]
           + [("DEQ", 0), ("DEQ", 1)])       # v1.8.0e OPS_DEQ joins the mix
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
        elif kind == "DEQ":
            await check_dequant(dut, sel, rng.getrandbits(32), b,
                                label=f"b2b[{i}]")
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


# ===========================================================================
# v1.8.0e — 0x78 OPS_DEQ suites (spec §25.2.2, 0e1 sequencer-side commit)
# ===========================================================================


@cocotb.test()
async def dequant_random(dut):
    """20,000 random per source dtype: full-32-bit garbage lane words
    (only a_in[3:0]/[7:0] may matter) x rand_fp scales (specials/denormal/
    boundary-binade biased — every §25.2.2 specials row is hit at random
    density on top of the enumerated directed suite below)."""
    await _start_clock(dut)
    rng = random.Random(0xDE04)
    for i in range(NUM_RANDOM_PER_OP):
        await check_dequant(dut, 0, rng.getrandbits(32), rand_fp(rng),
                            label=f"deq4_rand[{i}]")
    for i in range(NUM_RANDOM_PER_OP):
        await check_dequant(dut, 1, rng.getrandbits(32), rand_fp(rng),
                            label=f"deq8_rand[{i}]")
    dut._log.info("dequant_random: 2 x %d random bit-exact (worst "
                  "latency int4 %d / int8 %d)", NUM_RANDOM_PER_OP,
                  _worst_lat[(OPC_DEQUANT, 0)], _worst_lat[(OPC_DEQUANT, 1)])


@cocotb.test()
async def dequant_directed_specials_and_exact(dut):
    """Enumerated §25.2.2 cells, every pinned row by name:
      * scale NaN (qNaN/sNaN, both signs, payload spread) -> bf16 qNaN
        0x7FC0 for EVERY k (canonical, sign dropped);
      * scale +-Inf: k == 0 -> qNaN; k != 0 -> SIGNED bf16 Inf by
        sign-XOR;
      * scale +-0 and every DAZ'd denormal scale -> SIGNED zero by
        sign-XOR (k = 0 rows included — 0 x 0 keeps the XOR sign rule);
      * k == 0 x finite scales -> signed zero;
      * overflow -> +-Inf NEVER max-finite: |k| >= 2 x max-finite scale
        (e_u > 127 substitute path) AND |k| == 1 x max-finite scale (the
        narrow's own 0x7F7F -> 0x7F80 ripple path);
      * scale min-normal x every k (the FTZ-at-dest vacuity boundary:
        results stay >= bf16 min-normal);
      * EXACTNESS (oracle-free, value-level): every int4 field and a
        stratified int8 set x power-of-two scales — bf16_to_frac(got)
        must equal k * 2^e EXACTLY (|k| <= 128 fits the 8-bit bf16
        significand, so the product is representable and round-once
        must return it exactly)."""
    await _start_clock(dut)
    from fractions import Fraction as Fr
    n = 0
    nan_pool = [0x7FC00000, 0xFFC00000, 0x7F800001, 0xFF800001,
                0x7FFFFFFF, 0x7FBFFFFF]
    k4 = list(range(16))                          # all int4 fields
    k8 = [0x00, 0x01, 0x7F, 0x80, 0x81, 0xFF, 0x05, 0xFB, 0x40, 0xC0]
    for dt, ks in ((0, k4), (1, k8)):
        for f in ks:
            for s in nan_pool:
                got = await check_dequant(dut, dt, f, s,
                                          label=f"deq_nan[{dt}/{f:#x}]")
                assert got == 0x7FC0, "scale NaN must give canonical bf16 qNaN"
                n += 1
            for s in (0x7F800000, 0xFF800000):    # +-Inf
                await check_dequant(dut, dt, f, s,
                                    label=f"deq_inf[{dt}/{f:#x}]")
                n += 1
            for s in (0x00000000, 0x80000000,     # +-0
                      0x00000001, 0x80000001,     # +-min denormal (DAZ)
                      0x007FFFFF, 0x807FFFFF):    # +-max denormal (DAZ)
                got = await check_dequant(dut, dt, f, s,
                                          label=f"deq_zero[{dt}/{f:#x}]")
                assert got & 0x7FFF == 0, "zero/DAZ scale must give a zero"
                n += 1
            for s in (0x7F7FFFFF, 0xFF7FFFFF):    # +-max normal (overflow
                await check_dequant(dut, dt, f, s,  # + ripple-to-Inf rows)
                                    label=f"deq_maxf[{dt}/{f:#x}]")
                n += 1
            for s in (0x00800000, 0x80800000):    # +-min normal
                await check_dequant(dut, dt, f, s,
                                    label=f"deq_minn[{dt}/{f:#x}]")
                n += 1
    # exactness: k x 2^e value-level identity (never consults golden)
    for dt, ks in ((0, k4), (1, k8)):
        for f in ks:
            if dt == 0:
                k = f - 16 if f >= 8 else f
            else:
                k = f - 256 if f >= 128 else f
            for e in (-100, -50, -7, 0, 1, 8, 63, 100, 112):
                s = (e + 127) << 23
                got = await check_dequant(dut, dt, f, s,
                                          label=f"deq_exact[{dt}/{f:#x}/{e}]")
                if k == 0:
                    assert got in (0x0000, 0x8000)
                else:
                    assert G.bf16_to_frac(got) == Fr(k) * Fr(2) ** e, (
                        f"k={k} 2^{e}: {got:#06x} not the exact product")
                n += 1
    dut._log.info("dequant_directed: %d specials/exactness cells bit-exact", n)


def _dequant_tie_cells():
    """The constructive ROUND-ONCE tie cells, reproduced with attribution
    from scripts/mse_sweep.py dequant_tie_cells() (that module imports
    mpmath, which this cocotb venv lacks — the fp_release_sweep numpy
    precedent). Returns (discriminators, exact_ties) as (field,
    scale_bits, dtype) with dtype in TB encoding {0: int4, 1: int8}.
    See the mse_sweep docstring for the below/above-midpoint
    construction; delta is forced by P ≡ 0 (mod |k|)."""
    disc, ties = [], []
    for dtype, ks in ((0, (3, 5, 7, -3, -5, -7)),
                      (1, (3, 5, 7, 11, 25, 89, 127, -3, -89, -127))):
        mask = 0xF if dtype == 0 else 0xFF
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
    disc += [(f, G.f32_exp_shift(s, dk), dt)
             for (f, s, dt) in disc[:4] for dk in (-120, 90)]
    ties += [(f, G.f32_exp_shift(s, dk), dt)
             for (f, s, dt) in ties[:2] for dk in (-120, 90)]
    return disc, ties


@cocotb.test()
async def dequant_round_once_ties(dut):
    """THE enforcement point of rounding definition (a) — the MSE gate is
    provably blind to round-once-vs-double-round (§25.5.2), so the
    directed tie vectors run as golden/TB BIT-EQUIVALENCE here. Every
    discriminator is first proven to HAVE POWER: a double-round twin
    composed from golden primitives (RNE the exact product to fp32
    first, then narrow — the FORBIDDEN ref_mul-then-narrow composition)
    must differ from ref_dequant_lane on it; then the RTL must match
    round-once. Exact ties (product ON the midpoint, sticky 0) pin
    ties-to-even and must agree across all three."""
    await _start_clock(dut)
    disc, ties = _dequant_tie_cells()
    assert len(disc) >= 40 and len(ties) >= 6, "tie generator lost power"
    for f, s, dt in disc:
        r = G.ref_dequant_lane(f, s, dt)
        dbl = G.ref_narrow_f32(G.ref_mul(G.ref_i2f(f, dt), s), G.DT_BF16)
        assert dbl != r, (
            f"discriminator lost power: f={f:#x} s={s:#010x} dt={dt}")
        got = await check_dequant(dut, dt, f, s,
                                  label=f"deq_disc[{f:#x}/{s:#010x}]")
        assert got == r and got != dbl, "RTL rounded twice (definition (b))"
    for f, s, dt in ties:
        r = G.ref_dequant_lane(f, s, dt)
        dbl = G.ref_narrow_f32(G.ref_mul(G.ref_i2f(f, dt), s), G.DT_BF16)
        assert dbl == r, "exact tie must coincide by construction"
        await check_dequant(dut, dt, f, s,
                            label=f"deq_tie[{f:#x}/{s:#010x}]")
    dut._log.info("dequant_round_once: %d discriminators (all with proven "
                  "power) + %d exact ties bit-exact — definition (a) held",
                  len(disc), len(ties))


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


# ===========================================================================
# v1.8.0e 3a-C3 §27.7a — OPS_FDOTCR (0x7A FDOT32_CR) suites
# ---------------------------------------------------------------------------
# Everything from here down is APPENDED: the 25 pre-3a suites above are
# byte-unchanged, which is the §27.7a.4 / §25.1 item-9 full re-proof
# evidence (an op_sel touch re-proves ALL existing step programs; the
# capture-mux subtlety class is §23.10.10(h) item 4 — a shipped op's
# SILENT WRONG DATA, which is exactly why the old suites must run verbatim
# rather than "equivalently").
#
# Bit-exactness authority: include/generated/fdotcr_vectors.hex (450 golden
# directed lines, fixed seed, byte-identical re-run) whose RESULT field is
# ALWAYS the value-contract right-hand side pack_signed(exact Σ a_i·b_i) —
# never an EFT output (the C1 self-confirmation-loop fix, spec §27.7a.2a
# amendment-5). Layout contract: include/generated/fdotcr_vec_contract.md.
#
# Operand ingress (3a-C3 RTL decision, see the FP_StepSeq header and spec
# §27.7a.2b which records it as the third form): the 1,024-bit A||B wave
# enters ONE 64-bit fragment per cycle on {b_in, a_in} over 16 cycles —
# frag 0 on the launch edge, frags 1..15 on the next 15.
#
# WHITEBOX AXIS (3a-C3 repair): the fold-direction ban of §27.7a.2a can
# only be CHECKED if the RTL's own expansion is fine-grained enough for
# the direction to matter. That is a property of the RTL, not of the
# golden model, so the discriminator READS THE RTL's expansion out of
# fd_xp at STEP F entry and re-folds THAT column both ways with golden
# primitives. Same for the freeze axis: fd_jam is compared against the
# first substantive jam of the captured column, so the "watch window
# opens at the jam" claim is measured, not asserted.
# ===========================================================================
import golden_fdotcr as GF  # noqa: E402

OPC_FDOTCR = 0x7A
FDOT_CAP = 10_000               # §27.7a.2 hard cycle ceiling (gate V20-4)
FDOT_VEC_PATH = REPO / "include" / "generated" / "fdotcr_vectors.hex"
F32_QNAN = 0x7FC00000

# FP_StepSeq sub-sequencer state encodings (mirrored for the directed
# loud-fault probes below — they must poke at a KNOWN phase)
FDS_PRIME, FDS_LANE, FDS_PROD = 1, 2, 4
FDS_WALK, FDS_NEXT, FDS_FOLDW = 6, 9, 10

_fdot_worst = {"cycles": 0, "line": -1, "fam": -1}


# ---------------------------------------------------------------------------
# whitebox: the RTL's own expansion / fold trace
# ---------------------------------------------------------------------------
def _fd_word_me(word):
    """fd_xp word {sign, xe[11:0], mag[23:0]} -> golden component (m, e).
    RTL stores NORMALIZED magnitudes (mag[23] == 1), value ==
    mag * 2^(xe-23), so the golden pair is (+-mag, xe-23)."""
    mag = word & 0xFFFFFF
    xe = (word >> 24) & 0xFFF
    if xe >= 0x800:
        xe -= 0x1000
    return (-mag if (word >> 36) & 1 else mag, xe - 23)


def _fd_low(c):
    """The component's TRUE lowest set bit. golden's (m, e) may keep
    trailing zeros in m, so its e is a DECLARED scale and its non-overlap
    test `comp_top(a) <= b[1]` is the conservative form; the RTL stores
    normalized magnitudes, so its e is the real bit position and its
    non-overlap test is the exact one (never looser in bit-range terms —
    a golden-disjoint pair is always RTL-disjoint). The amendment-1
    theorem's premises are stated on the real bit ranges (the telescoping
    bound uses |c_i| <= 2^top - 2^e), so this is the form to check."""
    m, e = c
    a = abs(m)
    return e + (a & -a).bit_length() - 1


def _col_exact_me(col):
    m, e = 0, 0
    for c in col:
        m, e = GF.STUDY.add_me(m, e, c[0], c[1])
    return m, e


def _fold_me(col, descending):
    """RTO-48 fold of a captured RTL column with the GOLDEN primitives
    (no re-implementation): returns ((m, e), first_jam_pass) where the
    jam index is 0-based in fold order, None when no pass ever jams."""
    am, ae = 0, 0
    jam = None
    order = reversed(col) if descending else col
    for k, c in enumerate(order):
        pm, pe = GF.STUDY.add_me(am, ae, c[0], c[1])
        am, ae = GF.STUDY.rto_me(pm, pe, GF.Q48)
        if jam is None and not GF.STUDY.veq_me(am, ae, pm, pe):
            jam = k
    return (am, ae), jam


class _FoldWatch:
    """Per-cycle observer for launch_fdotcr(poke=...): captures the
    expansion the RTL hands to STEP F and the per-pass fd_jam trace."""

    def __init__(self, trace_jam=False):
        self.column = None          # [(m, e), ...] ascending, RTL's own
        self.trace_jam = trace_jam
        self._raw = []              # (fd_wait, fd_jam) per FDS_FOLDW cycle

    def __call__(self, d, _cyc):
        if int(d.fd_st.value) != FDS_FOLDW:
            return
        if self.column is None:
            n = int(d.fd_n.value)
            self.column = [_fd_word_me(int(d.fd_xp[i].value))
                           for i in range(n)]
        if self.trace_jam:
            self._raw.append((int(d.fd_wait.value), int(d.fd_jam.value)))

    def jam_pass(self):
        """The 0-based fold pass that first raised fd_jam, as OBSERVED.
        A pass retires on the cycle where fd_wait == 0 and the register
        update is visible from the next cycle on, so the first sample
        carrying fd_jam == 1 dates the raise to the pass that just
        retired. Returns None when no FDS_FOLDW cycle ever showed it —
        which also covers 'the jam happened on the very last pass', so
        callers pair this with the post-run fd_jam level."""
        passes = 0
        for wait, jam in self._raw:
            if jam:
                return passes - 1
            if wait == 0:
                passes += 1
        return None


def _load_fdotcr_vectors():
    """Read the golden vector file into dicts. Layout (vec_contract §1):
    META[1087:1056] | OPERANDS[1055:32] | RESULT[31:0], MSB-first hex."""
    rows = []
    for idx, ln in enumerate(FDOT_VEC_PATH.read_text().splitlines(), 1):
        if not ln or ln.startswith("//"):
            continue
        assert len(ln) == GF.VEC_HEX, (
            f"fdotcr_vectors.hex line {idx}: {len(ln)} hex chars, "
            f"contract says {GF.VEC_HEX}")
        v = int(ln, 16)
        bits = v & 0xFFFFFFFF
        v >>= 32
        payload = v & ((1 << 1024) - 1)
        meta = v >> 1024
        rows.append({
            "line": idx,
            "dtype": meta & 0xFF,
            "special": (meta >> 8) & 1,
            "n_special": (meta >> 16) & 0xFF,
            "fam": (meta >> 24) & 0xFF,
            "payload": payload,
            "result": bits,
        })
    assert rows, "fdotcr_vectors.hex carried no vectors"
    return rows


def _fdot_pairs(payload):
    """payload -> the 32 (a, b) raw 16-bit operand pairs (vec_contract §3;
    identical to the golden generator's own reader)."""
    frags = [(payload >> (64 * f)) & ((1 << 64) - 1) for f in range(16)]
    a_lanes = GF.frags_to_lanes(frags[:8], 16, GF.GROUP)
    b_lanes = GF.frags_to_lanes(frags[8:], 16, GF.GROUP)
    return list(zip(a_lanes, b_lanes))


async def launch_fdotcr(dut, dtype, payload, label="", cap=FDOT_CAP,
                        poke=None):
    """Launch one 0x7A dispatch back-to-back, stream the 16 operand
    fragments, enforce the §27.7a.2 hard cycle ceiling + the busy/done
    protocol, and return (result, cycles).

    `poke(dut, cycle)` (optional) is called after every clock edge so the
    directed loud-fault probes can inject at a known sub-sequencer phase.
    """
    assert int(dut.busy.value) == 0, f"{label}: busy before start"
    assert int(dut.done.value) == 0, f"{label}: stray done before start"
    frags = [(payload >> (64 * f)) & ((1 << 64) - 1) for f in range(16)]
    dut.opcode_in.value = OPC_FDOTCR
    dut.subop_in.value = 0
    dut.dtype_in.value = dtype
    dut.c_in.value = 0
    dut.a_in.value = frags[0] & 0xFFFFFFFF
    dut.b_in.value = (frags[0] >> 32) & 0xFFFFFFFF
    dut.start.value = 1
    lat = 0
    result = None
    while True:
        await FallingEdge(dut.clk)
        lat += 1
        dut.start.value = 0
        if lat < 16:                    # frags 1..15 on the next 15 cycles
            dut.a_in.value = frags[lat] & 0xFFFFFFFF
            dut.b_in.value = (frags[lat] >> 32) & 0xFFFFFFFF
        assert int(dut.busy.value) == 1, f"{label}: busy dropped mid-op"
        if int(dut.done.value):
            result = int(dut.result.value)
            break
        assert lat <= cap, (
            f"{label}: no done within the §27.7a.2 hard ceiling {cap}")
        if poke is not None:
            poke(dut, lat)
    assert lat <= cap, f"{label}: done at {lat} > hard ceiling {cap}"
    await FallingEdge(dut.clk)
    assert int(dut.done.value) == 0, f"{label}: done wider than 1 cycle"
    assert int(dut.busy.value) == 0, f"{label}: busy stuck after done"
    return result, lat


async def check_fdotcr(dut, row):
    """One golden vector: bit-exact result + the §27.7a.1 (iii) sticky
    contract (special wave -> canonical qNaN AND the dedicated sticky;
    finite wave -> no sticky, no loud fault)."""
    label = f"fdot L{row['line']} fam{row['fam']}"
    got, lat = await launch_fdotcr(dut, row["dtype"], row["payload"], label)
    if lat > _fdot_worst["cycles"]:
        _fdot_worst.update(cycles=lat, line=row["line"], fam=row["fam"])
    assert got == row["result"], (
        f"{label}: dtype={row['dtype']:#x} got {got:#010x} expected "
        f"{row['result']:#010x} (value contract pack_signed(exact))")
    spec = int(dut.fd_spec.value)
    fault = int(dut.fd_fault.value)
    assert fault == 0, f"{label}: loud fault raised on a legal vector"
    if row["special"]:
        assert got == F32_QNAN, f"{label}: special wave result not qNaN"
        assert spec == 1, f"{label}: special wave did not raise the sticky"
    else:
        assert spec == 0, f"{label}: sticky raised on a special-free wave"
    return got, lat


@cocotb.test()
async def fdotcr_golden_vectors(dut):
    """§27.7a.5 (TB, unit): the FULL golden vector file through the RTL
    step program, bit-exact against the value contract, with the hard
    cycle ceiling asserted on every launch and the specials/sticky rows
    contrasted (vec_contract §5)."""
    await _start_clock(dut)
    rows = _load_fdotcr_vectors()
    per_fam = {}
    sp_lat = set()
    for row in rows:
        _, lat = await check_fdotcr(dut, row)
        f = per_fam.setdefault(row["fam"], [0, 0])
        f[0] += 1
        f[1] = max(f[1], lat)
        if row["special"]:
            sp_lat.add(lat)
    n_sp = sum(r["special"] for r in rows)
    dut._log.info("fdotcr special-wave latencies (EFT never entered): %s",
                  sorted(sp_lat))
    dut._log.info("fdotcr golden vectors: %d lines bit-exact "
                  "(%d special / %d finite), families %s",
                  len(rows), n_sp, len(rows) - n_sp,
                  sorted(per_fam))
    dut._log.info("fdotcr per-family worst cycles: %s",
                  ", ".join(f"fam{k}:{v[1]}({v[0]})"
                            for k, v in sorted(per_fam.items())))
    dut._log.info("fdotcr worst start->done = %d cycles (hard ceiling %d, "
                  "line %d family %d) — §27.7a.2 measured, not estimated",
                  _fdot_worst["cycles"], FDOT_CAP, _fdot_worst["line"],
                  _fdot_worst["fam"])
    assert _fdot_worst["cycles"] <= FDOT_CAP


@cocotb.test()
async def fdotcr_descending_fold_discriminator(dut):
    """POWER PROOF for the §27.7a.2a fold-direction ban, measured on the
    RTL's OWN expansion (3a-C3 repair — the first version of this suite
    was structurally vacuous).

    The ban only has teeth if the column the RTL hands to STEP F is
    fine-grained enough for the fold direction to change the answer.
    That is a property of the RTL's component geometry (the exact
    `top(a) <= e_b` non-overlap test), NOT of the golden model, so
    asserting things about golden expansions proves nothing about the
    RTL. Here we read fd_xp[0..fd_n-1] at STEP F entry and, per row:

      (i)   re-check the STEP I invariants ON THE RTL COLUMN — strictly
            ascending, non-overlapping (golden assert (2)), and
            pack_signed(exact sum of the column) == the value contract
            (golden assert (3), which the RTL cannot afford in hardware);
      (ii)  fold that very column DESCENDING with golden primitives and
            require it to equal what the RTL returned;
      (iii) fold it ASCENDING (the REFUTED pin) and count the rows where
            that disagrees with the value contract. Those rows are the
            teeth: on them an ascending RTL fails fdotcr_golden_vectors.

    Zero such rows == the ban is unfalsifiable == hard fail (the same
    stance as the golden generator's amendment-8 'ASC 반증 근거 소실'
    exit). Measured 2026-08-17: 2 of the 311 non-empty finite columns +
    3 of 120 fresh eft_top_cancel trials, the same order as the golden
    report's asc_detection_rate_by_family (that family's value-violation
    rate is 120/3,000 = 4%). Before the geometry repair BOTH counts were
    ZERO — which is how a coarser non-overlap test hides here."""
    await _start_clock(dut)
    rows = [r for r in _load_fdotcr_vectors() if not r["special"]]
    teeth = []
    checked = 0
    widest = (0, -1)                # (components, vector line) — RTL's own
    for row in rows:
        watch = _FoldWatch()
        got, _ = await launch_fdotcr(dut, row["dtype"], row["payload"],
                                     f"disc L{row['line']}", poke=watch)
        assert got == row["result"], f"disc L{row['line']}: {got:#010x}"
        col = watch.column
        if col is None:                 # every lane zero-contributing
            continue
        checked += 1
        if len(col) > widest[0]:
            widest = (len(col), row["line"])
        for i, c in enumerate(col):
            # golden comp_ok + the RTL's own normalized-storage invariant
            assert c[0] != 0 and abs(c[0]) < (1 << 24), (
                f"L{row['line']}: component {i} out of W=24: {c!r}")
            assert abs(c[0]) >= (1 << 23), (
                f"L{row['line']}: component {i} is not normalized "
                f"(mag[23] must be 1): {c!r}")
            assert -1024 <= c[1] + 23 <= 1023, (
                f"L{row['line']}: component {i} exponent outside "
                f"signed-11: {c!r}")
        for i in range(1, len(col)):
            assert GF.comp_top(col[i - 1]) <= _fd_low(col[i]), (
                f"L{row['line']}: RTL column overlaps/unsorted at {i}: "
                f"{col[i - 1]!r} then {col[i]!r} — STEP I invariant")
        assert GF.pack_final_me(*_col_exact_me(col)) == row["result"], (
            f"L{row['line']}: the RTL column's exact sum does not pack to "
            f"the value contract — STEP I exact-sum preservation broken")
        (dm, de), _ = _fold_me(col, descending=True)
        assert GF.pack_final_me(dm, de) == row["result"], (
            f"L{row['line']}: descending fold of the RTL column != the "
            f"value contract")
        (am, ae), _ = _fold_me(col, descending=False)
        asc_bits = GF.pack_final_me(am, ae)
        if asc_bits != row["result"]:
            teeth.append((row["line"], row["fam"], len(col), asc_bits))
        if row["fam"] == 12:
            # c1_regress: the GOLDEN-side refutation the spec cites must
            # also still hold (kept verbatim from the pre-repair suite —
            # the RTL-side proof above is additional, not a replacement)
            ref = GF.fdotcr_ref(row["dtype"], _fdot_pairs(row["payload"]))
            g_asc = GF.pack_final_me(*GF.fold_ascending_refuted(
                ref["expansion"]))
            assert g_asc != row["result"], (
                f"L{row['line']}: the ASC refutation evaporated in the "
                f"GOLDEN model — the spec §27.7a.2a citation collapses")
    assert checked > 0
    # fresh adversarial trials from the family the vector file samples
    # only 30 lines of (the C1 counterexample mechanism, contract §6)
    rng = random.Random(0x7ADC3D1)
    fresh = 0
    for _ in range(120):
        dtype, pairs = GF.gen_top_cancel(rng)
        payload = 0
        for f, w in enumerate(G.lanes_to_frags([a for a, _ in pairs], 16)
                              + G.lanes_to_frags([b for _, b in pairs], 16)):
            payload |= w << (64 * f)
        exp_bits, exp_sp, _ = GF._independent_expected(dtype, pairs)
        if exp_sp:
            continue
        watch = _FoldWatch()
        got, _ = await launch_fdotcr(dut, dtype, payload, "disc_fresh",
                                     poke=watch)
        assert got == exp_bits, f"disc_fresh: {got:#010x} != {exp_bits:#010x}"
        if watch.column is None:
            continue
        (am, ae), _ = _fold_me(watch.column, descending=False)
        if GF.pack_final_me(am, ae) != exp_bits:
            fresh += 1
    dut._log.info("RTL expansion granularity (its own fd_xp at STEP F): "
                  "widest column %d components (vector line %d) of the %d "
                  "slot capacity — golden report max_observed_components "
                  "is 25, and a coarser non-overlap test shows up HERE "
                  "first (draft: 17)", widest[0], widest[1], 33)
    dut._log.info("fold-direction teeth: %d of %d finite vector rows + "
                  "%d of 120 fresh eft_top_cancel trials FAIL under the "
                  "REFUTED ascending fold of the RTL's own column",
                  len(teeth), checked, fresh)
    for line, fam, n, bits in teeth:
        dut._log.info("  L%d fam%d: RTL column n=%d, ASC would return "
                      "%#010x", line, fam, n, bits)
    assert len(teeth) + fresh > 0, (
        "the fold-direction ban is UNFALSIFIABLE against this RTL: no "
        "vector's own expansion distinguishes ascending from descending. "
        "That is exactly the 3a-C3 defect (a coarser non-overlap test "
        "merges the column until the ASC failure mode is unreachable) — "
        "spec §27.7a.2b. FIX THE GEOMETRY, DO NOT RELAX THIS ASSERT.")


@cocotb.test()
async def fdotcr_freeze_axis_jam_anchored(dut):
    """§27.7a.2a pins freeze ('acc unchanged after the first substantive
    jam') as THE information axis of the fold theorem, so the watch
    window must open exactly where golden's does — at the jam itself.

    The first 3a-C3 draft only armed the watch after OBSERVING an
    unchanged pass, which is strictly weaker in one direction: a
    theorem-(4) collapse on the FIRST pass after the jam was invisible.
    fd_jam now anchors on the pass being inexact, and this suite measures
    that: for every vector we take the RTL's own column, compute the
    first substantive jam with the golden primitives (RTO output !=
    pre-RTO exact sum — fold_descending's own test), and require the RTL
    to have raised fd_jam on exactly that pass, never later."""
    await _start_clock(dut)
    rows = [r for r in _load_fdotcr_vectors() if not r["special"]]
    jam_rows = 0
    anchored = 0
    for row in rows:
        watch = _FoldWatch(trace_jam=True)
        got, _ = await launch_fdotcr(dut, row["dtype"], row["payload"],
                                     f"jam L{row['line']}", poke=watch)
        assert got == row["result"]
        col = watch.column
        if col is None:
            continue
        _, exp_jam = _fold_me(col, descending=True)
        rtl_level = int(dut.fd_jam.value)
        assert rtl_level == (0 if exp_jam is None else 1), (
            f"L{row['line']}: fd_jam={rtl_level} but the golden fold of "
            f"the RTL's own column jams at pass {exp_jam}")
        if exp_jam is None:
            continue
        jam_rows += 1
        seen = watch.jam_pass()
        if exp_jam == len(col) - 1:
            # jam on the last pass: the FSM leaves FDS_FOLDW immediately,
            # so only the post-run level is observable (asserted above)
            assert seen is None or seen == exp_jam
            continue
        anchored += 1
        assert seen == exp_jam, (
            f"L{row['line']}: fd_jam raised after pass {seen}, golden "
            f"jams at pass {exp_jam} of {len(col)} — the freeze watch "
            f"window does not open at the jam (a collapse in the "
            f"pass(es) in between would be invisible)")
    dut._log.info("freeze axis: %d of %d finite rows jam; %d have the jam "
                  "before the last pass and the RTL anchored fd_jam on "
                  "the exact golden pass in every one", jam_rows,
                  len(rows), anchored)
    assert anchored > 0, (
        "no row exercised the jam anchor — the freeze axis would be "
        "asserted, not measured")


@cocotb.test()
async def fdotcr_busy_interlock_rejects_overlap(dut):
    """§27.7a.1 'busy-interlock, 중첩 dispatch 거부' — the half of the
    contract the pre-3a launch convention left unchecked. Every other
    suite only shows busy==1 while the op runs; here start is actually
    RE-ASSERTED mid-flight (with a different opcode and hostile
    operands) and the dispatch must be ignored BIT-FOR-BIT: same result,
    same cycle count, no sticky, no fault. The converse direction (a
    0x7A start raised while a scalar op is in flight) is checked too —
    that is the one that would corrupt a SHIPPED op (§23.10.10(h) item
    4)."""
    await _start_clock(dut)
    row = [r for r in _load_fdotcr_vectors() if not r["special"]][0]
    clean, clean_lat = await launch_fdotcr(dut, row["dtype"],
                                           row["payload"], "interlock_ref")
    assert clean == row["result"]

    for frac in (0.02, 0.25, 0.6, 0.95):
        at = max(1, min(clean_lat - 1, int(clean_lat * frac)))
        # foreign-opcode overlap (generic FSM interlock) AND same-opcode
        # overlap (the 0x7A launch guard itself — a re-dispatch would
        # reload the fragment buffer mid-program). Only the second one
        # reaches fd_launch, so both are needed.
        for same_op in (False, True):

            def intrude(d, cyc, _at=at, _same=same_op):
                if cyc != _at:
                    return
                d.start.value = 1               # <- the illegal overlap
                if _same:
                    d.opcode_in.value = OPC_FDOTCR
                    d.dtype_in.value = 3
                else:
                    d.opcode_in.value = OPC_FSCALAR
                    d.subop_in.value = FS["FS_DIV"]
                    d.c_in.value = 0xDEADBEEF
                if _at >= 16:                   # ingress window is over
                    d.a_in.value = 0x7F7FFFFF
                    d.b_in.value = 0x0000_0001

            got, lat = await launch_fdotcr(dut, row["dtype"], row["payload"],
                                           f"interlock@{at}", poke=intrude)
            dut.opcode_in.value = OPC_FDOTCR
            dut.subop_in.value = 0
            dut.c_in.value = 0
            assert got == clean and lat == clean_lat, (
                f"overlapping start at cycle {at} "
                f"({'same' if same_op else 'foreign'} opcode) was NOT "
                f"ignored: {got:#010x}/{lat} vs clean "
                f"{clean:#010x}/{clean_lat}")
            assert int(dut.fd_fault.value) == 0
            assert int(dut.fd_spec.value) == 0

    # converse: 0x7A start raised while a scalar FS_DIV is in flight
    a, b = 0x3FC00000, 0x40490FDB
    exp = G.micro_fscalar(FS["FS_DIV"], a, b, 0)
    assert int(dut.busy.value) == 0
    dut.opcode_in.value = OPC_FSCALAR
    dut.subop_in.value = FS["FS_DIV"]
    dut.dtype_in.value = 0
    dut.a_in.value = a
    dut.b_in.value = b
    dut.c_in.value = 0
    dut.start.value = 1
    lat = 0
    while True:
        await FallingEdge(dut.clk)
        lat += 1
        dut.start.value = 0
        assert int(dut.busy.value) == 1
        if lat == 3:                            # mid-FS_DIV overlap
            dut.start.value = 1
            dut.opcode_in.value = OPC_FDOTCR
            dut.dtype_in.value = 3
            dut.a_in.value = row["payload"] & 0xFFFFFFFF
            dut.b_in.value = (row["payload"] >> 32) & 0xFFFFFFFF
        if int(dut.done.value):
            got = int(dut.result.value)
            break
        assert lat <= 32
    dut.opcode_in.value = OPC_FSCALAR
    dut.dtype_in.value = 0
    assert got == exp, (
        f"a 0x7A start raised mid-FS_DIV corrupted the shipped op: "
        f"{got:#010x} != {exp:#010x}")
    await FallingEdge(dut.clk)
    assert int(dut.busy.value) == 0 and int(dut.done.value) == 0
    # and the unit is still healthy for a real 0x7A right after
    got, lat = await launch_fdotcr(dut, row["dtype"], row["payload"],
                                   "interlock_post")
    assert got == clean and lat == clean_lat
    dut._log.info("busy-interlock: 8 mid-flight overlaps (4 phases x "
                  "{foreign, same} opcode) + 1 mid-FS_DIV 0x7A overlap all "
                  "ignored bit-for-bit (clean %#010x in %d cycles)",
                  clean, clean_lat)


@cocotb.test()
async def fdotcr_loud_fault_paths(dut):
    """Directed exercise of the three loud-fault families the spec pins
    as never-silent (§27.7a.2 capacity + STEP T vacuous-RTO / §27.7a.2a
    freeze). Legal operands can never reach any of them (measured
    expansion max 25 of 33; merge aligned width max 48 == the enforced
    bound; freeze violations 0 in 33,370 golden jams), so the probes
    inject at a known sub-sequencer phase — the point is that the PATH
    exists, raises the sticky and substitutes the canonical qNaN marker
    instead of returning wrong data.

    Each probe also pins WHICH guard fired (the sub-sequencer state the
    cycle before fd_fault rose). Without that the two capacity guards
    cover for each other: deleting either one still leaves a faulting
    dispatch, so a value-only check calls the mutant healthy."""
    await _start_clock(dut)
    rows = _load_fdotcr_vectors()
    finite = [r for r in rows if not r["special"]]
    victim = finite[0]

    class _FaultPhase:
        """Records the state fd_fault was raised FROM (registered fault =>
        the guard ran in the previously observed state)."""

        def __init__(self, inject):
            self.inject = inject
            self.prev = None
            self.at = None

        def __call__(self, d, cyc):
            if self.at is None and int(d.fd_fault.value):
                self.at = self.prev
            self.prev = int(d.fd_st.value)
            self.inject(d, cyc)

    # (a) array guard in FDS_PROD: force the stored count past the slot
    #     count right after the fragment window primes
    def poke_cap(d, _cyc):
        if int(d.fd_st.value) == FDS_PRIME:
            d.fd_n.value = 34                       # FD_TOP

    watch = _FaultPhase(poke_cap)
    got, lat = await launch_fdotcr(dut, victim["dtype"], victim["payload"],
                                   "fault_cap_guard", poke=watch)
    assert int(dut.fd_fault.value) == 1, "capacity guard did not raise"
    assert got == F32_QNAN, f"capacity fault returned {got:#010x}, not qNaN"
    assert watch.at == FDS_PROD, (
        f"capacity fault came from state {watch.at}, not the FDS_PROD "
        f"array guard — the probe is being caught by another guard")
    dut._log.info("loud fault (capacity guard, from FDS_PROD): qNaN + "
                  "sticky at %d cycles", lat)

    # (b) §27.7a.2 3-way assert (1): the post-walk capacity assert in
    #     FDS_NEXT, reached from a skipped (zero-contribution) lane
    zero_pay = 0
    for i in range(GF.GROUP):                       # bf16 1.0 on every lane
        zero_pay |= 0x3F80 << (16 * i)
        zero_pay |= 0x3F80 << (512 + 16 * i)
    zero_pay &= ~(0xFFFF << 16)                     # lane 1 A := +0 -> skip

    def poke_next(d, _cyc):
        # inject on the SKIPPED lane, whose FDS_LANE arm jumps straight to
        # FDS_NEXT without passing the FDS_PROD array guard
        if int(d.fd_st.value) == FDS_LANE and int(d.fd_cnt.value) == 1:
            d.fd_n.value = 34

    watch = _FaultPhase(poke_next)
    got, lat = await launch_fdotcr(dut, 3, zero_pay, "fault_cap_assert",
                                   poke=watch)
    assert int(dut.fd_fault.value) == 1, "capacity assert did not raise"
    assert got == F32_QNAN
    assert watch.at == FDS_NEXT, (
        f"capacity fault came from state {watch.at}, not the FDS_NEXT "
        f"post-walk assert")
    dut._log.info("loud fault (capacity assert, from FDS_NEXT): qNaN + "
                  "sticky at %d cycles", lat)

    # (c) freeze violation (§27.7a.2a graduation axis): mark the fold as
    #     jammed before its first pass; that pass necessarily changes the
    #     accumulator, which is exactly the theorem-(4) collapse — and it
    #     is the FIRST post-jam pass, the case the pre-repair watch window
    #     (armed only after an observed unchanged pass) could not see
    def poke_jam(d, _cyc):
        if int(d.fd_st.value) == FDS_FOLDW and int(d.fd_wait.value) != 0:
            d.fd_jam.value = 1

    got, lat = await launch_fdotcr(dut, victim["dtype"], victim["payload"],
                                   "fault_freeze", poke=poke_jam)
    assert int(dut.fd_fault.value) == 1, "freeze violation did not raise"
    assert got == F32_QNAN, f"freeze fault returned {got:#010x}, not qNaN"
    dut._log.info("loud fault (freeze): qNaN + sticky at %d cycles", lat)

    # (d) STEP T vacuous-RTO collapse (golden's own `vacuous-RTO
    #     violated` FdotFault, which had NO RTL counterpart before the
    #     3a-C3 repair — an inexact merge silently breaks exact-sum
    #     preservation). Legal columns cannot reach it (the merge branch
    #     is only taken for overlapping pairs, whose aligned width is
    #     structurally <= 48), so the probe swaps the walk's upper
    #     partner for a component 1,000+ binades below: the pair still
    #     reads as overlapping, but the pass now genuinely rounds.
    fired = {"hit": False}

    def poke_vacrto(d, _cyc):
        if fired["hit"] or int(d.fd_st.value) != FDS_WALK:
            return
        w = int(d.fd_w.value)
        if w + 1 >= int(d.fd_n.value):
            return
        fired["hit"] = True
        d.fd_xp[w + 1].value = (0xC18 << 24) | 0x800001   # xe = -1000
    got, lat = await launch_fdotcr(dut, victim["dtype"], victim["payload"],
                                   "fault_vacuous_rto", poke=poke_vacrto)
    assert fired["hit"], "the probe never reached the walk"
    assert int(dut.fd_fault.value) == 1, "vacuous-RTO guard did not raise"
    assert got == F32_QNAN, f"vacuous-RTO fault returned {got:#010x}"
    dut._log.info("loud fault (vacuous-RTO merge): qNaN + sticky at %d "
                  "cycles", lat)

    # (e) a theorem-(4) collapse on the FIRST pass after the watch window
    #     opens, reached WITHOUT poking the anchor itself: the fold runs
    #     untouched until the RTL raises fd_jam on its own, then the
    #     stored accumulator is corrupted one cycle before the next pass
    #     retires (FP_AddWide sampled its operands three edges earlier,
    #     so the pass result stays honest and only the stored acc moves).
    #     SCOPE OF THIS PROBE, stated precisely: it proves the fault PATH
    #     is live from the very first post-anchor pass. It does NOT prove
    #     the anchor sits at the jam — a late anchor would simply arm
    #     later and still fault here. That claim is measured separately,
    #     on 128 rows, by fdotcr_freeze_axis_jam_anchored, which is what
    #     kills the draft (acc_same-only) anchor.
    collapse = {"armed": False}

    def poke_collapse(d, _cyc):
        if collapse["armed"] or int(d.fd_st.value) != FDS_FOLDW:
            return
        if int(d.fd_jam.value) == 1 and int(d.fd_wait.value) == 1:
            d.fd_accm.value = int(d.fd_accm.value) ^ 1
            collapse["armed"] = True

    for row in finite:
        got, lat = await launch_fdotcr(dut, row["dtype"], row["payload"],
                                       "fault_first_post_jam",
                                       poke=poke_collapse)
        if collapse["armed"]:
            break
    assert collapse["armed"], "no vector jammed early enough to probe"
    assert int(dut.fd_fault.value) == 1, (
        "a collapse on the FIRST post-jam pass went unnoticed — that is "
        "precisely the pre-repair freeze hole (§27.7a.2b amendment-11)")
    assert got == F32_QNAN, f"first-post-jam collapse returned {got:#010x}"
    dut._log.info("loud fault (collapse on the first post-jam pass): qNaN "
                  "+ sticky at %d cycles", lat)

    # and the clean re-launch afterwards must be unaffected (the sticky is
    # per-dispatch state, cleared at launch)
    got, _ = await launch_fdotcr(dut, victim["dtype"], victim["payload"],
                                 "post_fault_clean")
    assert int(dut.fd_fault.value) == 0 and got == victim["result"], \
        "a faulted dispatch poisoned the next clean one"


@cocotb.test()
async def fdotcr_back_to_back_isolation(dut):
    """§27.7a.5 capture-mux contamination vectors: 0x7A interleaved
    back-to-back with EVERY pre-3a op class in both directions. A
    non-launching op must be bit-unaffected by the new capture path and
    vice versa (§23.10.10(h) item 4 — the subtle capture-mux regression
    is a SILENT WRONG DATA class, so it is checked by value, not by
    liveness)."""
    await _start_clock(dut)
    rng = random.Random(0x7ADC3B2)
    rows = [r for r in _load_fdotcr_vectors() if not r["special"]]
    payload64 = (rng.getrandbits(32) << 32) | rng.getrandbits(32)
    for k, row in enumerate(rows[:24]):
        got, _ = await launch_fdotcr(dut, row["dtype"], row["payload"],
                                     f"b2b L{row['line']}")
        assert got == row["result"], f"b2b L{row['line']}: {got:#010x}"
        a, b, c = rand_fp(rng), rand_fp(rng), rand_fp(rng)
        which = k % 9
        if which == 0:
            await check_fscalar(dut, FS["FS_ADD"], a, b, label="b2b_add")
        elif which == 1:
            await check_fscalar(dut, FS["FS_SUB"], a, b, label="b2b_sub")
        elif which == 2:
            await check_fscalar(dut, FS["FS_MUL"], a, b, label="b2b_mul")
        elif which == 3:
            await check_fscalar(dut, FS["FS_FMA"], a, b, c, label="b2b_fma")
        elif which == 4:
            await check_fscalar(dut, FS["FS_DIV"], a, b, label="b2b_div")
        elif which == 5:
            await check_rsqrt(dut, a, label="b2b_rsq")
        elif which == 6:
            await check_exp2(dut, a, label="b2b_exp2")
        elif which == 7:
            await check_cvt(dut, CVT_NAR, 3, payload64, label="b2b_cvt")
            await check_accew(dut, a, payload64, label="b2b_accew")
        else:
            await check_dequant(dut, 1, rng.getrandbits(32), b,
                                label="b2b_deq")
        # and back the other way round: the just-run scalar op must not
        # have disturbed the 0x7A path either
        got, _ = await launch_fdotcr(dut, row["dtype"], row["payload"],
                                     f"b2b2 L{row['line']}")
        assert got == row["result"], f"b2b2 L{row['line']}: {got:#010x}"
    dut._log.info("fdotcr back-to-back isolation: 24 x (0x7A, scalar op, "
                  "0x7A) triples bit-exact in both directions")


@cocotb.test()
async def fdotcr_illegal_dtype_rows_terminate(dut):
    """§27.7a.1 restrictive-first: EXACTLY two legal dtype rows (0x2 f16 /
    0x3 bf16). Every other dtype falls to the module's don't-care arm.
    Only LIVENESS is asserted here (no hang, no stuck busy) — the
    don't-care return value is explicitly NON-contractual (module header),
    so pinning it would be a spec invention."""
    await _start_clock(dut)
    row = _load_fdotcr_vectors()[0]
    for dt in (0, 1, 4, 5, 8, 15):
        _, lat = await launch_fdotcr(dut, dt, row["payload"],
                                     f"illegal_dt{dt}", cap=64)
        assert lat <= 8, f"dtype {dt}: don't-care arm took {lat} cycles"
    # the legal rows still work right after
    got, _ = await launch_fdotcr(dut, row["dtype"], row["payload"], "legal")
    assert got == row["result"]
    dut._log.info("fdotcr illegal dtype rows: 6 rows terminate in <= 8 "
                  "cycles; legal row unaffected")


@cocotb.test()
async def fdotcr_extended_family_sweep(dut):
    """STRENGTHENING (never a weakening — §27.7a.2a amendment-5 discipline):
    the 450-line vector file carries only the FIRST 30 trials per family,
    so this suite re-generates FRESH trials from the golden generators on
    a DISTINCT fixed seed and drives them through the RTL.

    Oracle = GF._independent_expected — the Fraction path that never
    touches the EFT (golden_lattice.operand_frac x acc_format_study.
    pack_signed). Using the EFT twin here would re-confirm the algorithm
    with itself; the independent path is the same self-confirmation-loop
    block the C1 audit put on the vector emitter.

    This is also the measurement that §27.7a.2a amendment-3 assigned to
    3a-C3: the refined insertion walk's queue-scan cycles were UNCOUNTED
    in the nominal budget, so the worst start->done latency here is the
    number that graduates the estimate."""
    await _start_clock(dut)
    per_fam = {}
    n_total = 0
    for fi, (fam, gen) in enumerate(GF.FAM_GENS):
        rng = random.Random(0x7ADC3C0 + fi)     # fixed — deterministic re-run
        worst = 0
        for _ in range(300):
            dtype, pairs = gen(rng)
            exp_bits, exp_sp, _ = GF._independent_expected(dtype, pairs)
            payload = 0
            for f, w in enumerate(
                    G.lanes_to_frags([a for a, _ in pairs], 16)
                    + G.lanes_to_frags([b for _, b in pairs], 16)):
                payload |= w << (64 * f)
            got, lat = await launch_fdotcr(dut, dtype, payload, f"ext_{fam}")
            assert got == exp_bits, (
                f"ext_{fam}: dtype={dtype:#x} got {got:#010x} expected "
                f"{exp_bits:#010x} (independent Fraction oracle)")
            assert int(dut.fd_spec.value) == exp_sp, \
                f"ext_{fam}: sticky {int(dut.fd_spec.value)} != {exp_sp}"
            assert int(dut.fd_fault.value) == 0, f"ext_{fam}: loud fault"
            worst = max(worst, lat)
            n_total += 1
        per_fam[fam] = worst
        if worst > _fdot_worst["cycles"]:
            _fdot_worst.update(cycles=worst, line=-1, fam=fi)
    dut._log.info("fdotcr extended sweep: %d fresh trials bit-exact vs the "
                  "EFT-independent oracle", n_total)
    dut._log.info("fdotcr extended per-family worst cycles: %s",
                  ", ".join(f"{k}:{v}" for k, v in per_fam.items()))
    dut._log.info("fdotcr GLOBAL worst start->done = %d cycles vs the "
                  "§27.7a.2 hard ceiling %d (headroom %.1fx)",
                  _fdot_worst["cycles"], FDOT_CAP,
                  FDOT_CAP / max(_fdot_worst["cycles"], 1))
    assert _fdot_worst["cycles"] <= FDOT_CAP
