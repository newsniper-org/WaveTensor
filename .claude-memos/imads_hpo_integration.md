<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# imads-hpo 가속기 연계 — 검토

> **연관 메모**: [`notebook_web_ui.md`](./notebook_web_ui.md) — HPO 잡 발사/모니터링은 노트북 UI의 자연스러운 use case. [`remote_accelerator_access.md`](./remote_accelerator_access.md) — HPO 가 다수 trial 을 동시 발사할 때 lease/큐 협상.
>
> **저장소**:
> - 알고리즘 코어: https://github.com/Honey-Be/imads (Rust + multi-lang FFI)
> - HPO 응용: https://github.com/Honey-Be/imads-hpo (Python/PyTorch)

## 두 저장소의 계층 관계

```
+------------------------------------------------+
| imads-hpo                                      |
|   - PyTorch 기반 HPO 워크로드                   |
|   - multi-fidelity / multi-objective / 제약     |
|   - 모델 forward·backward (가속 대상)            |
+----------------------+-------------------------+
                       | uses (FFI)
                       v
+------------------------------------------------+
| imads (algorithm core)                         |
|   - Rust 75.5% native 구현                      |
|   - FFI bindings: C/C++, Python 3.x, WASM,     |
|     Kotlin/Scala/Clojure                       |
|   - Mesh Adaptive Direct Search (MADS)          |
|   - derivative-free 최적화                       |
+------------------------------------------------+
```

핵심 분업:
- **imads**: 검색 알고리즘 (Rust로 빠르게 — CPU에서 충분)
- **imads-hpo**: 검색을 PyTorch 모델 평가 루프와 결합 (이게 진짜 무거움)
- **WaveTensor 가속기**: imads-hpo 의 inner loop인 **모델 평가** 를 가속

## imads-hpo 요약

PyTorch 기반 HPO (HyperParameter Optimization) 패키지. 핵심 특징:

- **IMADS** (Integrated Mesh Adaptive Direct Search) — gradient-free, mesh-adaptive 직접 탐색. 이산/혼합 hyperparameter 공간에 적합. 알고리즘 코어는 별도 저장소 `imads` 에 Rust 로 구현됨.
- **Multi-fidelity**: epoch 수를 늘려가며 점진적 평가
- **Multi-objective**: Pareto front 추출
- **Constraint**: GPU 메모리, 지연, 모델 크기를 first-class 제약으로 둠
- **재현성**: seed/checkpoint 기반
- **64-bit 정수 인코딩**: categorical 변수 지원
- **대시보드**: W&B, MLflow, TensorBoard

런타임 지배 요소: **신경망 forward/backward + constraint 평가**. 즉 PyTorch 잡 자체가 가속 대상. (검색 알고리즘 자체는 Rust 코어에서 돌아 가속 불필요.)

## imads 저장소 자체에 대한 시너지

`imads` 가 Rust 코어 + 다중 언어 FFI 라는 점이 우리에게 **추가 시너지** 를 제공:

1. **WaveTensor SDK 도 Rust 로 작성하면 imads 와 동일 ABI/언어 생태계** — Python, WASM, JVM-군 모두에서 일관된 통합 가능
2. **Notebook UI 의 HPO panel** 이 Python 측에서 imads + WaveTensor 둘 다를 동일 패턴 (Rust FFI) 으로 호출 가능
3. **Edge / 임베디드 환경** 에서도 imads + WaveTensor 묶음이 작동 — Rust + WASM 이라 브라우저 내 시뮬레이션도 후일 가능
4. **derivative-free 라는 점이 우리 forward-only 가속기와 본질적으로 잘 맞음** — backprop 가속이 미완성인 단계에서도 imads-hpo 의 evaluation 단계는 가속됨

## 가속기 연계 시 가치

### 잘 맞는 부분

1. **다수 trial 병렬 평가** — IMADS는 mesh adaptive로 다수 후보를 발사. WaveTensor 의 PE/Cluster/Pod 다중 실행 단위가 trial 분산에 자연스럽게 매핑.
2. **Multi-fidelity 의 저-fidelity 단계** — 짧은 epoch 의 빠른 평가는 가속기 latency benefit 이 직접적
3. **Constraint 평가 (latency/memory)** — 가속기에서 직접 측정하는 지연/자원 사용량이 IMADS 의 constraint 입력으로 그대로 활용됨 → "예측" 이 아닌 "실측" constraint
4. **64-bit 정수 인코딩 categorical** — WaveTensor 의 ZERO/ONE 레지스터 + integer ALU 가 정확히 64-bit 정수 처리에 부합 (Bit-Fusion ALU 의 INT64 mode)
5. **Pareto multi-objective** — 다양한 objective 를 가속기에서 동시 평가 후 Pareto 갱신은 호스트 측에서 수행 → 분업 자연스러움

### 통합 지점 (어디에 hook?)

| imads-hpo 측 | WaveTensor 측 | 연결 방법 |
|------------|------------|---------|
| `objective_fn(model, x, y)` 호출 | PyTorch forward/backward | `torch.compile` backend 또는 PyTorch 의 custom `Module` 가 가속기로 발사 |
| Constraint: latency 측정 | 가속기 cycle counter | `lower_required` 처리 후 cycle 수 → wall-time 변환 (post-synth timing) |
| Constraint: memory | HIU 의 DMA 트랜잭션 카운터 | HIU 에 별도 telemetry register 추가 필요 |
| Multi-fidelity dispatch | trial 별 lease 점유/해제 | `remote_accelerator_access.md` 의 daemon RPC |
| Categorical → 정수 | 가속기 INT64 ALU | 그대로 — 추가 작업 없음 |

### 통합의 효과 (예측)

- **시간 절감**: trial-당 epoch 평가가 GPU 대비 가속되면, total HPO 시간이 비례 감소 (IMADS 가 trial 수 증가시키므로 효과 크게 누적)
- **에너지 효율**: HPO 는 본질적으로 "낭비 많은" 워크로드 (실패한 trial 의 비용 큼). 가속기의 ops/J 가 GPU 보다 좋으면 누적 절감 큼
- **보다 정밀한 constraint**: 실측 latency/memory 가 곧 constraint → IMADS 가 더 정확한 Pareto front 도출

## 통합 시 필요한 작업 (연계 작업 후보)

1. **PyTorch backend** — WaveTensor 어셈블러를 `torch.compile` backend 로 wrapping (또는 ONNX → WaveTensor lowering)
   - 이게 imads-hpo 통합의 가장 큰 prerequisite
   - 현재 어셈블러는 텐서 연산을 LL 로 lower 가능 — `torch.fx` 그래프 → 어셈블러 호출은 별도 layer
2. **HIU telemetry registers** — DMA 횟수, BRAM read/write count, cycle accumulator 노출. Constraint 측정 데이터 소스
3. **Lease + multi-trial** — HPO 가 여러 trial 을 발사할 때 가속기를 시분할 또는 (가속기가 충분히 크면) 공간 분할 — 후자는 PE/Cluster grid 가 trial 별로 격리될 수 있어야 함 → Pod 수준 격리 메커니즘 필요
4. **imads-hpo 자체 patch** — 가속기 backend 인지 시 evaluation loop 가 daemon RPC 로 전환되도록 plugin 추가
   - PR 또는 fork 로 진입 (저장소 주인이 본인이라면 직접)
5. **Notebook UI 의 HPO panel** — IMADS 진행 상황, Pareto front, trial 상태를 노트북 안에서 가시화 ([`notebook_web_ui.md`](./notebook_web_ui.md) 의 dashboard 항목)

## 지금 단계에서의 의의

- **"가속기 + HPO" demo 가 첫 wall-clock 비교의 강력한 사례** — RTX 5050 GPU 와 직접 비교 가능 (`(III) GPU 비교` 메모리 ↑)
- **사용자 친화적인 첫 응용** — 노트북에 IMADS 잡 띄우고 가속기에서 trial 발사하는 데모는 PR 가치도 큼
- IMADS 의 gradient-free 성질 덕에 **forward-only 가속기로도 의미 있음** — backprop 가속이 미완성이어도 evaluation 단계에서 가치 창출 가능

## 미해결 / 추후 결정

- **소유권**: imads / imads-hpo 두 저장소 주인이 동일인 (`Honey-Be`) — 맞으면 직접 patch, 아니면 contribution PR
- **Backprop**: 현재 가속기는 forward 위주. backprop 가속은 별도 RTL 작업 필요 (큰 범위) — 처음엔 forward-only HPO 데모로 시작, backprop 은 후속. *참고*: imads 의 derivative-free 성질 덕에 backprop 미완 상태로도 imads-hpo 통합은 의미를 가짐.
- **PyTorch ↔ WaveTensor lowering 의 범위**: imads-hpo 는 사용자 정의 모델을 받음 → 임의 PyTorch nn.Module 을 자동 lowering 하려면 graph capture (torch.fx, torch.compile) 인프라 필수
- **단일 가속기에서의 trial 격리**: 같은 시각 trial A,B 가 같은 가속기를 점유하면 결과 격리 어떻게? Pod 단위로 분할? lease 단위로 시분할?
- **결과 reproducibility**: 가속기 RTL 버전 + 합성 결과 + imads seed + imads-hpo 설정 이 모두 한 archive 로 묶여야 — `notebook_web_ui.md` 의 재현성 항목과 연동
- ~~**WaveTensor SDK 의 언어 선택**~~ → **결정됨**: imads 와 동일하게 **Rust core + 다중 FFI** (C/C++, Python, WASM Component Model, JVM FFM/JDK22+). 자세한 내용은 [`sdk_architecture.md`](./sdk_architecture.md).

## 진입 트리거

- PyTorch ↔ WaveTensor lowering 인프라 (별도 큰 작업) 가 갖춰진 후 — 그 전엔 단순 demo 만 가능
- 또는 GPU 비교 (`(III)`) 단계에서 imads-hpo 를 벤치마크 워크로드로 채택 시 함께 작업
- 외부 publication / demo 일정 시
