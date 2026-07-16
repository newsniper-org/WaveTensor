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

참조 구현 마이그레이션: **진행 중 (2026-07-12 개시)** — 참조 보드가 XCAU25P → LFE5U-85F → Avant G70 순으로 이동, 아래 §"참조 구현 마이그레이션 노트" 참조.

**Backward compatibility**: v1.1 은 v1.0 의 모든 명령을 지원 + 새 opcode/signature 만 추가. v1.0 conformant 소프트웨어는 v1.1 디바이스에서 그대로 동작. 반대로 v1.1 전용 명령 (SPLAT 등) 을 v1.0 디바이스에 발사 시 `lower_required` 발사 (기존 unknown-opcode 처리 그대로).

본 문서는 WaveTensor의 기본 명령어 집합 아키텍처 v1, 약칭 **WT64v1**의 정식 사양이다. 본 사양에 conformant한 디바이스는 별도 확장 없이도 단독으로 의미 있는 dataflow / scalar 워크로드를 수행할 수 있어야 한다.

확장은 v1 사양에 conformance를 가지는 위에서 추가된다 — 첫 번째 정의된 확장은 `WT64v1-C` (crypto + bit-permute, 별도 메모 참조).

**중요**: ISA 자체 (opcode / EH / tag / payload 정의) 는 확정 상태에서 **변경 없음**. 참조 구현 사양의 리소스 / timing / power 값만 새 벤더 실측 데이터로 순차 갱신된다.

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
| Tensor_ALU | 1 |
| SIMD_ALU | 9 |
| ALU_Extended | 16 |
| Top_Core | 7 |
| PE | 4 |
| Cluster | 12 |
| Pod | 7 |
| **Total** | **185 PASS / 0 FAIL** |

합성: XCAU25P (xcau25p-ffvb676-2-e), 100 MHz, 16-PE Pod, post-route LUT 61.9K (44%), WNS +2.06 ns, DRC 0 errors.

## 12. 변경 정책

- WT64v1 사양의 v1.0 은 2026-05-03 lock 되었고, v1.1 amendment 는 2026-07-14 (§14 EINSUM completeness) 적용.
- 향후 변경은 **v1.x** (backward-compatible 추가) 또는 **WT64v2** (incompatible) 로 분류.
- 새 opcode 추가는 5장 reserved 영역에서 시작.
- TRNG/HIU sub-spec 변경은 v1.x patch 가능.
- Conformance test suite 는 v1.0 시점 185 tests + v1.1 amendment 후 신규 회귀 (SPLAT + BMM + TRACE-IIJ 각 5-10 tests).

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
- int4/int8 **VDOT_ACC/VFMA_ACC → int32 누산기** — order-free bit-exact (NVIDIA IMMA semantics).
- **STORE_QUANT** (int32/fp32 → int4/int8/f16/bf16, RNE+saturate, ≤256-bit — 기존 2-bit frag FSM 과 lint 그대로 생존), **DEQUANT** (slice-select 로 기존 wide int4 wave 수용).
- LayerNorm/RMSNorm/Softmax 매크로를 fp32 통계로 재구축, 종단 1회 양자화 — 기존 문서화된 4개 numerics 버그 (MEAN ASR floor, x-µ mod-16 wrap, gamma p[3:0] truncation, rsqrt 6.25% floor) 전부 은퇴.

**v2.0 "TRAIN"** — 최초 학습 가능 버전 (training triple: bf16 multiply / fused fp32 accumulate / fp32-master-or-SR update).
- 통합 f16/bf16 **fused-FMA** lane (11-bit mantissa 곱셈기 하나로 양쪽 커버; 곱은 wide-exponent 내부 포맷으로 exact 유지, fp32 누산에서 단 1회 RNE). bf16-accumulate 는 구조적으로 금지 (업계 전례 없음). ECP5 에서 FP_LANES=2 가 한계.
- **fp32 ACC bank** (2 × 32 lanes × 32b/cluster, tag pcid[1:0] 로 bank 선택 + 명시적 ownership/drain 계약 + ACC_SPILL/FILL) — "requester ID" 식 암묵 계약은 반증되어 폐기.
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
- 남는 비대칭은 문서화된 3개 carve-out: (a) 정수 exact vs FP correctly-rounded (모든 CPU ISA 와 동일한, 유일하게 정합적인 비대칭), (b) bitwise/shift 는 dtype-transparent raw bits, (c) 기존 truncating int4 벡터 opcode (0x60-0x6C 산술) 는 호환용으로 실행 가능하되 **"compute op" 에서 "storage-format op" 로 재분류** — frozen, 권장 매크로에서 제외, silent loss 명시.

### 23.4 "정밀도 무변동" 의 정직한 정의 (사용자 질문 1 직답) + acceptance criteria

**보장하는 것** (cocotb + numpy/mpmath golden 으로 검증 가능한 normative 계약):
1. exact narrow products (int 은 구조상, f16/bf16 은 wide-exponent 내부 포맷)
2. wide accumulation — int32 는 order-free bit-exact; fp32 는 canonical order 에서 step 당 정확히 1회 RNE
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
- 기존 0x67/0x69/0x6B/0x6C 는 first-class 유지하되 **frozen** — alias-collapse 주장은 반증됨 (혼합 A/B/out-format 이라 단일 dtype nibble 로 인코딩 불가).
- FP 결과를 0x68 로 캐싱하는 recipe 는 PRECISION EH 로 precision byte 를 pin 해야 함 (dim=0x55 pin 과 동일 패턴) — 아니면 결정론적 CAM miss.

#### 23.6a v1.8.0a normative mode-byte legality 표 (2026-07-16 저작 — COMMIT 0)

이 표가 **normative source of review** 다: isa/wt64v1_isa.json 의 fp_block 섹션은 이 표의 전사(transcription)이고, asm 테스트의 spec-row pin 들은 이 표에서 문자 그대로 옮긴다 (별도 commit 에서 선행 리뷰됨으로써 same-author-same-commit 순환을 끊는 독립 anchor).

**정책 (restrictive-first + monotonic loosening)**: 아래 표에 명시되지 않은 모든 (op, dtype, acc, rnd) 조합은 **ILLEGAL (decode_error)**. 이후 버전에서 합법화(loosening)는 non-breaking — 어떤 코드도 거부되던 인코딩에 의존할 수 없기 때문. 역방향(합법→불법)은 breaking 이므로 금지. 불확실하면 ILLEGAL 로 남긴다.

**mode byte 필드**: dtype = eff_precision[3:0], acc = eff_precision[5:4], rnd = eff_precision[7:6]. 이 의미론은 **opcode 0x70-0x7F 안에서만** 활성 (in_fp_block = cb_opcode[7:4]==4'h7 로 self-gate) — 0x00-0x6C 에서 precision byte 는 지금처럼 inert metadata.

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

**EH shape (restrictive-first)**: 0x70/0x71/0x73/0x79 = ALU-binary 형 (port + IMM XOR OPREF); 0x72/0x74/0x75/0x76/0x77/0x78 = port-only (모든 data EH forbidden); 0x7C/0x7D = port+mem; 0x7E = no-data-EH forbid-all. 모든 0x70-block mnemonic 은 assembler 에서 `.precision` EH + `prec` flag **필수** (asm 정적 mode 검사를 exact 하게 만듦). RTL 은 추가로 runtime tag-driven mode byte (input_tag[15:8], flags[2]=0) 를 수용 — 의도된 기록된 비대칭, 불변식 방향은 **asm-legal ⊆ RTL-legal** (equivalence 테스트로 기계 검증).

### 23.7 주요 residual risk (전문은 workflow 산출물)

1. 모든 HW 비용이 문헌 추정 — repo 자신의 Vivado 35-DSP vs yosys 123-MULT18X18D 괴리가 증명하듯, **per-operator FloPoCo + yosys/nextpnr synth 가 예산 확정 전 hard gate**. v2.0 의 ECP5 multiplier 여유는 사실상 0.
2. 어떤 타깃에서도 timing 데이터 없음 (base pod 조차 nextpnr PnR 미완). 5-6-stage fused FMA @100MHz 미증명 — v2.0 첫 마일스톤은 Fmax 산출.
3. ACC bank 는 순수 tagged-wave 모델 밖의 신규 architectural state — tag-keyed bank aliasing 은 silent-gradient-corruption 클래스. **RTL 전에 TLA+/formal 선행** (wavetensor-drivers formal-first 관례).
4. xczu3eg 는 synth report 0건 + board plan 부재 + FP-UNIT 미탑재 확정 — Makefile default 에서 은퇴하거나 int4-inference-only 로 명시 강등할 것.
5. 검증 공수가 RTL 공수를 초과할 전망 (~16 opcodes, fused-FMA pipe, NR microcode, SR, ACC state, canonical-order equivalence) — v2.0 의 지배적 일정 리스크.
6. "training-capable ≠ training-competitive" — 포지셔닝 규율 자체가 리스크.

### 23.8 진입 트리거

**v1.8 결정됨 (2026-07-16).** 사용자 지시: "f64는 별도의 확장(접미사 Lf)에서 본격적으로 다루는 게 좋겠어. 일단은 v1.8 진행해."
- f64 → optional extension **Lf** 로 이관 (§23.2 갱신). base 의 dtype nibble 0x5 는 decode_error 예약 유지, Lf 가 나중에 이 인코딩을 claim.
- v1.8 선행 조건 처리: (1) per-operator synth gate — v1.8.0c (FP-UNIT) 착수 전 완료 필수, (2) base pod nextpnr Fmax — 착수와 병렬 진행 (yosys/nextpnr-ecp5 로컬 설치 확인 완료, make synth-pod-ecp5/impl-pod-ecp5 flow 기존재. **첫 실행이 즉시 성과**: 함수호출 인덱싱 yosys 비호환이 v1.6.1b 부터 잠복해 있었음을 적발 — commit 0afcf81 로 수정), (3) legality-ROM **JSON** codegen (~~YAML~~, §23.6 치환 기록 참조) — v1.8.0a 의 첫 산출물, (4) ACC bank TLA+ — v2.0 전 (v1.8 스코프 아님).
- **enforcement plan (v1.8.0a 설계 workflow 확정)**: freshness 검사(gen_isa_tables.py --check 재생성+byte-diff)는 commit 필수인 `python -m unittest asm.test_wavetensor_asm` 스위트에 test 로 탑승 (no-CI repo 에서 가장 강한 채널); `make lint` 신설 (isa freshness + frag_total_m1_held, 향후 CI entrypoint); 전수 곱집합 decode-legality sweep (`WT_FULL_ISA_SWEEP=1`) 은 **release gate** 로 지정 — per-commit 은 equivalence-class 축약 실행.

### 23.9 v1.8 구현 staging

- **v1.8.0a**: ISA foundation — 단일 **JSON** 소스 codegen (legality ROM + asm.py 테이블 + golden model + spec 표 + lint 생성), 0x70-0x7F decode skeleton, mode byte field 파싱 (dtype[3:0]/acc[5:4]/rnd[7:6]). **3-commit staging** (설계 workflow w8gmgeokm 확정): COMMIT 0 = spec 선행 (§23.6a normative 표 저작 — 독립 리뷰로 same-author 순환 차단), COMMIT 1 = 무동작변경 legacy 이관 (isa/wt64v1_isa.json 47 opcodes 를 emitter-faithful 하게 — 알려진 asm-vs-RTL 비대칭 2건도 bit-for-bit 보존, EHDecode.v 의 legality case/is_alu_binary/opcode_supported/EH_* 를 generated include 4종으로 대체, asm.py Section-1 상수를 generated 모듈 import 로 대체, **사전-이관 RTL-derived frozen truth table + EH-subset sweep** 로 zero-behavior-change 증명), COMMIT 2 = 0x70-block skeleton (13 opcodes whitelist 편입, FP_LEGAL_ROM 4096-bit localparam, mode-byte wire 3종 + decode_error 11번째 항, PE_Core stub arm — BCAST 0x24 형 lower_required, asm require_precision_eh)
- **v1.8.0b**: int32 누산 경로 — VDOT_ACC/VFMA_ACC/ACC_REDUCE + int 대상 STORE_QUANT (FP 하드웨어 불요, "벡터 정수 = 스칼라급 신뢰성" 을 가장 먼저 배달)
- **v1.8.0c**: FP-UNIT fp32 scalar pipeline (FSCALAR/FRSQRT32/FEXP2_32) — per-operator synth gate 통과 후
- **v1.8.0d**: CVT/I2F/F2I + DEQUANT + FP 대상 STORE_QUANT + norm 매크로 fp32 재구축
