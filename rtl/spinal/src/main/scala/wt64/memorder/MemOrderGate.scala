// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// MemOrderGate — EXT-6 명시적 순서 토큰의 발화 게이트 (정본 §4.4.4 · §4.6 · D13).
//
// 정본 §4.4.4 「무엇으로 순서를 만드는가」:
//   1. 보장되는 쌍: 순서 토큰으로 연결된 (m1, m2) 에 대해 m2 는 m1 이
//      **완료된 뒤에만** 발화한다 — 발화 계약.
//   2. 보장되지 않는 쌍: 그 밖의 *모든* 쌍. 같은 주소여도, 같은 wave
//      안이어도 토큰으로 잇지 않으면 순서가 없다.
//   3. wave 번호는 순서 기전이 아니다 — 식별자로 남으며 아무것도 게이트하지
//      않는다.
//   6. 게이트되는 것은 발화뿐이다 — 완료는 게이트되지 않는다.
//
// 정본 §4.4.4 「과잉 게이팅 금지」 규범 (D13):
//   발화 게이트의 입력은 **토큰 완료 상태만**이다. wave 번호·주소·태그는
//   게이트 입력이 아니다. 구분선은 대기를 *무엇이 푸는가* — 자원 점유의
//   일시 대기(포트 중재·큐 만석)는 *배압*이고 자원의 해제가 푼다(허용).
//   의미 값의 대기는 *게이팅*이고 데이터의 값이 푼다(금지).
//   이 모듈의 인터페이스가 그 구분선을 그대로 나른다: down(i).ready 가
//   배압 축(자원), gateOpen(i) 이 게이트 축(토큰)이며, 둘은 별도 신호로
//   관측된다 — up(i).ready 는 그 둘의 연언일 뿐 셋째 축이 없다.
//
// loud fault 가 이 모듈에 없는 이유 — §4.4.4 함정 「여기서 loud fault 의
// 전건은 비어 있다」: 이 기전에서 순서 위반은 구조적으로 발생할 수 없다
// (토큰이 도착하지 않으면 의존 연산이 발화하지 않는다). *검사가 없는 것이
// 아니라 검사할 것이 없는 것*이며, 순번 자원이 없으므로 고갈 fault 도 없다
// (§4.4.4 규범 4). 그래서 이 모듈에는 StickyFault 인스턴스가 없다 — 빠진
// 것이 아니라 전건이 빈 것임을 여기 적어 둔다.
//
// 토큰 채널: 토큰을 명령의 *어느 필드*로 나르는지 정본은 아직 배정하지
// 않았다 (§4.4.3 해설 — 스레드 ID·wave 번호에 자리가 있다는 관찰뿐).
// 선-formal 모델이 채널을 추상했듯 이 모듈도 배선 결과만 받는다 —
// io.cfgPreds 가 그 착지 자리이며, 필드 배정이 확정되면 상류(디코드)가
// 이 구성 입력을 구동한다.
//
// 선-formal 모델: rtl/formal/tla/MemOrder.tla (AllGuards 7). 대응은 아래
// GUARD-MAP. 모델의 wave·addr 변수는 이 RTL 에 *대응물이 없다* — 모델이
// 그 둘을 든 이유가 「게이트 콘에 없어야 한다」는 부정 명제의 판정이므로,
// 좋은 RTL 에서 그 신호는 IO 에 아예 존재하지 않는 것이 가장 강한 실현이다.
//
// GUARD-MAP: MemOrder.token_gate -> gates(i).open = ~|waitVec(i), waitVec(i)(j) = cfgPreds(i)(j) && !token(j) — down(i).valid 승격과 up(i).ready 는 open 연언을 지나므로 발화는 선행 토큰 전부 완료일 때뿐이다 (§4.4.4 규범 1)
// GUARD-MAP: MemOrder.token_on_complete -> token(j) 레지스터의 set 입력은 io.complete(j) 하나 — 발화 사건(down(j).fire)과는 결선 자체가 없어 토큰은 발화 시가 아니라 완료 시에 선다 (§4.4.4 규범 1 「완료된 뒤에만」)
// GUARD-MAP: MemOrder.wave_not_gating -> 구조 사실: wave 번호는 이 모듈 IO 에 신호로 존재하지 않는다 — 태그(wave 포함)는 불투명 payload 에 실려 전량 통과하고, 게이트 콘 입력 전수 목록(gates 주석)에 wave 가 없다 (§4.4.4 규범 3 · 과잉 게이팅 금지)
// GUARD-MAP: MemOrder.gate_matches_dep -> waitVec(i) 의 선행 집합 원천은 io.cfgPreds(i) 그대로다 — 원소를 더하는 논리도 빼는 논리도 재부호화도 없다 (cfgPreds(i) 폭이 N−1 이라 자기 자리는 값 공간에 아예 없다 — 모델 GateCand(o) = Ops∖{o} 타입 공간의 실현이지 기계의 빼기가 아니다) (§4.4.4 규범 1·2)
// GUARD-MAP: MemOrder.addr_not_gating -> 구조 사실: 주소도 이 모듈 IO 에 신호로 존재하지 않는다 — payload 는 불투명하고 그 fanout 은 down(i).payload 하나뿐, 주소 비교기가 없다 (§4.4.4 규범 2 「같은 주소여도 순서가 없다」)
// GUARD-MAP: MemOrder.inflight_not_gating -> 구조 사실: 비행 수 계수기·fired 상태가 이 모듈에 존재하지 않고 waitVec(i) 콘에 타 슬롯 handshake 신호가 없다 — down(i).ready 대기는 배압(자원 해제가 푼다)이지 게이팅(값이 푼다)이 아니다 (§4.4.4 과잉 게이팅 금지 규범의 구분선)
// GUARD-MAP: MemOrder.complete_not_ordered -> io.complete 는 슬롯별 독립 1비트이고 각 비트의 fanout 은 자기 token(j) set 뿐 — 완료 경로에 FIFO·순서 비교·상호 게이트·ready 가 없어 동시·역순 완료가 그대로 수락된다 (§4.4.4 규범 6 「완료는 게이트되지 않는다」 · §4.4.4 함정 「응답 FIFO 는 모든 순서 테스트를 통과한다」)
package wt64.memorder

import spinal.core._
import spinal.lib._

/** 발화 게이트의 형상 파라미터 — 전부 구현 파라미터이며 명령·태그 인코딩에
  * 새지 않는다 (INV-T1: cfgPreds 폭은 구성 배선의 폭이지 명령 필드 폭이
  * 아니다. §4.4.3 함정 「형상 독립성과의 상호작용」 — 순번·순서 기전이 물리
  * 자원 개수를 인코딩에 노출하면 위반인데, 이 기전에는 순번 자원 자체가
  * 없고 슬롯 수는 게이트의 동시 관리 폭일 뿐이다).
  *
  * @param nSlots 동시 관리하는 메모리 연산 슬롯 수 N
  * @param reqW   불투명 연산 기술자(태그·주소 포함) 폭 — 이 모듈은 해석하지
  *               않고 나른다
  */
case class MemOrderGateParams(
    nSlots: Int = 4,
    reqW:   Int = 16,
) {
  // 축퇴 형상 금지 — 모델 ASSUME NOps >= 3 과 동형: 슬롯이 3 미만이면
  // 「이어진 쌍」과 「잇지 않은 쌍」이 한 실행에 함께 살 수 없어, 규범 1
  // (보장)과 규범 2(자유)를 같은 기계에서 함께 관측할 수 없다.
  require(nSlots >= 3, "축퇴 형상 금지 — 선-formal ASSUME NOps >= 3 과 동형")
  require(reqW >= 1)
}

/** EXT-6 발화 게이트 — 명시적 순서 토큰의 유일한 강제 지점.
  *
  * 슬롯 i 하나가 메모리 연산 하나다 (모델의 Ops 색인). 프로그램이 건 선행
  * 토큰 집합(io.cfgPreds(i))의 토큰이 전부 서 있을 때만 슬롯 i 의 연산이
  * 하류로 발화하고, 슬롯 i 의 토큰은 하류 완료 응답(io.complete(i))이
  * 돌아온 사이클에 선다.
  *
  * ## 인터페이스 계약 (모델의 초기 상태 동결에 대응)
  *
  *  - io.cfgPreds 는 한 epoch(프로그램 구간) 동안 안정이다 — 모델에서
  *    dep·gateOn 이 초기 상태에서 얼어붙는 것의 RTL 형태. 동적 토큰
  *    재라우팅은 모델도 이 RTL 도 표현하지 않는다 (모델 머리 ⚠️ 절).
  *  - 자기 대기(o ∈ gateOn[o])는 표현 불가다 — cfgPreds(i) 의 폭이 N−1 이라
  *    자기 자리가 값 공간에 없다. 모델 GateCand(o) = Ops ∖ {o} 와 동형.
  *  - epoch 당 슬롯당 발화 ≤ 1, 완료 ≤ 1 이고 완료는 발화된 연산에 대해서만
  *    온다 (모델 Complete 의 전제 fired[o]). 슬롯 재사용은 io.epochClear 로
  *    토큰을 내린 뒤에만 한다.
  *  - 순서 토큰과 데이터플로 피연산자 대기는 별개다 — 피연산자가 갖춰진
  *    연산만 up(i).valid 로 제시되는 것은 상류(데이터플로 발화 규칙)의
  *    소관이며, 이 모듈은 순서 토큰 축만 강제한다.
  */
case class MemOrderGate(p: MemOrderGateParams) extends Component {
  private val n = p.nSlots

  val io = new Bundle {
    /** 구성 입력 — 프로그램이 건 선행 토큰 집합. 폭이 N−1 인 이유: 자기
      * 자리를 값 공간에서 뺀다 (모델 GateCand(o) = Ops ∖ {o} 동형 — 자기
      * 대기는 표현 불가). 비트 k 가 가리키는 선행 슬롯은 predIdx(i)(k) =
      * (k < i ? k : k+1) 이다. cfgPreds(i)(k) = 1 이면 슬롯 i 는 그 선행의
      * 완료 토큰을 기다린다. 게이트 배선은 이 입력 *그대로*다 — 기계가
      * 더하지도 빼지도 않는다 (gate_matches_dep). */
    val cfgPreds = in(Vec(Bits(n - 1 bits), n))

    /** epoch 경계 — 토큰 일괄 해제. 슬롯 재사용의 유일한 통로다. */
    val epochClear = in Bool()

    /** 상류 연산 제시 — payload 는 불투명 연산 기술자(태그·주소 포함).
      * 이 모듈은 해석하지 않고 나른다: wave·주소·태그가 게이트에 닿을
      * 배선 자체가 없다 (wave/addr_not_gating 의 구조 실현). */
    val up = Vec(slave(Stream(Bits(p.reqW bits))), n)

    /** 하류(메모리 파이프) 발화 — ready 는 **배압 축**이다: 자원 점유의
      * 일시 대기이고 자원의 해제가 푼다. 게이트 축(gateOpen — 토큰, 값이
      * 아니라 완료 상태)과 별도 신호로 갈라 둔다 (§4.4.4 구분선). */
    val down = Vec(master(Stream(Bits(p.reqW bits))), n)

    /** 완료 응답 — 슬롯별 독립 1펄스. ready 가 없다: 완료는 어떤 순서로,
      * 몇 개가 동시에 와도 그 사이클에 수락된다 (complete_not_ordered —
      * 응답 FIFO 금지의 구조 실현). */
    val complete = in Bits(n bits)

    /** 관측 — 슬롯별 완료 토큰 상태. */
    val token = out Bits(n bits)

    /** 관측 — 게이트 축 단독 노출: 토큰 조건만으로 발화 가능한가.
      * 배압 축(down(i).ready)과 분리해 두 대기의 원인이 밖에서 구별된다. */
    val gateOpen = out Bits(n bits)
  }

  // ── 토큰 상태 — 슬롯별 독립 비트 (모델 compIdx>0 의 이 게이트 관측면) ──
  //
  // set 입력은 io.complete(j) 하나다 (token_on_complete). 해제는 epochClear
  // 하나다. 같은 사이클에 둘 다 서면 set 이 이긴다 — StickyFault 와 같은
  // 우선순위 규율이되, epoch 경계에 걸친 완료 펄스가 없다는 것은 상류
  // 시퀀싱의 계약이다 (위 인터페이스 계약 3항).
  private val token = Vec.fill(n)(RegInit(False))
  for (j <- 0 until n) {
    when(io.epochClear)  { token(j) := False }
    when(io.complete(j)) { token(j) := True }
  }
  io.token := token.asBits

  // ── 발화 게이트 — 슬롯별 (모델 TokenWait / FireEnabled) ────────────────
  //
  // 게이트 콘의 입력 **전수 목록** (후-formal 이 대조할 앵커 — 모델 가드
  // wave_not_gating · addr_not_gating · inflight_not_gating 의 CHECK 는
  // 「그 신호가 이 콘에 없다」는 구조 사실이다):
  //
  //   io.cfgPreds(i)(k)               — 프로그램이 건 선행 토큰 배선 (구성 입력)
  //   token(predIdx(i)(k)), 즉 j ≠ i  — 선행 슬롯의 완료 토큰 상태
  //
  // 이것이 전부다. 이 콘에 없는 것: wave 번호(IO 에 신호 부재 — payload
  // 불투명), 주소(동일), 태그(동일), 비행 중 연산 수(계수기 부재), 타 슬롯
  // up/down handshake, down(i).ready(발화 *완결*의 배압 항일 뿐 게이트
  // 불참 — gateOpen 은 ready 와 무관하게 선다), io.up(i).valid(연산의
  // 존재이지 순서 조건이 아니다).
  val gates = for (i <- 0 until n) yield new Area {
    // 아직 기다리는 선행의 집합 (모델 TokenWait(o) 의 비트벡터). 자기
    // 자리는 값 공간에 없다 (폭 N−1) — GateCand(o) = Ops ∖ {o} 의 타입
    // 공간 실현. 비트 k ↔ 선행 슬롯 j = (k < i ? k : k+1).
    val waitVec = Vec.tabulate(n - 1) { k =>
      val j = if (k < i) k else k + 1
      io.cfgPreds(i)(k) && !token(j)
    }
    // token_gate: 발화 조건 = 기다리는 집합이 비었다 (모델 FireEnabled —
    // 액션은 공집합 여부만 본다).
    val open = !waitVec.asBits.orR

    io.gateOpen(i) := open

    // 발화 = down(i).fire. valid 는 (연산 존재) ∧ (게이트) 이고, 완결은
    // 하류 ready(배압)가 정한다 — 게이트와 배압은 여기서 연언으로만 만나며
    // 서로의 원천에 배선되지 않는다.
    io.down(i).valid   := io.up(i).valid && open
    io.down(i).payload := io.up(i).payload
    io.up(i).ready     := open && io.down(i).ready
  }
}
