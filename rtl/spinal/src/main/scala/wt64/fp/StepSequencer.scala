// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// StepSequencer — fp32 스칼라 유닛의 step sequencer 골격 (정본 §2.5)
//
// ## 용어 (정본 §2.5 「용어 — 반드시 지킬 것」)
//
// 이 유닛의 순차 제어기는 **step sequencer** 이고 각 단계는 **step** 이다.
// 번역 계층이 아니다 — 명령을 하위 연산으로 번역하는 것이 아니라, 공유
// 연산기 두 기(곱셈기 1 · 가산기 1)를 op 별로 정해진 순서에 따라 걸어갈
// 뿐이다. 다른 이름을 쓰지 않는다.
//
// ## 이번 범위 — 구조 골격
//
// 산술 정확성(반올림 모드 RTO/RNE · 특수값 · 상수 ROM · FAB-8 golden 비트
// 일치)은 축 (b) 후속이다. 이 파일이 세우는 것은 §2.5 의 구조 계약 넷이다:
//   (1) 프로그램 저장 깊이 P >= 1 파라미터
//   (2) 선택자 = 논리 필드 전폭 표 조회, 미상주 = 능력 부재 (fault 불참)
//   (3) 단일 공유 곱셈기 + 단일 공유 가산기를 step 열이 걸어가는 실행 엔진
//   (4) 호스트 MMIO 프로그램 적재 포트 (재적재는 드레인 규약 §3.7 아래)
//
// ## step 부호화의 근거 — golden 관측 (허용 오라클 scripts/golden_fp32.py)
//
// golden 의 SEQUENCER-FAITHFUL 층(micro_*)을 관측하면 모든 step 프로그램의
// 각 단계는 **정확히 하나의 이항 연산**이고, 피연산자는 소수의 래치·상수에서
// 오며, 결과는 정확히 하나의 래치에 착지한다:
//
//   micro_div   루프: t = rto(mb·r) / r = rto(r·(2^F − t))   — 곱·감산 교대
//   micro_rsqrt 루프: t1 = rto(h·y) / t2 = rto(t1·y) / y = rto(y·(3·2^(F−1) − t2))
//   micro_exp2  Horner: acc = rto(acc·f_fix) + coeff[i]      — 곱 뒤 가산
//
// ⇒ step = { 연산기 선택(곱/가산) ‖ 피연산자 라우팅(srcA·srcB) ‖ 래치 제어
//    (dst) ‖ 종료 표시(last) }. 이것이 아래 STEP 워드의 필드 전부다.
//    §2.5 실측 트랙의 면적 내역(전체의 약 60% 가 피연산자 mux 패브릭)이
//    말하는 그 mux 가 곧 srcA/srcB 라우팅이다 — 단일 공유 연산기 설계의
//    본질 비용이며, 복제 대안은 면적·곱셈기 개수 둘 다 더 비쌌다(실측).
//
// STEP 워드 (하위부터 — 포트 폭 16b 고정, [15:14] 예약 = 0 아니면 적재 거절):
//   [0]      last  — 이 step 실행 후 종료, 기록값이 결과다
//   [1]      unit  — 0 = 공유 가산기 · 1 = 공유 곱셈기
//   [5:2]    srcA  — 피연산자 A 스크래치 선택 (표 조회 mux)
//   [9:6]    srcB  — 피연산자 B 스크래치 선택
//   [13:10]  dst   — 결과 래치 선택
// 필드 폭은 전부 **고정 상수**다 — 형상(P·stepMax)의 함수가 아니다 (INV-T1
// 정합). 예약 2b 는 축 (b)의 확장 여지다(반올림 모드 · 상수 소스 공간).
//
// ## 선택자 — 미상주 참조 = 능력 부재 (§2.5 · §1.6.2)
//
// 선택 열쇠는 명령의 논리 필드 = 연산 종류 8b ‖ 정밀도 8b (Isa.PRECISION_W)
// 로, 이미 형상 무관이다 (INV-T1) — P 는 값 공간에 닿지 않는 순수 용량이다.
// 조회는 열쇠 **전폭 2^16 을 색인하는 직접 사상 표**다 — LNID 역방향 표
// (MmioConfig.revMem) 선례. 열쇠 선형 비교 루프는 두지 않는다 (그 루프가
// 존재하는 한 그 값은 물리 인덱스다 — §1.4.3). 상수 비트 슬라이스 없음.
//
// 미적중 = 능력 부재: 바이너리는 옳고 이 기계가 지금 못 하는 것이다. 종결
// 등급 oCapAbsent 1비트로 알리고 **StickyFault 불참** (DecodeWalk oCapAbsent
// 선례 — 능력 부재는 오류가 아니다). 상위 계층이 재적재(§3.7 드레인 규약)
// 후 재시도한다. 새 fault 종류를 만들지 않는다.
//
// 상태열 균일 (§5.3 · DecodeWalk verdict_ungated 선례): 적중·미적중이 같은
// 접수→조회→판정 열을 지나고, 판정은 경로를 가르지 않고 **종결 등급만
// 게이트한다**. step 실행 구간은 상주 프로그램에만 존재한다 — 프로그램이
// 없으면 걸을 열 자체가 없으므로, 균일성의 정의역은 판정까지다.
//
// ## 단일 공유 곱셈기 — FAB-7 매핑 전 축 앵커 (§2.5 「곱셈기는 하나다」)
//
// 곱셈 연산자는 이 컴포넌트에서 **정확히 한 곳**(아래 sharedMul 의 유일한
// 호출)이며, elaborate 시점 계수(require(mulOps == 1))가 이를 강제한다 —
// 「매핑 전 곱셈 연산자 수」 축이 elaborate 에서 보인다. 매핑 후 전용 자원
// 수 축은 후-formal 이 합성 결과물에서 대조한다 (§2.5 검증 방법: 두 축을
// 모두 고정한다 — 증거는 생성 절차와 함께, 판정기는 출처를 검사).
//
// ## 프로그램 적재 — 재적재는 드레인 규약 아래에서 (§3.7)
//
// progWr/bindWr 는 호스트 MMIO 다 (소박한 동기 포트 — 버스 어댑터는 상위
// 몫, MmioConfig 선례). **기계에 드레인 모드는 없다** (§3.7): 진행 중인
// 일과 재적재가 겹치지 않게 하는 것은 호스트 의무다 — 장치 전역 드레인 아래에서 결속을 거둔
// 0xF04 기입 뒤 수락된 0xF08 읽기의 [1](= oBusy)이 0 임을 본 뒤 교체한다 (부록 E.1.1 「호스트 해석 규범」 4항). 이 모듈은
// 드레인 위반이라는 새 fault 를 만들지 않는다: 실행 중 슬롯의 step 을
// 다시 쓰면 결과가 다른 프로그램의 것이 될 뿐이고(미확인 교체의 처분은
// 기존 축), bind 변경은 진행 중 걷기에 닿지 않는다 (슬롯 번호는 조회
// 사이클에 래치된다).
//
// ## 선-formal 모델 없음 — 접점 서술 (GUARD-MAP 정식 줄이 아니다)
//
// 이 모듈이 소유하는 TLA+ 모델은 없다. lint_guard_map 이 파싱하지 않는
// 서술로 두 접점만 남긴다 (MmioConfig 의 서술 선례):
//
//   · FAB-7 (후-formal) — 매핑 전 축의 RTL 앵커가 이 파일의 sharedMul 이다.
//     후-formal 판정기는 생성물의 곱셈 연산자 수와 합성 후 전용 자원 수를
//     각각 선언값(1)과 대조한다.
//   · SEC-2 (마스크 유닛 소관) — 「경로 간 동일성」의 형식화는 §5 마스크
//     유닛의 몫이다. 이 모듈의 접점은 위 「상태열 균일」 문단이다: 선택자
//     적중·미적중은 같은 상태열을 지나며 판정은 종결 등급만 게이트한다.
//     이 모듈을 SEC-2 형식화의 대상으로 오독하지 말 것.

package wt64.fp

import spinal.core._
import wt64.{Isa, StickyFault}

/** step sequencer 의 고정 상수 — 전부 형상 무관 (INV-T1 정합).
  *
  * 호스트가 보는 적재 ABI(STEP 워드 · 슬롯 필드 · 열쇠)의 폭이므로 형상
  * 파라미터의 함수가 아니어야 한다. 구체 필드 배치는 정본이 호스트 측
  * 합의로 미룬 항목이며 아래는 이 구현의 잠정 결정이다 (MmioConfig 엔트리
  * 배치 선례 — 보고서 model_feedback 참조).
  */
object StepSequencer {
  /** 선택 열쇠의 연산 종류 필드 폭 — opcode/sub-op 의 논리 공간 8b.
    * (golden 관측: FSCALAR sub-op 는 imm16[7:4] 4b 지만, CVT·DEQUANT 등
    * 프로그램 종이 opcode 축으로도 갈라지므로 한 바이트로 잡는다.) */
  val KEY_OP_W = 8
  /** 선택 열쇠 전폭 = 연산 종류 ‖ 정밀도 (§2.5 「선택자는 명령의 논리
    * 필드(연산·정밀도)」). 표는 이 전폭을 색인한다. */
  val KEY_W = KEY_OP_W + Isa.PRECISION_W

  /** 스크래치 래치 수 — 피연산자 라우팅 공간. 고정 16 (SEL_W=4 전폭). */
  val N_REGS = 16
  val SEL_W  = 4

  /** STEP 워드 유효 폭과 포트 폭. 예약 [15:14] 는 0 이 아니면 **적재
    * 거절**이다 — MMIO 예약 오프셋의 관대 정책(§3.7)이 아니라 명령 인코딩
    * 쪽 정책(§1.4.6)을 따른다: step 워드는 실행 의미를 지닌 내용물이라,
    * 모르는 비트를 무시하고 실행하면 (예: 미래의 반올림 모드 비트) 결과가
    * 조용히 틀린다. 관측면: faultBadProg (조용한 실패 금지). */
  val STEP_W      = 2 + 3 * SEL_W
  val STEP_PORT_W = 16

  /** 적재 포트의 슬롯·step 색인 필드 폭 — 고정 8b. P·stepMax(형상)의
    * 함수가 아니다. 합법 값 검사는 기입 시점에 따로 선다 (MmioConfig
    * OWNER_POINT_W 선례). */
  val SLOT_FIELD_W = 8
  val IDX_FIELD_W  = 8

  // STEP 워드 필드 오프셋 (하위부터 — 머리 주석의 배치 그대로)
  val ST_LAST = 0
  val ST_UNIT = 1
  val ST_SRCA = 2
  val ST_SRCB = 2 + SEL_W
  val ST_DST  = 2 + 2 * SEL_W

  /** 스크래치 적재 규약 — 접수 사이클에 피연산자가 착지하는 자리.
    * step 프로그램은 이 규약을 전제로 작성된다 (호스트 측 합의 대상). */
  val REG_A = 0
  val REG_B = 1
  val REG_C = 2

  /** 곱셈 고위부 착지 래치 — 곱 step 마다 곱셈기의 2·dataW 결과 상위
    * 절반이 여기 착지한다. golden 관측 근거: micro_div 의 p = ma·r 는
    * 전폭(53b) 곱을 binade 판정과 Markstein 정확 잔차에 쓴다 — 광폭
    * 중간값이 라우팅 가능해야 한다. dst 가 REG_HI 인 곱 step 은 고위부
    * 기록이 이긴다 (규약 — 저위부를 남기려면 다른 dst 를 쓸 것). */
  val REG_HI = 15
}

/** 구현 파라미터 — 전부 용량이며 명령·태그·적재 ABI 의 값 공간에 닿지
  * 않는다 (INV-T1).
  *
  * @param progDepth 프로그램 저장 깊이 P >= 1 (§2.5 규범 — L·D 와 같은
  *                  처분). 기본 10 = 참조 구현의 step 프로그램 전 상주
  *                  형상 (§2.5 해설: 그때 능력 부재 경로는 도달 불가한 채
  *                  계약으로만 존재한다). Wt64Config.stepProgDepth 승격
  *                  대기 — 통합자 반영 전까지 생성자 파라미터로 둔다.
  * @param stepMax   슬롯당 step 수 상한 (2의 거듭제곱 — 저장 주소가
  *                  슬롯 ‖ 색인 연접이 되기 위한 조건)
  * @param dataW     데이터패스 폭 — 골격 값. 축 (b)가 golden 의 확장
  *                  유효자리 폭(Q2.28~Q2.30, RSQRT_FRAC/DIV_FRAC 관측)에
  *                  맞춰 확정한다.
  */
case class StepSeqParams(
    progDepth: Int = 10,
    stepMax:   Int = 32,
    dataW:     Int = 32,
) {
  import StepSequencer._
  require(progDepth >= 1, "§2.5 프로그램 깊이 P >= 1")
  require(progDepth <= (1 << SLOT_FIELD_W), "슬롯 필드 8b 초과 형상 — 적재 ABI 합의부터 다시")
  require(isPow2(stepMax) && stepMax >= 2, "슬롯 ‖ 색인 연접 주소를 위해 stepMax 는 2의 거듭제곱")
  require(stepMax <= (1 << IDX_FIELD_W), "step 색인 필드 8b 초과 형상 — 적재 ABI 합의부터 다시")
  require(dataW >= 8)

  val slotW = log2Up(progDepth) max 1
  val pcW   = log2Up(stepMax)
}

/** fp32 스칼라 유닛의 step sequencer — 구조 골격.
  *
  * 접수(req) → 선택자 조회(1사이클) → 판정 → (적중이면) step 걷기 → 종결.
  * 종결 등급은 {oExecValid, oCapAbsent, oProgMal} 셋이고 oDone 사이클에
  * 정확히 하나가 선다 (DecodeWalk 종결 등급 선례).
  */
case class StepSequencer(p: StepSeqParams) extends Component {
  import StepSequencer._

  val io = new Bundle {
    // ── 요청 — push 규약 (§2.6): 상류는 ready 를 보고 정지한다. ready 가
    //    낮은 사이클의 valid 는 배압 무시이며 loud fault 다 (SharedUnit 선례).
    val req = new Bundle {
      val valid     = in  port Bool()
      /** 선택 열쇠의 논리 필드 — 연산 종류. 값 공간은 형상 무관 (INV-T1). */
      val opKind    = in  port Bits(KEY_OP_W bits)
      /** 선택 열쇠의 논리 필드 — 정밀도 (태그 §1.4.4 의 그 필드 폭). */
      val precision = in  port Bits(Isa.PRECISION_W bits)
      val a         = in  port Bits(p.dataW bits)
      val b         = in  port Bits(p.dataW bits)
      val c         = in  port Bits(p.dataW bits)
      val ready     = out port Bool()
    }

    // ── 종결 — oDone 1펄스 + 종결 등급 (등급은 원인 코드가 아니다 —
    //    DecodeWalk out_no_reason 선례: 원인 코드 채널 자체가 없다).
    val oDone      = out port Bool()
    /** 상주 프로그램 완주 — oResult 유효. */
    val oExecValid = out port Bool()
    /** 미상주 참조 = 능력 부재 (§1.6.2) — StickyFault 불참. 상위 계층이
      * 재적재(§3.7) 후 재시도한다. */
    val oCapAbsent = out port Bool()
    /** 종료 표시 없이 stepMax 를 소진한 프로그램 — 적재 내용 불량 종결.
      * faultBadProg 가 함께 선다 (loud). */
    val oProgMal   = out port Bool()
    val oResult    = out port Bits(p.dataW bits)

    /** 진행 중인 걷기·판정이 있으면 1 — FP_STATUS `[1]` 의 원천이다 (부록 E.1.2 「걷기 진행 중」 · Wt64Top fpStat).
      * 드레인 집계(부록 E.11 「DRAIN_ALLZERO」)에는 결선되지 않는다. 재적재 순서의 관측은 부록 E.1.1 「호스트 해석 규범」 4항과 FP_STATUS 행이 정한다. */
    val oBusy = out port Bool()

    // ── 프로그램 적재 (호스트 MMIO — 버스 어댑터는 상위 몫) ─────────────
    // loadReady 가 낮은 동안(선택자 표 초기화 소거 중)의 기입은 수락되지
    // 않는다 — 상위 어댑터가 대기시킨다 (MmioConfig ready 선례).
    val progWr = new Bundle {
      val valid = in port Bool()
      val slot  = in port UInt(SLOT_FIELD_W bits)
      val idx   = in port UInt(IDX_FIELD_W bits)
      val step  = in port Bits(STEP_PORT_W bits)
    }
    /** 열쇠 → 슬롯 결속. en=1 결속 · en=0 해제. 결속이 곧 상주 선언이다 —
      * 상주 여부의 단일 authority 는 선택자 표 하나다 (프로그램 내용의
      * 유효성은 호스트 의무 — 결속 전에 step 을 다 실어야 한다). */
    val bindWr = new Bundle {
      val valid = in port Bool()
      val key   = in port Bits(KEY_W bits)
      val en    = in port Bool()
      val slot  = in port UInt(SLOT_FIELD_W bits)
    }
    val loadReady = out port Bool()

    // ── loud sticky fault — 세운다 / 명시적 해제 외엔 내리지 않는다 ─────
    // 배압 해제가 오류 비트를 함께 지우는 W1C 동반 클리어 금지 (§2.6 함정).
    val faultBpViolation = out port Bool()
    /** 폴딩 규정 (§5.6 — 폴딩 여부는 신호마다 명시): 「용량 밖 슬롯 적재」·
      * 「용량 밖 슬롯 결속」·「stepMax 밖 색인 적재」·「예약 비트 ≠ 0
      * 적재」·「종료 표시 없는 프로그램」은 전부 '호스트가 실은 프로그램의
      * 불량'이며 수리 주체가 같다 (드라이버) — 한 비트로 접는다. 능력
      * 부재(oCapAbsent)와는 접지 않는다 — 그쪽은 fault 가 아니다 (§1.6.2). */
    val faultBadProg = out port Bool()
    val faultClearBp      = in port Bool()
    val faultClearBadProg = in port Bool()
  }

  // ═══ 저장 구조 ═══════════════════════════════════════════════════════
  // progMem — 프로그램 저장: P 슬롯 × stepMax step. 주소 = 슬롯 ‖ 색인.
  //           크기는 2^(slotW+pcW) 로 채운다 (P 가 2의 거듭제곱이 아니면
  //           약간 남는다 — 주소 안전이 몇 워드보다 싸다).
  // selMem  — 선택자 표: 열쇠 전폭 2^16 직접 사상 → [slotW] 상주 ‖ 슬롯.
  //           엔트리 수는 열쇠가 논리 필드 전폭이라는 인코딩 사실이 정한다.
  //           P(형상)가 아니다 (MmioConfig TBL_ENTRIES 논리와 동형).
  //           엔트리의 슬롯 필드는 내부 폭 slotW 다 — 용량 검사를 통과한
  //           기입만 실리므로 저장된 슬롯은 항상 < P 다 (기입 시점 거절이
  //           읽기 시점 재검사를 불필요하게 만든다 — MmioConfig D2 논리).
  val progMem = Mem(Bits(STEP_W bits), 1 << (p.slotW + p.pcW))
  val selMem  = Mem(Bits(1 + p.slotW bits), 1 << KEY_W)

  // ═══ 선택자 표 초기화 소거 — reset 직후 전 열쇠 미상주 ═══════════════
  // 표는 Mem 이라 reset 신호로 비울 수 없다 — 2^16 사이클 소거를 돌고
  // 그동안 접수·적재를 막는다 (MmioConfig 초기화 소거 선례). 구성하지 않은
  // 기계가 우연히 동작하는 것을 막는 관측 가능한 구현이다.
  val initCnt  = Reg(UInt(KEY_W bits)) init 0
  val initDone = RegInit(False)
  when(!initDone) {
    initCnt := initCnt + 1
    when(initCnt === (1 << KEY_W) - 1) { initDone := True }
  }

  // ═══ 적재 — 용량 검사 뒤 커밋 (검사 없는 기입 경로가 없다) ═══════════
  io.loadReady := initDone

  // 용량 밖 검사 — P·stepMax 가 필드 전폭이면 위반이 표현 불가능하므로
  // Scala 상수 False (폭 비교 경고를 만들지 않는다).
  private def slotOut(s: UInt): Bool =
    if (p.progDepth >= (1 << SLOT_FIELD_W)) False else s >= p.progDepth
  private def idxOut(i: UInt): Bool =
    if (p.stepMax >= (1 << IDX_FIELD_W)) False else i >= p.stepMax

  // 예약 비트 [15:14] ≠ 0 은 거절이다 — 정책 근거는 STEP_PORT_W 주석.
  val stepResvBad = io.progWr.step(STEP_PORT_W - 1 downto STEP_W) =/= 0
  val progWrBad = io.progWr.valid && io.loadReady &&
    (slotOut(io.progWr.slot) || idxOut(io.progWr.idx) || stepResvBad)
  val progWrOk = io.progWr.valid && io.loadReady && !progWrBad
  progMem.write(
    address = io.progWr.slot(p.slotW - 1 downto 0) @@ io.progWr.idx(p.pcW - 1 downto 0),
    data    = io.progWr.step(STEP_W - 1 downto 0),
    enable  = progWrOk,
  )

  // 결속: en=1 이고 슬롯이 용량 밖이면 거절 — 수락하면 「표에는 있고
  // 프로그램은 없는 이름」(조용히 사라지는 이름, MmioConfig capSlots 논리)
  // 이 생긴다. en=0 해제는 슬롯 무관 — 데이터는 0 으로 정규화한다.
  val bindWrBad = io.bindWr.valid && io.loadReady && io.bindWr.en && slotOut(io.bindWr.slot)

  // selMem 단일 쓰기 포트 — 소거와 결속 기입을 먹싱한다 (Mem 마다 하나).
  val selWrEn   = False
  val selWrAddr = UInt(KEY_W bits)
  val selWrData = Bits(1 + p.slotW bits)
  selWrAddr := 0
  selWrData := 0
  when(!initDone) {
    selWrEn   := True
    selWrAddr := initCnt
  }.elsewhen(io.bindWr.valid && !bindWrBad) {
    selWrEn   := True
    selWrAddr := io.bindWr.key.asUInt
    // 용량 검사(bindWrBad)를 통과했으므로 하위 slotW 비트가 슬롯 전부다.
    when(io.bindWr.en) { selWrData := True ## io.bindWr.slot(p.slotW - 1 downto 0) }
  }
  selMem.write(selWrAddr, selWrData, selWrEn)

  // ═══ 접수 → 조회 → 판정 → 걷기 ═══════════════════════════════════════
  // 상태 부호 — 지역 UInt 상수. SpinalEnum 은 시뮬 전용 *_string 신호를
  // 생성해 -Wall 청정을 깨므로 쓰지 않는다 (MaskUnit 과 같은 선택).
  private val S_IDLE   = 0
  private val S_LOOKUP = 1
  private val S_RUN    = 2
  private val state = Reg(UInt(2 bits)) init S_IDLE

  io.req.ready := initDone && state === S_IDLE
  io.oBusy     := state =/= S_IDLE

  // 배압 무시 밀어넣기 — ready 가 낮다고 알린 사이클에 온 valid (§2.6 4항).
  // FAB-10 의 이 지점 형태: 이 갈래는 아래 어떤 상태(스크래치·pc·결과)에도
  // 쓰지 않는다 — 상태 갱신은 전부 accept 연언 아래에 있다.
  val bpViolation = io.req.valid && !io.req.ready
  io.faultBpViolation := StickyFault(set = bpViolation, clear = io.faultClearBp)
  // faultBadProg 결선은 걷기 쪽 발화선(runaway)이 정의된 뒤 아래 한 곳에서.

  val accept = io.req.valid && io.req.ready

  // ── 스크래치 래치 — 피연산자 라우팅의 정의역. 접수 규약: 0=a · 1=b · 2=c.
  val scratch = Vec.fill(N_REGS)(RegInit(B(0, p.dataW bits)))

  // 선택자 조회 — 접수 사이클에 열쇠 전폭으로 발사, LOOKUP 사이클에 유효.
  val key   = io.req.opKind ## io.req.precision
  val selRd = selMem.readSync(key.asUInt, accept)
  val selV    = selRd(p.slotW)
  val selSlot = selRd(p.slotW - 1 downto 0).asUInt

  when(accept) {
    scratch(REG_A) := io.req.a
    scratch(REG_B) := io.req.b
    scratch(REG_C) := io.req.c
    state := S_LOOKUP
  }

  // ── step 인출 — 걷기 중 매 사이클 하나, 실행은 인출 다음 사이클 ──────
  val slotReg = Reg(UInt(p.slotW bits)) init 0
  val fetchPc = Reg(UInt(p.pcW bits)) init 0   // 다음에 인출할 색인
  val execCnt = Reg(UInt(p.pcW bits)) init 0   // 지금까지 실행한 step 수 − 1

  val fetchEn   = False
  val fetchAddr = UInt(p.slotW + p.pcW bits)
  fetchAddr := slotReg @@ fetchPc
  val stepWord = progMem.readSync(fetchAddr, fetchEn)

  // ── 종결 펄스 래치 — 등급은 판정·걷기가 세우고 소비 지점은 이 래치만
  //    읽는다 (DecodeWalk mal_carried 논리: 재계산 없음).
  val rDone = RegInit(False)
  val rCapa = RegInit(False)
  val rMal  = RegInit(False)
  rDone := False
  rCapa := False
  rMal  := False

  val rResult = Reg(Bits(p.dataW bits)) init 0

  // ── 판정 (LOOKUP) — 적중·미적중이 같은 상태열을 지나왔고, 여기서 갈리는
  //    것은 종결 등급뿐이다 (verdict_ungated 선례 · SEC-2 접점 서술 참조).
  when(state === S_LOOKUP) {
    when(selV) {
      slotReg   := selSlot
      fetchEn   := True
      fetchAddr := selSlot @@ U(0, p.pcW bits)
      fetchPc   := 1
      execCnt   := 0
      state     := S_RUN
    }.otherwise {
      // 능력 부재 — 오류가 아니다. fault 비트 어디에도 나타나지 않는다.
      rDone := True
      rCapa := True
      state := S_IDLE
    }
  }

  // ═══ 실행 엔진 — 공유 곱셈기 1 + 공유 가산기 1 을 step 열이 걸어간다 ═══
  //
  // FAB-7 매핑 전 축 앵커: 곱셈 연산자는 sharedMul 안의 한 곳뿐이고,
  // elaborate 가 그 유일성을 계수로 강제한다. 후-formal 은 생성물의 곱셈
  // 연산자 수(1)와 합성 후 전용 자원 수를 선언값과 대조한다 (§2.5).
  private var mulOps = 0
  private def sharedMul(a: UInt, b: UInt): UInt = {
    mulOps += 1
    a * b // ← 이 컴포넌트의 유일한 곱셈 연산자
  }

  val stLast = stepWord(ST_LAST)
  val stUnit = stepWord(ST_UNIT)
  val stSrcA = stepWord(ST_SRCA, SEL_W bits).asUInt
  val stSrcB = stepWord(ST_SRCB, SEL_W bits).asUInt
  val stDst  = stepWord(ST_DST,  SEL_W bits).asUInt

  // 피연산자 라우팅 — 스크래치 표 조회 mux (면적 내역의 그 60%). 선형 비교
  // 루프가 아니라 색인 전폭 조회다.
  val opA = scratch(stSrcA).asUInt
  val opB = scratch(stSrcB).asUInt

  val mulProd = sharedMul(opA, opB)             // 2·dataW — 확장 폭은 축 (b) 소관
  val addSum  = opA + opB                       // 공유 가산기 — 데이터패스 유일 가산
  val wb      = Mux(stUnit, mulProd(p.dataW - 1 downto 0), addSum).asBits
  // (제어 카운터의 +1 은 데이터패스 가산이 아니다 — 「가산기는 하나」의
  //  정의역은 step 이 라우팅하는 피연산자 데이터패스다.)

  require(mulOps == 1, "FAB-7 매핑 전 축 — 곱셈 연산자는 정확히 하나여야 한다")

  when(state === S_RUN) {
    // 실행: 이전 사이클에 인출된 step 하나. 저위부는 dst 래치에, 곱이면
    // 고위부가 REG_HI 에 함께 착지한다 (규약은 REG_HI 주석 — 광폭 중간값의
    // golden 관측 근거도 거기 있다).
    scratch(stDst) := wb
    when(stUnit) { scratch(REG_HI) := mulProd(2 * p.dataW - 1 downto p.dataW).asBits }

    when(stLast) {
      rResult := wb
      rDone   := True
      state   := S_IDLE
    }.elsewhen(execCnt === p.stepMax - 1) {
      // 종료 표시 없이 상한 소진 — 적재 내용 불량. 능력 부재가 아니라
      // loud fault 다 (호스트가 실은 프로그램이 규약(last 필수)을 어겼다).
      rDone := True
      rMal  := True
      state := S_IDLE
    }.otherwise {
      fetchEn := True
      execCnt := execCnt + 1
      fetchPc := fetchPc + 1
    }
  }

  // faultBadProg — 발화선 셋(적재 불량 둘 + 걷기 불량 하나)을 한 비트에
  // 접는다. 폴딩 규정은 io 주석에 명시 (§5.6). runaway 는 위 elsewhen 갈래와
  // 같은 조건이다 — 종결 등급(rMal)과 sticky 가 같은 사이클에 함께 선다.
  val runaway = state === S_RUN && !stLast && execCnt === p.stepMax - 1
  io.faultBadProg := StickyFault(
    set   = progWrBad || bindWrBad || runaway,
    clear = io.faultClearBadProg,
  )

  // ═══ 종결 표면 ═══════════════════════════════════════════════════════
  io.oDone      := rDone
  io.oCapAbsent := rDone && rCapa
  io.oProgMal   := rDone && rMal
  io.oExecValid := rDone && !rCapa && !rMal
  io.oResult    := rResult
}
