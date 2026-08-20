---
name: post-stable-roadmap
description: 3단 장기 계획 중 §3(구현 이원화)은 2026-08-20 RTL 전면 재구현으로 대체됨 — §2 문서화·§4 양산만 T_stable 게이트 유지
metadata: 
  node_type: memory
  type: project
  originSessionId: 4e29961e-988b-4f27-9ede-dfb9c81925bc
  modified: 2026-08-20T06:48:02.638Z
---

사용자 지시 (2026-08-17): stable spec/RTL 완성 후 3단 진행 — ① 문서화,
② reference implementation 이원화, ③ 양산 플랜 이원화. 진입 게이트 `T_stable`
= stable spec 확정 AND stable RTL 동결.

**⛔ §3(단계 B 이원화)는 2026-08-20 에 대체됐다.** RTL 전면 재구현이
`T_stable` 미충족 상태에서 착수됐고, **신규 SpinalHDL 구현이 normative 를
승계**한다. 착수 요청 시 게이트 미충족 사실을 먼저 보고했고 사용자가 진행을
선택했다 — 규율은 이행됐다. 자세한 것은 [[wt64v1-rtl-reimplementation]].

**Why 대체:** 이원화의 동기는 "생산성·파라미터화 실험"이었으나, 실제 재구현의
동기는 다르다 — 참조 구현 검증에서 같은 부류의 결함이 반복 발견됐다(합성
넷리스트에 없는 회로, 무동작 연산, 확산 붕괴, 무언 드롭). 정본 서문 §0.8 은
재구현을 "실패가 아니라 발견의 결과"로 적는다.

**살아남은 것:** §3.2 의 pin 중 셋 — 혼재 경계 파일 단위 선언 / 생성물은
생성기와 함께 커밋 + 손편집 금지 / 툴체인 버전 고정 기록. 전부
`rtl/README.md` 와 `scripts/lint_toolchain_pins.py` 로 이행됐다.

**여전히 유효:** §2(문서화)·§4(양산 플랜 2종)는 plan-only 이며 게이트를 유지한다.
전문은 repo 의 `.claude-memos/post_stable_roadmap.md` (§3 에 대체 배너 부착,
원문은 규율상 보존). 관련: [[prestable-compat-policy]].
