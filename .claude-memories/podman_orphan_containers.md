---
name: podman-orphan-containers
description: podman run 클라이언트를 죽여도(타임아웃·TaskStop) 컨테이너는 살아남는다 — TLC 동시 실행 오염의 원인
metadata: 
  node_type: memory
  type: feedback
  originSessionId: e7f99d7a-a6eb-46be-b7eb-fd78237e02a7
  modified: 2026-08-23T10:05:07.821Z
---

`podman run`(비-detached)의 클라이언트 프로세스를 timeout/SIGTERM/TaskStop 으로 죽여도 **컨테이너와 그 안의 작업은 계속 돈다** (conmon 이 분리 유지). 실측 2회 (2026-08-22 워크플로 중단 시, 2026-08-23 10분 타임아웃 스윕): 살아남은 TLC 컨테이너가 이후 시작한 배터리와 같은 작업 디렉터리에서 겹쳐 상태 풀 오염 → 배터리 6 run 이 pool-read 오류로 RED.

**Why:** 클라이언트 kill ≠ 컨테이너 kill. 겹친 TLC 는 기본 metadir(`./states`) 공유로 서로의 상태를 밟는다.

**How to apply:**
1. 장시간 podman 작업을 중단·타임아웃시켰다면 **반드시 `podman ps` 로 고아를 확인하고 `podman rm -f`** 후 다음 작업을 시작한다.
2. WaveTensor 의 `rtl/formal/tla/run.sh` 는 run 별 고유 `-metadir` 로 경화됨(2026-08-23) — 새 TLC 호출 스크립트를 짤 때도 `-metadir $(mktemp -d)` 를 기본으로.
3. 긴 배터리는 timeout 을 걸지 말고 `run_in_background` + 로그 감시로.
