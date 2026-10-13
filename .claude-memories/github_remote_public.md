---
name: github-remote-public
description: origin(Honey-Be/WaveTensor-private)은 newsniper-org/WaveTensor 로 옮겨져 public — 2026-07-15 까지 30 커밋만 올라가 있다 (2026-10-12 확인)
metadata:
  node_type: memory
  type: project
  originSessionId: e7f99d7a-a6eb-46be-b7eb-fd78237e02a7
  modified: 2026-10-12T01:47:11.270Z
---

`git remote` 의 origin `git@github.com:Honey-Be/WaveTensor-private.git` 은 GitHub API 상
**`newsniper-org/WaveTensor`, visibility public** 으로 리다이렉트된다(2026-10-12 확인, pushed_at 2026-07-15).
올라간 것은 origin/main 30 커밋(마지막 09a33ce, 참조 구현 v1.6.5a+6 — 루트 `.v` RTL 과 SHL-2.1 /
CERN-OHL-W-2.0 · CC-BY-4.0 라이선스 표기)뿐이고, 그 뒤 로컬 커밋(정본 · 재구현 · 형식 검증, 250+)은
push 하지 않았다. 저장소 이름의 「-private」와 실제 공개 상태가 다르다 — 사업 문서 사실 검토가 적발했다.

**Why:** 대외 문서에 「저장소 비공개」라고 썼다가 거짓으로 판정됐다. 공개 의도는 사용자 확인 전이다.

**How to apply:** 공개 여부 · 라이선스가 걸린 판단(사업 모델, 이중 라이선스, 공개 시점)에서 이 사실을 전제로
삼고, push 는 사용자 지시 없이 하지 않는다. 상태는 `gh repo view` 로 다시 확인한다.
