<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# WaveTensor SDK 아키텍처 — Rust core + 다중 언어 FFI

> **연관 메모**: [`imads_hpo_integration.md`](./imads_hpo_integration.md) — 동일 stack 구조의 선례. [`notebook_web_ui.md`](./notebook_web_ui.md) — Python binding 의 1차 소비자. [`remote_accelerator_access.md`](./remote_accelerator_access.md) — 가속기 daemon RPC 의 client lib 가 본 SDK 의 한 layer.

## 결정

WaveTensor SDK 는 **Rust native core + 다중 언어 FFI bindings** 로 구성. `imads` 저장소와 동일한 distribution 모델.

| Layer | 기술 / 표준 |
|-------|------------|
| Core | Rust (stable, 2024 edition 이상) |
| C/C++ binding | `cbindgen` 으로 생성된 C ABI 헤더 + Rust `extern "C"` |
| Python binding | `PyO3` + `maturin` (wheel 빌드) |
| WASM binding | **WASI Component Model** (`wit-bindgen` + `cargo component`) — Component Model 기반, 단순 wasm-bindgen 이 아님 |
| JVM binding | **Foreign Function & Memory (FFM) API** — JDK 22+ 만 지원 (Project Panama 의 stable API, JNI 대체) |

## 각 binding 결정 근거

### Rust core
- 메모리 안전성 + 성능
- imads 와 동일 ABI 라 두 라이브러리를 같은 process 에서 native 로 호출 시 boilerplate 적음
- async runtime (tokio) 으로 가속기 daemon RPC client 도 같은 crate 에 통합 가능

### C/C++
- 모든 언어가 결국 C ABI 로 떨어짐 — bindgen / 자체 wrapper 의 베이스 layer
- C++ 직접 사용자 (FPGA 시뮬레이션 / verilator harness) 에도 유용

### Python (PyO3 + maturin)
- imads-hpo / PyTorch 사용자 가 가장 큰 audience
- maturin 으로 PyPI wheel 빌드 — `pip install wavetensor` 한 줄
- GIL 해제 가능한 작업 (가속기 RPC) 은 `py.allow_threads()` 안에서

### WASM (WASI Component Model)
- 단순 wasm-bindgen (브라우저 only, ad-hoc ABI) 이 아닌 **Component Model 기반**
- WIT (WebAssembly Interface Types) 로 인터페이스 정의 → `wit-bindgen` 이 host/guest 양쪽 코드 자동 생성
- WASI 0.2 Preview 안정화 이후 표준 ABI
- 활용 시나리오:
  - 브라우저 내 가속기 시뮬레이터 (cocotb 결과를 WASM 으로 packaging)
  - Edge / serverless 에서 가속기 RPC client
  - 노트북 UI (`notebook_web_ui.md`) 의 client-side preview
- `cargo component` 도구체인 표준화 (2024+)

### JVM (FFM, JDK 22+)
- **FFM = Foreign Function & Memory API** — Project Panama 의 stable 결과물
- JDK 22 (2024-03 GA) 부터 정식 (JEP 454 에 따름)
- JNI 대비:
  - Boilerplate 없음 (C 헤더에서 자동 stub 생성: `jextract`)
  - `MemorySegment` 로 native 메모리 직접 다룸 — JNI `GetByteArrayRegion` 같은 복사 불필요
  - 안전한 lifetime (`Arena`)
  - GC 와 native 메모리 간 명시적 경계
- Kotlin/Scala/Clojure 사용자 모두 같은 jar 에서 활용 (imads 와 동일)
- 단점: **JDK 22 미만 환경 사용자 배제** — 현실적으로 2026 시점엔 OK

## 저장소 구조 제안

```
wavetensor-sdk/
├── crates/
│   ├── wavetensor-core/         ← 알고리즘·타입 (no_std 가능 부분 분리)
│   ├── wavetensor-asm/          ← 어셈블러 (현재 asm/wavetensor_asm.py 의 Rust port)
│   ├── wavetensor-rpc/          ← 가속기 daemon client (tokio)
│   └── wavetensor-c-api/        ← cbindgen target (C ABI 노출)
├── bindings/
│   ├── python/                  ← PyO3 + maturin
│   ├── wasm/                    ← cargo component, wit/ 디렉토리
│   └── jvm/                     ← jextract output + Java FFM helper
├── wit/                         ← WIT 인터페이스 정의 (Component Model)
├── examples/
└── README.md
```

## 어셈블러 이주

현재 어셈블러는 `asm/wavetensor_asm.py` (Python). Rust core 로 가는 길:

1. **단기** — Python 어셈블러 유지. Rust SDK 는 가속기 RPC client 부터 시작 (어셈블러 없이도 가속기에 발사 가능)
2. **중기** — Rust 로 어셈블러 port (`crates/wavetensor-asm/`). Python binding 통해 기존 사용자 호환 유지
3. **장기** — Python 어셈블러 deprecated, Rust 가 single source of truth

이주 단계에서 두 어셈블러가 동일 비트 출력을 내는지 회귀 테스트로 보장 (현재 cocotb 의 `encode_instr()` 와 비트 동등성 검증한 것과 동일 패턴).

## 우리 가속기 측 의의

- **HIU 의 호스트 인터페이스가 PCIe/USB/CXL 등 무엇이든** Rust core 가 transport 추상화 (`Transport` trait) 로 처리 → SDK 사용자는 매체 무관
- **`remote_accelerator_access.md`** 의 daemon RPC client 가 SDK 의 한 module → 사용자가 같은 crate 에서 local + remote 가속기 모두 다룸
- **imads/imads-hpo 통합** 이 자연스러움 — 동일 stack
- **노트북 UI 의 magic** (`%%wt`) 은 Python binding 만 호출 → 위 lower 레이어 무관

## 단점 / 위험 요소

- **빌드 인프라 복잡** — 5개 binding 을 동시에 CI/CD 하려면 matrix builds 큰 규모. `maturin`, `cargo component`, `jextract` 각각 환경 차이 처리 필요
- **JDK 22+ 강제** — 일부 기업 환경 (LTS=21 등) 에서 사용 불가. JNI fallback 을 제공할지 결정 필요
- **WIT/Component Model 의 신생성** — 2024 안정화이지만 ecosystem 성숙도는 PyO3 보다 낮음. 첫 번째로 채택하는 사용자가 trailblazer 부담
- **Python binding 의 release GIL 처리** — async RPC 호출 동안 GIL 풀어야 의미 있는 동시성. 실수 시 deadlock 가능성
- **다중 binding 의 documentation 일관성** — 같은 함수가 5개 언어로 나타나면 docs 도 5종 — 단일 출처 + 자동 변환 필요 (예: rustdoc → mdBook → 각 언어 stub)

## 진입 트리거

- (a) imads-hpo 통합 작업 진입 시 동시 시작 — 그때 Python binding 이 1차 필요
- (b) 가속기 daemon (`remote_accelerator_access.md` Phase 0) 작성 시 client 측을 Rust 로 짜면 SDK 의 첫 module 이 됨
- (c) 외부 사용자가 처음 발생하는 시점 — 그때 binding 다양성이 광고 효과

가장 자연스러운 시점은 **(b)** — daemon RPC 가 first deliverable 이며, 그 client 가 Rust SDK 의 entry point.
