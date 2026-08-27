#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""후-formal 증명 선언(PROVES)과 GUARD-MAP 주장의 대조 + 실행 증거의 검사.

## 이 검사의 자리

lint_guard_map 은 「가드마다 RTL 주장 1줄」의 전수성을 재고, 스스로
「매핑의 참은 후-formal 몫」이라 적었다. 후-formal 이 착지하면 그 참의
증거는 sby 스크립트다 — 각 .sby 머리의 `# PROVES: <Model>.<guard>` 줄이
"이 태스크가 그 가드의 참을 잰다"는 앵커다.

세 층의 분업은 notes-vacuity-detection.md 의 표 그대로다:

    의존성 | 무엇을 *다시* 재야 하는가        | sby_impact.py
    실행   | 실제로 재고 **증거를 남긴다**    | make rtl-postformal (sby_sweep.sh)
    정적   | 증거가 **있고 신선한가**         | 이 파일

2026-08-26 개정 전까지 셋째 층은 둘째 층의 산출을 **전혀 읽지 않았다.**
앵커의 실재성만 재고 그것을 「덮임」으로 계수했다 — 자기 docstring 에
「증명의 통과 여부는 재지 못한다」고 정직하게 적어 두었는데 **「덮임」이라는
낱말이 그 정직함을 삼켰다.** 이 개정이 그 구멍을 닫는다.

## 이 검사가 대조하는 것

  (1) PROVES 가 참조하는 (모델, 가드)가 실재한다 (AllGuards 대조).
  (2) PROVES 는 CHECK 가드에만 선다 — DELEGATED/ENV/구조-skip 가드에
      증명을 주장하면 앵커가 거짓이다.
  (3) `[files]` 경로의 실재성 (저장소 루트 기준 규약).
  (4) **구조 skip** — 증명 대상이 아닌 구조적 부재를 *인정하되 근거를
      기계로 잰다*. `_STRUCTURAL` 표를 보라.
  (5) **부분 덮임** — 좁은 증명이 넓은 주장을 「덮임」으로 계수하는 것을
      막는다. `_PARTIAL` 표를 보라.
  (6) **실행 증거** — `<태스크>.evidence.json` 의 존재·판정·셀 수·신선도.
  (7) 래칫 넷 (아래).

## 이 검사가 재지 **못하는** 것 (정직하게)

증거를 만드는 주체는 sby 자신이다. 정적 층은 실행 층을 신뢰하는 것 외에
방법이 없고, 이것은 수용 가능한 신뢰 경계다 — 다만 그 경계가 어디인지
적어 두는 것과 모르는 것은 다르다. **실행 없이는 새 증거가 생기지 않는다.**

셀 수는 하한이지 충분조건이 아니다. 항진명제(폭이 이미 보장하는 것을
단언하는 형태)는 셀도 세어지고 증명도 통과하므로 이 층이 잡지 못한다 —
가드 삭제 실험의 후-formal 판이 그 자리이고 아직 없다.

## 세 낱말을 섞지 않는다

notes-vacuity-detection.md 가 실물 사고 둘로 배운 규율이다:
**「측정하지 못했다」와 「측정했더니 0이었다」와 「측정한 적이 없다」는
서로 다른 판정이다.** 앞의 둘은 각각 게이트/대상의 결함이고 셋째는 아직
아무 일도 일어나지 않은 것이다. 같은 낱말로 보고하면 엉뚱한 것을 고치러
간다. 이 파일은 각각 UNCOUNTED · HOLLOW · 미측정 으로 인쇄한다.

## 모드

    lint_postformal.py                  정적 검사 (make lint 가 부르는 것)
    lint_postformal.py --require-fresh  + stale·미측정 증거를 실패로 (스윕 직후 자기검사)
    lint_postformal.py --emit-evidence …  증거 파일 기록 (sby_sweep.sh 전용)

## 음성 시험 — 신설 검사가 실제로 깨지는가

`lint_generated_names` 의 선례대로, 새 검사는 **일부러 깨뜨린 입력에서
실패하는 것을 본 뒤에** 결선한다. 저장소를 더럽히지 않고 재현하는 법:
격리 사본을 만들고(스크립트 + `rtl/` 만 있으면 된다) 거기서 깨뜨린다.

    cp -r rtl /tmp/nt/rtl && mkdir -p /tmp/nt/scripts
    cp scripts/lint_postformal.py /tmp/nt/scripts/
    # 아래 각각을 /tmp/nt 안에서 하고 python3 /tmp/nt/scripts/lint_postformal.py

2026-08-26 실측 (21건 전건 검출 — 음성 20 · 양성 1):
  · 구조 skip 전제 파괴 3종 — DecodeWalk 의 io_oFault 를 [3:0] 로 넓히기 ·
    XlateStore 에 io_lookup_ready 달기 · HiuPipeline 에 io_hostQuery_valid 달기
  · 양성 대조 파괴 — io_oMalformed 를 개명 (「부재」가 아니라 「없는 곳을 봤다」)
  · 구조 skip 가드에 PROVES 앵커 달기
  · 부분 덮임 표 부패 — 표가 가리키는 앵커 삭제
  · 커버리지 래칫 — 앵커 하나 삭제
  · 증거 모순 7종 — HOLLOW · FAIL · UNCOUNTED · PASS 인데 셀 0 ·
    cover 증인 미도달 · schema 불일치 · JSON 아님
  · 증거 래칫 — _MIN_EVIDENCED 를 올린 채 증거 없음
  · stale 3종 — 입력 소스 변경 · .sby 자신 변경 · `[files]` 목록 불일치
    (기본 모드는 경고, --require-fresh 는 실패). 기본 모드가 통과하는 것
    자체가 시험 항목이다 — 편집 중에 깨지면 아무도 이 검사를 못 쓴다
  · 양성 대조 — 전 태스크에 신선한 증거를 두면 --require-fresh 가 통과한다

2026-08-26 3차 파도 (신설 검사 넷 · 16건 — 음성 13 · 양성 3, 전건 검출):
  · **4분류 승격** — 승격을 되돌리면(RHS 를 CHECK 문면으로) 「GUARD-MAP 에서
    CHECK 다」로 실패. 같은 파괴에서 lint_guard_map 이 **분모 75** 를 인쇄해
    두 lint 가 갈리는 것까지 관측했다 (파괴 전 둘 다 74) · 표에 없는 넷째
    STRUCTURAL 선언 → 양쪽에서 각각 (표에 근거 없음 / 구조 skip 래칫) ·
    `STRUCTURAL()` 빈 인자 · 선언만 있고 근거 문면 없음 ·
    선언 종류 불일치(state-absence vs 표의 port-absence)
  · **`unmeasured` 칸** — 칸 부재 · 빈 문자열 · `NONE —` 만 있고 근거 없음 ·
    잔여분 래칫(1→2)
  · **증인 없음 게이트** — cover 셀 0 인 증거 → 하드 실패. 그리고 **순서**를
    따로 시험했다: 항등 검사(`reached+unreached == cover`)와 미도달 검사는
    cover 0 에서 자동으로 참이 되므로, 이 검사가 뒤에 서면 조용히 통과한다.
    실측으로 「증인이 0 이다」가 먼저 인쇄되는 것을 확인했다 ·
    허용목록 등재만 하고 래칫 미상향 → 서명 요구 ·
    **양성 대조: 근거+서명이 갖춰지면 실제로 면제된다** (탈출구가 실재한다) ·
    표 부패(없는 .sby) · 근거 문면 빔
  · **`_DERIVED` 결속** — 앵커 없는 태스크를 가리키면 실패
  · **분모 항등 방어선** — 앞선 두 겹(쌍방 대조 · 근거 종류 대조)을 코드에서
    무력화한 뒤에야 닿는 셋째 겹이고, 거기서 「분모 항등 위반」이 났다
"""
import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

# GUARD-MAP RHS 의 분류 규칙은 **저장소에 한 벌만** 산다. 사본을 만들면 두
# lint 가 같은 GUARD-MAP 에서 다른 분모를 인쇄하고, 그것이 2026-08-26 이전의
# 실제 상태였다 (lint_guard_map: CHECK 77 / 여기: 분모 74). 같은 디렉터리의
# 스크립트라 python 이 자동으로 sys.path 에 올린다.
from lint_guard_map import classify  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
TLA_DIR = ROOT / "rtl" / "formal" / "tla"
SBY_DIR = ROOT / "rtl" / "formal" / "sby"
RTL_DIR = ROOT / "rtl" / "spinal" / "src"
GEN_DIR = ROOT / "rtl" / "generated"

EVIDENCE_SCHEMA = "wt64-postformal-evidence/1"

# ── 래칫 넷 ──────────────────────────────────────────────────────────────
#
# 방향이 서로 다른 것에 주의하라. 아래 둘은 **하한**(줄면 실패)이고 가운데
# 둘은 **상한**(늘면 실패)이다. 상한 쪽이 있는 이유: 구조 skip 과 부분 덮임은
# 「CHECK 분모를 비우는」 방향의 부정을 가능하게 하므로, 그것을 늘리는 일은
# 반드시 이 파일을 고치는 *명시적 서명*을 거쳐야 한다.
_MIN_COVERED = 74      # 완전+부분 덮임 CHECK 가드 수. 2026-08-26 실측. 줄지 않는다
_MAX_PARTIAL = 6       # 부분 덮임뿐인 가드 수. 늘지 않는다 (늘리려면 근거와 함께)
                       #
                       # 2 → 6 (2026-08-26, 같은 파도의 전수 검증 직후).
                       # 근거: 새로 부분 증명을 *만든* 것이 아니라 **이미 있던
                       # 넷을 표가 못 읽고 있었다.** 넷 다 자기 .sby 의 §미측정
                       # 잔여 절에 「이 축만 잰다」를 적어 두었는데 표에 없어서
                       # 완전 덮임으로 계수됐다 — Platform.owner_check 가
                       # 미끄러진 그 경로이고, 그것을 막으려고 만든 표가 같은
                       # 자리에서 넷을 더 놓쳤다. 이 상향은 커버리지를 낮추는
                       # 것이 아니라 **숫자를 사실에 맞추는 것**이다.
                       # (완전 덮임 72 → 68, 완전+부분은 74 로 불변.)
_MAX_STRUCTURAL = 3    # 구조 skip 가드 수. 늘지 않는다 (같은 이유)
                       # lint_guard_map._MAX_STRUCTURAL 과 같은 값이어야 한다 —
                       # 아래 쌍방 대조가 두 표의 일대일을 강제하므로 값이
                       # 갈리면 둘 중 낮은 쪽에서 먼저 실패한다.
_MAX_STRUCTURAL_RESIDUAL = 1
                       # 구조 skip 중 **잔여분이 남은** 가드 수. 늘지 않는다.
                       #
                       # 0 → 1 (2026-08-26, 3차 파도). 새 미측정을 만든 것이
                       # 아니라 `Isolation.fill_offpath` 의 잔여분이 이미
                       # 미측정이었고 표에 칸이 없어 보이지 않았을 뿐이다.
                       # `_MAX_PARTIAL` 이 2→6 으로 간 것과 같은 성격 —
                       # 커버리지를 낮추는 것이 아니라 숫자를 사실에 맞추는 것.
                       #
                       # 방향이 상한인 이유: 잔여분 있는 skip 은 「분모에서
                       # 빠졌는데 실제로는 덜 쟀다」는 상태다. 정직하게 적는 것이
                       # 숨기는 것보다 낫지만, **늘어도 되는 것은 아니다.**
                       # 줄이는 길은 그 축을 실제로 재고 칸을 _NOTHING_LEFT 로
                       # 바꾸는 것뿐이다.
_MIN_EVIDENCED = 80    # 실행 증거로 뒷받침된 앵커 수. 줄지 않는다.
                       #
                       # 0 → 80 (2026-08-26, 전수 스윕 직후 실측: 18/18 PASS ·
                       # fail 0 · hollow 0 · uncounted 0 · 앵커 80 전부 신선).
                       # **0 인 동안 이 층은 아무것도 재지 않는다** — 신설 파도의
                       # 과도기 값이었고, 발효시키지 않으면 증거를 쓰기만 하고
                       # 읽지 않는 층이 된다. 그것이 이 저장소가 이름 붙인
                       # 「집행되지 않는 규율」(부록 B.3)의 새 사례가 됐을 것이다.

# ── 부분 덮임 표 ─────────────────────────────────────────────────────────
#
# ## 왜 앵커 쪽이 아니라 여기인가
#
# 「이 증명이 그 주장을 다 덮는가」는 **앵커 저자가 판정할 수 없는 것**이다.
# 자기 증명의 폭을 자기가 선언하면 그것이 곧 자기 인증이고, Platform.owner_check
# 가 「덮임」으로 계수된 경로가 정확히 그것이었다 — OwnershipTable 앵커는
# 자기가 재는 것을 정직하게 적었는데(「판정 데이터 원천」), 그 정직함을 읽는
# 기계가 없어서 lint 는 그것을 완전 덮임 1건으로 셌다.
#
# 그래서 판정을 **통합자의 표 한 곳**에 모은다. 이 표를 늘리는 일은 diff 에
# 남고 `_MAX_PARTIAL` 래칫이 서명을 요구한다. 표가 부패하면(앵커가 사라졌는데
# 항목이 남으면) 아래 대조가 실패한다 — 표는 앵커의 실재에 결속돼 있다.
#
# 키: (모델, 가드, .sby 경로) — 앵커 하나를 정확히 지목한다.
# 값: (이 앵커가 재는 축, 이 앵커가 **재지 않는** 것)
#
# 규칙: 한 가드의 앵커가 *전부* 이 표에 있으면 그 가드는 **부분 덮임**이다.
# 축의 합집합이 주장 전체라는 판정은 하지 않는다 — 그 판정이야말로 사람이
# 두 태스크를 읽어야 하는 것이고, 기계가 대신하면 같은 함정을 한 겹 더
# 정교하게 다시 만든다 (notes-vacuity-detection.md 의 논지).
_PARTIAL = {
    ("Platform", "owner_check", "rtl/formal/sby/OwnershipTable/ownershiptable.sby"): (
        "판정 데이터 원천 축 — io.query.devOwned = 유효 ∧ 태그 일치",
        "GUARD-MAP 문면의 값 차단(비소유 적중의 frame/perm 0)과 loud sticky 의 "
        "관측면 도달. 그 둘은 소비쪽(HiuPipeline)에 있고 이 태스크의 top 밖이다",
    ),
    ("Platform", "owner_check", "rtl/formal/sby/HiuMask/hiumask.sby"): (
        "승인 소비 축 — granted ⊆ devOwned · 비소유의 값 차단 · loud sticky",
        "devOwned 값 자체가 옳게 계산된다는 것 (OwnershipTable 앵커의 몫). "
        "이 태스크에서 io_owner_devOwned 는 자유 입력이다",
    ),
    ("Platform", "xlate_local", "rtl/formal/sby/HiuMask/hiumask.sby"): (
        "우선순위 축 — 호스트 leg 은 로컬 미적중일 때만 소비되는 최하 순위",
        "지속 상태 불오염 축 (hostRsp 가 저장 자원 기입 콘에 부재). 2사본 "
        "miter 가 필요하고 아직 착지하지 않았다",
    ),
    # ── 아래 넷: .sby 가 스스로 자백한 좁힘인데 이 표가 못 읽고 있었다 ──
    #
    # 2026-08-26 전수 검증이 잡았다. 넷 다 자기 `.sby` 의 §미측정 잔여 절에
    # 「이 축만 잰다」를 적어 두었는데, 표에 없으면 lint 는 완전 덮임으로
    # 계수한다 — `Platform.owner_check` 가 미끄러진 경로가 정확히 이것이고,
    # 그것을 막으려고 만든 표가 같은 자리에서 넷을 더 놓치고 있었다.
    #
    # 「자백이 있는데 기계가 못 읽는다」는 상태는 자백이 없는 것보다 나쁘다 —
    # 읽는 쪽은 커버리지 숫자를 믿고 `.sby` 주석을 다시 읽지 않기 때문이다.
    ("Isolation", "no_early_forward", "rtl/formal/sby/HiuMask/hiumask.sby"): (
        "시간축 관측형 — 값이 실리는 사이클은 거울 f_v 의 6번째 지점뿐",
        "GUARD-MAP 문면이 주장하는 「s3·s4·s5 운반 레지스터가 io.rsp 에 배선돼 "
        "있지 않다」는 elaborate 시점 사실 자체. 관측형으로 좁혀 재고 있으며, "
        "문면을 시간축으로 개정하거나 STRUCTURAL 로 격하하는 것이 남은 결정이다 "
        "(hiumask.sby §미측정 잔여 ②)",
    ),
    ("Isolation", "query_no_serve", "rtl/formal/sby/HiuMask/hiumask.sby"): (
        "값 축 — 로컬 적중 시 호스트 leg 이 값에 들어가지 못한다",
        "판정 축 — 호스트 응답이 hit 계산에 들어가지 않는다는 것. XlateStore 의 "
        "io.rsp.hit 소유라 이 태스크의 top 밖이다 (hiumask.sby §미측정 잔여 ⑤)",
    ),
    ("Decode", "evict_inline", "rtl/formal/sby/HiuMask/hiumask.sby"): (
        "단계 축 — 대체 궤적도 미적중과 같은 단 수를 밟는다 (축출 단 부재)",
        "기입 축 — 요청 경로가 저장 기입 enable 의 콘에 없다는 것. XlateStore 의 "
        "commitFire 소유이고 다른 가드의 앵커에 위임돼 있다 "
        "(hiumask.sby §미측정 잔여 ④)",
    ),
    ("Payload", "base_from_tag", "rtl/formal/sby/Reassembly/props.sby"): (
        "결속 불변 축 — ctx.base 는 개방 수락에서만 기입되고 조각 경로가 안 건드린다",
        "모델 가드의 앞쪽 절반 — 그 base 값이 *개시 wave 의 ACCTGT 에서 온다*는 "
        "것(b = f(tag)). 디코드 경계 밖이라 이 태스크가 재지 못한다 "
        "(props.sby 가 「좁은 증명이 넓은 모델 가드를 대신한다」로 명기)",
    ),
}

# ── 구조 skip 표 ─────────────────────────────────────────────────────────
#
# ## 왜 이 종류가 필요한가
#
# CHECK 가드 중에는 **주장의 알맹이가 포트·상태의 부재**인 것이 있다.
# 부재는 elaborate 시점 사실이지 트레이스 속성이 아니다. 그것을 단언으로
# 옮기면 이 저장소가 이미 세 번 밟은 공허 3종 중 둘로 곧장 간다:
#   · 존재하지 않는 신호를 참조해 상수 0 wire 로 접힘 (2형)
#   · 폭·연결이 이미 보장하는 명제라 `connect \A 1'1` 로 접힘 (3형)
# 표현 수단이 없으면 통합자는 커버리지를 올리려고 **구조 부재에 억지 단언을
# 세우는 압력**을 받는다. 그것이 정확히 항진명제 생산 경로다.
#
# ## 근거 없는 skip 은 미덮임과 구별되지 않는다
#
# 그래서 이 표의 항목은 산문이 아니라 **기계가 재는 근거**를 든다.
#
# ## 이 검사의 강도 — 「전수」가 아니라 이름 거부목록이다 (정직하게)
#
# 아래 `forbid` 는 *열거한 이름꼴*이 생성물에 나타나지 않음을 잰다. 포트
# 목록 전체를 허용목록으로 잠그지 않으므로, **거부목록에 없는 이름으로 같은
# 기능을 달면 통과한다** — 2026-08-26 실측: `io_oMalCode[3:0]`(원인 코드
# 채널) · `io_oFaultDetail[7:0]` · `io_busy` · `io_probe_valid` 를 각각
# 달아도 전부 통과했다.
#
# 그래도 값어치가 있는 이유: 구조 skip 이 깨지는 *현실적인* 경로는 「그
# 포트를 도로 다는 것」이고 그 이름은 대개 원래 이름이다. 다만 그 한계를
# 적어 두지 않으면 다음 사람이 이 검사를 실제보다 강하게 믿는다 — 검사가
# 무엇을 보는지에 대한 가정이 조용히 틀리는 것이 이 저장소가 세 번 밟은
# 형태다. 더 강하게 하려면 포트 목록 해시(허용목록)로 승격해야 하고,
# 그것은 생성물이 바뀔 때마다 서명을 요구하는 대가를 진다.
#
# 생성 SV 의 포트 선언을 읽어:
#   · `require` 가 **하나 이상** 매치해야 한다 — 「없다」와 「없는 곳을 봤다」를
#     가르는 양성 대조다. 모듈 이름이 틀렸거나 포트 블록 파싱이 깨지면
#     forbid 는 자동으로 0 건이 되어 조용히 통과한다. 그 형태가 바로
#     2026-08-25 의 두 오탐(「측정하지 못했다」를 「0이었다」로 보고)이다.
#   · `forbid` 가 **정확히 0** 건 매치해야 한다 — 이것이 부재 그 자체다.
#     누가 그 포트를 *원래 이름꼴로* 도로 달면 skip 의 전제가 깨지고 이
#     검사가 실패한다 (다른 이름이면 통과한다 — 위 「강도」 절 참조).
#
# 선례: synth/scripts/gen_premap_mul.py 의 verify_provenance — 「증거가
# 현행 소스로 만들어졌는지」를 해시로 잰다. 여기서는 「부재 주장이 현행
# 생성물에서도 참인지」를 포트 목록으로 잰다.
#
# ## `unmeasured` — 「안 잰다」 칸 (2026-08-26, 3차 파도)
#
# 여기까지가 2차 파도의 설계였고, 3차가 그 구멍을 하나 찾았다: **구조 skip 이
# all-or-nothing 이었다.** `_PARTIAL` 은 (재는 축, 안 재는 것) 쌍을 요구하는데
# `_STRUCTURAL` 에는 뒤 칸이 없어서, 「부재 축은 구조이고 *나머지 축은 아직
# 안 쟀다*」인 가드가 「이 가드는 전혀 잴 것이 없다」와 같은 모양으로 기록됐다.
#
# 실물: `Isolation.fill_offpath`. 부재(조회 leg 의 ready/stall 포트)는 구조가
# 맞지만 모델 문면(Isolation.tla 의 **파티션 간 타이밍 부채널**)에는 관측
# 가능한 잔여분이 있다 — `fillPend`/`fillSlot` 만 다른 2사본 miter 의 `advance`
# 단조성. `xlatestore.sby` 가 그 사실을 스스로 적어 두었는데(§모델 문면의
# 잔여분) 표에 칸이 없어 분모에서 통째로 빠졌다. `_PARTIAL` 을 만든 이유와
# 정확히 같은 사고다: **자백이 있는데 기계가 못 읽는 상태는 자백이 없는 것보다
# 나쁘다** — 읽는 쪽은 커버리지 숫자를 믿고 주석을 다시 읽지 않는다.
#
# 그래서 `unmeasured` 를 **필수 칸**으로 둔다. 값은 둘 중 하나다:
#
#   _NOTHING_LEFT + "<어디서 덮이는가 / 왜 없는가>"
#       「부재가 곧 가드의 전부」. 접두가 강제되므로 빈 문자열이나 깜빡한
#       None 과 구별된다 — 뒤의 근거 문면도 비면 실패한다.
#   "<잔여분 서술>"
#       부재는 구조이나 다른 축이 미측정. `_MAX_STRUCTURAL_RESIDUAL` 이
#       건수에 서명을 요구하고, 보고가 그 항목을 매번 인쇄한다.
#
# 축의 합집합이 주장 전체라는 판정은 여기서도 하지 않는다 (`_PARTIAL` 과 같은
# 이유). 기계가 대신하면 같은 함정을 한 겹 더 정교하게 다시 만든다.
_NOTHING_LEFT = "NONE — "

_STRUCTURAL = {
    ("Isolation", "query_offpath"): {
        "kind": "port-absence",
        "module": "HiuPipeline",
        "why": "호스트 질의 *발행* 포트가 없다. io.hostRsp 는 선택 경로가 밀어 "
               "넣는 입력 셋뿐이고, 질의 왕복(query·qwait)에 해당하는 단계·"
               "레지스터가 없다 — 단계열은 s1..s6 여섯으로 닫혀 있다. "
               "관측 가능한 잔여분(「호스트 응답 유무가 단 수를 바꾸지 않는다」)은 "
               "HiuMask 의 Isolation.coh_no_shortcut 앵커가 이미 덮는다 — "
               "거울 f_v 는 io_hostRsp_* 를 일절 보지 않는다.",
        "ref": "rtl/formal/sby/HiuMask/hiumask.sby §미측정 잔여 ①",
        "unmeasured": _NOTHING_LEFT + (
            "모델 문면의 관측 가능한 잔여분(「호스트 응답 유무가 단 수를 "
            "바꾸지 않는다」)이 **다른 가드의 앵커에 이미 서 있다** — HiuMask 의 "
            "Isolation.coh_no_shortcut 이 거울 f_v 로 재고, 그 거울은 "
            "io_hostRsp_* 를 일절 보지 않는다. 부재(질의 발행 포트)와 그 잔여분을 "
            "합치면 가드 문면이 닫힌다"
        ),
        "require": [r"^\s*input\b.*\bio_hostRsp_valid\b"],
        "forbid": [
            (r"^\s*output\b.*\bio_host", "호스트 방향 *출력* 포트 = 질의 발행 경로"),
            (r"\bio_\w*[Qq]uery\w*", "질의 채널 이름"),
            (r"\bio_\w*[Qq]wait\w*", "질의 대기 단계 노출"),
        ],
    },
    ("Isolation", "fill_offpath"): {
        "kind": "port-absence",
        "module": "XlateStore",
        "why": "조회 leg 에 역방향 신호가 없다. lookup 번들은 {valid, part, vpn} "
               "입력뿐이라 채움 상태가 조회 경로에 정지·ready 를 만들 자리가 "
               "구조적으로 없고, fwait 에 해당하는 상태 레지스터도 없다. "
               "응답은 readAsync 조합이며 채움은 값 판정(fillHit)으로만 나타난다.",
        "ref": "rtl/formal/sby/XlateStore/xlatestore.sby",
        # ── 이 표에서 유일하게 잔여분이 있는 항목이다 ──────────────────────
        # 부재는 XlateStore 의 사실이지만 모델 문면은 XlateStore 밖까지 말한다.
        # Isolation.tla:428-429 가 금지하는 것은 「채움이 진행 중이면 트레이스에
        # fwait 가 낀다」 = *파티션 간 타이밍 부채널*이고, 실제 정지는 이 모듈이
        # 아니라 HiuPipeline.scala:334-335 의 missWait/advance 에 있다.
        # 그래서 부재 증명만으로는 가드 문면이 닫히지 않는다.
        "unmeasured": (
            "파티션 간 타이밍 부채널 — 「채움이 정지를 만들지 않는다」의 단조성 "
            "형태(advance_with_fill >= advance_without_fill)를 fillPend/fillSlot "
            "만 다른 2사본 miter 로 재는 것. 정지의 소재가 HiuPipeline "
            "(missWait/advance)이라 이 모듈의 포트 부재로는 닫히지 않는다. "
            "세우려면 GUARD-MAP 소유 파일을 XlateStore.scala 에서 "
            "HiuPipeline.scala 로 옮기거나 문면을 둘로 쪼개야 한다 "
            "(xlatestore.sby §모델 문면의 잔여분 — 그 .sby 가 스스로 적어 둔 것을 "
            "이 칸이 처음으로 기계에 올린다)"
        ),
        "require": [r"^\s*input\b.*\bio_lookup_valid\b"],
        "forbid": [
            (r"^\s*output\b.*\bio_lookup_", "조회 leg 의 역방향 신호(ready/stall)"),
            (r"\bio_\w*[Ff]wait\w*", "채움 대기 단계 노출"),
        ],
    },
    ("Decode", "out_no_reason"): {
        "kind": "port-absence",
        "module": "DecodeWalk",
        "why": "판정 방출면이 1비트 종결 등급뿐이다 — 원인 코드 채널 자체가 "
               "없어 예약값 원본이 승인 경계로 반향될 자리가 없다. 1차 파도가 "
               "이미 「트레이스 속성으로 표현 불가, 방출면 포트 전수 검토로 "
               "갈음」이라 판정했고, 그 판정이 기계에 착지하지 못해 미덮임 "
               "10건에 섞여 있던 것이 이 항목의 유일한 사유였다. "
               "부수 증거로 예약 비트 불투과는 Decode.resv_not_echoed 앵커가 "
               "방출면 전수 등가로 덮는다.",
        "ref": "rtl/formal/sby/DecodeWalk/walk_decode.sby",
        "unmeasured": _NOTHING_LEFT + (
            "가드 문면이 「원인 코드 채널이 없다」 하나이고 그것이 곧 부재다. "
            "예약값 원본의 불투과라는 부수 축은 Decode.resv_not_echoed 앵커가 "
            "방출면 전수 등가로 이미 덮는다 (walk_decode.sby). §5.6 폴딩 규범 "
            "2항의 reason 확장은 이 모듈 밖이며, 확장되면 forbid 정규식이 "
            "그 시점에 실패해 이 skip 을 회수하게 한다"
        ),
        "require": [r"^\s*output\b.*\bio_oMalformed\b"],
        "forbid": [
            (r"^\s*output\b.*\bio_o\w*([Rr]eason|[Cc]ause|[Ww]hy)\w*",
             "원인 코드 채널 이름"),
            (r"^\s*output\s+\w+\s*\[\s*\d+\s*:\s*\d+\s*\]\s*"
             r"io_o(Valid|Malformed|CapAbsent|ExecValid|Fault)\b",
             "판정면 출력의 다비트화 — 등급 비트에 원인을 실을 폭이 생긴다"),
        ],
    },
}


# ── 증인 없는 증명 — 공허의 넷째 결 ──────────────────────────────────────
#
# ## 무엇이 남아 있었는가
#
# 이 저장소가 이름 붙인 공허는 셋이었다 — 하네스 미부착(셀 0) · 줄번호 밀림
# (상수 0 wire) · 항진명제(`connect \A 1'1`). 셋 다 **단언 쪽**의 결이다.
# 넷째는 단언이 아니라 **전제** 쪽에 있다:
#
#     if (P) assert (Q);      P 가 도달 불가능하면 이 단언은 공허하게 참이다.
#
# 셀은 세어지고(3형 검사 통과), 이름도 멀쩡하고(2형 통과), 부착도 됐고(1형
# 통과), 증명도 PASS 다. 앞선 셋의 검출 방법 어느 것도 이것을 잡지 못한다.
# 잡는 것은 **cover 증인** 하나뿐이다 — 「그 전제가 실제로 도달한다」를 궤적
# 으로 보이는 것.
#
# 「증인 없는 증명은 전제가 도달 불가능해서 통과하는 경우를 구분하지 못한다」는
# 규율이 notes-vacuity-detection.md 에 **문장으로** 있었다. 그런데 증거층은
# `unreached > 0` 만 하드 실패시키고 **`cover == 0` 은 조용히 통과**시켰다 —
# 증인이 하나도 없으면 미도달도 0 이라 검사가 자동으로 참이 되는 구조였다.
# 규율이 있는데 기계가 없는 상태이고, 이 저장소가 부록 B.3 에서 이름 붙인
# 「집행되지 않는 규율」의 표본이다. 2026-08-26 3차 파도 직전까지 7개 태스크
# **단언 382개**가 증인 0 으로 서 있었다.
#
# ## 처분: 하드 실패 + 서명된 허용목록 (래칫 0)
#
# 세 선택지를 놓고 골랐다.
#
#   경고        — 가장 약하다. 「집행되지 않는 규율」을 「인쇄되지만 집행되지
#                 않는 규율」로 바꿀 뿐이다. 위 7건이 정확히 그 상태로 오래
#                 서 있었으므로 이 저장소에는 이미 반례가 있다.
#   순수 하드 실패 — 강하지만 **탈출구가 없다.** cover 가 원리적으로 무의미한
#                 태스크가 언젠가 나오면 다음 사람은 규율을 고치는 대신
#                 「아무거나 세는 증인」을 하나 넣는다. 그것은 3형(항진)의
#                 cover 판이고, 검사가 스스로 공허를 생산하게 만드는 설계다.
#   허용목록+래칫 — 아래. 표가 비어 있으므로 **오늘의 동작은 하드 실패와 같다.**
#                 탈출구는 있되 diff 에 남고 래칫이 서명을 요구한다.
#                 `_STRUCTURAL` 과 같은 형태이고, 이 저장소가 이미 검증한 idiom.
#
# ## 「무조건 단언만 있는 태스크」는 면제 사유인가 — **아니다** (실측 근거)
#
# 이 물음이 처분을 가르는 자리였다. 3차 파도의 증인 담당 넷이 각자 담당
# 하네스의 단언을 전수로 읽고 보고했고, 결론이 일치한다:
#
#   · MemOrderGate — 「무조건 단언은 0건이다. 24개 전부가 다섯 전건 부류에 든다」
#   · FabricMerge  — 전건 없는 9건은 one-hot 4 + 등식 5. **등식은 양변이 늘 0 인
#                    세계에서 접힌다** — 문법상 무전건이지 공허 면역이 아니다
#   · RouteMmio    — 무전건 9건 전부 등식. 「이쪽의 도달성 질문이 *배선이 실제로
#                    움직이는가*다」
#   · MmioConfig   — 서로소 단언 120건이 문법상 무전건인데 **실질 전건이 두 겹**
#                    (표가 영원히 공집합이면 「빈 표는 항상 서로소」로 통째 공허)
#
# ⇒ 「전건이 없다」는 「증인이 필요 없다」를 뜻하지 않는다. 무전건 단언의 공허는
#   전건 도달 불가가 아니라 **양변 상수화**로 오는데, 그것을 배제하는 것도
#   결국 「이 신호가 실제로 0 이 아닌 값을 든다」는 궤적 = cover 증인이다.
#   따라서 오늘 시점에 면제가 정당한 태스크는 **하나도 없고**, 표는 비어 있다.
#   비어 있는 표를 두는 것은 미래의 면제를 예상해서가 아니라, 면제가 필요해질 때
#   *규율을 우회하는 대신 서명하는 길*을 남겨 두기 위해서다.
#
# 키: .sby 의 저장소 루트 기준 경로. 값: (근거, 그래도 재는 다른 수단).
_NO_WITNESS = {
    # 비어 있다 — 2026-08-26 실측으로 18/18 태스크가 cover ≥ 1 이다.
    # 항목을 넣으려면 _MAX_NO_WITNESS 를 함께 올려야 한다 (그것이 서명이다).
}
_MAX_NO_WITNESS = 0    # 증인 없이 통과가 허용된 태스크 수. 늘지 않는다.
                       #
                       # 0 인 채로 두는 것이 이 파도의 결론이다. 위 실측이
                       # 「원리적으로 증인이 무의미한 태스크」를 하나도 찾지
                       # 못했으므로, 0 은 과도기 값이 아니라 **판정**이다.

# ── 유도되는 단언 — 항진과 같은가? 아니다 ────────────────────────────────
#
# `Platform.owner_check ②` (HiuMask_props.sv):
#
#     ①  granted → devOwned
#     ②  ¬devOwned → (frame == 0 ∧ ¬perm_*)
#     approve_gates_value  (frame ≠ 0 ∨ perm_*) → granted
#
# ②는 ① 과 approve_gates_value 에서 유도된다 (후자의 대우 + ①의 대우 연쇄).
# 셀 +1 이 새 측정이 아니다. 처분: **유지.** 근거는 반환 보고와
# notes-vacuity-detection.md 에 적었고, 요지는 이것이 *항진과 다른 것*이라는
# 판단이다 —
#
#   항진명제의 공허는 **단언 하나의 성질**이다. `connect \A 1'1` 로 접히면
#   어떤 설계에서도 통과하므로 이 설계에 대해 아무것도 말하지 않는다.
#   ②의 중복은 **단언 집합의 성질**이다. ②는 상수로 접히지 않고
#   (io_owner_devOwned 는 모듈 자유 입력, 우변은 실제 값 버스),
#   ①을 지우면 즉시 독립 반증력을 되찾는다.
#
# 그래서 「셀을 재지 않으므로 지운다」가 아니라 「형제 단언에 의존하는 잉여임을
# 기록하고 둔다」가 옳다. 다만 그 기록이 없으면 다음 사람이 셀 수 23 을 보고
# 23 가지를 쟀다고 읽으므로, 아래 표가 그것을 인쇄한다.
#
# **왜 래칫을 걸지 않는가**: 「②가 ①에서 유도된다」는 명제 자체를 기계가 재지
# 않는다 (재려면 솔버가 필요하고 그것은 하네스 소유다). 내용을 못 재는 표에
# 건수 래칫을 거는 것은 「집행되지 않는 규율」을 숫자로 위장하는 것이고, 이
# 파도가 닫으러 온 형태와 같은 부류다. 표는 **보고용**이며 그 사실을 명기한다.
# 앵커의 실재는 아래 대조가, 하네스 편집은 증거 신선도(sby_sha256)가 잡는다.
_DERIVED = {
    ("Platform", "owner_check", "rtl/formal/sby/HiuMask/hiumask.sby"): (
        "owner_check ② (¬devOwned → 값 차단)",
        "같은 태스크의 ①(granted → devOwned)과 Isolation.approve_gates_value "
        "((값≠0) → granted)에서 유도된다 — 독립 반증력 0. 유지 근거: (a) 상수로 "
        "접히지 않아 항진이 아니다 (b) 형제를 지우면 반증력을 되찾는 backstop "
        "이다 (c) 전건을 devOwned 로 둔 문면이 「자격(entitle)만 다른 경우」와 "
        "갈라 주는 문서적 값을 진다. 비용은 assert 23 중 1셀",
    ),
}


def fail(msg: str) -> None:
    print(f"lint_postformal: FAIL — {msg}", file=sys.stderr)
    sys.exit(1)


def sha256(p: Path) -> str:
    h = hashlib.sha256()
    h.update(p.read_bytes())
    return h.hexdigest()


def model_guards(model: str) -> set:
    p = TLA_DIR / f"{model}.tla"
    if not p.is_file():
        fail(f"PROVES 가 참조한 모델 {model} 의 .tla 가 없다")
    m = re.search(r"AllGuards\s*==\s*\{([^}]*)\}", p.read_text(encoding="utf-8"))
    if not m:
        fail(f"{model}.tla 에서 AllGuards 를 찾지 못했다")
    return set(re.findall(r'"([A-Za-z_]+)"', m.group(1)))


def guard_kinds() -> tuple:
    """GUARD-MAP 줄에서 ({(모델, 가드): kind}, {(모델, 가드): 괄호 인자}).

    분류 규칙은 `lint_guard_map.classify` 하나뿐이다 (import). 넷째 종류
    `STRUCTURAL(<근거 종류>) — <근거>` 와 이 파일의 `_STRUCTURAL` 표는
    **일대일**이어야 한다 — 선언만 있고 기계 근거가 없는 skip 은 미덮임과
    구별되지 않고, 근거만 있고 선언이 없으면 lint_guard_map 이 그것을 CHECK 로
    세어 두 분모가 갈린다. 그 대조는 main() 이 양방향으로 한다.
    """
    kinds, args = {}, {}
    pat = re.compile(r"//\s*GUARD-MAP:\s*([A-Za-z]+)\.([A-Za-z_]+)\s*->\s*(.+)$")
    for f in sorted(RTL_DIR.rglob("*.scala")):
        for line in f.read_text(encoding="utf-8").splitlines():
            m = pat.search(line)
            if not m:
                continue
            key, rhs = (m.group(1), m.group(2)), m.group(3).strip()
            kinds[key] = classify(rhs)
            am = re.match(r"[A-Z]+\(([^)]*)\)", rhs)
            args[key] = am.group(1).strip() if am else ""
    return kinds, args


def sby_files() -> list:
    return sorted(SBY_DIR.rglob("*.sby"))


def sby_anchors(path: Path) -> list:
    """`# PROVES: Model.guard` 앵커 목록 — 파일 순서 그대로."""
    pat = re.compile(r"#\s*PROVES:\s*([A-Za-z]+)\.([A-Za-z_]+)")
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        m = pat.search(line)
        if m:
            out.append(f"{m.group(1)}.{m.group(2)}")
    return out


def sby_inputs(path: Path) -> list:
    """`[files]` 절이 선언한 입력 경로 — 저장소 루트 기준.

    이 파서가 저장소에서 셋째 사본이다 (sby_impact.py · 아래 경로 실재성
    검사와 같은 문법). 사본을 하나 더 만드는 대신 **sby_sweep.sh 가 이
    함수를 호출한다** — 증거의 입력 목록과 lint 의 대조 목록이 같은 코드에서
    나오지 않으면 두 층이 서로 다른 것을 보게 되고, 그것이 정확히
    notes-vacuity-detection.md 가 이름 붙인 「게이트가 자기가 무엇을 세는지
    모른다」의 형태다.
    """
    out, in_files = [], False
    for line in path.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if s.startswith("["):
            in_files = s.lower().startswith("[files]")
            continue
        if not in_files or not s or s.startswith("#"):
            continue
        out.append(s.split()[-1])  # `dst src` 형태도 허용된다
    return out


def evidence_path(sby: Path) -> Path:
    return sby.with_suffix(".evidence.json")


def sv_ports(module: str):
    """생성 SV 에서 모듈의 포트 선언 줄 전수. (줄 목록, 실패 사유)"""
    p = GEN_DIR / f"{module}.sv"
    if not p.is_file():
        return None, f"{p.relative_to(ROOT)} 가 없다"
    txt = p.read_text(encoding="utf-8")
    m = re.search(rf"^module\s+{re.escape(module)}\s*\((.*?)^\);",
                  txt, re.S | re.M)
    if not m:
        return None, f"{p.relative_to(ROOT)} 에서 module {module} 의 포트 블록을 찾지 못했다"
    return m.group(1).splitlines(), None


# ─────────────────────────────────────────────────────────────────────────
# 증거 기록 모드 — sby_sweep.sh 전용
# ─────────────────────────────────────────────────────────────────────────
def emit_evidence(a) -> None:
    sby = Path(a.emit_evidence)
    if not sby.is_file():
        fail(f"--emit-evidence: {sby} 가 없다")
    sby = sby.resolve()  # 호출 cwd 와 무관하게 — 아래 relative_to 가 그것을 요구한다
    rel = sby.relative_to(ROOT).as_posix()
    inputs = {}
    for q in sby_inputs(sby):
        f = ROOT / q
        inputs[q] = sha256(f) if f.is_file() else "MISSING"
    doc = {
        "schema": EVIDENCE_SCHEMA,
        "sby": rel,
        "sby_sha256": sha256(sby),
        "verdict": a.verdict,
        "tasks": a.tasks,
        "cells": {"assert": a.assert_cells, "cover": a.cover_cells},
        "cover": {"reached": a.cover_reached, "unreached": a.cover_unreached},
        "anchors": sby_anchors(sby),
        "inputs": inputs,
        "tool": a.tool,
        "at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    out = evidence_path(sby)
    out.write_text(json.dumps(doc, ensure_ascii=False, indent=2,
                              sort_keys=True) + "\n", encoding="utf-8")
    print(f"evidence: {out.relative_to(ROOT)} ({a.verdict}, "
          f"assert {a.assert_cells} · cover {a.cover_cells}/"
          f"{a.cover_reached} 도달)")


# ─────────────────────────────────────────────────────────────────────────
# 증거 검사
# ─────────────────────────────────────────────────────────────────────────
def check_evidence(files: list):
    """.sby 별 증거 상태. -> (상태 dict, 하드 실패 목록, 경고 목록)"""
    state, hard, warn = {}, [], []
    for f in files:
        rel = f.relative_to(ROOT).as_posix()
        ev = evidence_path(f)
        if not ev.is_file():
            state[rel] = ("미측정", None)
            continue
        try:
            doc = json.loads(ev.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            hard.append(f"{ev.relative_to(ROOT)} 가 JSON 이 아니다 ({e})")
            state[rel] = ("깨짐", None)
            continue
        if doc.get("schema") != EVIDENCE_SCHEMA:
            hard.append(f"{ev.relative_to(ROOT)} 의 schema 가 {EVIDENCE_SCHEMA} 가 "
                        f"아니다 ({doc.get('schema')!r}) — 옛 판을 지금 판으로 읽고 있다")
            state[rel] = ("깨짐", None)
            continue

        verdict = doc.get("verdict")
        # 태스크별 판정에 ERROR 가 있으면 그것이 verdict 보다 정확하다.
        #
        # sby 는 엔진이 죽어도(rc=16 — 「Engine terminated without status」)
        # 0 이 아닌 코드를 낸다. 스윕이 그것을 FAIL 로 접으면 lint 가
        # 「실패한 증명의 앵커는 덮임이 아니다」로 인쇄하고, 독자는 설계를
        # 고치러 간다 — 실제 원인은 z3 프로세스 사망이었는데.
        #
        # 2026-08-26 실측: mmio_deep 의 귀납이 z3 를 70분째 물고 있는 동안
        # OperandDecode 의 basecase 가 「Unexpected EOF response from solver」로
        # 죽었고, 단독 재실행은 PASS 였다. 이것은 **게이트/환경의 결함**이지
        # 대상의 결함이 아니므로 UNCOUNTED 와 같은 부류로 읽는다.
        tasks = str(doc.get("tasks", ""))
        if "ERROR" in tasks:
            hard.append(f"{rel} — 태스크 판정에 ERROR 가 있다 ({tasks}). "
                        f"엔진이 죽은 것이지 증명이 실패한 것이 아니다 — "
                        f"**게이트/환경의 결함**이다. 자원 경합 없이 단독으로 "
                        f"다시 재라: sh scripts/sby_sweep.sh {rel}")
            state[rel] = ("ERROR", doc)
            continue
        if verdict in ("UNCOUNTED", "ERROR"):
            hard.append(f"{rel} — 증거가 {verdict} 다. **게이트의 결함**이지 "
                        f"대상의 결함이 아니다 (셀을 셀 수 없었다). 스윕을 고쳐라")
            state[rel] = (verdict, doc)
            continue
        if verdict == "HOLLOW":
            hard.append(f"{rel} — 증거가 HOLLOW 다. 단언 0개로 통과했다 — "
                        f"PASS 가 아무것도 보증하지 않는다")
            state[rel] = ("HOLLOW", doc)
            continue
        if verdict != "PASS":
            hard.append(f"{rel} — 증거의 판정이 {verdict!r} 다. 실패한 증명의 "
                        f"앵커는 「덮임」이 아니다")
            state[rel] = (str(verdict), doc)
            continue
        cells = doc.get("cells", {})
        if int(cells.get("assert", 0)) + int(cells.get("cover", 0)) <= 0:
            hard.append(f"{rel} — 증거가 PASS 인데 assert/cover 셀이 0 이다 "
                        f"(스윕의 HOLLOW 판정과 증거가 어긋난다)")
            state[rel] = ("HOLLOW", doc)
            continue
        # 증인 계수의 항등 — 「세지 못한 것」과 「0이었던 것」을 가른다.
        #
        # 아래 unreached 검사만 두면 cover 셀 N>0 인데 reached=0·unreached=0 인
        # 증거가 조용히 통과한다. sby 요약 파일 글롭이 어긋나면 정확히 그
        # 모양이 되고 — 이 저장소가 두 번 밟은 「측정하지 못했다를 0이었다로
        # 보고」가 *증거층 안에서* 그대로 재현된다. 셋째 판은 만들지 않는다.
        #
        # 항등이 성립하는 근거: sby 는 cover 태스크의 요약에 모든 cover 문을
        # reached 또는 unreached 로 정확히 한 번씩 인쇄한다. 2026-08-26 전수
        # 실측에서 18/18 성립.
        _cov = int(cells.get("cover", 0))
        _r = int(doc.get("cover", {}).get("reached", 0))
        _u = int(doc.get("cover", {}).get("unreached", 0))
        # 공허의 넷째 결 — 증인이 아예 없는 증명. `_NO_WITNESS` 를 보라.
        #
        # 이 검사가 **아래 두 검사보다 먼저** 서야 한다는 것이 요점이다.
        # cover 셀이 0 이면 reached=0·unreached=0 이라 항등도 성립하고
        # `_u > 0` 도 거짓이라, 순서를 바꾸면 증인 0 인 태스크가 두 검사를
        # 조용히 통과한다 — 검사가 자기 전제의 도달 불가로 공허해지는 것이고,
        # 그것이 정확히 이 검사가 잡으려는 결이다. 검출기가 자기 대상의 병에
        # 걸려 있었던 셈이다.
        if _cov <= 0 and rel not in _NO_WITNESS:
            hard.append(f"{rel} — cover 증인이 0 이다. 단언 "
                        f"{int(cells.get('assert', 0))}건이 증인 없이 서 있다 — "
                        f"전건이 도달 불가능해서 통과하는 경우(공허한 참)를 "
                        f"구분하지 못한다. 증인을 세우거나 "
                        f"lint_postformal._NO_WITNESS 에 근거와 함께 등재하라 "
                        f"(_MAX_NO_WITNESS 서명 필요)")
            state[rel] = ("증인 없음", doc)
            continue
        if _r + _u != _cov:
            hard.append(f"{rel} — cover 셀이 {_cov} 인데 증인 계수는 "
                        f"{_r}+{_u}={_r + _u} 다. 증인을 *세지 못한* 것이지 "
                        f"0 이었던 것이 아니다 — 스윕의 요약 파싱을 고쳐라")
            state[rel] = ("UNCOUNTED", doc)
            continue
        if _u > 0:
            hard.append(f"{rel} — 도달하지 못한 cover 증인이 "
                        f"{doc['cover']['unreached']}건 있다 — 전제가 도달 불가능한 "
                        f"증명을 「덮임」으로 셀 수 없다")
            state[rel] = ("증인 미도달", doc)
            continue

        # 신선도 — fp_op_gate_check 의 provenance 대조와 같은 축.
        drift = []
        if doc.get("sby_sha256") != sha256(f):
            drift.append(".sby 자신이 바뀌었다 (앵커·레시피 드리프트)")
        want = set(sby_inputs(f))
        have = set(doc.get("inputs", {}))
        if want != have:
            drift.append(f"[files] 목록 불일치 (증거에만 {sorted(have - want)} · "
                         f"소스에만 {sorted(want - have)})")
        for q, digest in sorted(doc.get("inputs", {}).items()):
            src = ROOT / q
            if not src.is_file():
                drift.append(f"{q} 가 사라졌다")
            elif sha256(src) != digest:
                drift.append(f"{q} 가 바뀌었다")
        if drift:
            state[rel] = ("stale", doc)
            warn.append(f"{rel} — stale: " + " · ".join(drift[:3])
                        + (" …" if len(drift) > 3 else ""))
        else:
            state[rel] = ("fresh", doc)
    return state, hard, warn


# ─────────────────────────────────────────────────────────────────────────
def main() -> None:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--require-fresh", action="store_true",
                    help="stale·미측정 증거를 실패로 —— 스윕 직후 자기검사용")
    ap.add_argument("--emit-evidence", metavar="SBY",
                    help="증거 파일 기록 (sby_sweep.sh 전용)")
    ap.add_argument("--verdict", default="PASS")
    ap.add_argument("--tasks", default="")
    ap.add_argument("--assert-cells", type=int, default=0)
    ap.add_argument("--cover-cells", type=int, default=0)
    ap.add_argument("--cover-reached", type=int, default=0)
    ap.add_argument("--cover-unreached", type=int, default=0)
    ap.add_argument("--tool", default="")
    a = ap.parse_args()

    if a.emit_evidence:
        emit_evidence(a)
        return

    if not SBY_DIR.is_dir():
        fail(f"{SBY_DIR} 가 없다 — 후-formal 미착지 상태로 이 lint 가 결선됐다면 결선이 이르다")

    files = sby_files()
    if not files:
        fail("*.sby 가 하나도 없다 — 디렉터리만 있는 상태")

    proves = []  # (model, guard, rel)
    for f in files:
        rel = f.relative_to(ROOT).as_posix()
        for anchor in sby_anchors(f):
            model, guard = anchor.split(".", 1)
            proves.append((model, guard, rel))

    kinds, kind_args = guard_kinds()
    known = {}

    def guards_of(model):
        if model not in known:
            known[model] = model_guards(model)
        return known[model]

    for model, guard, rel in proves:
        if guard not in guards_of(model):
            fail(f"{rel} — PROVES 의 {model}.{guard} 는 AllGuards 에 없다")
        k = kinds.get((model, guard))
        if k is None:
            fail(f"{rel} — {model}.{guard} 에 GUARD-MAP 줄이 없다 (주장 없는 증명)")
        if k != "CHECK":
            fail(f"{rel} — {model}.{guard} 는 {k} 다. 증명 주장은 CHECK 에만 선다")

    # [files] 선언의 실재성 — 경로는 *저장소 루트 기준*이 규약이다.
    #
    # 2026-08-24: 10개 .sby 가 `../../../generated/` 를 쓰고 있었다. sby 는
    # [files] 를 *호출 cwd* 로 풀므로, 자기 디렉터리에서 돌린 에이전트는 전부
    # 통과했고 루트에서 돌린 전수 스윕만 FileNotFoundError 로 죽었다. 통과와
    # 실패가 호출 위치에 따라 갈리는 검증은 검증이 아니다.
    bad_paths = [(f.relative_to(ROOT), p) for f in files
                 for p in sby_inputs(f) if not (ROOT / p).is_file()]
    if bad_paths:
        for sby, p in bad_paths:
            print(f"lint_postformal: {sby} 의 [files] 가 없는 파일을 가리킨다: {p}",
                  file=sys.stderr)
        fail("[files] 경로는 저장소 루트 기준이다 — sby 는 호출 cwd 로 푼다")

    covered = {(m, g) for m, g, _ in proves}
    checks = {k for k, v in kinds.items() if v == "CHECK"}

    # ── 구조 skip 대조 ───────────────────────────────────────────────────
    structural = set()
    residual = []          # 잔여분이 남은 구조 skip — (모델, 가드, 서술)
    for key, spec in sorted(_STRUCTURAL.items()):
        model, guard = key
        if guard not in guards_of(model):
            fail(f"구조 skip 표의 {model}.{guard} 가 AllGuards 에 없다 (표 부패)")
        k = kinds.get(key)
        if k is None:
            fail(f"구조 skip 표의 {model}.{guard} 에 GUARD-MAP 줄이 없다")
        # 쌍방 대조의 한쪽 — 표에 있으면 GUARD-MAP 도 STRUCTURAL 이어야 한다.
        # 2026-08-26 이전에는 여기서 CHECK 도 받았고, 그래서 lint_guard_map 이
        # 같은 셋을 CHECK 로 세어 **두 lint 가 다른 분모를 인쇄했다.**
        # 반대쪽(GUARD-MAP 이 STRUCTURAL 인데 표에 없음)은 아래 루프가 잡는다.
        if k != "STRUCTURAL":
            fail(f"구조 skip 표의 {model}.{guard} 가 GUARD-MAP 에서 {k} 다 — "
                 f"RHS 를 `STRUCTURAL({spec['kind']}) — <근거>` 로 승격하라. "
                 f"표만 알고 GUARD-MAP 이 모르면 두 lint 의 분모가 갈린다")
        if key in covered:
            where = [r for m, g, r in proves if (m, g) == key]
            fail(f"{model}.{guard} 는 구조 skip 인데 {where} 가 증명을 주장한다 — "
                 f"둘 중 하나가 거짓이다")
        if not spec.get("why", "").strip():
            fail(f"구조 skip {model}.{guard} 에 근거 문면이 없다 — "
                 f"근거 없는 skip 은 미덮임과 구별되지 않는다")
        if spec["kind"] != "port-absence":
            fail(f"구조 skip {model}.{guard} 의 근거 종류 {spec['kind']!r} 를 "
                 f"기계로 잴 방법이 없다")
        # GUARD-MAP 이 선언한 근거 종류와 표의 종류가 같은가 —
        # `STRUCTURAL(port-absence)` 의 괄호 안이 표의 kind 와 어긋나면
        # 두 문서가 서로 다른 근거를 주장하는 것이다.
        decl = kind_args.get(key, "")
        if decl != spec["kind"]:
            fail(f"구조 skip {model}.{guard} — GUARD-MAP 은 근거 종류를 "
                 f"{decl!r} 로 선언했는데 표는 {spec['kind']!r} 다")
        # ── 「안 잰다」 칸 (필수) ──────────────────────────────────────────
        # 구조 skip 이 all-or-nothing 이던 시절의 구멍을 닫는다. 자세한 근거는
        # `_STRUCTURAL` 머리 주석의 §unmeasured 를 보라.
        if "unmeasured" not in spec:
            fail(f"구조 skip {model}.{guard} 에 `unmeasured` 칸이 없다 — "
                 f"「이 가드는 전혀 잴 것이 없다」와 「부재 축은 구조이고 나머지 "
                 f"축은 아직 안 쟀다」가 구별되지 않는다")
        un = spec["unmeasured"]
        if not isinstance(un, str) or not un.strip():
            fail(f"구조 skip {model}.{guard} 의 `unmeasured` 가 비었다")
        if un.startswith(_NOTHING_LEFT):
            if not un[len(_NOTHING_LEFT):].strip():
                fail(f"구조 skip {model}.{guard} — `unmeasured` 가 "
                     f"{_NOTHING_LEFT!r} 뿐이고 근거 문면이 없다. "
                     f"「잴 것이 없다」는 주장에도 근거가 든다")
        else:
            residual.append((model, guard, un))
        lines, why = sv_ports(spec["module"])
        if lines is None:
            fail(f"구조 skip {model}.{guard} — {why}")
        # 양성 대조가 먼저다. 이것이 없으면 forbid 0건은
        # 「없다」가 아니라 「없는 곳을 봤다」일 수 있다.
        for rx in spec["require"]:
            if not any(re.search(rx, ln) for ln in lines):
                fail(f"구조 skip {model}.{guard} — 양성 대조 {rx!r} 가 "
                     f"{spec['module']} 포트 전수에서 0건이다. 근거를 잴 곳을 "
                     f"잘못 보고 있다 (「측정하지 못했다」이지 「부재」가 아니다)")
        for rx, what in spec["forbid"]:
            hits = [ln.strip() for ln in lines if re.search(rx, ln)]
            if hits:
                fail(f"구조 skip {model}.{guard} 의 전제가 깨졌다 — "
                     f"{spec['module']} 에 {what} 가 생겼다: {hits[:2]}")
        structural.add(key)

    # GUARD-MAP 쪽에 STRUCTURAL 선언만 있고 기계 근거가 없는 경우.
    for key, k in sorted(kinds.items()):
        if k == "STRUCTURAL" and key not in _STRUCTURAL:
            fail(f"{key[0]}.{key[1]} 가 GUARD-MAP 에서 STRUCTURAL 인데 "
                 f"lint_postformal 의 _STRUCTURAL 표에 근거가 없다")

    # ── 부분 덮임 대조 ───────────────────────────────────────────────────
    anchors_by_guard = {}
    for m, g, rel in proves:
        anchors_by_guard.setdefault((m, g), set()).add(rel)
    for (m, g, rel), (axis, gap) in sorted(_PARTIAL.items()):
        if rel not in anchors_by_guard.get((m, g), set()):
            fail(f"부분 덮임 표의 항목 {m}.{g} @ {rel} 이 실재 앵커를 가리키지 "
                 f"않는다 (표 부패 — 앵커가 옮겨졌거나 사라졌다)")
        if not axis.strip() or not gap.strip():
            fail(f"부분 덮임 표의 {m}.{g} @ {rel} 에 축·간극 문면이 비어 있다")
    partial_guards = {
        key for key, rels in anchors_by_guard.items()
        if rels and all((key[0], key[1], r) in _PARTIAL for r in rels)
    }

    # ── 증인 없음 허용목록 · 유도 단언 표의 부패 대조 ────────────────────
    #
    # 두 표 다 「.sby 실재」에 결속한다. 결속하지 않으면 태스크가 사라진 뒤에도
    # 면제가 남고, 그 면제는 아무도 다시 읽지 않는다 (_PARTIAL 이 앵커 실재에
    # 결속된 것과 같은 이유).
    _sby_rels = {f.relative_to(ROOT).as_posix() for f in files}
    for rel, val in sorted(_NO_WITNESS.items()):
        if rel not in _sby_rels:
            fail(f"_NO_WITNESS 표의 {rel} 이 실재하지 않는다 (표 부패)")
        if not isinstance(val, (tuple, list)) or len(val) != 2 or not all(
                isinstance(s, str) and s.strip() for s in val):
            fail(f"_NO_WITNESS 표의 {rel} 에 (근거, 다른 수단) 두 문면이 없다")
    if len(_NO_WITNESS) > _MAX_NO_WITNESS:
        fail(f"증인 없음 래칫 위반 — {len(_NO_WITNESS)} > {_MAX_NO_WITNESS}. "
             f"「증인 없는 증명은 전제가 도달 불가능해서 통과하는 경우를 "
             f"구분하지 못한다」를 면제하려면 서명이 든다")
    for (m, g, rel), val in sorted(_DERIVED.items()):
        if rel not in anchors_by_guard.get((m, g), set()):
            fail(f"_DERIVED 표의 {m}.{g} @ {rel} 이 실재 앵커를 가리키지 않는다 "
                 f"(표 부패 — 앵커가 옮겨졌거나 사라졌다)")
        if not isinstance(val, (tuple, list)) or len(val) != 2 or not all(
                isinstance(s, str) and s.strip() for s in val):
            fail(f"_DERIVED 표의 {m}.{g} @ {rel} 에 (단언, 근거) 두 문면이 없다")

    # ── 계수 ─────────────────────────────────────────────────────────────
    denom = checks - structural
    # covered ⊆ checks 이고 covered ∩ structural = ∅ 은 위 두 검사가 강제한다
    # (증명 주장은 CHECK 에만 · 구조 skip 에 앵커가 서면 실패). 교집합은
    # 그 두 불변식이 깨졌을 때를 위한 방어다.
    covered_checks = covered & denom
    full_guards = covered_checks - partial_guards
    uncovered = sorted(denom - covered_checks)

    if len(covered_checks) < _MIN_COVERED:
        fail(f"커버리지 래칫 위반 — 덮임 {len(covered_checks)} < {_MIN_COVERED}")
    if len(partial_guards) > _MAX_PARTIAL:
        fail(f"부분 덮임 래칫 위반 — {len(partial_guards)} > {_MAX_PARTIAL}. "
             f"부분 증명을 늘리려면 근거와 함께 _MAX_PARTIAL 을 올려라")
    if len(structural) > _MAX_STRUCTURAL:
        fail(f"구조 skip 래칫 위반 — {len(structural)} > {_MAX_STRUCTURAL}. "
             f"구조 skip 남발은 CHECK 분모를 비우는 반대 방향의 부정이다")
    if len(residual) > _MAX_STRUCTURAL_RESIDUAL:
        fail(f"구조 skip 잔여분 래칫 위반 — {len(residual)} > "
             f"{_MAX_STRUCTURAL_RESIDUAL}. 「부재 축은 구조인데 나머지 축은 안 "
             f"쟀다」인 가드가 늘었다: "
             + " · ".join(f"{m}.{g}" for m, g, _ in residual))

    # ── 두 lint 의 분모가 같은가 ─────────────────────────────────────────
    #
    # 4분류 승격 뒤에는 STRUCTURAL 가드가 애초에 CHECK 가 아니므로
    # `checks ∩ structural = ∅` 이고 `denom == checks` 여야 한다. 그 항등이
    # 곧 「lint_guard_map 이 인쇄하는 CHECK 수 = 여기 분모」이며, 위 쌍방
    # 대조가 그것을 지탱한다. 항등이 깨지면 승격이 반쯤 된 상태이므로
    # 두 lint 가 다시 다른 수를 인쇄하기 시작한다 — 조용히 넘기지 않는다.
    if checks & structural:
        fail(f"분모 항등 위반 — CHECK 이면서 구조 skip 인 가드가 있다: "
             + " · ".join(f"{m}.{g}" for m, g in sorted(checks & structural))
             + ". lint_guard_map 과 이 파일의 분모가 갈린다")
    if len(denom) != len(checks):
        fail(f"분모 항등 위반 — 분모 {len(denom)} ≠ CHECK {len(checks)}")

    # ── 증거 층 ──────────────────────────────────────────────────────────
    state, hard, warn = check_evidence(files)
    if hard:
        for h in hard:
            print(f"lint_postformal: 증거 모순 — {h}", file=sys.stderr)
        fail(f"증거가 스스로 결함을 보고한다 ({len(hard)}건) — 통과가 아니다")

    fresh_files = {r for r, (s, _) in state.items() if s == "fresh"}
    stale_files = {r for r, (s, _) in state.items() if s == "stale"}
    none_files = {r for r, (s, _) in state.items() if s == "미측정"}
    evidenced = sum(1 for _, _, r in proves if r in fresh_files or r in stale_files)
    attested = sum(1 for _, _, r in proves if r in fresh_files)

    if evidenced < _MIN_EVIDENCED:
        fail(f"증거 래칫 위반 — 증거로 뒷받침된 앵커 {evidenced} < {_MIN_EVIDENCED}. "
             f"증거 파일을 지우는 편집은 측정을 되돌린다")
    if a.require_fresh and (stale_files or none_files):
        for r in sorted(none_files):
            print(f"lint_postformal: {r} — 증거 미측정", file=sys.stderr)
        for w in warn:
            print(f"lint_postformal: {w}", file=sys.stderr)
        fail(f"--require-fresh — stale {len(stale_files)} · 미측정 "
             f"{len(none_files)}. 스윕 직후라면 이것은 **스윕의 결함**이다")

    # ── 보고 ─────────────────────────────────────────────────────────────
    witnesses = sum(int(d.get("cells", {}).get("cover", 0))
                    for _, d in state.values() if d)
    print(
        f"lint_postformal: OK — PROVES {len(proves)}건 · 후-formal 분모 "
        f"{len(denom)} (= CHECK; 구조 skip {len(structural)} 는 GUARD-MAP 에서 "
        f"이미 갈렸다 — lint_guard_map 과 같은 수) 중 "
        f"완전 덮임 {len(full_guards)} · 부분 덮임 {len(partial_guards)} "
        f"(래칫 덮임≥{_MIN_COVERED} · 부분≤{_MAX_PARTIAL} · "
        f"구조≤{_MAX_STRUCTURAL} · 잔여≤{_MAX_STRUCTURAL_RESIDUAL} · "
        f"증인없음≤{_MAX_NO_WITNESS}) · [files] 경로 실재 · sby {len(files)}파일"
    )
    print(f"  cover 증인: {len(files)}태스크 전수에 {witnesses}건 "
          f"(증인 0 인 태스크 {len(_NO_WITNESS)} — 공허의 넷째 결 게이트)")
    print(
        f"  증거: 앵커 {len(proves)} 중 신선 {attested} · stale "
        f"{evidenced - attested} · 미측정 {len(proves) - evidenced} "
        f"(래칫 ≥{_MIN_EVIDENCED}) — 파일 기준 신선 {len(fresh_files)} · "
        f"stale {len(stale_files)} · 미측정 {len(none_files)}"
    )
    if attested != _MIN_EVIDENCED:
        print(f"  _MIN_EVIDENCED 후보: {attested} (스윕 직후 값으로 올려라)")
    for w in warn:
        print(f"  ⚠ {w}")
    if partial_guards:
        print("  부분 덮임 — 좁은 증명이 넓은 주장을 대신하지 않도록 명기한다:")
        for m, g in sorted(partial_guards):
            for r in sorted(anchors_by_guard[(m, g)]):
                axis, gap = _PARTIAL[(m, g, r)]
                print(f"    {m}.{g} @ {Path(r).parent.name}/{Path(r).name}")
                print(f"      잰다  : {axis}")
                print(f"      안 잰다: {gap}")
    if _DERIVED:
        print("  유도 단언 — 셀은 있으나 독립 반증력이 없다 (보고용 · 래칫 없음):")
        for (m, g, rel), (what, why) in sorted(_DERIVED.items()):
            print(f"    {m}.{g} @ {Path(rel).parent.name}/{Path(rel).name} — {what}")
            print(f"      근거: {why}")
    if structural:
        print("  구조 skip (근거 기계 대조 통과 — GUARD-MAP·표 쌍방 선언):")
        for m, g in sorted(structural):
            spec = _STRUCTURAL[(m, g)]
            print(f"    {m}.{g} — {spec['kind']} @ {spec['module']}.sv · {spec['ref']}")
            un = spec["unmeasured"]
            if un.startswith(_NOTHING_LEFT):
                print(f"      안 잰다: 없음 — {un[len(_NOTHING_LEFT):]}")
            else:
                print(f"      ⚠ 안 잰다: {un}")
    if residual:
        print(f"  ⚠ 구조 skip 잔여분 {len(residual)}건 (≤{_MAX_STRUCTURAL_RESIDUAL}) — "
              f"부재 축은 구조이나 나머지 축이 미측정이다: "
              + " · ".join(f"{m}.{g}" for m, g, _ in residual))
    if uncovered:
        print(f"  미덮임 CHECK {len(uncovered)}건 (후속 파도 대상): "
              + " · ".join(f"{m}.{g}" for m, g in uncovered[:8])
              + (" …" if len(uncovered) > 8 else ""))


if __name__ == "__main__":
    main()
