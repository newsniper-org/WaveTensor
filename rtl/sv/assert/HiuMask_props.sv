// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// HiuMask — HiuPipeline × MaskUnit 합성 후-formal 하네스 (§6.3)
//
// 어느 선-formal 모델도 단독 소유하지 않는 첫 **상태열 합성**이다. 결선
// 계약(HiuPipeline.scala io.mask 주석 — 통합자 의무)을 그대로 실물로 잇는다:
//
//   · MaskUnit.io_en   = advance (= HiuPipeline.io_req_ready — 같은 그물)
//   · io.mask.req ↔ MaskUnit.io_req · io.mask.rsp ↔ MaskUnit.io_rsp 직결
//     (io.mask 는 MaskUnit 외에 결선하지 않는다)
//
// 여기서 재는 것 (각 assert 옆에 GUARD-MAP 가드명):
//   · Decode.stall_uniform    — advance 하나가 합성 전 단의 공통 enable.
//     정지 원천(io_hold · E.3 미적중 채움 대기) 무관 전 단이 함께 선다 —
//     MaskUnit 쪽 s4 몸(rValid/rFrame = io_rsp_valid/frame) 포함.
//     그리고 **정지 원천 자체가 그 둘뿐**이다 (2026-08-31 신설 · W2 개정):
//     advance == !io_hold && !(s3_valid && !(x_hit || f_lat)). E.3 2항 파생 요건
//     「정지를 푸는 것은 항목 기입뿐이다」의 관측형이며, 호스트 응답이
//     정지 해제 주체가 될 수 없음을 기계로 세운다. W2 부터 정지는 *판정 전*
//     (판정 래치 지상 진리 f_lat 이 빔)의 로컬 미적중이다 — 판정된 요청은 그
//     항목이 밀려나도 다시 서지 않는다 (아래 W2 항).
//   · Isolation.coh_no_shortcut / Decode.lookup_unbranched — 상태열 균일:
//     검사자 수리(shift 거울 f_v)가 조회 결과·판정·구성 어느 것도 보지 않고
//     io_req_valid 만 advance 로 시프트하는데, 그것이 단 valid 열과 항상
//     일치한다 → 유효 요청의 단 통과 enable-사이클 수는 상수 6 이다
//     (미적중은 advance 정지로만 나타나고 단 배치는 불변 — §5.3·E.4).
//   · Isolation.approve_gates_value — **값축**: io.rsp 값축(frame·perm)이
//     비0 인 사이클은 granted 인 사이클뿐. 승인 게이트가 값을 통제하는
//     유일 지점이다 (Isolation.tla:585-588 RequestApprove 의 obsVal').
//   · Isolation.no_early_forward — **시간축**: 그 값이 실리는 사이클은 거울의
//     6번째 지점(f_v[6] = 승인 단)뿐. 실행(s5)과 승인(s6) 사이의 일시
//     누출 부재 (Isolation.tla:554-558 — 「둘은 같은 규범의 서로 다른 두 항」).
//   · Isolation.query_no_serve / Platform.xlate_local — **양 면 다** 잰다
//     (2026-08-31 확장 · W2 개정). 적중 면: 로컬 저장 leg 이 답했으면(지금
//     적중이거나 판정이 래치됐으면) s4 로 들어가는 값은 그 로컬 판정 값
//     그 자체다(래치면 첫 적중 사이클의 저장 leg 값). **미적중 면**: 판정 전
//     로컬 미적중이면 값은 0 이고 판정 비트는 0 이다 — 호스트 응답이 서
//     있어도 그렇다.
//     종전 판은 적중 면만 재서 정의역이 구멍의 *여집합*이었다: 실제 구멍은
//     「로컬이 답할 때」가 아니라 「로컬이 미적중일 때」에 있었고, 그
//     사이클에 호스트 leg 이 값·판정·정지 셋 다에 들어갔다
//     (§3.3.1 규범 2 「늘어도 안 된다」 위반 · HIU-11 세 축).
//   · Decode.evict_inline — advance 에지의 s4 몸은 조회 데이터 그 자체.
//     대체 전용 상태도 대체 전용 데이터 경로도 없다 (+ 대체 궤적 도달 증인).
//   · Platform.owner_check — granted ⊆ devOwned · 비소유의 값 차단 ·
//     비소유 적중의 loud fault (sticky 상승 + 명시 해제 없는 비하강) — W1 부터
//     *원인별*: 자격 허용 ∧ 비소유는 faultOwn([19] 원천), 자격 거부는
//     io_faultPerm([4]) 이다 (아래 W1 항).
//   · W1 (3.10 v1.0 묶음 RTL 파도 — FAULT_STATUS [19], 2026-10-11) — 선-formal
//     rtl/formal/tla/Platform.tla 의 새 가드 넷. 정본 (좌표 뒤 「」 는 그 줄의 축자):
//       e-defined.typ:527 「권한 비트가 그 접근을 허용하지 않으면 소유와 무관하게 `[4]` 만 서고」
//       e-defined.typ:527 「자격이 허용된 접근이 장치 소유가 아닌 프레임에 닿을 때만 `[19]` 가 선다」
//       e-defined.typ:527 「한 접근에 둘이 함께 서지 않는다」
//       e-defined.typ:527 「값 차단 · 승인 거부 · 상태열」 — 둘의 처분이 같고 갈리는 것은
//         보고 비트뿐이다.
//       e-defined.typ:527 「프레임이 무엇이든 `[4]` 로만 선다」 — 거부 채움(R = W = X = 0).
//     지상 진리는 승인 단의 단 몸(s6_*) + 자유 입력 io_owner_devOwned 로 다시 쓴다 —
//     DUT 의 entitle · permViol · ownViol 를 참조하지 않는다 (아래 f_ent_deny ·
//     f_unowned 선언 해설):
//       Platform.entitle_gates_value — o_grant_entitle (granted ⇒ entitle) ·
//         o_ent_blocked (¬entitle ⇒ ¬granted ∧ 값 0 — o_grant_entitle 과
//         approve_gates_value 에서 유도되는 backstop · owner_check ② 와 같은 처분)
//       Platform.perm_entitle_only — o_perm_rise ([4] 상승 원천은 자격 거부뿐 —
//         devOwned 는 항이 아니다) · o_perm_loud (자격 거부는 [4] 를 세운다)
//       Platform.entitle_first — o_own_rise ([19] 상승 원천은 자격 허용 ∧ 비소유뿐 —
//         거부 채움은 비소유여도 [19] 가 아니다). 두 상승 원천의 전건이 서로소라
//         o_perm_rise ∧ o_own_rise 가 「한 접근에 둘이 함께 서지 않는다」의 정확
//         등식이다.
//       Platform.own_reported — o_own_loud (자격 허용 ∧ 비소유 적중은 faultOwn 을
//         세운다 — 조용한 거부가 아니다) · o_own_hold (해제 없이 안 내려감) ·
//         o_own_clear (해제로 내려감). FAULT_STATUS [19] 배치와 0xF84 [19] 해제
//         라우팅은 조립층 Wt64Top/assembly.sby 몫이다 (hiu 가 그 태스크에서 절단).
//   · (결선 계약) MaskUnit 고정 1사이클 왕복 — req.valid → 다음 enable 에
//     rsp.valid. 계약 문면: MaskUnit.scala io.en/io.req 주석.
//   · Mask.key_write_own_only (2026-09-15 신설, 정본 7fa5f2e — 임대별
//     마스크 키) — 파티션 p 의 키 기입(io_keyWr_valid && io_keyWr_part==p)
//     이후 q≠p 의 maskReady 비트는 그 에지를 건너 그대로다. bind 가
//     MaskUnit 의 io_maskReady 출력(이미 존재하는 포트)을 직접 물어 잰다
//     (HiuPipeline_props 의 s1_valid 등과 같은 내부-신호 tap 방식).
//   · Mask.key_scoped_storage (2026-09-15 신설) — REKEY(p) 가
//     수락된 다음 사이클, 엔진의 유도 초기 상태 워드 0(st_4)은 *그
//     사이클의* p 파티션 키와 같다. 지상 진리는 DUT 의 key 저장 그
//     자체가 아니라 keyWr 입력을 그대로 미러링하는 독립 섀도우
//     (shadow_key) — 검사 어휘로 지상 진리를 적지 않는다는 이 파일의
//     원칙(위 lookAny 해설)과 같은 자리.
//   · Mask.rekey_idle_only (2026-09-15 신설) — REKEY 가 실제로 발화하면
//     그 사이클의 phase 는 IDLE 이었다(io_rekey_ready = !engineBusy 배선의
//     회귀 그물). 이 축의 로직 자체는 이번 파도가 건드리지 않는다 — 설계
//     문면이 요구한 것은 신규 증명이 아니라 회귀 확인이다.
//   · XlateObs.* 파이프라인 절반 (2026-09-26 파도 4 — 미적중 관측 값, 판정 E04 (A)) —
//     HiuPipeline 의 새 출력 missStall · missPart · missVpn 이 정지 게이트 스냅샷이다:
//     missStall = 조회 지점 로컬 미적중(m_obs_stall), 정지 중에는 *그 요청의* 파티션 ·
//     VPN(m_obs_part · m_obs_vpn — 지상 진리는 DUT s3_* 가 아니라 io_req_* 를 advance 로
//     시프트한 독립 거울 f_part · f_vpn), 정지가 없으면 0(m_obs_zero). 거울과 단 몸의
//     일치(m_cap_1..3 — valid 인 단만)는 k-귀납의 보조 불변식이자 그 자체로 「단 데이터가
//     그 요청의 것이다」의 단언이다. STATUS 워드로의 포장은 조립층(assembly.sby)이 잰다.
//   · 미적중 sticky 규약 m_sticky (파도 4) — io_missNotice 의 차기 상태가 정확히
//     (정지 ∨ (sticky ∧ ¬해제)) 다: 정지가 set 이고 해제를 이긴다 · 해제 없이는 내려가지
//     않는다 · 읽기 같은 제3 원천이 없다. XlateObs.obs_sticky 와 XlateSurface 의 mclr_fires ·
//     mclr_needs_one 의 파이프라인 절반을 잰다 (종전 「어느 형식 태스크도 재지 않는다」).
//   · XlateSurface.mclr_keeps_stall 파이프라인 절반 — 새 단언이 아니다. 아래 정지 원천
//     등식(advance == !io_hold && !(s3_valid && !(x_hit || f_lat)) — W2 판정 전 미적중)이 io_missClear 가 자유 입력인
//     합성에서 이미 서 있었다 — 해제가 정지를 풀 수 없다는 것의 관측형이다. 원장이 그
//     절반을 「안 잰다」로 과소 계수하고 있었다 (hiumask.sby §역-변이 KEEPSTALL 실측).
//   · 슬롯 여유 통과 결선 m_slot_pass · m_slot_split (파도 4 SLOTFREE) — HiuPipeline 의
//     installSlotFree 가 XlateStore 의 슬롯 여유 그대로이고, install.ready 와의 차이는
//     같은 파티션 flush 항 하나다 (XlateStore_props.sv a_ready_split 의 합성 쪽 대응).
//   · W2 (3.10 v1.0 묶음 RTL 파도 — 판정 래치, 2026-10-12) — 선-formal
//     rtl/formal/tla/XlateObs.tla 의 새 가드 셋. 정본 (좌표 뒤 「」 는 그 줄의 축자):
//       03-hiu.typ:734 「처음 적중한 사이클이다」 — 판정 시점.
//       03-hiu.typ:737 「같은 값으로 쓰인다」 — 소유권 조회 주소와 마스킹 입력 프레임.
//       03-hiu.typ:742 「전에 다른 커밋이 그 항목을 밀어내도 다시 미적중하지 않는다」
//       03-hiu.typ:1324 「스냅샷을 들고 끝까지 간다」
//     지상 진리 f_lat · f_lfr · f_lperm · f_lfill 은 **DUT 의 래치 레지스터가 아니라**
//     거울 valid f_v[3] · XlateStore 독립 출력 x_hit/x_frame/x_perm_*/x_fromFill ·
//     advance 에서 다시 짓는다 (검사 어휘 규율 — 아래 f_ent_deny · f_unowned · lookAny
//     해설과 같은 자리): 조회 지점의 요청이 처음 적중한 사이클에 떠나지 못하면 그
//     사이클의 조회값을 잡고, 떠나는 에지(advance)에 비운다. 판정 = x_hit ∨ f_lat.
//       XlateObs.verdict_latch — l_hold (래치된 요청이 떠나는 에지의 s4 캡처 = 래치
//         값: frame · perm · fromFill 이 같은 래치를 탄다) · 정지 원천 등식(판정된
//         요청은 다시 서지 않는다) · query_no_serve 두 면 · l_capture_gated (판정은
//         유효 게이트된 적중 x_hit 에서만 선다 — HIU-3 짝)
//       XlateObs.latch_clears_on_leave — l_clear (떠나는 에지 직후 조회 지점의 요청 —
//         연속 전진이면 같은 에지에 s2 에서 들어온 다음 요청 — 의 판정은 그 요청 자신의
//         조회값뿐이다 — 앞 요청의 판정을 물려받지 않는다)
//       XlateObs.latch_one_value — l_one_value (승인 단 소유권 조회 주소 io_owner_frame
//         = 같은 요청이 s3→s4 에서 마스킹에 실은 io_mask_req_frame — 거울 시프트로 잰다)
//       XlateObs.obs_* 파이프라인 절반 — f_stall = f_v[3] ∧ ¬(x_hit ∨ f_lat) 이
//         m_obs_* · m_sticky 로 전파된다 (래치된 요청은 정지가 아니다 — 미적중 sticky
//         의 set 원천도 판정 전 미적중뿐이다)
//     l_clear · l_capture_gated 는 정지 원천 등식 · query_no_serve 두 면을 각각 전진
//     에지 직후 사이클 · 그 뒤 사이클로 좁힌 사영이다 — 이 하네스는 포트(기존 tap)만
//     보므로 DUT 래치를 따로 관측할 길이 없고, 두 단언의 반증력은 격리 실측으로 든다
//     (hiumask.sby 「W2」 절).
//
// ## Mask.rekey_explicit_target 은 조립층이 잰다 — 여기서 앵커하지 않는다
//
// 정본 7fa5f2e "임대별 키의 인코딩 — 창이지 평면 배열이 아니다" 7항의
// MASK_PART(0xEA0) 라우팅(키·논스 두 기입 모두가 같은 창을 거친다, REKEY
// 는 별개 authority)은 **Wt64Top 의 MMIO 디코드**(maskArea) 몫이고, 이
// 합성(HiuPipeline × MaskUnit)은 Wt64Top 을 포함하지 않는다 — MaskUnit
// 자신에는 "창" 개념이 없다: keyWr.part / rekey.part 는 이미 분리된
// 자유 입력으로 이 유닛에 도착한다. 그 가드는 파도 2 에 DELEGATED(Wt64Top)
// 에서 CHECK 로 올랐고 정식 GUARD-MAP 줄은 top/Wt64Top.scala 머리에 있다 —
// 후-formal 은 rtl/formal/sby/Wt64Top/assembly.sby 의 PROVES(a_rekey_iff ·
// a_rekey_part · a_win_pins)다. 엔진이 그 파티션의 저장을 읽는 절반은 아래
// Mask.key_scoped_storage 가 다른 가드 이름으로 잰다. 이 합성은 Wt64Top 을
// 포함하지 않으므로 이 파일에는 그 가드의 앵커를 달지 않는다.
// (2026-09-26 파도 4 — 옛 문면 「DELEGATED 선언」은 승격으로 낡아 있었다.)
//
// 이 태스크가 **재지 않는** 것과 그 근거는 hiumask.sby 머리의
// 「§미측정 잔여」에 적는다 (Isolation.query_offpath 구조 skip ·
// no_early_forward 문면의 오계수 · xlate_local 지속 상태 축 · evict_inline
// 기입 축의 XlateStore 귀속). 거짓 앵커를 다느니 안 재는 것이 낫다.
//
// 대상 SV 는 rtl/generated/ 의 커밋본 그대로 (재생성 금지 — 통합자 보증).

`timescale 1ns/1ps

// ── 합성 top ──────────────────────────────────────────────────────────────
module HiuMask_comp (
  input  wire        clk,
  input  wire        reset,
  // HiuPipeline 외부 표면 (io.mask 제외 전부 노출 — 환경은 자유 입력)
  input  wire        io_req_valid,
  output wire        io_req_ready,
  input  wire [1:0]  io_req_part,
  input  wire [31:0] io_req_vpn,
  input  wire        io_req_write,
  input  wire        io_hold,
  output wire [31:0] io_owner_frame,
  input  wire        io_owner_devOwned,
  input  wire        io_install_valid,
  output wire        io_install_ready,
  input  wire [1:0]  io_install_part,
  input  wire [3:0]  io_install_idx,
  input  wire [27:0] io_install_tag,
  input  wire [31:0] io_install_frame,
  input  wire        io_install_perm_r,
  input  wire        io_install_perm_w,
  input  wire        io_install_perm_x,
  input  wire        io_install_v,        // XLATE_ENTRY_HI [31] — 자유 입력 (파도 3)
  input  wire        io_flush_valid,
  input  wire [1:0]  io_flush_part,
  input  wire        io_hostRsp_valid,
  input  wire [31:0] io_hostRsp_frame,
  input  wire        io_hostRsp_perm_r,
  input  wire        io_hostRsp_perm_w,
  input  wire        io_hostRsp_perm_x,
  output wire        io_rsp_valid,
  output wire        io_rsp_granted,
  output wire [1:0]  io_rsp_part,
  output wire        io_rsp_write,
  output wire        io_rsp_fromFill,
  output wire [31:0] io_rsp_frame,
  output wire        io_rsp_perm_r,
  output wire        io_rsp_perm_w,
  output wire        io_rsp_perm_x,
  output wire [2:0]  io_occupancy,
  output wire        io_faultPerm,
  input  wire        io_faultClear,
  output wire        io_missNotice,
  input  wire        io_missClear,
  // 파도 4 — io 번들 밖 포트 (SLOTFREE 슬롯 여유 · 미적중 관측 값)
  output wire        installSlotFree,
  output wire        missStall,
  output wire [1:0]  missPart,
  output wire [31:0] missVpn,
  // W1 — FAULT_STATUS [19] 원천 (클래스 끝 포트) · 그 해제 (자유 입력 — 조립이
  // 0xF84 [19] 를 잇는다. IO 해제선은 없다)
  output wire        faultOwn,
  input  wire        faultOwnClear,
  // MaskUnit 구성 표면 (자유 입력 — 속성은 구성 무관하게 서야 한다)
  input  wire        io_keyWr_valid,
  input  wire [1:0]  io_keyWr_part,  // 2026-09-15 파도: 정본 7fa5f2e — 키도 창을 거친다
  input  wire [2:0]  io_keyWr_idx,
  input  wire [31:0] io_keyWr_data,
  input  wire        io_nonceWr_valid,
  input  wire [1:0]  io_nonceWr_part,
  input  wire [2:0]  io_nonceWr_idx,
  input  wire [31:0] io_nonceWr_data,
  input  wire        io_rekey_valid,
  output wire        io_rekey_ready,
  input  wire [1:0]  io_rekey_part,
  output wire [3:0]  io_maskReady,
  output wire        io_busy,
  output wire        io_faultNoMask,
  output wire        io_faultNonceDup,
  output wire        io_faultWrDuringRekey,
  input  wire        io_faultClearNoMask,
  input  wire        io_faultClearNonceDup,
  input  wire        io_faultClearWrRekey
);

  // 결선 계약의 실물 — req↔rsp 직결, en = advance(= io_req_ready)
  wire        mask_req_valid;
  wire [1:0]  mask_req_part;
  wire [31:0] mask_req_frame;
  wire        mask_rsp_valid;
  wire [31:0] mask_rsp_frame;

  HiuPipeline u_pipe (
    .io_req_valid       (io_req_valid),
    .io_req_ready       (io_req_ready),
    .io_req_part        (io_req_part),
    .io_req_vpn         (io_req_vpn),
    .io_req_write       (io_req_write),
    .io_hold            (io_hold),
    .io_owner_frame     (io_owner_frame),
    .io_owner_devOwned  (io_owner_devOwned),
    .io_mask_req_valid  (mask_req_valid),
    .io_mask_req_part   (mask_req_part),
    .io_mask_req_frame  (mask_req_frame),
    .io_mask_rsp_valid  (mask_rsp_valid),
    .io_mask_rsp_frame  (mask_rsp_frame),
    .io_install_valid   (io_install_valid),
    .io_install_ready   (io_install_ready),
    .io_install_part    (io_install_part),
    .io_install_idx     (io_install_idx),
    .io_install_tag     (io_install_tag),
    .io_install_frame   (io_install_frame),
    .io_install_perm_r  (io_install_perm_r),
    .io_install_perm_w  (io_install_perm_w),
    .io_install_perm_x  (io_install_perm_x),
    .io_install_v       (io_install_v),
    .io_flush_valid     (io_flush_valid),
    .io_flush_part      (io_flush_part),
    .io_hostRsp_valid   (io_hostRsp_valid),
    .io_hostRsp_frame   (io_hostRsp_frame),
    .io_hostRsp_perm_r  (io_hostRsp_perm_r),
    .io_hostRsp_perm_w  (io_hostRsp_perm_w),
    .io_hostRsp_perm_x  (io_hostRsp_perm_x),
    .io_rsp_valid       (io_rsp_valid),
    .io_rsp_granted     (io_rsp_granted),
    .io_rsp_part        (io_rsp_part),
    .io_rsp_write       (io_rsp_write),
    .io_rsp_fromFill    (io_rsp_fromFill),
    .io_rsp_frame       (io_rsp_frame),
    .io_rsp_perm_r      (io_rsp_perm_r),
    .io_rsp_perm_w      (io_rsp_perm_w),
    .io_rsp_perm_x      (io_rsp_perm_x),
    .io_occupancy       (io_occupancy),
    .io_faultPerm       (io_faultPerm),
    .io_faultClear      (io_faultClear),
    .io_missNotice      (io_missNotice),
    .io_missClear       (io_missClear),
    .installSlotFree    (installSlotFree),
    .missStall          (missStall),
    .missPart           (missPart),
    .missVpn            (missVpn),
    .faultOwn           (faultOwn),
    .faultOwnClear      (faultOwnClear),
    .clk                (clk),
    .reset              (reset)
  );

  MaskUnit u_mask (
    .io_keyWr_valid         (io_keyWr_valid),
    .io_keyWr_part          (io_keyWr_part),
    .io_keyWr_idx           (io_keyWr_idx),
    .io_keyWr_data          (io_keyWr_data),
    .io_nonceWr_valid       (io_nonceWr_valid),
    .io_nonceWr_part        (io_nonceWr_part),
    .io_nonceWr_idx         (io_nonceWr_idx),
    .io_nonceWr_data        (io_nonceWr_data),
    .io_rekey_valid         (io_rekey_valid),
    .io_rekey_ready         (io_rekey_ready),
    .io_rekey_part          (io_rekey_part),
    .io_maskReady           (io_maskReady),
    .io_busy                (io_busy),
    .io_en                  (io_req_ready),   // ← 결선 계약: en = advance
    .io_req_valid           (mask_req_valid),
    .io_req_part            (mask_req_part),
    .io_req_frame           (mask_req_frame),
    .io_rsp_valid           (mask_rsp_valid),
    .io_rsp_frame           (mask_rsp_frame),
    .io_faultNoMask         (io_faultNoMask),
    .io_faultNonceDup       (io_faultNonceDup),
    .io_faultWrDuringRekey  (io_faultWrDuringRekey),
    .io_faultClearNoMask    (io_faultClearNoMask),
    .io_faultClearNonceDup  (io_faultClearNonceDup),
    .io_faultClearWrRekey   (io_faultClearWrRekey),
    // W1 — 0xEC4 캡처 워드 (클래스 끝 출력). 이 합성은 재지 않는다 — 캡처는
    // MaskUnit/engine.sby 가 단독 하네스로 잰다 (미결선 출력).
    .dupCapture             (),
    .clk                    (clk),
    .reset                  (reset)
  );

  // ── ENV assume: 단발 reset 프로토콜 ──────────────────────────────────────
  // 근거: 전원 인가 시 reset 어서션 후 해제 — async-reset 레지스터의 형식
  // 검사 초기화 규약 (설계 자체가 reset 으로 초기 상태를 정의한다. 재어서션
  // 없는 정상 동작 구간이 검사 대상 — GUARD-MAP 의 모든 속성은 reset 밖
  // 문면이다).
  reg f_init = 1'b1;
  always @(posedge clk) f_init <= 1'b0;
  always @(*) begin
    if (f_init) assume (reset);
    else        assume (!reset);
  end

  // ── ENV assume: keyWr / nonceWr / rekey 는 결선상 상호배타다 (2026-09-16
  // 신설, Mask.key_write_own_only 귀납 반례 수리) ───────────────────────────
  // 근거: 정본 E.7 「워드 단위 정의」(e-defined.typ:236-238) — 구성 표면
  // 기입은 「한 워드 쓰기 한 번」이다. Wt64Top.scala 의 MMIO 디코더에서
  // isKey(wordOff < M_KEY_WORDS) · isNonce(wordOff in M_NONCE0 구간) ·
  // isRekey(wordOff == M_REKEY/4) 는 서로 겹치지 않는 오프셋 범위이고,
  // keyWr.valid/nonceWr.valid/rekey.valid 는 전부 `wr && isXxx` 형태로
  // 같은 단일 워드 strobe(wr) 에서 파생된다 — 한 사이클에 최대 하나만
  // 참일 수 있다. 이 유닛은 그 결선을 스스로 표현하지 못하므로(GUARD-MAP
  // 머리말 — keyWr.part/rekey.part 는 이미 분리된 자유 입력으로 도착한다)
  // 상위(Wt64Top)가 보장하는 이 계약을 ENV assume 으로 명시해야 한다.
  //
  // 이것이 없으면 무엇이 깨지는가 (실측, 2026-09-16): k-귀납이
  // Mask.key_write_own_only 에서 UNKNOWN(induction FAIL) 을 냈다 — 같은
  // 사이클에 keyWr(파티션 p)와 nonceWr(파티션 q≠p) 가 **동시에** valid=1
  // 인, 결선상 불가능한 조합을 솔버가 자유롭게 골라 nonceWr 이 떨어뜨린
  // maskReady[q] 를 keyWr 전용 assert 가 위반으로 오판했다(spurious
  // counterexample — RTL 결함이 아니다). 선-formal Mask.tla 의 `Next` 는
  // 애초에 `\/`(상호배타 액션 분기)로 이 제약을 옳게 가졌다 — 후-formal
  // 하네스만 그 제약을 옮기지 않았다.
  //
  // 그 외 assume 없음 — 나머지 기능 입력은 여전히 자유.
  always @(*) if (!f_init) begin
    assume ($onehot0({io_keyWr_valid, io_nonceWr_valid, io_rekey_valid}));
  end
endmodule

// ── HiuPipeline 쪽 검사자 (bind) ──────────────────────────────────────────
module HiuPipeline_props (
  input wire         clk,
  input wire         reset,
  input wire         advance,
  input wire         io_hold,             // 증인 전용 — 정지 *원천*을 갈라 본다
  input wire         io_req_valid,
  input wire         io_mask_rsp_valid,   // 합성에서 MaskUnit.rValid — s4 valid
  input wire         io_rsp_valid,
  input wire         io_rsp_granted,
  input wire [31:0]  io_rsp_frame,
  input wire         io_rsp_perm_r,
  input wire         io_rsp_perm_w,
  input wire         io_rsp_perm_x,
  input wire         s1_valid,
  input wire         s2_valid,
  input wire         s3_valid,
  input wire         s5_valid,
  input wire         s6_valid,
  input wire [288:0] f_stage_data,        // 전 단 수송 몸체 레지스터 연접
  // ── 2차 파도 신설 tap (전부 HiuPipeline 스코프의 평범한 신호다 —
  //    줄번호 매인 생성 이름 when_*_l<N> 은 하나도 쓰지 않는다) ───────────
  input wire         io_owner_devOwned,   // 소유권 판정 입력 (자유 입력)
  input wire         io_faultPerm,        // sticky 권한 위반 (관측면 출력)
  input wire         io_faultClear,       // 그 명시 해제 (자유 입력)
  input wire         io_flush_valid,
  input wire [1:0]   io_flush_part,
  input wire         io_hostRsp_valid,
  // 파도 3 — V=0 설치(단일 항목 무효화)의 관측. 대체 추적기가 「유효 비트는
  // 커밋이 세우기만 한다」에 기대던 것을 V=0 커밋이 깬다 (아래 f_ev_seen).
  input wire         f_kill,              // io_install 수락 ∧ v = 0
  input wire [1:0]   f_kill_part,
  input wire [31:0]  io_hostRsp_frame,
  input wire [1:0]   s3_part,
  input wire [31:0]  s3_vpn,
  input wire         s4_anyHit,
  input wire         s4_fromFill,
  input wire [31:0]  s4_frame,
  input wire         s4_perm_r,
  input wire         s4_perm_w,
  input wire         s4_perm_x,
  input wire         s6_anyHit,
  input wire         s6_write,
  input wire         s6_perm_r,
  input wire         s6_perm_w,
  // 조회 응답 — XlateStore 인스턴스 출력 (로컬 저장 leg + 호스트 leg 분리)
  input wire         x_hit,               // xlate.io_rsp_hit   (로컬 leg 판정)
  input wire         x_fromFill,          // xlate.io_rsp_fromFill
  input wire [31:0]  x_frame,             // xlate.io_rsp_frame (로컬 leg 값)
  input wire         x_perm_r,
  input wire         x_perm_w,
  input wire         x_perm_x,
  input wire         x_hostPresent,       // xlate.io_rsp_hostPresent (호스트 leg)
  // 값 접기 결과 — s4 로 들어가는 것 (io.mask.req.frame 과 같은 그물)
  //
  // ※ `lookAny` tap 은 2026-08-31 파도가 **뺐다**. 그것은 DUT 자신의 판정
  //    어휘였고, 지상 진리로 쓰는 순간 「lookAny 가 무엇으로 정의되든 참」인
  //    등식이 된다 — 아래 지상 진리 선언(옛 `f_nonowned_hit` — W1 에서 f_ent_deny · f_unowned 로 갈림)이 스스로
  //    적어 둔 함정을 이 자리에서만 어기고 있었다 (「검사 어휘로 지상 진리를
  //    적으면 그 신호를 지운 구현에서 전건이 함께 사라진다」 — 좌표가 아니라
  //    식별자로 가리킨다. 줄 좌표는 이 파일을 고칠 때마다 미끄러지고, 실제로
  //    이 파도의 첫 판이 그렇게 미끄러졌다). 판정 축의 지상 진리는 XlateStore 의
  //    독립 출력 `x_hit` 하나다. (수리로 lookAny 는 넷 자체가 사라졌다 —
  //    「그 신호를 지운 구현에서 전건이 함께 사라진다」의 실물이다.)
  input wire [31:0]  lookFrame,
  input wire         lookPerm_r,
  input wire         lookPerm_w,
  input wire         lookPerm_x,
  // ── 파도 4 tap (2026-09-26) — 전부 HiuPipeline 스코프의 평범한 이름이다 ──────
  input wire [1:0]   io_req_part,         // 거울 f_part 의 원천 (자유 입력)
  input wire [31:0]  io_req_vpn,          // 거울 f_vpn 의 원천 (자유 입력)
  input wire [1:0]   s1_part,
  input wire [31:0]  s1_vpn,
  input wire [1:0]   s2_part,
  input wire [31:0]  s2_vpn,
  input wire         missStall,           // 미적중 관측 값 (클래스 끝 포트)
  input wire [1:0]   missPart,
  input wire [31:0]  missVpn,
  input wire         io_missNotice,       // 미적중 sticky (관측면 출력)
  input wire         io_missClear,        // 그 해제 (자유 입력)
  input wire         io_install_valid,
  input wire         io_install_ready,
  input wire [1:0]   io_install_part,
  input wire         installSlotFree,     // 슬롯 여유 (클래스 끝 포트)
  // ── W1 tap (2026-10-11) — FAULT_STATUS [19] · 승인 단 프레임 ───────────────
  input wire [31:0]  s6_frame,            // 승인 단의 저장 프레임 (증인 W26 — 막힌 값이 비0)
  input wire         faultOwn,            // [19] 원천 sticky (클래스 끝 포트)
  input wire         faultOwnClear,       // 그 해제 (자유 입력)
  // ── W2 tap (2026-10-12) — 판정 래치의 두 소비자. 둘 다 HiuPipeline 의 기존 포트다 —
  //    DUT 의 래치 레지스터는 tap 하지 않는다 (지상 진리는 아래 f_lat — 검사 어휘 규율) ──
  input wire [31:0]  io_mask_req_frame,   // 마스킹 입력 프레임 (s3→s4 캡처 = MaskUnit io_req_frame)
  input wire [31:0]  io_owner_frame       // 승인 단 소유권 조회 주소 (s6)
);
  // f_ok — 「직전 에지도 이번 에지도 reset 밖」. $past(reset) 을 쓰지 않고
  // 명시 레지스터로 지연시킨다: yosys 0.66 은 clocked block 밖의 $past 를
  // 거절한다 (실측 ERROR). 의미는 동일하며 MemOrderGate/Reassembly/XlateStore
  // 하네스와 같은 관용구다.
  reg f_past_valid = 1'b0;
  reg f_past_reset = 1'b1;
  always @(posedge clk) begin
    f_past_valid <= 1'b1;
    f_past_reset <= reset;
  end
  wire f_ok = f_past_valid && !reset && !f_past_reset;

  // 상태열 거울 — io_req_valid 만 advance 로 시프트. 조회 결과·판정을 일절
  // 보지 않는 수리이므로, 아래 일치 assert 가 서면 단 통과가 요청 내용과
  // 무관(상수 6 enable-사이클)임이 증명된다.
  reg [6:1] f_v = 6'h0;
  always @(posedge clk) begin
    if (reset)        f_v <= 6'h0;
    else if (advance) f_v <= {f_v[5:1], io_req_valid};
  end

  // ── W2 (2026-10-12) — 판정 래치의 지상 진리 ─────────────────────────────
  // 정본의 판정 시점은 조회 지점의 *첫 적중 사이클*이고 판정은 요청이 떠날 때까지
  // 유지된다. 그 「판정」을 DUT 의 래치 레지스터가 아니라 거울 valid f_v[3] ·
  // XlateStore 독립 출력 x_* · advance 에서 다시 쓴다 — DUT 래치를 지상 진리로
  // 삼으면 래치를 잘못 지은 구현에서 등식이 함께 선다 (포트 목록의 lookAny 해설 ·
  // 아래 f_ent_deny 선언과 같은 규율). 조회 지점의 요청이 적중한 사이클에 떠나지
  // 못하면(advance = 0) 그 사이클 끝 에지에 조회값을 잡고, 떠나는 에지에 비운다.
  // 첫 적중 사이클에 바로 떠나는 요청은 래치가 필요 없다 — 판정 값이 그 사이클의
  // 조회값이다. 래치가 서 있으면 조회 지점의 요청은 유효하다(f_lat ⇒ f_v[3] —
  // 포착이 f_v[3] 을 요구하고 f_v[3] 이 바뀌는 에지는 advance 뿐이며 그 에지가
  // 래치를 비운다).
  reg        f_lat = 1'b0;
  reg [31:0] f_lfr;
  reg [2:0]  f_lperm;                    // {x, w, r}
  reg        f_lfill;
  always @(posedge clk) begin
    if (reset)        f_lat <= 1'b0;
    else if (advance) f_lat <= 1'b0;
    else if (f_v[3] && !f_lat && x_hit) begin
      f_lat   <= 1'b1;
      f_lfr   <= x_frame;
      f_lperm <= {x_perm_x, x_perm_w, x_perm_r};
      f_lfill <= x_fromFill;
    end
  end
  // 판정 — 적중(지금 로컬 적중이거나 판정이 래치됨)과 그 값(래치면 래치 값).
  wire        f_jhit  = x_hit || f_lat;
  wire [31:0] f_jfr   = f_lat ? f_lfr   : x_frame;
  wire [2:0]  f_jperm = f_lat ? f_lperm : {x_perm_x, x_perm_w, x_perm_r};

  // 마스킹 입력 프레임 거울 — io_mask_req_frame 을 s4..s6 로 advance 에 시프트한다
  // (l_one_value: 승인 단의 소유권 조회 주소가 *같은 요청이* 마스킹에 실은 값이다).
  reg [31:0] f_mf4, f_mf5, f_mf6;
  always @(posedge clk) begin
    if (advance) begin
      f_mf4 <= io_mask_req_frame;
      f_mf5 <= f_mf4;
      f_mf6 <= f_mf5;
    end
  end

  // 지상 진리 — 승인 단에 선 적중의 원인별 둘(자격 거부 · 자격 허용 ∧ 비소유). DUT 의 permViol · ownViol
  // 신호를 참조하지 않고 단 몸과 자유 입력으로 다시 쓴다 (검사 어휘로
  // 지상 진리를 적으면 그 신호를 지운 구현에서 전건이 함께 사라진다).
  //
  // W1 (2026-10-11) — 옛 단일 술어 `f_nonowned_hit`(= 적중 ∧ ¬(devOwned ∧ entitle))를
  // 원인별 둘로 갈랐다. 정본이 자격을 먼저 두므로 두 술어는 정의상 서로소이고 합이 옛
  // 술어다: f_ent_deny ∨ f_unowned ≡ f_nonowned_hit. 자격(entitle)도 DUT 의 entitle
  // 넷이 아니라 승인 단의 단 몸(쓰기면 W · 읽기면 R)에서 다시 쓴다.
  wire f_entitle  = s6_write ? s6_perm_w : s6_perm_r;
  wire f_ent_deny = s6_valid && s6_anyHit && !f_entitle;                        // → [4] 만
  wire f_unowned  = s6_valid && s6_anyHit &&  f_entitle && !io_owner_devOwned;  // → [19] 만

  always @(posedge clk) begin
    if (f_ok) begin
      // Isolation.coh_no_shortcut · Decode.lookup_unbranched — 상태열 균일:
      // 거울과 단 valid 열의 전 지점 일치 (s4 는 MaskUnit rValid — 합성 결선)
      assert (f_v[1] == s1_valid);
      assert (f_v[2] == s2_valid);
      assert (f_v[3] == s3_valid);
      assert (f_v[4] == io_mask_rsp_valid);
      assert (f_v[5] == s5_valid);
      assert (f_v[6] == s6_valid);
      // 응답은 정확히 6번째 enable 지점에서만 — 이르지도 늦지도 않다
      assert (io_rsp_valid == (f_v[6] && advance));

      // Decode.stall_uniform — advance 하나가 전 단의 공통 enable. 정지
      // 원천 무관 전 단이 함께 선다. (sticky fault 레지스터
      // _zz_io_faultPerm/_zz_io_missNotice 는 단 수송 몸체가 아니라 제외 —
      // GUARD-MAP 문면의 "나머지 단·필드" = when(advance) 안의 것들.)
      if (!$past(advance)) begin
        assert ($stable({s1_valid, s2_valid, s3_valid, s5_valid, s6_valid}));
        assert ($stable(f_stage_data));
      end

      // ── Decode.evict_inline — 캡처 축 (2026-08-26 신설) ─────────────────
      // 전진 에지의 s4 몸은 *그 요청의 판정 데이터 그 자체*다 — 판정 전이면 그 사이클의 조회 데이터, 판정이 래치된 요청이면 첫 적중 사이클의 조회 데이터다(W2 — 아래 l_hold; 판정 *뒤*의 대체는 그 요청에 보이지 않는다). 대체
      // (유효 ∧ 태그 불일치)에 전용 상태도, 전용 데이터 경로도, 전용
      // 판정 비트도 없다 — 판정 *전*의 대체는 미적중과 똑같이 anyHit=0 캡처로만
      // 나타난다. 축출 상태를 둔 구현(대체 사이클에 다른 것을 싣거나
      // 단을 한 번 더 도는 구현)이면 여기서 반례가 난다.
      //   ※ 항진 아님: s4_* 는 EN=advance 인 DFF, $past(·) 는 EN=1 인
      //     별개의 그림자 DFF 다. 두 셀이 병합될 수 없으므로 등식이
      //     상수로 접히지 않는다 (완료 기준 ②).
      //   ※ 판정 비트의 우변은 `x_hit` 다 — 종전 판(2026-08-26)은
      //     `$past(lookAny)` 였고, 그것은 DUT 의 판정 어휘를 지상 진리로
      //     삼아 lookAny 의 정의가 무엇이든(hit || hostPresent 여도) 참이
      //     되는 등식이었다. 옛 `f_nonowned_hit` 선언의 규율을 permViol 에만
      //     지키고 이 자리에 빠뜨린 결함이다 (2026-08-31 수리). x_hit 는
      //     XlateStore 소유의 독립 출력이라 접기 정의와 무관하다.
      //   ※ 반증력 실측 — 아래 §반증력 실측표의 ① 항.
      //   ※ W2 (2026-10-12) — 판정 비트의 우변을 `$past(x_hit || f_lat)` 로 넓혔다:
      //     래치된 요청은 그 항목이 밀려나 x_hit 이 내려가도 적중으로 떠난다
      //     (03-hiu.typ:742 「전에 다른 커밋이 그 항목을 밀어내도 다시 미적중하지 않는다」).
      //     fromFill 은 래치되지 않은 전진만 여기서 잰다 — 래치된 전진의 fromFill ·
      //     frame · perm 은 l_hold 가 래치 값으로 잰다. frame · perm 은 여전히
      //     「s4 몸 = 그 사이클의 접기 결과 lookFrame」 전달 등식이고, 접기 결과가
      //     판정 값이라는 것은 query_no_serve 두 면이 잰다.
      if ($past(advance)) begin
        e_cap_hit: assert (s4_anyHit == $past(f_jhit));
        assert (s4_frame    == $past(lookFrame));
        assert ({s4_perm_x, s4_perm_w, s4_perm_r}
                  == $past({lookPerm_x, lookPerm_w, lookPerm_r}));
      end
      if ($past(advance && !f_lat))
        e_cap_fill: assert (s4_fromFill == $past(x_fromFill));

      // ── XlateObs.verdict_latch — l_hold (W2, 2026-10-12) ──────────────────
      // 판정이 래치된 요청이 떠나는 에지의 s4 캡처는 래치 값 그 자체다 — 판정 데이터의
      // 필드(fromFill · frame · perm)마다 같은 래치를 탄다 (XlateObs.tla 닫힌 목록 5 의
      // 몫). 그 사이의 대체 커밋 · V=0 · flush · 같은 파티션 축출이 무엇을 했든
      // 03-hiu.typ:1324 「스냅샷을 들고 끝까지 간다」. 값 쪽 마지막 대입(lookFrame ·
      // lookPerm 의 래치 가지)을 지운 구현 — 선-formal 대안 value_no_latch — 과
      // fromFill 을 조회값에서 다시 읽는 구현이 여기서 반례를 낸다. 래치가 없는
      // 구현(W2 전 RTL)은 같은 VPN 의 대체 커밋 뒤에 떠나는 궤적과 채움 바이패스로
      // 판정돼 저장에서 떠나는 궤적(fromFill 1 → 0)에서 반례를 낸다.
      if ($past(advance && f_lat))
        l_hold: assert ({s4_fromFill, s4_frame, s4_perm_x, s4_perm_w, s4_perm_r}
                        == $past({f_lfill, f_lfr, f_lperm}));

      // ── Platform.owner_check ③ — loud fault (승격 항목 1: fault 축) ─────
      // 승인 단에 선 적중이 원인별 sticky 를 *다음 에지에* 세운다 — 자격 거부는
      // [4](io_faultPerm) · 자격 허용 ∧ 비소유는 [19](faultOwn). 전건은 permViol ·
      // ownViol 의 재인용이 아니라 지상 진리(승인 단의 단 몸 + 자유 입력 devOwned)로
      // 적는다 — 그래야 그 신호를 지워도 반례가 난다. 해제와의 우선순위는 RTL 이 세움
      // 우선이므로 해제를 전건에서 빼지 않는다 (뺐다면 그것이 반례 원천).
      //
      // W1 — 원인별로 갈랐다. 자격 거부는 [4](io_faultPerm), 자격 허용 ∧ 비소유는
      // [19](faultOwn). 옛 단언 `$past(f_nonowned_hit) → io_faultPerm` 은 자격 허용 ∧
      // 비소유에서도 [4] 를 요구했으므로 W1 RTL 에서 *반례가 나는 것이 옳다* — 그 절반이
      // 아래 o_own_loud 로 옮겨 갔다.
      // Platform.perm_entitle_only — 자격 거부는 [4] 를 세운다 (해제와 겹쳐도).
      if ($past(f_ent_deny))
        o_perm_loud: assert (io_faultPerm);
      // 그리고 명시 해제 없이는 내려가지 않는다 — 「크게 알린다」의 둘째 항.
      if ($past(io_faultPerm) && !$past(io_faultClear))
        assert (io_faultPerm);
      // Platform.perm_entitle_only — [4] 의 상승 원천은 자격 거부뿐이다: devOwned 는
      // 항이 아니다. 자격 허용 ∧ 비소유 접근이 [4] 를 세우는 구현(오늘의 RTL 형 —
      // permViol = ¬(devOwned ∧ entitle))이 여기서 반례를 낸다.
      if (io_faultPerm && !$past(io_faultPerm))
        o_perm_rise: assert ($past(f_ent_deny));
      // Platform.own_reported — 자격 허용 ∧ 비소유 적중은 다음 에지에 faultOwn([19]
      // 원천)을 세운다 — 해제와 겹쳐도 (조용한 거부가 아니다).
      if ($past(f_unowned))
        o_own_loud: assert (faultOwn);
      // Platform.entitle_first — [19] 의 상승 원천은 자격 허용 ∧ 비소유뿐이다: 자격
      // 거부(거부 채움 포함)는 비소유여도 [19] 를 세우지 않는다. o_perm_rise 와 함께
      // 「한 접근에 둘이 함께 서지 않는다」의 정확 등식이다 (두 전건이 서로소).
      if (faultOwn && !$past(faultOwn))
        o_own_rise: assert ($past(f_unowned));
      // Platform.own_reported — sticky: 해제 없이 내려가지 않는다.
      if ($past(faultOwn) && !$past(faultOwnClear))
        o_own_hold: assert (faultOwn);
      // Platform.own_reported — 해제가 실제로 내린다 (새 원천이 없는 사이클).
      if ($past(faultOwn && faultOwnClear && !f_unowned))
        o_own_clear: assert (!faultOwn);
    end
  end

  // ── 승인 게이트의 두 항 + 소유권 축 + 조회 leg 우선순위 (조합) ─────────
  always @(*) begin
    if (f_past_valid && !reset) begin
      // Isolation.approve_gates_value — **값축**. 값이 실린 사이클은 승인
      // 사이클뿐이다. 미승인 요청의 값 축 관측은 0 (Isolation.tla:585-588).
      if (io_rsp_frame != 32'h0 || io_rsp_perm_r || io_rsp_perm_w || io_rsp_perm_x)
        assert (io_rsp_granted);

      // Isolation.no_early_forward — **시간축**. 그 값이 실리는 사이클은
      // 거울의 6번째 지점뿐이다. 거울 f_v 는 조회·판정을 일절 보지 않고
      // io_req_valid 만 advance 로 시프트하므로, 승인 판정을 s5 로 당기고
      // 값도 함께 당기는 구현(모델의 fwd = 실행·승인 사이 일시 누출)이면
      // f_v[6]=0 인 사이클에 값이 실려 반례가 난다. approve_gates_value 는
      // 그것을 잡지 못한다 — 값축은 「granted 라는 이름의 게이트」만 보고
      // 그 게이트가 *어느 단에 앉아 있는지*를 보지 않기 때문이다
      // (Isolation.tla:554-558 의 분업 문면 그대로).
      if (io_rsp_frame != 32'h0 || io_rsp_perm_r || io_rsp_perm_w || io_rsp_perm_x)
        assert (f_v[6]);

      // Platform.owner_check ① — granted 는 devOwned 를 논리곱의 항으로
      // 요구한다. A 입력이 모듈 자유 입력 그 자체라 상수가 될 수 없다.
      if (io_rsp_granted)
        assert (io_owner_devOwned);

      // Platform.owner_check ② — 비소유의 **값 차단**. 전건을 devOwned 로
      // 두는 것이 요점이다: !granted 로 두면 approve_gates_value 의
      // 재인용이 되어 자격(entitle)만 다른 경우와 갈리지 않는다.
      if (!io_owner_devOwned)
        assert (io_rsp_frame == 32'h0
                && !io_rsp_perm_r && !io_rsp_perm_w && !io_rsp_perm_x);

      // ── W1 · Platform.entitle_gates_value — 자격 쪽 짝 ─────────────────────
      // 정본: 자격 거부와 비소유는 「값 차단 · 승인 거부 · 상태열」이 같고 보고
      // 비트만 갈린다. 위 owner_check ①② 는 devOwned 쪽만 들었다 — granted 에서
      // entitle 항을 지운 구현(자격 거부 접근이 승인되어 값을 돌려받는다)은 ①② ·
      // approve_gates_value 를 전부 통과한다 (선-formal 결함 1 의 RTL 판).
      // granted 는 entitle 을 논리곱의 항으로 요구한다.
      if (io_rsp_granted)
        o_grant_entitle: assert (f_entitle);
      // 자격 거부는 승인 거부 + 값 차단 — 전건을 entitle 로 두는 것이 요점이다
      // (owner_check ② 와 같은 이유). o_grant_entitle 과 approve_gates_value 에서
      // 유도되는 backstop 이다 (lint_postformal _DERIVED 등재).
      if (!f_entitle)
        o_ent_blocked: assert (!io_rsp_granted && io_rsp_frame == 32'h0
                               && !io_rsp_perm_r && !io_rsp_perm_w && !io_rsp_perm_x);

      // Isolation.query_no_serve + Platform.xlate_local — *적중 면*.
      // 로컬 저장 leg 이 답하는 사이클에 s4 로 들어가는 값(= io.mask.req
      // .frame 과 같은 그물)은 저장 leg 값 그 자체다. 두 leg 이 다른 값을
      // 들고 있는 궤적의 도달성은 증인 W9 가 든다.
      //
      //   ※ 2026-08-31 주석 수리. 종전 문면은 이 단언이 무는 변이를
      //     「elsewhen 순서를 뒤집으면」이라 적었는데, 그 문법은 이 파도가
      //     지웠다 — HiuPipeline.scala 의 접기에는 `when(xlate.io.rsp.hit)`
      //     한 가지뿐이라 「순서 뒤집기」가 표현 불가다. 오늘 이 단언이 무는
      //     변이는 **접기에 호스트 가지를 다시 넣는 것**이고, 그 변이가
      //     적중 사이클의 값을 바꾸는 형태(호스트 우선)일 때만 여기서 잡힌다.
      //     호스트 가지를 *미적중* 쪽에만 넣는 형태 — 즉 실제로 있었던 결함 —
      //     은 이 전건 밖이라 아래 미적중 면이 잡는다.
      //   ※ 「우선순위 축」이라는 부제도 뗐다. `.sby` 앵커와 _PARTIAL 은
      //     이 파도부터 「판정·값·정지 세 축」으로 적으며, 순위는 leg 이
      //     둘일 때만 뜻을 갖는 낱말이다 (오늘 leg 은 하나다).
      //   ※ W2 (2026-10-12) — 전건을 판정 적중 f_jhit = x_hit ∨ f_lat 로, 값을 판정
      //     값 f_jfr · f_jperm(래치면 첫 적중 사이클의 저장 leg 값)으로 넓혔다. 판정이
      //     래치된 사이클에도 호스트 leg 은 값 축에 들어가지 못한다 — 래치를 호스트
      //     leg 에서 포착하는 구현이 여기서 반례를 낸다.
      if (f_jhit) begin
        q_hit_frame: assert (lookFrame == f_jfr);
        q_hit_perm:  assert ({lookPerm_x, lookPerm_w, lookPerm_r} == f_jperm);
      end

      // ── Isolation.query_no_serve — *미적중 면* (2026-08-31 신설) ────────
      //
      // 위 두 줄의 전건은 `x_hit` 다. 그런데 구멍은 「로컬이 답할 때」가
      // 아니라 **「로컬이 미적중일 때」**에 있었다 — 전건이 정확히 구멍의
      // 여집합이라 도메인이 어긋나 있었다. 이 아래가 그 여집합을 잰다.
      //
      // 종전 판은 이 축을 「항진이라 못 잰다」로 포기했다 (hiumask.sby
      // §미측정 잔여 ⑤: `hit -> lookAny` 는 lookAny = hit || hostPresent
      // 에서 흡수 법칙으로 접힌다 — 공허 3형). 진단은 옳았고 결론이
      // 틀렸다: **함의를 등식으로 바꾸면 접히지 않는다.** 아래 값 축
      // 단언은 `x_hit ->` 함의가 아니라 미적중 면의 *값 지정*이다.
      //
      // 근거: §3.3.1 규범 2 「지원하는 호스트에서 기능이 *늘어도* 안 된다.
      // 서비스 없는 구성이 미적중하는 접근을 서비스 있는 구성이 적중시키면,
      // 그 순간 PE 가 보는 세계가 호스트에 따라 달라진다」 · HIU-11 의
      // 값 축 「같은 값을 관측한다」.
      //
      // 반증력 실측 — 아래 §반증력 실측표의 ②③ 항.
      //
      // W2 (2026-10-12) — 전건을 「판정 전 로컬 미적중」 ¬(x_hit ∨ f_lat) 로 좁혔다
      // (래치된 요청은 x_hit 이 내려가도 미적중이 아니다 — 위 적중 면이 잰다). 두 면의
      // 전건은 여전히 서로 여집합이라 조회 사이클 전체가 덮인다.
      if (!f_jhit) begin
        q_miss_frame: assert (lookFrame == 32'h0);
        q_miss_perm:  assert (!lookPerm_r && !lookPerm_w && !lookPerm_x);
      end

      // ── Decode.stall_uniform — *정지 원천* 축 (2026-08-31 신설) ─────────
      //
      // 위 $stable 두 줄은 「정지가 걸리면 전 단이 함께 선다」만 재고
      // **「무엇이 세우고 무엇이 푸는가」**는 재지 않는다. advance 가
      // hostRsp 의 함수여도 거울과 DUT 가 같은 advance 로 시프트하므로
      // 상태열 등식은 그대로 성립한다 — 거울 축의 구조적 사각지대다.
      //
      // E.3 2항 파생 요건이 정지 해제의 주체를 배타적으로 못박는다:
      // 「해제는 정지를 풀지 않는다 — 정지를 푸는 것은 2항의 *항목 기입*
      // 뿐이다」. hostRsp 는 install 이 아니므로 이 식의 항이 될 수 없다.
      // 그것이 항이면 서비스 없는 구성이 영구 정지하는 접근을 서비스 있는
      // 구성이 통과시켜 HIU-11 의 *상태열* 축이 깨진다.
      //
      // 정지 원천은 정확히 둘이다: 외부 io_hold, 그리고 조회 지점의 로컬
      // 미적중(E.4 3항이 명시 허용한 그 한 지점). 셋째 원천도, 셋째
      // 해제 주체도 없다.
      //
      // 반증력 실측 — 아래 §반증력 실측표의 ④ 항.
      //
      // W2 (2026-10-12) — 로컬 미적중 원천은 *판정 전*의 미적중이다: ¬(x_hit ∨ f_lat).
      // 판정이 래치된 요청은 그 항목이 축출 · 철회 · flush 로 x_hit 을 잃어도 다시
      // 서지 않는다(03-hiu.typ:742 「전에 다른 커밋이 그 항목을 밀어내도 다시 미적중하지 않는다」
      // — 선-formal Prop_NoReMiss). 래치가 없는 구현(W2 전 RTL — 매 사이클 다시
      // 판정)은 「정지 → 커밋으로 풀림 → hold 로 머묾 → 같은 파티션 다른 VPN 커밋이
      // 축출 → 재정지」에서 반례를 낸다. 그리고 판정을 남에게서 물려받은 요청 ·
      // 유효 게이트된 적중 없이 판정된 요청이 서지 않는 구현도 여기서 운다 (아래
      // l_clear · l_capture_gated 는 이 식의 그 두 갈래를 이름으로 든 사영이다).
      d_stall_src: assert (advance == (!io_hold && !(s3_valid && !f_jhit)));
    end
  end

  // ── 파도 4 (2026-09-26) — 미적중 관측 값 · 미적중 sticky 규약 · 슬롯 여유 통과 ──────
  //
  // 요청 데이터 거울 — io_req_part · io_req_vpn 을 거울 f_v 와 같은 enable(advance)로
  // 시프트한다. 관측 값의 지상 진리를 DUT 의 s3_* 가 아니라 이 거울에서 적는다 — 검사
  // 어휘로 지상 진리를 적으면 그 신호가 틀린 구현에서 등식이 함께 선다 (위 f_ent_deny · f_unowned ·
  // lookAny 해설과 같은 규율). reset 이 없는 레지스터인 것은 DUT 의 단 몸과 같다.
  reg [1:0]  f_p1, f_p2, f_p3;
  reg [31:0] f_n1, f_n2, f_n3;
  always @(posedge clk) begin
    if (advance) begin
      f_p1 <= io_req_part;  f_n1 <= io_req_vpn;
      f_p2 <= f_p1;         f_n2 <= f_n1;
      f_p3 <= f_p2;         f_n3 <= f_n2;
    end
  end
  // 조회 지점의 로컬 미적중 — 거울 valid 와 XlateStore 독립 출력 x_hit 로 적는다 (DUT
  // missWait 를 재인용하지 않는다). W2 (2026-10-12) — *판정 전*의 미적중이다: 판정이
  // 래치된 요청(지상 진리 f_lat)은 x_hit 이 내려가도 정지가 아니다. 이 정의가
  // m_obs_stall · m_obs_part · m_obs_vpn · m_obs_zero · m_sticky 로 전파된다 —
  // 특히 미적중 sticky 의 set 원천이 원시 미적중(s3 ∧ ¬x_hit)인 구현은 m_sticky 가
  // 래치된 요청의 항목이 밀려난 사이클(증인 W29)에 잡는다.
  wire f_stall = f_v[3] && !f_jhit;

  always @(*) begin
    if (f_past_valid && !reset) begin
      // 거울 ↔ 단 몸 — valid 인 단의 파티션 · VPN 은 그 요청의 것이다. 관측 단언들의
      // k-귀납 보조 불변식이기도 하다 (이것 없이는 임의 시작점에서 거울과 단 몸이 어긋난
      // 채 정지가 마지막 스텝에 서는 반례가 귀납을 깬다).
      m_cap_1: assert (!f_v[1] || (s1_part == f_p1 && s1_vpn == f_n1));
      m_cap_2: assert (!f_v[2] || (s2_part == f_p2 && s2_vpn == f_n2));
      m_cap_3: assert (!f_v[3] || (s3_part == f_p3 && s3_vpn == f_n3));
      // XlateObs.obs_stall_live (파이프라인 절반) — missStall 은 *지금* 조회 지점이 로컬
      // 미적중으로 서 있는가의 레벨이다 (sticky 가 아니다).
      m_obs_stall: assert (missStall == f_stall);
      // XlateObs.obs_part_stalled · obs_vpn_stalled (파이프라인 절반) — 정지 중의 값은
      // *지금* 정지한 요청의 것이다 (첫 미적중 포착이 아니다 — 해제 없이 온 둘째 정지는
      // 둘째 요청을 낸다).
      m_obs_part: assert (!f_stall || missPart == f_p3);
      m_obs_vpn:  assert (!f_stall || missVpn == f_n3);
      // XlateObs.obs_no_residue (파이프라인 절반) — 정지가 없으면 0: 조회 지점에 산 적중
      // 요청의 값도, 끝난 정지의 값도 새지 않는다.
      m_obs_zero: assert (f_stall || (missPart == 2'd0 && missVpn == 32'd0));
      // 슬롯 여유 통과 결선 (SLOTFREE) — installSlotFree 는 install.ready 의 상계이고(ready
      // 이면 슬롯 여유) 둘이 갈리는 사이클은 같은 파티션 flush 뿐이다. 앵커 없음 — 결선
      // 계약이다 (XlateStore 쪽 a_ready_split · 조립 쪽 a_xonehot 과 한 벌).
      m_slot_pass:  assert (!io_install_ready || installSlotFree);
      m_slot_split: assert (!(installSlotFree && !io_install_ready) ||
                            (io_flush_valid && (io_flush_part == io_install_part)));
    end
  end

  always @(posedge clk) begin
    if (f_ok) begin
      // 미적중 sticky 규약 — XlateObs.obs_sticky · XlateSurface.mclr_fires ·
      // XlateSurface.mclr_needs_one 의 파이프라인 절반. 차기 상태가 정확히 (정지 ∨
      // (sticky ∧ ¬해제)): 정지(set)가 해제를 이기고 · 정지가 없으면 해제가 내리고 ·
      // 해제 없이는 내려가지 않고 · 제3 원천(읽기 등)이 없다. 지상 진리의 정지는 거울
      // valid + x_hit 다. (StickyFault 규약 — Common.scala 의 「발화가 이긴다」.)
      m_sticky: assert (io_missNotice == $past(f_stall || (io_missNotice && !io_missClear)));
    end
  end

  // ── W2 (2026-10-12) — 판정 래치의 비움 · 포착 게이트 · 한 값 ──────────────────
  always @(posedge clk) begin
    if (f_ok) begin
      // XlateObs.latch_clears_on_leave — l_clear. 떠나는 에지(advance) 직후 사이클에
      // 조회 지점에 선 것(연속 전진이면 같은 에지에 s2 에서 들어온 다음 요청 · 아니면
      // 거품)의 판정은 *그 자신의* 조회값뿐이다: 적중이면 값이 그 조회값이고, 아니면
      // 값 0 · 유효 요청이면 정지한다. 비움이 한 에지 늦거나(대안 clear_late) 같은 에지의
      // 포착이 비움을 이기면(대안 capture_beats_clear) 다음 요청이 앞 요청의 판정을
      // 물려받아 미적중인데도 서지 않거나 남의 값을 싣는다 — 다른 파티션의 판정일 수도
      // 있다(HIU-1 꼴). 증인 W31 · W32 가 연속 전진 에지를 덮는다. 유도 단언이다 — 그 구현들은 격리에서 여기서 울고, 전 단언 bmc 에서는 형제 q_miss_perm 이 먼저 운다(hiumask.sby §W2).
      if ($past(advance))
        l_clear: assert (x_hit ? (lookFrame == x_frame
                                  && {lookPerm_x, lookPerm_w, lookPerm_r} == {x_perm_x, x_perm_w, x_perm_r})
                               : (lookFrame == 32'h0 && !lookPerm_r && !lookPerm_w && !lookPerm_x
                                  && (!s3_valid || !advance)));
      // XlateObs.verdict_latch 의 포착 조건 — l_capture_gated (HIU-3 짝). 조회 지점에
      // 한 에지 이상 머문 요청이 아직 유효 게이트된 적중(x_hit)을 한 번도 보지 못했으면
      // (지상 진리 판정 없음) 장치도 그것을 판정된 것으로 다루지 않는다 — 정지하고 값은
      // 0 이다. 래치가 저장 값의 새 보유 경로이므로 「포착은 유효 게이트된 적중에서만」을
      // 관측으로 잰다: 적중 항 없이 포착하는 구현 · 호스트 leg 에서 포착하는 구현이
      // 격리에서 여기서 운다(유도 단언 — 전 단언 bmc 에서는 형제 d_stall_src 가 먼저 운다). (첫 사이클은 위 l_clear 가 든다 — 두 단언의 전건은 서로소다.)
      if (!$past(advance) && f_v[3] && !f_jhit)
        l_capture_gated: assert (!advance && lookFrame == 32'h0
                                 && !lookPerm_r && !lookPerm_w && !lookPerm_x);
    end
  end

  always @(*) begin
    if (f_past_valid && !reset) begin
      // XlateObs.latch_one_value — l_one_value. 승인 단(s6)의 소유권 조회 주소는 *같은
      // 요청이* s3→s4 에서 마스킹 입력으로 실은 프레임이다 (03-hiu.typ:737 「같은 값으로 쓰인다」).
      // 거울 f_mf4..6 은 io_mask_req_frame 을 advance 로 시프트한 것이라 소유권 조회가
      // 저장 블록이나 조회 응답을 다시 읽는 구현 · 마스킹이 래치 아닌 조회값을 먹는
      // 구현이 래치된 요청의 항목이 바뀐 궤적(증인 W30)에서 반례를 낸다. 유효 요청은
      // 판정 없이 s4 로 가지 못하므로(정지 원천 등식) s6 의 유효 요청은 적중이다.
      if (f_v[6])
        l_one_value: assert (io_owner_frame == f_mf6);
    end
  end

  // ── §반증력 실측표 — 「이 단언들이 오늘의 결함을 실제로 무는가」 ─────────
  //
  // 규율: 반증력은 **주장이 아니라 실행 결과**다. 수리한 단언을 **수리 전
  // RTL** 에 걸어 반례가 나는지를 재지 않으면, 그 단언이 여전히 헛것인지
  // 사람이 알 수 없다 (저장소가 반복해 밟은 형태 — 무변이 GREEN 은 수락
  // 기준이 아니다).
  //
  // 방법 (2026-08-31 실측). 격리 사본 /tmp/wt-mut 에
  //   · rtl/generated/HiuPipeline.sv ← **수리 전** 생성 SV (git HEAD 판:
  //     lookAny = hit || hostPresent · missWait = … && !hostPresent)
  //   · rtl/sv/assert/HiuMask_props.sv ← **이 파일(수리 후)**
  //   · MaskUnit.sv · hiumask.sby ← 저장소 사본 그대로
  // 를 두고 `sby -f … bmc` (mode bmc · depth 24 · smtbmc z3) 를 돌렸다.
  // bmc 는 첫 반례에서 멈추므로 **네 단언을 하나씩만 살리고** 나머지 셋은
  // `assert (1'b1);` 로 중화해 네 번 따로 돌렸다 — 그러지 않으면 「하나가
  // 물었다」가 「넷이 문다」로 오독된다.
  //
  //   ① 캡처 등식 판정 비트 `s4_anyHit == $past(x_hit)`
  //        → FAIL, step 3   (수리 전 우변 $past(lookAny) 로는 통과했다)
  //   ② 미적중 면 값   `!x_hit -> lookFrame == 32'h0`
  //        → FAIL, step 1
  //   ③ 미적중 면 권한 `!x_hit -> perm 삼비트 0`
  //        → FAIL, step 1
  //   ④ 정지 원천 등식 `advance == !io_hold && !(s3_valid && !x_hit)`
  //        → FAIL, step 4
  //
  // 넷 다 물었다. 그리고 ②④ 가 수리 후 설계에서 **통과**한다는 사실이
  // 곧 「W10 의 결론 두 항은 전건에서 따라온다」의 증명이다 — W10 주석의
  // ⚠⚠ 문단이 그 함의를 자기 자신에 대한 공허 고지로 쓰는 근거다.
  //
  // 종전 이 자리에는 실측이 단언마다 한 줄씩 흩어져 있었고 그중 하나는
  // 「전부 살린 채 한 번 돌린」 결과를 단언 하나의 반증력으로 적었다.
  // 한 곳에 모으고 방법을 함께 적는다 — 재현 없는 수치는 증거가 아니다.

  // ── cover 증인 — 공허 아님의 증거 (2026-08-25 신설) ─────────────────────
  //
  // 위 여섯 일치 assert 는 *등식*이라 「아무것도 흐르지 않는 세계」에서
  // 0 == 0 으로 자명하게 선다. stall_uniform 의 $stable 단언도 마찬가지로
  // 「단이 언제나 비어 있다」면 공허하다. 아래 증인이 reset 으로부터
  // 실제로 요청이 흐르고, 실제로 멈추고, 실제로 승인·거절된다는 것을 보인다.
  //   ※ sby 의 cover 모드는 chformal -assert -remove 로 단언을 스스로
  //     떼어낸다. 증인이 적법 궤적 위에 있다는 것은 bmc 태스크가 보증한다.
`ifdef HIUMASK_COVER
  // W1 ← Isolation.coh_no_shortcut · Decode.lookup_unbranched
  //      6단 전 구간을 요청이 실제로 통과해 응답이 나온다 (거울 전 지점이
  //      1 을 실어 본다 — 등식 여섯이 0==0 이 아니다)
  always @(posedge clk) if (f_ok) w1_rsp: cover (io_rsp_valid);

  // W2 ← Isolation.coh_no_shortcut · Decode.lookup_unbranched
  //      파이프가 실제로 파이프다: 서로 다른 두 요청이 동시에 비행 중
  //      (거울 양 끝이 동시에 1)
  always @(posedge clk) if (f_ok) w2_two_inflight: cover (f_v[1] && f_v[6]);

  // W3 ← Decode.stall_uniform
  //      전제 ①: io_hold 발 정지를 *내용이 실린* 단이 건넌다
  always @(posedge clk)
    if (f_ok && !$past(advance) && $past(io_hold))
      w3_hold_loaded: cover (s3_valid || s5_valid || s6_valid);

  // W4 ← Decode.stall_uniform
  //      전제 ②: io_hold 가 아닌 정지 — E.3 미적중 채움
  //      대기(missWait) 발. 「정지 원천 무관」이 두 원천 모두에서 재어진다는
  //      증거 (하나뿐이면 그 문면이 절반만 실측된 것이다)
  always @(posedge clk)
    if (f_ok && !$past(advance) && !$past(io_hold))
      w4_misswait_stall: cover (s3_valid);

  // W5 ← Isolation.approve_gates_value · Isolation.no_early_forward · o_grant_entitle
  //      활성면: 승인이 실제로 나고 값축이 비0 이다
  //      (이것 없이는 「무엇도 승인되지 않는 기계」가 단언을 통과한다)
  always @(posedge clk) if (f_ok) w5_granted_nonzero: cover (io_rsp_granted && (io_rsp_frame != 32'h0));

  // W6 ← Isolation.approve_gates_value
  //      그 반대면: 유효 응답인데 승인이 없고, 그래서 값축이 0 이다
  //      (거절이 실제로 값을 지운다 — 두 면을 함께 둬야 계약이 잠긴다)
  always @(posedge clk)
    if (f_ok) w6_denied_zero: cover (io_rsp_valid && !io_rsp_granted && (io_rsp_frame == 32'h0)
                     && !io_rsp_perm_r && !io_rsp_perm_w && !io_rsp_perm_x);

  // ── 2차 파도 증인 (2026-08-26 신설) ────────────────────────────────────
  //
  // 대체 궤적 추적기 — 「축출 상태 없음」의 도달성 증거를 만드는 도구다.
  // 저장 leg 적중(fromFill=0)을 한 번 관측하면 그 순간 그 칸의 유효 비트가
  // 1 이었다는 뜻이다. XlateStore 의 유효 비트를 내리는 것은 flush 와 V=0
  // 커밋(파도 3)뿐이므로(생성 SV 의 validBits 전이 전수), 그 파티션에 flush 도
  // V=0 설치도 없는 한 그 칸은 계속 유효하다. 그래서 「같은 파티션·같은 idx 를 *다른 태그*로
  // 조회하는 사이클」 = 유효 ∧ 태그 불일치 = §3.6.2 규범 4 의 대체다.
  // 사이 커밋이 태그를 갈아치웠더라도 증인은 건전하다 — 그때는 적중이
  // 나므로 `!x_hit` 가 그 경우를 그 자리에서 배제한다.
  reg        f_ev_seen = 1'b0;
  reg [1:0]  f_ev_part;
  reg [3:0]  f_ev_idx;
  reg [27:0] f_ev_tag;
  always @(posedge clk) begin
    if (reset) f_ev_seen <= 1'b0;
    else if (s3_valid && x_hit && !x_fromFill
             && !(io_flush_valid && (io_flush_part == s3_part))
             && !(f_kill && (f_kill_part == s3_part))) begin
      f_ev_seen <= 1'b1;
      f_ev_part <= s3_part;
      f_ev_idx  <= s3_vpn[3:0];      // XlateStore reqIdx = vpn(3 downto 0)
      f_ev_tag  <= s3_vpn[31:4];     // XlateStore reqTag = vpn(31 downto 4)
    end else if ((io_flush_valid && (io_flush_part == f_ev_part)) ||
                 (f_kill && (f_kill_part == f_ev_part))) begin
      f_ev_seen <= 1'b0;
    end
  end
  wire f_replace = f_ev_seen && s3_valid && (s3_part == f_ev_part)
                   && (s3_vpn[3:0] == f_ev_idx) && (s3_vpn[31:4] != f_ev_tag);

  // 대체 미적중이 조회 단에 *섰다*는 사실을 붙드는 대기 비트.
  //
  // 2026-08-31 신설. 종전 판은 f_rep 의 입력에 `f_replace && !x_hit` 를
  // 직접 물렸는데, 그 식은 **정지가 풀리는 사이클에 이미 거짓**이다 —
  // E.3 이 정한 해제 주체가 항목 기입이므로 대체 미적중은 install 로
  // x_hit 가 서야 전진하고, 전진 에지에서는 `!x_hit` 가 거짓이다. 즉
  // 꼬리표가 영영 0 이라 W12 가 도달 불가가 된다.
  //   ※ 수리 전 RTL 에서 이 꼬리표가 실렸던 이유는 **결함 그 자체**였다:
  //     hostPresent 가 미적중 정지를 풀어 미적중 요청이 여섯 단을 완주했다.
  //     W12 도 W10 과 같이 위반에 매인 증인이었다 — W10 은 *전건*이
  //     위반이었고, 이쪽은 *도달 경로*가 위반이었다. 결함을 고치자
  //     증인이 함께 죽는 것이 그 매임의 증거다.
  //   ⇒ 올바른 궤적은 E.3 그대로다: 대체 미적중이 조회에 서서 정지 →
  //     호스트가 항목을 기입 → 채움 바이패스 적중 → 전진. 아래 대기
  //     비트가 「조회에 선 그 요청이 대체였다」를 정지 구간 너머로 나른다.
  reg f_rep_pend = 1'b0;
  always @(posedge clk) begin
    if (reset)                    f_rep_pend <= 1'b0;
    else if (f_replace && !x_hit && !f_lat)            // 대체 미적중이 조회에 섰다 (W2 — 판정이
                                  f_rep_pend <= 1'b1;  // 래치된 요청의 축출은 대체 미적중이 아니다)
    else if (advance)             f_rep_pend <= 1'b0;  // 그 요청이 s4 로 떠났다
  end

  // 그 대체 요청을 단으로 실어 나르는 꼬리표 (거울과 같은 enable)
  reg [6:4] f_rep = 3'h0;
  always @(posedge clk) begin
    if (reset)        f_rep <= 3'h0;
    else if (advance) f_rep <= {f_rep[5:4], f_rep_pend};
  end

  // W9 ← Isolation.query_no_serve · Platform.xlate_local
  //      활성면: 두 leg 이 실제로 *충돌*
  //      한다 (같은 사이클에 로컬 적중 + 호스트 응답이 다른 frame).
  //      이것 없이는 우선순위 단언이 「호스트 leg 이 죽어 있는 세계」에서
  //      자명하다.
  always @(posedge clk)
    if (f_ok) w9_leg_clash: cover (x_hit && io_hostRsp_valid && (io_hostRsp_frame != x_frame));

  // W10 ← Isolation.query_no_serve(미적중 면) · Decode.stall_uniform(정지 원천)
  //
  //       **이 증인이 재는 것은 전건 도달성 하나다.** 위 두 신설 단언
  //       (미적중 면 값 지정 · 정지 원천 등식)의 전건이 살아 있는 궤적 —
  //       로컬 미적중이면서 호스트 leg 이 실제로 서 있고(x_hostPresent ·
  //       비0 frame) 자유 입력이 흔들리는 사이클 — 이 도달 가능하다.
  //
  //       ⚠ 2026-08-31 교체. 종전 판은
  //         cover (s3_valid && !x_hit && x_hostPresent
  //                && lookFrame == io_hostRsp_frame && io_hostRsp_frame != 0)
  //       였고 「최하 순위 가지가 살아 있어야 「최하 순위」가 명제다」로
  //       스스로를 정당화했다. 그러나 그 전건은 **정확히 §3.3.1 규범 2
  //       「지원하는 호스트에서 기능이 *늘어도* 안 된다」 위반 궤적**이다 —
  //       로컬이 미적중한 사이클에 호스트 프레임이 값 축에 실리는 것.
  //       증거층은 그것을 `reached` 로 세어 verdict PASS 에 실었다. 공허
  //       검출을 위해 지은 증인 층이 위반의 *도달성*을 증명해 게이트에
  //       초록으로 올린 셈이다.
  //
  //       ⚠⚠ **이 증인은 「호스트 leg 이 죽은 세계」에서 자명하다.** 결론
  //       두 항(`lookFrame == 0` · `!advance`)은 오늘 설계에서 전건으로부터
  //       *구조적으로* 따라온다 — 접기의 기본 구동이 0 이고 미적중 가지가
  //       없으므로 판정 전(래치 빔) `!x_hit → lookFrame == 0` 이고, W2 부터
  //       `missWait = s3_valid && !lookAny` · `lookAny = 래치 ∨ x_hit` 이므로
  //       `s3_valid && !x_hit && !f_lat → !advance` 다. 즉 남는 자유도는
  //       `x_hostPresent && io_hostRsp_frame != 0` 뿐이고 그 둘은 팬아웃이
  //       없는 자유 입력이다 (HiuPipeline.sv 에서 io_hostRsp_* 는 XlateStore
  //       를 통과해 미결선 넷 다섯으로 끝난다). **그러므로 이 cover 가
  //       도달했다는 사실은 호스트 leg 이 무언가를 한다는 증거가 아니다.**
  //         · 2026-08-31 첫 판의 주석은 이 자리에 「호스트 leg 이 죽은
  //           세계에서 자명해지지 않는다」라 적었다. 그것이 거짓이었다 —
  //           §3.4.2 「아무것도 하지 않는 선택적 경로는 HIU-11 을 자명하게
  //           만족한다」가 경계하는 그 형태를 **피하지 못한다.**
  //         · 피할 수 없는 것이 오늘의 상태다. 정본 §3.3.1 측정 트랙이
  //           이 leg 을 「의도된 미결선」이라 부르고 승격 조건을 적어 두었고,
  //           승격 전까지 §3.4.2 「요구할 것은 셋이다」 — 두 구성의 내부
  //           상태가 *실제로 어긋난다* · 그 상태가 *관측 경로 위에 있다* ·
  //           중립성이 *가드가 만든 참이다* — 는 셋 다 성립하지 않는다.
  //           그 사실은 `.sby` §미측정 잔여 ③ 와 lint_postformal 의
  //           `_PARTIAL` 이 기계가 읽는 칸에 적는다.
  //         ⇒ 이 증인의 정직한 이름은 「전건이 도달한다」이지 「leg 이
  //           불활성임을 증명한다」가 아니다. 불활성을 *증명*하는 것은 위
  //           두 단언(값 0 · 정지 유지)이고, 이 cover 는 그 단언들이
  //           공허하지 않다는 것만 든다.
  always @(posedge clk)
    if (f_ok) w10_host_leg_inert: cover (s3_valid && !x_hit && !f_lat && x_hostPresent
                     && (io_hostRsp_frame != 32'h0)
                     && (lookFrame == 32'h0) && !advance);

  // W11 ← Decode.evict_inline
  //       본체: 대체 궤적이 실제로 도달 가능하다
  //       (유효한 칸을 다른 태그로 조회 → 미적중으로만 나타난다). W2 — 판정이 래치된
  //       요청의 항목이 밀려난 사이클은 대체 미적중이 아니므로 !f_lat 로 뺀다.
  always @(posedge clk) if (f_ok) w11_replace_reached: cover (f_replace && !x_hit && !f_lat);

  // W12 ← Decode.evict_inline · Isolation.coh_no_shortcut
  //       그 대체 요청이 여섯 단을 완주해 응답이 난다. 거울 등식은 전
  //       궤적에 대해 서 있으므로, 대체 궤적이 도달 가능하다는 이 증인이
  //       「대체가 단계열을 바꾸지 않는다」의 실측이다.
  //       2026-08-31 이후 도달 경로는 E.3 규범 그대로다 — 대체 미적중이
  //       조회에 서서 정지하고, 호스트가 항목을 기입해야 풀린다. 즉 이
  //       증인은 「축출 단 부재」와 「정지 해제 주체가 항목 기입」을
  //       한 궤적으로 함께 든다 (위 f_rep_pend 주석).
  always @(posedge clk) if (f_ok) w12_replace_completes: cover (f_rep[6] && io_rsp_valid);

  // W13 ← Platform.owner_check · Platform.own_reported · Platform.entitle_first ·
  //       Isolation.approve_gates_value · o_own_loud · o_own_rise
  //       자격이 허용된 비소유 적중이 실제로 일어나고, 값이 차단된 채로
  //       크게 알려진다 (fault 축의 활성면 — 승격 항목 1). W1 부터 그 비트는 [19]
  //       원천 faultOwn 이고 [4] 는 서지 않는다 — 옛 라벨 w13_nonowner_loud 는 [4] 를
  //       요구했으므로 원인별 판에서 이름과 식을 함께 바꿨다.
  always @(posedge clk)
    if (f_ok) w13_unowned_loud: cover ($past(f_unowned && io_rsp_valid && !io_rsp_granted && (io_rsp_frame == 32'h0)
                                            && !faultOwn && !io_faultPerm)
                                      && faultOwn && !io_faultPerm);

  // W14 ← Platform.owner_check
  //       sticky 가 *처음* 서는 순간. 이미 서 있는 상태를 지나가는 것과
  //       구분되지 않으면 loud 단언이 「늘 1 인 비트」로 자명해진다.
  always @(posedge clk) if (f_ok) w14_fault_rise: cover (!$past(io_faultPerm) && io_faultPerm);

  // W15 ← Platform.owner_check
  //       해제가 실제로 가능하다 (영구 1 이 아니다 — 위 자명화의 반대면)
  always @(posedge clk) if (f_ok) w15_fault_clear: cover ($past(io_faultPerm) && !io_faultPerm);

  // ── 파도 4 증인 (2026-09-26) — 미적중 관측 값 · sticky 규약 · 슬롯 여유 ──────────
  // W19 ← XlateObs.obs_stall_live · XlateObs.obs_part_stalled · XlateObs.obs_vpn_stalled ·
  //       m_obs_stall · m_obs_part · m_obs_vpn — 정지가 실제로 서고 그 값이 0 이 아니다
  //       (파티션 값 0 · VPN 0 이면 「상수 0」 구현이 등식을 통과한다)
  always @(posedge clk) if (f_ok) w19_obs_stall: cover (missStall && missPart != 2'd0 && missVpn != 32'd0);

  // W20 ← XlateObs.obs_no_residue · m_obs_zero — 정지가 없는데 값이 샐 원천이 실재한다:
  //       조회 지점에 비0 요청이 적중으로 산 사이클 (비게이트 갈래가 새는 자리)과, 비0 값을
  //       내던 정지가 막 풀린 사이클 (포착 갈래의 잔재가 남는 자리) — 둘 다 값은 0 이다
  always @(posedge clk) if (f_ok) w20_live_zero:  cover (f_v[3] && x_hit && f_p3 != 2'd0 && f_n3 != 32'd0 && missPart == 2'd0 && missVpn == 32'd0);
  always @(posedge clk) if (f_ok) w20_after_zero: cover ($past(missStall && missVpn != 32'd0) && !missStall && missVpn == 32'd0);

  // W21 ← XlateObs.obs_sticky · XlateSurface.mclr_needs_one · m_sticky — 정지가 풀린 뒤
  //       해제 없는 에지를 건너 sticky 가 1 로 남는다 ([0] 은 0 — 두 비트가 갈린다)
  always @(posedge clk) if (f_ok) w21_sticky_holds: cover ($past(io_missNotice && !io_missClear && !f_stall) && io_missNotice && !missStall);

  // W22 ← XlateSurface.mclr_fires · m_sticky — 정지가 없을 때 해제가 sticky 를 실제로 내린다
  always @(posedge clk) if (f_ok) w22_clear_lowers: cover ($past(io_missNotice && io_missClear && !f_stall) && !io_missNotice);

  // W23 ← XlateSurface.mclr_keeps_stall · m_sticky — 정지 *중*의 해제: 다음 에지에도
  //       정지가 그대로이고(advance 0) sticky 도 선 채다 (set 이 이긴다 — 해제 유실)
  always @(posedge clk) if (f_ok) w23_clear_in_stall: cover ($past(f_stall && io_missClear) && f_stall && io_missNotice && !advance);

  // W24 ← m_slot_pass · m_slot_split — 슬롯은 비었는데 같은 파티션 flush 가 설치를 막는
  //       사이클 (두 신호가 실제로 갈린다)
  always @(posedge clk) if (f_ok) w24_slot_split: cover (installSlotFree && !io_install_ready);

  // ── W1 증인 (2026-10-11) — FAULT_STATUS [4] / [19] 원인별 · 자격의 값 차단 ──────────
  // W25 ← Platform.perm_entitle_only · Platform.entitle_first · o_perm_loud · o_perm_rise
  //       거부 채움(승인 단 R = W = 0)이 *비소유* 프레임에 닿는다 — [4] 만 0→1 로 서고
  //       [19] 는 서지 않는다 (정본 「프레임이 무엇이든 [4] 로만」. 선-formal 증인
  //       Witness_NoBothCauses 의 RTL 판).
  always @(posedge clk)
    if (f_ok) w25_ent_deny_loud: cover ($past(f_ent_deny && !io_owner_devOwned && !s6_perm_r && !s6_perm_w
                                             && io_rsp_valid && !io_faultPerm && !faultOwn)
                                       && io_faultPerm && !faultOwn);
  // W26 ← Platform.entitle_gates_value · o_grant_entitle · o_ent_blocked
  //       *장치 소유* 프레임에 대한 자격 거부 접근 — 저장 프레임이 비0 인데 승인이 없고
  //       값이 0 이며 [4] 가 선다 (선-formal 증인 Witness_NoDenyFillOwned 와 같은 자리 —
  //       owner_check ② 의 devOwned 전건으로는 이 사이클이 막히지 않는다).
  always @(posedge clk)
    if (f_ok) w26_ent_deny_owned: cover ($past(f_ent_deny && io_owner_devOwned && io_rsp_valid && !io_rsp_granted
                                              && (io_rsp_frame == 32'h0) && (s6_frame != 32'h0) && !io_faultPerm)
                                        && io_faultPerm && !faultOwn);
  // W27 ← Platform.own_reported · o_own_clear
  //       선 [19] 원천이 해제로 실제로 내려간다 (영구 1 이 아니다).
  always @(posedge clk)
    if (f_ok) w27_own_clear: cover ($past(faultOwn && faultOwnClear && !f_unowned) && !faultOwn);
  // W28 ← Platform.own_reported · o_own_hold
  //       새 원천도 해제도 없는 에지를 건너 [19] 가 선 채다 (레벨이 아니라 sticky —
  //       RegNext(ownViol) 형 구현은 여기서 0 으로 떨어진다).
  always @(posedge clk)
    if (f_ok) w28_own_hold: cover ($past(faultOwn && !faultOwnClear && !f_unowned) && faultOwn);

  // ── W2 증인 (2026-10-12) — 판정 래치 ─────────────────────────────────────────────
  // 판정이 래치된 요청이 그 항목이 바뀐 채(축출 · 철회 · 대체 — 지금 조회가 미적중이거나
  // 래치와 다른 값) 떠났다는 꼬리표를 단으로 실어 나른다 (거울과 같은 enable).
  reg [6:4] f_lmv = 3'h0;
  always @(posedge clk) begin
    if (reset)        f_lmv <= 3'h0;
    else if (advance) f_lmv <= {f_lmv[5:4], f_v[3] && f_lat && (!x_hit || (x_frame != f_lfr))};
  end
  // W29 ← XlateObs.verdict_latch · d_stall_src · m_sticky
  //       래치가 실제로 일을 하는 궤적 — 판정이 래치된 요청이 hold 로 조회 지점에 머무는 동안
  //       그 항목이 밀려나 로컬 조회가 미적중이다. 래치 없는 구현은 여기서 다시 서고, sticky 의
  //       set 원천이 원시 미적중인 구현은 여기서 sticky 를 세운다.
  always @(posedge clk) if (f_ok) w29_latched_evicted: cover (f_lat && !x_hit && s3_valid && io_hold);
  // W30 ← XlateObs.verdict_latch · XlateObs.latch_one_value · l_one_value · l_hold
  //       그 요청이 다시 서지 않고 여섯 단을 완주해 응답하고, 승인 단의 소유권 조회 주소가
  //       비0 이다 — 한 요청이 두 판정을 가질 수 있는 궤적에서 한 값이 실제로 실린다.
  always @(posedge clk) if (f_ok) w30_latched_completes: cover (f_lmv[6] && io_rsp_valid && (io_owner_frame != 32'h0));
  // W31 ← XlateObs.latch_clears_on_leave · l_clear
  //       연속 전진 에지 — 판정이 래치된 요청이 떠나는 *그* 에지에 s2 의 다음 요청이 조회
  //       지점에 들어오고, 그 요청은 미적중이다 (비움이 한 에지 늦은 구현은 여기서 앞
  //       요청의 판정을 물려받는다).
  always @(posedge clk) if (f_ok) w31_clear_after_latched: cover ($past(advance && f_lat && f_v[2]) && s3_valid && !x_hit);
  // W32 ← XlateObs.latch_clears_on_leave · l_clear
  //       연속 전진 에지 — 첫 적중 사이클에 바로 떠나는 요청(포착 조건과 비움이 같은 에지에
  //       겹친다) 뒤에 들어온 다음 요청이 미적중이다 (포착이 비움을 이기는 구현은 여기서
  //       앞 요청의 판정을 물려받는다).
  always @(posedge clk) if (f_ok) w32_clear_after_fresh: cover ($past(advance && f_v[3] && x_hit && !f_lat && f_v[2]) && s3_valid && !x_hit);
  // W33 ← XlateObs.verdict_latch · l_hold · q_hit_frame
  //       판정이 래치된 요청의 항목이 다른 값의 V=1 재커밋으로 대체된 채 떠나는 에지 — 래치
  //       값과 지금 조회값이 실제로 갈린다 (값 절반 — 선-formal 대안 value_no_latch 의 전건).
  always @(posedge clk) if (f_ok) w33_replaced_leaves: cover (f_lat && x_hit && (x_frame != f_lfr) && advance);
  // W34 ← l_hold
  //       채움 바이패스로 판정이 래치된 요청이 저장 블록 적중으로 떠나는 에지 — fromFill
  //       절반이 실제로 갈린다 (래치 1 · 지금 조회 0).
  always @(posedge clk) if (f_ok) w34_fill_latched_leaves: cover (f_lat && f_lfill && x_hit && !x_fromFill && advance);
  // W35 ← l_capture_gated · XlateObs.verdict_latch
  //       판정 없는 요청이 조회 지점에 한 에지 이상 머물고, 그 사이클에 호스트 leg 이 비0
  //       값을 들고 서 있다 — 포착 조건이 적중 항을 빠뜨리거나 호스트 leg 을 먹는 구현이
  //       래치할 바로 그 전건이다.
  always @(posedge clk) if (f_ok) w35_unjudged_dwell: cover (!$past(advance) && f_v[3] && !f_jhit && x_hostPresent && (io_hostRsp_frame != 32'h0));
  // W36 ← XlateObs.verdict_latch · d_stall_src · l_hold
  //       철회의 효력 범위 — 판정이 래치된 요청이 머무는 동안 그 파티션의 flush 에지를 건너고,
  //       조회가 미적중인 채 다시 서지 않고 떠난다 (flush 는 조회에만 효력이 있다 — 선-formal
  //       증인 Witness_NoRetractWhileLatched 의 RTL 판).
  always @(posedge clk) if (f_ok) w36_latched_across_flush: cover ($past(f_lat && !advance && io_flush_valid && (io_flush_part == s3_part)) && f_lat && !x_hit && advance);
`endif // HIUMASK_COVER
endmodule

// ── MaskUnit 쪽 검사자 (bind) ─────────────────────────────────────────────
module MaskUnit_props (
  input wire        clk,
  input wire        reset,
  input wire        io_en,
  input wire        io_req_valid,
  input wire        io_rsp_valid,
  input wire [31:0] io_rsp_frame,
  // ── 2026-09-15 파도 신설 tap — 임대별 마스크 키 (정본 7fa5f2e) ─────────
  // io_keyWr_* 는 MaskUnit 자신의 포트(이미 자유 입력), rekeyFire ·
  // io_maskReady · st_4(유도 초기 상태 워드 0) 는 MaskUnit 스코프의 평범한 내부 신호다 —
  // bind 텍스트 전개가 이 검사자를 MaskUnit 본문 안에 주입하므로, 아래
  // 포트에 연결되는 실인수는 DUT 자신의 이름으로 그대로 풀린다
  // (HiuPipeline_props 의 s1_valid 등 기존 tap 과 같은 방식).
  input wire        io_keyWr_valid,
  input wire [1:0]  io_keyWr_part,
  input wire [2:0]  io_keyWr_idx,
  input wire [31:0] io_keyWr_data,
  input wire        rekeyFire,     // io_rekey_valid && io_rekey_ready (내부 wire)
  input wire        io_rekey_valid,
  input wire [1:0]  io_rekey_part,
  input wire [3:0]  io_maskReady,  // {maskValid_3,maskValid_2,maskValid_1,maskValid_0}
  input wire [31:0] st_4,        // 유도 초기 상태 워드 0 (MaskUnit.scala st(4))
  input wire [2:0]  phase,         // PH_IDLE=0 (MaskUnit.scala 지역 상수)
  // 2026-09-16 신설 — DUT 실물 key 레지스터 (MaskUnit.scala `key =
  // Vec.fill(parts)(...)` 가 합성되며 붙는 이름 `key_p_0`, 파티션당
  // 워드 0). 아래 shk_p_0 섀도우와의 **동기화 자체를 무조건 불변식으로
  // 검사**하는 데 쓴다 — key_scoped_storage 귀납 반례(아래 해설) 수리.
  input wire [31:0] key_0_0,
  input wire [31:0] key_1_0,
  input wire [31:0] key_2_0,
  input wire [31:0] key_3_0,
  // 2026-09-16 — REKEY 완료 유효화 대상 (MaskUnit.scala actPart, PH_FINAL
  // 완주 시 MaskUnit.scala:481 「maskValid(actPart) := !dirtyNow」 가 그 파티션을
  // *유효화*한다 — 파도 D 2026-09-22 에 `!compDirty` 에서 재조준·결속).
  // key_write_own_only 가 이 원인의 변화를 keyWr 원인과 혼동하지 않도록
  // 배제하는 데 쓴다 — 아래 해설.
  input wire [1:0]  actPart
);
  // f_ok — HiuPipeline_props 와 같은 관용구 (위 주석 참조).
  reg f_past_valid = 1'b0;
  reg f_past_reset = 1'b1;
  always @(posedge clk) begin
    f_past_valid <= 1'b1;
    f_past_reset <= reset;
  end
  wire f_ok = f_past_valid && !reset && !f_past_reset;

  // ── 섀도우 키 — 지상 진리를 DUT 어휘가 아니라 keyWr 입력에서 다시 적는다
  // (이 파일의 원칙: "검사 어휘로 지상 진리를 적으면 그 신호를 지운
  // 구현에서 전건이 함께 사라진다" — lookAny 해설과 같은 자리).
  //
  // **파티션당 워드 0 하나만** 미러링한다(4 레지스터, 128b) — 8워드
  // 전부(32 레지스터, 1024b)를 배열로 처음 적었다가 SMT array 이론이
  // 걸려 bmc 5분+ 정체를 실측했고, 평평한 레지스터 32개로 바꾼 뒤에도
  // bmc 스텝 8 에서 여전히 분 단위로 막혀(누적 상태 1024b 가 여전히
  // 무겁다) 실측으로 폭을 좁혔다. 워드 0 만으로도 key_scoped_storage
  // 결함(mutG — 저장이 전역 1벌)과 rekey_explicit_target 형 결함
  // (창이 지목을 겸함)은 **모든 워드에 균일하게** 나타나므로 워드 0
  // 하나만 비교해도 반증력이 그대로다 — 8워드를 다 보는 것은 "같은
  // 결함을 여덟 번 다시 보는" 중복이었다. DUT 자신도 key 저장을 동적
  // 배열이 아니라 case-select 로 합성한다(생성 SV
  // `case(io_rekey_part) ... _zz_st_4 = key_0_0; ...`).
  reg [31:0] shk_0_0, shk_1_0, shk_2_0, shk_3_0;
  always @(posedge clk) begin
    if (reset) begin
      {shk_0_0, shk_1_0, shk_2_0, shk_3_0} <= 128'h0;
    end else if (io_keyWr_valid && (io_keyWr_idx == 3'd0)) begin
      case (io_keyWr_part)
        2'b00: shk_0_0 <= io_keyWr_data;
        2'b01: shk_1_0 <= io_keyWr_data;
        2'b10: shk_2_0 <= io_keyWr_data;
        default: shk_3_0 <= io_keyWr_data;
      endcase
    end
  end

  // rekey_reads_own_key 의 비교 대상(워드 0) — **같은 에지에서** 캡처한다.
  //
  // 첫 판은 `$past(rekeyFire)` 뒤에 (아직 이번 에지가 갱신한) 섀도우를
  // 직접 비교했는데, rekeyFire 와 **같은 사이클**에 같은 (파티션,워드)
  // 로 향한 키 기입이 겹치면 거짓 반례가 났다(실측, bmc step 2 —
  // props_only.sv:793): DUT 의 `st(4) := key(target)(0)` 도 이 섀도우의
  // 기입도 둘 다 논블로킹이라 *그 에지 이전* 값을 읽는데, 검사가 *에지
  // 이후* 섀도우를 읽어 비교 시점이 어긋났다. MaskUnit.scala 의 compDirty
  // 규율(MaskUnit.scala:501-502 「compDirty := True」 — 같은 사이클의 기입은
  // dirty 로 표시해 결과를
  // 무효화한다, *st 자체를 새 값으로 바꾸지는 않는다*)과 같은 자리 — 이
  // 검사자도 "그 에지 이전 값" 을 DUT 와 같은 논블로킹 타이밍으로
  // 캡처해야 레이스가 아니라 실제 결함만 잡는다.
  reg [31:0] shadow_target_now;
  always @(*) begin
    case (io_rekey_part)
      2'b00: shadow_target_now = shk_0_0;
      2'b01: shadow_target_now = shk_1_0;
      2'b10: shadow_target_now = shk_2_0;
      default: shadow_target_now = shk_3_0;
    endcase
  end
  reg [31:0] shadow_target_d1;
  always @(posedge clk) shadow_target_d1 <= shadow_target_now;

  // ── 귀납 보조 불변식 — 섀도우 ≡ DUT 실물 (2026-09-16 신설) ─────────────
  // 근거: k-귀납은 리셋을 지나온 이력이 아니라 "임의의(reset=0 고정)
  // 상태"에서 시작한다(engine_0.induction). shk_p_0 와 key_p_0 는 리셋에서
  // 똑같이 0 이고 이후 똑같은 조건(io_keyWr_valid && idx==0, case part)
  // 으로만 갱신되므로 리셋 이후 항상 같다 — 그러나 그 사실은 "쭉 그래
  // 왔다"는 이력 추론이고, 임의 시작점에서 귀납 엔진은 그것을 모른다.
  //
  // 처방: 동기화 자체를 **무조건 assert** 로 적어 귀납 가정에 태운다.
  // 이 assert 는 그 자신부터 귀납된다(같은 갱신 조건이므로 자명) —
  // 서면 st_4 == shadow_target_d1(key_scoped_storage) 도 그로부터
  // 도출된다: shadow_target_now = shk_{rekey_part}_0 = key_{rekey_part}_0
  // 이고 DUT 도 st(4) := key(rekey_part)(0) 이므로 같은 값이다.
  //
  // 실측(2026-09-16): 이 불변식 없이는 induction 이 UNKNOWN — 섀도우와
  // DUT 가 서로 다른 임의값으로 시작하는 조합에서 반례가 났다
  // (props_only.sv:863, st_4 != shadow_target_d1). RTL 결함이 아니라
  // 검사 하네스가 귀납 불변식을 하나 덜 가졌던 것이다.
  // f_ok 가드 필수 — reset 이 *인가된 바로 그 사이클*에는 두 sync-reset
  // 레지스터(key_p_0 · shk_p_0) 모두 아직 클럭 엣지를 지나지 않아 초기화
  // 전 임의값일 수 있다(실측: 가드 없이 걸었더니 basecase step 0 에서
  // 즉시 반례 — 리셋 로직 결함이 아니라 검사 타이밍 어긋남이었다).
  // f_ok(= 직전·이번 에지 모두 reset 밖)는 「리셋을 지나 안정된 상태」만
  // 잰다 — 이 파일의 다른 모든 검사와 같은 전제.
  always @(*) if (f_ok) begin
    assert (shk_0_0 == key_0_0);
    assert (shk_1_0 == key_1_0);
    assert (shk_2_0 == key_2_0);
    assert (shk_3_0 == key_3_0);
  end

  always @(posedge clk) begin
    if (f_ok) begin
      // Decode.stall_uniform — MaskUnit 쪽 s4 몸(rValid/rFrame)도 en(=advance)
      // 이 낮으면 함께 선다. 구성 기입(keyWr/nonceWr/rekey)이 무엇을 하든.
      if (!$past(io_en))
        assert ($stable({io_rsp_valid, io_rsp_frame}));
      // (결선 계약) 고정 1사이클 왕복 — req.valid → 바로 다음 enable 에
      // rsp.valid. 가변 지연·조기 응답 부재 (MaskUnit.scala io.req 문면).
      if ($past(io_en))
        assert (io_rsp_valid == $past(io_req_valid));

      // Mask.key_write_own_only — 정본 7fa5f2e, e-defined.typ:339 「기입은 그 파티션의 마스크 유효를 즉시 떨어뜨린다」.
      // 파티션 p 로 향한 키 기입이 있었던 에지에서, q != p 의 maskReady
      // 비트는 그 에지를 건너 그대로다 (재구현 착수 시점 결함 — 전 파티션
      // 무효화 — 이 assert 가 정확히 그 형태를 잡는다: for 문 삭제 회귀 시
      // 반례).
      // REKEY 완료(FINAL 완주)로 그 사이클 유효화되는 파티션은 keyWr 과
      // 무관한 별개 원인이다(MaskUnit.scala:481 「maskValid(actPart) := !dirtyNow」,
      // PH_FINAL=3'd4 완주 다음 사이클 — 파도 D 2026-09-22 에 `!compDirty`
      // 에서 재조준·결속). 같은 파티션 겹침(FINAL 사이클의 actPart 기입)은
      // 아래 배제 조건이 keyWr.part != k 일 때만 걸리므로 여기서 관측되지
      // 않는다 — 그 모서리는 rtl/formal/sby/MaskUnit/engine.sby 가 잰다.
      // 실측(2026-09-16):
      // 이 배제 없이는 induction 이 UNKNOWN — keyWr(p) 와 REKEY(q) 완료가
      // 같은 사이클에 겹치면 q 의 maskReady 상승이 「keyWr 전용 assert」의
      // 위반으로 오판됐다(spurious — RTL 결함 아님, actPart 는 REKEY 시작
      // 때 캡처한 파티션이라 keyWr.part 와 독립적으로 아무 값이나 될 수
      // 있다). $past(actPart) 를 쓰는 이유 — FINAL 완주 판정(`$past(phase)
      // == PH_FINAL`)과 유효화 대상(actPart)은 **같은 에지 이전** 값이어야
      // 짝이 맞는다(actPart 는 FINAL 사이클 내내 안정이므로 $past 든 현재든
      // 값은 같지만, 문면의 짝을 명시한다).
      if ($past(io_keyWr_valid)) begin
        if ($past(io_keyWr_part) != 2'd0 && !($past(phase) == 3'd4 && $past(actPart) == 2'd0))
          assert (io_maskReady[0] == $past(io_maskReady[0]));
        if ($past(io_keyWr_part) != 2'd1 && !($past(phase) == 3'd4 && $past(actPart) == 2'd1))
          assert (io_maskReady[1] == $past(io_maskReady[1]));
        if ($past(io_keyWr_part) != 2'd2 && !($past(phase) == 3'd4 && $past(actPart) == 2'd2))
          assert (io_maskReady[2] == $past(io_maskReady[2]));
        if ($past(io_keyWr_part) != 2'd3 && !($past(phase) == 3'd4 && $past(actPart) == 2'd3))
          assert (io_maskReady[3] == $past(io_maskReady[3]));
      end

      // Mask.key_scoped_storage — 정본 7fa5f2e, E.9 4항 "엔진은 그
      // 파티션의 키와 논스를 읽는다". REKEY(p) 수락 다음 사이클, 엔진의
      // 유도 초기 상태 워드 0(st_4)은 *섀도우 키의 p 워드 0*과
      // 같다 — 창(MASK_PART)이 아니라 REKEY 기입 자신이 지목한 파티션.
      // shadow_target_d1 은 rekeyFire 와 **같은 에지**에서 캡처한 값이다
      // (위 해설 — 레이스 없이 DUT 의 논블로킹 타이밍과 맞춘다).
      if ($past(rekeyFire)) assert (st_4 == shadow_target_d1);

      // Mask.rekey_idle_only — 정본 7fa5f2e, e-defined.typ:345 「엔진이 유휴가 아니면 수락되지 않고」.
      // rekeyFire(= io_rekey_valid && io_rekey_ready) 가 실제로 발화하면
      // 그 사이클의 phase 는 IDLE(0) 이었어야 한다 — io_rekey_ready 배선
      // (= !engineBusy) 자신의 회귀 그물. (이 축의 로직은 이번 파도가
      // 건드리지 않는다 — 설계 문면 그대로 회귀만 잰다.)
      if (rekeyFire) assert (phase == 3'b000);
    end
  end

  // ── cover 증인 ──────────────────────────────────────────────────────────
`ifdef HIUMASK_COVER
  // W7 ← Decode.stall_uniform
  //      마스크 왕복이 실제로 돈다: 응답이 서고 값축이 비0 이다
  //      (rValid 가 늘 0 이면 위 왕복 등식이 0==0 으로 공허하다)
  always @(posedge clk) if (f_ok) w7_mask_roundtrip: cover (io_rsp_valid && (io_rsp_frame != 32'h0));

  // W16 ← Mask.key_write_own_only
  //       q(=파티션 0) 가 이미 maskReady 인 상태에서 *다른* 파티션으로
  //       향한 키 기입이 실제로 일어나는가 — 안 되면 위 assert 의
  //       "q != p" 전건이 공허하다. (「두 파티션이 동시에 ready」로
  //       처음 적었다가 depth 16 에서 미도달로 실패했다 — REKEY 는
  //       43사이클 고정 FSM(헤더 주석)이라 *둘 다* ready 이려면 REKEY
  //       가 최소 두 번 완주해야 하고 최소 depth 가 ~86 이다. 이 축이
  //       실제로 재려는 것 — "다른 파티션으로 향한 기입이 이미 ready 인
  //       파티션을 건드리지 않는가" — 은 REKEY 한 번 + 키 기입 한 번
  //       (~44사이클)으로도 충분히 증인이 선다. 더 싼 전건으로 같은
  //       것을 재는 쪽을 택했다.)
  always @(posedge clk)
    if (f_ok) w16_keywr_while_other_ready: cover (io_maskReady[0] && $past(io_keyWr_valid) && ($past(io_keyWr_part) != 2'd0));

  // W17 ← Mask.key_scoped_storage
  //       REKEY 수락이 실제로 일어나는가 (안 되면 위 assert 가 공허하다).
  always @(posedge clk) if (f_ok) w17_rekey_fires: cover ($past(rekeyFire));

  // W18 ← Mask.rekey_idle_only
  //       busy 중 REKEY 시도(→ 미수락)가 실제로 일어나는가 — 안 되면
  //       io_rekey_ready 의 "유휴가 아니면 미수락" 배선이 한 번도
  //       실행되지 않은 채 통과한 것이다.
  always @(posedge clk)
    if (f_ok) w18_rekey_busy_reject: cover (io_rekey_valid && !rekeyFire && (phase != 3'b000));

  // W8 ← Decode.stall_uniform
  //      MaskUnit 쪽 전제: en 이 낮은 에지를 *실린* 응답이
  //      건넌다 (rsp_valid 가 1 인 채로 동결 — 0 인 채 동결이 아니다)
  always @(posedge clk)
    if (f_ok && !$past(io_en)) w8_mask_frozen_loaded: cover (io_rsp_valid && (io_rsp_frame != 32'h0));
`endif // HIUMASK_COVER
endmodule

bind MaskUnit MaskUnit_props u_mask_props (
  .clk          (clk),
  .reset        (reset),
  .io_en        (io_en),
  .io_req_valid (io_req_valid),
  .io_rsp_valid (io_rsp_valid),
  .io_rsp_frame (io_rsp_frame),
  .io_keyWr_valid (io_keyWr_valid),
  .io_keyWr_part  (io_keyWr_part),
  .io_keyWr_idx   (io_keyWr_idx),
  .io_keyWr_data  (io_keyWr_data),
  .rekeyFire      (rekeyFire),
  .io_rekey_valid (io_rekey_valid),
  .io_rekey_part  (io_rekey_part),
  .io_maskReady   (io_maskReady),
  .st_4           (st_4),
  .phase          (phase),
  .key_0_0        (key_0_0),
  .key_1_0        (key_1_0),
  .key_2_0        (key_2_0),
  .key_3_0        (key_3_0),
  .actPart        (actPart)
);

// ── HiuPipeline 쪽 bind — 파일 *맨 끝*이어야 한다.
// hiumask.sby 의 텍스트 전개가 두 bind 를 「MaskUnit 것 먼저, HiuPipeline 것
// 마지막」 순서로 잘라낸다 (sed 종료 주소에 ';' 와 ')' 를 쓸 수 없어 — yosys
// exec 의 인용 전달이 깨진다 — 시작 패턴 + 파일 끝으로만 구간을 짚는다).
bind HiuPipeline HiuPipeline_props u_hiu_props (
  .clk               (clk),
  .reset             (reset),
  .advance           (advance),
  .io_hold           (io_hold),
  .io_req_valid      (io_req_valid),
  .io_mask_rsp_valid (io_mask_rsp_valid),
  .io_rsp_valid      (io_rsp_valid),
  .io_rsp_granted    (io_rsp_granted),
  .io_rsp_frame      (io_rsp_frame),
  .io_rsp_perm_r     (io_rsp_perm_r),
  .io_rsp_perm_w     (io_rsp_perm_w),
  .io_rsp_perm_x     (io_rsp_perm_x),
  .s1_valid          (s1_valid),
  .s2_valid          (s2_valid),
  .s3_valid          (s3_valid),
  .s5_valid          (s5_valid),
  .s6_valid          (s6_valid),
  .f_stage_data      ({s1_part, s1_vpn, s1_write,
                       s2_part, s2_vpn, s2_write,
                       s3_part, s3_vpn, s3_write,
                       s4_part, s4_write, s4_anyHit, s4_fromFill, s4_frame,
                       s4_perm_r, s4_perm_w, s4_perm_x,
                       s5_part, s5_write, s5_anyHit, s5_fromFill, s5_frame,
                       s5_masked, s5_perm_r, s5_perm_w, s5_perm_x,
                       s6_part, s6_write, s6_anyHit, s6_fromFill, s6_frame,
                       s6_masked, s6_perm_r, s6_perm_w, s6_perm_x}),
  .io_owner_devOwned (io_owner_devOwned),
  .io_faultPerm      (io_faultPerm),
  .io_faultClear     (io_faultClear),
  .io_flush_valid    (io_flush_valid),
  .io_flush_part     (io_flush_part),
  .io_hostRsp_valid  (io_hostRsp_valid),
  .f_kill            (io_install_valid && io_install_ready && !io_install_v),
  .f_kill_part       (io_install_part),
  .io_hostRsp_frame  (io_hostRsp_frame),
  .s3_part           (s3_part),
  .s3_vpn            (s3_vpn),
  .s4_anyHit         (s4_anyHit),
  .s4_fromFill       (s4_fromFill),
  .s4_frame          (s4_frame),
  .s4_perm_r         (s4_perm_r),
  .s4_perm_w         (s4_perm_w),
  .s4_perm_x         (s4_perm_x),
  .s6_anyHit         (s6_anyHit),
  .s6_write          (s6_write),
  .s6_perm_r         (s6_perm_r),
  .s6_perm_w         (s6_perm_w),
  .x_hit             (xlate_io_rsp_hit),
  .x_fromFill        (xlate_io_rsp_fromFill),
  .x_frame           (xlate_io_rsp_frame),
  .x_perm_r          (xlate_io_rsp_perm_r),
  .x_perm_w          (xlate_io_rsp_perm_w),
  .x_perm_x          (xlate_io_rsp_perm_x),
  .x_hostPresent     (xlate_io_rsp_hostPresent),
  .lookFrame         (lookFrame),
  .lookPerm_r        (lookPerm_r),
  .lookPerm_w        (lookPerm_w),
  .lookPerm_x        (lookPerm_x),
  .io_req_part       (io_req_part),
  .io_req_vpn        (io_req_vpn),
  .s1_part           (s1_part),
  .s1_vpn            (s1_vpn),
  .s2_part           (s2_part),
  .s2_vpn            (s2_vpn),
  .missStall         (missStall),
  .missPart          (missPart),
  .missVpn           (missVpn),
  .io_missNotice     (io_missNotice),
  .io_missClear      (io_missClear),
  .io_install_valid  (io_install_valid),
  .io_install_ready  (io_install_ready),
  .io_install_part   (io_install_part),
  .installSlotFree   (installSlotFree),
  .s6_frame          (s6_frame),
  .faultOwn          (faultOwn),
  .faultOwnClear     (faultOwnClear),
  .io_mask_req_frame (io_mask_req_frame),
  .io_owner_frame    (io_owner_frame)
);
