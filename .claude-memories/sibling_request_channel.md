---
name: sibling-request-channel
description: "형제 저장소(Y4 등)와의 소통은 상대 파일을 고치지 않고 `.local-requests-*/.local-replies-*` 디렉터리에 「어떻게 할까요?」 메시지로 — Y4 관례; Y4 에 WaveTensor 소스 「읽기 전용 조건부」 접근을 허용했다(2026-10-01)"
metadata:
  node_type: memory
  type: feedback
  originSessionId: e7f99d7a-a6eb-46be-b7eb-fd78237e02a7
  modified: 2026-10-01T04:14:56.822Z
---

형제 저장소에 무언가를 알리거나 요청할 때는 **상대 저장소의 CLAUDE.md · 메모리 ·
문서를 고치지 말고**, 요청 디렉터리에 「어떻게 할까요?」 식 메시지를 둔다 (사용자 지시
2026-10-01: 「`~/Y4/.local-requests-from/WaveTensor` 디렉터리를 만들어서 거기에 "어떻게
할까요?" 식의 메세지로 보내면 되잖아?」).

관례는 Y4 `.gitignore` 가 정한 네 디렉터리다(전부 git 이력 밖 — WaveTensor 도 `.gitignore`
에 넣었다):
- 발신 원본 `<나>/.local-requests-to/<상대>/` → 상대의 `.local-requests-from/<나>/` 로 거울
- 답장 `<상대>/.local-replies-to/<나>/` → 나의 `.local-replies-from/<상대>/` 로 거울

**Why:** 상대 저장소의 지침 파일을 직접 고치면 상대 세션의 결정권을 빼앗는다. 첫 시도에서
Y4 CLAUDE.md §7 · 메모리 · 트래커를 고치려다 사용자가 끊었다.

**How to apply:** 형제 저장소 소통은 먼저 이 채널부터. 새 세션을 시작하면 `.local-replies-from/`
와 `.local-requests-from/` 에 도착한 것이 있는지 본다.

2026-10-01 첫 발신: `.local-requests-to/Y4/2026-10-01-status-and-read-access.md` — 현황 ·
「읽기 전용 조건부」 소스 접근 허용 방침(읽기만 · 정본 > rtl 실물 > memos, legacy 루트 *.v 는
ABI 근거 아님 · sha 고정 인용 · legacy 내용을 WaveTensor 로 옮기지 않음(clean-room,
[[cleanroom-airlock]]) · 쓰기 권한 확장 아님 · 라이선스 경계) · 결정 요청 일곱(특히
Y4 `docs/hiu_abi.md` 56행의 판 0 — Y4 가 2026-10-02 (a) 「약속 없음」 채택). 관련 [[wt64v1-rtl-reimplementation]].
