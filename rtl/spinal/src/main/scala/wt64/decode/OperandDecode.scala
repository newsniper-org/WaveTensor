// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// OperandDecode — EH 본문 해석 (2차 파도).
//
// DecodeWalk 가 방출한 순회 산출(효과 게이트된 슬롯 서술자 + 명령 워드)을
// 받아 종류별 본문을 필드로 해석한다. DecodeWalk 머리 주석의 「범위」가
// 2차 파도에 남긴 것 중 **EH 본문 해석과 본문 내 예약 필드 판정**이 이
// 모듈이다 (플래그–EH 대응 검사는 여기 아니다 — 아래 「남긴 것」).
//
// 정본: §1.4 (목적지·피연산자 명명 — 논리화 개정판),
//       §1.4.1 PORT 본문 = dest_node_id 16b 축자 (재정렬·스왑 없음),
//       §1.4.3 OPREF noc_route[7:0] 전폭 = LBID · src_kind 표 (≥3 예약 → 오류),
//       §1.4.6 OPREF [23:20] 포트 니블 폐지 — 예약, 반드시 0, 아니면
//              malformation (@sec:security 5.7),
//       §1.4.7 ACCTGT — [31:24] 목적 LBID · [23:16] 예약 반드시 0. 다중 조각
//              wave 재조립 문맥의 결속 원천 (§4.3 「태그→구간 결속」),
//       §4.2.3 반복 결합 전수표 — OPREF 는 등장 순서대로 A·B (최대 2회),
//              SUBSCRIPT 는 등장 순서대로 연접, NOP_PAD 는 효과 없음.
//              반복 상한 위반의 *판정*은 DecodeWalk (dupBad) 소관이고, 이
//              모듈은 그 순서 규약대로 *자리를 배정*한다,
//       §5.7 예약 불투과 — 0 이 아니면 malformation, 조용히 무시하지 않는다,
//       §1.6.1 함정 「존재하지 않는 EH 의 본문 잔여값」 — 검사는 EH 가 실제로
//              존재하는 명령에 대해서만 발화한다 (모든 본문 판정·해석이
//              iSlotPresent 로 게이트되는 이유),
//       §1.6.1 판정 위치 — 2차 파도의 malformation 항은 DecodeWalk 의 판정과
//              같은 판정점(실행 유효 이전)에 합류해야 한다 (D14 정합 — 이
//              모듈이 조합 논리인 이유: 판정 tick 을 새로 만들지 않는다).
//
// ── 인코딩 관측 기록 (허용 오라클: asm/wavetensor_asm.py encode_pass) ────
//  본문 [31:16]("body 상위 16비트") 과 후속 워드의 배치 전부 _encode_eh
//  (1891–1996 행) 실측이며 정본 §1.3.3 「EH 의 비트 배치」 표와 일치:
//  · PORT      w0[31:16] = dest_node_id 16b — 비트 i 가 그대로 비트 i (1928 행)
//  · IMM16     w0[31:16] = 즉치 16b (1932 행)
//  · IMM32     w1 = 즉치 32b, w0[31:16] 은 어셈블러가 0 방출 (1935 행)
//  · IMM64     w1 = 하위 32b · w2 = 상위 32b, w0[31:16] 은 0 방출 (1938–1942 행)
//  · MEM       w0[31:20] = stride 12b · w0[19:16] = addr_mode 4b ·
//              w1 = 오프셋 32b (1944–1948 행: upper = stride<<4 | mode)
//  · SUBSCRIPT w0[31:16] = O축 · w1[31:16] = A축 · w1[15:0] = B축 —
//              각 16b = 4b 축 코드 × 4, 하위 니블부터 (1949–1957 행 ·
//              _pack_axes 1844–1861 행). 5–8축은 두 EH 연접, 첫째가 축 0–3 ·
//              둘째가 축 4–7 (_encode_subscript_eh_multi 1999–2017 행) —
//              §4.2.3 「등장 순서대로 연접」의 실물
//  · OPREF     w0[31:24] = noc_route 8b (= LBID) · w0[23:20] = 예약 4b
//              (폐지된 포트 니블 — 반드시 0) · w0[19:16] = src_kind 4b
//              (1958–1988 행: upper = route<<8 | kind, port≠0 은 어셈블러도
//              거절). RouteJudge.scala 34–39 행의 같은 관측 재확인
//  · PRECISION w0[31:24] = dim_override 8b · w0[23:16] = precision_mode 8b
//              (1989–1993 행: upper = dim<<8 | mode)
//  · NOP_PAD   본문 없음 — w0[31:16] 은 0 방출 (1995 행). 정렬 전용, 해석
//              산출 없음 (§4.2.3 「효과 없음」)
//  · ACCTGT    어셈블러·isa/wt64v1_isa.json 미착지 — 배치 원천은 정본 §1.4.7
//              표 그대로: w0[31:24] = 목적 LBID · w0[23:16] = 예약 0
// ─────────────────────────────────────────────────────────────────────────
//
// 이 모듈이 남긴 것 (2차 파도의 나머지 — 여기 없다):
//  · 플래그–EH 대응 검사 (§1.6.1 항2) — 플래그 의미 배정(F_HAS_OPB 등)을
//    소비하는 검사이며 별도 착지 대상.
//  · 「조각 총개수 ≥ 2 선언 wave 에 ACCTGT 부재 = malformation」(§4.3) —
//    조각 선언은 사이드밴드(CTRL) 정보라 명령 워드만으로 판정 불가.
//  · ACCTGT LBID 의 사상표 부재 판정 — route fault 의 사상 축 (ISA-8),
//    판정 주체는 배달 범위 진입점 (RouteJudge, §1.6.3).
//
// GUARD-MAP 없음 — 이 모듈의 선-formal 모델은 없다 (지시서: 모델 없음).
// 본문 예약 판정의 모델·정본 대응은 DecodeWalk 의 Decode.resv_judged 줄이
// 이미 「2차 파도가 같은 판정점에 합류시킨다」로 예고했다 — 이 모듈이 그
// 합류의 실물이다.
package wt64.decode

import spinal.core._
import spinal.lib._
import wt64.{Isa, StickyFault}
import wt64.route.RouteJudge

/** EH 본문 해석기 — DecodeWalk 의 2차 파도.
  *
  * 조합 논리다 — 판정 tick 을 새로 만들지 않는다. DecodeWalk 의 방출
  * 사이클 안에서 본문 예약 판정이 기존 판정(rMal·rCapa)에 합류하고
  * (§1.6.1 「판정은 순회 종료 직후 한 번」과 정합), 해석 산출 전부가
  * 합류된 실행 유효(oExecValid)로 게이트된다 — malformed·capability
  * 명령의 본문은 하류에 실리지 않는다 (§1.6.1 「진입하지 않는다」는 효과의
  * 문장). 데이터 의존 제어가 없어 어떤 명령 비트도 소요 tick 을 바꾸지
  * 못한다 (§5.3 상태열 균일 — D11/D14 부류).
  *
  * @param ehSlots EH 슬롯 상한 — DecodeWalk 와 같은 형상 파라미터 (§4.3).
  *                두 모듈은 같은 값으로 인스턴스돼야 한다.
  */
class OperandDecode(val ehSlots: Int = 4) extends Component {
  import Isa.EhCode

  // DecodeWalk 와 같은 하한 — 축퇴 형상 금지 (Walk.tla ASSUME Cap >= 2 동형).
  require(ehSlots >= 2, "축퇴 형상 금지 — DecodeWalk 와 같은 하한")

  /** EH 종류 코드 폭 — DecodeWalk.KIND_W 와 같은 ISA 사실 (Isa 승격 후보). */
  val KIND_W = 4

  /** 카탈로그 최대 EH 워드 수 (IMM64 = 3, §1.3.2) — ISA 사실. */
  val EH_WORDS_MAX = 3

  /** 명령 버퍼 워드 수 — DecodeWalk.maxWords 와 같은 식 (형상). */
  val maxWords = 1 + ehSlots * EH_WORDS_MAX
  require(maxWords <= 255, "오프셋 산술이 bh_len 선언 폭 8비트 안에 있어야 한다 (§1.3)")

  /** 종류별 등장 계수 폭 — 슬롯 상한 + 1 값 공간. */
  private val OCC_W = log2Up(ehSlots + 1)

  /** src_kind 예약 하한 — §1.4.3 표: 0 직접 / 1 결과 뱅크 / 2 난수 뱅크 /
    * ≥3 예약 → 오류. RouteJudge.scala 37–39 행이 이 거절을 「malformation
    * 판정(디코드 경계) 소관」으로 이 모듈에 넘겼다 — 여기가 그 판정이다. */
  private val SRC_KIND_RESERVED_MIN = 3

  val io = new Bundle {
    // ── DecodeWalk 방출면과 1:1 (oValid·oMalformed·… → iValid·iMalformed·…) ──
    /** 판정 완료 스트로브 (DecodeWalk.oValid). */
    val iValid = in(Bool())
    /** 순회 검산의 malformation 판정 (DecodeWalk.oMalformed). */
    val iMalformed = in(Bool())
    /** capability 종결 (DecodeWalk.oCapAbsent) — fault 아님 (§1.6.2). */
    val iCapAbsent = in(Bool())
    /** 순회 검산 기준 실행 유효 (DecodeWalk.oExecValid). */
    val iExecValid = in(Bool())
    /** 명령 워드 (DecodeWalk.oInstr — 워드0 예약 [15:8] 은 이미 0 마스킹). */
    val iInstr = in(Vec(Bits(32 bits), maxWords))
    /** 슬롯 서술자 — 실재 슬롯만 present (post_end_gated 를 지난 것). */
    val iSlotPresent = in(Vec(Bool(), ehSlots))
    /** 슬롯 종류 (사슬 포인터 authority 가 지목한 것). */
    val iSlotCode = in(Vec(Bits(KIND_W bits), ehSlots))
    /** 슬롯 워드0 의 명령 내 워드 오프셋 (8비트 = bh_len 값 공간). */
    val iSlotOff = in(Vec(UInt(8 bits), ehSlots))
    /** malformation sticky 의 명시적 해제 (§5.5). */
    val iFaultClear = in(Bool())

    // ── 합류된 판정면 — DecodeWalk 판정에 본문 예약 판정이 더해진 것 ──────
    val oValid = out(Bool())
    /** malformation — 순회 검산 ∨ 본문 예약 판정. 원인 코드 없음
      * (Decode.out_no_reason 과 같은 규율 — 예약값 원본이 반향될 자리가 없다). */
    val oMalformed = out(Bool())
    /** capability 종결 — 무변경 통과. 본문 판정은 능력 밖 사슬에 불참한다
      * (ISA-5 배타성 — DecodeWalk judge.mal 의 !capAbsent 와 같은 형태). */
    val oCapAbsent = out(Bool())
    /** 실행 인터페이스 유효 — 아래 모든 해석 산출의 게이트. */
    val oExecValid = out(Bool())

    // ── 해석 산출 — 전부 oExecValid 로 게이트. 비유효 명령은 전부 0 이라
    //    같은 판정을 받은 두 명령이 이 방출면에서 구별 불가능하다 (SEC-7 (ii)
    //    부류 — DecodeWalk outStage.masked 와 같은 규율). ──────────────────
    /** PORT — 결과 토큰 수신자 dest_node_id (LNID 16b 축자, §1.4.1). */
    val oPortPresent = out(Bool())
    val oPortDest    = out(UInt(Isa.LNID_W bits))
    /** IMM 계열 — 어느 폭이 실렸는가는 종류별 present 로 구별한다. */
    val oImm16Present = out(Bool())
    val oImm16        = out(Bits(16 bits))
    val oImm32Present = out(Bool())
    val oImm32        = out(Bits(32 bits))
    val oImm64Present = out(Bool())
    val oImm64        = out(Bits(64 bits))
    /** MEM — addr_mode 4b · stride 12b · 32b 오프셋 (§1.3.2). */
    val oMemPresent  = out(Bool())
    val oMemAddrMode = out(Bits(4 bits))
    val oMemStride   = out(Bits(12 bits))
    val oMemOffset   = out(Bits(32 bits))
    /** SUBSCRIPT — 등장 순서 j 자리에 j번째 EH 의 48b (O·A·B 각 16b).
      * 연접 의미(§4.2.3)의 소비는 EINSUM 쪽 몫 — 여기는 순서 보존 방출까지. */
    val oSubValid = out(Vec(Bool(), ehSlots))
    val oSubO     = out(Vec(Bits(16 bits), ehSlots))
    val oSubA     = out(Vec(Bits(16 bits), ehSlots))
    val oSubB     = out(Vec(Bits(16 bits), ehSlots))
    val oSubCount = out(UInt(OCC_W bits))
    /** OPREF — 등장 순서대로 A·B (§4.2.3, F_HAS_OPB 와 정합). LBID 는
      * noc_route[7:0] 전폭 — 값 공간 항상 0..255 (INV-T1, §1.4.3). */
    val oOprefAValid   = out(Bool())
    val oOprefALbid    = out(UInt(Isa.LBID_W bits))
    val oOprefASrcKind = out(UInt(RouteJudge.SRC_KIND_W bits))
    val oOprefBValid   = out(Bool())
    val oOprefBLbid    = out(UInt(Isa.LBID_W bits))
    val oOprefBSrcKind = out(UInt(RouteJudge.SRC_KIND_W bits))
    /** PRECISION — precision_mode 8b · dim_override 8b. */
    val oPrecPresent = out(Bool())
    val oPrecMode    = out(Bits(8 bits))
    val oPrecDim     = out(Bits(8 bits))
    /** ACCTGT → 목적 LBID — 재조립 개방 인터페이스. 결속 원천의 실물 배선:
      * 재조립 문맥은 개시 wave 디코드 시점에 열리고 결속 값은 이 필드다
      * (§4.3 「태그→구간 결속」 — D8 부류의 결속 원천). valid 는 실행 유효
      * 게이트를 지난 ACCTGT 존재 — malformed 명령이 문맥을 열지 못한다. */
    val oReasmBind = master(Flow(UInt(Isa.LBID_W bits)))
    /** 본문 예약 malformation 전용 sticky (합성 sticky, §5.5) —
      * 폴딩 규정 (§5.6 신호별 명시): OPREF 예약 니블·src_kind 예약값·ACCTGT
      * 예약 바이트 세 원인을 이 1비트로 접는다 (셋 다 같은 분류 —
      * malformation — 이고 같은 수리 주체 — 어셈블러 — 다, §1.6.2).
      * DecodeWalk.oFault(순회 검산 sticky)와는 접지 않는다 — 별도 신호. */
    val oFault = out(Bool())
  }

  // ── 슬롯 본문 워드 조회 — 8비트 전폭 등가 비교의 one-hot 표 선택 ─────────
  // 오프셋은 bh_len 값 공간(8비트) 그대로 표를 지난다 — 축소 resize 없음
  // (§1.3 함정의 조용한 절단 금지 부류를 색인에도 적용). 오프셋의 구조적
  // 상계 off(i) <= 1 + EH_WORDS_MAX*i <= maxWords - EH_WORDS_MAX (DecodeWalk
  // walk.off 주석의 증명) 때문에 실재 슬롯의 조회는 항상 표 안에 적중하고,
  // 표 밖 값(부재 슬롯의 off=0 파생 포함)은 아무 워드도 선택하지 않아 0 —
  // 어차피 아래 해석 전부가 present 게이트로 소거한다.
  val slots = new Area {
    /** 워드별 [31:16] — EH 워드0 의 본문 상위 16비트 (관측: _encode_eh 는
      * body<<16 | code<<8 | words 로 조립한다, 1891–1996 행). */
    private val hi16 = io.iInstr.map(w => w(31 downto 16))

    /** body(i) — 슬롯 i 워드0 의 본문 16비트. */
    val body = Vec(Bits(16 bits), ehSlots)
    /** w1(i)·w2(i) — 슬롯 i 의 후속 워드 (2·3워드 EH 만 의미를 갖는다). */
    val w1 = Vec(Bits(32 bits), ehSlots)
    val w2 = Vec(Bits(32 bits), ehSlots)
    for (i <- 0 until ehSlots) {
      val off0 = io.iSlotOff(i)
      val off1 = off0 + 1 // 8비트 산술 — maxWords <= 255 라 넘침 없음 (§1.3)
      val off2 = off0 + 2
      body(i) := gather((0 until maxWords).map(k => off0 === k), hi16)
      w1(i)   := gather((0 until maxWords).map(k => off1 === k), io.iInstr)
      w2(i)   := gather((0 until maxWords).map(k => off2 === k), io.iInstr)
    }
  }

  // ── 종류 적중과 순서 배정 ────────────────────────────────────────────────
  /** 슬롯 i 가 종류 code 의 실재 EH 인가 — 4비트 코드 전체 비교 (비트 슬라이스
    * 판정 아님). 모든 본문 판정·해석의 전건이 present 인 것이 §1.6.1 함정
    * (「존재하지 않는 EH 의 본문 잔여값은 판정 대상이 아니다」)의 구현이다. */
  private def hit(i: Int, code: Int): Bool =
    io.iSlotPresent(i) && io.iSlotCode(i) === B(code, KIND_W bits)

  /** sel 로 마스킹한 값들의 OR 접기 — one-hot 이 구조로 보장되는 자리
    * (단독 종류는 DecodeWalk dupBad 가, A·B 는 계수 비교가 보장)에만 쓴다. */
  private def gather(sel: collection.Seq[Bool], vals: collection.Seq[Bits]): Bits =
    sel.zip(vals).map { case (s, v) => s ? v | B(0, v.getWidth bits) }.reduce(_ | _)

  /** i 이전 슬롯 중 sel 이 선 개수 — §4.2.3 「등장 순서대로」의 순서 축. */
  private def occBefore(sel: collection.IndexedSeq[Bool], i: Int): UInt =
    if (i == 0) U(0, OCC_W bits)
    else (0 until i).map(j => sel(j).asUInt(OCC_W bits)).reduce(_ + _)

  val parse = new Area {
    val isPort   = Vec((0 until ehSlots).map(hit(_, EhCode.PORT)))
    val isImm16  = Vec((0 until ehSlots).map(hit(_, EhCode.IMM16)))
    val isImm32  = Vec((0 until ehSlots).map(hit(_, EhCode.IMM32)))
    val isImm64  = Vec((0 until ehSlots).map(hit(_, EhCode.IMM64)))
    val isMem    = Vec((0 until ehSlots).map(hit(_, EhCode.MEM)))
    val isSub    = Vec((0 until ehSlots).map(hit(_, EhCode.SUBSCRIPT)))
    val isOpref  = Vec((0 until ehSlots).map(hit(_, EhCode.OPREF)))
    val isPrec   = Vec((0 until ehSlots).map(hit(_, EhCode.PRECISION)))
    val isAcctgt = Vec((0 until ehSlots).map(hit(_, EhCode.ACCTGT)))
    // NOP_PAD 는 해석 산출이 없다 — 정렬 전용, 효과 없음 (§4.2.3).

    // 단독 종류 (반복 = malformation, §4.2.3) — 존재는 OR, 값은 마스킹 OR.
    // 적법 명령에서 one-hot 이고, 중복 명령은 DecodeWalk dupBad → 방출 게이트.
    val portPresent = isPort.reduce(_ || _)
    /** PORT 본문 = dest_node_id 축자 — 비트 i 가 비트 i (§1.4.1, asm 1928 행). */
    val portDest = gather(isPort, slots.body).asUInt

    val imm16Present = isImm16.reduce(_ || _)
    val imm16        = gather(isImm16, slots.body) // w0[31:16] (asm 1932 행)
    val imm32Present = isImm32.reduce(_ || _)
    val imm32        = gather(isImm32, slots.w1) // w1 전폭 (asm 1935 행)
    val imm64Present = isImm64.reduce(_ || _)
    /** w2 = 상위 32 ‖ w1 = 하위 32 (asm 1938–1942 행). */
    val imm64 = gather(isImm64, slots.w2) ## gather(isImm64, slots.w1)

    val memPresent = isMem.reduce(_ || _)
    /** w0[19:16] = addr_mode · w0[31:20] = stride (asm 1947 행: upper 조립). */
    val memAddrMode = gather(isMem, slots.body.map(_(3 downto 0)))
    val memStride   = gather(isMem, slots.body.map(_(15 downto 4)))
    val memOffset   = gather(isMem, slots.w1) // w1 = 32b 오프셋 (asm 1948 행)

    val precPresent = isPrec.reduce(_ || _)
    /** w0[23:16] = precision_mode · w0[31:24] = dim_override (asm 1992 행). */
    val precMode = gather(isPrec, slots.body.map(_(7 downto 0)))
    val precDim  = gather(isPrec, slots.body.map(_(15 downto 8)))

    val acctgtPresent = isAcctgt.reduce(_ || _)
    /** w0[31:24] = 목적 LBID — 읽기측 LBID 와 같은 이름 공간 (§1.4.7). */
    val acctgtLbid = gather(isAcctgt, slots.body.map(_(15 downto 8))).asUInt

    // OPREF — 등장 순서대로 A·B (§4.2.3). 3회 이상은 DecodeWalk dupBad 몫.
    val oprefA = Vec((0 until ehSlots)
      .map(i => isOpref(i) && occBefore(isOpref, i) === 0))
    val oprefB = Vec((0 until ehSlots)
      .map(i => isOpref(i) && occBefore(isOpref, i) === 1))
    val oprefAValid = oprefA.reduce(_ || _)
    val oprefBValid = oprefB.reduce(_ || _)
    /** w0[31:24] = noc_route 전폭 = LBID · w0[19:16] = src_kind
      * (asm 1987 행: upper = route<<8 | kind — RouteJudge 관측 재확인). */
    val oprefALbid    = gather(oprefA, slots.body.map(_(15 downto 8))).asUInt
    val oprefASrcKind = gather(oprefA, slots.body.map(_(3 downto 0))).asUInt
    val oprefBLbid    = gather(oprefB, slots.body.map(_(15 downto 8))).asUInt
    val oprefBSrcKind = gather(oprefB, slots.body.map(_(3 downto 0))).asUInt

    // SUBSCRIPT — 등장 순서 j 자리 배정 (§4.2.3 연접의 순서 보존).
    val subSel = Vec((0 until ehSlots).map { j =>
      Vec((0 until ehSlots).map(i => isSub(i) && occBefore(isSub, i) === j))
    })
    val subValid = Vec((0 until ehSlots).map(j => subSel(j).reduce(_ || _)))
    /** w0[31:16] = O축 · w1[31:16] = A축 · w1[15:0] = B축 (asm 1954–1957 행). */
    val subO = Vec((0 until ehSlots).map(j => gather(subSel(j), slots.body)))
    val subA = Vec((0 until ehSlots)
      .map(j => gather(subSel(j), slots.w1.map(_(31 downto 16)))))
    val subB = Vec((0 until ehSlots)
      .map(j => gather(subSel(j), slots.w1.map(_(15 downto 0)))))
    val subCount = (0 until ehSlots).map(i => isSub(i).asUInt(OCC_W bits)).reduce(_ + _)
  }

  // ── 본문 예약 판정 — DecodeWalk 판정점에의 합류 (Decode.resv_judged 예고) ─
  // 예약 필드 불투과의 구조 (SEC-7): 아래 세 예약 슬라이스 — body[7:4](OPREF
  // 폐지 니블)·body[3:0]의 예약값 구간(src_kind ≥ 3)·body[7:0](ACCTGT 예약
  // 바이트) — 의 fanout 은 이 Area 의 비교기뿐이다. 해석 산출(위 parse)은
  // 예약 비트를 어떤 필드·색인·유효에도 싣지 않고, 판정은 아래 1비트
  // 등급(bodyMal)으로만 나간다 — 예약값 원본이 방출면에 반향될 자리가 없다.
  val judge = new Area {
    /** OPREF [23:20] 폐지 니블 ≠ 0 — malformation (§1.4.6 · §5.7).
      * 실재 OPREF 슬롯에 대해서만 발화한다 (§1.6.1 함정). */
    val oprefResvBad = (0 until ehSlots)
      .map(i => parse.isOpref(i) && slots.body(i)(7 downto 4) =/= 0)
      .reduce(_ || _)
    /** src_kind ≥ 3 = 예약 → 오류 (§1.4.3 표) — RouteJudge 가 디코드 경계로
      * 넘긴 결정의 실물. 4비트 전폭 비교 (값 구간 판정 — 비트 슬라이스 아님). */
    val srcKindBad = (0 until ehSlots)
      .map(i => parse.isOpref(i) &&
        slots.body(i)(3 downto 0).asUInt >= SRC_KIND_RESERVED_MIN)
      .reduce(_ || _)
    /** ACCTGT [23:16] 예약 바이트 ≠ 0 — malformation (§1.4.7 · §5.7). */
    val acctgtResvBad = (0 until ehSlots)
      .map(i => parse.isAcctgt(i) && slots.body(i)(7 downto 0) =/= 0)
      .reduce(_ || _)

    /** 본문 malformation — capability 종결이 맨 앞이다: 능력 밖 사슬은 본문
      * 판정의 대상이 아니어서 두 종결이 동시에 서지 않는다 (ISA-5 —
      * DecodeWalk judge.mal 의 !capAbsent 와 같은 형태). */
    val bodyMal = !io.iCapAbsent && (oprefResvBad || srcKindBad || acctgtResvBad)
  }

  // ── 합류된 판정 방출 — 게이트이지 분기가 아니다 (§1.6.1 · §5.3) ─────────
  io.oValid     := io.iValid
  io.oMalformed := io.iMalformed || judge.bodyMal
  io.oCapAbsent := io.iCapAbsent
  io.oExecValid := io.iExecValid && !judge.bodyMal

  /** 방출 게이트 — 모든 해석 산출의 유일한 게이트. malformed·capability
    * 명령의 본문이 하류에 실리지 않는다 (§1.6.1). */
  private val emit = io.oExecValid

  private def gatedB(pres: Bool, v: Bits): Bits = (emit && pres) ? v | B(0, v.getWidth bits)
  private def gatedU(pres: Bool, v: UInt): UInt = (emit && pres) ? v | U(0, v.getWidth bits)

  io.oPortPresent := emit && parse.portPresent
  io.oPortDest    := gatedU(parse.portPresent, parse.portDest)

  io.oImm16Present := emit && parse.imm16Present
  io.oImm16        := gatedB(parse.imm16Present, parse.imm16)
  io.oImm32Present := emit && parse.imm32Present
  io.oImm32        := gatedB(parse.imm32Present, parse.imm32)
  io.oImm64Present := emit && parse.imm64Present
  io.oImm64        := gatedB(parse.imm64Present, parse.imm64)

  io.oMemPresent  := emit && parse.memPresent
  io.oMemAddrMode := gatedB(parse.memPresent, parse.memAddrMode)
  io.oMemStride   := gatedB(parse.memPresent, parse.memStride)
  io.oMemOffset   := gatedB(parse.memPresent, parse.memOffset)

  for (j <- 0 until ehSlots) {
    io.oSubValid(j) := emit && parse.subValid(j)
    io.oSubO(j)     := gatedB(parse.subValid(j), parse.subO(j))
    io.oSubA(j)     := gatedB(parse.subValid(j), parse.subA(j))
    io.oSubB(j)     := gatedB(parse.subValid(j), parse.subB(j))
  }
  io.oSubCount := emit ? parse.subCount | U(0, OCC_W bits)

  io.oOprefAValid   := emit && parse.oprefAValid
  io.oOprefALbid    := gatedU(parse.oprefAValid, parse.oprefALbid)
  io.oOprefASrcKind := gatedU(parse.oprefAValid, parse.oprefASrcKind)
  io.oOprefBValid   := emit && parse.oprefBValid
  io.oOprefBLbid    := gatedU(parse.oprefBValid, parse.oprefBLbid)
  io.oOprefBSrcKind := gatedU(parse.oprefBValid, parse.oprefBSrcKind)

  io.oPrecPresent := emit && parse.precPresent
  io.oPrecMode    := gatedB(parse.precPresent, parse.precMode)
  io.oPrecDim     := gatedB(parse.precPresent, parse.precDim)

  // 재조립 결속 원천 (§4.3) — D8 부류 결속의 실물 배선. 게이트를 지난
  // ACCTGT 만 문맥을 연다 — malformed wave 는 결속을 만들지 못한다.
  io.oReasmBind.valid   := emit && parse.acctgtPresent
  io.oReasmBind.payload := gatedU(parse.acctgtPresent, parse.acctgtLbid)

  // 본문 malformation 전용 sticky — 세운다 / 명시적 해제 외엔 내리지 않는다
  // (§5.5). capability 종결 불참 (§1.6.2 — bodyMal 의 !iCapAbsent 가 구조).
  io.oFault := StickyFault(set = io.iValid && judge.bodyMal, clear = io.iFaultClear)
}
