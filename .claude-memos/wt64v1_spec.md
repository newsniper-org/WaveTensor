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

### 3.1 Control / memory

| Op | Mnemonic | 의미 | 인자 |
|---|---|---|---|
| 0x00 | NOP | no-op | — |
| 0x01 | WADV | Wave-advance (wave_number+=1) | port |
| 0x02 | STEER | Pass-through with new tag | port |
| 0x03 | MERGE | Merge alias of STEER | port |
| 0x04 | LD | Memory load via HIU | port + mem |
| 0x05 | ST | Memory store via HIU | port + mem |

### 3.2 Arithmetic / bitwise (binary)

`port + (imm XOR opref)` legality.

| Op | Mnemonic | Action |
|---|---|---|
| 0x10 | ADD | a + b |
| 0x11 | SUB | a − b |
| 0x12 | MUL | a × b (multi-cycle, M-UNIT) |
| 0x13 | DIV | a / b (bit-serial, DIV-UNIT, 64 cycles) |
| 0x14 | AND | a & b |
| 0x15 | OR  | a \| b |
| 0x16 | XOR | a ^ b |
| 0x1C | REM | a % b (bit-serial, DIV-UNIT) |
| 0x1D | DIVREM | {a/b, a%b} 32-bit halves (bit-serial, 32 cycles) |
| 0x51 | NAND | ~(a & b) |
| 0x52 | NOR  | ~(a \| b) |
| 0x53 | XNOR | ~(a ^ b) |

### 3.3 Shift / rotate (require IMM16)

`port + imm16` legality, `forbid opref`.

| Op | Mnemonic | Action |
|---|---|---|
| 0x17 | SHL | a << imm6 (logical) |
| 0x18 | SHR | a >> imm6 (logical) |
| 0x19 | SAR | $signed(a) >>> imm6 (arithmetic) |
| 0x1A | ROR | rotate_right_64(a, imm6) |
| 0x1E | ROL | rotate_left_64(a, imm6) |

### 3.4 Unary scalar

`port` only.

| Op | Mnemonic | Action |
|---|---|---|
| 0x1B | NEG | ~a + 1 (two's complement) |
| 0x1F | BITREV | bit-reverse 64-bit |
| 0x50 | NOT | ~a (1's complement) |
| 0x54 | POPCNT | hamming weight (0..64) |
| 0x55 | CLZ | leading zero count (0..64) |
| 0x56 | CTZ | trailing zero count (0..64) |

### 3.5 Shape ops

`port + imm16` legality.

| Op | Mnemonic | Action |
|---|---|---|
| 0x20 | SQZ | squeeze (tag-only) |
| 0x21 | USQZ | unsqueeze (tag-only) |
| 0x22 | VIEW | shape view (tag-only) |
| 0x23 | PERM | permute (2×2 transpose는 PE-local; 그 외 lower_required) |
| 0x24 | BCAST | broadcast (모두 lower_required) |
| 0x25 | RED | reduce_axis (axis=0, dim=0x03 + sum/max/min만 PE-local) |

### 3.6 Tensor binary

`port + opref` (require), `F_HAS_OPB=1`.

| Op | Mnemonic | Action |
|---|---|---|
| 0x30 | MATMUL | 2×2 × 2×2 matmul (M-UNIT, MATMUL_UNIT 패턴) |
| 0x31 | TADD | element-wise tensor add |

### 3.7 EINSUM

`port + subscript + opref` (require), `F_HAS_OPB=1`. HW-direct 10 패턴:

| Pattern | Mnemonic 형 |
|---|---|
| `i->` (sum) | SIG_SUM_I |
| `ii->` (trace) | SIG_TRACE_II |
| `ij->ji` (transpose) | SIG_TRANSPOSE |
| `ij,jk->ik` (matmul) | SIG_MATMUL |
| `ij,ij->ij` (hadamard) | SIG_HADAMARD |
| `i,j->ij` (outer) | SIG_OUTER |
| `ijk->ij` (partial sum) | SIG_PARTIAL_IJK |
| `ii->i` (diagonal) | SIG_DIAGONAL |
| `i,i->` (dot) | SIG_DOT |
| `ij,j->i` (mat-vec) | SIG_MAT_VEC |

지원 외 패턴 → `lower_required`. opcode `0x32`, mnemonic `EINSUM`.

### 3.8 Unary FP

`port` only.

| Op | Mnemonic | Action |
|---|---|---|
| 0x40 | FLOOR | floor |
| 0x41 | ROUND | round-to-nearest |
| 0x42 | CEIL | ceil |
| 0x43 | ENORM | euclid_norm (re² + im²) |
| 0x44 | CONJ | complex conjugate |

### 3.9 Reserved

| Range | 상태 |
|---|---|
| `0x06..0x0F` | 미할당 (장래 control/memory 확장) |
| `0x26..0x2F` | 미할당 (binary scalar MIN/MAX 후보 — 별도 논의) |
| `0x33..0x3F` | 미할당 (텐서 확장) |
| `0x45..0x4F` | 미할당 (FP unary 확장) |
| `0x57..0x5F` | 미할당 (bitwise 확장) |
| `0x60..0xFF` | **WT64v1-C 확장 영역** (crypto / PEXT-PDEP) |

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
- v1.6.2 에서 5-bit interpolated rsqrt LUT 로 rsqrt 정밀도 향상 가능.

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

### 22.11 SDK composition pattern

`wavetensor_asm.py` 또는 상위 SDK 는 `_lower_norm_*` macro pass 를 통해 norm 을 primitive 시퀀스로 lowering. 예시 골격:

```python
def _lower_layernorm(inst: Instruction) -> List[Instruction]:
    """LayerNorm macro expansion into RISC-ish primitive sequence."""
    # Read γ, β, eps, N from macro args
    # Emit 8-primitive chain per §22.3
    return [
        make_sig_mean_5d_to_4d(x_tag),
        make_simd_sub_wide_vec(x_tag, mu_tag),
        make_sig_l2sq_5d_to_4d(xc_tag),
        make_simd_mul_wide_scalar(sq_tag, inv_N),
        make_simd_add_wide_scalar(var_tag, eps),
        make_scalar_rsqrt_approx(vare_scalar_tag),
        make_simd_mul_wide_scalar(xc_tag, scale_tag),
        make_simd_mul_wide_vec(nrm_tag, gamma_tag),
        make_simd_add_wide_vec(sc_tag, beta_tag),
    ]
```

**미탑재 (v1.6.1c 는 spec only)**: 실제 macro pass 구현은 assembler / SDK 별도 후속 작업. `wavetensor_asm.py` 에 `NORM_MACROS` 등록 + `macro_pass` 확장이 후속 amendment.

### 22.12 회귀

Groups A+B+C 회귀 (v1.6.1a + v1.6.1b commits 참조):
- **276 tests PASS** (194 cocotb + 71 assembler; 신규 24 tests over v1.5.5's 252)
- 이 §22 문서는 **spec-only landing** — RTL 무변경, 회귀 유지

### 22.13 남은 v1.6.2+ 스코프

- **v1.6.2**: SIG_MEAN/SUM/L2SQ_4D_TO_3D (InstanceNorm partial support 완성)
- **v1.6.3**: rsqrt mantissa LUT refinement (16-entry Q1.15) → ~4-bit precision
- **v1.6.4**: SDK `_lower_norm_*` macro pass 구현 + assembler 정합성 tests
- **v1.6.5**: Multi-slot fragment buffer (동시 wave 다수, latency amortization)
- **v1.6.6**: PE_Core `pe_ready` back-pressure (norm chain stall 대응)

### 22.14 진입 트리거

v1.6.1c amendment 는 **결정된 상태 (2026-07-15)**. 사용자 지시 (ultracode mode, RISC-ish 원칙): "어떤 정규화 기법이든 상관없이, 덩어리째로 가속시키는 것 대신에 유한한 가지수의 연산들로 분해하고 그 '유한한 가지수의 연산들'을 가속시키는 쪽으로 정규화 기법 가속 방안 모색". v1.6.1a → v1.6.1b → v1.6.1c 3-commit 순차 landing 으로 primitive basis + broadcast + rsqrt + 문서화 완비. 구현 완료 (2026-07-15).
