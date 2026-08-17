#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""FDOT32_CR (0x7A) — §27.7a 확정 규범의 golden EFT twin (3a-C1,
golden-before-RTL; 착지 순서 §27.7a.4 의 C1 단계).

§27.7a.2 알고리즘을 단계 그대로 (sequencer-faithful) 구현한다 — RTL
(3a-C3 step 프로그램 / 3a-C4 TB) 이 이 단계 분해를 그대로 미러링한다:

  STEP M  곱 (exact)      bf16 8x8->16b / f16 11x11->22b significand 곱
                          (FP_Mul36 재사용 계약), p_exp 합 signed-11.
                          곱 지점 반올림 0회. operand classify 는
                          FP_FmaLaneBf16 S1 과 동일: bf16 exp field 0 ->
                          canonical zero 기여 (DAZ), f16 subnormal ->
                          leading-one normalize 후 exact 기여,
                          NaN/Inf -> 전용 sticky + qNaN (아래 specials).
  STEP T  TwoSumExact     vacuous-RTO 1 AddWide pass: 정렬 span <= 48 이면
                          48-bit 창의 exact 합 (RTO-48 이 vacuous — 구조
                          증명을 매 호출 assert) + 24|24 field-slice split
                          (hi + lo == s exact); 완전 비겹침 (span > 48)
                          이면 pass 없이 (큰 쪽, 작은 쪽) — 어느 분기에도
                          오차항 없음. RN 전제 정리 (Knuth/Fast2Sum) 에
                          일절 무의존.
  STEP I  grow-expansion  비겹침 component 열 (용량 33 = 32 삽입 +
                          carry 1; FDOT32_CR 은 bank 무접촉 32항 dot 라
                          자연 도달 <= 32) 에 곱 32개를 lane 순서로 순차
                          삽입. 매 스텝 3종 assert: 비겹침·길이(용량)·
                          exact-합-보존. 용량 초과 = loud fault
                          (never silent).
                          ** walk = 정련 walk (§27.7a.2 amendment-2) **
                          §27.7a.2 STEP I 의 문언 독해 (오름차순 chain
                          에서 merge 잔차 lo 를 즉시 확정 방출) 는
                          borrow 가 잔차를 다음 component 의 LSB 위로
                          확장시키는 입력에서 **같은 절이 pin 한 비겹침
                          invariant 를 스스로 위반**한다 (report 의
                          checks.spec_literal_walk_annex — 결정 반례 +
                          고정-seed 밀도 실측). 문언대로면 invariant
                          FAIL, invariant 를 지키면 문언 이탈 — 명세
                          자기모순이므로 정련 walk 을 정식 pin 으로
                          승격했다. 정련 walk = 같은 산술 표면 (겹침 쌍의
                          exact AddWide merge + 24|24 split) 을 유지한
                          "최저 2개 순서 merge": (e,top) 오름차순
                          대기열에서 최저 component 가 나머지 전부와
                          비겹침이면 확정 방출, 아니면 다음 최저와 exact
                          merge 후 split 조각을 대기열에 재삽입. 겹침
                          쌍은 span < 48 이 구조적이라 모든 pass 가
                          무반올림 exact (vacuous-RTO 강화형),
                          비겹침·오름차순은 구성적으로 성립하며 매 스텝
                          assert 로 재확인.
  STEP F  descending fold **내림차순** RTO-48 fold (§27.7a.2
                          amendment-1) — 최상위 component 부터 내려가며
                          pass 마다 FP_AddWide PACK_WIDE (exact 합 ->
                          top-48 + sticky-jam = RTO_48).
                          원 pin 은 "오름차순" 이었고 **C1 실측이 그
                          pin 을 부정했다** (값 계약 반례 2건, 상대오차
                          24%). 오름차순은 큰 component 가 나중에
                          도착하므로 상단 인접 상쇄가 항상 jam 이후에
                          일어나 jam 표식이 값으로 승격된다 — 구조적
                          결함이며 scope 축소로 구제되지 않는다.
                          내림차순은 모든 상쇄를 acc 가 아직 exact 인
                          동안 소진시키고, 첫 실질 jam 이후 acc 가
                          freeze 되므로 "fold == RTO_48(exact)" 가
                          **임의의 비겹침 오름차순 열에 대해** 성립한다
                          (증명은 STEP F 블록 주석). 정리 지위는 §25.4
                          대로 golden 졸업 대상으로 남기며, jam 마진과
                          freeze 를 매 trial 계측한다.
  STEP P  PACK_FINAL      단일 unbounded RNE-24 + flush-after-round FTZ
                          + overflow -> ±Inf + exact-cancellation -> +0.
                          rounding core = scripts/golden_fp32.pack_rne_ftz
                          (acc_format_study.pack_signed 경유 — 값 계약의
                          규범 원천인 true-B 경로 그대로, 중복 구현 금지).

값 계약 (§27.7a.1): r == pack_signed(exact Σ a_i·b_i) BIT-동일. 본
스크립트는 전 trial 에서 EFT 결과를 이 exact reference 와 비트 비교한다.

specials (§27.7a.1, audit 경로): NaN/Inf operand (sNaN 포함, Inf×0 포함)
-> 결과 = canonical qNaN 0x7FC00000 + 전용 sticky. main path 대조 축은
값이 아니라 sticky 유무 — main 은 canonical zero 기여 + LANE_SPECIAL
sticky + wave writeback 억제 (drain 산출 클래스는 finite/±Inf/±0 뿐,
NaN 절대 불산출 — qNaN marker 무모호성의 근거). 본 golden 은 두 경로를
나란히 산출해 대조 축 성립을 실증한다.

invariant (§27.7a.3): 비-special 입력의 single-wave 즉시-drain 에서
FDOT32_CR == main path (golden_lattice.wave_step, carry = canonical
zero) BIT-EXACT — 본 스크립트가 sweep 으로 실측한다.

인용 규율 (§27.7a.5): §27.7 sketch 의 "66k+" 는 salted-seed 라 인용
불가 — 본 C1 이 고정-seed EFT 경로 카운트 (>= 40,000 value-contract
trial, 0 mismatch 의무) 를 생성해 승계·졸업시킨다. 재실행 byte-identical.

산출물 (전부 결정적 — 고정 seed, timestamp 없음):
  include/generated/fdotcr_vectors.hex        RTL TB 벡터 ($readmemh) —
                                              operand 1,024b A||B (§27.7a.1
                                              frag 배치 그대로) + 기대 결과
  include/generated/fdotcr_vec_contract.md    벡터 비트 레이아웃/의미 계약
  include/generated/fdotcr_golden_report.json 카운트·sha256·정리 실측 결과

ground truth 는 exact 정수/(m,e)/Fraction 산술, stdlib-only. 기존 golden
산출물 (lattice/bank/cluster) 은 본 스크립트가 접촉하지 않는다.
"""

import hashlib
import json
import random
import sys
import time
from fractions import Fraction
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
GEN = REPO / "include" / "generated"
VEC_PATH = GEN / "fdotcr_vectors.hex"
CONTRACT_PATH = GEN / "fdotcr_vec_contract.md"
REPORT_PATH = GEN / "fdotcr_golden_report.json"
sys.path.insert(0, str(Path(__file__).resolve().parent))

from golden_fp32 import (DT_BF16, DT_F16, F32_QNAN,  # noqa: E402
                         frags_to_lanes, lanes_to_frags)
import acc_format_study as STUDY  # noqa: E402  (true-B 경로 + (m,e) 기계)
import golden_lattice as LAT  # noqa: E402  (main path wave_step + operand 관례)

TWO = Fraction(2)
GROUP = LAT.GROUP               # 32 lanes = 32항 dot
W24 = 24                        # component significand 폭 (§27.7a.2)
Q48 = 48                        # FP_AddWide / PACK_WIDE significand 폭
EXP_CAP = 33                    # expansion 용량 (32 삽입 + carry 1)
_M64 = (1 << 64) - 1
_M1024 = (1 << 1024) - 1

VEC_BITS = 32 + 1024 + 32       # META + A||B payload + RESULT = 1088
VEC_HEX = VEC_BITS // 4         # 272

# 고정 seed — 결정론의 유일한 난수원 (salted-seed 금지, §27.7a.5)
SEEDS = {
    "eft_bf16_wide": 0x7ADC001,
    "eft_f16_all": 0x7ADC002,
    "eft_cancel": 0x7ADC003,
    "eft_cancel_chain": 0x7ADC004,
    "eft_tie": 0x7ADC005,
    "eft_ladder": 0x7ADC006,
    "eft_same": 0x7ADC007,
    "eft_pack_edge": 0x7ADC008,
    "eft_adv_residue": 0x7ADC009,
    "eft_top_cancel": 0x7ADC00A,
    "invariant": 0x7ADC011,
    "special_rand": 0x7ADC012,
    "fold_synth": 0x7ADC013,
    "special_det_bg": 0x7ADC014,
    "spec_literal_walk": 0x7ADC015,
}

# EFT 랜덤 가족 trial 수 (합계 45,000). §27.7a.5 (a) 는 "재생성 고정-seed
# 36,000 **재사용**" 을 선공표했으나, 그 36,000 은 acc_format_study 의 곱
# (m,e) 수준 스트림이라 §27.7a.1 의 A||B operand 인터페이스에 그대로 투입
# 할 수 없다 — 동일 성격 (cancellation/tie/wide) 을 operand 수준에서
# 재구성해 **신규 고정 seed** 로 생성한다. 이 대체 사실은 report 의
# prannounced_plan_conformance.a_value_contract_stream 과 spec
# §27.7a.2a amendment-6 에 명기한다 (재해석만 남기지 않는다, §12a 규칙 5).
N_FAM = {
    "eft_bf16_wide": 9000,
    "eft_f16_all": 7000,
    "eft_cancel": 6000,
    "eft_cancel_chain": 4000,
    "eft_tie": 5000,
    "eft_ladder": 3000,
    "eft_same": 3000,
    "eft_pack_edge": 3000,
    "eft_adv_residue": 2000,
    "eft_top_cancel": 3000,     # C1 반례 메커니즘 표적 (신설, 3a-C1)
}
N_INVARIANT = 12000
N_SPECIAL_RAND = 496
N_SYNTH = 20000
N_LITERAL_WALK = 3000           # §27.7a.2 문언 walk 위반 밀도 실측
VEC_PER_FAM = 30                # 가족별 벡터 파일 수록 수 (앞에서부터)

_ZP = (0, 0)                    # zero operand 쌍 (±0 인코딩 0x0000)


class FdotFault(Exception):
    """loud fault — never silent (프로젝트 법칙). RTL 대응은 합성 가능한
    sticky status bit 클래스 (§27.7a.1 sticky / §26.5 선례)."""


# ===========================================================================
# STEP M — operand classify + exact 곱 (FP_FmaLaneBf16 S1 / FP_Mul36 twin)
# component = (m, e): 값 = m * 2^e, 0 < |m| < 2^24, e 는 signed-11 수납
# ===========================================================================


def lane_classify(dtype, bits):
    """FDOT32_CR capture classify — §27.7a.1 의 (i)/(ii)/(iii) 행 그대로.
    returns ('special', None) | ('zero', None) | ('fin', (s, m_norm, e)).
    m_norm: bf16 [2^7,2^8) / f16 [2^10,2^11) (subnormal 은 S1 leading-one
    normalize — exact), e = leading bit 의 지수 (binade)."""
    assert 0 <= bits <= 0xFFFF
    s = (bits >> 15) & 1
    if dtype == DT_BF16:
        E, m = (bits >> 7) & 0xFF, bits & 0x7F
        if E == 0xFF:
            return "special", None          # NaN/Inf (sNaN 포함)
        if E == 0:
            return "zero", None             # zero + 전 254 subnormal (DAZ)
        return "fin", (s, 128 + m, E - 127)
    if dtype == DT_F16:
        E, m = (bits >> 10) & 0x1F, bits & 0x3FF
        if E == 0x1F:
            return "special", None
        if E == 0:
            if m == 0:
                return "zero", None
            k = 11 - m.bit_length()         # subnormal: exact normalize
            return "fin", (s, m << k, -14 - k)
        return "fin", (s, 1024 + m, E - 15)
    raise FdotFault("FDOT32_CR dtype must be 0x2 (f16) / 0x3 (bf16): 0x%X"
                    % dtype)


def lane_product(dtype, a, b):
    """STEP M: exact significand 곱 + 지수 합 — 반올림 0회 (§27.7a.2).
    returns ('special'|'zero'|'fin', comp) — comp = (m, e) 곱 component
    (bf16 |m| < 2^16 / f16 |m| < 2^22 — 즉시 1 component 수납)."""
    ka, fa = lane_classify(dtype, a)
    kb, fb = lane_classify(dtype, b)
    if ka == "special" or kb == "special":
        return "special", None
    if ka == "zero" or kb == "zero":
        return "zero", None
    sa, ma, ea = fa
    sb, mb, eb = fb
    frac = 7 if dtype == DT_BF16 else 10
    m = ma * mb
    assert m.bit_length() < W24
    if sa ^ sb:
        m = -m
    return "fin", (m, ea + eb - 2 * frac)


def _is_special_operand(dtype, bits):
    if dtype == DT_BF16:
        return ((bits >> 7) & 0xFF) == 0xFF
    return ((bits >> 10) & 0x1F) == 0x1F


# ===========================================================================
# component 기하
# ===========================================================================


def comp_ok(c):
    m, e = c
    if m == 0 or abs(m) >= (1 << W24):
        raise FdotFault("component significand out of W=24: %r" % (c,))
    if not -1024 <= e <= 1023:
        raise FdotFault("component exponent outside signed-11: %r" % (c,))


def comp_top(c):
    """exclusive top: 2^(top-1) <= |값| < 2^top 의 top (= e + bl(|m|))."""
    return c[1] + abs(c[0]).bit_length()


# ===========================================================================
# STEP T — TwoSumExact: vacuous-RTO 1 AddWide pass (§27.7a.2)
# ===========================================================================


def two_sum_exact(x, y):
    """returns ("disjoint", big, small) — span > 48: pass 없음, 그대로
         or ("merge", hi, lo) — 48-bit 창 exact 합의 24|24 split
                                (hi=None ⇔ 정확 상쇄; lo=None ⇔ 잔차 0).
    vacuous-RTO 증명 의무: merge 분기의 정렬 합은 반드시 <= 48 bit —
    위반은 loud fault (spec §27.7a.2 (ii) 의 구조 성질)."""
    comp_ok(x)
    comp_ok(y)
    (mx, ex), (my, ey) = x, y
    emin = ex if ex < ey else ey
    span = max(comp_top(x), comp_top(y)) - emin
    if span > Q48:
        # 완전 비겹침 (W=24 두 component 에서 span>48 ⇒ 범위 분리)
        if ex >= comp_top(y):
            return "disjoint", x, y
        if ey >= comp_top(x):
            return "disjoint", y, x
        raise FdotFault("span>48 but ranges overlap: %r %r" % (x, y))
    S = (mx << (ex - emin)) + (my << (ey - emin))
    if S == 0:
        return "merge", None, None
    a = -S if S < 0 else S
    bl = a.bit_length()
    if bl > Q48:
        raise FdotFault("vacuous-RTO violated: aligned sum %d bits" % bl)
    if bl <= W24:
        return "merge", (S, emin), None
    sh = bl - W24                           # 24|24 field-slice split
    sgn = -1 if S < 0 else 1
    lo_a = a & ((1 << sh) - 1)
    hi = (sgn * (a >> sh), emin + sh)
    lo = (sgn * lo_a, emin) if lo_a else None
    return "merge", hi, lo


# ===========================================================================
# STEP I — grow-expansion 삽입 (매 스텝 3종 assert: 비겹침·용량·합-보존)
# ===========================================================================


def _insort(pend, c):
    """(e, top) 오름차순 대기열 삽입 (열 길이 <= ~40 — 선형 스캔).

    반환 = 선형 스캔의 비교 횟수. 이 값은 step sequencer 의 **대기열
    유지 비용** 이며 AddWide pass 수 (twosum_passes) 에 계상되지 않는다
    — §27.7a.2a amendment-3 이 "미계상, 3a-C3 실측 축" 으로 명시 기록한
    항목이라 여기서 계측해 report (checks.insertion_queue_cost) 에
    싣는다 (주장 대신 실측 — §25.4)."""
    comp_ok(c)
    key = (c[1], comp_top(c))
    i = 0
    while i < len(pend) and (pend[i][1], comp_top(pend[i])) <= key:
        i += 1
    pend.insert(i, c)
    return i + 1


def grow_insert(expansion, q, stats):
    """정련 walk — "최저 2개 순서 merge" (모듈 docstring STEP I 참조).
    (e, top) 오름차순 대기열에서: 최저 component a 가 다음 최저 b 와
    비겹침 (top(a) <= e_b) 이면 a 는 남은 전부의 아래 ⇒ 확정 방출;
    겹침이면 a+b 를 exact AddWide merge (겹침 ⇒ span < 48 구조 보장 —
    vacuous-RTO 강화형) 후 24|24 split 조각을 재삽입. 반환 = 새 열
    (비겹침·오름차순 구성적 성립 + 매 스텝 assert)."""
    for _k in ("insort_steps", "insort_calls", "merge_count",
               "merge_width_max"):
        stats.setdefault(_k, 0)
    pend = list(expansion)                  # 오름차순 유지 (assert 재확인)
    stats["insort_steps"] += _insort(pend, q)
    stats["insort_calls"] += 1
    out = []
    chain = 0
    iters = 0
    while pend:
        iters += 1
        if iters > 4000:
            raise FdotFault("insertion walk did not terminate")
        a = pend.pop(0)
        if not pend:
            out.append(a)
            break
        b = pend[0]
        if comp_top(a) <= b[1]:             # a 는 남은 전부의 아래 — FINAL
            out.append(a)
            continue
        pend.pop(0)                         # 겹침 — 1 AddWide pass (exact)
        chain += 1
        stats["merge_count"] += 1
        emin = a[1] if a[1] < b[1] else b[1]
        S = (a[0] << (a[1] - emin)) + (b[0] << (b[1] - emin))
        if S == 0:
            continue                        # 정확 상쇄
        aa = -S if S < 0 else S
        bl = aa.bit_length()
        # 정렬합 폭 계측 — 계약(=fault 경계)은 Q48, 아래 max 는 실측치
        # (§27.7a.2a amendment-2 의 "vacuous-RTO 강화" 주장을 report
        # 필드 merge_aligned_width_max 로 고정한다; 정확상쇄 merge 는
        # S == 0 이라 폭이 없고 merge_count 에만 계상된다).
        if bl > stats["merge_width_max"]:
            stats["merge_width_max"] = bl
        if bl > Q48:
            raise FdotFault("vacuous-RTO violated: aligned sum %d bits"
                            % bl)
        if bl <= W24:
            stats["insort_steps"] += _insort(pend, (S, emin))
            stats["insort_calls"] += 1
            continue
        sh = bl - W24                       # 24|24 field-slice split
        sgn = -1 if S < 0 else 1
        lo_a = aa & ((1 << sh) - 1)
        stats["insort_steps"] += _insort(pend, (sgn * (aa >> sh), emin + sh))
        stats["insort_calls"] += 1
        if lo_a:
            stats["insort_steps"] += _insort(pend, (sgn * lo_a, emin))
            stats["insort_calls"] += 1
    stats["twosum_passes"] += chain
    if chain > stats["max_chain"]:
        stats["max_chain"] = chain
    # 3종 assert ① 용량 (초과 = loud fault, "도달 불가" 주장으로 대체 금지)
    if len(out) > EXP_CAP:
        raise FdotFault("expansion capacity %d exceeded: %d components"
                        % (EXP_CAP, len(out)))
    # 3종 assert ② 비겹침·오름차순 (구성적 성립의 재확인)
    for i in range(1, len(out)):
        if comp_top(out[i - 1]) > out[i][1]:
            raise FdotFault("expansion nonoverlap/ascending violated: "
                            "%r then %r" % (out[i - 1], out[i]))
    return out


# ---------------------------------------------------------------------------
# naive walk annex — §27.7a.2 소박한 독해의 결정적 반례 (재개정 근거)
# ---------------------------------------------------------------------------


def naive_grow_insert(expansion, q):
    """§27.7a.2 의 소박한 독해: 오름차순 chain, span<=48 이면 TwoSumExact
    후 잔차 lo 를 즉시 확정 방출, span>48 이면 (큰 쪽, 작은 쪽) 그대로.
    이 독해는 비겹침 invariant 를 위반할 수 있다 — annex 실증 전용."""
    out = []
    carry = q
    idx, n = 0, len(expansion)
    while idx < n and carry is not None:
        comp = expansion[idx]
        kind, big, small = two_sum_exact(carry, comp)
        if kind == "disjoint":
            if small == carry:
                out.append(carry)
                carry = None
                break
            out.append(small)
            idx += 1
            continue
        if small is not None:
            out.append(small)
        carry = big
        idx += 1
    out.extend(expansion[idx:])
    if carry is not None:
        out.append(carry)
    return out


def spec_literal_walk_annex():
    """§27.7a.2 STEP I 문언 (TwoSumExact chain — span<=48 merge, 잔차 lo
    즉시 확정 방출) 이 **같은 절이 pin 한 비겹침 invariant 를 스스로
    위반**함을 실측·기록한다 (§27.7a.2 amendment-2 의 근거).

    (a) 결정 반례: column [(3,-25), (265106,-20)] 에 q = (-2^23, -1) 삽입.
        문언 walk 은 q 와 (3,-25) 를 span=48 로 merge, borrow 가 잔차 lo
        를 [-25,-2) 전폭으로 확장시켜 (265106,-20) [-20,-2) 와 겹친 채
        확정 방출한다 — 비겹침 위반. 정련 walk 는 올바르게 처리한다.
    (b) 고정-seed 밀도 실측: 문언 walk 을 실제 operand 가족에 걸어
        비겹침 위반 trial 비율을 센다. "드문 모서리" 가 아니라 상시
        위반임을 수치로 남긴다 (§25.4 — 주장 대신 실측).
    (c) 문언 walk 은 값 축에서도 안전하지 않다: 그 산출 열은 비겹침이
        아니므로 fold 정리의 전건을 만족하지 않는다 — 채택된 내림차순
        fold 를 그 열에 걸면 실제로 깨진다 (같은 sweep 에서 계측).
    """
    col = [(3, -25), (265106, -20)]
    q = (-(1 << 23), -1)
    naive = naive_grow_insert(col, q)
    viol = any(comp_top(naive[i - 1]) > naive[i][1]
               for i in range(1, len(naive)))
    st = {"twosum_passes": 0, "max_chain": 0}
    fixed = grow_insert(col, q, st)
    ok = all(comp_top(fixed[i - 1]) <= fixed[i][1]
             for i in range(1, len(fixed)))
    want = _exact_sum_me(col + [q])
    assert STUDY.veq_me(*_exact_sum_me(fixed), *want)
    assert viol and ok      # 문언 위반 + 정련 성립 — annex 의 존재 이유

    rng = random.Random(SEEDS["spec_literal_walk"])
    gens = [gen_bf16_wide, gen_f16_all, gen_cancel, gen_cancel_chain,
            gen_tie, gen_ladder, gen_pack_edge, gen_top_cancel]
    n = n_viol = n_ins = n_ins_viol = n_fold_break = 0
    for i in range(N_LITERAL_WALK):
        dtype, pairs = gens[i % len(gens)](rng)
        prods = []
        for a, b in pairs:
            k, me = lane_product(dtype, a, b)
            if k == "special":
                prods = None
                break
            if k == "fin":
                prods.append(me)
        if not prods:
            continue
        n += 1
        exp = []
        bad = False
        for pq in prods:
            exp = naive_grow_insert(exp, pq)
            n_ins += 1
            if any(comp_top(exp[j - 1]) > exp[j][1]
                   for j in range(1, len(exp))):
                bad = True
                n_ins_viol += 1
        if bad:
            n_viol += 1
            sm, se = _exact_sum_me(exp)
            tm, te = STUDY.rto_me(sm, se, Q48)
            fm, fe = 0, 0
            for c in reversed(exp):         # 채택 fold 를 문언 열에 적용
                fm, fe = addwide_rto48_me(fm, fe, c[0], c[1])
            if not (STUDY.veq_me(fm, fe, tm, te) if sm else fm == 0):
                n_fold_break += 1
    return {
        "_doc": "§27.7a.2 STEP I 의 문언 walk 이 같은 절의 비겹침 "
                "invariant 를 스스로 위반한다 — 문언대로 구현하면 "
                "invariant FAIL, invariant 를 지키면 문언 이탈. 명세 "
                "자기모순이므로 정련 walk 을 정식 pin 으로 승격한다 "
                "(§27.7a.2 amendment-2). 문언 walk 은 fold 정리의 "
                "전건 (비겹침) 도 파괴하므로 채택 불가.",
        "deterministic_case": {
            "column": [[3, -25], [265106, -20]],
            "insert_q": [-(1 << 23), -1],
            "spec_literal_result": [[c[0], c[1]] for c in naive],
            "spec_literal_nonoverlap_violated": viol,
            "refined_result": [[c[0], c[1]] for c in fixed],
            "refined_nonoverlap_ok": ok,
            "refined_exact_sum_preserved": True,
        },
        "density_sweep": {
            "seed": SEEDS["spec_literal_walk"],
            "trials": n,
            "trials_with_nonoverlap_violation": n_viol,
            "trial_violation_rate": (round(n_viol / n, 4) if n else None),
            "insertions": n_ins,
            "insertions_with_violation": n_ins_viol,
            "insertion_violation_rate": (round(n_ins_viol / n_ins, 4)
                                         if n_ins else None),
            "violating_columns_breaking_descending_fold": n_fold_break,
            "note": "문언 walk 산출 열은 비겹침이 아니므로 내림차순 "
                    "fold 정리의 전건 밖 — 실제로 깨진다 (위 카운트).",
        },
        "verdict": "SPEC LITERAL WALK REFUTED — 정련 walk 정식 pin",
    }


def _exact_sum_me(comps):
    m, e = 0, 0
    for c in comps:
        m, e = STUDY.add_me(m, e, c[0], c[1])
    return m, e


# ===========================================================================
# STEP F — descending RTO-48 fold (pass = FP_AddWide PACK_WIDE)
#
# §27.7a.2 종료 (2) amendment-1 (3a-C1 실측 개정). 원 pin 은 "ascending-
# magnitude RTO-48 fold" 였고, 그 근거 문언은 "각 pass 의 sticky-jam 이
# 정확히 '48-bit 창 아래 잔여 != 0' 를 운반한다" 였다. 이 근거는 거짓이다:
# sticky-jam 은 *그 pass 시점의* 창에 대해서만 "아래 잔여" 표식이며, 이후
# pass 가 상단 인접 상쇄로 창을 jam 위치 아래로 끌어내리면 표식이 값으로
# 승격된다 (C1 실측 반례 2건 — 상대오차 24%). 오름차순은 큰 component 가
# 나중에 도착하므로 상쇄가 항상 jam 이후에 일어난다 — 구조적 결함이다.
#
# 내림차순 fold 의 정리 (전건: 오름차순 저장 + 엄격 비겹침 top(c_i) <=
# e_{i+1} + W <= 24; STEP I 가 매 삽입 assert):
#   (1) 첫 실질 jam 이전의 모든 pass 는 무반올림 exact ⇒ acc_k = P_k :=
#       Σ_{i>=k} c_i. 상쇄는 acc 와 크기가 비견되는 상대와만 일어나고,
#       비겹침 하에서 그 상대는 항상 '바로 아래' component 다 ⇒ 모든
#       상쇄가 jam 이전에 exact 로 해소된다.
#   (2) index k 에서 실질 jam ⇔ P_k 가 grid p := top(P_k) - 48 의 배수가
#       아님 ⇒ e_k < p. 비겹침 telescoping 으로 남은 꼬리 전체가
#       |R| = |Σ_{i<k} c_i| <= 2^{top(c_{k-1})} - 2^{e_0} < 2^{e_k} < 2^p.
#   (3) P_k 의 cell 내 offset r 은 2^{e_k} 의 배수이고 0 이 아니므로
#       r ∈ [2^{e_k}, 2^p - 2^{e_k}] — |R| < 2^{e_k} 로는 cell 을 벗어날
#       수도 exact 가 될 수도 없다 ⇒ RTO_48(Σ) == RTO_48(P_k) == acc_k,
#       그리고 top(Σ) == top(P_k).
#   (4) acc_k 는 grid p 에서 홀수 (RTO) 이므로 |c| < 2^p 의 이후 가산은
#       인접 두 cell 안에 머물고, 절단 후 LSB set 이 정확히 acc_k 를
#       되돌린다 ⇒ **freeze** (acc 가 더 이상 변하지 않는다).
#   ∴ fold_descending == RTO_48(exact 합) — 임의의 비겹침 오름차순 열에
#   대해 성립 (일반형; scope 축소 불요). 이어 §27.2.1 추출 정리
#   RNE_24(RTO_48(x)) == RNE_24(x) 로 §27.7a.1 값 계약이 닫힌다.
#
# 졸업 지표 (§25.4): jam 위치 p 와 최종 top(T) 의 마진 (p <= top(T) - 25
# 이면 최종 RNE-24 가 jam 오차를 흡수) + freeze 를 매 trial 계측한다 —
# 정리가 어디서 깨지는지 기계로 관측 가능하게 유지하기 위함이다.
# ===========================================================================


def addwide_rto48_me(am, ae, bm, be):
    """FP_AddWide 1 pass: exact wide 합 -> top-48 + sticky-jam (RTO_48).
    STUDY.add_me / rto_me — golden_fp32._rto core, 중복 구현 없음."""
    m, e = STUDY.add_me(am, ae, bm, be)
    return STUDY.rto_me(m, e, Q48)


def fold_descending(expansion, stats):
    """내림차순 fold (최상위 component 부터). 빈 열 -> (0,0) = canonical
    zero (exact-상쇄 -> +0). 정리·전건은 위 블록 주석 참조.

    stats 에 졸업 지표를 적재한다:
      jam_grid_p    첫 실질 jam 의 grid LSB 위치 (없으면 None)
      jam_margin    top(최종 acc) - p  (>= 25 이면 RNE-24 가 흡수)
      freeze_ok     첫 실질 jam 이후 acc 불변 (정리 (4) 의 실측)
    """
    am, ae = 0, 0
    jam_p = None
    jam_acc = None
    freeze_ok = True
    for c in reversed(expansion):
        pm, pe = STUDY.add_me(am, ae, c[0], c[1])
        am, ae = STUDY.rto_me(pm, pe, Q48)
        stats["fold_passes"] += 1
        if jam_p is None:
            if not STUDY.veq_me(am, ae, pm, pe):        # 첫 실질 jam
                jam_p = ae
                jam_acc = (am, ae)
        elif not STUDY.veq_me(am, ae, *jam_acc):        # freeze 위반?
            freeze_ok = False
            jam_acc = (am, ae)
    stats["jam_grid_p"] = jam_p
    stats["freeze_ok"] = freeze_ok
    if jam_p is None or am == 0:
        stats["jam_margin"] = None
    else:
        stats["jam_margin"] = (ae + abs(am).bit_length()) - jam_p
    if not freeze_ok:                       # loud — 정리 (4) 붕괴
        raise FdotFault("descending fold freeze violated: %r" % (expansion,))
    return am, ae


# ===========================================================================
# STEP P — PACK_FINAL (값 계약의 규범 원천 = acc_format_study true-B 경로)
# ===========================================================================


def pack_final_me(m, e):
    """단일 unbounded RNE-24 + flush-after-round FTZ + overflow ±Inf +
    exact zero -> +0. STUDY.pack_signed == pack_rne_ftz(golden_fp32)."""
    if m == 0:
        return 0x00000000
    return STUDY.pack_signed(Fraction(m) * TWO ** e)


# ===========================================================================
# FDOT32_CR reference (audit 경로 전체) + main path twin
# ===========================================================================


def fdotcr_ref(dtype, pairs):
    """§27.7a 전 단계: classify -> 곱 -> 삽입 -> fold -> PACK_FINAL.
    specials 는 EFT 미진입: qNaN 0x7FC00000 + sticky (§27.7a.1 (iii)).
    반환 dict 에 값 계약 우변 (ref_bits = pack_signed(exact)) 과 fold
    정리 실측 (fold_ok) 을 나란히 담는다 — mismatch 는 호출측이 집계
    (감추지 않고 보고하기 위해 여기서 raise 하지 않는다)."""
    assert dtype in (DT_F16, DT_BF16) and len(pairs) == GROUP
    prods = []
    n_special = 0
    for a, b in pairs:
        k, me = lane_product(dtype, a, b)
        if k == "special":
            n_special += 1
        elif k == "fin":
            prods.append(me)
    if n_special:
        return {"special": True, "sticky": True, "bits": F32_QNAN,
                "n_special": n_special, "n_products": len(prods)}
    stats = {"twosum_passes": 0, "max_chain": 0, "fold_passes": 0,
             "exp_max": 0, "insort_steps": 0, "insort_calls": 0,
             "merge_count": 0, "merge_width_max": 0}
    expansion = []
    sm, se = 0, 0                           # exact 누적 합 (m,e)
    for i, q in enumerate(prods):
        expansion = grow_insert(expansion, q, stats)
        sm, se = STUDY.add_me(sm, se, q[0], q[1])
        xm, xe = _exact_sum_me(expansion)   # 3종 assert ③ exact-합-보존
        if not STUDY.veq_me(xm, xe, sm, se):
            raise FdotFault("exact-sum preservation violated at insert %d"
                            % i)
        if len(expansion) > stats["exp_max"]:
            stats["exp_max"] = len(expansion)
    fm, fe = fold_descending(expansion, stats)
    tm, te = STUDY.rto_me(sm, se, Q48)      # RTO_48(exact) — 정리 우변
    fold_ok = STUDY.veq_me(fm, fe, tm, te) if sm else fm == 0
    bits = pack_final_me(fm, fe)
    ref_bits = pack_final_me(sm, se)        # 값 계약 우변 (true-B)
    return {"special": False, "sticky": False, "bits": bits,
            "ref_bits": ref_bits, "value_ok": bits == ref_bits,
            "fold_ok": fold_ok, "n_special": 0, "n_products": len(prods),
            "expansion": expansion, "stats": stats,
            "exact_me": (sm, se), "fold_me": (fm, fe)}


def main_twin(dtype, pairs):
    """main path 즉시-drain twin (§27.7a.3): golden_lattice.wave_step,
    carry = canonical zero (0x7E 선행/리셋 상태). special lane 은
    canonical zero 기여 + LANE_SPECIAL sticky + writeback 억제 — drain
    값은 '억제된 가상값' 으로 산출해 NaN 불산출 (marker 무모호) 을
    실증한다."""
    cl = 0 if dtype == DT_BF16 else 1       # cluster 층 dtype 관례
    prods = []
    n_special = 0
    for a, b in pairs:
        if _is_special_operand(dtype, a) or _is_special_operand(dtype, b):
            n_special += 1
            prods.append(LAT.CANON_ZERO)    # canonical zero 기여
        else:
            prods.append(LAT.lane_product_addend(cl, a, b))
    _, _, _, f32 = LAT.wave_step(prods, LAT.CANON_ZERO)
    st = n_special > 0
    return {"sticky": st, "suppressed": st, "drain": f32,
            "n_special": n_special}


def _is_nan_f32(bits):
    return ((bits >> 23) & 0xFF) == 0xFF and (bits & 0x7FFFFF) != 0


def _crosscheck_products_frac(dtype, pairs):
    """EFT 곱 decode 를 Fraction 독립 경로 (golden_lattice.operand_frac)
    와 교차검증 — 비-special 입력 전용 (subset 호출)."""
    cl = 0 if dtype == DT_BF16 else 1
    n = 0
    for a, b in pairs:
        k, me = lane_product(dtype, a, b)
        f = LAT.operand_frac(cl, a) * LAT.operand_frac(cl, b)
        if k == "fin":
            assert Fraction(me[0]) * TWO ** me[1] == f
        else:
            assert k == "zero" and f == 0
        n += 1
    return n


# ===========================================================================
# operand 쌍 생성기 (전부 고정 seed rng 인자 경유; (dtype, pairs) 반환)
# ===========================================================================


def _split_e_bf16(rng, e):
    """곱 지수 e (= Ea+Eb-14) 를 operand 지수 쌍으로 분해."""
    Es = e + 14
    assert -252 <= Es <= 254, e
    Ea = rng.randint(max(-126, Es - 127), min(127, Es + 126))
    return Ea, Es - Ea


def mk_bf16_pair(rng, e, sign, a8=None, b8=None):
    """곱 == ±(a8*b8)·2^e 인 bf16 operand 쌍 (a 측이 부호 보유)."""
    if a8 is None:
        a8 = rng.randrange(128, 256)
    if b8 is None:
        b8 = rng.randrange(128, 256)
    Ea, Eb = _split_e_bf16(rng, e)
    return (LAT.bf16_bits(sign, Ea, a8), LAT.bf16_bits(0, Eb, b8))


def mk_f16_pair(rng, e, sign, m11a=None, m11b=None):
    """곱 == ±(m11a*m11b)·2^e 인 f16 normal 쌍 (e = Ea+Eb-20 ∈ [-48,10])."""
    if m11a is None:
        m11a = rng.randrange(1024, 2048)
    if m11b is None:
        m11b = rng.randrange(1024, 2048)
    Es = e + 20
    assert -28 <= Es <= 30, e
    Ea = rng.randint(max(-14, Es - 15), min(15, Es + 14))
    return (LAT.f16_bits(sign, Ea, m11a), LAT.f16_bits(0, Es - Ea, m11b))


def _pad(pairs):
    assert len(pairs) <= GROUP
    return pairs + [_ZP] * (GROUP - len(pairs))


def gen_bf16_wide(rng):
    return DT_BF16, LAT.cwave_bf16_rand(rng)


def gen_f16_all(rng):
    return DT_F16, LAT.cwave_f16_rand(rng)


def gen_cancel(rng):
    return DT_BF16, LAT.cwave_cancel(rng)


def gen_cancel_chain(rng):
    """대규모 상쇄 후 미세 잔차 (fold 적대 축 1): 임의 곱 4-8개 뒤에
    greedy top-8bit canceller 곱을 연쇄 — exact 합의 상위 비트를 반복
    소거해 깊은 상쇄 잔차를 남긴다. 삽입 순서 = lane 순서 유지."""
    pairs = []
    sm, se = 0, 0
    for _ in range(rng.randint(4, 8)):
        e = rng.randint(-30, 25)
        a8, b8 = rng.randrange(128, 256), rng.randrange(128, 256)
        s = rng.randint(0, 1)
        pairs.append(mk_bf16_pair(rng, e, s, a8, b8))
        sm, se = STUDY.add_me(sm, se, (-1 if s else 1) * a8 * b8, e)
    for _ in range(rng.randint(8, 14)):
        if sm == 0 or len(pairs) >= GROUP:
            break
        aa = -sm if sm < 0 else sm
        bl = aa.bit_length()
        if bl < 8:                          # 잔차가 8-bit 미만 — 종료
            break
        top8 = aa >> (bl - 8)               # [128, 256)
        e_val = se + bl - 8 - 7             # 곱 (top8·128)·2^e_val
        if not -266 <= e_val <= 240:
            break
        s = 0 if sm < 0 else 1              # 반대 부호
        pairs.append(mk_bf16_pair(rng, e_val, s, top8, 128))
        sm, se = STUDY.add_me(sm, se, (-1 if s else 1) * top8 * 128, e_val)
    return DT_BF16, _pad(pairs)


def gen_tie(rng):
    """24-bit RNE tie 인접 + bit-48 아래 dust — jam/sticky/tie 집중."""
    if rng.random() < 0.5:
        pairs = [(0x3F80, 0x3F80),                      # 1·1
                 (LAT.bf16_pow2(-12), LAT.bf16_pow2(-12))]  # 2^-24
        for _ in range(rng.randint(2, 6)):
            t = rng.randint(-62, -45)
            pairs.append(mk_bf16_pair(rng, t - 15, rng.randint(0, 1)))
        pairs = _pad(pairs)
        rng.shuffle(pairs)
        return DT_BF16, pairs
    pairs = [(0x3C00, 0x3C00), (0x0001, 0x3C00)]        # 1 + 2^-24 (f16)
    for _ in range(rng.randint(1, 4)):                  # subnormal dust
        pairs.append((LAT.f16_sub_bits(rng.randint(0, 1),
                                       rng.randint(1, 1023)),
                      LAT.f16_sub_bits(0, rng.randint(1, 1023))))
    pairs = _pad(pairs)
    rng.shuffle(pairs)
    return DT_F16, pairs


def gen_ladder(rng):
    """exponent ladder 2^-252..2^255 급 (§27.7a.5 (b)) — 인접 gap 을
    48 경계 근방 (49..52) 으로 걸어 expansion 최대 깊이 + rung 당 1-2곱
    (동일 지수 다수 component 적대 축)."""
    pairs = []
    e = -266 + rng.randint(0, 3)
    while e <= 238 and len(pairs) < GROUP:
        for _ in range(rng.randint(1, 2)):
            if len(pairs) < GROUP:
                pairs.append(mk_bf16_pair(
                    rng, min(e + rng.randint(0, 1), 240), rng.randint(0, 1)))
        e += rng.choice([49, 50, 51, 52])
    pairs = _pad(pairs)
    if rng.random() < 0.5:
        rng.shuffle(pairs)                  # 삽입 순서 적대 변형
    return DT_BF16, pairs


def gen_same(rng):
    """전부동일 32쌍 — 동일 곱 32회 삽입의 carry/split 체인."""
    if rng.random() < 0.5:
        p = (LAT.rand_bf16_operand(rng, -60, 60),
             LAT.rand_bf16_operand(rng, -60, 60))
        return DT_BF16, [p] * GROUP
    p = (LAT.rand_f16_operand(rng, 0.25), LAT.rand_f16_operand(rng, 0.25))
    if lane_classify(DT_F16, p[0])[0] == "zero":        # 전부-zero 회피
        p = (0x3C00, p[1])
    return DT_F16, [p] * GROUP


def gen_pack_edge(rng):
    """PACK_FINAL FTZ/overflow/+0 경계 (§27.7a.5 (b))."""
    mode = rng.randrange(3)
    if mode == 0:                           # overflow 대역 (|합| ~ 2^128)
        pairs = [mk_bf16_pair(rng, rng.randint(105, 126),
                              0 if rng.random() < 0.85 else 1)
                 for _ in range(rng.randint(4, GROUP))]
    elif mode == 1:                         # FTZ 대역 (|합| ~ 2^-126)
        pairs = [mk_bf16_pair(rng, rng.randint(-155, -125),
                              rng.randint(0, 1))
                 for _ in range(rng.randint(1, GROUP))]
    else:                                   # 정확 상쇄 -> +0 (± 홀수 잔차)
        pairs = []
        for _ in range(rng.randint(1, 8)):
            e = rng.randint(-40, 40)
            a8, b8 = rng.randrange(128, 256), rng.randrange(128, 256)
            s = rng.randint(0, 1)
            pa = mk_bf16_pair(rng, e, s, a8, b8)
            pairs.append(pa)
            pairs.append((pa[0] ^ 0x8000, pa[1]))       # 정확 상쇄쌍
        if rng.random() < 0.4 and len(pairs) < GROUP:
            pairs.append(mk_bf16_pair(rng, rng.randint(-150, -120),
                                      rng.randint(0, 1)))
    return DT_BF16, _pad(pairs[:GROUP])


_COMPOSITE_ADJ = None


def _has88(m):
    a = 128
    while a * a <= m and a < 256:
        if m % a == 0 and 128 <= m // a < 256:
            return True
        a += 1
    # a*b, a<=b 만으로 충분 (b < 256 검사 포함 위: a >= 128 ⇒ b <= m/128)
    return False


def composite_adj_table():
    """(m, m-1) 둘 다 8x8 합성수 ([128,255]×[128,255]) 인 m 표 — 단위
    잔차 (±1·2^e) 를 곱 2개의 정확 상쇄로 만드는 재료 (결정적)."""
    global _COMPOSITE_ADJ
    if _COMPOSITE_ADJ is None:
        _COMPOSITE_ADJ = [m for m in range((1 << 14) + 1, 1 << 16)
                          if _has88(m) and _has88(m - 1)]
        assert len(_COMPOSITE_ADJ) > 100
    return _COMPOSITE_ADJ


def _split88(m):
    a = 128
    while True:
        if m % a == 0 and 128 <= m // a < 256:
            return a, m // a
        a += 1


def gen_adv_residue(rng):
    """fold 창-하강 적대 구성 (§27.7a.2 정리의 표적 공격): ±m·2^E ∓
    (m-1)·2^E 정확 상쇄로 단위 잔차 (±1) component 를 상단에 만들고,
    그 아래 48-경계 gap (46..52) 에 반대 부호 mid 곱, 최하단에 dust —
    fold 중간 jam 후 상단 상쇄로 창이 내려가는 배치를 노린다. 삽입
    순서 3종 (unit 선/후, shuffle) 을 순환."""
    m1 = rng.choice(composite_adj_table())
    e1 = rng.randint(-40, 200)
    su = rng.randint(0, 1)
    a8, b8 = _split88(m1)
    c8, d8 = _split88(m1 - 1)
    unit = [mk_bf16_pair(rng, e1, su, a8, b8),
            mk_bf16_pair(rng, e1, 1 - su, c8, d8)]
    gap = rng.choice([46, 47, 48, 49, 50, 51, 52])
    mids, e = [], e1 - gap
    for _ in range(rng.randint(1, 4)):
        if e < -260:
            break
        mids.append(mk_bf16_pair(rng, e, 1 - su))
        e -= rng.randint(15, 26)
    dust = []
    ed = e - rng.choice([49, 50, 52, 60])
    for _ in range(rng.randint(1, 3)):
        if ed < -266:
            break
        dust.append(mk_bf16_pair(rng, ed, rng.randint(0, 1)))
        ed -= rng.randint(2, 20)
    order = rng.randrange(3)
    if order == 0:
        pairs = unit + mids + dust
    elif order == 1:
        pairs = mids + dust + unit
    else:
        pairs = unit + mids + dust
        rng.shuffle(pairs)
    return DT_BF16, _pad(pairs[:GROUP])


def gen_top_cancel(rng):
    """**C1 반례 메커니즘 표적 가족** (3a-C1 신설 — §27.7a.5 (b) 추가).
    값 계약 반례 2건의 구조를 명시 구성한다. 두 조건을 함께 만든다:
      (M1) 깊은 tail — 2^(E0-48) 아래 곱을 깔아 fold 의 한 pass 에서
           정렬폭 > 48 을 만들어 **sticky-jam 을 강제**한다.
      (M2) 상단 인접 상쇄 — 8-bit 블록 사슬로 top == E0 인 (거의 꽉 찬)
           24-bit component 를 쌓고, **마지막 lane 두 개**로 순수
           -2^E0 (129·129 - 128·130 = 1) 를 삽입한다. 비겹침 하에서 큰
           상쇄는 최상위 significand 가 ±1 일 때만 가능하므로 이것이
           표준형이다.
    폐기된 ASC pin 은 이 가족에서 정리를 ~99% 위반한다 (기존
    eft_cancel_chain 의 검출률 0.05% 대비 표적성 확보 — 표적 가족 없이는
    회귀가 다시 숨는다). 채택된 DESC pin 은 0 이어야 한다."""
    E0 = rng.randint(-30, 30)
    pairs = []
    nb = rng.randint(2, 3)                  # 8-bit 블록 수 (16 또는 24 bit)
    for i in range(nb):
        b = 255 if i < nb - 1 else rng.randrange(248, 256)
        pairs.append(mk_bf16_pair(rng, E0 - 8 * (i + 1) - 7, 0, b, 128))
    for _ in range(rng.randint(1, 3)):      # (M1) jam 유발 tail
        pairs.append(mk_bf16_pair(rng, E0 - rng.randint(52, 90),
                                  rng.randint(0, 1)))
    pairs.append(mk_bf16_pair(rng, E0, 1, 129, 129))    # (M2) 순수 -2^E0
    pairs.append(mk_bf16_pair(rng, E0, 0, 128, 130))
    return DT_BF16, _pad(pairs[:GROUP])


FAM_GENS = [
    ("eft_bf16_wide", gen_bf16_wide),
    ("eft_f16_all", gen_f16_all),
    ("eft_cancel", gen_cancel),
    ("eft_cancel_chain", gen_cancel_chain),
    ("eft_tie", gen_tie),
    ("eft_ladder", gen_ladder),
    ("eft_same", gen_same),
    ("eft_pack_edge", gen_pack_edge),
    ("eft_adv_residue", gen_adv_residue),
    ("eft_top_cancel", gen_top_cancel),
]

# fold-적대 전용으로 설계된 가족 (별도 카운트 근거 — §27.7a.5 (b))
FOLD_ADV_FAMS = {"eft_cancel", "eft_cancel_chain", "eft_tie", "eft_ladder",
                 "eft_same", "eft_adv_residue", "eft_top_cancel"}


# ===========================================================================
# directed 결정 벡터 (EFT 값 계약 + invariant + 벡터 파일 수록)
# ===========================================================================


def _p2b(p, s=0):
    return LAT.bf16_pow2(p, s)


def det_eft_cases():
    """(name, dtype, pairs, expect_bits|None). expect 는 손계산 고정점 —
    None 이면 pack_signed(exact) 만으로 판정."""
    ones24 = [(_p2b(63), _p2b(k - 63)) for k in range(104, 128)]
    ones25 = [(_p2b(63), _p2b(k - 63)) for k in range(103, 128)]
    return [
        ("det_tie_q25", DT_BF16,
         _pad([(0x3F80, 0x3F80), (_p2b(-12), _p2b(-12)),
               (_p2b(-30), _p2b(-30))]), 0x3F800001),
        ("det_rne48_disc", DT_BF16,
         _pad([(_p2b(24), _p2b(24)), (_p2b(12), _p2b(12)),
               (0x3F80, 0x3F80)]), 0x57800001),
        ("det_exact_cancel", DT_BF16,
         _pad([(0x40C0, 0x3FA0), (0xC0C0, 0x3FA0)]), 0x00000000),
        ("det_ftz_min_normal", DT_BF16,
         _pad([(_p2b(-63), _p2b(-63))]), 0x00800000),
        ("det_ftz_under", DT_BF16,
         _pad([(_p2b(-63), _p2b(-63)), (_p2b(-75, 1), _p2b(-75))]),
         0x00000000),
        ("det_ftz_neg", DT_BF16,
         _pad([(_p2b(-75, 1), _p2b(-74))]), 0x80000000),
        ("det_ovf_2p128", DT_BF16,
         _pad([(_p2b(63), _p2b(64)), (_p2b(63), _p2b(64))]), 0x7F800000),
        ("det_ovf_neg", DT_BF16,
         _pad([(_p2b(63, 1), _p2b(64)), (_p2b(63, 1), _p2b(64))]),
         0xFF800000),
        ("det_maxfinite_24ones", DT_BF16, _pad(ones24), 0x7F7FFFFF),
        ("det_inf_25ones", DT_BF16, _pad(ones25), 0x7F800000),
        ("det_f16_min_sub_prod", DT_F16,
         _pad([(0x0001, 0x3C00)]), 0x33800000),
        ("det_f16_tie_even", DT_F16,
         _pad([(0x3C00, 0x3C00), (0x0001, 0x3C00)]), 0x3F800000),
        ("det_f16_tie_up", DT_F16,
         _pad([(0x3C00, 0x3C00), (0x0001, 0x3C00), (0x0001, 0x0001)]),
         0x3F800001),
        ("det_f16_sub_sq_all", DT_F16,
         [(0x0001, 0x0001)] * GROUP, 0x2A000000),
        ("det_f16_max_sq_all", DT_F16, [(0x7BFF, 0x7BFF)] * GROUP, None),
        ("det_bf16_daz_zero", DT_BF16,
         _pad([(0x0001, 0x7F00), (0x807F, 0x7F00)]), 0x00000000),
        ("det_bf16_daz_plus_one", DT_BF16,
         _pad([(0x007F, 0x7F40), (0x3F80, 0x3F80)]), 0x3F800000),
        ("det_all_same_1p5", DT_BF16, [(0x3FC0, 0x3FC0)] * GROUP,
         0x42900000),
        ("det_bf16_min_lsb", DT_BF16,
         _pad([(LAT.bf16_bits(0, -126, 129), LAT.bf16_bits(0, -126, 129))]),
         0x00000000),
        ("det_bf16_top", DT_BF16, [(0x7F7F, 0x7F7F)] * GROUP, 0x7F800000),
    ]


# ===========================================================================
# specials directed (§27.7a.1 (iii) — 대조 축 실증)
# ===========================================================================

_BF_SP = {"qnan": 0x7FC0, "snan": 0x7F81, "pinf": 0x7F80, "ninf": 0xFF80}
_F16_SP = {"qnan": 0x7E00, "snan": 0x7C01, "pinf": 0x7C00, "ninf": 0xFC00}


def special_det_cases():
    cases = []
    rng = random.Random(SEEDS["special_det_bg"])
    for dtype, tab in ((DT_BF16, _BF_SP), (DT_F16, _F16_SP)):
        def norm(r=rng, d=dtype):
            if d == DT_BF16:
                return LAT.rand_bf16_operand(r, -30, 30)
            return LAT.rand_f16_operand(r, 0.2)
        for kind in ("qnan", "snan", "pinf", "ninf"):
            for side in (0, 1):
                for lane in (0, 17, 31):
                    for bg in ("zeros", "norm"):
                        if bg == "zeros":
                            pairs = [_ZP] * GROUP
                        else:
                            pairs = [(norm(), norm()) for _ in range(GROUP)]
                        a, b = pairs[lane]
                        pairs[lane] = (tab[kind], b) if side == 0 \
                            else (a, tab[kind])
                        cases.append(("sp_%s_%s_s%d_l%d_%s"
                                      % ("bf16" if dtype == DT_BF16
                                         else "f16", kind, side, lane, bg),
                                      dtype, pairs))
        cases.append(("sp_%s_inf_x_zero" % dtype, dtype,
                      _pad([(tab["pinf"], 0x0000)])))
        cases.append(("sp_%s_nan_x_zero" % dtype, dtype,
                      _pad([(tab["qnan"], 0x8000)])))
        cases.append(("sp_%s_both_sides" % dtype, dtype,
                      _pad([(tab["qnan"], tab["pinf"])])))
        cases.append(("sp_%s_all_lanes" % dtype, dtype,
                      [(tab["ninf"], norm()) for _ in range(GROUP)]))
    return cases


def gen_special_rand(rng):
    dtype, pairs = (gen_bf16_wide if rng.random() < 0.5
                    else gen_f16_all)(rng)
    tab = _BF_SP if dtype == DT_BF16 else _F16_SP
    for _ in range(rng.randint(1, 5)):
        lane = rng.randrange(GROUP)
        kind = rng.choice(list(tab))
        pat = tab[kind]
        if kind in ("qnan", "snan"):        # 임의 payload NaN + 임의 부호
            payload = rng.randint(1, 127 if dtype == DT_BF16 else 1023)
            base = 0x7F80 if dtype == DT_BF16 else 0x7C00
            pat = base | payload | (rng.randint(0, 1) << 15)
        a, b = pairs[lane]
        if rng.random() < 0.15:             # Inf/NaN × zero 행
            other = rng.randint(0, 1) << 15
            pairs[lane] = (pat, other) if rng.random() < 0.5 \
                else (other, pat)
        else:
            pairs[lane] = (pat, b) if rng.random() < 0.5 else (a, pat)
    return dtype, pairs


# ===========================================================================
# fold 정리 — 일반형 (임의 비겹침 열) synthetic annex (감추지 않는 보고)
#
# 본 annex 는 두 fold 방향을 같은 열에 나란히 걸어 §27.7a.2 종료 (2) 의
# 개정 근거를 기계 판독 가능하게 남긴다:
#   ASC  (원 pin, 3a-C0)  — 일반형 REFUTED (결정 반례 + 랜덤 sweep)
#   DESC (개정 pin, C1)   — 일반형 성립 (같은 반례·같은 sweep 에서 0)
# 반례를 삭제하지 않는다 (§25.4 / 정직 보고 법칙): ASC 반례는 개정의
# 근거 artifact 로 존치되며, 각 행이 DESC 에서 해소됨을 함께 싣는다.
# ===========================================================================

# 결정적 반례 (손구성): 오름차순 비겹침 열이지만 ASC fold 중간 jam 뒤
# 상단 상쇄로 창이 내려가 RTO_48(exact) 와 갈라진다 (B 는 PACK_FINAL
# 까지 갈라진다). cex_C/D 는 3a-C1 이 값 계약 반례 2건에서 역추출한
# 실측 expansion — 삽입-생성 scope 안에서도 ASC 가 부정됨을 보인다
# (죽은 세션이 제안한 "scope 축소 재서술" 처방이 무효인 근거).
SYNTH_CEX = [
    ("cex_A_jam_then_adjacent_cancel",
     [(1, 0), ((1 << 23) + 1, 31), (-1, 55)]),
    ("cex_B_deep_cancel_pack_final",
     [(1, 0), ((1 << 24) - 1, 8), ((1 << 24) - 1, 32), (-1, 56)]),
    ("cex_C_c1_value_contract_cex0_expansion",
     [(2, -28), (16777212, -23), (16777215, 1), (-1, 25)]),
    ("cex_D_c1_value_contract_cex1_expansion",
     [(6, -28), (16777206, -25), (16777215, -1), (-1, 23)]),
]


def fold_ascending_refuted(expansion):
    """원 pin (ASC) 의 fold — **개정으로 폐기된 형**. annex 전용:
    개정 근거를 재현 가능하게 남기기 위해서만 존치한다 (값 경로에서
    호출 금지 — fdotcr_ref 는 fold_descending 만 쓴다)."""
    am, ae = 0, 0
    for c in expansion:
        am, ae = addwide_rto48_me(am, ae, c[0], c[1])
    return am, ae


def _synth_expansion(rng):
    n = rng.randint(2, 20)
    comps = []
    e = rng.randint(-260, -200)
    for _ in range(n):
        w = rng.randint(1, W24)
        m = (rng.getrandbits(w - 1) | (1 << (w - 1))) if w > 1 else 1
        if rng.random() < 0.5:
            m = -m
        comps.append((m, e))
        e += w + rng.choice([0, 0, 0, 1, 2, 25, 49, 60])
        if e > 250:
            break
    return comps


def synth_fold_annex():
    rows = []
    for name, comps in SYNTH_CEX:
        for i in range(1, len(comps)):
            assert comp_top(comps[i - 1]) <= comps[i][1]    # 유효 비겹침 열
        sm, se = _exact_sum_me(comps)
        tm, te = STUDY.rto_me(sm, se, Q48)
        pt = pack_final_me(sm, se)
        am_, ae_ = fold_ascending_refuted(comps)
        st = {"fold_passes": 0}
        dm, de = fold_descending(comps, st)
        a_div = not STUDY.veq_me(am_, ae_, tm, te)
        d_div = not STUDY.veq_me(dm, de, tm, te)
        pa, pd = pack_final_me(am_, ae_), pack_final_me(dm, de)
        rows.append({
            "case": name,
            "components": [[c[0], c[1]] for c in comps],
            "rto48_exact_me": [tm, te],
            "pack_final_exact": "0x%08X" % pt,
            "asc_refuted_pin": {
                "fold_me": [am_, ae_], "fold_ne_rto48": a_div,
                "pack_final": "0x%08X" % pa,
                "pack_final_diverges": pa != pt,
            },
            "desc_adopted_pin": {
                "fold_me": [dm, de], "fold_ne_rto48": d_div,
                "pack_final": "0x%08X" % pd,
                "pack_final_diverges": pd != pt,
                "jam_grid_p": st["jam_grid_p"],
                "jam_margin": st["jam_margin"],
                "freeze_ok": st["freeze_ok"],
            },
        })
    rng = random.Random(SEEDS["fold_synth"])
    a_div = a_pack = d_div = d_pack = 0
    margin_min = None
    for _ in range(N_SYNTH):
        comps = _synth_expansion(rng)
        sm, se = _exact_sum_me(comps)
        tm, te = STUDY.rto_me(sm, se, Q48)
        pt = pack_final_me(sm, se)
        am_, ae_ = fold_ascending_refuted(comps)
        if not STUDY.veq_me(am_, ae_, tm, te):
            a_div += 1
            if pack_final_me(am_, ae_) != pt:
                a_pack += 1
        st = {"fold_passes": 0}
        dm, de = fold_descending(comps, st)
        if not STUDY.veq_me(dm, de, tm, te):
            d_div += 1
            if pack_final_me(dm, de) != pt:
                d_pack += 1
        if st["jam_margin"] is not None:
            if margin_min is None or st["jam_margin"] < margin_min:
                margin_min = st["jam_margin"]
    det_a = any(r["asc_refuted_pin"]["fold_ne_rto48"] for r in rows)
    det_a_pack = any(r["asc_refuted_pin"]["pack_final_diverges"]
                     for r in rows)
    det_d = any(r["desc_adopted_pin"]["fold_ne_rto48"] for r in rows)
    return {
        "_doc": "fold 정리의 **일반형** (임의 비겹침 오름차순 열 — 삽입-"
                "생성 expansion 이 아닌 합성 열) 을 두 방향에 나란히 건 "
                "실측. ASC = §27.7a.2 원 pin (3a-C0), DESC = C1 실측 "
                "개정 pin. 반례는 삭제하지 않고 개정 근거로 존치한다 "
                "(§25.4 / 정직 보고). cex_C/D 는 값 계약 반례 2건에서 "
                "역추출한 실측 expansion — ASC 가 삽입-생성 scope "
                "안에서도 부정됨을 보인다 (scope 축소 처방이 무효인 근거).",
        "deterministic_cases": rows,
        "asc_refuted_pin": {
            "deterministic_counterexample_found": det_a,
            "deterministic_pack_final_counterexample_found": det_a_pack,
            "random_sweep": {"N": N_SYNTH, "seed": SEEDS["fold_synth"],
                             "fold_ne_rto48": a_div,
                             "pack_final_diverges": a_pack},
            "verdict_general_form": "REFUTED" if det_a or a_div else "PASS",
        },
        "desc_adopted_pin": {
            "deterministic_counterexample_found": det_d,
            "random_sweep": {"N": N_SYNTH, "seed": SEEDS["fold_synth"],
                             "fold_ne_rto48": d_div,
                             "pack_final_diverges": d_pack},
            "jam_margin_min": margin_min,
            "jam_margin_floor_25_held": (margin_min is None
                                         or margin_min >= 25),
            "verdict_general_form": "REFUTED" if det_d or d_div else "PASS",
        },
    }


def capacity_probe():
    """용량 상한 probe: 33 수용 / 34 = loud fault (§27.7a.2)."""
    base = [(1, -900 + 55 * j) for j in range(EXP_CAP)]
    st = {"twosum_passes": 0, "max_chain": 0}
    out = grow_insert(base[1:], (1, -970), st)          # 32+1 = 33 수용
    assert len(out) == EXP_CAP
    try:
        grow_insert(base, (1, -970), st)                # 33+1 = 34 -> fault
    except FdotFault:
        return {"accept_33": True, "overflow_34_loud_fault": True,
                "verdict": "PASS"}
    raise AssertionError("capacity fault NOT raised at 34 components")


# ===========================================================================
# 벡터 파일 (operand 1,024b A||B — §27.7a.1 frag 배치) + 계약 문서
# ===========================================================================

FAM_CODES = {"det": 0, "eft_bf16_wide": 1, "eft_f16_all": 2,
             "eft_cancel": 3, "eft_cancel_chain": 4, "eft_tie": 5,
             "eft_ladder": 6, "eft_same": 7, "eft_pack_edge": 8,
             "eft_adv_residue": 9, "special_det": 10, "special_rand": 11,
             "c1_regress": 12, "eft_top_cancel": 13}

# 3a-C1 이 ASC pin 하에서 실측한 값 계약 반례 2건의 operand — **영구
# 회귀 벡터**로 고정한다 (반례 가족 제외 금지). 기대 RESULT 는 언제나
# 값 계약 우변 pack_signed(exact) 이며, 폐기된 ASC fold 는 각각
# 0xB4C00000 / 0xB4900000 을 내어 이 벡터에서 즉시 FAIL 한다.
C1_REGRESSION_CASES = [
    ("c1_value_cex0_asc_gave_0xB4C00000", DT_BF16, [
        (0x4947, 0x3982), (0x933A, 0x65A0), (0xDEFA, 0x1D6F),
        (0x13AE, 0x64E7), (0x9B81, 0x7701), (0x8D80, 0x77DC),
        (0x5D82, 0x3500), (0x4280, 0x4900), (0x4055, 0x4500),
        (0x322F, 0x4F00), (0x11B4, 0x6B00), (0x527E, 0x2680)]),
    ("c1_value_cex1_asc_gave_0xB4900000", DT_BF16, [
        (0x35EE, 0x480C), (0x10CC, 0x6F87), (0xA57F, 0x6CFF),
        (0xBC06, 0x3C77), (0xE984, 0x1130), (0xFDDF, 0x009D),
        (0x6EFE, 0x2380), (0x777F, 0x1300), (0x6D7F, 0x1900),
        (0x1D73, 0x6500), (0x3DF2, 0x3F00), (0x0849, 0x7080)]),
]


class FdotVecEmitter:
    def __init__(self):
        self.lines = []
        self.families = []
        self._fam = None

    def begin(self, name, doc):
        self._fam = {"family": name, "code": FAM_CODES[name], "doc": doc,
                     "start": len(self.lines), "count": 0}
        self.families.append(self._fam)

    def emit(self, dtype, pairs, r):
        # 벡터 파일의 RESULT 는 **값 계약 우변** 이어야 한다 (RTL 이
        # 재현해야 할 것은 exact reference 이지 EFT 산출물이 아니다).
        # bits != ref_bits 인 trial 을 수록하면 TB 가 버그를 정답으로
        # 강제한다 — loud fault 로 막는다 (C1 감사 지적 사항).
        if not r["special"] and r["bits"] != r["ref_bits"]:
            raise FdotFault(
                "vector emit refused: bits 0x%08X != ref_bits 0x%08X — "
                "값 계약 위반 trial 은 벡터 파일에 수록 금지"
                % (r["bits"], r["ref_bits"]))
        a_lanes = [a for a, _ in pairs]
        b_lanes = [b for _, b in pairs]
        payload = 0
        for f, w in enumerate(lanes_to_frags(a_lanes, 16)
                              + lanes_to_frags(b_lanes, 16)):
            payload |= w << (64 * f)        # frag 0-7 = A, 8-15 = B
        meta = ((self._fam["code"] << 24) | (min(r["n_special"], 255) << 16)
                | (int(r["special"]) << 8) | dtype)
        v = (meta << (1024 + 32)) | (payload << 32) | r["bits"]
        assert v < (1 << VEC_BITS)
        self.lines.append("%0*x" % (VEC_HEX, v))
        self._fam["count"] += 1


def write_vector_file(em):
    hdr = [
        "// fdotcr_vectors.hex — FDOT32_CR (0x7A) golden EFT 벡터 "
        "(결정적, 고정 seed)",
        "// 생성기: scripts/golden_fdotcr.py — 비트 레이아웃 계약: "
        "include/generated/fdotcr_vec_contract.md",
        "// 1 line = 1 dispatch = %d hex chars = %d bits; N_VEC = %d"
        % (VEC_HEX, VEC_BITS, len(em.lines)),
    ]
    VEC_PATH.write_text("\n".join(hdr + em.lines) + "\n")


def _independent_expected(dtype, pairs):
    """**EFT 경로에 무의존한** 기대 결과 재산출 (자기확인 루프 차단).
    fdotcr_ref 를 일절 쓰지 않고 golden_lattice.operand_frac (Fraction
    독립 decode) + acc_format_study.pack_signed 로 값 계약 우변을 직접
    계산한다. specials 는 §27.7a.1 (iii) 대로 qNaN.
    returns (bits, is_special, n_special)"""
    cl = 0 if dtype == DT_BF16 else 1
    nsp = 0
    acc = Fraction(0)
    for a, b in pairs:
        if _is_special_operand(dtype, a) or _is_special_operand(dtype, b):
            nsp += 1
            continue
        acc += LAT.operand_frac(cl, a) * LAT.operand_frac(cl, b)
    if nsp:
        return F32_QNAN, 1, nsp
    return (0x00000000 if acc == 0 else STUDY.pack_signed(acc)), 0, 0


def verify_vector_file():
    """파일 재독 -> operand 복원 -> **두 경로** 재대조:
      (i) fdotcr_ref (EFT twin) — 단계 재현성,
      (ii) _independent_expected (Fraction 독립 경로) — RESULT 필드가
           값 계약 우변 pack_signed(exact) 임을 EFT 와 무관하게 확인.
    (ii) 가 없으면 EFT 버그를 EFT 로 재확인하는 자기확인 루프가 된다."""
    n = 0
    for ln in VEC_PATH.read_text().splitlines():
        if not ln or ln.startswith("//"):
            continue
        assert len(ln) == VEC_HEX
        v = int(ln, 16)
        bits = v & 0xFFFFFFFF
        v >>= 32
        payload = v & _M1024
        meta = v >> 1024
        dtype = meta & 0xFF
        sp = (meta >> 8) & 1
        nsp = (meta >> 16) & 0xFF
        frags = [(payload >> (64 * f)) & _M64 for f in range(16)]
        a_lanes = frags_to_lanes(frags[:8], 16, GROUP)
        b_lanes = frags_to_lanes(frags[8:], 16, GROUP)
        pairs = list(zip(a_lanes, b_lanes))
        r = fdotcr_ref(dtype, pairs)
        assert r["bits"] == bits and int(r["special"]) == sp
        assert min(r["n_special"], 255) == nsp
        ib, isp, insp = _independent_expected(dtype, pairs)
        if ib != bits or isp != sp or min(insp, 255) != nsp:
            raise FdotFault(
                "vector line %d: RESULT 0x%08X != 독립 경로 기대값 "
                "0x%08X (값 계약 우변)" % (n, bits, ib))
        n += 1
    return n


def contract_text(em, n_eft, n_inv, n_sp):
    fam_rows = "\n".join(
        "| %d | %s | %d | %d | %s |" % (f["code"], f["family"], f["start"],
                                        f["count"], f["doc"])
        for f in em.families)
    seed_rows = "\n".join("| `%s` | `0x%X` |" % kv for kv in SEEDS.items())
    return """<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor \
contributors -->

# fdotcr_vectors.hex — FDOT32_CR (0x7A) golden EFT 벡터 계약

생성기: `scripts/golden_fdotcr.py` (stdlib-only, 고정 seed, 재실행
byte-identical). 규범 출처: wt64v1_spec.md **§27.7a** (값 계약 §27.7a.1 /
알고리즘 §27.7a.2 / invariant §27.7a.3 / 검증 계획 §27.7a.5). 이 벡터가
3a-C3 (FP_StepSeq OPS_FDOTCR unit TB) / 3a-C4 (통합 TB dual-run) 의
directed 입력이다.

## 1. 라인 형식

`$readmemh`, 주석 3줄 + %d 라인. 1 line = 1 dispatch = %d hex chars =
%d bits, MSB-first:

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
   반례 2건, 상대오차 24%%). RTL 은 이 방향을 반드시 미러링해야 한다:
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
%s

## 7. seeds (고정 — 결정론의 유일한 난수원)

| key | seed |
|---|---|
%s

## 8. 카운트 (report 와 동일)

EFT 값-계약 trial %d (0 mismatch 의무) / invariant trial %d /
special trial %d. 상세·sha256 은 `fdotcr_golden_report.json`.
""" % (len(em.lines), VEC_HEX, VEC_BITS, fam_rows, seed_rows,
       n_eft, n_inv, n_sp)


def _sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


# ===========================================================================
# main — 자기검증 sweep 전체
# ===========================================================================


def _cex_row(tag, dtype, pairs, r):
    return {"tag": tag, "dtype": dtype,
            "pairs_hex": [["0x%04X" % a, "0x%04X" % b] for a, b in pairs],
            "bits": "0x%08X" % r["bits"],
            "ref_bits": "0x%08X" % r.get("ref_bits", 0),
            "fold_me": list(r.get("fold_me", (0, 0))),
            "exact_me": [str(x) for x in r.get("exact_me", (0, 0))]}


def main():
    t0 = time.time()

    def stamp(tag):
        print("  [%6.1fs] %s" % (time.time() - t0, tag))
        sys.stdout.flush()

    print("golden_fdotcr: FDOT32_CR (0x7A) §27.7a golden EFT twin (3a-C1)")

    counters = {
        "eft_trials": 0, "value_mismatch": 0,
        "fold_checks": 0, "fold_mismatch": 0, "fold_adv_trials": 0,
        "invariant_trials": 0, "invariant_mismatch": 0,
        "special_trials": 0,
        "exp_max": 0, "twosum_passes_max": 0, "fold_passes_max": 0,
        "chain_max": 0, "product_frac_crosschecked": 0,
        "jam_trials": 0, "jam_margin_min": None, "jam_margin_lt25": 0,
        "freeze_violations": 0,
        "merge_width_max": 0, "merge_count_total": 0,
        "insort_steps_max": 0, "insort_steps_total": 0,
        "insort_calls_max": 0,
    }
    exp_hist = {}
    jam_hist = {}
    value_cex, fold_cex, inv_cex = [], [], []
    inv_by_fam = {}                 # 가족별 invariant 카운트 (공시 의무)
    asc_by_fam = {}                 # 폐기 ASC pin 의 가족별 검출률 실측

    def track(fam, dtype, pairs, r, fold_adv):
        """값 계약 + fold 정리 + **invariant (동일 operand 전수)** +
        폐기 ASC pin 재현 probe 를 한 trial 에서 함께 건다.

        §27.7a.5 (c) 선공표는 invariant sweep 을 "**동일 operand 전
        벡터에서** bit-equal **전수** assert" 로 못박았다 — 별도 스트림
        으로 일부 가족만 도는 구현은 그 문언의 이행이 아니다 (3a-C1
        자체 감사 지적, §27.7a.2a amendment-7). 따라서 값 계약을 받는
        모든 trial 이 같은 operand 로 main path twin 대조를 받는다."""
        counters["eft_trials"] += 1
        counters["fold_checks"] += 1
        if fold_adv:
            counters["fold_adv_trials"] += 1
        base = fam.split(":")[0]
        if not r["value_ok"]:
            counters["value_mismatch"] += 1
            if len(value_cex) < 8:
                value_cex.append(_cex_row(fam, dtype, pairs, r))
        if not r["fold_ok"]:
            counters["fold_mismatch"] += 1
            if len(fold_cex) < 8:
                fold_cex.append(_cex_row(fam, dtype, pairs, r))
        st = r["stats"]
        counters["exp_max"] = max(counters["exp_max"], st["exp_max"])
        counters["twosum_passes_max"] = max(counters["twosum_passes_max"],
                                            st["twosum_passes"])
        counters["fold_passes_max"] = max(counters["fold_passes_max"],
                                          st["fold_passes"])
        counters["chain_max"] = max(counters["chain_max"], st["max_chain"])
        exp_hist[st["exp_max"]] = exp_hist.get(st["exp_max"], 0) + 1
        assert st["twosum_passes"] <= 528          # §27.7a.2 삽입 위치 총수
        assert not r["sticky"]                     # 비-special 축 청결
        # 개정된 종료 (2) 의 졸업 지표 — jam 마진 + freeze (§25.4)
        if not st["freeze_ok"]:
            counters["freeze_violations"] += 1
        mg = st["jam_margin"]
        if mg is not None:
            counters["jam_trials"] += 1
            jam_hist[mg] = jam_hist.get(mg, 0) + 1
            if counters["jam_margin_min"] is None \
                    or mg < counters["jam_margin_min"]:
                counters["jam_margin_min"] = mg
            if mg < 25:                    # RNE-24 흡수 마진 붕괴 = 경고축
                counters["jam_margin_lt25"] += 1
        # 대기열 유지 비용 (amendment-3 이 "미계상" 으로 기록한 축)
        counters["merge_count_total"] += st["merge_count"]
        counters["merge_width_max"] = max(counters["merge_width_max"],
                                          st["merge_width_max"])
        counters["insort_steps_total"] += st["insort_steps"]
        counters["insort_steps_max"] = max(counters["insort_steps_max"],
                                           st["insort_steps"])
        counters["insort_calls_max"] = max(counters["insort_calls_max"],
                                           st["insort_calls"])

        # ---- invariant (§27.7a.3 / §27.7a.5 (c)) — 동일 operand 전수 ----
        tw = main_twin(dtype, pairs)
        counters["invariant_trials"] += 1
        inv_by_fam[base] = inv_by_fam.get(base, 0) + 1
        assert not tw["sticky"] and not tw["suppressed"]
        if tw["drain"] != r["bits"]:
            counters["invariant_mismatch"] += 1
            if len(inv_cex) < 8:
                inv_cex.append(_cex_row("invariant:" + fam, dtype,
                                        pairs, r))

        # ---- 폐기 ASC pin 재현 probe (검출력 실측 — amendment-7) ----
        # 같은 expansion 에 폐기된 오름차순 fold 를 걸어 (a) 가족별
        # 정리 위반률, (b) 값 계약 위반 수, (c) **독립 main path twin
        # 이 그 값 위반을 검출하는지** 를 센다. (c) 는 "invariant 축은
        # EFT 와 결함 표면을 공유해 판별력이 없다" 는 3a-C1 중간 진단이
        # 거짓임을 고정-seed 로 못박는 축이다 (main_twin 은
        # golden_lattice.wave_step — EFT fold 를 일절 쓰지 않는다).
        a = asc_by_fam.setdefault(base, {
            "trials": 0, "fold_violations": 0, "value_violations": 0,
            "value_violations_caught_by_main_twin": 0})
        a["trials"] += 1
        am_, ae_ = fold_ascending_refuted(r["expansion"])
        sm_, se_ = r["exact_me"]
        tm_, te_ = STUDY.rto_me(sm_, se_, Q48)
        asc_fold_ok = (STUDY.veq_me(am_, ae_, tm_, te_) if sm_
                       else am_ == 0)
        if not asc_fold_ok:
            a["fold_violations"] += 1
            # 정리가 성립하면 fold 결과가 RTO_48(exact) 와 **값이 같아**
            # pack 도 동일하므로, pack 은 위반 시에만 계산한다 (가정이
            # 아니라 값 동일성의 귀결 — veq_me 는 값 상등이다).
            asc_bits = pack_final_me(am_, ae_)
            if asc_bits != r["ref_bits"]:
                a["value_violations"] += 1
                if asc_bits != tw["drain"]:
                    a["value_violations_caught_by_main_twin"] += 1

    # ---- synthetic fold annex (일반형 — ASC 부정 / DESC 성립) ----
    annex = synth_fold_annex()
    stamp("fold 일반형 annex: ASC %s / DESC %s (결정 반례 %d + 랜덤 %d)"
          % (annex["asc_refuted_pin"]["verdict_general_form"],
             annex["desc_adopted_pin"]["verdict_general_form"],
             len(SYNTH_CEX), N_SYNTH))

    # ---- §27.7a.2 문언 walk annex (invariant 자기모순의 실측 근거) ----
    lit = spec_literal_walk_annex()
    stamp("문언 walk annex: 비겹침 위반 trial %d/%d"
          % (lit["density_sweep"]["trials_with_nonoverlap_violation"],
             lit["density_sweep"]["trials"]))

    # ---- 용량 probe ----
    cap = capacity_probe()
    stamp("expansion 용량 probe (33 수용 / 34 loud fault)")

    em = FdotVecEmitter()

    # ---- directed 결정 벡터 ----
    em.begin("det", "손계산 고정점 directed — tie/q-경계/FTZ/overflow/"
             "정확상쇄/DAZ/f16 subnormal/전부동일 (§27.7a.5 (b))")
    det_rows = []
    for name, dtype, pairs, expect in det_eft_cases():
        r = fdotcr_ref(dtype, pairs)
        track("det:" + name, dtype, pairs, r, True)
        if expect is not None:
            assert r["bits"] == expect, (name, hex(r["bits"]), hex(expect))
        counters["product_frac_crosschecked"] += \
            _crosscheck_products_frac(dtype, pairs)
        em.emit(dtype, pairs, r)
        det_rows.append({"case": name, "result": "0x%08X" % r["bits"],
                         "exp_len": r["stats"]["exp_max"]})
    stamp("directed 결정 벡터 %d" % len(det_rows))

    # ---- EFT 랜덤 가족 sweep (값 계약 + fold 정리, 고정 seed) ----
    for fam, gen in FAM_GENS:
        rng = random.Random(SEEDS[fam])
        n = N_FAM[fam]
        em.begin(fam, _FAM_DOCS[fam])
        adv = fam in FOLD_ADV_FAMS
        for i in range(n):
            dtype, pairs = gen(rng)
            r = fdotcr_ref(dtype, pairs)
            track(fam, dtype, pairs, r, adv)
            if i < VEC_PER_FAM:
                em.emit(dtype, pairs, r)
            if i < 40:
                counters["product_frac_crosschecked"] += \
                    _crosscheck_products_frac(dtype, pairs)
        stamp("EFT %s x%d" % (fam, n))

    # ---- C1 영구 회귀 벡터 (ASC pin 이 값 계약을 깼던 실측 2건) ----
    em.begin("c1_regress", "3a-C1 이 폐기된 ASC fold pin 하에서 실측한 값 "
             "계약 반례 2건 — 영구 회귀 벡터. RESULT = 값 계약 우변 "
             "pack_signed(exact); ASC 로 회귀하면 즉시 FAIL 한다.")
    c1_rows = []
    for name, dtype, ps in C1_REGRESSION_CASES:
        pairs = _pad(list(ps))
        r = fdotcr_ref(dtype, pairs)
        track("c1_regress:" + name, dtype, pairs, r, True)
        em.emit(dtype, pairs, r)            # bits != ref_bits 면 loud fault
        c1_rows.append({"case": name, "result": "0x%08X" % r["bits"],
                        "value_ok": r["value_ok"], "fold_ok": r["fold_ok"]})
    stamp("C1 영구 회귀 벡터 %d" % len(c1_rows))
    # 신규 반례가 나오면 **벡터에 싣지 않는다** — 벡터의 RESULT 는 값
    # 계약 우변이어야 하므로, 버그난 산출을 정답으로 박으면 TB 가 버그를
    # 재현하도록 강제된다. 반례는 report 에 전량 싣고 verdict 를 FAIL 로
    # 떨어뜨린다 (감추지 않되, artifact 는 오염시키지 않는다).

    # ---- specials directed + random (대조 축 실증) ----
    sp_rows = []
    em.begin("special_det", "NaN/Inf 전 행 directed — qNaN/sNaN/±Inf × "
             "A/B × lane {0,17,31} × 배경 {zeros,normals} + Inf×0/NaN×0/"
             "양측/전-lane (§27.7a.1 (iii))")
    for name, dtype, pairs in special_det_cases():
        r = fdotcr_ref(dtype, pairs)
        tw = main_twin(dtype, pairs)
        counters["special_trials"] += 1
        assert r["special"] and r["sticky"] and r["bits"] == F32_QNAN
        assert tw["sticky"] and tw["suppressed"]
        assert not _is_nan_f32(tw["drain"])         # main 은 NaN 불산출
        em.emit(dtype, pairs, r)
        if len(sp_rows) < 12:
            sp_rows.append({"case": name,
                            "audit": {"result": "0x%08X" % r["bits"],
                                      "sticky": True},
                            "main": {"sticky": True,
                                     "writeback_suppressed": True,
                                     "suppressed_drain_class_not_nan": True,
                                     "suppressed_drain":
                                         "0x%08X" % tw["drain"]}})
    rng = random.Random(SEEDS["special_rand"])
    em.begin("special_rand", "임의 배경 + 임의 special 주입 1-5 lane "
             "(payload NaN/부호/±0 짝 포함)")
    for i in range(N_SPECIAL_RAND):
        dtype, pairs = gen_special_rand(rng)
        r = fdotcr_ref(dtype, pairs)
        tw = main_twin(dtype, pairs)
        counters["special_trials"] += 1
        assert r["special"] and r["sticky"] and r["bits"] == F32_QNAN
        assert r["n_special"] == tw["n_special"]    # 분류 일치 (같은 S1)
        assert tw["sticky"] and tw["suppressed"]
        assert not _is_nan_f32(tw["drain"])
        if i < 24:
            em.emit(dtype, pairs, r)
    stamp("specials %d (directed %d + random %d)"
          % (counters["special_trials"],
             counters["special_trials"] - N_SPECIAL_RAND, N_SPECIAL_RAND))

    # ---- invariant 전용 추가 스트림 (§27.7a.3) ----------------------
    # invariant 대조 자체는 track() 이 **값 계약 전 trial 에 전수**로
    # 걸고 있다 (§27.7a.5 (c) 문언 이행). 아래는 그 위에 얹는 독립
    # 스트림이며 generator 는 **전 가족 (FAM_GENS 10종)** 을 쓴다 —
    # 이전 초안은 7종만 돌려 적대 3가족 (eft_cancel_chain /
    # eft_adv_residue / eft_top_cancel) 을 통째로 빠뜨렸다 (3a-C1 자체
    # 감사 지적; 가족 제외는 어디에도 공시되지 않았었다).
    rng = random.Random(SEEDS["invariant"])
    inv_gens = [g for _, g in FAM_GENS]
    assert len(inv_gens) == len(FAM_GENS)      # 가족 제외 금지 (전수)
    for i in range(N_INVARIANT):
        dtype, pairs = inv_gens[i % len(inv_gens)](rng)
        r = fdotcr_ref(dtype, pairs)
        track("invariant", dtype, pairs, r, False)
        if i < 200:
            counters["product_frac_crosschecked"] += \
                _crosscheck_products_frac(dtype, pairs)
    stamp("invariant: 값 계약 전 trial 전수 %d (전용 스트림 %d 포함)"
          % (counters["invariant_trials"], N_INVARIANT))

    # ---- 벡터 파일 + 자기검증 ----
    write_vector_file(em)
    n_verified = verify_vector_file()
    assert n_verified == len(em.lines)
    CONTRACT_PATH.write_text(contract_text(
        em, counters["eft_trials"], counters["invariant_trials"],
        counters["special_trials"]))
    stamp("벡터 파일 %d 라인 self-verify + 계약 문서" % n_verified)

    # ---- report ----
    dedicated_fold_adv = counters["fold_adv_trials"]
    report = {
        "_doc": "FDOT32_CR (0x7A) golden EFT twin (3a-C1) 자기검증 결과 "
                "+ RTL TB 벡터 명세. 생성기: scripts/golden_fdotcr.py "
                "(stdlib-only, 고정 seed, 재실행 byte-identical; rounding "
                "core = golden_fp32, true-B 경로 = acc_format_study."
                "pack_signed, main path = golden_lattice.wave_step). "
                "§27.7 sketch 의 salted '66k+' 는 인용 불가 — 본 report "
                "의 고정-seed 카운트가 그 수치를 승계·졸업시킨다 "
                "(§27.7a.5 인용 규율).",
        "normative_source": "wt64v1_spec.md §27.7a (.1 값 계약 / .2 "
                            "알고리즘 / .3 invariant / .5 검증 계획)",
        "determinism": {
            "seeds": SEEDS,
            "note": "고정 정수 seed 외 난수원/timestamp 없음 — 산출물 "
                    "3종 (hex/md/json) 전부 byte-identical 재생성",
        },
        "algorithm_constants": {
            "component_sig_width_W": W24, "addwide_width": Q48,
            "expansion_capacity": EXP_CAP,
            "insertion_order": "lane 순서 (frag/lane packing pin 순)",
            "insertion_walk": "정련 walk — 최저 2개 순서 merge "
                              "(§27.7a.2 amendment-2 정식 pin; 문언의 "
                              "chain 독해는 checks.spec_literal_walk_"
                              "annex 에서 부정)",
            "fold": "descending RTO-48 (pass = FP_AddWide PACK_WIDE) — "
                    "§27.7a.2 amendment-1. 원 pin 'ascending' 은 C1 "
                    "실측으로 부정됨 (checks.fold_theorem_general_form_"
                    "annex.asc_refuted_pin)",
            "pack_final": "단일 unbounded RNE-24 + flush-after-round FTZ "
                          "(acc_format_study.pack_signed == golden_fp32."
                          "pack_rne_ftz)",
        },
        "checks": {
            "value_contract": {
                "statement": "r == pack_signed(exact Σ a·b) BIT-동일 "
                             "(§27.7a.1 — acc_format_study true-B 기준)",
                "trials": counters["eft_trials"],
                "mismatches": counters["value_mismatch"],
                "counterexamples": value_cex,
                "families": {f: N_FAM[f] for f, _ in FAM_GENS},
                "directed": len(det_rows),
                "salted_66k_supersede": {
                    "_doc": "§27.7a.5 인용 규율 이행 (§27.7a.2a "
                            "amendment-6). §27.7 sketch 의 salted "
                            "'66k+' 는 인용 불가 — 아래 고정-seed "
                            "카운트가 승계·졸업시킨다 (재실행 byte-"
                            "identical 확인).",
                    "value_contract_trials": counters["eft_trials"],
                    "threshold_40000_met":
                        counters["eft_trials"] >= 40000,
                    "eft_path_total_trials":
                        counters["eft_trials"] + counters["special_trials"]
                        + N_SYNTH + N_LITERAL_WALK,
                    "eft_path_total_breakdown": {
                        "value_contract": counters["eft_trials"],
                        "specials": counters["special_trials"],
                        "fold_general_form_annex_random": N_SYNTH,
                        "spec_literal_walk_density": N_LITERAL_WALK,
                    },
                    "exceeds_salted_66k":
                        (counters["eft_trials"]
                         + counters["special_trials"] + N_SYNTH
                         + N_LITERAL_WALK) >= 66000,
                },
                "verdict": "PASS" if counters["value_mismatch"] == 0
                           else "FAIL",
            },
            "fold_theorem_insertion_scope": {
                "statement": "fold(expansion) == RTO_48(exact) — 삽입-"
                             "생성 expansion (알고리즘의 실제 fold 입력) "
                             "전 trial 실측 (§27.7a.2 종료 (2) 의 golden "
                             "졸업). fold = **내림차순** (amendment-1)",
                "trials": counters["fold_checks"],
                "dedicated_adversarial_trials": dedicated_fold_adv,
                "adversarial_families": sorted(FOLD_ADV_FAMS),
                "mismatches": counters["fold_mismatch"],
                "counterexamples": fold_cex,
                "graduation_metric": {
                    "_doc": "개정된 종료 (2) 의 졸업 지표. 정리상 첫 실질 "
                            "jam 이후 acc 는 freeze 되고 jam 마진 "
                            "top(T)-p 는 48 로 고정된다 — RNE-24 흡수 "
                            "조건 (>= 25) 을 23 bit 여유로 만족. 마진이 "
                            "25 미만으로 내려가는 trial 이 곧 값 계약 "
                            "붕괴 지점이다 (ASC pin 의 실패 형태).",
                    "trials_with_real_jam": counters["jam_trials"],
                    "jam_margin_min": counters["jam_margin_min"],
                    "jam_margin_histogram": {str(k): jam_hist[k]
                                             for k in sorted(jam_hist)},
                    "trials_margin_lt_25": counters["jam_margin_lt25"],
                    "freeze_violations": counters["freeze_violations"],
                },
                "verdict": "PASS" if counters["fold_mismatch"] == 0
                           else "FAIL — 정리 부정 (§27.7a 재개정 사유)",
            },
            "fold_theorem_general_form_annex": annex,
            "spec_literal_walk_annex": lit,
            "invariant_sweep": {
                "statement": "비-special single-wave 즉시-drain: "
                             "FDOT32_CR == golden_lattice.wave_step "
                             "BIT-EXACT (§27.7a.3). §27.7a.5 (c) 선공표 "
                             "문언대로 **동일 operand 전 벡터 전수** — "
                             "값 계약을 받는 모든 trial 이 같은 operand "
                             "로 main path twin 대조를 받는다.",
                "trials": counters["invariant_trials"],
                "equals_value_contract_trials":
                    counters["invariant_trials"] == counters["eft_trials"],
                "by_family": {k: inv_by_fam[k]
                              for k in sorted(inv_by_fam)},
                "families_excluded": [],
                "dedicated_stream": {
                    "trials": N_INVARIANT, "seed": SEEDS["invariant"],
                    "generators": [f for f, _ in FAM_GENS],
                    "_doc": "전수 대조 위에 얹는 독립 스트림. generator "
                            "는 전 가족 (FAM_GENS 10종) — 3a-C1 초안은 "
                            "7종만 돌려 적대 3가족을 미공시 제외했었다 "
                            "(§27.7a.2a amendment-7 이 그 사실과 정정을 "
                            "기록한다).",
                },
                "discriminating_power": {
                    "_doc": "invariant 축이 EFT 결함을 실제로 잡는가 — "
                            "3a-C1 중간 진단 '양 경로가 같은 결함 표면을 "
                            "공유해 판별력이 없다' 는 **거짓**이다. "
                            "main_twin 은 golden_lattice.wave_step "
                            "(lattice_accumulate -> extract_rto48 -> "
                            "drain_rne24_ftz) 로 EFT fold 를 일절 쓰지 "
                            "않는 독립 경로다. 아래는 같은 expansion 에 "
                            "폐기된 ASC fold 를 걸었을 때 그 값 위반을 "
                            "main twin 이 검출하는 비율의 고정-seed "
                            "실측 — 0 mismatch 였던 진짜 원인은 결함 "
                            "표면 공유가 아니라 **가족 커버리지 결손** "
                            "이었다.",
                    "asc_value_violations":
                        sum(v["value_violations"]
                            for v in asc_by_fam.values()),
                    "caught_by_main_twin":
                        sum(v["value_violations_caught_by_main_twin"]
                            for v in asc_by_fam.values()),
                },
                "mismatches": counters["invariant_mismatch"],
                "counterexamples": inv_cex,
                "verdict": "PASS" if counters["invariant_mismatch"] == 0
                           else "FAIL",
            },
            "asc_detection_rate_by_family": {
                "_doc": "폐기된 ASC pin (§27.7a.2 원 종료 (2)) 을 각 "
                        "가족의 **삽입-생성 expansion** 에 재적용한 "
                        "실측. §27.7a.2a amendment-5 의 표적성 주장은 "
                        "본 필드를 인용한다 (본문 수치 단독 확정 금지 — "
                        "§25.4). fold_violation_rate = ASC fold != "
                        "RTO_48(exact) 비율; value_violations = 그 중 "
                        "PACK_FINAL 까지 승격돼 값 계약을 깨는 수; "
                        "caught_by_main_twin = 그 값 위반을 독립 main "
                        "path 가 검출한 수 (검출력 실증).",
                "by_family": {
                    k: dict(asc_by_fam[k], fold_violation_rate=round(
                        asc_by_fam[k]["fold_violations"]
                        / asc_by_fam[k]["trials"], 6))
                    for k in sorted(asc_by_fam)},
                "adopted_desc_fold_violations": counters["fold_mismatch"],
            },
            "special_contrast": {
                "statement": "NaN/Inf: audit = qNaN 0x7FC00000 + 전용 "
                             "sticky; main = zero 기여 + LANE_SPECIAL "
                             "sticky + writeback 억제 — 대조 축 = sticky "
                             "유무 (값 비교 금지); main 은 NaN 불산출 "
                             "(marker 무모호)",
                "trials": counters["special_trials"],
                "classify_agreement": "audit/main 의 special lane 수 "
                                      "전수 일치 (같은 S1 classify)",
                "sample_rows": sp_rows,
                "verdict": "PASS",
            },
            "expansion_capacity": {
                "max_observed_components": counters["exp_max"],
                "histogram": {str(k): exp_hist[k]
                              for k in sorted(exp_hist)},
                "structural_bound": "carry 없음 (bank 무접촉 32항 dot) "
                                    "⇒ 자연 도달 <= 32; 용량 33 probe 는 "
                                    "인위 열로 fault 경로 검사",
                "probe": cap,
                "twosum_passes_max": counters["twosum_passes_max"],
                "twosum_passes_bound_528_held": True,
                "max_chain_single_insert": counters["chain_max"],
                "fold_passes_max": counters["fold_passes_max"],
                "merge_aligned_width_max": counters["merge_width_max"],
                "merge_count_total": counters["merge_count_total"],
                "merge_aligned_width_enforced_bound": Q48,
                "merge_aligned_width_doc":
                    "정련 walk 의 겹침 merge 정렬합 폭. **강제 경계는 "
                    "Q48 (초과 = loud fault)** 이고 위 max 는 실측치다 "
                    "— §27.7a.2a amendment-2 의 'vacuous-RTO 강화' "
                    "주장은 이 필드를 인용한다 (assert 로 강제되는 값이 "
                    "아님을 명시; 실측 < 48 은 관측이지 계약이 아니다).",
            },
            "insertion_queue_cost": {
                "_doc": "정련 walk (amendment-2) 이 새로 요구하는 (e, "
                        "top) 정렬 대기열 유지 비용. **이 비교/삽입 "
                        "cycle 은 twosum_passes (AddWide pass 수) 에 "
                        "계상되지 않는다** — §27.7a.2a amendment-3 의 "
                        "cycle 무영향 판정은 AddWide pass 축만 논거로 "
                        "삼았으므로, 본 필드가 그 미계상 축을 실측으로 "
                        "노출한다 (3a-C3 step 프로그램 실측 대상). "
                        "step sequencer 가 비교 1회/cycle 이면 삽입 축 "
                        "단독 상한 = insort_scan_steps_max cycle.",
                "insort_scan_steps_max": counters["insort_steps_max"],
                "insort_scan_steps_total": counters["insort_steps_total"],
                "insort_calls_max": counters["insort_calls_max"],
                "counted_in_twosum_passes": False,
                "resolution_axis": "3a-C3 (RTL step 프로그램 실측) — "
                                   "cycle <= 10,000 hard 상한은 불변",
            },
            "product_decode_crosscheck": {
                "pairs_fraction_checked":
                    counters["product_frac_crosschecked"],
                "note": "EFT 곱 (m,e) vs golden_lattice.operand_frac "
                        "Fraction 곱 — 독립 경로 값-일치",
            },
            "directed_cases": det_rows,
            "vector_file_self_verify": {
                "lines": n_verified, "mismatches": 0, "verdict": "PASS"},
        },
        "vector_file": {
            "path": "include/generated/fdotcr_vectors.hex",
            "n_vectors": len(em.lines),
            "bits_per_line": VEC_BITS,
            "hex_chars_per_line": VEC_HEX,
            "operand_layout": "A||B 연접 16-frag (frag 0-7 = A 32x16b, "
                              "frag 8-15 = B; lanes_to_frags pin)",
            "families": em.families,
            "sha256": _sha256(VEC_PATH),
        },
        "contract": {
            "path": "include/generated/fdotcr_vec_contract.md",
            "sha256": _sha256(CONTRACT_PATH),
        },
        "prannounced_plan_conformance": {
            "_doc": "§27.7a.5 선공표 (locked) 대비 실제 이행. 선공표 "
                    "문언에서 벗어난 항목은 **대체 사실 자체를** 여기와 "
                    "§27.7a.2a amendment 에 기록한다 (§12a 규칙 5) — "
                    "'하한 충족' 같은 재해석만 남기지 않는다.",
            "a_value_contract_stream": {
                "prannounced": "재생성 고정-seed 36,000 재사용 "
                               "(families 30,000 + single-wave streams "
                               "6,000)",
                "actual": "재사용하지 않고 golden 자체 고정 seed "
                          "(0x7ADC001-00A) 로 신규 생성",
                "substitution": True,
                "reason": "선공표가 가리킨 36,000 은 "
                          "scripts/acc_format_study.py 의 **곱 (m,e) "
                          "수준** 스트림 (rto_tree_families 30,000 + "
                          "bank single-wave 6,000) 이라 §27.7a.1 의 "
                          "A||B 16-bit operand 인터페이스로 그대로 "
                          "투입할 수 없다 — FDOT32_CR 은 operand 쌍을 "
                          "먹는다. 동일 seed 재사용 대신 같은 적대 "
                          "성격 (cancellation / tie / wide) 을 operand "
                          "수준에서 재구성한 가족을 신규 고정 seed 로 "
                          "생성했다.",
                "random_family_trials": sum(N_FAM.values()),
                "value_contract_trials_total": counters["eft_trials"],
                "declared_floor_40000": 40000,
                "prannounced_reference_36000": 36000,
                "meets_both": counters["eft_trials"] >= 40000,
                "note_36000_still_regenerated": "§27.7a.3 이 인용하는 "
                                                "36,000 assert 는 "
                                                "acc_format_study 가 "
                                                "여전히 자기 산출물 "
                                                "(fp_validation_report/"
                                                "acc_format_study_report)"
                                                " 에서 재생성한다 — 본 "
                                                "C1 이 그 축을 대체하는 "
                                                "것이 아니라 operand "
                                                "수준 축을 추가한다.",
            },
            "b_directed_and_adversarial": {
                "directed_cases": len(det_rows),
                "adversarial_families": sorted(FOLD_ADV_FAMS),
                "added_in_c1": ["eft_top_cancel", "c1_regress"],
            },
            "c_invariant_full_sweep": {
                "prannounced": "golden lattice model (§27.4 ①) vs "
                               "golden EFT 를 동일 operand 전 벡터에서 "
                               "bit-equal 전수 assert",
                "actual": "값 계약을 받는 전 trial (%d) 에 동일 operand "
                          "main twin 대조 — 가족 제외 0"
                          % counters["invariant_trials"],
                "substitution": False,
                "c1_draft_defect_corrected": "3a-C1 초안은 별도 스트림 "
                                             "12,000 만 돌리며 적대 "
                                             "3가족 (eft_cancel_chain / "
                                             "eft_adv_residue / "
                                             "eft_top_cancel) 을 미공시 "
                                             "제외했다 — 본 산출물에서 "
                                             "전수로 정정 (amendment-7)",
            },
        },
        "spec_findings": [
            "**C1 실측이 C0 pin 을 부정했다 (amendment-1).** §27.7a.2 "
            "종료 (2) 가 pin 한 'ascending-magnitude RTO-48 fold' 는 "
            "일반형뿐 아니라 **삽입-생성 scope 안에서도** 부정된다 — "
            "고정-seed 42,000 급 스트림에서 값 계약 반례 2건 (전부 "
            "bf16 eft_cancel_chain; 상대오차 24%, 1 ulp 급 아님). 근거 "
            "문언 ('각 pass 의 sticky-jam 이 정확히 48-bit 창 아래 "
            "잔여를 운반') 은 거짓이다: sticky-jam 은 그 pass 시점의 "
            "창에 대해서만 표식이며, 이후 pass 가 상단 인접 상쇄로 창을 "
            "jam 아래로 끌어내리면 표식이 값으로 승격된다. 오름차순은 "
            "큰 component 가 나중에 도착하므로 상쇄가 항상 jam 이후에 "
            "일어난다 — 구조적 결함이다. ⇒ 이전 세션이 제안한 'scope 를 "
            "삽입-생성 expansion 으로 좁혀 재서술' 처방은 **무효** "
            "(좁힌 scope 안에 반례가 있다; annex 의 cex_C/cex_D 가 그 "
            "실측 expansion). 채택 수리 = **내림차순 (descending-"
            "magnitude) RTO-48 fold** — 일반형 정리가 증명과 함께 "
            "성립하므로 scope 축소가 불필요하다.",
            "**§27.7a.2 STEP I 문언은 자기모순이다 (amendment-2).** "
            "문언의 TwoSumExact chain 독해 (span<=48 merge, 잔차 lo 즉시 "
            "확정 방출) 는 같은 절이 pin 한 비겹침 invariant 를 스스로 "
            "위반한다 — 결정 반례 + 고정-seed 밀도 실측 "
            "(spec_literal_walk_annex). 문언대로 구현하면 invariant "
            "FAIL, invariant 를 지키면 문언 이탈이므로 완전 준수 구현이 "
            "존재하지 않는다. golden 이 쓰는 정련 walk ('최저 2개 순서 "
            "merge') 를 정식 pin 으로 승격해야 한다. 문언 walk 은 "
            "비겹침을 깨므로 내림차순 fold 정리의 전건도 파괴한다 "
            "(같은 annex 에서 계측) — 값 축에서도 대안이 아니다.",
            "**벡터 artifact 오염 경로 차단 (구현 결함, C1 자체 감사).** "
            "이전 emit 경로는 값 계약 위반 trial 의 EFT 산출 (bits) 을 "
            "기대 RESULT 로 벡터 파일에 박았고, self-verify 가 같은 EFT "
            "경로를 재실행해 대조했으므로 자기확인 루프였다 — 그대로 "
            "3a-C3/C4 TB 가 소비하면 RTL 이 버그를 재현하도록 강제된다. "
            "이제 emit 은 bits != ref_bits 를 loud fault 로 거부하고, "
            "self-verify 는 EFT 무의존 Fraction 경로로 RESULT 를 재확인 "
            "한다. 반례 2건은 삭제하지 않고 c1_regress 영구 회귀 벡터로 "
            "고정했다 (기대값 = 값 계약 우변; ASC 회귀 시 즉시 FAIL).",
            "**§27.7a.5 (c) 선공표 미이행 — 3a-C1 초안의 계약 위반, 본 "
            "산출물에서 정정 (amendment-7).** 선공표 (c) 는 invariant "
            "sweep 을 '동일 operand **전 벡터**에서 bit-equal **전수** "
            "assert' 로 못박았는데, 초안 구현은 별도 seed 스트림 12,000 "
            "만 돌렸고 그 generator 목록에서 **적대 3가족 "
            "(eft_cancel_chain — C1 반례가 나온 바로 그 가족 — / "
            "eft_adv_residue / eft_top_cancel)** 이 빠져 있었다. 가족 "
            "sweep 과 c1_regress 는 main twin 을 아예 호출하지 않아 값 "
            "계약 trial 대부분이 invariant 검사를 받지 못했고, 이 축소는 "
            "spec·report·vec_contract 어디에도 공시되지 않았다. 정정: "
            "invariant 대조를 **값 계약 전 trial 에 전수**로 걸고 "
            "(checks.invariant_sweep.by_family 로 가족별 공시), 전용 "
            "스트림의 generator 도 FAM_GENS 전 가족으로 넓혔다. "
            "**추가로, 초안이 남긴 원인 진단 '양 경로가 같은 결함 "
            "표면을 공유해 invariant 축에 판별력이 없었다' 는 거짓이다** "
            "— main twin 은 golden_lattice.wave_step 이라 EFT fold 를 "
            "공유하지 않으며, 폐기 ASC 를 걸면 값 위반을 "
            "checks.invariant_sweep.discriminating_power 대로 검출한다. "
            "0 mismatch 였던 진짜 원인은 **가족 커버리지 결손**이다. "
            "원인을 잘못 적으면 '구조적 한계' 로 읽혀 최강 안전망 "
            "(독립 main-path twin × 적대 가족) 이 미배선으로 남는다.",
            "**선공표 실측 주장은 report 필드로 고정한다 (§25.4 사각 "
            "차단).** amendment-5 의 'ASC 는 이 가족에서 정리를 거의 "
            "전부 위반' 과 amendment-2 의 '전 merge 정렬합 <= 47 bit' 는 "
            "둘 다 load-bearing 근거인데 초안 report 에 대응 필드가 없어 "
            "재실행 byte-identical 보호 밖이었다 (회귀 시 조용히 거짓이 "
            "된다). 이제 checks.asc_detection_rate_by_family 와 "
            "checks.expansion_capacity.merge_aligned_width_max 로 "
            "수록하고 spec 은 그 필드를 인용한다. 정렬합 폭의 **강제 "
            "경계는 48 (초과 = loud fault)** 이고 47 은 실측 관측치일 "
            "뿐임도 같은 필드에 명시했다.",
            "**amendment-3 의 cycle 판정에는 미계상 축이 있다 (정직 "
            "표기).** 그 판정은 AddWide pass 수만 논거로 삼았으나, "
            "amendment-2 가 새로 pin 한 정련 walk 은 (e, top) 정렬 "
            "대기열에 임의 위치 삽입을 매 merge 조각마다 수행한다 — 이 "
            "비교/삽입 cycle 은 twosum_passes 에 전혀 계상되지 않는다. "
            "checks.insertion_queue_cost 에 실측 (스캔 step 최대/총합, "
            "삽입 호출 최대) 을 싣고, spec amendment-3 에 '미계상 — "
            "3a-C3 실측 축' 을 명시했다. cycle <= 10,000 hard 상한과 "
            "GATE V20-4 선공표 수치는 불변이며 판정은 ESTIMATE 유지다.",
            "**선공표 (a) 는 '재사용' 이 아니라 '신규 생성' 으로 "
            "이행됐다 (대체 사실 기록, §12a 규칙 5).** (a) 문언은 "
            "'재생성 고정-seed 36,000 재사용' 인데, 그 36,000 은 "
            "acc_format_study 의 곱 (m,e) 수준 스트림이라 §27.7a.1 의 "
            "A||B operand 인터페이스에 그대로 투입할 수 없다. 본 C1 은 "
            "동일 성격의 적대 가족을 operand 수준에서 재구성해 자체 "
            "고정 seed 로 신규 생성했다 — '하한 충족' 재해석만 남기지 "
            "않고 대체 사실과 사유를 "
            "prannounced_plan_conformance.a_value_contract_stream 및 "
            "amendment-6 에 명기한다.",
            "**§27.7a.5 파일명 불일치 (미해소).** 선공표는 "
            "`scripts/golden_fdot32_cr.py` 인데 실제 파일은 "
            "`scripts/golden_fdotcr.py` 다 — 둘 중 하나를 §12a "
            "amendment 로 정정해야 한다 (본 C1 은 spec 측 문언을 실제 "
            "파일명으로 맞추는 amendment-4 를 기록).",
        ],
        "verdicts": {
            "value_contract_zero_mismatch":
                counters["value_mismatch"] == 0,
            "fold_theorem_insertion_scope_zero_mismatch":
                counters["fold_mismatch"] == 0,
            "fold_general_form_asc_pin_refuted":
                annex["asc_refuted_pin"]["verdict_general_form"]
                == "REFUTED",
            "fold_general_form_desc_pin_holds":
                annex["desc_adopted_pin"]["verdict_general_form"] == "PASS",
            "spec_literal_walk_refuted": True,
            "jam_margin_floor_25_held": counters["jam_margin_lt25"] == 0,
            "freeze_property_held": counters["freeze_violations"] == 0,
            "invariant_bit_exact":
                counters["invariant_mismatch"] == 0,
            "invariant_full_sweep_no_family_excluded":
                counters["invariant_trials"] == counters["eft_trials"]
                and set(inv_by_fam) >= {f for f, _ in FAM_GENS},
            "invariant_axis_discriminating":
                sum(v["value_violations_caught_by_main_twin"]
                    for v in asc_by_fam.values())
                == sum(v["value_violations"]
                       for v in asc_by_fam.values())
                and sum(v["value_violations"]
                        for v in asc_by_fam.values()) > 0,
            "special_contrast_axis_established": True,
            "capacity_fault_loud": True,
            "vector_file_self_verified": True,
            "c0_pin_refuted_by_c1_measurement": True,
        },
    }
    REPORT_PATH.write_text(json.dumps(report, indent=1, allow_nan=False,
                                      ensure_ascii=False) + "\n")
    print("wrote %s" % VEC_PATH)
    print("wrote %s" % CONTRACT_PATH)
    print("wrote %s" % REPORT_PATH)
    print("total %.1fs" % (time.time() - t0))
    print("headlines:")
    print("  value contract: %d trials, %d mismatch"
          % (counters["eft_trials"], counters["value_mismatch"]))
    print("  fold theorem (insertion scope): %d checks (%d adversarial), "
          "%d mismatch" % (counters["fold_checks"], dedicated_fold_adv,
                           counters["fold_mismatch"]))
    print("  fold general-form annex: ASC(폐기) %s — random %d/%d diverge"
          " | DESC(채택) %s — random %d/%d"
          % (annex["asc_refuted_pin"]["verdict_general_form"],
             annex["asc_refuted_pin"]["random_sweep"]["fold_ne_rto48"],
             N_SYNTH,
             annex["desc_adopted_pin"]["verdict_general_form"],
             annex["desc_adopted_pin"]["random_sweep"]["fold_ne_rto48"],
             N_SYNTH))
    print("  fold jam 마진: 최소 %s (>=25 요구), margin<25 %d, freeze 위반 "
          "%d, 실질 jam trial %d"
          % (counters["jam_margin_min"], counters["jam_margin_lt25"],
             counters["freeze_violations"], counters["jam_trials"]))
    print("  문언 walk annex: 비겹침 위반 trial %d/%d (%s), 그 열에서 "
          "DESC fold 붕괴 %d"
          % (lit["density_sweep"]["trials_with_nonoverlap_violation"],
             lit["density_sweep"]["trials"],
             lit["density_sweep"]["trial_violation_rate"],
             lit["density_sweep"]["violating_columns_breaking_descending_"
                                  "fold"]))
    print("  invariant: %d trials, %d mismatch"
          % (counters["invariant_trials"], counters["invariant_mismatch"]))
    print("  specials: %d trials (axis = sticky, main NaN-free OK)"
          % counters["special_trials"])
    print("  expansion: max %d components (cap %d), twosum passes max %d "
          "(<=528), fold passes max %d"
          % (counters["exp_max"], EXP_CAP, counters["twosum_passes_max"],
             counters["fold_passes_max"]))
    print("  invariant 검출력: ASC 값 위반 %d 중 main twin 검출 %d"
          % (report["checks"]["invariant_sweep"]["discriminating_power"]
             ["asc_value_violations"],
             report["checks"]["invariant_sweep"]["discriminating_power"]
             ["caught_by_main_twin"]))
    print("  대기열 유지 (미계상 cycle 축): insort 스캔 step 최대 %d, "
          "총합 %d" % (counters["insort_steps_max"],
                       counters["insort_steps_total"]))
    print("  merge 정렬합 폭 최대 %d bit (강제 경계 %d), merge %d회"
          % (counters["merge_width_max"], Q48,
             counters["merge_count_total"]))
    print("  vectors: %d lines, sha256 %s"
          % (len(em.lines), report["vector_file"]["sha256"][:16]))

    # ---- 종료 코드 (§27.7a.5 (a) 의 "assert" 이행) --------------------
    # counter-only 는 문언 이탈이다 — 벡터 수록분 밖에서 나는 실패가
    # exit 0 인 채 JSON 만 FAIL 이 되면, 종료 코드에 물린 gate 배선을
    # 통과해버린다. report 를 **먼저 쓴 뒤** (반례 은닉 금지) 비영으로
    # 종료한다.
    fails = []
    if counters["value_mismatch"]:
        fails.append("값 계약 mismatch %d" % counters["value_mismatch"])
    if counters["fold_mismatch"]:
        fails.append("fold 정리 mismatch %d" % counters["fold_mismatch"])
    if counters["invariant_mismatch"]:
        fails.append("invariant mismatch %d"
                     % counters["invariant_mismatch"])
    if counters["jam_margin_lt25"]:
        fails.append("jam 마진 <25 %d" % counters["jam_margin_lt25"])
    if counters["freeze_violations"]:
        fails.append("freeze 위반 %d" % counters["freeze_violations"])
    if counters["invariant_trials"] != counters["eft_trials"]:
        fails.append("invariant 전수 미이행 (%d != %d)"
                     % (counters["invariant_trials"],
                        counters["eft_trials"]))
    if not report["verdicts"]["invariant_axis_discriminating"]:
        fails.append("invariant 축 검출력 실증 실패 (ASC probe)")
    if annex["asc_refuted_pin"]["verdict_general_form"] != "REFUTED":
        fails.append("폐기 ASC pin 의 반증 근거 소실 (annex 가 더 이상 "
                     "REFUTED 를 보이지 않음 — spec 인용 붕괴)")
    if annex["desc_adopted_pin"]["verdict_general_form"] != "PASS":
        fails.append("채택 DESC pin 일반형 FAIL")
    if fails:
        print("  !! MISMATCH DETECTED — report counterexamples 참조 "
              "(감추지 않음): " + "; ".join(fails))
        return 1
    return 0


_FAM_DOCS = {
    "eft_bf16_wide": "전 지수역 임의 bf16 쌍 (±0/DAZ subnormal 산재) — "
                     "cwave_bf16_rand 관례",
    "eft_f16_all": "f16 전 클래스 (normal/subnormal 0.2-0.3/±0) — "
                   "cwave_f16_rand 관례",
    "eft_cancel": "X, -X + 수십 binade 아래 dust — 대규모 상쇄 "
                  "(cwave_cancel)",
    "eft_cancel_chain": "greedy top-8bit canceller 연쇄 — 대규모 상쇄 후 "
                        "미세 잔차 (fold 적대)",
    "eft_tie": "24-bit RNE tie 인접 + bit-48 아래 dust (bf16 1+2^-24, "
               "f16 1+2^-24 subnormal 경유)",
    "eft_ladder": "exponent ladder 2^-252..2^255 급, gap 49-52 — "
                  "expansion 최대 깊이 + 동일 지수 클러스터",
    "eft_same": "전부동일 32쌍 — 동일 곱 32회 삽입 carry/split 체인",
    "eft_pack_edge": "PACK_FINAL 경계 — overflow ~2^128 / FTZ ~2^-126 / "
                     "정확 상쇄 +0",
    "eft_adv_residue": "단위 잔차 (±1) 상단 + 48-경계 gap mid + dust — "
                       "fold 창-하강 표적 공격 (삽입 순서 3종)",
    "eft_top_cancel": "C1 반례 메커니즘 표적 (신설): 8-bit 블록 사슬로 "
                      "top=E0 인 24-bit component + 2^(E0-48) 아래 tail "
                      "(jam 강제) + 마지막 lane 2개로 순수 -2^E0 (상단 "
                      "인접 상쇄). 폐기된 ASC pin 은 여기서 정리를 상시 "
                      "위반한다 — 가족별 실측률은 report 의 "
                      "checks.asc_detection_rate_by_family 참조",
}


if __name__ == "__main__":
    sys.exit(main())      # mismatch = 비영 종료 (gate 배선이 통과 금지)
