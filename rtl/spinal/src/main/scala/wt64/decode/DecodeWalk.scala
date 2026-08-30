// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// DecodeWalk — EH 사슬 고정 순회 + 검산 + malformation·capability 판정.
//
// 선-formal 모델(의사-명세): rtl/formal/tla/Walk.tla · Decode.tla.
// 정본: §4.2 (END authority · 검산 3중 · 미지 EH · 반복 규약),
//       §4.2.2 검산 규범 2항 · 함정 「END 미출현은 순회로 구별할 수 없다 —
//       선언이 가른다」: declLen > 구현 상한 = 능력 부재 (순회 전, 선언만으로)
//       / declLen 이내 END 부재 = malformation. 두 조건은 서로소 — ISA-5 가
//       구조로 성립한다,
//       §1.3 「최대 길이」 — 지원하지 않는 길이는 능력 부재로 보고한다.
//       바이너리는 옳다 — 오류가 아니다 (§1.6.2 오류 3분류),
//       §4.2.1 순회 규범 「순회는 슬롯 상한만큼 고정 횟수로 돈다. 종료 표식을
//       만난 뒤의 슬롯은 순회하되 효과가 없어야 한다」 — 조기 탈출 금지,
//       멈추는 것은 순회가 아니라 효과다,
//       §1.3 함정 「bh_len 의 실효 폭은 8비트가 아니다」 — 비교 폭 = 선언 폭
//       8비트 전체, 조용한 절단 금지,
//       §1.6.1 판정 위치 규범 — 디코드 경계 · 순회 종료 직후 · 실행 전 (D14).
//       「진입하지 않는다」는 효과의 문장이지 상태열의 문장이 아니다,
//       §1.3.4 둘째 헤더 — CH (Castagnoli Header, W8): word0 의 next_hdr ≠
//       END ⇔ word1 = CH (EH 아님 — 회계·코드점·반복 규약 무관, 순회 대상
//       아님). 재계산 대조 불일치 = malformation + loud, 판정은 디코드 경계.
//       = END ⇔ CH 없음 (bh_len = 1). bh_len 은 CH 포함 물리 워드 총수,
//       §5.7 예약 필드 「0이 아니면 덫」 · §5.8 SEC-7 예약 필드 불투과.
//
// 범위: 순회·검산(CH 재계산 대조 포함)까지다. EH 본문 해석(즉치·MEM·
// SUBSCRIPT·OPREF·PRECISION 의 내용과 본문 내 판정 — OPREF CRC-4 검산 ·
// src_kind 예약값)은 OperandDecode(2차 파도 착지)가 이 모듈의 방출면
// (슬롯 서술자 + 명령 워드)을 받아 같은 판정점에 합류시킨다.
// 플래그–EH 대응 검사(§1.6.1 항2)는 여전히 미착지다.
//
// ── GUARD-MAP ────────────────────────────────────────────────────────────
// GUARD-MAP: Walk.end_authority   -> walk.ended 는 오직 사슬 포인터의 END(0x0)로만 선다 — judge.declLen 은 judge.lenBad 비교기에만 들어가고 종료 판정·보폭 계산에 불참 (§4.2.2 「길이를 authority 로 쓰면 길이 검산이 항진명제가 된다」)
// GUARD-MAP: Walk.len_check       -> judge.lenBad — endSeen 일 때 declLen(8비트 전폭) =/= walk.off(ehSlots) 이면 malformed. 양변 모두 UInt(8 bits) — §1.3 함정의 조용한 절단 금지
// GUARD-MAP: Walk.cap_declared    -> judge.capAbsent — 순회 *전* 선언 비교: declLen(8비트 전폭) > maxWords(구현 슬롯 상한의 선언 단위 환산 = 1(기본 헤더) + 1(CH) + ehSlots*EH_WORDS_MAX) 이면 capability 종결. StickyFault 불참 — 능력 부재는 오류가 아니다 (§4.2.2 검산 규범 2항 · §1.3 「최대 길이」 · §1.6.2). 관측면은 oCapAbsent 종결 등급 1비트
// GUARD-MAP: Walk.cap_check       -> judge.capBad — 선언 이내(!capAbsent)인데 정적 ehSlots 완주 후 endSeen 부재이면 malformed — 「들어간다」고 선언하고 실물이 아닌 자기모순 (§4.2.2 검산 규범 3항). capAbsent 와 서로소라 ISA-5 분류 배타성이 구조로 성립한다
// GUARD-MAP: Walk.junk_check      -> judge.junkBad — catalogWords 표 조회(kindDefined)로 END 이전 슬롯의 미지 종류이면 malformed. 비트 슬라이스 판정 아님 — 16진 코드 전체가 표를 지난다
// GUARD-MAP: Walk.post_end_gated  -> 순회는 정적 for 로 ehSlots 회 완전 전개 — 조기 탈출이 구조적으로 불가능하다. 모든 슬롯 효과(off 증분·검산 기여·oSlot* 방출)가 walked(i) = !ended(i) 로 게이트된다
// GUARD-MAP: Decode.resv_judged      -> judge.resvBad — 기본 헤더 예약 [15:12] =/= 0 이면 malformed (§5.7 — [11:8] 은 W1 부터 opcode_ext 라 예약이 아니다). EH 본문 내부의 판정(OPREF CRC-4 · src_kind 예약값)은 OperandDecode 가 같은 판정점(oExecValid 이전)에 합류시킨다 — 모델 없는 모듈이라 VERIFIES 경로(body_judge.sby)다
// GUARD-MAP: Decode.ch_judged        -> judge.chBad — next_hdr(word0 [23:20]) =/= END 인 명령의 word1 은 둘째 헤더 CH 다 (§1.3.4): CH 자기 워드를 제외한 전 워드(word0·word2‥bh_len−1, 워드 오름차순·워드당 리틀엔디언 바이트 직렬)의 CRC-32C(RFC 3720 관례) 재계산이 iInstr(1) 과 다르면 malformed. 판정은 순회 종료 직후 judge.mal 합류 — 래치 이전 = D14 정합. EH-0(next_hdr = END) 명령에는 CH 가 없어 판정이 서지 않는다
// GUARD-MAP: Decode.mal_carried      -> 판정은 outStage.rMal·rCapa 두 래치에 서고 rValid 와 같은 레지스터 단에서 함께 이동한다. 소비 지점(oMalformed·oCapAbsent·oExecValid·oFault set)은 전부 그 래치들만 읽는다 — 재계산 없음
// GUARD-MAP: Decode.resv_not_indexed -> judge.resvFld 의 fanout 은 judge.resvBad 비교기 단 하나다. 이 모듈의 색인 축(walk.off 버퍼 색인·슬롯 오프셋)은 kind 표 조회 결과와 END 게이트만으로 계산되어 예약 비트가 어떤 색인에도 기여하지 않는다 (변환 저장 조회는 이 모듈에 없다 — 그 키의 불투과는 조회 유닛의 같은 가드가 진다)
// GUARD-MAP: Decode.resv_not_timed   -> 순회 완전 전개 + 무정지 고정 1사이클 래치 — 이 모듈에 데이터 의존 제어가 없어 어떤 명령 비트도(예약 포함) 소요 tick 을 바꿀 수 없다 (§3.2 2단계와 정합)
// GUARD-MAP: Decode.resv_not_echoed  -> 방출면(oInstr·oSlot*·oValid·oMalformed·oCapAbsent·oExecValid·oFault) 어디에도 예약 비트가 실리지 않는다 — outStage.masked 가 oInstr 워드0 [15:12] 을 0 으로 지워 방출하므로 같은 판정을 받은 두 명령은 방출면에서 구별 불가능하다. [11:8] opcode_ext 는 opcode 가 그렇듯 정당한 구별 인자라 방출된다 — SEC-7 (ii) 재유도 (§5.8)
// GUARD-MAP: Decode.fault_not_folded -> oFault 는 malformation 전용 sticky(공용 StickyFault)다 — 이 모듈에 미적중 sticky 표시가 없고, capability 종결은 fault 를 세우지 않으며(§1.6.2 — 능력 부재는 오류가 아니다), 이 신호의 폴딩 여부를 여기 명시한다: 폴딩하지 않는다 (§5.6 「malformation 은 미적중으로 접지 않는다」)
// GUARD-MAP: Decode.out_no_reason    -> STRUCTURAL(port-absence) — 판정 방출은 {oExecValid, oMalformed, oCapAbsent} 종결 등급 비트뿐 — oCapAbsent 는 §1.6.2 의 셋째 분류(종결 종류)이지 원인 코드가 아니다. 원인 코드 채널 자체가 없어 예약값 원본이 승인 경계로 반향될 자리가 없다 (§5.6 폴딩 규범 2항의 reason 확장은 이 모듈 밖이며, 추가 시 예약값 원본 금지가 그 확장의 의무다)
// GUARD-MAP: Decode.verdict_ungated  -> outStage.rMal 의 fanout 은 oMalformed·oExecValid 게이트·oFault set, rCapa 의 fanout 은 oCapAbsent·oExecValid 게이트뿐이다 — 단계 선택·mux 제어에 불참. capability 로 조기에 판정이 서도 순회는 상한까지 완주한다 (D14 상태열 균일). 판정은 경로를 가르지 않고 결과를 게이트한다 (§3.2 · §1.6.1 「미진입은 효과의 문장」)
// (이관 기록: Decode.lookup_unbranched · evict_inline · stall_uniform 의
//  DELEGATED 3줄은 조회를 품는 상태열 유닛(HiuPipeline)의 착지와 함께 그쪽
//  CHECK 줄로 **이동**했다 — 가드당 저장소 전체 정확히 1줄 규약.)
// ─────────────────────────────────────────────────────────────────────────
//
// ── 인코딩 관측 기록 — 인코딩 개정 파도(W1~W8) 반영 기준 ─────────────────
//    (허용 오라클: asm/wavetensor_asm.py encode_pass. 파도 전 실측 + 파도
//     핀 명세의 확정 문면 — 어셈블러 행 번호 인용은 파도 편집으로 밀리므로
//     여기서는 지웠다.)
//  · 기본 헤더(word0) = opcode 하위 8b [31:24] | next_hdr [23:20] |
//    flags [19:16] | 예약 [15:12](반드시 0, §5.7) | opcode_ext [11:8] |
//    bh_len [7:0]. opcode 는 12비트 — 물리적으로 [31:24](하위 8b) 와
//    [11:8](확장 니블)로 갈린다 (W1). 기존 opcode 는 0x0 프리픽스라 확장
//    니블이 0 — 기존 바이너리의 word0 은 무변경.
//  · word0 의 next_hdr ≠ END 이면 word1 = CH (둘째 헤더, W8) — 32비트 전부
//    CRC-32C. EH 가 아니다 (EH 회계·코드점·반복 규약 무관·순회 대상 아님).
//    EH 순회의 시작 워드는 word2 다. next_hdr = END 이면 CH 없음 (bh_len=1).
//  · bh_len = CH 포함 물리 워드 총수: EH-0 = 1 · EH≥1 = 2 + Σ EH 워드 수.
//    최대 14워드 = 448비트 (EH 예산 12워드 불변).
//  · EH 워드0 = body<<16 | code<<8 | words — [15:12] = 다음 EH 종류,
//    [11:8] = 자기 EH 종류, [7:0] = 워드 수. 정본 §1.3.3 표와 일치,
//    파도 무변경.
//  · END(0x0) 는 next 필드 값으로만 나타나는 sentinel 이다 — 자기 워드가 없다.
//  · 워드 i 는 비트 32i (리틀엔디언 워드 배치).
//  · 워드 수: PORT/IMM16/OPREF/PRECISION/NOP_PAD = 1, IMM32/MEM/SUBSCRIPT = 2,
//    IMM64 = 3 — 정본 §1.3.2 카탈로그와 일치.
//  · ACCTGT(0x9) 는 어셈블러·isa/wt64v1_isa.json 에 이번 파도도 미배정이다
//    (eh_codes 0x9 배정·표면은 Di 실장 파도 몫 — P4 범위 제한). 원천은 정본
//    §1.4.7 (Isa.EhCode.ACCTGT). 워드 수 1 은 정본 표에서 온다.
//    귀결 (수리 라운드 1 기록): legacy eh 표(include/generated/
//    isa_eh_codes.vh)에는 0x9 행 자체가 없어 legacy 구조 판정은 0x9 를
//    미지 종류 후보로 처분하고, 이 카탈로그는 0x9 를 정의 종류(1워드·
//    반복상한 1)로 순회한다 — 0x9 를 나르는 명령의 구조 판정이 두 층에서
//    갈릴 수 있는 창이다. truth table 은 acctgt 0점, encwave 계획도 축
//    무변경이라 어떤 벡터도 이 창을 재지 않는다. 배정 커밋(Di 실장 파도,
//    0x79 재행과 함께)은 JSON eh_codes + legacy 표 재생성 + 재캡처를 같은
//    커밋에 실어야 한다. 상주 트립와이어: asm/test_wavetensor_asm.py
//    TestEhAcctgtTwoLayerTripwire 가 0x9 부재를 핀해 배정 시 의식적 갱신을
//    강제한다.
//  · W2 규범 기록 — 12b opcode 를 8b 로 접는 모든 지점(legacy fp ROM 게이트
//    의 in_fp_block, 미래 디스패치의 StepSequencer KEY_OP_W=8 접힘)은 반드시
//    opcode_ext == 0x0 검사를 동반해야 한다. 안 넣으면 0x47B 가 0x07B 행에
//    얹히는 공허 PASS 다. 실물 게이트는 scripts/gen_isa_tables.py 소관.
//  · W3 규범 기록 — 미배정 opcode = malformation, 예비 영역(0x8##–0xF##)
//    전체 = malformation (claim 전까지). 영역 구획은 배정 절차 규범이지
//    하드웨어 판정이 아니다 — 하드웨어가 아는 것은 배정된 opcode 뿐 (§1.3.1).
//    이 순회 모듈은 opcode 를 소비하지 않으므로 그 판정의 거처가 아니다 —
//    opcode 적법성 판정은 opcode 소비자(legacy 표 게이트·미래 디스패치) 몫.
// ─────────────────────────────────────────────────────────────────────────
package wt64.decode

import spinal.core._
import wt64.{Isa, StickyFault}

/** EH 사슬 고정 순회 + 검산 + malformation·capability 판정.
  *
  * 접수한 명령 버퍼를 조합 논리로 완전 전개된 고정 순회에 태워 슬롯 서술자를
  * 뽑고, 순회 종료 직후 종결을 **한 번** 판정해 (D14) 결과 전체를
  * 한 레지스터 단에 싣는다. 종결은 셋으로 갈린다 — 실행 유효 · malformation
  * (loud fault) · capability(선언이 구현 상한 초과 — 오류가 아니다, §1.6.2).
  * capability 는 순회 전에 선언만으로 서지만 순회는 그래도 상한까지 완주한다.
  * 모든 명령이 정확히 같은 1사이클 경로를 지난다 —
  * 판정 결과·명령 내용 어느 쪽도 단계를 바꾸지 못한다 (§1.6.1 · §5.3).
  *
  * @param ehSlots EH 슬롯 상한 — 고정 순회의 횟수 (§4.2.1). 형상 파라미터다
  *                (§1.3 「이 상한은 형상 파라미터이지 ISA 상수가 아니다」).
  *                기본값 4 는 정본 기본 형상. Wt64Config 승격 후보 —
  *                기존 slotCap(§2.4.1 결과 슬롯)과는 다른 축이라 새 이름이 필요하다.
  */
class DecodeWalk(val ehSlots: Int = 4) extends Component {
  import Isa.EhCode

  // 축퇴 배제 — Walk.tla ASSUME Cap >= 2 와 동형: 슬롯이 1개면
  // post_end_gated 가 볼 「END 뒤의 슬롯」이 원리적으로 없다.
  require(ehSlots >= 2, "축퇴 형상 금지 — Walk.tla ASSUME Cap >= 2")

  /** EH 종류 코드의 폭 — 4비트. 어셈블러 관측(기본 헤더 [23:20] ·
    * EH 워드 [15:12]/[11:8])이며 형상과 무관한 ISA 사실이다 (INV-T1).
    * Isa 승격 후보 — Isa.EH_CODE_W(8) 는 next(4)‖self(4) 합폭이다. */
  val KIND_W = 4

  /** 카탈로그 최대 EH 워드 수 (IMM64 = 3, §1.3.2) — ISA 사실이지 형상이 아니다. */
  val EH_WORDS_MAX = 3

  /** 명령 버퍼 워드 수 — 형상(기본 14 = §1.3 최대 448비트): 기본 헤더 1 +
    * CH 1 + EH 예산 ehSlots*EH_WORDS_MAX. CH 는 EH-조건부(next_hdr ≠ END)
    * 지만 버퍼는 최악 길이를 든다 (W8). */
  val maxWords = 1 + 1 + ehSlots * EH_WORDS_MAX
  // bh_len 은 선언 폭 8비트 전체로 비교한다 (§1.3 함정). 오프셋 산술을 같은
  // 8비트에서 하므로, 버퍼가 그 값 공간을 넘는 형상은 여기서 거절한다.
  require(maxWords <= 255, "오프셋·길이 산술이 bh_len 선언 폭 8비트 안에 있어야 한다 (§1.3)")

  /** EH 카탈로그 — 종류 → 워드 수 (§1.3.2 표 + §1.4.7 ACCTGT, 어셈블러 관측과
    * 일치). END(0x0) 는 슬롯 종류가 아니라 종료 sentinel 이므로 표에 없다 —
    * 표 부재 = 미지 종류 = malformation (§4.2.2 규범 3항). */
  private val catalogWords: Map[Int, Int] = Map(
    EhCode.PORT      -> 1,
    EhCode.IMM16     -> 1,
    EhCode.IMM32     -> 2,
    EhCode.IMM64     -> 3,
    EhCode.MEM       -> 2,
    EhCode.SUBSCRIPT -> 2,
    EhCode.OPREF     -> 1,
    EhCode.PRECISION -> 1,
    EhCode.ACCTGT    -> 1,
    EhCode.NOP_PAD   -> 1,
  )

  /** §4.2.3 반복 규약 (전수 표) — 종류 → 최대 등장 횟수. 표에 없는 종류
    * (SUBSCRIPT 연접 · NOP_PAD 정렬)는 무제한이다. */
  private val repeatCap: Map[Int, Int] = Map(
    EhCode.PORT      -> 1,
    EhCode.IMM16     -> 1,
    EhCode.IMM32     -> 1,
    EhCode.IMM64     -> 1,
    EhCode.MEM       -> 1,
    EhCode.PRECISION -> 1,
    EhCode.ACCTGT    -> 1, // 누산 대상은 하나 — 재조립 결속 원천의 유일성 (§1.4.7 · §4.2.3)
    EhCode.OPREF     -> 2, // 등장 순서대로 A·B — F_HAS_OPB 와 정합 (§4.2.3)
  )
  catalogWords.foreach { case (_, w) =>
    require(w >= 1 && w <= EH_WORDS_MAX, "카탈로그 워드 수가 버퍼 산정과 어긋난다")
  }

  val io = new Bundle {
    /** 이번 사이클에 명령 버퍼가 유효한가. */
    val iValid = in(Bool())
    /** 명령 버퍼 — 워드 i 가 비트 32i (리틀엔디언 워드 배치, 어셈블러 관측). */
    val iInstr = in(Vec(Bits(32 bits), maxWords))
    /** malformation sticky 의 명시적 해제 (§5.5 — 해제 외엔 내리지 않는다). */
    val iFaultClear = in(Bool())

    /** 판정 완료 — 접수 다음 사이클, 명령 내용과 무관하게 균일하다. */
    val oValid = out(Bool())
    /** 판정 등급 — malformed 인가. 원인 코드 없음. */
    val oMalformed = out(Bool())
    /** 종결 등급 — capability 인가. 선언(bh_len)이 구현 상한을 넘어 이 기계가
      * 못 받는 명령이다 — 바이너리는 옳고, malformed 와 다른 신호이며, fault
      * 가 아니다 (§4.2.2 검산 규범 2항 · §1.6.2 오류 3분류). oMalformed 와
      * 동시에 서지 않는다 — ISA-5 분류 배타성. */
    val oCapAbsent = out(Bool())
    /** 실행 인터페이스 유효 — malformed·capability 이면 유효가 실리지
      * 않는다 (§1.6.1). 판정은 이 게이트로만 작용한다 — 경로는 가르지 않는다. */
    val oExecValid = out(Bool())
    /** 명령 워드 전달 (2차 파도의 본문 해석용). 워드0 예약 [15:12] 은 0 으로
      * 지워져 있다 — 예약값은 판정에 소비된 뒤 어떤 방출면에도 실리지 않는다.
      * [11:8] 은 opcode_ext(W1) 라 지우지 않고 방출한다. */
    val oInstr = out(Vec(Bits(32 bits), maxWords))
    /** 슬롯 서술자 — END 이전에 실재하는 슬롯만 present (post_end_gated). */
    val oSlotPresent = out(Vec(Bool(), ehSlots))
    /** 슬롯 종류 (사슬 포인터가 지목한 것). 비어 있으면 END(0x0). */
    val oSlotCode = out(Vec(Bits(KIND_W bits), ehSlots))
    /** 슬롯 워드0 의 명령 내 워드 오프셋. 폭 8비트 = bh_len 값 공간 (형상 무관). */
    val oSlotOff = out(Vec(UInt(8 bits), ehSlots))
    /** malformation 전용 sticky fault — 합성되는 상태 비트, 폴딩하지 않는다. */
    val oFault = out(Bool())
  }

  // ── 종류 표 — 표 조회다. 미지 판정도 표에서 온다 (비트 슬라이스 판정 금지) ──
  private val kindDefined = Vec((0 until (1 << KIND_W)).map(c => Bool(catalogWords.contains(c))))
  private val kindWords   = Vec((0 until (1 << KIND_W)).map(c => U(catalogWords.getOrElse(c, 1), 8 bits)))

  // ── 고정 순회 (§4.2.1) — 정적 전개. 조기 탈출이 구조적으로 불가능하다 ──────
  val walk = new Area {
    // 순회가 읽는 것은 각 워드의 하위 16비트뿐이다 —
    // [15:12] 다음 종류 · [11:8] 자기 종류 · [7:0] 워드 수 (어셈블러 관측).
    // 본문 [31:16] 은 여기서 해석하지 않는다 (2차 파도).
    val lo16 = Vec(io.iInstr.map(w => w(15 downto 0)))

    /** ptr(i) — 슬롯 i 의 종류를 지목하는 사슬 포인터.
      * ptr(0) 은 기본 헤더 [23:20], 이후는 앞 슬롯 워드0 의 [15:12]. */
    val ptr    = Vec(Bits(KIND_W bits), ehSlots + 1)
    /** ended(i) — 슬롯 i 지시 시점에 사슬이 이미 끝났는가. END 만이 세운다. */
    val ended  = Vec(Bool(), ehSlots + 1)
    /** walked(i) — 슬롯 i 가 실재하는가. 모든 슬롯 효과의 게이트다. */
    val walked = Vec(Bool(), ehSlots)
    /** off(i) — 슬롯 i 워드0 의 워드 오프셋. 8비트 산술 (§1.3). */
    val off    = Vec(UInt(8 bits), ehSlots + 1)
    val head     = Vec(Bits(16 bits), ehSlots)
    val selfCode = Vec(Bits(KIND_W bits), ehSlots)
    val wordsFld = Vec(UInt(8 bits), ehSlots)
    val defd     = Vec(Bool(), ehSlots)
    val stepW    = Vec(UInt(8 bits), ehSlots)

    ptr(0)   := io.iInstr(0)(23 downto 20)
    ended(0) := ptr(0) === B(EhCode.END, KIND_W bits)
    // W8: next_hdr ≠ END ⇒ word1 = CH (둘째 헤더 — EH 아님, 순회 대상 아님)
    // 라 EH 순회의 시작 워드는 word2 다 (§4.2.1). = END ⇒ CH 없음 — 걷지
    // 않는 시작 오프셋 1 (어차피 walked 전부 False).
    off(0)   := ended(0) ? U(1, 8 bits) | U(2, 8 bits)

    for (i <- 0 until ehSlots) {
      walked(i) := !ended(i)
      // off(i) <= 2 + EH_WORDS_MAX*i < maxWords 가 구조적으로 성립하므로
      // (시작 오프셋 상한 2 = CH 존재 갈래 · 표의 보폭 상한 EH_WORDS_MAX ·
      // 미지 보폭 1) 이 축소 resize 는 값을 잃지 않는다 — 조용한 절단이
      // 아니라 증명된 상계다.
      head(i)     := lo16(off(i).resize(log2Up(maxWords) bits))
      selfCode(i) := head(i)(11 downto 8)
      wordsFld(i) := head(i)(7 downto 0).asUInt
      defd(i)     := kindDefined(ptr(i).asUInt)
      // 보폭은 표에서 온다 — 미지 종류(이미 malformation)는 1 워드로 전진해
      // 순회를 유계로 유지한다. 워드 수 필드는 보폭이 아니라 검산 대상이다.
      stepW(i)    := kindWords(ptr(i).asUInt)
      ptr(i + 1)   := head(i)(15 downto 12)
      ended(i + 1) := ended(i) || ptr(i + 1) === B(EhCode.END, KIND_W bits)
      // END 뒤의 슬롯은 오프셋에도 기여하지 않는다 (post_end_gated).
      off(i + 1)   := off(i) + (walked(i) ? stepW(i) | U(0, 8 bits))
    }
  }

  // ── CH (둘째 헤더, W8) — CRC-32C 재계산의 데이터패스 (§1.3.4) ────────────
  // 관례 = RFC 3720 (iSCSI): 다항식 0x1EDC6F41(정규형) / 0x82F63B78(반사형),
  // 입·출력 반사, init 0xFFFFFFFF, xorout 0xFFFFFFFF. 메시지 = CH 자기 워드
  // (word1)를 *제외한* 명령 전 워드 — word0, word2‥(bh_len−1) — 를 워드
  // 오름차순으로, 각 워드는 최하위 바이트부터(리틀엔디언) 직렬화. 반사 관례
  // + 리틀엔디언 바이트 순서라 워드 안 처리 순서는 정확히 비트 0→31 이다.
  // 구현 형태: 고정 maxWords 전개 × 워드당 선형 갱신 — 순수 조합 XOR 트리다.
  // 표 조회 금지 (yosys proc_rom → $mem_v2 가 귀납에서 내용을 임의화하는
  // 함정 — walk_decode.sby 실측 기록). 패딩(≥ bh_len)은 메시지에 들어가지
  // 않는다. bh_len 은 여기서 검산 메시지의 경계로만 쓰인다 — 종료 판정·보폭
  // 계산 불참 (Walk.end_authority 유지 — END 가 여전히 유일한 종료
  // authority 다).
  val ch = new Area {
    /** CRC-32C 반사형 다항식 (0x1EDC6F41 의 비트 반전). */
    private val POLY_REV = BigInt("82F63B78", 16)
    /** init = xorout = 0xFFFFFFFF (RFC 3720 관례). */
    private val INIT_XOR = BigInt("FFFFFFFF", 16)
    /** bh_len — judge.declLen 과 같은 필드의 별도 슬라이스 (8비트 전폭,
      * §1.3). 용도는 검산 메시지 워드 경계 하나다. */
    private val msgLen = io.iInstr(0)(7 downto 0).asUInt

    /** 소프트웨어 참조(엘라보레이션 시점) — 워드 하나(비트 0→31)의 반사
      * 관례 비트-직렬 갱신: fb = s(0) ^ 입력비트, s' = (s >> 1) ^ (fb ?
      * POLY_REV : 0). 리틀엔디언 바이트 직렬 + 반사 관례라 워드 안 처리
      * 순서가 정확히 비트 0→31 인 것이 이 형태의 근거다. */
    private def foldWordSW(state: BigInt, w: BigInt): BigInt = {
      var s = state
      for (b <- 0 until 32) {
        val fb = s.testBit(0) ^ w.testBit(b)
        s = s >> 1
        if (fb) s = s ^ POLY_REV
      }
      s
    }
    // 기지값 자기시험 (RFC 3720 시험 패턴 중 워드 정렬 두 벌) — 이 모델이
    // 아래 열 마스크의 유일한 원천이므로 elaborate 가 여기서 못박는다.
    private def crcSW(words: Seq[BigInt]): BigInt =
      words.foldLeft(INIT_XOR)(foldWordSW) ^ INIT_XOR
    require(crcSW(Seq.fill(8)(BigInt(0))) == BigInt("8A9136AA", 16),
      "CRC-32C 자기시험 실패 — 32×0x00 은 0x8A9136AA 이어야 한다 (RFC 3720)")
    require(crcSW(Seq.fill(8)(INIT_XOR)) == BigInt("62A8AB43", 16),
      "CRC-32C 자기시험 실패 — 32×0xFF 는 0x62A8AB43 이어야 한다 (RFC 3720)")

    // 워드 갱신의 선형 전개 — GF(2) 선형성 (전 연산이 시프트·XOR 이고
    // f(0,0)=0): state' = A·state ⊕ B·word. 열 마스크는 엘라보레이션 시점
    // 단위-벡터 프로브로 얻고, 하드웨어는 비트당 균형 XOR 트리다 (상수
    // 행렬이지 메모리가 아니다 — 표 조회 함정 무관. 32단 비트-직렬 중첩식
    // 그대로는 elaborate 재귀를 넘겨(StackOverflow 실측) 이 평탄화가 필수).
    private val colS = (0 until 32).map(j => foldWordSW(BigInt(1) << j, BigInt(0)))
    private val colW = (0 until 32).map(b => foldWordSW(BigInt(0), BigInt(1) << b))
    private def xorAll(ts: Seq[Bool]): Bool = ts.size match {
      case 0 => False
      case 1 => ts.head
      case n => xorAll(ts.take(n / 2)) ^ xorAll(ts.drop(n / 2))
    }
    /** 워드 하나를 접는 조합 갱신 — foldWordSW 와 비트 동일 (선형 전개). */
    private def foldWord(state: Bits, w: Bits): Bits = {
      val out = Bits(32 bits)
      for (k <- 0 until 32) {
        out(k) := xorAll(
          (0 until 32).collect { case j if colS(j).testBit(k) => state(j) } ++
            (0 until 32).collect { case b if colW(b).testBit(k) => w(b) })
      }
      out
    }
    private val states = Vec(Bits(32 bits), maxWords + 1)
    states(0) := B(INIT_XOR, 32 bits)
    for (i <- 0 until maxWords) {
      if (i == 1) {
        // CH 의 32비트는 검산 메시지에 들어가지 않는다 — 자기 워드 구조 제외.
        states(i + 1) := states(i)
      } else {
        val incl = if (i == 0) True else U(i, 8 bits) < msgLen
        states(i + 1) := incl ? foldWord(states(i), io.iInstr(i)) | states(i)
      }
    }
    /** 재계산된 CRC-32C 최종값 (xorout 반영) — judge.chBad 비교기의 좌변. */
    val crcCalc = ~states(maxWords)
  }

  // ── 판정 — 순회 종료 직후 한 번 (§1.6.1 D14 · Walk.tla Finish) ──────────
  val judge = new Area {
    /** 선언 길이 bh_len — 8비트 전폭 그대로 (§1.3 함정: 조용한 절단 금지). */
    val declLen = io.iInstr(0)(7 downto 0).asUInt
    /** 기본 헤더 예약 [15:12] — 이 신호의 fanout 은 아래 비교기 하나다.
      * [11:8] 은 W1 부터 opcode_ext 라 예약이 아니다 — 판정하지 않는다. */
    val resvFld = io.iInstr(0)(15 downto 12)

    /** 능력 부재 — 순회 *전* 에 선언만으로 선다 (§4.2.2 검산 규범 2항 ·
      * §1.3 「최대 길이」). 비교 상대는 구현 슬롯 상한을 선언(워드) 단위로
      * 환산한 maxWords = 1 + 1(CH) + ehSlots*EH_WORDS_MAX — 이 기계가 받을 수 있는
      * 어떤 사슬의 bh_len 도 이 값을 넘지 못하므로(off 의 구조적 상계),
      * 그것을 넘는 선언은 실물과 무관하게 능력 밖이다. Walk.tla 의
      * declLen > Cap 과 동형(모델은 슬롯·워드 축약이 1:1). 8비트 전폭
      * 비교 — 조용한 절단 금지 (§1.3 함정). */
    val capAbsent = declLen > maxWords
    /** END authority 가 실제로 나타났는가. */
    val endSeen = walk.ended(ehSlots)
    /** 검산 1 — 길이. END 가 정한 실측 총 워드 수와 선언을 8비트 전폭 비교. */
    val lenBad = endSeen && (declLen =/= walk.off(ehSlots))
    /** 검산 2 — 안전장치. 선언 이내인데 상한 완주 후 END 미출현 =
      * malformation — 「들어간다」고 선언하고 실물이 아닌 자기모순 (§4.2.2
      * 검산 규범 3항). capAbsent 와 서로소 — END 미출현은 순회로 구별할 수
      * 없고 선언이 가른다 (§4.2.2 함정). */
    val capBad = !capAbsent && !endSeen
    /** 검산 3 — 미지 종류 (표 조회). END 이전 슬롯만 본다. */
    val junkBad = (0 until ehSlots).map(i => walk.walked(i) && !walk.defd(i)).reduce(_ || _)
    /** 자기 종류 필드 검산 — 사슬 포인터(authority)와 자기 선언의 자기모순.
      * 어셈블러는 언제나 일치시켜 방출한다 (관측) — 적법 바이너리 무거절. */
    val selfBad = (0 until ehSlots)
      .map(i => walk.walked(i) && walk.selfCode(i) =/= walk.ptr(i)).reduce(_ || _)
    /** 워드 수 필드 검산 — 카탈로그와의 자기모순. 8비트 전폭 비교 (§1.3 부류). */
    val wordsBad = (0 until ehSlots)
      .map(i => walk.walked(i) && walk.defd(i) && walk.wordsFld(i) =/= walk.stepW(i)).reduce(_ || _)

    /** 종류별 등장 횟수 — END 이전 슬롯만 센다. */
    private def occ(code: Int): UInt = {
      val w = log2Up(ehSlots + 1)
      (0 until ehSlots)
        .map(i => (walk.walked(i) && walk.ptr(i) === B(code, KIND_W bits)).asUInt(w bits))
        .reduce(_ + _)
    }
    /** §4.2.3 반복 규약 위반. */
    val dupBad = repeatCap.map { case (code, cap) => occ(code) > cap }.reduce(_ || _)
    /** 예약 필드 판정 (§5.7) — 0 이 아니면 malformation. */
    val resvBad = resvFld =/= 0
    /** CH 검산 (W8, §1.3.4) — next_hdr ≠ END 인 명령의 word1 은 CH 다:
      * 재계산 대조 불일치 = malformation. EH-0 명령에는 CH 가 없어 서지
      * 않는다. 판정 자리는 다른 검산과 같은 D14 판정점 — 순회 종료 직후
      * 한 번, 래치 이전. */
    val chBad = !walk.ended(0) && (ch.crcCalc =/= io.iInstr(1))

    /** malformation — 순회 종료 직후 단 한 곳의 판정 (D14). capability 가
      * 맨 앞이다 — 능력 밖 사슬은 나머지 판정의 대상이 아니어서(§1.6.2 ·
      * Walk.tla Finish · Payload.tla 접수 순서) 두 종결이 동시에 서지
      * 않는다 (ISA-5). 순회 자체는 판정과 무관하게 상한까지 완주했다 —
      * 갈리는 것은 이 판정 결과뿐이다 (D14 상태열 균일). */
    val mal = !capAbsent &&
      (resvBad || chBad || capBad || lenBad || junkBad || selfBad || wordsBad || dupBad)
  }

  // ── 방출 단 — 판정·서술자·명령이 한 레지스터 단으로 함께 이동한다 ────────
  val outStage = new Area {
    val rValid = RegNext(io.iValid) init (False)
    /** 래치된 판정 — 모든 소비 지점의 유일한 원천 (mal_carried). */
    val rMal = RegNext(judge.mal) init (False)
    /** 래치된 capability 종결 — rMal 과 같은 레지스터 단에서 함께 이동한다. */
    val rCapa = RegNext(judge.capAbsent) init (False)

    // 예약 필드는 판정에 소비된 뒤 방출면에서 지워진다 — 같은 판정을 받은
    // 두 명령은 방출면에서 완전히 구별 불가능하다 (§5.8 SEC-7 (ii)).
    // 마스킹은 [15:12] 만 — [11:8] 은 opcode_ext 라 opcode 처럼 정당한 구별
    // 인자로 방출된다 (W1 · SEC-7 (ii) 재유도). CH 워드는 명령 비트열의
    // 결정론적 함수라 신규 구별 인자가 아니다 — 마스킹 불요.
    val masked = Vec(Bits(32 bits), maxWords)
    for (i <- 0 until maxWords) { masked(i) := io.iInstr(i) }
    masked(0)(15 downto 12) := 0

    val rInstr   = RegNext(masked)
    val rPresent = RegNext(Vec((0 until ehSlots).map(i => walk.walked(i))))
    // END 뒤 슬롯의 종류·오프셋은 방출되지 않는다 (post_end_gated) — 명령의
    // 의미가 사슬 뒤의 쓰레기에 의존하지 않는다 (§4.2.1 함정).
    val rCode = RegNext(Vec((0 until ehSlots)
      .map(i => walk.walked(i) ? walk.ptr(i) | B(EhCode.END, KIND_W bits))))
    val rOff = RegNext(Vec((0 until ehSlots)
      .map(i => walk.walked(i) ? walk.off(i) | U(0, 8 bits))))
  }

  io.oValid       := outStage.rValid
  io.oMalformed   := outStage.rMal
  // capability 종결 — malformed 와 구조적으로 배타다 (judge.mal 의 !capAbsent).
  io.oCapAbsent   := outStage.rCapa
  // malformed·capability → 실행 인터페이스에 유효가 실리지 않는다.
  // 게이트이지 분기가 아니다.
  io.oExecValid   := outStage.rValid && !outStage.rMal && !outStage.rCapa
  io.oInstr       := outStage.rInstr
  io.oSlotPresent := outStage.rPresent
  io.oSlotCode    := outStage.rCode
  io.oSlotOff     := outStage.rOff
  // malformation 전용 sticky — 세운다 / 명시적 해제 외엔 내리지 않는다 (§5.5).
  // capability 종결은 이 신호에 불참한다 — 능력 부재는 오류가 아니다 (§1.6.2).
  // 폴딩 규정 (§5.6 신호별 명시): 이 신호는 폴딩하지 않는다.
  io.oFault := StickyFault(set = outStage.rValid && outStage.rMal, clear = io.iFaultClear)
}
