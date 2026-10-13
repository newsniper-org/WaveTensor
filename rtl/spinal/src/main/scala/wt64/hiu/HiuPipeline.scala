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
// GUARD-MAP: Isolation.no_early_forward   -> 소비자 인터페이스(io.rsp)에 닿는 배선은 승인 단계(s6) 조합 판정 뒤에만 존재한다 — s3 조회값 · 판정 래치(클래스 끝 lat)와 s4·s5 운반 레지스터는 io.rsp 어디에도 배선되지 않는다. io.owner.frame 은 승인 자신의 소유권 조회 주소이고 io.mask.req 는 마스킹 단(s4) 자신의 왕복 요청이다 — 둘 다 소비자가 아니라 파이프 단계의 몸이며, io.mask 는 MaskUnit 외에 결선하지 않는 것이 통합자 결선 계약이다 (io.mask 주석)
// GUARD-MAP: Isolation.query_offpath      -> STRUCTURAL(port-absence) — 이 모듈에 호스트 질의 발행 포트가 없다 — io.hostRsp 는 선택 경로가 밀어 넣는 입력이고 XlateStore 로 통과할 뿐 파이프가 소비하지 않는다. 질의 왕복(query·qwait)이 단계열 s1..s6 에 존재하지 않는다 (§3.3.1 「질의 왕복은 가변 지연」 — 요청 경로 밖)
// GUARD-MAP: Isolation.query_no_serve     -> 호스트 응답(xlate.io.rsp.hostPresent/hostFrame/hostPerm)은 판정·값 어느 축에도 **무조건** 들어가지 않는다 — 조회 캡처(s3→s4)의 값 접기는 when(hit) 와 클래스 끝 판정 래치의 마지막 대입 when(lat.hit) 둘뿐이고 lookAny = lat.hit ∨ hit 이며, 래치는 로컬 조회값(xlate.io.rsp.hit/frame/perm/fromFill)만 포착한다(포착 조건 latCapture 의 적중 항도 xlate.io.rsp.hit) — 호스트 leg 에 가지가 없다. 전건이 「로컬이 답하면」이 아니라 항상이다 — 로컬 *미적중* 사이클이 정확히 이 가드가 지켜야 할 자리이기 때문이다 (§3.6.2 규범 2 최하 순위 · §3.3.1 규범 1 「변환은 장치 안에서 완결」 · 규범 2 「늘어도 안 된다」 · HIU-8 로컬 우선. 접기가 승인이 아니라 캡처에 있는 이유는 마스킹(s4)이 승인(s6)에 선행해 마스킹 대상 값이 s4 전에 확정되어야 하기 때문)
// GUARD-MAP: Isolation.coh_no_shortcut    -> 단계 전진(advance · 단계 valid 시프트)은 판정·구성 신호와 독립이고, 일관성 가용 신호는 이 모듈에 배선 자체가 없다 — 승인 변종(approve_own/approve_coh)은 판정 입력(io.owner.devOwned)에만 존재하고 단계열은 하나다 (§3.4.1 「일관성이 있어도 규약은 남는다」 · §5.3 상태열 동일성)
// GUARD-MAP: Decode.lookup_unbranched     -> 조회 결과(hit·frame·perm·fromFill)는 s4 캡처와 판정 래치(클래스 끝 lat)의 **데이터**로만 흐르고 단계 배치를 바꾸지 않는다 — D12 값 접기도 래치 값 선택(lat.hit ? 래치값 : 조회값)도 값 mux 지 단계 mux 가 아니고, 조회 뒤 모든 요청이 마스킹→실행→승인을 무조건 지난다 (단계 선택 mux 부재 — 시프트 구조. E.4 규범 1·2항). 래치 포착 enable(latCapture)은 데이터 레지스터의 enable 이지 단계 제어가 아니다. 조회 결과가 닿는 유일한 *단계* 제어는 E.4 3항이 명시 허용한 조회 지점의 일제 정지(advance — missWait 를 거쳐 lookAny = 래치 ∨ 적중 이 든다)다 — 판정이 래치된 요청은 그 정지를 다시 일으키지 않으며, 적중 · 래치 어느 판정이든 같은 단계열을 지난다
// GUARD-MAP: Decode.evict_inline          -> 축출 상태가 없다 — 판정 *전*의 대체(유효 ∧ 태그 불일치, §3.6.2 규범 4)는 미적중과 똑같이 캡처 데이터(anyHit=0)로만 나타나고(판정이 래치된 요청의 캡처는 첫 적중 사이클의 것이다 — W2 판정 래치: 판정 *뒤*의 대체는 그 요청에 보이지 않는다 · hiumask l_hold · 증인 W33), 저장 기입은 XlateStore 의 채움 경로(호스트 install, E.3 「장치는 채우지 않는다」)가 요청 경로 밖에서 수행하므로 단계열에 축출이 낄 자리가 구조적으로 없다
// GUARD-MAP: Decode.stall_uniform         -> advance 하나가 파이프 전 단계 레지스터의 공통 enable 이다 — 마스킹 단(s4)의 valid·마스킹 frame 레지스터는 io.mask 왕복 반대편(MaskUnit — io.en 에 같은 advance = io.req.ready 를 물리는 것이 결선 계약)에 있고 나머지 단·필드 전부가 when(advance) 하나 안이다. 클래스 끝 판정 래치(lat)는 단계 레지스터가 아니다 — 판정 데이터만 들고, advance 에 비워지며(when(advance) 가 첫 가지 · 포착은 .elsewhen(latCapture)), 어느 단의 enable 도 아니다. 정지 원천(외부 io.hold · E.3 미적중 채움 대기 — 판정 전(래치 빔)의 로컬 미적중)이 무엇이든 파이프 전체가 함께 서고, 요청별·단계별 enable 이 없다 (E.4 3항 「모든 요청이 같은 지점에서 정지 가능하므로 경로가 갈리지 않는다」)
// GUARD-MAP: Platform.xlate_local         -> 변환 값의 유일한 원천은 XlateStore(로컬 저장 블록 + 채움 바이패스)다 — 호스트는 install 포트의 채움 공급자일 뿐이다. hostRsp leg 는 이 모듈의 판정(lookAny)·값(lookFrame/lookPerm)·정지(missWait) 어느 축에도 소비되지 않는다 — 포트는 §3.3.1 측정 트랙의 「의도된 미결선」(「응답 비트만 세우고 주소를 반환하지 않는다」)으로 남으며 승격 조건은 「전송 방식별 자격 계약이 규범으로 기록되는 시점」이다 (§3.3.1 규범 1·2 · HIU-11 세 축 — 구조)
// GUARD-MAP: Platform.state_machine_kept  -> 소유권 판정(io.owner.devOwned 의 granted 논리곱 참여)은 승인 조합식에 무조건 존재한다 — 이를 우회하는 elaborate 파라미터도 런타임 구성 비트도 없다 (§3.4.1 「소유권 상태 기계 자체는 그대로 유지한다」 — 판정이 구성 무관하게 상존. 마스킹 우회 파라미터를 두지 않은 판단도 같은 정신이다 — io.mask 주석)
// GUARD-MAP: Platform.owner_check         -> granted 는 devOwned 를 논리곱의 항으로 요구하고, 비소유 적중은 값 차단(granted 의 devOwned 항 — io.rsp.frame/perm 이 0 유지) + 원인별 보고 [4]/[19] 다: 자격 거부는 permViol → io.faultPerm([4]), 자격 허용 ∧ 비소유는 ownViol → 클래스 끝 faultOwn([19]) — 비소유 적중이면 둘 중 정확히 하나가 sticky 로 선다 (HIU-10 · §3.2 「비소유 접근의 관측 결과는 값 차단 + loud fault」 · §3.8 권한 위반 — D11 사후 게이팅)
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
// 미적중은 오류가 아니다 (§3.6.2 규범 3). s3 의 요청이 판정 전(판정 래치 빔)이고 로컬 미적중이면 파이프 전체가 정지하고(missWait → advance 하강)
// 미적중을 sticky 로 알린다 (io.missNotice — fault 가 아니다. §3.8 폴딩
// 규범: 미적중 표시와 fault 는 서로 다른 신호이며 어느 쪽도 다른 쪽을
// 세우지 않는다). 호스트가 항목을 기입하면 채움 바이패스(XlateStore D12
// 1순위)가 같은 사이클에 적중을 세워 정지가 풀린다 — E.3 의 「호스트가
// 기입하면 정지가 풀린다」가 신선도 순서 그대로 구현된 것이다. 풀린 요청은 그 판정을 래치해(클래스 끝 판정 래치) 조회 지점을 떠날 때까지 든다 — 하류 hold 로 머무는 동안 같은 파티션의 다른 커밋이 그 항목을 밀어내도 다시 정지하지 않는다(그래서 정지와 경쟁 커밋이 엇갈려도 채움이 수렴한다). 타임아웃은
// 두지 않는다 (E.3: 타임아웃은 조용한 실패의 다른 이름).
//
// ## D11 — 소유권·자격 확인은 접근 승인(6) 안이다 (§3.2 규범)
//
// 일곱째 단계도 전단 확인도 없다. s6 에서 소유권 상태(io.owner — 상태
// 기계의 거처는 구성 표면의 페이지 소유권 표, 부록 E.7)를 조합 조회하고,
// 판정은 경로를 가르지 않고 결과를 게이트한다 (사후 게이팅). 비소유·자격
// 미달의 관측 결과는 값 차단 + 원인별 sticky fault(자격 [4] · 비소유 [19]) 뿐이고,
// 타이밍은 승인된 경우와 구별 불가능하다 (같은 단계열·같은 enable).
//
// ## flush × 채움 상호작용 — 파이프 관점의 계약 (환류 항목)
//
// XlateStore 는 flush(p) 에서 유효 비트와 함께 파티션 p 의 진행 중 채움
// 버퍼 줄을 취하고, 같은 사이클의 같은 파티션 install 을 거절한다
// (install.ready 하강). 파이프 관점에서 검증한 계약은 둘이다:
//
//   1. flush(p) **다음 에지부터** s3 에서 평가되는 조회(그 에지 뒤의 판정 — 앞서 래치된 판정은 2항)는 p 의 이전 컨텍스트
//      항목으로도, flush 이전에 점유된 채움 줄로도 적중할 수 없다 — 채움
//      줄을 함께 취하지 않았다면 flush 뒤 창 하나에서 이전 컨텍스트의 줄이
//      커밋·바이패스 적중해 HIU-2 가 깨졌을 것이다. 현행 구현이 그 창을
//      닫는다 (XlateStore flush 블록이 텍스트상 마지막 — 같은 사이클 커밋을
//      이긴다).
//   2. flush 발화 사이클에 이미 판정된 요청 — s3 를 지난(s4~s6 의) 요청과 s3 에서 판정이
//      래치된 요청(클래스 끝 판정 래치 — flush 는 래치를 비우지 않는다) — 은 flush 이전 변환을 데이터로 들고 승인까지 간다 — 판정 시점 스냅샷이 계약이다.
//      이양 전 요청 경로의 정온(quiesce)은 호스트 ABI 의무다 (§3.4.1 전이
//      시점 규범 · §3.10 — flush_on_handoff ENV 줄과 같은 자리).
//
// 1항의 창(flush 와 같은 사이클의 install 거절 · 채움 줄 취소)은 어느 모델에도 없다 (XlateStore.tla 에 채움이 · Isolation.tla 에 flush 가 없다) — model_feedback 유지. 2항의 s3 몫(래치된 판정이 flush · V=0 · 대체 커밋을 건넌다)은 XlateObs.tla 판정 래치 절(W2)이 잰다.

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
      val v     = in port Bool() // XLATE_ENTRY_HI [31] — 통과만 한다 (0 = 단일 항목 무효화)
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
    /** 자격 거부 sticky (§3.8 — FAULT_STATUS [4], 자격 미달만. 비소유는 클래스 끝 faultOwn [19]. HIU-10). */
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
  xlate.io.install.v     := io.install.v
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
  // 변환 값의 원천은 XlateStore(바이패스∨저장 — 1>2 순위를 그쪽이 이미
  // 접었다) 하나다. 접기가 캡처에 있는 이유는 머리 「s4 왕복」절 —
  // 마스킹 대상은 s4 전에 확정돼야 한다. 유효 값은 판정 래치 ? 래치값 : 조회값 이다 — 클래스 끝 when(lat.hit) 가 마지막 대입이다.
  //
  // 호스트 응답 leg(xlate.io.rsp.hostPresent/hostFrame/hostPerm)은 이
  // 접기에 **가지를 갖지 않는다**. §3.3.1 규범 2 「지원하는 호스트에서
  // 기능이 *늘어도* 안 된다」 · HIU-11 「켠 구성과 끈 구성이 같은 상태열을
  // 지나고 같은 판정과 같은 값을 관측한다」 — 호스트 leg 이 값·판정·정지
  // 어느 축에라도 들어가면 PE 가 보는 세계가 호스트에 따라 달라진다.
  // 정본 §3.3.1 측정 트랙이 이 상태를 「질의 상태는 응답 비트만 세우고
  // *주소를 반환하지 않는다.*」라 적고, 이어서 「이것은 미완성이 아니라
  // *의도된 미결선*이다」라 못박는다. 이 접기가 그 서술 그대로다 (포트는
  // 남고 소비가 없다 — 승격 조건은 「전송 방식별 자격 계약이 규범으로
  // 기록되는 시점」).
  private val lookFrame = UInt(FRAME_W bits)
  private val lookPerm  = XlatePerm()
  lookFrame  := 0
  lookPerm.r := False
  lookPerm.w := False
  lookPerm.x := False
  when(xlate.io.rsp.hit) {
    lookFrame := xlate.io.rsp.frame
    lookPerm  := xlate.io.rsp.perm
  }
  private val lookAny  = Bool() // 판정 적중 = 판정 래치 ∨ 조회 적중 — 구동은 클래스 끝(아래 missWait 가 읽으므로 선언만 여기)
  private val lookFill = Bool() // 판정 fromFill = 래치 ? 래치값 : 조회값 — 구동은 클래스 끝(s4 캡처가 읽는다)
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
  // E.3 미적중 채움 대기: s3 의 요청이 판정 전(판정 래치 빔)이고 로컬(바이패스·저장)
  // 미적중이면 선다(lookAny = 래치 ∨ 조회 적중 — 구동은 클래스 끝). 정지를 푸는 것은 **항목 기입 하나**다 — 호스트 install →
  // 채움 바이패스(XlateStore D12 1순위) 적중 → 같은 사이클 해제(hold 로 머물면 그 사이클 끝 에지에 판정을 래치한다).
  // E.3 2항 파생 요건이 그 배타성을 축자로 못박는다: 「해제는 정지를
  // 풀지 않는다 — 정지를 푸는 것은 2항의 항목 기입뿐이다」.
  // 그러므로 hostRsp leg 은 이 식의 항이 될 수 없다 — 그것이 항이면
  // 서비스 없는 구성이 영구 정지하는 접근을 서비스 있는 구성이 통과시켜
  // HIU-11 의 *상태열* 축이 깨진다 (§3.3.1 규범 2 「늘어도 안 된다」).
  // E.4 3항이 이 지점 하나를 명시 허용한다.
  private val missWait = s3.valid && !lookAny
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

    // 판정 스냅샷 캡처 — flush × 채움 계약 2항의 「판정 시점 스냅샷」(lookAny · lookFill · lookFrame/lookPerm = 래치 ? 래치값 : 조회값).
    // valid·마스킹 frame 의 캡처는 io.mask 왕복 반대편에서 같은 enable 로
    // 일어난다 (결선 계약 — 이 when 에 그 두 필드의 대입이 없는 이유).
    s4.part     := s3.part
    s4.write    := s3.write
    s4.anyHit   := lookAny
    s4.fromFill := lookFill
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

  // 자격 — 요청 종류 대 권한 (§3.2 「소유권·자격」 · x 는 판정 불참, 값으로만 방출). 보고는 원인별이다 —
  // 자격 거부 → permViol([4]) · 자격 허용 ∧ 비소유 → 클래스 끝 ownViol([19]). 둘은 배타다 (자격이 먼저).
  private val entitle  = Mux(s6.write, s6.perm.w, s6.perm.r)
  private val granted  = s6.valid && s6.anyHit && io.owner.devOwned && entitle
  private val permViol = s6.valid && s6.anyHit && !entitle

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
  // 자격 거부([4])·비소유 접근([19] — 클래스 끝 faultOwn)·미적중 통지는 서로 다른 신호다 —
  // 어느 쪽도 다른 쪽을 세우지 않는다 (§3.8 폴딩 규범).
  io.faultPerm  := StickyFault(set = permViol, clear = io.faultClear)
  io.missNotice := StickyFault(set = missWait, clear = io.missClear)

  // ── 파도 4 (2026-09-26) — 클래스 *끝*: :348 missWait 좌표를 밀지 않는다 ─────
  // (xlatestore.sby · lint_postformal 이 그 줄을 축자로 인용한다). io 번들 밖 포트라
  // 이름에 io_ 접두가 없다 — 조립층 절단 핀은 hiu__installSlotFree · hiu__miss*.
  //
  // 슬롯 여유 통과 (SLOTFREE) — XlateStore.installSlotFree 그대로. 조립의 MMIO ready ·
  // 문의 installReady 가 install.ready 대신 이것을 먹는다 (XlateStore 끝 주석).
  val installSlotFree = out port Bool()
  installSlotFree := xlate.installSlotFree
  // 미적중 관측 값 — 정지 게이트 스냅샷 (선-formal rtl/formal/tla/XlateObs.tla · 판정 E04 (A)).
  // 정지 중(missWait)에만 조회 지점(s3)의 요청을 내고 정지가 없으면 0 이다. s3 은 정지
  // 동안 advance = 0 으로 동결되므로(E.4 3항 — 정지를 푸는 것은 항목 기입뿐) 두 VPN
  // 워드와 파티션이 같은 요청을 말한다. sticky(io.missNotice)는 위 그대로다.
  val missStall = out port Bool()
  val missPart  = out port UInt(partW bits)
  val missVpn   = out port UInt(VPN_W bits)
  missStall := missWait
  missPart  := Mux(missWait, s3.part, U(0, partW bits))
  missVpn   := Mux(missWait, s3.vpn, U(0, VPN_W bits))

  // ── 3.10 v1.0 묶음 RTL 파도 W1 (2026-10-11) — FAULT_STATUS [19] 비소유 프레임 접근 ──────
  // 클래스 *끝*: 위쪽 줄 좌표(:348 missWait 등 — xlatestore.sby · lint_postformal 이 인용)를
  // 밀지 않는다. 선-formal 은 rtl/formal/tla/Platform.tla (가드 entitle_first · own_reported —
  // 원인별 보고: 자격 거부는 [4] 만, 자격 허용 ∧ 비소유는 [19] 만, 한 접근에 둘이 함께 서지
  // 않는다. 거부 채움 R = W = X = 0 은 entitle = 0 이라 언제나 [4] 다).
  //
  // 값 차단 · granted · 상태열은 그대로다 — granted 는 위 승인 줄 그대로(devOwned ∧ entitle)
  // 이고, 바뀐 것은 보고 비트의 귀속뿐이다: 위 permViol 이 자격 거부(¬entitle)로 좁혀졌고,
  // 자격이 허용된 비소유 적중은 여기 ownViol 이 별도 sticky 로 든다. 두 식은 entitle 항으로
  // 배타다. io 번들 밖 포트라 이름에 io_ 접두가 없다 (installSlotFree 관례) — 조립(Wt64Top)
  // 이 faultOwn 을 io.fault.hiuOwn · FAULT_STATUS [19] 로 내고, faultOwnClear 에 0xF84 [19]
  // W1C(fclr(19)) 하나를 물린다. **IO 해제선은 없다** — 표면 이후 축의 규율(Wt64Top
  // io.faultClear 주석)이다. 캡처 워드도 없다 (정본이 [19] 에 캡처를 두지 않는다).
  val faultOwn      = out port Bool()
  val faultOwnClear = in port Bool()
  private val ownViol = s6.valid && s6.anyHit && entitle && !io.owner.devOwned
  faultOwn := StickyFault(set = ownViol, clear = faultOwnClear)

  // ── 3.10 v1.0 묶음 RTL 파도 W2 (2026-10-12) — 판정 래치 (정본 3.6.2 「판정 시점과 판정 래치」) ──────
  // 클래스 *끝*: 위쪽 줄 좌표(missWait 줄 — xlatestore.sby · lint_postformal 이 인용)와 익명 when
  // 이름을 밀지 않는다. 위의 lookAny · lookFill 은 선언만 위에 있고(전방 참조는 elaborate 때 null 이다)
  // 구동은 여기다. 선-formal 은 rtl/formal/tla/XlateObs.tla — 가드 verdict_latch · latch_clears_on_leave ·
  // latch_one_value, 그리고 이 블록의 그럴듯한 오구현 넷(대안 clear_late · capture_beats_clear ·
  // sticky_raw_miss · value_no_latch)이 각각 상주 MUST FAIL run 으로 반증된다.
  //
  // 판정 시점은 조회 지점(s3)에서 요청이 처음 적중한 사이클이다. 그 사이클에 떠나지 못하면(io.hold)
  // 판정(적중 · 프레임 · 권한 · fromFill)을 여기 래치해 떠날 때까지 든다 — 그 사이의 커밋 · flush ·
  // 축출은 이 요청의 판정을 바꾸지 못한다(조회에만 효력). 래치는 단계 레지스터가 아니다: 판정
  // 데이터만 들고, 요청이 떠나는 *그* 에지(advance)에 비워지며, 그 비움이 같은 에지의 포착보다
  // 앞선다(첫 가지). reset 값도 빈 래치다. 상태열은 그대로다 — 래치는 정지 판정(lookAny → missWait)
  // 과 값에만 들고 어느 단의 enable 도 아니다. 이름은 고정이다(이름 있는 Area · 이름 있는 포착
  // 조건 — 익명 when 안의 Reg 가 아니다): lat_hit · lat_frame · lat_perm_r/w/x · lat_fromFill · latCapture.
  private val lat = new Area {
    val hit      = RegInit(False)
    val frame    = Reg(UInt(FRAME_W bits))
    val perm     = Reg(XlatePerm())
    val fromFill = Reg(Bool())
  }
  // 포착 조건 — 판정 전(래치 빔)의 유효 게이트된 로컬 적중. xlate.io.rsp.hit 은 XlateStore 안에서
  // lookup.valid(= s3.valid) 로 게이트된다. 호스트 leg(hostPresent/hostFrame/hostPerm)은 항이 아니다.
  private val latCapture = s3.valid && !lat.hit && xlate.io.rsp.hit
  when(advance) {
    lat.hit := False // 떠나는 그 에지에 비운다 — 같은 에지의 포착보다 앞(첫 가지)
  }.elsewhen(latCapture) {
    lat.hit      := True
    lat.frame    := xlate.io.rsp.frame
    lat.perm     := xlate.io.rsp.perm
    lat.fromFill := xlate.io.rsp.fromFill
  }
  // 유효 판정 — 정지(missWait)와 s4 캡처가 읽는 lookAny · lookFill, 그리고 lookFrame/lookPerm 의 마지막
  // 대입. 마스킹 입력(io.mask.req.frame)과 승인 단 소유권 조회의 원천(s4.frame → s5 → s6 →
  // io.owner.frame)이 같은 lookFrame 한 신호다 — 어느 단도 저장 블록을 다시 읽지 않는다.
  lookAny  := lat.hit || xlate.io.rsp.hit
  lookFill := Mux(lat.hit, lat.fromFill, xlate.io.rsp.fromFill)
  when(lat.hit) {
    lookFrame := lat.frame
    lookPerm  := lat.perm
  }
}

// ── GUARD-MAP — 미적중 관측면(XlateObs.tla)의 파이프라인 쪽 가드 셋 (파도 4) ─────────
// 나머지 셋(obs_stall_live · obs_sticky · obs_read_pure)은 STATUS 워드의 포장과 읽기
// 경로가 사는 top/Wt64Top.scala 파일 끝이 든다. 파일 *끝*에 둔 것은 위 익명 when 의
// 줄 좌표를 밀지 않기 위해서다.
// GUARD-MAP: XlateObs.obs_part_stalled -> missPart = Mux(missWait, s3.part, 0) — 정지 중(missWait = s3.valid ∧ ¬lookAny — ¬(판정 래치 ∨ 조회 적중), W2)에는 조회 지점 s3 의 파티션 그 자체다. s3 는 advance 가 0 인 동안 when(advance) 밖이라 동결된다 — 정지 중에 파티션을 바꾸는 경로가 없다. 판정이 래치된 요청은 그 항목이 밀려나도 정지가 아니므로 0 이다
// GUARD-MAP: XlateObs.obs_vpn_stalled -> missVpn = Mux(missWait, s3.vpn, 0) — 정지 중에는 s3 의 VPN 그 자체다. 미적중 포착 레지스터가 없다(클래스 끝 판정 래치는 *적중* 판정만 잡고 이 Mux 의 값 항이 아니다) — 첫 미적중이 아니라 *지금* 정지한 요청의 VPN 이고, 해제 없이 온 둘째 정지는 둘째 요청의 VPN 을 낸다
// GUARD-MAP: XlateObs.obs_no_residue -> missPart · missVpn 의 Mux 기본 가지가 상수 0 이다 — 정지가 없으면(missWait = 0 — 판정이 래치된 요청 포함) 조회 지점에 산 요청이 있어도 · 끝난 정지가 있었어도 0 이다. 값 가지에 상태가 없으므로(판정 래치는 정지 판정 missWait 에만 들고 값 항이 아니며 떠나는 에지에 비워진다) 끝난 정지의 잔재를 들 자리가 없다

// ── GUARD-MAP — 비소유 프레임 접근 [19] 원인별 보고(Platform.tla 확장)의 파이프라인 쪽 가드 넷 (3.10 v1.0 묶음 RTL 파도 W1) ──
// 다섯째 Platform.owner_check 는 머리 GUARD-MAP 절에 있다(문면만 원인별로 개정 — 키 그대로). 파일
// *끝*에 둔 것은 위 익명 when 과 피인용 좌표를 밀지 않기 위해서다 (XlateObs 절과 같은 이유).
// GUARD-MAP: Platform.entitle_gates_value -> 승인 줄 granted = s6.valid ∧ s6.anyHit ∧ io.owner.devOwned ∧ entitle 의 entitle 항(W1 이 바꾸지 않은 줄) — 자격 거부 접근은 granted = 0 이라 값 게이트 when(granted) 가 io.rsp.frame/perm 을 기본 0 으로 두고 io.rsp.granted 가 내려간다(승인 거부). 처분이 비소유와 같고 갈리는 것은 보고 비트([4] 대 [19])뿐이다. 거부 채움(R = W = X = 0)도 이 항으로 차단되므로 그 요청은 값 없이 퇴장해 드레인이 완주한다
// GUARD-MAP: Platform.perm_entitle_only -> permViol = s6.valid ∧ s6.anyHit ∧ ¬entitle — io.owner.devOwned 는 이 식의 항이 아니다. [4](io.faultPerm = StickyFault(permViol) → Wt64Top io.fault.hiuPerm → FAULT_STATUS B_XLATE_PERM)는 자격 거부에서만 서고, 자격이 허용된 비소유 적중은 [4] 를 세우지 않는다
// GUARD-MAP: Platform.entitle_first -> 클래스 끝 ownViol = s6.valid ∧ s6.anyHit ∧ entitle ∧ ¬io.owner.devOwned 의 entitle 항 — 자격 거부가 비소유를 가린다. permViol(¬entitle) 과 ownViol(entitle) 은 그 항으로 배타라 한 접근이 [4] 와 [19] 를 함께 세우지 않고, 거부 채움은 소유와 무관하게 [4] 만 세운다
// GUARD-MAP: Platform.own_reported -> 클래스 끝 faultOwn = StickyFault(set = ownViol, clear = faultOwnClear) — 자격이 허용된 비소유 장치 접근이 [19] 원천을 세운다(조용한 거부가 아니다). 조립이 faultOwn → io.fault.hiuOwn → faultWords.status(Fault.B_OWN_FRAME = 19) 로 내고(Fault.N_BITS = 20 · 0xF84 예약 [31:20]), 해제는 faultOwnClear = fclr(Fault.B_OWN_FRAME) 하나다 — IO 해제선 없음

// ── GUARD-MAP — 판정 래치(XlateObs.tla 확장)의 파이프라인 쪽 가드 셋 (3.10 v1.0 묶음 RTL 파도 W2) ──
// 모델 머리 「RTL GUARD-MAP 예정 문면」의 RTL 쪽 사실이다. 파일 *끝*에 둔 것은 위 익명 when 과
// 피인용 좌표(missWait 줄)를 밀지 않기 위해서다 (XlateObs · Platform 절과 같은 이유).
// GUARD-MAP: XlateObs.verdict_latch -> missWait = s3.valid && !lookAny 이고 클래스 끝 lookAny := lat.hit || xlate.io.rsp.hit 다 — 판정 래치가 서 있으면 조회가 미적중이어도(그 항목이 같은 파티션의 다른 커밋에 밀려나거나 V=0 · flush 로 철회돼도) 정지가 아니다. 래치 레지스터(이름 고정 Area lat — lat_hit · lat_frame · lat_perm_r/w/x · lat_fromFill)는 latCapture = s3.valid && !lat.hit && xlate.io.rsp.hit 이고 advance 가 0 인(첫 적중에 hold 로 머무는) 사이클 끝 에지에 조회값(hit · frame · perm · fromFill)을 잡는다. 값 쪽은 같은 래치를 따른다 — 클래스 끝 when(lat.hit) 가 lookFrame · lookPerm 의 마지막 대입이고 lookFill = Mux(lat.hit, lat.fromFill, xlate.io.rsp.fromFill) 이라 유효 값 = 래치 ? 래치값 : 조회값 이다. 이 줄은 항 둘(정지 쪽 lookAny · 값 쪽 마지막 대입)을 묶는다 — 값 절반의 반증은 고정 속성 Prop_LatchedSurvivesRetract(대안 value_no_latch)가 든다. 미적중 sticky(io.missNotice = StickyFault(set = missWait))와 관측 missStall · missPart · missVpn 도 같은 missWait 를 읽는다(대안 sticky_raw_miss)
// GUARD-MAP: XlateObs.latch_clears_on_leave -> 클래스 끝 when(advance) { lat.hit := False }.elsewhen(latCapture) { … } — 래치는 요청이 조회 지점을 떠나는 *그* 에지(advance — s3→s4 캡처의 enable 이고 같은 에지에 s2 의 요청이 s3 로 들어온다)에 비워지며(지연 비움이 아니다 — 대안 clear_late), 비움이 첫 가지라 같은 에지의 포착을 이긴다(대안 capture_beats_clear). reset 값도 빈 래치다(lat.hit = RegInit(False)). 그래서 다음 요청은 앞 요청의 판정을 물려받지 않고 자기 조회로만 판정된다
// GUARD-MAP: XlateObs.latch_one_value -> io.mask.req.frame := lookFrame(마스킹 입력)과 s4.frame := lookFrame(→ s5.frame → s6.frame → io.owner.frame — 승인 단 소유권 조회 주소)이 같은 lookFrame 한 신호에서 온다 — 클래스 끝 when(lat.hit) 마지막 대입이 둘에 같은 래치 값을 싣는다. s5 · s6 은 s4.frame 을 나를 뿐이고 어느 단도 저장 블록(xlate.io.rsp)을 다시 읽지 않는다. 권한 · fromFill 도 같은 래치(lookPerm 마지막 대입 · lookFill)를 탄다
