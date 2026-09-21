---
name: agent-concurrency-cap
description: 이 프로젝트의 동시 실행 에이전트 상한은 4개 — 사용자 지시 2026-09-21, 크레딧 고갈 방지. Workflow 의 parallel/pipeline 폭을 4 이하로.
metadata:
  type: feedback
  originSessionId: e7f99d7a-a6eb-46be-b7eb-fd78237e02a7
  modified: 2026-09-21T11:01:22.464Z
---

**이 프로젝트(WaveTensor)에서 동시에 실행하는 에이전트는 최대 4개.**

사용자 원문(2026-09-21): "크레딧 고갈을 방지하기 위해, 이 프로젝트의 전체
동시 실행 에이전트 상한을 4개로 묶어놓을 것!"

**Why:** 주간 한도(weekly limit) 소진으로 워크플로 에이전트 6개·5개가 통째로
실패한 전례가 같은 세션에 있다 — 넓게 펼치면 한 파도 안에서 한도를 다
태우고, 실패한 에이전트의 작업은 재시도 비용까지 이중으로 든다.

**How to apply:**
- `Workflow` 스크립트에서 `parallel([...])` 의 원소 수, `pipeline()` 의
  동시 진행 폭, `phase` 안에서 동시에 뜨는 `agent()` 수를 **합쳐서 4 이하**로
  설계한다. 넓은 팬아웃은 `chunk(4)` 로 잘라 순차 배치한다.
- `Agent` 도구로 직접 띄우는 fork/서브에이전트도 같은 상한에 포함된다 —
  워크플로가 4개를 쓰고 있으면 그 위에 fork 를 더 띄우지 않는다.
- [[ultracode-default]](매 작업 워크플로 + 전수 검증)는 그대로 — 폭을
  줄이고 깊이(단계 수)로 같은 검증량을 채운다.
