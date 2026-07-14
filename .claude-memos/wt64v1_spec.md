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
