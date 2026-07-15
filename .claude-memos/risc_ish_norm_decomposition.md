<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# RISC-ish normalization decomposition — 심화 설계 memo

작성일: 2026-07-15
상태: **v1.6.1c amendment 로 landing** (2026-07-15). Companion to [`wt64v1_spec.md`](./wt64v1_spec.md) §22.

## 1. 발상의 계보

사용자 통찰 (2026-07-15, ultracode 세션):
> "어떤 정규화 기법이든 상관없이, 덩어리째로 가속시키는 것 대신에 유한한 가지수의 연산들로 분해하고 그 '유한한 가지수의 연산들'을 가속시키는 쪽으로 정규화 기법 가속 방안 모색 (마치, CISC의 중구난방함을 해결하기 위해 RISC가 제시되었듯이...)"

이는 architecturally 우아한 관점이며 WT64v1 의 정규화 관련 로드맵 전체를 재정의:

- **원래 계획 (§21.7)**: v1.6.1 = SIG_LAYERNORM_5D, SIG_SOFTMAX_HEAD, SIG_SUM_5D 3개 monolithic primitive
- **재정의 (§22)**: v1.6.1 = 19개 fine-grained primitives (Groups A+B+C) + spec-only decomposition doc

## 2. 왜 "RISC-**ish**" 인가

사용자와 후속 지시로 정확히 명명: **"RISC-ish normalization decomposition"** (진짜 RISC 아님).

### 2.1 True RISC 원칙 (Patterson & Hennessy 정의)

1. **Simple instruction format** — fixed size (예: 32-bit)
2. **Load-store architecture** — 메모리 접근은 LD/ST 만, 나머지는 register-register
3. **Single-cycle execution** (또는 fully pipelined)
4. **Small orthogonal instruction set** (~50-100 instructions)
5. **Register file with many registers**

### 2.2 WT64v1 v1.6.1 이 준수하는 부분

| 원칙 | 준수 | 비고 |
|---|---|---|
| Fixed instruction size | ❌ | Variable via EH chain (32-bit + up to MAX_EH×96-bit) |
| Load-store architecture | ❌ | Payload-oriented (dataflow), not register-based |
| Single-cycle execution | ⚠️ | Legacy ALU ops YES, wide-consumer FSM NO |
| **Fine-grained decomposition** | ✅ | monolithic norm 대신 primitives 조합 |
| **Compiler-level composition** | ✅ | SDK `_lower_norm_*` macro pass |
| Small orthogonal instruction set | ⚠️ | Opcode 공간 계속 확장 중이나 각 opcode 는 orthogonal |

### 2.3 정확한 명명이 중요한 이유

"RISC normalization decomposition" 이라 하면 진짜 RISC 원칙 준수를 함의 → 잘못된 기대. **"RISC-ish"** 는 borrowed philosophy (decomposition) 만 표시 → 정확하고 겸손한 표현.

## 3. Decomposition 의 경제학

### 3.1 Amortization 계산

**CISC 대안** (5 개별 norm opcode):
- SIG_LAYERNORM_5D:    ~3000 LUT
- SIG_BATCHNORM_5D:    ~2500 LUT
- SIG_RMSNORM_5D:      ~2200 LUT
- SIG_INSTANCENORM_5D: ~3200 LUT
- SIG_GROUPNORM_5D:    ~4000 LUT
- **총**: ~15000 LUT / Cluster (norm 하나 추가 시마다 +2-4K LUT)

**RISC-ish (v1.6.1)**:
- Group A (12 reductions):  ~2900 LUT (재사용: 여러 norm 이 공유)
- Group B (6 broadcasts):   ~1600 LUT (재사용: 모든 norm 이 공유)
- Group C (rsqrt):          ~100 LUT (재사용: 모든 sqrt 기반 norm 이 공유)
- **총**: ~4600 LUT / Cluster (norm 하나 추가 = **0 LUT** marginal)

**Amortization ratio**: 15000 / 4600 ≈ **3.3×** 즉시 (norm 5개 landing 시). 새 norm 추가할수록 ratio 개선 (10 norm → ~7×, 20 norm → ~13×).

### 3.2 새 norm 추가 비용

**CISC**: RTL 신설 (수천 LUT) + spec 변경 + verification 재수행. **Weeks of engineering per norm**.

**RISC-ish**: SDK 파이썬 코드 몇십 줄 (`_lower_normX(inst)`). Recipe 확인 후 primitive sequence 정의. **Hours per norm**.

### 3.3 정규화 기법 landscape (RISC-ish 로 커버 가능한지)

| Norm 기법 | RISC-ish 완전 커버? | Primitive 수 | Notes |
|---|---|---|---|
| BatchNorm (inference) | ✅ | 2 | K1, K2 SDK 사전 계산 |
| BatchNorm (training) | ✅ | 8 | LayerNorm recipe (다른 axis) |
| LayerNorm | ✅ | 8-9 | §22.3 recipe |
| RMSNorm | ✅ | 6-7 | §22.4 recipe, LLaMA-style |
| InstanceNorm | ⚠️ v1.6.2 | ~11 | 4D→3D reduction primitive 필요 |
| GroupNorm | ⚠️ v1.6.2 | ~13-14 | 3-axis reduction chain |
| Weight Standardization | ✅ | ~7 | SDK 는 offline 가능 (weights 는 정적) |
| PowerNorm | ✅ | ~9 | running stats 를 SDK 관리 |
| DivisiveNorm | ✅ | ~10 | 이웃 pooling + broadcast div |
| CosineNorm | ⚠️ | ~10+ | sqrt + division (SDK-level Newton-Raphson iteration 필요) |

Reflection: **거의 모든 정규화 기법이 몇 개 core primitive 조합으로 커버 가능**. WT64v1 v1.6.1 이 landing 한 primitive 는 대부분의 실전 정규화를 지원.

## 4. Precision analysis 상세

### 4.1 int4 quantization error 전파 모델

각 primitive 는 int4 wrap 을 유발:
- **ADD/SUB**: 2's complement wrap — 정보 손실 없음 (wrap 이 예상된 동작)
- **MUL (int4 × int4 → int4)**: 8-bit intermediate → 4-bit truncation. **1 LSB int4 ≈ 6.25% relative error**
- **Reduction (SUM, L2SQ)**: 여러 nibble 누적 → wider accumulator 로 저장. Truncation to int4 시 정보 손실.

### 4.2 LayerNorm error budget

9-primitive chain 에서 발생하는 quantization events:
- Step 2 SUB (SCALAR/VEC): no loss
- Step 3 L2SQ (5D→4D int4 truncate): **~1 LSB per position**
- Step 4 MUL SCALAR (1/N constant): **~1 LSB** (constant is exact for N=2)
- Step 5 ADD SCALAR eps: no loss
- Step 6 RSQRT (Q16.16 power-of-2 approx): **~3-4 bit precision** (baseline)
- Step 7 MUL SCALAR (xc × scale): **~1 LSB**
- Step 8 MUL VEC (nrm × γ): **~1 LSB**
- Step 9 ADD VEC (sc + β): no loss

**Cumulative worst case**: ~4-5 LSB int4 ≈ **25-40% MSE** 대 fp32 reference.

### 4.3 QAT 필수

**Post-Training Quantization (PTQ)**: fp32 모델을 int4 로 직접 변환 → 위 error 로 정확도 붕괴.

**Quantization-Aware Training (QAT)**: training 중 int4 rounding 을 모델링 → norm 의 quantization sensitivity 학습 → **accuracy 회복** 가능.

**결론**: WT64v1 은 **QAT-trained 모델 전용**. Product 팀에 이 사실 명시 (spec §22.7 에도 기재).

### 4.4 RMSNorm 가 LayerNorm 대비 정밀도 우위

LayerNorm 의 SUB 후 L2SQ 는 **catastrophic cancellation** 위험 (`x - μ` 가 작으면 상대 오차 증폭). RMSNorm 은 centering 이 없어 이 hazard 회피 → **~10-15% MSE** (LayerNorm 25-40% 대비 절반).

**Product recommendation**: v1.6.1 workload 는 **RMSNorm 을 default 로 채택** — 최신 LLM (LLaMA/Mistral/Qwen) trend 와 일치.

## 5. Latency & throughput 분석

### 5.1 Per-op latency

각 primitive dispatch = ~5-10 cycles data + ~2 cycles Cluster + ~1 cycle NoC = **8-13 cycles**.

**LayerNorm 8-primitive chain**: ~80-100 cycles per tile.
**Monolithic 가상 SIG_LAYERNORM_5D**: ~30-40 cycles.

**3× latency penalty** for RISC-ish.

### 5.2 NoC bandwidth

RISC-ish 는 wave-token 8× 발생. 하지만 정규화는 MATMUL/BMM_3 다음에 오는 소량 op → total workload 의 <10% NoC 사용. 흡수 가능.

### 5.3 End-to-end 영향

Transformer inference 에서 layer 당 (매트릭스 곱셈 3-4개) × 24-96 layers = MATMUL 이 dominant. 정규화 latency 3× 증가는 total 시간에 **~5-8% 증가** 예상.

**Trade-off**: 5-8% latency 대신 **~10K LUT/Cluster 절감 + 새 norm 지원 무한 확장**. 명백한 win.

## 6. 향후 로드맵

### 6.1 v1.6.2 후보

- **4D→3D reduction primitives** (SIG_SUM/MEAN/L2SQ_4D_TO_3D) → InstanceNorm/GroupNorm 완결
- **rsqrt mantissa LUT** (16-entry Q1.15) → precision 4→8 bit 개선
- **int8 guard tile** — LayerNorm 중간 `xc` 를 int8 로 저장, MSE ~15% 회복 (RTL 무변경, SDK 만)

### 6.2 v1.6.3 후보

- **SDK `_lower_norm_*` macro pass 구현** — assembler / wt-sdk 에 자동 lowering. 사용자는 `LAYERNORM` mnemonic 만 쓰면 8 primitives 자동 emit.
- **Fusion optimizer**: 연속된 norm chain 최적화 (예: LayerNorm → RMSNorm sequence 에서 중복 rsqrt 제거)

### 6.3 v1.7+ 전망

- **Non-normalization RISC-ish** — 같은 원칙을 activation function 계열 (softmax, gelu, silu) 로 확장. exp/log approximation primitives 추가.
- **Attention decomposition** — Q·K^T·V 을 SIG_BMM_3 + softmax primitives 로 조합.

## 7. Cross-reference

- [`wt64v1_spec.md`](./wt64v1_spec.md) §22 — 정식 spec (recipe, primitive table)
- [`eh_encoding_expansion.md`](./eh_encoding_expansion.md) §11 — Sentinel-terminated chain (v1.3, RISC-ish 의 인프라)
- [`noc_fragmentation_design.md`](./noc_fragmentation_design.md) — Fragment reassembly (wide input/output infrastructure)

## 8. 배운 것 (session learning)

### 8.1 Design principle 의 힘

사용자의 "RISC-ish decomposition" 발상 하나로 v1.6.1 로드맵이 완전 재정의됨. **1-line insight** → **decades of ISA 설계 노하우** (RISC vs CISC 논쟁) 를 활용한 결정. Architecture 설계에서 **먼저 원칙을 정하고 그 원칙에 따라 primitive 를 조합**하는 것이 그 반대보다 훨씬 강력.

### 8.2 Terminology precision

"RISC" 를 무비판적으로 사용하면 잘못된 기대 유발. **"RISC-ish"** 는 borrowed philosophy 만 표시 — architectural humility. 사용자 후속 지시로 정확 명명 채택.

### 8.3 Amortization 가시화

Design workflow 의 cost 표 (§22.10, §3.1) 로 CISC vs RISC-ish 비교 정량화. 이런 comparative table 은 **stakeholder communication** (product/business team) 에 필수.

### 8.4 QAT 필수성 조기 인지

Precision analysis (§22.7, §4) 로 int4 norm 이 QAT 없이는 accuracy 붕괴함을 조기 발견. **Product 팀에 미리 알려 model training pipeline QAT 채택**하도록 유도해야 함. 이는 spec-level 이 아닌 **product-level risk**.
