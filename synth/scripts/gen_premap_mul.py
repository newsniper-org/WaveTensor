#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""gen_premap_mul.py — premap `$mul` 증거 로그를 **flow 안에서** 재생성한다.

왜 이 파일이 존재하는가 (spec §22.14b-10, 2026-08-18 적대 검수)
--------------------------------------------------------------
`fp_op_gate_check.py` 의 **binding 축** 하나(`premap $mul`)는
`synth/reports/fp_ops/<tag>_premap_mul.log` 라는 archived yosys stat 로그에서
읽힌다. 그런데 그 로그를 만드는 단계가 **어느 flow 타깃에도 없었다** —
`make synth-sys-gate` 는 Vivado 만 호출하고, 로그는 사람이 손으로 친 yosys
한 줄의 산출물이었다. 결과: 소스가 바뀌어도 로그는 그대로 남고, **binding
축이 측정이 아니라 동결 상수 위에서 PASS** 했다. 실제로 GATE S1 이 두 번
완주하는 동안 이 파일만 갱신되지 않았고, 내부 라인 참조(`EHDecode.v:671/680`)
가 당시 소스(`:727/736`)와 어긋나 있었다. §12a 가 금지하는 "조용히 통과하는
검사" 의 교과서적 형태다.

수리는 두 겹이다 — **생성을 flow 에 편입**(이 파일)하고, **소비 측에서
provenance 를 강제**(`fp_op_gate_check.py` 의 `verify_provenance`)한다.
어느 한쪽만으로는 부족하다: 생성만 편입하면 손으로 만든 옛 로그가 계속
통과하고, 검증만 넣으면 flow 가 로그를 못 만들어 gate 가 영영 FAIL 한다.

provenance 헤더
---------------
로그 **선두**에 주석 블록으로 박는다 (sidecar 파일이 아니다 — 사이드카는
분실·분리되고, 헤더는 증거와 물리적으로 같은 파일에 있어 `git diff` 에
같이 뜬다). 각 소스의 sha256 을 적으므로, 소스가 한 바이트라도 바뀌면
`fp_op_gate_check.py` 가 **STALE 로 즉시 FAIL** 한다. mtime 이 아니라 내용
해시인 이유: mtime 은 checkout·touch·복사로 아무 의미 없이 바뀌고, 반대로
내용이 바뀌어도 보존될 수 있다.

소스 목록은 **파생**된다 (Makefile `FP_OP_SRCS_<tag>` 에서 `synth/` 밑의
gate_top 래퍼를 뺀 것). 손으로 두 벌 유지하지 않는다 — 두 벌이면 어긋나고,
어긋남이 곧 이 결함이었다.

사용
----
    python3 synth/scripts/gen_premap_mul.py --tag sys_top_core \
        --top Top_Core --sources Top_Core.v,ISA_Decoder.v,...

gate 표(`fp_op_gate_check.GATES`)에 `premap_mul_log` 가 **없는** tag 는
조용히가 아니라 **한 줄 보고하고** skip 한다 (그 축이 없는 gate 다).
"""

import argparse
import datetime
import hashlib
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
RPT_DIR = REPO / "synth" / "reports" / "fp_ops"

HEADER_BEGIN = "# ===== WT premap-$mul evidence provenance (spec §22.14b-10) ====="
HEADER_END = "# ===== end provenance ====="


def sha256_of(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def parse_provenance(text):
    """로그 선두 provenance 헤더를 파싱한다.

    반환: dict(tag, top, yosys, generated, sources=[(rel_path, sha256), ...])
          헤더가 없으면 None (호출자가 STALE/LEGACY 로 판정한다).
    """
    if not text.startswith(HEADER_BEGIN):
        return None
    end = text.find(HEADER_END)
    if end < 0:
        return None
    head = text[:end]
    prov = {"sources": []}
    for line in head.splitlines():
        m = re.match(r"^#\s+(tag|top|yosys|generated):\s+(.*)$", line)
        if m:
            prov[m.group(1)] = m.group(2).strip()
            continue
        m = re.match(r"^#\s+source:\s+(\S+)\s+sha256=([0-9a-f]{64})\s*$", line)
        if m:
            prov["sources"].append((m.group(1), m.group(2)))
    return prov if prov["sources"] else None


def verify_provenance(log_path, expected_sources=None, expected_top=None):
    """증거 로그가 **현행 소스로** 만들어졌는지 검증한다.

    반환: (ok: bool, detail: str). 실패 사유는 넷이다 —
      (a) 헤더 없음    = flow 밖에서 손으로 만든 로그 (legacy). 재생성 필요.
      (b) 해시 불일치  = 소스가 바뀐 뒤 재생성되지 않음 (STALE). 이것이 원래
                         결함이 숨어 있던 자리다.
      (c) 목록 불일치  = Vivado 가 합성한 소스 집합과 premap 증거의 소스
                         집합이 다름 — 한쪽에만 파일이 추가된 상태.
      (d) top 불일치   = 같은 소스를 **다른 top 으로** 정교화한 증거. 계수의
                         의미가 통째로 달라진다 (`hierarchy -top` 이 무엇을
                         살리고 무엇을 프루닝하는지를 결정한다).

    `expected_sources` / `expected_top` 은 **archived Vivado run log** 에서
    온다. run log 가 없는 gate 는 둘 다 None 이 넘어오고, 그 경우 검증은
    해시 대조까지만이다 — 즉 **소스 수정은 잡지만 소스 추가는 못 잡는다**
    (추가분은 헤더에 없으므로 대조 대상이 아니다). 이 한정은 gate 별로
    비대칭이며, `fp_op_gate_check.parse_run_expect` 의 주석이 어느 gate 가
    어느 강도를 받는지 적어 둔다. 한정을 없애는 방법은 하나뿐이다 —
    그 gate 도 run log 를 아카이브하는 것.
    """
    p = Path(log_path)
    if not p.exists():
        return False, f"{p.name}: 없음"
    prov = parse_provenance(p.read_text(errors="replace"))
    if prov is None:
        return False, (f"{p.name}: provenance 헤더 없음 — flow 밖에서 만든 "
                       f"legacy 로그다. `make synth-sys-gate` (또는 "
                       f"`make synth-fp-op`) 로 재생성할 것")
    bad = []
    for rel, want in prov["sources"]:
        src = REPO / rel
        if not src.exists():
            bad.append(f"{rel}: 소스 없음")
        elif sha256_of(src) != want:
            bad.append(f"{rel}: sha256 불일치 (증거는 {want[:12]}…, "
                       f"현행은 {sha256_of(src)[:12]}…)")
    if bad:
        return False, (f"{p.name}: STALE — 증거가 현행 소스로 만들어지지 "
                       f"않았다: " + "; ".join(bad))
    if expected_sources is not None:
        have = [rel for rel, _ in prov["sources"]]
        if sorted(have) != sorted(expected_sources):
            return False, (f"{p.name}: 소스 목록이 합성 run 과 다르다 — "
                           f"증거 {sorted(have)} vs run log "
                           f"{sorted(expected_sources)}")
    if expected_top is not None and prov.get("top") != expected_top:
        return False, (f"{p.name}: top 이 합성 run 과 다르다 — 증거는 "
                       f"`{prov.get('top', '(없음)')}`, run log 는 "
                       f"`{expected_top}`. 같은 소스라도 top 이 다르면 "
                       f"premap 계수는 다른 설계를 잰 것이다")
    scope = "sources+top" if expected_top is not None else "sources(hash only)"
    return True, (f"{p.name}: provenance OK ({len(prov['sources'])} sources, "
                  f"{scope}, generated {prov.get('generated', '?')})")


def premap_sources(srcs_csv):
    """Vivado SRCS 목록 → premap 소스 목록.

    `synth/` 밑의 `*_gate_top.v` 래퍼를 뺀 것 = 코어 소스. 래퍼는 OOC I/O
    플롭만 있고 곱셈을 만들지 않으며, premap 계수는 **코어 top** 기준이라
    (`hierarchy -top <core>`) 래퍼를 읽으면 top 이 모호해진다.
    """
    return [s for s in srcs_csv.split(",") if s and not s.startswith("synth/")]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    ap.add_argument("--top", required=True,
                    help="코어 top (gate_top 래퍼가 아니다)")
    ap.add_argument("--sources", required=True,
                    help="Vivado SRCS 그대로 (쉼표 구분). gate_top 래퍼는 "
                         "여기서 자동으로 제외된다")
    ap.add_argument("--yosys", default="yosys")
    args = ap.parse_args()

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import fp_op_gate_check as gc

    gate = next((g for g in gc.GATES if g["tag"] == args.tag), None)
    if gate is None or "premap_mul_log" not in gate:
        print(f"gen_premap_mul: tag '{args.tag}' 는 premap $mul 축을 "
              f"선언하지 않는다 — 증거 생성 skip")
        return 0

    srcs = premap_sources(args.sources)
    if not srcs:
        sys.exit(f"gen_premap_mul: '{args.sources}' 에서 코어 소스를 "
                 f"고르지 못했다")
    missing = [s for s in srcs if not (REPO / s).exists()]
    if missing:
        sys.exit(f"gen_premap_mul: 소스 없음: {missing}")

    if shutil.which(args.yosys) is None:
        sys.exit(f"gen_premap_mul: '{args.yosys}' 를 찾을 수 없다. premap "
                 f"$mul 은 binding gate 축이므로 증거 없이 진행하지 않는다 "
                 f"(§12a: 측정 못 하면 PASS 가 아니라 정지)")

    # §26.6 pin form — 이 명령줄을 바꾸면 축의 의미가 바뀐다. 바꿀 일이
    # 있으면 spec §26.6 을 먼저 고칠 것.
    cmd = (f"read_verilog -I include {' '.join(srcs)}; "
           f"hierarchy -top {args.top}; proc; opt_clean; stat")
    print(f"gen_premap_mul: yosys -p '{cmd}'")
    r = subprocess.run([args.yosys, "-p", cmd], cwd=REPO,
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stdout[-4000:] + r.stderr[-4000:])
        sys.exit(f"gen_premap_mul: yosys exit {r.returncode}")

    now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    ver = ""
    for line in r.stdout.splitlines():
        if line.strip().startswith("Yosys "):
            ver = line.strip()
            break
    header = [
        HEADER_BEGIN,
        "# 이 헤더는 `make synth-sys-gate` / `make synth-fp-op` 가 자동으로",
        "# 쓴다 (synth/scripts/gen_premap_mul.py). 손으로 고치지 말 것 —",
        "# `fp_op_gate_check.py` 가 아래 sha256 을 현행 소스와 대조하고,",
        "# 하나라도 어긋나면 gate 를 PASS 가 아니라 STALE FAIL 로 끝낸다.",
        f"# tag: {args.tag}",
        f"# top: {args.top}",
        f"# yosys: {ver or '(unknown)'}",
        f"# generated: {now}",
        f"# command: yosys -p '{cmd}'",
    ]
    header += [f"# source: {s} sha256={sha256_of(REPO / s)}" for s in srcs]
    header += [HEADER_END, ""]

    out = RPT_DIR / gate["premap_mul_log"]
    out.write_text("\n".join(header) + "\n" + r.stdout)
    n = gc.parse_premap_mul(gate["premap_mul_log"])
    print(f"gen_premap_mul: {out.relative_to(REPO)} — premap $mul = {n} "
          f"(gate expects {gate.get('premap_mul_expect', 0)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
