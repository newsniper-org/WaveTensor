---
name: scratch-space-fallback
description: 2026-10-25 개정 — 큰 산출물은 /tmp(tmpfs, swap 254G 로 받침), 재개 캐시만 외장 SSD wt-tmp/; nvme 는 btrfs 메타 포화로 피한다; podman 스토리지 건드리지 말 것
metadata:
  node_type: memory
  type: feedback
  originSessionId: e7f99d7a-a6eb-46be-b7eb-fd78237e02a7
  modified: 2026-10-11T08:45:07.048Z
---

**2026-10-25 개정 (사용자 지시, 아래 옛 순서보다 우선):** 「swap을 넉넉하게 넓혀놨으니, 크레딧 소진 시 중단된 작업들을 재개하는 데에 필요한 캐시들만 외장 SSD에 저장해두는 타협책」 · 「podman 스토리지는 건드리지 말고」.
- 큰 산출물(sby `SBY_OUT`/prefix · 변이 사본 · 스윕 출력 · 빌드) → 호스트 `/tmp/wt-*` (tmpfs, swap 254G 가 받친다). `TMPDIR=/tmp`.
- 재개 캐시(progress.md · 보고서 · 스크립트 · lintdraft · tmpindex · 요약 로그 · headwt) → 외장 SSD `wt-tmp/wt-s310`; `/var/tmp/wt-s310` 은 그 심링크(옛 경로 · 워크플로 캐시 유지).
- nvme(`/`, `/var/tmp`)는 btrfs 메타데이터 포화라 쓰지 않는다 — [[btrfs-metadata-enospc]].
- podman 스토리지(graphroot `~/.local/share/containers/storage` · runroot · SSD 의 `podman/` · `heavy_storage.conf`)는 건드리지 않는다.

(옛 규칙, 2026-10-11) 무거운 임시물(TLC metadir · sby 출력 · 워크트리 · 변이 사본 · Verilator 빌드 · 로그)의 자리는
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
