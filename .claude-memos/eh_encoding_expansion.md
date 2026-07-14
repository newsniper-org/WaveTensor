<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# WT64v1 EH 인코딩 확장 조사 — MAX_EH 완화 / 해제

작성일: 2026-07-14
상태: **v1.3 amendment 로 랜딩** (2026-07-14). 사용자 후속 지시로 "C-string sentinel" 접근이 채택되어 §11 로 실행 요약 추가.

원래 설계 조사 (2026-07-14): 사용자 지시 "EH 최대 갯수 제한을 완화하거나 해제할 방법도 모색"

> **연관 메모**: [`wt64v1_spec.md`](./wt64v1_spec.md) §15.8 (남은 raise: 3+ batch dims 는 EH 인코딩 상한 원인). [`einsum_trace_broadcast_analysis.md`](./einsum_trace_broadcast_analysis.md).

## 1. 현재 상한 근거

**WT64v1 (v1.0~v1.2) 명령어 최대 크기**: `32 + MAX_EH × 96 = 32 + 4×96 = 416 bit`.

`MAX_EH = 4` 상한의 근원 (2026-05-03 v1.0 lock 시점):
1. **`bh_len` 8-bit field 상한**: 최대 256 워드 (8192 bits) — MAX_EH 상 이론적 제약 아님.
2. **`stg_off` 4-bit register (`EHDecode.v` line 146)**: 슬롯 오프셋 최대 15 워드. 실질적 상한 = `1 + MAX_EH × 3 ≤ 16` → **MAX_EH ≤ 5**.
3. **`stg_index` 3-bit register (`EHDecode.v` line 148)**: 슬롯 인덱스 최대 7. **MAX_EH ≤ 8**.
4. **`INSTR_WIDTH` 파라미터화**: `Pod.v` / `Cluster.v` / `Top_Core.v` 모두 `parameter INSTR_WIDTH = 32 + MAX_EH*96` — 자동 스케일.
5. **`stg_expect` 등 EH 타입 필드 (4-bit)**: 타입 개수 상한 (16) 과 무관. MAX_EH 무관.

**실제 blocker**: `stg_off` 의 4-bit 폭 (5 → 확장 시 재컴파일 시 넓혀야 함). 다른 슬롯 관련 상태 register 폭도 확인 필요.

## 2. 확장 옵션 3가지

### 옵션 A — parameter override (compile-time)

`MAX_EH` 를 4 → N 으로 elaboration-time override. 이미 파라미터화되어 있음.

**필요 변경**:
1. `EHDecode.v` line 146: `stg_off` reg `[3:0]` → `[log2(1+MAX_EH*3):0]` 로 자동 스케일 (매크로 계산 또는 hard-code 최대 지원 N).
2. Chain walk pipeline: 한 슬롯당 1 cycle → 총 MAX_EH cycle 로 자동 스케일 (기존 코드 그대로).
3. Bus routing (fabric): INSTR_WIDTH 증가 → cluster/pod 간 routing wire 증가.

**HW 비용**:
- LUT: chain walk pipeline 자체는 slot 당 constant. MAX_EH=8 시 pipeline register 8 세트 (~4× 증가). 대략 +2K LUT/Pod.
- Instruction bus routing: MAX_EH=8 시 800-bit → 각 PE 로 broadcast. 라우팅 fabric 증가 (~10-15% LUT).
- Latency: MAX_EH cycle 로 대기 → wave-parallel dataflow 에 자연스러움.

**장점**:
- 파라미터만 변경, 논리적 재설계 없음.
- Backward-compatible: MAX_EH=4 인스턴스는 그대로.

**단점**:
- 소프트웨어 (assembler) 는 elaboration 별로 다른 MAX_EH 를 알아야 함.
- Global 설정이라 mixed-MAX_EH 시스템은 불가.

### 옵션 B — EH 인코딩 자체 확장 (subscript body 96-bit → 128-bit 등)

Subscript EH 를 예로: 현재 body 48-bit = 4 axes × 12-bit. 확장 시:
- `SUBSCRIPT_v2` 새 EH 타입 (예: 0x9) — body 6 axes × 12-bit = 72-bit.
- 5+ axes einsum 표현 가능.

**필요 변경**:
1. `EHDecode.v` EH type table 확장 (0x9 등록).
2. `SUBSCRIPT_v2` body 파싱 로직 (기존 subscript 함수 확장).
3. `ISA_Decoder.v` / `PE_Core.v` 의 subscript 사용 코드 6-axis 지원.
4. Assembler 신규 subscript 인코딩 지원.

**HW 비용**:
- SUBSCRIPT parsing: 기존 48-bit → 72-bit register + parsing logic. ~500 LUT/Pod.
- EINSUM signature 확장 (5+ axes = 60+ bit): PE_Core dispatch case 확장.

**장점**:
- MAX_EH 은 변경 없음 (여전히 4). Bus width 증가 없음.
- 파이프라인 지연 증가 없음.

**단점**:
- 여러 EH 종류의 body 를 개별 확장해야 함.
- SUBSCRIPT_v2 는 opcode 별로 다른 legality 판단 필요 (v1 EINSUM 은 v1 subscript, v2 EINSUM 은 v2 subscript).
- **결과적으로 새 opcode 그룹 도입과 동등한 복잡도**.

### 옵션 C — 새 인코딩 방식 (indirect / RAM-backed subscript)

EH 안에 pointer 를 두고 실제 subscript 를 별도 위치 (예: instruction cache 확장 영역) 에서 참조.

**아이디어**:
- SUBSCRIPT EH body 를 pointer (16-bit index) 로 표현.
- Instruction stream 뒷단에 확장 subscript 테이블.
- Runtime 시 pointer 로 참조.

**단점**:
- Instruction cache 확장 필요 (별도 SRAM/BRAM).
- Wave-parallel 모델과 이질적 (fetch 후 재fetch 필요).
- **WT64v1 의 self-contained instruction 원칙 위반**. → **비권장**.

## 3. 3+ batch dims 케이스에 대한 각 옵션 적용

목표: `abcij,abcjk->abcik` (3 batch dims) 를 close.

- **A axes = 5개** (a, b, c, i, j) → 현재 subscript body (4 axes × 12-bit = 48-bit) 초과.
- **필요**: subscript body 를 5+ axes 로 확장 OR 명령어 여러 개로 unroll.

| 옵션 | 3+ batch dims close? | 구현 부담 |
|---|---|---|
| A (MAX_EH↑) | ❌ subscript body 인코딩 자체가 4 axes 상한 | MAX_EH 확장은 부수 이득 (더 큰 imm/subscript 여러 개) |
| B (SUBSCRIPT_v2) | ✅ 직접 target — 5+ axes 인코딩 지원 | 중간 (~2K LUT + assembler + testset) |
| C (indirect) | ✅ 이론상 | 큼 (fetch 재설계) — 비권장 |

**단독 최적**: **옵션 B (SUBSCRIPT_v2)**.

**조합 최적**: **A + B** — MAX_EH↑ (미래 명령어 인코딩 여유) + SUBSCRIPT_v2 (5+ axes 지원). 
- MAX_EH 를 4 → 6 으로 확장 (여유 조금).
- SUBSCRIPT_v2 도입 (5+ axes 인코딩).
- v1.3 amendment 로 통합.

## 4. v1.3 amendment 제안 (계획 안, 미승인)

### 4.1 MAX_EH: 4 → 6

- `Pod.v` / `Cluster.v` / `Top_Core.v` `MAX_EH = 6` 파라미터 override.
- `EHDecode.v` `stg_off` 확장: `[3:0]` → `[4:0]` (32 워드까지 표현).
- Bus routing 폭 증가: INSTR_WIDTH 416 → 608 bit (+192).
- Latency: 4 cycle → 6 cycle chain walk (dataflow 흡수 가능).
- 예상 LUT 증가: +5-8K / Pod.

### 4.2 새 EH type `SUBSCRIPT_v2` (0x9)

- Body: 6 axes × 12-bit = 72-bit (body 크기 → 3 words).
- 각 axis 4-bit code 표현 (기존 subscript 와 동일 label 공간).
- 사용 시 legality: EINSUM_v2 (새 opcode?) 또는 EINSUM (기존 0x32) 가 SUBSCRIPT_v2 도 accept.

### 4.3 새 EINSUM signatures (5+ axes)

`SIG_BMM_3` — 'abcij,abcjk->abcik' at int4:
- 3 batch dims (a, b, c) × 2×2 matmul (i,j,k contract j)
- 총 A elements: 2^5 = 32 int4 = 128 bit — **여전히 payload (64-bit) 초과**.

Hmm. int4 도 5-axis 4D+ 에서 payload 초과. 

**추가 옵션**: shape 축소 — 예: batch 축은 size 2 만, i/j/k 는 size 1. 즉 `abc,abc->abc` 스칼라 batched. 실용성 낮음.

**결론**: 3+ batch dims 의 general case 는 **payload 확장 없이 불가**. MAX_EH 확장은 opcode 인코딩 유연성만 얻고, 실행 자체는 int4-payload 상한이 blocker.

## 5. Payload 크기 확장 (v2 candidate)

Wave payload 를 64-bit → 128-bit 로 확장 시:
- int4 packed 32 nibbles → 5-axis 4D+ 지원 가능.
- 하지만 이는 **base ISA breaking change** (payload 필드 모든 곳 재정의).
- WT64v1 에서 **WT128v1** 또는 **WT64v2** 로 분기 필요.

**결정**: 이는 **v2 스코프**. v1.x 안에서는 불가.

## 6. 실질적 v1.3 amendment 스코프

3+ batch dims 를 base ISA 로 close 하는 것은 **v1.x 스코프 밖**. 다음 3가지 옵션:

**옵션 I**: **v1.3 = MAX_EH 확장 + SUBSCRIPT_v2 도입** (3+ axes 표현만 지원, execution 은 payload 상한 준수).
- 인코딩 유연성 향상 (예: 명령어 안에 더 많은 immediate 인수)
- 3+ batch dims 는 여전히 payload 상한으로 raise
- 실질 이득: assembler side 의 명확한 error message + 향후 다양한 EH types 진입 여지

**옵션 II**: **v1.3 을 만들지 않고 v2 (payload 128-bit)** 로 직행.
- 큰 breaking change
- 여러 라운드의 spec / RTL 리팩터링
- Camera target ILC 스케일에는 payload 128 이 유리 (int8 8 elements → 16 elements)

**옵션 III**: **현 상태 (v1.2) 유지 + 3+ batch dims 는 프로그램 수준에서 unroll**.
- 사용자가 `abcij,abcjk->abcik` 대신 명시적 loop 로 여러 개 SIG_BMM_2 를 발사
- Compiler / 프로그래머 몫
- ISA 변경 없음

## 7. 권장 진로

**단기 (즉시)**: **옵션 III** — 현 v1.2 유지. 3+ batch dims 는 프로그램 수준 unroll 로 처리.

**중기 (수개월)**: **옵션 I** — v1.3 amendment (MAX_EH ↑ + SUBSCRIPT_v2). 실행 스코프는 확장 X, 인코딩 유연성만.

**장기 (수년)**: **옵션 II** — v2 (payload 128-bit) 검토. 카메라 target 상용화 시점 실측 데이터 기반.

## 8. 3+ batch dims assembler-side 갱신 계획 (옵션 III 준수)

현재 `_lower_einsum_general` 은 5+ axes 를 `_pack_axes` 에서 raise (line 1094-1096):
```python
def _pack_axes(codes: List[int]) -> int:
    if len(codes) > 4:
        raise AssemblerError(f"at most 4 subscript axes per group, got {codes}")
```

3+ batch dims 시 에러 메시지를 명확히 갱신:
- "5+ axes einsum requires WT64v1 v1.3 (SUBSCRIPT_v2). See `eh_encoding_expansion.md` §7."

이는 어셈블러만 갱신 (소소한 문구 개선).

## 9. 결론

- **MAX_EH=4 상한 완화는 이론상 옵션 A/B 조합으로 가능** — v1.3 amendment 후보.
- 그러나 **3+ batch dims general case 는 payload 상한 (64-bit) 이 근본 blocker** — v2 스코프.
- v1.3 amendment 는 **인코딩 유연성** 확보용 (미래 확장 여지) 이지 3+ batch dims 실행 지원은 아님.
- 실무적 조언: **v1.2 로 우선 안정화**, 3+ batch dims 는 프로그램 수준 unroll 로 처리, v1.3 는 별도 세션에서 필요 시 착수.

## 10. 후속 작업 후보

- `wt64v1_spec.md` §15.8 갱신 — 3+ batch dims 관련 assembler error message 개선 정책 명시.
- `wt64v1_spec.md` §16 신설 (v1.3 amendment) — MAX_EH ↑ + SUBSCRIPT_v2 스펙 상세 (사용자 승인 시).
- Or: 본 memo 로만 유지 (구현 지연).

## 11. 실제 랜딩 (v1.3 amendment, 2026-07-14) — sentinel 방식 채택

사용자 후속 통찰 (2026-07-14): "EH 자체의 크기는 고정이니까, 특정 비트(들)의 값이 미리 정의된 terminal 상수인 EH가 나올때까지 갯수 제한없이 받아들이도록 하는 것은 어떨까? 마치, 문자열의 끝은 항상 `'\0'`이어야 한다는 C언어의 규칙처럼 말이지."

이 관점이 **SUBSCRIPT_v2 body 확장 (옵션 B) 보다 훨씬 우아**함이 확인됨:

- Base ISA 는 이미 sentinel (`EH_END = 0x0`) 를 `next_hdr` 필드에 사용 중.
- `EHDecode.v:340` 의 `stg_index == 3'd3` 하드코드가 그 원리를 무효화하고 있었음.
- 이 하드코드를 파라메트릭 (`stg_index == MAX_EH-1`) 로 대체하면 **MAX_EH 는 인코딩 spec 제약이 아니라 hardware sizing hint** 가 됨.

### 11.1 v1.3 실제 랜딩 스코프 (`wt64v1_spec.md` §16 참조)

- Chain-walk state 파라메트릭 (`$clog2`) — MAX_EH 임의 override 가능
- `MAX_EH = 4` default 유지 → 완전 backward-compat (기존 145 cocotb + 65 assembler 회귀 통과)
- Multi-SUBSCRIPT accumulation (`acc_subscript` 48→96 bit) — 두 SUBSCRIPT EH concatenate → 8 axes 지원
- 신규 output: `dec_eff_subscript_hi` (48-bit, 둘째 SUBSCRIPT body)
- Assembler `_pack_axes_multi` + `_encode_subscript_eh_multi` → 5+ axes 자동 emit
- `HW_DIRECT_EINSUM_SIGS_MULTI` (6-tuple) — SIG_BMM_3_CANDIDATE / SIG_TRACE_IIJKL_CANDIDATE 등록

### 11.2 남은 blocker (v2 scope 유지)

- **3+ batch dims 실행**: multi-SUBSCRIPT 로 인코딩 성공 후 RTL 에서 `lower_required` (매칭 primitive 없음). 근본 원인은 payload 64-bit 상한.
- **원래 §5-7 분석 결론 재확인**: payload 128-bit (v2) 없이는 실행 지원 불가.

### 11.3 옵션 A/B/C 재평가

원래 §2 의 옵션들과 v1.3 실제 채택 비교:

| 옵션 | 원래 평가 | v1.3 실제 |
|---|---|---|
| A (MAX_EH↑) | +5-8K LUT | 랜딩 (default 4 유지, override 가능한 파라메트릭화 만) |
| B (SUBSCRIPT_v2 body↑) | +2K LUT | **폐기** — sentinel + multi-SUBSCRIPT 방식이 우수 |
| C (indirect) | 비권장 | 유지 (비권장) |
| **D (sentinel — user 발안)** | 언급 없었음 | **채택** — spec/RTL 둘 다 간결 |

### 11.4 학습 포인트

원래 조사 (§2-7) 는 "고정된 개별 EH body 를 확장" 방향으로만 사고. 사용자 발안은 "**EH chain 자체의 길이 제약 개념을 spec 에서 제거**" 하는 상위 원리적 접근. 결과적으로 훨씬 적은 RTL 변경 (`stg_index` 하드코드 1줄) 으로 훨씬 큰 유연성 확보.

일반 원칙: 실제 blocker 를 spec 층위에서 재정의하는 방향이 code 변경보다 우아할 때가 많음.
