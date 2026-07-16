---
name: wt64v1-precision-recovery-roadmap
description: RMSNORM/LAYERNORM scale-mul 정밀도 회복 roadmap 및 LUT floor 사실
metadata: 
  node_type: memory
  type: project
  originSessionId: 09e02def-fe68-4449-8866-9db15ac81932
---

# WT64v1 RMSNORM/LAYERNORM scale multiplication 정밀도 roadmap

Workflow `whro79brj` (2026-07-15, 24 agents, 1.06M tokens) 로 5개 설계안
adversarial verification 완료.

## 결정된 로드맵

- **v1.6.7 (landed 2026-07-16)**: `0x69 SIMD_MUL_WIDE_Q8_8_SCALAR` — B lane
  을 Q4.4 → Q8.8 로 widening. IMM16 EH 이미 dec_eff_b_value[15:0] 로 배선됨
  (16-bit 폭이 정확히 일치). FSM 무변경, output 여전히 int4 2-fragment.
  RMSNORM/LAYERNORM scale 곱셈이 0x67 → 0x69 로 전환됨. spec §22.14e 참조.
- **v1.7 (landed 2026-07-16)**: `SIMD_MUL_WIDE_Q4_4_SCALAR_128_WIDEN` (0x6B)
  + `SIMD_REQUANTIZE_Q4_4_TO_INT4` (0x6C). Output int8/Q4.4 4-fragment
  방출. PE_Core.v 공유 fragment-drain FSM 을 1-bit(frag_state)→2-bit
  (frag_idx up-counter)로 확장 — 세션 최고 위험도 RTL 변경(9개+ opcode 가
  공유하는 FSM)이었으나 전 계층(PE→ISA_Decoder→Top_Core→Pod→Cluster 양쪽
  build) 무손상 확인. opcode 재조정: v1.6.5d(FRAG_INVAL) 가 0x6A 선점,
  WIDEN/REQUANTIZE 는 0x6B/0x6C 로 확정. spec §22.18 참조.

  ⚠️ **정밀도 주장 정정 (이 메모리의 이전 버전이 틀렸음)**: "Output rounding
  exact zero in-range" 는 **부정확**. 실제로는:
  - WIDEN 자신의 Q4.4-int8 출력은 정확히 rounding-free (A 가 정수라 raw
    product 가 이미 Q4.4 grid 위에 있음, saturating cast 만 필요)
  - 하지만 REQUANTIZE (기존 int4-only 소비자 호환에 필수) 가 round-half-up
    + saturate 를 다시 수행 — 최종 int4 출력은 여전히 기존 0x67/0x69 과
    동일한 ~0.5 output-LSB rounding bound
  - 올바른 결론: v1.7 은 기존 int4 소비자 대비 **parity 복원**일 뿐, output
    rounding 병목을 완전히 제거하지 않음. 진짜 zero-rounding 은 네이티브
    Q4.4-int8 을 받는 다운스트림 소비자가 있어야 실현되는데 **아직 ISA 에
    그런 소비자가 없음**.

**Why:** 곱셈 정밀도가 아니라 rsqrt LUT (≤6.25% rel) 이 실제 bottleneck.
Q8.8 로 B-side quant 을 LUT floor 훨씬 아래로 밀어내는 것이 v1.6.7 스코프.
v1.7 은 (parity 수준으로) output-side 를 추가 개선하나 완전 제거는 아님.

**How to apply:** v1.6.7, v1.7 모두 landed. 후속은 FP-native 설계 조사
(spec §23) 가 대체 — v1.8 "WIDE-ACC" 가 rsqrt/norm 체인을 fp32 로 재구축
하므로 "LUT densification / 네이티브 Q4.4-int8 소비자" 계획은 §23 roadmap
에 흡수됨.

## FP-native compute path 설계 조사 (2026-07-16, spec §23 — 미결정)

학습 가속이 주요 제품 목표임이 명시되어 수행한 조사. 핵심 결론:
- **v1.8 "WIDE-ACC"**: opcode block 0x70-0x7F, per-Cluster FP-UNIT (3번째
  stripped-PE peer), int32 누산 VDOT/VFMA, fp32 scalar pipeline +
  FRSQRT32(NR 3회)/FEXP2_32, STORE_QUANT/DEQUANT, norm 매크로 fp32 재구축
  → 추론 GPU-parity. 학습 불가 명시.
- **v2.0 "TRAIN"**: 최초 학습 가능 — 통합 f16/bf16 fused-FMA(fp32 누산),
  fp32 ACC bank + canonical accumulation order(bit-reproducible), fp32
  master weights, counter-based stochastic rounding (non-default).
- **v2.1 "SCALE"**: Avant G70 에서 FP_LANES=8+, FP8, 16-fragment FSM.
- **f64 CUT** (encoding 예약만): DL 학습 가속기 중 탑재 사례 0.
- precision_mode(tag[15:8]) 는 현재 순수 메타데이터 (PE_Core 29곳 전부
  output_tag 조립) — 0x70 block 안에서만 dtype selector 로 승격.
- 차별점은 속도가 아니라 **bit-reproducibility** (run/lane/part 간 비트
  동일 — GPU 는 못 줌). Stage-1 ECP5 는 GPU 대비 수 자릿수 느림, 속도
  주장은 Stage-2 Avant G70 부터.
- 착수 전 hard gate: per-operator synth (FloPoCo+yosys/nextpnr), base pod
  Fmax, legality-ROM YAML codegen, ACC bank TLA+ (v2.0 전).

## Rejected 대안 (다시 제안 금지)

- **Q16.16 scalar**: ISA 최초 IMM-width-specific opcode 가 됨. IMM64 32-bit
  낭비, output rounding 이 여전히 dominant → 무의미
- **Fused-MAC**: 첫 ternary op, 새 OPREF_C EH 필요, gamma int4 clip 이 오히려
  ~4 LSB 손실 introducing
- **Multi-pass Q4.4 (HI/LO)**: 27% 개선에 그침, 새 opcode + FSM 필요, p1
  saturation 근방 regression 존재

## 근본적 한계 (v1.7 로도 안 없어지는 것)

- **rsqrt LUT ≤6.25% relative floor** — ISA 로 못 없앰. v1.8 후보:
  (a) LUT bin resolution 2-3 bit 확장 (≤1.5% rel), (b) Newton-Raphson refinement
  opcode
- **|A×r|>7.5 saturation wrap** — variance→0 degenerate case. SDK range check
  로 처리 (HW-side telemetry 없음)

## Cross-repo 파급

v1.6.7 landing 시 5곳 동시 update: WaveTensor RTL/asm/spec, wavetensor-sdk 
emitter + capability flag, Y4 Isabelle 형식 검증, wavetensor-drivers Frama-C
bit-equivalence, Dasima notebook 예제. [[spinoff_pattern]] 참조.

## 참고

- Related: [[wavetensor_sdk_separate_repo]] (asm 은 SDK Phase B-C 까지 bit-
  equivalence reference)
- Related: [[wavetensor_drivers_separate_repo]] (Frama-C bit-equivalence)
- v1.6.5a landing spec: `.claude-memos/wt64v1_spec.md` §22.14a
