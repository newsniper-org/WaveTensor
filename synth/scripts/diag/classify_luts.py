#!/usr/bin/env python3
# FROZEN — 수정 금지 (이름 규칙은 고정 리비전 전용). 진단 전용, GATE 미등재.
#
# 무엇인가
# --------
# /tmp/wt_diag/lutcells.txt (REF_NAME NAME per line) 를 FP_AccLattice
# 스테이지별로 분류한다. 이름 규칙: Vivado 는 comb LUT 를 주로
# "드라이브하는 net/reg 이름 + _i_N" 으로 명명한다.
#
# 2026-08-15 GATE V20-2 FAIL 원인 진단 (R3) 의 재현 도구이며, 그 산출물은
# spec `.claude-memos/wt64v1_spec.md` §27.6 이 인용하는 규범적 증적
# (`synth/reports/fp_ops/fp_acclattice_diag_flat_attribution.txt`).
#
# 왜 FROZEN 인가
# --------------
# 아래 정규식(g_addend / g_l[1-8] / row_a_p1 / g_place …)은 **진단 당시의**
# FP_AccLattice.v (commit 903351c) 에만 대응한다. 2026-08-16 커밋 cddb4d1
# 이 모듈을 beat-serial 로 재작성하면서 그 라벨은 현행 RTL 에 0건이 됐다.
# 짝인 diag_names.tcl 은 이제 frozen/ 고정본을 읽는다 —
# 자세한 근거와 기준 수치는 frozen/PROVENANCE.txt 참조.
#
# 규칙을 현행 RTL 에 맞춰 고치지 마라. 그러면 인용된 과거 측정을 재현할
# 수 없게 된다. 현행 RTL 분류는 별도 하네스로 만들어라.
#
# loud-fault-never-silent
# -----------------------
# 예전에는 엉뚱한 netlist 를 먹여도 exit 0 으로 "전부 OTHER" 인 그럴듯한
# 표를 찍었다 — 조용히 틀린 답. 이제 OTHER 비율이 OTHER_FAIL_PCT 를
# 넘거나 입력이 비면 stderr 로 사유를 찍고 **exit 1** 한다.
import re
import sys
import collections

path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/wt_diag/lutcells.txt"

# 기준 재현 run 의 OTHER 는 0.00% 였다 (frozen/PROVENANCE.txt). 이름 규칙이
# 맞지 않는 netlist 를 먹이면 OTHER 가 압도한다. 여유를 두되, "조용히 틀린
# 답"이 통과하지 못할 만큼 낮게 잡는다.
OTHER_FAIL_PCT = 5.0

# (category, regex on the cell name AFTER the "u_core/" prefix)
rules = [
    # S1 placement: generate-scope 이름 (barrel/demux/decode/fault)
    ("S1_place", re.compile(r"^g_addend\[")),
    # S1 ncnt popcount
    ("S1_ncnt", re.compile(r"^(g_pc3\[|pc[ABC]|ncnt)")),
    # S1 tree: compressor levels + S1 pipeline regs
    ("S1_tree", re.compile(r"^(g_l[1-8]|row_a_p1|row_b_p1)")),
    ("S1_fault", re.compile(r"^fault_p1")),
    # S2 resolve
    ("S2_resolve", re.compile(r"^(lat_p2|fault_p2|phys_sum)")),
    # S3 extract
    ("S3_extract", re.compile(r"^(win_p3|lz_p3|cs_p3|stlow_p3|sign_p3|magz_p3|fault_p3|lat_p3|mag|chunk|ch_any|cs\b|win\b|pre|st_low|v[0-5]|z[0-5])")),
    # S4 encode + 출력 레지스터
    ("S4_encode", re.compile(r"^(resolved_q|wide_q|bank_q|fp32_q|fault_q|n[0-6]|sig_rto|top48|sticky|m2[45]|e_(w|biased|fin)|p_pos|biased|ovf|udf|rne_up)")),
]

cnt = collections.Counter()
unk = collections.Counter()
total = 0
try:
    fh = open(path)
except OSError as exc:
    print(f"classify_luts: FAIL — 입력을 열 수 없다: {exc}", file=sys.stderr)
    print("  diag_names.tcl 을 먼저 돌려 /tmp/wt_diag/lutcells.txt 를 만들어라.",
          file=sys.stderr)
    sys.exit(1)

with fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        ref, name = line.split(None, 1)
        total += 1
        # strip hierarchy prefix (u_core/ or top-level)
        short = name.split("/", 1)[1] if name.startswith("u_core/") else name
        for cat, rx in rules:
            if rx.match(short):
                cnt[cat] += 1
                break
        else:
            cnt["OTHER"] += 1
            # first two tokens of the name for triage
            key = re.split(r"[\[_]", short)[0]
            unk[key] += 1

if total == 0:
    print(f"classify_luts: FAIL — {path} 에 LUT cell 이 0건이다 "
          "(빈 파일이거나 synth 가 실패했다).", file=sys.stderr)
    sys.exit(1)

print(f"total LUT cells: {total}")
for cat in ["S1_place", "S1_ncnt", "S1_tree", "S1_fault", "S2_resolve",
            "S3_extract", "S4_encode", "OTHER"]:
    c = cnt.get(cat, 0)
    print(f"  {cat:12s} {c:7d}  ({100.0*c/total:5.2f}%)")
if unk:
    print("top OTHER prefixes:")
    for k, v in unk.most_common(15):
        print(f"    {k:20s} {v}")

other_pct = 100.0 * cnt.get("OTHER", 0) / total
if other_pct > OTHER_FAIL_PCT:
    print(f"\nclassify_luts: FAIL — OTHER {other_pct:.2f}% > "
          f"{OTHER_FAIL_PCT:.2f}% 임계", file=sys.stderr)
    print("  이름 규칙이 이 netlist 에 대응하지 않는다. 규칙을 고치지 말고,",
          file=sys.stderr)
    print("  diag_names.tcl 이 frozen/ 고정본(commit 903351c)을 읽고 있는지",
          file=sys.stderr)
    print("  확인하라 — frozen/PROVENANCE.txt 참조.", file=sys.stderr)
    sys.exit(1)
