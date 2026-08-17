#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""fp_op_gate_check.py — evaluate the per-operator UltraScale+ gates from
the artifacts produced by synth/scripts/synth_fp_op.tcl, the Vivado
counterpart of synth/lattice/fp_ops/gate_check.py.

Reads, for each gate tag:
    synth/reports/fp_ops/<tag>_impl_summary.json   (tcl-emitted raw counts,
                                                    post-route WNS/WHS/Fmax)
    synth/reports/fp_ops/<tag>_impl_util.rpt       (Vivado hierarchical
                                                    utilization — the LUT
                                                    SITE count and the
                                                    per-submodule split)
    synth/reports/fp_ops/<tag>_impl_drc.rpt        (post-route DRC — the
                                                    gate FAILS on any
                                                    Error/Critical, and
                                                    every Warning is
                                                    LISTED in the summary
                                                    so "DRC clean" can
                                                    never be claimed where
                                                    the truth is "0
                                                    errors, N warnings")
Writes synth/reports/fp_ops/gate_summary.txt and exits nonzero on failure.

WHY THE CRITERIA LOOK DIFFERENT FROM THE ECP5 GATE'S
----------------------------------------------------
The ECP5 gate is an AREA gate: an LFE5U-85F has 83,640 LUT4 and 156
MULT18X18D, so every operator competes for a scarce budget and each gate
carries a pre-declared LUT4/MULT ceiling. UltraScale+ is not that fabric:
xcu55c has 1,303,680 LUTs and 9,024 DSP48E2, and the whole 2x2x2x2 Pod
uses 13.1% / 1.7% of them. Declaring an area ceiling here would be
theatre. What UltraScale+ is uniquely able to answer is the question spec
risk 2 actually asks — "a 5-6 stage fused FMA at 100 MHz is unproven; v2.0's
first milestone is producing an Fmax" — so the HARD criteria here are:

  * Fmax >= 100 MHz post-ROUTE (never post-synth: on this project the same
    design measured WNS -1.835 ns after synth and -0.205 ns after route)
  * DSP48 <= the structural per-lane budget (an 11x11 significand multiply
    needs at most ONE DSP; 2+ means the mapper split a multiply this
    small, which is the yosys-vs-Vivado divergence class the per-operator
    gates exist for)
  * BRAM == 0 (no operator core may infer block RAM)
  * WHS >= 0 (no hold violations after route)

LUT / FF are reported as INFORMATIONAL, with the lane-count arithmetic the
numbers feed, because the spec carries no UltraScale+ area budget yet.
"""

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
RPT_DIR = REPO / "synth" / "reports" / "fp_ops"

FMAX_TARGET = 100.0

GATES = [
    {
        "tag": "fp_fmalane_bf16",
        "label": "GATE F1-US",
        "desc": "v2.0 TRAIN unified bf16/f16 fused-FMA lane (spec §23.1) "
                "— PRIMARY: xcu55c is EC2 F2's exact silicon",
        "max_dsp48": 1,
        "dsp_note": "one 11x11 significand multiply = at most ONE DSP48E2",
    },
    {
        "tag": "fp_fmalane_bf16_xcu50",
        "label": "GATE F1-US/xcu50",
        "desc": "same lane, speed-grade cross-check on xcu50 (-2)",
        "max_dsp48": 1,
        "dsp_note": "one 11x11 significand multiply = at most ONE DSP48E2",
    },
    {
        # GATE V20-2 (spec §27.6) — the xcu55c half is the gate's ONLY
        # merge-blocker binding (user directive 2026-08-15; the ECP5 half is
        # a feasibility MEASUREMENT and can never constitute gate FAIL).
        # Binding criteria: (a) LUT hard ceiling, (b) DSP48 == 0 AND premap
        # $mul == 0. Fmax/WNS at the 100 MHz harness clock are RECORDED —
        # §27.6's "resolve fits 1 cycle @ 100 MHz" graduates from ESTIMATE
        # to measurement here, but the merge verdict rides on (a)/(b).
        "tag": "fp_acclattice",
        "label": "GATE V20-2/US",
        "desc": "v2.0 528-bit exact-integer lattice unit "
                "(spec §27.2/§27.6) — xcu55c half = the ONLY merge-blocker "
                "binding of GATE V20-2",
        "max_dsp48": 0,
        "dsp_note": "lattice is add/shift/compare ONLY — any DSP48 means "
                    "the mapper found a multiply that must not exist",
        "max_lut_sites": 20040,
        "lut_note": "hard ceiling = 12,000 nominal x 1.67 measured overrun "
                    "factor (spec §27.6, §23.10.10(g) method)",
        "fmax_hard": False,
        "premap_mul_log": "fp_acclattice_premap_mul.log",
    },
    {
        # GATE V20-3 (spec §27.6 "④ GATE V20-3 기준 선공표" block,
        # 2026-08-17) — v2.0 TRAIN full-cluster datapath. As with V20-2 the
        # xcu55c half is the gate's ONLY merge-blocker binding; the ECP5
        # half is a feasibility MEASUREMENT and can never constitute gate
        # FAIL. Every number below is the pre-announced block transcribed
        # VERBATIM (announced BEFORE any integrated RTL was measured —
        # "기준을 움직여서 통과하는 경로는 없다"):
        #   (a) LUT sites hard ceiling 35,377 = measured anchors 33,874
        #       (lattice 19,298 + bank 8,368 + lane 776 x 8) + unmeasured
        #       glue worst 900 x 1.67 = 1,503 (§23.10.10(g) factor);
        #   (b) DSP48 EXACTLY 8 — 1 per lane x 8 lanes, lattice 0 / bank 0
        #       measured; any deviation = no merge + attribution first
        #       (§26.6 MULT-deviation investigation method);
        #   (c) premap $mul EXACTLY 8 (delta +8) — §26.6 pin form;
        #   (d) BRAM 0;  (e) DRC errors 0 (warnings listed, never "clean").
        # Fmax/WNS at the 10 ns harness clock are RECORDED only:
        # congestion-drift below the component minimum (lattice 143.10 MHz
        # routed) is a realized failure mode on this project (§26.6 V9-4)
        # and is recorded + attributed, not FAILED.
        # NOTE the integrated top adopts the lane's wide-product FRONT-END
        # tap (FP_TrainLaneTap — no per-lane FP_AddWide back-end), while
        # the LUT anchor uses the measured WHOLE lane (776): the ceiling is
        # an upper bound and the measurement is expected to land BELOW the
        # anchor sum — that fact is part of the gate record (§27.6 ④
        # "lane 형상 주기" clause).
        "tag": "fp_traincluster",
        "label": "GATE V20-3/US",
        "desc": "v2.0 TRAIN full-cluster datapath (spec §27.6 ④ — FMA "
                "lane tap x8 + lattice N=8 + bank + beat-dispatch skeleton "
                "+ FILL/DRAIN/ZERO cmd path) — xcu55c half = the ONLY "
                "merge-blocker binding of GATE V20-3",
        "max_dsp48": 8,
        "dsp_exact": True,
        "dsp_note": "one 11x11 significand multiply per lane tap x 8 "
                    "lanes; lattice 0 / bank 0 measured (§27.6 ④)",
        "max_lut_sites": 35377,
        "lut_note": "hard ceiling = anchors 33,874 (19,298 lattice + "
                    "8,368 bank + 776x8 lane) + glue 900 x 1.67 "
                    "(spec §27.6 ④, §23.10.10(g) method)",
        "fmax_hard": False,
        "fmax_note": "MEASUREMENT — §27.6 ④ record axis; integration Fmax "
                     "below the component minimum is recorded + "
                     "attributed (§26.6 V9-4 congestion precedent), "
                     "never a FAIL",
        "premap_mul_log": "fp_traincluster_premap_mul.log",
        "premap_mul_expect": 8,
    },
]


def parse_premap_mul(fname):
    """Count premap $mul operator cells in an archived yosys stat log
    (§26.6 pin form: read_verilog + hierarchy + proc + opt_clean, stat).
    Missing log is a hard error — the premap evidence is part of the gate,
    not an optional nicety.

    Format notes (measured against this repo's logs, not assumed):
      * yosys 0.64 (/usr/bin/yosys) prints stat rows COUNT-first
        ("        8   $mul"); older releases printed NAME-first
        ("     $mul     8"). Both are matched.
      * a multi-module design (fp_traincluster) prints per-module "Local
        Count" sections followed by a "=== design hierarchy ===" section
        whose counts are accumulated PER INSTANCE — the honest total
        (8 tap instances x 1 $mul = 8, not the 1 of the FP_TrainLaneTap
        module definition, and never the double-counted 1+8=9 of a
        whole-file sum). When that section exists ONLY it is counted;
        single-module logs (fp_acclattice) have no such section and are
        summed whole."""
    p = RPT_DIR / fname
    if not p.exists():
        sys.exit(f"{p}: missing — regenerate with\n"
                 "  yosys -p 'read_verilog -I include <sources...>; "
                 "hierarchy -top <core-top>; proc; opt_clean; stat' "
                 f"> {p}")
    text = p.read_text()
    if "Printing statistics" not in text:
        sys.exit(f"{p}: not a yosys stat log (no statistics section)")
    hier = text.find("=== design hierarchy ===")
    if hier >= 0:
        text = text[hier:]
    return (sum(int(m.group(1)) for m in                 # NAME-first form
                re.finditer(r"^\s+\$mul\s+(\d+)\s*$", text, re.M))
            + sum(int(m.group(1)) for m in               # COUNT-first form
                  re.finditer(r"^\s+(\d+)\s+\$mul\s*$", text, re.M)))


def parse_summary(tag):
    p = RPT_DIR / f"{tag}_impl_summary.json"
    if not p.exists():
        sys.exit(f"{p}: missing — run `make synth-fp-op FP_OP={tag} "
                 f"PART=<device>` first")
    return json.loads(p.read_text())


def parse_util_top(tag):
    """Top row of Vivado's hierarchical utilization table:
       Instance | Module | Total LUTs | Logic LUTs | LUTRAMs | SRLs | FFs |
       RAMB36 | RAMB18 | URAM | DSP Blocks
    Returns the design totals plus the per-submodule rows."""
    p = RPT_DIR / f"{tag}_impl_util.rpt"
    if not p.exists():
        sys.exit(f"{p}: missing")
    rows = []
    for line in p.read_text().splitlines():
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) != 11 or not cells[2].isdigit():
            continue
        rows.append({
            "instance": cells[0], "module": cells[1],
            "total_luts": int(cells[2]), "logic_luts": int(cells[3]),
            "lutrams": int(cells[4]), "srls": int(cells[5]),
            "ffs": int(cells[6]), "ramb36": int(cells[7]),
            "ramb18": int(cells[8]), "uram": int(cells[9]),
            "dsp": int(cells[10]),
        })
    if not rows:
        sys.exit(f"{p}: no utilization rows parsed")
    return rows[0], rows


def parse_drc(tag):
    """DRC summary table -> list of (rule, severity, description, count).
    Missing report is a hard error: the DRC status is part of the archived
    evidence, not an optional nicety."""
    p = RPT_DIR / f"{tag}_impl_drc.rpt"
    if not p.exists():
        sys.exit(f"{p}: missing")
    rows = []
    for line in p.read_text().splitlines():
        m = re.match(r"\|\s*([A-Z]+-\d+)\s*\|\s*(\w+)\s*\|\s*(.+?)\s*\|"
                     r"\s*(\d+)\s*\|", line)
        if m:
            rows.append((m.group(1), m.group(2), m.group(3),
                         int(m.group(4))))
    return rows


# Known Warning-severity DRCs on these OOC runs, annotated so the summary
# states what each one MEANS instead of hiding behind a count:
DRC_NOTES = {
    "DPOP-4": "DSP multiplier not pipelined (MREG=0) — enabling MREG in a "
              "later pipeline rebalance is an unclaimed free Fmax upside",
    "RTSTAT-10": "OOC top-level output nets have no routable loads — "
                 "structural to out-of-context runs",
}


def main():
    tags = sys.argv[1:] or [g["tag"] for g in GATES]
    lines = []
    all_pass = True

    for g in GATES:
        if g["tag"] not in tags:
            continue
        s = parse_summary(g["tag"])
        top, rows = parse_util_top(g["tag"])

        fmax = float(s["fmax_mhz"])
        wns = float(s["wns_ns"])
        whs = float(s["whs_ns"])
        dsp = int(s["dsp48"])
        bram = int(s["bram"])

        drc = parse_drc(g["tag"])
        drc_errors = [d for d in drc
                      if d[1].lower() not in ("warning", "advisory")]
        drc_warnings = [d for d in drc if d[1].lower() == "warning"]

        fmax_hard = g.get("fmax_hard", True)
        lut_limit = g.get("max_lut_sites")
        mul_count = (parse_premap_mul(g["premap_mul_log"])
                     if "premap_mul_log" in g else None)

        # dsp_exact / premap_mul_expect: "정확히 N" binding (GATE V20-3 —
        # deviation in EITHER direction fails; a smaller count means the
        # mapper split or merged a multiply the pin says must exist as-is).
        mul_expect = g.get("premap_mul_expect", 0)
        ok_fmax = (fmax >= FMAX_TARGET) if fmax_hard else True
        ok_dsp = ((dsp == g["max_dsp48"]) if g.get("dsp_exact")
                  else dsp <= g["max_dsp48"])
        ok_lut = (top["total_luts"] <= lut_limit) if lut_limit else True
        ok_mul = (mul_count == mul_expect) if mul_count is not None else True
        ok_bram = bram == 0
        ok_hold = whs >= 0.0
        ok_drc = not drc_errors
        ok = (ok_fmax and ok_dsp and ok_lut and ok_mul and ok_bram
              and ok_hold and ok_drc)
        all_pass &= ok

        if fmax_hard:
            fmax_line = (f"    Fmax       = {fmax:8.2f} MHz  "
                         f"(WNS {wns:+.3f} ns; HARD target >= "
                         f"{FMAX_TARGET} MHz — spec risk 2)"
                         f"   -> {'PASS' if ok_fmax else 'FAIL'}")
        else:
            fmax_note = g.get("fmax_note",
                              "MEASUREMENT — §27.6 resolve-in-1-cycle "
                              "context")
            fmax_line = (f"    Fmax       = {fmax:8.2f} MHz  "
                         f"(WNS {wns:+.3f} ns @ {s['period_ns']} ns; "
                         f"{fmax_note}; "
                         f">= {FMAX_TARGET} MHz: "
                         f"{'yes' if fmax >= FMAX_TARGET else 'NO'}; "
                         f"binding verdict rides on LUT/DSP/premap-$mul "
                         f"only)   -> RECORDED")

        sub = [r for r in rows[1:] if r["module"] not in ("(top)",)]
        lines += [
            f"{g['label']} — {g['tag']}: {g['desc']}",
            f"    device     = {s['part']}  (Vivado out-of-context, "
            f"synth + opt + place + phys_opt + route)",
            f"    constraint = {s['period_ns']} ns "
            f"({1000.0 / float(s['period_ns']):.2f} MHz)",
            "",
            fmax_line,
            *([f"    LUT sites  = {top['total_luts']:5d}      "
               f"(HARD ceiling {lut_limit} — {g['lut_note']})"
               f"   -> {'PASS' if ok_lut else 'FAIL'}"]
              if lut_limit else []),
            f"    DSP48      = {dsp:5d}      "
            f"({'EXACTLY' if g.get('dsp_exact') else 'limit'} "
            f"{g['max_dsp48']} — {g['dsp_note']})"
            f"   -> {'PASS' if ok_dsp else 'FAIL'}",
            *([f"    premap $mul= {mul_count:5d}      "
               f"({'EXACTLY' if 'premap_mul_expect' in g else 'limit'} "
               f"{mul_expect} — §26.6 pin form; "
               f"evidence: {g['premap_mul_log']})"
               f"   -> {'PASS' if ok_mul else 'FAIL'}"]
              if mul_count is not None else []),
            f"    BRAM       = {bram:5d}      (limit 0)"
            f"   -> {'PASS' if ok_bram else 'FAIL'}",
            f"    WHS        = {whs:+8.3f} ns (hold, limit >= 0)"
            f"   -> {'PASS' if ok_hold else 'FAIL'}",
            f"    DRC        = {len(drc_errors)} errors, "
            f"{len(drc_warnings)} warnings (limit: 0 errors; warnings are "
            f"listed, NOT 'clean')"
            f"   -> {'PASS' if ok_drc else 'FAIL'}",
            *[f"                 {rule} ({sev} x{cnt}): {desc}"
              + (f" — {DRC_NOTES[rule]}" if rule in DRC_NOTES else "")
              for rule, sev, desc, cnt in drc],
            "",
            f"    LUT sites  = {top['total_luts']:5d}      "
            f"({'see HARD line above; ' if lut_limit else 'informational; '}"
            f"{top['logic_luts']} logic + {top['srls']} SRL; raw LUT cells "
            f"{s['lut_cells']} before LUT-combining)",
            f"    FF         = {top['ffs']:5d}      (informational; incl. "
            "the gate-top wrapper I/O flops)",
            f"    CARRY8     = {s['carry']:5d}      (informational)",
        ]
        for r in sub:
            lines.append(
                f"      {r['instance']:<14s} {r['module']:<16s} "
                f"LUT {r['total_luts']:5d}  FF {r['ffs']:5d}  "
                f"DSP {r['dsp']:3d}")
        lines += [f"    {g['label']} RESULT: {'PASS' if ok else 'FAIL'}", ""]

    summary = "\n".join(lines)
    print(summary)
    (RPT_DIR / "gate_summary.txt").write_text(summary + "\n")
    if not all_pass:
        sys.exit("fp_op_gate_check: GATE FAILURE — see "
                 "synth/reports/fp_ops/gate_summary.txt")
    print("fp_op_gate_check: all UltraScale+ per-operator gates PASS")


if __name__ == "__main__":
    main()
