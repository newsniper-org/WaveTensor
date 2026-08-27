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
    // GUARD-MAP: <Model>.<guard> -> STRUCTURAL(<근거 종류>) — <근거>

  TLA+ 모델의 가드 목록:
    AllGuards == {"g1", "g2", ...}

이 검사가 대조하는 것:
  (1) ENFORCED 목록의 각 모델에 대해, AllGuards 의 **모든** 가드가 rtl/spinal
      트리 어딘가의 GUARD-MAP 에 **정확히 한 번** 나타난다.
  (2) GUARD-MAP 이 참조하는 (모델, 가드) 가 실재한다 — 오타·삭제된 가드를
      계속 주장하는 매핑을 잡는다.
  (3) DELEGATED 대상 모듈명 · STRUCTURAL 근거 종류가 비어 있지 않다.
  (4) STRUCTURAL 건수 래칫 (`_MAX_STRUCTURAL`).

이 검사가 대조하지 **못하는** 것 (정직하게):
  매핑의 *참* — "이 신호가 정말 그 가드를 강제하는가"는 후-formal(같은 속성을
  RTL 에 다시 검사)이 답한다. 이 lint 는 주장의 전수성과 실재성만 잰다.

## 넷째 종류 STRUCTURAL — 왜 3분류로는 부족했는가 (2026-08-26, 3차 파도)

주장의 알맹이가 **포트·상태의 부재**인 가드가 셋 있다 (`Isolation.query_offpath` ·
`Isolation.fill_offpath` · `Decode.out_no_reason`). 부재는 elaborate 시점 사실이지
트레이스 속성이 아니라 후-formal 이 재지 못한다 — `lint_postformal` 은 그것을
`_STRUCTURAL` 표로 인정하고 **CHECK 분모에서 뺀다.**

그런데 2026-08-26 이전까지 그 셋의 GUARD-MAP RHS 는 여전히 CHECK 문면이었다.
결과: **두 lint 가 서로 다른 분모를 인쇄했다** — 여기는 `CHECK 77`, 저기는
`분모 74`. 같은 사실에 대해 두 기계가 다른 수를 내는 상태는, 이 저장소가
`notes-vacuity-detection.md` 에서 「게이트가 자기가 무엇을 세는지 모른다」로
이름 붙인 형태의 정확한 재발이다. 읽는 쪽은 큰 쪽(77)을 커버리지 분모로 믿는다.

그래서 분류를 넷으로 넓히고, **분류 규칙 자체를 이 파일의 `classify()` 한 곳에
둔다.** `lint_postformal` 이 그것을 import 한다 — 규칙 사본이 둘이면 언젠가
갈라지고, 갈라진 다음에는 어느 쪽이 옳은지 아무도 모른다.

STRUCTURAL 선언과 `lint_postformal._STRUCTURAL` 표의 **쌍방 대조**(선언↔표가
정확히 일대일)는 lint_postformal 쪽에 있다. 근거(생성 SV 포트 정규식)가 거기
살기 때문이고, 그래야 「선언만 있고 기계 근거가 없는 skip」이 막힌다.

### GUARD-MAP 주석을 고칠 때 — 줄 수를 바꾸지 마라

SpinalHDL 이 익명 `when` 을 `when_<파일>_l<줄번호>` 로 이름 짓고 후-formal
하네스가 그 이름을 하드코딩한다. 주석 한 줄을 **추가·삭제**하면 그 아래
`when` 들의 이름이 밀려 하네스 참조가 상수 0 wire 가 된다 (공허 2형).
2026-08-26 의 4분류 승격은 그래서 세 줄을 **같은 줄에서 치환**만 했다 —
`git diff --numstat` 이 파일마다 `1 1` 이고, `make rtl-gen` 뒤 생성 SV 18개가
전부 바이트 동일이라 재측정 비용이 0 이었다. 확인은
`python3 scripts/lint_generated_names.py`.

### 음성 시험 (2026-08-26 실측 — 격리 사본에서)

`cp -r rtl /tmp/nt3/rtl` + `scripts/lint_*.py` 를 두고 거기서 깨뜨린다.
이 파일의 신설 검사 셋이 각각 실패하는 것을 확인했다:
  · 넷째 STRUCTURAL 선언 추가 → 「구조 skip 래칫 위반」
  · `STRUCTURAL()` 빈 인자 → 「근거 종류이 비었다」
  · `STRUCTURAL(port-absence) — ` (근거 문면 없음) → 「근거 없는 skip 은
    미덮임과 구별되지 않는다」
그리고 **분모 갈림의 양성 관측**: 승격 한 건을 되돌리면 여기가 75 를,
lint_postformal 이 74 를 인쇄한다 — 승격 전의 상태가 정확히 그것이었다.

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
    # 2차 파도 (2026-08-23)
    "Payload",
    "MemOrder",
    "Platform",
]
# 미착지: NoLoss — 기계 전체 회계는 모듈이 아니라 합성 속성이다. RTL 대응물은
# 후-formal 이 조합 위에서 검사한다 (모듈 단위 GUARD-MAP 강제 부적합).
# 이 판단이 틀렸다고 판명되면 목록에 올리고 사유를 갱신하라.

_MIN_ENFORCED = 11  # 래칫 바닥 — 이 수 아래로 줄이는 편집은 실패한다

# 구조 skip 건수 래칫 — **상한**이다 (늘면 실패). 방향이 위 래칫과 반대인 것에
# 주의하라. STRUCTURAL 은 CHECK 분모를 비우는 방향이므로 늘리는 일은 반드시
# 이 파일을 고치는 명시적 서명을 거쳐야 한다. `lint_postformal._MAX_STRUCTURAL`
# 과 같은 값이어야 하고, 두 표의 일대일 대조가 그것을 강제한다.
_MAX_STRUCTURAL = 3

# 분류 이름 — 사본을 만들지 않기 위해 여기 한 벌만 둔다.
KINDS = ("CHECK", "DELEGATED", "ENV", "STRUCTURAL")


def classify(rhs: str) -> str:
    """GUARD-MAP RHS 문면 → 넷 중 하나.

    **이 저장소의 유일한 분류 규칙이다.** `lint_postformal` 이 이 함수를
    import 한다 — 규칙 사본이 둘이면 언젠가 갈라지고, 갈라진 뒤에는 두 lint 가
    같은 GUARD-MAP 에서 서로 다른 분모를 인쇄한다. 그것이 2026-08-26 이전의
    실제 상태였다 (CHECK 77 vs 분모 74).

    RHS 의 *접두*로만 판정한다. 본문 어딘가에 'STRUCTURAL' 이라는 낱말이 산문
    으로 나오는 것과 그것을 선언으로 세우는 것은 다르다 — 접두 규칙이 그 둘을
    가른다 (xlatestore.sby 의 머리 주석이 정확히 그 산문 사례였다).
    """
    for k in ("DELEGATED", "ENV", "STRUCTURAL"):
        if rhs.startswith(k):
            return k
    return "CHECK"


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
            kind = classify(rhs)
            # 괄호 인자를 요구하는 둘 — 비면 분류가 이름만 남고 내용이 없다.
            if kind in ("DELEGATED", "STRUCTURAL"):
                dm = re.match(rf"{kind}\(([^)]*)\)", rhs)
                what = "대상 모듈명" if kind == "DELEGATED" else "근거 종류"
                if not dm or not dm.group(1).strip():
                    fail(f"{f.relative_to(ROOT)}:{i} — {kind} {what}이 비었다 "
                         f"(형식: {kind}(<{what}>) — <근거>)")
                if kind == "STRUCTURAL" and not rhs[dm.end():].strip(" —-:"):
                    fail(f"{f.relative_to(ROOT)}:{i} — STRUCTURAL 선언에 근거 "
                         f"문면이 없다. 근거 없는 skip 은 미덮임과 구별되지 않는다")
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

    n = {k: sum(1 for e in entries if e[2] == k) for k in KINDS}

    # 구조 skip 래칫 — 상한. CHECK 분모를 비우는 방향이라 서명을 요구한다.
    if n["STRUCTURAL"] > _MAX_STRUCTURAL:
        locs = " · ".join(f"{m}.{g} @ {f}:{i}"
                          for m, g, k, f, i in entries if k == "STRUCTURAL")
        fail(f"구조 skip 래칫 위반 — STRUCTURAL {n['STRUCTURAL']} > "
             f"{_MAX_STRUCTURAL}. 구조 skip 남발은 CHECK 분모를 비우는 반대 "
             f"방향의 부정이다 ({locs})")

    total_guards = sum(len(model_guards(m)) for m in ENFORCED)
    # **두 lint 가 같은 분모를 인쇄한다** — 후-formal 이 증명으로 덮어야 하는
    # 가드 수는 CHECK 뿐이고, STRUCTURAL·DELEGATED·ENV 는 각각 다른 이유로
    # 트레이스 증명의 대상이 아니다. `lint_postformal` 의 「분모」와 이 수가
    # 어긋나면 둘 중 하나가 GUARD-MAP 을 잘못 읽고 있는 것이다.
    print(
        f"lint_guard_map: OK — ENFORCED {len(ENFORCED)}모델 · 가드 {total_guards} 전수 "
        f"(CHECK {n['CHECK']} / DELEGATED {n['DELEGATED']} / ENV {n['ENV']} / "
        f"STRUCTURAL {n['STRUCTURAL']}) · 후-formal 분모 {n['CHECK']} "
        f"(구조≤{_MAX_STRUCTURAL}) · 스캔 {len(scala_files)}파일 · 참조 실재성 위반 0"
    )
    if n["STRUCTURAL"]:
        print("  구조 skip (근거는 lint_postformal._STRUCTURAL 이 기계로 잰다):")
        for m, g, k, f, i in entries:
            if k == "STRUCTURAL":
                print(f"    {m}.{g} @ {f}:{i}")


if __name__ == "__main__":
    main()
