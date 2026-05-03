# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

"""Pretty-printer for the key metrics in Vivado reports.

Reads the most recent synth/impl reports for a given Pod geometry,
extracts LUT / FF / BRAM / DSP utilization, WNS / TNS / WHS, and (if
implementation has run) total on-chip power, then emits a one-page
summary for the README / progress reports.

Usage:
    python synth/parse_reports.py [GEOMETRY]

GEOMETRY defaults to "2x2_2x2" — matches the Pod default. Use e.g.
"4x4_2x2" for a wider PE grid.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
REPORT_DIR = REPO / "synth" / "reports"


def _slurp(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(errors="replace")


def parse_utilization(text: str) -> dict:
    """Extract top-level resource usage. Vivado emits two report styles:
       (a) hierarchical (`-hierarchical`)  — has a "Pod (top)" row at the start
       (b) flat — has summary tables for "Slice LUTs", "DSPs", etc.
    We try both."""
    out = {}

    # (a) Hierarchical: first row "Pod | (top) | <luts> | <logic> | <lutram>
    #                        | <srl> | <ffs> | <ramb36> | <ramb18> [| <uram>]
    #                        | <dsp> |"
    # UltraScale+ inserts a URAM column between RAMB18 and DSP; older
    # families (Spartan/Artix 7) skip it. Match both shapes.
    m = re.search(
        r"\|\s*Pod\s*\|\s*\(top\)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*\d+\s*\|"
        r"\s*\d+\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|"
        r"(?:\s*(\d+)\s*\|)?\s*(\d+)\s*\|",
        text,
    )
    if m:
        total_luts, _logic_luts, ffs, ramb36, ramb18, uram, dsp = m.groups()
        out["LUT"] = (int(total_luts), 0, 0.0)
        out["FF"] = (int(ffs), 0, 0.0)
        out["BRAM"] = (int(ramb36) + int(ramb18), 0, 0.0)
        out["URAM"] = (int(uram or 0), 0, 0.0)
        out["DSP"] = (int(dsp), 0, 0.0)

    # (b) Flat summary: e.g. "| Slice LUTs* | 12345 | 0 | 67890 | 18.18 |"
    for key, label in [
        ("CLB LUTs",       "LUT"),
        ("Slice LUTs",     "LUT"),
        ("CLB Registers",  "FF"),
        ("Slice Registers","FF"),
        ("Block RAM Tile", "BRAM"),
        ("DSPs",           "DSP"),
    ]:
        m = re.search(
            rf"\|\s*{re.escape(key)}\*?\s*\|\s*(\d+)\s*\|.*?\|\s*"
            rf"(\d+)\s*\|\s*([\d.]+)\s*\|",
            text,
        )
        if m:
            used, avail, util = m.group(1), m.group(2), m.group(3)
            # Prefer flat data (has avail/util) over hierarchical (no avail).
            out[label] = (int(used), int(avail), float(util))
    return out


def parse_timing(text: str) -> dict:
    """Extract WNS/TNS from the 'Design Timing Summary' table — first
    row of numbers under the WNS/TNS/etc. header line."""
    out = {}
    m = re.search(
        r"WNS\(ns\)\s+TNS\(ns\).*?\n\s*-+\s+-+.*?\n"
        r"\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s+"
        r"(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)",
        text, re.S,
    )
    if m:
        out["WNS"] = float(m.group(1))
        out["TNS"] = float(m.group(2))
        out["Failing endpoints (setup)"] = int(m.group(3))
        out["WHS"] = float(m.group(5))
        out["Failing endpoints (hold)"] = int(m.group(7))
    # Fallback: explicit "Setup : ... Worst Slack ..." line
    m2 = re.search(r"Setup\s*:\s*(\d+)\s*Failing Endpoints,\s*Worst Slack\s*"
                   r"(-?[\d.]+)\s*ns,\s*Total Violation\s*(-?[\d.]+)", text)
    if m2 and "WNS" not in out:
        out["Failing endpoints (setup)"] = int(m2.group(1))
        out["WNS"] = float(m2.group(2))
        out["TNS"] = float(m2.group(3))
    return out


def parse_power(text: str) -> dict:
    out = {}
    m = re.search(r"\|\s*Total On-Chip Power\s*\(W\)\s*\|\s*([\d.]+)\s*\|", text)
    if m:
        out["Total Power (W)"] = float(m.group(1))
    m = re.search(r"\|\s*Dynamic\s*\(W\)\s*\|\s*([\d.]+)\s*\|", text)
    if m:
        out["Dynamic (W)"] = float(m.group(1))
    m = re.search(r"\|\s*Device Static\s*\(W\)\s*\|\s*([\d.]+)\s*\|", text)
    if m:
        out["Static (W)"] = float(m.group(1))
    return out


def fmt_util(label: str, vals) -> str:
    used, avail, util = vals
    return f"  {label:<6} : {used:>7} / {avail:<7} ({util:>5.2f}%)"


def main(geom: str) -> int:
    print(f"WaveTensor — synthesis report ({geom})")
    print(f"Reports root : {REPORT_DIR}")
    print()

    # Synthesis reports
    synth_util = REPORT_DIR / f"pod_{geom}_synth_util.rpt"
    synth_time = REPORT_DIR / f"pod_{geom}_synth_timing.rpt"

    if synth_util.exists():
        print(f"--- post-synthesis ({synth_util.name}) ---")
        u = parse_utilization(_slurp(synth_util))
        for lab in ("LUT", "FF", "BRAM", "DSP"):
            if lab in u:
                print(fmt_util(lab, u[lab]))
        if synth_time.exists():
            t = parse_timing(_slurp(synth_time))
            if t:
                print()
                print("  Timing (synthesis estimate):")
                for k, v in t.items():
                    if "endpoints" in k:
                        print(f"    {k:<28}: {v:>8.0f}")
                    else:
                        print(f"    {k:<28}: {v:>+8.3f} ns")
        print()
    else:
        print("No synthesis reports found — run `make synth-pod` first.")
        return 1

    # Implementation reports
    impl_util = REPORT_DIR / f"pod_{geom}_impl_util.rpt"
    impl_time = REPORT_DIR / f"pod_{geom}_impl_timing.rpt"
    impl_pow  = REPORT_DIR / f"pod_{geom}_impl_power.rpt"

    if impl_util.exists():
        print(f"--- post-implementation ({impl_util.name}) ---")
        u = parse_utilization(_slurp(impl_util))
        for lab in ("LUT", "FF", "BRAM", "DSP"):
            if lab in u:
                print(fmt_util(lab, u[lab]))
        if impl_time.exists():
            t = parse_timing(_slurp(impl_time))
            if t:
                print()
                print("  Timing (post-route, signed off):")
                for k, v in t.items():
                    if "endpoints" in k:
                        print(f"    {k:<28}: {v:>8.0f}")
                    else:
                        print(f"    {k:<28}: {v:>+8.3f} ns")
        if impl_pow.exists():
            p = parse_power(_slurp(impl_pow))
            if p:
                print()
                print("  Power (estimated):")
                for k, v in p.items():
                    print(f"    {k:<18}: {v:>5.3f} W")
    else:
        print("Implementation reports not found — run `make impl-pod` to "
              "complete place + route.")

    return 0


if __name__ == "__main__":
    geom = sys.argv[1] if len(sys.argv) > 1 else "2x2_2x2"
    sys.exit(main(geom))
