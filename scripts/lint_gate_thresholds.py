#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""판정기 무결성 — 게이트 기준을 사후에 옮기지 못하게 한다.

정본 부록 B.3:

    게이트 기준을 사후에 옮기지 않는다 | **집행 기계 없음.**
                                        판정기 상수를 편집해도 아무것도 울지 않는다

그리고 정본 §6.7 「측정 게이트 원칙」:

    1. 기준은 측정 이전에 공표한다. 재고 나서 정한 기준은 기준이 아니다.
    2. 기준을 사후에 완화하지 않는다. **초과하면 설계를 줄이지 기준을 늘리지 않는다.**

이 파일이 그 "아무것도 울지 않는다" 를 없앤다.

## 왜 상수가 아니라 파일 전체를 해시하는가

임계값만 뽑아 감시하면 임계를 *우회하는* 편집을 놓친다 — 비교 연산자를 뒤집거나,
판정 대상 목록에서 한 항을 빼거나, 실패 경로를 `continue` 로 바꾸는 것은 상수를
건드리지 않고도 게이트를 무력화한다. 실제로 이 저장소가 겪은 사고도 상수 변경이
아니라 *증거 파일이 재생성되지 않은 채 판정에 쓰이던 것*이었다.

판정기는 게이트를 **정의하는** 파일이다. 그런 파일에 조용한 편집이라는 범주는
없어야 한다. 그래서 전체를 묶고, 바꾸려면 아래 표를 **의도적으로** 고치게 한다.
그 편집이 곧 "기준을 바꿨다" 는 기록이다.

## 이 검사가 하지 않는 것

새 기준이 **옳은지**는 판정하지 않는다 — 그것은 사람의 일이다. 이 검사가 보장하는
것은 오직 하나: *기준이 바뀐 사실이 조용히 지나가지 않는다.*

## 왜 BLAKE2b-512 인가 (그리고 왜 BLAKE3 가 아닌가)

BLAKE 계열 · 512비트 출력 · **stdlib** 세 가지를 동시에 만족하는 것이 이것뿐이다.

- `blake3` 는 `hashlib` 에 **없다** (실측: 호스트·컨테이너 모두 부재). PyPI
  패키지가 필요한데, 이 저장소의 lint 는 stdlib 전용이라는 성질로 "cocotb 없이도
  바로 돌릴 수 있다" 를 보장한다. merge gate 에 설치 의존을 넣으면 *"설치했나"*
  라는 새 실패 경로가 생기고, 그 경로는 조용히 통과하는 쪽으로 기운다.
- BLAKE3 의 강점(대용량 병렬·트리 해싱)은 여기서 발현되지 않는다 — 대상은
  수십 KB 파일 몇 개다.
- 512비트가 이 위협 모델에 더해 주는 것도 없다. 이 해시는 적대적 preimage
  방어가 아니라 **변경 탐지**다. 그래도 길이 비용이 0이므로 넉넉한 쪽을 쓴다.

> 저장소의 해시 핀은 **전부 BLAKE2b-512 로 통일**돼 있다 (2026-08-20) —
> TLA+ 도구 핀 · premap 게이트 증거 · 생성물 출처 · golden 보고서 메타 · 이 표.
> 통일의 값은 취향이 아니다: 계열이 섞이면 "무엇으로 쟀는가" 앞에
> *"어느 해시로?"* 라는 질문이 하나 더 붙고, 그 질문에 답이 없는 증거가 생긴다.

stdlib 전용.  python3 scripts/lint_gate_thresholds.py
"""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path

#: 판정기 해시 알고리즘. 바꾸면 아래 JUDGES 표 전체를 다시 계산해야 한다.
DIGEST_BITS = 512

REPO = Path(__file__).resolve().parent.parent

# 판정기와 그 BLAKE2b-512. **이 표를 고치는 것은 게이트 기준을 고치는 것이다.**
# 고칠 때는 무엇을 왜 바꿨는지 커밋 메시지에 남기고, 필요하면 재측정한다.
JUDGES: dict[str, str] = {
    "synth/scripts/fp_op_gate_check.py":
        "ade1cce7ea9c92191d81a0417f4de5f050846d7f99a8c600d737ba146c4f663f"
        "fe766444491b7fa25f695f08ae5f12d1a769c1f7d006a0b33b6d7c743492133e",
    "synth/lattice/fp_ops/gate_check.py":
        "194f50f3b377d91ed092d507f2f1279fb40f0788ebf07971530892b0a726e4e3"
        "e87702960400a874f1e1a0bb4d777e1c779b1bcc3e115e2154854523158d2356",
    "scripts/lint_synth_coverage.py":
        "2fbac9eb274c34293c4efdfa1535cffa1a75321b198f07aa3570eb3f28ecb6ba"
        "dfb2d9102bbfc7b710f2ff77e02a8ff1432f9381f7ba5d294b1d6854fec78bd0",
}


def digest(path: Path) -> str:
    return hashlib.blake2b(path.read_bytes(), digest_size=DIGEST_BITS // 8).hexdigest()


def main() -> int:
    problems: list[str] = []
    for rel, expected in sorted(JUDGES.items()):
        path = REPO / rel
        if not path.exists():
            problems.append(
                f"{rel}: **판정기가 사라졌다.**\n"
                f"      게이트를 강제하던 유일한 검사가 증발하는 것이 이 저장소가\n"
                f"      실제로 밟은 실패형이다 (정본 §6.5.1)."
            )
            continue
        actual = digest(path)
        if actual != expected:
            problems.append(
                f"{rel}: 판정기가 바뀌었다 (BLAKE2b-{DIGEST_BITS})\n"
                f"      기대 {expected}\n"
                f"      실제 {actual}"
            )

    if problems:
        print("lint_gate_thresholds: FAIL — 게이트를 정의하는 파일이 움직였다", file=sys.stderr)
        for p in problems:
            print(f"  · {p}", file=sys.stderr)
        print(
            "\n  판정기 편집은 **기준 변경**이다. 정당한 변경이라면:\n"
            "    1) 무엇을 왜 바꿨는지 커밋 메시지에 남긴다\n"
            "    2) 기준이 실제로 움직였다면 **재측정**한다\n"
            "    3) 이 파일의 JUDGES 표를 새 BLAKE2b-512 로 갱신한다\n       python3 -c \"import hashlib,pathlib;print(hashlib.blake2b(pathlib.Path('<파일>').read_bytes(),digest_size=64).hexdigest())\"\n"
            "\n  갱신 자체가 기록이다. 조용히 지나가는 경로를 두지 않는 것이 목적이며,\n"
            "  새 기준이 옳은지는 이 검사가 판정하지 않는다 — 사람의 일이다.\n"
            "\n  ⚠️ 초과하면 **설계를 줄이지 기준을 늘리지 않는다** (정본 §6.7 원칙 2).",
            file=sys.stderr,
        )
        return 1

    print(f"lint_gate_thresholds: OK — 판정기 {len(JUDGES)}종 무결 (BLAKE2b-{DIGEST_BITS})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
