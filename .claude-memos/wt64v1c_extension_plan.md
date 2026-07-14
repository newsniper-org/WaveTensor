<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# WT64v1-C 확장 — 계획 (구현 미포함)

작성일: 2026-05-03
상태: **plan-only** (코드 미구현 — base v1 conformance 위에 별도 design pass)

본 메모는 WaveTensor base ISA `WT64v1`(별도 메모)에 conformance를 가지는 위에서 **암호 / 비트 순열** 확장을 정의하는 `WT64v1-C` 사양의 계획안이다. 본 메모는 WT64v1 lock 직후의 후속 설계 단계 입력 자료로서, 구현 일정·인터페이스·다이 분리 정책을 결정한다.

## 1. 범위

`WT64v1-C`는 다음 두 그룹의 명령어를 base v1에 추가한다:

1. **Crypto co-processor 명령군**: AES / LEA / CRC / SHA-3
2. **Bit-permutation 명령군**: PEXT / PDEP

두 그룹 모두 base PE_Core dispatch에서 **분리된 실행 경로**를 가진다. 1번군은 별도 다이/chiplet, 2번군은 PE_Core 내부 전용 functional unit으로 구현 권장.

## 2. Crypto co-processor 다이 (별도 chiplet)

### 2.1 분리 동기 (WT64v1 base에서 빠진 이유)

| # | 사유 | 영향 |
|---|---|---|
| 1 | 워크로드 격리 | 암호 라운드는 round-key 스케줄과 S-box LUT을 무겁게 사용 — 본체의 1 cycle/op dataflow 모델과 mismatch. 별도 다이는 본체 timing/area에 영향 0. |
| 2 | Trust boundary 명확화 | AES key, SHA-3 absorb state 등 비밀 자료가 본체 register file에 누설되지 않음. HIU(TRNG/IOMMU)와 함께 신뢰 컴퓨팅 베이스에 격리. |
| 3 | SCA / fault isolation | 전력/EM 사이드채널, fault injection 대응이 단순. 본체 dataflow 활동 패턴과 섞이면 마스킹/dummy op 비용 폭발. |
| 4 | Process node 자유도 | 본체는 logic-dense node, 암호 다이는 mature node 가능. chiplet packaging에 자연스러움. |
| 5 | 인증 부담 분리 | FIPS 140-3 / KCMVP 등 인증은 격리된 다이에서 진행이 단순. |

### 2.2 후보 명령군

| Group | Algorithms | 특이점 |
|---|---|---|
| **AES** | AES-128 / AES-192 / AES-256 round + key expansion + GCM | 128-bit block, 10/12/14 round. S-box는 LUT 또는 GF(2⁸) inverter. |
| **LEA** | LEA (KS X 3246) — 32/64/128-bit block, 24-round | ARX 기반 — ChaCha20과 구조 유사. 한국 lightweight 표준. |
| **CRC** | CRC-32 / CRC-32C (Castagnoli) | Slicing-by-N table 또는 Barrett reduction. 1 cycle/byte. |
| **SHA-3** | SHA3-256 / SHA3-512 / SHAKE128 / SHAKE256 (Keccak-f[1600]) | 1600-bit state, 24-round. θ/ρ/π/χ/ι 라운드 함수. |

### 2.3 인터페이스 옵션

| 옵션 | 설명 | 장단점 |
|---|---|---|
| (a) **OPREF.src_kind=3** (crypto-coproc bank) | 본체 OPREF 메커니즘 확장. crypto 다이가 토큰을 받아 결과를 bank에 기록, 본체 PE는 bank 조회로 결과 fetch. | 기존 메커니즘 재사용, ISA 표면적 변경 최소. dataflow 모델 일관성. |
| (b) 새 opcode range `0x60..0x6F` (CRYPTO group) | dedicated opcodes per algorithm. e.g., 0x60 AES_ROUND, 0x61 AES_KEYEXP, 0x68 SHA3_ROUND. | 명시적, 추적 용이. PE_Core dispatch에 새 case 필요 — 다이 분리 의도와 충돌. |
| (c) **Hybrid**: streaming MMIO interface + control opcode | 본체에서 `0x60 CRYPTO_CTL`로 다이 상태 전이 명령. 데이터는 별도 streaming bus. | 다이 격리 가장 명확. 인증 단순. dataflow 모델에서 약간 이질적. |

**1차 권장**: (c) Hybrid — chiplet 격리 정신과 가장 부합.

### 2.4 다이 보드라인

- 본체 ↔ crypto 다이는 chiplet interconnect (UCIe / Bunch-of-Wires) 또는 board-level AXI-Stream
- 본체에서 보낸 토큰 = `(op_id, key_handle, payload)` 형식
- 다이 내부 round 처리는 자체 클럭 도메인 가능 (본체 100 MHz와 무관)
- 결과 토큰은 본체로 돌아옴 — `last_was_coproc[k]` flag로 bank 추적

### 2.5 Phase 분할 (구현 시점)

1. **Phase C1**: Crypto-coproc dummy chiplet — 단순 echo 동작. ISA 인터페이스 검증.
2. **Phase C2**: AES-128 round + key expansion. FIPS-aligned test vectors.
3. **Phase C3**: LEA-128 round (KMVP-aligned).
4. **Phase C4**: SHA3-256 / SHAKE.
5. **Phase C5**: CRC-32 / CRC-32C.
6. **Phase C6**: GCM / SHAKE squeeze 모드.

각 Phase는 chiplet design + 본체 interface + 인증 testset를 포함.

## 3. PEXT / PDEP

### 3.1 의미

| Op | 의미 |
|---|---|
| **PEXT** (parallel bit extract) | mask가 1인 비트 위치만 source에서 뽑아 결과의 하위로 정렬 |
| **PDEP** (parallel bit deposit) | source의 하위 비트를 mask가 1인 위치에 분산 배치 |

### 3.2 use-case

- **Bit permutation networks** (cryptography 보조, ChaCha20/SHA의 round 외 비트 셔플링)
- **Hash mixing** (MurmurHash, xxHash 등에서 비트 흩기)
- **Compression** (RLE, bit packing/unpacking)
- **GPU-style ballot operations** (warp 단위 mask 압축)

### 3.3 비용 추정

64-bit PEXT/PDEP 각 ~500 LUT (barrel network — 6-stage, log₂(64) 단계의 conditional swap)
PE_Core당 +1000 LUT, Pod 16-PE × 2 unit = 32K LUT 추가 → XCAU25P 사용률 65% (현재 44% → 65%)

### 3.4 ISA 매핑 후보

| Op | Mnemonic | 역할 | EH legality |
|---|---|---|---|
| `0x57` | `PEXT` | extract by mask | port + opref (binary, mask in B) |
| `0x58` | `PDEP` | deposit by mask | port + opref |

bitwise binary 그룹과 동일한 legality. dec_eff_b_value를 mask로 사용.

### 3.5 도입 결정 기준

- BNN / 압축 / 해시 워크로드의 실제 빈도 측정 (소프트웨어 프로파일링) 후 결정
- LUT 비용 1000/PE는 Pod에 32K 추가 — 현재 99K 사용까지 여유 있음
- 도입 시 PE_Core 내부 unit (M-UNIT/DIV-UNIT처럼 별도 분리는 과도) 권장

## 4. 확장 conformance 표시

WT64v1-C conformant 디바이스는 다음을 만족:

1. WT64v1 base 모든 요건 충족 (mandatory).
2. 본 메모 §2 또는 §3 또는 둘 다 구현.
3. 부분 구현 시 sub-conformance flag 노출:
   - `WT64v1-C/AES-128`
   - `WT64v1-C/LEA-128`
   - `WT64v1-C/SHA3-256`
   - `WT64v1-C/CRC32C`
   - `WT64v1-C/PEXT-PDEP`
4. 본체에서 미지원 -C op 수신 시 `lower_required` 발사.

## 5. 후속 작업 트리거

**Note (2026-07-14)**: 초기 검토 과정에서 EINSUM completeness (SPLAT / SIG_BMM / SIG_TRACE_IIJ) 를 WT64v1-C 로 편입하는 방안을 논의했으나, **이 3가지는 base ISA 완결성 문제** 로 판단하여 **WT64v1 v1.1 amendment** 로 이관됨. 자세한 근거는 [`wt64v1_spec.md`](./wt64v1_spec.md) §14 및 [`einsum_trace_broadcast_analysis.md`](./einsum_trace_broadcast_analysis.md) 참조. 본 메모 (WT64v1-C) 는 crypto / bit-permute 도메인 확장에만 집중.



본 메모의 구현 시작은 다음 중 하나가 발생할 때:
- 보안 워크로드 (TLS termination / disk encryption / MAC) profile 데이터 확보
- KMVP/FIPS 인증 요구 발생
- BNN/압축 워크로드의 PEXT/PDEP 의존성 측정 결과 확보

각 트리거에 대해 별도 design memo + Phase 시작.

## 6. v1 base 와의 분리 약속

본 확장은 **WT64v1 base의 사양을 변경하지 않는다**. v1 base는 -C 확장 유무와 무관하게 단독으로 conformant 가능. -C 확장은 v1 위에 add-on. crypto 다이가 없는 보드에서도 base v1 워크로드는 그대로 동작.
