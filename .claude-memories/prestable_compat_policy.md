---
name: prestable-compat-policy
description: 동결 보증(frozen/keep-forever)은 stable release부터 발효 — pre-stable에서는 compat freeze에 얽매이지 말 것 (사용자 지시 2026-07-24)
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 09e02def-fe68-4449-8866-9db15ac81932
---

# Pre-stable 단계의 호환성 정책: 동결 보증은 stable release부터

"frozen first-class 유지", truth-table "keep forever", snapshot 동결 류의
호환성 보증은 **stable release에 발효되는 ABI 약속**이며, pre-stable 개발
단계의 설계·정리 작업을 구속하지 않는다. dead opcode 제거, truth-table
의도적 recapture, latency 계약 개정은 pre-stable에서 **정규 개발
이벤트**다 (물론 spec 개정으로 기록하고 도메인 버전을 올린다).

**Why:** 사용자 지시 (2026-07-24, opcode cleanup 계획 검토 중):
"stable release 전까지는 frozen 요구조건에 너무 얽매일 필요가 없지
않나?" / "frozen first-class 유지는 stable release에 적용하는 게 맞지
않겠어?" — 이전 워크플로들이 개발 중 ISA를 이미 동결된 것처럼 다뤄
과도한 보수성(정책 번복 ceremony, dead 코드 존치)을 만들고 있었음.

**How to apply:** WT64v1 spec에 compat 정책 절이 있음 (Stage-1 cleanup
commit 참조) — 동결 보증 발효 시점 = stable release. 설계 workflow
프롬프트에 "pre-stable: 호환성 pin은 spec 개정으로 갱신 가능한 정규
대상" 임을 명시할 것. 단 이것이 무단 변경 면허는 아님 — 변경은 여전히
spec-first로 기록하고 recapture는 의도적·버전 표기된 이벤트로 수행.
관련: [[wt64v1-precision-recovery-roadmap]]
