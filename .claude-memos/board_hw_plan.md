<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# WaveTensor 실물 검증 하드웨어 계획 — 2-stage FPGA 이주 (Vivado → ECP5 → Avant)

작성일: 2026-07-12
상태: **Stage 1 board 발주 승인 (2026-07-12) — 소프트웨어 정비 완료, 물리 발주 대기**

> **연관 메모**: [`wt64v1_spec.md`](./wt64v1_spec.md) — 참조 구현 사양 (2026-05-03 로크). 본 계획 진행 시 그 값들을 새 벤더 실측값으로 갱신 예정.
> [`sdk_architecture.md`](./sdk_architecture.md) — Stage 1 의 `UsbCdcTransport` / Stage 2 의 `PcieTransport` 가 SDK `Transport` trait 의 첫 실제 구현체.

## 1. 배경 — AMD/Xilinx 이탈 결정

2026-07 발표 기준 AMD (구 Xilinx) 의 **Vivado 무료 버전 Linux 지원이 2025.2.x 를 마지막으로 만료** 예정. 공식 포럼에서 논쟁 활발. 우리 프로젝트는 개인/오픈 실리콘 프로젝트라 vendor 정책 리스크 회피가 시급 → **벤더 이주 결정**.

기존 참조 구현 사양 (`wt64v1_spec.md`):
- Board: ALINX AXAU25 (XCAU25P, -2 speed grade)
- 결과: WNS +2.058 ns, LUT 61.9K/141K (44%), DSP 140, Power 0.62W @ 100 MHz
- 상태: 회귀 167/167 PASS, timing closure, 실측 검증만 남음

**중요**: 보드 발주 전. Pivot 비용 최소.

## 2. 이주 전략 — 2-stage 순차 검증

FPGA 대체 후보를 다각 검토 후 (multi-FPGA 커스텀 보드, SoM+캐리어, 전문 위탁 등 포함), **위험 순차 분리** 원칙에 따라 다음 2-stage 계획 채택:

### Stage 1 — 최소 검증 (완전 FOSS)

| 항목 | 값 |
|---|---|
| Board | **CS-ULX3S-03** (LFE5U-85F, ECP5 family) |
| 부품 | Lattice ECP5 LFE5U-85F-6BG381C (CABGA381, 84K LUT, 156 EBR, no SerDes, no DSP48) |
| 가격 | ~$115 |
| Geometry | 기본 (2,2)×(2,2) = 16 PE (현 참조 구현과 동일 파라미터) |
| 예상 리소스 | LUT 60-70K / 84K (72-83%) — ECP5 는 DSP48 없어 MATMUL 이 LUT 로 흡수됨 |
| 툴체인 | **yosys + nextpnr-ecp5 + prjtrellis (100% FOSS)** |
| Host 인터페이스 | USB CDC UART (ULX3S 온보드 FT231X) |
| 예상 시간 | 4-6주 (board 도착 1-2주 + 이식 1주 + host + bring-up 2-3주) |

**목적**:
- 아키텍처 자체 검증 (cocotb 시뮬 → 실제 FPGA 등가성)
- 완전 FOSS 파이프라인 확립 → 향후 벤더 정책 리스크 무관
- SDK 첫 실제 backend (`UsbCdcTransport`) 확보
- ECP5 상의 timing / power 실측 데이터 획득

**리스크 (낮음)**:
- ECP5 는 DSP48 없음 → MATMUL_UNIT LUT 소비 증가 (예상 700-1000 LUT 추가 per matmul). 84K fabric 안에서 fit 확인 필요.
- TRNG ring oscillator (`(* keep *)` 필요) 가 yosys 파이프라인에서 살아남는지 확인 필요.
- Xilinx-style `(* keep = "true" *)` 등 vendor attribute → **`include/attributes.vh` 벤더-agnostic 매크로 도입 완료 (2026-07-12)**.

### Stage 2 — Flagship 검증 (투자 유치 후)

| 항목 | 값 |
|---|---|
| Board | **Avant G70 PCIe card** (특정 모델 미정 — 조사 진행 예정) |
| 부품 | Lattice Avant G70 (~700K LUT class, 16nm FinFET, hard PCIe Gen4 IP, high-speed SerDes) |
| 가격 | ~$2000-5000 (dev card 예상) |
| Geometry | **최대 (4,4)×(4,4) = 256 PE** — flagship ILC target 매치 |
| 예상 리소스 | LUT ~720K / ~700K (마진 좁음, geometry 축소 fallback 준비) |
| 툴체인 | **Lattice Radiant (paid subscription 필요 — Free 미커버 확정)** |
| Host 인터페이스 | **PCIe Gen3/Gen4 x8** (SDK `PcieTransport` 실현) |
| 예상 시간 | Stage 1 완료 후 3-4개월 |

**목적**:
- **flagship ILC ASIC 등가 스케일 실측** — (4,4)×(4,4) 최대 geometry 로 카메라 target 완결 검증 (별도 메모 `deployment_scaling_ilc.md` 참조)
- **PCIe 통합** — `wavetensor-daemon` 첫 실제 하드웨어 backend, SDK Phase D 트리거
- Geometry 파라미터 스윕: 같은 board 에서 (2,2)×(2,2) 부터 (4,4)×(4,4) 까지 각 조합 합성 → 카메라 tier (Entry / Enthusiast / Flagship) 별 실측 매트릭스 획득
- ASIC 트랙 진입 전 최종 아키텍처 확정

**리스크 (중간)**:
- **Radiant Free G/X 계열 미커버 확정 (사용자 확인 완료 2026-07-12)** → Radiant Subscription 필요. 우리가 AMD 를 떠난 이유 (툴 라이선스) 와 정합성 일부 붕괴하지만, **투자 유치 후 진행 예정**이라 라이선스 비용 감내 가능.
- 720K LUT 는 G70 정격 (~700K) 상 마진 좁음. Timing closure 실패 시 (4,4)×(2,4) = 128 PE 로 축소 fallback.
- Avant G70 PCIe card 상용 존재 여부 미확인 (2026-07 현재). Lattice 공식 evaluation kit + PCIe carrier 조합 또는 서드파티 (Alpha Data, HiTechGlobal 등) 조사 필요.
- Radiant 컴파일 시간: 720K design 은 몇 시간/합성. 개발 iteration 느려짐.

## 3. RTL 이식성 조사 결과 (2026-07-12 실측)

```
grep -REn Vivado 특화 primitive → 0건 (DSP48E1/RAMB18E1/MMCM/PLLE2/BUFG 등)
find *.xci → 0건 (IP 코어 없음)
find synth/constraints/*.xdc → 1개 (매우 단순: clock 1개 + false_path 1줄)
```

**Vendor 특화 attribute 사용**:
| 파일 | 라인 | attribute | 목적 |
|---|---|---|---|
| HIU.v | 356-378 | `(* keep = "true" *)` `(* dont_touch = "true" *)` | TRNG ring oscillator 보존 (필수 — optimizer 방지) |
| ALU_Extended.v | 115-116 | `(* use_dsp = "yes" *)` | Cfloat32 mul DSP 유도 |
| PE_Core.v | 109-398 | `(* use_dsp = "yes" *)` | MATMUL / SQ 등 DSP 유도 |

**결론**: **이식성 매우 좋음**. 위 attribute 만 벤더-agnostic 매크로로 처리하면 완결.

## 4. 인프라 정비 산출물 (2026-07-12 완료)

### 4.1 `include/attributes.vh` — 벤더-agnostic 매크로 헤더

```
`WT_KEEP        → Vivado: (* keep = "true" *)      Lattice/yosys: (* keep *)      Radiant: (* syn_keep = 1 *)
`WT_DONT_TOUCH  → Vivado: (* dont_touch = "true" *) Lattice/yosys: (* keep *)      Radiant: (* syn_noprune = 1 *)
`WT_USE_DSP     → Vivado: (* use_dsp = "yes" *)    Lattice/yosys: (no-op, auto)  Radiant: (* syn_multstyle = "dsp" *)
```

각 벤더 매크로는 command-line define 으로 활성화:
- Vivado: `+define+WT_VENDOR_VIVADO`
- yosys (ECP5): `-DWT_VENDOR_LATTICE_YOSYS` (synth_pod.ys 에서 자동 설정)
- Radiant: `-define WT_VENDOR_LATTICE_RADIANT`

미정의 시 매크로 확장 없음 (안전한 기본값 — 다만 TRNG 는 안전하지 않으므로 반드시 정의).

**TODO**: Stage 1 진입 시 HIU.v / ALU_Extended.v / PE_Core.v 의 hardcoded attribute 를 매크로 참조로 교체 (`\`WT_KEEP` 등). 파일 헤더에 `\`include "include/attributes.vh"` 추가.

### 4.2 `synth/lattice/` — Stage 1 flow 스캐폴드

```
synth/lattice/
├── scripts/
│   ├── synth_pod.ys       yosys 합성 스크립트 (JSON 산출)
│   └── pnr_pod.sh         nextpnr-ecp5 place+route + ecppack 드라이버
├── constraints/
│   └── pod_ulx3s.lpf      ULX3S 제약 파일 (스켈레톤, board 도착 시 pin 배치 추가)
└── reports/               (합성/PNR 산출물 저장 위치)
```

기존 `synth/scripts/` (Vivado), `synth/constraints/` (XDC), `synth/reports/` 는 **무변경 유지** — Vivado flow 무결점 보존 (Stage 2 재사용 위해). 향후 Stage 1 실행 시작 시 필요하면 `synth/vivado/` 로 대칭 이동 예정 (선택적).

### 4.3 Makefile — 새 타겟

```
make synth-pod           # 기존 Vivado (변경 없음)
make impl-pod            # 기존 Vivado (변경 없음)
make synth-pod-ecp5      # NEW: yosys 로 Pod 합성 → JSON
make impl-pod-ecp5       # NEW: nextpnr-ecp5 PNR + ecppack 비트스트림
make lattice-clean       # NEW: lattice/reports/* 정리
```

## 5. 다음 실행 단계

### 즉시 (Stage 1 board 발주 전 — 소프트웨어 정비, 2026-07-12 완료)

- [x] ULX3S CS-ULX3S-03 발주 **승인** (2026-07-12) → 물리 발주 및 배송 대기 (~1-2주)
- [x] `include/attributes.vh` 생성 (완료)
- [x] `synth/lattice/` 스캐폴드 생성 (완료)
- [x] Makefile targets 추가 (완료)
- [x] 본 메모 작성 (완료)
- [x] **Xilinx-style attribute → `\`WT_KEEP` / `\`WT_DONT_TOUCH` / `\`WT_USE_DSP` 매크로 이행 완료** (2026-07-12) — HIU.v 3 라인, ALU_Extended.v 2 라인, PE_Core.v 7 라인 모두 이행. `\`include "attributes.vh"` 추가. Vivado synth_pod.tcl 에 `-include_dirs` + `-verilog_define WT_VENDOR_VIVADO=1` 추가. Makefile COMPILE_ARGS 에 `-I$(CURDIR)/include` 추가.
- [x] **cocotb 회귀 91/91 PASS** (2026-07-12) — HIU 1, PE 4, ALU_Extended 16, ISA_Decoder 70 검증. Include 경로 + 매크로 확장 정상 동작 확인.
- [x] **`wt64v1_spec.md` 갱신 완료** (2026-07-12) — Stage 0/1/2 참조 구현 사양 표 추가 + 마이그레이션 노트 §1a 신설.
- [ ] 사전 검증 — yosys 로컬 설치 후 `make synth-pod-ecp5` 실행 (board 없이도 합성만 시도 가능, LUT/timing 예상값 획득)

### Board 도착 후 (Stage 1 실행)

- [ ] Xilinx-style attribute 를 `\`WT_KEEP` / `\`WT_USE_DSP` 매크로로 교체 (HIU.v, ALU_Extended.v, PE_Core.v 3 파일)
- [ ] `Pod_ulx3s_top.v` wrapper 작성 — clk/rst/UART/LED 외 pod 내부 신호 격리
- [ ] `pod_ulx3s.lpf` pin 배치 추가
- [ ] USB CDC 프로토콜 정의 + host 스크립트 (Python)
- [ ] cocotb 회귀 corpus 를 실제 board 에 발사 → 결과 회귀 확인
- [ ] LUT / timing / power 실측 → `wt64v1_spec.md` 참조 구현 사양 갱신
- [ ] Stage 1 완료 마일스톤 → SDK Phase B 진입 트리거 만족 (`wavetensor-sdk` 저장소)

### Stage 1 완료 후 (Stage 2 준비)

- [ ] 투자 유치 진행 상태 확인
- [ ] Avant G70 PCIe card 상용 조사 (Lattice eval kit + PCIe carrier, 서드파티 카드)
- [ ] Radiant Subscription 견적 요청
- [ ] Stage 1 결과 기반 (4,4)×(4,4) geometry 파라미터 스윕 예상 (Vivado 시뮬 + yosys 시뮬)
- [ ] `wavetensor-daemon` 저장소 스핀오프 (다음 spin-off 후보) — SDK 의 첫 실제 client, PcieTransport 소비자

## 6. 리스크 매트릭스

| 리스크 | 확률 | 영향 | 완화 |
|---|---|---|---|
| ULX3S 발주 후 소재/화물 지연 | 낮음 | 저 (그동안 소프트웨어 진행) | 소프트웨어 트랙 병렬 |
| ECP5 84K LUT 부족 (MATMUL 이 DSP 없이 LUT 로 흡수 시) | 낮음-중간 | 중 | `matmul_func` 를 2×2 로 이미 축소 (`.claude-memos/wt64v1_spec.md`). 넘칠 시 SIMD_ALU 대체 |
| TRNG oscillator 가 yosys 에서 프루닝됨 | 낮음 | 고 (엔트로피 상실) | `\`WT_KEEP` 매크로 정확한 lattice 문법 검증 필수. .json netlist 에서 `ro_out_w`, `ro_lfsr_q` 신호 존재 확인 |
| timing closure ECP5 @ 100 MHz 실패 | 낮음 | 중 | 80 MHz 로 완화 후 progressive tuning |
| Avant G70 PCIe card 상용 존재 안 함 | 중간 | 중 | Lattice eval kit + PCIe carrier 조합 대안 |
| Radiant Subscription 비용 산정 오차 | 중간 | 저 (투자 유치 후 진행) | 견적 사전 확보 |
| 720K LUT G70 마진 부족 | 중간 | 중 | (4,4)×(2,4) = 128 PE geometry fallback 준비 |

## 7. 결정 기록

| 항목 | 결정 | 날짜 |
|---|---|---|
| 벤더 이주 결정 (AMD → Lattice) | 결정 | 2026-07-12 |
| 2-stage 순차 검증 (min → max) | 결정 | 2026-07-12 |
| Stage 1 board = CS-ULX3S-03 | 결정 | 2026-07-12 |
| Stage 2 target = Avant G70 PCIe card | 결정 | 2026-07-12 |
| Stage 2 는 투자 유치 후 진행 | 결정 | 2026-07-12 |
| Radiant Free G/X 계열 미커버 사실 확인 | 확정 | 2026-07-12 |
| Stage 2 유료 Radiant Subscription 감수 | 결정 | 2026-07-12 |
| ILC (카메라) 를 primary target scenario | 결정 (진행 중) | 2026-07-12 |
| ILC target = (4,4)×(4,4) = 256 PE flagship 단일 Pod | 결정 | 2026-07-12 |
| Multi-Pod / Multi-die 는 카메라 target 에 불필요 | 결정 | 2026-07-12 |
| **Stage 1 board 발주 승인 (CS-ULX3S-03)** | **승인** | **2026-07-12** |
| Xilinx-style attribute → 벤더-agnostic 매크로 이행 | 완료 | 2026-07-12 |
| Cocotb 회귀 (91/91 PASS) 로 매크로 이행 검증 | 완료 | 2026-07-12 |

## 8. 미해결 / 후속 논의

- **Stage 1 wrapper 설계**: `Pod_ulx3s_top.v` 의 정확한 인터페이스. USB CDC 만? SDRAM DDR3 를 instruction buffer 로? micro-SD 를 weight storage 로? — Board 도착 시점에 결정.
- **어셈블러 실측 회귀 corpus**: 100+ 프로그램 중 어느 것들을 first bring-up 에 사용? — cocotb 회귀 corpus 재사용 이 자연스러움.
- **Stage 2 특정 dev card**: Avant G70 PCIe card 로 어떤 모델을 지목할지 미결. Lattice sales 문의 필요.
- **`imads-hpo` / camera 도메인 integration**: 이 계획이 성공하면 카메라 SDK 와 imads-hpo 를 결합하는 next-order 프로젝트. `.claude-memos/imads_hpo_integration.md` 스핀오프 시점에 재논의.

## 9. 진입 트리거

- Board 발주 승인 → Stage 1 진입.
- Stage 1 검증 완료 + 투자 유치 → Stage 2 진입.
- 또는 사용자께서 명시적으로 어느 stage 로 진입 지시.
