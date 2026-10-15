// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// ActivePart — `0xE14` XLATE_ACTIVE_PART 의 결속 워드와 그 수락 판정 (A, D)
// (3.10 v1.0 묶음 RTL 파도 W4, 2026-10-15 신설). 선-formal 계약은 rtl/formal/tla/ActivePart.tla 다.
//
// ## 이 컴포넌트가 무엇이고 무엇이 아닌가
//
// 워드 하나의 *행위*다 — 결속 레지스터 · 값 검사 · 드레인 판정 · (A, D) 귀속 · 판정 사이클의 두 정지.
// 어느 주소가 이 워드인가(구역 · 워드 선택 · 정렬)와 거절의 발화를 FAULT_STATUS `[6]` 에 잇는 것,
// 두 정지를 버스 ready 와 HIU 접수에 거는 것, D 의 원천(CompletionUnit.drainAllZero)을 대는 것은
// 조립(Wt64Top xlateArea)의 결선이다. AbortStaging · CapStatusWord 와 같은 「잴 수 있는 경계」다.
//
//   e-defined.typ:329 「`[8]` APPLIED (A — 마지막 기입이 적용됐는가)」
//   e-defined.typ:329 「`[9]` DRAINED (D — 마지막 기입 수락 에지의 드레인 판정)」
//   e-defined.typ:329 「`[9:8]` *쓰기 무시* (RW 워드 안의 RO 필드」
//   e-defined.typ:329 「`[31:10]` 예약 = 0 (엄격)」
//   e-defined.typ:332 「*값 검사가 먼저다.*」
//   e-defined.typ:332 「버스 수락된 `0xE14` 기입은 어느 것이든 A · D 를 갱신한다」
//   e-defined.typ:332 「어떤 사유든(값 검사 · 드레인 판정) 거절이면 A = 0 이다」
//   e-defined.typ:332 「A = 1 · 무동작 · *fault 없음* — D = 0 이 보고된다」
//   e-defined.typ:332 「v1.0 의 D 는 `0x37C` DRAIN_ALLZERO 다」
//
// ## D 표집 — α (DP-4 · W4-2)
//
//   e-defined.typ:332 「D 는 값 검사와 무관하게 늘 *그 기입 수락 에지 직후의 상태*(같은 사이클의 요청 접수 포함)에 대해 표집한다」
// 수락 사이클 t 에는 기입을 잡기만 한다(actPend · pendV · pendOk). 값 검사 거절의 발화는 t 에 바로
// 낸다. t+1 에 io.drainNow(= 그 사이클의 DRAIN_ALLZERO — t 에지 직후의 상태: t 에 접수된 요청은
// 파이프 단 하나를 이미 차지하고, t 에지에 빠져나간 일은 이미 없다)로 판정해 t+1 에지에 결속 ·
// A · D 를 적용한다. 판정 사이클 t+1 동안 두 정지(stallReq · stallMmio)가 선다 — 판정 뒤 · 적용
// 전에 옛 결속으로 받는 요청과 판정 전 레지스터의 되읽기를 닫는다. 정지는 actPend 그 자체다 —
// 늘이거나 래치하지 않는다(정확히 1 사이클). 정지 사이클의 기입은 버스가 받지 않았으므로 여기서도
// 효과가 없다(acc 의 ¬actPend 항 — 그래서 actPend 는 두 사이클 연속으로 서지 않는다).
// 모델의 대안 β(t 에 ALLZERO ∧ ¬접수 로 판정)는 마지막 일이 같은 에지에 빠져나가는 모서리에서
// 적법한 전환을 거절 + `[6]` 한다 — 정본과 다른 관측이라 α 다 (ActivePart.tla 「설계 결정」).
//
// ## 값의 폭과 절단 별칭
//
// 필드는 8b 고정이고 결속 레지스터는 형상의 partW 다. pendV 는 partW 로 저장한다 — 없는 값(≥ parts)
// 을 자르면 실재 파티션과 별칭이 되는데, 그 기입은 pendOk = 0 이라 적용 가지(applyNow)가 서지 않는다.
// 없는 값 판정은 XlateStaging.partBad 한 정의를 부른다 (파티션을 값으로 받는 표면 — 이 워드가 넷째).
//
// ## GUARD-MAP — ActivePart 열둘 중 열 (req_part_from_bound · unaligned_outside 는 Wt64Top 파일 끝 — xlateArea 결선)
//
// GUARD-MAP: ActivePart.value_first -> valOk = !XlateStaging.partBad(io.wdata(7 downto 0).asUInt, parts) && io.wdata(31 downto 10) === 0 — 없는 값 판정은 maskArea · XlateStaging 과 한 정의다. ¬valOk 인 수락 기입은 pendOk = 0 이라 actPend 사이클의 applyNow 가 pendSame · io.drainNow 와 무관하게 서지 않는다(값 검사가 같은 값 비교 · 드레인 판정보다 먼저) — 절단된 pendV 가 지금 결속과 같아도 무동작 수락(A = 1)이 없다
// GUARD-MAP: ActivePart.rsv_strict -> valOk 의 io.wdata(31 downto 10) === 0 항 — [31:10] 비0 기입은 ¬valOk 로 그 수락 사이클에 badWrite 이고 결속이 움직이지 않으며 A = 0 이다 ([7:0] 만 보고 판정하는 가지가 없다)
// GUARD-MAP: ActivePart.ro_field_ignored -> io.wdata(9 downto 8) 은 valOk · pendV · pendOk · pendSame · applyNow · aReg · dReg · bound 어느 식에도 없다 — 값 검사는 [7:0] 의 partBad 와 [31:10] 의 0 비교 둘뿐이라 [9:8] 의 어떤 값도 거절 · 판정을 바꾸지 않는다 (RW 워드 안의 RO 필드는 쓰기 무시 — 되읽은 A · D 를 그대로 되쓰는 RMW 드라이버가 거절받지 않는다)
// GUARD-MAP: ActivePart.drain_gates_switch -> applyNow = actPend && pendOk && (pendSame || io.drainNow) 이고 bound := pendV 는 when(applyNow) 하나뿐이다 — 다른 값은 판정 사이클의 DRAIN_ALLZERO(io.drainNow)가 1 일 때만 결속을 바꾼다
// GUARD-MAP: ActivePart.same_value_noop -> applyNow 의 pendSame(= pendV === bound) 항 — 같은 값의 적법 기입은 io.drainNow 와 무관하게 applyNow = 1 이라 A = 1 이고 badWrite 의 둘째 항(actPend ∧ pendOk ∧ ¬applyNow)이 서지 않는다(fault 없음). bound := pendV 는 같은 값이라 무동작이다
// GUARD-MAP: ActivePart.ad_every_accept -> when(actPend) { aReg := applyNow; dReg := io.drainNow } — A · D 의 쓰기 허가는 actPend 하나다(적용 여부 · 값 검사 결과와 무관). actPend 는 수락된 정렬 기입(acc)마다 다음 사이클에 선다 — 값 거절이면 applyNow = 0 이라 A = 0 이고 D 는 그래도 표집된다(드레인된 값 거절 = A 0 · D 1)
// GUARD-MAP: ActivePart.d_includes_same_cycle -> dReg 는 actPend 사이클(t+1)의 io.drainNow 를 잡는다 — 기입 사이클(t)의 io.drainNow 를 래치하는 레지스터가 없다. io.drainNow 의 원천은 조립이 대는 CompletionUnit.drainAllZero(0x37C 읽기와 같은 allZero) 이고 t 에 접수된 요청은 t+1 의 파이프 점유에 이미 든다
// GUARD-MAP: ActivePart.pend_stalls_req -> io.stallReq := actPend — 조립이 when(actp.io.stallReq) 로 hiu.io.req.valid 와 io.hiuReq.ready 를 *둘 다* False 로 덮는다(HiuPipeline 의 ready = advance 는 valid 와 무관해 ready 만 내리면 정지 사이클 요청이 s1 에 실리고 재전송된다). 판정 사이클 t+1 에 옛 결속으로 받는 요청이 없다
// GUARD-MAP: ActivePart.pend_stalls_mmio -> io.stallMmio := actPend — 조립이 정렬 0xE14(isAct) 접근의 io.mmio.ready 를 그 사이클 False 로 덮고 그 읽기의 rvalid 원천 resvRd 를 끈다(rvalid 원천은 resvRd 하나 — obsRd 의 ¬actStall 항은 rdata 포착 위생이고 포트 관측 동치다: obsRv 는 rdata 만 고른다). 정지는 isAct 범위다(페이지 전역 정지는 ready 를 보지 않는 날 스트로브 구역에 이중 효과) — 판정 전 레지스터의 되읽기가 수락되지 않는다. 정지 사이클의 0xE14 기입은 acc 의 ¬actPend 항으로 효과가 없다
// GUARD-MAP: ActivePart.reject_loud -> io.badWrite = (acc && !valOk) || (actPend && pendOk && !applyNow) — 값 거절은 수락 사이클 t 에, 드레인 판정 거절은 판정 사이클 t+1 에 선다. 조립이 Wt64Top 클래스 끝의 원천별 sticky io_fault_actCfgBadWrite = StickyFault(actp.io.badWrite, fclr(B_CFG_BADWRITE))로 FAULT_STATUS [6] 에 잇는다(W4 D1 — surfBadWr 합류가 아니다). 조용한 거절 가지가 없다
//
package wt64.top

import spinal.core._

/** `0xE14` 결속 워드 — 결속 · (A, D) · 판정 사이클 정지.
  *
  * @param parts 형상의 파티션 수 (`Wt64Config.xlateParts`). 결속 레지스터 폭은 log2Up(parts) 다.
  */
class ActivePart(val parts: Int) extends Component {
  private val partW = log2Up(parts) max 1

  val io = new Bundle {
    /** 정렬된 `0xE14` 쓰기 스트로브 — 구역 · 워드 선택 · 정렬은 조립이 했다. 정지 사이클(actPend)의
      * 스트로브는 버스가 받지 않은 기입이라 여기서 버린다. */
    val wr         = in port Bool()
    val wdata      = in port Bits(32 bits)
    /** 이 사이클의 DRAIN_ALLZERO — 조립이 CompletionUnit.drainAllZero 를 댄다. */
    val drainNow   = in port Bool()
    /** 결속 파티션 — 조립이 HIU 요청의 파티션으로 잇는다 (요청 파티션 = 접수 시점의 결속). */
    val activePart = out port UInt(partW bits)
    /** 되읽기 값 — `[7:0]` 결속 · `[8]` A · `[9]` D · `[31:10]` 0. */
    val actWord    = out port Bits(32 bits)
    /** 거절 — 값 검사(수락 사이클) · 드레인 판정(판정 사이클). 조립이 FAULT_STATUS `[6]` 로 잇는다. */
    val badWrite   = out port Bool()
    /** 판정 사이클 정지 — 조립이 `0xE14` 접근의 ready 와 HIU 요청 접수에 건다. 둘 다 actPend 그 자체. */
    val stallMmio  = out port Bool()
    val stallReq   = out port Bool()
  }

  // ── 상태 — reset 은 결속 0 · A 0 · D 0 · 판정 대기 없음 ───────────────────
  val bound   = Reg(UInt(partW bits)) init 0
  val aReg    = RegInit(False)
  val dReg    = RegInit(False)
  val actPend = RegInit(False)
  val pendV   = Reg(UInt(partW bits)) init 0
  val pendOk  = RegInit(False)

  // ── 수락 사이클 t — 값 검사 · 기입 포착 ────────────────────────────────
  val acc   = io.wr && !actPend
  val valOk = !XlateStaging.partBad(io.wdata(7 downto 0).asUInt, parts) &&
              io.wdata(31 downto 10) === 0
  actPend := acc
  when(acc) {
    pendV  := io.wdata(7 downto 0).asUInt.resized
    pendOk := valOk
  }

  // ── 판정 사이클 t+1 — D 표집 · 적용 ───────────────────────────────────
  val pendSame = pendV === bound
  val applyNow = actPend && pendOk && (pendSame || io.drainNow)
  when(actPend) {
    aReg := applyNow
    dReg := io.drainNow
  }
  when(applyNow) { bound := pendV }

  io.badWrite   := (acc && !valOk) || (actPend && pendOk && !applyNow)
  io.stallMmio  := actPend
  io.stallReq   := actPend
  io.activePart := bound
  io.actWord    := B(0, 22 bits) ## dReg.asBits ## aReg.asBits ## bound.resize(8).asBits
}
