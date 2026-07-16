#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""run_fp_ops_tests.py — self-contained cocotb runner for the v1.8.0c fp32
operator blocks (FP_Mul36 / FP_AddWide), the mandatory correctness sanity
BEFORE synth Gates 1 and 2 (spec §23.10.7).

Deliberately separate from the repo's main cocotb Makefile (MOD=... flow):
these blocks gate on standalone synthesis before any PE_Core wiring
exists, so the harness lives here with them. Uses the cocotb 2.x Python
runner API with the same verilator backend as the main flow.

Usage:
    python3 synth/lattice/fp_ops/run_fp_ops_tests.py [FP_Mul36|FP_AddWide]

Build artifacts go to $WT_FP_OPS_BUILD (default: a fresh temp dir).
"""

import os
import sys
import tempfile
from pathlib import Path

from cocotb_tools.check_results import get_results
from cocotb_tools.runner import get_runner

REPO = Path(__file__).resolve().parents[3]
FP_OPS = Path(__file__).resolve().parent

TESTS = {
    "FP_Mul36": {
        "sources": [REPO / "FP_Mul36.v"],
        "test_module": "tb_fp_mul36",
    },
    "FP_AddWide": {
        "sources": [REPO / "FP_AddWide.v"],
        "test_module": "tb_fp_addwide",
    },
}


def run_one(top, build_root):
    cfg = TESTS[top]
    runner = get_runner("verilator")
    build_dir = Path(build_root) / top
    runner.build(
        sources=[str(s) for s in cfg["sources"]],
        includes=[str(REPO / "include")],
        hdl_toplevel=top,
        build_dir=str(build_dir),
        waves=False,
    )
    results_xml = runner.test(
        hdl_toplevel=top,
        test_module=cfg["test_module"],
        build_dir=str(build_dir),
        test_dir=str(build_dir),
    )
    num_tests, num_failed = get_results(results_xml)
    if num_failed:
        sys.exit(f"{top}: {num_failed}/{num_tests} cocotb tests FAILED "
                 f"(results: {results_xml})")
    print(f"{top}: {num_tests} cocotb tests passed")


def main():
    wanted = sys.argv[1:] or list(TESTS)
    for top in wanted:
        if top not in TESTS:
            sys.exit(f"unknown top '{top}' (valid: {', '.join(TESTS)})")

    build_root = os.environ.get("WT_FP_OPS_BUILD") or tempfile.mkdtemp(
        prefix="wt_fp_ops_")
    # the tb modules import golden_fp32 themselves; make them importable
    sys.path.insert(0, str(FP_OPS))
    os.environ["PYTHONPATH"] = os.pathsep.join(
        [str(FP_OPS), os.environ.get("PYTHONPATH", "")])

    for top in wanted:
        print(f"=== {top}: build + test (build dir: {build_root}) ===")
        run_one(top, build_root)
    print("run_fp_ops_tests: all requested suites passed")


if __name__ == "__main__":
    main()
