// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// WT64v1 재구현 — 결과 뱅크 (ResultBank). 정본 §2.4 (인터페이스 계약 4항 ·
// 소유 구간 [t, t+L] 양끝 포함 · L 은 파라미터) · §2.4.1 (조각별 슬롯) ·
// §2.7 FAB-3 (기입 자격) · FAB-4 (소유 구간).
//
// 선-formal 계약: rtl/formal/tla/ResultBank.tla — 검사된 모델이 의사-명세다
// (§6.3). 아래 GUARD-MAP 이 그 모델의 AllGuards 전부와 이 RTL 의 검사를
// 잇는다. 매핑은 실제로 강제하는 검사만 적는다.
//
// GUARD-MAP: ResultBank.owner_check  -> 검사 wrQualified — io.write 는 ownerValid(slot) && ownerId(slot) === io.write.prod 인 사이클에만 store 에 닿고, 아니면 store 불변 + io.fault(sticky) 발화 (loud, 무언 드롭 없음 — INV-T3)
// GUARD-MAP: ResultBank.acquire_free -> 검사 acqFree — 소유 상태 갱신(ownerValid := True)은 !ownerValid(slot) 인 슬롯에만 일어나고, 소유된 슬롯 요청은 io.acquire.granted === False 의 명시적 거절을 받는다 (규정된 처분 — §2.2 어휘)
// GUARD-MAP: ResultBank.interval_end -> 검사 ageAtEnd — 소유 슬롯의 age 는 매 사이클 +1 하되 age === ownL 인 사이클 말에 소유 해제·age := 0. 나이 L 인 사이클까지 기입 자격이 살아 있으므로 [t, t+L] 양끝 포함이다
//
// ## 나이 카운터가 L+1 을 표현하지 않는 근거 (모델 해설의 「판단하라」 지점)
//
// 모델은 age 를 0..(L+1) 로 두었다 — 가드 삭제 실험에서 「구간을 넘겼다」는
// 위반 상태 자체를 표현할 수 있어야 검출이 성립하기 때문이다. RTL 에서 그
// 요구는 검사기 배치의 문제로 바뀐다: 여기서는 해제가 age === L 판정과 같은
// 조합 블록에 융합돼 있어 (아래 ageAtEnd), age > L 인 상태가 구조적으로
// 생성 불가능하다 — 위반을 저장할 별도 검사기가 감시할 전이가 없다. 따라서
// 카운터는 0..L 만 표현하며(폭 log2Up(L+1)), L+1 표현은 두지 않는다.
// 이 융합을 깨는 개정(해제를 다른 always 블록·다른 조건으로 옮기는 것)은
// 이 근거를 무효화하므로 그때 L+1 표현과 검사기를 함께 들여와야 한다.
//
// ## 이 모듈이 하지 않는 것 (소관 경계)
//
//  - LBID → 물리 슬롯 사상은 여기 없다. 포트의 slot 은 **사상 후 물리
//    색인**이다 — 사상표(표 조회, §3.7.1)는 상류 소관이고, 미사상 LBID 의
//    route fault(§2.4 계약 4항)도 그쪽이 선다. 그래서 이 파일에는 명령·
//    태그 유래 필드가 아예 들어오지 않는다 (INV-T1/T2 무풍지대).
//  - 포트가 슬롯당 1 획득 / 1 기입인 것은 상류 중재(FAB-1 단일 생산자,
//    §2.3 선택 규칙)를 전제한다 — 여기서 중재하지 않는다.
//  - §2.4.1 조각별 슬롯의 「선언 총개수 > 구현 슬롯 상한 = 능력 부재」
//    판정은 재조립(§4.3 소관)이 선다. 이 뱅크는 구간의 낱개 슬롯을 빌려줄
//    뿐이다.
//  - §2.4 계약 3항 「마지막 기입자」— FAB-4 아래에서 구간당 기입자는 최대
//    하나라 겨룰 일이 없고(정본 해설), 모델의 lastWriter 는 관측 변수다.
//    이 RTL 은 기입자 기록을 아예 갖지 않으므로 「구간이 바뀌면 기록도 새로
//    시작한다」는 개정 3항이 공허하게 참이다 — 기록을 들여오는 개정은
//    Acquire 에서의 초기화를 함께 들여와야 한다 (모델 Acquire 의 lastWriter
//    초기화가 그 자리다).
package wt64.fabric

import spinal.core._
import spinal.lib.CountOne
import wt64.{StickyFault, Wt64Config}

/** 결과 뱅크 — 생산자의 직전 출력을 담아 두는 슬롯 집합 (정본 §2.4 정의).
  *
  * 슬롯마다 소유자·나이 상태를 두고, 세 가드를 강제한다:
  * 자유 슬롯만 획득(acquire_free) · 소유자만 기입(owner_check, 위반은 loud
  * fault) · 나이 L 에서 소유 해제(interval_end, [t, t+L] 양끝 포함).
  *
  * @param cfg   형상 파라미터 — slotCap(슬롯 수) · ownL(소유 구간 L)
  * @param dataW 결과 값 폭. 데이터패스 형상이며 명령·태그 인코딩과 무관.
  *              Wt64Config 에 아직 없어 지역 파라미터로 둔다 (promote 후보).
  * @param prodW 생산자 식별 폭. 내부 소유 장부 전용 — 명령·태그 필드가
  *              아니므로 형상의 함수여도 INV-T1 위반이 아니다 (promote 후보).
  */
class ResultBank(cfg: Wt64Config, val dataW: Int = 64, val prodW: Int = 4) extends Component {
  require(dataW >= 1, "결과 값 폭은 1b 이상")
  require(prodW >= 1, "생산자 식별 폭은 1b 이상")

  /** 슬롯 색인 폭. slotCap = 1 이어도 포트는 1b — 0폭 포트를 만들지 않는다. */
  private val slotW = log2Up(cfg.slotCap) max 1

  /** 나이 폭 — 0..L 만 표현한다 (파일 머리의 근거 참조). ownL = 0 이면
    * 구간은 [t, t] 한 사이클이고 카운터는 1b 로 0 만 오간다. */
  private val ageW = log2Up(cfg.ownL + 1) max 1

  val io = new Bundle {
    /** 소유 획득 요청. granted 는 같은 사이클의 명시적 처분이다 — 거절을
      * 조용히 삼키지 않는다. 허가되면 소유는 **다음 사이클부터** 관측된다
      * (레지스터 갱신) — 구간 시작 t 는 그 사이클이다. */
    val acquire = new Bundle {
      val valid   = in  port Bool()
      val slot    = in  port UInt(slotW bits)
      val prod    = in  port UInt(prodW bits)
      val granted = out port Bool()
    }

    /** 기입. 응답 신호가 없는 이유: 자격 있는 기입은 무조건 성사되고,
      * 자격 없는 기입은 io.fault 로 크게 실패한다 — 제3의 결과가 없다. */
    val write = new Bundle {
      val valid = in port Bool()
      val slot  = in port UInt(slotW bits)
      val prod  = in port UInt(prodW bits)
      val data  = in port Bits(dataW bits)
    }

    /** 조합 읽기. 값은 소유 해제 후에도 남는다 — 뱅크의 존재 이유가 후속
      * 명령의 참조다 (§2.4 정의). owned 는 지금 소유 구간 안인가의 관측. */
    val read = new Bundle {
      val slot  = in  port UInt(slotW bits)
      val data  = out port Bits(dataW bits)
      val owned = out port Bool()
    }

    /** 자격 없는 기입의 sticky fault (§1.6.3 · §2.6 함정 — 합성 가능한
      * 상태 비트, 시뮬레이션 전용 단언 금지). 명시적 해제 외엔 내려가지
      * 않는다. */
    val fault      = out port Bool()
    val faultClear = in  port Bool()

    /** E.11 점유 관측면 (§3.7 드레인 정의역 ④ — 소유 구간이 진행 중인 결과
      * 슬롯). 소유 중(ownerValid) 슬롯 수의 조합 집계 — 이미 있는 점유
      * 상태의 배선일 뿐 새 상태가 아니다 (E.11 해설). age === L 로 이번
      * 사이클 말에 풀리는 슬롯도 아직 소유 중이므로 센다 (양끝 포함 —
      * acquire 거절과 같은 독법). 폭은 슬롯 상한에서 유도 — 관측면이지
      * 인코딩이 아니므로 INV-T1 의 대상이 아니다. */
    val occupancy = out port UInt(log2Up(cfg.slotCap + 1) bits)
  }

  // ── 슬롯 상태 ─────────────────────────────────────────────────────
  // 소유자 = (valid, id) 쌍. 모델의 NoOwner 는 ownerValid === False 다 —
  // id 값 공간을 쪼개 「없음」을 박지 않는다 (id 는 valid 일 때만 유의미).
  private val ownerValid = Vec.fill(cfg.slotCap)(RegInit(False))
  private val ownerId    = Vec.fill(cfg.slotCap)(Reg(UInt(prodW bits)) init 0)
  private val age        = Vec.fill(cfg.slotCap)(Reg(UInt(ageW bits)) init 0)
  private val store      = Vec.fill(cfg.slotCap)(Reg(Bits(dataW bits)) init 0)

  /** 물리 색인 유효 판정. slotCap 이 2의 거듭제곱이면(1 제외) 색인 공간
    * 전체가 유효해 상수 True 로 접힌다 — 비교기가 생기지 않는다.
    * slotCap = 1 은 포트가 1b 더미라 0 만 유효하다. */
  private def inRange(idx: UInt): Bool =
    if (cfg.slotCap == 1) idx === 0
    else if (isPow2(cfg.slotCap)) True
    else idx < cfg.slotCap

  /** 포트 색인 → Vec 주소. Vec 이 요구하는 주소 폭은 log2Up(slotCap) 이고
    * 포트 폭은 0폭 회피로 그보다 넓을 수 있다(slotCap = 1). 자격 판정은
    * 항상 inRange 가 전체 포트 폭으로 먼저 서므로, 여기서의 절단은 유효
    * 색인에 대해 항등이다. */
  private def phys(idx: UInt): UInt = idx.resize(log2Up(cfg.slotCap))

  // ── interval_end — 나이 진행과 구간 만료 (ageAtEnd) ──────────────
  // 소유 슬롯만 나이를 먹는다. age === L 인 사이클: 아직 소유 중(양끝
  // 포함 — 이 사이클의 기입은 자격 있음)이고, 사이클 말 레지스터 갱신에서
  // 해제된다. 해제와 판정이 이 한 블록에 융합돼 있어 age > L 은 구조적으로
  // 불가능하다 — 파일 머리의 L+1 비표현 근거가 정확히 이 융합에 기댄다.
  private val ageAtEnd = Vec.tabulate(cfg.slotCap)(s => ownerValid(s) && age(s) === cfg.ownL)
  for (s <- 0 until cfg.slotCap) {
    when(ownerValid(s)) {
      when(ageAtEnd(s)) {
        ownerValid(s) := False
        age(s)        := U(0, ageW bits)
      } otherwise {
        age(s) := age(s) + 1
      }
    }
  }

  // ── acquire_free — 자유 슬롯만 획득 (acqFree) ────────────────────
  // 소유된 슬롯은 빼앗을 수 없다 — 모델에선 가드가 동작 자체를 막지만,
  // RTL 의 요청은 배선으로 도착하므로 「막힘」을 granted === False 의
  // 명시적 거절로 관측 가능하게 만든다 (무처분 없음 — FAB-2 어휘).
  // age === L 로 이번 사이클 말에 풀리는 슬롯도 아직 소유 중이므로 거절된다
  // (양끝 포함) — 다음 사이클에야 자유다.
  private val acqFree = inRange(io.acquire.slot) && !ownerValid(phys(io.acquire.slot))
  io.acquire.granted := io.acquire.valid && acqFree
  when(io.acquire.valid && acqFree) {
    ownerValid(phys(io.acquire.slot)) := True
    ownerId(phys(io.acquire.slot))    := io.acquire.prod
    age(phys(io.acquire.slot))        := U(0, ageW bits)
  }
  // 위 갱신은 나이 블록과 같은 슬롯을 다투지 않는다 — 나이 블록은 소유
  // 슬롯만, 이 블록은 자유 슬롯만 만진다 (acqFree 가 그 배타를 강제한다).

  // ── owner_check — 소유자만 기입 (wrQualified) ────────────────────
  // FAB-3: 값 레지스터는 자격자가 존재하는 사이클에만 바뀐다. store 의
  // 유일한 기입 경로가 이 when 하나이므로 속성이 구조로 성립한다 — §2.4
  // 함정(자격 검사가 모듈 삭제와 함께 증발)의 재발 방지가 GUARD-MAP lint 다.
  // 범위 밖 물리 색인은 자격 없음으로 접는다 — 어느 소유자와도 일치할 수
  // 없는 색인이므로 같은 fault 로 크게 실패한다.
  // 획득 허가와 같은 사이클의 기입은 자격 없음이다 — 소유는 다음 사이클부터
  // 관측되며(위), 모델에서도 Acquire 와 Write 는 별개 원자 단계다.
  private val wrQualified = inRange(io.write.slot) &&
    ownerValid(phys(io.write.slot)) && ownerId(phys(io.write.slot)) === io.write.prod
  when(io.write.valid && wrQualified) {
    store(phys(io.write.slot)) := io.write.data
  }

  // 자격 없는 기입 시도 = loud fault. 조용한 무시 금지 (INV-T3) — sticky
  // 비트로 세우고 명시적 해제 외엔 내리지 않는다 (StickyFault: 해제·발화
  // 동시면 발화가 이긴다).
  io.fault := StickyFault(set = io.write.valid && !wrQualified, clear = io.faultClear)

  // ── 읽기 ─────────────────────────────────────────────────────────
  io.read.data  := store(phys(io.read.slot))
  io.read.owned := inRange(io.read.slot) && ownerValid(phys(io.read.slot))

  // ── E.11 점유 관측면 — 드레인 집계의 실입력 (§3.7 정의역 ④) ──────
  // 소유 비트의 popcount — 조합, 새 상태 없음 (E.11 해설). store 잔존
  // 값은 세지 않는다: 값이 남는 것은 뱅크의 존재 이유(§2.4)이지 진행이
  // 아니고, 드레인 정의역은 §3.7.2 가 적은 「소유 구간이 *진행 중*인」 슬롯이다.
  io.occupancy := CountOne(ownerValid)
}
