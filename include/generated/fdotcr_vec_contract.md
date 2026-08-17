<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# fdotcr_vectors.hex — FDOT32_CR (0x7A) golden EFT 벡터 계약

생성기: `scripts/golden_fdotcr.py` (stdlib-only, 고정 seed, 재실행
byte-identical). 규범 출처: wt64v1_spec.md **§27.7a** (값 계약 §27.7a.1 /
알고리즘 §27.7a.2 / invariant §27.7a.3 / 검증 계획 §27.7a.5). 이 벡터가
3a-C3 (FP_StepSeq OPS_FDOTCR unit TB) / 3a-C4 (통합 TB dual-run) 의
directed 입력이다.

## 1. 라인 형식

`$readmemh`, 주석 3줄 + 450 라인. 1 line = 1 dispatch = 272 hex chars =
1088 bits, MSB-first:

| 필드 | 폭 | 위치 (MSB 기준) | 의미 |
|---|---|---|---|
| META | 32 | [1087:1056] | 아래 §2 |
| OPERANDS | 1024 | [1055:32] | `dec_input_payload_wide[1023:0]` — §3 |
| RESULT | 32 | [31:0] | 기대 fp32 결과 (MU 결과 fragment 하위 32b) |

## 2. META

| 비트 | 의미 |
|---|---|
| [31:24] | family code (§6 표) |
| [23:16] | special lane 수 (포화 255) |
| [15:9] | 0 예약 |
| [8] | special flag — 1 이면 기대 결과 = canonical qNaN `0x7FC00000` **이고 전용 sticky 발화가 기대된다**; main path 대조는 §5 |
| [7:0] | dtype — `0x2` f16 / `0x3` bf16 (§23.6a 의 2행 그대로) |

## 3. OPERANDS — A||B 연접 16-fragment (§27.7a.1)

`payload[1023:0]` 에서 fragment `f` = `payload[64*f +: 64]`. **frag 0-7 =
A 의 32×16b, frag 8-15 = B 의 32×16b.** fragment 내 lane 배치는 단일
packing pin (`golden_fp32.lanes_to_frags`, lane_bits=16) 그대로: fragment
`f` 는 lane `4f..4f+3` 을 담고 lane `j` 는 word 의 `[16*(j mod 4) +: 16]`.
즉 lane `i` 의 A operand = `payload[16*i +: 16]`, B operand =
`payload[512 + 16*i +: 16]`.

## 4. reference 의미론 (RTL 이 미러링할 단계 분해)

1. **classify (S1)** — bf16 exp field 0 → canonical zero 기여 (DAZ);
   f16 subnormal → leading-one normalize 후 exact 기여; NaN/Inf (sNaN
   포함, Inf×0 포함) → 전용 sticky + 결과 qNaN `0x7FC00000` (§27.7a.1).
2. **STEP M** — exact significand 곱 (bf16 8×8→16b / f16 11×11→22b,
   FP_Mul36 재사용), p_exp 합 signed-11, 반올림 0회.
3. **STEP T (TwoSumExact)** — vacuous-RTO 1 AddWide pass: 정렬 span ≤ 48
   → 48-bit 창 exact 합 + 24|24 field-slice split (hi+lo == s); span >
   48 → pass 없음 (큰 쪽, 작은 쪽). 오차항 없음 (RN 전제 정리 무의존).
4. **STEP I (grow-expansion)** — 비겹침 오름차순 열 (용량 33) 에 곱
   32개를 **lane 순서로** 순차 삽입; 용량 초과 = loud fault. walk =
   **정련 walk "최저 2개 순서 merge"** (§27.7a.2a amendment-2 정식 pin —
   원문의 chain 독해는 비겹침 invariant 를 스스로 위반하므로 폐기).
5. **STEP F (descending fold)** — **내림차순** RTO-48 fold (최상위
   component 부터; pass = FP_AddWide PACK_WIDE). §27.7a.2a
   amendment-1 — 원 pin "ascending" 은 3a-C1 실측이 부정했다 (값 계약
   반례 2건, 상대오차 24%). RTL 은 이 방향을 반드시 미러링해야 한다:
   삽입 단계와 융합한 스트리밍 오름차순 fold 는 **금지** (재발 경로).
6. **STEP P (PACK_FINAL)** — 단일 unbounded RNE-24 + flush-after-round
   FTZ + overflow ±Inf + exact-cancellation +0.

값 계약: RESULT == `pack_signed(exact Σ a_i·b_i)` — 본 파일 전 라인이
그 비트-동일성을 재검증한 산출물이다 (report `checks.value_contract`).
RESULT 필드는 **언제나 값 계약 우변**이며 EFT 산출물이 아니다: emit 은
`bits != ref_bits` 를 loud fault 로 거부하고, self-verify 는 EFT 에
무의존한 Fraction 경로로 전 라인을 재확인한다 (자기확인 루프 차단).

invariant 대조 범위 (공시): 값 계약을 받는 **전 trial** (본 파일 수록분
포함, 가족 제외 0) 이 **같은 operand** 로 main path twin
(`golden_lattice.wave_step`) 과 bit-equal 대조를 받는다 — §27.7a.5 (c)
의 "동일 operand 전 벡터 전수" 문언 이행. 가족별 카운트는 report 의
`checks.invariant_sweep.by_family` 에 공시한다.

## 5. special 라인의 main-path 대조 (§27.7a.3)

special flag=1 라인에서 audit (본 벡터의 RESULT) = qNaN + sticky. main
path 같은 operand 는 special lane 을 canonical zero 기여로 두고
`LANE_SPECIAL` sticky + wave writeback 억제 — **대조 축은 값이 아니라
sticky 유무다** (main 의 억제된 drain 산출 클래스는 finite/±Inf/±0 뿐,
NaN 불산출 — report `checks.special_contrast` 가 실증). special-set 시
값 비교 금지.

## 6. family 표

| code | family | start | count | doc |
|---|---|---|---|---|
| 0 | det | 0 | 20 | 손계산 고정점 directed — tie/q-경계/FTZ/overflow/정확상쇄/DAZ/f16 subnormal/전부동일 (§27.7a.5 (b)) |
| 1 | eft_bf16_wide | 20 | 30 | 전 지수역 임의 bf16 쌍 (±0/DAZ subnormal 산재) — cwave_bf16_rand 관례 |
| 2 | eft_f16_all | 50 | 30 | f16 전 클래스 (normal/subnormal 0.2-0.3/±0) — cwave_f16_rand 관례 |
| 3 | eft_cancel | 80 | 30 | X, -X + 수십 binade 아래 dust — 대규모 상쇄 (cwave_cancel) |
| 4 | eft_cancel_chain | 110 | 30 | greedy top-8bit canceller 연쇄 — 대규모 상쇄 후 미세 잔차 (fold 적대) |
| 5 | eft_tie | 140 | 30 | 24-bit RNE tie 인접 + bit-48 아래 dust (bf16 1+2^-24, f16 1+2^-24 subnormal 경유) |
| 6 | eft_ladder | 170 | 30 | exponent ladder 2^-252..2^255 급, gap 49-52 — expansion 최대 깊이 + 동일 지수 클러스터 |
| 7 | eft_same | 200 | 30 | 전부동일 32쌍 — 동일 곱 32회 삽입 carry/split 체인 |
| 8 | eft_pack_edge | 230 | 30 | PACK_FINAL 경계 — overflow ~2^128 / FTZ ~2^-126 / 정확 상쇄 +0 |
| 9 | eft_adv_residue | 260 | 30 | 단위 잔차 (±1) 상단 + 48-경계 gap mid + dust — fold 창-하강 표적 공격 (삽입 순서 3종) |
| 13 | eft_top_cancel | 290 | 30 | C1 반례 메커니즘 표적 (신설): 8-bit 블록 사슬로 top=E0 인 24-bit component + 2^(E0-48) 아래 tail (jam 강제) + 마지막 lane 2개로 순수 -2^E0 (상단 인접 상쇄). 폐기된 ASC pin 은 여기서 정리를 상시 위반한다 — 가족별 실측률은 report 의 checks.asc_detection_rate_by_family 참조 |
| 12 | c1_regress | 320 | 2 | 3a-C1 이 폐기된 ASC fold pin 하에서 실측한 값 계약 반례 2건 — 영구 회귀 벡터. RESULT = 값 계약 우변 pack_signed(exact); ASC 로 회귀하면 즉시 FAIL 한다. |
| 10 | special_det | 322 | 104 | NaN/Inf 전 행 directed — qNaN/sNaN/±Inf × A/B × lane {0,17,31} × 배경 {zeros,normals} + Inf×0/NaN×0/양측/전-lane (§27.7a.1 (iii)) |
| 11 | special_rand | 426 | 24 | 임의 배경 + 임의 special 주입 1-5 lane (payload NaN/부호/±0 짝 포함) |

## 7. seeds (고정 — 결정론의 유일한 난수원)

| key | seed |
|---|---|
| `eft_bf16_wide` | `0x7ADC001` |
| `eft_f16_all` | `0x7ADC002` |
| `eft_cancel` | `0x7ADC003` |
| `eft_cancel_chain` | `0x7ADC004` |
| `eft_tie` | `0x7ADC005` |
| `eft_ladder` | `0x7ADC006` |
| `eft_same` | `0x7ADC007` |
| `eft_pack_edge` | `0x7ADC008` |
| `eft_adv_residue` | `0x7ADC009` |
| `eft_top_cancel` | `0x7ADC00A` |
| `invariant` | `0x7ADC011` |
| `special_rand` | `0x7ADC012` |
| `fold_synth` | `0x7ADC013` |
| `special_det_bg` | `0x7ADC014` |
| `spec_literal_walk` | `0x7ADC015` |

## 8. 카운트 (report 와 동일)

EFT 값-계약 trial 57022 (0 mismatch 의무) / invariant trial 57022 /
special trial 600. 상세·sha256 은 `fdotcr_golden_report.json`.
