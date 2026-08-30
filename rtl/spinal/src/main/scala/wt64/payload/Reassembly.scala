// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// WT64v1 재구현 — 조각 재조립 (Reassembly). EXT-4 · D8 · D9.
//
// 선-formal 계약: rtl/formal/tla/Payload.tla — 검사된 모델이 의사-명세다 (§6.3).
// 아래 GUARD-MAP 이 그 모델의 AllGuards 전부(14)와 이 RTL 의 검사를 잇는다.
//
// 정본: §4.3 전부 — 규범 5항 (태그=키 · 두 「상한」 상이 · 순번 누락도 loud ·
//       미완 중 재시작 loud · 완료 후 재사용은 회계 소거 후) · 「태그→구간
//       결속」 (결속 원천 = 개시 wave 의 ACCTGT 가 명명한 목적 LBID, 개방 시
//       1회 확정·종료까지 불변) · 「조각열 종료 — 삼중 구조」 (마지막 표시가
//       authority / 선언 총개수는 검산 / 구현 슬롯 상한은 안전장치 · 타임아웃
//       금지 — 표시 유실의 처분은 태그 지정 문맥 소거),
//       §2.4.1 (조각별 슬롯 — 조각열 하나가 연속한 슬롯 구간, 순번이 구간 안의
//       자리, 선언 총개수 > 구현 슬롯 상한 = 능력 부재),
//       §1.4.7 (ACCTGT — 쓰기측 결과 슬롯 = 목적 LBID 명명, 사슬당 최대 1회),
//       §1.6.2 (오류 3분류 배타 — 능력 부재는 오류가 아니다),
//       §3.7 「미완 문맥의 소거 — 드레인 완주 가능성」 (소거 수단이 없으면
//       표시 유실 문맥 하나가 드레인을 영원히 막는다),
//       부록 E.10 (조각 머리 채널 — Types.FragHead 가 실물. 조각 머리는 자기
//       조각과 같은 beat — 도착의 원자성),
//       부록 E.12 (태그 지정 문맥 소거 — fault 아님 · 소거 카운트 회계 ·
//       없는 태그 쓰기 무시 · *소거 대상에 구간 데이터가 든다*),
//       §4.3 「소거 후 재사용」 (인도 후와 소거 후가 같은 요건 · 비우는 순서는
//       결속 폐기 *전* · **소거는 종료가 아니라 폐기라 검산을 실행하지
//       않는다** — 이 RTL 은 종료 판정(fr.endBad)을 조각 수락 경로 안에만
//       두고 ab 소거 경로는 그 판정에 닿지 않는다. 정본 함정 「닫는 경로
//       하나에 검산을 심으면 모든 소거가 거짓 fault 를 낸다」가 경고한
//       결함형이 구조적으로 표현 불가다: 두 소거가 회계 비우기를 공유하되
//       검산은 접수 판정 안에 산다).
//
// ── GUARD-MAP ────────────────────────────────────────────────────────────
// GUARD-MAP: Payload.key_is_tag -> 검사 fr.hit — 문맥 탐색의 유일한 키가 태그 전량 비교(c.tag === head.tag, 번들 통비교 — 슬라이스·부분 키 없음)다. 개방측 op.clash 가 같은 태그의 활성 문맥이 있는 한 새 문맥을 열지 않으므로 태그당 활성 문맥 <= 1 이 유지되고 hit 는 one-hot 이다 (§4.3 규범 1 「태그가 재조립의 키다」)
// GUARD-MAP: Payload.no_restart -> 검사 op.clash — 진행 중 태그(인도 대기 포함 — 소거 전이면 태그는 아직 그 문맥의 것)로의 재개시는 granted=False 거절 + io.fault sticky 발화 (op.clashEvt). 조용한 덮어쓰기 경로가 구조적으로 없다 (§4.3 규범 4 · 함정 「참조 구현에 남아 있던 조용한 덮어쓰기」)
// GUARD-MAP: Payload.no_dup_seq -> 검사 fr.dupRej — 문맥의 수신 순번 집합(seen)에 이미 있는 순번은 거절 + io.fault, 기입·회계 불변 (§4.3 규범 2 의 중복 축 — 도착 시점 판정)
// GUARD-MAP: Payload.cap_check -> 검사 fr.overRej — 순번 0 또는 순번 > 선언 총개수(8비트 전폭 비교)이면 거절 + io.fault. 수락 기입은 off = 순번-1 < 선언 총개수 <= slotCap 이 구조적으로 성립해 기입 면에 구간 밖 좌표가 실리지 않는다 (Inv_NoCrossWindow 의 RTL 형 — §2.4.1 「순번이 구간 안의 자리를 정한다」)
// GUARD-MAP: Payload.capability_check -> 검사 fr.capaRej — head.total(8비트 전폭) > slotCap 이면 맨 앞 판정으로 거절. 능력 밖 조각열은 나머지 판정·회계·기입에 불참한다 (§2.4.1 규범 4 · §1.6.2 · Payload.tla 접수 순서 「능력 → 상한 → 재시작 → 중복」)
// GUARD-MAP: Payload.capability_not_fault -> fr.capaRej 는 io.capAbsent sticky 관측면만 세우고 io.fault 의 set 항에 나타나지 않는다 — 능력 부재는 오류가 아니며 malformation 과 동시에 서지 않는다 (§1.6.2 오류 3분류 배타 · DecodeWalk oCapAbsent 선례)
// GUARD-MAP: Payload.base_from_tag -> ctx.base 의 유일한 기입 경로는 개방 수락 when 블록(op.grant)이고 값은 디코드가 개시 wave 의 ACCTGT 에서 준 목적 LBID 다 — 조각 경로에 base 대입이 없고(읽기만), 기입 착지는 그 결속(io.wr.base := fr.cBase)으로만 계산된다 (D8 · §4.3 태그→구간 결속 · §1.4.7)
// GUARD-MAP: Payload.loud_reject -> 조각 거절 전 사유(fr.strayRej·totBad·overRej·dupRej)와 재시작 거절(op.clashEvt)이 io.fault sticky 를, 능력 부재 거절(fr.capaEvt)이 io.capAbsent sticky 를 세운다 — 흔적 없는 거절 경로가 없다. 풀 고갈 개방 거절만 granted=False 의 명시적 처분이다 (모델 밖 — 파일 머리 「어긋난 자리」)
// GUARD-MAP: Payload.reset_on_deliver -> 인도 완결(io.deliver.fire) when 블록이 그 문맥의 active·seen·last·totalKnown 을 전부 소거한다 — 태그 해방과 회계 소거가 같은 전이라 낡은 회계로 같은 구간이 다시 결과로 나갈 수 없다 (§4.3 규범 5 · Inv_NoStaleRedeliver)
// GUARD-MAP: Payload.write_atomic -> 기입 면 발화(io.wr.valid := fr.accept)와 회계 갱신(seen·last·total 래치, 같은 fr.accept 게이트)이 같은 사이클에 선다 — 둘을 가르는 파이프 단·지연 경로가 없다 (모델 write_atomic — 「회계는 진행했는데 칸은 아직 비었다」 상태가 구조적으로 없다)
// GUARD-MAP: Payload.last_judges -> 검사 fr.endBad — 수락 조각이 마지막 표시(head.last)를 나르는 시점에 갱신 후 수신 집합(newSeen)이 선언 총개수 전량 마스크와 다르면 누락/중복으로 io.fault (fr.endEvt). 거절된 조각의 표시는 접수되지 않는다. 표시 유실은 fault 가 아니다 — 미완 문맥 수가 io.incomplete 진단 관측면이다 (D9 · §4.3 조각열 종료 삼중 구조 · Inv_EndIncompleteLoud)
// GUARD-MAP: Payload.abort_erases -> 검사 ab 소거 when 블록 — 소거 발화(ab.fire)가 그 태그 문맥의 active·seen·last·totalKnown 을 reset_on_deliver 와 같은 소거 규율로 한 전이에 전부 비운다. 태그만 해방하고 회계를 남기는 경로가 없다 (개방 수락 op.grant 의 재초기화가 이중 방어로 겹친다 — 부록 E.12 1항 「소거 대상: 그 태그의 활성 문맥 전체」의 회계 축)
// GUARD-MAP: Payload.abort_clears_window -> 검사 구간 무효화 면 io.clr — 소거 발화와 *같은 게이트*(ab.fire)로 결속 구간 전체의 무효화가 발해진다. 좌표는 소거 대상 문맥의 결속(ab.cBase)이고 그것은 그 사이클의 레지스터 값이라 §4.3 「소거 후 재사용」 3항의 「결속을 버리기 전에 구간을 비운다」가 구조로 성립한다. 회계만 비우고 구간을 남기는 경로가 없다 — 두 소거가 같은 게이트를 쓰므로 그 어긋남이 표현 불가다 (부록 E.12 1항의 구간 축 · 2026-08-25 결정 B. 슬롯 실물은 이 모듈 소유가 아니므로 비우기는 *명령*이고, 이행은 슬롯 소유자 의무다 — E.12 1항 해설이 「요구를 거는 형태는 이 문서가 정하지 않는다」로 위임한 자리)
// GUARD-MAP: Payload.abort_leaves_trace -> 검사 ab.cnt — 소거 발화(ab.fire)와 소거 카운트 증가가 같은 사이클·같은 게이트다 (포화 — 되감기면 0 이 「소거 없음」으로 읽혀 조용한 소거가 된다). 흔적 없는 소거 경로가 없다. 없는 태그 무시는 카운트도 올리지 않는다 — 카운트는 「일어난 소거」의 회계다 (부록 E.12 2항 · Inv_AbortLoud)
// GUARD-MAP: Payload.abort_not_fault -> ab 경로는 io.fault 의 set 항(fr.rejEvt·fr.endEvt·op.clashEvt)에 나타나지 않는다 — 소거는 호스트의 의도된 처분이지 오류가 아니고, 없는 태그 기입의 무시도 마찬가지다 (부록 E.12 2·3항 · capability_not_fault 선례 · Inv_AbortNotFault)
// ─────────────────────────────────────────────────────────────────────────
//
// ## 모델 ↔ RTL 의 어긋난 자리 (정직하게)
//
//  - 모델의 문맥 개방은 첫 조각 수락에 접혀 있다 (Send 의 Free(c) 갈래 + b
//    선택). 정본 「태그→구간 결속」 규범은 개방을 *개시 wave 디코드 시점*으로
//    확정했고 (D8), 이 RTL 은 그 규범을 따른다 — io.open 이 그 인터페이스다.
//    모델의 「문맥을 새로 열 때 한 번」 ctxBase 확정과 같은 자리다.
//  - 모델의 ASSUME |Ctxs| >= NumTags (문맥 고갈 배제)는 RTL 에서 성립 불가 —
//    태그 공간(2^80)이 어떤 유한 풀보다 크다. 고갈 시 개방은 granted=False 의
//    명시적 거절이다 (fault 아님 — 모델 머리가 고갈의 무처분을 SEC-3 몫으로
//    남겼고, ResultBank acquire 거절과 같은 「규정된 처분」 형태다).
//  - 모델이 ctxFill(개수)과 ctxSeen(집합)을 가른 것은 no_dup_seq 삭제 실험을
//    표현하기 위해서였다. 가드가 강제되는 이 RTL 에서 개수 = |집합| 이
//    구조적으로 성립하므로 seen 하나만 둔다 — 완료 검산은 수신 집합과 선언
//    마스크의 전량 비교다 (훑어 세지 않는다 — 모델 Deliver 해설과 같은 이유).
//  - 순번 0: 모델의 Seqs 는 1부터라 표현이 없었다. §2.4.1 「순번이 구간 안의
//    자리를 정한다」에서 순번은 1..총개수이므로 0 은 선언과 실물의 자기모순 —
//    상한 초과와 같은 malformation 부류로 처분한다 (fr.overRej 에 합류).
//  - 선언 총개수는 첫 수락 조각에서 래치되고, 이후 조각의 선언이 그와 다르면
//    malformation loud fault 다 (fr.totBad). 모델은 total[r] 이 지상 진리라
//    이 축(선언 위조)을 검사하지 않는다고 자백했다 — RTL 은 같은 조각열 안의
//    자기모순만 판정한다 (§4.3 규범 2 「선언과 실물의 자기모순」 부류).
//  - 모델의 ContextAbort 는 창의 slots(데이터)도 비운다. **이 어긋남은
//    2026-08-25 결정 B 로 닫혔다** — 이 RTL 도 소거 시 구간을 비운다. 다만
//    슬롯 실물은 이 모듈 소유가 아니므로(소관 경계 — §3.7.1 상류 사상표·슬롯
//    소유자) *비우는 방식*이 명령이다: io.clr 이 「이 base 의 구간 전체를
//    무효화하라」를 소거 발화와 같은 사이클·같은 게이트로 발한다. 모델의 한
//    원자 스텝이 RTL 에서도 한 사이클이며, 전 슬롯 순회도 정지도 배압도 없다.
//    이행(구간 slotCap 칸의 무효화)은 슬롯 소유자의 의무이고, 그 의무가
//    *묵시가 아니라 면(面)* 이라는 것이 이번 변경의 실물이다.
//  - 모델의 Consume 도 slots 를 비우는데 **그쪽은 여전히 대응이 없다** —
//    그리고 그것이 옳다. 모델의 Deliver 는 slots 를 out 으로 *복사*한 뒤
//    Consume 이 비우지만, 이 RTL 의 io.deliver 는 {태그·결속·총개수}만
//    넘기고 데이터는 구간에 남아 소비자가 읽는다. 인도 시점에 비우면
//    소비자가 읽기 전에 지우는 것이다. 「소비 완료」에 해당하는 사건이 이
//    모듈에 도착하지 않으므로 (정본에 그 통지가 없다 — §4.3 5항은 재사용
//    *전에* 비우라 요구할 뿐 비우는 주체를 이 모듈로 지정하지 않는다) 인도
//    경로의 구간 소거는 소비자 쪽 계약이다. 소거 경로에는 읽을 소비자가
//    아예 없으므로 그 비대칭이 곧 근거다.
//
// ## 이 모듈이 하지 않는 것 (소관 경계)
//
//  - LBID → 물리 슬롯 사상은 여기 없다 (§3.7.1 상류 소관 — ResultBank 와 같은
//    경계). 기입 면(io.wr)은 결속 LBID 와 구간 내 오프셋을 내보내고 물리
//    착지는 사상표 소유자의 몫이다. 구간 밖 좌표가 이 면에 실리지 않는 것
//    (cap_check · base_from_tag)까지가 이 모듈의 계약이다.
//  - 배압·무손실(§2.6)은 SEC-3(NoLoss) 몫이다. 조각 입력은 스트로브다 — 모든
//    조각이 도착 사이클에 처분되므로(수락 또는 loud 거절) 정지가 없다.
//  - 미완 문맥의 회수는 호스트 몫이다 — 타임아웃 금지 (§4.3 조각열 종료 규범
//    4항: 「유실」과 「지연」은 기계적으로 구별 불가능하고, 자의적 마감의
//    만료는 조용한 실패의 다른 이름이다). 이 모듈은 미완 문맥 수를 진단
//    면(io.incomplete)으로 관측 가능하게 하는 것까지다.
//  - ACCTGT 부재 malformation (총개수 >= 2 선언인데 ACCTGT 없음)과 ACCTGT
//    LBID 미사상 route fault (ISA-8) 는 디코드·진입점 소관이다 (§4.3 결속
//    규범 1·2항) — 이 모듈에 도착하는 open 은 이미 그 판정을 지났다.
package wt64.payload

import spinal.core._
import spinal.lib._
import wt64.{Isa, StickyFault, Types, Wt64Config}

/** 인도 통지 — 완성된 구간의 신원 (지역 정의, 승격 후보).
  *
  * 소비자가 구간을 읽는 데 필요한 셋: 태그(누구의 결과인가) · 결속 LBID
  * (구간이 어디인가) · 선언 총개수(구간이 얼마나 긴가 — §2.4.1 「길이는
  * 조각열이 나르는 선언 총개수」).
  */
case class ReassemblyDone() extends Bundle {
  val tag   = Types.Tag()
  val base  = UInt(Isa.LBID_W bits)
  val total = UInt(Isa.FRAG_TOTAL_W bits)
}

/** 조각 재조립 — 재조립 문맥 풀 + 접수 판정 + 종료 판정 (EXT-4, 정본 §4.3).
  *
  * 문맥 = {태그, 결속 LBID, 선언 총개수, 수신 순번 집합, 마지막 표시 관측}.
  * 개방은 개시 인터페이스(io.open — 디코드의 ACCTGT 유래)로만, 결속은 개방 시
  * 1회 확정·종료까지 불변 (D8). 조각(io.frag)은 태그로 문맥을 찾고, 접수
  * 검사는 모델 순서 그대로 능력 → 상한 → 중복이며, 수락이면 기입 면과 회계가
  * 같은 사이클에 원자로 선다. 종료는 마지막 표시가 authority 이고 (D9), 표시
  * 접수 시점에 완전성이 판정된다. 판정은 조합으로 한 번 서고 효과(기입·회계·
  * sticky)만 게이트한다 — 조각 내용이 소요 사이클을 바꾸지 않는다 (D11/D14
  * 상태열 균일 부류: 모든 조각이 같은 1사이클 처분 경로를 지난다).
  *
  * @param cfg   형상 파라미터 — slotCap(구현 슬롯 상한 = 한 구간의 물리 칸 수)
  * @param nCtxs 재조립 문맥 풀 크기 — 유한 (모델의 Ctxs). Wt64Config 승격 후보
  * @param bodyW 조각 본문 폭. 데이터 경로 형상이며 명령·태그 인코딩과 무관
  *              (INV-T1 의 대상이 아니다) — FabricMerge 의 bodyW 와 같은 지위
  */
class Reassembly(val cfg: Wt64Config, val nCtxs: Int = 4, val bodyW: Int = 64) extends Component {
  import Isa.{FRAG_TOTAL_W, LBID_W}

  // 축퇴 배제 — Payload.tla 의 ASSUME 과 동형 (주석만 있는 축퇴 배제는 배제가
  // 아니다 — 모델 머리의 실측 교훈을 elaborate 강제로 옮긴다).
  require(nCtxs >= 2, "축퇴 형상 금지 — Payload.tla ASSUME |Ctxs| >= 2: 문맥이 하나면 key_is_tag 가 공허하다")
  require(cfg.slotCap >= 2, "축퇴 형상 금지 — Payload.tla ASSUME SlotCap >= 2: 한 조각 재조립에는 미완 상태가 없다")
  // 선언 총개수(8비트 전폭)가 slotCap 을 넘는 값을 가질 수 있어야 §2.4.1
  // 규범 4(능력 부재)가 판정할 것을 갖는다 — 모델 Totals == 2..SlotCap+1 동형.
  require(cfg.slotCap <= 254, "능력 부재 축이 표현 가능해야 한다 — slotCap + 1 이 선언 총개수 8비트 값 공간 안이어야 한다")
  require(bodyW >= 1, "본문 폭은 1b 이상")

  /** 구간 내 오프셋 폭 — 물리 좌표이지 명령·태그 필드가 아니다 (INV-T1 무관).
    * slotCap >= 2 이므로 1b 이상이다. */
  private val offW = log2Up(cfg.slotCap)

  val io = new Bundle {
    /** 개시 인터페이스 (D8) — 디코드가 개시 wave 의 ACCTGT 에서 준 목적 LBID
      * 와 태그로 문맥을 연다. 결속은 여기서 1회 확정, 종료까지 불변이다
      * (§4.3 태그→구간 결속). granted 는 같은 사이클의 명시적 처분 — 진행 중
      * 태그(no_restart, loud)나 풀 고갈(fault 아님)이면 False. 허가된 문맥은
      * **다음 사이클부터** 조각을 접수한다 (레지스터 갱신 — ResultBank
      * acquire 의 「소유는 다음 사이클부터 관측」과 같은 처분). */
    val open = new Bundle {
      val valid   = in  port Bool()
      val tag     = in  port Types.Tag()
      val base    = in  port UInt(LBID_W bits)
      val granted = out port Bool()
    }

    /** 조각 도착 — 조각 머리(부록 E.10)와 본문이 같은 beat 에 있다 (도착의
      * 원자성 — 채널이 따로 흐르면 대응 계약이 새로 생긴다). 스트로브인
      * 이유: 모든 조각이 이 사이클에 처분된다 — 수락이면 기입·회계가 원자로
      * 서고, 거절이면 sticky 흔적이 선다. 제3의 결과(대기·유실)가 없으므로
      * ready 가 없다. */
    val frag = new Bundle {
      val valid = in port Bool()
      val head  = in port Types.FragHead()
      val body  = in port Bits(bodyW bits)
    }

    /** 기입 면 — 수락 사이클에 원자로 발화한다 (write_atomic). 좌표는 결속
      * LBID(base)와 구간 내 오프셋(off = 순번-1)이다. LBID → 물리 슬롯
      * 사상은 상류 사상표 소유자의 몫 (§3.7.1) — 이 면에 구간 밖 좌표는
      * 실리지 않는다 (cap_check · base_from_tag). */
    val wr = new Bundle {
      val valid = out port Bool()
      val base  = out port UInt(LBID_W bits)
      val off   = out port UInt(offW bits)
      val body  = out port Bits(bodyW bits)
    }

    /** 인도 — 완성 판정(표시 authority + 총개수 검산)이 선 문맥의 신원.
      * fire 가 소비의 완결이고, 그 사이클에 회계 소거·태그 해방이 함께 선다
      * (reset_on_deliver — §4.3 규범 5). fire 전까지 태그는 그 문맥의
      * 것이므로 재개시는 no_restart 로 거절된다. */
    val deliver = master(Stream(ReassemblyDone()))

    /** 진단 관측면 — 미완 문맥 수 (모델 IncompleteCtx 의 RTL 형: 활성인데
      * 마지막 표시 미접수). 표시 유실은 fault 가 아니고 회수는 호스트 몫이다
      * — 타임아웃 금지 (§4.3 조각열 종료 규범 4항). 그 회수의 실물이 아래
      * abort 다. */
    val incomplete = out port UInt(log2Up(nCtxs + 1) bits)

    /** E.11 점유 관측면 (§3.7 드레인 정의역 ⑤ — 활성 재조립 문맥, 미완
      * *포함*). active popcount — 인도 대기(완성) 문맥도 태그를 쥔 활성이므로
      * 함께 센다 (top 의 「활성 총계 포트 신설 대기」가 이 포트다).
      * io.incomplete(active && !last)와 다른 관측이다 — 그쪽은 표시 유실
      * 진단, 이쪽은 드레인 집계. 조합 집계 — 이미 있는 점유 상태의 배선일
      * 뿐 새 상태가 아니다 (E.11 해설). 폭은 문맥 풀 상한에서 유도 —
      * 관측면이지 인코딩이 아니므로 INV-T1 의 대상이 아니다. */
    val occupancy  = out port UInt(log2Up(nCtxs + 1) bits)

    /** 태그 지정 문맥 소거 (부록 E.12 · §3.7 드레인 완주 가능성) — 호스트
      * MMIO 기입의 스트로브. MMIO 주소·레지스터 사상은 상류(E.1 레지스터 맵
      * 소유자) 몫이고, 이 모듈은 「태그 하나를 지정한 소거 기입」이라는
      * 의미론만 받는다. *태그 80b 를 32b 워드 셋으로 실을 때의 무장 규율*
      * (결정 A — 워드별 무장 · 무장 완비 발화 · 발화 시 잔류 소진)도 그
      * 상류의 것이다 (`wt64.top.AbortStaging`) — 이 면에 valid 가 서는 순간
      * 그 규율은 이미 통과했고, 무장 미완 발화는 여기 도착하지 않는다.
      * 지정 태그에 활성 문맥이 없으면 무시 — 오류도
      * 카운트도 아니다 (E.12 3항: 드레인 경합에서 이미 인도·소거된 문맥의
      * 소거 시도는 정상 경로다). fault 불참 (E.12 2항).
      *
      * 인도 대기(완성) 문맥의 소거도 허용된다 — 그 사이클에 io.deliver.valid
      * 가 서 있었다면 다음 사이클에 fire 없이 내려간다. 이 valid 철회는
      * 호스트가 개시한 폐기의 의도된 관측이다 — 소비자 쪽 계약이 valid 의
      * 지속을 가정한다면 그 가정은 abort 를 쓰는 호스트 규약과 함께 정해야
      * 한다 (모델도 같은 처분 — Deliver 전의 ContextAbort 가 인도를 대체). */
    val abort = new Bundle {
      val valid = in port Bool()
      val tag   = in port Types.Tag()
    }

    /** 구간 무효화 면 — 소거가 회계뿐 아니라 *구간 데이터까지* 비운다는
      * 계약의 실물 (결정 B · 모델 ContextAbort 의 `slots'`). 한 beat 가
      * `base` 결속 구간 전체(칸 slotCap 개)의 무효화를 뜻한다 — 칸마다 한
      * beat 를 내지 않는 이유는 셋이다:
      *
      *  1. *원자성* — 모델의 소거는 한 스텝이다. 순회로 펴면 「회계는 비었는데
      *     구간은 반쯤 낡은」 중간 상태가 sixteen 사이클 동안 관측 가능해지고,
      *     그 상태의 지위를 정본이 정한 적이 없다.
      *  2. *기입 면 무간섭* — io.wr 은 조각 수락과 원자다 (write_atomic).
      *     순회를 그 면에 실으면 소거 중 도착한 조각이 기입을 잃는데, 조각
      *     면은 스트로브라 되미룰 수단이 없다 (§2.6 은 SEC-3 몫이고 이
      *     모듈은 「모든 조각이 도착 사이클에 처분된다」를 계약으로 든다).
      *     별 면으로 두면 그 충돌 자체가 없다.
      *  3. *이행의 자연형* — 구간 무효화의 자연스러운 실물은 데이터 zeroing
      *     이 아니라 칸 유효 비트의 일괄 하강이다. 그쪽에서도 한 사이클이다.
      *
      * *비우는 순서* — §4.3 「소거 후 재사용」 3항은 「결속을 버리기 *전에*
      * 구간을 비운다」를 요구한다: 결속이 비울 대상의 유일한 이름이기
      * 때문이다. 이 면의 base 는 소거와 *같은 사이클의 레지스터 값*(ab.cBase)
      * 이므로 그 순서가 구조로 성립한다 — 결속이 내려가는 것은 다음 사이클
      * 이고, 그때 명령은 이미 떠났다.
      *
      * ⚠ 정본이 아직 정하지 않은 것: *무효화 이행의 완결 시점*이다. E.12 1항
      * 해설이 「요구를 거는 형태(스트로브·핸드셰이크)는 이 문서가 정하지
      * 않는다」로 형태를 위임했으므로 이 스트로브는 그 위임 안에 있으나,
      * 「소거 후 같은 LBID 를 언제부터 재개방해도 안전한가」에는 답이 없다.
      * ABORT_COUNT 는 *명령*의 회계이지 이행의 완결이 아니다 —
      * rtl/README.md 「정본 환류 필요」 등재. */
    val clr = new Bundle {
      val valid = out port Bool()
      val base  = out port UInt(LBID_W bits)
    }

    /** 소거 카운트 — E.12 2항의 회계 관측면 (진단 표면, fault 아님). 포화 —
      * 되감기면 0 이 「소거 없음」으로 읽혀 조용한 소거의 다른 형태가 된다.
      * 해제 입력이 없는 이유: E.12 가 해제를 규정하지 않았다 — 규정 없는
      * 표면을 지어내지 않는다 (§1.3 부류). 8비트는 진단 용도의 자리값이다. */
    val abortCount = out port UInt(8 bits)

    /** malformation·재시작·표시 시점 누락의 loud fault sticky (§4.3 「loud
      * fault」 · §1.6.3 — 합성되는 상태 비트). 명시적 해제 외엔 안 내려간다. */
    val fault      = out port Bool()
    val faultClear = in  port Bool()

    /** 능력 부재 sticky 관측면 — fault 와 *다른 채널*이다 (§1.6.2 — 셋을 한
      * 신호로 접으면 관측자에게 어디를 고쳐야 하는지를 거짓으로 알린다). */
    val capAbsent      = out port Bool()
    val capAbsentClear = in  port Bool()
  }

  // ── 재조립 문맥 풀 — 유한, 태그로 색인하지 **않는다** ────────────────────
  // 모델과 같은 처분: 「태그가 유일 키」는 구조로 참이 되게 하지 않고 검사
  // (op.clash + fr.hit)로 강제한다 — 구조로 참이면 한 번도 시험되지 않는다
  // (모델 머리 「문맥은 태그로 색인되지 않는다 — 그것이 검사 대상이다」).
  val ctx = for (_ <- 0 until nCtxs) yield new Area {
    val active     = RegInit(False)                 // 모델 NoT 표식의 RTL 형
    val tag        = Reg(Types.Tag())               // 서비스하는 태그 — 유일 키
    val base       = Reg(UInt(LBID_W bits))         // 결속 LBID — 개방 시 1회 기입
    val total      = Reg(UInt(FRAG_TOTAL_W bits))   // 선언 총개수 — 첫 수락에서 래치
    val totalKnown = RegInit(False)
    val seen       = Reg(Bits(cfg.slotCap bits)) init 0 // 수신 순번 집합
    val last       = RegInit(False)                 // 마지막 표시 관측 — 종료 authority
  }

  // ── 완전성 마스크 표 — 총개수 t ↦ {1..t} 의 비트 표현 ───────────────────
  // 표 조회다 (사상·조회는 표 — 선형 비교 루프 금지). 조회 색인은 언제나
  // <= slotCap 이다 (capability_check 가 그보다 앞서 거른다).
  private val fullMask = Vec((0 to cfg.slotCap).map(t => B((BigInt(1) << t) - 1, cfg.slotCap bits)))

  /** 총개수 → 완전성 마스크. 호출부가 total <= slotCap 을 보장하므로 이
    * 축소 resize 는 값을 잃지 않는다 (DecodeWalk 의 증명된 상계와 같은 형태). */
  private def maskOf(total: UInt): Bits = fullMask(total.resize(log2Up(cfg.slotCap + 1)))

  // ── 조각 도착 경로 — 접수 검사 순서는 모델 그대로: 능력 → 상한 → 중복 ───
  val fr = new Area {
    val head = io.frag.head

    /** key_is_tag — 탐색의 유일한 키는 태그다. 번들 통비교 (슬라이스 없음 —
      * 태그 조립·분해는 Types.Tag 한 곳). 개방 규율이 태그당 활성 문맥 <= 1
      * 을 유지하므로 one-hot 이다 (MuxOH 의 전제). */
    val hit    = Vec(ctx.map(c => c.active && c.tag === head.tag))
    val hitAny = hit.reduce(_ || _)

    val cBase  = MuxOH(hit, ctx.map(_.base))
    val cTotal = MuxOH(hit, ctx.map(_.total))
    val cKnown = MuxOH(hit, ctx.map(_.totalKnown))
    val cSeen  = MuxOH(hit, ctx.map(_.seen))

    /** 이 조각열의 선언 총개수 — 래치돼 있으면 그것, 첫 조각이면 머리의 선언. */
    val effTotal = cKnown ? cTotal | head.total

    /** capability_check — 능력 부재가 맨 앞이다: 능력 밖 조각열은 나머지
      * 판정의 대상이 아니어서 두 종결이 동시에 서지 않는다 (§1.6.2 · ISA-5
      * 부류 — DecodeWalk judge.mal 의 !capAbsent 와 같은 형태). 8비트 전폭
      * 비교 — 조용한 절단 금지 (§1.3 함정 부류). */
    val capaRej = head.total > cfg.slotCap
    /** 결속 없는 조각 — 개시(ACCTGT 디코드) 없이 도착했다. 조각은 태그만
      * 나르므로(§4.3 결속 규범) 착지가 없고, 조용한 드롭은 금지다 (INV-T3
      * 부류 — 모든 거절이 흔적을 남긴다). */
    val strayRej = !capaRej && !hitAny
    /** 같은 조각열 안의 선언 자기모순 — 래치된 선언과 다른 선언 (§4.3 규범 2
      * 「선언과 실물의 자기모순」 부류 — 파일 머리 「어긋난 자리」 참조). */
    val totBad = !capaRej && hitAny && cKnown && head.total =/= cTotal
    /** cap_check — 순번이 구간 밖: 0 이거나 선언 총개수 초과 (§4.3 규범 2 ·
      * §2.4.1). 8비트 전폭 비교. */
    val overRej = !capaRej && hitAny && !totBad && (head.seq === 0 || head.seq > effTotal)

    /** 구간 내 오프셋 = 순번 - 1, offW 폭 모듈로 산술. overRej 가 앞서 걸러
      * 수락 시 1 <= 순번 <= slotCap 이므로 전폭 계산과 값이 같다 — 축소를
      * 뺄셈 앞에 두는 이유는 폭만이다 (상위 비트는 판정(overRej)이 이미 전폭
      * 으로 소비했다). */
    val off   = head.seq.resize(offW) - 1
    val ohSeq = UIntToOh(off, cfg.slotCap)
    /** no_dup_seq — 이미 받은 순번 (§4.3 규범 2 의 중복 축, 도착 시점 판정). */
    val dupRej = !capaRej && hitAny && !totBad && !overRej && (cSeen & ohSeq).orR

    val accept  = io.frag.valid && hitAny && !capaRej && !totBad && !overRej && !dupRej
    val newSeen = cSeen | ohSeq
    /** last_judges (D9) — 표시가 *접수되는* 시점의 완전성 판정: 갱신 후 수신
      * 집합이 {1..선언 총개수} 와 다르면 누락/중복이다 (§4.3 규범 3). 거절된
      * 조각의 표시는 접수되지 않는다 (accept 게이트 — 모델과 같은 처분:
      * 거절 자체가 이미 loud 이고 문맥에 어떤 흔적도 남기지 않는다). */
    val endBad = head.last && newSeen =/= maskOf(effTotal)

    // 회계 갱신 — 기입 면 발화(아래 io.wr)와 같은 accept 신호·같은 사이클
    // (write_atomic). 둘을 가르는 파이프 단이 없다. 개방 갱신(op)·소거(dv)와
    // 같은 문맥을 다투지 않는다 — accept 는 active 를, 개방은 !active 를
    // 요구하고, 인도 대기(완성) 문맥의 구간 내 순번은 전부 중복이라 accept
    // 가 서지 않는다.
    for ((c, i) <- ctx.zipWithIndex) {
      when(accept && hit(i)) {
        c.seen       := newSeen
        c.last       := c.last || head.last
        c.total      := effTotal
        c.totalKnown := True
      }
    }

    /** 거절 사건 (loud_reject) — 능력 부재만 채널이 다르다 (아래 sticky). */
    val rejEvt  = io.frag.valid && (strayRej || totBad || overRej || dupRej)
    val endEvt  = accept && endBad
    val capaEvt = io.frag.valid && capaRej
  }

  // ── 기입 면 — 수락과 원자 (write_atomic), 좌표는 결속에서만 (base_from_tag)
  io.wr.valid := fr.accept
  io.wr.base  := fr.cBase
  io.wr.off   := fr.off
  io.wr.body  := io.frag.body

  // ── 개시 경로 — 개방·결속 확정 (D8) 과 재시작 판정 (no_restart) ─────────
  val op = new Area {
    /** no_restart — 진행 중 태그(인도 대기 포함)로의 재개시. 태그 통비교. */
    val clash   = ctx.map(c => c.active && c.tag === io.open.tag).reduce(_ || _)
    val free    = Vec(ctx.map(c => !c.active))
    val freeAny = free.reduce(_ || _)
    /** 자유 문맥 선택 — 우선 인코더. 어느 문맥을 고르는가는 계약이 아니다
      * (문맥은 불투명 토큰 — 모델의 Ctxs 와 같다). */
    val freeOh = OHMasking.first(free.asBits)

    val grant = io.open.valid && !clash && freeAny
    io.open.granted := grant
    for ((c, i) <- ctx.zipWithIndex) {
      when(grant && freeOh(i)) {
        c.active := True
        c.tag    := io.open.tag
        // base_from_tag (D8): base 의 유일한 기입 — 개방 시 1회, 값은 디코드가
        // ACCTGT 에서 준 목적 LBID. 조각 경로는 base 를 읽기만 한다.
        c.base       := io.open.base
        c.seen       := 0
        c.last       := False
        c.totalKnown := False
      }
    }
    /** 재시작 충돌 = loud (§4.3 규범 4). 풀 고갈 거절은 fault 가 아니다 —
      * granted=False 의 명시적 처분 (파일 머리 「어긋난 자리」). */
    val clashEvt = io.open.valid && clash
  }

  // ── 인도 — 종료의 authority 는 마지막 표시, 총개수는 검산 (§4.3 삼중 구조)
  val dv = new Area {
    /** 완성 = 표시 관측 + 수신 집합의 전량 검산. 슬롯을 훑어 세지 않는다 —
      * 훑어 세면 구멍 있는 구간의 완성 오판이 구조적으로 불가능해져 검사가
      * 장식이 된다 (모델 Deliver 해설). 상한 안전장치는 capability_check 가
      * 접수 전에 이미 섰다. totalKnown 게이트로 total 레지스터의 미정 값이
      * 판정에 실리지 않는다. */
    val done = Vec(ctx.map(c => c.active && c.last && c.totalKnown && c.seen === maskOf(c.total)))
    val doneAny = done.reduce(_ || _)
    /** 인도 선택 — 우선 인코더. 공정성은 이 모듈의 계약이 아니다 — 인도된
      * 문맥은 fire 로 소거되므로 굶김이 자체 해소되고, 진행 전파는 소비자
      * 쪽 배압 계약(§2.6 · FAB-6 부류)의 몫이다. */
    val grantOh = OHMasking.first(done.asBits)

    io.deliver.valid         := doneAny
    io.deliver.payload.tag   := MuxOH(grantOh.asBools, ctx.map(_.tag))
    io.deliver.payload.base  := MuxOH(grantOh.asBools, ctx.map(_.base))
    io.deliver.payload.total := MuxOH(grantOh.asBools, ctx.map(_.total))

    // reset_on_deliver — 소비 완결·회계 소거·태그 해방이 같은 전이 (§4.3
    // 규범 5: 「재조립 상태를 전부 비운 뒤여야 한다」). fire 전의 문맥은
    // 여전히 태그를 쥐므로 (no_restart 대상) 이중 인도가 없다.
    for ((c, i) <- ctx.zipWithIndex) {
      when(io.deliver.fire && grantOh(i)) {
        c.active     := False
        c.seen       := 0
        c.last       := False
        c.totalKnown := False
      }
    }
  }

  // ── 문맥 소거 — 태그 지정 MMIO 기입 (부록 E.12 · §3.7 드레인 완주 가능성)
  // 이 Area 는 fr(접수 회계)·op(개방)·dv(인도 소거) *뒤*에 있다 — 같은
  // 사이클에 같은 문맥을 다투면 소거가 이긴다 (마지막 대입 우선). 경합 셋:
  //   accept+abort  — 회계 갱신 위에 소거가 덮인다. 그 사이클의 io.wr 발화는
  //                   이미 떠났고, 같은 사이클의 io.clr 이 그 구간을
  //                   무효화한다 — 두 면의 순서는 소유자가 「같은 beat 의
  //                   무효화가 기입을 이긴다」로 닫는다 (소거가 마지막 대입
  //                   우선이라는 이 모듈 안의 규율과 같은 방향). 잔재가
  //                   남는 갈래가 이 파도로 사라졌다.
  //   deliver+abort — 둘 다 같은 소거 규율이라 결과가 같다.
  //   open+abort    — 문맥이 겹칠 수 없다 (grant 는 !active, hit 는 active).
  //                   같은 태그면: abort 는 레지스터 시점을 보므로 이 사이클
  //                   grant 된 문맥을 보지 못하고 무시된다 — 개방 규율의
  //                   「다음 사이클부터 관측」과 같은 처분.
  val ab = new Area {
    /** key_is_tag 와 같은 탐색 규율 — 태그 전량 통비교, one-hot. */
    val hit    = Vec(ctx.map(c => c.active && c.tag === io.abort.tag))
    val hitAny = hit.reduce(_ || _)
    /** 소거 발화 — 없는 태그는 무시 (E.12 3항: 오류도 카운트도 아니다). */
    val fire = io.abort.valid && hitAny
    /** 소거 대상의 결속 LBID — 구간 무효화 좌표. 탐색 규율이 fr.cBase 와
      * 같다 (같은 one-hot, 같은 base_from_tag 원천 — 소거가 「어느 구간을
      * 비우는가」를 스스로 지어내지 않는다). */
    val cBase = MuxOH(hit, ctx.map(_.base))

    // abort_erases — 소거 규율은 reset_on_deliver 와 같다: active(태그 해방)
    // 와 회계(seen·last·totalKnown) 소거가 같은 전이다. 태그만 해방하고
    // 회계를 남기는 경로가 없다. tag·base·total 레지스터는 active 하강으로
    // 관측 불가가 된다 — dv 소거와 같은 처분.
    for ((c, i) <- ctx.zipWithIndex) {
      when(fire && hit(i)) {
        c.active     := False
        c.seen       := 0
        c.last       := False
        c.totalKnown := False
      }
    }

    // abort_leaves_trace — 소거 카운트: 발화와 같은 사이클·같은 게이트(포화).
    // abort_not_fault — 이 Area 는 io.fault 의 set 항에 나타나지 않는다.
    val cnt = RegInit(U(0, 8 bits))
    when(fire && cnt =/= cnt.maxValue) { cnt := cnt + 1 }
  }
  io.abortCount := ab.cnt

  // 구간 무효화 — 회계 소거와 *같은 게이트*다 (결정 B). 두 신호가 같은
  // ab.fire 를 쓰므로 「회계는 비웠는데 구간은 안 비웠다」가 표현 불가다 —
  // write_atomic 이 기입과 회계에 대해 하는 것과 같은 형태의 원자성이며,
  // 그래서 별도의 순서 계약이 생기지 않는다.
  io.clr.valid := ab.fire
  io.clr.base  := ab.cBase

  // ── 진단 관측면 — 미완 문맥 수 (IncompleteCtx 의 RTL 형: active && !last) ─
  io.incomplete := CountOne(Vec(ctx.map(c => c.active && !c.last)))

  // ── E.11 점유 관측면 — 드레인 집계의 실입력 (§3.7 정의역 ⑤) ────────────
  // 활성 문맥 총계 — 미완(!last)도 인도 대기(완성)도 전부 활성이다. 조합
  // popcount, 새 상태 없음 (E.11 해설). incomplete <= occupancy 가 구조로
  // 성립한다 (같은 active 에 !last 연언 하나 차이).
  io.occupancy := CountOne(Vec(ctx.map(_.active)))

  // ── loud fault sticky — malformation(구간 밖·중복·선언 모순·스트레이) ·
  //    재시작 충돌 · 표시 시점 누락 (§4.3 · §5.5: 세운다 / 명시적 해제 외엔
  //    내리지 않는다). capability 는 이 신호에 불참한다 (capability_not_fault).
  io.fault := StickyFault(set = fr.rejEvt || fr.endEvt || op.clashEvt, clear = io.faultClear)

  // ── 능력 부재 sticky — fault 채널과 분리된 관측면 (§1.6.2). StickyFault
  //    헬퍼를 쓰지 않는 이유는 이것이 fault 가 *아니기* 때문이다 — 같은
  //    「해제·발화 동시면 발화가 이긴다」 순서만 승계한다 (관측을 삼키는 창을
  //    만들지 않는다).
  private val capBit = RegInit(False)
  when(io.capAbsentClear) { capBit := False }
  when(fr.capaEvt) { capBit := True }
  io.capAbsent := capBit
}
