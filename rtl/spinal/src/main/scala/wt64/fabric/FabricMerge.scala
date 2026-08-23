// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// FabricMerge — 결과 방향 valid 디먹스 + OR 병합 + 배압.
//
// 정본 §2.3 「상호연결의 실제 정체」: 실체는 셋뿐이다 — 브로드캐스트 ·
// valid 디먹스 · OR 병합. "라우터도, 중재기도, 패킷도, flit 도 없다."
// 이 모듈은 그중 *결과 방향* — 생산자 N 개의 출력 자원(깊이 D)이 병합 지점
// 하나에서 만나 소비자 인터페이스로 나가는 길 — 이다. dispatch 방향의 공유
// 자원 경합은 FAB-2(SharedUnit)의 소관이며 여기 없다.
//
// 선-formal 모델: rtl/formal/tla/Fabric.tla (검사된 계약, §6.3).
// 대응 관계는 아래 GUARD-MAP 이 가드 단위로 서술한다.
//
// GUARD-MAP: Fabric.single_producer      -> 검사: selOh 가 OHMasking.roundRobin 산출 one-hot(lockedOh 는 그 포획)이고 구동 집합 drive = selOh & req — 사이클당 버스를 구동하는 생산자 ≤ 1 이 구조적으로 보장된다 (FAB-1, §2.3 함정)
// GUARD-MAP: Fabric.valid_gated          -> 검사: 병합 OR 의 입력이 contrib(i) = drive(i) ? face(i) : 0 — vld 가 내려간 lane 의 낡은 face 레지스터 값은 병합에 참여하지 않는다 (FAB-9, §2.3 규범 2항)
// GUARD-MAP: Fabric.valid_tracks_data    -> 검사: vld(= cnt =/= 0) 을 올리는 유일한 경로 doPush 가 같은 사이클에 slots 를 쓴다 — 데이터 없이 valid 만 서는 경로가 없다 (§2.3 결과 방향 규율 1)
// GUARD-MAP: Fabric.capture_atomic       -> 검사: doPop(i) = drive(i) && io.consumer.fire — 버스면 pop 과 소비자 수락(ready/valid 완결)이 같은 사건이다. 「떠났는데 도착 안 함」 상태가 상태 공간에 없다 (FAB-5, §2.6 규범 3항)
// GUARD-MAP: Fabric.stall_on_pending     -> 검사: doPush = strb && !full, full(= cnt === D) 을 io.push(i).stall 로 수출 — 가득 찬 출력 자원에 닿는 쓰기 경로가 없다. 깊이 D 무관 문면 그대로 (§2.6 「깊이 D 는 파라미터다」)
// GUARD-MAP: Fabric.bp_loud              -> 검사: shove = strb && full 이 faultSet 을 구동 — 배압(stall) 무시 밀어넣기는 조용한 소실이 아니라 loud fault 처분을 받는다. 병합 지점 쪽 밀어넣기는 구조 배제(pop 이 fire 연언) (§2.6 규범 4항)
// GUARD-MAP: Fabric.fault_raised         -> 검사: StickyFault(set = shoveAny) — 위반 그 사이클에 상태 비트가 선다 (§2.6 함정 요구 1)
// GUARD-MAP: Fabric.fault_sticky         -> 검사: StickyFault 의 해제 입력이 io.faultClear 하나 — 배압 해제(io.consumer.ready 상승)와 결선되지 않았다. W1C 동반 클리어 없음 (§2.6 함정 요구 2)
// GUARD-MAP: Fabric.bp_no_consumer_write -> 검사: 소비자로 가는 전이는 io.consumer.fire(ready 연언)뿐이고 shove 경로가 쓰는 것은 fault 비트 하나다 — ~ready 동안 io.consumer.valid/payload 의 원천(face·selOh)도 불변(lock + face 불가침) (FAB-10, §2.6 규범 5항)
// GUARD-MAP: Fabric.fair_grant           -> 검사: io.consumer.fire 마다 ptrOh := selOh.rotateLeft(1) — 방금 서비스된 lane 이 최하위 우선순위가 되는 라운드로빈. 고정 우선순위 없음: 대기 lane 은 최대 N grant 안에 선택된다 (FAB-6, §2.3 선택 규칙)
// GUARD-MAP: Fabric.bp_relief            -> ENV — 배압이 결국 풀린다는 것은 소비자/호스트 의무다. §2.6 「진행 전파」 규범의 조건부 의무 사슬이 각 소비자에 걸리고, 무조건 의무(완료 큐를 결국 비운다)는 사슬의 뿌리인 호스트 ABI(부록 E)에만 있다 — RTL 검사가 아니다
package wt64.fabric

import spinal.core._
import spinal.lib._
import wt64.{StickyFault, Types, Wt64Config}

/** 병합 지점을 지나는 결과 비트의 형상 — 지역 정의 (승격 후보).
  *
  * 조각 머리(Types.FragHead — 태그 ∥ 순번 ∥ 선언 총개수 ∥ 마지막 표시,
  * §2.6 규범 1항 「각 조각은 순번과 총 개수를 나른다」)에 본문이 따른다.
  *
  * 본문 폭은 정본이 아직 확정하지 않았다 — §2.3.1 「번들 등급 분리」는
  * DATA 등급의 실측 폭만 적고 재구현 폭은 측정 후 결정으로 미룬다. 그래서
  * elaborate 파라미터로 열어 둔다. 이 폭은 데이터 경로 폭이지 명령·태그
  * 필드 폭이 아니다 — INV-T1 의 대상이 아니며, FabricMerge 는 페이로드를
  * 해석하지 않으므로 이 값이 명령·태그 해석에 샐 자리도 없다.
  */
case class ResultBeat(bodyW: Int) extends Bundle {
  val head = Types.FragHead()
  val body = Bits(bodyW bits)
}

/** 생산자 → 출력 자원 경계의 밀어넣기 포트 — 지역 정의 (승격 후보).
  *
  * Stream 이 아니라 스트로브인 이유: PE 의 산출은 파이프라인 끝에서 나오는
  * 되물릴 수 없는 사건이고, §2.6 규범 4항이 규정하는 「배압 무시」가
  * *물리적으로 가능한* 지점이 바로 이 경계다. Stream 의 의미론(valid 를
  * 들고 기다린다)으로 감싸면 위반이 표현 불가능해지고, 표현 불가능한
  * 결함은 검출 불가능하다 — 선-formal 모델이 Produce 를 가드 없이 열어 둔
  * 것과 같은 이유로, 여기서도 위반을 표현하고 검출한다.
  */
case class ProducePort[T <: Data](payloadType: HardType[T]) extends Bundle with IMasterSlave {
  /** 생산 스트로브 — 이 사이클에 결과를 놓는다. */
  val strb   = Bool()
  val result = payloadType()
  /** 출력 자원 가득 — 생산 정지 요구 (§2.6 규범 2항의 이 경계 형태). */
  val stall  = Bool()

  override def asMaster(): Unit = {
    out(strb, result)
    in(stall)
  }
}

/** 결과 방향 병합 지점 (정본 §2.3 · §2.6 · §2.7 FAB-1·5·6·9·10).
  *
  * 구조: 생산자 N(cfg.nPoints) 각각에 깊이 D(cfg.outDepth ≥ 1)의 출력 자원
  * (버스면 레지스터 = slots(0) + 뒤 슬롯 D-1) → 선택 규칙이 고른 하나가
  * 버스를 구동 → OR 병합 → 소비자 Stream.
  *
  * 페이로드는 불투명하다 — 이 모듈은 해석하지 않고 나른다. 형상 파라미터
  * (N·D)가 명령·태그 해석에 새지 않는 가장 단순한 형태다 (INV-T1).
  */
case class FabricMerge[T <: Data](cfg: Wt64Config, payloadType: HardType[T]) extends Component {
  private val nProd = cfg.nPoints
  private val depth = cfg.outDepth

  val io = new Bundle {
    /** sticky fault — 배압 위반 상태 비트 (§2.6 함정). 합성 결과물에 있다. */
    val fault      = out Bool()
    /** 명시적 해제 — fault 처리 경로만 구동한다. 배압 해제와 무관하다. */
    val faultClear = in Bool()
    val push       = Vec(slave(ProducePort(payloadType)), nProd)
    /** 소비자 인터페이스 — ready/valid 완결이 곧 도착이다 (FAB-5).
      * 이름을 `out` 으로 두지 않는 이유: 같은 스코프의 방향 지정자
      * spinal.core.out 을 가려 다른 포트 선언을 깨뜨린다. */
    val consumer   = master(Stream(payloadType))

    /** E.11 점유 관측면 (§3.7 드레인 정의역 ③ — 생산자 출력 자원과 병합 중
      * 전송). lane 별 출력 자원 점유(cnt)의 합 — 조합 집계, 새 상태 아님
      * (E.11 해설). 병합 중(제공됐으나 핸드오프 미완) beat 는 별항이 아니다:
      * capture_atomic (FAB-5) 이 pop 을 소비자 수락과 같은 사건으로 묶어
      * 「떠났는데 도착 안 함」 상태가 상태 공간에 없으므로, 병합 중인 beat 는
      * 버스면 slots(0) 점유로 이 합에 이미 들어 있다 — 별항을 더하면 이중
      * 계수다. 폭은 자원 상한(N·D)에서 유도 — 관측면이지 인코딩이 아니므로
      * INV-T1 의 대상이 아니다. */
    val occupancy  = out UInt(log2Up(nProd * depth + 1) bits)
  }

  // ── 생산자별 출력 자원 — 버스면 레지스터 + 뒤 슬롯 (§2.6 깊이 D) ──────
  //
  // slots(0) 이 버스면이다. pop 은 아래로 시프트하고 레지스터 내용을 *지우지
  // 않는다* — 실물 레지스터가 그렇다. 마지막 항목을 넘긴 lane 의 face 에는
  // 낡은 값이 남으며, 그 값이 병합에 실리지 않는 것은 이 자원의 성질이
  // 아니라 병합의 valid 게이팅(아래) 이 보장한다. 두 축을 섞지 않는다.
  val lanes = for (i <- 0 until nProd) yield new Area {
    val slots = Vec.fill(depth)(Reg(payloadType()))
    val cnt   = Reg(UInt(log2Up(depth + 1) bits)) init 0
    val full  = cnt === depth
    val vld   = cnt =/= 0

    val port = io.push(i)
    port.stall := full

    // stall_on_pending: 쓰기 경로 전체가 !full 로 게이트된다. 가득 찬 자원을
    // 덮어쓰는 경로는 존재하지 않는다 — 깊이 D 가 얼마든 같은 문면이다.
    val doPush = port.strb && !full
    // §2.6 규범 4항: 배압(stall) 무시 밀어넣기. 데이터는 자원에 닿지 않고
    // (덮어쓰기 없음), 처분은 loud sticky fault 다 — 조용한 소실이 아니다.
    val shove  = port.strb && full
    // 버스면 pop — 병합 지점에서 취해졌다. 아래에서 소비자 수락과 원자적으로
    // 결선된다 (capture_atomic).
    val doPop  = Bool()

    when(doPop) {
      for (k <- 0 until depth - 1) { slots(k) := slots(k + 1) }
    }
    // 새 항목이 놓이는 자리 — pop 을 반영한 뒤의 꼬리. doPop 이면 cnt ≥ 1
    // 이므로 cnt - 1 은 랩하지 않는다.
    val wIdx = Mux(doPop, cnt - 1, cnt)
    when(doPush) {
      for (k <- 0 until depth) {
        when(wIdx === k) { slots(k) := port.result }
      }
    }
    // valid_tracks_data: vld 를 올리는 유일한 경로가 이 증가이고, 같은
    // 사이클에 위의 slots 쓰기가 함께 일어난다 — valid 는 데이터와 함께 선다.
    when(doPush && !doPop) { cnt := cnt + 1 }
      .elsewhen(!doPush && doPop) { cnt := cnt - 1 }
  }

  // ── 선택 규칙 (§2.3 결과 방향 규율 2) ─────────────────────────────────
  //
  // §2.3.1 함정 「라우터를 짓지 말 것」: 이것은 중재기를 새로 짓는 것이
  // 아니다 — 분리된 자원도 패킷도 큐도 없고, 동시에 준비된 생산자 중 *누가
  // 지금 자기 valid 를 버스에 세우는가* 를 정하는 valid 디먹스의 판정
  // 규칙이다. 정본이 「이름을 가진 계약」이라 부른 그 자리이며, FAB-6 의
  // 공정성 의무가 걸리는 곳이 정확히 여기다.
  //
  // 규칙은 라운드로빈이다: fire 마다 우선순위 포인터가 방금 서비스된 lane
  // 의 *다음*으로 돈다. 대기 중인 lane 은 최대 N 번의 grant 안에 반드시
  // 선택된다 — 조각열 생산자가 valid 를 끊지 않고 이어 대도(모델의
  // EmitStream) 포인터가 그를 지나치므로 기아가 없다. 고정 우선순위가
  // 아니다 (fair_grant 삭제 실험이 반증한 바로 그 형태를 피한다).
  val select = new Area {
    val req = Bits(nProd bits)
    for (i <- 0 until nProd) { req(i) := lanes(i).vld }

    /** one-hot 우선순위 포인터 — 여기서부터 처음 만나는 요청이 이긴다. */
    val ptrOh    = Reg(Bits(nProd bits)) init 1
    val rrOh     = OHMasking.roundRobin(req, ptrOh)

    // 제공(valid) 이 수락(ready)을 기다리는 동안 선택을 잠근다 — 대기 중
    // 다른 lane 의 vld 가 서도 제공 중인 페이로드가 바뀌지 않는다. 소비자
    // 관측의 안정성(FAB-10 의 ~ready 구간 불변)의 선택 축이다.
    val locked   = RegInit(False)
    val lockedOh = Reg(Bits(nProd bits)) init 0
    val selOh    = Mux(locked, lockedOh, rrOh)

    // single_producer: selOh 는 one-hot(라운드로빈 산출 또는 그 포획)이고,
    // 버스를 구동하는 집합은 drive = selOh & req ⊆ selOh — 사이클당 최대
    // 하나가 구조적으로 보장된다. 검사 코드가 아니라 구조가 계약이다.
    val drive    = selOh & req

    when(io.consumer.valid && !io.consumer.ready) {
      locked   := True
      lockedOh := selOh
    } otherwise {
      locked := False
    }
    // fair_grant: 서비스된 lane 의 다음 lane 이 최상위 우선순위가 된다.
    when(io.consumer.fire) {
      ptrOh := selOh.rotateLeft(1)
    }
  }

  // ── OR 병합 (§2.3 규범 3항) ───────────────────────────────────────────
  //
  // valid_gated (FAB-9): OR 의 입력은 drive 로 게이트된다 — vld 가 내려간
  // lane 의 face 에 남은 낡은 값은 실리지 않는다. 이것은 FAB-1(동시 유효
  // 생산자 ≤ 1)과 *독립인 축*이다 (§2.7 함정 「FAB-1 은 이 축을 덮지
  // 않는다」): 유효 생산자가 정확히 하나여도 게이팅이 빠지면 이전 핸드오프
  // 가 다른 PE 의 face 에 남긴 값이 함께 실려, 소비자는 어느 생산자도
  // 보내지 않은 값을 받는다 — 경합 없이 일어나는 결함이다. 그래서 위의
  // one-hot 선택(전제 축)과 이 게이팅(게이팅 축)을 각각 따로 세운다.
  val merge = new Area {
    val w = widthOf(io.consumer.payload)
    val contribs = for (i <- 0 until nProd)
      yield Mux(select.drive(i), lanes(i).slots(0).asBits, B(0, w bits))
    val merged = contribs.reduce(_ | _)

    io.consumer.valid := select.drive.orR
    io.consumer.payload.assignFromBits(merged)
  }

  // ── 핸드오프 = 소비자 수락 (capture_atomic / FAB-5) ───────────────────
  //
  // 버스면 pop 이 io.consumer.fire(= valid && ready) 그 사건이다. 「생산자를
  // 떠났는데 소비자에 도착하지 않은」 상태는 상태 공간에 없다 — ready/valid
  // 완결이 원자성이다. ~ready 동안은 pop 도 없고(face 불변) 소비자 쪽으로
  // 향하는 어떤 레지스터 쓰기도 없다 (bp_no_consumer_write / FAB-10 —
  // 소비자 상태를 바꿀 수 있는 유일한 전이가 fire 로 게이트된 이 경로다).
  for (i <- 0 until nProd) {
    lanes(i).doPop := select.drive(i) && io.consumer.fire
  }

  // ── 배압 위반 fault (§2.6 규범 4항 + 함정 「배압 위반은 조용하기 쉽다」) ─
  //
  // 두 요구는 독립이다 — (1) 위반 사이클에 세운다 (fault_raised),
  // (2) 명시적 해제(io.faultClear) 외의 어떤 동작도 내리지 않는다
  // (fault_sticky). 특히 배압 해제가 오류 비트를 함께 지우는 W1C 동반
  // 클리어가 없다 — 해제 입력은 faultClear 하나뿐이고 ready 와 결선되지
  // 않았다. 공용 StickyFault 헬퍼가 그 두 요구를 담는다 (합성 가능한
  // sticky 상태 비트 — 시뮬레이션 전용 단언이 아니다).
  private val shoveAny = lanes.map(_.shove).reduce(_ || _)
  io.fault := StickyFault(set = shoveAny, clear = io.faultClear)

  // ── E.11 점유 관측면 — 드레인 집계의 실입력 (§3.7 정의역 ③) ──────────
  // 이미 있는 점유 상태(lane 별 cnt)의 조합 합산 — 새 상태 없음 (E.11 해설).
  // 부분합·총합 전부 상한 N·D 이내라 occW 로 넘치지 않는다.
  private val occW = log2Up(nProd * depth + 1)
  io.occupancy := lanes.map(_.cnt.resize(occW)).reduce(_ + _)
}
