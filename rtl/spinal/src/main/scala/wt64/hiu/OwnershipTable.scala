// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// OwnershipTable — 페이지 소유권 표 (정본 부록 E.7 · §3.4.1 · §3.7)
//
// 구성 표면 `0x200`~`0x2FF` (256 B) 의 색인 + 데이터 쌍. 페이지 → {호스트
// 소유 | 장치 소유} 의 상태 기계 그 자체다. §3.4.1 규약 4요소 중 이 모듈이
// 드는 것은 앞의 둘 — 단위(페이지)·두 상태, 그리고 전이 경로(명시적 MMIO
// 기입만)다. 위반 판정(4요소의 넷째)은 HiuPipeline 승인 단계 소관이고,
// 비우기 의무(셋째)는 넘기는 쪽 — 호스트 소프트웨어 — 의 ABI 의무다.
//
// ## 레지스터 배치 (E.7 — 색인 + 데이터 쌍)
//
//   0x200  OWN_IDX   RW  조회 색인 — 상태를 *읽을* 페이지 프레임. 읽기는
//                        기입값 반환. **조회 대상만 정한다** — 전이에 불참.
//   0x204  OWN_DATA  RW  읽기: OWN_IDX 페이지의 상태 ([0] 1 = 장치 소유,
//                        나머지 0). 쓰기: 전이 — 아래 워드 배치.
//   그 밖  예약 오프셋 — 쓰기 무시 · 읽기 0 (§3.7. *오프셋* 정책이다 —
//          명령 인코딩의 예약 *필드*와 정반대. 디코더로 옮겨 적지 말 것).
//
// ## 전이 워드 (E.7 원자성 — 한 번의 쓰기로 완결)
//
//   OWN_DATA 쓰기: [31] 목표 상태 (1 = 장치로 이양 · 0 = 호스트로 회수)
//                  [30:0] 대상 페이지 프레임
//
// 전이 명령과 대상 페이지가 한 워드에 함께 실리므로 색인–데이터 사이의
// 중간 상태가 관측 가능해질 표면이 없다 (E.7 — "계약을 늘리는 대신
// 인코딩을 좁힌 것"). 커밋은 클럭 에지 하나에서 유효 비트·태그가 함께
// 갱신되는 단일 기입이다 — 부분 상태가 구조적으로 없다 (§3.7.1 HIU-7 동형).
//
//   ⚠️ 워드 32b − 명령 1b = 프레임 31b. XlateStore 의 지역 결정 PA_W = 44
//   (프레임 32b — 그 자체가 promote 후보인 잠정값) 와 정확히 1비트
//   충돌한다. E.7 「한 워드」가 규범이므로 여기가 좁다: 프레임 ≥ 2^31 인
//   페이지는 전이 워드에 실을 수 없어 **구조적으로 항상 호스트 소유**다.
//   조용한 실패는 아니다 — 그런 페이지에 장치가 접근하면 비소유 접근이라
//   HiuPipeline 이 loud fault 를 낸다 (§3.4.1 4항). 최종 수습(PA_W = 43
//   로 좁히거나 E.7 워드를 넓히는 합의)은 보고서 model_feedback 으로 되돌린다.
//
// ## 저장 구조 — 직접 사상 (E.2 연접 선례)
//
// 페이지 수가 크고 가변이라 직접 배열이 불가능한 유일한 표다 (E.7). 여기는
// 「장치 소유 페이지」 집합만 실물로 들면 된다 — reset 기본이 전 페이지
// 호스트 소유이므로 (Platform.tla Init 동형) 표에 없는 페이지 = 호스트
// 소유가 전칭으로 성립한다. 집합의 실물은 직접 사상 표다:
//
//   색인 = 프레임 하위 idxW 비트 · 태그 = 프레임 상위 (E.2 「{파티션, 색인}
//   연접」과 같은 형태 — 곱셈도 선형 비교 루프도 만들지 않는다. 조회는
//   유효 비트 1개 + 태그 비교 1개다.)
//
// 직접 사상의 대가는 충돌이다 — 같은 색인의 두 페이지를 동시에 장치
// 소유로 둘 수 없다. 충돌하는 이양 기입은 **쓰기 무효 + loud sticky
// fault** 다 (faultCollide). 조용히 기존 항목을 축출하면 그 페이지가
// *암묵 전이* (장치→호스트) 를 겪는다 — E.7 이 금지한 바로 그 형태라
// 축출 배선 자체를 두지 않았다. 용량 축은 정본에 없는 구현 결정이다 —
// model_feedback 참조. 슬롯 수(ownEntries)는 생성자 파라미터로 두고
// Wt64Config 승격 diff 를 보고서 promote 에 적는다 (Common.scala 불가침).
//
// ## 무연산 항등 — Platform.tla Handoff 와 동형
//
// 이미 목표 상태인 페이지로의 전이는 무연산이다 (거절이 아니라 이미 원하는
// 상태다). Handoff 가 owner[pg] ≠ frm 이면 상태를 건드리지 않는 것과 같은
// 자리다 — 모델이 무연산으로 둔 것을 RTL 이 fault 로 올리면 두 세계의
// fault 정책이 어긋난다 (Inv_SameFaultPolicy 의 정신).
//
// ## Platform.tla 대응 — 정식 GUARD-MAP 줄의 거처에 관한 주의
//
// Platform 모델의 가드 넷은 전부 HiuPipeline.scala 머리에 정식 줄이 있다
// (lint_guard_map 은 가드당 저장소 전체 정확히 한 줄 — 여기 재기재 금지).
// 이 모듈은 그 판정들의 **데이터 원천**이다:
//
//   · Platform.owner_check — HiuPipeline 의 granted 논리곱이 소비하는
//     io.owner.devOwned 가 이 모듈의 io.query.devOwned 다. 판정은 저쪽,
//     상태는 여기.
//   · Platform.state_machine_kept — 「일관성이 있어도 그대로 유지」되는
//     소유권 상태 기계의 실물이 이 표다. 일관성 가용 신호는 이 모듈에
//     배선 자체가 없다 — 상태 기계를 생략하는 elaborate 경로가 없다.
//   · Platform.flush_on_handoff — ENV (호스트 의무). 이양 커밋 지점
//     (OWN_DATA 기입 수락)이 여기지만, 그 전에 비우는 것은 넘기는 쪽의
//     ABI 의무다 (§3.4.1 3항 · §3.10).
//
// ## reset 초기 상태
//
// reset 직후 모든 페이지는 호스트 소유다 (Platform.tla Init:
// owner = host 전칭). 유효 비트가 레지스터라 reset 으로 스스로 비워진다 —
// MmioConfig 같은 초기화 소거가 필요 없고, ready 는 항상 높다.

package wt64.hiu

import spinal.core._
import wt64.{StickyFault, Wt64Config}

/** 소유권 표 구역의 지역 상수 (부록 E.7 의 확정 지점). */
object OwnershipTable {
  /** E.7 창 — addr[11:8] 비교값 (`0x200`~`0x2FF`). */
  val REGION      = 0x2
  /** 조회 색인 레지스터 오프셋 (4 KiB 블록 안). */
  val OFF_IDX     = 0x200
  /** 상태/전이 데이터 레지스터 오프셋. */
  val OFF_DATA    = 0x204
  /** 전이 워드의 목표 상태 비트 — 1 = 장치로 이양 · 0 = 호스트로 회수. */
  val DIR_BIT     = 31
  /** 전이 워드가 나르는 프레임 폭 — 32b 워드 − 명령 1b (머리말 ⚠️ 참조). */
  val MMIO_FRAME_W = 31
  /** OWN_DATA 읽기의 상태 비트 — 1 = 장치 소유. */
  val STATE_DEV_BIT = 0
}

/** 페이지 소유권 표 — E.7 색인+데이터 쌍과 승인 조회의 반대편.
  *
  * 버스 프로토콜은 상위 몫이다 (MmioConfig 와 같은 소박한 동기 인터페이스).
  * HiuPipeline.io.owner 와는 top 조립이 frame/devOwned 를 직결한다.
  *
  * @param cfg        형상 (여기서는 검증 목적 외 미사용 — 표 크기는 아래)
  * @param ownEntries 직접 사상 슬롯 수 = 동시 장치 소유 가능 페이지 상한.
  *                   2의 거듭제곱. Wt64Config 승격 후보 (보고서 promote).
  */
case class OwnershipTable(cfg: Wt64Config = Wt64Config(), ownEntries: Int = 64) extends Component {
  import OwnershipTable._

  private val frameW = XlateStore.FRAME_W
  private val idxW   = log2Up(ownEntries)
  private val tagW   = MMIO_FRAME_W - idxW

  require(ownEntries >= 2 && isPow2(ownEntries), "소유권 표 슬롯 수는 2 이상 2의 거듭제곱")
  require(tagW >= 1, "색인이 전이 워드 프레임 폭을 다 먹으면 태그가 없다 — 슬롯 수 과대")
  require(frameW >= MMIO_FRAME_W, "프레임이 전이 워드보다 좁아지면 상위 0 판정 슬라이스가 공허해진다 — 배치 재검토")

  val io = new Bundle {
    // ── MMIO (소박한 동기 포트 — 버스 프로토콜은 상위 몫) ────────────
    val addr    = in  port UInt(12 bits) // 4 KiB 구성 블록 안 바이트 오프셋
    val wstrobe = in  port Bool()
    val wdata   = in  port Bits(32 bits)
    val rstrobe = in  port Bool()
    val rdata   = out port Bits(32 bits)
    val rvalid  = out port Bool()
    /** 항상 높다 — 초기화 소거도 다사이클 검사도 없다 (머리말 reset 절).
      * MmioConfig 와 인터페이스를 맞추기 위한 자리다. */
    val ready   = out port Bool()

    // ── 소유권 조회 — HiuPipeline.io.owner 의 반대편 ─────────────────
    /** 타이밍·원자성 계약 (환류 「경계 계약 필요」의 해소):
      *
      *  - **조합 0사이클** — devOwned 는 frame 과 같은 사이클의 값이다.
      *    HiuPipeline 승인(D11)이 조합 조회를 전제하므로 여기가 그 이행.
      *  - **사이클 원자성** — devOwned 는 그 사이클 시작 시점의 표 상태를
      *    본다. 전이 커밋은 에지 하나에서 유효·태그가 함께 갱신되는 단일
      *    기입이라 (E.7) 혼합 상태(새 유효 + 옛 태그 따위)가 조회에 보이는
      *    사이클이 존재하지 않는다. 전이 기입 수락 사이클의 조회는 전이
      *    **전** 상태, 다음 사이클부터 **후** 상태다.
      *  - **순서** — 전이와 진행 중 요청의 겹침 금지는 이 표의 계약이
      *    아니라 호스트 ABI 다 (§3.7 구성 교체·드레인 · §3.10). 표는 어느
      *    사이클에도 일관된 스냅숏을 줄 뿐, 겹침의 의미론을 구제하지 않는다.
      */
    val query = new Bundle {
      val frame    = in  port UInt(frameW bits)
      val devOwned = out port Bool()
    }

    // ── loud fault — 합성 가능한 sticky 상태 비트 (§3.8 · §5.5) ──────
    /** 직접 사상 충돌로 거절된 이양 기입 (머리말 — 축출은 암묵 전이라 금지). */
    val faultCollide = out port Bool()
    val faultClearCollide = in port Bool()
  }

  io.ready := True

  // ═══ 저장 구조 — 장치 소유 집합의 직접 사상 표 ═══════════════════════
  // validBits — 슬롯 점유 = 그 페이지가 장치 소유. reset 0 = 전부 호스트 소유.
  // tagVec   — 슬롯이 어느 페이지의 것인지 (프레임 상위). 조회가 조합
  //            0사이클이어야 하므로 (io.query 계약) Mem 이 아니라 레지스터
  //            배열이다 — Mem.readAsync 는 생성 경고를 남기고, 64 슬롯
  //            규모에서 레지스터 표가 더 곧다. 조회는 색인 먹싱 = 표 조회다
  //            (선형 비교 루프 아님).
  val validBits = Reg(Bits(ownEntries bits)) init 0
  val tagVec    = Vec.fill(ownEntries)(Reg(Bits(tagW bits)) init 0)

  // ═══ 소유권 조회 — 조합 (계약은 io.query 주석) ═══════════════════════
  val qIdx      = io.query.frame(idxW - 1 downto 0)
  val qTagLow   = io.query.frame(MMIO_FRAME_W - 1 downto idxW)
  // 전이 워드에 실을 수 없는 프레임(≥ 2^31)은 구조적으로 항상 호스트 소유다
  // (머리말 ⚠️). 상위가 0 일 때만 표가 발언권을 갖는다.
  val qHighZero =
    if (frameW > MMIO_FRAME_W) io.query.frame(frameW - 1 downto MMIO_FRAME_W) === 0
    else True
  io.query.devOwned := validBits(qIdx) &&
    tagVec(qIdx) === qTagLow.asBits && qHighZero

  // ═══ MMIO 접근 수락 (MmioConfig 와 같은 규약 — 동시 제시면 쓰기 우선) ═
  val aligned = io.addr(1 downto 0) === 0 // 비정렬 접근은 예약 오프셋 정책 (§3.7)
  val region  = io.addr(11 downto 8) === REGION
  val word    = io.addr(7 downto 2)       // 0 = OWN_IDX · 1 = OWN_DATA · 그 밖 예약

  val WORD_IDX  = (OFF_IDX  >> 2) & 0x3F
  val WORD_DATA = (OFF_DATA >> 2) & 0x3F

  val acceptW = io.ready && io.wstrobe
  val acceptR = io.ready && !io.wstrobe && io.rstrobe

  // ═══ OWN_IDX — 조회 색인 레지스터 (조회 대상만 정한다 — 전이 불참) ═══
  // 전폭 32b 를 그대로 든다 — 조회 공간(frameW)과 같은 해석이라, 상위 비트가
  // 선 색인의 상태 읽기는 아래 idxHighZero 로 0 (장치 소유 불가) 이 된다.
  val idxReg = Reg(Bits(32 bits)) init 0
  when(acceptW && aligned && region && word === WORD_IDX) {
    idxReg := io.wdata
  }

  // ═══ 공용 태그 조회 자리 — 전이 검사(쓰기 사이클) / 상태 읽기(읽기 사이클)
  // 한 사이클에 쓰기와 읽기는 동시 수락되지 않으므로 (쓰기 우선) 주소를
  // 먹싱해도 두 용도가 경합하지 않는다.
  val wFrame  = io.wdata(MMIO_FRAME_W - 1 downto 0).asUInt
  val wIdx    = wFrame(idxW - 1 downto 0)
  val wTag    = wFrame(MMIO_FRAME_W - 1 downto idxW).asBits
  val idxFrm  = idxReg.asUInt
  val chkAddr = UInt(idxW bits)
  chkAddr := idxFrm(idxW - 1 downto 0)
  when(io.wstrobe) { chkAddr := wIdx }
  val chkTag = tagVec(chkAddr)

  // ═══ OWN_DATA 읽기 — OWN_IDX 페이지의 상태 (수락 사이클 표 상태 스냅숏) ═
  val idxTagLow = idxFrm(MMIO_FRAME_W - 1 downto idxW).asBits
  // 색인 워드의 [31:MMIO_FRAME_W] — 전이 불가 영역이면 항상 호스트 소유.
  val idxHigh0 = idxFrm(31 downto MMIO_FRAME_W) === 0
  val devStateAtIdx =
    validBits(chkAddr) && chkTag === idxTagLow && idxHigh0

  val rdSel  = Reg(UInt(2 bits)) init 0 // 0 = 예약(0 반환) · 1 = IDX · 2 = DATA
  val rState = Reg(Bool()) init False
  io.rvalid := RegNext(acceptR, False)
  when(acceptR) {
    rdSel  := 0
    rState := devStateAtIdx
    when(aligned && region) {
      when(word === WORD_IDX)  { rdSel := 1 }
      when(word === WORD_DATA) { rdSel := 2 }
    }
  }
  io.rdata := 0 // 예약 오프셋 — 읽기 0 (§3.7)
  switch(rdSel) {
    is(1) { io.rdata := idxReg }
    is(2) { io.rdata(STATE_DEV_BIT) := rState }
  }

  // ═══ OWN_DATA 쓰기 — 전이. 한 번의 쓰기로 완결 (E.7 원자성) ══════════
  // 커밋 = 유효 비트 + 태그가 같은 에지에 갱신되는 단일 기입. 중간 상태 없음.
  val collide  = False
  val dataWr   = acceptW && aligned && region && word === WORD_DATA
  val slotBusy = validBits(wIdx)          // 슬롯 점유 여부
  val slotMine = chkTag === wTag          // 점유자가 = 이 워드의 페이지인가

  when(dataWr) {
    when(io.wdata(DIR_BIT)) {
      // 장치로 이양 (호스트 → 장치)
      when(!slotBusy) {
        validBits(wIdx) := True
        tagVec(wIdx)    := wTag
      }.elsewhen(!slotMine) {
        // 직접 사상 충돌 — 축출은 남의 페이지의 암묵 전이라 금지 (E.7).
        // 쓰기 무효 + loud sticky. 호스트는 점유 페이지를 먼저 회수하라.
        collide := True
      }
      // slotBusy && slotMine — 이미 장치 소유. 무연산 (Handoff 항등과 동형).
    }.otherwise {
      // 호스트로 회수 (장치 → 호스트)
      when(slotBusy && slotMine) {
        validBits(wIdx) := False
      }
      // 그 밖 — 이미 호스트 소유 (표에 없음). 무연산.
    }
  }

  // ═══ sticky fault — 세운다 / 명시적 해제 외엔 내리지 않는다 ══════════
  io.faultCollide := StickyFault(collide, io.faultClearCollide)

  // 전이 기입과 진행 중 요청(승인 조회)의 순서 규율은 호스트 ABI 다
  // (§3.7 드레인 · §3.10) — 여기서는 커밋의 원자성(단일 에지)과 조회
  // 스냅숏의 일관성만 보장한다 (io.query 주석의 계약).
}
