<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# xchacha_vectors.hex — HIU 주소 마스킹 (표준 XChaCha20) 벡터 계약

생성기: `scripts/golden_xchacha.py` (stdlib-only, 고정 seed, 재실행
byte-identical). 규범 출처: **RFC 8439** (ChaCha20) + **draft-irtf-cfrg-
xchacha-03** (HChaCha20 §2.2 / XChaCha20 구성 §2.3 / 테스트 벡터 §A.3.2),
그리고 wt64v1_spec.md **§29.8** (HIU 가 XChaCha20 을 쓴다는 선언).

이 벡터는 **golden-before-RTL** 산출물이다 — RTL 수리보다 먼저 착지하며,
수리된 `HIU.v` 가 만족해야 할 값을 정의한다.

## 1. 라인 형식

`$readmemh`, 주석 3줄 + 80 라인. 1 line = 1 변환 = 360 hex chars =
1440 bits, MSB-first:

| 필드 | 폭 | 위치 (MSB 기준) |
|---|---|---|
| `META` | 32 | [1439:1408] |
| `KEY` | 256 | [1407:1152] |
| `NONCE` | 192 | [1151:960] |
| `PHYS` | 64 | [959:896] |
| `SUBKEY` | 256 | [895:640] |
| `BLOCK` | 512 | [639:128] |
| `MASK` | 64 | [127:64] |
| `MASKED` | 64 | [63:0] |

  * `KEY` / `NONCE` / `SUBKEY` 필드의 정수값은 **RTL 포트/레지스터 정수
    값 그대로**다 (`chacha_key` / `chacha_nonce` / `subkey`). 즉 워드 j 는
    `field[32j+31:32j]` 이고, 바이트열로는 little-endian 이다.
  * `BLOCK` 은 `CHACHA_FINAL` 시점의 `chacha_state[i] + initial_state[i]`
    16워드이며 워드 i 가 `BLOCK[32i+31:32i]` 다. RTL 은 워드 0/1 만
    소비하지만 나머지 14워드도 관측 가능하므로 **부분 수리 검출**을 위해
    전부 싣는다.
  * `MASK` = `{BLOCK[1], BLOCK[0]}` (상위 32b = 워드 1). `MASKED` =
    `PHYS ^ MASK` — `masked_phys_addr` 의 기대값.
  * `META` = `{family[31:24], serial[23:8], flags[7:0]}`. `flags` bit0 =
    쌍의 앞 라인, bit1 = 쌍의 뒤 라인.

## 2. 가족

| code | 가족 | 시작 라인 | 라인 수 | 설명 |
|---|---|---|---|---|
| 0x00 | `pinned` | 0 | 8 | `test_hiu.py` 의 FIXED_KEY/FIXED_NONCE × phys 8종 (TB 직결 — 이 가족이 마스크 정확값 assert 의 원본) |
| 0x01 | `rand` | 8 | 32 | 고정 seed 난수 key/nonce/phys — 일반형 |
| 0x02 | `edge` | 40 | 8 | 경계 입력 (전0 / 전1 / 1비트 key / 1비트 nonce / phys 경계) |
| 0x03 | `nonce_tail` | 48 | 16 | **nonce 바이트 16-23 만** 다른 인접 쌍. 폐기 RTL 에서 이 두 라인의 마스크는 **같다** (그 64비트가 죽어 있었다). 표준에서는 반드시 달라야 한다 — 편차 A/B 회귀의 직접 검출기 |
| 0x04 | `key_word` | 64 | 16 | key 워드 w 의 1비트만 다른 인접 쌍 (w=0..7). 폐기 RTL 에서는 마스크의 **한쪽 32비트만** 바뀐다 (그룹 분해). 표준에서는 양쪽 32비트가 모두 바뀌어야 한다 |

## 3. seed (난수원/timestamp 없음)

| 이름 | 값 |
|---|---|
| `dep_matrix` | `0x13550001` |
| `avalanche` | `0x13550002` |
| `vec_rand` | `0x13550011` |
| `vec_edge` | `0x13550012` |
| `vec_pair` | `0x13550013` |

## 4. 값 계약 (RTL 이 이행해야 할 것)

1. **HChaCha20 (1단).** 초기상태 = `{상수 4, chacha_key 8워드,
   chacha_nonce 바이트 0-15 의 4워드}`. double round 10회. 출력 subkey =
   상태 워드 `[0..3]` + `[12..15]` (최종 덧셈 **없음**).
2. **ChaCha20 (2단).** 초기상태 = `{상수 4, subkey 8워드, counter=0,
   0, nonce 바이트 16-19, nonce 바이트 20-23}`.
   → **`state[13]` 은 0 이고 nonce 는 `[14]`/`[15]` 에 들어간다.**
   폐기 RTL 의 `[13]=nonce[16:20], [14]=nonce[20:24], [15]=0` 배치는
   draft §2.3 (12바이트 nonce = 4 NUL || nonce[16:24]) 위반이다.
3. **double round 는 column round → diagonal round 를 반드시 직렬로**
   수행한다. 폐기 RTL 은 8개 quarter-round 를 같은 (직전) 상태에서
   병렬 계산해 column 결과를 diagonal 이 전량 덮었다 — 실질 diagonal
   round 1회였다.
4. **최종 덧셈.** 블록 = 라운드 후 상태 + 초기상태 (워드별 mod 2^32).
5. **마스크.** `masked_phys_addr = phys_addr ^ {블록워드1, 블록워드0}`.

## 5. RTL 형태에 대한 주의 (값 계약과 별개)

값 계약은 cycle 수에 무관하다. 다만 3번을 이행하는 형태는 둘이다:

  * **(A) 반라운드 2 cycle** — cycle 마다 column 또는 diagonal 중 하나만
    적용하고 라운드 카운터를 2배로 돈다. 조합 depth 불변, 변환당 +20
    cycle. `test_hiu.py:run_translate` 는 400 cycle 까지 기다리므로
    TB 영향 없음.
  * **(B) 1 cycle 직렬 2단** — 같은 cycle 에 column → diagonal 을 직렬로
    잇는다. cycle 수 불변, **조합 depth 2배**.

GATE S1 의 WHS 여유는 +0.007~+0.019 ns 로 얇다. (B) 는 그 축을 직접
때린다 — 형태 선택은 WHS 실측에 종속시킬 것. 본 계약은 값만 규정하고
형태를 규정하지 않는다.

## 6. 회귀 검출기 (이 벡터가 잡는 것)

| 가족 | 폐기 RTL 에서의 증상 | 표준에서 요구 |
|---|---|---|
| `nonce_tail` | 쌍의 두 마스크가 **동일** (nonce 64비트 사망) | 반드시 상이 |
| `key_word` | 마스크의 **한쪽 32비트만** 변화 (그룹 분해) | 양쪽 모두 변화 |
| 전 가족 | `BLOCK` 14워드가 표준과 상이 | 16워드 전부 일치 |

## 7. 확산 실측 요약 (상세는 `xchacha_golden_report.json`)

| 축 | 폐기 RTL | 표준 |
|---|---|---|
| 상태 분할 | 4그룹 `[[0, 5, 10, 15], [1, 6, 11, 12], [2, 7, 8, 13], [3, 4, 9, 14]]` | 분할 없음 |
| 워드 의존 밀도 (10 라운드) | 64/256 | 256/256 |
| 마스크에 살아 있는 nonce 비트 | 128/192 | 192/192 |
| mask 하위 32b 가 보는 key 워드 | [0, 2, 5, 7] | [0, 1, 2, 3, 4, 5, 6, 7] |
| mask 상위 32b 가 보는 key 워드 | [1, 3, 4, 6] | [0, 1, 2, 3, 4, 5, 6, 7] |
| 마스크가 보는 subkey 워드 | [1, 2, 6, 7] | [0, 1, 2, 3, 4, 5, 6, 7] |
| avalanche (key 1비트 → 마스크) | 16.04/64 (25.1%) | 31.95/64 (49.9%) |
| avalanche (nonce 1비트) | 10.41/64 (16.3%) | 31.94/64 (49.9%) |
| 변화 0비트인 nonce flip 비율 | 34.7% | 0.0% |

정직 명기: 위 수치는 **구현 편차의 크기**를 재는 것이지 XChaCha20 자체의
안전성을 재는 것이 아니다. 64-bit 마스크로 주소를 XOR 하는 구성의 보안
강도·키 재사용 정책·counter 고정(=0) 의 함의는 본 계약의 대상이 아니다.
