// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// RouteJudge — 배달 범위 진입점 판정기.
//
// 정본 §1.6.3 「route fault (신설)」 전부가 이 모듈의 계약이다:
//   · 발화 조건 2 — ① 토큰의 LNID 가 이 배달 범위 전체에서 어느 소유자에게도
//     속하지 않는다. ② `src_kind=1` 인 명령의 LBID 가 사상표에 없다.
//   · 판정 주체와 범위 — 판정 주체는 배달 범위의 *진입점*이고, 조건 ②도
//     같은 자리에서 판정한다. 따라서 route fault 는 어느 조건이든 실행 전에
//     발화하고, 「계층당 1회」는 두 조건을 합쳐 센 상한이다.
//   · 토큰 전파 — fault 의 발화는 토큰을 소멸시키지 않는다. *차단 게이트는
//     두지 않는다.* 통과의 효과는 0이다 — 수락은 소유권이 막는다.
//   · sticky — route fault 는 sticky 여야 한다. 한 사이클 펄스는 관측자가
//     놓친다.
//
// 선-formal 계약은 rtl/formal/tla/Route.tla (가드 6). 대응은 아래 GUARD-MAP.
//
// GUARD-MAP: Route.global_judge      -> viewHit — 판정은 진입점이 든 합집합 뷰 표(viewValid/viewName)의 적중 하나로만 선다; 지점별 비소유(NonOwners) 신호는 IO 에 입력 자체가 없다 (§1.6.3 「형제 노드의 미스는 fault 가 아니다」)
// GUARD-MAP: Route.fault_once        -> anyMiss — 두 발화 조건(missLnid·missLbid)을 단일 OR 로 접어 토큰 제시당 발화 신호가 최대 1개다; 합산 경로가 없다 (ISA-4, §1.6.3 「계층당 1회」)
// GUARD-MAP: Route.loud_fault        -> faultFire·io.fault — anyMiss 인 토큰은 조건 없이 faultFire 를 세우고 StickyFault 로 남는다; miss 를 삼키는 분기가 없고 해제는 io.faultClear 명시 해제뿐이다 (INV-T3, ISA-6)
// GUARD-MAP: Route.view_sync         -> io.viewWr — 뷰는 이 모듈의 상태이고 갱신 경로는 이 단일 포트뿐이며 기입 사이클에 즉시 반영된다(지연 단 없음); 소유 기입마다 이 포트를 구동하는 것은 MmioConfig 의 계약이다(IO 주석의 구동 규약)
// GUARD-MAP: Route.scope_independent -> io — 다른 범위의 뷰·사상표·fault 를 실어 오는 입력이 없고, tokOut 은 무게이트 전량 통과다; 판정은 (토큰, 자기 뷰, 자기 존재 비트 표)만의 함수다 (Route.tla Inv_ScopeLocal 의 구조적 실현)
// GUARD-MAP: Route.unique_owner      -> DELEGATED(MmioConfig) — 서로소성 강제는 사상표 *기입 시점의 거절*이다 (§1.4.5); 이 판정기는 기입 판정 경로를 갖지 않고, 배달 시점 중재 장치를 두지 않는 것이 그 규범의 나머지 절반이다
package wt64.route

import spinal.core._
import spinal.lib._
import wt64._
import wt64.Types.Tag

/** RouteJudge 의 지역 상수 — Common.scala 승격 후보 (보고서 promote 참조). */
object RouteJudge {
  /** `src_kind` 필드 폭. 어셈블러 encode_pass 관측 — OPREF 본문 워드는
    * `((noc_route&0xFF)<<8 | src_kind&0xF) << 16 | 0x7<<8 | 1` 이므로
    * [31:24]=LBID · [23:20]=예약(폐지된 포트 니블, 반드시 0) · [19:16]=src_kind.
    * 값 배정은 정본 §1.4.3: 0 직접 / 1 결과 뱅크(첨자는 LBID) / 2 난수 뱅크 /
    * ≥3 예약 → 오류. ≥3 의 거절은 malformation 판정(디코드 경계) 소관이다 —
    * 이 판정기의 축이 아니다. */
  val SRC_KIND_W = 4
  /** 결과 뱅크 조회 — 이 값일 때만 LBID 축(ISA-8)이 판정 대상이다 (§1.4.3). */
  val SRC_KIND_RESULT = 1
}

/** 판정 대상 토큰 — 태그(§1.4.4) 에 명령의 결과 뱅크 참조 축을 얹은 것.
  * 태그 조립·분해는 Types.Tag 한 곳이다 — 여기서는 통째로 나르기만 한다. */
case class RouteTok() extends Bundle {
  val tag     = Tag()
  /** OPREF `noc_route[7:0]` 전폭 — 값 공간은 항상 0..255 (INV-T1). */
  val lbid    = UInt(Isa.LBID_W bits)
  val srcKind = UInt(RouteJudge.SRC_KIND_W bits)
}

/** 합집합 뷰 기입 포트 — MMIO 소유 기입(§1.4.5 @sec:isa-mapping)이 이리로
  * 들어온다. 엔트리 직접 지정(idx) 방식이라 이 모듈에는 할당 로직이 없다 —
  * 엔트리 배정·서로소 거절은 전부 MmioConfig 소관이다. */
case class ViewWrite(entries: Int) extends Bundle {
  val valid = Bool()
  val idx   = UInt(log2Up(entries) bits)
  /** False 기입이 엔트리 해제다 — reset(전부 무효, §1.5)로 되돌리는 길. */
  val en    = Bool()
  val lnid  = UInt(Isa.LNID_W bits)
}

/** LBID 사상표 존재 비트 기입 포트 — 같은 방식 (MMIO 소관, §1.5). */
case class BankWrite() extends Bundle {
  val valid  = Bool()
  val lbid   = UInt(Isa.LBID_W bits)
  val mapped = Bool()
}

/** 배달 범위 진입점 판정기.
  *
  * 하나의 배달 범위(계층)마다 하나 인스턴스된다. 다른 범위의 상태를 실어
  * 오는 포트가 없다는 사실 자체가 scope_independent 의 구현이다 — 깊이를
  * 쌓는 것은 이 모듈을 겹으로 인스턴스하는 상위의 일이고, 겹 사이에 배선할
  * 것은 토큰 흐름뿐이다.
  *
  * 시간축 유의: 선-formal 은 범위당 1회 원자 판정만 모델링했다 (Route.tla
  * 머리 주석 「시간축 없음」). 이 RTL 은 tokIn 을 valid 스트로브 — 토큰 하나가
  * 정확히 한 사이클 valid — 로 받는 전제 위에 있고, 그 전제의 시간축 검증은
  * 후-formal(sby) 몫이다.
  */
class RouteJudge(cfg: Wt64Config) extends Component {

  /** 뷰 표 용량 — 형상 선택이다. 지점 수에 비례한 기본값을 쓴다. 용량은
    * 「몇 개의 이름을 소유로 구성할 수 있는가」만 정하고, 이름의 값 공간
    * (16b 전폭)에는 닿지 않는다 — INV-T1 무위반. 승격 후보 (promote). */
  val viewEntries = cfg.viewEntries // 승격 — Wt64Config 한 곳 정의

  /** 존재 비트 표 크기 — LBID 값 공간 전폭 256. 형상의 함수가 아니라 이름
    * 공간의 함수다 (INV-T1). */
  private val bankEntries = 1 << Isa.LBID_W

  val io = new Bundle {
    /** 진입 토큰. valid 스트로브 — 토큰 하나 = valid 한 사이클. */
    val tokIn  = slave(Flow(RouteTok()))
    /** 통과 토큰 — 입력 그대로다 (§1.6.3 토큰 전파, D3). 차단 게이트 없음.
      * fault 여부는 이 흐름에 실리지 않는다 — 관측면(fault·faultFire)으로만
      * 나간다. */
    val tokOut = master(Flow(RouteTok()))

    /** 합집합 뷰 기입 — 구동 규약(MmioConfig 계약): 이 범위의 소유 집합을
      * 바꾸는 모든 MMIO 기입은 표 반영과 같은 조작으로 이 포트를 정확히
      * 한 번 구동한다. 이 규약이 지켜지는 한 뷰와 실재의 스큐(Route.tla
      * view_sync 삭제 배터리가 보인 결함형)는 표현 자체가 불가능하다. */
    val viewWr = in(ViewWrite(viewEntries))
    /** LBID 사상표 존재 비트 기입 — 같은 구동 규약. */
    val bankWr = in(BankWrite())

    /** route fault sticky — 클러스터·Pod 경계 관측용 (§1.6.3 sticky). */
    val fault      = out(Bool())
    /** 명시적 해제 — 이것 외에 fault 를 내리는 경로는 없다. */
    val faultClear = in(Bool())
    /** 발화 펄스 — 토큰 제시 사이클에 선다. 계수 관측면. */
    val faultFire  = out(Bool())
  }

  // ── 상태: 진입점이 든 합집합 뷰 (§1.6.3 1항 — 「합집합 표를 갖든 …」의
  //    표 갈래) 와 LBID 존재 비트 표. reset 직후 전부 무효 — 구성 전에는
  //    어떤 토큰도 배달되지 않고 전부 fault 다. 의도다 (§1.5).
  private val viewValid   = Vec.fill(viewEntries)(RegInit(False))
  private val viewName    = Vec.fill(viewEntries)(Reg(UInt(Isa.LNID_W bits)) init (0))
  private val bankPresent = Reg(Bits(bankEntries bits)) init (0)

  when(io.viewWr.valid) {
    viewValid(io.viewWr.idx) := io.viewWr.en
    viewName(io.viewWr.idx)  := io.viewWr.lnid
  }
  when(io.bankWr.valid) {
    bankPresent(io.bankWr.lbid) := io.bankWr.mapped
  }

  // ── 판정 — 두 발화 조건을 진입점의 한 자리에서 (§1.6.3 2항, D1).
  //
  // 뷰 적중은 *이름 전폭* 연상 조회다. 도는 축은 구성 엔트리이지 하드웨어
  // 인스턴스가 아니다 — §1.4.3 이 금지한 「인스턴스 개수만큼 도는 비교 루프」
  // (그 루프가 존재하는 한 값은 물리 인덱스다)와 다른 물건이고, 비트 슬라이스
  // 디먹스(INV-T2)도 아니다.
  private val lnidIn  = io.tokIn.payload.tag.lnid
  private val viewHit = viewValid.zip(viewName)
    .map { case (v, n) => v && n === lnidIn }
    .reduce(_ || _)

  /** 발화 조건 ① — 전역 미스. 지역 비소유는 여기 없다: 이 모듈은 지점별
    * 소유를 아예 모른다 (ISA-3). */
  private val missLnid = !viewHit
  /** 발화 조건 ② — src_kind=1 이고 LBID 미사상. 존재 비트 표 직조회 (ISA-8). */
  private val missLbid = io.tokIn.payload.srcKind === RouteJudge.SRC_KIND_RESULT &&
    !bankPresent(io.tokIn.payload.lbid)

  /** 두 조건의 접기 — OR 하나. 둘 다 밟아도 발화는 1회다 (ISA-4). */
  private val anyMiss   = missLnid || missLbid
  private val faultFire = io.tokIn.valid && anyMiss

  // ── 출력 — 토큰은 판정 결과와 무관하게 전량 통과 (D3).
  io.tokOut << io.tokIn
  io.faultFire := faultFire
  io.fault := StickyFault(set = faultFire, clear = io.faultClear)
}
