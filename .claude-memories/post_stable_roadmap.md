---
name: post-stable-roadmap
description: stable spec+RTL 완성 후에만 열리는 3단 장기 계획 (문서화 → 구현 이원화 → 양산) — T_stable 게이트 전에는 착수 금지
metadata: 
  node_type: memory
  type: project
  originSessionId: 4e29961e-988b-4f27-9ede-dfb9c81925bc
  modified: 2026-08-17T09:19:57.852Z
---

사용자 지시 (2026-08-17): stable spec 과 stable reference implementation 이
**전부 완성된 후** 다음 3단을 순서대로 진행한다 — ① 본격적인 문서화,
② reference implementation 이원화 (순수 Verilog 판 = 기존 유지 + Chisel+Verilog
복합 판 = 신규), ③ 양산 플랜 이원화 (기존 파운드리 공정용 플랜 + 새로운
공정까지 포함하는 장기 플랜).

**Why:** 현행 개발 (v2.0 TRAIN, 3a FDOT32_CR, v2.1 SCALE) 이 아직 진행 중이고,
pre-stable 에서는 계약 변경이 정규 이벤트다 ([[prestable_compat_policy]]).
문서화·이원화·양산은 규범이 흔들리는 동안 하면 전부 재작업이 되므로
`T_stable` (stable spec 확정 AND stable RTL 동결) 을 진입 게이트로 못박았다.

**How to apply:** 전문은 repo 의 `.claude-memos/post_stable_roadmap.md`
(plan-only, 구속 조건·철회 조건 포함). `T_stable` 이전에 이 계획의 착수
요청이 오면 **게이트 미충족 사실을 먼저 보고**하라. 이원화의 핵심 pin —
복합 판은 순수 Verilog 판과 golden 전건 bit-exact 여야 하고 (불일치 = 결함
신호), **binding gate 판정은 순수 Verilog 판에만** 있다 (복합 판은
MEASUREMENT 지위 — ECP5 반쪽 정책과 동형). 양산 플랜 2건은 서로의 전제가
아니다. 노드·파운드리·툴체인 버전은 이 계획이 선점하지 않으며 착수 시점
실측으로 결정한다. 관련: [[wt64v1_precision_recovery_roadmap]] (현행 개발
상태), [[wavetensor_sdk_separate_repo]] (문서화 단계에서 연동).
