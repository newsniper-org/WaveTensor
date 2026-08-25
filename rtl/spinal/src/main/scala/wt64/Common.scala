// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// WT64v1 재구현 — 공용 어휘.
//
// 이 파일이 정하는 것은 **ISA 가 정한 폭과 코드**뿐이다. 형상(인스턴스 개수)은
// Wt64Config 로 가고, 여기 있는 값은 전부 형상과 무관한 상수다 — INV-T1:
// 명령·태그 필드의 값 공간은 하드웨어 인스턴스 개수의 함수가 아니다.
//
// 출처 규율: 폭·코드는 정본(각 절 인용)과 isa/wt64v1_isa.json(§1.7.3 의
// "기계가 읽는 단일 정의") 에서 온다. 비트 오프셋처럼 정본이 폭과 순서만
// 주는 것은 어셈블러(허용 오라클)의 encode 출력을 관측해 적고, 그 관측
// 지점을 주석에 남긴다.
//
// **그 규율에는 예외가 하나 있고, 그것은 예외가 아니라 정의의 귀결이다.**
// 태그(§1.4.4)의 비트 오프셋은 어셈블러 관측으로 확정할 수 *없다* — §1.1
// 정의가 태그를 「명령어 인코딩의 일부가 아니라」고 못박았으므로 어셈블러가
// 태그를 방출하지 않기 때문이다. 관측원이 원리적으로 비어 있다. 그래서 태그의
// 팩킹 순서는 *결정 대기*이지 관측 대기가 아니며, 아래 Types.Tag 가 그 사실과
// 그것을 *우회하는* 직렬화(정본 E.5.1 세 워드)를 함께 든다.
package wt64

import spinal.core._

/** ISA 상수 — 전부 형상 무관 (INV-T1). */
object Isa {
  // ── 논리 식별자 폭 ──────────────────────────────────────────────
  /** 논리 노드 ID. 16b 평면 이름 공간 (정본 §1.4.2 — dest 16b). */
  val LNID_W = 16
  /** 논리 뱅크 ID. 8b 평면 이름 공간 (정본 §1.4.3 · §1.4.7 ACCTGT "평면 8비트"). */
  val LBID_W = 8

  // ── 태그 (정본 §1.4.4 — 80b: wave 32 / 스레드 16 / LNID 16 / 정밀도 8 / 차원 8)
  val TAG_W       = 80
  val WAVE_W      = 32
  val THREAD_W    = 16
  val PRECISION_W = 8
  val DIM_W       = 8

  // ── EH (isa/wt64v1_isa.json eh_codes + 정본 §1.4.7) ─────────────
  // 워드 형식: [31:16] 본문 / [15:8] 코드 / [7:0] 워드 수
  //   (어셈블러 encode_pass 관측 — 예: PORT = (dest&0xFFFF)<<16 | code<<8 | 1)
  val EH_CODE_W = 8
  object EhCode {
    val END       = 0x0 // 종료 표식 — 종료의 유일한 authority (정본 §4.2.2)
    val PORT      = 0x1
    val IMM16     = 0x2
    val IMM32     = 0x3
    val IMM64     = 0x4
    val MEM       = 0x5
    val SUBSCRIPT = 0x6
    val OPREF     = 0x7
    val PRECISION = 0x8
    val ACCTGT    = 0x9 // 누산 대상 = 목적 LBID (정본 §1.4.7) — 재조립 결속 원천 (§4.3)
    val NOP_PAD   = 0xF
  }

  // ── 조각 머리 채널 (정본 부록 E.10 — 사이드밴드 CTRL) ───────────
  // 폭은 고정 상수다 (INV-T1/T2). 구체 값은 E.10 이 RTL 단계에서 SlotCap 과
  // 함께 확정하라고 했으므로 여기가 그 확정 지점이다: 8b 는 선언 총개수의
  // 값 공간(§2.4.1 선언 총개수)이 LBID 와 같은 평면 8b 세계에 사는 것과
  // 정합하고, 형상의 함수가 아니다.
  val FRAG_SEQ_W   = 8
  val FRAG_TOTAL_W = 8
}

/** 형상 파라미터 — elaborate 시점에만 존재. 명령·태그 인코딩에 새지 않는다
  * (INV-T2: 고정 니블 분할 금지 — 폭이 이 값들의 함수가 되는 순간 위반이다.
  * scripts/lint_isa7_topology.py 가 정적으로 감시한다).
  *
  * @param nPoints   배달 지점 수 (한 배달 범위 안)
  * @param ownL      결과 슬롯 소유 구간 파라미터 L — [t, t+L] 양끝 포함 (§2.4)
  * @param outDepth  생산자 출력 레지스터 깊이 D >= 1 (§2.6)
  * @param slotCap   구현 슬롯 상한 — capability 축의 상한 (§2.4.1, §4.3 과 별개)
  * @param xlateParts  변환 저장 파티션 수 (§3.6.1)
  * @param xlateIdx    파티션당 직접 사상 색인 수 (§3.6.1)
  * @param ownEntries    페이지 소유권 표 슬롯 수 (부록 E.7)
  * @param cqDepth       완료 링 깊이 (부록 E.5)
  * @param stepProgDepth step 프로그램 저장 깊이 P (§2.5)
  */
case class Wt64Config(
    nPoints:    Int = 4,
    ownL:       Int = 2,
    outDepth:   Int = 1,
    slotCap:    Int = 16,
    xlateParts: Int = 4,
    xlateIdx:   Int = 16,
    ownEntries: Int = 64, // E.7 소유권 표 직접 사상 슬롯 수 = 동시 장치 소유 가능 페이지 상한 (2의 거듭제곱)
    cqDepth:    Int = 8, // 완료 링 깊이 — E.5: 2^k, 한 칸 비움 인코딩이라 수용량 cqDepth-1
    stepProgDepth: Int = 10, // step 프로그램 저장 깊이 P >= 1 (§2.5) — 기본 전 상주(10종)
) {
  /** 진입점 뷰 표 용량 — RouteJudge 의 뷰와 MmioConfig 의 수락 용량이 같은
    * 식을 봐야 한다 (두 곳에 따로 적혀 드리프트 표면이 됐던 것을 승격).
    * 이름 값 공간에는 닿지 않으므로 INV-T1 무위반. */
  def viewEntries: Int = 4 * nPoints

  require(nPoints >= 2, "축퇴 형상 금지 — 지점 1개면 경합·판정이 전부 공허해진다 (선-formal ASSUME 과 동형)")
  require(ownL >= 0 && outDepth >= 1 && slotCap >= 1)
  require(ownEntries >= 2 && isPow2(ownEntries), "소유권 표 슬롯 수는 2 이상 2의 거듭제곱")
  require(cqDepth >= 2 && isPow2(cqDepth), "완료 링 크기는 2의 거듭제곱 >= 2 (E.5)")
  require(stepProgDepth >= 1, "§2.5 프로그램 깊이 P >= 1 — 미상주 참조는 능력 부재 계약으로만 존재")
}

object Types {
  import Isa._

  /** 태그 80b. 필드 순서는 정본 §1.4.4 의 나열 순서.
    *
    * ## 80b 팩킹 순서는 *결정 대기*다 — 관측 대기가 아니다 (2026-08-25 정정)
    *
    * 앞판 주석은 「비트 오프셋은 어셈블러 관측으로 확정할 것」이라 적고 그
    * 관측을 기다렸다. **그 관측원은 원리적으로 비어 있다.** 정본 §1.1 정의가
    * 태그를 「명령어 인코딩의 일부가 *아니라*」고 못박았으므로 어셈블러는 태그를
    * 방출하지 않는다 — 관측할 encode 출력 자체가 존재하지 않는다. 즉 앞판은
    * 영원히 오지 않을 관측을 기다리고 있었고, 그 사이 잠정 배치(`asBits` 가
    * 함축하는 순서)가 생성된 SV 한 줄로 조용히 굳고 있었다. 정본이 정한 적 없는
    * 값이 계약이 되는 형태다 — 부록 B 해설의 「조용히 메운 공백은 메워지지 않은
    * 것보다 위험하다」와 같은 부류이며, 여기서는 모델이 아니라 생성물이 메웠다.
    *
    * 그래서 팩킹 순서는 **미확정으로 남긴다**. 확정의 조건은 관측이 아니라
    * *결정*이다 (@sec:gaps B.5 · §3.10 호스트 ABI 합의).
    *
    * ## 그럼에도 워드 표면은 오늘 닫힌다 — 세 워드 명명 필드 (정본 E.5.1)
    *
    * 32비트 워드로 태그를 나르는 표면은 *세 워드의 명명 필드*로 나른다. 팩킹
    * 순서를 몰라도 상호운용되고, 순서가 훗날 확정돼도 이 배치는 한 비트도
    * 움직이지 않는다 — 미확정 값을 ABI 로 승격시키지 않으면서 ABI 를 닫는
    * 형태다. 그 직렬화가 아래 `toWords`/`fromWords` 다.
    *
    * *번들 포트는 워드 표면이 아니다.* 명령 제시의 태그 사이드밴드처럼 장치
    * 안쪽에서 태그를 나르는 자리는 이 번들을 *통째로* 쓴다 — E.5.4 규범 3항이
    * 「사이드밴드가 나르는 태그는 통째다. 워드 표면이 아니므로 E.5.1 직렬화의
    * 대상이 아니다」라고 정한다. 워드 코덱은 호스트 메모리·MMIO 워드에 태그가
    * 실릴 때만 쓴다.
    *
    * ## 조립·분해는 여전히 단 한 곳 (§1.4.4 「태그 조립은 한 곳에서」)
    *
    * 워드 코덱이 생겨도 그 규범은 유지된다 — 오히려 강화된다. 이 번들과 아래 두
    * 함수 밖에서 태그를 슬라이스하거나 재조립하지 않는다. 참조 구현이 같은
    * 관용구를 30곳에 복제해 드리프트한 실패형이 그 규범의 근거다.
    */
  case class Tag() extends Bundle {
    val wave      = UInt(WAVE_W bits)
    val thread    = UInt(THREAD_W bits)
    val lnid      = UInt(LNID_W bits)
    val precision = UInt(PRECISION_W bits)
    val dim       = UInt(DIM_W bits)
  }

  /** 태그의 *워드 직렬화* — 32비트 워드 표면의 공통 코덱 (정본 E.5.1).
    *
    * {{{
    *   TAG0  +0x0  [31:0]  wave 번호
    *   TAG1  +0x4  [31:16] 스레드 ID · [15:0] LNID
    *   TAG2  +0x8  [31:16] 예약 · [15:8] 정밀도 · [7:0] 차원
    * }}}
    *
    * 80 = 32 + 32 + 16 이라 세 워드에 16비트가 남고, 그 여백이 TAG2 상위다.
    * **여백의 정책은 직렬화가 아니라 *방향*이 정한다** — 장치가 돌려주는 표면은
    * 전량 0 기입(E.5.3), 받아들이는 표면은 엄격 malformation(E.5.4 · E.1.2)이며
    * 축은 §5.7 함정의 그것이다. 그래서 이 객체는 여백의 처분을 갖지 않는다:
    * 조립은 0 을 쓰고, 분해는 절단하며, *판정과 처분은 표면이 한다.*
    *
    * 이 배치는 새로 만든 것이 아니다 — E.1.2 「재조립 문맥 소거」의 `0xF40`~
    * `0xF48` 세 워드가 이미 같은 배치이고, E.5.1 이 그 하나를 세 표면(완료
    * 디스크립터 · 명령 디스크립터 · 소거 스테이징)의 *공통* 직렬화로 올렸다.
    * 그래서 이 코덱을 고치면 세 표면이 함께 움직인다 — 그것이 의도다.
    *
    * 워드 색인은 *상대*다. 디스크립터 안의 절대 자리는 부록 E.5 프레임
    * (`wt64.host.HostDesc`)이 정하고, 그 프레임이 두 방향에 같은 상대 오프셋을
    * 준다. 여기는 「태그를 어떻게 세 워드로 펴는가」만 안다.
    */
  object Tag {
    /** 직렬화 워드 수 — 형상 무관 상수 (INV-T1). */
    val WORDS = 3

    /** 상대 워드 색인 (E.5.1 표). */
    val W_TAG0 = 0
    val W_TAG1 = 1
    val W_TAG2 = 2

    /** TAG2 의 예약 여백 — `[31:16]`. 80 = 32+32+16 의 나머지다. */
    val TAG2_RSV_LO = PRECISION_W + DIM_W
    val TAG2_RSV_HI = 31

    // 배치가 성립하는 조건을 elaborate 시점에 든다 — §1.4.4 표가 움직이면
    // 여기서 즉시 멎어야 한다 (조용히 다른 배치를 내지 않는다).
    require(WAVE_W == 32, s"TAG0 은 wave 전폭이어야 한다 (WAVE_W=$WAVE_W)")
    require(THREAD_W + LNID_W == 32, "TAG1 = 스레드 ID ‖ LNID 가 한 워드여야 한다")
    require(PRECISION_W + DIM_W <= 32, "TAG2 하위가 한 워드를 넘는다")
    require(WAVE_W + THREAD_W + LNID_W + PRECISION_W + DIM_W == TAG_W,
      s"필드 폭 합이 태그 폭 $TAG_W 와 다르다 — §1.4.4 표와 어긋난다")

    /** 조립 — 태그 → 세 워드. TAG2 예약은 *0 을 쓴다* (돌려주는 쪽 의무). */
    def toWords(t: Tag): Vec[Bits] = Vec(
      t.wave.asBits,
      t.thread.asBits ## t.lnid.asBits,
      B(0, 32 - PRECISION_W - DIM_W bits) ## t.precision.asBits ## t.dim.asBits,
    )

    /** 예약 여백의 *판정* — TAG2 `[31:16]` 이 0 이 아닌가.
      *
      * 값이 아니라 1비트 판정만 낸다. 받아들이는 표면(E.5.4 명령 디스크립터 ·
      * E.1.2 ABORT_TAG2)은 이것을 malformation 으로 처분하고, 돌려주는 표면은
      * 애초에 0 을 쓰므로 쓸 일이 없다. 처분을 여기 두지 않는 이유가 그것이다 —
      * 같은 직렬화 위에 방향이 다른 두 정책이 선다 (E.5.2 해설). */
    def reservedNonZero(w: Vec[Bits]): Bool = {
      require(w.length == WORDS, s"태그 워드 ${w.length}개 — $WORDS 개여야 한다")
      if (TAG2_RSV_LO > TAG2_RSV_HI) False
      else w(W_TAG2)(TAG2_RSV_HI downto TAG2_RSV_LO) =/= 0
    }

    /** 분해 — 세 워드 → 태그. 예약 여백은 절단한다.
      *
      * 절단은 「무시되는 비트가 어딘가에 저장되거나 반향되면 은닉 채널」(§5.7
      * 해설)의 후건을 구조로 막는다 — 잘린 비트는 어느 하류에도 도달하지 않는다.
      * 그 비트가 *검사받지 않고* 통과하는 쪽은 `reservedNonZero` 를 부르는
      * 표면이 닫는다. */
    def fromWords(w: Vec[Bits]): Tag = {
      require(w.length == WORDS, s"태그 워드 ${w.length}개 — $WORDS 개여야 한다")
      val t = Tag()
      t.wave      := w(W_TAG0).asUInt
      t.thread    := w(W_TAG1)(31 downto LNID_W).asUInt
      t.lnid      := w(W_TAG1)(LNID_W - 1 downto 0).asUInt
      t.precision := w(W_TAG2)(PRECISION_W + DIM_W - 1 downto DIM_W).asUInt
      t.dim       := w(W_TAG2)(DIM_W - 1 downto 0).asUInt
      t
    }
  }

  // EH 워드 번들은 여기 두지 않는다. 초안은 [15:8] 을 단일 코드 바이트로
  // 읽었으나 어셈블러 관측(DecodeWalk 착지 시)이 [15:12] next ‖ [11:8] self
  // 의 사슬 구조를 확정했다 — 실물은 wt64.decode 에 있고, 두 번째 사용처가
  // 생길 때 관측된 구조 그대로 승격한다. 틀린 공용 정의는 없는 것보다 나쁘다.

  /** 조각 머리 (부록 E.10) — 태그 ∥ 순번 ∥ 선언 총개수 ∥ 마지막 표시. */
  case class FragHead() extends Bundle {
    val tag   = Tag()
    val seq   = UInt(FRAG_SEQ_W bits)
    val total = UInt(FRAG_TOTAL_W bits)
    val last  = Bool()
  }
}

/** sticky fault — 합성 가능한 상태 비트.
  *
  * 정본의 반복 규범: fault 는 시뮬레이션 전용 단언이 아니라 **합성 결과물에
  * 존재하는 sticky 비트**다 (§1.6.3 sticky · §2.6 함정 · §5.5). 두 요구는
  * 서로 독립이다 — (1) fault 시점에 세운다, (2) 명시적 해제 외에는 어떤
  * 동작도 내리지 않는다. §2.6 함정이 실측으로 가른 그 둘이다.
  */
object StickyFault {
  /** set 이 한 번이라도 서면 clear 가 명시될 때까지 유지되는 비트를 만든다. */
  def apply(set: Bool, clear: Bool = False): Bool = {
    val bit = RegInit(False)
    // 해제와 발화가 같은 사이클이면 발화가 이긴다 — 해제로 fault 를 삼키는
    // 창을 만들지 않는다 (loud-fault-never-silent).
    when(clear) { bit := False }
    when(set)   { bit := True }
    bit
  }
}
