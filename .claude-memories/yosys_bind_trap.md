---
name: yosys-bind-trap
description: yosys 0.66 이 SVA bind 를 조용히 무시 — 하네스가 제거돼 공허 PASS. 사람의 적발로는 못 막는다, 실행 게이트가 유일한 그물
metadata:
  node_type: memory
  type: feedback
  originSessionId: e7f99d7a-a6eb-46be-b7eb-fd78237e02a7
  modified: 2026-08-25T01:09:08.309Z
---

yosys 0.66 네이티브 프런트엔드는 SystemVerilog `bind` 지시를 **오류 없이 파싱하되 조용히 무시**한다
(2026-08-24, 최소 재현 3변형 실측 — 파일 꼭대기·모듈 스코프·-defer 무관). 하네스 모듈이
「Removing unused module」로 제거되어 **sby 태스크가 공허 PASS** 가 된다.

**이 함정은 사람의 적발로 막히지 않는다.** 1차 파도에서 세 팀이 독립적으로 밟고 각자 적발했는데도,
2026-08-25 전수 실측에서 **두 태스크가 그물을 빠져나가 있었다** — `XlateStore`(앵커 7건, assert=0)와
`HiuMask`(앵커 4건, assert=0). 즉 실측 덮임이 래칫이 세던 66이 아니라 62였다. 두 파일 다
한 번도 elaborate 된 적이 없어서 `$past(reset)`-in-a-wire 같은 **컴파일 에러조차 잠들어 있었다** —
그것이 공허함의 총체성을 보여주는 가장 날카로운 증거다.

**Why:** bind 미지원이 경고조차 없어서, 「돌았고 통과했다」가 아무것도 보증하지 않는다.
그리고 `lint_postformal` 같은 *정적* 검사는 셀 수를 셀 수 없어 공허를 원리적으로 못 잡는다 —
PROVES 앵커의 실재성·정합성만 재고 그것을 「덮임」으로 계수한다.

**How to apply:**
1. **지문은 「`prep -top` 이 DUT 자신」이 아니다** — 그 특정은 틀렸고 HiuMask 가 래퍼를 가졌다는
   이유로 빠져나갔다. 진짜 지문은 **「단언이 bind 로만 붙는 모듈에 산다」** 이다. 래퍼가 DUT 를
   배선만 하고 단언이 별도 props 에 있으면 똑같이 공허하다.
2. **실행 게이트가 유일한 그물**: `make rtl-postformal` 이 각 태스크의 `design_prep.il` 에서
   `cell $assert|$cover` 를 세어 0 이면 HOLLOW 로 실패시킨다 (2026-08-25 결선). PASS 만으로는
   부족하다. 새 하네스의 완료 기준에 셀 수 + cover reached 증인을 포함한다.
3. 부착은 두 형태 중 택일 — `expose`+래퍼(MmioConfig/RouteMmio 선례) 또는 `exec` 텍스트 전개
   (MemOrderGate/Reassembly/XlateStore 선례). **연접 표현식을 포트로 받는 하네스는 expose 로
   부착할 수 없다**(expose 는 신호만 승격, 연접을 못 만든다) — 손으로 재작성하면 RTL 과 검사기
   사이에 전사 오류가 숨는 자리가 새로 생긴다. 그 경우 텍스트 전개를 쓴다.
4. 하네스 SV 자체는 `bind` 가능한 형태를 유지한다(다른 도구에서는 동작한다) — 부착은 `.sby` 에서.
5. 부수 함정: generate 루프 안 단언 라벨 유일화 실패("Cannot add procedural assertion") —
   라벨 제거·주석 유지. proc_rom ROM 은 귀납 상태 비구속 — `memory_map` 필요.
   `$past` 는 clocked block 안에서만 — wire 에 쓰면 yosys ERROR (`f_past_reset` 레지스터 관용구).

관련: [[sby_composite_regression]] (같은 부류 — 증명이 「돌았다」가 무엇도 보증하지 않는 형태)
