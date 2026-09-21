---
name: host-tlc-shadow-package
description: 호스트의 /usr/bin/tlc 는 이 프로젝트의 것이 아니라 무관한 시스템 패키지(구버전) — rtl/formal/tla/run.sh 는 devcontainer 안에서 돌려야 한다.
metadata:
  type: project
  originSessionId: e7f99d7a-a6eb-46be-b7eb-fd78237e02a7
  modified: 2026-09-20T17:08:39.440Z
---

2026-09-21 실측: 이 작업 호스트에 시스템 패키지로 설치된 `/usr/bin/tlc`
(`/usr/share/java/tla2tools.jar` 경유, TLC2 2.19 of 08 August 2024)가
**이 프로젝트가 pin 한 것과 무관한, 훨씬 구버전**의 TLC 다. `wavetensor-dev:scala`
컨테이너 안의 `tlc` 는 프로젝트가 보관·고정한 빌드(`TLC2 2026.09.10.191157`,
[[rolling-asset-pin-trap]] 이 착지시킨 바로 그 jar)를 쓴다.

**증상**: `rtl/formal/tla/run.sh`(재구현 전용, `-noGenerateSpecTE` 플래그
사용 — 신형 TLC 에만 있음)를 호스트에서 직접 `sh rtl/formal/tla/run.sh`
로 돌리면 `Error: unrecognized option: -noGenerateSpecTE` 로 **368 run
전부** 즉시 실패한다. 반면 `proofs/tla/run.sh`(레거시 16 run, 그 플래그를
쓰지 않음)는 같은 호스트 tlc 로도 통과해서 **한쪽만 실패하는 것처럼
보인다** — 원인이 TLA 모델 결함이 아니라 도구 선택 오류임을 가리기 쉽다.

**Why:** `Makefile` 의 `rtl-formal` 타깃 자체가 `sh $(RTL_DIR)/formal/tla/run.sh`
를 **podman 래핑 없이** 직접 호출한다(`rtl-postformal` 과 다르게). 이는
"터미널이 이미 devcontainer 안"이라는 표준 devcontainer 워크플로를
전제한 것 — Claude Code 가 raw 호스트 셸에서 돌릴 때는 이 전제가
깨진다.

**How to apply:** `rtl/formal/tla/run.sh` 를 raw 호스트에서 돌려 실패가
나오면, 먼저 `which tlc` → `cat $(which tlc)` 로 그 tlc 가 실제로 이
프로젝트의 것인지(`/usr/share/java/tla2tools.jar` 가 아니라 컨테이너가
빌드에서 까는 경로인지) 확인하라. 아니라면 RTL 결함을 의심하기 전에
컨테이너로 옮겨라:

```sh
podman run --rm --userns=keep-id -v "$(pwd):/workspace" wavetensor-dev:scala \
  sh -lc "cd /workspace && sh rtl/formal/tla/run.sh"
```

`proofs/tla/run.sh`(플래그 없음)는 호스트에서도 무해하게 통과하므로 이
증상의 존재 자체가 진단 신호다 — 레거시 게이트는 통과하는데 신형만
실패하면 모델이 아니라 도구를 의심하라.

호스트 패키지를 제거·수정하는 것은 이 세션의 권한 밖(시스템 변경)이며,
어차피 이 프로젝트의 진짜 게이트는 컨테이너 안에서만 의미가 있다 —
호스트 `tlc` 를 "고치려" 하지 마라.

관련: [[rolling-asset-pin-trap]] · [[podman-orphan-containers]] ·
[[wt64v1-rtl-reimplementation]].
