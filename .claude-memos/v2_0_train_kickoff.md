<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# v2.0 "TRAIN" kickoff memo — 설계 입력 · 계약 초안 · 검증 계획

작성일: 2026-08-15
상태: **plan-only** — RTL 없음, spec 편집 없음. 본 메모는 v2.0 의 **COMMIT 0 (spec 선행) 에 들어갈 원료**이지 규범 문서가 아니다. 규범이 되는 시점은 §23.x 하위 절로 전사(transcribe)될 때이며, 그 전까지 본 문서의 어떤 문장도 계약이 아니다.
상태 갱신 (2026-08-15, 같은 날 후속): **v2.0 COMMIT 0 이 spec §27 (신규 top-level 절) 로 착지** — 누산 아키텍처는 사용자 결정으로 **옵션 3 (wave-step-atomic accumulation)** 채택, 본 메모의 G6 (§6.4/§7 항 1) 종결. 본 메모의 해당 절들은 in-place RESOLVED 표기로 갱신됐고, 미결로 남긴 나머지 (G7 ownership, bank selector arity, drain opcode, SR 시드 등) 는 여전히 열려 있다.
전제 commit: `0249536` (xcu55c 실측 기준선 채택) 시점

> **연관 메모**
> - [`cross_vendor_fabric_evidence.md`](./cross_vendor_fabric_evidence.md) — 2026-08-13 실측. §5 의 risk register 재작성이 전적으로 이 문서에 의존한다.
> - [`../scripts/acc_format_study.py`](../scripts/acc_format_study.py) + [`../include/generated/acc_format_study_report.json`](../include/generated/acc_format_study_report.json) — **§27 결정의 재현 artifact** (2026-08-15): 누산 포맷 설계 조사 전 실험의 고정-seed 재생성 (stdlib-only, 재실행 byte-identical). §1.2 C3 판정·"(A) 6회" 정정·소거 근거 수치의 normative 출처.
> - [`wt64v1_spec.md`](./wt64v1_spec.md) §23 (roadmap 원문), §23.6a (mode-byte legality 표), §23.7 (residual risk 1-6), §23.10.8 (stub disposition), §26.5/§26.8 (v1.9 bank-fix 선례)
> - [`../proofs/tla/README.md`](../proofs/tla/README.md) — ACC bank TLA+ 모델 (Stage-4 산출물 1). 본 메모 초고 시점(2026-08-15)에는 미착지였으나 **형제 산출물로 같은 commit 에 착지**했다.
> - [`board_hw_plan.md`](./board_hw_plan.md) — Stage-1/2 부품 판정 (cross-vendor 실측으로 §5 갱신됨)
> - [`future_applications.md`](./future_applications.md) — v2.0 이후 활용처 (본 메모의 스코프 밖)

---

## 0. 이 메모가 여는 것과 닫는 것

**닫는 것**: §23.1 의 v2.0 bullet 5개가 그동안 각각 한 문장짜리 forward-reference 로만 존재했다. 본 메모는 그 5개를 **인용 가능한 형태로 전사**하고, 각각에 대해 "무엇이 이미 결정됐는가 / 무엇이 반증됐는가 / 무엇이 아직 미결인가" 를 분리한다. 특히 반증 기록(§2.2, §3.5)은 **재제안 방지**가 목적이다 — 반증 사유가 repo 어디에도 남아 있지 않은 항목이 이미 2건 있고(§2.2), 그 상태로 두면 다음 설계 세션이 같은 안을 다시 올린다.

**열지 않는 것**: 본 메모는 어떤 인코딩도 확정하지 않는다. §3 의 계약 초안은 **초안**이며, `isa/wt64v1_isa.json` 의 어떤 행도 본 메모를 근거로 편집해서는 안 된다. §12a pre-stable 정책상 contract 변경은 정규 이벤트지만 **spec-first** 로 기록되어야 하고, 그 spec 편집은 v2.0 COMMIT 0 의 일이지 본 메모의 일이 아니다.

---

## 1. v2.0 TRAIN 의 스코프 — spec §23 전사

### 1.1 training triple (§23.1 v2.0 헤더, §23.5)

> "v2.0 **TRAIN** — 최초 학습 가능 버전 (training triple: bf16 multiply / fused fp32 accumulate / fp32-master-or-SR update)." (§23.1)

§23.5 가 이 triple 을 산업 표준 대비로 고정한다:

> "학습: bf16 곱 → fused fp32 누산 → fp32 master + fp32 Adam (또는 HW-SR 16-bit master)." (§23.5)

즉 v2.0 의 성공 정의는 **GPU 학습 계약과의 구조적 동형**이지 성능이 아니다.

### 1.2 통합 f16/bf16 fused-FMA lane (§23.1)

> "통합 f16/bf16 **fused-FMA** lane (11-bit mantissa 곱셈기 하나로 양쪽 커버; 곱은 wide-exponent 내부 포맷으로 exact 유지, fp32 누산에서 단 1회 RNE). bf16-accumulate 는 구조적으로 금지 (업계 전례 없음). ECP5 에서 FP_LANES=2 가 한계." (§23.1)

여기서 뽑히는 계약 5개:

| # | 계약 | 근거 |
|---|---|---|
| C1 | 곱셈기 **1개**, 11-bit mantissa, f16·bf16 양쪽 커버 | §23.1, §23.2 ("bf16 과 11-bit mantissa 곱셈기 공유로 near-free") |
| C2 | 곱은 wide-exponent 내부 포맷에서 **exact** — 곱 지점에 반올림 없음 | §23.1, §23.4 항목 1 |
| C3 | RNE 는 fp32 누산에서 **단 1회** | §23.1 — **✅ RESOLVED 2026-08-15**: per-FMA fusion 계약으로 한정 재구속 (spec §23.1 in-place 개정); 누산 스케줄은 spec §27 이 규범 (아래 RESOLVED 블록) |
| C4 | bf16-accumulate **구조적 금지** (acc==0 은 bf16 에서 **영구** ILLEGAL) | §23.1, §23.6a 전역 불변식 4 |
| C5 | ECP5 에서 FP_LANES=2 가 한계 | §23.1 — **본 메모 §5.1 에서 재검토 대상으로 지정** |

**C1 의 메커니즘은 spec 에 없다 — 명시해 둘 것.** f16 significand = 10 explicit + 1 hidden = 11 bit. bf16 significand = 7 explicit + 1 hidden = **8 bit**. 곱셈기는 둘 중 **넓은 쪽(f16, 11 bit)** 으로 sizing 되고, bf16 은 8-bit significand 를 11-bit operand port 에 zero-extend 해서 태워 보낸다 — 상위 3 bit 이 0 이 될 뿐, packing 도 sharing trick 도 dual-issue 도 없다. "bf16 이 11-bit mantissa 를 갖는다" 는 오독이 가능한 현 문구는 COMMIT 0 에서 풀어 쓸 것. (이 repo 는 `PE_Core.v:144-145` 형 doc/RTL drift 를 이미 한 번 겪었다 — §23.0.)

**C2 의 내부 포맷 폭이 spec 어디에도 없다.** §23.1 과 §23.4 항목 1 이 "wide-exponent 내부 포맷" 이라고만 하고 significand 폭·exponent 폭·정규화 관례를 전부 비운다. 그런데 **de-facto 답은 이미 출하돼 있다** — `FP_AddWide.v:20-33` 이 `value = (-1)^sign · sig · 2^(exp-47)`, 48-bit unsigned significand (unit at bit 47), **signed 11-bit exponent** 로 인터페이스를 못 박았고, 이 모듈은 이미 per-operator gate 를 통과했다(§4.2 실측표). **권고: v2.0 내부 포맷을 이 인터페이스 그대로 pin 한다.** 근거 3개:

1. **significand 창이 정확히 맞는다.** 전제조건은 "nonzero operand 의 sig ∈ [2^46, 2^48)". bf16: ma,mb ∈ [2^7,2^8) → 곱 ∈ [2^14,2^16) → **<<32** → [2^46,2^48). f16: ma,mb ∈ [2^10,2^11) → 곱 ∈ [2^20,2^22) → **<<26** → [2^46,2^48). 둘 다 정확히 착지하고, shift 는 static 2:1 wire mux(≈0 LUT).
2. **exponent 식이 dtype 무관하게 동일하다.** 두 dtype 모두 `p_exp = ea + eb + 1` 로 떨어지는데, 이는 fp32 경로가 이미 쓰는 식(`FP_StepSeq.v:905`, `aw_pexp = ex_ab1`)과 **같다** — exponent adder 는 변경 불요.
3. **C4 가 정책이 아니라 구조가 된다.** `FP_AddWide` 의 pack mode 는 PACK_WIDE(48-bit round-to-odd)와 PACK_FINAL(fp32) **둘뿐**이고 `final_fp32` 는 hard 32-bit port 다. bf16/f16 pack 경로가 모듈에 아예 없으므로, 이 모듈을 재사용하는 순간 bf16-accumulate 는 decode legality 이전에 **하드웨어적으로 불가능**해진다. formal-first 문화에서 방어 가능한 형태의 주장이다.

**C3 에 해석 충돌이 하나 있다 — COMMIT 0 에서 반드시 판정할 것.**

| 읽기 | 근거 문장 | 32-lane dot 당 RNE 횟수 |
|---|---|---|
| (A) per-step | §23.4 항목 2: "fp32 는 canonical order 에서 **step 당** 정확히 1회 RNE" | fused 곱 1회 + 5-level tree 5회 = **6회** (통상 GPU 계약) |
| (B) per-dot | §23.1: "fp32 누산에서 **단 1회** RNE" 의 문자 그대로 | **1회** |

(B) 를 택하면 tree 중간값을 PACK_WIDE(48-bit round-to-odd)로 들고 root 에서만 PACK_FINAL 하는 우회가 떠오르지만 **기본값으로 안전하지 않다**: round-to-odd 중간값 + fp32 RNE 의 single-rounding 등가는 중간 폭 ≥ 2p+2 = **50 bit** 를 요구하는데 `FP_AddWide` 의 내부 폭은 **48** 이다. 모듈 헤더가 주장하는 것은 RTO 합성성(`rto_n(rto_48(x)) == rto_n(x)`, n < 48)뿐이고 이는 다른·더 약한 성질이며, 현재 이 성질은 golden `micro_*` 모델과 bit-match 가 증명된 step sequence **내부**에서만 쓰이지 누산 트리의 double-rounding 우회로 쓰인 적이 없다. 따라서 **(B) 를 택하면 48-bit 가 재검토 대상이 되고 Gate 2 가 재개된다.** (A) 를 택하는 것이 기존 실측 자산을 보존한다. **판정은 사용자 결정 사항으로 남긴다** (§7).

> **✅ RESOLVED (2026-08-15, 사용자 결정 — spec §27 로 성문화, G6 종결).** 판정은 (A) 도 (B)-via-RTO-tree 도 아닌 **옵션 3 "wave-step-atomic accumulation"** 이다: in-dot 528-bit exact-integer lattice 가 dot 내부 반올림을 **0회** 로 만들고, wave-step 당 반올림은 **bank store 의 RTO-48 1회**, drain 에서 **RNE-24 1회** 뿐이다 — 즉 (B) 가 원하던 "dot 당 단일 반올림" 을 wide 포맷에 대해 달성하되, tree 가 아니라 **exact 합** 으로 달성하므로 위 50-bit 논증이 적용될 cascade 자체가 없다. **`FP_AddWide` 는 48-bit byte-untouched 존치, Gate 2 는 영구 폐쇄** — "50 bit 필요" 명제는 category error 로 은퇴했다 (RTO tree 는 50 포함 전 폭에서 실패하고, 폭이 중요한 유일한 지점인 최종 추출은 q ≥ 26 만 요구 — 48 은 22 bit 마진; spec §27.5 항 6).
>
> **아울러 위 표의 "(A) = 6회" 는 오류로 정정한다**: 6 은 경로 **깊이** (곱 1 + 5-level tree) 이지 이벤트 **수** 가 아니다. 32-leaf tree 의 dot 당 반올림 이벤트는 node 31 + bank store 1 = **32회/dispatch** 다 (`include/generated/acc_format_study_report.json` `rounding_events.correction`). 옵션 비교의 올바른 대비는 32 (option A/2 스케줄) vs **1** (옵션 3) 이다.
>
> **상태 갱신 (2026-08-15, GATE V20-2 실측 — spec §27.6)**: 옵션 3 의 첫 hard gate (528-bit lattice unit, xcu55c) 는 **FAIL** — LUT **53,418** > hard ceiling 20,040 (premap `$mul` 0 / Fmax 122.06 MHz 축은 통과; FAIL 의 94.5% 는 S1 배치 33× + compressor tree 귀속). ECP5 feasibility 측정 (판정 아님): 전 병렬 배치 불가 (LUT4 102,871 = fabric 123%), beat-serial 변형은 PnR 완주 + golden 4001/4001 bit-exact. 후속 방향 — (A) 재설계 (beat-serial N≤8 이 유일한 measured 경로) vs (B) ceiling 재anchor (§12a 정규 이벤트) vs (C) 혼합 — 은 **사용자 결정 대기**. 상세·귀속·레버는 spec §27.6 실측 블록.
>
> **상태 갱신 (2026-08-16, 사용자 결정 — spec §27.6 결정 기록)**: 위 후속 방향은 **옵션 (A) 로 착지** — L1 beat-serial N=8 재설계로 ceiling 20,040 충족, **재anchor 없음**. full-parallel II=1 은 §12a 정규 이벤트로 폐기 (원문 amendment 보존), 출하 microarchitecture 는 spec §27.2.1 amendment 가 normative (`PRODUCTS_PER_BEAT=8`, II ≤ 8, 수학 계약·golden·4001 벡터 불변 재사용). **하류 ③ (bank RTL) 착수 조건 = N=8 형상의 GATE V20-2 재실측 PASS** — lattice unit 최종 형상 (II, carry-in 인가 beat) 이 bank 인터페이스를 결정하기 때문이다 (spec §27.6 재실측 선언).

### 1.3 fp32 ACC bank + canonical accumulation order (§23.1)

> "**fp32 ACC bank** (2 × 32 lanes × 32b/cluster, tag pcid[1:0] 로 bank 선택 + 명시적 ownership/drain 계약 + ACC_SPILL/FILL) — "requester ID" 식 암묵 계약은 반증되어 폐기." (§23.1)
> "**normative canonical accumulation order**: 32-lane balanced 5-level tree + ascending wave-order K. 모든 FP_LANES 구성이 이 순서와 serially-equivalent 해야 함 → run/lane-config/part 간 bit-identical fp32 누산." (§23.1)

**위 인용문 2개가 ACC bank 에 관한 규범 텍스트의 전부다.** repo 전체에서 `pcid` 는 spec 에 정확히 1회 등장하고(위 문장), 정의는 spec 어디에도 없다 — RTL 에서만 `port_context_id = tag[31:16]` 로 정의된다(`EHDecode.v:363-367`).

> **[2026-08-15 갱신 — spec §27.2.2 가 bank 의 normative source 로 착지]** 위 "규범 텍스트의 전부" 서술은 이 시점부로 stale 다: bank word 는 **32b fp32 가 아니라 64b (PACK_WIDE 값의 IEEE binary64 무손실 재인코딩)** 로 확정됐고 (2 banks × 32 lanes × 64b/cluster; canonical zero = commit c21092a pin; SPILL image fp64, quarter-op 8 fragments; FILL validation — NaN/Inf sticky fault, ±0 canonicalize), 전 규범은 `wt64v1_spec.md` §27.2.2 다. **본 절의 pcid arity 모순·ownership/identity 질문과 TLA+ 선행 의무는 그대로 유효** — §27 은 그것을 닫지 않았다 (잔존 검증 표면으로 §27.4 에 등재).

**왜 이 한 줄이 TLA+ 를 강제하는가** (§23.7 리스크 3):

> "ACC bank 는 순수 tagged-wave 모델 밖의 신규 architectural state — tag-keyed bank aliasing 은 silent-gradient-corruption 클래스. **RTL 전에 TLA+/formal 선행** (wavetensor-drivers formal-first 관례)." (§23.7-3)

그리고 그 한 줄 안에 **arity 모순이 이미 들어 있다**: `pcid[1:0]` 은 4 값을 갖는 selector 인데 bank 는 2 개다. 문자 그대로 읽으면 selector 는 **설계상 2:1 non-injective** 이며, 이것이 정확히 TLA+ 가 부재를 증명해야 할 aliasing 그 자체다. 게다가 `pcid` 의 비트는 이미 routing 이 전부 점유하고 있다 — Pod 은 `pcid[7:4]` 를 cluster index 로(`Pod.v:130-132`), Cluster 는 `pcid[3:0]` 을 intra-cluster PE index 로(`Cluster.v:498-500`) 쓴다. 따라서 `pcid[1:0]` = **intra-cluster PE index 의 하위 2 bit**. Cluster 는 2×4/4×2/4×4 geometry 도 합법 elaborate 하므로(`Cluster.v:396-397`) 최대 16 PE 가 2 bank 를 두고 경쟁한다. 결정적으로 **pcid 에는 thread_id 도 wave_number 도 없다** — 두 논리적으로 다른 누산이 무조건 같은 bank 로 사상된다.

세부 미결 항목과 불변식 제안은 형제 산출물 `proofs/tla/README.md` 로 이관한다. 본 메모는 **v2.0 이 그 모델의 결론에 종속된다**는 사실만 기록한다(§6 sequencing).

**canonical accumulation order 는 두 갈래로 쪼개서 증명할 것을 권고한다:**

| 반쪽 | 증명 대상 | 도구 | 왜 |
|---|---|---|---|
| 구조 | 임의의 interleaving·FP_LANES·spill/fill 스케줄에서 bank cell 에 쌓이는 **⊕-tree 가 canonical serial reference 와 syntactically identical** | **TLA+/TLC** — ⊕ 를 **uninterpreted binary operator** 로 두고 숫자를 절대 쓰지 않음 | 이건 concurrency 정리다. K≤8, bank 2, lane 2-4 면 유한 상태 |
| 수치 | **그 고정 순서가 요구되는 bit 를 낸다** | golden model + numpy/mpmath/ml_dtypes 독립 oracle (§23.10.5 항목 13 규칙) | 이건 IEEE-754 정리다. TLC 에 float theory 가 없고 실수 산술은 상태공간 폭발 |

**둘의 합성 논증을 명시 기록할 것**: TLA+ 가 "연산 **순서**가 프로그램 결정적 불변식이다" 를 주고, golden model 이 "그 고정 순서가 그 bit 를 낸다" 를 준다. **어느 한쪽만으로는 §23.4 항목 5 (bit-reproducibility) 가 성립하지 않는다.**

### 1.4 fp32 master weights + Adam (§23.1)

> "fp32 master weights + Adam (fp32 scalar pipeline 재사용)." (§23.1)

**신규 하드웨어를 요구하지 않는 유일한 v2.0 항목이다.** v1.8.0c 의 FP-UNIT(FSCALAR add/sub/mul/FMA/sequential-div, FRSQRT32 ≤2 ulp, FEXP2_32 ≤2 ulp)이 Adam 의 모든 원소 연산을 이미 커버한다 — Adam 은 elementwise FMA 2회(m, v) + rsqrt + FMA 1회(update) 이고, `sqrt(v)+ε` 의 역수는 FRSQRT32 로 흡수된다. 남는 일은 **매크로 조립과 golden 대조**이지 datapath 가 아니다. 이 사실이 §6 sequencing 에서 Adam 을 후반부에 배치하는 근거다.

### 1.5 counter-based stochastic rounding — non-default (§23.1)

> "**Stochastic rounding 은 탑재하되 non-default**: counter-based RNG keyed on (wave_number, thread_id, lane_index), ≥16 random bits — free-running LFSR(재현 불가)과 8-bit/correlated-lane(bias) 방식 둘 다 반증됨. fp32→bf16 STORE_QUANT downcast 에서만 적용 (Trainium/Graphcore 지점)." (§23.1)

전문은 §2.

### 1.6 v2.0 가 **아닌** 것

spec 이 명시적으로 부정하는 항목들. 포지셔닝 규율 자체가 리스크로 등재돼 있다(§23.7-6).

| 부정 항목 | spec 근거 |
|---|---|
| **v1.8 은 학습 가능하지 않다.** "v1.8 을 학습 가능한 것처럼 마케팅 금지" | §23.5 |
| **v2.0 은 학습-속도 parity 가 아니다.** "v2.0 은 학습-**정확성** parity + GPU 가 못 주는 차별점(bit-reproducibility)이지, 학습-**가속** parity 가 아님. 속도 주장은 Stage-2 Avant G70 (v2.1) 부터" — 단 Avant G70 은 cross-vendor 실측 이후 **폐기**됐으므로(§5.4) 이 문장의 "Stage-2" 지시대상은 재지정 필요 | §23.5, cross-vendor §5 |
| **타 GPU/CPU 와의 bitwise 동일성은 영원히 약속 불가.** FP 덧셈 비결합성 — GPU 자신도 kernel config 간 bit 동일성을 보장하지 않는다 | §23.4 |
| **f64 는 v2.0 스코프 밖.** 별도 확장 `Lf`; base 의 dtype nibble 0x5 는 decode_error 예약 유지 | §23.2, §23.6a 전역 불변식 1 |
| **FP8 / FP_LANES=8+ / 16-fragment 출력 FSM 은 v2.1.** SR 의 default 승격 검토도 v2.1 | §23.1 v2.1 bullet |
| **bf16-accumulate 는 영구 금지.** 완화 loosening 대상이 아니다 | §23.1, §23.6a 불변식 4 |
| **TRNG 는 SR 의 엔트로피원이 아니다.** SR 은 counter-based 여야 재현 가능하다(§2.2) — `HIU.v:347` 의 ring-oscillator TRNG 와 SR 은 **직교하며 연결 금지** | §23.1 (counter-based), cross-vendor §5.1 |

---

## 2. SR (stochastic rounding) 설계 입력

### 2.1 이미 결정된 것 (spec §23.1 / §23.6a)

| 항목 | 결정 | 근거 |
|---|---|---|
| RNG 종류 | **counter-based** (재현 가능) | §23.1 |
| key | **(wave_number, thread_id, lane_index)** | §23.1 |
| 폭 | **≥16 random bits** | §23.1 |
| 적용 지점 | **fp32→bf16 STORE_QUANT(0x7C) downcast 에서만** | §23.1 |
| mode-byte 인코딩 | **rnd = 1** (eff_precision[7:6]) | §23.6 |
| v1.8 에서의 상태 | rnd==1 은 v1.8 **전체에서 ILLEGAL**; v2.0 이 STORE_QUANT 에서 합법화 | §23.6a 전역 불변식 3, 0x7C 행 "rnd=1(SR) 은 v2.0 loosening" |
| default 여부 | **non-default.** default 승격 검토는 v2.0 이 아니라 **v1.8.0? → v2.1** ("SR 을 in-house 수렴 검증 후 default 승격 검토") | §23.1 v2.1 bullet |
| bit-reproducibility 계약 | §23.4 항목 5 가 **SR 을 포함한다** — "SR 포함 — counter-based RNG 라 재현됨" | §23.4-5 |

**핵심**: SR 은 §23.4 항목 5 의 **예외가 아니라 그 안에 있다**. 즉 "SR 켜면 비트가 달라진다" 는 허용되지만 "SR 켜면 run 마다 달라진다" 는 **계약 위반**이다. 이 구분이 §2.3 의 설계 질문 전부를 지배한다.

### 2.2 반증 기록 — 재제안 금지 (⚠️ 사유가 repo 에 남아 있지 않음)

§23.1 은 두 안이 반증됐다는 **판정만** 기록하고 **사유를 기록하지 않았다**. 원 사유는 design study workflow (`fp-native-compute-path-study`, task `wul707ze7`/`wf_3208c8ae-396`, 16 agents, 1.04M tokens) 산출물에 있는데 그 산출물은 **repo 에 없다** (`.claude-memos/_completed` 는 비어 있음). 아래는 판정문에 붙은 괄호 사유를 근거로 한 **재구성**이며, 재구성임을 명시한다.

#### 반증 1 — free-running LFSR

- **판정** (spec 문자 그대로): "free-running LFSR(**재현 불가**)" — §23.1
- **재구성한 사유**: free-running LFSR 의 출력은 **리셋 이후 경과 클럭 수**의 함수다. 즉 같은 프로그램·같은 데이터·같은 시드라도 dispatch 가 도착한 **시각**이 다르면 다른 난수를 뽑는다. 그런데 v1.9 는 dispatch 파이프라이닝으로 latency 를 T+1 → T+2 로 바꿨고(§26.4), 앞으로도 arbitration/스케줄링 변경은 정규 이벤트다. **free-running RNG 를 쓰면 파이프라인 깊이를 1 단 바꾸는 것만으로 학습 결과 비트가 바뀐다.** 이는 §23.4 항목 5 ("run/FP_LANES/part 불문 bit-identical")를 직접 위반하며, WT 가 GPU 대비 유일하게 주장하는 차별점을 삭제한다.
- **⚠️ 재제안 금지 트리거**: "LFSR 이 counter+hash 보다 싸다" 는 면적 논증은 **이 반증을 건드리지 않는다**. 면적이 아니라 **결정론**이 반증 사유다. LFSR 자체가 금지된 것도 아니다 — **counter 로 인덱싱되는(= free-running 이 아닌) LFSR-계열 mixing function 은 허용 가능**하다. 금지된 것은 *free-running* 이다.

#### 반증 2 — 8-bit / correlated-lane

- **판정**: "8-bit/correlated-lane(**bias**)" — §23.1. 대안 요구사항이 "≥16 random bits" 인 것이 사유를 절반 말해 준다.
- **재구성한 사유 (두 갈래)**:
  - **폭 (8-bit)**: fp32 → bf16 은 significand 24 bit → 8 bit 로, **16 bit 를 버린다**. SR 이 unbiased 하려면 난수가 **버려지는 비트 전부**를 커버해야 한다 — 즉 `round_up = (discarded_bits + rand) 가 carry 를 내는가` 형태에서 `rand` 가 discarded 폭보다 좁으면 하위 (16 − w) bit 는 반올림 결정에 **영향을 줄 수 없고**, 그만큼 기댓값이 truncation 쪽으로 치우친다. 8-bit 는 16-bit 중 8-bit 를 무시하므로 **구조적 bias**다. "≥16" 이라는 하한이 정확히 이 폭에서 나온다.
  - **lane 상관 (correlated-lane)**: 모든 lane 이 같은 난수를 쓰면 반올림 오차가 lane 간 독립이 아니라 **동조**한다. SR 의 존재 이유는 누산에서 오차가 √n 로 상쇄되는 것인데, 완전 상관이면 상쇄가 아니라 **n 배 누적**된다 — SR 을 켠 쪽이 RNE 보다 나빠질 수 있다. 그래서 key 에 `lane_index` 가 들어 있다.
- **⚠️ 재제안 금지 트리거**: "lane 마다 같은 난수를 쓰고 lane_index 로 XOR 만 하면 싸다" 는 안은 **반증 2 의 두 번째 갈래를 재도입한다** — XOR 은 값을 바꾸지만 lane 간 상관을 제거하지 않는다(선형 관계가 그대로 남는다). 필요한 것은 **decorrelation** 이지 permutation 이 아니다(§2.3 Q3).

### 2.3 답해야 할 구체적 설계 질문

전부 **미결**이며 v2.0 COMMIT 0 의 대상이다.

**Q1 — counter 폭과 counter 의 정체.** key 가 (wave_number 32b, thread_id 16b, lane_index) 인데 이것은 **counter 가 아니라 좌표**다. counter-based RNG (Philox/Threefry 계열) 는 보통 (key, counter) 2-입력이다. 여기서 counter 로 쓸 것은 무엇인가?
  - (a) 좌표 전체를 counter 로 보고 key 를 프로그램 시드로 두는가? → 시드를 어디로 넣는가(신규 architectural state? EH? tag?)가 열린다.
  - (b) 좌표를 key 로 두고 counter 를 "이 좌표에서의 몇 번째 downcast" 로 두는가? → **그 카운트를 셀 하드웨어가 없다** (dec_* bus 에 fragment 수가 없다는 §23.6a SDK 계약 1 의 노출면과 동일).
  - 폭: 32+16+lane_index 를 그대로 먹이면 입력이 이미 ≥50 bit 다. 출력 ≥16 bit 는 확정. **입력 폭·mixing rounds 수·면적이 전부 미결**이며, 이것이 §4 의 gate 대상이다.

**Q2 — reseeding 정책.** 재현성 계약상 "reseed" 는 **프로그램이 명시적으로 지정한 값**이어야 한다 (시간·엔트로피 기원 금지 — §1.6 마지막 행). 열린 질문:
  - 시드를 담는 곳이 없다. 후보: (i) 신규 architectural register (0x7E 의 sub-op 으로 write — §3.3), (ii) tag 의 어떤 필드 (⚠️ **신규 tag namespace 를 만들지 않는다**는 v1.9 §26.5 의 확립된 규율에 걸린다), (iii) STORE_QUANT 의 imm16 (⚠️ imm16[5:0] 은 이미 shift amount s 가 점유, [15:6] 은 reserved-zero → lower_required).
  - epoch/step 경계에서 시드가 바뀌어야 하는가? 아니면 (wave_number, thread_id) 가 이미 step 을 구별하므로 시드는 프로그램당 1회로 충분한가? **후자가 유력하나 미검증** — wave_number 가 학습 step 을 단조 증가로 반영하는지가 SDK 계약에 달려 있고 그 계약이 없다.

**Q3 — per-lane decorrelation.** 반증 2 가 XOR-류 선형 변환을 배제한다(§2.2). 최소 요구사항 초안:
  - lane_index 가 **mixing function 의 입력**으로 들어가야 하고, mixing 은 **비선형**이어야 한다 (ARX 또는 다중 라운드).
  - 검증 가능한 술어로 표현할 것: 고정 (wave_number, thread_id) 에 대해 lane 별 난수열의 **쌍별 상호상관이 통계적 잡음 수준**. 이는 golden model 에서 sweep 으로 확인 가능하고 RTL 은 golden 과 bit-match 만 보이면 된다 — **RTL 에 통계 테스트를 넣지 말 것** (§23.10.5 독립-oracle 규칙의 정신).
  - ⚠️ **미결**: FP_LANES 가 2 인 구성과 8 인 구성에서 `lane_index` 의 의미가 같아야 한다. 32-lane canonical order 를 2-lane 으로 16 pass 접어 실행할 때 lane_index 는 **물리 lane 이 아니라 논리 lane(0..31)** 이어야 §23.4 항목 5 가 성립한다. **이것을 명시 pin 하지 않으면 FP_LANES 를 바꾸는 순간 SR 결과가 달라진다** — 본 메모가 발견한 가장 조용한 함정이다.

**Q4 — SR on/off 에서 bit-reproducibility 가 어떻게 보존되는가.** 계약을 세 층으로 분리해 진술할 것을 권고한다:

| 층 | 진술 | 검증 |
|---|---|---|
| R1 | rnd=0 (RNE) 결과는 rnd 필드가 존재한다는 사실에 **영향받지 않는다** — SR 하드웨어가 있어도 RNE 경로 비트는 v1.8 과 동일 | 기존 STORE_QUANT 회귀가 무변경 통과 |
| R2 | rnd=1 결과는 (프로그램, 데이터, 시드) 고정 시 **run/FP_LANES/part 불문 동일** | §4.3 SR-REPRO 테스트군 |
| R3 | rnd=0 과 rnd=1 은 **서로 다른 비트를 낸다** — 이는 위반이 아니라 정의 | 차분 테스트 (둘이 같으면 SR 이 동작하지 않는 것) |

R1 이 중요한 이유: SR 을 넣으면서 STORE_QUANT 의 RNE 경로를 건드리면 **v1.8 의 모든 출력 비트가 조용히 바뀐다**. R1 을 명시 계약으로 두면 그것이 회귀 테스트로 강제된다.

**Q5 — SR 이 ACC bank drain 과 만나는 지점 (⚠️ 고위험, 조용함).** SR 의 key 는 (wave_number, thread_id, lane_index) 인데, ACC bank 를 STORE_QUANT rnd=1 로 drain 할 때 그 (wave_number, thread_id) 는 **누가 것인가**?
  - **소유자(누산을 시작한 identity)의 것**이어야 한다 — 그래야 "누가 drain 했는가" 와 무관하게 비트가 결정된다.
  - **drain 하는 dispatch 의 것**이면, 같은 프로그램이 drain 스케줄만 달라져도 다른 비트를 낸다 → §23.4 항목 5 위반. **조용한 위반이다** (결과는 멀쩡한 유한 fp32).
  - spec 은 어느 쪽인지 말하지 않는다. **이것 하나만으로도 ownership token 을 pcid 파생 slice 가 아니라 명시적 architectural object 로 만들 충분한 근거가 된다** — TLA+ 모델의 identity 선택과 직결되므로 `proofs/tla/README.md` 와 교차 참조할 것.

### 2.4 golden model 격차 (실측)

`scripts/golden_fp32.py` 에서 `stochastic` 문자열 **0회 매치** (2026-08-15 실측). `ref_narrow_f32` (line 665) 는 RNE 전용이고 rounding 인자를 받지 않는다. 즉 **SR 은 golden 에 존재하지 않는다** — v2.0 의 신규 작업이다.

반면 **이미 있는 것**(실측 확인): `ref_fma` (:295), `ref_widen_f16` (:620), `ref_widen_bf16` (:642), `ref_narrow_f32` (:665), `micro_fscalar` (:562). bf16→f32 widening 이 normal 에 대해 **exact** 이므로 `ref_fma(ref_widen_bf16(a), ref_widen_bf16(b), c_f32)` 는 **이미 v2.0 FMA lane 1개의 bit-exact reference 다** — `ref_fma` 가 Fraction 산술로 곱을 exact 하게 들고 RNE 를 1회만 적용하기 때문이며, 이것이 정확히 C2+C3 계약이다. **v2.0 golden 작업의 본체는 새 산술 커널이 아니라 (i) SR, (ii) 누산 순서 모델, (iii) ACC bank 상태 모델이다.**

⚠️ **한 가지 비대칭을 v2.0 에서 재핀할 것**: `ref_widen_bf16` 은 bf16 subnormal 을 **signed zero 로 flush** 하는데 `ref_widen_f16` 은 f16 subnormal 을 **exact 하게 존중**한다. 이 비대칭은 **CVT 를 위해** 핀된 것이고, compute 경로(FMA lane)로 그대로 상속시키면 spec-vs-golden drift 가 된다. COMMIT 0 에서 operand-load 정책을 명시할 것.

---

## 3. 0x7D ACC_SPILL_FILL / 0x7E FP_ACC_CTRL 계약 초안

### 3.1 현 상태 (실측 — `isa/wt64v1_isa.json`, 2026-08-15)

| | **0x7D ACC_SPILL_FILL** (code 125) | **0x7E FP_ACC_CTRL** (code 126) |
|---|---|---|
| `stub_v18` | **true** | **true** |
| 현 동작 | decode-legal → PE_Core **lower_required** (capability absence, malformation 아님) | 동일 |
| disposition | §23.10.8: "**0x7D → v2.0**" | §23.10.8: "v1.8.0d/v2.0 — v1.8.0c 는 semantics 를 **prose 로만 예약**하고 레지스터를 추가하지 않는다" |
| mode byte | dtype **0x4 (f32)** only, acc **1**, rnd **0** | dtype **0x4**, acc **1**, rnd **0** — dtype 은 **관례적** (제어 op) |
| asm required | `mem`, `port` | `port` |
| asm forbidden | imm16, imm32, imm64, opref, subscript | imm16, imm32, imm64, **mem**, opref, subscript |
| rtl_legality | req_port ✔ req_mem ✔ / forbid_imm_any ✔ forbid_opref ✔ forbid_subscript ✔ | req_port ✔ / **forbid_mem ✔** forbid_imm_any ✔ forbid_opref ✔ forbid_subscript ✔ |
| `require_precision_eh` | **true** | **true** |
| stub 유지 사유 (JSON notes) | "int32 spill loosening 은 **affirmatively NOT needed** (no accumulator exists)" | "nothing to zero (no accumulator exists); ZERO/STATUS sub-op 인코딩 결정은 op 와 **함께** 이연 — **do not burn the encoding space early**" |

### 3.2 0x7D ACC_SPILL_FILL — 계약 초안

**해야 할 일**: ACC bank(2 × 32 lane × 32b/cluster = cluster 당 2 Kib)를 메모리로 **spill** 하고 메모리에서 **fill** 한다. 존재 이유는 oversubscription 이다 — cluster 당 bank 가 **2 개뿐**이므로 3번째 live 누산이 생기면 소프트웨어가 자리를 비워야 한다.

**초안 항목**:

| 항목 | 초안 | 상태 |
|---|---|---|
| 이동 단위 | JSON desc 의 "**quarter-ops**". bank = 32×32b = 1024 bit 이고 그 1/4 = **256 bit** 로 기존 wide-payload 상한과 일치 — **그러나 이는 추론이지 spec 아님** | ⚠️ 추론 |
| 주소 | `mem` EH 가 required 이므로 offset 이 carrier | 확정 (EH shape) |
| bank 지정 | 미결: `pcid[1:0]` 파생인가, 별도 operand 인가 | ⚠️ 미결 |
| sub-op (SPILL vs FILL) | **carrier 가 없다** — §3.4 | ⚠️ **차단 항목** |
| dtype loosening | "int32 spill 필요 시 loosening" 은 v1.8.0b 에서 **affirmatively 불요** 판정. v2.0 에서 ACC bank 가 fp32 전용이면 그대로 불요 | 확정 (조건부) |
| frag FSM | desc: "**frag FSM untouched**" — ⚠️ **전제가 낡았다**. 이 문구는 frag FSM 이 2-bit/4-fragment 이던 시절 작성됐고, §25.3 (v1.8.0e) 이 `frag_idx [1:0]→[3:0]`, `frag_pending [0:3]→[0:15]` 로 **16-fragment 로 확장**했다. 256-bit quarter 는 64-bit fragment 4개 = 여전히 수용되지만, **"untouched" 라는 주장은 재검증 대상** | ⚠️ 재검증 |

### 3.3 0x7E FP_ACC_CTRL — 계약 초안

**두 개의 서로 다른 일을 한다** — 하나는 누산기 제어, 하나는 예외 플래그.

**(a) FP_ACC_ZERO**: 지정된 bank 를 0 으로 만든다. ACC bank ownership 계약의 **acquire 지점 후보** — §3.5.

**(b) FP_STATUS**: sticky IEEE exception flag 의 **atomic read-and-clear**. spec §23.10.8:

> "sticky flag register (invalid / overflow / underflow-flushed). v1.8.0c 는 semantics 를 prose 로만 예약하고 레지스터를 추가하지 않는다 — fp special-case 표가 deterministic 이므로 flag 는 이후 어떤 result bit 도 바꾸지 않고 추가 가능."

그리고 §23.10.9 리스크 8 이 이 결손을 **미해결로 등재**해 두었다:

> "**IEEE sticky exception flag 는 0x7E FP_STATUS 착지 전까지 갈 곳이 없음**: 초기 소프트웨어는 invalid/overflow 를 전혀 관측 불가; spec 은 semantics 만 예약하며, 0x7E 의 최종 설계가 per-op flag capture 를 원하면 fp FSM 에 (results-invariant) sticky-latch retrofit 필요."

**즉 v2.0 의 0x7E 는 v1.8.0c 이래 열려 있던 리스크 8 을 닫는 지점이다.** 학습 문맥에서 이것은 장식이 아니다 — bf16 학습에서 overflow/invalid 가 관측 불가능하면 발산을 진단할 수단이 없다. 초안 항목:

| 항목 | 초안 | 상태 |
|---|---|---|
| flag 집합 | invalid / overflow / **underflow-flushed** (FTZ 가 발동했다는 뜻 — IEEE underflow 와 구별) | spec 예약됨 |
| 접근 | **atomic read-and-clear** (JSON desc) | spec 예약됨 |
| 범위 | 미결: per-cluster 1 세트인가, per-identity 인가? 학습은 후자를 원하지만(어느 layer 가 터졌는지) 비용이 다르다 | ⚠️ 미결 |
| capture 지점 | §23.10.9-8 이 예고한 "results-invariant sticky-latch retrofit" — **결과 비트를 바꾸지 않는다**는 것이 계약 | ⚠️ 설계 필요 |
| SR 과의 관계 | SR 은 새 예외를 만들지 않는다 (반올림 방향만 바꿈). 단 **overflow 는 SR 로 유발될 수 있다** — RNE 로는 max-finite 로 떨어지는 값이 SR 로는 올라가서 Inf 가 될 수 있다. 계약: overflow→±Inf (never max-finite, `ref_narrow_f32` 의 기존 규칙) 유지, flag 만 셋 | ⚠️ 확인 필요 |
| ZERO vs STATUS sub-op | **carrier 가 없다** — §3.4 | ⚠️ **차단 항목** |

### 3.4 ⚠️ 차단 항목 — 두 opcode 모두 sub-op 을 실을 곳이 없다

두 JSON desc 가 모두 "sub-op encoding v1.8.0b" 로 끝나는데, 그 결정은 **명시적으로 이연됐고("do not burn the encoding space early") 착지한 적이 없다.** 그런데 두 행 모두 `forbid_imm_any: true`, `forbid_opref: true`, `forbid_subscript: true` 이고 0x7E 는 `forbid_mem: true` 까지다. **즉 selector 를 실을 필드가 하나도 열려 있지 않다.**

이 계열의 확립된 해법은 **imm16[7:4] 에 sub-op 을 싣는 monotonic loosening** 이다 — 0x72 ACC_REDUCE(`acc_reduce_op_codes`), 0x74 FSCALAR(`fscalar_op_codes`), 0x77 CVT, 0x79 FMINMAX 가 전부 이 패턴이고, forbidden→optional 은 **어떤 합법 인코딩도 불법으로 만들지 않으므로 non-breaking** 이다(§23.6a 정책).

**그러나 default 값 처리가 여기서만 위험하다**:

| 선례 | absent imm16 의 의미 | 위험도 |
|---|---|---|
| 0x72 ACC_REDUCE | absent = **SUM** | 낮음 — 기존 port-only 인코딩이 자연스러운 의미를 획득 |
| 0x74 FSCALAR | absent = **FS_ADD** | 낮음 |
| 0x77 CVT | absent = **widen** | 낮음 |
| **0x7D** | absent = SPILL? FILL? | **높음** — 둘은 **반대 방향 데이터 이동**이다. 잘못 고르면 메모리를 덮어쓰거나 누산기를 덮어쓴다 |
| **0x7E** | absent = ZERO? STATUS? | **높음** — ZERO 는 파괴적, STATUS 는 read-and-clear. 둘 다 부작용이 있다 |

**권고**: 0x7D/0x7E 에 대해서는 **absent imm16 = lower_required** 로 둘 것 (default 를 지정하지 않음). 이것도 monotonic 이다 — 오늘 이 인코딩들은 어차피 전부 lower_required 이므로 **어떤 프로그램도 회귀하지 않는다**. "default 를 안 정하는 것" 이 이 두 opcode 에서는 restrictive-first 원칙의 정확한 적용이다. (0x72/0x74 는 stub→real 전환에서 기존 port-only 인코딩을 **살려야 했기 때문에** default 가 필요했고, 여기는 그런 제약이 없다.)

**대안 검토 (기록용, 권고 아님)**: 0x7D 는 `mem` 이 required 이므로 mem offset 의 상위 비트로 방향을 인코딩할 수 있다 — **그러나 offset 을 semantic selector 로 쓰는 선례가 이 repo 에 없고**, 0x7C 가 "mem-present 는 합법이되 offset 무시" 로 이미 회색지대를 만들어 둔 상태라 혼란만 키운다. **imm16 loosening 이 선례 정합적이다.**

### 3.5 ACC bank ownership/drain 계약과의 상호작용

§23.1 은 "명시적 ownership/drain 계약" 이라고만 하고 **본문이 없다** — acquire op 도, release op 도, fault semantics 도, **하드웨어 강제인지 SDK 규율인지도** 없다. 그리고 "requester ID 식 **암묵** 계약은 반증되어 폐기" 라는 판정이 있다. 즉 반증된 것은 "소유자를 요청자 ID 로부터 **추론**하는" 방식이고, 살아남은 것은 "**선언**하는" 방식이다.

**⚠️ 별개로 반증된 항목 하나 더**: `per-pe-acc` (PE 마다 누산기를 두는 배치)는 adversarial verify 에서 refuted — 사유 2개가 기록돼 있다: (i) **forbidden→required EH 전환 = spec 자기 정책 위반 breaking**, (ii) **LUT/MULT 예산 초과에 uncosted** (§23.9 v1.8.0b). **두 항목 모두 재제안 금지.**

**0x7D/0x7E 가 이 계약에서 맡을 자리 (초안)**:

| 계약 이벤트 | 후보 opcode | 논평 |
|---|---|---|
| **acquire** (소유권 선언) | **0x7E FP_ACC_ZERO** | 자연스럽다 — "이 bank 를 0 으로 만들고 내 것으로 한다" 는 하나의 원자적 행위. bank 를 0 으로 만드는 것과 소유권을 잡는 것을 분리할 이유가 없고, 분리하면 "zero 됐지만 주인 없는 bank" 라는 상태가 생긴다 |
| **contribute** | 0x70 VFMA_ACC (v2.0 에서 dtype f16/bf16 loosening) | §23.6a 0x70 행: "FP dtype (f16/bf16) 는 v2.0 에서 loosening" |
| **drain** (소유권 해제 + 값 반출) | **미지정** — 후보 3개: 0x72 ACC_REDUCE(현재 stateless, int4/int8 전용; fp32 reduce 는 loosening 예고됨), 0x7C STORE_QUANT, 0x7D SPILL | ⚠️ **미결.** SR 과 만나는 지점이므로(§2.3 Q5) 아무거나 고를 수 없다 |
| **spill/fill** (소유권 **유지** 하에 자리 비우기) | 0x7D | ⚠️ spill 이 소유권을 **유지**하는지 **이전**하는지가 미결. 유지가 맞다고 본다 — 아니면 spill 이 곧 drain 이고 별도 opcode 가 불필요 |

**v1.9 §26.5 선례에서 가져올 것 / 가져오면 안 되는 것**은 `proofs/tla/README.md` 로 이관하되, 계약 설계에 직접 걸리는 3개만 여기 남긴다:

1. **loud fault, never silent.** v1.9 의 `bank_tag_collision_error_r` 는 **합성 가능한 sticky 상태 비트**로 Cluster 출력 포트에 노출됐고, spec 이 "simulation-only `$error`/assertion 이어서는 안 된다" 를 명시했다(§26.5). ACC bank 의 소유권 위반도 **같은 등급의 loud fault** 여야 한다 — silent-gradient-corruption 클래스의 정의상 조용한 수용이 곧 실패다.
2. **하드웨어 강제 vs SDK 규율.** §26.8 항목 10 이 마지막 SDK spacing 규칙을 **삭제(narrow 가 아니라 delete)** 하고 하드웨어 제거로 대체했다. 그리고 §23.6a SDK 계약 1 이 보여주듯 **SDK-only 계약은 하드웨어에서 감지 불가**하다. → **ACC bank ownership 은 하드웨어 강제로 pin 할 것을 권고하며, 이는 사용자 결정 사항이다**(§7).
3. **claim 의 cycle 을 모델링할 것.** v1.9 residual risk 11 이 정확히 이 함정이었다 — accept/reject 결정이 T+1 로 옮겨졌는데 allocation 이 T 에 남아 **phantom row** 가 생겼다. 소유권 claim 모델은 **claim 사이클과 reject 경로를 반드시 포함**해야 한다.

---

## 4. 검증 공수 리스크 (§23.7 리스크 5) — v2.0 의 **지배적** 일정 리스크

### 4.1 원문과 왜 이것이 1순위인가

> "**검증 공수가 RTL 공수를 초과할 전망** (~16 opcodes, fused-FMA pipe, NR step-sequence, SR, ACC state, canonical-order equivalence) — v2.0 의 지배적 일정 리스크." (§23.7-5)

이 리스크가 다른 리스크와 다른 점: 리스크 1(면적)·2(timing)은 **측정하면 닫힌다**(그리고 실제로 §5 에서 절반 닫혔다). 리스크 5 는 **측정으로 닫히지 않고 오직 테스트를 작성해야 닫힌다.** 게다가 v2.0 이 파는 것이 **bit-reproducibility** 이므로 — 즉 제품의 가치 명제 자체가 검증 산출물이므로 — 검증을 줄이는 것은 기능을 줄이는 것이다.

그리고 이 repo 는 **이 리스크로 이미 한 번 물렸다**: v1.8.0b 가 자신이 선언한 "MU MAC-tree per-operator synth gate = merge blocker" 를 실행하지 않고 merge 했고, 결함(6개 reduction 함수의 선형 누산 루프 → 1,015 logic stage, Fmax 5.88 MHz)이 **5 commit 뒤** Gate 4 에서 발각됐다(§23.10.7). 도출된 normative 교훈이 "**merge blocker 선언된 gate 는 commit 전 완료 확인**" 이다.

### 4.2 현 검증 자산 (2026-08-15 직접 실측)

| 자산 | 실측값 | 방법 |
|---|---|---|
| cocotb 테스트 | **279** `@cocotb.test` (test_isa_decoder 189 / test_cluster 45 / test_alu_extended 16 / test_simd_alu 9 / test_pod 7 / test_top_core 7 / test_pe 4 / test_hiu 1 / test_tensor_alu 1) | `grep -h '@cocotb.test' test_*.py \| wc -l` |
| asm unittest | **138** (`asm/test_wavetensor_asm.py`) | `grep -h "def test_" \| wc -l` |
| golden model | `scripts/golden_fp32.py` (2-layer: `ref_*` 참조 / `micro_*` sequencer-faithful twin) + `scripts/fp_release_sweep.py` (독립 oracle: numpy/mpmath/**ml_dtypes**) | 파일 확인 |
| per-operator synth gate | 3개 (fp_mul36 / fp_addwide / fp_stepseq), `synth/lattice/scripts/synth_fp_ops.sh` + `gate_check.py`, 보고서는 `synth/lattice/reports/fp_ops/` 에 archive | `gate_summary.txt` |
| lint | `lint_frag_total_m1_held.py`, `lint_isa_tables_fresh.py`, `make lint` | 파일 확인 |

> ⚠️ **수치 정정**: 착수 브리프의 "233-test cocotb suite" 는 본 실측(**279**)과 일치하지 않는다. 233 은 더 이전 시점 수치이거나 일부 모듈 제외 집계로 보인다. 아래 배수 추정은 **279 + 138 = 417** 을 기준선으로 삼는다.

### 4.3 test plan skeleton — 5개 테스트군

각 군에 대해 **무엇을 잡는가**(잡히는 failure mode)를 명시한다. 이것이 없는 테스트는 커버리지 장식이다.

#### TP-1 — training-epsilon test (§23.4 항목 6, **최상위 acceptance**)

> "training epsilon test: 소형 MLP N-step 학습 궤적이 golden bf16/fp32 소프트웨어 파이프라인과 bit-for-bit 일치" (§23.4-6)

| | |
|---|---|
| **잡는 것** | 다른 4개 군이 개별적으로 통과해도 **합성했을 때 어긋나는** 모든 것. 특히 누산 순서·ACC bank 소유권·SR key 가 층을 넘어가며 조용히 뒤바뀌는 경우 |
| **구조** | golden 측: `golden_fp32.py` 위에 순수 Python MLP forward/backward/Adam (bf16 곱 → fp32 누산 → fp32 master). RTL 측: 같은 프로그램을 asm 으로 인코딩해 Cluster/Pod 에 흘림. 비교: **파라미터 전체의 bit-for-bit** — loss 값이 아니라 **weight bit** |
| **N** | 미결. 발산은 초기에 안 보이므로 N=1 은 무의미하고, cocotb 에서 N 이 크면 시뮬 시간이 폭발한다. **권고: N 을 파라미터로 두고 per-commit N=3-5 / release gate N≥50** (`WT_FULL_ISA_SWEEP` 이 release gate 로 지정된 선례와 동형) |
| **크기** | 미결. lane 수(32)와 fragment 경계를 **둘 다 걸치는** 최소 크기여야 한다 — 예: 입력 32 → hidden 32 → 출력 4. 32 미만이면 zero-padding 이 들어가고 MEAN 의 sum/N≠sum/K bias 규칙(§23.6a)에 걸린다 |
| **⚠️ 함정** | golden MLP 가 **RTL 과 같은 저자·같은 commit** 이면 §23.10.9-6 이 경고한 same-author 순환이 된다. `fp_release_sweep.py` 가 ml_dtypes 로 하는 것과 같은 **독립 oracle** 이 필요 — 최소한 forward pass 는 `ml_dtypes.bfloat16` + numpy 로 독립 구현해 교차검증할 것 |

#### TP-2 — canonical-order serial-equivalence (§23.4 항목 5)

| | |
|---|---|
| **잡는 것** | FP_LANES 를 바꿨을 때 누산 순서가 달라져 비트가 바뀌는 것. **가장 조용한 실패** — 결과는 항상 멀쩡한 fp32 |
| **구조** | 같은 입력 벡터를 FP_LANES ∈ {1, 2, 4, 8} 로 elaborate 한 빌드에 흘리고 **결과 비트가 전부 동일**함을 확인. 추가로 각 결과가 **golden 의 canonical 32-lane balanced 5-level tree** 와 일치 |
| **선행 조건** | `golden_fp32.py` 에 **`ref_acc_tree32` 가 없다** (실측 — 존재하는 것은 단일 fused scalar op 인 `accew`/`ref_acc_elemwise` 뿐). 이 참조 구현이 **TP-2 의 blocking 선행 작업**이다 |
| **TLA+ 와의 분업** | TLA+ 는 "임의 interleaving 에서 ⊕-tree 가 canonical 과 동형" 을 준다(§1.3). TP-2 는 "그 트리가 그 비트를 낸다" 를 준다. **둘 다 있어야 §23.4-5 가 성립** |
| **비용 주의** | FP_LANES 4개 × 전체 회귀 = 시뮬 시간 4배. **권고: per-commit 은 {2, 8} 2점, release gate 에서 4점 전수** |

#### TP-3 — ACC bank ownership / aliasing directed tests

| | |
|---|---|
| **잡는 것** | silent-gradient-corruption 클래스 전체 (§23.7-3) |
| **구조** | **TLA+ 모델의 불변식에서 직접 유도한다** — 이것이 formal-first 의 실질적 배당이다. TLC 가 반례를 내면 그 반례 trace 가 곧 directed test 의 시나리오다 |
| **최소 시나리오** | (i) write-write alias: 서로 다른 identity 가 같은 bank 에 순차 누산 → **loud fault** 여야 함(§3.5-1). (ii) zero race: 소유자 누산 중 타 identity 의 FP_ACC_ZERO. (iii) spill/fill alias: 타 identity 의 FILL 이 live partial 을 덮어씀 (**cross-context leak** 이기도 함). (iv) short drain: K 개 중 j<K 만 도착한 상태의 drain. (v) same-cycle free-then-reallocate (v1.9 §26.5 가 실제로 겪은 형태) |
| **선례** | v1.9 의 `test_bank_tag_collision_interlock`, `test_mu_busy_reject_no_phantom_row` 가 정확한 템플릿 — **sticky 상태 비트를 관측하는 테스트**이지 `$error` 를 세는 테스트가 아니다 |
| **⚠️ 구조적 한계** | **INV_Complete("K 개 전부 도착했을 때만 drain")은 오늘 하드웨어로 검사 불가능하다** — `dec_*` bus 에 fragment 수가 없다(§23.6a SDK 계약 1 이 같은 노출면). TLA+ 에서는 ghost 변수로 모델링하고, **"이 불변식은 현재 하드웨어에서 강제 불가"를 명시 기록**할 것. 기록하지 않으면 TLA+ 가 증명한 것보다 강한 것을 증명했다고 오독된다 |

#### TP-4 — SR reproducibility

| | |
|---|---|
| **잡는 것** | §2.3 Q1-Q5 의 실패, 특히 Q3(FP_LANES 별 lane_index 의미 변화)와 Q5(drain 주체에 따라 RNG key 가 바뀜) |
| **구조** | R1/R2/R3 (§2.3 Q4) 3층을 각각 테스트로: **R1** rnd=0 회귀 무변경(기존 STORE_QUANT 테스트 재실행), **R2** 같은 (프로그램·데이터·시드) 를 서로 다른 run/FP_LANES/part 에서 실행 → bit-identical, **R3** rnd=0 vs rnd=1 차분이 non-empty |
| **추가** | **통계 테스트는 golden 에서만** — lane 쌍별 상호상관, 반올림 기댓값 unbiasedness. RTL 은 golden 과 bit-match 만 보이면 된다(§23.10.5 독립-oracle 규칙의 정신) |
| **선행 조건** | golden 에 SR 이 **전무**(§2.4) — counter-based RNG 참조 구현이 blocking |

#### TP-5 — per-operator synth gate 확장 (기존 7-step 절차 재사용)

| | |
|---|---|
| **잡는 것** | 면적/Fmax 회귀를 **merge 전에**. v1.8.0b 가 5 commit 동안 놓쳤던 종류(§4.1) |
| **신규 gate 후보** | `FP_MulNarrow11` (11×11→22), `FP_FmaLane` (곱 + wide adder + per-lane classify), SR RNG 코어 |
| **⚠️ 예측 (중요)** | `WT_USE_DSP` 는 **yosys 에서 no-op** 이다(`include/attributes.vh:47`) — fp_mul36 의 4 MULT18X18D 는 순수 yosys 추론이다. 11×11 은 yosys ECP5 DSP 추론 임계 아래일 가능성이 높아 **ECP5 gate 는 MULT 0 + LUT4 수백** 을 보고할 것이고, Vivado 의 `(* use_dsp = "yes" *)` 는 DSP48E2 를 강제할 수 있다. **두 fabric 이 개수가 아니라 종류에서 갈린다** → fp_mul36 식 "정확히 N MULT" 핀은 **잘못된 도구**다. **`MULT ≤ FP_LANES` + LUT4 상한**의 2-축 기준으로 사전 공표할 것 |
| **절차 준수** | STEP 0 은 **측정 전 spec 에 수치 기준 사전 공표**다(§23.10.7 교훈). 측정하고 나서 기준을 쓰면 gate 가 아니다 |
| **Vivado 측 부재** | `synth/scripts/` 에 `common.tcl`/`synth_pod.tcl`/`impl_pod.tcl` 뿐이고 tree 전체의 `synth_design -top` 은 `-top Pod` 하나다 → **per-operator Vivado gate 는 신규 도구 작업**(§5.2) |

### 4.4 상대 공수 추정 — ⚠️ **추정이며 실측 아님**

측정 근거가 없는 항목이므로 **추정임을 명시**한다. 근거는 (a) v1.8.0c/0d/0e 에서 관측된 테스트-대-RTL 비, (b) 각 군의 선행 작업 유무다.

| 작업 | RTL 공수 (상대) | 검증 공수 (상대) | 비 | 근거 |
|---|---|---|---|---|
| bf16/f16 FMA lane | 1.0 | 1.5 | 1.5× | golden 참조가 **이미 있다**(`ref_fma`+`ref_widen_bf16`, §2.4) — 신규 산술 커널 불요 |
| canonical-order tree + fold | 1.5 | **4.0** | **2.7×** | `ref_acc_tree32` 신규 + FP_LANES 4구성 × 전체 회귀 + TLA+ 정합 |
| ACC bank + ownership | 2.0 | **5.0** | **2.5×** | TLA+ 선행(별도 공수) + directed test 5종 + 하드웨어 강제 fault 경로 |
| SR | 1.0 | **3.0** | **3.0×** | golden 에 **전무** — RNG 참조 + 통계 sweep + 3층 재현성 |
| 0x7D / 0x7E | 1.0 | 1.5 | 1.5× | 인코딩 확정 후에는 기존 stub→real 패턴 |
| Adam 매크로 | 0.5 | 1.5 | 3.0× | datapath 신규 없음(§1.4) — 전부 조립·대조 |
| **합계** | **7.0** | **16.5** | **≈2.4×** | |

**결론: §23.7 리스크 5 의 "검증 > RTL" 진술은 본 추정으로 지지된다** — 초과 폭은 대략 **2-2.5배**이며 "약간 초과" 가 아니다. 그리고 이 표에는 **TLA+ 모델링 자체와 Vivado per-operator gate 도구 신규 작성이 빠져 있다** (둘 다 Stage-4/도구 공수로 별도).

**공수 절감이 가능한 유일한 정직한 축**은 **per-commit / release-gate 이원화**다 — 이미 이 repo 의 확립된 패턴이다(`WT_FULL_ISA_SWEEP=1` = release gate, per-commit 은 equivalence-class 축약; §23.8). TP-1 의 N, TP-2 의 FP_LANES 점수, TP-4 의 통계 sweep 크기가 전부 이 축에 올라탄다.

---

## 5. 갱신된 risk register — 2026-08-13 cross-vendor 실측 반영

### 5.1 리스크 1 (ECP5 multiplier 여유 = 0) — **fabric-specific 으로 재진술**

**원문**: "모든 HW 비용이 문헌 추정 — repo 자신의 Vivado 35-DSP vs yosys 123-MULT18X18D 괴리가 증명하듯, per-operator FloPoCo + yosys/nextpnr synth 가 예산 확정 전 hard gate. **v2.0 의 ECP5 multiplier 여유는 사실상 0.**" (§23.7-1)

**실측 (본 메모가 직접 읽은 값)**:

| geometry / fabric | MULT18X18D 또는 DSP | 출처 |
|---|---|---|
| **Pod 2×2×2×2 / ECP5 LFE5U-85F** (2026-07-16) | **497 / 156 = 3.2× 초과** | `synth/lattice/reports/pod_2x2_2x2_synth.rpt`, §23.8 |
| **Cluster 단독 / ECP5** (v1.9b, 2026-07-27) | **103 / 156 = 66%** — **53 여유** | `synth/lattice/reports/cluster_v19b_pnr.log` |
| **Pod 2×2×2×2 / xcu55c** (2026-08-13) | **156 / 9,024 = 1.7%** | `synth/reports/pod_2x2_2x2_impl_util.rpt` |

**재진술 (권고)**:

> 리스크 1 의 per-fabric 판정: (a) **ECP5 단일 Cluster — 문장 그대로는 거짓.** 103/156 으로 **53 개 여유**가 있고, lane 당 narrow 곱셈기는 GATE F1 실측 **1개** (MULT18X18D 1, `fp_fmalane_bf16_synth.rpt`) 이므로 **곱셈기가 FP_LANES 를 2 로 제한하지 않는다** — 곱셈기 축의 한계는 **53 lanes** 다. (b) **ECP5 Pod — v2.0 이전부터 이미 배치 불가.** Pod 2×2×2×2 는 곱셈기 기준 497/156 = 3.2× 초과 — v2.0 가 만든 사실이 아니라 v2.0 과 무관하게 성립해 있던 실측이다. (c) **UltraScale+ — non-issue.** Pod 전체가 DSP 156/9,024 = **1.7%** 사용. **따라서 "ECP5 multiplier 여유 0" 은 v2.0 lane 수의 근거로 인용해서는 안 된다.**

**그 결과 C5 (FP_LANES=2) 의 근거가 비어 있고, GATE F1 실측이 착지한 지금은 자원 산술을 단위를 섞지 않고 할 수 있다.** ⚠️ **단위 규율**: lane 당 비용은 **placed nextpnr TRELLIS_COMB = 1,350** (`synth/lattice/reports/fp_ops/fp_fmalane_bf16_pnr.log`) 이지 yosys LUT4 cell 수(924, `fp_fmalane_bf16_synth.rpt`)가 **아니다** — nextpnr 는 LUT4 와 CCU2C carry 를 COMB site 로 packing 하므로 두 수는 다른 단위이고, free COMB 을 LUT4 cell 수로 나누면 lane 당 비용을 **~46% 과소평가**한다. 같은 단위(TRELLIS_COMB/TRELLIS_COMB)로 계산하면: free COMB = 83,640 − 33,089 = **50,551** → 50,551 / 1,350 ≈ **37 lanes COMB-bound** (MULT 축은 53/1 = 53 lanes). 즉 **raw 자원 여유는 ~37 lane 을 허용한다** — 그러므로 FP_LANES=2 의 근거는 자원 부족이 될 수 없고, 남는 근거는: (i) **routing congestion** — ECP5 Cluster 는 TRELLIS_COMB **39%** (33,089/83,640, 실측) 에서 이미 라우팅이 포화다(cross-vendor §3: 라우팅 지연 68%, logic level 117, Fmax 11.34 MHz); 즉 **비어 있는 COMB 이 사용 가능한 COMB 이 아니며**, 이것이 ~37 이라는 산술적 상한이 실제로는 도달 불가능한 이유다. (ii) ACC bank / partial-sum 저장 — 32-lane 트리를 2-lane 으로 접으면 level-1 partial 을 최대 16개 들고 있어야 한다. (iii) Pod 이 애초에 안 들어가므로 Pod 기준 lane 수는 무의미. **권고 문구: "FP_LANES=2 는 단일-Cluster ECP5 검증 vehicle 에서 congestion-bound 한계이며(곱셈기 부족도, raw LUT 부족도 아님 — 산술은 ~37 lanes 를 허용), 신규 per-operator gate 로 확인 대상"** — 그리고 이는 cross-vendor §3.2 의 ECP5 재포지셔닝과 정합한다.

### 5.2 리스크 2 (어떤 타깃에서도 timing 데이터 없음, 100 MHz 미증명) — **절반 닫힘, per-fabric 재진술**

**원문**: "어떤 타깃에서도 timing 데이터 없음 (base pod 조차 nextpnr PnR 미완). 5-6-stage fused FMA @100MHz 미증명 — **v2.0 첫 마일스톤은 Fmax 산출**." (§23.7-2)

**실측**:

| | ECP5 LFE5U-85F | xcu55c-fsvh2892-2L-e (= F2 실리콘, **보수적 -2L**) |
|---|---|---|
| Pod 2×2×2×2 Fmax | 배치 불가 (MULT 497>156, COMB 101%) | **~98 MHz** (WNS **-0.205 ns** @ 100 MHz) |
| Cluster 단독 Fmax | **11.34 MHz** (실측, v1.9b) | — |
| logic levels | 117 | 48 |

**재진술 (권고)**:

> 리스크 2 의 전제("어떤 타깃에서도 timing 데이터 없음")는 **더 이상 참이 아니다**. 동일 RTL 이 ECP5 11.34 MHz / UltraScale+ ~98 MHz 로 **8.7배** 갈리며, ECP5 수치는 fabric 특성(DSP48 부재 + 라우팅 자원 빈약)에 지배된다(cross-vendor §3). 따라서:
> - **ECP5 Fmax 를 v2.0 의 성능 게이트로 쓰지 않는다.** ECP5 는 FOSS 검증 vehicle 이다(cross-vendor §3.2). ECP5 에서의 Fmax 는 **회귀 탐지용 상대 지표**로만 쓴다.
> - **100 MHz 계약의 판정 fabric 은 UltraScale+ 다.** 현재 -2L 에서 **-0.205 ns 부족**이고 실제 F2 는 -2(고속)이므로 100 MHz 충족이 유력하나 **미측정**이다.
> - **⚠️ 이것이 v2.0 의 실질 리스크로 남는 이유**: 현 여유가 **0.205 ns 적자**다. v2.0 은 여기에 fused-FMA lane · ACC bank · 그 주소 디코드를 **추가**한다. 즉 **v2.0 은 음(-)의 timing 예산에서 출발한다.** "첫 마일스톤은 Fmax 산출" 이라는 §23.7-2 의 지시는 유효하며, **fabric 을 xcu55c 로 지정**해서 유효하다.

**Stage-4 산출물 2 착지 (본 메모 초고 이후 실측 — 같은 commit 의 형제 산출물)**: bf16 FMA lane per-operator gate 가 **양 fabric 에서 실행·PASS** 됐다. 수치는 fabric 별 **단위가 다르므로** 절대 같은 단위인 것처럼 병치하지 말 것 (예: FP_AddWide 는 ECP5 에서 894 **LUT4 cell**, xcu55c 에서 617 **LUT site** 인데 이 둘은 mapper 도 단위도 달라 크기 비교 증거가 아니다):
- **ECP5 GATE F1** (`synth/lattice/reports/fp_ops/gate_summary.txt`): LUT4 cell **924** / placed TRELLIS_COMB **1,350** / MULT18X18D **1** / Fmax **42.53 MHz** — PASS. §5.1 의 lane-수 산술은 **placed COMB 1,350** 쪽을 쓴다 (단위 규율 참조).
- **xcu55c GATE F1-US** (`synth/reports/fp_ops/gate_summary.txt`): LUT site **776** (cell 935) / DSP48E2 **1** / **255.30 MHz** (WNS +6.083 ns); **xcu50** cross-check **221.73 MHz** — 둘 다 PASS. **DRC 는 "clean" 이 아니라 "0 errors, 2 warnings"** 다 (`*_impl_drc.rpt`): **DPOP-4** (DSP MREG=0 — 곱셈기 출력 미파이프라인; MREG 를 켜면 **공짜 Fmax 상승 여지**가 있다는 뜻이므로 v2.0 파이프라인 재조정 시 후보로 기록) + **RTSTAT-10** (OOC top 출력 32 net 무부하 — out-of-context 러닝의 구조적 산물).

**미측정으로 남는 것 (정직하게 pending)**:
- Pod-level `xcu50-fsvh2104-2-e` / `-3` 실행 — speed-grade 정합 상한값. **미실행**(cross-vendor §7; 위의 xcu50 실측은 FMA lane 단독 gate 뿐이다).
- full Pod (4×4 cluster) geometry — **미측정**.
- ECP5 seed 1-5 sweep — 전 5세대 ECP5 수치가 `seed=1` 단발. 11.34 MHz 의 잡음 폭 **미확정**.

### 5.3 리스크 3 (ACC bank / silent-gradient-corruption) — **변경 없음, 단 Stage-4 로 활성화**

§23.7-3 그대로 유효하며 **완화되지 않았다**. 유일한 변화는 **도구가 확보됐다**는 것이다: TLC `/usr/bin/tlc`, `tla2tools.jar` `/usr/share/java/tla2tools.jar` (parent 검증). **Apalache 는 미설치** → 모델은 **TLC-checkable(유한·소형 상수)** 여야 하며, 이 제약이 §1.3 의 "숫자 대신 uninterpreted ⊕" 인코딩을 사실상 강제한다. 본 메모 초고 시점 `proofs/` 트리는 repo 에 없었고, **형제 산출물 1 (`proofs/tla/`) 로 같은 commit 에 착지**했다 — WaveTensor 계열 **최초의 TLA+ 산출물**이며 형제 repo `/home/ybi/Y4` 의 `proofs/{coq,isabelle,verus}` 관례를 따라 `proofs/tla/` 로 둔다.

### 5.4 리스크 5 (검증 > RTL) — **격상**

§4.4 의 추정으로 **약 2.4배**가 뒷받침됐다. 게다가 원문의 나열("~16 opcodes, fused-FMA pipe, NR step-sequence, SR, ACC state, canonical-order equivalence")에 **빠진 항목 2개**를 추가한다: **TLA+ 모델 자체의 작성·유지**, **Vivado per-operator gate 도구의 신규 작성**(§4.3 TP-5). 즉 리스크 5 는 과소평가돼 있었다.

### 5.5 리스크 6 (포지셔닝: training-capable ≠ training-competitive) — **재지정 필요**

§23.5 가 "속도 주장은 **Stage-2 Avant G70** (v2.1) 부터" 라고 못 박았는데, cross-vendor §5 가 **Avant G70 을 폐기**했다(리드타임 52주, 1년차 $6,476 + 이후 $3,142/yr, PCIe Gen3, F2 부품 대비 3-5배 작음). **따라서 "Stage-2" 라는 지시어의 대상이 비었다.** v2.0 COMMIT 0 에서 재지정할 것. 유력 후보는 **xcu55c/xcu50 (무료 Vivado 경로)** 이며, 이는 하드웨어 구매 없이 도달 가능하다는 점에서 이전 계획보다 강하다.

### 5.6 신규 리스크 — 도구 라이선스 (⚠️ 절대 위반 금지)

**Vivado 2025.2 를 업그레이드하지 말 것.** 2025.2 가 **마지막 라이선스-프리 릴리스**이고, 2026.1 부터 BASIC 조차 툴 실행 시점에 FLEX 를 요구하며 **Alveo 계열이 BASIC 에서 제외**된다. 업그레이드하면 §5.2 의 UltraScale+ 측정 경로가 **소멸**한다 — 그리고 그 경로가 v2.0 의 유일한 성능 판정 fabric 이다(§5.2). `/opt/Xilinx/2025.2.1` (81 GB) 은 **만료되지 않는 자산**이며 디스크 정리 시 보존 대상. 상세: cross-vendor §4.2.

---

## 6. sequencing 제안 + go/no-go

### 6.1 원칙

1. **spec-first.** 모든 계약은 RTL 이전에 §23.x 에 착지한다 (v1.8.0a 의 3-commit staging 이 확립한 패턴, §23.9).
2. **formal-first.** ACC bank 는 TLA+ 가 RTL 을 선행한다 (§23.7-3, wavetensor-drivers 관례).
3. **gate-first.** per-operator synth gate 는 **merge blocker** 이고, 기준 수치는 **측정 전에** 공표한다 (§23.10.7 의 normative 교훈).
4. **loud, never silent.** 새 architectural state 의 계약 위반은 합성 가능한 sticky 상태 비트로 노출한다 (§26.5 선례).

### 6.2 제안 순서

| # | 단계 | 산출물 | 선행 |
|---|---|---|---|
| **S0** | **Stage 4 완료** (본 메모 = 산출물 3) | ① `proofs/tla/` ACC bank 모델 + TLC 통과, ② bf16 lane pre-synth gate (ECP5 + UltraScale+ 양쪽) Fmax/면적 실측, ③ 본 메모 | — |
| **S1** | **v2.0 COMMIT 0 — spec 선행** | §23.x 신규 절: 내부 wide 포맷 폭 pin(§1.2), RNE 횟수 판정 A/B(§1.2), ACC bank ownership 계약 본문(TLA+ 결론 전사), SR 계약(§2), 0x7D/0x7E 계약(§3), FP_LANES 근거 재작성(§5.1), 리스크 1·2 per-fabric 재진술(§5) | S0 전부 |
| **S2** | **golden model 선행** | `ref_acc_tree32` (canonical 32-lane 5-level tree), SR counter-based RNG 참조, `ref_fma_bf16`/`ref_fma_f16` wrapper + operand-load 정책 pin, ACC bank 상태 oracle. **독립 oracle(ml_dtypes) 교차검증 포함** | S1 |
| **S3** | **FMA lane RTL** + TP-5 gate | `FP_MulNarrow11` + `FP_FmaLane` (per-lane classify 포함) — `FP_AddWide` 는 **재사용**(§1.2) | S1, S2 |
| **S4** | **canonical-order fold** + TP-2 | 32-lane 트리의 FP_LANES 접기, serial-equivalence 테스트 | S3 |
| **S5** | **ACC bank RTL** + TP-3 | S0-① 의 불변식을 **하드웨어 강제 loud fault** 로 구현; directed test 는 TLC 반례에서 유도 | S4 (fold 가 bank 를 요구하므로 실제로는 S4 와 얽힘 — 분리 가능성은 S1 에서 판정) |
| **S6** | **0x7D / 0x7E** | 인코딩 loosening (imm16[7:4], absent=lower_required) + spill/fill + FP_ACC_ZERO + **FP_STATUS sticky flag** (§23.10.9-8 종결) | S5 |
| **S7** | **SR** + TP-4 | rnd=1 합법화는 STORE_QUANT 에서만; R1/R2/R3 3층 | S2, S6 |
| **S8** | **Adam 매크로** + **TP-1 training-epsilon** | 신규 datapath 없음. TP-1 이 **v2.0 의 최종 acceptance** | S7 |

**순서의 근거 3가지**: (a) S2 를 RTL 앞에 두는 이유 — golden 이 없으면 TP-2/TP-4 를 쓸 수 없고, 이는 §4.4 에서 가장 큰 검증 항목 2개다. (b) S5(ACC bank)를 S3/S4 뒤에 두는 이유 — **누산 fold 가 bank 를 요구하는 것이지 그 반대가 아니다**; bank 를 먼저 만들면 무엇을 담을지 모르는 채로 만들게 된다. (c) S6(0x7D/0x7E)를 S5 뒤 — spill/fill 과 zero 는 **bank 가 존재해야 의미가 있고**, 실제로 v1.8.0b 가 stub 을 유지한 사유가 정확히 "no accumulator exists" 였다.

### 6.3 Stage 4 다음의 hard gate — **GATE V20-1 (bf16 FMA lane pre-synth)**

§23.7-2 의 "v2.0 첫 마일스톤은 Fmax 산출" 을 이 gate 가 이행한다. **기준 수치는 gate 실행 전에 spec 에 공표해야 한다** (§23.10.7 교훈) — 본 메모는 기준을 **제안**할 뿐 확정하지 않는다.

**제안하는 gate 형태 (2-fabric)**:

| 축 | ECP5 (FOSS 검증 vehicle) | UltraScale+ xcu55c (성능 판정) |
|---|---|---|
| 도구 | yosys `synth_ecp5` + nextpnr-ecp5, `--out-of-context`, LFE5UM-85F CABGA381 -6 (기존 `synth_fp_ops.sh` 그대로) | Vivado 2025.2.1, **신규** `synth/scripts/synth_fp_op.tcl` — `-mode out_of_context`, `-verilog_define WT_VENDOR_VIVADO=1`, **route_design 까지** |
| 곱셈기 | **MULT18X18D ≤ FP_LANES** (0 도 PASS — LUT 매핑) | **DSP48E2 ≤ FP_LANES** |
| 면적 | LUT4 상한 — 사전 공표 (기존 gate 관례: fp_addwide 900, fp_stepseq 4909) | LUT 상한 — 사전 공표 |
| Fmax | ≥ 40 MHz (기존 fp_ops gate 의 관례값) | **≥ 100 MHz** — 이것이 진짜 계약 |
| 왜 2-fabric 인가 | 같은 Cluster RTL 이 yosys 103 MULT18X18D vs Vivado 39 DSP48E2 로 **2.6배** 갈린다(실측). 한쪽 수치가 다른 쪽을 예측하지 않는다 | |

**⚠️ gate 설계상의 함정 (§4.3 TP-5 재게)**: 11×11 은 yosys ECP5 DSP 추론 임계 아래일 가능성이 높다 → ECP5 는 MULT 0 을 보고할 수 있고 Vivado 는 DSP48E2 를 강제할 수 있다. **"정확히 N MULT" 핀(fp_mul36 Gate 1 의 형태)은 여기서 잘못된 도구다.** 상한(≤)으로 쓸 것. 이 repo 는 이미 같은 결론에 도달한 적이 있다 — §25.7 리스크 3 이 "**yosys DSP-inference drift** (C6 선례: legacy cone +1 MULT)" 를 등재하면서 **pin form 을 "ceiling + unit-증명 delta" 로 두어 설계상 ±1 drift 를 관용**하게 했다. v2.0 의 fabric 간 격차는 ±1 이 아니라 **종류가 다른** 수준이므로 ceiling form 이 더욱 필요하다.

**신규 Vivado gate 작성 시 함정 3개**: (i) `synth/constraints/pod.xdc` 재사용 불가 — `set_false_path -from [get_ports rst]` 가 있는데 fp_ops 코어는 **의도적으로 reset-free** 다 → `create_clock` 만 있는 최소 xdc 신규 필요. (ii) `PART` 를 항상 명시 — `Makefile:91` 기본값은 `xczu3eg-sfvc784-1-i`(~71K LUT). (iii) 신규 Makefile 타깃은 `$(PWD)` 가 아니라 **`$(CURDIR)`** — `Makefile:84` 에 이미 그 버그가 있다(`:140` Lattice 쪽은 올바름).

### 6.4 go / no-go 기준

**Stage 4 → v2.0 COMMIT 0 진입 (S0 → S1)**

| # | 기준 | 판정 |
|---|---|---|
| G1 | `proofs/tla/` ACC bank 모델이 **TLC 로 통과**하고, 불변식 집합이 §23.7-3 의 silent-gradient-corruption 클래스를 **명시적으로** 커버 | **필수** |
| G2 | 모델이 **강제 불가능한 불변식을 명시 표시**했다 (예: INV_Complete — §4.3 TP-3) | **필수** — 표시 없으면 과잉주장 |
| G3 | GATE V20-1 이 **양 fabric 에서 실행**되고 수치가 archive 됐다 | **필수** |
| G4 | UltraScale+ 에서 FMA lane 이 **≥100 MHz** | **필수 (조건부)** — 미달 시 no-go 가 아니라 **파이프라인 단수 재설계**로 되돌아감 (v1.9 가 dispatch 파이프라이닝으로 한 것과 동형). 단 **미달을 미달로 기록**할 것 (§26.6 이 Fmax FAIL 을 정직 기록한 선례) |
| G5 | 반증 항목 3개(free-running LFSR, 8-bit/correlated-lane, per-pe-acc)가 **사유와 함께** spec 에 기록됐다 | **필수** — 본 메모 §2.2/§3.5 를 전사 |
| G6 | §1.2 의 RNE 횟수 판정(A per-step vs B per-dot)이 **사용자 결정으로 확정** | **✅ CLOSED (2026-08-15)** — 옵션 3 채택으로 종결 (§1.2 RESOLVED 블록, spec §27.1): dot 내부 반올림 0회 + bank store RTO-48 1회 + drain RNE-24 1회; `FP_AddWide` 48-bit 무수정, Gate 2 영구 폐쇄 |
| G7 | ACC bank ownership 이 **하드웨어 강제인지 SDK 규율인지** 사용자 결정 | **필수** — §3.5-2 |

**v2.0 전체 → release (S8 완료)**

| # | 기준 |
|---|---|
| R-A | **TP-1 training-epsilon 이 bit-for-bit 통과** (§23.4-6). 이것이 v2.0 의 존재 증명이다 |
| R-B | TP-2 가 FP_LANES 4구성 전수에서 bit-identical (§23.4-5) |
| R-C | TP-3 의 aliasing 시나리오 5종이 전부 **loud fault** 를 낸다 (silent 수용 0건) |
| R-D | TP-4 R1/R2/R3 3층 통과 — 특히 **R1 (rnd=0 회귀 무변경)** |
| R-E | 기존 279 cocotb + 138 asm 이 **무회귀** |
| R-F | `make lint` + isa freshness 통과 |
| R-G | 0x7E FP_STATUS 착지로 §23.10.9 리스크 8 이 **닫혔다** |
| R-H | GATE V20-final: full v2.0 Cluster 가 xcu55c 에서 **WNS ≥ 0** (§5.2 의 음(-)예산 출발 문제 해소 증명) |

---

## 7. 사용자 결정이 필요한 열린 질문

본 메모는 아래를 **의도적으로 미결로 남긴다**. 임의 결정이 나중에 breaking change 를 만드는 항목들이다.

1. ~~**RNE 횟수 (§1.2 C3)** — (A) per-step 6회(GPU 통상, 기존 실측 자산 보존) vs (B) per-dot 1회(§23.1 문자 그대로, `FP_AddWide` 48-bit 재검토 유발). **G6.**~~ **✅ RESOLVED (2026-08-15, 사용자 결정 — spec §27)**: 옵션 3 wave-step-atomic accumulation — (A)/(B) 양자택일이 아닌 in-dot exact lattice (dot 내부 0회 + bank RTO-48 1회 + drain RNE-24 1회). "(A) 6회" 표기는 깊이/이벤트 혼동 오류였음 (올바른 값 32회/dispatch — §1.2 정정 블록). G6 종결.
2. **ACC bank ownership 이 하드웨어 강제인가 SDK 규율인가 (§3.5)** — §26.8 이 마지막 SDK 규칙을 삭제하고 하드웨어로 대체한 방향, 그리고 SDK 계약이 하드웨어에서 감지 불가하다는 §23.6a 사실은 **하드웨어 강제**를 가리킨다. 그러나 비용이 측정되지 않았다. **G7.**
3. **bank selector arity (§1.3)** — `pcid[1:0]` 은 4 값인데 bank 는 2 개다. bank 를 4 개로? `bank = pcid[0]`? 2:1 사상 + collision fault? **TLA+ 모델이 세 안을 비교할 수 있으나 선택은 설계 결정이다.**
4. **drain opcode (§3.5)** — 0x72 ACC_REDUCE / 0x7C STORE_QUANT / 0x7D SPILL 중 미지정. **SR key 귀속(§2.3 Q5)과 얽혀 있어 독립적으로 고를 수 없다.**
5. **SR 시드의 거처 (§2.3 Q2)** — 신규 architectural register(0x7E sub-op)가 유력하나, tag namespace 확장 금지 규율과 imm16 점유 상황을 고려한 판단 필요.
6. **"Stage-2" 지시대상 재지정 (§5.5)** — Avant G70 폐기 이후 v2.1 속도 주장의 근거 부품이 비었다. xcu55c/xcu50 무료 경로가 유력.
7. **0x7D 의 "frag FSM untouched" 재검증 (§3.2)** — 이 문구는 2-bit/4-fragment 시절 작성됐고 §25.3 이 16-fragment 로 확장했다. 여전히 참인가?

---

## 8. 부록 — 본 메모가 직접 실측한 값 (2026-08-15)

추정과 구별하기 위해 분리 기재한다. 아래는 전부 **repo 파일을 읽어서 얻은 값**이다.

| 값 | 출처 |
|---|---|
| cocotb 279 / asm 138 | `grep -h '@cocotb.test' test_*.py \| wc -l`; `grep -h "def test_" asm/test_wavetensor_asm.py \| wc -l` |
| ECP5 Cluster v1.9b: MULT18X18D **103/156**, TRELLIS_COMB **33,089/83,640 (39%)**, TRELLIS_FF **10,607/83,640 (12%)**, Fmax **11.34 MHz** | `synth/lattice/reports/cluster_v19b_pnr.log` |
| xcu55c Pod: LUT **170,850**, DSP **156** | `synth/reports/pod_2x2_2x2_impl_util.rpt` |
| fp_ops gate 3종: fp_mul36 LUT4 **72** / MULT **4** / **134.34 MHz**; fp_addwide LUT4 **894** / MULT **0** / **41.08 MHz**; fp_stepseq LUT4 **4,721** / MULT **4** / **40.37 MHz** — 전부 PASS | `synth/lattice/reports/fp_ops/gate_summary.txt` |
| GATE F1 (ECP5, 형제 산출물): fp_fmalane_bf16 LUT4 cell **924** / **placed TRELLIS_COMB 1,350** / MULT **1** / **42.53 MHz** — PASS. ⚠️ 924 (yosys cell) 와 1,350 (nextpnr placed site) 는 **다른 단위** — lane-수 산술(§5.1)은 1,350 을 쓴다 | `synth/lattice/reports/fp_ops/gate_summary.txt`, `fp_fmalane_bf16_pnr.log` (`TRELLIS_COMB: 1350/83640`) |
| GATE F1-US (UltraScale+, 형제 산출물): xcu55c LUT site **776** / DSP48E2 **1** / **255.30 MHz**, xcu50 **221.73 MHz** — PASS. DRC **0 errors / 2 warnings** (DPOP-4 MREG=0, RTSTAT-10) — "clean" 아님 | `synth/reports/fp_ops/gate_summary.txt`, `*_impl_drc.rpt` |
| `golden_fp32.py` 의 `stochastic` 매치 **0회** | `grep -ci stochastic scripts/golden_fp32.py` |
| golden 함수 존재: `ref_fma` :295, `micro_fscalar` :562, `ref_widen_f16` :620, `ref_widen_bf16` :642, `ref_narrow_f32` :665 | `grep -n` |
| 0x7D/0x7E 의 `stub_v18: true`, `forbid_imm_any: true`, `require_precision_eh: true`, 0x7E 는 `forbid_mem: true` | `isa/wt64v1_isa.json` code 125/126 |
| `proofs/` 트리 — 초고 시점 부재, **형제 산출물 1 로 착지** (`proofs/tla/`, 같은 commit) | `ls /home/ybi/WaveTensor/proofs/tla` |
| bf16 FMA lane per-operator gate — 초고 시점 부재, **형제 산출물 2 로 착지** (위 GATE F1 / F1-US 행) | `ls synth/lattice/reports/fp_ops/`, `ls synth/reports/fp_ops/` |
| Vivado per-operator flow — 초고 시점 부재, **형제 산출물 2 로 착지** (`synth_fp_op.tcl` + `fp_op_gate_check.py`) | `ls synth/scripts/` |

**추정으로 명시한 것**: §4.4 의 공수 배수 표 전체, §3.2 의 "quarter = 256 bit", §2.2 의 반증 사유 재구성, §5.1 의 lane 당 자원 산정. 그 외 §1 의 인용문은 전부 `wt64v1_spec.md` 원문 전사다.
