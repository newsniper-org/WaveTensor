#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""golden_xchacha.py — HIU 주소 마스킹의 golden model = **표준 XChaCha20**.

규범 출처
---------
  * RFC 8439 — ChaCha20 (quarter-round §2.1 / 블록 함수 §2.3 / 암호화 §2.4)
  * draft-irtf-cfrg-xchacha-03 — HChaCha20 §2.2, XChaCha20 구성 §2.3,
    테스트 벡터 부록 A.2 / A.3.2.1 (counter 0) / A.3.2.2 (counter 1)
  * wt64v1_spec.md §29.8 (D8) — HIU 가 XChaCha20 을 쓴다는 선언

본 파일의 지위 (golden-before-RTL)
----------------------------------
이 golden 은 **RTL 이 무엇을 하는지**가 아니라 **RTL 이 무엇을 해야
하는지**를 정의한다. `hiu_mask64()` 는 표준 XChaCha20 키스트림에서
직접 유도되며, RTL 이 그 값을 내지 못하면 `test_hiu.py` 가 FAIL 한다.
그것이 이 파일이 RTL 보다 먼저 착지하는 이유다.

  **경고 (의도된 red):** RTL 수리 전에는 `test_hiu.py` 의 마스크 assert 가
  **반드시 FAIL 한다.** 이것은 사고가 아니라 golden-before-RTL 의 신호다.
  수리 후 GREEN 이 되는 것이 착지 조건이다.

폐기된 RTL 알고리즘 (`legacy_*`) 은 **삭제하지 않고 남긴다** — 확산 붕괴의
크기를 수치로 계속 보여주고, 회귀가 일어나면 `legacy_mask64` 와 값이
같아지는 것으로 즉시 검출되기 때문이다 (loud-fault-never-silent).

폐기 사유 (실측, `xchacha_golden_report.json` 의 `diffusion` 절)
---------------------------------------------------------------
`HIU.v` 의 `CHACHA_H_MASK` / `CHACHA_MASK` 는 한 cycle 에 8개의
`chacha_qr_func` 호출을 나열하는데, 그 함수는 레지스터 `chacha_state` 를
**직접 읽고** 8개 대입은 전부 **비차단**이다. 따라서 8개 전부가 같은
(직전) 상태에서 계산되고, diagonal 4쌍의 목적지 인덱스 합집합이 정확히
{0..15} 이므로 **column round 결과가 전량 덮인다.** 한 cycle = diagonal
round 1회이며, 그 결과:

  * 상태가 영구히 4그룹 {0,5,10,15} / {1,6,11,12} / {2,7,8,13} / {3,4,9,14}
    로 **분해**된다 — 10 라운드 내내 그룹 간 혼합 0.
  * 워드 의존 밀도 **64/256 (25.0%)** — 표준은 2 double round 만에
    **256/256 (100%)**.
  * nonce **64비트 (바이트 16-23) 가 완전히 죽는다** — 마스크에 전혀
    도달하지 않는다 (표준은 192/192 생존).
  * mask 하위 32비트는 key 워드 {0,2,5,7}, 상위 32비트는 key 워드
    {1,3,4,6} 에만 의존한다 — **서로소인 128비트 반쪽 2개**이지
    256비트 하나가 아니다.
  * 2단 ChaCha20 초기상태에서 마스크 워드 하나가 보는 미지 입력은
    **subkey 2워드 = 64비트뿐**이다 (나머지 2워드는 상수와 0).
  * avalanche (seed `SEEDS["avalanche"]`, key/nonce 각 1024 flip):
    key 1비트 → 마스크 **16.04/64 (25.1%)**, nonce 1비트 →
    **10.41/64 (16.3%)**, 그중 **34.7%** 는 아예 0비트 변화.
    표준은 각각 31.95/64 (49.9%) / 31.94/64 (49.9%) / 0.0%.
    (이 수치들은 `_test_diffusion_claims` 가 실측으로 강제한다 — 문서가
    늙으면 self-test 가 먼저 깨진다.)

편차 A (nonce 배치) 도 함께 정정 대상이다: RTL 은 `c_init_w[13]=nonce
[16:20]`, `[14]=nonce[20:24]`, `[15]=0` 이었고 표준은 `[13]=0`,
`[14]=nonce[16:20]`, `[15]=nonce[20:24]` 다 (draft §2.3 — 12바이트 nonce
= 4 NUL || nonce 바이트 16-23).

산출물 (전부 stdlib-only, 고정 seed, 재실행 byte-identical)
----------------------------------------------------------
  * `include/generated/xchacha_vectors.hex`      — RTL TB 결정적 벡터
  * `include/generated/xchacha_vec_contract.md`  — 비트 레이아웃·계약
  * `include/generated/xchacha_golden_report.json` — 자기검증 + 확산 실측

정직 명기 — 이것은 암호학적 강도 주장이 아니다
---------------------------------------------
본 golden 은 "RTL 이 표준 XChaCha20 을 계산하는가" 만 판정한다. 64-bit
마스크로 주소를 XOR 하는 구성 자체의 보안 강도, 키/nonce 재사용 정책,
counter 고정(=0) 의 함의는 본 파일의 대상이 아니다. 위 확산 수치는
**구현 편차의 크기**를 재는 것이지 표준의 안전성을 재는 것이 아니다.
"""

import hashlib
import json
import random
import sys
from pathlib import Path

MASK32 = 0xFFFFFFFF
MASK64 = 0xFFFFFFFFFFFFFFFF

REPO = Path(__file__).resolve().parent.parent
GEN = REPO / "include" / "generated"
VEC_PATH = GEN / "xchacha_vectors.hex"
CONTRACT_PATH = GEN / "xchacha_vec_contract.md"
REPORT_PATH = GEN / "xchacha_golden_report.json"

# ChaCha20 상수 "expand 32-byte k" 를 little-endian 32-bit 워드로 분해한 값.
CHACHA_CONST = (0x61707865, 0x3320646E, 0x79622D32, 0x6B206574)

# RTL 의 CHACHA_ROUNDS 파라미터 기본값 (HIU.v:12).
CHACHA_ROUNDS = 20

# 확산 실측의 고정 seed (난수원/timestamp 없음).
SEEDS = {
    "dep_matrix": 0x1355_0001,
    "avalanche": 0x1355_0002,
    "vec_rand": 0x1355_0011,
    "vec_edge": 0x1355_0012,
    "vec_pair": 0x1355_0013,
}


class XChaChaFault(Exception):
    """loud fault — 조용히 넘어갈 경로를 만들지 않는다."""


# ===========================================================================
# 1. 표준 원시함수 (RFC 8439 / draft-irtf-cfrg-xchacha)
# ===========================================================================

def _rotl32(x, n):
    x &= MASK32
    return ((x << n) | (x >> (32 - n))) & MASK32


def quarter_round(s, a, b, c, d):
    """RFC 8439 §2.1 — 리스트 `s` 를 제자리에서 갱신한다."""
    s[a] = (s[a] + s[b]) & MASK32
    s[d] = _rotl32(s[d] ^ s[a], 16)
    s[c] = (s[c] + s[d]) & MASK32
    s[b] = _rotl32(s[b] ^ s[c], 12)
    s[a] = (s[a] + s[b]) & MASK32
    s[d] = _rotl32(s[d] ^ s[a], 8)
    s[c] = (s[c] + s[d]) & MASK32
    s[b] = _rotl32(s[b] ^ s[c], 7)


# column / diagonal quarter-round 쌍 — RFC 8439 §2.3.1 순서 그대로.
COL_QUADS = ((0, 4, 8, 12), (1, 5, 9, 13), (2, 6, 10, 14), (3, 7, 11, 15))
DIAG_QUADS = ((0, 5, 10, 15), (1, 6, 11, 12), (2, 7, 8, 13), (3, 4, 9, 14))


def column_round(s):
    """RFC 8439 §2.3.1 전반 — column 4쌍. **직렬로** 적용된다."""
    for q in COL_QUADS:
        quarter_round(s, *q)


def diagonal_round(s):
    """RFC 8439 §2.3.1 후반 — diagonal 4쌍. column 결과 **위에서** 돈다."""
    for q in DIAG_QUADS:
        quarter_round(s, *q)


def double_round(s):
    """RFC 8439 §2.3.1 — column round → diagonal round (이 순서가 규범)."""
    column_round(s)
    diagonal_round(s)


def _words_le(data):
    """바이트열 → little-endian 32-bit 워드 리스트."""
    if len(data) % 4:
        raise XChaChaFault("길이가 4의 배수가 아니다")
    return [int.from_bytes(data[i:i + 4], "little")
            for i in range(0, len(data), 4)]


def _bytes_le(words):
    return b"".join((w & MASK32).to_bytes(4, "little") for w in words)


def chacha20_state(key, counter, nonce):
    """ChaCha20 초기 상태 16워드 (key 32B, counter 32-bit, nonce 12B)."""
    if len(key) != 32:
        raise XChaChaFault("key 는 32바이트여야 한다")
    if len(nonce) != 12:
        raise XChaChaFault("nonce 는 12바이트여야 한다")
    return (list(CHACHA_CONST) + _words_le(key)
            + [counter & MASK32] + _words_le(nonce))


def chacha20_block_words(key, counter, nonce, rounds=CHACHA_ROUNDS):
    """RFC 8439 §2.3 — 블록 함수 출력 16워드 (최종 덧셈 포함)."""
    init = chacha20_state(key, counter, nonce)
    work = list(init)
    for _ in range(rounds // 2):
        double_round(work)
    return [(work[i] + init[i]) & MASK32 for i in range(16)]


def chacha20_block(key, counter, nonce, rounds=CHACHA_ROUNDS):
    """RFC 8439 §2.3 — 64바이트 키스트림 블록."""
    return _bytes_le(chacha20_block_words(key, counter, nonce, rounds))


def chacha20_xor(key, counter, nonce, data, rounds=CHACHA_ROUNDS):
    """RFC 8439 §2.4 — 키스트림 XOR (암·복호 동일)."""
    out = bytearray()
    for i in range(0, len(data), 64):
        ks = chacha20_block(key, counter + i // 64, nonce, rounds)
        chunk = data[i:i + 64]
        out += bytes(a ^ b for a, b in zip(chunk, ks))
    return bytes(out)


def hchacha20(key, nonce16, rounds=CHACHA_ROUNDS):
    """draft-irtf-cfrg-xchacha §2.2 — 32바이트 subkey.

    최종 덧셈이 **없는** 것이 ChaCha20 블록 함수와의 차이다. 출력은
    라운드 후 상태의 word 0-3 과 12-15 를 little-endian 으로 직렬화한
    것이다 — `HIU.v` 의 `CHACHA_H_MASK` else 분기가 뽑는 워드와 같다.
    """
    if len(key) != 32:
        raise XChaChaFault("key 는 32바이트여야 한다")
    if len(nonce16) != 16:
        raise XChaChaFault("HChaCha20 nonce 는 16바이트여야 한다")
    work = list(CHACHA_CONST) + _words_le(key) + _words_le(nonce16)
    for _ in range(rounds // 2):
        double_round(work)
    return _bytes_le([work[0], work[1], work[2], work[3],
                      work[12], work[13], work[14], work[15]])


def xchacha20_block_words(key32, nonce24, counter=0, rounds=CHACHA_ROUNDS):
    """draft §2.3 — XChaCha20 블록 함수 출력 16워드.

    구성: subkey = HChaCha20(key, nonce[0:16]) 이고, ChaCha20 을
    **12바이트 nonce = 4 NUL || nonce[16:24]** 로 돌린다. 즉 상태
    워드는 `[12]=counter, [13]=0, [14]=nonce[16:20], [15]=nonce[20:24]`.
    (libsodium 계열의 64-bit counter 표기와 값이 동일하다 — counter 상위
    32비트가 0 인 것과 `[13]=0` 이 같은 워드를 가리킨다.)
    """
    if len(nonce24) != 24:
        raise XChaChaFault("XChaCha20 nonce 는 24바이트여야 한다")
    subkey = hchacha20(key32, nonce24[:16], rounds)
    return chacha20_block_words(subkey, counter,
                                b"\x00\x00\x00\x00" + nonce24[16:24], rounds)


def xchacha20_xor(key32, nonce24, data, counter=0, rounds=CHACHA_ROUNDS):
    """draft §2.3 — XChaCha20 스트림 XOR (테스트 벡터 대조용)."""
    subkey = hchacha20(key32, nonce24[:16], rounds)
    return chacha20_xor(subkey, counter,
                        b"\x00\x00\x00\x00" + nonce24[16:24], data, rounds)


# ===========================================================================
# 2. 독립 재구현 (자기확인 루프 차단)
#
# 1절과 **구조가 다른** 경로로 같은 값을 낸다: 상태를 4행 (a,b,c,d) 으로
# 보고 column round 는 원소별 quarter-round, diagonal round 는 행 회전
# (b<<<1, c<<<2, d<<<3) 후 원소별 quarter-round 로 만든다 (SIMD 정식화).
# 인덱스 표를 공유하지 않으므로 인덱스 오타를 서로 잡아낸다.
# ===========================================================================

def _alt_qr(a, b, c, d):
    a = (a + b) & MASK32
    d = ((d ^ a) << 16 | (d ^ a) >> 16) & MASK32
    c = (c + d) & MASK32
    b = ((b ^ c) << 12 | (b ^ c) >> 20) & MASK32
    a = (a + b) & MASK32
    d = ((d ^ a) << 8 | (d ^ a) >> 24) & MASK32
    c = (c + d) & MASK32
    b = ((b ^ c) << 7 | (b ^ c) >> 25) & MASK32
    return a, b, c, d


def _alt_rows(s):
    return [list(s[0:4]), list(s[4:8]), list(s[8:12]), list(s[12:16])]


def _alt_flat(rows):
    return rows[0] + rows[1] + rows[2] + rows[3]


def _rot_row(row, n):
    return row[n:] + row[:n]


def _alt_double_round(rows):
    a, b, c, d = rows
    for i in range(4):
        a[i], b[i], c[i], d[i] = _alt_qr(a[i], b[i], c[i], d[i])
    b, c, d = _rot_row(b, 1), _rot_row(c, 2), _rot_row(d, 3)
    for i in range(4):
        a[i], b[i], c[i], d[i] = _alt_qr(a[i], b[i], c[i], d[i])
    b, c, d = _rot_row(b, 3), _rot_row(c, 2), _rot_row(d, 1)
    return [a, b, c, d]


def _alt_permute(state, rounds=CHACHA_ROUNDS):
    rows = _alt_rows(state)
    for _ in range(rounds // 2):
        rows = _alt_double_round(rows)
    return _alt_flat(rows)


def alt_xchacha20_block_words(key32, nonce24, counter=0,
                              rounds=CHACHA_ROUNDS):
    """독립 경로 XChaCha20 블록 함수 — 값이 1절과 같아야 한다."""
    h = list(CHACHA_CONST) + _words_le(key32) + _words_le(nonce24[:16])
    hp = _alt_permute(h, rounds)
    subkey_words = [hp[0], hp[1], hp[2], hp[3], hp[12], hp[13], hp[14], hp[15]]
    init = (list(CHACHA_CONST) + subkey_words
            + [counter & MASK32, 0,
               int.from_bytes(nonce24[16:20], "little"),
               int.from_bytes(nonce24[20:24], "little")])
    work = _alt_permute(init, rounds)
    return [(work[i] + init[i]) & MASK32 for i in range(16)]


# ===========================================================================
# 3. HIU 포트 인코딩
# ===========================================================================

def _key_bytes(chacha_key):
    """`chacha_key` (256-bit 정수 포트값) → 32바이트.

    RTL 은 `h_init_w[4+n] = chacha_key[32n+31 : 32n]` 으로 워드를 뽑는다.
    즉 포트 정수의 최하위 32비트가 key word 0 이고, 이는 key 바이트열을
    little-endian 으로 본 것과 정확히 같다.
    """
    return int(chacha_key).to_bytes(32, "little")


def _nonce_bytes(chacha_nonce):
    """`chacha_nonce` (192-bit 정수 포트값) → 24바이트 (같은 논거)."""
    return int(chacha_nonce).to_bytes(24, "little")


# ===========================================================================
# 4. HIU 규범 계약 — 표준 XChaCha20 (RTL 이 만족해야 할 값)
# ===========================================================================

def hiu_subkey_words(chacha_key, chacha_nonce, rounds=CHACHA_ROUNDS):
    """`subkey` 레지스터 8워드 (word j = `subkey[32j+31:32j]`)."""
    sk = hchacha20(_key_bytes(chacha_key),
                   _nonce_bytes(chacha_nonce)[:16], rounds)
    return _words_le(sk)


def hiu_subkey(chacha_key, chacha_nonce, rounds=CHACHA_ROUNDS):
    """`subkey` 32바이트 (little-endian 직렬화)."""
    return hchacha20(_key_bytes(chacha_key),
                     _nonce_bytes(chacha_nonce)[:16], rounds)


def hiu_block_words(chacha_key, chacha_nonce, rounds=CHACHA_ROUNDS):
    """`CHACHA_FINAL` 시점의 `chacha_state[i] + initial_state[i]` 16워드.

    RTL 은 워드 0/1 만 쓰지만 16워드 전부가 관측 가능하므로 (두 배열이
    모두 살아 있다) 벡터 파일은 전부를 싣는다 — 부분 수리를 잡는다.
    """
    return xchacha20_block_words(_key_bytes(chacha_key),
                                 _nonce_bytes(chacha_nonce), 0, rounds)


def hiu_mask64(chacha_key, chacha_nonce, rounds=CHACHA_ROUNDS):
    """`CHACHA_FINAL` 이 만들어야 할 64-bit 마스크 (**표준값**).

    RTL 형태:  `{chacha_state[1] + initial_state[1],
                 chacha_state[0] + initial_state[0]}`
    → 상위 32비트가 워드 1, 하위 32비트가 워드 0. 이는 XChaCha20
    키스트림의 **첫 8바이트를 little-endian 64-bit 로 읽은 값**과 같다
    (워드 선택·연접 순서는 표준 준거이므로 유지한다).
    """
    w = hiu_block_words(chacha_key, chacha_nonce, rounds)
    return ((w[1] << 32) | w[0]) & MASK64


def hiu_masked_phys(phys_addr, chacha_key, chacha_nonce,
                    rounds=CHACHA_ROUNDS):
    """`masked_phys_addr` 의 정확값."""
    return (int(phys_addr) ^ hiu_mask64(chacha_key, chacha_nonce, rounds)) \
        & MASK64


def standard_xchacha20_mask64(chacha_key, chacha_nonce,
                              rounds=CHACHA_ROUNDS):
    """표준 XChaCha20 마스크 — `hiu_mask64` 와 **같은 값**이어야 한다.

    이름을 남겨 둔 것은 §29.8 이하 문서가 이 이름으로 표준 참조를
    가리키기 때문이다. 두 함수가 갈라지면 self-test 가 먼저 깨진다.
    """
    blk = xchacha20_block_words(_key_bytes(chacha_key),
                                _nonce_bytes(chacha_nonce), 0, rounds)
    return ((blk[1] << 32) | blk[0]) & MASK64


# ===========================================================================
# 5. 폐기된 RTL 알고리즘 (`legacy_*`) — 확산 붕괴 정량화 + 회귀 검출용
# ===========================================================================

def _qr_pure(s, a, b, c, d):
    """`chacha_qr_func` 재현 — 인자 상태 `s` 에서만 읽고 4워드를 반환한다.

    RTL 의 function 은 레지스터 `chacha_state` 를 직접 읽으므로, 같은
    cycle 의 다른 호출이 만든 값을 **볼 수 없다**. 그 성질이 편차 B 의
    원인이며 여기서 그대로 재현된다.
    """
    xa = (s[a] + s[b]) & MASK32
    xd = _rotl32(s[d] ^ xa, 16)
    xc = (s[c] + xd) & MASK32
    xb = _rotl32(s[b] ^ xc, 12)
    xa = (xa + xb) & MASK32
    xd = _rotl32(xd ^ xa, 8)
    xc = (xc + xd) & MASK32
    xb = _rotl32(xb ^ xc, 7)
    return xa, xb, xc, xd


def legacy_round_cycle(state):
    """폐기된 `CHACHA_*_MASK` 한 cycle 의 **실물** 동작.

    8개 호출 전부가 직전 상태 `old` 에서 계산되고, 비차단 대입의
    나중-대입 규칙 때문에 diagonal 4쌍이 column 4쌍을 **완전히** 덮는다
    (diagonal 인덱스 합집합 = 0..15). column 루프를 코드에 남겨 두는
    것은 그 사실을 눈으로 볼 수 있게 하기 위해서다 — 지우면 "왜
    diagonal 만 있지?" 가 되고, 남기면 "덮인다" 가 보인다.
    """
    old = list(state)
    new = list(state)
    for q in COL_QUADS:                       # 계산되지만 아래에서 전부 덮인다
        new[q[0]], new[q[1]], new[q[2]], new[q[3]] = _qr_pure(old, *q)
    for q in DIAG_QUADS:
        new[q[0]], new[q[1]], new[q[2]], new[q[3]] = _qr_pure(old, *q)
    return new


def legacy_h_init_words(chacha_key, chacha_nonce):
    return (list(CHACHA_CONST) + _words_le(_key_bytes(chacha_key))
            + _words_le(_nonce_bytes(chacha_nonce)[:16]))


def legacy_c_init_words(subkey_words, chacha_nonce):
    """폐기 배치 (편차 A): `[12]=0, [13]=n[16:20], [14]=n[20:24], [15]=0`."""
    nb = _nonce_bytes(chacha_nonce)
    return (list(CHACHA_CONST) + list(subkey_words)
            + [0,
               int.from_bytes(nb[16:20], "little"),
               int.from_bytes(nb[20:24], "little"),
               0])


def legacy_subkey_words(chacha_key, chacha_nonce, rounds=CHACHA_ROUNDS):
    work = legacy_h_init_words(chacha_key, chacha_nonce)
    for _ in range(rounds // 2):
        work = legacy_round_cycle(work)
    return [work[0], work[1], work[2], work[3],
            work[12], work[13], work[14], work[15]]


def legacy_block_words(chacha_key, chacha_nonce, rounds=CHACHA_ROUNDS):
    init = legacy_c_init_words(
        legacy_subkey_words(chacha_key, chacha_nonce, rounds), chacha_nonce)
    work = list(init)
    for _ in range(rounds // 2):
        work = legacy_round_cycle(work)
    return [(work[i] + init[i]) & MASK32 for i in range(16)]


def legacy_mask64(chacha_key, chacha_nonce, rounds=CHACHA_ROUNDS):
    """폐기된 RTL 이 실제로 내던 마스크 (verilator 실측과 bit-exact)."""
    w = legacy_block_words(chacha_key, chacha_nonce, rounds)
    return ((w[1] << 32) | w[0]) & MASK64


def legacy_masked_phys(phys_addr, chacha_key, chacha_nonce,
                       rounds=CHACHA_ROUNDS):
    return (int(phys_addr) ^ legacy_mask64(chacha_key, chacha_nonce, rounds)) \
        & MASK64


# ===========================================================================
# 6. 고정 벡터 — `test_hiu.py` 가 쓰는 값
# ===========================================================================

FIXED_KEY = 0xDEADBEEFCAFEBABE0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF
FIXED_NONCE = 0xAABBCCDDEEFF00112233445566778899AABBCCDDEEFF0011

# 폐기 RTL 이 이 키/nonce 에서 내던 값 — verilator 실측으로 확인됐다.
# `legacy_mask64` 가 이 값을 재현하지 못하면 "무엇을 고쳤는가" 의 기준
# 자체가 사라지므로 self-test 가 pin 한다.
LEGACY_MEASURED_MASK64 = 0x817EBA4A8961A7D6


# ===========================================================================
# 7. 확산 (diffusion) 실측
# ===========================================================================

def diagonal_orbit_groups():
    """diagonal-only 반복이 유도하는 인덱스 분할 (union-find)."""
    parent = list(range(16))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for q in DIAG_QUADS:
        for i in q[1:]:
            ra, rb = find(q[0]), find(i)
            if ra != rb:
                parent[ra] = rb
    groups = {}
    for i in range(16):
        groups.setdefault(find(i), []).append(i)
    return sorted(sorted(g) for g in groups.values())


def word_dependency_matrix(cycle_fn, cycles, seed):
    """출력 워드 j 가 입력 워드 i 에 의존하는가 (16×16 bool).

    입력 워드의 32비트를 하나씩 뒤집어 출력 변화를 본다 — "의존"의
    **실측** 정의이며 구조 논증이 아니다.
    """
    rnd = random.Random(seed)
    base = [rnd.getrandbits(32) for _ in range(16)]
    ref = list(base)
    for _ in range(cycles):
        ref = cycle_fn(ref)
    dep = [[False] * 16 for _ in range(16)]
    for i in range(16):
        for b in range(32):
            st = list(base)
            st[i] ^= (1 << b)
            out = st
            for _ in range(cycles):
                out = cycle_fn(out)
            for j in range(16):
                if out[j] != ref[j]:
                    dep[j][i] = True
    return dep


def _std_cycle(s):
    w = list(s)
    double_round(w)
    return w


def full_diffusion_double_rounds(seed, limit=10):
    """표준 double round 몇 회에 의존 밀도가 256/256 이 되는가."""
    for n in range(1, limit + 1):
        dep = word_dependency_matrix(_std_cycle, n, seed)
        if sum(sum(r) for r in dep) == 256:
            return n
    return None


def mask_input_dependence(mask_fn, key, nonce):
    """마스크가 살아 있는 key/nonce 비트 수와 워드 단위 의존 분포."""
    base = mask_fn(key, nonce)
    live_key, live_nonce = 0, 0
    lo_key_words, hi_key_words = set(), set()
    lo_nonce_words, hi_nonce_words = set(), set()
    for b in range(256):
        v = mask_fn(key ^ (1 << b), nonce)
        if v != base:
            live_key += 1
        if (v & MASK32) != (base & MASK32):
            lo_key_words.add(b // 32)
        if (v >> 32) != (base >> 32):
            hi_key_words.add(b // 32)
    for b in range(192):
        v = mask_fn(key, nonce ^ (1 << b))
        if v != base:
            live_nonce += 1
        if (v & MASK32) != (base & MASK32):
            lo_nonce_words.add(b // 32)
        if (v >> 32) != (base >> 32):
            hi_nonce_words.add(b // 32)
    return {
        "live_key_bits": live_key,
        "live_nonce_bits": live_nonce,
        "dead_nonce_bits": 192 - live_nonce,
        "mask_lo_key_words": sorted(lo_key_words),
        "mask_hi_key_words": sorted(hi_key_words),
        "mask_lo_nonce_words": sorted(lo_nonce_words),
        "mask_hi_nonce_words": sorted(hi_nonce_words),
    }


def _stage2_mask_from_subkey(subkey_words, nonce, legacy):
    """2단 ChaCha20 만 돌린다 (subkey 의존도 측정용)."""
    if legacy:
        init = legacy_c_init_words(subkey_words, nonce)
        work = list(init)
        for _ in range(CHACHA_ROUNDS // 2):
            work = legacy_round_cycle(work)
    else:
        nb = _nonce_bytes(nonce)
        init = (list(CHACHA_CONST) + list(subkey_words)
                + [0, 0,
                   int.from_bytes(nb[16:20], "little"),
                   int.from_bytes(nb[20:24], "little")])
        work = list(init)
        for _ in range(CHACHA_ROUNDS // 2):
            double_round(work)
    w0 = (work[0] + init[0]) & MASK32
    w1 = (work[1] + init[1]) & MASK32
    return ((w1 << 32) | w0) & MASK64


def subkey_word_dependence(legacy, key, nonce):
    """마스크가 subkey **몇 워드**에 의존하는가 (2단 단독 실측)."""
    sk = (legacy_subkey_words(key, nonce) if legacy
          else hiu_subkey_words(key, nonce))
    base = _stage2_mask_from_subkey(sk, nonce, legacy)
    live = set()
    for j in range(8):
        for b in (0, 7, 15, 23, 31):
            t = list(sk)
            t[j] ^= (1 << b)
            if _stage2_mask_from_subkey(t, nonce, legacy) != base:
                live.add(j)
                break
    return sorted(live)


def avalanche(mask_fn, seed, trials=64, bits_per_trial=16):
    """입력 1비트 변화 → 마스크 64비트 중 몇 비트가 바뀌는가."""
    rnd = random.Random(seed)
    tot_k = tot_n = 0
    n_k = n_n = 0
    zero_k = zero_n = 0
    min_k, max_k = 64, 0
    for _ in range(trials):
        k = rnd.getrandbits(256)
        n = rnd.getrandbits(192)
        base = mask_fn(k, n)
        for b in rnd.sample(range(256), bits_per_trial):
            d = bin(base ^ mask_fn(k ^ (1 << b), n)).count("1")
            tot_k += d
            n_k += 1
            min_k = min(min_k, d)
            max_k = max(max_k, d)
            if d == 0:
                zero_k += 1
        for b in rnd.sample(range(192), bits_per_trial):
            d = bin(base ^ mask_fn(k, n ^ (1 << b))).count("1")
            tot_n += d
            n_n += 1
            if d == 0:
                zero_n += 1
    return {
        "key_flips": n_k,
        "key_mean_bits": round(tot_k / n_k, 4),
        "key_mean_pct": round(100.0 * tot_k / n_k / 64.0, 3),
        "key_min_bits": min_k,
        "key_max_bits": max_k,
        "key_zero_change": zero_k,
        "nonce_flips": n_n,
        "nonce_mean_bits": round(tot_n / n_n, 4),
        "nonce_mean_pct": round(100.0 * tot_n / n_n / 64.0, 3),
        "nonce_zero_change": zero_n,
        "nonce_zero_change_pct": round(100.0 * zero_n / n_n, 3),
    }


def measure_diffusion():
    """§29.8a 확산 실측 일괄 — report 의 `diffusion` 절 원본."""
    dep_seed = SEEDS["dep_matrix"]
    dep_leg = word_dependency_matrix(legacy_round_cycle, 10, dep_seed)
    dep_std = word_dependency_matrix(_std_cycle, 10, dep_seed)
    return {
        "orbit_groups_legacy": diagonal_orbit_groups(),
        "word_dependency": {
            "cycles": 10,
            "seed": dep_seed,
            "legacy_cells": sum(sum(r) for r in dep_leg),
            "standard_cells": sum(sum(r) for r in dep_std),
            "total_cells": 256,
            "legacy_out_word0_deps": [i for i in range(16) if dep_leg[0][i]],
            "legacy_out_word1_deps": [i for i in range(16) if dep_leg[1][i]],
            "standard_out_word0_deps": [i for i in range(16) if dep_std[0][i]],
            "standard_full_after_double_rounds":
                full_diffusion_double_rounds(dep_seed),
        },
        "mask_input_dependence": {
            "legacy": mask_input_dependence(legacy_mask64,
                                            FIXED_KEY, FIXED_NONCE),
            "standard": mask_input_dependence(hiu_mask64,
                                              FIXED_KEY, FIXED_NONCE),
        },
        "subkey_word_dependence": {
            "legacy": subkey_word_dependence(True, FIXED_KEY, FIXED_NONCE),
            "standard": subkey_word_dependence(False, FIXED_KEY, FIXED_NONCE),
            "note": "2단 ChaCha20 만 단독으로 돌려 subkey 워드를 뒤집었다. "
                    "legacy 는 4워드 (128b) 에만 의존하고, 그중 마스크 "
                    "워드 하나가 보는 미지 입력은 2워드 (64b) 뿐이다 "
                    "— 나머지 2개는 공개 상수와 0 이다.",
        },
        "avalanche": {
            "legacy": avalanche(legacy_mask64, SEEDS["avalanche"]),
            "standard": avalanche(hiu_mask64, SEEDS["avalanche"]),
            "ideal_mean_bits": 32.0,
        },
    }


# ===========================================================================
# 8. 표준 테스트 벡터 (self-test 의 외부 anchor)
# ===========================================================================

RFC8439_QR = {
    "ref": "RFC 8439 §2.1.1",
    "in": [0x11111111, 0x01020304, 0x9B8D6F43, 0x01234567],
    "out": [0xEA2A92F4, 0xCB1CF8CE, 0x4581472E, 0x5881C4BB],
}

RFC8439_BLOCK = {
    "ref": "RFC 8439 §2.3.2",
    "key": bytes(range(32)),
    "counter": 1,
    "nonce": bytes.fromhex("000000090000004a00000000"),
    "out": bytes.fromhex(
        "10f1e7e4d13b5915500fdd1fa32071c4"
        "c7d1f4c733c068030422aa9ac3d46c4e"
        "d2826446079faa0914c2d705d98b02a2"
        "b5129cd1de164eb9cbd083e8a2503c4e"),
}

RFC8439_ENCRYPT = {
    "ref": "RFC 8439 §2.4.2",
    "key": bytes(range(32)),
    "counter": 1,
    "nonce": bytes.fromhex("000000000000004a00000000"),
    "plain": (b"Ladies and Gentlemen of the class of '99: If I could offer "
              b"you only one tip for the future, sunscreen would be it."),
    "cipher": bytes.fromhex(
        "6e2e359a2568f98041ba0728dd0d6981"
        "e97e7aec1d4360c20a27afccfd9fae0b"
        "f91b65c5524733ab8f593dabcd62b357"
        "1639d624e65152ab8f530c359f0861d8"
        "07ca0dbf500d6a6156a38e088a22b65e"
        "52bc514d16ccf806818ce91ab7793736"
        "5af90bbf74a35be6b40b8eedf2785e42"
        "874d"),
}

XCHACHA_HCHACHA = {
    "ref": "draft-irtf-cfrg-xchacha-03 §2.2.1",
    "key": bytes.fromhex("000102030405060708090a0b0c0d0e0f"
                         "101112131415161718191a1b1c1d1e1f"),
    "nonce16": bytes.fromhex("000000090000004a0000000031415927"),
    "subkey": bytes.fromhex("82413b4227b27bfed30e42508a877d73"
                            "a0f9e4d58a74a853c12ec41326d3ecdc"),
}

_XCHACHA_PLAIN = bytes.fromhex(
    "5468652064686f6c65202870726f6e6f756e6365642022646f6c652229206973"
    "20616c736f206b6e6f776e2061732074686520417369617469632077696c6420"
    "646f672c2072656420646f672c20616e642077686973746c696e6720646f672e"
    "2049742069732061626f7574207468652073697a65206f662061204765726d61"
    "6e20736865706865726420627574206c6f6f6b73206d6f7265206c696b652061"
    "206c6f6e672d6c656767656420666f782e205468697320686967686c7920656c"
    "757369766520616e6420736b696c6c6564206a756d70657220697320636c6173"
    "736966696564207769746820776f6c7665732c20636f796f7465732c206a6163"
    "6b616c732c20616e6420666f78657320696e20746865207461786f6e6f6d6963"
    "2066616d696c792043616e696461652e")

XCHACHA_STREAM = {
    "ref": "draft-irtf-cfrg-xchacha-03 §A.3.2",
    "key": bytes.fromhex("808182838485868788898a8b8c8d8e8f"
                         "909192939495969798999a9b9c9d9e9f"),
    "nonce24": bytes.fromhex("404142434445464748494a4b4c4d4e4f"
                            "5051525354555658"),
    "plain": _XCHACHA_PLAIN,
    "cipher_ctr0": bytes.fromhex(
        "4559abba4e48c16102e8bb2c05e6947f50a786de162f9b0b7e592a9b53d0d4e9"
        "8d8d6410d540a1a6375b26d80dace4fab52384c731acbf16a5923c0c48d3575d"
        "4d0d2c673b666faa731061277701093a6bf7a158a8864292a41c48e3a9b4c0da"
        "ece0f8d98d0d7e05b37a307bbb66333164ec9e1b24ea0d6c3ffddcec4f68e744"
        "3056193a03c810e11344ca06d8ed8a2bfb1e8d48cfa6bc0eb4e2464b74814240"
        "7c9f431aee769960e15ba8b96890466ef2457599852385c661f752ce20f9da0c"
        "09ab6b19df74e76a95967446f8d0fd415e7bee2a12a114c20eb5292ae7a349ae"
        "577820d5520a1f3fb62a17ce6a7e68fa7c79111d8860920bc048ef43fe84486c"
        "cb87c25f0ae045f0cce1e7989a9aa220a28bdd4827e751a24a6d5c62d790a663"
        "93b93111c1a55dd7421a10184974c7c5"),
    "cipher_ctr1": bytes.fromhex(
        "7d0a2e6b7f7c65a236542630294e063b7ab9b555a5d5149aa21e4ae1e4fbce87"
        "ecc8e08a8b5e350abe622b2ffa617b202cfad72032a3037e76ffdcdc4376ee05"
        "3a190d7e46ca1de04144850381b9cb29f051915386b8a710b8ac4d027b8b050f"
        "7cba5854e028d564e453b8a968824173fc16488b8970cac828f11ae53cabd201"
        "12f87107df24ee6183d2274fe4c8b1485534ef2c5fbc1ec24bfc3663efaa08bc"
        "047d29d25043532db8391a8a3d776bf4372a6955827ccb0cdd4af403a7ce4c63"
        "d595c75a43e045f0cce1f29c8b93bd65afc5974922f214a40b7c402cdb91ae73"
        "c0b63615cdad0480680f16515a7ace9d39236464328a37743ffc28f4ddb324f4"
        "d0f5bbdc270c65b1749a6efff1fbaa09536175ccd29fb9e6057b307320d31683"
        "8a9c71f70b5b5907a66f7ea49aadc409"),
}


# ===========================================================================
# 9. RTL TB 벡터 생성
# ===========================================================================

FAM_CODES = {
    "pinned": 0x00,
    "rand": 0x01,
    "edge": 0x02,
    "nonce_tail": 0x03,
    "key_word": 0x04,
}

FAM_DOCS = {
    "pinned": "`test_hiu.py` 의 FIXED_KEY/FIXED_NONCE × phys 8종 "
              "(TB 직결 — 이 가족이 마스크 정확값 assert 의 원본)",
    "rand": "고정 seed 난수 key/nonce/phys — 일반형",
    "edge": "경계 입력 (전0 / 전1 / 1비트 key / 1비트 nonce / "
            "phys 경계)",
    "nonce_tail": "**nonce 바이트 16-23 만** 다른 인접 쌍. 폐기 RTL 에서 "
                  "이 두 라인의 마스크는 **같다** (그 64비트가 죽어 "
                  "있었다). 표준에서는 반드시 달라야 한다 — 편차 A/B "
                  "회귀의 직접 검출기",
    "key_word": "key 워드 w 의 1비트만 다른 인접 쌍 (w=0..7). 폐기 RTL "
                "에서는 마스크의 **한쪽 32비트만** 바뀐다 (그룹 분해). "
                "표준에서는 양쪽 32비트가 모두 바뀌어야 한다",
}

VEC_FIELDS = (("META", 32), ("KEY", 256), ("NONCE", 192), ("PHYS", 64),
              ("SUBKEY", 256), ("BLOCK", 512), ("MASK", 64), ("MASKED", 64))
VEC_BITS = sum(w for _, w in VEC_FIELDS)          # 1440
VEC_HEX = VEC_BITS // 4                            # 360


class VecEmitter:
    def __init__(self):
        self.lines = []
        self.families = []
        self._fam = None

    def begin(self, name):
        self._fam = {"family": name, "code": FAM_CODES[name],
                     "doc": FAM_DOCS[name], "start": len(self.lines),
                     "count": 0}
        self.families.append(self._fam)

    def emit(self, key, nonce, phys, flags=0):
        key &= (1 << 256) - 1
        nonce &= (1 << 192) - 1
        phys &= MASK64
        sk = hiu_subkey_words(key, nonce)
        blk = hiu_block_words(key, nonce)
        mask = ((blk[1] << 32) | blk[0]) & MASK64

        # 자기확인 루프 차단 — 벡터에 싣는 값은 **독립 경로**로도 같아야
        # 한다. 다르면 싣지 않고 loud fault 로 죽는다.
        alt = alt_xchacha20_block_words(_key_bytes(key), _nonce_bytes(nonce))
        if alt != blk:
            raise XChaChaFault(
                "vector emit refused: 독립 경로 블록 불일치 "
                "(key=0x%064x nonce=0x%048x)" % (key, nonce))
        if mask != standard_xchacha20_mask64(key, nonce):
            raise XChaChaFault("vector emit refused: 표준 마스크 불일치")

        serial = len(self.lines) & 0xFFFF
        meta = ((self._fam["code"] << 24) | (serial << 8) | (flags & 0xFF))
        sk_field = 0
        for j, w in enumerate(sk):
            sk_field |= w << (32 * j)
        blk_field = 0
        for j, w in enumerate(blk):
            blk_field |= w << (32 * j)
        v = meta
        for val, width in ((key, 256), (nonce, 192), (phys, 64),
                           (sk_field, 256), (blk_field, 512), (mask, 64),
                           (phys ^ mask, 64)):
            v = (v << width) | val
        if v >= (1 << VEC_BITS):
            raise XChaChaFault("vector 폭 초과")
        self.lines.append("%0*x" % (VEC_HEX, v))
        self._fam["count"] += 1
        return mask


def build_vectors():
    em = VecEmitter()

    em.begin("pinned")
    for phys in (0x0000_0000_2000_0000, 0x0000_0000_2000_0ABC,
                 0x0000_0000_1000_0000, 0x0000_0000_0000_0000,
                 0xFFFF_FFFF_FFFF_FFFF, 0x0000_0000_0000_1000,
                 0x0123_4567_89AB_CDEF, 0xFEDC_BA98_7654_3210):
        em.emit(FIXED_KEY, FIXED_NONCE, phys)

    em.begin("rand")
    rnd = random.Random(SEEDS["vec_rand"])
    for _ in range(32):
        em.emit(rnd.getrandbits(256), rnd.getrandbits(192),
                rnd.getrandbits(64))

    em.begin("edge")
    rnd = random.Random(SEEDS["vec_edge"])
    edges = [
        (0, 0, 0),
        ((1 << 256) - 1, (1 << 192) - 1, MASK64),
        (1, 0, 0x1000),
        (1 << 255, 0, 0x1000),
        (0, 1, 0x1000),
        (0, 1 << 191, 0x1000),
        (0, 1 << 128, 0x1000),                     # nonce 바이트 16 의 LSB
        (FIXED_KEY, 0, rnd.getrandbits(64)),
    ]
    for k, n, p in edges:
        em.emit(k, n, p)

    em.begin("nonce_tail")
    rnd = random.Random(SEEDS["vec_pair"])
    for i in range(8):
        k = rnd.getrandbits(256)
        n = rnd.getrandbits(192)
        # 바이트 16-23 = 비트 128-191 만 건드린다.
        n2 = n ^ (1 << (128 + rnd.randrange(64)))
        p = rnd.getrandbits(64)
        m1 = em.emit(k, n, p, flags=0x01)           # 쌍의 앞 라인
        m2 = em.emit(k, n2, p, flags=0x02)          # 쌍의 뒤 라인
        if m1 == m2:
            raise XChaChaFault(
                "nonce_tail 쌍 %d 의 마스크가 같다 — 표준에서는 불가능" % i)
        # 계약 §6 표의 좌열 ("폐기 RTL 에서는 **동일**") 을 산문으로
        # 두지 않고 기계로 확인한다 — 검출기의 검출력 실증.
        if legacy_mask64(k, n) != legacy_mask64(k, n2):
            raise XChaChaFault(
                "nonce_tail 쌍 %d 가 폐기 경로에서 이미 달라진다 — 이 "
                "가족의 검출력 근거(nonce 64비트 사망)가 무너졌다" % i)

    em.begin("key_word")
    rnd = random.Random(SEEDS["vec_pair"] ^ 0xFFFF)
    for w in range(8):
        k = rnd.getrandbits(256)
        n = rnd.getrandbits(192)
        k2 = k ^ (1 << (32 * w + rnd.randrange(32)))   # key 워드 w 만 1비트
        p = rnd.getrandbits(64)
        m1 = em.emit(k, n, p, flags=0x01)              # 쌍의 앞 라인
        m2 = em.emit(k2, n, p, flags=0x02)             # 쌍의 뒤 라인
        if (m1 & MASK32) == (m2 & MASK32) or (m1 >> 32) == (m2 >> 32):
            raise XChaChaFault(
                "key_word 쌍 w=%d: 마스크 32비트 반쪽 하나가 안 바뀌었다 "
                "— 그룹 분해 회귀" % w)
        # 계약 §6 표의 좌열 ("폐기 RTL 에서는 한쪽 32비트만 변화").
        l1, l2 = legacy_mask64(k, n), legacy_mask64(k2, n)
        lo_moved = (l1 & MASK32) != (l2 & MASK32)
        hi_moved = (l1 >> 32) != (l2 >> 32)
        if lo_moved == hi_moved:
            raise XChaChaFault(
                "key_word 쌍 w=%d 가 폐기 경로에서 양쪽/무변화다 — 이 "
                "가족의 검출력 근거(그룹 분해)가 무너졌다" % w)
    return em


def write_vector_file(em):
    hdr = [
        "// xchacha_vectors.hex — HIU 주소 마스킹 (표준 XChaCha20) golden "
        "벡터 (결정적, 고정 seed)",
        "// 생성기: scripts/golden_xchacha.py — 비트 레이아웃 계약: "
        "include/generated/xchacha_vec_contract.md",
        "// 1 line = 1 변환 = %d hex chars = %d bits; N_VEC = %d"
        % (VEC_HEX, VEC_BITS, len(em.lines)),
    ]
    VEC_PATH.write_text("\n".join(hdr + em.lines) + "\n")


def verify_vector_file():
    """파일 재독 → 필드 분해 → **독립 경로**로 전 필드 재대조."""
    n = 0
    for ln in VEC_PATH.read_text().splitlines():
        if not ln or ln.startswith("//"):
            continue
        if len(ln) != VEC_HEX:
            raise XChaChaFault("라인 길이 %d != %d" % (len(ln), VEC_HEX))
        v = int(ln, 16)
        fields = {}
        for name, width in reversed(VEC_FIELDS):
            fields[name] = v & ((1 << width) - 1)
            v >>= width
        key, nonce, phys = fields["KEY"], fields["NONCE"], fields["PHYS"]

        alt = alt_xchacha20_block_words(_key_bytes(key), _nonce_bytes(nonce))
        blk_field = 0
        for j, w in enumerate(alt):
            blk_field |= w << (32 * j)
        if blk_field != fields["BLOCK"]:
            raise XChaChaFault("line %d: BLOCK 이 독립 경로와 다르다" % n)

        sk = hchacha20(_key_bytes(key), _nonce_bytes(nonce)[:16])
        sk_field = int.from_bytes(sk, "little")
        if sk_field != fields["SUBKEY"]:
            raise XChaChaFault("line %d: SUBKEY 불일치" % n)

        mask = ((alt[1] << 32) | alt[0]) & MASK64
        if mask != fields["MASK"]:
            raise XChaChaFault("line %d: MASK 불일치" % n)
        if (phys ^ mask) != fields["MASKED"]:
            raise XChaChaFault("line %d: MASKED 불일치" % n)
        if mask != hiu_mask64(key, nonce):
            raise XChaChaFault("line %d: hiu_mask64 와 불일치" % n)
        n += 1
    return n


# ===========================================================================
# 10. self-test
# ===========================================================================

def _test_rfc8439_quarter_round():
    s = list(RFC8439_QR["in"])
    quarter_round(s, 0, 1, 2, 3)
    assert s == RFC8439_QR["out"], s


def _test_rfc8439_block():
    v = RFC8439_BLOCK
    got = chacha20_block(v["key"], v["counter"], v["nonce"])
    assert got == v["out"], got.hex()


def _test_rfc8439_encrypt():
    v = RFC8439_ENCRYPT
    got = chacha20_xor(v["key"], v["counter"], v["nonce"], v["plain"])
    assert got == v["cipher"], got.hex()
    assert chacha20_xor(v["key"], v["counter"], v["nonce"], got) == v["plain"]


def _test_hchacha20():
    v = XCHACHA_HCHACHA
    got = hchacha20(v["key"], v["nonce16"])
    assert got == v["subkey"], got.hex()


def _test_xchacha20_stream():
    """draft §A.3.2 — **XChaCha20 전체 구성**의 외부 anchor.

    이것이 편차 A (nonce 배치) 를 잡는 검사다: 워드 13/14/15 배치가
    표준과 다르면 300바이트 전체가 어긋난다.
    """
    v = XCHACHA_STREAM
    got0 = xchacha20_xor(v["key"], v["nonce24"], v["plain"], counter=0)
    assert got0 == v["cipher_ctr0"], got0.hex()
    got1 = xchacha20_xor(v["key"], v["nonce24"], v["plain"], counter=1)
    assert got1 == v["cipher_ctr1"], got1.hex()
    # 첫 블록의 워드 0/1 = 마스크 추출 경로. 키스트림 = plain ^ cipher.
    ks = bytes(a ^ b for a, b in zip(v["plain"], v["cipher_ctr0"]))
    blk = xchacha20_block_words(v["key"], v["nonce24"], 0)
    assert _bytes_le(blk)[:8] == ks[:8]
    assert ((blk[1] << 32) | blk[0]) == int.from_bytes(ks[:8], "little")


def _test_alt_path_agreement():
    """1절과 2절 (독립 재구현) 이 같은 값을 낸다."""
    rnd = random.Random(0x5A17)
    for _ in range(16):
        k = rnd.getrandbits(256)
        n = rnd.getrandbits(192)
        assert alt_xchacha20_block_words(_key_bytes(k), _nonce_bytes(n)) \
            == hiu_block_words(k, n)
    v = XCHACHA_HCHACHA
    assert alt_xchacha20_block_words(
        v["key"], v["nonce16"] + b"\x00" * 8)[0:2] == \
        xchacha20_block_words(v["key"], v["nonce16"] + b"\x00" * 8)[0:2]


def _test_hiu_contract_is_standard():
    """HIU 계약 = 표준. 두 경로가 갈라지면 여기서 먼저 깨진다."""
    rnd = random.Random(0xC0FFEE)
    for _ in range(8):
        k = rnd.getrandbits(256)
        n = rnd.getrandbits(192)
        assert hiu_mask64(k, n) == standard_xchacha20_mask64(k, n)
    assert hiu_mask64(FIXED_KEY, FIXED_NONCE) \
        == standard_xchacha20_mask64(FIXED_KEY, FIXED_NONCE)


def _test_legacy_pin():
    """폐기 알고리즘의 실측 pin — "무엇을 고쳤는가" 의 기준."""
    got = legacy_mask64(FIXED_KEY, FIXED_NONCE)
    assert got == LEGACY_MEASURED_MASK64, \
        ("legacy_mask64 = 0x%016x, verilator 실측 pin 0x%016x — 재현이 "
         "깨졌다면 폐기 알고리즘의 서술 자체를 재유도하라"
         % (got, LEGACY_MEASURED_MASK64))
    assert got != hiu_mask64(FIXED_KEY, FIXED_NONCE), \
        "폐기값과 표준값이 같다 — 둘 중 하나의 모델이 무너졌다"


def _test_round_structure_deviation_shape():
    """폐기 알고리즘의 성질을 구조로 확인한다 (서술이 참인지 기계로 본다).

    (i) diagonal 4쌍의 인덱스 합집합이 정확히 0..15 라서 column 결과가
        하나도 살아남지 못한다,
    (ii) 그러므로 `legacy_round_cycle` 은 "diagonal 만 적용" 과 같다,
    (iii) 그리고 그것은 표준 double round 와 다르다.
    """
    union = set()
    for q in DIAG_QUADS:
        union |= set(q)
    assert union == set(range(16)), \
        "diagonal 합집합이 0..15 가 아니다 — 폐기 서술을 재유도하라"

    st = [(i * 0x9E3779B1) & MASK32 for i in range(16)]
    diag_only = list(st)
    for q in DIAG_QUADS:
        (diag_only[q[0]], diag_only[q[1]],
         diag_only[q[2]], diag_only[q[3]]) = _qr_pure(st, *q)
    assert legacy_round_cycle(st) == diag_only, \
        "column round 가 살아남았다 — 폐기 서술이 틀렸다"
    std = list(st)
    double_round(std)
    assert legacy_round_cycle(st) != std


def _test_diffusion_claims(diff):
    """docstring 의 수치 주장을 실측으로 강제한다 (문서가 늙지 않게)."""
    assert diff["orbit_groups_legacy"] == [
        [0, 5, 10, 15], [1, 6, 11, 12], [2, 7, 8, 13], [3, 4, 9, 14]], \
        diff["orbit_groups_legacy"]
    wd = diff["word_dependency"]
    assert wd["legacy_cells"] == 64 and wd["standard_cells"] == 256, wd
    assert wd["legacy_out_word0_deps"] == [0, 5, 10, 15]
    assert wd["legacy_out_word1_deps"] == [1, 6, 11, 12]

    md = diff["mask_input_dependence"]
    assert md["legacy"]["dead_nonce_bits"] == 64, md["legacy"]
    assert md["standard"]["dead_nonce_bits"] == 0, md["standard"]
    assert md["legacy"]["mask_lo_key_words"] == [0, 2, 5, 7]
    assert md["legacy"]["mask_hi_key_words"] == [1, 3, 4, 6]
    assert set(md["legacy"]["mask_lo_key_words"]) & \
        set(md["legacy"]["mask_hi_key_words"]) == set(), \
        "폐기 경로의 key 워드 반쪽이 서로소가 아니다 — 서술 재유도"
    assert md["standard"]["mask_lo_key_words"] == list(range(8))
    assert md["standard"]["mask_hi_key_words"] == list(range(8))

    sk = diff["subkey_word_dependence"]
    assert sk["legacy"] == [1, 2, 6, 7], sk["legacy"]
    assert sk["standard"] == list(range(8)), sk["standard"]

    av = diff["avalanche"]
    assert av["standard"]["key_zero_change"] == 0
    assert av["standard"]["nonce_zero_change"] == 0
    assert 45.0 <= av["standard"]["key_mean_pct"] <= 55.0, av["standard"]
    assert 45.0 <= av["standard"]["nonce_mean_pct"] <= 55.0, av["standard"]
    assert av["legacy"]["key_mean_pct"] < 30.0, av["legacy"]
    assert av["legacy"]["nonce_zero_change"] > 0, av["legacy"]


def _test_determinism():
    a = hiu_masked_phys(0x0000000020001100, FIXED_KEY, FIXED_NONCE)
    b = hiu_masked_phys(0x0000000020001100, FIXED_KEY, FIXED_NONCE)
    assert a == b


def _test_xor_involution():
    m = hiu_mask64(FIXED_KEY, FIXED_NONCE)
    for pa in (0, 1, 0x20000000, MASK64):
        assert hiu_masked_phys(pa, FIXED_KEY, FIXED_NONCE) == (pa ^ m)


def _test_port_encoding():
    """포트 정수 ↔ 워드 대응 (RTL 슬라이스와 같은지)."""
    k = 0x1F1E1D1C_1B1A1918_17161514_13121110 \
        << 128 | 0x0F0E0D0C_0B0A0908_07060504_03020100
    assert _key_bytes(k) == bytes(range(32))
    assert _words_le(_key_bytes(k))[0] == 0x03020100
    n = int.from_bytes(bytes(range(24)), "little")
    assert _nonce_bytes(n) == bytes(range(24))


# ===========================================================================
# 11. 산출물 (contract md / report json)
# ===========================================================================

def _sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def contract_text(em, diff, n_vec):
    fam_rows = "\n".join(
        "| 0x%02X | `%s` | %d | %d | %s |"
        % (f["code"], f["family"], f["start"], f["count"], f["doc"])
        for f in em.families)
    seed_rows = "\n".join("| `%s` | `0x%X` |" % kv for kv in SEEDS.items())
    off = VEC_BITS
    field_rows = []
    for name, width in VEC_FIELDS:
        hi = off - 1
        off -= width
        field_rows.append("| `%s` | %d | [%d:%d] |" % (name, width, hi, off))
    field_rows = "\n".join(field_rows)

    md = diff["mask_input_dependence"]
    av = diff["avalanche"]
    wd = diff["word_dependency"]

    return """<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor \
contributors -->

# xchacha_vectors.hex — HIU 주소 마스킹 (표준 XChaCha20) 벡터 계약

생성기: `scripts/golden_xchacha.py` (stdlib-only, 고정 seed, 재실행
byte-identical). 규범 출처: **RFC 8439** (ChaCha20) + **draft-irtf-cfrg-
xchacha-03** (HChaCha20 §2.2 / XChaCha20 구성 §2.3 / 테스트 벡터 §A.3.2),
그리고 wt64v1_spec.md **§29.8** (HIU 가 XChaCha20 을 쓴다는 선언).

이 벡터는 **golden-before-RTL** 산출물이다 — RTL 수리보다 먼저 착지하며,
수리된 `HIU.v` 가 만족해야 할 값을 정의한다.

## 1. 라인 형식

`$readmemh`, 주석 3줄 + %d 라인. 1 line = 1 변환 = %d hex chars =
%d bits, MSB-first:

| 필드 | 폭 | 위치 (MSB 기준) |
|---|---|---|
%s

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
%s

## 3. seed (난수원/timestamp 없음)

| 이름 | 값 |
|---|---|
%s

## 4. 값 계약 (RTL 이 이행해야 할 것)

1. **HChaCha20 (1단).** 초기상태 = `{상수 4, chacha_key 8워드,
   chacha_nonce 바이트 0-15 의 4워드}`. double round %d회. 출력 subkey =
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
| 상태 분할 | 4그룹 `%s` | 분할 없음 |
| 워드 의존 밀도 (10 라운드) | %d/256 | %d/256 |
| 마스크에 살아 있는 nonce 비트 | %d/192 | %d/192 |
| mask 하위 32b 가 보는 key 워드 | %s | %s |
| mask 상위 32b 가 보는 key 워드 | %s | %s |
| 마스크가 보는 subkey 워드 | %s | %s |
| avalanche (key 1비트 → 마스크) | %.2f/64 (%.1f%%) | %.2f/64 (%.1f%%) |
| avalanche (nonce 1비트) | %.2f/64 (%.1f%%) | %.2f/64 (%.1f%%) |
| 변화 0비트인 nonce flip 비율 | %.1f%% | %.1f%% |

정직 명기: 위 수치는 **구현 편차의 크기**를 재는 것이지 XChaCha20 자체의
안전성을 재는 것이 아니다. 64-bit 마스크로 주소를 XOR 하는 구성의 보안
강도·키 재사용 정책·counter 고정(=0) 의 함의는 본 계약의 대상이 아니다.
""" % (n_vec, VEC_HEX, VEC_BITS, field_rows, fam_rows, seed_rows,
       CHACHA_ROUNDS // 2,
       diff["orbit_groups_legacy"],
       wd["legacy_cells"], wd["standard_cells"],
       192 - md["legacy"]["dead_nonce_bits"],
       192 - md["standard"]["dead_nonce_bits"],
       md["legacy"]["mask_lo_key_words"], md["standard"]["mask_lo_key_words"],
       md["legacy"]["mask_hi_key_words"], md["standard"]["mask_hi_key_words"],
       diff["subkey_word_dependence"]["legacy"],
       diff["subkey_word_dependence"]["standard"],
       av["legacy"]["key_mean_bits"], av["legacy"]["key_mean_pct"],
       av["standard"]["key_mean_bits"], av["standard"]["key_mean_pct"],
       av["legacy"]["nonce_mean_bits"], av["legacy"]["nonce_mean_pct"],
       av["standard"]["nonce_mean_bits"], av["standard"]["nonce_mean_pct"],
       av["legacy"]["nonce_zero_change_pct"],
       av["standard"]["nonce_zero_change_pct"])


def build_report(em, diff, n_vec, n_verified):
    return {
        "_doc": "HIU 주소 마스킹 golden = 표준 XChaCha20 (spec §29.8 D8 "
                "수리의 golden-before-RTL 전건) 의 자기검증 결과 + RTL TB "
                "벡터 명세. 생성기: scripts/golden_xchacha.py (stdlib-only, "
                "고정 seed, 재실행 byte-identical). 벡터 계약: "
                "include/generated/xchacha_vec_contract.md.",
        "normative_source": {
            "chacha20": "RFC 8439 §2.1 (quarter-round) / §2.3 (block) / "
                        "§2.4 (encryption)",
            "hchacha20": "draft-irtf-cfrg-xchacha-03 §2.2",
            "xchacha20": "draft-irtf-cfrg-xchacha-03 §2.3 (구성) / §A.3.2 "
                         "(테스트 벡터)",
            "spec": "wt64v1_spec.md §29.8 (D8)",
        },
        "determinism": {
            "seeds": SEEDS,
            "note": "고정 정수 seed 외 난수원/timestamp 없음 — 산출물 3종 "
                    "(hex/md/json) 전부 byte-identical 재생성",
        },
        "standard_test_vectors": {
            "rfc8439_2_1_1_quarter_round": "PASS",
            "rfc8439_2_3_2_block": "PASS",
            "rfc8439_2_4_2_encryption": "PASS",
            "xchacha_2_2_1_hchacha20": "PASS",
            "xchacha_a_3_2_1_stream_ctr0": "PASS",
            "xchacha_a_3_2_2_stream_ctr1": "PASS",
            "note": "여섯 벡터 전부 표준 문서에서 그대로 옮긴 값이며 "
                    "self-test 가 assert 한다. §A.3.2 (300바이트, counter "
                    "0/1) 는 **구성 전체**를 건다 — nonce 워드 배치가 "
                    "틀리면 전량 어긋난다.",
        },
        "contract": {
            "mask64": "{block_word1, block_word0} (상위 32b = 워드 1)",
            "masked_phys_addr": "phys_addr ^ mask64",
            "stage2_state_words_12_15": ["counter=0", "0",
                                         "nonce[16:20]", "nonce[20:24]"],
            "rounds": CHACHA_ROUNDS,
            "fixed_key": "0x%064x" % FIXED_KEY,
            "fixed_nonce": "0x%048x" % FIXED_NONCE,
            "fixed_mask64_standard": "0x%016x"
                                     % hiu_mask64(FIXED_KEY, FIXED_NONCE),
            "fixed_subkey_standard": hiu_subkey(FIXED_KEY,
                                                FIXED_NONCE).hex(),
        },
        "legacy_pre_repair": {
            "_doc": "폐기된 RTL 알고리즘 — 삭제하지 않고 모델로 남긴다. "
                    "회귀하면 마스크가 이 값으로 되돌아가므로 즉시 "
                    "검출된다.",
            "deviation_a_nonce_layout":
                "state[13]=nonce[16:20], [14]=nonce[20:24], [15]=0 "
                "(표준: [13]=0, [14]=nonce[16:20], [15]=nonce[20:24])",
            "deviation_b_round_structure":
                "8 quarter-round 를 같은 (직전) 상태에서 병렬 계산 → "
                "diagonal 4쌍이 column 4쌍을 전량 덮음 → 한 cycle = "
                "diagonal round 1회",
            "fixed_mask64_legacy": "0x%016x" % legacy_mask64(FIXED_KEY,
                                                             FIXED_NONCE),
            "verilator_measured_pin": "0x%016x" % LEGACY_MEASURED_MASK64,
            "pin_reproduced": legacy_mask64(FIXED_KEY, FIXED_NONCE)
            == LEGACY_MEASURED_MASK64,
        },
        "diffusion": diff,
        "vectors": {
            "path": str(VEC_PATH.relative_to(REPO)),
            "n_vec": n_vec,
            "vec_bits": VEC_BITS,
            "vec_hex_chars": VEC_HEX,
            "fields": [{"name": n, "width": w} for n, w in VEC_FIELDS],
            "families": em.families,
            "verified_lines": n_verified,
            "verify_path": "재독 후 독립 재구현 (SIMD 정식화) 으로 "
                           "BLOCK/SUBKEY/MASK/MASKED 전 필드 재대조",
        },
        "checks": {
            "hiu_contract_equals_standard": True,
            "legacy_differs_from_standard": True,
            "vector_lines_verified": n_verified == n_vec,
            "artifacts_sha256": {
                "xchacha_vectors.hex": _sha256(VEC_PATH),
                "xchacha_vec_contract.md": _sha256(CONTRACT_PATH),
            },
        },
    }


# ===========================================================================
# 12. main
# ===========================================================================

def main():
    print("golden_xchacha: HIU 주소 마스킹 golden = 표준 XChaCha20 "
          "(§29.8 D8, golden-before-RTL)")

    _test_port_encoding()
    _test_rfc8439_quarter_round()
    _test_rfc8439_block()
    _test_rfc8439_encrypt()
    _test_hchacha20()
    _test_xchacha20_stream()
    _test_alt_path_agreement()
    _test_hiu_contract_is_standard()
    _test_legacy_pin()
    _test_round_structure_deviation_shape()
    _test_determinism()
    _test_xor_involution()
    print("  표준 테스트 벡터 6종 + 계약 self-test: PASS")

    diff = measure_diffusion()
    _test_diffusion_claims(diff)
    print("  확산 실측 + 수치 주장 대조: PASS")

    GEN.mkdir(parents=True, exist_ok=True)
    em = build_vectors()
    write_vector_file(em)
    n_verified = verify_vector_file()
    if n_verified != len(em.lines):
        raise XChaChaFault("재독 라인 수 불일치 %d != %d"
                           % (n_verified, len(em.lines)))
    CONTRACT_PATH.write_text(contract_text(em, diff, len(em.lines)))
    report = build_report(em, diff, len(em.lines), n_verified)
    REPORT_PATH.write_text(json.dumps(report, indent=1, ensure_ascii=False)
                           + "\n")

    md = diff["mask_input_dependence"]
    av = diff["avalanche"]
    wd = diff["word_dependency"]
    print("  벡터 %d 라인 → %s" % (len(em.lines),
                                   VEC_PATH.relative_to(REPO)))
    print("  계약   → %s" % CONTRACT_PATH.relative_to(REPO))
    print("  report → %s" % REPORT_PATH.relative_to(REPO))
    print()
    print("  FIXED_KEY      = 0x%064x" % FIXED_KEY)
    print("  FIXED_NONCE    = 0x%048x" % FIXED_NONCE)
    print("  mask64 (표준)  = 0x%016x   <-- RTL 이 내야 할 값"
          % hiu_mask64(FIXED_KEY, FIXED_NONCE))
    print("  mask64 (폐기)  = 0x%016x   (verilator 실측 pin 재현)"
          % legacy_mask64(FIXED_KEY, FIXED_NONCE))
    print("  subkey (표준)  = %s" % hiu_subkey(FIXED_KEY, FIXED_NONCE).hex())
    print()
    print("  확산 붕괴 실측 (폐기 → 표준):")
    print("    상태 분할          %s → 없음" % diff["orbit_groups_legacy"])
    print("    워드 의존 밀도     %d/256 → %d/256"
          % (wd["legacy_cells"], wd["standard_cells"]))
    print("    살아 있는 nonce    %d/192 → %d/192"
          % (192 - md["legacy"]["dead_nonce_bits"],
             192 - md["standard"]["dead_nonce_bits"]))
    print("    mask_lo key 워드   %s → %s"
          % (md["legacy"]["mask_lo_key_words"],
             md["standard"]["mask_lo_key_words"]))
    print("    mask_hi key 워드   %s → %s"
          % (md["legacy"]["mask_hi_key_words"],
             md["standard"]["mask_hi_key_words"]))
    print("    subkey 워드 의존   %s → %s"
          % (diff["subkey_word_dependence"]["legacy"],
             diff["subkey_word_dependence"]["standard"]))
    print("    avalanche (key)    %.2f/64 (%.1f%%) → %.2f/64 (%.1f%%)"
          % (av["legacy"]["key_mean_bits"], av["legacy"]["key_mean_pct"],
             av["standard"]["key_mean_bits"], av["standard"]["key_mean_pct"]))
    print("    avalanche (nonce)  %.2f/64 (%.1f%%) → %.2f/64 (%.1f%%)"
          % (av["legacy"]["nonce_mean_bits"], av["legacy"]["nonce_mean_pct"],
             av["standard"]["nonce_mean_bits"],
             av["standard"]["nonce_mean_pct"]))
    print("    0비트 변화 nonce   %.1f%% → %.1f%%"
          % (av["legacy"]["nonce_zero_change_pct"],
             av["standard"]["nonce_zero_change_pct"]))
    print()
    print("  NOTE golden-before-RTL — `HIU.v` 수리 전에는 test_hiu.py 의")
    print("       마스크 assert 가 **의도적으로 FAIL** 한다. 수리 후")
    print("       GREEN 이 되는 것이 착지 조건이다 (계약 §4/§5 참조).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
