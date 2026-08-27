<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# WaveTensor 장기 활용처 모색 — 계획 메모

> ### ⏸ 지위 판정 연기 (2026-08-27)
>
> **이 계획의 지위는 아직 판정하지 않았다.** 판정의 전건은 `T_stable` 재정의이며
> 그것이 미결이다 (`post_stable_roadmap.md` §1 — 그 게이트의 전건 2가 가리키던
> "현행 순수 Verilog RTL 동결"이 §3 대체로 성립하지 않게 됐다).
> **미판정과 판정 연기는 다르다** — 이 배너가 후자의 기록이다.
>
> 이 문서의 트리거 조건은 전부 §23 roadmap (v1.8 → v2.0 → v2.1) 의 성숙에
> 걸려 있고, **그 §23 자신이 판정 연기 상태**다 (`wt64v1_spec.md` 배너).
> 전건이 연기됐으므로 후건도 연기된다 — 그것이 이 배너다.
>
> 아울러 이 문서는 **비정본**이다. 정본은 `docs/wt64v1-architecture-guide/`
> 이고, 어긋나는 지점은 정본 **부록 B** 가 정정본이다.

작성일: 2026-07-24
상태: **plan-only** (탐색 단계 — 설계·구현 미포함, roadmap 트리거 조건만 정의)

본 메모는 WT64v1 base + 확장군(C, Lf)의 성숙 이후를 겨냥한 **추가 활용처
후보**를 수집·평가하는 장기 계획서다. §23 roadmap (v1.8 WIDE-ACC → v2.0
TRAIN → v2.1 SCALE) 의 어느 것도 대체하지 않으며, 각 후보는 명시된
트리거 조건이 충족될 때 별도 design pass 로 승격한다.

## 1. 후보 A — 아날로그 회로와 결합한 PLL-DSP

### 1.1 개념

WaveTensor dataflow core 를 mixed-signal 루프의 **디지털 백엔드**로
사용한다. 대상 부류:

- **ADPLL(all-digital PLL) 루프 필터/제어**: TDC/DCO 와 결합해 루프
  필터·게인 스케줄링·스퍼 보상을 WT 코어가 수행. wave/tag 모델이
  스트리밍 샘플 처리와 자연 정합 (per-sample wave, tag = 채널/시각).
- **direct-RF sampling DSP**: 고속 ADC 뒤단의 DDC/필터뱅크/채널라이저.
  einsum/VDOT 경로가 FIR/상관기와 구조 동일.
- **센서 프런트엔드 융합**: 아날로그 AFE + WT 코어의 저지연 제어 루프
  (모터 제어, 전력 변환, 빔포밍).

### 1.2 WaveTensor 고유의 강점

1. **bit-reproducibility** (§23 차별점): 제어 루프·필터의 거동이 run 간
   비트 동일 — 인증 요구가 있는 제어 시스템(전력, 의료, 항공)에서 GPU
   대비 실질적 우위.
2. **deterministic latency**: dataflow dispatch 는 cache/warp 비결정성이
   없음 — 루프 지연 상한을 규범적으로 명시 가능 (v1.8.0c 의
   cycle-maxima 표 방법론을 그대로 적용).
3. fp32 step sequencer (v1.8.0c) + CVT/DEQUANT (v1.8.0d) 가 갖춰지면
   fixed-point AFE 데이터 ↔ fp 제어 연산의 왕복이 ISA 네이티브.

### 1.3 트리거 조건 (이전에는 착수 금지)

- [ ] v1.9 dispatch 파이프라이닝으로 Fmax ≥ 40 MHz 급 (현 10.51 MHz 는
      RF 급 샘플레이트에 부족; 제어 루프급은 현행으로도 가능)
- [ ] v1.8.0d CVT/DEQUANT 완결 (AFE 정수 ↔ fp 경로)
- [ ] 보드 계획 (board_hw_plan.md) 에 아날로그 동반 칩(TDC/DCO/ADC)
      선정 — chiplet 분리 원칙은 WT64v1-C crypto 다이 선례
      (wt64v1c_extension_plan.md §2.1) 를 따름: 아날로그 다이 분리로
      본체 timing/공정 자유도 확보
- [ ] 파일럿 워크로드 1종 선정 (권고: ADPLL 루프 필터 — 상태 수가 작고
      bit-exact golden 을 Python 으로 만들기 쉬움)

## 2. 후보 B — WT64v1CLf 기반 GPGPU

### 2.1 개념

`WT64v1CLf` = base **WT64v1** + **C 확장** (crypto/bit-permutation,
wt64v1c_extension_plan.md) + **Lf 확장** (f64, dtype nibble 0x5 예약 —
2026-07-16 사용자 결정) 의 풀 스택 조합을 **범용 가속기(GPGPU)** 로
포지셔닝한다.

- Lf 가 f64 를 제공하면 과학계산(선형대수, ODE/PDE, 통계) 이 사정권.
- C 가 AES/SHA-3/PEXT/PDEP 를 제공하면 데이터 파이프라인의 암호화
  구간(전송·저장 암호화, 무결성)을 가속기 안에서 완결 — trust boundary
  분리(§2.1 표의 2번 사유)가 confidential computing 셀링 포인트.
- 시장 논리는 속도 경쟁이 아니라 **재현 가능한 수치 + 격리된 신뢰
  경계**: HPC 재현성 위기(연구 재현), 금융 리스크 계산(감사 가능성),
  regulated industry 의 결정론 요구.

### 2.2 전제되는 기술 부채

| 항목 | 현황 | 필요 수준 |
|---|---|---|
| f64 (Lf) | dtype 0x5 decode_error 예약만 | Lf 본격 설계 (Stage-2 이상, 기존 결정) |
| 처리량 | 10.51 MHz, MU 직렬 fp | v1.9 파이프라이닝 + v2.1 FP_LANES=8+ |
| 메모리 모델 | wave 단편 + OPREF bank | GPGPU 급 gather/scatter 는 미설계 — 최대 격차 |
| 프로그래밍 모델 | asm + SDK 초기 | 커널 컴파일러 (SDK Phase C 이후) |
| C 확장 | plan-only 메모 | chiplet 설계 착수 조건: base v1 lock |

### 2.3 트리거 조건

- [ ] v2.0 TRAIN landing (fp32 ACC bank + canonical order — GPGPU 의
      최소 수치 기반)
- [ ] Lf 설계 착수 (Stage-2 Avant G70 이후, 기존 roadmap 결정 유지)
- [ ] 메모리 모델 격차 해소를 위한 별도 design pass (gather/scatter,
      wave 크기 초과 텐서의 타일링 규약) — **이 메모가 승격하는 첫
      작업물이 될 가능성이 가장 높은 항목**
- [ ] SDK 커널 컴파일러 경로 확정 (wavetensor-sdk repo)

## 3. 후보 수집 백로그 (평가 전)

- 이벤트 기반 신호처리 (뉴로모픽 인접 — wave 모델의 sparse 활성 자연
  정합 여부 미평가)
- FPGA-in-the-loop 실시간 시뮬레이터 (HIL) 백엔드
- 결정론적 물리 시뮬레이션 (게임/로보틱스 lockstep — bit-reproducibility
  직결)

## 4. 평가 축 (모든 후보 공통)

1. bit-reproducibility 가 실질 구매 사유인가 (아니면 nice-to-have 인가)
2. 현 Fmax/처리량 현실 (10.51 MHz, §23.10.7 Gate 4) 에서 파일럿이
   성립하는가, v1.9/v2.1 을 기다려야 하는가
3. 기존 확장(C/Lf) 재사용율 — 새 ISA 표면을 만들지 않는 후보 우선
4. golden model 을 순수 Python 으로 만들 수 있는가 (프로젝트 검증
   방법론의 전제)

## 5. 관련 메모

- wt64v1_spec.md §23 (FP roadmap, hard-gate 실측)
- wt64v1c_extension_plan.md (C 확장 — chiplet 분리 원칙의 원전)
- board_hw_plan.md (Stage-1/2 보드)
- sdk_architecture.md → wavetensor-sdk repo (커널 컴파일러 전제)
