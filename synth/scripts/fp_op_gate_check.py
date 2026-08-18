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

GATE S1-US IS A DIFFERENT KIND OF GATE (spec §28)
-------------------------------------------------
Every gate above measures an OPERATOR. GATE S1-US measures a SYSTEM TOP,
and it exists for a reason none of the operator gates cover: `HIU.v` and
`Top_Core.v` had never been synthesized by anything in this repo while
passing cocotb continuously, and the first synthesis attempt was REFUSED
(`ERROR [Synth 8-685]`, a Verilog-2001 violation — defect D1). So the
proposition under test is not "how fast" or "how big" but
**"synthesizable at all, and still synthesizable tomorrow"**. Two axes are
therefore new here:

  * CRITICAL WARNING census, with an EXPLICIT whitelist. A synthesizability
    regression shows up as a Critical Warning long before it shows up as
    an error. The HIU TRNG ring oscillators legitimately produce
    `[Synth 8-295] found timing loop` x8 (8 ring oscillators = 8 loops),
    and that count — the count, not the message class — is whitelisted.
    `set_msg_config` global demotion is FORBIDDEN by spec §28: demoting
    the class would hide a real combinational loop elsewhere.
  * BRAM as an EXPECTED VALUE rather than 0. An operator core inferring
    block RAM is a defect; a system top containing PE_Core's buffers
    legitimately infers 2 RAMB18, and pinning the exact number is what
    detects a silent memory-inference change.
"""

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_premap_mul import premap_sources, verify_provenance  # noqa: E402

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
    {
        # GATE S1-US (spec §28) — SYSTEM-INTEGRATION SYNTHESIZABILITY gate.
        # A different kind of gate from every row above: see the module
        # docstring. It was created because HIU.v and Top_Core.v had never
        # been synthesized while passing cocotb continuously, and the first
        # attempt was REFUSED by Vivado (defect D1).
        #
        # ANCHOR-GENERATING COMMIT — READ THIS BEFORE TRUSTING A PASS.
        # No prior xcu55c measurement of this top existed, so there was
        # nothing to price the ceilings against. Per the GATE V20-4
        # procedure (spec §27.7a.5, "측정 anchor 부재 → gate 절차가 anchor
        # 를 먼저 생성한다") the numbers below are derived FROM the first
        # measurement, which means THIS commit's run cannot fail the area
        # axis by construction: measurement == anchor <= anchor x 1.67.
        # The binding force starts with the NEXT commit that touches this
        # tree — from then on the ceiling is a real merge blocker and the
        # exact-value axes (DSP/BRAM/premap $mul) fail on any drift.
        # Everything here is transcribed from the archived reports without
        # rounding beyond the one floor() noted on the LUT line.
        "tag": "sys_top_core",
        "label": "GATE S1-US",
        "desc": "system-integration synthesizability gate (spec §28) — "
                "Top_Core = ISA_Decoder + HIU, the top that had never been "
                "synthesized; xcu55c half = the ONLY merge-blocker binding "
                "of GATE S1 (the ECP5 half is a MEASUREMENT)",
        "max_lut_sites": 24799,
        "lut_note": "hard ceiling = anchor 14,850 (first repo-harness "
                    "xcu55c routed measurement, this commit) x 1.67 "
                    "(§23.10.10(g) overrun factor) = 24,799.5, floored to "
                    "24,799; binding from the NEXT commit onward",
        "max_dsp48": 39,
        "dsp_exact": True,
        "dsp_note": "anchor — 35 in PE_Core's einsum/dot path + 4 in "
                    "FP_StepSeq's FP_Mul36; HIU 0. Any drift means the "
                    "mapper's multiply inference moved and gets attributed "
                    "before re-verdict (§26.6 MULT-deviation method)",
        "max_bram": 2,
        "bram_exact": True,
        "bram_note": "anchor — 2 RAMB18 inside FP_StepSeq; a system top "
                     "legitimately infers memory, so the axis pins the "
                     "EXACT count instead of demanding 0 as the operator "
                     "gates do. Drift = a silent memory-inference change",
        "premap_mul_log": "sys_top_core_premap_mul.log",
        # 429 -> 381: re-anchored 2026-08-18 on the user's §12a decision.
        # The retired 48 were the row-address multiplies of the dead 2D
        # partitioned_tlb_* arrays — phantoms that yosys kept as $memrd at
        # premap time while the mapped netlist held ZERO cells for them.
        # D4 deleted the arrays, so the phantoms went with them. Raising an
        # exact axis is normally forbidden; here the axis was over-counting
        # a structure that did not exist in silicon. See spec §29.11.
        "premap_mul_expect": 381,
        "crit_whitelist": {"Synth 8-295": 8},
        "crit_note": "the 8 HIU TRNG ring oscillators are an INTENDED "
                     "combinational feedback (they are the entropy "
                     "source), so exactly 8 timing loops are expected and "
                     "whitelisted BY COUNT; a 9th, or any other critical "
                     "warning id, fails. Global set_msg_config demotion is "
                     "forbidden (spec §28) — it would hide a real loop. "
                     "DRC LUTLP-1 must be 0: that is the "
                     "synth/constraints/hiu_trng_ro.xdc acknowledgement "
                     "working, and it shows up as LUTLP-2 'Combinatorial "
                     "Loop Allowed' x8 in the DRC warning list",
        "fmax_hard": False,
        "fmax_note": "MEASUREMENT — §28 record axis. This top is not on "
                     "the v2.0 datapath critical path and no Fmax contract "
                     "has ever been declared for it; the number exists so "
                     "the next measurement has something to drift against",
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


def parse_run_expect(tag):
    """archived Vivado run log 의 `Command line :` 행에서 `SRCS=` / `TOP=` 를 뽑는다.

    premap 증거가 **Vivado 가 실제로 합성한 것과 같은 설계**를 잰 것인지
    대조하기 위한 것이다. 두 축을 본다:
      * 소스 집합 — 소스가 하나 추가됐는데 premap 증거만 옛 목록으로 남아
        있으면, 남은 항목의 해시는 전부 맞으므로 두 축이 서로 다른 설계를
        재는데도 둘 다 PASS 한다. 해시 대조만으로는 **추가**를 못 잡는다.
      * 코어 top — `hierarchy -top` 이 무엇을 살리고 무엇을 프루닝할지
        결정하므로, top 이 다르면 같은 소스라도 계수의 의미가 달라진다.
        run log 는 gate_top 래퍼 이름을 싣고, 코어 top 은 `_gate_top` 을 뗀
        것이다 (Makefile `PREMAP_CORE_TOP` 과 같은 규칙 — 규칙이 한 벌이어야
        두 벌이 어긋나는 이 결함 자체가 재발하지 않는다).

    반환: (sources, core_top). run log 가 없으면 (None, None) 이고, 그 경우
    provenance 검증은 **해시 대조까지만** 이다.

    ⚠️ 검증 강도가 gate 별로 비대칭이다 — run log 를 아카이브하는 것은
    `make synth-sys-gate` 계열뿐이고, `make synth-fp-op` 로 도는 운영자
    gate (fp_fmalane_bf16 / fp_acclattice / fp_traincluster) 는 아직 로그가
    쌓이기 전이라 해시 대조만 받는다. `synth-fp-op` 도 `-log` 를 넘기도록
    고쳐 뒀으므로 **다음 재합성부터** 자동으로 같은 강도가 된다. 그때까지의
    한정을 "전 축 검증됨" 으로 요약하지 말 것 (spec §22.14b-12).
    """
    p = RPT_DIR / f"{tag}_run.log"
    if not p.exists():
        return None, None
    srcs = top = None
    for line in p.read_text(errors="replace").splitlines()[:64]:
        m = re.search(r"\bSRCS=(\S+)", line)
        if m and srcs is None:
            srcs = premap_sources(m.group(1))
        m = re.search(r"\bTOP=(\S+)", line)
        if m and top is None:
            top = re.sub(r"_gate_top$", "", m.group(1))
        if srcs is not None and top is not None:
            break
    return srcs, top


def parse_msg_census(tag):
    """CRITICAL WARNING / ERROR census from the ARCHIVED VIVADO RUN LOG
    (`synth/reports/fp_ops/<tag>_run.log`, written by `make synth-sys-gate`
    via Vivado's -log).

    WHY THE LOG AND NOT A TCL QUERY: the obvious in-tcl form
    `get_msg_config -count -severity {CRITICAL WARNING}` was tried and
    MEASURED WRONG — on Vivado 2025.2.1 it returned 0 for a run whose log
    held 8 `CRITICAL WARNING: [Synth 8-295]` lines. It reports message
    configuration, not messages issued. A census that silently answers 0
    is a false PASS on the one axis whose whole job is to be loud, so the
    count is taken where it is also citable and greppable.

    Returns None when no run log is archived — the caller turns that into
    UNMEASURED (= FAIL) for any gate that declares the axis, never a pass.

    COMPLETENESS IS PART OF THE CENSUS (added 2026-08-18, spec §22.14b-11).
    A census over a TRUNCATED log is a false PASS, and not a hypothetical
    one: this checker was run against a log that a still-running Vivado had
    written only as far as mid-`synth_design`, and it reported
    `CRIT WARN = 0 -> PASS` for a gate whose complete log holds the 8
    whitelisted ring-oscillator loops. Fewer critical warnings than reality
    is exactly the direction that passes silently — the axis counts UP to a
    ceiling, so a half-written log always looks cleaner than the truth.
    A complete `vivado -mode batch` log ends with `[Common 17-206] Exiting
    Vivado`; without that marker the run either crashed, was killed, or is
    still in flight, and the only honest verdict is UNMEASURED (= FAIL).
    """
    p = RPT_DIR / f"{tag}_run.log"
    if not p.exists():
        return None
    if "[Common 17-206] Exiting Vivado" not in p.read_text(errors="replace"):
        return None            # 미완주 로그 = 미측정 (절대 PASS 아님)
    ids = {}
    n_crit = n_err = 0
    for line in p.read_text(errors="replace").splitlines():
        if line.startswith("CRITICAL WARNING:"):
            n_crit += 1
            m = re.search(r"\[([A-Za-z]+ [\w-]+)\]", line)
            ids[m.group(1) if m else "(unidentified)"] = \
                ids.get(m.group(1) if m else "(unidentified)", 0) + 1
        elif line.startswith("ERROR:"):
            n_err += 1
    return {"critical": n_crit, "error": n_err, "by_id": ids, "log": p.name}


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
        # NOTE the severity group is `[A-Za-z ]+` and NOT `\w+`. The
        # original `\w+` silently DROPPED every row whose severity contains
        # a space — i.e. exactly the "Critical Warning" rows, the ones this
        # axis exists to fail on. Found 2026-08-18 by the GATE S1
        # discriminator self-test (spec §28.6): the D2-withheld run's DRC
        # report carries `LUTLP-1 | Critical Warning | ... | 8` and the
        # checker reported "0 errors" for it. A gate axis that cannot see
        # the severity it gates on is worse than no axis.
        m = re.match(r"\|\s*([A-Z]+-\d+)\s*\|\s*([A-Za-z][A-Za-z ]*?)\s*\|"
                     r"\s*(.+?)\s*\|\s*(\d+)\s*\|", line)
        if m:
            rows.append((m.group(1), m.group(2), m.group(3),
                         int(m.group(4))))
    return rows


# Known Warning-severity DRCs on these OOC runs, annotated so the summary
# states what each one MEANS instead of hiding behind a count:
DRC_NOTES = {
    "DPOP-4": "DSP multiplier not pipelined (MREG=0) — enabling MREG in a "
              "later pipeline rebalance is an unclaimed free Fmax upside",
    "DPOP-3": "DSP output not pipelined (PREG=0) — same class as DPOP-4",
    "DPIP-2": "DSP input not pipelined (AREG/BREG=0) — same class",
    "RTSTAT-10": "OOC top-level output nets have no routable loads — "
                 "structural to out-of-context runs",
    "LUTLP-2": "Combinatorial Loop Allowed — this is the INTENDED HIU TRNG "
               "ring oscillator, acknowledged by "
               "synth/constraints/hiu_trng_ro.xdc (defect D2). Its "
               "presence is the constraint WORKING: without it the same 8 "
               "loops appear as LUTLP-1 Critical Warnings, which this "
               "checker counts as DRC errors and fails on",
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
        census = parse_msg_census(g["tag"])

        drc = parse_drc(g["tag"])
        drc_errors = [d for d in drc
                      if d[1].lower() not in ("warning", "advisory")]
        drc_warnings = [d for d in drc if d[1].lower() == "warning"]

        fmax_hard = g.get("fmax_hard", True)
        lut_limit = g.get("max_lut_sites")
        mul_count = (parse_premap_mul(g["premap_mul_log"])
                     if "premap_mul_log" in g else None)

        # premap 증거의 PROVENANCE (§22.14b-10, 2026-08-18 적대 검수).
        # 이 축은 archived yosys 로그에서 읽히는데, 그 로그를 만드는 단계가
        # 어느 flow 타깃에도 없어서 **소스가 바뀌어도 로그는 그대로** 남았다.
        # 그 상태에서 나오는 PASS 는 측정이 아니라 동결 상수다. 이제 로그
        # 선두의 sha256 목록을 현행 소스와 대조하고, 어긋나면 축을 PASS 로
        # 세지 않는다. 실패는 "숫자가 틀렸다" 가 아니라 **"재지 않았다"** 이며
        # 둘 다 gate FAIL 이다 (loud-fault-never-silent).
        if "premap_mul_log" in g:
            run_srcs, run_top = parse_run_expect(g["tag"])
            ok_prov, prov_detail = verify_provenance(
                RPT_DIR / g["premap_mul_log"], run_srcs, run_top)
        else:
            ok_prov, prov_detail = True, None

        # dsp_exact / premap_mul_expect: "정확히 N" binding (GATE V20-3 —
        # deviation in EITHER direction fails; a smaller count means the
        # mapper split or merged a multiply the pin says must exist as-is).
        mul_expect = g.get("premap_mul_expect", 0)
        ok_fmax = (fmax >= FMAX_TARGET) if fmax_hard else True
        ok_dsp = ((dsp == g["max_dsp48"]) if g.get("dsp_exact")
                  else dsp <= g["max_dsp48"])
        ok_lut = (top["total_luts"] <= lut_limit) if lut_limit else True
        ok_mul = ((mul_count == mul_expect and ok_prov)
                  if mul_count is not None else True)

        # BRAM: operator gates want 0; the GATE S1-US system top wants an
        # EXACT expected count (see the module docstring).
        bram_limit = g.get("max_bram", 0)
        ok_bram = (bram == bram_limit if g.get("bram_exact")
                   else bram <= bram_limit)

        # CRITICAL WARNING census (GATE S1-US axis). Gates that do not
        # declare `crit_whitelist` are not judged on it — the axis was added
        # with §28 and the operator gates' archived runs have no log.
        #
        # The criterion is deliberately TWO-SIDED rather than a bare total:
        #   (i) every whitelisted message id is capped at its own count
        #       (8 ring oscillators => at most 8 `Synth 8-295` timing
        #       loops; a 9th means something else started looping), and
        #  (ii) ANY critical warning outside the whitelist fails.
        # A single total would let a real loop hide behind a retired RO.
        # `set_msg_config` global demotion is forbidden by spec §28 for the
        # same reason.
        # (iii) ERROR lines in the archived log fail outright. This was
        # counted but NOT judged until the 2026-08-18 adversarial audit —
        # a census that displays a number it does not act on is decoration,
        # and an ERROR in a run whose reports still parsed is exactly the
        # silent-failure shape §28.4 exists to catch. There is no whitelist:
        # a passing synthesis run has zero ERROR lines.
        wl = g.get("crit_whitelist")
        crit_over = []
        log_errors = 0
        if wl is None:
            ok_crit = True
        elif census is None:
            ok_crit = False        # no run log archived: never a pass
        else:
            for mid, cnt in sorted(census["by_id"].items()):
                if cnt > wl.get(mid, 0):
                    crit_over.append((mid, cnt, wl.get(mid, 0)))
            log_errors = census["error"]
            ok_crit = (not crit_over) and log_errors == 0
        ok_hold = whs >= 0.0
        ok_drc = not drc_errors
        ok = (ok_fmax and ok_dsp and ok_lut and ok_mul and ok_bram
              and ok_hold and ok_drc and ok_crit)
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
            *([f"                 provenance: {prov_detail}"
               f"   -> {'PASS' if ok_prov else 'FAIL (STALE EVIDENCE — 이 축은 재지 않았다)'}"]
              if prov_detail else []),
            f"    BRAM       = {bram:5d}      "
            f"({'EXACTLY' if g.get('bram_exact') else 'limit'} {bram_limit}"
            f"{'; ' + g['bram_note'] if 'bram_note' in g else ''})"
            f"   -> {'PASS' if ok_bram else 'FAIL'}",
            *([("    CRIT WARN  = " + (
                "  n/a      -> UNMEASURED (FAIL — "
                f"{g['tag']}_run.log 이 없거나 **완주 마커"
                "(`[Common 17-206] Exiting Vivado`)가 없다**: 크래시·강제 "
                "종료·실행 중 셋 중 하나다. 잘린 로그의 census 는 항상 "
                "실제보다 적게 나오므로 조용히 PASS 한다 — parse_msg_census "
                "참조)"
                if census is None else
                f"{census['critical']:5d}      (whitelist "
                + ", ".join(f"{k} x{v}" for k, v in sorted(wl.items()))
                + f" — {g['crit_note']}; evidence: {census['log']})"
                f"   -> {'PASS' if ok_crit else 'FAIL'}"))]
              if wl is not None else []),
            *([f"                 issued: {mid} x{cnt}"
               + ("  <= whitelist" if cnt <= wl.get(mid, 0)
                  else f"  OVER whitelist {wl.get(mid, 0)}")
               for mid, cnt in sorted(census["by_id"].items())]
              if wl is not None and census is not None else []),
            *([f"                 ERROR lines in log: {census['error']}"
               f" (limit 0, BINDING)"
               f"   -> {'PASS' if log_errors == 0 else 'FAIL'}"]
              if wl is not None and census is not None else []),
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
