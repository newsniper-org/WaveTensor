// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// RouteJudge 후-formal 하네스 — Route.tla 가드의 RTL 재검사 (§6.3).
//
// 대상: rtl/generated/RouteJudge.sv (커밋본 그대로 — 재생성하지 않는다)
// 실행: rtl/formal/sby/RouteJudge/route_judge.sby (yosys+sby, smtbmc z3)
//
// ## 부착 방식 — bind 대신 expose+인스턴스 (실측 근거)
//
// 계획은 bind 부착이었으나, 컨테이너의 yosys 0.66 자유 프론트엔드는 SV
// `bind` 구문을 *조용히* 버린다 — 파스는 통과하고 인스턴스는 생성되지
// 않는다 (2026-08-24 컨테이너 실측: 최소 예제에서 bind 된 모듈이
// "Removing unused module" 로 사라지고 $check 셀 0개). 그래서 이 하네스는
// sby [script] 의 `expose` 로 대상 내부 레지스터(viewValid_*, viewName_*,
// bankPresent)를 출력 포트로 승격한 뒤 대상을 직접 인스턴스한다.
// 「수기 SV 는 검증 하네스 용도로만」이라는 규약의 정신은 그대로다 —
// 대상 RTL 은 한 글자도 손대지 않는다.
//
// ## 시간축 유의
//
// RouteJudge.scala 머리 주석은 tokIn 을 valid 스트로브(토큰 하나 = valid
// 한 사이클)로 전제하지만, 아래 속성들은 그 전제 *없이* 성립하는 형태로
// 세웠다 — 발화가 사이클당 최대 1비트이고 제시 사이클에만 선다는 것을
// 재므로, 여러 사이클 제시는 여러 제시로 센다. Route.tla 가 미덮임으로
// 남긴 시간축(재제시·해제 겹침)이 정확히 이 방식으로 덮인다. 토큰 입력에
// assume 은 없다.
//
// ## SVA 문법 유의
//
// yosys 자유 프론트엔드는 temporal SVA(|=>, ##) 를 지원하지 않는다 —
// 전부 즉시 assert + $past 로 옮겼다. 각 속성 주석에 원 가드를 적는다.

`timescale 1ns/1ps

module RouteJudge_props (
  input wire        clk,
  input wire        reset,
  // ── 자유 입력 — 환경 제약 없음 (assume 은 reset 프로토콜 하나뿐) ──
  input wire        tok_valid,
  input wire [31:0] tok_wave,
  input wire [3:0]  tok_epoch,
  input wire        tok_poison,
  input wire        tok_trace,
  input wire [15:0] tok_lnid,
  input wire [7:0]  tok_precision,
  input wire [7:0]  tok_dim,
  input wire [7:0]  tok_lbid,
  input wire [3:0]  tok_srcKind,
  input wire        vw_valid,
  input wire [3:0]  vw_idx,
  input wire        vw_en,
  input wire [15:0] vw_lnid,
  input wire        bw_valid,
  input wire [7:0]  bw_lbid,
  input wire        bw_mapped,
  input wire        fault_clear
);

  // ── 대상 출력 + expose 로 승격된 내부 상태 ──────────────────────────
  wire        out_valid;
  wire [31:0] out_wave;
  wire [3:0]  out_epoch;
  wire        out_poison;
  wire        out_trace;
  wire [15:0] out_lnid;
  wire [7:0]  out_precision;
  wire [7:0]  out_dim;
  wire [7:0]  out_lbid;
  wire [3:0]  out_srcKind;
  wire        o_fault;
  wire        o_fire;
  wire        vv0, vv1, vv2, vv3, vv4, vv5, vv6, vv7;
  wire        vv8, vv9, vv10, vv11, vv12, vv13, vv14, vv15;
  wire [15:0] vn0, vn1, vn2, vn3, vn4, vn5, vn6, vn7;
  wire [15:0] vn8, vn9, vn10, vn11, vn12, vn13, vn14, vn15;
  wire [255:0] bank;

  RouteJudge dut (
    .io_tokIn_valid(tok_valid),
    .io_tokIn_payload_tag_wave(tok_wave),
    .io_tokIn_payload_tag_epoch(tok_epoch),
    .io_tokIn_payload_tag_poison(tok_poison),
    .io_tokIn_payload_tag_trace(tok_trace),
    .io_tokIn_payload_tag_lnid(tok_lnid),
    .io_tokIn_payload_tag_precision(tok_precision),
    .io_tokIn_payload_tag_dim(tok_dim),
    .io_tokIn_payload_lbid(tok_lbid),
    .io_tokIn_payload_srcKind(tok_srcKind),
    .io_tokOut_valid(out_valid),
    .io_tokOut_payload_tag_wave(out_wave),
    .io_tokOut_payload_tag_epoch(out_epoch),
    .io_tokOut_payload_tag_poison(out_poison),
    .io_tokOut_payload_tag_trace(out_trace),
    .io_tokOut_payload_tag_lnid(out_lnid),
    .io_tokOut_payload_tag_precision(out_precision),
    .io_tokOut_payload_tag_dim(out_dim),
    .io_tokOut_payload_lbid(out_lbid),
    .io_tokOut_payload_srcKind(out_srcKind),
    .io_viewWr_valid(vw_valid),
    .io_viewWr_idx(vw_idx),
    .io_viewWr_en(vw_en),
    .io_viewWr_lnid(vw_lnid),
    .io_bankWr_valid(bw_valid),
    .io_bankWr_lbid(bw_lbid),
    .io_bankWr_mapped(bw_mapped),
    .io_fault(o_fault),
    .io_faultClear(fault_clear),
    .io_faultFire(o_fire),
    .clk(clk),
    .reset(reset),
    // expose 승격 포트 (sby [script] 의 expose 가 만든다)
    .viewValid_0(vv0),  .viewValid_1(vv1),  .viewValid_2(vv2),  .viewValid_3(vv3),
    .viewValid_4(vv4),  .viewValid_5(vv5),  .viewValid_6(vv6),  .viewValid_7(vv7),
    .viewValid_8(vv8),  .viewValid_9(vv9),  .viewValid_10(vv10), .viewValid_11(vv11),
    .viewValid_12(vv12), .viewValid_13(vv13), .viewValid_14(vv14), .viewValid_15(vv15),
    .viewName_0(vn0),  .viewName_1(vn1),  .viewName_2(vn2),  .viewName_3(vn3),
    .viewName_4(vn4),  .viewName_5(vn5),  .viewName_6(vn6),  .viewName_7(vn7),
    .viewName_8(vn8),  .viewName_9(vn9),  .viewName_10(vn10), .viewName_11(vn11),
    .viewName_12(vn12), .viewName_13(vn13), .viewName_14(vn14), .viewName_15(vn15),
    .bankPresent(bank)
  );

  // ── 뷰의 독립 재구성 — 판정 함수를 하네스가 다시 계산한다 ──────────
  wire [15:0]  h_vv = {vv15, vv14, vv13, vv12, vv11, vv10, vv9, vv8,
                       vv7, vv6, vv5, vv4, vv3, vv2, vv1, vv0};
  wire [255:0] h_vn = {vn15, vn14, vn13, vn12, vn11, vn10, vn9, vn8,
                       vn7, vn6, vn5, vn4, vn3, vn2, vn1, vn0};

  integer i;
  reg h_hit;
  always @* begin
    h_hit = 1'b0;
    for (i = 0; i < 16; i = i + 1)
      if (h_vv[i] && h_vn[i*16 +: 16] == tok_lnid) h_hit = 1'b1;
  end
  // 발화 조건 ①·② 를 §1.6.3 문면대로 독립 재계산 (SRC_KIND_RESULT=1)
  wire h_missLnid = !h_hit;
  wire h_missLbid = (tok_srcKind == 4'd1) && !bank[tok_lbid];
  wire h_anyMiss  = h_missLnid || h_missLbid;

  // ── reset 프로토콜 (유일한 환경 assume) ─────────────────────────────
  // assume 근거: 형식 검증의 reset 관례 — 부트 시 reset 1회 인가 후 해제.
  // SpinalHDL 비동기 reset 설계의 표준 모델링이며, GUARD-MAP 의 어느 계약
  // 도 reset 재인가 하의 성질을 주장하지 않는다 (§1.5 는 "reset 직후"
  // 상태만 규정한다).
  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;
  always @* begin
    if (!f_past_valid) assume (reset);
    else               assume (!reset);
  end
  reg past_reset = 1'b1;
  always @(posedge clk) past_reset <= reset;

  always @(posedge clk) begin
    if (!reset) begin
      // ── Route.global_judge — 판정은 (토큰, 자기 뷰, 자기 존재 비트 표)
      //    만의 함수이고, 그 함수는 §1.6.3 의 두 발화 조건 그대로다.
      //    하네스가 뷰에서 독립 재계산한 값과 출력이 등가임을 잰다.
      //    (지점별 비소유 입력의 부재는 IO 목록이 구조로 보증 — 주석 참조)
      p_global_judge: assert (o_fire == (tok_valid && h_anyMiss));

      // ── Route.fault_once — 제시당 발화 <= 1. 발화면은 1비트 신호 하나
      //    뿐이므로(합산 경로 없음 — 구조), 남는 의무는 "제시 없는 사이클
      //    에 발화 없음"이다. 위 등식과 함께 시간축의 「계층당 1회」가 선다.
      p_fault_once: assert (!o_fire || tok_valid);

      // ── Route.scope_independent — 무게이트 전량 통과 (§1.6.3 토큰 전파,
      //    D3). fault 여부가 토큰 흐름에 실리지 않는다. 다른 범위의 상태를
      //    실어 오는 입력이 없다는 나머지 절반은 IO 목록의 구조다.
      p_scope_pass: assert (out_valid == tok_valid
                            && out_wave == tok_wave
                            && out_epoch == tok_epoch && out_poison == tok_poison && out_trace == tok_trace
                            && out_lnid == tok_lnid
                            && out_precision == tok_precision
                            && out_dim == tok_dim
                            && out_lbid == tok_lbid
                            && out_srcKind == tok_srcKind);
    end

    if (f_past_valid && !past_reset && !reset) begin
      // ── Route.loud_fault — sticky 의 정확한 다음 상태 함수:
      //    fault' = fire | (fault & ~clear).  이 등식 하나가
      //    「miss 인데 sticky 안 서는 사이클 없음」(fire 다음 사이클 반드시
      //    선다 — 동시 clear 라도 set 우선)과 「해제 외 하강 없음」을 함께
      //    강제한다 (INV-T3, ISA-6).
      p_loud_fault: assert (o_fault == ($past(o_fire)
                                        || ($past(o_fault) && !$past(fault_clear))));

      // ── Route.view_sync (반영 절반) — 기입은 기입 사이클의 클럭 에지에
      //    즉시 커밋된다 (지연 단 없음): 다음 사이클 관측값이 기입값이다.
      if ($past(vw_valid)) begin
        p_view_sync_wr_v: assert (h_vv[$past(vw_idx)] == $past(vw_en));
        p_view_sync_wr_n: assert (h_vn[$past(vw_idx)*16 +: 16] == $past(vw_lnid));
        // 기입되지 않은 엔트리는 부동 — 갱신 경로가 이 단일 포트뿐이다.
        // (루프 전개라 라벨 불가 — yosys 가 셀 이름 충돌로 거부한다. 실측)
        for (i = 0; i < 16; i = i + 1)
          if (i != $past(vw_idx)) begin
            assert (h_vv[i] == $past(h_vv[i]));
            assert (h_vn[i*16 +: 16] == $past(h_vn[i*16 +: 16]));
          end
      end else begin
        p_view_sync_hold: assert (h_vv == $past(h_vv) && h_vn == $past(h_vn));
      end

      // ── Route.view_sync (존재 비트 표 축) — bankWr 도 같은 규약.
      if ($past(bw_valid)) begin
        p_bank_sync_wr: assert (bank[$past(bw_lbid)] == $past(bw_mapped));
        p_bank_sync_oth: assert ((bank & ~(256'b1 << $past(bw_lbid)))
                                 == ($past(bank) & ~(256'b1 << $past(bw_lbid))));
      end else begin
        p_bank_sync_hold: assert (bank == $past(bank));
      end
    end

    // ── §1.5 — reset 직후 뷰·존재 표 전부 무효, fault 없음. 구성 전에는
    //    어떤 토큰도 배달되지 않고 전부 fault 다 (global_judge 등식과 합쳐
    //    공집합 뷰 → 전 토큰 miss 가 따라 나온다).
    if (f_past_valid && past_reset) begin
      p_reset_empty: assert (h_vv == 16'b0 && bank == 256'b0 && !o_fault);
    end
  end

  // ══ cover 증인 — 공허의 넷째 결에 대한 방벽 (2026-08-26 신설) ════════════
  //
  // 위 단언들은 두 가지 방식으로 *공허하게* 통과할 수 있고, 셀 수 게이트도
  // 항진 검출(`connect \A` 상수)도 그 둘을 잡지 못한다.
  //
  //  (가) **전건 도달 불가** — `if (P) assert (Q)` 에서 P 가 도달 불가능하면
  //       Q 는 검사되지 않는다. 이 하네스에는 P 가 붙은 단언이 여섯 부류다.
  //  (나) **등식의 반쪽 측정** — `assert (lhs == rhs)` 는 형태상 무전건이지만,
  //       rhs 가 한 값만 취하는 세계에서는 등식의 다른 면이 한 번도 재어지지
  //       않는다. 이 하네스의 요체인 `p_global_judge` 가 정확히 그 위험 위에
  //       있다: §1.5 대로 reset 직후 뷰는 공집합이고 존재 표는 전부 0 이라
  //       **구성 전에는 모든 토큰이 fault 다.** 뷰 기입 없이 도는 궤적만으로는
  //       `o_fire == 1` 쪽만 재어지고 「적중·무결 → 배달」(Inv_CleanNeverFaults
  //       의 RTL 상)은 한 번도 서지 않는다.
  //
  // 그래서 아래 증인은 「무엇이 도달 가능한가」를 부류별로 못 박는다. 각
  // 증인 머리에 **어느 단언의 어느 전건(또는 등식의 어느 면)에 대응하는지**를
  // 적는다 — 대응 없는 증인은 셀만 늘리므로 두지 않는다.
  //
  // ## 「구성이 끝난 기계」 단서 (f_cfg)
  //
  // Route.tla 의 증인 절이 적대 검증에서 받은 지적을 그대로 옮긴다: 구성
  // 전에는 전부 fault 이므로 그 상태에서 잡은 fault 증인은 정본 §1.5 가 이미
  // 자명하다고 선언한 것을 되풀이할 뿐이다. 그래서 **미스 증인 셋(W2·W3·W4)은
  // 뷰가 비어 있지 않고 존재 표도 비어 있지 않은 상태**에서만 인정한다
  // (`f_cfg`) — Route.tla 의 `Configured(s)` 술어의 RTL 판이다.
  //
  // ## 시작 상태 (정직 표기)
  //
  // 전부 **reset 기점**이다. 이 설계에는 긴 초기화 소거가 없어(reset 이 뷰와
  // 존재 표를 즉시 0 으로 놓는다) 도달성이 그대로 살아 있다. 실측 도달 스텝은
  // .sby 머리에 적었다. sby 의 cover 모드는 `chformal -assert -remove` 로
  // 단언을 스스로 떼어내지만, 이 증인들이 *적법* 궤적 위에 있다는 것은 bmc
  // 태스크가 따로 보증한다 — 깊이 20 까지 reset 기점 전 궤적에서 단언이 선다.
  //
  // 증인은 cover 태스크에서만 컴파일한다 (-DROUTEJUDGE_COVER). bmc/prove 의
  // 모델을 종전과 한 비트도 다르지 않게 유지하기 위한 규율이다.
`ifdef ROUTEJUDGE_COVER
  // 시간 창 — f_run 은 reset 해제 후(스텝 ≥1), f_seq 는 $past 가 reset 이후
  // 값을 가리키는 구간(스텝 ≥2). 위 단언들의 두 always 블록 조건과 같다.
  wire f_run = f_past_valid && !reset;
  wire f_seq = f_past_valid && !past_reset && !reset;

  // 「구성이 끝난 기계」 — 뷰에 유효 엔트리가 하나라도 있고 존재 표에 사상된
  // LBID 가 하나라도 있다 (Route.tla `Configured(s)` 의 RTL 판).
  wire f_cfg = (h_vv != 16'h0) && (bank != 256'h0);

  // 형제 비소유의 실물 — 유효한데 이름이 이 토큰과 *다른* 뷰 엔트리.
  // 지역 판정 기계였다면 바로 이 엔트리가 fault 를 냈을 자리다.
  integer j;
  reg f_sibling;
  always @* begin
    f_sibling = 1'b0;
    for (j = 0; j < 16; j = j + 1)
      if (h_vv[j] && (h_vn[j*16 +: 16] != tok_lnid)) f_sibling = 1'b1;
  end

  // 중첩 $past 회피용 그림자 — `$past(h_vv[$past(vw_idx)])` 를 쓰지 않는다.
  reg [15:0]  c_vv;
  reg [255:0] c_bank;
  always @(posedge clk) begin
    c_vv   <= h_vv;
    c_bank <= bank;
  end

  // ── 부류 ① 판정 분기 — p_global_judge 등식의 네 면 + p_fault_once 전건 ──

  // W1 ← Route.global_judge · Route.scope_independent · p_global_judge ·
  //      p_scope_pass — ⟨판정 등식의 `o_fire == 0` 면⟩ ⟨전량 통과의 유의미한 면⟩
  //    Route.tla `Witness_NoFault` 의 RTL 판. **두 판정 축을 다 통과하는**
  //    토큰이 fault 없이 배달된다 — 뷰 적중이면서 `src_kind=1` 의 LBID 도
  //    사상돼 있다. srcKind 우회로 얻은 무결이 아니라는 뜻으로 두 조건을
  //    다 요구한다 (그 우회 자체는 W5 가 따로 잰다).
  //    **이것이 도달 불가능하면 이 하네스 전체가 「구성 전 기계」 위에서만
  //    돌고, 정본 ISA-3 전반(Inv_CleanNeverFaults)의 RTL 상은 한 번도
  //    재어지지 않는다 — 등식의 반쪽만 보는 증명이 된다.**
  always @(posedge clk) begin
    w1_clean_delivery: cover (
      f_run && f_cfg && tok_valid && h_hit && (tok_srcKind == 4'd1)
           && bank[tok_lbid] && !o_fire && out_valid);
  end

  // W2 ← Route.global_judge · Route.fault_once · p_global_judge · p_fault_once
  //      ⟨판정 등식의 `o_fire == 1` 면 · LNID 축 단독⟩ ⟨발화 1회의 전건⟩
  //    **구성된** 기계에서 전역 미스만으로 발화한다 (ISA-3 후반).
  always @(posedge clk) begin
    w2_miss_lnid_only: cover (
      f_run && f_cfg && tok_valid && h_missLnid && !h_missLbid && o_fire);
  end

  // W3 ← Route.global_judge · p_global_judge
  //      ⟨판정 등식의 `o_fire == 1` 면 · LBID 축 단독⟩
  //    적중한 LNID 인데 `src_kind=1` 의 LBID 가 미사상이라 발화한다 (ISA-8).
  //    이 증인이 없으면 두 축이 독립이라는 정본의 주장(ISA-3/ISA-8 분리)이
  //    RTL 에서 재어지지 않는다 — 종전 판의 ISA-3 이 이 축을 삼키고 있었다.
  always @(posedge clk) begin
    w3_miss_lbid_only: cover (
      f_run && f_cfg && tok_valid && !h_missLnid && h_missLbid && o_fire);
  end

  // W4 ← Route.fault_once · p_fault_once · p_global_judge
  //      ⟨발화 1회의 실질 전건⟩ — Route.tla `Witness_NoDoubleMiss` 의 RTL 판.
  //    두 조건을 *동시에* 밟는 토큰이 실재한다. 이것이 도달 불가능하면
  //    ISA-4 「두 조건을 다 밟아도 fault 는 하나」는 검사할 것이 없다.
  always @(posedge clk) begin
    w4_double_miss_one_fire: cover (
      f_run && f_cfg && tok_valid && h_missLnid && h_missLbid && o_fire);
  end

  // W5 ← Route.global_judge · p_global_judge
  //      ⟨h_missLbid 의 srcKind 전건⟩ — LBID 가 미사상인데 `src_kind≠1` 이라
  //    fault 가 없다. ISA-8 의 전건이 상수-참으로 접혀 있지 않다는 증거이며,
  //    이것 없이는 「사상 축은 src_kind=1 한정」이 재어지지 않는다.
  always @(posedge clk) begin
    w5_srckind_gates_lbid: cover (
      f_run && tok_valid && h_hit && (tok_srcKind != 4'd1)
           && !bank[tok_lbid] && !o_fire);
  end

  // W6 ← Route.global_judge · Route.scope_independent · p_global_judge
  //      ⟨정본 §1.6.3 함정: 「전역 미스」와 「지역 비소유」의 구분⟩
  //    Route.tla `Witness_NoLocalNonOwnership` 의 RTL 판. 뷰에 *이름이 다른*
  //    유효 엔트리가 있는데 — 지역 판정 기계였다면 바로 그 자리가 fault 를
  //    냈을 상황 — 토큰은 합집합에 속하므로 fault 가 없다. 「형제 노드의
  //    비소유는 fault 가 아니다」가 실측되는 유일한 자리다.
  always @(posedge clk) begin
    w6_sibling_nonowner_clean: cover (
      f_run && tok_valid && h_hit && f_sibling && !h_missLbid && !o_fire);
  end

  // W7 ← Route.fault_once · p_fault_once
  //      ⟨발화 1회의 반대편 전건⟩ — 미스 조건이 성립하는데 제시가 없어
  //    발화하지 않는다. `!o_fire || tok_valid` 가 「미스가 없어서」가 아니라
  //    「제시가 없어서」 서는 사이클이 실재한다.
  always @(posedge clk) begin
    w7_miss_without_presentation: cover (
      f_run && !tok_valid && h_anyMiss && !o_fire);
  end

  // ── 부류 ② 시간축 — Route.tla 가 미덮임으로 남긴 축 (하네스 머리 주석) ──

  // W8 ← Route.fault_once · p_fault_once
  //      ⟨발화 1회의 시간축 판⟩ — 동일 (wave·에포크·poison·trace·lnid) 토큰이 연속 두
  //    사이클 제시되어 각각 발화한다. 「제시당 1회」가 「토큰당 1회」로 접히지
  //    않는다는 것, 곧 재제시가 표현 가능하다는 것. Route.tla 가 범위당 1회
  //    원자 판정으로 모델링해 표현 자체를 못 가졌던 축이며(하네스 머리 주석),
  //    후-formal 이 그 몫을 맡는다는 분업의 실물이다.
  always @(posedge clk) begin
    w8_repeat_presentation: cover (
      f_seq && o_fire && $past(o_fire) && tok_valid && $past(tok_valid)
            && (tok_lnid == $past(tok_lnid)) && (tok_wave == $past(tok_wave))
            && (tok_epoch == $past(tok_epoch)) && (tok_poison == $past(tok_poison))
            && (tok_trace == $past(tok_trace)));
  end

  // W9 ← Route.global_judge · Route.view_sync · p_global_judge
  //      ⟨판정이 「뷰만의 함수」라는 주장의 실측 ①⟩ — ISA-2(사상 경유)
  //    의 RTL 상. *같은* 토큰이 뷰 구성 뒤에는 fault 를 밟지 않는다. 판정이
  //    토큰만의 함수라면 이 궤적은 없다.
  always @(posedge clk) begin
    w9_verdict_flips_to_clean: cover (
      f_seq && $past(o_fire) && $past(tok_valid) && tok_valid && !o_fire
            && (tok_lnid == $past(tok_lnid)) && (tok_lbid == $past(tok_lbid))
            && (tok_srcKind == $past(tok_srcKind)));
  end

  // W10 ← Route.global_judge · Route.view_sync · p_global_judge
  //      ⟨같은 주장의 실측 ②⟩ — 반대 방향. 뷰 엔트리를 무효화하면 같은 토큰이
  //      fault 를 밟는다. 두 방향을 함께 두어야 「뷰가 판정을 *지배*한다」가
  //      한 방향의 우연이 아님이 선다.
  always @(posedge clk) begin
    w10_verdict_flips_to_fault: cover (
      f_seq && !$past(o_fire) && $past(tok_valid) && tok_valid && o_fire
            && (tok_lnid == $past(tok_lnid)) && (tok_lbid == $past(tok_lbid))
            && (tok_srcKind == $past(tok_srcKind)));
  end

  // ── 부류 ③ sticky — p_loud_fault 등식의 네 분기 (ISA-6 · INV-T3) ──────

  // W11 ← Route.loud_fault · p_loud_fault
  //      ⟨`fault' = fire | …` 의 fire 항⟩ — sticky 가 실제로 선다.
  always @(posedge clk) begin
    w11_sticky_rise: cover (
      f_seq && !$past(o_fault) && $past(o_fire) && o_fault);
  end

  // W12 ← Route.loud_fault · p_loud_fault
  //      ⟨`… | (fault & ~clear)` 의 유지 항⟩ — 재발화 없이 해제도 없이 유지.
  //      ISA-6 「명시적 해제 전까지 유지」가 재어지는 자리.
  always @(posedge clk) begin
    w12_sticky_hold: cover (
      f_seq && $past(o_fault) && !$past(o_fire) && !$past(fault_clear) && o_fault);
  end

  // W13 ← Route.loud_fault · p_loud_fault
  //      ⟨같은 항의 `~clear` 인자⟩ — 명시적 해제가 실제로 내린다. 이것이
  //      도달 불가능하면 p_loud_fault 는 「한 번 서면 영원히 1」인 기계에서도
  //      통과하고, 해제 경로는 재어지지 않는다.
  always @(posedge clk) begin
    w13_sticky_clear: cover (
      f_seq && $past(o_fault) && $past(fault_clear) && !$past(o_fire) && !o_fault);
  end

  // W14 ← Route.loud_fault · p_loud_fault
  //      ⟨두 항의 우선순위⟩ — 발화와 해제가 *같은 사이클*에 오면 set 이
  //      이긴다. 하네스 주석이 주장하는 「miss 삼킴 없음」의 구석이며, 이
  //      궤적 없이는 등식의 `fire |` 가 clear 와 겹치는 면이 미측정이다.
  always @(posedge clk) begin
    w14_set_beats_clear: cover (
      f_seq && $past(o_fire) && $past(fault_clear) && o_fault);
  end

  // ── 부류 ④ 뷰 기입 — `if ($past(vw_valid))` 전건과 그 else 가지 ────────

  // W15 ← Route.view_sync · p_view_sync_wr_v · p_view_sync_wr_n
  //      ⟨두 기입 단언의 전건⟩ — 기입이 상태를 *실제로 바꾼다*.
  //      이것 없이는 기입 단언들이 「아무것도 안 바뀌는」 기계 위에서 성립.
  always @(posedge clk) begin
    w15_view_write_changes: cover (
      f_seq && $past(vw_valid) && (h_vv != c_vv));
  end

  // W16 ← Route.view_sync · p_view_sync_wr_v
  //      ⟨같은 전건의 en=0 면⟩ — 무효화 기입. `== $past(vw_en)` 등식이 en=1
  //      쪽만으로 재어지지 않는다는 증거.
  always @(posedge clk) begin
    w16_view_invalidate: cover (
      f_seq && $past(vw_valid) && !$past(vw_en)
            && c_vv[$past(vw_idx)] && !h_vv[$past(vw_idx)]);
  end

  // W17 ← Route.view_sync · p_view_sync_wr_v
  //      ⟨루프 단언 15×2 (`i != $past(vw_idx)`)의 전건 — 그 단언들은 for 안이라
  //      라벨을 달 수 없어 가드로 적는다⟩ — 기입 사이클에 *다른*
  //      엔트리가 유효하다. 뷰가 한 칸만 쓰이는 세계라면 부동 단언 30개가
  //      전부 0==0 이다.
  always @(posedge clk) begin
    w17_other_entry_live: cover (
      f_seq && $past(vw_valid) && ((h_vv & ~(16'h1 << $past(vw_idx))) != 16'h0));
  end

  // W18 ← Route.view_sync · p_view_sync_hold
  //      ⟨유지 단언의 전건 (else 가지)⟩ — 무기입 사이클에 뷰가 비어
  //      있지 않다. 유지 단언이 공집합 위의 자명한 성립이 아니라는 증거.
  always @(posedge clk) begin
    w18_view_hold_nonempty: cover (
      f_seq && !$past(vw_valid) && (h_vv != 16'h0));
  end

  // ── 부류 ⑤ 존재 비트 표 — `if ($past(bw_valid))` 전건과 그 else 가지 ────

  // W19 ← Route.view_sync · p_bank_sync_wr
  //      ⟨존재 비트 기입 단언의 전건 · mapped=1 면⟩ — 사상 등재가 실제로 일어난다.
  always @(posedge clk) begin
    w19_bank_set: cover (
      f_seq && $past(bw_valid) && $past(bw_mapped)
            && bank[$past(bw_lbid)] && !c_bank[$past(bw_lbid)]);
  end

  // W20 ← Route.view_sync · p_bank_sync_wr
  //      ⟨같은 전건 · mapped=0 면⟩ — 사상 말소. `== $past(bw_mapped)` 등식이
  //      기입 값 한쪽 면만으로 재어지지 않는다는 증거이며, 뷰 축의 W16
  //      (무효화 기입)에 대응한다.
  always @(posedge clk) begin
    w20_bank_clear: cover (
      f_seq && $past(bw_valid) && !$past(bw_mapped)
            && !bank[$past(bw_lbid)] && c_bank[$past(bw_lbid)]);
  end

  // W21 ← Route.view_sync · p_bank_sync_oth
  //      ⟨마스크 부동 단언의 전건⟩ — 기입 사이클에 *다른* 비트가 서 있다.
  //      마스크 등식이 0==0 이 아니라는 증거.
  always @(posedge clk) begin
    w21_other_bank_bit_live: cover (
      f_seq && $past(bw_valid)
            && ((bank & ~(256'h1 << $past(bw_lbid))) != 256'h0));
  end

  // W22 ← Route.view_sync · p_bank_sync_hold
  //      ⟨유지 단언의 전건 (else 가지)⟩ — 무기입 사이클에 표가 비어
  //      있지 않다.
  always @(posedge clk) begin
    w22_bank_hold_nonempty: cover (
      f_seq && !$past(bw_valid) && (bank != 256'h0));
  end

  // ── 부류 ⑥ reset 관문 — `if (f_past_valid && past_reset)` 전건 ──────────

  // W23 ← p_reset_empty
  //      ⟨reset 관문 단언의 전건⟩ — reset 직후 사이클이 실재한다. 유일한 환경
  //      assume(reset 프로토콜)이 이 창을 목 졸라 놓지 않았다는 증거 —
  //      졸랐다면 §1.5 단언은 존재하지 않는 사이클에 대한 주장이 된다.
  always @(posedge clk) begin
    w23_reset_exit_window: cover (
      f_past_valid && past_reset && !reset);
  end
`endif // ROUTEJUDGE_COVER

endmodule
