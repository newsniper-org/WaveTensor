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
  */
case class Wt64Config(
    nPoints:    Int = 4,
    ownL:       Int = 2,
    outDepth:   Int = 1,
    slotCap:    Int = 16,
    xlateParts: Int = 4,
    xlateIdx:   Int = 16,
) {
  /** 진입점 뷰 표 용량 — RouteJudge 의 뷰와 MmioConfig 의 수락 용량이 같은
    * 식을 봐야 한다 (두 곳에 따로 적혀 드리프트 표면이 됐던 것을 승격).
    * 이름 값 공간에는 닿지 않으므로 INV-T1 무위반. */
  def viewEntries: Int = 4 * nPoints

  require(nPoints >= 2, "축퇴 형상 금지 — 지점 1개면 경합·판정이 전부 공허해진다 (선-formal ASSUME 과 동형)")
  require(ownL >= 0 && outDepth >= 1 && slotCap >= 1)
}

object Types {
  import Isa._

  /** 태그 80b. 필드 순서는 정본 §1.4.4 의 나열 순서.
    * 비트 오프셋(어느 필드가 하위인가)은 어셈블러 관측으로 확정할 것 —
    * 그 전까지 이 번들을 **통째로만** 나르고 슬라이스하지 않는다.
    * (태그 조립을 여러 곳에 복제하지 않는다 — 정본이 지목한 30곳 복제
    * 드리프트 실패형. 조립·분해는 이 번들 하나가 담당한다.) */
  case class Tag() extends Bundle {
    val wave      = UInt(WAVE_W bits)
    val thread    = UInt(THREAD_W bits)
    val lnid      = UInt(LNID_W bits)
    val precision = UInt(PRECISION_W bits)
    val dim       = UInt(DIM_W bits)
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
