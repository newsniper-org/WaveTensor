---
name: differential-domain-trap
description: 차등 시험은 양쪽이 같은 정의역에서 나올 때만 반증력이 있다 — 기대측이 안 자라는 손-리터럴이면 새 경우는 정의역 밖에서 태어나고 시험은 영원히 침묵한다
metadata: 
  node_type: memory
  type: project
  originSessionId: e7f99d7a-a6eb-46be-b7eb-fd78237e02a7
  modified: 2026-08-30T07:43:16.544Z
---

`isa/truth_table_encwave.json`(6,141점)은 RTL 재구현의 **clean-room 블랙박스
오라클**이고 `test_isa_decoder.py:4272` 가 매 push·PR 에 전량 차등으로 돌린다.
그런데 2026-08-30 실측: 캡처 도메인 `_TT_SUPPORTED_OPCODES` /
`_TT_UNSUPPORTED_PROBES` 는 **손-리터럴**이고 `isa/wt64v1_isa.json` 과 **아무것도
대조하지 않았다.**

⇒ 새 opcode 가 배정되면 **오라클에 한 점도 없이 태어나고**, 차등 시험은 기대측
`got` 이 상수라 **영원히 침묵**한다. 실패가 아니라 부재다.

**Why:** 「전량 차등 게이트가 있다」가 곧 「덮인다」가 아니다. 차등은 두 산출을
비교하는 것이고, 기대측 정의역이 안 자라면 자란 쪽만 검사 밖으로 나간다.
이 저장소가 [[yosys-bind-trap]]·[[sby-composite-regression]]에서 배운 침묵의
또 다른 얼굴 — 이번엔 **하네스가 아니라 정의역**이 비었다.

**How to apply:**

1. `scripts/lint_truth_table_domain.py`(2026-08-30 신설, `make lint` 안)가 선언을
   **AST 로** 읽어(그 `python3` 에 cocotb 가 없다) 키 6,141개를 **전량 재유도**하고
   오라클의 자기 키 집합과 양방향 대조한다. **계수 산술보다 강하다** — 형상 축·키
   표기까지 잡는다.
2. **인코딩을 지문으로 삼지 마라 — 이 표에는 인코딩이 한 비트도 없다.** 판정
   3비트(err/lwr/out)뿐이고, 실측상 인코딩 파도가 5,796점의 바이너리를 전부 바꿨는데
   outcome 은 5,934/5,934 동일했다. 낡는 축은 **정의역**이다.
3. **구조적 잔여를 세어서 인쇄한다.** 배정 opcode 14개(21%, `0x70`–`0x7E`)는 ISA
   소스 자신의 선언으로 정의역 밖이라 이 탐지기가 **영구 침묵**한다. 게이트가 그
   사실과 대가와 남은 그물(`test_fp_block_unassigned_opcodes_still_error` · CI 차등)을
   함께 인쇄한다. **「전부」라고 쓰면서 21%를 빼는 것이 처음 실장의 결함이었다.**
4. **동결 표와 재생성 대상을 형으로 가른다.** `truth_table_premigration.json` 은
   「이관 전 계보 전용」 **동결 산출물**이라 blake2b-512 핀이고, `encwave` 에는
   **핀을 걸지 않는다**(정당하게 움직이는 파일에 핀을 걸면 둘째 선언처가 된다 —
   [[rolling-asset-pin-trap]]). 게이트가 자기 AST 를 **함수간 오염 전파**로 훑어
   동결 경로에 쓰기를 여는 자리를 정적으로 막는다.
5. **`WT_CAPTURE_TRUTH_TABLE=1` 은 오라클을 조용히 덮어쓰고 passed 로 끝난다.**
   CI 의 `git diff --exit-code -- isa/` 가 유일한 그물이다.
6. **재캡처 절차**: `WT_CAPTURE_TRUTH_TABLE=1 make MOD=ISA_Decoder` → dv 범프 →
   소비자 핀 재동기 → 3회 바이트 동일 → **한 커밋**. 게이트 실패 문면이 이 7단계를
   담는다.

**남은 최대 결손**: 어셈블러↔`ref` 핀이 **12/68 opcode(18%)** 다. 어셈블러는
동결하지 않기로 했으므로([[dev-platform-policy]]) 이 마디가 사슬에서 가장 약하다 —
그 뒤 `ref`↔캡처 인코더는 1,144점 전수인데 앞 마디만 표본이다. 범위 확대는 미결.

관련: [[selftest-residency]] · [[wt64v1-rtl-reimplementation]](이 표가 그 오라클이다).
