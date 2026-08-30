<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# 인코딩 델타 통지 — `wavetensor-sdk` 앞 (#33 · on-wire 원장 L13 의 이행)

> ### 📌 지위 — 이 문서가 **통지의 authority** 다 (2026-08-30)
>
> 형제 저장소 `/home/ybi/wavetensor-sdk` (Apache-2.0) 의 메모는 이 문서를
> **가리키기만** 한다. 사실이 어긋나면 **이 문서가 이긴다.**
>
> 다만 **인코딩 규범 자체의 정본은 이 문서가 아니다** — 정본은
> `docs/wt64v1-architecture-guide/chapters/01-isa-asm.typ` 이고, 비트-동등의
> 기준 실물은 `asm/wavetensor_asm.py` 다. 이 문서는 **그 둘 사이의 델타를
> 한 자리에 모은 통지**이며, 셋이 어긋나면 순위는 **정본 > 어셈블러 실물 >
> 이 문서** 다. 이 문서를 명세로 읽지 마라 — 통지로 읽고, 구현할 때는
> 좌표를 따라 실물을 열어라.

---

## 0. 이 통지가 정정하는 것 — 과제 서술 자체가 부정확했다

작업 큐 #33 은 「인코딩 파도로 **인코더가 비트-동등 기준에서 이탈**」이라
적혀 있었다. **실측 결과 그 전제가 틀렸다.**

**판정: 「이탈」이 아니라 「포팅 전 기준선 이동」이다.**

2026-08-30 실측 — `/home/ybi/wavetensor-sdk` 는 `.git` 을 뺀 파일 21개가
전부 문서·라이선스·메모리·에디터 설정이다. `crates/` 0 · `bindings/` 0 ·
`Cargo.toml` 0 · `.rs` 0 · `.py` 0. 커밋 2개(`6daae8a` scaffold ·
`c4d76e9` phase_plan). **Phase A 스캐폴드다.**

⇒ SDK 에는 **이탈할 인코더가 없다.** 정확한 문장은 이것이다:

> **Phase C 포팅이 시작되기 전에, 포팅 대상(Python 참조 어셈블러)의
> 인코딩이 개정됐다.**

SDK 는 아직 아무것도 잃지 않았다. 잃을 것이 생기는 시점은 **Phase C 착수**
이고, 이 통지의 목적은 **그 시점의 기준선을 미리 바꿔 놓는 것**이다.

**부수 판정 — 인코딩 파도 때문에 SDK 안에서 거짓이 된 문장은 0건이다.**
SDK 문서 어디에도 명령 길이·워드 수·EH 구조·헤더 비트 배치·truth table
파일명을 적은 자리가 없다(전수 grep: `416`/`448`/`word`/`bh_len`/`OPREF`/
`ACCTGT`/`CRC`/`opcode`/`truth_table`). 인용이 전부 「저 파일이 참조다」
수준의 **경로 지시**라서 파도에 면역이었다. **이 절제가 SDK 를 구했다** —
규범을 베끼지 않고 가리키기만 한 문서는 상류 개정에 부서지지 않는다.
Phase C 문서도 같은 절제를 유지하는 편이 낫다.

---

## 1. 비트 수준 델타 — 무엇이 불변이고 무엇이 변했는가

파도 전 어셈블러(`62889e5^`)를 실제로 꺼내 import 해 **양쪽을 함께 돌린**
실측이다. 재현 절차는 §6 에 있다.

### 1.1 컨테이너 — 13워드/416b → 14워드/448b

`asm/wavetensor_asm.py:88` 「INSTR_WORDS_REAL = 14」 ·
`asm/wavetensor_asm.py:89` 「INSTR_WIDTH_BITS = INSTR_WORDS_REAL * 32」.
내역은 `asm/wavetensor_asm.py:87` 「기본 헤더 1 + CH(둘째 헤더, EH ≥ 1 일 때만) 1 + EH 예산 12 (불변)」 다.
**EH 예산 12 는 움직이지 않았다** — 넓어진 것은 CH 한 워드뿐이다.

### 1.2 EH-0 명령 — **비트 불변** (실증)

```
NOP   old(13w/416b) = 0x1        new(14w/448b) = 0x1        int_equal = True
```

opcode ≤ 0xFF ⇒ 확장 니블 `[11:8]` = 0 · 예약 `[15:12]` = 0 ·
`next_hdr` = END ⇒ CH 없음 · `bh_len` = 1. **모든 유효 비트가 같다.**
컨테이너 폭만 13 → 14 워드로 넓어지고 word13 = 0 이다.

⇒ **기존 EH-0 바이너리는 파도를 건너 그대로 유효하다.**

### 1.3 EH ≥ 1 명령 — 델타는 **정확히 CH 삽입 + `bh_len` +1**

```
ADD .imm16 5
  old:  10200002  00050201
  new:  10200003  92B843A3  00050201
          ↑bh_len 2→3  ↑CH(word1 신설)  ↑EH 사슬 한 워드 우측 이동

.default_port dest=1 / ADD .imm16 5
  old:  10100003  00012101  00050201
  new:  10100004  2A4F180B  00012101  00050201
```

**델타의 외연 — 실측으로 닫힌다:**

1. word0 `[7:0]` `bh_len` **+1** (CH 포함 회계)
2. word1 에 **CH 32비트 신설** — 기존 word1‥ 이 전부 한 워드 우측 이동
3. **그 밖의 비트 불변** — opcode · `next_hdr` · flags · EH 본문 전부 그대로
4. OPREF 를 실은 명령은 **추가로** EH 워드 `[23:20]` 이 0(종전 엄격 예약)
   → CRC-4 값
5. `0x100`–`0xFFF` 확장 영역 opcode 는 **신설** — 종전 인코딩에 표현 자체가
   없었다 (델타가 아니라 순증)
6. ACCTGT(EH `0x9`)는 **어셈블러에 미실장** — §4 참조

---

## 2. 재현해야 하는 계약 — Phase C 가 비트-동등으로 맞춰야 할 전문

전부 `asm/wavetensor_asm.py` 실물 판독이다. 규범 대조는
`docs/wt64v1-architecture-guide/chapters/01-isa-asm.typ`.

### 2.1 기본 헤더 word0

```
[31:24]  opcode[7:0]
[23:20]  next_hdr      — 첫 EH 종류. 0x0 = END(EH 없음)
[19:16]  flags (4b)
[15:12]  예약 4b       — 항상 0 방출 (종전 예약 8b 를 니블로 협소화)
[11:8]   opcode[11:8]  — 확장 니블 (W1 신설)
[7:0]    bh_len        — CH 를 포함한 물리 워드 총수
```

실물은 `asm/wavetensor_asm.py:2110` 「base = ((opcode & 0xFF) << 24)」 부터
`asm/wavetensor_asm.py:2114` 「| (bh_len & 0xFF)」 까지의 다섯 줄이다.
확장 니블은 그 사이 `asm/wavetensor_asm.py:2113` 「| (((opcode >> 8) & 0xF) << 8)」.

- **opcode 는 12비트.** 공간 `0x000..0xFFF`. 초과 시 `AssemblerError`.
- 기존 opcode(≤ 0xFF)는 확장 니블 `0x0` 프리픽스 ⇒ `0x07B == 0x7B`.
  표기 규범은 **세 자리 hex `0x###`**.
- 명령은 word0 이 LSB 인 **리틀엔디언 워드 순서**의 단일 정수로 조립된다.
- 14워드 초과 시 `AssemblerError`. 부족분은 상위 워드에 0 패딩.

> **함정** — `bh_len` 의 *선언* 폭은 8비트지만 *비교* 폭은 형상 유도다.
> 종전 실효 최대 13, 현행 14. 8비트라고 읽고 255 를 받으면 안 된다.

### 2.2 `bh_len` 회계

실물 한 줄이다 — `asm/wavetensor_asm.py:2100` 「bh_len = 1 + (1 if has_ch else 0) + sum(len(words) for _, words in encoded)」.

```
bh_len = 1                                   # 기본 헤더
       + (1 if EH 가 하나라도 있으면 else 0)  # CH
       + Σ(각 EH 의 워드 수)
```

> **함정** — 확장 명세 셋이 워드 수를 적었는데 **둘은 CH 포함, 하나는
> 미포함**이었다. 워드 수를 인용하는 자리는 「CH 포함」 여부를 반드시 병기하거나,
> 아예 규범을 가리켜라.

### 2.3 CH (Castagnoli Header) — word1

**존재 유도** (별도 플래그 비트가 **없다**):

- word0 `next_hdr ≠ END` ⇔ word1 = CH
- `next_hdr == END` ⇒ CH 없음, `bh_len = 1`, 1워드 명령

실물 분기는 `asm/wavetensor_asm.py:2099` 「has_ch = bool(encoded)」 ·
`asm/wavetensor_asm.py:2119` 「ch = _ch_word([base] + chain_words)」.

**CH 는 EH 가 아니다** — 셋 다 못박아라:

- EH 슬롯 상한(12워드 예산)에 **계상되지 않는다**
- EH 사슬 순회 대상이 **아니다** — `[11:8]` 이 우연히 적법 EH 종류로 보일 수
  있다(오독 함정)
- 단 **`bh_len` 에는 포함된다.** EH 는 **word2 부터** 시작한다

**CRC-32C 파라미터** — 이것만 보고 구현할 수 있게 전부 적는다:

| 항목 | 값 |
|---|---|
| 다항식 | 정규형 `0x1EDC6F41` / 반사형 `0x82F63B78` |
| 반사 | **입력 반사 · 출력 반사** (refin = true, refout = true) |
| init | `0xFFFFFFFF` |
| xorout | `0xFFFFFFFF` |
| 관례 | RFC 3720 (iSCSI) |

실물 선언은 `asm/wavetensor_asm.py:1841` 「다항식 0x1EDC6F41(정규형)/0x82F63B78(반사형), 입·출력 반사」.

> **손구현 필수** — Python stdlib 의 `zlib.crc32`/`binascii` 는 다항식
> `0x04C11DB7`(ISO-HDLC)라 **쓸 수 없다.** Rust 도 마찬가지로 crate 를
> 쓸 때 Castagnoli 인지 확인해야 한다. `crc32fast` 는 ISO-HDLC 다.

**메시지 정의** — 틀리기 쉬운 자리다. 네 축 전부 못박혀 있다:

1. **범위** — CH **자기 워드를 제외한** 명령의 전 워드
   = word0, word2 … word(`bh_len` − 1)
2. **순서** — 워드 **오름차순**
3. **직렬화** — 각 32비트 워드를 **최하위 바이트부터(리틀엔디언) 4바이트**로 이음
4. **패딩 워드 불포함** — 메시지 길이는 정확히 (`bh_len` − 1) × 32 비트

실물 문면이 그대로 적는다 —
`asm/wavetensor_asm.py:1855` 「메시지 = CH 를 제외한 명령의 전 워드(word 0, word 2‥bh_len−1)를」 ·
`asm/wavetensor_asm.py:1857` 「워드를 최하위 바이트부터(리틀엔디언) 4바이트로 잇는다」.
직렬화 실물은 `asm/wavetensor_asm.py:1859` 「msg = b''.join((w & 0xFFFFFFFF).to_bytes(4, 'little')」.

**순서 규율 (W8)** — `asm/wavetensor_asm.py:2115` 「순서 규율 (W8): bh_len(CH 포함)·next_hdr 후패치가 완결된 **뒤에**」.
`bh_len`(CH 포함 값)과 `next_hdr` **후패치가 완결된 뒤**에 CRC 를 계산한다.
`_ch_word()` 는 패치 완료본을 받는다. **순서를 뒤집으면 조용히 다른 CH 가
나온다** — 시험이 없으면 못 잡는다.

**디코더 측 판정 순서**: word0 판독 → `next_hdr ≠ END` 면 word1 을 CH 로
→ word2 부터 EH 순회.

### 2.4 OPREF EH (종류 `0x7`, 1워드) — CRC-4

**워드 배치**:

```
[31:24]  LBID (8b)
[23:20]  CRC-4         ← W5 신설 (종전 엄격 예약 0)
[19:16]  src_kind (4b)
[15:12]  next_hdr      (사슬 후패치)
[11:8]   자기 EH 종류 (= 0x7)
[7:0]    이 EH 의 워드 수 (= 1)
```

실물 조립 두 줄 — `asm/wavetensor_asm.py:2045` 「upper = ((noc_route & 0xFF) << 8) | (crc << 4) | (src_kind & 0xF)」 ·
`asm/wavetensor_asm.py:2046` 「return EH_OPREF, [(upper << 16) | (EH_OPREF << 8) | 1]」.

**CRC-4 파라미터**:

| 항목 | 값 |
|---|---|
| 다항식 | `G(x) = x⁴ + x + 1` (`0b10011`) |
| 반사 | **비반사** |
| init | `0` |
| xorout | **없음** |

실물 선언은 `asm/wavetensor_asm.py:1821` 「G(x) = x⁴ + x + 1 (0b10011), 비반사, init 0, xorout 없음」.

**메시지 M = 논리 12비트** `LBID[7]…LBID[0] ∥ src_kind[3]…src_kind[0]`
(MSB-first). **물리 워드 슬라이스 순서(`[31:24]`·`[19:16]`)가 아니다** —
CRC 니블 `[23:20]` 이 물리적으로 둘 사이에 끼기 때문에 정본이 논리 순서를
명문화한다. **이 구분을 놓치면 값이 달라진다.**

반환 = `(M(x)·x⁴) mod G(x)`, 4비트. 방출 위치 `[23:20]`, **crc[3] 이 비트 23**.

> **사용자 주입 금지** — CRC 는 어셈블러가 계산·주입한다. 사용자 지정 통로를
> 열면 「잘못된 LBID 에 올바른 CRC」를 붙이는 경로가 된다. 어셈블러는
> `.opref port=` 를 거부하고, 시험 `test_opref_user_crc_injection_rejected`
> 가 그 거부를 고정한다. **Rust 포트도 같은 거부를 실장해야 한다** —
> 이것은 편의 기능이 아니라 은닉 채널 차단이다.

### 2.5 EH 사슬 후패치

끝에서부터 역방향으로 각 EH 워드0 의 `[15:12]` 에 **다음** EH 의 종류를
기입하고, 마지막은 END(`0x0`). 첫 EH 의 종류가 word0 `[23:20]` 으로
올라간다. SUBSCRIPT 는 축 수 5–8 이면 EH **두 개**로 분할 방출된다
(`_encode_subscript_eh_multi`).

### 2.6 EH 종류 코드 — `isa/wt64v1_isa.json` 의 `eh_codes` 실측

```
END 0 · PORT 1 · IMM16 2 · IMM32 3 · IMM64 4 · MEM 5
SUBSCRIPT 6 · OPREF 7 · PRECISION 8 · NOP_PAD 15
```

---

## 3. 자기시험 기지값 — 소재

### 3.1 CRC 기지값 7종

`asm/test_wavetensor_asm.py` 의 `TestCrcReferenceValues`.

**P1 — OPREF CRC-4** `(LBID, src_kind) → CRC`:

| LBID | src_kind | CRC |
|---|---|---|
| `0x00` | 0 | `0x0` |
| `0x01` | 1 | `0x6` |
| `0xA5` | 2 | `0x8` |
| `0xFF` | 2 | `0xA` |

**P2 — CH CRC-32C** (RFC 3720 시험 패턴):

| 입력 | CRC |
|---|---|
| `b"123456789"` | `0xE3069283` |
| `bytes(32)` (32 × `0x00`) | `0x8A9136AA` |
| `bytes([0xFF] * 32)` | `0x62A8AB43` |

교차 검증: CRC-4 는 본문 12b **전 공간 4,096점 전수** 교차일치,
CRC-32C 는 표본 교차일치.

> **규율 — 표를 옮기지 마라.** 본체(`wavetensor_asm.py`)는 비트직렬 LFSR /
> 반사 비트루프이고, 참조(`test_wavetensor_asm.py`)는 16b 부호어 장제법 /
> 256-엔트리 표다. **의도적으로 다른 형태**다. Rust 포트는 **3계통째 독립
> 구현**이어야 같은 버그를 세 벌 복사하는 경로가 막힌다. 표를 그대로
> 베끼면 이 규율이 죽는다 — 세 구현이 같은 기지값을 통과한다는 사실이
> 증거이지, 구현이 같다는 사실은 증거가 아니다.

### 3.2 비트-동등 corpus — **좌표를 정정한다**

**진짜 corpus 는 `asm/test_wavetensor_asm.py` 다.** 2026-08-30 실행 실측
**177 passed**. 어셈블러 표면 호출 `assemble(` 97회 + `assemble_one(` 18회.

**`test_isa_decoder.py` 가 아니다.** 실측: `encode_instr(` 170회 대
`assemble_one(` **3회**(`test_isa_decoder.py:1412` · `:1434` · `:1456`).
그 파일은 어셈블러 텍스트 프로그램 corpus 가 아니라 **손조립 비트벡터
corpus** 이며, **RTL 디코더 시험용**이지 어셈블러 비트-동등용이 아니다.

⇒ SDK 의 「corpus = `test_isa_decoder.py` 의 100+ 프로그램」은 **틀린
좌표**다. 고치지 않으면 Phase C 가 잘못된 corpus 로 착수한다.

다만 `test_isa_decoder.py` 는 다른 이유로 값지다 — 그 안의 `encode_instr()`
(`test_isa_decoder.py:187` 「def encode_instr(opcode, *exts, flags=0, force_bh_len=None,」)
가 W1/W8 을 반영한 **어셈블러와 독립인 2계통째 인코더**이고
`force_ch` 부정 시험까지 든다. Rust 포트는 **3계통째**가 된다.

### 3.3 truth table — **오라클 한정**

| 파일 | `domain_version` | points | ext_probes | 지위 |
|---|---|---|---|---|
| `isa/truth_table_encwave.json` | **4** | 5,934 | 207 | **현행** |
| `isa/truth_table_premigration.json` | 3 | 5,934 | — | **동결 · 이관 전 계보 전용** |

`rtl/README.md:28` 「**오라클로만** (현행 인코딩)」 — 통과/실패를 받는 것은
안전하나 **명세로 읽으면 오염**이다. **Rust 포트가 인코딩 규범을 truth
table 에서 역추출하면 안 된다.** 규범은 정본에서, 비트는 어셈블러에서 받아라.

`premigration` 쪽은 `rtl/README.md:29` 「**이관 전 계보 전용**」 이다 —
파도 이전 바이너리에만 답한다. Phase C 대조에 쓰면 안 된다.

### 3.4 생성기 사슬 — 표는 손으로 옮기지 마라

```
isa/wt64v1_isa.json  →  scripts/gen_isa_tables.py  →  asm/generated_isa_tables.py
```

신선도 게이트는 `scripts/lint_isa_tables_fresh.py` 다. **opcode 표는
`isa/wt64v1_isa.json` 에서 생성하라** — 손으로 옮기면 그 게이트가 SDK 쪽에
없어지고, 상류 표가 움직여도 조용히 낡는다.

---

## 4. 아직 미실장인 것 — ACCTGT (EH `0x9`)

정본 1.4.7 이 배치만 정의했다: `[31:24]` = 누산 대상 LBID 8b,
`[23:16]` = 조각열 선언 총개수 T 8b.

**어셈블러 표면은 미실장이다.** `isa/wt64v1_isa.json` 의 `eh_codes` 에
**`0x9` 가 없다**(§2.6 실측). on-wire 원장 L11 도 「미결(살아 있음)」로
세워 둔다 — `.claude-memos/onwire_format_spec.md` 의 L11 행이
「기준선 스냅숏에 `0x9` 방출 실물이 없다」 고 적는다.

⇒ **Phase C 포트가 ACCTGT 를 구현하면 현행 기준선과 비트-동등이 깨진다.**
**구현하지 않는 것이 정답이다.** Di 파도가 어셈블러에 실장한 뒤 lockstep 으로
따라가라. 그때 L11 의 「대조 재확인」이 함께 열린다.

---

## 5. 포팅 금지 목록 — legacy 복제 계약 소멸 (#27 원장 L12)

on-wire 원장 L12 가 **확정**했다 (2026-08-29): legacy 조각별 명령·EH 사슬
복제 계약이 **신정본에서 소멸한다.** 신정본 제시는 **1회**(부록 E.5.4
사이드밴드 원자 제시)이고, pre-stable 정책(동결 보증은 stable release 부터
발효)이 이 소멸을 **정규 이벤트**로 허용한다. ingress 재방출로 살려 두지
않는다.

**소멸하는 계약의 실제 거처는 WaveTensor 쪽 두 docstring 이다:**

- `asm/wavetensor_asm.py:2264` 「SDK CONTRACT (hardware-unenforced): the INSTRUCTION + full EH chain」
  — `wave_fragments_vdot()` (VDOT_ACC `0x71`, 4 조각)
- `asm/wavetensor_asm.py:2327` 「INSTRUCTION + full EH chain must be replicated on EVERY fragment —」
  — `wave_fragments_fdot32_cr()` (FDOT32_CR `0x7A`, 16 조각)

> **SDK 저장소에는 지울 문장이 없다.** 전수 grep(`vdot|fdot|fragment|조각|
> replicat|복제|v1.5`) → **0건**. 원장 L13 은 「SDK 의 v1.5.x 복제 계약을
> 건드린다」고 적었지만, **건드릴 문장이 거기 없다.** L13 의 위험 판단
> 자체는 옳다 — 통지 없이 포팅하면 죽은 계약이 Rust 로 **되살아난다.**
> 틀린 것은 「SDK 에 그 계약이 이미 있다」는 전제뿐이다.

⇒ 통지의 정확한 형태는 「고쳐라」가 아니라 **「포팅 금지 목록에 올려라」** 다:

**Phase C 에서 `wave_fragments_vdot()` · `wave_fragments_fdot32_cr()` 를
포팅할 때, 그 docstring 의 조각별 복제 계약을 함께 옮기지 마라.**

`wave_fragments()` 본체(순수 분할기)는 **계속 유효**하다. 죽는 것은
「전 조각에 명령을 복제한다」는 **상위 계약뿐**이다.

> **↔ 포팅 착수 전에 닫혀야 할 것이 이 목록 말고 하나 더 있다.** 어셈블러의
> **오라클 지위** 승계(정본 §0.3.1 오라클 넷 · `lint_guide_derived_tables` 의
> 진실 원천 · `lint_section_refs` hard 구역 래칫)가
> [`dev_platform_axis.md`](./dev_platform_axis.md) §4 에 미결로 등재돼 있다.
> **이 문서는 비트 델타의 authority 로 남고 지위 논의를 들이지 않는다.**

---

## 6. 재현 절차 — 이 통지의 §1 을 다시 재는 법

```
git show 62889e5^:asm/wavetensor_asm.py       > /tmp/prewave/wavetensor_asm.py
git show 62889e5^:asm/generated_isa_tables.py > /tmp/prewave/generated_isa_tables.py
```

두 트리를 각각 `sys.path` 앞에 놓고 `wavetensor_asm` 을 **번갈아 import**
하되, 사이에 `sys.modules` 에서 `wavetensor_asm`·`generated_isa_tables` 를
지워라(지우지 않으면 캐시된 파도-전 모듈이 재사용돼 델타가 0 으로 보인다).
`assemble()` 은 **정수 리스트**를 돌려준다 — 워드 분해는
`(v >> (32*i)) & 0xFFFFFFFF` 이고 `i` 상한이 양쪽에서 다르다(13 대 14).

파도 커밋: `62889e5` (asm·JSON) · `b27b68b` (정본) · `4a8da34` (RTL+formal) ·
`c682acd` (legacy + encwave 재캡처).

---

## 7. Phase C 착수 체크리스트

1. CRC-4 기지값 4종 + CRC-32C 기지값 3종을 **독립 3계통째 구현**으로 통과
   (표 복사 금지 — §3.1)
2. CRC-4 본문 12b **전 공간 4,096점**을 Python 참조와 교차 대조
3. **`asm/test_wavetensor_asm.py` 의 177 케이스**를 비트-동등 corpus 로 사용
   (`test_isa_decoder.py` 아님 — §3.2)
4. **EH-0 명령이 파도 전 바이너리와 비트 불변**임을 회귀로 고정 (§1.2)
5. **EH ≥ 1 델타가 정확히 CH 삽입 + `bh_len` +1 뿐**임을 회귀로 고정 (§1.3)
6. opcode 표는 `isa/wt64v1_isa.json` 에서 **생성** (§3.4)
7. truth table 은 **오라클로만** (§3.3)
8. **ACCTGT 를 구현하지 마라** (§4)
9. **조각별 복제 계약을 옮기지 마라** (§5)
10. `.opref port=` **거부**를 함께 포팅 (§2.4)

---

## 8. SDK 쪽에서 정정한 것 (2026-08-30, 형제 저장소)

인코딩 파도가 원인인 정정은 **0건**이다. 아래 넷은 **다른 축**에서 낡아
있던 것이고, 이 통지 파도가 함께 고쳤다.

| 자리 | 무엇이 낡았나 |
|---|---|
| `docs/architecture.md` §5 | 「cocotb 회귀 167/167」 — 실측 cocotb 총 **333**(decoder 214 · cluster 63 · hiu 22 · alu_extended 16 · pod 10 · top_core 8). asm 자체 시험은 **177** |
| `.claude-memories/wavetensor_sdk_asm_migration.md` | 같은 「167/167」 + **귀속 오류** — 어셈블러 비트-동등을 지키는 것은 `test_wavetensor_asm.py` 이고 cocotb 는 독립 계통이다. 「cocotb 가 asm 을 검증한다」는 참이 아니다 |
| 같은 메모 + `docs/phase_plan.md` C2 | corpus 좌표 「`test_isa_decoder.py` 의 100+ 프로그램」 → **틀림** (§3.2) |
| `docs/phase_plan.md` 열린 질문 | 「spec §22.17.1」의 **거처 이동** — §22 계열은 정본이 아니라 `.claude-memos/wt64v1_spec.md` 의 자기 절 번호다. 정본(`docs/wt64v1-architecture-guide/`)에 §22.17 은 0건이다 |

**경계 사례 — 정책 충돌 하나.** SDK 메모가 「Phase B–C 동안
`wavetensor_asm.py` 를 삭제·중대 변경하지 마라」고 적는데, 이 파도가 정확히
그 파일을 중대 변경했다. **위반이 아니라 정책 충돌**이다 — WaveTensor 의
pre-stable 정책상 pre-stable 개정은 **정규 이벤트**이고, SDK 메모는 그
정책의 존재를 몰랐다. SDK 쪽에 「pre-stable 동안 참조는 움직일 수 있다 —
움직이면 통지가 온다」는 단서를 붙였다.

**참으로 확인돼 정정하지 않은 것**: `phase_plan.md` C1 의 6-stage 파이프라인
이름 전수(parse → alias_pass → default_pass → macro_pass → legality_pass →
encode_pass)는 실물과 일치. `make_layernorm_abort_cleanup()` ·
`_layernorm_xc_slot_addressing()` 두 함수와 그 공유 계약도 실물 존재.
`docs/licensing.md` §3 의 triple-license 기술은 `asm/wavetensor_asm.py:1`
SPDX 헤더와 일치(`LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0`).

---

## 9. 관련 좌표

- `asm/wavetensor_asm.py` — 참조 어셈블러 (**비트-동등 기준 실물**)
- `asm/test_wavetensor_asm.py` — 비트-동등 corpus (177) + CRC 기지값
- `asm/generated_isa_tables.py` — 생성물 (**편집 금지**)
- `isa/wt64v1_isa.json` — 표의 단일 기계 소스
- `isa/truth_table_encwave.json` · `isa/truth_table_premigration.json`
- `test_isa_decoder.py` — RTL cocotb, 독립 `encode_instr()`
- `scripts/gen_isa_tables.py` · `scripts/lint_isa_tables_fresh.py`
- `docs/wt64v1-architecture-guide/chapters/01-isa-asm.typ` — **인코딩 규범 정본**
- `.claude-memos/onwire_format_spec.md` — L11 · L12 · L13 원장
- `.claude-memos/sdk_architecture.md` — SDK 관계의 역사 맥락
- `rtl/README.md` — truth table 오라클-한정 경고
- `/home/ybi/wavetensor-sdk/` — 형제 저장소 (문서 21파일, 실물 코드 0)
