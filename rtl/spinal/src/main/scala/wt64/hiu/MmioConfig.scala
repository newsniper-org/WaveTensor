// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// MmioConfig — 4 KiB 구성 블록의 사상표 구역 (정본 §3.7 · §3.7.1 · §1.4.5 · §1.5)
//
// 이 모듈이 담는 것은 논리 ID 사상표 두 장이다:
//
//   LNID 소유 표   0x400~0x7FF   256 항목 × 4 B  (등록 슬롯 배열)
//   LBID 사상표    0x800~0xBFF   256 항목 × 4 B  (색인 = LBID 값 — §3.7.1:
//                                엔트리 수 256 은 LBID 가 평면 8비트라는
//                                인코딩 사실이 정한다. 인스턴스 개수가 아니다)
//
// 엔트리 폭 4 B = 단일 워드이므로 부분 갱신이라는 상태가 구조적으로 존재하지
// 않는다 (§3.7.1 — HIU-7 이 자명해지는 이유). 이 모듈의 모든 표 갱신은
// Mem 단일 워드 쓰기 하나로 커밋된다.
//
// ## 서로소 기입 거절 (D2, §1.4.5)
//
// LNID n 을 지점 p 에 등록하는 쓰기는, n 이 이 배달 범위에서 이미 소유돼
// 있으면 **쓰기 무효 + loud sticky fault** 다. 배달 시점 중재는 두지 않는다 —
// 표에 중복이 존재할 수 없으므로 중재할 것이 없다 (§1.4.5).
//
// 서로소 검사는 「LNID → 소유 여부」 **역방향 표** 하나로 O(1) 이다. 소유가
// 서로소이므로 역방향 관계가 *함수*다 — 그 사실 자체가 D2 의 선물이다.
// LNID 선형 비교 루프는 두지 않는다 (그 루프가 존재하는 한 그 값은 물리
// 인덱스다 — §1.4.3). 표는 이름 전폭 2^16 을 색인한다 — 상수 비트 슬라이스
// 없이 (INV-T2).
//
// ## Route.tla 대응 — 정식 GUARD-MAP 줄의 거처에 관한 주의
//
// Route 모델의 GUARD-MAP 여섯 줄은 담당 RTL 인 route/RouteJudge.scala 머리에
// 있다. lint_guard_map 은 가드당 저장소 전체에서 *정확히 한 줄*을 요구하므로
// 여기 같은 줄을 다시 적으면 전수성 검사가 깨진다. 그중 이 파일이 이행
// 지점인 두 가드만 아래에 서술로 남긴다 (lint 이 파싱하지 않는 형태다):
//
//   · Route.unique_owner — RouteJudge 쪽 줄이 DELEGATED(MmioConfig) 로 이
//     파일을 지목한다. 이행 지점: chkDupOwn — CHECK 단계에서 역방향 표
//     적중(revChkPresent)이 서면 커밋 억제 + faultDupOwner(StickyFault).
//     §1.4.5 「기입 시점의 거절」이며, Route.tla ConfigOwn 의
//     n ∉ ScopeUnion(s) 가드의 RTL 강제 지점이다.
//
//   · Route.view_sync — RouteJudge 쪽 매핑(io.viewWr)이 요구하는 구동 규약의
//     이행자가 이 모듈이다: 소유 집합·사상 존재를 바꾸는 모든 커밋은 자기
//     표 기입과 *같은 사이클, 같은 조건*에서 viewWr/bankWr 를 정확히 한 번
//     구동한다. 거절·무연산 기입은 구동하지 않는다 — 기입 성공 외에 뷰를
//     움직이는 경로가 구조적으로 없다.
//
// ## 예약 오프셋 — §3.7 (명령 인코딩 예약과 정반대 정책임에 주의)
//
// 이 모듈 관점의 표 밖 오프셋(0x000~0x3FF · 0xC00~0xFFF · 비정렬 접근)은
// 예약 *오프셋* 정책을 따른다: 쓰기 무시 · 읽기 0. 관대함이 하위 호환을
// 만들기 때문이다 (§3.7). 명령 인코딩의 예약 *필드*는 정반대다 — 0 이
// 아니면 malformation (§1.4.6 · §5.7): 그쪽에서는 관대함이 은닉 채널을
// 만든다. 같은 낱말, 정반대 정책 — 이 정책을 디코더로 옮겨 적지 말 것.
// (0x000~0x3FF 의 실제 구성 레지스터들은 다른 유닛 소관이다. 상위 데코더가
//  그쪽을 먼저 갈라낸다면 이 모듈에는 도달하지 않고, 도달하면 예약 정책이다.)
//
// ## reset 초기 상태 — §1.5
//
// reset 직후 모든 LNID 소유 집합은 공집합이고 모든 LBID 는 미사상이어야
// 한다. 역방향 표는 Mem 이라 reset 신호로 비울 수 없으므로, reset 해제 후
// 2^16 사이클의 초기화 소거(sweep)를 돌고 그동안 ready 를 내린다 — 구성하지
// 않은 기계가 우연히 동작하는 것을 막는 관측 가능한 구현이다. (RouteJudge
// 쪽 뷰·존재 비트 표는 레지스터라 reset 으로 스스로 비워진다.)

package wt64.hiu

import spinal.core._
import wt64.{Isa, StickyFault, Wt64Config}
import wt64.route.{BankWrite, ViewWrite}

/** 사상표 구역의 지역 상수.
  *
  * 엔트리 *내부* 비트 배치는 정본 §3.7.1 이 호스트 측 합의로 미룬 항목이다 —
  * 아래 배치는 이 구현이 내리는 잠정 결정이며 (보고서 model_feedback 참조),
  * 정본이 못박은 것(오프셋 · 엔트리 수 256 · 폭 4 B · 단일 워드 원자성)만
  * 규범이다.
  *
  *   LNID 소유 표 엔트리: [31] V · [30:24] 예약 · [23:16] 소유 지점 · [15:0] LNID
  *   LBID 사상표 엔트리:  [31] V · [30:16] 예약 · [15:8] 슬롯 구간 시작 · [7:0] 길이
  *     (LBID 엔트리가 슬롯 *구간*을 표현해야 한다는 요건은 §3.7.1 규범 —
  *      §2.4.1 조각별 슬롯 결정의 입력이다. 구간 해석 자체는 소비자 몫.)
  *
  * 엔트리 안의 예약 *비트*는 예약 오프셋과 같은 관대한 정책으로 둔다 —
  * 쓰기 무시(정규화해 0 저장) · 읽기 0. Common.scala 승격 후보다.
  */
object MmioConfig {
  /** 소유 지점 필드 폭 — 고정 8b. nPoints(형상)의 함수가 아니다 (INV-T1 정합:
    * 필드 폭은 형상 무관, 합법 값 검사는 기입 시점 구성 검사로 따로 선다). */
  val OWNER_POINT_W = 8
  val LNID_TBL_BASE = 0x400
  val LBID_TBL_BASE = 0x800
  val ENTRY_V_BIT   = 31
  /** 표 하나의 엔트리 수 — LBID 값 공간(평면 8b)이 정한다 (§3.7.1). */
  val TBL_ENTRIES   = 256
  /** 엔트리 정규화 마스크 — 예약 비트를 0 으로 저장하는 「쓰기 무시」의
    * 구현체다. 필드 재조립이 아니라 마스크 하나로 적는 이유: 정책(어느
    * 비트가 실리는가)이 상수 한 곳에 보이고, 기입 워드 전폭이 항상 이
    * 연산을 통과한다. */
  val LNID_ENTRY_MASK = 0x80FFFFFFL // V · 소유 지점 · LNID
  val LBID_ENTRY_MASK = 0x8000FFFFL // V · 슬롯 구간 시작 · 길이
}

/** 구성 레지스터 블록 — 사상표 구역.
  *
  * 버스 프로토콜은 상위 몫이다. 여기는 주소 · 쓰기데이터 · 쓰기스트로브 ·
  * 읽기데이터의 소박한 동기 인터페이스만 낸다:
  *
  *   - ready 가 높을 때만 접근이 수락된다 (초기화 소거 중 · LNID 기입 검사
  *     중에는 낮다 — 상위 어댑터가 대기시킨다).
  *   - 읽기: 수락 다음 사이클에 rdata 유효 (rvalid 1펄스).
  *   - LBID 기입: 1사이클 커밋. LNID 기입: 검사 1사이클 뒤 커밋/거절.
  *     어느 쪽이든 커밋 자체는 Mem 단일 워드 쓰기 하나다 (§3.7.1 원자성).
  *
  * RouteJudge 로는 viewWr(합집합 뷰 기입) · bankWr(사상 존재 비트 기입)를
  * 낸다 — RouteJudge io 주석의 구동 규약 그대로, 기입 성공시에만, 자기 표
  * 기입과 같은 사이클에 정확히 한 번.
  */
case class MmioConfig(cfg: Wt64Config) extends Component {
  import MmioConfig._

  // 소유 지점 필드가 8b 이므로 표현 가능한 지점 수의 상한이다. 형상이 이를
  // 넘으면 필드를 넓히는 합의가 먼저다 — 조용히 잘리게 두지 않는다.
  require(cfg.nPoints <= (1 << OWNER_POINT_W), "소유 지점 필드 8b 초과 형상 — 엔트리 배치 합의부터 다시")

  /** RouteJudge 의 뷰 표 용량 — 같은 식이어야 viewWr 폭이 맞물린다.
    * Wt64Config.viewEntries 로 승격 완료 — 두 모듈이 같은 식을 본다
    * (두 곳이 같은 식을 따로 말하고 있다 — 드리프트 표면). */
  val viewEntries = cfg.viewEntries // 승격 — Wt64Config 한 곳 정의

  /** 등록을 수락하는 MMIO 슬롯 수 — 뷰 용량과 표 크기 중 작은 쪽. 용량 밖
    * 슬롯 기입을 수락하면 표에는 있고 뷰에는 없는 이름(= 조용히 사라지는
    * 이름, view_sync 스큐)이 생기므로 크게 거절한다. capability 축의 상한이지
    * (slotCap 선례) 이름 값 공간의 축소가 아니다 — INV-T1 무위반. */
  val capSlots = viewEntries.min(TBL_ENTRIES)

  val io = new Bundle {
    // ── MMIO (소박한 동기 포트 — 버스 프로토콜은 상위 몫) ────────────
    val addr    = in  port UInt(12 bits) // 4 KiB 블록 안 바이트 오프셋
    val wstrobe = in  port Bool()
    val wdata   = in  port Bits(32 bits)
    val rstrobe = in  port Bool()
    val rdata   = out port Bits(32 bits)
    val rvalid  = out port Bool()
    val ready   = out port Bool()

    // ── RouteJudge 구동 표면 (합집합 뷰 · 사상 존재 — 기입 성공시에만) ──
    val viewWr = out port ViewWrite(viewEntries)
    val bankWr = out port BankWrite()

    // ── loud fault — 합성 가능한 sticky 상태 비트 (§3.7 · §5.5) ──────
    // 원인별로 접지 않고 가른다 (§5.6 폴딩 규범 — 폴딩 여부는 신호마다 명시).
    val faultDupOwner = out port Bool() // D2 서로소 위반 기입 거절
    val faultBadWrite = out port Bool() // 그 밖의 거절된 LNID 기입 (아래 폴딩 규정 참조)
    val faultClearDup = in  port Bool() // 명시적 해제 — 이 외엔 내려가지 않는다
    val faultClearBad = in  port Bool()
  }

  // ═══ 저장 구조 ═══════════════════════════════════════════════════════
  // fwdMem  — LNID 소유 표 그 자체 (MMIO 가 읽는 정본 내용물). 슬롯 배열.
  // revMem  — 「LNID → 소유 여부」 역방향 표 = 서로소 검사 O(1). 배달 조회와
  //           합집합 뷰는 RouteJudge 쪽 표가 담당하므로 여기는 존재 비트
  //           1b 로 족하다 (지점 번호는 fwdMem 이 정본으로 든다).
  // lbidMem — LBID 사상표 (색인 = LBID 값).
  val fwdMem  = Mem(Bits(32 bits), TBL_ENTRIES)
  val revMem  = Mem(Bits(1 bits), 1 << Isa.LNID_W)
  val lbidMem = Mem(Bits(32 bits), TBL_ENTRIES)

  // ═══ 초기화 소거 — §1.5 「reset 직후 전부 공집합·미사상」 ═══════════
  val initCnt  = Reg(UInt(Isa.LNID_W bits)) init 0
  val initDone = RegInit(False)
  val sweeping = !initDone
  when(sweeping) {
    initCnt := initCnt + 1
    when(initCnt === ((1 << Isa.LNID_W) - 1)) {
      initDone := True
    }
  }

  // ═══ 단일 쓰기 포트 (Mem 마다 하나 — 소거와 기능 쓰기를 먹싱) ════════
  val revWrEn   = False
  val revWrAddr = UInt(Isa.LNID_W bits)
  val revWrData = Bits(1 bits)
  revWrAddr := 0
  revWrData := 0

  val fwdWrEn   = False
  val fwdWrAddr = UInt(8 bits)
  val fwdWrData = Bits(32 bits)
  fwdWrAddr := 0
  fwdWrData := 0

  val lbWrEn   = False
  val lbWrAddr = UInt(8 bits)
  val lbWrData = Bits(32 bits)
  lbWrAddr := 0
  lbWrData := 0

  when(sweeping) {
    revWrEn   := True
    revWrAddr := initCnt
    when(initCnt < TBL_ENTRIES) {
      fwdWrEn := True
      lbWrEn  := True
      fwdWrAddr := initCnt.resized
      lbWrAddr  := initCnt.resized
    }
  }

  // ═══ 접근 수락 ═══════════════════════════════════════════════════════
  // busy = LNID 기입의 CHECK 단계 (검사에 역방향 표 동기 읽기 1사이클이 든다.
  // 커밋은 그래도 Mem 단일 워드 쓰기 하나 — 원자성(§3.7.1)은 그대로다).
  val busy = RegInit(False)
  io.ready := initDone && !busy

  val aligned = io.addr(1 downto 0) === 0 // 비정렬 접근은 예약 오프셋 정책 (§3.7)
  val region  = io.addr(11 downto 10)     // 1 = LNID 표 · 2 = LBID 표 · 0,3 = 예약
  val wordIdx = io.addr(9 downto 2)       // 표 안 워드 색인 (256 항목 = 1 KiB 만재)

  val REGION_LNID = LNID_TBL_BASE >> 10
  val REGION_LBID = LBID_TBL_BASE >> 10

  val acceptW = io.ready && io.wstrobe
  val acceptR = io.ready && !io.wstrobe && io.rstrobe // 동시 제시면 쓰기 우선

  // ═══ 읽기 — 수락 다음 사이클 rdata (예약 오프셋은 읽기 0 — §3.7) ═════
  val memRdEn = acceptR || acceptW
  val fwdRd   = fwdMem.readSync(wordIdx, memRdEn)
  val lbRd    = lbidMem.readSync(wordIdx, memRdEn)

  val rdSel = Reg(UInt(2 bits)) init 0 // 0 = 예약(0 반환) · 1 = LNID 표 · 2 = LBID 표
  io.rvalid := RegNext(acceptR, False)
  when(acceptR) {
    rdSel := 0
    when(aligned) {
      rdSel := region
    }
  }
  io.rdata := 0
  switch(rdSel) {
    is(REGION_LNID) { io.rdata := fwdRd }
    is(REGION_LBID) { io.rdata := lbRd }
  }

  // ═══ RouteJudge 구동 기본값 — 커밋 사이클에만 valid 가 선다 ═════════
  io.viewWr.valid := False
  io.viewWr.idx   := 0
  io.viewWr.en    := False
  io.viewWr.lnid  := 0
  io.bankWr.valid  := False
  io.bankWr.lbid   := 0
  io.bankWr.mapped := False

  // ═══ LBID 사상표 기입 — 1사이클 커밋 ════════════════════════════════
  // 지킬 불변식이 없으므로 (서로소성은 LNID 소유의 규범이다) 재기입·해제를
  // 포함해 무조건 수락한다. 단일 워드라 부분 상태가 없다 (HIU-7).
  // 예약 비트 [30:16] 은 정규화해 0 으로 저장한다 (쓰기 무시·읽기 0).
  val lbidWrite = acceptW && aligned && region === REGION_LBID
  when(lbidWrite) {
    lbWrEn   := True
    lbWrAddr := wordIdx
    lbWrData := io.wdata & B(LBID_ENTRY_MASK, 32 bits)
    // 존재 비트 뷰(RouteJudge.bankPresent)는 같은 사이클 같은 조건에서
    // 정확히 한 번 구동된다 — view_sync 구동 규약.
    io.bankWr.valid  := True
    io.bankWr.lbid   := wordIdx
    io.bankWr.mapped := io.wdata(ENTRY_V_BIT)
  }

  // ═══ LNID 소유 표 기입 — CHECK 1사이클 뒤 커밋/거절 ══════════════════
  val lnidWrite = acceptW && aligned && region === REGION_LNID

  // 수락 시점 래치 — CHECK 사이클의 판단 재료. 워드는 정규화해 통째로 든다
  // (pWord 가 곧 커밋될 엔트리다 — 조립을 두 번 하지 않는다).
  val pSlot = Reg(UInt(8 bits)) init 0
  val pWord = Reg(Bits(32 bits)) init 0
  when(lnidWrite) {
    busy  := True
    pSlot := wordIdx
    pWord := io.wdata & B(LNID_ENTRY_MASK, 32 bits)
  }
  val pV     = pWord(ENTRY_V_BIT)
  val pPoint = pWord(23 downto 16).asUInt
  val pLnid  = pWord(15 downto 0).asUInt

  // 서로소 검사용 역방향 표 읽기 — 수락 사이클에 새 LNID 로 발사한다.
  val revChkAddr    = io.wdata(15 downto 0).asUInt
  val revChk        = revMem.readSync(revChkAddr, memRdEn)
  val revChkPresent = revChk(0)

  // 기존 슬롯 내용 (fwdRd 가 같은 수락 사이클에 읽혀 CHECK 에서 유효하다).
  val oldV    = fwdRd(ENTRY_V_BIT)
  val oldLnid = fwdRd(15 downto 0).asUInt

  // 거절 원인별 발화선. faultBadWrite 는 세 원인을 한 비트로 접는다 —
  // 폴딩 규정 (§5.6 이 요구하는 명시): 「용량 밖 슬롯」·「없는 지점 등록」·
  // 「점유 슬롯 재기입」은 전부 '거절된 LNID 기입'이며 수리 주체가 같다
  // (드라이버). D2(서로소 위반)와는 접지 않는다 — 그쪽은 §1.4.5 가 이름한
  // 별도 규범이다.
  val chkDupOwn = False
  val chkBadWr  = False

  when(busy) {
    busy := False
    // 용량 밖 슬롯 — 표에는 실리고 뷰에는 못 실리는 이름을 만들지 않는다.
    val slotOutOfCap = if (capSlots >= TBL_ENTRIES) False else pSlot >= capSlots
    when(pV) {
      // 없는 지점에 등록하면 그 LNID 는 뷰에는 있고 배달자는 없는 —
      // 조용히 사라지는 이름이 된다. 그래서 기입 시점에 크게 거절한다.
      val pointBad = pPoint >= cfg.nPoints
      when(slotOutOfCap || oldV || pointBad) {
        chkBadWr := True // 거절 — 점유 슬롯은 먼저 해제(V=0 기입)하고 다시
      }.elsewhen(revChkPresent) {
        chkDupOwn := True // D2 — 서로소 위반. 쓰기 무효 + loud fault (§1.4.5)
      }.otherwise {
        // 커밋 — 표(fwdMem)·역방향 표(revMem)·RouteJudge 뷰(viewWr)가
        // *같은 사이클, 같은 조건*에서만 함께 갱신된다. 기입 성공 외에
        // 뷰를 움직이는 경로가 없다 (view_sync 구동 규약).
        fwdWrEn   := True
        fwdWrAddr := pSlot
        fwdWrData := pWord // 정규화된 워드 그대로 — V·지점·LNID
        revWrEn   := True
        revWrAddr := pLnid
        revWrData := 1
        io.viewWr.valid := True
        io.viewWr.idx   := pSlot.resized
        io.viewWr.en    := True
        io.viewWr.lnid  := pLnid
      }
    }.otherwise {
      // V=0 기입 = 슬롯 해제. 점유 슬롯이면 표·역방향 표·뷰를 함께 비우고,
      // 빈 슬롯이면 무연산이다 (거절이 아니라 이미 원하는 상태다).
      // 용량 밖 슬롯은 점유일 수 없으므로 (기입이 거절됐다) 자연히 무연산.
      when(oldV) {
        fwdWrEn   := True
        fwdWrAddr := pSlot
        fwdWrData := 0
        revWrEn   := True
        revWrAddr := oldLnid
        revWrData := 0
        io.viewWr.valid := True
        io.viewWr.idx   := pSlot.resized
        io.viewWr.en    := False // ViewWrite 규약 — False 기입이 엔트리 해제
        io.viewWr.lnid  := oldLnid
      }
    }
  }

  // 쓰기 포트 결선 (Mem 마다 정확히 하나).
  revMem.write(revWrAddr, revWrData, revWrEn)
  fwdMem.write(fwdWrAddr, fwdWrData, fwdWrEn)
  lbidMem.write(lbWrAddr, lbWrData, lbWrEn)

  // ═══ sticky fault — 세운다 / 명시적 해제 외엔 내리지 않는다 ══════════
  io.faultDupOwner := StickyFault(chkDupOwn, io.faultClearDup)
  io.faultBadWrite := StickyFault(chkBadWr, io.faultClearBad)

  // 구성 쓰기와 실행(토큰 흐름)의 순서 자체는 호스트 의무다 (§3.10 호스트
  // ABI 경계) — 여기서는 커밋의 원자성(단일 워드, §3.7.1)과 뷰 동시 구동만
  // 보장한다.
}
