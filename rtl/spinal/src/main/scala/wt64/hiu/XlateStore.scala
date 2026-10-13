// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// WT64v1 재구현 — 변환 저장 블록 + 채움 경로 (정본 §3.6 전부 · 부록 E.2 · E.3).
//
// 선-formal 계약: rtl/formal/tla/XlateStore.tla (HIU-1~3 축 · HIU-4 는 XlateSurface) +
// rtl/formal/tla/Isolation.tla 의 저장·채움 축 (SEC-4). 승인 축 5가드
// (approve_gates_value · no_early_forward · query_offpath · query_no_serve ·
// coh_no_shortcut)는 착지한 HiuPipeline.scala 의 CHECK 로 이관됐다.
//
// GUARD-MAP: XlateStore.valid_check        -> storeHit = lookup.valid ∧ storeValid ∧ 태그 일치 ∧ ¬fillShadow — storeValid(validBits(part)(idx)) 가 논리곱의 항이고, rsp.frame/rsp.perm 은 hit 인 가지에서만 구동된다 (miss 시 0). 채움 줄은 fillLine.v 가 논리곱의 항이다 (V=0 줄은 적중하지 않는다)
// GUARD-MAP: XlateStore.partition_check    -> entryAddr = lookup.part @@ reqIdx — 저장 주소 상위가 요청 파티션 그 자체라 남의 파티션 항목은 조회 주소 공간에 존재하지 않는다. validBits·fillSlot 도 part 로 색인된다
// GUARD-MAP: XlateStore.flush_keeps_data   -> flush 는 validBits(flush.part) := 0 (자기 파티션 채움 버퍼 취하는 방어 중복 — 대기 채움 ≤ 1 이 그 사이클 커밋으로 빠지고 flush 대입이 마지막이라 이미 성립, 아래 flush 블록) 만 수행 — store Mem 에는 flush 에서 비롯한 쓰기 포트 자체가 없다. 태그·데이터는 남는다 (§3.6.3)
// GUARD-MAP: Isolation.install_scoped      -> 커밋 주소 = commitSel @@ 그 슬롯의 idx — 버퍼 슬롯 번호가 곧 파티션이므로 기입이 자기 파티션 밖 항목 주소를 만들 수 없다 (구조 보장)
// GUARD-MAP: Isolation.capacity_partitioned -> 직접 사상 + validBits 는 파티션별 레지스터, Mem 주소 상위 = 파티션 — q 의 설치·커밋·flush 가 p 구간의 유효 비트·주소를 건드릴 경로가 구조적으로 없다 (축출이 경계를 못 넘는다)
// GUARD-MAP: Isolation.fill_tagged         -> fillHit 는 fillSlot(lookup.part) 하나만 후보로 삼는다 — 타 파티션 슬롯은 아예 조회되지 않고(파티션 검사의 구조화), idx·tag 일치와 줄의 v 가 논리곱의 항이다
// GUARD-MAP: Isolation.fill_slot_per_partition -> fillPend/fillSlot 이 파티션당 정확히 한 자리인 Vec 이고, install.ready 는 자기 파티션 슬롯의 점유만 본다 — 남의 채움이 내 자리를 차지하거나 덮어쓸 수 없다
// GUARD-MAP: Isolation.fill_offpath        -> STRUCTURAL(port-absence) — 조회 응답은 같은 사이클 조합 판정이며 채움 상태는 lookup 경로에 정지·ready 를 만들지 않는다 — 채움은 fillHit 라는 값 판정으로만 나타난다 (fwait 단계 없음)
//
// ## D12 — 읽기 우선순위 (§3.6.2 규범 2, 확정)
//
//   진행 중 채움의 바이패스 > 저장 블록 조회 > (선택적) 호스트 응답.
//   채움 후보 복수면 자기 파티션 우선.
//
// 이 블록은 앞의 둘을 판정하고, 호스트 응답은 **인터페이스 자리만** 둔다 —
// 그 leg 의 선택 경로는 HiuPipeline(착지)이 세운다. 자기 파티션 우선은
// 여기서 구조가 됐다: 채움 버퍼 자리가 파티션당 하나이고 기입이 자기
// 파티션에만 가므로, 요청 파티션의 슬롯 하나가 유일한 후보다.
//
// ## HIU-3 — 유효 게이팅 전수 (§3.12)
//
// 이 블록에서 값을 읽는 경로는 둘이다 — 채움 버퍼 바이패스(fillPend 로
// 게이트)와 저장 블록(validBits 로 게이트). 출력 자체도 hit 인 가지에서만
// 구동되므로 게이트되지 않은 값 유출 경로가 없다. 다만 「모든 읽기 경로」의
// **전수성**은 이 파일 하나가 증명할 수 없다 — 읽기 경로는 유한·열거
// 가능하므로 그 전수성은 정적 검사의 몫이다 — **그 검사는 아직 없다** (XlateStore.tla 머리말과
// 같다 — 이름만 적혀 온 scripts/lint_hiu3_valid_gating.py 는 저장소에 실재한 적이 없다 · 이월).

package wt64.hiu

import spinal.core._
import spinal.lib._
import wt64._

/** 지역 폭 정의와 VPN 분할 — 정본이 폭을 확정하지 않은 자리의 확정 지점 (Common.scala 수정 금지 —
  * promote 후보). VA_W = PA_W = 44 의 근거: 표면이 VPN 32b · FRAME 32b 이고 페이지가 4 KiB
  * 고정이라 44b 가 유도된다 (E.2 해설). 항목의 저장 폭은 형상이다 — 호스트 계약이 아니다.
  * 분할(칸 = VPN 하위 idxW 비트 · 태그 = 나머지 — 직접 사상 · 연관도 1, DP-1)은 이 한 정의다:
  * 조회(reqIdx · reqTag)와 커밋 결선(Wt64Top xlateArea — 문은 VPN 32b 를 낸다)이 같은 함수를
  * 부르므로 같은 VPN 은 같은 칸으로 가서 덮인다 (결과 (a)(b) 의 정합이 여기에 기댄다). */
object XlateStore {
  /** 칸 색인 = VPN 하위 idxW 비트. */
  def idxOf(vpn: UInt, idxW: Int): UInt = vpn(idxW - 1 downto 0)
  /** 저장 태그 = VPN 의 나머지 위 비트. */
  def tagOf(vpn: UInt, idxW: Int): UInt = vpn(vpn.getWidth - 1 downto idxW)
  /** 파티션당 저장 칸 수 — 직접 사상이라 색인 수 (0xFF8 HIU_SHAPE `[23:8]` 의 출처). */
  def capPerPart(cfg: Wt64Config): Int = cfg.xlateIdx
  // ── 폭 ──
  /** 가상 주소 폭 (비트). */
  val VA_W = 44
  /** 물리 주소 폭 (비트). */
  val PA_W = 44
  /** 페이지 오프셋 폭 — 4 KiB 고정 (부록 E.2: 가변 페이지는 SEC-2 를 깬다). */
  val PAGE_W = 12
  /** 가상 페이지 번호 폭. 페이지 오프셋은 변환에 관여하지 않으므로 이
    * 블록의 조회 입력은 VPN 이다 — 오프셋 비트를 받았다가 쓰지 않는 항구를
    * 만들지 않는다. */
  val VPN_W = VA_W - PAGE_W
  /** 물리 프레임 번호 폭. */
  val FRAME_W = PA_W - PAGE_W
}

/** 권한 — 읽기 · 쓰기 · 실행 (부록 E.2). */
case class XlatePerm() extends Bundle {
  val r = Bool()
  val w = Bool()
  val x = Bool()
}

/** 저장 블록 항목 본체 — 유효 비트를 **제외한** 전부.
  *
  * 유효 비트가 여기 없는 것이 구조다: 본체는 reset 없는 Mem 에 살고
  * (§3.6.1 결과 2 — 메모리 자원 추론), 유효 비트는 flush 가능해야 하므로
  * 파티션별 레지스터에 산다. flush 가 데이터를 못 지우는 것(§3.6.3)이
  * 규율 준수가 아니라 **불능**이 되게 하는 배치다. */
case class XlateEntryBody(tagW: Int, frameW: Int) extends Bundle {
  val tag   = UInt(tagW bits)
  val frame = UInt(frameW bits)
  val perm  = XlatePerm()
}

/** 채움 버퍼 한 줄 — 커밋 전의 가장 새 항목 (§3.6.2 해설: 신선도). */
case class XlateFillLine(idxW: Int, tagW: Int, frameW: Int) extends Bundle {
  val idx   = UInt(idxW bits)
  val tag   = UInt(tagW bits)
  val frame = UInt(frameW bits)
  val perm  = XlatePerm()
  val v     = Bool() // XLATE_ENTRY_COMMIT [31] — 커밋이 유효 비트에 그대로 싣는다 (0 = 단일 항목 무효화)
}

/** 변환 저장 블록 + 채움 경로.
  *
  * 파티션 4 × 색인 16 직접 사상 (형상은 Wt64Config — 인코딩에 새지 않는다).
  * 항목 주소는 {파티션, 색인} **연접** — 곱셈을 구조적으로 만들지 않는다
  * (§3.6.1 「재구현에 대한 요건」 결과 1). 적중은 파티션·태그·유효의
  * 논리곱 (§3.6.2 규범 1). flush 는 유효 비트만 지운다 (§3.6.3).
  *
  * 채움 주체는 호스트다 (부록 E.3) — install 포트가 파티션 표시를 동반한
  * 호스트 기입이고, 파티션당 한 자리의 채움 버퍼를 거쳐 다음 사이클에
  * 저장 블록으로 커밋된다. 버퍼 점유 중의 조회는 바이패스로 그 줄을
  * 적중시킨다 — 커밋 순간에 같은 접근이 다른 값을 돌려주는 관측을 없애는
  * 신선도 순서다 (§3.6.2 해설).
  *
  * 미적중은 오류가 아니다 (§3.6.2 규범 3) — 이 블록은 fault 원천이 없고
  * sticky 비트도 없다. 미적중 배압·sticky 통지(부록 E.3)는 요청 상태
  * 기계를 소유한 HiuPipeline(착지)의 몫이다. */
class XlateStore(val cfg: Wt64Config = Wt64Config()) extends Component {
  import XlateStore._

  // 연접 주소가 정확히 전 항목을 덮으려면 두 축 모두 2의 거듭제곱이어야
  // 한다 — 아니면 연접이 구멍을 만들고, 그 구멍이 사실상 곱셈 주소화로
  // 되돌아가는 압력이 된다 (§3.6.1 결과 1).
  require(isPow2(cfg.xlateParts) && isPow2(cfg.xlateIdx),
    "xlateParts·xlateIdx 는 2의 거듭제곱 — {파티션, 색인} 연접 주소의 전제 (§3.6.1)")

  private val partW = log2Up(cfg.xlateParts)
  private val idxW  = log2Up(cfg.xlateIdx)
  private val tagW  = VPN_W - idxW

  // 옛 require 「유효 1 + 권한 3 + 태그 + 프레임 ≤ 64b」(앞판 E.2 의 항목 폭 8 B)는 지웠다 —
  // 항목의 저장 폭은 이제 형상이다(E.2). 그 require 가 색인 < 16 형상(태그 > 28b)을 막고 있었다.
  // 저장 줄 폭은 tagW + FRAME_W + 3 이고 상한은 합성 자원(Mem 폭)의 일이다 — 계약이 아니다.
  // (3.10 v1.0 묶음 W3)

  val io = new Bundle {
    /** 조회 — 같은 사이클 조합 응답. */
    val lookup = new Bundle {
      val valid = in port Bool()
      val part  = in port UInt(partW bits)
      val vpn   = in port UInt(VPN_W bits)
    }
    /** 조회 응답. hit 는 채움 바이패스 ∨ 저장 블록 (D12 앞 두 순위). */
    val rsp = new Bundle {
      val hit      = out port Bool()
      val fromFill = out port Bool()
      val frame    = out port UInt(FRAME_W bits)
      val perm     = out port XlatePerm()
      /** 호스트 응답 leg — D12 최하 순위의 **인터페이스 자리**. 이 블록은
        * 값을 판정에 쓰지 않고 실어 나르기만 한다. 선택 경로(그리고
        * query_no_serve 검사)는 HiuPipeline(착지) 소관이다. */
      val hostPresent = out port Bool()
      val hostFrame   = out port UInt(FRAME_W bits)
      val hostPerm    = out port XlatePerm()
    }
    /** 호스트 응답 입력 — 위 인터페이스 자리의 원천. */
    val hostRsp = new Bundle {
      val valid = in port Bool()
      val frame = in port UInt(FRAME_W bits)
      val perm  = in port XlatePerm()
    }
    /** 호스트 기입 (부록 E.3: 채움 주체는 호스트) — 파티션 표시 동반.
      * ready 는 자기 파티션 채움 슬롯의 점유(와 같은 파티션 flush 충돌)만
      * 본다 — 슬롯이 파티션당 하나라는 사실의 인터페이스 형태다. */
    val install = new Bundle {
      val valid = in port Bool()
      val ready = out port Bool()
      val part  = in port UInt(partW bits)
      val idx   = in port UInt(idxW bits)
      val tag   = in port UInt(tagW bits)
      val frame = in port UInt(FRAME_W bits)
      val perm  = in port XlatePerm()
      val v     = in port Bool() // 유효 — XLATE_ENTRY_COMMIT `[31]` 그대로. 0 이면 그 항목을 무효로 커밋한다
    }
    /** 파티션 단위 flush — 유효 비트만 (§3.6.3). */
    val flush = new Bundle {
      val valid = in port Bool()
      val part  = in port UInt(partW bits)
    }
  }

  // ── 저장 자원 ────────────────────────────────────────────────────
  // 항목 본체 — reset 없는 Mem. 초기화하지 않는 것이 규율이다: §3.6.3 은
  // 전원 투입 쓰레기와 이전 테넌트 잔여물을 같은 자리에 두고, 유효 비트만을
  // 방벽으로 삼는다. reset 을 두면 합성기가 RAM 추론을 거부하고 레지스터로
  // 편다 (§3.6.1 해설 실측 — LUT 2배 · FF 3배).
  val store = Mem(XlateEntryBody(tagW, FRAME_W), cfg.xlateParts * cfg.xlateIdx)

  // 유효 비트 — 파티션별 레지스터. 파티션별로 쪼개 둔 것이 곧 capacity_partitioned
  // 의 구조 보장이다: 어떤 동작도 남의 파티션 레지스터에 닿는 배선이 없다.
  val validBits = Vec.fill(cfg.xlateParts)(RegInit(B(0, cfg.xlateIdx bits)))

  // 채움 버퍼 — 파티션당 정확히 한 자리 (fill_slot_per_partition). 줄 안에 파티션 필드가
  // 없다 — 슬롯 번호가 파티션이다 (install_scoped: 자기 파티션 밖 줄을 표현할 수단이 없다).
  val fillPend = Vec.fill(cfg.xlateParts)(RegInit(False))
  val fillSlot = Vec.fill(cfg.xlateParts)(Reg(XlateFillLine(idxW, tagW, FRAME_W)))
  val installFire = io.install.valid && io.install.ready // install.fire — 이름 있는 신호(DP-22 · 하네스가 이 이름으로 잡는다)
  // ── 채움 경로 ① — 호스트 기입이 버퍼 자리를 점유한다 ─────────────
  private val flushSamePart = io.flush.valid && io.flush.part === io.install.part
  io.install.ready := !fillPend(io.install.part) && !flushSamePart
  when(installFire) {
    fillPend(io.install.part)       := True
    fillSlot(io.install.part).idx   := io.install.idx
    fillSlot(io.install.part).tag   := io.install.tag
    fillSlot(io.install.part).frame := io.install.frame
    fillSlot(io.install.part).perm  := io.install.perm
    fillSlot(io.install.part).v     := io.install.v
  }

  // ── 채움 경로 ② — 버퍼의 줄이 저장 블록으로 커밋된다 ─────────────
  // Mem 쓰기 포트는 하나다 — 점유된 슬롯 중 하나를 골라 사이클당 하나씩
  // 커밋한다 (고정 우선순위. 기입 원천이 호스트 구성 표면 하나라 유입도
  // 사이클당 최대 하나이고, 밀림은 유한하다). 점유와 커밋 사이의 창이
  // 바이패스가 판정을 정하는 창이다.
  private val commitPend = fillPend.asBits
  private val commitFire = commitPend.orR
  private val commitSel = PriorityMux(
    commitPend,
    (0 until cfg.xlateParts).map(k => U(k, partW bits)),
  )
  private val commitLine = fillSlot(commitSel)
  private val commitBody = XlateEntryBody(tagW, FRAME_W)
  commitBody.tag   := commitLine.tag
  commitBody.frame := commitLine.frame
  commitBody.perm  := commitLine.perm
  store.write(
    address = commitSel @@ commitLine.idx, // 연접 — 곱셈 없음 (§3.6.1 결과 1)
    data    = commitBody,
    enable  = commitFire,
  )
  when(commitFire) {
    validBits(commitSel)(commitLine.idx) := commitLine.v // COMMIT [31] 그대로 — 0 이면 단일 항목 무효화
    fillPend(commitSel)                  := False
  }

  // ── flush — 유효 비트만 (§3.6.3 「유효 비트가 유일한 방벽」) ──────
  // store Mem 은 건드리지 않는다 — 건드릴 쓰기 포트가 이 경로에 없다.
  // 자기 파티션의 진행 중 채움 취하(fillPend := False)는 방어 중복이다 — 관측 효과가 없다: 대기 채움은
  // 한 번에 ≤ 1 이라 그 사이클 commitFire 가 어차피 비우고, 아래 validBits 대입이 마지막이라 이긴다(이 항을 뺀 판과 포트 동치 — W3 검증 abc pdr miter).
  // 이 결정은 모델(XlateStore.tla 에 채움이, Isolation.tla 에 flush 가 없다)에 없다 — model_feedback.
  // 이 블록이 텍스트상 마지막인 것은 의도다 — 같은 사이클의 커밋이 같은
  // 파티션의 유효 비트를 세워도 flush 의 전체 덮어쓰기가 이긴다.
  when(io.flush.valid) {
    validBits(io.flush.part) := B(0, cfg.xlateIdx bits)
    fillPend(io.flush.part)  := False
  }

  // ── 조회 — 같은 사이클 조합 판정 ─────────────────────────────────
  private val reqIdx = idxOf(io.lookup.vpn, idxW) // 커밋 결선과 한 정의 (companion)
  private val reqTag = tagOf(io.lookup.vpn, idxW)

  // 항목 주소 = {파티션, 색인} 연접. 파티션이 주소의 상위이므로 남의
  // 파티션 항목은 이 요청의 주소 공간에 존재하지 않는다 (partition_check).
  private val entryAddr = io.lookup.part @@ reqIdx
  private val storeBody = store.readAsync(entryAddr)

  // 바이패스 후보는 자기 파티션 슬롯 하나 — 타 파티션 슬롯은 조회되지
  // 않는다 (fill_tagged 의 파티션 검사 + D12 「자기 파티션 우선」이 구조로
  // 동시에 성립하는 지점).
  private val fillLine = fillSlot(io.lookup.part)

  // 채움 가림 — 대기 중인 줄은 *그 항목의 가장 새 판*이다 (3.6.2 해설: 신선도).
  // 같은 {파티션, 색인} 의 저장 판은 대기 동안 보이지 않는다. 이것이 없으면
  // XLATE_ENTRY_COMMIT 이 커밋한 항목이 한 사이클 동안 옛 판으로 보인다 — V=0
  // 무효화(e-defined.typ:308 「`[31]` V — 유효」)가 옛 유효 항목을 한 사이클 더
  // 적중시키고, 태그를 바꾸는 설치가 옛 태그를 한 사이클 더 적중시킨다.
  // 호스트 쪽 문(Wt64Top xlateArea)이 보는 표는 「COMMIT 에지에 항목 전체가 바뀐다」이다 —
  //   e-defined.typ:308 「유효 비트를 담은 워드가 마지막이므로 부분 기입 상태가 유효해질 수 없다」
  // 채움 슬롯은 그 에지를 저장 블록 쪽으로 한 사이클 미루는 구현 세부다 — 가림이 그
  // 세부를 관측면에서 지운다.
  private val fillShadow = fillPend(io.lookup.part) && fillLine.idx === reqIdx

  // 적중 = 파티션(주소 구조) ∧ 태그 일치 ∧ 유효 (§3.6.2 규범 1) — 가림 밖에서만.
  private val storeValid = validBits(io.lookup.part)(reqIdx)
  private val storeHit =
    io.lookup.valid && storeValid && storeBody.tag === reqTag && !fillShadow

  // 채움 적중도 유효를 요구한다 — 줄의 v 가 논리곱의 항이다 (V=0 줄은 가리기만 한다).
  private val fillHit = io.lookup.valid && fillShadow &&
    fillLine.tag === reqTag && fillLine.v

  // D12: 채움 바이패스 > 저장 블록. 커밋 사이클에도 fillPend 가 아직 서
  // 있고 유효 비트는 다음 에지에 서므로, 바이패스→저장 이관에 관측 공백이
  // 없다 (§3.6.2 해설: 신선도).
  io.rsp.hit      := fillHit || storeHit
  io.rsp.fromFill := fillHit

  // 값 출력은 hit 인 가지에서만 구동 — miss 에서 본체 값이 새지 않는다
  // (HIU-3 유효 게이팅의 이 블록 몫. 전수성은 정적 검사 — 파일 머리 주석).
  io.rsp.frame  := 0
  io.rsp.perm.r := False
  io.rsp.perm.w := False
  io.rsp.perm.x := False
  when(fillHit) {
    io.rsp.frame := fillLine.frame
    io.rsp.perm  := fillLine.perm
  } elsewhen (storeHit) {
    io.rsp.frame := storeBody.frame
    io.rsp.perm  := storeBody.perm
  }

  // 호스트 응답 leg — 실어 나르기만. 판정(hit)에 쓰지 않는다 (D12 최하
  // 순위의 자리 예약. 선택 경로는 2차 파도).
  io.rsp.hostPresent := io.hostRsp.valid
  io.rsp.hostFrame   := io.hostRsp.frame
  io.rsp.hostPerm    := io.hostRsp.perm

  // ── 슬롯 여유 — flush 와 무관한 설치 수락 가능성 (파도 4, 2026-09-26 SLOTFREE) ──
  // install.ready = 슬롯 여유 ∧ ¬(같은 사이클 · 같은 파티션 flush) 이다. 뒤 항의
  // flush.valid 는 호스트 쪽에서 0xE00 기입의 wdata 판정(XlateStaging 의 예약 ·
  // 없는 파티션)이라, install.ready 를 MMIO ready 로 쓰면 wdata → ready 조합 경로가
  // 넷리스트에 생긴다 (기능적으로는 죽은 경로 — 문의 항목 기입과 flush 발화는 주소
  // 디코드로 배타). 조립(Wt64Top xlateArea)이 ready · 문의 installReady 로 쓰는 것은
  // 이 신호다 — 파티션 슬롯 점유만의 함수. 배타가 깨지면 문은 커밋을 내고 이 블록은
  // flush 우선으로 그 설치를 버린다(조용한 드롭) — 조립 하네스 a_xonehot 이 배타를
  // 기계로 잡는다. install.ready 자체는 이 블록의 단독 계약으로 남는다
  // (XlateStore_props.sv a_ready_split 이 둘의 관계를 핀한다).
  // 클래스 *끝*인 이유: io 번들 안이면 아래 줄이 밀린다(옛 when_XlateStore_l200 — W3 부터 이름 있는
  // installFire 라 줄 이름이 없다, DP-22). 포트 이름은 io_ 접두 없이 installSlotFree.
  val installSlotFree = out port Bool()
  installSlotFree := !fillPend(io.install.part)
}

// ── GUARD-MAP — 호스트 쪽 문(XlateSurface.tla)의 저장 쪽 가드 넷 (3.10 v1.0 묶음 W3) ──────
// 문의 스물넷은 top/XlateStaging.scala 가, commit_replaces_vpn 은 Wt64Top xlateArea 아래가 든다.
// 이 넷이 여기 있는 이유: V 를 유효 비트로 옮기는 식 · 희생 칸의 파티션 · 저장 쓰기 원천 ·
// 채움 슬롯의 비움 발화가 이 파일에 산다. 파일 *끝*에 둔 것은 위쪽 줄 좌표(xlatestore.sby 가
// 축자 인용하는 줄들)를 밀지 않기 위해서다. 칸 선택은 직접 사상(칸 = idxOf(VPN))이라 같은 (파티션,
// VPN) 은 늘 같은 칸이고 연관도 1 · 교체 상태 없음(DP-2)이다.
// GUARD-MAP: XlateSurface.commit_v_carried -> install.v(= XLATE_ENTRY_COMMIT [31], XlateStaging 이 wdata(31) 을 그대로 싣는다)가 채움 줄의 v 로 들어가고 커밋이 validBits(commitSel)(idx) := commitLine.v 로 그 값을 그대로 쓴다 — 커밋이 유효를 상수 True 로 세우는 경로가 없다. 대기 중에는 fillHit 가 fillLine.v 를 논리곱의 항으로 요구하고 fillShadow 가 같은 칸의 옛 저장 판을 가리므로 V=0 커밋은 COMMIT 수락 다음 에지부터 그 (파티션, VPN) 에 적중하지 않는다
// GUARD-MAP: XlateSurface.evict_in_partition -> 커밋 주소 = commitSel @@ commitLine.idx 이고 commitSel 은 PriorityMux(fillPend) 가 고른 채움 슬롯 번호 = 그 줄을 받은 install.part 다 — 희생 칸(덮이는 칸)은 늘 COMMIT 의 파티션 구간 안이고 validBits(commitSel) 만 쓴다 (Isolation.install_scoped 사상과 같은 항 — 두 가드가 같은 구조를 가리킨다)
// GUARD-MAP: XlateSurface.evict_on_commit_only -> validBits 의 대입 원천은 when(commitFire) 의 validBits(commitSel)(idx) := commitLine.v 와 when(io.flush.valid) 의 validBits(flush.part) := 0 둘뿐이고 store 의 쓰기 포트는 store.write(enable = commitFire) 하나다 — 시간 · 조회 · 배경 경로가 없다(조회는 store.readAsync 와 validBits 읽기뿐). 다른 파티션의 활동은 남의 validBits 를 쓰지 않는다
// GUARD-MAP: XlateSurface.stall_independent -> commitFire = fillPend.orR 이고 commitSel = PriorityMux(fillPend) 다 — 채움 슬롯의 저장 커밋은 점유가 있으면 매 사이클 발화하고 그 콘에 hold · 미적중 정지 · 버스(io.install · ready) 입력이 없다(이 블록은 그 입력을 갖지 않는다). 정지된 COMMIT 은 버스를 잡고 있어 새 설치가 오지 않으므로 xlateParts 사이클 안에 그 슬롯이 빈다 — 측정은 xlatestore.sby s_pend_bounded · w_pend_drains 와 XlateDoor/door.sby (ready 쪽은 assembly a_ready_only_slot)
