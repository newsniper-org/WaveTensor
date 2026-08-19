#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
r"""lint_estimate_index.py — spec §39.2 CI lint: **추정치 색인의 기계 집행**.

무엇이 새어 나갔는가 (이 파일이 생긴 이유)
------------------------------------------
이 저장소는 자기 추정치를 성실하게 적어 왔다 — "hand-count 추정이고 합성
실측이 아니다", "지금 없는 수치를 만들지 않는다", "gate 판정 근거로 인용하지
마라". 그런데 **그 성실함을 지키는 것이 아무것도 없었다.** 실측이 추정 대역을
전부 하회했는데 원 추정 줄에 supersede 배너가 붙지 않은 채 남고(§27.6),
"ESTIMATE 실측 졸업" 배너가 붙었는데 정작 졸업한 것은 문장의 절반뿐이고
나머지 수치는 4× 빗나간 채로 있고(§27.2 ↔ §27.6), 체커 상수는 실측과 다른
값을 들고 파생 줄에 틀린 수를 인쇄한다(§28.10). 전부 **사람이 기억해야
지켜지는** 형태였고, 이 저장소에서 그 형태는 예외 없이 조용히 무너졌다.

**산문 스캐너를 hard FAIL 로 쓰지 않는 이유 (실측, spec §39.2.1)**
------------------------------------------------------------------
초안은 `~N` / `추정` / `nominal` 류 고정밀 검출기 12종의 union 을 래칫하는
설계였다. 실측하고 폐기했다:

  * naive `grep 약` 오탐률 **96.9%** (HEAD `30b2202` 실측 414 중 진성
    `약\s+[0-9]` 13 — 오탐은 `계약`/`제약`/`예약`/`약화`/`약속`/`규약`/`요약`).
    (초판은 "98.3% — 413 중 13" 이라 적었다. 98.3% 는 진성을 `' 약 '`
    양쪽-공백 정의로 셌을 때의 값(7)이고 13 은 `약\s+[0-9]` 정의의 값이라
    **한 셀 안에 두 정의가 섞여 있었다.** spec §39.5 항 7.)
  * 고정밀 union 은 spec 7,605줄에서 **290줄**. 그런데 HEAD `30b2202` 하나가
    그 union 을 **+31줄** 늘렸고 그중 진성 신규 추정치는 **약 3건**이다
    (나머지는 "예상 빗나감" / "예상 적중" / "크기 예상 안 함" 같은 **추정치에
    대한 서술**, 버전 범위 `v1.0~1.2`, 확률 `~2^-24`, 백분율 산문).
  * 최근 13개 spec commit 중 **9개**가 union 을 증가시켰다.

즉 이 저장소는 자기 예상을 기록하고 대조하는 것을 규율로 삼기 때문에
**규율을 지킬수록 산문 검출기가 더 시끄러워진다.** 그런 검사를 merge-blocker
로 걸면 spec 을 정직하게 쓸 때마다 lint 가 깨지고, 사람은 lint 를 끈다 —
그것이 최악의 결과다. 그래서 산문 스캔은 **advisory 카운터**로만 출력하고,
집행은 아래 선언표와 anchor 실재에 건다.

검사 규칙
---------
  A. **anchor(위치) + value(수치) 실재** — 색인의 모든 항목이 `anchor` (대상
     파일의 축자 부분문자열) 로 **정확히 1회** 실재해야 한다. 0회 = 색인이
     stale. 2회 이상 = anchor 가 모호해 다음 편집에서 조용히 엉뚱한 줄을
     가리키게 된다. **줄번호를 anchor 로 쓰지 않는다** — spec 은 계속 자라므로
     줄번호 anchor 는 첫 커밋에 죽는다.

     추가로 **`value` (수치 pin)** 가 있다. anchor 가 절 제목이거나 숫자를 한
     자도 포함하지 않으면 `value` 는 **필수**이고, 역시 정확히 1회 실재해야
     한다. 이유는 실측이다 — 초판은 anchor 하나로 위치와 수치를 겸했는데,
     37 항목 중 **절 제목 anchor 7건 + 무숫자 anchor 5건 = 12건**에서 그
     anchor 는 "절이 사라졌는가" 만 쟀다. 변이 MUT-X 가 §18.8(EI-01)의 추정치
     **3줄을 전부 지우고 절 제목만 남겼는데 EXIT 0 으로 통과**했다. 반대로
     실수치가 anchor 인 항목은 한 글자만 바꿔도 죽었다 — 검출력이 anchor
     종류에 따라 갈렸고 "anchor 실재 37/37" 이라는 통과 메시지가 그 편차를
     균질한 것처럼 보이게 했다.
  B. **ID 양방향 정합** — 선언표의 모든 ID 가 spec **§39.2.3 구역 안에**
     `| **EI-NN** |` **행 형태**로 있어야 하고, spec 에 등장하는 모든 `EI-NN`
     토큰이 선언표에 있어야 한다. 한쪽만 고치면 FAIL 한다 — spec-first
     순서(§12a 규칙 3)가 관례가 아니라 검사가 되는 지점이다.

     **구역 한정**이 붙은 것도 변이 때문이다 (MUT-D): 행 형태만 요구하고
     구역을 보지 않으면 본표의 행을 **§39.1 의 다른 표로 옮겨도** 통과한다.
     §39.1 과 §39.2.3 이 같은 파일에서 같은 `| **XX-NN** |` 문법을 쓰므로
     절 재편·표 병합에서 조용히 성립할 수 있다.
  C. **졸업 근거 실재 (강화)** — `graduated` 항목은 `evidence` **와**
     `evidence_file` 이 둘 다 필수이고, `evidence` 는 길이 ≥12 이며 그
     파일에 **정확히 1회** 실재해야 한다. `graduation` (승격 요건) 문자열은
     **status 와 무관하게 전건 필수**다 — 졸업한 항목에서는 "무엇이 졸업
     요건이었는가" 의 기록이 된다.

     초판은 (i) `evidence` 가 파일 경로면 `Path.exists()` 만, 문자열이면
     `in` 포함만 검사했고 (ii) 길이 하한도 유일성도 없었으며 (iii)
     `graduation` 을 미졸업에만 요구했다. 그래서 변이 MUT-E(`evidence` 를
     저장소의 **무관한 다른 파일**로 교체)와 MUT-F(미측정 항목을
     `graduated` 로 뒤집고 `evidence` 에 아무 파일 이름을 넣고 `graduation`
     을 지움) 가 **둘 다 EXIT 0 으로 통과**했다. MUT-F 는 더 나빴다 —
     `unmeasured` 래칫이 5→4 로 **내려가서** 거짓 졸업이 벌이 아니라 상이
     됐다. docstring 이 인용하는 premap `$mul` 사고의 본질은 "증거 파일이
     없다" 가 아니라 **"증거가 그 주장을 뒷받침하지 않는다"** 였으므로,
     초판의 검사는 인용한 선례를 그대로 재현했다.
  D. **인용 금지 집행** — `forbid_in` 을 든 항목의 수치가 gate 판정
     스크립트에 등장하면 FAIL. §35.5.4 의 *"gate 판정 근거로 인용하지 마라"*
     를 산문에서 검사로 옮긴 것이다.
  E. **래칫** — `estimate` / `derived` / `unmeasured` / `mismatch` /
     `pre-announced` 개수가 아래 상한을 넘으면 FAIL. **오탐 0** — 산문이
     아니라 선언 항목을 세기 때문이다. 졸업이 상한을 내린다.
  F. **소리내기** — 미졸업 전건을 매 실행 stdout 에 열거한다. 통과해도
     침묵하지 않는다 (loud-fault-never-silent).
  G. **선언 집계 정합** — spec §39 의 표를 **실제로 파싱해서** 머리표·집계
     문장의 숫자와 대조한다: §39.1.1 D 행 수 · §39.1.2 M 행 수 · §39.2.3
     EI 행 수 · §39.3 의 총행수와 ✅/⚠️/❌ 분포. **집계를 거는 문장 자체가
     사라져도 FAIL** 한다 (검사가 조용히 무효화되는 경로 봉쇄).

     이 불변식이 생긴 이유: 초판 §39.3 의 집계 문장이 *"총 56행 — ✅ 22 /
     ⚠️ 20 / ❌ 14"* 였는데 실제 표는 **✅ 25 / ⚠️ 19 / ❌ 12** 였다. 세 숫자
     중 둘이 틀렸고, 매트릭스는 자기 존재 이유가 "정확한 집계" 인 산출물이며,
     §39.3 머리말이 스스로 "기계 집행: 없음" 이라 적었으므로 잡을 것이
     없었다. §39.3.5 항 1 이 규탄한 "수치를 재지 않고 전사" 와 같은 형태다.

Exit 0 = A~E, G 위반 없음. Exit 1 = 위반.
"""

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SPEC = ".claude-memos/wt64v1_spec.md"
ECP5_GATE = "synth/lattice/fp_ops/gate_check.py"
SYNTH_COV = "scripts/lint_synth_coverage.py"

# spec §39.2.3 본표가 사는 파일 — ID 양방향 대조의 상대편.
ID_MIRROR = SPEC

# ---------------------------------------------------------------------------
# 래칫 상한 — 낮추는 편집만 정당하다. 올리려면 그 자체가 리뷰 대상이다.
# §12a 규칙 6 (j) 선례: 항목이 졸업하면 상한도 같이 내린다. 남겨 두면 다음
# 추정치가 조용히 그 자리를 채운다.
#
# 착지 시점(2026-08-19, spec §39.2.3) 실측치와 동일하게 SET 한다.
# ---------------------------------------------------------------------------
EST_MAX = 14          # status="estimate"
DERIVED_MAX = 3       # status="derived"
UNMEASURED_MAX = 5    # status="unmeasured" — 측정하지 않았음이 명시된 것
# 7 → 8 (2026-08-19, spec §39.5 항 9). **래칫을 올린 편집이므로 사유를 남긴다.**
# 초판 색인이 §22.8 의 `~180 MHz` 기준 clock 을 빠뜨렸다 — 실측 10.85 MHz 대비
# **16.6× 빗나감**으로 등재된 MISMATCH 중 최대인데(기존 최대는 EI-18 의 4×)
# 미등재였다. 상한을 올린 것은 새 어긋남이 생겨서가 아니라 **이미 있던 어긋남을
# 이제 세기 때문**이다. 세지 않아서 낮았던 상한은 방어가 아니라 착시다.
MISMATCH_MAX = 8      # status="mismatch" — 실측과 문서/스크립트가 어긋난 것
PRE_MAX = 2           # status="pre-announced" 중 미해소

VALID_STATUS = ("estimate", "derived", "pre-announced", "graduated",
                "unmeasured", "mismatch")
UNGRADUATED = ("estimate", "derived", "pre-announced", "unmeasured",
               "mismatch")

# ---------------------------------------------------------------------------
# 추정치 선언표 (spec §39.2.3 이 사람이 읽는 면, 이 표가 정본)
#
#   file        — anchor 가 실재해야 하는 파일 (repo 상대 경로)
#   anchor      — 그 파일의 **축자 부분문자열** (위치 pin). 정확히 1회 실재.
#   value       — **수치 pin**. 추정치 그 자체를 담은 축자 부분문자열이며 역시
#                 정확히 1회 실재해야 한다. anchor 가 절 제목이거나 숫자를 한
#                 자도 포함하지 않으면 **필수**. anchor 가 이미 수치를 담고
#                 있으면 생략 가능 (그 경우 anchor 가 수치 pin 을 겸한다).
#   what        — 무엇의 수치인가 (사람용)
#   spec        — spec 절 번호 (사람용)
#   status      — VALID_STATUS 중 하나
#   graduation  — 승격 요건. **전건 필수** (졸업 항목에서는 "무엇이 요건이었나"
#                 의 기록이 된다 — 졸업하면서 요건을 지우면 무엇을 근거로
#                 졸업했는지가 사라진다)
#   evidence    — 졸업 근거의 **축자 문자열** (길이 ≥12). graduated 에 필수
#   evidence_file — evidence 가 정확히 1회 실재해야 하는 파일. graduated 에 필수
#   forbid_in   — [(파일, 등장해서는 안 되는 문자열), ...] 인용 금지 집행
# ---------------------------------------------------------------------------
ESTIMATE_INDEX = {
    # --- Cluster/PE feature 단위 hand-count (전부 같은 승격 요건) ---------
    "EI-01": {
        "value": "**총 ~1.5-2K LUT + 1K FF / Cluster**",
        "file": SPEC, "anchor": "### 18.8 하드웨어 비용 (LFE5U-85F 예상)",
        "what": "Cluster fragment buffer FF/LUT", "spec": "§18.8",
        "status": "estimate",
        "graduation": "ECP5 Cluster 합성에서 fragment-buffer cone 만 귀속 "
                      "분리. 현재 어느 측정도 이 단위로 분해하지 않는다.",
    },
    "EI-02": {
        "value": "**총 ~2K FF + 200 LUT / Cluster**",
        "file": SPEC, "anchor": "### 19.8 하드웨어 비용 증분 (LFE5U-85F 추정)",
        "what": "wide mux/latch 증분", "spec": "§19.8", "status": "estimate",
        "graduation": "EI-01 과 동일 — feature 단위 귀속 분해.",
    },
    "EI-03": {
        "value": "~990 LUT + 153 FF / PE_Core (MU 인스턴스)",
        "file": SPEC, "anchor": "### 20.11 HW 비용 (LFE5U-85F 추정)",
        "what": "8-way 확장 LUT/FF", "spec": "§20.11", "status": "estimate",
        "graduation": "EI-01 과 동일 — feature 단위 귀속 분해. 단가 자체가 "
                      "추정인 곱셈 결과가 굵게 강조돼 실측처럼 읽힌다.",
    },
    "EI-04": {
        "value": "총 **~90 LUT / Cluster**",
        "file": SPEC, "anchor": "### 21.5 HW 비용 증분 (LFE5U-85F 추정)",
        "what": "소형 증분 LUT", "spec": "§21.5", "status": "estimate",
        "graduation": "EI-01 과 동일 — feature 단위 귀속 분해.",
    },
    "EI-05": {
        "file": SPEC,
        "anchor": "~200-250 LUT (priority encoder ~50 + LUT ROM ~40",
        "what": "rsqrt LUT 내역 4분할", "spec": "§22.13", "status": "estimate",
        "graduation": "per-operator synth (rsqrt cone 단독 OOC).",
    },
    "EI-06": {
        "value": "총 **~360-510 LUT / Cluster**",
        "file": SPEC, "anchor": "#### 22.14d HW 비용 (LFE5U-85F 추정)",
        "what": "0x67 계열 증분", "spec": "§22.14d", "status": "estimate",
        "graduation": "EI-01 과 동일 — feature 단위 귀속 분해.",
    },
    "EI-07": {
        "value": "Q8.8 곱셈 array ~2.2-2.9× Q4.4 baseline",
        "file": SPEC, "anchor": "hand-count 추정치, 실제 synthesis 미검증",
        "what": "Q8.8 array 배수", "spec": "§22.14e", "status": "estimate",
        "graduation": "0x69 per-operator synth. 원문이 미검증을 자기명기.",
    },
    "EI-08": {
        "value": "≈ **~4664 FF** (순증 ~3539",
        "file": SPEC,
        "anchor": "모든 FF/LUT 수치는 hand-count 추정, 실제 synthesis 검증 필요",
        "what": "FRAG_SLOTS=4 FF/LUT", "spec": "§22.16.5", "status": "estimate",
        "graduation": "FRAG_SLOTS=4 빌드 OOC 합성. 비트 합산이 정확해도 FF "
                      "수는 매퍼가 정한다 — 산술의 정확성이 결과의 "
                      "정확성이 아니다.",
    },
    "EI-09": {
        "value": "nominal **+636** = 33,725 (**40.32%**)",
        "file": SPEC,
        "anchor": "위 LUT 수치는 **hand-count 추정**이고 합성 실측이 아니다",
        "what": "22.14b-5 델타 예측 (breach 예상)", "spec": "§22.14b-5",
        "status": "estimate",
        "graduation": "22.14b-5 착지 후 ECP5 full-Cluster 재합성. "
                      "**breach 가 예상으로 기록돼 있고 아직 미측정이다.**",
    },
    "EI-10": {
        "file": SPEC, "anchor": "FMA-capable wide adder (500-900 LUT4 책정)",
        "what": "wide fp32 adder LUT4 책정", "spec": "§23.10.2",
        "status": "estimate", "graduation": "GATE 2 (per-operator synth).",
    },

    # --- 프로젝트 상수로 승격된 유도값 -----------------------------------
    "EI-11": {
        "value": "(Gate 3: 3,345/2,000 = **1.67×**)",
        "file": SPEC, "anchor": "이 project 의 실측 overrun 계수",
        "what": "overrun 계수 1.67× 자체", "spec": "§23.10.10(g) 및 전역",
        "status": "derived",
        "graduation": "표본 n=1 (3,345/2,000) 의 실측 비율이 프로젝트 "
                      "상수로 승격돼 최소 6개 gate 의 ceiling 을 결정한다. "
                      "실측인가(측정된 비율) 추정인가(1 표본의 일반화) 의 "
                      "분류는 spec §39.4 이월 4 — 사용자 판단 사항.",
    },
    "EI-24": {
        "file": SPEC,
        "anchor": "anchor 14,850 × 1.67 = 24,799.5 → floor 24,799",
        "what": "GATE S1 ceiling 도출식", "spec": "§28.5", "status": "derived",
        "graduation": "binding 수치인데 도출 입력의 한쪽이 EI-11 이다. "
                      "EI-11 분류가 정해지면 이 항목도 함께 정해진다.",
    },
    "EI-25": {
        "file": SPEC, "anchor": "실 FF 는 14 → 16, **+2 FF**",
        "what": "one-hot FSM FF 증분", "spec": "§29.3 항 5",
        "status": "derived",
        "graduation": "원문이 '추정이 아니라 관측에서 도출' 이라고 스스로 "
                      "정확히 라벨한 모범 사례이고 재측정 확인 의무도 "
                      "명기했다. 다음 HIU 재합성에서 실측 대조.",
    },

    # --- 미졸업 EST ------------------------------------------------------
    "EI-12": {
        "file": SPEC, "anchor": "**OPS_DEQ L=6-7 은 ESTIMATE**",
        "what": "OPS_DEQ latency L", "spec": "§25.2/§25.4/§25.7",
        "status": "estimate",
        "graduation": "C-gate TB 의 L 실측. 미졸업이며 cut-ladder rung 3 "
                      "발동 조건이 여기에 매달려 있다.",
    },
    "EI-13": {
        "value": "10.93 MHz (91.5 ns/cy) 기준; 공식 = N_lanes × (L+1) + 고정 ~3",
        "file": SPEC,
        "anchor": "### 25.4 cycle maxima 표 (normative — 추정→실측 졸업 규율)",
        "what": "cycle maxima 표 전 행", "spec": "§25.4", "status": "estimate",
        "graduation": "절 제목이 졸업 규율을 약속하고 C-gate TB 에서 "
                      "estimate→measured 로 졸업하겠다고 적었는데 "
                      "**cycle 행의 졸업 기록이 spec 어디에도 없다.**",
    },
    "EI-15": {
        "file": SPEC, "anchor": "추정 조합 깊이: stage 1 은 case-select mux",
        "what": "stage1/stage2 조합 깊이", "spec": "§26.3",
        "status": "estimate",
        "graduation": "mux 깊이만 GATE V9-3 로 졸업했다. 가산 트리 레벨과 "
                      "cheap opcode 개수는 미졸업 — 넷리스트 경로 census.",
    },
    "EI-22": {
        "value": "nominal 500-900 → × 1.67 = 835-1,503 → worst **1,503** 채택",
        "file": SPEC, "anchor": "glue nominal 성분 (전부 ESTIMATE",
        "what": "V20-3 glue 성분", "spec": "§27.6", "status": "estimate",
        "graduation": "GATE V20-3 총계는 PASS 했으나 glue 성분의 귀속 "
                      "분해를 하지 않았다 — 계층 리포트 귀속.",
    },

    # --- 선공표 (PRE) ----------------------------------------------------
    "EI-16": {
        "file": SPEC, "anchor": "**목표 17.0 MHz**",
        "what": "GATE V9-4 Fmax 목표/floor/stretch", "spec": "§26.6",
        "status": "pre-announced",
        "graduation": "실측 11.34 MHz 로 floor 미달 FAIL 이 확정됐고 "
                      "예상은 규율대로 수정 없이 병존한다. 남은 것은 "
                      "**처분**이며 그것이 미해소다 — spec §39.3.4 D8. "
                      "V9-4 를 집행하는 체커가 두 gate 스크립트 어디에도 "
                      "없다는 것이 이 항목의 실체다.",
    },
    "EI-30": {
        "file": SPEC, "anchor": "`limit 4,909` 를 **넘길 가능성이 실재한다**",
        "what": "ECP5 C3 LUT4 상한 초과 가능성", "spec": "§35.4",
        "status": "pre-announced",
        "graduation": "M-02 (아카이브 재실행) 실행. 초과 시 처분은 D-15 이고 "
                      "**측정 전에** 정해야 한다 — 측정 후에 고르면 기준 "
                      "완화로 읽힌다.",
    },

    # --- 명시적 미측정 ---------------------------------------------------
    "EI-26": {
        "file": SPEC, "anchor": "4-way set-associative 중간안은 측정하지 않았다",
        "what": "4-way set-assoc TLB 비용", "spec": "§29.3",
        "status": "unmeasured",
        "graduation": "M-09 — 합성 1회. 발동 조건은 associativity 재협상이며 "
                      "현재 그 결정은 열려 있지 않다.",
    },
    "EI-27": {
        "file": SPEC,
        "anchor": "D8 수리의 LUT/FF 영향은 **측정하지 않았다.**",
        "what": "D8 수리 면적 영향", "spec": "§29.9/§30.9",
        "status": "unmeasured",
        "graduation": "넷리스트 cell census. 부호조차 미정이라고 원문이 "
                      "명기했다.",
    },
    "EI-29": {
        "file": SPEC,
        "anchor": "§28.8 실측 DSP48 310 에서 **~760 으로 외삽**된다",
        "what": "Tensor_ALU 정답 구현 DSP48 외삽", "spec": "§31.7",
        "status": "unmeasured",
        "graduation": "**영구 불가** — 모듈이 C-2 에서 폐기됐다. 이 항목은 "
                      "닫히지 않고 '측정될 수 없음' 으로 색인에 남는다. "
                      "지우면 '그때도 없었다' 로 읽힌다 (§12a 규칙 5).",
    },
    "EI-31": {
        "file": SPEC, "anchor": "ingress ≈ 410-610 LUT / ≈ 1,030 FF",
        "what": "ingress LUT/FF 산정치", "spec": "§35.5.4",
        "status": "unmeasured",
        "graduation": "M-01 (Cluster/Pod OOC MEASUREMENT). 이 저장소에서 "
                      "가장 오래 열려 있는 미측정 추정치이고, §36.2.2(b) 가 "
                      "ingress 의 전면 DCE 를 실측 확정했으므로 이 측정 없이 "
                      "ingress 면적을 재는 gate 는 존재하지 않는다.",
        # 불변식 D — 원문이 "gate 판정 근거로 인용하지 마라" 를 명시했다.
        "forbid_in": [("synth/scripts/fp_op_gate_check.py", "410-610"),
                      (ECP5_GATE, "410-610")],
    },
    "EI-34": {
        "file": SPEC, "anchor": "| MUL (0x12) | **8** (= 6 +2, 아래 (a)) |",
        "what": "§5 latency 표 MUL/DIV/DIVMOD", "spec": "§5.2",
        "status": "unmeasured",
        "graduation": "M-06 — 경계 A·B·C directed cocotb. §26.3-26.4 로 "
                      "재유도 불가가 확정됐고 spec 이 추측값 전사를 "
                      "금지한다. 선행 종속: §22.14b-5 rung 2 발동 시 경계 C "
                      "전 행이 균일 +1 되므로 §22.14b 착지 이후.",
    },

    # --- 졸업 (GRAD) — evidence 실재를 검사한다 --------------------------
    "EI-14": {
        "file": SPEC, "anchor": "사전 도출 예측(2,800×1.67=39.86%)과 정확히 일치",
        "what": "0e 최악 nominal 도출", "spec": "§25.5.1",
        "status": "graduated",
        "evidence": "| TRELLIS_COMB | 37.76% | **39.86%** (33,335) | ≤40.0% |",
        "evidence_file": SPEC,
        "graduation": "요건이었던 것: 0e 최악 nominal 을 cluster COMB 실측과 "
                      "대조. 사전 도출 예측 2,800×1.67=39.86% 가 실측과 "
                      "정확히 일치해 졸업했다. 성분 표의 각 행은 미졸업.",
    },
    "EI-17": {
        "file": SPEC, "anchor": "nominal 신규 COMB 추정 300-600 LUT",
        "what": "V9-4 COMB nominal", "spec": "§26.6", "status": "graduated",
        # 초판 evidence 는 `"39.56%"` (6자) 였고 spec 에 **4회** 등장해 어느 줄을
        # 가리키는지 확정되지 않았다 — 유일성도 길이 하한도 없던 시절의 잔재다.
        # §26.6 gate 표 행 전체로 교체해 정확히 1회로 만든다 (spec §39.5 항 2).
        "evidence": "| **COMB** | **39.56%** (33,089/83,640) | "
                    "≤40.0% (33,456) | PASS",
        "evidence_file": SPEC,
        "graduation": "요건이었던 것: GATE V9-4 의 COMB 축 실측. nominal 신규 "
                      "COMB 추정 300-600 LUT 에 대해 실측 39.56% "
                      "(33,089/83,640) 로 gate 통과가 확정돼 졸업했다.",
    },
    "EI-20": {
        "file": SPEC, "anchor": "barrel 은 추정 ~336 대비 실측 188",
        "what": "barrel 성분 추정", "spec": "§27.6 R2", "status": "graduated",
        "evidence": "demux 512 + barrel 188 + decode 63", "evidence_file": SPEC,
        "graduation": "요건이었던 것: barrel 성분의 귀속 실측. '배치는 과대, "
                      "tree 는 과소' 로 **정정 졸업**했다 — 빗나감을 지우지 "
                      "않고 방향까지 명기한 형식이 이 항목의 값이다.",
    },
    "EI-28": {
        "file": SPEC, "anchor": "**≈ 14,872** (+22)",
        "what": "§29 LUT 예측 + premap 예측", "spec": "§29.11",
        "status": "graduated",
        "evidence": '"premap_mul_expect": 381',
        "evidence_file": "synth/scripts/fp_op_gate_check.py",
        "graduation": "요건이었던 것: §29 LUT 예측과 premap 예측의 실측 대조 "
                      "+ 재anchor 3요건(측정 이전 공표 · 넷리스트 귀속 · "
                      "사용자 승인). 실측 14,984 / 381 로 전건 이행 졸업.",
    },
    "EI-32": {
        "value": "| 1 | **LUT** | cells 3,809 / sites 3,277 |",
        "file": SPEC, "anchor": "#### 35.5.2 8축 예상표 (측정 **전** 공표",
        "what": "GATE V20-4 8축 선공표", "spec": "§35.5.2",
        "status": "graduated",
        "evidence": "예상 빗나감 3 건을 예상 옆에 남겼다", "evidence_file": SPEC,
        "graduation": "요건이었던 것: 8축 전부에 실측을 채우고 빗나감을 예상 "
                      "옆에 병존시킬 것. 전건 채워졌고 빗나감 3건이 수정 없이 "
                      "병존한다 — **형식의 모범**.",
    },
    "EI-33": {
        "file": SPEC, "anchor": "≤ 6,009 / ≤ 5,477 (binding)",
        "what": "V20-4 LUT cells/sites 상한", "spec": "§35.5.1",
        "status": "graduated",
        # 초판 evidence 는 **경로 문자열 하나**(`Path.exists()` 만 검사)라
        # 저장소의 아무 파일 이름으로 바꿔도 통과했다 (변이 MUT-E). 실제 상한
        # 상수를 축자로 pin 한다 — 상수가 움직이면 졸업 근거가 죽는다.
        "evidence": '"max_lut_cells": 6009',
        "evidence_file": "synth/scripts/fp_op_gate_check.py",
        "graduation": "요건이었던 것: 선공표 상한 cells ≤6,009 / sites ≤5,477 "
                      "에 대한 실측. §36.1 실측 5,137 / 4,572 로 두 축 PASS 하여 "
                      "졸업했고 상한 상수는 체커에 그대로 살아 있다.",
    },

    # --- MISMATCH — 실측과 문서/스크립트가 어긋나 있는 것 ----------------
    "EI-18": {
        "file": SPEC, "anchor": "~66 CARRY8, ~4 ns; ECP5: 9-cycle serial",
        "what": "resolve CARRY8 / 지연", "spec": "§27.2", "status": "mismatch",
        "graduation": "'ESTIMATE 실측 졸업' 배너는 붙었으나 **졸업한 것은 "
                      "resolve 1 cycle 이고 CARRY8 수치는 4× 빗나갔다** "
                      "(실측 265). 빗나감을 §35.5.2 형식으로 예상 옆에 "
                      "남기는 편집이 승격 요건이다. anchor 입도 문제의 "
                      "실물 — spec §39.4 이월 4(ii).",
    },
    "EI-19": {
        "file": SPEC, "anchor": "nominal **8-12k LUT + 2-3k FF/cluster**",
        "what": "v2.0 cluster nominal + ceiling 도출", "spec": "§27.6",
        "status": "mismatch",
        "graduation": "실측 53,418 = ceiling 의 2.67×. (A) 채택 후 N=8 "
                      "재실측은 PASS 이나 **원 nominal 의 도출 artifact 가 "
                      "spec 에 없다** (자백 있음). 도출을 복원하거나 "
                      "복원 불가를 명기하는 것이 승격 요건이다.",
    },
    "EI-21": {
        "file": SPEC, "anchor": "추정 **57,841-63,768 = 69.2-76.2%**",
        "what": "ECP5 bank 팽창 사전 추정", "spec": "§27.6",
        "status": "mismatch",
        "graduation": "실측 TRELLIS_COMB 54% 가 추정 대역 **전부를 "
                      "하회**했는데 원 추정 행에 supersede 배너가 없다. "
                      "배너 문안이 '기준 불변, 추정 대조만 추가' 를 명시해야 "
                      "하는지는 gate 절 편집이라 사용자 판단 사항.",
    },
    "EI-23": {
        "file": SPEC, "anchor": "채택 형 (1-pass TwoSumExact) 의 nominal",
        "what": "3a cycle nominal", "spec": "§27.7a.2", "status": "mismatch",
        "graduation": "실측 GLOBAL worst 1,167 로 졸업했으나 nominal 하단의 "
                      "1/3 이고 그 빗나감이 nominal 줄에 표기되지 않았다.",
    },
    "EI-35": {
        "file": ECP5_GATE, "anchor": '"wrapper_ff": 1601',
        "what": "ECP5 체커 wrapper_ff 상수", "spec": "§28.10",
        "status": "mismatch",
        "graduation": "실측은 다른 값(1,740)인데 상수가 그대로다. "
                      "MEASUREMENT 반쪽이라 FAIL 을 만들지 않고 **파생 줄이 "
                      "틀린 수를 인쇄한다.** 상수 정정은 gate 기준 이동이라 "
                      "§12a 상 사용자 결정 사항 — 색인은 등재만 한다.",
    },
    "EI-36": {
        "file": ECP5_GATE, "anchor": '"premap_pin": 429',
        "what": "ECP5 체커 premap_pin 상수", "spec": "§28.7/§29.11a",
        "status": "mismatch",
        "graduation": "xcu55c 는 §29.11a 로 381 재anchor 됐는데 ECP5 쪽은 "
                      "미반영이라 MISMATCH 가 상시 출력된다. §28.7 이 '축이 "
                      "작동하는 것' 으로 판정했으나 재anchor 미반영 상태가 "
                      "고착됐다 — 사용자 결정 사항.",
    },
    "EI-37": {
        "file": SYNTH_COV, "anchor": "Fmax 167.31 MHz",
        "what": "lint 선언표의 ALU_Extended Fmax 서술", "spec": "§28.8",
        "status": "mismatch",
        "graduation": "spec 은 'constraint 를 MET 한 run 의 **외삽**이므로 "
                      "보수적 하한' 이라고 정직하게 적었는데 기계가 읽는 쪽 "
                      "`how` 문자열에는 외삽 성격이 소실됐다. **기계 쪽이 "
                      "사람 쪽보다 덜 정확하다** — `how` 문자열에 외삽임을 "
                      "적는 1줄 편집이 승격 요건.",
    },
    # spec §39.5 항 9 이 추가. 초판 색인이 빠뜨린 최대 편차 MISMATCH.
    "EI-38": {
        "file": SPEC, "anchor": "LFE5U-85F 예상 clock ~180 MHz",
        "what": "LayerNorm latency 비교의 기준 clock", "spec": "§22.8",
        "status": "mismatch",
        "graduation": "실측 fabric 은 10.85 MHz (§23.8) — **16.6× 빗나감**이고 "
                      "등재된 MISMATCH 중 최대다 (기존 최대는 EI-18 의 4×). "
                      "§22.8 은 이 기준 위에 세운 파생값(30-40 cycles / "
                      "~90-135 cycles / ~3× latency penalty / ~8× NoC traffic / "
                      "inference 총 시간 <8% 증가)을 배너 없이 오늘도 들고 "
                      "있다. 승격 요건은 §35.5.2 형식의 supersede 배너를 원 "
                      "추정 줄에 붙이는 것 — EI-21 과 동일 클래스이며 파생값 "
                      "재산정 여부는 사용자 판단 사항이다.",
    },
}

# ---------------------------------------------------------------------------
# advisory 산문 스캐너 (**FAIL 을 만들지 않는다** — 위 docstring 의 실측 근거)
# ---------------------------------------------------------------------------
PROSE_DETECTORS = [
    r"ESTIMATE", r"(추정.*[0-9])|([0-9].*추정)", r"hand-count", r"문헌 추정",
    r"산정치", r"nominal", r"약\s+[0-9]", r"≈\s*[0-9]",
    r"(?<!~)~\s*[0-9]", r"미측정", r"(예상.*[0-9])|([0-9].*예상)", r"투영",
]

ID_TOKEN = re.compile(r"\bEI-\d{2}\b")
# 정방향(선언표 → spec)은 **§39.2.3 구역 안의 행 형태**를 요구한다. 두 겹으로
# 좁혀져 있고 각 겹은 실제 변이가 뚫은 자리다:
#   * 단순 토큰 등장으로 만족시키면 안 된다 (MUT-4) — §39.1.2 가 M-01 에서
#     `EI-31` 을 상호참조하고 있어서, §39.2.3 본표에서 그 **행을 통째로
#     지워도** 토큰은 남아 검사가 조용히 통과했다.
#   * 행 형태만으로도 부족하다 (MUT-D) — 본표 행을 잘라 **§39.1.1 Band A 표로
#     옮겨도** 통과했다. 두 표가 같은 파일에서 같은 `| **XX-NN** |` 문법을
#     쓰므로 절 재편·표 병합에서 조용히 성립한다. 그래서 구역을 한정한다.
ID_ROW = re.compile(r"^\|\s*\*\*(EI-\d{2})\*\*\s*\|", re.M)

# ---------------------------------------------------------------------------
# 불변식 G — 선언 집계 정합. spec §39 의 각 표를 실제로 파싱해 머리표/집계
# 문장의 숫자와 대조한다. **집계를 거는 문장이 사라져도 FAIL** 한다.
# ---------------------------------------------------------------------------
SEC_D_LIST = "#### 39.1.1"
SEC_M_LIST = "#### 39.1.2"
SEC_U_LIST = "#### 39.1.3"
SEC_INDEX = "#### 39.2.3"
SEC_INDEX_END = "#### 39.2.4"
SEC_MATRIX = "#### 39.3.1"
SEC_MATRIX_END = "#### 39.3.5"

D_HEAD = re.compile(r"^#### 39\.1\.1 \(D\) 사용자 결정 대기 · (\d+)건", re.M)
M_HEAD = re.compile(r"^#### 39\.1\.2 \(M\) 실행 대기 목록 · (\d+)건", re.M)
I_HEAD = re.compile(r"^#### 39\.2\.3 색인 본표 · (\d+) 항목", re.M)
MATRIX_TALLY = re.compile(
    r"\*\*집계: 총 (\d+)행 — ✅ (\d+) / ⚠️ 조건부 (\d+) / ❌ (\d+)\.\*\*")
CARRY1_TALLY = re.compile(
    r"선언표는 \*\*(\d+) D \+ (\d+) M 중 (\d+)건\*\*을")
ENFORCE_TALLY = re.compile(r"나머지 \*\*(\d+) D \+ (\d+) M\*\*")

D_ROW = re.compile(r"^\|\s*\*\*(D-\d{2})\*\*\s*\|", re.M)
M_ROW = re.compile(r"^\|\s*\*\*(M-\d{2})\*\*\s*\|", re.M)
MATRIX_ROW = re.compile(r"^\|\s*([ABCD]\d+)\s*\|")
VERDICTS = ("✅", "⚠️", "❌")
# `deadline` 이 달린 D — `lint_synth_coverage.py` 가 부분 집행하는 2건.
# §39.0 표와 §39.4 이월 1 이 "나머지" 를 셀 때 빼는 수이며, 그 수 자체가
# 여기 상수로 있어야 두 문장이 같은 근거를 쓴다.
PARTIALLY_ENFORCED_D = 2


def _read(rel: str) -> str:
    p = REPO_ROOT / rel
    if not p.is_file():
        sys.exit(f"lint_estimate_index: 대상 파일 부재: {rel}")
    return p.read_text(encoding="utf-8")


def _slice(txt: str, start: str, end: str, fail, label: str):
    """`start` 헤딩부터 `end` 헤딩 직전까지. 경계가 없으면 FAIL 한다 —
    검사의 정박점이 사라지는 것 자체가 위반이다 (조용한 무효화 봉쇄)."""
    i = txt.find(start)
    j = txt.find(end)
    if i < 0 or j < 0 or j <= i:
        fail.append(f"불변식 G: {label} 의 구역 경계를 찾지 못했다 "
                    f"({start!r} … {end!r}) — 검사의 정박점이 사라졌다. "
                    "절을 재편했다면 이 상수도 같은 commit 에서 옮겨야 한다.")
        return ""
    return txt[i:j]


def _split_cells(line: str):
    """마크다운 셀 분해. 셀 안의 `\\|` 는 구분자가 아니다."""
    return [c.strip() for c in re.split(r"(?<!\\)\|", line)]


def _schema_check(eid, e, fail):
    if e["status"] not in VALID_STATUS:
        sys.exit(f"lint_estimate_index: {eid}: 알 수 없는 status "
                 f"{e['status']!r} (허용: {VALID_STATUS})")
    for key in ("file", "anchor", "what", "spec"):
        if not e.get(key):
            sys.exit(f"lint_estimate_index: {eid}: `{key}` 는 필수다.")
    if len(e["anchor"]) < 12:
        sys.exit(f"lint_estimate_index: {eid}: anchor 가 너무 짧다 "
                 f"({len(e['anchor'])} < 12) — 짧은 anchor 는 우연히 다른 "
                 "줄과 일치해 색인을 조용히 엉뚱한 곳에 묶는다.")

    # `graduation` 은 **status 무관 전건 필수**다. 졸업 항목에서는 "무엇이
    # 요건이었나" 의 기록이 된다. 미졸업 → graduated 로 뒤집으면서 요건을
    # 지우는 경로(변이 MUT-F)를 이 한 줄이 막는다.
    if not e.get("graduation"):
        fail.append(f"{eid}: `graduation` 은 전건 필수다 — 미졸업이면 승격 "
                    "요건, 졸업했으면 '무엇이 요건이었는가' 의 기록이다. "
                    "졸업하면서 이 필드를 지우면 무엇을 근거로 졸업했는지가 "
                    "사라진다 (변이 MUT-F 가 정확히 그 경로였다).")

    # 수치 pin — anchor 가 절 제목이거나 숫자를 한 자도 담지 않으면 필수.
    # 그 12건에서 anchor 는 "절이 사라졌는가" 만 재고 "수치가 살아 있는가" 를
    # 재지 않았다 (변이 MUT-X: §18.8 추정치 3줄 전량 삭제 → EXIT 0).
    val = e.get("value")
    anchor_is_heading = e["anchor"].lstrip().startswith("#")
    anchor_has_digit = bool(re.search(r"\d", e["anchor"]))
    if (anchor_is_heading or not anchor_has_digit) and not val:
        why = "절 제목" if anchor_is_heading else "숫자 미포함"
        fail.append(f"{eid}: anchor 가 {why} 이므로 `value` (수치 pin) 가 "
                    "필수다 — 이 anchor 로는 수치가 통째로 지워져도 검사가 "
                    "통과한다 (변이 MUT-X).")
    if val is not None:
        if len(val) < 10:
            sys.exit(f"lint_estimate_index: {eid}: value 가 너무 짧다 "
                     f"({len(val)} < 10).")
        if not re.search(r"\d", val):
            sys.exit(f"lint_estimate_index: {eid}: value 에 숫자가 없다 — "
                     "수치 pin 이 수치를 담지 않으면 pin 이 아니다.")

    if e["status"] == "graduated":
        if not e.get("evidence"):
            fail.append(f"{eid}: status 'graduated' 는 `evidence` 가 필수다 — "
                        "근거 없는 졸업 선언을 막는다 (premap $mul '측정했다' "
                        "주장이 그 실물이었다, §22.14b-10).")
        elif len(e["evidence"]) < 12:
            fail.append(f"{eid}: evidence 가 너무 짧다 "
                        f"({len(e['evidence'])} < 12) — anchor 와 같은 하한을 "
                        "건다. 짧은 근거는 여러 줄에 우연히 걸려 어느 줄이 "
                        "졸업을 뒷받침하는지 확정되지 않는다.")
        if not e.get("evidence_file"):
            fail.append(f"{eid}: status 'graduated' 는 `evidence_file` 이 "
                        "필수다 — 경로 존재만 보는 형태는 저장소의 **아무 "
                        "파일**로도 통과한다 (변이 MUT-E). premap 사고의 "
                        "본질은 '증거 파일이 없다' 가 아니라 '증거가 그 "
                        "주장을 뒷받침하지 않는다' 였다.")


def _declared(rx, txt, fail, label, ngroups):
    """집계를 거는 문장을 찾아 숫자를 뽑는다. **문장이 없으면 FAIL** —
    검사를 무효화하는 가장 값싼 방법이 '검사가 물고 있는 문장을 지우는 것'
    이기 때문이다. (§39.5 항 1 이 잡은 결함은 문장이 *있는데* 숫자가 틀린
    형태였고, 그 문장을 지우는 것은 더 조용한 경로다.)"""
    m = rx.search(txt)
    if m is None:
        fail.append(f"불변식 G: {label} 의 집계 문장을 찾지 못했다 — 검사가 "
                    "물고 있는 문장이 사라지면 대조가 조용히 사라진다. "
                    "문안을 바꿨다면 이 스크립트의 정규식도 같은 commit 에서 "
                    "옮겨야 한다.")
        return None
    return tuple(int(g) for g in m.groups()[:ngroups])


def _tally_check(spec_txt, fail):
    """spec §39 의 표를 **실제로 파싱해** 머리표·집계 문장과 대조한다."""
    # (1) §39.1.1 D 목록
    d_sec = _slice(spec_txt, SEC_D_LIST, SEC_M_LIST, fail, "§39.1.1 D 목록")
    d_rows = D_ROW.findall(d_sec)
    d_decl = _declared(D_HEAD, spec_txt, fail, "§39.1.1 머리표", 1)
    if d_decl and d_decl[0] != len(d_rows):
        fail.append(f"불변식 G: §39.1.1 머리표는 {d_decl[0]}건이라 적는데 실제 "
                    f"`| **D-NN** |` 행은 {len(d_rows)}건이다.")
    if len(set(d_rows)) != len(d_rows):
        dup = sorted({x for x in d_rows if d_rows.count(x) > 1})
        fail.append(f"불변식 G: §39.1.1 에 중복 D-ID {dup}.")

    # (2) §39.1.2 M 목록
    m_sec = _slice(spec_txt, SEC_M_LIST, SEC_U_LIST, fail, "§39.1.2 M 목록")
    m_rows = M_ROW.findall(m_sec)
    m_decl = _declared(M_HEAD, spec_txt, fail, "§39.1.2 머리표", 1)
    if m_decl and m_decl[0] != len(m_rows):
        fail.append(f"불변식 G: §39.1.2 머리표는 {m_decl[0]}건이라 적는데 실제 "
                    f"`| **M-NN** |` 행은 {len(m_rows)}건이다.")
    if len(set(m_rows)) != len(m_rows):
        dup = sorted({x for x in m_rows if m_rows.count(x) > 1})
        fail.append(f"불변식 G: §39.1.2 에 중복 M-ID {dup}.")

    # (3) §39.2.3 색인 본표 — 머리표 · 실제 행 · 선언표 셋이 모두 같아야 한다
    i_sec = _slice(spec_txt, SEC_INDEX, SEC_INDEX_END, fail, "§39.2.3 본표")
    i_rows = ID_ROW.findall(i_sec)
    i_decl = _declared(I_HEAD, spec_txt, fail, "§39.2.3 머리표", 1)
    if i_decl and not (i_decl[0] == len(i_rows) == len(ESTIMATE_INDEX)):
        fail.append(f"불변식 G: §39.2.3 머리표 {i_decl[0]} / 실제 행 "
                    f"{len(i_rows)} / 선언표 {len(ESTIMATE_INDEX)} 가 "
                    "서로 다르다.")

    # (4) §39.3 매트릭스 — 총행수 + ✅/⚠️/❌ 분포를 판정 셀에서 재계수한다.
    #     판정 열의 위치는 표마다 다르므로(A~C 축은 `충족`, D 축은 `판정`)
    #     **헤더 행을 읽어 열 번호를 찾는다** — 열 번호를 상수로 박으면 표
    #     구조가 바뀔 때 조용히 엉뚱한 셀을 센다.
    mx = _slice(spec_txt, SEC_MATRIX, SEC_MATRIX_END, fail, "§39.3 매트릭스")
    counts = {v: 0 for v in VERDICTS}
    total = 0
    col = None
    for line in mx.split("\n"):
        cells = _split_cells(line)
        if len(cells) > 2 and cells[1] == "#":
            col = next((k for k, c in enumerate(cells)
                        if c in ("충족", "판정")), None)
            if col is None:
                fail.append("불변식 G: §39.3 표 헤더에 `충족`/`판정` 열이 "
                            f"없다: {line[:70]!r}")
            continue
        if not MATRIX_ROW.match(line):
            continue
        total += 1
        if col is None or col >= len(cells):
            fail.append(f"불변식 G: §39.3 행의 판정 열을 찾을 수 없다: "
                        f"{line[:70]!r}")
            continue
        cell = cells[col]
        hits = {v: cell.find(v) for v in VERDICTS if v in cell}
        if not hits:
            fail.append(f"불변식 G: §39.3 행에 판정 심볼이 없다: "
                        f"{line[:70]!r}")
            continue
        counts[min(hits, key=hits.get)] += 1
    decl = _declared(MATRIX_TALLY, spec_txt, fail, "§39.3 집계 문장", 4)
    if decl:
        want = (total, counts["✅"], counts["⚠️"], counts["❌"])
        if decl != want:
            fail.append(
                f"불변식 G: §39.3 집계 문장은 총 {decl[0]} / ✅ {decl[1]} / "
                f"⚠️ {decl[2]} / ❌ {decl[3]} 이라 적는데, 표를 파싱한 실측은 "
                f"총 {want[0]} / ✅ {want[1]} / ⚠️ {want[2]} / ❌ {want[3]} "
                "이다. **매트릭스는 자기 존재 이유가 정확한 집계인 산출물이다** "
                "— 초판이 22/20/14 로 착지한 것이 이 검사가 생긴 이유다.")

    # (5) 파생 집계 2곳 — §39.0 표와 §39.4 이월 1 은 D/M 총수에서 부분 집행
    #     2건을 뺀 수를 인쇄한다. 세 곳이 같은 근거를 쓰는지 대조한다.
    if d_decl and m_decl:
        nd, nm = d_decl[0], m_decl[0]
        rest = nd - PARTIALLY_ENFORCED_D
        enf = _declared(ENFORCE_TALLY, spec_txt, fail, "§39.0 집행 표", 2)
        if enf and enf != (rest, nm):
            fail.append(f"불변식 G: §39.0 표는 '나머지 {enf[0]} D + {enf[1]} M' "
                        f"이라 적는데 실측 근거는 {rest} D + {nm} M 이다 "
                        f"(D {nd} − 부분 집행 {PARTIALLY_ENFORCED_D}).")
        c1 = _declared(CARRY1_TALLY, spec_txt, fail, "§39.4 이월 1", 3)
        if c1 and c1 != (nd, nm, rest + nm):
            fail.append(f"불변식 G: §39.4 이월 1 은 '{c1[0]} D + {c1[1]} M 중 "
                        f"{c1[2]}건' 이라 적는데 실측 근거는 {nd} D + {nm} M "
                        f"중 {rest + nm}건이다.")


def main():
    fail = []
    texts = {}

    # --- 불변식 A: anchor 실재 (정확히 1회) ------------------------------
    for eid, e in sorted(ESTIMATE_INDEX.items()):
        _schema_check(eid, e, fail)
        txt = texts.setdefault(e["file"], _read(e["file"]))
        n = txt.count(e["anchor"])
        if n == 0:
            fail.append(
                f"{eid}: anchor 가 {e['file']} 에 없다 (0회) — 색인이 stale "
                f"이거나 수치가 지워졌다. anchor={e['anchor'][:60]!r}")
        elif n > 1:
            fail.append(
                f"{eid}: anchor 가 {e['file']} 에 {n}회 등장한다 — 모호한 "
                f"anchor 는 다음 편집에서 조용히 다른 줄을 가리키게 된다. "
                f"anchor={e['anchor'][:60]!r}")

        # 수치 pin — anchor 와 **같은 강도**로 검사한다. anchor 가 위치를
        # 잡고 value 가 수치를 잡는다. 둘을 한 필드로 겸하면 절 제목 anchor
        # 12건에서 수치가 통째로 지워져도 통과한다 (변이 MUT-X).
        val = e.get("value")
        if val is not None:
            m = txt.count(val)
            if m == 0:
                fail.append(
                    f"{eid}: value(수치 pin)가 {e['file']} 에 없다 (0회) — "
                    f"**수치가 지워졌거나 바뀌었다.** 절 제목만 남아도 anchor "
                    f"는 살아 있으므로 이 축이 그것을 잡는다. "
                    f"value={val[:60]!r}")
            elif m > 1:
                fail.append(
                    f"{eid}: value 가 {e['file']} 에 {m}회 등장한다 — 어느 "
                    f"줄의 수치를 pin 하는지 확정되지 않는다. "
                    f"value={val[:60]!r}")

    # --- 불변식 C: 졸업 근거 실재 (정확히 1회) ----------------------------
    for eid, e in sorted(ESTIMATE_INDEX.items()):
        if e["status"] != "graduated":
            continue
        ev = e.get("evidence")
        evf = e.get("evidence_file")
        if not ev or not evf:
            continue                    # 스키마 검사가 이미 FAIL 을 넣었다
        txt = texts.setdefault(evf, _read(evf))
        k = txt.count(ev)
        if k == 0:
            fail.append(
                f"{eid}: evidence 문자열이 {evf} 에 없다 — 졸업 근거가 "
                f"실재하지 않는다. evidence={ev[:60]!r}")
        elif k > 1:
            fail.append(
                f"{eid}: evidence 가 {evf} 에 {k}회 등장한다 — 어느 줄이 "
                f"졸업을 뒷받침하는지 확정되지 않는다. 유일성은 anchor 와 "
                f"같은 요건이다. evidence={ev[:60]!r}")

    # --- 불변식 D: 인용 금지 ---------------------------------------------
    for eid, e in sorted(ESTIMATE_INDEX.items()):
        for path, token in e.get("forbid_in", ()):
            txt = texts.setdefault(path, _read(path))
            if token in txt:
                fail.append(
                    f"{eid}: 인용 금지 위반 — 비-실측 수치 {token!r} 가 gate "
                    f"판정 스크립트 {path} 에 등장한다. spec 이 '이 수치를 "
                    "gate 판정 근거로 인용하지 마라' 를 명시했다 (§35.5.4).")

    # --- 불변식 B: ID 양방향 정합 ----------------------------------------
    mirror = texts.setdefault(ID_MIRROR, _read(ID_MIRROR))
    index_sec = _slice(mirror, SEC_INDEX, SEC_INDEX_END, fail, "§39.2.3 본표")
    spec_ids = set(ID_TOKEN.findall(mirror))       # 상호참조 포함, 역방향용
    spec_rows = set(ID_ROW.findall(index_sec))     # **구역 안의** 행만, 정방향
    table_ids = set(ESTIMATE_INDEX)
    missing_in_spec = sorted(table_ids - spec_rows)
    missing_in_table = sorted(spec_ids - table_ids)
    if missing_in_spec:
        fail.append(
            f"선언표에만 있는 ID {missing_in_spec} — spec §39.2.3 **구역 안**에 "
            "`| **EI-NN** |` 행이 없다 (다른 절의 상호참조도, 다른 표로 옮긴 "
            "행도 본표 행을 대신하지 못한다). spec-first (§12a 규칙 3) 가 "
            "지켜지지 않았다.")
    if missing_in_table:
        fail.append(
            f"spec 에만 있는 ID {missing_in_table} — 선언표에 항목이 없다. "
            "본표 행만 늘리면 anchor 검사도 승격 요건 검사도 받지 않는다.")

    # --- 불변식 G: 선언 집계 정합 ----------------------------------------
    _tally_check(mirror, fail)

    # --- 불변식 E: 래칫 ---------------------------------------------------
    by_status = {s: sorted(k for k, v in ESTIMATE_INDEX.items()
                           if v["status"] == s) for s in VALID_STATUS}
    ratchets = [("estimate", EST_MAX), ("derived", DERIVED_MAX),
                ("unmeasured", UNMEASURED_MAX), ("mismatch", MISMATCH_MAX),
                ("pre-announced", PRE_MAX)]

    # --- 불변식 F: 소리내기 ----------------------------------------------
    print(f"lint_estimate_index — 추정치 색인 (spec §39.2; {len(table_ids)}"
          "항목)")
    for s in VALID_STATUS:
        print(f"  {s:<15s} {len(by_status[s])}: "
              f"{', '.join(by_status[s]) or '-'}")
    print()
    for s in UNGRADUATED:
        for eid in by_status[s]:
            e = ESTIMATE_INDEX[eid]
            print(f"  [{s}] {eid} {e['spec']} — {e['what']}")
            print(f"      승격: {e['graduation']}")
    print()

    # advisory 산문 스캔 — 절대 FAIL 하지 않는다.
    rxs = [re.compile(p) for p in PROSE_DETECTORS]
    lines = mirror.split("\n")
    suspect = sum(1 for ln in lines if any(r.search(ln) for r in rxs))
    print(f"  [advisory] 산문 검출기 12종 union: {suspect}줄 / "
          f"{len(lines)}줄 ({ID_MIRROR})")
    print("  [advisory] 이 수치는 **판정에 쓰이지 않는다** — 실측 오탐률이 "
          "높아(HEAD 증분 31줄 중 진성 ≈3) hard FAIL 로 쓸 수 없다.")
    print("  [advisory] 미등재 신규 추정치를 막는 기계는 없다 "
          "(spec §39.4 이월 3).")
    print()

    for s, cap in ratchets:
        n = len(by_status[s])
        if n > cap:
            fail.append(f"래칫 위반: {s} {n} > 상한 {cap}")

    if fail:
        for f in fail:
            print(f"VIOLATION: {f}")
        sys.exit(1)

    n_val = sum(1 for e in ESTIMATE_INDEX.values() if e.get("value"))
    print("lint_estimate_index OK — anchor 실재 "
          f"{len(table_ids)}/{len(table_ids)} (그중 수치 pin `value` 별도 "
          f"검증 {n_val}건 — 나머지는 anchor 가 수치를 겸한다) / ID 양방향 "
          f"정합(§39.2.3 구역 한정) / 졸업 근거 "
          f"{len(by_status['graduated'])}건 유일 실재 / 인용 금지 0 위반 / "
          "선언 집계 정합 / 래칫 "
          + " / ".join(f"{s} {len(by_status[s])}<={c}"
                       for s, c in ratchets))


if __name__ == "__main__":
    main()
