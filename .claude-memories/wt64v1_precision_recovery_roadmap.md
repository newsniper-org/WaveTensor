---
name: wt64v1-precision-recovery-roadmap
description: RMSNORM/LAYERNORM scale-mul 정밀도 회복 roadmap 및 LUT floor 사실
metadata: 
  node_type: memory
  type: project
  originSessionId: 09e02def-fe68-4449-8866-9db15ac81932
  modified: 2026-08-17T05:29:37.823Z
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
- **f64 → 별도 optional extension "Lf" 로 이관** (2026-07-16 사용자 결정,
  완전 컷 아님): base 는 dtype nibble 0x5 를 decode_error 로 예약, Lf 가
  나중에 claim. Lf 본격 설계는 Stage-2 이상에서.
- **v1.8 착수 결정됨 (2026-07-16)**: staging 은 v1.8.0a(YAML codegen +
  decode skeleton) → 0b(int32 누산) → 0c(FP-UNIT, synth gate 후) →
  0d(CVT/DEQUANT/norm 재구축). spec §23.9 참조.
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

## v1.8 hard gate 실측 (2026-07-16 — 이후 모든 HW 논의의 기준)

- **Cluster Fmax = 10.85 MHz** (nextpnr-ecp5 OOC, LFE5U-85F speed 6) —
  100 MHz 가정 대비 9.2× 미달. Critical path 470 LUT 레벨 (단일 사이클
  dispatch 조합논리 구조의 귀결). dispatch 파이프라이닝이 v1.8.0c 의
  필수 아키텍처 항목.
- **pod 2x2_2x2 는 LFE5U-85F 에 배치 불가**: MULT18X18D 497 vs 156
  (3.2×) + TRELLIS_COMB 101%. Cluster 단독은 수용 (COMB 25%, MULT 82%).
- synth gate 가 적발한 잠복 버그: v1.6.1b 함수호출 인덱싱(yosys 불법),
  v1.7 frag_pending 범위 밖 인덱스, 스크립트 AUTONAME/whitebox 처리.
- 문헌 추정치를 절대 신뢰하지 말 것 — 이 프로젝트에서 3연속 실측 반박됨.
- **v1.8.0c Gate 4 사건 (2026-07-17)**: v1.8.0b 의 "MU MAC-tree
  per-operator synth gate = merge blocker" 가 실행되지 않은 채 commit 됨
  → 5 commit 뒤 Gate 4 에서 Fmax 10.85→5.88 MHz 반토막으로 발각. 원인:
  선형 누산 루프 (acc = acc + lane[i]) 가 32개 직렬 carry-chain ripple
  (~1,000 logic stages) 로 합성. 수정: 6개 reduction 함수 전부 최소 폭
  balanced tree 로 재작성 (참값 범위가 stage 폭에 수용 → 재결합 불변,
  bit-exact — regression 전체 green 으로 입증). **교훈 2건: (1) RTL 의
  reduction 루프는 반드시 tree 로 쓸 것, (2) merge blocker 로 선언한
  gate 는 task 로 만들어 commit 전 완료 확인할 것.**

## v1.8.0c/0d 완결 상태 (2026-07-24)

- **v1.8.0c landed**: MU-hosted fp32 step sequencer (FSCALAR 5 sub-op /
  FRSQRT32 0.617ulp / FEXP2_32 0.569ulp), Gate 1-4 전부 실측 통과
  (amended: Gate3 LUT 3500, Gate4 COMB 38%). 용어: "스텝 시퀀서"
  ([[fp32-step-sequencer-terminology]]).
- **v1.8.0d landed**: 0x77 CVT 6종 (f16/bf16 widen/narrow, 2-pass I2F,
  F2I NaN→0), 0x73 ACC_ELEMWISE OPREF 전용, 0x7C fp-dest
  (fp_narrow_f32.vh 단일 함수 공유 = bit-identity 구조 성립),
  **norm 매크로 하이브리드 재구축 — rsqrt LUT ≤6.25% floor 가 실전
  RMSNORM/LAYERNORM 흐름에서 제거됨** (이 roadmap 의 종착).
  C6: COMB 39.48%/41%, Fmax 10.23-10.36 (0d 로직 경로 부재 증명).
- **cleanup + 0e + v1.9 전부 landed (2026-07-24~27)**: dead opcode 4종
  제거(Fmax 10.93 신기록), 0e1/0e2(MSE ratio 1.000, frag 16 확폭),
  v1.9 case_result_s2 — 단 v1.9 는 자기 Fmax gate FAIL (11.34 vs floor
  14.2, spec §26.6 정직 기록).
- **cross-vendor 실측 (2026-08-13, 결정적)**: 동일 RTL 이 ECP5 11.34
  MHz vs xcu55c(=EC2 F2 실리콘) ~98 MHz — **8.7배, v1.9 FAIL 은 설계가
  아니라 fabric**. ECP5 는 "FOSS 검증 vehicle, 성능 타겟 아님" 으로
  재포지셔닝. **xcu55c/xcu50 은 무료 Vivado 2025.2 로 합성 가능**
  (xcvu47p 만 차단 — device 문자열 라이선싱). ⚠️ **Vivado 2025.2 가
  마지막 라이선스-프리 — 절대 업그레이드 금지**. Avant G70 폐기(52주
  리드, $6,476), F2 는 비긴급(AWS 가 조합 루프 금지 → TRNG 불가),
  ULX3S 는 TRNG 실측 유일 경로로 유지.
  .claude-memos/cross_vendor_fabric_evidence.md 참조.
- **Stage 4 / v2.0 준비 landed (2026-08-15)**: ACC bank TLA+ (일가
  최초 형식 산출물, proofs/tla/ — guard 별 삭제 실험이 run.sh 에
  상설화된 실측형 모델), bf16 FMA lane 양대 fabric gate PASS (ECP5
  42.53 MHz / xcu55c **255.30 MHz**, lane 당 MULT/DSP 1개 — spec risk
  1 반증·risk 2 입증), v2_0_train_kickoff.md.
- **v2.0 COMMIT 0 확정 (2026-08-15, ca98604, spec §27)**: §23.1 vs
  §23.4 rounding 충돌은 사용자 결정으로 해소 — **옵션 3 채택:
  "wave-step-atomic accumulation"** (exact 528-bit lattice in-dot +
  wide 64b fp64-encoded bank, wave-step 당 RTO-48 1회 + drain RNE
  1회). 성공 시 옵션 3a (FDOT32_CR audit opcode, **0x7A 예약**) 즉시
  이행 약속. 핵심 사실: RTO-tree 는 전 폭(48-368)에서 사망 (반례
  가족), "FP_AddWide 50-bit 필요설"은 범주 오류로 영구 폐기 (Gate 2
  재개봉 없음 — 추출 정리 RNE₂₄(RTO₄₈(exact))==RNE₂₄(exact), q≥26
  이면 충분), bf-사다리·posit 전부 실측 기각 (posit 표준의 quire 가
  Kulisch 필요성의 자백), 입력노이즈 지배 (paired 전승 — 정확도
  아닌 계약강도·처리량·검증표면이 채택 근거). FP_LANES serial-
  equivalence 증명 의무가 exact 구조로 소멸. 재현: scripts/
  acc_format_study.py (고정 seed). PACK_WIDE 형식 폐쇄 (c21092a):
  canonical zero (0,-1024,0), I/O 폐쇄성, 전 gate 재측정 PASS.
- **GATE V20-2 실측 완료 (2026-08-15, 903351c+42130e2)**: golden
  (적대 2렌즈 무반증, 4001 벡터+fuzz 30k) + FP_AccLattice.v (4001/4001
  bit-exact, 변이 3종 적발) 착지. **xcu55c binding FAIL — LUT 53,418 >
  ceiling 20,040** (기준 b/c 는 PASS: $mul 0, Fmax 122.06 MHz,
  resolve-1-cycle 졸업). 귀속: 94.5% 가 S1 (배치 33× demux 복제 +
  34×576 tree, dynamic 배치 범위 기인) — full-parallel II=1 의 구조적
  비용. beat-serial Beat2 xcu55c 실측 6,075 LUT / 136.95 MHz / II=28.
  ECP5: 전 병렬 배치 불가 = 예정된 off-ramp 발동 (측정, FAIL 아님 —
  사용자 지시); beat-serial 9,374 LUT4 / 19.55 MHz 완주.
- **옵션 (A) 채택·완결 (2026-08-16, 3d51b84/cddb4d1/0f97695)**: 사용자
  결정 — beat-serial N=8, ceiling 재anchor 없음. FP_AccLattice.v 재작성
  (PRODUCTS_PER_BEAT 파라미터, carry-in beat 0 병합, **II=4**, 병렬
  1-cycle resolve). **GATE V20-2 재실측 PASS**: xcu55c LUT 19,251 ≤
  20,040 (여유 789) / $mul 0 / Fmax 143.64 MHz — make fp-op-report
  exit 0 복귀. ECP5 N=8 MEASUREMENT: 37.7% 수납·16.51 MHz·완주. golden
  벡터 4081 로 확장 (sticky_window_band 80, 결정성 유지), divisor 전수
  회귀 N∈{2,4,8,16,32} bit-exact. **하류 ③ (bank RTL) 착수 가능** —
  입력 계약: carry-in beat 0 병합의 bank 함의 (read-before-dispatch,
  ownership window, slot 체이닝 ≥ LATENCY=7) + spec §27.6 pin 3건
  (−2^261 corner / carry normalized 명문화 / lattice-비표현 carry
  fault 클래스). TB 커버리지 경계: back-to-back 전용 (gap-후 재시작은
  ③ directed test 에서 폐쇄).
- **하류 ③ 완결 (2026-08-16, f56b907/ab51a91/d419458)**: pin 3건
  spec 해소 + IF-1..IF-4 bank 계약 확정. FP_AccBank.v (2x32x64b) +
  FP_AccLattice pin 2 강화형 (V20-2 재확인 PASS 19,298, delta +47) +
  TLA+ 유도 directed 14건 (TLC byte-identical 실증) + golden 343
  시나리오 + 통합 TB 전량 bit-exact (gap 1/3/17 폐쇄, 변이 7종 사멸
  — SPILL/UNK 블라인드 스팟은 검증 렌즈 실측 발견 후 golden-first
  폐쇄). bank smoke: xcu55c 8,368 LUT / ECP5 14,671 LUT4 (양쪽 $mul
  0). 커버리지 경계 3건 spec 정직 기록 (offset 0 / 교차곱 공백 /
  TLC ghost 2건 — 전부 ④ 몫).
- **④ GATE V20-3 완결 (2026-08-17, 69c30f4/d2c1948/7f05ef3/21ad6de)**:
  기준 선공표 (LUT ceiling 35,377 = anchor 33,874 + glue 900×1.67)
  → FP_TrainCluster.v (lane 전단 tap ×8 → lattice N=8 → bank;
  offset-0 중재 pin ARB_OFFSET0/ARB_PORT; NaN/Inf → canonical zero
  + LANE_SPECIAL + writeback 억제) → **xcu55c binding PASS: LUT
  26,863 (여유 8,514, tap 효과) / DSP·$mul 정확히 8 / DRC 0 / Fmax
  121.62 MHz**. ECP5 MEASUREMENT: **PnR 완주 — infeasible 사전 분기
  미발동** (COMB 54%, 18.23 MHz). e2e 1,234 wave + 변이 7종 사멸
  (fault_o 집약 공백은 발견→폐쇄→재적용 재현). ③ 이월 3건 폐쇄.
  **∴ §27.6 하류 ①→②→③→④ 전부 종결 — 옵션 3 gate 전건 PASS.
  다음 = 3a FDOT32_CR (0x7A) COMMIT 0 (사용자 기결정 2026-08-15
  "성공하면 곧바로 3a" — 별도 release, §27.7 op_sel 격리) + TRAIN
  opcode ISA 결선·step sequencer 통합 후속.**
- 장기 활용처: .claude-memos/future_applications.md (PLL-DSP,
  WT64v1CLf GPGPU — 트리거 조건 충족 전 착수 금지).

## Cross-repo 파급

v1.6.7 landing 시 5곳 동시 update: WaveTensor RTL/asm/spec, wavetensor-sdk 
emitter + capability flag, Y4 Isabelle 형식 검증, wavetensor-drivers Frama-C
bit-equivalence, Dasima notebook 예제. [[spinoff_pattern]] 참조.

## 참고

- Related: [[wavetensor_sdk_separate_repo]] (asm 은 SDK Phase B-C 까지 bit-
  equivalence reference)
- Related: [[wavetensor_drivers_separate_repo]] (Frama-C bit-equivalence)
- v1.6.5a landing spec: `.claude-memos/wt64v1_spec.md` §22.14a
