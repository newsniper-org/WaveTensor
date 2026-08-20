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
  include/generated/lattice_golden_report.json 체크 결과·벡터 수·blake2b512
  include/generated/bank_scenarios.hex         bank 상태기계 시나리오 스트림
                                               (§27.6 하류 ③ 검증 계획 (c))
  include/generated/bank_scenarios_contract.md 시나리오 record 형식/의미 계약
  include/generated/cluster_wave_vectors.hex   ④ cluster operand-level 벡터
                                               (bf16/f16 쌍 -> lane raw 곱 ->
                                               4층 기대값; GATE V20-3 의무 2)
  include/generated/cluster_vec_contract.md    operand-레벨 비트/정책 계약

BANK 상태기계 reference (§27.6 하류 ③ (c) — 2026-08-16 확장):
  wide ACC bank (2 banks x 32 lanes x 64b/cluster) 의 slot ownership
  (RequestOwn/CommitOwn — proofs/tla/AccBank.tla 대응) + FILL/DRAIN/ZERO
  + wave-step 체이닝 (IF-1 read-before-dispatch / IF-2 ownership window
  / IF-3 같은 slot >= LATENCY=7 / IF-4 canonical zero 기록 — §27.2.2
  하류 ③ COMMIT 블록) 의 cycle-정밀 실행기. 명령 시퀀스 (cycle-태그) 를
  받아 기대 bank 상태·sticky fault 를 산출하고, 통합 TB 용 시나리오
  스트림을 생성한다 (같은 slot 체이닝 경계 7/8, gap 1/3/17 재시작,
  창 경계 cycle 정밀 FILL/DRAIN/ZERO 인터리브, SPILL guard 거부/수용
  + 미정의 opcode 6/7 PROTO_GUARD — 2026-08-16 적대 재실측 폐쇄 —,
  랜덤 인터리브 300+).

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
BANK_HEX_PATH = GEN / "bank_scenarios.hex"
BANK_CONTRACT_PATH = GEN / "bank_scenarios_contract.md"
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

# cluster operand-level 벡터 (④ GATE V20-3 — 2026-08-17 확장):
#   META 32 + operand pair 32x32 + 기대 raw 곱 32x64 + carry 64
#   + RESOLVED 528 + WIDE 64 + BANK 64 + FP32 32 = 3856 bit.
#   하위 [2799:0] 은 lattice_wave_vectors.hex 의 라인 형식과 비트 단위로
#   동일하다 (addend 32개 = 기대 lane raw 곱) — 계약 문서 §1.
CVEC_BITS = 32 + GROUP * 32 + GROUP * 64 + 64 + LAT_W + 64 + 64 + 32
CVEC_HEX = CVEC_BITS // 4                               # 964
CLUSTER_VEC_PATH = GEN / "cluster_wave_vectors.hex"
CLUSTER_CONTRACT_PATH = GEN / "cluster_vec_contract.md"

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
    "bank_rand_interleave": 0x1A77E21,
}

# cluster operand-level 벡터 전용 seed (④ 확장). 별도 dict 인 이유:
# SEEDS 는 lattice_vec_contract.md §8 표에 전사되므로, 거기에 키를 더하면
# 기존 계약 문서의 byte-identity 가 깨진다 — 기존 산출물 3종 (lattice
# hex/contract, bank 기존 record 스트림) 은 ④ 확장 후에도 byte-identical
# 이어야 한다 (④ 검증 의무 4 무회귀).
CLUSTER_SEEDS = {
    "cl_bf16_rand": 0x1A77E31,
    "cl_f16_rand": 0x1A77E32,
    "cl_cancel": 0x1A77E33,
    "cl_sparse": 0x1A77E34,
    "cl_chain_bf16": 0x1A77E35,
    "cl_chain_mixed": 0x1A77E36,
    "cl_chain_parkcancel": 0x1A77E37,
    "cl_daz_rand": 0x1A77E38,
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
    산술 등가). 수용 구간은 **개구간 (-2^261, 2^261)** (§27.2.1 amendment
    pin 1, 2026-08-16): 총합 == 정확히 -2^261 (signed 표현 하한) 도
    경계 도달 = lattice overflow 동일 클래스 loud fault 다 (RTL fault
    (f) 대응)."""
    if len(addends) != N_ADDENDS:
        raise LatticeFault("exactly 33 addends required (32 products + "
                           "carry-in), got %d" % len(addends))
    total = 0
    for a in addends:
        total += addend_units(*a)
    if not LAT_MIN < total <= LAT_MAX:
        raise LatticeFault("lattice overflow: resolved sum outside "
                           "(-2^261, 2^261) — precondition violation "
                           "(open interval, §27.2.1 amendment pin 1)")
    return total


def lattice_word(units):
    """resolve 결과의 528-bit two's-complement 표현 (TB 기대값 형)."""
    assert LAT_MIN <= units <= LAT_MAX
    return units & _M528


def extract_rto48(units):
    """추출 = 그 wave-step 의 유일한 반올림: LZC/normalize 후 top-48 +
    sticky-jam = exact 합의 RTO_48. exact zero -> canonical zero.
    지수 범위 검사는 loud fault (§27.2.1 amendment pin 1 의 golden 이행:
    e == 261 <=> |합| >= 2^261 — RTL fault (f) 대응; bare assert 에서
    LatticeFault 로 승격, 2026-08-16)."""
    if units == 0:
        return CANON_ZERO
    s = 1 if units < 0 else 0
    a = -units if s else units
    e = a.bit_length() - 1 + LAT_LSB_EXP    # binade
    sh = a.bit_length() - Q48
    sig = _rto(a, sh) if sh > 0 else a << -sh
    assert (1 << 47) <= sig <= _M48
    if not -266 <= e <= LAT_TOP_EXP:        # fault (f) — pin 1 승격
        raise LatticeFault(
            "extract exponent outside lattice band (e == %d; e == 261 "
            "<=> |sum| >= 2^261 — open-interval boundary, fault (f))" % e)
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
        _expect_fault(lambda: lattice_accumulate(
            [(1, 260, 1 << 47)] * 2 + [CANON_ZERO] * 31),
            "합 == 정확히 -2^261 (signed 하한 경계) -> fault — 개구간 "
            "(-2^261, 2^261) 수용 (pin 1)"),
        _expect_fault(lambda: extract_rto48(LAT_MIN),
                      "extract e == 261 (|합| == 2^261) -> fault (f) — "
                      "pin 1 의 bare assert 승격"),
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
# bank 상태기계 reference — §27.6 하류 ③ 검증 계획 (c) (2026-08-16 확장)
# ===========================================================================
# wide ACC bank 의 시나리오-레벨 golden. 규범 출처:
#   * §27.2.2 [하류 ③ COMMIT] IF-1 read-before-dispatch / IF-2 ownership
#     window (start..writeback, LATENCY=7 — 창 내 FILL/DRAIN/ZERO 접촉 =
#     loud sticky fault) / IF-3 같은 slot 체이닝 >= 7, 타 slot II=4 중첩 /
#     IF-4 0x7E = canonical zero 기록.
#   * §27.2.1 amendment pin 1 (개구간 (-2^261, 2^261)) / pin 2 (carry
#     normalized 전제) / §27.2.2 pin 3 (lattice-비표현 carry = fault
#     (d)/(e) 의 carry-lane 적용, 발화 = carry 소비 beat 0).
#   * proofs/tla/AccBank.tla — guard 군 {commit_free, commit_zero,
#     acc_owner, drain_owner, fill_bankfree, zero_owner} 의 cycle-정밀
#     정제 + sticky conflict. fill_owner / FillFaultForeign (외래 spill
#     image 주소) 는 spill slot 모델을 요구하므로 본 시나리오 레벨 밖 —
#     §27.6 검증 계획 (a) 의 TLC 반례 trace 변환이 담당 (계약 문서 §1).
#   * SPILL guard / 미정의 opcode (2026-08-16 적대 재실측 폐쇄): RTL 의
#     spill_ref (창 내 / 비-owner SPILL 거부) 와 cmd_unk (opcode 6/7)
#     -> PROTO_GUARD sticky 경로가 TB 블라인드 스팟이었다 (spill_ref
#     1'b0 절단 / cmd_unk 절단이 TB 를 escape — 변이 실측). 본 레벨이
#     SPILL/UNK 의미론을 §27.2.2 SPILL 항 + FP_AccBank.v 헤더 계약
#     그대로 운반한다 (spill_window / spill_owner / spill_accept /
#     proto_unk family — 거부는 word 불변, 수용은 release + word 잔존).
#
# 시나리오 실행기 bank_execute: cycle-태그 명령 시퀀스를 받아 기대 bank
# 상태·fault 를 산출한다. 형식/의미의 전 계약은 생성 문서
# include/generated/bank_scenarios_contract.md (본 스크립트가 원자적으로
# 동기 유지).

BANK_LATENCY = 7        # N=8 출하 형상: NUM_BEATS+3 (FP_AccLattice.v 헤더)
BANK_II = 4             # NUM_BEATS — 타 slot wave-step 최소 start 간격 (IF-3)
BANK_NSLOTS = 4         # 시나리오 slot 주소 공간 (TB 가 bank x lane 로 사상)
BANK_NO_OWNER = 0xFF    # owner map 인코딩의 "소유자 없음"

_TAG_BEGIN, _TAG_END = 0x01, 0x0F
_TAG_OP = {"REQ": 0x10, "WAVE": 0x11, "FILL": 0x12, "DRAIN": 0x13,
           "ZERO": 0x14, "SPILL": 0x15, "UNK": 0x16}
_OP_FROM_TAG = {v: k for k, v in _TAG_OP.items()}


class ScenarioError(Exception):
    """시나리오 구성 오류 (생성기 규율 위반 — 계약 문서 §2 형식 규율).
    bank fault 가 아니다: fault 는 실행기의 sticky 로만 표현된다."""


def _c(t, op, st, sl, **kw):
    d = {"t": t, "op": op, "st": st, "sl": sl}
    d.update(kw)
    return d


def bank_execute(cmds):
    """cycle-태그 명령 시퀀스 -> 기대 bank 상태/fault (상태기계 reference).

    명령에 in-place 주석을 단다:
      refused  — ownership/window 거부 (거부 + sticky, 상태 무변경)
      vfault   — 값 검증 fault (FILL validation / carry-lane (d)/(e))
      why      — 원인 문자열 (coverage 집계용 — 인코딩에는 없음)
      exp_word — 기대 slot word 스냅샷 (WAVE: cycle t+LATENCY 말;
                 FILL/SPILL/UNK: cycle t 말) — 계약 문서 §6 의 TB 샘플
                 시점 (SPILL/UNK 스냅샷 = word 불변/잔존의 직접 증명)
      fp32     — DRAIN 수용 시 기대 drain 값 (RNE-24 + FTZ)
      spill    — SPILL 수용 시 기대 spill word (fp64 raw — slot word)
    반환: {"sticky", "owner", "words", "horizon"}.

    cycle 처리 순서 (계약 §4): (1) writeback -> (2) acquire commit ->
    (3) 그 cycle 의 명령 (slot 오름차순). 검사 우선순위: window (IF-2/
    IF-3) -> ownership guard -> 값 검증. 모든 거부/fault 는 sticky 이며
    silent 수용은 없다 (project law)."""
    seen, wave_ts = set(), []
    for c in cmds:
        if c["t"] < 0 or not 0 <= c["sl"] < BANK_NSLOTS \
                or not 0 <= c["st"] < 16:
            raise ScenarioError("field out of range: %r" % c)
        key = (c["t"], c["sl"])
        if key in seen:
            raise ScenarioError("two commands on one (cycle, slot): %r"
                                % (key,))
        seen.add(key)
        if c["op"] == "WAVE":
            wave_ts.append(c["t"])
            if len(c["prods"]) != GROUP:
                raise ScenarioError("WAVE needs %d products" % GROUP)
    wave_ts.sort()
    for a, b in zip(wave_ts, wave_ts[1:]):
        if b - a < BANK_II:
            raise ScenarioError(
                "wave starts closer than II=%d: %d,%d" % (BANK_II, a, b))
    by_cycle = {}
    for c in sorted(cmds, key=lambda c: (c["t"], c["sl"])):
        by_cycle.setdefault(c["t"], []).append(c)
    horizon = max(c["t"] for c in cmds) + BANK_LATENCY + 2

    words = [0] * BANK_NSLOTS       # power-on 정의: canonical +0 (계약 §3)
    owner = [None] * BANK_NSLOTS
    win = [None] * BANK_NSLOTS      # slot 별 마지막 '수용된' wave 의 start
    sticky, pend, wb, hist = False, None, {}, []

    def fdz_window_open(sl, t):
        # IF-2: FILL/DRAIN/ZERO 의 fault 창 = [start, start+LATENCY]
        # (writeback cycle 포함 — 창 마지막 cycle 접촉도 fault, 직후 합법)
        return win[sl] is not None and win[sl] <= t <= win[sl] + BANK_LATENCY

    for t in range(horizon + 1):
        if t in wb:                                     # (1) writeback
            sl_w, w_w = wb.pop(t)
            words[sl_w] = w_w
        if pend is not None and pend[2] == t:           # (2) acquire commit
            p_st, p_sl, _, p_cmd = pend
            if owner[p_sl] is None:                     # commit_free PASS
                owner[p_sl] = p_st                      # CommitOwn
                words[p_sl] = 0                         # commit_zero (융합)
            else:                                       # RejectOwn
                sticky = True
                p_cmd["refused"] = True
                p_cmd["why"] = "reject_own"
            pend = None
        for c in by_cycle.get(t, ()):                   # (3) 명령
            op, st_id, sl = c["op"], c["st"], c["sl"]
            c.setdefault("refused", False)
            c.setdefault("vfault", False)
            c.setdefault("why", None)
            if op == "REQ":
                if pend is not None:
                    raise ScenarioError("pend register occupied at t=%d"
                                        % t)
                pend = (st_id, sl, t + 1, c)
            elif op == "WAVE":
                if win[sl] is not None and t - win[sl] < BANK_LATENCY:
                    c["refused"], c["why"] = True, "window_chain"   # IF-3
                    c["off"] = t - win[sl]  # ④ 교차곱 계측 (인코딩 밖)
                elif owner[sl] != st_id:
                    c["refused"], c["why"] = True, "acc_owner"
                if c["refused"]:
                    sticky = True
                else:
                    # IF-1: carry read 는 start 이전 완료 — beat 0 공급
                    carry = fp64_to_wide(words[sl])
                    try:
                        addend_units(*carry)   # pin 3: carry 소비 시점 검사
                    except LatticeFault as ex:
                        c["vfault"] = True
                        c["why"] = "carry_range_d" if "range" in str(ex) \
                            else "carry_precision_e"
                        sticky = True
                        win[sl] = t     # 창은 점유, writeback 은 억제 (§5)
                    else:
                        try:
                            _, wide, bankw, f32 = check_wave_against_fraction(
                                c["prods"], carry)
                        except LatticeFault as ex:
                            raise ScenarioError(
                                "scenario wave overflows lattice: %s" % ex)
                        wb[t + BANK_LATENCY] = (sl, bankw)
                        win[sl] = t
                        c["_wave"] = (wide, bankw, f32)
            elif op == "FILL":
                if fdz_window_open(sl, t):
                    c["refused"], c["why"] = True, "window_fill"     # IF-2
                    c["off"] = t - win[sl]  # ④ 교차곱 계측 (인코딩 밖)
                elif owner[sl] is not None:
                    # fill_bankfree — FillFaultBusy (자기/외래 불문 busy)
                    c["refused"], c["why"] = True, "fill_busy"
                if c["refused"]:
                    sticky = True
                else:
                    try:
                        w = fp64_to_wide(c["word"])  # validation (i)-(iii)
                    except LatticeFault:
                        c["vfault"], c["why"] = True, "fill_validation"
                        sticky = True
                    else:
                        owner[sl] = st_id            # acquire-by-fill
                        words[sl] = wide_to_fp64(*w)  # ±0 -> canonical +0
            elif op == "DRAIN":
                if fdz_window_open(sl, t):
                    c["refused"], c["why"] = True, "window_drain"    # IF-2
                    c["off"] = t - win[sl]  # ④ 교차곱 계측 (인코딩 밖)
                elif owner[sl] != st_id:
                    c["refused"], c["why"] = True, "drain_owner"
                if c["refused"]:
                    sticky = True
                else:
                    c["fp32"] = drain_rne24_ftz(*fp64_to_wide(words[sl]))
                    owner[sl] = None    # release — word 는 SRAM 잔존
            elif op == "ZERO":
                if fdz_window_open(sl, t):
                    c["refused"], c["why"] = True, "window_zero"     # IF-2
                    c["off"] = t - win[sl]  # ④ 교차곱 계측 (인코딩 밖)
                elif owner[sl] != st_id:
                    c["refused"], c["why"] = True, "zero_owner"
                if c["refused"]:
                    sticky = True
                else:
                    words[sl] = 0       # IF-4 canonical zero (owner 불변)
            elif op == "SPILL":
                # §27.2.2 SPILL / FP_AccBank.v 헤더: window -> owner 통과
                # 시 word 를 spill 스트림으로 (확폭은 상위 frag FSM 몫),
                # release, word 잔존. 위반 = 거부 + sticky (PROTO_GUARD).
                if fdz_window_open(sl, t):
                    c["refused"], c["why"] = True, "window_spill"    # IF-2
                    c["off"] = t - win[sl]  # ④ 교차곱 계측 (인코딩 밖)
                elif owner[sl] != st_id:
                    c["refused"], c["why"] = True, "spill_owner"
                if c["refused"]:
                    sticky = True
                else:
                    c["spill"] = words[sl]  # 기대 spill_q (slot word)
                    owner[sl] = None    # release — word 는 SRAM 잔존
            elif op == "UNK":
                # 미정의 opcode (6/7) — PROTO_GUARD (방어적 decode):
                # sticky 만. 상태 무변경, 응답 없음 (RTL resp_v_q 는
                # 정의된 비-REQ op 에만 뜬다 — loud-fault-never-silent).
                c["refused"], c["why"] = True, "proto_unk"
                sticky = True
            else:
                raise ScenarioError("unknown op %r" % op)
        hist.append(tuple(words))
    if wb:
        raise ScenarioError("writeback beyond horizon")
    for c in cmds:
        if c["op"] == "WAVE":
            c["exp_word"] = hist[c["t"] + BANK_LATENCY][c["sl"]]
        elif c["op"] in ("FILL", "SPILL", "UNK"):
            c["exp_word"] = hist[c["t"]][c["sl"]]
    return {"sticky": sticky, "owner": list(owner), "words": list(words),
            "horizon": horizon}


# ---------------------------------------------------------------------------
# 시나리오 record 인코딩 / 파일 자기증명 (형식 계약: bank_scenarios_contract.md)
# ---------------------------------------------------------------------------


def bank_encode_scenario(idx, fam_code, cmds, final):
    body = []
    for c in cmds:
        assert c["t"] < (1 << 32)
        h = (_TAG_OP[c["op"]] << 56) | (c["st"] << 52) \
            | (c["sl"] << 48) | (int(c["refused"]) << 47) \
            | (int(c["vfault"]) << 46) | c["t"]
        if c["op"] == "UNK":
            assert c["rawop"] in (6, 7)     # 미정의 opcode 원형 (계약 §6)
            h |= c["rawop"] << 40
        body.append(h)
        if c["op"] == "WAVE":
            body.extend(field_encode(*a) for a in c["prods"])
            body.append(c["exp_word"])
        elif c["op"] == "FILL":
            body.append(c["word"])
            body.append(c["exp_word"])
        elif c["op"] == "DRAIN":
            body.append(((1 << 32) | c["fp32"]) if "fp32" in c else 0)
        elif c["op"] == "SPILL":
            body.append(c.get("spill", 0))  # 거부 = spill 방출 없음 (0)
            body.append(c["exp_word"])      # word 불변/잔존 스냅샷
        elif c["op"] == "UNK":
            body.append(c["exp_word"])      # 상태 무변경 스냅샷
    omap = 0
    for o in final["owner"]:
        omap = (omap << 8) | (BANK_NO_OWNER if o is None else o)
    n_rec = 1 + len(body) + 1 + BANK_NSLOTS
    assert idx < (1 << 16) and n_rec < (1 << 16) and len(cmds) < (1 << 8)
    begin = (_TAG_BEGIN << 56) | (idx << 40) | (fam_code << 32) \
        | (n_rec << 16) | (BANK_NSLOTS << 8) | len(cmds)
    end = (_TAG_END << 56) | (int(final["sticky"]) << 48) | (omap << 16)
    return [begin] + body + [end] + list(final["words"])


def bank_verify_file():
    """파일 재독 -> record 파싱 -> 명령 재구성 -> 실행기 재실행 -> 인코딩
    된 기대 필드 전부 재대조 (파일 자기증명 — verify_vector_file 동형)."""
    vals = []
    for ln in BANK_HEX_PATH.read_text().splitlines():
        if not ln or ln.startswith("//"):
            continue
        assert len(ln) == 16
        vals.append(int(ln, 16))
    i = n_scen = 0
    while i < len(vals):
        begin = vals[i]
        assert begin >> 56 == _TAG_BEGIN
        idx = (begin >> 40) & 0xFFFF
        n_rec = (begin >> 16) & 0xFFFF
        n_cmds = begin & 0xFF
        assert (begin >> 8) & 0xFF == BANK_NSLOTS
        recs = vals[i:i + n_rec]
        assert len(recs) == n_rec, idx
        j, cmds, enc = 1, [], []
        for _ in range(n_cmds):
            h = recs[j]
            j += 1
            op = _OP_FROM_TAG[h >> 56]
            c = _c(h & 0xFFFFFFFF, op, (h >> 52) & 0xF, (h >> 48) & 0xF)
            e = {"refused": bool((h >> 47) & 1),
                 "vfault": bool((h >> 46) & 1)}
            if op == "UNK":
                c["rawop"] = (h >> 40) & 0x7
                assert c["rawop"] in (6, 7), idx
            if op == "WAVE":
                c["prods"] = [field_decode(recs[j + k]) for k in range(GROUP)]
                j += GROUP
                e["exp_word"] = recs[j]
                j += 1
            elif op == "FILL":
                c["word"] = recs[j]
                e["exp_word"] = recs[j + 1]
                j += 2
            elif op == "DRAIN":
                e["drain"] = recs[j]
                j += 1
            elif op == "SPILL":
                e["spill"] = recs[j]
                e["exp_word"] = recs[j + 1]
                j += 2
            elif op == "UNK":
                e["exp_word"] = recs[j]
                j += 1
            cmds.append(c)
            enc.append(e)
        endr = recs[j]
        assert endr >> 56 == _TAG_END, idx
        exp_words = recs[j + 1:j + 1 + BANK_NSLOTS]
        final = bank_execute(cmds)      # 재실행 (기대는 인코딩과 독립 재산출)
        omap = 0
        for o in final["owner"]:
            omap = (omap << 8) | (BANK_NO_OWNER if o is None else o)
        assert final["sticky"] == bool((endr >> 48) & 1), idx
        assert omap == (endr >> 16) & 0xFFFFFFFF, idx
        assert final["words"] == exp_words, idx
        for c, e in zip(cmds, enc):
            assert c["refused"] == e["refused"], idx
            assert c["vfault"] == e["vfault"], idx
            if c["op"] in ("WAVE", "FILL", "SPILL", "UNK"):
                assert c["exp_word"] == e["exp_word"], idx
            if c["op"] == "SPILL":
                assert c.get("spill", 0) == e["spill"], idx
            elif c["op"] == "DRAIN":
                got = ((1 << 32) | c["fp32"]) if "fp32" in c else 0
                assert got == e["drain"], idx
        i += n_rec
        n_scen += 1
    return n_scen


# ---------------------------------------------------------------------------
# 시나리오 생성 — directed (경계 손계산 고정점 포함) + 랜덤 인터리브
# ---------------------------------------------------------------------------


def _prods_const(k=1):
    """1.0 곱 k개 + zero — 손계산 가능한 chain 값 (합 = k)."""
    return [me_to_addend(1 << 14, -14)] * k + [CANON_ZERO] * (GROUP - k)


def _rand_bank_prods(rng):
    prods = [CANON_ZERO] * GROUP
    for i in rng.sample(range(GROUP), rng.randint(1, 4)):
        prods[i] = rand_bf16_addend(rng, -20, 20)
    return prods


def _rand_good_word(rng):
    """FILL-valid 이고 lattice-표현 가능한 임의 bank word."""
    return wide_to_fp64(rng.randint(0, 1), rng.randint(-30, 30),
                        (1 << 47) | rng.getrandbits(47))


_BAD_FILL_WORDS = (0x7FF8000000000000,   # qNaN        — validation (i)
                   0x7FF0000000000001,   # sNaN        — validation (i)
                   0x7FF0000000000000,   # +Inf        — validation (i)
                   0xFFF0000000000000,   # -Inf        — validation (i)
                   0x3FF0000000000001,   # 1+2^-52     — validation (ii)
                   0x0000000000000001)   # 2^-1074     — validation (ii)


def gen_rand_bank_scenario(rng):
    """랜덤 인터리브 1개: 소유 준비 단계 (REQ/FILL) 후 wave 체이닝 경계
    (delta 4..9)/창 경계 FDZ (offset 1..9 straddle)/외래 접촉/불량 FILL 을
    섞은 본문. 형식 규율 (II, pend, (cycle,slot) 유일) 은 구성으로 보장."""
    cmds, t = [], 0
    last_wave = -BANK_II
    n_st = rng.randint(2, 3)
    slots = rng.sample(range(BANK_NSLOTS), rng.randint(2, 3))

    def emit(op, st_id, sl, adv, **kw):
        nonlocal t
        cmds.append(_c(t, op, st_id, sl, **kw))
        t += adv

    for sl in slots:                        # 소유 준비 단계
        st_id = rng.randrange(n_st)
        if rng.random() < 0.5:
            emit("REQ", st_id, sl, 2)
        else:
            emit("FILL", st_id, sl, rng.randint(1, 2),
                 word=_rand_good_word(rng))
    for _ in range(rng.randint(3, 7)):      # 인터리브 본문
        sl = rng.choice(slots)
        st_id = rng.randrange(n_st)
        r = rng.random()
        if r < 0.45:                        # wave (+ 경계 follow-up)
            t = max(t, last_wave + BANK_II)
            w_t = t
            emit("WAVE", st_id, sl, 1, prods=_rand_bank_prods(rng))
            last_wave = w_t
            f = rng.random()
            if f < 0.30:                    # 같은 slot 재start delta 4..9
                t = w_t + rng.choice((4, 5, 6, 7, 7, 8, 9))
                last_wave = t
                emit("WAVE", rng.randrange(n_st) if rng.random() < 0.3
                     else st_id, sl, rng.randint(1, 3),
                     prods=_rand_bank_prods(rng))
            elif f < 0.60:                  # 창 경계 FDZ straddle 1..9
                t = w_t + rng.choice((1, 3, 5, 7, 7, 8, 8, 9))
                op = rng.choice(("DRAIN", "ZERO", "FILL"))
                kw = {"word": _rand_good_word(rng)} if op == "FILL" else {}
                emit(op, st_id, sl, rng.randint(1, 3), **kw)
            else:
                t += rng.randint(1, 3)
        elif r < 0.60:
            emit("DRAIN", st_id, sl, rng.randint(1, 3))
        elif r < 0.70:
            emit("ZERO", st_id, sl, rng.randint(1, 3))
        elif r < 0.85:
            p = rng.random()
            if p < 0.15:                    # FILL validation fault 주입
                word = rng.choice(_BAD_FILL_WORDS)
            elif p < 0.28:                  # FILL-valid, lattice 밖 —
                word = wide_to_fp64(        # 후속 wave 의 (d)/(e) 후보
                    rng.randint(0, 1), rng.choice((300, -280)), 1 << 47)
            else:
                word = _rand_good_word(rng)
            emit("FILL", st_id, sl, rng.randint(1, 3), word=word)
            if 0.15 <= p < 0.28:            # lattice-밖 word 의 carry
                t = max(t, last_wave + BANK_II)     # 소비를 유도 (beat 0
                last_wave = t                       # fault (d)/(e) 경로)
                emit("WAVE", st_id, sl, rng.randint(1, 3),
                     prods=_rand_bank_prods(rng))
        else:
            emit("REQ", st_id, sl, 2)
    return cmds


# family 코드/의도 (계약 문서 §7 표의 원천 — 코드는 record BEGIN 의 [39:32])
BANK_FAM_DOCS = {
    "chain_boundary": (1, "같은 slot 체이닝 합법 경계 — delta 정확히 7 "
                          "그리고 8 (IF-3), 최종 drain 손계산 고정점"),
    "chain_violation": (2, "같은 slot 재start delta 4/5/6 — 창 내 접촉 "
                           "거부 + sticky, 거부된 wave 는 창을 열지도 "
                           "쓰지도 않음 (복구 chain 으로 증명)"),
    "gap_same_slot": (3, "gap-후 재시작 (같은 slot): delta = 7+gap, "
                         "gap 1/3/17 — back-to-back 밖 커버리지 폐쇄"),
    "gap_cross_slot": (4, "gap-후 재시작 (타 slot): delta = II+gap = "
                          "4+gap, gap 1/3/17 — II 중첩 합법성"),
    "window_touch_drain": (5, "DRAIN 창 접촉: offset 1/3/7 fault (7 = 창 "
                              "마지막 cycle), offset 8 합법 (직후)"),
    "window_touch_zero": (6, "ZERO 창 접촉: offset 1/3/7 fault, offset 8 "
                             "합법 + zero 후 carry=+0 재시작 (+④ append: "
                             "offset 4 — 교차곱 폐쇄)"),
    "window_touch_fill": (7, "FILL 창 접촉: offset 1/3/7 fault, drain 후 "
                             "재-FILL 합법 (acquire-by-fill) (+④ append: "
                             "offset 6 — 교차곱 폐쇄)"),
    "window_prelude": (8, "창 직전 접촉 합법 — commit/FILL/ZERO 가 wave "
                          "start 직전 cycle 에 완료"),
    "fill_validation": (9, "FILL validation (i)/(ii) — NaN/±Inf/정밀도 "
                           "초과/subnormal 하한 밖 -> sticky, 상태 무변경"),
    "fill_canonicalize": (10, "FILL validation (iii) — fp64 -0 수용 + "
                              "canonical +0 화, 후속 carry 는 +0"),
    "carry_fault_range": (11, "FILL-valid 2^300 -> carry 소비 (beat 0) "
                              "에서 fault (d), writeback 억제, 잔존 word "
                              "drain = +Inf"),
    "carry_fault_precision": (12, "FILL-valid 2^-280 -> carry 소비에서 "
                                  "fault (e), ZERO 복구 후 정상 chain"),
    "ownership_reject": (13, "RequestOwn 2-phase: 외래 live bank 에 "
                             "RejectOwn + sticky, incumbent 무접촉"),
    "ownership_foreign": (14, "외래 WAVE/DRAIN/ZERO 접촉 (창 밖) — "
                              "acc_owner/drain_owner/zero_owner 거부"),
    "ownership_fill_busy": (15, "외래 FILL 접촉 (live bank) — "
                                "fill_bankfree 거부 (FillFaultBusy)"),
    "ownership_sram_scrub": (16, "drain 후 SRAM 잔존 + 재-acquire 의 "
                                 "commit_zero scrub — stale 값 미주입 증명"),
    "ownership_fill_reacquire": (17, "drain release 후 타 stream 의 "
                                     "acquire-by-fill — TLA+ Fill 대응"),
    "rand_interleave": (18, "랜덤 인터리브 (고정 seed) — 전 명령/거부/"
                            "fault 클래스 혼합, coverage 하한은 report"),
    "spill_window": (19, "창 내 SPILL 거부 — offset 1/3/7 fault "
                         "(PROTO_GUARD), offset 8 수용 대조 병치; 거부는 "
                         "word 불변, 수용 spill 값 = 직전 writeback (+④ "
                         "append: offset 2/4/5/6 — 교차곱 폐쇄)"),
    "spill_owner": (20, "비-owner SPILL 거부 (외래 owner / 무소유) — "
                        "PROTO_GUARD, incumbent word/owner 완전 불변"),
    "spill_accept": (21, "수용 SPILL 대조 — spill 값 = slot word, "
                         "release + word 잔존, 재-acquire scrub 로 미유출"),
    "proto_unk": (22, "미정의 opcode 6/7 — PROTO_GUARD sticky, 상태 "
                      "무변경, 응답 없음 (loud-fault-never-silent)"),
}


def gen_bank_scenarios():
    """전 시나리오 생성 + 실행 + directed 손계산 고정점 assert.
    반환: [(fam_name, cmds, final)] (인코딩은 호출자)."""
    out = []

    def run(fam, cmds):
        final = bank_execute(cmds)
        out.append((fam, cmds, final))
        return cmds, final

    P1, P2 = _prods_const(1), _prods_const(2)
    W1 = wide_to_fp64(0, 0, 1 << 47)        # 1.0
    W4 = wide_to_fp64(0, 2, 1 << 47)        # 4.0
    F1, F2, F3, F5 = 0x3F800000, 0x40000000, 0x40400000, 0x40A00000
    PINF = 0x7F800000

    # ---- (i) 같은 slot 체이닝 — 합법 경계 delta 정확히 7 / 8 ----
    cmds, fin = run("chain_boundary", [
        _c(0, "REQ", 0, 0), _c(2, "WAVE", 0, 0, prods=P1),
        _c(9, "WAVE", 0, 0, prods=P1),      # delta 7 — IF-3 하한
        _c(17, "WAVE", 0, 0, prods=P1),     # delta 8
        _c(25, "DRAIN", 0, 0)])
    assert not fin["sticky"] and cmds[4]["fp32"] == F3      # 1+1+1 체인

    # ---- (i) 위반 경계 delta 4/5/6 — 거부 + sticky + 복구 체인 ----
    for d in (4, 5, 6):
        t3 = max(9, 2 + d + BANK_II)
        cmds, fin = run("chain_violation", [
            _c(0, "REQ", 0, 0), _c(2, "WAVE", 0, 0, prods=P1),
            _c(2 + d, "WAVE", 0, 0, prods=P1),     # 창 내 — 거부
            _c(t3, "WAVE", 0, 0, prods=P1),        # 복구 (carry = wave1)
            _c(t3 + 8, "DRAIN", 0, 0)])
        assert fin["sticky"] and cmds[2]["refused"]
        assert cmds[4]["fp32"] == F2      # 거부된 wave 는 쓰지 않았다

    # ---- (ii) gap-후 재시작 — 같은 slot (delta = 7+gap) ----
    for g in (1, 3, 17):
        cmds, fin = run("gap_same_slot", [
            _c(0, "REQ", 0, 0), _c(2, "WAVE", 0, 0, prods=P1),
            _c(2 + BANK_LATENCY + g, "WAVE", 0, 0, prods=P1),
            _c(2 + BANK_LATENCY + g + 8, "DRAIN", 0, 0)])
        assert not fin["sticky"] and cmds[3]["fp32"] == F2

    # ---- (ii) gap-후 재시작 — 타 slot (delta = II+gap) ----
    for g in (1, 3, 17):
        t1 = 4 + BANK_II + g
        cmds, fin = run("gap_cross_slot", [
            _c(0, "REQ", 0, 0), _c(2, "REQ", 0, 1),
            _c(4, "WAVE", 0, 0, prods=P1),
            _c(t1, "WAVE", 0, 1, prods=P2),
            _c(12, "DRAIN", 0, 0), _c(t1 + 8, "DRAIN", 0, 1)])
        assert not fin["sticky"]
        assert cmds[4]["fp32"] == F1 and cmds[5]["fp32"] == F2

    # ---- (iii) 창 접촉 — DRAIN: offset 1/3/7 fault, 8 합법 ----
    for off in (1, 3, 7):
        cmds, fin = run("window_touch_drain", [
            _c(0, "REQ", 0, 0), _c(2, "WAVE", 0, 0, prods=P1),
            _c(2 + off, "DRAIN", 0, 0),            # 창 내 — fault
            _c(10, "DRAIN", 0, 0)])                # 직후 (offset 8) 합법
        assert fin["sticky"] and cmds[2]["refused"]
        assert "fp32" not in cmds[2] and cmds[3]["fp32"] == F1
    cmds, fin = run("window_touch_drain", [
        _c(0, "REQ", 0, 0), _c(2, "WAVE", 0, 0, prods=P1),
        _c(10, "DRAIN", 0, 0)])                    # 합법 단독 (offset 8)
    assert not fin["sticky"] and cmds[2]["fp32"] == F1

    # ---- (iii) 창 접촉 — ZERO ----
    for off in (1, 3, 7):
        cmds, fin = run("window_touch_zero", [
            _c(0, "REQ", 0, 0), _c(2, "WAVE", 0, 0, prods=P1),
            _c(2 + off, "ZERO", 0, 0),             # 창 내 — fault
            _c(10, "ZERO", 0, 0),                  # 직후 합법 -> +0
            _c(12, "WAVE", 0, 0, prods=P1),        # carry = +0
            _c(20, "DRAIN", 0, 0)])
        assert fin["sticky"] and cmds[2]["refused"]
        assert cmds[5]["fp32"] == F1               # zero 가 실제로 지웠다
    cmds, fin = run("window_touch_zero", [
        _c(0, "REQ", 0, 0), _c(2, "WAVE", 0, 0, prods=P1),
        _c(10, "ZERO", 0, 0), _c(14, "WAVE", 0, 0, prods=P1),
        _c(22, "DRAIN", 0, 0)])
    assert not fin["sticky"] and cmds[4]["fp32"] == F1

    # ---- (iii) 창 접촉 — FILL (합법 재-FILL 은 drain 후) ----
    for off in (1, 3, 7):
        cmds, fin = run("window_touch_fill", [
            _c(0, "FILL", 0, 0, word=W1),          # acquire-by-fill, 1.0
            _c(2, "WAVE", 0, 0, prods=P1),         # carry 1 -> 2.0
            _c(2 + off, "FILL", 0, 0, word=W4),    # 창 내 — fault
            _c(10, "DRAIN", 0, 0),                 # 2.0, release
            _c(11, "FILL", 1, 0, word=W4),         # 합법 재-FILL (4.0)
            _c(13, "WAVE", 1, 0, prods=P1),        # carry 4 -> 5.0
            _c(21, "DRAIN", 1, 0)])
        assert fin["sticky"] and cmds[2]["refused"]
        assert cmds[3]["fp32"] == F2 and cmds[6]["fp32"] == F5
    cmds, fin = run("window_touch_fill", [
        _c(0, "FILL", 0, 0, word=W1), _c(2, "WAVE", 0, 0, prods=P1),
        _c(10, "DRAIN", 0, 0), _c(11, "FILL", 0, 0, word=W4),
        _c(12, "DRAIN", 0, 0)])
    assert not fin["sticky"]
    assert cmds[2]["fp32"] == F2 and cmds[4]["fp32"] == 0x40800000  # 4.0

    # ---- (iii) 창 직전 접촉 합법 ----
    cmds, fin = run("window_prelude", [
        _c(0, "REQ", 0, 0), _c(1, "ZERO", 0, 0),   # commit 과 같은 cycle,
        _c(2, "WAVE", 0, 0, prods=P1),             # 창 직전 — 합법
        _c(10, "DRAIN", 0, 0)])
    assert not fin["sticky"] and cmds[3]["fp32"] == F1
    cmds, fin = run("window_prelude", [
        _c(0, "FILL", 0, 0, word=W1),              # start 직전 cycle FILL
        _c(1, "WAVE", 0, 0, prods=P1),             # carry 1 -> 2.0
        _c(9, "DRAIN", 0, 0)])
    assert not fin["sticky"] and cmds[2]["fp32"] == F2

    # ---- FILL validation (i)/(ii) — 전 불량 word, 상태 무변경 ----
    bad = list(_BAD_FILL_WORDS)
    cmds, fin = run("fill_validation",
                    [_c(i, "FILL", 0, 0, word=w) for i, w in enumerate(bad)]
                    + [_c(6, "FILL", 0, 0, word=W1),
                       _c(8, "WAVE", 0, 0, prods=P1),
                       _c(16, "DRAIN", 0, 0)])
    assert fin["sticky"]
    assert all(c["vfault"] for c in cmds[:6])
    assert cmds[8]["fp32"] == F2       # 불량 FILL 후에도 정상 경로 무손상

    # ---- FILL validation (iii) — -0 canonicalize ----
    cmds, fin = run("fill_canonicalize", [
        _c(0, "FILL", 0, 0, word=0x8000000000000000),
        _c(2, "WAVE", 0, 0, prods=P1), _c(10, "DRAIN", 0, 0)])
    assert not fin["sticky"]
    assert cmds[0]["exp_word"] == 0    # -0 -> canonical +0 (fp64 +0)
    assert cmds[2]["fp32"] == F1       # carry 는 +0 이었다

    # ---- carry-lane fault (d)/(e) — pin 3 (발화 = carry 소비 beat 0) ----
    w_big = wide_to_fp64(0, 300, 1 << 47)          # FILL-valid, |v|=2^300
    cmds, fin = run("carry_fault_range", [
        _c(0, "FILL", 0, 0, word=w_big),
        _c(2, "WAVE", 0, 0, prods=P1),             # fault (d), no wb
        _c(10, "DRAIN", 0, 0)])                    # 잔존 word -> +Inf
    assert fin["sticky"] and cmds[1]["vfault"]
    assert cmds[1]["exp_word"] == w_big            # writeback 억제 증명
    assert cmds[2]["fp32"] == PINF
    w_bigneg = wide_to_fp64(1, 300, 1 << 47)       # FILL-valid, -2^300
    cmds, fin = run("carry_fault_range", [
        _c(0, "FILL", 0, 1, word=w_bigneg),
        _c(2, "WAVE", 0, 1, prods=P1),             # fault (d) — 음수판
        _c(10, "DRAIN", 0, 1)])
    assert fin["sticky"] and cmds[1]["why"] == "carry_range_d"
    assert cmds[2]["fp32"] == 0xFF800000           # 잔존 word -> -Inf
    w_tiny = wide_to_fp64(0, -280, 1 << 47)        # FILL-valid, 2^-280
    cmds, fin = run("carry_fault_precision", [
        _c(0, "FILL", 0, 0, word=w_tiny),
        _c(2, "WAVE", 0, 0, prods=P1),             # fault (e), no wb
        _c(10, "ZERO", 0, 0),                      # 복구 (owner 유지)
        _c(12, "WAVE", 0, 0, prods=P1),            # carry +0 -> 1.0
        _c(20, "DRAIN", 0, 0)])
    assert fin["sticky"] and cmds[1]["vfault"]
    assert cmds[1]["why"] == "carry_precision_e"
    assert cmds[4]["fp32"] == F1
    w_tinyneg = wide_to_fp64(1, -300, 1 << 47)     # FILL-valid, -2^-300
    cmds, fin = run("carry_fault_precision", [
        _c(0, "FILL", 0, 1, word=w_tinyneg),
        _c(2, "WAVE", 0, 1, prods=P1),             # fault (e) — 음수판
        _c(10, "DRAIN", 0, 1)])
    assert fin["sticky"] and cmds[1]["why"] == "carry_precision_e"
    assert cmds[2]["fp32"] == 0x80000000           # 잔존 word FTZ -> -0

    # ---- ownership — RejectOwn / 외래 접촉 / FillFaultBusy ----
    cmds, fin = run("ownership_reject", [
        _c(0, "REQ", 0, 0), _c(2, "REQ", 1, 0),    # commit@3 -> Reject
        _c(4, "WAVE", 0, 0, prods=P1), _c(12, "DRAIN", 0, 0)])
    assert fin["sticky"] and cmds[1]["refused"]
    assert cmds[3]["fp32"] == F1                   # incumbent 무접촉
    cmds, fin = run("ownership_foreign", [
        _c(0, "REQ", 0, 0), _c(2, "WAVE", 0, 0, prods=P1),
        _c(12, "WAVE", 1, 0, prods=P1),            # 창 밖 — 순수 acc_owner
        _c(16, "DRAIN", 1, 0), _c(17, "ZERO", 1, 0),
        _c(20, "WAVE", 0, 0, prods=P1), _c(28, "DRAIN", 0, 0)])
    assert fin["sticky"]
    assert [c["why"] for c in cmds[2:5]] == \
        ["acc_owner", "drain_owner", "zero_owner"]
    assert cmds[6]["fp32"] == F2                   # 외래 접촉 전부 무효과
    cmds, fin = run("ownership_fill_busy", [
        _c(0, "REQ", 0, 0), _c(2, "FILL", 1, 0, word=W1),
        _c(4, "WAVE", 0, 0, prods=P1), _c(12, "DRAIN", 0, 0)])
    assert fin["sticky"] and cmds[1]["why"] == "fill_busy"
    assert cmds[3]["fp32"] == F1

    # ---- ownership — SRAM 잔존 + commit_zero scrub / fill 재-acquire ----
    cmds, fin = run("ownership_sram_scrub", [
        _c(0, "REQ", 0, 0), _c(2, "WAVE", 0, 0, prods=P2),
        _c(10, "DRAIN", 0, 0),                     # 2.0, word 잔존
        _c(11, "REQ", 1, 0),                       # commit@12 zero scrub
        _c(13, "WAVE", 1, 0, prods=P1),            # carry +0 (stale 아님)
        _c(21, "DRAIN", 1, 0)])
    assert not fin["sticky"]
    assert cmds[2]["fp32"] == F2 and cmds[5]["fp32"] == F1
    cmds, fin = run("ownership_fill_reacquire", [
        _c(0, "REQ", 0, 0), _c(2, "WAVE", 0, 0, prods=P1),
        _c(10, "DRAIN", 0, 0),
        _c(11, "FILL", 1, 0, word=W4),             # free -> acquire (4.0)
        _c(13, "WAVE", 1, 0, prods=P1),            # carry 4 -> 5.0
        _c(21, "DRAIN", 1, 0)])
    assert not fin["sticky"] and cmds[5]["fp32"] == F5

    # ---- SPILL guard — 창 내 거부 + 수용 대조 병치 (2026-08-16 적대
    #      재실측 폐쇄: RTL spill_ref 절단이 TB 를 escape 했던 블라인드
    #      스팟 — 거부-SPILL 시나리오 전무가 원인) ----
    W2 = wide_to_fp64(0, 1, 1 << 47)               # 2.0
    for off in (1, 3, 7):
        cmds, fin = run("spill_window", [
            _c(0, "FILL", 0, 0, word=W1),          # acquire-by-fill, 1.0
            _c(2, "WAVE", 0, 0, prods=P1),         # carry 1 -> 2.0 (wb@9)
            _c(2 + off, "SPILL", 0, 0),            # 창 내 — 거부 + sticky
            _c(10, "SPILL", 0, 0),                 # 직후 (offset 8) 수용
            _c(11, "FILL", 1, 0, word=W4),         # release 증명 (재-acquire)
            _c(13, "WAVE", 1, 0, prods=P1),        # carry 4 -> 5.0
            _c(21, "DRAIN", 1, 0)])
        assert fin["sticky"] and cmds[2]["refused"]
        assert cmds[2]["why"] == "window_spill"
        assert "spill" not in cmds[2]              # 거부 = spill 방출 없음
        # 거부 SPILL 은 word 불변 (off<7: wb 전 1.0 / off=7: wb 선행 2.0)
        assert cmds[2]["exp_word"] == (W2 if off == 7 else W1)
        assert cmds[3]["spill"] == W2              # 수용 spill = wave1 결과
        assert cmds[3]["exp_word"] == W2           # release 후에도 word 잔존
        assert cmds[6]["fp32"] == F5               # 재-acquire 체인 무손상

    # ---- SPILL guard — 비-owner 거부 (외래 owner / 무소유) ----
    cmds, fin = run("spill_owner", [
        _c(0, "FILL", 0, 0, word=W1),              # owner 0, word 1.0
        _c(1, "SPILL", 1, 0),                      # 외래 stream — 거부
        _c(2, "WAVE", 0, 0, prods=P1),             # incumbent 무손상
        _c(10, "DRAIN", 0, 0)])
    assert fin["sticky"] and cmds[1]["why"] == "spill_owner"
    assert cmds[1]["exp_word"] == W1 and "spill" not in cmds[1]
    assert cmds[3]["fp32"] == F2                   # word/owner 완전 불변
    cmds, fin = run("spill_owner", [
        _c(0, "SPILL", 0, 1),                      # 무소유 slot — 거부
        _c(2, "FILL", 0, 1, word=W1),              # 이후 정상 acquire 가능
        _c(4, "WAVE", 0, 1, prods=P1),
        _c(12, "DRAIN", 0, 1)])
    assert fin["sticky"] and cmds[0]["why"] == "spill_owner"
    assert cmds[0]["exp_word"] == 0                # power-on +0 불변
    assert cmds[3]["fp32"] == F2

    # ---- SPILL 수용 대조 단독 — release + word 잔존 + scrub 미유출 ----
    cmds, fin = run("spill_accept", [
        _c(0, "FILL", 0, 0, word=W4),              # 4.0
        _c(1, "SPILL", 0, 0),                      # 수용 — 유일한 합법 유출
        _c(2, "REQ", 1, 0),                        # 재-acquire (commit@3)
        _c(4, "WAVE", 1, 0, prods=P1),             # carry +0 -> 1.0
        _c(12, "DRAIN", 1, 0)])
    assert not fin["sticky"]
    assert cmds[1]["spill"] == W4 and cmds[1]["exp_word"] == W4
    assert cmds[4]["fp32"] == F1                   # scrub — 잔존값 미유출

    # ---- 미정의 opcode 6/7 — PROTO_GUARD sticky, 상태 무변경 ----
    cmds, fin = run("proto_unk", [
        _c(0, "FILL", 0, 0, word=W1),
        _c(1, "UNK", 1, 0, rawop=6),               # opcode 6 — sticky
        _c(2, "UNK", 0, 1, rawop=7),               # opcode 7, 무소유 slot
        _c(3, "WAVE", 0, 0, prods=P1),             # 정상 경로 무손상
        _c(11, "DRAIN", 0, 0)])
    assert fin["sticky"]
    assert cmds[1]["why"] == "proto_unk" and cmds[2]["why"] == "proto_unk"
    assert cmds[1]["exp_word"] == W1 and cmds[2]["exp_word"] == 0
    assert cmds[4]["fp32"] == F2                   # UNK 는 상태 무변경
    assert fin["owner"][1] is None                 # UNK 는 acquire 아님
    cmds, fin = run("proto_unk", [
        _c(0, "UNK", 0, 0, rawop=7),               # power-on 직후 단독 UNK
        _c(2, "REQ", 0, 0),
        _c(4, "WAVE", 0, 0, prods=P1),
        _c(12, "DRAIN", 0, 0)])
    assert fin["sticky"] and cmds[0]["refused"]
    assert cmds[0]["exp_word"] == 0
    assert cmds[3]["fp32"] == F1

    # ---- (iv) 랜덤 인터리브 300 (고정 seed) ----
    rng = random.Random(SEEDS["bank_rand_interleave"])
    for _ in range(300):
        run("rand_interleave", gen_rand_bank_scenario(rng))

    # ---- ④ 이월 (ii) 교차곱 폐쇄 directed (GATE V20-3 검증 의무 1(ii),
    #      2026-08-17): window_fill offset 6 / window_zero offset 4 /
    #      window_spill offset {2,4,5,6} — 3 클래스 x offset 1..7 전수
    #      완성 (bank_window_crossproduct 가 전수를 assert). 기존 343
    #      시나리오 record 스트림의 byte-identity 를 지키기 위해 **뒤에
    #      append** 한다 (family 는 기존 코드 재사용 — 배치 위치만 뒤). ----
    for off in (6,):                        # window_touch_fill 과 동일 구조
        cmds, fin = run("window_touch_fill", [
            _c(0, "FILL", 0, 0, word=W1),
            _c(2, "WAVE", 0, 0, prods=P1),
            _c(2 + off, "FILL", 0, 0, word=W4),    # 창 내 offset 6 — fault
            _c(10, "DRAIN", 0, 0),
            _c(11, "FILL", 1, 0, word=W4),
            _c(13, "WAVE", 1, 0, prods=P1),
            _c(21, "DRAIN", 1, 0)])
        assert fin["sticky"] and cmds[2]["refused"]
        assert cmds[2]["why"] == "window_fill" and cmds[2]["off"] == off
        assert cmds[3]["fp32"] == F2 and cmds[6]["fp32"] == F5
    for off in (4,):                        # window_touch_zero 와 동일 구조
        cmds, fin = run("window_touch_zero", [
            _c(0, "REQ", 0, 0), _c(2, "WAVE", 0, 0, prods=P1),
            _c(2 + off, "ZERO", 0, 0),             # 창 내 offset 4 — fault
            _c(10, "ZERO", 0, 0),
            _c(12, "WAVE", 0, 0, prods=P1),
            _c(20, "DRAIN", 0, 0)])
        assert fin["sticky"] and cmds[2]["refused"]
        assert cmds[2]["why"] == "window_zero" and cmds[2]["off"] == off
        assert cmds[5]["fp32"] == F1
    for off in (2, 4, 5, 6):                # spill_window 와 동일 구조
        cmds, fin = run("spill_window", [
            _c(0, "FILL", 0, 0, word=W1),
            _c(2, "WAVE", 0, 0, prods=P1),
            _c(2 + off, "SPILL", 0, 0),            # 창 내 — 거부 + sticky
            _c(10, "SPILL", 0, 0),                 # 직후 (offset 8) 수용
            _c(11, "FILL", 1, 0, word=W4),
            _c(13, "WAVE", 1, 0, prods=P1),
            _c(21, "DRAIN", 1, 0)])
        assert fin["sticky"] and cmds[2]["refused"]
        assert cmds[2]["why"] == "window_spill" and cmds[2]["off"] == off
        assert "spill" not in cmds[2]
        assert cmds[2]["exp_word"] == W1           # off < 7: wb 이전 — 1.0
        assert cmds[3]["spill"] == W2 and cmds[3]["exp_word"] == W2
        assert cmds[6]["fp32"] == F5

    return out


def bank_window_crossproduct(scens):
    """④ 이월 (ii) 의 전수 판정: 창-거부 클래스별 offset 집합을 집계하고
    FILL/DRAIN/ZERO/SPILL x offset 1..7 전수 + chain 4..6 전수를 assert
    한다 (좁음이 seed 이동으로 조용히 재발하는 것을 막는 가드)."""
    xp = {k: set() for k in ("window_fill", "window_drain", "window_zero",
                             "window_spill", "window_chain")}
    for _, cmds, _ in scens:
        for c in cmds:
            if c.get("why") in xp:
                xp[c["why"]].add(c["off"])
    full = set(range(1, BANK_LATENCY + 1))          # 1..7
    for k in ("window_fill", "window_drain", "window_zero", "window_spill"):
        assert xp[k] == full, (k, sorted(xp[k]))
    # chain 거부는 구성상 II<=delta<LATENCY 만 도달 가능 (delta<II 는
    # 생성기 형식 규율 위반, >=LATENCY 는 합법)
    assert xp["window_chain"] == set(range(BANK_II, BANK_LATENCY)), \
        sorted(xp["window_chain"])
    return {k: sorted(v) for k, v in xp.items()}


def bank_coverage(scens):
    """전 시나리오의 수용/거부/fault 클래스 집계 + 하한 assert (거부·경계
    커버리지가 seed 이동으로 조용히 사라지는 것을 막는 non-vacuity 가드)."""
    cov = {k: 0 for k in
           ("wave_ok", "chain_delta7", "chain_delta8", "fdz_after_window",
            "drain_ok", "zero_ok", "fill_ok", "spill_ok", "window_chain",
            "acc_owner", "window_fill", "window_drain", "window_zero",
            "window_spill", "fill_busy", "drain_owner", "zero_owner",
            "spill_owner", "reject_own", "fill_validation",
            "carry_range_d", "carry_precision_e", "proto_unk")}
    for _, cmds, _ in scens:
        last_acc = {}
        for c in sorted(cmds, key=lambda c: c["t"]):
            if c.get("why"):
                cov[c["why"]] += 1
            ok = not c["refused"] and not c["vfault"]
            sl = c["sl"]
            if c["op"] == "WAVE" and ok:
                cov["wave_ok"] += 1
                if sl in last_acc:
                    d = c["t"] - last_acc[sl]
                    if d == BANK_LATENCY:
                        cov["chain_delta7"] += 1
                    elif d == BANK_LATENCY + 1:
                        cov["chain_delta8"] += 1
                last_acc[sl] = c["t"]
            elif c["op"] in ("DRAIN", "ZERO", "FILL", "SPILL") and ok:
                cov[{"DRAIN": "drain_ok", "ZERO": "zero_ok",
                     "FILL": "fill_ok", "SPILL": "spill_ok"}[c["op"]]] += 1
                if sl in last_acc \
                        and c["t"] - last_acc[sl] == BANK_LATENCY + 1:
                    cov["fdz_after_window"] += 1
    for k, v in cov.items():
        assert v >= 2, "coverage class '%s' vacuous (%d)" % (k, v)
    return cov


def write_bank_file(scens):
    """시나리오 스트림 -> bank_scenarios.hex. 반환: (n_records, fam_table)
    — fam_table = [(name, code, n_scen, n_records)] (계약/report 공용)."""
    lines, fam_stat = [], {}
    for idx, (fam, cmds, final) in enumerate(scens):
        recs = bank_encode_scenario(idx, BANK_FAM_DOCS[fam][0], cmds, final)
        lines.extend("%016x" % r for r in recs)
        n_s, n_r = fam_stat.get(fam, (0, 0))
        fam_stat[fam] = (n_s + 1, n_r + len(recs))
    fam_table = [(f, BANK_FAM_DOCS[f][0]) + fam_stat[f] for f in fam_stat]
    hdr = [
        "// bank_scenarios.hex — wide ACC bank 상태기계 시나리오 스트림 "
        "(결정적, 고정 seed)",
        "// 생성기: scripts/golden_lattice.py — record 형식/의미 계약: "
        "include/generated/bank_scenarios_contract.md",
        "// 1 line = 1 record = 16 hex chars = 64 bits; N_SCENARIOS = %d; "
        "N_RECORDS = %d" % (len(scens), len(lines)),
    ]
    BANK_HEX_PATH.write_text("\n".join(hdr + lines) + "\n")
    return len(lines), fam_table


def bank_contract_text(n_scen, n_rec, fam_table, cov, xprod):
    fam_rows = "\n".join(
        "| `%s` | %d | %d | %d | %s |"
        % (f, code, ns, nr, BANK_FAM_DOCS[f][1].replace("\n", " "))
        for f, code, ns, nr in fam_table)
    cov_rows = "\n".join("| `%s` | %d |" % kv for kv in cov.items())
    xp_rows = "\n".join("| `%s` | %s |" % (k, ", ".join(map(str, v)))
                        for k, v in xprod.items())
    return """<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor \
contributors -->
<!-- GENERATED by scripts/golden_lattice.py — 손편집 금지. 재생성은 \
`python3 scripts/golden_lattice.py` (byte-identical). -->

# bank_scenarios.hex — wide ACC bank 상태기계 시나리오 계약 (하류 ③ golden)

- **규범 출처**: `.claude-memos/wt64v1_spec.md` §27.2.2 [하류 ③ COMMIT]
  블록 — 인터페이스 계약 **IF-1** (read-before-dispatch — carry read 는
  start cycle 이전 완료, beat 0 공급), **IF-2** (ownership window =
  start..writeback, LATENCY=%d; 창 내 FILL/DRAIN/ZERO 접촉 = loud sticky
  fault), **IF-3** (같은 slot 체이닝 >= %d, 타 slot II=%d 중첩), **IF-4**
  (0x7E = canonical zero 기록) + pin 3 (lattice-비표현 carry = fault
  (d)/(e) 의 carry-lane 적용, 발화 = carry 소비 beat 0); §27.2.1
  amendment pin 1 (수용 개구간 (-2^261, 2^261)) / pin 2 (carry-in
  normalized 전제); `proofs/tla/AccBank.tla` guard 군.
- **golden**: `scripts/golden_lattice.py` 의 `bank_execute` (상태기계
  reference 실행기 — 본 문서의 생성기이자 모든 기대값의 산출자). 산술
  기대값 (wave/drain) 은 lattice golden 경로 그대로 (Fraction 이중 검증
  포함 — `check_wave_against_fraction`).
- **소비자**: §27.6 하류 ③ 검증 계획 **(b) lattice-bank 통합 TB** / **(c)
  golden 확장**. 계획 **(a)** (TLA+ TLC 반례 trace 의 directed 변환) 는
  본 파일 밖 — `fill_owner`/FillFaultForeign (외래 spill image 주소) 는
  spill slot 모델을 요구하므로 **본 시나리오 레벨이 다루지 않는다** (정직
  기록; (a) 계열이 담당).

## 1. 모델 — slot / stream / 상태

- **slot**: 물리 bank word 주소 %d개 (0..%d) — TB 가 실제 bank x lane
  좌표로 사상한다 (사상은 TB 의 자유; 시나리오는 slot 간 독립성만 전제).
- **stream**: 논리 소유 주체 (AccBank.tla 의 `Streams` — 80-bit tag
  정체성의 대역). 4-bit 인코딩 (0..15), owner map 의 `0xFF` = 무소유.
- **slot 상태**: `word` (fp64 인코딩 bank word — §27.2.2 word 포맷),
  `owner` (stream 또는 무소유), lattice ownership window (아래 §4).
- **power-on 정의 (reference pin)**: 전 slot word = canonical +0, 전
  slot 무소유. TB 는 초기화 시퀀스로 이 상태에 정렬한 뒤 스트림을 적용
  한다.
- **sticky fault**: 시나리오 스코프의 단일 sticky bit — 어떤 거부/검증
  fault 도 이것을 세우고, 시나리오 안에서 절대 해제되지 않는다 (합성
  가능한 sticky status 클래스 — v1.9 `bank_tag_collision_error` 등급,
  §26.5 선례; TLA+ `conflict` 대응).

## 2. 명령 (cycle-태그) 와 형식 규율

| 명령 | 의미 | AccBank.tla 대응 |
|---|---|---|
| `REQ(t, st, sl)` | 2-phase acquire: t 에 등록 (pend), **t+1 에 commit 또는 reject** | RequestOwn -> CommitOwn / RejectOwn |
| `WAVE(t, st, sl, prods[32])` | wave-step start: carry = slot word (IF-1, beat 0 소비), writeback t+%d | Accumulate / AccumulateFault |
| `FILL(t, st, sl, word)` | fp64 word ingest (§27.2.2 FILL validation (i)-(iii)) | Fill / FillFaultBusy |
| `DRAIN(t, st, sl)` | PACK_FINAL RNE-24 + flush-after-round FTZ (§27.2.3), **ownership release** | Drain / DrainFault |
| `ZERO(t, st, sl)` | raw 0x7E — canonical zero 기록 (IF-4), owner 불변 | Zero / ZeroFault |
| `SPILL(t, st, sl)` | slot word 를 spill 스트림으로 (image 8-fragment 확폭은 상위 frag FSM 몫 — §27.2.2 SPILL), **ownership release**, word 잔존; 위반 (창 내/비-owner) = 거부 + sticky (**PROTO_GUARD**) | fault 6종 밖 — loud 법칙 (FP_AccBank.v [12]) |
| `UNK(t, st, sl, rawop∈{6,7})` | 미정의 opcode — sticky (**PROTO_GUARD**, 방어적 decode) 만; 상태 무변경, **응답 없음** (resp 무발행) | — (방어적) |

**형식 규율 (시나리오 구성 제약 — 위반은 fault 가 아니라 생성기 오류)**:
같은 (cycle, slot) 에 명령 2개 금지 (같은 cycle 두 port 의 같은 slot
중재는 ③ RTL COMMIT 몫 — 본 레벨 밖); WAVE start 는 전 slot 통틀어
간격 >= II=%d (lattice unit 이 1개 — 상위 dispatch 스케줄 책임, RTL 은
beat 중 start 무시); pend register 는 1개 (REQ 는 commit 전 재발행 금지
— v1.9 `mu_pending_other` 선례).

## 3. cycle 처리 순서 (실행기 정의 — TB 판정의 기준 시각)

cycle t 에서: **(1) writeback** (t == 이전 wave start + %d 인 wave 의
bank word 기록) -> **(2) acquire commit** (t-1 의 REQ 판정: slot 무소유
면 CommitOwn — owner 기록 + **word 를 canonical zero 로 scrub**
(`commit_zero`, acquire 융합 zero — SRAM 잔존값이 새 소유자에게 새지
않는 유일한 방벽); 소유 중이면 RejectOwn + sticky) -> **(3) 그 cycle 의
명령** (slot 오름차순). 따라서 **delta=%d 체이닝에서 다음 wave 의 carry
는 직전 wave 의 writeback 값이다** (read-before-dispatch 는 bank 구현
의무 — IF-1).

## 4. 검사 우선순위와 window 산술 (cycle-정밀)

명령별 검사 순서: **window (IF-2/IF-3) -> ownership guard -> 값 검증**.
모든 거부/fault = sticky + 상태 무변경 (silent 수용 금지).

- 수용된 wave (start t0) 의 **FILL/DRAIN/ZERO/SPILL fault 창 = [t0,
  t0+%d]** (양끝 포함 — **창 마지막 cycle (= writeback cycle) 접촉도
  fault, 그 직후 cycle (t0+%d) 접촉은 합법**).
- **같은 slot 다음 WAVE**: start 간격 >= LATENCY=%d 합법 (정확히 %d 부터
  — 그 cycle 에 writeback 이 선행하므로 carry 는 새 값), 4..6 은 거부 +
  sticky. **거부된 wave 는 창을 열지 않고 아무것도 쓰지 않는다.**
- ownership guard (창 밖에서만 도달): WAVE `acc_owner` / DRAIN
  `drain_owner` / ZERO `zero_owner` / SPILL `spill_owner` — owner ==
  stream 요구 (SPILL 위반의 RTL sticky 원인은 PROTO_GUARD); FILL
  `fill_bankfree` — **무소유 slot 에만** (수용 시 acquire-by-fill: owner
  := stream; 소유 중 slot 은 자기/외래 불문 거부 — FillFaultBusy); REQ
  commit `commit_free`. 미정의 opcode (`UNK` 6/7) 는 무조건 sticky
  (PROTO_GUARD) — 상태 무변경, 응답 무발행.
- 값 검증: FILL validation (i) NaN/Inf (ii) PACK_WIDE-비표현 -> sticky
  + **acquire 도 하지 않음** (iii) ±0 수용 + canonical +0 화; WAVE carry
  소비 (beat 0) 의 lattice 수용성 — 범위 밖 fault (d), 정밀도 위반
  fault (e) (§27.2.2 pin 3; golden `LatticeFault` 2종 대응).

## 5. reference pin (본 golden 이 확정하는 관측 계약 — ③ RTL 구현 의무)

1. **carry-lane fault (d)/(e) 의 wave 는 writeback 을 억제한다** — slot
   word 는 보존되고 (silent 오염 금지), fault 는 sticky. 창은 그대로
   점유된다 (unit 은 LATENCY 동안 그 slot 소유).
2. DRAIN 은 release 하되 word 를 **지우지 않는다** (SRAM 잔존 — TLA+
   SRAM semantics). 잔존값의 유일한 방벽은 acquire 시 zero (§3) 다.
3. ZERO 는 owner 를 바꾸지 않는다 (raw 0x7E — ownership-checked).
4. 거부/검증-fault 는 어떤 것도 상태를 바꾸지 않는다 (sticky 만).
5. SPILL 도 DRAIN 과 같은 release + word 잔존이다 — 수용 spill 값은
   그 cycle 의 유효 slot word (같은 cycle writeback/commit 선행 후).
   **거부-SPILL (창 내/비-owner) 와 미정의 opcode 는 PROTO_GUARD
   sticky** — 거부-SPILL 은 spill 방출도 상태 변경도 없다 (2026-08-16
   적대 재실측 폐쇄: 이 두 경로의 TB 시나리오 부재가 spill_ref/cmd_unk
   변이 절단의 escape 원인이었다).

## 6. record 형식 (1 line = 1 record = 64 bit) + TB 판정 규칙

시나리오 = `BEGIN` + 명령 record 열 (+ 인라인 데이터/기대) + `END` +
slot 기대 word %d개. record 태그 = `[63:56]`:

| record | 레이아웃 |
|---|---|
| `BEGIN` (0x01) | `[55:40]` 시나리오 index, `[39:32]` family 코드, `[31:16]` 이 시나리오의 총 record 수 (BEGIN/END/기대 포함), `[15:8]` N_SLOTS, `[7:0]` 명령 수 |
| 명령 (0x10 REQ / 0x11 WAVE / 0x12 FILL / 0x13 DRAIN / 0x14 ZERO / 0x15 SPILL / 0x16 UNK) | `[55:52]` stream, `[51:48]` slot, `[47]` **기대 refused** (거부 + sticky; REQ 는 t+1 reject; UNK 는 항상 1), `[46]` **기대 값-검증 fault** (FILL validation / carry (d)/(e)), `[42:40]` **UNK 만: 원 opcode (6/7)** — TB 는 이 값을 그대로 인가, `[31:0]` cycle t |
| WAVE 후속 | addend record x32 (`lattice_vec_contract.md` §2 의 64-bit wide field) + **기대 slot word 1개 — cycle t+%d 말 스냅샷** |
| FILL 후속 | fill word 1개 (fp64 raw) + **기대 slot word 1개 — cycle t 말 스냅샷** |
| DRAIN 후속 | 기대 1개: `[32]` = 수용, `[31:0]` = 기대 fp32 (거부 시 record == 0) |
| SPILL 후속 | 기대 spill word 1개 (fp64 raw — 수용 시 `spill_q`; 거부 시 0, `spill_v` 무발행) + **기대 slot word 1개 — cycle t 말 스냅샷** (거부 = word 불변 / 수용 = release 후 word 잔존의 직접 판정) |
| UNK 후속 | **기대 slot word 1개 — cycle t 말 스냅샷** (상태 무변경 판정; 응답은 무발행 — TB 는 t+1 에 resp_v==0 도 판정) |
| `END` (0x0F) | `[48]` 기대 sticky, `[47:16]` 기대 최종 owner map (slot0 `[47:40]` .. slot3 `[23:16]`; 0xFF = 무소유) |
| 최종 기대 | slot word x%d (horizon 말 — 마지막 명령 cycle + %d + 2) |

**판정**: 명령별 refused/vfault 플래그, WAVE/FILL 스냅샷 word, DRAIN
fp32, 최종 sticky/owner/word 전부 **bit-exact**. 하나라도 불일치 = FAIL
(표본률 논증 금지). 스냅샷 시각은 §3 의 처리 순서 기준 — 같은 cycle 의
writeback/commit 이 명령보다 선행한 뒤의 값이다.

## 7. family 배치

| family | 코드 | 시나리오 | records | 의도 |
|---|---|---|---|---|
%s

총 **%d 시나리오, %d records** (주석 3줄 제외). directed family 는 전부
실행기 산출과 별개의 손계산 고정점 assert 를 통과했다 (생성기 내
`gen_bank_scenarios`).

## 8. coverage (non-vacuity — 생성기가 하한 assert)

| class | count |
|---|---|
%s

## 9. 결정론

고정 seed `bank_rand_interleave = 0x%X` 외 난수원/timestamp 없음 —
재실행 byte-identical (blake2b512 은 `lattice_golden_report.json`).

## 10. ④ GATE V20-3 이월 기록 (2026-08-17 — golden 반쪽; §27.6 ④ 검증 의무 1)

**(ii) per-op x offset 교차곱 폐쇄**: directed append (window_fill
offset 6 / window_zero offset 4 / window_spill offset {2,4,5,6} —
family 표의 "+④ append" 표기; 기존 343 시나리오 record 스트림 뒤에
붙여 기존 스트림 byte-identical 유지) 로 창-거부 4 클래스 x offset
1..7 **전수**가 성립하고, 생성기 `bank_window_crossproduct` 가 전수를
assert 한다 (seed 이동으로 조용히 좁아지는 것을 막는 가드). 집계:

| 창-거부 class | 실측 offset 집합 |
|---|---|
%s

(창 offset 0 — start 와 같은 cycle 의 같은 slot 접촉 — 은 시나리오
형식상 표현 불가 (§2 형식 규율) 로 불변이며, ④ 통합 TB 의 직접 구동
몫이다 — §27.6 ④ 검증 의무 1(i).)

**(iii) TLC ghost 2건 처분 (검증 의무 1(iii) — RTL 실물화 vs 계약
재배정 양자택일의 판정. 본 절이 그 판정 기록이고, gate log 전사는 ④
merge COMMIT 몫이다)**:

1. **DT-04 (h) K 완결 캐리어 — 판정: 계약 재배정 ("hw 강제 불가"
   명시; RTL 실물화 아님)**. 근거: 캐리어 실물화는 tag / 0x70-block
   인코딩에 "K 중 i번째 / last 마커" 를 신설하는 **ISA-레벨 편집**인데,
   ④ 는 datapath 구조 합성 gate 로서 TRAIN ISA 결선을 명시 제외한다
   (§27.6 ④ 제외 (ii)) — ④ 범위 안에 실물화 경로가 없다. 재배정 형식:
   `Drain` 의 `issued == K` 전제를 §23.6a SDK 계약 1 (dec_* bus 에
   fragment 수 부재 — proofs/tla README §8 (h) 가 "동일 노출면" 으로
   특정한 그 항) 과 같은 급의 **SDK 계약으로 명시 등재**하고,
   `Inv_Complete` 는 "가정 모양" 지위를 유지한다 — V20-3 블록이 사전
   합법화한 종결 형식 (kickoff TP-3 의 INV_Complete 요구 형식).
2. **DT-05 (l) spill image owner-tag 캐리어 — 판정: 계약 재배정
   (`fill_owner` 의 SDK 계약 강등 + 명시; RTL 실물화 아님)**. 근거:
   하드웨어 대조는 spill image 포맷의 owner-토큰 규범화를 전제한다 —
   §27.2.2 SPILL image 는 순수 fp64 데이터 8 fragment 라 토큰 수납은
   포맷 규범 편집 (또는 metadata fragment 신설 — FRAG_MAX 16 중 8
   사용이라 공간 자체는 있다) 을 요구하고, 그 규범화는 spec COMMIT +
   0x7D TRAIN ISA 결선의 몫이지 ④ 의 "FILL/DRAIN/ZERO 는 bank cmd
   인터페이스 레벨 결선" scope 가 아니다. **정직 기록**: 이 재배정은
   §23.6a contract-1 급 노출면을 **하나 더** 만든다 (README §8 (l) 의
   그 경고 그대로) — 따라서 0x7D spill image 포맷 규범화 시점에
   owner-토큰 필드 신설을 **재심사 의무**로 이월한다 (본 판정은 ④
   시점의 scope 판정이지 영구 포기가 아니다).
3. **TB 반쪽 요구사항 (판정의 이행 명세 — ④ 통합 TB 저작자 대상)**:
   (a) 두 전제는 ③ 방식 그대로 **TB scoreboard ghost 대조**로 유지한다
   — `issued == K` 는 TB 스케줄이 보장하고 (K 미만 조기 drain 시나리오
   는 fault 를 기대하지 말 것 — hw 는 검사하지 않는다), 외래 spill
   image FILL 은 scoreboard 가 image 출처를 추적해 대조하되 **RTL 이
   잡는다고 주장하지 않는다** (hw 가 이 두 검사를 하지 않는다는 사실
   자체가 본 판정이다); (b) hw-실재 guard 군 (window / acc_owner /
   drain_owner / zero_owner / fill_bankfree / spill_owner / commit_zero
   / PROTO_GUARD) 과 혼동 금지 — 변이 반증 (④ 검증 의무 3) 은 hw-실재
   guard 에만 적용한다; (c) gate log 에 본 §10 판정 2건을 전사한다
   (merge-blocker 의무의 일부).
""" % (BANK_LATENCY, BANK_LATENCY, BANK_II,
       BANK_NSLOTS, BANK_NSLOTS - 1, BANK_LATENCY, BANK_II, BANK_LATENCY,
       BANK_LATENCY, BANK_LATENCY, BANK_LATENCY + 1, BANK_LATENCY,
       BANK_LATENCY, BANK_NSLOTS, BANK_LATENCY, BANK_NSLOTS, BANK_LATENCY,
       fam_rows, n_scen, n_rec, cov_rows, SEEDS["bank_rand_interleave"],
       xp_rows)


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

    # ---- directed: window sticky band — sticky OR 부분 절단 적발 ----
    # (반증 폐쇄 2026-08-16: 기존 4001 벡터에는 leading bit 아래 48..127
    #  위치 — 추출 128-bit window 의 top-48 아래 밴드 — 의 비트가 RTO
    #  jam 을 '단독' 결정하는 벡터가 0개였고, 그 결과 추출기 sticky OR 의
    #  부분 절단 (폭 k<=49 전부, chunk-정렬 k=48 포함) 이 TB 를 escape
    #  했다. 본 family 는 그 밴드의 모든 위치 d 에 유일 sticky 비트를
    #  두고 top-48 LSB=0 + window 아래(st_low) 0 을 강제한다 — 어떤 부분
    #  절단도 해당 위치의 벡터에서 WIDE/BANK 층 FAIL 을 낸다. leading
    #  bit 은 2^53 (lattice 물리 bit 319 = chunk 4 의 bit 63, lz=0) 에
    #  두어 window 가 최대 깊이 (127-bit) 로 열리게 한다.)
    em.begin("sticky_window_band",
             "2^53 + 2^(53-d), d=48..127 — leading bit 을 chunk 상단 "
             "(lz=0, window 최대 깊이) 에 두고 leading bit 아래 d 위치의 "
             "유일 비트가 RTO sticky-jam 을 단독 결정 (top-48 LSB=0, "
             "window 아래 0) — 추출기 sticky OR 부분 절단의 위치별 적발")
    for d in range(48, 128):
        wave = [(0, 53, 1 << 47), (0, 53 - d, 1 << 47)] \
            + [CANON_ZERO] * (GROUP - 2)
        w = em.emit(wave, CANON_ZERO)
        # 판별성 pin: jam LSB 는 오직 위치 d 의 비트가 세운다 (top-48
        # 나머지 0) — sticky 에서 d 를 빠뜨린 RTL 은 LSB=0 으로 갈라진다.
        assert w == (0, 53, (1 << 47) | 1), (d, w)

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
  byte-identical; blake2b512 은 `lattice_golden_report.json`).

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
// addend k 의 64-bit field:
//   wire [63:0] fld_k = vec[i][2799 - 64*k -: 64];
```

- dynamic part-select 금지 (project law) 는 **RTL 을 구속**한다. TB 의
  driver/checker 는 행위 모델로서 벡터 슬라이싱에 behavioral loop /
  variable shift 를 써도 좋다 — 단, TB 헤더에 행위 모델 면책 주석을
  명시할 것 (`tb_fp_acclattice.v` 선례).

- DUT resolve 출력 == `EXP_RESOLVED`, RTO-48 추출 == `EXP_WIDE`, bank
  인코딩 == `EXP_BANK`, PACK_FINAL drain == `EXP_FP32` — 4층 전부
  bit-exact 판정. 하나라도 불일치 = FAIL (표본률 논증 금지).
- `b_rne48_discriminator` (boundary family) 는 store 를 RNE-48 로 잘못
  구현한 RTL 을 1 ulp 로 적발한다; `b_tie_q25_killer` 는 추출 폭 부족
  (q<26) 을 적발한다.

## 7. 미결 pin (정직 기록 — 벡터는 이 영역을 회피)

- **FILL-valid 이나 lattice-표현 밖 carry**: bank word 는 fp64 로
  |v| <= ~2^1024 까지 담지만 lattice 는 |v| < 2^261 만 수용한다
  (§27.2.1 폭 도출 — 수용 구간은 pin 1 해소로 **개구간 (-2^261,
  2^261)**). **-> 폐쇄 (2026-08-16, ③ spec COMMIT — §27.2.2 하류 ③
  블록)**: 신규 클래스 없이 기존 **fault (d)/(e) 의 carry-lane 적용**
  (범위 <-> (d), 정밀도 <-> (e)), 발화 지점은 bank FILL 이 아니라
  **carry 소비 (beat 0)**. golden `LatticeFault` 2종이 그 대응이고,
  시나리오 레벨 reference 는 `bank_scenarios_contract.md` 의
  `carry_fault_*` family 가 운반한다.
- **fp64 -0 FILL**: 수용 + canonical +0 화 (§27.2.2 (iii)) — "검증
  통과 값은 round-trip bit-exact" 문장의 유일한 예외 (수용-후-재작성).
- f16 subnormal 곱의 lane-측 raw operand 형태 (§2 참조).

## 8. 결정론

고정 seed (아래) 외 난수원 없음, timestamp 없음 — 재실행 산출물은
byte-identical (blake2b512 은 report).

| seed key | value |
|---|---|
%s
""" % (n, VEC_HEX, VEC_BITS, VEC_BITS - 1, fam_rows, n, n, VEC_BITS - 1,
       seed_rows)


# ===========================================================================
# cluster operand-level 벡터 — ④ GATE V20-3 (2026-08-17 확장)
# ===========================================================================
# §27.6 ④ 검증 의무 2 (cluster 통합 TB 전 경로) 의 golden 반쪽: bf16/f16
# operand 쌍 (lane 8 x 4 beat = 32 쌍/wave) 에서 출발해 lane 곱 전단의
# §27.2.1 raw product 형식 (bf16 8x8 -> s16<<32 / f16 11x11 -> s22<<26,
# p_exp = ea_eff + eb_eff + 1) 을 거쳐 wave_step 4층 기대값 (RESOLVED/
# WIDE/BANK/FP32) 까지를 한 라인에 담는다. 기존 lattice 벡터의 addend 를
# 역-인수분해하지 않고 operand 부터 새로 생성한다 (별도 고정 seed).
#
# operand-load 정책의 규범 출처 = `FP_FmaLaneBf16.v` OPERAND-LOAD POLICY
# (§23.10.5 widen 의미론의 승계 — lane 헤더가 pin):
#   * bf16 exponent field 0 -> SIGNED ZERO (진짜 zero + 전 subnormal —
#     DAZ-일관 flush). 곱은 canonical zero addend.
#   * f16 subnormal -> EXACT 존중 (S1 leading-one scan + shift 로
#     normalize 후 곱 — 비대칭은 §23.10.5 의 pin 된 행동). 따라서
#     lattice 계약 §7 이 미결로 남겼던 "f16 subnormal 곱의 lane-측 raw
#     형태" 는 lane RTL 로 확정됐다: normalize 된 m11 로 s22 = m11a*m11b
#     ∈ [2^20, 2^22), sig = s22 << 26, p_exp = ea_eff+eb_eff+1 (ea_eff =
#     leading bit 의 지수) — 본 확장이 그 확정을 golden 으로 운반한다.
#   * NaN/Inf operand 는 벡터에 등장하지 않는다 — in-dot 경로는
#     FP_CLASSIFY 가 specials 를 lattice 이전에 필터한다 (§27.2 docstring
#     의 차단 계약 위치 (ii); lane 의 qNaN/특례 표는 후단 fp32 경로 몫).
#   * 곱이 zero (operand ±0 또는 bf16 DAZ) -> canonical zero addend
#     (lane 헤더: "significand forced to 0, p_exp -1024 sentinel").

_BF16_EXP_BIAS, _F16_EXP_BIAS = 127, 15


def bf16_bits(s, e, m8):
    """bf16 normal 인코딩: e = unbiased [-126,127], m8 = [128,256)."""
    assert s in (0, 1) and -126 <= e <= 127 and 128 <= m8 <= 255
    return (s << 15) | ((e + _BF16_EXP_BIAS) << 7) | (m8 - 128)


def f16_bits(s, e, m11):
    """f16 normal 인코딩: e = unbiased [-14,15], m11 = [1024,2048)."""
    assert s in (0, 1) and -14 <= e <= 15 and 1024 <= m11 <= 2047
    return (s << 15) | ((e + _F16_EXP_BIAS) << 10) | (m11 - 1024)


def f16_sub_bits(s, m10):
    """f16 subnormal 인코딩: 값 = (-1)^s * m10 * 2^-24, m10 = [1,1023]."""
    assert s in (0, 1) and 1 <= m10 <= 1023
    return (s << 15) | m10


def bf16_pow2(p, s=0):
    """정확한 2의 거듭제곱 bf16 (p in [-126,127])."""
    return bf16_bits(s, p, 128)


def operand_frac(dtype, bits):
    """operand 의 exact Fraction 값 — lane 정책 반영 (bf16 DAZ 포함).
    specials (NaN/Inf) 는 loud fault (벡터 전제 위반)."""
    assert 0 <= bits <= 0xFFFF
    s = (bits >> 15) & 1
    if dtype == 0:                          # bf16
        E, m = (bits >> 7) & 0xFF, bits & 0x7F
        if E == 0xFF:
            raise LatticeFault("bf16 special operand forbidden: 0x%04X"
                               % bits)
        if E == 0:                          # signed zero + DAZ subnormal
            return Fraction(0)
        v = Fraction(128 + m) * TWO ** (E - _BF16_EXP_BIAS - 7)
    else:                                   # f16
        E, m = (bits >> 10) & 0x1F, bits & 0x3FF
        if E == 0x1F:
            raise LatticeFault("f16 special operand forbidden: 0x%04X"
                               % bits)
        if E == 0 and m == 0:
            return Fraction(0)
        if E == 0:                          # subnormal — EXACT 존중
            v = Fraction(m) * TWO ** -24
        else:
            v = Fraction(1024 + m) * TWO ** (E - _F16_EXP_BIAS - 10)
    return -v if s else v


def _lane_sig_exp(dtype, bits):
    """operand 의 (normalized significand, leading-bit 지수) — lane S1
    (unpack + f16-subnormal normalize) 의 산술 모델. zero -> None."""
    s = (bits >> 15) & 1
    if dtype == 0:
        E, m = (bits >> 7) & 0xFF, bits & 0x7F
        assert E != 0xFF, "specials forbidden"
        if E == 0:
            return s, None, None            # DAZ signed zero
        return s, 128 + m, E - _BF16_EXP_BIAS
    E, m = (bits >> 10) & 0x1F, bits & 0x3FF
    assert E != 0x1F, "specials forbidden"
    if E == 0 and m == 0:
        return s, None, None
    if E == 0:                              # subnormal: leading-one scan
        k = 11 - m.bit_length()
        return s, m << k, -14 - k           # m<<k in [2^10,2^11)
    return s, 1024 + m, E - _F16_EXP_BIAS


def lane_product_addend(dtype, a_bits, b_bits):
    """lane 곱 전단의 raw wide product (§27.2.1 / FP_FmaLaneBf16 C1+C2
    ALIGN ALGEBRA): sig = (ma*mb) << (32|26), exp = ea_eff+eb_eff+1.
    어느 한쪽이 zero (±0 또는 bf16 DAZ) -> canonical zero addend."""
    sa, ma, ea = _lane_sig_exp(dtype, a_bits)
    sb, mb, eb = _lane_sig_exp(dtype, b_bits)
    if ma is None or mb is None:
        return CANON_ZERO
    sh = 32 if dtype == 0 else 26
    add = (sa ^ sb, ea + eb + 1, (ma * mb) << sh)
    wide_check(*add, what="lane raw product")
    # 값-일치 교차검증: raw 형식 구성 vs 필드 직독 Fraction 곱 (독립 경로)
    assert wide_frac(*add) == operand_frac(dtype, a_bits) \
        * operand_frac(dtype, b_bits)
    return add


# ---------------------------------------------------------------------------
# cluster wave 생성기 (전부 CLUSTER_SEEDS 고정 seed 의 rng 인자 경유)
# ---------------------------------------------------------------------------


def rand_bf16_operand(rng, elo=-126, ehi=127):
    return bf16_bits(rng.randint(0, 1), rng.randint(elo, ehi),
                     rng.randrange(128, 256))


def rand_f16_operand(rng, p_sub=0.0):
    if rng.random() < p_sub:
        return f16_sub_bits(rng.randint(0, 1), rng.randint(1, 1023))
    return f16_bits(rng.randint(0, 1), rng.randint(-14, 15),
                    rng.randrange(1024, 2048))


def _zeroish_operand(rng, dtype):
    """곱을 zero 로 만드는 operand: ±0, 또는 (bf16 만) DAZ subnormal —
    operand 는 nonzero 인데 lane 이 zero 로 flush 하는 killer 포함."""
    r = rng.random()
    if dtype == 0 and r < 0.5:
        return (rng.randint(0, 1) << 15) | rng.randint(1, 127)  # DAZ sub
    return rng.randint(0, 1) << 15                              # ±0


def cwave_bf16_rand(rng):
    pairs = []
    for _ in range(GROUP):
        if rng.random() < 0.08:             # zero/DAZ 산재
            z = _zeroish_operand(rng, 0)
            a, b = (z, rand_bf16_operand(rng))
            pairs.append((a, b) if rng.random() < 0.5 else (b, a))
        else:
            pairs.append((rand_bf16_operand(rng), rand_bf16_operand(rng)))
    return pairs


def cwave_f16_rand(rng):
    pairs = []
    for _ in range(GROUP):
        if rng.random() < 0.06:
            z = _zeroish_operand(rng, 1)
            a, b = (z, rand_f16_operand(rng, 0.3))
            pairs.append((a, b) if rng.random() < 0.5 else (b, a))
        else:
            pairs.append((rand_f16_operand(rng, 0.2),
                          rand_f16_operand(rng, 0.2)))
    return pairs


def cwave_cancel(rng):
    """operand-레벨 대규모 상쇄: 쌍 (a,b) 와 (-a,b) — 곱이 정확히
    상쇄된다 — + 수십 binade 아래 dust 쌍."""
    Z = (0, 0)
    pairs = [Z] * GROUP
    a = rand_bf16_operand(rng, -20, 20)
    b = rand_bf16_operand(rng, -20, 20)
    pairs[0], pairs[1] = (a, b), (a ^ 0x8000, b)
    ec = rng.randint(-60, -30)
    for i in rng.sample(range(2, GROUP), rng.randint(2, 4)):
        pairs[i] = (rand_bf16_operand(rng, ec // 2 - 1, ec // 2 + 1),
                    rand_bf16_operand(rng, ec // 2 - 1, ec // 2 + 1))
    return pairs


def cwave_sparse(rng):
    Z = (0, 0)
    pairs = [Z] * GROUP
    for i in rng.sample(range(GROUP), rng.randint(0, GROUP)):
        pairs[i] = (rand_bf16_operand(rng, -40, 40),
                    rand_bf16_operand(rng, -40, 40))
    return pairs


class ClusterEmitter:
    """operand-레벨 벡터 누적기 — 모든 emit 은 (i) per-pair raw 곱의
    Fraction 교차검증 (lane_product_addend 내장), (ii) wave 4층 Fraction
    이중 검증 (check_wave_against_fraction), (iii) segment 기하 assert 를
    통과해야 한다."""

    def __init__(self):
        self.lines = []
        self.families = []
        self.max_span = 0
        self.n_pairs_checked = 0
        self._fam = None

    def begin(self, name, doc):
        self._fam = {"family": name, "doc": doc,
                     "start": len(self.lines), "count": 0}
        self.families.append(self._fam)

    def emit(self, dtype, pairs, carry, chained=False):
        assert dtype in (0, 1) and len(pairs) == GROUP
        adds = [lane_product_addend(dtype, a, b) for a, b in pairs]
        self.n_pairs_checked += GROUP
        units, wide, bank, f32 = check_wave_against_fraction(adds, carry)
        self.max_span = max(self.max_span, check_segments(
            adds + [carry], units))
        v = (int(chained) << 1) | dtype     # META [0]=dtype, [1]=chained
        for a, b in pairs:
            assert 0 <= a <= 0xFFFF and 0 <= b <= 0xFFFF
            v = (v << 32) | (a << 16) | b
        for ad in adds:
            v = (v << 64) | field_encode(*ad)
        v = (v << 64) | field_encode(*carry)
        v = (v << LAT_W) | lattice_word(units)
        v = (v << 64) | field_encode(*wide)
        v = (v << 64) | bank
        v = (v << 32) | f32
        assert v < (1 << CVEC_BITS)
        self.lines.append("%0*x" % (CVEC_HEX, v))
        self._fam["count"] += 1
        return wide, adds, f32


def gen_cluster_vectors():
    em = ClusterEmitter()
    Z = (0, 0)

    def pad(pairs):
        return pairs + [Z] * (GROUP - len(pairs))

    def pow2_pair(p):
        """곱 == 2^p 인 bf16 쌍 (p in [-252,254])."""
        return (bf16_pow2(p // 2), bf16_pow2(p - p // 2))

    # ---- directed ----
    em.begin("c_raw_unnorm", "1.0x1.0 등 2^k 곱 — raw 형식의 1-bit "
             "un-normalized (sig = 2^46) 경로 directed: normalize 를 "
             "곱 지점에 잘못 넣은 RTL 은 EXP_ADDEND 층에서 갈라진다")
    _, adds, _ = em.emit(0, pad([(bf16_pow2(0), bf16_pow2(0)),
                                 pow2_pair(-100), pow2_pair(200)]),
                         CANON_ZERO)
    assert adds[0] == (0, 1, 1 << 46)       # 1x1: sig 하한, leading zero 1

    em.begin("c_rne48_discriminator", "operand-레벨 x = 2^48+2^24+1 — "
             "store 반올림 모드 판별 (§27.2.1; drain 0x57800001, RNE-48 "
             "오구현 RTL 은 0x57800000)")
    _, _, f32 = em.emit(0, pad([pow2_pair(48), pow2_pair(24),
                                pow2_pair(0)]), CANON_ZERO)
    assert f32 == 0x57800001

    em.begin("c_tie_q25_killer", "operand-레벨 x = 1+2^-24+2^-60 — 추출 "
             "폭 q<26 적발 (정답 0x3F800001)")
    _, _, f32 = em.emit(0, pad([pow2_pair(0), pow2_pair(-24),
                                pow2_pair(-60)]), CANON_ZERO)
    assert f32 == 0x3F800001

    em.begin("c_sticky_band", "2^53 + 2^(53-d), d in {48,63,64,95,127} — "
             "lattice sticky_window_band 의 operand-레벨 재현 (전 80 위치는 "
             "lattice 벡터가 커버; 여기는 전 경로 통과 확인 subset)")
    for d in (48, 63, 64, 95, 127):
        w, _, _ = em.emit(0, pad([pow2_pair(53), pow2_pair(53 - d)]),
                          CANON_ZERO)
        assert w == (0, 53, (1 << 47) | 1), (d, w)

    em.begin("c_bf16_daz_killer", "bf16 subnormal operand -> SIGNED ZERO "
             "flush (lane 정책 — §23.10.5 pin 6): subnormal 쌍은 곱 "
             "canonical zero. DAZ 를 빠뜨린 RTL 은 EXP_ADDEND/합 양층에서 "
             "갈라진다 (최대 subnormal 0x007F 포함)")
    _, adds, f32 = em.emit(0, pad([(0x007F, bf16_pow2(120)),
                                   (0x807F, bf16_pow2(120)),
                                   (0x0001, 0x0001),
                                   (bf16_pow2(0), bf16_pow2(0))]),
                           CANON_ZERO)
    assert adds[0] == adds[1] == adds[2] == CANON_ZERO
    assert f32 == 0x3F800000                # 살아남는 것은 1.0 하나
    _, adds, f32 = em.emit(0, pad([(0x0040, 0x8040)]), CANON_ZERO)
    assert adds[0] == CANON_ZERO and f32 == 0x00000000

    em.begin("c_f16_subnormal", "f16 subnormal EXACT 존중 (lane S1 "
             "normalize — 비대칭은 §23.10.5 pin): 최소 subnormal 제곱 "
             "2^-48 (lattice 하단), subnormal x normal, 홀수 m10 dust")
    _, adds, _ = em.emit(1, pad([(f16_sub_bits(0, 1), f16_sub_bits(0, 1))]),
                         CANON_ZERO)
    assert adds[0] == (0, -47, 1 << 46)     # (2^-24)^2 — un-normalized raw
    _, adds, _ = em.emit(1, pad([(f16_sub_bits(0, 3), f16_bits(0, 0, 1024)),
                                 (f16_sub_bits(1, 1023),
                                  f16_bits(0, 15, 2047))]), CANON_ZERO)
    assert wide_frac(*adds[0]) == Fraction(3) * TWO ** -24
    em.emit(1, pad([(f16_sub_bits(0, 2 * k + 1),
                     f16_bits(k % 2, k - 7, 1024 + 64 * k))
                    for k in range(8)]), CANON_ZERO)

    em.begin("c_boundary", "경계 directed — 최대 곱 x32 (drain ±Inf), "
             "f16 최대 곱 x32, bf16 최소 normal 곱 (lattice bit 0, 홀수 "
             "significand)")
    mx = bf16_bits(0, 127, 255)
    _, _, f32 = em.emit(0, [(mx, mx)] * GROUP, CANON_ZERO)
    assert f32 == 0x7F800000
    _, _, f32 = em.emit(0, [(mx ^ 0x8000, mx)] * GROUP, CANON_ZERO)
    assert f32 == 0xFF800000
    fmx = f16_bits(0, 15, 2047)             # 65504.0
    em.emit(1, [(fmx, fmx)] * GROUP, CANON_ZERO)
    lo = bf16_bits(0, -126, 129)            # 129 홀수 — lattice bit 0
    _, adds, f32 = em.emit(0, pad([(lo, lo)]), CANON_ZERO)
    assert wide_frac(*adds[0]) == Fraction(16641) * TWO ** -266
    assert f32 == 0x00000000                # drain FTZ
    _, _, f32 = em.emit(0, pad([(lo ^ 0x8000, lo)]), CANON_ZERO)
    assert f32 == 0x80000000

    # ---- random families ----
    rng = random.Random(CLUSTER_SEEDS["cl_bf16_rand"])
    em.begin("c_bf16_rand", "전 지수역 임의 bf16 operand 쌍 32개 + 임의 "
             "carry — ±0/DAZ-subnormal 산재 (8%)")
    for _ in range(400):
        em.emit(0, cwave_bf16_rand(rng), rand_carry(rng))

    rng = random.Random(CLUSTER_SEEDS["cl_f16_rand"])
    em.begin("c_f16_rand", "임의 f16 쌍 (subnormal operand ~20% 혼입 — "
             "EXACT 존중 경로) + 임의 carry")
    for _ in range(250):
        em.emit(1, cwave_f16_rand(rng), rand_carry(rng))

    rng = random.Random(CLUSTER_SEEDS["cl_cancel"])
    em.begin("c_cancel", "operand-레벨 상쇄 (a,b) + (-a,b) + 아래 binade "
             "dust — park/cancel 계열")
    for _ in range(150):
        em.emit(0, cwave_cancel(rng), rand_carry(rng))

    rng = random.Random(CLUSTER_SEEDS["cl_sparse"])
    em.begin("c_sparse", "nonzero 쌍 0..32개 — zero-쌍 슬롯 처리")
    for _ in range(100):
        em.emit(0, cwave_sparse(rng), rand_carry(rng))

    # ---- carry 체이닝 families ----
    rng = random.Random(CLUSTER_SEEDS["cl_chain_bf16"])
    em.begin("c_chain_bf16", "K=1024 chain x4 (32 wave/chain, 이전 wave "
             "의 EXP_WIDE == 다음 wave 의 ADDEND[32]) — bf16, factor exp "
             "[-10,10]")
    for _ in range(4):
        carry = CANON_ZERO
        for k in range(32):
            carry, _, _ = em.emit(
                0, [(rand_bf16_operand(rng, -10, 10),
                     rand_bf16_operand(rng, -10, 10))
                    for _ in range(GROUP)], carry, chained=k > 0)

    rng = random.Random(CLUSTER_SEEDS["cl_chain_mixed"])
    em.begin("c_chain_mixed", "bf16/f16 교대 chain x2 — dtype 이 wave "
             "마다 바뀌어도 carry 체이닝의 수학 계약은 불변 (exact 합)")
    for _ in range(2):
        carry = CANON_ZERO
        for k in range(32):
            if k % 2 == 0:
                pairs = [(rand_bf16_operand(rng, -8, 8),
                          rand_bf16_operand(rng, -8, 8))
                         for _ in range(GROUP)]
            else:
                pairs = cwave_f16_rand(rng)
            carry, _, _ = em.emit(k % 2, pairs, carry, chained=k > 0)

    rng = random.Random(CLUSTER_SEEDS["cl_chain_parkcancel"])
    em.begin("c_chain_parkcancel", "cross-wave park-plus-cancel chain x2 "
             "— 이전 wave 곱의 operand 부호 반전 재주입으로 상쇄 (F1/F4 "
             "계열의 operand-레벨 확장)")
    for _ in range(2):
        carry, pending = CANON_ZERO, []
        for k in range(32):
            pairs, j = [Z] * GROUP, 0
            for (a, b) in pending:
                pairs[j] = (a ^ 0x8000, b)
                j += 1
            pending = []
            for _ in range(rng.randint(1, 3)):
                p = (rand_bf16_operand(rng, -10, 10),
                     rand_bf16_operand(rng, -10, 10))
                pairs[j] = p
                j += 1
                if rng.random() < 0.7:
                    pending.append(p)
            for _ in range(rng.randint(1, 4)):
                pairs[j] = (rand_bf16_operand(rng, -20, -13),
                            rand_bf16_operand(rng, -20, -13))
                j += 1
            carry, _, _ = em.emit(0, pairs, carry, chained=k > 0)

    rng = random.Random(CLUSTER_SEEDS["cl_daz_rand"])
    em.begin("c_daz_rand", "DAZ/±0 고밀도 임의 wave — 쌍의 절반가량이 "
             "zero-곱 (bf16 subnormal/±0), 나머지 정상 — flush 대량 혼류")
    for _ in range(60):
        pairs = []
        for _ in range(GROUP):
            if rng.random() < 0.5:
                z = _zeroish_operand(rng, 0)
                n = rand_bf16_operand(rng, -30, 30)
                pairs.append((z, n) if rng.random() < 0.5 else (n, z))
            else:
                pairs.append((rand_bf16_operand(rng, -30, 30),
                              rand_bf16_operand(rng, -30, 30)))
        em.emit(0, pairs, rand_carry(rng))

    return em


def write_cluster_file(em):
    hdr = [
        "// cluster_wave_vectors.hex — v2.0 cluster operand-level TB 벡터 "
        "(④ GATE V20-3; 결정적, 고정 seed)",
        "// 생성기: scripts/golden_lattice.py — 비트 레이아웃 계약: "
        "include/generated/cluster_vec_contract.md",
        "// 1 line = 1 wave-step = %d hex chars = %d bits; N_VEC = %d"
        % (CVEC_HEX, CVEC_BITS, len(em.lines)),
    ]
    CLUSTER_VEC_PATH.write_text("\n".join(hdr + em.lines) + "\n")


def verify_cluster_file():
    """파일 재독 -> operand 분해 -> lane 곱/4층 golden 재계산 -> 인코딩된
    기대 전 필드 재대조 (파일 자기증명 — verify_vector_file 동형)."""
    n = 0
    for ln in CLUSTER_VEC_PATH.read_text().splitlines():
        if not ln or ln.startswith("//"):
            continue
        assert len(ln) == CVEC_HEX
        v = int(ln, 16)
        f32 = v & 0xFFFFFFFF
        v >>= 32
        bank = v & _M64
        v >>= 64
        widef = v & _M64
        v >>= 64
        resolved = v & _M528
        v >>= LAT_W
        carryf = v & _M64
        v >>= 64
        addf = [(v >> (64 * (GROUP - 1 - k))) & _M64 for k in range(GROUP)]
        v >>= 64 * GROUP
        pairs = [((v >> (32 * (GROUP - 1 - k) + 16)) & 0xFFFF,
                  (v >> (32 * (GROUP - 1 - k))) & 0xFFFF)
                 for k in range(GROUP)]
        v >>= 32 * GROUP
        assert v >> 2 == 0                  # META [31:2] 예약 0
        dtype = v & 1
        adds = [lane_product_addend(dtype, a, b) for a, b in pairs]
        assert [field_encode(*a) for a in adds] == addf
        carry = field_decode(carryf)
        units, wide, bank_g, f32_g = wave_step(adds, carry)
        assert lattice_word(units) == resolved
        assert field_encode(*wide) == widef
        assert bank_g == bank and f32_g == f32
        n += 1
    return n


def cluster_contract_text(em):
    fam_rows = "\n".join(
        "| %s | %d | %d | %s |" % (f["family"], f["start"], f["count"],
                                   f["doc"].replace("\n", " "))
        for f in em.families)
    seed_rows = "\n".join("| `%s` | `0x%X` |" % kv
                          for kv in CLUSTER_SEEDS.items())
    n = len(em.lines)
    return """<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor \
contributors -->
<!-- GENERATED by scripts/golden_lattice.py — 손편집 금지. 재생성은 \
`python3 scripts/golden_lattice.py` (byte-identical). -->

# cluster_wave_vectors.hex — operand-레벨 벡터 계약 (④ GATE V20-3)

- **규범 출처**: `.claude-memos/wt64v1_spec.md` §27.6 ④ 검증 의무 2
  (cluster 통합 TB 전 경로 — operand 주입 -> lane widen/곱 -> 8-operand
  x 4-beat dispatch -> lattice -> bank RTO-48 -> drain RNE-24); §27.2.1
  raw product 형식; `FP_FmaLaneBf16.v` OPERAND-LOAD POLICY + ALIGN
  ALGEBRA (C1/C2 — §23.10.5 widen 의미론의 lane 승계 pin).
- **golden**: `scripts/golden_lattice.py` (`lane_product_addend` +
  `wave_step` — 모든 기대값의 산출자; 전 쌍 Fraction 값-일치 교차검증 +
  전 wave 4층 Fraction 이중 검증 통과).
- **벡터 파일**: `include/generated/cluster_wave_vectors.hex` —
  `$readmemh`, 주석 3줄 + %d 라인. 결정적 (고정 seed, 재실행
  byte-identical; blake2b512 은 `lattice_golden_report.json`).
- operand 를 새로 생성했다 — 기존 lattice 벡터 addend 의 역-인수분해가
  아니다 (④ 지시). 기존 `lattice_wave_vectors.hex` 4081 벡터는 무변경.

## 1. 라인 형식

1 라인 = 1 wave-step = **%d hex 문자 = %d bit** 단일 토큰.
`CVEC[%d:0]` (MSB 먼저):

| 필드 | 비트 구간 | 폭 | 의미 |
|---|---|---|---|
| `META` | `[%d:%d]` | 32 | `[0]` dtype (0=bf16, 1=f16 — wave 단위 단일), `[1]` chained (직전 라인의 `EXP_WIDE` 가 본 라인 `ADDEND[32]` — 정보 제공), `[31:2]` 예약 0 |
| `OPRND[k]` | `[%d-32k : %d-32k]`, k=0..31 | 32 x32 | operand 쌍 k — `[31:16]` = A, `[15:0]` = B (bf16 또는 IEEE binary16 원시 16-bit 인코딩) |
| `EXP_ADDEND[k]` | `[2799-64k : 2736-64k]`, k=0..31 | 64 x32 | **기대 lane raw 곱** (§3) — lane 곱 전단 tap 의 bit-exact 판정점 |
| `ADDEND[32]` | `[751:688]` | 64 | bank carry-in (wide field) |
| `EXP_RESOLVED` | `[687:160]` | 528 | 기대 resolve (exact 33-항 합) |
| `EXP_WIDE` | `[159:96]` | 64 | 기대 RTO-48 추출 |
| `EXP_BANK` | `[95:32]` | 64 | 기대 bank word (fp64 무손실 재인코딩) |
| `EXP_FP32` | `[31:0]` | 32 | 기대 즉시-drain (RNE-24 + FTZ) |

**하위 [2799:0] 은 `lattice_vec_contract.md` §1 의 라인 형식과 비트
단위로 동일하다** (`EXP_ADDEND[0..31]` 가 그쪽 `ADDEND[0..31]` 자리) —
TB 는 lattice-레벨 checker 를 하위 슬라이스에 그대로 재사용할 수 있다.

## 2. operand 인코딩과 lane 적재 정책 (normative — lane 헤더 전사)

- **bf16** = 1s + 8e + 7m. `E==0` -> **SIGNED ZERO** (진짜 zero 와 전
  254 subnormal — DAZ-일관 flush, §23.10.5 pin 6). `E==255` (specials)
  는 **벡터에 등장하지 않는다**.
- **f16** = 1s + 5e + 10m. `E==0, m!=0` (subnormal) -> **EXACT 존중**
  (lane S1 leading-one scan + shift 로 normalize — bf16 과의 비대칭은
  pin 된 §23.10.5 행동). `E==31` 은 벡터에 등장하지 않는다.
- **specials 차단 계약 위치** (lattice 계약 §4 와 동일): in-dot 경로는
  FP_CLASSIFY 가 NaN/Inf 를 lattice 이전에 필터한다 — 본 벡터의
  operand 는 전부 finite 다.

## 3. `EXP_ADDEND[k]` — lane raw 곱 (§27.2.1 확정 형식)

```
zero 곱 (어느 쪽이든 ±0 또는 bf16 DAZ) -> canonical zero
   64'h0400_0000_0000_0000
bf16: sig = (m8a_eff * m8b_eff) << 32   (8x8 -> 16-bit),  m8 in [128,256)
f16 : sig = (m11a_eff * m11b_eff) << 26 (11x11 -> 22-bit), m11 in [1024,2048)
exp = ea_eff + eb_eff + 1   (ea_eff = leading significand bit 의 지수)
sign = sa ^ sb
```

- sig 는 [2^46, 2^48) — **1-bit un-normalized (leading zero 1) 허용**이
  raw 형식의 본질이다 (2^k 곱은 정확히 sig == 2^46). 곱 지점 normalize
  를 넣은 RTL 은 `c_raw_unnorm` family 의 `EXP_ADDEND` 층에서 갈라진다.
- **f16 subnormal 의 raw 형태 확정 기록**: `lattice_vec_contract.md` §7
  이 "RTL C2 경로 확정 사항" 으로 미결 유지하던 항 — `FP_FmaLaneBf16.v`
  S1 (f16-subnormal normalize) 착지로 확정됐다: m10 을 leading-one
  scan 으로 normalize 한 m11_eff 와 ea_eff = -14 - (11 - bitlen(m10))
  를 위 공식에 그대로 인가한다. 본 계약이 그 확정의 golden 운반자다.
- p_exp 범위: bf16 [-251, 255], f16 [-47, 31] — signed-11 수납, -1024
  zero sentinel 과 절대 비충돌 (lane ALIGN ALGEBRA 증명 전사).

## 4. beat/lane 사상 (canonical drive 규약)

쌍 k 의 canonical dispatch 좌표 = **beat `k>>3` (0..3), lane `k&7`
(0..7)** — §27.2.1 amendment 의 8-operand x 4-beat 스케줄 (II=4, carry
beat 0 병합). 단, lattice 합은 exact (association-free) 이므로 **어떤
beat/lane 재배열도 기대값을 바꾸지 않는다** — 이 사상은 TB 의 drive
규약이지 정답의 전제가 아니다. `EXP_ADDEND[k]` 는 언제나 `OPRND[k]` 의
곱이다 (k 로 대응 — 사상과 무관).

## 5. 전제조건 (모든 벡터가 보장)

- operand 는 전부 finite (specials 없음 — §2); 33-항 합은 개구간
  (-2^261, 2^261) 안 (§27.2.1 pin 1; 생성 시 loud-fault 로 강제).
- carry-in 은 normalized 또는 canonical zero (§27.2.1 pin 2).
- `EXP_FP32` 는 ±Inf/±0 가능, NaN 절대 불가.

## 6. family 배치 (라인 인덱스 0-base)

| family | start | count | 의도 |
|---|---|---|---|
%s

- 총 **%d 벡터**. `c_chain_*` family 는 직전 라인 `EXP_WIDE` == 본 라인
  `ADDEND[32]` 체인이나, 각 라인이 자체 carry 를 운반하므로 TB 는 라인
  단위 독립 검증만으로 충분하다 (체인 재현은 선택 — META[1] 참조).

## 7. TB 판정 규칙

- **lane 곱 전단 tap**: beat b 의 lane l 에 `OPRND[8b+l]` 인가 시 raw
  곱 == `EXP_ADDEND[8b+l]` — **bit-exact** (§3 형식 그대로;
  un-normalized 보존 포함; 다른 사상 채택 시에도 `EXP_ADDEND[k]` 는
  언제나 `OPRND[k]` 의 곱이다 — §4).
- **wave 4층**: resolve == `EXP_RESOLVED`, 추출 == `EXP_WIDE`, bank
  == `EXP_BANK`, drain == `EXP_FP32` — 전부 bit-exact. 하나라도
  불일치 = FAIL (표본률 논증 금지).
- dynamic part-select 금지는 RTL 구속 — TB behavioral 슬라이싱 면책
  주석 관례는 `lattice_vec_contract.md` §6 그대로.

## 8. 결정론

고정 seed (아래, `CLUSTER_SEEDS` — 기존 `SEEDS` 와 분리: 기존 산출물
byte-identity 유지) 외 난수원/timestamp 없음 — 재실행 byte-identical
(blake2b512 은 report).

| seed key | value |
|---|---|
%s
""" % (n, CVEC_HEX, CVEC_BITS, CVEC_BITS - 1,
       CVEC_BITS - 1, CVEC_BITS - 32,
       CVEC_BITS - 33, CVEC_BITS - 64,
       fam_rows, n, seed_rows)


# ===========================================================================
# main
# ===========================================================================


def _digest(path):
    return hashlib.blake2b(path.read_bytes(), digest_size=64).hexdigest()


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

    t0 = time.time()
    cem = gen_cluster_vectors()
    write_cluster_file(cem)
    CLUSTER_CONTRACT_PATH.write_text(cluster_contract_text(cem))
    stamp("cluster operand-level vector generation (%d vectors, "
          "%d families)" % (len(cem.lines), len(cem.families)), t0)

    t0 = time.time()
    n_cluster_verified = verify_cluster_file()
    assert n_cluster_verified == len(cem.lines)
    stamp("cluster vector file re-read self-verify (%d lines)"
          % n_cluster_verified, t0)

    t0 = time.time()
    bank_scens = gen_bank_scenarios()
    bank_cov = bank_coverage(bank_scens)
    bank_xprod = bank_window_crossproduct(bank_scens)
    n_bank_rec, bank_fams = write_bank_file(bank_scens)
    BANK_CONTRACT_PATH.write_text(bank_contract_text(
        len(bank_scens), n_bank_rec, bank_fams, bank_cov, bank_xprod))
    stamp("bank scenario generation (%d scenarios, %d records, "
          "%d families)" % (len(bank_scens), n_bank_rec, len(bank_fams)),
          t0)

    t0 = time.time()
    n_bank_verified = bank_verify_file()
    assert n_bank_verified == len(bank_scens)
    stamp("bank scenario file re-read self-verify (%d scenarios)"
          % n_bank_verified, t0)

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
            "blake2b512": _digest(VEC_PATH),
        },
        "contract": {
            "path": "include/generated/lattice_vec_contract.md",
            "blake2b512": _digest(CONTRACT_PATH),
        },
        "cluster_vectors": {
            "_doc": "④ GATE V20-3 (2026-08-17): cluster operand-level "
                    "벡터 — bf16/f16 operand 쌍 32개/wave 에서 lane 곱 "
                    "전단 raw 형식 (§27.2.1) 을 거쳐 wave_step 4층 "
                    "기대값까지. operand 는 신규 생성 (기존 lattice "
                    "벡터 역-인수분해 아님, CLUSTER_SEEDS 분리). 계약: "
                    "include/generated/cluster_vec_contract.md.",
            "path": "include/generated/cluster_wave_vectors.hex",
            "n_vectors": len(cem.lines),
            "bits_per_line": CVEC_BITS,
            "hex_chars_per_line": CVEC_HEX,
            "families": cem.families,
            "seeds": CLUSTER_SEEDS,
            "pair_fraction_crosscheck": {
                "pairs_checked": cem.n_pairs_checked,
                "mismatches": 0,
                "note": "전 쌍: raw 형식 구성 (normalize+multiply) vs "
                        "operand 필드 직독 Fraction 곱의 값-일치 — "
                        "lane_product_addend 내장 assert",
            },
            "f16_subnormal_raw_form": "확정 운반 (FP_FmaLaneBf16.v S1 "
                                      "normalize — lattice 계약 §7 의 "
                                      "미결 항 해소; cluster 계약 §3)",
            "self_verify": {
                "lines": n_cluster_verified, "mismatches": 0,
                "verdict": "PASS"},
            "blake2b512": _digest(CLUSTER_VEC_PATH),
            "contract": {
                "path": "include/generated/cluster_vec_contract.md",
                "blake2b512": _digest(CLUSTER_CONTRACT_PATH),
            },
        },
        "gate_v20_3_carryover": {
            "_doc": "§27.6 ④ 검증 의무 1 — ③ 이월 3건의 golden-반쪽 "
                    "처분 기록 (gate log 전사는 ④ merge COMMIT 몫).",
            "i_window_offset0": "시나리오 형식상 표현 불가 불변 — ④ 통합 "
                                "TB 직접 구동 몫 (bank 계약 §2/§10)",
            "ii_crossproduct": {
                "added_directed": {
                    "window_fill_offsets": [6],
                    "window_zero_offsets": [4],
                    "window_spill_offsets": [2, 4, 5, 6]},
                "appended_after_existing_343": True,
                "window_offsets_measured": bank_xprod,
                "exhaustive_1_to_7_asserted": True,
            },
            "iii_ghost_disposition": {
                "DT-04_h_K_carrier": {
                    "disposition": "계약 재배정 — 'hw 강제 불가' 명시 "
                                   "(RTL 실물화 아님)",
                    "rationale": "캐리어는 tag/0x70-block ISA-레벨 편집 "
                                 "요구 — ④ 제외 (ii) 로 범위 밖; §23.6a "
                                 "SDK 계약 1 동일 노출면으로 명시 등재, "
                                 "Inv_Complete 는 '가정 모양' 유지 — "
                                 "V20-3 블록 사전 합법화 형식 (kickoff "
                                 "TP-3)",
                },
                "DT-05_l_spill_owner_tag": {
                    "disposition": "계약 재배정 — fill_owner 의 SDK 계약 "
                                   "강등 + 명시 (RTL 실물화 아님)",
                    "rationale": "hw 대조는 spill image 포맷 owner-토큰 "
                                 "규범화 (spec COMMIT + 0x7D ISA 결선 "
                                 "몫) 전제 — ④ scope 밖; §23.6a "
                                 "contract-1 급 노출면 +1 정직 기록, "
                                 "0x7D 포맷 규범화 시점 재심사 의무로 "
                                 "이월",
                },
                "tb_requirements": "bank_scenarios_contract.md §10 항 3 "
                                   "— scoreboard ghost 대조 유지 / "
                                   "hw-실재 guard 와 혼동 금지 (변이 "
                                   "반증은 hw-실재 guard 만) / gate log "
                                   "전사",
            },
        },
        "bank_reference": {
            "_doc": "wide ACC bank 상태기계 reference + 통합 TB 시나리오 "
                    "(§27.6 하류 ③ 검증 계획 (c), 2026-08-16 확장). 형식/"
                    "의미 계약: include/generated/bank_scenarios_"
                    "contract.md; 실행기: bank_execute.",
            "constants": {
                "LATENCY": BANK_LATENCY, "II": BANK_II,
                "n_slots": BANK_NSLOTS,
                "fdz_fault_window": "[start, start+%d] 양끝 포함 (IF-2 — "
                                    "창 마지막 = writeback cycle 접촉도 "
                                    "fault, 직후 합법)" % BANK_LATENCY,
                "same_slot_chain_min": BANK_LATENCY,
            },
            "pin1_amendment": {
                "acceptance": "개구간 (-2^261, 2^261) — lattice_"
                              "accumulate 는 LAT_MIN < total, 경계 도달 "
                              "= LatticeFault (fault (f) 클래스)",
                "extract_rto48": "지수 범위 검사 bare assert -> "
                                 "LatticeFault 승격 (e == 261 <=> |합| "
                                 ">= 2^261)",
                "vector_file_byte_identical": True,
            },
            "scenario_file": {
                "path": "include/generated/bank_scenarios.hex",
                "n_scenarios": len(bank_scens),
                "n_records": n_bank_rec,
                "families": [
                    {"family": f, "code": code, "scenarios": ns,
                     "records": nr, "doc": BANK_FAM_DOCS[f][1]}
                    for f, code, ns, nr in bank_fams],
                "blake2b512": _digest(BANK_HEX_PATH),
            },
            "contract": {
                "path": "include/generated/bank_scenarios_contract.md",
                "blake2b512": _digest(BANK_CONTRACT_PATH),
            },
            "coverage": bank_cov,
            "window_offset_crossproduct": bank_xprod,
            "self_verify": {
                "scenarios": n_bank_verified, "mismatches": 0,
                "note": "파일 재독 -> record 파싱 -> 명령 재구성 -> "
                        "실행기 재실행 -> 인코딩된 기대 전 필드 재대조",
                "verdict": "PASS"},
        },
        "spec_gap_notes": [
            "[폐쇄 2026-08-16 — ③ spec COMMIT, §27.2.2 하류 ③ 블록] "
            "FILL-valid 이나 lattice-표현 밖 carry 의 RTL fault 클래스: "
            "신규 클래스 없이 기존 fault (d)/(e) 의 carry-lane 적용 "
            "(범위 <-> (d), 정밀도 <-> (e)), 발화 = carry 소비 (beat 0). "
            "golden LatticeFault 2종이 그 대응이고 bank 시나리오 "
            "carry_fault_* family 가 시나리오 레벨 reference 를 운반한다",
            "fp64 -0 FILL 은 수용 + canonical +0 화 — round-trip "
            "bit-exact 보증의 유일한 수용-후-재작성 예외",
            "f16 subnormal 곱의 lane-측 raw operand 형태는 RTL C2 경로 "
            "확정 사항 — 본 벡터는 값-충실 normalized 인코딩 사용",
            "bank 시나리오 레벨은 fill_owner/FillFaultForeign (외래 "
            "spill image 주소) 를 다루지 않는다 — §27.6 검증 계획 (a) "
            "의 TLC 반례 trace 변환이 담당 (bank_scenarios_contract.md "
            "머리말)",
        ],
        "verdicts": {
            "all_checks_pass": True,
            "theorem_identity_zero_mismatch": True,
            "permutation_bit_identical": True,
            "jam_families_match_study_exactly": True,
            "canonical_zero_on_exact_zero": True,
            "segment_2_of_9_never_exceeded":
                em.max_span <= 2 and cem.max_span <= 2,
            "pin1_open_interval_enforced": True,
            "bank_scenarios_self_verified": True,
            "cluster_vectors_self_verified": True,
            "window_offset_crossproduct_exhaustive": True,
        },
    }
    REPORT_PATH.write_text(json.dumps(report, indent=1, allow_nan=False,
                                      ensure_ascii=False) + "\n")
    print("wrote %s" % VEC_PATH)
    print("wrote %s" % CONTRACT_PATH)
    print("wrote %s" % CLUSTER_VEC_PATH)
    print("wrote %s" % CLUSTER_CONTRACT_PATH)
    print("wrote %s" % BANK_HEX_PATH)
    print("wrote %s" % BANK_CONTRACT_PATH)
    print("wrote %s" % REPORT_PATH)
    print("total %.1fs" % (time.time() - t_start))
    print("headlines:")
    print("  vectors: %d (families %d), blake2b512 %s"
          % (len(em.lines), len(em.families),
             report["vector_file"]["blake2b512"][:16]))
    print("  theorem sweep: %d waves, 0 mismatch (+%d per-vector)"
          % (theorem["N"], len(em.lines)))
    print("  oracle: fp64 struct %d, f32 struct %d checked"
          % (codec["N"], theorem["f32_struct_oracle_checked"]))
    print("  bank scenarios: %d (families %d, records %d), blake2b512 %s"
          % (len(bank_scens), len(bank_fams), n_bank_rec,
             report["bank_reference"]["scenario_file"]["blake2b512"][:16]))
    print("  bank coverage: chain7 %d / chain8 %d / window-fault %d / "
          "after-window %d / reject %d / carry (d)+(e) %d"
          % (bank_cov["chain_delta7"], bank_cov["chain_delta8"],
             bank_cov["window_fill"] + bank_cov["window_drain"]
             + bank_cov["window_zero"] + bank_cov["window_chain"],
             bank_cov["fdz_after_window"], bank_cov["reject_own"],
             bank_cov["carry_range_d"] + bank_cov["carry_precision_e"]))
    print("  bank spill/unk guard: spill_ok %d / window_spill %d / "
          "spill_owner %d / proto_unk %d"
          % (bank_cov["spill_ok"], bank_cov["window_spill"],
             bank_cov["spill_owner"], bank_cov["proto_unk"]))
    print("  cluster vectors: %d (families %d, %d operand pairs "
          "crosschecked), blake2b512 %s"
          % (len(cem.lines), len(cem.families), cem.n_pairs_checked,
             report["cluster_vectors"]["blake2b512"][:16]))
    print("  window x offset crossproduct: " + "; ".join(
        "%s={%s}" % (k.replace("window_", ""), ",".join(map(str, v)))
        for k, v in bank_xprod.items()))
    print("  ghost disposition (V20-3 1(iii)): DT-04(h)/DT-05(l) 모두 "
          "계약 재배정 — bank_scenarios_contract.md §10 / report "
          "gate_v20_3_carryover")


if __name__ == "__main__":
    main()
