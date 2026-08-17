#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""gate_check.py — evaluate the fp-ops synth gates (spec §23.10.7 Gates
1-2 + the v1.8.0d §23.10.10(g) GATE C3 criteria on the fp_stepseq unit)
from the measured yosys stat + nextpnr report files produced by
synth/lattice/scripts/synth_fp_ops.sh. Writes gate_summary.txt into the
report dir and exits nonzero if any gate criterion fails.

Pass criteria (merge blockers):
  GATE 1 fp_mul36   : MULT18X18D <= 4 (hard fail on decomposition to more),
                      LUT4 <= 300, Fmax >= 40 MHz
  GATE 2 fp_addwide : LUT4 <= 900, MULT18X18D == 0, Fmax >= 40 MHz
  GATE C3 fp_stepseq: whole unit (step sequencer + FP_Mul36 + FP_AddWide +
                      seed/coeff ROMs + the v1.8.0d OPS_CVT/OPS_ACCEW
                      extension + the v1.8.0e OPS_DEQ fused DEQUANT
                      program) — LUT4 <= 4909 = the 0e1 unit line derived
                      mechanically from the published spec §25.5.1
                      itemization: the v1.8.0d C3 archived measurement
                      4,409 (the committed gate_summary baseline; the
                      historical 0d line was 3,345 + 1.2k escalation =
                      4,545) + the §25.5.1 "OPS_DEQ case rows + bf16
                      round-once pack" nominal CEILING of +500 (the
                      itemization row's 250-500 band — its lane-counter /
                      32:1-lane-extract share is PE_Core-side and lands
                      with the 0e1 integration commit's gates, not here).
                      The measured DELTA against 4,409 is recorded vs the
                      +250-500 band, and a delta above +500 executes
                      §25.5.1 cut-ladder rung 3 (fused OPS_DEQ ->
                      two-pass CVT+FS_MUL reuse, pre-priced, MSE-neutral)
                      instead of a gate amendment. MULT18X18D == 4
                      EXACTLY (0 new multipliers — the §25.5.1 MULT pin:
                      the unit instantiates ONE FP_Mul36 and the fused
                      OPS_DEQ rides it with zero new passes; hard-fail on
                      any 0e-cone multiplier attribution), TRELLIS_FF <=
                      900 net of the 147 gate-top wrapper I/O flops (113
                      input + 34 output bits, incl. the v1.8.0d dtype_i
                      port — see FP_StepSeq_gate_top.v), EBR == 0
                      (distributed ROM; spec allows a DOCUMENTED 1-EBR
                      fallback, which this checker deliberately does NOT
                      auto-pass), Fmax >= 40 MHz (seed sweep 1-5 allowed,
                      archive at the first passing seed — §23.10.7 Gate-3
                      precedent: seed noise, not structure; the 0e re-run
                      confirms it, the failing-seed paths sit entirely
                      inside the untouched FP_AddWide stage).
  GATE F1 fp_fmalane_bf16
                    : the v2.0 TRAIN unified bf16/f16 fused-FMA lane
                      (spec §23.1; FP_FmaLaneBf16.v) — LUT4 <= 1300
                      (= the 898 LUT4 Gate-2 FP_AddWide archive (post format-closure,
                      2026-08-15), which the
                      lane instantiates VERBATIM, + a 406 nominal ceiling
                      for the narrow front end), MULT18X18D <= 1 (an 11x11
                      needs AT MOST one; 0 is a PASS and means yosys
                      LUT-mapped it — that measurement is what re-derives
                      the per-fabric FP_LANES ceiling, so it is recorded
                      whichever way it lands), TRELLIS_FF <= 520 net of
                      the 97 gate-top wrapper I/O flops (65 input + 32
                      output bits), EBR == 0, Fmax >= 40 MHz with the same
                      1-5 seed sweep. Criteria pre-declared BEFORE the
                      first run per the §23.8 merge-blocker lesson.
"""

import json
import re
import sys
from pathlib import Path

FREQ_TARGET = 40.0

GATES = [
    # name: max_lut4, mult (max unless exact), ff criterion (None = info),
    #       wrapper_ff subtracted from the FF measurement before the check,
    #       lut4_baseline: prior-gate archive the LUT4 delta is recorded
    #       against (None = no delta line)
    {"name": "fp_mul36",   "label": "GATE 1",
     "max_lut4": 300,  "mult": 4, "mult_exact": False,
     "max_ff": None, "wrapper_ff": 0,   "max_ebr": 0, "lut4_baseline": None},
    {"name": "fp_addwide", "label": "GATE 2",
     "max_lut4": 900,  "mult": 0, "mult_exact": False,
     "max_ff": None, "wrapper_ff": 0,   "max_ebr": 0, "lut4_baseline": None},
    {"name": "fp_stepseq", "label": "GATE C3",
     "max_lut4": 4909, "mult": 4, "mult_exact": True,
     "max_ff": 900,  "wrapper_ff": 147, "max_ebr": 0, "lut4_baseline": 4409,
     "baseline_label": "C3 archive",
     "delta_note": "estimate +250-500, the spec 25.5.1 OPS_DEQ itemization "
                   "band; hard escalation to cut-ladder rung 3 above +500"},
    {"name": "fp_fmalane_bf16", "label": "GATE F1",
     "max_lut4": 1300, "mult": 1, "mult_exact": False,
     "max_ff": 520,  "wrapper_ff": 97,  "max_ebr": 0, "lut4_baseline": 898,
     "baseline_label": "Gate-2 FP_AddWide archive",
     "delta_note": "the lane instantiates FP_AddWide VERBATIM, so the "
                   "delta against its 898 LUT4 Gate-2 archive (post format-"
                   "closure) IS the cost "
                   "of the narrow front end (unpack/classify, f16 "
                   "subnormal normalizer, static align mux, IEEE special "
                   "injector) NET of the PACK_WIDE cone that constant-"
                   "folds away here; nominal ceiling +406"},
]

# every ECP5 block-RAM cell type yosys memory_bram can emit
EBR_CELLS = ("DP16KD", "PDPW16KD", "DP16KD_COMB")

# GATE V20-2 ECP5 half (spec §27.6): feasibility MEASUREMENTS, not gates.
# User directive 2026-08-15 (spec-normative): the ECP5 half constitutes NO
# gate FAIL whatever it measures — including "does not fit" / "PnR did not
# complete". These rows therefore (i) never touch the exit status, (ii)
# tolerate missing reports (a not-yet-run or died-in-PnR measurement is
# reported as such, not treated as an error), (iii) record the §27.6
# classification data: completion, Fmax vs the 40 MHz reference point
# (reference only — NOT a target here), MULT18X18D == 0 expectation and
# the premap $mul count from <name>_premap.rpt.
MEASUREMENTS = [
    {"name": "fp_acclattice", "label": "MEAS V20-2/ECP5 full-parallel",
     "desc": "FROZEN 903351c archive — FP_AccLattice 33-addend "
             "full-parallel unit measured as-is on the 85F; the v2.0 "
             "beat-serial rewrite (spec 27.2.1 amendment 2026-08-16) "
             "retired this shape, re-measurements land under "
             "fp_acclattice_n8 / fp_acclattice_n2",
     "wrapper_ff": 2801},   # 2112 in + 689 out gate-top I/O flops
    {"name": "fp_acclattice_n8", "label": "MEAS V20-2/ECP5 beat-serial N=8",
     "desc": "v2.0 SHIPPING shape (spec 27.2.1 amendment 2026-08-16): "
             "PRODUCTS_PER_BEAT=8 — 4 beats, beat-0 merged carry-in, "
             "parallel 1-cycle 576-bit resolve, II=4",
     "wrapper_ff": 1267},   # (1+512+64) in + 690 out gate-top I/O flops
    {"name": "fp_acclattice_n2", "label": "MEAS V20-2/ECP5 beat-serial N=2",
     "desc": "parameterization-consistency point vs the Beat2 archive "
             "(9,374 LUT4 / 19.55 MHz): PRODUCTS_PER_BEAT=2 — 16 beats, "
             "beat-0 merged carry-in, PARALLEL resolve (Beat2 differs: "
             "separate carry beat + 9-cycle SERIAL resolve)",
     "wrapper_ff": 883},    # (1+128+64) in + 690 out gate-top I/O flops
    {"name": "fp_acclattice_beat2", "label": "MEAS V20-2/ECP5 beat-serial",
     "desc": "spec 27.6 ECP5 target shape: 2 products/beat x 16 beats "
             "(+1 carry-in beat) + 9-cycle serial resolve",
     "wrapper_ff": 819},    # 129 in + 690 out gate-top I/O flops
    # GATE V20-3 ECP5 half (spec §27.6 "④ GATE V20-3 기준 선공표", dated
    # 2026-08-17): the v2.0 TRAIN full-cluster datapath — lane wide-product
    # tap x8 + FP_AccLattice N=8 + FP_AccBank + beat dispatch skeleton +
    # FILL/DRAIN/ZERO cmd path. MEASUREMENT only — the pre-announcement
    # records "PnR did not complete" as a realistic, pre-declared branch.
    # Discriminating pin: premap $mul == 8 (exactly 1 per lane tap x 8;
    # lattice 0 / bank 0 measured); MULT18X18D is a record axis (yosys
    # share discretion allowed — the §26.6 MULT-variance precedent).
    {"name": "fp_traincluster", "label": "MEAS V20-3/ECP5 full-cluster",
     "desc": "v2.0 TRAIN full-cluster datapath (spec 27.6 ④): lane tap x8 "
             "+ lattice N=8 + bank + dispatch skeleton + FILL/DRAIN/ZERO; "
             "xcu55c half carries the merge-blocker binding, this half is "
             "measurement-only and 'did not complete' is a pre-declared "
             "outcome",
     "wrapper_ff": 432,     # 140 in + 292 out gate-top I/O flops
     "premap_pin": 8,       # the §27.6 판별 pin — lane tap x8
     "mult_axis": "record axis — yosys share discretion allowed (§26.6)"},
    # GATE S1 ECP5 half (spec §28.7): the system-integration top
    # (Top_Core = ISA_Decoder + HIU). Same MEASUREMENT regime — the xcu55c
    # half carries the entire merge-blocker binding. TWO outcomes are
    # PRE-DECLARED in §28.7 so neither can be spun afterwards: (a) the HIU
    # TRNG ring oscillators are an intended combinational feedback that
    # Vivado accepts via ALLOW_COMBINATORIAL_LOOPS and the yosys/nextpnr
    # flow has no equivalent constraint for, so a loop complaint or
    # rejection is an EXPECTED outcome of this half; (b) the v1.9b full
    # Cluster was already routing-dominated on the 85F at 39.6% COMB
    # (11.34 MHz), so a low Fmax is the fabric's answer, not a regression.
    # The load-bearing datum is the FRONT of the flow: does the same RTL
    # elaborate and map under a NON-Vivado frontend? That is exactly what
    # defects D1 (Vivado rejects) and D3 (Vivado tolerates) put on the
    # table, so the archived premap stat is a valid measurement even if
    # PnR dies. Discriminating pin: premap $mul == 429, the SAME number the
    # xcu55c half pins — cross-frontend agreement on the multiply census.
    {"name": "sys_top_core", "label": "MEAS S1/ECP5 system top",
     "desc": "system-integration top (spec §28): Top_Core = ISA_Decoder "
             "(EHDecode + PE_Core + FP_StepSeq) + HIU — the top that had "
             "never been synthesized by anything in this repo; xcu55c half "
             "carries the merge-blocker binding, this half is "
             "measurement-only and 'did not complete' is a pre-declared "
             "outcome",
     "wrapper_ff": 1601,    # 1246 in + 355 out gate-top I/O flops
     "premap_pin": 429,
     "mult_axis": "record axis — yosys share discretion allowed (§26.6); "
                  "the xcu55c half measured 39 DSP48E2"},
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

    for g in GATES:
        name = g["name"]
        label = g["label"]
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
        delta_line = []
        if g["lut4_baseline"] is not None:
            delta = lut4 - g["lut4_baseline"]
            delta_line = [
                f"    LUT4 delta = {delta:+5d}   vs the {g['lut4_baseline']} "
                f"{g.get('baseline_label', 'archive')} ({g['delta_note']})"]
        lines += [
            f"{label} — {name} (LFE5UM-85F CABGA381 -6, out-of-context, "
            f"yosys synth_ecp5 + nextpnr-ecp5, wrapper-top incl. I/O regs):",
            f"    LUT4       = {lut4:5d}   (limit {g['max_lut4']})"
            f"   -> {'PASS' if ok_lut else 'FAIL'}",
            *delta_line,
            f"    MULT18X18D = {mult:5d}   ({mult_crit})"
            f"   -> {'PASS' if ok_mult else 'FAIL'}",
            ff_line,
            f"    EBR        = {ebr:5d}   (limit {g['max_ebr']}, "
            f"cells {'/'.join(EBR_CELLS)})"
            f"   -> {'PASS' if ok_ebr else 'FAIL'}",
            f"    CCU2C      = {ccu2:5d}   (informational, carry cells)",
            f"    Fmax       = {fmax:8.2f} MHz (target >= {FREQ_TARGET})"
            f"   -> {'PASS' if ok_fmax else 'FAIL'}",
            f"    {label} RESULT: {'PASS' if ok else 'FAIL'}",
            "",
        ]

    # ---- GATE V20-2 ECP5-half measurement rows (never gate the exit) ----
    for m in MEASUREMENTS:
        name = m["name"]
        synth_rpt = rpt_dir / f"{name}_synth.rpt"
        if not synth_rpt.exists():
            continue        # measurement not run — nothing to report
        cells = parse_stat(synth_rpt)
        lut4 = cells.get("LUT4", 0)
        mult = cells.get("MULT18X18D", 0)
        ff = cells.get("TRELLIS_FF", 0)
        ccu2 = cells.get("CCU2C", 0)
        ebr = sum(cells.get(c, 0) for c in EBR_CELLS)
        premap_rpt = rpt_dir / f"{name}_premap.rpt"
        premap_mul = (parse_stat(premap_rpt).get("$mul", 0)
                      if premap_rpt.exists() else None)
        pnr_rpt = rpt_dir / f"{name}_pnr.rpt"
        fmax = parse_fmax(pnr_rpt) if pnr_rpt.exists() else None
        premap_pin = m.get("premap_pin", 0)
        pin_txt = (f"pin expects {premap_pin}"
                   + (" — matches the xcu55c half's premap census"
                      if premap_pin > 8 else " — exactly 1 per lane tap")
                   + ("  MISMATCH" if premap_mul != premap_pin else "")
                   if premap_pin else "pin expects 0 — adder/compressor only")
        mul_line = ("    premap $mul= " + (
            f"{premap_mul:5d}   ({pin_txt})"
            if premap_mul is not None else
            "  n/a   (no premap report archived)"))
        mult_txt = m.get("mult_axis", "pin expects 0")
        if fmax is None:
            pnr_lines = [
                "    PnR        = DID NOT COMPLETE — that outcome is the "
                "measurement; see the archived _pnr.log for the stage/reason",
            ]
        else:
            pnr_lines = [
                f"    Fmax       = {fmax:8.2f} MHz (40 MHz is a reference "
                f"point only — NOT a target here, spec 27.6)",
                "    PnR        = completed",
            ]
        lines += [
            f"{m['label']} — {name} (LFE5UM-85F CABGA381 -6, out-of-context,"
            f" yosys synth_ecp5 + nextpnr-ecp5, wrapper-top incl. I/O regs):",
            f"    [{m['desc']}]",
            f"    LUT4       = {lut4:5d}   (85F budget 83,640 — utilization "
            f"{lut4 / 83640 * 100:.1f}%; no ceiling declared, spec 27.6)",
            f"    MULT18X18D = {mult:5d}   ({mult_txt})",
            mul_line,
            f"    TRELLIS_FF = {ff:5d}   raw; unit = {ff - m['wrapper_ff']} "
            f"after -{m['wrapper_ff']} wrapper I/O flops (informational)",
            f"    EBR        = {ebr:5d}   (informational, "
            f"cells {'/'.join(EBR_CELLS)})",
            f"    CCU2C      = {ccu2:5d}   (informational, carry cells)",
            *pnr_lines,
            f"    {m['label']} RESULT: MEASUREMENT (recorded — the ECP5 half"
            f" constitutes no gate verdict, spec 27.6)",
            "",
        ]

    summary = "\n".join(lines)
    print(summary)
    (rpt_dir / "gate_summary.txt").write_text(summary + "\n")
    if not all_pass:
        sys.exit("synth_fp_ops: GATE FAILURE — see gate_summary.txt")
    print("synth_fp_ops: " + " + ".join(g["label"] for g in GATES) + " PASS")


if __name__ == "__main__":
    main()
