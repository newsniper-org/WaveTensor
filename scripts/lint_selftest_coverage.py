#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""게이트가 부르는 검사마다 **자기시험의 처분**이 등재돼 있는가.

## 왜 이 검사가 있는가

이 저장소가 같은 부류의 사건을 셋 겪었다. 셋 다 결함이 아니라 **그것을
가능하게 한 조용한 검사**가 사건이었다 (정본 §0.8 · §6.7).

  · **yosys bind 묵살** — `bind` 가 조용히 무시돼 공허 PASS. 세 팀이 적발
    했는데도 둘이 빠져나갔다. 사람 적발로는 못 막았고 `make rtl-postformal`
    의 HOLLOW 게이트가 유일한 그물이었다.
  · **sby 합성 태스크 회귀** — 모듈 태스크만 돌리면 그것을 인스턴스하는
    합성 증명이 조용히 깨진다.
  · **ARG 표기 우회** (2026-08-30) — 완전성 검사가 합법 표기 다섯으로
    우회됐다. 잡은 것은 상주 시험이 아니라 사람의 전수 검증이었다.

그래서 「검사가 무는지」를 기계가 재는 것 — 음성 시험 — 이 이 저장소의
규율이 됐다. 이 파일이 닫는 것은 그 다음 결이다: **어느 검사가 자기시험을
갖는지를 사람이 세고 있었다.** (오늘의 계수는 여기 적지 않는다. 이 검사가
매 실행 인쇄하는 숫자가 유일한 정본이고, 산문에 박은 숫자는 하루 만에
낡는다 — 바로 아래가 그 실측이다.)

세어 보는 일이 얼마나 빨리 낡는지는 실측으로 안다 (2026-08-30, 하루 안에):

  · 「`lint_section_refs` 에 18변이」 → 실제 **25행**
  · 「`lint_guide_derived_tables` 는 도입 이래 안 돌면서 OK 인쇄」 → **이미
    수리됨.** 매 실행 16변이를 먹인다
  · 훅 머리주석 「합계 약 3초」 → 실측 **약 20초**
  · 재고를 세려던 `scripts/[a-z_]+\\.py` 가 `lint_frag_total_m1_held.py`
    (이름 안의 숫자 `m1`)를 놓쳐 **16을 15로 셌다** — 오늘 잡은 ARG 사건과
    같은 형태를 그 측정기가 즉시 재현했다

⇒ 손으로 유지되는 재고는 반드시 뒤처진다. 이 검사는 재고를 **늘리지** 않고
  **누락이 실패가 되게** 한다 — `lint_toolchain_pins` 의 완전성 검사와
  똑같은 처방이고, 그것이 이 저장소가 이미 두 번 쓴 형태다
  (`lint_forbidden_terms.EXPECTED`, `lint_toolchain_pins.ARGS_NOT_COMPARED`
  — 「빈칸이 아니라 판정이다」).

## 이 검사가 재는 것

  (1) **정의역을 손으로 적지 않는다.** 훅 정본과 `.github/workflows/**` 를
      진입점으로 삼아 `make <타깃>` 을 Makefile 에서 **전개**하고, 그
      레시피가 부르는 `scripts/*.py` 를 전부 모은다.
  (2) 모인 스크립트마다 처분이 셋 중 하나여야 한다 —
        · **플래그형**  스크립트가 `--self-test` 를 받고, 게이트 호출 줄 중
                        하나가 실제로 그것을 넘긴다. **둘 다 기계로 잰다.**
        · **상시형**    `SELFTEST_ALWAYS` 등재. 플래그 없이 매 실행 돈다.
        · **미보유**    `SELFTEST_ABSENT` 또는 `NOT_A_CHECK` 에 **이유와
                        함께** 등재. 등재가 없으면 실패한다.
  (3) 플래그를 **지원하는데 게이트가 넘기지 않으면 실패.** 이것이 이 파일이
      사는 가장 큰 이유다 — `make lint` 에서 `--self-test` 줄 하나가 조용히
      사라지는 것이 정확히 이 저장소의 실패형이고, 그때 남는 것은
      「자기시험이 있다」는 기억뿐이다. 그 「넘긴다」는 **실행되는 줄**이어야
      한다: 주석 속 언급은 세지 않는다 (아래 ⚠️).
  (4) `SELFTEST_ABSENT` 에 등재된 스크립트가 실제로는 플래그를 지원하면
      실패 — **표가 낡았다**는 뜻이다. `NOT_A_CHECK` 도 같다: 「검사가
      아니다」와 「자기시험 플래그를 받는다」는 함께 설 수 없다.
  (5) 게이트가 부르는 스크립트 파일이 실재하지 않으면 실패.
  (6) 열거 수 **하한**. 0 건을 돌고 OK 를 인쇄하는 것이 이 부류의 전형이다.

⚠️ **(3) 이 주석 한 줄로 우회됐었다** (실측 2026-08-30, 이 파일 도입 당일).
Makefile 에서 실 호출 `… --self-test` 줄을 지우고 훅에 **실행되지 않는 주석**
`# 참고: … --self-test 로도 잰다` 한 줄을 넣으면 이 검사가 rc=0 으로
「플래그형 5」를 인쇄했다. 게이트가 자기시험을 하나도 안 돌리는데 초록이었다는
뜻이다. 원인은 열거가 원문을 그대로 훑은 것이고, **오차 방향이 갈래마다
반대**라는 것을 놓친 데 있었다 — 열거(정의역)에서 주석을 세면 상위집합이라
견디지만, 「호출이 있는가」에서 주석을 세면 **위음성**이다. ⇒ 자리마다
「코드인가」를 함께 세고, (3) 의 증거는 코드 자리에서만 얻는다. 변이 S8 이
그것을 상주로 잰다.

## 이 검사가 재지 **못하는** 것 — 반드시 함께 읽어라

  · **상시형이 실제로 매 실행 도는가**는 재지 못한다. 그것을 재려면 그
    스크립트를 실행해 자기시험 증거 문면을 확인해야 하고, 그러면 이 검사가
    다른 검사 전체를 실행하는 것이 된다. 대신 약한 대조 하나(자기시험 함수
    정의가 실재하는가)를 걸고 **못 잰다는 사실을 인쇄**한다. 「대조했더니
    같았다」와 「대조할 것이 없었다」는 다른 낱말이다. 그 약한 대조조차
    2026-08-30 까지 변이가 없어 실명시켜도 초록이었다 — 지금은 S9 가 문다.
  · **자기시험의 품질**은 재지 못한다. 변이 하나짜리 자기시험도 「가짐」이다.
    이름을 부풀리지 않는다 — 이것은 **처분의 등재**를 강제하는 검사이지
    「음성 시험이 충분하다」의 증명이 아니다.
  · **make 타깃 전개는 주석까지 센다** — 그쪽은 일부러 그대로 둔다. 훅·CI 의
    산문이 언급하는 타깃(`make hooks-install` · `make rtl-postformal`)이 그래서
    전개 목록에 든다. 그 오차는 **상위집합**이라 등재를 더 요구할 뿐 빠뜨리지
    않는다. 위 ⚠️ 의 갈래와 방향이 반대라는 것이 요점이다.
  · **주석 판정은 `#` 규칙 하나다** — 줄머리 또는 공백 뒤의 `#` 부터. 따옴표
    안의 `#` 까지 자르는 과잉 절단이 남는다. 그 방향은 **위양성**(있는 호출을
    못 보고 크게 실패)이라 견디는 쪽이다.
  · **`SELFTEST_ALWAYS` · `NOT_A_CHECK` 는 (3) 의 탈출구다.** 이름을 거기 넣으면
    분기 순서상 플래그 검사가 아예 돌지 않는다. 막는 것은 「이유를 적어라」와
    위 (4) 의 낡음 대조뿐이고, 그것이 이 두 표가 **짧게 유지돼야 하는** 이유다.

stdlib 전용. 직접 실행 가능:

    python3 scripts/lint_selftest_coverage.py
    python3 scripts/lint_selftest_coverage.py --self-test
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

MAKEFILE = REPO / "Makefile"
HOOK = REPO / "scripts" / "hooks" / "pre-commit"
CI_DIR = REPO / ".github" / "workflows"
SCRIPTS_DIR = REPO / "scripts"

TAG = "lint_selftest_coverage"

# 손-유지 **하한**이다. 손-유지 *정의역*(목록)은 금지지만 하한은 허용된다 —
# 방향이 반대이기 때문이다: 목록에서 빠뜨리면 침묵이고 하한에서 빠뜨리면 곧
# 실패다 (`lint_section_refs` ⑭ 가 적은 그대로). 실측으로만 올려라. 내리려면
# 무엇이 왜 게이트에서 빠졌는지를 함께 적어라.
MIN_GATE_SCRIPTS = 23  # 실측 2026-08-30 (+1: lint_truth_table_domain 신설) · 2026-09-26 +1: lint_ready_cone 신설 (파도 4 3B)
MIN_ENTRYPOINTS = 2  # 훅 정본 + 워크플로 최소 1편

# ── 상시형 ────────────────────────────────────────────────────────────────
# 플래그 없이 **매 실행 무조건** 자기시험이 도는 검사. 대가는 매 실행의 시간,
# 값은 「안 돌면서 OK 인쇄」가 **구조적으로 불가능**하다는 것이다.
SELFTEST_ALWAYS = {
    "lint_tautology.py": (
        "감사보다 **먼저** 양성 대조가 돈다. 그 파일의 주석: 「계수 0 은 "
        "『접힘이 없다』가 아니라 『보지 못했다』이고, 그 둘을 가르는 것이 "
        "이 순서다.」 `--self-test` 플래그도 있으나 게이트는 `--audit` 로 "
        "부르고 자기시험은 그와 무관하게 돈다."
    ),
    "lint_guide_derived_tables.py": (
        "`main()` 안에서 `_self_test()` 가 무조건 호출되고 `must_raise(...)` "
        "와 (5) 의 변이 표가 (3)·(5)·(6)·(7)·(8) 다섯 축에 변이를 먹인다 (수는 "
        "산문에 박지 않는다 — 위 머리말). 그 파일의 주석: 「(3) 이 *바로 그것이 "
        "없어서* 도입 "
        "이래 죽어 있었다. 자기 시험이 먹이지 않는 축은 수리해도 다시 "
        "죽는다.」 — 상시형이 된 계기가 그 사고다."
    ),
}

# ── 미보유 ────────────────────────────────────────────────────────────────
# **빈칸이 아니라 판정이다.** 여기 적힌 것은 「아직 안 했다」가 아니라 「왜
# 이번 파도가 아닌가」이고, 그 이유가 적혀 있어야 다음 사람이 순서를 다시
# 세우지 않는다. 새 게이트 검사를 들이면 위 둘 중 하나이거나 여기 등재하기
# 전까지 이 검사가 실패한다.
SELFTEST_ABSENT = {
    # 다음 파도 첫 후보 둘 — 값싸다(174/79줄)고 실측했다. (셋째였던 lint_guard_map 은
    # 2026-09-26 파도 4 검토 뒤 `--self-test` 를 얻어 이 표를 떠났다 — 플래그형.)
    "lint_isa7_topology.py": (
        "**다음 파도 첫 후보.** 정규식 5개 × `rtl/**.{scala,sv,v,svh,vh}`. "
        "ISA-7 은 부록 D 의 「증명됨」 속성이라 표기 하나를 못 읽으면 형상 "
        "파라미터가 인코딩에 새어도 초록이다. 174줄 — 값싸다."
    ),
    "lint_generated_names.py": (
        "**다음 파도 첫 후보.** SpinalHDL `when_<파일>_l<줄>` 추출이 빗나가면 "
        "검사할 이름이 줄어들 뿐이라 침묵이다. 79줄 — 값싸다."
    ),
    "lint_postformal.py": (
        "**부류로는 최고 위험, 그러나 이번 파도가 아니다.** 정규식 둘"
        "(`GUARD-MAP:` :938 · `# PROVES:` :957)이 후-formal 분모 **전체**를 "
        "만들고, 태그 하나가 파싱 실패하면 못 덮은 것이 분모에서 빠져 덮임률이 "
        "올라간다 — yosys bind 부류 그 자체다. 미루는 이유는 값이 아니라 "
        "픽스처다: 후-formal 증거층 전체(.sby + 증거 JSON + 신선도 해시)가 "
        "필요하고 그것은 **열린 과제 #21(증거층 자기 무결성)과 같은 픽스처**다. "
        "따로 하면 픽스처를 두 번 만든다. 2026-09-26 파도 4 검토 뒤: 가드 이름 문법 "
        "밖의 AllGuards 토큰 · 읽지 못한 GUARD-MAP · PROVES 선언은 이제 이 파일 단독 "
        "실행에서도 크게 운다(파서는 `lint_guard_map.split_all_guards` 공유 — 그 파서의 "
        "음성은 `lint_guard_map --self-test` ① 이 상주로 문다). 그러나 이 파일 쪽 "
        "호출 자리의 음성은 여전히 손 실측뿐이다."
    ),
    "lint_frag_total_m1_held.py": (
        "표기 표면은 최대다 — 머리주석이 스스로 과거 침묵 미검출을 자백한다"
        "(「the old heuristic only recognized case-arm writers」). 그러나 "
        "**대상이 legacy `rtl/*.v` 이고 그것은 SpinalHDL 전면 재구현으로 "
        "대체 중**이다. 사라질 코드를 겨냥한 시험은 전방 가치가 낮다."
    ),
    "lint_output_payload_hold.py": (
        "위 `lint_frag_total_m1_held.py` 와 같다 — 들여쓰기 휴리스틱이 "
        "「missed openers whose `begin` sits on a wrapped line」였다고 "
        "머리주석이 적는다. 대상이 legacy `rtl/*.v` 라 같은 판정."
    ),
    "lint_forbidden_terms.py": (
        "**처방이 자기시험이 아니다.** 실측 2026-08-30 으로 우회 넷을 확인했다 "
        "— `마이크로 코드` · `micro-code` · `μcode` · `ucode` 가 전부 통과한다. "
        "남은 구멍은 철자 바꿔 쓰기뿐이고 그 처방은 **정규식 확장**이다. "
        "(파일별 `EXPECTED` 래칫이 부작용으로 다른 우회로를 이미 닫는다: "
        "`counts[rel]` 이 면제 판정 **전에** 세어진다.) 별건으로 올린다."
    ),
    "lint_estimate_index.py": (
        "정규식 14로 표기 표면은 넓으나 판정 대부분이 **계수 대조**(머리 문면의 "
        "N vs 실제 행 수)라, 파싱이 빗나가면 대개 불일치로 **시끄럽게** 터진다. "
        "「우회가 침묵으로 나타나는가」가 이 표의 가르는 기준이고 이것은 아니다."
    ),
    "lint_synth_coverage.py": (
        "정규식 2~4, 대상 파일이 이름으로 고정, 판정이 계수 대조 — 위와 같은 "
        "이유로 중하."
    ),
    "lint_frag_slots_dual_run.py": "위 `lint_synth_coverage.py` 와 같다.",
    "lint_isa_tables_fresh.py": (
        "**표기 표면 0.** 19줄짜리 `gen_isa_tables.py --check` 래퍼이고 판정이 "
        "재생성 후 **바이트 diff** 다. 자기시험의 대상은 이 파일이 아니라 "
        "생성기다."
    ),
    "lint_gate_thresholds.py": (
        "정규식 **0**. BLAKE2b-512 로 판정기 파일을 통째로 묶으므로 우회 = 핀 "
        "표 편집이고 그것은 정의상 시끄럽다.\n"
        "        ⚠️ 다만 남는 결손이 있고 그것은 표기가 아니라 **정의역**이다 — "
        "핀 대상 목록이 **손-유지**다. 필요한 것은 변이 배터리가 아니라 "
        "`lint_section_refs` ⑭ 형태의 **정의역 폐쇄 시험**이라 처방이 다르다."
    ),
    "lint_known_defect_tests.py": (
        "정규식 0.\n"
        "        ⚠️ 남는 결손은 역시 정의역이다 — `REPO_ROOT.glob(\"test_*.py\")` "
        "가 **비재귀**이고 `rtl/sim/test_*.py` 가 실제로 그 밖에 있다. "
        "「빠뜨림이 침묵」인 형태지만 처방은 정의역 폐쇄 시험이다."
    ),
}

# ── 검사가 아닌 것 ────────────────────────────────────────────────────────
# 게이트가 부르지만 「조용히 통과할 수 있는가」라는 물음 자체가 성립하지 않는
# 스크립트. 산출물이 대조되는 구동기는 결과가 없으면 그 자리에서 터진다.
NOT_A_CHECK = {
    "run_cluster_dual.py": (
        "검사가 아니라 **시뮬 구동기**다 (`make test-cluster-both`). 판정은 "
        "이 스크립트의 침묵이 아니라 두 형상 실행 결과의 대조이고, 실행이 "
        "없으면 대조할 것이 없어 그 자리에서 실패한다."
    ),
}


# ── 진입점 → make 타깃 전개 → scripts/*.py ─────────────────────────────────
#
# 정의역을 **손으로 적지 않는다.** 손 목록은 반드시 뒤처지고, 뒤처진 목록은
# 「그건 게이트가 아니니까」로 읽혀 침묵이 된다. 진입점 둘만 구조로 못박는다:
# 훅 정본(그 경로는 `make hooks-check` 가 이미 집행한다)과 워크플로 디렉터리.

_TARGET = re.compile(r"^([A-Za-z0-9_.%/+-]+)\s*:(?!=)\s*(.*)$")
_SCRIPT = re.compile(
    r"scripts/([A-Za-z0-9_.-]+\.py)((?:[ \t]+--?[A-Za-z0-9_=-]+)*)"
)
_MAKE_CALL = re.compile(
    r"(?:\$\(MAKE\)|\bmake)\s+((?:--?\S+\s+)*)([a-zA-Z][A-Za-z0-9_.-]*)"
)


# 주석 한 줄은 아무것도 실행하지 않는다. 훅(sh) · 워크플로(YAML) · Makefile
# 레시피(sh) 셋 다 `#` 규칙이 같아 하나로 잰다: **줄머리 또는 공백 뒤의 `#`
# 부터가 주석이다.**
_COMMENT_START = re.compile(r"(?:^|\s)#")


def _code_end(line: str) -> int:
    """그 줄에서 주석이 시작되기 **전까지**의 길이."""
    m = _COMMENT_START.search(line)
    return len(line) if m is None else m.start()


def parse_makefile(path: Path) -> dict[str, tuple[list[str], list[str]]]:
    """`{타깃: (선행조건, 레시피 줄들)}`. 레시피는 TAB 으로 시작하는 줄이다.

    ⚠️ **빈 줄과 주석 줄은 레시피를 끝내지 않는다.** GNU make 실측
    (2026-08-30): `demo:` → `\\t@echo A` → `# 주석` → 빈 줄 → `\\t@echo B` 를
    돌리면 **A 와 B 를 둘 다** 인쇄한다. 옛 판은 TAB 이 아닌 줄을 만나면
    `_TARGET` 매칭 실패 시 무조건 `cur = None` 이라 거기서 수집을 끝냈고,
    **그 뒤의 모든 스크립트 호출 줄을 정의역에서 조용히 떨어뜨렸다.**
    (실증: `lint:` 레시피 한 줄을 주석 줄로 바꿨더니 그 뒤 두 줄이 함께
    사라져 엉뚱한 두 번째 오류가 났다.) 오차 방향이 **과소 열거 = 침묵**이라
    이 파일이 겨냥한 부류 그 자체다 — 정의역 폐쇄 D4 가 상주로 잰다.
    """
    out: dict[str, tuple[list[str], list[str]]] = {}
    cur: str | None = None
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.startswith("\t"):
            if cur is not None:
                out[cur][1].append(raw)
            continue
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue  # GNU make: 레시피를 끝내지 않는다 (위 실측)
        m = _TARGET.match(raw)
        if m:
            cur = m.group(1)
            out.setdefault(cur, (m.group(2).split(), []))
        else:
            cur = None
    return out


def entrypoints() -> list[Path]:
    eps = [HOOK] if HOOK.is_file() else []
    if CI_DIR.is_dir():
        eps += sorted(
            p for p in CI_DIR.rglob("*")
            if p.suffix in (".yml", ".yaml") and p.is_file()
        )
    return eps


def gate_domain() -> tuple[dict[str, list[tuple[str, str, bool]]], list[str]]:
    """`{스크립트명: [(출처, 호출 줄 조각, 코드인가)]}` 과 전개된 make 타깃 목록.

    셋째 칸이 **왜 있는가**: 주석 한 줄이 (3) 「게이트가 플래그를 넘긴다」를
    만족시켜 자기시험을 하나도 안 돌리고 초록이 됐다 (실측 2026-08-30, 위
    docstring ⚠️). 열거 자체는 여전히 원문 전체를 훑는다 — 그쪽 오차는
    상위집합이라 견디는 방향이고, 좁히면 산문에만 남은 이름이 정의역에서
    조용히 빠진다. **판정 갈래마다 안전한 방향이 반대**라서 자리마다 코드
    여부를 들고 다니고, 갈래에서 고른다.
    """
    targets = parse_makefile(MAKEFILE) if MAKEFILE.is_file() else {}
    found: dict[str, list[tuple[str, str, bool]]] = {}
    expanded: list[str] = []
    seen: set[str] = set()

    def scan(text: str, origin: str) -> None:
        for line in text.splitlines():
            cut = _code_end(line)
            for m in _SCRIPT.finditer(line):
                found.setdefault(m.group(1), []).append(
                    (origin, m.group(0), m.end() <= cut)
                )
        # make 타깃 전개는 일부러 **원문 전체**를 본다 (주석 속 `make …` 포함).
        # 오차가 상위집합이라 등재를 더 요구할 뿐 빠뜨리지 않는다.
        for m in _MAKE_CALL.finditer(text):
            t = m.group(2)
            if t in targets and t not in seen:
                seen.add(t)
                expanded.append(t)
                prereq, recipe = targets[t]
                for p in prereq:
                    if p in targets and p not in seen:
                        seen.add(p)
                        expanded.append(p)
                        scan("\n".join(targets[p][1]), f"Makefile:{p}")
                scan("\n".join(recipe), f"Makefile:{t}")

    for ep in entrypoints():
        scan(ep.read_text(encoding="utf-8"),
             str(ep.relative_to(REPO)))
    return found, expanded


def supports_flag(path: Path) -> bool:
    """그 스크립트가 `--self-test` 를 **받는가**.

    토큰 대조다. argparse 든 `sys.argv` 든 이 리터럴이 파일에 있어야 플래그가
    성립하므로 표면이 좁고, 넓히면(호출 그래프 분석) 이 검사 자신이 파서가
    되어 같은 부류의 사각을 새로 만든다.
    """
    try:
        return '"--self-test"' in path.read_text(encoding="utf-8")
    except OSError:
        return False


def has_selftest_fn(path: Path) -> bool:
    try:
        return bool(re.search(r"^def _?self_test\(", path.read_text(encoding="utf-8"),
                              re.M))
    except OSError:
        return False


def run(quiet: bool = False) -> int:
    problems: list[str] = []

    for p in (MAKEFILE, HOOK):
        if not p.is_file():
            problems.append(f"진입점 부재: {p.relative_to(REPO)}")
    eps = entrypoints()
    if len(eps) < MIN_ENTRYPOINTS:
        # 진입점이 사라지면 이 검사는 **아무것도 재지 않으면서** 통과한다.
        problems.append(
            f"진입점 {len(eps)}개 < 하한 {MIN_ENTRYPOINTS} — 이 검사가 잰 것이 "
            f"0 이다. 정의역을 확인하라 (훅 정본 + .github/workflows)"
        )
    if problems:
        for p in problems:
            print(f"{TAG}: FAIL — {p}", file=sys.stderr)
        return 1

    found, expanded = gate_domain()

    if len(found) < MIN_GATE_SCRIPTS:
        problems.append(
            f"게이트 스크립트 {len(found)}개 < 하한 {MIN_GATE_SCRIPTS} — "
            f"검사가 게이트에서 빠졌거나 열거가 깨졌다. 어느 쪽이든 "
            f"**침묵으로 지나갈 일이 아니다**"
        )

    counts = {"플래그형": 0, "상시형": 0, "미보유": 0, "비검사": 0}
    for name in sorted(found):
        path = SCRIPTS_DIR / name
        sites = found[name]
        # **코드 자리에서만** 증거를 얻는다 — 주석은 아무것도 실행하지 않는다.
        flagged = [o for o, frag, code in sites if "--self-test" in frag and code]
        commented = sorted({o for o, frag, code in sites
                            if "--self-test" in frag and not code})

        if not path.is_file():
            problems.append(
                f"게이트가 없는 스크립트를 부른다: `{name}` "
                f"({', '.join(sorted({o for o, _, _ in sites}))})"
            )
            continue

        if name in NOT_A_CHECK:
            counts["비검사"] += 1
            continue

        if name in SELFTEST_ALWAYS:
            counts["상시형"] += 1
            if not has_selftest_fn(path):
                problems.append(
                    f"표가 낡았다: `{name}` 이 SELFTEST_ALWAYS 에 등재됐는데 "
                    f"자기시험 함수 정의가 없다"
                )
            continue

        if supports_flag(path):
            counts["플래그형"] += 1
            if not flagged:
                problems.append(
                    f"자기시험이 게이트에서 빠졌다: `{name}` 은 `--self-test` "
                    f"를 받는데 게이트 호출 줄 중 그것을 넘기는 것이 없다 — "
                    f"자기시험이 있다는 **기억**만 남고 실제로는 아무도 "
                    f"돌리지 않는다. 호출처: "
                    f"{', '.join(sorted({o for o, _, _ in sites}))}"
                    + (
                        f"\n      ⚠ `--self-test` 언급이 **주석 안에만** 있다"
                        f"({', '.join(commented)}) — 주석은 아무것도 실행하지 "
                        f"않는다. 실 호출 줄을 넣어라"
                        if commented else ""
                    )
                )
            continue

        if name in SELFTEST_ABSENT:
            counts["미보유"] += 1
            continue

        problems.append(
            f"자기시험 처분 미등재: `{name}` — 자기시험을 붙이거나, "
            f"**이유와 함께** SELFTEST_ABSENT(또는 NOT_A_CHECK) 에 넣어라. "
            f"빈칸이 아니라 판정이어야 한다"
        )

    # 표가 실물보다 넓어지는 방향도 침묵이다 — 등재는 남아 있는데 그 스크립트가
    # 게이트에서 사라지면 「미보유 13」이라는 숫자가 거짓말을 하기 시작한다.
    for table, label in ((SELFTEST_ABSENT, "SELFTEST_ABSENT"),
                         (SELFTEST_ALWAYS, "SELFTEST_ALWAYS"),
                         (NOT_A_CHECK, "NOT_A_CHECK")):
        for name in sorted(table):
            if name not in found:
                problems.append(
                    f"표가 낡았다: `{name}` 이 {label} 에 등재됐는데 게이트가 "
                    f"부르지 않는다 — 등재를 지우거나 게이트를 고쳐라"
                )
            elif table is SELFTEST_ABSENT and supports_flag(SCRIPTS_DIR / name):
                problems.append(
                    f"표가 낡았다: `{name}` 이 SELFTEST_ABSENT 인데 실제로는 "
                    f"`--self-test` 를 받는다 — 「미보유」가 아니다. 등재를 "
                    f"지우고 게이트에 그 줄을 넣어라"
                )
            # `NOT_A_CHECK` 은 (3) 의 **탈출구**다 — 이름을 넣으면 분기 순서상
            # 플래그 검사가 아예 돌지 않는다. 그 탈출구에 낡음 대조를 건다:
            # 「검사가 아니다」와 「자기시험 플래그를 받는다」는 함께 설 수 없다.
            elif table is NOT_A_CHECK and supports_flag(SCRIPTS_DIR / name):
                problems.append(
                    f"표가 낡았다: `{name}` 이 NOT_A_CHECK 인데 `--self-test` 를 "
                    f"받는다 — 「검사가 아니다」와 「자기시험이 있다」는 함께 설 "
                    f"수 없다. 등재를 지우고 게이트에 그 줄을 넣어라"
                )

    if problems:
        print(f"{TAG}: FAIL — 자기시험 처분이 어긋났다", file=sys.stderr)
        for p in problems:
            print(f"  · {p}", file=sys.stderr)
        print(
            "\n  이 검사가 막는 것은 「자기시험이 없다」가 아니라 **「없는 줄도\n"
            "  모른다」**다. 검사가 무는지를 사람이 기억으로 유지하면 반드시\n"
            "  뒤처진다 (실측 2026-08-30: 하루 만에 전제 넷이 낡았다).",
            file=sys.stderr,
        )
        return 1

    if not quiet:
        print(
            f"{TAG}: OK — 게이트 스크립트 {len(found)}개"
            f"(하한 {MIN_GATE_SCRIPTS}) 전부 처분 등재 — "
            f"플래그형 {counts['플래그형']} · 상시형 {counts['상시형']} · "
            f"미보유 {counts['미보유']} · 비검사 {counts['비검사']}"
        )
        print(f"  · 진입점 {len(eps)}편 → make 타깃 {len(expanded)}개 전개: "
              f"{' '.join(sorted(expanded))}")
        print("  · ⚠ **상시형은 기계로 못 잰다** — 「매 실행 돈다」는 등재를 "
              "이 검사가 확인하는 것은 자기시험 함수의 실재뿐이다. "
              "「대조했더니 같았다」가 아니라 「대조할 것이 없었다」에 가깝다.")
        print("  · ⚠ 이것은 **처분의 등재**를 강제하는 검사이지 「음성 시험이 "
              "충분하다」의 증명이 아니다 — 변이 하나짜리도 「가짐」으로 센다.")
    return 0


# ═══════════════════════════════════════════════════════════════════════════
# 음성 시험 — 이 검사 **자신도 파서다**
#
# 2026-08-30 에 재고를 세려던 `scripts/[a-z_]+\.py` 가 `lint_frag_total_m1_held`
# 를 놓쳐 16을 15로 셌다. 그러므로 이 파일의 열거도 조용히 빗나갈 수 있고,
# 빗나가면 「전부 등재됐다」는 초록이 거짓이 된다.
#
# **재귀는 여기서 멈춘다.** 아래가 이 파서의 전 정의역이다 — 열거가 실물을
# 읽는가(S1·S3·S5·S13·D4) · 미등재가 실패가 되는가(S2·S6) · 표가 낡으면 우는가
# (S4·S7·S9·S10) · 주석이 호출로 세어지지 않는가(S8) · 정의역이 무너지면 우는가
# (S11·S12) · 그리고 잴 것이 있는가(D1–D4). 「검사를 검사하는 검사」를 하나 더
# 세우지 않는 이유는 그 층이 같은 부류의 사각을 하나 더 만들 뿐이기 때문이다.
#
# ⚠️ 도입 당일(2026-08-30) 전수 검증이 **미덮임 갈래 넷**을 실측으로 찾았다.
# 넷 다 「본 검사 rc=0 · 자기시험 rc=0」으로 조용했다 —
#   · 훅에 심은 **미끼 주석 한 줄**로 (3) 이 만족됐다            → S8
#   · `has_selftest_fn` 을 `return True` 로 실명시켜도 초록      → S9
#   · 진입점 하한 분기·진입점 부재 검사를 들어내도 초록          → S11 · S12
#   · `for p in prereq:`(선행조건 전개)를 들어내도 초록          → S13
# 「변이 하나짜리도 가짐으로 센다」는 이 파일의 고백이 자기 자신에게 먼저
# 적용됐던 셈이다. 새 판정 분기를 넣거든 변이를 **같은 커밋에서** 넣어라.
# ═══════════════════════════════════════════════════════════════════════════

_MIN_MUTATIONS = 13
_MIN_EXPANDED = 3


class _MutationMiss(RuntimeError):
    """변이 지점을 찾지 못했다 — **skip 이 아니라 실패다.**"""


_FIX_SUBTREES = ("scripts", ".github")
_FIX_FILES = ("Makefile",)


def _build_fixture(root: Path) -> Path:
    base = root / "repo"
    for sub in _FIX_SUBTREES:
        src = REPO / sub
        if not src.is_dir():
            raise _MutationMiss(f"픽스처 정의역 부재: {sub}")
        shutil.copytree(src, base / sub, symlinks=True,
                        ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    for f in _FIX_FILES:
        src = REPO / f
        if not src.is_file():
            raise _MutationMiss(f"픽스처 정의역 부재: {f}")
        shutil.copy2(src, base / f)
    return base


def _run_fixture(base: Path) -> tuple[int, str]:
    me = Path(__file__).resolve().name
    r = subprocess.run([sys.executable, str(base / "scripts" / me)],
                       capture_output=True, text=True)
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def _sub(path: Path, before: str, after: str) -> None:
    text = path.read_text(encoding="utf-8")
    if before not in text:
        raise _MutationMiss(f"{path.name}: 변이 지점 부재 — /{before[:64]}/")
    path.write_text(text.replace(before, after, 1), encoding="utf-8")


def _append(path: Path, extra: str) -> None:
    path.write_text(path.read_text(encoding="utf-8") + extra, encoding="utf-8")


_PROBE_SRC = "#!/usr/bin/env python3\nimport sys\nsys.exit(0)\n"


def _mutations() -> list[tuple[str, str, object, tuple[str, ...]]]:
    """변이 자리는 **기준 실행이 돌려준 실제 자리**에서 고른다.

    리터럴을 박으면 문면이 옮겨간 날 「아무것도 치환 못 함 = 변화 없음 =
    잡지 못함」으로 조용히 무효가 된다.
    """
    found, _ = gate_domain()
    mk_text = MAKEFILE.read_text(encoding="utf-8")
    mk_targets = parse_makefile(MAKEFILE)

    # 실제로 `--self-test` 가 넘어가는 첫 줄 — Makefile 안에 있는 것으로.
    victim = None
    for name in sorted(found):
        for origin, frag, code in found[name]:
            if "--self-test" in frag and code and origin.startswith("Makefile:"):
                line = next(
                    (ln for ln in mk_text.splitlines()
                     if frag in ln and "--self-test" in ln), None)
                if line:
                    victim = (name, line, frag)
                    break
        if victim:
            break
    if victim is None:
        raise _MutationMiss("Makefile 에 `--self-test` 호출 줄이 없다")
    v_name, v_line, v_frag = victim

    # 미보유 표에 등재된 스크립트 하나 — 실재하고 게이트가 부르는 것으로.
    absent = next((n for n in sorted(SELFTEST_ABSENT)
                   if n in found and (SCRIPTS_DIR / n).is_file()), None)
    if absent is None:
        raise _MutationMiss("SELFTEST_ABSENT 중 게이트가 부르는 실재 파일이 없다")

    # `lint:` 레시피 줄 여럿 — 열거 수 하한을 깨는 데 쓴다.
    lint_lines = [ln for ln in mk_text.splitlines()
                  if ln.startswith("\t") and "scripts/lint_" in ln]
    if len(lint_lines) < 5:
        raise _MutationMiss("Makefile 레시피의 lint 호출 줄이 너무 적다")

    # 상시형 등재 중 자기시험 함수 정의를 실제로 가진 첫 것 — S9 의 닻.
    always = next((n for n in sorted(SELFTEST_ALWAYS)
                   if n in found and (SCRIPTS_DIR / n).is_file()
                   and has_selftest_fn(SCRIPTS_DIR / n)), None)
    if always is None:
        raise _MutationMiss("SELFTEST_ALWAYS 중 자기시험 함수를 가진 것이 없다")
    always_def = next(
        ln for ln in (SCRIPTS_DIR / always).read_text(encoding="utf-8").splitlines()
        if re.match(r"^def _?self_test\(", ln)
    )

    # S13 의 닻 — `lint_lines[0]` 을 레시피로 가진 타깃과 그 타깃 줄.
    host = next((t for t, (_pre, rec) in mk_targets.items()
                 if lint_lines[0] in rec), None)
    if host is None:
        raise _MutationMiss("lint 호출 줄을 레시피로 가진 타깃을 찾지 못했다")
    host_line = next(
        (ln for ln in mk_text.splitlines()
         if _TARGET.match(ln) and _TARGET.match(ln).group(1) == host), None)
    if host_line is None:
        raise _MutationMiss(f"`{host}:` 타깃 줄을 찾지 못했다")

    def mk(b: Path) -> Path:
        return b / "Makefile"

    def s1(b: Path) -> None:
        _sub(mk(b), v_line + "\n", "")

    def s2(b: Path) -> None:
        probe = "\tpython3 $(CURDIR)/scripts/lint_zz_selftest_probe.py\n"
        _sub(mk(b), lint_lines[0] + "\n", lint_lines[0] + "\n" + probe)
        (b / "scripts" / "lint_zz_selftest_probe.py").write_text(
            "#!/usr/bin/env python3\nimport sys\nsys.exit(0)\n",
            encoding="utf-8")

    # S3 은 **하한 분기를 격리한다.** 처음에는 `lint:` 레시피 줄 여섯을 지워
    # 계수를 떨어뜨렸는데, 그러면 미보유 표의 등재가 통째로 고아가 되어
    # 「표가 낡았다」가 먼저 울었다 — 하한 코드를 통째로 들어내도 다른 이유로
    # 실패하니 이 변이가 하한을 재고 있지 않았다는 뜻이다 (실측으로 잡았다).
    # 그래서 하한 상수 쪽을 올린다. 줄 제거는 S7 이 따로 잰다.
    def s3(b: Path) -> None:
        f = b / "scripts" / Path(__file__).name
        _sub(f, f"MIN_GATE_SCRIPTS = {MIN_GATE_SCRIPTS}",
             f"MIN_GATE_SCRIPTS = {len(found) + 5}")

    def s7(b: Path) -> None:
        for ln in lint_lines[:6]:
            _sub(mk(b), ln + "\n", "")

    def s4(b: Path) -> None:
        f = b / "scripts" / absent
        f.write_text(f.read_text(encoding="utf-8")
                     + '\n# probe: "--self-test"\n', encoding="utf-8")

    def s5(b: Path) -> None:
        (b / "scripts" / absent).unlink()

    def s6(b: Path) -> None:
        probe = "\tpython3 $(CURDIR)/scripts/lint_zz_selftest_probe.py\n"
        _sub(mk(b), lint_lines[0] + "\n", lint_lines[0] + "\n" + probe)
        # 파일을 만들지 않는다 — 게이트가 없는 스크립트를 부르는 형태.

    # ── S8 : 미끼 주석. **이 파일이 도입 당일 실제로 뚫린 자리다.** ─────────
    # 실 호출 줄을 지우고 훅에 실행되지 않는 주석 한 줄을 심으면, 열거가
    # 원문을 그대로 훑는 동안 (3) 이 만족돼 rc=0 이 됐다. S1 은 줄만 지울 뿐
    # 미끼를 심지 않아 이 갈래를 재지 못했다.
    def s8(b: Path) -> None:
        _sub(mk(b), v_line + "\n", "")
        _append(b / HOOK.relative_to(REPO),
                f"\n# 참고: 이 축은 `{v_frag}` 로도 잰다\n")

    # ── S9 : 상시형의 유일한 약한 대조를 실제로 문다. ────────────────────────
    # `has_selftest_fn` 을 `return True` 로 실명시켜도 자기시험이 초록이었다.
    def s9(b: Path) -> None:
        f = b / "scripts" / always
        _sub(f, always_def, always_def.replace("def ", "def zz_disabled_", 1))

    # ── S10 : `NOT_A_CHECK` 탈출구의 낡음 대조. ─────────────────────────────
    def s10(b: Path) -> None:
        f = b / "scripts" / Path(__file__).name
        _sub(f, "NOT_A_CHECK = {\n",
             "NOT_A_CHECK = {\n    %r: \"wt-selftest probe\",\n" % v_name)

    # ── S11 · S12 : 정의역이 무너지면 이 검사는 **아무것도 재지 않으면서**
    #                통과한다. 하한 분기와 진입점 부재 검사를 각각 문다.
    def s11(b: Path) -> None:
        n = 0
        for p in sorted((b / CI_DIR.relative_to(REPO)).rglob("*")):
            if p.suffix in (".yml", ".yaml") and p.is_file():
                p.unlink()
                n += 1
        if n == 0:
            raise _MutationMiss("픽스처에 워크플로가 없다")

    def s12(b: Path) -> None:
        (b / HOOK.relative_to(REPO)).unlink()

    # ── S13 : 선행조건 전개. 오늘 실 트리에서는 선행조건으로만 닿는 스크립트가
    #          0건이라 `for p in prereq:` 를 통째로 들어내도 초록이었다. 그
    #          갈래를 합성으로 만든다 — 미등재 검사를 **선행조건 타깃 안에만**
    #          두고, 전개가 살아 있어야만 보이게 한다.
    _PRQ_TGT = "lint-zz-prereq-probe"
    _PRQ_PY = "lint_zz_prereq_probe.py"

    def s13(b: Path) -> None:
        _sub(mk(b), host_line + "\n",
             f"{host}: {_PRQ_TGT} " + " ".join(mk_targets[host][0]) + "\n")
        _append(mk(b),
                f"\n{_PRQ_TGT}:\n\tpython3 $(CURDIR)/scripts/{_PRQ_PY}\n")
        (b / "scripts" / _PRQ_PY).write_text(_PROBE_SRC, encoding="utf-8")

    return [
        ("S1", f"게이트에서 `--self-test` 줄 제거 ({v_name})", s1,
         ("자기시험이 게이트에서 빠졌다", f"`{v_name}`")),
        ("S2", "미등재 새 게이트 검사 투입", s2,
         ("자기시험 처분 미등재", "`lint_zz_selftest_probe.py`")),
        ("S3", "열거 수를 하한 아래로 (하한 분기 격리)", s3,
         ("< 하한", "침묵으로 지나갈 일이 아니다")),
        ("S4", f"미보유 등재가 낡음 ({absent} 이 플래그를 받게 됨)", s4,
         ("표가 낡았다", f"`{absent}`", "SELFTEST_ABSENT 인데")),
        ("S5", f"게이트가 부르는 파일이 사라짐 ({absent})", s5,
         ("게이트가 없는 스크립트를 부른다", f"`{absent}`")),
        ("S6", "게이트가 실재하지 않는 스크립트를 부름", s6,
         ("게이트가 없는 스크립트를 부른다",
          "`lint_zz_selftest_probe.py`")),
        # 표가 실물보다 **넓어지는** 방향. 검사가 게이트에서 조용히 빠지면
        # 「미보유 13」이라는 숫자가 그때부터 거짓말을 한다.
        ("S7", "게이트에서 검사 줄 여섯 제거 (등재가 고아가 된다)", s7,
         ("표가 낡았다", "게이트가 부르지 않는다")),
        ("S8", f"미끼 주석 한 줄이 (3) 을 만족시키지 못한다 ({v_name})", s8,
         ("자기시험이 게이트에서 빠졌다", f"`{v_name}`", "주석 안에만")),
        ("S9", f"상시형 등재가 낡음 ({always} 의 자기시험 함수 정의 소실)", s9,
         ("표가 낡았다", f"`{always}`", "자기시험 함수 정의가 없다")),
        ("S10", f"NOT_A_CHECK 탈출구가 낡음 ({v_name} 을 비검사로 등재)", s10,
         ("표가 낡았다", f"`{v_name}`", "NOT_A_CHECK 인데")),
        ("S11", "진입점이 하한 아래로 (워크플로 전멸)", s11,
         (f"진입점 1개 < 하한 {MIN_ENTRYPOINTS}", "이 검사가 잰 것이 0 이다")),
        ("S12", "훅 정본 부재", s12,
         ("진입점 부재", str(HOOK.relative_to(REPO)))),
        ("S13", f"선행조건으로만 닿는 미등재 검사 ({_PRQ_TGT})", s13,
         ("자기시험 처분 미등재", f"`{_PRQ_PY}`")),
    ]


def self_test() -> int:
    print(f"{TAG}: 음성 시험 — 격리 사본(/tmp)에서 변이 주입")
    rows: list[tuple[bool, str, str]] = []
    ok = True

    try:
        muts = _mutations()
    except _MutationMiss as e:
        print(f"  ✗ 변이표를 짓지 못했다 — {e}", file=sys.stderr)
        print("음성 시험 불통과 (변이 0건은 통과가 아니다)", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory(prefix="wt-stcov-neg-") as td:
        root = Path(td)

        # ── ⓪ 정의역 폐쇄 — 변이보다 **먼저**. ─────────────────────────────
        try:
            base0 = _build_fixture(root / "d0")
        except _MutationMiss as e:
            print(f"  ✗ D1 {e}", file=sys.stderr)
            return 1
        found, expanded = gate_domain()
        d1 = len(entrypoints()) >= MIN_ENTRYPOINTS
        rows.append((d1, "D1", f"진입점 {len(entrypoints())}편 ≥ 하한 "
                                f"{MIN_ENTRYPOINTS} (훅 정본 + 워크플로)"))
        d2 = len(expanded) >= _MIN_EXPANDED and len(found) >= MIN_GATE_SCRIPTS
        rows.append((d2, "D2", f"make 타깃 {len(expanded)}개 전개 → 스크립트 "
                                f"{len(found)}개 — **열거가 실물을 읽는다**"))
        d3 = len(muts) >= _MIN_MUTATIONS
        rows.append((d3, "D3", f"변이 {len(muts)}건 ≥ 하한 {_MIN_MUTATIONS} "
                                f"(0건은 통과가 아니다)"))

        # ── D4 : 레시피 중간의 주석·빈 줄이 열거를 **줄이지 않는다.** ────────
        # GNU make 실측(2026-08-30): `demo:` → `\t@echo A` → `# 주석` → 빈 줄
        # → `\t@echo B` 가 A 와 B 를 **둘 다** 인쇄한다. 옛 파서는 거기서
        # 수집을 끝내 뒤의 호출 줄을 전부 조용히 떨어뜨렸다.
        # 변이가 아니라 **양성 대조**인 이유: 이 결함은 「못 잡는다」가 아니라
        # 「덜 센다」라 실패 문면이 아니라 계수로만 드러나고, 오차 방향이
        # 침묵이라 rc 로는 잡히지 않는다.
        mk_lines = MAKEFILE.read_text(encoding="utf-8").splitlines()
        anchor = next((ln for ln in mk_lines
                       if ln.startswith("\t") and "scripts/lint_" in ln), None)
        if anchor is None:
            rows.append((False, "D4", "Makefile 에 레시피 호출 줄이 없다"))
            d4 = False
        else:
            k = mk_lines.index(anchor)
            probe_mk = root / "probe.mk"
            probe_mk.write_text(
                "\n".join(mk_lines[:k + 1]
                          + ["# wt-selftest: 레시피 중간 주석", ""]
                          + mk_lines[k + 1:]) + "\n",
                encoding="utf-8")
            base_t = parse_makefile(MAKEFILE)
            probe_t = parse_makefile(probe_mk)
            d4 = probe_t == base_t
            n_rec = sum(len(r) for _p, r in base_t.values())
            n_probe = sum(len(r) for _p, r in probe_t.values())
            rows.append((d4, "D4",
                         f"레시피 중간 주석·빈 줄이 열거를 줄이지 않는다 — "
                         f"타깃 {len(base_t)} / 레시피 줄 {n_rec} → {n_probe} "
                         f"(GNU make 실측 일치)"))

        if not (d1 and d2 and d3 and d4):
            for good, tag, text in rows:
                print(f"  {'✓' if good else '✗'} {tag} {text}")
            print("음성 시험 불통과 — 정의역 폐쇄가 깨졌다 (변이는 걸지 않았다)",
                  file=sys.stderr)
            return 1

        rc, out = _run_fixture(base0)
        if rc != 0:
            for good, tag, text in rows:
                print(f"  {'✓' if good else '✗'} {tag} {text}")
            print("  ✗ S0 대조군 — **변이 없는 사본이 이미 실패한다**")
            print(out)
            print("음성 시험 불통과 — 기준이 깨진 상태에서는 모든 변이가 "
                  "엉뚱한 이유로 운다", file=sys.stderr)
            return 1
        rows.append((True, "S0", "대조군 — 변이 없는 사본은 통과한다 (rc=0)"))

        for i, (tag, desc, apply, expect) in enumerate(muts):
            base = _build_fixture(root / f"m{i}")
            try:
                apply(base)  # type: ignore[operator]
            except _MutationMiss as e:
                rows.append((False, tag, f"{desc} — 변이 지점을 찾지 못했다: {e}"))
                ok = False
                continue
            rc, out = _run_fixture(base)
            if rc == 0:
                rows.append((False, tag,
                             f"{desc} — **검사가 잡지 못했다** (공허한 검사다)"))
                ok = False
                continue
            miss = [s for s in expect if s not in out]
            if miss:
                rows.append((False, tag,
                             f"{desc} — 실패는 했으나 **다른 이유로** 울었다: "
                             f"기대 문면 부재 {miss}"))
                ok = False
                continue
            rows.append((True, tag, f"{desc} — FAIL 확인"))

    for good, tag, text in rows:
        print(f"  {'✓' if good else '✗'} {tag} {text}")
    if not ok:
        print(f"음성 시험 불통과 — {sum(1 for g, _, _ in rows if not g)}건이 "
              f"기대대로 실패하지 않았다", file=sys.stderr)
        return 1
    print(f"음성 시험 통과 — 대조군 1 + 정의역 폐쇄 4 + 변이 {len(muts)} 전부 "
          f"기대대로 판정된다")
    print("  ⚠ 이것은 **이 검사가 무는지**를 재는 것이지 게이트의 자기시험들이 "
          "충분한지를 재는 것이 아니다 — 변이 하나짜리도 「가짐」으로 센다.")
    return 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(self_test())
    sys.exit(run())
