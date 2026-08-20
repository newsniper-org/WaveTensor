#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""정본의 *파생 표*가 원천과 어긋나지 않는지 검사한다.

## 왜 이 검사가 있는가

정본에는 다른 곳의 사실을 *요약해 적은* 표와 문장이 여럿이다 — 속성 총수,
축별 분류, 단계별 분류, 진행 현황의 run 수. 이것들은 원천이 아니라 파생이고,
파생은 원천이 움직이면 조용히 낡는다.

이 저장소에서 그 드리프트가 **다섯 번** 일어났다.

  1. 부록 D 축별 분류가 27 인데 실물이 39 였다 (HIU-8~11 추가 시 갱신 누락)
  2. §3.9 요약 표가 본문과 어긋났다
  3. README 의 쪽수가 낡았다
  4. 부록 D 진행 현황이 낡았다
  5. 부록 B.5 해설의 산술이 표 행 수와 맞지 않았다 (아홉 vs 열둘)

다섯 번 모두 *컴파일은 통과했고 아무 테스트도 실패하지 않았다.* 파생 표는
틀려도 조용하다 — 그것이 이 검사가 필요한 이유 전부다.

정본 README §검증 6항은 이 대조를 *셸 스니펫으로* 적어 두었다. 사람이 손으로
돌리는 검사이며, 부록 B.3 이 「집행되지 않는 규율」이라 부른 것과 같은 형태다.
그래서 기계로 옮겼다.

## 무엇을 대조하는가

  (1) 각 장 `#속성(...)` 선언 수  ==  부록 D 색인 행 수
  (2) 부록 D 축별 분류 합         ==  위 수
  (3) 부록 D 단계별 분류 합       ==  위 수
  (4) 부록 D 진행 현황의 run 수   ==  rtl/formal/tla/run.sh 의 expect_* 수

(4) 는 형식 배터리가 커질 때마다 낡는 자리다. 실제로 36 → 39 → 51 → 64 → 78
로 다섯 번 움직였다.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GUIDE = ROOT / "docs" / "wt64v1-architecture-guide"
RUNSH = ROOT / "rtl" / "formal" / "tla" / "run.sh"

PREFIXES = ("ISA", "FAB", "HIU", "EXT", "SEC")


def fail(msg: str) -> None:
    print(f"lint_guide_derived_tables: FAIL — {msg}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    if not GUIDE.is_dir():
        fail(f"정본 디렉터리가 없다: {GUIDE}")

    # --- 원천 (1): 각 장의 #속성 선언 -------------------------------------
    declared = []
    for f in sorted((GUIDE / "chapters").glob("*.typ")):
        declared += re.findall(r'#속성\("([A-Z]+-\d+)"', f.read_text(encoding="utf-8"))
    n_declared = len(declared)
    if n_declared == 0:
        fail("각 장에서 #속성 선언을 하나도 찾지 못했다 — 조판 환경 이름이 바뀌었나")

    dupes = {p for p in declared if declared.count(p) > 1}
    if dupes:
        fail(f"속성 ID 중복 선언: {sorted(dupes)}")

    # --- 파생 (1): 부록 D 색인 행 ----------------------------------------
    dpath = GUIDE / "appendix" / "d-properties.typ"
    dtext = dpath.read_text(encoding="utf-8")
    index_rows = re.findall(r"^  \[((?:%s)-\d+)\]," % "|".join(PREFIXES), dtext, re.M)
    n_index = len(index_rows)
    if n_index != n_declared:
        fail(
            f"속성 수 불일치 — 각 장 선언 {n_declared} vs 부록 D 색인 {n_index}\n"
            f"  색인에만: {sorted(set(index_rows) - set(declared))}\n"
            f"  선언에만: {sorted(set(declared) - set(index_rows))}"
        )

    # --- 파생 (2): 축별 분류 표 ------------------------------------------
    # 표 행은 `[(a) …], […], [38],` 형태다. *합계* 행도 함께 대조한다.
    # 이 셋(세 축 · 합계 · 실물)이 전부 같아야 한다 — 드리프트 1번이 정확히
    # 여기서 났다 (축 (a) 를 25 로 두어 합계 27, 실물은 39).
    axes = dict(
        (k, int(v))
        for k, v in re.findall(r"^  \[\(([abc])\)[^\]]*\], \[[^\]]*\], \[(\d+)\],", dtext, re.M)
    )
    if set(axes) != {"a", "b", "c"}:
        fail(
            "부록 D 축별 분류 표를 읽지 못했다 — 표가 사라졌거나 형식이 바뀌었다. "
            "이 검사가 조용히 건너뛰면 드리프트 1번이 그대로 재발한다"
        )
    axis_sum = axes["a"] + axes["b"] + axes["c"]
    if axis_sum != n_declared:
        fail(
            f"축별 분류 합 {axis_sum} != 속성 수 {n_declared} "
            f"((a) {axes['a']} / (b) {axes['b']} / (c) {axes['c']})"
        )
    total = re.search(r"^  \[\*합계\*\], \[\], \[\*(\d+)\*\],", dtext, re.M)
    if total is None:
        fail("부록 D 축별 분류 표에 *합계* 행이 없다")
    if int(total.group(1)) != n_declared:
        fail(f"축별 분류 표의 합계 {total.group(1)} != 속성 수 {n_declared}")

    # --- 파생 (3): 단계별 분류 합 ----------------------------------------
    n_pre = sum(1 for m in re.finditer(r'#속성\("[A-Z]+-\d+", 단계: "선"', "".join(
        f.read_text(encoding="utf-8") for f in sorted((GUIDE / "chapters").glob("*.typ")))))
    n_post = n_declared - n_pre
    stage = re.search(r"선\s*\*?(\d+)\*?\s*/\s*후\s*\*?(\d+)", dtext)
    if stage:
        s_pre, s_post = int(stage.group(1)), int(stage.group(2))
        if (s_pre, s_post) != (n_pre, n_post):
            fail(
                f"단계별 분류 불일치 — 부록 D 는 선 {s_pre}/후 {s_post}, "
                f"실물은 선 {n_pre}/후 {n_post}"
            )

    # --- 파생 (4): 진행 현황의 run 수 vs run.sh --------------------------
    if not RUNSH.is_file():
        fail(f"형식 배터리가 없다: {RUNSH}")
    # 호출만 센다. `expect_pass() {` 같은 *정의* 줄은 제외해야 한다 —
    # 처음 판은 `\b` 로 끝내서 정의 둘을 함께 세었고, 이 검사 자신이
    # 2 만큼 어긋난 수를 보고했다. 파생 표를 지키는 검사도 파생이다.
    runs = len(re.findall(r"^expect_(?:pass|fail)[ \t]", RUNSH.read_text(encoding="utf-8"), re.M))
    if runs == 0:
        fail("run.sh 에서 expect_pass/expect_fail 를 하나도 찾지 못했다")

    claimed = re.search(r"\*(\d+)\s*run\*", dtext)
    if claimed is None:
        fail("부록 D 진행 현황에 run 수가 적혀 있지 않다 — 파생 표가 사라졌다")
    n_claimed = int(claimed.group(1))
    if n_claimed != runs:
        fail(
            f"run 수 불일치 — 부록 D 는 {n_claimed} run, "
            f"rtl/formal/tla/run.sh 는 {runs} run"
        )

    print(
        f"lint_guide_derived_tables: OK — 속성 {n_declared}건 "
        f"(선 {n_pre} / 후 {n_post}) · 부록 D 색인 {n_index}건 정합"
        + f" · 축별 (a){axes['a']}/(b){axes['b']}/(c){axes['c']} 합계 정합"
        + f" · 형식 배터리 {runs} run 정합"
    )


if __name__ == "__main__":
    main()
