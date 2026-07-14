<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# EINSUM Trace / Broadcast lowering — 실현 가능성 분석 + WT64v1-C 확장 제안

작성일: 2026-07-14
상태: 진행 (부분 lowering 어셈블러 반영 완료, HW-side 확장은 WT64v1-C 후보 논의)

> **연관 메모**: [`wt64v1_spec.md`](./wt64v1_spec.md) — 확정 base ISA (v1.0 locked). [`wt64v1c_extension_plan.md`](./wt64v1c_extension_plan.md) — WT64v1-C 확장 plan-only. `claude.md §7` — 잔여 TODO 목록.

## 1. 배경 — §7 #3 의 실제 어려움

`claude.md §7` 의 잔여 TODO 항목 3번:
> 임의 EINSUM lowering의 trace/broadcast 케이스 지원 (현재 matmul-style만).

이 항목은 **얼핏 간단해 보이지만, 실제로는 대부분의 케이스가 WT64v1 base ISA 로는 close 할 수 없음** 을 이 메모에서 분명히 한다.

### 1.1 현재 지원 상태 (2026-07-14)

**HW-direct kernels (RTL 에서 1-cycle 실행 가능)**:
```
SIG_SUM_I       'i->'          (unary)
SIG_TRACE_II    'ii->'         (unary)
SIG_TRANSPOSE   'ij->ji'       (unary)
SIG_MATMUL      'ij,jk->ik'    (binary)
SIG_HADAMARD    'ij,ij->ij'    (binary)
SIG_OUTER       'i,j->ij'      (binary)
SIG_PARTIAL_IJK 'ijk->ij'      (unary)
SIG_DIAGONAL    'ii->i'        (unary)
SIG_DOT         'i,i->'        (binary)
SIG_MAT_VEC     'ij,j->i'      (binary)
```

**Assembler macro lowering (`_lower_einsum_general`)**:
일반 `A,B->O` 의 matmul-style 패턴을 `PERM_A → VIEW_A → PERM_B → VIEW_B → EINSUM(SIG_MATMUL) → VIEW_R → PERM_R` 로 분해.

**작동 조건**:
- A / B 에 duplicate label 없음
- A ∩ B ∩ O 없음 (batched 없음)
- O ⊆ A ∪ B (broadcast 없음)

## 2. 4가지 unsupported 패턴 별 lowering 가능성

### 2.1 Trace-in-A (A 에 duplicate label)

**예시**: `iij->j`, `iikl->kl`, `iikkl->kl` 등.

**원하는 semantic**: `result[..., x, ...] = sum_i A[i, i, ..., x, ...]`

**HW-direct 로 축소 시도**:
- `ii->` (SIG_TRACE_II) 는 순수 2D input 만 처리 (다른 axis 없음).
- `ii->i` (SIG_DIAGONAL) 는 diagonal 추출 후 i 유지 — trace 아님.
- **결과**: `iij->j` 같이 kept axis (j) 가 있는 trace 는 축소 불가.

**Assembler-side unroll 대안**:
- shape[j] 가 compile-time 상수 (≤4) 이면 j 값별로 TRACE_II 를 반복 실행.
- 예: `iij->j` with shape[i]=2, shape[j]=2:
  - `result[0] = A[0,0,0] + A[1,1,0]`
  - `result[1] = A[0,0,1] + A[1,1,1]`
- **하지만**: WT64v1 의 64-bit payload 는 8×int16 packed 이라 j 별 slice 를 추출하려면 shift+mask 이 필요. Bit-level manipulation 은 WT64v1 에 없음. **불가**.

**HW 확장 필요**: WT64v1-C 후보 `SIG_TRACE_IIJ` — 3D input 에 대해 첫 두 axis 를 trace, 셋째 axis (j) 유지. Payload 반환 layout 은 j 축 packed 그대로.

### 2.2 Trace-in-B (B 에 duplicate label)

`iij` 는 A 든 B 든 동일 문제. 대칭적으로 처리.

### 2.3 Broadcast (O 에 label 이 A/B 어디에도 없음)

**예시**: `i->ij` (i 로부터 [i,j] 생성), `ij->ijk` 등.

**원하는 semantic**: `result[..., x, ...] = A[...]` 를 broadcast dim 을 따라 복제.

**HW-direct 로 축소 시도**:
- BCAST (opcode 0x24) 는 RTL 에서 `lower_required = 1` 만 설정 (PE-local 실행 X). Assembler 가 lowering 해야 함.
- OUTER (`i,j->ij`) 는 두 벡터의 outer product — broadcast 도 유사하게 표현 가능한가?
  - `result[i,j] = A[i] * [1] * ... * [1]` (j size 만큼 1's 벡터와 outer product)
  - **필요조건**: constant `[1, 1, ..., 1]` vector 를 runtime 에 만들 수 있어야 함.
  - **WT64v1 에는 없음**: ZERO (0x0), ONE (0x1) 상수 있음 (single value). 벡터는 없음.

**부분 지원 (구현 완료 2026-07-14)** — size-1 broadcast:
- shape[bcast_label] == 1 이면 UNSQUEEZE (metadata-only, 0x21) 로 처리 가능.
- 예: `A=i B=j O=i,j,q` with shape[q]=1: MATMUL(i,j → ij) 후 USQZ pos=2 → [i,j,q] with q size 1.
- 실제로 사용되는 케이스: pipeline chain 에서 size-1 placeholder axis 명시 유지 시.

**HW 확장 필요 (size>1 broadcast 지원)**: WT64v1-C 후보 `SPLAT` 오퍼레이션 — scalar 를 지정된 shape 로 전개하여 constant vector 생성. 또는 `SIG_BCAST_XY` 계 EINSUM signature 여러 개 추가.

### 2.4 Mixed (batched) — A ∩ B ∩ O

**예시**: `ijk,ijl->ijkl` (batched matmul, batch dims i,j), `bik,bkj->bij` (batch 단일 축 b).

**원하는 semantic**: batch dims 를 따라 여러 matmul 을 병렬 실행.

**HW-direct 로 축소 시도**:
- MATMUL 은 순수 2D 만. Batch 축이 있는 3D+ 입력은 지원 안 함.
- Assembler unroll: batch 축의 각 인덱스별로 MATMUL 을 emit. shape[batch] 개 명령어 생성.
  - 예: `bik,bkj->bij` with shape[b]=2: MATMUL(A[0,:,:], B[0,:,:]) → result[0]; MATMUL(A[1,:,:], B[1,:,:]) → result[1]; 그 후 결과 concat.
- **문제**: A[0,:,:] 를 payload 에서 추출하려면 shift+mask 필요 (없음). 결과 concat 도 마찬가지.

**HW 확장 필요**: WT64v1-C 후보 `SIG_BMM` (batched matmul, 3D×3D→3D), 또는 batched-op prefix (전 unary/binary 를 batched 로 실행).

## 3. 결론 — 실제로 close 할 수 있는 것

| 항목 | Assembler-side 만으로 close? |
|---|---|
| Size-1 broadcast (trivial) | ✅ **완료 (2026-07-14)** — USQZ (0x21) chain |
| Trace-in-A / Trace-in-B | ❌ **불가**. WT64v1-C 확장 필요 (`SIG_TRACE_IIJ` 등) |
| Size>1 broadcast | ❌ **불가**. WT64v1-C 확장 필요 (`SPLAT` 또는 `SIG_BCAST_*`) |
| Mixed (batched) | ❌ **불가**. WT64v1-C 확장 필요 (`SIG_BMM` 등) |

즉 `claude.md §7 #3` "임의 EINSUM lowering" 은 **base ISA 의 완전한 lowering 은 불가능**이며, 그 중 실현 가능한 부분 (size-1 broadcast) 만 2026-07-14 어셈블러에 landing. 나머지는 **HW 확장 명세 (`WT64v1-C`) 결정 후에 close** 가능.

## 4. WT64v1-C 확장 후보 (분산 lowering close 용)

기존 `wt64v1c_extension_plan.md` 에 crypto + bit-permute 가 담긴 상태. EINSUM 확장을 추가 후보로 고려:

### 4.1 `SIG_TRACE_IIJ` — 3D trace with kept axis
- Semantic: `result[j] = sum_i A[i, i, j]` for shape[i], shape[j] each ≤4.
- 어셈블러 signature 매핑: `iij->j`.
- HW 구현: 기존 TRACE_II 를 j slice 별로 반복 (내부 배치화).

### 4.2 `SPLAT k` — scalar broadcast
- Semantic: 1-cycle 에 payload 를 constant [x, x, ..., x] 로 전개 (shape[k] copies).
- HW 구현: MUX broadcast, LUT 소모 작음.
- 이후 OUTER 등과 조합해 size>1 broadcast 지원 가능.

### 4.3 `SIG_BMM` — batched matmul
- Semantic: `result[b, i, k] = sum_j A[b, i, j] * B[b, j, k]` for shape[b]≤2.
- HW 구현: 기존 MATMUL_UNIT 을 batch 축으로 loop (2 cycles per batch).

### 4.4 우선순위 (실측 데이터 기반)

Camera target (ILC) 워크로드에서 어떤 패턴이 가장 자주 등장하는지 실측 후 우선순위 결정. 잠정:
1. **`SPLAT`** — 가장 general 도구, 구현 저비용, 다른 lowering 에도 쓸모.
2. **`SIG_BMM`** — 카메라의 batch 처리 (multi-frame denoise) 에 필수.
3. **`SIG_TRACE_IIJ`** — 상대적 우선순위 낮음, 실제로 얼마나 쓰이는지 검증 후.

## 5. 어셈블러 사용자에게 안내되는 에러 메시지

2026-07-14 반영된 에러 메시지 (Python `asm/wavetensor_asm.py` 의 `_lower_einsum_general`):

- Trace-in-A: "not lowerable by macro_pass — WT64v1 provides HW-direct 'ii->' (SIG_TRACE_II) and 'ii->i' (SIG_DIAGONAL) but no batched trace over additional kept axes. See `.claude-memos/einsum_trace_broadcast_analysis.md`."
- Trace-in-B: "not lowerable by macro_pass — same reason as trace-in-A."
- Mixed batched: "labels {...} appear in A, B, and O simultaneously (batched contraction) — WT64v1 has no batched-matmul primitive. Rewrite as a sequence of per-batch matmuls or await WT64v1-C extension."
- Non-trivial broadcast: "broadcast labels {...} have sizes {...} — only size-1 broadcast is lowerable via UNSQUEEZE (WT64v1 has no constant-vector splat primitive). Add `.shape X=1` to indicate the axis is a placeholder, or await WT64v1-C extension."

각 메시지가 본 메모를 가리키도록 되어있어 사용자가 상세 컨텍스트 확인 가능.

## 6. 관련 커밋 및 회귀

- 2026-07-14 커밋 (예정): 어셈블러 `_lower_einsum_general` 확장 + 4개 신규 테스트 (`test_broadcast_size_1_lowers_via_unsqueeze`, `test_broadcast_size_1_in_middle_of_O`, `test_broadcast_in_o_size_gt_1_raises`, `test_mixed_batched_raises_with_hint`).
- Assembler 회귀: 61/61 PASS (58 기존 + 3 신규 통과).
- Cocotb 회귀: 무관 (RTL 변경 없음).

## 7. 후속 작업

- (선택) HW-direct `SPLAT` primitive 실증 — LUT 소모 예측 후 WT64v1-C 진입 결정.
- (지연) `SIG_TRACE_IIJ` / `SIG_BMM` — camera target 실측 후 우선순위 확정.
- (연관) `wt64v1c_extension_plan.md` 갱신 시 본 메모의 §4 옵션들을 카탈로그에 추가 검토.

## 8. 진솔한 §7 갱신 제안

`claude.md §7 #3` 을 다음처럼 refine:

> **~~임의 EINSUM lowering의 trace/broadcast 케이스 지원~~** → **EINSUM lowering 확장 — size-1 broadcast 완료 (2026-07-14); trace / size>1 broadcast / batched matmul 은 base ISA 로는 불가, WT64v1-C 진입 시 (`einsum_trace_broadcast_analysis.md` §4) 재검토**.
