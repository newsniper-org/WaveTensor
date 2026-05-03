<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# 원격 가속기 인스턴스 접근 — 서버팜 구성 검토

> **연관 메모**: [`notebook_web_ui.md`](./notebook_web_ui.md) — 본 메모에서 정의되는 daemon RPC / lease API의 가장 중요한 클라이언트는 M에서 돌아갈 노트북 웹 UI. 두 메모는 동일 시스템의 control-plane (이 메모) + user-plane (그 메모) 양면.

## 상정 시나리오

| 노드 | 역할 |
|------|------|
| **A** | 가속기 (WaveTensor FPGA) 가 물리적으로 꽂혀 있는 호스트 PC |
| **M** | 메인 서버 — 실제 사용자/잡이 돌아가는 곳, 가속기를 사용할 클라이언트 |
| **S** | 스토리지 서버 — 모델 weight, 데이터셋 |
| **N** | 네트워크 스위치 |
| **R** | 인터넷 접속용 라우터 |

**물리 토폴로지**: A, M, S, R 전부 N (스위치) 에 직접 연결되는 단일-스위치 LAN 구성.

```
        +-- R (internet)
        |
   +----N----+
   |    |    |
   A    M    S
```

→ A↔M, M↔S, A↔S 모두 **동일 L2 도메인** 안에서 single-hop. 별도 라우팅/터널 없음.

요구사항: M에서 A의 가속기 인스턴스에 "원격으로 연결해 두고 필요할 때만 사용". 즉 평소엔 idle 상태로 두고, M의 잡이 발사할 때만 가속기 자원을 점유.

## 후보 접근법

### (1) Userspace daemon + RPC (gRPC / Cap'n Proto / 자체)
- A 측에 가속기 드라이버 wrapping daemon (`wavetensord`) 상시 가동
- M 측이 client lib (Python/Rust)로 연결
- 잡 시작 시 `wavetensord.acquire()` → 가속기 owner=M, idle 시 release
- 큐 / lease / heartbeat 기반 점유 관리
- **장점**: 구현 자유도 ↑, 다중 클라이언트 lease 협상 가능
- **단점**: 직접 짜야 함, 인증/암호화 별도 필요

### (2) PCIe-over-Network passthrough (예: NVMe-oF style)
- 가속기를 M의 로컬 PCIe 디바이스처럼 보이게 함
- 후보 프로토콜: NVMe-oF (의미적으로는 NVMe 디스크용이지만 일부 벤더가 일반 PCIe 장치로 확장), CXL.io over fabric, USB/IP, PCIe-over-ethernet (Liqid 등 상용)
- **장점**: M의 SW 스택은 가속기가 로컬에 있는 것처럼 동작
- **단점**: 표준화 미숙, 레이턴시 큼, 호스트 OS 커널 모듈 필요

### (3) Container/VM hand-off (LXC, KVM PCI passthrough)
- A에 컨테이너 또는 VM 템플릿을 두고, 가속기 PCI를 그 컨테이너에 passthrough
- M이 SSH/원격 컨테이너 SDK 로 인스턴스 시작 → 잡 끝나면 컨테이너 stop → 가속기 released
- 도구 후보: Docker + `--device`, Podman, Kata, Firecracker, libvirt + KVM
- **장점**: 표준 도구, 격리 견고
- **단점**: 시작 latency (수 초~수십 초), 컨테이너 안에서도 결국 (1) 같은 RPC 필요

### (4) Job scheduler 통합 (Slurm / Kubernetes device plugin)
- A가 cluster의 한 노드, 가속기를 K8s device plugin (또는 Slurm GRES) 로 advertise
- M 측에서 `kubectl run --requests='wavetensor.dev/accel: 1'` 같은 식으로 점유
- **장점**: 다중 사용자/잡 큐 관리 자동화
- **단점**: orchestrator 도입 비용, 단일 가속기 + 단일 메인 서버 시나리오엔 과한 인프라

## 권장 — Phase 별

| 단계 | 권장 |
|------|------|
| Phase 0 (개발) | **(1) userspace daemon + RPC**. 빠르게 가속기 노출, M에서 연결 테스트. |
| Phase 1 (실험) | **(1) + 인증/lease 추가**. mTLS + 토큰, 점유 timeout, heartbeat. |
| Phase 2 (다중 사용자) | **(4) Slurm 또는 Kubernetes**. 잡 큐 + 가속기 자원 broker. |
| Phase 3 (대규모) | **(2) PCIe-over-fabric** 또는 CXL 패브릭 — A 자체를 없애고 가속기를 직접 패브릭에 매다는 방향. |

## 우리 가속기 측 사전 준비 (RTL/펌웨어 레벨)

- HIU의 호스트 인터페이스 추상화는 이미 PCIe/USB/CXL 등 어떤 full-duplex 매체든 받을 수 있음
- 단, **여러 호스트가 시간 분할로 점유하는 시나리오** 를 위해 다음을 검토:
  - context_switch 신호 (이미 HIU에 있음) 가 호스트 lease 전환 시 호출되도록 daemon이 wiring
  - 가속기의 모든 가상 메모리 매핑이 lease 종료 시 flush (TLB flush 기능 이미 존재)
  - lease 종료 시 미완 wave 토큰 drain → side-channel 공격 방지 (XChaCha20 masking 이미 있음)

## 단일-스위치 LAN 토폴로지에 따른 추가 고려

- **A↔S 직접 데이터 경로**: M이 가속기 잡을 dispatch한 뒤 weight/dataset 은 S→A 직접 (M을 거치지 않고) — 같은 L2이므로 single-hop. M은 control-plane만 담당.
- **N의 capacity가 병목**: A,M,S가 동시에 풀 대역 통신하면 스위치 backplane 한계가 곧 시스템 한계. N의 사양 (1G/10G/25G) 이 가속기 throughput 상한을 결정.
- **L2 multicast/broadcast** 활용: A의 telemetry (가속기 상태, lease 만료 알림) 를 M+S에 동시 broadcast 가능 — 같은 broadcast 도메인이라 zero-cost.
- **R(인터넷) 격리**: 가속기 RPC는 LAN-only. R 으로 outbound 차단 (방화벽 규칙) → 가속기 endpoint가 실수로 외부 노출되지 않도록.
- **시간 동기화**: A,M,S가 같은 LAN이면 chrony/PTP로 µs 단위 sync 쉬움. lease timestamp / heartbeat 정밀도에 유리.

## 미해결 / 추후 결정

- **연결 매체**: 일반 ethernet (TCP/IP) vs. RDMA (RoCE/InfiniBand)
  - 가속기 throughput 이 작으면 ethernet 충분
  - 큰 텐서 weight load 시 (S→A) 엔 RDMA 가 latency/throughput 면에서 유리
  - 단일-스위치 LAN 이라 RDMA 도입 시 N이 RoCE-capable 인지 확인 필요
- **N 등급**: 1GbE/10GbE/25GbE 중 어느 것? 가속기 burst peak 와 매칭되는지 검토
- **다중 가속기 (single A 에 여러 보드)** 시 동일 daemon 이 sub-device id 로 route
- **A의 호스트 OS 부담**: A가 "단순 가속기 호스트" 면 가벼운 OS (Alpine, NixOS minimal) 로 daemon 만 가동. M의 잡 SW 와 격리.

## 진입 트리거

이 메모는 다음 중 하나가 충족되면 작업 진입:
- FPGA 합성 + 보드 도착 후 첫 wall-clock 검증 단계
- 또는 사용자께서 "이제 원격 점유 daemon 작업하자" 신호 시
