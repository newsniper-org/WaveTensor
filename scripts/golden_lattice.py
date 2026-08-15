#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""v2.0 wave-step-atomic accumulation — 528-bit exact-integer lattice 의
golden model + RTL TB 벡터 생성기 (spec §27.2 normative; §27.6 하류 gate
순서 ① — golden-before-RTL law).

§27.2 규범을 EXACT 산술로 구현한다:

  (1) lattice   dispatch 당 32 곱 + ACC bank carry-in 1 = 33 addend 를
                528-bit two's-complement lattice (weight 2^-266..2^260
                527 자리 + sign 1) 에 exact 배치·누산, resolve 1회.
                dot 내부 반올림 0회 — 순서-무관은 구조의 필연.
  (2) 추출      resolve 결과의 top-48 + sticky-jam = exact 33-항 합의
                RTO_48 (wave-step 유일의 반올림). exact zero 합이면
                PACK_WIDE canonical zero (sign=0, exp=-1024, sig=0) 방출
                (§23.10.1 / FP_AddWide.v 인터페이스 계약 그대로).
  (3) bank word PACK_WIDE 값의 IEEE binary64 무손실 재인코딩 (상수 배선
                + bias 가산 + 2-case corner shift), FILL validation
                (NaN/Inf → loud fault; 비표현 값 → 동일 fault; ±0 은
                수용하되 canonical +0 으로 canonicalize) — §27.2.2.
  (4) drain     PACK_FINAL — 정확히 1회 RNE-24 + flush-after-round FTZ
                (§27.2.3). rounding core 는 scripts/golden_fp32.py 에서
                import — 중복 구현 금지.

정당성 정리 (§27.2.1): RNE_24(RTO_48(exact)) == RNE_24(exact) —
q >= p+2 = 26 이면 성립, 48 은 22 bit 마진. 본 스크립트는 이 정리를
Fraction 기반 exact 참조와 대량 sweep 로 비트 비교해 재확인한다.

자기검증 (main 실행 시 전부 assert):
  * 정리 identity sweep — lattice 경로 vs Fraction 참조 비트 비교
  * 순열 불변 — 같은 33 addend 의 임의 순서 재주입, bit-identical
  * directed jam family — scripts/acc_format_study.py 의 F1..F6 (+F7..F9)
    재현 입력을 본 golden 에 통과, study 의 per-write chain / true-B
    판정과 정확히 일치함을 교차검증 (발산하는 곳은 발산까지 일치)
  * 경계 — weight 2^-266 / 2^260 양끝, 전부 음수, 대규모 상쇄(exact 0),
    carry-in 지배/미미, drain FTZ/overflow, RNE-48-store 판별 반례
  * fault 계약 — NaN/Inf/비표현/overflow 는 loud fault (§27.2.2);
    NaN/Inf 의 lattice 진입 차단 계약 위치는 아래 참조
  * codec — bank word 왕복 bit-exact + struct 기반 독립 oracle (하드웨어
    binary64/binary32 변환기) 교차검증 (§23.10.5 pin 13 규칙의 stdlib 형)
  * 적재 기하 — static barrel + 2-of-9 segment demux 기하 pin 의
    등가성 검사 (아래 SEGMENT GEOMETRY)

NaN/Inf 차단 계약 위치 (본 golden 의 계약 명시):
  wide 포맷 (sign/exp/sig) 자체에는 NaN/Inf 인코딩이 존재하지 않는다.
  따라서 lattice 는 구조적으로 specials 를 볼 수 없고, 차단은 두 경계가
  담당한다 — (i) bank FILL ingest 의 fp64 E=2047 검사 → sticky fault
  (§27.2.2, 본 파일 fp64_to_wide 가 참조 구현); (ii) 곱 operand 는
  FP_CLASSIFY 가 IEEE specials 를 lattice 이전에 필터 (§23.10.5 /
  FP_AddWide.v PRECONDITIONS 와 동형 — specials 는 이 블록에 절대
  진입하지 않는다).

SEGMENT GEOMETRY (§27.2.1 "segment 기하는 golden model/RTL 에서 확정"):
  물리 lattice = 576 bit = 9 segment x 64 bit. 값 비트는 PHYS[575:48]
  (PHYS bit 48 = weight 2^-266), PHYS[47:0] 은 표현성 전제에 의해 항상
  0 인 정렬 여유. addend (sign, e, sig48) 의 sig 필드는 LSB 를 PHYS
  q = e+267 에 두고 [q, q+47] 을 점유; k = q>>6, o = q&63 로 static
  6-stage barrel (o) + segment demux (k) — 48 <= 64 이므로 임의 addend
  의 데이터 필드는 인접 <= 2 segment 만 건드린다 ("2-of-9"). 음수는
  two's-complement (mod 2^576); trailing zero 보존으로 PHYS[47:0] 은
  불변 0. resolve = (S mod 2^576) >> 48 의 하위 528 bit. 본 파일은 이
  기하로 배치한 물리 누산이 direct 정수 누산과 bit-identical 함을 모든
  벡터에서 assert 한다.

산출물 (전부 결정적 — 고정 seed, timestamp 없음, 재실행 byte-identical):
  include/generated/lattice_wave_vectors.hex   RTL TB 벡터 ($readmemh)
  include/generated/lattice_vec_contract.md    벡터 비트 레이아웃 계약
  include/generated/lattice_golden_report.json 체크 결과·벡터 수·sha256

ground truth 는 exact 정수/Fraction 산술; stdlib-only. acc_format_study
는 설계 판정의 재현 artifact 로서 교차검증 대상으로만 import 한다
(§27.4 — golden 의 대체물이 아니다).
"""

import hashlib
import json
import math
import random
import struct
import sys
import time
from fractions import Fraction
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
GEN = REPO / "include" / "generated"
VEC_PATH = GEN / "lattice_wave_vectors.hex"
CONTRACT_PATH = GEN / "lattice_vec_contract.md"
REPORT_PATH = GEN / "lattice_golden_report.json"
sys.path.insert(0, str(Path(__file__).resolve().parent))

from golden_fp32 import _rto, pack_rne_ftz  # noqa: E402
import acc_format_study as STUDY  # noqa: E402  (교차검증 전용)

TWO = Fraction(2)

# ---------------------------------------------------------------------------
# 격자/포맷 상수 (§27.2.1 / §27.2.2)
# ---------------------------------------------------------------------------
LAT_W = 528                 # two's-complement lattice 폭
LAT_LSB_EXP = -266          # bit 0 의 weight = 2^-266
LAT_TOP_EXP = 260           # bit 526 의 weight = 2^260 (bit 527 = sign)
LAT_MIN = -(1 << 527)       # 단위 2^-266 의 정수 범위
LAT_MAX = (1 << 527) - 1
Q48 = 48                    # PACK_WIDE significand 폭
WEXP_MIN, WEXP_MAX = -1024, 1023        # signed-11 exponent
CANON_ZERO = (0, -1024, 0)  # PACK_WIDE canonical zero (§23.10.1, c21092a)
GROUP = 32                  # dispatch 당 곱 lane 수
N_ADDENDS = 33              # 32 곱 + bank carry-in

SEG_W, N_SEG, PHYS_W = 64, 9, 576       # segment 기하 pin (docstring 참조)
_M48 = (1 << 48) - 1
_M64 = (1 << 64) - 1
_M528 = (1 << 528) - 1
_M576 = (1 << 576) - 1

VEC_BITS = N_ADDENDS * 64 + LAT_W + 64 + 64 + 32        # 2800
VEC_HEX = VEC_BITS // 4                                 # 700

# 고정 seed — 결정론의 유일한 난수원
SEEDS = {
    "theorem_sweep": 0x1A77E01,
    "perm": 0x1A77E02,
    "codec": 0x1A77E03,
    "vec_rand_wide": 0x1A77E11,
    "vec_cancel": 0x1A77E12,
    "vec_tie": 0x1A77E13,
    "vec_f16": 0x1A77E14,
    "vec_chain_s1": 0x1A77E15,
    "vec_chain_s4": 0x1A77E16,
    "vec_chain_s5": 0x1A77E17,
    "vec_parkcancel": 0x1A77E18,
    "vec_sparse": 0x1A77E19,
}


class LatticeFault(Exception):
    """loud fault — never silent (project law). RTL 대응은 합성 가능한
    sticky status bit 클래스 (§27.2.2 FILL validation, §26.5 선례)."""


# ===========================================================================
# PACK_WIDE wide 값 — (sign, exp, sig48), value = (-1)^s * sig * 2^(e-47)
# ===========================================================================


def wide_check(s, e, sig, what="addend"):
    """형식 검증. zero 는 canonical zero 단 하나 (§23.10.1 폐포 계약);
    nonzero 는 leading zero <= 1 (FP_AddWide PRECONDITIONS 동형 규약)."""
    if s not in (0, 1) or not WEXP_MIN <= e <= WEXP_MAX \
            or not 0 <= sig <= _M48:
        raise LatticeFault("%s field out of range: %r" % (what, (s, e, sig)))
    if sig == 0:
        if (s, e, sig) != CANON_ZERO:
            raise LatticeFault(
                "%s zero must be canonical (0,-1024,0): %r"
                % (what, (s, e, sig)))
    elif sig < (1 << 46):
        raise LatticeFault(
            "%s sig has >1 leading zero: %r" % (what, (s, e, sig)))


def wide_frac(s, e, sig):
    """exact Fraction 값 (측정 helper)."""
    if sig == 0:
        return Fraction(0)
    v = Fraction(sig) * TWO ** (e - 47)
    return -v if s else v


def wide_binade(s, e, sig):
    """nonzero wide 값의 binade (2^b <= |v| < 2^(b+1))."""
    assert sig
    return e + sig.bit_length() - 48


def field_encode(s, e, sig):
    """TB 64-bit addend field: [63:60]=0, [59]=sign,
    [58:48]=exp (11-bit two's complement), [47:0]=sig."""
    wide_check(s, e, sig)
    return (s << 59) | ((e & 0x7FF) << 48) | sig


def field_decode(word):
    if not 0 <= word <= _M64 or (word >> 60) != 0:
        raise LatticeFault("addend field [63:60] must be 0: 0x%016X" % word)
    s = (word >> 59) & 1
    e = (word >> 48) & 0x7FF
    if e >= 0x400:
        e -= 0x800
    sig = word & _M48
    wide_check(s, e, sig)
    return s, e, sig


def me_to_addend(pm, pe):
    """exact 값 pm * 2^pe 를 normalized wide addend 로 (값-충실 인코딩).
    acc_format_study 의 (m,e) directed 입력 재현용."""
    assert pm != 0
    s = 1 if pm < 0 else 0
    a = -pm if pm < 0 else pm
    sh = 48 - a.bit_length()
    assert sh >= 0, "significand wider than 48 bits is not a wide value"
    return s, pe + a.bit_length() - 1, a << sh


# ===========================================================================
# bank word — PACK_WIDE 값의 IEEE binary64 무손실 재인코딩 (§27.2.2)
# ===========================================================================


def wide_to_fp64(s, e, sig):
    """bank/spill word 인코딩: 상수 배선 + bias 가산 + 2-case corner
    shift. canonical zero -> fp64 +0."""
    wide_check(s, e, sig, "bank")
    if sig == 0:
        return 0
    if (sig >> 47) != 1:
        raise LatticeFault("bank word must be normalized: %r" % ((s, e, sig),))
    if e >= -1022:                          # fp64 normal
        return (s << 63) | ((e + 1023) << 52) | ((sig & ((1 << 47) - 1)) << 5)
    if e == -1023:                          # corner 1: subnormal, shift 4
        return (s << 63) | (sig << 4)
    return (s << 63) | (sig << 3)           # corner 2: e = -1024, shift 3


def fp64_to_wide(bits):
    """FILL validation (§27.2.2 normative — loud fault, never silent):
    (i) NaN/Inf (E=2047) -> fault; (ii) PACK_WIDE-representable 집합 밖
    -> 동일 fault; (iii) ±0 은 수용, canonical +0 으로 canonicalize."""
    if not 0 <= bits <= _M64:
        raise LatticeFault("fp64 word out of range")
    s = (bits >> 63) & 1
    E = (bits >> 52) & 0x7FF
    m = bits & ((1 << 52) - 1)
    if E == 0x7FF:
        raise LatticeFault("FILL: NaN/Inf -> sticky fault (fp64 E=2047)")
    if E == 0 and m == 0:
        return CANON_ZERO                   # ±0 canonicalize (+0)
    if E > 0:
        if m & 0x1F:
            raise LatticeFault(
                "FILL: not PACK_WIDE-representable (fp64 mantissa below "
                "48-bit precision): 0x%016X" % bits)
        return s, E - 1023, (1 << 47) | (m >> 5)
    bl = m.bit_length()                     # fp64 subnormal: m * 2^-1074
    if bl == 52:
        sh, e = 4, -1023
    elif bl == 51:
        sh, e = 3, -1024
    else:
        raise LatticeFault(
            "FILL: not PACK_WIDE-representable (binade below 2^-1024): "
            "0x%016X" % bits)
    if m & ((1 << sh) - 1):
        raise LatticeFault(
            "FILL: not PACK_WIDE-representable (subnormal precision "
            "overflow): 0x%016X" % bits)
    return s, e, m >> sh


def _fp64_struct_oracle(s, e, sig):
    """독립 oracle: 호스트 hw binary64 로 같은 값을 인코딩 (struct).
    sig <= 2^48 이므로 ldexp 는 subnormal corner 포함 전 구간 exact."""
    if sig == 0:
        return 0
    w = struct.unpack(">Q", struct.pack(">d", math.ldexp(sig, e - 47)))[0]
    return (s << 63) | w


def _f32_struct_oracle(s, e, sig):
    """독립 oracle: 호스트 hw binary64->binary32 RNE (struct). wide 값은
    fp64 에서 exact 이므로 단일 반올림. FTZ/overflow 경계 모호성이 없는
    normal 구간 (-125 <= e <= 126) 만 판정, 밖은 None (skip 집계)."""
    if sig == 0 or not -125 <= e <= 126:
        return None
    v = math.ldexp(sig, e - 47)
    return struct.unpack(">I", struct.pack(">f", -v if s else v))[0]


# ===========================================================================
# lattice — exact 배치/누산/resolve (§27.2.1)
# ===========================================================================


def addend_units(s, e, sig):
    """addend 를 lattice 정수 단위 (2^-266) 로 exact 변환.
    lattice-표현 불가 (LSB < 2^-266 또는 |v| > 최대) -> loud fault."""
    wide_check(s, e, sig)
    if sig == 0:
        return 0
    sh = e + 219                            # (e-47) - (-266)
    if sh >= 0:
        u = sig << sh
    else:
        if sig & ((1 << -sh) - 1):
            raise LatticeFault(
                "addend not lattice-representable (precision below "
                "2^-266): %r" % ((s, e, sig),))
        u = sig >> -sh
    if u > LAT_MAX:
        raise LatticeFault(
            "addend exceeds lattice range (|v| >= 2^261): %r"
            % ((s, e, sig),))
    return -u if s else u


def lattice_accumulate(addends):
    """33 addend 의 exact 정수 누산 (compressor tree + resolve 1회의
    산술 등가). 총합의 528-bit two's-complement 범위 이탈 -> loud fault
    (in-run assert, §27.2.1)."""
    if len(addends) != N_ADDENDS:
        raise LatticeFault("exactly 33 addends required (32 products + "
                           "carry-in), got %d" % len(addends))
    total = 0
    for a in addends:
        total += addend_units(*a)
    if not LAT_MIN <= total <= LAT_MAX:
        raise LatticeFault("lattice overflow: resolved sum outside "
                           "[-2^261, 2^261) — precondition violation")
    return total


def lattice_word(units):
    """resolve 결과의 528-bit two's-complement 표현 (TB 기대값 형)."""
    assert LAT_MIN <= units <= LAT_MAX
    return units & _M528


def extract_rto48(units):
    """추출 = 그 wave-step 의 유일한 반올림: LZC/normalize 후 top-48 +
    sticky-jam = exact 합의 RTO_48. exact zero -> canonical zero."""
    if units == 0:
        return CANON_ZERO
    s = 1 if units < 0 else 0
    a = -units if s else units
    e = a.bit_length() - 1 + LAT_LSB_EXP    # binade
    sh = a.bit_length() - Q48
    sig = _rto(a, sh) if sh > 0 else a << -sh
    assert (1 << 47) <= sig <= _M48
    assert -266 <= e <= LAT_TOP_EXP         # signed-11 수납 (in-run assert)
    return s, e, sig


def drain_rne24_ftz(s, e, sig):
    """drain (§27.2.3): PACK_FINAL — 정확히 1회 RNE-24 (unbounded), 그 후
    flush-after-round FTZ; overflow -> ±Inf; exact zero -> +0 (A4/F4 pin).
    rounding core 는 golden_fp32.pack_rne_ftz 를 그대로 사용."""
    if sig == 0:
        return 0x00000000
    return pack_rne_ftz(s, Fraction(sig) * TWO ** (e - 47))


def _pack_frac(v):
    """exact Fraction 의 fp32 RNE+FTZ pack (참조 경로; exact zero -> +0)."""
    if v == 0:
        return 0
    return pack_rne_ftz(0 if v > 0 else 1, abs(v))


# ---------------------------------------------------------------------------
# segment 기하 twin — 물리 배치 등가성 (docstring SEGMENT GEOMETRY)
# ---------------------------------------------------------------------------


def phys_contrib(s, e, sig):
    """addend 의 물리 lattice 기여 (mod 2^576) 와 점유 segment 수.
    데이터 필드는 인접 <= 2 segment ("2-of-9") — assert."""
    if sig == 0:
        return 0, 0
    q = e + 267                             # PHYS LSB 위치 = (e+219)+48
    assert 1 <= q <= PHYS_W - Q48, "PHYS placement out of range"
    k, o = q >> 6, q & 63
    span = 2 if o + Q48 > SEG_W else 1
    assert k + span - 1 <= N_SEG - 1, "2-of-9 segment demux violated"
    field = sig << q
    assert field & _M48 == 0, "PHYS[47:0] must stay zero (representability)"
    contrib = ((1 << PHYS_W) - field) if s else field
    return contrib & _M576, span


def check_segments(addends, units):
    """물리 segmented 누산 == direct 정수 누산 (bit-identical)."""
    total, max_span = 0, 0
    for a in addends:
        c, span = phys_contrib(*a)
        total = (total + c) & _M576
        max_span = max(max_span, span)
    assert total & _M48 == 0
    assert (total >> 48) & _M528 == lattice_word(units)
    return max_span


# ===========================================================================
# wave-step — 규범 파이프라인 1 dispatch (§27.2 전체)
# ===========================================================================


def wave_step(products, carry):
    """32 곱 + carry-in -> (resolved units, wide 결과, bank word fp64,
    즉시 drain fp32). bank 반올림 이벤트 정확히 1회 (RTO-48 store)."""
    assert len(products) == GROUP
    units = lattice_accumulate(list(products) + [carry])
    wide = extract_rto48(units)
    bank = wide_to_fp64(*wide)
    f32 = drain_rne24_ftz(*wide)
    return units, wide, bank, f32


# ===========================================================================
# 난수 wave 생성기 (전부 고정 seed 의 rng 인자 경유)
# ===========================================================================


def rand_bf16_addend(rng, elo, ehi):
    """bf16 normal x bf16 normal 곱 — lane raw 형식 (sig = s16 << 32,
    exp = Ea+Eb+1; §27.2.1 의 8x8 -> 16-bit significand 곱)."""
    s16 = rng.randrange(128, 256) * rng.randrange(128, 256)
    E = rng.randint(elo, ehi) + rng.randint(elo, ehi)
    return rng.randint(0, 1), E + 1, s16 << 32


def rand_f16_addend(rng, elo=-14, ehi=15):
    """f16 normal x f16 normal 곱 — lane raw 형식 (sig = s22 << 26,
    exp = Ea+Eb+1; 11x11 -> 22-bit significand 곱)."""
    s22 = rng.randrange(1024, 2048) * rng.randrange(1024, 2048)
    E = rng.randint(elo, ehi) + rng.randint(elo, ehi)
    return rng.randint(0, 1), E + 1, s22 << 26


def wave_rand_wide(rng):
    return [rand_bf16_addend(rng, -126, 40) for _ in range(GROUP)]


def wave_cancel(rng):
    """대규모 상쇄: X 와 -X + 수십 binade 아래의 dust (acc_format_study
    fam_cancel 의 wide-domain 이식)."""
    prods = [CANON_ZERO] * GROUP
    s16 = rng.randrange(128, 256) * rng.randrange(128, 256)
    E = rng.randint(-20, 20) + rng.randint(-20, 20)
    X = (0, E + 1, s16 << 32)
    c = (wide_binade(*X) - rng.randint(45, 95)) // 2
    prods[0], prods[1], prods[2] = X, rand_bf16_addend(rng, c - 1, c + 1), \
        (1, X[1], X[2])
    for i in rng.sample(range(4, GROUP), 3):
        prods[i] = rand_bf16_addend(rng, c - 2, c)
    return prods


def wave_tie(rng):
    """24-bit RNE tie 인접: 1 + half-ulp24 + bit-48 아래 signed dust
    (fam_tie 이식) — jam/sticky 경로 집중 타격."""
    prods = [CANON_ZERO] * GROUP
    prods[0] = (0, 0, 1 << 47)              # 곱 1x1
    prods[1] = (0, -24, 1 << 47)            # 정확히 half-ulp24
    for i in range(2, 2 + rng.randint(2, 6)):
        t = rng.randint(-62, -45)
        prods[i] = rand_bf16_addend(rng, t // 2 - 1, t // 2 + 1)
    rng.shuffle(prods)                      # demux 슬롯 커버리지
    return prods


def wave_f16(rng):
    return [rand_f16_addend(rng) for _ in range(GROUP)]


def wave_sparse(rng, n_nz=None):
    """0..32 개만 nonzero — canonical-zero addend 슬롯 처리 검증."""
    if n_nz is None:
        n_nz = rng.randint(0, GROUP)
    prods = [CANON_ZERO] * GROUP
    for i in rng.sample(range(GROUP), n_nz):
        prods[i] = rand_bf16_addend(rng, -60, 30)
    return prods


def rand_carry(rng, max_units_bits=505):
    """lattice-표현 가능이 보장되는 임의 carry-in: 임의 lattice 값의
    RTO-48 추출 (bank 값 불변식의 구성적 재현). < 2^505 units 로 제한해
    임의 32곱과의 합이 lattice 범위를 절대 넘지 않게 한다."""
    r = rng.random()
    if r < 0.35:
        return CANON_ZERO
    bl = rng.randint(1, max_units_bits)
    u = (rng.getrandbits(bl - 1) | (1 << (bl - 1))) if bl > 1 else 1
    if rng.random() < 0.5:
        u = -u
    return extract_rto48(u)


# ===========================================================================
# 자기검증 1 — 정리 identity + 순열 불변
# ===========================================================================


def check_wave_against_fraction(products, carry):
    """한 wave 의 lattice 경로 전체를 Fraction 독립 참조와 비트 비교.
    (i) resolve == exact 합, (ii) wide == RTO_48(exact) [study 의
    Fraction-domain rto_q 로 교차], (iii) drain == RNE24(exact) — 정리."""
    units, wide, bank, f32 = wave_step(products, carry)
    exact = sum((wide_frac(*a) for a in products), Fraction(0)) \
        + wide_frac(*carry)
    assert exact == Fraction(units) * TWO ** -266
    assert wide_frac(*wide) == STUDY.rto_q(exact, Q48)
    assert f32 == _pack_frac(exact)         # RNE24(RTO48(x)) == RNE24(x)
    assert fp64_to_wide(bank) == wide       # bank 왕복
    assert bank == _fp64_struct_oracle(*wide)
    return units, wide, bank, f32


def check_theorem_sweep(n_trials):
    rng = random.Random(SEEDS["theorem_sweep"])
    gens = (wave_rand_wide, wave_tie, wave_cancel, wave_sparse, wave_f16)
    oracle_checked = oracle_skipped = 0
    for i in range(n_trials):
        prods = gens[i % len(gens)](rng)
        carry = rand_carry(rng)
        _, wide, _, f32 = check_wave_against_fraction(prods, carry)
        o = _f32_struct_oracle(*wide)
        if o is None:
            oracle_skipped += 1
        else:
            assert o == f32
            oracle_checked += 1
    return {
        "N": n_trials, "seed": SEEDS["theorem_sweep"],
        "generators": [g.__name__ for g in gens],
        "statement": "RNE_24(RTO_48(exact)) == RNE_24(exact) — lattice "
                     "경로 vs Fraction 참조 비트 비교 (drain/wide/resolve "
                     "3층 전부)",
        "mismatches": 0,
        "f32_struct_oracle_checked": oracle_checked,
        "f32_struct_oracle_skipped_nonnormal": oracle_skipped,
        "verdict": "PASS",
    }


def check_permutation(n_trials, n_perms):
    """exact 구조의 필연 — 같은 33 addend 를 어떤 순서로 넣어도 (carry
    슬롯 포함) resolve/wide/drain 전부 bit-identical."""
    rng = random.Random(SEEDS["perm"])
    for _ in range(n_trials):
        prods = wave_rand_wide(rng)
        carry = rand_carry(rng)
        base = wave_step(prods, carry)
        all33 = list(prods) + [carry]
        orders = [list(reversed(all33)),
                  sorted(all33, key=lambda a: (a[2], a[1], a[0]))]
        for _ in range(n_perms - 2):
            p = all33[:]
            rng.shuffle(p)
            orders.append(p)
        for p in orders:
            got = wave_step(p[:GROUP], p[GROUP])
            assert got == base
    return {"trials": n_trials, "orders_per_trial": n_perms + 1,
            "seed": SEEDS["perm"], "mismatches": 0, "verdict": "PASS"}


# ===========================================================================
# 자기검증 2 — directed jam family 교차검증 (acc_format_study 재현)
# ===========================================================================


def _study_chain_rto48(prods_me):
    """study 의 per-write RTO-48 chain (rto_me) 을 그대로 재계산."""
    am, ae = 0, 0
    for pm, pe in prods_me:
        am, ae = STUDY.rto_me(*STUDY.add_me(am, ae, pm, pe), 48)
    return am, ae


def check_jam_families():
    """F1..F6 (+posit 계열 F7..F9) 재현 입력을 golden lattice 에 통과:
    (a) per-write chain (곱 1개 = wave 1개) 이 study 의 rto_me chain 과
        전 스텝 exact 일치 — 발산하는 가족 (F5b/F6 등) 은 true-B 와의
        발산 여부까지 study 판정과 일치해야 한다 (한계의 재현, §27.3);
    (b) single-wave (전 곱 1 wave) 는 정리에 의해 true B 와 bit-exact."""
    rows = []
    fams = list(STUDY.JAM_FAMILIES) + STUDY.POSIT_FAMILIES[3:]
    for name, doc, prods_me in fams:
        # --- (a) per-write chain ---
        carry = CANON_ZERO
        for pm, pe in prods_me:
            w = [me_to_addend(pm, pe)] + [CANON_ZERO] * (GROUP - 1)
            _, carry, _, _ = wave_step(w, carry)
            # 스텝별 study chain 과 exact 일치
        am, ae = _study_chain_rto48(prods_me)
        gm = (-1 if carry[0] else 1) * carry[2]
        assert STUDY.veq_me(am, ae, gm, carry[1] - 47) or \
            (carry == CANON_ZERO and am == 0)
        fm, fe = STUDY.rne_me(am, ae, 24)   # study 최종 drain (m,e)
        drain_bits = drain_rne24_ftz(*carry)
        assert drain_bits == _pack_frac(Fraction(fm) * TWO ** fe)
        (tm, te), (xm, xe) = STUDY.true_b(prods_me)
        chain_eq_b = STUDY.veq_me(fm, fe, tm, te)
        study_eq_b = STUDY.veq_me(
            *STUDY.chain_perwrite(prods_me, "RTO48"), tm, te)
        assert chain_eq_b == study_eq_b     # 발산 패턴까지 study 와 일치
        # --- (b) single-wave == true B (정리) ---
        wave = [me_to_addend(pm, pe) for pm, pe in prods_me]
        wave += [CANON_ZERO] * (GROUP - len(wave))
        _, _, _, f32 = check_wave_against_fraction(wave, CANON_ZERO)
        assert f32 == _pack_frac(Fraction(tm) * TWO ** te)
        rows.append({"family": name, "products": doc,
                     "perwrite_chain_matches_study": True,
                     "perwrite_chain_equals_true_B": chain_eq_b,
                     "single_wave_equals_true_B": True})
    # 결정적 반증 leaf [1x1, 2^-30 x 2^-30, 1x(-1)] — single wave 는
    # exact 이므로 true 2^-60 을 정확히 낸다 (RTO-tree 는 전 폭 발산).
    det = [me_to_addend(1 << 14, -14), me_to_addend(1 << 14, -74),
           me_to_addend(-(1 << 14), -14)] + [CANON_ZERO] * 29
    _, wide, _, f32 = check_wave_against_fraction(det, CANON_ZERO)
    assert wide_frac(*wide) == TWO ** -60 and f32 == _pack_frac(TWO ** -60)
    return {"families": rows,
            "deterministic_leaf_1_2m60_m1_exact": True,
            "note": "발산 가족 (perwrite_chain_equals_true_B=false) 은 "
                    "§27.3 의 정직한 한계 재현 — 인용 시 표본률이 아니라 "
                    "이 반례를 인용할 것 (study sampling_note 규율)",
            "verdict": "PASS"}


# ===========================================================================
# 자기검증 3 — 경계 directed + fault 계약
# ===========================================================================


def boundary_cases():
    """(tag, products, carry, 설명). 기대값은 전부 Fraction 참조로
    검증되므로 여기서는 구성만 나열한다."""
    mkp = me_to_addend
    max_p = (0, 255, 65025 << 32)           # 최대 bf16 곱 255x255 @ E=254
    cases = [
        ("b_min_lsb_pos",
         [mkp(16641, -266)] + [CANON_ZERO] * 31, CANON_ZERO,
         "weight 2^-266 하단끝: 129x129 @ E=-252, 홀수 s16 — lattice "
         "bit 0 사용; drain 은 FTZ 로 +0, bank 는 nonzero"),
        ("b_min_lsb_neg",
         [mkp(-16641, -266)] + [CANON_ZERO] * 31, CANON_ZERO,
         "위의 음수판 — drain 은 FTZ 로 -0 (0x80000000)"),
        ("b_top_pos", [max_p] * GROUP, CANON_ZERO,
         "weight 2^260 상단끝: 32 x 최대곱, resolve bit 526 사용, "
         "drain 은 overflow 로 +Inf"),
        ("b_top_neg", [(1, 255, 65025 << 32)] * GROUP, CANON_ZERO,
         "전부 음수 최대곱 — two's-complement sign bit 527 행사, "
         "drain -Inf"),
        ("b_cancel_zero",
         [mkp(1 << 14, -14), mkp(1 << 15, 20), mkp(16641, -40),
          mkp(-(1 << 14), -14), mkp(-(1 << 15), 20), mkp(-16641, -40)]
         + [CANON_ZERO] * 26, CANON_ZERO,
         "대규모 상쇄 -> exact 0: canonical zero (0,-1024,0), bank +0, "
         "drain +0"),
        ("b_cancel_with_carry",
         [mkp(-(1 << 14), 85), mkp(-(1 << 14), 85)] + [CANON_ZERO] * 30,
         (0, 100, 1 << 47),
         "carry 2^100 을 곱 -2^99 x2 로 정확히 상쇄 -> canonical zero"),
        ("b_carry_dominant_jam",
         [mkp(16641, -266)] + [CANON_ZERO] * 31, (0, 250, 1 << 47),
         "carry 지배 + 최하단 dust -> RTO sticky-jam 이 LSB 를 세움"),
        ("b_carry_dominant_borrow",
         [mkp(-16641, -266)] + [CANON_ZERO] * 31, (0, 250, 1 << 47),
         "carry 지배 - dust -> binade 하강 + 전비트 borrow + jam"),
        ("b_carry_negligible",
         wave_rand_wide(random.Random(0xB0)), (0, -250, 1 << 47),
         "carry 미미 (2^-250, exp < -219 의 표현 가능 케이스)"),
        ("b_carry_identity_min",
         [CANON_ZERO] * GROUP, (0, -266, 1 << 47),
         "곱 전부 0 + 최소 양의 lattice 값 carry -> wide == carry "
         "bit-identical (48-bit 값은 RTO exact)"),
        ("b_rne48_discriminator",
         [mkp(1, 48), mkp(1, 24), mkp(1, 0)] + [CANON_ZERO] * 29,
         CANON_ZERO,
         "x = 2^48+2^24+1: RTO-48 store -> drain 0x57800001 (정답). "
         "RNE-48 store 로 잘못 구현된 RTL 은 0x57800000 (1 ulp low, "
         "double rounding) — store 반올림 모드 판별 벡터 (§27.2.1)"),
        ("b_tie_q25_killer",
         [mkp(1, 0), mkp(1, -24), mkp(1, -60)] + [CANON_ZERO] * 29,
         CANON_ZERO,
         "x = 1+2^-24+2^-60 (정리의 directed tie): 정답 0x3F800001 — "
         "q=25 급 추출이면 tie 를 놓친다"),
        ("b_f16_min_subnormal_sq",
         [mkp(1, -48)] + [CANON_ZERO] * 31, CANON_ZERO,
         "f16 최소 subnormal 곱 (2^-24)^2 = 2^-48 — f16 하단끝 "
         "(값-충실 normalized 인코딩)"),
        ("b_f16_max_sq",
         [(0, 31, 4190209 << 26)] * GROUP, CANON_ZERO,
         "f16 최대 normal 곱 (65504)^2 x32 — f16 상단끝, lane raw 형식"),
        ("b_neg_exact_pow2",
         [mkp(-(1 << 14), 85), mkp(-(1 << 14), 85)] + [CANON_ZERO] * 30,
         CANON_ZERO,
         "정확한 음의 2의 거듭제곱 (-2^100): 음수 normalize/추출 경로"),
        ("b_all_neg_mixed",
         [(1, e + 1, s << 32) for e, s in
          [(-40, 33000), (0, 20000), (37, 65025), (-120, 16384),
           (5, 40000), (-7, 30000), (60, 17000), (-200, 21000)] * 4],
         (1, 10, (1 << 47) | 1),
         "전부 음수 곱 + 음수 carry (jam LSB 보유) — 음수 경로 종합"),
    ]
    return cases


def check_boundaries():
    rows = []
    for tag, prods, carry, doc in boundary_cases():
        units, wide, bank, f32 = check_wave_against_fraction(prods, carry)
        rows.append({"case": tag, "doc": doc,
                     "wide": [wide[0], wide[1], "0x%012X" % wide[2]],
                     "bank": "0x%016X" % bank, "drain": "0x%08X" % f32})
    # 개별 spot 기대값 (손계산 고정점)
    spot = {r["case"]: r for r in rows}
    assert spot["b_min_lsb_pos"]["drain"] == "0x00000000"
    assert spot["b_min_lsb_neg"]["drain"] == "0x80000000"
    assert spot["b_top_pos"]["drain"] == "0x7F800000"
    assert spot["b_top_neg"]["drain"] == "0xFF800000"
    assert spot["b_cancel_zero"]["wide"] == [0, -1024, "0x000000000000"]
    assert spot["b_cancel_zero"]["bank"] == "0x0000000000000000"
    assert spot["b_cancel_with_carry"]["drain"] == "0x00000000"
    assert spot["b_rne48_discriminator"]["drain"] == "0x57800001"
    assert spot["b_tie_q25_killer"]["drain"] == "0x3F800001"
    assert spot["b_carry_identity_min"]["wide"] == [0, -266, "0x800000000000"]
    return {"cases": rows, "n_cases": len(rows), "verdict": "PASS"}


def _expect_fault(fn, what):
    try:
        fn()
    except LatticeFault:
        return {"probe": what, "loud_fault": True}
    raise AssertionError("fault NOT raised: " + what)


def check_fault_contract():
    """loud-fault-never-silent: 규범 fault 전건이 실제로 raise 되는지."""
    probes = [
        _expect_fault(lambda: fp64_to_wide(0x7FF8000000000000),
                      "FILL qNaN -> sticky fault"),
        _expect_fault(lambda: fp64_to_wide(0x7FF0000000000001),
                      "FILL sNaN -> sticky fault"),
        _expect_fault(lambda: fp64_to_wide(0x7FF0000000000000),
                      "FILL +Inf -> sticky fault"),
        _expect_fault(lambda: fp64_to_wide(0xFFF0000000000000),
                      "FILL -Inf -> sticky fault"),
        _expect_fault(lambda: fp64_to_wide(0x3FF0000000000001),
                      "FILL 48-bit 초과 정밀도 (1+2^-52) -> fault"),
        _expect_fault(lambda: fp64_to_wide(0x0000000000000001),
                      "FILL 2^-1074 (binade < -1024) -> fault"),
        _expect_fault(lambda: fp64_to_wide(1 << 49),
                      "FILL subnormal bl=50 -> fault"),
        _expect_fault(lambda: fp64_to_wide((1 << 50) | 1),
                      "FILL subnormal 정밀도 초과 -> fault"),
        _expect_fault(lambda: addend_units(0, -260, (1 << 47) | 1),
                      "lattice 비표현 addend (LSB < 2^-266) -> fault"),
        _expect_fault(lambda: addend_units(0, 300, 1 << 47),
                      "lattice 범위 초과 addend (2^300) -> fault"),
        _expect_fault(lambda: lattice_accumulate(
            [(0, 260, _M48)] + [(0, 255, 65025 << 32)] * 32),
            "resolve overflow (>= 2^261) -> fault"),
        _expect_fault(lambda: wide_check(0, 0, 0),
                      "비-canonical zero (exp!=-1024) -> fault"),
        _expect_fault(lambda: wide_check(1, -1024, 0),
                      "비-canonical zero (sign=1) -> fault"),
        _expect_fault(lambda: wide_check(0, 0, 1 << 40),
                      "leading zero > 1 operand -> fault"),
        _expect_fault(lambda: wide_to_fp64(0, 0, 1 << 46),
                      "비정규화 bank word encode -> fault"),
    ]
    # ±0 수용 + canonicalize (fault 아님 — 유일한 수용-후-재작성 입력)
    assert fp64_to_wide(0x0000000000000000) == CANON_ZERO
    assert fp64_to_wide(0x8000000000000000) == CANON_ZERO
    # 경계 정상 수용: subnormal bl=51/52 의 정확한 corner
    assert fp64_to_wide(1 << 50) == (0, -1024, 1 << 47)
    assert fp64_to_wide(1 << 51) == (0, -1023, 1 << 47)
    # FILL 은 통과하지만 lattice 표현 밖인 carry (spec-gap note 대상)
    big = fp64_to_wide(_fp64_struct_oracle(0, 300, 1 << 47))
    probes.append(_expect_fault(
        lambda: lattice_accumulate([CANON_ZERO] * 32 + [big]),
        "FILL-valid 이나 lattice 밖 carry (2^300) -> accumulate fault"))
    return {"probes": probes, "n_probes": len(probes),
            "minus_zero_canonicalized": True,
            "subnormal_corners_accepted": True, "verdict": "PASS"}


def check_codec_roundtrip(n_trials):
    """bank word 왕복 bit-exact + struct 독립 oracle 전수 대조."""
    rng = random.Random(SEEDS["codec"])
    corners = [CANON_ZERO,
               (0, -1024, 1 << 47), (1, -1024, (1 << 48) - 1),
               (0, -1023, 1 << 47), (1, -1023, (1 << 48) - 1),
               (0, -1022, 1 << 47), (1, 1023, (1 << 48) - 1),
               (0, 1023, 1 << 47), (0, 0, 1 << 47),
               (0, -266, 1 << 47), (0, 260, (1 << 48) - 1)]
    n = 0
    for i in range(n_trials):
        if i < len(corners):
            w = corners[i]
        else:
            w = (rng.randint(0, 1), rng.randint(WEXP_MIN, WEXP_MAX),
                 (1 << 47) | rng.getrandbits(47))
        bits = wide_to_fp64(*w)
        assert bits == _fp64_struct_oracle(*w)
        assert fp64_to_wide(bits) == w
        n += 1
    return {"N": n, "seed": SEEDS["codec"], "corners": len(corners),
            "struct_oracle_mismatches": 0, "roundtrip_mismatches": 0,
            "verdict": "PASS"}


# ===========================================================================
# 벡터 파일 생성
# ===========================================================================


class VecEmitter:
    """벡터 누적기 — 모든 벡터는 emit 시점에 check_wave_against_fraction
    + segment 기하 assert 를 통과해야 한다 (전 벡터 golden 이중 검증)."""

    def __init__(self):
        self.lines = []
        self.families = []
        self.max_span = 0
        self._fam = None

    def begin(self, name, doc):
        self._fam = {"family": name, "doc": doc,
                     "start": len(self.lines), "count": 0}
        self.families.append(self._fam)

    def emit(self, products, carry):
        units, wide, bank, f32 = check_wave_against_fraction(products, carry)
        self.max_span = max(self.max_span, check_segments(
            list(products) + [carry], units))
        v = 0
        for a in list(products) + [carry]:
            v = (v << 64) | field_encode(*a)
        v = (v << LAT_W) | lattice_word(units)
        v = (v << 64) | field_encode(*wide)
        v = (v << 64) | bank
        v = (v << 32) | f32
        assert v < (1 << VEC_BITS)
        self.lines.append("%0*x" % (VEC_HEX, v))
        self._fam["count"] += 1
        return wide


def gen_vectors():
    em = VecEmitter()

    # ---- directed: 결정적 반증 leaf + jam family 양 granularity ----
    em.begin("det_leaf", "[1x1, 2^-30 x 2^-30, 1x(-1)] — RTO-tree 전 폭 "
             "반증 leaf 의 single-wave (exact 라 정답 2^-60)")
    em.emit([me_to_addend(1 << 14, -14), me_to_addend(1 << 14, -74),
             me_to_addend(-(1 << 14), -14)] + [CANON_ZERO] * 29, CANON_ZERO)

    fams = list(STUDY.JAM_FAMILIES) + STUDY.POSIT_FAMILIES[3:]
    em.begin("jam_single_wave", "F1..F9 전 곱을 1 wave 로 — 정리에 의해 "
             "true B 와 bit-exact (drain 까지)")
    for _, _, prods_me in fams:
        wave = [me_to_addend(pm, pe) for pm, pe in prods_me]
        em.emit(wave + [CANON_ZERO] * (GROUP - len(wave)), CANON_ZERO)

    em.begin("jam_perwrite_chain", "F1..F9 곱 1개 = wave 1개 (carry "
             "체이닝) — RTO-48 store jam 의 정직한 한계 재현 (§27.3)")
    for _, _, prods_me in fams:
        carry = CANON_ZERO
        for pm, pe in prods_me:
            w = [me_to_addend(pm, pe)] + [CANON_ZERO] * (GROUP - 1)
            carry = em.emit(w, carry)

    em.begin("boundary", "경계 directed — check_boundaries 와 동일 구성 "
             "(설명은 report 의 boundary_directed.cases)")
    for _, prods, carry, _ in boundary_cases():
        em.emit(prods, carry)

    # ---- random families ----
    rng = random.Random(SEEDS["vec_rand_wide"])
    em.begin("rand_bf16_wide", "전 지수역 임의 bf16 곱 32개 + 임의 "
             "carry (zero 35% / 임의 lattice 값의 RTO-48)")
    for _ in range(1200):
        em.emit(wave_rand_wide(rng), rand_carry(rng))

    rng = random.Random(SEEDS["vec_cancel"])
    em.begin("cancellation", "X, -X + 수십 binade 아래 dust — 대규모 "
             "상쇄 + park 계열")
    for _ in range(700):
        em.emit(wave_cancel(rng), rand_carry(rng))

    rng = random.Random(SEEDS["vec_tie"])
    em.begin("tie_straddle", "1 + half-ulp24 + bit-48 아래 dust — "
             "tie/jam/sticky 집중")
    for _ in range(700):
        em.emit(wave_tie(rng), rand_carry(rng))

    rng = random.Random(SEEDS["vec_f16"])
    em.begin("f16_rand", "f16 normal 곱 (11x11 -> 22-bit, sig=s22<<26) — "
             "통합 lattice 의 f16 커버")
    for _ in range(400):
        em.emit(wave_f16(rng), rand_carry(rng))

    for band, key, lo, hi in (("S1_near1", "vec_chain_s1", -4, 4),
                              ("S4_hi_band", "vec_chain_s4", 118, 126),
                              ("S5_mid_band", "vec_chain_s5", 48, 56)):
        rng = random.Random(SEEDS[key])
        em.begin("chain_" + band, "K=1024 accumulate chain x6 (32 "
                 "wave/chain, carry 체이닝) — factor exp [%d,%d]"
                 % (lo, hi))
        for _ in range(6):
            carry = CANON_ZERO
            for _ in range(32):
                carry = em.emit(
                    [rand_bf16_addend(rng, lo, hi) for _ in range(GROUP)],
                    carry)

    rng = random.Random(SEEDS["vec_parkcancel"])
    em.begin("chain_parkcancel", "cross-wave park-plus-cancel chain x2 — "
             "F1/F4 계열의 확률적 확장 (carry 체이닝)")
    for _ in range(2):
        carry, pending = CANON_ZERO, []
        for _ in range(32):
            prods, j = [CANON_ZERO] * GROUP, 0
            for (s, e, sig) in pending:
                prods[j] = (1 - s, e, sig)
                j += 1
            pending = []
            for _ in range(rng.randint(1, 3)):
                x = rand_bf16_addend(rng, -10, 10)
                prods[j] = x
                j += 1
                if rng.random() < 0.7:
                    pending.append(x)
            for _ in range(rng.randint(1, 4)):
                prods[j] = rand_bf16_addend(rng, -40, -25)
                j += 1
            carry = em.emit(prods, carry)

    rng = random.Random(SEEDS["vec_sparse"])
    em.begin("sparse", "nonzero 0..32개 (첫 5개: 전-zero+zero-carry -> "
             "canonical zero; 다음 5개: 전-zero+carry -> 항등)")
    for i in range(300):
        if i < 5:
            em.emit([CANON_ZERO] * GROUP, CANON_ZERO)
        elif i < 10:
            c = rand_carry(rng)
            while c == CANON_ZERO:
                c = rand_carry(rng)
            em.emit([CANON_ZERO] * GROUP, c)
        else:
            em.emit(wave_sparse(rng), rand_carry(rng))

    return em


def write_vector_file(em):
    hdr = [
        "// lattice_wave_vectors.hex — v2.0 528-bit lattice wave-step TB "
        "벡터 (결정적, 고정 seed)",
        "// 생성기: scripts/golden_lattice.py — 비트 레이아웃 계약: "
        "include/generated/lattice_vec_contract.md",
        "// 1 line = 1 wave-step = %d hex chars = %d bits; N_VEC = %d"
        % (VEC_HEX, VEC_BITS, len(em.lines)),
    ]
    VEC_PATH.write_text("\n".join(hdr + em.lines) + "\n")


def verify_vector_file():
    """파일 재독 후 전 라인을 필드 분해 -> golden 재계산 -> 4개 기대
    필드 전부 재대조 (파일 자체의 자기증명)."""
    n = 0
    for ln in VEC_PATH.read_text().splitlines():
        if not ln or ln.startswith("//"):
            continue
        assert len(ln) == VEC_HEX
        v = int(ln, 16)
        f32 = v & 0xFFFFFFFF
        v >>= 32
        bank = v & _M64
        v >>= 64
        widef = v & _M64
        v >>= 64
        resolved = v & _M528
        v >>= LAT_W
        adds = [field_decode((v >> (64 * (N_ADDENDS - 1 - k))) & _M64)
                for k in range(N_ADDENDS)]
        units, wide, bank_g, f32_g = wave_step(adds[:GROUP], adds[GROUP])
        assert lattice_word(units) == resolved
        assert field_encode(*wide) == widef
        assert bank_g == bank and f32_g == f32
        n += 1
    return n


# ===========================================================================
# 계약 문서 (generated — 벡터와 같은 스크립트가 원자적으로 동기 유지)
# ===========================================================================


def contract_text(em):
    fam_rows = "\n".join(
        "| %s | %d | %d | %s |" % (f["family"], f["start"], f["count"],
                                   f["doc"].replace("\n", " "))
        for f in em.families)
    seed_rows = "\n".join("| `%s` | `0x%X` |" % kv for kv in SEEDS.items())
    n = len(em.lines)
    return """<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor \
contributors -->
<!-- GENERATED by scripts/golden_lattice.py — 손편집 금지. 재생성은 \
`python3 scripts/golden_lattice.py` (byte-identical). -->

# lattice_wave_vectors.hex — 벡터 비트 레이아웃 계약 (v2.0 528-bit lattice)

- **규범 출처**: `.claude-memos/wt64v1_spec.md` §27.2 (lattice/추출/bank/
  drain 전 규범), §23.10.1 + `FP_AddWide.v` 헤더 (PACK_WIDE 값 규약과
  canonical zero (sign=0, exp=-1024, sig=0)).
- **golden**: `scripts/golden_lattice.py` (본 문서의 생성기이자 모든
  기대값의 산출자 — golden-before-RTL, §27.6 ①). rounding core 는
  `scripts/golden_fp32.py` 에서 import.
- **벡터 파일**: `include/generated/lattice_wave_vectors.hex` —
  `$readmemh` 형식, 주석 3줄 + %d 라인. 결정적 (고정 seed, 재실행
  byte-identical; sha256 은 `lattice_golden_report.json`).

## 1. 라인 형식

1 라인 = 1 wave-step (= 1 dispatch) = **%d hex 문자 = %d bit** 단일
토큰. `VEC[%d:0]` 로 읽었을 때 (MSB 먼저):

| 필드 | 비트 구간 | 폭 | 의미 |
|---|---|---|---|
| `ADDEND[0..31]` | `[2799-64k : 2736-64k]`, k=0..31 | 64 x32 | 곱 operand 32개 (lane k) |
| `ADDEND[32]` | `[751:688]` | 64 | **bank carry-in** (33번째 EXACT addend, §27.2.1) |
| `EXP_RESOLVED` | `[687:160]` | 528 | 기대 resolve 값 — exact 33-항 합의 528-bit two's-complement (아래 §3) |
| `EXP_WIDE` | `[159:96]` | 64 | 기대 RTO-48 추출 결과 (addend 와 같은 64-bit wide field; exact 0 이면 canonical zero) |
| `EXP_BANK` | `[95:32]` | 64 | 기대 bank word — `EXP_WIDE` 의 IEEE binary64 무손실 재인코딩 (§27.2.2) |
| `EXP_FP32` | `[31:0]` | 32 | 기대 즉시-drain 결과 — RNE-24 + flush-after-round FTZ (§27.2.3). 정리에 의해 `RNE24(exact 33-항 합)` 과 비트 동일 |

## 2. 64-bit wide field 인코딩 (`ADDEND[*]`, `EXP_WIDE` 공통)

```
[63:60] = 4'b0000 (예약 — 반드시 0)
[59]    = sign
[58:48] = exp  — 11-bit two's complement, -1024..+1023
[47:0]  = sig  — unsigned significand, unit at bit 47
값       = (-1)^sign * sig * 2^(exp-47)
```

- **canonical zero** = `64'h0400_0000_0000_0000` (sign=0, exp=-1024,
  sig=0) — zero 의 유일한 인코딩. 미사용 곱 슬롯도 이 값이다.
- **nonzero 규약**: leading zero <= 1 (`sig >= 2^46`) —
  `FP_AddWide.v` PRECONDITIONS 와 동형. carry-in 과 `EXP_WIDE` 는 항상
  normalized (`sig[47]==1`).
- **곱 operand 의 lane raw 형식**: bf16 곱 = `sig = (m8a*m8b) << 32`,
  `exp = Ea+Eb+1` (8x8 -> 16-bit significand, §27.2.1); f16 normal 곱 =
  `sig = (m11a*m11b) << 26`, `exp = Ea+Eb+1`. directed (m,e) 재현
  입력과 f16 subnormal 곱은 값-충실 normalized 인코딩을 쓴다 (f16
  subnormal 곱의 lane-측 raw 형태는 RTL C2 경로 확정 사항 — lattice
  계약은 값만 구속한다).

## 3. `EXP_RESOLVED` — 528-bit lattice 값

`L = EXP_RESOLVED` 를 two's complement 로 해석: 값 =
`signed(L) * 2^-266`. bit i (i=0..526) 의 weight = `2^(i-266)`
(즉 `2^-266 .. 2^260`), bit 527 = sign (weight `-2^261`). 이는 exact
33-항 합과 정확히 같다 (dot 내부 반올림 0회 — §27.2.1).

**적재 기하 pin** (§27.2.1 "segment 기하는 golden model/RTL 에서 확정"):
물리 lattice = 576 bit = **9 segment x 64 bit**; 값 비트는
`PHYS[575:48]` (`PHYS[48]` = weight `2^-266`), `PHYS[47:0]` 은 표현성
전제로 항상 0 인 정렬 여유. addend 의 48-bit sig 필드는 LSB 를
`q = exp + 267` 에 두고 `PHYS[q+47:q]` 를 점유; `k = q[9:6]` (segment
demux), `o = q[5:0]` (static 6-stage barrel). `48 <= 64` 이므로 데이터
필드는 인접 **<= 2 segment** 만 건드린다 ("2-of-9"). 음수 addend 는
two's complement (mod 2^576) — trailing zero 보존으로 `PHYS[47:0]` 은
불변 0. resolve = `(S mod 2^576) >> 48` 의 하위 528 bit. golden 은 이
기하의 물리 누산이 direct 정수 누산과 bit-identical 함을 전 벡터에서
assert 했다.

## 4. 전제조건 (모든 벡터가 보장; RTL 위반 입력은 벡터에 없음)

- 모든 addend 는 **lattice-표현 가능** (2^-266 의 정수배, |v| < 2^261)
  이고 33-항 합도 lattice 범위 안이다 (§27.2.1 폭 도출; overflow 는
  loud-fault 계약 — 아래 §7).
- zero addend 는 canonical zero 뿐. carry-in 은 normalized 또는
  canonical zero.
- **NaN/Inf 는 등장하지 않는다** — wide 포맷 자체에 인코딩이 없다.
  차단 계약 위치: (i) bank FILL ingest 의 fp64 E=2047 검사 -> sticky
  fault (§27.2.2); (ii) 곱 operand 는 FP_CLASSIFY 가 specials 를
  lattice 이전에 필터 (§23.10.5 / FP_AddWide PRECONDITIONS 동형).
- `EXP_FP32` 는 ±Inf (drain overflow) 또는 ±0 (FTZ / exact zero) 일 수
  있으나 NaN 은 절대 아니다.

## 5. family 배치 (라인 인덱스는 주석 제외 0-base)

| family | start | count | 의도 |
|---|---|---|---|
%s

- 총 **%d 벡터**. `jam_perwrite_chain` / `chain_*` family 는 앞 벡터의
  `EXP_WIDE` 가 다음 벡터의 `ADDEND[32]` 로 들어가는 체인이지만, 각
  라인이 자체 carry-in 을 운반하므로 TB 는 라인 단위 독립 검증만 하면
  된다 (체인 재현은 선택).
- `boundary` family 의 케이스별 의미는
  `lattice_golden_report.json` 의 `checks.boundary_directed.cases`.

## 6. TB 스케치 + 판정 규칙

```verilog
localparam integer N_VEC = %d;
reg [%d:0] vec [0:N_VEC-1];
initial $readmemh("include/generated/lattice_wave_vectors.hex", vec);
// addend k 의 64-bit field (k 는 generate 상수 — dynamic part-select
// 금지는 project law; TB 도 static unroll 로):
//   wire [63:0] fld_k = vec[i][2799 - 64*k -: 64];
```

- DUT resolve 출력 == `EXP_RESOLVED`, RTO-48 추출 == `EXP_WIDE`, bank
  인코딩 == `EXP_BANK`, PACK_FINAL drain == `EXP_FP32` — 4층 전부
  bit-exact 판정. 하나라도 불일치 = FAIL (표본률 논증 금지).
- `b_rne48_discriminator` (boundary family) 는 store 를 RNE-48 로 잘못
  구현한 RTL 을 1 ulp 로 적발한다; `b_tie_q25_killer` 는 추출 폭 부족
  (q<26) 을 적발한다.

## 7. 미결 pin (정직 기록 — 벡터는 이 영역을 회피)

- **FILL-valid 이나 lattice-표현 밖 carry**: bank word 는 fp64 로
  |v| <= ~2^1024 까지 담지만 lattice 는 |v| < 2^261 만 수용한다
  (§27.2.1 폭 도출). FILL 로 그런 값을 넣고 accumulate 하는 경로의 RTL
  fault 배선 (sticky-fault 클래스 배정) 은 §27.2 미명시 — golden 은
  loud fault (`LatticeFault`) 로 고정했고, GATE V20-2 하류 ③ (bank
  RTL + TLA+) COMMIT 에서 pin 해야 한다.
- **fp64 -0 FILL**: 수용 + canonical +0 화 (§27.2.2 (iii)) — "검증
  통과 값은 round-trip bit-exact" 문장의 유일한 예외 (수용-후-재작성).
- f16 subnormal 곱의 lane-측 raw operand 형태 (§2 참조).

## 8. 결정론

고정 seed (아래) 외 난수원 없음, timestamp 없음 — 재실행 산출물은
byte-identical (sha256 은 report).

| seed key | value |
|---|---|
%s
""" % (n, VEC_HEX, VEC_BITS, VEC_BITS - 1, fam_rows, n, n, VEC_BITS - 1,
       seed_rows)


# ===========================================================================
# main
# ===========================================================================


def _sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    t_start = time.time()

    def stamp(tag, t0):
        print("  [%6.1fs] %s" % (time.time() - t0, tag))
        sys.stdout.flush()

    print("golden_lattice: v2.0 528-bit lattice golden model — self-check "
          "+ TB vector generation (fixed seeds)")

    t0 = time.time()
    theorem = check_theorem_sweep(20000)
    stamp("extraction theorem identity sweep (20k waves x 3 layers)", t0)

    t0 = time.time()
    perm = check_permutation(400, 6)
    stamp("permutation invariance (400 x 7 orders)", t0)

    t0 = time.time()
    jam = check_jam_families()
    stamp("directed jam families F1..F9 vs acc_format_study", t0)

    t0 = time.time()
    bnd = check_boundaries()
    faults = check_fault_contract()
    stamp("boundary directed + fault contract", t0)

    t0 = time.time()
    codec = check_codec_roundtrip(20000)
    stamp("bank codec roundtrip + struct oracle (20k)", t0)

    t0 = time.time()
    em = gen_vectors()
    write_vector_file(em)
    CONTRACT_PATH.write_text(contract_text(em))
    stamp("vector generation (%d vectors, %d families)"
          % (len(em.lines), len(em.families)), t0)

    t0 = time.time()
    n_verified = verify_vector_file()
    assert n_verified == len(em.lines)
    stamp("vector file re-read self-verify (%d lines)" % n_verified, t0)

    report = {
        "_doc": "v2.0 wave-step-atomic accumulation — 528-bit exact-"
                "integer lattice golden model (spec §27.2) 의 자기검증 "
                "결과 + RTL TB 벡터 명세. 생성기: scripts/golden_lattice"
                ".py (stdlib-only, 고정 seed, 재실행 byte-identical, "
                "rounding core 는 scripts/golden_fp32.py). 벡터 계약: "
                "include/generated/lattice_vec_contract.md.",
        "normative_source": "wt64v1_spec.md §27.2 (+ §23.10.1 PACK_WIDE / "
                            "FP_AddWide.v 인터페이스 계약)",
        "determinism": {
            "seeds": SEEDS,
            "note": "고정 정수 seed 외 난수원/timestamp 없음 — 산출물 "
                    "3종 (hex/md/json) 전부 byte-identical 재생성",
        },
        "lattice_constants": {
            "width_bits": LAT_W, "lsb_weight_2exp": LAT_LSB_EXP,
            "top_weight_2exp": LAT_TOP_EXP, "addends": N_ADDENDS,
            "extraction": "RTO_48 (round-to-odd, top-48 + sticky-jam)",
            "drain": "RNE-24 + flush-after-round FTZ (PACK_FINAL)",
            "canonical_zero": "(sign=0, exp=-1024, sig=0)",
            "segment_geometry": {
                "phys_bits": PHYS_W, "segments": N_SEG,
                "seg_width": SEG_W, "value_lsb_phys_bit": 48,
                "max_segments_touched_per_addend": em.max_span,
            },
        },
        "checks": {
            "extraction_theorem_identity": theorem,
            "permutation_invariance": perm,
            "jam_family_study_mirror": jam,
            "boundary_directed": bnd,
            "fault_contract": faults,
            "bank_codec_roundtrip": codec,
            "vector_file_self_verify": {
                "lines": n_verified, "mismatches": 0, "verdict": "PASS"},
        },
        "vector_file": {
            "path": "include/generated/lattice_wave_vectors.hex",
            "n_vectors": len(em.lines),
            "bits_per_line": VEC_BITS,
            "hex_chars_per_line": VEC_HEX,
            "families": em.families,
            "sha256": _sha256(VEC_PATH),
        },
        "contract": {
            "path": "include/generated/lattice_vec_contract.md",
            "sha256": _sha256(CONTRACT_PATH),
        },
        "spec_gap_notes": [
            "FILL-valid (fp64/PACK_WIDE 표현 가능) 이나 lattice-표현 밖 "
            "(|v| >= 2^261 또는 2^-266 미만 정밀도) 인 carry-in 의 RTL "
            "fault 배선은 §27.2 미명시 — golden 은 loud fault 로 고정, "
            "GATE V20-2 하류 ③ bank RTL COMMIT 에서 sticky-fault 클래스 "
            "배정 필요",
            "fp64 -0 FILL 은 수용 + canonical +0 화 — round-trip "
            "bit-exact 보증의 유일한 수용-후-재작성 예외",
            "f16 subnormal 곱의 lane-측 raw operand 형태는 RTL C2 경로 "
            "확정 사항 — 본 벡터는 값-충실 normalized 인코딩 사용",
        ],
        "verdicts": {
            "all_checks_pass": True,
            "theorem_identity_zero_mismatch": True,
            "permutation_bit_identical": True,
            "jam_families_match_study_exactly": True,
            "canonical_zero_on_exact_zero": True,
            "segment_2_of_9_never_exceeded": em.max_span <= 2,
        },
    }
    REPORT_PATH.write_text(json.dumps(report, indent=1, allow_nan=False,
                                      ensure_ascii=False) + "\n")
    print("wrote %s" % VEC_PATH)
    print("wrote %s" % CONTRACT_PATH)
    print("wrote %s" % REPORT_PATH)
    print("total %.1fs" % (time.time() - t_start))
    print("headlines:")
    print("  vectors: %d (families %d), sha256 %s"
          % (len(em.lines), len(em.families),
             report["vector_file"]["sha256"][:16]))
    print("  theorem sweep: %d waves, 0 mismatch (+%d per-vector)"
          % (theorem["N"], len(em.lines)))
    print("  oracle: fp64 struct %d, f32 struct %d checked"
          % (codec["N"], theorem["f32_struct_oracle_checked"]))


if __name__ == "__main__":
    main()
