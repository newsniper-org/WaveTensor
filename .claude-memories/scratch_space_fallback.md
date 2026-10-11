---
name: scratch-space-fallback
description: 임시 공간 순서 /tmp → /var/tmp → 외장 SSD(PSSD T9) 의 전용 임시폴더 — 사용자 지시 2026-10-11
metadata:
  node_type: memory
  type: feedback
  originSessionId: e7f99d7a-a6eb-46be-b7eb-fd78237e02a7
  modified: 2026-10-11T08:45:07.048Z
---

무거운 임시물(TLC metadir · sby 출력 · 워크트리 · 변이 사본 · Verilator 빌드 · 로그)의 자리는
`/tmp`(tmpfs 24G, 남의 scratch 로 자주 찬다) → `/var/tmp`(루트 nvme, 2026-10-11 여유 ~61G) →
**외장 SSD 의 전용 임시폴더** 순이다. 사용자 지시 (2026-10-11): 「`/var/tmp/`도 용량 모자라게 되면,
외장 SSD에 임시폴더 만들어서 쓰도록.」

- 외장 SSD: Samsung PSSD T9, `/run/media/ybi/6ee5fba6-c9b3-4c4c-954f-89d39f34b4c7` (btrfs, ~574G 여유).
  사용자 개인 파일이 같은 루트에 있다 — 반드시 전용 하위 폴더(예: `wt-tmp/`)를 만들어 그 안에서만 쓰고,
  다 쓰면 그 폴더만 치운다. 다른 항목은 건드리지 않는다.
- USB 이동식 장치라 마운트 경로가 바뀌거나 빠져 있을 수 있다 — 쓰기 전에 `findmnt` 로 확인.

**Why:** `/tmp` 고갈로 검증 에이전트가 ENOSPC 로 죽은 선례([[tmpfs-scratch-exhaustion]]); 남의 scratch 는
지우지 않는다(사용자가 그대로 두라고 했다, 2026-10-11).

**How to apply:** 파도 시작 때 `df -h /tmp /var/tmp` 를 보고, `/var/tmp` 여유가 작업량(예: postformal 전수 ·
TLC 배터리 · 워크트리 여럿)에 비해 모자라면(대략 15G 미만) 외장 SSD 폴더로 `TMPDIR` · `SBY_OUT` · 워크트리를 옮긴다.
