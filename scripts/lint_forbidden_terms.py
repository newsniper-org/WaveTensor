#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""금지 용어 집행 — "마이크로코드" / "microcode".

정본이 두 곳에서 규정한다 (서문 §0.6.1, 부록 C.6):

    부동소수점 스칼라 유닛을 구동하는 순차 제어기는 *step sequencer* 이고 그
    각 단계는 *step* 이다. 이것을 "마이크로코드"라고 부르지 않는다.
    이유: 마이크로코드는 명령어를 하위 연산으로 번역하는 계층을 뜻하는데, 이
    유닛은 번역하지 않는다 — 공유 연산기 두 기를 op 별로 정해진 순서에 따라
    걸어갈 뿐이다. **잘못된 이름은 잘못된 구현을 부른다.**

그런데 정본 부록 B.3 이 같은 항목을 이렇게 적는다:

    금지 용어 (마이크로코드) | **집행 lint 0건.** 준수가 사람 기억으로만 유지된다

이 파일이 그 0건을 없앤다. 부록 B.3 은 이런 항목을 "재구현이 반드시 고쳐야
할 것" 으로 분류한다 — 규범은 있는데 그것을 강제하는 기계가 없는 것들이다.

## 합법 인용 두 가지

전수 금지가 아니다. 그러면 규칙을 서술하는 문서 자신이 위반이 된다.

1. **규칙 자체를 서술하는 줄** — 금지를 선언·인용·기록하는 문장.
2. **역사적 고유명사** `sequential-microcode-mu` — 과거 설계 workflow 의 내부
   명칭이며, 유닛을 그렇게 *지칭*한 것이 아니라 이름을 *인용*한 것이다.

## 왜 래칫인가

파일별 기대 건수를 못박는다. 늘면 새 위반이고, **줄어도 실패**다 — 규칙을
강제하던 문장이 조용히 사라지는 것이 정본 §6.5.1 이 기록한 실제 사고
("속성을 강제하던 검사가 모듈 삭제와 함께 증발했고 정적 검사는 전부 통과했다")
와 같은 형태이기 때문이다. 변경은 의도적으로 이 표를 고쳐서 한다.

stdlib 전용.  python3 scripts/lint_forbidden_terms.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

TERM = re.compile(r"마이크로코드|microcode", re.IGNORECASE)

# 스캔에서 제외 — VCS 내부 · 빌드 산출물 · 캐시.
SKIP_DIRS = {
    ".git", "sim_build", "__pycache__", ".pytest_cache", ".Xil",
    ".benchmarks", "target", "node_modules", ".private",
}
# 텍스트가 아닌 것 / 도구 출력물.
SKIP_SUFFIX = {
    ".pdf", ".png", ".jpg", ".zst", ".gz", ".jar", ".bit", ".hex",
    ".rpt", ".log", ".jou", ".xml", ".dcp",
}

# 합법 인용 판정 — 둘 중 하나에 해당해야 한다.
HISTORICAL_NAME = re.compile(r"sequential-microcode-mu")
RULE_STATEMENT = re.compile(
    r"금지|부르지 않는다|쓰지 않는다|사용하지 않는다|정본은|위반|규율|lint|"
    r"allowlist|용어|terminology|step sequencer|D-32|forbidden"
)
# 금지 선언은 여러 줄에 걸친다. 판정은 ±CONTEXT 줄의 창에서 한다.
CONTEXT = 3

# 래칫 — 파일별 기대 건수. 전부 위 두 부류의 합법 인용이다.
EXPECTED: dict[str, int] = {
    "docs/wt64v1-architecture-guide/chapters/00-preface.typ": 2,
    "docs/wt64v1-architecture-guide/chapters/02-fabric-alu.typ": 1,
    "docs/wt64v1-architecture-guide/appendix/b-gaps.typ": 1,
    "docs/wt64v1-architecture-guide/appendix/c-glossary.typ": 1,
    "docs/wt64v1-architecture-guide/README.md": 2,
    # CI 스텝 이름 — 이 lint 자신을 가리키는 라벨이다.
    ".github/workflows/gates.yml": 1,
    "scripts/lint_forbidden_terms.py": 0,   # 아래에서 자기 자신은 면제한다
    ".claude-memos/wt64v1_spec.md": 4,
    ".claude-memories/fp32_step_sequencer_terminology.md": 6,
    ".claude-memories/MEMORY.md": 1,
}

SELF = "scripts/lint_forbidden_terms.py"


def iter_files():
    for p in REPO.rglob("*"):
        if not p.is_file():
            continue
        if any(part in SKIP_DIRS for part in p.relative_to(REPO).parts):
            continue
        if p.suffix.lower() in SKIP_SUFFIX:
            continue
        yield p


def main() -> int:
    illegal: list[str] = []
    counts: dict[str, int] = {}

    for path in iter_files():
        rel = str(path.relative_to(REPO))
        if rel == SELF:
            continue  # 검사기 자신은 규칙을 서술하므로 면제한다
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        lines = text.splitlines()
        hits = [(n, line) for n, line in enumerate(lines, 1) if TERM.search(line)]
        if not hits:
            continue
        counts[rel] = len(hits)
        for n, line in hits:
            # 판정은 **문맥 창**으로 한다. 금지 선언은 여러 줄에 걸치는 일이
            # 흔하다 — 용어집은 낱말이 한 줄에, "사용하지 않는다" 가 다음 줄에
            # 있다. 줄 단위로 보면 규칙을 서술하는 문서 자신이 위반이 된다.
            lo, hi = max(0, n - 1 - CONTEXT), min(len(lines), n + CONTEXT)
            window = "\n".join(lines[lo:hi])
            if HISTORICAL_NAME.search(window) or RULE_STATEMENT.search(window):
                continue
            illegal.append(f"{rel}:{n}: {line.strip()[:100]}")

    problems: list[str] = []

    if illegal:
        problems.append("금지 용어를 **지칭**으로 쓴 줄:")
        problems.extend(f"    {x}" for x in illegal)

    for rel, n in sorted(counts.items()):
        exp = EXPECTED.get(rel)
        if exp is None:
            problems.append(
                f"래칫에 없는 파일에서 {n}건: {rel}"
                "  ← 합법 인용이라면 EXPECTED 에 의도적으로 등재할 것"
            )
        elif n != exp:
            direction = "늘었다 (새 위반?)" if n > exp else "줄었다 (규칙 서술이 사라졌나?)"
            problems.append(f"건수 불일치: {rel} 기대 {exp} / 실제 {n} — {direction}")

    for rel, exp in sorted(EXPECTED.items()):
        if rel == SELF:
            continue
        if exp > 0 and rel not in counts:
            problems.append(
                f"사라졌다: {rel} 에 {exp}건이 있어야 하는데 0건이다"
                "  ← 규칙을 강제/서술하던 문장이 증발했을 수 있다"
            )

    if problems:
        print("lint_forbidden_terms: FAIL", file=sys.stderr)
        for p in problems:
            print(f"  · {p}", file=sys.stderr)
        print(
            "\n  정본: 순차 제어기는 **step sequencer**, 각 단계는 **step** 이다.\n"
            '  "마이크로코드" 라고 부르지 않는다 — 번역 계층이 아니기 때문이다.\n'
            "  잘못된 이름은 잘못된 구현을 부른다 (서문 §0.6.1 · 부록 C.6).",
            file=sys.stderr,
        )
        return 1

    total = sum(counts.values())
    print(
        f"lint_forbidden_terms: OK — {len(counts)}개 파일 {total}건, 전부 합법 인용 "
        "(규칙 서술 또는 역사적 명칭)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
