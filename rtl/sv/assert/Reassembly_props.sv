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
// (호스트 ABI 결정 4·5 파도가 Common.scala 를 늘려 l141 → l259).
//
// *크게 실패한 것은 다행이다.* 그리고 그 태스크를 돌리게 한 것은 사람의 기억이
// 아니라 scripts/sby_impact.py 역색인이었다 — 그 도구가 존재하는 이유가 이
// 부류다. 아래 매크로가 다음에 밀릴 때 고칠 자리를 한 줄로 만든다.
//
// (근본 수리는 그 조건에 안정된 이름을 주는 것이고, 그것은 StickyFault 를 쓰는
//  전 모듈의 생성물 이름을 움직이므로 별 파도다 — rtl/README.md 등재.)
`define WT_STICKY_SET_FAULT when_Common_l259
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
  input logic        io_open_granted,
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
  // sticky 관측면
  input logic        io_fault,
  input logic        io_faultClear,
  input logic        io_capAbsent,
  input logic        io_capAbsentClear,
  input logic        `WT_STICKY_SET_FAULT,
  // 조각 접수 판정 내부
  input logic        fr_hit_0, fr_hit_1, fr_hit_2, fr_hit_3,
  input logic        fr_accept,
  input logic        fr_capaRej,
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
  // 문맥 풀 (nCtxs=4)
  input logic        ctx_0_active,
  input logic [31:0] ctx_0_tag_wave,
  input logic [15:0] ctx_0_tag_thread,
  input logic [15:0] ctx_0_tag_lnid,
  input logic [7:0]  ctx_0_tag_precision,
  input logic [7:0]  ctx_0_tag_dim,
  input logic [7:0]  ctx_0_total,
  input logic        ctx_0_totalKnown,
  input logic [15:0] ctx_0_seen,
  input logic        ctx_0_last,
  input logic        ctx_1_active,
  input logic [31:0] ctx_1_tag_wave,
  input logic [15:0] ctx_1_tag_thread,
  input logic [15:0] ctx_1_tag_lnid,
  input logic [7:0]  ctx_1_tag_precision,
  input logic [7:0]  ctx_1_tag_dim,
  input logic [7:0]  ctx_1_total,
  input logic        ctx_1_totalKnown,
  input logic [15:0] ctx_1_seen,
  input logic        ctx_1_last,
  input logic        ctx_2_active,
  input logic [31:0] ctx_2_tag_wave,
  input logic [15:0] ctx_2_tag_thread,
  input logic [15:0] ctx_2_tag_lnid,
  input logic [7:0]  ctx_2_tag_precision,
  input logic [7:0]  ctx_2_tag_dim,
  input logic [7:0]  ctx_2_total,
  input logic        ctx_2_totalKnown,
  input logic [15:0] ctx_2_seen,
  input logic        ctx_2_last,
  input logic        ctx_3_active,
  input logic [31:0] ctx_3_tag_wave,
  input logic [15:0] ctx_3_tag_thread,
  input logic [15:0] ctx_3_tag_lnid,
  input logic [7:0]  ctx_3_tag_precision,
  input logic [7:0]  ctx_3_tag_dim,
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

  // 태그 전량 비교 (번들 통비교 — key_is_tag 의 문면)
  wire tag_eq_01 = (ctx_0_tag_wave == ctx_1_tag_wave) && (ctx_0_tag_thread == ctx_1_tag_thread)
                && (ctx_0_tag_lnid == ctx_1_tag_lnid) && (ctx_0_tag_precision == ctx_1_tag_precision)
                && (ctx_0_tag_dim == ctx_1_tag_dim);
  wire tag_eq_02 = (ctx_0_tag_wave == ctx_2_tag_wave) && (ctx_0_tag_thread == ctx_2_tag_thread)
                && (ctx_0_tag_lnid == ctx_2_tag_lnid) && (ctx_0_tag_precision == ctx_2_tag_precision)
                && (ctx_0_tag_dim == ctx_2_tag_dim);
  wire tag_eq_03 = (ctx_0_tag_wave == ctx_3_tag_wave) && (ctx_0_tag_thread == ctx_3_tag_thread)
                && (ctx_0_tag_lnid == ctx_3_tag_lnid) && (ctx_0_tag_precision == ctx_3_tag_precision)
                && (ctx_0_tag_dim == ctx_3_tag_dim);
  wire tag_eq_12 = (ctx_1_tag_wave == ctx_2_tag_wave) && (ctx_1_tag_thread == ctx_2_tag_thread)
                && (ctx_1_tag_lnid == ctx_2_tag_lnid) && (ctx_1_tag_precision == ctx_2_tag_precision)
                && (ctx_1_tag_dim == ctx_2_tag_dim);
  wire tag_eq_13 = (ctx_1_tag_wave == ctx_3_tag_wave) && (ctx_1_tag_thread == ctx_3_tag_thread)
                && (ctx_1_tag_lnid == ctx_3_tag_lnid) && (ctx_1_tag_precision == ctx_3_tag_precision)
                && (ctx_1_tag_dim == ctx_3_tag_dim);
  wire tag_eq_23 = (ctx_2_tag_wave == ctx_3_tag_wave) && (ctx_2_tag_thread == ctx_3_tag_thread)
                && (ctx_2_tag_lnid == ctx_3_tag_lnid) && (ctx_2_tag_precision == ctx_3_tag_precision)
                && (ctx_2_tag_dim == ctx_3_tag_dim);

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

    // Payload.write_atomic — 기입 면 발화 == 접수 판정 (같은 사이클·같은
    // 게이트, 사이를 가르는 파이프 단 없음).
    p_wr_atomic_face: assert (io_wr_valid == fr_accept);
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
  end

endmodule

// 대상 안에 부착 — 내부 신호는 대상 스코프에서 이름으로 결선된다.
bind Reassembly Reassembly_props u_props (
  .clk(clk), .reset(reset),
  .io_open_valid(io_open_valid), .io_open_granted(io_open_granted),
  .io_frag_valid(io_frag_valid), .io_frag_head_seq(io_frag_head_seq),
  .io_frag_head_total(io_frag_head_total), .io_frag_head_last(io_frag_head_last),
  .io_wr_valid(io_wr_valid), .io_wr_base(io_wr_base), .io_wr_off(io_wr_off),
  .io_deliver_valid(io_deliver_valid), .io_deliver_fire(io_deliver_fire),
  .dv_grantOh(dv_grantOh),
  .io_abort_valid(io_abort_valid), .io_abortCount(io_abortCount),
  .ab_fire(ab_fire), .ab_hitAny(ab_hitAny),
  .ab_hit_0(ab_hit_0), .ab_hit_1(ab_hit_1), .ab_hit_2(ab_hit_2), .ab_hit_3(ab_hit_3),
  .io_fault(io_fault), .io_faultClear(io_faultClear),
  .io_capAbsent(io_capAbsent), .io_capAbsentClear(io_capAbsentClear),
  .`WT_STICKY_SET_FAULT(`WT_STICKY_SET_FAULT),
  .fr_hit_0(fr_hit_0), .fr_hit_1(fr_hit_1), .fr_hit_2(fr_hit_2), .fr_hit_3(fr_hit_3),
  .fr_accept(fr_accept), .fr_capaRej(fr_capaRej), .fr_dupRej(fr_dupRej),
  .fr_cKnown(fr_cKnown), .fr_cSeen(fr_cSeen), .fr_ohSeq(fr_ohSeq),
  .fr_newSeen(fr_newSeen), .fr_effTotal(fr_effTotal), .fr_cBase(fr_cBase),
  .fr_rejEvt(fr_rejEvt), .fr_endEvt(fr_endEvt), .fr_capaEvt(fr_capaEvt),
  ._zz_fr_endBad(_zz_fr_endBad),
  .op_clash(op_clash), .op_clashEvt(op_clashEvt), .op_grant(op_grant),
  .ctx_0_active(ctx_0_active), .ctx_0_tag_wave(ctx_0_tag_wave),
  .ctx_0_tag_thread(ctx_0_tag_thread), .ctx_0_tag_lnid(ctx_0_tag_lnid),
  .ctx_0_tag_precision(ctx_0_tag_precision), .ctx_0_tag_dim(ctx_0_tag_dim),
  .ctx_0_total(ctx_0_total), .ctx_0_totalKnown(ctx_0_totalKnown),
  .ctx_0_seen(ctx_0_seen), .ctx_0_last(ctx_0_last),
  .ctx_1_active(ctx_1_active), .ctx_1_tag_wave(ctx_1_tag_wave),
  .ctx_1_tag_thread(ctx_1_tag_thread), .ctx_1_tag_lnid(ctx_1_tag_lnid),
  .ctx_1_tag_precision(ctx_1_tag_precision), .ctx_1_tag_dim(ctx_1_tag_dim),
  .ctx_1_total(ctx_1_total), .ctx_1_totalKnown(ctx_1_totalKnown),
  .ctx_1_seen(ctx_1_seen), .ctx_1_last(ctx_1_last),
  .ctx_2_active(ctx_2_active), .ctx_2_tag_wave(ctx_2_tag_wave),
  .ctx_2_tag_thread(ctx_2_tag_thread), .ctx_2_tag_lnid(ctx_2_tag_lnid),
  .ctx_2_tag_precision(ctx_2_tag_precision), .ctx_2_tag_dim(ctx_2_tag_dim),
  .ctx_2_total(ctx_2_total), .ctx_2_totalKnown(ctx_2_totalKnown),
  .ctx_2_seen(ctx_2_seen), .ctx_2_last(ctx_2_last),
  .ctx_3_active(ctx_3_active), .ctx_3_tag_wave(ctx_3_tag_wave),
  .ctx_3_tag_thread(ctx_3_tag_thread), .ctx_3_tag_lnid(ctx_3_tag_lnid),
  .ctx_3_tag_precision(ctx_3_tag_precision), .ctx_3_tag_dim(ctx_3_tag_dim),
  .ctx_3_total(ctx_3_total), .ctx_3_totalKnown(ctx_3_totalKnown),
  .ctx_3_seen(ctx_3_seen), .ctx_3_last(ctx_3_last)
);
