// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// Reassembly 후-formal 하네스 — 선-formal Payload.tla 가드 중 배타·토큰 파도
// 담당분(key_is_tag·no_restart·no_dup_seq·cap_check·capability_not_fault·
// last_judges·reset_on_deliver·abort_erases·abort_leaves_trace·abort_not_fault·
// write_atomic)을 커밋된 rtl/generated/Reassembly.sv (nCtxs=4, slotCap=16,
// seq/total 8비트) 에 대해 재검사. bind 로 대상 안에 부착 — 포트는 대상
// 내부 신호명 그대로 결선한다.
//
// ══ ⚠ 줄 번호에 매인 신호 이름 — 한 곳에 모아 둔다 (2026-08-25 실측) ═══
//
// SpinalHDL 은 익명 `when` 조건 신호를 **소스 줄 번호**로 이름 짓는다
// (`when_<파일>_l<줄>`). 그래서 Common.scala 의 줄이 밀리면 이 이름이 조용히
// 바뀐다. 이 하네스의 부착 방식(bind 문을 대상 모듈 본문으로 텍스트 전개)에서는
// 없는 이름이 *암묵 wire* 로 살아나 자유 신호가 되고, 그 위에 선 단언은 반증
// 가능해진다 — 2026-08-25 에 p_ab_not_fault_src 가 정확히 그렇게 FAIL 했다
// (호스트 ABI 결정 4·5 파도가 Common.scala 를 늘려 l141 → l259 · 태그 코덱 전파
// 파도가 Tag 코덱을 E.5.1 재배분으로 고쳐 l259 → l337).
//
// *크게 실패한 것은 다행이다.* 그리고 그 태스크를 돌리게 한 것은 사람의 기억이
// 아니라 scripts/sby_impact.py 역색인이었다 — 그 도구가 존재하는 이유가 이
// 부류다. 아래 매크로가 다음에 밀릴 때 고칠 자리를 한 줄로 만든다.
//
// (근본 수리는 그 조건에 안정된 이름을 주는 것이고, 그것은 StickyFault 를 쓰는
//  전 모듈의 생성물 이름을 움직이므로 별 파도다 — rtl/README.md 등재.)
`define WT_STICKY_SET_FAULT when_Common_l337
//
// 문체: yosys 개방판은 SVA 시퀀스를 받지 않으므로 즉시 단언(always+$past).
// sticky 관측면(io_fault·io_capAbsent)은 차기 상태 함수의 *등식*으로 잰다 —
// 등식이 서면 set 원천의 전수 목록이 기계 검증되므로 「~는 fault 를 세우지
// 않는다」류 부정 명제가 문면 그대로 닫힌다.
module Reassembly_props (
  input logic        clk,
  input logic        reset,
  // 개방 면
  input logic        io_open_valid,
  input logic [7:0]  io_open_base,
  input logic        io_open_granted,
  // 세 매칭 면의 태그 (태그 코덱 전파 파도 — 키 투영 단언 p_key_* 의 입력)
  input logic [31:0] io_open_tag_wave,
  input logic [3:0]  io_open_tag_epoch,
  input logic        io_open_tag_poison,
  input logic        io_open_tag_trace,
  input logic [15:0] io_open_tag_lnid,
  input logic [7:0]  io_open_tag_precision,
  input logic [7:0]  io_open_tag_dim,
  input logic [31:0] io_frag_head_tag_wave,
  input logic [3:0]  io_frag_head_tag_epoch,
  input logic        io_frag_head_tag_poison,
  input logic        io_frag_head_tag_trace,
  input logic [15:0] io_frag_head_tag_lnid,
  input logic [7:0]  io_frag_head_tag_precision,
  input logic [7:0]  io_frag_head_tag_dim,
  input logic [31:0] io_abort_tag_wave,
  input logic [3:0]  io_abort_tag_epoch,
  input logic        io_abort_tag_poison,
  input logic        io_abort_tag_trace,
  input logic [15:0] io_abort_tag_lnid,
  input logic [7:0]  io_abort_tag_precision,
  input logic [7:0]  io_abort_tag_dim,
  // 조각 면
  input logic        io_frag_valid,
  input logic [7:0]  io_frag_head_seq,
  input logic [7:0]  io_frag_head_total,
  input logic        io_frag_head_last,
  // 기입 면
  input logic        io_wr_valid,
  input logic [7:0]  io_wr_base,
  input logic [3:0]  io_wr_off,
  // 인도 면
  input logic        io_deliver_valid,
  input logic        io_deliver_fire,
  input logic [3:0]  dv_grantOh,
  // 소거 면
  input logic        io_abort_valid,
  input logic [7:0]  io_abortCount,
  input logic        ab_fire,
  input logic        ab_hitAny,
  input logic        ab_hit_0, ab_hit_1, ab_hit_2, ab_hit_3,
  // 구간 무효화 면 (결정 B)
  input logic        io_clr_valid,
  input logic [7:0]  io_clr_base,
  // sticky 관측면
  input logic        io_fault,
  input logic        io_faultClear,
  input logic        io_capAbsent,
  input logic        io_capAbsentClear,
  input logic        `WT_STICKY_SET_FAULT,
  // 조각 접수 판정 내부
  input logic        fr_hit_0, fr_hit_1, fr_hit_2, fr_hit_3,
  input logic        fr_hitAny,
  input logic        fr_accept,
  input logic        fr_capaRej,
  input logic        fr_strayRej,
  input logic        fr_totBad,
  input logic        fr_overRej,
  input logic        fr_dupRej,
  input logic        fr_cKnown,
  input logic [15:0] fr_cSeen,
  input logic [15:0] fr_ohSeq,
  input logic [15:0] fr_newSeen,
  input logic [7:0]  fr_effTotal,
  input logic [7:0]  fr_cBase,
  input logic        fr_rejEvt,
  input logic        fr_endEvt,
  input logic        fr_capaEvt,
  input logic [15:0] _zz_fr_endBad,   // fullMask(fr_effTotal) 조회 결과
  // 개방 판정 내부
  input logic        op_clash,
  input logic        op_clashEvt,
  input logic        op_grant,
  input logic        op_freeAny,
  input logic [3:0]  op_freeOh,
  // 문맥 풀 (nCtxs=4)
  input logic        ctx_0_active,
  input logic [31:0] ctx_0_tag_wave,
  input logic [3:0]  ctx_0_tag_epoch,
  input logic        ctx_0_tag_poison,
  input logic        ctx_0_tag_trace,
  input logic [15:0] ctx_0_tag_lnid,
  input logic [7:0]  ctx_0_tag_precision,
  input logic [7:0]  ctx_0_tag_dim,
  input logic [7:0]  ctx_0_base,
  input logic [7:0]  ctx_0_total,
  input logic        ctx_0_totalKnown,
  input logic [15:0] ctx_0_seen,
  input logic        ctx_0_last,
  input logic        ctx_1_active,
  input logic [31:0] ctx_1_tag_wave,
  input logic [3:0]  ctx_1_tag_epoch,
  input logic        ctx_1_tag_poison,
  input logic        ctx_1_tag_trace,
  input logic [15:0] ctx_1_tag_lnid,
  input logic [7:0]  ctx_1_tag_precision,
  input logic [7:0]  ctx_1_tag_dim,
  input logic [7:0]  ctx_1_base,
  input logic [7:0]  ctx_1_total,
  input logic        ctx_1_totalKnown,
  input logic [15:0] ctx_1_seen,
  input logic        ctx_1_last,
  input logic        ctx_2_active,
  input logic [31:0] ctx_2_tag_wave,
  input logic [3:0]  ctx_2_tag_epoch,
  input logic        ctx_2_tag_poison,
  input logic        ctx_2_tag_trace,
  input logic [15:0] ctx_2_tag_lnid,
  input logic [7:0]  ctx_2_tag_precision,
  input logic [7:0]  ctx_2_tag_dim,
  input logic [7:0]  ctx_2_base,
  input logic [7:0]  ctx_2_total,
  input logic        ctx_2_totalKnown,
  input logic [15:0] ctx_2_seen,
  input logic        ctx_2_last,
  input logic        ctx_3_active,
  input logic [31:0] ctx_3_tag_wave,
  input logic [3:0]  ctx_3_tag_epoch,
  input logic        ctx_3_tag_poison,
  input logic        ctx_3_tag_trace,
  input logic [15:0] ctx_3_tag_lnid,
  input logic [7:0]  ctx_3_tag_precision,
  input logic [7:0]  ctx_3_tag_dim,
  input logic [7:0]  ctx_3_base,
  input logic [7:0]  ctx_3_total,
  input logic        ctx_3_totalKnown,
  input logic [15:0] ctx_3_seen,
  input logic        ctx_3_last
);

  // ── 리셋 규율 ────────────────────────────────────────────────────────
  // ENV: 기계는 리셋에서 시작한다 (Payload.tla Init 대응 — 모든 문맥
  // Free·회계 0). 근거: 모델 Init 이 유일한 시작점이고 RTL 의 대응물이
  // 리셋이다. 이것이 이 하네스의 유일한 assume 이다.
  initial assume (reset);

  logic f_past_valid = 1'b0;
  logic f_past_reset = 1'b1;
  always @(posedge clk) begin
    f_past_valid <= 1'b1;
    f_past_reset <= reset;
  end
  wire f_step = f_past_valid && !reset && !f_past_reset;

  // ── 형상 상수 — 이 하네스가 검사하는 커밋 생성물의 형상 (파일 머리 참조) ──
  // Reassembly.scala:148 의 `require(slotCap <= 254)` 가 「선언 총개수 8비트
  // 값 공간 안에 능력 부재 축이 표현 가능하다」를 elaborate 로 못박아 둔
  // 덕분에 아래 비교가 값 공간 넓은 비교로 선다 (16 초과 값 239개) — 폭이
  // 답을 정해 버리는 항진명제의 정반대 자리다.
  localparam [7:0] WT_SLOT_CAP = 8'd16;

  // ── 독립 참조: 능력 부재 판정 (Payload.capability_check) ────────────────
  //
  // **DUT 의 비교기를 재인용하지 않는다.** fr_capaRej 는 `slotCap < head.total`
  // 한 개의 비교 셀인데, 아래 참조는 같은 술어를 *비트 분해*로 따로 만든다:
  //   total > 16  ⇔  total[7:5] != 0  ∨  (total[4] ∧ total[3:0] != 0)
  // 두 계산이 구조적으로 달라 opt 가 하나로 합치지 못하므로 p_capa_def 의
  // 등식이 상수로 접히지 않는다. 그리고 이 형태는 이 저장소가 실제로 밟은
  // 「조용한 절단」(§1.3 함정 부류)을 정면으로 잰다 — DUT 가 총개수를 4비트로
  // 잘라 비교하면 total=32 에서 즉시 반례가 난다.
  wire f_capa_ref = (|io_frag_head_total[7:5])
                 || (io_frag_head_total[4] && (|io_frag_head_total[3:0]));

  // 개방 착지 one-hot — 개방 수락 when 블록의 생성 조건 이름은 줄번호에
  // 매여 있으므로(`when_Reassembly_l<N>` — 파일 머리 함정 2형) 쓰지 않는다.
  // 안정된 이름 둘(op_grant · op_freeOh)로 여기서 되만든다.
  wire [3:0] f_grant_oh = {4{op_grant}} & op_freeOh;

  // 키 투영 비교 — wave · 에포크 · LNID · 정밀도 · 차원 (poison · trace 제외 —
  // key_is_tag 의 「태그」의 범위는 Payload.key_drops_side 가 정한다, 04-ext-payload 4.3)
  wire tag_eq_01 = (ctx_0_tag_wave == ctx_1_tag_wave) && (ctx_0_tag_epoch == ctx_1_tag_epoch)
                && (ctx_0_tag_lnid == ctx_1_tag_lnid) && (ctx_0_tag_precision == ctx_1_tag_precision)
                && (ctx_0_tag_dim == ctx_1_tag_dim);
  wire tag_eq_02 = (ctx_0_tag_wave == ctx_2_tag_wave) && (ctx_0_tag_epoch == ctx_2_tag_epoch)
                && (ctx_0_tag_lnid == ctx_2_tag_lnid) && (ctx_0_tag_precision == ctx_2_tag_precision)
                && (ctx_0_tag_dim == ctx_2_tag_dim);
  wire tag_eq_03 = (ctx_0_tag_wave == ctx_3_tag_wave) && (ctx_0_tag_epoch == ctx_3_tag_epoch)
                && (ctx_0_tag_lnid == ctx_3_tag_lnid) && (ctx_0_tag_precision == ctx_3_tag_precision)
                && (ctx_0_tag_dim == ctx_3_tag_dim);
  wire tag_eq_12 = (ctx_1_tag_wave == ctx_2_tag_wave) && (ctx_1_tag_epoch == ctx_2_tag_epoch)
                && (ctx_1_tag_lnid == ctx_2_tag_lnid) && (ctx_1_tag_precision == ctx_2_tag_precision)
                && (ctx_1_tag_dim == ctx_2_tag_dim);
  wire tag_eq_13 = (ctx_1_tag_wave == ctx_3_tag_wave) && (ctx_1_tag_epoch == ctx_3_tag_epoch)
                && (ctx_1_tag_lnid == ctx_3_tag_lnid) && (ctx_1_tag_precision == ctx_3_tag_precision)
                && (ctx_1_tag_dim == ctx_3_tag_dim);
  wire tag_eq_23 = (ctx_2_tag_wave == ctx_3_tag_wave) && (ctx_2_tag_epoch == ctx_3_tag_epoch)
                && (ctx_2_tag_lnid == ctx_3_tag_lnid) && (ctx_2_tag_precision == ctx_3_tag_precision)
                && (ctx_2_tag_dim == ctx_3_tag_dim);

  // ── Payload.key_drops_side — 세 매칭의 키가 poison · trace 를 뺀다 (태그 코덱 전파 파도) ──
  //
  // 정본: 04-ext-payload 4.3 「*그러나 키는 태그 전량이 아니다 — poison 과 trace 는
  // 빠진다.*」 · e-defined E.12 6항 「⇒ 키는 wave · 에포크 · LNID · 정밀도 · 차원이다」.
  // 참조는 필드별 등식의 연언이다 — DUT 의 넓은 연접 비교 한 셀을 재인용하지 않는다
  // (p_capa_def 와 같은 이유: 두 계산이 구조로 달라야 opt 가 합치지 못한다). 등식이라
  // 두 방향을 다 잰다: poison · trace 를 키에 넣는 기계(오늘의 번들 통비교 — D2b)는
  // 그 비트만 다른 도착에서, 키 필드 하나를 빠뜨린 기계는 그 필드만 다른 도착에서 반례가
  // 난다. 전건 없는 조합 등식이라 전 사이클에서 선다.
  wire k_fh_0 = (ctx_0_tag_wave == io_frag_head_tag_wave) && (ctx_0_tag_epoch == io_frag_head_tag_epoch)
                && (ctx_0_tag_lnid == io_frag_head_tag_lnid) && (ctx_0_tag_precision == io_frag_head_tag_precision)
                && (ctx_0_tag_dim == io_frag_head_tag_dim);
  wire k_fh_1 = (ctx_1_tag_wave == io_frag_head_tag_wave) && (ctx_1_tag_epoch == io_frag_head_tag_epoch)
                && (ctx_1_tag_lnid == io_frag_head_tag_lnid) && (ctx_1_tag_precision == io_frag_head_tag_precision)
                && (ctx_1_tag_dim == io_frag_head_tag_dim);
  wire k_fh_2 = (ctx_2_tag_wave == io_frag_head_tag_wave) && (ctx_2_tag_epoch == io_frag_head_tag_epoch)
                && (ctx_2_tag_lnid == io_frag_head_tag_lnid) && (ctx_2_tag_precision == io_frag_head_tag_precision)
                && (ctx_2_tag_dim == io_frag_head_tag_dim);
  wire k_fh_3 = (ctx_3_tag_wave == io_frag_head_tag_wave) && (ctx_3_tag_epoch == io_frag_head_tag_epoch)
                && (ctx_3_tag_lnid == io_frag_head_tag_lnid) && (ctx_3_tag_precision == io_frag_head_tag_precision)
                && (ctx_3_tag_dim == io_frag_head_tag_dim);
  wire k_ab_0 = (ctx_0_tag_wave == io_abort_tag_wave) && (ctx_0_tag_epoch == io_abort_tag_epoch)
                && (ctx_0_tag_lnid == io_abort_tag_lnid) && (ctx_0_tag_precision == io_abort_tag_precision)
                && (ctx_0_tag_dim == io_abort_tag_dim);
  wire k_ab_1 = (ctx_1_tag_wave == io_abort_tag_wave) && (ctx_1_tag_epoch == io_abort_tag_epoch)
                && (ctx_1_tag_lnid == io_abort_tag_lnid) && (ctx_1_tag_precision == io_abort_tag_precision)
                && (ctx_1_tag_dim == io_abort_tag_dim);
  wire k_ab_2 = (ctx_2_tag_wave == io_abort_tag_wave) && (ctx_2_tag_epoch == io_abort_tag_epoch)
                && (ctx_2_tag_lnid == io_abort_tag_lnid) && (ctx_2_tag_precision == io_abort_tag_precision)
                && (ctx_2_tag_dim == io_abort_tag_dim);
  wire k_ab_3 = (ctx_3_tag_wave == io_abort_tag_wave) && (ctx_3_tag_epoch == io_abort_tag_epoch)
                && (ctx_3_tag_lnid == io_abort_tag_lnid) && (ctx_3_tag_precision == io_abort_tag_precision)
                && (ctx_3_tag_dim == io_abort_tag_dim);
  wire k_op_0 = (ctx_0_tag_wave == io_open_tag_wave) && (ctx_0_tag_epoch == io_open_tag_epoch)
                && (ctx_0_tag_lnid == io_open_tag_lnid) && (ctx_0_tag_precision == io_open_tag_precision)
                && (ctx_0_tag_dim == io_open_tag_dim);
  wire k_op_1 = (ctx_1_tag_wave == io_open_tag_wave) && (ctx_1_tag_epoch == io_open_tag_epoch)
                && (ctx_1_tag_lnid == io_open_tag_lnid) && (ctx_1_tag_precision == io_open_tag_precision)
                && (ctx_1_tag_dim == io_open_tag_dim);
  wire k_op_2 = (ctx_2_tag_wave == io_open_tag_wave) && (ctx_2_tag_epoch == io_open_tag_epoch)
                && (ctx_2_tag_lnid == io_open_tag_lnid) && (ctx_2_tag_precision == io_open_tag_precision)
                && (ctx_2_tag_dim == io_open_tag_dim);
  wire k_op_3 = (ctx_3_tag_wave == io_open_tag_wave) && (ctx_3_tag_epoch == io_open_tag_epoch)
                && (ctx_3_tag_lnid == io_open_tag_lnid) && (ctx_3_tag_precision == io_open_tag_precision)
                && (ctx_3_tag_dim == io_open_tag_dim);
  always @(*) if (!reset) begin
    p_key_hit_0:   assert (fr_hit_0 == (ctx_0_active && k_fh_0));
    p_key_hit_1:   assert (fr_hit_1 == (ctx_1_active && k_fh_1));
    p_key_hit_2:   assert (fr_hit_2 == (ctx_2_active && k_fh_2));
    p_key_hit_3:   assert (fr_hit_3 == (ctx_3_active && k_fh_3));
    p_key_abhit_0: assert (ab_hit_0 == (ctx_0_active && k_ab_0));
    p_key_abhit_1: assert (ab_hit_1 == (ctx_1_active && k_ab_1));
    p_key_abhit_2: assert (ab_hit_2 == (ctx_2_active && k_ab_2));
    p_key_abhit_3: assert (ab_hit_3 == (ctx_3_active && k_ab_3));
    p_key_clash:   assert (op_clash == ((ctx_0_active && k_op_0) || (ctx_1_active && k_op_1) ||
                                    (ctx_2_active && k_op_2) || (ctx_3_active && k_op_3)));
  end

  // ═══ 상태 불변식 (리셋 밖 전 사이클) ═══════════════════════════════
  always @(*) if (!reset) begin
    // Payload.key_is_tag + Payload.no_restart — 태그당 활성 문맥 <= 1.
    // CAM one-hot 의 원천 불변식: 활성 문맥 쌍의 태그는 전부 상이하다.
    // (개방측 op_clash 거절이 유지하고, 해방은 활성만 줄인다 — 귀납 성립)
    inv_tag_uniq_01: assert (!(ctx_0_active && ctx_1_active && tag_eq_01));
    inv_tag_uniq_02: assert (!(ctx_0_active && ctx_2_active && tag_eq_02));
    inv_tag_uniq_03: assert (!(ctx_0_active && ctx_3_active && tag_eq_03));
    inv_tag_uniq_12: assert (!(ctx_1_active && ctx_2_active && tag_eq_12));
    inv_tag_uniq_13: assert (!(ctx_1_active && ctx_3_active && tag_eq_13));
    inv_tag_uniq_23: assert (!(ctx_2_active && ctx_3_active && tag_eq_23));

    // key_is_tag 의 관측 결과: 조각 CAM 탐색 hit 은 one-hot (쌍별 배타).
    inv_hit_excl_01: assert (!(fr_hit_0 && fr_hit_1));
    inv_hit_excl_02: assert (!(fr_hit_0 && fr_hit_2));
    inv_hit_excl_03: assert (!(fr_hit_0 && fr_hit_3));
    inv_hit_excl_12: assert (!(fr_hit_1 && fr_hit_2));
    inv_hit_excl_13: assert (!(fr_hit_1 && fr_hit_3));
    inv_hit_excl_23: assert (!(fr_hit_2 && fr_hit_3));
    // 소거 CAM 도 같은 키·같은 배타 (abort_erases 의 one-hot 전제).
    inv_abhit_excl_01: assert (!(ab_hit_0 && ab_hit_1));
    inv_abhit_excl_02: assert (!(ab_hit_0 && ab_hit_2));
    inv_abhit_excl_03: assert (!(ab_hit_0 && ab_hit_3));
    inv_abhit_excl_12: assert (!(ab_hit_1 && ab_hit_2));
    inv_abhit_excl_13: assert (!(ab_hit_1 && ab_hit_3));
    inv_abhit_excl_23: assert (!(ab_hit_2 && ab_hit_3));

    // Payload.no_restart — 진행 중 태그 재개시는 거절 (granted 억제).
    p_no_restart_grant: assert (!(io_open_granted && op_clash));
    p_no_restart_evt:   assert (op_clashEvt == (io_open_valid && op_clash));

    // Payload.no_dup_seq — 수락은 seen 에 없는 순번뿐 (재기입 부재의 원천).
    p_no_dup_accept: assert (!fr_accept || ((fr_cSeen & fr_ohSeq) == 16'h0000));

    // Payload.cap_check 보조 불변식 — 래치된 선언 총개수는 1..slotCap(16).
    // (수락 경로가 !capaRej(총개수<=16)·!overRej(순번>=1, 순번<=effTotal)를
    //  지나므로 래치 값이 이 창을 벗어날 수 없다 — 귀납 성립)
    inv_total_bounds_0: assert (!ctx_0_totalKnown || (8'h01 <= ctx_0_total && ctx_0_total <= 8'h10));
    inv_total_bounds_1: assert (!ctx_1_totalKnown || (8'h01 <= ctx_1_total && ctx_1_total <= 8'h10));
    inv_total_bounds_2: assert (!ctx_2_totalKnown || (8'h01 <= ctx_2_total && ctx_2_total <= 8'h10));
    inv_total_bounds_3: assert (!ctx_3_totalKnown || (8'h01 <= ctx_3_total && ctx_3_total <= 8'h10));

    // Payload.cap_check — 기입 면에 구간 밖 좌표가 실리지 않는다:
    // 발화 시 순번은 1..선언 총개수, 총개수는 slotCap(16) 이내, off = 순번-1.
    p_cap_window: assert (!io_wr_valid ||
                          (io_frag_head_seq != 8'h00 &&
                           io_frag_head_seq <= fr_effTotal &&
                           fr_effTotal != 8'h00 && fr_effTotal <= 8'h10));
    p_cap_off:    assert (!io_wr_valid ||
                          ({4'h0, io_wr_off} == (io_frag_head_seq - 8'h01)));

    // Payload.capability_not_fault — set 항 분리 (조각 축): 능력 부재
    // 사건과 malformation·종료 fault 사건은 같은 조각에서 동시에 서지
    // 않는다 (판정 순서 「능력 → …」의 문면).
    p_capa_excl: assert (!(fr_capaEvt && (fr_rejEvt || fr_endEvt)));

    // Payload.last_judges — 종료 판정의 문면: 표시 접수(수락 조각의 last)
    // 시점에 갱신 후 수신 집합 != 선언 전량 마스크 ⇔ endEvt.
    p_last_judges_def: assert (fr_endEvt ==
                               (fr_accept && io_frag_head_last && (fr_newSeen != _zz_fr_endBad)));

    // Payload.reset_on_deliver + Payload.abort_erases 의 불변식 형태 —
    // 「태그만 해방하고 회계를 남기는 경로가 없다」: 비활성 문맥의 회계는
    // 언제나 공(空)이다.
    inv_free_clean_0: assert (ctx_0_active || (ctx_0_seen == 16'h0000 && !ctx_0_last && !ctx_0_totalKnown));
    inv_free_clean_1: assert (ctx_1_active || (ctx_1_seen == 16'h0000 && !ctx_1_last && !ctx_1_totalKnown));
    inv_free_clean_2: assert (ctx_2_active || (ctx_2_seen == 16'h0000 && !ctx_2_last && !ctx_2_totalKnown));
    inv_free_clean_3: assert (ctx_3_active || (ctx_3_seen == 16'h0000 && !ctx_3_last && !ctx_3_totalKnown));

    // Payload.abort_not_fault (+ capability_not_fault 의 소거 축) —
    // fault·capAbsent 의 set 사건 원천에는 조각·개방 항뿐이다: 조각도
    // 개방도 없는 사이클(소거만 있는 사이클 포함)엔 set 사건이 없다.
    p_ab_not_fault_src: assert ((io_frag_valid || io_open_valid) || !`WT_STICKY_SET_FAULT);
    p_ab_not_capa_src:  assert (io_frag_valid || !fr_capaEvt);

    // Payload.abort_leaves_trace 전제 — 소거 발화의 문면: 있는 태그를 맞힌
    // 소거뿐이다 (없는 태그 무시는 발화가 아니다).
    p_ab_fire_def: assert (ab_fire == (io_abort_valid && ab_hitAny));

    // ── Payload.abort_clears_window (결정 B · 정본 E.12 1항 구간 축) ──────
    //
    // 「소거는 구간 데이터까지 비운다」의 RTL 형. 이 모듈은 슬롯 실물을
    // 소유하지 않으므로 비우기는 *명령*이고, 계약은 그 명령이 회계 소거와
    // **같은 게이트**라는 것이다 — 등식이 서면 「회계는 비웠는데 구간은
    // 안 비웠다」(2026-08-25 이전의 이 RTL 그 자체)가 표현 불가가 된다.
    p_abort_clears_slots: assert (io_clr_valid == ab_fire);

    // 좌표는 *소거 대상 문맥의 결속*이다 — 소거가 「어느 구간을 비우는가」를
    // 스스로 지어내지 않는다 (base_from_tag 의 소거 축). 그리고 그 값은 이
    // 사이클의 레지스터이므로 §4.3 「소거 후 재사용」 3항의 「결속을 버리기
    // *전에* 구간을 비운다」가 구조로 성립한다 — 결속 관측(active)이 내려가는
    // 것은 다음 사이클이고 그때 명령은 이미 떠났다.
    p_clr_base_0: assert (!(io_clr_valid && ab_hit_0) || (io_clr_base == ctx_0_base));
    p_clr_base_1: assert (!(io_clr_valid && ab_hit_1) || (io_clr_base == ctx_1_base));
    p_clr_base_2: assert (!(io_clr_valid && ab_hit_2) || (io_clr_base == ctx_2_base));
    p_clr_base_3: assert (!(io_clr_valid && ab_hit_3) || (io_clr_base == ctx_3_base));

    // 무효화 명령은 *반드시* 맞힌 문맥이 있다 — 허공을 비우는 beat 가 없다
    // (없는 태그 무시가 무효화 명령을 내지 않는다는 문면).
    p_clr_needs_hit: assert (!io_clr_valid || ab_hitAny);

    // Payload.write_atomic — 기입 면 발화 == 접수 판정 (같은 사이클·같은
    // 게이트, 사이를 가르는 파이프 단 없음).
    p_wr_atomic_face: assert (io_wr_valid == fr_accept);

    // ══ Payload.capability_check (2차 파도 신설) ═════════════════════════
    //
    // 모델의 접수 순서는 「능력 → 상한 → 재시작 → 중복」이고 Payload.tla:431-437
    // 이 CapRej·RestartRej·DupRej 전부의 전건에 ~CapaRej 를 넣는다. 그
    // *순서*의 관측 가능한 알맹이는 「능력 밖 조각열은 나머지 판정·회계·기입에
    // 불참한다」이며 여기서는 그것을 **DUT 의 fr_capaRej 가 아니라 독립 참조
    // f_capa_ref 를 전건으로** 적는다.
    //
    // 왜 그게 요점인가: RTL 의 strayRej·totBad·overRej·dupRej·accept 는 전부
    // 문면 그대로 `!capaRej && …` 로 시작한다. 전건에 fr_capaRej 를 쓰면
    // `!capaRej ∨ !(!capaRej ∧ X)` 가 되어 **부울 항등식**이다 — 셀은 세어지고
    // 증명도 통과하는데 아무것도 재지 않는다 (이 저장소가 세 번째로 밟은
    // 공허 형태 그대로). 독립 참조를 전건에 두면 그 붕괴가 일어나지 않고,
    // 판정 순서를 뒤집은 구현(능력 판정을 상한 뒤로 옮긴 구현)에서 반례가 난다.
    p_capa_def:      assert (fr_capaRej == f_capa_ref);
    p_capa_excl_all: assert (!(io_frag_valid && f_capa_ref) ||
                             (!fr_accept && !io_wr_valid &&
                              !fr_strayRej && !fr_totBad && !fr_overRej && !fr_dupRej &&
                              !fr_rejEvt && !fr_endEvt));

    // ══ Payload.base_from_tag — 조각 축 (소거 축 p_clr_base_* 의 거울) ════
    //
    // 기입 착지 좌표는 *적중 문맥의 결속*이다 — 조각이 나른 값도, 다른 문맥의
    // 결속도 아니다. 조각 머리는 태그·순번·총개수·표시만 나르므로 (§4.3 결속
    // 규범) 이 등식이 깨지는 유일한 길은 결속 원천이 어긋나는 구현이다.
    p_wr_base_0: assert (!(io_wr_valid && fr_hit_0) || (io_wr_base == ctx_0_base));
    p_wr_base_1: assert (!(io_wr_valid && fr_hit_1) || (io_wr_base == ctx_1_base));
    p_wr_base_2: assert (!(io_wr_valid && fr_hit_2) || (io_wr_base == ctx_2_base));
    p_wr_base_3: assert (!(io_wr_valid && fr_hit_3) || (io_wr_base == ctx_3_base));
  end

  // ═══ 전이 단언 (연속 두 사이클 리셋 밖) ═══════════════════════════
  always @(posedge clk) if (f_step) begin
    // sticky 차기 상태 *등식* — set 원천의 전수 목록을 기계 검증한다.
    //   io_fault 의 set 은 위 매크로가 가리키는 조건(= fr_rejEvt | fr_endEvt |
    //   op_clashEvt) 뿐 → 능력 부재(capability_not_fault)도 소거
    //   (abort_not_fault)도 fault 를 세울 수 없다.
    //   io_capAbsent 의 set 은 fr_capaEvt 뿐 → malformation 이 capAbsent 를
    //   세울 수 없다. 두 관측면의 set 분리가 등식 둘로 닫힌다.
    t_fault_next_eq: assert (io_fault ==
        ($past(`WT_STICKY_SET_FAULT) || ($past(io_fault) && !$past(io_faultClear))));
    t_capa_next_eq:  assert (io_capAbsent ==
        ($past(fr_capaEvt) || ($past(io_capAbsent) && !$past(io_capAbsentClear))));

    // Payload.no_restart — 재시작 거절은 loud: 다음 사이클 fault 관측.
    t_no_restart_loud: assert (!$past(op_clashEvt) || io_fault);

    // Payload.last_judges — 불완전 종료는 loud: 다음 사이클 fault 관측.
    t_last_judges_loud: assert (!$past(fr_endEvt) || io_fault);
    // 거절된 조각의 표시는 접수되지 않는다 — last 래치 상승의 유일한
    // 원천은 「수락 조각이 나른 표시」다.
    t_last_src_0: assert (!(ctx_0_last && !$past(ctx_0_last)) || $past(fr_accept && fr_hit_0 && io_frag_head_last));
    t_last_src_1: assert (!(ctx_1_last && !$past(ctx_1_last)) || $past(fr_accept && fr_hit_1 && io_frag_head_last));
    t_last_src_2: assert (!(ctx_2_last && !$past(ctx_2_last)) || $past(fr_accept && fr_hit_2 && io_frag_head_last));
    t_last_src_3: assert (!(ctx_3_last && !$past(ctx_3_last)) || $past(fr_accept && fr_hit_3 && io_frag_head_last));

    // Payload.reset_on_deliver — 인도 완결은 그 문맥을 즉시 해방한다
    // (회계 공은 inv_free_clean_* 이 이어받는다: 해방 = 회계 소거 동시).
    t_deliver_frees_0: assert (!$past(io_deliver_fire && dv_grantOh[0]) || !ctx_0_active);
    t_deliver_frees_1: assert (!$past(io_deliver_fire && dv_grantOh[1]) || !ctx_1_active);
    t_deliver_frees_2: assert (!$past(io_deliver_fire && dv_grantOh[2]) || !ctx_2_active);
    t_deliver_frees_3: assert (!$past(io_deliver_fire && dv_grantOh[3]) || !ctx_3_active);

    // Payload.abort_erases — 소거 발화는 맞힌 문맥을 즉시 해방한다.
    t_abort_frees_0: assert (!$past(ab_fire && ab_hit_0) || !ctx_0_active);
    t_abort_frees_1: assert (!$past(ab_fire && ab_hit_1) || !ctx_1_active);
    t_abort_frees_2: assert (!$past(ab_fire && ab_hit_2) || !ctx_2_active);
    t_abort_frees_3: assert (!$past(ab_fire && ab_hit_3) || !ctx_3_active);

    // Payload.abort_leaves_trace — 소거 발화 = 카운트 증가 동시 (포화 8'hff),
    // 발화 없는 사이클(없는 태그 무시 포함)엔 카운트 부동.
    t_ab_cnt_inc: assert (!($past(ab_fire) && $past(io_abortCount) != 8'hff) ||
                          (io_abortCount == ($past(io_abortCount) + 8'h01)));
    t_ab_cnt_sat: assert (!($past(ab_fire) && $past(io_abortCount) == 8'hff) ||
                          (io_abortCount == 8'hff));
    t_ab_cnt_hold: assert ($past(ab_fire) || (io_abortCount == $past(io_abortCount)));

    // Payload.write_atomic — 접수 사이클에 회계가 원자로 진행한다: 다음
    // 상태의 seen 은 그 사이클의 newSeen, 총개수는 effTotal 로 래치.
    // 동시 소거(같은 태그 abort)가 있으면 소거 규율(abort_erases)이
    // 우선한다 — 그 갈래는 t_abort_frees_* + inv_free_clean_* 소관이라
    // 여기서 배제한다 (같은 사이클 인도는 접수와 양립 불가 — 완결 문맥에
    // 새 순번이 없다 — 라 배제 조건이 필요 없다).
    t_wr_atomic_0: assert (!$past(fr_accept && fr_hit_0 && !(ab_fire && ab_hit_0)) ||
                           (ctx_0_seen == $past(fr_newSeen) && ctx_0_totalKnown && ctx_0_total == $past(fr_effTotal)));
    t_wr_atomic_1: assert (!$past(fr_accept && fr_hit_1 && !(ab_fire && ab_hit_1)) ||
                           (ctx_1_seen == $past(fr_newSeen) && ctx_1_totalKnown && ctx_1_total == $past(fr_effTotal)));
    t_wr_atomic_2: assert (!$past(fr_accept && fr_hit_2 && !(ab_fire && ab_hit_2)) ||
                           (ctx_2_seen == $past(fr_newSeen) && ctx_2_totalKnown && ctx_2_total == $past(fr_effTotal)));
    t_wr_atomic_3: assert (!$past(fr_accept && fr_hit_3 && !(ab_fire && ab_hit_3)) ||
                           (ctx_3_seen == $past(fr_newSeen) && ctx_3_totalKnown && ctx_3_total == $past(fr_effTotal)));

    // ══ Payload.base_from_tag — 결속 불변 + 개방 원천 (2차 파도 신설) ═════
    //
    // 이 둘이 이 가드의 본체다. p_wr_base_* 는 MuxOH 문면의 거울이라 「어느
    // 값이 실리는가」만 재는데, 모델이 금지하는 어긋남(구간 시작이 태그와
    // 어긋난다 — Payload.tla:453)의 RTL 형은 **조각이 결속을 갱신하는 것**이다.
    // 그것은 시간축이라야 잡힌다.
    //
    // ① 결속 불변 — 개방 착지가 없는 사이클에 base 는 움직이지 않는다.
    //    조각 수락 경로가 c.base 를 쓰는 구현이면 즉시 반례.
    t_base_stable_0: assert ($past(f_grant_oh[0]) || (ctx_0_base == $past(ctx_0_base)));
    t_base_stable_1: assert ($past(f_grant_oh[1]) || (ctx_1_base == $past(ctx_1_base)));
    t_base_stable_2: assert ($past(f_grant_oh[2]) || (ctx_2_base == $past(ctx_2_base)));
    t_base_stable_3: assert ($past(f_grant_oh[3]) || (ctx_3_base == $past(ctx_3_base)));
    // ② 개방 원천 — 그 유일한 기입의 값은 개시가 준 목적 LBID 다.
    //    ※ 모델 문면 `b = (t-1)*SlotCap`(구간 시작이 *태그의 함수*)의 알맹이는
    //      이 모듈이 재지 않는다 — io.open.base 는 in port 이고 태그→LBID
    //      사상은 디코드 소관이다 (GUARD-MAP 문면 자신이 그 위임을 적는다).
    //      좁은 증명이 넓은 모델 가드를 대신한다는 사실은 props.sby 머리에
    //      명기했다.
    t_base_src_0: assert (!$past(f_grant_oh[0]) || (ctx_0_base == $past(io_open_base)));
    t_base_src_1: assert (!$past(f_grant_oh[1]) || (ctx_1_base == $past(io_open_base)));
    t_base_src_2: assert (!$past(f_grant_oh[2]) || (ctx_2_base == $past(io_open_base)));
    t_base_src_3: assert (!$past(f_grant_oh[3]) || (ctx_3_base == $past(io_open_base)));

    // ══ Payload.capability_check — 회계 불참 (2차 파도 신설) ══════════════
    //
    // 능력 밖 조각은 회계에 흔적을 남기지 않는다. 전건은 다시 독립 참조다.
    // 같은 사이클의 소거·인도는 자기 규율(abort_erases·reset_on_deliver)로
    // 회계를 비우므로 배제한다 — 그 갈래는 t_abort_frees_*·t_deliver_frees_*
    // 소관이다. 개방(f_grant_oh)은 배제하지 **않는다**: 개방은 !active 문맥만
    // 고르고 그 문맥의 회계는 inv_free_clean_* 로 이미 공(空)이라 개방의
    // 0 대입이 부동과 같기 때문이다 — 배제하면 그만큼 약해진다.
    t_capa_no_acct_0: assert (!($past(io_frag_valid && f_capa_ref) &&
                                !$past(ab_fire && ab_hit_0) &&
                                !$past(io_deliver_fire && dv_grantOh[0])) ||
                              (ctx_0_seen == $past(ctx_0_seen) &&
                               ctx_0_last == $past(ctx_0_last) &&
                               ctx_0_totalKnown == $past(ctx_0_totalKnown)));
    t_capa_no_acct_1: assert (!($past(io_frag_valid && f_capa_ref) &&
                                !$past(ab_fire && ab_hit_1) &&
                                !$past(io_deliver_fire && dv_grantOh[1])) ||
                              (ctx_1_seen == $past(ctx_1_seen) &&
                               ctx_1_last == $past(ctx_1_last) &&
                               ctx_1_totalKnown == $past(ctx_1_totalKnown)));
    t_capa_no_acct_2: assert (!($past(io_frag_valid && f_capa_ref) &&
                                !$past(ab_fire && ab_hit_2) &&
                                !$past(io_deliver_fire && dv_grantOh[2])) ||
                              (ctx_2_seen == $past(ctx_2_seen) &&
                               ctx_2_last == $past(ctx_2_last) &&
                               ctx_2_totalKnown == $past(ctx_2_totalKnown)));
    t_capa_no_acct_3: assert (!($past(io_frag_valid && f_capa_ref) &&
                                !$past(ab_fire && ab_hit_3) &&
                                !$past(io_deliver_fire && dv_grantOh[3])) ||
                              (ctx_3_seen == $past(ctx_3_seen) &&
                               ctx_3_last == $past(ctx_3_last) &&
                               ctx_3_totalKnown == $past(ctx_3_totalKnown)));
    // 능력 부재의 관측면 도달 — 독립 참조 전건으로 (t_capa_next_eq 가 쓰는
    // $past(fr_capaEvt) 의 재인용이 아니다: 그 등식은 「set 원천이 capaEvt
    // 뿐」을, 이것은 「capaEvt 가 실제로 능력 밖 도착에서 선다」를 잰다.
    // 둘을 합쳐야 fr_capaEvt 의 정의가 양방향으로 닫힌다).
    //   해제와 발화가 겹쳐도 발화가 이기므로 io_capAbsentClear 를 배제하지
    //   않는다 — 관측을 삼키는 창이 없다는 것이 여기서 함께 재어진다.
    t_capa_absent_loud: assert (!($past(io_frag_valid) && $past(f_capa_ref)) || io_capAbsent);

    // ══ Payload.loud_reject (2차 파도 신설) ══════════════════════════════
    //
    // **지상 진리를 검사 어휘로 적지 않는 것이 요점이다.** 전건은 사유 신호
    // (rejEvt·capaEvt)의 재인용이 아니라 `조각이 왔는데 수락되지 않았다` 하나다.
    // 조각의 처분은 accept 하나뿐이고 제3의 결과(대기·유실)가 없다 —
    // io.frag 에 ready 가 없는 구조가 그것을 보장한다 (Reassembly.scala:174-179).
    // 따라서 「io.frag.valid ∧ ¬accept」가 곧 거절의 지상 진리이며, 어떤 사유도
    // 붙지 않는 *조용한 드롭* 경로가 하나라도 생기면 이 단언이 깨진다.
    //   set 이 clear 를 이기므로(t_fault_next_eq 의 등식 문면) 전건 사이클의
    //   clear 를 배제할 필요가 없다.
    t_loud_frag: assert (!($past(io_frag_valid) && !$past(fr_accept)) ||
                         io_fault || io_capAbsent);

    // 개방 축 — 모델 밖 처분(풀 고갈)을 전건에서 명시적으로 뺀다. 풀 고갈
    // 거절은 fault 가 아니라 granted=False 의 명시적 처분이므로(파일 머리
    // 「어긋난 자리」) 빼지 않으면 *거짓 반례*가 난다. 남는 거절 사유는
    // 재시작 충돌 하나뿐이고 그것은 loud 여야 한다.
    t_loud_open: assert (!($past(io_open_valid) && !$past(io_open_granted) &&
                           $past(op_freeAny)) || io_fault);
  end

  // ── cover 증인 — 공허 아님의 증거 (소거 축, 2026-08-25 신설) ────────────
  //
  // 위 소거 단언은 전부 등식 또는 함의라 「소거가 한 번도 일어나지 않는
  // 세계」에서 자명하게 선다 — p_abort_clears_slots 는 0 == 0 이고,
  // p_clr_base_* 는 전건이 거짓이다. 아래 증인이 reset 으로부터 실제로
  // 소거가 발화하고 무효화 명령이 나가는 궤적을 보인다.
  //   ※ sby 의 cover 모드는 chformal -assert -remove 로 단언을 스스로
  //     떼어낸다. 증인이 적법 궤적 위에 있다는 것은 bmc 태스크가 보증한다.
  // 증인은 cover 태스크에서만 컴파일한다 (-DREASM_COVER) — bmc/prove 모델을
  // 종전과 한 비트도 다르지 않게 유지하기 위한 규율이다 (XlateStore 선례).
`ifdef REASM_COVER
  // 각 줄의 `←` 오른쪽이 **그 증인이 살리는 대상**이다: `<Model>.<guard>` 는
  // 이 태스크의 `# PROVES:` 앵커, 소문자 식별자는 이 하네스의 단언 라벨.
  // 줄번호로 매지 않는다. scripts/lint_witness_map.py 가 참조 실재성만 재고
  // 「그 궤적이 정말 그 전건을 세우는가」는 재지 못한다.
  //
  // W1 ← Payload.abort_erases · Payload.abort_leaves_trace ·
  //      Payload.abort_not_fault · p_ab_fire_def · t_ab_cnt_inc · t_abort_frees_0
  //      소거가 실제로 발화한다 (Payload.tla Witness_NoAbort 의 RTL 대응).
  //      이것 없이는 소거 단언 전부가 공허하다.
  always @(posedge clk) if (f_step) w1_abort_fire: cover (ab_fire);

  // W2 ← Payload.abort_clears_window · p_abort_clears_slots · p_clr_needs_hit ·
  //      p_clr_base_0 — 그 발화가 구간 무효화 명령을 실제로 낸다 (결정 B 의
  //      실물이 도달한다 — p_abort_clears_slots 가 0 == 0 이 아니다).
  always @(posedge clk) if (f_step) w2_clr_cmd: cover (io_clr_valid);

  // W3 ← Payload.abort_erases · Payload.abort_clears_window
  //      *미완* 문맥의 소거 — E.12 가 존재하는 이유 그 자체다 (표시 유실
  //      문맥이 드레인을 막지 않게 하는 수단). 완성 문맥만 소거되는 세계면
  //      이 표면은 인도의 중복일 뿐이다.
  always @(posedge clk)
    if (f_step) w3_abort_incomplete: cover (ab_fire && ((ab_hit_0 && !ctx_0_last) || (ab_hit_1 && !ctx_1_last) ||
                                   (ab_hit_2 && !ctx_2_last) || (ab_hit_3 && !ctx_3_last)));

  // W4 ← Payload.abort_erases · Payload.key_is_tag · inv_free_clean_0
  //      *회계가 실린* 문맥의 소거: 비울 것이 실제로 있는 상태에서 소거가
  //      난다 (seen 이 0 이 아닌 문맥). 빈 문맥만 소거되면 「비운다」가
  //      무동작과 구별되지 않는다.
  always @(posedge clk)
    if (f_step) w4_abort_loaded: cover (ab_fire && ((ab_hit_0 && (ctx_0_seen != 16'h0)) ||
                                   (ab_hit_1 && (ctx_1_seen != 16'h0)) ||
                                   (ab_hit_2 && (ctx_2_seen != 16'h0)) ||
                                   (ab_hit_3 && (ctx_3_seen != 16'h0))));

  // W5 ← Payload.abort_leaves_trace · p_ab_fire_def · t_ab_cnt_hold
  //      없는 태그의 소거 기입 (E.12 3항의 무시 갈래가 실재한다).
  always @(posedge clk) if (f_step) w5_abort_miss: cover (io_abort_valid && !ab_hitAny);

  // ── 증인 — base_from_tag 축 (2차 파도) ─────────────────────────────────
  //
  // p_wr_base_* 는 전건이 거짓이면(기입이 없으면) 자명하고, base 가 늘 같은
  // 값인 세계에서는 등식이 무엇도 가르지 않는다. 아래 셋이 그 둘을 막는다.

  // W6 ← Payload.base_from_tag · Payload.write_atomic · p_wr_base_0 ·
  //      p_wr_atomic_face · t_wr_atomic_0 — 기입이 실제로 나고 결속이 0 이
  //      아니다 (전건 도달 + 「base 는 늘 0」인 축퇴 세계 배제).
  always @(posedge clk) if (f_step) w6_write_nonzero_base: cover (io_wr_valid && (io_wr_base != 8'h00));

  // W7 ← Payload.base_from_tag · Payload.key_is_tag · p_wr_base_0
  //      **서로 다른 결속을 가진 두 활성 문맥**이 공존하는 채로 한쪽에 기입이
  //      난다. 이것이 없으면 p_wr_base_* 는 「어느 문맥을 골라도 답이 같은」
  //      세계에서 통과하고 MuxOH 의 선택이 재어지지 않는다.
  always @(posedge clk)
    if (f_step) w7_two_ctx_distinct_base: cover (io_wr_valid &&
                       ((fr_hit_0 && ctx_1_active && (ctx_1_base != ctx_0_base)) ||
                        (fr_hit_1 && ctx_0_active && (ctx_0_base != ctx_1_base)) ||
                        (fr_hit_2 && ctx_3_active && (ctx_3_base != ctx_2_base)) ||
                        (fr_hit_3 && ctx_2_active && (ctx_2_base != ctx_3_base))));

  // W8 ← Payload.base_from_tag · t_base_src_0 · t_base_stable_0
  //      개방 착지가 실제로 난다, 비0 결속으로 (전건 도달 — 개방이 한 번도
  //      없으면 ①②③ 이 통째로 공허하다).
  always @(posedge clk) if (f_step) w8_open_nonzero_base: cover (op_grant && (io_open_base != 8'h00));

  // ── 증인 — capability_check 축 (2차 파도) ──────────────────────────────

  // W9 ← Payload.capability_check · p_capa_excl_all · p_capa_def
  //      능력 밖 조각이 *활성 문맥에 적중한 채로* 도착한다. 이것 없이는
  //      p_capa_excl_all 이 「능력 밖은 애초에 hit 도 안 난다」로 공허해진다
  //      (전건이 서긴 하나 배제 항들이 다른 이유로 이미 0 인 세계).
  always @(posedge clk) if (f_step) w9_capa_hit: cover (io_frag_valid && fr_capaRej && fr_hitAny);

  // W10 ← Payload.capability_check · t_capa_no_acct_0
  //       그 도착이 회계가 실린 문맥에 난다 (t_capa_no_acct_* 가 「비울 것이
  //       있는」 상태에서 재어진다 — 빈 문맥 부동은 무동작과 구별되지 않는다).
  always @(posedge clk)
    if (f_step) w10_capa_loaded_ctx: cover (io_frag_valid && fr_capaRej &&
                       ((fr_hit_0 && (ctx_0_seen != 16'h0)) ||
                        (fr_hit_1 && (ctx_1_seen != 16'h0)) ||
                        (fr_hit_2 && (ctx_2_seen != 16'h0)) ||
                        (fr_hit_3 && (ctx_3_seen != 16'h0))));

  // ── 증인 — loud_reject 축 (2차 파도) ───────────────────────────────────
  //
  // 「크게 알린다」가 재어지려면 사유별로 (a) 거절이 실제로 일어나고 (b) 그
  // 다음 사이클에 해당 sticky 가 **처음** 선다는 궤적이 있어야 한다. 이미 서
  // 있는 sticky 위를 지나가는 통과는 아무것도 증명하지 않는다.

  // W11 ← Payload.loud_reject · t_loud_frag                (스트레이)
  // W12 ← Payload.loud_reject · Payload.cap_check · p_cap_window · t_loud_frag
  //                                                          (선언 자기모순)
  // W13 ← Payload.loud_reject · Payload.cap_check · p_cap_off · t_loud_frag
  //                                                          (구간 밖)
  // W14 ← Payload.loud_reject · Payload.no_dup_seq · p_no_dup_accept ·
  //       t_loud_frag                                        (중복)
  // 사유별로 갈라 두는 것이 알맹이다 — 한 사유만 도달하면 나머지 셋에서
  // 「크게 알린다」는 한 번도 재어지지 않는다.
  always @(posedge clk)
    if (f_step) w11_loud_stray: cover ($past(io_frag_valid && fr_strayRej) && io_fault && !$past(io_fault));
  always @(posedge clk)
    if (f_step) w12_loud_totbad: cover ($past(io_frag_valid && fr_totBad) && io_fault && !$past(io_fault));
  always @(posedge clk)
    if (f_step) w13_loud_over: cover ($past(io_frag_valid && fr_overRej) && io_fault && !$past(io_fault));
  always @(posedge clk)
    if (f_step) w14_loud_dup: cover ($past(io_frag_valid && fr_dupRej) && io_fault && !$past(io_fault));

  // W15 ← Payload.capability_not_fault · Payload.capability_check ·
  //       t_capa_absent_loud · t_capa_next_eq
  //       능력 부재: 다른 채널(capAbsent)의 첫 상승.
  always @(posedge clk)
    if (f_step) w15_capabsent_rise: cover ($past(io_frag_valid && fr_capaRej) && io_capAbsent && !$past(io_capAbsent));

  // W16 ← Payload.no_restart · Payload.loud_reject · p_no_restart_evt ·
  //       p_no_restart_grant · t_no_restart_loud
  //       재시작 충돌 (개방 축의 loud 사유).
  always @(posedge clk)
    if (f_step) w16_loud_restart: cover ($past(op_clashEvt) && io_fault && !$past(io_fault));

  // W17 ← Payload.loud_reject · t_loud_open
  //       **모델 밖 예외가 실재한다**: 풀 고갈 개방 거절. t_loud_open 이
  //       전건에서 빼는 그 갈래가 도달 불가라면 그 배제는 장식이고, 반대로
  //       도달 가능하면 배제하지 않았을 때 거짓 반례가 났을 것이다.
  always @(posedge clk)
    if (f_step) w17_pool_exhausted: cover (io_open_valid && !io_open_granted && !op_freeAny);

  // W18 ← Payload.loud_reject · Payload.abort_not_fault · t_fault_next_eq
  //       sticky 가 실제로 내려갈 수 있다 (명시적 해제). io_fault 가 영구
  //       1 인 세계라면 t_loud_frag·t_loud_open 이 자명하게 선다 — 그 축퇴를
  //       배제하는 증인이다.
  always @(posedge clk) if (f_step) w18_fault_clear: cover ($past(io_fault) && !io_fault);

  // ── 증인 — last_judges · reset_on_deliver 축 (2026-09-24 이월 B) ──────────
  //
  // 4차 파도가 「면제가 아니라 미결 보고」로 남긴 두 앵커다 (lint_witness_map
  // `_ANCHOR_UNWITNESSED` 의 종전 두 항목). p_last_judges_def 는 무전건 등식이라
  // fr_endEvt 가 영영 0 이면 0 == 0 이고, t_last_judges_loud · t_last_src_* ·
  // t_deliver_frees_* 는 전건이 죽으면 자명하다. 아래 셋이 그 전건을 reset
  // 기점에서 실제로 세운다 — 전부 개방 1회 + 조각 1회 안에 닿는 얕은 궤적이다
  // (props.sby 깊이 주석의 실측 표).

  // W19 ← Payload.last_judges · p_last_judges_def · t_last_judges_loud
  //       불완전 종료(표시가 왔는데 수신 집합 != 전량 마스크)가 실제로 서고
  //       그 다음 사이클 fault 가 **처음** 선다 — W11~W16 의 「첫 상승」 규율
  //       그대로다 (이미 서 있는 sticky 위를 지나가는 통과는 아무것도 증명하지
  //       않는다). 전건이 `$past(fr_endEvt)` 이므로 fr_endEvt 도달 자체를
  //       함의한다 — 미결 보고의 처방 후보 `cover (fr_endEvt)` 를 포섭한다.
  always @(posedge clk)
    if (f_step) w19_end_incomplete_loud: cover ($past(fr_endEvt) && io_fault && !$past(io_fault));

  // W20 ← Payload.last_judges · t_last_src_0
  //       last 래치가 실제로 상승한다 (t_last_src_* 의 전건 — 표시 접수가 한
  //       번도 없는 세계에서는 「상승 원천은 수락 조각의 표시뿐」이 공허하다).
  always @(posedge clk)
    if (f_step) w20_last_rise: cover (ctx_0_last && !$past(ctx_0_last));

  // W21 ← Payload.reset_on_deliver · Payload.last_judges · t_deliver_frees_0 ·
  //       inv_free_clean_0
  //       인도 완결이 실제로 난다 (t_deliver_frees_* 넷의 전건 — 종전엔 통째로
  //       미측정이었다). dv_done 은 last ∧ totalKnown ∧ seen == 전량 마스크를
  //       요구하므로 이 궤적은 동시에 last_judges 의 *완전* 종료 갈래 — 표시가
  //       왔는데 endEvt 가 서지 **않는** 쪽 — 의 실재이기도 하다 (W19 가 불완전
  //       갈래, 이것이 완전 갈래: 둘이 있어야 p_last_judges_def 의 등식이 양쪽
  //       값을 다 본다). 그리고 인도 직전 seen 은 결코 0 이 아니므로
  //       inv_free_clean_0 이 「비울 것이 있는」 상태에서 재어진다.
  always @(posedge clk)
    if (f_step) w21_deliver_frees: cover ($past(io_deliver_fire && dv_grantOh[0]));

  // ── 증인 — key_drops_side 축 (태그 코덱 전파 파도, 2026-09-26) ─────────────

  // W22 ← Payload.key_drops_side · p_key_hit_0
  //       poison 또는 trace 만 다른 조각이 열린 문맥에 실제로 적중한다 (Payload.tla
  //       Witness_NoSideFragHit 의 RTL 대응). 이것 없이는 p_key_hit_* 의 「두 비트를
  //       보지 않는다」 방향이 두 비트가 늘 같은 세계에서 공허하다.
  always @(posedge clk)
    if (f_step) w22_side_frag_hit: cover (io_frag_valid && fr_hit_0 && ((io_frag_head_tag_trace != ctx_0_tag_trace) || (io_frag_head_tag_poison != ctx_0_tag_poison)));

  // W23 ← Payload.key_drops_side · Payload.abort_erases · p_key_abhit_0
  //       두 비트를 0 으로 싣는 소거(ABORT_TAG1 [27:26] = 0 강제 — 조립이 싣는 유일한
  //       값)가 trace 또는 poison 이 선 문맥을 실제로 지운다 (Witness_NoSideAbortHit ·
  //       D2b 의 호스트 가시 귀결 「trace 든 문맥은 소거할 수 없다」의 반대편).
  always @(posedge clk)
    if (f_step) w23_side_abort_hit: cover (ab_fire && ab_hit_0 && !io_abort_tag_trace && !io_abort_tag_poison && (ctx_0_tag_trace || ctx_0_tag_poison));

  // W24 ← Payload.key_drops_side · Payload.no_restart · p_key_clash
  //       trace 또는 poison 만 다른 재개시가 진행 중 문맥과 충돌해 거절된다 — 개시의
  //       재시작 판정도 같은 키 범위다 (04-ext-payload 4.3 「셋에 같은 범위로」).
  always @(posedge clk)
    if (f_step) w24_side_open_clash: cover (io_open_valid && !io_open_granted && ctx_0_active && k_op_0 && ((io_open_tag_trace != ctx_0_tag_trace) || (io_open_tag_poison != ctx_0_tag_poison)));
`endif // REASM_COVER

endmodule

// 대상 안에 부착 — 내부 신호는 대상 스코프에서 이름으로 결선된다.
bind Reassembly Reassembly_props u_props (
  .clk(clk), .reset(reset),
  .io_open_valid(io_open_valid), .io_open_base(io_open_base),
  .io_open_granted(io_open_granted),
  .io_open_tag_wave(io_open_tag_wave), .io_open_tag_epoch(io_open_tag_epoch), .io_open_tag_poison(io_open_tag_poison), .io_open_tag_trace(io_open_tag_trace),
  .io_open_tag_lnid(io_open_tag_lnid), .io_open_tag_precision(io_open_tag_precision), .io_open_tag_dim(io_open_tag_dim),
  .io_frag_head_tag_wave(io_frag_head_tag_wave), .io_frag_head_tag_epoch(io_frag_head_tag_epoch), .io_frag_head_tag_poison(io_frag_head_tag_poison), .io_frag_head_tag_trace(io_frag_head_tag_trace),
  .io_frag_head_tag_lnid(io_frag_head_tag_lnid), .io_frag_head_tag_precision(io_frag_head_tag_precision), .io_frag_head_tag_dim(io_frag_head_tag_dim),
  .io_abort_tag_wave(io_abort_tag_wave), .io_abort_tag_epoch(io_abort_tag_epoch), .io_abort_tag_poison(io_abort_tag_poison), .io_abort_tag_trace(io_abort_tag_trace),
  .io_abort_tag_lnid(io_abort_tag_lnid), .io_abort_tag_precision(io_abort_tag_precision), .io_abort_tag_dim(io_abort_tag_dim),
  .io_frag_valid(io_frag_valid), .io_frag_head_seq(io_frag_head_seq),
  .io_frag_head_total(io_frag_head_total), .io_frag_head_last(io_frag_head_last),
  .io_wr_valid(io_wr_valid), .io_wr_base(io_wr_base), .io_wr_off(io_wr_off),
  .io_deliver_valid(io_deliver_valid), .io_deliver_fire(io_deliver_fire),
  .dv_grantOh(dv_grantOh),
  .io_abort_valid(io_abort_valid), .io_abortCount(io_abortCount),
  .io_clr_valid(io_clr_valid), .io_clr_base(io_clr_base),
  .ab_fire(ab_fire), .ab_hitAny(ab_hitAny),
  .ab_hit_0(ab_hit_0), .ab_hit_1(ab_hit_1), .ab_hit_2(ab_hit_2), .ab_hit_3(ab_hit_3),
  .io_fault(io_fault), .io_faultClear(io_faultClear),
  .io_capAbsent(io_capAbsent), .io_capAbsentClear(io_capAbsentClear),
  .`WT_STICKY_SET_FAULT(`WT_STICKY_SET_FAULT),
  .fr_hit_0(fr_hit_0), .fr_hit_1(fr_hit_1), .fr_hit_2(fr_hit_2), .fr_hit_3(fr_hit_3),
  .fr_hitAny(fr_hitAny),
  .fr_accept(fr_accept), .fr_capaRej(fr_capaRej), .fr_dupRej(fr_dupRej),
  .fr_strayRej(fr_strayRej), .fr_totBad(fr_totBad), .fr_overRej(fr_overRej),
  .fr_cKnown(fr_cKnown), .fr_cSeen(fr_cSeen), .fr_ohSeq(fr_ohSeq),
  .fr_newSeen(fr_newSeen), .fr_effTotal(fr_effTotal), .fr_cBase(fr_cBase),
  .fr_rejEvt(fr_rejEvt), .fr_endEvt(fr_endEvt), .fr_capaEvt(fr_capaEvt),
  ._zz_fr_endBad(_zz_fr_endBad),
  .op_clash(op_clash), .op_clashEvt(op_clashEvt), .op_grant(op_grant),
  .op_freeAny(op_freeAny), .op_freeOh(op_freeOh),
  .ctx_0_active(ctx_0_active), .ctx_0_tag_wave(ctx_0_tag_wave),
  .ctx_0_tag_epoch(ctx_0_tag_epoch), .ctx_0_tag_poison(ctx_0_tag_poison),
  .ctx_0_tag_trace(ctx_0_tag_trace), .ctx_0_tag_lnid(ctx_0_tag_lnid),
  .ctx_0_tag_precision(ctx_0_tag_precision), .ctx_0_tag_dim(ctx_0_tag_dim),
  .ctx_0_base(ctx_0_base),
  .ctx_0_total(ctx_0_total), .ctx_0_totalKnown(ctx_0_totalKnown),
  .ctx_0_seen(ctx_0_seen), .ctx_0_last(ctx_0_last),
  .ctx_1_active(ctx_1_active), .ctx_1_tag_wave(ctx_1_tag_wave),
  .ctx_1_tag_epoch(ctx_1_tag_epoch), .ctx_1_tag_poison(ctx_1_tag_poison),
  .ctx_1_tag_trace(ctx_1_tag_trace), .ctx_1_tag_lnid(ctx_1_tag_lnid),
  .ctx_1_tag_precision(ctx_1_tag_precision), .ctx_1_tag_dim(ctx_1_tag_dim),
  .ctx_1_base(ctx_1_base),
  .ctx_1_total(ctx_1_total), .ctx_1_totalKnown(ctx_1_totalKnown),
  .ctx_1_seen(ctx_1_seen), .ctx_1_last(ctx_1_last),
  .ctx_2_active(ctx_2_active), .ctx_2_tag_wave(ctx_2_tag_wave),
  .ctx_2_tag_epoch(ctx_2_tag_epoch), .ctx_2_tag_poison(ctx_2_tag_poison),
  .ctx_2_tag_trace(ctx_2_tag_trace), .ctx_2_tag_lnid(ctx_2_tag_lnid),
  .ctx_2_tag_precision(ctx_2_tag_precision), .ctx_2_tag_dim(ctx_2_tag_dim),
  .ctx_2_base(ctx_2_base),
  .ctx_2_total(ctx_2_total), .ctx_2_totalKnown(ctx_2_totalKnown),
  .ctx_2_seen(ctx_2_seen), .ctx_2_last(ctx_2_last),
  .ctx_3_active(ctx_3_active), .ctx_3_tag_wave(ctx_3_tag_wave),
  .ctx_3_tag_epoch(ctx_3_tag_epoch), .ctx_3_tag_poison(ctx_3_tag_poison),
  .ctx_3_tag_trace(ctx_3_tag_trace), .ctx_3_tag_lnid(ctx_3_tag_lnid),
  .ctx_3_tag_precision(ctx_3_tag_precision), .ctx_3_tag_dim(ctx_3_tag_dim),
  .ctx_3_base(ctx_3_base),
  .ctx_3_total(ctx_3_total), .ctx_3_totalKnown(ctx_3_totalKnown),
  .ctx_3_seen(ctx_3_seen), .ctx_3_last(ctx_3_last)
);
