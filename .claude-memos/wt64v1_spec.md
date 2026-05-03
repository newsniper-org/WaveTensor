<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# WaveTensor 기본 ISA v1 (WT64v1) — 사양

작성일: 2026-05-03
상태: **확정 (locked)**

본 문서는 WaveTensor의 기본 명령어 집합 아키텍처 v1, 약칭 **WT64v1**의 정식 사양이다. 본 사양에 conformant한 디바이스는 별도 확장 없이도 단독으로 의미 있는 dataflow / scalar 워크로드를 수행할 수 있어야 한다.

확장은 v1 사양에 conformance를 가지는 위에서 추가된다 — 첫 번째 정의된 확장은 `WT64v1-C` (crypto + bit-permute, 별도 메모 참조).

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
| 참조 구현 보드 | ALINX AXAU25 (XCAU25P, -2 speed grade) |
| Reference timing | 100 MHz core clock, WNS +2.06 ns post-route |
| Reference resource | LUT 61.9K / 141K (44%), DSP 140, Power 0.62 W |

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

- WT64v1 사양은 본 문서 시점에서 **freeze**된다.
- 향후 변경은 **v1.1** (backward-compatible 추가) 또는 **WT64v2** (incompatible)로 분류.
- 새 opcode 추가는 5장 reserved 영역에서 시작.
- TRNG/HIU sub-spec 변경은 v1.x patch 가능.
- Conformance test suite는 본 메모와 함께 freeze된 cocotb 회귀 (185 tests)로 정의됨.
