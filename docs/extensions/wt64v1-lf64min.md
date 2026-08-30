<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# WT64v1 확장 명세 — `Lf64min` (f64 최소 지원) · 초안 v0.1

> ### 지위 — 확장 명세 초안 v0.1
>
> 이 문서는 base 정본(`docs/wt64v1-architecture-guide/`)에 **종속**하며 충돌 시
> base 가 이긴다. 이 문서는 **`Lf64min` 확장의 계약 원천**이다.
>
> 계보: 2026-07-16 사용자 결정(「f64 → 별도 optional 확장 `Lf`, 완전 컷 아님」
> — base 는 dtype `0x5` 를 예약) → `.claude-memos/lf_extension_split.md`
> (2026-08-28, `Lf` ⇒ `Lf64min`/`Lf64di` 분할 — 사용자 승인) → 설계 →
> 적대 검증(조건부 채택 — 골격 성립, 수리 지시 C-1~C-8) → 이 문서.
> 검증이 반증한 문장(「P ≥ 18 확정 · progMem 배가 확정」)은 싣지 않았고,
> 수리 지시는 전부 반영했다.
>
> 인용 규약: base 인용에는 **규범 라벨을 병기**한다. 좌표(파일:행)는 작성 시점
> 값이고 문서는 움직인다 — authority 는 라벨이다.
>
> **opcode 표기 규약** (`.claude-memos/opcode_width_expansion.md`, 채택
> 2026-08-28 · 같은 날 인코딩 개정 파도로 base 이관 완료 — base §1.3.1):
> opcode 는 12b 정식 표기로 적는다. **이 확장의 신설 opcode 는 0 이므로 이
> 문서의 opcode 는 전부 base 인용이고, 그것도 `0x074`·`0x07A` 처럼 세
> 자리다** (영역 `0x0##`, 확장 니블은 기본 헤더 `[11:8]`). **수치는 종전 8b
> 표기와 동일하다** (`0x07A == 0x7A`).
>
> **2자리로 남는 것은 opcode 가 아니다** — 이 문서에는 폭이 다른 두 종류가
> 나란히 산다: **mode(정밀도) 바이트**는 8b 필드이므로 `0x14`·`0x15` 처럼
> 두 자리로 적고(§0 · §4.3), dtype 코드점은 한 자리(`0x5`)다. 세 자리를
> 보면 opcode, 두 자리를 보면 mode 바이트다 — 이관 후 이 문서 본문에 남은
> 두 자리는 **전부** mode 바이트이지 이관 누락이 아니다 (예외는 바로 위
> 등식 `0x07A == 0x7A` 하나 — 그것은 규약 진술이다).
>
> fp 블록 게이트는 12b 확장 시 확장 니블 `== 0x0` 검사가 함께 필요하다(같은
> 메모 §3-5 공허 PASS 함정 — W2). 이것은 `Di` 와 공유하는 base 개정 전제다.

---

## 0. 확장의 형태 — 확정 요약

**`Lf64min` = fp 블록 14행 중 5행에 dtype `0x5`(f64)를 더하는 것, 그것이
전부다.** 신규 opcode **0** · 신규 EH **0** · 신규 dtype 코드점 **0**
(`0x5 f64_reserved_Lf` 는 base 가 이미 예약한 자리의 claim 이다 — JSON
`dtype_codes` 실측) · 신규 명령 형태 **0**.

| 축 | 확정 |
|---|---|
| 범위 | **5행 in / 9행 out** — `0x074 FSCALAR` · `0x075 FRSQRT32` · `0x076 FEXP2_32` · `0x077 CVT` · `0x079 FMINMAX` 에 dtype 5 추가. 합법 (opcode,dtype) 행 26 → **31** |
| f64 합법 mode byte | **`0x15` 유일** (rnd=0 `[7:6]` · acc=1 `[5:4]` · dtype=5 `[3:0]` — JSON `mode_byte_fields` 실측 재계산) |
| 태그 충돌 | **없음** — base 합법 정밀도 바이트는 `{0x10..0x14, 0x16, 0x17}`, `0x15` 는 미사용 (실측). 결속 키 = 태그(정밀도 포함)라 조각열 문맥도 갈린다 |
| beat/조각 | f64 스칼라 = **정확히 64b 한 조각** (조각=64b 실측 — DEQUANT desc "128b, 2-frag" · FDOT32_CR desc "16-frag 1,024b" · `Reassembly.scala:139` `bodyW=64`) |
| 집행 기구 | **어셈블러 프로파일 (갈래 (a))** — §3. 신규 계약 계수는 **~7건** (§3.3), 「인코딩 0 신설」과 별개로 정직하게 센다 |

「인코딩 0 신설」은 참이다. 「계약 0 신설」은 거짓이다 — 둘을 섞지 않는 것이
이 문서의 셈법이다 (§3.3).

---

## 1. 손-핀 개정 목록 — 전수

base 의 「dtype 0x5 = f64/Lf-reserved illegal **everywhere**」 는 생성기
독립의 손-핀 불변식이다 (`fp_block._doc` 원문 — "hand-pinned in tests,
generator-independent"). 이 확장의 착지는 그 핀의 **프로파일-조건부 완화**이고,
움직여야 하는 실물은 아래가 **전수**다 (grep 전수 — 독립 검증 2회 일치.
「다른 dtype-5 리터럴 핀은 asm 측에 없다」).

| # | 실물 | 현행 | 개정 |
|---|---|---|---|
| 1 | `isa/wt64v1_isa.json` `fp_block._doc` | "dtype 0x5 = f64/Lf-reserved illegal everywhere" | "illegal outside the `Lf64min` profile; `Lf64min` claims rows {0x074,0x075,0x076,0x077,0x079}" |
| 2 | `asm/test_wavetensor_asm.py:1740-1748` | 전 행 `assertNotIn(5, …)` | 프로파일 분기 — base 프로파일에선 원문 유지, Lf 프로파일에선 5행 한정 `assertIn` |
| 3 | `:1755-1779` | SPEC_ROWS 14행 + `total == 26` (`:1778`) | Lf 쌍둥이 표 신설 — `total == 31` (26+5) |
| 4 | `:1793-1804` | 등가 스윕 (14×256) | 프로파일 축 추가 |
| 5 | `:2419` · `:2436-2445` | 거절 사유표 `0x15: 'dtype 0x5 f64/Lf-reserved'` | Lf 프로파일에서 5행 한정 수용 |
| 6 | `scripts/golden_fp32.py:577-586` | dtype-5 거절 | 프로파일 분기 + f64 오라클 위임 |

부수 확정 둘:

- **생성기가 선행한다.** `scripts/gen_isa_tables.py` `validate()` 에는 dtype-5
  검사가 **없고**(실측 — 핀은 전부 생성기 밖), `_reject_unknown`(`:108-111`)
  때문에 신규 키(`lf_legal_dtypes`)는 생성기 개정 없이는 JSON 에 실리지
  못한다. 착지 순서는 §9 단계 1 이 진다. `FP_LEGAL_ROM` 4096b + `in_fp_block`
  게이트는 `:236-249`.
- **스테일 docstring 2건을 같은 파도에서 수리한다** (검증 C-7):
  `asm/test_wavetensor_asm.py:1794` "Exhaustive **13**x256" (실물 루프 14) ·
  `:1757` "**21** legal rows" (단언은 26). 실행 기준 수치(14×256 · 26)가
  옳다 — Lf 쌍둥이 표가 docstring 을 복제하면 거짓을 이식하므로, §9 단계 2 에
  docstring 수리를 동반 지시로 넣는다.

완화가 아니라 **신설**인 핀 셋 (§4·§5 의 규범을 테스트로 못박는 자리):

1. **DAZ-bypass 핀** — `NARROW_FROM_F32 × dtype5` 방향은 DAZ pre-stage 를
   우회한다 (§4.2, 검증 C-2).
2. **canonical qNaN 계열 핀** — f64 결과의 모든 NaN 생산 자리 =
   `0x7FF8_0000_0000_0000` (§4.4, 검증 C-5).
3. **f64 min_normal 상수 핀** — `0x0010_0000_0000_0000` (§7, 검증 C-4).

---

## 2. 범위 — 행 전수와 각 행의 규범

### 2.1 들어가는 5행

| opcode | 행 | f64 의미 | 비고 |
|---|---|---|---|
| `0x074 FSCALAR` | ×5 | FS_ADD · FS_SUB · FS_MUL · FS_DIV 의 f64 판 | **FS_FMA×5 = `lower_required`** (아래) |
| `0x075 FRSQRT32` | ×5 | f64 rsqrt | 성립 근거는 **`Lf64di` DRSQRT primal 의존 경제** 하나다 — desc 실물("fp32 rsqrt: LUT seed + 3 Newton iterations")은 f32 조율 규범이고, f64 행은 그 조율의 재선언이 아니라 별도 몸체/공유 판정(§6)을 진다 (검증 C-6 수리 문면) |
| `0x076 FEXP2_32` | ×5 | f64 2^x | 몸체는 **확실히 별도다** (§6) |
| `0x077 CVT` | ×5 | f64↔f32 변환 두 방향 | §4 전체가 이 행의 규범이다 |
| `0x079 FMINMAX` | ×5 | 2레인 f64 min/max | §5 |

**FS_FMA×5 는 `lower_required` 다.** f64 단일-반올림 FMA 계약은 이 확장이
사지 않는다 — lowering 은 MUL+ADD 두 발화로 펴고, 값은 그 두-발화 열
(각 RNE)이 정의한다. `Di` 의 FMA 예약(값-미러 구멍 보존, `wt64v1-di.md`
§4.1)과 같은 처분 부류다 — 기각이지 불가능이 아니므로 malformation 이 아니라
`lower_required` 가 옳다.

### 2.2 남는 9행 — 제외 근거

`0x070 VFMA_ACC` · `0x071 VDOT_ACC` · `0x072 ACC_REDUCE` · `0x073 ACC_ELEMWISE` ·
`0x078 DEQUANT` · `0x07A FDOT32_CR` · `0x07C STORE_QUANT` · `0x07D ACC_SPILL_FILL`
· `0x07E FP_ACC_CTRL`.

- **누산기 축** (`0x070`–`0x073` · `0x07D`) — f64 누산은 누산기 폭·spill 경로의
  전면 개정이다. 「최소」의 정의가 이 경계다.
- **양자화 축** (`0x078` · `0x07C`) — f64 소비자 0.
- **`0x07A` 리만 축약** — f32 조차 없다 (`legal_dtypes [2,3]` 실측). f64 는
  이 확장의 결손이 아니라 별건 결손이다 (`lf_extension_split.md` §1.2 —
  「리만은 범위 밖」).
- **`0x07E FP_ACC_CTRL`** — 행 추가 불요: sticky **기입**은 dtype 무관이라
  f64 연산의 IEEE 예외도 오늘의 그 워드에 오르고, **읽기** 발화는 dtype4 로
  이미 적법하다.

### 2.3 파도·beat 형태와 ISA-9 판정

- 스칼라 4행 (`0x074`/`0x075`/`0x076`/`0x077`): A = `payload_a` 64b 전폭
  (f32 는 `[31:0]` 저워드였다 — f64 는 전폭이 정확히 맞는다), B (이항) =
  `payload_b` 64b 전폭 (`0x079` 의 B 저워드 규약 `dec_input_payload_b[31:0]`,
  `golden_fp32.py:1156-1160` 의 f64 자연 확장). 출력 = 64b 단일 beat.
  **ISA-9 ②** (규범 「토큰 비증식 — 발화가 남기는 후속 전송 전량의 분할」,
  `01-isa-asm.typ:617-631` — ② 는 `:621`).
- `0x079 FMINMAX`: A = 2 f64 레인 128b **2조각 파도**, 출력 128b = 2조각 —
  f32 형("4 f32 lanes (128b = 2-fragment) … 128b out = 2 fragments", JSON
  desc)과 동형. **함정**: `0x079` 의 2조각 출력은 오늘 ACCTGT 선언 없이
  나간다 — W4(ACCTGT 승격) 착지 시 결속 규범(`04-ext-payload.typ:285-286`)과
  자기모순이 되는 **선행 충돌**이고, f32/f64 양쪽에 걸린다. 처분은 별건
  등재다 (`wt64v1-lf64di.md` §9 — 검증 A-1).

---

## 3. 프로파일 기구 — 갈래 (a) 확정

### 3.1 형태

어셈블러 표면 실측: `assemble(text)` 는 프로파일 인자가 없고
(`asm/wavetensor_asm.py:2467`), legality 는 `FP_MODE_LEGAL` 하나이며
(`:1762-1798`), mode byte 는 런타임 태그가 주도한다 (`input_tag[15:8]`,
`:1758-1759`). 확정 형태:

1. JSON 에 **`lf_legal_dtypes`** 키 신설 — base `legal_dtypes` 는 무변경
   (base 프로파일의 진리가 움직이지 않는 것이 이 갈래의 알맹이다).
2. 생성기가 **`FP_MODE_LEGAL_LF`** ROM 쌍둥이를 굽는다 — base ROM 과의
   델타는 5행 × dtype5 비트뿐.
3. 어셈블러에 프로파일 인자 신설 (`assemble(text, profile=...)`) — 기본값
   base, 종전 호출 전부 무변경 통과.
4. 손-핀 테스트의 프로파일-조건부 분기 (§1 표).

### 3.2 이 기구의 지위 — 기술 필연이 아니다

**프로파일 기구는 2026-07-16 사용자 결정(f64 → 별도 optional 확장)의
귀결이지 기술 필연이 아니다** (검증 C-8). 늘리지 않는 길은 실재한다 —
pre-stable recapture 로 base `legal_dtypes` 에 dtype5 를 직접 편입하면
§3.1 의 ①–④ 가 통째로 소멸하고, `prestable_compat_policy` 상 그것은 정규
이벤트다. 그 길을 막는 것은 그 사용자 결정 하나다. **해제(base 편입)는
릴리스 축 미결과 같은 자리에 산다** (§8 미결 1) — 이 문장이 없으면 프로파일
기구가 구조적 강제인 것처럼 읽힌다.

### 3.3 신규 계약 계수 — 정직한 셈

「신규 인코딩 0」과 별개로, 이 확장이 신설하는 계약은 **~7건**이다:

① `lf_legal_dtypes` 키 · ② `FP_MODE_LEGAL_LF` + ROM 델타 · ③ asm 프로파일
표면 · ④ 프로파일-조건부 불변식 · ⑤ CVT 방향-이름 규범 (§4.1) ·
⑥ FS_FMA×5 `lower_required` (§2.1) · ⑦ f64 qNaN 계열 핀 + DAZ-bypass 핀
(§4). ①–④ 는 §3.2 의 사용자-결정 귀결분이다.

### 3.4 재구현 — 처음부터 넣는다

`FP_LEGAL_ROM` · `in_fp_block` 은 재구현 트리(`rtl/spinal/`)에 **0건**이다
(grep 전수 — 독립 재실행 일치). 즉 재구현의 mode-legality 층은 아직 지어지지
않았고, 지을 때 **프로파일 형상 파라미터를 처음부터 넣는다** — base ROM 을
짓고 나중에 쌍둥이를 덧대는 갈래를 만들지 않는다.

---

## 4. `CVT × dtype5` — 두 방향의 규범

두 방향 모두 명령 mode byte = `0x15` 다. 이 절의 네 규범이 없으면 이 행은
착지할 수 없다 — 검증이 적발한 규범 결손(C-2 · C-3)과 계열 핀 결손(C-5)의
수리가 이 절이다.

### 4.1 방향-이름 규범

**방향의 authority 는 `cvt_op_codes` 값이지 이름의 어감이 아니다**
(`cvt_op_codes = {WIDEN_TO_F32: 0, NARROW_FROM_F32: 1}` — JSON 실측; dtype
니블이 비-f32 쪽을 이름한다):

- `WIDEN_TO_F32 × 5` = **f64 → f32** (실질은 좁힘),
- `NARROW_FROM_F32 × 5` = **f32 → f64** (실질은 넓힘 — 정확 주입).

dtype5 에서 이름의 어감이 역전된다 — 이 한 줄을 적지 않으면 구현자가 이름을
믿는다.

### 4.2 규범 — dtype5 방향은 DAZ pre-stage 를 우회한다 (신설 핀)

base 계열 처분 실측 (`golden_fp32.py:107-108, 64-65, 52-54`): DAZ 는
denormal **피연산자**를 적재 시 같은 부호 0 으로 접고, `ref_narrow_f32` 는
"DAZ pre-stage folded in"(두 RTL 지점 동일 핀), DAZ 우회는 **non-fp32** CVT
원천 한정이다. `NARROW_FROM_F32 × 5` 의 원천은 fp32 이므로 계열 승계대로면
DAZ 가 접힌다 — 그러면 f32 `0x00000001`(최소 subnormal)이 `+0` 으로 죽고,
왕복 f32→f64→f32 비트 정확성이 subnormal 8,388,606 개 × 2 부호에서 깨진다.

**핀 (신설)**: `NARROW_FROM_F32 × dtype5` 는 **DAZ pre-stage 를 우회한다 —
모든 f32 값(subnormal 포함)은 f64 로 정확히 주입된다.** f16 원천의
DAZ-BYPASS 선례(op-class-conditional capture pin)에 얹는다. 이것이 §3.3 ⑦
의 절반이다.

### 4.3 규범 — 결과 태그 정밀도 = 출력 형식

태그 정밀도 바이트가 mode byte 를 주도하고(`asm:1758-1759`) step 선택
열쇠가 (연산, 정밀도)이므로(`StepSequencer.scala:113-116`), 결과 파도가
생산 명령의 정밀도 바이트를 승계하면 `WIDEN_TO_F32 × 5` 의 f32 결과가
`0x15` 를 달고 하류에서 f64 프로그램·f64 폭을 선택시킨다. base 선례(I2F)는
dtype4 = f32 라 우연히 안전했을 뿐이다.

**규범 (신설)**: **CVT 결과 파도의 태그 정밀도는 출력 형식이다** —
`WIDEN_TO_F32 × 5` 결과 태그 = f32 계열(`0x14`), `NARROW_FROM_F32 × 5`
결과 태그 = `0x15`.

**착지 전건**: 결과 태그 형성의 실물은 clean-room 밖(참조 RTL)이라 이 문서
시점에 미측정이다 — §7 원장 4. 재구현이 태그 형성 층을 지을 때 이 규범이
설계 입력이다.

### 4.4 규범 — canonical qNaN 은 계열 전체다

base 는 「every NaN-producing case → canonical qNaN」을 계열로 핀한다
(`golden_fp32.py:110-112`). f64 판:

- **f64 결과의 모든 NaN 생산 자리 = `0x7FF8_0000_0000_0000`** — CVT 두
  방향·FSCALAR·FRSQRT·FEXP2·FMINMAX(6핀 3·4항 포함, §5) **계열 전체**.
- **`NARROW_FROM_F32 × 5` 의 NaN 입력도 canonical 이다 — payload 는
  보존하지 않는다.** 왕복 비트 보존은 계약이 아니다 (반례 기록:
  `0x7FC00001` 은 f64 왕복에서 `0x7FC00000` 으로 돌아온다). 보존-확장
  갈래는 기각 — base 계열 핀과 두 규칙이 되는 대가를 산다.

---

## 5. `FMINMAX × dtype5` — 2레인 동형

- A = 2 f64 레인 = 128b 2조각 파도 · 출력 128b 2조각 (§2.3).
- **키 정규화 (f64 판)**:
  `key64(a) = a[63] ? ~a : a ^ 0x8000_0000_0000_0000` — f32 키
  `a[31] ? ~a : a ^ 0x80000000` (JSON notes + `golden_fp32.py:1108-1118`)의
  64b 동형. −0 < +0 유지 등 f32 6핀 (`golden_fp32.py:1104-1169`)을 f64
  형태로 전부 승계하고, NaN 자리(6핀 3·4항)는 §4.4 계열 핀을 따른다.
- B = `payload_b` **64b 전폭** — f32 의 저워드 규약(`[31:0]`)이 f64 에서
  전폭으로 정확히 맞는다 (§2.3).
- **P 계상 밖** — FMINMAX 는 combinational arm 이고 step 시퀀서 접촉이
  0 이다 ("zero FP_StepSeq contact", JSON notes 실측). f64 판도 같다.

---

## 6. step 프로그램 · P — 몸체 공유가 설계 목표다

이 절은 검증 C-1 의 재작성판이다. 종전 서술(「P ≥ 18 확정 · progMem 배가
확정」)은 **반증됐다** — 자기 원장(「RSQRT NR 3 충분 vs 4 필요 미측정」)과
모순이었다.

### 6.1 확실한 것 하나 — EXP2 f64 몸체는 별도다

f32 FEXP2 는 차수 6 minimax (~2⁻²⁶ 급) — **2⁻⁵⁴ 에 수학적으로 도달
불가하다.** f64 는 차수 11~13 다항이 필요하고(차수 11 에서 ~2⁻⁵⁷ 산정 —
`Lf64di` 검증 세션 계산), 이는 step 수가 다른 별도 몸체다. **+1 은 확정이다.**

### 6.2 조건부인 것 — DIV·RSQRT f64 의 몸체 공유

- 실측: FRSQRT32 = 256×9 seed ROM + **3** NR (JSON `0x075` notes) ·
  `micro_div` 도 3회 (`golden_fp32.py:34, 479`). seed 2⁻⁹ 에서 NR 3회 배가 =
  명목 2⁻⁷² > 2⁻⁵⁴ — **f64 도 3회로 충분한 갈래가 실재한다.**
- 그 갈래에서 DIV·RSQRT 의 f64 몸체는 f32 와 반복 구조가 같고, 남는 차이는
  F-의존 상수(2^F · 3·2^(F−1))와 라운더 폭뿐이다 — 이것은 ADD/MUL/CVT 공유의
  관건인 **「프로그램 밖 정밀도 문맥」과 동일한 기구**다. 그 기구가 서면
  DIV·RSQRT 도 공유된다.
- **몸체 공유(정밀도 문맥화)는 이 확장의 설계 목표로 승격한다** — 공유
  성립이 곧 progMem 배가 회피다.

### 6.3 P 의 정직한 범위

| 구성 | P | slotW | progMem |
|---|---|---|---|
| `Lf64min` 단독 (base 10 + EXP2f64 1, 공유 성립) | 11 | 4 | 512 워드 — 무료 |
| `Di` 적층 (base 10 + dual 5 + EXP2f64 1, 공유 성립) — **최선** | **16** | 4 | 512 워드 — 무료 |
| 공유 불성립 (DIV·RSQRT·EXP2 + 문맥류 별도 몸체) — 최악 | ≤ 21 | 5 | **1024 워드 — 배가** |

실측 기준: `StepSequencer.scala:172-173` (P 기본 10 · stepMax 32) · `:183`
`slotW = log2Up(P)` · `:271-272` `progMem = 2^(slotW+pcW)`. `log2Up(16)=4`,
`log2Up(21)=5`. 「`Di` §1.3 의 P ≤ 16 무료 경계가 깨진다」는 공유 불성립
**갈래**의 서술이지 확정이 아니다.

원장 (§7): DIV f64 반복 수 · RSQRT f64 반복 수 — 둘 다 미측정 (「3 충분」은
명목 배가 산정이지 ulp 증명이 아니다).

---

## 7. f64 subnormal · DAZ/FTZ · 정확도 앵커 (검증 C-4)

base 는 형식별로 핀한다 (f16 정확/bf16 flush — COMMIT-0 pin 6 · FSCALAR
「DAZ/FTZ」 · FEXP2 「FTZ(RN_unbounded) underflow boundary」 · f32
min_normal `0x00800000` 상수 핀). f64 행의 처분:

1. **FSCALAR/FRSQRT/FEXP2 × 5 의 DAZ/FTZ 이월 여부는 사용자 미결이다**
   (§8 미결 2). f64 수요자(과학계산)는 정확히 gradual underflow 를 원하는
   집단이라 이것은 형식 이월로 조용히 정할 수 없는 실질 결정이다.
2. **`WIDEN_TO_F32 × 5` 는 f32 subnormal 결과를 낳는 최초의 CVT 경로다**
   (I2F 결과는 구조상 비-subnormal). f32-결과 계열 처분(FTZ)을 승계하면
   **(0, 2⁻¹²⁶) 전 구간의 f64 입력이 ±0 으로 접힌다** — 이 대가를 지불
   문면으로 명시한 채 승계할지, 이 방향만 정확 결과로 열지는 미결 2 의
   부속이다.
3. **f64 min_normal 상수 핀 = `0x0010_0000_0000_0000`** (신설 핀 — §1).
4. **정확도 앵커 이월** — f32 의 ≤2ulp normative 외에 **monotonicity
   normative** · RSQRT 「x=4^k bit-exact」 · EXP2 「integer bypass 2^n
   bit-exact」 (JSON `0x075`/`0x076` notes 실측)가 f64 행으로 이월되는지 —
   원장 6. 선언 없이 이월된 것으로 읽지 말 것.

---

## 8. 기각한 대안

- **base 직접 편입 (recapture)** — 기술로는 살아 있으나 (§3.2) 2026-07-16
  사용자 결정이 봉인한다. 기각이 아니라 **봉인**이고 해제는 미결 1 이다.
- **9행 전면 확장** — 누산기·양자화 축의 데이터패스 전면 개정을 소비자 실측
  0 인 채 산다 (§2.2). 「좁게 시작해서 넓히는 것은 언제나 가능하고 그 반대는
  불가능하다」 (§1.4.2 해설).
- **FS_FMA×5 실장** — f64 단일-반올림 FMA 몸체를 소비자 미측정인 채 산다.
  처분은 `lower_required` (§2.1) — 되살릴 때는 값-계약(단일 반올림)을 함께
  사야 한다.
- **NARROW×5 의 DAZ 승계** — §4.2 의 반례로 기각. **qNaN payload 보존-확장**
  — §4.4 로 기각.

---

## 9. 단계적 착지 경로 — 5단계

| 단계 | 내용 | 선행 |
|---|---|---|
| 1 | **생성기 개정** — `_reject_unknown` 에 `lf_legal_dtypes` 수용 + `FP_MODE_LEGAL_LF` ROM 방출 (`gen_isa_tables.py:103` `_FP_OP_KEYS` 포함) | 없음 |
| 2 | JSON `lf_legal_dtypes` 5행 + `_doc` 개정 + **손-핀 프로파일 분기 (§1 표 전수) + 스테일 docstring 2건 수리 (C-7)** | 1 |
| 3 | asm 프로파일 표면 (`assemble(profile=)`) + legality 이중화 | 2 |
| 4 | **golden f64 오라클** — §4 네 규범 + §5 key64 + §7 상수 핀을 그대로 구현. FAB-8 (비트 일치 golden 대조) 소비자의 전건 | 2 |
| 5 | 재구현 착지 — mode-legality 층을 프로파일 형상 파라미터로 신설 (§3.4) · 결과 태그 형성 층에 §4.3 규범 (원장 4 의 해소 지점) | 3–4 |

---

## 10. 미측정 원장 — 재지 않은 것 전수

**미측정은 통과가 아니다.**

| # | 항목 | 아는 것 |
|---|---|---|
| 1 | DIV f64 반복 수 (NR 3 충분 vs 4) | 명목 배가 산정만 (2⁻⁷² > 2⁻⁵⁴) — ulp 증명 0건 |
| 2 | RSQRT f64 반복 수 | 같은 지위 |
| 3 | **몸체 공유(정밀도 문맥화) 성립 여부** | 설계 목표 (§6.2). 성립 = P 16 무료 · 불성립 = P ≤ 21 progMem 배가 |
| 4 | 결과 태그 형성 실물 | clean-room 밖 (참조 RTL) — §4.3 규범의 착지 전건 |
| 5 | EXP2 f64 차수 (11~13) | 차수 11 ~2⁻⁵⁷ 산정 — 실측 0건. `Lf64di` 원장(DEXP2-f64 step)과 연동 |
| 6 | 정확도 앵커 이월 (monotonicity · 4^k · 2^n) | §7-4 — 방향만 안다 |
| 7 | f64 gradual underflow 의 데이터패스 대가 | 미결 2 의 전건 — 방향만 안다 |
| 8 | 제외 9행의 f64 수요 | 방향만 안다 (누산 축이 첫 후보) |

`Di` 원장 11 (「손-핀 완화가 움직일 생성기 밖 테스트 수 — 방향만 안다」)은
**이 문서 §1 이 좌표 전수로 닫았다.**

---

## 11. 미결 — 사용자만 답할 수 있는 것

1. **릴리스 축** — `Lf64min` 이 `WT64v1-C` 계열인가 `v2.x` 인가 (`Di` 미결 1
   과 같은 질문, `lf_extension_split.md` §4). **프로파일 기구의 해제(base
   편입, §3.2)가 같은 자리에 걸려 있다.**
2. **f64 subnormal 정책** — FSCALAR/FRSQRT/FEXP2×5 를 DAZ/FTZ 로 이월할
   것인가, gradual underflow 로 열 것인가 (§7-1). 부속: `WIDEN_TO_F32 × 5`
   의 f32 subnormal 결과 처분 (§7-2 — FTZ 승계면 (0, 2⁻¹²⁶) 전 구간 ±0 의
   대가).

역방향 강제 규칙(`Lf64min` ∧ `Di` ⇒ `Lf64di`)은 이 문서의 미결이 아니라
`wt64v1-lf64di.md` §6 의 미결이다.
