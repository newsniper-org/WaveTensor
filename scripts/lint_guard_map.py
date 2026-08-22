#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""선-formal 모델의 가드와 RTL 검사의 대응을 대조한다.

## 왜 이 검사가 있는가

정본 §6.3 은 RTL 단계의 완료 판정을 「모델과의 대응 관계가 서술 가능함」으로
정한다. 서술은 드리프트한다 — 그래서 서술을 기계 검사 가능한 형태로 강제한다:

  RTL 파일의 GUARD-MAP 블록:
    // GUARD-MAP: <Model>.<guard> -> <검사 서술>
    // GUARD-MAP: <Model>.<guard> -> DELEGATED(<모듈>) — <근거>
    // GUARD-MAP: <Model>.<guard> -> ENV — <환경 의무, 근거 절>

  TLA+ 모델의 가드 목록:
    AllGuards == {"g1", "g2", ...}

이 검사가 대조하는 것:
  (1) ENFORCED 목록의 각 모델에 대해, AllGuards 의 **모든** 가드가 rtl/spinal
      트리 어딘가의 GUARD-MAP 에 **정확히 한 번** 나타난다.
  (2) GUARD-MAP 이 참조하는 (모델, 가드) 가 실재한다 — 오타·삭제된 가드를
      계속 주장하는 매핑을 잡는다.
  (3) DELEGATED 대상 모듈명이 비어 있지 않다.

이 검사가 대조하지 **못하는** 것 (정직하게):
  매핑의 *참* — "이 신호가 정말 그 가드를 강제하는가"는 후-formal(같은 속성을
  RTL 에 다시 검사)이 답한다. 이 lint 는 주장의 전수성과 실재성만 잰다.

## ENFORCED 래칫

모델은 RTL 이 착지한 시점에 이 목록에 들어오고, 이후 뺄 수 없다 (래칫).
목록에 없는 모델은 아직 RTL 미착지 — 검사 대상이 아니다. 목록을 줄이는
diff 는 이 검사가 아니라 리뷰가 잡아야 하므로, 줄이면 여기서 크게 실패한다.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TLA_DIR = ROOT / "rtl" / "formal" / "tla"
RTL_DIR = ROOT / "rtl" / "spinal" / "src"

# RTL 착지 래칫 — 1차 파도 (2026-08-22). 늘기만 한다.
ENFORCED = [
    "Route",
    "SharedUnit",
    "ResultBank",
    "Fabric",
    "XlateStore",
    "Isolation",
    "Walk",
    "Decode",
]
# 미착지 (2차 파도 대기): NoLoss(회계는 횡단 관심사), Platform(플랫폼 비교는
# 검증 구조), Payload(재조립), MemOrder(순서 토큰). 착지 시 위로 옮긴다.

_MIN_ENFORCED = 8  # 래칫 바닥 — 이 수 아래로 줄이는 편집은 실패한다


def fail(msg: str) -> None:
    print(f"lint_guard_map: FAIL — {msg}", file=sys.stderr)
    sys.exit(1)


def model_guards(model: str) -> set:
    p = TLA_DIR / f"{model}.tla"
    if not p.is_file():
        fail(f"ENFORCED 모델 {model} 의 .tla 가 없다: {p}")
    m = re.search(r"AllGuards\s*==\s*\{([^}]*)\}", p.read_text(encoding="utf-8"))
    if not m:
        fail(f"{model}.tla 에서 AllGuards 를 찾지 못했다")
    return set(re.findall(r'"([A-Za-z_]+)"', m.group(1)))


def main() -> None:
    if len(ENFORCED) < _MIN_ENFORCED:
        fail(f"ENFORCED 래칫 위반 — {len(ENFORCED)} < {_MIN_ENFORCED}. 목록은 늘기만 한다")

    # RTL 트리의 GUARD-MAP 수집
    entries = []  # (model, guard, kind, file, line)
    pat = re.compile(
        r"//\s*GUARD-MAP:\s*([A-Za-z]+)\.([A-Za-z_]+)\s*->\s*(.+)$"
    )
    scala_files = sorted(RTL_DIR.rglob("*.scala"))
    if not scala_files:
        fail(f"{RTL_DIR} 에 .scala 가 없다 — 스캔 대상이 사라졌다")
    for f in scala_files:
        for i, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            m = pat.search(line)
            if not m:
                continue
            model, guard, rhs = m.group(1), m.group(2), m.group(3).strip()
            if rhs.startswith("DELEGATED"):
                kind = "DELEGATED"
                dm = re.match(r"DELEGATED\(([^)]*)\)", rhs)
                if not dm or not dm.group(1).strip():
                    fail(f"{f.relative_to(ROOT)}:{i} — DELEGATED 대상 모듈명이 비었다")
            elif rhs.startswith("ENV"):
                kind = "ENV"
            else:
                kind = "CHECK"
            entries.append((model, guard, kind, f.relative_to(ROOT), i))

    # (2) 실재성 — 참조된 모델·가드가 실재하는가
    known = {}
    for model, guard, kind, f, i in entries:
        if model not in known:
            p = TLA_DIR / f"{model}.tla"
            if not p.is_file():
                fail(f"{f}:{i} — GUARD-MAP 이 없는 모델 {model} 을 참조한다")
            known[model] = model_guards(model)
        if guard not in known[model]:
            fail(
                f"{f}:{i} — {model}.{guard} 는 AllGuards 에 없다 "
                f"(실재: {sorted(known[model])})"
            )

    # (1) 전수성·유일성 — ENFORCED 모델의 모든 가드가 정확히 한 번
    bad = []
    for model in ENFORCED:
        guards = model_guards(model)
        for g in sorted(guards):
            hits = [(f, i) for (m2, g2, k, f, i) in entries if m2 == model and g2 == g]
            if len(hits) == 0:
                bad.append(f"{model}.{g} — GUARD-MAP 부재 (가드가 RTL 에서 무주장)")
            elif len(hits) > 1:
                locs = " · ".join(f"{f}:{i}" for f, i in hits)
                bad.append(f"{model}.{g} — 중복 주장 {len(hits)}회 ({locs})")
    if bad:
        fail("전수성 위반 " + str(len(bad)) + "건\n  " + "\n  ".join(bad))

    n_check = sum(1 for e in entries if e[2] == "CHECK")
    n_del = sum(1 for e in entries if e[2] == "DELEGATED")
    n_env = sum(1 for e in entries if e[2] == "ENV")
    total_guards = sum(len(model_guards(m)) for m in ENFORCED)
    print(
        f"lint_guard_map: OK — ENFORCED {len(ENFORCED)}모델 · 가드 {total_guards} 전수 "
        f"(CHECK {n_check} / DELEGATED {n_del} / ENV {n_env}) · "
        f"스캔 {len(scala_files)}파일 · 참조 실재성 위반 0"
    )


if __name__ == "__main__":
    main()
