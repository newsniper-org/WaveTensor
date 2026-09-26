// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// XlateStaging — 변환 저장소의 *호스트 쪽 문* (파도 3, 2026-09-26).
//
// `0xC00` 항목 배열(XLATE_ENTRY_LO/HI)의 스테이징·커밋과 `0xE00` 구역
// (XLATE_FLUSH · XLATE_MISS_CLEAR · RO 세 워드의 쓰기)의 처분을 한 경계에 둔다.
// 선-formal 계약은 rtl/formal/tla/XlateSurface.tla 이고, 그 모델이 「문」이라
// 부른 것이 정확히 이 컴포넌트다 — 상위(Wt64Top)는 구역 선택·정렬만 가려
// 워드 오프셋과 스트로브를 넘기고, 하류(HiuPipeline 이 품은 XlateStore)는
// install · flush 두 포트로만 닿는다.
//
// ## GUARD-MAP — XlateSurface 열아홉 중 열여덟: 항목·flush 열하나는 여기, `0xE10` · RO 다섯과 판정 T5 · T4 둘은 파일 끝 (hi_v_carried 는 hiu/XlateStore.scala 끝)
//
// GUARD-MAP: XlateSurface.lo_stages_only -> LO 워드의 수락된 기입은 스테이징 세 레지스터(stgValid · stgNum · stgFrame)만 움직이고 commit.valid · flush.valid · missClr 어느 것도 세우지 않는다 — 하류 표를 움직이는 원천은 그 두 포트뿐이다 (XlateStore 의 validBits · fillPend · store 기입 원천 전수가 install · flush 둘)
// GUARD-MAP: XlateSurface.hi_fires -> 스테이징이 차 있고 래치 번호가 그 기입의 번호와 같은 HI 워드 기입(needReady)은 하류가 받을 수 있는 사이클(installReady — 상위가 그 기입의 mmio ready 로 쓰는 바로 그 신호)에 commit.valid 를 세운다 — 흡수 가지가 없다. 수락 전(installReady = 0)의 적법 HI 는 아무것도 움직이지 않고 상위가 버스를 정지시킨다 (D-2 처분 · 모델 Refusal = "stall")
// GUARD-MAP: XlateSurface.hi_entry_match -> 래치 번호(stgNum)와 다른 항목 번호의 HI 는 commit.valid 를 세우지 않고 badWrite 를 세운다 — 스테이징도 움직이지 않는다 (거절된 기입은 기입이 아니다)
// GUARD-MAP: XlateSurface.hi_needs_staging -> stgValid(reset 0) 가 commit.valid 의 논리곱 항이다 — LO 가 한 번도 수락되지 않은 상태의 HI 는 번호와 무관하게 거절 + badWrite 다 (reset 직후 래치 번호의 우연 일치로 쓰이지 않은 프레임이 커밋되는 경로가 없다)
// GUARD-MAP: XlateSurface.hi_commit_whole -> commit 번들 하나가 그 항목의 전 필드를 한 사이클에 나른다 — frame 은 스테이징 LO, tag·perm·v 는 이 HI 워드, part·idx 는 이 워드의 번호. XlateStore 는 install.fire 한 에지에 채움 줄 전체를 싣는다 (가림 fillShadow 가 그 에지부터 그 항목의 옛 판을 가린다)
// GUARD-MAP: XlateSurface.flush_fires -> XLATE_FLUSH(0xE00) 의 기입이 예약 [31:8] = 0 이고 [7:0] 이 실재 파티션이면 flush.valid 가 그 사이클에 선다 — 발화 워드 자체가 트리거다. 이 경로는 버스 ready 를 보지 않는다 (0xE00 구역은 ready 를 낮추지 않는다 — 조합 루프 금지)
// GUARD-MAP: XlateSurface.flush_scoped -> flush.part 는 그 기입의 [7:0] 그 자체(실재 파티션만 통과)이고 flush 포트는 파티션 하나를 나른다 — 전 파티션을 한꺼번에 지우는 출력·워드가 없다. XlateStore 쪽은 validBits(flush.part) 만 지운다 (Isolation.capacity_partitioned)
// GUARD-MAP: XlateSurface.flush_valid_only -> DELEGATED(XlateStore) — 이 문의 flush 출력은 {valid, part} 뿐이라 데이터를 지울 채널이 없고, 지우는 범위(유효 비트 · 자기 채움 pend)와 저장 Mem 에 flush 발 쓰기 포트가 없다는 사실은 XlateStore.flush_keeps_data 가 증명한다 (xlatestore.sby)
// GUARD-MAP: XlateSurface.flush_part_exists -> [7:0] ≥ 형상 파티션 수인 XLATE_FLUSH 는 flush.valid 를 세우지 않고 badWrite 를 세운다 — 8b 필드를 partW 로 자르는 경로가 없다 (partBad 는 maskArea 와 한 정의 — 아래 companion)
// GUARD-MAP: XlateSurface.flush_rsv_strict -> [31:8] 비0 인 XLATE_FLUSH 는 flush.valid 를 세우지 않고 badWrite 를 세운다 (워드 안 예약 엄격)
// GUARD-MAP: XlateSurface.reject_loud -> 거절 다섯 사유 — HI 의 스테이징 빔(reset · 래치 파티션 flush 뒤) · 번호 불일치 · (형상 밖 파티션 — LO 포함) · XLATE_FLUSH 의 없는 파티션 · 예약 비0 — 가 전부 같은 사이클 badWrite 이고, 상위가 그것을 surfBadWr → FAULT_STATUS [6] sticky 로 잇는다. 거절은 하류 상태를 보지 않는다(needReady 가 아닌 HI 는 정지 없이 곧장 거절). 하류 거부(installReady = 0)는 거절이 아니라 적법 HI 의 정지다 (D-2)
//
// ## 설계 판정 — 정본이 닫지 않았던 자리 여섯 (파도 4 판정 T5 로 셋이 정본 문면이 됐다)
//
// 정본은 스테이징의 번호 래치에 더해 이제 수명까지 정한다 (판정 T5 (a), f229c8b) —
//   e-defined.typ:306 「스테이징 레지스터는 *항목 번호를 함께 래치*하고」
//   e-defined.typ:306 「커밋은 스테이징을 소진하지 않는다」
// 무장 규율(소진 포함)을 걸지 않는다는 :180 의 갈래 판정은 그대로다 — 한 워드 쌍 *안의*
// 원자성은 구조가 주고, 임대 경계를 건넌 옛 LO 는 격리의 문제라 flush 가 끊는다:
//   e-defined.typ:180 「원자성이 구조로 성립하고 더 걸 것이」
// 아래 여섯 중 (1)(2)(4) 는 정본 문면, (3)(5)(6) 은 그 위의 선택이고 전부 모델이 먼저 싣는다:
//   (1) HI 커밋은 스테이징을 소진하지 않는다 — 같은 LO 로 HI 를 되풀이하면
//       매번 커밋한다. 소진을 고르면 HI 하나로 V=0 무효화하는 정본 적합
//       드라이버가 거절된다. 같은 임대 안의 재커밋은 그대로 남고, flush(임대 회전 ⑵)를
//       건넌 옛 LO 는 (4) 가 끊는다(교차 항목은 번호 래치가 막는다) — T5 · 모델 판정 1.
//   (2) reset = 빈 스테이징 (stgValid = 0). LO 없이 온 HI 는 거절 + [6] —
//       FAULT_STATUS [6] 폴딩 목록의 기존 원천이지 새 원천이 아니다:
//         e-defined.typ:552 「항목 번호 불일치 · 없는 파티션 값 기입이다」
//       모델 판정 2.
//   (3) 번호 불일치 HI 는 거절이고 스테이징은 불변이다.
//   (4) 래치 파티션의 *수락된* flush 는 스테이징 유효를 내린다(번호·프레임은 남는다) — 파일 끝.
//   (5) LO 재기입은 값과 번호를 덮는다 (스테이징 레지스터는 단수다).
//   (6) 하류 거부로 수락되지 않은 HI 는 아무것도 움직이지 않는다 — 상위가
//       mmio ready 를 내려 같은 기입을 잡아 두고, 슬롯이 비는 사이클에 그
//       기입이 수락된다 (D-2 · 모델의 Refusal = "stall"). 정지는 *적법한* HI
//       에만 걸린다 (needReady — 모델의 Refused(w) 가 ~DevHiBad(w) 를 전건에
//       든 것과 같다). 거절될 HI 는 기다리지 않고 곧장 거절된다 — 그래서 거절
//       선(badWrite)의 콘에 하류 상태(installReady)가 없다. ready 는 여전히
//       *기능적으로* 주소 · 스트로브 · 상태(스테이징)만의 함수다 (wdata 비의존).
//       구조적으로도 그렇다 (파도 4 SLOTFREE 수리): 판정 전에는 조합 경로 wdata →
//       flush.valid(이 컴포넌트) → XlateStore flushSamePart → install.ready → 상위 mmio
//       ready 덮어쓰기가 넷리스트에 있었다(기능적으로는 죽은 경로 — 두 전건 wrEnt ·
//       wrCtl 이 주소 디코드로 배타). 이제 installReady 는 flush 와 무관한 슬롯 여유
//       hiu.installSlotFree(= !fillPend(part))라 그 경로가 없다 — 구조 콘 검사
//       scripts/lint_ready_cone.py 가 ready 의 조합 콘 = {addr, wstrobe} 를 잰다. 기록은
//       rtl/README.md 파도 3 「구조 경로」 · 파도 4 3B 절.
//
// ## HI 권한 필드의 비트 배정 — 호스트 ABI 합의 입력
//
// 정본은 권한 필드를 나열 순서로만 준다 —
//   e-defined.typ:308 「`[30:28]` 권한 R·W·X」
// 이 컴포넌트는
// `[30]` = R · `[29]` = W · `[28]` = X 로 결선한다 — 나열 순서를 상위 비트부터
// 읽은 것이다. 하네스(XlateStaging_props.sv · Wt64Top_props.sv)가 필드 등식으로
// 이 배정을 핀한다.
//
// ## 형상 밖 파티션 — 판정 T4 (ii) (f229c8b)
//
//   e-defined.typ:424 「주소 비트 `addr[8:7]` 2b 이므로 없는 값이 *표현 자체가 불가능*하다」
// 는 형상이 상한(파티션 4)일 때만 할 일이 없고, 상한 아래에서는 —
//   e-defined.typ:424 「상한 아래 형상에서는 그 주소가 없는 파티션을 가리키고」
// 파티션 2 인 형상에서 addr[8:7] ∈ {2,3} 이 표에 있는 오프셋이면서 없는
// 파티션이다. 처분은 판정대로 XLATE_FLUSH 쪽 규범 1항 그대로다 —
//   e-defined.typ:414 「실재하지 않는 파티션 값의 기입은 *수락되지 않고 거절 + loud fault* 다」
// LO · HI 모두 거절 + [6], 스테이징 부동이다 (entPhantom). 기본 형상(4)에서 이 가지는
// elaborate 상수 False 다 — 파티션 2 판(XlateStagingP2.sv)을 XlateStaging/p2.sby 가 잰다.
package wt64.top

import spinal.core._
import wt64.hiu.XlatePerm

object XlateStaging {
  /** 항목 번호 폭 — `addr[8:3]` = {파티션 2b, 색인 4b}. 창(`0xC00` 구역 512 B)이
    * 고정이라 형상의 함수가 아니다 (E.2 5항 — 형상은 그 상한 아래). */
  val NUM_W  = 6
  val IDX_W  = 4
  /** HI `[27:0]` 태그 · LO `[31:0]` 프레임 — 두 워드가 8 B 를 정확히 채운다. */
  val TAG_W   = 28
  val FRAME_W = 32

  /** XLATE_FLUSH `[31:8]` · XLATE_MISS_CLEAR `[31:1]` — 워드 안 예약, 엄격. */
  val FLUSH_RSV      = 0xFFFFFF00L
  val MISS_CLEAR_RSV = 0xFFFFFFFEL

  /** 8b 파티션 필드의 「없는 값」 판정 — **한 정의**. 기입으로 파티션을 받는
    * 표면 셋(XLATE_FLUSH · MASK_PART · MASK_REKEY)이 전부 이것을 부른다
    * (Wt64Top 의 maskArea 포함). 필드가 형상의 값 공간을 다 덮으면 상수
    * False 다. */
  def partBad(field: UInt, parts: Int): Bool =
    if (parts >= (1 << field.getWidth)) False else field >= parts
}

/** 호스트 쪽 문 — 스테이징 · 커밋 · flush 발화 · 미적중 해제의 판정.
  *
  * @param parts 형상의 파티션 수 (`Wt64Config.xlateParts`). 번호 폭은 고정이고
  *              실재 파티션 판정만 이 값의 함수다.
  */
class XlateStaging(val parts: Int) extends Component {
  import XlateStaging._

  private val partW = log2Up(parts) max 1

  val io = new Bundle {
    /** 정렬된 기입 스트로브 — `0xC00`–`0xDFF` (항목 배열). */
    val wrEnt = in port Bool()
    /** 정렬된 기입 스트로브 — `0xE00`–`0xE7F` (저장소 제어). */
    val wrCtl = in port Bool()
    /** 워드 오프셋 `addr[8:2]`. 항목 배열에서는 {번호 6b, 워드 1b} 이고
      * 제어 구역에서는 하위 5b 가 구역 안 워드 색인이다. */
    val woff  = in port UInt(NUM_W + 1 bits)
    val wdata = in port Bits(32 bits)
    /** 하류 슬롯 여유 — HiuPipeline `installSlotFree`(XlateStore 의 !fillPend(part) — flush 와 무관). 상위는
      * needReady 인 HI 쓰기의 mmio ready 를 같은 신호로 구동한다 (파도 4 SLOTFREE). */
    val installReady = in port Bool()
    /** 적법한 HI 쓰기 — 스테이징이 차 있고 번호가 같다. 하류 수락을 기다리는
      * 쓰기는 이것뿐이다 (상위의 ready 덮어쓰기 전건). 이 신호 자신은 wdata 를
      * 보지 않는다 (덮어쓰기 *값*인 installReady 도 wdata 콘이 없다 — 머리 (6)). */
    val needReady = out port Bool()

    /** 커밋 — XlateStore install 포트로 간다. part 는 valid 와 무관하게 그
      * 기입의 번호에서 나온다 (installReady 가 그 파티션의 슬롯을 보게). */
    val commit = new Bundle {
      val valid = out port Bool()
      val part  = out port UInt(partW bits)
      val idx   = out port UInt(IDX_W bits)
      val tag   = out port UInt(TAG_W bits)
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
    /** 거절된 구성 기입 — FAULT_STATUS `[6]` 로 간다 (상위의 surfBadWr). */
    val badWrite = out port Bool()
  }

  // ── 워드 디코드 ─────────────────────────────────────────────────────
  private val isHi   = io.woff(0)
  private val num    = io.woff(NUM_W downto 1)
  private val numPart = num(NUM_W - 1 downto IDX_W)
  private val ctlWord = io.woff(4 downto 0)
  private val isFlush = ctlWord === Wt64Top.Xctl.FLUSH / 4
  private val isMissC = ctlWord === Wt64Top.Xctl.MISS_CLEAR / 4
  private val isCtlRo = ctlWord === Wt64Top.Xctl.STATUS / 4 ||
                        ctlWord === Wt64Top.Xctl.MISS_VPN_LO / 4 ||
                        ctlWord === Wt64Top.Xctl.MISS_VPN_HI / 4

  /** 형상 밖 파티션의 항목 번호 (정본 판정 요청 T4 — 기본 형상에서 상수 False). */
  private val entPhantom = if (parts >= 4) False else numPart >= parts

  // ── 스테이징 — 값 · 래치 번호 · 유효 (reset 0 = 빈 스테이징) ─────────
  val stgValid = RegInit(False)
  val stgNum   = Reg(UInt(NUM_W bits)) init 0
  val stgFrame = Reg(Bits(FRAME_W bits)) init 0

  private val loWr  = io.wrEnt && !isHi
  private val loOk  = loWr && !entPhantom
  when(loOk) {
    stgValid := True
    stgNum   := num
    stgFrame := io.wdata
  }

  // ── HI — 적법하면 하류가 받을 수 있을 때 커밋 (D-2: 정지이지 거절이 아니다) ──
  private val hiWr    = io.wrEnt && isHi
  private val hiLegal = !entPhantom && stgValid && stgNum === num
  private val hiRej   = hiWr && !hiLegal

  io.needReady     := hiWr && hiLegal
  io.commit.valid  := hiWr && hiLegal && io.installReady
  io.commit.part   := numPart.resized
  io.commit.idx    := num(IDX_W - 1 downto 0)
  io.commit.tag    := io.wdata(TAG_W - 1 downto 0).asUInt
  io.commit.frame  := stgFrame.asUInt
  io.commit.perm.r := io.wdata(30)
  io.commit.perm.w := io.wdata(29)
  io.commit.perm.x := io.wdata(28)
  io.commit.v      := io.wdata(31)

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

  // ── 거절 — 전부 한 선 (상위가 FAULT_STATUS [6] 에 잇는다) ────────────────
  io.badWrite := (loWr && entPhantom) || hiRej ||
                 (flWr && (flRsvBad || flPartBad)) ||
                 (mcWr && mcRsvBad) ||
                 (io.wrCtl && isCtlRo)

  // ── 판정 T5 (a) — 래치 파티션의 *수락된* XLATE_FLUSH 가 스테이징 유효를 내린다 ──
  // 번호·프레임은 남는다(유효 비트만). 파티션 필드 2b 비교로 충분하다 — flush.valid ⇒
  // [7:0] < parts ≤ 4. 같은 사이클의 수락된 LO 가 이긴다(직렬화 flush → LO): 상위의
  // 두 구역 스트로브는 주소 디코드로 배타라 조립에서는 도달하지 않고, 문 단독(자유
  // 입력)에서도 어느 직렬화와 같은 상태만 남긴다. 머리의 익명 when 좌표를 밀지 않게
  // 클래스 끝에 두고 조건을 이름 붙인 신호로 둔다 (when_<파일>_l<줄> 이름을 만들지 않는다).
  val stgFlushDrop = io.flush.valid && !loOk &&
                     stgNum(NUM_W - 1 downto IDX_W) === partField(1 downto 0)
  when(stgFlushDrop) { stgValid := False }
}

// ── GUARD-MAP 이어서 — XlateSurface 의 `0xE10` · RO 쓰기 다섯 (파도 3 수리, 2026-09-26) ──
//
// 이 다섯은 RTL 이 모델보다 먼저 배선한 결정이다 (검토자 D-7). 정본 6.3 이
// 「모델에 없는 결정을 구현이 새로 하게 되면 그 결정을 모델로 돌려보낸다」고
// 요구하므로 XlateSurface.tla 가 뒤따라 가드 다섯 · 증인 다섯 · 발견 run 하나
// (정지 중 해제의 유실)로 실었고, 그 가드의 RTL 주장이 아래다. 머리가 아니라
// 끝에 둔 것은 머리 절의 줄 좌표를 밀지 않기 위해서다.
//
// GUARD-MAP: XlateSurface.mclr_fires -> XLATE_MISS_CLEAR(0xE10) 의 기입이 [31:1] = 0 이고 [0] = 1 이면 missClr 가 그 사이클에 선다. 상위(Wt64Top xlateArea)가 그것을 IO 해제선과 논리합해 hiu.io.missClear 로 잇고, HiuPipeline 의 io.missNotice := StickyFault(set = missWait, clear = io.missClear) 가 해제로 받는다 — 정지가 없는 사이클이면 sticky 가 내려간다. 정지 중에는 set(missWait 레벨)이 이긴다 (모델 발견 4 — 정지 중 해제의 유실)
// GUARD-MAP: XlateSurface.mclr_needs_one -> missClr 의 논리곱 항에 wdata(0) 가 있다 — [0] = 0 · [31:1] = 0 의 기입은 missClr 도 badWrite 도 세우지 않는다 (적법한 무동작 — 모델의 noop)
// GUARD-MAP: XlateSurface.mclr_rsv_strict -> [31:1] 비0 인 XLATE_MISS_CLEAR 는 missClr 를 세우지 않고 badWrite 를 세운다 (워드 안 예약 엄격 — MISS_CLEAR_RSV)
// GUARD-MAP: XlateSurface.mclr_keeps_stall -> missClr 는 commit.valid · flush.valid 어느 것의 항에도 없고 상위에서 hiu.io.missClear 하나로만 간다. HiuPipeline 의 정지 missWait = s3.valid && !xlate.io.rsp.hit 와 advance 에 missClear 항이 없다 — 정지를 푸는 것은 적중(= 그 항목의 커밋)뿐이다
// GUARD-MAP: XlateSurface.ro_rejected -> 0xE04 · 0xE08 · 0xE0C(isCtlRo) 의 쓰기는 badWrite 를 세우고 commit · flush · missClr 어느 것도 세우지 않는다 — 흡수 가지가 없다 (loud 로 잇는 것은 reject_loud 의 surfBadWr → FAULT_STATUS [6])
//
// ── GUARD-MAP 이어서 — 파도 4 판정 T5 (a) · T4 (ii) 의 착지 (2026-09-26, 정본 f229c8b) ──
//
// 모델 XlateSurface.tla 가 같은 커밋에서 가드 둘을 실었다 (선-formal run 이 이 편집보다
// 먼저다). 머리가 아니라 끝에 둔 것은 위와 같은 이유다.
//
// GUARD-MAP: XlateSurface.flush_drops_staging -> 수락된 XLATE_FLUSH(flush.valid — 예약 [31:8] = 0 · 실재 파티션)의 [1:0] 이 래치 번호의 파티션 필드 stgNum[5:4] 와 같으면 그 사이클 뒤 stgValid 가 내려간다(stgFlushDrop — 클래스 끝). stgNum · stgFrame 은 움직이지 않는다(유효 비트만). 뒤따르는 HI 는 hiLegal 의 stgValid 항에서 번호와 무관하게 거절 + badWrite 다(hi_needs_staging 과 같은 선). 다른 파티션의 flush · 거절된 flush(flush.valid = 0)는 스테이징에 닿지 않는다. 같은 사이클의 수락된 LO(loOk)가 이긴다 — 직렬화 flush → LO (상위의 두 구역 스트로브는 주소 디코드로 배타)
// GUARD-MAP: XlateSurface.ent_part_exists -> entPhantom(항목 번호의 파티션 필드 ≥ 형상 파티션 수 — 기본 형상 4 에서 elaborate 상수 False)이면 LO 는 loOk 가 서지 않아 스테이징 세 레지스터가 부동이고 badWrite 를 세우며, HI 는 거절 + badWrite 다(needReady · commit.valid 없음) — 스테이징이 형상 밖 번호를 래치할 수 없으므로 stgNum === num 이 서지 않고, hiLegal 의 !entPhantom 항은 그 위의 중복 방어다(역-변이 P03 — 그 항만 지운 판은 생존한다). commit.part := numPart.resized 의 절단이 실재 파티션 항목을 설치하는 별칭 경로가 서지 않는다. 파티션 2 판 XlateStagingP2.sv 를 XlateStaging/p2.sby 가 잰다
