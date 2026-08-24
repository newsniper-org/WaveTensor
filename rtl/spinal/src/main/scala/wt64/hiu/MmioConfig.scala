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
//     움직이는 경로가 구조적으로 없다. (2026-08-24 결정 A 로 '성공'의
//     정의가 좁아졌다 — 예약 비트 비0 기입이 거절 쪽으로 넘어갔다. 구동
//     규약 자체는 그대로다: 좁아진 것은 술어이지 규약이 아니다.)
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
// ## 엔트리 *내부* 예약 비트 — 엄격 (결정 A, 2026-08-24)
//
// 위의 관대한 정책은 예약 *오프셋* 에만 적용된다. 엔트리 안의 예약 *비트*는
// 정반대로 **엄격**이다: 비0 기입은 수락되지 않고 loud fault 다.
//
// 구별 축은 방향이다. 예약 오프셋은 「장치가 *돌려주는* 쪽」이라 관대함이
// 하위 호환을 만든다 (장차 그 오프셋이 뭔가를 뜻하게 돼도 옛 드라이버는
// 0 을 읽고 지나간다). 엔트리 안의 비트는 호스트가 써 넣고 장치가 해석하는
// 「*받아들이는* 쪽」이라, 관대함은 검사받지 않는 비트를 남긴다 — 그 비트가
// 장차 뜻을 얻는 순간 옛 드라이버의 쓰레기가 조용히 의미가 된다.
//
// 부가 근거 — 폭이 아직 확정되지 않았다는 사실 자체가 이유다: 정본은 소유
// 지점 필드를 「형상 무관 고정 폭」으로만 규정하고 값을 비웠다. 넓힐 압력은
// 이미 명시적이다 (아래 nPoints <= 2^8 require). 예약 비트를 엄격하게
// 지켜야만 8b → 15b 확장이 기존 드라이버를 깨지 않는다.
//
// 되돌림 비대칭: 엄격 → 관대는 언제든 무해하다 (거절이 사라질 뿐이고
// 드라이버는 이미 0 을 쓰고 있다). 관대 → 엄격은 편도다 (돌던 드라이버가
// 죽는다). 한쪽만 두 결말에 모두 도달한다 — 그래서 엄격에서 시작한다.
//
// ## 구성 표면에 sub-word(바이트 인에이블) 쓰기 금지 — 규범 (결정 B)
//
// 이 파일 머리의 「엔트리 폭 4 B = 단일 워드이므로 부분 갱신이라는 상태가
// 구조적으로 존재하지 않는다」(§3.7.1) 는 논증은 *한 워드 쓰기가 쪼개지지
// 않는다*를 전제한다. 정본은 그 전제를 어디에서도 보증한 적이 없고, 이
// RTL 은 포트에 바이트 스트로브를 두지 않아 구조로만 봉해 두고 있었다 —
// 즉 문서화되지 않은 ABI 전제였다.
//
// 이제 규범이다: **구성 페이지(4 KiB) 전체에 대해 sub-word 쓰기는 거절 +
// loud fault** 다. 적용 범위는 사상표만이 아니라 구성 표면 전체다 — E.7
// 전이 워드·E.12 발화 워드가 같은 원자성 논증 위에 서 있기 때문이다.
//
// 이 모듈은 그 규범을 *표현할 수단이 없다*. io.wstrobe 는 워드 낱알이고
// 바이트 인에이블 입력이 아예 없으므로 「sub-word 기입」이라는 사건이 이
// 경계에 도달할 수 없다. 따라서 거절의 이행 지점은 상위 어댑터(PCIe/AXI →
// 이 포트 브리지)다: 호스트 버스는 sub-word 쓰기를 허용하므로, 어댑터가
// 그것을 거절하지 않으면 read-modify-write 가 조용히 생기고 위 원자성
// 논증이 무너진다. 이것은 이 저장소 밖에서 지켜야 할 계약이며 여기서는
// 검사할 수 없다 — rtl/README.md 「구성 표면 sub-word ABI 조항」 참조.
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
  * 엔트리 *내부* 비트 배치는 정본 §3.7.1 이 호스트 측 합의로 미룬 항목이었고,
  * 2026-08-24 합의가 아래 배치로 **확정**했다 (그 전까지는 이 구현의 잠정
  * 결정이었다 — 보고서 model_feedback 참조). 정본이 직접 못박은 것은
  * 오프셋 · 엔트리 수 256 · 폭 4 B · 단일 워드 원자성이다.
  *
  *   LNID 소유 표 엔트리: [31] V · [30:24] 예약 · [23:16] 소유 지점 · [15:0] LNID
  *   LBID 사상표 엔트리:  [31] V · [30:16] 예약 · [15:8] 슬롯 구간 시작 · [7:0] 길이
  *     (LBID 엔트리가 슬롯 *구간*을 표현해야 한다는 요건은 §3.7.1 규범 —
  *      §2.4.1 조각별 슬롯 결정의 입력이다. 구간 해석 자체는 소비자 몫.)
  *
  * 폭의 지위는 서로 다르다 — 섞어 읽지 말 것:
  *   · LNID 16b 는 *정본*이다 (§1.1 정의 · §1.4.4 「태그의 16비트 노드 ID
  *     필드 전폭이 LNID」).
  *   · LBID 8b 도 *정본*이다 (§1.1 · §1.4.3).
  *   · **소유 지점 8b 는 정본에 없다** — 2026-08-24 합의가 처음 정한 값이다
  *     (정본은 「형상 무관 고정 폭」만 규정하고 값을 비웠다). 그래서 예약
  *     비트가 엄격해야 이 값을 나중에 넓힐 수 있다 (파일 머리 결정 A).
  *
  * 엔트리 안의 예약 *비트*는 **엄격**이다 — 비0 기입은 거절 + loud fault
  * (파일 머리 「엔트리 내부 예약 비트」 절). 예약 *오프셋*의 관대한 정책을
  * 이리로 옮겨 적지 말 것.
  */
object MmioConfig {
  /** 소유 지점 필드 폭 — 고정 8b. nPoints(형상)의 함수가 아니다 (INV-T1 정합:
    * 필드 폭은 형상 무관, 합법 값 검사는 기입 시점 구성 검사로 따로 선다).
    * 정본이 정하지 않은 값이다 (위 스칼라독) — 넓힐 여지는 예약 비트 엄격
    * 정책이 지킨다. */
  val OWNER_POINT_W = 8
  val LNID_TBL_BASE = 0x400
  val LBID_TBL_BASE = 0x800
  val ENTRY_V_BIT   = 31
  /** 표 하나의 엔트리 수 — LBID 값 공간(평면 8b)이 정한다 (§3.7.1). */
  val TBL_ENTRIES   = 256
  /** 엔트리 적재 마스크 — 실제로 뜻을 갖는 비트. 필드 재조립이 아니라 마스크
    * 하나로 적는 이유: 배치 정책이 상수 한 곳에 보인다. */
  val LNID_ENTRY_MASK = 0x80FFFFFFL // V · 소유 지점 · LNID
  val LBID_ENTRY_MASK = 0x8000FFFFL // V · 슬롯 구간 시작 · 길이

  /** 예약 비트 마스크 — 적재 마스크의 여집합으로 *유도*한다 (두 상수가 따로
    * 표류할 자리를 없앤다). 이 비트가 하나라도 서 있으면 기입은 거절 +
    * loud fault 다 (결정 A — 파일 머리 「엔트리 내부 예약 비트」).
    *
    * 예전에는 이 자리에 정규화(`wdata & ENTRY_MASK`)가 있었고, 그것이 곧
    * 「비0 을 조용히 0 으로 만들어 수락」이었다. 지금은 정규화가 없다 —
    * 커밋되는 워드에 예약 비트가 서지 않는다는 사실은 마스크가 아니라
    * *거절*이 보장한다. 그래서 저장 워드는 호스트가 쓴 워드와 항등이다. */
  val LNID_RSV_MASK = (~LNID_ENTRY_MASK) & 0xFFFFFFFFL // [30:24]
  val LBID_RSV_MASK = (~LBID_ENTRY_MASK) & 0xFFFFFFFFL // [30:16]
}

/** 구성 레지스터 블록 — 사상표 구역.
  *
  * 버스 프로토콜은 상위 몫이다. 여기는 주소 · 쓰기데이터 · 쓰기스트로브 ·
  * 읽기데이터의 소박한 동기 인터페이스만 낸다:
  *
  *   - ready 가 높을 때만 접근이 수락된다 (초기화 소거 중 · LNID 기입 검사
  *     중에는 낮다 — 상위 어댑터가 대기시킨다).
  *   - 읽기: 수락 다음 사이클에 rdata 유효 (rvalid 1펄스).
  *   - LBID 기입: 1사이클 커밋/거절. LNID 기입: 검사 1사이클 뒤 커밋/거절.
  *     어느 쪽이든 커밋 자체는 Mem 단일 워드 쓰기 하나다 (§3.7.1 원자성).
  *   - 쓰기 낱알은 워드 하나뿐이다 — sub-word 는 이 경계에 도달할 수 없다
  *     (결정 B, 파일 머리).
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
    // 쓰기 낱알은 *워드 하나*다. 바이트 인에이블 입력이 없는 것은 누락이
    // 아니라 규범이다 (결정 B — 파일 머리 「sub-word 쓰기 금지」): 이 포트에
    // 도달하는 쓰기는 정의상 쪼개지지 않는 32b 하나이고, 그 사실 위에
    // §3.7.1 원자성 논증이 서 있다. sub-word 요청의 거절은 상위 어댑터
    // 의무이며 이 경계에서는 표현조차 불가능하다.
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
    val faultBadWrite = out port Bool() // 그 밖의 거절된 구성 기입 (아래 폴딩 규정 참조)
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
  // 사상 자체에 지킬 불변식은 없으므로 (서로소성은 LNID 소유의 규범이다)
  // 재기입·해제를 포함해 수락한다. 단일 워드라 부분 상태가 없다 (HIU-7).
  //
  // 거절 원인은 정확히 하나다: 예약 비트 [30:16] 비0 (결정 A). 예전에는
  // 이 축에 거절 경로가 아예 없었고 예약 비트를 마스크로 지워 수락했다.
  val lbidWrite = acceptW && aligned && region === REGION_LBID
  val lbRsvBad  = (io.wdata & B(LBID_RSV_MASK, 32 bits)) =/= 0
  val chkLbBadWr = lbidWrite && lbRsvBad // 거절 발화선 (faultBadWrite 로 접힌다)
  val lbidCommit = lbidWrite && !lbRsvBad
  when(lbidCommit) {
    lbWrEn   := True
    lbWrAddr := wordIdx
    // 정규화 없음 — 예약 비트가 0 이 아니면 여기 도달하지 못한다. 저장
    // 워드는 호스트가 쓴 워드와 항등이다 (LBID_RSV_MASK 스칼라독).
    lbWrData := io.wdata
    // 존재 비트 뷰(RouteJudge.bankPresent)는 같은 사이클 같은 조건에서
    // 정확히 한 번 구동된다 — view_sync 구동 규약. 규약은 그대로이고
    // '성공'의 정의만 좁아졌다: 거절된 기입은 표도 뷰도 움직이지 않는다.
    io.bankWr.valid  := True
    io.bankWr.lbid   := wordIdx
    io.bankWr.mapped := io.wdata(ENTRY_V_BIT)
  }

  // ═══ LNID 소유 표 기입 — CHECK 1사이클 뒤 커밋/거절 ══════════════════
  val lnidWrite = acceptW && aligned && region === REGION_LNID

  // 수락 시점 래치 — CHECK 사이클의 판단 재료. 워드는 *원문 그대로* 든다
  // (pWord 가 곧 커밋될 엔트리다 — 조립을 두 번 하지 않는다). 정규화가
  // 사라진 자리를 거절이 대신한다: 예약 비트가 서 있으면 CHECK 에서
  // 거절되므로, 커밋되는 pWord 는 언제나 예약 비트 0 이다 (결정 A).
  val pSlot = Reg(UInt(8 bits)) init 0
  val pWord = Reg(Bits(32 bits)) init 0
  when(lnidWrite) {
    busy  := True
    pSlot := wordIdx
    pWord := io.wdata
  }
  val pV      = pWord(ENTRY_V_BIT)
  val pPoint  = pWord(23 downto 16).asUInt
  val pLnid   = pWord(15 downto 0).asUInt
  val pRsvBad = (pWord & B(LNID_RSV_MASK, 32 bits)) =/= 0

  // 서로소 검사용 역방향 표 읽기 — 수락 사이클에 새 LNID 로 발사한다.
  val revChkAddr    = io.wdata(15 downto 0).asUInt
  val revChk        = revMem.readSync(revChkAddr, memRdEn)
  val revChkPresent = revChk(0)

  // 기존 슬롯 내용 (fwdRd 가 같은 수락 사이클에 읽혀 CHECK 에서 유효하다).
  val oldV    = fwdRd(ENTRY_V_BIT)
  val oldLnid = fwdRd(15 downto 0).asUInt

  // 거절 원인별 발화선. faultBadWrite 는 *넷*을 한 비트로 접는다 —
  // 폴딩 규정 (§5.6 이 요구하는 「신호마다 명시」):
  //
  //   ① 용량 밖 슬롯 · ② 없는 지점 등록 · ③ 점유 슬롯 재기입
  //   ④ 엔트리 예약 비트 비0 (신설 — 결정 A. LNID·LBID 두 축 모두)
  //
  // 접는 근거: 원인 넷이 전부 「거절된 구성 기입」이고 수리 주체가 하나다
  // (드라이버). 원인을 가르는 비트가 늘어도 드라이버가 하는 일은 같다 —
  // 자기가 방금 쓴 워드를 고쳐 다시 쓰는 것뿐이다.
  //
  // SEC-7 (ii)(판정 이후 구별 불가능) 은닉 채널 논증은 여기 걸리지 않는다:
  // 구성 표면의 기입자는 호스트 자신이므로, 자기가 방금 써 넣은 값이 fault
  // 로 되돌아오는 것은 신뢰 경계를 넘지 않는다. SEC-7 이 막는 것은 *다른
  // 주체*가 넣은 비트가 관측면으로 새는 일이다.
  //
  // D2(서로소 위반)와는 접지 않는다 — 그쪽은 §1.4.5 가 이름한 별도 규범이고
  // 수리도 「다른 소유자를 먼저 해제」라는 다른 동작이다.
  val chkDupOwn = False
  val chkBadWr  = False

  when(busy) {
    busy := False
    // 용량 밖 슬롯 — 표에는 실리고 뷰에는 못 실리는 이름을 만들지 않는다.
    val slotOutOfCap = if (capSlots >= TBL_ENTRIES) False else pSlot >= capSlots
    // 예약 비트 검사는 V 갈래보다 앞선다 — 엔트리 *워드 전체*에 대한 규범이라
    // 등록(V=1)이든 해제(V=0)든 똑같이 적용된다 (결정 A). 관대함을 남기지
    // 않는 것이 목적이므로 「해제니까 봐준다」는 예외를 두지 않는다.
    when(pRsvBad) {
      chkBadWr := True // ④ 예약 비트 비0 — 표·역방향 표·뷰 어느 것도 안 움직인다
    }.elsewhen(pV) {
      // 없는 지점에 등록하면 그 LNID 는 뷰에는 있고 배달자는 없는 —
      // 조용히 사라지는 이름이 된다. 그래서 기입 시점에 크게 거절한다.
      val pointBad = pPoint >= cfg.nPoints
      when(slotOutOfCap || oldV || pointBad) {
        chkBadWr := True // ①②③ 거절 — 점유 슬롯은 먼저 해제(V=0 기입)하고 다시
      }.elsewhen(revChkPresent) {
        chkDupOwn := True // D2 — 서로소 위반. 쓰기 무효 + loud fault (§1.4.5)
      }.otherwise {
        // 커밋 — 표(fwdMem)·역방향 표(revMem)·RouteJudge 뷰(viewWr)가
        // *같은 사이클, 같은 조건*에서만 함께 갱신된다. 기입 성공 외에
        // 뷰를 움직이는 경로가 없다 (view_sync 구동 규약).
        fwdWrEn   := True
        fwdWrAddr := pSlot
        fwdWrData := pWord // 원문 그대로 — V·지점·LNID (예약 비트는 이미 0)
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
  // 두 축의 거절이 같은 sticky 비트로 접힌다 (위 폴딩 규정). 두 발화선이
  // 같은 사이클에 서는 일은 구조적으로 없다 — chkBadWr 는 busy 사이클에
  // 서고 busy 사이클에는 ready 가 낮아 lbidWrite 자체가 성립하지 않는다.
  // 그래도 sticky 는 OR 라 겹쳐도 유실이 없다 (§3.8 합성 가능한 상태 비트).
  io.faultDupOwner := StickyFault(chkDupOwn, io.faultClearDup)
  io.faultBadWrite := StickyFault(chkBadWr || chkLbBadWr, io.faultClearBad)

  // 구성 쓰기와 실행(토큰 흐름)의 순서 자체는 호스트 의무다 (§3.10 호스트
  // ABI 경계) — 여기서는 커밋의 원자성(단일 워드, §3.7.1)과 뷰 동시 구동만
  // 보장한다.
}
