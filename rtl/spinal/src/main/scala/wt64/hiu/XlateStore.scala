// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// WT64v1 재구현 — 변환 저장 블록 + 채움 경로 (정본 §3.6 전부 · 부록 E.2 · E.3).
//
// 선-formal 계약: rtl/formal/tla/XlateStore.tla (HIU-1~4 축) +
// rtl/formal/tla/Isolation.tla 의 저장·채움 축 (SEC-4). 승인 축 5가드
// (approve_gates_value · no_early_forward · query_offpath · query_no_serve ·
// coh_no_shortcut)는 착지한 HiuPipeline.scala 의 CHECK 로 이관됐다.
//
// GUARD-MAP: XlateStore.valid_check        -> storeHit = lookup.valid ∧ storeValid ∧ 태그 일치 — storeValid(validBits(part)(idx)) 가 논리곱의 항이고, rsp.frame/rsp.perm 은 hit 인 가지에서만 구동된다 (miss 시 0)
// GUARD-MAP: XlateStore.partition_check    -> entryAddr = lookup.part @@ reqIdx — 저장 주소 상위가 요청 파티션 그 자체라 남의 파티션 항목은 조회 주소 공간에 존재하지 않는다. validBits·fillSlot 도 part 로 색인된다
// GUARD-MAP: XlateStore.flush_keeps_data   -> flush 는 validBits(flush.part) := 0 (와 자기 파티션 채움 버퍼 취하) 만 수행 — store Mem 에는 flush 에서 비롯한 쓰기 포트 자체가 없다. 태그·데이터는 남는다 (§3.6.3)
// GUARD-MAP: Isolation.install_scoped      -> 커밋 주소 = commitSel @@ 그 슬롯의 idx — 버퍼 슬롯 번호가 곧 파티션이므로 기입이 자기 파티션 밖 항목 주소를 만들 수 없다 (구조 보장)
// GUARD-MAP: Isolation.capacity_partitioned -> 직접 사상 + validBits 는 파티션별 레지스터, Mem 주소 상위 = 파티션 — q 의 설치·커밋·flush 가 p 구간의 유효 비트·주소를 건드릴 경로가 구조적으로 없다 (축출이 경계를 못 넘는다)
// GUARD-MAP: Isolation.fill_tagged         -> fillHit 는 fillSlot(lookup.part) 하나만 후보로 삼는다 — 타 파티션 슬롯은 아예 조회되지 않고(파티션 검사의 구조화), idx·tag 일치가 논리곱의 항이다
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
// 가능하므로 그 전수성은 정적 검사의 몫이다 (XlateStore.tla 머리말이 지목한
// scripts/lint_hiu3_valid_gating.py 축). 이 주석이 그 검사의 앵커다.

package wt64.hiu

import spinal.core._
import spinal.lib._
import wt64._

/** 지역 폭 정의 — 정본이 폭을 확정하지 않은 자리의 확정 지점.
  *
  * 부록 E.2 가 못박은 것: 항목 폭 8 B, 페이지 4 KiB 고정, 필드는
  * {유효 1b, 태그(가상 주소 상위), 물리 프레임, 권한 r·w·x}.
  * 가상·물리 주소의 전체 폭은 정본 어디에도 없다 — 그래서 여기서 정하고
  * 보고서 model_feedback 으로 되돌린다 (§6.3 「모델에 없는 결정은 모델로」):
  *
  *   VA_W = PA_W = 44. 근거: 기본 형상(파티션 4 × 색인 16)에서 항목이
  *   정확히 8 B 를 채운다 — 유효 1 + 권한 3 + 태그 28 + 프레임 32 = 64b.
  *   예약 비트를 만들지 않는 선택이다 (「예약」은 §3.7/§5.6 이 경고한
  *   양의성 있는 낱말이라, 없는 편이 가장 싸다).
  *
  * Common.scala 는 수정 금지라 지역 정의다 — promote 후보. */
object XlateStore {
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

  // 부록 E.2: 항목 폭 8 B. 유효 1b 는 레지스터에 살지만 항목 폭 계산에는
  // 포함된다 — 폭이 넘치면 E.2 위반이므로 elaborate 에서 죽는다.
  require(1 + 3 + tagW + FRAME_W <= 64,
    "변환 항목이 8 B 를 넘는다 — 부록 E.2 (유효 1 + 권한 3 + 태그 + 프레임)")

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

  // 유효 비트 — 파티션별 레지스터. 파티션별로 쪼개 둔 것이 곧
  // capacity_partitioned 의 구조 보장이다: 어떤 동작도 남의 파티션
  // 레지스터에 닿는 배선이 없다.
  val validBits = Vec.fill(cfg.xlateParts)(RegInit(B(0, cfg.xlateIdx bits)))

  // 채움 버퍼 — 파티션당 정확히 한 자리 (fill_slot_per_partition).
  // 줄 안에 파티션 필드가 없다 — 슬롯 번호가 파티션이다 (install_scoped 의
  // 구조 보장: 기입이 자기 파티션 밖 줄을 표현할 수단 자체가 없다).
  val fillPend = Vec.fill(cfg.xlateParts)(RegInit(False))
  val fillSlot = Vec.fill(cfg.xlateParts)(Reg(XlateFillLine(idxW, tagW, FRAME_W)))

  // ── 채움 경로 ① — 호스트 기입이 버퍼 자리를 점유한다 ─────────────
  private val flushSamePart = io.flush.valid && io.flush.part === io.install.part
  io.install.ready := !fillPend(io.install.part) && !flushSamePart
  when(io.install.valid && io.install.ready) {
    fillPend(io.install.part)       := True
    fillSlot(io.install.part).idx   := io.install.idx
    fillSlot(io.install.part).tag   := io.install.tag
    fillSlot(io.install.part).frame := io.install.frame
    fillSlot(io.install.part).perm  := io.install.perm
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
    validBits(commitSel)(commitLine.idx) := True
    fillPend(commitSel)                  := False
  }

  // ── flush — 유효 비트만 (§3.6.3 「유효 비트가 유일한 방벽」) ──────
  // store Mem 은 건드리지 않는다 — 건드릴 쓰기 포트가 이 경로에 없다.
  // 자기 파티션의 진행 중 채움도 함께 취한다: 남겨 두면 flush 뒤에 이전
  // 컨텍스트의 줄이 커밋돼 HIU-2 (flush 후 미적중)가 창 하나만큼 깨진다.
  // 이 결정은 모델(XlateStore.tla 에는 채움이, Isolation.tla 에는 flush 가
  // 없다)에 없으므로 model_feedback 으로 되돌린다.
  // 이 블록이 텍스트상 마지막인 것은 의도다 — 같은 사이클의 커밋이 같은
  // 파티션의 유효 비트를 세워도 flush 의 전체 덮어쓰기가 이긴다.
  when(io.flush.valid) {
    validBits(io.flush.part) := B(0, cfg.xlateIdx bits)
    fillPend(io.flush.part)  := False
  }

  // ── 조회 — 같은 사이클 조합 판정 ─────────────────────────────────
  private val reqIdx = io.lookup.vpn(idxW - 1 downto 0)
  private val reqTag = io.lookup.vpn(VPN_W - 1 downto idxW)

  // 항목 주소 = {파티션, 색인} 연접. 파티션이 주소의 상위이므로 남의
  // 파티션 항목은 이 요청의 주소 공간에 존재하지 않는다 (partition_check).
  private val entryAddr = io.lookup.part @@ reqIdx
  private val storeBody = store.readAsync(entryAddr)

  // 적중 = 파티션(주소 구조) ∧ 태그 일치 ∧ 유효 (§3.6.2 규범 1).
  private val storeValid = validBits(io.lookup.part)(reqIdx)
  private val storeHit =
    io.lookup.valid && storeValid && storeBody.tag === reqTag

  // 바이패스 후보는 자기 파티션 슬롯 하나 — 타 파티션 슬롯은 조회되지
  // 않는다 (fill_tagged 의 파티션 검사 + D12 「자기 파티션 우선」이 구조로
  // 동시에 성립하는 지점).
  private val fillLine = fillSlot(io.lookup.part)
  private val fillHit = io.lookup.valid && fillPend(io.lookup.part) &&
    fillLine.idx === reqIdx && fillLine.tag === reqTag

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
}
