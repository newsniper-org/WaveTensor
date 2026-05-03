<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# 표준 Bitwise 연산 확장 — 도입 결정 및 ISA 매핑

작성일: 2026-05-03
컨텍스트: 16-PE Pod 구현 후 timing closure 완료. PE_Core LUT 1.6 K. Bitwise 연산은 cycle당 ~64 LUT의 매우 저렴한 비용이라 expand 여력 large.

## 도입할 연산 목록과 그 이유

기존 ISA에는 binary bitwise 연산이 SHL/ROR/BITREV (그리고 `~x+1`로 implement된 NEG)밖에 없어 다음과 같은 표준 워크로드가 막혀 있었다:

| 연산군 | 도입 동기 |
|---|---|
| **AND/OR/XOR** | 비트마스킹, 플래그 합성, packed-array 부울 연산. CRC/checksum 등의 stream-level kernel. 이 셋이 없으면 boolean tensor 연산을 외부 lowering으로 강제. |
| **NAND/NOR/XNOR** | universal gate set 완성, secure-computation의 garbled circuit 평가, 이미지 픽셀 단위 비교 (XNOR-pop = 효율적 hamming similarity, BNN의 dot product). XNOR-pop은 binarized neural network에 직결. |
| **NOT** (pure) | 1's complement (이미지 invert, 부울 negate). 기존 0x1B는 2's complement라 별개 연산이 필요. |
| **SHR (logical) / SAR (arithmetic)** | unsigned/signed shift 분리. Hash mixing, fast division by power-of-2, sign extension. 이 둘 없이는 fp16 mantissa decode조차 어려움. |
| **ROL** | 추가 rotate 방향. ChaCha20/Salsa20/SHA-2 round 연산이 ROL을 직접 사용 — 기존 ROR만으로는 컴파일러가 `rotate_left = rotate_right(64-n)`으로 우회해야 함. |
| **POPCOUNT** | hamming weight. BNN dot product의 핵심 (`xnor + popcount`), bloom filter 카운팅, fast set cardinality. CPU에는 거의 모두 instruction이 있음. |
| **CLZ / CTZ** | 정수의 log₂, 가장 가까운 power-of-2 라운딩, bit-set scanning, IEEE 754 mantissa 정렬. fp emulation에서 빈번. |

## ISA 매핑

기존 `0x10..0x1F` 산술/비트 범위 안에 빈 슬롯들 활용 + 새 `0x50..0x56` 범위 신설:

| Opcode | 니모닉 | 클래스 | 인자 | EHDecode legality |
|---|---|---|---|---|
| 0x14 | `AND` | binary | A & B | port + (imm XOR opref) |
| 0x15 | `OR` | binary | A \| B | port + (imm XOR opref) |
| 0x16 | `XOR` | binary | A ^ B | port + (imm XOR opref) |
| 0x18 | `SHR` | shift | A >> imm6 (logical) | port + imm16 |
| 0x19 | `SAR` | shift | $signed(A) >>> imm6 | port + imm16 |
| 0x1E | `ROL` | shift | rotate_left_64(A, imm6) | port + imm16 |
| 0x50 | `NOT` | unary | ~A | port |
| 0x51 | `NAND` | binary | ~(A & B) | port + (imm XOR opref) |
| 0x52 | `NOR` | binary | ~(A \| B) | port + (imm XOR opref) |
| 0x53 | `XNOR` | binary | ~(A ^ B) | port + (imm XOR opref) |
| 0x54 | `POPCNT` | unary | hamming weight | port |
| 0x55 | `CLZ` | unary | leading zero count | port |
| 0x56 | `CTZ` | unary | trailing zero count | port |

기존 0x10..0x1F 범위는 다 차게 됨 (0x14/15/16/18/19/1E를 채워서 이제 5-bit ALU 그룹에 빈 슬롯 없음). 차후 더 많은 비트 op이 필요하면 0x50..0x5F 범위 확장.

## 구현 비용 추산

| 연산 | LUT (per PE_Core) | 비고 |
|---|---:|---|
| AND/OR/XOR/NAND/NOR/XNOR | ~64 each × 6 = 384 | 64-bit binary boolean |
| NOT | ~0 | wire only (`~`만 인버터) |
| SHR | ~150 | 64-bit barrel shifter (logical) |
| SAR | ~150 | sign-extend barrel |
| ROL | ~150 | rotate (SHL/SHR 둘 다 사용) |
| POPCOUNT | ~250 | 64-bit adder tree |
| CLZ/CTZ | ~200 each | priority encoder |
| **합계** | **~1,500 LUT/PE_Core** | 기존 1,645 LUT의 ~91% 추가 → 예상 ~3.1 K LUT/L-PE |

Pod 16 L-PE × 3.1 K = ~50 K LUT (이전 26 K에서 +24 K). XCAU25P Logic LUT 141 K 한도 대비 사용률 35% → ~50% 예상. 여유 충분.

NOTE: 실제 합성에서는 Vivado가 binary boolean 연산을 LUT-fusing해서 위 추산보다 적게 쓸 수 있음. 측정 후 업데이트 필요.

## EHDecode 변경

`opcode_supported`에 0x14/15/16/18/19/1E/50/51/52/53/54/55/56 추가. 합법성 표는 세 그룹으로 정리:

1. **Binary ALU (XOR of imm/opref)**: 0x10/11/12/13/14/15/16/1C/1D/51/52/53
2. **Shift/rotate (require imm16)**: 0x17/18/19/1A/1E
3. **Pure unary**: 0x1B/1F/50/54/55/56

## 결정론 vs DCE

새 unary opcodes(0x50/54/55/56)는 모두 단순 combinational, multi-cycle 미사용.
- `MUL_OPS_SUPPORTED=0` (L-PE): 영향 없음 — bitwise는 mul-class 아님.
- `DIV_OPS_SUPPORTED=0` (L-PE/M-UNIT): 영향 없음.
- `NON_MUL_OPS_SUPPORTED=0` (M-UNIT, DIV-UNIT): bitwise op 들어오면 lower_required로 처리 (기존 패턴 유지). 새 opcodes는 `dec_is_div_op` / `dec_is_mul_op`에 안 들어가니까 자동으로 NON_MUL 그룹으로 분류됨 → M-UNIT/DIV-UNIT은 lower_required 발사. L-PE만 실제 실행. 의도대로 작동.

## Test 전략

각 opcode마다 양성(positive) 테스트 1-2개 추가 (총 13개). 음성 테스트는 기존 chain-error / forbidden-EH 메커니즘이 자동으로 커버.

특히 검증한 코너 케이스:
- `SAR`: MSB=1 input → sign-fill 확인 (`0x80...10` >> 4 = `0xF8...01`)
- `SHR`: MSB=1 input → zero-fill 확인 (`0x80...10` >> 4 = `0x08...01`)
- `ROL`: 8-bit rotate로 byte 위치 wrap 확인
- `XNOR`: 동일 input에서 all-ones 확인
- `CLZ/CTZ`: 입력 0일 때 64 반환 (대부분의 ISA처럼)
- `POPCOUNT`: 패턴 0xF0F0... 확인 (32개 1)

## 회귀 결과

전체 122 테스트 (109 + 13 신규) 모두 PASS. assembler 58 unit test + cocotb 64 RTL test.

## 미도입 — 의도적 제외 / 후속 논의

### 별도 co-processor 다이로 분리 검토 (이번 ISA에 포함시키지 않음)

`AES / LEA / CRC / SHA-3` 류 도메인 특화 instruction은 본체 PE_Core에 박지 않고 **독립 co-processor 다이**로 분리하는 방향을 검토. 분리 동기:

- **워크로드 격리**: 암호 라운드는 round-key 스케줄과 S-box LUT을 무겁게 사용 — 일반 dataflow PE의 1 cycle/op 모델과 잘 맞지 않음. 별도 다이로 두면 본체의 timing/area에 영향 없음.
- **Trust boundary**: HIU/TRNG와 함께 신뢰 경계를 명확히 그을 수 있음. AES key, SHA-3 absorb state 등 비밀 자료가 본체 register file에 누설되는 경로를 물리적으로 차단.
- **Fault/SCA isolation**: 전력/EM 사이드채널, fault injection은 격리된 다이에서 대응이 더 단순. 본체 dataflow 패턴과 활동 패턴이 섞이면 마스킹/dummy op 비용이 커짐.
- **Process node 선택 자유도**: 본체는 logic-dense node, 암호 다이는 mature node로 갈 수 있음 (cost/yield 최적화). chiplet 패키징에 자연스러움.
- **표준 인터페이스**: WaveScalar 토큰 형태로 ChaCha20-style streaming 인터페이스 (이미 HIU에 존재) 또는 별도 OPREF.src_kind=3 (crypto-coproc) 형태로 본체와 결합.

후보 instruction set:
- **AES**: AES-128/192/256 round, key expansion, GCM
- **LEA** (Lightweight Encryption Algorithm, KS X 3246): ARX 기반 Korean lightweight 암호 — 32/64/128-bit block. ChaCha20과 구조 유사하므로 코어 재사용 가능.
- **CRC**: CRC-32/CRC-32C (ISO 3309, IEEE 802.3) — Slicing-by-N, polynomial table.
- **SHA-3** (Keccak): θ/ρ/π/χ/ι 라운드 함수, 1600-bit state.

별도 메모로 상세 설계 후 결정 — 본 메모 범위 밖.

### 후속 상세 논의 예정 (deferred)

| 연산 | 보류 사유 |
|---|---|
| **PEXT/PDEP** (BMI2-style parallel bit extract/deposit) | bit permutation/hash mixer에 강력하지만 LUT 비용 (~500/op) 대비 사용 빈도 평가 필요. 별도 세션에서 use-case enumeration + 비용 측정. |
| **Binary scalar MIN/MAX** | 0x25 REDUCE_AXIS의 axis-wise MIN/MAX와 별개 — 두 scalar 입력 비교 op. 0x40 직전 범위 (0x26..0x2F)에 슬롯 가능. signed/unsigned 분리 여부, NaN 의미론(FP) 등 함께 결정 필요. |

### 영구 제외

| 연산 | 이유 |
|---|---|
| **MULHI** (high-half mul) | MUL이 multi-cycle 64-bit pipeline. 상위 절반 출력은 단순 wire 추출이지만 별도 op으로 만들 가치 부족 — 필요 시 64-bit MUL 후 `SHR 32`로 합성 가능. |

## 결론

표준 bitwise 13개 (`AND/OR/XOR/NAND/NOR/XNOR/NOT/SHR/SAR/ROL/POPCNT/CLZ/CTZ`) 모두 추가 완료. opcode space는 0x10..0x1F + 0x50..0x56을 사용. PE_Core LUT 영향 +1.5 K (Pod 합산 +24 K), XCAU25P 한도 대비 여전히 50% 미만으로 안전. 회귀 122/122 PASS.

CRC, hash, BNN dot product, signed shift, sign extension, fp emulation 등 표준 워크로드의 lowering 우회가 일제히 해소됨.
