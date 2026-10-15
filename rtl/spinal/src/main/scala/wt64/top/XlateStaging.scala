// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// XlateStaging — 변환 저장소의 *호스트 쪽 문* (3.10 v1.0 묶음 RTL 파도 W3, 2026-10-13 전면 재작성).
//
// `0xC00` 형상 비노출 항목 표면(파티션 기저 `0xC00` + (p ≪ 7) 마다 VPN · FRAME · COMMIT ·
// VPN_HI · 예약-엄격 28 워드)의 스테이징 · 커밋과 `0xE00` 구역(XLATE_FLUSH · XLATE_MISS_CLEAR ·
// RO 세 워드의 쓰기)의 처분을 한 경계에 둔다. 선-formal 계약은 rtl/formal/tla/XlateSurface.tla
// 이고, 그 모델이 「문」이라 부른 것이 정확히 이 컴포넌트다 — 상위(Wt64Top xlateArea)는 구역
// 선택 · 정렬만 가려 워드 오프셋과 스트로브를 넘기고, 하류(HiuPipeline 이 품은 XlateStore)는
// install · flush 두 포트로만 닿는다. 앞판(파도 3 · 4)은 호스트가 항목 번호(파티션 · 색인)를
// 지목하는 LO/HI 직접 배열의 문이었다 — 그 표면은 정본에서 사라졌다.
//
// ## 이 문은 형상을 모른다 (DP-1 · DP-3 갈래 A″)
//
// 호스트는 VPN 을 쓰고 칸은 장치가 정한다 —
//   e-defined.typ:297 「호스트는 (VPN, 프레임, 권한)만 기입하고 장치 안 어느 칸에 둘지는 *장치가 정한다*」
// 그래서 커밋 번들은 색인 · 태그가 아니라 VPN 32b 를 그대로 낸다. 분할(칸 = VPN 하위 비트 ·
// 태그 = 나머지 — 직접 사상 · 연관도 1)은 조립이 XlateStore.idxOf/tagOf 로 하고, 조회도 같은
// 함수를 부른다 — 분할의 정의가 저장소에 하나다. 이 컴포넌트의 파라미터는 파티션 수 하나다.
//
// ## 하류 정지 — 주소 · 스테이징 상태만 본다
//
// 하류 채움 슬롯이 찬 동안의 *적법한* COMMIT 은 버스 정지다 —
//   e-defined.typ:308 「정지 중에는 효과가 없고, 수락되면 커밋되며, 드롭하지 않는다」
// 정지의 정의역(needReady)은 주소와 스테이징 상태다 — wdata 를 보지 않는다. 주소 · 상태 사유의
// 거절은 needReady 가 0 이라 ready 를 내리지 않는다 —
//   e-defined.typ:308 「기다리지 않고 곧장 거절 + `[6]` 이다」
// 데이터 필드 사유(FRAME 유효 없는 V=1 · `[27:0]` 비0)는 정지를 받고, 풀린 수락 사이클에
// 거절된다 —
//   e-defined.typ:308 「수락 사이클에 거절된다 — 그 수락은 위 유계 정지 뒤일 수 있다」
// 그래서 거절선이 둘이다. badWrite(주소 · 상태 사유 · 0xE00 구역)는 installReady 를 콘에 두지
// 않고, badData(= cmAcc ∧ cmDataBad — 수락된 COMMIT 의 데이터 사유)는 installReady 를 콘에
// 둔다. 상위는 badWrite 를 조립 sticky(surfBadWr)에, badData 를 원천별 sticky
// (io.fault.xlateCfgBadWrite)에 잇고 둘이 FAULT_STATUS `[6]` 에서 합류한다 (DP-15 — FP_BIND
// 예약 거절의 fpBindArea 와 같은 이유: 조립 sticky 의 콘에 절단 핀 installSlotFree 가 들면
// 조립 cover 의 절단 무관 증인 판별이 운다). ready 덮어쓰기(상위)는 needReady 만 본다 —
// 그 콘에 wdata 가 없다는 것을 scripts/lint_ready_cone.py 가 생성물에서 잰다.
// 정지는 유계다 — 정지된 COMMIT 이 버스를 잡고 있어 새 설치가 오지 않는 동안 XlateStore 의
// commitFire(= fillPend.orR)가 매 사이클 한 파티션씩 비우므로 xlateParts 사이클 안에 슬롯이
// 빈다 (DP-21 — 측정은 xlatestore.sby · XlateDoor/door.sby).
//
// ## 스테이징 — 하나, 유효 둘
//
//   e-defined.typ:311 「VPN 기입은 기입 주소의 파티션을 래치하고 FRAME 스테이징 유효를 내린다」
//   e-defined.typ:311 「FRAME 기입은 래치 파티션과 같은 기저에서만 수락한다」
//   e-defined.typ:311 「V=1 COMMIT 은 *FRAME 유효*를 요구한다」
//   e-defined.typ:311 「V=0 COMMIT 은 VPN 유효만 요구한다」
//   e-defined.typ:306 「커밋은 스테이징을 소진하지 않는다」
//   e-defined.typ:308 「수락된 VPN_HI 기입은 FRAME 스테이징 유효를 내린다.」
//   e-defined.typ:311 「래치 파티션에 대한 *수락된* flush 가 두 스테이징 유효를 모두 내린다」
// VPN_HI 스테이징 레지스터는 두지 않는다 — v1.0 은 0 만 수락하므로 값이 늘 0 이다 (VA 확장 판이
// 그 워드를 관대로 열 때 더한다). V=0 COMMIT 의 권한 `[30:28]` 은 수락한다(DP-20 — 정의된
// 필드이고 예약은 `[27:0]` 뿐이다. V=0 항목은 적중하지 않으므로 값은 관측되지 않는다).
//
// ## 권한 필드의 비트 배정 — 호스트 ABI
//
//   e-defined.typ:308 「`[30]` R · `[29]` W · `[28]` X」
// 하네스(XlateStaging_props.sv · Wt64Top_props.sv)가 필드 등식으로 이 배정을 핀한다.
//
// ## 형상 밖 파티션 (판정 T4 (ii))
//
//   e-defined.typ:424 「상한 아래 형상에서는 그 주소가 없는 파티션을 가리키고」
//   e-defined.typ:311 「없는 파티션 기저로의 기입은 어느 워드든 거절 + `[6]` 이」
// 기본 형상(파티션 4)에서 이 가지는 elaborate 상수 False 다 — 파티션 2 판(XlateStagingP2.sv)을
// XlateStaging/p2.sby 가 잰다.
//
// ## GUARD-MAP — XlateSurface 스물아홉 중 스물넷 (넷은 hiu/XlateStore.scala 끝, commit_replaces_vpn 은 Wt64Top xlateArea 아래)
//
// GUARD-MAP: XlateSurface.frame_stages_only -> vpnOk · frOk · vhOk 의 when 본문은 스테이징 레지스터(stgVpn · stgPart · stgVpnValid · stgFrame · stgFrameValid)만 대입하고 commit.valid · flush.valid · missClr 어느 식에도 그 셋이 항으로 들지 않는다 — 하류 표를 움직이는 원천은 commit · flush 두 포트뿐이다 (XlateStore 의 validBits · fillPend · store 기입 원천 전수가 install · flush 둘)
// GUARD-MAP: XlateSurface.commit_fires -> commit.valid = cmAcc ∧ ¬cmDataBad, cmAcc = needReady(= wrEnt ∧ isCommit ∧ pairOk) ∧ installReady — 상위가 그 기입의 mmio ready 로 쓰는 바로 그 신호(installSlotFree)다. 흡수 가지가 없다: 적법 COMMIT 은 installReady = 0 이면 아무것도 움직이지 않고 상위가 버스를 정지시키며, installReady = 1 인 사이클에 커밋되거나(데이터 적법) badData 로 거절된다
// GUARD-MAP: XlateSurface.commit_base_match -> pairOk 의 stgPart === entPart 항 — 래치 파티션과 다른 기저의 COMMIT 은 needReady 가 서지 않아 commit.valid 없이 같은 사이클 badWrite(entRej 의 isCommit ∧ ¬pairOk) 이고 ready 를 내리지 않는다(곧장 거절 — 주소 · 상태 절반은 props.sby p_need_iff · assembly a_ready_only_slot 이 잰다)
// GUARD-MAP: XlateSurface.commit_needs_vpn -> pairOk 의 stgVpnValid(RegInit False — reset 은 빈 스테이징) 항 — VPN 이 한 번도 수락되지 않았거나 래치 파티션 flush 가 내린 뒤의 COMMIT 은 기저와 무관하게 거절 + badWrite 이고 needReady 가 서지 않는다
// GUARD-MAP: XlateSurface.commit_whole -> commit 번들 하나가 그 항목의 전 필드를 한 사이클에 나른다 — vpn = stgVpn · frame = stgFrame(스테이징), perm · v = 이 COMMIT 워드 [30:28] · [31], part = 기입 기저(entPart). XlateStore 는 installFire 한 에지에 채움 줄 전체를 싣고 fillShadow 가 그 에지부터 같은 칸의 옛 판을 가린다
// GUARD-MAP: XlateSurface.vpn_drops_frame -> when(vpnOk) 와 when(vhOk) 의 본문이 둘 다 stgFrameValid := False 를 대입한다 — VPN(또는 VPN_HI)의 수락된 기입 뒤에는 새 FRAME 이 수락될 때까지 V=1 COMMIT 이 cmDataBad 로 거절된다
// GUARD-MAP: XlateSurface.commit_needs_frame -> cmDataBad 의 (wdata(31) ∧ ¬stgFrameValid) 항 — FRAME 유효 없는 V=1 COMMIT 은 수락 사이클(cmAcc)에 commit.valid 없이 badData 다. V=0 COMMIT 의 논리곱에는 stgFrameValid 가 없다
// GUARD-MAP: XlateSurface.frame_pair_check -> frOk · vhOk 의 pairOk 항(!phantom ∧ stgVpnValid ∧ stgPart === entPart) — 래치 파티션과 다른 기저이거나 VPN 유효가 없는 FRAME · VPN_HI 는 entRej 로 badWrite 이고 스테이징 레지스터가 부동이다
// GUARD-MAP: XlateSurface.vpnhi_strict -> vhOk 의 (wdata & VPN_HI_RSV) === 0 항 — 비0 VPN_HI 는 vhOk 가 서지 않아 stgFrameValid 가 그대로이고 entRej 의 isVpnHi ∧ ¬vhLegal 로 badWrite 다
// GUARD-MAP: XlateSurface.rsvw_rejected -> isRsvw(= entWord ≥ W_RSV_FIRST — 기저 +0x10..+0x7C 의 28 워드)의 항목 구역 쓰기는 entRej 로 badWrite 이고 vpnOk · frOk · vhOk · needReady 어느 것도 서지 않는다 — 스테이징 · 커밋 · 정지가 없다
// GUARD-MAP: XlateSurface.commit_rsv_strict -> cmDataBad 의 (wdata & COMMIT_RSV) ≠ 0 항 — [27:0] 비0 COMMIT 은 수락 사이클에 commit.valid 없이 badData 다 (needReady 는 이 항을 보지 않는다 — 하류가 찬 동안에는 정지 뒤 거절)
// GUARD-MAP: XlateSurface.flush_fires -> XLATE_FLUSH(0xE00) 의 기입이 예약 [31:8] = 0 이고 [7:0] 이 실재 파티션이면 flush.valid 가 그 사이클에 선다 — 발화 워드 자체가 트리거다. 이 경로는 버스 ready 를 보지 않는다 (0xE00 구역은 ready 를 낮추지 않는다 — 조합 루프 금지)
// GUARD-MAP: XlateSurface.flush_scoped -> flush.part 는 그 기입의 [7:0] 그 자체(실재 파티션만 통과)이고 flush 포트는 파티션 하나를 나른다 — 전 파티션을 한꺼번에 지우는 출력 · 워드가 없다. XlateStore 쪽은 validBits(flush.part) 만 지운다 (Isolation.capacity_partitioned)
// GUARD-MAP: XlateSurface.flush_valid_only -> DELEGATED(XlateStore) — 이 문의 flush 출력은 {valid, part} 뿐이라 데이터를 지울 채널이 없고, 지우는 범위(유효 비트 · 자기 채움 pend)와 저장 Mem 에 flush 발 쓰기 포트가 없다는 사실은 XlateStore.flush_keeps_data 가 증명한다 (xlatestore.sby)
// GUARD-MAP: XlateSurface.flush_part_exists -> [7:0] ≥ 형상 파티션 수인 XLATE_FLUSH 는 flush.valid 를 세우지 않고 badWrite 를 세운다 — 8b 필드를 partW 로 자르는 경로가 없다 (partBad 는 maskArea 와 한 정의 — 아래 companion)
// GUARD-MAP: XlateSurface.flush_rsv_strict -> [31:8] 비0 인 XLATE_FLUSH 는 flush.valid 를 세우지 않고 badWrite 를 세운다 (워드 안 예약 엄격 — FLUSH_RSV)
// GUARD-MAP: XlateSurface.reject_loud -> 주소 · 상태 사유(entRej — 없는 기저 · 예약-엄격 워드 · 짝 불일치 FRAME/VPN_HI/COMMIT · 비0 VPN_HI)와 0xE00 구역 사유(FLUSH 예약 · 없는 파티션 · MISS_CLEAR 예약 · RO 쓰기)는 같은 사이클 badWrite 이고 상위가 surfBadWr → FAULT_STATUS [6] sticky 로 잇는다. 데이터 사유(cmAcc ∧ cmDataBad)는 badData 이고 상위 xlateArea 가 원천별 sticky io.fault.xlateCfgBadWrite 로 받아 faultWords 의 [6] 논리합에 합류시킨다. 하류 거부(installReady = 0)는 거절이 아니라 적법 COMMIT 의 정지다
//
// 나머지 일곱(0xE10 · RO · 스테이징 수명 · 형상 밖 기저)은 파일 끝에 있다.
package wt64.top

import spinal.core._
import wt64.hiu.XlatePerm

object XlateStaging {
  /** 워드 오프셋 폭 — `addr[8:2]`. 항목 구역에서는 {파티션 2b(`addr[8:7]`), 기저 안 워드
    * 5b(`addr[6:2]`)} 이고 제어 구역에서는 하위 5b 가 구역 안 워드 색인이다. 창(512 B)이
    * 고정이라 형상의 함수가 아니다. */
  val WOFF_W     = 7
  val ENT_PART_W = 2
  val ENT_WORD_W = 5

  /** 기저 안 워드 색인 — VPN · FRAME · COMMIT · VPN_HI, 4 이상은 예약-엄격 28 워드. */
  val W_VPN      = 0
  val W_FRAME    = 1
  val W_COMMIT   = 2
  val W_VPN_HI   = 3
  val W_RSV_FIRST = 4

  /** XLATE_ENTRY_VPN `[31:0]` · XLATE_ENTRY_FRAME `[31:0]` — 예약 비트 없음. */
  val VPN_W   = 32
  val FRAME_W = 32

  /** 워드 안 예약, 엄격 — COMMIT `[27:0]` · VPN_HI `[31:0]` · XLATE_FLUSH `[31:8]` ·
    * XLATE_MISS_CLEAR `[31:1]`. */
  val COMMIT_RSV     = 0x0FFFFFFFL
  val VPN_HI_RSV     = 0xFFFFFFFFL
  val FLUSH_RSV      = 0xFFFFFF00L
  val MISS_CLEAR_RSV = 0xFFFFFFFEL

  /** 8b 파티션 필드의 「없는 값」 판정 — **한 정의**. 파티션을 값이나 주소로 받는 표면
    * 다섯(XLATE_FLUSH · MASK_PART · MASK_REKEY · 0xE14 결속 값(ActivePart) · 이 문의 항목 기저 `addr[8:7]`)이 전부
    * 이것을 부른다 (Wt64Top 의 maskArea 포함). 필드가 형상의 값 공간을 다 덮으면 상수
    * False 다. */
  def partBad(field: UInt, parts: Int): Bool =
    if (parts >= (1 << field.getWidth)) False else field >= parts
}

/** 호스트 쪽 문 — 스테이징 · 커밋 · flush 발화 · 미적중 해제의 판정.
  *
  * @param parts 형상의 파티션 수 (`Wt64Config.xlateParts`). 저장 칸 수 · 색인 함수는 이
  *              컴포넌트가 모른다 — 커밋은 VPN 을 낸다.
  */
class XlateStaging(val parts: Int) extends Component {
  import XlateStaging._

  private val partW = log2Up(parts) max 1

  val io = new Bundle {
    /** 정렬된 기입 스트로브 — `0xC00`–`0xDFF` (항목 표면). */
    val wrEnt = in port Bool()
    /** 정렬된 기입 스트로브 — `0xE00`–`0xE7F` (저장소 제어). */
    val wrCtl = in port Bool()
    /** 워드 오프셋 `addr[8:2]` (companion WOFF_W). */
    val woff  = in port UInt(WOFF_W bits)
    val wdata = in port Bits(32 bits)
    /** 하류 슬롯 여유 — HiuPipeline `installSlotFree`(XlateStore 의 !fillPend(part) — flush 와
      * 무관). 상위는 needReady 인 COMMIT 쓰기의 mmio ready 를 같은 신호로 구동한다. */
    val installReady = in port Bool()
    /** 주소 · 스테이징 상태로 적법한 COMMIT 쓰기 — 하류 수락을 기다리는 쓰기는 이것뿐이다
      * (상위의 ready 덮어쓰기 전건). wdata 를 보지 않는다. */
    val needReady = out port Bool()

    /** 커밋 — 상위가 XlateStore.idxOf/tagOf 로 vpn 을 갈라 install 포트로 잇는다. part 는
      * valid 와 무관하게 그 기입의 기저에서 나온다 (installReady 가 그 파티션의 슬롯을 보게). */
    val commit = new Bundle {
      val valid = out port Bool()
      val part  = out port UInt(partW bits)
      val vpn   = out port UInt(VPN_W bits)
      val frame = out port UInt(FRAME_W bits)
      val perm  = out(XlatePerm())
      val v     = out port Bool()
    }
    /** 파티션 flush 발화 — XlateStore flush 포트로 간다. */
    val flush = new Bundle {
      val valid = out port Bool()
      val part  = out port UInt(partW bits)
    }
    /** XLATE_MISS_CLEAR `[0]`=1 의 수락된 기입 — 미적중 sticky 해제 펄스.
      * 정지는 풀지 않는다 — 그 배선이 없다 (정지를 푸는 것은 항목 기입뿐). */
    val missClr  = out port Bool()
    /** 주소 · 상태 사유와 0xE00 구역의 거절 — 상위의 surfBadWr (FAULT_STATUS `[6]`).
      * 콘에 installReady 가 없다. */
    val badWrite = out port Bool()
    /** 데이터 필드 사유의 COMMIT 거절 — 수락 사이클(cmAcc)에만 선다. 상위의 원천별
      * sticky io.fault.xlateCfgBadWrite (FAULT_STATUS `[6]` 합류). */
    val badData  = out port Bool()
  }

  // ── 워드 디코드 ─────────────────────────────────────────────────────
  private val entPart  = io.woff(WOFF_W - 1 downto ENT_WORD_W)   // addr[8:7]
  private val entWord  = io.woff(ENT_WORD_W - 1 downto 0)        // addr[6:2]
  private val isVpn    = entWord === W_VPN
  private val isFrame  = entWord === W_FRAME
  private val isCommit = entWord === W_COMMIT
  private val isVpnHi  = entWord === W_VPN_HI
  private val isRsvw   = entWord >= W_RSV_FIRST
  private val ctlWord  = io.woff(4 downto 0)
  private val isFlush  = ctlWord === Wt64Top.Xctl.FLUSH / 4
  private val isMissC  = ctlWord === Wt64Top.Xctl.MISS_CLEAR / 4
  private val isCtlRo  = ctlWord === Wt64Top.Xctl.STATUS / 4 ||
                         ctlWord === Wt64Top.Xctl.MISS_VPN_LO / 4 ||
                         ctlWord === Wt64Top.Xctl.MISS_VPN_HI / 4

  /** 형상 밖 파티션의 기저 (판정 T4 (ii) — 기본 형상에서 elaborate 상수 False). */
  private val phantom = partBad(entPart, parts)

  // ── 스테이징 — 하나, 유효 둘 (reset = 빈 스테이징) ─────────────────────
  val stgVpnValid   = RegInit(False)
  val stgFrameValid = RegInit(False)
  val stgPart       = Reg(UInt(ENT_PART_W bits)) init 0
  val stgVpn        = Reg(Bits(VPN_W bits)) init 0
  val stgFrame      = Reg(Bits(FRAME_W bits)) init 0

  /** 짝 검사 — 실재 기저 ∧ VPN 유효 ∧ 래치 파티션의 기저. FRAME · VPN_HI · COMMIT 이 받는다. */
  private val pairOk  = !phantom && stgVpnValid && stgPart === entPart
  private val vhLegal = pairOk && (io.wdata & B(VPN_HI_RSV, 32 bits)) === 0

  val vpnOk = io.wrEnt && isVpn && !phantom
  val frOk  = io.wrEnt && isFrame && pairOk
  val vhOk  = io.wrEnt && isVpnHi && vhLegal

  when(vpnOk) {
    stgVpn        := io.wdata
    stgPart       := entPart
    stgVpnValid   := True
    stgFrameValid := False
  }
  when(frOk) {
    stgFrame      := io.wdata
    stgFrameValid := True
  }
  when(vhOk) {
    stgFrameValid := False
  }

  // ── COMMIT — 정지 판정은 주소 · 상태만, 데이터 사유는 수락 사이클에 ─────
  io.needReady := io.wrEnt && isCommit && pairOk
  val cmAcc     = io.needReady && io.installReady
  val cmDataBad = (io.wdata & B(COMMIT_RSV, 32 bits)) =/= 0 ||
                  (io.wdata(31) && !stgFrameValid)

  io.commit.valid  := cmAcc && !cmDataBad
  io.commit.part   := entPart.resized
  io.commit.vpn    := stgVpn.asUInt
  io.commit.frame  := stgFrame.asUInt
  io.commit.perm.r := io.wdata(30)
  io.commit.perm.w := io.wdata(29)
  io.commit.perm.x := io.wdata(28)
  io.commit.v      := io.wdata(31)
  io.badData       := cmAcc && cmDataBad

  // ── XLATE_FLUSH (0xE00) — 기입이 곧 발화, 예약 엄격, 없는 파티션 거절 ──
  private val partField = io.wdata(7 downto 0).asUInt
  private val flRsvBad  = (io.wdata & B(FLUSH_RSV, 32 bits)) =/= 0
  private val flPartBad = partBad(partField, parts)
  private val flWr      = io.wrCtl && isFlush
  io.flush.valid := flWr && !flRsvBad && !flPartBad
  io.flush.part  := partField.resized

  // ── XLATE_MISS_CLEAR (0xE10) — [0]=1 이 해제 · [31:1] 예약 엄격 ─────────
  private val mcRsvBad = (io.wdata & B(MISS_CLEAR_RSV, 32 bits)) =/= 0
  private val mcWr     = io.wrCtl && isMissC
  io.missClr := mcWr && !mcRsvBad && io.wdata(0)

  // ── 거절 — 주소 · 상태 사유 (installReady 를 보지 않는다) ─────────────────
  val entRej = io.wrEnt && (phantom || isRsvw ||
                            ((isFrame || isCommit) && !pairOk) ||
                            (isVpnHi && !vhLegal))
  io.badWrite := entRej ||
                 (flWr && (flRsvBad || flPartBad)) ||
                 (mcWr && mcRsvBad) ||
                 (io.wrCtl && isCtlRo)

  // ── 래치 파티션의 *수락된* XLATE_FLUSH 가 두 유효를 내린다 (값 레지스터는 남는다) ──
  // 파티션 필드 2b 비교로 충분하다 — flush.valid ⇒ [7:0] < parts ≤ 4. 같은 사이클의 수락된
  // VPN 이 이긴다(직렬화 flush → VPN). 상위의 두 구역 스트로브는 주소 디코드로 배타라 조립에서는
  // 도달하지 않고, 문 단독(자유 입력)에서도 어느 직렬화와 같은 상태만 남긴다 — 같은 사이클의
  // 수락된 FRAME 은 직렬화 FRAME → flush 와 같다(두 유효 모두 0). 마지막 대입이라 이긴다.
  val stgFlushDrop = io.flush.valid && !vpnOk &&
                     stgPart === partField(ENT_PART_W - 1 downto 0)
  when(stgFlushDrop) {
    stgVpnValid   := False
    stgFrameValid := False
  }
}

// ── GUARD-MAP 이어서 — XlateSurface 의 `0xE10` · RO 쓰기 다섯 (파도 3 수리 — W3 문면 갱신) ──
//
// 이 다섯은 RTL 이 모델보다 먼저 배선한 결정이었다 (검토자 D-7) — 모델이 뒤따라 실었고 그
// 가드의 RTL 주장이 아래다. 0xE00 구역 처분은 W3 에서 바뀌지 않았다.
//
// GUARD-MAP: XlateSurface.mclr_fires -> XLATE_MISS_CLEAR(0xE10) 의 기입이 [31:1] = 0 이고 [0] = 1 이면 missClr 가 그 사이클에 선다. 상위(Wt64Top xlateArea)가 그것을 IO 해제선과 논리합해 hiu.io.missClear 로 잇고, HiuPipeline 의 io.missNotice := StickyFault(set = missWait, clear = io.missClear) 가 해제로 받는다 — 정지가 없는 사이클이면 sticky 가 내려간다. 정지 중에는 set(missWait 레벨)이 이긴다 (모델 발견 4 — 정지 중 해제의 유실)
// GUARD-MAP: XlateSurface.mclr_needs_one -> missClr 의 논리곱 항에 wdata(0) 가 있다 — [0] = 0 · [31:1] = 0 의 기입은 missClr 도 badWrite 도 세우지 않는다 (적법한 무동작 — 모델의 noop)
// GUARD-MAP: XlateSurface.mclr_rsv_strict -> [31:1] 비0 인 XLATE_MISS_CLEAR 는 missClr 를 세우지 않고 badWrite 를 세운다 (워드 안 예약 엄격 — MISS_CLEAR_RSV)
// GUARD-MAP: XlateSurface.mclr_keeps_stall -> missClr 는 commit.valid · flush.valid 어느 것의 항에도 없고 상위에서 hiu.io.missClear 하나로만 간다. HiuPipeline 의 정지 missWait = s3.valid && !lookAny(lookAny = 판정 래치 ∨ xlate.io.rsp.hit — 3.10 v1.0 묶음 W2 판정 래치) 와 advance 에 missClear 항이 없다 — 정지를 푸는 것은 적중(= 그 (파티션, VPN) 의 V=1 커밋)뿐이다(래치 포착도 적중에서만 선다)
// GUARD-MAP: XlateSurface.ro_rejected -> 0xE04 · 0xE08 · 0xE0C(isCtlRo) 의 쓰기는 badWrite 를 세우고 commit · flush · missClr 어느 것도 세우지 않는다 — 흡수 가지가 없다 (loud 로 잇는 것은 reject_loud 의 surfBadWr → FAULT_STATUS [6])
//
// ── GUARD-MAP 이어서 — 스테이징 수명 · 형상 밖 기저 (판정 T5 (a) · T4 (ii), W3 문면) ──
//
// GUARD-MAP: XlateSurface.flush_drops_staging -> 수락된 XLATE_FLUSH(flush.valid — 예약 [31:8] = 0 · 실재 파티션)의 [1:0] 이 래치 파티션 stgPart 와 같으면 그 사이클 뒤 stgVpnValid · stgFrameValid 가 둘 다 내려간다(stgFlushDrop — 클래스 끝, 마지막 대입). stgVpn · stgPart · stgFrame 은 움직이지 않는다(유효 비트만). 뒤따르는 FRAME · VPN_HI · COMMIT 은 pairOk 의 stgVpnValid 항에서 거절 + badWrite 다(commit_needs_vpn 과 같은 선). 다른 파티션의 flush · 거절된 flush(flush.valid = 0)는 스테이징에 닿지 않는다. 같은 사이클의 수락된 VPN(vpnOk)이 이긴다 — 직렬화 flush → VPN (상위의 두 구역 스트로브는 주소 디코드로 배타)
// GUARD-MAP: XlateSurface.ent_part_exists -> phantom = partBad(entPart, parts)(기저 addr[8:7] ≥ 형상 파티션 수 — 기본 형상 4 에서 elaborate 상수 False)이면 어느 워드든 entRej 로 badWrite 이고 vpnOk · frOk · vhOk · needReady 가 서지 않아 스테이징 다섯 레지스터가 부동이며 commit.valid 가 없다 — 스테이징이 형상 밖 기저를 래치할 수 없으므로 commit.part := entPart.resized 의 절단이 실재 파티션 항목을 설치하는 별칭 경로가 서지 않는다(pairOk 의 !phantom 항은 그 위의 중복 방어다). 파티션 2 판 XlateStagingP2.sv 를 XlateStaging/p2.sby 가 잰다
