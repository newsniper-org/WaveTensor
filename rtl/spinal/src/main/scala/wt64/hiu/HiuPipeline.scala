// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// WT64v1 재구현 — 요청 파이프라인 + 승인 게이팅 (정본 §3.2 전부 · §3.3 ·
// §3.4.1 · §3.6.2 · §5.3 · 부록 E.3 · E.4 · E.11 ①). SEC-2 상태열의 소유자.
//
// 선-formal 계약: Isolation.tla 의 승인 축 (SEC-4 · HIU-11), Decode.tla 의
// 경로 축 (SEC-2 — DecodeWalk 가 「SEC-2 상태열 유닛」으로 위임했던 그
// 유닛이 이 모듈이다), Platform.tla (HIU-8 · HIU-9 · HIU-10).
//
// ── GUARD-MAP ────────────────────────────────────────────────────────────
// GUARD-MAP: Isolation.approve_gates_value -> io.rsp.frame/perm 은 기본 0 구동에 when(granted) 단 한 곳에서만 실린다 — granted = 승인 판정(적중 ∧ 소유 ∧ 자격)이며, 미승인 요청의 값 축 관측은 0 이다 (§3.2 규범 2항 「값이 새면 격리 위반」). 게이트가 값을 통제하는 유일 지점이다
// GUARD-MAP: Isolation.no_early_forward   -> 소비자 인터페이스(io.rsp)에 닿는 배선은 승인 단계(s6) 조합 판정 뒤에만 존재한다 — s3 조회값과 s4·s5 운반 레지스터는 io.rsp 어디에도 배선되지 않는다. io.owner.frame 은 승인 자신의 소유권 조회 주소이고 io.mask.req 는 마스킹 단(s4) 자신의 왕복 요청이다 — 둘 다 소비자가 아니라 파이프 단계의 몸이며, io.mask 는 MaskUnit 외에 결선하지 않는 것이 통합자 결선 계약이다 (io.mask 주석)
// GUARD-MAP: Isolation.query_offpath      -> STRUCTURAL(port-absence) — 이 모듈에 호스트 질의 발행 포트가 없다 — io.hostRsp 는 선택 경로가 밀어 넣는 입력이고, 파이프는 그것을 값(3순위 leg)과 E.3 채움 대기의 해제 조건으로만 소비한다. 질의 왕복(query·qwait)이 단계열 s1..s6 에 존재하지 않는다 (§3.3.1 「질의 왕복은 가변 지연」 — 요청 경로 밖)
// GUARD-MAP: Isolation.query_no_serve     -> 호스트 leg 소비는 조회 캡처(s3→s4)의 when(hit).elsewhen(hostPresent) 값 접기 둘째 가지 하나 — 로컬(채움 바이패스·저장 블록)이 답하면 호스트 응답은 판정·값 어느 축에도 들어갈 수 없다 (§3.6.2 규범 2 최하 순위 · §3.3.1 규범 1 「변환은 장치 안에서 완결」 · HIU-8 로컬 우선. 접기가 승인이 아니라 캡처에 있는 이유는 마스킹(s4)이 승인(s6)에 선행해 마스킹 대상 값이 s4 전에 확정되어야 하기 때문 — 접기 위치는 순위를 바꾸지 않는다)
// GUARD-MAP: Isolation.coh_no_shortcut    -> 단계 전진(advance · 단계 valid 시프트)은 판정·구성 신호와 독립이고, 일관성 가용 신호는 이 모듈에 배선 자체가 없다 — 승인 변종(approve_own/approve_coh)은 판정 입력(io.owner.devOwned)에만 존재하고 단계열은 하나다 (§3.4.1 「일관성이 있어도 규약은 남는다」 · §5.3 상태열 동일성)
// GUARD-MAP: Decode.lookup_unbranched     -> 조회 결과(hit·fromFill·hostPresent)는 s4 캡처 **데이터**로만 흐르고 단계 배치를 바꾸지 않는다 — D12 값 접기도 값 mux 지 단계 mux 가 아니고, 조회 뒤 모든 요청이 마스킹→실행→승인을 무조건 지난다 (단계 선택 mux 부재 — 시프트 구조. E.4 규범 1·2항). 조회 결과가 닿는 유일한 제어는 E.4 3항이 명시 허용한 조회 지점의 일제 정지(advance)다
// GUARD-MAP: Decode.evict_inline          -> 축출 상태가 없다 — 대체(유효 ∧ 태그 불일치, §3.6.2 규범 4)는 미적중과 똑같이 캡처 데이터(anyHit=0)로만 나타나고, 저장 기입은 XlateStore 의 채움 경로(호스트 install, E.3 「장치는 채우지 않는다」)가 요청 경로 밖에서 수행하므로 단계열에 축출이 낄 자리가 구조적으로 없다
// GUARD-MAP: Decode.stall_uniform         -> advance 하나가 파이프 전 단계 레지스터의 공통 enable 이다 — 마스킹 단(s4)의 valid·마스킹 frame 레지스터는 io.mask 왕복 반대편(MaskUnit — io.en 에 같은 advance = io.req.ready 를 물리는 것이 결선 계약)에 있고 나머지 단·필드 전부가 when(advance) 하나 안이다. 정지 원천(외부 io.hold · E.3 미적중 채움 대기)이 무엇이든 파이프 전체가 함께 서고, 요청별·단계별 enable 이 없다 (E.4 3항 「모든 요청이 같은 지점에서 정지 가능하므로 경로가 갈리지 않는다」)
// GUARD-MAP: Platform.xlate_local         -> 변환 값의 1·2순위 원천은 XlateStore(로컬 저장 블록 + 채움 바이패스)다 — 호스트는 install 포트의 채움 공급자일 뿐이고, hostRsp leg 는 로컬이 미적중일 때만 소비되는 최하 순위 가속이라 로컬 판정을 이길 수 없다 (§3.3.1 규범 1·2 — 구조)
// GUARD-MAP: Platform.state_machine_kept  -> 소유권 판정(io.owner.devOwned 의 granted 논리곱 참여)은 승인 조합식에 무조건 존재한다 — 이를 우회하는 elaborate 파라미터도 런타임 구성 비트도 없다 (§3.4.1 「소유권 상태 기계 자체는 그대로 유지한다」 — 판정이 구성 무관하게 상존. 마스킹 우회 파라미터를 두지 않은 판단도 같은 정신이다 — io.mask 주석)
// GUARD-MAP: Platform.owner_check         -> granted 는 devOwned 를 논리곱의 항으로 요구하고, 비소유 적중은 값 차단(io.rsp.frame/perm 이 0 유지) + StickyFault(io.faultPerm) 다 (HIU-10 · §3.2 「비소유 접근의 관측 결과는 값 차단 + loud fault」 · §3.8 권한 위반 — D11 사후 게이팅)
// GUARD-MAP: Platform.flush_on_handoff    -> ENV — 이양 시 비우기는 넘기는 쪽(호스트 소프트웨어)의 의무다 (§3.4.1 규범 3항 「넘기는 쪽이 비운다」 · §3.10 호스트 ABI 경계). 장치 쪽 강제 지점이 없고, 하드웨어 일관성 구성에서의 생략 역시 호스트 ABI 합의 사항이다
//
// ## §3.2 여섯 단계 — 상태열이 곧 계약이다
//
//   s1 접수 → s2 고정지연 → s3 조회 → s4 마스킹 → s5 실행(자리) → s6 승인
//
// 모든 요청이 이 여섯 단을 같은 순서·같은 enable 로 지난다. 적중·대체·
// 미적중은 s4 캡처 데이터로만 갈리고 단계는 갈리지 않는다 — §5.3 이 상수
// 시간성을 「절대 사이클 수」가 아니라 「어느 경로를 타든 같은 상태열」로
// 규정했고, E.4 가 그 상태열을 여섯으로 열거했다.
//
//   - 고정지연(s2)의 길이는 1사이클 상수다. 정본은 목적(「뒤따르는 판정의
//     소요 시간을 관측에서 가리기」)만 주고 길이를 정하지 않았다 — 이 확정은
//     보고서 model_feedback 으로 되돌린다.
//   - 마스킹(s4)은 이제 자리가 아니라 io.mask 왕복이 실물이다 (§5.2 ·
//     부록 E.9 — MaskUnit 인스턴스는 통합자 몫, 아래 「s4 왕복」절).
//   - 실행(s5)은 자리다 — 패브릭으로의 요청 발행이 후속으로 여기 앉는다.
//     §3.2 규범 1항(승인 이전 외부 부수 효과 금지)은 지금 구조로 성립한다:
//     s5 에서 구동되는 모듈 출력이 없다. 후속 착지는 이 성질을 유지해야
//     한다 — 쓰기 발행은 승인 뒤에만 외부로 나간다.
//
// ## s4 왕복 — 마스킹 단의 실물은 모듈 밖(MaskUnit)이다
//
// MaskUnit 의 요청 경로는 경로 무관 고정 1사이클 + 공통 enable 하나다
// (mask/MaskUnit.scala 머리 — SEC-2 전제의 그 유닛 쪽 의무). 그 1사이클
// 레지스터가 s4 의 valid·마스킹 frame 레지스터를 **정확히 대체**한다:
//
//   io.mask.req  = s3 캡처 (valid · part · 접힌 후보 프레임) — s3→s4 캡처
//   io.mask.rsp  = s4 의 몸 (valid · 마스킹된 frame) — s5 가 여기서 캡처
//   결선 계약   = 통합자는 MaskUnit 하나를 req↔rsp 로 직결하고 io.en 에
//                 advance(= io.req.ready)를 물린다. 다른 결선은 없다.
//
// 단계 수·상태열은 불변이다 — 레지스터 한 단의 거처가 모듈 경계 밖일 뿐,
// enable 도 지연도 같다. 판정 데이터(part·write·anyHit·fromFill·비마스킹
// 프레임·perm)는 여전히 이 모듈의 s4 레지스터가 나른다.
//
//   · 값 접기의 위치 — 마스킹(4단)이 승인(6단)에 선행하므로 마스킹 대상
//     프레임은 s4 진입 전에 확정되어야 한다. 따라서 D12 전순서의 이 모듈
//     몫(로컬 > 호스트 leg — XlateStore 가 1>2 를 이미 접었다)은 조회
//     캡처(s3→s4)에서 접는다. 접기 위치는 순위를 바꾸지 않는다
//     (query_no_serve 줄).
//   · 비마스킹 프레임도 s4~s6 이 나른다 — 승인(D11)의 소유권 조회(E.7
//     페이지 소유권 표)는 실프레임 색인이라 마스킹된 값으로는 판정할 수
//     없다. 비마스킹 프레임이 모듈 밖에 닿는 곳은 io.owner.frame(승인
//     자신의 조회 주소) 하나다 — 소비자 값(io.rsp.frame)은 마스킹된
//     프레임이다 (E.9 — 장치 밖으로 나가는 물리 프레임은 마스킹된 것).
//   · 미준비 마스크의 통과는 MaskUnit 의 faultNoMask 가 크게 알린다 —
//     이 모듈은 마스크 준비 상태를 알지 못하고 알 필요도 없다 (경로·
//     상태열이 준비 여부와 무관하게 동일 — §5.3).
//
// ## 마스킹 우회 elaborate 파라미터 — 두지 않는다 (판단)
//
//   · 우회 형상은 s4 의 몸이 없는 두 번째 상태열 변종을 만든다 — §5.3
//     「어느 경로를 타든 같은 상태열」은 형상 사이에도 지켜야 실기와 검증
//     형상이 같은 기계다. 보안 변환을 elaborate 손잡이로 끄는 구조는
//     state_machine_kept 가 소유권 판정에 금지한 것과 같은 부류다.
//   · 테스트 형상은 파라미터 없이 성립한다 — 단독 검증 하네스는 io.mask
//     를 1레지스터 항등 루프백(enable = io.req.ready, frame 무변형)으로
//     되돌리면 된다. 그것은 우회가 아니라 항등 *마스크*라 상태열·지연이
//     실기와 정확히 같다 (MaskUnit 자체도 미준비 파티션에서 XOR 0 항등 —
//     같은 형태다). 미결선 방치는 애초에 불가능하다 — SpinalHDL 은
//     인스턴스의 미구동 입력을 elaborate 오류로 잡는다.
//
// ## E.11 ① — 파이프 점유 관측 (io.occupancy)
//
// 드레인 여섯 카운트의 첫째 「요청 파이프라인 안의 요청」= s1..s6 유효
// 수의 합이다. 순수 조합 배선(popcount)이고 새 상태가 없다 — 관측이
// 상태열에 영향을 줄 수 없는 형태다. s4 의 valid 는 왕복 반대편 것을
// 그대로 센다 (io.mask.rsp.valid — s4 의 몸이 그쪽이므로 그것이 정의다).
//
// ## E.3 미적중 배압 — 정지는 조회 지점 하나, 파이프 전체가 함께 선다
//
// 미적중은 오류가 아니다 (§3.6.2 규범 3). s3 의 요청이 로컬 미적중이고
// 호스트 응답 leg 도 없으면 파이프 전체가 정지하고(missWait → advance 하강)
// 미적중을 sticky 로 알린다 (io.missNotice — fault 가 아니다. §3.8 폴딩
// 규범: 미적중 표시와 fault 는 서로 다른 신호이며 어느 쪽도 다른 쪽을
// 세우지 않는다). 호스트가 항목을 기입하면 채움 바이패스(XlateStore D12
// 1순위)가 같은 사이클에 적중을 세워 정지가 풀린다 — E.3 의 「호스트가
// 기입하면 정지가 풀린다」가 신선도 순서 그대로 구현된 것이다. 타임아웃은
// 두지 않는다 (E.3: 타임아웃은 조용한 실패의 다른 이름).
//
// ## D11 — 소유권·자격 확인은 접근 승인(6) 안이다 (§3.2 규범)
//
// 일곱째 단계도 전단 확인도 없다. s6 에서 소유권 상태(io.owner — 상태
// 기계의 거처는 구성 표면의 페이지 소유권 표, 부록 E.7)를 조합 조회하고,
// 판정은 경로를 가르지 않고 결과를 게이트한다 (사후 게이팅). 비소유·자격
// 미달의 관측 결과는 값 차단 + sticky fault 뿐이고, 타이밍은 승인된 경우와
// 구별 불가능하다 (같은 단계열·같은 enable).
//
// ## flush × 채움 상호작용 — 파이프 관점의 계약 (환류 항목)
//
// XlateStore 는 flush(p) 에서 유효 비트와 함께 파티션 p 의 진행 중 채움
// 버퍼 줄을 취하고, 같은 사이클의 같은 파티션 install 을 거절한다
// (install.ready 하강). 파이프 관점에서 검증한 계약은 둘이다:
//
//   1. flush(p) **다음 에지부터** s3 에서 평가되는 조회는 p 의 이전 컨텍스트
//      항목으로도, flush 이전에 점유된 채움 줄로도 적중할 수 없다 — 채움
//      줄을 함께 취하지 않았다면 flush 뒤 창 하나에서 이전 컨텍스트의 줄이
//      커밋·바이패스 적중해 HIU-2 가 깨졌을 것이다. 현행 구현이 그 창을
//      닫는다 (XlateStore flush 블록이 텍스트상 마지막 — 같은 사이클 커밋을
//      이긴다).
//   2. flush 발화 사이클에 이미 s3 를 지난(s4~s6 의) 요청은 flush 이전
//      변환을 데이터로 들고 승인까지 간다 — 조회 시점 스냅샷이 계약이다.
//      이양 전 요청 경로의 정온(quiesce)은 호스트 ABI 의무다 (§3.4.1 전이
//      시점 규범 · §3.10 — flush_on_handoff ENV 줄과 같은 자리).
//
// 이 상호작용 자체는 어느 모델에도 없다 (XlateStore.tla 에는 채움이,
// Isolation.tla 에는 flush 가 없다) — model_feedback 유지.

package wt64.hiu

import spinal.core._
import wt64._

/** §3.2 요청 파이프라인 + 승인 게이팅.
  *
  * XlateStore 를 품고(조회 = 3단계), 호스트 채움(install)·flush·호스트 응답
  * leg 는 상위로 그대로 낸다. 마스킹 단(s4)의 몸은 io.mask 왕복 반대편의
  * MaskUnit 이다 (인스턴스·결선은 통합자 몫 — 머리 「s4 왕복」절). 소유권
  * 상태 기계(E.7)는 구성 표면 소관이라 io.owner 조회 인터페이스로만 닿는다
  * — 판정은 여기(승인 안)에 있다. */
class HiuPipeline(val cfg: Wt64Config = Wt64Config()) extends Component {
  import XlateStore._

  private val partW = log2Up(cfg.xlateParts)
  private val idxW  = log2Up(cfg.xlateIdx)
  private val tagW  = VPN_W - idxW

  val io = new Bundle {
    /** 요청 접수 (§3.2 1단계 — 가상 주소 + 요청 종류). ready 는 파이프
      * 일제 전진과 같다 — 단계별 ready 는 존재하지 않는다 (stall_uniform). */
    val req = new Bundle {
      val valid = in port Bool()
      val ready = out port Bool()
      val part  = in port UInt(partW bits)
      val vpn   = in port UInt(VPN_W bits)
      /** 요청 종류 — 쓰기면 True. 자격 판정(perm.w/perm.r)의 입력. */
      val write = in port Bool()
    }
    /** 하류 배압 — 파이프 전체를 세우는 유일한 외부 정지원. */
    val hold = in port Bool()
    /** 소유권 조회 (승인 단계 조합, D11) — 상태 기계의 거처는 페이지
      * 소유권 표(E.7, 구성 표면)다. frame 은 승인 자신의 조회 주소이지
      * 소비자 값이 아니다 — 실프레임(비마스킹) 색인이다. */
    val owner = new Bundle {
      val frame    = out port UInt(FRAME_W bits)
      val devOwned = in port Bool()
    }
    /** 마스킹 단(s4)의 왕복 — 반대편은 MaskUnit 하나 (인스턴스는 통합자
      * 몫. 머리 「s4 왕복」절). req 는 s3 캡처(접힌 후보 프레임 + part),
      * rsp 는 s4 의 몸(valid + 마스킹된 프레임)이다. 결선 계약: MaskUnit
      * io.req/io.rsp 에 직결하고 io.en 에 advance(= io.req.ready)를 물린다.
      * 우회 elaborate 파라미터는 두지 않는다 — 판단과 근거는 머리
      * 「마스킹 우회 elaborate 파라미터」절 (테스트 형상은 1레지스터 항등
      * 루프백으로 성립한다). */
    val mask = new Bundle {
      val req = new Bundle {
        val valid = out port Bool()
        val part  = out port UInt(partW bits)
        val frame = out port UInt(FRAME_W bits)
      }
      val rsp = new Bundle {
        val valid = in port Bool()
        val frame = in port UInt(FRAME_W bits)
      }
    }
    /** 호스트 기입 — XlateStore 로 통과 (E.3: 채움 주체는 호스트). */
    val install = new Bundle {
      val valid = in port Bool()
      val ready = out port Bool()
      val part  = in port UInt(partW bits)
      val idx   = in port UInt(idxW bits)
      val tag   = in port UInt(tagW bits)
      val frame = in port UInt(FRAME_W bits)
      val perm  = in port XlatePerm()
    }
    /** 파티션 flush — XlateStore 로 통과 (§3.6.3). */
    val flush = new Bundle {
      val valid = in port Bool()
      val part  = in port UInt(partW bits)
    }
    /** 선택적 호스트 응답 leg 의 원천 (§3.3.1 — 가속이지 authority 아님). */
    val hostRsp = new Bundle {
      val valid = in port Bool()
      val frame = in port UInt(FRAME_W bits)
      val perm  = in port XlatePerm()
    }
    /** 승인 뒤 소비자 인터페이스 — 값 배선은 여기 하나뿐이다. valid 는
      * 승인·거부 공히 요청 퇴장 사이클에 선다 (상태열 균일 — 판정이 관측
      * 시점을 가르지 않는다). frame 은 **마스킹된** 물리 프레임이다 —
      * 마스킹이 요청 경로 안(s4)이므로 승인 뒤에 마스킹할 것이 남지 않는다
      * (E.9 — 장치 밖 물리 프레임은 마스킹된 것). */
    val rsp = new Bundle {
      val valid    = out port Bool()
      val granted  = out port Bool()
      val part     = out port UInt(partW bits)
      val write    = out port Bool()
      /** 진단 — 값이 채움 바이패스(D12 1순위)에서 왔는가. */
      val fromFill = out port Bool()
      val frame    = out port UInt(FRAME_W bits)
      val perm     = out port XlatePerm()
    }
    /** E.11 ① 파이프 점유 — s1..s6 유효 수 (0..6). 순수 조합 관측,
      * 새 상태 없음 (머리 E.11 절). */
    val occupancy = out port UInt(3 bits)
    /** 권한 위반 sticky (§3.8 — 비소유·자격 미달. HIU-10). */
    val faultPerm  = out port Bool()
    val faultClear = in port Bool()
    /** 미적중 sticky 통지 (E.3) — fault 가 아니다 (§3.8 폴딩 규범:
      * 미적중 표시와 fault 는 서로 다른 신호다). */
    val missNotice = out port Bool()
    val missClear  = in port Bool()
  }

  // ── 조회 유닛 — XlateStore 인스턴스 (3단계의 몸) ─────────────────
  val xlate = new XlateStore(cfg)
  xlate.io.install.valid := io.install.valid
  xlate.io.install.part  := io.install.part
  xlate.io.install.idx   := io.install.idx
  xlate.io.install.tag   := io.install.tag
  xlate.io.install.frame := io.install.frame
  xlate.io.install.perm  := io.install.perm
  io.install.ready       := xlate.io.install.ready
  xlate.io.flush.valid   := io.flush.valid
  xlate.io.flush.part    := io.flush.part
  xlate.io.hostRsp.valid := io.hostRsp.valid
  xlate.io.hostRsp.frame := io.hostRsp.frame
  xlate.io.hostRsp.perm  := io.hostRsp.perm

  // ── 단계 레지스터 — 여섯 단, 공통 enable 하나 ────────────────────
  // s1 접수 · s2 고정지연 · s3 조회. 조회까지는 요청 원문만 나른다.
  private val s1 = new Area {
    val valid = RegInit(False)
    val part  = Reg(UInt(partW bits))
    val vpn   = Reg(UInt(VPN_W bits))
    val write = Reg(Bool())
  }
  private val s2 = new Area {
    val valid = RegInit(False)
    val part  = Reg(UInt(partW bits))
    val vpn   = Reg(UInt(VPN_W bits))
    val write = Reg(Bool())
  }
  private val s3 = new Area {
    val valid = RegInit(False)
    val part  = Reg(UInt(partW bits))
    val vpn   = Reg(UInt(VPN_W bits))
    val write = Reg(Bool())
  }

  // 조회는 s3 페이로드의 같은 사이클 조합 판정이다 (XlateStore 계약).
  xlate.io.lookup.valid := s3.valid
  xlate.io.lookup.part  := s3.part
  xlate.io.lookup.vpn   := s3.vpn

  // ── 조회 값 접기 — D12 전순서의 이 모듈 몫 (query_no_serve 의 몸통) ──
  // 로컬(바이패스∨저장 — XlateStore 가 1>2 순위를 이미 접었다) > 호스트
  // 응답. elsewhen 이라 로컬이 답하면 호스트 값은 선택 불가능하다. 접기가
  // 캡처에 있는 이유는 머리 「s4 왕복」절 — 마스킹 대상은 s4 전에 확정.
  private val lookFrame = UInt(FRAME_W bits)
  private val lookPerm  = XlatePerm()
  lookFrame  := 0
  lookPerm.r := False
  lookPerm.w := False
  lookPerm.x := False
  when(xlate.io.rsp.hit) {
    lookFrame := xlate.io.rsp.frame
    lookPerm  := xlate.io.rsp.perm
  } elsewhen (xlate.io.rsp.hostPresent) {
    lookFrame := xlate.io.rsp.hostFrame
    lookPerm  := xlate.io.rsp.hostPerm
  }
  private val lookAny = xlate.io.rsp.hit || xlate.io.rsp.hostPresent

  // 마스킹 왕복의 요청 변 — s3→s4 캡처가 곧 MaskUnit req 다. 반대편
  // 레지스터(en = advance)가 s4 의 valid·마스킹 frame 레지스터를 대체한다.
  io.mask.req.valid := s3.valid
  io.mask.req.part  := s3.part
  io.mask.req.frame := lookFrame

  // s4 마스킹 — 판정 데이터 몫만 이 모듈의 레지스터다. valid 와 마스킹
  // frame 의 거처는 io.mask 왕복 반대편이고(s4Valid 별칭), 비마스킹 frame
  // 은 승인(D11)의 소유권 조회 전용으로 나른다 (E.7 표는 실프레임 색인).
  private val s4 = new Area {
    val part     = Reg(UInt(partW bits))
    val write    = Reg(Bool())
    val anyHit   = Reg(Bool())
    val fromFill = Reg(Bool())
    val frame    = Reg(UInt(FRAME_W bits))
    val perm     = Reg(XlatePerm())
  }
  private val s4Valid = io.mask.rsp.valid

  // s5 실행(자리) · s6 승인 — s4 부터는 마스킹된 프레임도 함께 나른다.
  private class Carry extends Area {
    val valid    = RegInit(False)
    val part     = Reg(UInt(partW bits))
    val write    = Reg(Bool())
    val anyHit   = Reg(Bool())
    val fromFill = Reg(Bool())
    val frame    = Reg(UInt(FRAME_W bits))
    val masked   = Reg(UInt(FRAME_W bits))
    val perm     = Reg(XlatePerm())
  }
  private val s5 = new Carry
  private val s6 = new Carry

  // ── 일제 정지 — 유일한 정지 지점 (stall_uniform 의 CHECK 몸통) ────
  // E.3 미적중 채움 대기: s3 의 요청이 로컬(바이패스·저장) 미적중이고
  // 호스트 응답 leg 도 없으면 선다. 호스트 기입 → 채움 바이패스 적중 →
  // 같은 사이클 해제. E.4 3항이 이 지점 하나를 명시 허용한다.
  private val missWait = s3.valid && !xlate.io.rsp.hit && !xlate.io.rsp.hostPresent
  private val advance  = !io.hold && !missWait
  io.req.ready := advance

  when(advance) {
    s1.valid := io.req.valid
    s1.part  := io.req.part
    s1.vpn   := io.req.vpn
    s1.write := io.req.write

    s2.valid := s1.valid
    s2.part  := s1.part
    s2.vpn   := s1.vpn
    s2.write := s1.write

    s3.valid := s2.valid
    s3.part  := s2.part
    s3.vpn   := s2.vpn
    s3.write := s2.write

    // 조회 스냅샷 캡처 — flush × 채움 계약 2항의 「조회 시점 스냅샷」.
    // valid·마스킹 frame 의 캡처는 io.mask 왕복 반대편에서 같은 enable 로
    // 일어난다 (결선 계약 — 이 when 에 그 두 필드의 대입이 없는 이유).
    s4.part     := s3.part
    s4.write    := s3.write
    s4.anyHit   := lookAny
    s4.fromFill := xlate.io.rsp.fromFill
    s4.frame    := lookFrame
    s4.perm     := lookPerm

    // s5 실행(자리) — 모듈 출력에 닿는 배선이 없다 (§3.2 규범 1항 구조).
    // 마스킹된 프레임은 여기서 왕복 반대편(s4 의 몸)으로부터 캡처된다.
    s5.valid    := s4Valid
    s5.part     := s4.part
    s5.write    := s4.write
    s5.anyHit   := s4.anyHit
    s5.fromFill := s4.fromFill
    s5.frame    := s4.frame
    s5.masked   := io.mask.rsp.frame
    s5.perm     := s4.perm

    s6.valid    := s5.valid
    s6.part     := s5.part
    s6.write    := s5.write
    s6.anyHit   := s5.anyHit
    s6.fromFill := s5.fromFill
    s6.frame    := s5.frame
    s6.masked   := s5.masked
    s6.perm     := s5.perm
  }

  // ── 승인 (6단계) — 판정은 경로를 가르지 않고 결과를 게이트한다 ────
  // 소유권 조회 — 승인 안의 판정 배선 (D11). 조회 주소는 비마스킹
  // 실프레임이다 (E.7 표 색인). E.3 정지 구조상 s6 도달 요청은 적중이지만,
  // 게이트는 캡처된 적중을 다시 요구한다 — 도달 불가능성 논증이 아니라
  // 논리곱이 값을 지킨다.
  io.owner.frame := 0
  when(s6.valid && s6.anyHit) { io.owner.frame := s6.frame }

  // 자격 — 요청 종류 대 권한 (§3.2 「소유권·자격」). 실행 권한(x)은 요청
  // 종류에 실행이 없으므로 판정에 불참하고 값으로만 방출된다.
  private val entitle  = Mux(s6.write, s6.perm.w, s6.perm.r)
  private val granted  = s6.valid && s6.anyHit && io.owner.devOwned && entitle
  private val permViol = s6.valid && s6.anyHit && !(io.owner.devOwned && entitle)

  // 방출 — valid 는 판정과 무관하게 퇴장 사이클에 선다 (상태열 균일).
  io.rsp.valid    := s6.valid && advance
  io.rsp.granted  := granted
  io.rsp.part     := s6.part
  io.rsp.write    := s6.write
  io.rsp.fromFill := s6.fromFill

  // 값 게이트 — approve_gates_value 의 유일 지점. 기본 0, granted 가지
  // 에서만 실린다. frame 은 s4 에서 마스킹된 프레임이다.
  io.rsp.frame  := 0
  io.rsp.perm.r := False
  io.rsp.perm.w := False
  io.rsp.perm.x := False
  when(granted) {
    io.rsp.frame := s6.masked
    io.rsp.perm  := s6.perm
  }

  // ── E.11 ① 파이프 점유 — 조합 popcount, 새 상태 없음 ─────────────
  // s4 의 valid 는 왕복 반대편 것(s4Valid)이다 — s4 의 몸이 그쪽이므로
  // 그것이 정의다 (머리 E.11 절).
  io.occupancy := Seq(s1.valid, s2.valid, s3.valid, s4Valid, s5.valid, s6.valid)
    .map(_.asUInt.resize(3 bits))
    .reduce(_ + _)

  // ── sticky — 합성 상태 비트 (§3.8 · 공용 StickyFault) ────────────
  // 권한 위반(비소유·자격 미달)과 미적중 통지는 서로 다른 신호다 — 어느
  // 쪽도 다른 쪽을 세우지 않는다 (§3.8 폴딩 규범).
  io.faultPerm  := StickyFault(set = permViol, clear = io.faultClear)
  io.missNotice := StickyFault(set = missWait, clear = io.missClear)
}
