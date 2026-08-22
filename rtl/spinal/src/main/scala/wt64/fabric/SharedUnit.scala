// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// FAB-2 — 공유 유닛 점유·대기 처분.
//
// 정본 §2.2 「공유 자원의 계약」·「처분 확정 — 대기」:
//   점유 중 도착한 요청은 보류 자원에 받아 두고 공유 유닛이 비는 순서대로
//   처리한다. **무처분이 없다** — 도착한 요청은 반드시 셋 중 하나를 받는다:
//   (1) 받아들여 보류(또는 즉시 점유), (2) 보류 자원 가득 → 배압,
//   (3) 배압을 어긴 밀어넣기 → loud fault. 어느 경우에도 상태 비트를
//   세우지 않고 사라지는 경로가 없다.
//
// 정본 §2.6 「조각 전송과 배압」(같은 배압 규약을 이 지점에 적용):
//   소비자가 받을 수 없으면 배압으로 알리고, 생산자는 **정지한다**. 따라서
//   req 포트는 push 규약이다 — ready 가 낮은 사이클에 valid 를 세우는 것
//   자체가 배압 무시이며 loud fault 다. 그 fault 는 독립인 두 요구를 둘 다
//   진다: 세운다 / 명시적 해제 외엔 내리지 않는다 (공용 StickyFault).
//   FAB-10: 배압이 걸린 동안 소비자 상태(보류 슬롯·유닛 본체)는 쓰이지
//   않는다 — 밀어 넣어진 데이터는 fault 처분과 별개로 상태에 닿지 않는다.
//
// 선-formal 모델: rtl/formal/tla/SharedUnit.tla (AllGuards 3).
// GUARD-MAP: SharedUnit.busy_check   -> acceptDirect = !bodyBusy && queueEmpty — 점유 중(body.io.busy)에는 본체 직행 경로(start)가 닫힌다; start 는 popNow/acceptDirect 두 경로에서만 선다
// GUARD-MAP: SharedUnit.queue_room   -> acceptQueue 에 queueRoom(cnt < queueDepth) 가드 — 자리 검사 없이 슬롯을 쓰는 경로가 없다 (덮어쓰기 부재; 깊이 0 이면 queueRoom = False 상수)
// GUARD-MAP: SharedUnit.backpressure -> io.req.ready := acceptDirect || acceptQueue — 가득 참이 ready 강하로 상류에 보인다; ready 무시 push(valid && !ready)는 bpViolation → StickyFault
//
// 배치 규율: 처분 구조(이 파일의 SharedUnit)와 유닛 본체(SharedUnitBody
// 하위 클래스)를 분리한다. 본체는 고정 인터페이스(start/req/busy/done/rsp)
// 뒤의 추상이며, mkBody 파라미터로 교체해도 처분 구조는 변하지 않는다.
package wt64.fabric

import spinal.core._
import wt64.StickyFault

/** 처분 구조의 파라미터 — 전부 구현 파라미터이며 명령·태그 해석에 새지
  * 않는다 (INV-T1: 요청 토큰은 모델과 같은 **불투명 토큰**이고, 폭이
  * 인스턴스 개수의 함수가 아니다).
  *
  * @param reqWidth     불투명 요청 토큰 폭
  * @param queueDepth   보류 자원 깊이 — 정본 §2.2 3항: 깊이 0(「항상 배압」)도
  *                     적법하다. 다만 그 경우에도 무언 드롭은 금지다.
  * @param occupyCycles 자리 표시자 본체의 점유 사이클 수 N (>= 1)
  */
case class SharedUnitParams(
    reqWidth:     Int = 16,
    queueDepth:   Int = 4,
    occupyCycles: Int = 8,
) {
  require(reqWidth >= 1)
  require(queueDepth >= 0, "깊이 0 = 항상 배압 — 적법 (정본 §2.2 3항)")
  require(occupyCycles >= 1)
}

/** 유닛 본체의 고정 인터페이스 — 처분 구조가 아는 전부.
  *
  * 계약: start 는 busy 가 낮은 사이클에만 선다 (처분 구조가 보장 —
  * busy_check). busy 는 start 다음 사이클부터 점유가 끝날 때까지 높다.
  * done 은 완료 사이클에 1사이클 서고, rsp 는 그 사이클에 유효하다.
  * 본체를 무엇으로 갈아 끼워도 이 다섯 신호가 전부다 — 본체 교체가 처분
  * 구조를 건드릴 수 없다.
  */
abstract class SharedUnitBody(val reqWidth: Int) extends Component {
  val io = new Bundle {
    val start = in  port Bool()
    val req   = in  port Bits(reqWidth bits)
    val busy  = out port Bool()
    val done  = out port Bool()
    val rsp   = out port Bits(reqWidth bits)
  }
}

/** 자리 표시자 본체 — 요청을 N 사이클 점유한 뒤 토큰을 그대로 완료로
  * 돌린다. 설계가 아니다: 처분 구조를 실제 유닛 없이 elaborate·검증하기
  * 위한 대상일 뿐이며, 실제 공유 유닛(나눗셈·행렬 등)이 착지하면
  * SharedUnitBody 하위 클래스로 교체된다.
  */
class SharedUnitOccupyStub(reqWidth: Int, occupyCycles: Int)
    extends SharedUnitBody(reqWidth) {
  require(occupyCycles >= 1)

  private val remain  = RegInit(U(0, log2Up(occupyCycles + 1) bits))
  private val held    = RegInit(B(0, reqWidth bits))
  private val busyReg = RegInit(False)

  io.busy := busyReg
  io.done := False
  io.rsp  := held

  when(io.start) {
    busyReg := True
    held    := io.req
    remain  := occupyCycles
  } elsewhen (busyReg) {
    remain := remain - 1
    when(remain === 1) {
      busyReg := False
      io.done := True
    }
  }
}

/** FAB-2 처분 구조 — 공유 유닛 앞의 도착 처분과 보류 자원.
  *
  * 도착(io.req.valid)의 처분은 아래 `dispatch` 의 when 사슬이 **전수**로
  * 보인다 — 즉시 점유 / 보류 / (ready 낮음 = 배압이 이미 알려진 상태에서
  * 온 valid =) 배압 무시 fault. 세 갈래 밖의 경로가 코드에 없다.
  */
class SharedUnit(
    val p: SharedUnitParams,
    mkBody: SharedUnitParams => SharedUnitBody =
      pp => new SharedUnitOccupyStub(pp.reqWidth, pp.occupyCycles),
) extends Component {

  val io = new Bundle {
    /** push 규약 요청 포트 (§2.6): 상류는 ready 를 보고 정지한다.
      * ready 가 낮은 사이클의 valid 는 배압 무시이며 loud fault 다. */
    val req = new Bundle {
      val valid   = in  port Bool()
      val payload = in  port Bits(p.reqWidth bits)
      val ready   = out port Bool()
    }

    /** 완료 반환 — done 사이클에 1사이클 유효. 완료 쪽의 배압(생산자 출력
      * 레지스터 깊이 D >= 1)은 §2.6 별도 규범이고 병합 지점 쪽 모듈의
      * 소관이다 — 이 모듈은 도착 처분(FAB-2)만 담당한다. */
    val rsp = new Bundle {
      val valid   = out port Bool()
      val payload = out port Bits(p.reqWidth bits)
    }

    /** 배압 무시 sticky fault. 해제는 이 전용 입력뿐이다 — 배압 해제가
      * 오류 비트를 함께 지우는 W1C 동반 클리어 금지 (§2.6 함정). */
    val faultBpViolation = out port Bool()
    val faultClear       = in  port Bool()
  }

  private val body = mkBody(p)

  // ── 보류 자원 — 깊이 queueDepth 의 FIFO (깊이 0 이면 자원 자체가 없다) ──
  private val hasQueue = p.queueDepth > 0
  private val queue = hasQueue generate new Area {
    val ptrW  = log2Up(p.queueDepth) max 1
    val slots = Vec.fill(p.queueDepth)(RegInit(B(0, p.reqWidth bits)))
    val rdPtr = RegInit(U(0, ptrW bits))
    val wrPtr = RegInit(U(0, ptrW bits))
    val cnt   = RegInit(U(0, log2Up(p.queueDepth + 1) bits))

    def bump(x: UInt): UInt =
      Mux(x === p.queueDepth - 1, U(0, ptrW bits), x + 1)

    val head = slots(rdPtr)
  }

  private val queueEmpty = if (hasQueue) queue.cnt === 0 else True
  // queue_room: 깊이 0 이면 상수 False — 「항상 배압」 형상 (§2.2 3항).
  private val queueRoom  = if (hasQueue) queue.cnt < p.queueDepth else False

  private val bodyBusy = body.io.busy

  // ── 처분 판정 (조합) — 도착 한 건은 아래 셋 중 정확히 하나를 받는다 ──
  // busy_check: 점유 중에는 직행이 닫힌다. 유닛이 비어도 보류 열이 비어
  // 있지 않으면 직행하지 않는다 — 추월이 없어야 FAB-6(도착 순서 공정성)의
  // 이 지점 형태가 선다.
  private val acceptDirect = !bodyBusy && queueEmpty
  // queue_room: 자리 검사 없이는 보류 자원에 쓰지 않는다.
  private val acceptQueue  = !acceptDirect && queueRoom

  // backpressure: 받을 수 없음(가득 참·항상 배압)이 상류에 보인다. 배압은
  // 오류가 아니다 (§2.2 2항) — 상류가 정지·재시도하는 정상 경로다.
  io.req.ready := acceptDirect || acceptQueue

  // 배압 무시 밀어넣기 — ready 가 낮다고 알린 사이클에 온 valid. 정본 §2.6
  // 4항: loud fault. 공용 StickyFault: 세운다 / 명시적 해제 외엔 안 내린다.
  private val bpViolation = io.req.valid && !io.req.ready
  io.faultBpViolation := StickyFault(set = bpViolation, clear = io.faultClear)

  // ── 처분 실행 — 도착의 세 갈래가 이 when 사슬로 전수다 ──────────────
  val dispatch = new Area {
    body.io.start := False
    body.io.req   := io.req.payload

    if (hasQueue) {
      // 유닛이 비면 보류 열에서 하나를 꺼내 처리한다 (모델 Dequeue).
      val pop = !bodyBusy && !queueEmpty
      when(pop) {
        body.io.start := True
        body.io.req   := queue.head
        queue.rdPtr   := queue.bump(queue.rdPtr)
      }

      val push = io.req.valid && acceptQueue
      when(io.req.valid) {
        when(acceptDirect) {
          // 처분 1 — 즉시 점유. pop 과는 상호 배타다 (queueEmpty 가 갈라
          // 놓는다): start 가 한 사이클에 두 번 서는 경로가 없다.
          body.io.start := True
        } elsewhen (acceptQueue) {
          // 처분 2 — 보류. queue_room 가드를 통과한 유일한 쓰기 경로다.
          queue.slots(queue.wrPtr) := io.req.payload
          queue.wrPtr := queue.bump(queue.wrPtr)
        } otherwise {
          // 처분 3 — 배압 무시 fault (위의 bpViolation 이 이 갈래와 정확히
          // 일치한다: valid && !acceptDirect && !acceptQueue = valid && !ready).
          // FAB-10: 이 갈래는 어떤 레지스터에도 쓰지 않는다 — 밀어 넣어진
          // payload 는 슬롯에도 본체에도 닿지 않는다.
        }
      }

      queue.cnt := queue.cnt + push.asUInt - pop.asUInt
    } else {
      // 깊이 0 — 보류 자원이 없다. 처분은 즉시 점유 아니면 배압뿐이고,
      // 배압 무시는 위의 bpViolation 이 받는다. 무처분 갈래는 없다.
      when(io.req.valid && acceptDirect) {
        body.io.start := True
      }
    }
  }

  // ── 완료 반환 ────────────────────────────────────────────────────────
  io.rsp.valid   := body.io.done
  io.rsp.payload := body.io.rsp
}
