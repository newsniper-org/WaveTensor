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

## 11a. v1.5.1 landing (2026-07-14 완료) — Fabric fragment reassembly

**Cluster.v 진입 single-slot fragment buffer** (§7-8 설계 실현):
- `ext_frag_hdr[7:0]` input port 신설 (Cluster + Pod)
- 16-slot `frag_data[16]` × 64-bit = 1024-bit wide payload 저장 가능
- 상태 register: `frag_mask[15:0]`, `frag_total_m1[3:0]`, `frag_tag_reg[79:0]`, `frag_active`
- 완결 pulse: `frag_reass_valid` (조합) + `frag_reass_wide[1023:0]` (조합)
- Legacy 단일-fragment (frag_hdr=0x00) 완전 bypass

**회귀**: 158 cocotb + 66 assembler = 224 tests PASS. 신규 4 tests:
- `test_frag_buffer_single_fragment_bypasses`
- `test_frag_buffer_two_fragments_assemble`
- `test_frag_buffer_out_of_order_arrival` (§8 IPv6 준수)
- `test_frag_buffer_four_fragments_assemble`

**하드웨어 비용**: ~1.5-2K LUT + 1K FF / Cluster (LFE5U-85F 추정).

**한계 (v1.5.1b/c 로 이월)**:
- Single-slot: 동시 활성 multi-fragment wave 1개
- Downstream 미연결 — `frag_reass_wide` 는 Cluster-internal (v1.5.2 에서 EHDecode 스레딩)

## 11b. v1.5.2 landing (2026-07-15 완료) — EHDecode 스레딩 + wave-complete gating

**EHDecode 인터페이스 확장** (§7 시나리오 A 실현):
- 신규 파라미터: `FRAG_MAX = 16`, `WIDE_W = 1024`
- 신규 입력: `input_payload_wide[1023:0]` + `input_payload_wide_valid`
- 신규 latch: `payload_wide_latched` + `payload_wide_valid_latched`
- 신규 출력: `dec_input_payload_wide[1023:0]` + `_valid` (registered, `done_d1` 에 update)

**Cluster wave-complete gating**:
```verilog
wire wave_complete = ext_valid
                   && ((ext_frag_hdr == 8'h00) || frag_reass_valid);
```
- Legacy 단일-fragment: 즉시 트리거 (완전 backward compat)
- Multi-fragment 중간: EHDecode idle, buffer 만 축적
- Multi-fragment 마지막: 재조립 완료 후 EHDecode 트리거

**Payload mux**: `(ext_frag_hdr == 0x00) ? ext_payload : frag_reass_wide[63:0]` — legacy consumers 는 low slot 을 정상 소비.

**상류 tie-off**: PE.v / Top_Core.v 는 wide input 을 `1024'h0` + `1'b0` 로 hardwire. Pod.v 는 무영향 (재조립은 Cluster 각자).

**회귀**: 165 cocotb + 66 assembler = 231 tests PASS. 신규 4 tests:
- `test_wide_payload_latches_when_valid` (ISA_Decoder)
- `test_wide_payload_zero_when_invalid` (ISA_Decoder)
- `test_wave_complete_gates_intermediate_fragments` (Cluster)
- `test_fragment_completion_feeds_ehdecode_wide` (Cluster)

**하드웨어 비용**: ~2K FF + 200 LUT / Cluster (payload_wide_latched + dec_input_payload_wide register + mux).

**한계 (v1.5.3 로 이월)**:
- PE_Core 는 wide input 아직 미소비 — `dec_input_payload_wide` 는 hierarchical 접근만
- 실제 wide-consumer primitive (SIG_BMM_3 등) 실행은 v1.5.3

## 11c. v1.5.2b landing (2026-07-15 완료) — PE_Core wide input port

v1.5.2 는 Cluster-internal wire 까지만. v1.5.2b 는 **PE_Core 안까지** 배선 완비 → v1.5.3 dispatch 계층 landing zone 완성.

**변경 요약**:
- PE_Core.v: `dec_input_payload_wide[1023:0]` + `_valid` input port 추가 (legacy 미참조, lint UNUSED 처리)
- ISA_Decoder.v: `dec_input_payload_wide` 를 internal wire 로 승격, EHDecode → PE_Core 배선, top-level output 미러
- Cluster.v: 4개 PE_Core-family instance (L-PE gen + MU + DU) 에 wide 배선
- PE.v / Top_Core.v: ISA_Decoder 의 wide input 을 0 으로 tie-off (fabric 없음)

**회귀**: **231 PASS 유지** — 신규 회귀 없음. Legacy backward compat 검증.

**HW 비용**: ~50 LUT (wire fan-out). 실제 사용 시점은 v1.5.3.

## 12. v1.6+ 로드맵 요약

| 단계 | 스코프 | 예상 LUT 비용 | 상태 |
|---|---|---|---|
| v1.5.1 | Fabric fragment buffer + reassembly (Cluster) | +1.5-2K LUT + 1K FF/Cluster | **완료 (2026-07-14)** |
| v1.5.1b | Multi-slot buffer (N-slot LRU) | +8-16K LUT + 8Kbit BRAM | 대기 |
| v1.5.2 | EHDecode `dec_input_payload_wide` + Cluster threading + wave_complete gate | +2K FF + 200 LUT / Cluster | **완료 (2026-07-15)** |
| v1.5.2b | PE_Core wide input port (dispatch layer 준비) | +50 LUT | **완료 (2026-07-15)** |
| v1.5.3 | Wide-output primitive: SIG_BMM_3 실행 (multi-fragment emit) | +3K LUT (matmul_2x2 확장) | 대기 |
| v1.5.4 | Assembler multi-IMM64 emit 자동화 (5+ axes einsum 감지 시) | Python only | 대기 |
| v1.5.5 | Multi-fragment SIG_TRACE_IIJKL 등 reduction primitive | +1K LUT each | 대기 |

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
