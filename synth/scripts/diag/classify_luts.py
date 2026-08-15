#!/usr/bin/env python3
# DIAGNOSTIC ONLY — /tmp/wt_diag/lutcells.txt (REF_NAME NAME per line) 를
# FP_AccLattice 스테이지별로 분류한다. 이름 규칙: Vivado 는 comb LUT 를
# 주로 "드라이브하는 net/reg 이름 + _i_N" 으로 명명한다.
import re, sys, collections

path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/wt_diag/lutcells.txt"

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
with open(path) as fh:
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

print(f"total LUT cells: {total}")
for cat in ["S1_place", "S1_ncnt", "S1_tree", "S1_fault", "S2_resolve",
            "S3_extract", "S4_encode", "OTHER"]:
    c = cnt.get(cat, 0)
    print(f"  {cat:12s} {c:7d}  ({100.0*c/total:5.2f}%)")
if unk:
    print("top OTHER prefixes:")
    for k, v in unk.most_common(15):
        print(f"    {k:20s} {v}")
