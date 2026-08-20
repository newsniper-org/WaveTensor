#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""ISA-7 정적 검사 — 인코딩에 형상 파라미터가 나타나지 않는가.

정본 §1.8 (후-formal, 축 (a)):

    ISA-7 인코딩 정적 불변 — 명령·태그 필드의 폭과 합법 값 범위에 형상
    파라미터가 나타나지 않는다. 명령·태그 유래 필드의 상수 비트 슬라이스가
    인스턴스 선택자로 쓰이지 않는다. (`grep` 으로 세어지는 수이며 답은 0이어야
    한다.)

정본 §1.2.2 가 이것을 두 축으로 나눈다:

    정적 검사 (INV-T1) 명령·태그 필드의 **폭 또는 합법 값 범위**가 형상
                       파라미터의 함수로 쓰인 지점 → 있으면 FAIL
    정적 검사 (INV-T2) 명령·태그 유래 필드의 **상수 비트 슬라이스가 인스턴스
                       선택자로** 쓰이는지 → 있으면 FAIL

부록 D.5 는 이 검사를 우선순위 밖의 **즉시** 항목으로 뺀다 — 인프라가 필요
없기 때문이다. 그래서 설계가 한 줄도 없는 지금부터 돌린다.

## 왜 "0건" 을 크게 자랑하지 않는가

정본 §6.7 이 지목한 실패형 중 하나가 *"조건이 안 맞으면 스스로 건너뛰고
통과로 보고하는 테스트"* 다. 스캔 대상이 0개일 때 "위반 0건" 은 참이지만
**아무것도 뜻하지 않는다.**

⇒ 이 검사는 위반 수와 함께 **스캔한 파일 수를 항상 같은 무게로 보고**한다.
   0건이 공허한지 실질인지 읽는 사람이 판정할 수 있어야 한다.

## 무엇이 "형상 파라미터" 인가

정본 §2.1: 그리드 크기는 구현 파라미터이며 각각 최대 4×4 다. PE 개수 ·
클러스터 개수 · 레인 개수 · 뱅크 개수 — INV-T1 은 인코딩의 값 공간이 이 중
어느 것의 함수여도 안 된다고 못박는다.

stdlib 전용.  python3 scripts/lint_isa7_topology.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RTL = REPO / "rtl"

SCAN_SUFFIX = {".scala", ".sv", ".v", ".svh", ".vh"}
SKIP_DIRS = {"target", "project", ".bloop", ".metals", ".bsp"}

# 형상 파라미터로 읽히는 식별자. 대소문자·스네이크/카멜을 함께 본다.
TOPOLOGY = re.compile(
    r"\b("
    r"pe_?rows?|pe_?cols?|cluster_?rows?|cluster_?cols?|"
    r"num_?pes?|num_?clusters?|num_?lanes?|num_?banks?|num_?partitions?|"
    r"pe_?count|cluster_?count|lane_?count|bank_?count|"
    r"grid_?rows?|grid_?cols?"
    r")\b",
    re.IGNORECASE,
)

# 인코딩(명령·태그) 유래임을 시사하는 식별자 — 정본이 정한 이름들.
ENCODING = re.compile(
    r"\b("
    r"lnid|lbid|dest_?node_?id|noc_?route|src_?kind|next_?hdr|bh_?len|"
    r"opcode|tag|eh_?kind|precision_?mode|dim_?override|addr_?mode|subscript"
    r")\b",
    re.IGNORECASE,
)

# 폭 / 값 범위를 만드는 문법.
WIDTH_EXPR = re.compile(
    r"(\bbits\b|\blog2Up\b|\bwidth\b|\[\s*[^\]]*-\s*1\s*:\s*0\s*\]|\bBits\s*\(|\bUInt\s*\()",
    re.IGNORECASE,
)

# 상수 비트 슬라이스 — 고정 니블 분할의 표면.
CONST_SLICE = re.compile(
    r"(\(\s*\d+\s+downto\s+\d+\s*\)|\[\s*\d+\s*:\s*\d+\s*\])"
)

# 슬라이스 결과가 인스턴스 선택자로 쓰이는 정황.
SELECTOR_HINT = re.compile(
    r"\b(select|sel\b|mux|demux|index|idx|case\s*\(|when\s*\(|\.apply\()",
    re.IGNORECASE,
)


def iter_design_files():
    if not RTL.exists():
        return
    for p in sorted(RTL.rglob("*")):
        if not p.is_file() or p.suffix not in SCAN_SUFFIX:
            continue
        if any(part in SKIP_DIRS for part in p.relative_to(RTL).parts):
            continue
        yield p


def main() -> int:
    inv_t1: list[str] = []
    inv_t2: list[str] = []
    scanned = 0

    for path in iter_design_files():
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except (UnicodeDecodeError, OSError):
            continue
        scanned += 1
        rel = str(path.relative_to(REPO))
        for n, line in enumerate(lines, 1):
            code = line.split("//")[0]
            if not code.strip():
                continue

            # INV-T1 — 인코딩 필드의 폭/범위가 형상 파라미터의 함수인가.
            if (
                ENCODING.search(code)
                and TOPOLOGY.search(code)
                and WIDTH_EXPR.search(code)
            ):
                inv_t1.append(f"{rel}:{n}: {code.strip()[:100]}")

            # INV-T2 — 인코딩 유래 값의 상수 비트 슬라이스가 선택자인가.
            if (
                ENCODING.search(code)
                and CONST_SLICE.search(code)
                and SELECTOR_HINT.search(code)
            ):
                inv_t2.append(f"{rel}:{n}: {code.strip()[:100]}")

    total = len(inv_t1) + len(inv_t2)

    if total:
        print("lint_isa7_topology: FAIL — 인코딩이 형상을 말하고 있다", file=sys.stderr)
        if inv_t1:
            print("\n  [INV-T1] 인코딩 필드의 폭/값 범위가 형상 파라미터의 함수다:", file=sys.stderr)
            for x in inv_t1:
                print(f"    · {x}", file=sys.stderr)
        if inv_t2:
            print("\n  [INV-T2] 인코딩 유래 값의 상수 비트 슬라이스가 인스턴스 선택자다:", file=sys.stderr)
            for x in inv_t2:
                print(f"    · {x}", file=sys.stderr)
        print(
            "\n  정본 §1.2 요건: 한 글자도 다르지 않은 바이너리가, 서로 다른\n"
            "  상호연결 형상과 규모에서 재컴파일 없이 같은 의미를 가져야 한다.\n"
            "  · LNID 는 평면 16비트, LBID 는 평면 8비트 — 내부 구조가 없다.\n"
            "  · 배달은 **사상표 조회**로 한다. 비트 슬라이스 디먹스는 금지.\n"
            "  · LBID 를 인스턴스 개수만큼 도는 비교 루프로 풀지 않는다 —\n"
            "    그 루프가 존재하는 한 그 값은 물리 인덱스다 (§1.4.3).",
            file=sys.stderr,
        )
        return 1

    if scanned == 0:
        print(
            "lint_isa7_topology: 스캔 대상 0개 — **미측정이다. 통과가 아니다.**\n"
            "  rtl/ 에 설계 파일(.scala/.sv)이 아직 없다. 인코딩 계층이 착지하는\n"
            "  순간부터 이 검사가 실질이 된다 (정본 §6.7 원칙 5)."
        )
        return 0

    print(
        f"lint_isa7_topology: OK — 위반 0건 / 스캔 {scanned}개 파일\n"
        f"  (0건이 실질인지 공허한지는 스캔 수가 말한다 — 두 수를 같이 읽을 것)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
