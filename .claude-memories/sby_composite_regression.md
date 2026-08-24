---
name: sby-composite-regression
description: "모듈 sby 만 돌리면 그 모듈을 인스턴스하는 합성 태스크의 회귀를 놓친다 — [files] 역색인이 완료 기준"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: e7f99d7a-a6eb-46be-b7eb-fd78237e02a7
  modified: 2026-08-24T20:18:44.080Z
---

RTL 모듈을 고친 뒤 그 모듈의 sby 태스크만 돌리면, **그 모듈을 인스턴스하는 합성 증명 태스크가
조용히 회귀한다.** 2026-08-25 WT64v1 실측: `MmioConfig.scala` 의 예약 비트 엄격화(커밋 df49b24)로
LBID 커밋 조건이 `lbidWrite` → `lbidWrite && !lbRsvBad` 로 좁아졌는데, 담당자가
`mmio_config.sby`·`mmio_deep.sby` 두 태스크만 돌리고 `RouteMmio/route_mmio.sby`
(= `MmioConfig.sv` + `RouteJudge.sv` 합성)를 돌리지 않아 `p_bank_iff`·`p_pair_bank` 가
induction 에서 깨진 채 커밋됐다. 후속 파도의 검증자도 「Wt64Top.sv 를 읽는 태스크 0개」만
확인하고 *직전 파도가 바꾼 생성물*은 대조하지 않아 「선재 결함」으로 오분류했다.

**Why:** 하네스는 RTL 의 '성공' 정의를 사본으로 들고 있다. 모듈 하네스는 같은 파도에서 함께
갱신되지만 합성 하네스는 다른 디렉터리에 있어 시야에서 사라진다. basecase 는 통과하고
induction 만 깨지므로 얕은 확인으로는 안 보인다.

**How to apply:**
1. 생성물(`rtl/generated/*.sv`)을 바꿨으면 `rtl/formal/sby/**/*.sby` 의 `[files]` 절을
   **전수 파싱해 역색인**을 만들고, 그 파일을 읽는 태스크를 *전부* 돌린다. 완료 기준에 포함.
2. 돌리지 않은 태스크가 있으면 「입력이 안 바뀌었다」는 구성적 근거를 대야 한다 — "아마 무관"은 근거가 아니다.
3. 합성 하네스에는 「이 식은 <모듈>_props 의 식과 같아야 한다」를 주석으로 박아 둔다 (사본임을 명시).
4. `make rtl-postformal` 전수 실행이 최종 그물이다 — 부분 실행으로 커밋하지 않는다.
   관련: [[yosys_bind_trap]] (같은 부류 — 증명이 "돌았다"가 아무것도 보증하지 않는 형태)
