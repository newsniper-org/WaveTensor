#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""후-formal 증명 선언(PROVES)과 GUARD-MAP 주장의 대조.

## 이 검사의 자리

lint_guard_map 은 「가드마다 RTL 주장 1줄」의 전수성을 재고, 스스로
「매핑의 참은 후-formal 몫」이라 적었다. 후-formal 이 착지하면 그 참의
증거는 sby 스크립트다 — 각 .sby 머리의 `# PROVES: <Model>.<guard>` 줄이
"이 태스크가 그 가드의 참을 잰다"는 앵커다.

이 검사가 대조하는 것:
  (1) PROVES 가 참조하는 (모델, 가드)가 실재한다 (AllGuards 대조).
  (2) PROVES 는 CHECK 가드에만 선다 — DELEGATED/ENV/구조-skip 가드에
      증명을 주장하면 앵커가 거짓이다.
  (3) 커버리지 래칫 — PROVES 로 덮인 CHECK 가드 수는 줄지 않는다.

이 검사가 재지 **못하는** 것 (정직하게):
  증명의 통과 여부 — 그것은 `make rtl-postformal` 이 sby 를 실제로 돌려
  판정한다. 이 lint 는 선언의 실재성·정합성·래칫만 잰다. 통과 없이
  선언만 커밋하는 것은 make 타깃이 잡는다.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TLA_DIR = ROOT / "rtl" / "formal" / "tla"
SBY_DIR = ROOT / "rtl" / "formal" / "sby"
RTL_DIR = ROOT / "rtl" / "spinal" / "src"

# 커버리지 래칫 — 후-formal 1차 파도 착지 시 확정한다. 줄이는 편집은 실패.
_MIN_COVERED = 66  # 1차 파도 실측 (2026-08-24). 줄지 않는다


def fail(msg: str) -> None:
    print(f"lint_postformal: FAIL — {msg}", file=sys.stderr)
    sys.exit(1)


def model_guards(model: str) -> set:
    p = TLA_DIR / f"{model}.tla"
    if not p.is_file():
        fail(f"PROVES 가 참조한 모델 {model} 의 .tla 가 없다")
    m = re.search(r"AllGuards\s*==\s*\{([^}]*)\}", p.read_text(encoding="utf-8"))
    if not m:
        fail(f"{model}.tla 에서 AllGuards 를 찾지 못했다")
    return set(re.findall(r'"([A-Za-z_]+)"', m.group(1)))


def guard_kinds() -> dict:
    """GUARD-MAP 줄에서 (모델, 가드) -> kind."""
    kinds = {}
    pat = re.compile(r"//\s*GUARD-MAP:\s*([A-Za-z]+)\.([A-Za-z_]+)\s*->\s*(.+)$")
    for f in sorted(RTL_DIR.rglob("*.scala")):
        for line in f.read_text(encoding="utf-8").splitlines():
            m = pat.search(line)
            if not m:
                continue
            rhs = m.group(3).strip()
            kind = ("DELEGATED" if rhs.startswith("DELEGATED")
                    else "ENV" if rhs.startswith("ENV") else "CHECK")
            kinds[(m.group(1), m.group(2))] = kind
    return kinds


def main() -> None:
    if not SBY_DIR.is_dir():
        fail(f"{SBY_DIR} 가 없다 — 후-formal 미착지 상태로 이 lint 가 결선됐다면 결선이 이르다")

    proves = []  # (model, guard, file)
    pat = re.compile(r"#\s*PROVES:\s*([A-Za-z]+)\.([A-Za-z_]+)")
    sby_files = sorted(SBY_DIR.rglob("*.sby"))
    if not sby_files:
        fail("*.sby 가 하나도 없다 — 디렉터리만 있는 상태")
    for f in sby_files:
        for line in f.read_text(encoding="utf-8").splitlines():
            m = pat.search(line)
            if m:
                proves.append((m.group(1), m.group(2), f.relative_to(ROOT)))

    kinds = guard_kinds()
    known = {}
    for model, guard, f in proves:
        if model not in known:
            known[model] = model_guards(model)
        if guard not in known[model]:
            fail(f"{f} — PROVES 의 {model}.{guard} 는 AllGuards 에 없다")
        k = kinds.get((model, guard))
        if k is None:
            fail(f"{f} — {model}.{guard} 에 GUARD-MAP 줄이 없다 (주장 없는 증명)")
        if k != "CHECK":
            fail(f"{f} — {model}.{guard} 는 {k} 다. 증명 주장은 CHECK 에만 선다")

    covered = {(m, g) for m, g, _ in proves}
    checks = {k for k, v in kinds.items() if v == "CHECK"}
    if len(covered) < _MIN_COVERED:
        fail(f"커버리지 래칫 위반 — {len(covered)} < {_MIN_COVERED}")

    uncovered = sorted(checks - covered)
    print(
        f"lint_postformal: OK — PROVES {len(proves)}건 · CHECK {len(checks)} 중 "
        f"{len(covered)} 덮임 (래칫 {_MIN_COVERED}) · 참조 실재성 위반 0 · "
        f"sby {len(sby_files)}파일"
    )
    if uncovered:
        print(f"  미덮임 CHECK {len(uncovered)}건 (후속 파도 대상): "
              + " · ".join(f"{m}.{g}" for m, g in uncovered[:8])
              + (" …" if len(uncovered) > 8 else ""))


if __name__ == "__main__":
    main()
