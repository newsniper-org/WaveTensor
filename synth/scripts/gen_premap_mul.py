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


# =============================================================================
# v1.8.0e 3a-C4 적대 검수 (2026-08-18) — provenance 의 이중 사각지대
#
# 반증이 실측으로 재현한 것 두 가지:
#
#   (1) **gate_top 래퍼가 추적되지 않는다.** `premap_sources()` 가
#       `synth/` 로 시작하는 항목을 뺀다. 그 제외에는 정당한 사유가 있지만
#       (아래 그 함수의 docstring), 그것은 **yosys 계수의 입력** 을 고르는
#       규칙이지 **증거의 현행성** 규칙이 아니었다. 래퍼는 Vivado 가 실제로
#       합성하는 **top 그 자체** 이고, 3a-C4 가 11→13 포트로 실제로 고친
#       파일이다. 재현: 래퍼에 한 줄 붙이고 `fp_op_gate_check.py` 를 돌리면
#       6 gate 전건 `provenance OK` / EXIT=0 이 나왔다.
#
#   (2) **`` `include `` 된 헤더가 추적되지 않는다.** SRCS 에는 `.v` 만
#       올라가는데, `FP_StepSeq.v` 하나가 5개 헤더를 읽고 그중 3개는 생성된
#       ROM (`fp_frsqrt_seed_rom.vh` / `fp_fdiv_seed_rom.vh` /
#       `fp_fexp2_coeffs.vh`) 이다. ROM 을 재생성하면 설계가 바뀌는데 증거는
#       `provenance OK` 로 남는다. 재현: `isa_opcode_wires.vh` 에 한 줄
#       붙이고 돌리면 GATE S1-US 가 PASS/EXIT=0.
#
# 수리: 헤더에 두 계열을 **추가**한다 (기존 `# source:` 는 yosys 코어 소스
# 목록 그대로 둔다 — 그 축의 의미는 변하지 않았다).
#   * `# vivado-source:` — Vivado SRCS **전량** (래퍼 포함)
#   * `# include:`       — 위 전량에서 **전이적으로** 도달하는 헤더 전량
#
# 왜 해시 목록이지 "래퍼도 yosys 에 먹인다" 가 아닌가: 래퍼를 읽히면
# `hierarchy -top` 이 모호해져 premap 계수의 의미가 바뀐다 (§26.6 pin form).
# 계수 입력은 그대로 두고 **현행성 증거만** 넓히는 것이 축을 건드리지 않는
# 유일한 형태다.
# =============================================================================

_INC_RE = re.compile(r'^\s*`include\s+"([^"]+)"', re.M)


def _strip_comments(text):
    """`//` 줄주석과 `/* */` 블록주석 제거.

    필요한 이유는 실측이다: `HIU.v:557` 의 한국어 주석 안에 백틱 표기가
    있어, 주석을 지우지 않으면 존재하지 않는 include 를 하나 잡아낸다.
    """
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def resolve_includes(rel_paths, repo=None, incdirs=("include",)):
    """SRCS 전량에서 **전이적으로** 도달하는 헤더 목록 (repo 상대, 정렬).

    탐색 경로는 실제 flow 와 같은 한 벌이다 — yosys 는 `read_verilog -I
    include`, Vivado 는 `-include_dirs [file join $REPO_ROOT include]`
    (`synth/scripts/synth_fp_op.tcl:166`). 여기에 "포함하는 파일의 디렉터리"
    를 마지막 후보로만 덧붙인다.

    해소되지 않는 include 는 **조용히 버리지 않고** 예외로 세운다. 못 찾은
    헤더를 무시하면 그 헤더는 영원히 추적 밖에 남고, 그것이 바로 이 수리가
    닫으려는 실패형이다.
    """
    repo = Path(repo or REPO)
    seen, out, queue = set(), set(), list(rel_paths)
    while queue:
        rel = queue.pop()
        if rel in seen:
            continue
        seen.add(rel)
        src = repo / rel
        if not src.exists():
            raise FileNotFoundError(f"include 해소 실패: 소스 없음 {rel}")
        body = _strip_comments(src.read_text(errors="replace"))
        for inc in _INC_RE.findall(body):
            cands = [repo / d / inc for d in incdirs] + [src.parent / inc]
            hit = next((c for c in cands if c.exists()), None)
            if hit is None:
                raise FileNotFoundError(
                    f"{rel} 이 `include \"{inc}\"` 하는데 탐색 경로 "
                    f"{[str(c) for c in cands]} 에 없다. 조용히 넘기면 그 "
                    f"헤더는 provenance 밖에 영구히 남는다")
            hrel = str(hit.resolve().relative_to(repo.resolve()))
            out.add(hrel)
            queue.append(hrel)
    return sorted(out)


def parse_provenance(text):
    """로그 선두 provenance 헤더를 파싱한다.

    반환: dict(tag, top, yosys, generated, sources=[(rel_path, sha256), ...],
               vivado_sources=[...], includes=[...])
          헤더가 없으면 None (호출자가 STALE/LEGACY 로 판정한다).

    `vivado_sources` / `includes` 는 2026-08-18 이후 증거에만 있다. 옛
    증거에서는 빈 리스트가 되고, 그 사실이 **검증 강도 문자열에 찍힌다**
    (`verify_provenance` 참조) — 조용히 통과시키지 않는다.
    """
    if not text.startswith(HEADER_BEGIN):
        return None
    end = text.find(HEADER_END)
    if end < 0:
        return None
    head = text[:end]
    prov = {"sources": [], "vivado_sources": [], "includes": []}
    KEY = {"source": "sources", "vivado-source": "vivado_sources",
           "include": "includes"}
    for line in head.splitlines():
        m = re.match(r"^#\s+(tag|top|yosys|generated):\s+(.*)$", line)
        if m:
            prov[m.group(1)] = m.group(2).strip()
            continue
        m = re.match(r"^#\s+(source|vivado-source|include):\s+(\S+)\s+"
                     r"sha256=([0-9a-f]{64})\s*$", line)
        if m:
            prov[KEY[m.group(1)]].append((m.group(2), m.group(3)))
    return prov if prov["sources"] else None


def verify_provenance(log_path, expected_sources=None, expected_top=None,
                      expected_vivado_sources=None):
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

    **v1.8.0e 3a-C4 적대 검수 추가 (2026-08-18)** — 위 세 축은 전부 `.v`
    코어 소스에만 걸려 있었다. 실측으로 재현된 두 사각지대(파일 상단 주석
    블록 참조)를 닫기 위해 두 축을 더 본다:
      (e) `vivado-source` 해시 — Vivado 가 합성한 **전량**(gate_top 래퍼
          포함). 래퍼는 합성의 top 그 자체다.
      (f) `include` 해시 — 전이적으로 읽히는 헤더 전량(생성 ROM 포함).

    두 축은 **2026-08-18 이후 증거에만** 있다. 그 이전 로그에서는 헤더에
    해당 줄이 없고, 그때 이 함수는 PASS 를 주되 강도 문자열에
    `⚠ wrapper+include UNVERIFIED` 를 박는다. 조용한 완화가 아니라
    **찍히는 한정**이며, 없애는 방법은 하나뿐이다 — 그 gate 를 재합성하는
    것(전 flow). 어느 gate 가 어느 강도인지는 spec §37 이 이름으로 적는다.
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
    for kind in ("sources", "vivado_sources", "includes"):
        for rel, want in prov[kind]:
            src = REPO / rel
            if not src.exists():
                bad.append(f"[{kind}] {rel}: 소스 없음")
            elif sha256_of(src) != want:
                bad.append(f"[{kind}] {rel}: sha256 불일치 (증거는 "
                           f"{want[:12]}…, 현행은 {sha256_of(src)[:12]}…)")
    if bad:
        return False, (f"{p.name}: STALE — 증거가 현행 소스로 만들어지지 "
                       f"않았다: " + "; ".join(bad))
    if expected_vivado_sources is not None and prov["vivado_sources"]:
        have_v = [rel for rel, _ in prov["vivado_sources"]]
        if sorted(have_v) != sorted(expected_vivado_sources):
            return False, (f"{p.name}: Vivado 소스 목록이 합성 run 과 "
                           f"다르다 — 증거 {sorted(have_v)} vs run log "
                           f"{sorted(expected_vivado_sources)}")
    if prov["vivado_sources"]:
        # 헤더가 새 형식이면 include 목록이 **현행 소스 기준으로 재해소한
        # 것과 같아야** 한다. 해시 대조만으로는 "새 `include` 가 추가됐다" 를
        # 못 잡는다 — 추가분은 헤더에 없으므로 대조 대상이 아니기 때문이다.
        try:
            now_inc = resolve_includes([rel for rel, _ in
                                        prov["vivado_sources"]])
        except FileNotFoundError as e:
            return False, f"{p.name}: include 재해소 실패 — {e}"
        have_i = sorted(rel for rel, _ in prov["includes"])
        if have_i != now_inc:
            return False, (f"{p.name}: `include` 목록이 현행 소스와 다르다 "
                           f"— 증거 {have_i} vs 현행 {now_inc}. 헤더가 "
                           f"생긴 뒤 include 가 추가/삭제됐다는 뜻이고, "
                           f"추가분은 해시 대조가 보지 못한다")
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
    if prov["vivado_sources"]:
        scope += (f"+wrapper({len(prov['vivado_sources'])})"
                  f"+include({len(prov['includes'])})")
    else:
        # 조용히 통과시키지 않는다 — 강도 문자열에 한정을 박는다. 이 표식이
        # 보이는 gate 는 gate_top 래퍼와 `` `include `` 헤더가 **한 번도
        # 대조되지 않은** 증거 위에 서 있다 (2026-08-18 이전 형식).
        scope += " ⚠ wrapper+include UNVERIFIED (pre-2026-08-18 evidence)"
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
    # Vivado 가 실제로 합성한 **전량** (gate_top 래퍼 포함). yosys 에는
    # 먹이지 않는다 — 계수 축은 코어 top 기준이다. 해시만 증거에 박는다.
    vsrcs = [s for s in args.sources.split(",") if s]
    missing = [s for s in vsrcs if not (REPO / s).exists()]
    if missing:
        sys.exit(f"gen_premap_mul: 소스 없음: {missing}")
    try:
        incs = resolve_includes(vsrcs)
    except FileNotFoundError as e:
        sys.exit(f"gen_premap_mul: {e}")

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
    # v1.8.0e 3a-C4 — 사각지대 2종을 닫는 두 계열. `# source:` 는 yosys 가
    # 읽은 코어 소스, 아래 둘은 **Vivado 가 합성한 것 전량과 그것이 읽는
    # 헤더 전량**이다. 셋은 서로 다른 질문에 답한다.
    header += [f"# vivado-source: {s} sha256={sha256_of(REPO / s)}"
               for s in vsrcs]
    header += [f"# include: {s} sha256={sha256_of(REPO / s)}" for s in incs]
    header += [HEADER_END, ""]

    out = RPT_DIR / gate["premap_mul_log"]
    out.write_text("\n".join(header) + "\n" + r.stdout)
    n = gc.parse_premap_mul(gate["premap_mul_log"])
    print(f"gen_premap_mul: {out.relative_to(REPO)} — premap $mul = {n} "
          f"(gate expects {gate.get('premap_mul_expect', 0)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
