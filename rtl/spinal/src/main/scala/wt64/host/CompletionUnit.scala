// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// CompletionUnit — 완료 큐 · 완료 통지 · 드레인 관측면
//                  (정본 부록 E.5 · E.6 · E.11, §3.7 드레인 규약, §2.6 배압)
//
// 이 모듈이 담는 것은 호스트-장치 경계의 완료 방향 표면 셋이다:
//
//   1. 완료 큐 (E.5)   — 링. 생산자는 장치(tail 전진), 소비자는 호스트(head
//      전진). 크기는 2의 거듭제곱 (나머지 연산이 마스크가 된다). head == tail
//      은 *빈 링*, 가득 참은 (tail+1) mod size == head — 한 칸을 비워 두
//      상태를 구별한다. 구별하지 못하는 인코딩은 조용히 틀린다 (E.5 문면).
//      완료 항목(디스크립터)은 32 B 고정이다 — 가변 길이 파싱 상태 기계를
//      만들지 않기 위해서다 (E.5 4항).
//   2. 완료 통지 (E.6) — 통지는 *완료 링에 항목을 넣는 것*이고 그것이 유일한
//      통지 수단이다. 인터럽트는 선택적 가속이며 마스크로 끌 수 있다 — 끄면
//      호스트가 링을 폴링하고 기능이 줄지 않는다. 인터럽트 상태는 sticky 이며
//      명시적 해제까지 유지된다.
//   3. 드레인 관측면 (E.11) — §3.7 드레인 정의역 여섯 항의 진행 중 개수 +
//      자기 완료 큐 점유, 그리고 「전부 0」 비트. 읽기 전용. 이 표면은 새
//      상태를 만들지 않는다 — 각 유닛이 이미 가진 점유 상태의 집계 배선일
//      뿐이다 (여섯 카운트의 배선은 top 몫). 기계에 드레인 *모드*는 없다
//      (§3.7 — 드레인의 수행은 호스트 의무다). 관측 부류는 상태 표면이다
//      (§5.8 닫힌 4부류 안).
//
// ## 오버플로 처분 — E.5 그대로 (배압 규약 정합)
//
// 완료 링이 가득이면 장치는 *배압으로 정지*한다 (§2.6) — comp.ready 강하가
// 그 배압이다. ready 가 낮다고 알린 사이클에 온 valid(= 가득인 링에 밀어
// 넣기)가 E.5 의 오버플로이며 처분은 loud sticky fault 다 (§3.8 「오버플로」
// 항 · SharedUnit/FabricMerge 의 같은 배압 규약). 그 갈래는 어떤 링 상태에도
// 쓰지 않는다 — 밀어 넣어진 항목은 저장에 닿지 않는다 (FAB-10 과 동형).
// 이 fault 는 오버플로 전용이며 다른 신호와 폴딩하지 않는다 (§5.6 — 폴딩
// 여부는 신호마다 명시).
//
// ## FAB-6 앵커 — 이 모듈이 호스트 의무의 장치 쪽 실물 표면이다
//
// E.6 4항 「호스트는 완료 링을 결국 비운다」는 장치 규범이 아니라 호스트 ABI
// 의무다 (§3.10). FAB-6 진행성의 조건부 의무 사슬을 하류로 따라가면 마지막에
// 기계 밖 — 완료 링을 읽는 호스트 — 이 나오고, 무조건 의무가 놓일 자리는
// 그곳 하나다 (E.6 해설). 그 의무를 선-formal 은 Fabric.tla 의 bp_relief
// 공정성 가정으로 걸어 검증했고, 정식 매핑 줄(ENV)은 fabric/FabricMerge.scala
// 머리가 소유한다 — 가드당 저장소 전체 정확히 1줄이므로 여기 다시 적지
// 않는다 (MmioConfig 의 Route 가드 서술 선례). 접점만 남긴다:
//
//   · Fabric.bp_relief (FabricMerge 의 ENV 줄) — 그 줄이 가리키는 호스트
//     의무 「완료 링을 결국 비운다」의 장치 쪽 실물이 이 모듈의 head 배수
//     표면(CQ_HEAD 기입 + 엔트리 창 읽기)이다. RTL 검사가 아니라 표면 제공
//     이다 — 장치는 이행을 강제할 수단을 두지 않는다 (E.6: 타임아웃은
//     조용한 실패의 다른 이름이다, E.3 과 같은 처분).
//
// GUARD-MAP 줄 없음 — 이 모듈 소유의 선-formal 모델은 없다 (완료 큐·통지는
// Fabric.tla 가 bp_relief 가정으로, 배압 처분은 SharedUnit.tla 가 같은 규약
// 으로 이미 다뤘다). 후속 모델이 서면 그때 정식 줄이 이 파일로 온다.
//
// ## MMIO 자리 — E.1 의 0x300~0x3FF (명령/완료 큐 · 인터럽트)
//
// 상위 데코더가 0x300 영역을 갈라 이 모듈에 넣는다 — addr 는 영역 안 바이트
// 오프셋 8비트다. 표에 없는 오프셋·비정렬 접근은 예약 *오프셋* 정책이다
// (§3.7 — 쓰기 무시 · 읽기 0. 명령 인코딩의 예약 *필드*와 정반대 정책임에
// 주의 — 그쪽은 0 이 아니면 malformation 이다).
//
// 오프셋 배치는 이 구현이 내리는 잠정 결정이며 호스트 ABI 합의(§3.10)의
// 입력이다 — E.5 가 못박은 것(링 인코딩 · head/tail 의 갱신 주체와 RO/RW ·
// 2^k 크기 · 32 B 디스크립터)만 규범이다:
//
//   0x00 CQ_SIZE       RO  링 크기 (엔트리 수, 2^k)
//   0x04 CQ_HEAD       RW  소비 색인 — *호스트 갱신* (E.5 표의 RW 그대로)
//   0x08 CQ_TAIL       RO  생산 색인 — *장치 갱신* (E.5 표의 RO 그대로)
//   0x10 IRQ_STATUS    RO  [0] sticky 인터럽트 상태 (E.6)
//   0x14 IRQ_MASK      RW  [0] 1 = 마스크. reset 값 1 — 인터럽트는 opt-in
//                          가속이다 (E.6 함정: 인터럽트를 정상 경로의 전제로
//                          두지 말 것. 기본이 폴링이어야 그 함정이 닫힌다)
//   0x18 IRQ_CLEAR     WO  [0] 에 1 기입 = 명시적 해제 (이 외엔 안 내려간다)
//   0x1C FAULT         RO  [0] 오버플로 sticky
//   0x20 FAULT_CLEAR   WO  [0] 에 1 기입 = 명시적 해제
//   0x40~0x5F 엔트리 창 RO  head 가 가리키는 항목의 8워드 (빈 링이면 0)
//   0x60~0x77 드레인 카운트 RO  §3.7 여섯 항 (E.11 — 아래 io.drain 순서)
//   0x78 CQ_OCC        RO  자기 완료 큐 점유 (E.11 집계의 일곱째 관측)
//   0x7C DRAIN_ALLZERO RO  [0] 전부 0 — 여섯 카운트 + 완료 큐 점유
//
// 「전부 0」 비트는 읽기 수락 사이클의 조합 스냅샷 하나가 단일 32비트 읽기로
// 나간다 — 호스트가 여섯(+1) 카운트를 개별로 읽는 동안 상태가 움직이는 찢김을
// 이 비트 하나가 닫는다 (E.11 규범). 완료 큐 점유를 논리합에 넣는 것은 지시된
// 집계이며 보수 방향이다 — 링 배수는 어차피 호스트의 E.6 의무라서 드레인
// 완주를 새로 막지 않는다 (E.11 문면은 여섯이다 — 보고서 model_feedback 참조).
//
// E.5 의 base 레지스터(호스트 메모리 배치)와 명령 큐 방향은 이 착지에 없다 —
// 이 링은 장치 상주이고 명령 경로는 별도 유닛이다 (보고서 observations 참조).

package wt64.host

import spinal.core._
import wt64.StickyFault

/** 지역 상수 — 전부 형상 무관 (INV-T1: 어느 값도 인스턴스 개수의 함수가
  * 아니다. 완료 항목은 불투명 256비트다 — wave 를 포함한 태그 필드를 이
  * 모듈은 해석하지 않는다, §1.4.4).
  */
object CompletionUnit {
  /** 완료 디스크립터 — 32 B 고정 (E.5 4항). */
  val ENTRY_BYTES = 32
  val ENTRY_W     = ENTRY_BYTES * 8
  val ENTRY_WORDS = ENTRY_BYTES / 4
  /** 드레인 카운트 폭 — 고정 상수. 값의 상한은 형상이 정하지만 폭은 형상의
    * 함수가 아니다 (E.10 이 조각 머리 폭에 내린 처분과 같은 논리). */
  val DRAIN_CNT_W = 16

  // MMIO 오프셋 (영역 안 바이트 오프셋 — 배치 근거는 파일 머리)
  val OFF_CQ_SIZE     = 0x00
  val OFF_CQ_HEAD     = 0x04
  val OFF_CQ_TAIL     = 0x08
  val OFF_IRQ_STATUS  = 0x10
  val OFF_IRQ_MASK    = 0x14
  val OFF_IRQ_CLEAR   = 0x18
  val OFF_FAULT       = 0x1C
  val OFF_FAULT_CLEAR = 0x20
  val OFF_WINDOW      = 0x40 // ~0x5F — head 엔트리 8워드
  val OFF_DRAIN       = 0x60 // ~0x77 — 여섯 카운트
  val OFF_CQ_OCC      = 0x78
  val OFF_ALLZERO     = 0x7C
}

/** §3.7 드레인 정의역 여섯 항의 진행 중 개수 — E.11 의 입력면.
  *
  * 각 유닛이 자기 점유 상태를 노출하고 top 이 여기로 배선한다. 이 번들은
  * 새 상태가 아니라 이미 있는 점유의 집계 어휘다 (E.11 해설).
  */
case class DrainCounts() extends Bundle {
  import CompletionUnit.DRAIN_CNT_W
  val pipe     = UInt(DRAIN_CNT_W bits) // ① 요청 파이프라인 안의 요청 (§3.2 여섯 단계)
  val pending  = UInt(DRAIN_CNT_W bits) // ② 공유 유닛의 보류 자원 (§2.2)
  val output   = UInt(DRAIN_CNT_W bits) // ③ 생산자 출력 자원·병합 중 전송 (§2.6)
  val ownSlots = UInt(DRAIN_CNT_W bits) // ④ 소유 구간 진행 중 결과 슬롯 (§2.4)
  val contexts = UInt(DRAIN_CNT_W bits) // ⑤ 활성 재조립 문맥 — 미완 포함 (§4.3)
  val tokens   = UInt(DRAIN_CNT_W bits) // ⑥ 미완료 순서 토큰 (§4.4)
}

/** 완료 큐 · 통지 · 드레인 관측면.
  *
  * 버스 프로토콜은 상위 몫이다 (MmioConfig 선례) — 소박한 동기 인터페이스:
  * ready 는 상시 높다 (다사이클 연산이 없다). 읽기는 수락 다음 사이클에
  * rdata 유효 (rvalid 1펄스). 쓰기는 1사이클 커밋.
  *
  * @param cqDepth 완료 링 깊이 (엔트리 수). 2의 거듭제곱 (E.5 — 나머지가
  *                마스크가 된다). 한 칸을 비우는 인코딩이라 수용량은
  *                cqDepth-1 이다. Wt64Config 승격 후보 — 보고서 promote 의
  *                diff 제안 참조 (그때까지 생성자 파라미터로 둔다).
  */
class CompletionUnit(val cqDepth: Int = 8) extends Component {
  import CompletionUnit._

  require(cqDepth >= 2 && isPow2(cqDepth),
    "링 크기는 2의 거듭제곱 >= 2 — E.5 (한 칸을 비워 빈/가득을 구별하므로 1이면 수용량 0)")

  private val ptrW = log2Up(cqDepth)

  val io = new Bundle {
    // ── MMIO (0x300 영역 안 바이트 오프셋 — 상위 데코더가 가른다) ───────
    val addr    = in  port UInt(8 bits)
    val wstrobe = in  port Bool()
    val wdata   = in  port Bits(32 bits)
    val rstrobe = in  port Bool()
    val rdata   = out port Bits(32 bits)
    val rvalid  = out port Bool()
    val ready   = out port Bool()

    // ── 완료 항목 수락 — push 규약 (§2.6): 상류는 ready 를 보고 정지한다.
    //    ready 가 낮은 사이클의 valid 는 가득인 링에 밀어 넣기 = E.5 오버플로.
    //    항목 내용은 불투명하다 — 이 모듈은 한 비트도 해석하지 않는다.
    val comp = new Bundle {
      val valid   = in  port Bool()
      val payload = in  port Bits(ENTRY_W bits)
      val ready   = out port Bool()
    }

    // ── 완료 통지 — 인터럽트 선 (E.6: 선택적 가속. 통지 자체는 링 항목이다)
    val irq = out port Bool()

    // ── E.11 여섯 카운트 (top 배선 — 각 유닛의 점유 관측 출력에서 온다) ──
    val drain = in port DrainCounts()

    // ── loud fault 관측 — 합성 가능한 sticky 상태 비트 (§3.8 오버플로).
    //    해제는 MMIO FAULT_CLEAR 명시 기입뿐이다 — 이 유닛은 호스트 대면
    //    표면이라 해제 권한도 그 표면에 있다 (배압 해제가 fault 를 함께
    //    지우는 W1C 동반 클리어 금지 — §2.6 함정).
    val faultOverflow = out port Bool()
  }

  io.ready := True // 다사이클 수락이 없다 — 예약 정책 포함 모든 접근이 1사이클

  // ═══ 완료 링 — E.5 인코딩 그대로 ════════════════════════════════════
  // 갱신 주체는 표 그대로: tail 은 장치(push), head 는 호스트(MMIO 기입) —
  // 서로 다른 레지스터라 경합 표면이 없다. head 는 기입 워드 전폭을 마스크로
  // 정규화해 든다 (MmioConfig 의 엔트리 마스크 선례 — 정책이 상수 한 곳에
  // 보인다). 마스크가 곧 mod size 다 (E.5 1항 — 2^k 크기의 이유). 정규화로
  // 0 이 되는 상위 비트는 예약 비트의 관대 정책과 같다: 쓰기 무시 · 읽기 0.
  val headReg = Reg(Bits(32 bits)) init 0
  val head    = headReg(ptrW - 1 downto 0).asUInt
  val tail    = RegInit(U(0, ptrW bits))
  val ring = Mem(Bits(ENTRY_W bits), cqDepth)

  val empty = head === tail                // E.5 2항 — 빈 링
  val full  = (tail + 1) === head          // E.5 2항 — 가득 (한 칸 비움)
  val occ   = tail - head                  // 점유 — 감산이 폭으로 wrap (<= cqDepth-1)

  // 배압: 받을 수 없음이 상류에 보인다 (§2.6 — 배압은 오류가 아니다).
  io.comp.ready := !full

  // 수락 = 통지 (E.6 1항 — 링에 항목을 넣는 것이 통지다).
  val doPush = io.comp.valid && !full
  when(doPush) { tail := tail + 1 }
  ring.write(tail, io.comp.payload, doPush)

  // 가득인 링에 밀어 넣기 — E.5 오버플로. loud sticky, 링 상태 불변
  // (이 갈래는 head·tail·ring 어디에도 쓰지 않는다 — FAB-10 동형).
  val shove = io.comp.valid && full

  // ═══ MMIO 접근 수락 ═════════════════════════════════════════════════
  val aligned = io.addr(1 downto 0) === 0 // 비정렬 = 예약 오프셋 정책 (§3.7)
  val acceptW = io.wstrobe                 // 동시 제시면 쓰기 우선 (MmioConfig 선례)
  val acceptR = !io.wstrobe && io.rstrobe

  // ═══ 쓰기 — 1사이클 커밋. 표에 없는 오프셋은 무시 ═══════════════════
  val doWr = acceptW && aligned
  val irqClrPulse = doWr && io.addr === OFF_IRQ_CLEAR   && io.wdata(0)
  val fltClrPulse = doWr && io.addr === OFF_FAULT_CLEAR && io.wdata(0)

  // 인터럽트 마스크 — reset 1 (끔). 인터럽트는 opt-in 가속이다 (E.6 함정 —
  // 켜져 있어야 도는 설계는 인터럽트 지원 호스트를 전제한다). 정의 비트는
  // [0] 하나 — 나머지는 마스크 정규화로 0 (쓰기 무시 · 읽기 0).
  val irqMaskReg = Reg(Bits(32 bits)) init 1
  val irqMask    = irqMaskReg(0)

  when(doWr) {
    switch(io.addr) {
      // head 는 호스트가 소비한 만큼 전진시키는 값이다 (E.5 표 — RW).
      // 마스크 밖 비트는 버린다 (2^k 크기 — 나머지 연산이 마스크다). 값의
      // 적법성(전진이 tail 을 넘지 않음)은 호스트 ABI 의무다 — 장치는 강제
      // 수단을 두지 않는다 (E.6 — 타임아웃은 조용한 실패의 다른 이름).
      is(OFF_CQ_HEAD)  { headReg := io.wdata & B(cqDepth - 1, 32 bits) }
      is(OFF_IRQ_MASK) { irqMaskReg := io.wdata & B(1, 32 bits) }
    }
  }

  // ═══ 통지 상태 — sticky, 명시적 해제까지 유지 (E.6 3항) ═════════════
  // set 원천은 항목 삽입(doPush) 하나다 — 통지가 곧 삽입이라는 E.6 1항의
  // 상태화. 해제와 삽입이 같은 사이클이면 삽입이 이긴다 (StickyFault 규약 —
  // 해제로 통지를 삼키는 창이 없다).
  val irqSticky = StickyFault(set = doPush, clear = irqClrPulse)
  io.irq := irqSticky && !irqMask

  // ═══ 오버플로 fault — 세운다 / 명시적 해제 외엔 내리지 않는다 ═══════
  val faultOv = StickyFault(set = shove, clear = fltClrPulse)
  io.faultOverflow := faultOv

  // ═══ E.11 집계 — 조합. 새 상태 없음 (해설 문면 그대로) ═══════════════
  val cntVec = Vec(io.drain.pipe, io.drain.pending, io.drain.output,
                   io.drain.ownSlots, io.drain.contexts, io.drain.tokens)
  // 「전부 0」 — 여섯 카운트 + 자기 완료 큐 점유의 단일 비트 스냅샷.
  val allZero = cntVec.map(_ === 0).reduce(_ && _) && occ === 0

  // ═══ 읽기 — 수락 다음 사이클 rdata (예약 오프셋은 0 — §3.7) ═════════
  // 레지스터·카운트 읽기는 수락 사이클의 조합값을 rdataReg 에 스냅한다 —
  // ALLZERO 가 단일 읽기 원자 스냅샷이 되는 지점이 정확히 여기다 (E.11).
  val readValue = Bits(32 bits)
  readValue := 0
  when(aligned) {
    switch(io.addr) {
      is(OFF_CQ_SIZE)    { readValue := B(cqDepth, 32 bits) }
      is(OFF_CQ_HEAD)    { readValue := headReg }
      is(OFF_CQ_TAIL)    { readValue := tail.resize(32).asBits }
      is(OFF_IRQ_STATUS) { readValue := irqSticky.asBits.resize(32) }
      is(OFF_IRQ_MASK)   { readValue := irqMaskReg }
      is(OFF_FAULT)      { readValue := faultOv.asBits.resize(32) }
      is(OFF_CQ_OCC)     { readValue := occ.resize(32).asBits }
      is(OFF_ALLZERO)    { readValue := allZero.asBits.resize(32) }
      // 드레인 여섯 카운트 — 0x60 + 4·i (E.11 · §3.7 정의역 순서)
      for (i <- 0 until 6) {
        is(OFF_DRAIN + 4 * i) { readValue := cntVec(i).resize(32).asBits }
      }
    }
  }

  // 엔트리 창 — head 항목을 동기 읽기로 낸다. 빈 링이면 0 (미기입 저장소를
  // 관측면에 내지 않는다 — head∈[head,tail) 인 항목만 창에 실린다).
  val isWindow = io.addr(7 downto 5) === (OFF_WINDOW >> 5)
  val ringRd   = ring.readSync(head, acceptR)

  val rdataReg = Reg(Bits(32 bits)) init 0
  val winSel   = RegInit(False)
  val winWord  = Reg(UInt(3 bits)) init 0
  io.rvalid := RegNext(acceptR, False)
  when(acceptR) {
    rdataReg := readValue
    winSel   := aligned && isWindow && !empty
    winWord  := io.addr(4 downto 2)
  }
  io.rdata := winSel ? ringRd.subdivideIn(32 bits)(winWord) | rdataReg
}
