---
name: tmpfs-scratch-exhaustion
description: /tmp 는 24G tmpfs 이고 세션 scratchpad·/tmp/wt_sim_*·/tmp/wt-sby-out 이 전부 거기 산다 — 파도가 쌓이면 검증 에이전트가 ENOSPC 로 죽는다
metadata:
  node_type: memory
  type: project
  originSessionId: e7f99d7a-a6eb-46be-b7eb-fd78237e02a7
  modified: 2026-09-25T21:46:41.537Z
---

/tmp 는 24G **tmpfs** 다(RAM 이다). 세션 scratchpad(`/tmp/claude-1000/…`),
`run_wt64.py` 의 mkdtemp 빌드 루트(`/tmp/wt_sim_*`, 개당 ~230M — 러너가
**지우지 않는다**), `SBY_OUT=/tmp/wt-sby-out` 이 전부 여기에 쌓인다.
2026-09-26 파도 3 에서 98%(640M 남음)까지 차 검토 에이전트의 rtl-gen·rtl-sim
사본이 ENOSPC 로 죽었다 — 한 에이전트는 `/var/tmp` 로 옮겨 우회했다.

**Why:** 워크플로 에이전트마다 저장소 사본(~90–230M)과 sim 빌드를 scratchpad
에 만들고, 파도가 커밋된 뒤에도 아무도 치우지 않는다. 한 세션의 scratchpad 만
6.5G 였다.

**How to apply:** 파도를 커밋한 뒤에는 그 파도의 세션 scratch 디렉터리를
지운다(커밋 시각 이전 것만 — 진행 중 파도의 증거 로그는 남긴다). 파도 시작 전
`df -h /tmp` 를 본다. 내가 돌린 `make rtl-sim` 의 `/tmp/wt_sim_*` 는 로그의
「build root」 줄로 찾아 지운다; 남의 것·다른 저장소의 /tmp 디렉터리는 사용자
몫이다. 큰 사본이 필요한 에이전트에게는 `/var/tmp` 를 지정한다. 이월:
`run_wt64.py` 가 자기 mkdtemp 루트를 종료 시 지우게 하기. 관련
[[background-task-oom-kill]] · [[podman-orphan-containers]].
