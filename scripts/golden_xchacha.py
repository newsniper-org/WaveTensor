#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""golden_xchacha.py — HIU 주소 마스킹 (XChaCha20) 의 golden model
(spec §29.8 — 결함 D8 수리의 golden-before-RTL 전건, 착지 단계 S2-C1).

왜 이 파일이 존재하는가
-----------------------
`test_hiu.py` 는 3.5개월 동안 마스킹을 `masked_phys_addr != phys_addr`
로만 검사했다 — 마스크가 **무엇이든** 0 이 아니면 통과한다. 그 사이
`HIU.v` 의 `CHACHA_H_INIT` / `CHACHA_INIT` 은 같은 사이클에
`initial_state[*] <= 상수/키/nonce` 와 `chacha_state[m] <= initial_state[m]`
을 함께 수행하고 있었고 (비차단 대입 → RHS 는 **직전** 값), 그 결과
subkey 가 HChaCha20 사양대로 유도되지 않고 ChaCha20 라운드가 subkey
상태 위에서 돌지 않았다. 즉 **선언된 암호 계약이 실물에서 이행되지
않았고, 값을 보지 않는 테스트가 그것을 은폐했다** (spec §29.8).

이 golden 은 그 은폐 경로를 닫는다: `test_hiu.py` 가 `masked_phys_addr`
를 여기서 산출한 **정확값**과 비교한다.

구성 (전부 stdlib-only, 고정 벡터, 재실행 byte-identical)
--------------------------------------------------------
  * `chacha20_block()`  — RFC 8439 §2.3 ChaCha20 블록 함수
  * `hchacha20()`       — draft-irtf-cfrg-xchacha §2.2 HChaCha20
  * `hiu_mask64()`      — 위 두 원시함수로 **HIU.v 가 실제로 만드는**
                          64-bit 마스크를 재현
  * `hiu_masked_phys()` — `masked_phys_addr = phys_addr ^ mask64`

자기검증 (`python3 scripts/golden_xchacha.py` 로 전부 assert):
  * RFC 8439 §2.3.2 ChaCha20 블록 테스트 벡터
  * RFC 8439 §2.1.1 quarter-round 테스트 벡터
  * draft-irtf-cfrg-xchacha §2.2.1 HChaCha20 테스트 벡터
  * 결정성 — 같은 입력 재실행 bit-identical

정직 명기 1 — **RTL 은 표준 XChaCha20 이 아니다. 편차 2건.**
------------------------------------------------------------
본 golden 을 쓰면서 §29.8 이 기록하지 않은 편차 **2건**이 드러났다.
이것이 golden-before-RTL law 가 존재하는 이유 그 자체다 — 값을 보는
순간에만 보이는 것들이다. 둘 다 **§29.8 의 normative 수리 형태
("`initial_state` 를 경유하지 않는 직접 대입") 밖**이므로 본 세션은
**RTL 을 고치지 않고 모델링 + 명명**한다 (§12a 규칙 3: spec 없는
의미론 변경 금지). 판정은 spec 소유자 몫이다.

  **편차 A — nonce 워드 배치 (`HIU_NONCE_LAYOUT_DEVIATION`)**
  표준: `state[12]=counter, state[13]=0, state[14]=nonce[16:20],
        state[15]=nonce[20:24]`
  RTL (`HIU.v` `CHACHA_INIT`): `state[12]=0(counter),
        state[13]=nonce[16:20], state[14]=nonce[20:24], state[15]=0`
  → 두 nonce 워드가 **한 칸씩 앞으로 밀려 있다.**

  **편차 B — 라운드 구조 (`HIU_ROUND_STRUCTURE_DEVIATION`). 더 무겁다.**
  `CHACHA_H_MASK` / `CHACHA_MASK` 는 한 cycle 에 8개의
  `chacha_qr_func` 호출을 나열한다. 그런데 그 함수는 **레지스터
  `chacha_state` 를 직접 읽고**, 8개 대입은 전부 **비차단**이다. 따라서
  8개 전부가 **같은 (직전) 상태**에서 계산되며, column round 4개가 쓴
  16워드를 diagonal round 4개가 **전부 덮어쓴다** (diagonal 4-쌍의 인덱스
  합집합이 정확히 0..15 이다). 즉 RTL 의 한 "double round" cycle 은
  실제로는 **diagonal round 1회**이고, column round 는 계산만 되고
  버려진다. 10 cycle × diagonal-only ≠ ChaCha20 20 라운드.

  실측 확인 (verilator, 고정 벡터): 아래 `hiu_mask64()` 가 산출하는
  `0x817eba4a8961a7d6` 이 RTL `masked_phys_addr ^ phys_addr` 과
  **bit-exact 일치**한다. 즉 편차 B 는 추정이 아니라 실측이다.

  **왜 이번 세션이 편차 B 를 고치지 않는가 (기각 근거 3건):**
   1. §29.8 의 수리 형태는 대입 경로 하나만 규정한다 — 라운드 구조
      변경은 별개의 계약 변경이고 spec-first 대상이다.
   2. 수리는 quarter-round 2단을 **직렬로** 잇는 것이라 조합 depth 가
      2배가 된다. GATE S1 에서 **WHS 는 마진 +0.019 ns 의 binding 축**
      이고 §29.11 이 "본 변경의 유일한 실질 리스크 축" 으로 지목했다.
      암호 의미론 수리를 D4 면적/타이밍 측정과 같은 commit 에 섞으면
      **어느 쪽 실측인지 귀속이 불가능해진다.**
   3. 값을 바꾸면 이 golden 의 고정 벡터도 함께 바뀐다 — 판정 전에
      기준을 움직이는 형태가 된다.

  **그래서 하는 일:** `standard_xchacha20_mask64()` 를 나란히 두고,
  두 값이 **다르다**는 사실 자체를 self-test 가 assert 한다. 편차가
  정정되면 그 self-test 가 **먼저 깨져서** 알려준다 — 조용히 넘어갈
  경로가 없다 (loud-fault-never-silent 의 golden 측 이행).

정직 명기 2 — 이것은 암호학적 강도 주장이 아니다
-----------------------------------------------
본 golden 은 "RTL 이 자기 사양대로 계산하는가" 만 판정한다. 64-bit
마스크로 주소를 XOR 하는 구성 자체의 보안 강도, 키/nonce 재사용 정책,
counter 고정(=0) 의 함의는 본 파일의 대상이 아니다.
"""

import sys

MASK32 = 0xFFFFFFFF

# ChaCha20 상수 "expand 32-byte k" 를 little-endian 32-bit 워드로 분해한 값.
CHACHA_CONST = (0x61707865, 0x3320646E, 0x79622D32, 0x6B206574)

# RTL 의 CHACHA_ROUNDS 파라미터 기본값 (HIU.v:12). 라운드 수는 double
# round 단위로 소비된다 — RTL 의 `round_counter < CHACHA_ROUNDS/2` 가
# 8 quarter-round(= 1 double round) 를 CHACHA_ROUNDS/2 회 수행한다.
CHACHA_ROUNDS = 20

# §29.8 정직 명기 1 — RTL 이 표준 XChaCha20 과 갈라지는 지점의 기계
# 판독 가능한 이름. True 인 동안 hiu_* 함수는 **RTL 실물**을 재현한다.
HIU_NONCE_LAYOUT_DEVIATION = True     # 편차 A — nonce 워드 한 칸 밀림
HIU_ROUND_STRUCTURE_DEVIATION = True  # 편차 B — column round 가 덮여 사라짐


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


def double_round(s):
    """RFC 8439 §2.3.1 — column round 4개 + diagonal round 4개."""
    quarter_round(s, 0, 4, 8, 12)
    quarter_round(s, 1, 5, 9, 13)
    quarter_round(s, 2, 6, 10, 14)
    quarter_round(s, 3, 7, 11, 15)
    quarter_round(s, 0, 5, 10, 15)
    quarter_round(s, 1, 6, 11, 12)
    quarter_round(s, 2, 7, 8, 13)
    quarter_round(s, 3, 4, 9, 14)


def _words_le(data):
    """바이트열 → little-endian 32-bit 워드 리스트."""
    if len(data) % 4:
        raise ValueError("길이가 4의 배수가 아니다")
    return [int.from_bytes(data[i:i + 4], "little")
            for i in range(0, len(data), 4)]


def chacha20_state(key, counter, nonce):
    """ChaCha20 초기 상태 16워드 (key 32B, counter 32-bit, nonce 12B)."""
    if len(key) != 32:
        raise ValueError("key 는 32바이트여야 한다")
    if len(nonce) != 12:
        raise ValueError("nonce 는 12바이트여야 한다")
    return (list(CHACHA_CONST) + _words_le(key)
            + [counter & MASK32] + _words_le(nonce))


def chacha20_block(key, counter, nonce, rounds=CHACHA_ROUNDS):
    """RFC 8439 §2.3 — 64바이트 키스트림 블록."""
    init = chacha20_state(key, counter, nonce)
    work = list(init)
    for _ in range(rounds // 2):
        double_round(work)
    out = [(work[i] + init[i]) & MASK32 for i in range(16)]
    return b"".join(w.to_bytes(4, "little") for w in out)


def hchacha20(key, nonce16, rounds=CHACHA_ROUNDS):
    """draft-irtf-cfrg-xchacha §2.2 — 32바이트 subkey.

    최종 덧셈이 **없는** 것이 ChaCha20 블록 함수와의 차이다. 출력은
    라운드 후 상태의 word 0-3 과 12-15 를 little-endian 으로 직렬화한
    것이다 — `HIU.v` 의 `CHACHA_H_MASK` else 분기가 하는 일과 같다.
    """
    if len(key) != 32:
        raise ValueError("key 는 32바이트여야 한다")
    if len(nonce16) != 16:
        raise ValueError("HChaCha20 nonce 는 16바이트여야 한다")
    work = list(CHACHA_CONST) + _words_le(key) + _words_le(nonce16)
    for _ in range(rounds // 2):
        double_round(work)
    sel = [work[0], work[1], work[2], work[3],
           work[12], work[13], work[14], work[15]]
    return b"".join(w.to_bytes(4, "little") for w in sel)


# ---------------------------------------------------------------------------
# HIU.v 재현 경로
# ---------------------------------------------------------------------------

def _key_bytes(chacha_key):
    """`chacha_key` (256-bit 정수 포트값) → 32바이트.

    RTL 은 `initial_state[4+n] <= chacha_key[32n+31 : 32n]` 으로 워드를
    뽑는다. 즉 포트 정수의 최하위 32비트가 key word 0 이고, 이는 key
    바이트열을 little-endian 으로 본 것과 정확히 같다.
    """
    return int(chacha_key).to_bytes(32, "little")


def _nonce_bytes(chacha_nonce):
    """`chacha_nonce` (192-bit 정수 포트값) → 24바이트 (같은 논거)."""
    return int(chacha_nonce).to_bytes(24, "little")


# column / diagonal quarter-round 쌍 — `HIU.v` 의 나열 순서 그대로.
_COL_QUADS = ((0, 4, 8, 12), (1, 5, 9, 13), (2, 6, 10, 14), (3, 7, 11, 15))
_DIAG_QUADS = ((0, 5, 10, 15), (1, 6, 11, 12), (2, 7, 8, 13), (3, 4, 9, 14))


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


def hiu_round_cycle(state):
    """`CHACHA_*_MASK` 한 cycle 의 **실물** 동작 (편차 B).

    8개 호출 전부가 직전 상태 `old` 에서 계산되고, 비차단 대입의
    나중-대입 규칙 때문에 diagonal 4쌍이 column 4쌍을 **완전히**
    덮는다 (diagonal 인덱스 합집합 = 0..15). column 루프를 코드에
    남겨 두는 것은 그 사실을 눈으로 볼 수 있게 하기 위해서다 — 지우면
    "왜 diagonal 만 있지?" 가 되고, 남기면 "덮인다" 가 보인다.
    """
    old = list(state)
    new = list(state)
    for q in _COL_QUADS:                      # 계산되지만 아래에서 전부 덮인다
        new[q[0]], new[q[1]], new[q[2]], new[q[3]] = _qr_pure(old, *q)
    for q in _DIAG_QUADS:
        new[q[0]], new[q[1]], new[q[2]], new[q[3]] = _qr_pure(old, *q)
    return new


def hiu_subkey(chacha_key, chacha_nonce, rounds=CHACHA_ROUNDS):
    """HIU 의 HChaCha20 단계 — **초기상태는 표준과 일치하고 라운드는 다르다.**

    `CHACHA_H_INIT` 이 놓는 상태는 상수 + key 8워드 + nonce 앞 16바이트
    4워드로 표준 HChaCha20 초기상태와 같다. 그러나 뒤따르는
    `CHACHA_H_MASK` 가 편차 B 를 갖는다.
    """
    work = (list(CHACHA_CONST) + _words_le(_key_bytes(chacha_key))
            + _words_le(_nonce_bytes(chacha_nonce)[:16]))
    for _ in range(rounds // 2):
        work = hiu_round_cycle(work)
    sel = [work[0], work[1], work[2], work[3],
           work[12], work[13], work[14], work[15]]
    return b"".join(w.to_bytes(4, "little") for w in sel)


def hiu_keystream_words01(chacha_key, chacha_nonce, rounds=CHACHA_ROUNDS):
    """HIU 의 ChaCha20 단계가 만드는 키스트림 워드 0, 1.

    **RTL 배치 재현 (정직 명기 1):**
        state[12] = 0                      (counter, RTL 과 동일)
        state[13] = nonce 바이트 16..19    (표준은 0)
        state[14] = nonce 바이트 20..23    (표준은 16..19)
        state[15] = 0                      (표준은 20..23)
    """
    subkey = hiu_subkey(chacha_key, chacha_nonce, rounds)
    nb = _nonce_bytes(chacha_nonce)
    init = (list(CHACHA_CONST) + _words_le(subkey)
            + [0,
               int.from_bytes(nb[16:20], "little"),
               int.from_bytes(nb[20:24], "little"),
               0])
    work = list(init)
    for _ in range(rounds // 2):
        work = hiu_round_cycle(work)   # 편차 B
    return ((work[0] + init[0]) & MASK32, (work[1] + init[1]) & MASK32)


def hiu_mask64(chacha_key, chacha_nonce, rounds=CHACHA_ROUNDS):
    """`CHACHA_FINAL` 이 만드는 64-bit 마스크.

    RTL:  `{chacha_state[1] + initial_state[1],
             chacha_state[0] + initial_state[0]}`
    → 상위 32비트가 워드 1, 하위 32비트가 워드 0.
    """
    w0, w1 = hiu_keystream_words01(chacha_key, chacha_nonce, rounds)
    return ((w1 << 32) | w0) & 0xFFFFFFFFFFFFFFFF


def hiu_masked_phys(phys_addr, chacha_key, chacha_nonce,
                    rounds=CHACHA_ROUNDS):
    """`masked_phys_addr` 의 정확값."""
    return (int(phys_addr) ^ hiu_mask64(chacha_key, chacha_nonce, rounds)) \
        & 0xFFFFFFFFFFFFFFFF


def standard_xchacha20_mask64(chacha_key, chacha_nonce,
                              rounds=CHACHA_ROUNDS):
    """같은 키/nonce 에 대한 **표준** XChaCha20 의 워드 0/1 마스크.

    RTL 이 만드는 값이 아니다 — 편차 A/B (정직 명기 1) 의 크기를 눈으로
    확인할 수 있게 나란히 둔다. 편차가 정정되면 `hiu_mask64` 와 이 값이
    같아지고, self-test 가 그것을 먼저 잡는다.
    """
    subkey = hchacha20(_key_bytes(chacha_key),
                       _nonce_bytes(chacha_nonce)[:16], rounds)
    nb = _nonce_bytes(chacha_nonce)
    blk = chacha20_block(subkey, 0, b"\x00\x00\x00\x00" + nb[16:24], rounds)
    w0 = int.from_bytes(blk[0:4], "little")
    w1 = int.from_bytes(blk[4:8], "little")
    return ((w1 << 32) | w0) & 0xFFFFFFFFFFFFFFFF


# ---------------------------------------------------------------------------
# 고정 벡터 — `test_hiu.py` 가 쓰는 값 (재실행 byte-identical)
# ---------------------------------------------------------------------------

FIXED_KEY = 0xDEADBEEFCAFEBABE0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF
FIXED_NONCE = 0xAABBCCDDEEFF00112233445566778899AABBCCDDEEFF0011


# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

def _test_quarter_round():
    """RFC 8439 §2.1.1."""
    s = [0x11111111, 0x01020304, 0x9B8D6F43, 0x01234567]
    quarter_round(s, 0, 1, 2, 3)
    assert s == [0xEA2A92F4, 0xCB1CF8CE, 0x4581472E, 0x5881C4BB], s


def _test_chacha20_block():
    """RFC 8439 §2.3.2 테스트 벡터."""
    key = bytes(range(32))
    nonce = bytes.fromhex("000000090000004a00000000")
    blk = chacha20_block(key, 1, nonce)
    expect = bytes.fromhex(
        "10f1e7e4d13b5915500fdd1fa32071c4"
        "c7d1f4c733c068030422aa9ac3d46c4e"
        "d2826446079faa0914c2d705d98b02a2"
        "b5129cd1de164eb9cbd083e8a2503c4e")
    assert blk == expect, blk.hex()


def _test_hchacha20():
    """draft-irtf-cfrg-xchacha §2.2.1 테스트 벡터."""
    key = bytes.fromhex(
        "000102030405060708090a0b0c0d0e0f"
        "101112131415161718191a1b1c1d1e1f")
    nonce16 = bytes.fromhex("000000090000004a0000000031415927")
    sub = hchacha20(key, nonce16)
    expect = bytes.fromhex(
        "82413b4227b27bfed30e42508a877d73"
        "a0f9e4d58a74a853c12ec41326d3ecdc")
    assert sub == expect, sub.hex()


def _test_determinism():
    a = hiu_masked_phys(0x0000000020001100, FIXED_KEY, FIXED_NONCE)
    b = hiu_masked_phys(0x0000000020001100, FIXED_KEY, FIXED_NONCE)
    assert a == b


def _test_deviation_is_real():
    """정직 명기 1 의 discriminator.

    RTL 경로와 표준 경로가 **실제로 다른 값을 낸다**는 것을 assert 한다.
    같아지면 (= 편차가 정정되면) 이 self-test 가 먼저 깨진다 — 그때는
    두 플래그를 내리고 `hiu_*` 를 표준 경로로 옮기는 것이 정확한 후속
    조치다. 조용히 넘어갈 경로가 없다.
    """
    assert HIU_NONCE_LAYOUT_DEVIATION and HIU_ROUND_STRUCTURE_DEVIATION
    a = hiu_mask64(FIXED_KEY, FIXED_NONCE)
    b = standard_xchacha20_mask64(FIXED_KEY, FIXED_NONCE)
    assert a != b, "편차가 사라졌다 — 위 docstring 의 후속 조치 참조"


def _test_round_structure_deviation_shape():
    """편차 B 의 성질을 구조로 확인한다 — 서술이 참인지 기계로 본다.

    (i) diagonal 4쌍의 인덱스 합집합이 정확히 0..15 라서 column 결과가
        하나도 살아남지 못한다,
    (ii) 그러므로 `hiu_round_cycle` 은 "diagonal 만 적용" 과 같다.
    """
    union = set()
    for q in _DIAG_QUADS:
        union |= set(q)
    assert union == set(range(16)), \
        "diagonal 합집합이 0..15 가 아니다 — 편차 B 의 서술을 재유도하라"

    st = [(i * 0x9E3779B1) & MASK32 for i in range(16)]
    diag_only = list(st)
    for q in _DIAG_QUADS:
        (diag_only[q[0]], diag_only[q[1]],
         diag_only[q[2]], diag_only[q[3]]) = _qr_pure(st, *q)
    assert hiu_round_cycle(st) == diag_only, \
        "column round 가 살아남았다 — 편차 B 의 서술이 틀렸다"

    # 그리고 그것은 표준 double round 와 다르다 (tautology 방지).
    std = list(st)
    double_round(std)
    assert hiu_round_cycle(st) != std


def _test_xor_involution():
    m = hiu_mask64(FIXED_KEY, FIXED_NONCE)
    for pa in (0, 1, 0x20000000, 0xFFFFFFFFFFFFFFFF):
        assert hiu_masked_phys(pa, FIXED_KEY, FIXED_NONCE) == (pa ^ m)


def main():
    _test_quarter_round()
    _test_chacha20_block()
    _test_hchacha20()
    _test_determinism()
    _test_deviation_is_real()
    _test_round_structure_deviation_shape()
    _test_xor_involution()

    m = hiu_mask64(FIXED_KEY, FIXED_NONCE)
    std = standard_xchacha20_mask64(FIXED_KEY, FIXED_NONCE)
    print("golden_xchacha self-test: PASS")
    print(f"  FIXED_KEY        = 0x{FIXED_KEY:064x}")
    print(f"  FIXED_NONCE      = 0x{FIXED_NONCE:048x}")
    print(f"  hiu_mask64       = 0x{m:016x}   (RTL 배치 — HIU.v 재현)")
    print(f"  standard mask64  = 0x{std:016x}   (표준 XChaCha20 배치)")
    print(f"  subkey (RTL)     = {hiu_subkey(FIXED_KEY, FIXED_NONCE).hex()}")
    print("  NOTE 두 값이 다른 것은 편차 2건 때문이다 — A: nonce 워드가 한 칸")
    print("       밀려 있다, B: column round 가 diagonal 에 덮여 사라진다.")
    print("       둘 다 spec §29.8 의 normative 수리 범위 **밖**이므로 이번")
    print("       세션은 RTL 을 고치지 않고 모델링·명명한다 (§12a 규칙 3).")
    print("       판정은 spec 소유자 몫이다 — docstring 정직 명기 1 참조.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
