// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// CapStatusWord — 능력 부재 관측 워드 CAP_STATUS(`0xF8C`, RO) · CAP_CLEAR
// (`0xF90`, WO W1C) 의 행위 (정본 E.1.2 두 행 · E.1.2 규범 「`CAP_STATUS` 비트
// 배정 — 축은 「고칠 동작」으로 가른다」 · §1.6.2 「능력 부재의 조회는 상위
// 계층의 의무다」). 2026-09-21 CAP_STATUS 파도(정본 1126a38, 축 둘→넷)가
// Wt64Top 의 faultArea 에서 추출했다.
//
// ## 이 컴포넌트가 무엇이고 무엇이 아닌가
//
// 워드 하나의 *행위*다 — 축별 sticky · 축별 수락 W1C · 예약 구간 엄격 거절 ·
// 「발화가 해제를 이긴다」. 어느 사건이 어느 축인가(정본 E.1.2 표의 *배정*)는
// 여기 없다 — 축은 불투명 번호이고 배정은 Wt64Top 의 결선(`Fault.C_*`)이
// 든다. 선-formal 모델 rtl/formal/tla/CapWord.tla 가 같은 추상 수준이다.
//
// 능력 부재는 fault 가 아니다 — 이 컴포넌트에 fault 출력 포트가 없는 것이
// 그 이행이다. 예약 위반 기입의 거절은 rsvBad 로만 나가고, 그것을
// FAULT_STATUS `[6]`(거절된 구성 기입)에 잇는 것은 Top 의 몫이다 — 거절은
// *구성 기입*의 오류이지 능력 부재의 오류가 아니다.
//
// 이 컴포넌트가 재지 않는 것: 상류 sticky 와 pass-through 축을 잇는 Top 의
// 결선(clrAcc(0) → reasm.io.capAbsentClear), 축 `[2]` set 의 oValid 유효 한정,
// 축 `[3]` 이 상수 0 이라는 사실 — 전부 Top 의 결선이며 Wt64Top 을 읽는
// 후-formal 태스크는 아직 0건이다 (rtl/README.md 「미측정」).
//
// ## 축 0 이 pass-through 인 이유 — 이중 sticky 레이스
//
// `[0]` 재조립 슬롯 용량의 sticky 는 Reassembly 안(capBit)에 살고 해제는
// 그 유닛의 capAbsentClear 로 간다. 여기서도 sticky 로 들면 sticky 가 둘이
// 된다: 해제 사이클에 상류 레벨이 아직 1 이라(상류의 clear 는 다음 사이클에야
// 레벨에 반영된다) 「발화가 이긴다」 규약이 *상류의 잔상*을 새 발화로 읽어
// 이 워드의 비트가 영영 안 내려간다. 그래서 축 0 은 레벨을 통과시키고
// clrAcc(0) 를 상류의 clear 로 돌려준다 — sticky 는 한 곳에만 산다.
//
// ## 축 3 이 sticky 인데 상수 0 인 이유
//
// 컴포넌트는 일반 계약이다 — 네 축이 대칭이고, `[3]` 연산 미지원의 원천이
// 0건인 것은 이 파일이 아니라 Top 의 사실이다(Top 이 set(3) := False 로
// 묶는다). 그 묶음은 rtl/README.md 「자리는 있고 회로는 없다」 표의 행이
// 든다. 원천이 서는 날 바뀌는 것은 Top 의 한 줄이지 이 파일이 아니다.
//
// ## GUARD-MAP — CapWord 모델 (2026-09-21 신설, 정본 1126a38)
//
// 후-formal 앵커는 rtl/formal/sby/CapStatusWord/capword.sby 다. `CapWord` 는
// lint_guard_map.ENFORCED 안이라(2026-09-22 파도 D 등재) 전수성이 강제되고, 넷 다
// CHECK 이고 넷 다 그 .sby 의 PROVES 가 앵커한다. 부착은 래퍼 모듈(bind 는
// yosys 가 조용히 무시한다 — SharedUnitDepth0 선례) — 필요한 신호가 전부
// 포트라 expose 도 필요 없다.
// GUARD-MAP: CapWord.axis_isolated -> 축 k 의 비트는 io.set(k)·io.clrAcc(k) 만 본다 (아래 `defined` 의 원소 k — 다른 축의 set 도, wdata 의 다른 비트도 그 식에 없다). capword.sby 의 a_isolated_1/2/3 · a_rise_only_by_set_1/2/3 · a_passthru_0 이 「축 k 의 set 없이 word(k) 가 서지 않는다」를 잰다 — 축 k 의 set 이 축 j 도 세우게 한 변이가 반례를 낸다.
// GUARD-MAP: CapWord.sticky_until_clear -> stickyHere(k) 축은 StickyFault(io.set(k), io.clrAcc(k)) 다 — 내리는 항은 *그 축의 수락된 W1C* clrAcc(k) 하나뿐이고 읽기·시간 경과는 식에 없다. capword.sby 의 a_sticky_1/2/3 · a_clear_1/2/3 (차기상태 등식). 축 0 은 pass-through 라 여기서 재지 않는다 — 그 sticky 는 Reassembly.capBit 이고 Reassembly_props.sv 의 t_capa_next_eq 가 잰다 (lint_postformal `_PARTIAL` 등재).
// GUARD-MAP: CapWord.clear_atomic -> accept = io.wr && !io.rsvBad 이고 clrAcc(k) = accept && wdata(k) 다 — 예약 `[31:nBits]` 에 1 이 있는 기입은 어느 축의 clrAcc 도 세우지 않고 rsvBad 만 세운다 (반쯤 수락이 없다 — E.1.1 「워드 안의 인코딩」 3항의 거절 + loud · E.1.2 CAP_CLEAR 행의 「(엄격)」). capword.sby 의 a_clear_atomic · a_rsvbad_def · a_clracc_def — 예약 마스크를 `[31:2]` 로 넓힌 변이가 반례를 낸다.
// GUARD-MAP: CapWord.set_beats_clear -> StickyFault 규약을 그대로 승계한다 — wt64.Common 의 StickyFault 는 when(clear) 뒤에 when(set) 을 두어 같은 사이클이면 set 이 이긴다. capword.sby 의 a_set_beats_clear_1/2/3 — 해제가 이기게 한 변이가 반례를 낸다. 축 0 은 pass-through 라 이 컴포넌트에 그 겹침이 없다 (Reassembly.capBit 이 같은 규약을 갖고 t_capa_next_eq 가 잰다 — `_PARTIAL` 등재).

package wt64.host

import spinal.core._
import wt64.StickyFault

object CapStatusWord {
  /** CAP_CLEAR 예약 마스크 — 정의 비트 nBits 의 *여집합*으로 유도한다 (Wt64Top
    * companion 의 `rsv()` 와 같은 유도 — 두 상수가 따로 표류할 자리를 없앤다;
    * 같은지는 Top 이 elaborate 시점 `require` 로 못박는다). */
  def rsvMask(nBits: Int): Long = (~((1L << nBits) - 1)) & 0xFFFFFFFFL
}

/** 능력 부재 관측 워드 — CAP_STATUS 읽기 값과 CAP_CLEAR 의 축별 W1C.
  *
  * @param nBits      정의 비트 수 — `[31:nBits]` 는 RO 예약 = 0 이고 CAP_CLEAR
  *                   의 같은 구간은 엄격(비0 기입은 거절, 한 비트도 안 내린다)
  * @param stickyHere 축별 「sticky 가 여기 사는가」. true 면 word(k) 는
  *                   StickyFault(set(k), clrAcc(k)) — 발화가 해제를 이긴다.
  *                   false 면 word(k) = set(k) 조합 통과 — sticky 는 상류에
  *                   살고 clrAcc(k) 를 그 상류의 clear 로 돌려주는 것이 Top
  *                   의 의무다 (파일 머리 「이중 sticky 레이스」)
  */
case class CapStatusWord(
    nBits:      Int          = 4,
    stickyHere: Seq[Boolean] = Seq(false, true, true, true),
) extends Component {
  require(nBits >= 1 && nBits < 32, s"nBits=$nBits — 32비트 워드 안의 정의 비트여야 한다")
  require(stickyHere.length == nBits,
    s"stickyHere 길이 ${stickyHere.length} ≠ nBits $nBits — 축마다 sticky 거처를 하나씩 정한다")

  /** 예약 구간 `[31:nBits]` 마스크 — Top 이 자기 `CAP_CLEAR_RSV` 와 대조한다. */
  val rsvMask: Long = CapStatusWord.rsvMask(nBits)

  val io = new Bundle {
    /** 축별 set. pass-through 축은 상류 sticky 의 *레벨*, sticky 축은 펄스/레벨. */
    val set    = in  port Bits(nBits bits)
    /** CAP_CLEAR 워드 기입 strobe — 정렬·구역·워드 선택은 Top 이 이미 했다. */
    val wr     = in  port Bool()
    val wdata  = in  port Bits(32 bits)
    /** CAP_STATUS 읽기 값. `[31:nBits]` = 0. */
    val word   = out port Bits(32 bits)
    /** wr 이면서 예약 구간에 1 — 거절. Top 이 이것으로 FAULT_STATUS `[6]` 을
      * 세운다 (구성 기입의 오류). 이 컴포넌트에 fault 포트는 없다. */
    val rsvBad = out port Bool()
    /** 수락된 축별 W1C 펄스 — sticky 축은 안에서 소비하고, pass-through 축은
      * Top 이 상류 sticky 의 clear 로 나른다. accept = wr && !rsvBad. */
    val clrAcc = out port Bits(nBits bits)
  }

  // ── 수락 판정 — 예약 위반은 한 비트도 내리지 않는다 (clear_atomic) ────────
  private val rsvHit = (io.wdata & B(rsvMask, 32 bits)) =/= 0
  io.rsvBad := io.wr && rsvHit
  private val accept = io.wr && !io.rsvBad
  private val clrAcc = Vec((0 until nBits).map(k => accept && io.wdata(k)))
  io.clrAcc := clrAcc.asBits

  // ── 축별 비트 — 축 k 는 set(k)·clrAcc(k) 만 본다 (axis_isolated) ────────
  // sticky 축은 wt64.Common 의 StickyFault 그대로 — 해제와 발화가 같은 사이클
  // 이면 발화가 이긴다 (set_beats_clear). pass-through 축은 조합 통과.
  private val defined = Vec((0 until nBits).map { k =>
    if (stickyHere(k)) StickyFault(io.set(k), clrAcc(k)) else io.set(k)
  })
  io.word := B(0, 32 - nBits bits) ## defined.asBits
}
