#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""정본 PDF 의 *렌더링*을 검사한다 — 컴파일 성공과 렌더링 정상은 다른 명제다.

## 왜 이 검사가 있는가

부록 B.5 표가 한동안 73쪽으로 부풀어 있었다. `auto` 폭 열 두 개가 긴 셀
하나에 끌려 자연폭을 키우면 가운데 `1fr` 열이 한 글자 폭으로 떨어지고,
표 전체가 세로로 흐른다. 그 동안:

  - typst compile 은 경고 0 으로 성공했다
  - 쪽수는 확인했지만 *렌더링은 아무도 보지 않았다*

즉 「컴파일 OK · N쪽」 보고가 반복되는 동안 문서의 10% 이상이 읽을 수 없는
상태였다. 컴파일러는 조판이 무너졌다는 것을 모른다 — 그것은 컴파일러의
관점에서 적법한 출력이기 때문이다.

## 무엇을 검사하는가

pdftotext 로 전 쪽을 뽑아, 줄 수가 충분한데 평균 줄 길이가 극단적으로 짧은
쪽(한 글자 세로 흐름)을 찾는다. 하나라도 있으면 실패.

`make guide` 가 컴파일과 이 검사를 묶는다 — 정본을 컴파일하는 정규 진입점은
raw `typst compile` 이 아니라 그쪽이다.
"""
import statistics
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PDF = ROOT / "docs" / "wt64v1-architecture-guide" / "main.pdf"

# 임계값. 정상 본문 쪽의 평균 줄 길이는 20자 이상이고, 무너진 표 쪽은
# 1~3자였다 (실측). 6 은 그 사이의 넓은 골짜기에 있다.
MIN_AVG_LINE_LEN = 6.0
MIN_LINES = 20  # 줄이 적은 쪽(장 표지 등)은 판정하지 않는다


def fail(msg: str) -> None:
    print(f"check_guide_render: FAIL — {msg}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    if not PDF.is_file():
        fail(f"{PDF} 가 없다 — 먼저 컴파일하라 (make guide)")
    try:
        txt = subprocess.run(
            ["pdftotext", str(PDF), "-"],
            capture_output=True, text=True, check=True,
        ).stdout
    except FileNotFoundError:
        fail("pdftotext 가 없다 (poppler). 이 검사는 렌더링 검사라 대체 수단이 없다")
    except subprocess.CalledProcessError as e:
        fail(f"pdftotext 실패: {e.stderr[:200]}")

    pages = txt.split("\f")
    bad = []
    for i, pg in enumerate(pages, 1):
        lines = [l for l in pg.splitlines() if l.strip()]
        if len(lines) < MIN_LINES:
            continue
        avg = statistics.mean(len(l.strip()) for l in lines)
        if avg < MIN_AVG_LINE_LEN:
            bad.append((i, avg))

    if bad:
        head = " · ".join(f"p.{i}({a:.1f})" for i, a in bad[:8])
        fail(
            f"한 글자 세로 흐름 쪽 {len(bad)}개 — {head}\n"
            f"  표의 auto 폭 열이 1fr 열을 짜부라뜨렸을 가능성이 크다. "
            f"열 폭을 고정하라 (부록 B.5 표의 주석 참조)"
        )

    print(f"check_guide_render: OK — {len(pages) - 1}쪽 전수, 세로 흐름 0")


if __name__ == "__main__":
    main()
