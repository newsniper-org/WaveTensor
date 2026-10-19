// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// OwnershipTable — 페이지 소유권 표 (정본 부록 E.7 · §3.4.1 · §3.7)
//
// 구성 표면 `0x200`~`0x2FF` (256 B) 의 조회 쌍 + 전이 쌍. 페이지 → {호스트
// 소유 | 장치 소유} 의 상태 기계 그 자체다. §3.4.1 규약 4요소 중 이 모듈이
// 드는 것은 앞의 둘 — 단위(페이지)·두 상태, 그리고 전이 경로(명시적 MMIO
// 기입만)다. 위반 판정(4요소의 넷째)은 HiuPipeline 승인 단계 소관이고,
// 비우기 의무(셋째)는 넘기는 쪽 — 호스트 소프트웨어 — 의 ABI 의무다.
//
// ## 레지스터 배치 (E.7 — 조회 쌍 + 전이 쌍. 전이 명령은 *오프셋*에 실린다)
//
//   0x200  OWN_IDX     RW  조회 색인 — 상태를 *읽을* 페이지 프레임 32b.
//                          읽기는 기입값 반환. **조회 대상만 정한다** — 전이 불참.
//   0x204  OWN_STATUS  RO  [0] 1 = OWN_IDX 페이지가 장치 소유 · [31:1] 예약 0.
//                          RO 오프셋의 쓰기는 **거절 + loud fault** (E.1.1).
//   0x208  OWN_SET     WO  [31:0] 대상 프레임 32b — 호스트 → 장치 이양.
//   0x20C  OWN_CLR     WO  [31:0] 대상 프레임 32b — 장치 → 호스트 회수.
//                          WO 오프셋의 읽기는 0 반환 · fault 없음 (E.1.1).
//   그 밖  예약 오프셋 — 쓰기 무시 · 읽기 0 (§3.7. *오프셋* 정책이다 —
//          명령 인코딩의 예약 *필드*와 정반대. 디코더로 옮겨 적지 말 것). 단 비정렬 *쓰기*는 어디서든 거절 + loud (판정 T2 — 3.7 sub-word 규범 끝줄).
//
// E.1.2 가 이 넷의 주소 비트를 읽는 방식: `addr[3]` 이 *조회 쌍과 전이 쌍*을,
// `addr[2]` 가 쌍 안의 방향을 가른다 — 두 비트 전수 디코드라 빈 인코딩이
// 없고, 읽기 응답이 있는 워드와 없는 워드가 주소 비트 하나로 갈린다
// (`addr[3]` = 0 이면 RW/RO · 1 이면 WO). 앞판 OWN_DATA `[31]` 이 나르던
// 전이 명령을 이제 `addr[2]` 가 나른다.
//
// ## 전이 인코딩 — 명령을 데이터가 아니라 오프셋이 나른다
//
// E.7 의 규범적 알맹이는 「전이는 데이터 레지스터에 대한 *한 번의 쓰기*로
// 완결된다」와 그 이유(색인–데이터 중간 상태의 비관측)다. 이 배치는 그것을
// 그대로 지킨다 — 전이는 여전히 한 워드 쓰기 한 번이고 중간 상태가 없다.
// 바뀐 것은 *어디에 명령을 싣는가* 하나이며, 대가로 세 가지를 얻는다:
//
//   1. *기계 안에 주소 용량이 하나만 남는다.* 앞판은 전이 워드에 방향 비트
//      하나를 실어 프레임을 31b 로 좁혔고, 같은 기계의 변환 항목은 32b 를
//      통째로 줬다. 그 어긋남은 「유효하게 사상되지만 결코 소유될 수 없는
//      페이지 부류」를 만들었다 — §3.4.1 이 「상태는 둘뿐」이라 적은 자리에
//      들어앉는 제3 상태다. 이제 PA_W = 44 · FRAME_W = 32 가 소유권 표와
//      변환 항목 양쪽에서 같다.
//   2. *기입 시점 별칭이라는 조용한 실패가 구조적으로 사라진다.* 앞판의
//      기입 경로는 프레임을 하위 31비트로 잘라 받았다. 드라이버가
//      `(1<<31)|F` 를 순진하게 조립하면 F 의 최상위 비트가 방향 비트와
//      겹쳐 *다른 페이지가 조용히 장치 소유로 넘어갔다.* §3.7.1 이 사상표에
//      세운 「기입 시점의 거절」의 대응물을 거기서는 세울 수 없었다 —
//      표현 불가 값이 도착 전에 이미 잘려 있어 거절할 대상 자체가 관측되지
//      않는다. §5.5 는 조용한 실패를 보안 문제로 승격했다.
//   3. *좁힘은 되돌릴 수 없다.* 좁힌 주소 폭은 호스트 SDK 의 DMA 주소 타입이
//      되고 stable 이후 다시 넓힐 수 없다. 위험은 설치 메모리 양이 아니라
//      *플랫폼의 희소한 물리 주소 배치*에 있다 — 대형 서버·메모리 확장
//      상호연결은 실장량이 적어도 DRAM 창을 높은 PA 에 얹는다. 정본의 척추
//      문장은 「추상은 환경을 새게 하지 않는다」이고, 호스트의 물리 주소
//      배치가 장치의 표현 능력에 새는 형태를 비용 0 으로 피할 수 있다면
//      피한다.
//
// 비용은 레지스터 두 워드다. 구역에 여유가 압도적이고 (256 B 중 4 워드 사용),
// §3.7 예약 정책이 「레지스터 추가는 하위 호환 형태」임을 이미 규범으로
// 보장한다.
//
//   ⚠️ 마이그레이션 — 앞판 드라이버는 `0x204` 에 `[31]`+프레임을 썼다. 그
//   오프셋은 이제 RO 다. 조용히 무시하면 드라이버는 자기 이양이 먹혔다고
//   믿는다 ⇒ E.1.1 「RO 오프셋의 쓰기는 거절 + loud fault」가 이 자리에서
//   마이그레이션 안전망 노릇을 겸한다 (faultBadWrite → FAULT_STATUS `[6]`).
//
//   ⚠️ 이 파일이 닫지 *않는* 것 — 「비소유 접근은 loud fault」(§3.4.1 4항 ·
//   HIU-10)의 후-formal. 선-formal 이 증명한 것은 모델 위의 배타성이고, 값
//   차단·sticky 원천은 이 표가 아니라 소비쪽(HiuPipeline)이, `0xF80` `[19]` 배치는 조립(Wt64Top)이 진다
//   (E.7 함정 · B.5 · §3.9 행). 이 개정이 없앤 것은 *전이 인코딩이 만든* 조용한 실패이지 접근 시점의
//   loud 성이 아니다 — 두 명제는 별개이고, 후자는 후-formal 의 fault 축이
//   답한다. *그 축은 3.10 RTL 파도 W1(2026-10-12)이 세웠다* — HiuMask 하네스가 원인별
//   값 차단 · sticky 상승 · 유지를, 조립 하네스가 [19] 배치 · 0xF84 해제 라우팅을 재고 둘의
//   합성은 서술이다 (B.5 해소 행 · lint_postformal _PARTIAL). 미측정은 통과가 아니다.
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
// 색인 + 태그가 프레임 *전폭*을 덮으므로 (idxW + tagW = FRAME_W) 조회에도
// 기입에도 「표가 발언권을 갖지 못하는 프레임 구간」이 없다. 앞판이 들고
// 있던 상위 0 판정(qHighZero·idxHigh0)은 그 구간의 관측형이었고, 구간이
// 사라지면서 배선도 함께 사라졌다.
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
// Platform 모델의 가드는 W1 까지가 HiuPipeline.scala 머리, W6 의 여섯은 이 파일 끝에 정식 줄이 있다
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
//     (OWN_SET 기입 수락)이 여기지만, 그 전에 비우는 것은 넘기는 쪽의
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
  /** 조회 색인 레지스터 오프셋 (4 KiB 블록 안). RW. */
  val OFF_IDX     = 0x200
  /** 상태 읽기 레지스터 오프셋. RO — 쓰기는 거절 + loud fault (E.1.1). */
  val OFF_STATUS  = 0x204
  /** 이양(호스트 → 장치) 전이 레지스터 오프셋. WO — 워드 전체가 프레임. */
  val OFF_SET     = 0x208
  /** 회수(장치 → 호스트) 전이 레지스터 오프셋. WO — 워드 전체가 프레임. */
  val OFF_CLR     = 0x20C
  /** OWN_STATUS 읽기의 상태 비트 — 1 = 장치 소유. */
  val STATE_DEV_BIT = 0
}

/** 페이지 소유권 표 — E.7 조회 쌍 + 전이 쌍과 승인 조회의 반대편.
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
  private val tagW   = frameW - idxW

  require(ownEntries >= 2 && isPow2(ownEntries), "소유권 표 슬롯 수는 2 이상 2의 거듭제곱")
  require(tagW >= 1, "색인이 프레임 폭을 다 먹으면 태그가 없다 — 슬롯 수 과대")
  // ── 두 표면의 폭이 같다 — E.7 5항 · E.2 4항이 규범으로 세운 *관계* ──
  //
  // 규범은 「프레임은 n 비트다」가 아니라 「소유권 전이 워드와 변환 항목의
  // 물리 프레임이 *같은 폭*을 쓴다」이다 (E.2 해설: 값은 재구현이 정하고
  // 동결은 호스트 ABI 합의의 대상 · 관계는 값과 무관하게 참이어야 하므로
  // 규범). 이 파일은 그 관계를 *구조로* 지킨다 — 폭을 자기가 정하지 않고
  // XlateStore.FRAME_W 하나에서 받는다. 두 값이 따로 움직일 자리가 없다.
  //
  // 아래 require 는 관계가 아니라 *현행 배정과의 정합*을 잰다. E.1.2 가 지금
  // OWN_SET/OWN_CLR 에 `[31:0]` 을 주었으므로 (= 예약 비트 없는 전폭 프레임)
  // frameW 가 32 를 벗어나면 워드 안에 예약 비트가 생기거나(엄격 정책 필요)
  // 프레임이 워드를 넘친다(상위 절반 워드 필요 — E.1.2 가 `0xE0C` 선례로
  // 열어 둔 축). 어느 쪽이든 E.7 워드 배치의 재설계이지 이 파일의 지역
  // 수정이 아니다. 조용히 자르지 말고 여기서 크게 멈춘다.
  require(frameW == 32,
    s"FRAME_W(=PA_W-PAGE_W)=$frameW — E.1.2 의 OWN_SET/OWN_CLR `[31:0]` 배정과 어긋난다. " +
    "E.7 워드 배치의 재설계가 선행돼야 한다 (예약 비트 엄격 또는 상위 절반 워드 증설)")

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
      *  - **정의역** — frame 전폭(FRAME_W)이 조회 공간이다. 표가 발언권을
      *    갖지 못하는 프레임 구간은 없다 (머리말 저장 구조 절).
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
    /** 거절된 구성 기입 — RO 오프셋(OWN_STATUS)의 쓰기 (E.1.1) · 수락된 비정렬 쓰기 (판정 T2). 호스트 대면
      * 표면에서 FAULT_STATUS `[6]`「구성 — 거절된 구성 기입」으로 합류한다
      * (CompletionUnit.faultBadWrite 와 같은 부류·같은 폴딩 지점). 해제
      * 표면은 MMIO `0xF84[6]` 이고 전용 IO 선은 새로 만들지 않는다. */
    val faultBadWrite = out port Bool()
    val faultClearBadWrite = in port Bool()
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
  // 색인 + 태그가 프레임 전폭이다 — 별도의 상위 0 판정이 없다.
  val qIdx    = io.query.frame(idxW - 1 downto 0)
  val qTag    = io.query.frame(frameW - 1 downto idxW).asBits
  io.query.devOwned := validBits(qIdx) && tagVec(qIdx) === qTag

  // ═══ MMIO 접근 수락 (MmioConfig 와 같은 규약 — 동시 제시면 쓰기 우선) ═
  val aligned = io.addr(1 downto 0) === 0 // 비정렬 *쓰기*는 거절 + loud (T2 — 아래 faultBadWrite) · 비정렬 읽기는 0 (§3.7)
  val region  = io.addr(11 downto 8) === REGION
  val word    = io.addr(7 downto 2)       // 0 = IDX · 1 = STATUS · 2 = SET · 3 = CLR

  val WORD_IDX    = (OFF_IDX    >> 2) & 0x3F
  val WORD_STATUS = (OFF_STATUS >> 2) & 0x3F
  val WORD_SET    = (OFF_SET    >> 2) & 0x3F
  val WORD_CLR    = (OFF_CLR    >> 2) & 0x3F

  val acceptW = io.ready && io.wstrobe
  val acceptR = io.ready && !io.wstrobe && io.rstrobe
  val selW    = acceptW && aligned && region

  // ── 전이 관문 — *오프셋이* 방향이다. 두 신호는 구조적으로 배타적이다
  //    (같은 주소가 두 워드일 수 없다) — 한 쓰기가 두 방향을 뜻할 표면이
  //    없다는 것이 E.7 「한 번의 쓰기로 완결」의 이 배치에서의 형태다.
  val idxWr    = selW && word === WORD_IDX
  val statusWr = selW && word === WORD_STATUS // RO 오프셋 쓰기 — 거절 + loud
  val setWr    = selW && word === WORD_SET    // 이양 (호스트 → 장치)
  val clrWr    = selW && word === WORD_CLR    // 회수 (장치 → 호스트)

  // ═══ OWN_IDX — 조회 색인 레지스터 (조회 대상만 정한다 — 전이 불참) ═══
  // 전폭 32b = frameW 다. 조회 공간과 같은 해석이라 해석 구간이 갈리지 않는다.
  val idxReg = Reg(Bits(32 bits)) init 0
  when(idxWr) { idxReg := io.wdata }

  // ═══ 공용 태그 조회 자리 — 전이 검사(쓰기 사이클) / 상태 읽기(읽기 사이클)
  // 한 사이클에 쓰기와 읽기는 동시 수락되지 않으므로 (쓰기 우선) 주소를
  // 먹싱해도 두 용도가 경합하지 않는다.
  val wFrame  = io.wdata.asUInt                        // 워드 전체가 프레임
  val wIdx    = wFrame(idxW - 1 downto 0)
  val wTag    = wFrame(frameW - 1 downto idxW).asBits
  val idxFrm  = idxReg.asUInt
  val chkAddr = UInt(idxW bits)
  chkAddr := idxFrm(idxW - 1 downto 0)
  when(io.wstrobe) { chkAddr := wIdx }
  val chkTag = tagVec(chkAddr)

  // ═══ OWN_STATUS 읽기 — OWN_IDX 페이지의 상태 (수락 사이클 표 상태 스냅숏) ═
  val idxTag = idxFrm(frameW - 1 downto idxW).asBits
  val devStateAtIdx = validBits(chkAddr) && chkTag === idxTag

  // rdSel — 0 = 예약 오프셋 · WO 오프셋(읽기 0, fault 없음) · 1 = IDX · 2 = STATUS
  val rdSel  = Reg(UInt(2 bits)) init 0
  val rState = Reg(Bool()) init False
  io.rvalid := RegNext(acceptR, False)
  when(acceptR) {
    rdSel  := 0
    rState := devStateAtIdx
    when(aligned && region) {
      when(word === WORD_IDX)    { rdSel := 1 }
      when(word === WORD_STATUS) { rdSel := 2 }
      // WORD_SET · WORD_CLR — WO. 읽기는 0 을 돌려주고 fault 를 내지 않는다
      // (E.1.1: 읽기는 장치가 *돌려주는* 쪽이라 관대함이 하위 호환을 만든다).
    }
  }
  io.rdata := 0 // 예약 오프셋 — 읽기 0 (§3.7)
  switch(rdSel) {
    is(1) { io.rdata := idxReg }
    is(2) { io.rdata(STATE_DEV_BIT) := rState }
  }

  // ═══ 전이 — 한 번의 쓰기로 완결 (E.7 원자성) ═════════════════════════
  // 커밋 = 유효 비트 + 태그가 같은 에지에 갱신되는 단일 기입. 중간 상태 없음.
  val collide  = False
  val slotBusy = validBits(wIdx)          // 슬롯 점유 여부
  val slotMine = chkTag === wTag          // 점유자가 = 이 워드의 페이지인가

  when(setWr) {
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
  }
  when(clrWr) {
    // 호스트로 회수 (장치 → 호스트)
    when(slotBusy && slotMine) {
      validBits(wIdx) := False
    }
    // 그 밖 — 이미 호스트 소유 (표에 없음). 무연산.
  }

  // ═══ sticky fault — 세운다 / 명시적 해제 외엔 내리지 않는다 (거절 둘: RO 쓰기 · 비정렬 쓰기 — 둘 다 전이 없음, selW 가 aligned 를 요구) ═══
  io.faultCollide  := StickyFault(collide, io.faultClearCollide)
  io.faultBadWrite := StickyFault(statusWr || (acceptW && !aligned), io.faultClearBadWrite)

  // 전이 기입과 진행 중 요청(승인 조회)의 순서 규율은 호스트 ABI 다
  // (§3.7 드레인 · §3.10) — 여기서는 커밋의 원자성(단일 에지)과 조회
  // 스냅숏의 일관성만 보장한다 (io.query 주석의 계약).
}

// ── GUARD-MAP — OWN_SET 의 거절 · FAULT_STATUS [7] (Platform.tla 확장 — 3.10 v1.0 묶음 RTL 파도 W6 · e-defined E.7 6항) ──
// GUARD-MAP: Platform.set_reject_inert -> setWr 의 충돌 갈래 `.elsewhen(!slotMine) { collide := True }` 는 validBits · tagVec 에 어떤 대입도 하지 않는다 — 대상 프레임은 호스트 소유로 남고 점유 슬롯(같은 색인 · 다른 태그)의 유효 · 태그도 그대로다(축출 배선 없음). 이양 커밋은 `!slotBusy` 갈래 하나뿐이다
// GUARD-MAP: Platform.set_reject_loud -> io.faultCollide := StickyFault(collide, io.faultClearCollide) — 충돌 거절 사이클의 collide 가 sticky 를 세우고 조립이 own.io.faultCollide → io.fault.ownCollide → FAULT_STATUS [7](Fault.B_OWN_COLLIDE) 로 낸다
// GUARD-MAP: Platform.set_reject_floor -> collide 는 slotBusy = validBits(wIdx) 를 전건으로 한다 — 장치 소유 페이지가 하나도 없으면(validBits = 0) 어느 OWN_SET 도 거절되지 않고 `!slotBusy` 커밋 갈래로 간다
// GUARD-MAP: Platform.set_owned_noop -> collide 는 ¬slotMine(chkTag ≠ wTag — 쓰기 사이클 chkAddr = wIdx)을 요구한다 — slotBusy ∧ slotMine(이미 장치 소유)은 대입도 collide 도 없는 무연산 갈래다
// GUARD-MAP: Platform.clr_no_reject -> clrWr 갈래에는 collide 대입이 없다 — slotBusy ∧ slotMine 이면 validBits(wIdx) := False, 아니면 무연산. 비정렬 OWN_CLR 의 거절 + [6] 은 형상 · 점유 축이 아니다(faultBadWrite — MmioPage.unaligned_rejected)
// GUARD-MAP: Platform.seven_reject_only -> faultCollide 의 set 원천은 collide 하나이고 collide 는 기본 False · setWr ∧ slotBusy ∧ ¬slotMine 에서만 True — 커밋(!slotBusy) · 무연산(slotMine) · OWN_CLR · 다른 오프셋 · 읽기는 [7] 을 세우지 않는다(상승 건전성)
