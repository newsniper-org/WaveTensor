#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""cover 증인 ↔ 전건 대응 선언의 **참조 실재성** 검사.

## 왜 이 검사가 있는가 — 공허의 다섯째 결

이 저장소가 닫은 공허 넷은 순서대로 이렇다.

  1형 하네스 미부착 (bind 묵살)      → 셀 수 0.        `sby_sweep.sh` 의 HOLLOW
  2형 줄번호 밀림 (참조가 상수 0)     → 이름 부재.      `lint_generated_names.py`
  3형 항진명제 (`connect \\A` 상수)   → 상수 접힘 계수. `lint_postformal` 의 상수 검사
  4형 전제 도달 불가 (`if (P) …` 죽음)→ cover 증인 0.  `_NO_WITNESS` + 래칫

4형을 닫은 게이트가 재는 것은 **「그 태스크에 cover 가 하나라도 있는가」**다.
그 바로 다음 결이 이것이다 —

  **5형: cover 는 있는데 그 증인이 어느 전건에도 대응하지 않는다.**

`w9_x: cover (1'b1);` 하나면 4형 게이트가 만족된다. 태스크당 증인 1 이
요구의 전부일 때, 대응은 사람이 주석으로만 적었고 기계는 개수만 셌다.
이 검사가 그 주석을 **기계가 읽는 형식**으로 승격한다.

## 형식 (RouteJudge 형 — 새로 만든 규약이 아니다)

3차 파도 하네스 넷이 이미 세 가지 표기로 대응을 적고 있었고, 그중 가장
최근 판(RouteJudge)을 정본으로 골랐다. 새 기호는 0 개다 — `←` 는
FabricMerge 가 「이 증인이 살리는 단언」 뜻으로 이미 썼고, 목록 분리자 `·`
는 MemOrderGate 의 `PROVES 대응` 줄과 lint 출력 전역이 이미 쓴다.

    // <TAG> ← <대상>[ · <대상>]*   [— 산문]
    <tag>_<슬러그>: cover (<식>);

  * `<TAG>` 는 대문자+숫자 (`W1` · `WL3` · `M12` · `O7` · `D2`).
    라벨은 `<TAG>` 를 소문자로 내린 것에 `_` 를 붙인 접두로 묶인다 —
    **주석과 셀을 줄번호 없이 잇는다**(2형을 되풀이하지 않는 유일한 방법).
  * 한 태그가 라벨 여럿을 거느릴 수 있다 (`wl1_l0`..`wl1_l3` — lane 넷에
    같은 부류의 증인이 서는 경우). 그때 선언은 하나면 된다.
  * 대상은 셋 중 하나다.
      `<Model>.<guard>`  — GUARD-MAP 의 가드 또는 그 .sby 의 `# VERIFIES:`
                           앵커. **앵커 덮임 계산에 들어가는 유일한 형.**
      `<assert_label>`   — 같은 하네스에 실재하는 단언 라벨 (`p_*`·`t_*`·
                           `a_*`·`g_*`·`inv_*`).
      `?<서술>`          — 해소 불가 선언. `_UNRESOLVED` 래칫이 붙는다.
  * 대상 목록이 길어 줄을 넘길 때는 줄 끝을 `·` 로 맺는다 (그 줄이 이어짐을
    뜻한다). 목록은 `—` 또는 `(` 에서 끝난다.

## 이 검사가 재는 것 (여덟)

  (1) cover 문마다 라벨이 있다. **무명 `cover(1)` 이 게이트를 만족시키는
      길을 막는다** — 5형의 가장 값싼 형태가 그것이다.
  (2) 라벨마다 선언이 정확히 하나이고, 선언마다 라벨이 하나 이상이다.
  (3) 선언의 대상이 **실재한다** — 가드는 GUARD-MAP/앵커에, 단언 라벨은
      같은 하네스에. CHECK 가드를 지목했는데 그 .sby 가 그 가드의 앵커를
      세우지 않았으면 실패다 (남의 태스크가 증명하는 것을 자기 증인의
      대상으로 적는 것은 대응이 아니다).
  (4) 그 .sby 의 **앵커마다 증인이 하나 이상**. 4형 게이트를 태스크 단위
      에서 앵커 단위로 올린다. 면제는 `_ANCHOR_UNWITNESSED` 에 서명한다.
  (5) 증인이 어느 .sby 에도 컴파일되지 않는 경우 (죽은 `ifdef` 안의 증인).
  (6) `_WITNESS_RESIDUAL` — 「이 태스크의 가정 아래에서 원리적으로 증인
      불가」 부류의 표 ↔ 하네스·`.sby` 선언 **쌍방 대조** + 그 가정이 실재
      하는지의 **양성 대조**(`require`). 가정을 되돌리면 면제의 전제가
      깨지고 이 검사가 실패한다 — 살아 있는 검사다.
  (7) 팬아웃 보고 — 한 증인이 앵커 여럿을 주장하면 매번 인쇄한다.
      **래칫은 걸지 않는다**: 내용을 못 재는 표에 건수 래칫을 거는 것은
      「집행되지 않는 규율」을 숫자로 위장하는 것이다 (`_DERIVED` 의 판단).
  (8) 절단 부류 — 절단 무관 증인 집합을 `[script]` 의 `cover: select -assert-none
      … %ci* <모듈>/i:*__* %i` 선택식(조립층 무결성 핀 ④)이 닫는 .sby 에서, 하네스
      W 태그 산문의 [무관]/[의존] 표기가 그 선택식과 라벨 단위로 같은지, 그리고
      머리의 `# CUT-DEP-ONLY:` 닫힌 목록이 「증인이 전부 [의존] 인 앵커」의 기계
      유도 집합과 같은지 잰다 (파도 4 W6 — 손 목록이 여섯에 멈춰 여덟을 놓쳤다).

## 이 검사가 재지 **못하는** 것 — 반드시 함께 읽어라

**선언은 있는데 실제로 그 전건에 대응하지 않는 경우를 전혀 못 잡는다.**

    w9_x: cover (1'b1);        // W9 ← Decode.mal_carried

이 두 줄은 위 여덟 검사를 **전부 통과한다**. 라벨이 있고, 선언이 하나이고,
`Decode.mal_carried` 는 실재하는 가드이고, 그 .sby 의 앵커이기도 하다.
「이 궤적이 저 전건을 세운다」는 **의미의 주장**이고, 로컬 정적 검사가
원리적으로 잴 수 없다. 이 파일은 **이름이 실재하는가**만 잰다 —
`lint_generated_names.py` 가 「이름이 사라진 경우」만 닫는 것과 같은 자리다.

근사하려는 유혹 하나를 미리 거부하고 기록한다: 「증인 식이 그 단언이 쓰는
신호를 문법적으로 언급해야 한다」. `f_ok`·`clk`·`reset`·`f_past_valid` 가
어디에나 있어 즉시 무력해지고, **부분적으로 잡는 근사가 더 찾기 어려운
사각지대를 만든다**는 것이 이 저장소가 세 번 겪은 형태다 (`prep -top` 지문
→ 래퍼 top 통과 / `_STRUCTURAL` forbid → 다른 이름이면 통과 /
`unreached > 0` → cover 0 에서 자동 참).

그 밖에 못 잡는 것:

  * **증인이 실제로 도달했는가** — 그것은 실행 층(sby)의 일이고 증거층
    (`lint_postformal`)이 `reached`/`unreached` 로 읽는다. 이 파일은
    증거를 **보조로만** 읽는다: 증거 스키마에 증인 *이름*이 들어오면
    하네스 라벨 집합과 대조하고, 없으면 「미측정」으로 인쇄한다
    (「대조했더니 같았다」와 「대조할 것이 없었다」를 가른다).
  * **위조** — 선언과 라벨을 함께 고치면 통과한다. 로컬 정적 검사가 할 수
    있는 유일한 성취는 「조용하지 않게」다: 이름이 들어가면 위조가 `.sv`
    로 번져 diff 가 리뷰 대상이 된다. 그 이상은 없고, 주장하지 않는다.
  * **대상 단언이 그 태스크에서 컴파일되는가** — 일부러 재지 않는다.
    cover 모드는 `chformal -assert -remove` 로 단언을 제거하고, MmioConfig
    처럼 증인 영역과 단언 영역이 `ifdef` 로 갈린 하네스도 있다. 증인이
    살리는 것은 **다른 태스크가 재는 단언**이므로 대응은 소스 수준의
    사실이다.

## 이 검사의 순이득이 성립하는 **조건** (명기한다)

앵커당 증인 요구는 3차 파도가 세운 「태스크당 증인 1」(18건)을 「앵커당 1」
(90건)로 올린다. 3차가 `_NO_WITNESS` 를 순수 하드 실패로 두지 않은 이유가
정확히 이 압력이었다 — **요구를 늘리면 「아무거나 세는 증인」의 기대 개수도
같이 는다.** 게이트는 「증인이 있다」를 재고 「증인이 뜻이 있다」는 못 재므로,
이 검사의 순이득은 **리뷰 규율이 버틸 때만** 성립한다. 완화 수단은 둘뿐이고
둘 다 약하다: 팬아웃 보고(한 증인이 앵커 여럿을 주장하면 인쇄)와 사람 검토.

그래서 낱말을 정확히 붙인다 — 이것은 「증인 검증」이 아니라 **「증인 대응
선언의 참조 실재성 대조」**다. 이름을 부풀리면 다음 사람이 「이건 잡았겠지」로
읽고, 그것이 `HiuMask` 를 놓친 형태다 (래퍼 top 을 부착의 증거로 읽었다).

## 음성 시험 (이 검사를 결선하기 전에 통과시킨 것)

`--self-test` 가 격리 사본(`/tmp`)에서 아홉 변이를 만들어 각각이 실제로
실패하는지 확인한다 — 저장소를 더럽히지 않는다.

    ① 없는 단언 라벨을 가리킨다        → 대상 부재로 FAIL
    ② 없는 가드를 가리킨다             → 대상 부재로 FAIL
    ③ 라벨을 지운다 (무명 cover)       → 무명 증인으로 FAIL
    ④ 선언(`←` 줄)을 지운다            → 선언 없는 라벨로 FAIL
    ⑤ 앵커 하나의 증인을 전부 뗀다     → 앵커 미덮임으로 FAIL
    ⑥ 잔여 면제의 전제 assume 을 지운다 → 양성 대조 불통과로 FAIL
    ⑦ 숫자 든 모듈 이름(`Wt64Top.x`)의 VERIFIES 앵커에서 증인을 뗀다
                                        → 앵커 미덮임으로 FAIL (정규식 회귀 대조)
    ⑧ 절단 무관 증인의 산문 부류를 [의존] 으로 바꾼다 → 부류 대조로 FAIL
    ⑨ `# CUT-DEP-ONLY:` 닫힌 목록에서 하나를 뺀다 → 유도 집합 불일치로 FAIL

    scripts/lint_witness_map.py             검사
    scripts/lint_witness_map.py --self-test 음성 시험
"""
import fnmatch
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lint_postformal import (  # noqa: E402
    ROOT, SBY_DIR, evidence_path, guard_kinds, sby_anchors, sby_inputs, sha256,
)

ASSERT_DIR = ROOT / "rtl" / "sv" / "assert"

# ── 표 ①: 「이 태스크의 가정 아래에서 원리적으로 증인 불가」인 부류 ─────────
#
# `_STRUCTURAL` 과 **같은 idiom** 이다: 선언은 하네스·.sby 에, 기계 근거와
# 래칫은 여기에, 그리고 둘을 쌍방 대조한다. 한쪽만 두는 두 대안은 각각 이미
# 겪은 결함으로 간다 —
#
#   하네스 선언만 : 자기 인증. 저자가 「이 부류는 증인 불가」를 스스로 선언해
#                   앵커당 증인 요구를 빠져나갈 수 있고, 그 편집은 같은 파일
#                   안이라 diff 에서 다른 편집과 섞인다.
#   여기 표만     : 사실을 아는 사람이 표를 못 쓴다. 「다리 assume 아래 시작
#                   상태가 무엇을 못박는가」는 하네스 저자만 아는 국소 사실이다.
#
# **표의 키는 `.sby` 하나**다 — `_PARTIAL`·`_DERIVED` 처럼 앵커를 지목하면
# 이 표를 만든 이유가 된 사례가 정작 안 들어간다: mmio_deep 은 unique_owner 가
# DELEGATED 라 앵커가 0 건이다.
#
# `require` 가 **양성 대조**다. 「없다」와 「없는 곳을 봤다」를 가르라는
# `_STRUCTURAL` 조항의 이행이고, 동시에 **살아 있는 검사**다 — 누가 나중에
# 시작 상태를 reset 기점으로 고치면 면제의 전제가 깨지고 여기서 실패한다.
# `premise`(선택)는 그 전제의 이름이다 — 없으면 「시작 상태」 (조립층 항목의
# 전제는 assume 이 아니라 절단 핀 포트 선언이다, 2026-09-26).
_ELSEWHERE = "ELSEWHERE — "   # 그 부류를 실제로 재는 다른 태스크가 있다
_NOWHERE = "NOWHERE — "       # 어디서도 안 잰다 (근거를 적어야 한다)

_WITNESS_RESIDUAL = {
    "rtl/formal/sby/MmioConfig/mmio_deep.sby": {
        "classes": ["소거 구간 (initDone=0)", "reset 기점 도달성"],
        "why": "cover 시작 상태가 initDone·!busy·fault 없음 + 그림자 공집합을 "
               "t=0 에 못박는다. 소거 2^16 사이클을 BMC 가 건너지 못하므로 "
               "reset 기점으로는 원리적으로 잡히지 않는다",
        "ref": "rtl/sv/assert/MmioConfig_props.sv (MMIO_POSTSWEEP_START 절 · "
               "MMIO_DEEP_COVER 시작 상태 절) · mmio_deep.sby (증인 불가 부류 절)",
        "elsewhere": _ELSEWHERE + (
            "소거 구간의 성질(침묵·ready 저지·단조 상승)은 mmio_config.sby 의 "
            "bmc 태스크가 reset 기점으로 따로 잰다. reset 기점 도달성 자체는 "
            "어느 태스크도 재지 않으며, 줄이는 길은 그 부류를 재는 태스크를 "
            "세우는 것 하나뿐이다 (벌점이 아니라 영구 정직 표기다)"
        ),
        "require": [r"assume \(w_initDone\)", r"assume \(shV == 16'b0\)"],
    },
    "rtl/formal/sby/Wt64Top/assembly.sby": {
        "classes": ["실물 도달성 — 절단 출력 의존 증인"],
        "why": "하위 유닛 열넷을 expose -evert 로 절단했다 — 그 출력 핀은 매 스텝 자유다. "
               "콘에 절단 핀이 든 증인은 과대근사 위에서 도달하며 실물 도달을 보증하지 않는다",
        "ref": "rtl/sv/assert/Wt64Top_props.sv (머리 WITNESS-RESIDUAL · W 태그의 [무관]/[의존]) · "
               "rtl/formal/sby/Wt64Top/assembly.sby (cover [script] 콘 판별)",
        "elsewhere": _NOWHERE + (
            "절단 의존 증인을 실물 도달로 올리는 태스크는 없다. 일부는 유닛 태스크의 "
            "증인이 대응 궤적을 세우고(W 태그 산문이 라벨을 인용한다), 절단 무관 증인은 "
            "cover [script] 의 콘 판별이 기계로 강제한다. 조립 전체 궤적의 실물 도달은 "
            "전체 설계(절단 없음) btor cover 가 서기 전까지 어디서도 재지 않는다"
        ),
        "require": [r"(?m)^\s*input\s+logic\b.*\b[a-z0-9_]+__io_[A-Za-z0-9_]+\b"],
        "premise": "절단 핀을 자유 입력으로 받는 하네스 포트 선언",
    },
}
_MAX_WITNESS_RESIDUAL = 2   # 증인 부분 덮임인 태스크 수. 늘지 않는다.
                            # 1 → 2 (2026-09-26, 파도 2 — 조립층 Wt64Top/assembly.sby
                            # 의 「절단 출력 의존 증인」 부류. lint_postformal 의 같은
                            # 이름 래칫과 같은 사건이다).

# ── 표 ②: 증인이 없는 앵커 (서명된 면제) ───────────────────────────────────
#
# 검사 (4) 의 탈출구다. `_NO_WITNESS` 와 같은 형태 — 탈출구가 없으면 다음
# 사람은 규율을 우회하는 대신 **아무거나 세는 증인**을 넣고, 그것은 5형을
# 검출 불가 형태로 옮기는 것이다.
#
# 오늘 0 건. 4차 파도(2026-08-27)가 두 건을 **「면제」가 아니라 「미결 보고」**로
# 넣었었다 — Reassembly/props.sby 의 Payload.last_judges(종료 판정 fr_endEvt 가
# 서는 궤적 없음) · Payload.reset_on_deliver(인도 완결 io_deliver_fire ∧ grant
# 의 궤적 없음). 그 파도는 기존 증인에 대응을 다는 파도라 증인 신설이 범위
# 밖이었고, 처분은 이월 B(2026-09-24)가 증인 W19·W20·W21 신설로 닫았다
# (Reassembly_props.sv 의 REASM_COVER 절 · props.sby 깊이 주석의 실측 표).
# 표는 비었지만 **형식은 남긴다** — 다음 파도가 앵커를 새로 세우고 증인을 못
# 세울 때 「아무거나 세는 증인」 대신 여기 서명하도록 (파일 머리 검사 (4)).
_ANCHOR_UNWITNESSED = {}
_MAX_ANCHOR_UNWITNESSED = 0   # 늘지 않는다. 줄이는 길은 증인 신설뿐이다.
                              # 2 → 0 (2026-09-24 이월 B — 위 두 건을 증인 신설로
                              # 닫았다). 0 이 「미결이 없다」를 뜻하는 것은 표가
                              # 비었기 때문이고, 다시 늘리려면 근거와 함께.

# ── 표 ③: 해소 불가 대상 (`?` 접두) ────────────────────────────────────────
_MAX_UNRESOLVED = 0   # 오늘 0. 늘리려면 근거와 함께.

# ── 하한 래칫 ──────────────────────────────────────────────────────────────
_MIN_WITNESS_MAPPED = 383   # 대응 선언이 붙은 cover 문 수. 줄지 않는다.
                             # 378 → 383 (2026-09-26 실측 383/383 — 태그 코덱 전파 파도: Reassembly_props.sv
                             # W22–W24 셋 · CompletionUnit_props.sv W9 · W10)
                             # 376 → 378 (2026-09-26 실측 378/378 — 파도 4 W6 검토 수리: 비정렬 읽기 0 의
                             # 유닛 증인 CompletionUnit_props.sv W8 · OwnershipTable_props.sv W14)
                             # 345 → 376 (2026-09-26 실측 376/376 — 파도 4 통합 착지: 11 + 14 + 6. 아래 셋은 각
                             # 축 판의 345 기준 증분 서명이다 — 3B 의 W29–W32 는 통합이 W36–W39 로, 3A 의 W29 는 W40 으로 다시 매겼다)
                             # 345 → 356 (2026-09-26 실측 356/356 — 파도 4 페이지 통합: Wt64Top_props.sv 에
                             # W29–W35 일곱 · MmioConfig_props.sv W10 · OwnershipTable_props.sv W13 ·
                             # CompletionUnit_props.sv W6 · W7).
                             # 345 → 359 (2026-09-26 실측 359/359 — 파도 4 3B: HiuMask_props.sv 에 W19–W24 일곱
                             # 라벨, XlateStore_props.sv 에 W13 둘, Wt64Top_props.sv 에 W36–W39 다섯).
                             # 345 → 351 (2026-09-26 실측 351/351 — 파도 4 판정 T5 · T4 착지, 축 3A:
                             # XlateStaging_props.sv 에 W15 · W16(기본 형상) · W17–W19(XLATESTG_P2 — p2.sby),
                             # Wt64Top_props.sv 에 W40 하나).
                             # 336 → 345 (2026-09-26 실측 345/345 — 파도 4 D2 · AbortSurface: AbortStaging_props.sv
                             # 에 W7 셋 · W8 · W9–W12 넷(여덟), Wt64Top_props.sv 에 W28 하나).
                             # 256 → 336 (2026-09-26 실측 336/336 — 파도 3 반증 검토가 하한이
                             # 실측 334 아래 78 칸 헐겁다고 지적했다: 파도 2 · 3 이 증인을 더하는
                             # 동안 이 하한은 한 번도 오르지 않아 증인 78건이 조용히 사라져도
                             # 게이트가 침묵했다. 334 에 수리판이 XlateStaging_props.sv 에 더한
                             # cover 둘(w13_mclr_zero · w14_mclr_rsv)을 더해 336 — w11_missclr 는
                             # w12_missclr 로 태그만 옮겼다).
_MIN_ANCHOR_WITNESSED = 195  # 증인이 선 앵커 수. 줄지 않는다.
                             # 193 → 195 (2026-09-26 실측 195/195 — 태그 코덱 전파 파도: PROVES
                             # Payload.key_drops_side(Reassembly/props.sby W22–W24) · VERIFIES
                             # CompletionUnit.cd_tag1_device_authored(descriptor.sby W9 · W10))
                             # 191 → 193 (2026-09-26 실측 193/193 — 파도 4 W6: VERIFIES
                             # CompletionUnit.unaligned_read_zero · OwnershipTable.unaligned_read_zero)
                             # 163 → 191 (2026-09-26 실측 191/191 — 파도 4 통합 착지: 10 + 14 + 4. 아래 셋은 각
                             # 축 판의 163 기준 증분 서명이다)
                             # 163 → 173 (2026-09-26 실측 173/173 — 파도 4 페이지 통합: MmioPage PROVES 열셋
                             # (assembly.sby 아홉 · mmio_config · ownershiptable 하나씩 · descriptor 둘)이
                             # 증인을 갖고 태어났고, assembly.sby 의 VERIFIES 셋(undefined_offset ·
                             # wo_read_zero · ro_write_loud)이 그중 셋으로 흡수됐다 — 순증 10. 새 과대근사
                             # 증인뿐인 앵커 둘: MmioPage.rsp_on_accept(W33) · effect_on_accept(W34 · W35) —
                             # 콘에 fps__io_loadReady 절단 핀).
                             # 163 → 177 (2026-09-26 실측 177/177 — 파도 4 3B: hiumask.sby PROVES 여덟(XlateObs
                             # 다섯 · XlateSurface mclr_* 셋) · Wt64Top/assembly.sby PROVES 여섯(XlateObs)이 전부
                             # 증인을 갖고 태어났다 — W19–W23 · W36–W39).
                             # 163 → 167 (2026-09-26 실측 167/167 — 파도 4 판정 T5 · T4 착지, 축 3A:
                             # XlateSurface.flush_drops_staging 앵커 둘(XlateStaging/props.sby W15 · W16 ·
                             # Wt64Top/assembly.sby W40) · 신설 XlateStaging/p2.sby 의 ent_part_exists(W17 · W18)
                             # · flush_part_exists(W19) — 전부 증인을 갖고 태어났다).
                             # 148 → 163 (2026-09-26 실측 163/163 — 파도 4: AbortSurface PROVES 열다섯
                             # (AbortStaging/props.sby 열둘 · Wt64Top/assembly.sby 셋)이 전부 증인을 갖고 태어났다).
                             # 144 → 148 (2026-09-26 실측 148/148 — 파도 3 수리: XlateStaging/
                             # props.sby 가 VERIFIES XlateStaging.missclr_word 하나를 PROVES
                             # 다섯(XlateSurface.mclr_* 넷 · ro_rejected)으로 갈았다 — 순증 4,
                             # 전부 W11–W14 증인을 갖고 태어났다).
                             # 133 → 144 (2026-09-26 실측 144/144 — 파도 3 후-formal:
                             # Wt64Top/assembly.sby 의 XlateSurface PROVES 열하나가 전부 조립
                             # 하네스 증인(W18 · W19 · W21 · W23–W27)을 갖고 태어났다).
                             # 118 → 133 (2026-09-26 실측 133/133 — 파도 3: 변환 저장소의
                             # MMIO 문 — XlateStaging/props.sby 앵커 13(PROVES 11 · VERIFIES 2)
                             # · xlatestore.sby 의 XlateSurface.hi_v_carried · assembly.sby 의
                             # Wt64Top.xlate_surface).
                             # 102 → 118 (2026-09-26 실측 118/118 — 파도 2: 조립층
                             # Wt64Top/assembly.sby 의 앵커 열여섯(PROVES 1 ·
                             # VERIFIES 15)이 전부 증인을 갖고 태어났다). 단 넷은
                             # **과대근사 위의 증인뿐**이다 — Wt64Top.wo_read_zero ·
                             # fault_status_map · drain_wiring · composite_wiring 의
                             # 증인은 전부 절단 의존 부류(콘에 절단 핀)라 실물 도달을
                             # 보증하지 않는다 (_WITNESS_RESIDUAL 의 같은 .sby 항목).
                             # 이 계수는 「증인 선언이 선 앵커」를 세지 「실물 도달이
                             # 선 앵커」를 세지 않는다.
                             # 88 (2026-08-27 실측) → 102 (2026-09-24 실측 — 이월 B:
                             # Reassembly/props.sby 의 미결 앵커 둘을 W19~W21 로
                             # 덮어 102/102 가 됐고, 그 사이 파도들의 증가분
                             # (88 → 100, 임대별 마스크 키 · CAP_STATUS 축 둘→넷 ·
                             # FINAL 엣지 동시 기입)을 포함한다). 하한을 실측값에
                             # 세운다 — 「줄지 않는다」는 현재값에 서 있어야 문장이
                             # 된다 (lint_postformal `_MIN_COVERED` 2026-09-21 문면).

_TAG = re.compile(r"^\s*//\s*([A-Z][A-Z]*[0-9]+)\s*←\s*(\S.*?)\s*$")
_COMMENT = re.compile(r"^\s*//\s?(.*?)\s*$")
_COVER = re.compile(r"(?:^|[^\w.$])cover\s*\(")
_LABELED = re.compile(r"\b([a-z][a-z0-9_]*)\s*:\s*cover\s*\(")
_ASSERT_LABEL = re.compile(r"(?:^|[^\w.$])([a-z][a-z0-9_]*)\s*:\s*assert\b", re.M)
_GUARD = re.compile(r"^[A-Z][A-Za-z0-9]*\.[a-z_][A-Za-z0-9_]*$")
_LABEL = re.compile(r"^[a-z][a-z0-9_]*$")
# 모듈 이름에 숫자를 허용하고 가드 이름은 _GUARD 와 같은 꼴로 읽는다 (2026-09-26).
# 옛 꼴 `([A-Za-z]+)\.([A-Za-z_]+)` 은 `Wt64Top.x` 를 [] 로 놓치고 `Top.e1_map_v2`
# 를 ('Top','e') 로 잘랐다 — 기존 .sby 스무 개에서 파싱 결과 차이 0 (실측).
_VERIFIES = re.compile(r"#\s*VERIFIES:\s*([A-Z][A-Za-z0-9]*)\.([a-z_][A-Za-z0-9_]*)")
# (8) 절단 부류 — .sby 머리의 과대근사-전용 앵커 닫힌 목록 (조립층, 파도 4 W6).
_DEP_ONLY = re.compile(r"^#\s*CUT-DEP-ONLY:\s*(.*?)\s*$", re.M)
_CLASS = re.compile(r"\[(무관|의존)")
_DIRECTIVE = re.compile(r"^`(ifdef|ifndef|else|elsif|endif|define|undef)\b\s*(\w+)?")


def fail(msg: str) -> None:
    print(f"lint_witness_map: FAIL — {msg}", file=sys.stderr)
    sys.exit(1)


# ─────────────────────────────────────────────────────────────────────────
# .sby 쪽 — 앵커·정의·하네스
# ─────────────────────────────────────────────────────────────────────────
def sby_verifies(path: Path) -> list:
    """`# VERIFIES: Module.name` — 모델 없는 모듈의 검증 앵커.

    `sby_anchors`(PROVES) 와 같은 자격으로 검사 (3)·(4) 에 들어간다. 둘을
    가르지 않는 이유: 이 검사가 재는 것은 「대상이 이 태스크가 스스로 선언한
    검증 대상인가」이고, 그 점에서 두 낱말은 같은 일을 한다. 가르면
    CompletionUnit·OperandDecode 는 앵커가 0 이 되어 검사 (4) 가 **공허하게
    참**이 된다 — 이 파도가 닫으러 온 형태 그 자체다.
    """
    return [f"{m.group(1)}.{m.group(2)}"
            for m in _VERIFIES.finditer(path.read_text(encoding="utf-8"))]


def sby_defines(path: Path) -> set:
    """`[script]` 절이 켜는 매크로 — `read -define X` 와 `-DX` 둘 다."""
    txt = path.read_text(encoding="utf-8")
    m = re.search(r"^\[script\]$(.*?)(?=^\[|\Z)", txt, re.S | re.M)
    # 주석 줄을 먼저 뗀다. `[script]` 절의 산문이 `-DHIUMASK_COVER` 처럼 매크로
    # 이름을 **인용**하는 실물이 있고(FabricMerge/contracts.sby), 그것을 정의로
    # 읽으면 증인의 태스크 귀속이 조용히 넓어진다 — 「무엇을 세는지 모르는
    # 게이트」의 작은 판이다.
    body = "\n".join(ln.split("#", 1)[0]
                     for ln in (m.group(1) if m else "").splitlines())
    return (set(re.findall(r"-define\s+(\w+)", body))
            | set(re.findall(r"-D(\w+)", body)))


def active_lines(text: str, defines: set) -> list:
    """매크로 집합 아래에서 각 줄이 컴파일되는가 (1-기준 색인은 +1).

    `\\`define` 도 활성 구간에서만 반영한다 — MmioConfig 가 MMIO_COVER 에서
    MMIO_POSTSWEEP_START 를 켜는 관용구가 실물이다.
    """
    defs, stack, out = set(defines), [], []
    for line in text.splitlines():
        m = _DIRECTIVE.match(line.strip())
        active = all(stack)
        if m:
            d, name = m.group(1), m.group(2)
            if d == "ifdef":
                stack.append(active and name in defs)
            elif d == "ifndef":
                stack.append(active and name not in defs)
            elif d == "elsif":
                if stack:
                    stack.pop()
                stack.append(all(stack) and name in defs)
            elif d == "else":
                if stack:
                    prev = stack.pop()
                    stack.append(all(stack) and not prev)
            elif d == "endif":
                if stack:
                    stack.pop()
            elif d == "define" and active:
                defs.add(name)
            elif d == "undef" and active:
                defs.discard(name)
            out.append(False)
            continue
        out.append(active)
    return out


# ─────────────────────────────────────────────────────────────────────────
# 하네스 쪽 — 라벨·선언
# ─────────────────────────────────────────────────────────────────────────
def parse_declarations(text: str):
    """`// <TAG> ← <대상> · <대상> …` → {TAG: (대상 목록, 줄번호)}."""
    lines = text.splitlines()
    out, dup = {}, []
    for i, line in enumerate(lines):
        m = _TAG.match(line)
        if not m:
            continue
        tag, rest = m.group(1), m.group(2)
        j = i
        while rest.rstrip().endswith("·") and j + 1 < len(lines):
            j += 1
            cm = _COMMENT.match(lines[j])
            if not cm:
                break
            rest = rest.rstrip() + " " + cm.group(1)
        head = re.split(r"—|\(", rest, maxsplit=1)[0]
        targets = [x.strip() for x in head.split("·") if x.strip()]
        if tag in out:
            dup.append((tag, i + 1))
        else:
            out[tag] = (targets, i + 1)
    return out, dup


def parse_covers(text: str):
    """cover 문 전수 → [(줄번호, 라벨 or None)]."""
    out = []
    for i, line in enumerate(text.splitlines(), 1):
        code = line.split("//", 1)[0]   # 주석 안의 `cover (` 는 증인이 아니다
        if not _COVER.search(code):
            continue
        m = _LABELED.search(code)
        out.append((i, m.group(1) if m else None))
    return out


def tag_of(label: str, tags) -> list:
    return [t for t in tags if label.startswith(t.lower() + "_")]


# ─────────────────────────────────────────────────────────────────────────
def main() -> int:
    if not ASSERT_DIR.is_dir() or not SBY_DIR.is_dir():
        print("lint_witness_map: OK — 하네스/sby 디렉터리 부재 (미착지)")
        return 0

    kinds, _ = guard_kinds()
    hard, warn, notes = [], [], []

    # ── 하네스 파싱 ────────────────────────────────────────────────────
    harness = {}
    for f in sorted(ASSERT_DIR.glob("*.sv")):
        txt = f.read_text(encoding="utf-8")
        decls, dup = parse_declarations(txt)
        rel = f.relative_to(ROOT).as_posix()
        for tag, ln in dup:
            hard.append(f"{rel}:{ln} — 태그 {tag} 의 `←` 선언이 둘 이상이다")
        harness[rel] = {
            "path": f,
            "text": txt,
            "decls": decls,
            "covers": parse_covers(txt),
            "asserts": set(_ASSERT_LABEL.findall(txt)),
        }

    # (1) 무명 cover · 라벨 중복
    total_covers = 0
    for rel, h in harness.items():
        seen = {}
        for ln, lab in h["covers"]:
            total_covers += 1
            if lab is None:
                hard.append(
                    f"{rel}:{ln} — 무명 cover. 라벨이 없으면 yosys 가 "
                    f"`check_cover_<파일>_<줄>_<id>` 로 **줄번호 매인** 이름을 "
                    f"짓고(실측), 그 이름이 증거에 남으면 무관한 편집마다 증인 "
                    f"이름이 갈린다 — 공허 2형의 증거층 판이다")
            elif lab in seen:
                hard.append(f"{rel}:{ln} — 라벨 {lab} 중복 (:{seen[lab]} 과)")
            else:
                seen[lab] = ln

    # ── .sby 쪽 ────────────────────────────────────────────────────────
    sbys = {}
    for s in sorted(SBY_DIR.rglob("*.sby")):
        rel = s.relative_to(ROOT).as_posix()
        hs = [q for q in sby_inputs(s) if q.startswith("rtl/sv/assert/")]
        sbys[rel] = {
            "path": s,
            "anchors": sby_anchors(s) + sby_verifies(s),
            "defines": sby_defines(s),
            "harnesses": hs,
        }

    # (5) 증인 → .sby 귀속 · (2) 선언↔라벨 · (3) 대상 실재성
    owner = {}          # (하네스, 라벨) -> [.sby …]
    for srel, s in sbys.items():
        for hrel in s["harnesses"]:
            h = harness.get(hrel)
            if h is None:
                hard.append(f"{srel} 의 [files] 가 없는 하네스 {hrel} 를 든다")
                continue
            act = active_lines(h["text"], s["defines"])
            for ln, lab in h["covers"]:
                if lab and ln - 1 < len(act) and act[ln - 1]:
                    owner.setdefault((hrel, lab), []).append(srel)

    mapped = 0
    used_tags = set()
    fanout = []
    unresolved = []
    witnessed = {}      # (.sby, 앵커) -> [증인 라벨 …]
    for hrel, h in harness.items():
        for ln, lab in h["covers"]:
            if lab is None:
                continue
            owners = owner.get((hrel, lab), [])
            if not owners:
                hard.append(
                    f"{hrel}:{lab} — 어느 .sby 도 이 증인을 컴파일하지 않는다 "
                    f"(죽은 `ifdef` 안의 증인 — 세어지지도 도달되지도 않는다)")
                continue
            cands = tag_of(lab, h["decls"])
            if not cands:
                hard.append(
                    f"{hrel}:{ln} — 라벨 {lab} 에 대응 선언(`// <TAG> ← …`)이 "
                    f"없다. 접두 규칙: 라벨 `w3_foo` ↔ 태그 `W3`")
                continue
            if len(cands) > 1:
                hard.append(f"{hrel}:{ln} — 라벨 {lab} 이 태그 "
                            f"{' · '.join(sorted(cands))} 여럿에 걸린다")
                continue
            tag = cands[0]
            used_tags.add((hrel, tag))
            targets, dln = h["decls"][tag]
            mapped += 1
            if not targets:
                hard.append(f"{hrel}:{dln} — 태그 {tag} 의 대상 목록이 비었다")
                continue
            anchors_hit = 0
            for tgt in targets:
                if tgt.startswith("?"):
                    if len(tgt) < 3:
                        hard.append(f"{hrel}:{dln} — `?` 대상에 서술이 없다")
                    unresolved.append(f"{hrel} {tag} → {tgt}")
                    continue
                if _GUARD.match(tgt):
                    model, guard = tgt.split(".", 1)
                    in_anchor = [s for s in owners if tgt in sbys[s]["anchors"]]
                    if in_anchor:
                        anchors_hit += 1
                        for s in in_anchor:
                            witnessed.setdefault((s, tgt), []).append(lab)
                        continue
                    kind = kinds.get((model, guard))
                    if kind is None:
                        hard.append(
                            f"{hrel}:{dln} — 태그 {tag} 의 대상 {tgt} 가 "
                            f"GUARD-MAP 에도 이 .sby 의 앵커에도 없다 "
                            f"(태스크: {' · '.join(owners)})")
                    elif kind == "CHECK":
                        hard.append(
                            f"{hrel}:{dln} — 태그 {tag} 가 CHECK 가드 {tgt} 를 "
                            f"지목하는데 {' · '.join(owners)} 는 그 가드의 "
                            f"`# PROVES:` 앵커를 세우지 않는다 — 남의 태스크가 "
                            f"증명하는 것은 이 증인의 대상이 아니다")
                    else:
                        notes.append(f"{hrel} {tag} → {tgt} ({kind} 가드 — "
                                     f"앵커 덮임 계산 밖)")
                    continue
                if _LABEL.match(tgt):
                    if tgt not in h["asserts"]:
                        hard.append(
                            f"{hrel}:{dln} — 태그 {tag} 의 대상 `{tgt}` 가 이 "
                            f"하네스의 단언 라벨이 아니다 (2형과 같은 결: "
                            f"이름이 밀리면 대응이 조용히 허공을 가리킨다)")
                    continue
                hard.append(f"{hrel}:{dln} — 태그 {tag} 의 대상 `{tgt}` 가 "
                            f"셋 중 어느 형태도 아니다")
            if anchors_hit >= 3:
                fanout.append(f"{hrel} {tag} → 앵커 {anchors_hit}개")

    # (2) 선언은 있는데 라벨이 없는 태그
    for hrel, h in harness.items():
        for tag, (_, dln) in sorted(h["decls"].items()):
            if (hrel, tag) not in used_tags:
                hard.append(f"{hrel}:{dln} — 태그 {tag} 의 선언은 있는데 "
                            f"`{tag.lower()}_*` 라벨이 하나도 없다")

    # (4) 앵커마다 증인 하나 이상
    covered = uncovered = 0
    signed = []
    for srel, s in sorted(sbys.items()):
        for a in s["anchors"]:
            if witnessed.get((srel, a)):
                covered += 1
            elif (srel, a) in _ANCHOR_UNWITNESSED:
                signed.append((srel, a))
            else:
                uncovered += 1
                hard.append(
                    f"{srel} — 앵커 {a} 에 증인이 없다. 전건이 도달 불가능해서 "
                    f"통과하는 경우와 구별되지 않는다 (공허 4형의 앵커 단위 판). "
                    f"면제하려면 `_ANCHOR_UNWITNESSED` 에 서명하라")
    stale = [k for k in _ANCHOR_UNWITNESSED
             if k[0] not in sbys or k[1] not in sbys[k[0]]["anchors"]]
    for k in stale:
        hard.append(f"_ANCHOR_UNWITNESSED 의 {k[0]} / {k[1]} 가 실재하지 않는다 "
                    f"(표 부패 — 대상이 사라진 면제는 아무도 다시 읽지 않는다)")
    # (8) 절단 부류 대조 — 절단 무관 증인 집합을 [script] 선택식(④)이 닫는 .sby 에서
    #     ① W 태그 산문의 [무관]/[의존] 표기 = 선택식이 고른 라벨 집합 (라벨 단위)
    #     ② 머리의 `# CUT-DEP-ONLY:` 닫힌 목록 = 증인이 전부 [의존] 인 앵커 집합 (기계 유도)
    #     손으로 적은 목록이 기계 밖 자백으로 남아 여섯에 멈춰 있던 것을 닫는다.
    dep_checked = 0
    for srel, s in sorted(sbys.items()):
        stext = s["path"].read_text(encoding="utf-8")
        free_line = next((ln for ln in stext.splitlines()
                          if ln.startswith("cover: select -assert-none")
                          and "%ci*" in ln and "i:*__*" in ln), None)
        decl = _DEP_ONLY.search(stext)
        if free_line is None and decl is None:
            continue
        if free_line is None or decl is None:
            hard.append(f"{srel} — 절단 무관 선택식(④)과 `# CUT-DEP-ONLY:` 닫힌 목록은 "
                        f"짝으로만 선다 (한쪽만 있다)")
            continue
        pats = re.findall(r"c:chk\.([A-Za-z0-9_*]+)", free_line.split("%ci*", 1)[0])
        labs = {(hrel, lab) for (hrel, lab), owners in owner.items() if srel in owners}
        free = {lab for (_, lab) in labs
                if any(fnmatch.fnmatchcase(lab, p_) for p_ in pats)}
        for hrel, lab in sorted(labs):
            h = harness[hrel]
            cands = tag_of(lab, h["decls"])
            if len(cands) != 1:
                continue            # (2) 가 이미 운다
            lines = h["text"].splitlines()
            j = h["decls"][cands[0]][1] - 1
            block = [lines[j]]
            while j + 1 < len(lines) and _COMMENT.match(lines[j + 1]) \
                    and not _TAG.match(lines[j + 1]):
                j += 1
                block.append(lines[j])
            btxt = " ".join(block)
            m = re.search(re.escape(lab) + r"\s*\[(무관|의존)", btxt)
            if not m:
                tail = btxt.split("—", 1)[1] if "—" in btxt else ""
                m = _CLASS.search(tail)
            if not m:
                hard.append(f"{hrel} — 증인 {lab} 에 [무관]/[의존] 표기가 없다 ({srel} 의 "
                            f"절단 부류는 라벨마다 선언한다)")
                continue
            said_free = m.group(1) == "무관"
            if said_free != (lab in free):
                hard.append(
                    f"{hrel} — 증인 {lab} 의 산문 부류 [{m.group(1)}] 가 {srel} ④ 선택식과 "
                    f"어긋난다 (선택식은 {'무관' if lab in free else '의존'})")
        declared = set()
        tail = stext[decl.start():].splitlines()
        body = decl.group(1)
        k = 0
        while body.rstrip().endswith("·") and k + 1 < len(tail):
            k += 1
            body = body.rstrip() + " " + tail[k].lstrip("#").strip()
        declared = {x.strip() for x in body.split("·") if x.strip()}
        derived = {a for a in s["anchors"]
                   if witnessed.get((srel, a))
                   and not any(l_ in free for l_ in witnessed[(srel, a)])}
        for a in sorted(derived - declared):
            hard.append(f"{srel} — 앵커 {a} 의 증인은 전부 절단 의존인데 `# CUT-DEP-ONLY:` "
                        f"닫힌 목록에 없다")
        for a in sorted(declared - derived):
            hard.append(f"{srel} — `# CUT-DEP-ONLY:` 의 {a} 는 절단 무관 증인이 있거나 "
                        f"이 태스크의 증인 선 앵커가 아니다")
        dep_checked += 1
        notes.append(f"{srel} — 절단 의존 증인뿐인 앵커 {len(derived)} (④ 선택식 무관 "
                     f"{len(free)} 라벨에서 유도 · 닫힌 목록과 일치)")
    if len(signed) > _MAX_ANCHOR_UNWITNESSED:
        hard.append(f"증인 없는 앵커 {len(signed)} > 래칫 "
                    f"{_MAX_ANCHOR_UNWITNESSED}")

    # (6) 증인 잔여 — 표 ↔ 하네스·.sby 쌍방 + 양성 대조
    residual = []
    for srel, ent in sorted(_WITNESS_RESIDUAL.items()):
        s = sbys.get(srel)
        if s is None:
            hard.append(f"_WITNESS_RESIDUAL 의 {srel} 가 실재하지 않는다 (표 부패)")
            continue
        el = ent.get("elsewhere", "")
        if not (el.startswith(_ELSEWHERE) or el.startswith(_NOWHERE)):
            hard.append(f"_WITNESS_RESIDUAL[{srel}] 의 `elsewhere` 가 "
                        f"`{_ELSEWHERE}` 또는 `{_NOWHERE}` 로 시작하지 않는다")
        elif len(el.split("— ", 1)[-1].strip()) < 20:
            hard.append(f"_WITNESS_RESIDUAL[{srel}] 의 `elsewhere` 근거가 비었다")
        decl_txt = s["path"].read_text(encoding="utf-8")
        hs_txt = "\n".join((ROOT / q).read_text(encoding="utf-8")
                           for q in s["harnesses"] if (ROOT / q).is_file())
        for cls in ent["classes"]:
            for where, txt in (("sby", decl_txt), ("하네스", hs_txt)):
                if f"WITNESS-RESIDUAL: {cls}" not in txt:
                    hard.append(
                        f"{srel} — 잔여 부류 「{cls}」 의 선언이 {where} 에 없다 "
                        f"(쌍방 대조: 한쪽만 아는 상태가 분모 갈림의 원인이다)")
        for pat in ent["require"]:
            if not re.search(pat, hs_txt):
                hard.append(
                    f"{srel} — 잔여 면제의 **전제**"
                    f"({ent.get('premise', '시작 상태')})가 하네스에 없다: /{pat}/ "
                    f"불일치. 전제를 되돌렸다면 면제가 무효다 (양성 대조)")
        residual.append((srel, ent))
    if len(residual) > _MAX_WITNESS_RESIDUAL:
        hard.append(f"증인 부분 덮임 {len(residual)} > 래칫 "
                    f"{_MAX_WITNESS_RESIDUAL}")

    if len(unresolved) > _MAX_UNRESOLVED:
        hard.append(f"해소 불가 대상(`?`) {len(unresolved)} > 래칫 "
                    f"{_MAX_UNRESOLVED}")

    # 래칫
    if mapped < _MIN_WITNESS_MAPPED:
        hard.append(f"대응 선언이 붙은 증인 {mapped} < 하한 "
                    f"{_MIN_WITNESS_MAPPED} (줄지 않는다)")
    if covered < _MIN_ANCHOR_WITNESSED:
        hard.append(f"증인이 선 앵커 {covered} < 하한 "
                    f"{_MIN_ANCHOR_WITNESSED} (줄지 않는다)")

    # (보조) 증거의 증인 이름 대조 — 증거가 **신선할 때만** 한다.
    #
    # stale 한 증거와 대조하면 「하네스에 있는데 증거에 없다」가 쏟아지고,
    # 그것은 이 검사의 결함이 아니라 아직 안 돈 스윕이다. 두 낱말을 섞지
    # 않는다 — stale 은 `lint_postformal` 의 낱말이고 여기서는 **대조 보류**다.
    ev_checked = ev_absent = ev_stale = 0
    for srel, s in sorted(sbys.items()):
        ev = evidence_path(s["path"])
        if not ev.is_file():
            continue
        try:
            doc = json.loads(ev.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        cov = doc.get("cover") or {}
        if not isinstance(cov.get("reached_names"), list):
            ev_absent += 1
            continue
        fresh = all(
            (ROOT / q).is_file() and sha256(ROOT / q) == h
            for q, h in (doc.get("inputs") or {}).items())
        if not fresh:
            ev_stale += 1
            continue
        ev_checked += 1
        got = {n.rsplit(".", 1)[-1]
               for n in (cov.get("reached_names") or [])
               + (cov.get("unreached_names") or [])}
        want = {lab for (hrel, lab), owners in owner.items() if srel in owners}
        for n in sorted(got - want):
            hard.append(
                f"{ev.relative_to(ROOT)} 의 증인 이름 `{n}` 이 하네스 라벨 "
                f"집합에서 유도되지 않는다 — 증거와 하네스가 갈렸다 (무명 "
                f"cover 가 남아 yosys 가 줄번호 매인 이름을 지었거나, 증거가 "
                f"다른 하네스에서 왔다)")
        for n in sorted(want - got):
            hard.append(
                f"{ev.relative_to(ROOT)} 에 증인 `{n}` 이 없다 — 하네스에는 "
                f"있는데 실행이 그 셀을 보지 못했다 (귀속 계산과 실제 컴파일이 "
                f"어긋난다)")
        for n in sorted({x.rsplit(".", 1)[-1]
                         for x in (cov.get("unreached_names") or [])}):
            notes.append(f"{srel} — 증인 {n} **미도달** (그 전건이 죽었다는 "
                         f"뜻이고, 대응 선언이 그 자리를 이름으로 귀속한다)")

    # ── 보고 ───────────────────────────────────────────────────────────
    for w in warn:
        print(f"  ⚠ {w}")
    if hard:
        for m in hard:
            print(f"lint_witness_map: {m}", file=sys.stderr)
        fail(f"증인↔전건 대응 {len(hard)}건이 자기모순이다")

    print(f"lint_witness_map: OK — cover 증인 {total_covers}건 전부 라벨 + 대응 "
          f"선언 ({mapped} 귀속) · 앵커 {covered}/{covered + len(signed)} 에 증인 "
          f"(하한 {_MIN_ANCHOR_WITNESSED})")
    print("  이것은 **자기모순 대조**이지 검증이 아니다: 이름의 실재성만 잰다. "
          "선언이 실제로 그 전건에 대응하는지는 재지 못하고, 선언과 라벨을 "
          "함께 고친 위조도 잡지 못한다 — **재실행만이 검증이다**.")
    if signed:
        print(f"  ⚠ 증인 없는 앵커 {len(signed)} ≤{_MAX_ANCHOR_UNWITNESSED} "
              f"(면제가 아니라 **미결 보고**)")
        for srel, a in signed:
            print(f"      {srel} — {a}")
            print(f"        {_ANCHOR_UNWITNESSED[(srel, a)]}")
    for srel, ent in residual:
        print(f"  ⚠ {srel} — 증인 **부분** 덮임: 증인 불가 부류 "
              f"{len(ent['classes'])} — {' · '.join(ent['classes'])}")
        print(f"      근거 기계 대조 통과 (전제 assume 실재) · "
              f"{ent['elsewhere'].split('— ', 1)[-1][:72]}…")
    for n in notes:
        print(f"  · {n}")
    for f_ in fanout:
        print(f"  · 팬아웃 {f_}")
    print(f"  · 증거 증인 이름 대조: {ev_checked}건 대조 · {ev_stale}건 대조 "
          f"보류(증거 미갱신) · {ev_absent}건 **미측정**(증거 스키마에 증인 "
          f"이름 필드 없음) — 셋은 서로 다른 낱말이다")
    return 0


# ─────────────────────────────────────────────────────────────────────────
# 음성 시험 — 격리 사본에서 아홉 변이가 실제로 실패하는지
# ─────────────────────────────────────────────────────────────────────────
_MUTATIONS = [
    ("① 없는 단언 라벨을 가리킨다",
     "rtl/sv/assert/SharedUnit_props.sv",
     ("W2 ← SharedUnit.queue_room · a_queue_room",
      "W2 ← SharedUnit.queue_room · a_queue_room_typo")),
    ("② 없는 가드를 가리킨다",
     "rtl/sv/assert/XlateStore_props.sv",
     ("W1 ← Isolation.fill_tagged", "W1 ← Isolation.fill_tagged_typo")),
    ("③ 라벨을 지운다 (무명 cover)",
     "rtl/sv/assert/ResultBank_props.sv",
     ("w1_grant:         cover (io_acquire_granted);",
      "cover (io_acquire_granted);")),
    ("④ 선언(`←` 줄)을 지운다",
     "rtl/sv/assert/OwnershipTable_props.sv",
     ("// W6  ← Platform.state_machine_kept — 충돌 기입 형상 도달 (기입 무효화",
      "// (지운 선언) 충돌 기입 형상 도달 (기입 무효화")),
    ("⑤ 앵커 하나의 증인을 전부 뗀다",
     "rtl/sv/assert/SharedUnitDepth0_props.sv",
     ("// W1 ← SharedUnit.busy_check · a_busy_check · a_no_silent_drop",
      "// W1 ← a_busy_check · a_no_silent_drop")),
    ("⑥ 잔여 면제의 전제 assume 을 지운다",
     "rtl/sv/assert/MmioConfig_props.sv",
     ("      assume (shV == 16'b0);", "      // (지운 전제)")),
    ("⑦ 숫자 든 모듈 이름의 VERIFIES 앵커에서 증인을 뗀다",
     "rtl/sv/assert/Wt64Top_props.sv",
     ("W1 ← Wt64Top.region_routing · a_cq_strb", "W1 ← a_cq_strb")),
    ("⑧ 절단 무관 증인의 산문 부류를 [의존] 으로 바꾼다",
     "rtl/sv/assert/Wt64Top_props.sv",
     ("a_miss_clr · a_hiu_pass — [무관]", "a_miss_clr · a_hiu_pass — [의존]")),
    ("⑨ 과대근사-전용 앵커 닫힌 목록에서 하나를 뺀다",
     "rtl/formal/sby/Wt64Top/assembly.sby",
     ("CUT-DEP-ONLY: MmioPage.effect_on_accept · ", "CUT-DEP-ONLY: ")),
]


def self_test() -> int:
    me = Path(__file__).resolve()
    ok = True
    with tempfile.TemporaryDirectory(prefix="wt-witness-neg-") as td:
        base = Path(td) / "repo"
        for sub in ("scripts", "rtl"):
            shutil.copytree(ROOT / sub, base / sub, symlinks=True,
                            ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        r = subprocess.run([sys.executable, str(base / "scripts" / me.name)],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print("음성 시험 전제 불통과 — 변이 없는 사본이 이미 실패한다:")
            print(r.stdout + r.stderr)
            return 1
        print("양성 대조: 변이 없는 사본은 통과한다 ✓")
        for name, rel, (a, b) in _MUTATIONS:
            f = base / rel
            orig = f.read_text(encoding="utf-8")
            if a not in orig:
                print(f"  {name}: 변이 지점을 찾지 못했다 — /{a[:40]}/")
                ok = False
                continue
            f.write_text(orig.replace(a, b, 1), encoding="utf-8")
            r = subprocess.run([sys.executable, str(base / "scripts" / me.name)],
                               capture_output=True, text=True)
            f.write_text(orig, encoding="utf-8")
            if r.returncode == 0:
                print(f"  {name}: **검사가 잡지 못했다** (공허한 검사다)")
                ok = False
            else:
                first = [ln.split("lint_witness_map: ", 1)[-1]
                         for ln in (r.stderr or "").splitlines()
                         if "lint_witness_map:" in ln
                         and not ln.startswith("lint_witness_map: FAIL —")]
                print(f"  {name}: FAIL 확인 ✓ — {first[0][:92] if first else ''}")
    print("음성 시험 " + ("통과 — 아홉 변이 전부 잡힌다" if ok else "불통과"))
    return 0 if ok else 1


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(self_test())
    sys.exit(main())
