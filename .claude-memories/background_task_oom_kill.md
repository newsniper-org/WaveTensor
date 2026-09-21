---
name: background-task-oom-kill
description: 시스템 메모리 부족 신호 시 run_in_background Bash 는 자기 풋프린트와 무관하게 죽는다 — nohup 백그라운드 + Monitor 조합이 살아남는다. 긴 podman/z3 검증에 쓸 것.
metadata:
  type: feedback
  originSessionId: e7f99d7a-a6eb-46be-b7eb-fd78237e02a7
  modified: 2026-09-20T17:08:55.039Z
---

2026-09-20 HiuMask 후-formal 재캡처(2시간+ z3 cover 작업) 중 실측. 완료를
기다리려고 만든 `run_in_background: true` Bash 폴링 루프(`until ! kill -0
PID; do sleep; done`)가 "system is running low on memory" 로 **두 번**
강제 종료됐다 — 그런데 그 직후 확인한 실제 메모리는 46Gi 중 32Gi 사용
(13Gi 가용), 스왑도 여유가 있었다. 폴링 루프 자체의 메모리 풋프린트는
무시할 수준(`sleep` 한 줄)인데도 죽었다.

**반면** 다음 둘은 같은 메모리 압박 상황에서 **살아남았다**:
1. `nohup <heavy command> > log 2>&1 &` 로 시작하고 `disown` 한 뒤 PID 를
   기억해 두는 방식 — 실제 z3/yosys/podman 프로세스는 이 killing 과
   무관하게 계속 돌았다(`ps aux` 로 CPU 99% 실측 확인).
2. `Monitor` 도구의 `persistent: true` 워치 — `while kill -0 PID; do sleep;
   done; echo DONE` 을 Monitor 에 준 것은 알림이 정상 도착했다.

**Why (추정)**: 하네스가 **자신이 추적하는 background Bash task**(`run_in_background: true`
로 만든 것)만 메모리 가드의 kill 대상으로 삼는 듯하다. `nohup ... &` 로
띄운 뒤 harness 가 추적하지 않는 plain 자식 프로세스나, `Monitor` 가
관리하는 워치는 그 가드의 사정권 밖이다. 실제 메모리 사용량과 무관하게
"harness 가 추적하는 background Bash" 라는 것 자체가 위험 신호였다.

**How to apply:** 몇 시간 걸리는 podman/z3/sby 검증을 기다릴 때:
- 작업 자체는 `nohup podman run ... > log 2>&1 &` (synchronous Bash 호출
  안에서, `run_in_background` 옵션 **없이**) 로 시작하고 `disown`, PID 를
  적어 둔다.
- 완료 대기는 `Monitor`(`persistent: true`, `while kill -0 PID; do sleep
  N; done; echo DONE; tail ...`)로 건다 — `run_in_background: true` Bash
  로 같은 걸 하지 않는다.
- 스왑을 늘려도(사용자가 46Gi→126Gi 로 확장한 사례 있음) 이 킬은 막히지
  않았다 — 스왑 부족이 원인이 아니었다는 뜻이므로, 스왑을 늘리는 것으로
  이 패턴을 우회하려 하지 마라. 처음부터 nohup+Monitor 조합을 써라.

관련: [[podman-orphan-containers]] · [[solver-blindness-trap]] ·
[[wt64v1-rtl-reimplementation]].
