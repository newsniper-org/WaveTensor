---
name: btrfs-metadata-enospc
description: nvme btrfs 가 df 로는 88G 여유인데 메타데이터 청크가 꽉 차 쓰기가 간헐 ENOSPC — sby 게이트가 SIGBUS·잘린 JSON·21 FAIL 로 위장한다
metadata:
  node_type: memory
  type: project
  originSessionId: e7f99d7a-a6eb-46be-b7eb-fd78237e02a7
  modified: 2026-10-24T07:53:57.429Z
---

2026-10-24 W7 게이트: `/` (nvme btrfs) 의 Data 청크가 디스크 전부를 할당(911.49/≈930 GiB, 실사용 824)해 Metadata(9.00 GiB, 8.5 사용 + GlobalReserve 512M)가 자랄 자리가 없었다. `df` 는 88G 여유를 보이지만 쓰기가 간헐적으로 ENOSPC — sby 가 `OSError 28`, SIGBUS(rc=135), yosys 의 잘린 JSON, 컨테이너 `/tmp/log-…` 실패(28 중 21 FAIL)로 나타났다. 외장 SSD 도 100%, /tmp tmpfs 는 남의 세션(AD1·loom-research) scratch 로 85%.

**Why:** 게이트 실패를 설계 결함으로 오독하기 쉽다 — [[solver-blindness-trap]] 의 「느림 ≠ 웨지」처럼 「FAIL ≠ 결함」, 먼저 `btrfs filesystem df /` 를 본다.

**How to apply:** 게이트 전후 `btrfs filesystem df /` 로 Metadata used/total 확인. 우리 scratch(`/var/tmp/wt-s310` 의 커밋된 파도 디렉터리)를 치우면 조금 돌아온다(11G → 0.13 GiB 메타). 근본 해결은 `sudo btrfs balance start -dusage=N /` — sudo 라 사용자 몫. 컨테이너가 만든 파일은 subuid 소유라 호스트에서 rm 이 거부된다(`podman unshare rm` 필요). [[tmpfs-scratch-exhaustion]] [[scratch-space-fallback]]
