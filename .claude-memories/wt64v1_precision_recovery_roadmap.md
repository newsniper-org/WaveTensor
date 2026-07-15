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
- **v1.7**: `SIMD_MUL_WIDE_Q4_4_SCALAR_128_WIDEN` + `SIMD_REQUANTIZE_
  Q4_4_TO_INT4` (반드시 함께 landing). Output int8/Q4.4 4-fragment 방출. FSM
  1-bit → 2-bit 확장 필요. Output rounding exact zero in-range.
  **opcode 재조정 필요**: 원래 0x6A/0x6B 예약이었으나, v1.6.5d (FRAG_INVAL)
  가 같은 세션에서 0x69 충돌을 피해 0x6A 이후로 배정받음 — v1.7 착수 전
  실제 landed opcode 를 spec §22.15/22.16 에서 재확인할 것.

**Why:** 곱셈 정밀도가 아니라 rsqrt LUT (≤6.25% rel) 이 실제 bottleneck.
Q8.8 로 B-side quant 을 LUT floor 훨씬 아래로 밀어내는 것이 v1.6.7 스코프.
Output rounding 은 v1.7 로 별도 제거.

**How to apply:** v1.6.7 는 landed. v1.7 착수 시 opcode 번호를 spec 에서
재확인 후 위 로드맵 그대로 실행.

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
