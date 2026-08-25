#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""후-formal 영향 역색인 — 이 파일을 바꾸면 어느 sby 태스크가 흔들리는가.

## 왜 이 도구가 있는가

2026-08-25 에 실제로 놓친 회귀가 있다. `MmioConfig.scala` 의 예약 비트
엄격화로 LBID 커밋 조건이 좁아졌는데, 담당자가 `MmioConfig/` 의 두 태스크만
돌리고 **그 모듈을 인스턴스하는 합성 증명** `RouteMmio/route_mmio.sby`
(= `MmioConfig.sv` + `RouteJudge.sv`)를 돌리지 않았다. 합성 하네스가 옛
'성공' 정의를 사본으로 들고 있었으므로 `p_bank_iff`·`p_pair_bank` 가
induction 에서 깨졌고, basecase 는 통과했기에 얕은 확인으로는 보이지 않았다.

뒤이은 검증자도 「이번 파도가 바꾼 .sby/props 0개」만 확인하고 *직전 파도가
바꾼 생성물*은 대조하지 않아 그것을 「선재 결함」으로 오분류했다.

두 사람 다 성실했고 둘 다 놓쳤다. 사람이 매번 역색인을 머리로 짜야 하는
구조였기 때문이다. 그 역색인이 이 도구다.

## 쓰는 법

    python3 scripts/sby_impact.py rtl/generated/MmioConfig.sv
    python3 scripts/sby_impact.py $(git diff --name-only HEAD)
    python3 scripts/sby_impact.py --all        # 역색인 전체를 인쇄

인자 없이 부르면 `git diff --name-only HEAD` 를 스스로 읽는다.

## 이 도구가 재는 것과 재지 않는 것

재는 것: `.sby` 의 `[files]` 절이 선언한 입력 파일과 변경분의 교집합.
재지 않는 것: 증명의 통과 여부. 그것은 실제로 sby 를 돌려야 안다 —
이 도구는 **무엇을 돌려야 하는지**만 답한다.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SBY_DIR = ROOT / "rtl" / "formal" / "sby"


def sby_inputs() -> dict:
    """{sby 경로: {선언된 입력 파일들}} — [files] 절을 판다."""
    index = {}
    for f in sorted(SBY_DIR.rglob("*.sby")):
        lines = f.read_text(encoding="utf-8").splitlines()
        files, in_files = set(), False
        for line in lines:
            s = line.strip()
            if s.startswith("["):
                in_files = s.lower().startswith("[files]")
                continue
            if not in_files or not s or s.startswith("#"):
                continue
            # `dst src` 형태도 허용된다 — 마지막 토큰이 원본 경로다.
            files.add(s.split()[-1])
        index[f.relative_to(ROOT)] = files
    return index


def changed_files() -> list:
    """추적 변경 ∪ 미추적 신규.

    미추적을 함께 보는 이유: 기존 .sby 에 *새 props 파일만* 추가하는 파도는
    추적 변경이 0 일 수 있고, 그러면 이 도구가 「돌릴 것 없음」이라 답한다 —
    이 도구가 존재하는 이유가 정확히 그 부류다. 2026-08-25 전수 검증이
    실측으로 지적했다(그때는 같은 파도가 생성물도 건드려 우연히 잡혔다).
    """
    seen = []
    for args in (["git", "diff", "--name-only", "HEAD"],
                 ["git", "ls-files", "--others", "--exclude-standard"]):
        out = subprocess.run(args, cwd=ROOT, capture_output=True, text=True, check=False)
        seen += [ln for ln in out.stdout.splitlines() if ln.strip()]
    return sorted(set(seen))


def main() -> None:
    args = sys.argv[1:]
    index = sby_inputs()

    if not index:
        print("sby_impact: FAIL — *.sby 가 하나도 없다", file=sys.stderr)
        sys.exit(1)

    # 선언된 입력이 실재하는지 — 경로는 저장소 루트 기준이 규약이다.
    # (2026-08-24: `../../../generated/` 상대 경로가 호출 cwd 기준으로 풀려
    #  에이전트 국소 실행은 통과하고 루트 스윕은 FileNotFoundError 로 죽었다.)
    missing = [
        (sby, p) for sby, fs in index.items() for p in fs
        if not (ROOT / p).is_file()
    ]
    if missing:
        for sby, p in missing:
            print(f"sby_impact: FAIL — {sby} 의 [files] 가 없는 파일을 가리킨다: {p}",
                  file=sys.stderr)
        print("  경로는 *저장소 루트 기준*이다 — sby 는 [files] 를 호출 cwd 로 푼다.",
              file=sys.stderr)
        sys.exit(1)

    if args == ["--all"]:
        print(f"sby_impact: 역색인 — {len(index)} 태스크 파일")
        rev = {}
        for sby, fs in index.items():
            for p in fs:
                rev.setdefault(p, []).append(str(sby))
        for p in sorted(rev):
            print(f"  {p}")
            for s in sorted(rev[p]):
                print(f"      → {s}")
        return

    changed = args or changed_files()
    if not changed:
        print("sby_impact: 변경 없음 — 돌릴 태스크 없음")
        return

    changed_set = set(changed)
    hit = {sby: sorted(fs & changed_set) for sby, fs in index.items() if fs & changed_set}

    if not hit:
        print(f"sby_impact: 변경 {len(changed)}건 중 sby 입력 0건 — 돌릴 태스크 없음")
        print("  (근거: 아래 어느 .sby 의 [files] 에도 없다. "
              "「아마 무관」이 아니라 구성적 근거다.)")
        return

    print(f"sby_impact: 돌려야 할 태스크 {len(hit)}건 — "
          f"변경분이 이들의 [files] 에 실재한다")
    for sby in sorted(hit):
        print(f"  {sby}")
        for p in hit[sby]:
            print(f"      ← {p}")
    print()
    print("실행 (저장소 루트에서 — 경로가 호출 cwd 기준으로 풀린다):")
    for sby in sorted(hit):
        name = Path(sby).stem
        d = Path(sby).parent.name
        print(f"  sby -f --prefix /tmp/sby-{d}-{name} {sby}")


if __name__ == "__main__":
    main()
