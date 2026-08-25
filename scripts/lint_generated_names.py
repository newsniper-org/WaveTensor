#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""줄번호가 박힌 생성 신호 이름을 하네스가 하드코딩한 자리의 실재성 검사.

## 왜 이 검사가 있는가

SpinalHDL 은 익명 `when` 블록의 조건 신호를 `when_<파일>_l<줄번호>` 로 이름
짓는다. 후-formal 하네스가 그 내부 신호를 관측하려면 그 이름을 **하드코딩**
할 수밖에 없고(yosys 자유 프론트엔드에 계층 참조가 없다), 그 순간
**Scala 원본의 줄 하나만 밀려도 이름이 조용히 바뀐다.**

조용히 바뀌면 무슨 일이 나는가: 하네스가 없는 이름을 참조하고, yosys 가
그것을 암묵 wire 로 만들어 **항상 0 인 신호**가 된다. 단언은 여전히 세어지고
(HOLLOW 게이트를 통과한다) 증명도 통과한다 — 다만 아무것도 재지 않는다.
공허의 두 번째 결이며, 셀 수로는 잡히지 않는다.

2026-08-25 전수 검증이 이 부류를 실측했다: `when_Common_l141` → `l259` 로
줄이 밀린 자리에서 `p_ab_not_fault_src` 가 무력화됐고, 역-변이로 재현됐다.

## 이 검사가 재는 것과 재지 못하는 것

잰다: 하네스가 참조하는 `when_*_l<N>` 이 대응 생성물에 **실재하는가**.
재지 못한다: 그 이름이 *의도한 그 조건*인가. 줄이 밀려 다른 `when` 이 같은
번호를 차지하면 이름은 실재하지만 뜻이 바뀐다 — 그 층은 증명 자신이
반례로 답해야 한다. 이 lint 는 「이름이 사라진 경우」만 닫는다.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSERT_DIR = ROOT / "rtl" / "sv" / "assert"
GEN_DIR = ROOT / "rtl" / "generated"

NAME = re.compile(r"when_([A-Za-z0-9]+)_l(\d+)")


def fail(msg: str) -> None:
    print(f"lint_generated_names: FAIL — {msg}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    if not ASSERT_DIR.is_dir() or not GEN_DIR.is_dir():
        print("lint_generated_names: OK — 하네스/생성물 디렉터리 부재 (미착지)")
        return

    # 생성물 전체를 한 번만 읽어 이름 집합을 만든다. 어느 파일에 있든
    # 인라인될 수 있으므로(SpinalHDL 이 하위 모듈을 상위에 펼친다) 파일별이
    # 아니라 전역 실재성을 본다.
    pool = set()
    for g in sorted(GEN_DIR.glob("*.sv")):
        pool.update(m.group(0) for m in NAME.finditer(g.read_text(encoding="utf-8")))

    refs = {}  # 이름 -> 참조한 하네스들
    for f in sorted(ASSERT_DIR.glob("*.sv")):
        for m in NAME.finditer(f.read_text(encoding="utf-8")):
            refs.setdefault(m.group(0), set()).add(f.name)

    missing = sorted(n for n in refs if n not in pool)
    if missing:
        for n in missing:
            who = " · ".join(sorted(refs[n]))
            print(f"lint_generated_names: {n} 가 생성물에 없다 — 참조: {who}",
                  file=sys.stderr)
        fail("줄번호가 밀려 이름이 사라졌다. 하네스가 참조하는 신호가 "
             "암묵 wire(상수 0)가 되어 단언이 조용히 무력해진다 — "
             "셀 수 게이트로는 잡히지 않는 공허다")

    print(f"lint_generated_names: OK — 줄번호 매인 참조 {len(refs)}종 전부 "
          f"생성물에 실재 · 하네스 {len({w for s in refs.values() for w in s})}파일")
    if refs:
        for n in sorted(refs):
            print(f"  {n} ← {' · '.join(sorted(refs[n]))}")


if __name__ == "__main__":
    main()
