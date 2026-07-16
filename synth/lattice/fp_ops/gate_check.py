#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""gate_check.py — evaluate v1.8.0c synth Gates 1-3 (spec §23.10.7) from
the measured yosys stat + nextpnr report files produced by
synth/lattice/scripts/synth_fp_ops.sh. Writes gate_summary.txt into the
report dir and exits nonzero if any gate criterion fails.

Pass criteria (merge blockers):
  GATE 1 fp_mul36   : MULT18X18D <= 4 (hard fail on decomposition to more),
                      LUT4 <= 300, Fmax >= 40 MHz
  GATE 2 fp_addwide : LUT4 <= 900, MULT18X18D == 0, Fmax >= 40 MHz
  GATE 3 fp_stepseq : whole unit (step sequencer + FP_Mul36 + FP_AddWide +
                      seed/coeff ROMs) — LUT4 <= 2000, MULT18X18D == 4
                      EXACTLY (the unit instantiates ONE FP_Mul36 and
                      nothing else may infer a multiplier), TRELLIS_FF
                      <= 900 net of the 143 gate-top wrapper I/O flops
                      (109 input + 34 output bits — see
                      FP_StepSeq_gate_top.v), EBR == 0 (distributed ROM;
                      spec allows a DOCUMENTED 1-EBR fallback, which this
                      checker deliberately does NOT auto-pass — flip the
                      limit only with the documentation in place),
                      Fmax >= 40 MHz
"""

import json
import re
import sys
from pathlib import Path

FREQ_TARGET = 40.0

GATES = [
    # name: max_lut4, mult (max unless exact), ff criterion (None = info),
    #       wrapper_ff subtracted from the FF measurement before the check
    {"name": "fp_mul36",   "max_lut4": 300,  "mult": 4, "mult_exact": False,
     "max_ff": None, "wrapper_ff": 0,   "max_ebr": 0},
    {"name": "fp_addwide", "max_lut4": 900,  "mult": 0, "mult_exact": False,
     "max_ff": None, "wrapper_ff": 0,   "max_ebr": 0},
    {"name": "fp_stepseq", "max_lut4": 2000, "mult": 4, "mult_exact": True,
     "max_ff": 900,  "wrapper_ff": 143, "max_ebr": 0},
]

# every ECP5 block-RAM cell type yosys memory_bram can emit
EBR_CELLS = ("DP16KD", "PDPW16KD", "DP16KD_COMB")


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

    for i, g in enumerate(GATES, start=1):
        name = g["name"]
        cells = parse_stat(rpt_dir / f"{name}_synth.rpt")
        lut4 = cells.get("LUT4", 0)
        mult = cells.get("MULT18X18D", 0)
        ff = cells.get("TRELLIS_FF", 0)
        ccu2 = cells.get("CCU2C", 0)
        ebr = sum(cells.get(c, 0) for c in EBR_CELLS)
        fmax = parse_fmax(rpt_dir / f"{name}_pnr.rpt")

        ok_lut = lut4 <= g["max_lut4"]
        ok_mult = (mult == g["mult"]) if g["mult_exact"] else \
            (mult <= g["mult"])
        ok_ebr = ebr <= g["max_ebr"]
        ok_fmax = fmax >= FREQ_TARGET
        ff_unit = ff - g["wrapper_ff"]
        ok_ff = True if g["max_ff"] is None else ff_unit <= g["max_ff"]
        ok = ok_lut and ok_mult and ok_ff and ok_ebr and ok_fmax
        all_pass &= ok

        mult_crit = (f"exactly {g['mult']}" if g["mult_exact"]
                     else f"limit {g['mult']}")
        if g["max_ff"] is None:
            ff_line = f"    TRELLIS_FF = {ff:5d}   (informational)"
        else:
            ff_line = (
                f"    TRELLIS_FF = {ff:5d}   raw; unit = {ff_unit} after "
                f"-{g['wrapper_ff']} wrapper I/O flops (limit {g['max_ff']})"
                f"   -> {'PASS' if ok_ff else 'FAIL'}")
        lines += [
            f"GATE {i} — {name} (LFE5UM-85F CABGA381 -6, out-of-context, "
            f"yosys synth_ecp5 + nextpnr-ecp5, wrapper-top incl. I/O regs):",
            f"    LUT4       = {lut4:5d}   (limit {g['max_lut4']})"
            f"   -> {'PASS' if ok_lut else 'FAIL'}",
            f"    MULT18X18D = {mult:5d}   ({mult_crit})"
            f"   -> {'PASS' if ok_mult else 'FAIL'}",
            ff_line,
            f"    EBR        = {ebr:5d}   (limit {g['max_ebr']}, "
            f"cells {'/'.join(EBR_CELLS)})"
            f"   -> {'PASS' if ok_ebr else 'FAIL'}",
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
    print("synth_fp_ops: Gates 1-3 PASS")


if __name__ == "__main__":
    main()
