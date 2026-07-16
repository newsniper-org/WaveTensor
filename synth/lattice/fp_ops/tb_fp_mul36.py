# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""tb_fp_mul36 — correctness sanity for FP_Mul36 (v1.8.0c shared multiplier,
spec §23.10.7 Gate 1) BEFORE synthesis.

FP_Mul36 is a raw 36x36 -> 72 unsigned integer multiplier, latency exactly
2, one result per cycle. Reference = python ints (p == a*b). Vectors:

  * directed edges (0, 1, 2^35, 2^36-1, single-bit walks, 18-bit-limb
    boundary patterns) so each MULT18X18D partial product is exercised
    alone and in combination;
  * 10^4 uniform random 36x36 pairs, driven BACK-TO-BACK (a new operand
    pair every cycle) — this also proves the 1-result-per-cycle always-
    flowing contract and the exact-2-cycle latency (the expected-value
    queue is keyed to cycle index).

Invoked by run_fp_ops_tests.py (self-contained runner — the main Makefile
is untouched).
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge

MASK36 = (1 << 36) - 1
NUM_RANDOM = 10_000


def _directed_vectors():
    edge = [0, 1, 2, 3, (1 << 18) - 1, 1 << 18, (1 << 18) + 1,
            (1 << 35), (1 << 36) - 1, (1 << 36) - 2,
            0x800000001, 0xAAAAAAAAA & MASK36, 0x555555555 & MASK36]
    vecs = [(a, b) for a in edge for b in edge]
    # single-bit walks against all-ones (carry propagation through the
    # stage-2 recombination adder)
    for i in range(36):
        vecs.append((1 << i, MASK36))
        vecs.append((MASK36, 1 << i))
    # 24x24 mantissa-product shape (the fp32 use) and Q2.30 step shape
    for _ in range(200):
        ma = random.getrandbits(23) | (1 << 23)
        mb = random.getrandbits(23) | (1 << 23)
        vecs.append((ma, mb))
        vecs.append((random.getrandbits(32), random.getrandbits(32)))
    return vecs


@cocotb.test()
async def mul36_exhaustiveish(dut):
    random.seed(0x36C0FFEE)
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    vectors = _directed_vectors()
    vectors += [(random.getrandbits(36), random.getrandbits(36))
                for _ in range(NUM_RANDOM)]

    pending = []          # (a, b) pairs in flight, depth == latency == 2
    checked = 0
    dut.a.value = 0
    dut.b.value = 0
    await FallingEdge(dut.clk)

    for a, b in vectors:
        # check the result that must be visible now (driven 2 edges ago)
        if len(pending) == 2:
            ea, eb = pending.pop(0)
            got = int(dut.p.value)
            exp = ea * eb
            assert got == exp, (
                f"FP_Mul36 mismatch after {checked} ok: "
                f"a={ea:#011x} b={eb:#011x} got={got:#019x} exp={exp:#019x}")
            checked += 1
        dut.a.value = a
        dut.b.value = b
        pending.append((a, b))
        await FallingEdge(dut.clk)

    # drain the last two in-flight results
    while pending:
        ea, eb = pending.pop(0)
        got = int(dut.p.value)
        exp = ea * eb
        assert got == exp, (
            f"FP_Mul36 drain mismatch: a={ea:#011x} b={eb:#011x} "
            f"got={got:#019x} exp={exp:#019x}")
        checked += 1
        await FallingEdge(dut.clk)

    dut._log.info("FP_Mul36: %d/%d vectors bit-exact (latency 2, "
                  "back-to-back)", checked, len(vectors))
    assert checked == len(vectors)
