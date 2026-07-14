<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# WaveTensor NoC Fragment Extension Header — 설계 memo

작성일: 2026-07-14
상태: **v1.5 amendment 로 인프라 landing** (2026-07-14). Fabric 재조립 로직 및 fragment-emitting primitives 는 v1.6+ 로드맵.

> **연관 memo**: [`wt64v1_spec.md`](./wt64v1_spec.md) §17, [`eh_encoding_expansion.md`](./eh_encoding_expansion.md).

## 1. 발상 배경

사용자 통찰 (2026-07-14): 출력측 64-bit payload 상한을 **NoC packet format 을 breaking 하지 않고** 우회하려면, IP fragmentation (IPv6 Fragment Extension Header) 처럼 논리 payload 를 여러 physical wave token 에 분산 실어 나르면 됨.

원문: "출력측의 opcode와 payload 사이에 8비트짜리 index 필드를 추가하는 건 어떨까? OSI 7계층에서 상위 레이어의 패킷이 너무 거대하면 작은 페이로드들로 쪼개어 하위 레이어의 패킷들에 담을 수 있도록 하는 것처럼..."

## 2. Wave token layout (v1.5)

```
Legacy (v1.0..1.4):
+--------------------+---------+-------------+
| tag (80)           | op (8)  | payload(64) |
+--------------------+---------+-------------+

v1.5 신규:
+--------------------+---------+-------------+-------------+
| tag (80)           | op (8)  | frag_hdr(8) | payload(64) |
+--------------------+---------+-------------+-------------+
                                [7:4] fragment_index
                                [3:0] total_fragments - 1
```

`frag_hdr = 0x00` → total=1, index=0 → **legacy single-fragment**. 모든 기존 primitive 는 이 값 유지 → 100% backward compat.

## 3. IPv6 Fragment Extension Header 와의 매핑

| IPv6 field | WaveTensor frag_hdr | 역할 |
|---|---|---|
| Fragment Offset (13-bit) | fragment_index [7:4] (4-bit) | 논리 payload 안에서의 이 fragment 위치 |
| More Fragments (M) flag | (묵시적) | index < total-1 시 more, index == total-1 시 last |
| Identification (32-bit) | wave token `tag[wave_number, thread_id, port_context_id]` | 같은 논리 payload 소속 fragment 식별 |
| Total Length | (묵시적, sender-declared) | total_fragments - 1 [3:0] |

IPv6 는 총 갯수를 명시 안 함 (MF 플래그로 마지막 감지). WaveTensor 는 sender 가 total 을 encoding — receiver 가 buffer 사이즈 예측 가능.

## 4. 4-bit / 4-bit split 근거

- **max 16 fragment**: 16 × 64 = **1024-bit logical payload**. 
  - 3-batch matmul int4 → 128-bit → 2 fragment
  - 4-batch matmul int4 → 256-bit → 4 fragment
  - 5-batch matmul int4 → 512-bit → 8 fragment
  - 6-batch matmul int4 → 1024-bit → 16 fragment (상한 딱 맞음)
  - 실전 CV/AI 워크로드 대부분 커버.
- 8-bit / 8-bit split 시 256 fragment × 64 = 16 Kbit — 과잉.
- 4/4 가 실용성-표현력 균형점.

## 5. 재조립 시나리오 (v1.6+ 로드맵)

### 시나리오 A: HIU/Cluster 진입에서 재조립 (권장)

- Downstream PE_Core 가 보는 `dec_input_payload` 는 **재조립된 wide payload** (128-bit 등).
- Cluster fabric 이 fragment 를 tag 기준으로 collect + concat.
- PE_Core 인터페이스는 payload width 만 넓힘 (파라메트릭).
- **이점**: PE_Core 내부는 단일 처리, cleanest downstream.
- **비용**: fabric buffer (~16 × 64 × N_ACTIVE_WAVES bit ≈ 16 Kbit / Cluster).

### 시나리오 B: PE_Core 가 fragment 개별 소비

- 각 wave token 도착마다 PE_Core 상태 기계가 fragment 를 accumulator 에 stitching.
- **비용**: PE_Core 상태 폭발 (accumulator + fragment tracking + backpressure).
- **비권장** — fabric layer 에서 처리하는 게 layer 분리 원칙에 부합.

## 6. Wide-output primitive 발행 (v1.6+ 로드맵)

**PE_Core state machine 확장**:

```
    ┌────────────────────────────────────┐
    │ IDLE                               │
    │  ← 명령어 도착, wide 결과 계산     │
    │                                    │
    │  결과 <= 128-bit computation       │
    │  frag_state <= EMIT_LOW            │
    └───────────────┬────────────────────┘
                    │
    ┌───────────────▼────────────────────┐
    │ EMIT_LOW                           │
    │  output_valid = 1                  │
    │  output_payload = result[63:0]     │
    │  output_frag_hdr = 0x0_1           │  ← index=0, total=2
    │  → EMIT_HI                         │
    └───────────────┬────────────────────┘
                    │
    ┌───────────────▼────────────────────┐
    │ EMIT_HI                            │
    │  output_valid = 1                  │
    │  output_payload = result[127:64]   │
    │  output_frag_hdr = 0x1_1           │  ← index=1, total=2
    │  → IDLE                            │
    └────────────────────────────────────┘
```

**Backpressure**: `EMIT_HI` cycle 동안 새 명령어 dispatch 는 stall. Wave-parallel 처리는 서로 다른 tag 로 병렬 흐르므로 head-of-line blocking 없음.

## 7. Cluster fragment reassembly (v1.6+ 로드맵)

**Fragment buffer 구조**:

```verilog
// Per active wave (indexed by wave_number LSBs or hash)
reg [ADDR_WIDTH-1:0] frag_buf [0:FRAG_BUF_DEPTH-1][0:15];
reg [15:0]           frag_mask [0:FRAG_BUF_DEPTH-1];  // 도착 bitmap
reg [3:0]            frag_total [0:FRAG_BUF_DEPTH-1]; // sender-declared total-1
```

**동작**:
1. Wave token 도착 → tag 기준으로 slot 할당 (LRU 또는 wave_number hash).
2. `frag_hdr[7:4]` index 위치에 payload 저장.
3. `frag_mask` 해당 bit set.
4. `frag_mask == (1 << (frag_total+1)) - 1` 시 완결 → downstream PE_Core 로 wide payload assemble 후 전달.
5. Slot 회수.

**버퍼 크기**: FRAG_BUF_DEPTH=8 (동시 활성 wave 8개), 슬롯당 16 × 64 = 1024 bit → 8 KB / Cluster. ULX3S BRAM 여유 안에서 소화 가능.

## 8. Out-of-order arrival 처리

IP fragmentation 처럼 fragment 도착 순서 무관. `frag_hdr[7:4]` 로 재정렬. Wave-parallel dataflow 에서는 fragment 가 NoC 상 여러 경로를 통해 out-of-order 도착 가능성 있음 — 이 스펙으로 자동 처리.

## 9. Retransmission / drop 처리 (미도입)

IP fragmentation 은 fragment 하나 drop 시 timeout + entire datagram drop. WaveTensor 는 **lossless NoC 가정** (내부 fabric 이므로) → drop 처리 로직 없음. Future: timeout 카운터로 stuck slot 감지 후 error 발생.

## 10. Assembler 관점: 완전 abstract

Fragmentation 은 **RTL 층위 인프라**이지 어셈블러 코드에 노출 안 됨. 어셈블러는 여전히 "한 명령어 = 한 논리 output" 관점으로 emit — RTL 이 wide 결과일 때 자동으로 여러 fragment 로 쪼갬. IPv6 도 응용 계층은 fragmentation 을 보지 않음.

## 11. v1.5 초기 랜딩 스코프 (2026-07-14 완료)

- `PE_Core.v` 에 `output_frag_hdr[7:0]` output port 신설, 기본값 `8'h00`.
- `ISA_Decoder.v` / `PE.v` / `Cluster.v` / `Pod.v` / `Top_Core.v` 에 배선 전파.
- 회귀: 149 tests + 신규 2 tests (test_frag_hdr_default_zero_alu / _einsum) = 154 PASS.
- **미포함**: fragment 발행 primitive, fabric 재조립, wide-input consumer.

## 12. v1.6+ 로드맵 요약

| 단계 | 스코프 | 예상 LUT 비용 |
|---|---|---|
| v1.5.1 | Fabric fragment buffer + reassembly (Cluster) | +2K LUT + 8Kbit BRAM/Cluster |
| v1.5.2 | PE_Core wide-input consumer (128-bit dec_input_payload_wide) | +500 LUT |
| v1.5.3 | Wide-output primitive: SIG_BMM_3 실행 (multi-fragment emit) | +3K LUT (matmul_2x2 확장) |
| v1.5.4 | Assembler multi-IMM64 emit 자동화 (5+ axes einsum 감지 시) | Python only |
| v1.5.5 | Multi-fragment SIG_TRACE_IIJKL 등 reduction primitive | +1K LUT each |

## 13. 원리 요약

v1.5 는 **spec 층위 재정의** 를 v1.3 (sentinel-terminated chain) 과 동일한 방식으로 반복:

| 항목 | 재정의 전 | 재정의 후 |
|---|---|---|
| MAX_EH | Spec 상한 | 하드웨어 sizing hint (v1.3) |
| Wave token payload width | Fixed 64-bit 논리 상한 | Physical transport 단위 — 논리 payload 는 fragmentation 으로 임의 확장 (v1.5) |

두 재정의 모두 사용자의 상위 레이어 (OSI / C 문자열) 관점에서 발안됨. 하드코딩된 상수를 spec 층위에서 재해석 → 하드웨어 최소 변경으로 큰 유연성.

## 14. 후속 memo 후보

- `.claude-memos/fragment_buffer_sizing.md` — 실측 fragment buffer 요구량 분석 (workload profile 기반).
- `.claude-memos/wave_ordering_semantics.md` — fragment out-of-order arrival 시 wave 순서 보장 방식.
