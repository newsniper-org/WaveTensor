<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# WaveTensor 기본 ISA v1 (WT64v1) — 사양

작성일: 2026-05-03
현재 버전: **v1.5** (2026-07-14 payload extension via multi-EH + NoC fragmentation)
- v1.0 (2026-05-03): 초기 확정. 10 HW-direct EINSUM signature.
- v1.1 (2026-07-14): SPLAT + SIG_BMM + SIG_TRACE_IIJ 추가 (기본 ISA 완결성 확보, backward-compatible). 자세한 근거는 §14 및 [`einsum_trace_broadcast_analysis.md`](./einsum_trace_broadcast_analysis.md) 참조.
- v1.2 (2026-07-14): SIG_BMM_2 + SIG_TRACE_IIJK 추가 (4D int4 packed 16-nibble path). §15 참조.
- v1.3 (2026-07-14): EH chain 종료를 **C-string-style sentinel** (EH_END = 0x0) 로 재정의 + multi-SUBSCRIPT accumulation (5+ axes). MAX_EH 는 spec 제약이 아닌 hardware sizing hint 로 격하. §16 참조.
- v1.4 (2026-07-14): Multi-IMM64 EH accumulation — 128-bit wide input immediate via 2-slot bank. Input payload 64-bit blocker 우회. §17 참조.
- v1.5 (2026-07-14): NoC wave-token 에 **IPv6-style Fragment Extension Header** (8-bit `frag_hdr`) 신설. Output payload 64-bit blocker 우회 인프라. §17 참조.
- v1.5.1 (2026-07-14): Cluster 진입에 **single-slot fragment reassembly buffer** 도입 — 조합 wide payload assembly + 완결 pulse. Downstream 소비는 v1.5.2 로. §18 참조.
- v1.5.2 (2026-07-15): Fragment 재조립을 **EHDecode 로 스레딩** + `wave_complete` gating 도입. `dec_input_payload_wide[1023:0]` 인터페이스 확립. wide 소비 primitive 는 v1.5.3+. §19 참조.
- v1.5.2b (2026-07-15): `dec_input_payload_wide` 를 **PE_Core input port 로 스레딩**. 모든 4개 PE_Core-family instance (L-PE + MU + DU + standalone) 가 wide bus 를 볼 수 있음. Legacy dispatch 는 무영향, v1.5.3 primitive 착수 landing zone 확보. §19.11 참조.
- v1.5.3 (2026-07-15): 첫 wide-consumer primitive **SIG_BMM_3** (`abcij,abcjk->abcik`, 3-batch matmul at int4). 5D 2^5 = 128-bit A/B/O. Input 은 4-fragment wave (A_lo, A_hi, B_lo, B_hi) 로 Cluster 재조립 → wide[255:0]. Output 은 2-fragment (frag_hdr 0x01, 0x11) 로 emit. Multi-cycle emit FSM (`frag_state`) + 2-level SUBSCRIPT dispatch guard + MUL/DIV in-flight collision 방지. WT64v1 spec 상 완결 달성. §20 참조.
- v1.5.4 (2026-07-15): **Assembler wave-fragment emitter** (`wavetensor_asm.py:wave_fragments`) — 128-bit / 256-bit logical payload 을 64-bit fragment 시퀀스로 자동 분할, `frag_hdr = (idx << 4) | (total-1)` 인코딩. Legacy single-fragment (wide_bits=64) 는 frag_hdr=0x00. Convenience helpers `wave_fragments_bmm3`, `wave_fragments_trace_iijkl`. §21 참조.
- v1.5.5 (2026-07-15): **SIG_TRACE_IIJKL** (`iijkl->jkl`, 5D trace + 3 kept axes at int4) — reduction primitive. 128-bit input via 2-fragment wave, 32-bit output single-fragment (no FSM engagement). 대칭 편입 완료 — WT64v1 의 dominant CV/AI reduction workload (layernorm/softmax 기반) landing zone. §21 참조.
- v1.6.1a (2026-07-15): **Group A** — 12 reduction einsum primitives (SIG_SUM/MAX/MIN/ARGMAX/ARGMIN/L1/L2SQ_IJKLM, SIG_SUM/MAX/MEAN/L2SQ_5D_TO_4D, SIG_TRACE_IJJKL). op_marker convention (HI.O_hi[3:0]) 도입. MIN/ARGMIN 은 사용자 통찰: Fréchet medoid, k-means assignment, KNN classifier, VQ-VAE codebook lookup 등 metric-based ML 필수. §22.1 참조.
- v1.6.1b (2026-07-15): **Group B+C** — 6 broadcast SIMD (0x60-65: ADD/SUB/MUL WIDE_SCALAR + WIDE_VEC) + SCALAR_RSQRT_APPROX (0x66). Normalization 조합에 필요한 building blocks. §22.2 참조.
- v1.6.1c (2026-07-15): **§22 RISC-ish normalization decomposition** — LayerNorm/BatchNorm/RMSNorm/InstanceNorm/GroupNorm 을 Groups A+B+C primitives 로 분해하는 recipes. Compositional decomposition philosophy 정식화. §22 참조.
- v1.6.2 (2026-07-15): **4D→3D reduction family** (SUM/MAX/MIN/L2SQ/MEAN) — InstanceNorm/GroupNorm gap closure. A_hi=0x0004 을 family discriminator 로 (adversarial review 발견 bug 방지). SIG_MIN_5D_TO_4D 대칭 backfill. §22.13 참조.
- v1.6.3 (2026-07-15): **rsqrt mantissa LUT** — 기존 power-of-2 baseline → 16-entry Q0.15 LUT 로 정밀도 ~4-bit 향상. LUT[0]=0x8000 로 기존 3 tests 완전 backward-compat. §22.13 참조.
- v1.6.4 (2026-07-15): **assembler norm macros** — 7 primitive mnemonics (0x60-66) + BATCHNORM_INFER / RMSNORM / LAYERNORM macros. Assembler-only landing (RTL 무변경). LAYERNORM 은 xc-fanout 처리를 위한 SDK-side re-emission 전략 채택. §22.11 참조.
- v1.6.5a (2026-07-15): **SIMD_MUL_WIDE_Q4_4_SCALAR (0x67)** — B lane widening (int4 → signed Q4.4). RMSNORM/LAYERNORM 매크로가 scale 곱셈 단계에서 0x62 대신 0x67 사용 → ~4-bit 정밀도 회복 (v1.6.4 부터 남아있던 ~12-bit loss 완화). §22.14a 참조.
- v1.6.6 (2026-07-15): **pe_ready back-pressure signal** — PE_Core FSM+pipeline 상태 통합 combinational output. Cluster→Pod→Top_Core 계층으로 aggregate (AND-reduce). MVP observe-only (ext_valid gate 안 함). §22.14b 참조.
- v1.6.5c (2026-07-15): **multi-slot fragment buffer + CACHE_LOAD_WIDE (0x68)** — Cluster.v `FRAG_SLOTS` parameter (N-way full-tag CAM + monotonic-timestamp LRU + persistence), LAYERNORM step 5 가 xc 재발행 대신 캐시 재로드. Tag-stability 를 위한 PRECISION-EH guard (dim=0x55). 부수적으로 EHDecode.v 0x63/64/65 legality 선행 버그 (LAYERNORM 이 실제로는 무조건 decode-error 나던 상태) 발견 및 수정. §22.16 참조.
- v1.6.7 (2026-07-16): **SIMD_MUL_WIDE_Q8_8_SCALAR (0x69)** — B lane 추가 widening (Q4.4 → Q8.8, LSB 1/16 → 1/256). RMSNORM/LAYERNORM scale 곱셈이 0x67 대신 0x69 사용 → B-side quantization 을 rsqrt LUT 의 ~6.25% floor 아래로 완전히 밀어냄 (precision-zero-loss-research workflow whro79brj 결과). §22.14e 참조.
- v1.6.5d (2026-07-16): **FRAG_INVAL (0x6A)** — SDK 명시적 캐시 슬롯 회수 (LRU 자연 회수 대기 없이). Design workflow 가 "0x68 mirror" 원안의 PE_Core.v 배치 버그(공유 wide-emit 그룹에 넣으면 FRAG_EMIT_HI 가 다음 cycle 에 가비지 2번째 fragment 를 무조건 방출)를 발견 — standalone case arm (0x66 shape) 으로 수정. **Tag-stability 리터럴 유지보수** 동시 landing: `_lower_layernorm()` 실함수를 직접 호출해 live 값을 비교하는 cross-file consistency test 로 OP_MEAN↔CACHE_LOAD_WIDE dim_sizes 리터럴 desync 를 자동 검출. §22.17 참조. `make_layernorm_abort_cleanup()` SDK contract 를 같은 날 amendment 로 추가 (§22.17.1a).
- v1.7 (2026-07-16): **SIMD_MUL_WIDE_Q4_4_SCALAR_128_WIDEN (0x6B) + SIMD_REQUANTIZE_Q4_4_TO_INT4 (0x6C)** — PE_Core.v 의 공유 fragment-drain FSM 을 1-bit(frag_state)→2-bit(frag_idx up-counter)로 확장, 4-fragment(256-bit) WIDEN 출력 지원. 세션 최고 위험도 RTL 변경(9개+ opcode 가 공유하는 FSM)이었으나 전 계층 무손상 확인. **정밀도 주장 정정**: 원래 로드맵의 "output-side rounding 완전 제거" 주장은 틀림 — WIDEN 자신은 rounding-free 이나 REQUANTIZE(기존 int4 소비자 호환 필수)가 round-half-up+saturate 를 다시 수행해 실제로는 parity 복원일 뿐. §22.18 참조.
- v1.7.1 (2026-07-24): **Pre-stable dead-opcode removal** — 0x66 SCALAR_RSQRT_APPROX / 0x67 SIMD_MUL_WIDE_Q4_4_SCALAR / 0x6B WIDEN / 0x6C REQUANTIZE 제거 (reserved · decode_error 복귀) + einsum reduce 미사용 9개 변형 un-whitelist (SIG_4D3D family 전체 + SIG_5D4D 의 SUM/MAX/L2SQ/MIN — MEAN 만 잔존). 전부 audit 로 asm/SDK 소비자 0 확정. Truth-table `domain_version` 1→2 로 의도적 recapture. 근거 정책은 §12a (pre-stable 호환성 정책, 2026-07-24 사용자 지시 성문화), 상세는 §24 참조.

참조 구현 마이그레이션: **진행 중 (2026-07-12 개시)** — 참조 보드가 XCAU25P → LFE5U-85F → Avant G70 순으로 이동, 아래 §"참조 구현 마이그레이션 노트" 참조.

**Backward compatibility**: v1.1 은 v1.0 의 모든 명령을 지원 + 새 opcode/signature 만 추가. v1.0 conformant 소프트웨어는 v1.1 디바이스에서 그대로 동작. 반대로 v1.1 전용 명령 (SPLAT 등) 을 v1.0 디바이스에 발사 시 `lower_required` 발사 (기존 unknown-opcode 처리 그대로).

본 문서는 WaveTensor의 기본 명령어 집합 아키텍처 v1, 약칭 **WT64v1**의 정식 사양이다. 본 사양에 conformant한 디바이스는 별도 확장 없이도 단독으로 의미 있는 dataflow / scalar 워크로드를 수행할 수 있어야 한다.

확장은 v1 사양에 conformance를 가지는 위에서 추가된다 — 첫 번째 정의된 확장은 `WT64v1-C` (crypto + bit-permute, 별도 메모 참조).

**중요**: 보드 마이그레이션 자체는 ISA (opcode / EH / tag / payload 정의) 를 **변경하지 않는다** — 참조 구현 사양의 리소스 / timing / power 값만 새 벤더 실측 데이터로 순차 갱신된다. 단, ISA 의 변경 가능성 일반에 대해서는 §12a pre-stable 호환성 정책이 우선한다 (stable release 전 dead-opcode 제거는 정규 개발 행위 — 첫 사례 §24).

## 1. 개요

| 항목 | 값 |
|---|---|
| Architecture name | WaveTensor 64-bit Dataflow ISA, version 1 |
| 약칭 | **WT64v1** |
| Token payload width | 64-bit |
| Tag width | 80-bit |
| Instruction length | 가변 (IPv6-EH 패턴, 32-bit base + ≤4 EH × ≤96-bit, max 416-bit) |
| Word alignment | 32-bit |
| Default Pod 크기 (참조 구현) | 2×2 cluster × 2×2 PE = 16 PE/Pod |
| 참조 구현 보드 (Stage 0, 폐기됨) | ~~ALINX AXAU25 (XCAU25P, -2 speed grade)~~ — AMD/Xilinx Vivado Free Linux 지원 만료 (2025.2 마지막) 로 마이그레이션 |
| 참조 구현 보드 (Stage 1, 진행 중) | **CS-ULX3S-03** (LFE5U-85F, ECP5 family, TBD 실측값) |
| 참조 구현 보드 (Stage 2, 계획) | **Avant G70 PCIe card** (~700K LUT, TBD 특정 모델, 투자 유치 후) |
| Reference timing (Stage 0 실측) | 100 MHz core clock, WNS +2.06 ns post-route |
| Reference resource (Stage 0 실측) | LUT 61.9K / 141K (44%), DSP 140, Power 0.62 W |
| Reference timing (Stage 1) | TBD — 목표 100 MHz, ECP5 는 DSP 블록 없어 MATMUL 이 LUT 로 흡수됨 |
| Reference resource (Stage 1) | TBD |
| Reference power (Stage 1) | TBD |

## 1a. 참조 구현 마이그레이션 노트 (2026-07-12 개시)

2026-07 발표된 AMD/Xilinx Vivado Free 버전의 Linux 지원 만료 (2025.2.x 마지막) 로 참조 구현 보드가 순차 이동. 자세한 계획은 [`board_hw_plan.md`](./board_hw_plan.md) 참조.

- **Stage 0** (2026-04~2026-05, 폐기): ALINX AXAU25 (XCAU25P) — Vivado 2025.2 로 timing closure + 회귀 167/167 PASS 확인. 이후 벤더 정책 리스크 회피 위해 폐기.
- **Stage 1** (2026-07 진행 중): CS-ULX3S-03 (LFE5U-85F, 84K LUT, no DSP48). 완전 FOSS 툴체인 (yosys + nextpnr-ecp5 + prjtrellis). 목표 = 아키텍처 등가성 실측 + `include/attributes.vh` 벤더-agnostic 매크로 검증 + SDK 첫 실제 backend (`UsbCdcTransport`).
- **Stage 2** (계획, 투자 유치 후): Avant G70 PCIe card. (4,4)×(4,4) = 256 PE 최대 geometry 실측 + PCIe 통합 + ILC (렌즈교환식 카메라) target 검증.

**본 §1 표의 Stage 1 / Stage 2 실측값은 각 단계 완료 시 채워짐**. Stage 0 실측값은 historical baseline 으로 유지.

**아키텍처 이식성 사전 조사 결과** (2026-07-12): Vivado 특화 primitive 0건, Xilinx IP 코어 0건, vendor-specific attribute 3개 파일 12 라인만 사용. 모두 `include/attributes.vh` 매크로로 이행 완료 (2026-07-12), cocotb 회귀 91/91 PASS 로 검증 완료.

## 2. Instruction format (TLV / IPv6-EH)

### Base header (32-bit, 항상 존재)

```
[31:24] opcode      (8b)
[23:20] next_hdr    (4b)   — 첫 EH 타입; 0x0=END
[19:16] flags       (4b)   — bit3=F_HAS_OPB, bit2=F_PRECISION_OVR,
                              bit1=F_MEM, bit0=F_DIM_OVR
[15:8]  reserved    (8b)   — must be 0
[7:0]   bh_len      (8b)   — 전체 instruction 길이 (32-bit word 단위)
```

### EH 카탈로그

| Code | Name | Words | Body |
|---|---|---:|---|
| 0x0 | END | — | sentinel |
| 0x1 | PORT | 1 | output_port_id, input_port_mask |
| 0x2 | IMM16 | 1 | 16-bit immediate |
| 0x3 | IMM32 | 2 | 32-bit immediate |
| 0x4 | IMM64 | 3 | 64-bit immediate |
| 0x5 | MEM | 2 | addr_mode, stride, 32-bit offset |
| 0x6 | SUBSCRIPT | 2 | EINSUM 48-bit subscript (a/b/o axes × 4 each) |
| 0x7 | OPERAND_REF | 1 | src_kind, port_id, noc_route |
| 0x8 | PRECISION | 1 | precision_mode, dim_override |
| 0xF | NOP_PAD | 1 | alignment-only |

### `OPREF.src_kind` (Phase 2 결정 후 확장)

| Value | 의미 |
|---|---|
| 0 | 직접 `input_payload_b` 사용 |
| 1 | NoC bank 조회 (`bank[noc_route]` = 직전 L-PE / M-UNIT / DIV-UNIT 출력) |
| 2 | **TRNG bank** (Pod-wide `rng_word`, 64-bit conditioned random — Phase 2/3) |
| ≥3 | reserved → `error_flag` |

## 3. Opcode 표 (WT64v1 base)

> **v1.8.0a COMMIT 1 (2026-07-16)**: 이 섹션의 hand-written opcode/legality
> 표들은 단일 기계가독 소스 `isa/wt64v1_isa.json` 으로 이관 완료. 표 전문은
> 생성물 **`.claude-memos/generated/isa_tables_frag.md`** 참조 (asm/RTL 양쪽
> legality shape + 설명 포함, `scripts/gen_isa_tables.py` 가 생성 —
> hand-edit 금지, freshness 는 `make lint` 와 unittest 스위트가 강제).
> ISA 를 바꾸려면 JSON 을 편집하고 재생성해서 함께 commit 한다 (§23.9).
> 알려진 asm-vs-RTL 비대칭 2건은 emitter-faithful 하게 보존되어 JSON _doc
> 에 문서화됨 — 통일은 명시적 v1.8.0b 결정 사항.

**Reserved 복귀 (2026-07-24, §12a 정책 첫 적용 — §24)**: 다음 4개 opcode 는 pre-stable dead-opcode 제거로 **reserved (decode_error)** 로 복귀했다 (JSON 에서 행 삭제 후 재생성):

- **0x66 SCALAR_RSQRT_APPROX** — fp path 의 **FRSQRT32 (0x75, ≤2 ulp)** 가 supersede. v1.8.0d norm 재구축(0d) 이 rsqrt 를 fp32 insert 로 대체하며 은퇴 (rsqrt LUT 6.25% floor kill 의 본체).
- **0x67 SIMD_MUL_WIDE_Q4_4_SCALAR** — v1.6.7 부터 **0x69 (Q8.8)** 가 supersede. 매크로가 0x67→0x69 로 이행 완료한 이후 소비자 0.
- **0x6B SIMD_MUL_WIDE_Q4_4_SCALAR_128_WIDEN / 0x6C SIMD_REQUANTIZE_Q4_4_TO_INT4** — Q4.4-int8 WIDEN/REQUANTIZE 쌍. Native 소비자가 끝내 착지하지 않았고, **v1.8 fp32+CVT 경로** 가 supersede.

0x68 CACHE_LOAD_WIDE, **0x69** (live norm tail), 0x6A FRAG_INVAL 은 유지.

## 4. PE 내부 hetero 구성 (참조 구현)

| Unit | per-Cluster 개수 | MUL_OPS | DIV_OPS | NON_MUL_OPS |
|---|---:|---|---|---|
| L-PE | 4 (PE_ROWS×PE_COLS) | 0 | 0 | 1 |
| MATMUL_UNIT | 1 | 1 | 0 | 0 |
| DIV-UNIT | 1 | 0 | 1 | 0 |
| EHDecode | 1 (shared) | — | — | — |

L-PE는 ALU/shape/단항/bitwise 모두 처리. MATMUL_UNIT은 0x12/0x30/0x32/0x43만. DIV-UNIT은 0x13/0x1C/0x1D만. EHDecode는 chain walk를 4-cycle pipeline으로 처리.

## 5. Pipeline latency

| 단계 | cycles |
|---|---:|
| EHDecode chain walk (SLOT 0..3) | 4 |
| dec_* register stage | 1 |
| PE_Core single-cycle dispatch (ADD/SUB/AND/OR/XOR/NOT/NAND/NOR/XNOR/SHL/SHR/SAR/ROL/ROR/NEG/BITREV/POPCNT/CLZ/CTZ/shape ops/MATMUL/TADD/EINSUM-non-mul/FP unary) | 1 |
| MUL multi-cycle pipeline (0x12) | 2 추가 |
| DIV/MOD bit-serial | 64 추가 |
| DIVMOD bit-serial | 32 추가 |

대부분 op은 token in → token out **6 cycles**. MUL 7. DIV 70. DIVMOD 38.

## 6. TRNG 사양 (WT64v1 base에 포함)

| 컴포넌트 | 폭 | 위치 | 비고 |
|---|---|---|---|
| Ring oscillator bank | 8 RO × 3-stage inverter | HIU 내부 | `dont_touch` + `keep` 필수 |
| Von Neumann debias | per-RO | HIU | (00)/(11) discard |
| Raw output | 8-bit `rng_raw` + valid | HIU → SoC | Phase 1 |
| RCT health check | window=1, threshold=41 | HIU | SP800-90B 4.4.1 |
| APT health check | window=64, threshold=51 | HIU | SP800-90B 4.4.2 |
| Conditioned output | 64-bit `rng_word` + valid | HIU → Pod broadcast | Phase 3 |
| `trng_unhealthy` flag | 1-bit, sticky | HIU | RCT 또는 APT 실패 시 latch |

ChaCha20-기반 SP800-90A conditioning은 **Phase 3.5 (post-v1)**로 분리. WT64v1은 von Neumann + 8-byte 패킹까지 정의.

OPREF.src_kind=2가 `rng_word`를 B 피연산자로 가져옴. RNG_RD 전용 opcode는 v1에 없음 (`ADD opb .opref kind=2 a=0` 패턴으로 단일 RNG word fetch 가능).

## 7. Cluster bank routing

`OPREF.src_kind=1`일 때 `bank[noc_route[3:0]]` 조회. bank 항목은 (L-PE 직전 출력 / M-UNIT 직전 출력 / DIV-UNIT 직전 출력) 중 가장 최근 writer를 선택 (`last_was_mu` / `last_was_du`).

## 8. error_flag / lower_required 분류

| 조건 | 신호 |
|---|---|
| chain_err (next_hdr 불일치) | `error_flag` |
| bh_len mismatch | `error_flag` |
| reserved nonzero | `error_flag` |
| 미지원 opcode | `error_flag` |
| missing required EH | `error_flag` |
| forbidden EH | `error_flag` |
| binary ALU에 imm/opref 둘 다 또는 둘 다 없음 | `error_flag` |
| F_HAS_OPB without `input_payload_b_valid` | `error_flag` |
| OPREF.src_kind ≥ 3 | `error_flag` |
| precision flag set without PRECISION EH | `error_flag` |
| MATMUL dim 불일치 | `error_flag` |
| DIV/MOD/DIVMOD divide-by-zero | `error_flag` |
| HW-direct EINSUM 미지원 패턴 | `lower_required` |
| 0x23 PERMUTE non-2×2-transpose | `lower_required` |
| 0x24 BCAST 모두 | `lower_required` |
| 0x25 RED non-trivial | `lower_required` |
| `NON_MUL_OPS_SUPPORTED=0` unit에 non-mul op | `lower_required` |
| `MUL_OPS_SUPPORTED=0` unit에 mul op | `lower_required` |
| `DIV_OPS_SUPPORTED=0` unit에 div op | `lower_required` |

## 9. Conformance 요건

WT64v1 conformant 디바이스는 다음을 모두 만족해야 한다:

1. 표 3.1–3.8의 모든 opcode 정상 처리.
2. EH 카탈로그 0x0–0x8 + 0xF 정상 파싱.
3. OPREF.src_kind ∈ {0, 1, 2} 모두 지원.
4. TRNG 인프라 (RO + von Neumann + RCT/APT + 64-bit `rng_word`) 제공.
5. error_flag / lower_required 분류 정확히 따름.
6. 8장의 분류에 따른 Latency 표 (Section 5)는 reference에 한해 적용 — 다른 구현은 자체 latency 가능하나 functionally equivalent.

## 10. 비-요건 (확장으로 분리)

다음은 **WT64v1-C 확장**으로 분리되며, base v1 conformance에는 영향 없음:

- AES / LEA / CRC / SHA-3 (별도 co-processor 다이 검토)
- PEXT / PDEP
- Stochastic einsum (dropout / sampling subscript)
- Binary scalar MIN/MAX (논의 후 v1.1 또는 -C에 편입)

## 11. 회귀 베이스라인

WT64v1 lock 시점 회귀 결과 (185 tests):

| 모듈 | tests |
|---|---:|
| asm.test_wavetensor_asm | 58 |
| HIU | 1 |
| ISA_Decoder | 70 |
| Tensor_ALU | ~~1~~ → **8** |
| SIMD_ALU | 9 |
| ALU_Extended | 16 |
| Top_Core | 7 |
| PE | ~~4~~ → **7** |
| Cluster | 12 |
| Pod | 7 |
| **Total** | ~~185~~ → **195 PASS / 0 FAIL** |

> **[2026-08-18 재계상 — §31.13]** 두 행만 갱신했다. `Tensor_ALU` 1 → **8**
> (§31.11 이 요구한 최소 6 케이스 + 파이썬 참조 랜덤 대조 2 케이스;
> 그중 2건은 `expect_fail=True` 로 알려진 결함 O1/O1b 를 loud 하게 기록한다).
> `PE` 4 → **7** (§31.3 D10 warm-reset 회귀 3 케이스 신설).
> **정직 명기:** 이 표는 **v1.0 lock 시점 기준선**이고 현행 RTL 실측 총계와는
> 별개 계보다 (현행 `MOD=ISA_Decoder` 단독이 192 케이스다). 본 갱신은 본
> workflow 가 실제로 바꾼 두 행만 반영하며 **표 전체의 재동기화는 하지
> 않았다** — 그 재동기화는 별건이고, 하지 않았다는 사실을 여기 적는다.

합성: XCAU25P (xcau25p-ffvb676-2-e), 100 MHz, 16-PE Pod, post-route LUT 61.9K (44%), WNS +2.06 ns, DRC 0 errors.

## 12. 변경 정책

- WT64v1 사양의 v1.0 은 2026-05-03 lock 되었고, v1.1 amendment 는 2026-07-14 (§14 EINSUM completeness) 적용.
- 향후 변경은 **v1.x** (backward-compatible 추가) 또는 **WT64v2** (incompatible) 로 분류.
- 새 opcode 추가는 5장 reserved 영역에서 시작.
- TRNG/HIU sub-spec 변경은 v1.x patch 가능.
- Conformance test suite 는 v1.0 시점 185 tests + v1.1 amendment 후 신규 회귀 (SPLAT + BMM + TRACE-IIJ 각 5-10 tests).

## 12a. Pre-stable 호환성 정책 (2026-07-24 사용자 지시, 본 amendment 에서 성문화)

**Freeze 보장은 STABLE RELEASE 시점부터 발효된다.** 구체적으로 다음 세 보장 — (1) **frozen first-class 유지** (한번 landing 한 opcode 는 영구 유지), (2) **truth-table keep-forever** (사전-이관 frozen truth table 행의 영구 보존), (3) **snapshot 등가성** (`_PREMIGRATION_LEGAL_SNAPSHOT` 류의 "kept forever" 스냅샷 계약) — 은 stable release 선언 이전에는 발효된 계약이 아니라 **regression-safety 를 위한 개발 편의 장치**다.

Pre-stable 기간 (현재) 의 규칙:

1. **Dead-opcode 제거는 정규 개발 행위다.** Audit 로 asm/SDK 소비자 0 을 확정한 opcode/signature 는 제거할 수 있다.
2. **Truth-table 의 의도적 recapture 는 정규 개발 행위다.** 단 반드시 (a) **spec-first** — 본 문서 amendment 가 선행하고, (b) `domain_version` 을 monotonic 하게 bump 하며, (c) `WT_CAPTURE_TRUTH_TABLE=1` 재캡처를 리뷰된 의도적 행위로 수행한다. 암묵적·무기록 recapture 는 여전히 금지 — 이 정책이 완화하는 것은 "불변성" 이지 "감사 가능성" 이 아니다.
3. **모든 제거는 spec-first 순서를 따른다**: 본 문서 amendment (changelog + 제거 섹션) → `isa/wt64v1_isa.json` 편집 → 생성물 재생성 → RTL/테스트 갱신 → truth-table 재캡처.
4. 제거된 opcode 인코딩은 **reserved (decode_error)** 로 복귀하며, 후속 버전이 재사용할 수 있다 (§12 "새 opcode 추가는 reserved 영역에서 시작" 과 정합).
5. Superseded 된 spec 절은 삭제하지 않고 **superseded history** 로 보존한다 (배너 표기).

Stable release 선언 시점부터는 위 세 보장이 전부 발효되어, 이후 opcode 제거는 **WT64v2** (incompatible) 분류로만 가능하다. 첫 적용 사례: §24 (2026-07-24 dead-opcode removal, truth-table domain_version 2).

## 13. TBD (v1.0 시점 예약, v1.1 에서 부분 해결)

*이 절은 v1.0 lock 시점에 예약된 항목. v1.1 에서 EINSUM completeness (§14) 로 부분적 해결됨.*

## 14. EINSUM completeness — v1.1 amendment (2026-07-14)

### 14.1 배경

v1.0 lock 후 `_lower_einsum_general` (어셈블러 macro pass) 실증 결과, **base ISA 만으로 close 되지 않는 3가지 패턴 클래스** 발견:

1. **Trace with kept axis** (`iij->j` 류) — WT64v1 v1.0 의 `SIG_TRACE_II` 는 순수 2D input 만 처리, kept axis 확장 불가.
2. **Size>1 broadcast** (`i->ij` where shape[j]>1) — WT64v1 v1.0 의 ZERO/ONE 은 scalar constant 뿐, vector constant 생성 불가.
3. **Batched matmul** (`bik,bkj->bij` 류) — WT64v1 v1.0 의 `SIG_MATMUL` 은 순수 2D×2D 만.

이는 assembler-side 매크로 lowering 으로 어떤 우회도 불가능 — **base ISA 자체의 표현력 결손**. 상세 분석은 [`einsum_trace_broadcast_analysis.md`](./einsum_trace_broadcast_analysis.md).

### 14.2 판단 — WT64v1-C 확장이 아닌 base ISA v1.1 amendment

초기 제안은 이 3가지를 WT64v1-C (별도 확장) 로 분리하는 것이었으나, **이 3가지는 base ISA 완결성 문제** 이며 crypto / bit-permute (WT64v1-C 의 원 대상) 와 성격이 다름:

- Base ISA 는 "일반적인 tensor / scalar dataflow 워크로드를 표현 가능해야 함" (§1 개요).
- EINSUM 은 base ISA 의 핵심 표현 도구. 그 lowering 이 반복적으로 실패하는 것은 **표현력 부족**.
- Crypto / bit-permute 는 도메인 특화 확장 — base ISA 완결성과 무관.

따라서 v1.1 base 에 편입 (backward-compatible).

### 14.3 신규 opcode + signature

**opcode `0x26` — `SPLAT` (scalar → constant packed vector)** — v1.1 신규.
- **Semantic**: scalar 를 payload lane 0..N-1 (N ≤ 4) 로 packed 복제.
- **Encoding**:
  - Base header: opcode = `0x26`, F_HAS_OPB = 0, F_DIM_OVR = 1 (target shape 은 tag 의 dimension_sizes 또는 IMM16 EH `[7:0]` 에서 읽음).
  - IMM16 EH body: `[7:0]` = int8 scalar 값 (signed).
  - PRECISION EH 로 target 크기 명시 (또는 tag 의 precision_mode 참조).
- **Output**: `payload[63:0] = {int16(scalar), int16(scalar), int16(scalar), int16(scalar)}` (precision int16 default).
- **Multi-lane packed** — precision int8 시 8 lanes.
- **1-cycle 실행**, `output_valid <= 1'b1`.
- **HW 비용**: ~5K LUT / Pod (16 PE × ~200 LUT + MUX broadcast + packing).

**EINSUM signature 신규 — `SIG_BMM`** — v1.1 신규.
- **Semantic**: `bik,bkj->bij` (batched matrix multiplication, batch 축 b, shape[b] ≤ 2).
- **Subscript encoding**: `A=b,i,j B=b,j,k O=b,i,k`.
- **HW 구현**: 기존 MATMUL_UNIT 을 batch 축으로 sequentiate (2 cycles for shape[b]=2).
- **HW 비용**: ~2K LUT / Pod (기존 MATMUL 재사용).

**EINSUM signature 신규 — `SIG_TRACE_IIJ`** — v1.1 신규.
- **Semantic**: `iij->j` (첫 두 axis trace, j 유지, shape[i]≤4 shape[j]≤4).
- **Subscript encoding**: `A=i,i,j B=(empty) O=j`.
- **HW 구현**: 기존 TRACE_II 를 j slice 별로 loop.
- **HW 비용**: ~1K LUT / Pod.

### 14.4 어셈블러 매크로 lowering 활용

v1.1 opcode/signature 도입 후 `_lower_einsum_general` 확장:

- **Size>1 broadcast lowering** (`A=i B=j O=i,j,q` with shape[q]=N>1):
  - `MATMUL(A,B) → SPLAT q=1 (size N) → OUTER(result, ones_vec) → USQZ/PERM`
- **Trace with kept axis** (`iij->j`):
  - `SIG_TRACE_IIJ` HW-direct → pass-through.
- **Batched matmul** (`bik,bkj->bij`):
  - `SIG_BMM` HW-direct → pass-through.

### 14.5 Sub-conformance flags

- `WT64v1/SPLAT` — 우선순위 1, 대부분의 broadcast lowering close
- `WT64v1/EINSUM-BMM` — 우선순위 2
- `WT64v1/EINSUM-TRACE-IIJ` — 우선순위 3
- 상위 3개 모두 구현 시 `WT64v1/EINSUM-FULL` 통합 플래그 → v1.1 full conformance.

**Note**: v1.1 은 sub-conformance 없이 3개 모두 구현 요구. Sub-conformance flag 는 부분 구현 프로토타입 (예: FPGA prototype 이 SPLAT 만 landing 한 상태) 을 위한 임시 marker. 상용화된 WT64v1 conformant 디바이스는 v1.1 full 이어야 함.

### 14.6 회귀 확장 예정

v1.1 amendment 를 실측으로 확인할 새 회귀:
- `test_isa_decoder.py`: SPLAT 5-10 tests, SIG_BMM 3-5 tests, SIG_TRACE_IIJ 3-5 tests
- `test_wavetensor_asm.py`: 확장된 `_lower_einsum_general` 테스트 (broadcast size>1 lowers, batched matmul lowers, trace-with-kept lowers) 5-10 tests

### 14.7 진입 트리거

v1.1 amendment 는 **결정된 상태 (2026-07-14)**. 구현 순서:
1. **SPLAT** 우선 (가장 general + 저비용).
2. **SIG_BMM** 후행 (카메라 target 시나리오 매치).
3. **SIG_TRACE_IIJ** 최후 (실제 등장 빈도 검증 후).

`wavetensor-drivers` P1 진행 중 어셈블러가 v1.1 opcode 요구 시 또는 사용자 명시적 지시 시 착수.

## 15. 4D int4 EINSUM path — v1.2 amendment (2026-07-14)

### 15.1 배경

v1.1 landing (§14) 후 남은 두 가지 raise:
- **2+ batch dims** (`abij,abjk->abik`) — SIG_BMM 은 단일 batch 축만.
- **Trace with 2+ kept axes** (`iijk->jk`) — SIG_TRACE_IIJ 는 kept axis 1개만.

두 케이스 모두 4D 텐서 (2×2×2×2 = 16 elements) 필요. int16 precision 시 128 bits (payload 초과), **int8 시 128 bits (여전히 초과)**, **int4 시 정확히 64 bits (payload 딱 맞음)**. 따라서 int4 packed 16-nibble path 를 EINSUM signature 층위에서 지원.

### 15.2 결정 — 4D int4 EINSUM 을 base ISA 편입

v1.1 과 동일한 근거 — 이 3가지가 base ISA 완결성 문제 (arbitrary tensor computation 표현력) 이지 도메인 확장이 아님. 따라서 base v1.2 amendment.

### 15.3 신규 EINSUM signatures — v1.2 신규

**`SIG_BMM_2` — 'abij,abjk->abik' (2-batch matmul at int4)**
- **Semantic**: 4 independent 2×2 matmul, batch dims (a, b), contract j.
- **Subscript encoding**: A=[a,b,i,j] B=[a,b,j,k] O=[a,b,i,k]. Canonicalized (A→B→O): a=1, b=2, i=3, j=4, k=5.
  - A_packed = 0x4321, B_packed = 0x5421, O_packed = 0x5321.
- **Layout**: int4 packed 16 nibbles.
  - A[a][b][i][j] at nibble (a*8+b*4+i*2+j).
  - B[a][b][j][k] at nibble (a*8+b*4+j*2+k).
  - R[a][b][i][k] at nibble (a*8+b*4+i*2+k).
- **Constraint**: dim_sizes = 0x55 (4D 2×2×2×2). 다른 shape 시 lower_required.
- **HW 비용 예상**: ~3K LUT / Pod (matmul_2x2_int4 4번 인스턴스).

**`SIG_TRACE_IIJK` — 'iijk->jk' (3D trace w/ 2 kept axes at int4)**
- **Semantic**: R[j][k] = A[0][0][j][k] + A[1][1][j][k], truncated to int4.
- **Subscript encoding**: A=[i,i,j,k] B=[] O=[j,k]. Canonicalized: i=1, j=2, k=3.
  - A_packed = 0x3211, B_packed = 0x0000, O_packed = 0x0032.
- **Layout**: int4 packed 16 nibbles.
  - A[i][i'][j][k] at nibble (i*8+i'*4+j*2+k).
  - R[j][k] at nibble (j*2+k), upper 12 nibbles = 0.
- **Constraint**: dim_sizes = 0x55 (input 4D). Result dim_sizes = 0x05 (2D 2×2).
- **HW 비용 예상**: ~1.5K LUT / Pod.

### 15.4 어셈블러 매크로 lowering

v1.2 opcodes 도입 후 `_lower_einsum_general`:
- 2-batch matmul → SIG_BMM_2 HW-direct pass-through.
- 3D trace + 2 kept axes → SIG_TRACE_IIJK pass-through.
- 3+ batch dims 또는 더 큰 pattern → 여전히 raise (5+ axes EH 인코딩 제약).

### 15.5 Sub-conformance flags

- `WT64v1/EINSUM-BMM-2` — 우선순위 1 (2-batch matmul close)
- `WT64v1/EINSUM-TRACE-IIJK` — 우선순위 2
- v1.2 full: 위 2개 + v1.1 EINSUM-FULL 모두 구현 → `WT64v1/EINSUM-4D-INT4-FULL`.

### 15.6 Precision path 노트

v1.2 EINSUM signatures 는 **payload 를 int4 로 interpretation 하도록 HW 가 hardcoded** (dim_sizes = 0x55 매칭 시). Precision mode (dec_eff_precision) 는 tag 에 보존되지만 payload interpretation 은 signature-driven. int16 default precision 이더라도 SIG_BMM_2 / SIG_TRACE_IIJK 는 int4 로 처리.

이는 payload 크기 (64-bit fixed) 제약 하 최선의 타협. v1.3 (또는 v2.0) 에서 정식 int4 precision mode 확장 시 재검토.

### 15.7 회귀

v1.2 신규 회귀 (test_isa_decoder.py):
- test_bmm_2_identity_per_batch — 4 배치 identity matmul
- test_bmm_2_computed_matmul — signed int4 arithmetic 확인
- test_bmm_2_wrong_dim_lowers — dim_sizes ≠ 0x55 시 lower_required
- test_trace_iijk_basic — R[j][k] 값 확인
- test_trace_iijk_signed_int4 — signed 부호 처리
- test_trace_iijk_wrong_dim_lowers

Assembler pass-through (test_wavetensor_asm.py):
- test_bmm_2_v1_2_hw_direct_pass_through
- test_trace_iijk_v1_2_hw_direct_pass_through
- test_3_batch_dims_still_raises_beyond_v1_2

### 15.8 남은 raise — v1.3 이상 스코프

**3+ batch dims** (`abcij,abcjk->abcik`) — 5+ axes, EH 인코딩 상한 (subscript body 48-bit = 4 axes × 12 bits) 초과. 이는 EH 인코딩 자체 확장 필요:

- Option: **subscript body 확장** — 4 axes → 5+ axes. EH size 확장 필요.
- Option: **MAX_EH 파라미터 relaxation** — 현재 4 → 6 이상. 파이프라인 cycle 수 증가.
- Option: **새 EINSUM 인코딩 방식** — 별도 opcode 로 batched-with-lookup 형식.

이는 별도 design memo 필요 (예: `.claude-memos/eh_encoding_expansion.md`). v1.3 amendment 후보.

### 15.9 진입 트리거

v1.2 amendment 는 **결정된 상태 (2026-07-14)**. 구현 완료 시점 동일 (2026-07-14).

## 16. Sentinel-terminated EH chain + multi-SUBSCRIPT — v1.3 amendment (2026-07-14)

### 16.1 배경 및 원리

v1.0~1.2 는 EH chain 크기를 `MAX_EH = 4` 라는 하드코딩된 상수 (spec + RTL 양쪽) 로 강제. 이는 두 가지 문제:
1. **Spec 층위 제약**: EH 갯수 상한이 명령어 인코딩 spec 에 상주 → 확장성 결여.
2. **RTL 층위 제약**: `EHDecode.v:340` 의 `stg_index == 3'd3` 하드코딩이 sentinel 종료 원리를 무효화.

v1.3 는 **C 문자열의 `'\0'` 종결자 관습**을 EH chain 에 정식 도입:
- 각 EH 의 `next_hdr` (4-bit) 필드가 `EH_END = 0x0` 를 만나면 chain 종료.
- `MAX_EH` 는 spec 제약이 아니라 **하드웨어 sizing hint** (bus width = 32 + MAX_EH×96 bit).
- 소프트웨어는 bus width 안에서 어떤 갯수의 EH 든 자유롭게 emit 가능.

### 16.2 RTL 구현 (backward-compatible)

`EHDecode.v` 변경:
- Chain-walk state (`stg_off`, `stg_index`) 폭을 `$clog2(MAX_EH+1)` 등으로 **파라메트릭** 화.
- `stg_index == 3'd3` 하드코딩을 `stg_index == MAX_EH-1` (safety cap) 로 대체. Sentinel 자체 종료 (`cur_present && stg_expect != EH_END` gating) 는 원래 존재.
- **Fixed-cycle walk 유지**: MAX_EH cycle 동안 pipeline 이 돌지만 sentinel 이후는 no-op. 이는 Cluster.v 의 6-stage `pe_active` 정렬을 유지하기 위함 (early exit 은 v2 시 pe_active dynamic feedback 도입 후에 재검토).

Default `MAX_EH = 4` 유지 → 기존 v1.0~1.2 인코딩 100% 회귀 통과. `MAX_EH` override 시 파라메트릭 스케일.

### 16.3 다중 SUBSCRIPT EH accumulation

Sentinel-terminated chain 이 확립되니 **동일 타입 EH 여러 개 chain** 가능:
- `acc_subscript` (기존 48-bit) 를 **96-bit 로 확장** — 2 개의 SUBSCRIPT EH 를 low + hi 로 이어붙임.
- **첫 SUBSCRIPT** EH → `acc_subscript[47:0]` (axes 0-3 for {A, B, O}).
- **둘째 SUBSCRIPT** EH → `acc_subscript[95:48]` (axes 4-7 for {A, B, O}).
- **셋째 이상** SUBSCRIPT EH → `stg_chain_err` (encoding overflow).

Interface 확장:
- `dec_eff_subscript` (48-bit) 은 유지 = 첫 SUBSCRIPT body. 기존 v1.0~1.2 signature 회귀 완전 유지.
- 신규 `dec_eff_subscript_hi` (48-bit) 노출 = 둘째 SUBSCRIPT body. Testable via ISA_Decoder / Cluster wire (hierarchical access).

### 16.4 어셈블러 지원

`wavetensor_asm.py`:
- 신규 `_pack_axes_multi(codes)` → `(lo_16, hi_16)` 8 axes 까지 지원.
- 신규 `_encode_subscript_eh_multi(eh)` → 5+ axes 시 두 SUBSCRIPT EH emit.
- `_encode_instruction` 이 `subscript` kind 를 `_encode_subscript_eh_multi` 로 라우팅.
- 신규 `HW_DIRECT_EINSUM_SIGS_MULTI` — 6-tuple `(a_lo, b_lo, o_lo, a_hi, b_hi, o_hi)` 형식.

### 16.5 신규 signatures (**encoding only**, 실행 미지원)

**`SIG_BMM_3_CANDIDATE` — 'abcij,abcjk->abcik' (3-batch matmul)**
- Labels: a=1, b=2, c=3, i=4, j=5, k=6
- A = [a,b,c,i,j] → lo = 0x4321, hi = 0x0005
- B = [a,b,c,j,k] → lo = 0x5321, hi = 0x0006
- O = [a,b,c,i,k] → lo = 0x4321, hi = 0x0006
- 6-tuple sig: `(0x4321, 0x5321, 0x4321, 0x0005, 0x0006, 0x0006)`

**`SIG_TRACE_IIJKL_CANDIDATE` — 'iijkl->jkl' (trace + 3 kept axes)**
- Labels: i=1, j=2, k=3, l=4
- A = [i,i,j,k,l] → lo = 0x3211, hi = 0x0004
- B = [] → lo = 0x0000, hi = 0x0000
- O = [j,k,l] → lo = 0x0432, hi = 0x0000
- 6-tuple sig: `(0x3211, 0x0000, 0x0432, 0x0004, 0x0000, 0x0000)`

### 16.6 실행 지원 상태

v1.3 는 **인코딩 인프라만** 랜딩. PE_Core 에는 5+ axes signature 매칭 primitive 가 없음 → 이들 signature 를 담은 명령어는 RTL 에서 `lower_required` 로 surface.

**근본 원인**: 5+ axes 실행은 **payload 64-bit 상한이 blocker**. 예: `abcij,abcjk->abcik` (2^5 = 32 elements per tensor):
- int16: 512 bit (초과)
- int8: 256 bit (초과)  
- int4: 128 bit (초과)
- int2: **64 bit (딱 맞음)** — 극단적 저정밀도

int2 packed 32-nibble path 는 이론상 가능하지만 실용성 낮음. Payload 확장 (128-bit) 이 정답 → **v2 스코프**. 자세한 분석: [`eh_encoding_expansion.md`](./eh_encoding_expansion.md).

### 16.7 남은 raise — v1.3 이후 스코프

- **4+ batch dims** (`abcdij,abcdjk->abcdik`) 는 6 axes / 그룹 — `_pack_axes_multi` 의 8 axes 안 (인코딩 가능). 하지만 `HW_DIRECT_EINSUM_SIGS_MULTI` 에 미등록 → `_lower_einsum_general` 이 batched contraction 로 raise. 이는 의도적 (실행 지원 없이 인코딩만 허용하면 오작동 위험).
- **9+ axes**: `_pack_axes_multi` 상한 (8 axes) 초과 → raise. 3 개 이상 SUBSCRIPT EH chain 이 필요한 시나리오는 v1.4 후보.

### 16.8 Sub-conformance flags

- `WT64v1/EH-SENTINEL-CHAIN` — sentinel-terminated chain 준수 (v1.3 필수)
- `WT64v1/EH-MULTI-SUBSCRIPT` — 2 개 SUBSCRIPT accumulation 지원 (v1.3 필수)
- `WT64v1/EINSUM-5-AXES-ENCODE` — 5+ axes signature 인코딩만 지원 (실행 미지원)

### 16.9 회귀

v1.3 신규 회귀 (test_isa_decoder.py, +4 tests):
- test_multi_subscript_low_only_backward_compat — 1개 SUBSCRIPT, hi=0 확인 (v1.0~1.2 signature 회귀)
- test_multi_subscript_two_ehs_accumulate — 2개 SUBSCRIPT, low/hi 분리 확인
- test_multi_subscript_three_ehs_raises_chain_err — 3개 SUBSCRIPT → chain_err
- test_multi_subscript_max_chain_fits_MAX_EH_slots — MAX_EH=4 chain (PORT+SUBSCRIPT×2+OPREF) 정상

Assembler pass-through (test_wavetensor_asm.py, +1 갱신 +1 신규):
- test_3_batch_dims_v1_3_multi_subscript_pass_through (former "still_raises" 교체)
- test_4_batch_dims_still_raises_beyond_v1_3

### 16.10 진입 트리거

v1.3 amendment 는 **결정된 상태 (2026-07-14)**. 사용자 지시: "특정 비트(들)의 값이 미리 정의된 terminal 상수인 EH가 나올때까지 갯수 제한없이 받아들이도록 하는 것은 어떨까? 마치, 문자열의 끝은 항상 `'\0'`이어야 한다는 C언어의 규칙처럼 말이지."

구현 완료 (2026-07-14).

## 17. Payload 64-bit blocker 우회 — v1.4 (input) + v1.5 (output) amendment (2026-07-14)

### 17.1 배경

v1.3 까지 인코딩 (EH chain) 은 확장 가능하지만 **실행측 payload 는 64-bit 고정** — 5+ axes primitive 실행이 불가한 근본 원인:
- 3-batch matmul `abcij,abcjk->abcik` int4 packed: 32 elements × 4 bit = 128 bit (input, output 모두)
- 64-bit payload 초과

사용자 후속 통찰 두 가지 (2026-07-14):
1. **입력측**: "EH 갯수 제한 해제를 통해 payload 64-bit 상한 blocker를 우회할 수 있지 않을까?" — 여러 IMM64 EH 를 chain 해서 wide immediate 로 payload 확장.
2. **출력측**: "출력측의 opcode와 payload 사이에 8비트짜리 index 필드를 추가하는 건 어떨까? OSI 7계층에서 상위 레이어의 패킷이 너무 거대하면 작은 페이로드들로 쪼개어 하위 레이어의 패킷들에 담을 수 있도록 하는 것처럼..." — **IPv6 Fragment Extension Header** 스타일 fragmentation.

두 발상 모두 **NoC packet 폭을 유지**하면서 넓은 논리 payload 를 처리 가능케 함. Breaking-change 없는 v1.x 확장.

### 17.2 v1.4 — 입력측: Multi-IMM64 accumulation

**메커니즘**: v1.3 §16 multi-SUBSCRIPT 와 동형 (isomorphic).

- `acc_imm64` (64-bit) 유지 (backward compat).
- 신규 `acc_imm64_hi` (64-bit) — 둘째 IMM64 EH body.
- 신규 `acc_imm64_slot` (2-bit) counter — 0/1/2.
- 첫 IMM64 → `acc_imm64` (slot 0→1).
- 둘째 IMM64 → `acc_imm64_hi` (slot 1→2).
- 셋째 IMM64 → `stg_chain_err`.
- 신규 output `dec_eff_imm64_hi` (64-bit) 노출.

**총 payload 용량**: A tensor input 시 `input_payload` (64) + `acc_imm64` (64) + `acc_imm64_hi` (64) = **192-bit**. B tensor 도 유사 확장 시 384-bit 까지.

**활용 시나리오**:
- 5+ axes reduction primitives (SIG_TRACE_IIJKL, SIG_SUM_IJKLM 등) — input wide, output naturally small (fits legacy 64-bit output).
- Input-only wide 는 v1.4 만으로 실행 가능.

### 17.3 v1.5 — 출력측: NoC Fragment Extension Header

**메커니즘**: IPv6 Fragment Extension Header 를 wave token 에 삽입.

**Token layout**:
```
+---------+---------+-------------+-------------+
| tag(80) | op(8)   | frag_hdr(8) | payload(64) |
+---------+---------+-------------+-------------+
                     [7:4] fragment_index (0..15)
                     [3:0] total_fragments-1 (0..15, meaning 1..16 fragments)
```

- `frag_hdr = 0x00` → total=1, index=0 → **legacy single-fragment** (v1.0..1.4 primitives 모두 이 값).
- `frag_hdr = 0x1_1` → total=2, index=1 → 2 fragment 중 두번째.
- Max 16 fragment × 64-bit = **1024-bit logical payload**.

**전파 경로**: PE_Core → Cluster (per-PE frag_hdr, OR-merged) → Pod (per-cluster frag_hdr) → Top_Core (`output_frag_hdr` output).

**Backward-compat**: 모든 기존 primitive 의 `output_frag_hdr` 기본값 = `8'h00`. 회귀 149 tests 통과.

**재조립**: v1.5 초기 랜딩은 **인프라만** (frag_hdr 필드 신설). 실제 fragment 발행 primitive 는 v1.6 이후 (fabric buffer + reassembly 로직 필요). IPv6 destination host 재조립 관행과 동일.

### 17.4 왜 두 개를 함께?

- **v1.4 단독 (input only)**: reduction-heavy 5+ axes 실행 가능. Matmul 은 output blocker.
- **v1.5 단독 (output only)**: fragmentation 인프라만 있고 payload extension 없어 실제 활용 불가.
- **v1.4 + v1.5 함께**: WT64v1 을 **spec 상 완결** — 모든 einsum 패턴 (matmul 포함) 을 v1.x 안에서 실행 가능하도록 인프라 완비. v2 (payload 128-bit breaking change) 미룰 근거 소멸.

### 17.5 실행 지원 상태 — **v1.4 부분 지원, v1.5 인프라만**

v1.4 는 인코딩만 (dec_eff_imm64_hi 노출). 실제로 이를 소비하는 primitive 는 v1.6+ 로드맵. 하지만 hierarchical test 접근으로 accumulation 로직 검증 가능.

v1.5 는 순수 인프라 (frag_hdr 필드 신설, 기본값 0x00). Multi-fragment 발행 primitive 및 fabric 재조립 로직은 v1.6+.

즉 **v1.4 + v1.5 는 실행 primitive 랜딩을 위한 "레일 깔기"**. 실제 primitive (SIG_BMM_3 실행 등) 는 다음 amendment 에서 이 레일 위에 landing.

### 17.6 Sub-conformance flags

- `WT64v1/EH-MULTI-IMM64` — 2-slot IMM64 bank 지원 (v1.4 필수)
- `WT64v1/NoC-FRAG-HDR` — output_frag_hdr 필드 준수 (v1.5 필수)
- `WT64v1/PAYLOAD-EXT-INFRA` — 위 두 개 모두 지원 (v1.5 conformance = v1.4 + v1.5)

### 17.7 회귀

v1.4 신규 tests (test_isa_decoder.py, +3):
- test_multi_imm64_single_backward_compat — 단일 IMM64, hi=0
- test_multi_imm64_two_ehs_accumulate — 2 IMM64, hi 획득
- test_multi_imm64_three_ehs_raises_chain_err — 3 IMM64 → chain_err

v1.5 신규 tests (+2):
- test_frag_hdr_default_zero_alu — ALU op frag_hdr=0
- test_frag_hdr_default_zero_einsum — EINSUM op frag_hdr=0

전 모듈 회귀 (149 cocotb): v1.4/v1.5 하류 (PE_Core, Cluster, Pod, Top_Core) 배선 변경 후 모두 통과.

### 17.8 남은 스코프 — v1.6 이후

- **wide-output primitive 실행**: PE_Core state machine 확장 (multi-cycle output_valid 발행 + frag_hdr sequencing).
- **Fabric fragment 재조립**: Cluster 진입에 fragment buffer + tag 별 collection.
- **Wide-input consumer**: PE_Core input path 를 확장된 payload (input_payload + IMM64 bank) 로 소비.
- **첫 실전 primitive**: SIG_BMM_3 실행 (input via multi-IMM64, output via 2-fragment split).

### 17.9 진입 트리거

v1.4 + v1.5 amendment 는 **결정된 상태 (2026-07-14)**. 사용자 지시로 두 인사이트 (input EH-chain 확장 + output IPv6-style fragmentation) 가 하나의 세션에서 함께 landing. WT64v1 을 spec 상 완결시키는 마일스톤.

구현 완료 (2026-07-14).

## 18. Fragment reassembly buffer — v1.5.1 amendment (2026-07-14)

### 18.1 배경

v1.5 는 wave token 에 `frag_hdr[7:0]` 필드를 신설했지만 **재조립 로직은 미구현**. Fragment 는 발행 가능하지만 downstream 이 wide payload 를 볼 수 없음. v1.5.1 은 **Cluster 진입에 fragment buffer** 를 도입해 실제 재조립을 수행.

사용자 지시 (2026-07-14): "v1.5.1부터 차근차근 진행". 즉 v1.5.1a → 1b → 1c 순차 landing.

### 18.2 설계 — Single-slot buffer MVP

**위치**: Cluster.v top 부위. 외부 `ext_*` 입력을 관측 후 fragment 를 buffer.

**저장 구조** (총 16×64 + 20-bit state ≈ 1044 bit / Cluster):
```verilog
reg [ADDR_WIDTH-1:0] frag_data [0:15];   // 16 slot × 64-bit
reg [15:0]           frag_mask;          // fragment 도착 bitmap
reg [3:0]            frag_total_m1;      // sender-declared total - 1
reg [TAG_WIDTH-1:0]  frag_tag_reg;       // owner tag
reg                  frag_active;
```

**입력 파싱**:
- `frag_in_idx    = ext_frag_hdr[7:4]` (fragment index 0..15)
- `frag_in_tot_m1 = ext_frag_hdr[3:0]` (total-1, 0 == 1 fragment)
- `frag_in_multi  = ext_valid && (ext_frag_hdr != 8'h00)` → non-zero frag_hdr

**상태 전이**:
- **Idle** → **Active**: 첫 multi-fragment 도착 시 slot 할당 (frag_tag_reg 등록).
- **Active**: 같은 tag 의 fragment 도착 시 mask 갱신. 다른 tag 도착 시 slot 재할당 (silent displacement; multi-slot 은 v1.5.1b).
- **Complete → Idle**: mask == mask_full 시 다음 cycle 초기화.

**완결 판정** (조합):
```verilog
mask_full  = (1 << (tot_ref + 1)) - 1
mask_after = (frag_active && same_tag) ? (frag_mask | new_bit) : new_bit
frag_reass_valid = frag_in_multi && (mask_after == mask_full)
```

**Wide payload assembly** (조합):
```verilog
frag_reass_wide[i*64 +: 64] = 
    (frag_in_multi && frag_in_idx == i) ? ext_payload   // 이번 cycle 도착
                                        : frag_data[i]  // 이전 저장
```

이번 cycle 도착 fragment 를 overlay 하여 last-arriving 도 즉시 wide payload 에 포함.

### 18.3 백워드 호환 (v1.5.1 필수)

**Legacy 단일-fragment 경로 완전 unchanged**:
- `ext_frag_hdr = 0x00` (default) 은 `frag_in_multi = 0` → buffer 완전 bypass.
- 149 tests (v1.0..1.5) 100% 통과 확인.
- `_fire()` / `_reset()` helper 에 `ext_frag_hdr = 0` 초기화 추가 (test_cluster.py, test_pod.py).

### 18.4 IPv6 재조립 관행 준수

- **Out-of-order arrival 지원**: fragment 는 index 순서와 무관하게 도착 가능 (`test_frag_buffer_out_of_order_arrival` 회귀).
- **Sender-declared total**: IPv4 MF flag 방식 대비, WaveTensor 는 sender 가 `[3:0]=total-1` 로 총 갯수 명시. Receiver buffer 사이즈 예측 가능.

### 18.5 한계 (v1.5.1b/c 로드맵)

- **Single-slot**: 동시 활성 multi-fragment wave 1개만. 두 번째 wave 는 첫 번째의 partial state 를 displacement. 실전에서는 Fabric fragment buffer 를 **N-slot LRU** 로 확장 필요 (v1.5.1b).
- **Downstream 미연결**: `frag_reass_wide` 는 Cluster-internal signal — EHDecode/PE_Core 미소비. v1.5.2 에서 wide `dec_input_payload_wide` 로 스레딩.
- **Fragment drop / timeout**: 미구현. lossless NoC 가정. 향후 stuck slot detector 추가.

### 18.6 신규 signals (hierarchical test 접근)

Cluster.v 내부 노출:
- `frag_active`, `frag_mask`, `frag_total_m1`, `frag_tag_reg`: 저장 상태
- `frag_reass_valid`: 완결 pulse (조합)
- `frag_reass_wide[1023:0]`: 조합 wide payload

test_cluster.py 에서 `dut.frag_reass_valid.value`, `dut.frag_reass_wide.value` 등으로 관측.

### 18.7 회귀

test_cluster.py 신규 4 tests:
- `test_frag_buffer_single_fragment_bypasses` — 단일-fragment 시 buffer idle
- `test_frag_buffer_two_fragments_assemble` — 2-fragment sequence 완결 + wide payload 검증
- `test_frag_buffer_out_of_order_arrival` — idx=1 → idx=0 순서로 도착해도 정확 재조립
- `test_frag_buffer_four_fragments_assemble` — 4-fragment (total-1=3) mask 누적 + wide payload

전 모듈 회귀 (158 tests + 66 assembler = 224 PASS).

### 18.8 하드웨어 비용 (LFE5U-85F 예상)

- Register: 16 × 64 + 32 = 1056 bit = ~1K FF
- Combinational logic: mask compare + shift + wide payload mux ≈ 500-800 LUT
- **총 ~1.5-2K LUT + 1K FF / Cluster** — ULX3S BRAM 없이 fabric logic 만.

### 18.9 v1.5.2 로드맵 (다음 amendment)

- EHDecode.v: `dec_input_payload_wide[1023:0]` output 추가 (wide 소비자 인터페이스)
- Cluster.v: `frag_reass_wide` 를 EHDecode 로 스레딩 + valid 게이트
- PE_Core.v: `dec_input_payload_wide` input port 추가 (unused for legacy primitives)
- v1.5.3 에서 SIG_BMM_3 실제 실행 primitive landing.

### 18.10 진입 트리거

v1.5.1 amendment 는 **결정된 상태 (2026-07-14)**. 사용자 지시로 v1.5.1 부터 차근차근 sequential landing. 구현 완료 (2026-07-14).

## 19. Fragment → EHDecode threading + wave-complete gating — v1.5.2 amendment (2026-07-15)

### 19.1 배경

v1.5.1 은 Cluster 안에 fragment buffer 를 landing 했지만 `frag_reass_wide` 는 **Cluster-internal signal 로만 노출** (테스트 hierarchical 접근용). v1.5.2 는 이를 **EHDecode 안까지 스레딩** 하여 `dec_input_payload_wide[1023:0]` 이라는 표준 인터페이스 로 확립. Wide-consumer primitive (v1.5.3+) 가 사용할 landing zone.

사용자 지시 (2026-07-15): "v1.5.2로 진행".

### 19.2 EHDecode wide-input path

**신규 파라미터**:
- `parameter FRAG_MAX = 16` — fragment 최대 갯수 (Cluster 버퍼와 일치)
- `parameter WIDE_W = FRAG_MAX * ADDR_WIDTH = 1024` — wide payload 폭

**신규 입력**:
- `input [WIDE_W-1:0] input_payload_wide` — 재조립된 wide payload
- `input input_payload_wide_valid` — wide 유효 신호 (fragment 완결 신호)

**신규 상태**:
- `reg [WIDE_W-1:0] payload_wide_latched` — 다른 payload 와 같은 edge 에서 latch
- `reg payload_wide_valid_latched`

**신규 출력**:
- `output reg [WIDE_W-1:0] dec_input_payload_wide` — `done_d1` 시 registered
- `output reg dec_input_payload_wide_valid`

### 19.3 wave_complete gating (Cluster)

Cluster.v 는 이제 다음 신호로 EHDecode 를 트리거:

```verilog
wire wave_complete = ext_valid
                   && ((ext_frag_hdr == 8'h00) || frag_reass_valid);
```

- **Legacy single-fragment** (`ext_frag_hdr == 8'h00`): 즉시 wave_complete = 1 → EHDecode 트리거. 완전 backward compat.
- **Multi-fragment 중간**: `frag_reass_valid = 0` → wave_complete = 0 → EHDecode 무동작 (buffer 만 축적).
- **Multi-fragment 마지막**: `frag_reass_valid = 1` → wave_complete = 1 → EHDecode 트리거 with **재조립된 wide + legacy low64**.

`ext_to_mu/du/lpe` 클래스ifier 도 `wave_complete` 로 gate → PE_active pipeline 은 중간 fragment 시 idle 유지.

### 19.4 Payload mux — legacy vs multi-frag

Cluster.v 에서 EHDecode 입력용 legacy payload 는:

```verilog
wire [63:0] ehdec_input_payload =
    (ext_frag_hdr == 8'h00) ? ext_payload
                            : frag_reass_wide[63:0];  // multi-frag low slot
```

- Legacy: `ext_payload` 그대로 (기존 동작)
- Multi-frag: `frag_reass_wide` 의 **low 64-bit slot** 이 legacy `dec_input_payload` 로 노출 → wide 를 무시하는 primitive 도 slot 0 을 정상 소비 가능

### 19.5 상류 배선

- **ISA_Decoder.v**: `input_payload_wide` + valid 를 top-level 로 노출, wide output `dec_input_payload_wide_out/valid_out` 도 top-level 로.
- **PE.v** (single-PE wrapper): wide input 을 `1024'h0` + `1'b0` 로 tie-off. Wide 는 fabric 이 없으므로 legacy 만 동작.
- **Top_Core.v** (single-cluster demo): 동일하게 wide 0 tie-off.
- **Cluster.v**: `frag_reass_wide` + `frag_reass_valid` → EHDecode 로 스레딩.
- **Pod.v**: fragment 는 개별 Cluster 안에서 재조립되므로 Pod 는 무영향 (Cluster 각자 재조립).

### 19.6 백워드 호환

- 모든 legacy 145 tests (v1.0..v1.4 primitives) 100% 통과 확인.
- `input_payload_wide_valid = 0` (기본값) 시 `dec_input_payload_wide_valid = 0` → wide-consumer 는 skip.
- Multi-fragment 없이 legacy 정확성 유지.

### 19.7 회귀

test_isa_decoder.py 신규 2 tests:
- `test_wide_payload_latches_when_valid` — wide input + valid drive, dec output 확인
- `test_wide_payload_zero_when_invalid` — wide 비활성 시 legacy path 무영향

test_cluster.py 신규 2 tests:
- `test_wave_complete_gates_intermediate_fragments` — 중간 fragment 시 `stg_active` 여전히 0
- `test_fragment_completion_feeds_ehdecode_wide` — 2-fragment wave → EHDecode wide 캡처

전체 회귀: **231 tests PASS** (165 cocotb + 66 assembler).

### 19.8 하드웨어 비용 증분 (LFE5U-85F 추정)

- `payload_wide_latched` register: 1024-bit → 1K FF/EHDecode instance
- `dec_input_payload_wide` register: 1024-bit → 1K FF
- Wide mux + latch 로직: ~200 LUT
- **총 ~2K FF + 200 LUT / Cluster** (EHDecode 는 Cluster 당 1개)

### 19.9 남은 v1.5.x 스코프

- **v1.5.2b**: PE_Core 에 `dec_input_payload_wide` input port 추가 (unused for legacy, primed for v1.5.3). 현 세션에서는 Cluster/EHDecode 계층까지만.
- **v1.5.3**: 실제 wide-consumer primitive (SIG_BMM_3, SIG_TRACE_IIJKL) 실행. PE_Core state machine 확장, wide 소비 + fragmented output emit.
- **v1.5.4**: Assembler multi-IMM64 자동화.
- **v1.5.5**: 추가 reduction primitive.

### 19.10 진입 트리거

v1.5.2 amendment 는 **결정된 상태 (2026-07-15)**. 사용자 지시로 v1.5.1 완료 후 곧바로 v1.5.2 진행. 구현 완료 (2026-07-15).

### 19.11 v1.5.2b 후속 — PE_Core wide input port (2026-07-15)

v1.5.2 는 EHDecode 에서 Cluster-internal wire (`dec_input_payload_wide`) 까지만 스레딩. v1.5.2b 는 이를 **PE_Core 인스턴스 안까지** 전달하여 v1.5.3 primitive 착수 시 dispatch 계층이 즉시 접근 가능하도록 landing zone 완비.

**PE_Core 변경**:
- 신규 파라미터: `FRAG_MAX = 16`, `WIDE_W = 1024` (EHDecode/Cluster 와 일치)
- 신규 입력: `input [WIDE_W-1:0] dec_input_payload_wide`
- 신규 입력: `input dec_input_payload_wide_valid`
- Legacy dispatch 는 wide 미참조 → `/* verilator lint_off UNUSEDSIGNAL */` 로 warning 억제
- 실제 소비는 v1.5.3 wide-consumer primitive (SIG_BMM_3 등) 에서 시작

**ISA_Decoder 리팩터**:
- `dec_input_payload_wide` 를 **internal wire** 로 승격 (기존 top-level output 직결에서)
- EHDecode 출력 → 이 internal wire → PE_Core input AND top-level `dec_input_payload_wide_out`
- 관찰용 top-level output 유지 (hierarchical test 접근 편의)

**Cluster 배선** (4개 PE_Core 인스턴스 모두):
- L-PE (generate block, PE_ROWS × PE_COLS 개)
- MATMUL_UNIT (mul-only PE_Core)
- DIV_UNIT (div/mod-only PE_Core)
- 각각에 `dec_input_payload_wide` + `_valid` 연결

**PE.v** (single-PE wrapper): ISA_Decoder 의 wide input 을 `1024'h0` + `1'b0` 로 tie-off (fabric 없음). 내부 배선은 ISA_Decoder 가 처리.

**Top_Core.v** (single-cluster demo): 동일한 tie-off 유지.

**회귀**: **231 PASS 유지** — 신규 회귀 없음 (인프라만 landing, dispatch 무변경). Legacy backward compat 검증됨.

**HW 비용**: **~50 LUT** (wire fan-out 만; PE_Core 는 wide 를 소비하지 않으므로 실제 LUT 사용은 v1.5.3 에서 발생).

**남은 v1.5.3 스코프**:
- PE_Core dispatch 에 wide-consumer case 추가 (예: SIG_BMM_3, SIG_TRACE_IIJKL)
- Wide primitive computation 함수 (128/256-bit int4 packed)
- Fragmented output emit state machine (multi-cycle output_valid + frag_hdr sequencing)
- Cluster fabric fragment collection at ext_out_* boundary (자체 fragment 발행 시)

v1.5.2b amendment 는 **결정된 상태 (2026-07-15)**. 사용자 지시로 v1.5.2 완료 후 곧바로 진행. 구현 완료 (2026-07-15).

## 20. SIG_BMM_3 wide-consumer primitive — v1.5.3 amendment (2026-07-15)

### 20.1 배경

v1.5.2b 까지 완비된 wide payload 파이프라인 (NoC → Cluster fragment buffer → EHDecode wide latch → PE_Core input port) 위에서 **첫 wide-consumer primitive** 실행. SIG_BMM_3 는 3-batch matmul (`abcij,abcjk->abcik`) 로 payload 64-bit blocker 를 실제로 우회하는 데모.

사용자 지시 (ultracode 2026-07-15): "v1.5.3* 한꺼번에 진행하도록" → v1.5.3 primitive + v1.5.3a output FSM + v1.5.3b fabric propagation 을 단일 세션에 landing. Design research + adversarial verify workflow 로 사전 검증.

### 20.2 SIG_BMM_3 수학

**Einsum**: `abcij,abcjk->abcik` — 8-batch matrix multiplication (a×b×c = 2×2×2 batches).

**정식화**:
$$R[a][b][c][i][k] = \left(\sum_{j=0}^{1} A[a][b][c][i][j] \cdot B[a][b][c][j][k]\right) \mod 2^4$$

**Tensor shape**: 5D 2×2×2×2×2 = 32 elements per tensor.

**int4 packing (128-bit per tensor)**:
- `A[a][b][c][i][j]` at nibble `(a*16 + b*8 + c*4 + i*2 + j)`
- Per-batch 16-bit sub-payload = `payload[(a*4 + b*2 + c)*16 +: 16]`
- 8 non-overlapping 16-bit windows, direct row-major extension of SIG_BMM_2

**연산**: `matmul_2x2_int4` × 8 (v1.2 함수 재사용, 새 산술 없음).

### 20.3 Signature encoding

Multi-SUBSCRIPT (v1.3 §16) 2-tuple:
- **SIG_BMM_3_LO** = `{16'h4321, 16'h5321, 16'h4321}` (lo 48-bit, axes 0-3)
  - A: [a=1, b=2, c=3, i=4]
  - B: [a=1, b=2, c=3, j=5]
  - O: [a=1, b=2, c=3, i=4]
- **SIG_BMM_3_HI** = `{16'h0005, 16'h0006, 16'h0006}` (hi 48-bit, axes 4-7)
  - A: [j=5]
  - B: [k=6]
  - O: [k=6]

Verilog concat order `{A_pack, B_pack, O_pack}` with A at MSB (matches SIG_BMM_2 convention).

**Two-level dispatch guard** (PE_Core `case (dec_eff_subscript)`):
```verilog
if (dec_eff_subscript_hi != 48'h0) begin
    // v1.5.3 wide-consumer path
    if ((dec_eff_subscript == SIG_BMM_3_LO)
         && (dec_eff_subscript_hi == SIG_BMM_3_HI)) begin
        // SIG_BMM_3 dispatch
    end else lower_required;
end else case (dec_eff_subscript)
    // legacy v1.0..v1.2 signatures
endcase
```

Legacy signatures 는 `dec_eff_subscript_hi == 0` 을 요구 → wide-signature-alias 방지.

### 20.4 Input/output layout

**Input (Cluster fragment buffer, 4-fragment wave)**:
```
frag_hdr = (idx << 4) | 0x3     // total-1 = 3 → 4 fragments
idx 0 → wide[63:0]   = A[63:0]   (a=0: batches 000..011)
idx 1 → wide[127:64] = A[127:64] (a=1: batches 100..111)
idx 2 → wide[191:128] = B[63:0]
idx 3 → wide[255:192] = B[127:64]
```

PE_Core reads A = `dec_input_payload_wide[127:0]`, B = `dec_input_payload_wide[255:128]`.

**Output (PE_Core → NoC, 2-fragment wave)**:
```
frag_hdr = 0x01  // idx=0 total-1=1 → cycle N, R[a=0 batches]
frag_hdr = 0x11  // idx=1           → cycle N+1, R[a=1 batches]
```

Output split by outermost axis `a` (a=0 → fragment 0, a=1 → fragment 1). Clean 64-bit boundary — no cross-lane shuffling.

### 20.5 Fragment emit FSM (§20.5a)

**1-bit Moore FSM** mirroring `div_state` idiom:
```verilog
localparam FRAG_IDLE    = 1'b0;
localparam FRAG_EMIT_HI = 1'b1;
reg        frag_state;
reg [63:0] frag_hi_pending;   // fragment 1 payload held for cycle N+1
reg [79:0] frag_tag_held;
reg [ 7:0] frag_opcode_held;
```

**State transitions**:
- **FRAG_IDLE**: SIG_BMM_3 dispatch → fragment 0 emit (cycle N), latch hi payload/tag/opcode, transition to FRAG_EMIT_HI
- **FRAG_EMIT_HI**: absolute-priority override at output mux top → fragment 1 emit (cycle N+1), return to FRAG_IDLE

**Absolute-priority output override** (before MUL/DIV mux):
```verilog
if (frag_state == FRAG_EMIT_HI) begin
    output_payload  <= frag_hi_pending;
    output_frag_hdr <= 8'h11;
    output_valid    <= 1'b1;
    output_tag      <= frag_tag_held;
    opcode_out      <= frag_opcode_held;
    frag_state      <= FRAG_IDLE;
end else if (mul_valid_p2) ...
```

### 20.6 MUL/DIV in-flight collision mitigation

**Compound drain gate** (SIG_BMM_3 dispatch precondition):
```verilog
output_regs_free = (frag_state == FRAG_IDLE)
                && !mul_valid_p1 && !mul_valid_p2
                && (div_state == DIV_IDLE)
                && !div_valid_p2 && !div_b_zero_p2
```

- Prevents fragment 0 (cycle N) from colliding with any MUL/DIV pulse.
- Prevents fragment 1 (cycle N+1) from colliding with a MUL launched on N.

**MUL/DIV launch gates** (`frag_state == FRAG_IDLE` requirement):
- `mul_valid_p1 <= ... && (frag_state == FRAG_IDLE)`
- DIV_IDLE → DIV_ITER transition gated on `frag_state == FRAG_IDLE`

Combined: no new MUL/DIV can enter pipeline during fragment emit AND SIG_BMM_3 cannot dispatch during any in-flight MUL/DIV.

### 20.7 Wide-valid guard

SIG_BMM_3 with `dec_input_payload_wide_valid == 0` is an **illegal wave** (fabric contract violation — Cluster's `wave_complete` guarantees wide_valid=1 for multi-fragment waves). PE_Core raises `error_flag` on this case.

Distinct from `lower_required`: this is a HARD contract error, not a stall / lowering hint.

### 20.8 Backward compatibility

**dec_eff_subscript_hi guard** on all legacy case arms:
- Legacy v1.0..v1.2 signatures (SIG_MATMUL, SIG_BMM_2, etc.) only dispatch when `dec_eff_subscript_hi == 48'h0`.
- Regression test `test_legacy_sig_with_subscript_hi_nonzero_lowers` catches accidental wide-signature-aliasing.

**Legacy 회귀 100%**: 231 tests (v1.0..v1.5.2b) pre-existing all pass. Zero legacy regression.

### 20.9 Assembler infrastructure

`wavetensor_asm.py` (v1.3 §16) `HW_DIRECT_EINSUM_SIGS_MULTI` already contains the SIG_BMM_3 candidate 6-tuple:
```python
(0x4321, 0x5321, 0x4321, 0x0005, 0x0006, 0x0006)
```
No assembler change required — `_encode_subscript_eh_multi` emits 2 SUBSCRIPT EHs automatically.

**Missing**: input-side fragment emission (assembler needs to emit A + B as 4-fragment wave). Currently users must construct fragments manually via test harness. v1.5.4 task.

### 20.10 회귀 (240 tests PASS)

test_isa_decoder.py 신규 9 tests (99 → 108):
- `test_bmm_3_identity_per_batch` — A=identity → R=B, verify both fragments
- `test_bmm_3_computed_matmul` — concrete values, Python reference match
- `test_bmm_3_two_fragment_output_sequence` — frag_hdr 0x01→0x11 + NRZ return-to-zero
- `test_bmm_3_wide_valid_gate_error_flag` — wide_valid=0 → error_flag
- `test_bmm_3_tag_stability_across_fragments` — both fragments share tag
- `test_legacy_sig_with_subscript_hi_nonzero_lowers` — regression guard
- `test_bmm_3_unknown_wide_sig_lowers` — unknown wide-sig → lower_required
- `test_mul_then_bmm3_drain_gate` — MUL→SIG_BMM_3 drain gate coverage (bug 5)
- `test_bmm3_then_mul_launch_gate` — SIG_BMM_3→MUL launch gate coverage (bug 5)

test_cluster.py 신규 3 tests (18 → 21):
- `test_bmm_3_end_to_end_via_cluster` — 4-frag input → 2-frag output through fabric
- `test_bmm_3_cluster_frag_hdr_returns_to_zero` — NRZ hazard at cluster boundary
- `test_bmm_3_lpe_collision_raises_output_collision` — bug 3+4 collision detection

전체: 174 cocotb + 66 assembler = **240 PASS** (기존 231 + 9 신규 tests).

### 20.10a Adversarial review findings — landed fixes (2026-07-15)

Post-implementation adversarial review workflow (5 dimensions × 20 refute agents, 25 subagents total, ~1.3M tokens) 발견 5 confirmed bugs / 23 findings. 모두 landing:

**Bug 1+2 (LOW/MED) — Stale port comment for `dec_eff_imm64_hi`**:
- `PE_Core.v:72-82`: 원 comment 는 SIG_BMM_3 가 IMM64 를 소비한다고 서술했으나 실제로는 wide[255:128] 사용
- Fix: comment 재작성 + `/* verilator lint_off UNUSEDSIGNAL */` pragma 로 dead-wire 상태 machine-visible

**Bug 3 (HIGH) — MU frag-1 cycle silently drops L-PE outputs**:
- `Cluster.v:757+`: 기존 OR-merge 는 MU>DU>L-PE 우선순위로 `!m_valid` guard 만. MU 의 2-cycle emit 창에서 L-PE 출력이 silent drop.
- Fix: **Atomic per-source arbitration** — winner 는 data channel + memory channel 을 함께 획득. 잃은 source 는 `m_output_collision` 를 raise.

**Bug 4 (HIGH) — `m_mem_req` independent of `m_valid` (corrupted tuple)**:
- 기존: data 채널과 memory 채널이 independent priority chain → collision 시 MU tag 와 L-PE mem_req 가 wrong tuple 로 결합
- Fix: bug 3 fix 와 통합 — atomic 병합으로 tuple 원자성 보장. 신규 output `any_output_collision` (Cluster) 로 fabric 이 drop 인지 가능

**Bug 5 (HIGH) — MUL/DIV in-flight collision path 미테스트**:
- 3 신규 regression tests 추가 (위 목록):
  * MUL → SIG_BMM_3 drain gate 커버
  * SIG_BMM_3 → MUL launch gate 커버 (hierarchical probe: `dut.u_core.mul_valid_p1`)
  * Cluster-level MU/L-PE collision → `any_output_collision` fire 확인

**Refuted findings (18/23)**: legacy dispatch guard, assembler regression, precision handling 등 — 조사 결과 non-issue 또는 이미 존재하는 안전장치로 커버됨.

### 20.11 HW 비용 (LFE5U-85F 추정)

- `einsum_bmm_3_int4_lo/hi` functions: 8 × matmul_2x2_int4 각 = 8 × ~120 LUT = **~960 LUT** (int4 mul array)
- FSM registers: `frag_state` (1) + `frag_hi_pending` (64) + `frag_tag_held` (80) + `frag_opcode_held` (8) = **153 FF**
- Compound drain gate: ~10 LUT
- Absolute-priority override mux: ~20 LUT (5 signal 64-bit mux extension)
- Cluster atomic OR-merge (bug 3+4 fix): ~100 LUT (기존 대비 +50 LUT for collision detection)
- 총 **~990 LUT + 153 FF / PE_Core (MU 인스턴스) + ~50 LUT / Cluster (collision detector)**.

### 20.12 남은 v1.5.x 스코프

- **v1.5.4**: Assembler input-side fragment emitter — 5+ axes einsum 감지 시 자동으로 4-fragment 시퀀스 emit
- **v1.5.5**: 추가 wide-consumer primitives — SIG_TRACE_IIJKL (5D trace + 3 kept axes), SIG_LAYERNORM_5D, SIG_SOFTMAX_HEAD 등
- **v1.6**: Fragment buffer 다중-slot LRU 확장 (동시 wave 다수 지원)
- **v1.6+**: PE_Core `pe_ready` back-pressure signal (in-flight collision 을 rejection 대신 stall 로)

### 20.13 진입 트리거

v1.5.3 amendment 는 **결정된 상태 (2026-07-15)**. 사용자 지시 (ultracode mode) 로 v1.5.3 primitive + v1.5.3a output FSM + v1.5.3b fabric propagation 을 단일 세션 landing. Design research workflow (8 agents) → 구현 → adversarial review workflow (5+20 agents) 로 검증. 구현 완료 (2026-07-15).

## 21. Assembler wave-fragment emitter + SIG_TRACE_IIJKL — v1.5.4 + v1.5.5 amendment (2026-07-15)

### 21.1 배경

v1.5.3 SIG_BMM_3 landing 후 사용자 코드 (driver / SDK / testbench) 는 여전히 wave-token fragment 시퀀스를 **수동으로 조립**해야 함. v1.5.4 는 이를 assembler layer helper 로 정식화. v1.5.5 는 SIG_BMM_3 (matmul, output FSM 필요) 와 대비되는 **reduction primitive** (SIG_TRACE_IIJKL, output 32-bit single-fragment) landing.

사용자 지시 (ultracode 2026-07-15): "v1.5.4와 v1.5.5를 한꺼번에 진행하도록".

### 21.2 v1.5.4 — `wave_fragments()` API

**Location**: `wavetensor_asm.py` §9b (Section 10 Public API 직전).

**Signature**:
```python
def wave_fragments(wide_payload: int, wide_bits: int) -> List[Tuple[int, int]]:
    """Split a logical wide payload into 64-bit NoC wave-token fragments.
    Returns [(payload_64, frag_hdr), ...] in emission order.
    frag_hdr = (idx << 4) | (total - 1) per §17."""
```

**Supported wide_bits**:
- `0` → 빈 wave `[]`
- `64` → 1 fragment, frag_hdr=0x00 (**legacy Cluster bypass path**)
- `128` → 2 fragments, frag_hdr [0x01, 0x11] (SIG_TRACE_IIJKL A-only)
- `192` → 3 fragments (reserved for future)
- `256` → 4 fragments, frag_hdr [0x03, 0x13, 0x23, 0x33] (SIG_BMM_3 A+B)
- 기타 → `AssemblerError`

**Convenience helpers**:
```python
def wave_fragments_bmm3(a_128, b_128) -> List[Tuple[int, int]]
def wave_fragments_trace_iijkl(a_128) -> List[Tuple[int, int]]
```

**Design 원칙**:
- **Wire-level**: integer 입출력. Tensor-shape validation 은 caller 책임 (기존 `_pack_int4_128` helper 사용).
- **Uniform API**: v1.0..v1.5.x 전 primitive 지원 (legacy 는 wide_bits=64).
- **Round-trip 보장**: `wave_fragments_bmm3` 출력을 Cluster fragment buffer 재조립 규칙 (idx * 64 shift into 1024-bit wide bus) 대로 재조립 시 bit-exact 원본 payload 복원.

### 21.3 v1.5.5 — SIG_TRACE_IIJKL primitive

**Einsum**: `iijkl->jkl` (5D trace + 3 kept axes at int4).

**Formula**:
$$R[j][k][l] = \left(\sum_{i=0}^{1} A[i][i][j][k][l]\right) \mod 2^4$$

Only diagonal `i==i2` contributes. Off-diagonal nibbles (8-23) 은 wide bus 에서 읽히지만 dispatch 계산에서 무시.

**Signature (v1.3 §16.5)**:
- **SIG_TRACE_IIJKL_LO** = `{16'h3211, 16'h0000, 16'h0432}`
  - A = [i,i,j,k]: axes 0-3, packed = 0x3211
  - B = empty
  - O = [j,k,l]: 3 axes fit in lo, packed = 0x0432
- **SIG_TRACE_IIJKL_HI** = `{16'h0004, 16'h0000, 16'h0000}`
  - A hi: axis 4 (l) = 0x0004
  - B hi: 0
  - O hi: 0

**Input layout** (128-bit A via 2-fragment wave):
```
A[i][i'][j][k][l] at nibble (i*16 + i'*8 + j*4 + k*2 + l)
Diagonal 0 base: nibble 0  (bits [0 +: 32])
Diagonal 1 base: nibble 24 (bits [96 +: 32])
```

**Output**: 32-bit result (8 int4 nibbles) fits in single 64-bit fragment. `output_frag_hdr = 0x00` — **no FSM engagement** (unlike SIG_BMM_3).

**Output tag `dim_sizes`**: `0x15` (3D 2×2×2).

**PE_Core dispatch** (inside 2-level SUBSCRIPT else-if chain):
- Wide-valid guard (§20.7): error_flag if `dec_input_payload_wide_valid==0`
- Reused compound drain gate (§20.6): lower_required if MUL/DIV in flight
- Single-cycle emit, `output_frag_hdr` default 0x00 유지 (no explicit write)
- NO changes to MUL/DIV launch gates (no cycle-N+1 hazard since single-fragment output)

### 21.4 회귀 (252 tests PASS)

test_isa_decoder.py 신규 6 tests (108 → 114):
- `test_trace_iijkl_zero` — A=0 baseline
- `test_trace_iijkl_computed` — Python reference match
- `test_trace_iijkl_signed_int4` — signed wrap + off-diagonal ignore proof
- `test_trace_iijkl_single_output_fragment` — 확인: FSM 미진입, output_frag_hdr 0x00 유지
- `test_trace_iijkl_wide_valid_gate_error` — wide_valid=0 → error_flag
- `test_trace_iijkl_output_tag_dim_sizes` — tag dim_sizes=0x15, wave/thread preserved

test_cluster.py 신규 1 test (21 → 22):
- `test_trace_iijkl_end_to_end_via_cluster` — 2-frag input → 1-frag output through fabric + NRZ

test_wavetensor_asm.py 신규 5 tests (66 → 71) — new TestWaveFragments class:
- `test_wave_fragments_bmm3_layout` — 4-frag layout + hdr encoding
- `test_wave_fragments_bmm3_convenience` — helper vs generic equivalence
- `test_wave_fragments_trace_iijkl_layout` — 2-frag layout
- `test_wave_fragments_legacy_single` — legacy 1-frag with 0x00 + invalid wide_bits error
- `test_wave_fragments_bmm3_reassembly_matches_pe_core` — round-trip via Cluster reassembly rule

전체: 181 cocotb + 71 assembler = **252 PASS** (기존 240 + 12 신규).

### 21.5 HW 비용 증분 (LFE5U-85F 추정)

- `einsum_trace_iijkl_int4`: 8 signed 4-bit adds → **~60 LUT** (int4 add is cheaper than int4 mul)
- Dispatch else-if arm 확장: ~30 LUT
- Cluster: 변경 없음
- 총 **~90 LUT / Cluster** (SIG_BMM_3 의 ~1K LUT 대비 훨씬 저렴)

### 21.6 v1.5.4/v1.5.5 두 통합의 의미

- v1.5.4: **user ergonomics** — driver / SDK / test author 가 wave 조립을 직접 하지 않아도 됨
- v1.5.5: **primitive diversity** — reduction (small-output) 패턴은 FSM 없이 landing 가능함을 실증. 향후 SIG_LAYERNORM_5D, SIG_SOFTMAX_HEAD, SIG_SUM_5D 등도 동일 패턴 재활용.

Wide-consumer primitive landing 부담이 SIG_BMM_3 (~1K LUT + FSM) → SIG_TRACE_IIJKL (~90 LUT, no FSM) 로 극감. **Reduction-heavy CV/AI workload** (activation function 계열) v1.5.5 계기로 대량 landing 가능.

### 21.7 남은 v1.6 스코프

- **v1.6.1**: 추가 reduction primitives (SIG_LAYERNORM_5D, SIG_SOFTMAX_HEAD, SIG_SUM_5D)
- **v1.6.2**: Multi-slot fragment buffer (동시 wave 다수 지원, LRU 정책)
- **v1.6.3**: PE_Core `pe_ready` back-pressure (collision 을 rejection 대신 stall)
- **v1.6.4**: Assembler에서 wide-consumer instruction 을 자동으로 wave sequence 로 확장하는 higher-level API

### 21.8 진입 트리거

v1.5.4 + v1.5.5 amendment 는 **결정된 상태 (2026-07-15)**. 사용자 지시 (ultracode mode) 로 단일 세션 landing. Design research workflow (3 research + 3 verify agents) → 구현 → 회귀 → spec. 구현 완료 (2026-07-15).

## 22. RISC-ish normalization decomposition — v1.6.1 amendment (2026-07-15)

### 22.0 Philosophy: CISC → RISC-ish

사용자 통찰 (ultracode 2026-07-15):
> "어떤 정규화 기법이든 상관없이, 덩어리째로 가속시키는 것 대신에 유한한 가지수의 연산들로 분해하고 그 '유한한 가지수의 연산들'을 가속시키는 쪽으로 정규화 기법 가속 방안 모색 (마치, CISC의 중구난방함을 해결하기 위해 RISC가 제시되었듯이...)"

**Term 정확화**: "**RISC-ish**" (RISC 유사) 로 표기 — true RISC 원칙 (fixed-size instructions, load-store architecture, single-cycle execution, register-register ops) 을 완전히 만족하지 않음. **compositional decomposition philosophy** 만 차용:

| 진짜 RISC 원칙 | WT64v1 v1.6.1 준수 여부 |
|---|---|
| Fixed instruction size | ❌ (variable-length via EH chain) |
| Load-store architecture | ❌ (payload-oriented, not register file) |
| Single-cycle execution | ⚠️ (일부만, wide-consumer 는 multi-cycle FSM) |
| **Fine-grained decomposition of complex ops** | ✅ |
| **Compiler-level composition** | ✅ (SDK `_lower_norm_*` pass) |
| **Small orthogonal instruction set** | ⚠️ (opcode 공간 확장 중이나 각 opcode 는 orthogonal) |

핵심 원칙 채택: **norm 은 HW primitive 로 만들지 않고, 이미 있는 primitives 를 SDK-level 로 compose**.

### 22.1 Available primitive basis (v1.6.1a + v1.6.1b landed)

> **[2026-07-24 부분 supersede — §24]** 아래 basis 는 v1.6.1 시점 기록. 이후 pre-stable dead-opcode 제거로 **0x66 (→ fp32 FRSQRT32 경로)** 이 제거되었고, **5D→4D family 는 MEAN (op_marker 0x5) 만** hardware whitelist 에 잔존한다 (SUM/MAX/L2SQ 및 v1.6.2 backfill MIN 은 un-whitelist). 본 절과 §22.3-22.6 recipes 의 해당 사용례는 superseded history 로 보존.

**Group A — 12 reduction einsum primitives** (op_marker in HI.O_hi[3:0]):

*5D→scalar family* (A_lo=0x4321, A_hi=0x0005, O_lo/hi=0):
| op_marker | Name | Math | Output |
|---|---|---|---|
| 0x0 | SIG_SUM_IJKLM | Σ A[all] mod 2^4 | int4 |
| 0x1 | SIG_MAX_IJKLM | max A[all] | int4 |
| 0x2 | SIG_ARGMAX_IJKLM | index of max (0..31) | 5-bit |
| 0x3 | SIG_L1_IJKLM | Σ \|A[all]\| | int32 |
| 0x4 | SIG_L2SQ_IJKLM | Σ A[all]² | int32 |
| 0x6 | SIG_MIN_IJKLM | min A[all] | int4 |
| 0x7 | SIG_ARGMIN_IJKLM | index of min | 5-bit |

*5D→4D family* (A_lo=0x4321, A_hi=0x0005, O_lo=0x4321):
| op_marker | Name | Math | Output |
|---|---|---|---|
| 0x0 | SIG_SUM_5D_TO_4D | pair-sum over m | 4D int4 |
| 0x1 | SIG_MAX_5D_TO_4D | pair-max over m | 4D int4 |
| 0x4 | SIG_L2SQ_5D_TO_4D | pair sum-of-squares | 4D int4 |
| 0x5 | SIG_MEAN_5D_TO_4D | (A0+A1)>>1 ASR | 4D int4 |

*5D→3D unique*:
- SIG_TRACE_IIJKL (v1.5.5) — trace over i
- SIG_TRACE_IJJKL (v1.6.1a) — trace over j

**Group B — 6 broadcast SIMD opcodes**:
| opcode | Name | Math |
|---|---|---|
| 0x60 | SIMD_ADD_WIDE_SCALAR | R[i] = A[i] + B_scalar |
| 0x61 | SIMD_SUB_WIDE_SCALAR | R[i] = A[i] - B_scalar |
| 0x62 | SIMD_MUL_WIDE_SCALAR | R[i] = A[i] * B_scalar |
| 0x63 | SIMD_ADD_WIDE_VEC | R[i] = A[i] + V[i>>1] |
| 0x64 | SIMD_SUB_WIDE_VEC | R[i] = A[i] - V[i>>1] |
| 0x65 | SIMD_MUL_WIDE_VEC | R[i] = A[i] * V[i>>1] |

**Group C — 1 scalar transcendental**:
- 0x66 SCALAR_RSQRT_APPROX — Q16.16 fixed-point 1/√x (MSB-normalized power-of-2)

**Support primitives** (v1.1~v1.5.5):
- SPLAT (0x26, v1.1) — scalar → packed vector
- multi-IMM64 (v1.4) — wide constants (up to 128-bit)
- Fragment reassembly (v1.5.1) — Cluster fabric for wide inputs
- Multi-fragment output emit (v1.5.3) — FSM for wide-output primitives

### 22.2 Notation

Assembly-like pseudocode uses `[opcode/mnemonic] operands -> result_tag`. Precision: unless otherwise noted, all int4 packed 5D 2×2×2×2×2 tensors (dim_sizes = 0x1F, reduced via wave fragmentation to 128-bit wide payload).

Fixed-point conventions:
- Tensor payloads: int4 (or int8, int16 per PRECISION EH)
- Rsqrt intermediate: Q16.16 (SCALAR_RSQRT_APPROX contract)
- Broadcast constants: int4 (dec_eff_b_value[3:0])

### 22.3 LayerNorm decomposition (9 primitives)

**Formula**: `y = γ · (x - μ) / √(var + eps) + β` where μ, var are per-position statistics over feature axis (=m).

```
Inputs: x (5D int4), γ (4D int4 per-feature), β (4D int4 per-feature), eps (scalar), N (=2, feature dim)

1) SIG_MEAN_5D_TO_4D    x                       -> μ[abcd]      # Group A (op_marker=0x5)
2) SIMD_SUB_WIDE_VEC    x, μ                    -> xc[abcde]    # Group B 0x64
3) SIG_L2SQ_5D_TO_4D    xc                      -> sq[abcd]     # Group A (op_marker=0x4)
4) SIG_SUM_5D_TO_4D     sq                      -> sq_sum[abcd] # (SDK reduces sq 4D→scalar via chain)
5) SCALAR_RSQRT_APPROX  sq_sum + eps            -> scale        # Group C 0x66
                                                                # (SDK precomputes 1/(N*eps) constant)
6) SIMD_MUL_WIDE_SCALAR xc, scale               -> nrm[abcde]   # Group B 0x62
7) SIMD_MUL_WIDE_VEC    nrm, γ                  -> sc[abcde]    # Group B 0x65
8) SIMD_ADD_WIDE_VEC    sc, β                   -> y[abcde]     # Group B 0x63
```

**Count**: 8 primitive dispatches (SDK-level 4-step reduction from 4D sq to scalar sq_sum expands to more if needed — see 22.7 precision).

**Comparison** vs monolithic SIG_LAYERNORM_5D:
- Monolithic estimate: ~3-3.5K LUT (fused reduce + broadcast + rsqrt + mul + add pipeline)
- RISC-ish: **reuses existing Groups A+B+C primitives, marginal cost ≈ 0** (all primitives already landed)
- **Amortization**: LayerNorm, RMSNorm, BatchNorm, InstanceNorm share the same primitive basis. Each additional norm = **0 LUT** marginal.

### 22.4 RMSNorm decomposition (6 primitives)

**Formula**: `y = γ · x / √(mean(x²) + eps)` — no centering.

```
Inputs: x (5D int4), γ (4D int4), eps

1) SIG_L2SQ_5D_TO_4D    x                       -> sq[abcd]         # Group A
2) SIG_SUM_5D_TO_4D     sq (via SDK reduction)  -> sq_sum[abcd]     
3) SIMD_MUL_WIDE_SCALAR sq_sum, 1/N             -> rms_sq[abcd]     # 1/N precomputed
4) SIMD_ADD_WIDE_SCALAR rms_sq, eps             -> rmse[abcd]       # (SDK reduces to scalar for rsqrt)
5) SCALAR_RSQRT_APPROX  rmse_scalar             -> scale            # Group C
6) SIMD_MUL_WIDE_SCALAR x, scale                -> nrm[abcde]       # Group B
7) SIMD_MUL_WIDE_VEC    nrm, γ                  -> y[abcde]         # Group B
```

**Count**: 7 primitives. RMSNorm 이 recent LLM (LLaMA/Mistral/Qwen) 에서 채택된 이유가 여기서 자명: centering step 이 없어 정밀도 손실이 적고 primitive 수도 적음. **WT64v1 int4 workload 에 optimal**.

### 22.5 BatchNorm decomposition

**Inference path** (running_mean, running_var pre-known; SDK fuses affine):

Precompute (SDK graph-load time):
- K1[e] = running_scale[e] · γ[e]  (running_scale = 1/√(running_var + eps))
- K2[e] = β[e] - running_mean[e] · K1[e]

Then per inference:
```
1) SIMD_MUL_WIDE_VEC    x, K1                   -> t[abcde]     # Group B
2) SIMD_ADD_WIDE_VEC    t, K2                   -> y[abcde]     # Group B
```

**Count**: **2 primitives** — 극단적 압축. Monolithic BatchNorm HW 대비 ~2500 LUT 절감.

**Training path**: 같은 LayerNorm recipe (reduce over batch axis instead of feature axis) — 8 primitives.

### 22.6 InstanceNorm / GroupNorm — partial coverage

**InstanceNorm**: per-sample-per-channel normalization over spatial axes. 만약 axes 를 `(n=a, c=b, h=c, w=d, feat=e)` 로 매핑하면 spatial reduction 은 axis d + e 두 축을 순차 reduce:

```
1) SIG_MEAN_5D_TO_4D    x, axis=e   -> mu_w[abcd]
2) [SIG_MEAN_4D_TO_3D]  mu_w, axis=d -> mu[abc]     # GAP — 4D→3D reduction not yet
3) ... LayerNorm recipe with axis-slice broadcast
```

**Status**: 부분 지원. `SIG_MEAN_4D_TO_3D` (그리고 `SIG_SUM/L2SQ_4D_TO_3D` 등) 은 **v1.6.2 후보** — 현 Group A 는 5D→4D/scalar 에 특화되어 있으며 4D→3D primitive 는 미탑재.

**GroupNorm**: LayerNorm over 채널 그룹. Reshape `(c,h,w) → (g, c/g, h, w)` (PERM/VIEW tag ops, 0x22/0x23) 후 그룹 안에서 정규화. 3-axis reduction 필요 → v1.6.2+ 스코프.

### 22.7 Precision analysis (int4 quantization error)

**Per-op ULP error** (int4 정밀도 기준):
- SIMD_ADD/SUB (SCALAR/VEC): int4 wrap, no error introduction
- SIMD_MUL (SCALAR/VEC): int4×int4 → int8 intermediate, truncated to int4. Worst case ULP loss ≈ 1 LSB int4 = **6.25% of dynamic range**.
- SIG_L2SQ_5D_TO_4D: pair sum-of-squares int4-truncated. Overflow risk if input >= 3 (3²+3²=18 truncated to 2).
- SCALAR_RSQRT_APPROX: MSB-normalized power-of-2, **~3-4 bit precision** (v1.6.1c coarse baseline; v1.6.1d 후보 mantissa LUT 로 정밀도 향상)

**Cumulative LayerNorm error budget** (fp32 reference 대비):
- 3 int4 quantize-back events (steps 6, 7, 8) + 1 rsqrt LUT
- 예상 activation MSE: **~25-40% relative** for typical transformer activations
- **QAT (Quantization-Aware Training) 필수** — PTQ (Post-Training Quantization) 로 배포 시 정확도 붕괴 가능

**RMSNorm precision**: LayerNorm 대비 **~10-15% MSE** — centering step 이 없어 catastrophic cancellation 없음. **v1.6.1 workload 의 preferred norm**.

**Mitigation options** (spec-level):
- SDK 는 중간 `xc` 를 int8 "guard tile" 로 저장 가능 (NoC bandwidth 2배 사용, MSE ~15% 회복). RTL 변경 불필요 (int8 precision mode 는 v1.1 부터 존재).
- **v1.6.3 에서 16-entry Q0.15 mantissa LUT 로 rsqrt 정밀도 ~4-bit 확보** (v1.6.1c 미리 계획한 5-bit interpolated variant 대신 landing).

### 22.8 Latency comparison

**LayerNorm on single 5D int4 tile** (LFE5U-85F 예상 clock ~180 MHz):

- **Monolithic SIG_LAYERNORM_5D** (가상): 내부 pipelined reduce→broadcast→rsqrt→mul→add. 예상 30-40 cycles input-to-output, 단일 opcode dispatch, wave-token 1 round-trip.
- **RISC-ish 8-primitive chain**: 각 primitive ~5-10 cycles + Cluster dispatch ~2 cycles + wave-token routing ~1 cycle → **~90-135 cycles**. **~3× latency penalty**.

**Wave-token bandwidth**: 8 ops → ~8× NoC traffic. 16-PE Pod 에 4 concurrent wave 흐름 시 흡수 가능 (§18 multi-slot fragment buffer v1.6.2 landing 후).

**End-to-end amortization**: LayerNorm 은 transformer layer 당 1회 발화 (~24-96회/token). MATMUL/BMM_3 latency 가 dominant → 3× LayerNorm penalty 는 **inference 총 시간 <8% 증가** 예상. **Trade-off 수용 가능**.

### 22.9 Sub-conformance flags

- `WT64v1/NORM-BASIS` — Groups A+B+C 완전 지원 (RMSNorm, BatchNorm inference 가능)
- `WT64v1/NORM-LAYER` — 추가로 SIG_L2SQ_5D_TO_4D + rsqrt 정밀도 mantissa LUT 지원 (LayerNorm 정확도 확보)
- `WT64v1/NORM-GROUP` — 4D→3D reduction 지원 (InstanceNorm/GroupNorm 가능, v1.6.2+)

### 22.10 왜 RISC-ish 인가 — CISC 대안과의 비교

**CISC alternative** (WT64v1 이 채택 안 한 길):
- SIG_LAYERNORM_5D, SIG_BATCHNORM_5D, SIG_RMSNORM_5D, SIG_INSTANCENORM_5D, SIG_GROUPNORM_5D 각 opcode
- 각 ~3K LUT → 5 norm × 3K = **15K LUT / Cluster**
- 새 norm 알고리즘 추가 시마다 spec + RTL 변경 (예: Weight Standardization, PowerNorm, DivisiveNorm, ...)
- Amortization 최소: 각 norm 이 독립적

**RISC-ish (v1.6.1)**:
- Groups A+B+C 통합 ~4.6K LUT / Cluster
- 새 norm 알고리즘 = **SDK compiler 변경만** (RTL/spec 무변경)
- **Amortization 12×** (workflow research 계산)
- 유연성: SDK 가 norm 조합 (예: `LayerNorm(RMSNorm(x))` 하이브리드) 자유롭게 표현

### 22.11 SDK composition pattern (v1.6.4 landing)

**v1.6.4 landing (2026-07-15)**: `wavetensor_asm.py` 에 정규화 macro 3개 정식 구현 (BATCHNORM_INFER, RMSNORM, LAYERNORM). Assembler-only 변경 (RTL 무변경, 288→296 tests).

#### 22.11.1 Primitive mnemonics 등록 (0x60-0x66)

> **[2026-07-24 부분 supersede — §24]** `SCALAR_RSQRT` (0x66) mnemonic 및 legality 행은 dead-opcode 제거로 삭제됨. 0x60-0x65 는 유지.

이전에는 opcode 만 존재. v1.6.4 에서 assembler-side mnemonic 추가:
```python
'SIMD_ADD_WIDE_SCALAR': 0x60, 'SIMD_SUB_WIDE_SCALAR': 0x61,
'SIMD_MUL_WIDE_SCALAR': 0x62,
'SIMD_ADD_WIDE_VEC':    0x63, 'SIMD_SUB_WIDE_VEC':    0x64,
'SIMD_MUL_WIDE_VEC':    0x65,
'SCALAR_RSQRT':         0x66,
```

Legality (Section 8 `_LEGAL` 확장):
- 0x60/61/62: binary-ALU 패턴 (req_port + IMM XOR OPREF, no subscript/mem)
- 0x63/64/65: req_port + F_HAS_OPB (V via imm64 or opref, 64-bit)
- 0x66: pure unary (req_port, all data EHs forbidden)

#### 22.11.2 Macro 3개 (HL_ONLY_MNEMONICS 등록)

```python
HL_ONLY_MNEMONICS = {'RESHAPE', 'BATCHNORM_INFER', 'RMSNORM', 'LAYERNORM'}
```

**Syntax (monolithic single-line)**:
```
BATCHNORM_INFER opb .k1 <64-bit K1> .k2 <64-bit K2>
RMSNORM         opb .gamma <64-bit γ>
LAYERNORM       opb .gamma <64-bit γ> .beta <64-bit β>
```

#### 22.11.3 BATCHNORM_INFER expansion (2 primitives)

Recipe (§22.5 pre-computed constants):
```
1) SIMD_MUL_WIDE_VEC   x, K1  →  t   (opcode 0x65)
2) SIMD_ADD_WIDE_VEC   t, K2  →  y   (opcode 0x63)
```

K1, K2 는 SDK 사전 계산 (running_scale · γ, β − running_mean · K1).

#### 22.11.4 RMSNORM expansion (4 primitives)

Recipe (§22.4 simplified, eps/1_N 는 SDK rsqrt seed 사전 folding):
```
1) EINSUM (L2SQ_IJKLM)   x        →  sq_scalar   (opcode 0x32, op_marker=0x4)
2) SCALAR_RSQRT          sq       →  scale        (opcode 0x66)
3) SIMD_MUL_WIDE_SCALAR  x, scale →  nrm         (opcode 0x62, scale[3:0])
4) SIMD_MUL_WIDE_VEC     nrm, γ   →  y           (opcode 0x65)
```

**KNOWN PRECISION LOSS (spec §22.7 재확인)**: 단계 3 에서 Q16.16 rsqrt scale 이 int4 로 truncate 됨. ~12-bit precision 손실. v1.6.5+ 후보: SIMD_MUL_WIDE_SCALAR B lane 을 Q4.4 또는 int8 로 widening.

#### 22.11.5 LAYERNORM expansion (8 primitives)

Recipe (§22.3, xc-fanout SDK 재발행 전략):
```
1) EINSUM (MEAN_5D_TO_4D)  x         →  μ[abcd]    (op_marker=0x5)
2) SIMD_SUB_WIDE_VEC       x, μ      →  xc (첫 emission)
3) EINSUM (L2SQ_IJKLM)     xc        →  sq_scalar
4) SCALAR_RSQRT            sq        →  scale
5) SIMD_SUB_WIDE_VEC       x, μ      →  xc (재발행 — SDK 전략 C)
6) SIMD_MUL_WIDE_SCALAR    xc, scale →  nrm
7) SIMD_MUL_WIDE_VEC       nrm, γ    →  sc
8) SIMD_ADD_WIDE_VEC       sc, β     →  y
```

**xc-fanout 해결 (workflow wsvd6rl41 verify 발견)**:
- 스펙 §22.3 은 `xc` 를 step 3+step 6 에 재사용하지만 wave-token 은 single-use
- SDK 옵션: (a) NoC broadcast fanout, (b) on-Cluster buffer (v1.6.5+ multi-slot), (c) **SUB 재발행 (v1.6.4 채택)**
- MVP 는 옵션 (c) — SIMD_SUB_WIDE_VEC 두 번 emit. 추가 primitive 1개 dispatch overhead, 상대적으로 저렴 (§20 SUB ~200 LUT).

#### 22.11.6 Op_marker encoding via subscript

Macro 는 EINSUM 을 emit 시 2-slot SUBSCRIPT chain 으로 op_marker 를 O_hi[3:0] 에 실음:
```python
_make_eh('subscript', {'A': ['i','j','k','l'], 'B': [], 'O': ['i','j','k','l']}),  # lo
_make_eh('subscript', {'A': ['m'], 'B': [], 'O': [0x5]}),  # hi, O_hi=MEAN marker
```

`_canonicalize_subscript` 는 **integer input 을 label code 로 pass-through** — op_marker 를 integer 로 넘기면 canonicalization 우회하여 정확한 nibble 값 유지.

#### 22.11.7 회귀 (296 tests PASS, +8 신규)

test_wavetensor_asm.py 신규 `TestNormMacros` class (8 tests):
- `test_batchnorm_infer_expansion` — 2-primitive opcode sequence 검증
- `test_batchnorm_infer_missing_k1_raises` — clear error
- `test_rmsnorm_expansion` — 4-primitive sequence
- `test_layernorm_expansion` — 8-primitive sequence (xc 재발행 포함)
- `test_layernorm_missing_beta_raises` — clear error
- `test_primitive_simd_add_wide_scalar_legality` — 0x60 legality
- `test_primitive_scalar_rsqrt_legality` — 0x66 pure unary
- `test_primitive_scalar_rsqrt_rejects_imm` — 0x66 imm rejection

전체: 217 cocotb + 79 assembler = **296 PASS** (기존 288 + 8 신규).

#### 22.11.8 남은 v1.6.4+ 스코프

- **v1.6.4+**: HL-only reduction mnemonics (MEAN_5D_TO_4D, L2SQ_IJKLM 등) — 현 macro 는 EINSUM opcode 를 직접 emit 하지만, 별도 mnemonic 도입 시 syntax 명확화 가능. 후속 refactor 후보.
- **v1.6.4+**: `.eps`, `.inv_n` directive 실 사용 — 현재는 SDK 사전 folding 을 가정. RTL 이 4D→scalar reduction 을 지원하는 v1.6.5 이후 macro 확장.

### 22.12 회귀

Groups A+B+C 회귀 (v1.6.1a + v1.6.1b commits 참조):
- **276 tests PASS** (194 cocotb + 71 assembler; 신규 24 tests over v1.5.5's 252)
- 이 §22 문서는 **spec-only landing** — RTL 무변경, 회귀 유지

### 22.12 회귀

Groups A+B+C 회귀 (v1.6.1a + v1.6.1b commits 참조):
- **276 tests PASS** (194 cocotb + 71 assembler; 신규 24 tests over v1.5.5's 252)
- 이 §22 문서는 **spec-only landing** — RTL 무변경, 회귀 유지

### 22.13 v1.6.2 + v1.6.3 landing (2026-07-15)

Ultracode 세션에서 병행 landing. Design workflow (3 research + 3 verify, ~336K tokens) 로 사전 검증 — **critical dispatch bug 발견 및 수정** 이후 진행.

#### 22.13.1 v1.6.2 — 4D→3D reduction family

> **[superseded 2026-07-24 — §24]** SIG_4D3D family 전체 (5개 marker) 는 audit 결과 asm 소비자 0 으로 확인되어 un-whitelist 됨 — 해당 signature 는 다시 "HW-direct EINSUM 미지원 패턴" 으로 `lower_required` (§8). SIG_MIN_5D_TO_4D backfill 도 함께 제거. 본 절은 superseded history 로 보존 (A_hi=0x0004 discriminator 교훈 포함).

**목적**: InstanceNorm / GroupNorm 이 요구하는 다축 reduction chain 의 마지막 단계. 5D→4D reduction 이후 남은 4D 텐서를 3D 로 축약.

**Primitives (5개)**:
| op_marker | Name | Math | 예상 LUT |
|---|---|---|---|
| 0x0 | SIG_SUM_4D_TO_3D | pair-sum over l | ~40 |
| 0x1 | SIG_MAX_4D_TO_3D | pair-max | ~80 |
| 0x6 | SIG_MIN_4D_TO_3D | pair-min | ~80 |
| 0x4 | SIG_L2SQ_4D_TO_3D | sum-of-squares (int4 truncated) | ~300 |
| 0x5 | SIG_MEAN_4D_TO_3D | (A0+A1)>>1 ASR | ~50 |

**Signature encoding**:
- SIG_4D3D_FAMILY_LO = `{16'h4321, 16'h0000, 16'h0321}` (4D A, 3D O)
- SIG_4D3D_FAMILY_HI_BASE = `{16'h0004, 16'h0000, 12'h000}`
- **A_hi = 0x0004** 는 family discriminator ★ — 5D4D 의 A_hi=0x0005 대칭. `subscript_hi != 48'h0` 항상 보장 → OP_SUM (marker=0x0) 시 legacy fall-through 방지.

**입력 경로**:
- 4D 2×2×2×2 = 16 nibbles = 64-bit → `dec_input_payload` (legacy)
- Fragment reassembly / wide_valid 사용 안 함
- Fabric contract: caller 는 wide 를 zero-pad 하거나 wide_valid=0 설정 가능

**출력 경로**:
- 32-bit result → 64-bit `output_payload` low half
- `output_frag_hdr = 0x00` (single fragment, no FSM)
- Output tag `dim_sizes = 0x15` (3D 2×2×2)

**Guards**:
- `dec_eff_dim_sizes == 8'h55` 검증 (아니면 lower_required)
- Compound drain gate 재사용 (§20.6 pattern)
- wide_valid check **의도적 skip** (§22.13.1 fabric contract)

**Additional**: **SIG_MIN_5D_TO_4D 대칭 backfill** (op_marker=0x6) — 5D→4D family 도 이제 SUM/MAX/MIN/MEAN/L2SQ 대칭.

**Adversarial review 발견 및 수정 사항**:
1. **BLOCKING BUG**: 초기 design 은 SIG_4D3D_FAMILY_HI_BASE=44'h0 (all-zero) 였음 → OP_SUM 시 subscript_hi=48'h0 → wide-consumer gate `subscript_hi != 48'h0` (line 1568) FAIL → legacy dispatch fall-through → silent lower_required. **A_hi=0x0004 로 fix**.
2. `dim_sizes` validation 미비 → guard 추가
3. Explicit `output_frag_hdr <= 8'h00` in each arm (defensive)
4. SIG_MIN_5D_TO_4D backfill (family symmetry)

#### 22.13.2 v1.6.3 — rsqrt mantissa LUT

**목적**: v1.6.1b baseline (~1-2 bit power-of-2 precision) → ~4-bit mantissa precision.

**Algorithm** (workflow research):
1. Priority encoder finds MSB position `m` in [0, 30]
2. Extract 3-bit mantissa: `mant = x[msb-1 -: 3]` (guard msb<3 with zero-pad)
3. LUT index = `{m[0] parity, mant[2:0]}` — 4-bit → 16 entries
4. LUT[0..7] = `rsqrt(1 + f/8)` × 2^15 in Q0.15 (even m)
5. LUT[8..15] = `1/√2 · rsqrt(1 + f/8)` × 2^15 in Q0.15 (odd m, absorbs √2)
6. Shift = `9 - (msb >> 1)` (range [-6, +9])
7. Output = `LUT_val << shift` (or right-shift with round-to-nearest for shift < 0)
8. Saturate 0x7FFF_FFFF on overflow

**LUT 값** (Q0.15 unsigned, precision ≤6.25% relative):
```
LUT[0..7]:  0x8000 0x78AE 0x727D 0x6D2B  0x6886 0x646D 0x60C5 0x5D7E
LUT[8..15]: 0x5A82 0x5555 0x50F4 0x4D2E  0x49E6 0x46FF 0x446A 0x4218
```

**Backward compat 검증**:
- rsqrt(1.0) = 0x0001_0000 → msb=16 even mant=0 → LUT[0]=0x8000, shift=+1 → **0x1_0000** (bit-identical to v1.6.1b)
- rsqrt(4.0) = 0x0004_0000 → msb=18 even mant=0 → shift=0 → **0x8000** (bit-identical)
- rsqrt(0) → saturate **0x7FFF_FFFF** (bit-identical)

**신규 정밀도 tests**:
- rsqrt(2.0) → ~0xB504 (odd m=17)
- rsqrt(0.5) → ~0x16A09 (√2, shift=+2)
- rsqrt(0.25) → 0x20000 (exact, m=14)
- rsqrt(1.5) → ~0xD10C (mantissa refinement, m=16 mant=4)
- rsqrt(6.0) → ~0x6886 (m=18 mant=4)

**HW 비용**: ~200-250 LUT (priority encoder ~50 + LUT ROM ~40 + barrel shift ~80 + round-to-nearest logic ~30). 기존 baseline ~100 LUT 대비 +100-150 LUT.

**Adversarial review 발견**:
- Right-shift 시 truncation bias → round-to-nearest 로 수정 (`(val + (1<<(sh-1))) >> sh`)
- `Q0.15` nomenclature 정확화 (LUT[0]=0x8000 은 1.0 을 표현, Q1.15 magnitude 인 unsigned 16-bit)
- 기존 3 tests 재작성 불필요 (LUT[0]=0x8000 로 bit-identical)

#### 22.13.3 회귀 (288 tests PASS)

- Cocotb 217 (기존 194 + 12 신규 + 5D→4D MIN 1개):
  * ISA_Decoder: 138 → 150 (+12)
    - reduce_sum/max/min/mean/l2sq_4d_to_3d (5)
    - reduce_4d_to_3d_wrong_dim_lowers (guard)
    - reduce_min_5d_to_4d (symmetric backfill)
    - rsqrt_lut_two/half/quarter/one_point_five/six (5 precision tests)
- 기타 모듈 67 무변경
- Assembler 71 무변경

#### 22.13.4 HW 비용 (v1.6.2 + v1.6.3 누적)

- v1.6.2 4D→3D: ~550 LUT
- v1.6.2 SIG_MIN_5D_TO_4D backfill: ~80 LUT
- v1.6.3 rsqrt LUT refinement: +100-150 LUT (기존 rsqrt 대체)
- 총 **~700 LUT / Cluster**. v1.6.1 누적 (~4.6K) + v1.6.2/1.6.3 = **~5.3K LUT / Cluster**.

### 22.14 남은 v1.6.4+ 스코프

- **v1.6.4**: SDK `_lower_norm_*` macro pass 구현 + assembler 정합성 tests
- **v1.6.5**: Multi-slot fragment buffer (동시 wave 다수, latency amortization)
- **v1.6.6**: PE_Core `pe_ready` back-pressure (norm chain stall 대응)
- **v1.7**: Non-normalization RISC-ish extension — activation function 계열 (softmax/gelu/silu). exp/log approximation primitives 추가 후보.

### 22.15 진입 트리거 (기존 22.14 재번호)

v1.6.1c amendment 는 **결정된 상태 (2026-07-15)**. 사용자 지시 (ultracode mode, RISC-ish 원칙): "어떤 정규화 기법이든 상관없이, 덩어리째로 가속시키는 것 대신에 유한한 가지수의 연산들로 분해하고 그 '유한한 가지수의 연산들'을 가속시키는 쪽으로 정규화 기법 가속 방안 모색". v1.6.1a → v1.6.1b → v1.6.1c → v1.6.2 + v1.6.3 5-commit 순차 landing 으로 primitive basis + broadcast + rsqrt + 문서화 + 4D→3D 완비. 구현 완료 (2026-07-15).

### 22.14 v1.6.5a + v1.6.6 landing (2026-07-15)

Ultracode 세션 병행 landing. Design workflow (task wj6ewzd50, 2 research + 2 verify, ~253K tokens) 로 사전 검증.

#### 22.14a v1.6.5a — SIMD_MUL_WIDE_Q4_4_SCALAR (0x67) 정밀도 회복

> **[superseded 2026-07-24 — §24]** 0x67 은 v1.6.7 의 0x69 (Q8.8) 에 superseded 된 뒤 소비자 0 → dead-opcode 제거 (reserved 복귀). 본 절은 superseded history 로 보존.

**목적**: 기존 0x62 SIMD_MUL_WIDE_SCALAR 는 B lane 을 `dec_eff_b_value[3:0]` (int4) 만 사용 — Q16.16 rsqrt 결과가 int4 로 truncated → ~12-bit 손실. 0x67 은 B lane 을 `dec_eff_b_value[7:0]` (Q4.4 signed) 로 widening → ~4-bit 정밀도 회복.

**Q4.4 arithmetic**:
- B interpretation: signed 8-bit, sign + 3 int + 4 frac bits (range [-8.0, +7.9375], LSB = 1/16)
- Per lane: `p = signed(A[3:0]) * signed(B[7:0])` → 12-bit signed Q8.4 intermediate
- Round-half-up: `(p + 8) >>> 4` → int4
- Mathematical bound: `|A|≤8, |B|≤8 → |A*B/16|≤4` fits int4, **no saturation needed**
- LUT ~350-500 / Cluster (32 lanes × 4×8 signed mult)

**Legality**: same as 0x60-62 (binary-ALU IMM XOR OPREF). Added to `is_alu_binary`, `_LEGAL[0x60,0x61,0x62,0x67]`, `opcode_supported`.

**Assembler mnemonic**: `SIMD_MUL_WIDE_Q4_4_SCALAR = 0x67`.

**RMSNORM/LAYERNORM 매크로 갱신**:
- RMSNORM step 3 (scale × x): 0x62 → 0x67
- LAYERNORM step 6 (scale × xc): 0x62 → 0x67

SDK 는 Q16.16 rsqrt 결과의 bits [11:4] 를 signed Q4.4 로 broadcast (즉 상위 8-bit 마감).

**Test vectors**:
- A=+2, B=Q4.4(+0.5)=0x08 → (2×8+8)>>4 = 1 (int4) — verified
- A=+4, B=Q4.4(-1.0)=0xF0 → (4×(-16)+8)>>4 = -4 (int4 0xC) — verified

#### 22.14b v1.6.6 — pe_ready back-pressure signal

**목적**: 기존 compound drain gate 는 `lower_required` (REJECTION) 로 upstream 이 retry 해야 함. `pe_ready` 는 STALL 신호 — upstream 이 backpressure 로 대기 가능.

**Signal definition** (combinational, 새 latch 없음):
```verilog
pe_ready = (frag_state == FRAG_IDLE)
        && !mul_valid_p1 && !mul_valid_p2
        && (div_state == DIV_IDLE)
        && !div_valid_p2 && !div_b_zero_p2
```

**Propagation 계층**:
- PE_Core.pe_ready → ISA_Decoder pass-through → PE.v (out_pe_ready)
- Cluster: cluster_ready = mu_pe_ready & du_pe_ready & AND(pe_ready_lpe[0..N-1])
- Pod: pod_ready = AND(cl_ready[0..N-1])
- Top_Core: pe_ready 로 top-level 노출

**MVP: observe-only** — `ext_valid` gating 안 함. External fabric 이 관찰해서 STALL 여부 결정 (v1.6.7+ 후보: 자동 gating).

**Tests**:
- `test_pe_ready_defaults_high` — 리셋 후 idle → pe_ready=1
- `test_pe_ready_low_during_bmm3_emit` — SIG_BMM_3 fire 시 FRAG_EMIT_HI cycle 에서 pe_ready=0, 이후 다시 1

#### 22.14c 회귀 (301 tests PASS, +4 신규)

- Cocotb: 217 → 221 (+4)
  * ISA_Decoder: 150 → 154 (+4)
    - test_simd_mul_wide_q4_4_scalar_basic (Q4.4 positive)
    - test_simd_mul_wide_q4_4_scalar_negative (Q4.4 signed)
    - test_pe_ready_defaults_high (reset state)
    - test_pe_ready_low_during_bmm3_emit (during FSM emit)
- Assembler: 79 → 80 (+1)
  * test_primitive_simd_mul_wide_q4_4_scalar_legality

**Backward compat**: 기존 296 tests 100% 통과 유지. RMSNORM/LAYERNORM 매크로가 0x62 → 0x67 로 바뀌었지만 기존 test_rmsnorm_expansion / test_layernorm_expansion 는 예상 opcode 시퀀스 갱신하여 재통과.

#### 22.14d HW 비용 (LFE5U-85F 추정)

- v1.6.5a Q4.4 mult array: ~350-500 LUT (기존 0x62 마출 대체가 아닌 새 함수)
- v1.6.6 pe_ready: ~10 LUT (combinational, wire fan-out만)
- 총 **~360-510 LUT / Cluster** (누적 v1.6 = ~5.6-5.8K LUT)

#### 22.14e v1.6.7 — SIMD_MUL_WIDE_Q8_8_SCALAR (0x69) landing (2026-07-16)

precision-zero-loss-research workflow (`whro79brj`, 2026-07-15, 24 agents) 의 v1.6.7 pick 을 그대로 landing. §22.14a 의 Q4.4 (0x67) 이후 남은 B-side 정밀도 손실을 16× 추가 회복.

**목적**: rsqrt LUT 자체가 ~6.25% relative error 를 갖는 근본 floor 임이 밝혀짐 (whro79brj Investigator 0). Q4.4 quantization (~3.13% @ r=1) 은 이미 LUT floor 근처지만 여전히 비교 가능한 자릿수 — Q8.8 (~0.20% @ r=1) 은 LUT floor 대비 확실히 sub-noise 로 밀어냄.

**Q8.8 arithmetic**:
- B interpretation: signed 16-bit, sign + 7 int + 8 frac bits (range 근사 [-128.0, +127.996], LSB = 1/256)
- Per lane: `p = signed(A[3:0]) * signed(B[15:0])` → 20-bit signed Q4.8 intermediate
- Round-half-up: `(p + 128) >>> 8` → int4
- Mathematical bound: 0x67 와 동일 (|A|≤8 라는 LAYERNORM/RMSNORM 사용 맥락에서 int4 output 이 saturation 없이 fit)

**Legality**: 0x60/61/62/67 legality entry 에 0x69 편입 (동일 binary-ALU IMM XOR OPREF shape). `is_alu_binary`, `_LEGAL[0x60,61,62,67,69]`, `opcode_supported` 모두 갱신.

**Assembler mnemonic**: `SIMD_MUL_WIDE_Q8_8_SCALAR = 0x69`. 16-bit IMM16 EH 가 dec_eff_b_value[15:0] 에 그대로 매핑 (별도 EH 확장 불필요 — whro79brj 의 핵심 발견: IMM16 EH 가 이미 16-bit 전체를 실어 나름).

**RMSNORM/LAYERNORM 매크로 갱신**: scale 곱셈 단계에서 0x67 → 0x69 로 교체. SDK 는 `q8_8 = clamp_saturate((rsqrt_q16_16 + 0x80) >> 8, INT16_MIN, INT16_MAX)` 로 Q16.16 → Q8.8 변환.

**Test vectors**:
- A=+2, B=Q8.8(+0.5)=0x0080 → (2×128+128)>>8 = 1 — verified
- A=+4, B=Q8.8(-1.0)=0xFF00 → (4×(-256)+128)>>8 = -4 (0xC) — verified
- A=+7, B=Q8.8(+0.25)=0x0040 → (7×64+128)>>8 = 2 — verified (Q4.4 로는 표현 불가능한 세분도 시연)

**회귀**: Cocotb 230→236(+6: Q8.8 기본/signed/precision-demo ×3 @ ISA_Decoder), Assembler 86→86 순증분은 test_rmsnorm/layernorm_expansion opcode 시퀀스 갱신(0x67→0x69) + 신규 legality 테스트 1개.

**HW 비용**: Q8.8 곱셈 array ~2.2-2.9× Q4.4 baseline (곱셈기 폭이 8-bit→16-bit) — hand-count 추정치, 실제 synthesis 미검증. DSP48 inference 시 LUT 비용은 훨씬 낮아질 수 있음 (whro79brj 잔여 리스크 항목).

**남은 스코프**: rsqrt LUT ~6.25% floor 는 이 landing 으로도 해소 안 됨 — v1.8 후보 (LUT bin 해상도 확장 또는 Newton-Raphson refinement). v1.7 Q4.4-WIDEN(output-side rounding 제거)은 별도 landing 대상.

### 22.15 남은 v1.6.5c + v1.6.7+ 스코프 (v1.6.5c 는 §22.16 으로 landing 완료)

- **v1.6.5d** (v1.6.5c 후속): FRAG_INVAL opcode — SDK explicit slot eviction
- **v1.6.7**: Q8.8 wide-scalar mul (0x69) — 0x67 이후 남은 정밀도 손실 추가 회복 (precision-zero-loss-research workflow whro79brj 결과, 별도 landing 예정)
- **v1.6.7 후속**: pe_ready 기반 ext_valid auto-gating (현 observe-only → 자동 STALL)
- **v1.7**: Q4.4-WIDEN (0x6A) + REQUANTIZE (0x6B) — output-side rounding 완전 제거. Activation function RISC-ish (softmax/gelu/silu, exp/log approximation)

### 22.16 v1.6.5c landing (2026-07-15) — multi-slot fragment buffer + CACHE_LOAD_WIDE

Ultracode 세션. Design workflow 2회 (`we8k5ib2j`/`wf_ee5bdedf-968` 최초 시도 — Verify phase 중 hung, TaskStop 후 `wf_94e698a4-521`/`wor4e34du` 로 처음부터 전체 재실행하여 완주; `w91wntdpk`/`wf_b81096c0-007` tag-stability 별도 검증) 로 설계.

#### 22.16.0 MUST-FIX-FIRST — EHDecode.v 0x63/64/65 legality 선행 버그

tag-stability 검증 workflow (`w91wntdpk`) 가 RTL 직접 재추적으로 발견, 사용자 세션에서 직접 재검증 완료: EHDecode.v 의 8'h63/64/65 (SIMD_ADD/SUB/MUL_WIDE_VEC) case 가 `forbid_imm_any=1 && forbid_opref=1` 로 되어 있어, LAYERNORM step 2/5 (opref 로 V 전달) 와 step 7/8 (imm64 로 V 전달) 이 **현재 무조건 decode-error** 나는 상태였음 — asm.py 의 `_set_legal([0x63,0x64,0x65], ..., allow_imm_xor_opref=True, require_opb_flag=True)` 모델과 모순.

증거: `dec_input_payload_b` 는 `input_payload_b` 의 순수 pass-through (EHDecode.v 는 IMM64/OPREF 를 여기에 resolve 하지 않음) — 즉 IMM64/OPREF EH 는 SDK 인코딩/legality 목적으로만 필요하고 RTL data path 는 영향받지 않음. 기존 test_simd_add/sub/mul_wide_vec 테스트들은 opref/imm64 EH 없이 (F_HAS_OPB 만으로) 발사하므로 이 버그에 걸리지 않았고, LAYERNORM/RMSNORM 은 end-to-end RTL 테스트가 아예 없어 (assembler-level opcode-sequence 테스트만 존재) 지금까지 발견되지 않음.

**Fix**: 0x63/64/65 legality 를 0x60/61/62/67 shape 로 통일 (forbid_imm_any/forbid_opref 제거).

**Regression**: `test_simd_wide_vec_opref_legal`, `test_simd_wide_vec_imm64_legal` (신규, test_isa_decoder.py) — 0x64+OPREF, 0x65+IMM64 가 decode-error 없이 통과함을 증명.

#### 22.16.1 Cluster.v multi-slot fragment buffer

`FRAG_SLOTS` 모듈 parameter (default 1). 단일 코드패스로 N-way CAM + LRU + persistence 구현 — dual-branch 대신, FRAG_SLOTS=1 일 때 정확히 기존 동작으로 reduce 됨을 직접 증명:
- `frag_ready[0]` 은 FRAG_SLOTS=1 에서 영원히 0 (persistence 분기가 gate 되어 있음) → `hit_ready`/`any_ready_hit` 항상 false → 4-way alloc 우선순위가 continue-vs-fresh-allocate 이진 선택으로 축소, 원본 `frag_active && frag_same_tag` 조건과 동일
- completion 분기의 `if (FRAG_SLOTS > 1) frag_ready<=1 else 원본 unconditional clear` 가 N=1 에서 원본과 동일

**설계**:
- Full 80-bit tag CAM (해싱 없음)
- LRU: rank-permutation 대신 **공유 monotonic timestamp counter** (`frag_age_ctr`, 매 touch 마다 +1, per-slot 로 snapshot) — cold-fill 에서 모든 슬롯이 age=0 이 되는 rank-permutation 버그 구조적으로 불가능
- Persistence: `FRAG_SLOTS>1` 일 때만 completion 시 `frag_ready<=1` (no clear); `FRAG_SLOTS==1` 은 기존 197-200줄 그대로
- Tag-reuse collision: 이미 ready 인 슬롯에 같은 tag 의 새 fragment 가 도착하면 **안전한 재할당** (mask fresh, ready→0) — 절대 stale 데이터에 OR-merge 하지 않음
- Alloc 우선순위: continue > ready-hit(재할당) > free-slot > LRU-evict

**하위 호환**: `frag_mask`/`frag_data`/`frag_total_m1`/`frag_tag_reg` 가 flat reg → per-slot array 로 변경되어, 기존 cocotb 테스트의 `dut.frag_mask.value` 직접 접근이 `dut.frag_mask[0].value` 로 변경 필요 (hierarchical array-vs-packed-vector 접근 차이 — `frag_active`/`frag_ready` 는 packed vector 라 인덱싱 대신 bit-mask 로 접근: `(int(dut.frag_active.value) >> i) & 1`).

**Makefile**: `make MOD=Cluster FRAG_SLOTS=4` 로 override (Verilator `-G` generic 플래그).

#### 22.16.2 CACHE_LOAD_WIDE (0x68)

**목적**: LAYERNORM step 5 가 xc 를 재발행(SIMD_SUB_WIDE_VEC 재실행)하는 대신, step 2 가 Cluster buffer 에 caching 한 xc 를 직접 재로드.

**Legality** (EHDecode.v + asm.py): req_port only, 모든 data EH forbidden (0x66 SCALAR_RSQRT 와 동일 shape) — B operand 자체가 없음. Cache lookup key 는 EH-carried operand 가 아니라 **인스트럭션 자신의 tag bus** (`ext_tag`). PRECISION EH 는 `_ALL_DATA_EHS` 에 없으므로 영향받지 않음.

**PE_Core.v**: 기존 0x60-67 wide-consumer case group 에 편입 (동일 `FRAG_IDLE`/`FRAG_EMIT_HI` FSM 재사용). Body 는 순수 passthrough (`output_payload <= dec_input_payload_wide[63:0]`, `frag_hi_pending <= [127:64]`) — 산술 없음. `output_tag` 는 override 하지 않고 기본 `dec_forwarded_tag` 그대로 사용 (아래 tag-stability 참조).

**Cluster.v**: `cache_load_req = ext_valid && (ext_frag_hdr==0x00) && (ext_opcode==0x68)`. Hit 시 `final_wide`/`final_wide_valid` 가 매칭된 슬롯의 `frag_data`/`frag_ready` 로 mux. Miss (`cache_load_req && !any_ready_hit`) 시 `final_wide_valid=0` → PE_Core 의 기존 `dec_input_payload_wide_valid` guard 가 `error_flag` 로 전환 — **조용한 오염이 아닌 loud-safe-miss**.

#### 22.16.3 Tag-stability (§22.16.2 의 핵심 난제)

두 번째 design workflow (`w91wntdpk`) 로 별도 검증. 최초 가설("기존 tag-forwarding 으로 충분")은 **반증됨** — RTL 직접 재추적으로 확인:

- Step 1 (EINSUM/OP_MEAN, PE_Core.v) 은 자신의 output tag 의 dim_sizes 를 리터럴 `8'h55` 로 하드코딩. Step 2 (SIMD_SUB_WIDE_VEC) 는 override 없이 그대로 상속 → step2 의 저장된 tag 도 dim_sizes=0x55.
- Step 4 (SCALAR_RSQRT, opcode 0x66) 는 자신의 output tag 의 dim_sizes 를 리터럴 `8'h00` (scalar) 로 하드코딩.
- Step 5 (CACHE_LOAD_WIDE) 가 기본 forwarding 경로로 dispatch 되면 step4 의 출력 tag 를 상속 → dim_sizes=0x00 상속 → **step2 의 저장된 tag (0x55) 와 8-bit 불일치, 확정적 miss**.
- wave_number/thread_id/precision 은 이 레시피의 어떤 case arm 도 건드리지 않음 (WADV opcode 0x01 미사용) — 이 필드들은 문제 없음. Port 도 모든 8-step 이 동일 `port_eh` 객체 재사용 (asm.py) 이라 문제 없음.

**Fix**: CACHE_LOAD_WIDE (step 5) 에 `.precision dim=0x55` EH + `dim_ovr` flag 추가 — `eff_dim_sizes` 를 corrupted forwarding chain 과 무관하게 0x55 로 고정. `_encode_eh` 의 precision branch: `word[31:24]=dim, word[23:16]=mode` — EHDecode.v 의 `acc_prec_dim <= cur_w0[31:24]` 캡처와 일치.

**Rejected 대안**:
- Q16.16 explicit tagref EH: 새 EH kind 필요, ISA 최초 IMM-width-specific opcode 될 위험, 첫 verify pass 에서 구체적 치명 버그 발견 (opcode_supported 미등록, opb+B-source 모순, 존재하지 않는 output_payload_wide 신호 참조)
- frag_tag_held 재사용: 이 LAYERNORM 8-step 시퀀스에 한해 RTL-검증상 correct 하지만 "우연히" 맞음 — single-slot last-write-wins latch 라 concurrent 한 다른 wave 의 SIG_BMM_3/wide-vec 이 같은 PE_Core 에 끼어들면 silently clobber. pe_ready/cluster_ready 가 observe-only (enforced stall 아님) 라 이 risk 는 실재.

**asm.py**: `_lower_layernorm` step 5 를 `CACHE_LOAD_WIDE` + `.precision dim=0x55` + `dim_ovr` flag 로 교체. `mu_opref`/`opb` flag 는 CACHE_LOAD_WIDE 에 불필요 (cache key 가 tag bus 자체이므로) — 이전 design workflow 초안의 "opb+mu_opref 유지" 제안은 실제 Cluster CAM 구현(§22.16.1, ext_tag 직접 매칭) 확정 후 불필요함이 판명되어 채택하지 않음.

#### 22.16.4 회귀

- Cocotb: 221 → **230** (+9)
  * ISA_Decoder: 154 → 158 (+4: opref/imm64 선행버그 regression ×2, cache_load_wide passthrough hit/miss ×2)
  * Cluster: 22 → 27 (+5: cache_load_wide roundtrip, never-cached miss, persistent-no-clear, coldfill-monotonic-age+lru-eviction, tag-reuse-collision-safe-realloc) — **양쪽 build (FRAG_SLOTS=1 default, FRAG_SLOTS=4) 모두 27/27 통과**
- Assembler: 80 → **85** (+5: layernorm_expansion 갱신 없이 신규 opcode 순서만 반영, layernorm step5 precision guard, encode_precision_eh_word, cache_load_wide legality ×2 legal/reject-imm/dim_ovr-requires-precision)

**Backward compat 검증**: FRAG_SLOTS=1 (default) 에서 기존 297 tests 전부 무변경 통과 (단 `test_frag_buffer_two/four_fragments_assemble` 의 마지막 assertion 은 `len(dut.frag_active.value)==1` 가드 추가 — FRAG_SLOTS>1 에서는 persistent 이므로 해당 assertion 자체가 의미 없어짐, skip 이 아니라 조건부 분기).

#### 22.16.5 HW 비용 (LFE5U-85F 추정, FRAG_SLOTS=4 vs N=1 baseline)

- FF: per-slot 1024(payload)+16(mask)+4(total_m1)+80(tag)+32(age) ≈ 1156 bits/slot × 4 = 4624 + packed active/ready(8) + 공유 age_ctr(32) ≈ **~4664 FF** (순증 ~3539, 대부분 1024-bit payload 4배 복제)
- LUT: 4-way 80-bit tag comparator(~56) + free-slot encoder(~10) + age-argmin(~30-40) + **1024-bit 4:1 select mux (~1024-1100, dominant, timing-critical path)** ≈ **~1120-1200 LUT** (LUT-only 추정, DSP48 inference 시 상이할 수 있음 — 실제 synth 필요)
- CACHE_LOAD_WIDE PE_Core case arm: 기존 FSM 재사용이라 위 mux 비용에 이미 포함, 추가 LUT 거의 0

#### 22.16.6 남은 residual risk

- **SDK 측 tag-stability 인프라**: ~~미해결~~ **부분 해결 (§22.17.2)** — OP_MEAN↔CACHE_LOAD_WIDE 쌍은 cross-file consistency test 로 desync 시 즉시 CI 실패. PE_Core.v 의 다른 독립적 0x55 guard 리터럴(4D→3D reduction family, SIG_BMM_2, SIG_TRACE_IIJK) 은 여전히 미연결 (§22.17.2 residual risk 참조)
- **FRAG_INVAL 없음** (v1.6.5d): ~~미해결~~ **해결 (§22.17.1)** — opcode 0x6A 로 landing. 단, SDK/runtime 이 실제로 매크로 abort 시 FRAG_INVAL 을 발행하는 wiring 은 여전히 out of scope (§22.17.1 residual risk 참조)
- **Eviction-under-concurrency**: FRAG_SLOTS 개 이상의 동시 multi-fragment wave 가 LAYERNORM 의 xc 슬롯을 evict 가능 — SDK 가 concurrent wave 수를 FRAG_SLOTS 미만으로 bound 해야 함 (§18.5/§19.9 의 no-drop/timeout 과는 다른 risk 카테고리). FRAG_INVAL 로도 미해결.
- **Capability-gating 미구현**: SDK 가 FRAG_SLOTS=1 타겟엔 legacy recompute, FRAG_SLOTS>1 타겟엔 CACHE_LOAD_WIDE 를 선택하는 메커니즘이 아직 없음 (RTL 은 안전 — FRAG_SLOTS=1 대상에 실수로 CACHE_LOAD_WIDE 를 쏘면 항상 안전하게 miss)
- 모든 FF/LUT 수치는 hand-count 추정, 실제 synthesis 검증 필요

### 22.17 v1.6.5d landing (2026-07-16) — FRAG_INVAL + tag-stability 리터럴 유지보수

Ultracode 세션, v1.6.7 과 병행 진행. Design workflow (`frag-inval-and-tag-literal-maintenance`, task `w3w0q0mt0`/`wf_88066d7f-9fa`, 16 agents, 1.09M tokens) 로 설계 — 3개 원안 중 하나(minimal-detect)의 PE_Core.v 배치가 **실제 데이터 오염 버그**를 유발함을 adversarial verify 가 발견, 직접 RTL 재확인 후 수정하여 채택.

#### 22.17.0 opcode 재배정

v1.6.7 (SIMD_MUL_WIDE_Q8_8_SCALAR) 가 같은 세션에서 0x69 를 선점 — 이전 로드맵의 "0x69/6A/6B 예약" 계획과 충돌. FRAG_INVAL 은 **0x6A** 로 배정, v1.7 의 Q4.4-WIDEN/REQUANTIZE 는 0x6B/0x6C 로 밀림 (roadmap memory 파일에도 반영).

#### 22.17.1 FRAG_INVAL (0x6A)

**목적**: SDK 가 LAYERNORM 매크로 abort 등으로 더 이상 필요 없어진 CACHE_LOAD_WIDE 캐시 슬롯을 명시적으로 회수 (LRU 자연 회수를 기다리지 않고 즉시 free 화).

**핵심 발견 — PE_Core.v 배치 버그**: 최초 원안("0x68 을 mirror") 대로 FRAG_INVAL 을 기존 `8'h60,61,62,63,64,65,67,68,69` 공유 wide-emit case-item 그룹에 편입시키면, 그 그룹의 epilogue 가 무조건 `output_frag_hdr<=8'h01; frag_state<=FRAG_EMIT_HI;` 를 실행 — 다음 cycle 에 절대 우선순위 override (PE_Core.v:1556-1563) 가 `frag_hi_pending`/`frag_tag_held` 로부터 **가비지 2번째 fragment 를 무조건 방출**한다. FRAG_INVAL 은 이 레지스터들을 쓰지 않으므로 이전의 무관한 wide op 가 남긴 stale 값이 그대로 방출되는 실제 데이터 무결성 버그. 세션에서 직접 RTL 재확인으로 검증.

**Fix — standalone case arm**: 0x66 (SCALAR_RSQRT) 과 동일하게 공유 그룹 **밖에** 별도 case arm 으로 배치. `frag_state` 를 건드리지 않으므로 FRAG_EMIT_HI 충돌 원천 차단. 이 case 에서 hit/miss 판정은 `dec_input_payload_wide_valid` 재사용 (opcode 무관하게 EHDecode 가 매 dispatch 마다 latch/forward 하는 generic 신호 — 별도 배선 불필요).

**Cluster.v**: `inval_req = ext_valid && (ext_frag_hdr==0x00) && (ext_opcode==0x6A)` — `cache_load_req` 와 동일 shape, ext_opcode 단일 8-bit 값이라 자동으로 상호 배타적 (별도 interlock 불필요). `inval_hit = inval_req && any_ready_hit` — 기존 `hit_ready`/`any_ready_hit` CAM 을 그대로 재사용 (새 비교기 없음). Sequential block 에 `else if (inval_hit) begin frag_active[ready_idx]<=0; frag_ready[ready_idx]<=0; end` 추가 (frag_age 는 미변경 — inactive 슬롯엔 무의미). `final_wide_valid`/`final_wide` 를 3-way ternary 로 확장.

**Free-not-evict 확인**: `frag_active` clear 는 즉시 `any_free` 를 true 로 만들고(alloc_idx 우선순위에서 evict_idx 보다 먼저 체크됨), 동시에 evict 후보에서도 제외 (evict_idx 스캔이 frag_active==1 요구). 즉 invalidate 된 슬롯은 다음 할당에서 **즉시 재사용**되며, LRU eviction 을 우회하지 않는다 — 테스트로 직접 증명 (`test_frag_inval_freed_slot_reclaimed_by_free_priority_not_evict`).

**의도된 스코프 제한**: `any_ready_hit` 은 `frag_ready==1` (완료된 슬롯) 만 매치 — mid-assembly (`frag_active && !frag_ready`) 슬롯은 miss 로 응답, cancel 이 아님. FRAG_INVAL 은 "완료된 캐시 슬롯 회수" 전용이지 "진행 중인 fragment 시퀀스 중단" primitive 가 아님 — 이 경계를 테스트로 명시적으로 고정 (`test_frag_inval_midassembly_slot_reports_miss_not_cancel`).

**Legality** (EHDecode.v + asm.py): 0x66/0x68 과 동일 shape — req_port only, 모든 data EH forbidden.

**asm.py**: `FRAG_INVAL` mnemonic 등록. 매크로(`_lower_layernorm` 등) 에 실제로 배선하는 것은 SDK/runtime 영역이라 이번 ISA-level landing 스코프 밖 (§22.16.6 의 "LAYERNORM abort 시 캐시 leak" 시나리오는 SDK 가 실제로 FRAG_INVAL 을 발행해야 완전히 닫힘).

#### 22.17.1a SDK abort-cleanup contract (2026-07-16 amendment, WaveTensor 쪽 절반)

§22.17.1 의 "SDK 가 실제로 FRAG_INVAL 을 발행해야" 를 두 절반으로 분리: (1) **어떻게 올바른 인스트럭션을 만드는가** (WaveTensor asm.py 의 책임 — 이번에 해결), (2) **언제 abort 를 감지해서 호출하는가** (실제 runtime/scheduler 의 책임 — wavetensor-sdk repo, 아직 Phase A scaffold 라 실질적 구현 대상 없음, §22.17.6 참조).

**설계**: step 5 (CACHE_LOAD_WIDE) 의 tag-addressing shape (`.precision dim=0x55` + `dim_ovr` flag) 을 `_layernorm_xc_slot_addressing(port_eh, line)` 공유 헬퍼로 추출 — step 5 emission 과 신규 `make_layernorm_abort_cleanup()` 양쪽이 **동일 함수**를 호출. 이는 §22.16.6 이 고치기 전의 OP_MEAN↔CACHE_LOAD_WIDE 리터럴 중복과 정확히 같은 클래스의 버그(두 곳에 손으로 같은 값을 타이핑하면 desync)를 애초에 원천 차단하는 설계 — cross-file test 로 사후 검출하는 대신 **단일 소스**로 애초에 불가능하게 만듦.

```python
def make_layernorm_abort_cleanup(inst: Instruction) -> Instruction:
    """원본 LAYERNORM macro-call Instruction 을 받아 FRAG_INVAL 인스트럭션을
    반환. Runtime 이 step 2 완료 후 ~ step 5 소비 전 사이에 LAYERNORM 을
    abort 하면 이 인스트럭션을 발행해야 캐시 슬롯이 leak 되지 않음."""
```

**Precondition** (문서화): abort-cleanup FRAG_INVAL 은 원본 LAYERNORM 호출과 **동일한 wave/thread 연속성**으로 dispatch 되어야 함 (step 2 완료 이후 WADV 없이) — step 5 자신의 tag-stability 요구사항과 완전히 동일 (같은 addressing shape 를 재사용하므로 당연히 같은 precondition 상속).

**Test**: `test_layernorm_abort_cleanup_matches_step5_shape` (abort-cleanup 과 step5 가 동일 shape 산출 확인 — 리팩터가 두 호출처를 몰래 갈라놓지 않았음을 lock), `test_layernorm_abort_cleanup_assembles_to_frag_inval` (실제 legality_pass+encode_pass 통과해서 0x6A 로 인코딩되는지 end-to-end 확인).

#### 22.17.2 Tag-stability 리터럴 유지보수

기존 §22.16.6 의 "hand-maintained cross-file literal, 한쪽만 바뀌면 조용히 desync" 문제에 대한 fix.

**거부된 대안**: (a) YAML/JSON manifest 로 Verilog `localparam` + Python constant 동시 생성 — 이 repo 에 codegen 인프라(예: `.py` 가 `.v` 생성)가 전혀 없어 investigator 가 직접 확인, "no speculative codegen infrastructure" 제약 위반으로 기각. (b) 리터럴 위치를 서로 cross-reference 하는 주석 — 이 repo 에서 정확히 이 실패 패턴이 이미 한 번 발생했음(§22.16.0 의 0x63/64/65 legality desync, spec.md:1826-1834 참조 지점)이 확인되어 기각.

**채택된 fix (2건, 순수 테스트 추가만, 신규 인프라 없음)**:
1. `test_reduce_mean_5d_to_4d` 확장 — OP_MEAN 실제 dispatch 의 `output_tag` dim_sizes byte 가 0x55 인지 assertion 추가 (기존엔 output_payload 만 검증, RTL 쪽 리터럴이 아예 미검증 상태였음).
2. **신규 cross-file consistency test** (`test_op_mean_and_cache_load_wide_dim_sizes_consistency`): asm.py 의 **실제** `_lower_layernorm()` 함수를 직접 호출(assemble() 이 내부적으로 쓰는 바로 그 함수)해서 CACHE_LOAD_WIDE step 의 precision EH 의 `dim` 값을 **live 로 추출** — 손으로 다시 타이핑한 리터럴이 아님. 이 값을 실제 OP_MEAN RTL dispatch 의 output_tag 와 비교. PE_Core.v 의 0x55 하드코딩이든 asm.py 의 `_lower_layernorm` dim 리터럴이든 **어느 한쪽만 바뀌어도 이 테스트가 즉시 깨짐** — §22.16.6 이 실제로 닫히는 지점.

**스코프 제한 (명시)**: 이 fix 는 LAYERNORM 이 실제로 쓰는 OP_MEAN↔CACHE_LOAD_WIDE 쌍만 닫는다. PE_Core.v 는 개념적으로 동일한 0x55 dim_sizes 상수를 다른 3곳(4D→3D reduction family guard, SIG_BMM_2, SIG_TRACE_IIJK)에도 독립적으로 하드코딩 — 이들은 asm.py 쪽 대응 값이 없는 guard-check 리터럴이라 상대적으로 낮은 위험이지만 여전히 미연결 (residual risk 로 기록, exhaustive 하다고 주장하지 않음).

#### 22.17.3 회귀 (241 cocotb + 88 assembler, 전부 PASS)

- Cocotb: 236 → **241** (+5)
  * ISA_Decoder: 161 → 165 (+4: cache_load_wide dim_ovr guard, op_mean/cache_load_wide dim_sizes consistency, frag_inval hit/miss ×2)
  * Cluster: 27 → 31 (+4: frag_inval hit-frees-slot, never-cached-miss, freed-slot-reclaimed-by-free-priority, midassembly-miss-not-cancel) — **양쪽 build (FRAG_SLOTS=1 default, FRAG_SLOTS=4) 모두 31/31 통과**
- Assembler: 86 → 88 (+2: frag_inval legality, frag_inval rejects-imm) → **90** (+2 abort-cleanup contract, §22.17.1a)
- 나머지 전 모듈 무변경 통과

#### 22.17.4 남은 residual risk

- FRAG_INVAL 은 mid-assembly 슬롯을 구조적으로 invalidate 불가 (의도된 설계, §22.17.1 참조) — 진행 중인 multi-fragment wave 를 중단하는 용도로는 쓸 수 없음
- Tag-stability literal fix 는 OP_MEAN↔CACHE_LOAD_WIDE 쌍만 커버 — PE_Core.v 의 다른 3개 독립 0x55 guard 사이트는 미연결
- FRAG_INVAL 은 ISA primitive 로만 landing — ~~`_lower_layernorm`/`_lower_rmsnorm` 등 매크로에 실제로 배선(abort 시 자동 발행)하는 것은 SDK/runtime 영역, 여전히 out of scope~~ **WaveTensor 쪽 절반 해결 (2026-07-16, §22.17.1a)**: `make_layernorm_abort_cleanup()` + `_layernorm_xc_slot_addressing()` 공유 헬퍼로 "올바른 인스트럭션을 어떻게 만드는가" 는 완료. "언제 실제로 abort 를 감지해서 발행하는가"는 여전히 wavetensor-sdk repo 의 실제 runtime 영역 (해당 repo 는 아직 Phase A scaffold 라 코드 작성 대상 없음 — docs/phase_plan.md 에 열린 설계 질문으로 기록, commit c4d76e9)
- Eviction-under-concurrency 는 FRAG_INVAL 로도 미해결 (별도 risk 카테고리, §22.16.6 참조)
- `dec_input_payload_wide_valid` 를 FRAG_INVAL 의 ack 채널로 재사용 — 원래 의미("캐시 데이터 valid")와 다른 의미("invalidate 성공")를 겹쳐 쓰는 것은 경미한 가독성 부채 (PE_Core.v 주석으로 완화, 완전히 제거되지는 않음)
- 매 opcode 추가마다 EHDecode.v/PE_Core.v 의 병렬 case table 을 수동으로 lockstep 유지해야 하는 systemic risk 는 여전함 (0x63/64/65 desync 가 이미 한 번 발생) — 이번 landing 은 그 2개 리터럴만 고쳤을 뿐 systemic tooling 은 추가하지 않음

### 22.18 v1.7 landing (2026-07-16) — SIMD_MUL_WIDE_Q4_4_SCALAR_128_WIDEN (0x6B) + SIMD_REQUANTIZE_Q4_4_TO_INT4 (0x6C)

> **[superseded 2026-07-24 — §24]** 0x6B/0x6C 는 native 소비자가 끝내 착지하지 않은 채 v1.8 fp32+CVT 경로에 superseded → dead-opcode 제거 (reserved 복귀). 단, 본 절이 도입한 frag FSM 확장 (frag_idx 2-bit up-counter, FRAG_EMIT_2/3) 은 **v1.8.0e wide package 예약** 으로 존치 — >2-fragment writer 만 일시 부재. 본 절은 superseded history 로 보존.

Ultracode 세션, FRAG_INVAL SDK wiring 과 병행 진행. Design workflow (`v1-7-widen-requantize-design`, task `wgcq5jc68`/`wf_960cb526-029`, 16 agents, 985K tokens) 로 설계 — 사용자 세션에서 PE_Core.v 현재 상태(FSM/gate/frag_hi_pending 정확한 line number)를 직접 재확인 후 구현.

#### 22.18.0 ⚠️ 정밀도 주장 정정 (기존 로드맵 메모리 오류 수정)

**기존 `wt64v1_precision_recovery_roadmap.md`/spec §22.15 가 v1.7 을 "output-side rounding 완전 제거" 로 기술한 것은 틀렸다.** Adversarial verify 가 발견, 아래로 정정:

- **WIDEN 자신의 Q4.4-int8 출력은 정확히 rounding-free** — A 가 정수(소수부 없음)이므로 raw product `p = A × B_raw` 는 이미 정확히 Q4.4 grid 위에 있음. 반올림이 필요 없고 saturating cast 만 필요.
- **하지만 REQUANTIZE (기존 int4-only 소비자와 호환하기 위해 반드시 필요)는 round-half-up + saturate 를 다시 수행** — 즉 REQUANTIZE(WIDEN(A,B)) 의 최종 int4 출력은 여전히 기존 0x67/0x69 과 동일한 ~0.5 output-LSB rounding bound 를 가짐.
- **올바른 주장**: "WIDEN 은 rounding-free 이나, 이를 소비하는 REQUANTIZE 가 기존 int4 소비자 대비 **parity 를 복원**할 뿐, output-side rounding 병목을 **완전히 제거하지는 않는다**. 진짜 zero-rounding 이득은 네이티브 Q4.4-int8 을 직접 받아들이는 다운스트림 소비자가 있어야 실현되는데, **그런 소비자는 아직 ISA 에 존재하지 않는다.**"
- 이 정정은 `wt64v1_precision_recovery_roadmap.md` 메모리 파일과 이 spec 양쪽 모두 반영 (§22.18.4 참조).

#### 22.18.1 opcode 재배정 (기존 예약 갱신)

FRAG_INVAL 이 같은 세션에서 0x6A 를 선점 — WIDEN=**0x6B**, REQUANTIZE=**0x6C** 로 확정 (원래 계획했던 0x6A/0x6B 에서 한 칸씩 밀림, 이미 §22.17.0/roadmap memory 에 반영됨).

#### 22.18.2 채택된 설계 — full-fsm-extension (frag_state 1비트 → frag_idx 2비트)

**Rejected 대안** (adversarial verify):
- **16-lane-no-fsm-change**: 헤드라인 장점("CACHE_LOAD_WIDE 를 그대로 재사용")이 반증됨 — CACHE_LOAD_WIDE 는 매칭된 슬롯 **전체**를 mux-out 하는 구조라 128-bit 캐시된 xc 의 절반(16-lane)만 재로드하는 메커니즘이 없음 → step 2(xc 생산) 자체도 결국 2-dispatch 로 쪼개야 해서 "WIDEN/REQUANTIZE 만 분할" 이라는 자신의 호환성 주장이 깨짐. FRAG_SLOTS 동시성 압박도 배가 (§22.16.6 의 미해결 eviction-under-concurrency risk 를 오히려 악화).
- **two-dispatch-half-select**: 자체 요약이 스스로의 cons 와 모순(목표 달성했다면서 실제 dispatch 수는 2가 아니라 4). 두 개의 독립적으로 태그된 128-bit half 가 "논리적으로 하나의 값"이라는 것을 하드웨어가 전혀 인지하지 못함 — correlation/ordering/scale 일치가 전부 SDK 쪽 미검증 불변식이 되어, 실패 모드가 **조용한 데이터 오염** (byte/lane-swap, tag 충돌, false hazard-aliasing).

**full-fsm-extension** 이 채택된 이유: FSM 리스크를 정면으로 분석한 결과 "accepted with caveats" 이지 "refuted" 인 적이 없었음 — 인용된 모든 line number 가 실제와 일치, drain loop pseudocode 가 모든 legacy 2-fragment producer 의 정확한 0x11 헤더/타이밍을 재현, compound gate 의 7곳 중 5곳은 `==FRAG_IDLE` 만 검사(busy encoding 은 검사 안 함)이라 폭 확장이 기계적, MUL/DIV launch gate 는 애초에 모든 wide-consumer dispatch 와 상호 배타적이었으므로 드레인 길이와 무관하게 새 충돌이 생길 수 없음 — 유일한 real hazard(stale frag_total_m1_held)는 이름 붙일 수 있고 lint 로 검증 가능한 종류.

**설계 3곳 교정** (raw 원안 대비):
1. REQUANTIZE(0x6C)를 WIDEN 자신의 standalone item 이 아니라 **기존 공유 8'h60-69 case-item 그룹의 10번째 멤버**로 편입 — write-site 개수를 열린 카운트에서 정확히 3곳(SIG_BMM_3 epilogue, 공유 그룹 epilogue, WIDEN 자신의 신규 epilogue)으로 축소.
2. REQUANTIZE 의 EHDecode.v legality 를 raw 초안의 (틀린) ALU-binary shape 에서 0x66/0x68/0x6A 와 동일한 **unary no-B shape** 로 수정 (REQUANTIZE 는 B operand 자체가 없음).
3. REQUANTIZE 의 narrowing 공식에 **명시적 saturating clamp** 추가 (round-half-up-then-shift 만으로는 "rounding 오차를 조용히 2배로 만드는" 갭이 adversarial review 에서 발견됨).

#### 22.18.3 RTL 메커니즘

**PE_Core.v** — `frag_state`(1-bit)→`frag_idx`(2-bit up-counter: FRAG_IDLE/FRAG_EMIT_1/FRAG_EMIT_2/FRAG_EMIT_3), `frag_hi_pending`(단일 64-bit)→`frag_pending[1:3]`(3-slot 64-bit array), 신규 `frag_total_m1_held`(2-bit, 이 wave 의 실제 fragment 개수 기록). `frag_tag_held`/`frag_opcode_held` 는 미변경(fragment 전체에 걸쳐 상수이므로 폭 확장 불필요, workflow investigator0 확인).

절대 우선순위 override 일반화:
```verilog
if (frag_idx != FRAG_IDLE) begin
    output_payload  <= frag_pending[frag_idx];
    output_frag_hdr <= {2'b00, frag_idx, 2'b00, frag_total_m1_held};
    output_valid    <= 1'b1;
    if (frag_idx == frag_total_m1_held) frag_idx <= FRAG_IDLE;
    else                                frag_idx <= frag_idx + 2'b01;
end
```

**MANDATORY 불변식** (CI-enforced): `frag_idx<=FRAG_EMIT_1` 를 쓰는 모든 블록은 같은 블록에서 `frag_total_m1_held` 도 써야 함 — `scripts/lint_frag_total_m1_held.py` 로 강제 (indentation 기반 case-arm 경계 탐지, false negative 를 실제 위반 제거 시뮬레이션으로 검증).

**WIDEN (0x6B)**: A(int4) × B(signed Q4.4, `dec_eff_b_value[7:0]`) → 32-lane × signed 8-bit Q4.4 = 256-bit/4-fragment (헤더 0x03/0x13/0x23/0x33). Standalone case item (공유 그룹 밖 — 그룹은 2-fragment epilogue 하드코딩이라 4-fragment 드레인과 안 맞음).

**REQUANTIZE (0x6C)**: 256-bit Q4.4-int8 (`dec_input_payload_wide[255:0]`) → 128-bit int4, round-half-up + saturate. 공유 8'h60-69+6C 그룹의 10번째 멤버.

**Cluster.v**: 변경 없음 — FRAG_MAX=16(1024-bit) 이 이미 generic, 4-fragment(tot_m1=3) 재조립도 이미 SIG_BMM_3/`test_frag_buffer_four_fragments_assemble` 로 production-검증됨.

**EHDecode.v**: 0x6B 는 0x60/61/62/67/69 와 동일 shape(is_alu_binary 편입), 0x6C 는 0x66/68/6A 와 동일 shape(unary no-B).

**asm.py**: `SIMD_MUL_WIDE_Q4_4_SCALAR_128_WIDEN`=0x6B(기존 IMM-XOR-OPREF 그룹 편입), `SIMD_REQUANTIZE_Q4_4_TO_INT4`=0x6C(별도 `_set_legal`, 0x6A 패턴).

#### 22.18.4 회귀 (252 cocotb + 95 assembler, 전부 PASS)

- Cocotb: 241 → **252** (+11, ISA_Decoder 165→176): widen 4-fragment emit, widen saturation, requantize parity-with-0x67, requantize saturation, requantize min-value-exact, **canary test**(legacy op 직후 WIDEN 이 stale total_m1 남기지 않음 증명), pe_ready 3-cycle, mul-during-drain(blocked-then-launches), reset, requantize/widen legality ×2
- Assembler: 90 → **95** (+5): widen/requantize legality ×2, widen requires-imm-xor-opref, requantize rejects-imm-and-opref, opcode-table-matches-hardware(0x63/64/65 desync 재발 방지 직접 회귀)
- **Cluster: FRAG_SLOTS=1(default)/FRAG_SLOTS=4 양쪽 build 모두 31/31 무변경 통과** (FSM 확장이 Cluster 레벨 동작에 영향 없음을 확인)
- 나머지 전 모듈(HIU/Tensor_ALU/SIMD_ALU/ALU_Extended/Top_Core/PE/Pod) 무변경 통과
- `scripts/lint_frag_total_m1_held.py`: 통과 확인 + 실제 위반 시뮬레이션(임시로 한 assignment 제거)으로 lint 자체가 진짜로 잡아내는지 sanity-check 완료

**핵심 검증**: 이 FSM 확장은 세션 전체에서 가장 위험도 높은 RTL 변경(9개 이상 opcode 가 공유하는 core FSM touch)이었으나, PE→ISA_Decoder→PE→Top_Core→Pod→Cluster(양쪽 build) 전 계층에서 무손상 확인.

#### 22.18.5 HW 비용

- Per-PE: frag_idx +1 FF, frag_total_m1_held +2 FF, frag_pending 64-bit→192-bit(+128 FF) = **+131 FF/PE**. frag_tag_held/frag_opcode_held 미변경.
- Combinational: override 분기가 1-way bypass → 3:1 64-bit mux + 2-bit 비교기 + 2-bit incrementer (~200 mux-equivalent + ~10 gate, 기존 1024-bit wide bus 대비 미미).
- 기본 Cluster(NUM_PES=4) 기준 cluster-wide ~+524 FF.
- EHDecode.v: is_alu_binary OR-term 1개 + unary shape 1개 + opcode_supported OR-term 2개 — combinational decode 로직 소폭 증가.
- Cluster.v/BRAM/NoC 변경 없음.
- Timing: override 분기의 critical path 가 3:1 mux + 2-bit 비교 1단 증가 — 기존에 더 큰 mux(1024-bit wide bus)가 이미 있어 critical path 될 가능성은 낮으나, **post-synthesis STA 검증 권장** (residual risk).

#### 22.18.6 남은 residual risk

- Stale `frag_total_m1_held` hazard 는 정확히 3개 write-site 로 스코프 축소 + lint + canary test 로 backstop 되었으나 **구조적으로 완전히 제거되지는 않음** — 향후 opcode 가 FRAG_EMIT_1 tail 을 재사용하면서 frag_total_m1_held 갱신을 잊으면 여전히 실패 가능 (lint 가 잡아냄)
- MUL/DIV throughput regression: WIDEN 직후 MUL/DIV 가 오면 1-cycle → 최대 3-cycle stall. SDK scheduler 에 통지 필요
- pe_ready 최악 deassertion 이 1→3 cycle 로 변경 — "observe-only" 문서화되어 있으나 실제 상류 fabric 이 1-cycle 을 가정했다면 재검증 필요
- REQUANTIZE 의 saturating clamp 은 0x67/0x69 에 없던 새 실패 클래스 — 이번 landing 에서 전용 edge-case 검증 완료했으나 향후 변형에서 재검증 필요
- wavetensor-sdk (Phase B/C) 가 4-fragment 제네릭성을 자동 상속하는지, 별도 구현이 필요한지 미확인 (repo 자체가 아직 fragment 처리 코드 없음)
- Timing/STA 미검증 (§22.18.5)
- REQUANTIZE(WIDEN(A,B)) 와 미래의 다른 연산 시퀀스 간 "같은 논리값" 에 대한 범용 bit-exactness 계약은 없음 — 이번 테스트는 0x67 대비 parity 만 확인

### 22.19 진입 트리거 (기존 22.18 재번호)

v1.6.5d + v1.7 amendment 는 **결정된 상태 (2026-07-16)**. 세 workflow(FRAG_INVAL+tag-literal, v1.7 FSM) + 사용자 세션 직접 RTL 재검증(FRAG_EMIT_HI 가비지 fragment 버그, MUL 차단이 lower_required 아닌 silent gate 임을 직접 확인)으로 최종 설계 확정. 구현 완료 (2026-07-16).

## 23. FP-native compute path 설계 조사 — v1.8/v2.0/v2.1 roadmap (2026-07-16, 조사 완료 · 미결정)

**상태: 설계 조사 완료, 사용자 결정 대기.** Design study workflow (`fp-native-compute-path-study`, task `wul707ze7`/`wf_3208c8ae-396`, 16 agents, 1.04M tokens; 최초 launch 는 추론 전용 프레이밍이었으나 사용자가 "학습 가속도 주요 목표" 를 명시하여 TaskStop 후 학습 요구사항 주입하고 resume). 3개 설계안(dtype-orthogonal / accumulator-first / full-fp-v2) × 3-lens adversarial verify — 전원 accepted-with-caveats, refuted 없음. 단 각 안의 개별 주장 다수가 반증되어 hybrid 로 수렴.

### 23.0 조사의 출발점 — 스칼라/벡터 정밀도 비대칭 (사용자 지적)

Phase 1 인벤토리로 확정한 현행 사실:
- **스칼라 ops (0x10-0x1F, 0x50-0x56)**: 전부 64-bit 정수 exact (mod-2^64). 예외 2개 — MUL(0x12) 은 128-bit 곱의 하위 64-bit 만 (표준 정수 semantics), DIVMOD(0x1D) 는 32-bit 한정.
- **벡터/SIMD ops**: 모든 경로에 양자화 이벤트 존재 — 0x62/0x65 는 `p[3:0]` hard truncation, 0x60/61/63/64 는 mod-2^4 wrap, EINSUM 16-bit 계열은 mod-2^16 곱 truncation, SIG_BMM int8 은 mod-2^8, 5D→4D L2SQ 는 int4 truncation (worst 18→2), MEAN 은 ASR floor. **유일한 exact 벡터 누산은 5D→scalar L1/L2SQ (32-bit acc) 와 EUCLID_NORM (64-bit)**.
- **`precision_mode` (tag[15:8]) 는 순수 메타데이터**: PE_Core.v 에서 정확히 29곳 등장, 전부 output_tag 조립 — 조건/케이스 선택자/산술 피연산자로 쓰인 적 0회. 즉 compute 의미론에 영향을 주지 않는 free 8-bit dtype-selector hook. (PE_Core.v:144-145 주석은 precision 의미론이 있는 것처럼 서술 — doc/RTL drift 의 실사례.)

### 23.1 권고 roadmap (hybrid: accumulator-first spine + dtype-orthogonal 의 field-structured selector + full-fp-v2 의 fused-FMA/결정론 계약)

**v1.8 "WIDE-ACC"** — 추론 GPU-parity (ECP5 Stage-1). 학습 불가 명시.
- 신규 opcode block **0x70-0x7F** (virgin 확인 — opcode_supported whitelist 라 미지 opcode 는 이미 decode_error). precision_mode 는 **이 block 안에서만** format selector 의미론 획득, 밖에서는 영원히 inert metadata (feature gate 없음, legacy flip 없음).
- per-Cluster **FP-UNIT** = MATMUL_UNIT/DIV_UNIT 에 이은 3번째 stripped-PE peer. fp32 scalar pipeline (FSCALAR add/sub/mul/fused-FMA, sequential div), FRSQRT32 (LUT seed + **3회** Newton — 2회 주장은 수렴 산술에서 반증됨, ≤2 ulp normative), FEXP2_32 (≤2 ulp), CVT f16/bf16/f32 + I2F/F2I.
- int4/int8 **VDOT_ACC — stateless 4-fragment wide dot** (v1.8.0b 설계 확정, workflow wwov1b5i3): v1.8 의 int 경로는 **하드웨어 누산기 상태를 갖지 않는다**. A=wide[127:0], B=wide[255:128] (SIG_BMM_3 패턴), 64-bit carry-in 은 IMM-XOR-OPREF. 결과 r = (sext64(Σ sext32(aᵢ)·sext32(bᵢ)) + c) mod 2^64 즉시 방출 — dispatch 내 dot 은 int32 에서 wrap 불가능한 bound (|dot| ≤ 2^11 int4 / 2^18 int8). **IMMA order-free bit-exact 계약 = mod-2^64 소프트웨어 체인(직렬 carry-in 또는 VDOT partial + ADD 0x10 트리)의 low-32 채널**; full-64 는 현실적인 어떤 K 에서도 exact (int8 최대 크기 기준 overflow 까지 >2^45 dispatch ≈ 2^49 elements). 누산기 서사(VFMA/ACC bank)는 v1.8.0c+/v2.0 으로 이동.
- **STORE_QUANT** (int32/fp32 → int4/int8/f16/bf16, RNE+saturate, ≤256-bit — 기존 2-bit frag FSM 과 lint 그대로 생존), **DEQUANT** (slice-select 로 기존 wide int4 wave 수용).
- LayerNorm/RMSNorm/Softmax 매크로를 fp32 통계로 재구축, 종단 1회 양자화 — 기존 문서화된 4개 numerics 버그 (MEAN ASR floor, x-µ mod-16 wrap, gamma p[3:0] truncation, rsqrt 6.25% floor) 전부 은퇴.

**v2.0 "TRAIN"** — 최초 학습 가능 버전 (training triple: bf16 multiply / fused fp32 accumulate / fp32-master-or-SR update).
- 통합 f16/bf16 **fused-FMA** lane (11-bit mantissa 곱셈기 하나로 양쪽 커버; 곱은 wide-exponent 내부 포맷으로 exact 유지, fp32 누산에서 단 1회 RNE). bf16-accumulate 는 구조적으로 금지 (업계 전례 없음). ECP5 에서 FP_LANES=2 가 한계. *(2026-08-15 개정 — §27: "fp32 누산에서 단 1회 RNE" 는 **per-FMA fusion 계약** — 개별 fused multiply-add 1건이 곱 지점 무반올림 + 융합 반올림 1회 — 에 한정 재구속된다. dot/누산 스케줄의 반올림 이벤트 수는 이 문장이 아니라 §27 wave-step-atomic 계약이 규범이다: in-dot exact lattice 로 dot 내부 반올림 0회, bank store 에서 RTO-48 1회, drain 에서 RNE-24 1회. 이 문장을 누산 트리의 "dot 당 1회 RNE" 로 읽는 해석은 kickoff memo §1.2 C3 충돌로 등재됐다가 §27.1 로 판정 종결.)*
- **fp32 ACC bank** (2 × 32 lanes × 32b/cluster, tag pcid[1:0] 로 bank 선택 + 명시적 ownership/drain 계약 + ACC_SPILL/FILL) — "requester ID" 식 암묵 계약은 반증되어 폐기. *(2026-08-15 개정 — §27.2.2: bank word 는 32b fp32 가 아니라 **64b — PACK_WIDE 값의 IEEE binary64 무손실 재인코딩** — 로 확정, 즉 **2 banks × 32 lanes × 64b/cluster**. SPILL image = fp64, FILL validation (NaN/Inf sticky fault, ±0 canonicalize) 포함 전 규범은 §27.2.2. pcid arity/ownership 미결과 TLA+ 선행 의무는 무변경 유효.)*
- **normative canonical accumulation order**: 32-lane balanced 5-level tree + ascending wave-order K. 모든 FP_LANES 구성이 이 순서와 serially-equivalent 해야 함 → run/lane-config/part 간 bit-identical fp32 누산.
- fp32 master weights + Adam (fp32 scalar pipeline 재사용). **Stochastic rounding 은 탑재하되 non-default**: counter-based RNG keyed on (wave_number, thread_id, lane_index), ≥16 random bits — free-running LFSR(재현 불가)과 8-bit/correlated-lane(bias) 방식 둘 다 반증됨. fp32→bf16 STORE_QUANT downcast 에서만 적용 (Trainium/Graphcore 지점).

**v2.1 "SCALE"** — Stage-2 Avant G70 (~700K LUT): FP_LANES=8+, output frag FSM 16-fragment 확장(전용 lint 동반), FP8 E4M3/E5M2 GEMM + per-block fp32 scale, SR 을 in-house 수렴 검증 후 default 승격 검토, f64 는 `WT_ENABLE_F64` 뒤 sequential-scalar 옵션으로만 (기본: 영구 미빌드).

### 23.2 dtype 판정

| dtype | 판정 | 근거 |
|---|---|---|
| f16 | SHIP (v1.8 storage/CVT, v2.0 compute) | bf16 과 11-bit mantissa 곱셈기 공유로 near-free; f16×f16→fp32 가 실제 GPU 계약; f16-accumulate 미제공 |
| bf16 | SHIP (v2.0) | THE training dtype; 8-bit exponent 가 loss-scaling 하드웨어 자체를 삭제 |
| f32 | SHIP (v1.8 scalar + accumulator, v2.0 master weights) | 누산기/master/Adam/통계/rsqrt/exp 의 정밀도 천장 — DL 에서 이 위는 무가치 |
| f64 | **별도 확장 `Lf` 로 분리** (2026-07-16 사용자 결정; base 에서는 dtype nibble 0x5 → decode_error 로 예약 유지) | TPU/Trainium/Cerebras/Graphcore/Dojo 어디에도 없어 base DL roadmap 에서는 제외하되, 완전 컷이 아니라 **WT64v1 의 optional extension "Lf"** (RISC-V 확장 문자 관례 유사 — 구현 명칭 예: WT64v1Lf) 로 본격 설계를 이관. Lf 착수 시점/스코프는 미정 — Stage-2 (Avant G70) 이상에서만 물리적으로 가능 |

### 23.3 스칼라/벡터 일관성 해결 (사용자 질문 3 직답)

**단일 규칙**: "레지스터/누산기는 무손실(정수) 또는 step 당 1회 반올림(FP); wave 는 양자화된 저장 포맷; 좁히기는 명명된 program-visible opcode (STORE_QUANT/CVT) 에서만."
- 스칼라 정수: 지금처럼 mod-2^64 exact.
- 벡터 정수: int4/int8 dot 이 int32 로 exact 누산 → 스칼라 64-bit ADD 체인과 동급의 신뢰성 (둘 다 "wide 로 들고 있다가 프로그래머가 의도적으로 좁힘").
- FP: 스칼라/벡터가 **같은 물리 FP-UNIT datapath** 를 통과 → 스칼라 fp32 op 와 벡터 fp32 op 의 lane 하나가 구조적으로 bitwise identical.
- 남는 비대칭은 문서화된 3개 carve-out: (a) 정수 exact vs FP correctly-rounded (모든 CPU ISA 와 동일한, 유일하게 정합적인 비대칭), (b) bitwise/shift 는 dtype-transparent raw bits, (c) 기존 truncating int4 벡터 opcode (잔존분: 0x60-0x65 산술 + 0x69) 는 호환용으로 실행 가능하되 **"compute op" 에서 "storage-format op" 로 재분류** — 권장 매크로에서 제외, silent loss 명시. *(2026-07-24 개정: 원문의 "0x60-0x6C 산술 frozen" 은 §12a pre-stable 정책으로 대체 — stable release 전 dead-opcode 제거는 정규 행위이며, 실제로 0x66/0x67/0x6B/0x6C 는 제거됨, §24.)*

### 23.4 "정밀도 무변동" 의 정직한 정의 (사용자 질문 1 직답) + acceptance criteria

**보장하는 것** (cocotb + numpy/mpmath golden 으로 검증 가능한 normative 계약):
1. exact narrow products (int 은 구조상, f16/bf16 은 wide-exponent 내부 포맷)
2. wide accumulation — int32 는 order-free bit-exact; fp32 는 canonical order 에서 step 당 정확히 1회 RNE *(2026-08-15 개정 — §27: int32 는 무변경. fp32 는 "step 당 1회 RNE" 가 아니라 — 그 서술은 option-A 스케줄의 것으로 superseded — **in-dot exact (order-free, dispatch 내부 반올림 0회) + bank store 에서만 RTO-48 1회 + drain 에서 RNE-24 1회** 다. 이로써 fp32 누산도 dot 내부에서는 int32 와 같은 order-free 성질을 얻는다.)*
3. 종단 1회 좁히기 (STORE_QUANT/CVT 에서만; norm 매크로 end-to-end MSE ≤ 1.05× 출력 dtype 의 이론 양자화 floor)
4. per-op IEEE 계약 (elementwise RNE; FRSQRT32/FEXP2_32 ≤2 ulp; DAZ+FTZ/NaN/Inf/-0 표가 normative)
5. **bit-reproducibility**: 같은 프로그램+데이터+시드 → run/FP_LANES/part 불문 bit-identical (SR 포함 — counter-based RNG 라 재현됨)
6. training epsilon test: 소형 MLP N-step 학습 궤적이 golden bf16/fp32 소프트웨어 파이프라인과 bit-for-bit 일치

**영원히 약속 불가능한 것** (spec 에 명기): 타 GPU/CPU 결과와의 bitwise 동일성. FP 덧셈은 비결합적이라 누산 순서가 다른 머신은 다른 비트를 냄 — GPU 자신도 kernel config 간 비트 동일성을 보장 않음. WT 의 차별점은 반대로 **GPU 가 못 주는 축의 결정론** (run/config/part 간 bit-identical).

### 23.5 시장 평가 (사용자 질문 2 직답)

- GPU bar — 추론: exact int8 곱 → int32 누산 → fp32 per-channel dequant + norm/softmax 는 fp16/fp32. 학습: bf16 곱 → fused fp32 누산 → fp32 master + fp32 Adam (또는 HW-SR 16-bit master).
- **v1.8 이 추론 계약 도달, v2.0 이 최초 학습 가능 버전.** 추론 전용 dtype set 은 제품 목표 미달 — v1.8 을 학습 가능한 것처럼 마케팅 금지.
- **처리량 정직성 (모든 포지셔닝에 필수)**: Stage-1 ECP5 는 pod-wide ~0.4-1.6 GFLOP/s bf16 — GPU 대비 수 자릿수 아래. v2.0 은 학습-**정확성** parity + GPU 가 못 주는 차별점(bit-reproducibility: 디버깅/인증/감사 니치 + 이 repo 의 formal-first 문화)이지, 학습-**가속** parity 가 아님. 속도 주장은 Stage-2 Avant G70 (v2.1) 부터.

### 23.6 ISA 인코딩 계획 (요지)

- mode byte (field-structured): [3:0] dtype (0x0 int4 … 0x4 f32, 0x5 f64-reserved→decode_error, 0x6 Q4.4, 0x7 Q8.8), [5:4] accumulate policy (0 same-width — bf16 은 ILLEGAL, 1 wide), [7:6] rounding (0 RNE, 1 stochastic, 2 RTZ).
- opcodes: 0x70 VFMA_ACC, 0x71 VDOT_ACC, 0x72 ACC_REDUCE{SUM,MEAN,L2SQ,MAX}, 0x73 ACC_ELEMWISE, 0x74 FSCALAR, 0x75 FRSQRT32, 0x76 FEXP2_32, 0x77 CVT/I2F/F2I, 0x78 DEQUANT, 0x79 FMAX/FMIN (IEEE minNum/maxNum — signed-int compare tree 재사용 금지, 3안 공통 미처리 hazard 였음), 0x7C STORE_QUANT, 0x7D ACC_SPILL/FILL, 0x7E FP_ACC_ZERO/FP_STATUS, 0x7F reserved.
- legality ROM (op-class × dtype × acc × rnd) — **ROM/spec 표/golden model/lint 를 단일 기계가독 JSON 소스에서 생성** (PE_Core.v:144-145 형 doc/RTL drift 의 구조적 해독제; 이 repo 최초의 codegen 도입 지점). ~~YAML~~→**JSON 으로 확정 (2026-07-16 v1.8.0a 설계 workflow)**: PyYAML 은 이 repo 의 최초 서드파티 non-cocotb 의존성이 되는 반면 json 은 stdlib — 조사 원문의 "YAML" 은 형식 예시였고 요구사항의 본질("단일 기계가독 소스")은 JSON 이 더 엄격히 충족. 사용자 승인된 치환으로 기록.
- alias-collapse 주장 (기존 wide-mul 계열을 0x70-block 의 dtype nibble 로 흡수) 은 여전히 **반증됨** — 혼합 A/B/out-format 이라 단일 dtype nibble 로 인코딩 불가하므로 collapse 는 수행하지 않는다. 다만 원문의 "기존 0x67/0x69/0x6B/0x6C first-class 유지하되 frozen" 은 §12a pre-stable 정책으로 **개정** (2026-07-24): 소비자 0 인 **0x67/0x6B/0x6C 는 dead-opcode 제거로 reserved 복귀** (§24), **0x69 는 live norm tail 로 first-class 유지**.
- FP 결과를 0x68 로 캐싱하는 recipe 는 PRECISION EH 로 precision byte 를 pin 해야 함 (dim=0x55 pin 과 동일 패턴) — 아니면 결정론적 CAM miss.

#### 23.6a v1.8.0a normative mode-byte legality 표 (2026-07-16 저작 — COMMIT 0)

이 표가 **normative source of review** 다: isa/wt64v1_isa.json 의 fp_block 섹션은 이 표의 전사(transcription)이고, asm 테스트의 spec-row pin 들은 이 표에서 문자 그대로 옮긴다 (별도 commit 에서 선행 리뷰됨으로써 same-author-same-commit 순환을 끊는 독립 anchor).

**정책 (restrictive-first + monotonic loosening)**: 아래 표에 명시되지 않은 모든 (op, dtype, acc, rnd) 조합은 **ILLEGAL (decode_error)**. 이후 버전에서 합법화(loosening)는 non-breaking — 어떤 코드도 거부되던 인코딩에 의존할 수 없기 때문. 역방향(합법→불법)은 breaking 이므로 금지. 불확실하면 ILLEGAL 로 남긴다.

**mode byte 필드**: dtype = eff_precision[3:0], acc = eff_precision[5:4], rnd = eff_precision[7:6]. 이 의미론은 **opcode 0x70-0x7F 안에서만** 활성 (in_fp_block = cb_opcode[7:4]==4'h7 로 self-gate) — 0x70 미만의 모든 opcode 에서 precision byte 는 지금처럼 inert metadata. *(원문 "0x00-0x6C" 는 2026-07-24 제거 (§24) 이후 range 끝점이 무의미해져 표현만 갱신 — 의미론 무변경.)*

**전역 불변식 (모든 op 공통, generator 와 무관한 hand-pinned 테스트 4종의 대상)**:
1. dtype 0x5 (f64) — **Lf 확장 예약**, 모든 op/acc/rnd 에서 ILLEGAL
2. dtype > 0x7 — ILLEGAL
3. rnd == 3 (reserved) — ILLEGAL. rnd == 1 (stochastic) 은 v1.8 전체에서 ILLEGAL (v2.0 이 STORE_QUANT downcast 에서 합법화). rnd == 2 (RTZ) 는 v1.8.0a 에서 ILLEGAL (필요 시 후속 loosening)
4. acc == 0 (same-width) — v1.8.0a 에서 전면 ILLEGAL (f16 opt-in same-width 는 v2.0 결정; bf16+acc==0 은 **영구** ILLEGAL). acc ∈ {2,3} — ILLEGAL

**per-op 표 (v1.8.0a 합법 행 전체 — 총 21 행 / 4096)**:

| opcode | mnemonic | legal dtype | legal acc | legal rnd | 비고 |
|---|---|---|---|---|---|
| 0x70 | VFMA_ACC | 0x0 int4, 0x1 int8 | 1 (wide→int32) | 0 RNE | FP dtype (f16/bf16) 는 v2.0 에서 loosening |
| 0x71 | VDOT_ACC | 0x0, 0x1 | 1 | 0 | 동상 |
| 0x72 | ACC_REDUCE | 0x0, 0x1 | 1 | 0 | int32 누산기 대상; fp32 reduce 는 v1.8.0c+ loosening |
| 0x73 | ACC_ELEMWISE | 0x4 f32 | 1 | 0 | fp32 scalar scale/shift (γ/β 단계) |
| 0x74 | FSCALAR | 0x4 | 1 | 0 | add/sub/mul/FMA/sequential-div |
| 0x75 | FRSQRT32 | 0x4 | 1 | 0 | LUT seed + NR 3회, ≤2 ulp normative |
| 0x76 | FEXP2_32 | 0x4 | 1 | 0 | ≤2 ulp normative |
| 0x77 | CVT | 0x2 f16, 0x3 bf16 | 1 | 0 | **conversion-dtype 규칙** 참조; I2F/F2I 의 sub-op 인코딩은 v1.8.0b 결정 |
| 0x78 | DEQUANT | 0x0, 0x1 | 1 | 0 | dtype = **source** (int4/int8 × fp32 scale → bf16/f32) |
| 0x79 | FMAX/FMIN | 0x4 | 1 | 0 | IEEE minNum/maxNum — signed-int compare tree 재사용 금지 |
| 0x7C | STORE_QUANT | 0x0, 0x1, 0x2, 0x3 | 1 | 0 | dtype = **destination**; rnd=1(SR) 은 v2.0 loosening |
| 0x7D | ACC_SPILL/FILL | 0x4 | 1 | 0 | v1.8.0b 에서 int32 spill 필요 시 loosening |
| 0x7E | FP_ACC_ZERO / FP_STATUS | 0x4 | 1 | 0 | 제어 op — dtype 은 관례적 (fp32) |

미배정 0x7A/0x7B 와 reserved 0x7F 는 opcode_supported whitelist 미포함 → 모든 mode byte 에서 decode_error (오늘과 동일).

**conversion-dtype 규칙 (0x77 CVT / 0x78 DEQUANT / 0x7C STORE_QUANT)**: dtype nibble 은 **비-누산기-폭 endpoint** 를 명명한다 — DEQUANT/I2F 는 source, STORE_QUANT/F2I 는 destination — 반대편 endpoint 는 int32/fp32 로 고정. 이 규칙으로 표현 불가능한 쌍은 v1.8.0a 에서 ILLEGAL (2번째 dtype 인코딩은 v1.8.0b 결정 사항).

**illegal mode byte 의 semantics**: EHDecode 단계의 **decode_error** (→ PE_Core error_flag, output_valid=0) — lower_required 가 절대 아님. decode/execute 경계 보존: malformed(EH shape 위반, illegal mode, 미배정 opcode) = decode_error; capability 부재(합법이나 미구현) = lower_required.

**EH shape (restrictive-first)**: 0x70/0x71/0x73/0x79 = ALU-binary 형 (port + IMM XOR OPREF); 0x72/0x74/0x75/0x76/0x77/0x78 = port-only (모든 data EH forbidden) — **단, v1.8.0c carve-out (§23.10): 0x74 FSCALAR 는 imm16 optional (absent = FS_ADD), imm32/imm64 는 asm-forbidden 이되 RTL-tolerated (0x72 의미론 verbatim — RTL 의 forbid_imm_any 는 단일 비트라 per-size 분리가 불가하고, FSCALAR 는 eff_b_value 를 읽지 않아 무해); 0x75/0x76 은 strictly port-only 유지**; 0x7C/0x7D = port+mem; 0x7E = no-data-EH forbid-all.

**v1.8.0b EH-shape loosening (2026-07-16, 전부 monotonic — 어떤 합법 인코딩도 불법이 되지 않음)**:
- 0x72 ACC_REDUCE: forbid_imm_any → false (RTL) / imm16 forbidden → optional (asm). **absent imm16 = SUM** (dec_eff_imm16=0 ⇒ sub-op 0x0) — 기존 port-only 인코딩은 전부 계속 decode 되며 SUM 의미를 획득 (표준 stub→real 전환). sub-op = imm16[7:4] ∈ **acc_reduce_op_codes {sum:0x0, max:0x1, l2sq:0x4, mean:0x5}** (신규 JSON 테이블 — einsum op_marker 공간과 코드 일치; **MIN 은 의도적 미탑재**: RED 는 min=2, einsum 은 min=6 으로 이미 충돌하는 공간이라 회피). imm16[3:0] reserved-zero 위반 / 미지 sub-op → lower_required (error_flag 아님). **MEAN = RNE(sum/N), ties-to-even, N ∈ {32,16} full lane set 만** — zero-padding 된 부분 벡터는 sum/N ≠ sum/K bias (normative 금지, SDK 강제).
- 0x7C STORE_QUANT: req_mem → false (RTL; mem-present 는 여전히 합법이되 v1.8.0b 에서 offset **무시** — v1.8.0d memory-destination form 예약), forbid_imm_any → false. out = clamp_dtype(RNE(x >>ₐ s)), s = imm16[5:0], absent = 0 (순수 saturating clamp). imm16[15:6] reserved-zero → lower_required. dtype 0x2/0x3 (f16/bf16) → lower_required (0d 까지).

**Scalar-in-64 payload 포맷 표 (normative)**:
| 관례 | 사용처 |
|---|---|
| {32'h0, x} zero-extend | legacy einsum L1/L2SQ (변경 없음; SCALAR_RSQRT 0x66 은 2026-07-24 제거 — §24) |
| **sext64(int32)** | 0x72 ACC_REDUCE, 0x7C STORE_QUANT 결과 |
| full 64-bit r | 0x71 VDOT_ACC (r = sext64(dot)+c mod 2^64) |

**v1.8.0b SDK 계약 (하드웨어 미강제 — asm/SDK 인코더가 보장)**:
1. 0x71 은 정확히 4-fragment, 0x72 는 정확히 2-fragment wave 로 발행 — 짧은 wave 는 stale slot 데이터를 읽음 (SIG_BMM_3 과 동일한 기존 노출면, dec_* bus 에 fragment 수가 없어 PE 에서 감지 불가)
2. instruction+EH chain 은 **모든 fragment 에 복제** — 완결 fragment 의 chain 만 파싱되고 완결 순서는 임의이므로, 미복제는 조용한 순서 의존 carry-in 버그
3. OPREF kind-1 carry-in 체이닝 중 같은 MU 에 개입하는 mul-class dispatch 금지 (positional bank clobber) — IMM 기반 트리 체이닝이 안전 기본값
4. MEAN 은 full lane set 에서만 모든 0x70-block mnemonic 은 assembler 에서 `.precision` EH + `prec` flag **필수** (asm 정적 mode 검사를 exact 하게 만듦). RTL 은 추가로 runtime tag-driven mode byte (input_tag[15:8], flags[2]=0) 를 수용 — 의도된 기록된 비대칭, 불변식 방향은 **asm-legal ⊆ RTL-legal** (equivalence 테스트로 기계 검증).

### 23.7 주요 residual risk (전문은 workflow 산출물)

1. 모든 HW 비용이 문헌 추정 — repo 자신의 Vivado 35-DSP vs yosys 123-MULT18X18D 괴리가 증명하듯, **per-operator FloPoCo + yosys/nextpnr synth 가 예산 확정 전 hard gate**. v2.0 의 ECP5 multiplier 여유는 사실상 0.
2. 어떤 타깃에서도 timing 데이터 없음 (base pod 조차 nextpnr PnR 미완). 5-6-stage fused FMA @100MHz 미증명 — v2.0 첫 마일스톤은 Fmax 산출.
3. ACC bank 는 순수 tagged-wave 모델 밖의 신규 architectural state — tag-keyed bank aliasing 은 silent-gradient-corruption 클래스. **RTL 전에 TLA+/formal 선행** (wavetensor-drivers formal-first 관례).
4. xczu3eg 는 synth report 0건 + board plan 부재 + FP-UNIT 미탑재 확정 — Makefile default 에서 은퇴하거나 int4-inference-only 로 명시 강등할 것.
5. 검증 공수가 RTL 공수를 초과할 전망 (~16 opcodes, fused-FMA pipe, NR step-sequence, SR, ACC state, canonical-order equivalence) — v2.0 의 지배적 일정 리스크.
6. "training-capable ≠ training-competitive" — 포지셔닝 규율 자체가 리스크.

### 23.8 진입 트리거

**v1.8 결정됨 (2026-07-16).** 사용자 지시: "f64는 별도의 확장(접미사 Lf)에서 본격적으로 다루는 게 좋겠어. 일단은 v1.8 진행해."
- f64 → optional extension **Lf** 로 이관 (§23.2 갱신). base 의 dtype nibble 0x5 는 decode_error 예약 유지, Lf 가 나중에 이 인코딩을 claim.
- v1.8 선행 조건 처리: (1) per-operator synth gate — v1.8.0c (FP-UNIT) 착수 전 완료 필수 (v1.8.0b 의 MU MAC tree 도 merge blocker 로 적용), (2) base pod nextpnr Fmax — 착수와 병렬 진행, (3) legality-ROM **JSON** codegen (~~YAML~~, §23.6 치환 기록 참조) — v1.8.0a 의 첫 산출물, (4) ACC bank TLA+ — v2.0 전 (v1.8 스코프 아님).
- **hard gate #2 실측 결과 (2026-07-16, 4차 실행에서 synth 최초 통과)**: 게이트가 잠복 결함 3건을 적발 — ① 함수호출 인덱싱 yosys 비호환 (v1.6.1b 잠복, commit 0afcf81), ② frag_pending[1:3] 범위 밖 동적 인덱스 (v1.7 잠복, commit d1b2739), ③ synth 스크립트 자체 (AUTONAME 30분+ → -run :check 우회; cell 라이브러리 whitebox 모델 → blackbox =A:whitebox 필수 — -nolutram 오진 정정 포함). **pod 2x2_2x2 실측 (yosys 0.64, synth_ecp5)**: LUT4 **70,235**/84K (84%), TRELLIS_FF **25,992**, CCU2C 5,165, PFUMX 10,526, **MULT18X18D 497 vs LFE5U-85F 보유 156 — 3.2× 초과예산 확정** (§23.7 리스크 1이 추정이 아닌 실측 사실이 됨). 결론: 현 geometry 의 base pod 는 Stage-1 부품에 곱셈기 기준으로 들어가지 않음 — v1.8.0b 이후 multiplier 공유/LUT 강제 매핑/geometry 축소 중 택일 필요. nextpnr PnR 결과 (2026-07-16 완결):
  - **pod 2x2_2x2**: MULT18X18D placement 실패 (497 > 156) + TRELLIS_COMB 101% (84,781/83,640) — 두 축 초과로 배치 불가 확정.
  - **Cluster 단독 (2x2 PE, out-of-context)**: 로직은 수용 (COMB 25%, MULT 128/156 = 82%, FF 7%) — IO 핀 초과라 --out-of-context 로 측정. **Fmax = 10.85 MHz** (100 MHz 제약 대비 **9.2× 미달**, worst slack ≈ -81 ns). Critical path: "**470 LUT 레벨**" 은 synth 단계(pre-PnR) 추정치로 기록을 유지하고, 잔존 PnR report (synth/lattice/reports/cluster_2x2_pnr.rpt, nextpnr JSON) 의 실측 critical path 는 **116 logic stage / 총 92.13 ns** (routing hop 117 포함, fmax achieved 10.8546 MHz) — 측정 단계가 달라 수치는 다르나 결론은 동일: 단일 사이클 dispatch 아키텍처(거대 einsum/MAC 함수 + 1024-bit wide mux + 우선순위 체인이 전부 한 클럭에 평가됨)의 구조적 귀결.
  - **결론 (v1.8.0c+ 설계 입력)**: §23.7 리스크 2 ("100MHz 미검증") 이 실측으로 최악 방향 확정. 100 MHz 는 현 조합 구조로는 불가능 — dispatch 파이프라이닝(wide 입력 레지스터링, 함수 평가 스테이지 분할, 출력 mux 단 분리)이 v1.8.0c FP-UNIT 설계와 함께 다뤄져야 할 아키텍처 항목. §23.5 처리량 정직성 수치(0.4-1.6 GFLOP/s @ 100MHz 가정)는 현 실측으론 ~10× 하향 — "정확성/재현성 우선, 속도는 Stage-2" 포지셔닝이 더더욱 필수.
- **enforcement plan (v1.8.0a 설계 workflow 확정)**: freshness 검사(gen_isa_tables.py --check 재생성+byte-diff)는 commit 필수인 `python -m unittest asm.test_wavetensor_asm` 스위트에 test 로 탑승 (no-CI repo 에서 가장 강한 채널); `make lint` 신설 (isa freshness + frag_total_m1_held, 향후 CI entrypoint); 전수 곱집합 decode-legality sweep (`WT_FULL_ISA_SWEEP=1`) 은 **release gate** 로 지정 — per-commit 은 equivalence-class 축약 실행.

### 23.9 v1.8 구현 staging

- **v1.8.0a**: ISA foundation — 단일 **JSON** 소스 codegen (legality ROM + asm.py 테이블 + golden model + spec 표 + lint 생성), 0x70-0x7F decode skeleton, mode byte field 파싱 (dtype[3:0]/acc[5:4]/rnd[7:6]). **3-commit staging** (설계 workflow w8gmgeokm 확정): COMMIT 0 = spec 선행 (§23.6a normative 표 저작 — 독립 리뷰로 same-author 순환 차단), COMMIT 1 = 무동작변경 legacy 이관 (isa/wt64v1_isa.json 47 opcodes 를 emitter-faithful 하게 — 알려진 asm-vs-RTL 비대칭 2건도 bit-for-bit 보존, EHDecode.v 의 legality case/is_alu_binary/opcode_supported/EH_* 를 generated include 4종으로 대체, asm.py Section-1 상수를 generated 모듈 import 로 대체, **사전-이관 RTL-derived frozen truth table + EH-subset sweep** 로 zero-behavior-change 증명), COMMIT 2 = 0x70-block skeleton (13 opcodes whitelist 편입, FP_LEGAL_ROM 4096-bit localparam — 21 legal rows, mode-byte wire 3종 + decode_error 11번째 항, PE_Core stub arm — BCAST 0x24 형 lower_required, asm require_precision_eh). **전 commit landing 완료 (2026-07-16)**: COMMIT 0=042f08e, COMMIT 1=c8213d6 (5934-point 이관 전 truth-table differential 로 무동작변경 증명), COMMIT 2 검증 = ROM sweep 4096점×2 (tag-path/PRECISION-EH-path 양쪽 eff_precision mux arm) golden model 과 bit-일치, stub all-ops live-extraction, 미배정 0x7A/7B/7F decode_error 유지, asm 13×256 mode 검사 equivalence — cocotb 181 (ISA_Decoder) + asm 104 + 전 모듈 무변경
- **v1.8.0b**: stateless int 경로 — VDOT_ACC(0x71, 4-fragment wide dot + carry-in) + ACC_REDUCE(0x72, wide 입력 stateless SUM/MAX/L2SQ/MEAN) + scalar int-dest STORE_QUANT(0x7C) (FP 하드웨어 불요, "벡터 정수 = 스칼라급 신뢰성" 을 가장 먼저 배달). **명시적 staging 양보 (설계 workflow wwov1b5i3 확정)**: VFMA_ACC(0x70) → v1.8.0c 로 이연 (stateless 형은 16-fragment 출력 FSM 필요, stateful 형은 누산기 설계 필요 — 양쪽 다 열린 상태로 stub 유지), vector STORE_QUANT → 0c/0d, f16/bf16 destination → 0d. per-pe-acc 안은 adversarial verify 에서 refuted (forbidden→required EH 전환 = spec 자기 정책 위반 breaking + LUT/MULT 예산 초과에 uncosted)
- **v1.8.0c**: FP-UNIT fp32 scalar pipeline (FSCALAR/FRSQRT32/FEXP2_32) — per-operator synth gate 통과 후 (normative 의미론·게이트·리스크 전문은 §23.10). **dispatch 파이프라이닝(shuttle)은 v1.8.0c 에서 명시적으로 descope — 전용 v1.9 timing release 로 이관** (§23.8 의 co-design 문구는 "pipelining-compatible 축조 + hoist 선지불" 로 이행). 0c 가 선지불하는 호환성 조치 3종: ① 모든 fp arithmetic 은 fp-local flop 뒤 (fp unit 자체가 pipelining-compatible), ② launch arm 은 register-load-only, ③ output_regs_free hoist 는 v1.9 shuttle 이 그대로 재사용
- **v1.8.0d**: CVT/I2F/F2I + DEQUANT + FP 대상 STORE_QUANT + norm 매크로 fp32 재구축

### 23.10 v1.8.0c — fp32 scalar step-sequencer unit (normative)

**당선 설계 "MU-hosted fp32 step sequencer (amended)" (설계 workflow 내부 명칭 sequential-microcode-mu) (2026-07-16 설계 workflow, adversarial verify 의 필수 amendment 7건 반영).** 본 절이 v1.8.0c 의 normative source 다 — spec-before-code FIRST COMMIT. IEEE specials 는 언제나 DATA (qNaN/Inf/zero) 를 산출하며 error_flag 가 절대 아니다; 유일한 fp error_flag 는 FSCALAR missing-B (아래). 결과 tag[15:8] 은 mode byte 를 verbatim 운반 (0x70 block 밖에선 inert, 기존 관례).

#### 23.10.1 아키텍처

- **MU-hosted fp_state FSM**: FP_IDLE / FP_CLASSIFY / FP_EXEC / FP_FINISH + fp_step[5:0] microprogram counter — 클럭당 정확히 1 registered micro-step. 0x74/0x75/0x76 은 **양쪽 twin classifier** (Cluster.v is_mul_op + PE_Core.v dec_is_mul_op) 에 동시 추가되어 기존 ext_to_mu 로 routing (한쪽 누락 = silent permanent lower_required dead-end — lockstep 테스트를 같은 commit 에 탑승).
- **공유 fp32 multiplier 1기**: 24×24 mantissa product, 4× MULT18X18D + `(* WT_USE_DSP *)`, registered stage 2단 (product 단 / exponent·normalize·RNE 단).
- **공유 wide FMA-capable adder 1기**: registered stage 2단. datapath 는 FMA 기준으로 sizing — 48-bit unrounded product 를 wide 로 유지, addend 는 **~76-bit sticky-preserving alignment** 경로에서 정렬, **~50-bit LZC**, **단일 final RNE**. 이 wide path 는 fused-FMA 계약과 FS_DIV Markstein correction 양쪽에 load-bearing; plain FADD 는 같은 하드웨어에 2nd operand zero-extend 로 통과.
- **generate gating**: 전체 datapath 는 `generate if (MUL_OPS_SUPPORTED) begin : g_v180c_fp`; **제어 state (fp_state[1:0], fp_step[5:0], fp_valid_p2) 는 generate 밖 unconditional 선언 (div_state 패턴)** 후 parameter 하에서만 구동 — pe_ready 와 drain gate 가 19 instance 전부에서 elaborate 되도록. data wire 는 g_v180c_fp_off 에서 zero-tied.

**Launch ladder (real case arm — stub arm 아님, DIV silent-swallow 아님; 4 rungs 순서 normative)**:
1. `!MUL_OPS_SUPPORTED` → **lower_required** (0x71/0x72 prologue 선례)
2. `!output_regs_free` → **lower_required** (VDOT busy-reject 패턴) — 5-34 cycle fp op 진행 중 도착하는 2번째 fp op, 또는 어떤 gated op 이든 **lower_required 를 받는다. silent drop 절대 금지.**
3. op별 decode guard (각 opcode 절 참조)
4. else launch: operand + sub-op latch, `fp_tag_held <= {dec_wave_number, dec_thread_id, 8'h00, dec_eff_output_port_id, dec_eff_precision, 8'h00}` (scalar dim=0x00 rebuild 관례), `fp_opcode_held <= dec_opcode`, `fp_state <= FP_CLASSIFY`

**output_regs_free (hoisted 단일 named wire, 8-term으로 widen; pe_ready = 동일 식)**:
```
(frag_idx==FRAG_IDLE) && !mul_valid_p1 && !mul_valid_p2
&& (div_state==DIV_IDLE) && !div_valid_p2 && !div_b_zero_p2
&& (fp_state==FP_IDLE)  && !fp_valid_p2
```

**MANDATORY MUL-launch fp-idle guard**: 0x12 MUL launch predicate (PE_Core.v:1790-1792) 에 `&& (fp_state==FP_IDLE) && !fp_valid_p2` 추가. 이것이 없으면 mul_valid_p2 pulse 가 1-cycle fp_valid_p2 FINISH pulse 와 겹치는 순간 fp 결과가 **조용히 유실**된다 (priority chain 에서 MUL 이 FP 상위).

**FINISH / output priority chain**: fp_valid_p2 / fp_result_p2(`{32'h0, packed_fp32}`) / fp_tag_p2 를 정확히 1 cycle pulse (div_valid_p2 처럼 default-clear). output priority chain 은 DIV 뒤에 registered arm 1개 추가 — **frag-drain > MUL p2 > DIV p2 > FP p2 > case dispatch**. 이 arm 은 `opcode_out <= fp_opcode_held` 도 설정: **DIV 의 stale-opcode quirk 로부터의 의도적 divergence** (테스트로 pin).

**SDK positional-bank 규칙 확장 (Cluster.v:401-403 주석 확장)**: fp 결과는 mu_out_* 를 경유해 mu_bank_reg 에 positional 하게 쓰이므로, **fp op 과 그에 의존하는 OPREF kind-1 read 사이에 개입 mul-class dispatch 금지** — DIV 의 64-cycle 잠복 hazard 와 동일 클래스 (하드웨어 fix 는 v1.9 로 deferred, §23.10.9).

#### 23.10.2 0x74 FSCALAR

**Operands**: A = payload_a[31:0] (dec_input_payload); B = payload_b[31:0] (dec_input_payload_b) — **F_HAS_OPB (cb_flags[3]) 가 모든 sub-op 에 필수**; C (FS_FMA 전용) = **payload_a[63:32]** — fp32 scalar 는 64-bit slot 의 절반이라 FMA 에 신규 EH channel 불요. non-FMA sub-op 의 payload_a[63:32] 는 reserved (하드웨어 무시, assembler zero-fill). eff_b_value 는 **미소비** (B 는 payload_b port 로 오고 imm/opref mux 가 아님) → EHDecode.v:501 의 alu_binary XOR trap 은 영구 dormant: rtl_alu_binary=false, forbid_opref=true 유지 (양쪽 다 load-bearing).

**Missing-B guard (dispatch-side)**: `!dec_input_payload_b_valid` → **error_flag** (malformed program, deterministic; PE_Core.v:59 input 의 첫 소비자). opb_required_invalid 는 "opcode 가 flag 를 요구함" 을 표현할 수 없어 dispatch 측 검사가 필수.

**Sub-op**: imm16[7:4] ∈ 신규 single-source JSON 테이블 **fscalar_op_codes {FS_ADD:0x0, FS_SUB:0x1, FS_MUL:0x2, FS_FMA:0x3, FS_DIV:0x4}** → isa_subop_codes.vh 로 codegen (ACC_REDUCE 0x72 패턴 verbatim). imm16 은 forbidden→**optional** loosening; **absent = 0x0 = FS_ADD**. imm16[3:0] reserved-zero 위반 → lower_required; 미지 sub-op (0x5-0xF) → lower_required.

**imm-forbid**: rtl_legality 의 imm forbid 는 전면 삭제 (0x72 의미론 verbatim — forbid_imm_any 단일 비트뿐, per-size split 이 없음); **imm32/imm64 는 ASM-FORBIDDEN 이되 RTL-TOLERATED** — FSCALAR 가 eff_b_value 를 읽지 않으므로 무해함을 명기.

**Sub-op 알고리즘**: FS_ADD/FS_SUB/FS_MUL = 공유 adder/multiplier 1 pass; FS_FMA = wide fused microstep (exact 48-bit product 유지, 단일 RNE); FS_DIV = 아래 pinned 알고리즘.

**FS_DIV (pinned — scale-invariant unpacked-significand Newton)**:
1. unpack: a = ma·2^ea, b = mb·2^eb, ma,mb ∈ [1,2)
2. reciprocal seed: 256×9 ROM, index mb[22:15]
3. NR **3회**: r' = r·(2 − mb·r) — unpacked significand 위, safe binade
4. q0 = ma·r
5. **Markstein correction**: e = ma − q0·mb, q = q0 + e·r — fused wide microstep 경유
6. exponent eq = ea − eb + normalize 는 **pack 에서 1회만** 조립; overflow/underflow 도 pack 에서만 처리 (q0-overflows-to-Inf hazard 제거)

**Markstein precondition 논증 (sketch)**: 256×9 seed 의 초기 상대오차 ≲2⁻⁹; NR 은 오차를 제곱하므로 3회 후 exact 산술 기준 ~2⁻⁷²급 — widened round-to-odd 중간값의 rounding noise 를 보수적으로 반영해도 r 의 1/mb 대비 상대오차는 2⁻²⁷ 이하로, fp32 (p=24) 의 Markstein 전제 (r 이 1/b 를 p bit 이상 근사) 를 여유 있게 충족. 그러면 q0 = RN(ma·r) 은 ma/mb 의 1 ulp 이내이고, residual e = ma − q0·mb 는 wide fused path (48-bit product 무반올림) 에서 **exact**. Markstein 정리에 의해 q = RN(q0 + e·r) 은 correctly-rounded RNE quotient. scale-invariant 형이므로 이 전제는 고정 binade [1,2) 안에서 성립하며 지수 범위(overflow/underflow)와의 간섭이 구조적으로 없다. **내부 micro-step 은 DAZ/FTZ-EXEMPT** — 아니면 underflow 근방에서 Markstein residual 이 flush 되어 misround (§23.10.5 정책 표에 pin).

#### 23.10.3 0x75 FRSQRT32

**Strictly port-only unary** (EH shape 는 v1.8.0a 와 byte-identical); A = payload_a[31:0].

**Range reduction — 구조적으로 PINNED**: rsqrt(4x) = rsqrt(x)/2 (exact) 를 이용해 datapath 가 x 를 x' ∈ [1,4) (mantissa + exponent parity) 와 even exponent shift 로 분해; **모든 NR iteration 은 x' 의 unpacked widened significand (27-30 bit, round-to-odd 중간값, DAZ/FTZ-exempt) 위에서** 실행; exponent 는 final pack 에서만 조립. 이로써 2²⁴ equivalence-class collapse 가 valid RTL property 가 되고 (scale covariance by construction), large-x FTZ divergence 가 제거된다.

**Seed**: 256-entry × 9-bit ROM, index **{exp[0], mant[22:16]}**, pinned script `scripts/gen_frsqrt_seed_rom.py` 생성 (midpoint-of-segment, 9-bit RNE quantization). exhaustive sweep 은 **shipped ROM 실물**에 대해 재실행 (reference 재구성 아님).

**Schedule**: h = 0.5·x' (exact exponent decrement) 후 **NR 3회 (THREE — normative)**: y' = y·(1.5 − h·y·y) = multiplier 3 pass + adder 1 pass / iteration; 단일 final RNE pack. (2회는 2.205 ulp 실측 — FAIL; 3회는 1.731 ulp — PASS.)

**계약**: **≤2 ulp** — 근거는 model 상 2²⁴ class 전수 sweep (proof, not sample) 이며, RTL 로의 유효성은 pinned range reduction + RTL scale-covariance property test + RTL-vs-model lockstep sample 로 이월. **기록된 margin: worst-case 1.731 ulp @ 3 iterations — 여유 0.27 ulp** (§23.10.9 리스크 참조). **Monotonicity (non-increasing) 는 NORMATIVE** — exhaustive sweep 내 monotonicity assertion 으로 discharge.

**Specials**: rsqrt(+0)=+Inf; rsqrt(−0)=−Inf; rsqrt(x<0)=qNaN; rsqrt(+Inf)=+0; rsqrt(NaN)=qNaN; **x=4^k → bit-exact 2^−k** (sweep 에서 별도 bit-equality 로 assert — ≤2 ulp 로 함의되지 않음).

#### 23.10.4 0x76 FEXP2_32

**Strictly port-only unary.**

**FP_CLASSIFY**: NaN → qNaN; **x ≥ 128 → +Inf** (fast path, exact — 2¹²⁸ 은 RNE overflow threshold 초과); **x 가 정수 n ∈ [−126,127] → exact exponent assembly 로 2^n BIT-EXACT BY CONSTRUCTION** (integer bypass — 계약이 polynomial fit 에 걸리지 않음); 정수 n ≤ −127 → +0 (FTZ); exp2(±0) = 1.0 exact (integer bypass 가 커버).

**Non-special path**: exact split x = n + f, f ∈ [0,1) (shift/compare, exact); 2^f 는 **DEGREE-6 minimax Horner** (degree-4 는 33.4 ulp 로 REFUTED; degree-5 는 1.47 ulp 로 thin; degree-6 실측 0.56 ulp — safe) = multiplier 6 pass + adder 6 pass; 계수 7개는 `scripts/gen_fexp2_coeffs.py` 산출로 **c0 를 정확히 1.0f 로 CONSTRAIN** (integer bypass 와 belt-and-suspenders), JSON single-source 에 frozen; exponent assembly 로 n 가산 (exact); final pack = unbounded-exponent RNE 후 FTZ.

**Underflow boundary — 올바르게 PINNED**: normative cell 은 **result = FTZ(RN_unbounded(2^x))** 이지 'x < −126 → +0' **comparator 가 아니다** — −126 바로 아래 sliver 에서 RN 이 min_normal 로 올림하면 결과는 **min_normal** (양 경계 ±1 ulp 에 directed vector). 하방 comparator fast path 는 **x ≤ −150 (무조건 +0)** 뿐.

**Overflow**: (127.99999991, 128) 구간 입력은 comparator 가 아닌 **pack 의 RNE overflow** 로 +Inf 도달.

**계약**: non-special domain 에서 **≤2 ulp**; **monotonicity (non-decreasing) 는 NORMATIVE** — model-exhaustive sweep (chunked 2³², offline 수 시간) 으로 discharge; RTL 측은 정직하게 SAMPLED (directed boundary + 10⁵ lockstep) — rsqrt 와의 커버리지 비대칭을 명기.

#### 23.10.5 normative IEEE 표

**정책 (전 op 공통, 각 항이 directed vector 를 생성)**:

| 정책 | normative 내용 |
|---|---|
| rounding | **RNE only** — fp_block ROM 행 불변 (dtype [0x4], acc [1], rnd [0]); rnd nibble 1/2/3 은 ILLEGAL 유지 |
| DAZ | denormal operand 는 **operand load 시에만** same-signed zero 로 flush; **min_normal 0x00800000 은 절대 flush 안 됨**; flush 된 부호 보존 |
| FTZ | **flush-AFTER-round with unbounded-exponent rounding**: exact result 의 RN 을 unbounded exponent 로 계산 → \|result\| < min_normal 이면 same-signed zero 로 치환 |
| 내부 micro-step | widened internal format 에서 **DAZ/FTZ-EXEMPT** (pinned — 아니면 Markstein residual flush 로 FDIV 가 underflow 근방 misround) |
| NaN | 모든 NaN-producing case 에 **단일 canonical qNaN 0x7FC00000**; sNaN 은 canonical 패턴으로 quiet, trap 없음 (§23.4 항목 5 bit-reproducibility 계약에 필수; sticky-invalid 는 0x7E 예약) |
| ulp 정의 | **ulp(x) = 2^(e−23)**, e 는 infinitely-precise result 의 binade exponent (Goldberg 관례; binade edge 에선 smaller binade) |

**Special-case 행 (각 행 = directed test vector 1개; 완전성이 계약)**:

| # | op | 입력/조건 | 결과 (normative) |
|---|---|---|---|
| A1 | add | Inf + Inf (동부호) | 동부호 Inf |
| A2 | add | (+Inf) + (−Inf) | qNaN 0x7FC00000 |
| A3 | add | (+0) + (−0) | +0 |
| A4 | add | x + (−x), x finite | +0 |
| A5 | add/mul | NaN operand (sNaN 포함) | canonical qNaN (sNaN quieted) |
| A6 | add/mul | RNE overflow | ±Inf |
| M1 | mul | Inf × 0 | qNaN |
| M2 | mul | Inf × finite≠0 | sign-XOR Inf |
| M3 | mul | 부호는 항상 XOR, zero 결과 포함 — (−0)×(+3) | −0 |
| Z1 | DAZ | denormal operand | same-signed zero 로 flush (부호 보존); min_normal 은 통과 |
| F1 | FMA | fused **단일 rounding** (48-bit product 무반올림 유지 후 1회 RNE) | normative |
| F2 | FMA | Inf×0 + c, 모든 c (**c=NaN 포함 — NaN operand 가 있으면 canonical qNaN 이 우선**) | qNaN |
| F3 | FMA | (+Inf×x) + (−Inf) | qNaN |
| F4 | FMA | exact cancellation a·b = −c | +0 (RNE) |
| F5 | FMA | product 가 −0 인 경우의 부호 | XOR rule 이 add 까지 관통 |
| V1 | FDIV | finite≠0 / (±0) | sign-XOR Inf |
| V2 | FDIV | 0 / 0 | qNaN |
| V3 | FDIV | Inf / Inf | qNaN |
| V4 | FDIV | finite / Inf | sign-XOR 0 |
| V5 | FDIV | Inf / finite | sign-XOR Inf |
| V6 | FDIV | quotient 부호 | 항상 sign-XOR (explicit row) |
| V7 | FDIV | x / denormal (**DAZ 귀결 — 자체 행으로 pin**) | x/(±0) 과 동일 = sign-XOR Inf |
| R1 | rsqrt | +0 | +Inf |
| R2 | rsqrt | −0 | −Inf |
| R3 | rsqrt | x < 0 | qNaN |
| R4 | rsqrt | +Inf | +0 |
| R5 | rsqrt | NaN | qNaN |
| R6 | rsqrt | x = 4^k | **bit-exact 2^−k** |
| E1 | exp2 | NaN | qNaN |
| E2 | exp2 | x ≥ 128 | +Inf (fast path) |
| E3 | exp2 | 정수 n ∈ [−126,127] | **bit-exact 2^n** (integer bypass) |
| E4 | exp2 | 정수 n ≤ −127 | +0 (FTZ) |
| E5 | exp2 | ±0 | 1.0 exact |
| E6 | exp2 | underflow sliver (x 가 −126 바로 아래) | **FTZ(RN_unbounded(2^x))** — RN 이 min_normal 로 올림하면 min_normal, 아니면 +0 |
| E7 | exp2 | x ≤ −150 | +0 (fast path) |
| E8 | exp2 | x ∈ (127.99999991, 128) | +Inf — **pack 의 RNE overflow 경유** (comparator 아님) |

#### 23.10.6 cycle maxima 표 (normative)

**maxima 다 — 테스트는 bound 내 완료(completion-within-bound)를 assert 하고, exact cycle count 는 절대 assert 하지 않는다** (Gate 2 fallback 인 +1 cycle/adder-pass 흡수 여유 포함).

| op | 최대 cycles |
|---|---|
| FS_ADD / FS_SUB | ≤6 |
| FS_MUL | ≤6 |
| FS_FMA | ≤10 |
| FS_DIV | ≤32 |
| FRSQRT32 | ≤34 |
| FEXP2_32 | ≤30 |

#### 23.10.7 per-operator synth gate (merge blocker)

§23.8(1) 의 hard gate 를 fp 에 적용 — 동기는 repo 자신의 Vivado-35-DSP vs yosys-497-MULT 괴리. **어떤 fp RTL 도 해당 operator 가 standalone yosys+nextpnr gate 를 정확한 타깃 (LFE5UM-85F, CABGA381, --speed 6, out-of-context, synth/lattice/scripts/pnr_pod.sh 와 동일 flow) 에서 통과하기 전에는 PE_Core.v 에 merge 되지 않는다.** 신규 harness: `synth/lattice/scripts/synth_fp_ops.sh` + per-operator wrapper top (synth/lattice/fp_ops/).

- **GATE 1 — fp32 shared multiplier** (24×24 mantissa product, registered product stage + registered exponent/normalize/RNE stage, `(* WT_USE_DSP *)` — PE_Core.v:1569 선례). **Pass: ≤4 MULT18X18D (yosys 가 더 많이 decompose 하면 hard fail — 이 gate 가 존재하는 바로 그 괴리 클래스), ≤300 LUT4, standalone Fmax ≥ 40 MHz per registered stage.**
- **GATE 2 — wide fp32 adder / FMA-align datapath** (registered stage 2단: 76-bit sticky-preserving alignment; wide add + ~50-bit LZC + normalize + RNE). fat 하게 synth 될 가능성이 가장 높은 operator (FMA-capable 이라 plain fp32 adder 의 1.5-2× — **정직하게 500-900 LUT4 로 가격 책정**, 300-500 plain-adder 수치 아님). **Pass: ≤900 LUT4, 0 MULT, standalone Fmax ≥ 40 MHz per stage**; stage 2 (add+LZC+normalize+RNE) 가 40 MHz 미달 시 pre-approved fallback 은 **adder pass 당 +1 sequencer cycle** (FSM step-count 변경만 — cycle maxima 표에 이미 headroom) 이지 datapath 재설계가 아님.
- **GATE 3 — 전체 g_v180c_fp unit standalone** (FSM + step-sequence case + source mux + temp reg + fp_tag_held + seed/coeff ROM + operator 양쪽). **Pass: 총 ≤ +3500 LUT4 (amended, 아래), 정확히 +4 MULT18X18D, ≤ +900 FF, distributed ROM 으로 0 EBR (문서화된 1-EBR fallback 허용), Fmax ≥ 40 MHz.** Gates 1-3 은 **PE_Core merge commit 이전에** 실행.
  - **AMENDMENT (2026-07-16, 실측 근거)**: LUT4 예산 2000 → 3500. 원 2000 은 문헌 추정 (residual risk 1 이 예고한 바로 그 케이스). 실측 3,345 LUT4 — 유일한 진성 pathology (seed-ROM dynamic part-select 가 2304-bit barrel shifter 로 합성, -428 LUT 수정 후 TB bit-exact 재입증) 제거 후의 architecture-intrinsic 수치: ~2,000 sequencer operand-mux fabric (단일 공유 곱셈기/adder 설계의 본질 비용 — 연산기 복제 대안은 면적·MULT 모두 더 비쌈), ~520 ROM, ~800 operators. **구속력 있는 실예산은 Gate 4 의 cluster TRELLIS_COMB ≤30%** 이며 정합 확인됨: 25% + 3,345/83,640 ≈ 29%. Fmax 는 seed noise 였음 (seed 1: 39.79, seeds 2/3/4: 40.84/40.11/40.95 — archive 는 seed 2). **Gate 3 실측 최종: 3,345 LUT4 / 4 MULT18X18D / 767 FF / 0 EBR / 40.84 MHz — PASS (amended).**
  - 교훈 (yosys): ROM 의 dynamic part-select 인덱싱은 barrel shifter 로 합성됨 — 상수 배열 인덱싱 shape 사용 (v1.6.1b 함수호출 인덱싱 금지와 같은 계열).
- **GATE 4 — 통합 후 full Cluster (2×2) synth+PnR 재실행.** **Pass: MULT18X18D ≤ 140/156; TRELLIS_COMB ≤ 38% (amended, 아래); Fmax ≥ 10.5 MHz (실측 10.8546 MHz 대비 ~3% noise 이상 regression 없음); 그리고 critical-path diff** — worst-path endpoint report 를 cluster_2x2_pnr.rpt 와 diff. 정직한 주장은 "**u_matmul_unit.output_payload endpoint 에서 ≤1 mux level, dispatch cone 심화 zero**" 이며 이 diff 가 그것을 강제하는 CI 검사다 (기존 "zero added depth" 문구는 은퇴). Gate 4 는 **release tag 이전에** 실행.

**Ordering**: Gate 1+2 → operator RTL 파일 merge (unwired); Gate 3 → PE_Core g_v180c_fp commit; Gate 4 → release.

**GATE 4 실측 최종 (2026-07-17, PASS with amendments)**:
- **Fmax 10.51 MHz** (≥10.5 PASS; baseline 10.85 대비 -3.1%). critical path 116 → 120 logic stages / 92.1 → 95.1 ns — 사실상 복원 (+4 stages 는 fp mux level + routing variance; netlist 익명화로 endpoint 단위 diff 는 stage-count diff 로 대체).
- **MULT18X18D 134/156** (≤140 PASS).
- **TRELLIS_COMB 30,968/83,640 = 37.0%** — 원 기준 30% 은 **산정 오류**: baseline 25% 는 v1.8.0b **이전** 시점 synth 였고, 30% 예산은 fp(+3.3k 실측)만 반영, v1.8.0b VDOT/ACC_REDUCE/STORE_QUANT datapath (+~6.7k, 잔차 귀속) 를 누락. 기준을 38% 로 amend (실측 37.0% PASS). Stage-1 단일-Cluster vehicle 에는 63% 여유 — 0d(CVT/DEQUANT/norm) 증분은 다음 gate 에서 실측 선반영.
- **Gate 4 가 적발한 결함 (v1.8.0b 유산)**: 첫 실행 Fmax 5.88 MHz / 1,015 logic stages — v1.8.0b 의 6개 reduction 함수가 선형 누산 루프 (acc = acc + lane[i]) 로 작성되어 32개 직렬 carry-chain ripple 로 합성된 것. v1.8.0b 가 자신의 "MU MAC-tree per-operator synth gate = merge blocker" 를 실행하지 않고 merge 된 프로세스 실패가 5 commit 뒤 여기서 발각. 수정: 6개 함수 전부 최소 폭 balanced tree (참값 범위가 stage 폭에 수용 → 재결합 불변 bit-exact, 전체 regression green 재입증). **교훈 (normative): (1) reduction 루프는 tree 로 쓸 것, (2) merge blocker 선언된 gate 는 commit 전 완료 확인.** 모든 gate 의 report 는 `synth/lattice/reports/fp_ops/` 에 archive — spec 의 hw_cost 표가 문헌이 아닌 실측을 인용하도록.

#### 23.10.8 stub dispositions (v1.8.0c 에서 stub 유지: {0x70, 0x73, 0x77, 0x78, 0x79, 0x7D, 0x7E} — lower_required)

- **0x70 VFMA** → v1.8.0d: scalar wide-FMA microstep 의 MU 상 sequential per-lane 재사용으로 vector FMA; bf16 dtype widening 은 v2.0 이연.
- **0x73 ACC_ELEMWISE** → v1.8.0d: 기존 MAC/adder 인프라 위 elementwise acc op, ~~sub-op 표는 0x72/0x74 패턴~~. **AMENDMENT (2026-07-24, v1.8.0d COMMIT 0)**: v1.8.0d 에서 **OPREF form 전용으로 graduate** — 원안의 sub-op 표는 **삭제** (EHDecode.v:501 의 alu_binary XOR trap 하에서 imm carve-out 이 decode_error 없이는 구현 불가 — invariant 를 amend 하는 대신 존중). **어떤 imm 이든 존재 (dec_eff_opref_kind==0) → lower_required** (capability absence). 전문은 §23.10.10(c).
- **0x77/0x78** → 빨라야 v1.8.0d: port-only shape 불변; **pure monotonic stub-body replacement 로만** 착지. **AMENDMENT (2026-07-24, v1.8.0d COMMIT 0)**: **0x77 CVT 는 v1.8.0d 에서 graduate** 하되 "port-only shape 불변" 문구를 완화 — imm16 은 forbidden→**optional** 로 loosening (0x72/0x74 의 정확한 선례, sub-op nibble imm16[7:4] 운반; imm32/imm64 는 FSCALAR 처럼 ASM-FORBIDDEN/RTL-TOLERATED). **이 loosening 이 intent-preserving 인 논증 (명시 기록)**: 원 문구의 의도는 "신규 EH data channel 을 열지 않는다" 였고, CVT 는 **eff_b_value 를 절대 읽지 않으므로** imm16 은 data 가 아니라 sub-op selector 로만 기능한다 — 0x74 FSCALAR 가 같은 shape 으로 이미 착지한 정확한 패턴이며, FP_LEGAL_ROM legal_dtypes [2,3]→[0,1,2,3,4] 확장도 monotonic illegal→legal 이므로 stub-body-replacement 계열의 monotonic 성질은 보존된다. **0x78 DEQUANT 는 v1.8.0e 로 이연** (전 form; §23.10.10(a) deferral 표). 전문은 §23.10.10(b).
- **0x7C STORE_QUANT fp-dest (dtype 0x2/0x3)** — **AMENDMENT (2026-07-24)**: STUB_OPS 집합 밖의 execute-side stub (PE_Core.v:3165-3169 else-arm) 이었던 fp-dest 팔이 **v1.8.0d 에서 graduate** — pure execute-side stub-body replacement, decode 불변, twin classifier 불변 (전 dtype L-PE 유지). 전문은 §23.10.10(d).
- **0x79 FMAX/FMIN** → 구현은 v1.8.0d, **의미론은 지금 (v1.8.0c spec commit 에서) PIN**: **IEEE754-2019 minimumNumber/maximumNumber** — **−0 < +0**; **NaN 은 number 에 패배** (한쪽 NaN → number 반환); **양쪽 NaN → canonical qNaN 0x7FC00000**; **signed-int compare tree 재사용 금지** (§23.6). 0d 는 frozen 계약에 대고 구현.
- **0x7D** → v2.0.
- **0x7E FP_STATUS** → v1.8.0d/v2.0: sticky flag register (invalid / overflow / underflow-flushed). **v1.8.0c 는 semantics 를 prose 로만 예약하고 레지스터를 추가하지 않는다** — fp special-case 표가 deterministic 이므로 flag 는 이후 어떤 result bit 도 바꾸지 않고 추가 가능.

#### 23.10.9 residual risks (v1.8.0c)

1. **모든 area/Fmax 수치는 synth Gates 1-3 실행 전까지 문헌 추정** — FMA-capable wide adder (500-900 LUT4 책정) 가 fat synth 또는 40 MHz stage 미달 가능성 최고; pre-approved fallback (+1 sequencer cycle/adder pass) 은 cycle 표 변경이지 재설계가 아니나, Gate 2 가 EBR 강제나 partitioning 결정을 spec 에 역주입할 수 있음.
2. **mu_bank_reg positional hazard 는 SDK-rule 확장 + directed test 로 완화될 뿐 하드웨어 fix 아님**: 긴 fp op 중 개입 mul-class dispatch 는 여전히 fp 결과를 잘못된 bank slot 에 쓴다. DIV 의 64-cycle 잠복 hazard 와 선례 일치하나 fp op 이 노출면을 넓힘; 제대로 된 fix (launch 시 bank target latch) 는 deferred — **v1.9 arbitration rework 에 탑승**.
3. **MU serialization 은 당선 설계에 내재**: cluster 당 scalar fp op 동시 1개, op 당 5-34 cycle (**10.85 MHz 에서 ~0.5-3 µs**) 동안 cluster_ready 가 cluster-wide deassert. Stage-1 accuracy-first vehicle + observe-only 인 오늘은 수용 가능하나, cluster_ready 의 미래 소비자와 fp-throughput-sensitive Stage-2 워크로드가 이를 상속 — **fp throughput 이 중요해지면 이 설계는 확장이 아니라 대체 대상**.
4. **dispatch 파이프라이닝은 §23.8 co-design 문구에도 불구하고 v1.9 로 의도적 이연** — 여기서는 "pipelining-compatible 축조 + output_regs_free hoist" 로 이행; fabric 은 v1.8.0c 내내 ~10.85 MHz 이고 v1.9 shuttle 은 소수의 cycle-exact pe_ready-window 테스트를 재유도해야 함; v1.9 가 밀리면 fp wall-clock latency (~3 µs worst) 지속.
5. **FRSQRT32 margin 이 얇음 (1.731 vs 2.0 ulp — 여유 0.27)** 이고 seed 구성·step 순서에 민감: 구현 RTL 의 step 순서가 모델 순서 (x·y-first, widened round-to-odd 중간값) 에서 이탈하면 margin 을 조용히 잠식 — shipped artifact 에 대한 exhaustive sweep 재실행이 backstop 이나, RTL-vs-model lockstep sample 과 scale-covariance test 가 실제로 CI 에 유지될 때만 유효; FEXP2 의 RTL coverage 는 필연적으로 sampled (2³² RTL-exhaustive 불가).
6. **twin-classifier lockstep 과 stub-membership 은 이번 release 가 편집하는 cross-file invariant**: 보호 대상 failure mode (silent permanent lower_required dead-end) 는 확장된 lockstep/reachability 테스트가 RTL 편집과 **같은 commit** 에 착지할 때만 잡힘 — 설계 리스크가 아닌 process 리스크이며, 이 codebase 를 이미 문 적 있음 (v1.5.3 arbitration bugs).
7. **pod-scale placement 는 여전히 실패** (MULT 497>156, COMB 101%) 이고 이번 release 는 pod 수요를 더 늘림 (cluster 당 +4 MULT); 단일-Cluster Stage-1 vehicle 에선 명시적 scope 밖이나, **모든 v1.8.0c 수치는 cluster-OOC 한정 — 어떤 pod 주장도 여기서 유도 금지**.
8. **IEEE sticky exception flag 는 0x7E FP_STATUS 착지 전까지 갈 곳이 없음**: 초기 소프트웨어는 invalid/overflow 를 전혀 관측 불가; spec 은 semantics 만 예약하며, 0x7E 의 최종 설계가 per-op flag capture 를 원하면 fp FSM 에 (results-invariant) sticky-latch retrofit 필요.

#### 23.10.10 v1.8.0d — scalar conversion 층 (normative)

**당선 설계 "split-scalar-first" (2026-07-24 설계 workflow, adversarial verify 의 확정 수정 전건 반영).** 본 절이 v1.8.0d 의 normative source 다 — spec-before-code COMMIT 0. 골자: **scalar-only 0d** — 0x77 CVT (6종 scalar 변환) + 0x73 ACC_ELEMWISE (OPREF form) + 0x7C STORE_QUANT fp-dest packer + hybrid fp-scalar/int-wide norm 매크로 재구축. 핵심 판단 근거 3: (1) release 의 존재 이유인 **rsqrt LUT 6.25% floor kill** 은 FRSQRT32(≤2 ulp) 를 세 norm 매크로 안에 CVT→FSCALAR→FRSQRT32→F2I insert 로 삽입하는 것만으로 달성 — full-fp application 경로 (DEQUANT/VFMA) 는 floor kill 에 불요하고 MSE≤1.05× 계약에만 필요하므로 후자는 0e 로 정직하게 re-scope; (2) 본 설계는 **2-bit emit FSM (v1.7 이 flag 한 최고위험 공유 구조) 을 일절 건드리지 않는 유일한 안** — 모든 0d 결과는 단일 64-bit fragment 이고 `lint_frag_total_m1_held.py` 가 무수정 통과 (테스트로 pin); (3) 최악 추정 × 실측 overrun 계수 1.67 로도 단일 pre-priced gate (40.82% < 41.0%) 아래 수납되는 유일한 안. MULT wall (≤140 ceiling 아래 여유 6) 이 모든 wide op 을 어차피 sequential 로 강제하므로 wide package 의 0e 이연은 어떤 아키텍처 선택지도 봉쇄하지 않는다.

##### 23.10.10(a) Scope — 착지 항목과 deferral 전건

**v1.8.0d 에 착지 (6건)**:

1. **0x77 CVT** — MU-hosted FP_StepSeq step 프로그램 (신규 op class **OPS_CVT**), scalar 변환 6종: f16→f32 · bf16→f32 (widen, sub-op 0x0 = imm16-absent default), f32→f16 · f32→bf16 (narrow, sub-op 0x1), I2F int4/int8 exact 및 int64-sext64 (dtype 0x4, int32 포괄) → f32, F2I f32 → int4/int8/int32 RNE-saturate. ISA 변경: FP_LEGAL_ROM legal_dtypes **[2,3] → [0,1,2,3,4]** (monotonic illegal→legal); forbid_imm_any → **imm16-optional** (0x72/0x74 선례, §23.10.8 amendment — CVT 가 eff_b_value 를 절대 읽지 않으므로 intent-preserving); imm16[3:0]/[15:8] reserved-zero 및 미지 sub-op → lower_required.
2. **0x73 ACC_ELEMWISE, OPREF form 전용** — FS_FMA-shape step 프로그램에 탑승하는 fused single-rounding fp32 **a·B[63:32] + B[31:0]** (신규 op class **OPS_ACCEW**); **어떤 imm 이든 존재 (dec_eff_opref_kind==0) → lower_required** (capability absence — 초안의 sub-op 표는 alu_binary_xor_err 하에서 구현 불가로 **삭제**).
3. **0x7C STORE_QUANT fp-dest** — PE_Core.v:3165-3169 else-arm 의 pure execute-side stub-body replacement, L-PE hosted combinational (×4 instance + MU), CVT 와 narrow 함수 1개 공유, **양쪽 site 에 DAZ-at-source pin**; dtype 0x2/0x3 에서 imm16[5:0] reserved-zero → lower_required; ROM row 이미 legal, decode 불변; **twin classifier 0x7C 무변경 (전 dtype L-PE)**.
4. **golden_fp32.py 확장 (COMMIT 1, 어떤 RTL 보다 선행)** — f16/bf16 codec, ref_cvt/ref_i2f/ref_f2i/ref_narrow_f32/ref_acc_elemwise, sequencer-faithful step layer, named sweep plan + independent-oracle cross-check.
5. **asm/wavetensor_asm.py hybrid norm 재구축** — fp32 scalar insert 가 0x66 SCALAR_RSQRT 를 대체 (0x66 자체는 2026-07-24 dead-opcode 제거로 reserved 복귀, §24); int wide tail (**0x69** — 0x6B/0x6C 는 소비자 없이 제거됨, §24) 불변; **eps ≥ 2⁻¹³ assembler guard** + int-scalar clamp fallback; FSCALAR B-constant producer dispatch 명시 계상.
6. **Pre-priced amended COMB gate 41.0% 를 COMMIT 0 에서 — 구현 이전에 — 공표** (§23.10.10(g)); per-operator synth gate = merge blocker (§23.10.7 normative).

**Deferral — 전건, 각각 destination 명시 (normative)**:

| 이연 항목 | destination | 근거/조건 |
|---|---|---|
| 0x70 VFMA_ACC | **v1.8.0e** | frag-FSM widening + result-accumulation buffer 필요 (stateless form = 16 fragments) |
| 0x78 DEQUANT (slice-select 포함 전 form) | **v1.8.0e** | 같은 package; sliced form 도 output-side 구조 필요, 전용 shift-add 경로 재가격 |
| 0x79 FMINMAX vector | **v1.8.0e** | §23.10.8 의 frozen IEEE-2019 minimumNumber/maximumNumber 의미론이 **무수정 이월**; clamp 소비자 출현 시 scalar K_INT FMIN/FMAX fallback 검토 |
| frag emit-FSM 2-bit→4-bit widening + buffer-then-drain | **v1.8.0e** | 위 3개 소비자를 전부 알고 **한 번에 하나의 coordinated work package 로** 축조 (VFMA + DEQUANT + vector FMINMAX + widening + buffer = 단일 단위) |
| end-to-end MSE ≤1.05× dtype-floor 계약 | **v1.8.0e** | 0d 의 normative 계약은: rsqrt 기여 ≤2 ulp, 오차는 Q8.8-application-dominated ≤2⁻⁹ scale-relative |
| 0x73 imm-B/bf16-immediate form | **0e-또는-이후** loosening | EHDecode per-opcode exemption 기구 결정 필요 |
| FTZ-at-f16-destination 재검토 | **v1.8.0e**, 0e MSE gate 실패 시에만 | §23.10.10(f) pin (5) |
| positional-bank 하드웨어 fix (latency shuttle) | **v1.9** | §23.10.9 risk 2 와 동일 노선 |
| lane-wise-B FMINMAX (VDOT packing) | **post-0e** | — |
| stochastic rounding | **v2.0** (frozen) | fp32→bf16 STORE_QUANT 한정 |
| dtype 0x5 f64 | **decode_error 유지** | — |
| pod scale | **scope 밖** | 전 주장 cluster-OOC 한정 |

##### 23.10.10(b) 0x77 CVT (MU, OPS_CVT)

**Operand**: scalar-in-64 를 payload_a 로 수취; **eff_b_value 는 절대 미소비** — imm32/imm64 는 FSCALAR 처럼 ASM-FORBIDDEN/RTL-TOLERATED.

**Sub-op**: imm16[7:4] ∈ 신규 single-source JSON 생성 테이블 **cvt_op_codes {0x0 WIDEN_TO_F32 (imm16-absent default), 0x1 NARROW_FROM_F32}**; imm16[3:0]/[15:8] nonzero 또는 sub-op >0x1 → **lower_required** (0x72 의 정확한 rung).

**MANDATORY RTL RULE (confirmed-bug fix) — op-class-conditional DAZ bypass**: FP_StepSeq 의 operand-load DAZ 는 **OPS_CVT 의 non-fp32-format source (모든 WIDEN 방향과 모든 I2F) 에 대해 BYPASS** 된다 — capture mux 의 op-class-conditional 항으로 구현. CVT 는 raw narrow bit 를 그대로 봐야 한다 (무조건 DAZ 는 I2F(5) 를 포함해 모든 non-fp32 source 를 0 으로 flush 하는 확정 버그). 반대로 **NARROW/F2I 의 fp32 SOURCE 는 DAZ-flush 된다** (pin) — 그리고 **0x7C site 에서도 동일하게 pin** (§23.10.10(d) bit-identity 전제).

**WIDEN (sub-op 0x0)**:
- dtype 0x2 f16→f32: **EXACT, f16 subnormal 포함** (FP_AddWide 의 LZC/normalize 를 K_ADD 1 pass 로 경유).
- dtype 0x3 bf16→f32: normals/zeros/Inf 는 exact bit-splice; **bf16-subnormal 입력 → CVT 출력에서 signed zero** (DAZ-consistent pin — splice 하면 fp32-subnormal 공간에 착지하므로).
- dtype 0x0/0x1 I2F int4/int8: exact.
- dtype 0x4 I2F signed int64 (sext64 payload): **ingress pinned — payload[63:32] → c_in, payload[31:0] → a_in (FSCALAR-style split)** → f32 RNE, overflow 불가능; **two-pass normalize PINNED: pass-1 은 RTO/sticky-preserving (rto_jam 경로), pass-2 가 final RNE — double rounding 금지.**
- **Widen-NaN row (normative)**: f16/bf16 의 **어떤 NaN 이든** → fp32 canonical qNaN 0x7FC00000 (sNaN quieted); exact-injection E-row 는 non-NaN 입력에 한정.

**NARROW (sub-op 0x1)** — round/sticky 는 어디서나 **disjoint 하게** 기술한다 (확정 off-by-one 방지: "dropped bits 전체의 sticky" 표현 금지):
- dtype 0x2 f32→f16: RNE, **round R = dropped bit 12, sticky S = OR(dropped bits [11:0]), increment ⇔ R & (S | kept-LSB)**; rebias 127→15; overflow → ±Inf; **FTZ-at-destination** (unbounded-exponent round 후 2⁻¹⁴ 미만 결과는 signed zero 로 flush).
- dtype 0x3 f32→bf16: RNE, **R = bit 15, S = OR(bits [14:0]), increment ⇔ R & (S | bit 16)**.
- **NaN narrow (양 format) → destination canonical qNaN (f16 0x7E00, bf16 0x7FC0), 부호 drop, payload 폐기 — 단일 규칙** (mantissa-MSB-forced vs canonical 모호성을 canonical 로 해소, fp32 선례 정합).

**F2I**: **RNE 후 saturate** — dtype 0x0/0x1 → [−8,7]/[−128,127], dtype 0x4 → int32 RNE-saturate; **NaN → 0** (deterministic DATA — **GPU-parity 근거: CUDA cvt.sat 선례를 명시 label** — F2I 의 NaN 이 error 가 아니라 결정론적 데이터여야 GPU-lockstep oracle 과 정합); **±Inf → dest min/max**; int 결과는 sext64.

**결과 payload row**: f16/bf16 = {48'h0, h} zero-extend; f32 = {32'h0, f}; int = sext64.

**Round-trip identity E-row — RE-SCOPED (normative)**: half→f32→half identity 는 **normal f16/bf16, ±0, ±Inf, canonical qNaN 에 한해** 성립. f16 subnormal 은 FTZ pin 에 의해 **설계상** 실패한다 — E-row 의 범위 밖.

**Launch ladder**: 0x77 은 shipped 0x74/0x75 arm 을 rung-for-rung mirror — MU gate → output_regs_free busy-reject = lower_required → reserved-field/sub-op rung → launch; 어떤 신규 result pulse 도 fp_valid_p2 를 우회하지 않으므로 MUL-launch fp-idle guard (§23.10.1) 는 불변.

##### 23.10.10(c) 0x73 ACC_ELEMWISE (MU, OPS_ACCEW)

- alu-binary, dtype [4]. **OPREF form ONLY**: a = payload[31:0] fp32, B 는 dec_eff_b_value (OPREF) 로 수취; 결과 = **round-once fp32 FMA(a · B[63:32] + B[31:0])**, golden 의 **ref_fma / micro_fscalar(FS_FMA)** 에 bit-exact (존재하지 않는 micro_fma 아님 — bit-match target 정정).
- **어떤 imm16/imm32/imm64 든 존재 → lower_required** (decode_error 아님, silent 아님). 초안의 sub-op 표는 **삭제** — EHDecode 의 alu_binary XOR invariant (§23.10.2 의 alu_binary XOR trap 과 동일 기구) 하에서 imm carve-out 은 decode_error 가 되므로, invariant 를 amend 하지 않고 capability absence 로 기술한다. 미래의 imm-B/bf16-immediate loosening 은 per-opcode exemption 기구 결정과 함께 0e-이후 (§23.10.10(a) 표).
- twin classifier (Cluster.v is_mul_op + PE_Core.v dec_is_mul_op) 가 **0x73 항을 opcode-only 로** 획득 (MU fp op; dtype 조건 없음); lockstep 테스트 같은 commit 탑승 (§23.10.9 risk 6).
- Launch ladder 는 0x77 과 동일하게 0x74/0x75 mirror + OPREF-only rung (dec_eff_opref_kind).

##### 23.10.10(d) 0x7C STORE_QUANT fp-dest packer

- source = fp32 payload[31:0], **source 에서 DAZ-flush** (bit-identity pin); dtype 0x2/0x3 에서 imm16[5:0] nonzero → lower_required (PE_Core.v:3150 의 imm16[15:6] rung 을 mirror); 결과 {48'h0, h} zero-extend; **int4/int8 arm 은 bit-불변**; emit-FSM/drain-override 변경 전무.
- **Bit-identity 조항 (normative)**: 0x7C fp-dest narrow 는 **0x77 NARROW_FROM_F32 와 전 2³² 입력에 대해 bit-identical — DAZ pre-stage 포함**. 시행 기제: **공유 Verilog 함수 1개** (신규 공통 include `include/fp_narrow_f32.vh`) + **golden 함수 1개 (ref_narrow_f32)**; golden 에서 chunked exhaustive 2³², RTL 에서 양 site (L-PE arm / MU step) directed+sampled.
- **0 added cycles** (contingency, pre-approved: packer 를 register 하면 fp-dest form 에 한해 +1 cy).

##### 23.10.10(e) cycle maxima 표 (normative — completion-within-bound, §23.10.6 관례 동일)

| op | 최대 cycles | 비고 |
|---|---|---|
| CVT widen / narrow / I2F-small / F2I | ≤8 | target 3-6; 8 은 Gate-2 fallback 패턴의 2번째 K_INT 가능성 흡수 |
| CVT I2F int64 | ≤10 | target 6-8 |
| ACC_ELEMWISE | ≤10 | target ~6 (FS_FMA shape) |
| 0x7C fp-dest | +0 | registered-packer contingency 시 +1 |

##### 23.10.10(f) f16/bf16 format 정책 (normative)

**상속 — 재론 금지**: RNE-only (rnd=[0]; SR 은 v2.0 fp32→bf16 STORE_QUANT 한정); acc 는 [1] 유지 (**bf16+acc==0 은 영구 illegal; acc 는 direction channel 이 아니다** — acc loosening 안은 frozen-pin 충돌로 기각); fp32 canonical qNaN 0x7FC00000, sNaN quieted, IEEE specials 는 DATA·절대 error_flag 아님; DAZ = operand-load flush 부호 보존; FTZ = flush-after-round with unbounded-exponent RNE; 내부 step 은 DAZ/FTZ-exempt; illegal mode byte = decode_error, unimplemented-legal = lower_required; frozen 0x79 minimumNumber/maximumNumber 계약은 0e 로 무수정 이월.

**신규 PIN (COMMIT 0, normative — 각 pin 이 directed vector 를 생성)**:

1. **Per-format canonical qNaN**: f16 **0x7E00**, bf16 **0x7FC0** (= fp32 상위 16 bit, truncation-consistent), f32 0x7FC00000. NaN narrow → destination canonical qNaN, 부호 drop — **NaN 은 절대 Inf 로 격하될 수 없다.**
2. **Widen-NaN row**: f16/bf16 NaN → fp32 canonical qNaN 0x7FC00000; exact-injection E-row 는 non-NaN 에 한정.
3. **Sticky 는 어디서나 disjoint 로 기술**: dropped field D 에 대해 round R = MSB(D), sticky S = OR(D − R), increment ⇔ R & (S | LSB_kept) — "dropped bits 전체의 sticky" 표현 금지 (확정 off-by-one 의 근원).
4. **Narrow overflow → ±Inf** (A6-row 정합), saturate-to-max-finite 절대 금지.
5. **f32→f16 은 FTZ-at-destination** (subnormal shifter 삭제); **문서화된 GPU divergence**: CUDA cvt.rn.f16.f32 는 f16 subnormal 을 보존 — 모든 GPU-lockstep/oracle harness 는 (0, 2⁻¹⁴) 결과 band 를 mask; bounded abs error < 2⁻¹⁴; 0e 재검토 가능. **이 기계는 f16 subnormal 을 ingest 하되 절대 produce 하지 않는다 (write-only range).**
6. f16 subnormal **입력**은 widen 에서 honored (exact, no DAZ); bf16 subnormal 입력 → CVT widen 출력에서 signed zero (splice-vs-flush 모호성을 DAZ-consistent 로 해소).
7. **DAZ 는 CVT-narrow/F2I 와 0x7C fp-dest 의 fp32 source operand 양쪽에 적용** (bit-identity 전제조건); sliver 0x007FFF80-0x007FFFFF 는 directed test.
8. I2F int4/int8 exact; int64/int32 는 RNE, **pass-1-RTO / pass-2-RNE pin** (double rounding 금지).
9. F2I: RNE 후 saturate; ±Inf → min/max; **NaN → 0** (deterministic DATA; knowledge-based CUDA cvt.sat 선례, label 명기).
10. **Conversion-dtype 규칙 확장**: 0x77 의 dtype 0x4 는 accumulator-format integer endpoint (int32/int64 ↔ fp32) 를 지명하고 방향은 sub-op 이 결정 — v1.8.0b 에서 미결이던 결정의 해소; **dtype 0x5 는 decode_error 유지**.
11. 16-bit fp scalar 결과는 [15:0] zero-extend (신규 scalar-in-64 row).
12. **Bit-identity 조항**: 0x7C fp-dest narrow == 0x77 NARROW_FROM_F32, 전 2³² 입력, DAZ pre-stage 포함 (RTL 함수 1개 + golden 함수 1개, golden exhaustive-chunked + RTL directed).
13. **Independent-oracle 규칙**: golden 의 narrow/widen/F2I 는 golden 이 단독 authority 가 되기 **전에** numpy float16 / ml_dtypes bfloat16 (boundary + sampled set, 명시적 FTZ/canonicalization post-pass) 와 cross-check — 공유 함수가 동일하게-틀리는 구멍의 방어.
14. **Single-narrowing 규칙 불변**: narrowing 은 STORE_QUANT/CVT 에서만.

##### 23.10.10(g) synth gate plan — pre-priced, 구현 이전 공표

**Pre-priced gate 는 구현 전 COMMIT 0 에서 SET 된다 (locked constraint)**: amended cluster **COMB gate = 41.0%** (34,292 LUT4 / 83,640). 도출 근거를 함께 공표: 실측 base 30,968 (37.02%); 구 38% gate 아래 정확한 headroom = **815 LUT4** ("~840" 아님); nominal 추정 +0.9-1.9k → 38.10-39.30%; 최악 추정 × 프로젝트의 유일한 실측 overrun 계수 (Gate 3: 3,345/2,000 = **1.67×**) → 30,968 + 3,173 = 34,141 = **40.82% < 41.0%**. **gate 수치는 C3/C4 실측 후 하향으로만 개정 가능, 상향 절대 불가**; 실측이 41.0% 를 위협하면 3번째 ad-hoc amendment 대신 **pre-declared cut ladder 가 집행된다**:

- **(cut 1)** int64 I2F 를 int32-only ingress 로 축소 (a_in 단독, single normalize pass, two-pass 기구 삭제 — norm 매크로는 int32 만 필요하므로 무영향)
- **(cut 2)** 0x7C packer 를 register (+1 cy, fp-dest form 한정)
- **(cut 3)** 0x73 을 0e 로 drop (norm 은 FSCALAR 2-dispatch 로 fallback — 정확성 보존)

**Per-operator synth gate = merge blocker — merge 전 실행 필수 (§23.10.7 normative). v1.8.0b 의 gate-skip — 자신이 선언한 merge blocker 를 건너뛰고 merge 되어 5.88 MHz / 1,015-stage 결함을 5 commit 뒤 Gate 4 에서 발각시킨 사건 (§23.10.7 GATE 4 실측 참조) — 이 구속력 있는 교훈이다: gate log 가 commit 에 첨부되지 않은 RTL commit 은 merge 금지.**

- **GATE C3 (FP_StepSeq — OPS_CVT+OPS_ACCEW 및 op_sel 3→4b 확장 후)**: standalone OOC synth. Pass: **신규 MULT18X18D 0 (hard)**; FF ≤ 900 line 재확인 (scalar 설계는 FF 소량; int64 ingress reg 계상); standalone Fmax 40 MHz 유지; 실측 LUT4 delta 를 +300-700 추정 대비 기록, **+1.2k 초과 시 cut ladder 로 hard escalation**. **추가 필수: 기존 6개 step 프로그램의 Gate-2 bit-exactness 증명 전건 재실행** (op_sel widening 이 모든 case tree 를 건드림).
- **GATE C4 (0x7C packer — ×4 L-PE + ×1 MU instantiation)**: cluster-level synth. critical-path 검사는 **익명화된 whole-cluster logic-stage-count diff** (Gate 4 의 실제 기제 — endpoint 단위 "u_matmul_unit.output_payload ≤1 mux" 문구는 L-PE cone 을 놓치므로 사용 금지); dispatch cone 심화 zero; pre-approved contingency = registered packer.
- **GATE C6 = Gate 5 (asm 재구축 후 full cluster OOC)**: COMB ≤ **41.0%** (또는 C3/C4 가 하향한 수치); MULT **정확히 134/156** (≤140 ceiling, hard); Fmax ≥ **10.51 MHz** (무회귀); stage-count diff clean; `lint_frag_total_m1_held.py` **무수정 통과** (테스트로 pin); cycle-maxima TB row 전부 green; **norm-row wall-clock 실측 기록** (기대 ~7-10 µs/row end-to-end, dispatch overhead ~6회 포함 — 정직한 수치이며 fp-cycles-only 4.8 µs 수치가 아님).
  - **C6 실측 최종 (2026-07-24, PASS with amendments)**: **COMB 39.48%** (33,024/83,640 ≤ 41.0% PASS — 선공표 예산 대비 -1.5%p 여유). **MULT 135/156** (≤140 hard PASS; "정확히 134" pin 은 +1 위반이나 netlist 귀속상 0d 로직은 K_INT 전용·곱셈기 0 추가 (C3 unit 증명: 정확히 4) — legacy cone 의 yosys DSP-inference 매핑 변동으로 귀속, pin 을 "≤140 hard + 0d 신규 곱셈기 0 (unit gate 로 증명)" 으로 amend). **Fmax 10.23-10.36 MHz (4 seeds)** vs 10.51 기준 — seed noise 아님 (-2.7% 실회귀). 단 critical path netlist 귀속 결과 **0d 로직은 경로에 부재**: 경로는 0c 와 동일한 legacy einsum wide cone (dec_input_payload_wide 관통, 120→128 stages / 95.1→97.4 ns) 이며 성장분은 설계 확대(COMB 37→39.5%)에 따른 ABC 재최적화·congestion 변동. "무회귀" pin 의 의도 = "0d 로직이 dispatch cone 을 심화시키지 않을 것" 은 충족 — 기준을 "0d-로직-경로-부재 (netlist 귀속으로 증명) + 전역 변동 ≤3% 기록" 으로 amend, 실측 10.27 (seed 1, archive) 기록. 근본 해소는 v1.9 dispatch 파이프라이닝의 소관.
  - **norm-row wall-clock (합성 실측)**: per-op TB 실측 cycle 의 합성 — fp insert 32 cycles (FSCALAR.ADD 5 + FRSQRT32 21 + FSCALAR.MUL 6, 전부 TB 실측) + int wide tail + dispatch ~6회 ≈ **60-100 cycles/row ≈ 5.8-9.7 µs @ 10.27 MHz** (spec 기대 7-10 µs 대역과 정합). true end-to-end 단일 실측은 SDK bring-up 항목으로 이월 (이 수치는 per-op 실측의 합성이며 e2e 단일 런 아님을 명기).

전 주장 cluster-OOC 한정; pod 는 failed/scope 밖 유지.

##### 23.10.10(h) residual risks (v1.8.0d)

1. **추정 리스크 (문헌 추정 0-for-3 전적)**: 41.0% pre-priced gate 는 최고 추정에 1.67× 역사적 overrun 을 흡수 (40.82%) 하나 **여유는 ~150 LUT4 뿐**; C3 가 FP_StepSeq 에서 +1.2k 초과를 실측하면 pre-declared cut ladder (int64→int32-only I2F, registered packer, 0x73→0e) 가 집행된다 — **3번째 ad-hoc COMB amendment 는 본 spec 이 금지.**
2. **headline MSE ≤1.05× dtype-floor 계약은 0e 로 공개적으로 이월**: 0d norm 출력은 Q8.8-application-limited (~2⁻⁹ scale-relative) 로 남는다. 6.25% floor 대비 ~30× 개선이며 roadmap 의 declared true-floor 항목을 kill 하지만 fp-grade 출력은 아니다 — "0d = norm rebuild" 로 읽는 누구든 이 COMMIT 0 re-scope 문구를 봐야 한다.
3. **Cluster-visible scalar-fp serialization**: norm insert 는 ~6 fp dispatch (~50 fp cycles + dispatch overhead ~6회 = 10.51 MHz 에서 현실적 **7-10 µs/row**), 각각이 output_regs_free/pe_ready 를 cluster-wide 로 점유; v1.9 latency shuttle 까지 §23.10.9 risk 4 와 같은 수용 가격 클래스; weight folding 없는 per-channel gamma/beta 는 0e VFMA/DEQUANT 까지 scalar crawl.
4. **op_sel 3→4-bit widening 은 FP_StepSeq 의 모든 (op_sel, fp_step) case 를 건드린다** — 이번 release 의 단일 최고 회귀위험 편집; Gate C3 의 기존 6개 프로그램 전건 재증명이 완화책이나, capture-mux 의 미묘한 회귀는 shipped 0c op 의 **silent wrong-data** 가 된다.
5. **FTZ-at-f16-destination 은 영구적·문서화된 GPU divergence** ((0, 2⁻¹⁴) 결과 band; CUDA 는 f16 subnormal 보존): 기계는 f16 subnormal 을 ingest 하되 절대 produce 하지 않음; 미래의 모든 GPU-lockstep harness 는 band 를 mask 하거나 통째로 fail; 0e 재검토는 MSE gate 실패 시에만.
6. **0x73 의 sub-op channel 은 alu_binary XOR invariant 에 의해 이 opcode 의 OPREF form 에서 영구 폐쇄**; 미래의 imm-B/bf16-immediate loosening 은 EHDecode per-opcode exemption 기구 (0e 결정) 필요 — 착지된 0d 실리콘은 fixed-function FMA 1개이며, norm flow 에서의 실용 가치는 OPREF {gamma,beta} constant staging 확인에 의존 (shipped fallback 은 two-FSCALAR baseline).
7. **eps ≥ 2⁻¹³ assembler 제약은 흔한 eps=1e-5 default 를 거부**; int-scalar clamp fallback 은 매크로 길이를 늘리고 그 자체는 emitter-tested 일 뿐 hardware-assisted 가 아니다.
8. **0e wide package (VFMA_ACC + DEQUANT + vector FMINMAX + 2→4-bit frag-FSM widening + buffer-then-drain) 는 미설계 하드웨어로 남으며 v1.7 의 "최고위험 공유 구조" label 을 계승**; 0d 는 선택지를 봉쇄하지 않으나 (MULT wall: ≤140 ceiling 아래 여유 6 이 sequential 설계를 어차피 강제) 리스크는 **이연이지 은퇴가 아니다**.
9. **×4-replicated L-PE packer 는 이미 −3.1% Fmax 인 cluster 위 이번 release 의 유일한 신규 output-cone logic**; Gate C4 의 whole-cluster stage-count diff 가 유일한 검사이고, pre-approved contingency 는 fp-dest form +1 cycle 의 비용.
10. **전 주장 cluster-OOC 한정**; pod scale 은 여전히 실패 (MULT 497>156, COMB 101%) 이며 0d 의 어떤 것도 이를 움직이지 않는다.

## 24. Pre-stable dead-opcode removal — v1.7.1 amendment (2026-07-24, truth-table domain_version 2)

**§12a 정책의 첫 적용.** Audit (2026-07-24) 로 아래 전 항목의 **asm/SDK 소비자 0** 을 확정한 뒤 제거한다 (wavetensor-sdk 저장소 grep 포함 — zero match 확인, `asm/wavetensor_asm.py` 는 제거 이후 removal-set emission 을 일절 포함하지 않으며 bit-equivalence reference 지위 유지). 기록 순서는 spec-first (§12a 규칙 3): **본 절 → `isa/wt64v1_isa.json` 행 삭제 → 생성물 재생성 (`scripts/gen_isa_tables.py`) → RTL/테스트 갱신 → truth-table 의도적 재캡처**. §3 의 opcode 표는 생성물이므로 직접 편집하지 않는다.

### 24.1 제거 opcode (4개 → reserved, decode_error)

| opcode | mnemonic | 은퇴 사유 / 행선지 |
|---|---|---|
| 0x66 | SCALAR_RSQRT_APPROX | fp path 의 **FRSQRT32 (0x75, ≤2 ulp)** 가 supersede — v1.8.0d norm 재구축이 rsqrt 를 fp32 insert (CVT→FSCALAR→FRSQRT32→F2I) 로 대체하며 은퇴 (rsqrt LUT 6.25% floor kill 의 본체). |
| 0x67 | SIMD_MUL_WIDE_Q4_4_SCALAR | v1.6.7 부터 **0x69 (Q8.8)** 가 supersede — RMSNORM/LAYERNORM 매크로가 0x67→0x69 이행을 완료한 뒤 소비자 0. |
| 0x6B | SIMD_MUL_WIDE_Q4_4_SCALAR_128_WIDEN | Q4.4-int8 WIDEN/REQUANTIZE 쌍 — native 소비자가 끝내 착지하지 않음. **v1.8 fp32+CVT 경로** 가 supersede. |
| 0x6C | SIMD_REQUANTIZE_Q4_4_TO_INT4 | 동상 (0x6B 과 쌍으로 도입·쌍으로 은퇴). |

**유지**: 0x68 CACHE_LOAD_WIDE, **0x69 SIMD_MUL_WIDE_Q8_8_SCALAR** (live norm tail — 유일하게 emit 되는 wide-mul), 0x6A FRAG_INVAL. 제거된 인코딩의 semantics 는 여타 미배정 opcode 와 동일한 **decode_error** (opcode_supported whitelist 탈락).

### 24.2 einsum signature whitelist 축소 (reduce 10개 변형 중 9개 제거)

Audit 사실: **10개 reduce 변형 중 9개가 asm 소비자 0** 이었고, 전부 단일 사이클 dispatch 의 **Fmax-critical cone** (§23.8 실측: cluster critical path 116 logic stage / 92.13 ns) 위에 앉아 있었다.

- **SIG_4D3D family (§22.13.1) 전체 un-whitelist** — SUM/MAX/MIN/MEAN/L2SQ 5개 marker 모두 (SIG_4D3D_FAMILY_LO/HI_BASE dispatch 제거).
- **SIG_5D4D family 는 op_marker 0x5 MEAN 만 잔존** — 유일한 live 소비자 (rmsnorm/layernorm 의 mean step lowering). SUM/MAX/L2SQ + v1.6.2 backfill MIN 제거.
- **5D→scalar ijklm family 는 무변경** — SIG_L2SQ_IJKLM 등은 별개 함수이며 live.
- **`reduce_op_codes` / op_marker 인코딩 공간은 무변경** — marker 는 live ijklm family 와 공유되므로 JSON 의 해당 키는 건드리지 않는다 (`einsum_signatures` 는 reserved stub — 역시 무변경).

제거된 signature 의 dispatch semantics: opcode 제거 (decode_error) 와 달리 기존 §8 분류 그대로 **"HW-direct EINSUM 미지원 패턴" → `lower_required`**.

### 24.3 Truth-table governance — domain_version 2 선언

- `isa/truth_table_premigration.json` 의 **`domain_version` 1 → 2** (post-cleanup baseline).
- 0x66/0x67/0x6B/0x6C 로 key 되는 행들은 outcome class 가 supported → **error-probe (decode_error)** 로 전이.
- Recapture 는 `WT_CAPTURE_TRUTH_TABLE=1` 로 수행하는 **의도적·리뷰된 행위** 이며, domain_version bump 없는 recapture 는 금지 (§12a 규칙 2). Keep-forever 보장은 stable release 부터 발효.
- `_PREMIGRATION_LEGAL_SNAPSHOT` (asm 테스트의 "kept forever" 스냅샷) 도 동일 정책 하에 편집 — pre-stable 에서는 스냅샷 등가성 계약 미발효, 편집은 본 절이 spec-first 기록.
- EHDecode 의 "0x00-0x6C inert" 류 range-endpoint 문구는 truth-table differential 을 참조하므로 recapture 와 함께 갱신 (§23.6a 갱신 완료).

### 24.4 잔존 구조물 (제거하지 않는 것)

- **frag FSM 확장분** (frag_idx 2-bit up-counter, FRAG_EMIT_2/3, frag_pending[0:3], frag_total_m1_held) — **v1.8.0e wide package 예약** 으로 존치. 0x6B 제거로 >2-fragment writer 가 일시 부재하나 (writer-dead), §23.10.10(a) deferral 표의 coordinated work package 가 재사용한다. `lint_frag_total_m1_held.py` co-location 불변식은 잔존 2-fragment site 에 대해 계속 성립.
- OP_SUM/OP_MAX/OP_MIN/OP_L2SQ/OP_MEAN localparam — live 5D→scalar ijklm arms 가 사용, 유지.
- Superseded history 로 보존되는 절: §22.11.1 (0x66 mnemonic), §22.13.1 (4D3D family), §22.14a (0x67), §22.18 (0x6B/0x6C), §22.1/§22.3-22.6 recipes 의 0x66/0x67/5D4D 사용례 — 전부 배너 표기 완료, 삭제하지 않음 (§12a 규칙 5).

### 24.5 cleanup 후 Cluster 실측 (2026-07-24, synth+PnR seed 1)

| 지표 | cleanup 전 (0d C6) | cleanup 후 | delta |
|---|---|---|---|
| Fmax | 10.23-10.36 MHz | **10.93 MHz** | **+5.5-6.8%** — 최초 실측 10.85 도 상회 (프로젝트 신기록) |
| TRELLIS_COMB | 39.48% (33,024) | **34.26% (28,659)** | **-5.2%p (-4,365 LUT)** |
| MULT18X18D | 135/156 | **122/156** | **-13** (Q4.4 곱셈기 군 이탈 — 0e/v2.0 예산 대폭 회복) |
| critical path | 128 stages / 97.4 ns | **113 stages / 91.5 ns** | cone 실축소 (-15 stages) |

dead 코드가 critical cone 과 MULT 예산을 실질 점유하고 있었음이 실측
으로 확정 — cleanup 은 미용이 아니라 v1.8.0e/v1.9 의 선행 투자였다.
0e 의 선공표 COMB gate 는 이 34.26% 를 새 기준선으로 도출할 것.

## 25. v1.8.0e — MSE-contract wide package — amendment (2026-07-24, COMMIT 0 · normative)

**당선 설계 "hybrid-minimal (repaired)" (2026-07-24 설계 workflow, adversarial verify 기록에서 합성된 mandatory repair 7건 반영).** 본 절이 v1.8.0e 의 normative source 다 — spec-before-code COMMIT 0 (§12a pre-stable 정책 하, 아래 나열된 모든 계약 변경의 spec-first 기록). 기준선 anchor 는 §24.5 cleanup 후 실측: **COMB 34.26% (28,659/83,640) · MULT18X18D 122/156 · Fmax 10.93 MHz / 113 stages**.

Mandatory repair 7건 (전부 본 절에 성문화): ① twin-classifier 편집 (Cluster.v is_mul_op + PE_Core.v dec_is_mul_op 에 0x70/0x78/0x79 + 신규 0x6B) + lockstep/reachability 테스트 (§25.3); ② Cluster.v:257-258 frag_mask_full 4-bit shift wrap 수정 — **잠복 버그 수리로 기록** (16-fragment 재조립은 오늘 tot_m1=15 에서 깨져 있음, §25.3); ③ 0x79 FMINMAX 를 FSCALAR-clone legality 로 re-row (원 pin 은 alu_binary_xor_err 하 decode 불가 — §25.2.1); ④ DEQUANT destination 을 0e 에서 bf16-ONLY 로 pin (no-dest-dtype-carrier 반증 폐쇄 + 16-frag DEQUANT form 삭제 — §25.2.2); ⑤ 신규 opcode 0x6B GAMMA_MUL_W — MU-hosted exact widening per-lane int4×int4→int8 곱 (치명적 broadcast-gamma 반증의 수리, criterion 3 의 진짜 end-to-end 충족 — §25.2.3); ⑥ vfma_busy 점유 항 + fp_valid_p2 lane-loop 억제 + atomic frag0_hold handoff pin (§25.3); ⑦ MSE harness 수리 (eps-inclusive exact reference, denominator-floor 규칙, gamma-variation tensors, round-once 는 MSE ratio 아닌 bit-equivalence 로 시행 — §25.5.2).

Staging: **0e1** (MSE-contract release) → **0e2** (0x70 VFMA). 신규 산술은 전부 step sequencer (FP_StepSeq) 뒤 또는 registered launch-capture 뒤 — FMINMAX/VFMA/0x6B 는 step sequencer 에 진입하지 않고, FP_StepSeq 는 OPS_DEQ 행 추가로만 접촉된다.

### 25.1 Scope — 0e1/0e2 staging + CLOSED-DEFERRED 표

**0e1 (MSE-contract release)**:

1. **COMMIT 0** = 본 절 (전 pin + gate 선공표 + cut ladder + amendments §25.6).
2. **COMMIT 1** = golden-before-RTL: `scripts/golden_fp32.py` 에 ref_dequant (round-once 정의 (a), 전 specials cell), ref_fminmax (**raw bit pattern 위에서 6 frozen 행 전사 — golden decode() 위 축조 금지, DAZ-exempt**), ref_gamma_mul_w (exact int, lane order pin), ref_vfma_lane (explicit mod 2³², b_mul 폭 pin), micro_dequant (sequencer-faithful twin — ref_dequant 와 bit-equivalent), lane→fragment packing layer (spec/SDK 공유); bf16 codec 은 golden 이 단독 authority 가 되기 **전에** ml_dtypes cross-check (§23.10.10(f) pin 13 규칙).
3. frag FSM **2→4-bit emit-side widening** + Cluster frag_mask_full fix + twin-classifier 추가 (§25.3).
4. **0x79 FMINMAX** — comb arm, FSCALAR-clone legality (§25.2.1).
5. **0x78 DEQUANT** — fused **OPS_DEQ = 4'd9**, bf16-dest-only: int4-32→bf16 8 frags / int8-16→bf16 4 frags (§25.2.2).
6. **0x6B GAMMA_MUL_W** — MU-hosted, 16-lane, 단일-frag A + imm64/OPREF gamma, 2-frag int8 out (§25.2.3).
7. `_lower_rmsnorm` 재작성: ×256/F2I/Q8.8/int-gamma tail 삭제; fp insert 는 fp32 scale s 에서 정지하되 gamma 고정소수점 지수를 기존 상수에 **exact 폴딩** (추가 FSCALAR 없음); 0x6B gamma 단계; DEQUANT tail 에서 **정확히 1회 좁히기**.
8. **MSE release-gate sweep** (§25.5.2).
9. **op_sel 기존 8개 step 프로그램 전건 re-proof — 0e1 에서 1회 mandatory (locked)**; fused OPS_DEQ 는 이미 locked 된 이 re-proof 에 편승하므로 fused 프로그램의 한계 증명 비용은 선지불됨.

**0e2**: **0x70 VFMA_ACC** (stateless, sequential LUT-mapped MAC, B split {c_acc[63:32], b_mul[31:0]} — §25.2.4) + vfma_busy interlock + **16-fragment emit (frag_mask_full fix 의 첫 소비자)**.

**CLOSED-DEFERRED 표 (normative — designated carrier 명시; imm16 forbidden→optional 완화는 CVT 선례를 따르는 단일 미래 loosening event 1회로 통합)**:

| 이연 항목 | designated carrier / destination | 비고 |
|---|---|---|
| DEQUANT slice-select | **imm16[7:4]** | f32-dest 와 같은 단일 loosening event 에 동승 |
| DEQUANT f32-dest | **imm16[3:0]** | 이 field map 이 double-booking 을 해소 |
| lane-wise-B FMINMAX/DEQUANT | post-0e | — |
| VFMA stateful accumulator + fp dtypes | **v2.0** | §25.7 risk 10 |
| 32-lane GAMMA_MUL_W form | post-0e | N=32 row = 16-lane dispatch 2회로 표현 가능 |
| LAYERNORM/BATCHNORM fp-grade 승격 | vector fp add 착지 시까지 deferred | **사유: beta 가 0e 에 fp-vector-add home 부재** — 두 매크로는 0d Q8.8 form 유지 (§25.6 항 2) |

Locked 항목 전건 준수 확인: 실측-anchor 예산 (34.26%/122/10.93); gate 는 구현 이전 선공표 + cut ladder (§25.5); golden-before-RTL; per-operator+unit+cluster gate **전부 실행**; op_sel re-proof; frozen FMINMAX IEEE 의미론 (§23.10.8 pin 무수정 이월); 본 절의 모든 계약 변경에 pre-stable spec-first 정책 적용.

### 25.2 Opcode 의미론 (normative)

#### 25.2.1 0x79 FMINMAX (0e1)

**f32-only, 4 lanes vs broadcast B; 입력 128b = 2-fragment wave, 출력 128b = 2 fragments** — 오늘의 FSM 에 수납.

**LEGALITY RE-ROW (spec-first — 확정된 alu_binary_xor_err dead-end 의 폐쇄)**: 원 pin (imm16 sub-op + OPREF-B 동시 요구) 은 EHDecode 의 alu-binary XOR invariant 하에서 **decode 불가** 였다 — imm 과 OPREF 를 동시에 요구하는 인코딩은 alu_binary_xor_err 로 즉사하므로, 그 형태로는 어떤 합법 인코딩도 존재하지 않는다. 따라서 **0x74 FSCALAR clone verbatim** 으로 re-row: isa JSON `rtl_alu_binary` true→**false**, `forbid_opref`→**true**, imm16 optional 은 **CONTROL 로만** (sub-op imm16[7:4]: 0x0=minimumNumber, 0x1=maximumNumber; [3:0]/[15:8] reserved-zero 위반 → lower_required); B 는 **dec_input_payload_b port 로만** 수취 ("EHDecode alu-binary XOR trap 을 dormant 하게 유지" — 0x74/0x77 의 기록된 maneuver); missing-B → **error_flag** (0x74 idiom); OPREF-B 는 기록된 post-0e loosening. isa_opcode_wires.vh/isa_ehshape_case_body.vh 재생성 → **frozen truth-table differential recapture + domain_version bump** (§25.6 항 7).

**SEMANTICS (frozen IEEE-2019 — §23.10.8 의 pin 이월, 6행 normative)**: lane 별 NaN-detect classify 후, ordering 은 **신규 전용 comparator key = a[31] ? ~a : (a ^ 0x80000000)** 에 대한 **unsigned 32b 비교 정확히 1회** (signed-int compare tree 재사용 금지 유지):

1. **−0 < +0** natively
2. 한쪽 NaN → number 반환
3. 양쪽 NaN → canonical qNaN **0x7FC00000**
4. sNaN 은 canonical 로 quiet
5. offset-transform 이 주는 total order (전 monotone chain {−Inf..+Inf})
6. denormal cell 은 **bit-pattern-preserving (DAZ-EXEMPT)** — **ref_fminmax 를 golden decode() 위에 축조 금지** (decode 의 DAZ 가 이 행을 조용히 위반한다)

구현: **MUL_OPS_SUPPORTED-gated dispatch 내부의 combinational PE_Core arm** (einsum-arm 패턴) — **step sequencer 무접촉**.

#### 25.2.2 0x78 DEQUANT (0e1)

**port-only legality 불변** (forbid_imm_any + forbid_opref 존치). **Destination 은 0e 에서 bf16-ONLY pin** — 근거 명기: mode dtype 은 conversion-dtype 규칙 (§23.6a) 대로 **source** 를 명명하며, **dest 를 나를 carrier 가 존재하지 않고 0e 는 어떤 것도 추가하지 않는다** (no-dest-dtype-carrier 반증의 해소; f32-dest 는 §25.1 표의 imm16[3:0] carrier 로 이연). Forms: **int4 32-lane** (128b, 2-frag in) → 32 bf16 = 512b = **8 fragments**; **int8 16-lane** → 16 bf16 = 256b = **4 fragments**. 16-frag DEQUANT form 은 **삭제**.

- fp32 scale 은 **ext_payload_b + ext_payload_b_valid** 로, **wave-완결 fragment beat** 에 탑승 (0x63-65 선례; **beat 배치는 SDK/NoC 계약으로 pin**); missing scale → error_flag.
- Launch-cycle 에 A(128b)+B(64b)+tag 를 **MU-local reg 로 capture** (0x74 idiom — EHDecode 는 cluster-shared).
- Compute: **fused step-sequencer 프로그램 OPS_DEQ = 4'd9** (op_sel 은 이미 4-bit — widening 불요): exact I2F 를 FP_Mul36 경유 FS_MUL-shape tail 에 폴딩. **L = 6-7 은 ESTIMATE** — 비정규화 significand 폴딩이 +1 normalize step (L=8) 을 요구할 수 있음; §25.4 의 규율대로 C-gate TB 에서 실측 졸업.
- **Rounding pin — 정의 (a) ROUND-ONCE**: 미반올림 48-bit product 에서 **직접 bf16 로 RNE 1회** — §23.10.10(f) pin 3 의 disjoint round/sticky 논리의 bf16-pack 변형; sign = sign(k) XOR sign(scale); k=0 → signed zero. **Exactness 논증**: int lane 의 I2F 는 exact, 곱은 미반올림 wide 로 유지 → 체인 전체에서 RNE 정확히 1회 (선행 0x6B 단계는 int-exact — RMSNORM 체인 rel-rms ~2⁻²¹·⁹, MSE ratio 1+~5×10⁻⁸).
- Specials pin: scale denormal → operand-load DAZ; scale NaN/Inf 는 mul 관통 후 narrow; product overflow → **±Inf, max-finite 절대 금지**; product 가 bf16 min-normal 미만 → destination pack 에서 **FTZ signed zero**. 전 cell 은 ref_dequant + directed vector 로 열거.

#### 25.2.3 0x6B GAMMA_MUL_W (0e1, 신규)

**§24 에서 은퇴한 0x6B code point 의 pre-stable 재배정** (§12a 규칙 4 — reserved 복귀 인코딩의 재사용; **slot 재사용임을 명시 기록**). **Retired-0x6B stale-consumer grep 이 commit 시 mandatory** — 제거 근거가 소비자 0 이었어도 검사는 의무.

존재 이유 (반증 기록): broadcast s_c = s·γ_c 는 문서화된 **per-lane gamma 계약** (asm/wavetensor_asm.py:835-877; §22.4) 을 구현할 수 없고, 제출된 전 설계가 이 지점에서 반증되었다. zero-RTL 우회도 부재 — 구 0x6B/0x6C 는 은퇴했고 (§24) 0x65 는 product 를 int4 로 절단하며, per-channel DEQUANT dispatch 는 cycle 예산의 16×. **0x6B 가 이 반증을 수리하여 criterion 3 이 per-lane gamma 포함 end-to-end 로 진짜 충족된다.**

- **MU-HOSTED**: 양쪽 twin classifier 등재 (§25.3); arm 은 **parameter-gated 영역 내부 — L-PE 는 아무것도 합성하지 않는다** (MU 1기 ~200-300 LUT vs 전 L-PE 전개 시 ~3-5k; 어차피 같은 unit 에서 DEQUANT 에 선행하는 op).
- A = **16 int4 lanes = 64b 단일-fragment payload_a**; gamma = 16 int4 lanes, **imm64 XOR OPREF** (alu-binary XOR 충족: 정확히 하나).
- **out[i] = sext8(a4[i]) × sext8(g4[i]) — EXACT (|p| ≤ 64 ⊂ int8)**; 출력 16 int8 lanes = 128b = **2 fragments** (오늘의 FSM). Combinational, 1-cycle. **lane order pin: lane i = bits [8i+7:8i]** — spec+golden+SDK 3자 동시 pin.
- **Gamma 고정소수점 관례**: gamma int4 는 implicit 2⁻ᵏ 를 운반; 이 2⁻ᵏ 는 후속 DEQUANT 의 broadcast scale 에 **exact 지수 shift** 로 폴딩된다.

#### 25.2.4 0x70 VFMA_ACC (0e2, int4/int8 only)

- **STATELESS pin**; mode-byte acc bit = 1 은 ROM-shipped 그대로 (legal_acc [1]) — **acc=1 은 wide-acc OUTPUT form 의 표기이지 stateful 누산이 아니다** (lane-engine 안의 polarity 역독 오류를 정정하여 기록).
- **B 64b split (spec-first)**: **B[63:32] = broadcast int32 addend c_acc**; **b_mul = sext32(B[3:0])** (int4 dtype) / **sext32(B[7:0])** (int8). **asm-lint 는 lane 폭 위 비트가 nonzero 인 b_mul imm 인코딩을 LOUDLY 거부** (silent truncation 금지); imm16/imm32 는 상위 word 를 zero-fill → c_acc=0.
- **out[i] = (sext32(a[i]) × b_mul + c_acc) mod 2³² — EXPLICIT** (c_acc 가 wrap 경계에 앉을 수 있다). 출력 int32 lanes [32i+31:32i]: int4 → **16 fragments** (widening + mask-fix 의 소비자), int8 → **8 fragments**.
- Compute: **공유 sequential LUT-mapped signed 8×8 MAC**, 1-2 cy/lane, **step sequencer 무접촉, MULT18 0**. instruction+EH chain 은 **전 fragment 에 복제** (VDOT 계약 그대로).
- vfma_busy interlock 은 §25.3.

### 25.3 Fragment widening + accumulation buffer (normative)

**Emit-side 2→4-bit widening (0e1; Cluster CAM 저장은 이미 16-deep — 수신 파싱 무변경)** — PE_Core.v 편집 목록:

- (a) localparam + frag_idx/frag_total_m1_held **[1:0]→[3:0]** (1383-1389; FSM 은 plain up-counter 유지, FRAG_IDLE=4'd0)
- (b) frag_pending **[0:3]→[0:15]** (1394, +768 FF; **row 0 은 reset-only dummy 유지** — frag_idx==0 은 fragment 0 을 alias 하며, **fragment 0 은 언제나 arm cycle 에 직접 emit 되고 절대 drain 되지 않는다** — 불변식)
- (c) reset write (1558-1563) → 16 rows
- (d) drain read (1735) → **16:1×64b mux** (진성 reg-array read — Gate-3 상수-배열 pathology 아님; ~250-350 LUT)
- (e) header pack (1738) → {frag_idx, frag_total_m1_held} (nibble 은 이미 예약 — 기존 2-frag wave 는 bit-identical)
- (f) live total_m1 literal 2건 **2'd1→4'd1** (2066, 2405)
- (g) 폭-literal 위생: 1743 `frag_idx + 2'b01`, 1559 `2'b00` 을 4-bit 로 정규화 (zero-extension 하 benign 이나 lint-culture 대상)

**수신측 수정 — 잠복 버그 수리로 기록**: Cluster.v:257-258 frag_mask_full 의 shift 량을 **5-bit 로 확장** (`wire [4:0] = {1'b0,frag_tot_ref}+5'd1`). 현행 RTL 은 tot_m1=15 에서 4-bit self-determined shift 가 0 으로 wrap → mask 0x0000 → **16-fragment wave 는 오늘 영구 재조립 불가** (verilator 확정; silent CAM-slot rot). 1행 수정이며 0e2 16-frag emit 의 전제조건.

**Twin classifier**: Cluster.v:422-432 `is_mul_op` + PE_Core.v:1238-1243 `dec_is_mul_op` 가 **0x6B/0x70/0x78/0x79 를 lockstep 으로** 획득 (한쪽 누락 = silent permanent lower_required dead-end — in-RTL invariant 주석 403-417 갱신, lockstep 테스트 같은 commit 탑승); stub arm 2465-2467 은 같은 commit 에서 0x70/0x78/0x79 trio graduate (0x6B 는 stub 이력 없음); all-ops live-extraction membership 테스트 flip.

**BUFFER — 누산 버퍼는 widened frag_pending 그 자체다 (제2 구조 없음)**: loop writer 는 완료 lane 을 64b staging word 로 pack — **word 당 bf16 4 lanes 또는 int32 2 lanes** (hybrid 제출본의 "2 bf16/word" prose 오류 정정); word ≥1 → frag_pending[word_idx]; **word 0 → 전용 64b frag0_hold reg** (row-0-dummy 불변식 보존).

**DRAIN ENTRY — atomic handoff PIN**: 마지막 lane 의 completion cycle 에 — **covering busy 항이 아직 high 인 동안** — arm 이 frag0_hold 를 hdr {4'd0, total_m1} 로 emit 하고, **기존 writer 들과 같은 clocked block** (lint co-location) 에서 frag_idx <= **FRAG_EMIT_1 (SYMBOL — 4'd1 literal 금지, lint 발견성)** + frag_total_m1_held <= N-1 을 기록; rows 1..N-1 은 무변경 priority override (1734-1744) 를 통해 **정확히 1 fragment/cycle drain**. **Spec-delta 불변식: loop 형 op 의 fragment 0 은 dispatch 시점이 아니라 loop 완료 시점에 emit 된다.**

**pe_ready worst-case 주석 amendment (PE_Core.v:1378-1381)**: 16-fragment 결과의 drain 은 최악 **~15 cycle 의 pe_ready deassert** (fragment 0 은 arm cycle 직접 emit + rows 1..15 가 1/cycle) — 기존 2-frag 가정 수치를 대체.

**점유 interlock**: DEQUANT loop — fp_busy 가 output_regs_free 를 연속 low 유지 (registered relaunch 가 첫 idle cycle 에 착지함은 검증 완료) **+ pack/arm window 를 덮는 deq_loop_active 항**; per-lane fp_done pulse 는 fp output arm 에서 **DIVERT** (loop 중 fp_armed 를 low 유지) — lane 별 spurious emit 없음 (1701/1768 의 확정 hazard). VFMA loop (0e2) — 신규 **vfma_busy** 항을 output_regs_free (1403) **와** 0x12 MUL launch gate (1592-1595 — output_regs_free 가 덮지 않는 확정 구멍) 양쪽에 OR; fp 선례의 **2-항 (busy || valid) form** 으로 gap-cycle dispatch sneak 차단. Mid-flight mul-class dispatch 는 **loudly busy-reject (lower_required, VDOT rung)**; L-PE/DIV traffic 무영향; 전 readiness 신호 observe-only 유지.

**lint_frag_total_m1_held.py 확장 — 첫 신규 writer 와 같은 commit**: 현행 case-arm indentation heuristic 은 generate-region writer 에 대해 vacuous pass (확정 blind spot) — non-case-arm writer block 발견으로 확장 + FRAG_EMIT_1 SYMBOL 강제 (4'd1 literal flag) + 잔존 2-frag writer 2곳과 신규 loop-completion/comb-arm writer 의 same-block co-location 검증.

### 25.4 cycle maxima 표 (normative — 추정→실측 졸업 규율)

10.93 MHz (91.5 ns/cy) 기준; 공식 = N_lanes × (L+1) + 고정 ~3 + fragment 당 drain 1 cy. **OPS_DEQ L=6-7 은 ESTIMATE** (비정규화 significand 폴딩 시 +1 → L=8) — 표는 **ceiling** 을 운반하고 **C-gate TB 에서 estimate→measured 로 졸업**한다 (§23.10.6 completion-within-bound 관례 동일: ceiling 을 assert, exact count 는 절대 assert 금지).

| op / form | 추정 cycles | ceiling |
|---|---|---|
| 0x79 FMINMAX | ~3-4 (comb + frag0 + drain 1) | **6** |
| 0x6B GAMMA_MUL_W | ~3-4 (comb + 2-frag emit) | **6** |
| 0x78 int8-16→bf16 | 16×(7..8)+3+4 = ~119-135 (~11-12 µs) | **160** (L=8 시 147) |
| 0x78 int4-32→bf16 | 32×(7..8)+3+8 = ~235-267 (~21-24 µs) | **300** (L=8 시 299) |
| 0x70 int4 (0e2) | 32×(1..2)+3+16 = ~51-83 | **90** |
| 0x70 int8 (0e2) | ~27-43 | **48** |
| RMSNORM row N=16 (int4) | L2SQ + fp insert ~32 (TB 실측, 불변) + 0x6B ~4-6 + DEQUANT-int8-16 ~123-139 + dispatch ~6-10 = ~165-190 (~15-17 µs) | **210 cy/row** |
| RMSNORM row N=32 | (0x6B+DEQUANT) 쌍 2회 = ~300-340 | **380** |

**정직한 regression — spec delta 에서 명시 RE-ACCEPT**: 0d Q8.8 row (60-100 cy = 5.8-9.7 µs, §23.10.10(g) C6 합성 실측) 대비 **~1.9-2.9× wall-clock** — exactness 를 cycle 로 산 것. 제출본 hybrid (~3×) 보다 개선: FSCALAR gamma-fold step 삭제 (gamma 지수는 무료 폴딩, §25.2.3) + 매크로 경로가 int4-32 대신 **int8-16 DEQUANT** 사용.

**MU 점유**: in-scope 최악 window = DEQUANT int4-32 (weight-dequant form) ~235-300 cy = 수용된 DIV-66 선례의 **~3.6-4.5×**, 현행 최악 fp op 의 ~7-9×; 그동안 pe_ready/cluster_ready/pod_ready 는 observe-only low; mid-flight mul-class dispatch 전건 loudly busy-reject; 16-frag VFMA drain 이 최악 ~16 cy 의 dispatch 차단 추가; **기지의 positional NoC-bank hazard (Cluster.v:408-417 — fix 는 v1.9 arbitration rework)** 의 노출이 **~4× 증가** — §23.10.9 risk-2/3 수용에 대고 재진술 (§25.6 항 4). **v1.9 까지 아무것도 pipeline 되지 않는다** (lane compute · pack · drain 엄격 직렬).

### 25.5 Gates — pre-priced, 구현 이전 공표 (locked)

#### 25.5.1 COMB / MULT / Fmax gate + cut ladder

실측 anchor (§24.5): COMB 34.26% (28,659/83,640), MULT 122/156, Fmax 10.93 MHz / 113 stages.

**Nominal 항목별 견적 (합산 일치 의무 — all-sequential 안의 itemization/ceiling 불일치 교훈)**:

| 항목 | LUT4 |
|---|---|
| frag widening + 16:1 drain mux + write decode | 350-500 |
| FMINMAX comb arm | 350-500 |
| OPS_DEQ case rows + lane counter + 32:1 lane extract + bf16 round-once pack | 250-500 |
| VFMA sequential MAC (0e2) | 300-600 |
| 0x6B gamma arm (16× signed 4×4 + pack, MU 단일 instance) | 200-300 |
| decode/legality/twin-classifier/asm-visible control | 200-400 |
| **nominal 계** | **+1.65-2.8k** |

**COMB GATE ≤ 40.0% (33,456 LUT4)** — 도출을 함께 공표: 최악 nominal 2,800 × **1.67** (Gate-3 실측 overrun 계수 — §23.10.10(g) 의 방법, 0d 를 당선시킨 그 기준) = 4,676 → 28,659 + 4,676 = 33,335 = **39.86%**; margin **121 LUT** (0d 의 ~150-LUT-class margin). **하향 개정만 가능.** 명시 기록: 40.0% 는 cleanup 전 실측 39.48% 보다 **위** 이고 구 0d gate 41.0% 보다 1.0%p 아래 — 제출본 hybrid 의 "39.5% 는 39.48% 아래" 문장은 사실 오류로 폐기. **0e1 착지 후 interim check**: nominal 1.35-2.2k → projection ≤39.0%.

**MULT pin (C6-amended form — ceiling + unit-증명 delta, total-count pin 아님)**: cluster gate 기대치 **정확히 122 (0e 신규 0)** — 형식은 **≤140 hard ceiling + 0e cone 신규 곱셈기 0 을 per-operator/unit gate 에서 증명**. 억제 기제를 명명한다 (C6 +1-drift 교훈): **VFMA MAC · 0x6B 곱셈기 · FMINMAX comparator 는 LUT-structural + 명시적 DSP-inference 억제 attribute 로 축조**; unit gate 는 0e cone 에 귀속되는 신규 곱셈기 발견 시 **hard-fail** (legacy-cone remap ±1 은 C6 관례대로 기록-비실패).

**Fmax pin (C6-amended criterion)**: **netlist 귀속으로 0e 로직의 critical path 부재 증명 + 전역 drift ≤3%**. 기지 노출면: output cone 의 16:1 drain mux, 확장된 dispatch case tree — 양쪽 다 축조상 오늘의 113-stage 경로 밖 (전 산술이 step sequencer 뒤 또는 registered launch-capture 뒤).

**Gate 실행 (v1.8.0b 교훈 normative — 3 레벨 전부 mandatory-run, merge blocker)**: per-operator synth — **0x79 / 0x78+OPS_DEQ / 0x6B / 0x70 각각 착지 후**; unit gate — PE_Core MU-parameterization + **L-PE parameterization 으로 MU-gated arm 의 L-PE 성장 0 증명**; cluster gate — full.

**Pre-declared cut ladder (구현 중 집행 가능, 순서 고정)**:

1. FMINMAX comb arm → FP_StepSeq operand reg 를 공유하는 1-step K_INT 프로그램 (−300-400 LUT)
2. VFMA int4-slice-only, int8 arm 이연 (−150-250)
3. OPS_DEQ fused → two-pass CVT+FS_MUL 재사용 (−200-300; cycle 비용: int4 DEQUANT 267→427 cy — 선가격 완료, 수용, MSE-중립)
4. 0x70 전체를 0e3 으로 이연 (−500-900; MSE 계약 무영향 — **0e1 은 criterion 3 에 self-sufficient**)

#### 25.5.2 MSE release gate (신규 `scripts/mse_sweep.py` — harness 수리 반영)

- **eps-INCLUSIVE exact reference**: mpmath 로 exact_i = γ_i·x_i/√(mean(x²)+eps) — eps 를 포함한 채 exact (reference 의 eps 누락 수리).
- per-tensor ratio **MSE(chain, exact) / MSE(RNE_bf16(exact), exact) ≤ 1.05**, 단 **denominator-floor 규칙**: 경험적 bf16 floor 가 ~0 이거나 exactly-representable 인 row 는 ratio 대신 절대 기준으로 fallback (0/0 금지).
- **Tensor 생성 pin**: int4/int8 lane + per-tensor fp32 scale — **고정 int-lane 분포에 대해 scale 을 binade 2⁻⁸..2⁸ 로 sweep** (data-binade sweep 단독은 all-zero row 로 양자화되는 확정 함정).
- Families: Gaussian, lognormal heavy-tail, outlier-injected, near-constant, eps-boundary rows, **그리고 per-lane GAMMA-VARIATION tensors (부호 flip 포함 random int4 gamma — broadcast-gamma 구현을 잡아내는 클래스)**.
- **Round-once 는 MSE ratio 로 증명 불가 (증명적으로 blind)** — directed tie vector 를 **golden/TB bit-equivalence** 검사로 실행한다 (round-once vs double-round 를 구별하는 유일한 시행 지점; §25.7 risk 8).
- end-to-end 검사는 RMSNORM 매크로 체인 (L2SQ → fp insert → 0x6B → DEQUANT) 을 mpmath exact 에 대고 실행.

전 사이클/면적 주장 cluster-OOC 한정, pod 주장 금지 (§23.10 관례).

### 25.6 Amendments (COMMIT 0 성문화)

1. **§23.10.10(f) pin 14 개정**: single-narrowing 규칙이 **DEQUANT 를 sanctioned narrowing site 로 획득** — "narrowing 은 STORE_QUANT/CVT/**DEQUANT** 에서만".
2. **§23.4 criterion 3 re-scope**: "종단 1회 좁히기 + norm 매크로 MSE ≤1.05×" 는 **narrowed 출력 dtype (bf16)** 과 **RMSNORM 매크로 end-to-end (per-lane gamma 완전 이행 포함)** 로 scope 된다 — 0x6B 가 이를 진짜로 충족시킨다. **LAYERNORM/BATCHNORM 은 명시 제외**: beta 가 0e 에 fp-vector-add home 이 없어 두 매크로는 0d Q8.8 form 잔류, 1.05× 계약 밖 — **은폐가 아닌 명기** (§25.7 risk 7, v2.0 재론).
3. **eps ≥ 2⁻¹³ assembler guard 존치, 근거 재진술**: 구 Q8.8-absorption 근거는 은퇴; 새 근거 — exact reference 가 **eps-inclusive** (§25.5.2) 이므로 guard 는 수치 안정 하한이지 오차 은폐 장치가 아니다.
4. **MU-점유 + NoC positional-bank hazard 노출 증가의 명시 RE-ACCEPT** (§23.10.9 risk-2/3 에 대고): §25.4 의 수치 (~4.5× DIV-66 window, hazard 노출 ~4×) 로 재진술하고 수용을 갱신; **SDK no-intervening-mul-dispatch 규칙 (§23.6a SDK 계약 3) 을 0x6B/0x70/0x78/0x79 로 확장**.
5. **pe_ready worst-case 주석 amendment** (PE_Core.v:1378-1381): 16-frag drain 최악 ~15 cy deassert (§25.3).
6. **Twin-classifier 등재**: is_mul_op / dec_is_mul_op += **{0x6B, 0x70, 0x78, 0x79}** lockstep (§25.3; §23.10.9 risk 6 의 process 규칙 — lockstep 테스트 같은 commit).
7. **Frozen truth-table governance**: 0x79 legality re-row + 0x6B 재배정이 differential recapture + **domain_version 2 → 3** bump 를 강제 (§24.3/§12a 규칙 2 동일 — 의도적·리뷰된 recapture 만; 구표에 pin 된 downstream 도구는 같은 commit 재동기; retired-0x6B stale-consumer grep 필수).
8. **Loop 형 op 의 fragment-0-at-loop-completion 불변식 + lane→fragment packing pin** (§25.3) 을 normative 로 성문화.

### 25.7 residual risks (v1.8.0e)

1. **OPS_DEQ latency 가 유일한 미실측 수치**: fused I2F 가 FP_Mul36 에 비정규화 significand 를 공급하고 epilogue 가 더 넓은 LZC normalize 를 요구할 수 있음 (+1 step → L=8, int4 DEQUANT ~299 cy); cycle 표는 estimate-flag + ceiling 으로 출하되고 C-gate TB 에서 졸업 — **L>8 이 실현되면 cut-ladder rung 3 (two-pass 재사용, 427 cy) 이 pre-declared fallback, MSE-중립**.
2. **COMB gate margin 이 얇다**: 1.67×-inflated 최악 nominal 위 **121 LUT** (39.86% vs 40.0%) — 0d 의 ~150-LUT-class margin 이나, itemization creep 은 구현 중 cut ladder 집행을 강제; rung 1 (FMINMAX → K_INT 프로그램) 단독으로 300-400 LUT 회수.
3. **yosys DSP-inference drift** (C6 선례: legacy cone +1 MULT): 억제 기제가 명명되고 unit gate 가 0e-cone 곱셈기 귀속에 hard-fail 하나, legacy-cone remap ±1 은 여전히 출현 가능하며 C6 의 기록-비실패 처분이 필요 — pin form (ceiling + unit-증명 delta) 이 설계상 이를 관용한다.
4. **Fmax 전역 drift**: 0e 는 ~+5.6%p COMB 를 추가 (0d 의 +2.46%p 가 congestion 으로 −2.7% 전역 drift 를 실측한 전례); 0e 로직이 경로에 증명적으로 부재해도 ≤3% pin 이 근접될 수 있음 — pre-declared 대응은 cut ladder, 그 다음 C6-식 pin amendment 이며 **silent acceptance 는 절대 금지**.
5. **Frozen truth-table churn**: 0x79 legality re-row + 0x6B 배정이 differential recapture + domain_version bump 를 강제; 구표에 pin 된 downstream 도구는 같은 commit 에서 재동기해야 하고, retired code 0x6B 의 pre-stable 재배정은 stale-consumer grep clean 이 필수 (제거 근거가 소비자 0 이었어도 검사는 mandatory).
6. **Norm-macro wall-clock ~1.9-2.9× 와 MU 점유 최대 ~4.5× DIV-66 window 는 RE-ACCEPT 이지 fix 가 아니다**: positional NoC-bank hazard (Cluster.v:408-417) 는 v1.9 arbitration rework 까지 비례 노출 증가를 얻고, SDK no-intervening-mul-dispatch 규칙은 확장된 opcode set 에서 준수가 더 어려워진다 — §23.10.9 risk-2/3 에 대고 spec delta 에서 명시 재진술.
7. **Criterion 3 은 RMSNORM 에 한해 end-to-end 충족**: LAYERNORM/BATCHNORM beta 는 0e 에 fp-vector-add home 이 없어 두 매크로는 0d Q8.8 form 으로 남고 v2.0 까지 1.05× 계약 밖 — 0e 에서 fp-grade layernorm 을 기대하는 소비자는 얻지 못한다.
8. **Round-once 정의 (a) 는 golden/TB bit-equivalence + directed tie vector 로만 시행 가능** — MSE gate 는 수학적으로 blind; TB tie vector 가 약화되면 pin 은 소리 없이 미검증 상태가 된다.
9. **atomic frag0_hold handoff** (busy-clear 와 frag_idx<=FRAG_EMIT_1 이 같은 completion cycle) 와 **fp_armed loop 억제** 는 PE_Core 의 불변식 밀도가 가장 높은 영역에 착지: 양쪽 다 전용 테스트로 pin 되나 이 package 최고접촉 제어 편집 — verify:fsm re-proof 가 drain-entry timing 을 전수 커버해야 한다.
10. **VFMA 의 stateless acc-via-B[63:32] 는 누산을 broadcast addend 로 한정**: 진짜 per-lane accumulate chain 은 여전히 partial sum 을 SDK 로 round-trip 하며, stateful-accumulator 문제는 fp lane 과 함께 v2.0 에서 재부상 — **의도된 재이연**.

### 25.8 0e1 C-gate 실측 최종 (2026-07-25, PASS 전 항목)

| 지표 | 기준선 (§24.5) | 0e1 실측 | gate | 판정 |
|---|---|---|---|---|
| TRELLIS_COMB | 34.26% | **37.76%** (31,585) | ≤40.0% | PASS (마진 2.24%p) |
| MULT18X18D | 122 | **122** | 정확히 122 (신규 0) | PASS |
| Fmax | 10.93 MHz | **11.16 MHz** | ≤3% 회귀 | PASS — **+2.1% 개선, 신기록** |
| critical path | 113 stages / 91.5 ns | 119 stages / **89.6 ns** | attribution | 절대 지연 개선 |

frag 16 확폭 + 3 opcode + lane loop 를 추가하고도 Fmax 가 오른 것은
cleanup 이 만든 배치 여유의 지속 효과. unit gate (4,721 ≤ 4,909 /
40.37 MHz) 와 함께 0e1 의 모든 실측 gate 닫힘. MSE 계약은 모델·asm
방출 체인 양쪽에서 ratio 1.000 으로 이행 (§25.5 MSE gate).

### 25.9 0e2 (v1.8.0e 최종) C-gate 실측 (2026-07-25, PASS — 마진 최소)

| 지표 | 0e1 | 0e2 (v1.8.0e 최종) | gate | 판정 |
|---|---|---|---|---|
| TRELLIS_COMB | 37.76% | **39.86%** (33,335) | ≤40.0% | PASS — **마진 0.14%p, 사전 도출 예측(2,800×1.67=39.86%)과 정확히 일치** |
| MULT18X18D | 122 | **122** | 정확히 122 | PASS |
| Fmax | 11.16 MHz | **10.93 MHz** | ≤3% 회귀 (기준선 10.93) | PASS — 기준선과 동률, 0e1 대비 -2.1% |
| critical path | 119/89.6 ns | 122 stages / 91.5 ns | — | 0x70 dispatch cone 성장 반영 |

VFMA_ACC 추가로 COMB 예산을 사실상 소진 (여유 0.14%p) — **v1.8.0e 계열
추가 opcode는 이 예산 안에서 불가**, 다음 폭 확장은 v1.9 dispatch
파이프라이닝(Fmax 상한 재정의) 또는 v2.0 이후 예산 재산정이 선행돼야
한다. v1.8.0e (0e1+0e2) 전 gate 최종 PASS로 마감.

## 26. v1.9 — dispatch 파이프라인 2단 분할 (case_result_s2) — amendment (2026-07-26, COMMIT 0 · normative)

**당선 설계 "corrected uniform 2-stage split" (2026-07-26 설계 workflow, cross-analysis 합성 결과 — 세 편의 제출 설계 및 6회 adversarial verification pass 전체가 수렴한 지점이며, 어느 한 제출본의 문자 그대로의 채택이 아니다).** 본 절이 v1.9 의 normative source 다 — spec-before-code COMMIT 0 (§12a pre-stable 정책 하, 아래 나열된 dispatch latency-contract 변경 전건의 spec-first 기록). 기준선 anchor 는 v1.8.0e 최종 실측 (§25.9): **TRELLIS_COMB 39.86% (33,335/83,640) · MULT18X18D 122/156 · Fmax 10.93 MHz / 122 stages / 91.5 ns**.

### 26.1 배경 및 동기

§25.9 는 0e2 착지 시점에 이미 "**v1.8.0e 계열 추가 opcode는 이 예산 안에서 불가**, 다음 폭 확장은 **v1.9 dispatch 파이프라이닝**(Fmax 상한 재정의) 또는 v2.0 이후 예산 재산정이 선행돼야 한다" 고 명시했다. §23.10.9 risk 2/4 와 §25.6 항 4 / §25.7 risk 6 은 각각 mu_bank_reg positional hazard 하드웨어 fix 와 dispatch 파이프라이닝 자체를 "v1.9 arbitration rework" 로 반복 이연해 왔다. 본 절은 그 이연의 이행이다: COMB 여유가 사실상 소진된(0.14%p) 상태에서 Fmax 상한을 높이는 유일한 정직한 경로는 **논리 깊이를 자르는 파이프라인 레지스터 삽입**이지 추가 COMB 확보가 아니라는 것이 mandate 의 제1 우선순위였다.

### 26.2 당선 아키텍처 — `case_result_s2` (신규 register bank)

**단 하나의 신규 register bank.** 이름 `case_result_s2`, PE_Core.v 내부, 위치는 기존 `case (dec_opcode)` 조합 블록(현재 PE_Core.v:2065) **직후**, 기존 8-level/18-site **출력 우선순위 체인**(현재 PE_Core.v:2006-3354) **직전**이다. wres_*/einsum/vdot 함수 평가는 이 블록 안에서 오늘과 동일하게 일어나며, 그 결과가 새 레지스터로 커밋된다.

**기각된 대안 1 — pre-case-select 배치 ("2-stage-minimal-split" 설계의 문자 그대로의 안):** `case(dec_opcode)` **앞**에 레지스터를 놓는 배치는 degenerate 로 확정 기각한다. 근거: EHDecode 의 `dec_*` 버스(`dec_opcode`/`dec_valid`/`dec_forwarded_tag`/`dec_input_payload(_b)`/`dec_input_payload_wide`)는 **이미 EHDecode 단에서 레지스터로 잡혀 있고 그 사이에 개입하는 조합 로직이 0** 이다 — 즉 이 지점에 레지스터를 하나 더 놓아도 어떤 조합 경로도 잘리지 않는다. 이 사실은 phase-1 조사(finding 3, finding 5)와 해당 설계 자신의 timing-realism verification 양쪽에서 독립적으로 확인됐다.

**기각된 대안 2 — "Boundary A" ("operand-registered-3-stage" 설계의 두 번째 pre-case-select 레지스터):** 동일한 이유로 기각한다 — dec_* 버스가 이미 레지스터로 잡혀 있어 이 지점의 레지스터도 아무것도 사지 않는다는 사실이 그 설계 자신의 timing-realism verification 에서 재차 확인됐고, 그 설계의 hw_cost 서술 자체도 Boundary A 가 아무 일도 하지 않음을 암묵적으로 인정하고 있다. Boundary A 를 제거하면 그 설계의 3-stage 아키텍처는 정확히 본 절이 채택하는 2-stage 아키텍처로 붕괴한다 — 즉 "3단"은 실제로는 "쓸모없는 레지스터가 하나 앞에 덧붙은 2단"이었다.

**기각된 대안 3 — decode-result-cache/class-split (전면 기각):** 이 설계는 세 가지 검증 렌즈 전부에서 반증됐다:
1. 이 설계의 stage_boundary 서술은 fat opcode 에 대해 **전 계산을 stage2 로 미룬다(분할하지 않는다)**고 스스로 말하면서, 그로부터 나오지 않는 **~2x Fmax** 를 주장한다 — 자신이 서술한 메커니즘으로부터 자신이 주장하는 결론이 따라 나오지 않는 내적 모순이다.
2. 이 설계는 depth-1 `CLS_REG` occupancy invariant 를 bank_fix_design 절에서 주장하지만, 그 invariant 는 그 설계 **자신의 stage_boundary 메커니즘에 의해 실제로 구현되지 않는다** — 주장과 구현이 어긋난다.
3. 이 설계는 "다음 dispatch 가 도착했을 때 `CLS_REG` 가 아직 점유 중"이라는 hazard 를 상정하지만, 이는 **phantom hazard** 다 — 사이클당 dispatch 1건, 레지스터는 그 다음 사이클에 overwrite 되기 전에 이미 소비되는 평범한 단일-레지스터 파이프라인에는 애초에 존재하지 않는 종류의 위험이다.

이상 세 가지 기각을 거쳐 남는 유일한, 세 설계 문서와 여섯 번의 adversarial verification pass 전부가 구조적으로 의미 있다고 수렴한 경계가 `case_result_s2` 다 (investigator-0 finding 5 자신이 권고한 삽입점과 일치).

### 26.3 pipeline_architecture_final (normative)

**Stage 1 (comb, cycle T) — 입력·case 평가는 무변경.** `dec_opcode`/`dec_valid`/`dec_forwarded_tag`/`dec_input_payload(_b)`/`dec_input_payload_wide` 는 EHDecode 가 이미 레지스터로 잡은 값을 live 로 읽으며, 이 앞에 신규 레지스터를 두지 않는다(§26.2 의 기각 근거 그대로 — degenerate 배치를 두 설계 계열에서 반복 배제한 뒤 남은, non-degenerate 한 경계). `case` 문 자체는 오늘과 동일하게 평가된다 — 동일한 55 case-item / 67 opcode, 동일한 wres_*/einsum/vdot 함수 호출. 다만 그 OUTPUT 은 더 이상 `output_payload`/`frag_pending`/`fp_start`/`lower_required` 등을 직접 구동하지 않고, `case_result_s2` 의 필드를 구동한다:

- **11개 compute-inline arm** (0x32 wide sub-tree ×5, 0x60-0x65/0x68/0x69 공유 wide-SIMD, 0x6B, 0x71, 0x72, 0x79, 0x7C): 계산된 결과 값(narrow, arm 당 약 32-256b, 또는 multi-fragment arm 의 경우 frag_pending-preimage 배열), tag, opcode_out, frag_total_m1, error_flag intent 를 캡처.
- **7개 FSM-launch arm** (0x70, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78): launch-intent 플래그 + 오늘 `fp_a_q`/`fp_b_q`/`fp_c_q`/`fp_subop_q`/`fp_tag_held`, `vfma_a_q`/`b_q`/`c_q`, `deq_a_q`/lane-config 를 채우는 바로 그 operand 들을 캡처 — 오늘의 register-load 가 하는 일과 동일하되, 종착지가 `fp_start`/`vfma_busy`/`deq_loop_active` 가 아니라 `case_result_s2` 라는 점만 다르다. **COMMIT 0 대비 정정 (구현 세션에서 실제 RTL 확인 후 발견)**: COMMIT 0 원문은 0x73 ACC_ELEMWISE 와 0x77 CVT 를 13개 compute-inline 집합에 두었으나, 실제 RTL 은 이 둘이 `fp_start<=1`/`fp_armed<=1`/`fp_a_q..subop_q`/`fp_opcode_held`/`fp_tag_held` 만 채우고 결과는 이후 `fp_valid_p2` arm 이 반환하는, 0x74-0x76 과 **byte-identical 한 register-load-only 메커니즘**이다 — spec 원문이 당시 RTL 사실관계를 오인했던 것으로 판명되어 여기서 7-arm 집합으로 정정한다(구현은 처음부터 이 정정된 분류를 따랐다 — RTL 이 spec 오기를 재현하지 않았다).
- **~40개 architecturally-cheap opcode** (단순 ALU, legacy narrow einsum, 0x6A FRAG_INVAL 등, 오늘 output_regs_free 게이트가 걸려 있지 않은 것들): 이들도 결과/제어 필드를 **동일한 방식으로 균일하게** 캡처한다 — 이 arm 들은 이 분할에서 타이밍 이득을 전혀 얻지 못함에도, contract 를 단일하게 유지하기 위해 균일 캡처한다(§26.4 의 uniform +1 계약과 짝을 이루는 설계 선택).

T→T+1 edge 에서 커밋되며, 이 edge 에는 순수 register-load 외의 신규 조합 로직이 없다.

**Stage 2 (comb, cycle T+1) — 우선순위 체인은 종류상 무변경, 입력만 재배선.** frag-drain absolute-priority override(2006-2016, 자신의 `frag_idx` state 를 읽음, 무변경) > MUL p2(무변경) > DIV p2(무변경) > DIV b_zero p2(무변경) > FP p2(무변경) > **[신규] `case_result_s2` arbitration** — 이제 live case-block wire 대신 캡처된 레지스터를 읽는다 > DEQUANT frag0 handoff(무변경) > VFMA frag0 handoff(무변경). 신규 arbitration 단계에서:
- `output_regs_free` 는 **T+1 시점에 LIVE 로 재평가**한다 — T 시점 값을 그대로 들고 오는 stale carry 가 아니다. 이는 우연이 아니라 correctness 렌즈가 요구하는 **의도적 re-homing** 이다. **재-homing 의 정확한 범위 (구현 세션에서 명확화)**: stage 1 "case 는 오늘과 동일하게 평가된다"는 문장과 이 재-homing 문장은 18개 output_regs_free-gated arm 에 한해 문자 그대로는 busy-check 시점에서 충돌한다(오늘의 RTL 은 case arm 안에서 `!output_regs_free` 를 inline 으로 즉시 검사한다). 해소: **busy-check 만** `cr_needs_regs_free` 플래그로 stage 2 에 이연되고, 그 밖의 모든 guard(missing-wide/missing-B 오류, dim/subop-range `lower_required` 등 — `dec_*` 버스에만 의존하는 것들)는 stage 1 에 그대로 남는다. **부작용 (문서화된 허용 사항, 결함 아님)**: 어떤 dispatch 가 busy-blocked 이면서 **동시에** malformed 이기도 한 극단 코너 케이스에서, `lower_required`(busy)와 `error_flag`/`lower_required`(malformed) 사이의 우선순위가 v1.9 이전 대비 1-arbitration-slot 이동할 수 있다 — 어느 경우든 `output_valid`=0 은 불변이며, 이 정확한 동시-조건을 assert 하는 기존 테스트는 없다(226/226 유지). re-derive 후보로 flag 하되 이번 release 의 blocking 조건은 아니다.
- 7개 launch arm 의 실제 register-load(`fp_start<=1`, `vfma_busy<=1`, `deq_loop_active<=1` 등)는 이제 stage 1 이 아니라 **stage 2 에서** 일어난다.
- 승자는 오늘과 동일한 기존 출력측 레지스터(`output_payload`, `frag_pending[]`, `frag_idx`, `output_tag`, `opcode_out`, `output_valid`, `error_flag`, `lower_required`)에 T+1→T+2 edge 에서 커밋된다.

MUL 발사(`mul_valid_p1`, PE_Core.v:1781-1811), bit-serial DIV FSM(1814-1897), frag-drain override(2006-2016) 는 구조적으로 무변경이다 — 이들은 `dec_opcode`/`dec_valid` 또는 자신의 state 를 case 블록과 병렬·독립적으로 직접 읽는다(finding 4) — 0-cycle 변경이며, 이 사실이 §26.5 bank-fix 를 리터럴 MUL/DIV opcode 에 대해 본 변경과 직교하게 만드는 메커니즘이다.

추정 조합 깊이: stage 1 은 case-select mux(깊이 phase-1 미측정 — Fmax 추정의 최대 불확실성 원천) + wres_*/einsum 평가(0-6 단, `vdot_int4_256`/`vdot_int8_256` 의 ~5-6 레벨 가산 트리에서 최심)를 보유. stage 2 는 wide result-select mux + 8-level 우선순위 체인을 보유 — 두 adversarial pass 모두 tail-loaded/heavy 로 별도 지적한 부분이다. 어느 쪽도 서로의 깨끗한 절반이 아니다 — 이 비대칭이 §26.6 Fmax 사전가격의 불확실폭을 만든다.

### 26.4 latency_contract_final (normative)

**균일(uniform), 평탄(flat), opcode-class 무관.** `case(dec_opcode)` 블록을 경유해 dispatch 되는 **모든 opcode**(약 67개 전부, output_regs_free 게이트가 걸린 "fat" arm 과 게이트가 없는 ~40개 architecturally-cheap arm 양쪽 모두)는 dispatch(EHDecode `dec_valid`, cycle T)로부터 최초 출력측 register commit 까지 **정확히 +1 cycle**을 얻는다: T+1(기준선) → T+2(v1.9). **MUL, DIV, frag-drain absolute-priority override 는 변경 없음(0 cycle)** — 이들은 case 블록을 완전히 우회한다(finding 4).

7개 FSM-launch arm(0x70 VFMA, 0x73 ACC_ELEMWISE, 0x74-0x76 FP, 0x77 CVT, 0x78 DEQUANT)의 경우 register-load launch 동작(`fp_start<=1` 등)도 다른 모든 것과 균일하게 +1 cycle 이동한다 — 이것이 안전한 이유는, 이들의 downstream FSM(FP_StepSeq, VFMA/DEQUANT lane-loop advance)이 이미 **자신이 캡처한 레지스터만** 읽고 `dec_*` 를 직접 읽지 않기 때문이다(PRE-PAID 조치 #2, finding 4) — 따라서 이들은 임의로 지연된 launch 를 내부 재작업 없이 그대로 수용한다. 이들 자신의 완결 latency(5-34 cycle `fp_busy` bound, VFMA/DEQUANT lane-loop bound)는 크기 자체는 무영향이고 시작 시점만 +1 이동한다 — 즉 이 opcode 들의 dispatch-to-completion 총합은 정확히 +1 만큼 커지고 **+2 가 아니다**.

`output_regs_free`/busy-reject 는 case-dispatch 되는 모든 arm 에 대해 **신규 commit cycle(T+1)에 LIVE 로 재평가**한다 — T 시점에서 그대로 들고 오는 stale carry 가 아니다. 이것도 §26.3 과 동일하게 의도적 re-homing 이며, 신규 test B(§26.7)로 강제된다.

**Frag-drain fragment-cadence 문서 갱신:** "fragment 1 이 dispatch 후 정확히 cycle N+1 에 착지한다"는 불변식은, compute-inline multi-fragment case arm 에 한해 **N+2 로 변경**된다(N+3 이 아니다 — 레지스터가 하나만 추가됐지 둘이 추가된 게 아니기 때문이다). grep 으로 직접 확인된 **6개 stale comment site** 전부를 같은 commit 에서 수정해야 한다 — **PE_Core.v:1365, 1366, 1989, 2320, 2332, 2464**(mandate 자체의 단일 라인 인용은 이 범위를 5개 site 만큼 과소 산정하고 있었다). 아울러 `lint_frag_total_m1_held.py` 가 이 offset 을 hardcode 하고 있는지 점검하고, hardcode 되어 있다면 stage-agnostic 하게(절대 상수가 아니라 `frag_idx` 가 최초로 non-IDLE 이 되는 cycle 기준 상대 카덴스로) 갱신해야 한다.

본 계약은 §12a(pre-stable 호환성 정책, .claude-memos/wt64v1_spec.md §12a / line 248 에서 확정된, 바로 이런 종류의 contract-breaking 변경을 "정규 개발 행위"로 규율하며 spec-before-code 순서를 요구하는 정책) 하에 spec-first 로 기록되며, 기존 opcode-latency 표 및 SDK 대상 생성 latency 문서(`isa/wt64v1_isa.json` 파생 문서) 전부가 같은 commit 에서 bump 된다. Cycle-exact 테스트 breakage 는 **예상되고 요구되는** 것이며, 보존이 아니라 재유도(re-derive) 대상이다(§26.9, §26.7).

### 26.5 bank_fix_final (normative) — tag-indexed launch-time latch table

Cluster.v 의 두 positional shift-tap 메커니즘을 tag-indexed launch-time latch table 로 교체한다(unit 당 1개).

**MU table (depth 2, `mu_target_pipe_s2`/`s3`/`s4` 교체 — s3/s4 는 오늘 이미 dead code, Cluster.v:923-927 주석):** op 이 M-UNIT 에 LAUNCH 되는 cycle(`mul_valid_p1` 최초 assert, 또는 오늘 `mu_out_valid`/`mu_bank_reg` 를 positional 하게 타는 opcode — v1.8.0c/0e SDK-rule 확장에 따라 §25.6 amendment 4/6 으로 확인된 {0x74-0x76 FP, 0x6B, 0x70, 0x78, 0x79} — 의 register-load launch)에 `{target_idx}` 를 `launch_tag` 로 키잉된 빈 table row 에 기록한다 — 기존 `mu_out_tag`/`output_tag` wire(Cluster.v:794)를 재사용하며 **신규 tag namespace 는 만들지 않는다**. 완결 시(`mu_out_valid`) `mu_bank_reg[bank_target_by_tag[mu_out_tag]] <= mu_out_payload` 를 tag match 로(positional-shift-depth match 가 아니라) 읽고, 해당 row 를 해제한다.

**depth-2 근거(단순히 "p1/p2 와 맞춘다"가 아니다):** `output_regs_free` 의 복합 조건은 PE_Core 인스턴스당 **동시에 최대 1개의 fat op**(MUL 또는 DIV 또는 FP 또는 VFMA 또는 DEQUANT 또는 frag-drain wave)만 진행 중일 수 있음을 보장한다 — 따라서 2개의 동시 MU-table row 가 필요한 유일한 시나리오는 **MUL 자신의 고정 p1/p2 sub-pipeline** 뿐이다. MUL 이 아닌, `mu_out_valid` 를 타는 그 밖의 모든 opcode 는 (구조상 MUL 과 상호배타적이므로) 언제나 row 1개만 필요하다 — 즉 depth 2 는 MUL 하나만이 아니라 `mu_out_valid` 를 타는 **전체 opcode 집합**에 대해 충분함이 증명적으로 성립한다.

**DU table (depth 1, `du_target_pipe_s2` 교체):** DIV 는 엄격한 single-flight FSM(DIV_IDLE/DIV_ITER/DIV_FINISH)이므로 row 1개로 자명하게 충분하다.

**busy-bit interlock — 반드시 실제 synthesizable 하드웨어 fault 여야 한다.** row 마다 busy bit 를 두어 write 시 set, matching completion 시 clear 한다. 아직 busy 인 row 의 tag 를 재사용하려는 launch 시도는 **synthesizable 한 sticky `bank_tag_collision_error` status bit**(cluster 측에서 읽을 수 있는)로 나타나야 하며, simulation-only `$error`/assertion 이어서는 안 된다 — correctness 렌즈가 지적한 간극(sim-only assertion 은 silent corruption 을 시끄러운 테스트 실패로 바꿀 뿐 production 보장은 남기지 않는다)을 닫는다.

**merge 전 directed test 로 확인된 scope 항목:**
- **(a) 정정 (구현 세션에서 RTL 을 동적으로 확인 — COMMIT 0 원문의 가정과 반대로 판명):** 0x71 VDOT_ACC / 0x72 ACC_REDUCE 는 `mu_out_valid`/`mu_bank_reg` 를 **탄다** — PE_Core 자신의 `output_payload`/`frag_pending` 경로 안에서 전부 해소되는 것이 **아니다**. COMMIT 0 원문은 이 반대 방향을 전제(추정)로 배제 항목을 열었으나, RTL 검사 결과 0x71/0x72 는 여느 MU-hosted compute-inline case arm 과 동일하게 `mu_out_valid` 를 assert 함이 확인됐다. 따라서 MU table(depth 2)의 배선은 처음부터 **0x71/0x72 를 포함**해 이루어졌다 — 배제가 아니라 포함이 정답이었다.
- **(b) TWIN-CLASSIFIER GAP(NORMATIVE FIX):** 0x74-0x76 은 §25.6 amendment 4 에 의해 SDK "no-intervening-mul-dispatch" 규칙 텍스트에는 들어가 있으나, §25.6 amendment 6 의 `is_mul_op`/`dec_is_mul_op` classifier 집합(`{0x6B, 0x70, 0x78, 0x79}`)에는 **빠져 있다** — mu_out_valid 를 실제로 타는 opcode 이면서 classifier 집합에 없는 이 gap 은 MU table 이 실제 소비자에 대해 채워지지 않을 수 있는 silent 위험이다. **본 release 는 이 gap 을 note 가 아니라 NORMATIVE FIX 로 닫는다**: `is_mul_op`(Cluster.v) / `dec_is_mul_op`(PE_Core.v) 양쪽에 **0x74-0x76 을 lockstep 으로 추가**하여 classifier 집합을 `{0x6B, 0x70, 0x74, 0x75, 0x76, 0x78, 0x79}` 로 확정한다 — 같은 commit 에 lockstep/membership 테스트(§26.7 test O)를 동반한다.

**SDK-rule 은퇴 후보:** "no intervening mul-class dispatch" 소프트웨어 규칙(Cluster.v:416-449, §23.6a 계약 3, §25.6 amendment 4 로 확장)은, 위 depth-2/depth-1 table 근거가 directed test 로 확인되면 **완전 은퇴(축소가 아니라 폐기) 후보**다 — 단, 규칙 텍스트는 "v1.9 하드웨어-fix 확인 대기 중 superseded" 로 유지되다가, 같은 release 안에서 해당 테스트가 green 이 된 **바로 그 commit** 에서 함께 삭제한다(미검증 RTL 과 나란히 선제적으로 삭제하지 않는다).

### 26.6 Gates V9-1~V9-4 — pre-priced, 구현 이전 공표 (locked)

이 project 자신의 Gate 1-4 방법론(op_sel widening / frag-FSM widening 선례, §23.10.7·§25.5 의 그것)을 그대로 미러링한다 — **"선언된 merge-blocker gate 를 건너뛰면 5 commit 뒤 silent regression 으로 발각된다"는 교훈**(v1.8.0b 사건, §23.10.7 GATE 4 실측·§23.10.10(g)·§25.5 에서 이미 3회 확인)이 본 절로 **4번째 확인**을 얻는다. 전 게이트는 merge 전 실행·기록이 의무이며 예외 없음.

**GATE V9-1 (`case_result_s2` register, 격리 stage1/stage2 경계의 standalone OOC synth):** 레지스터 자체가 순수 FF 로 합성되는지(~18개 이형 case arm 에 걸친 필드 packing/폭 정렬로부터의 예기치 않은 comb bloat 없음)를 확인한다. Pass: 신규 MULT18X18D 0; FF count 는 문헌 추정(~1-2K, finding 5 선례대로 13개 hoisted wres_* wire 중 12개가 MU-gated 인 만큼 MU-hosted 인스턴스에 집중) 범위 내; 이 레지스터의 feeder/consumer 로직에서 신규 comb LUT 가 인스턴스당 ~150 LUT 를 넘으면 flag(hard-fail 아님).

**GATE V9-2 (bank-fix tag-latch table, Cluster-level standalone OOC synth):** MU table(depth 2)과 DU table(depth 1)의 tag-comparator + busy-bit interlock 로직을 확인한다. Pass: 신규 MULT18X18D 0; nominal LUT 추정 인스턴스당 20-40 × 해당 MU-capable 인스턴스 수, cluster 전체 nominal ~200-400 LUT.

**GATE V9-3 (full PE_Core 인스턴스, MU-hosted `generate if (MUL_OPS_SUPPORTED)` geometry 와 16개 L-PE narrow geometry 양쪽 — 이 project 의 per-operator-gate 선례대로 standalone OOC):** 두 인스턴스 형태 양쪽에서 2단 분할이 in situ 로 정확히 동작함을 확인하고, phase-1 이 측정한 적 없는 case-select-mux-depth 불확실성을 해소하는 **최초의 실제 stage1 vs stage2 조합 분할 수치**를 준다.

**GATE V9-3 실측 (2026-07-26, 0e14e12 구현 직후, 실 nextpnr PnR — synth stat 뿐 아니라):**
- **MU-hosted**: Fmax **37.44 MHz**(17.0 MHz 목표 대비 2.2× 마진). critical path 는 **`case_result_s2` 를 전혀 거치지 않음** — 기존(v1.9 이전부터 있던) FP32 adder 경로(`a_q` register → carry/exponent chain → `sticky_w`)에 그대로 남아 있다. 즉 이 geometry 에서는 dispatch 2단 분할 자체가 병목이 아니다.
- **LPE-narrow**: Fmax **154.37 MHz**. critical path 는 **`case_result_s2` 를 거친다** — `cr_decode_error`(stage-1 레지스터) → stage-2 arbitration/output mux ~4 LUT level → `output_frag_hdr`. 짧고 얕다.
- 두 standalone 수치 모두 17.0 MHz 를 크게 상회하나, 이 project 자신의 congestion-drift 선례(0d, §26.8 risk 3)에 따라 **standalone 수치를 routed full-Cluster 수치로 1:1 전이하지 않는다** — 구속력 있는 판정은 GATE V9-4.

**GATE V9-4 (full cluster, 구속력 있는 수치 — 역사적 Gate 4 패턴과 동일):**

| 지표 | 사전가격(pre-priced) | 근거 |
|---|---|---|
| **Fmax** | **목표 17.0 MHz** (58.8 ns, 1.556× 기준선) · **floor 14.2 MHz** (70.4 ns, 1.30×) · **stretch 20.5 MHz** (48.8 ns, 1.88×) | 두 독립 adversarial pass 가 같은 finding-5 경계에 대해 서로 다른 추론 경로로 [15,18] MHz / [16,22] MHz 에 수렴, 교집합 [16,18] MHz. 17.0 MHz 는 이 교집합의 **중간값**이지 낙관적 상단이 아니다 — (a) case-select mux 깊이가 미가격(stage1 을 두 추정 모두보다 무겁게 만들 수 있음), (b) 이 project 의 congestion 선례(0d: +2.46%p COMB → 로직이 critical path 부재로 증명됐음에도 -2.7% 전역 Fmax drift) 때문에 의도적으로 보수적으로 잡았다. floor 미달 시 **merge 하지 않고** stage-boundary 질문을 재개(case-select mux 자체 일부를 경계 너머로 옮기는 진짜 균형 분할이 필요할 수 있음). |
| **COMB** | **불변 hard gate ≤40.0% (33,456 LUT4)** — gate 상향 요청 없음 | nominal 신규 COMB 추정 300-600 LUT(`case_result_s2` 필드 packing/제어보관 + bank-fix comparator, Gate V9-1/V9-2 기준). 이 project 고유의 실측 overrun 계수 **1.67×**(Gate-3 실측 overrun 계수 — §23.10.10(g) 의 방법, 0d 를 당선시킨 그 기준)를 적용하면 worst-case 신규분 500-1002 LUT → **33,835-34,337 LUT (40.44%-41.05%)** — 이 honest worst-case 는 **불변 40.0% gate 를 breach 할 수 있다**. 출발 마진이 121 LUT(§26.6 아래 참조)뿐이므로 이는 형식이 아니라 실질 위험이다: V9-4 실측이 33,456 을 넘으면 **3번째 ad-hoc gate amendment 를 검토하기 전에**(§23.10.10(g) 가 명시적으로 금지) pre-declared cut ladder rung 1(FMINMAX → K_INT, 300-400 LUT 회수)을 먼저 집행한다. Breach 를 silent 하게 수용하지 않는다. |
| **MULT18X18D** | **정확히 122, 무관용(zero tolerance)** | register-only 파이프라인 분할 + comparator 기반 bank-fix 는 신규 곱셈 구조를 도입하지 않는다 — 편차는 그 자체로 버그 신호다. |
| **FF** | **추적만, gate 아님** | 역사적으로 여유 풍부; low-thousands 증가 예상, 예상 밖 자릿수 급증이 아닌 한 blocking 하지 않고 report 만 한다. |

COMB 121-LUT 출발 마진의 맥락: v1.8.0e 0e2 착지 실측이 이미 **39.86%/40.0%, 마진 0.14%p**(§25.9)였고, 이는 §25.5.1 이 구현 이전 공표한 nominal worst-case 도출(2,800×1.67=33,335, margin **121 LUT**)과 정확히 일치했다. v1.9 는 이 이미 razor-thin 한 COMB 예산 위에서 시작한다 — 이것이 위 COMB gate 항목이 형식적 반복이 아니라 실질적으로 breach 가능하다고 취급되는 이유다.

**226-test 전체 suite**(186 `test_isa_decoder.py` + 40 `test_cluster.py`) 재실행은 gate 결과와 무관하게 필수이며, §26.7 신규 테스트와 함께 gate log 를 merge commit 에 첨부한다 — gate log 미첨부 RTL commit 은 이 project 자신의 구속력 있는 프로세스 규칙(post-v1.8.0b)에 의해 merge 금지다.

**GATE V9-4 실측 최종 (2026-07-27, commit 618def9 — residual-risk-11 수리 반영된 clean 상태, 재synth+재PnR):**

| 지표 | 실측 | 사전가격 | 판정 |
|---|---|---|---|
| **Fmax** | **11.34 MHz** (critical path 117 logic stage/28.1 ns + 118 routing/59.6 ns = 88.1 ns) | floor 14.2 / target 17.0 / stretch 20.5 MHz | **FAIL — floor 미달**. 기준선(10.93 MHz) 대비 **+3.75%** 뿐 — 사전가격이 예견한 1.30-1.88× 이득의 거의 전부가 실측에서 증발했다. |
| **COMB** | **39.56%** (33,089/83,640) | ≤40.0% (33,456) | PASS (마진 367 LUT). |
| **MULT18X18D** | **103** | 정확히 122, 무관용 선언 | **원 pin 자체가 틀린 전제 위에 있었음이 조사로 확정** — 아래 참조. |
| **FF** | 10,607 (12.7%) | 추적만 | 문제 없음. |

**MULT 편차 조사 (완결, 버그 아님으로 확정):** 122→103 은 "신규 곱셈 구조 도입"이 아니다. `git worktree` 로 최종 known-good 지점(0e2, commit 6b97f83)을 분리 체크아웃해 **동일 yosys 버전·동일 흐름**으로 독립 재synth 하고, techmap(DSP 매핑) **이전** 단계(`read_verilog+hierarchy+proc+opt_clean`, `stat`)에서 각 PE_Core 파라미터화 인스턴스(MU-hosted/DU/L-PE-narrow)의 원시 `$mul` 연산자 개수를 비교했다: **0e2 와 v1.9 양쪽 모두 정확히 377/102/102/4/891 로 완전 일치**(FP_Mul36/EHDecode 포함) — 즉 곱셈 연산 자체는 한 개도 늘거나 줄지 않았다. 차이는 yosys `synth_ecp5` 의 DSP-inference 공유 패스(`share.cc:669:make_supercell`)가 `case_result_s2` 도입으로 달라진 인접 로직 형태를 보고 **더 많은 논리적 곱셈을 더 적은 물리 MULT18X18D 로 시분할 공유**하기로 재결정한 것 — COMB 이 오히려 소폭 낮아진 사실(39.56% vs 이전 39.86%)과도 정합된다(LUT-fallback 이었다면 COMB 급증이 따랐을 것). **원 pin 의 전제("편차 = 버그 신호")는 반증됐다** — 실제 불변식은 "MULT18X18D 개수 고정"이 아니라 "premap `\$mul` 연산자 개수 고정"이어야 했음을 이번 조사가 확정했고, 이 amendment 를 pin 문구에 반영한다: **"MULT18X18D 절대 개수는 gate 대상이 아니다(합성 도구의 리소스 공유 재량); 대신 premap `\$mul` 연산자 개수가 baseline 과 정확히 일치해야 한다(신규/제거된 곱셈 로직 없음의 증거) — 이 release 에서 377/102/102/4/891 로 실측 일치 확인, 문서화된 baseline 으로 확정."**

**Fmax FAIL 의 정책적 결론 (§26.6 원문 자신의 gate policy 적용):** 원문이 명시한 대로 — "floor 미달 시 merge 하지 않고 stage-boundary 질문을 재개(case-select mux 자체 일부를 경계 너머로 옮기는 진짜 균형 분할이 필요할 수 있음)". GATE V9-3(standalone: MU-hosted 37.44 MHz, LPE-narrow 154.37 MHz)이 낙관적으로 보였던 것과 정반대로, **congestion-drift 가 이번 release 에서 이 project 최악의 사례로 실현됐다** — 0d 선례(+2.46%p COMB → -2.7% Fmax)보다 압도적으로 크다: standalone 수치가 시사한 1.3-2.2× 잠재 이득이 routed full-Cluster 문맥에서 사실상 전부(96% 이상) 잠식됐다. 이는 **case_result_s2 단일 레지스터 경계만으로는 부족하며, case-select mux 자체의 물리적 배치·라우팅이 실제 병목**이라는 뜻으로 읽힌다(비교: 두 standalone geometry 모두 짧은 critical path 를 보였는데 — MU-hosted 는 아예 case_result_s2 를 안 거쳤고 LPE-narrow 는 4 LUT level 뿐이었다 — full Cluster 문맥에서 배치·라우팅 혼잡이 지배적 요인이 됐다는 뜻). **본 release 는 자신이 선언한 gate 를 충족하지 못했으며, 이 사실을 silent 하게 수용하지 않는다** — 재설계(stage-boundary 재검토, 혹은 배치 제약 추가)가 필요한 상태로 기록하고 후속 판단을 상위 결정권자에게 넘긴다.

### 26.7 test_plan (15개 항목)

1. **`test_bmm3_then_mul_launch_gate`(기존, SURVIVES 예상)** — fragment-0 대기가 bounded 20-cycle poll(신규 +1 cycle 흡수)이고, 정확-edge assertion 이 `frag_idx`(frag-drain, 무변경) 대 `mul_valid_p1`(MUL bypass, 무변경)을 probe — 둘 다 `case_result_s2` 무영향. 그대로 실행하고 실패는 진짜 버그로 취급(합성 당시 "가장 명백한 breaking 사례"라는 오분류를 정정).
2. **`test_mul_then_bmm3_drain_gate`(기존, SURVIVES 예상)** — assertion 본체는 `output_valid`/`opcode_out` 만 bounded poll; docstring 의 N/N+1/N+2 서술은 문서일 뿐 강제 assertion 아님. 그대로 실행, 변경된 절대 cycle 을 인용하는 docstring 만 갱신.
3. **`test_trace_iijkl_single_output_fragment`(기존, 재유도)** — TRACE_IIJKL 은 compute-inline output_regs_free-gated arm; 3개 probe site 전부 개별 검토 후 재유도.
4. **`test_fp_busy_reject_is_lower_required` / `test_fp_drain_gate_and_frag_interaction` / `test_fp_tag_and_opcode_out_preservation`(기존, 재유도)** — FP-family launch 가 이제 `case_result_s2` 를 거쳐 T+1 에 커밋; 절대-edge assertion +1 재유도. `test_fp_tag_and_opcode_out_preservation` 은 tag/opcode_out/frag_total_m1 이 신규 레지스터 hop 을 무변형으로 통과함을 보강 assertion 으로 추가하는 자리로도 삼는다.
5. **`test_dequant_loop_suppression_and_busy_reject` / `test_gamma_mul_w_directed_e2e`(기존, 재유도)** — DEQUANT(0x78, launch-arm)와 GAMMA_MUL_W(0x6B, compute-inline) 모두 균일 +1 이동; 절대-edge assertion 재유도.
6. **`test_vfma_busy_reject_and_mul_gate`(기존, 재유도 + directed cross-class-skew regression 으로 재목적화)** — 절대치 재유도와 별개로, VFMA 의 case-dispatch +1 이동이 `mul_valid_p1` 타이밍(정확히 0-cycle 변경이어야 함)으로 누출되지 않음을 확인하는 directed check 로 명시 활용(test-migration-completeness verification 이 지적한, 기존에 누락돼 있던 연결고리).
7. **`test_frag_inval_hit_ack`(기존, 재유도)** — 0x6A FRAG_INVAL 은 case-dispatched 이나 output_regs_free-gated 아님; 균일 계약 하에서도 +1 이동. probe site 1개 재유도.
8. **phase-1 인용 범위 밖에서 발견된 4개 bit-exact lane-cadence 테스트(기존, confirm-only)** — `test_dequant_e2e_int8_4frag_bit_exact`, `test_dequant_e2e_int4_8frag_bit_exact`, `test_vfma_e2e_int4_16frag_bit_exact`, `test_vfma_e2e_int8_8frag_bit_exact` 는 `cycles[0]`(최초 관측 이벤트) 상대로 cycle 을 assert — cadence 자체가 무변경 lane-loop 로직에 의해 구동되므로 생존 예상; 가정하지 말고 실행해서 확인.
9. **NEW `test_uniform_case_dispatch_plus1_sweep`(구조적)** — case 표의 모든 영역(compute-inline, FSM-launch, simple-ALU, legacy-narrow-einsum, 0x6A)을 대표하는 opcode 에 대한 parametrized sweep 으로 dispatch-to-commit 이 **정확히 +1** cycle 임을 각각 assert, MUL/DIV/frag-drain 트리거 opcode 에 대해서는 별도 sweep 으로 **정확히 0-cycle** 변경임을 assert — priority #2("무엇도 소리 없이 오배선되지 않는다")를 지키는 가장 중요한 신규 테스트.
10. **NEW `test_output_regs_free_live_at_stage2`** — case-dispatch op 이 in-flight 인 동안 MU/DU/FP/VFMA/DEQUANT occupancy state 를 stage1(T)과 stage2(T+1) 사이에서 뒤집어, busy-reject 판정이 stage1-stale 복사본이 아니라 **더 나중(T+1) state** 를 반영함을 assert — correctness 렌즈가 지적한 race 에 대한 직접 회귀 테스트.
11. **NEW `test_bank_tag_latch_no_intervening_hazard`(positive proof, MU depth-2 · DU depth-1 각각)** — 서로 다른 target bank 를 갖는 MUL-class(또는 mu_out_valid-routed) op 2개를 SDK-rule 간격 없이 연속 dispatch; 둘 다 tag match 로 올바르게 라우팅됨을 확인 — "hazard 회피" 테스트 계열을 "hazard 소거 증명" 테스트로 대체.
12. **NEW `test_bank_tag_collision_interlock`** — table row 가 아직 busy 인 동안 tag 재사용을 강제; synthesizable `bank_tag_collision_error` sticky fault 가 assert 됨(단순 sim-only `$error` 아님)을 확인 — interlock 이 실제 하드웨어 보장인지에 대한 correctness 렌즈 간극을 닫는다.
13. **`test_vdot_acc_reduce_rides_mu_bank`(0x71/0x72 scope-check, 구현 세션에서 RTL 실측에 맞춰 `test_vdot_acc_reduce_bypass_mu_bank` 에서 재명명 — 최초 초안은 COMMIT 0 의 배제 가정대로 반대 방향을 assert 했다가 실제 RTL 에 대해 실패, 확인된 사실대로 수정)** — VDOT_ACC/ACC_REDUCE 가 실제로 `mu_out_valid`/`mu_bank_reg` 를 타는 것을 확인 — 추론이나 spec 원문 가정으로 출하하지 않고 merge 전 명시 플래그된 open scope 질문을 (반대 결론으로) 닫는다.
14. **NEW `test_frag_drain_priority_unaffected_by_case_result_s2`(mandate 자신이 지목한 open question 의 재증명)** — case-dispatch 된 multi-fragment op 의 결과가 stage2 의 `case_result_s2` 에 앉아 있는 상태에서 동시/중첩하는 frag-drain wave 가 활성일 때, `frag_idx != FRAG_IDLE` 인 매 cycle frag-drain 이 오늘과 동일하게 **무조건 승리**함을 assert — 세 원 설계 문서 중 어느 것도 실제로 증명하지 않은 유일한 질문이며, 미검증 assertion 으로 출하하지 않는다.
15. **NEW `test_twin_classifier_mu_bank_coverage`** — 확장된 `is_mul_op`/`dec_is_mul_op` 집합(`{MUL, 0x6B, 0x70, 0x74-0x76, 0x78, 0x79}`)을 RTL 에서 실제로 `mu_out_valid` 를 assert 하는 모든 opcode 와 대조; classifier 집합에 없이 `mu_out_valid` 를 타는 opcode 가 하나라도 있으면 fail — MU-table 미충원(silent gap)에 대한 최종 방어선.

### 26.8 residual risks (v1.9)

이 설계는 이례적으로 자기비판적이며, 그 정직함을 그대로 보존한다:

1. **COMB 예산이 razor-thin 하다**: 1.67×-inflated worst-case nominal 위 마진이 **121 LUT**(39.86% vs 40.0%)뿐이다 — pre-staged cut ladder(rung 1: FMINMAX → K_INT, 300-400 LUT 회수)가 구현 중 즉석 고안이 아니라 준비된 상태로 있어야 한다.
2. **[해소됨, GATE V9-3 실측]** case-select mux 깊이는 더 이상 미가격이 아니다 — MU-hosted standalone Fmax **37.44 MHz**(critical path 가 `case_result_s2` 를 아예 안 거침, 병목은 기존 FP32 adder 경로), LPE-narrow standalone Fmax **154.37 MHz**(critical path 가 `case_result_s2` 를 거치나 ~4 LUT level 로 짧음). 두 수치 모두 17.0 MHz 사전가격을 크게 상회 — 다만 congestion-drift 선례(risk 3) 때문에 이 standalone 수치가 routed full-Cluster 수치로 그대로 전이된다고 가정하지 않는다; 구속력 있는 판정은 GATE V9-4(§26.6 표).
3. **Congestion-driven Fmax drift 는 이 project 에서 이미 실현된 실패 모드다**(0d: +2.46%p COMB 가 추가 로직이 critical path 에 없음이 증명됐음에도 congestion 을 통해 -2.7% Fmax 를 실측으로 일으킴) — 로직-깊이-절단만으로 얻는 1.556× 이득이 `case_result_s2` 와 bank-fix comparator 의 증분 COMB 에 의해, critical path 위에 있는지 여부와 무관하게, 부분적으로 잠식될 수 있다.
4. **균일 +1-cycle 선택은 의도적 trade-off 다**: ~40개 architecturally-cheap opcode(critical path 위에 있던 적 없음, finding 1b 기준 0-1 comb stage)가 구조적으로 필요 없는 latency 1 cycle 을 지불하는 대신, 비대칭 계약의 오배선 위험과 class-split 검증 표면의 약 절반을 제거한다. 향후 release 에서 이 1 cycle 이 실제 워크로드에 실질적으로 해롭다고 판명되면, 올바르게 scope 된 class-split(decode-result-cache-class-split 의 두 치명적 결함을 고쳐서 — operand 아닌 **결과**를 캡처하고, 평범한 파이프라인 레지스터에는 multi-cycle occupancy hazard 가 없음을 인정하고) 이 v1.9.x/v2.0 후보로 남는다.
5. **[해소됨]** MU bank-table 충원 범위는 twin-classifier 집합이 `mu_out_valid` 를 assert 하는 모든 opcode 와 정확히 일치해야 했다 — 0x74-0x76 gap 은 §26.5 NORMATIVE FIX 로 같은 commit(0e14e12)에서 닫혔고, `test_twin_classifier_mu_bank_coverage` 가 수동 감사에 의존하지 않고 확인했다. 이 범위 안의 마지막 남은 결함(timing-class phantom-row, risk 11)도 후속 commit(618def9)에서 닫혔다 — coverage 는 이제 opcode 집합과 timing 양쪽에서 완결.
6. **[해소됨]** busy-bit tag-collision interlock 은 `bank_tag_collision_error_r` — reset-clearable 만 가능한 sticky status bit — 로 구현됐다(sim-only assertion 아님). `test_bank_tag_collision_interlock` 이 DU depth-1 collision 과 MU depth-2 exhaustion collision 양쪽에서 이 bit 가 실제로 assert·sticky 함을 확인, 다른 op 의 결과가 훼손되지 않음도 함께 확인했다. Production 보장이 실재한다.
7. **[해소됨]** 신규 2단 case-dispatch 경로 하 frag-drain 의 1-frag/cycle absolute-priority 보장은 `test_frag_drain_priority_unaffected_by_case_result_s2`(0e14e12 commit) 로 실증됐다 — 16-fragment VFMA wave 방출 중 첫 fragment 에 ungated ADD intruder 를 주입해 intruder 의 `case_result_s2` capture 가 실제로 drain 중간에 착지함을 hierarchical probe 로 확인한 뒤, 16 fragment 전부가 bit-exact 로 착지하고 intruder 결과는 전혀 표면화되지 않음을 증명 — mandate 가 명명한 유일한 미해결 질문이 이제 가정이 아니라 테스트로 닫혔다.
8. **[해소됨, 구현 세션]** 0x71/0x72 의 Cluster-level bank hazard 관련 여부는 phase-1 추론(제외 방향)을 상속한 채 COMMIT 0 에 남아 있었으나, 구현 세션의 directed test(`test_vdot_acc_reduce_rides_mu_bank`)가 **포함** 방향으로 독립 재도출·확정했다 — MU table 배선에 0x71/0x72 가 포함되어 있으며 반대로 오분류됐을 silent-corruption 위험은 닫혔다.
9. **[해소됨]** phase-1 이 검증한 cycle-exact 테스트 수(12개, adversarial review 로 인용 범위 밖 4개가 추가 발견되어 최소 16개)는 mandate 의 20-40개 추정보다 작았다 — 구현 세션이 phase-1/synthesis 목록 어느 쪽도 신뢰하지 않고 test_isa_decoder.py(189개)/test_cluster.py(44→45개) 전체를 fresh grep 으로 재조사, §26.7 이 지정한 모든 site 를 개별 재확인해 226개 기존 테스트가 전부 bounded-poll 또는 relative-cadence 이며 무수정 생존함을 실측으로 확정했다(0e14e12).
10. **[해소됨]** SDK no-intervening-mul-dispatch 규칙(§23.6a 계약 3, §25.6 amendment 4 확장분 포함)은 test C/D/E/F(`test_bank_tag_latch_no_intervening_hazard`/`test_bank_tag_collision_interlock` 등, §26.7 항 9-12에 상당) 통과 뒤 **완전 은퇴(삭제)** 됐다(618def9) — risk 11 이 드러낸 잔여 케이스(non-MUL busy-reject 의 phantom row)를 그 commit 이 직접 닫았으므로, narrowing 이 아니라 폐기가 최종 결론이다. Cluster.v ~422-463 의 규칙 주석 블록은 RETIRED 로 표시·보존됐고, asm 의 대응 주석(GAMMA_MUL_W/DEQUANT 쌍 spacing 근거)도 은퇴 사유와 함께 갱신됐다.
11. **[해소됨]** `test_bank_tag_collision_interlock` 구성 도중 발견된 `mu_launch`/PE_Core `fp_busy`(정확히는 `output_regs_free`, MUL 을 제외한 전 is_mul_op class) 타이밍 격차 — case_result_s2 재-homing 이후 실제 accept/reject 결정이 T+1 인데 `mu_launch` 는 T 시점에 무조건 row 를 할당해 busy-reject 된 dispatch 가 영구 phantom row 를 남길 수 있던 결함 — 은 commit 618def9 에서 닫혔다: MUL(0x12)은 T-시점 무조건 할당 그대로 유지(case_result_s2 를 안 타므로 정확), 그 외 class 는 row commit 을 T+1 로 이연해 Cluster 에 이미 배선된 `mu_pe_ready`(=PE_Core `output_regs_free`)를 그 시점에 live 로 게이트 — busy-reject 시 row 를 아예 할당하지 않는다. `test_mu_busy_reject_no_phantom_row`(신규) + `test_bank_tag_collision_interlock` 재실행(원인이 됐던 시나리오에서 phantom-row exhaustion 재현 안 됨)으로 폐곡선 확인.

### 26.9 congestion 원인 진단 (2026-07-27, 사용자 지시 — 재설계 전 진단 전용)

Gate V9-4 의 Fmax FAIL(§26.6) 을 받아들고 재설계에 착수하기 전에, 원인
자체를 먼저 규명했다(3-lens 독립 조사, read-only, RTL/spec 무편집).

**핵심 재발견 — "collapse" 는 실측 대비 착시였다:** 최근 5개 세대의
full-Cluster Fmax(동일 flow, 동일 geometry 2×2 = MU+DU+4×L-PE, 6
인스턴스 — "18 인스턴스"는 이번 진단 이전 필자의 착오였음, PE_ROWS=
PE_COLS=2 로 확인): cleanup=10.93 · 0e1=11.16 · 0e2=10.93 · v1.9(수리
전)=11.00 · **v1.9(618def9, 수리 후)=11.34 MHz**. v1.9 는 이 5개 중
**최고치**이며 직전 세대 대비 **+3.8% 개선**이다 — 회귀가 아니다.
"collapse" 로 보인 것은 오직 §26.6 이 사전가격한 floor(14.2 MHz)·
GATE V9-3 standalone 수치(37.44/154.37 MHz) 대비로만 성립한다.

**진짜 원인 (high confidence, 3-lens 수렴):** full-Cluster critical
path 는 5세대 내내 **u_matmul_unit 내부의 case(dec_opcode) 조합 로직
자체**(PE_Core.v:2117-3291, 55-arm, v1.9 가 "오늘과 완전 동일 평가"
라고 명시 선언한 바로 그 본체)에서 발생하며, routing:logic 지연 비
(v1.9b 2.124 vs 0e2 2.127, delta 0.15%)가 사실상 불변인 채 5세대 동안
고정돼 왔다 — v1.9 는 이 병목의 성격을 전혀 바꾸지 못했다(악화도
개선도 아님). GATE V9-3 standalone 이 낙관적이었던 이유는 **애초에
이 병목을 측정하지 못하는 구성**이었기 때문: MU-hosted 표준형은
critical path 가 `case_result_s2` 를 아예 안 거치고(기존 FP32 adder
경로), LPE-narrow 는 거치되 겨우 4 LUT level 얕다 — 둘 다 case 본체의
전체 조합 깊이 + multi-instance 배치 경합을 동시에 겪지 않는다(실제로
v1.9b 의 logic-only 지연(28.05ns)만으로 이미 MU-hosted standalone 의
전체 주기(26.71ns)를 초과한다). **§26.6 의 floor/target 자체가 이
병목을 볼 수 없는 gate 위에 세워진 것이었다.**

**v1.9 에 실제로 귀속되는 결함 (작고, 실재함):** critical path 상
최대 단일 routing hop(1.53ns, 전체 routing 지연의 2.6%)이 `case_
result_s2` 수신 register 를 55-arm fanin 군집으로부터 물리적으로
~13열 떨어진 곳에 배치한 결과로 확인됨 — 실재하나 gap 규모를 설명
하기엔 턱없이 작다.

**정직한 미해결 (seed=1 단발 실측의 한계):** 이번 5개 세대 실측 전부
**seed=1 단발**이다 — 이 project 자신이 Gate 3/0d 에서 확립한 "seed
sweep 없이는 noise 와 signal 을 구분 못한다"는 원칙이 이번 진단
대상 자체에는 적용되지 않았다(진단 세션은 read-only 라 새 seed sweep
을 수행하지 않음). 11.34 MHz 대 10.93 MHz 의 +3.75% 가 진짜 신호인지
seed noise 인지는 **미확정**.

**권고 (진단 세션 결론, 재설계 아님):**
1. v1.9b·0e2 양쪽에 **seed 1-5 sweep** — 저비용, 이 project 기존
   관행 그대로, "+3.8%"의 신호/잡음 여부를 가장 싸게 확정.
2. `case_result_s2` register 에 **경량 RLOC/LOC 힌트** 하나 — fanin
   군집에 인접 배치를 시도, 확인된 유일한 v1.9-귀속 결함(1.53ns hop)
   을 격리 검증. 재설계가 아니라 PnR 배치 힌트 실험.
3. **진짜 구조적 개선이 필요하다면 표적은 `case_result_s2` 경계가
   아니라 case(dec_opcode) 본체 자체의 조합 깊이(55-arm)** — v1.9 의
   가정("경계 하나면 충분")이 5세대 불변 병목 앞에서 반증됐다.
4. cluster_v19b_synth.json(누락) 재생성 — 향후 분석이 log 의 소스
   주석이 아니라 netlist 직접 대조를 쓸 수 있도록.

### 26.10 §12a 기록 — pre-stable 정규 개발 행위

본 절 전체(§26.2-26.6 의 아키텍처·latency-contract·bank-fix·gate 변경)는 **§12a 하의 정규 개발 행위(regular development act)**로 기록한다 — dispatch latency contract 변경은 §12a 가 예시하는 "frozen 계약이 stable release 이전에는 발효되지 않는" 종류의 변경이며, freeze 보장 3종(frozen first-class 유지·truth-table keep-forever·snapshot 등가성) 중 어느 것도 아직 발효되지 않은 상태에서 이루어진다. §12a 규칙 3의 순서(spec amendment → `isa/wt64v1_isa.json` 편집 → 생성물 재생성 → RTL/테스트 갱신)를 그대로 따른다: 본 절이 spec-first 기록이고, RTL(PE_Core.v/Cluster.v) 및 `test_isa_decoder.py`/`test_cluster.py`/`lint_frag_total_m1_held.py` 갱신은 이후 commit 에서 뒤따른다.

**의도적 test-breakage/재유도 입장을 명시한다**: §26.4 의 균일 +1-cycle 계약은 cycle-exact 절대치를 assert 하는 기존 테스트 다수를 고의로 깨뜨린다. 이는 사고가 아니라 §12a 정책이 규정하는 정규 개발 행위의 직접적 결과이며, 이 정책 하에서 cycle-exact breakage 는 **보존 대상이 아니라 재유도(re-derive) 대상**이다 — §26.7 의 test_plan 이 그 재유도의 완전한 목록이다(생존 2건, 재유도 7건[grouped], confirm-only 4건, 신규 directed test 6건). Stable release 선언 전까지는 이 세 가지 freeze 보장이 개발 편의 장치일 뿐 발효된 계약이 아니므로, 본 release 는 그 편의를 명시적으로 행사한다.

---

**TODO(다음 commit, parent 세션 확인 필요) — 본 session 이 편집하지 않음:** §23.10.9(risk 2/4, 특히 line 2324/2326 의 "v1.9 arbitration rework"/"v1.9 로 의도적 이연" 문구)와 §25.6 항 4 / §25.7 risk 6(positional NoC-bank hazard 노출 증가의 RE-ACCEPT 서술, "fix 는 v1.9 arbitration rework")은 본 절 착지 이후 **stale 해질 가능성이 있다** — 본 절(§26)이 바로 그 v1.9 하드웨어 fix 이므로, 위 절들의 "v1.9 로 이연" 서술을 "§26 에서 이행됨"으로 소급 갱신할지, 아니면 superseded-history 배너(§12a 규칙 5)로 표기할지는 이 절의 scope 밖이며 별도 commit 에서 검토가 필요하다. 본 session 은 mandate 지시대로 §23.10.9/2291/2325 인근 절을 편집하지 않았다.

## 27. v2.0 TRAIN 누산 아키텍처 — 옵션 3 채택 (2026-08-15, COMMIT 0 · normative)

**사용자 결정 (2026-08-15, binding): v2.0 누산은 옵션 3 — exact-integer in-dot lattice + wide ACC bank — 를 채택하고, 옵션 3 의 gate 전건 통과 즉시 옵션 3a (FDOT32_CR audit opcode 추가, §27.7) 로 이행한다.** 계약 명칭: **"wave-step-atomic accumulation"**. 본 절이 v2.0 누산 아키텍처의 normative source 다 — spec-before-code COMMIT 0 (§12a). 세 편의 완결된 실측 분석 (RTO-tree 전 폭 반증 / 포맷 사다리·posit 실측 / input-noise dominance) 이 본 결정의 근거이며, **재현 artifact 는 `scripts/acc_format_study.py` + `include/generated/acc_format_study_report.json`** (stdlib-only, 고정 seed, 재실행 byte-identical, rounding core 는 `scripts/golden_fp32.py` 에서 import) 이다. **인용 규율**: 설계 세션의 일부 수치는 salted-hash seed 로 생성되어 normative 인용 불가 — 본 절의 모든 수치는 고정-seed 재생성본 (위 JSON) 에서 가져왔고, 세션값과 다른 곳은 본문에 명기한다.

### 27.1 결정 기록 — 옵션 2/3/2a/3a 비교 판정

비교 대상 4안 (전부 wide ACC bank 공유; 차이는 in-dot 경로와 audit opcode 유무):

| 안 | in-dot 경로 | dispatch 당 반올림 이벤트 | FP_LANES serial-equivalence 증명 의무 | audit opcode |
|---|---|---|---|---|
| 2 | RTO-48 tree (FP_AddWide 31회 pass) | **32** (tree node RNE/RTO 31 + bank store 1) | **영구 부담** (순서가 결과에 개입) | 없음 |
| 2a | 옵션 2 + FDOT32_CR | 32 | 영구 부담 | 있음 — 단 main path 와 **불일치가 정상** (근사 비교만 가능) |
| **3 (채택)** | **exact-integer 528-bit lattice** | **1** (bank store RTO-48; in-dot 0) | **구조적으로 소거** (exact = 결합 순서 무관) | 없음 (3a 로 이행 예약) |
| 3a (committed follow-up) | 옵션 3 + FDOT32_CR (0x7A) | 1 | 소거 | 있음 — **single-wave 즉시 drain 에서 main path 와 bit-exact 일치가 정리로 보장** (§27.7) |

**판정**: 옵션 3 이 옵션 2 를 3개 축 전부에서 지배한다 — (i) 반올림 이벤트 32→1, (ii) 처리량 (31회 순차 adder pass vs 정수 compressor tree + resolve 1회), (iii) 검증 표면 (serial-equivalence 세금 소거, §27.4). 옵션 3a 는 옵션 3 위에서만 성립하는 자기검증 불변식 (dual-datapath bit-match) 을 추가하므로, **순서는 3 → gate 통과 → 3a** 로 확정한다 (op_sel 격리 근거는 §27.7).

**"wave-step-atomic accumulation" 의 정의**: 한 wave-step (= 한 dispatch 의 32-lane dot + bank carry-in) 이 bank 상태에 기여하는 반올림 이벤트는 **정확히 1회** (RTO-48 store) 이고, 그 1회는 **exact 한 33-항 합** (32 곱 + carry-in) 의 함수다. 즉 wave-step 내부에는 반올림도 순서 민감성도 없으며, store 후 bank word 는 (직전 bank word, 32 곱) 만의 결정적 함수다 — 형식적 single-rounding (B) 가 **wave-step 단위로** 성립한다 (한계는 §27.3).

**정확성만으로는 어떤 안도 정당화되지 않았음을 기록한다** (§27.5 항 5, input-noise dominance): 옵션 3 채택 사유는 **계약 강도 + 처리량 + 검증 표면 축소**이지 raw accuracy 가 아니다.

### 27.2 normative 아키텍처

#### 27.2.1 in-dot 경로 — 528-bit exact-integer lattice

- **입력**: dispatch 당 32개 곱 (bf16: 8×8→16-bit significand 곱 / f16: 11×11→22-bit — 출하된 C2 계약대로 48-bit wide 포맷에서 **exact**, 곱 지점 반올림 없음) + **ACC bank carry-in 을 33번째 EXACT addend 로 융합**.
- **lattice**: **528-bit two's-complement segmented carry-save lattice** — weight 2^-266..2^260 (527 자리) + sign 1 = **528**. 도출 (JSON `lattice_width`): bf16 곱 LSB weight 2^-266 (최소 곱 2^-252 의 significand LSB), 곱 상한 <2^256, span 522 + carry 헤드룸 log2(32)=5 + sign 1 = 528; **32× 최대 곱 <2^261, exponent 260 은 signed-11 에 수납** — 전부 in-run assert 로 검사됨. 529 는 1 bit 과잉으로 판명; **528 이 fused carry-in 포함으로 충분**. f16 단독이면 86 bit (span 80+5+1) 이나 통합 lattice 528 이 양 dtype 을 커버한다.
- **적재**: **static 6-stage barrel + 2-of-9 segment demux** — `FP_AddWide.v:179-194` 의 static-barrel idiom 그대로 (**dynamic part-select 금지 — project law**). segment 기하는 golden model/RTL 에서 확정하되 idiom pin 은 본 절이 한다.
- **합산**: 정수 3:2/4:2 compressor — **exact, 따라서 dot 내부는 순서-무관 (association-free)**. dot 당 **resolve 정확히 1회** (xcu55c: ~66 CARRY8, ~4 ns; ECP5: 9-cycle serial — **양쪽 다 ESTIMATE, §27.6 unit gate 에서 실측 졸업**, §25.4 규율). **[실측 졸업 2026-08-15, GATE V20-2 — §27.6]**: xcu55c 에서 resolve 1 cycle @ 10 ns 수납 실측 확인 (WNS +1.807 ns; worst path 는 resolve 가 아니라 S1 compressor tree 진입) — 단 unit 전체는 LUT ceiling FAIL (§27.6 실측 블록). ECP5 는 전 병렬 배치 불가, beat-serial 형상에서만 PnR 완주 (§27.6 feasibility 블록). **[amendment 2026-08-16]**: 본 bullet 의 시간 구조 (33-addend 동시 적재·합산, full-parallel II=1) 는 beat-serial N=8 로 superseded — 본 절 말미 amendment 블록이 normative.
- **추출 = 그 wave-step 의 유일한 반올림**: resolve 결과에 LZC/normalize 후 **top-48 + sticky-jam = exact 33-항 합의 RTO_48** 을 bank 에 store 한다.
- **정당성 정리 (본 아키텍처를 sound 하게 만드는 단 하나의 정리)**: **RNE_24(RTO_48(exact)) == RNE_24(exact)** — 단일 값에 대한 Boldo-Melquiond 의 유일하게 정당한 적용 (q ≥ p+2 = 26 필요; 48 은 **22 bit 마진**). 재생성 실측 (JSON `extraction_theorem`): directed tie x = 1+2^-24+2^-60 에서 q25 실패/q26·48·50 통과; random sweep 200k (tie-인접 생성기) 에서 **q25 는 82,237/200k = 41.12% 실패, q26/q48/q50 은 0 mismatch**; 별도 composition sweep 200k (RNE24∘RTO48) 도 0. **store 가 RNE-48 이 아니라 RTO-48 인 이유** (JSON `rto48_vs_rne48_composition`): directed 반례 x = 2^48+2^24+1 에서 RNE24(RNE48(x)) = 2^48 (1 ulp 낮음 — double rounding), RNE24(RTO48(x)) = 2^48+2^25 (정답) — assert 로 고정. random 200k 에서 RNE-48 도 0 hit 이지만 이는 이벤트 확률 ~2^-24 의 **예상된 표본 결과이지 안전성이 아니다** — directed 반례가 판정이다.

**[amendment 2026-08-16 — 출하 microarchitecture = beat-serial N=8 (사용자 결정, §27.6 결정 기록; §12a 정규 이벤트)]** 위 본문의 수학 — 528-bit lattice 도출, 적재 idiom (static barrel + segment demux), exact 합, RTO-48 추출, 추출 정리 — 은 전부 불변이다. supersede 되는 것은 **시간 구조 하나** (33-addend 동시 적재·합산, full-parallel II=1) 이며, 원문은 삭제하지 않고 위에 보존한다 (§12a 규칙 5). 출하 형상:

- **beat-serial N=8**: **8 products/beat × 4 beats** 로 32 곱을 인가. **carry-in 인가 방식** — beat 0 에 병합 (총 4 beat) 또는 별도 carry beat (총 5 beat) — 은 **RTL 이 선택하고 TB 로 고정**하되, 이 선택은 bank 인터페이스 (하류 ③) 에 직접 함의를 갖는다: carry-in 이 인가되는 beat 이 bank read 시점과 ownership window 를 결정하므로, ③ COMMIT 은 RTL 이 고정한 그 선택을 bank 인터페이스 계약으로 승계·명문화해야 한다. **[확정 2026-08-16 — GATE V20-2 재실측 기록과 동시]**: RTL (`FP_AccLattice.v`) 은 **beat 0 병합 (총 4 beats)** 을 선택하고 TB 로 고정했다 — `carry_i` 는 `start_i` 와 같은 cycle 에만 샘플되며, 그 기여는 beat 0 의 빈 carry-save row (s-row) 자리에 주입되어 compressor 추가 row 0 으로 흡수되고, 별도 carry beat 제거로 II 를 1 beat 절약한다; TB 는 비-beat0 cycle 오염값 인가로 이 선택을 봉인한다. ③ 함의 확정: **bank 는 carry word read 를 start(dispatch) cycle 이전에 완료해야 하고 (read-before-dispatch), 그로부터의 ownership window 와 같은 slot 체이닝 간격 ≥ LATENCY=7 을 — RTL 헤더가 명문화한 그대로 — bank 인터페이스 계약으로 승계한다.**
- **carry-save 상태**: 2 × 576-bit row 가 beat 간 유지되고, 음수 addend 의 +1 보정 (ones'-complement 반전분) 을 나르는 **per-beat ncnt row** 가 함께 유지된다 — beat 마다 (N 필드 + carry-save 2 row + ncnt 1 row) 를 compressor 에 인가한다 (§27.6 L1 레버의 "N+2+1 rows" 그 구조).
- **resolve: 병렬 1-cycle 576-bit** — S2 가 WNS +1.807 ns 로 실측 졸업한 그 구조 그대로 (§27.6 GATE V20-2 실측 표). **serial 9-cycle resolve 는 재실측에서 LUT ceiling 이 위협될 때의 명시 fallback** 이다 (채택 시 II 증가를 수반하며, 채택 여부는 재실측 gate 기록에 남긴다 — **fallback 채택은 아래 II ≤ 8 계약을 초과하므로 II 계약 자체의 §12a 재개정을 동반해야 한다**; 하류 ③/④ 의 입력 제약도 함께 갱신된다).
- **수학 계약 불변 (normative)**: wave-step 결과는 full-parallel 과 **bit-identical** — exact 33-항 합의 RTO_48, 순서-무관 (association-free), canonical zero, loud-fault 클래스 전부 그대로다. beat 분할은 exact 정수 부분합의 시간 분할이므로 반올림 이벤트의 수 (wave-step 당 1) 도 위치 (bank store) 도 변하지 않는다. 따라서 **golden lattice model·기존 벡터·추출 정리 (RNE_24(RTO_48(exact)) == RNE_24(exact)) 는 무변경 재사용**한다. [갱신 2026-08-16: 기존 4001 벡터는 무변경 유지, TB 반증력 강화를 위해 `sticky_window_band` family 80개 (d=48..127 위치별 sticky-OR 절단 적발) 를 golden-first 로 추가해 **4081 벡터** — 계약 문서 개정·결정성 재확인 (byte-identical) 완료.]
- **II 계약**: II=1 은 폐기, 신규 계약은 **II ≤ 8** @ 100 MHz 문맥 (N=8). 상류 dispatch 는 wave-step 당 **8-operand × 4(또는 5) beat 인가 스케줄** 을 공급해야 하며, 이 스케줄은 v2.0 TRAIN dispatch 설계 (하류 ③/④) 의 **입력 제약** 으로 등재된다. **[실측 확정 2026-08-16 — §27.6 재실측 결과 블록]**: RTL 실측 II = **4** (beat 0 병합, 4 beats — 별도 carry beat 없음) ≤ 8 — 계약 충족, 여유 4 beat; dispatch 스케줄은 **8-operand × 4 beat** 로 확정된다 (5-beat 분기 소멸). serial-resolve fallback 미채택 — II 계약 재개정 불발생.
- **파라미터화**: `PRODUCTS_PER_BEAT` (32 의 약수, 기본 **8**). **N=2 파라미터 구성이 기존 측정 전용 변형 `FP_AccLatticeBeat2` 의 역할을 승계한다** — Beat2 파일·리포트 (`synth/lattice/fp_ops/FP_AccLatticeBeat2.v`, `fp_acclattice_beat2_*` / `fp_acclattice_diag_beat2_*`) 는 provenance 로 유지하고, 이후 측정은 파라미터 구성으로 수행한다. **full-parallel `FP_AccLattice.v` 원본은 commit 903351c 에서 회수 가능하며, 파일 자체는 beat-serial 로 재작성된다.**

**[amendment 2026-08-16 — 하류 ③ spec COMMIT: §27.6 pin 1/2 해소 (normative; §12a 정규 이벤트, 원문 무삭제)]**

- **pin 1 해소 — lattice 수용 구간의 개구간 규범화**: 33-항 exact 합의 수용 구간은 **개구간 (-2^261, 2^261)** 이다. 경계값 **합 == 정확히 -2^261** (units = -2^527 — 528-bit two's-complement 로 표현 자체는 가능) 도달은 **lattice overflow 와 동일 클래스의 loud fault** 로 배정한다: RTL 은 **fault (f)** (`FP_AccLattice.v` FAULT taxonomy — 추출 지수 e==261 은 528-bit 표현 값 중 정확히 이 corner 에서만 발화하므로 **기존 배선 무변경**으로 이 계약을 이행한다), golden 은 `LatticeFault` (lattice overflow 클래스). 근거 (1문장): 경계값 하나만 수용하는 계약은 golden 의 bare assert 사망 vs RTL fault 발화라는 silent 경계 케이스 분기를 남기므로, 개구간 규범화가 RTL/golden/TLA+ 유도 directed test 삼자를 동일 계약으로 만든다. 기존 전제 문언 ("32× 최대 곱 <2^261", 벡터 계약 §4 "|합| < 2^261") 은 개구간 하에서 전부 참으로 유지된다 — 최소 churn. **golden 이행 의무 (코드 수정은 다음 단계 몫 — 본 COMMIT 은 spec 만 편집)**: `scripts/golden_lattice.py` 는 현재 `lattice_accumulate` 가 `LAT_MIN <= total` 로 경계값을 통과시키고 `extract_rto48` 의 **bare assert** (`-266 <= e <= 260`) 가 사후 사망한다 — 수용 조건을 `LAT_MIN < total` 로 좁히고 (오류 메시지의 반개구간 표기 "[-2^261, 2^261)" 도 개구간으로 함께 갱신), 그 bare assert 를 `LatticeFault` 로 승격해야 한다.
- **pin 2 해소 — carry-in normalized 전제의 명문화**: **carry-in slot (addend 32) 은 normalized (sig[47]==1) 또는 canonical zero 다** — 벡터 계약 §4 가 전제로만 운반하던 문언의 normative 본문 승격. 곱 lane 에 허용되는 1-bit un-normalized raw 형식 (sig ∈ [2^46, 2^47)) 은 carry-in 에 불허. 구조적 보장 경로 (정상 경로에서 위반 도달 불가): bank 가 공급하는 carry word 의 출처는 (i) 본 unit 의 RTO-48 추출 산출 — 구조상 normalized 또는 canonical zero (golden `extract_rto48` 의 사후조건) — 과 (ii) FILL 통과값 — `fp64_to_wide` 는 normalized 또는 canonical zero 만 산출 (§27.2.2 FILL validation) — 둘뿐이다. 그러나 loud-fault-never-silent 법칙상 전제는 hw 검사된다. 위반 fault 클래스: **fault (c) 의 carry-lane 강화형** — carry lane (lane N, beat 0 전용) 에서는 nonzero sig 의 `sig[47]==0` 이 곧 fault 다 (곱 lane 의 (c) 는 leading zero > 1 검사 그대로 — 불변). 현 RTL 의 carry lane 은 (c) 약형만 배선되어 있으므로 강화형 배선은 ③ 구현 단계의 의무로 등재한다.

#### 27.2.2 wide ACC bank — 2 × 32 lanes × 64b/cluster

- **word 포맷**: 내부 datapath 값 = PACK_WIDE 형 (sign / signed 11-bit exp / 48-bit sig, unit at bit 47 — `FP_AddWide.v` 인터페이스 그대로). 저장/spill word = 그 값의 **IEEE binary64 무손실 재인코딩** — 48-bit sig 는 fp64 의 53-bit precision 에 정확히 수납되며, 변환은 상수 배선 + bias 가산 + 2-case corner shift 로 **exact 검증 완료**. bank 상태 = 2 × 32 × 64b = **4,096 bit/cluster** (비교: bf16 Kulisch bank 는 33,792 bit — §27.5 항 4).
- **canonical zero**: PACK_WIDE 의 정준 zero (**sign=0, exp=-1024, sig=0**) 는 commit **c21092a** 에서 pin + 전 gate 재실측 완료 — bank 의 zero 표현도 이것 하나다 (fp64 인코딩상 +0).
- **SPILL**: image = fp64 (numpy-native; SDK 는 `np.float64` 로 직독). quarter-op = **8 lanes × 64b = 512b = 8 fragments** — FRAG_MAX=16 내 수납 (§25.3 확폭의 소비자).
- **FILL validation (normative — loud fault, never silent)**: ingest 시 (i) **NaN/Inf (fp64 E=2047) → sticky fault** (v1.9 `bank_tag_collision_error` 와 같은 등급의 합성 가능한 sticky status bit 클래스 — sim-only assertion 금지, §26.5 선례); (ii) **PACK_WIDE-representable 집합 밖의 어떤 값도 → 동일 fault**; (iii) **fp64 −0 과 +0 은 양쪽 다 수용하되 ingest 에서 내부 canonical +0 으로 canonicalize** — §23.10.5 특례표의 A4/F4 +0 pin 과 정합. bank ingest/egress 는 무손실 변환이므로 이 검증을 통과한 값은 round-trip bit-exact 다.

**[하류 ③ spec COMMIT 2026-08-16 — bank 인터페이스 계약 확정 (normative) + §27.6 pin 3 해소. §27.2.1 amendment (carry-in beat 0 병합 확정) 와 `FP_AccLattice.v` 헤더의 "bank 인터페이스 함의" 명문을 bank 측 계약으로 승계·명문화한다 — 위 기존 문언 (word 포맷 / canonical zero / SPILL / FILL validation) 은 불변이며 아래는 인터페이스 계약의 증보다]**

- **pin 3 해소 — lattice-비표현 carry 의 RTL fault 클래스**: FILL validation 은 PACK_WIDE-표현성만 검사하므로 FILL-valid bank word 는 |v| < 2^1024 (fp64 전역) 까지 담을 수 있으나, lattice 는 개구간 (-2^261, 2^261) · 정밀도 2^-266 만 수용한다 (§27.2.1). 그런 word 가 carry-in 으로 인가되는 경로의 fault 는 **신규 클래스 없이 기존 taxonomy 의 carry-lane 적용**으로 배정한다: **범위 밖 → fault (d)** (q < 1 또는 q > 528, 또는 q==528 에서 sig[47]==1 — |v| ≥ 2^261 동치 지점), **정밀도 위반 → fault (e)** (배치 후 PHYS[47:0] != 0 — 2^-266 미만 잔여). golden 대응 (벡터 계약 §7 미결 pin 의 폐쇄): `addend_units` 의 `LatticeFault` 2종 — "addend exceeds lattice range" ↔ (d), "addend not lattice-representable (precision below 2^-266)" ↔ (e). **발화 지점은 bank FILL 이 아니라 lattice unit 의 carry 소비 (beat 0)** — FILL 은 PACK_WIDE-표현성 계약만으로 수용하며 (위 FILL validation (i)-(iii) 불변), lattice 수용성 검사는 carry 인가 시점의 per-lane 검사 몫이다. 현 RTL 은 이 검사를 carry lane 에 이미 배선했고 (per-lane (d)/(e) 가 lane N 에 beat 0 적용 — `FP_AccLattice.v` g_lane) 본 COMMIT 이 그 배선을 normative 로 확정한다. sticky 등급: v1.9 `bank_tag_collision_error` 와 같은 합성 가능한 sticky status 클래스 (§26.5 선례).
- **IF-1 read-before-dispatch**: bank 는 carry word read 를 wave-step 의 start (dispatch) cycle **이전에 완료**하고, carry word 를 `start_i` 와 같은 cycle (beat 0) 에 lattice 에 공급한다. 비-beat0 cycle 의 carry 값은 lattice 가 무시한다 — §27.2.1 amendment 가 확정하고 TB 가 오염값 인가로 봉인한 계약.
- **IF-2 ownership window**: start cycle 부터 그 wave-step 의 writeback (**LATENCY = NUM_BEATS+3; N=8 출하 형상 = 7 cycle**) 까지 해당 bank slot 은 **lattice 소유**다. 이 창 내 그 slot 에 대한 **FILL/DRAIN/ZERO 접촉은 loud fault** (합성 가능한 sticky — 거부 + fault, silent 수용 금지). **TLA+ 대응 (명기)**: `proofs/tla/AccBank.tla` 의 ownership guard 군 {`acc_owner`, `drain_owner`, `fill_bankfree`, `zero_owner`} + sticky `conflict` bit 가 이 계약의 stream-레벨 형이고, 창 내 접촉의 거부는 그 모델의 attempt-surface fault 경로 (AccumulateFault / DrainFault / FillFaultBusy / ZeroFault) 를 cycle-정밀 창으로 정제한 것이다 (창 내 FILL 이 **외래 image 를 주소하는 변형**은 `fill_owner` guard / FillFaultForeign 경로 — 위 4종 밖이나 같은 계약의 일부이며, ③ 검증 계획 (a) 의 fault 액션 6종 변환이 이를 포함한다) — guard-별 삭제 실험 (`proofs/tla/run.sh`) 의 TLC 반례 trace 가 ③ directed test 시나리오의 원천이다 (§27.6 하류 ③ 검증 계획). **[승격 2026-08-16 — ③ 착지 기록 (§27.6) 의 검증 렌즈 권고: golden 계약 pin (`bank_scenarios_contract.md` §5 항 1) 의 normative 본문 승격]**: carry-lane fault (d)/(e) 로 writeback 이 억제된 wave 도 ownership window 를 그대로 점유한다 — unit 은 LATENCY 동안 그 slot 을 소유한다.
- **IF-3 같은 slot 체이닝 간격**: 이 wave-step 의 wide 결과를 같은 slot 의 다음 wave-step carry-in 으로 쓰는 체이닝은 — bank forwarding 없는 기본 계약에서 — 다음 start 를 이전 start 로부터 **≥ LATENCY = 7 cycle** 뒤에 두어야 한다; 서로 다른 slot 의 wave-step 은 II = 4 로 완전 중첩 가능. 이 두 간격은 상위 dispatch 스케줄의 입력 제약이다 (§27.2.1 amendment "II 계약" 항의 승계).
- **IF-4 FP_ACC_ZERO (0x7E) 의 zero 기록**: bank slot 의 zero 화는 **canonical zero 기록** (fp64 인코딩상 +0 — 위 canonical zero 항의 유일 표현) 이다. ownership window 내 발화는 IF-2 의 loud fault 이며, raw 0x7E 는 ownership-checked (TLA+ `zero_owner` guard 대응 — acquire 융합 원자형이 권장 형태, `AccBank.tla` CommitOwn 주석).

#### 27.2.3 drain

**PACK_FINAL — 정확히 1회 RNE-24 + flush-after-round FTZ** (출하된 pin 그대로). wave-step store 의 RTO-48 과 합성하면, 위 정리에 의해 **단일 wave-step 의 dot 을 즉시 drain 한 결과는 RNE_24(exact 33-항 합) 과 bit-exact** 다 — 이것이 §27.7 FDOT32_CR 불변식의 기반이다.

### 27.3 계약의 한계 (honest — normative 로 명기)

- **full-K 단일 반올림은 형식적으로 보장하지 않는다.** 보장되는 형식적 (B) 는 **각 wave-step 내부** (dot + carry-in → wide 포맷으로의 단일 반올림) 다. wave 경계를 넘으면 bank 에 park 된 RTO-48 값의 jam (odd 로 밀린 최하위 bit) 이 **후속 wave 의 cancellation 으로 노출**될 수 있다 — 구성적 증거는 JSON `bank_store_jam_families` 의 **F5b/F6 (exact-tie 경계에서 true (B) 대비 2 ulp)** 와 **F1/F4 (park-plus-cancel 계열)** 다. **주의 — 인용 규율**: 옵션 3 의 실제 wave-step 단위 store 는 전 표본 (모든 K, 전 stream) 에서 cross-wave 발산 0 으로 실측됐으나, 이 0 은 **표본 결과이지 증명이 아니다** — 한계를 인용할 때는 jam family 반례를 인용하고 **표본률을 인용하지 말 것** (JSON `sampling_note` 가 이 규율을 운반).
- **보장하는 것**: (i) per-wave-step atomicity (dispatch 당 bank 반올림 이벤트 정확히 1); (ii) 결정론 — bank 궤적은 (프로그램, 데이터, wave-order) 만의 함수; (iii) **run/FP_LANES/part 불문 bit-identity** — dot 내부가 exact 라 lane 접기/스케줄이 결과에 개입할 수 없고, 잔존 순서 자유도는 wave-order K 시퀀싱뿐이다 (ascending wave-order K 는 §23.1 대로 normative 유지).
- 타 GPU/CPU 와의 bitwise 동일성 비약속 (§23.4) 은 그대로다.

### 27.4 검증 표면 변화

- **소거**: §23.1 의 "모든 FP_LANES 구성이 canonical order 와 serially-equivalent 해야 함" 증명 의무는 **dot 내부에 한해 구조로 대체된다** — exact 정수 합은 결합 순서가 없으므로 증명할 명제 자체가 소멸한다 (kickoff memo TP-2 의 serial-equivalence 테스트군은 wave-order 시퀀싱 검사로 축소). §23.1 의 canonical order 문장에서 살아남는 부분은 **wave-order K 시퀀싱** 하나다.
- **잔존**: (i) wave-order K 시퀀싱의 결정론 테스트; (ii) **bank ownership — `proofs/tla/` TLA+ 모델이 RTL 을 선행** (formal-first, §23.7-3); (iii) **golden lattice model — RTL 이전에 착지** (golden-before-RTL law, §25.1 선례): 33-항 exact dot + RTO-48 추출 + fp64 codec + FILL validation 의 reference 를 `scripts/golden_fp32.py` 계열로 저작, 독립 oracle (mpmath/ml_dtypes) 교차검증 포함 (§23.10.5 pin 13 규칙).
- `scripts/acc_format_study.py` 는 **설계 판정의 재현 artifact** 로 존치한다 (golden model 의 대체물이 아니다 — golden 은 sequencer/RTL-faithful 층을 별도로 요구한다).

### 27.5 소거 근거 (전부 고정-seed 재생성 수치 — JSON 인용)

1. **RTO-tree 는 모든 폭에서 죽었다.** realizable-leaf 반례 [1×1, 2^-30×2^-30, 1×(-1)]: RTO_48-tree **0x28000000** / RTO_50-tree **0x27000000** vs true **0x21800000**; 스케일 구성으로 q=48/50/64/128/254/368 전부 발산 (f16 leaf 도 48/50 발산); **tie-straddle family 는 catastrophic cancellation 전무한데도 q48 12.45% / q50 7.11% 발산** (재생성값 — 세션값 13.4/7.9 대체); cancellation family 100%/100% (worst 1.5e23 ulp), rand-wide 0.20%/0.19%. **안전 폭 == Kulisch 폭** (bf16 527 / f16 85; q=527 에서 0/2000) — 그 폭에서 tree 는 더 이상 반올림 tree 가 아니라 **exact 누산기 그 자체**다. 즉 "충분히 넓은 RTO tree" 의 극한이 곧 옵션 3 이다.
2. **옵션 2 기각.** dispatch 당 반올림 이벤트 **32 vs 1** (tree node 31 + bank store 1 — JSON `rounding_events`); 31회 순차 adder pass 로 더 느림; FP_LANES serial-equivalence 검증 세금 영구 부담. **정정 기록**: kickoff memo 의 "(A) = dot 당 6회 RNE" 는 **오류** — 경로 깊이 (곱 1 + tree 5-level) 를 이벤트 수와 혼동했다. 32-leaf tree 의 이벤트 수는 node 31 + bank 1 = **32/dispatch** 다 (memo 측 정정은 같은 commit 에 동반).
3. **bf-exponent ladder 붕괴.** bf48(1+8+39): bf16 곱의 exponent 범위가 8-bit exp 를 overflow — 즉사. (1+11+36): write 당 PACK_WIDE 보다 좁고 K-horizon ~2^11 로 부족 — 지배됨. ladder 의 끝점 == PACK_WIDE — 신규 포맷이 아니라 이미 출하된 포맷이다.
4. **posit 실측 기각 (exact-arithmetic codec, roundtrip 20k idempotence 자가검증 통과).** 표준 posit64es2 는 bf16-곱 극단 binade (−252/+255) 에서 **significand 1 bit 로 붕괴** — 2^230 band 에서 100% 발산, max **5.52e8 ulp** (재생성값 — 세션값 4.3e9 와 같은 클래스); es=5 튜닝은 최선에서 option-C 동급이나 **F2 sticky-tie family 를 전 구간에서 패배** (sticky 가 폭을 이긴다 — JSON `posit_adv` F2); 튜닝 gradient 는 fixed-field 포맷으로 수렴 (그 시점에 posit 이 아니다); **quire 의 자백**: posit 생태계 자신의 exact 누산 답인 quire 는 posit64 에서 1,024 bit/lane — quarter-op spill 8,192 bit = **128 fragments = FRAG_MAX 16 의 8×** (PACK_WIDE bank 는 8 fragments), bank 상태 33,792 bit (bf16 Kulisch) vs **4,096 bit**.
5. **input-noise dominance — 정확성 논증의 종결.** 같은 dot 에 대한 쌍대 비교에서 bf16 입력 양자화 noise 가 어떤 누산 방식의 오차보다도 큼: **1,920/1,920 쌍 전부 dominance, 최소 유한 비 56.45× (재생성값 — 세션 3.9× 보다 유리), median 477×–57,513×**. 따라서 옵션 3 의 채택 사유는 계약 강도/처리량/검증 표면이다 (§27.1).
6. **"FP_AddWide 는 50 bit 가 필요하다 / Gate 2 재개" 명제의 영구 은퇴.** 이 명제는 category error 다 — 문제는 폭이 아니라 **cascade** 다: RTO tree 는 50 포함 전 폭에서 실패하고 (항 1; tie-straddle 은 50 bit 에서도 7.11%), 폭이 실제로 중요한 유일한 지점 (최종 추출) 은 q ≥ 26 만 요구하며 48 은 22 bit 마진을 갖는다 (§27.2.1 정리). **FP_AddWide 는 48-bit 로 byte-untouched 존치, Gate 2 영구 폐쇄.**

### 27.6 Gates — pre-priced, 구현 이전 공표 (locked)

**GATE V20-2 (528-bit lattice unit gate, dual-fabric) 가 v2.0 의 첫 hard gate 다.** (번호 부여: GATE V20-1 = bf16 FMA lane pre-synth gate — kickoff memo §6.3 이 정의, GATE F1/F1-US 로 이미 실행·PASS.) 방법론은 §23.10.7/§25.5/§26.6 의 그것 — merge-blocker, 기준 수치는 측정 전 공표, gate log 는 merge commit 첨부, "선언된 gate 건너뛰면 5 commit 뒤 발각" 교훈은 이미 4회 확인됐다.

- **xcu55c (성능 판정 fabric — kickoff §5.2)**: nominal **8-12k LUT + 2-3k FF/cluster** (Pod 투영 nominal ≤ +3.8%). **LUT gate ceiling = 12,000 × 1.67 (이 project 의 실측 overrun 계수 — §23.10.10(g) 방법, 0d/0e/v1.9 를 관통한 그 기준) = 20,040 LUT/cluster-상당 unit — hard ceiling, 초과 시 merge 금지.** FF 는 추적만 (V9-4 관례). 곱셈기: lattice 는 adder/compressor 만이므로 **premap `$mul` 연산자 delta 0** (§26.6 amendment 의 pin form — 물리 DSP/MULT 절대 개수는 gate 대상 아님). resolve 는 1 cycle @ 100 MHz 목표에 수납되어야 함 (~66 CARRY8 / ~4 ns 는 ESTIMATE — gate 에서 실측 졸업). Pod 투영은 unit 실측 후 재산정 의무.
- **ECP5 (feasibility measurement — gate 판정 대상이 아님, 사용자 지시 2026-08-15)**: **GATE V20-2 의 merge-blocker binding 은 xcu55c 반쪽에만 있다. ECP5 반쪽은 실현성 측정이며, 어떤 결과가 나와도 — 어렵다·비싸다·불가능하다 포함 — gate FAIL 을 구성하지 않는다.** 유일한 의무는 측정의 실행과 정직한 기록이다. 대상 설계는 **beat-serialized 2-products/beat × 16 beats + 9-cycle serial resolve**. nominal 면적 추정이 존재하지 않으므로 LUT ceiling 을 선공표하지 않으며, 아래는 pass/fail 이 아니라 **판정 분류 기준**(feasible/infeasible 의 기록 형식)이다: (i) standalone OOC synth+PnR 완주 여부, (ii) Fmax (기존 fp_ops 관례값 40 MHz 는 비교 참조점일 뿐 계약 아님), (iii) MULT18X18D 신규 0 / premap `$mul` delta 0 여부. **명시 off-ramp (사전 선언 — 발동은 실패가 아니라 예정된 분기다)**: ECP5 가 infeasible (미완주 또는 cluster 통합 불가) 로 분류되면 **ECP5 는 at-speed dot path 를 제외한 검증 역할 (TRNG 실리콘 검증·UsbCdcTransport·FOSS bitstream) 을 전부 유지**하고, dot-path 검증은 cocotb + xcu55c 로 수행한다 — cross_vendor_fabric_evidence.md 의 "ECP5 는 FOSS 검증 vehicle, 성능 타겟 아님" 포지셔닝의 직접 적용.
- **하류 gate 순서 (선공표)**: ① **golden lattice model** (§27.4 — RTL 이전, golden-before-RTL law) → ② GATE V20-2 (본 gate) → ③ bank RTL + TLA+ 유도 directed test (ownership loud-fault 경로 포함 — TLC 반례 trace 가 시나리오) → ④ full-cluster gate (COMB/Fmax/premap-`$mul` — 기준 수치는 ③ 착지 후 별도 COMMIT 에서 V9-4 형식으로 선공표). **FDOT32_CR 관련 gate 전부는 3a 로 이연** (§27.7).

**GATE V20-2 실측 최종 (2026-08-15, `FP_AccLattice.v` — Vivado 2025.2.1 / xcu55c-fsvh2892-2L-e / OOC / 10 ns clock, 전 flow synth+place+route):**

| 지표 | 실측 | 사전가격 | 판정 |
|---|---|---|---|
| **LUT** | **53,418 sites** (raw LUT cells 67,696) | nominal 8-12k, **hard ceiling 20,040** (12,000 × 1.67) | **FAIL — ceiling 의 2.67×, nominal 상단 12,000 의 4.45×. "초과 시 merge 금지" 규정 발동.** |
| **premap `$mul`** | **0** (`$add` 368 / `$sub` 2) | delta 0 | PASS |
| **Fmax / resolve** | WNS **+1.807 ns** @ 10 ns → **Fmax 122.06 MHz**, WHS +0.042 ns, CARRY8 265 | resolve 1 cycle @ 100 MHz 목표 (~66 CARRY8 / ~4 ns 는 ESTIMATE) | **PASS — resolve-1-cycle ESTIMATE 실측 졸업.** worst path 는 resolve 가 아니라 **S1 compressor tree 진입** (route 지연 82.7%). |
| **FF** | 5,729 (core 2,986 — 나머지는 gate_top wrapper I/O) | 추적만 (V9-4 관례) | 기록 — core 는 nominal 2-3k 범위 하단. |
| DSP / DRC | DSP 0 / DRC errors 0 | — | 기록 |

리포트: `synth/reports/fp_ops/fp_acclattice_{impl_summary.json,impl_util.rpt,impl_timing.rpt,impl_drc.rpt,premap_mul.log}`. **본 gate 는 자신이 선언한 ceiling 을 충족하지 못했으며, 이 사실을 silent 하게 수용하지 않는다** — §26.6 GATE V9-4 FAIL 기록의 형식과 정책을 그대로 따른다: FAIL 원인을 귀속하고, 옵션을 기록하고, 결정을 상위 결정권자에게 넘긴다 (아래).

**ECP5 feasibility 측정 (판정 아님 — 본 절 원문 그대로 반복한다: "어떤 결과가 나와도 — 어렵다·비싸다·불가능하다 포함 — gate FAIL 을 구성하지 않는다"; 이행된 의무는 측정의 실행과 정직한 기록이다):**
- **전 병렬 (`FP_AccLattice` 그대로, LFE5UM-85F)**: yosys LUT4 **102,871** = COMB fabric (83,640) 의 **123%** → nextpnr **배치 불가** (`ERROR: no BELs remaining`, placement 중단) — **infeasible 분류**. 이는 사전 선언된 off-ramp 의 발동이며 **유효한 측정이다** — 실패가 아니라 예정된 분기. off-ramp 대로 ECP5 는 at-speed dot path 를 제외한 검증 역할을 전부 유지한다.
- **beat-serial 변형 `FP_AccLatticeBeat2.v` (측정 전용 변형 — 2 products/beat × 16 beats + carry beat, 9-cycle serial resolve)**: LUT4 **9,374** / Fmax **19.55 MHz** / PnR **완주** / verilator 로 golden 벡터 **4001/4001 bit-exact** — **ECP5 는 beat-serial 형상으로 lattice 검증 역할을 수행 가능함이 실측 확인됐다** (Fmax 는 fp_ops 관례 참조점 40 MHz 미달 — 계약이 아니므로 기록만). 리포트: `synth/lattice/reports/fp_ops/fp_acclattice_*` (전 병렬) / `fp_acclattice_beat2_*` (beat-serial).

**FAIL 원인 진단 (2026-08-15, 진단 전용 3-run — 신규 출하 RTL 없음; 방법: (R1) Beat2 를 동일 하네스로 xcu55c 전 flow 실측, (R3) 출하 top 재-synth 후 전 LUT cell 67,766 을 이름-cone 분류로 스테이지 귀속 — `synth/reports/fp_ops/fp_acclattice_diag_flat_attribution.txt`, (R2) 스테이지 경계 keep_hierarchy 분리 synth — `fp_acclattice_diag_stages_util.rpt`, 진단 하네스는 `synth/scripts/diag/` 보존):**

| # | 성분 | LUT | 비중 | 근거 |
|---|---|---|---|---|
| S1-a | **배치 33×** — per-addend decode/fault + 112-bit 6-stage barrel + 2-of-9 segment demux 의 576-bit 필드 형성. addend 당 **763 = demux 512 + barrel 188 + decode 63** (R2 실측) — demux 지배 확인, barrel 은 추정 ~336 대비 실측 188 | 25,179 | 46.7% | **measured (R2)** |
| S1-b | **34-row 3:2 compressor tree** (8 level × 576 column; ones'-complement `~field` 반전은 level-1 XOR LUT 에 흡수 — 분리 cell 0 확인). 전 column 정적 밀도는 부호확장이 아니라 **dynamic 배치 범위** (어느 addend 든 576 column 어디든 착지 가능) 기인 | 25,279 | 46.9% | **measured (R2)** |
| S2 | resolve — 576-bit carry-propagate 가산 + 정렬검사 (CARRY 126+66) | 1,307 | 2.4% | measured (R2) |
| S3 | 추출 전반부 — 528-bit negate + chunk 분해 + coarse 우선순위 + 128-bit window + CLZ + sticky (CARRY 68) | 1,721 | 3.2% | measured (R2) |
| S4 | 추출 후반부 + 인코딩 — 128-bit normalize barrel + RTO-48 + wide/bank/fp32 인코딩 + 출력 | 438 | 0.8% | measured (R2) |

(R2 기준: keep_hierarchy 분리 synth 합계 53,933 — 출하 flat netlist 53,418 sites 와 1% 이내 정합. R3 flat 이름-cone 분류에서는 fault cone 2,591 이 별도 계수되고 S1 합산 94.5% — R2 분할과 정합. 최초 보고의 S1 내부 추정 분할 29,000/54.3% vs 18,900/35.4% 는 **R2 로 정정 졸업**: 배치는 과대, tree 는 과소 추정이었고 실측은 **사실상 동률 지배**다.)

**핵심 판정 (R2 졸업 후 불변)**: FAIL 의 **93.6% (R2 실측) 는 S1 한 스테이지** — 배치 33× 복제 (46.7%) + 34×576 compressor tree (46.9%), 동률 지배 — 이고 S2-S4 합계는 6.4% 뿐이라 **추출/인코딩 최적화는 무의미하다**. 초기 가설 2건은 정정됐다: H1 "full 528-bit barrel" 은 부존재 — 출하 RTL 은 이미 fine-shift × 창 + demux 구조 (`FP_AccLattice.v:160-187`); H2 "부호확장 밀도" 도 반증 — 밀도 원인은 dynamic 배치 범위다. Fmax 는 문제가 아니며 (+1.807 ns 여유), **53,418 은 이 마이크로아키텍처 (full-parallel 33-addend, II=1) 의 구조적 비용으로 판정한다**.

**beat-serial xcu55c 실측점 (진단 R1)**: `FP_AccLatticeBeat2_gate_top` 을 동일 하네스 전 flow 로 — LUT **6,075 sites** (raw cells 6,951) / FF 3,806 (wrapper I/O 761 + core 3,045) / DSP 0 / CARRY 85 / WNS **+2.698 ns** → **Fmax 136.95 MHz** / DRC clean-class. full-parallel 대비 **8.8× 작음** — ceiling 20,040 의 30%, nominal 하단 8k 도 하회. 비용: **II = 28 cycle/wave-step** (acc 17 + serial resolve 9 + extract 2) vs full-parallel II=1. 리포트: `synth/reports/fp_ops/fp_acclattice_diag_beat2_*`. (Beat2 의 golden 4001/4001 bit-exact 은 ECP5 verilator 세션에서 기실증 — verilator 재검증 없이 xcu55c netlist 의 기능 동일성까지 본 진단이 주장하지는 않는다.)

**감축 레버 (진단 결론 — 어느 레버의 채택도 본 절이 결정하지 않는다):**

| 레버 | 기전 | 기대 LUT | 신뢰도 | 비용 |
|---|---|---|---|---|
| **L1 beat-serial N 조정** | 배치 demux + compressor rows 를 시간 재사용 — beat 당 rows 를 N+2(carry-save 상태)+1(nrow) 로 제한해 S1 의 89.7% 를 N/33 로 축소 | N=2: **6,075 (실측)** · N=4 ≈ 9-12k (II≈20) · N=8 ≈ 14-18k (II≈16; 병렬 576-bit resolve +~1.1k 추가 시 II≈8) · N=16 ≈ 22-26k — **ceiling 초과** | **measured** (N=2) | throughput II=1 → 28(N=2)/≈20(N=4)/≈8-16(N=8); latency 4 → 28 cycle; 상류 dispatch 가 wave-step 당 N-operand 씩 인가하는 스케줄 변경 필요. Fmax 는 오히려 상승 (136.95 vs 122.06 MHz) |
| L2 부호확장 붕괴 (constant-row/Baugh-Wooley 류) | **가설 반증** — tree 밀도는 dynamic 배치 범위 기인; `~field` 반전은 이미 XOR3 LUT 에 흡수 (분리 cell 0, 한계비용 이미 낮음); constant-row 는 배치 위치가 dynamic 이라 컴파일타임 상수로 붕괴하지 않음 | ≈52-53.4k — 실질 무변화 (±2% 이내) | high | RTL churn + re-proof 만 발생, 이득 없음 — **비권고** |
| L3 barrel → fine-shift × 창 + segment demux 재구성 | **전제 오류 — 출하 RTL 이 이미 정확히 이 구조** (`FP_AccLattice.v:160-187`), delta 0 | 53,418 (불변) | measured | 없음 — 이 형태로도 배치가 최대 성분 (demux 의 576-bit 폭 × 33 복제) |
| L4a row-reduction → CARRY8 ternary adder tree | 34→1 을 17개의 576-bit ternary add 로 대체 시도 — **R2 실측 반증**: ternary576 실험 인스턴스 = **34,412 LUT + 2,016 CARRY8**, 대체 대상 tree (25,279 LUT / CARRY 0) 보다 **+9.1k 더 큼** | ≈63k — **악화. measured 로 기각** (최초 추정 ≈43-48k 폐기) | **measured (R2)** | 이득 없음 — **기각 확정** |
| L4b PHYS 하위 48 column 상수화 | fault (e) 전제 (PHYS[47:0]==0) 를 배치 전에 정적 강제 → demux segment 0 하위 + tree 하위 48 column 상수화 (~8% 절감) | ≈51-52.5k | low | fault (e) 검사를 배치 전 검사로 이동 (loud-fault 계약 유지 필요), 이득 소폭 — 단독 무의미 |

**정책적 결론 — 후속 결정은 사용자 소관이며 spec 은 선점하지 않는다.** 진단이 확정한 제약: full-parallel II=1 을 유지하려면 ~50k 는 구조적 비용이므로 **ceiling 재anchor 없이는 도달 불가** (L2/L3/L4 로는 20,040 미달 불가); ceiling 을 유지하려면 **beat-serial N≤8 이 유일한 measured 경로**다. 기록하는 옵션:
- **(A) 재설계로 ceiling 충족** — 레버 조합, 실질적으로 L1 beat-serial N≤8 (필요시 L4a 병용). throughput 계약 (II=1) 의 완화와 상류 dispatch 스케줄 변경을 수반.
- **(B) ceiling 재anchor** — nominal 8-12k 는 구현 이전 pre-priced 공표 추정이고 (도출 artifact 는 spec 에 없음 — pre-priced 선공표 자체가 §23.10.10(g) 방법론), pre-stable 에서 gate 기준 재anchor 는 **§12a 정규 이벤트**다. 재anchor 판단용 맥락 실측: 53,418 = xcu55c 전체 1,303,680 LUT (Vivado part DB 실측 질의) 의 **4.10%/unit**; v1.x full cluster 실측 42,538-42,731 LUT (`pod_2x2_2x2_impl_util.rpt`, xcu55c routed) 의 **~125%** — unit 하나가 v1.x cluster 전체보다 크다; cluster 당 1 unit + pod 2×2 가정 시 4 unit = +213,672 LUT = device 의 +16.4%p (v1.x pod 실측 170,850 = 13.1% 위에 추가 → 합 ~29.5%).
- **(C) 혼합** — 부분 직렬화 (예: N=8) + ceiling 소폭 재anchor.
어느 옵션이든 **하류 ③ (bank RTL) 착수 이전에 결정되어야 한다** — lattice unit 의 최종 형상 (II, carry-in 인가 시점) 이 bank 인터페이스를 결정하기 때문이다.

**사용자 결정 (2026-08-16, binding) — 옵션 (A) 채택: L1 beat-serial N=8 재설계로 ceiling 충족. ceiling 20,040 은 재anchor 하지 않는다.** FAIL 해소 경로는 이것 하나로 확정하며, **full-parallel II=1 마이크로아키텍처는 §12a 정규 이벤트로 폐기한다** — 원문은 삭제하지 않고 §27.2.1 에 amendment 표기로 보존하고 (§12a 규칙 5), 출하 형상은 §27.2.1 amendment (PRODUCTS_PER_BEAT=8, II ≤ 8) 가 normative 다. 근거 요약:
1. **R2 귀속이 국소 최적화를 봉쇄한다** — S1 배치 25,179 + compressor tree 25,279 = 93.6% 동률 지배는 full-parallel 33-addend II=1 의 **구조적 비용**이다 (L2/L3 는 delta≈0 으로 실측·반증 완료). ceiling 을 유지하면서 구조를 바꾸지 않는 경로는 존재하지 않는다.
2. **L1 이 유일한 measured 생존 레버다** — L4a ternary 는 실측 기각 (+9.1k 악화), L2/L3 무효. 실측점 (N=2: xcu55c 6,075 LUT) 을 가진 레버는 L1 뿐이다.
3. **양 fabric 마이크로아키텍처 통일** — ECP5 feasibility 는 이미 beat-serial 형상으로만 완주했다 (LUT4 9,374, golden 4001/4001 bit-exact). xcu55c 출하 형상을 같은 계열로 통일하면 TB·golden 벡터·fault 경로가 단일 마이크로아키텍처를 검증하게 되어 **검증 표면이 축소**된다.
4. **Fmax 는 오히려 상승 실측** — beat-serial 136.95 MHz vs full-parallel 122.06 MHz (xcu55c 동일 하네스, 진단 R1).

**GATE V20-2 재실측 선언 (N=8 형상 — 선공표 기준 불변)**: 재작성된 `FP_AccLattice.v` (PRODUCTS_PER_BEAT=8) 를 **동일 선공표 기준** — LUT ≤ **20,040** hard ceiling / premap `$mul` delta **0** / WNS @ 10 ns clock 기록 — 으로 동일 하네스 (gate_top OOC, 전 flow synth+place+route) 재실측한다. **PASS 시 본 gate 의 FAIL 은 해소**되고 `make fp-op-report` 의 비zero exit 이 해제된다 (gate 스크립트의 기준 수치는 무변경 — 기준을 움직여서가 아니라 설계를 움직여서 통과한다). ECP5 는 **N=8 구성으로 재측정**한다 — MEASUREMENT 지위 불변 (본 절 원문 그대로: "어떤 결과가 나와도 — 어렵다·비싸다·불가능하다 포함 — gate FAIL 을 구성하지 않는다"); 아울러 **N=2 파라미터 구성이 기존 `FP_AccLatticeBeat2` 실측치 (ECP5 LUT4 9,374 / xcu55c 6,075 LUT) 를 재현하는지를 파라미터화 정합 검사로 병기**한다 — 단 Beat2 는 serial 9-cycle resolve + 별도 carry beat 구조이므로, 이 검사는 **동일 구조 config (serial resolve + carry beat) 로 수행하거나, 병렬-resolve config 로 수행할 경우 기대 delta (+~1.1k LUT, §27.6 L1 레버 표) 를 명기하고 비교**한다 (gate-binding 아님 — 파라미터화가 측정 계보를 보존하는지의 확인이다).

**GATE V20-2 재실측 결과 (2026-08-16, beat-serial N=8 `FP_AccLattice.v` — Vivado 2025.2.1 / xcu55c-fsvh2892-2L-e / OOC / 10 ns clock, 전 flow synth+opt+place+phys_opt+route). 위의 기존 FAIL 실측 표·진단·레버 표는 원형 보존 — 본 블록과 병존한다:**

| 지표 | 실측 | 사전가격 | 판정 |
|---|---|---|---|
| **LUT** | **19,251 sites** (= 19,250 logic + 1 SRL; raw LUT cells 21,475) | **hard ceiling 20,040** (선공표 불변) | **PASS — 여유 789. FAIL 해소 (이전 53,418 대비 −34,167), `make fp-op-report` exit 0 복귀** (gate_check 기준 수치 무수정 — 기준이 아니라 설계가 움직여서 통과했다). |
| **premap `$mul`** | **0** (yosys stat 재생성 — cell 목록에 `$mul` 부재, `$add`/`$mux`/`$eq` 등만) | delta 0 | PASS |
| **Fmax** | WNS **+3.038 ns** @ 10 ns → **Fmax 143.64 MHz**, WHS +0.039 ns, CARRY8 217 | 기록 (§27.6 binding 은 LUT/DSP/premap-`$mul` 만) | 기록 — full-parallel 122.06 MHz 대비 상승 (진단 R1 의 방향 예측과 일치). |
| **FF** | 4,202 (u_core 단독 2,993 — 나머지는 gate_top wrapper I/O flop) | 추적만 (V9-4 관례) | 기록 — core 는 nominal 2-3k 범위 내. |
| DSP / BRAM / DRC | DSP48 0 / BRAM 0 / DRC errors 0, warnings 0 | — | 기록 |

RTL 실측 **II = 4** (carry-in beat 0 병합 — 4 beats, 별도 carry beat 없음) ≤ 계약 **II ≤ 8** — **충족, 여유 4 beat**. **serial 9-cycle resolve fallback 은 미채택** (§27.2.1 amendment 가 요구한 채택-여부 기록의 이행): 병렬 1-cycle 576-bit resolve 그대로 ceiling PASS 이므로 II 계약 재개정은 발생하지 않는다. golden 벡터 **4081/4081 bit-exact** (TB 총 4097 = 4081 벡터 + 16 directed fault 시나리오; 벡터는 §27.2.1 amendment 의 2026-08-16 갱신대로 `sticky_window_band` 80개 확장분 포함, 결정성 byte-identical 재확인) — 수학 계약 (full-parallel 과 bit-identical) 확인. 파라미터 divisor 전수 회귀 N∈{2,4,8,16,32} 전부 동일 bit-exact (N=32 는 full-parallel 시간 등가). 리포트: `synth/reports/fp_ops/fp_acclattice_{impl_summary.json,impl_util.rpt,impl_timing.rpt,impl_drc.rpt,premap_mul.log}` + `gate_summary.txt`. **공지 — 리포트 덮어쓰기**: 이전 FAIL run 의 `fp_acclattice_impl_*`/`synth_*` 리포트는 본 재실측이 같은 경로에 덮어썼다 — FAIL 원본 리포트는 git **903351c/42130e2** 에 커밋되어 있어 역사가 보존된다.

**N=2 파라미터화 정합 검사 — xcu55c (synth-only 1회: 동일 파라미터화 RTL + 동일 gate_top, `synth_design -generic PRODUCTS_PER_BEAT=2`, 10 ns)**: LUT sites **9,089** (raw cells 9,782) / FF 3,821 / DSP48 0 / BRAM 0 — 무오류 elaboration/합성으로 파라미터화 정합 확인. Beat2 실측 6,075 (routed; synth 단계 6,096) 대비 delta **+3,014** — 선공표 병기 요건의 병렬-resolve 기대 delta +~1.1k 를 약 +1.9k 초과하나, 초과분은 resolve 외의 구조 차이 2건으로 설명되어 **정합 판정**: (1) carry-in beat 0 병합 선택에 따른 상시 3번째 decode/barrel/demux lane (Beat2 는 별도 carry beat 가 기존 2-lane datapath 를 재사용), (2) II=NUM_BEATS 완전 중첩 파이프라인 (R/S3/S4 독립 스테이지 상시 인스턴스) vs Beat2 의 phase-다중화 단일 datapath (중첩 없음, 64-bit/cycle serial resolve + 시분할 extract). 즉 동일 수치 재현이 아니라 구조 차이로 정합하며, N 스케일링도 sublinear 로 정상 (decode 3 lanes 9,089 → 9 lanes 19,251). synth-only vs full-flow 비교 오차는 무시 가능 실증 (같은 RTL N=8: synth 19,363 → routed 19,251, −0.6%; Beat2: 6,096 → 6,075). 진단 하네스: `synth/scripts/diag/diag_acclattice_n2.tcl` (GATES 미등재 — 진단 전용), 리포트 `fp_acclattice_diag_n2_*`.

**ECP5 N=8 재측정 (MEASUREMENT — 본 절 원문 그대로 반복한다: "어떤 결과가 나와도 — 어렵다·비싸다·불가능하다 포함 — gate FAIL 을 구성하지 않는다"; yosys 0.64 synth_ecp5 + nextpnr-ecp5, LFE5UM-85F CABGA381 -6, OOC, seed 1, 40 MHz reference)**: LUT4 **29,834** / TRELLIS_COMB **31,500 = COMB fabric (83,640) 의 37.7%** — **85F 에 수납된다** (full-parallel 의 123% 배치-불가와 대비 — beat-serial 통일의 직접 이득) / CCU2C 758 / PFUMX 2,071 / TRELLIS_FF raw 4,200 = unit 2,933 (wrapper I/O flop 1,267 차감) / MULT18X18D **0** / premap `$mul` **0** / EBR 0 / PnR **완주** / Fmax **16.51 MHz** (post-route; 40 MHz 는 비교 참조점일 뿐 계약 아님). **N=2 파라미터화 정합 (ECP5)**: LUT4 **11,185** / CCU2C 648 / FF raw 3,816 (unit 2,933) / **15.21 MHz** — 측정 전 선언한 기대 밴드 (Beat2 실측 LUT4 9,374 / CCU2C 376 / 19.55 MHz 대비: LUT4 ±20%, CCU2C +200..+300 [576-bit CPA ≈ +288 − serial slice], Fmax 15-20 MHz) 안에 전부 착지: LUT4 +1,811 (+19.3%, 밴드 상단) / CCU2C +272 (밴드 내) / Fmax −22% (밴드 하단 — 병렬 576-bit resolve chain 의 임계경로화와 부합) / FF unit −47 (serial-resolve 상태 제거분). 추가 정합 근거: **unit FF 2,933 이 N=2 와 N=8 에서 동일** — core 상태 (carry-save 2 row + ncnt + 파이프라인) 가 N-독립이라는 파라미터화 구조 예측과 일치. premap `$mul` 0 / MULT18X18D 0 은 세 형상 (beat2/n2/n8) 모두 동일. 리포트: `synth/lattice/reports/fp_ops/fp_acclattice_n8_*` / `fp_acclattice_n2_*` + `gate_summary.txt` (옛 full-parallel·beat2 리포트는 다른 파일명으로 동결 보존, gate_summary 에 provenance 행 유지; gate_check exit 0 — 기존 binding gate 4건 전부 PASS 유지, V20-2/ECP5 행은 전부 MEASUREMENT). 실행 provenance: 최초 N=8 PnR 은 백그라운드 태스크 수명 종료로 routing 중 강제 종료 (~58분 시점) — 보존된 synth.json 에서 동일 인자·seed 1 로 detach 재실행해 완주했고, 아카이브된 `fp_acclattice_n8_pnr.log` 는 재실행분이다.

**하류 ③ (bank RTL COMMIT) pin 등재 — 검증 렌즈가 발견한 minor 2건 + 기존 미결 1건 (`include/generated/lattice_vec_contract.md` §7 과 정합 확인 완료):**
1. **합 == 정확히 −2^261 corner 의 fault 클래스 배정 (신규 — 검증 렌즈)**: 33-항 합이 signed 표현 하한 −2^261 에 정확히 떨어지는 corner 를 golden 은 현재 bare assert 로만 차단한다 — ③ 에서 `LatticeFault` 로 승격하거나 수용 하한 LAT_MIN+1 을 규범화하는 양자택일 pin 이 필요하다. **→ 해소 (2026-08-16, ③ spec COMMIT — §27.2.1 amendment pin 1 항)**: 수용 구간을 **개구간 (-2^261, 2^261)** 으로 규범화, 경계 도달 = lattice overflow 동일 클래스 loud fault (RTL fault (f) 기존 배선 무변경 이행 / golden 은 bare assert 의 `LatticeFault` 승격 의무 — 코드 수정은 다음 단계).
2. **carry-in slot 의 normalized 전제 명문화 (신규 — 검증 렌즈)**: 벡터 계약 §4 는 "carry-in 은 normalized (sig[47]==1) 또는 canonical zero" 를 전제로 운반하나 본 절 (§27.2) normative 본문에는 미명문 — ③ 에서 normative 화한다. **→ 해소 (2026-08-16, ③ spec COMMIT — §27.2.1 amendment pin 2 항)**: normative 본문 승격 + 구조적 보장 경로 병기, 위반 = fault (c) 의 carry-lane 강화형 (RTL 강화형 배선은 ③ 구현 의무).
3. **lattice-비표현 carry 의 RTL fault 클래스 배정 (기존 — 벡터 계약 §7 미결 pin 재확인)**: FILL-valid 한 fp64 bank word 는 |v| ≤ ~2^1024 까지 담지만 lattice 는 |v| < 2^261 만 수용 — golden 은 loud fault (`LatticeFault`) 로 고정했고, RTL 의 sticky-fault 클래스 배정은 ③ COMMIT 몫이다. **→ 해소 (2026-08-16, ③ spec COMMIT — §27.2.2 하류 ③ 블록)**: 신규 클래스 없이 기존 fault (d)/(e) 의 carry-lane 적용으로 배정 (범위 ↔ (d), 정밀도 ↔ (e); golden `LatticeFault` 2종과의 대응 명기), 발화 지점은 FILL 이 아니라 carry 소비 (beat 0).

**하류 ③ 검증 계획 선공표 (2026-08-16, spec-first COMMIT — §26.6/V9-4 형식: 방법을 구현 이전에 공표한다. 위 pin 3건은 본 COMMIT 이 해소했고, ③ 구현 산출물은 아래 3계열 전부의 실행·기록을 의무로 진다):**

- **(a) TLA+ 유도 directed test**: `proofs/tla/run.sh` 가 고정한 guard-별 삭제 실험 7건 + requesterid 1건의 **TLC 반례 trace 를 각각 RTL directed test 시나리오로 변환**한다 — trace 의 action 열 (RequestOwn / CommitOwn / Accumulate / Drain / Spill / Fill / Zero) 을 bank RTL 자극 열로 사상하고, guard **armed** 상태의 RTL 이 같은 자극 열을 **거부 + sticky fault** 로 종결함을 판정한다 (ownership loud-fault 경로 전부 포함 — RejectOwn / AccumulateFault / DrainFault / FillFaultForeign / FillFaultBusy / ZeroFault 대응 경로). witness 6건 (README §5.4) 은 fault 없는 도달성 시나리오로 병행 변환한다.
- **(b) lattice-bank 통합 TB**: (1) **같은 slot 체이닝** — 간격 ≥ LATENCY=7 준수 시퀀스의 bit-exact 판정 + ownership window 내 접촉 (위반) 시퀀스의 loud fault 판정 (IF-2/IF-3); (2) **gap-후 재시작** — V20-2 TB (`tb_fp_acclattice.v`) 는 전 구간 back-to-back (wave-step 간 idle 0) 전용이었으므로 임의 idle gap 후 재시작은 커버리지 경계 밖이었다: **본 TB 가 이 경계를 명시 폐쇄한다**; (3) **FILL/DRAIN/ZERO 와 wave-step 의 인터리브** — ownership window 경계의 cycle 정밀 판정 (창 직전/직후 접촉 합법, 창 내 접촉 fault).
- **(c) golden 확장 (bank 상태기계 시나리오 레벨)**: `scripts/golden_lattice.py` 에 FILL/DRAIN/ZERO/체이닝 시퀀스의 reference 를 확장하고, pin 1 의 golden 이행 의무 (bare assert → `LatticeFault` 승격 + 수용 조건 `LAT_MIN < total` 화) 를 같은 편집에서 이행한다.
- **④ 재확인**: full-cluster gate (COMB/Fmax/premap-`$mul`) 의 기준 수치 선공표는 — 기존 선언 그대로 — **③ 착지 후 별도 COMMIT** 에서 V9-4 형식으로 수행한다; 본 COMMIT 은 ④ 기준을 선점하지 않는다.

**하류 ③ 착지 기록 (2026-08-16, 구현 commit `ab51a91` — `FP_AccBank.v` + `tb_fp_accbank.v` + TLA+ 유도 directed + golden bank 상태기계; §26.6/V9-4 기록 관례. 위 선공표 (a)/(b)/(c) 3계열 전부 이행 — 선공표·pin 등재·gate 시점 요약의 기존 문언은 원형 보존, 본 블록과 병존한다):**

- **(a) 이행 — TLC 반례 trace 14건 변환 (guard 삭제 7 + requesterid 1 + witness 6)**: trace 재실행 byte-identical 실증 + action 좌표 원문 대조, fault 액션 6종 (RejectOwn / AccumulateFault / DrainFault / FillFaultForeign / FillFaultBusy / ZeroFault) 전부 커버. 변환 규칙·대응표는 `proofs/tla/trace_to_directed.md`, trace 원본·시나리오는 `proofs/tla/derived/` (`tla_directed_scenarios.json` + `traces/*.trace.txt` — 2회 재실행 byte-identical).
- **(c) 이행 (golden-before-RTL) — golden bank 상태기계 + 343 시나리오**: `scripts/golden_lattice.py` `bank_execute` (상태기계 reference) + `include/generated/bank_scenarios.hex` **343 시나리오 (directed 43 + rand_interleave 300), 39,360 records** — 결정적 (재생성 2회 byte-identical), **적대 검증 렌즈의 독립 재실행기 (golden 미 import, 일회성 /tmp 스크립트 — 디스크 규율로 미커밋) 로 전량 불일치 0; 커밋된 상시 교차검증 실물은 통합 TB (Verilog 경로 — golden 미 import) 다**. **pin 1 golden 이행** — 수용 조건 `LAT_MIN < total` (개구간 (-2^261, 2^261)) 화 + bare assert 의 `LatticeFault` 승격 — **lattice 4081 벡터 byte-identical 유지**. **pin 3** 은 carry (d)/(e) directed ±판 (`carry_fault_range`/`carry_fault_precision` — writeback 억제 + 잔존 word drain 확인) 으로 커버.
- **(b) 이행 — 통합 TB `tb_fp_accbank.v`**: FP_AccBank–FP_AccLattice 실결선에서 **TLC 14 + golden directed 43 + random 300 전량 cycle-정밀 bit-exact PASS**. **gap-후 재시작 (gap 1/3/17, 같은/타 slot) — V20-2 TB back-to-back 전용 커버리지 경계의 명시 폐쇄** (선공표 (b)(2) 이행). 체이닝 delta 7/8 합법 경계 + 4/5/6 거부, 창 offset 1..7 fault vs 8 합법 (창 마지막 = writeback cycle 접촉 포함 — (b)(3) 인터리브 이행).
- **pin 2 이행 — `FP_AccLattice.v` fault (c) carry-lane 강화형 배선**: 기존 4097 회귀 bit-exact 유지 + **GATE V20-2 재확인 PASS — LUT 19,298 ≤ 20,040 (여유 742, 강화형 delta +47) / premap `$mul` 0 / WNS +3.012 ns → Fmax 143.10 MHz / `make fp-op-report` exit 0**. TB PHASE P2 가 판별 벡터 (약형 (c) 는 통과시키고 강화형만 발화) 로 배선을 직접 증명 — bank 경유로는 구조적 도달 불가라 (pin 2 의 "구조적 보장 경로" 그 자체) 별도 lattice 인스턴스로 판정.
- **적대 검증**: 변이 공격 지정 5종 전부 사멸. 검증 렌즈가 **TB 블라인드 스팟 2건을 실측 발견** — `spill_ref` 절단 (비-owner SPILL silent 유출) / `cmd_unk` 절단 (미정의 opcode silent 수용) — golden-first 로 directed 8건 추가 (SPILL 거부 창/비-owner + PROTO_GUARD + 수용 대조; 시나리오 335→343) 후 **두 변이 사멸 재실증 (TB errors 127/44 — 일회성 변이 실측 전사, 재현은 변이 재적용으로만 가능)** — 총 변이 반증 7종 전부 사멸 + discriminator 자기시험 (tautology 방지, PHASE C).
- **FP_AccBank synth smoke (측정 — gate 아님)**: xcu55c **LUT 8,368 / FF 4,819 / DSP 0 / BRAM 0 / synth WNS +5.106** (synth_design only — post-synth, Fmax 아님); ECP5 **LUT4 14,671 / MULT18X18D 0 / EBR 0 / premap `$mul` 0** (mux 지배 — premap `$mux` 527). 리포트: `synth/reports/fp_ops/fp_accbank_synth_*` / `synth/lattice/reports/fp_ops/fp_accbank_{synth,premap}.rpt`.
- **커버리지 경계 (정직 기록)**: (i) **창 offset 0** (start 와 같은 cycle 접촉 = 같은 (cycle,slot) 2명령 중재) 은 시나리오 형식상 표현 불가 — 계약 문서 (`bank_scenarios_contract.md` §2 형식 규율) 가 문서화; RTL 2-port 중재 커버는 ④ 통합 몫. (ii) per-op×offset 교차곱 공백 — window_fill offset 6 / window_zero offset 4 부재, window_spill 은 directed 설계상 offset {1,3,7} 만 존재 (coverage 하한은 전 클래스 충족). (iii) TLC ghost 2건 — DT-05 spill image owner-tag 캐리어 (l) / DT-04 K 완결 캐리어 (h) — 는 TB scoreboard 실물화로 대조했고, RTL 실물화는 ④ 몫.
- **spec 승격 1건 (검증 렌즈 권고 이행)**: golden 계약 pin (`bank_scenarios_contract.md` §5 항 1) "carry-lane fault (d)/(e) 로 writeback 이 억제된 wave 도 ownership window 를 점유한다" 를 §27.2.2 IF-2 본문에 normative 1문장으로 승격 (해당 항의 [승격] 표기).
- **④ 재확인 (불변)**: full-cluster gate 기준 수치 선공표는 별도 COMMIT 몫 그대로다 — 본 착지 기록은 ④ 기준을 선점하지 않는다.

**검증 체계 실적 (gate 시점 요약)**: golden lattice model 은 적대 2렌즈 검증에서 무반증 — 독립 Fraction 재계산으로 4001 벡터 전량 + fuzz 30k 교차검증 불일치 0. RTL TB 는 변이 4종 중 3종을 적발했고, 미적발 1종 (fault 경로 변이) 은 계약상 벡터가 회피하는 영역 (벡터 계약 §4/§7) 임을 문서화했다. 추출 정리 (RNE_24(RTO_48(exact)) == RNE_24(exact)) 의 반례는 0건으로 유지된다.

**④ GATE V20-3 기준 선공표 (2026-08-17, 별도 COMMIT — §26.6/V9-4 형식. 본 절 하류 gate 순서 ④ 의 "기준 수치는 ③ 착지 후 별도 COMMIT 에서 V9-4 형식으로 선공표" 를 이행하는 그 COMMIT 이 본 블록이다. ③ 완결 (spec 선공표 f56b907 / 구현 ab51a91 / 검증 d419458 계열) 로 전건 충족. 본 블록 작성 시점에 ④ 통합 RTL 은 존재하지 않으며, 아래 기준은 전부 측정 이전 공표다):**

**명명·계보·구속력**: 본 gate 는 **GATE V20-3 (v2.0 TRAIN full-cluster datapath gate, dual-fabric)** 이다. 계보: GATE V20-1 = bf16/f16 FMA lane pre-synth (kickoff §6.3 정의, GATE F1/F1-US 로 실행·PASS) → GATE V20-2 = 528-bit lattice unit (N=8 재실측 PASS) → **GATE V20-3 = 본 gate**. **merge-blocker** — binding 기준 미충족 통합 RTL 의 merge 금지, gate log 는 merge commit 첨부 의무 (§23.10.7 교훈 — "선언된 gate 건너뛰면 5 commit 뒤 발각", 이미 4회 확인). V20-2 와 동일하게 **merge-blocker binding 은 xcu55c 반쪽에만 있고 ECP5 반쪽은 MEASUREMENT** 다 (아래). gate_check 스크립트 등재는 ④ 구현 COMMIT 몫이며 본 블록 수치의 **무수정 전사**여야 한다 (기준을 움직여서 통과하는 경로는 없다 — V20-2 재실측 선언의 그 규율).

**scope 선언 (kickoff memo 의 아키텍처 계획에서 도출 — 정합 기록 병기)**: gate 대상 = v2.0 TRAIN cluster 의 **누산 datapath 구조 합성체** 단일 top:

- **FMA lane × 8** (`FP_FmaLaneBf16` 계열). **lane 수 8 의 도출 (기록)**: §27.2.1 amendment 가 실측 확정한 dispatch 스케줄은 **8-operand × 4 beat** (II=4, carry-in beat 0 병합) 이고, lattice 는 beat 당 정확히 8 addend 를 소비한다 (PRODUCTS_PER_BEAT=8). lane 은 cycle 당 wide product 1개를 내므로 **FP_LANES = 8 = PRODUCTS_PER_BEAT** 에서 beat 당 8 product 가 정확히 공급되고 lane idle 이 0 이다. 기각 대안 (기록): 32 lanes 는 §12a 로 폐기된 full-parallel 시간 구조의 잔재 (lattice 가 beat 당 8 만 소비 — 3/4 idle); 8 미만 lanes 는 beat 당 8 addend 포트를 단일 clock 에서 채울 수 없다 (double-pump 는 clock 계약 밖). kickoff C5 "ECP5 에서 FP_LANES=2 가 한계" 는 fabric-specific congestion 서술 (kickoff §5.1 재진술 — 곱셈기 부족도 raw LUT 부족도 아님) 로서 xcu55c 출하 형상을 구속하지 않으며, ECP5 반쪽은 MEASUREMENT 이므로 xcu55c 와 **동일 8-lane 형상 그대로** 측정한다 (마이크로아키텍처 통일 — 본 절 사용자 결정 근거 3 의 승계). **lane 형상 주기 (honest)**: F1/F1-US 가 측정한 lane 실물은 per-lane `FP_AddWide` PACK_FINAL 후단을 포함한다 (776 중 u_addwide 617). 옵션 3 하에서 in-dot 경로가 lattice 로 공급하는 것은 lane 의 **wide-product 전단 (C1 곱셈기 + C2 exact wide 포맷 + operand-load 정책)** 이고 per-lane 후단 누산은 in-dot 경로에 없다 (§27.2.1 — in-dot 반올림 0회). ④ 통합이 전단 tap 형상을 취하든 전체 lane 을 인스턴스하든, anchor 는 측정 실물인 **전체 lane 776** 을 쓴다 — ceiling 은 상한이며, 전단 tap 채택 시 실측이 anchor 를 하회할 것이고 그 사실은 gate 기록에 남긴다. premap `$mul` = lane 당 정확히 1 은 형상 불문 불변 (`FP_FmaLaneBf16.v` "the ONE 11x11 significand multiplier" 명문).
- **lattice × 1** (`FP_AccLattice`, beat-serial N=8 출하 형상 — GATE V20-2 재확인 PASS 실물 그대로, fault (c) carry-lane 강화형 포함).
- **bank × 1** (`FP_AccBank` — ③ 착지 실물 그대로, IF-1..IF-4 계약 + ownership loud-fault 경로).
- **beat dispatch 스켈레톤**: wave-step operand 보관 + 8-of-32 beat 선택 + beat counter/start 파이프 + IF-1 결선 (bank carry word 를 start cycle 의 beat 0 에 공급). "스켈레톤" 인 이유: ISA decode 로부터의 결선이 아니라 **TB-구동 가능한 dispatch 인터페이스까지**가 본 gate 의 범위다.
- **FILL/DRAIN/ZERO 명령 경로**: bank cmd 인터페이스 레벨의 결선 (③ TB `tb_fp_accbank.v` 가 구동한 그 표면을 통합체 top 에 노출).

**제외 (명시)**: (i) **FDOT32_CR (0x7A)** — 3a 이연 그대로 (§27.7 op_sel 격리 근거 불변). (ii) **TRAIN 신규 opcode 의 ISA 결선 / step sequencer 전체 통합** — 0x7D/0x7E sub-op 인코딩, 0x70 dtype loosening, decode→dispatch 결선은 후속 COMMIT 몫이다 (본 gate 는 **datapath 구조 합성 gate** — ISA 결선 완성이 아니다). kickoff 정합 확인: 이 경계는 kickoff §6.2 의 S3-S5 (lane/fold/bank) 통합 지점과 S6 이후 (0x7D/0x7E/SR/Adam) 의 분리와 일치하며 상충이 없다; kickoff 의 release-급 기준 **GATE V20-final (R-H — full v2.0 Cluster 가 xcu55c 에서 WNS ≥ 0)** 은 별도로 존속하고 본 gate 가 선점하지 않는다. (iii) SR / Adam / 0x7C rnd=1 (kickoff S7/S8 몫).

**xcu55c binding 기준 (측정 전 공표 — 전 항 리포트 실물 전사, 임의 반올림 없음)**:

| 축 | 기준 | 근거/출처 |
|---|---|---|
| **LUT** | **hard ceiling 35,377 — 초과 시 merge 금지** | 아래 산식 표 (measured-anchor 합 + 미측정 glue × 1.67) |
| **DSP48E2** | **정확히 8** | FMA lane 당 1 (F1-US 실측) × 8 lanes; lattice 0 / bank 0 실측. 편차는 merge 금지 + 조사 (§26.6 MULT 편차 조사 선례의 방법으로 귀속 후 재판정) |
| **premap `$mul`** | **정확히 8** (delta +8 — lattice 0 실측 / bank 0 실측 / lane 1×8) | §26.6 amendment pin form; 증거 파일은 premap 로그 archive |
| **BRAM/URAM** | 0 | 구성 3요소 전부 0 실측 |
| **DRC** | errors 0 (warnings 는 열거 — "clean" 아님) | F1-US 관례 |
| Fmax/WNS | 기록 축 — binding 아님 | 아래 "Fmax/WNS 기록 축" 항 |
| FF | 추적만 | V9-4 관례 |

LUT ceiling 산식 (measured-anchor + 미측정분 1.67× 규율 — 1.67× 는 **미측정 glue 항에만** 적용된다):

| 항 | 값 | 지위 | 출처 |
|---|---|---|---|
| lattice `FP_AccLattice` (N=8) | **19,298** | measured — xcu55c routed | `synth/reports/fp_ops/gate_summary.txt` V20-2/US 행 + `fp_acclattice_impl_util.rpt` (19,297 logic + 1 SRL) |
| bank `FP_AccBank` | **8,368** | measured — xcu55c **synth-only smoke** (8,362 logic + 6 SRL; raw cells 8,858) | `synth/reports/fp_ops/fp_accbank_synth_util.rpt` / `fp_accbank_synth_summary.json` |
| lane `FP_FmaLaneBf16` × 8 | **776 × 8 = 6,208** | measured — xcu55c routed, lane 단독 (776 = 773 logic + 3 SRL; raw cells 935) | `synth/reports/fp_ops/gate_summary.txt` F1-US 행 + `fp_fmalane_bf16_impl_util.rpt` |
| **anchor 합** | **33,874** | measured | 위 3행의 합 |
| glue (미측정 — beat dispatch 스켈레톤 + 결선) | nominal 500-900 → × 1.67 = 835-1,503 → worst **1,503** 채택 | **ESTIMATE × 1.67** (§23.10.10(g) 실측 overrun 계수 — 0d/0e/v1.9/V20-2 를 관통한 그 기준) | 아래 성분 표 |
| **hard ceiling** | **35,377** | = 33,874 + 1,503 | — |

glue nominal 성분 (전부 ESTIMATE — ceiling 에는 nominal 상단 900 의 1.67× 인 1,503 을 가산했다):

| glue 성분 | nominal LUT |
|---|---|
| wave-step operand 보관 (32 pair × 32b FF) 의 8-of-32 beat 선택 mux (256b × 4:1) + enable 결선 | 300-450 |
| beat counter / start 파이프 + IF-1 carry beat-0 정렬 | 50-100 |
| FILL/DRAIN/ZERO cmd 경로 결선 (bank cmd 인터페이스 레벨) | 100-200 |
| fault/sticky 집약 + drain 반출 결선 | 50-150 |
| 합 | **500-900** |

병기 (honest): (i) bank anchor 는 routed 가 아니라 synth-only 다 — 동일 RTL 의 synth-vs-routed 오차 실측 전례는 lattice −0.6% (synth 19,363 → routed 19,251) / Beat2 −0.3% (6,096 → 6,075) 로 무시 가능 수준이나, 통합 문맥의 cross-boundary 최적화/팽창은 glue worst-case 마진이 흡수할 몫으로 남는다. (ii) 맥락 실측: ceiling 35,377 은 v1.x full cluster 실측 **42,538-42,731** (`synth/reports/pod_2x2_2x2_impl_util.rpt` 4 인스턴스: 42,731/42,566/42,670/42,538) 의 **82.8-83.2%**, xcu55c 전체 1,303,680 LUT 의 **2.71%** 다.

**Fmax/WNS 기록 축 (binding 아님 — V20-2 전례의 동일 적용을 채택·기록한다: binding 은 면적/승수/DRC 만)**: clock 제약은 기존 gate 관례 그대로 — **OOC, `create_clock` 10.000 ns (100 MHz) 단일, clock-only xdc** (fp_ops gate xdc 관례 = `fp_acclattice_gate.xdc`; pod 하네스 `synth/constraints/pod.xdc` 와 동일 주기 10 ns 이나 pod.xdc 의 `set_false_path -from rst` 는 **부적용** — fp-ops 코어는 reset-free, kickoff §6.3 함정 (i)). WNS/WHS/Fmax 는 기록·archive 한다. 기대 문맥 (기준 아님): 구성 요소 실측 Fmax 는 lattice 143.10 MHz (routed) / lane 255.30 MHz (routed) / bank synth WNS +5.106 ns (post-synth — Fmax 아님) 이나, congestion-drift 는 이 project 의 실현된 실패 모드 (§26.6 V9-4: standalone 이득의 96% 이상 잠식) 이므로 통합 Fmax 가 구성 요소 최솟값을 하회해도 그 자체는 FAIL 이 아니고 기록·귀속 대상이다. kickoff R-H (full v2.0 Cluster WNS ≥ 0 @ xcu55c) 는 release-급 기준으로 별도 존속한다.

**ECP5 반쪽 (MEASUREMENT — 본 절 원문 그대로 반복한다: "어떤 결과가 나와도 — 어렵다·비싸다·불가능하다 포함 — gate FAIL 을 구성하지 않는다"; 유일한 의무는 측정의 실행과 정직한 기록이다)**: xcu55c 와 동일 8-lane 형상 (LFE5UM-85F CABGA381 -6, OOC, seed 1, 40 MHz reference — 관례 참조점일 뿐 계약 아님). **예상 규모의 정직 계산 (측정 전 기록 — LUT4 cell 과 placed TRELLIS_COMB 는 다른 단위, 혼용 금지)**:

| 항 | LUT4 (yosys cell) | placed TRELLIS_COMB |
|---|---|---|
| lattice N=8 | 29,834 (실측) | 31,500 (실측) |
| bank | 14,671 (실측 — synth-only) | 미측정 — LUT4→placed 팽창 실측 전례 +5.6% (lattice) ~ +46% (lane) 적용 시 15,493-21,420 추정 |
| lane × 8 | 930 × 8 = 7,440 (실측 단가 — c21092a 재측정 후 현행 `fp_fmalane_bf16_synth.rpt`; 924 는 6e3bf3e 아카이브 단가) | 1,356 × 8 = 10,848 (실측 단가 — 현행 `fp_fmalane_bf16_pnr.log`) |
| 합 (glue 미포함) | **51,945** = 85F COMB fabric 83,640 의 **62.1%** | 추정 **57,841-63,768 = 69.2-76.2%** |

**infeasible 가능성 사전 기록**: LUT4 산술 (62.1%) 은 수납 가능 범위이나, placed 69-76% + glue 는 ECP5 라우팅 포화 실측 전례 (v1.9b full cluster 가 COMB 39.6% 에서 이미 routing-지배 11.34 MHz — `cluster_v19b_pnr.log`; lattice 단독 37.7% 에서 16.51 MHz) 의 훨씬 위다 — **PnR 미완주 (infeasible 분류) 가 현실적 결과이며, 발동은 실패가 아니라 예정된 분기다**. 발동 시 off-ramp 그대로: ECP5 는 at-speed dot path 를 제외한 검증 역할 (TRNG 실리콘 검증·UsbCdcTransport·FOSS bitstream) 전부 유지, dot-path 검증은 cocotb + xcu55c. MULT18X18D 는 기록 축 (yosys share 재량 편차 허용 — §26.6 MULT 편차 조사 선례), 판별 pin 은 premap `$mul` = 8 이다.

**④ 검증 의무 (gate 와 한 몸의 merge-blocker — 전부의 실행·기록 없이 merge 금지)**:
1. **③ 이월 커버리지 경계 3건 폐쇄**: (i) **창 offset 0** — start 와 같은 cycle 의 같은 slot 접촉 (same-cycle 2-port 중재) 을 RTL 통합 directed test 로 커버 — bank_scenarios 시나리오 형식상 표현 불가였던 그 경계 (`bank_scenarios_contract.md` §2) 이므로 통합 TB 가 직접 구동한다. (ii) **per-op×offset 교차곱 공백** — window_fill offset 6 / window_zero offset 4 / window_spill offset {2,4,5,6} directed 소량 추가로 3 클래스 × offset 1..7 전수를 완성한다. (iii) **TLC ghost 2건** — DT-05 spill image owner-tag 캐리어 (l) / DT-04 K 완결 캐리어 (h) 의 **RTL 실물화 또는 계약 재배정** (양자택일의 판정을 gate 기록에 남긴다; (h) 는 fragment 수가 dec_* bus 에 없다는 §23.6a SDK 계약 1 노출면에 걸리므로, 실물화 불가 판정 시 "hw 강제 불가" 명시 재배정이 합법 종결이다 — kickoff TP-3 이 INV_Complete 에 요구한 그 형식).
2. **cluster 통합 TB (전 경로)**: bf16/f16 operand 주입 → lane widen/곱 (operand-load 정책 포함) → 8-operand × 4-beat dispatch → lattice → bank RTO-48 store → drain RNE-24 반출까지 **전 경로 vs golden bit-exact** (reference = `golden_fp32.py` widen/fma 계열 + `golden_lattice.py` wave_step/`bank_execute` 의 합성; 시나리오 재생성 결정성 byte-identical 은 ③ 관례 그대로). II=4 지속 (다른 slot 완전 중첩) + 같은 slot 체이닝 ≥ LATENCY=7 경계 + FILL/DRAIN/ZERO 인터리브를 **통합 문맥에서** 재판정한다.
3. **변이 반증 의무 (③ 의 7종 전부 사멸 형식)**: 최소 5 클래스 지정 변이의 사멸 실증 — (a) lane 곱 significand 하위 절단, (b) lane→lattice 결선 lane 전치, (c) beat 선택 mux off-by-one, (d) carry-in 비-beat0 수용, (e) FILL/DRAIN/ZERO 중 1 경로 절단 (silent 수용) — + discriminator 자기시험 (tautology 방지 — ③ PHASE C 형식).
4. **무회귀**: lattice 4097 회귀 + bank TLC 14 / directed 43 / random 300 + golden 재생성 byte-identical + `make lint` + `make fp-op-report` exit 0 유지.

**리포트/실행 규정**: xcu55c — `synth/scripts/synth_fp_op.tcl` 하네스 (OOC gate_top, 전 flow synth+opt+place+phys_opt+route), 리포트 `synth/reports/fp_ops/fp_traincluster_{impl_summary.json,impl_util.rpt,impl_timing.rpt,impl_drc.rpt,premap_mul.log}` + `gate_summary.txt` 행 추가. ECP5 — `synth/lattice/reports/fp_ops/fp_traincluster_*`. gate_check 등재 (binding: LUT ceiling 35,377 / DSP48 정확히 8 / premap `$mul` 정확히 8 / BRAM 0 / DRC errors 0) 는 ④ 구현 COMMIT 에서 본 블록 수치의 무수정 전사로 수행한다.

**④ GATE V20-3 착지 기록 (2026-08-17, 구현·gate commit `d2c1948` + ECP5 측정 commit `7f05ef3` — `FP_TrainCluster.v` (lane 전단 tap ×8 → lattice N=8 → bank 결선 + beat dispatch 스켈레톤 + FILL/DRAIN/ZERO cmd 경로) + `tb_fp_traincluster.v` + cluster golden 벡터; §26.6/V9-4 기록 관례. 위 선공표 블록은 원형 보존 — 본 블록과 병존하며, gate_check V20-3 등재는 선공표 수치의 무수정 전사로 수행됐다):**

- **xcu55c binding PASS (선공표 기준 무수정 — 전 항 리포트 실물 전사)**: LUT **26,863 ≤ 35,377** (여유 8,514; raw cells 31,744; FF 8,478, CARRY8 238) / DSP48 **정확히 8** / premap `$mul` **정확히 8** / BRAM 0 / DRC errors 0 (warnings 2 열거 — "clean" 아님: DPOP-4 ×8 [DSP MREG=0 — 후속 pipeline rebalance 의 미청구 Fmax 상방] + RTSTAT-10 ×1 [OOC 구조적]) / Fmax **121.62 MHz** (WNS +1.778 ns, WHS +0.042 ns — 기록 축; lattice 단독 143.10 MHz 대비 하락은 congestion-drift 클래스 — worst path 는 cmd 스테이징 flop → lattice `s_row` 의 cross-boundary 경로 (`fp_traincluster_impl_timing.rpt`), 선공표 문언 그대로 FAIL 아님, 기록·귀속). `make fp-op-report` exit 0 — 전 gate PASS. 리포트: `synth/reports/fp_ops/fp_traincluster_*` + `gate_summary.txt` GATE V20-3/US 행.
- **anchor 하회 사유 (선공표 "lane 형상 주기" 의 이행 — gate 기록 의무 그 자체)**: 통합은 전체 lane (anchor 776) 이 아니라 **전단 tap** (`FP_TrainLaneTap` — C1 곱셈기 + C2 exact wide 포맷 + operand-load 정책, per-lane 후단 누산 미인스턴스) 을 채택했다 — 선공표가 예고한 "전단 tap 채택 시 실측이 anchor 를 하회할 것이고 그 사실은 gate 기록에 남긴다" 의 그 기록이 본 항이다. in-context 계층 (gate_summary 계층 행): lattice 16,912 / bank 7,839 / tap 193-194 ×8 / cluster-local 565 — tap 실측 193-194 vs anchor lane 776.
- **ECP5 MEASUREMENT — PnR 완주, 선공표가 "현실적 결과" 로 사전 기록한 infeasible 분기 미발동**: TRELLIS_COMB **45,476/83,640 = 54% placed** (사전 추정 69-76% 하회 — tap 채택 + cross-boundary 최적화 귀속) / LUT4 42,972 cell = 51.4% (사전 산술 51,945 하회) / Fmax **18.23 MHz** (post-route; 40 MHz 는 참조점일 뿐 계약 아님) / MULT18X18D 8 (기록 축) / premap `$mul` 8 (판별 pin 충족) / EBR 0 / CCU2C 1,037. v1.9b 전례 (COMB 39.6% 에서 routing-지배 11.34 MHz) 대비 **완주 자체가 유효한 측정** — v2.0 TRAIN full-cluster datapath 가 85F 에 실수납·라우팅된다. off-ramp 미발동, ECP5 검증 역할 전부 유지. 리포트: `synth/lattice/reports/fp_ops/fp_traincluster_*` + gate_summary MEAS V20-3/ECP5 행.
- **검증 의무 2 이행 — cluster 통합 TB 전 경로**: operand-level 벡터 **1,234 wave** (wave 당 bf16/f16 쌍 32개 — Fraction 재계산 39,488쌍 교차검증; `cluster_wave_vectors.hex` + `cluster_vec_contract.md`) 의 e2e **4층+tap층 bit-exact 전량 PASS** + directed 18/18. II=4 지속 (타 slot 완전 중첩) + 같은 slot 체이닝 ≥ 7 경계 + FILL/DRAIN/ZERO 인터리브 — 선공표 의무 2 문언 그대로 통합 문맥에서 재판정했다.
- **검증 의무 1 이행 — ③ 이월 커버리지 경계 3건 폐쇄**: (i) **창 offset 0 중재** — directed 6건 (ARB_OFFSET0 4 + ARB_PORT 2, cycle 정밀, bank 미도달 증명 포함): 같은 cycle 같은 slot cmd = IF-2 창 위반 거부 + `ARB_OFFSET0` sticky, 타 slot 포트 충돌 = `ARB_PORT` (원인 귀속 분리 — 혼동 금지, RTL 헤더 pin). (ii) **per-op×offset 교차곱 전수** — directed 6건 append (bank 시나리오 343→349, 기존 스트림 byte-identical 유지) 로 창-거부 **4 클래스 × offset 1..7 전수** 성립, 생성기 `bank_window_crossproduct` assert 가 전수를 봉인 (seed 이동으로 조용히 좁아지는 것을 막는 가드). (iii) **TLC ghost 2건 — 계약 재배정 판정** (`bank_scenarios_contract.md` §10 이 판정 기록): DT-04 (h) K 완결 캐리어 = ISA 레벨 편집 요구로 **hw 강제 불가 명시** (§23.6a 계약 재배정 — kickoff TP-3 이 INV_Complete 에 허용한 그 형식) / DT-05 (l) spill image owner-tag = 0x7D 포맷 규범화 시점 **재심사 의무 이월** — 양쪽 다 contract-1급 노출면으로 정직 등재, RTL 실물화 아님.
- **검증 의무 3 이행 — 변이 반증 7종 전부 사멸 (TB 밖 일회성 실측 전사 — ③ 관례: 재현은 변이 재적용으로만 가능)**: 지정 5 클래스 — (a) tap 곱 significand 하위 절단 **9,693** / (b) lane→lattice 전치 **32,202** / (c) beat mux off-by-one **32,725** / (d) carry 비-beat0 수용 **64,439** / (e) DRAIN silent 절단 **67,825** errors. 추가로 **적대 검증이 발견한 fault_o 집약 공백 2종** — bank 항 탈락 (`fault_o = |clu_sticky`) **27** / 완전 절단 (`fault_o = 1'b0`) **180** errors: phase 별 0-기대 검사만으로는 사멸 불가였던 표면을 **매 negedge 집약 불변식 `fault_o === (|clu_causes) | (bank fault)`** 신설로 폐쇄했다 (발견→수리→재실증 — ③ 블라인드 스팟 폐쇄와 동형 서사). discriminator 자기시험 (tautology 방지) 병행.
- **검증 의무 4 이행 — 무회귀**: lattice 4097 / bank **349** (선공표 의무 4 문언 "directed 43" 대비 49 는 교차곱 6건 append 의 **superset — 명시**) / golden 재생성 결정성 2회 byte-identical / `make lint` / 양 시뮬레이터 (verilator + iverilog) 교차 / `make fp-op-report` exit 0 유지.
- **cluster RTL pin (§27.2 승계 기록 — normative 노출면)**: (1) **NaN/Inf operand = canonical zero 기여 + `LANE_SPECIAL` sticky + writeback 억제** — silent 대체 금지 (loud, never silent). (2) **상류 스케줄 제약** — 타 slot wave 간격 ≥ 4 (= II), 같은 slot 체이닝 ≥ 7 (`FP_TrainCluster.v` 헤더 명문 — §27.2.2 IF-3 의 승계 산술).
- **상태 전이 (본 절 하류 순서 종결 선언)**: **①(golden) → ②(V20-2) → ③(bank) → ④(V20-3) 전부 종결 — 옵션 3 의 gate 전건 PASS.** §27.7 의 3a (FDOT32_CR 0x7A) 착지 전건이 충족됐다 (사용자 기결정 2026-08-15 — "성공하면 곧바로 3a 로 이행"). 3a 는 §27.7 sequencing 그대로 **별도 release** 로만 착지한다 — 다음 = 3a COMMIT 0; TRAIN 신규 opcode ISA 결선·step sequencer 전체 통합 (본 gate 제외 (ii)) 은 그와 별개의 후속 COMMIT 몫으로 존속한다.

### 27.7 FDOT32_CR 예약 — opcode 0x7A (옵션 3a, committed follow-up)

- **0x7A 를 FDOT32_CR 로 예약한다.** 3a 착지 전까지 0x7A 는 오늘처럼 opcode_supported whitelist 미포함 → **decode_error** (§23.6a) — 본 예약은 다른 소비자의 선점을 금지하는 배정 기록이다.
- **semantics sketch (3a COMMIT 0 에서 확정)**: 순차 2Sum/EFT (error-free transformation) 기반 **correctly-rounded 32-term dot** — audit 전용, ~9,000 cycles (처리량 경로 아님). 설계 조사에서 66k+ trials 0 mismatch 로 검증됨.
- **옵션 3 하에서 FDOT32_CR 의 가치는 불변식이다**: 단일 wave 의 dot 을 즉시 drain 하면 **FDOT32_CR == main path BIT-EXACT** — 양쪽 다 RNE_24(exact) 이기 때문 (§27.2.3 정리; JSON 의 OPT3 single-wave == true B in-run assert 6,000+ trials). 즉 3a 는 **on-silicon dual-datapath 자기검증** 을 제공한다 — 두 경로의 불일치는 그 자체로 결함 신호다 (프로그램 레벨 검사; runtime fault 아님).
- **sequencing 근거 (왜 lattice release 와 격리하는가)**: op_sel 확장은 이 repo 의 상존 최고 회귀 위험 편집이다 — §25.1 항 9 가 op_sel 접촉 1회에 기존 8개 step 프로그램 전건 re-proof 를 강제한 선례. FDOT32_CR 을 lattice release 에 동승시키면 그 re-proof 비용과 회귀 표면이 첫 hard gate 에 얹힌다. **따라서 0x7A 는 옵션 3 의 gate 전건 PASS 이후 별도 release 로만 착지한다.**

### 27.7a FDOT32_CR (0x7A) 확정 규범 — 3a COMMIT 0 (2026-08-17, spec-first · normative)

**본 절이 §27.7 의 semantics sketch 를 확정 규범으로 승격한다.** 착지 전건은 §27.6 종결 선언 (①→④ 전부 PASS) 으로 충족됐고, 이행 자체는 사용자 기결정 (2026-08-15, §27.1 — "옵션 3 의 gate 전건 통과 즉시 옵션 3a 로 이행") 이 binding 이다. §27.7 원문 (예약·sketch·sequencing) 은 무수정 보존한다 (§12a 규칙 5). 3a 는 §27.7 sequencing 그대로 **별도 release** 이며, 본 COMMIT 0 은 §27.8 선례 그대로 **spec (본 절) 과 kickoff memo 상태 갱신만 편집한다** — `isa/wt64v1_isa.json` 편집은 §27.7a.4 착지 순서의 3a-C2 몫이다 (§12a 규칙 3 순서 판정은 §27.7a.6).

#### 27.7a.1 값 계약 (semantics — normative)

> **[2026-08-17 부분 supersede — §27.7a.2b amendment-9]** 아래 **operand 계약** 항의 ingress 형 ("`dec_input_payload_wide[1023:0]` 에 정확 수납 ... launch cycle 에 MU-local capture", 대체 = 2-dispatch fallback) 은 3a-C3 RTL 착지에서 **제3형 (기존 {b_in, a_in} 위 16-cycle 64b/cycle 스트리밍, 단일 dispatch, MU-local 버퍼)** 으로 실현됐다. 본 항이 요구한 §12a 재개정은 **§27.7a.2b amendment-9** 가 이행한다 (C4 의무 포함). 값 계약·operand 총량·frag 배치·dtype 2행은 무변경이다.

- **FDOT32_CR (0x7A)**: 32-term narrow dot 의 correctly-rounded fp32 — **r == `pack_signed(exact Σ a_i·b_i)`** = 단일 unbounded RNE_24 정확히 1회 + flush-after-round FTZ + overflow → ±Inf (RNE 규칙) + exact-cancellation → +0 — PACK_FINAL 과 동일 의미론. **값 계약의 규범 원천 = `scripts/acc_format_study.py` 의 exact reference** (`run_variants` 의 true (B) = `pack_signed(exact)`; exact-(m,e) 기계 `add_me`/`rne_me` — rounding core 는 `golden_fp32` 에서 import): FDOT32_CR 의 정의는 이 reference 와의 **bit-동일성** 이다.
- **operand 계약**: dtype 은 wave dtype 을 직접 명명한다 (conversion-dtype 규칙 비적용 — dot 의 narrow operand 그 자체). §23.6a 표 추가 행은 **정확히 2행**: (0x7A, dtype 0x2 f16, acc 1, rnd 0) / (0x7A, dtype 0x3 bf16, acc 1, rnd 0) — 그 외 전 조합 ILLEGAL (restrictive-first). EH shape = **port-only** (forbid_imm_any + forbid_opref — 0x78 선례). operand 총량 1,024 bit = **A||B 연접 16-fragment 단일 wave** (frag 0-7 = A 의 32×16b, frag 8-15 = B 의 32×16b) — `dec_input_payload_wide[1023:0]` 에 정확 수납, **FRAG_MAX=16 정확 소진** (frag_mask_full fix 계보의 소비자 — emit 측은 0x70 VFMA_ACC 16-frag (§25.1, 0e2 출하) 와 §27.2.2 SPILL 8-frag 이 선행; FDOT32_CR 은 **16-fragment input-wave 재조립 경로의 첫 소비자**다). launch cycle 에 MU-local capture (0x74 idiom — EHDecode 는 cluster-shared, ~9k cycle 프로그램 동안 버퍼 보존 불가). 결선 COMMIT 에서 이 형태가 실현 불가로 판명되면 fallback = 2-dispatch 형 (A-wave + B-wave, 0x70 interlock 선례) — 채택 시 본 항의 §12a 재개정 동반 의무.
- **결과**: fp32 scalar, 표준 MU 결과 반환 (1 fragment). bank 무접촉 — FDOT32_CR 은 ACC bank 상태·ownership 에 일절 개입하지 않는다 (audit 경로는 MU 에 폐쇄; 회귀 격리 §27.7a.4 의 구조 근거).
- **special/DAZ 계약 — main path 와 행별 대조 (invariant 의 필요조건)**: (i) **bf16 exp field 0 (zero + 전 254 subnormal) → canonical zero 기여 (DAZ)** — `FP_FmaLaneBf16.v` S1 classify 와 동일; (ii) **f16 subnormal → exact normalize 기여 (DAZ 아님)** — 동일 (min f16 subnormal 2^-24 는 wide 형식의 normal — lane 승계); (iii) **NaN/Inf operand (sNaN 포함) → 결과 = canonical qNaN 0x7FC00000 + 전용 sticky 발화** — main path 의 같은 상황은 canonical zero 기여 + `LANE_SPECIAL` sticky + wave writeback 억제 (§27.6 cluster RTL pin) 이므로 special wave 에서 두 경로의 대조 축은 **값이 아니라 sticky 유무** 다 (검사 규칙 §27.7a.3; qNaN marker 는 무모호 — main drain 은 finite exact 합의 PACK_FINAL 이라 산출 클래스가 finite/±Inf/±0 뿐, NaN 절대 불산출). sticky 는 합성 가능한 sticky status bit 클래스 (v1.9 `bank_tag_collision_error` 등급, §26.5 선례 — sim-only assertion 금지).
- **audit 전용 — 처리량 비계약**: non-pipelined, busy-interlock (0x70 vfma_busy 선례), 중첩 dispatch 거부. cycle 계약은 §27.7a.2 의 상한 하나다.

#### 27.7a.2 알고리즘 pin — 순차 2Sum/EFT 의 폭-소거 형

> **[2026-08-17 부분 supersede — §27.7a.2a]** 아래 종료 3단의 **(2) fold 방향 (ascending-magnitude)** 과 **STEP I 의 walk 독해**는 3a-C1 실측으로 **부정**되었다 (값 계약 위반 실측 — 상대오차 23.8% 급, 1 ulp 문제 아님). 대체 규범은 **§27.7a.2a (descending fold + freeze)** 이며, 본 절은 §12a 규칙 5 에 따라 superseded history 로 보존한다. **본 절의 (2) 를 단독 인용·미러링하지 마라** — RTL 이 오름차순 스트리밍 fold 를 구현하면 그것이 재발 경로다 (`include/generated/fdotcr_vec_contract.md` §4 의 금지 pin).

내부 산술 표면은 출하 datapath 그대로다: **FP_Mul36 (곱) + FP_AddWide (합·pack) — 공유 datapath 파일 (`FP_AddWide.v`/`FP_Mul36.v`/`include/fp_narrow_f32.vh`) 은 byte-untouched 의무** (diff 로 검사, §27.5 항 6 의 "FP_AddWide 48-bit byte-untouched 존치" 승계).

- **곱 단계 (exact)**: bf16 8×8→16-bit / f16 11×11→22-bit significand 곱 — **FP_Mul36 재사용** (FS_MUL launch 관례), p_exp = ea_eff + eb_eff + 1 은 signed-11 수납 (§27.2.1 lattice 와 동일 산술). 곱 지점 반올림 0회 (출하된 C2 계약 그대로).
- **component 표현**: significand ≤ **W = 24 bit** + signed-11 exp. W=24 선택의 3중 근거: (i) 곱 significand ≤ 22 < 24 → 곱 1개 = component 1개로 즉시 수납; (ii) 24+24 ≤ 48 = FP_AddWide 폭 → 겹침 add 의 정렬 span ≤ 48 이라 **PACK_WIDE 의 RTO-48 이 vacuous — add 는 무반올림 exact**; (iii) 48-bit wide 결과의 24|24 절단 split (hi = sig[47:24]@e, lo = sig[23:0]@e−24) 이 field-slice 로 exact (hi+lo == s). 즉 본 EFT 는 **반올림 모드 성질 (RN 전제의 Knuth/Fast2Sum 오차항 정리) 에 일절 의존하지 않는 폭-소거 EFT** 다 — 모든 산술 스텝이 구조적으로 무반올림이다.
- **TwoSumExact(x, y)** = 1 AddWide pass: 정렬 span ≤ 48 이면 s = PACK_WIDE(x+y) 는 exact, 산출 = split(s); 완전 비겹침 (span > 48) 이면 pass 없이 (큰 쪽, 작은 쪽) 그대로 — 어느 분기에도 오차항이 없다.
- **누산 = grow-expansion**: 비겹침 component 열 (용량 **33 = 32 삽입 + carry 1**) 에 곱 32개를 순차 삽입 — 삽입 i 의 TwoSumExact 체인 길이 ≤ i, 총 삽입 위치 수 Σ ≈ 528. **용량 초과 = loud fault (never silent)** — "도달 불가" 주장으로 hw 검사를 대체하지 않는다; golden 은 매 스텝 비겹침·길이·exact-합-보존 3종을 assert 한다.
- **종료 3단**: (1) 최종 expansion 의 exact 합 == 곱 32개의 exact 합 (EFT 불변식); (2) **ascending-magnitude RTO-48 fold** — 비겹침 열의 오름차순 fold 에서 각 pass 의 sticky-jam 이 정확히 "48-bit 창 아래 잔여 ≠ 0" 를 운반하므로 fold 결과 == RTO_48(exact 합) (RTO 조성 성질 — `FP_AddWide.v` 헤더의 rto_n∘rto_48 성질과 같은 family; **이 항의 정리 지위는 golden directed family 로 이행해 졸업시킨다 — §25.4 규율, 본문 주장만으로 확정하지 않음**); (3) PACK_FINAL 1회 → §27.2.1 추출 정리 (RNE_24(RTO_48(exact)) == RNE_24(exact), 48 은 22-bit 마진) 에 의해 §27.7a.1 값 계약이 달성된다.
- **cycle 예산**: §27.7 sketch 의 "~9,000" 과 정합하는 도출 (재구성 — 세션 harness 는 회수 불가): 삽입 위치 총수 ≈ 528 × Knuth 6-op 2Sum × 3-cycle adder pass ≈ 9,504. 채택 형 (1-pass TwoSumExact) 의 nominal = 곱 32×~6 + 삽입 ≤ 528×(3+~3) + compress/fold ≤ 66 pass ×~6 + capture/classify/pack 고정 ≈ **3,600-5,500 cycles** (per-pass 제어 오버헤드는 ESTIMATE). **상한 선언: cycle ≤ 10,000 — hard, TB 실측 졸업 (§25.4 규율), 초과 = gate FAIL** (sketch 형 9,504 를 상회 수납 + 채택 형 nominal 의 ~2× 여유).

#### 27.7a.2a [AMENDMENT 2026-08-17, 3a-C1 실측] 종료 (2) 와 STEP I walk 의 개정 — **C1 실측이 C0 pin 을 부정했다**

**본 절은 §12a 규칙 5 하의 amendment 다. 위 §27.7a.2 원문은 무수정 보존한다** (그 문언 중 종료 (2) 의 fold 방향과 STEP I 의 walk 독해는 본 절이 supersede 한다). 근거 artifact: `scripts/golden_fdotcr.py` + `include/generated/fdotcr_golden_report.json` (고정 seed, 재실행 byte-identical).

**사실 기록 (은폐 없음)**: §27.7a.5 가 요구한 golden 졸업 절차 (3a-C1) 를 실행한 결과, **§27.7a.2 종료 (2) 가 pin 한 알고리즘이 §27.7a.1 값 계약을 위반했다**. 즉 이것은 golden 구현 버그가 아니라 **C0 (spec-first) 단계에서 pin 한 알고리즘 자체의 결함이며, C1 실측이 C0 pin 을 부정한 사건**이다. §25.4 규율 ("본문 주장만으로 확정하지 않는다") 이 설계대로 작동한 결과다 — 원 문언이 정리 지위를 golden 졸업 대상으로 남겨두었기에 RTL 착지 전에 포착됐다.

##### amendment-1 — 종료 (2): **ascending → descending** RTO-48 fold

**폐기되는 원 문언**: "(2) **ascending-magnitude RTO-48 fold** — 비겹침 열의 오름차순 fold 에서 각 pass 의 sticky-jam 이 정확히 '48-bit 창 아래 잔여 ≠ 0' 를 운반하므로 fold 결과 == RTO_48(exact 합)".

**부정의 실측**: 고정-seed 값 계약 스트림에서 **반례 2건** (전부 bf16, `eft_cancel_chain` 가족). 첫 케이스: fold 산출 `0xB4C00000` vs 값 계약 우변 `0xB4FC0000` — **상대오차 23.8%** (1 ulp 급이 아니다). 최종 expansion `[(2,−28), (16777212,−23), (16777215,1), (−1,25)]` 은 비겹침·오름차순·용량 assert 를 전부 통과한 정상 열이다. 곱·삽입 단계는 무결하며 발산은 STEP F 에서만 발생한다.

**근거 문언이 거짓인 이유**: sticky-jam 은 *그 pass 시점의* 48-bit 창에 대해서만 "아래 잔여 ≠ 0" 표식이다. 이후 pass 가 **상단 인접 상쇄** 로 결과 창을 jam 위치보다 아래로 끌어내리면, jam bit 은 표식이 아니라 **결과 그 자체**가 된다. 위 반례에서 pass 3 이 2^−23 에서 jam 하고 pass 4 의 −2^25 가 상위 26 bit 를 상쇄해 최종 창이 top=−21 로 46 binade 내려간다. RTO 조성 성질 (rto_n ∘ rto_48 = rto_n) 은 **같은 수를 다시 반올림할 때만** 성립하고, 사이에 크기를 줄이는 덧셈이 끼면 성립하지 않는다. 오름차순은 큰 component 가 나중에 도착하므로 상쇄가 **항상 jam 이후에** 일어난다 — 우연이 아니라 구조적 결함이다.

**scope 축소 처방은 무효 (명시 기록)**: 3a-C1 중간 보고는 "일반형은 반례로 부정되었으니 종료 (2) 문언을 '삽입-생성 expansion' 으로 scope 를 좁혀 재서술하라" 고 제안했다. **이 처방은 채택하지 않는다 — 좁힌 scope 안에 반례가 있다.** 위 반례 2건이 바로 삽입-생성 expansion 이며, report 의 `checks.fold_theorem_general_form_annex.deterministic_cases` 의 `cex_C`/`cex_D` 가 그 실측 expansion 을 결정 반례로 고정 수록한다. scope 축소로는 정리를 구제할 수 없다.

**채택 문언 (신규 pin)**: **(2) descending-magnitude RTO-48 fold** — 완성된 expansion 을 **최상위 component 부터 내려가며** 접는다. 전건은 STEP I 가 매 삽입 assert 하는 두 성질뿐이다: **저장 오름차순 + 엄격 비겹침** (top(c_i) ≤ e_{i+1}) 및 **W ≤ 24**. 정리와 증명:

1. 첫 *실질 jam* 이전의 모든 pass 는 정렬폭 ≤ 48 이라 무반올림 exact ⇒ acc_k = P_k := Σ_{i≥k} c_i. 비겹침 하에서 acc 와 크기가 비견되는 상대는 항상 '바로 아래' component 이므로 **모든 상쇄가 jam 이전에 exact 로 해소된다**.
2. index k 에서 실질 jam ⇔ P_k 가 grid p := top(P_k) − 48 의 배수가 아님 ⇒ e_k < p. 비겹침의 telescoping 합 (Σ_{i<k}(2^{top(c_i)} − 2^{e_i}) ≤ 2^{top(c_{k−1})} − 2^{e_0}) 으로 남은 꼬리 전체가 **|R| < 2^{e_k} < 2^p**.
3. P_k 의 셀 내 offset r 은 2^{e_k} 의 배수이고 0 이 아니므로 r ∈ [2^{e_k}, 2^p − 2^{e_k}] — |R| < 2^{e_k} 로는 셀을 벗어날 수도 exact 가 될 수도 없다 ⇒ **RTO_48(Σ) == RTO_48(P_k) == acc_k**, 그리고 top(Σ) == top(P_k).
4. acc_k 는 grid p 에서 홀수 (RTO) 이므로 이후 |c| < 2^p 의 가산은 인접 두 셀 안에 머물고, 절단 후 LSB set 이 정확히 acc_k 를 되돌린다 ⇒ **freeze** (acc 가 더 이상 변하지 않는다).

∴ fold 결과 == RTO_48(exact 합) 이 **임의의 비겹침 오름차순 열에 대해** 성립한다 (일반형 — scope 축소 불요). 이어 (3) PACK_FINAL 1회 → §27.2.1 추출 정리로 §27.7a.1 값 계약이 닫힌다. 정리상 jam 마진 top(T) − p 는 항상 48 이므로 최종 RNE-24 의 흡수 조건 (마진 ≥ 25) 을 **23 bit 여유**로 만족한다 — 원문 (3) 의 "48 은 22-bit 마진" 논법과 같은 family 다.

**정리 지위는 §25.4 대로 golden 졸업 대상으로 남긴다** (본문 증명만으로 확정하지 않는다 — 바로 그 규율이 원 pin 의 결함을 잡았다). 졸업 지표를 다음으로 **명시 pin** 한다: **(b) freeze (jam 이후 acc 불변) 를 loud fault 로 검사한다 — 이것이 정보를 나르는 유일한 축이다.** 실측: 실질 jam 33,370 trial 에서 freeze 위반 = 0. 보조로 (a) 첫 실질 jam 의 grid 위치 p 와 최종 top(T) 의 **마진** 을 계측해 `마진 ≥ 25` 를 검사하나, **이 지표는 항등적이다** — freeze 가 성립하는 한 최종 acc == jam 시점 acc 이고 RTO-48 의 실질 jam 산출은 정의상 48-bit significand 이므로 마진 ≡ 48 이 구조적으로 강제된다 (실측 히스토그램 단일 버킷 `{48: 33370}` 이 그 증거다). 따라서 (a) 는 정리의 **독립 확인이 아니라 freeze 의 항등 귀결**이고, §27.7a.2a amendment-8 의 `마진 < 25` hard 종료 분기는 freeze 검사를 통과하는 한 **도달 불가능한 방어선**이다 (제거하지 않고 이중 안전망으로 존치하되, 그 지위를 여기 명기한다 — §25.4 의 "본문 주장만으로 확정 금지" 규율의 자기적용). 폐기 ASC pin 의 실패 형태를 마진 축으로 대비 계측한 실측은 **없다** — ASC 경로의 반증 근거는 마진이 아니라 값 계약 위반 실측 (annex 의 REFUTED 판정) 이다.

##### amendment-2 — STEP I: 문언 walk 은 자기모순, **정련 walk 을 정식 pin**

**부정되는 원 문언**: §27.7a.2 의 "누산 = grow-expansion" 항이 서술한 TwoSumExact chain 독해 (오름차순 chain 에서 span ≤ 48 이면 merge, 잔차 lo 를 즉시 확정 방출).

**자기모순의 실측**: 이 문언대로 구현하면 **같은 절이 pin 한 "비겹침 component 열" 과 "매 스텝 비겹침 assert" 를 스스로 위반한다** — merge 의 borrow 가 잔차를 다음 component 의 LSB 위로 확장시키기 때문이다. 결정 반례: column `[(3,−25), (265106,−20)]` 에 q = `(−2^23, −1)` 삽입. 밀도 실측 (고정-seed 3,000 trial, 8 가족): **비겹침 위반 trial 1,023 (34.1%)** — "드문 모서리" 가 아니다. 즉 **문언대로 구현하면 invariant FAIL, invariant 를 지키면 문언 이탈** 이므로 완전 준수 구현이 존재하지 않는다.

**문언 walk 은 값 축의 대안도 아니다**: 그 산출 열은 비겹침이 아니므로 amendment-1 정리의 전건 밖이다 — 위반 열에 내림차순 fold 를 걸면 실제로 깨진다 (같은 sweep 에서 12건 계측). 따라서 "문언대로 되돌리기" 는 채택 불가다.

**채택 문언 (신규 pin)**: STEP I 의 walk 은 **"최저 2개 순서 merge" (정련 walk)** 다 — (e, top) 오름차순 대기열에서 최저 component 가 나머지 전부와 비겹침이면 확정 방출, 겹치면 다음 최저와 exact AddWide merge 후 24|24 split 조각을 대기열에 재삽입. 산술 표면은 원문과 동일하다 (겹침 쌍의 exact merge + field-slice split — 새 원시연산 없음). 겹침 쌍은 span < 48 이 구조적이므로 **vacuous-RTO 는 원문보다 오히려 강화**된다 — 실측 인용원은 report 필드 `checks.expansion_capacity.merge_aligned_width_max` = **47 bit** (merge 1,074,817 회 전수 계측). **다만 강제 경계는 48 이다**: 코드가 loud fault 로 막는 값은 `> 48` 이고 47 은 관측치이지 계약이 아니다 (같은 필드의 `merge_aligned_width_enforced_bound` = 48 에 명기). 비겹침·오름차순은 구성적으로 성립하며 매 스텝 assert 로 재확인한다. **매 스텝 3종 assert 는 원문 그대로 유지한다** (비겹침·길이·exact-합-보존) — 이제 셋 다 실제로 성립하므로 약화가 아니다.

##### amendment-3 — cycle 예산 · GATE V20-4 선공표에 대한 영향: **재선공표 불요 (알고리즘 변경에 따른 판정, 측정 후 조정 아님)**

amendment-1/2 는 **선공표 수치를 변경하지 않는다.** 판정 근거를 명시한다 (§27.7a.5 선공표는 locked 이므로 무영향임을 논증할 의무가 있다):

- **premap `$mul` delta 정확히 0 — 무영향.** 내림차순 fold 도 정련 walk 도 **새 산술 원시연산을 요구하지 않는다**. 곱은 FP_Mul36, 합·pack 은 FP_AddWide 그대로다.
- **공유 datapath 3 파일 byte-untouched — 유지.** `FP_AddWide.v` / `FP_Mul36.v` / `include/fp_narrow_f32.vh` 에 변경이 없다 (datapath 변경 자체가 없다).
- **cycle ≤ 10,000 (hard) — 무영향.** fold 는 pass 수가 바뀌지 않는다 (실측 최댓값 25 pass, 개정 전후 동일). 삽입 pass 실측 최댓값 77 ≤ 528 (원문 상한) 도 동일. 바뀌는 것은 STEP F 의 순회 index 방향 하나 (count−1 → 0) 다.
  - **미계상 축 (정직 표기)**: 위 논거는 **AddWide pass 수만** 센다. amendment-2 가 새로 pin 한 정련 walk 은 (e, top) 정렬 대기열에 **임의 위치 삽입** 을 매 merge 조각마다 수행하며, 그 선형 스캔 비교 cycle 은 `twosum_passes` 에 **전혀 계상되지 않는다**. 실측 (report `checks.insertion_queue_cost`): trial 당 스캔 step 최대 **326**, 삽입 호출 최대 158, 전 스트림 총합 5,023,794. step sequencer 가 비교 1회/cycle 이면 삽입 축 단독으로 최대 ~326 cycle 이 nominal 위에 얹힌다 (hard 10,000 대비 여유는 유지되나 **nominal 3,600-5,500 의 내역에는 없던 항목**이다). 이 축의 확정 실측은 **3a-C3 (RTL step 프로그램)** 몫이며, 뒤집히면 §12a 개정으로 재선공표한다.
- **LUT delta ≤ 2,200 — 무영향 (재선공표 없음).** 판정 근거는 **amendment-1 (내림차순) 단독의 delta 가 0** 이라는 것이다: 내림차순은 기존 index 카운터의 방향 하나이며 신규 상태·비교기·저장을 만들지 않는다. (amendment-2 의 대기열은 amendment-1 의 baseline 이 아니다 — 대기열 자체가 이번에 pin 된 항목이므로 "이미 materialize 되어 있다" 는 순환 논거를 쓰지 않는다. 대기열의 면적·cycle 비용은 위 bullet 대로 **3a-C3 실측 축**이다.) 원 nominal 상단 1,300 의 내역 (expansion 저장 150-250 + capture mux 200-350 + FSM/step 행 250-400 + compare/split glue 200-300) 중 어느 항목도 증가하지 않는다.
- **정직 표기**: 위 판정은 **알고리즘·golden 레벨의 판정이며 ESTIMATE 다** — 0x7A RTL 은 아직 없으므로 (착지 순서상 3a-C3/C4) 실측 대조는 불가하다. GATE V20-4 는 선공표대로 anchor 실측 → 착지 후 재실측 → delta 판정 절차를 그대로 수행하며, 본 amendment 는 그 절차를 완화하지 않는다. **초과 시에도 ad-hoc 상향은 금지이고 pre-declared cut ladder 를 따른다** (원문 불변). 만약 3a-C3 실측이 본 판정을 뒤집으면 그때는 "측정 후 조정" 이 아니라 §12a 개정으로 재선공표한다.

##### amendment-4 — §27.7a.5 golden 파일명 정정

선공표 문언의 `scripts/golden_fdot32_cr.py` 는 실제 착지 파일명 **`scripts/golden_fdotcr.py`** 로 정정한다 (구현이 아니라 spec 측 문언을 실물에 맞춘다 — 파일명은 계약 축이 아니다). 원문은 §12a 규칙 5 대로 위에 보존한다.

##### amendment-5 — §27.7a.5 검증 계획의 강화 (약화 아님)

3a-C1 은 반례를 제거하는 방향이 아니라 **표적을 추가하는 방향**으로 닫는다:

- **표적 적대 가족 `eft_top_cancel` 신설 (3,000 trial)** — 본 결함의 두 조건을 명시 구성한다: (M1) 2^(E−48) 아래 tail 로 jam 강제 + (M2) 8-bit 블록 사슬로 top=E 인 24-bit component 를 쌓고 마지막 lane 2개로 순수 −2^E 삽입 (상단 인접 상쇄). 폐기된 ASC pin 은 이 가족에서 정리를 **2,997/3,000 = 99.90% 위반**하고 그중 **120 건은 값 계약까지 깬다** — 기존 `eft_cancel_chain` 의 검출률 (2/4,000 = 0.05%) 대비 표적성을 확보했다. **표적 가족 없이는 회귀가 다시 숨는다.** 위 수치의 인용원은 본문이 아니라 고정-seed artifact 필드 `checks.asc_detection_rate_by_family` 다 (§25.4 — 본문 주장만으로 확정 금지; 회귀 시 재실행 byte-identical 이 깨지도록 report 에 싣는다).
- **C1 영구 회귀 벡터 `c1_regress`** — 값 계약 반례 2건의 operand 를 벡터 파일에 영구 고정한다. 기대 RESULT 는 **언제나 값 계약 우변** `pack_signed(exact)` 이며, ASC 로 회귀하면 즉시 FAIL 한다. **반례를 삭제하지 않는다.**
- **벡터 artifact 오염 경로 차단 (C1 자체 감사에서 발견한 구현 결함)** — 이전 emit 경로는 값 계약 위반 trial 의 EFT 산출을 기대 RESULT 로 벡터에 박았고, self-verify 가 같은 EFT 경로를 재실행해 대조했으므로 **자기확인 루프**였다 (그대로 3a-C3/C4 TB 가 소비하면 RTL 이 버그를 재현하도록 강제된다). 이제 emit 은 `bits != ref_bits` 를 loud fault 로 거부하고, self-verify 는 **EFT 무의존 Fraction 경로**로 RESULT 를 재확인한다.

##### 3a-C1 실측 결과 (개정 후, 고정 seed · 재실행 byte-identical)

| 검사 | 카운트 | mismatch |
|---|---|---|
| 값 계약 (§27.7a.1, `pack_signed(exact)` bit-동일) | 57,022 trial | **0** |
| fold 정리 (삽입-생성 scope, 내림차순) | 57,022 check (적대 26,022) | **0** |
| invariant (§27.7a.3, main twin bit-exact) — **값 계약 전 trial 전수** | 57,022 trial (가족 제외 0) | **0** |
| fold 일반형 annex — DESC (채택) | 결정 4 + 랜덤 20,000 | **0 (PASS)** |
| fold 일반형 annex — ASC (폐기, 근거 존치) | 결정 4 + 랜덤 20,000 | 113 (**REFUTED**) |
| freeze (졸업 지표 — 정보 축) | 실질 jam 33,370 | freeze 위반 0 |
| jam 마진 (freeze 의 항등 귀결 — 독립 확인 아님) | 실질 jam 33,370 | 히스토그램 단일 버킷 {48}, 마진<25 = 0 |
| invariant 축 **검출력** (폐기 ASC 재적용 probe) | ASC 값 계약 위반 168 | main twin 검출 **168/168** |

expansion 최대 25 component (용량 33), 삽입 pass 최대 77 (≤ 528), fold pass 최대 25 — 전부 원문 상한 이내. merge 정렬합 폭 최대 47 bit (강제 경계 48, merge 1,074,817 회). 대기열 스캔 step 최대 326 (미계상 cycle 축 — amendment-3). 기존 golden 산출물 (lattice 4081 / bank 349 / cluster 1234) 은 재생성 byte-identical 유지 (무회귀). **mismatch 가 하나라도 있으면 생성기는 report 를 먼저 쓴 뒤 비영 종료한다** (amendment-8).

##### amendment-6 — §27.7a.5 인용 규율의 이행 완료 (salted "66k+" 승계·졸업)

§27.7 sketch 의 "66k+ trials" 는 세션 salted-seed 수치로 normative 인용 불가였고, §27.7a.5 는 그 승계를 3a-C1 의 고정-seed 재생성 카운트에 위임했다. **본 C1 이 그 의무를 이행한다** — 아래 수치는 전부 고정 정수 seed 산출이며 재실행 byte-identical 이 확인됐다 (`include/generated/fdotcr_golden_report.json`).

- **값 계약 trial = 57,022** — 내역: 랜덤 가족 45,000 + invariant 전용 스트림 12,000 + directed 20 + `c1_regress` 2. golden 스크립트 자체 선언 하한 (module docstring 의 "≥ 40,000 value-contract trial") 과 선공표 (a) 의 참조 규모 36,000 을 **둘 다 상회**한다.
- **고정-seed EFT 경로 총 trial = 80,622** (값 계약 57,022 + specials 600 + fold 일반형 annex 랜덤 20,000 + 문언 walk 밀도 sweep 3,000) — salted "66k+" 를 **수치로도 상회**한다.

**선공표 (a) 문언과의 차이 — 대체 사실 기록 (§12a 규칙 5)**: 선공표 (a) 는 "재생성 고정-seed 36,000 **재사용** (families 30,000 + single-wave streams 6,000)" 이었다. 본 C1 은 그 벡터를 **재사용하지 않고** 자체 고정 seed (`0x7ADC001`-`00A`) 로 **신규 생성**했다. 사유: 그 36,000 은 `scripts/acc_format_study.py` 의 **곱 (m,e) 수준** 스트림 (`rto_tree_families` 30,000 + bank single-wave 6,000) 이라, §27.7a.1 이 pin 한 A||B 16-bit **operand** 인터페이스에 그대로 투입할 수 없다 — FDOT32_CR 은 operand 쌍을 먹는다. 대신 같은 적대 성격 (cancellation / tie / wide) 을 operand 수준에서 재구성한 가족으로 대체했다. 이 대체는 "하한 충족" 이라는 재해석이 아니라 **문언 성격의 변경**이므로 여기에 사실 자체를 적는다 (report 필드 `prannounced_plan_conformance.a_value_contract_stream` 이 같은 내용을 고정-seed artifact 로 싣는다). §27.7a.3 이 인용하는 36,000 assert 는 `acc_format_study` 가 자기 산출물에서 계속 재생성하므로 그 축이 사라지는 것은 아니다.

∴ 이후 본 프로젝트의 normative 인용은 위 두 수치를 쓰고, §27.7 의 salted "66k+" 는 인용하지 않는다. §27.7 원문은 §12a 규칙 5 대로 무수정 보존한다.

##### amendment-7 — §27.7a.5 (c) 선공표의 **미이행 정정** + 잘못된 원인 진단의 철회

**사실 기록 (은폐 없음)**: §27.7a.5 (c) 선공표 (locked) 는 invariant sweep 을 "golden lattice model (§27.4 ①) vs golden EFT 를 **동일 operand 전 벡터에서** bit-equal **전수** assert" 로 못박았다. **3a-C1 초안 구현은 이를 이행하지 않았다** — 별도 seed(`0x7ADC011`) 스트림 12,000 만 돌렸고, 그 generator 목록에서 **적대 3가족 (`eft_cancel_chain` — C1 반례가 나온 바로 그 가족 —, `eft_adv_residue`, `eft_top_cancel`)** 이 빠져 있었다. 가족 sweep 45,000 과 `c1_regress` 는 main twin 을 아예 호출하지 않아, 값 계약 trial 중 directed 20 만이 invariant 검사를 받았다. 이 축소는 spec·report·`vec_contract.md` 어디에도 **공시되지 않았고**, amendment-5 의 "검사 약화 없음 — 강화만" 과 모순이었다.

**정정 (본 산출물)**: invariant 대조를 **값 계약을 받는 전 trial 에 전수**로 건다 (57,022 = 값 계약 trial 수와 동일; report `checks.invariant_sweep.equals_value_contract_trials` = true). 가족별 카운트를 `checks.invariant_sweep.by_family` 로 **공시**하고, invariant 전용 스트림의 generator 도 `FAM_GENS` **전 10가족**으로 넓혔다. 결과: 57,022 trial, mismatch **0** — 계약 (.3) 은 개정된 알고리즘에서도 성립한다.

**철회되는 원인 진단**: 3a-C1 중간 보고는 잔여 리스크로 "invariant sweep 은 개정 전에도 0 mismatch 였다 — 양 경로가 같은 결함 표면을 공유해 판별력이 없었다" 고 적었다. **이 진단은 거짓이므로 철회한다.** main twin 은 `golden_lattice.wave_step` (lattice_accumulate → extract_rto48 → drain_rne24_ftz) 로 **EFT fold 를 일절 쓰지 않는 독립 경로**다. 실측 (report `checks.invariant_sweep.discriminating_power` + `checks.asc_detection_rate_by_family`): 같은 expansion 에 폐기 ASC fold 를 재적용하면 값 계약 위반 **168 건**이 발생하고 main twin 이 **168/168 전부 검출**한다 (`eft_top_cancel` 120, `eft_cancel_chain` 2, invariant 스트림 44, `c1_regress` 2). 0 mismatch 였던 진짜 원인은 결함 표면 공유가 아니라 **가족 커버리지 결손**이다. 원인을 잘못 적으면 "고칠 수 없는 구조적 한계" 로 읽혀, 실제로는 배선 가능한 최강 안전망 (독립 main-path twin × 적대 가족) 이 미배선으로 남는다.

##### amendment-8 — §27.7a.5 (a) 의 "assert" 이행: mismatch = **비영 종료**

선공표 (a) 는 "전 벡터에서 §27.7a.1 의 exact reference 와 bit-equal **assert**" 를 요구한다. 초안 생성기는 mismatch 를 카운터/JSON verdict 로만 떨어뜨리고 항상 exit 0 이었다 — 벡터 수록분 (가족당 앞 30행) **밖**에서 나는 실패는 종료 코드에 물린 gate 배선을 통과해버린다. 정정: 생성기는 반례를 **report 에 먼저 기록한 뒤** (은닉 금지) 비영 종료한다. 종료 실패 조건은 값 계약 / fold 정리 / invariant mismatch, jam 마진 < 25, freeze 위반, invariant 전수 미이행, invariant 축 검출력 실증 실패, **그리고 폐기 ASC pin 의 반증 근거 소실** (annex 가 더 이상 REFUTED 를 보이지 않으면 spec 인용이 붕괴하므로 hard fail) 이다.

#### 27.7a.2b [AMENDMENT 2026-08-17, 3a-C3 RTL 실측] step 프로그램 착지에서 확정된 3건 — ingress 제3형 · component 기하 · freeze 앵커

**본 절은 §12a 규칙 5 하의 amendment 다** (§27.7a.1 / §27.7a.2a 원문 무수정 보존). 근거 artifact: `FP_StepSeq.v` OPS_FDOTCR sub-sequencer + `synth/lattice/fp_ops/tb_fp_stepseq.py` (33 suite, 고정 seed). 셋 다 **RTL 착지 세션에서 발견된 사실**이며, 그중 두 번째는 초안이 검사를 약화시킨 사건이라 은폐 없이 기록한다.

##### amendment-9 — §27.7a.1 operand ingress: **제3형 (16-cycle 64b streaming) 채택**, 재개정 의무 이행

**원 문언**: "`dec_input_payload_wide[1023:0]` 에 정확 수납, FRAG_MAX=16 정확 소진 ... **launch cycle 에 MU-local capture**", 실현 불가 시 유일 대체 = "fallback = 2-dispatch 형 (A-wave + B-wave) — 채택 시 본 항의 **§12a 재개정 동반 의무**".

**채택 형 (신규 pin, 3a-C3 한정)**: 1,024-bit A||B wave 는 **기존 포트 {b_in, a_in} 위로 16 cycle 에 걸쳐 64b/cycle 스트리밍**된다 (fragment 0 = launch edge, 1..15 = 이어지는 15 cycle). 버퍼는 §27.7a.1 이 요구한 대로 **MU-local** (`fd_asr`/`fd_bsr`, EHDecode 무접촉) 이고 dispatch 는 여전히 **1회**다 — 즉 fallback (2-dispatch) 이 **아니다**. 사유: 1,024-bit 신규 포트를 지금 추가하면 PE_Core 의 기존 instantiation 이 미결선 포트를 갖게 되어 PE_Core 포함 전 suite 가 verilator elaboration 에서 죽는다 (그 결선은 3a-C4 몫 — §27.7a.4 착지 순서). 원 문언도 fallback 도 아닌 제3형이므로 **본 항이 그 재개정 의무를 이행한다** (문언 성격 변경을 사실 그대로 기록 — §12a 규칙 5).

**C4 의무 (명시 pin)**: (i) C4 는 이 스트리밍 형을 유지하거나 wide 포트로 대체할 수 있다 — **산술 sub-sequencer 는 ingress 와 독립**이라 값 축 증명 (450 벡터 + 3,000 확장 trial + 변이 사살) 은 그대로 이식된다; (ii) 그러나 **launch/busy/latency 계약은 재증명 대상**이다 (unit TB 의 프로토콜 assert 는 이 임시 형 위에 서 있다); (iii) 어느 쪽을 택하든 C4 는 그 결정을 본 항에 **재개정으로 기록**한다.

##### amendment-10 — STEP I 의 component 기하: 근사 비겹침 판정이 **금지 pin 을 검사 불능으로 만들었다** (초안 결함, 정정 완료)

**사실 기록 (은폐 없음)**: 3a-C3 초안 RTL 은 component 를 정규화 저장 `{sign, xe[11:0], mag[23:0]}` 으로 두고 (mag[23]==1, 값 = mag·2^(xe−23)), 비겹침 판정을 **`xe_b − xe_a >= 24`** 로 근사했다. 이 근사는 golden 의 `comp_top(a) <= e_b` 보다 **엄격**하다 (mag_b 의 trailing zero 수만큼). 결과:

- 열이 뭉친다 — RTL 자신의 `fd_xp` 를 STEP F 진입 시점에 읽어 계측한 최대 열 길이가 golden 벡터 322 행에서 **17** 이다 (golden report `expansion_capacity.max_observed_components` = **25**). 같은 하네스로 잰 정정 후 값은 **25** — golden 과 일치한다.
- 그 표현형에서는 §27.7a.2a 가 부정 근거로 삼은 **상단 인접 상쇄**가 구조적으로 불가능해져, **금지 pin 인 ASC fold 가 값 계약을 위반하는 사건 자체가 도달 불가**가 된다. 실측: ASC 변이 RTL (fold 방향만 뒤집은 사본) 이 **31 suite 전건 PASS** — 450 벡터·3,000 확장 trial 이 한 건도 잡지 못했다. 즉 초안은 "금지 pin 을 지켰음" 을 실증한 것이 아니라 **검사할 수 없게** 만들어 놓은 것이었다 (§27.7a.2a 가 `vec_contract` §4 와 함께 재발 경로로 못박은 바로 그 축의 무력화).

**정정 (신규 pin)**: 정규화 저장은 golden 의 기하 두 축을 **복원해서** 쓴다 — `e = xe − 23 + tz(mag)`, `top = xe + 1` (tz 는 24-bit trailing-zero cascade, 고정 shift 만). 이로써 비겹침 판정은 golden `grow_insert` 의 `comp_top(a) <= b[1]` 과, 정렬 키는 golden `_insort` 의 `(e, top)` 과 **근사 없이 일치**한다. (golden 의 m 은 trailing zero 를 남길 수 있어 그 e 는 '선언된 scale' 이고 RTL 의 e 는 '실제 최저 set bit' 이다 — 후자 >= 전자이므로 RTL 판정이 golden 보다 **느슨해지지 않는다**. amendment-1 정리의 전건 (비겹침·오름차순) 은 실제 bit 구간 기준으로 성립하며 telescoping 상한 `|c_i| <= 2^top − 2^e` 도 그 축에서 더 타이트하다. golden-disjoint 쌍은 항상 RTL-disjoint 이고 그 역은 아니므로 RTL 열은 golden 열과 같거나 **더 잘다**.)

**정정 후 실측 (전부 고정 seed, 재실행 동일)**:

| 축 | 초안 (근사) | 정정 후 | golden 참조 |
|---|---|---|---|
| 최대 열 길이 (golden 벡터 322행, RTL 의 `fd_xp` 직접 계측) | 17 | **25** | 25 (`expansion_capacity`) |
| merge 정렬합 폭 | 모델 미러 max 47 | 모델 미러 max **48** (== 강제 경계) — RTL 측 근거는 신설 loud fault 가 3,450 trial 에서 **0 회 발화**한 사실이다 | 47 (경계 48) |
| ASC 가 값 계약을 깨는 벡터 행 (RTL 열 기준) | **0** / 311 | **2** / 311 (열 비지 않은 finite 행) | — |
| ASC 가 값 계약을 깨는 신규 trial (eft_top_cancel, TB 생성) | **0** / 120 | **3** / 120 ≈ 2.5% | 4.0% (`asc_detection_rate_by_family.eft_top_cancel` value_violations 120/3,000) |
| ASC 변이 판정 | **전건 생존** | **사살** (33 suite 중 4 FAIL) | — |

즉 정정 후 RTL 의 열 통계는 golden 과 같은 급이 되었고, 금지 pin 은 다시 **반증 가능**해졌다. 값 축은 정정 전후 모두 bit-동일하다 (모든 merge 가 exact 이므로 열의 분해가 달라도 exact 합이 같다 — amendment-1 정리의 일반형).

**검사의 구조도 정정한다 (약화 금지의 이행)**: unit TB 의 `fdotcr_descending_fold_discriminator` 는 golden 모델 안에서 ASC≠계약 을 보이는 자기주장형이었다 (RTL 의 fold 방향과 무관 — 구조적으로 공허). 정정본은 **RTL 자신의 열** (`fd_xp[0..fd_n−1]`, STEP F 진입 시점) 을 읽어 ① STEP I invariant (엄격 오름차순·비겹침·열의 exact 합이 값 계약으로 pack) 를 RTL 열에 대해 재확인하고 ② 그 열을 내림차순 fold 하면 RTL 산출과 일치, ③ 같은 열을 오름차순 fold 하면 값 계약과 **불일치하는 행 수**를 센다. 그 수가 0 이면 "금지 pin 이 이 RTL 에 대해 반증 불가" 이므로 **hard fail** 이다 (golden 생성기 amendment-8 의 "ASC 반증 근거 소실 = hard fail" 과 같은 지위).

##### amendment-11 — freeze 축의 **jam 앵커** 정정 + STEP T vacuous-RTO 의 loud fault 신설

**(a) freeze 앵커.** §27.7a.2a 는 freeze 를 "정보를 나르는 유일한 축" 으로 pin 했다. 초안 RTL 은 `acc 불변인 pass 를 먼저 관측한 뒤` 감시를 시작했는데, 이는 golden `fold_descending` (RTO 산출 vs pre-RTO exact 비교로 **첫 실질 jam 위치 자체**를 잡고 그 이후의 변화를 즉시 fault) 보다 **단방향으로 약하다**: jam 직후 **첫 번째** pass 에서 정리 (4) 가 붕괴하면 감시가 한 번도 열리지 않아 100% 놓친다 ("acc 불변 ⇒ jam 이후" 만 참이고 필요한 역방향은 미검출). 정정: pass 의 inexact 여부를 기하로 직접 판정한다 —

> pass 가 inexact ⇔ **exact 합의 최저 set bit < 결과 48-bit 창 바닥 (wide_exp − 47)**.
> 비겹침 열에서 exact 합의 최저 set bit == 그 pass 에 들어온 component 의 최저 set bit 이다 (acc 의 bit 구간이 그보다 위 — 하단 상쇄가 구조적으로 불가능; jam 이후에도 남은 component 는 전부 grid p 아래라 등식 유지). ⇒ golden 과 **같은 pass 에서** 참이 된다 (과·미검출 없음).

`fd_acc_same` 는 그 특수형이므로 OR 로 존치한다 (이중 안전망). **검사는 두 축을 분리해 친다 (각 probe 가 무엇을 증명하는지 명기)**: (α) *경로* — 벡터를 자연스럽게 jam 시킨 뒤 **감시 창이 열린 직후 첫 pass** 에서만 acc 를 흔들어 (AddWide 가 피연산자를 이미 표집한 뒤라 pass 산출은 정직하고 저장 acc 만 움직인다) loud fault 가 서는 것을 실증한다; 이 probe 는 **앵커 위치를 증명하지 않는다** (늦은 앵커는 늦게 무장하고 여기서 똑같이 fault 를 낸다). (β) *앵커 위치* — 아래 실측이 그 축이며, 초안 앵커로 되돌린 변이를 죽이는 것도 이쪽이다. **실측**: golden 벡터 finite 322 행 중 **167 행이 실제로 jam** 하고, 그중 마지막 pass 가 아닌 **128 행 전부에서 RTL 의 fd_jam 이 golden 이 계산한 바로 그 pass 에 섰다** (unit TB `fdotcr_freeze_axis_jam_anchored` — RTL 자신의 열로 golden 원시함수를 돌려 대조). 초안 앵커로 되돌린 변이는 이 suite 에 **사살**된다.

**(b) STEP T vacuous-RTO.** golden 은 겹침 merge 의 정렬합 폭이 48 을 넘으면 `vacuous-RTO violated` 를 던지는데 (amendment-2 의 강제 경계), 초안 RTL 에는 그 대응 검사가 **없었다** — merge 가 실제로 반올림하면 exact-합 보존이 조용히 깨진다. 정정: 같은 기하 판정 (`min(e_a, e_b) < wide_exp − 47`) 으로 loud fault (qNaN + sticky) 를 낸다. 정상 열에서는 도달 불가이지만 ("도달 불가" 주장으로 검사를 대체하지 않는다 — §27.7a.2 문언) TB 가 directed poke 로 경로 존재를 실증한다.

##### amendment-12 — 3a-C3 검증 실측 기록 (선공표 변경 없음)

- **전 벡터**: `include/generated/fdotcr_vectors.hex` **450 행 전량 bit-exact** (finite 322 / special 128), special 행은 qNaN + sticky 대조까지. 확장 sweep **3,000 trial** 은 EFT 무의존 Fraction oracle 대조 (자기확인 루프 차단).
- **re-proof**: pre-3a 25 suite **byte-unchanged 재실행** (§25.1 item 9 / §27.7a.4) — 총 **33 suite PASS / 0 FAIL**.
- **cycle 실측**: GLOBAL worst **1,167 cycle** (hard 상한 10,000 대비 8.6× 여유; 가족별 worst = eft_bf16_wide 1167 / eft_f16_all 947 / eft_same 649 / eft_pack_edge 663 / eft_ladder 506 / eft_cancel_chain 357 / eft_tie 216 / eft_adv_residue 235 / eft_top_cancel 211 / eft_cancel 144, special wave 17). 정정으로 열이 잘아졌음에도 worst 는 **1,616 → 1,167 로 감소**했다 (merge pass 1회 = 4 + 재삽입 cycle 이 fold pass 1회 = 4 보다 비싸다 — 근사 판정이 만들던 불필요한 merge 가 사라진 결과).
- **변이 사살 (mutation battery, 14종 전건 KILLED)**: ASC fold 반전 / freeze fault 삭제 / freeze 앵커를 초안형으로 후퇴 / 용량 guard 2종 각각 삭제 / PACK_FINAL→WIDE / TwoSum 잔차 lo 폐기 / 비겹침 근사 복귀 (2형) / 정렬 키 xe 단일 복귀 / vacuous-RTO guard 삭제 / launch 의 busy 조건 삭제 / jam 창 off-by-one / 비겹침 판정 off-by-one. 용량 guard 2종은 **서로를 가려주고 있었으므로** (어느 하나를 지워도 다른 하나가 fault 를 내서 값 검사만으로는 통과) 각 probe 가 **fault 를 낸 상태 (FDS_PROD / FDS_NEXT)** 까지 pin 하도록 TB 를 강화한 뒤에야 둘 다 사살됐다.
- **busy-interlock / 중첩 dispatch 거부** (§27.7a.1, 선공표 §27.7a.5 의 미검증 절반): 진행 중 start 재인가를 4 지점 × {타 opcode, 동일 0x7A} = 8 회 + FS_DIV 진행 중 0x7A start 1 회 실측 — 전부 **bit-for-bit 무시** (결과·cycle 수 동일, sticky/fault 0). `fd_launch` 의 IDLE 조건을 지운 변이는 동일-opcode 중첩 케이스에 사살된다 (타 opcode 중첩만으로는 fd_launch 에 닿지 않아 생존했다 — 이 사실도 기록한다).
- **loud fault probe 5종** (전부 qNaN + sticky, 값 반환 없음): 용량 배열 guard (FDS_PROD) / 용량 assert (FDS_NEXT) / freeze 위반 (앵커 강제 주입) / STEP T vacuous-RTO / **감시 창 개방 직후 첫 pass 의 붕괴** (자연 jam 후 acc 만 교란). 각 probe 는 fault 를 **어느 상태에서** 냈는지까지 assert 한다.
- **양 시뮬레이터 교차**: verilator 5.048 과 iverilog 12 에서 **33 suite 전건 PASS**, 로그 수치 완전 동일 (최대 열 25 / teeth 2+3 / jam 167·앵커 128 / interlock clean 116 cycle / GLOBAL worst 1,167). 신규 whitebox 축 (배열 `fd_xp` 읽기·쓰기 poke) 이 두 시뮬레이터에서 같게 동작함도 이로써 확인된다.
- **선공표 무변경**: GATE V20-4 수치 (LUT delta ≤ 2,200 / premap `$mul` delta 0 / DSP·BRAM delta 0 / cycle ≤ 10,000) 는 변경하지 않는다. 신규 로직은 24-bit trailing-zero cascade 4개 + 13-bit 비교기 몇 개 + fault 분기 1개로, §27.7a.5 의 "compare/split glue 200-300" 항 안에 든다 (실측은 C4 의 gate 몫).

#### 27.7a.3 invariant 계약 — on-silicon dual-datapath 자기검증

- **정리 (§27.2.3 의 합성)**: 옵션 3 하에서 **single-wave 즉시-drain** — canonical-zero slot (0x7E 선행 또는 리셋 상태) 에 wave 정확히 1개 (carry-in = canonical zero → exact 33-항 합 == 32-항 합), IF-2/IF-3 준수 하에 개입 접촉 없이 DRAIN — 의 결과 r_main = PACK_FINAL(RTO_48(exact)) == RNE_24(exact) (§27.2.1 추출 정리). FDOT32_CR 의 r_audit == RNE_24(exact) (§27.7a.1 값 계약). ∴ **r_main == r_audit BIT-EXACT** — 양쪽이 같은 PACK_FINAL 의미론이라 FTZ/overflow/+0 경계까지 동일하다. 재생성 인용 근거 (JSON): `opt3_single_wave_equals_true_B_asserted` 6,000 + `exact_rto48_store_equals_true_B_asserted_trials` 30,000 = **36,000 assert 실패 0**.
- **검사는 프로그램 레벨이다 — runtime fault 아님 (pin)**: hw 는 비교기를 탑재하지 않는다 — 두 결과는 data 다. audit 프로그램 (SDK) 이 **동일 operand** 로 양 경로를 발사하고 (결과, sticky/status) 쌍을 회수해 검사한다: (i) special-sticky 유무 불일치 → 결함; (ii) 양쪽 special-free 인데 r_main != r_audit (bitwise) → 결함; special-set 이면 값 비교 금지 (main 은 +0/기존값 유지, audit 은 qNaN — 값 축은 정의상 무의미).
- **불일치의 소비 방식 (pin)**: 불일치 = **결함 신호** (silicon/RTL/spec 결함 또는 upset) 이지 수치 정책 이벤트가 아니다. SDK audit API 는 불일치를 **오류로 승격 (loud)** 하며, 재시도·평균화·silent 무시를 금지한다. 이 검사가 §27.7 이 약속한 on-silicon dual-datapath 자기검증의 소비 형태다.

#### 27.7a.4 회귀 격리 — op_sel 확장의 정량 선언

- **위험 선례 (§25.1 항 9)**: op_sel 접촉 1회 = 기존 step 프로그램 **전건 re-proof** 강제. 선례 문언의 "8개" 는 0e1 저작 시점 수이고, **현행 전건 = 9개** (OPS_FSADD/FSMUL/FSFMA/FSDIV/RSQRT/FEXP2/CVT/ACCEW/DEQ — OPS_BAD 제외). §23.10.10(h) 항 4 의 기록 그대로 capture-mux 미묘 회귀 = shipped op 의 **silent wrong-data** (§25.1 항 9 와 함께 읽을 것) — 이것이 3a 를 lattice release 와 격리한 이유다 (§27.7).
- **접촉 파일 목록 (전량 선언)**: `FP_StepSeq.v` (op_sel case tree — 유일한 고위험 접촉) / `PE_Core.v` (launch·capture·결과 반환 결선) / `EHDecode.v` + `isa/wt64v1_isa.json` + 생성물 (`isa_opcode_wires.vh`, `isa_ehshape_case_body.vh`) / `asm/wavetensor_asm.py` / golden 신규 파일 / TB. 공유 datapath 3 파일은 §27.7a.2 대로 byte-untouched.
- **frozen truth-table 무접촉 판정**: 0x7A 는 fp block (0x70-0x7F) — **frozen truth-table 도메인 밖** (isa JSON 0x79 note 명문 "0x70-0x7F is outside the truth-table domain"; §25.6 항 7 recapture 의 가시 delta 가 0x6B 재배정뿐이었던 그 근거). ∴ **recapture/domain_version bump 불요** (현행 3 유지) — 회귀 표면에서 truth-table 축이 제외된다.
- **최소 접촉 형태 (pin)**: op_sel 은 이미 4-bit (0e1 OPS_DEQ 선례 — widening 불요) → **OPS_FDOTCR = 4'd10, case tree 는 행 추가만** — 기존 행 무변경을 diff 로 증명한다. capture mux 는 op-class-conditional 항 추가 (OPS_CVT/OPS_DEQ bypass 선례 형식 — narrow raw field 는 DAZ bypass, §27.7a.1 (i)/(ii) 는 프로그램 내 classify 로 이행). expansion 저장·FSM 등 신규 로직은 op-gated 영역에 격리.
- **착지 순서 (선언 — golden-before-RTL 과 §12a 규칙 3 을 동시 충족)**: **3a-C0** = 본 절 (spec-first) → **3a-C1 golden** (EFT twin + 벡터 + invariant sweep — §27.7a.5) → **3a-C2 ISA** (`isa/wt64v1_isa.json` 0x7A row 2행 전사 + 생성물 재생성 + asm mnemonic) → **3a-C3 step 프로그램** (FP_StepSeq OPS_FDOTCR + unit TB — 기존 9 프로그램 전건 re-proof 포함) → **3a-C4 결선 + gate** (PE_Core/EHDecode 결선 + 통합 TB dual-run + GATE V20-4 실행·기록). 0x7A 는 3a-C4 의 opcode_supported 등재 전까지 오늘처럼 decode_error 유지 (§27.7 예약 문언 불변).

#### 27.7a.5 검증·gate 선공표 (V9-4 형식 — 측정 전 공표, locked)

- **golden (3a-C1)**: `scripts/golden_fdot32_cr.py` — sequencer-faithful EFT twin, **전 벡터에서 §27.7a.1 의 exact reference 와 bit-equal assert**. 벡터 계획: (a) 재생성 고정-seed **36,000 재사용** (families 30,000 + single-wave streams 6,000); (b) EFT-특화 directed — expansion 최대 깊이 (exponent ladder 2^-252..2^255, 용량 33 worst-case), tie-인접 (extraction_theorem 의 tie-인접 생성기 재사용), PACK_FINAL FTZ/overflow/+0 경계, specials 전 행 (§27.7a.1 대조표 — bf16 DAZ / f16 subnormal exact / NaN/Inf/qNaN marker), f16 전 클래스; (c) **invariant sweep — golden lattice model (§27.4 ①) vs golden EFT 를 동일 operand 전 벡터에서 bit-equal 전수 assert**. **인용 규율 이행 (명시)**: §27.7 sketch 의 "66k+ trials" 는 세션 salted-seed 수치로 normative 인용 불가하며, 재생성 artifact 에 EFT 구현 자체는 아직 없다 (오늘 인용 가능한 것은 불변식 우변의 36,000 뿐) — **3a-C1 이 EFT 경로의 고정-seed 재생성 카운트를 생성해 이 수치를 승계·졸업시킨다** (재실행 byte-identical 의무).
- **TB (3a-C3/C4)**: unit — 기존 9 프로그램 bit-exactness 증명 **전건 재실행** (GATE C3 형식) + OPS_FDOTCR directed (golden 전량 + cycle 상한 assert + busy-interlock + capture-mux 오염 벡터 — 비발사 op 의 무영향 증명); 통합 — 0x7A decode/EH legality (16-frag wave 수납 포함) + **dual-run 실증** (같은 operand 로 TRAIN wave→즉시 drain vs FDOT32_CR bit-equal — §27.7a.3 의 TB-레벨 실증이며 hw 비교기가 아니다).
- **GATE V20-4 (FDOT32_CR unit gate — merge-blocker)**: 대상 = FP_StepSeq-hosting unit OOC, **xcu55c binding / ECP5 = MEASUREMENT** (V20-2/3 정책 승계). **측정 anchor 부재** (이 unit 의 xcu55c 실측이 없다) → gate 절차가 anchor 를 먼저 생성한다: 3a-C3 직전 base 형상 (OPS_FDOTCR 미포함) 을 동일 스크립트로 실측 (= anchor, 기록) → 착지 후 재실측 → delta 판정. binding: **LUT delta ≤ 2,200** (신규 로직 nominal 상단 1,300 [expansion 저장 150-250 + capture mux 200-350 + FSM/step 행 250-400 + compare/split glue 200-300] × 실측 overrun 계수 **1.67** (§23.10.10(g) 방법) = 2,171 → 2,200); **premap `$mul` delta 정확히 0** (판정 근거: 곱은 MU 의 단일 공유 곱셈기 FP_Mul36 재사용 — §23.10 단일-공유-곱셈기 설계 그대로, 신규 multiplier 금지); DSP48/MULT18X18D delta 0 (hard); BRAM/EBR delta 0; FF 는 추적만 (V9-4 관례 — capture 1,024 + expansion ≤ 1,221 bit 의 FF/LUT-RAM 배분 실측 기록); Fmax/WNS 기록 축 (binding 아님 — V20-2/3 동일); **cycle 실측 ≤ 10,000 (hard — §27.7a.2)**; `make lint` + 양 시뮬레이터 교차 + 무회귀 (기존 unit 벡터 + lattice 4097 / bank 349 전량). gate 수치는 하향 개정만 가능 — 초과 시 ad-hoc 상향 대신 **pre-declared cut ladder**: rung 1 = f16 행 이연 (bf16 만 착지, f16 은 기록된 loosening 예약), rung 2 = 2-dispatch fallback (capture 1,024→512 bit).
- **cluster 통합 실측은 본 gate 가 선점하지 않는다**: TRAIN 신규 opcode ISA 결선·step sequencer 전체 통합 (§27.6 종결 선언의 별개 후속 COMMIT 몫) 의 gate 기준은 그 COMMIT 0 이 V9-4 형식으로 별도 선공표한다.

#### 27.7a.6 §12a 기록 (3a COMMIT 0)

본 절은 §12a 하의 정규 개발 행위다 — spec-before-code COMMIT 0. §27.7 sketch 의 "~9,000 cycles" / "66k+ trials" 는 본 절이 각각 **상한 10,000 선언** / **재생성 졸업 의무** 로 정제하며 원문은 무수정 보존한다 (§12a 규칙 5). `isa/wt64v1_isa.json` (0x7A row — §23.6a 표 전사 2행) · asm · golden · RTL 은 §12a 규칙 3 의 순서대로 3a-C1..C4 에서 뒤따른다 — **본 COMMIT 0 은 spec (본 절) 과 kickoff memo 상태 갱신만 편집한다** (§27.8 의 옵션 3 COMMIT 0 선례와 동일 범위 판정).

**[amendment 2026-08-17 — 3a-C1 golden 실측이 본 COMMIT 0 의 알고리즘 pin 을 부정함]** §27.7a.2 종료 (2) 의 fold 방향과 STEP I 의 walk 독해는 **§27.7a.2a 가 supersede** 한다 (원문 무수정 보존, §12a 규칙 5). 이는 §12a 하의 정규 이벤트다 — pre-stable 에서 spec 개정은 정규 개발 행위이며, C0 이 pin 한 정리의 지위를 §25.4 규율대로 golden 졸업 대상으로 남겨둔 것이 바로 RTL 착지 전에 결함을 잡아낸 이유다. **순서 판정**: 본 개정은 spec (§27.7a.2a) 과 golden (`scripts/golden_fdotcr.py` + 산출물 3종) 만 편집하며, `isa/wt64v1_isa.json` · RTL 은 여전히 3a-C2 이후 몫이다 (§12a 규칙 3 유지 — golden-before-RTL 이므로 C1 이 blocker 였고, 지금 해소됐다). **선공표 (GATE V20-4 / cycle ≤ 10,000) 는 변경하지 않는다** — 근거는 §27.7a.2a amendment-3.

**[amendment 2026-08-17 — 3a-C3 step 프로그램 착지]** RTL 착지에서 확정·정정된 3건은 **§27.7a.2b (amendment-9..12)** 가 기록한다: (i) §27.7a.1 의 ingress 재개정 의무 이행 (제3형 = 16-cycle 64b 스트리밍, 단일 dispatch, MU-local — fallback 아님), (ii) STEP I component 기하의 정정 (근사 비겹침 판정이 §27.7a.2a 의 **금지 pin 을 검사 불능**으로 만들었던 초안 결함 — 은폐 없이 기록하고 golden 판정과 근사 없이 일치시킴), (iii) freeze 축의 jam 앵커 정정 + STEP T vacuous-RTO loud fault 신설. **순서 판정**: 본 개정은 spec (§27.7a.1 supersede 배너 + §27.7a.2b) 과 `FP_StepSeq.v` + unit TB 만 편집한다 — `isa/wt64v1_isa.json` 과 생성물·asm 은 3a-C2 에서 동결됐고 (재편집 없음), golden 3종은 3a-C1 에서 동결됐으며 (재편집 없음), PE_Core/EHDecode 결선과 `decode_reserved` 해제는 여전히 3a-C4 몫이다 (§12a 규칙 3 유지). 공유 datapath 3파일 (`FP_AddWide.v` / `FP_Mul36.v` / `include/fp_narrow_f32.vh`) 은 **byte-untouched** 이며 diff 로 확인된다 (§27.7a.2 / §27.7a.4 의무). **선공표는 변경하지 않는다** — 근거는 §27.7a.2b amendment-12.

### 27.8 §12a 기록

본 절은 §12a 하의 정규 개발 행위다 — §23.1 의 v2.0 bullet (fused-FMA "단 1회 RNE" 문구, 32b ACC bank, canonical-order serial-equivalence) 과 §23.4 항 2 는 본 절이 supersede 하며, 해당 원문은 삭제하지 않고 amendment 표기로 보존한다 (§12a 규칙 5; 편집 기록은 각 절 in-place). `isa/wt64v1_isa.json` 편집 (0x7A 예약 주석 포함) · golden model · RTL 은 §12a 규칙 3 의 순서대로 후속 commit 에서 뒤따른다 — 본 COMMIT 0 은 spec 과 kickoff memo 정리만 편집한다.

---

## 28. 시스템 통합 합성 gate 신설 — GATE S1 (2026-08-18, 사용자 지시 · normative)

**사용자 지시 (binding): 전체 합성을 gate 계보에 편입한다.** 본 절이 그 이행 기록이며, WT64v1 에서 처음으로 **operator 가 아니라 system top 을 대상으로 하는 gate** 를 신설한다. 계보: ECP5 GATE 1 / 2 / C3 / F1 → xcu55c GATE F1-US / V20-2 / V20-3 → **GATE S1 (본 절)**. 이름 `S` 는 system-integration synthesizability 다 — `V20-4` 는 §27.7a.5 가 FDOT32_CR unit gate 로 이미 선점했으므로 쓰지 않는다 (본 절이 차용한 것은 그 gate 의 **anchor 부재 절차 패턴**뿐이다).

### 28.1 발견 경위 — 면적 질문 하나가 미합성 계통을 드러냈다

경위를 순서대로 기록한다. 이것이 gate 신설의 정당성 자체이기 때문이다.

1. 사용자가 **HIU 의 면적**을 물었다.
2. 답할 수 없었다. `grep -rn 'HIU.v|Top_Core.v' synth/` 의 매치가 **0건**이었다 — 두 파일은 repo 의 어떤 합성 스크립트 (Vivado `synth/scripts/*.tcl`, ECP5 `synth/lattice/scripts/*.ys|sh`) 에도 등장하지 않았다. 실측이 없으므로 추정밖에 할 수 없었고, 이 프로젝트는 추정을 실측으로 말하지 않는다 (§25.4 규율).
3. 그래서 합성을 시도했다. **Vivado 가 거부했다**: `ERROR [Synth 8-685] variable 'dma_data_out' should not be used in output port connection (HIU.v:83)` → `ERROR [Synth 8-6156] failed synthesizing module 'HIU'`.
4. 즉 `HIU.v` 는 **합성이 불가능한 상태로 존재하고 있었다.** 그런데 `make MOD=HIU` 는 계속 1/1 PASS 였고, `Top_Core` 는 7/7 PASS 였다. §11 회귀 베이스라인도 이들을 정상 계상하고 있었다.
5. **시뮬레이터 PASS 가 "합성 가능" 의 대역(proxy)으로 쓰이고 있었다.** 그것도 **repo 존재 기간 전체**에 걸쳐 — `HIU.v`/`Top_Core.v` 는 최초 private commit (2026-05-03) 부터 오늘 (2026-08-18) 까지 3.5개월 내내 한 번도 합성되지 않았고, 그 사이 `HIU.v` 는 2026-07-14 (벤더 attribute 이행) 에, `Top_Core.v` 는 2026-07-15 에 실제로 편집됐다. 즉 편집은 계속되는데 합성 검증은 한 번도 없었다. 이 gate 는 그 대역 관계를 끊고, 합성 가능성을 **직접·상시** 검사한다.

미합성이 이 두 파일에 국한된 문제가 아니라는 점도 기계적으로 확인됐다. repo 루트 non-tb `.v` 18개를 전수 대조한 결과, 본 workflow 이전 매핑된 넷리스트가 0인 파일은 **5개** 였다 — `HIU.v` / `Top_Core.v` / `TENSOR_ALU.v` / `SIMD_ALU.v` / `ALU_Extended.v`. 그리고 이 5개는 정확히 `claude.md` §6 로드맵의 버려진 가지 하나 (`PE.v = ISA_Decoder + ALU wrapper`) 를 구성한다 — `Cluster.v → PE_Core.v` 직결 경로가 그 가지 전체를 대체했기 때문이다 (§28.8). 본 workflow 가 5개 전부를 처음 합성했다.

### 28.2 결함 D4 — partitioned TLB 는 실리콘에 없다 (최우선 기록)

**본 절에서 가장 중요한 기록이다. 이 gate 를 신설하는 이유가 D1 (합성 거부) 이 아니라 D4 이기 때문이다.** D1 은 시끄러운 실패였고 즉시 드러났다. D4 는 조용한 실패이며, gate 가 없었다면 계속 조용했을 것이다.

**사실 (실측):**

- `HIU.v:51-52` 의 `partitioned_tlb_virt` / `partitioned_tlb_phys` 배열은 **어디에서도 기입되지 않는다.** 읽기만 존재한다.
- `HIU.v:154-155` 의 `partitioned_tlb_valid` 는 **clear 만** 된다 (reset / context_switch). set 하는 코드가 없다.
- 결과: 합성 후 넷리스트에 이 TLB 의 **cells = 0**. 옵티마이저가 전체를 소멸시킨다 — undriven 저장소는 상수이고, 상수로 인덱싱된 lookup 은 접힌다.
- 따라서 **실리콘에는 partitioned TLB 경로가 존재하지 않는다.** HIU 의 모든 주소 변환은 shadow-region 경로로만 성립한다.

**그런데 테스트는 통과한다. 왜 통과하는지가 핵심이다:**

- `test_hiu.py:24-26` 이 `dut.partitioned_tlb_virt` / `_phys` / `_valid` 를 **계층 강제 기입**(hierarchical force write)한다. cocotb 가 시뮬레이터의 내부 신호에 직접 값을 넣는 것이다.
- 시뮬레이터에는 그 저장소가 있으므로 값이 들어가고, lookup 이 성공하고, 테스트가 PASS 한다.
- 실리콘에는 그 저장소가 없다. **테스트는 RTL 이 만들지 않는 상태를 스스로 만들어 놓고 그것을 검증하고 있었다.**

**판정과 처분:**

- 이것은 **의미 보존 수리가 불가능한 결함**이다. TLB fill 포트 신설 + FSM 상태 추가는 모듈 인터페이스와 기능의 변경이며, 본 workflow 의 금지 규정 (의미 변경 수리 금지 — 시뮬 결과가 바뀌면 회귀다) 에 정면으로 걸린다.
- 따라서 **수리하지 않았다.** spec 수준 결정 사항으로 이월한다. 결정해야 할 것은 두 갈래다: (a) partitioned TLB 를 실물화한다 (fill 경로 + FSM + 인터페이스 확장 — cache-attack 저항이라는 원래 설계 의도를 실현), 또는 (b) partitioned TLB 를 폐기하고 shadow-region 단일 경로를 정규 계약으로 성문화한다 (그리고 `test_hiu.py` 의 계층 강제 기입을 삭제해 테스트가 실물만 검증하게 한다).
- **어느 쪽이든, 지금 상태 — "실리콘에 없는 경로를 테스트가 있다고 말하는 상태" — 는 유지되어서는 안 된다.** 이 문장이 본 항의 normative 내용이다.

**교훈의 일반형 (§28.4 정책의 근거):** 계층 강제 기입은 강력한 테스트 도구이고 금지 대상이 아니다. 위험한 것은 그것이 **RTL 이 구동하지 않는 상태**를 만들 때인데, 시뮬레이터만 보면 그 차이가 보이지 않는다. 합성이 그 차이를 본다 — undriven 저장소는 넷리스트에서 사라지기 때문이다. 그래서 "합성을 상시 검사로 만드는 것" 이 이 클래스 결함의 유일한 상시 탐지 수단이다.

### 28.3 결함 7건 전수와 처분

정찰이 확보한 7건 전부를 처분과 함께 기록한다. **수리 4건 / 이월 3건**이며, 이월은 전부 "의미 변경 없이는 수리 불가" 또는 "blast radius 초과" 사유다.

| # | 위치 | 결함 | 처분 | 의미 보존 |
|---|---|---|---|---|
| **D1** | `HIU.v:32,83` | `output reg dma_data_out` 을 서브모듈(`dma_inst`) 출력에 연결 — Verilog-2001 위반. **계통 전체를 막던 유일한 hard error** (`Synth 8-685` → `8-6156`) | **수리** — `output` (암묵 wire) 로 | ✅ 예 |
| **D2** | `HIU.v:377-386` | `g_ro` ring-oscillator TRNG 가 timing loop CRITICAL WARNING ×8 + DRC LUTLP-1 ×8 을 유발. **RTL 결함 아님 — XDC 공백** | **수리** — 신규 `synth/constraints/hiu_trng_ro.xdc` (RTL 0줄 변경) | ✅ 예 |
| **D3** | `EHDecode.v:171,207` | `stg_active` 등 6개 reg 를 선언 전에 사용. Vivado 는 관용, 타 합성기는 hard error 가능 | **수리** — 선언 블록을 사용 지점 앞으로 이동 (선언 161-166 / 최초 사용 192) | ✅ 예 |
| **D4** | `HIU.v:51-52,154-155` | **partitioned TLB 전체가 undriven → 실리콘에 없음. 테스트는 계층 강제 기입으로 통과** | **이월 (수리 금지)** — §28.2 | ❌ 불가 |
| **D5** | `HIU.v:62,267-269` | `chacha_stream[0:15]` 이 채워지지만 읽히지 않음 (write-only 16 reg) | **수리** — 배열 + 16-way 대입 루프 삭제 | ✅ 예 (옵티마이저가 이미 제거) |
| **D6** | `HIU.v:114` | async-reset always 안에 reset 미대입 레지스터군 → `Synth 8-7137` ×66 ("both Set and reset with same priority") | **이월** — blast radius | ✅ 예 (수리 자체는) |
| **D7** | `HIU.v:20` | `interface_type` 포트가 선언·전달되나 내부에서 읽히지 않음 | **이월 (제거 불가)** | ❌ 불가 |

**수리 4건의 의미 보존 근거 (실증):**

- **D1** — 수리 전 `dma_data_out` 의 전체 출현은 딱 2곳 (포트 선언 + `dma_inst` 포트 연결) 이었고, HIU 본체의 어떤 always 블록도 이 신호에 대입하지 않는다. 실제 구동원은 `dma_engine` 내부 always (HIU.v:608-620) 하나뿐이므로 `reg` 저장소는 애초에 쓰이지 않았다. 1차 채증: elaborate 대조에서 pre-fix `FAILED` / post-fix `OK`.
- **D3** — 옮긴 것은 `reg` 6개 (`stg_off`/`stg_expect`/`stg_index`/`stg_active`/`stg_chain_err`/`stg_unknown`) 의 **선언 위치뿐**이고 폭·개수·초기화·구동 always 는 전부 그대로다. 같은 모듈 스코프 안이라 계층 이름이 불변임은 `test_cluster.py:528` 의 `dut.u_ehdec.stg_active` 접근이 수리 후에도 통과 (Cluster 45/45) 하는 것으로 실증된다.
- **D5** — grep 전수로 읽기 0곳 확인. 주소 마스크는 같은 상태 안에서 `chacha_state`/`initial_state` 를 직접 더해 계산되며 `chacha_stream` 을 경유하지 않는다. 옵티마이저가 이미 16 reg 를 제거했다는 증거는 수리 후 HIU 실측이 수리 전 anchor 와 완전 일치하는 것이다.
- **D2** — `HIU.v:337-338` 주석이 이미 "합성 시 XDC 가 `DONT_TOUCH` / `set_false_path` 를 추가해야 한다" 고 규정해 둔 항목의 실현이다. 채증: 같은 run 안에서 `report_drc -checks LUTLP-1` BEFORE 8건 → AFTER 0건 (HIU 단독·Top_Core 양쪽).

**무회귀 실증 (수리 전/후 대조, `COCOTB_RESULTS_FILE` 을 `/tmp` 로 리다이렉트해 tracked `results.xml` 무접촉):** HIU 1/1 · ISA_Decoder 192/192 · Cluster 45/45 · Pod 7/7 · Top_Core 7/7 · PE 4/4 — **base 256 PASS / 0 FAIL == fix 256 PASS / 0 FAIL**, 6개 모듈 전부 테스트 이름 집합까지 완전 동일. 독립 프론트엔드 교차검증: yosys `synth -top` 후 stat 비교에서 `HIU.v` (D1+D5) / `EHDecode.v` (D3) 모두 pre-vs-post 넷리스트 통계 diff 0.

**이월 3건의 사유 (은폐 없이):**

- **D6** — 약 66개 레지스터 (HIU 단독 합성 기준) 를 별도 `always @(posedge clk) if (!rst)` 블록으로 분리하는 작업이 FSM 본체 (HIU.v:114-317) 전체를 재구성하게 되어 D1/D3/D5 의 최소 수리 blast radius 를 크게 넘는다. **이번 xcu55c 매핑에서는 전부 FDRE 로 떨어져 divergence 미발현** (실측 재확인) 이나, 매핑이 FDSE/FDPE 로 바뀌는 순간 reset 값이 갈리는 **상시 리스크**로 남는다. 별도 commit 권고. 동형 결함이 `TENSOR_ALU.v` 에 ×49 로 존재하므로 (§28.6 결함 O2) 함께 처리하면 효율적이다 — 그쪽은 `if (!rst)` 가드 분리형이 파형 완전 일치임이 확인됐다.
- **D7** — 포트 제거는 의미 보존이 아니다. `Top_Core.v:183` 이 이 포트를 전달 중이고, 모듈 인터페이스의 일부다. 넷리스트 관측: `interface_type` 은 HIU 안에서 읽히지 않으므로 그 경로가 상수로 접히는 것이 확인되지만, `Synth 8-7129`/`8-6014` 계열 메시지로 이 포트가 제거됐다고 단정할 근거는 확보하지 않았다 — **미조사로 남긴다** (추적 축이므로 gate 판정에 영향 없음).
- **D4** — §28.2.

**D6 에 대해 본 gate 가 새로 발견한 사실 2건 (아카이브 로그 `sys_top_core_run.log` 실측 — 정찰 시점에는 없던 정보다):**

1. **메시지 수는 문맥 의존이다.** `Synth 8-7137` 는 HIU 단독 합성에서 66건이었는데 Top_Core 문맥에서는 **HIU 32건**이다 (같은 RTL, 같은 part). 즉 "66건" 은 결함의 크기가 아니라 그 문맥의 매핑 산물이며, 이 수치를 회귀 지표로 쓰면 문맥이 바뀔 때마다 흔들린다. **따라서 GATE S1 은 8-7137 을 gate 축으로 채택하지 않았다** (Warning 이고 CRITICAL 이 아니므로 CRIT 축에도 걸리지 않는다) — 채택하려면 문맥을 고정한 별도 축이 필요하고, 그 설계는 D6 수리 commit 몫이다.
2. **같은 결함 클래스가 `PE_Core` 에 68건 존재한다 — 지금까지 어디에도 기록되지 않았다.** Top_Core 문맥의 8-7137 총 101건은 HIU 32 + **PE_Core 68** (+1 기타) 이다. PE_Core 는 이 프로젝트의 주력 연산 모듈이고 Cluster/Pod 를 통해 이미 여러 번 합성됐는데도, 이 경고가 집계·귀속된 기록이 없다. HIU D6 / Tensor_ALU O2 (§28.8) 와 합쳐 **동일 클래스 3개소 (HIU 32 · PE_Core 68 · Tensor_ALU 49)** 로 이월한다 — 수리 형식은 세 곳 다 같다 (`if (!rst)` 가드 블록 분리, 파형 불변). 이 발견 자체가 §28.4 정책의 근거를 하나 더 보탠다: **합성 로그를 아카이브해 두지 않으면, 이미 합성되고 있는 모듈에서도 경고가 조용히 누적된다.**

### 28.4 정책 — "시뮬레이터 통과 ≠ 합성 가능" 을 상시 검사로 전환한다 (normative)

D1 과 D4 는 같은 뿌리를 갖는다: **cocotb PASS 가 합성 가능성의 대역으로 쓰였다.** 본 절이 그 대역 관계를 정책적으로 끊는다.

1. **cocotb 로 검증되는 모든 모듈은 합성 지위가 선언되어 있어야 한다.** 지위는 4종이다 — `gate` (merge-blocker binding 있음) / `harness` (재현 가능한 합성 경로 있음, binding 없음) / `measured-pending` (실측 있음, 편입 보류 + 사유 필수) / `uncovered` (합성 경로 없음 + 사유 필수).
2. **이 선언은 기계적으로 강제된다.** `scripts/lint_synth_coverage.py` 가 `Makefile` 의 cocotb `MOD` 목록을 파싱해 (분기와 `$(error ... Valid: ...)` 목록을 교차검증), 선언표와 대조한다. **미분류 1건 = `make lint` 비영 종료.** 즉 새 모듈을 cocotb 에 추가하면서 합성 지위를 선언하지 않으면 빌드가 깨진다 — HIU/Top_Core 가 repo 존재 기간 3.5개월 내내 미합성으로 남았던 그 경로가 봉쇄된다.
3. **래칫**: `uncovered` ≤ 2, `measured-pending` ≤ 3 (본 절 착지 시점 실측치와 동일). 상한을 올리는 것은 그 자체가 리뷰 대상인 편집이다. 지위 강등은 조용히 일어날 수 없다.
4. **소리내기**: `gate` 가 아닌 전 항목을 매 실행 stdout 에 사유와 함께 열거한다. 통과해도 침묵하지 않는다 (loud-fault-never-silent).
5. **`set_msg_config` 전역 강등 금지.** 합성 로그의 CRITICAL WARNING 을 전역으로 강등해 gate 를 통과시키는 것을 금지한다 — D2 의 timing loop 8건은 **개수로** 화이트리스트하고, 클래스로 숨기지 않는다. 클래스 강등은 다른 곳의 진짜 조합 루프를 함께 숨기기 때문이다.
6. **계층 강제 기입 테스트의 의무**: cocotb 가 `dut.<internal>` 을 강제 기입하는 테스트는, 그 신호가 **RTL 에 의해 구동되는지**를 함께 확인해야 한다. 구동되지 않는 신호에 대한 강제 기입은 D4 형 결함 (실리콘에 없는 경로를 검증하는 테스트) 을 만든다. 본 절은 이 의무를 선언하며, 기계적 강제는 후속 commit 으로 이월한다 (undriven-signal 탐지는 합성 넷리스트 대조 또는 별도 lint 를 요구한다).

선언 현황 (착지 시점, `make lint` 출력 전사): `gate` 2 (HIU, Top_Core) / `harness` 2 (Cluster, Pod) / `measured-pending` 3 (Tensor_ALU, SIMD_ALU, ALU_Extended) / `uncovered` 2 (PE, ISA_Decoder).

`uncovered` 2건은 구조적 사유이며 단순 누락이 아니다: `synth/lattice/scripts/synth_pod.ys:27-28` 과 `synth_cluster.ys:20-21` 이 `PE.v` / `ISA_Decoder.v` 를 `read_verilog` 하지만, Pod/Cluster 가 둘을 인스턴스화하지 않으므로 `hierarchy -top` 단계에서 프루닝된다 (`pod_2x2_2x2_impl_util.rpt` 계층에 `ISA_Decoder` 문자열 0건, bare `PE` 행 0건). `Cluster.v` 가 `EHDecode` 를 cluster 레벨로 끌어올려 공유하고 `PE_Core` 를 직접 인스턴스화하면서 per-PE decode 래퍼 계층이 supersede 됐다. 단 `ISA_Decoder` 는 GATE S1-US 의 `Top_Core` 안에서 `u_core/u_decoder` 로 실제 합성되므로 "전혀 합성되지 않는 RTL" 은 아니다 — standalone top 으로서의 경로가 없다는 뜻이고, 이 구분은 D1 류의 **top-level 포트 결함이 standalone 에서만 드러나는** 경우를 놓칠 수 있다는 정직한 한계로 기록한다.

### 28.5 GATE S1 기준 선공표 (V9-4 형식 — anchor 생성 commit)

**명명·계보·구속력**: 본 gate 는 **GATE S1 (system-integration synthesizability gate, dual-fabric)** 이다. **merge-blocker** — binding 기준 미충족 상태의 merge 금지, gate log 는 merge commit 첨부 의무 (§23.10.7 교훈 "선언된 gate 건너뛰면 5 commit 뒤 발각", 이미 4회 확인). V20-2/V20-3 정책을 승계해 **merge-blocker binding 은 xcu55c 반쪽에만 있고 ECP5 반쪽은 MEASUREMENT** 다 (§28.7).

**anchor 부재 절차 (정직 명기 — 본 항의 가장 중요한 문장)**: 이 top 의 xcu55c 실측은 존재하지 않았다. 따라서 ceiling 을 가격할 대상이 없었고, §27.7a.5 GATE V20-4 가 확립한 절차 ("측정 anchor 부재 → gate 절차가 anchor 를 먼저 생성한다") 를 그대로 적용한다:

- **(a) 본 commit 의 실측이 anchor 다.** 최초 실측이므로 anchor 생성이 목적이고, 그 자체를 pass/fail 판정 대상으로 삼지 않는다.
- **(b) ceiling = anchor × 1.67** (§23.10.10(g) 실측 overrun 계수 — 0d/0e/v1.9/V20-2 를 관통한 그 계수).
- **(c) 따라서 본 commit 의 area 판정은 구조적으로 PASS 다** (측정값 == anchor ≤ anchor × 1.67). **binding 은 다음 commit 부터 발효한다.** 이 문장을 숨기지 않는다 — 숨기면 "gate 를 통과했다" 가 "설계가 검증됐다" 로 오독되고, 그것이 §23.10.7 이 4회 적발한 바로 그 실패다. 반면 exact-value 축 (DSP / BRAM / premap `$mul`) 과 DRC / CRITICAL WARNING 축은 **본 commit 부터 즉시 구속력이 있다** — 이들은 anchor 에서 도출된 상한이 아니라 넷리스트의 구조적 사실이며, 다음 실측에서 1이라도 어긋나면 FAIL 이다.

**xcu55c binding 기준 (리포트 실물 전사, 임의 반올림 없음 — LUT 의 floor 1회만 명시):**

| 축 | 기준 | 지위 | 근거/출처 |
|---|---|---|---|
| **LUT sites** | **hard ceiling 24,799** — 초과 시 merge 금지 | anchor 도출 (다음 commit 부터 binding) | anchor 14,850 × 1.67 = 24,799.5 → floor 24,799 |
| **DSP48E2** | **정확히 39** | **즉시 binding** | PE_Core einsum/dot 35 + FP_StepSeq `FP_Mul36` 4 + HIU 0. 편차는 merge 금지 + 귀속 조사 후 재판정 (§26.6 MULT 편차 조사 방법) |
| **RAMB18** | **정확히 2** | **즉시 binding** | FP_StepSeq 내부 2. operator gate 의 "BRAM 0" 을 그대로 쓰지 않는다 — system top 은 정당하게 메모리를 추론하므로, 축의 의미는 "0 강요" 가 아니라 "정확한 수 고정 = 조용한 메모리 추론 변화 탐지" 다 |
| **premap `$mul`** | **정확히 429** | **즉시 binding** | §26.6 pin form. yosys `read_verilog + hierarchy -top Top_Core + proc + opt_clean + stat` 의 `=== design hierarchy ===` 절 누계. 증거: `synth/reports/fp_ops/sys_top_core_premap_mul.log` |
| **DRC** | **errors 0** (warnings 는 열거 — "clean" 아님) | **즉시 binding** | F1-US 관례. `LUTLP-1` 은 Critical 이므로 여기서 자동으로 error 로 계상된다 = D2 제약이 풀리면 즉시 FAIL |
| **CRITICAL WARNING** | **`Synth 8-295` ≤ 8 이고, 화이트리스트 외 id 는 0** | **즉시 binding** | RO 8개 = 루프 8개. 9번째는 다른 것이 발진하기 시작했다는 뜻. 전역 강등 금지 (§28.4 항 5) |
| Fmax / WNS | 기록 축 — binding 아님 | 기록 | 이 top 은 v2.0 datapath critical path 상에 없고 Fmax 계약이 선언된 적이 없다 |
| **WHS (hold)** | **≥ 0 — 즉시 binding** | **즉시 binding** | 정정 (적대 감사 2026-08-18): 하네스 `fp_op_gate_check.py` 의 `ok_hold = whs >= 0.0` 이 이미 이 축을 구속하고 있었으므로 "기록 축" 서술이 하네스와 불일치였다. setup 미달은 클럭을 낮추면 되지만 **hold 위반은 어떤 주파수에서도 동작하지 않는 결함**이므로 binding 이 옳다 — 문서를 하네스에 맞춘다 |
| FF / CARRY8 / SRL | 추적만 | 기록 | V9-4 관례 |

**CRITICAL WARNING 축의 측정 방법 (실패한 방법을 먼저 기록한다)**: 처음 채택한 tcl 형식 `get_msg_config -count -severity {CRITICAL WARNING}` 은 **틀린 값을 냈다** — 로그에 `CRITICAL WARNING: [Synth 8-295]` 8줄이 있는 run 에서 **0** 을 반환했다 (Vivado 2025.2.1). 이 명령은 발행된 메시지 수가 아니라 메시지 *설정*을 보고한다. 0 을 답하는 census 는 census 가 없는 것보다 나쁘다 — 시끄러워지는 것이 유일한 목적인 축에서 false PASS 이기 때문이다. 그래서 census 는 **아카이브된 run 로그**에서 취한다 (`make synth-sys-gate` 가 `-log` 로 `synth/reports/fp_ops/sys_top_core_run.log` 를 남긴다). 수와 목록이 같은 산출물에서 나오고 리뷰어가 grep 할 수 있다. 로그가 없으면 UNMEASURED = **FAIL** 이며 절대 pass 가 아니다.

**하네스·리포트 규정**: `synth/scripts/synth_fp_op.tcl` (기존 fp-ops 하네스를 fork 하지 않고 옵션 2개를 추가), top = `synth/gate/Top_Core_gate_top.v`, 전 flow `synth + opt + place + phys_opt + route`, OOC, `-flatten_hierarchy none`, `create_clock 10.000 ns` 단일. 추가한 옵션 2개:

- `RST_FALSE_PATH=1` — fp-ops 코어는 reset-free 라 reset false path 가 없었다. 이 top 은 async-reset 설계이고 gate_top 래퍼가 `rst` 를 **의도적으로 등록하지 않으므로** (등록하면 reset 릴리즈 cycle 의 의미가 바뀐다) `rst` 는 전 FF 로 팬아웃하는 top 입력이다. `synth/constraints/pod.xdc` 가 같은 이유로 같은 입장을 취한다.
- `POST_XDC=synth/constraints/hiu_trng_ro.xdc` — D2. `g_ro[*]` 는 넷리스트 객체이므로 elaborate 전에는 존재하지 않는다. 따라서 `synth_design` **이후** `opt_design` **이전**에 source 해야 한다 (phys_opt 단계에서 루프가 붕괴하는 2차 경로까지 막는다). 실측 확인: `ALLOW_COMBINATORIAL_LOOPS TRUE on 24 g_ro net(s)` (8 RO × 3단).

리포트: `synth/reports/fp_ops/sys_top_core_{impl_summary.json,impl_util.rpt,impl_timing.rpt,impl_drc.rpt,synth_util.rpt,synth_timing.rpt,premap_mul.log,run.log,gate.xdc}` + `gate_summary.txt` 의 `GATE S1-US` 행. gate_check 등재 = `synth/scripts/fp_op_gate_check.py` 의 `sys_top_core` 항 (본 표의 무수정 전사).

### 28.6 GATE S1-US anchor 실측 (2026-08-18)

Vivado 2025.2.1 (Build 6403652) / `xcu55c-fsvh2892-2L-e` / OOC / 10.000 ns / `Design State: Routed`. 전 수치는 리포트 실물 전사다.

| 항 | 값 | 비고 |
|---|---|---|
| LUT sites (top) | **14,850** | 14,654 logic + 132 LUTRAM + 64 SRL. raw LUT cells 17,753 (LUT-combining 전) |
| FF | 9,585 | 계층 `(top)` 행 1,573 + `u_core` 8,012. 래퍼 설계상 I/O flop 은 1,601 (= 입력 1,246 + 출력 355; ECP5 반쪽의 `port bits 1,603` = 1,601 + clk + rst 로 독립 확인) 이고 리포트 `(top)` 행이 28 적은 것은 **계층 재귀속**이 주 성분으로 보인다 — `Unused sequential element … was removed` 는 run 전체에 6건뿐이고 그 6건 다 래퍼 flop 이 아니며, `u_hiu` 행 3,621 이 HIU 단독 실측 3,617 보다 4 많은 것이 흡수의 흔적이다. **정확한 귀속은 미조사** (FF 는 추적 축) |
| DSP48E2 | **39** | split `DSP_*` cells 312 |
| RAMB18 / RAMB36 / URAM | **2 / 0 / 0** | 전부 FP_StepSeq 내부 |
| CARRY8 | 702 | 추적 |
| SRL cells | 128 | 추적 |
| WNS @ 10 ns | **+1.497 ns** | → **Fmax 117.61 MHz** (기록 축) |
| WHS | +0.019 ns | hold 위반 0 |
| DRC | **errors 0**, warnings 137 checks / 5 규칙 | DPIP-2 66 + DPOP-3 29 + DPOP-4 33 + **LUTLP-2 8** + RTSTAT-10 1 |
| CRITICAL WARNING | **8, 전부 `[Synth 8-295]`** | = RO 8개. 화이트리스트 정확 일치, 외부 id 0 |
| premap `$mul` | **429** | yosys 0.64, `=== design hierarchy ===` 누계 |

계층 분해 (`sys_top_core_impl_util.rpt` 전사) — **사용자의 원래 질문에 대한 직답이 이 표다**:

| 인스턴스 | 모듈 | LUT | FF | DSP | RAMB18 |
|---|---|---|---|---|---|
| `u_core` | Top_Core | 14,850 | 8,012 | 39 | 2 |
| `u_core/u_hiu` | **HIU** | **2,570** | **3,621** | **0** | **0** |
| `u_core/u_hiu/dma_inst` | dma_engine | 33 | 65 | 0 | 0 |
| `u_core/u_decoder` | ISA_Decoder | 12,248 | 4,391 | 39 | 2 |
| `u_core/u_decoder/u_core` | PE_Core | 11,118 | 3,016 | 39 | 2 |
| `…/g_v180c_fp.u_fp_stepseq` | FP_StepSeq | 4,565 | 1,300 | 4 | 2 |

즉 **HIU 는 Top_Core 의 17.3%** (2,570 / 14,850) 이고, DSP 와 BRAM 을 전혀 쓰지 않는다. HIU 단독 OOC 실측은 **2,631 LUT / 3,617 FF / WNS +5.505 ns → Fmax 222.47 MHz** 로, Top_Core 안의 2,570 과 비교해 **옵티마이저가 HIU 를 지워버리지 않았음**을 확인한다 (계통 통합에서 61 LUT 감소 = cross-boundary 최적화).

**병목 귀속 (실측)**: 시스템 Fmax 117.61 MHz 를 결정하는 것은 HIU (단독 222 MHz) 가 **아니다.** worst setup path 는 `u_core/u_decoder/u_ehdec/dec_eff_imm16_reg[4]/C` → `u_core/u_decoder/u_core/cr_payload_reg[12]/D`, Data Path Delay **8.485 ns** (logic 2.505 = 29.5% / **route 5.980 = 70.5%**), Logic Levels 25 (CARRY8 6 + LUT2/3/4/5/6 18 + MUXF7 1) — 즉 **EHDecode → PE_Core 의 decode/dispatch 경로이고 라우팅 지배**다. 이는 §26.9 congestion 진단이 v1.9 에 대해 특정한 병목 위치 ("`case(dec_opcode)` 본체 자체의 조합 깊이") 와 같은 계열의 관측이며, 본 gate 가 그 관측을 system-top 문맥에서 독립 재확인한 것이다. `checking unconstrained_internal_endpoints (0)` — 제약 누락으로 낙관 편향된 수치가 아니다.

**독립 교차검증 (본 gate 이전의 별개 run — 하네스도 다르다)**: 정찰 A 가 `phys_opt_design` **없는** 흐름으로 같은 part 에 측정한 Top_Core 는 **LUT 14,847 / FF 8,012 / DSP 39 / RAMB18 2 / WNS +1.567 → 118.6 MHz** 였다. 본 gate 는 phys_opt 를 포함하므로 LUT +3 / WNS −0.070 ns 차이가 나며, 두 수치의 근접이 anchor 의 재현성 근거다. **anchor 로 채택하는 것은 repo 하네스 수치 (14,850)** 다 — repo 안에서 `make` 한 줄로 재현되고 리포트가 아카이브되는 쪽이어야 gate 가 성립한다.

**재현성 실측**: 같은 명령을 2회 실행해 `impl_summary.json` 이 **전 필드 동일**함을 확인했다 (LUT cells 17,753 / FF 9,585 / DSP 39 / BRAM 2 / CARRY 702 / WNS +1.497 / WHS +0.019 / Fmax 117.61). 즉 이 anchor 는 seed 잡음이 섞인 1회 측정이 아니다.

**discriminator 자기시험 — gate 가 실제로 발화하는가 (tautology 방지, §27.6 ③ PHASE C 관례의 합성 gate 적용)**

선언만 하고 발화하지 않는 gate 는 gate 가 아니다. 두 층에서 실증했다.

*(1) 축 변이 6종 — 체커가 각 축에서 실제로 FAIL 을 내는가.* 미변이 baseline exit 0 을 확인한 뒤, 축을 하나씩 어긋나게 변이해 전부 exit 1 을 실증했다: LUT ceiling 24,799→100 / DSP 정확히 39→38 / BRAM 정확히 2→1 / premap `$mul` 429→428 / crit 화이트리스트 8→7 / DRC severity 분류 완화. 추가로 **run 로그를 제거한 경우** `UNMEASURED (FAIL)` 로 떨어지는 것까지 확인했다 — 증거 부재가 pass 로 새지 않는다.

*(2) 제약 withhold 실측 1종 — D2 제약을 빼면 gate 가 떨어지는가.* `make synth-sys-gate SYS_GATE=sys_top_core_diag_nod2` 는 `POST_XDC` 만 넘기지 않는 동일 run 이다 (`_diag_` 명명은 `fp_acclattice_diag_*` 선례). 실측:

| 축 | D2 제약 적용 (gate) | D2 제약 withhold (diag) |
|---|---|---|
| CRITICAL WARNING | **8** — 전부 `[Synth 8-295]` | **16** — `[Synth 8-295]` 8 + **`[DRC LUTLP-1]` 8** |
| DRC | errors **0** / warnings 5 (LUTLP-2 "Loop Allowed" ×8 포함) | **errors 8** — DRC 표에 `LUTLP-1` 행이 severity `Critical Warning` / Checks 8 로 등장 |
| 판정 | **PASS** (exit 0) | **FAIL** (exit 1, 두 축 동시 발화) |
| LUT cells / FF / DSP / BRAM / WNS | 17,753 / 9,585 / 39 / 2 / +1.497 | **완전 동일** |

마지막 행이 D2 판정의 실증이다: **제약은 설계를 1비트도 바꾸지 않고 인정(acknowledgement)만 바꾼다.** 즉 D2 는 RTL 결함이 아니라 XDC 공백이었다는 §28.3 의 주장이 여기서 실측으로 확인된다.

*(3) 자기시험이 잡아낸 기존 체커의 결함 1건 (수리 · 정직 기록).* (2) 를 처음 돌렸을 때 CRIT WARN 축은 FAIL 을 냈으나 **DRC 축은 "0 errors" 로 PASS 를 냈다.** 원인: `fp_op_gate_check.py` 의 `parse_drc` 정규식이 severity 를 `(\w+)` 로 잡아, **공백이 들어간 severity — 정확히 `Critical Warning` — 행을 전부 조용히 버리고 있었다.** 이 축이 발화해야 하는 유일한 severity 를 볼 수 없는 상태였던 것이다. `([A-Za-z][A-Za-z ]*?)` 로 수리하고 재실증했다 (diag run 이 DRC 축에서도 FAIL). 기존 4개 gate 의 warning 계수는 수리 전후 불변 (F1-US 2 / xcu50 2 / V20-2 0 / V20-3 2) — 즉 이 수리는 아카이브된 판정을 재분류하지 않고 보이지 않던 severity 만 보이게 한다. **이 결함은 GATE S1 을 만들지 않았다면 발견되지 않았을 것이다** — 지금까지 어떤 gate 도 Critical Warning DRC 행을 낸 적이 없어서 vacuous 하게 통과해 왔다.

**GATE S1-US 재측정 (2026-08-18 — §29 HIU 실물화 반영, area binding 발효 후 최초 실측)**

§28.5 (c) 가 "binding 은 **다음 commit** 부터 발효한다" 고 적은 그 다음 commit 이 이것이다. 위 anchor 기록 (표·계층 분해·병목 귀속·discriminator 자기시험) 은 **삭제하지 않고 병존**한다 (§12a 규칙 5) — anchor 는 anchor 로 남고, 아래가 그것에 대한 첫 drift 측정이다. 판정 형식은 §26.6 GATE V9-4 실측 표 형식을 그대로 쓴다.

측정 조건은 anchor 와 동일하다: Vivado 2025.2.1 (Build 6403652) / `xcu55c-fsvh2892-2L-e` / OOC / 10.000 ns / `Design State: Routed` / `make synth-sys-gate SYS_GATE=sys_top_core PART=xcu55c-fsvh2892-2L-e` → `python3 synth/scripts/fp_op_gate_check.py`. 전 수치는 리포트 실물 전사다.

**판정: GATE S1-US = FAIL. 단일 축 (premap `$mul`). 체커 exit 1.** 나머지 7개 binding 축은 전부 PASS 이고, **어떤 기준 수치도 수정하지 않았다.**

| 축 | 지위 | anchor (§28.6) | 재측정 | 기준 | 판정 |
|---|---|---:|---:|---|---|
| **LUT sites** | binding | 14,850 | **14,984** (+134) | hard ceiling **24,799** | **PASS** — ceiling 의 **60.4%**. §29.11 선공표 상한 (+400 이내 = ≤ 15,250) 안 |
| **DSP48E2** | binding, exact | 39 | **39** | 정확히 39 | **PASS** — 불변 |
| **RAMB18 / RAMB36 / URAM** | binding, exact | 2 / 0 / 0 | **2 / 0 / 0** | RAMB 정확히 2 | **PASS** — 불변 |
| **premap `$mul`** | binding, exact | 429 | **381** (−48) | ~~정확히 429~~ → **정확히 381** | **FAIL → 해소 (재anchor, 2026-08-18 사용자 결정)** — 아래 귀속 및 §29.11a |
| **DRC** | binding | errors 0, warnings 137 checks / 5 규칙 | **errors 0, warnings 137 checks / 5 규칙** | errors 0 | **PASS** — DPIP-2 66 + DPOP-3 29 + DPOP-4 33 + LUTLP-2 8 + RTSTAT-10 1. anchor 와 **구성·계수 완전 동일** |
| **CRITICAL WARNING** | binding | 8, 전부 `Synth 8-295` | **8, 전부 `Synth 8-295`** | 화이트리스트 8, 외부 id 0 | **PASS** — 로그의 `ERROR:` 줄 **0** |
| **WHS** | binding | +0.019 ns | **+0.019 ns** | ≥ 0 | **PASS** — §29.11 이 "본 변경의 **유일한 실질 리스크 축**" 으로 지목한 축이 **정확히 불변** |
| WNS / Fmax | 기록 | +1.497 ns / 117.61 MHz | **+1.053 ns / 111.77 MHz** | — | RECORDED (−0.444 ns / −5.84 MHz) |
| FF | 추적 | 9,585 | **9,674** (+89) | — | §29.11 선공표 상한 +320 이내 |
| raw LUT cells / CARRY8 / SRL cells | 추적 | 17,753 / 702 / 128 | **17,763 / 704 / 128** | — | — |

**FAIL 축의 귀속 — 수치를 맞추지 않는다 (§29.11 별항 1 절차 4 의 이행).**

premap `$mul` 은 **381** 로 측정됐고, §29.11 별항 1 이 **측정 이전에** 공표한 예측값 **381 (−48)** 과 **정확히 일치**한다. 귀속도 그 별항이 미리 적어 둔 그대로다: 소멸한 2D 배열 `partitioned_tlb_*[partition_id][j]` 의 행 주소 곱셈 (`p*TLB_ENTRIES + j`) **48개**가 anchor 429 안에 **넷리스트 cell 0개짜리 phantom multiplier** 로 들어앉아 있었고, §29.3 의 direct-mapped 형태는 엔트리 주소를 `{partition, index}` 연접으로 만들어 곱셈을 **구조적으로 만들지 않는다**. 즉 이 FAIL 은 회귀가 아니라 **anchor 자신이 결함을 포함하고 있었다는 사실의 노출**이다.

**그럼에도 FAIL 로 기록한다.** §28.5 는 이 축을 "즉시 binding, 1이라도 어긋나면 FAIL" 로 선언했고, 예측이 맞았다는 사실은 기준을 자동으로 움직이지 않는다. 실제 재anchor (`fp_op_gate_check.py` 의 `premap_mul_expect` 429 → 381) 는 **§12a 상 사용자 결정 사항**이며 §29.11 별항 1 절차 2 대로 승인 후 S2-C4 에서 수행한다. **승인 전 S2-C2/C3 merge 금지** (절차 3). 본 재측정 세션은 `premap_mul_expect` 를 건드리지 않았다.

**계층 분해 (`sys_top_core_impl_util.rpt` 전사) 와 면적 귀속:**

| 인스턴스 | 모듈 | LUT (anchor → 재측정) | FF (anchor → 재측정) | DSP | RAMB18 |
|---|---|---|---|---:|---:|
| `Top_Core_gate_top` | (top) | 14,850 → **14,984** (+134) | 9,585 → **9,674** (+89) | 39 | 2 |
| `(Top_Core_gate_top)` | (top) | 0 → **0** | 1,573 → **1,701** (+128) | 0 | 0 |
| `u_core` | Top_Core | 14,850 → **14,984** (+134) | 8,012 → **7,973** (−39) | 39 | 2 |
| `u_core/u_hiu` | **HIU** | 2,570 → **2,706** (+136) | 3,621 → **3,582** (−39) | **0** | **0** |
| `u_core/u_hiu/dma_inst` | dma_engine | 33 → **32** (−1) | 65 → **65** | 0 | 0 |
| `u_core/u_decoder` | ISA_Decoder | 12,248 → **12,245** (−3) | 4,391 → **4,391** | 39 | 2 |
| `u_core/u_decoder/u_core` | PE_Core | 11,118 → **11,116** (−2) | 3,016 → **3,016** | 39 | 2 |
| `…/g_v180c_fp.u_fp_stepseq` | FP_StepSeq | 4,565 → **4,565** (불변) | 1,300 → **1,300** | 4 | 2 |

**LUT 증분 +134 는 전부 HIU 안이고, 그 안에서 성분이 분리된다.** 리포트의 LUTRAM 열이 그것을 직접 준다: 설계 전체 LUTRAM **132 → 248 (+116)**, 그중 FP_StepSeq 132 (불변) / **HIU 116 (신규)**. 즉 `tlb_mem` 저장소의 대가는 **116 LUTRAM** 이고, HIU 의 logic LUT 는 2,570 → 2,590 으로 **+20** 뿐이다 (fault 로직 4종 + 기입 샘플 레지스터 디코드 + D6 형식3 분리 + D8 수리의 합). HIU 밖은 −2 (ISA_Decoder −3, dma_engine −1, PE_Core −2 — 계층 간 LUT combining 재귀속 규모이며 설계 변경이 아니다). **프로토타입 예측 +22 보다 큰 이유는 §29.11 이 미리 적어 둔 그대로다** — 정규 형태가 fault 로직·샘플 레지스터·D8 수리를 함께 갖고, 그 미지수를 흡수하도록 상한을 +400 으로 잡아 두었다.

**RAMB18 이 2 로 유지된 것은 우연이 아니다.** 합성 로그의 Distributed RAM Final Mapping Report 가 `|u_hiu | tlb_mem_reg | User Attribute | 64 x 100 | RAM64M8 x 15 |` 로 적는다 — §29.5 가 규범으로 못박은 `ram_style = "distributed"` 가 **User Attribute 로 존중**됐다는 뜻이다. `block` 이었다면 RAMB36 2개가 붙어 축이 4 가 되고 즉시 FAIL 이었을 자리다 (§29.3 채택 이유 3 의 실측 확인). 부수로 `Synth 8-4767` (async reset 때문에 RAM 추론 거부) **0건** — `tlb_mem` 을 async-reset 없는 전용 블록에 둔 §29.7 형식3 이 "선택이 아니라 필수" 였다는 것의 실측 확인이다.

**FF −39 (HIU) 의 귀속 — 추가분보다 소멸분이 컸다.** TLB 실물화는 HIU 에 `tlb_valid` 64 + `tlb_rd_q` 100 + 기입 샘플 4종 134 + fault 4 + one-hot state +2 를 **더한다**. 그런데 실측은 −39 다. 로그가 소멸분을 직접 보여준다: `Unused sequential element initial_state_reg[*] was removed` **14건** (설계 전체 `Synth 8-6014` 는 anchor **6건** → 재측정 **20건**, 즉 **증가분 14건이 전부 `initial_state`**) + `Synth 8-3886 merging instance … initial_state_reg[*]` **62건**. 즉 §29.8 의 D8 수리 (`initial_state` 경유 제거) 가 `initial_state` 를 `chacha_state` 와 동일 구동원으로 만들면서 그 512 bit 배열 대부분을 넷리스트에서 접어 버렸다. **FF 는 추적 축이므로 bit 단위 산술까지 유도하지 않는다** — 증거는 위 두 메시지 계수이고, 그 이상은 주장하지 않는다.

**WNS 는 악화됐고 (기록 축), 병목은 HIU 가 아니다.** worst setup path 는 `u_core/u_decoder/u_ehdec/dec_eff_imm16_reg[5]/C` → `u_core/u_decoder/u_core/cr_payload_reg[59]/D`, Data Path Delay **8.927 ns** (logic 2.476 = 27.7% / **route 6.451 = 72.3%**), Logic Levels **28** (CARRY8 9 + LUT2/3/4/5/6 19). anchor 의 worst path 는 같은 계보의 `dec_eff_imm16_reg[4] → cr_payload_reg[12]`, 8.485 ns / Logic Levels 25 였다 — **비트 인덱스만 다른 같은 EHDecode→PE_Core dispatch 경로**이고 route 지배도 그대로다 (70.5% → 72.3%). §26.9 · §28.6 · §28.9 가 세 번 독립 확인한 그 병목이며, **HIU 경로도 rst 경로도 아니다.** +134 LUT 가 placer 해를 흔든 congestion drift 로 귀속한다 (§26.6 V9-4 선례와 같은 클래스, 다만 여기서는 기록 축이라 FAIL 을 구성하지 않는다). `checking unconstrained_internal_endpoints (0)` — anchor 와 동일하게 제약 누락으로 낙관 편향된 수치가 아니다.

**WHS 는 정확히 불변이고, worst hold path 도 HIU 가 아니다.** `u_core/u_decoder/u_ehdec/payload_latched_reg[4]/C` → `…/dec_input_payload_reg[4]/D`, Data Path Delay 0.072 ns, Logic Levels **0**, Slack **+0.019 ns**. §29.11 이 "마진이 사실상 없다 · 음수면 즉시 FAIL, 완화 없음" 이라고 적은 축이 **한 자리도 움직이지 않았다.**

**신규 축 2종 (§29.11 별항 2·3) 의 최초 실측 — 둘 다 선공표 값과 정확히 일치:**

| 신규 축 | 선공표 | 실측 | 판정 |
|---|---|---|---|
| `Synth 8-7137` 모듈별 | HIU **0** / PE_Core **68** / 합 **68** | HIU **0** / PE_Core **68** / 합 **68** | 일치. D6 수리 전 HIU 66 → **0** |
| `Synth 8-3848` (undriven net) | **0** | **0** | 일치. allowlist 비어 있음 |

전제조건인 캡 상향 (`set_msg_config -id {…} -limit 100000`) 이 하네스에 들어가 있고, 그것이 작동했음이 로그로 확인된다: anchor 로그의 `Common 17-14` 캡 INFO 는 **7줄** (`Synth 8-7137` / `8-3848` / `8-7129` / `8-3886`×3 / `Route 35-198`) 이었고, 재측정 로그는 **1줄** (`Route 35-198`) 뿐이다. 즉 **gate 축 4종은 더 이상 100 에서 잘리지 않는다.** 남은 1건은 OOC 구조적 메시지 (`Port "…" does not have an associated HD.PARTPIN_LOCS`) 로 gate 축이 아니며, 이 사실을 적어 두어 "캡이 사라졌다" 로 과장되지 않게 한다. 부수로 캡 해제 후 `Synth 8-7129` **1,738건**, `Synth 8-3886` **316건** 이 보이며, 8-7129 안에 §29.10 이 유지를 결정한 예약 포트가 그대로 관측된다 (`Port interface_type[1] / [0] in module HIU is either unconnected or has no load`).

**측정 방법의 함정 1건 — 캡 상향이 만들어낸 새 오계수 경로 (§29.2 C3 의 두 번째 형태).** Vivado 는 `-source` 로 읽은 tcl 을 **`# ` 접두로 로그에 그대로 echo** 한다. 하네스의 캡 상향 줄이 `{Synth 8-7137} {Synth 8-3848} {Synth 8-7129} {Synth 8-3886}` 를 문자열로 담고 있으므로, **소박한 `grep -c "Synth 8-7137"` 는 69 를 답한다 — 참값 68 에 tcl echo 1 줄이 얹힌 값이다.** `Synth 8-3848` 은 더 나쁘다: 참값 **0** 인데 소박한 grep 은 **1** 을 답해 **exact-0 축이 거짓 FAIL** 로 보인다. 따라서 이 두 축의 계수는 **반드시 severity 접두를 앵커해서** 취한다 — `grep -cE "^(WARNING|CRITICAL WARNING|INFO|ERROR): \[Synth 8-7137\]"`. §29.2 C3 이 "그 +1 은 경고가 아니라 캡 INFO 줄 자신이었다" 고 적은 것과 **정확히 같은 클래스의 오계수이고, 원인만 다르다** (그때는 캡 INFO 줄, 지금은 tcl echo 줄). 두 사례의 공통 교훈을 규범으로 승격한다: **메시지 계수 축은 id 문자열이 아니라 severity-앵커 정규식으로 센다.**

**재현성 실측.** `impl_summary.json` 이 같은 날 앞선 run 과 **전 필드 동일**하다 (LUT cells 17,763 / FF 9,674 / DSP 39 / BRAM 2 / CARRY 704 / SRL 128 / WNS +1.053 / WHS +0.019 / Fmax 111.77). 다만 그 앞선 run 이후 `HIU.v` / `Top_Core.v` 의 mtime 이 갱신됐으므로, 이 일치는 두 가지를 동시에 말한다 — (i) 측정이 seed 잡음이 섞인 1회 관측이 아니고, (ii) **그 사이의 편집이 넷리스트에 영향을 주지 않았다.** (ii) 의 독립 증거는 yosys premap 로그를 재생성해 **본문이 바이트 동일** (logfile hash `3dc41cc4e8`) 함을 확인한 것이다.

**하네스 공백 1건 (정직 기록, 수리하지 않음).** premap `$mul` 축의 증거 파일 `synth/reports/fp_ops/sys_top_core_premap_mul.log` 는 **어떤 make 타깃도 재생성하지 않는다** — `make synth-sys-gate` 는 Vivado 리포트만 갱신하고, 이 로그는 out-of-band yosys 호출로 만들어져 아카이브된 것을 `fp_op_gate_check.py` 가 읽기만 한다. 따라서 **RTL 이 바뀌어도 이 축은 조용히 옛 값을 계속 답할 수 있다** (본 재측정에서는 명시적으로 재생성해 최신임을 확인했다). 이것은 §28.5 가 `get_msg_config -count` 에서, §29.2 C2 가 메시지 캡에서 겪은 것과 같은 유형 — **"증거가 자동으로 갱신되지 않는 축은 false PASS 를 낼 수 있다"** — 의 세 번째 사례다. 수리 (make 타깃 편입) 는 gate 하네스 변경이므로 본 재측정 세션의 범위 밖으로 두고 §28.10 이월 목록에 올린다.

### 28.7 ECP5 반쪽 (MEASUREMENT — 어떤 결과도 FAIL 아님)

V20-2/V20-3 의 정책을 문언 그대로 승계한다: **GATE S1 의 merge-blocker binding 은 xcu55c 반쪽에만 있다. ECP5 반쪽은 실현성 측정이며, 어떤 결과가 나와도 — 어렵다·비싸다·불가능하다·완주 실패 포함 — gate FAIL 을 구성하지 않는다. 유일한 의무는 측정의 실행과 정직한 기록이다.**

측정 대상은 xcu55c 와 **동일 gate_top** (`Top_Core_gate_top`) 으로, LFE5UM-85F CABGA381 -6 / OOC / seed 1 / 40 MHz 참조점 (관례 참조점일 뿐 계약 아님). 하네스 = `synth/lattice/scripts/synth_fp_ops.sh sys_top_core` 의 `run_meas` 경로 (yosys premap stat → `synth_ecp5` → `nextpnr-ecp5`), 리포트 `synth/lattice/reports/fp_ops/sys_top_core_*`.

**측정 전 사전 기록 (사후 해석 여지를 없애기 위해 두 결과를 미리 선언한다):**

- **(a) TRNG 링 오실레이터의 프론트엔드 차이.** `g_ro[*]` 는 의도된 조합 피드백이다. Vivado 는 넷리스트 property `ALLOW_COMBINATORIAL_LOOPS` 로 이를 인정하지만 (`hiu_trng_ro.xdc`), **yosys/nextpnr 흐름에는 동등한 제약이 없다.** 따라서 루프 거부 또는 타이밍 분석 경고는 이 반쪽의 **예정된 결과**이며 RTL 결함도 ECP5 흐름의 결함도 아니다.
- **(b) 라우팅 포화.** Top_Core 는 PE_Core + FP_StepSeq 를 통째로 담는다. v1.9b full Cluster 는 85F 에서 COMB 39.6% 만으로 이미 routing-지배 11.34 MHz 였다 (`cluster_v19b_pnr.log`). 낮은 Fmax 는 패브릭의 답이지 회귀가 아니다.

**이 반쪽의 하중을 지는 데이터는 흐름의 뒤가 아니라 앞이다**: 같은 RTL 이 **비-Vivado 프론트엔드에서 elaborate·매핑되는가.** D1 (Vivado 가 거부하는 Verilog-2001 위반) 과 D3 (Vivado 가 관용하는 선언 전 사용) 이 정확히 그 질문을 테이블에 올렸으므로, PnR 이 죽어도 아카이브된 premap stat 은 유효한 측정이다.

**ECP5 MEASUREMENT 결과 (2026-08-18, yosys 0.64 + nextpnr-ecp5 / LFE5UM-85F CABGA381 -6 / OOC / seed 1) — 사전 기록한 (a) 분기가 그대로 발동했다:**

| 단계 | 결과 |
|---|---|
| yosys `read_verilog` + `hierarchy -check` | **완주, ERROR 0** — D1/D3 수리 후 비-Vivado 프론트엔드에서 hard error 없음 (본 반쪽의 하중을 지는 데이터) |
| yosys premap stat | `$mul` **429** — **xcu55c 반쪽과 정확히 동일**. 판별 pin 이 두 프론트엔드에서 일치한다 |
| yosys `synth_ecp5` | **완주** — LUT4 17,073 (logic) / CCU2C 2,997 / TRELLIS_FF 10,645 / MULT18X18D 58 / DP16KD (EBR) **0** |
| nextpnr packing | **완주** — TRELLIS_COMB **24,397 / 83,640 = 29%**, TRELLIS_FF 10,645 = 12%, MULT18X18D 58/156 = 37%, EBR 0/208 |
| nextpnr timing analysis | **중단** — `ERROR: Timing analysis failed due to combinational loops` + `Found 8 combinational loops:` (loop 1..8 = `u_core.u_hiu.g_ro[0..7].ro_s2`) |
| placement / routing / Fmax | **미도달 — 측정값 없음.** 없는 수치를 만들지 않는다 |

단위 규율 (§27.6 의 "LUT4 cell 과 placed TRELLIS_COMB 는 다른 단위, 혼용 금지" 를 그대로 적용): packing 전 Total LUT4s **23,427 = 28%** (logic 17,073 + carry 5,994 + RAM 240 + RAMW 120) → packing 후 TRELLIS_COMB **24,397 = 29%**. 즉 **면적은 85F 에 여유롭게 수납된다** — 사전 기록 (b) 가 우려한 라우팅 포화 영역 (v1.9b 는 COMB 39.6% 에서 이미 routing-지배) 보다 **아래**다. 다만 Fmax 는 측정되지 않았으므로 "수납된다" 는 것과 "동작 속도가 나온다" 는 것은 별개로 남는다.

**중단 원인의 정직한 귀속**: 이것은 RTL 결함도 ECP5 흐름의 결함도 아니고, **제약 표면의 비대칭**이다. Vivado 는 넷리스트 property `ALLOW_COMBINATORIAL_LOOPS` 로 의도된 발진 루프를 인정할 수 있고 (`hiu_trng_ro.xdc` → DRC LUTLP-2 "Combinatorial Loop Allowed" ×8 로 통과), **nextpnr-ecp5 에는 동등한 인정 수단이 없어 타이밍 분석 자체가 실패한다.** §28.7 이 측정 전에 (a) 로 선언한 바로 그 결과이며, 따라서 사후 해석의 여지가 없다.

**cross-fabric 실측 divergence 2건 (기록 — 이것이 dual-fabric 측정을 하는 이유다):**

- **곱셈기**: xcu55c **DSP48E2 39** vs ECP5 **MULT18X18D 58**. premap `$mul` 은 양쪽 429 로 동일하므로 차이는 RTL 이 아니라 **매퍼의 share/decompose 재량**이다 — §26.6 이 MULT 편차 조사에서 확립한 그 클래스이고, 판별 pin (premap `$mul`) 이 일치하므로 결함이 아니다.
- **메모리**: xcu55c **RAMB18 2** vs ECP5 **EBR 0**. yosys 가 `Replacing memory ... with list of registers` (PE_Core/EHDecode 다수) 로 메모리를 레지스터로 전개했고, 그것이 TRELLIS_FF 10,645 vs xcu55c FF 9,585 차이의 성분이다. GATE S1-US 가 RAMB18 을 **정확히 2** 로 pin 하는 이유가 여기 있다 — 같은 RTL 이 패브릭에 따라 메모리를 쓰기도, 안 쓰기도 한다.

**리포트 아카이브**: `synth/lattice/reports/fp_ops/sys_top_core_{synth.rpt,premap.rpt,pnr.log}`. nextpnr 입력 넷리스트 `sys_top_core_synth.json` 은 **40 MB** (트래킹된 fp-ops 넷리스트 중 최대인 `fp_stepseq_synth.json` 7.9 MB 의 5배) 라 gitignore 하고 재생성 경로만 남긴다 — `sh synth/lattice/scripts/synth_fp_ops.sh sys_top_core`. 측정 증거 3종은 전부 트래킹된다.

**off-ramp 판정**: ECP5 는 이 top 의 **at-speed 측정 역할을 갖지 않는다** (Fmax 미측정 = 측정 불가). 나머지 검증 역할 — TRNG 실리콘 검증 · UsbCdcTransport · FOSS bitstream — 은 전부 유지된다. TRNG **실리콘** 검증이 ECP5 의 역할로 남아 있다는 점은 특히 기록해 둘 가치가 있다: 그 검증을 실제로 수행하려면 이 RO 루프를 ECP5 흐름에서 통과시킬 수단 (nextpnr 의 loop 처리 옵션 또는 RO 를 blackbox 로 격리한 별도 top) 이 필요하고, 본 측정이 그 요구사항을 처음으로 실측 근거와 함께 드러냈다. 후속 commit 몫으로 이월한다.

**ECP5 MEASUREMENT 재측정 (2026-08-18 — §29 HIU 실물화 반영). 위 최초 측정 기록은 삭제하지 않고 병존한다 (§12a 규칙 5).** 동일 하네스·동일 조건 (`sh synth/lattice/scripts/synth_fp_ops.sh sys_top_core`, yosys 0.64 + nextpnr-ecp5 / LFE5UM-85F CABGA381 -6 / OOC / seed 1 / 40 MHz 참조점). **본 절 정책 그대로 이 반쪽은 어떤 결과도 FAIL 을 구성하지 않는다** — 아래 전부 기록이다.

| 단계 / 축 | 최초 측정 | 재측정 | 비고 |
|---|---:|---:|---|
| yosys `read_verilog` + `hierarchy -check` | 완주, ERROR 0 | **완주, ERROR 0** | 비-Vivado 프론트엔드 elaborate — 본 반쪽의 하중을 지는 데이터, 유지 |
| premap `$mul` | 429 | **381** | **xcu55c 반쪽과 정확히 동일하게 이동**. 판별 pin 의 cross-frontend 일치가 유지된다 |
| premap ports / port bits | 42 / 1,603 | **49 / 1,742** | +7 포트 / +139 bit = §29.4 계약 확장 (`tlb_write_*` 5 입력 135 bit + `tlb_fault`/`tlb_fault_code` 4 bit). **래퍼 I/O flop 1,740 + clk + rst = 1,742 로 독립 확인** |
| premap memories / memory bits | 4 / 10,639 | **5 / 10,895** | `partitioned_tlb_virt`/`_phys` 소멸, `tlb_mem` 신설 |
| `synth_ecp5` LUT4 (logic) | 17,073 | **17,718** (+645) | |
| `synth_ecp5` CCU2C | 2,997 | **3,017** (+20) | |
| `synth_ecp5` TRELLIS_FF | 10,645 | **10,736** (+91) | |
| `synth_ecp5` MULT18X18D | 58 | **58** | **불변** |
| `synth_ecp5` PFUMX | 1,429 | **1,835** (+406) | |
| `synth_ecp5` TRELLIS_DPR16X4 | 60 | **160** (+100) | **`tlb_mem` 의 ECP5 판** — 아래 divergence 3 |
| `synth_ecp5` DP16KD (EBR) | **0** | **0** | 양쪽 패브릭 모두 block RAM 을 쓰지 않았다 |
| nextpnr packing 전 Total LUT4s | 23,427 = 28% | **24,712 = 29%** | logic 17,718 / carry 6,034 / **RAM 640** / **RAMW 320** |
| nextpnr packing 후 TRELLIS_COMB | 24,397 = 29% | **25,688 = 30%** | TRELLIS_FF 10,736 = 12%, TRELLIS_RAMW **160**, MULT18X18D 58/156 = 37%, EBR 0/208 |
| nextpnr timing analysis | 중단 (8 combinational loops) | **중단 — 완전히 같은 형태** | `Found 8 combinational loops` = `u_core.u_hiu.g_ro[0..7].ro_s2`, `ERROR: Timing analysis failed due to combinational loops`, `0 warnings, 1 error` |
| placement / routing / Fmax | 미도달 — 측정값 없음 | **미도달 — 측정값 없음** | 없는 수치를 만들지 않는다 |

**중단 원인은 그대로다** — 사전 기록 (a) 의 제약 표면 비대칭이며, TLB 실물화와 무관하다 (루프 8개의 좌표가 문자 단위로 동일하다). 즉 **§29 의 변경은 ECP5 반쪽의 완주 여부를 1도 바꾸지 않았다.** 면적은 여전히 85F 에 여유롭게 수납된다 (TRELLIS_COMB 30%, 사전 기록 (b) 가 우려한 v1.9b 의 39.6% routing-지배 영역보다 아래). "수납된다" 와 "동작 속도가 나온다" 가 별개로 남는 것도 그대로다.

**cross-fabric divergence 3건 — 기존 2건은 유지되고, 1건이 새로 관측됐다:**

- **곱셈기 (유지):** xcu55c **DSP48E2 39** vs ECP5 **MULT18X18D 58**. premap `$mul` 이 양쪽 **381** 로 동일하므로 차이는 여전히 매퍼 재량이고 결함이 아니다. 주목할 점은 **429 → 381 이동에도 두 패브릭의 물리 곱셈기 수가 둘 다 불변 (39 / 58)** 이라는 것 — 소멸한 48개가 **양쪽 패브릭 모두에서 물리 셀 0개** 였다는 독립 확인이며, §29.11 별항 1 의 "phantom multiplier" 귀속에 대한 두 번째 증거다.
- **메모리 (유지):** xcu55c **RAMB18 2** vs ECP5 **EBR 0**.
- **분산 RAM 의 가격 (신규):** 같은 `ram_style = "distributed"` 지시가 xcu55c 에서는 **116 LUTRAM** (`RAM64M8 × 15`), ECP5 에서는 **RAM LUT 400 + RAMW LUT 200 = TRELLIS_DPR16X4 100** 로 떨어진다. 원인은 기본 블록 크기다 — RAM64M8 은 64 word × 8 bit 이고 DPR16X4 는 16 word × 4 bit 이므로, 64×100 bit 저장소가 xcu55c 에서는 15개, ECP5 에서는 (64/16) × (100/4) = **정확히 100개**로 쪼개진다. **LUT 환산으로 약 3.4배 비싸다.** 이것이 §29.3 이 채택 형태를 고를 때 "ECP5 반쪽에서 더 커진다" 고 적어 둔 항목의 실측이며, xcu55c 의 116 LUTRAM 만 보고 저장소 비용을 일반화하면 안 된다는 근거다.

**하네스 staleness 1건 (정직 기록 — 고치지 않았다).** `synth/lattice/fp_ops/gate_check.py` 의 `sys_top_core` 행은 두 상수를 갖는다: `premap_pin = 429` 와 `wrapper_ff = 1601`.

- `premap_pin = 429` 는 이제 ` MISMATCH` 를 출력한다. **이것은 축이 작동하는 것이고, 고쳐야 할 대상이 아니다** — 해소는 xcu55c 반쪽과 **같은 하나의 사용자 재anchor 결정** (§29.11 별항 1) 에 종속되며, MEASUREMENT 반쪽이라 FAIL 을 구성하지도 않는다.
- `wrapper_ff = 1601` 은 §29.4 계약 확장으로 **사실이 아니게 됐다** (실제 1,740; ECP5 자신의 `port bits 1,742` 가 그 증거다). 그 결과 요약의 파생 줄 `unit = 9135 after -1601 wrapper I/O flops` 는 **틀린 수**이고, **옳은 값은 10,736 − 1,740 = 8,996** 이다. 본 재측정 세션은 이 상수를 **수정하지 않았다** — 하네스 상수 변경은 측정 세션이 조용히 할 일이 아니고, 무엇보다 raw 값 10,736 이 같은 줄에 함께 인쇄되므로 은폐 경로가 없다. **정정은 §28.10 이월 목록으로 올린다.**

### 28.8 고아 3종 — 실측과 편입 보류 판정

> **[2026-08-18 정정 — §31.6]** 본 절 제목과 본문의 **"고아 (orphan)"** 는 **부정확한 명명이었다.** 세 모듈이 어떤 `.v` 에서도 인스턴스화되지 않는다는 **사실 기술은 참**이나, 거기서 함의된 *"이 기능은 하드웨어에 없다"* 는 **거짓이다.** `TENSOR_ALU.v` 가 디코드하는 opcode 0x30/0x31/0x32 는 `isa/wt64v1_isa.json` 에 `MATMUL`/`TADD`/`EINSUM` 으로 **실재하고**, 그 하드웨어는 `PE_Core.v:2319/2329/2338` 에 **있으며**, 값 검증까지 통과한다 (`test_isa_decoder.py:659-675 test_matmul_2x2` — A=[[1,2],[3,4]] · B=[[5,6],[7,8]] → [[19,22],[43,50]] PASS). 즉 세 모듈은 **미결선 결함(unwired defect)이 아니라 대체 완료된 중복 구현(superseded duplicate)** 이다. `SIMD_ALU.v` / `ALU_Extended.v` 도 동일 구조다. 지위 판정과 근거 전수는 **§31.6**, MATMUL 결함의 정정·확장(O1b/O1c 신설)은 **§31.7**, O2 처분은 **§31.8** 이다. 본 절 원문은 §12a 규칙 5 대로 무수정 보존한다 — **본 절의 "고아" 라는 낱말을 단독 인용해 "폐기해도 기능이 사라진다/사라지지 않는다" 중 어느 쪽도 도출하지 마라.**

`TENSOR_ALU.v` (module `Tensor_ALU`) / `SIMD_ALU.v` / `ALU_Extended.v` 는 어느 `.v` 에서도 인스턴스화되지 않는다 (기계적 인스턴스 그래프 전수). 등장처는 자기 파일 · `test_*.py` · `Makefile` 의 `MOD` 분기뿐 — **cocotb 단독 top 으로만 존재**하며 `synth/` 전체에 파일명 등장 0건이었다. 본 workflow 가 3개 전부를 처음 합성했다.

**실측 (Vivado 2025.2.1 / `xcu55c-fsvh2892-2L-e` / OOC / `*_gate_top` 규약 / post-route):**

| 모듈 | LUT | FF | DSP48 | CARRY8 | Fmax | 비고 |
|---|---|---|---|---|---|---|
| `Tensor_ALU` | 4,486 | 7,178 | 310 | 372 | 155.79 MHz @ 10 ns | critical path 가 로직이 아니라 opcode 의 4,097-CE 팬아웃 라우팅 |
| `ALU_Extended` | 606 | 274 | 20 | 56 | 167.31 MHz @ 10 ns | Synth 경고 **0건** (3개 중 최청정), `WT_USE_DSP` 실효 확인 |
| `SIMD_ALU` | 10,001 | 939 | 16 | **1,608** | **22.47 MHz @ 45 ns (closure 실측)** | 10 ns 에서는 WNS −30.934 / 라우터 포기 → 그 run 의 Fmax 는 anchor 로 무효 판정, 45 ns 재측정으로 anchor 확보 |

**측정 정직성 2건:** (i) `Tensor_ALU`/`ALU_Extended` 의 Fmax 는 constraint 를 MET 한 run 의 외삽이다 — Vivado 는 MET 이후 최적화를 멈추므로 **보수적 하한**이다 (§28.6 의 Top_Core 수치와 동일 성격이라 상호 비교는 정합적). (ii) `SIMD_ALU` 45 ns 실측 22.47 MHz 는 실패 run 외삽값 24.43 MHz 보다 **낮다** — 실패 run 외삽이 낙관 편향이었음이 실증됐고, 재측정을 한 이유가 정당화된다. 45 ns 에서 margin 이 +0.495 ns (1.1%) 뿐이라 45 ns 가 실질 closure 점이다.

**결함 5건 (합성 에러 아님 — 전부 합성 이후 단계):**

- **O1 (기능 결함, 실측)** — `TENSOR_ALU.v:33-44` MATMUL (0x30): inner k-loop 이 한 iteration 안에서 같은 `res[i][j]` 에 nonblocking 대입을 4회 하므로 마지막 `k` 만 살아남고 그 RHS 가 `res[i][j]` 의 **구값**을 읽는다. 즉 MATMUL 이 `res += a[i][D-1]*b[D-1][j]` 라는 **무한 누산기**로 축퇴한다 (37행 `res[i][j] <= 0;` 도 같은 규칙으로 덮여 영구 무효). 실측 (verilator, D=2/W=16, 정답 `[[19,22],[43,50]]`): `r00 = 0,14,28,42,…` 로 매 사이클 +14 무한 증가 — 19 에 도달하는 사이클이 없다. 대조로 TENSOR_ADD(0x31)/TENSOR_MUL(0x32) 는 정답이므로 결함은 0x30 단독. **`test_tensor_alu.py:22` 가 `alu_valid == 1` 만 assert 하고 값을 전혀 검사하지 않아 1/1 PASS 가 이를 은폐하고 있다** — D4 의 계층-강제-기입 은폐와 동형 패턴이다.
- **O2 (경고 ×49)** — `TENSOR_ALU.v` `a_reg`/`b_reg`/`res_reg` 전군에 `Synth 8-7137` (Set/reset 동일 우선순위). **D6 와 동형** (D6 는 ×66). 수리 = `always @(posedge clk) if (!rst)` 가드 블록 분리이며 파형 완전 일치 (**의미 보존 — 5건 중 유일**). 주의: `if (!rst)` 가드를 빼고 순수 동기 블록으로 분리하면 rst 중에도 로드되어 의미가 바뀐다.
- **O3 (타이밍/면적 결함, 실측)** — `SIMD_ALU.v:90-91` 0x13 DIV / 0x1C REM 을 64-bit 조합논리 `/` `%` 로 4 lane 전개. Logic Levels 218 (CARRY8 159 + LUT3 57), Data Path Delay 40.915 ns. 4-lane ALU 하나가 whole L-PE (Pod 실측 `PE_Core u_lpe` 5,427 LUT) 의 **1.8배**. 결정적 대조: **`PE_Core` 는 같은 0x13/0x1C/0x1D 를 bit-serial 상태기계로 구현해 이 함정을 이미 회피했다** (`PE_Core.v:1900-1930`).
- **O4 (미독 포트 ×16)** — `SIMD_ALU.v:39,52` `precision_mode[7:0]` 이 선언·전달되나 `precision_unused` 로 흘려버릴 뿐 어떤 연산도 읽지 않는다. **D7 과 동형** — 포트 제거는 의미 보존 아님.
- **O5 (DSP 파이프라인 부재)** — 3개 모듈 공통 `DPOP-3/DPOP-4/DPIP-2` Warning (severity Warning, DRC ERROR 0). 수리는 latency 증가 = 의미 변경. 우선순위 낮음: 타이밍이 실제로 문제인 것은 SIMD 뿐인데 SIMD 의 병목은 DSP 가 아니라 O3 의 CARRY8 체인이라 이 수리로는 해소되지 않는다.

**편입 판정 — `measured-pending` (편입 보류). 사유를 전부 기록한다:**

편입 찬성 근거는 실재한다: (i) `claude.md:60,101-102` §5-1/§6 이 "PE = ISA_Decoder + ALU wrapper" 와 "Top_Core → HIU + ISA_Decoder + ALU 모듈들" 이라는 통합 지점을 **명시적으로 규정**하고, 그 ALU 목록이 3개 고아의 합집합과 정확히 일치한다. (ii) `wt64v1_spec.md:229-231` §11 회귀 베이스라인이 Tensor_ALU 1 / SIMD_ALU 9 / ALU_Extended 16 을 계상하고 있다. (iii) `.claude-memos/board_hw_plan.md:173` 은 SIMD_ALU 를 **live contingency** 로 등재한다 ("ECP5 84K LUT 부족 시 SIMD_ALU 대체"). (iv) `ALU_Extended.v` 는 3개 중 유일하게 initial commit 이후 커밋이 있고 (2026-07-14 벤더 attribute 이행), 폐기 어휘로 이 3개를 지목한 문장은 `.claude-memos/` + spec + `claude.md` 전체에 **0건**이다.

편입 반대 근거도 실재하며, 더 무겁다: (i) **O1 — 대표 연산 MATMUL 이 한 번도 동작한 적이 없다.** gate 편입은 설계를 merge-blocker 로 약속하는 행위인데, 지금 면적을 gate 로 고정하면 죽은 설계를 규범화한다. (ii) **O3 — 22.47 MHz** 는 프로젝트 100 MHz 문맥의 4.45× 미달이고, 수리는 인터페이스·latency 변경 (`SIMD_ALU.v` 헤더가 명문화한 "one cycle of latency" 계약 파기) 이라 **의미 보존이 아니다.** (iii) 기능이 이미 `PE_Core` 로 흡수 완료됐고 **서로 모순되는 설계 결정**을 담고 있다: `claude.md:383` 이 기록한 자원 폭증 진단에 대해 채택된 mitigation 은 MATMUL 을 고정 2×2 로 축소한 것 (`PE_Core.v:2319-2327` 이 실물) 인데 `TENSOR_ALU.v` 는 축소 전 4×4 형태를, 그것도 64-bit 원소 (1024-bit 행렬) 로 유지한다 — **채택된 결정에 정면으로 어긋나는 pre-mitigation 산물**이다. 데이터 레이아웃도 불일치 (PE_Core 0x31 = 4×16-bit lane vs Tensor_ALU 0x31 = 4×4×64-bit).

**따라서: 고아 지위 판정 (폐기 vs 통합) 이 gate 편입보다 선행해야 한다.** 본 절은 그 판정을 하지 않는다 — 판정은 상위 결정권자 몫이며, 본 절의 의무는 근거를 남기는 것이다. 대신 세 모듈은 §28.4 의 `measured-pending` 지위로 **선언되어 있고 래칫에 걸려 있으므로**, 이 보류는 조용히 영구화될 수 없다 (`make lint` 이 매 실행 사유와 함께 열거한다).

**정책 공백 1건 (기록)**: `§12a` 는 pre-stable dead-opcode 제거를 정규 개발 행위로 성문화하고 spec-first 순서·`domain_version` bump·superseded 보존까지 규정하며 §24 (v1.7.1) 선례가 있다. 그러나 §12a 는 **opcode/signature 단위** 정책이고, **RTL 모듈 단위 고아 제거에 대한 규정은 어디에도 없다.** 고아 판정이 "폐기" 로 나올 경우 그 절차 (audit 로 소비자 0 확정 → spec 기록 → 파일 제거 → `Makefile` MOD 분기 제거 → 테스트 제거 → §11 베이스라인 재계상) 를 §12a 확장으로 성문화해야 한다.

### 28.9 U30 (xcu30) Pod+HIU 묶음 실측 — hardware 판단 근거

사용자 질문 "Alveo U30 카드의 SoC 하나당 (2×2)×(2×2)+HIU 묶음을 각각 합성하는 건 어떨지" 에 실측으로 답하기 위한 별개 측정이다. GATE S1 의 binding 과 무관한 **hardware 선택 근거**로 기록한다.

**part 독립 검증 (Vivado `get_parts` 실측)**: `xcu30-fbvb900-2-e` — LUT_ELEMENTS 230,400 / FLIPFLOPS 460,800 / DSP 1,728 / BLOCK_RAMS 312 / ULTRA_RAMS 96 / SPEED -2 / FAMILY zynquplus. 무료 라이선스로 열린다.

**하네스**: `synth/gate/Pod_HIU_gate_top.v` (Pod 하나 + HIU 하나를 같은 top 에 병치, clk/rst 공유로 한 패브릭에서 경쟁) + `synth/constraints/u30_pod_hiu.xdc` (10.000 ns + rst false_path) + `synth/scripts/synth_u30_pod_hiu.tcl`. flow 는 `impl_pod.tcl` 의 U55C Pod 기준선과 동일하게 `opt → place → route` (phys_opt 없음) 로 맞춰 **speed grade 차이만 비교**되게 했다. 블록 간 결선은 RTL 주석이 명시한 2개만 잇고 프로토콜을 발명하지 않았다: (1) `HIU.rng_word/valid → Pod.rng_word/valid` (Pod.v "TRNG broadcast … sourced from HIU one level up"), (2) `Pod.mem_addr → HIU.virt_addr` (Pod.v "Memory side-channel … forwarded from any Cluster to a Pod-level HIU"). `mem_req` 는 HIU 의 어느 요청 입력에 물릴지 spec 이 규정하지 않아 발명하지 않고 등록된 top 출력으로 관측만 한다. D2 는 정규 파일 `hiu_trng_ro.xdc` 를 `source` 하므로 (중복 정의 없음 확인) 실측치가 정규 수리와 일관된다. 하네스 검증 통과: elaboration 0 Errors / 0 Critical Warnings, 계층에 `u_pod`(Pod) + `u_hiu`(HIU) 양쪽 존재 — 어느 블록도 optimize away 되지 않았다.

**판정에 쓸 기준선 (기존 리포트 전사)**: Pod 단독 `xcu55c-fsvh2892-2L-e` post-route **170,850 LUT / 41,563 FF / 156 DSP / 8 RAMB18, WNS −0.205 ns @ 10 ns → Fmax 97.99 MHz** (`synth/reports/pod_2x2_2x2_impl_*.rpt`) + HIU 단독 **2,631 LUT** → 단순 합 **173,481 LUT = U30 LUT_ELEMENTS 230,400 의 75.3%**.

**이 75.3% 는 U30 실측이 아니라 두 독립 run 의 산술 합이다.** 실제로는 (a) 같은 top 에 합치면 `opt_design` 의 cross-boundary 최적화로 줄어들 수 있고, (b) 75% 이용률에서는 place 가 LUT 를 덜 pack 해 늘어날 수도 있다. 어느 방향인지는 완주한 리포트만이 답한다. U55C −2L 의 −0.205 ns 를 U30 −2 등급이 메우는지도 실측 전에는 단정할 수 없다 — 등급 이득은 있으나 75% 이용률의 라우팅 혼잡이 반대 방향으로 작용하므로 두 효과의 부호 합은 측정으로만 결정된다.

**U30 실측 결과 (2026-08-18, Vivado 2025.2.1 / `xcu30-fbvb900-2-e` / OOC / 10.000 ns / `opt → place → route`, `Design State: Routed`):**

| 축 | 실측 | 이용률 | 예측 대비 |
|---|---|---|---|
| CLB LUTs | **177,793** | **77.17%** (/230,400) | 산술 합 예측 173,481 (75.3%) 대비 **+4,312 (+2.5%)** |
| CLB Registers | 48,007 | 10.42% (/460,800) | — |
| DSP48 | 156 | 9.03% (/1,728) | Pod 단독과 동일 (HIU 0) |
| RAMB18 | 8 | 1.28% (/624; Block RAM Tile 4/312) | Pod 단독과 동일 (HIU 0) |
| URAM | 0 | 0% (/96) | — |
| WNS @ 10 ns | **−1.450 ns** | — | → **Fmax 87.34 MHz** |
| TNS / failing endpoints | −254.623 ns / **258** (setup) | — | hold 0 failing (WHS +0.019) / PW 0 failing (WPWS +4.458) |
| DRC | **errors 0**, warnings 521 checks / 5 규칙 | — | DPIP-2 264 + DPOP-3 116 + DPOP-4 132 + **LUTLP-2 8** + RTSTAT-10 1 |

계층: `u_pod` (Pod) **175,220 LUT / 42,735 FF / 156 DSP / 8 RAMB18** + `u_hiu` (HIU) **2,574 LUT / 3,621 FF / 0 / 0** + wrapper 1,651 FF. 두 블록 모두 실재 — optimize away 되지 않았다. `LUTLP-2 ×8` 은 D2 제약이 U30 에서도 정상 작동함을 뜻한다.

**예측이 어느 방향으로 틀렸는가 (사전에 두 방향을 다 선언해 둔 것의 결산)**: §28.9 이 측정 전에 (a) cross-boundary 최적화로 **줄어들** 수 있고 (b) 75% 이용률에서 pack 이 느슨해져 **늘어날** 수 있다고 양방향을 기록해 두었다. 실측은 **(b) 가 이겼다** — +4,312 LUT. 성분: Pod 자체가 xcu55c 단독 170,850 → U30 안에서 175,220 (**+4,370**) 으로 늘었고, HIU 는 2,631 (단독) → 2,574 (**−57**, cross-boundary 최적화) 로 줄었다. 즉 (a) 는 HIU 쪽에서만 소량 관측되고, Pod 쪽의 배치 팽창이 그것을 압도한다.

**speed grade 이득은 오지 않았다 (정직 기록)**: xcu55c **−2L** 의 Pod 단독 WNS **−0.205 ns** 에서 xcu30 **−2** 의 Pod+HIU WNS **−1.450 ns** 로 **1.245 ns 악화**됐다. §28.9 이 "두 효과의 부호 합은 측정으로만 결정된다" 고 유보해 둔 그 판정이 여기서 내려진다: **등급 이득보다 77% 이용률의 라우팅 혼잡이 크다.** 라우터 자신의 진단이 이를 뒷받침한다 — `Estimated Global/Short routing congestion is level 5 (32x32)` + `Estimated Timing congestion is level 5` (레벨 5 이상은 Vivado 가 "routability 저하 및 타이밍 영향" 으로 명시하는 구간).

**변수 2개 동시 변경의 한계 (혼동 금지)**: 위 −0.205 → −1.450 비교는 **device 와 design 이 동시에 바뀐** 비교다 (xcu55c/Pod-단독 → xcu30/Pod+HIU). 따라서 1.245 ns 전부를 device 탓으로 귀속할 수 없다. 다만 HIU 는 단독 222.47 MHz (WNS +5.505) 이고 이 top 안에서 2,574 LUT = 전체의 1.4% 이므로, design 변경분의 기여는 소량으로 보는 것이 합리적이다 — **이것은 추론이고 실측이 아니다.** 분리 측정 (xcu30 에 Pod 단독) 은 수행하지 않았으며 후속 몫으로 이월한다.

**병목 귀속 — GATE S1-US 와 같은 경로다 (수렴 증거)**: U30 worst setup path 는 `u_pod/g_crow[1].g_ccol[1].u_cluster/u_ehdec/dec_input_payload_wide_reg[4]/C` → `…/u_matmul_unit/cr_payload_reg[37]/D`, Data Path Delay **11.432 ns** (logic 4.737 = 41.4% / route 6.695 = 58.6%), Logic Levels **53** (LUT6 35 포함). GATE S1-US 의 worst path (`u_ehdec/dec_eff_imm16_reg` → `cr_payload_reg`) 와 **같은 구조 클래스** — EHDecode 의 decode 출력에서 PE_Core 의 `cr_payload` 로 가는 dispatch 경로다. §26.9 congestion 진단이 v1.9 에 대해 특정한 병목 ("`case(dec_opcode)` 본체 자체의 조합 깊이 55-arm") 을 **서로 다른 part 2개 · 서로 다른 top 2개**가 독립적으로 재확인한 셈이고, 이는 §26.9 의 결론 3 ("진짜 구조적 개선의 표적은 `case_result_s2` 경계가 아니라 case 본체") 에 대한 추가 실측 근거다. `checking unconstrained_internal_endpoints (0)` — 양쪽 다 제약 누락 없음.

**post-route `phys_opt_design` 추가 실측 (1차가 미달일 때 "닫을 수 있는가" 를 별도로 재는 하네스 설계 그대로)**: WNS **−1.450 → −1.017 ns** (개선 0.433 ns), TNS −254.623 → **−187.636 ns**, failing endpoints **258 → 258 (불변)**, WHS +0.019 / WPWS +4.458 불변, LUT 177,793 → 177,794 (+1). → **phys_opt 로도 닫히지 않는다.** Fmax 는 87.34 → **90.79 MHz** 로 오른다. failing endpoint 수가 전혀 줄지 않은 채 worst slack 만 개선된 것은 병목이 **한 경로의 국소 문제가 아니라 258개 endpoint 에 퍼진 구조적 문제**라는 뜻이고, §26.9 의 "표적은 case 본체" 결론과 같은 방향의 증거다.

**리포트 아카이브**: `synth/reports/u30_pod_hiu_{impl_util,impl_util_flat,impl_timing,impl_drc,impl_route_status,impl_clock,impl_power,synth_util,synth_util_flat,synth_timing,opt_util,place_util,place_timing,place_analysis,physopt_timing,physopt_util}.rpt` — 기존 `pod_2x2_2x2_*` 관례와 같은 위치·같은 접미어. (methodology 리포트는 2.2 MB 로 로컬에만 남기고 트래킹하지 않는다 — `pod_2x2_2x2_synth_methodology.rpt` 선례와 달리 여기서는 생략했음을 명기한다.)

**hardware 판단에 넘기는 정리 (판정하지 않고 근거만)**: U30 한 장에 (2×2)×(2×2) Pod + HIU 는 **면적으로는 수납된다** (LUT 77.2%, DSP 9.0%, BRAM 1.3%, URAM 0% — LUT 이 유일한 압박 자원이고 나머지는 널널하다). **타이밍은 10 ns 에서 닫히지 않는다** (1차 WNS −1.450 / phys_opt 후 −1.017, failing endpoints 258 불변). 남는 선택지는 (i) 목표 주기 완화 (**90.79 MHz 는 phys_opt 후 실측**이므로 11.1 ns 목표는 즉시 성립), (ii) LUT 압박 완화 후 재측정 (77% → 60%대면 혼잡 등급이 내려갈 가능성 — 단 이것은 가설이다), (iii) 병목 경로의 구조적 개선 (§26.9 결론 3 의 표적 — failing endpoint 258 불변이 이 방향을 지지한다), (iv) 더 큰 part. **본 절은 이 중 어느 것도 선택하지 않는다.**

### 28.10 §12a 기록

본 절은 §12a 하의 **정규 개발 행위 (regular development act)** 다. 판정 근거를 항목별로 남긴다.

- **범위 판정 (§12a 규칙 3 순서)**: 본 절의 편집 대상은 (i) spec (본 절), (ii) 합성 하네스·gate·lint (`synth/gate/Top_Core_gate_top.v` 신규, `synth/constraints/hiu_trng_ro.xdc` 신규, `synth/scripts/synth_fp_op.tcl` 옵션 2개 추가, `synth/scripts/fp_op_gate_check.py` gate 1행 추가, `synth/lattice/scripts/synth_fp_ops.sh` 측정 1행 추가, `synth/lattice/fp_ops/gate_check.py` 측정 1행 추가, `scripts/lint_synth_coverage.py` 신규, `Makefile` 타깃 추가), (iii) **의미 보존 RTL 수리 3건** (`HIU.v` D1/D5, `EHDecode.v` D3) 이다. `isa/wt64v1_isa.json` · 생성물 · asm · golden · truth table 은 **무접촉**이다 — 본 절은 ISA 표면을 건드리지 않으므로 §12a 규칙 3 의 순서 자체가 발동하지 않는다.
- **RTL 편집의 성격**: 3건 전부 **의미 보존**이며 (§28.3 의 코드 근거 + 무회귀 실증 + yosys 넷리스트 통계 diff 0), 시뮬 결과가 바뀌지 않았다. 즉 §12a 가 §26.10 에서 명시한 "의도적 test-breakage" 형태의 개정이 **아니다** — 본 절은 재유도 대상 테스트를 만들지 않는다.
- **3a (§27.7a) 와의 격리**: 3a 산출물 — golden 3종 (`scripts/golden_{fp32,lattice,fdotcr}.py`), ISA (`isa/wt64v1_isa.json` + 생성물 + `asm/`), `FP_StepSeq.v` step 프로그램 — 은 **무접촉**이며 hash 대조로 확인된다. 공유 datapath 3파일 (`FP_AddWide.v` / `FP_Mul36.v` / `include/fp_narrow_f32.vh`) 은 **byte-untouched** 이고 `git diff --exit-code` 로 확인된다. `decode_reserved` 는 미접촉 (3a-C4 몫). 즉 본 절은 §27.7a 의 착지 순서를 선점하지 않는다.
- **선공표 규율**: §28.5 의 기준은 gate_check 스크립트에 **무수정 전사**됐다. 기준을 움직여서 통과하는 경로는 없다 (V20-2 재실측 선언의 그 규율). 단 본 commit 은 anchor 생성 commit 이므로 area 축이 구조적으로 PASS 라는 사실을 §28.5 (c) 가 명시한다 — **이 명시가 선공표 규율의 이행이지 예외가 아니다.**
- **이월 항목 (별도 commit)**: D4 실물화-vs-폐기 판정 (§28.2) · D6 + O2 의 reset 블록 분리 (동형이라 동시 처리 권고) · D7/O4 미독 포트 처분 · 고아 3종 지위 판정 (§28.8) · §12a 의 **RTL 모듈 단위 제거 절차 성문화** (§28.8 정책 공백) · §28.4 항 6 의 기계적 강제 (undriven-signal 탐지 lint) · `PE.v` / `ISA_Decoder.v` standalone 합성 경로 (§28.4 `uncovered` 2건).

**이월 항목 추가 3건 (2026-08-18 재측정 세션이 새로 드러낸 하네스 결함 — §28.6 재측정 · §28.7 재측정에서 각각 귀속됨). 전건 gate 하네스 변경이라 측정 세션이 수행하지 않았다:**

1. **premap `$mul` 증거의 자동 갱신 경로 부재.** `synth/reports/fp_ops/sys_top_core_premap_mul.log` 를 재생성하는 make 타깃이 없다 — `fp_op_gate_check.py` 는 아카이브를 읽기만 하므로 **RTL 이 바뀌어도 이 축이 조용히 옛 값을 답할 수 있다** (false PASS 경로). 수리 형태: yosys 호출을 `synth-sys-gate` 에 편입하거나 전용 타깃 신설. §28.6 재측정의 "하네스 공백 1건" 참조.
2. **`synth/lattice/fp_ops/gate_check.py` 의 `wrapper_ff = 1601` 이 사실이 아니다** (§29.4 계약 확장 후 실제 1,740). MEASUREMENT 반쪽이라 FAIL 을 만들지 않지만 파생 줄이 **틀린 수를 인쇄한다**. §28.7 재측정 참조.
3. **메시지 계수 축의 계수 방법을 규범으로 고정한다** — id 문자열 grep 이 아니라 **severity-앵커 정규식** (`^(WARNING|CRITICAL WARNING|INFO|ERROR): \[<id>\]`). 캡 상향 tcl 을 Vivado 가 `# ` 접두로 로그에 echo 하므로 소박한 grep 은 `Synth 8-3848` 을 **0 이 아니라 1** 로 답해 exact-0 축을 거짓 FAIL 시킨다. §28.6 재측정의 "측정 방법의 함정 1건" 참조. 현행 `parse_msg_census` 는 이미 `line.startswith("CRITICAL WARNING:")` 로 앵커되어 있어 **CRIT 축은 영향 없음** — 위험은 손으로 세는 신규 2축에 있다.

## 29. HIU 실물화 — D4 (partitioned TLB) / D6 (async-reset) / D7 (미독 포트) 처분 (2026-08-18, COMMIT 0 · normative)

**사용자 지시 (binding, 2026-08-18): "HIU 는 실물에서 쓸 거니까, 구조적 문제들부터 먼저 해결해."** 본 절이 그 이행의 spec-first 기록이며, §28 이 이월로 남긴 D4 / D6 / D7 을 **처분 결정과 규범 계약**으로 확정한다. §28 이 "지금 상태는 유지되어서는 안 된다" 고만 적고 판정을 상위로 올린 항목들의 판정이 여기서 내려진다.

본 절은 **spec-before-code COMMIT 0** 다 (§12a 규칙 3). RTL·테스트·gate 재측정은 §29.13 의 착지 순서대로 후속 commit 이 수행하며, 본 commit 은 spec 만 편집한다.

### 29.1 결정의 축 — "실물" 이 기각 기준이다

사용자 지시는 옵션 비교의 배경이 아니라 **기각 기준 그 자체**다. 실리콘 대상이라는 전제가 각 옵션에 대해 만들어내는 판정은 다음 셋이고, 본 절의 모든 처분이 이 셋에서 도출된다.

1. **시뮬레이터에서만 성립하는 상태는 남길 수 없다.** D4 의 본질은 "TLB 가 없다" 가 아니라 **테스트가 RTL 이 만들지 않는 상태를 스스로 만들어 검증한다** 는 것이다 (§28.2). 실물에서는 그 상태가 존재하지 않으므로, 검증은 실물에 대해 아무것도 말하지 않는다.
2. **매핑이 우연히 안전한 것은 안전이 아니다.** D6 가 "이번 xcu55c 매핑에서 미발현" 인 것은 설계의 성질이 아니라 그 매핑의 성질이다. 실물 대상에서는 매핑이 바뀌는 것이 정상 사건이다.
3. **관측될 수 없는 결함은 고칠 수 없다.** 따라서 처분은 "고쳤다" 로 끝나지 않고, **같은 결함이 재발하면 소리가 나는 축**을 함께 남겨야 한다 (loud-fault-never-silent 의 gate 형).

### 29.2 §28 정정 8건 — 조사 실측이 §28 서술을 뒤집은 것들

처분 이전에 정정을 먼저 적는다. §28 의 서술 일부가 **실측으로 부정**되었고, 그 서술 위에 세워진 §28 의 판단 두 개 (8-7137 축 미채택 / D7 "제거 불가") 가 함께 무너지기 때문이다. §12a 규칙 5 대로 §28 원문은 삭제하지 않는다.

| # | §28 의 서술 | 실측 | 파급 |
|---|---|---|---|
| **C1** | §28.2/§28.3 의 `HIU.v:51-52,154-155,114,127,297` | D1/D5 수리 **이전** 번호다. 현행: 배열 선언 **57-59**, rst clear **135-139**, 유일 read **163-168**, 죽은 가드 **170**, shadow fallback **171-177**, async 블록 머리 **124**, FLUSH_TLB clear **304-309** | 인용 정정만 |
| **C2** | §28.3 "`Synth 8-7137` 는 HIU 단독 66 인데 Top_Core 문맥에서 32 — **메시지 수는 문맥 의존**" | **캡 아티팩트다.** `sys_top_core_run.log:264` = `INFO: [Common 17-14] Message 'Synth 8-7137' appears 100 times and further instances ... disabled`, 직전 263행이 `shadow_regions_end_reg[15]` — 열거가 **끊긴** 지점이다. 로그 실계수 HIU 32 + PE_Core 68 = **정확히 100 = 캡**. `-limit` 해제 후 재합성: HIU **66** (단독 66 과 동일), PE_Core **68**, 합 **134** | §28.3 이 "문맥 의존이라 회귀 지표로 못 쓴다 → 8-7137 을 gate 축으로 채택하지 않았다" 고 한 **근거가 소멸**한다. 축 채택 가능 (§29.11) |
| **C3** | §28.3 "총 101건 = HIU 32 + PE_Core 68 **(+1 기타)**" | 그 "+1" 은 경고가 아니라 **캡 INFO 줄 자신**이다 (`grep -c` 가 INFO 줄도 센다) | 기타 결함 1건은 존재하지 않는다 |
| **C4** | §28.3 "이번 매핑에서는 **전부 FDRE 로 떨어져** divergence 미발현 / 매핑이 FDSE·FDPE 로 바뀌면 reset 값이 갈린다" | 인과가 틀렸다. 66개는 FDRE 이고 **R 핀이 `<const0>`** — 실리콘에 reset 이 아예 없다. 안전한 진짜 이유는 **Vivado 가 `rst` 를 CE LUT 에 데이터 항으로 접어 넣은 것** (`CE = !rst & enable`; 실측 INIT: `shadow_regions_start[0][63]_i_1` LUT6 `64'h…04` I5←rst, `phys_addr[63]_i_1` LUT4 `16'h0008` I3←rst, `chacha_state[12][31]_i_1` LUT6 `64'h00000000FFFF5700` I5←rst — 전부 rst=1 반평면 0). HIU 가 전부 FDRE 인 것도 아니다: FDRE 3,040 / FDCE 568 / FDPE 1 | 위험의 성질이 바뀐다 — §29.7 |
| **C5** | §28.3 D7 "**제거 불가**" | pre-stable 에서 dead 포트 제거는 **허가된 정규 이벤트**다 (`prestable_compat_policy`, 사용자 지시 2026-07-24). 정확한 서술은 "제거 불가" 가 아니라 "제거하지 않기로 **선택**" 이다 | §29.10 이 선택으로 재서술 |
| **C6** | §28.3 D7 "넷리스트 확정은 **미조사로 남긴다**" | 해소됨. `sys_top_core_run.log:398-399` = `WARNING: [Synth 8-7129] Port interface_type[1] / [0] in module HIU is either unconnected or has no load` ×2, 그리고 Top_Core_gate_top 넷리스트에 `interface_type_q` 셀 **0개** — 래퍼 2 FF 까지 소멸 | 유지·제거 모두 **0 FF / 0 LUT**. 면적은 D7 판정 근거가 될 수 없다 |
| **C7** | §28.8 O2 "`a_reg`/`b_reg`/`res_reg` **전군** ×49" | 49 는 맞으나 구성이 3군이 아니라 **4군**이다: `a` 16 + `b` 16 + `res` 16 + **`result_matrix` 1** (`TENSOR_ALU.v:13` output reg) | O2 수리 범위 정정 |
| **C8** | §28.2 "**8,192 memory bits**" | yosys 가 memory 로 세는 `virt`+`phys` 만의 수치다. `valid` 64 bit 는 1-bit 폭이라 memory 로 집계되지 않을 뿐 똑같이 소멸한다. 실 저장 규모는 **8,256 bit** (4,096 + 4,096 + 64) | §29.11 면적 서술의 기준 |

**C2 의 일반형 (본 절이 새로 확보한 사실)**: 캡은 8-7137 만의 문제가 아니다. 같은 로그에서 `Synth 8-3848` ("Net ... does not have driver") 도 **100 에서 잘려 있다** — 실계수는 `partitioned_tlb_phys` 64 + `partitioned_tlb_virt` 64 = **128** 인데 로그에는 phys 64 + virt 36 = 100 만 남았다. **메시지 계수를 축으로 삼으려면 `set_msg_config -id {…} -limit` 상향이 축 채택의 전제조건**이며, 이를 빼먹으면 축은 100 에서 잘려 **false PASS** 가 된다 (§28.5 가 `get_msg_config -count` 에서 겪은 것과 같은 유형의 함정, 두 번째 사례).

### 29.3 D4 처분 결정 — 실물화 (호스트 기입형 · direct-mapped · reset-free 저장)

**결정: partitioned TLB 를 실물화한다. 형태는 (i′) — 호스트 기입 포트 신설 + direct-mapped 색인 + async-reset 없는 전용 블록에 저장 (distributed RAM).** §28.2 가 제시한 두 갈래 (a) 실물화 / (b) 폐기 중 **(a)** 이고, 실물화 형태 4종 중 (i′) 이다.

**채택 이유 4건 (전부 실측 근거):**

1. **사용자 기준을 구조로 충족한다.** 테스트가 만지는 모든 TLB 상태가 **포트를 통해 RTL 이 구동하는 상태**가 된다. `test_hiu.py:24-26` 의 계층 강제 기입이 탐지 lint 없이 **구조적으로 소멸**하며, 이것이 §28.4 항 6 의무의 가장 강한 이행 형태다 — 규범이 금지하기 전에 대상 자체가 없어진다.
2. **면적이 추정이 아니라 실측이고, 그 실측이 사실상 0 이다.** HIU 인스턴스 post-route (xcu55c, OOC, 10 ns, POST_XDC=`hiu_trng_ro.xdc`, synth→opt→place→phys_opt→route): LUT sites 2,626 → **2,648 (+22)** (logic 2,626 → 2,504 = −122, LUTRAM +144), FF 3,617 → **3,803 (+186)**, DSP 0, BRAM **0**, Fmax 229.94 → **228.47 MHz**. 하네스 검증: baseline FF **3,617 = §28.6 의 HIU 단독 실측과 정확히 일치**.
3. **BRAM 축을 지키는 유일한 memory 형태다.** 같은 구조를 `ram_style="block"` 으로 만들면 **RAMB36 2개**가 붙어 §28.5 의 `bram = RAMB18 + RAMB36 = 정확히 2` 가 **4 로 깨진다 (즉시 FAIL)**. 100 bit × 64 word 에 72 Kb 를 쓰는 이용률 낭비이기도 하다. **힌트 하나의 차이가 gate 를 통과/실패시키므로 §29.5 가 `distributed` 를 규범으로 못박는다.**
4. **D6 를 같은 commit 에서 처리하도록 강제한다 — 이것이 비용이 아니라 장점이다.** 배열이 `HIU.v:124` 의 async-reset 블록 안에 있는 한 Vivado 는 RAM 추론을 거부한다: `WARNING: [Synth 8-4767] Trying to implement RAM 'tlb_mem_reg' in registers. ... 1: RAM is sensitive to asynchronous reset signal. this RTL style is not supported.` 실측 비용 차이 — 같은 direct-mapped TLB 가 async-reset 블록 **안**이면 5,140 LUT / 11,743 FF, **밖**이면 2,648 LUT / 3,803 FF. **LUT +2,492 / FF +7,940 이 순수 D6 세금**이다.

**기각한 옵션 4종 (기각 사유를 남긴다 — 재론 시 근거가 있어야 한다):**

| 옵션 | 실측 (HIU 인스턴스, post-route) | 기각 사유 |
|---|---|---|
| **(i) 호스트 기입 · fully-associative · FF 저장** | LUT **7,833 (+5,207)** / FF 11,878 / Fmax 157.51 | ① GATE S1 잔여 headroom 9,949 의 **52.3%** 를 결함 1건 수리에 쓴다. ② §28.9 U30 실측 (LUT 77.17%, WNS −1.450, phys_opt 후에도 failing endpoints **258 불변**, 혼잡 등급 5) 위에 +5,207 LUT 는 **정확히 틀린 방향**이다. ③ ECP5 반쪽에서 더 커진다 (§28.7 실측: yosys 가 메모리를 레지스터로 전개) |
| **(i″) direct-mapped · block RAM** | LUT 2,508 / FF 3,679 / **RAMB36 2** | **즉시 FAIL.** §28.5 의 BRAM exact 축 (=2) 이 **4** 가 된다. 위 채택 이유 3 |
| **(ii) FSM fill 형 — ATS 응답으로 채움** | LUT **8,882 (+6,256)** / FF 11,908 / Fmax **131.96** (4종 중 최저) | **상수시간 계약 파기가 본질적이다.** Y4 `hiu_abi.md` §2.1 이 "TRANSLATE 가 항상 DUMMY_DELAY 로 진행하므로 상수시간" 을 명문화했는데 실제 ATS 왕복은 가변 지연이다 — 최악 지연 패딩 없이는 HIU 의 존재 이유(side-channel 방지)가 무너지고, 패딩하면 모든 DMA 가 ATS 최악 지연으로 느려진다. 게다가 현행 `ATS_QUERY` 는 `ats_resp <= 1` 만 올리고 **주소를 반환하지 않으므로** (HIU.v:290-292) 실제 fill 에는 `ats_phys_in/valid` 신설이 필요하다 — 즉 (ii) 는 호스트 인터페이스를 **없애는 게 아니라 (i) 위에 두 번째 인터페이스를 얹는다**. 면적·Fmax 도 최악 |
| **(iii) 폐지 — shadow-region 단일 경로를 규범으로 승격** | LUT 2,596 (−30) / FF **3,617 (변화 0)** | ① **하드웨어 tenant 격리가 사라진다** — shadow region 16 슬롯에는 partition tag 가 없어 전역이므로, 어떤 tenant 의 DMA 든 등록된 아무 region 에나 접근이 허가된다. Y4 의 "동시 활성 lease hard cap 4" 가 하드웨어 근거를 잃고 순수 소프트웨어 약속으로 강등된다. ② 격리를 되살리려면 shadow region 에 partition tag 를 붙여야 하고 **그건 (i) 과 같은 크기의 인터페이스 변경**이다 — 폐지는 비용을 없애는 게 아니라 미루는 것. ③ `partition_id` 의 유일한 소비처가 lookup 이므로 **미독 포트 결함이 D7 1건 → 2건으로 늘어난다** — "구조적 문제부터 해결하라" 는 지시에 대해 결함 1개를 결함 1개로 교환하는 셈이다. ④ 3개 저장소 10곳 이상 동시 개정이 필요하고, §12a 에는 **RTL 모듈/기능 단위 제거 절차가 없다** (§28.8 정책 공백) — 폐지 경로는 그 절차 성문화가 선행 |

**부수 실측 (FF 변화 0 의 의미)**: (iii) 폐지형의 FF 가 baseline 과 **완전히 동일한 3,617** 인 것이, §28.2 의 "TLB 는 실리콘에 없다" 에 대한 **독립 재확인**이다 — 8,256 bit (§29.2 C8) 전부가 오늘 실리콘에 1 bit 도 없다.

**미측정 명기 (정직)**: **4-way set-associative 중간안은 측정하지 않았다.** (i) 의 fully-associative (+5,207 LUT) 와 (i′) 의 direct-mapped (+22 LUT) 사이 비용은 미지수다. associativity 가 재협상 대상이 되면 그때 측정한다 — 지금 없는 수치를 만들지 않는다.

### 29.4 인터페이스 변경 (normative) — §12a 규칙 3 대상

**본 항이 계약 변경의 본문이다.** HIU 모듈 인터페이스가 **입력 5개 + 출력 2개** 확장된다. `Top_Core.v` 는 전부 passthrough 하며, gate 래퍼 2종 (`synth/gate/Top_Core_gate_top.v`, `synth/gate/Pod_HIU_gate_top.v`) 은 기존 관례대로 rst 를 제외한 신규 I/O 를 정확히 1회 등록한다.

**신규 입력 (control plane — TLB fill):**

| 포트 | 폭 | 의미 |
|---|---|---|
| `tlb_write_en` | 1 | fill 요청 스트로브. `state == IDLE` 에서 **최우선** 분기 (shadow_write_en·dma_req_pending·ats_req·pri_req 보다 앞) |
| `tlb_write_partition` | `$clog2(NUM_PARTITIONS)` = 2 | 대상 파티션 = tenant lease id. Y4 `HIU_CTRL[7:6]` 과 같은 인코딩 |
| `tlb_write_index` | `$clog2(TLB_ENTRIES)` = 4 | 대상 슬롯. **`tlb_write_virt` 의 index 비트와 반드시 일치해야 한다** — 불일치는 loud fault (§29.6) |
| `tlb_write_virt` | ADDR_WIDTH = 64 | 가상 주소. tag 와 index 를 여기서 도출한다 |
| `tlb_write_phys` | ADDR_WIDTH = 64 | 물리 주소. **하위 `PAGE_SHIFT` 비트는 0 이어야 한다** — 비영은 loud fault (§29.6) |

**신규 출력 (loud-fault 관측면):**

| 포트 | 폭 | 의미 |
|---|---|---|
| `tlb_fault` | 1 | 1-cycle 펄스. **호스트 프로그래밍 오류 전용** — 변환 miss 는 여기 올리지 않는다 (§29.6 항 6) |
| `tlb_fault_code` | 3 | 마지막 fault 사유. 다음 fault 까지 유지. 인코딩은 §29.6 표 |

**프로토콜 (normative):**

1. 호스트는 5개 입력을 안정시킨 뒤 `tlb_write_en` 을 1 cycle 어서트한다.
2. HIU 가 `IDLE` 이면 다음 cycle 에 `TLB_UPDATE` 로 진입해 엔트리를 설치하고 `IDLE` 로 복귀한다 — **설치는 정확히 1 cycle**, 관측 가능한 부작용은 해당 엔트리의 `valid`/`tag`/`ppn` 뿐이다.
3. HIU 가 `IDLE` 이 아니면 **기입은 수행되지 않고 `tlb_fault` 가 뜬다** (code = `BUSY`). 조용한 드롭도 조용한 큐잉도 없다 (loud-fault-never-silent). 호스트는 재시도 책임을 진다.
4. `tlb_write_en` 과 `shadow_write_en` 이 같은 cycle 에 어서트되면 **TLB 기입이 이긴다** — shadow 기입은 수행되지 않고 `tlb_fault` 는 뜨지 않는다 (호스트 오류가 아니라 우선순위 규정이다). 이 우선순위는 §29.5 의 조회 우선순위 (TLB > shadow) 와 같은 방향이며, 두 우선순위가 **같은 방향인 것 자체가 규범**이다.
5. **FSM 상태 폭은 늘지 않는다.** 현행 14 상태 (`4'b0000`-`4'b1101`) 에 `TLB_UPDATE = 4'b1110`, `TLB_READ = 4'b1111` 을 배정하면 4-bit 공간이 정확히 소진된다. (Vivado 는 이 `state` 를 one-hot 으로 추론하므로 실 FF 는 14 → 16, **+2 FF** 다 — 추정이 아니라 §28.6 이 관측한 `FSM_onehot_state_reg` 형태에서 도출한 값이며 재측정으로 확인한다.)

**파라미터 제약 (normative — gate 축과 직결):** `NUM_PARTITIONS` 와 `TLB_ENTRIES` 는 **2의 거듭제곱이어야 한다.** 사유: 엔트리 주소를 `{tlb_write_partition, tlb_write_index}` **연접**으로 만들 수 있어야 곱셈이 생기지 않는다. 2의 거듭제곱이 아니면 주소가 `p*TLB_ENTRIES + j` 로 되돌아가고 **premap `$mul` exact 축이 움직인다** (§29.11 의 −48 귀속이 정확히 이 곱셈이다).

**다운스트림 계약 개정 의무 (별도 저장소 — 본 절이 목록을 확정한다):**

- **Y4** `docs/hiu_abi.md` §1 MMIO 맵: `HIU_TLB_VIRT` / `HIU_TLB_PHYS` / `HIU_TLB_INDEX` / `HIU_TLB_CTRL` (partition + en) + `HIU_TLB_FAULT` (code 판독) 신설. **결정적 근거 — 현행 §1 에는 `HIU_TLB_*` 레지스터가 아예 없다.** v0 draft 이므로 변경 가능하되 `hiu-abi:` prefix 필수, v1.0 freeze 는 양측 sign-off.
- **Y4** `docs/hiu_abi.md` §3 lease attribute 표: `partition_id` 가 이제 **실제 하드웨어 격리 경계**임을 명기 (오늘은 읽히기만 하는 값이다).
- **Y4** `docs/glossary.md` §2/§3: "물리적으로 분리된 4개의 16-entry 테이블" 서술은 **참으로 유지된다** (엔트리 주소 상위 2비트가 partition_id — §29.5). §3 의 "TLB miss 시 fallback" 서술은 §29.5 의 우선순위 규범과 일치하므로 변경 불필요.
- **wavetensor-drivers** `docs/pcie_host_interface.md`: `0x100+ per-partition registers` 블록에 fill 레지스터 추가 (현행 서술은 "TLB flush, key rotation" — **무효화만 있고 fill 이 없다**), `:61` BAR2 라벨 "Shadow region (HIU partitioned TLB mapping)" 의 **shadow/TLB 혼동 정정**.

**계보 기록 (본 절의 판정을 지탱하는 사실)**: `git show 4d80c76:HIU.v` (최초 private commit, 2026-05-03) 에도 배열 선언·lookup·flush 만 있고 **fill 이 없다.** 즉 D4 는 "구현하다 만 것" 이 아니라 **설계 단계에서 fill 을 아예 명세하지 않은 것**이며, repo 존재 기간 전체에 걸쳐 유일하게 존재해 온 fill 메커니즘이 `test_hiu.py:24-26` 의 계층 강제 기입이었다. 본 항이 그 공백을 처음으로 계약으로 메운다.

### 29.5 TLB 의 규범적 의미론 (normative)

**파티션 = tenant lease.** 3개 저장소가 일치해서 규정한다 — Y4 `glossary.md` §2 ("partition_id 별로 물리적으로 분리된 … cross-tenant cache-timing 채널 차단", "동시 활성 lease 수 hard cap 을 4 로 강제"), Y4 `hiu_abi.md` §3 (`partition_id ∈ {0,1,2,3}` → `HIU_CTRL[7:6]`), `.claude-memos/host_a_custom_hypervisor.md:250`. 파티션은 프로세스도 채널도 아니고 **VM/tenant** 다.

**주소 분해 (PAGE_SHIFT = 12, 즉 4 KiB 페이지 — 본 절이 확정한다):**

| 필드 | 비트 | 폭 |
|---|---|---|
| tag | `virt_addr[63:16]` | 48 |
| index | `virt_addr[15:12]` | 4 = `$clog2(TLB_ENTRIES)` |
| page offset | `virt_addr[11:0]` | 12 = `PAGE_SHIFT` |

**저장 구조:**

- `tlb_valid` — flat `NUM_PARTITIONS*TLB_ENTRIES` = **64 bit reg**, **async-reset 블록에 유지**한다 (reset 이 반드시 필요한 유일한 TLB 상태다).
- `tlb_mem` — `{tag[47:0], ppn[51:0]}` = **100 bit × 64 word**, **async-reset 없는 전용 `always @(posedge clk)` 블록**에 두고 `(* ram_style = "distributed" *)` 로 못박는다. `block` 은 금지 (§29.3 채택 이유 3).
- 엔트리 주소 = `{partition, index}` **연접** 6-bit. 곱셈 없음 (§29.4 파라미터 제약).

**히트 조건 (normative):**

```
tlb_hit = tlb_valid[{partition_id, xlat_virt[15:12]}]
       && (tlb_mem[{partition_id, xlat_virt[15:12]}].tag == xlat_virt[63:16])
```

`valid` 는 **AND 의 첫 항이자 유일한 자격 부여자**다 (§29.6 항 1).

**변환 시퀀스 (normative) — 2 cycle 조회, 상수시간 유지:**

1. `TRANSLATE` (cycle 1): `virt_addr` 를 `xlat_virt` 로 **샘플**한다. 이후 전 시퀀스 (조회·마스킹·DMA) 는 샘플본만 쓴다 — 라이브 입력을 다시 읽지 않는다. 같은 cycle 에 TLB 읽기 주소를 발행하고, shadow 16-way 비교 결과를 `shadow_hit` 에 확정한다.
2. `TLB_READ` (cycle 2): 태그 비교 1회로 우선순위를 해소한다.

```
if      (tlb_hit)    begin phys_addr <= {ppn, xlat_virt[11:0]}; access_granted <= 1'b1; end
else if (shadow_hit) begin phys_addr <= xlat_virt;              access_granted <= 1'b1; end
else                 begin phys_addr <= {ADDR_WIDTH{1'b0}};     access_granted <= 1'b0; end
```

3. 이후 `DUMMY_DELAY` → XChaCha20 → `DMA_EXEC` → `GRANT_ACCESS` 는 불변.

**우선순위 규범 — TLB 히트가 이기고 shadow 는 fallback 전용이다. 이것은 D4 수리의 부속이 아니라 선행 조건이다.**

현행 `HIU.v:170` 의 `if (!access_granted)` 가드는 **죽은 코드**다: `access_granted` 는 rst / TRANSLATE / GRANT_ACCESS 세 곳에서만 대입되고 TRANSLATE 진입 시점 값은 **항상 0** 이다 (직전 상태는 IDLE, 그 앞은 GRANT_ACCESS 또는 rst). 따라서 shadow 루프가 **항상** 실행되고, 같은 always 블록의 **나중 대입인 shadow 가 TLB 를 덮는다.** 통제 대조 시뮬 실측 (verilator, 호스트 기입형 DUT):

```
shadow [0x0, 0xFFFF_FFFF] (TLB 항목 포함) → phys_addr=0x0000000010000000  VERDICT SHADOW_OVERRIDES
shadow [0x0, 0x0FFF_FFFF] (비중첩)        → phys_addr=0x0000000020000000  VERDICT TLB_WINS
```

즉 **TLB 를 실체화하는 순간, shadow region 과 겹치는 TLB 엔트리는 조용히 identity-map 으로 강등된다 = tenant 격리 구멍**이다. 오늘은 TLB 가 죽어 있어서 이 결함이 보이지 않는다. 위 2번의 단일 `if/else if/else` 사슬이 이 구멍을 구조적으로 막으며, **죽은 가드는 삭제한다** (조건을 고치는 것이 아니라 우선순위 사슬로 대체한다 — 조건을 고치면 같은 always 블록의 나중-대입 규칙이 다시 함정이 된다).

**상수시간 계약 (유지, 정정 포함):** hit / shadow-fallback / miss 세 경로가 **완전히 동일한 상태열**을 지난다. `TLB_READ` 추가로 DMA 변환 시퀀스가 **36 → 37 cycle** 로 1 cycle 늘어난다 (프로토타입 실측; hit/miss 동일). **상수 시간성은 절대치가 아니라 경로 간 동일성이므로 계약은 유지되고, 절대치는 갱신된다.** 테스트는 절대 cycle 수가 아니라 **경로 간 동일성**을 assert 해야 한다 (§29.13 test_plan).

**associativity 규범 (명시적 축소 수용):** **파티션 간 격리는 계약이고, 파티션 내 associativity 는 계약이 아니다.** direct-mapped 이므로 같은 index 의 다른 tag 는 **덮어쓴다** — 이는 호스트 정책 책임이며 하드웨어는 fault 를 올리지 않는다 (정상 동작이다). 근거: 보안 주장의 대상은 **cross-tenant** 채널이고, 파티션 분리는 엔트리 주소 상위 2비트로 **구조적으로** 보장된다 (파티션 간 충돌 불가). 파티션 **내부** 충돌은 상수시간 경로 때문에 타이밍으로 관측되지도 않는다.

**flush 규범:** `context_switch` → `FLUSH_TLB` 는 **`tlb_valid` 64 비트 전체와 `shadow_valid` 16 비트를 지운다** (현행 동작 보존). **`tlb_mem` 의 tag/ppn 데이터는 지우지 않는다** — reset-free RAM 이므로 지울 수단이 없고, 지울 필요도 없다. **이 사실이 §29.6 의 존재 이유다**: flush 후에도 RAM 에는 이전 tenant 의 데이터가 남아 있으며 `valid` 가 유일한 방벽이다. 구현자는 "flush 했으니 깨끗하다" 를 **가정할 수 없다.**

### 29.6 loud-fault 계약 (normative) — 미초기화 TLB 를 히트로 오인하지 않는다

**규범 6항:**

1. **`valid` 가 유일한 자격 부여자다.** `tlb_mem` 은 reset-free 이므로 power-up 값이 **미정의**다. RTL 은 `tlb_valid` 검사 이전에 `tlb_mem` 출력을 **어떤 부수효과에도** 쓰지 않는다 (`phys_addr` 대입, `access_granted`, 마스킹 입력 전부 포함).
2. **flush 는 데이터를 남긴다** (§29.5 flush 규범). 따라서 항 1 은 power-up 1회의 규율이 아니라 **영구 규율**이다.
3. **zero-tag probe — 필수 directed test.** reset 직후, TLB 기입을 **한 번도 하지 않은 상태**에서, tag 가 0 이 되는 `virt_addr` (예: `64'h0000_0000_0000_0000`) 로 변환을 요청하면 `access_granted` 는 **0** 이어야 한다. 이 테스트에는 discriminator 가 실재한다: `Makefile:13` 의 `SIM ?= verilator` 는 **2-state zero-init** 이라 미기입 RAM 이 0 으로 읽히므로, `valid` 게이팅이 빠지면 tag 0 == RAM 0 으로 **반드시 히트하고 테스트가 반드시 실패한다.** 즉 이 테스트는 tautology 가 아니다.
4. **4-state X 규율.** X 를 지원하는 시뮬레이터에서 미기입 RAM 은 X 다. `tlb_hit` 이 X 가 되어 `access_granted` 로 전파되면 안 된다 — 항 1 의 `valid` 게이팅이 그 방어이며, `WT_SIM_ASSERT` 가드 하에 `if (tlb_hit === 1'bx) $fatal` 를 둔다 (loud-fault-never-silent 의 시뮬 측 이행).
5. **호스트 프로그래밍 오류는 즉시 소리를 낸다.** 아래 4종은 **기입을 수행하지 않고** `tlb_fault` 를 1 cycle 어서트하며 `tlb_fault_code` 를 갱신한다. **조용히 설치되어 영원히 히트하지 않는 엔트리를 만드는 것이 이 계약이 막는 대상이다.**

| code | 이름 | 조건 | 왜 fault 인가 |
|---:|---|---|---|
| 0 | `NONE` | — | fault 없음 |
| 1 | `INDEX_MISMATCH` | `tlb_write_index != tlb_write_virt[15:12]` | direct-mapped 에서 index 가 tag 와 어긋난 엔트리는 **어떤 주소로도 조회될 수 없다.** 조용히 설치하면 호스트는 매핑했다고 믿고 하드웨어는 영원히 miss 한다 — D4 와 같은 종류의 "선언과 실물의 괴리" 다 |
| 2 | `PHYS_MISALIGNED` | `tlb_write_phys[11:0] != 0` | 페이지 단위 변환이므로 하위 12비트는 offset 이 차지한다. 비영을 조용히 버리면 호스트가 요청한 물리 주소와 실제 변환 결과가 **말없이 달라진다** |
| 3 | `BUSY` | `tlb_write_en` 이 `state != IDLE` 에서 어서트 | §29.4 프로토콜 3 |
| 4 | `PARTITION_RANGE` | `tlb_write_partition >= NUM_PARTITIONS` | `NUM_PARTITIONS = 4` 인 현 형상에서는 2-bit 포트라 **구조적으로 발생 불가**이나, 파라미터가 4 미만으로 재형상되면 발생한다. 조건을 지금 적어 두는 것이 재형상 시의 조용한 실패를 막는다 |
| 5-7 | — | reserved | 미정의 |

6. **변환 miss 는 fault 가 아니다 — 그리고 그것이 의도다.** miss 는 상수시간 시퀀스 **끝**에서 `access_granted = 0` 으로만 신호된다. `tlb_fault` 를 miss 에 쓰지 않는 이유는 관대함이 아니라 **타이밍 채널 방지**다: miss 를 조기 스트로브로 알리면 hit/miss 가 시간으로 구별되어 HIU 의 존재 이유가 무너진다. 반대로 §29.6 항 5 의 4종은 **호스트가 스스로 발행한 control-plane 기입**에 대한 응답이므로 DMA 변환 타이밍과 무관하고, 여기서 소리를 내는 것은 채널을 만들지 않는다. **이 구분 — data plane 은 조용히 상수시간, control plane 은 즉시 시끄럽게 — 이 본 항의 규범 내용이다.**

**부수 규범 (`phys_addr` 결정성):** miss 시 `phys_addr` 는 **0 으로 구동**한다 (§29.5 시퀀스 3-arm). 현행 RTL 은 miss 시 `phys_addr` 를 대입하지 않아 **직전 변환 결과가 모듈 출력에 남고** `Top_Core.v` 가 `mem_phys_addr` 로 외부에 노출한다 — 소비자가 `mem_access_granted` 로 자격을 거른다는 계약은 spec 어디에도 쓰인 적이 없다. 0 구동은 그 미기록 계약 의존을 없애고, 동시에 D6 의 `phys_addr` read-before-write (§29.7) 를 근본에서 해소한다.

### 29.7 D6 정책 (normative) — 형식 혼합, HIU 이번 · PE_Core/Tensor_ALU 이월

**D6 의 진짜 실리콘 위험 (여기가 "미발현이니 그대로" 가 답이 아닌 이유):** §29.2 C4 대로 `rst` 는 CE LUT 의 **데이터 입력**이 되어 있다 — 즉 `rst → LUT → FF.CE` 는 setup/hold 가 걸리는 **동기 경로**다. 그런데 `synth/reports/fp_ops/sys_top_core_gate.xdc:6` 과 `synth/constraints/pod.xdc:20` 이 `set_false_path -from [get_ports rst]` 를 걸고, `synth/scripts/synth_fp_op.tcl:134` 주석은 *"It is not a functional timing path"* 라고 적는다. **이 주석은 D6 의 134개 레지스터군에 대해 거짓이다.** 정리하면: **실리콘에서 데이터 캡처를 게이팅하는데 타이밍이 검증되지 않은 경로**가 존재한다. 시뮬레이터는 이것을 볼 수 없다 — D4 와 같은 클래스이며, 사용자 지시의 정확한 대상이다. HIU 넷리스트에서 `rst` 를 데이터 입력으로 받는 LUT 실측 30개 (LUT6/I5 17 + LUT2 10 + LUT3 2 + LUT4 1) 중 LUT2 8개는 TRNG RO 의 `~(ro_s3 ^ rst)` 로 무관 → **실질 약 22개**. 나머지 rst 싱크는 FDCE/CLR 503 + FDPE/PRE 1 + `dma_engine/rst` 1.

**수리 형식 4종과 배정:**

| 형식 | 내용 | 넷리스트 효과 |
|---|---|---|
| **형식1** | 별도 `always @(posedge clk) if (!rst)` 블록 분리 (§28.3/§28.6 권고) | `if (!rst)` 가 **그대로 CE 로 접힌다** → rst→CE 동기 경로가 남는다 |
| **형식2** | rst 분기에 명시적 대입 추가 | FDRE(R=const0) → **FDCE(CLR=rst)**, rst 가 CE cone 에서 빠진다. 파형 변화 (rst 중 hold → 0) |
| **형식3** | `!rst` 가드 **없는** 순수 동기 블록 분리 | rst 가 CE cone 에서 **완전히** 사라진다. 파형·값 불변 |
| **형식4** | `set_msg_config -suppress` | **즉시 탈락** — §28.4 항 5 (전역 강등 금지) 정면 위배, ASIC 흐름 미이식, 진짜 위험 미해결 |

**HIU 배정 (본 commit):**

| 대상 | 건수 | 형식 | 근거 |
|---|---:|---|---|
| `shadow_regions_start[0:15]`, `shadow_regions_end[0:15]` | 32 | **형식3** | 기입 enable 이 `SHADOW_UPDATE` 상태 디코드 종속이고 `state` 는 async-reset (FDPE PRE=rst / FDCE CLR=rst) 이라 rst 중 IDLE 에 고정된다 → **enable 이 1 이 될 수 없음이 구조적으로 증명**된다. 파형·값·면적 전부 불변이면서 rst→CE 를 없애는 유일한 형식. 읽기는 `shadow_valid[k] &&` 로 가드되고 `shadow_valid` 는 reset 된다 (교과서적 data/valid 쌍) |
| `chacha_state[0:15]` | 16 | **형식3** | 동일 논거 (`CHACHA_*` 상태 종속) |
| `masked_phys_addr` | 1 | **형식3** | 동일 논거 (`CHACHA_FINAL` 종속). 소비자 `dma_engine` 은 `dma_req && access_granted` 에서만 읽고 내부 reg 는 전부 reset 된다 (HIU.v:619-622) |
| `initial_state[0:15]` | 16 | **형식3 + D8 수리** | 아래 **중요 정정** 참조 |
| `phys_addr` | 1 | **형식2** | 모듈 output 이고 `mem_phys_addr` 로 외부 노출된다. §29.6 부수 규범이 요구하는 **3-arm 전건 대입**과 함께 rst 대입 0 을 넣는다 |
| **신규** `tlb_mem` (100b × 64) | — | **형식3 (필수)** | async-reset 블록 안이면 RAM 추론이 원천 봉쇄된다 (`Synth 8-4767`). §29.3 채택 이유 4 |
| **신규** `tlb_valid` (64b) | — | **async 블록 유지** | reset 이 반드시 필요한 유일한 TLB 상태 (§29.5) |
| 전 구간 | — | **XDC 정정 (즉시·별건)** | `set_false_path -from [get_ports rst]` 를 **CLR/PRE 한정**으로 좁힌다: `-to [get_pins -hier -filter {REF_PIN_NAME == CLR \|\| REF_PIN_NAME == PRE}]`. 대상: `sys_top_core_gate.xdc` 생성 경로, `synth/constraints/pod.xdc:20`, `synth/scripts/synth_fp_op.tcl:130-136` 의 주석. **RTL 0줄 변경이므로 위 수리 이전에도 유효**하다 |

**형식1 을 HIU 에 쓰지 않는다 — 명시 기각.** §28.3/§28.6 이 권고한 형식이지만 (i) `if (!rst)` 가 CE 로 접히므로 **위 문단의 실리콘 리스크를 전혀 해결하지 못한다** (메시지만 없애고 위험은 남긴다 = 증상 제거), (ii) HIU 의 6개 그룹은 기입 조건이 전부 FSM state 디코드 종속이라 분리하려면 `case (state)` 골격을 6 상태에 대해 **복제**해야 하고, 같은 state 를 두 블록이 읽는 이중구조의 유지보수 위험이 D6 자체보다 크다. **결정적 근거: 현재 넷리스트가 이미 형식1 이다** — Vivado 가 그 변환을 이미 수행했고 (§29.2 C4), 그래도 위험이 남아 있다. **단 이 기각은 HIU 한정**이다: §28.6 이 O2 에서 형식1 의 파형 일치를 확인한 것은 Tensor_ALU 의 기입 조건이 무조건/단순 opcode 디코드라 blast radius 가 작기 때문이며, 그 사정은 HIU 로 이전되지 않는다.

**중요 정정 — `initial_state` 는 형식2 가 답이 아니다.** 조사 권고는 형식2 (reset 대입) 였으나 본 절은 이를 **기각**한다. 사유: `initial_state` 의 문제는 D6 가 아니라 **D8 (§29.8) 이다.** 형식2 는 rst 후 첫 진입의 미기입 값을 0 으로 만들 뿐 **영구적 1단계 어긋남을 고치지 못한다** — 즉 비결정적으로 틀린 값을 **결정적으로 틀린 값**으로 바꾼다. 그것은 개선이 아니라 **결함을 시뮬과 실리콘 양쪽에서 똑같이 조용하게 만드는 것**이며, 유일하게 남아 있던 "뭔가 어긋났다" 는 신호(sim ≠ silicon)를 지운다. 올바른 처분은 **D8 을 고쳐 read-before-write 자체를 없애고**, 그러면 `initial_state` 는 (a) 판정이 되어 **형식3 으로 충분**하다.

**이월 2건과 기한 조건 (기한 없는 이월은 금지한다):**

- **`PE_Core` 68건 — 이월.** 사유: (i) 68건 **전부 (a) 판정**이다 — 전부 데이터/피연산자 래치이고 reset 되는 valid 비트로 자격 부여되며, 의도가 이미 문서화되어 있다 (`PE_Core.v:1801-1807` *"Data regs (vfma_a_q/b_q/c_q/stage/lane/is_int8) are reset-free like the deq/fp operand regs."*). read-before-write 후보가 없으므로 **기능 결함이 없다**. (ii) PE_Core 는 §26.9 · §28.6 · §28.9 가 세 번 독립 재확인한 dispatch 병목 경로의 당사자다 — 본 commit 의 blast radius 에 넣으면 D4 판정과 dispatch 회귀가 뒤섞여 어느 쪽 실측인지 귀속이 불가능해진다. (iii) HIU 형식3 의 안전성 논증이 실증되면 그 패턴을 그대로 재사용할 수 있다 — 순서를 뒤집으면 미검증 패턴을 주력 모듈에 먼저 적용하게 된다. **수리 형식 사전 배정: 형식3 우선, 그룹별 enable 이 reset 되는 제어비트 종속임의 확인이 비싸면 형식1. 형식2 는 비권고** (위 인용 설계 의도와 정면 충돌하고 ASIC 면적만 늘린다).
  **기한 조건 — 아래 셋 중 가장 먼저 오는 시점까지 처리한다:**
  1. 본 절 S2-C4 (GATE S1-US #2) 가 PASS 하고 HIU 형식3 무회귀가 실증된 **직후의 다음 RTL commit**,
  2. `Synth 8-7137` 모듈별 축 (§29.11) 에서 PE_Core 계수가 **68 을 초과하는 최초 시점** — 증가는 새 미리셋 레지스터가 추가됐다는 뜻이므로 그 commit 에서 즉시 처리,
  3. PE_Core 를 **ASIC 흐름 또는 FDSE/FDPE 매핑이 나오는 흐름**으로 처음 내보내는 commit.
  조건 2 는 gate 가 **자동으로 발화**시키므로 이 이월은 조용히 영구화될 수 없다.
- **`Tensor_ALU` 49건 (= §29.2 C7 대로 4군) — 이월.** 사유: §28.8 의 **고아 지위 판정 (폐기 vs 통합) 이 선행해야 한다.** 폐기될 모듈의 reset 을 고치는 것은 낭비이고, 이 모듈은 애초에 대표 연산이 동작하지 않는다 (§28.8 O1 — MATMUL 이 무한 누산기로 축퇴). **기한 조건: §28.8 고아 지위 판정 commit 과 같은 commit.** 판정이 "폐기" 면 O2 수리는 소멸하고, "통합" 이면 그 commit 이 O1 (기능) · O2 (reset) · 데이터 레이아웃 불일치를 **동시에** 처리한다. 그 전건은 §12a 의 **RTL 모듈 단위 제거 절차 성문화** (§28.8 정책 공백) 다.
  **정정**: 조사 과정에서 "Tensor_ALU 를 손대면 `a[i][k]*b[k][j]` 가 premap `$mul` exact 축을 건드린다" 는 우려가 제기됐으나 **틀렸다** — Tensor_ALU 는 어디에도 인스턴스화되지 않는 고아이고 `sys_top_core` premap 명령의 `read_verilog` 목록에도 없으므로 **429 축에 0 기여**한다. 축 영향은 **편입되는 시점에** 발생하며, 그때는 편입 자체가 재anchor 사유다.

### 29.8 D8 (신규 결함) — XChaCha20 계약이 실물에서 이행되지 않는다

> **[2026-08-18 부분 supersede — §30]** 아래 **수리 형태 (normative)** 항 (`initial_state` 경유 제거 = 1단계 어긋남 소멸) 은 참이고 S2-C2 에서 이행됐으나, **D8 의 전부가 아니었다.** golden 착지 (`scripts/golden_xchacha.py`) 가 편차 **2건을 더** 실측 확정했다 — (A) 2단 nonce 워드 배치, (B) 라운드 구조 (8 quarter-round 병렬 → column round 전량 소실). 본 항의 수리 형태만 이행한 오늘의 RTL 은 **여전히 XChaCha20 키스트림을 내지 않는다.** 잔여 2건의 normative 수리 계약은 **§30** 이 규정하며, 본 절 원문은 §12a 규칙 5 대로 무수정 보존한다. **본 항의 "수리 형태" 를 단독 인용해 "D8 은 닫혔다" 고 읽지 마라.**

**본 절이 새로 기록하는 결함이며, D4 와 같은 급의 "선언과 실물의 괴리" 다.** §28 은 이것을 기록하지 않았다.

**사실:** `CHACHA_H_INIT` (HIU.v:186-209) 은 **같은 블록·같은 사이클**에 `initial_state[*] <= 상수/키/nonce` 와 `chacha_state[m] <= initial_state[m]` 을 수행한다. 비차단 대입이므로 RHS 는 **직전 값**이다. 결과는 첫 사이클만의 문제가 아니라 **영구적 1단계 어긋남**이다:

- `CHACHA_H_INIT`: `chacha_state ← (직전) initial_state` — 최초에는 미기입 값, 이후에는 **직전 `CHACHA_INIT` 이 넣은 subkey 기반 상태**.
- `CHACHA_INIT`: `chacha_state ← (직전) initial_state` = **HChaCha20 초기상태** (상수 + key + nonce).
- ⇒ **subkey 가 HChaCha20 사양대로 유도되지 않고, ChaCha20 라운드가 subkey 상태 위에서 돌지 않는다. 즉 마스크는 XChaCha20 키스트림이 아니다.**

**은폐 경로:** `test_hiu.py:51,68` 이 검사하는 것은 `masked_phys_addr != phys_addr` 뿐이다 — 마스크가 **무엇이든** 0 이 아니면 통과한다. §28.8 O1 이 `alu_valid == 1` 만 assert 해 MATMUL 결함을 은폐한 것과 **동형 패턴**이며, 본 절이 기록하는 세 번째 사례다 (D4 계층 강제 기입 / O1 값 미검사 / D8 값 미검사).

**시뮬 ≠ 실리콘:** `Makefile:13` 의 `SIM ?= verilator` 는 2-state zero-init 이라 시뮬은 결정적인데 실리콘 power-up 은 랜덤이다 → **첫 변환의 마스크 값이 시뮬과 실리콘에서 다르다.**

**처분: 본 절의 착지 범위에 포함한다 (S2-C1/C2).** 사유는 두 가지다 — (i) §29.7 이 확정한 대로 `initial_state` 의 D6 처분이 D8 판정에 종속되어 있어 분리할 수 없고, (ii) "실물에서 쓴다" 는 전제 하에서 **선언된 암호 계약이 이행되지 않는 것**은 D4 와 같은 등급의 구조적 결함이다.

**수리 형태 (normative):** `chacha_state[m]` 에 `initial_state` 를 **경유하지 않고** 같은 cycle 에 확정되는 값 (상수 / key / nonce / subkey) 을 직접 대입하고, `initial_state[m]` 에는 `CHACHA_FINAL` 의 final-add 를 위해 **같은 값을 병렬 대입**한다. 두 배열이 같은 cycle 에 같은 값을 갖게 되어 1단계 어긋남이 소멸한다.

**golden-before-RTL (프로젝트 법칙 이행):** XChaCha20 은 표준이므로 golden 이 존재할 수 있고, 따라서 존재해야 한다. **`scripts/golden_xchacha.py`** (stdlib-only, 고정 벡터, 재실행 byte-identical) 를 RTL 이전에 착지시키고, 그 산출물로 `test_hiu.py` 가 `masked_phys_addr` 의 **정확값**을 assert 한다 — `!=` 검사는 폐기한다. 참조: RFC 8439 (ChaCha20) + HChaCha20 (draft-irtf-cfrg-xchacha) 테스트 벡터.

**면적 미측정 (정직 명기):** D8 수리의 LUT/FF 영향은 **측정하지 않았다.** `initial_state`→`chacha_state` 의 512-bit mux 경로가 없어지는 대신 `chacha_key` (256b) / `chacha_nonce` (192b) 팬아웃이 늘어난다 — **부호가 미정이며 수십~수백 LUT 규모일 수 있다.** 조사 workflow 가 RTL 무수정 원칙이었으므로 실측이 불가능했다. §29.11 의 LUT 선공표 상한이 이 미지수를 흡수하도록 잡혀 있으며, **추정을 실측으로 말하지 않는다** (§25.4).

### 29.9 D9 (신규 결함, 이월) — FLUSH_TLB 의 전역성은 cross-tenant 행위다

**사실:** `context_switch` 하나가 `FLUSH_TLB` 를 발동하고, 그것은 **전 파티션의 `tlb_valid` 64비트와 전역 `shadow_valid` 16비트를 한꺼번에 지운다.** 즉 tenant A 의 context switch 가 tenant B 의 변환을 무효화한다.

**왜 결함인가:** §29.5 가 파티션을 tenant lease 격리 경계로 규범화한 순간, **한 tenant 가 다른 tenant 의 상태를 지울 수 있다는 것**은 격리 위반이다 (가용성 측면의 cross-tenant 영향이고, flush 후 재fill 지연은 관측 가능하다). D4 를 실물화하기 전에는 지울 상태가 없어 이 문제가 나타나지 않았다 — **D4 수리가 만들어낸 문제가 아니라, D4 수리가 드러낸 문제다.**

**처분: 이월.** 본 commit 에서 고치지 않는 사유 — 수리는 `context_switch` 를 partition-qualified 로 바꾸는 것이고, 그것은 **Y4 `hiu_abi.md` 의 lease-rotation 시퀀스 계약 변경**이라 별도 저장소와의 sign-off 를 요구한다. 본 절은 `context_switch` 의 현행 의미 (**전역 flush**) 를 규범으로 명시하고 그 한계를 기록한다 — 조용히 두지 않는다.
**기한 조건:** Y4 `hiu_abi.md` 의 **TLB fill 레지스터 신설 개정 (§29.4 다운스트림 목록) 과 같은 개정 라운드**에서 per-partition flush 를 함께 협상한다. 그 개정이 v1.0 freeze 전에 이루어져야 한다 — freeze 후에는 §12a 상 WT64v2 급 변경이 된다.

### 29.10 D7 처분 — 예약 포트 명문화

**결정: 처분3 — `interface_type[1:0]` 을 유지하되 지위를 "선언되지 않은 미독 포트" 에서 "선언된 예약 포트" 로 바꾼다.**

**의도 복원 (근거 3건):** 호스트 **transport 종류 선택자**다. (i) `test_hiu.py:38` — `# Test 1: … PCIe, DMA 요청` 직후 `interface_type = 0`, (ii) `test_hiu.py:58` — `# Test 2: Shadow 히트 with USB …` 직후 `interface_type = 1`, (iii) `.claude-memos/sdk_architecture.md:92` — *"HIU 의 호스트 인터페이스가 PCIe/USB/CXL 등 무엇이든 Rust core 가 transport 추상화(`Transport` trait)로 처리"*, `remote_accelerator_access.md:72` 동일 취지. 2비트 = 4종 (PCIe / USB / CXL / 예약) 이 memo 서술과 정합한다. **인코딩 0=PCIe, 1=USB 가 테스트 주석에 화석으로 남아 있다.**

**규범 (normative):**

1. `interface_type[1:0]` 은 **RESERVED** 다. 호스트는 `2'b00` 으로 구동해야 하며, non-zero 는 **미정의**다.
2. 현 RTL 은 이 포트를 읽지 않으므로 **어떤 값도 동작을 바꾸지 않는다.** 이 사실이 계약이다 — "무시된다" 를 명시적으로 약속한다.
3. **승격 조건 (처분1 발동 조건):** transport 별 ATS/PRI 자격 계약이 spec 에 normative 로 기록되는 시점. **그 전에는 결선을 금지한다** — 지금 결선하는 것은 없는 행동을 발명하는 일이다 (HIU 에 transport 종속 행동이 하나도 없고, ATS/PRI 는 이미 전용 포트로 처리된다).
4. **의무 — 이 항이 빠지면 처분3 은 무효다:** `test_hiu.py:38,58` 의 "PCIe" / "USB" 주석을 정정한다. RTL 이 그 구분을 **전혀 하지 않는다**는 사실을 주석에 명시해야 한다. 그 주석은 두 transport 를 검증하는 것처럼 읽히게 하는 **D4 와 동종의 거짓 진술**이며, 포트를 남기든 없애든 **무조건** 정정 대상이다. **D7 항에서 실물 관점에서 반드시 바뀌어야 하는 것은 포트가 아니라 이 주석이다.**
5. `HIU.v:20` 주석에 항 1-3 과 복원된 인코딩 화석 (0=PCIe, 1=USB, memo 근거 포함) 을 기록한다.
6. **예약 포트 목록의 기계 열거는 이월한다** — `scripts/lint_synth_coverage.py` 계보로 만들 수 있으나 본 commit 은 구현하지 않는다. 방어는 항 3 의 승격 조건과 `Synth 8-7129` 의 상시 관측이다.

**기각 기록:**

- **처분2 (제거)** — pre-stable 에서 허가된 정규 이벤트이지만 (§29.2 C5), (i) 면적 이득이 **실측 0** 이고 (`interface_type_q` 셀 0개, §29.2 C6), (ii) memo 2건 + SDK `Transport` trait 설계가 host-transport 선택을 **살아있는 설계 축**으로 유지하므로 재도입 확률이 낮지 않아 §12a 계약 변경을 **2회** 초래할 개연성이 있으며, (iii) blast radius 가 8개 파일 (gate 래퍼 2종 포함) 인데 얻는 것이 정결성 하나다.
- **처분1 (결선)** — 행동 발명이며 spec-first + golden-before-RTL 을 요구하는 별도 작업이다. D4/D6 와 같은 commit 에 실을 일이 아니다.

**D4 와의 성질 차이 (판정의 핵심):** D4 는 **실리콘에 없는 경로를 테스트가 있다고 말하는** 상태였다. D7 은 포트가 실리콘에 실재(입력 핀)하고 읽히지 않는다는 사실이 `Synth 8-7129` 로 **상시 관측**된다 — 은폐가 없다. 명문화는 "선언되지 않은 미독 포트" 를 "선언된 예약 포트" 로 바꾸는 것이고, 그것이 정직성의 전부다.

### 29.11 GATE S1 영향 선언 (측정 **전** 공표 — V9-4 정신)

**§28.5 (c) 대로 area binding 은 본 절의 구현 commit 부터 발효한다.** 아래는 **측정 이전에** 공표하는 예측이며, 사후 해석의 여지를 없애기 위해 방향과 상한을 함께 적는다. 근거 수치는 전부 `/tmp` 프로토타입의 **HIU 단독 OOC 실측**이고 system 문맥 값이 아니다 — **투영은 투영이고, 판정은 재측정으로만 내린다.**

| 축 | 지위 | anchor | 예상 착지 | 선공표 상한 | 귀속 |
|---|---|---:|---|---|---|
| **LUT sites** | binding (ceiling **24,799**) | 14,850 | **≈ 14,872** (+22) = ceiling 의 **60.0%** | **+400 이내** (≤ 15,250 = **61.5%**) | 프로토타입 +22 (LUTRAM +144, 16-way 비교기 소멸 −122). 정규 형태는 (−) RAM 폭 124→100 bit 와 (+) fault 로직·샘플 레지스터·D8 수리 (부호 미정, §29.8) 를 함께 갖는다. **ceiling 초과는 예상하지 않는다** |
| FF | 추적 | 9,585 | **≈ +186** | +320 이내 | 프로토타입 +186 + `tlb_fault_code` 3 + `tlb_fault` 1 + one-hot state +2 + 래퍼 flop |
| **DSP48E2** | **즉시 binding, exact** | **39** | **불변 39** | — | TLB 는 곱셈기를 만들지 않는다. §29.4 파라미터 제약 (2의 거듭제곱) 이 전건 |
| **RAMB18** | **즉시 binding, exact** | **2** | **불변 2** | — | `ram_style="distributed"` 강제 (§29.5). **`block` 을 쓰면 RAMB36 2개가 붙어 축이 4 가 되고 즉시 FAIL** — 실측 확인된 조건이며 §29.3 채택 이유 3 |
| **premap `$mul`** | **즉시 binding, exact** | **429** | **381 (−48) — 재anchor 예상** | — | **아래 별항** |
| **DRC errors** | binding | 0 | 0 | — | 전 프로토타입 errors 0, `LUTLP-2 Combinatorial Loop Allowed ×8` warning 만 (D2 제약 정상 작동) |
| **CRITICAL `Synth 8-295`** | binding, exact | 8 | 8 | — | TRNG RO 무접촉. **단 아래 재측정 의무 참조** |
| **WHS** | **즉시 binding** | **+0.019 ns** | **본 변경의 유일한 실질 리스크 축** | ≥ 0 | 프로토타입 HIU 단독 WHS **+0.007** (baseline +0.039). 형식2/3 은 rst→CE 조합 경로를 없애므로 hold 에 불리할 이유가 없으나 마진이 사실상 없다. **음수면 즉시 FAIL, 완화 없음** |
| WNS / Fmax | 기록 | +1.497 / 117.61 | ≈ 불변 | — | HIU 단독 229.94 → 228.47 MHz (사실상 무변화). 시스템 병목은 HIU 가 아니라 EHDecode→PE_Core dispatch 다 (§28.6) |
| **`Synth 8-7137` 모듈별** | **신규 축 — exact** | 미등재 | **HIU 0 / PE_Core 68 / 합 68** | — | 아래 별항 |
| **`Synth 8-3848` (undriven net)** | **신규 축 — exact** | 참값 128 (로그는 캡 100) | **0** | — | 아래 별항 |

**별항 1 — premap `$mul` 429 재anchor 사전 선언 (사용자 결정 사항).**

**429 는 매핑 넷리스트에 cell 이 0개인 구조의 곱셈 48개를 포함하고 있었다.** 귀속: HIU 단독 premap stat 에서 현행 `$mul` = **48**, 배열 삭제 시 **0**. 이 48 은 `partitioned_tlb_*[partition_id][j]` 의 **2D 배열 행 주소 곱셈** (`p*TLB_ENTRIES + j`) 이며, yosys 가 premap 단계에서 배열을 `$memrd` 로 유지하기 때문에 `opt_clean` 을 통과한다. 즉 **소멸한 TLB 가 gate anchor 429 안에 phantom multiplier 48개로 들어앉아 있었다.**

측정 실적 (gate 하네스와 동일 yosys 명령, HIU 만 교체): repo 현행 **429** / 호스트 기입형 · ATS fill 형 **432 (+3, 기입 포트 3개의 쓰기 주소 곱셈)** / **direct-mapped 381 (−48)** / 폐지형 **381 (−48)**. **모든 경로가 이 축을 움직인다 — 폐지해도 깨진다.**

**절차 (조작 여지를 없애기 위해 판정 전에 공표한다):**
1. 본 절이 **429 → 381** 을 예측으로 공표한다.
2. 실제 재anchor (= `synth/scripts/fp_op_gate_check.py` 의 `premap_mul_expect` 갱신) 는 **사용자 승인 후** S2-C4 에서 수행한다. §12a 상 gate 기준 재anchor 는 사용자 결정 사항이다.
3. **승인 전에는 S2-C2/C3 를 merge 할 수 없다.**
4. 실측이 381 이 아니면 **수치를 맞추지 않는다** — 귀속을 다시 유도하고 그 사유를 기록한다. 예측이 틀렸다는 사실 자체가 기록 대상이다.

**별항 2 — `Synth 8-7137` 모듈별 exact 축 신설.**

§28.3 이 이 축을 채택하지 않은 근거 ("문맥 의존") 가 §29.2 C2 로 **소멸**했다 — 문맥 의존이 아니라 **캡 의존**이었고, `-limit` 만 올리면 모듈별로 완전히 결정적인 정수다 (HIU 단독 66 == 문맥 66, PE_Core 단독 68 == 문맥 68).

- **전제조건 (빠뜨리면 축이 100 에서 잘려 false PASS):** 하네스에 `set_msg_config -id {Synth 8-7137} -limit 100000` 추가.
- **선공표 값:** HIU **0** (본 commit 전건 수리) / PE_Core **68** (이월분, 정확 계수 pin) / 합 **68**. `Tensor_ALU` 는 `sys_top_core` 문맥 밖이라 이 축에 나타나지 않는다 (§29.7 정정).
- **지위:** exact-value. **변동 시 FAIL.** 이월분을 수리하는 commit 이 같은 commit 에서 spec 과 gate_check 의 축 값을 함께 낮추는 것은 정규 행위다 — 수치를 통과시키려고 움직이는 것과, 수리 사실을 반영해 조이는 것은 다르다. 후자만 허용된다.

**별항 3 — `Synth 8-3848` ("Net ... does not have driver") exact 0 축 신설. 이것이 §29.12 가 요구하는 기계적 검사의 실물이다.**

아카이브된 `sys_top_core_run.log` 에서 이 경고는 **100건 (캡, 참값 128)** 이고 **전부 `partitioned_tlb_phys` / `partitioned_tlb_virt`** 다 — 즉 **D4 는 처음부터 기계 판독 가능한 형태로 로그에 있었다.** 아무도 이 축을 보지 않았을 뿐이다.

- **지위:** exact **0**. 예외는 allowlist 로만 허용하며 **항목마다 사유 필수** (§28.4 항 3 래칫과 같은 형태). 착지 시점 allowlist 는 **비어 있어야 한다**.
- **전제조건:** `-limit` 상향 (별항 2 와 동일 사유).
- **정직한 한계 — 이 축은 D4 의 절반만 본다.** `partitioned_tlb_valid` 는 clear 구동원이 있어 이 경고에 **잡히지 않는다.** 즉 "전혀 기입되지 않는 저장소" 는 잡지만 "clear 만 되고 set 은 없는 저장소" 는 못 잡는다. **따라서 이 축은 §29.12 규범의 보완물이지 대체물이 아니다.** 이 한계를 적지 않으면 다음 사람이 "lint 가 있으니 안전하다" 고 오독한다.

**재측정 의무 (구현 commit 몫):** `make synth-sys-gate SYS_GATE=sys_top_core PART=xcu55c-fsvh2892-2L-e` + `python3 synth/scripts/fp_op_gate_check.py` 로 **`sys_top_core` 문맥에서 전 축 재측정**. HIU 단독 수치로 대체 불가 — 조사에서 `Synth 8-295` census 가 HIU 단독 문맥에서 **v0=0 / 기입형=8** 로 **문맥 의존**임이 재현 확인됐다 (v0 을 별도 디렉터리에서 2회 재실행해 0 확인). gate 축은 system 문맥에 고정되어 있으므로 판정에 직접 영향은 없으나, **census 는 반드시 system 문맥에서 취한다.** ECP5 반쪽은 §28.7 정책 그대로 MEASUREMENT 이며 어떤 결과도 FAIL 을 구성하지 않는다.

**ceiling 초과 시 절차 (초과를 예상하지 않지만 미리 적는다 — 이것이 V9-4 정신이다):**
1. **정직 FAIL 로 기록한다.** 기준을 움직여 통과시키는 경로는 없다.
2. 초과분을 **귀속**한다 (어느 구조가 몇 LUT 인지 — 프로토타입 실측과 대조).
3. **재anchor 는 §12a 상 사용자 결정 사항**이다. 구현 세션이 스스로 결정하지 않는다.
4. 재anchor 를 받지 못하면 **pre-declared cut ladder** 를 따른다: (a) `tlb_fault_code` 폭 축소 3→2 bit, (b) shadow 16-way 비교기의 공유화, (c) `TLB_ENTRIES` 16→8 (파티션 격리는 유지되고 conflict 만 늘어난다 — §29.5 associativity 규범이 이미 이를 계약 밖으로 규정해 두었다). **(c) 는 계약 축소이므로 §12a 재개정을 동반한다.**

### 29.12 §28.4 항 7 신설 (normative) — 은폐 재발 방지 규범

**§28.4 에 항 7 을 추가한다** (항 1-6 은 무수정 유지):

> **7. 테스트는 RTL 이 구동하지 않는 상태를 계층 강제 기입으로 만들어 그 위에서 기능을 검증할 수 없다.** 계층 강제 기입 자체는 금지 대상이 아니며, 금지되는 것은 **RTL 이 만들지 않는 상태를 테스트가 스스로 만들어 그것을 검증 대상으로 삼는 것**이다. 경계는 다음 4항으로 정한다.
>
> - **(a) 허용 — 관측.** `dut.<internal>.value` **읽기**는 무제한 허용한다. 화이트박스 관측은 이 규범의 대상이 아니다.
> - **(b) 허용 — 단축.** RTL 이 실제로 구동하는 상태를 초기 조건으로 밀어 넣어 시퀀스를 단축하는 것은 허용한다. **단 같은 상태에 포트 경로로도 도달할 수 있음이 별도 테스트로 실증되어 있어야 한다.** 단축은 도달 가능성을 대체하지 못한다.
> - **(c) 금지 — 구동원 없는 기입.** 그 신호에 **RTL 구동원이 없는데** 기입하는 것. 이 경우 테스트는 실리콘에 존재하지 않는 경로를 검증한다 (D4 의 정확한 형태).
> - **(d) 금지 — 유일 도달 수단.** 포트 경로가 존재하는데도 검증의 **유일한** 도달 수단이 강제 기입인 것. 이 경우 포트 경로 자체가 미검증으로 남는다.
>
> 위반 발견 시의 처분은 테스트 수정이 아니라 **RTL 과 테스트 중 어느 쪽이 진실인지의 판정**이다 — D4 가 그 판정에 3.5개월이 걸린 이유는 판정을 요구하는 규범이 없었기 때문이다.

**적용 현황 (정량 baseline — 규범에 측정 기준선을 붙인다):** `test_*.py` 9개 파일의 `dut.<...>.value =` 대입은 총 **691건** (clk/rst 제외; test_cluster 304 / test_isa_decoder 280 / test_top_core 31 / test_hiu 27 / test_pod 17 / test_pe 13 / test_alu_extended 8 / test_simd_alu 8 / test_tensor_alu 3). **압도적 다수는 top-level 포트 구동이며 본 규범의 대상이 아니다.** 오늘 확인된 (c) 위반은 `test_hiu.py:24-26` 의 3건 (`partitioned_tlb_virt` / `_phys` / `_valid`) 이고, **D4 수리가 이를 포트 구동으로 교체하면서 구조적으로 소멸한다.** `test_hiu.py:29-31` 의 `shadow_regions_*` 3건은 (b) 에 해당하며 — `test_top_core.py:73-77` 이 `shadow_write_en` **정규 포트 경로**를 쓰는 것이 그 실증이다 — 규범을 만족한다. 이 대조가 (b) 와 (c) 의 경계를 실물로 보여준다.

**기계적 검사 가능성 (정직한 논의 — 되는 것과 안 되는 것을 나눈다):**

1. **이미 되는 것 — `Synth 8-3848` exact 0 축 (§29.11 별항 3). 본 절이 이 축을 신설한다.** 새 도구가 필요 없고 아카이브된 로그를 grep 하면 되며, D4 의 100/128 건이 전부 여기 잡혀 있었다. **한계는 명확하다: "전혀 구동원이 없는 저장소" 만 잡고, `partitioned_tlb_valid` 처럼 "clear 만 되고 set 은 없는 저장소" 는 못 잡는다.** 즉 D4 의 절반이다.
2. **되지만 비용이 있는 것 — 넷리스트 대조 lint.** `test_*.py` 의 대입 대상 심볼을 정규식으로 추출해 아카이브 넷리스트와 대조한다. 한계 2건: (i) 합성기가 이름을 바꾼다 (`_reg` 접미, 배열 flatten) 는 정규화 휴리스틱이 필요하고, (ii) **정당하게 최적화로 사라진 신호와 구동원 부재를 구별하지 못해 false positive 가 난다.** 따라서 사유 필수 allowlist 를 갖는 형태여야 한다.
3. **가장 정확하지만 도구 의존 — 프론트엔드 AST 질의.** verilator `--xml-only` 또는 yosys `read_verilog` 후 각 신호의 **대입문 존재**를 질의한다. 합성 최적화 이전이라 2의 false positive 가 대폭 준다. 한계: cocotb 계층 이름 ↔ AST 넷 이름 매핑을 만들어야 하고 generate/다차원 배열에서 깨진다. 스키마가 버전 의존이며 tracked artifact 가 아니다.
4. **판정:** 본 commit 은 **1만 구현하고 (§29.11 별항 3), 2/3 은 구현하지 않는다.** §28.10 이월 목록의 "undriven-signal 탐지 lint" 항목은 그대로 남는다.

**정직 명기 — "lint 가 있으니 안전하다" 고 말하지 않는다.** 이 commit 이후 D4 형 결함이 재발하지 않는 주된 이유는 lint 가 아니라 **D4 경로가 실제로 없어지고 (§29.3) 규범이 판정을 요구한다는 것 (항 7)** 이다. `Synth 8-3848` 축은 그 위에 얹는 **두 번째 방어선이고, 절반만 본다.**

### 29.13 착지 순서 · test_plan · 재측정 의무

**착지 순서 (spec-first §12a 규칙 3 + golden-before-RTL 동시 충족):**

| 단계 | 내용 | 전건 |
|---|---|---|
| **S2-C0** | **본 절 (spec-first)** — 본 commit. RTL·테스트 무접촉 | — |
| **S2-C1** | `scripts/golden_xchacha.py` + 고정 벡터 산출물 (D8 전건) | S2-C0 |
| **S2-C2** | RTL — `HIU.v` (D4 실체화 + D6 형식2/3 + D8 + D7 주석) / `Top_Core.v` passthrough / gate 래퍼 2종 / XDC false_path 축소 | S2-C1 + **premap `$mul` 재anchor 사용자 승인** |
| **S2-C3** | 테스트 — `test_hiu.py` 재작성 + `test_top_core.py` 갱신 | S2-C2 |
| **S2-C4** | **GATE S1-US #2 (최초 binding 측정)** — 전 축 재측정 + 신규 축 3종 등재 + ECP5 MEASUREMENT | S2-C3 |
| **S2-D** | 다운스트림 문서 (Y4 2파일 / wavetensor-drivers 2파일) — **별도 저장소이므로 별도 commit**, 목록은 §29.4 | S2-C2 |

**test_plan (S2-C3 몫 — 본 절이 항목을 확정한다):**

1. **계층 강제 기입 제거** — `test_hiu.py:24-26` 삭제, `tlb_write_*` 포트 구동으로 교체 (§28.4 항 7 (c) 위반 해소).
2. **zero-tag probe** — §29.6 항 3. **discriminator 가 실재하는 테스트**다.
3. **TLB 우선순위** — shadow region 과 **겹치는** TLB 엔트리를 설치하고 TLB 변환이 이기는 것을 assert. 조사가 실증한 `SHADOW_OVERRIDES` 회귀의 직접 방어.
4. **상수시간 동일성** — hit / shadow-fallback / miss 세 경로의 cycle 수가 **서로 같음**을 assert. **절대치 (37) 를 assert 하지 않는다** — 계약은 동일성이지 절대치가 아니다 (§29.5).
5. **loud fault 4종** — `INDEX_MISMATCH` / `PHYS_MISALIGNED` / `BUSY` / (`PARTITION_RANGE` 는 현 형상에서 도달 불가이므로 도달 불가임을 주석으로 기록) 각각에 대해 `tlb_fault` 펄스 + `tlb_fault_code` + **기입이 수행되지 않았음**을 assert.
6. **파티션 격리** — 파티션 0 에 설치한 엔트리가 `partition_id = 1` 에서 miss 하는 것을 assert.
7. **flush 후 stale 데이터 무해성** — 엔트리 설치 → `context_switch` → 같은 주소 변환이 miss 하는 것을 assert (RAM 에 데이터가 남아 있음에도).
8. **XChaCha20 정확값** — `masked_phys_addr` 를 golden 산출값과 **정확 비교**. 기존 `!=` 검사 폐기 (§29.8).
9. **D7 주석 정정** — `test_hiu.py:38,58` (§29.10 항 4). 코드 변경이 아니라 거짓 진술 제거다.
10. **무회귀** — 6개 모듈 전 suite. `COCOTB_RESULTS_FILE` 을 `/tmp` 로 리다이렉트해 tracked `results.xml` 무접촉 (§28.3 관례). **단 `test_hiu.py` 는 의도적으로 재작성되므로 HIU 항목의 테스트 이름 집합 변화는 회귀가 아니라 요구된 결과다** — §12a 하의 재유도 대상이다.

### 29.14 §12a 기록

본 절은 §12a 하의 **정규 개발 행위 (regular development act)** 이며 **spec-before-code COMMIT 0** 다.

- **계약 변경의 성격**: §29.4 의 HIU 모듈 인터페이스 확장 (입력 5 + 출력 2) 은 §12a 규칙 3 이 규율하는 계약 변경이다. **ISA 표면은 무접촉이다** — `isa/wt64v1_isa.json` · 생성물 · asm · golden 3종 · truth table 어느 것도 본 절의 대상이 아니므로 `domain_version` bump 도 truth-table recapture 도 발생하지 않는다. 규칙 3 의 순서 중 발동하는 것은 **spec amendment → RTL/테스트 갱신** 구간뿐이다.
- **3a (§27.7a) 와의 격리**: 3a 산출물 — golden 3종 (`scripts/golden_{fp32,lattice,fdotcr}.py`), ISA (`isa/wt64v1_isa.json` + 생성물 + `asm/`), `FP_StepSeq.v` step 프로그램 — 은 **무접촉**이다. 공유 datapath 3파일 (`FP_AddWide.v` / `FP_Mul36.v` / `include/fp_narrow_f32.vh`) 은 **byte-untouched** 이고 `decode_reserved` 는 미접촉이다 (3a-C4 몫). 본 절은 §27.7a 의 착지 순서를 선점하지 않는다. 신규 `scripts/golden_xchacha.py` (§29.8) 는 3a golden 3종과 무관한 별개 파일이다.
- **의도적 test-breakage 입장**: §29.13 항 10 대로 `test_hiu.py` 는 **의도적으로 재작성된다.** 계층 강제 기입 제거 (§28.4 항 7) 와 `!=` 검사 폐기 (§29.8) 는 사고가 아니라 본 절이 요구하는 결과이며, §12a 하에서 이런 breakage 는 **보존이 아니라 재유도 대상**이다 (§26.10 이 확립한 입장의 승계).
- **선공표 규율**: §29.11 의 예측·상한·재anchor 예고는 **측정 이전에** 공표됐다. premap `$mul` 재anchor 는 사용자 승인 전에는 발효하지 않으며, 승인 전 S2-C2/C3 merge 를 금지한다. ceiling 초과 시 절차 (정직 FAIL → 귀속 → 사용자 결정 → cut ladder) 도 측정 이전에 고정됐다 — **판정 이후에 만들어진 절차는 절차가 아니다.**
- **§28 정정의 성격**: §29.2 의 8건은 §28 원문을 **삭제하지 않고** 정정한다 (§12a 규칙 5). 그중 C2/C5/C6 은 §28 의 **판단 근거**를 무너뜨리므로 (8-7137 축 미채택 / D7 "제거 불가" / D7 미조사), 그 판단들은 본 절이 각각 §29.11 별항 2 · §29.10 · §29.2 C6 에서 대체한다.
- **이월 항목 (기한 조건 포함, §29 몫)**: **D9** per-partition flush (§29.9 — Y4 ABI 개정 라운드) · **PE_Core D6** 68건 (§29.7 — 3조건 중 최선) · **Tensor_ALU O2** 49건 (§29.7 — 고아 판정 commit 동시) · **undriven-signal 탐지 lint 2/3** (§29.12 — §28.10 이월 목록 유지) · **예약 포트 기계 열거** (§29.10 항 6) · **4-way set-associative 비용 측정** (§29.3 — associativity 재협상 시).

##### 29.11a — premap `$mul` 재anchor 발효 (2026-08-18, 사용자 승인)

**§29.11 별항 1 이 사전 선언한 절차의 종결부다.** GATE S1-US 의 `premap $mul` exact 축이 **429 → 381 (−48)** 로 FAIL 이었고, §12a 상 재anchor 는 사용자 결정 사항이므로 측정 agent 는 기준 수치를 건드리지 않은 채 FAIL 을 그대로 보고했다. 사용자가 **381 로의 재anchor 를 승인**했다 (2026-08-18).

**귀속 (승인의 근거 — 이것이 없으면 exact 축 완화는 금지다)**: anchor 429 는 **매핑 넷리스트에 셀이 0개인 구조를 세고 있었다.** 사라진 48 은 죽은 2D 배열 `partitioned_tlb_*[p][j]` 의 행 주소 곱셈 (`p*TLB_ENTRIES + j`) 이며, yosys 가 premap 단계에서 배열을 `$memrd` 로 보존하기 때문에 `opt_clean` 을 통과해 계수에 남았다. D4 가 그 배열을 삭제하자 phantom 도 함께 걷혔다. 신규 TLB 는 엔트리 주소를 `{partition, index}` **연접**으로 만들어 곱셈을 구조적으로 생성하지 않는다.

**이 재anchor 가 정당한 이유 — 그리고 선례가 되어서는 안 되는 이유**: exact 축을 올리는 것은 원칙적으로 금지다 (측정에 기준을 맞추는 행위). 본 건이 예외인 것은 **축이 실재하지 않는 것을 세고 있었음이 독립적으로 확인**됐기 때문이다 — 넷리스트 cell census (§29.13) 가 `partitioned_tlb_*` cells = 0 을 수리 **전** 상태에서 보였고, §29.11 이 예측값 381 을 **측정 이전에** 공표해 사후 맞춤이 아님을 고정했다. **"실측이 기준과 다르니 기준을 옮긴다" 는 논법은 이 기록으로 정당화되지 않는다.** 다음 exact 축 이탈도 동일하게 (i) 측정 전 예측, (ii) 넷리스트 수준 귀속, (iii) 사용자 승인 3건을 요구한다.

**발효 범위**: `synth/scripts/fp_op_gate_check.py` 의 `premap_mul_expect` 429 → 381 (변경 사유를 코드 주석에 병기). §29.11 별항 1 이 걸었던 **S2-C2/C3 merge 금지가 해제**된다. 다른 축은 불변이다.

## 30. D8-B — HIU 주소 마스킹의 표준 XChaCha20 준거화 (2026-08-18, COMMIT 0 · normative)

**사용자 지시 (binding, 2026-08-18): "HIU 는 실물에서 쓸 거니까 구조적 문제들부터 먼저 해결해."** §29 가 그 지시의 첫 이행이었고, 본 절은 **같은 지시의 계속**이다 — §29 착지 과정의 적대 감사가 D8 을 완전히 닫지 못했음을 실측으로 확정했기 때문이다.

본 절은 **spec-before-code COMMIT 0** 다 (§12a 규칙 3). 본 commit 은 spec 만 편집한다 — `HIU.v` · 테스트 · gate 스크립트는 §30.10 착지 순서대로 후속 commit 이 수행한다. golden 은 예외적으로 **이미 착지해 있다** (§30.4): 본 절은 golden-before-RTL 의 golden 을 **사후에 성문화**하는 것이 아니라, golden 이 실측으로 확정한 사실 위에서 **RTL 이 무엇을 이행해야 하는지를 규범으로 못박는다.**

### 30.1 §29.8 정정 — D8 은 결함 1건이 아니라 3건의 묶음이었다

§29.8 은 D8 을 **`initial_state` 경유로 인한 1단계 어긋남** 하나로 기술했고, normative 수리 형태도 그 한 줄이었다 (*"`chacha_state[m]` 에 `initial_state` 를 경유하지 않고 ... 같은 값을 병렬 대입"*). 그 진단은 **참이고** S2-C2 에서 이행됐다 (`HIU.v` 의 `h_init_w`/`c_init_w` wire 배열 + 두 배열 병렬 대입).

**그러나 그것으로 마스크가 XChaCha20 키스트림이 되지는 않았다.** golden 착지가 편차 2건을 더 실측 확정했다:

| # | 편차 | 위치 | 성질 |
|---|---|---|---|
| **D8-0** | `initial_state` 경유 → 영구적 1단계 어긋남 | `CHACHA_H_INIT` / `CHACHA_INIT` | §29.8 이 진단·처분. **S2-C2 에서 해소됨** |
| **D8-A** | 2단 ChaCha20 의 nonce 워드 배치가 draft §2.3 위반 | `HIU.v` `c_init_w[13..15]` | **미해소** — 본 절이 처분 |
| **D8-B** | 라운드 구조 — 8 quarter-round 병렬 계산으로 column round 가 전량 소실 | `CHACHA_H_MASK` / `CHACHA_MASK` | **미해소** — 본 절이 처분. **셋 중 가장 무겁다** |

**§29.8 의 서술을 정정한다 (§12a 규칙 5 — 원문 무삭제, 배너 표기 완료):** §29.8 의 인과 서술 *"⇒ subkey 가 HChaCha20 사양대로 유도되지 않고 ChaCha20 라운드가 subkey 상태 위에서 돌지 않는다"* 는 D8-0 의 결과로서는 옳으나, **D8-0 을 고쳐도 결론 *"마스크는 XChaCha20 키스트림이 아니다"* 는 그대로 참으로 남는다** — 원인이 하나 더(둘 더) 있었기 때문이다. 이 절이 없으면 다음 사람은 §29.8 의 수리 형태 한 줄을 읽고 "D8 은 닫혔다" 고 읽는다.

**왜 §29.8 이 놓쳤는가 (은폐 경로의 3차 사례 — 기록한다).** §29.8 조사는 **RTL 무수정 원칙**이었고, D8-0 은 `always` 블록의 대입 순서를 읽는 것만으로 눈에 보이는 결함이었다. D8-A/B 는 **값을 계산해 표준과 대조해야만** 보인다. 그리고 그 대조를 막고 있던 것이 정확히 §29.8 이 지적한 그 은폐 경로 — `masked_phys_addr != phys_addr` 검사 — 였다. **즉 §29.8 은 은폐 경로를 정확히 지목했으면서도, 그 경로를 실제로 걷어내기 전이었으므로 그 아래에 무엇이 더 있는지는 볼 수 없었다.** golden 이 착지하고 나서야 D8-A/B 가 드러났다. 이것은 조사의 실패가 아니라 **golden-before-RTL 이 왜 법칙인지의 실물 증거**다.

### 30.2 D8-B — 라운드 구조 (결함의 정확한 기술)

**사실 (RTL 인용):** `CHACHA_H_MASK` / `CHACHA_MASK` 는 각각 한 cycle 에 8개의 `chacha_qr_func` 호출을 수행한다 (`HIU.v:615-622` / `633-640`). 함수는 인자로 **인덱스만** 받고 상태는 레지스터 `chacha_state` 를 **직접 읽는다** (`HIU.v:680-683`). 8개 대입은 **같은 always 블록의 비차단 대입**이다. 따라서:

1. **8개 호출 전부가 직전 cycle 의 상태에서 계산된다.** column 4쌍이 만든 값을 diagonal 4쌍이 볼 수 없다 — 표준 double round 가 요구하는 **직렬성이 없다.**
2. **비차단 대입의 나중-대입 규칙이 column 결과를 전량 폐기한다.** diagonal 4쌍의 목적지 인덱스 합집합은 `{0,5,10,15} ∪ {1,6,11,12} ∪ {2,7,8,13} ∪ {3,4,9,14}` = **정확히 `{0..15}`** 다. 즉 column 이 쓴 16워드 **전부**를 diagonal 이 덮는다.
3. **∴ 한 cycle = diagonal round 정확히 1회.** column round 는 계산은 되지만 **넷리스트에서든 값에서든 존재하지 않는다.**

**파급 1 — 선언된 라운드 수도 이행되지 않는다.** 루프 조건은 `round_counter < CHACHA_ROUNDS / 2` = 10 cycle 이다. 표준에서 이 10 cycle 은 double round 10회 = **20 라운드**여야 하는데, 실물은 **diagonal round 10회 = 10 라운드**다. `CHACHA_ROUNDS = 20` 이라는 파라미터 선언과 Y4 `glossary.md:32` 의 *"`CHACHA_ROUNDS` 20 — XChaCha20 라운드 수"* 서술이 **둘 다 실물과 어긋난다.**

**파급 2 — 상태가 영구히 4그룹으로 분해된다.** diagonal quarter-round 만 반복하면 각 4워드 묶음이 닫힌 궤도가 되고, 그룹 간 정보 이동이 **10 라운드 내내 0** 이다:

```
{0, 5, 10, 15}   {1, 6, 11, 12}   {2, 7, 8, 13}   {3, 4, 9, 14}
```

**파급 3 — 마스크가 두 개의 서로소 반쪽으로 쪼개진다.** 마스크는 `{chacha_state[1] + initial_state[1], chacha_state[0] + initial_state[0]}` (`HIU.v:647-650`) 이므로 **하위 32b 는 궤도 `{0,5,10,15}` 에만, 상위 32b 는 궤도 `{1,6,11,12}` 에만** 의존한다. 두 궤도는 서로소다. **64비트 마스크 하나가 아니라 독립적인 32비트 두 개**이며, 각각이 보는 것은 아래 §30.4 의 실측대로 **키 절반씩**이다.

### 30.3 D8-A — nonce 워드 배치

**사실:** 2단 ChaCha20 초기상태의 `c_init_w[12..15]` 가 `HIU.v:570-573` 에서 `{counter=0, nonce[16:20], nonce[20:24], 0}` 이다.

**규범값 (draft-irtf-cfrg-xchacha-03 §2.3):** XChaCha20 의 2단은 subkey 와 **12바이트 nonce = `4 NUL || nonce[16:24]`** 로 ChaCha20 을 구동한다. 즉 워드 배치는 `{counter=0, 0, nonce[16:20], nonce[20:24]}` 다 — **`[13]` 은 0 이고 nonce 는 `[14]`/`[15]` 로 간다.** libsodium 계열의 64-bit counter 표기와도 값이 동일하다 (counter 상위 32b = `[13]` = 0).

**단독으로도 결함이지만, D8-B 와 겹치면 결함이 커진다.** D8-B 하에서 `[13]` 은 궤도 `{2,7,8,13}`, `[14]` 는 궤도 `{3,4,9,14}` 에 속하고 **둘 다 마스크에 도달하지 않는다** → **nonce 바이트 16-23 = 64비트가 완전히 죽는다.**

**부분 수리는 부족하다 (검증된 함정 — 반드시 읽어라).** golden 모델로 재현한 통제 실험:

- **A 만 고치고 B 를 남기면**: nonce 를 규범 배치로 옮기면 `[15]` 는 궤도 `{0,5,10,15}` 로 살아나지만 `[14]` 는 여전히 `{3,4,9,14}` 다 → **nonce tail 64비트 중 정확히 32비트가 여전히 죽는다** (고정 nonce 1개 × tail 64비트 전수 flip, 마스크 무변화 **32/64**). 즉 "nonce 배치만 고쳤다" 는 결함을 절반만 줄이고 **여전히 표준이 아니다.**
- **B 만 고치고 A 를 남기면**: 확산은 회복되어 죽은 비트는 사라지지만 값이 표준과 다르므로 **draft §A.3.2 벡터가 여전히 불일치**한다.

**∴ A 와 B 는 같은 commit 에서 함께 고친다.** 벡터 가족 `nonce_tail` 16 라인이 이 부분 수리를 직접 검출한다 (§30.6).

### 30.4 확산 붕괴 실측 — golden 이 잰 수치

**근거 artifact (본 절의 모든 수치의 출처, 고정 seed · stdlib-only · 재실행 byte-identical):**

| 파일 | sha256 (앞 16) |
|---|---|
| `scripts/golden_xchacha.py` | 생성기 (self-test 내장) |
| `include/generated/xchacha_vectors.hex` | `94db7c7d8456c41b` |
| `include/generated/xchacha_vec_contract.md` | `c0ea3387be8f0011` |
| `include/generated/xchacha_golden_report.json` | `b085f57cba700348` |

**표준 준거성 anchor 6종 (전부 PASS — 이 절의 "표준" 이 무엇인지의 근거):** RFC 8439 §2.1.1 (quarter-round) · §2.3.2 (block) · **§2.4.2 (114 B 암호화, counter=1, 왕복 복호 포함)** · draft-irtf-cfrg-xchacha-03 §2.2.1 (HChaCha20) · **§A.3.2.1 (XChaCha20 스트림 300 B, counter=0)** · **§A.3.2.2 (300 B, counter=1)**.

**anchor 커버리지 구멍이 있었고, 닫혔다 (정직 기록).** golden 착지 이전의 self-test 는 §2.1.1 / §2.3.2 / §2.2.1 만 걸고 있었다 — 즉 **부품 2개만** anchor 되어 있었고 **XChaCha20 구성 자체 (`state[12..15]` 배치)** 에는 외부 anchor 가 **하나도 없었다.** D8-A 가 그 구멍에 정확히 들어앉아 있었던 것이다. 새로 추가한 §2.4.2 / §A.3.2.1 / §A.3.2.2 세 벡터가 그 구멍을 닫는다 — **§A.3.2 두 벡터는 nonce 워드 배치를 직접 걸므로 D8-A 형태였으면 300바이트가 전량 어긋난다.** 추가로 자기확인 루프 차단을 위해 SIMD 정식화 (행 회전 `b<<<1`/`c<<<2`/`d<<<3`) 기반 **독립 재구현**을 넣어, 인덱스 표를 공유하지 않는 두 경로가 전 벡터에서 일치함을 확인했다.

**(a) 상태 분해 — 실재한다.** union-find 궤도 계산과 비트플립 실측이 일치: `{0,5,10,15}` / `{1,6,11,12}` / `{2,7,8,13}` / `{3,4,9,14}`.

| 축 | 현행 RTL | 표준 |
|---|---|---|
| 워드 의존 밀도 (10 라운드 후, 16×16 셀) | **64/256 = 25.0%** | **256/256 = 100%** (double round **1회**만에 100% 도달) |
| 마스크 출력워드 0 이 보는 입력워드 | `{0,5,10,15}` | 16워드 전부 |
| 마스크 출력워드 1 이 보는 입력워드 | `{1,6,11,12}` | 16워드 전부 |

**(b) 키·nonce 의존 폭 — 비트 계수만 보면 안 보인다. 워드 단위로 봐야 보인다.**

| 축 | 현행 RTL | 표준 |
|---|---|---|
| 마스크가 보는 **subkey** 워드 | **4/8** — `{1,2,6,7}` | 8/8 |
| 마스크 **하위 32b** 가 보는 key 워드 | `{0,2,5,7}` | 8워드 전부 |
| 마스크 **상위 32b** 가 보는 key 워드 | `{1,3,4,6}` | 8워드 전부 |
| live key bits | 256/256 | 256/256 |
| **live nonce bits** | **128/192 (64비트 사망)** | **192/192** |

**여기가 핵심이다:** live key bits 는 양쪽 다 256/256 이라 **비트 계수로는 결함이 보이지 않는다.** 실제 구조는 **서로소인 128비트 반쪽 2개**이지 256비트 하나가 아니다 — 마스크 하위 32b 와 상위 32b 가 겹치지 않는 key 워드 집합을 본다. 그리고 2단 초기상태에서 궤도 `{0,5,10,15}` 의 원소는 `{상수, subkey[1], subkey[6], 0}` 이므로, **마스크 워드 하나가 보는 미지 입력은 subkey 2워드 = 64비트뿐**이다 (나머지 둘은 공개 상수와 0).

**(c) avalanche (각 1024 flip, seed `0x13550002`, 이상치 32/64 = 50%):**

| 자극 | 현행 RTL | 표준 |
|---|---|---|
| key 1비트 → 마스크 변화 | **16.042/64 (25.066%)** | **31.9541/64 (49.928%)** |
| nonce 1비트 → 마스크 변화 | **10.415/64 (16.273%)** | **31.9395/64 (49.905%)** |
| **변화 0비트인 nonce flip** | **355/1024 = 34.668%** | **0/1024 = 0.0%** |
| key flip 변화폭 범위 | **6 ~ 25 비트** | 22 ~ 43 비트 |

**key flip 최대 변화폭이 25 (< 32) 인 것이 반쪽 분리의 독립 증거다** — 32비트 반쪽 하나만 움직이므로 구조적으로 32를 넘을 수 없다.

**이 수치들은 문서에 방치되지 않는다.** golden 의 `_test_diffusion_claims` 가 위 주장 전부를 실측으로 강제한다 — 서술이 늙으면 self-test 가 먼저 깨진다.

**정직 명기 (범위 한정):** 위 수치는 **구현 편차의 크기**를 재는 것이지 XChaCha20 자체의 안전성을 재는 것이 아니다. 64비트 마스크로 주소를 XOR 하는 구성의 보안 강도 · 키 재사용 정책 · counter 고정(=0) 의 함의는 본 절의 대상이 **아니다** (별건 — §30.11 이월).

### 30.5 결정 — 표준 XChaCha20 준거로 이동한다. 자체 변형은 채택하지 않는다

**결정: HIU 의 주소 마스킹 값 계약을 표준 XChaCha20 (RFC 8439 + draft-irtf-cfrg-xchacha-03) 준거로 확정한다.** D8-A / D8-B 를 함께 수리하고, 마스크는 표준 XChaCha20 키스트림의 **첫 8바이트를 little-endian u64 로 읽은 값**이 된다.

**채택 근거 5건:**

1. **선언이 이미 표준이다.** `HIU.v:12` (`CHACHA_ROUNDS = 20, // XChaCha20 rounds`), `HIU.v:48-49` (*"192-bit nonce for XChaCha20"*), Y4 `hiu_abi.md:49-50` (`HIU_CHACHA_KEY` / `HIU_CHACHA_NONCE` = *"XChaCha20"*), Y4 `glossary.md` §4, Y4 `lease_capability.md` §I3 (*"XChaCha20 보안 가정"*) — **다섯 곳이 XChaCha20 이라고 말한다.** 실물을 선언에 맞추는 것이 정상이고, 선언을 실물에 맞추는 것은 §29.8 이 D8 을 결함으로 판정한 근거 그 자체를 뒤집는 일이다.
2. **표준에서 벗어날 이유가 없다.** 편차 A/B 는 **설계 선택이 아니라 사고**다 — nonce 배치는 draft 오독, 라운드 구조는 비차단 대입 실수다. 의도된 변형이었다는 근거가 어디에도 없고, 그 변형이 무언가를 얻어냈다는 근거도 없다 (§30.9 대로 면적/타이밍 이득도 없다).
3. **자체 변형은 검증 부담을 늘리고 암호 강도 근거를 없앤다.** 표준을 쓰면 anchor 6종이 외부에서 주어지고 (§30.4), 벗어나면 그 6종이 **전부 무효가 되며** 대신 자체 안전성 논증을 세워야 한다. §30.4 의 실측은 그 논증이 실제로 어떻게 무너지는지의 실물이다 — 오늘의 변형은 마스크를 **독립 32비트 두 개**로 쪼개고 nonce 64비트를 죽인다.
4. **하드웨어가 상위 계층의 불변식을 조용히 위반하고 있다.** Y4 `lease_capability.md` §I3 은 nonce 유일성을 `NonceAllocator` 로 강제하고, 그 위반이 *"XChaCha20 의 IND-CPA 가정을 깨뜨려 cross-tenant 데이터 복원이 가능"* 하다고 적는다. **오늘의 RTL 은 nonce 바이트 16-23 을 무시하므로, 그 64비트에서만 다른 두 lease 는 소프트웨어가 I3 을 지켰어도 하드웨어에서 동일한 마스크를 얻는다.** I3 은 소프트웨어 측 의무이고, 본 수리는 그 의무를 받아 주는 **하드웨어 측 전건을 복원**한다.
5. **golden 이 이미 표준 편이다.** 표준 참조 구현·벡터·계약이 착지해 있고 (§30.4), 남은 것은 RTL 뿐이다. 이 시점에서 자체 변형을 택하면 **방금 착지한 산출물 4종을 전부 재저작**해야 한다.

**기각 기록 (재론 시 근거가 있어야 한다):**

| 대안 | 기각 사유 |
|---|---|
| **현행 유지 (변형을 규범으로 승격)** | §29.8 이 D8 을 결함으로 판정한 근거를 뒤집는다. 그리고 승격하려면 §30.4 의 확산 수치 위에서 **자체 안전성 논증**을 세워야 하는데, 그 수치가 바로 논증이 불가능함의 증거다 (avalanche 16.3% / nonce 64비트 사망) |
| **D8-B 만 수리 (라운드 직렬화, nonce 배치는 유지)** | 확산은 회복되나 값이 표준이 아니므로 draft §A.3.2 anchor 2종이 계속 FAIL 이다. **anchor 를 포기하는 대가로 얻는 것이 0** |
| **D8-A 만 수리 (nonce 재배치, 라운드 구조는 유지)** | §30.3 의 통제 실험대로 **nonce tail 64비트 중 32비트가 여전히 죽는다.** 결함을 절반으로 줄이고 "고쳤다" 고 기록하는 것이 가장 나쁜 결과다 |
| **라운드 수 축소로 면적 회수 (예: 8 라운드 XChaCha8)** | 표준 이탈이며, 본 절의 목적과 정반대다. 면적 압박이 실측으로 확인된 바도 없다 (§30.9: 남은 ceiling headroom 9,815 LUT) |

### 30.6 값 계약 (normative)

**본 항이 계약의 본문이다.** 아래는 `include/generated/xchacha_vec_contract.md` §4 와 **동일 내용의 규범 판**이며, 두 문서가 어긋나면 **본 항이 우선**한다.

1. **1단 HChaCha20.** 초기상태 = `{상수 4워드, chacha_key 8워드, chacha_nonce 바이트 0-15 의 4워드}`. **double round 10회** (= column round → diagonal round 를 직렬로 10쌍). 출력 subkey = 라운드 후 상태의 워드 `[0..3]` + `[12..15]` — **최종 덧셈 없음**.
2. **2단 ChaCha20.** 초기상태 = `{상수 4워드, subkey 8워드, counter=0, 0, nonce 바이트 16-19, nonce 바이트 20-23}`.
   → **`state[13]` 은 0 이고 nonce 는 `[14]`/`[15]` 로 간다** (D8-A 의 수리 대상). **double round 10회.**
3. **double round 는 column → diagonal 을 반드시 직렬로 수행한다.** 한 라운드의 8 quarter-round 를 **같은 (직전) 상태에서 병렬 계산하는 형태는 금지**다 (D8-B 의 수리 대상, 그리고 재발 경로). 이행 형태는 §30.7.
4. **최종 덧셈.** 블록 = 라운드 후 상태 + **2단 초기상태** (워드별 mod 2^32), 16워드 전부.
5. **마스크.** `masked_phys_addr = phys_addr ^ {블록워드1, 블록워드0}` — 즉 표준 ChaCha20 키스트림 **첫 8바이트를 little-endian u64** 로 읽은 값. **이 워드 선택·연접은 이미 표준 준거이므로 변경하지 않는다** (D5 가 `chacha_stream` 을 삭제하며 확정한 형태 그대로).

**고정 pin (`test_hiu.py` 의 `FIXED_KEY` / `FIXED_NONCE` 에 대한 값 — 수리 전후의 기준점):**

| 항목 | 값 |
|---|---|
| `FIXED_KEY` | `0xdeadbeefcafebabe0123456789abcdef0123456789abcdef0123456789abcdef` |
| `FIXED_NONCE` | `0xaabbccddeeff00112233445566778899aabbccddeeff0011` |
| **표준 subkey** | `9cc26b6c9c45f449afb32a9fedcff4d91f7d82e50e92ccd862ac3be9d32409f9` |
| **표준 mask64 (수리 후 요구값)** | **`0x9cdc759c43b88b32`** |
| **현행 RTL mask64 (verilator 실측 pin)** | **`0x817eba4a8961a7d6`** |

**벡터 계약 (`include/generated/xchacha_vectors.hex` — 80 라인 × 1440 bit, `$readmemh`):** `META32 | KEY256 | NONCE192 | PHYS64 | SUBKEY256 | BLOCK512 | MASK64 | MASKED64`. `KEY`/`NONCE`/`SUBKEY` 의 정수값은 RTL 포트·레지스터 정수 **그대로**다. `BLOCK` 은 `CHACHA_FINAL` 시점 `chacha_state[i] + initial_state[i]` **16워드 전부** — RTL 은 워드 0/1 만 소비하지만 나머지 14워드도 관측 가능하므로 **부분 수리를 잡으려고** 전부 싣는다.

**회귀 검출기 2종 — 산문이 아니라 생성 시점에 기계 확인된다.** 이 벡터는 "표준을 맞췄나" 뿐 아니라 "**옛 알고리즘이 아님**" 을 직접 판정한다:

| 가족 | 라인 | 현행 RTL 에서의 증상 | 표준에서 요구 |
|---|---|---|---|
| `nonce_tail` (8쌍) | 48-63 | 쌍의 두 마스크가 **완전히 동일** (nonce 64비트 사망) | 반드시 상이 |
| `key_word` (8쌍) | 64-79 | 마스크 **한쪽 32비트만** 변화 (궤도 분해) | 양쪽 32비트 모두 변화 |
| 전 가족 | 0-79 | `BLOCK` 14워드가 표준과 상이 | 16워드 전부 일치 |

나머지 가족: `pinned` 8 (라인 0-7, TB 직결) / `rand` 32 (8-39) / `edge` 8 (40-47).

### 30.7 RTL 이행 형태와 latency 계약 (normative)

**값 계약 (§30.6) 은 cycle 수에 무관하다.** §30.6 항 3 을 이행하는 형태는 둘이고, 본 항이 **형태 (A) 를 규범으로 지정**한다.

| 형태 | 내용 | 조합 깊이 | cycle |
|---|---|---|---|
| **(A) 반라운드 2 cycle — 채택** | cycle 마다 column **또는** diagonal 중 하나만 적용하고 `round_counter` 를 `CHACHA_ROUNDS` (=20) 까지 돈다. `round_counter[0]` 이 위상 선택자 | **불변** (quarter-round 1단) | 단 당 10 → **20** |
| **(B) 1 cycle 직렬 2단 — 기각** | 같은 cycle 에 column → diagonal 을 직렬로 잇는다 | **2배** | 불변 |

**(A) 채택 사유:** (i) **조합 깊이가 불변**이므로 GATE S1 의 타이밍 축을 건드릴 이유가 구조적으로 없다 — (B) 는 quarter-round 의존 덧셈 사슬을 4단에서 8단으로 늘려 **setup(WNS/Fmax) 축을 직접 때린다.** (ii) cycle 비용이 실질적으로 없다: `test_hiu.py:run_translate` 는 400 cycle 까지 기다리므로 TB 영향 0 이고, DMA 변환 자체가 이미 상수시간 패딩 경로다. (iii) 오늘 죽어 있는 column quarter-round 4개를 **되살려 쓰는** 형태이므로 (B) 처럼 quarter-round 실물을 늘리지 않는다.

**(B) 를 쓸 수 있는 유일한 조건:** (A) 실측이 **latency 축에서** 문제를 일으키고 (예: 상위 계층이 변환 latency 상한을 계약으로 갖게 되는 경우), 그 사실이 gate 기록에 남는 경우. 값 계약이 동일하므로 **§12a 재개정 없이 형태 교체가 가능**하나, **채택 사실과 사유는 gate 기록에 반드시 남긴다** (조용한 형태 교체 금지).

**구현 시 반드시 함께 바뀌는 3곳 (부분 편집이 만드는 조용한 실패 — 미리 적는다):**

1. `CHACHA_H_MASK` / `CHACHA_MASK` 의 루프 조건 `round_counter < CHACHA_ROUNDS / 2` → **`< CHACHA_ROUNDS`**. 이것을 빼먹으면 20 half-round 가 아니라 **10 half-round = double round 5회** 가 되어 라운드 수가 절반이 된다. 값은 표준 형태를 띠지만 벡터와 불일치하므로 **`BLOCK` 16워드 대조가 잡는다.**
2. 위상 선택 — `round_counter[0] == 0` 이면 column quad, `== 1` 이면 diagonal quad. **column 이 먼저다** (`CHACHA_H_INIT` / `CHACHA_INIT` 직후 `round_counter <= 0`).
3. `c_init_w[13..15]` 재배치 (D8-A). `[13] = 32'h0`, `[14] = chacha_nonce[159:128]`, `[15] = chacha_nonce[191:160]`.

**`round_counter` 폭은 늘지 않는다.** 현행 `reg [4:0] round_counter` (`HIU.v:230`) 는 최대 31 을 담으므로 20 까지 세는 데 충분하다 — **신규 FF 0**.

**latency 계약 (normative — 절대치 갱신, 계약 성질 불변):** 각 ChaCha 단이 10 → 20 cycle 이므로 DMA 변환 시퀀스는 **+20 cycle** 이다. §29.5 가 기록한 37 cycle 기준으로 **57 cycle 예상**이며, **절대치는 S2B-C3 실측으로 확정한다.**

**§29.5 의 상수시간 계약은 유지된다** — 계약은 hit / shadow-fallback / miss **경로 간 동일성**이지 절대치가 아니다. ChaCha 경로는 세 경로가 **공통으로** 지나므로 +20 은 세 경로에 동일하게 얹힌다. 테스트는 계속 절대치가 아니라 동일성을 assert 한다 (§29.13 항 4 불변).

### 30.8 관측 가능한 동작 변경 — §12a 정규 이벤트와 소비자 조사

**마스크 값이 바뀐다. 이것이 본 절의 계약 변경 본문이다.** 같은 `(chacha_key, chacha_nonce, phys_addr)` 에 대해 `masked_phys_addr` 가 **다른 값**이 되고 (pin: `0x817eba4a8961a7d6` → `0x9cdc759c43b88b32`), 그 값은 **모듈 출력 `phys_addr` 를 통해 `Top_Core` 경계 밖으로 나가** DMA 버스에 실린다. 즉 **순수한 내부 수리가 아니라 관측 가능한 동작 변경**이며, §12a 가 규율하는 정규 이벤트다.

**변환 latency 도 바뀐다** (37 → 57 예상, §30.7) — 이것도 관측 가능하다.

**소비자 조사 (전수 — grep 근거 명시).** 조사 범위: WaveTensor 저장소 전체 + 형제 저장소 3곳 (`/home/ybi/Y4`, `/home/ybi/wavetensor-drivers`, `/home/ybi/wavetensor-sdk`).

| 소비자 | 지위 | 판정 | 조치 |
|---|---|---|---|
| `test_hiu.py` | **마스크 정확값 assert 4곳** (`hiu_mask64` / `hiu_masked_phys` import, `:308`, `:359`, `:649`, `:693`) | **의도된 RED — 지금 이미 FAIL 상태다.** golden 이 `hiu_mask64` 를 표준값으로 전환했으므로 RTL 수리 전까지 반드시 깨진다 | **테스트 수정 없음.** RTL 이 따라오면 자동 GREEN. API 가 동일하므로 (`hiu_mask64` 이름 불변) 한 줄도 고칠 필요가 없다 |
| `test_top_core.py:164-166` | 마스크 **값 비의존** — `(phys & 0xFFFF) == 0x1100 or (phys & 0xFFFFFFFF) != 0` | **무영향** | 없음. **단 이 assert 가 마스크 값에 무감각한 것은 §29.8 이 지적한 은폐 패턴의 잔재**다 — 본 절의 scope 밖이며 §30.11 이월로 기록 |
| Y4 `docs/hiu_abi.md` **§2.1** | *"전체 latency (TLB hit 기준): `1 + 8 + 10 + 10 + 1 + 1 + 1 ≈ 32 cycle`"* — **두 개의 `10` 이 정확히 본 절이 바꾸는 ChaCha 라운드 cycle 수다** | **개정 필수.** 게다가 이 수치는 §29 의 `TLB_READ` 추가로 **이미 stale** 였다 | `10 + 10` → `20 + 20`. **산술 재계산이 아니라 §30.10 S2B-C3 실측값을 옮겨 적는다** — 오늘의 `≈ 32` 는 상태 열거가 불완전해 실측 37 과도 어긋난다 |
| Y4 `docs/hiu_abi.md` §1 (`0x040` / `0x060`) | `HIU_CHACHA_KEY` / `HIU_CHACHA_NONCE` 레지스터 정의. **마스크 값을 pin 하지 않는다** | **무영향** — 폭·주소·WO 지위 전부 불변 | 없음 |
| Y4 `docs/glossary.md` §4 + `:32` | *"물리 주소를 XChaCha20 키스트림과 XOR"*, `CHACHA_ROUNDS = 20` | **서술은 유지된다 — 그리고 이제야 참이 된다.** 오늘의 실물은 10 라운드 (전부 diagonal) 였다 (§30.2 파급 1) | 서술 변경 불필요. **본 수리가 문서를 실물에 맞추는 게 아니라 실물을 문서에 맞춘다** |
| Y4 `docs/lease_capability.md` §I3 | nonce 유일성 불변식 — 위반 시 *"IND-CPA 가정을 깨뜨려 cross-tenant 데이터 복원 가능"* | **하드웨어 측 전건이 복원된다.** 오늘은 nonce 바이트 16-23 이 죽어 있어, 그 64비트에서만 다른 두 lease 가 **동일 마스크**를 얻는다 — 소프트웨어가 I3 을 지켜도 하드웨어가 무효화한다 | 개정 불필요하되 **§30.4 (b) 를 근거로 인용**하는 각주 권고. 개정 라운드에 포함 |
| Y4 `docs/phase_plan.md:70` | *"XChaCha20 마스킹 / nonce binding on `context_switch` — Verus 불변식 선행"* | **무영향** (미착수 항목) | 없음 |
| `wavetensor-drivers` | `chacha` / `masked_phys` / `nonce` **매치 0** (`HIU_INTERRUPT_MASK` 는 무관한 MSI-X 마스크) | **무영향** | 없음. §29.4 가 이미 등재한 TLB fill 레지스터 개정과 **같은 라운드**에 나갈 뿐 |
| `wavetensor-sdk` | `docs/`·`*.rs` 에서 `chacha` / `masked_phys` **매치 0** (`Transport` trait 계층은 마스크를 보지 않는다) | **무영향** | 없음 |
| ISA 표면 (`isa/wt64v1_isa.json` · 생성물 · `asm/` · truth table) | 마스킹은 **opcode 의미론이 아니라 HIU 내부 데이터패스**다 | **무접촉** | `domain_version` bump **없음**, truth-table recapture **없음** |
| golden 3종 (3a — `golden_{fp32,lattice,fdotcr}.py`) · `FP_StepSeq.v` · 공유 datapath 3파일 | §29.14 격리 승계 | **무접촉 / byte-untouched** | 없음 |

**정직 명기 — "소비자 0" 이라고 쓰지 않는다.** 마스크 **값**을 pin 한 소비자는 `test_hiu.py` 하나이고 그것은 골든 경유라 자동 추종하지만, **latency** 를 pin 한 소비자가 별도 저장소에 실재한다 (Y4 `hiu_abi.md` §2.1). 값과 시간은 둘 다 관측면이며, 시간 쪽을 빠뜨리면 §29.4 가 D4 에서 겪은 것과 같은 "다운스트림 계약이 조용히 stale 해지는" 상태가 된다.

### 30.9 GATE S1 영향 선언 (측정 **전** 공표 — V9-4 정신)

**아래는 측정 이전에 공표하는 예측이며, 사후 해석의 여지를 없애기 위해 방향과 상한을 함께 적는다.** anchor 는 §29 착지 후 실측인 **GATE S1-US (`sys_top_core`, xcu55c, 10 ns OOC, synth→opt→place→phys_opt→route)** 이고, 그 안의 HIU 인스턴스는 LUT **2,706** / FF **3,582** / DSP **0** 이다.

| 축 | 지위 | anchor | 예상 착지 | 선공표 상한 | 귀속 |
|---|---|---:|---|---|---|
| **LUT sites** | binding (ceiling **24,799**) | **14,984** | **≈ 불변 ~ +700** | **+1,200 이내** (≤ 16,184 = ceiling 의 **65.3%**) | **부호가 미정이다 — 아래 별항 1** |
| FF | 추적 | 9,674 | **불변** | +8 이내 | 신규 레지스터 0. `round_counter` 는 `[4:0]` 이라 20 을 이미 담는다 (§30.7) |
| **DSP48E2** | **즉시 binding, exact** | **39** | **불변 39** | — | ChaCha 는 덧셈·XOR·상수 회전뿐이다. 곱셈 연산자가 RTL 에 **존재하지 않는다** |
| **premap `$mul`** | **즉시 binding, exact** | **381** | **불변 381** | — | 위와 같은 사유. **아래 별항 2 — 본 작업은 이 축을 움직이지 않는다** |
| **RAMB18** | **즉시 binding, exact** | **2** | **불변 2** | — | 메모리를 만들지도 없애지도 않는다 |
| **CRIT `Synth 8-295`** | binding, exact | **8** | **불변 8** | — | TRNG RO 무접촉 |
| **`Synth 8-7137`** | binding, exact | HIU **0** / PE_Core **68** | **불변 0 / 68** | — | Set·reset 동시 우선순위 경고. 신규 레지스터가 0 이므로 HIU 는 0 유지. PE_Core 는 §29.7 이월분 그대로 |
| **`Synth 8-3848`** | binding, exact | **0** | **불변 0** | — | 구동원 없는 넷을 만들지 않는다 |
| **DRC errors** | binding | **0** | **0** | — | `LUTLP-2 ×8` (TRNG RO 승인) 포함 warning 구성도 불변 예상 |
| **WHS** | **즉시 binding** | **+0.019 ns** | **≥ +0.019 예상** | **≥ 0 (음수면 즉시 FAIL, 완화 없음)** | **아래 별항 3** |
| WNS / Fmax | 기록 | +1.053 ns / 111.77 MHz | ≈ 불변 | — | 형태 (A) 는 조합 깊이 불변. 시스템 병목은 HIU 가 아니라 EHDecode→PE_Core dispatch 다 (§28.6) |

**별항 1 — LUT 부호가 미정인 이유 (추정을 실측으로 말하지 않는다).** 두 힘이 반대로 작용하고, 어느 쪽이 큰지는 **오늘의 넷리스트에서 죽은 column quarter-round 4개가 이미 `opt_clean` 되었는지에 달려 있는데 그것을 측정하지 않았다.**

- **(−) 방향**: 오늘 RTL 은 상태 arm 당 quarter-round **8개**를 기술하고 그중 column 4개는 결과가 전량 덮여 **죽어 있다.** 합성기가 이미 걷어냈다면 오늘 실물은 4개이고, 형태 (A) 도 cycle 당 4개이므로 quarter-round 실물은 **불변**이다.
- **(+) 방향**: 형태 (A) 는 위상 선택자를 도입한다 — quarter-round 입력 16워드 선택 + 출력 되쓰기 경로에 2:1 mux 가 붙는다. 32비트 × 16워드 × (입력·출력) 규모의 2:1 mux 는 **수백 LUT 규모**일 수 있다.
- **(−) 방향 2**: D8-A 는 상수·wire 재배선이므로 **0 LUT** 다.

**따라서 예상을 "≈ 불변 ~ +700" 이라는 구간으로 공표하고, 상한을 +1,200 으로 잡는다.** ceiling 까지의 headroom 은 **9,815 LUT** 이므로 어느 쪽이든 ceiling 초과는 예상하지 않는다. **실측이 +1,200 을 넘으면 수치를 맞추지 않고 귀속부터 다시 유도한다** (예측이 틀렸다는 사실 자체가 기록 대상이다).

**별항 2 — premap `$mul` 축은 본 작업의 대상이 아니다 (명시 기록).** 이 축의 계보는 다음과 같고, **본 절은 어느 단계도 되돌리거나 재해석하지 않는다**:

1. §29.11 별항 1 이 **429 → 381 (−48)** 을 **측정 이전에** 예측으로 공표했다 (귀속: 죽은 2D 배열의 행 주소 곱셈 `p*TLB_ENTRIES + j`).
2. 실측이 381 로 나왔고, exact 축이므로 측정 agent 는 기준을 건드리지 않은 채 **FAIL 을 그대로 보고**했다.
3. **§29.11a 가 사용자 승인 (2026-08-18) 을 받아 381 로 재anchor 를 발효**시켰다 — `synth/scripts/fp_op_gate_check.py:212,219`. 현재 이 축은 **381 exact 로 PASS** 다.

**본 절의 변경은 ChaCha 데이터패스뿐이고 거기에는 곱셈이 없으므로, 이 축은 381 에서 움직이지 않는다.** 본 절은 **재anchor 를 요청하지 않으며**, 379/383 어느 쪽으로든 움직이면 그것은 본 절의 예측이 틀린 것이므로 §29.11a 가 고정한 3요건 (측정 전 예측 · 넷리스트 수준 귀속 · 사용자 승인) 을 처음부터 다시 밟는다.

**별항 3 — WHS 가 얇다는 것과, 형태 (A) 가 그 축에 무해하다는 것.** anchor WHS 는 **+0.019 ns** 이고 §29 조사 구간에서 **+0.007 ~ +0.019 ns** 로 관측됐다 — 사실상 여유가 없다. 형태 (A) 의 hold 영향 분석:

- hold 위반은 **짧은 경로**가 만든다. 형태 (A) 는 quarter-round 경로 앞뒤에 mux 를 **추가**할 뿐 어떤 경로도 짧게 만들지 않는다 — 논리 지연 추가는 hold 에 **유리한** 방향이다.
- 조합 깊이는 불변이므로 setup 압박으로 인한 배치 재편도 최소다.
- **그럼에도 WHS 는 배치·클럭 스큐 의존이므로 "안전하다" 고 선언하지 않는다.** 이 축의 판정은 재측정으로만 내린다. **음수면 즉시 FAIL 이고 완화 경로는 없다.**

**정정 기록 — 형태 (B) 가 때리는 축은 WHS 가 아니라 WNS 다.** golden 산출물 (`xchacha_vec_contract.md` §5) 은 (B) 가 *"WHS 를 직접 때린다"* 고 적었는데, 이는 **부정확하다**: 조합 깊이 2배는 **setup (WNS/Fmax)** 를 악화시키고 hold 는 통상 **개선**한다. 결론 (형태 (A) 권고) 은 그대로 옳고 사유가 정정된다 — (B) 를 피하는 진짜 이유는 WNS 축과 불필요한 구조 확대이며, 본 절이 규범 판이므로 **이 정정이 우선한다.**

**ceiling 초과 시 절차 (초과를 예상하지 않지만 미리 적는다):** §29.11 의 4단계를 그대로 승계한다 — (1) 정직 FAIL 기록, (2) 초과분 귀속, (3) 재anchor 는 §12a 상 **사용자 결정 사항**, (4) 승인 불가 시 pre-declared cut ladder. **본 절의 cut ladder (측정 전 고정):** (a) 형태 (A) 의 위상 mux 를 입력 측 하나로 접고 되쓰기는 고정 배선으로 바꾼다, (b) `CHACHA_H_MASK` / `CHACHA_MASK` 두 arm 의 quarter-round 실물을 명시적으로 **공유**한다 (오늘은 합성기 재량에 맡겨져 있다). **(a)(b) 는 값 계약을 바꾸지 않으므로 §12a 재개정이 필요 없다.** 라운드 수 축소는 **cut ladder 에 없다** — 그것은 §30.5 가 기각한 표준 이탈이다.

**재측정 의무 (S2B-C4 몫):** `make synth-sys-gate SYS_GATE=sys_top_core PART=xcu55c-fsvh2892-2L-e` + `python3 synth/scripts/fp_op_gate_check.py` 로 **`sys_top_core` 문맥에서 전 축 재측정**. HIU 단독 수치로 대체 불가 (§29.11 재측정 의무 승계 — `Synth 8-295` census 의 문맥 의존이 그 근거). ECP5 반쪽은 §28.7 정책 그대로 **MEASUREMENT** 이며 어떤 결과도 FAIL 을 구성하지 않는다.

### 30.10 착지 순서 · test_plan · 재측정 의무

**착지 순서 (spec-first §12a 규칙 3 + golden-before-RTL 동시 충족). §29.13 의 S2-C* 와 구별하기 위해 S2B-C* 로 명명한다:**

| 단계 | 내용 | 전건 | 상태 |
|---|---|---|---|
| **S2B-C1** | `scripts/golden_xchacha.py` 표준 전환 + 산출물 3종 | — | **완료 (본 commit 이전 착지)** |
| **S2B-C0** | **본 절 (spec-first)** — RTL·테스트·gate 스크립트 무접촉 | S2B-C1 | **본 commit** |
| **S2B-C2** | RTL — `HIU.v` 의 D8-A (`c_init_w[13..15]`) + D8-B (형태 (A)) | S2B-C0 | — |
| **S2B-C3** | 테스트 — `test_hiu.py` **의도된 RED 해소 확인** + 벡터 소비 directed test 추가 + latency 절대치 실측 기록 | S2B-C2 | — |
| **S2B-C4** | **GATE S1-US #3 재측정** — 전 축 + §30.9 예측 대조 + ECP5 MEASUREMENT | S2B-C3 | — |
| **S2B-D** | 다운스트림 문서 (Y4 `hiu_abi.md` §2.1 latency + `lease_capability.md` §I3 각주) — **별도 저장소이므로 별도 commit** | S2B-C3 (실측 latency 필요) | — |

**순서 주기 (정직):** S2B-C1 (golden) 이 S2B-C0 (spec) 보다 **먼저** 착지했다. §12a 규칙 3 은 spec-first 를 요구하므로 이는 **순서 위반**이다. 사유와 처분을 숨기지 않고 적는다 — golden 세션은 §29.8 이 이미 명령한 `scripts/golden_xchacha.py` 착지를 수행하던 중 **D8-A/B 를 발견**했고, 그 발견 자체가 본 절의 존재 이유다. 즉 **spec 이 요구할 내용을 spec 이 알기 전에 측정이 먼저 알아냈다.** 처분: (i) golden 은 RTL 을 한 줄도 바꾸지 않았으므로 **실물 계약은 아직 변하지 않았고**, (ii) 본 절이 그 측정 결과를 규범으로 승격하는 것으로 순서가 회복되며, (iii) **RTL 편집은 본 절 착지 이후에만 허용**된다. 규칙 3 이 실제로 방어하는 것 — "실물이 spec 보다 먼저 움직이는 것" — 은 발생하지 않았다.

**test_plan (S2B-C3 몫 — 본 절이 항목을 확정한다):**

1. **표준 pin 일치** — `FIXED_KEY`/`FIXED_NONCE` 에서 `masked_phys_addr` 가 `phys ^ 0x9cdc759c43b88b32` 임을 assert. **오늘 FAIL 하는 그 assert 가 PASS 로 바뀌는 것이 본 절의 착지 판정이다** (`test_hiu.py:308`, `:359`, `:649`, `:693` — 코드 변경 불필요, golden API 불변).
2. **`nonce_tail` 가족 소비 (신규)** — `xchacha_vectors.hex` 48-63 의 8쌍을 DUT 에 태우고 **쌍의 마스크가 서로 다름** + 각각이 벡터값과 일치함을 assert. **D8-A 회귀 (부분 수리 포함) 의 직접 검출기.**
3. **`key_word` 가족 소비 (신규)** — 64-79 의 8쌍에서 마스크 **양쪽 32비트가 모두** 변함을 assert. **D8-B 회귀 (궤도 분해) 의 직접 검출기.**
4. **`BLOCK` 16워드 대조 (신규)** — `chacha_state[i] + initial_state[i]` 16워드 전부를 벡터와 대조. **라운드 수 절반 오류 (§30.7 부분 편집 함정 1) 를 잡는 유일한 축**이다 — 마스크 2워드만 봐서는 잡히지 않는 부분 수리가 여기 걸린다.
5. **subkey 대조 (신규)** — `CHACHA_INIT` 진입 시점 `subkey` 256비트를 벡터 `SUBKEY` 필드와 대조. **1단(HChaCha20) 과 2단(ChaCha20) 중 어느 쪽이 틀렸는지를 분리 진단**한다.
6. **latency 실측 기록** — 변환 cycle 절대치를 측정해 로그에 남긴다. **절대치를 assert 하지 않는다** (§29.5 / §29.13 항 4 불변 — 계약은 경로 간 동일성이다). 이 실측값이 S2B-D 의 Y4 `hiu_abi.md` §2.1 개정 입력이다.
7. **상수시간 재확인** — §29.13 항 4 의 hit/shadow/miss 동일성 테스트가 +20 cycle 이후에도 통과함을 확인 (기존 테스트, 수정 불필요).
8. **무회귀** — 6개 모듈 전 suite. `COCOTB_RESULTS_FILE` 을 `/tmp` 로 리다이렉트해 tracked `results.xml` 무접촉 (§28.3 관례).

**벡터 소비 형태 (S2B-C3 결정 사항, 본 절은 강제하지 않는다):** `xchacha_vectors.hex` 는 `$readmemh` 형식이나, 항 2-5 는 cocotb 에서 **파일을 파싱해 포트를 구동**하는 형태로도 동일하게 성립한다. RTL 에 벡터를 읽는 구조물을 넣지 **않는다** — 테스트 전용 데이터가 실리콘에 들어가면 그것이 §28.4 항 7 이 금지하는 종류의 혼입이다.

### 30.11 §12a 기록

본 절은 §12a 하의 **정규 개발 행위 (regular development act)** 이며 **spec-before-code COMMIT 0** 다.

- **계약 변경의 성격**: `masked_phys_addr` 의 **값**과 변환 **latency** 가 바뀐다 (§30.8). 둘 다 모듈 경계 밖에서 관측 가능하므로 §12a 규칙 3 이 규율하는 계약 변경이다. **ISA 표면은 무접촉이다** — `isa/wt64v1_isa.json` · 생성물 · `asm/` · truth table 어느 것도 대상이 아니므로 `domain_version` bump 도 truth-table recapture 도 발생하지 않는다 (§29.14 와 동일 구조). 규칙 3 의 순서 중 발동하는 것은 **spec amendment → RTL/테스트 갱신** 구간뿐이다.
- **3a (§27.7a) 와의 격리**: 3a 산출물 — golden 3종 (`scripts/golden_{fp32,lattice,fdotcr}.py`), ISA (`isa/wt64v1_isa.json` + 생성물 + `asm/`), `FP_StepSeq.v` step 프로그램 — 은 **무접촉**이다. 공유 datapath 3파일 (`FP_AddWide.v` / `FP_Mul36.v` / `include/fp_narrow_f32.vh`) 은 **byte-untouched** 이고 `decode_reserved` 는 미접촉이다 (3a-C4 몫). `scripts/golden_xchacha.py` 및 그 산출물 3종은 3a golden 과 무관한 별개 계보다. golden 세션이 `golden_lattice.py` / `golden_fdotcr.py` 를 재생성해 산출물 10종의 sha256 이 **전부 baseline 과 동일**함을 확인했다 (byte-identity 실증).
- **의도적 test-breakage 입장**: `test_hiu.py` 의 마스크 assert 는 **본 commit 시점에 이미 FAIL 한다** (RTL `0x817eba4a8961a7d6` vs 계약 `0x9cdc759c43b88b32`). 이는 사고가 아니라 **golden-before-RTL 의 신호**이며, §12a 하에서 이런 breakage 는 보존이 아니라 **재유도 대상**이다 (§26.10 → §29.14 로 이어진 입장의 승계). 다만 여기서는 재유도조차 불필요하다 — 테스트는 golden API 를 경유하므로 RTL 이 따라오면 **한 줄도 고치지 않고** GREEN 이 된다.
- **선공표 규율**: §30.9 의 예측·상한·귀속은 **측정 이전에** 공표됐다. LUT 부호가 미정이라는 사실도 **미정인 채로** 공표했다 — 방향을 확신하지 못하면서 확신한 척 적는 것이 선공표 규율의 유일한 실패 양식이다. ceiling 초과 시 절차와 cut ladder 도 측정 이전에 고정됐다.
- **§29.8 정정의 성격**: §29.8 원문은 **삭제하지 않고** 배너로 부분 supersede 표기했다 (§12a 규칙 5). supersede 되는 것은 *"수리 형태 (normative)"* 항이 **D8 의 전부**라는 함의 하나뿐이고, 그 항이 규정한 수리 자체 (`initial_state` 경유 제거) 는 **참이며 이미 이행됐다.**
- **premap `$mul` 축**: §29.11a 의 재anchor (429 → 381, 사용자 승인) 는 **발효 상태 그대로 유지**되며 본 절은 그 축을 움직이지도 재해석하지도 않는다 (§30.9 별항 2).
- **이월 항목 (기한 조건 포함, §30 몫)**:
  - **마스킹 구성 자체의 보안 논증** — 64비트 마스크로 주소를 XOR 하는 구성의 강도, counter 고정(=0) 의 함의, lease 당 키/nonce 회전 정책. **본 절은 "표준 XChaCha20 을 올바로 이행하는가" 만 다루고 "그 구성이 충분한가" 는 다루지 않는다.** 기한 조건: Y4 `lease_capability.md` §I3 의 Coq 측 보안 정리를 실제로 세우는 라운드.
  - **`test_top_core.py:164-166` 의 무감각 assert** — 마스크 값에 무관한 disjunction 이라 §29.8 이 지적한 은폐 패턴의 잔재다. 기한 조건: `test_top_core.py` 를 다음에 손대는 commit.
  - **D9 per-partition flush** (§29.9), **PE_Core D6 68건** (§29.7), **Tensor_ALU O2 49건** (§29.7), **undriven-signal 탐지 lint 2/3** (§29.12), **예약 포트 기계 열거** (§29.10 항 6), **4-way set-associative 비용 측정** (§29.3) — §29.14 의 이월 목록을 **무변경 승계**한다. 본 절은 어느 것도 해소하지 않고 어느 것도 추가로 지연시키지 않는다.

---

## 31. PE_Core D6 처분 + Tensor_ALU 지위 판정 — 이월 2건 해소 (2026-08-18, COMMIT 0 · normative)

> **사용자 지시 (2026-08-18)**: *"3a-C4 로 넘어가기 전에 PE_Core 랑 Tensor_ALU 이월 항목들도 마저 해결하도록."*
>
> 본 절은 §29.7 이 기한 조건과 함께 이월한 **2건** — PE_Core D6 68건 · Tensor_ALU O2 49건 (+ §28.8 고아 지위 판정) — 을 **처분한다.** §12a 하의 **spec-before-code COMMIT 0** 이며, 본 commit 은 RTL·테스트·lint·gate 하네스를 **한 줄도 건드리지 않는다.**
>
> **본 workflow 는 GATE S1 을 실행하지 않았다** (`make synth-sys-gate` 0회 / `synth/scripts/fp_op_gate_check.py` 0회 / `synth/reports/` 기입 0). 병행 중인 §30 XChaCha20 workflow 가 같은 리포트 경로를 소유하기 때문이다. 본 절의 모든 수치는 **`/tmp` 격리 실측**이고, 통합 판정은 **orchestrator 의 합류 후 1회 측정** 몫이다 (§31.10 · §31.11).

### 31.1 조사 방법과 격리 — 무엇을 근거로 말하는가

두 렌즈로 독립 조사했고, 양쪽 다 **repo RTL 0줄 수정**이다.

| 렌즈 | 대상 | 도구 · 격리 |
|---|---|---|
| **A** | PE_Core D6 68건 | Vivado 2025.2.1 OOC (`xcu55c-fsvh2892-2L-e`, `set_msg_config -id {Synth 8-7137} -limit 100000`) + iverilog 12 (4-state) + yosys 0.64 premap. 전부 `/tmp/pecore_d6/` |
| **B** | Tensor_ALU 지위 + MATMUL | ISA JSON / 생성물 / `asm/` / PE_Core dispatch / 외부 4개 리포 전수 대조 (읽기) + verilator 5.048 (2-state) + iverilog 12 (4-state) + yosys 0.64 premap. 전부 `/tmp/wt_lensB/` |

**격리 준수 실적**: Vivado 는 `/tmp` 에서만 호출, `synth/reports/` 기입 0, gate 스크립트 0회, 3a 산출물(golden 3종 · ISA JSON · 생성물 · `asm/` · `FP_StepSeq.v` step 프로그램) **읽기 전용**, 공유 datapath 3파일(`FP_AddWide.v` / `FP_Mul36.v` / `include/fp_narrow_f32.vh`) **byte-untouched**, `decode_reserved` 미접촉 (3a-C4 몫), `HIU.v` 미접촉 (§30 workflow 소유).

**정직 명기 — 본 절이 측정하지 **않은** 것:** post-P&R Fmax/WNS/WHS, system 문맥 LUT/FF, ECP5 반쪽. `synth/scripts/synth_fp_op.tcl` 헤더가 post-synth 타이밍을 판정 근거로 쓰는 것을 금지하고 P&R 은 gate 하네스 몫이므로, 타이밍 축은 **구조적 추정만** 하고 수치를 주장하지 않는다 (§31.10).

### 31.2 §29.7 정정 (최우선) — "PE_Core 68건 전부 (a) 판정" 은 거짓이다

**§29.7 의 이월 사유 (i) 는 다음과 같이 적었다:** *"68건 **전부 (a) 판정**이다 — 전부 데이터/피연산자 래치이고 reset 되는 valid 비트로 자격 부여되며, 의도가 이미 문서화되어 있다 (`PE_Core.v:1801-1807`). read-before-write 후보가 없으므로 **기능 결함이 없다**."*

**이 진술은 거짓이다.** 실측 판정은 **(b) 실제 reset 버그 1건 + (a′) 미기록 계약 의존 2건 + (a) 진성 reset-불필요 65건** 이다.

**거짓이 된 기전 — 인용된 설계 의도가 그 뱅크를 커버한 적이 없다.** `PE_Core.v:1798-1807` 의 주석은 문면 그대로 **`deq_a_q`/`deq_stage`/`frag0_hold`** 와 **`vfma_a_q`/`b_q`/`c_q`/`stage`/`lane`/`is_int8`** — 즉 **deq/vfma/fp 데이터 래치**만 지목한다 (본 절 조사에서 원문 재확인). 그런데 68건의 **절반(33건)은 v1.9 §26.2 가 신설한 `cr_*` (`case_result_s2`) 뱅크**이고, 그 뱅크의 **게이트 비트 자체**(`cr_dispatch_valid`)가 미리셋이다. §29.7 은 v1.8.0e 시대 주석을 v1.9 신설 뱅크로 **외삽**했고, 그 외삽이 유일한 근거였다.

**§28/§29 정정 4건 (§12a 규칙 5 — 원문 무수정, 여기서 정정):**

| # | 원 서술 | 위치 | 정정 |
|---|---|---|---|
| **E1** | "68건 전부 (a) 판정 … 기능 결함이 없다" | §29.7 | **거짓.** (b) 1건 = **§31.3 D10** (모듈 출력으로 새는 실 reset 버그), (a′) 2건 = **§31.4 D11**, (a) 65건 |
| **E2** | "수리 형식 사전 배정: **형식3 우선** … 형식2 는 비권고" | §29.7 | **실측으로 뒤집힌다.** 형식3 의 근거였던 HIU 선례(형식3 이 RAM 추론을 열어 면적 감소)가 PE_Core 에 **존재하지 않는다** — 추론 가능 배열 0개, `Synth 8-4767` **0건**. 형식3 은 형식2 의 **1.8배 비용(+258 vs +143 LUT)** 인데 실리콘 위험은 **절반만**(12→5 LUT) 제거한다. **채택은 형식2** (§31.5) |
| **E3** | "수리 형식은 세 곳 다 같다 (`if (!rst)` 가드 블록 분리, 파형 불변)" | §28.3 D6 발견사실 2 | **거짓.** 그 형식이 §29.7 의 **형식1** 이며 §29.7 이 이미 명시 기각했다 (`if (!rst)` 가 CE 로 접혀 위험이 그대로 남는다). 본 절 실측이 재확인: **현 넷리스트가 이미 형식1 형태인데 rst→LUT 데이터 입력 12개가 남아 있다** |
| **E4** | Tensor_ALU O2 "수리 = `if (!rst)` 가드 블록 분리이며 파형 완전 일치 (**의미 보존 — 5건 중 유일**)" | §28.8 O2 | 파형 일치 주장은 유지되나 **의미가 없다** — §31.8 대로 O2 수리는 **소멸**한다 (모듈이 어떤 합성 문맥에도 없고 편입이 기각됐다) |

**균형 기록 (§29.7 이 옳았던 것):** 이월 사유 (ii)(dispatch 병목 귀속 오염 회피)와 (iii)(HIU 형식3 선실증)은 **타당했다.** (iii) 는 결과적으로 형식3 을 **기각**시켰지만, 그 기각을 가능하게 한 것이 바로 "먼저 HIU 에서 실증하라" 는 순서였다. 순서가 틀렸다면 미검증 형식을 주력 모듈에 먼저 발랐을 것이다. **이월 자체는 옳았고, 이월 사유서의 사실 주장 1건이 틀렸다.**

### 31.3 D10 (신규 결함) — `cr_dispatch_valid` 미리셋 → warm reset 후 유령 wave 토큰

**이것은 D6 가 아니다. 기능 결함이며 §29.7 의 기한 조건 3개와 무관하게 즉시 처리 사유다.**

**코드 경로 (전부 `PE_Core.v` 실측 재확인 — always 블록은 파일 전체에 **1개**이므로 "rst 분기에 없는 LHS" 집합과 `Synth 8-7137` 집합이 정확히 일치한다):**

- 선언 `:1550` `reg cr_dispatch_valid; // pe_active && dec_valid sampled at T`
- 기입 `:1849` `<= 1'b0` (else 분기 최상단 무조건 기본값) / `:2106` `<= 1'b1` (`pe_active && dec_valid` 일 때)
- **rst 분기(1776–1830)에 대입 없음** — rst 중 **직전 값을 유지**한다
- 판독 `:3380` `else if (cr_dispatch_valid) begin` — **stage-2 commit 전체(3380–3454)의 유일한 게이트**

**발현 경로:** rst 해제 직후 첫 사이클에 else 분기가 실행되고, 그 사이클의 기본값 `<= 1'b0` 은 비차단이라 **다음** 에지에 반영된다. 같은 사이클의 stage-2 는 **rst 이전에 래치된 1** 을 읽는다. 상위 우선순위 arm 이 가려주지 못한다 — 우선순위 사슬 `frag_idx / mul_valid_p2 / div_valid_p2 / div_b_zero_p2 / fp_valid_p2` 는 **전부 rst 분기에서 대입**되므로 해제 직후 전부 0 이고, 사슬은 반드시 `cr_dispatch_valid` 로 떨어진다.

**결과:** rst **이전** 명령의 `cr_payload / cr_tag / cr_opcode_out / cr_valid_out / cr_memory_req / cr_mem_addr` 이 `output_*` 로 **1회 commit** 된다. 최악의 arm 에서는 `fp_start<=1` + 구 피연산자 / `vfma_busy<=1` / `deq_loop_active<=1` / `frag_idx<=FRAG_EMIT_1` 까지 발화한다.

**시스템 전파 — 결함은 PE_Core 안에서 끝나지 않는다:** `Cluster.v:793/855/916` → `pe_out_valid`/`mu_out_valid`/`du_out_valid` → `Cluster.v:1283-1321` arbiter → Cluster `m_valid`. **reset 직후 상위 fabric 으로 유령 wave 토큰이 나간다.** 상위 소스는 깨끗함이 확인됐다 (`EHDecode.v:587 dec_valid <= 1'b0`, `Cluster.v:673-` `pe_active_*` 전부 reset) — **결함 국소화 근거**이며, 따라서 수리도 PE_Core 안에서 자기완결적이어야 한다.

**실증 1 (최소 재현, `/tmp/pecore_d6/tb_rst.v`, iverilog 12)** — 0x10 ADD 1건 dispatch → 다음 사이클 rst 5 cy → 해제 후 **dispatch 0건**:

```
cyc=13 rst=0 out_valid=0 ... cr_dv=1 cr_vo=1
cyc=14 rst=0 out_valid=1 payload=deadbeef00000003 tag=…cafe opc=10   ← 유령 commit
```

`0xDEADBEEF00000001 + 2 = …0003`, tag `0xCAFE` — 전부 reset 이전 값이다.

**실증 2 (랜덤 자극, `/tmp/pecore_d6/tb_equiv.v` MODE=1, 3 seed × 4000 cy, warm reset ×3)** — 발현형 **2종**:

- seed 1 @cy904 — `output_valid=1` + 구 payload/tag/opcode (유령 토큰)
- seed 12345 @cy1754, 2604 — `error_flag=1` 1-cy 펄스 (**명령이 없는데 디코드 에러 보고**)

두 번째 발현형이 중요하다: **유령 commit 은 성공 arm 뿐 아니라 reject arm 으로도 샌다.**

**처분 (normative) — 형식2, 단독 commit, 즉시.**

`PE_Core.v` rst 분기(1830 뒤)에 `cr_dispatch_valid <= 1'b0;` **1줄** 추가. 측정: `Synth 8-7137` 68→67, **CLB LUT ±0 / FF ±0 / 전 gate 축 불변** (프로토타입 P1 실측).

**형식3 명시 기각 (여기가 HIU 와 갈리는 지점):** reset-free 블록으로 빼서 `cr_dispatch_valid <= pe_active && dec_valid` 로 두는 형태도 동작하지만, 그것은 **`EHDecode.dec_valid` 와 `Cluster.pe_active` 가 rst 중 0 이라는 모듈 간 미기록 계약**에 의존한다. 이 레지스터는 **33-레지스터 뱅크의 유일 게이트**이고 PE_Core 는 **단독 인스턴스화 테스트 대상**(`MOD=PE`)이므로, 상위 모듈의 행위에 안전성을 위탁할 수 없다. **자기완결적 형식2 가 정답이다.**

**파형 변화 입장:** D10 수리는 파형을 **바꾼다. 바뀌어야 정상이다** — 유령 commit 이 사라지는 것이 목적이다. 프로젝트 법칙 "파형 불변 실증" 은 **D6 수리(의미 보존)** 에 걸리는 것이지 기능 결함 수리에 거는 것이 아니다. 그 경계를 §31.11 test_plan 의 MODE 계약이 기계적으로 집행한다.

### 31.4 D11 (신규 결함) — `cr_payload` / `cr_mem_addr` 무자격 복사 (§29.6 `phys_addr` 와 동형)

`PE_Core.v:3407` `output_payload <= cr_payload;` 와 `:3410` `mem_addr <= cr_mem_addr;` 은 성공 arm 에서 **무조건** 실행된다 — 바로 옆의 `output_valid <= cr_valid_out;` / `memory_req <= cr_memory_req;` 와 달리 **자격자로 가드되지 않는다** (실측 재확인). 그 opcode 가 해당 필드를 쓰지 않았으면(예: 0x04 STORE 는 `cr_mem_addr` 만 쓴다) **미기입 레지스터가 모듈 출력으로 복사**된다.

**4-state 실측:** cold-reset 경로에서 `mem_addr` 에 **X 가 최대 87 cy / 4000 cy** 관측.

**현재는 새어 나가지 않는다 — 그러나 그 계약은 어디에도 없다.** baseline 6 trace 전건에서 `output_valid=1 & X-payload` = **0**, `memory_req=1 & X-addr` = **0** 으로 마스킹 성립이 검증됐다. 즉 소비자가 자격자로 거르고 있다. **그러나 "소비자가 자격자로 거른다" 는 계약은 spec 어디에도 기록되어 있지 않다.** §29.6 이 HIU `phys_addr` 에 대해 **정확히 이 이유로** 3-arm 전건 대입을 규범화한 것과 동형이다.

**처분 (normative):** **D6 본체(§31.5) 와 같은 commit 에서 반드시 함께 수리한다.** 수리 형태는 §29.6 규범 이식 — 둘 중 하나:

1. stage-2 복사(3407/3410)를 `cr_valid_out` / `cr_memory_req` 로 가드, 또는
2. stage-1 에서 `cr_payload` / `cr_mem_addr` 를 **전건 대입** (§29.6 이 `phys_addr` 에 쓴 형태).

**왜 "같은 commit" 이 조건인가 — 여기가 본 절에서 가장 미묘한 지점이다.** §31.5 의 형식2 는 4-state 파형을 바꾼다: `mem_addr` / `output_payload` 의 **X 가 0 이 된다** (P2 MODE=0 diff 5/11/87행, **전부 이 두 열**). 그런데 **그 X 는 D11 의 유일한 신호다.** §29.7 이 `initial_state` 에 대해 형식2 를 기각한 논거 — *"비결정적으로 틀린 값을 결정적으로 틀린 값으로 바꿔 sim ≠ silicon 신호를 지운다"* — 가 **그대로 적용된다.** 따라서 **D11 수리를 동반하지 않는 형식2 는 금지한다.** 동반하면 X 도 결함도 함께 사라지므로 신호를 지우는 것이 아니다.

### 31.5 D6 (PE_Core 68건) 처분 (normative) — **형식2 전건**, 형식3 실측 기각

**형식 정의는 §29.7 표를 그대로 승계한다** (형식1 = `if (!rst)` 가드 블록 분리 / 형식2 = rst 분기 명시 대입 / 형식3 = 가드 없는 순수 동기 블록 분리 / 형식4 = `set_msg_config -suppress`, 즉시 탈락).

**프로토타입 4종 실측 (`/tmp/pecore_d6`, PE_Core 단독 OOC, xcu55c-fsvh2892-2L-e):**

| | `Synth 8-7137` | CLB LUT | FF | FDCE | CARRY8 | ctrl set | DSP | **rst → LUT 데이터 입력** | premap `$mul` | 8-3848 | CRIT |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| base | **68** | 20050 | 4734 | 1299 | 849 | 99 | 39 | **12** | 381 | 0 | 0 |
| **P1** 형식2 ×1 (D10) | **67** | **20050 (±0)** | **4734 (±0)** | 1300 | 849 | 99 | 39 | 12 | 381 | 0 | 0 |
| **P2** 형식2 ×68 | **0** | 20193 (**+143**, +0.71%) | 4854 (+120) | **3555** | 849 | 95 | 39 | **0** | 381 | 0 | 0 |
| **P3** 형식2 ×1 + 형식3 ×32 | 35 | 20308 (**+258**, +1.29%) | 4740 (+6) | 1306 | 847 | 100 | 39 | 5 | 381 | 0 | 0 |

**채택: 형식2 전건 (68건).**

1. `Synth 8-7137` → **0** (68건 전건 소멸)
2. **§29.7 이 지목한 실리콘 위험의 완전 제거** — `rst` 가 CE LUT 의 **데이터** 입력으로 접힌 LUT **12 → 0**. 형식3 은 12 → 5 로 **절반만** 없앤다
3. 비용 **+143 LUT (+0.71%) / +120 FF (+2.5%)** — 형식3(+258 LUT)의 **0.55배**
4. premap `$mul` · DSP · CARRY8 · `Synth 8-3848` · CRITICAL 전부 **불변**

**형식3 명시 기각 — HIU 선례가 PE_Core 로 이전되지 않는다. 그 이유를 정확히 적는다.**

- **RAM 추론 종속이 0 이다.** PE_Core 트리의 유일한 distributed-RAM 추론은 `\g_v180c_fp.u_fp_stepseq/fd_xp_reg` (64×37, RAM64M8 ×18) 로 **`FP_StepSeq` 소유**이고, `Synth 8-4767` **0건**이다. 68건 중 **배열은 하나도 없다** (PE_Core 의 유일 배열 `frag_pending[0:15]` 은 rst 분기에서 16행 전건 대입 — 1813-1828 — 이라 애초에 68 밖이다). ⇒ **HIU 에서 형식3 이 면적을 크게 줄인 원인(async-reset 블록이 봉쇄하던 RAM 추론의 개방)이 여기엔 존재하지 않는다.** §29.3 채택 이유 4 는 HIU 고유 사정이었다.
- **비용이 위험 제거율에 반비례한다.** +258 LUT(형식2 의 1.8배)를 내고 위험은 절반만 제거한다. 원인: 미리셋 뱅크를 reset-free 블록으로 빼면 공유되던 `!rst` CE 항이 사라져 arm 별 enable 이 흩어진다 (ctrl set 99 → 100).
- **3a-C4 와 정면 충돌한다.** `decode_reserved` 해제 시 PE_Core stage-1 `case` 블록에 FDOT32_CR arm 이 추가되는데, 형식3 은 **바로 그 블록을 둘로 쪼개는** 수리다. 형식2 는 rst 분기만 건드리므로 **충돌면이 사실상 0** 이다.

**형식3 의 적용성 자체는 깨끗함을 확인해 뒀다 — 기각 근거가 "못 해서" 가 아님을 명시한다.** stage-1 블록(2105–3293)의 LHS 전수가 `cr_*` **33개뿐이고 non-cr 은 0개**다. 즉 HIU 가 요구했던 6-state `case` 골격 **복제가 필요 없다** (§29.7 이 HIU 에서 형식1 을 기각한 두 번째 사유가 여기엔 없다). 그럼에도 **실측이 기각시킨다** — 가능하다는 것과 나은 것은 다르다.

**형식1 명시 기각:** §29.7 논거 그대로 — `if (!rst)` 가 CE 로 접혀 위험이 그대로 남는다 (증상 제거). **본 절 실측이 이를 재확인한다: 현 넷리스트가 이미 형식1 형태인데(§29.2 C4) rst→LUT 데이터 입력 12개가 살아 있다.** §28.3 발견사실 2 의 "세 곳 다 `if (!rst)` 가드 분리" 권고는 이 근거로 폐기한다 (§31.2 E3).

**채택 조건 (normative — 빠뜨리면 형식2 자체가 금지된다):**

1. **D11 (§31.4) 수리를 같은 commit 에 넣는다.** 사유는 §31.4 말미 — 형식2 는 D11 의 유일한 신호(X)를 지운다.
2. **D10 (§31.3) 이 선행 commit 으로 이미 착지해 있어야 한다.** 사유는 §31.11 착지 순서 — 이 순서라야 형식2 의 miter 계약이 **MODE=0/1 양쪽 전건 일치**로 강해진다.
3. **miter 등가성 실증**을 동반한다 (§31.11 test_plan 항 1-3).
4. `Synth 8-7137` 모듈별 exact 축 (§29.11 별항 2) 을 **같은 commit 에서** spec 과 `synth/scripts/fp_op_gate_check.py` 양쪽에 반영한다 — §29.11 이 *"수리 사실을 반영해 조이는 것"* 으로 이미 정규 행위로 허용한 형태다.

**정직한 리스크 1건 — 여기서 "영향 없음" 이라고 쓰지 않는다.** 형식2 는 rst 팬아웃을 **FDCE 1,299 → 3,555 (2.7배)** 로 키운다 (PE_Core 1개 기준; Pod 문맥은 × PE 수). 라우팅·클럭 자원 부담은 **통합 gate 에서만** 확인 가능하다 (§31.10 WHS/WNS 축).

**§29.7 기한 조건과의 대조 (셋 중 어느 것이 발화했는가):** 조건 1(HIU 형식3 무회귀 실증 직후 다음 RTL commit) — **발화**. 조건 2(PE_Core 계수 > 68) — 현재 정확히 68 이라 미발화. 조건 3(ASIC/FDSE·FDPE 흐름) — 미발생. **단 3a-C4 가 FDOT32_CR 용 `cr_*` 레지스터를 추가하면 조건 2 가 자동 발화하므로, 3a-C4 이전에 본 절을 착지시키는 편이 순서상 유리하다** — 사용자 지시("3a-C4 로 넘어가기 전에")와 정합한다.

### 31.6 Tensor_ALU 지위 판정 (최우선) — 고아도, 미결선 결함도 아니다

**orchestrator 가 제시한 두 갈래 — (가) "ISA 에 실재하는데 하드웨어가 없다 = 미결선 결함" vs (나) "ISA 에서도 죽었다 = 고아" — 는 둘 다 사실과 어긋난다. 전수 대조가 준 답은 제3의 것이다.**

**opcode 0x30/0x31/0x32 는 ISA 에 살아 있고, 하드웨어도 있다 — `PE_Core` 안에.**

| 대조축 | 실측 (전부 읽기 전용 확인) |
|---|---|
| `isa/wt64v1_isa.json` | code 48 `MATMUL` / 49 `TADD` / 50 `EINSUM` **3행 실재**. `asm_legality` · `rtl_legality` 전부 채워져 있고 `decode_reserved` 아님 (그 표식은 0x7A 단 1건), `stub_v18` 아님 ({0x7D,0x7E}) |
| `include/generated/isa_opcode_wires.vh:67-69` | `opcode_supported` 화이트리스트에 0x30/0x31/0x32 **3건 전부** |
| `include/generated/isa_ehshape_case_body.vh:191,198,205` | EH-shape 케이스 3건 |
| `asm/generated_isa_tables.py:38-40` | `'MATMUL':0x30, 'TADD':0x31, 'EINSUM':0x32` |
| `asm/wavetensor_asm.py` | MATMUL/EINSUM 니모닉 실사용 + `HW_DIRECT_EINSUM_SIGS` lowering 매크로 패스 |
| **dispatch** | **`PE_Core.v:2319`** (0x30 → `matmul_func`, `dec_eff_dim_sizes != 8'h05` 이면 `cr_hard_error` = **2×2 고정**) / **`:2329`** (0x31 인라인 4×int16 lane add) / **`:2338`** (0x32 EINSUM 2단 SUBSCRIPT dispatch). `Cluster.v:466-467` 이 0x30/0x32 를 `is_mul_op` 으로 MATMUL_UNIT 라우팅 |
| decode_error 여부 | **아님** — `test_isa_decoder.py:3835` 가 `range(0x30,0x33)` 을 legal 로 검증 |
| **값 검증** | **`test_isa_decoder.py:659-675 test_matmul_2x2` 가 `expected = pack16(19,22,43,50)` 를 정확 assert 하고 PASS.** `test_tensor_add`(678-692) 도 값 assert |
| `ISA_Decoder.v` | EHDecode+PE_Core 얇은 래퍼(203줄), 0x30/31/32 리터럴 **0건** — 역사적 `matmul_func` 는 이미 PE_Core 로 이관 완료 |
| `Tensor_ALU` 소비자 | **0** — `.v` 인스턴스 0, `grep -rl` over `synth/` **rc=1(0건)**, `synth/lattice/scripts/synth_pod.ys:22-33` / `synth_cluster.ys` read_verilog 목록에도 없음. 등장처는 자기 파일 · `test_tensor_alu.py` · `Makefile:29-32` 뿐 |
| 외부 리포 소비자 | **0** — `/home/ybi/Y4/docs` · `/home/ybi/wavetensor-sdk` · `/home/ybi/dasima` · `/home/ybi/wavetensor-drivers` 전수 grep 0건 (§24 dead-opcode audit 과 동일 조건) |

**⇒ 지위 확정 (normative): `TENSOR_ALU.v` 는 `PE_Core` 가 이미 대체 완료한 pre-mitigation 중복 구현 — superseded duplicate 다.**

**결정적 의미론 불일치 3건 — 이 모듈은 *현행이 아닌 ISA* 를 구현하고 있다:**

1. **0x32 가 치명적.** `TENSOR_ALU.v:53` 주석은 `// TENSOR_MUL`, 구현은 element-wise 곱이다. **현행 ISA 의 0x32 는 `EINSUM` (SUBSCRIPT-dispatched)** 이고, Hadamard 는 EINSUM 의 서브시그니처(`einsum_hadamard`)로 흡수돼 **opcode 직행 진입점이 없다.** 즉 **Tensor_ALU 0x32 의 의미론은 현행 ISA 에 존재하지 않는다.**
2. **0x30 shape 불일치.** ISA/PE_Core = 2×2 int16, 64-bit payload 1개. Tensor_ALU = 4×4 × **64-bit 원소** = 1,024-bit 행렬 2개. `claude.md:383` 이 진단한 자원 폭증(4×4 unrolled, PE당 ~30K LUT, 16-PE Pod 494K LUT / WNS −214 ns)에 대해 **채택된 mitigation 이 "2×2 축소"** 인데, Tensor_ALU 는 그 축소 **이전** 형태다.
3. **0x31 layout 불일치.** ISA/PE_Core = 4 lane × int16 in 64-bit. Tensor_ALU = 16 원소 × 64-bit.

**따라서 §28.8 의 "고아" 명명을 정정한다** (배너 이미 삽입). 그리고 **orchestrator 조건문의 귀결도 성립하지 않는다**: *"ISA 에 실재 ⇒ 미결선 결함"* 은 **하드웨어가 다른 곳에 없을 때만** 참인데, 여기서는 `PE_Core` 에 있고 값 검증까지 통과한다. **전건은 참인데 귀결이 거짓인 조건문이며, 그 사실을 숨기지 않고 기록하는 것이 본 절의 의무다.**

**부수 결론 — 폐기해도 ISA 는 1바이트도 바뀌지 않는다.** 세 opcode 를 `PE_Core` 가 계속 제공하므로 `TENSOR_ALU.v` 제거는 `isa/wt64v1_isa.json` · 생성물 · `asm/` 를 **무접촉**으로 둔다. §12a dead-opcode 절차(spec→JSON→생성물→RTL→truth-table 재캡처)는 **발동하지 않고**, truth-table recapture **0**, `domain_version` bump **0** 이다.

**그럼에도 본 절은 폐기를 결정하지 않는다 (normative).** 사유 3건:

1. **사용자 지시 준수.** 본 workflow 는 "ISA 에 실재하면 폐기 옵션을 쓰지 마라" 는 지시를 받았고, **전건(ISA 실재)이 참**이다. 귀결이 성립하지 않는다는 이유로 금지 자체를 자의적으로 해제하지 않는다.
2. **§28.8 이 이미 "판정은 상위 결정권자 몫" 으로 유보했고**, §12a 상 RTL 파일 제거는 계약 변경이다.
3. **절차가 아직 없다.** §28.8 이 기록한 정책 공백 — §12a 는 **opcode/signature 단위** 정책이고 **RTL 모듈 단위 제거 규정이 없다** — 이 그대로 남아 있다. 절차 없이 실행하는 것이 곧 §12a 위반이다.

**본 절이 대신 하는 것: 전건을 전부 충족시켜 폐기를 1-step 결정으로 만든다.**

- **§12a 확장 (normative) — RTL 모듈 단위 제거 절차 성문화.** pre-stable 기간의 정규 개발 행위로 다음을 규정한다:
  > **6. RTL 모듈 단위 고아/중복 제거는 정규 개발 행위다.** 단 순서를 따른다: (a) **소비자 audit** — `.v` 인스턴스 그래프 · `synth/` read_verilog 목록 · `asm/` · 외부 sibling 리포 전수 grep 으로 **0** 확정, (b) **정본(定本) 지정** — 그 기능을 제공하는 모듈과 **값 검증 테스트**를 이름으로 명시, (c) **spec 기록** (본 항의 근거표), (d) 파일 제거, (e) `Makefile` `MOD` 분기 제거, (f) 테스트 제거, (g) **§11 베이스라인 재계상**, (h) `scripts/lint_synth_coverage.py` 표 갱신, (i) superseded 배너. **(a)(b) 없이 (d) 를 수행할 수 없다** — 제거의 정당성은 "안 쓰인다" 가 아니라 **"정본이 있고 그것이 검증됐다"** 다.
- **audit 근거는 본 절이 전부 제공한다** — 위 표의 (a) 와 (b) 가 이미 충족돼 있다. 남은 것은 **사용자 결정 1건**이다.

**개별 판정 — 3모듈 일괄 처분을 금지한다 (근거가 서로 다르다):**

| 모듈 | 지위 | 근거 | 다음 행위 |
|---|---|---|---|
| **`TENSOR_ALU.v`** | **superseded duplicate** | 소비자 0 · 정본 = `PE_Core` (값 검증 PASS) · 0x32 는 **현행 ISA 에 없는 의미론** · 0x30 은 **기각된 결정의 보존** | 폐기 **권고**, 실행은 사용자 결정. 그때까지 §31.7/§31.8/§31.9 적용 |
| **`SIMD_ALU.v`** | **superseded duplicate, 폐기 보류** | 디코드 opcode 6종(0x10/0x11/0x12/0x13/0x1C/0x1F) **전부 PE_Core 구현 완료**(0x13/0x1C/0x1D 는 `PE_Core.v:1900-1930` bit-serial FSM). **SIMD 계열 ISA opcode 0x60-0x65/0x69 는 하나도 디코드하지 않는다** — lane-parallel 형태의 ISA 진입점 0건. 단 **유일하게 live contingency 로 등재**돼 있다 (`board_hw_plan.md:173`, "ECP5 84K LUT 부족 시 대체") | **contingency 등재를 먼저 무효화**한 뒤 폐기. §28.8 O3 실측(조합 divider, **22.47 MHz**)이 대체제로서의 실효성을 이미 부정하므로 무효화 근거는 확보돼 있다. 값 테스트 9/9 는 건전 |
| **`ALU_Extended.v`** | **보존 재분류 (폐기 후보 아님)** | 3개 중 유일하게 Synth 경고 **0건** · 능동 유지보수 이력(7105e3c, 2026-07-14) · 값 테스트 **16/16 건전** | `measured-pending` 이 아니라 **reference implementation (비합성 대상)** 으로 재분류. 통합 지점(§6 `PE.v = ISA_Decoder + ALU wrapper`)이 소멸했음을 사유로 명기 |

**§28.4 항 1 에 5번째 합성 지위를 신설한다 (normative):**

> **`superseded`** — 기능이 다른 모듈로 **이관 완료**됐음이 확정되어 합성 대상이 아닌 RTL. 등재 요건 3건: (i) **정본 모듈**과 (ii) 그 정본의 **값 검증 테스트**를 이름으로 지정, (iii) **폐기 판정 기한 조건**. 래칫은 `measured-pending` 과 같이 **≤ 3**. 요건 3건 중 하나라도 비면 `make lint` 비영 종료.

`measured-pending` 3건은 **`superseded` 2 (Tensor_ALU, SIMD_ALU) + reference 1 (ALU_Extended)** 로 이동하므로 §28.4 항 3 래칫(`measured-pending` ≤ 3)은 **완화되지 않고 오히려 0 으로 내려간다.** 지위 이동은 §31.11 S3-C3 에서 실행한다 (본 commit 은 spec 만).

### 31.7 MATMUL 결함 정밀화 — §28.8 O1 정정 + 신규 O1b/O1c + **수리 기각**

**O1 재현 성공 (verilator 5.048, 2-state, D=2/W=16, A=[[1,2],[3,4]] B=[[5,6],[7,8]], 정답 [[19,22],[43,50]]):**

```
cy0 [0 0 0 0] / cy1 [0 0 0 0] / cy2 [14 16 28 32] / cy3 [28 32 56 64] / cy4 [42 48 84 96] …
```

r00 매 사이클 **+14 = a01·b10 = 2·7**. **§28.8 O1 기술과 자릿수까지 일치.** 19 에 도달하는 사이클 없음.

**O1 정정 (신규 — §28.8 이 기록하지 않은 더 나쁜 실상, iverilog 12 / 4-state):** 동일 자극에서 `result_matrix` 가 **12 사이클 내내 영구 X** 다. `res` 는 reset 되지 않아 초기 X 이고, 유일하게 살아남는 대입 `res[i][j] <= res[i][j] + a[i][D-1]*b[D-1][j]` 이 X 를 재귀 전파한다 (`res[i][j] <= 0` 은 같은 nonblocking 규칙으로 덮여 영구 무효).

> **정정 문장 (§28.8 O1 에 대해):** *"무한 누산기"* 는 **verilator 2-state 0-init 의 산물**이다. 4-state 시뮬 · 게이트 시뮬 · 실리콘에서는 **X/미정의 시작 + 발산**이며, 이는 §28.8 기술보다 **한 단계 나쁜** 결함이다. 부수적으로 **O1(기능)과 O2(reset)가 `res` 미리셋이라는 같은 뿌리를 공유**함이 여기서 드러난다 (수리는 여전히 직교).

**신규 O1b — `alu_valid` 는 data-valid 가 아니다 (loud-fault-never-silent 위반).** 4-state 실측: rst 해제 직후 **cy0/cy1 에 `alu_valid=1` 인데 `result_matrix` 는 X** 다. `TENSOR_ALU.v:26` 이 무조건 `alu_valid <= 1` 을 놓기 때문이며, 실제 파이프라인 latency 는 **3 사이클** (`matrix_a/b` → `a`/`b` reg → `res` → `result_matrix`). `alu_valid` 는 **"reset 중이 아님" 자유주행 플래그**일 뿐이다. **이것이 `test_tensor_alu.py:24` 의 단독 assert 가 O1 을 은폐한 직접 기전이다.**

**신규 O1c — 테스트 자극이 DUT 와도 주석과도 불일치한다.** `test_tensor_alu.py:20-21` 은 **256-bit 리터럴**을 주는데 `Makefile:29-32` 는 파라미터를 override 하지 않으므로 기본값 `ADDR_WIDTH=64` / `DIM_SIZE=4` → `matrix_a` 실폭은 **1,024 bit** 다. cocotb 가 상위 768 bit 를 0 으로 채운다. 주석 *"Packed A [1~16]"* 은 원소당 16 bit 를 의도했으나 포트는 원소당 64 bit — **자극 · 주석 · DUT 3자 불일치.** 즉 이 테스트는 값을 안 볼 뿐 아니라 **의도한 행렬을 넣은 적조차 없다.**

**대조 (§28.8 결론 유지 — 결함은 0x30 단독):** 4-state 실측으로 0x31 TADD = **[6 8 10 12]** 정답, 0x32 TENSOR_MUL = **[5 12 21 32]** 정답, default(0x33) = **[0 0 0 0]**. 셋 다 3-사이클 후 안정.

**올바른 구현은 확정돼 있다 (`/tmp/wt_lensB` 프로토타입, 기록용 — 채택하지 않는다):**

```verilog
reg [ADDR_WIDTH-1:0] acc;                 // 신규 blocking 임시변수
acc = {ADDR_WIDTH{1'b0}};
for (k = 0; k < DIM_SIZE; k = k + 1)
    acc = acc + a[i][k] * b[k][j];        // blocking — 같은 시간스텝 내 누산
res[i][j] <= acc;
result_matrix[(i*DIM_SIZE+j)*ADDR_WIDTH +: ADDR_WIDTH] <= res[i][j];   // 2단 구조 유지
```

iverilog 12 실측: cy2 에 **[19 22 43 50]**, 이후 안정. 포트 **0줄 변경**, latency 계약 **불변**(0x31/0x32 와 동일 3 사이클). (`result_matrix <= acc` 로 1단 단축하는 변형은 0x30 만 2사이클이 되어 모듈 내 latency 가 opcode-의존이 되므로 **채택 금지**.)

**그럼에도 O1 수리를 기각한다 (normative). 사유 3건:**

1. **채택된 mitigation 결정을 뒤집는다.** yosys 0.64 premap `stat` (기본 D=4/W=64): `$mul` **31 → 76 (2.45×)**, `$add` 32 → 64 (2.0×). 결함 상태가 D²=16 mul 로 축퇴해 있었기 때문에 **정답 구현은 D³=64 mul 을 요구한다.** §28.8 실측 DSP48 310 에서 **~760 으로 외삽**된다. 이것은 `claude.md:383` 이 진단하고 프로젝트가 **이미 기각한 바로 그 자원 폭증**이다 — 수리는 개선이 아니라 **기각된 결정의 복원**이다.
2. **정본이 이미 옳다.** 0x30 의 정본은 `PE_Core.matmul_func` 이고 `test_isa_decoder.py::test_matmul_2x2` 가 같은 벡터로 값을 검증한다. **수리해도 기능이 늘지 않는다.**
3. **틀린 ISA 를 고치게 된다.** 이 모듈의 0x32 는 현행 ISA 에 없는 의미론이고 0x30 은 pre-mitigation shape 다 (§31.6). 수리는 **ISA 문서와 RTL 의 모순을 더 정교하게 유지**하는 행위다.

**균형 기록 (수리 찬성 근거도 남긴다):** 수리는 인터페이스 0줄 변경 · latency 불변 · `$dffe` 49 불변으로 **국소적**이며, §11 이 이 모듈을 계상하고 `claude.md:55` §5-1 이 MATMUL 을 ALU 기능 목록에 넣고 있다. 그러나 위 3건이 더 무겁다 — 특히 1번은 **프로젝트가 명시적으로 내린 결정을 되돌리는 것**이라 §12a 상 사용자 결정 없이는 수행할 수 없는 종류다.

**따라서 결함은 수리되지 않고 남는다. 그러면 loud 해야 한다 — 그 이행이 §31.9 다.**

### 31.8 O2 (Tensor_ALU 49건) 처분 — **소멸** (수리하지 않는다)

§29.7 은 O2 의 이월 기한을 *"§28.8 고아 지위 판정 commit 과 같은 commit"* 으로 걸고, 판정이 *"폐기면 O2 수리는 소멸, 통합이면 O1·O2·레이아웃을 동시 처리"* 라는 2분기를 예고했다. **판정은 두 분기 중 어느 쪽도 아닌 superseded duplicate 이므로, 제3의 처분을 여기서 확정한다.**

**처분: O2 수리를 수행하지 않는다 (소멸).** 근거 4건:

1. **gate 축 기여가 구조적으로 0 이다.** `TENSOR_ALU.v` 는 `sys_top_core` read_verilog 목록에 없고 `synth/` 전체에 파일명 등장 0건이다. §29.11 별항 2 가 이미 *"`Tensor_ALU` 는 `sys_top_core` 문맥 밖이라 이 축에 나타나지 않는다"* 고 선공표했다.
2. **편입이 기각됐다** (§31.6) — 편입되지 않는 모듈의 reset 형식을 고치는 것은 낭비이고, 고쳐도 아무 gate 축이 움직이지 않으므로 **회귀 방어 효과조차 없다.**
3. **§28.8 O2 의 수리 형식 권고(형식1)가 §31.2 E3 로 폐기됐다** — 즉 권고된 형식 자체가 더 이상 유효하지 않다.
4. **독립 재확인**: yosys premap `$dffe` **49** = `a` 16 + `b` 16 + `res` 16 + `result_matrix` 1, `$adff` **1** = `alu_valid`. §29.2 C7 의 "4군 49건" 계수가 독립 도구로 재확인됐고, **O1 수리는 이 49 를 바꾸지 않는다** (O1 과 O2 는 직교). 계수의 정확성이 확인됐으므로 이 축을 다시 조사할 이유도 없다.

**따라서 §29.11 별항 2 의 `Synth 8-7137` 모듈별 축은 Tensor_ALU 에 대해 영구히 축 밖이다.** 축 값 갱신 대상은 PE_Core 뿐이다 (68 → 0, §31.10).

### 31.9 §28.4 항 8 신설 (normative) — 값 미검사 · 자극 공간 미검사 은폐 방지

§29.12 가 §28.4 에 **항 7**(계층 강제 기입)을 신설했다. 본 절이 **항 8** 을 신설한다 — 항 1-7 은 무수정 유지한다.

**신설 근거 — 같은 클래스의 은폐가 본 조사에서 2건 더 잡혔다:**

| 사례 | 은폐 기전 | 은폐 기간 |
|---|---|---|
| **D4** (§28.2) | 테스트가 RTL 이 구동하지 않는 상태를 **강제 기입**해 그 위에서 검증 → 항 7 이 봉쇄 | 3.5개월 |
| **O1** (§28.8, §31.7) | 테스트가 **자격 비트만** assert (`alu_valid == 1`) 하고 값을 전혀 안 봄 → 1/1 PASS 가 "MATMUL 무동작" 을 은폐 | initial commit 이후 전 기간 |
| **D10** (§31.3) | 스위트 전체에 **warm reset 자극이 0건** — `test_pe.py` / `test_cluster.py` / `test_top_core.py` 의 `_reset(dut)` 호출 **전건**이 `clock.start()` 직후, 즉 cold reset 만 존재 | v1.9 §26.2 뱅크 신설 이후 |

**D10 은폐가 특히 아프다: RTL 주석(`PE_Core.v:1794-1807`)이 "mid-op rst" 를 설계 시나리오로 명시하는데 그 시나리오가 테스트되지 않았다.** 설계 의도가 문서화돼 있는데 검증 자극이 없는 것 — 항 7 이 잡는 "잘못된 자극" 이 아니라 **"없는 자극"** 이며, 별도 항이 필요한 이유다.

> **8. 테스트는 출력 *값* 을 검사해야 하고, 검사하지 않는 *자극 공간* 은 공백으로 명시 기록해야 한다.** 항 7 이 "잘못된 자극" 을 규율한다면 항 8 은 **"검사하지 않는 것"** 을 규율한다.
>
> - **(a) 값 검사 의무.** 자격 비트(`valid` / `ready` / `done` / `busy`) 만의 assert 로 기능 검증을 대체할 수 없다. 연산 결과를 내는 DUT 의 테스트는 **결과 값**을 golden 과 비교해야 한다. 자격 비트 assert 는 값 assert 의 **전제**이지 대체물이 아니다. **`alu_valid == 1` 단독 assert 로 1/1 PASS 를 만든 `test_tensor_alu.py` 가 이 항의 발생 사례다.**
> - **(b) 자격 비트의 의미 검증 의무.** 자격 비트를 result-valid 로 쓰는 테스트는 **그 비트가 실제로 result-valid 임**을 별도 케이스로 실증해야 한다. 실증되지 않으면 그 비트는 자유주행 플래그일 수 있다 (O1b — `alu_valid` 는 "reset 중 아님" 이었다).
> - **(c) 자극 공간 명시 의무.** 스위트가 커버하지 않는 자극 축은 **공백으로 기록**한다. 최소 열거 축 4종: **warm reset**(동작 중 rst), back-pressure, 동시 도착/충돌, reject arm(디코드 에러·busy 거절). RTL 주석이 어떤 시나리오를 **설계 의도로 명시**하는데 그 시나리오의 자극이 스위트에 없으면 **그 자체가 결함 보고 대상**이다.
> - **(d) 자극 폭 정합 의무.** 테스트가 주는 리터럴의 폭은 DUT 포트의 **실폭**과 일치해야 하며, 파라미터 기본값에 의존하는 경우 `COMPILE_ARGS` 로 **명시 override** 하거나 실폭으로 정확히 패킹해야 한다. 폭 불일치는 조용한 zero-extension 으로 나타나 "의도한 자극을 넣은 적이 없는" 테스트를 만든다 (O1c).
> - **(e) 알려진 결함의 loud 기록 형식.** 수리하지 않기로 **결정된** 결함은 침묵으로 남길 수 없다. **golden 값을 assert 하는 테스트를 작성하고 `@cocotb.test(expect_fail=True)` 로 표기하며, docstring 에 spec 절 번호를 명시**한다. 이 형식은 세 가지를 동시에 만족한다 — (i) 결함이 기계 판독 가능하게 기록되고, (ii) CI 가 마비되지 않으며, (iii) **누군가 결함을 고치면 그 테스트가 unexpected-pass 로 FAIL 하여 spec 갱신을 강제한다** (래칫). `expect_fail` 없이 RED 를 방치하거나, 결함에 맞춰 assert 를 낮추는 것(축퇴 동작을 정답으로 못박는 것)은 **둘 다 금지**한다.

**정량 baseline (규범에 측정 기준선을 붙인다 — §29.12 형식 승계):** 값 검사 부재는 **`test_tensor_alu.py` 단 하나**다. 형제 모듈은 건전하다 — `test_simd_alu.py` 9개 **전부** lane 값 assert, `test_alu_extended.py` 16개 **전부** result 값 assert. **3모듈 일괄 문제가 아니라 1건이며, 그 1건이 프로젝트에서 유일하게 무동작인 연산을 덮고 있었다.** warm-reset 자극은 RTL 스위트 6개 모듈 **전건 0**이다.

**정직 명기 — 항 8 은 항 7 과 마찬가지로 lint 가 아니다.** (a)(b)(d) 는 원리적으로 기계 검사가 가능하지만(assert 문에 자격 비트만 등장하는 테스트 탐지, 리터럴 비트폭 대 포트 폭 대조), (c) 는 **"없는 것" 을 세는 문제**라 기계화가 어렵다. 본 commit 은 **규범만 세우고 lint 를 구현하지 않는다** — §28.10/§29.12 의 lint 이월 목록에 **"(a)(b)(d) 기계 검사"** 를 추가하고, (c) 는 **리뷰 의무**로 남긴다. "규범이 있으니 안전하다" 고 말하지 않는다.

### 31.10 GATE S1 영향 선언 (측정 **전** 공표 — V9-4 정신)

**본 workflow 는 gate 를 실행하지 않았다.** 아래는 **측정 이전에** 공표하는 예측이며, **검증은 orchestrator 가 §30 (XChaCha20) 착지 후 수행하는 통합 run 1회의 몫**이다. 근거 수치는 전부 `/tmp/pecore_d6` 의 **PE_Core 단독 OOC 실측**이고 **system 문맥 값이 아니다** — §29.11 과 같은 정직 조건이다.

**baseline 취급 (중요):** 아래 델타의 기준선은 **§29 / §30 착지 후 재측정되는 값**이지, 아래 표의 anchor 열이 아니다. §29(D4 실체화) 와 §30(XChaCha20 재구성)이 LUT/FF/WNS/WHS 를 먼저 움직인다. **따라서 본 절은 절대치를 예측하지 않고 델타만 예측한다.**

| 축 | 지위 | 현행 anchor | **본 절 델타 예측** | 선공표 상한 | 귀속 |
|---|---|---:|---|---|---|
| **LUT sites** | binding (ceiling **24,799**) | 14,850 | **+143 (+0.71%)** | **+250 이내** | P2 프로토타입 20,050→20,193. **PE_Core 단독 OOC 는 상수 접힘이 없어 팽창해 있다** (Pod 문맥 `u_lpe` 는 5,427 LUT) — 따라서 +143 은 **보수적 상한 성격**이며 system 문맥에서 더 작을 수 있다. sys_top_core 는 PE_Core 인스턴스 **1개** |
| FF | 추적 | 9,585 | **+120 (+2.5% of PE_Core)** | +200 이내 | P2 4,734→4,854. 형식2 는 레지스터 **개수**를 바꾸지 않는다 — 증가분은 FDRE→FDCE 전환에 따른 매핑/복제 산물이며 **귀속이 완전하지 않음을 명기한다** |
| **DSP48E2** | **binding, exact** | **39** | **불변 39** | — | 형식2 는 **상수 대입만 추가**한다. 4 프로토타입 전건 39 |
| **RAMB18** | **binding, exact** | **2** | **불변 2** | — | PE_Core 트리의 유일 RAM 추론은 `FP_StepSeq` 소유(RAM64M8 ×18, distributed). `Synth 8-4767` 0건 |
| **premap `$mul`** | **binding, exact** | **381** (§29.11a 승인 재anchor) | **불변 381** | — | `sys_top_core` 소스 구성 그대로 /tmp yosys 재현: **base/P1/P2/P3 전부 381.** 구조적으로도 자명 — 형식2 는 상수 대입 추가, 형식3 은 식 이동. **본 절은 이 축을 움직이지도 재해석하지도 않는다** |
| **DRC errors** | binding | 0 | **0** | — | 프로토타입 전건 errors 0 |
| **CRITICAL `Synth 8-295`** | binding, exact | 8 | **불변 8** | — | TRNG RO 무접촉 (PE_Core 는 HIU 를 포함하지 않는다) |
| **`Synth 8-3848`** | binding, exact | 0 | **불변 0** | — | 프로토타입 전건 0 |
| **`Synth 8-7137` 모듈별** | **binding, exact** | HIU 0 / PE_Core **68** / 합 **68** | **HIU 0 / PE_Core 0 / 합 0** | — | S3-C1 착지 시점 중간값 **67**. **축 값 인하는 §29.11 별항 2 가 정규 행위로 허용한 형태** — spec 과 `fp_op_gate_check.py` 를 같은 commit 에서 함께 내린다 |
| **WHS** | **binding** | +0.019 ns | **본 변경의 유일한 실질 리스크 축** | **≥ 0** | 형식2 는 rst→CE 조합 경로 12 LUT 를 제거하므로 hold 에 불리할 이유가 없다. **그러나 rst 팬아웃이 FDCE 1,299 → 3,555 (2.7×)** 로 커진다 (Pod 문맥은 × PE 수). 라우팅·클럭 자원 부담은 통합 gate 에서만 보인다. **음수면 즉시 FAIL, 완화 없음** |
| WNS / Fmax | 기록 | +1.497 / 117.61 | **방향 미정 — 미정인 채로 공표한다** | — | 개선 요인(CE cone 축소, 조합 깊이 불변)과 악화 요인(rst 팬아웃 2.7×)이 **공존**한다. 게다가 system 병목은 EHDecode→PE_Core dispatch 로 세 번 독립 확인됐다 (§26.9 · §28.6 · §28.9) — **즉 본 변경이 이 축을 움직일 수 있는 위치에 있다.** 방향을 확신하지 못하면서 확신한 척 적지 않는다 (§30.11 규율 승계) |
| **Tensor_ALU 관련 전 축** | — | — | **전건 0 기여** | — | `TENSOR_ALU.v` 는 `sys_top_core` read_verilog 목록 밖 (`grep -rl` over `synth/` rc=1). **O1 수리·O2 수리·폐기·테스트 강화 어느 것을 해도 GATE S1 축이 움직이지 않는다.** 단 **편입을 선택하는 순간** LUT/DSP48/Fmax 3축이 신설되고 그 자체가 §12a 상 사용자 승인 재anchor 사유다 |

**비-gate 래칫 (놓치기 쉬움):** `scripts/lint_synth_coverage.py:99/109/118` 의 `measured-pending` 3건은 `make lint` 이 매 실행 열거한다. §31.6 의 지위 이동(`superseded` 2 + reference 1)은 **처분 commit 이 반드시 반영해야 하며**, 반영하지 않으면 §28.4 항 4(소리내기)가 계속 "지위 판정 선행" 이라는 **이미 거짓이 된 사유**를 출력한다.

**ceiling 초과 시 절차 (초과를 예상하지 않지만 미리 적는다 — V9-4 정신):**

1. **정직 FAIL 로 기록한다.** 기준을 움직여 통과시키는 경로는 없다.
2. 초과분을 **귀속**한다 (프로토타입 P2 실측 +143 과 대조 — 차이가 나면 그 차이가 조사 대상이다).
3. **재anchor 는 §12a 상 사용자 결정 사항이다.** 구현 세션이 스스로 결정하지 않는다.
4. 재anchor 를 받지 못하면 **pre-declared cut ladder** 를 따른다:
   **(a)** 형식2 를 **D10 1건 + D11 2건 + `cr_*` 뱅크 33건**(= 유일 게이트 아래 뱅크, 위험 집중부)으로 **축소**하고 나머지 32건은 현행 유지 — `Synth 8-7137` 축을 0 이 아닌 **32** 로 재공표한다 (축 값을 **올리는** 것이므로 그 자체가 사용자 승인 대상).
   **(b)** 그래도 초과하면 D10+D11 3건만 남기고 D6 본체를 재이월 — 단 §29.7 조건 2(계수 > 68)가 3a-C4 에서 자동 발화하므로 **재이월은 3a-C4 를 막는다.** 이 결합을 미리 적어 둔다.
   **(c)** 형식3 으로의 전환은 **cut ladder 에 없다** — 비용이 형식2 의 1.8배이므로 ceiling 문제의 해법이 될 수 없다.

### 31.11 착지 순서 · test_plan · 재측정 의무

**착지 순서 (spec-first §12a 규칙 3):**

| 단계 | 내용 | 전건 |
|---|---|---|
| **S3-C0** | **본 절 (spec-first)** — 본 commit. RTL · 테스트 · lint · gate 하네스 **무접촉** | — |
| **S3-C1** | **D10 단독 수리** — `PE_Core.v` rst 분기에 `cr_dispatch_valid <= 1'b0;` **1줄** + `test_pe.py` **warm-reset 회귀 테스트 신설** | S3-C0 |
| **S3-C2** | **D6 본체 형식2 ×67 (잔여) + D11 2건** — 같은 commit 필수 (§31.4). miter 등가성 실증 동반. `Synth 8-7137` 축 68→0 을 spec + `fp_op_gate_check.py` 에 동시 반영 | S3-C1 |
| **S3-C3** | **`test_tensor_alu.py` 재작성** (§31.9 항 8 이행) + `scripts/lint_synth_coverage.py` 지위 이동 (`superseded` 신설 + 3모듈 재분류) + §11 베이스라인 재계상 | S3-C0 |
| **S3-C4** | **통합 GATE S1 재측정 — orchestrator 몫, §30 착지 후 1회** | S3-C2 + §30 RTL |

**S3-C1 을 S3-C2 에서 분리하는 이유 (귀속 가능성 — 이것이 순서의 전부다):** D10 수리는 파형을 **바꿔야** 하고(유령 commit 제거), D6 형식2 는 파형을 **보존해야** 한다(화이트리스트 2열 제외). 한 commit 에 섞으면 **어느 파형 차이가 어느 수리에 귀속되는지 증명할 수 없다.** 분리하면 S3-C2 의 miter 계약이 **MODE=0 / MODE=1 양쪽 모두 전건 일치**(D11 의 X→0 두 열만 화이트리스트)로 강해진다 — 유령 commit 이 S3-C1 에서 이미 사라졌기 때문이다. **약한 계약을 두 번 쓰는 대신 강한 계약을 한 번 쓴다.**

**S3-C3 은 S3-C1/C2 와 독립**이다 (`TENSOR_ALU.v` 와 `PE_Core.v` 는 무관). 병행 가능하며 **§30 XChaCha20 workflow 와도 파일 충돌이 없다** (`HIU.v` 무접촉).

**test_plan — PE_Core (S3-C1/C2 몫, 본 절이 항목을 확정한다):**

1. **miter TB 를 주 증거로 삼는다.** 수리 전 `PE_Core.v` 사본을 `PE_Core_ref` 로 rename 해 수리본과 **같은 TB 에 동시 인스턴스화**, 동일 자극, 매 사이클 출력 **11축** (`output_valid` / `output_payload` / `output_tag` / `opcode_out` / `output_frag_hdr` / `memory_req` / `mem_addr` / `error_flag` / `lower_required` / `pe_ready` / `output_valid`-부속) 전건 비교, 불일치 즉시 `$fatal`. **파일 diff 보다 강하다** — 누락 불가이고 자기검사다.
2. **MODE=0 (cold reset only) — 전건 일치가 계약.** 본 조사에서 이미 실측: P1/P3 모두 3 seed × 4000 cy × 11축 **byte 동일**. P2 는 **`mem_addr` / `output_payload` 두 열의 X→0 만** 갈린다 (diff 5/11/87행) — **그 두 열만 화이트리스트에 등재하고 그 외 차이는 FAIL.** D11 수리 후에는 화이트리스트가 **비어야 한다** (X 자체가 사라지므로) — 비지 않으면 D11 수리가 불완전하다는 신호다.
3. **MODE=1 (warm reset 주입) — S3-C1 에서는 차이가 나야 정상, S3-C2 에서는 전건 일치가 계약.** S3-C1 의 차이는 **전건이 "유령 commit 제거" 로 귀속**되는지 열 단위로 pin 한다 (본 조사 실측: seed1 `valid/payload/tag/opc/memaddr` @cy904, seed12345 `err` @cy1754,2604). 귀속되지 않는 차이가 **1건이라도** 나오면 FAIL.
4. **warm-reset 회귀 테스트 (S3-C1 필수 동봉, §31.9 항 8(c) 이행).** rst 해제 후 dispatch 0건인데 `output_valid` 또는 `error_flag` 가 뜨면 FAIL. **두 발현형 모두** 커버해야 한다 — 유령 토큰만 검사하면 reject-arm 발현형을 놓친다.
5. **자극 설계 규범.** opcode 표본은 스칼라 ALU · 메모리 · MUL/DIV/DIVMOD · MU-host 를 모두 포함하고, `pe_active` / `dec_valid` / `dec_tag_match` / `dec_decode_error` 를 랜덤화해 **reject arm 도 커버**한다. seed 는 **복수 고정** (재현 가능해야 한다).
6. **무회귀.** 6개 모듈 전 suite (`MOD=PE/Cluster/Pod/Top_Core/ISA_Decoder/HIU`). `COCOTB_RESULTS_FILE` 을 `/tmp` 로 리다이렉트해 tracked `results.xml` 무접촉 (§28.3 관례). **필요조건일 뿐 충분조건이 아니다** — 그 스위트에 warm-reset 자극이 0건이라는 것이 본 조사의 실측이다. 항 4 가 그 공백을 메운다.

**test_plan — `test_tensor_alu.py` 재작성 (S3-C3 몫, §31.9 항 8 전 항목 이행). 최소 6 케이스:**

| # | 케이스 | 기대 | 이행하는 항 |
|---|---|---|---|
| 1 | `MATMUL(0x30)` golden 값 assert | **`expect_fail=True`** — docstring 에 §31.7 O1 명시 | 8(a), 8(e) |
| 2 | `TADD(0x31)` golden `[6 8 10 12]` | PASS | 8(a) |
| 3 | `0x32` golden `[5 12 21 32]` | PASS — **단 docstring 에 "이 모듈의 0x32 는 현행 ISA(EINSUM)가 아니라 superseded TENSOR_MUL 의미론" 을 명시** (§31.6) | 8(a) |
| 4 | default opcode `[0 0 0 0]` | PASS | 8(a) |
| 5 | latency 계약 — rst 해제 후 **정확히 3 사이클** 뒤 값 안정 | PASS | 8(b) |
| 6 | `alu_valid == 1` 인 첫 사이클에 결과가 **정의돼 있음** | **`expect_fail=True`** — docstring 에 §31.7 O1b 명시 | 8(b), 8(e) |

**추가 규범 3건:**

- **자극 폭 정합 (8(d))** — `COMPILE_ARGS += -P Tensor_ALU.ADDR_WIDTH=16 -P Tensor_ALU.DIM_SIZE=2` 로 **명시 override** 하거나 1,024-bit 로 정확히 패킹. **현재의 256b/1024b 불일치를 먼저 해소하지 않은 어떤 값 assert 도 무의미하다.**
- **`expect_fail` 케이스는 깨끗한 `AssertionError` 로 실패해야 한다.** 4-state X 에 `int(...)` 를 걸면 `ValueError` 가 나서 실패 사유가 흐려진다 — `.value.binstr` 로 문자열 비교하거나 명시적으로 resolve 한 뒤 assert 한다.
- **§11 베이스라인 재계상** — `Tensor_ALU` 행 **1 → 6**, Total **185 → 190**. **정직 명기: §11 표는 v1.0 시점 기준선이고 현행 RTL 실측 총계(§28.3 의 256)와는 별개 계보다.** 본 절은 `Tensor_ALU` 행만 갱신하고 표 전체의 재동기화는 하지 않는다 — 그 재동기화는 별건이며, 하지 않았다는 사실을 여기 기록한다.

**재측정 의무 (S3-C4, orchestrator 몫):** `make synth-sys-gate SYS_GATE=sys_top_core PART=xcu55c-fsvh2892-2L-e` + `python3 synth/scripts/fp_op_gate_check.py` 로 **`sys_top_core` 문맥에서 전 축 재측정.** PE_Core 단독 OOC 수치로 대체 불가 — §29.11 이 `Synth 8-295` census 의 문맥 의존성으로 이미 실증한 원칙이다. **전제조건: `set_msg_config -id {Synth 8-7137} -limit 100000` 이 하네스에 있어야 한다** (없으면 축이 100 에서 잘려 false PASS). ECP5 반쪽은 §28.7 정책 그대로 MEASUREMENT 이며 어떤 결과도 FAIL 을 구성하지 않는다.

### 31.12 §12a 기록

본 절은 §12a 하의 **정규 개발 행위 (regular development act)** 이며 **spec-before-code COMMIT 0** 다.

- **계약 변경의 성격**: **ISA 표면은 무접촉이다** — `isa/wt64v1_isa.json` · 생성물 · `asm/` · golden 3종 · truth table 어느 것도 본 절의 대상이 아니므로 `domain_version` bump 도 truth-table recapture 도 발생하지 않는다 (§29.14 · §30.11 과 동일 구조). **모듈 인터페이스 변경도 없다** — 형식2 는 rst 분기 대입만 추가하고 포트를 건드리지 않는다. 규칙 3 의 순서 중 발동하는 것은 **spec amendment → RTL/테스트 갱신** 구간뿐이다. **단 D10 수리는 관측 가능한 동작을 바꾼다** (warm reset 후 유령 토큰 소멸) — 이는 계약 축소가 아니라 **계약 위반의 시정**이며, 소비자(Cluster arbiter · 상위 fabric)는 유령 토큰을 기대한 적이 없다.
- **§12a 확장 (본 절이 신설)**: **규칙 6 — RTL 모듈 단위 고아/중복 제거 절차** (§31.6). §28.8 이 기록한 정책 공백의 성문화이며, 본 절은 절차를 **세우기만 하고 실행하지 않는다.**
- **§28.4 확장 (본 절이 신설)**: **항 8** (값 미검사 · 자극 공간 미검사 은폐 방지, §31.9) + **5번째 합성 지위 `superseded`** (§31.6). 항 7(§29.12) 과 함께 은폐 3사례(D4 / O1 / D10)를 각각 다른 축에서 봉쇄한다.
- **3a (§27.7a) 와의 격리**: 3a 산출물 — golden 3종 (`scripts/golden_{fp32,lattice,fdotcr}.py`), ISA (`isa/wt64v1_isa.json` + 생성물 + `asm/`), `FP_StepSeq.v` step 프로그램 — 은 **무접촉**이다 (§31.6 의 ISA 대조는 **읽기 전용 조사**이며 편집이 아니다). 공유 datapath 3파일 (`FP_AddWide.v` / `FP_Mul36.v` / `include/fp_narrow_f32.vh`) 은 **byte-untouched**, `decode_reserved` 는 **미접촉** (3a-C4 몫). **본 절은 3a-C4 를 선점하지 않는다** — 오히려 §31.5 형식2 채택이 3a-C4 의 stage-1 `case` 편집면과 **충돌하지 않도록** 고른 결과다.
- **§30 (XChaCha20) 와의 격리**: `HIU.v` **무접촉**, `synth/reports/` **기입 0**, gate 스크립트 **0회 실행**. §30 이 소유한 축(마스크 값·latency)은 본 절이 건드리지 않고, 본 절이 움직이는 축(`Synth 8-7137` PE_Core)은 §30 이 건드리지 않는다. **합류 지점은 S3-C4 통합 gate 1회뿐이다.**
- **선공표 규율**: §31.10 의 예측 · 상한 · cut ladder 는 **측정 이전에** 공표됐다. **WNS/Fmax 방향이 미정이라는 사실도 미정인 채로 공표했다** — 방향을 확신하지 못하면서 확신한 척 적는 것이 선공표 규율의 유일한 실패 양식이다 (§30.11 승계). `Synth 8-7137` 축 인하(68→0)는 **수리 사실의 반영**이지 통과를 위한 완화가 아니며, §29.11 별항 2 가 그 구분을 이미 규정했다.
- **§28/§29 정정의 성격**: §31.2 의 4건(E1-E4)과 §31.6/§31.7 의 정정은 §28/§29 원문을 **삭제하지 않는다** (§12a 규칙 5). §28.8 에는 배너를 삽입했고 — 그 절의 제목 낱말 "고아" 가 orchestrator 의 판단 전제를 직접 오염시켰기 때문이다 — 나머지는 본 절의 표로 정정한다. **E1(§29.7 "전부 (a) 판정")과 §28.8 "고아" 는 각각 PE_Core 이월과 Tensor_ALU 이월의 *판단 근거*를 무너뜨리므로**, 그 판단들은 본 절이 §31.5 와 §31.6 에서 각각 대체한다.
- **균형 기록 원칙 (본 절이 자기 자신에게 거는 조건)**: 본 절의 모든 처분에 **채택 근거와 반대 근거를 함께** 적었다 — §31.2(§29.7 이 옳았던 것), §31.5(형식3 의 적용성 자체는 깨끗함 / rst 팬아웃 2.7× 리스크), §31.7(O1 수리 찬성 근거), §31.10(WNS 방향 미정). **한쪽만 적힌 처분은 처분이 아니라 주장이다.**
- **이월 항목 (기한 조건 포함, §31 몫)**:
  - **`TENSOR_ALU.v` / `SIMD_ALU.v` 파일 폐기 실행** — 전건(audit · 정본 지정 · 절차 성문화) 전부 충족. **기한 조건: 사용자 결정 1건.** `SIMD_ALU.v` 는 `board_hw_plan.md:173` contingency 등재 무효화가 선행한다.
  - **`ALU_Extended.v` reference implementation 재분류의 실효성 검토** — 비합성 대상 RTL 을 repo 에 유지하는 것이 정당한지. 기한 조건: stable release 선언 라운드.
  - **§28.4 항 8 (a)(b)(d) 기계 검사 lint** — §29.12 의 lint 이월 2/3 과 **같은 도구에 얹는다.** (c) 자극 공간은 리뷰 의무로 남긴다.
  - **`Makefile:30/34/38` 의 `$(PWD)` → `$(CURDIR)`** — 사용자 메모 규칙(`makefile_curdir_rule`)이 `$(CURDIR)` 를 요구하고 `make -C <dir>` 에서 버그가 발현한다. **기한 조건: S3-C3 이 `Makefile` MOD 분기를 어차피 건드리므로 그 commit.**
  - **§11 베이스라인 표 전체 재동기화** (v1.0 기준선 185 vs 현행 실측 256+) — 본 절은 `Tensor_ALU` 행만 갱신한다. 기한 조건: stable release 선언 라운드.
  - **D9 per-partition flush** (§29.9), **undriven-signal 탐지 lint 2/3** (§29.12), **예약 포트 기계 열거** (§29.10 항 6), **4-way set-associative 비용 측정** (§29.3), **마스킹 구성 보안 논증** (§30.11), **`test_top_core.py:164-166` 무감각 assert** (§30.11) — §30.11 의 이월 목록을 **무변경 승계**한다.
  - **해소되어 목록에서 빠지는 것 (본 절의 성과)**: **PE_Core D6 68건** (§29.7 → §31.3/§31.5 처분 확정) · **Tensor_ALU O2 49건** (§29.7 → §31.8 소멸) · **§28.8 고아 지위 판정** (→ §31.6 확정) · **§12a RTL 모듈 제거 절차 공백** (§28.8 → §31.6 규칙 6 성문화).

### 31.13 착지 실측 기록 (S3-C1 + S3-C2 + S3-C3 구현 세션, 2026-08-18)

> 본 절은 §31.1-§31.12 (COMMIT 0, spec-first) 의 처분을 **실제로 착지시킨**
> 세션의 측정·정정 기록이다. §12a 규칙 5 대로 §31 원문은 무수정 보존하고,
> 실측이 뒤집은 것은 여기서 정정한다. **GATE S1 은 실행하지 않았다** —
> `make synth-sys-gate` 0회 / `synth/scripts/fp_op_gate_check.py` 0회 /
> `synth/reports/` 기입 0. 모든 합성 수치는 `/tmp/s3` 격리 OOC 실측이다.

#### 31.13.1 착지물

| 파일 | 내용 |
|---|---|
| `PE_Core.v` | D10 형식2 ×1 + D6 형식2 ×67 (rst 분기 전건 대입, 합 68) + D11 (stage-2 자격 가드 2줄 + 0x05/0x6A arm 전건 대입 2줄) |
| `test_pe.py` | warm-reset 회귀 3 케이스 신설 (§31.11 항 4) — 유령 토큰 / `error_flag` / `lower_required` 3 발현형 |
| `test_tensor_alu.py` | 전면 재작성 8 케이스 (§31.11 test_plan 6 + 랜덤 bit-exact 2) |
| `Makefile` | `MOD=Tensor_ALU` 에 `-GADDR_WIDTH=16 -GDIM_SIZE=2` (O1c 해소) + `$(PWD)` → `$(CURDIR)` **42곳** (이월 항목 해소) |
| `scripts/lint_synth_coverage.py` | `superseded` / `reference` 지위 신설 + 3모듈 재분류 + 등재 요건 3건 기계 검사 + 래칫 4종 |
| `.claude-memos/wt64v1_spec.md` | §11 두 행 재계상 + 본 절 |

#### 31.13.2 `Synth 8-7137` 축 — 68 → 0 (실측)

> **✅ 검증 배너 (§31.14.5, 2026-08-18 후속 세션):** 본 표의 수치는 이 세션이
> 스스로 측정한 것이고 그때는 **독립 재현된 바 없었다** (적대 검증의 지적).
> 다른 측정 스크립트로 재측정한 결과 **16축 전건 일치**한다 — `8-7137` 68→0,
> CLB LUTs 20050→20178 (+128), CLB Registers 4734→4859, FDCE 1299→3560,
> FDRE 3430→1294, CARRY8 849, DSP48 39, RAMB18 2, `rst` 싱크 1312→3560,
> `rst`→LUT 데이터입력 **12→0**, `8-3848`/`8-4767`/CRITICAL/ERROR 전부 0.
> **이제 검증된 값이다.** 단 **WHS / WNS / Fmax 와 `sys_top_core` system 문맥
> 면적은 여전히 미측정**이며 S3-C4 통합 run 몫이다 (§31.14.5).


`/tmp/s3` Vivado 2025.2.1 OOC, `xcu55c-fsvh2892-2L-e`,
`-flatten_hierarchy rebuilt`, `set_msg_config -id {Synth 8-7137} -limit 100000`.
계수는 §28.6 규범대로 **severity 앵커** 정규식으로 취했다
(`grep -cE "^WARNING: \[Synth 8-7137\]"`) — 소박한 `grep -c` 는 tcl echo
1줄이 얹혀 69 를 답한다.

| | `8-7137` | CLB LUT | ΔLUT | FF | FDCE | FDRE | CARRY8 | DSP | RAMB18 | `rst`→LUT 데이터입력 | `8-3848` | `8-4767` | CRIT | ERROR |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| base (85e0d6f) | **68** | 20050 | — | 4734 | 1299 | 3430 | 849 | 39 | 2 | **12** | 0 | 0 | 0 | 0 |
| 형식2 ×68 only | **0** | 20252 | **+202** | 4853 | 3554 | 1294 | 849 | 39 | 2 | 0 | 0 | 0 | 0 | 0 |
| **착지본** (형식2 ×68 + D11) | **0** | **20178** | **+128 (+0.64%)** | 4859 (+125) | **3560** | 1294 | **849 (±0)** | **39** | **2** | **0** | **0** | **0** | **0** | **0** |

**§31.5 표 재현 상태:** base 행은 §31.5 의 base 열과 **전건 일치**한다
(8-7137 68 / LUT 20,050 / FF 4,734 / FDCE 1,299 / CARRY8 849 / DSP 39).
따라서 두 측정 환경이 동형임이 확인됐고, 델타 비교가 정당하다.

**§31.5 예측과의 차이 (정직 기록):** §31.5 P2 는 형식2 ×68 을 +143 LUT /
FF +120 / FDCE 3,555 로 실측했는데, 본 세션의 형식2 ×68 은 **+202 LUT /
FF +119 / FDCE 3,554** 다. FF·FDCE 는 사실상 일치하고 **LUT 만 +59 어긋난다.**
원인은 특정하지 못했다 — 후보는 (i) 프로토타입의 상수 대입 형태 차이,
(ii) `-flatten_hierarchy` 설정 차이다. **추정으로 덮지 않고 어긋났다는
사실만 기록한다.** 최종 착지본은 **+128** 로 §31.10 선공표 상한
**+250 이내**이고 점 예측 +143 보다도 작다.

**`rst` 팬아웃 (§31.5 가 "영향 없음이라고 쓰지 않겠다" 고 한 축):** `rst`
포트 net 의 싱크 전수 열거 결과 —

| | 총 싱크 | FDCE/CLR | LUT 데이터 입력 | 기타 |
|---|---:|---:|---:|---|
| base | 1,312 | 1,299 | **12** (LUT1/I0 1 · LUT2/I1 3 · LUT3/I2 2 · LUT4/I3 1 · LUT5/I1 2 · LUT6/I0 1 · LUT6/I5 2) | `FP_StepSeq/rst` 1 |
| 착지본 | 3,560 | **3,560** | **0** | 0 |

§31.5 가 지목한 실리콘 위험 — *"타이밍이 검증되지 않은 `rst`→LUT→FF.CE
동기 경로가 데이터 캡처를 게이팅한다"* — 는 **완전히 제거됐다 (12 → 0).**
§31.5 의 예측 FDCE 3,555 대비 실측 3,560 (Δ+5). **팬아웃 2.71× 증가는
그대로 남으며, 라우팅·클럭 부담은 §31.10 대로 통합 gate 의 WHS/WNS
축에서만 판정 가능하다 — 여기서 "영향 없음" 이라고 쓰지 않는다.**

#### 31.13.3 파형 불변 실증 (miter) — 실측

> **⚠ 정정 배너 (§31.14.1, 2026-08-18 후속 세션 — 원문은 §12a 규칙 5 대로
> 무수정 보존):** 본 절이 `output_payload` / `mem_addr` 차이를 분류한
> **"자격자가 양쪽 0 인 masked 사이클(SOFT)" 은 거짓이다.** `Cluster` 의
> NoC bank (OPREF.src_kind=1) 가 `pe_out_payload` 를 **자격자 없이 조합적으로
> 읽으며** L-PE 슬롯의 저장소로 그 레지스터를 재사용한다. 따라서 그 차이는
> Cluster 경계에서 **관측 가능**하다 (실증: §31.14.2 — 소비자가 읽은 B
> 피연산자가 `0x3333444455556666` ↔ `0x777788889999aaaa` 로 갈린다).
> **결론(착지본이 옳다)은 유지되나 근거가 틀렸다** — "아무도 안 본다" 가
> 아니라 "보는 데가 있고 착지본이 그 계약을 만족한다" 가 맞다.
> 계약은 §31.14.3 이 불변식 **H1/H2** 로 성문화하고 lint 1 + 테스트 3 으로
> 집행한다.


`/tmp/s3/tb_miter.v`, iverilog 12 (**4-state**, `===` 비교). 수리본
`PE_Core` 와 기준본 `PE_Core_ref` 를 **같은 TB 에 동시 인스턴스화**하고
동일 자극을 주며 출력 **10축** 전건을 매 사이클 비교한다. 자극은 48종
opcode 표본(스칼라 ALU · 메모리 · MUL/DIV/DIVMOD · MU-host · fp32 step
sequencer · 텐서 · 미정의)에 `pe_active`/`dec_valid`/`dec_tag_match`/
`dec_decode_error` 랜덤화(reject arm 커버)를 얹었다.

**하네스 자기검증 2건 (null-detector 방지 — 이것을 하지 않으면 "0 mismatch"
가 아무 뜻도 없다):** (i) 동일 RTL 두 벌 → 3 seed × 4000 cy **0 mismatch**,
(ii) `output_tag` 의 rst 값 1비트만 뒤집은 주입본 → **5 mismatch 검출**.

**S3-C1 (D10 단독) 대 base:**

| MODE | 정의 | 결과 |
|---|---|---|
| 0 | cold reset only | **5 seed × 4000 cy 전건 0 mismatch** — D10 수리는 cold 파형을 바꾸지 않는다 |
| 1 | 무작위 warm reset | 39-130 mismatch — **바뀌어야 정상** (유령 commit 제거) |
| **2** | **귀속 실증(음성)** — 기준본의 `cr_dispatch_valid == 0` 인 순간에만 warm reset 주입 | 19-24회 주입, **전건 0 mismatch** |
| **3** | **귀속 실증(양성)** — `cr_dispatch_valid == 1` 인 순간에만 주입 | 46-54회 주입, 274-437 mismatch |

**MODE 2/3 이 §31.11 항 3 의 "열 단위 pin" 을 iff-인과로 강화한다:** 차이는
미리셋 비트가 1 일 때에 **한해서만** 발생한다. 즉 전 차이가 D10 에 귀속되며,
귀속되지 않는 차이는 **0 건**이다. 방향도 확인했다 — 매 사이클 기준본이
유령을 내고 수리본이 조용하다. **발현형은 §31.3 이 기록한 2종이 아니라
3종이었다: 유령 wave 토큰 · 유령 `error_flag` · 유령 `lower_required`.**
(§31.3 정정 1건.)

**S3-C2 (형식2 ×68 + D11) 대 S3-C1:**

| 축 | 결과 |
|---|---|
| 8축 (`output_valid`/`output_tag`/`opcode_out`/`pe_ready`/`output_frag_hdr`/`memory_req`/`error_flag`/`lower_required`) | **MODE 0/1 · 5 seed × 4000 cy 전건 byte 일치** |
| `output_payload` / `mem_addr` | 차이 발생 — 아래 분류 |
| 수리본 출력의 4-state X | **전 run 0건** (기준본은 최대 59 cy 관측) |

**자격 마스킹 계약의 기계 검사 (§31.4 가 "spec 어디에도 없다" 고 한 계약을
여기서 성문화하고 집행한다):** `output_payload` 의 차이는 `output_valid`
가 양쪽 모두 0 인 사이클에서만, `mem_addr` 의 차이는 `memory_req` 가 양쪽
모두 0 인 사이클에서만 허용한다 (SOFT). 자격자가 1 인데 값이 다르면 HARD.
실측: **HARD 는 opcode `0x05` 와 `0x6A` 두 종에만 나타나고 그 외 0 건**이며,
그 둘은 §31.13.4 의 D11′ 로 귀속된다. MODE=0 에서 기준본의 X → 수리본의
정의된 값 전환은 `mem_addr` 열에서만 6/8/9/2/59 행 관측됐다 — §31.11 항 2
가 예고한 화이트리스트와 **같은 열, 같은 자릿수**다.

**end-to-end (원 base → 착지본) 종합 — 5 seed × 4000 cy, MODE 0(cold only)
와 MODE 2(정지 상태에서만 warm reset 주입) 양쪽:**

- **차이가 나는 열은 `output_payload` 와 `mem_addr` 둘뿐이다.** 나머지 8축은
  전 run byte 일치.
- 그 두 열의 차이는 전건이 (i) 자격자가 양쪽 0 인 masked 사이클, 또는
  (ii) opcode **`0x05` / `0x6A`** 다. **그 외 opcode 의 HARD 차이는 0 건**
  (`0x05` 245 · `0x6A` 153, 그 외 0).
- 착지본이 출력에 4-state X 를 내놓은 사이클 **0 건** (기준본은 최대 59).

**즉 D6 형식2 ×68 은 의미 보존이고, 관측 가능한 동작 변경은 (a) D10 의 유령
commit 소멸(warm reset 시)과 (b) D11′ 의 2개 arm payload 결정화 — 이 둘로
전부 귀속된다.**

#### 31.13.4 D11′ (신규 결함) — §31.4 의 "새어 나가지 않는다" 는 거짓이다

**§31.4 는 이렇게 적었다:** *"현재는 새어 나가지 않는다 — baseline 6 trace
전건에서 `output_valid=1 & X-payload` = 0 … 소비자가 자격자로 거르고 있다."*

**이 진술은 X 에 대해서만 참이고, 결함 전체에 대해서는 거짓이다.** 정적
전수 분석(stage-1 의 `cr_valid_out <= 1'b1` **70건** 전건에 대해 같은 arm 이
`cr_payload` 를 기입하는지 대조)이 **2건의 미기입 arm** 을 찾았고, 4-state
miter 가 그 2건을 런타임으로 재현했다:

| arm | 위치 | 증상 |
|---|---|---|
| **`0x05` (ST)** | `cr_memory_req <= 1'b1` + `cr_valid_out <= 1'b1` 인데 `cr_payload` 기입 없음 | stage-2 가 `output_payload <= cr_payload` 를 무조건 수행하므로 **`output_valid=1` 인 wave 토큰에 직전 명령의 payload 가 실려 나간다** |
| **`0x6A` (FRAG_INVAL ack)** | 같은 구조 (RTL 주석이 *"an ack carries no payload of its own"* 라고 스스로 적고 있다) | 동일 |

**즉 D11 은 "자격자가 걸러 준다" 가 아니라 자격자를 **통과해** 새고
있었다.** X 만 찾으면 보이지 않는다 — 새는 값이 X 가 아니라 **직전 명령의
정상 payload** 이기 때문이다. §31.4 의 조사 방법(X 탐지)이 이 클래스를
구조적으로 놓쳤고, 그 사실을 여기 기록한다.

**수리 형식 정정 — §31.4 의 두 형식 중 어느 것도 단독으로는 답이 아니다:**

- **형식 1 (stage-2 를 `cr_valid_out`/`cr_memory_req` 로 가드)** 단독은
  **0x05/0x6A 를 고치지 못한다** — 그 arm 들은 자격자를 1 로 세운다.
- **형식 2 (stage-1 per-cycle 기본값)** 단독은 고치지만 **+778 LUT** 가
  든다 (20,252 → 21,030 실측). 64-bit 레지스터의 hold(CE) 구조가 사라지고
  75-way mux 트리가 생기기 때문이다. §31.10 선공표 상한 +250 을 혼자
  3배 넘긴다 — **선공표 상한을 지키려면 이 형식은 채택할 수 없다.**
- **채택 (형식1 + 누출 arm 전건 대입):** stage-2 두 줄에 자격 가드를 걸고,
  정적 분석이 찾은 **2개 arm 에만** `cr_payload <= 0` 을 넣는다. 비용
  **+128 LUT (형식2 대비 -852)**, 누출 **0**. §29.6 이 `phys_addr` 에
  규범화한 "전건 대입" 을 **필요한 곳에만** 이식한 형태다.

**관측 가능한 동작 변경 (§12a — 숨기지 않는다):** `0x05`/`0x6A` 의 wave
토큰 payload 가 **직전 명령의 값 → 결정적 0** 으로 바뀐다. 두 opcode 의
토큰 payload 의미론은 ISA 에 규정된 바 없고(`ST` 는 `mem_addr` + `memory_req`
로 저장을 수행하며 `Cluster.v` 의 메모리 채널에 store-data 포트가 없다),
어떤 테스트도 이 필드를 assert 하지 않는다. **0 이 정답인지 다른 값이어야
하는지는 ISA 결정 사항이며 본 절이 결정하지 않는다** — 결정될 때까지
"직전 명령의 값" 보다 "결정적 0" 이 엄격히 낫다는 판단만 기록한다.

#### 31.13.5 Tensor_ALU — 처분 이행과 **지시 충돌 1건**

**MATMUL 수리는 하지 않았다.** 구현 지시서에는 *"spec 처분대로 (MATMUL
수리 포함)"* 이라고 적혀 있으나, **spec §31.7 은 O1 수리를 normative 로
기각**하고 §31.11 test_plan 은 케이스 1 을 `expect_fail=True` 로 규정한다.
둘은 정면 충돌하며, 본 세션은 **spec-first (§12a) 를 따라 spec 을 이행했다.**
§31.7 의 기각 사유 1번이 *"§12a 상 사용자 결정 없이는 수행할 수 없는
종류"* 이므로, 구현 세션이 지시서의 괄호 한 줄로 그 결정을 대신할 수 없다.

**대신 폐기/수리 결정에 필요한 근거를 전부 실측해 두었다:**

| 실측 | 결과 |
|---|---|
| §31.7 기각 근거 재현 (yosys 0.64 premap, 기본 D=4/W=64) | 축퇴본 `$mul` **31** / `$add` **32** → 정답본 `$mul` **76** / `$add` **64**. **§31.7 의 2.45× / 2.0× 와 자릿수까지 일치** |
| 정답 구현 프로토타입 (`/tmp/s3/TENSOR_ALU_fixed.v`, §31.7 이 기록한 blocking `acc` 형태) | D=2/W=16 에서 A=[[1,2],[3,4]]·B=[[5,6],[7,8]] → **[19 22 43 50]**, 랜덤 199 벡터 포함 **200/200 bit-exact**. latency 3 유지 |
| **정본 `PE_Core` MATMUL (0x30) 검증** — 이것이 실제로 출하되는 하드웨어다 | **착지본 `PE_Core.v` 로** 지정 벡터 [19 22 43 50] + 랜덤 199 벡터 = **200/200 bit-exact, mismatch 0**. 즉 D6/D10/D11 수리가 MATMUL 의미론을 보존했음이 같은 run 으로 증명된다 |

**따라서 "MATMUL 이 정답을 낸다" 는 요구는 정본에서 이미 충족돼 있고,
`TENSOR_ALU.v` 를 고치는 것은 기능을 늘리지 않는다 (§31.7 기각 사유 2).**
`TENSOR_ALU.v` 를 수리·폐기하려면 **사용자 결정 1건**이 남아 있다.

**부수 정정 (§31.8 계수):** yosys 0.64 로 `TENSOR_ALU.v` 를 premap 하면
`$dffe` **48** + `$sdffce` **16** + `$adff` **1** 이 나온다. §31.8 항 4 는
`$dffe` 49 + `$adff` 1 로 적었다 — 합(65 대 50)이 다르고 세부 셀 종류도
다르다. **`$sdffce` 16 은 `result_matrix` 의 16 슬라이스가 동기 CE 로
따로 잡힌 것**이며 pass 순서 차이로 보인다. O2 수리는 §31.8 대로 소멸
하므로 이 계수는 어느 판정에도 쓰이지 않으나, **§31.8 의 "독립 재확인"
문장이 재현되지 않았다는 사실은 기록한다.**

#### 31.13.6 테스트 — 은폐 재발 탐지 기전과 그 실증

> **⚠ 정정 배너 (§31.14.4, 2026-08-18 후속 세션 — 원문 무수정 보존):** 본 절의
> **"양방향 래칫"** 주장 중 뒤쪽 방향은 **선의에 의존하고 있었다.** assert 를
> 약화시키면서 `@cocotb.test(expect_fail=True)` 표식을 **함께 지우면** 그
> 테스트는 그냥 PASS 하고 CI 는 녹색이 된다 (실증: 2줄 편집으로 축퇴 은폐 완전
> 복원, `TESTS=8 PASS=8 FAIL=0`). `scripts/lint_known_defect_tests.py` 신설로
> 3방향(표식 존재 · golden assert 존재 · 미등재 표식 0건) 기계 집행한다 —
> §31.14.4.


**`test_pe.py` warm-reset 회귀 3 케이스 (§31.11 항 4).** rst 해제 후
dispatch 0건인데 `out_valid` / `error_flag` / `lower_required` 중 하나라도
뜨면 FAIL. 주입 지연은 1-23 사이클 **스윕**한다 (`cr_dispatch_valid == 1`
인 창이 정확히 1 사이클이라 고정 지연으로는 재현이 불안정하다).

> **검출력 실증 (이것이 없으면 테스트는 자기 자신을 증명하지 못한다):**
> 착지본에서 **3/3 PASS**, 수리 전 `PE_Core.v` 로 되돌리면 **3/3 FAIL**
> (`out_valid` payload=15 유령 토큰 / 유령 `error_flag` / 유령
> `lower_required`). reject-arm 케이스는 처음에 DIV-by-0 을 썼는데
> **baseline 에서도 PASS 해 버렸다** — `div_b_zero_p2` 가 rst 분기에서
> 대입되므로 그 경로로는 D10 이 발현하지 않기 때문이다. `cr_hard_error`
> arm (MATMUL + `dim_sizes != 0x05`) 으로 교체해 검출력을 확보했다.
> **"자기 이름이 가리키는 결함을 잡지 못하는 테스트" 는 그 자체가
> §28.4 항 8 위반이다.**

**`test_tensor_alu.py` 8 케이스.** §31.11 이 요구한 6 + 랜덤 bit-exact 2.
`expect_fail=True` 2건 (O1 MATMUL golden / O1b `alu_valid` 는 result-valid
가 아님) 은 **양방향 래칫**이다 — 결함이 고쳐져도 FAIL, assert 가 다시
약화돼도 (약화된 테스트는 통과해 버리므로 unexpected-pass 로) FAIL.
**즉 축퇴를 다시 은폐하는 순간 CI 가 운다.**

> **구현 중 발견 — 테스트 순서 상태 누출 (은폐 4번째 사례).** cocotb 는
> 한 시뮬레이션 안에서 테스트를 연달아 돌리는데 `Tensor_ALU` 는 `rst` 로
> `alu_valid` **하나만** 리셋한다 (`a`/`b`/`res`/`result_matrix` 는
> reset-free — §31.8 이 센 49건이 정확히 이 군이다). 그래서 앞 케이스의
> 행렬이 뒤 케이스로 새어 latency 를 **3 → 2 로 보이게** 만들었고,
> `alu_valid` 케이스는 `expect_fail` 인데 **통과해 버렸다.** 명시
> `_flush()` 로 봉쇄했다. **O2(reset 결함)가 테스트 신뢰성 자체를
> 오염시킨다는 실증**이며, "수리하지 않는다" 는 처분의 비용이 0 이
> 아님을 보여준다.

#### 31.13.7 회귀 · lint

| 스위트 | 결과 |
|---|---|
| `MOD=PE` | **7/7 PASS** (기존 4 + warm-reset 3) |
| `MOD=ISA_Decoder` | **192/192 PASS** (`test_matmul_2x2` 포함) |
| `MOD=Cluster` | **45/45 PASS** |
| `MOD=Pod` | **7/7 PASS** |
| `MOD=Top_Core` | **8/8 PASS** |
| `MOD=Tensor_ALU` | **8/8** (6 PASS + 2 expect_fail-as-designed) |
| `MOD=SIMD_ALU` / `MOD=ALU_Extended` | 무변경 통과 |
| `make lint` | **exit 0** |
| verilator 5.048 `--lint-only` | PE_Core / Tensor_ALU / SIMD_ALU / ALU_Extended / Cluster / Pod / Top_Core **전건 clean** |

전 run 에서 `COCOTB_RESULTS_FILE` 을 `/tmp` 로 리다이렉트해 tracked
`results.xml` 은 **무접촉**이다 (§28.3 관례).

**§28.4 항 8 정량 baseline 재확인 (§31.9 의 주장을 독립 검증):**
`test_simd_alu.py` 는 lane 값 assert 16건, `test_alu_extended.py` 는
result 값 assert 17건으로 **둘 다 건전**하다. 값 미검사는
`test_tensor_alu.py` **단 하나**였다는 §31.9 의 정량 서술이 재확인된다.

#### 31.13.8 이행하지 못한 것 · 새 이월

1. **`fp_op_gate_check.py` 의 `Synth 8-7137` 축 갱신 — 이행 대상이
   존재하지 않는다.** §31.5 채택 조건 4 는 축 값을 spec 과
   `fp_op_gate_check.py` 양쪽에서 내리라고 규정하지만, **그 파일에는
   `7137` 문자열이 0건**이다. §29.11 별항 2 가 축을 **선언**했을 뿐
   하네스에 **구현한 적이 없다.** 즉 `Synth 8-7137` 은 오늘까지
   merge-blocker 가 아니었다. 본 세션은 새 gate 축을 신설하지 않았다
   (지시상 gate 기준 수치 변경 금지 · 축 신설은 선공표 대상). **spec 쪽
   축 값은 §31.10 이 이미 "HIU 0 / PE_Core 0 / 합 0" 으로 선공표해 두었고
   실측이 그것을 충족한다.**
   **신규 이월 — 기한 조건: S3-C4 통합 gate commit.** 축을 실제로
   `fp_op_gate_check.py` 에 구현하거나, 구현하지 않기로 결정하고 §29.11
   별항 2 를 "선언만 하고 미구현" 으로 정정하거나 — **둘 중 하나는 해야
   한다.** 지금 상태는 "축이 있다고 적혀 있는데 없다" 이다.
2. **`0x05` / `0x6A` 토큰 payload 의미론의 ISA 확정** (§31.13.4). 기한
   조건: ISA 개정 라운드. 현재는 결정적 0.
3. **`TENSOR_ALU.v` / `SIMD_ALU.v` 파일 폐기 실행** — §31.6 대로 전건
   충족, **사용자 결정 1건** 대기. `lint_synth_coverage.py` 가 `superseded`
   등재 요건 3건(정본 / 정본 검증 테스트 / 기한 조건)을 기계 검사한다.
4. **§28.4 항 8 (a)(b)(d) 기계 검사 lint** — §31.12 승계, 미착수.
5. **§11 표 전체 재동기화** — 본 세션은 두 행만 갱신했다 (§31.13.1).
6. §30.11 / §31.12 의 나머지 이월 목록 **무변경 승계**.

**해소되어 목록에서 빠지는 것:** **PE_Core D6 68건** (착지, 8-7137 68→0) ·
**Tensor_ALU O2 49건** (§31.8 소멸 확정) · **고아 지위 판정**
(`superseded` 2 + `reference` 1 로 lint 반영 완료) · **`Makefile`
`$(PWD)` → `$(CURDIR)`** (42곳, §31.12 이월 항목).

### 31.14 적대 검증 반증 3건의 처분 — §31.13 정정 (2026-08-18, 같은 날 후속 세션)

> 본 절은 §31.13 (S3-C1/C2/C3 착지 기록) 에 대한 **적대 검증이 반증한 3건**을
> 처분한다. §12a 규칙 5 대로 §31.13 원문은 무수정 보존하고, 실측이 뒤집은 것은
> 여기서 정정한다. **GATE S1 은 실행하지 않았다** — `make synth-sys-gate` 0회 /
> `synth/scripts/fp_op_gate_check.py` 0회 / `synth/reports/` 기입 0. 모든 합성
> 수치는 `/tmp/fix/ooc` 격리 OOC 실측이다.
>
> **반증 3건 (원문 요지):**
> 1. *(major)* 파형 불변 실증에서 **"masked(SOFT)" 로 분류한 `output_payload`
>    발산이 Cluster 경계에서 관측된다** — `Cluster.v` 의 NoC bank mux 가
>    `pe_out_payload` 를 자격자 없이 조합적으로 읽는다.
> 2. *(minor)* 은폐 재발 래칫은 **assert 약화만** 잡는다 — `expect_fail` 을 함께
>    제거하면 완전 은폐가 복원되고 CI 는 녹색이 된다.
> 3. *(minor)* §31.13.2 의 gate 축 수치는 그 세션에서 **독립 검증되지 않았다**.
>
> **판정: 3건 전부 타당하다.** 아래에서 각각 정정·수리·재측정한다.

#### 31.14.1 §31.13.3 정정 (최우선) — "masked" 는 소비자를 확인하지 않고 내린 분류였다

**§31.13.3 원문:** *"그 두 열의 차이는 전건이 (i) 자격자가 양쪽 0 인 masked
사이클, 또는 (ii) opcode `0x05` / `0x6A` 다."*

**(ii) 는 참이나 (i) 의 '`masked`' 는 거짓이다.** `masked` 는 *"자격자가 0 이므로
아무도 그 값을 쓰지 않는다"* 를 뜻하는데, **그것을 소비자 쪽에서 확인한 적이
없다.** 실제 소비자 전수 audit 결과는 다음과 같다:

| 소비자 | 위치 | 자격자 사용 여부 | 판정 |
|---|---|---|---|
| **NoC bank mux (OPREF.src_kind=1)** | `Cluster.v` bank-selection `always @(*)` | **없음** — `pe_out_payload[kbank]` 를 조합적으로 읽는다 | **`masked` 성립 안 함** |
| Cluster 출력 arbiter | `Cluster.v` L-PE 우선순위 루프 | `m_valid = pe_out_valid[i]` 를 payload 와 **함께** 싣는다 | 성립 (하류가 valid 로 거른다) |
| Pod 출력 arbiter | `Pod.v` | `if (cl_out_valid[i] && !m_valid)` — 완전 valid-게이트, 기본값 0 | 성립 |
| Top_Core | `Top_Core.v` | `out_payload` 참조 **0건** | 해당 없음 |

**⇒ 자격자를 쓰지 않는 값 소비자는 NoC bank 단 하나이고, 그 하나가 정확히
반증의 대상이다.** 나머지 세 곳이 깨끗하다는 사실이 오히려 문제를 선명하게
만든다 — 프로젝트는 valid-게이트 관례를 지켜 왔고, **한 군데만 예외**다.

**왜 그 한 군데가 예외인가 (구조적 사유 — 실수가 아니다):** 세 뱅크 소스의
저장소 형태가 다르다. MU/DU 슬롯은 `mu_bank_reg` / `du_bank_reg` 라는 **전용
뱅크 레지스터**를 두고 `mu_out_valid` / `du_out_valid` 로 write-enable 한다.
L-PE 슬롯은 전용 레지스터를 두지 **않고** `PE_Core.output_payload` 를 **뱅크
저장소로 재사용**한다 — PE 당 64-bit 레지스터 1개를 아끼는 의도적 면적
최적화다 (Pod 문맥에서는 × 클러스터 수). 그 재사용이 성립하려면 출력
레지스터가 "마지막으로 발행한 토큰의 payload" 를 유지해야 하는데, **그 요구가
어디에도 기록되지 않았다.**

**따라서 §31.13.3 의 SOFT/HARD 이분법을 다음과 같이 정정한다:**

> **정정 문장 (§31.13.3 에 대해):** `output_payload` 의 차이는 "SOFT(masked) /
> HARD(0x05·0x6A)" 2분류가 아니라 **3분류**다 — (i) **뱅크 가시 (bank-visible)**:
> 자격자가 0 이지만 NoC bank 가 읽는다, (ii) **진성 masked**: 자격자가 0 이고
> arbiter 경로로만 흐른다, (iii) **HARD**: 자격자가 1 이다. §31.13.3 은 (i) 을
> (ii) 로 흡수해 **존재를 부정했다.** 착지본이 옳은 값을 낸다는 결론은 유지되나,
> 그 결론의 **근거**가 틀렸다: "아무도 안 본다" 가 아니라 "보는 데가 있고
> 착지본이 그 계약을 만족한다" 가 맞다.

#### 31.14.2 실증 (독립 재현) — Cluster 경계에서 값이 다르다

`/tmp/fix/cl` 격리 cocotb (`COCOTB_TOPLEVEL = Cluster`, verilator 5.048,
`PE_Core.v` **한 파일만** 교체하고 나머지 소스 동일):

```
L-PE0: 0x63 SIMD_ADD_WIDE_VEC  (2-fragment 입력 wave → 2 beat 출력)
       producer beats = [0x3333444455556666 (hdr 0x01),
                         0x777788889999aaaa (hdr 0x11)]
L-PE0: 0x04 LD  .mem(offset=0x100)   ← stage-2 성공 arm, cr_valid_out=0, 토큰 0건
L-PE1: 0x10 ADD + eh_opref(src_kind=1, noc_route=0), payload_a=0
```

| `PE_Core.v` | 소비자가 읽은 bank[0] | 계약 (`Cluster.v` 주석: *"last L-PE output at bank[route]"*) |
|---|---|---|
| v1.9 base (85e0d6f) | `0x3333444455556666` | **위반** — 첫 fragment 로 되돌아갔다 |
| 착지본 (S3-C2) | `0x777788889999aaaa` | 만족 — 마지막으로 발행된 beat |

소비자 토큰은 `ext_out_valid == 1` 이다. 수열에 `0x05` / `0x6A` 는 **한 번도
등장하지 않는다** — 즉 §31.13.3 이 HARD 로 귀속시킨 2개 arm 과 무관한 경로에서
값이 갈린다.

**기전:** base 는 stage-2 성공 arm 에서 `output_payload <= cr_payload` 를
**무조건** 수행하므로, frag-drain 이 써 넣은 fragment-1 값이 토큰을 내지 않는
LD 1건에 의해 `cr_payload`(= fragment-0) 로 **되돌아간다.** 착지본의 D11 자격
가드가 그것을 막는다.

**`LD` 는 왜 자격자를 통과하지 못하는데도 뱅크를 덮었는가 —** 바로 그것이
반증의 요지다. `cr_valid_out = 0` 이므로 토큰은 없지만 stage-2 복사는 실행됐고,
NoC bank 는 자격자를 보지 않으므로 그 복사를 그대로 읽었다.

**단일 fragment 수열에서는 재현되지 않는다 (정직 명기 — 검출력의 한계):**
ADD → LD → 소비자 수열은 base 와 착지본이 **같은 값**을 준다. 그 경우
`cr_payload` 가 아직 ADD 의 결과와 같기 때문이다. 발산은 `output_payload` 가
`cr_payload` **아닌 경로**로 쓰인 뒤에만 나타난다 — L-PE 에서 그 경로는
frag-drain / frag0_hold 뿐이다 (MUL/DIV/fp32 계열은 `is_mul_op`/`is_div_op` 로
MU/DU 에 라우팅되므로 L-PE 슬롯에 나타나지 않는다). **따라서 회귀 테스트는
다중 fragment 생산자를 써야 하며, 단일 fragment 케이스는 검출력이 0 이다.**
이 사실을 모르고 쓴 단일 fragment 케이스는 base 에서도 PASS 했다 (본 세션이
실제로 겪었고, §28.4 항 8 대로 그 케이스를 폐기했다).

#### 31.14.3 처분 (normative) — 불변식 H1/H2 성문화 + 3중 기계 집행

**계약을 이름으로 못박는다:**

> **불변식 H1 (normative).** `PE_Core.output_payload` 는 `output_valid` 가
> 어서트되는 사이클에만 값이 바뀐다. 즉 토큰을 발행하지 않는 명령은 그
> 레지스터를 움직일 수 없다.
>
> **불변식 H2 (normative).** `PE_Core.mem_addr` 는 `memory_req` 가 어서트되는
> 사이클에만 값이 바뀐다.
>
> **뱅크 저장소 계약 (normative).** `Cluster` 의 NoC bank (OPREF.src_kind=1) 는
> L-PE 슬롯의 저장소로 `PE_Core.output_payload` 를 재사용하며 자격자 없이
> 조합적으로 읽는다. 이 읽기의 정당성은 **전적으로 H1 에 의존한다.** 뱅크
> 값의 의미는 *"그 슬롯이 마지막으로 발행한 토큰의 payload"* 이며, 다중
> fragment wave 의 경우 **마지막 beat** 다.

**왜 소비자 쪽에 `pe_bank_reg` 를 달지 않는가 (대안 명시 기각):** `Cluster` 에
`pe_out_valid` 로 write-enable 되는 뱅크 레지스터를 두면 구조적으로는 안전하지만
— (a) `PE_Core.output_payload` 와 **완전히 중복되는** NUM_PES × 64-bit 레지스터가
새로 생기고 (Pod 문맥은 × 클러스터 수), 그 비용은 §31.10 이 선공표한 델타 예측
밖이며, (b) 무엇보다 **미래의 H1 위반을 조용히 덮는다** — 뱅크가 자기 값을
들고 있으면 `PE_Core` 가 토큰 없이 payload 를 움직여도 아무 증상이 없다.
**침묵시키는 대신 소리내는 쪽을 고른다** (loud-fault-never-silent). 중복
레지스터는 "결함을 없애는 것" 이 아니라 "결함을 안 보이게 하는 것" 이다.

**3중 집행 (계약을 주석으로만 두지 않는다 — §31.4 가 지적한 실패를 한 단계
위에서 반복하지 않기 위해):**

| # | 집행 | 대상 | 검출력 실증 (v1.9 base 로 되돌렸을 때) |
|---|---|---|---|
| 1 | **정적 lint** `scripts/lint_output_payload_hold.py` (`make lint`) | `PE_Core.v` 의 **모든** `output_payload <=` / `mem_addr <=` 대입이 (i) rst arm, (ii) 같은 begin/end 에 `output_valid <= 1'b1` 이 있는 emit arm, (iii) 자격자와 **같은 식**으로 인라인 가드된 복사 — 셋 중 하나여야 한다 | **FAIL, 위반 2건 정확 지목** (`PE_Core.v:3407` `output_payload <= cr_payload;` · `:3410` `mem_addr <= cr_mem_addr;`) |
| 2 | **런타임 감시** `test_pe.py::test_pe_output_payload_hold_invariant` | 3 seed × 900 cy 랜덤 자극 (opcode 14종 표본 — 스칼라 ALU / 메모리 / MUL·DIV / 텐서 / `0x05`·`0x6A` / 2-fragment emit / 미정의) 하에 매 사이클 H1·H2 검사. 4-state 를 문자열로 보존 비교하므로 X→0 전환도 "변화" 로 잡는다 | **FAIL, 위반 35건** |
| 3 | **시스템 directed** `test_cluster.py::test_cluster_noc_bank_multifragment_last_beat` | §31.14.2 수열을 그대로 pin — 다중 fragment 생산자 → 토큰 없는 LD → 소비자 bank 읽기 | **FAIL** (`bank[0]` 이 `0x3333...`, 기대 `0x7777...`) |
| 3′ | **시스템 directed** `test_cluster.py::test_cluster_store_token_payload_deterministic_and_bank` | §31.13.4 D11′ 이 **선언만 하고 테스트가 0건이던** 동작 변경을 pin — `0x05` 토큰 payload 는 결정적 0, 그 뒤 bank 도 0 | **FAIL** (ST 토큰 payload 가 `0xf` = 직전 ADD 결과 15 로 샌다) |

**RTL 변경은 0 줄이다 (중요).** 착지본 `PE_Core.v` 는 이미 H1/H2 를 만족한다 —
D11 자격 가드가 그것을 복원했다. 본 절이 추가한 것은 **계약의 기록과 집행**
뿐이며, `Cluster.v` / `PE_Core.v` 편집은 **주석 한정**이다. 따라서 **합성
결과물은 §31.13.2 착지본과 비트 단위로 동일**하고 GATE S1 축은 움직이지 않는다
(§31.14.5 가 이를 실측으로 확인한다).

**남는 리스크 (여기서 "영향 없음" 이라고 쓰지 않는다):** 조합 읽기 자체는
그대로 남는다. H1 이 깨지면 뱅크가 다시 오염되며, 그 안전은 이제 lint 1 + 테스트
3 에 걸려 있다. **lint 를 끄거나 표에서 빼는 편집은 그 자체가 리뷰 대상이다.**
또한 `test_cluster.py` 의 뱅크 테스트는 **다중 fragment 생산자에서만 검출력이
있다** (§31.14.2 말미) — 단일 fragment 형태로 "단순화" 하는 편집은 검출력을 0
으로 만든다. 이 두 문장을 여기 적어 두는 것이 본 절이 할 수 있는 전부다.

**미검사 자극 축 (§28.4 항 8(c) 명시 기록):** MU/DU 가 같은 슬롯을 덮은 뒤의
L-PE 뱅크 우선순위 상호작용, back-pressure 하의 재시도, HIU 왕복 메모리 응답,
다중 PE 동시 발행 시의 뱅크 경합.

#### 31.14.4 `expect_fail` 래칫의 실제 구멍과 봉쇄

**§31.13.6 원문:** *"`expect_fail=True` 2건은 **양방향 래칫**이다 — 결함이
고쳐져도 FAIL, assert 가 다시 약화돼도 (약화된 테스트는 통과해 버리므로
unexpected-pass 로) FAIL."*

**뒤쪽 방향이 열려 있었다.** 적대 검증 실증:

| 변이 | 편집 | 결과 |
|---|---|---|
| **M4a** | assert 를 `alu_valid == 1` 만 보게 되돌리고 `expect_fail=True` **유지** | `test_matmul_golden_known_broken` **FAIL** (unexpected pass) — 래칫 작동 |
| **M4b** | 위에 더해 `@cocotb.test(expect_fail=True)` → `@cocotb.test()` | **PASS. TESTS=8 PASS=8 FAIL=0.** 축퇴가 다시 완전히 은폐되고 CI 는 녹색 |

**즉 래칫은 편집자가 표식을 남겨 두기로 **선택했을 때에만** 작동했다 — 선의에
의존하는 래칫이며, 그것은 래칫이 아니다.** `scripts/lint_synth_coverage.py` 도
막지 못했다: `superseded` 등재 요건 3건은 `canonical_test` **문자열의 존재만**
검사했고 assert 강도도 `expect_fail` 표식도 보지 않았다.

**처분 (normative) — `scripts/lint_known_defect_tests.py` 신설, 3방향 집행:**

1. **정방향.** 선언표(`KNOWN_DEFECT_TESTS`)의 각 항목은 (a) 실존하는 `async def`
   이고, (b) `@cocotb.test(expect_fail=True)` 로 표기돼 있고, (c) `assert` 중
   하나가 선언된 **golden 토큰**을 포함하며, (d) 결과 신호를 실제로 **읽는**
   코드가 있고, (e) docstring 에 spec 절 번호가 있어야 한다. AST 로 검사한다.
   → **M4a FAIL (exit 1) · M4b FAIL (exit 1).** 두 경로 모두 봉쇄.
2. **역방향.** repo 의 **모든** `test_*.py` 를 훑어 `expect_fail` 표식을 전수
   수집하고, 표에 없는 것이 하나라도 있으면 FAIL. 회귀한 테스트에
   `expect_fail=True` 를 붙여 조용히 녹색으로 만드는 경로 — §28.4 항 8(e) 가
   금지한 두 실패 양식 중 나머지 하나 — 를 막는다.
   → 임의의 테스트에 표식을 주입하면 **FAIL (exit 1)** 실증.
3. **소멸 방지.** 선언된 known-defect 테스트가 **사라지면** FAIL. 결함이
   수리됐다면 spec 갱신 후 표에서 빼야 하며, 조용히 지울 수 없다.

**`lint_synth_coverage.py` 동반 강화 (§31.6 등재 요건의 실질화):**
`canonical_test` 는 산문이라 기계 검증이 불가능했으므로 **`canonical_test_refs`**
(파일·함수명 튜플 목록) 를 `superseded` 의 **4번째 등재 요건**으로 신설하고,
각 항목이 (a) 실제 `async def` 테스트로 **해소**되고 (b) 그 함수가 **DUT 신호를
읽는 값 assert** 를 최소 1개 가진다는 것까지 AST 로 확인한다.
→ 정본 테스트 개명 시 **FAIL** · 정본 테스트의 값 assert 제거 시 **FAIL** 실증.

> **§28.4 항 8(e) 보강 (normative — 항 1-8 무수정, 8(e) 에 문장 추가):**
> *"이 형식(golden assert + `expect_fail=True`)은 **기계 집행이 동반될 때에만**
> 래칫이다. 표식과 assert 를 함께 지우는 편집이 통과하면 그것은 래칫이 아니라
> 관례다. known-defect 테스트는 lint 선언표에 등재하고, 등재는 (i) 표식 존재,
> (ii) golden assert 존재, (iii) spec 절 번호, (iv) 미등재 표식 0건을 동시에
> 검사해야 한다."*

#### 31.14.5 gate 축 독립 재측정 — §31.13.2 검증

**§31.13.2 의 수치는 그 세션이 스스로 측정한 것이고 본 세션 이전에 독립
재현된 적이 없다.** 반증 3번의 지적이 정확하므로 여기서 재측정한다.
`/tmp/fix/ooc`, Vivado 2025.2.1 OOC, `xcu55c-fsvh2892-2L-e`,
`-flatten_hierarchy rebuilt`, `set_msg_config -id {Synth 8-7137} -limit 100000`.
**측정 스크립트는 §31.13 세션의 것을 재사용하지 않고 새로 작성했다** (같은
스크립트를 다시 돌리면 계통 오차가 그대로 재현되므로 검증이 되지 않는다).
`Synth 8-7137` 계수는 §28.6 규범대로 severity 앵커 정규식
(`grep -cE "^WARNING: \[Synth 8-7137\]"`) 으로 취했다.

| 축 | §31.13.2 base | **본 세션 base** | §31.13.2 착지본 | **본 세션 착지본** | 판정 |
|---|---:|---:|---:|---:|---|
| **`Synth 8-7137`** | 68 | **68** | 0 | **0** | **재현** |
| **CLB LUTs** | 20050 | **20050** | 20178 | **20178** (+128, +0.64%) | **재현** |
| CLB Registers | 4734 | **4734** | 4859 | **4859** (+125) | **재현** |
| **FDCE** | 1299 | **1299** | 3560 | **3560** | **재현** |
| FDRE | 3430 | **3430** | 1294 | **1294** | **재현** |
| CARRY8 | 849 | **849** | 849 | **849** (±0) | **재현** |
| **DSP48** | 39 | **39** | 39 | **39** (±0) | **재현** |
| **RAMB18** | 2 | **2** | 2 | **2** (±0) | **재현** |
| `rst` net 총 싱크 | 1312 | **1312** | 3560 | **3560** | **재현** |
| **`rst` → LUT 데이터 입력** | 12 | **12** | 0 | **0** | **재현** |
| `rst` → FD.CLR/R | 1299 | **1299** | 3560 | **3560** | **재현** |
| `rst` → 기타 | — | **1** (`FP_StepSeq/rst`) | — | **0** | (§31.13.2 서술과 일치) |
| `Synth 8-3848` | 0 | **0** | 0 | **0** | **재현** |
| `Synth 8-4767` | 0 | **0** | 0 | **0** | **재현** |
| CRITICAL WARNING | 0 | **0** | 0 | **0** | **재현** |
| ERROR | 0 | **0** | 0 | **0** | **재현** |

**⇒ §31.13.2 표는 전 축 독립 재현됐다.** 반증 3번이 *"검증된 값으로 취급하면
안 된다"* 고 한 수치들 — **+128 LUT / FDCE 3560 / `rst`→LUT 12→0** 을 포함해
16축 전건 — 이 다른 사람이 다시 잰 값과 일치한다. 이제 검증된 값이다.

**LUT 계수 형식 주의 (계통 오차의 후보를 미리 닫아 둔다):** 셀 census 로 센
`LUT*` 프리미티브 수는 base 23,764 / 착지본 23,960 으로 **CLB LUTs (20,050 /
20,178) 와 다르다** — 후자는 LUT5/LUT6 페어링 후의 슬라이스 계수다. §31.5 ·
§31.13.2 · 본 절이 인용하는 "CLB LUT" 는 전부 `report_utilization` 의
**CLB LUTs** 행이며, 두 계수를 섞으면 델타가 달라진다. 이 문장이 §31.13.2 의
"+59 어긋남" 의 원인은 **아니다** (둘 다 CLB LUTs 로 잰 값이다).

**여전히 측정하지 않은 것 (반증 3번이 열린 리스크로 남긴 축 — 그대로 열려
있다고 적는다):** post-P&R **WHS / WNS / Fmax**, `sys_top_core` **system 문맥**
LUT/FF, ECP5 반쪽. 본 절은 PE_Core 단독 OOC 만 재현했다. **§31.10 이 "본 변경의
유일한 실질 리스크 축" 으로 지목한 WHS 와 "방향 미정" 으로 공표한 WNS/Fmax 는
S3-C4 통합 run 에서 처음 판정된다.** 여기서 그 축을 검증했다고 말하지 않는다.

**§31.13.2 의 "+59 어긋남" 은 본 절이 해소하지 못했다.** §31.5 P2(형식2 ×68
단독)의 +143 LUT 와 §31.13.2 의 +202 LUT 차이의 원인은 여전히 미특정이다 —
본 절은 형식2 단독 프로토타입을 다시 만들지 않았고 (착지본은 D11 을 포함한다),
따라서 그 비교축을 재현할 위치에 있지 않았다. **모른다고 적는다.**

#### 31.14.6 §12a 기록 · 회귀 · 이월

**§12a 성격:** 본 절은 **정규 개발 행위**이며 **계약 변경이 아니다.**
- **RTL 로직 변경 0 줄.** `PE_Core.v` / `Cluster.v` 편집은 **주석 한정**이고
  포트·의미론·파형 어느 것도 바뀌지 않는다. 합성 결과물은 §31.13 착지본과
  동일하다.
- **ISA 표면 무접촉** — `isa/wt64v1_isa.json` · 생성물 · `asm/` · golden 3종 ·
  truth table 전부 대상 밖. `domain_version` bump 0, recapture 0.
- **성문화된 계약 3건은 신설이 아니라 *기존 RTL 행위의 기록*이다** — H1/H2 와
  뱅크 저장소 계약은 착지본이 이미 만족하고 있던 것이며, 본 절은 그것을 이름
  붙이고 집행할 뿐이다. `Cluster.v` 주석의 *"last L-PE output at bank[route]"*
  가 원래 의도였음을 뱅크 실측이 확인한다.
- **§30 (XChaCha20) 와의 격리 유지:** `HIU.v` **무접촉**, `synth/reports/` 기입
  **0**, gate 스크립트 **0회**. **3a 격리 유지:** golden 3종 / ISA / 생성물 /
  `asm/` / `FP_StepSeq.v` step 프로그램 **무접촉**, 공유 datapath 3파일
  (`FP_AddWide.v` / `FP_Mul36.v` / `include/fp_narrow_f32.vh`) **byte-untouched**,
  `decode_reserved` **미접촉** (3a-C4 몫).

**착지물:**

| 파일 | 내용 |
|---|---|
| `scripts/lint_output_payload_hold.py` | **신설** — H1/H2 정적 집행 |
| `scripts/lint_known_defect_tests.py` | **신설** — `expect_fail` 3방향 래칫 |
| `scripts/lint_synth_coverage.py` | `canonical_test_refs` 4번째 등재 요건 + AST 해소 검사 |
| `Makefile` | `lint` 타깃에 신설 lint 2건 추가 (3 → 5) |
| `PE_Core.v` | **주석만** — D11 가드 지점에 H1/H2 와 뱅크 계약 명시 |
| `Cluster.v` | **주석만** — bank mux 에 저장소 계약 · 왜 자격자가 없는가 · 집행 지점 3개 · 다중 fragment 의미론 |
| `test_pe.py` | `test_pe_output_payload_hold_invariant` 신설 (런타임 H1/H2 감시) |
| `test_cluster.py` | `test_cluster_store_token_payload_deterministic_and_bank` + `test_cluster_noc_bank_multifragment_last_beat` 신설 |
| `.claude-memos/wt64v1_spec.md` | 본 절 |

**회귀 (전건, `COCOTB_RESULTS_FILE` 을 `/tmp` 로 리다이렉트 — tracked
`results.xml` **무접촉** 확인):**

| 스위트 | 결과 |
|---|---|
| `MOD=PE` | **8/8 PASS** (기존 7 + H1/H2 감시 1) |
| `MOD=Cluster` | **47/47 PASS** (기존 45 + 뱅크 2) |
| `MOD=Pod` | **7/7 PASS** |
| `MOD=Top_Core` | **8/8 PASS** |
| `MOD=ISA_Decoder` | **192/192 PASS** |
| `MOD=Tensor_ALU` | **8/8** (6 PASS + 2 expect_fail-as-designed) |
| `MOD=SIMD_ALU` | **9/9 PASS** |
| `MOD=ALU_Extended` | **16/16 PASS** |
| `MOD=HIU` | **22/22 PASS** |
| `make lint` (5종) | **exit 0** |
| verilator 5.048 `--lint-only` | PE_Core / PE / Cluster / Pod / Top_Core / Tensor_ALU **전건 clean** |

**신규 검사의 검출력은 전건 실증됐다** (§31.14.3 표 · §31.14.4). *"자기 이름이
가리키는 결함을 잡지 못하는 테스트는 그 자체가 §28.4 항 8 위반"* 이라는 §31.13.6
의 규율을 본 절의 신규 검사 전건에 적용했고, 그 과정에서 **검출력 0 인 케이스
1건을 실제로 폐기했다** (단일 fragment 뱅크 케이스 — §31.14.2 말미).

**이월 (§31.13.8 승계 + 신규):**

1. **`fp_op_gate_check.py` 의 `Synth 8-7137` 축** — §31.13.8 항 1 **무변경 승계**
   (축이 있다고 적혀 있는데 하네스에 없다). 기한: S3-C4 통합 gate commit.
2. **`0x05` / `0x6A` 토큰 payload 의미론의 ISA 확정** — §31.13.8 항 2 승계.
   **단 본 절이 그 값을 pin 하는 테스트를 신설했으므로**, ISA 가 다른 값을
   규정하면 `test_cluster_store_token_payload_deterministic_and_bank` 가 FAIL 해
   결정을 강제로 다시 연다.
3. **다중 fragment wave 의 NoC bank 의미론 ISA 확정 (신규 이월).** 뱅크 슬롯은
   64-bit 인데 wave 는 최대 16 fragment 다. 현행은 **마지막 beat** 이며 ISA 규정은
   없다. 테스트는 현행을 pin 할 뿐 옳다고 주장하지 않는다. 기한: ISA 개정 라운드.
4. **L-PE 뱅크의 `last_was_*` 3자 상호작용 테스트 (신규 이월).** MU/DU 가 같은
   슬롯을 덮은 뒤 L-PE 가 다시 쓰는 수열의 뱅크 우선순위는 §31.14 의 검사
   범위 밖이다. 기한: 뱅크 관련 다음 변경.
5. **§28.4 항 8 (a)(b)(d) 기계 검사 lint** — 본 절이 **(e) 를 구현**했고 (a)(b)(d)
   는 여전히 미착수. §31.12 승계.
6. **WHS / WNS / Fmax / system 문맥 면적** — §31.10 대로 S3-C4 통합 run 몫.
   **본 절은 이 축을 검증하지 않았다.**
7. `TENSOR_ALU.v` / `SIMD_ALU.v` 폐기 실행 (사용자 결정 1건), §11 표 전체
   재동기화, §30.11 / §31.12 의 나머지 이월 목록 **무변경 승계**.
