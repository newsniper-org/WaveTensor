#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""gate_check.py — evaluate v1.8.0c synth Gates 1 & 2 (spec §23.10.7) from
the measured yosys stat + nextpnr report files produced by
synth/lattice/scripts/synth_fp_ops.sh. Writes gate_summary.txt into the
report dir and exits nonzero if any gate criterion fails.

Pass criteria (merge blockers):
  GATE 1 fp_mul36   : MULT18X18D <= 4 (hard fail on decomposition to more),
                      LUT4 <= 300, Fmax >= 40 MHz
  GATE 2 fp_addwide : LUT4 <= 900, MULT18X18D == 0, Fmax >= 40 MHz
"""

import json
import re
import sys
from pathlib import Path

FREQ_TARGET = 40.0

GATES = [
    # name,        max LUT4, max MULT18X18D
    ("fp_mul36",   300,      4),
    ("fp_addwide", 900,      0),
]


def parse_stat(path):
    """yosys `stat` report -> {cell_type: count}."""
    cells = {}
    for line in Path(path).read_text().splitlines():
        m = re.match(r"\s+(\d+)\s+([A-Za-z0-9_$]+)\s*$", line)
        if m:
            cells[m.group(2)] = int(m.group(1))
    return cells


def parse_fmax(path):
    """nextpnr JSON report -> min achieved Fmax over all clock domains."""
    rpt = json.loads(Path(path).read_text())
    fmax = rpt.get("fmax", {})
    achieved = [v["achieved"] for v in fmax.values()]
    if not achieved:
        sys.exit(f"{path}: no fmax entries in nextpnr report")
    return min(achieved)


def main():
    rpt_dir = Path(sys.argv[1] if len(sys.argv) > 1 else
                   "synth/lattice/reports/fp_ops")
    lines = []
    all_pass = True

    for i, (name, max_lut, max_mult) in enumerate(GATES, start=1):
        cells = parse_stat(rpt_dir / f"{name}_synth.rpt")
        lut4 = cells.get("LUT4", 0)
        mult = cells.get("MULT18X18D", 0)
        ff = cells.get("TRELLIS_FF", 0)
        ccu2 = cells.get("CCU2C", 0)
        fmax = parse_fmax(rpt_dir / f"{name}_pnr.rpt")

        ok_lut = lut4 <= max_lut
        ok_mult = mult <= max_mult
        ok_fmax = fmax >= FREQ_TARGET
        ok = ok_lut and ok_mult and ok_fmax
        all_pass &= ok

        lines += [
            f"GATE {i} — {name} (LFE5UM-85F CABGA381 -6, out-of-context, "
            f"yosys synth_ecp5 + nextpnr-ecp5, wrapper-top incl. I/O regs):",
            f"    LUT4       = {lut4:5d}   (limit {max_lut})"
            f"   -> {'PASS' if ok_lut else 'FAIL'}",
            f"    MULT18X18D = {mult:5d}   (limit {max_mult})"
            f"   -> {'PASS' if ok_mult else 'FAIL'}",
            f"    TRELLIS_FF = {ff:5d}   (informational)",
            f"    CCU2C      = {ccu2:5d}   (informational, carry cells)",
            f"    Fmax       = {fmax:8.2f} MHz (target >= {FREQ_TARGET})"
            f"   -> {'PASS' if ok_fmax else 'FAIL'}",
            f"    GATE {i} RESULT: {'PASS' if ok else 'FAIL'}",
            "",
        ]

    summary = "\n".join(lines)
    print(summary)
    (rpt_dir / "gate_summary.txt").write_text(summary + "\n")
    if not all_pass:
        sys.exit("synth_fp_ops: GATE FAILURE — see gate_summary.txt")
    print("synth_fp_ops: Gates 1 and 2 PASS")


if __name__ == "__main__":
    main()
