#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""CRC-32C 워드-스텝 행렬 상수 유도기 — 유도 출처는 RFC 3720 명세뿐이다.

## 무엇을 만드는가

DecodeWalk_props.sv 의 CH(둘째 헤더, §1.3.4) 참조 모델이 쓰는 워드 단계
모듈 `wt_crc32c_word_ref` 의 본문(32개 assign, 순수 XOR 트리)을 생성한다.
워드 하나(32비트)를 CRC-32C 상태에 흡수하는 변환은 GF(2) 위에서 선형이다:

    S' = A·S ⊕ B·W        (A, B ∈ GF(2)^{32×32}, 상수항 없음)

A·B 는 RFC 3720 의 반사형 비트-직렬 정의

    fb = s[0] ^ m ;  s' = (s >> 1) ^ (fb ? 0x82F63B78 : 0)

를 워드당 32 비트-스텝 기호 합성(GF(2))해서 얻는다. 반사 관례 + 워드당
리틀엔디언 바이트 직렬화이므로 워드 안 처리 순서는 정확히 비트 0→31 이고,
그것이 위 스텝을 워드 비트 k = 0..31 로 도는 근거다 (props.sv 의 CH 절
주석과 같은 문장).

## 독립성 (clean-room 규율)

이 스크립트는 RTL(rtl/spinal/**, rtl/generated/**)을 읽지 않는다 — 유도
입력은 위 비트-직렬 정의(RFC 3720 관례: 다항식 0x1EDC6F41 정규형 /
0x82F63B78 반사형, 입·출력 반사, init/xorout 0xFFFFFFFF)가 전부다.
RTL 쪽 상수는 SpinalHDL elaborate 가 스칼라 코드에서 평탄화한 것이므로,
같은 명세에서 유도 파이프라인이 다른 두 번째 구현이 된다.

## 자기시험 (실행할 때마다 전부 다시 잰다 — 실패 시 비상 종료)

  (i)  무작위 (S, W) 10^4 건에서 행렬형 == 비트-직렬형 (워드 스텝 등가)
  (ii) RFC 3720 기지값 3종 — 바이트 비트-직렬 전체 CRC 로:
         "123456789"            → 0xE3069283
         32 바이트 × 0x00       → 0x8A9136AA
         32 바이트 × 0xFF       → 0x62A8AB43
  (iii) 워드 배수 길이 메시지(기지값 32B 2종 + 무작위 100건)에서
        「LE 워드 패킹 → 행렬 폴드」 == 「바이트 비트-직렬」 —
        워드 절단면 도입이 직렬화 정의를 바꾸지 않았다는 교차 검사.

## 사용

    python3 rtl/sv/assert/gen_crc32c_matrix.py            # 자기시험 + 모듈 출력
    python3 rtl/sv/assert/gen_crc32c_matrix.py --selftest # 자기시험만

출력(표준출력)의 모듈 텍스트를 DecodeWalk_props.sv 말미의
`wt_crc32c_word_ref` 와 대조/갱신한다. 생성물은 저 파일 안에 살고, 이
스크립트는 재유도·재검이 필요할 때의 출처 기록이다.
"""

import argparse
import random
import sys

POLY_REFL = 0x82F63B78  # CRC-32C (Castagnoli) 반사형 — 정규형 0x1EDC6F41
MASK32 = 0xFFFFFFFF


# ── RFC 3720 비트-직렬 정의 (유도의 유일한 원천) ────────────────────────────

def bitserial_word(s: int, w: int) -> int:
    """워드 32비트를 비트 0→31 로 흡수 (반사 관례 + LE 직렬화의 귀결)."""
    for k in range(32):
        fb = (s ^ (w >> k)) & 1
        s = (s >> 1) ^ (POLY_REFL if fb else 0)
    return s


def crc32c_bytes(msg: bytes) -> int:
    """바이트 메시지 전체 CRC — init/xorout 0xFFFFFFFF, 바이트당 비트 0→7."""
    s = MASK32
    for byte in msg:
        for k in range(8):
            fb = (s ^ (byte >> k)) & 1
            s = (s >> 1) ^ (POLY_REFL if fb else 0)
    return s ^ MASK32


# ── GF(2) 기호 합성 — S' = A·S ⊕ B·W 의 A·B 유도 ────────────────────────────

def derive_matrices():
    """상태 비트를 64변수(s[0..31], w[0..31]) 계수 마스크로 두고 32 스텝 합성.

    반환: (A, B) — A[j]/B[j] 는 sn[j] 가 XOR 하는 s/w 비트들의 마스크.
    """
    # state[j] = 비트 j 의 계수 마스크. 변수 i<32 ↔ s[i], i>=32 ↔ w[i-32].
    state = [1 << i for i in range(32)]
    for k in range(32):
        fb = state[0] ^ (1 << (32 + k))          # fb = s[0] ^ w[k] 의 기호형
        nxt = []
        for j in range(32):
            c = state[j + 1] if j < 31 else 0    # (s >> 1) 의 비트 j
            if (POLY_REFL >> j) & 1:
                c ^= fb                          # ^ (fb ? POLY : 0) 의 비트 j
            nxt.append(c)
        state = nxt
    A = [row & MASK32 for row in state]
    B = [row >> 32 for row in state]
    return A, B


def matrix_word(s: int, w: int, A, B) -> int:
    """행렬형 워드 스텝 — sn[j] = parity(A[j]&s) ^ parity(B[j]&w)."""
    out = 0
    for j in range(32):
        p = (bin(A[j] & s).count("1") + bin(B[j] & w).count("1")) & 1
        out |= p << j
    return out


def matrix_fold_words(words, A, B) -> int:
    """워드열 전체 CRC — init/xorout 0xFFFFFFFF, 워드 오름차순."""
    s = MASK32
    for w in words:
        s = matrix_word(s, w, A, B)
    return s ^ MASK32


def pack_le_words(msg: bytes):
    assert len(msg) % 4 == 0
    return [int.from_bytes(msg[i:i + 4], "little") for i in range(0, len(msg), 4)]


# ── 자기시험 ────────────────────────────────────────────────────────────────

KNOWN = [
    (b"123456789", 0xE3069283),
    (b"\x00" * 32, 0x8A9136AA),
    (b"\xff" * 32, 0x62A8AB43),
]


def selftest(A, B, rng: random.Random, n_random: int = 10_000) -> None:
    # (ii) 기지값 — 비트-직렬 바이트 정의가 RFC 3720 그 자체인지.
    for msg, want in KNOWN:
        got = crc32c_bytes(msg)
        if got != want:
            sys.exit(f"selftest FAIL (known): {msg!r} → {got:#010x} != {want:#010x}")

    # (i) 무작위 워드 스텝 — 행렬형 == 비트-직렬형.
    for _ in range(n_random):
        s = rng.getrandbits(32)
        w = rng.getrandbits(32)
        bs = bitserial_word(s, w)
        mx = matrix_word(s, w, A, B)
        if bs != mx:
            sys.exit(f"selftest FAIL (step): s={s:#010x} w={w:#010x} "
                     f"bitserial={bs:#010x} matrix={mx:#010x}")

    # (iii) 워드 배수 메시지 — LE 워드 패킹 + 행렬 폴드 == 바이트 비트-직렬.
    msgs = [m for m, _ in KNOWN if len(m) % 4 == 0]
    msgs += [bytes(rng.getrandbits(8) for _ in range(4 * rng.randint(1, 14)))
             for _ in range(100)]
    for msg in msgs:
        want = crc32c_bytes(msg)
        got = matrix_fold_words(pack_le_words(msg), A, B)
        if got != want:
            sys.exit(f"selftest FAIL (fold): len={len(msg)} "
                     f"matrix={got:#010x} bytes={want:#010x}")


# ── Verilog 방출 — 순수 XOR 이항 트리 (함수·표·감산 없음) ───────────────────

def xor_tree(terms):
    if len(terms) == 1:
        return terms[0]
    mid = len(terms) // 2
    return f"({xor_tree(terms[:mid])} ^ {xor_tree(terms[mid:])})"


def wrap(expr: str, first: str, indent: str, width: int = 78):
    """공백 경계에서 탐욕 줄바꿈 — Verilog 식은 줄바꿈 위치에 무관하다."""
    out, line = [], first
    for tok in expr.split(" "):
        cand = f"{line} {tok}"
        if len(cand) > width and line != first:
            out.append(line)
            line = indent + tok
        else:
            line = cand
    out.append(line)
    return out


def emit_module(A, B):
    total = sum(bin(A[j] | (B[j] << 32)).count("1") for j in range(32))
    lines = [
        "// ── CRC-32C 워드 스텝 참조 — 스펙-유도 행렬 상수 (수리 기록 3) ────────────",
        "//",
        "// S' = A·S ⊕ B·W (GF(2), 상수항 없음). A·B 의 유도 출처는 RFC 3720 의",
        "// 반사형 비트-직렬 정의뿐이다 — 곁의 gen_crc32c_matrix.py 가 워드당",
        "// 32 비트-스텝을 기호 합성해 만들었고, 실행마다 (i) 무작위 (S,W) 10^4",
        "// 스텝 등가 (ii) RFC 3720 기지값 3종 (iii) LE 워드 폴드 == 바이트",
        "// 비트-직렬 교차 검사를 전부 다시 잰다. RTL 을 읽지 않는다 (clean-room).",
        f"// 아래 본문은 그 스크립트의 출력 그대로다 — XOR 항 총 {total}개,",
        "// 함수·표·감산 없음 (yosys 0.66 규율: 함수 미구동·$mem_v2 귀납 임의화).",
        "module wt_crc32c_word_ref (",
        "  input  wire [31:0] s,   // 워드 처리 전 상태",
        "  input  wire [31:0] w,   // 메시지 워드 (LE 직렬화 → 비트 0→31)",
        "  output wire [31:0] sn   // 워드 처리 후 상태",
        ");",
    ]
    for j in range(32):
        terms = [f"s[{i}]" for i in range(32) if (A[j] >> i) & 1]
        terms += [f"w[{i}]" for i in range(32) if (B[j] >> i) & 1]
        expr = xor_tree(terms)
        lines += wrap(f"{expr};", f"  assign sn[{j}] =", "    ")
    lines.append("endmodule")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--selftest", action="store_true", help="자기시험만")
    ap.add_argument("--seed", type=int, default=0x1EDC6F41,
                    help="무작위 자기시험 시드 (기본: 다항식 정규형)")
    args = ap.parse_args()

    A, B = derive_matrices()
    selftest(A, B, random.Random(args.seed))
    print("selftest OK — known 3/3 · random-step 10000/10000 · fold 102/102",
          file=sys.stderr)
    print(f"A rows popcount sum = {sum(bin(a).count('1') for a in A)}, "
          f"B rows popcount sum = {sum(bin(b).count('1') for b in B)}",
          file=sys.stderr)
    if not args.selftest:
        print(emit_module(A, B))


if __name__ == "__main__":
    main()
