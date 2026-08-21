---
name: workflow-placeholder-bug
description: Workflow 스크립트에 __PLACEHOLDER__ 를 넣고 나중에 치환하는 패턴 금지 — 두 번 연속 즉시 실패
metadata: 
  node_type: memory
  type: feedback
  originSessionId: e7f99d7a-a6eb-46be-b7eb-fd78237e02a7
  modified: 2026-08-21T13:59:14.523Z
---

Workflow 도구에 스크립트를 넘길 때 `JSON.parse(String.raw`__DATA__`)` 자리표시자를 넣고 "나중에 파일에서 치환" 하는 패턴을 두 번 썼고, 두 번 다 치환 전에 실행되어 `JSON Parse error: Unexpected identifier` 로 즉시 실패했다 (2026-08-21, MemOrder 수리 + 정본 환류 워크플로).

**Why:** Workflow 는 `script` 인라인 호출 시점에 즉시 파싱·실행한다. 자리표시자는 "먼저 파일로 저장 → 편집 → scriptPath 재실행" 흐름에서만 안전한데, 그 순서를 지키는 것을 매번 잊는다.

**How to apply:** 데이터를 스크립트에 넣을 때는 자리표시자 없이 **호출 전에 JSON 을 직접 인라인**하거나, `args` 파라미터로 전달한다 (`Workflow({script, args: {...}})` — 스크립트 안에서 전역 `args` 로 접근). `args` 쪽이 정석이다.
