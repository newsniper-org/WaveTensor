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
  input wire [15:0] tok_thread,
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
  wire [15:0] out_thread;
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
    .io_tokIn_payload_tag_thread(tok_thread),
    .io_tokIn_payload_tag_lnid(tok_lnid),
    .io_tokIn_payload_tag_precision(tok_precision),
    .io_tokIn_payload_tag_dim(tok_dim),
    .io_tokIn_payload_lbid(tok_lbid),
    .io_tokIn_payload_srcKind(tok_srcKind),
    .io_tokOut_valid(out_valid),
    .io_tokOut_payload_tag_wave(out_wave),
    .io_tokOut_payload_tag_thread(out_thread),
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
                            && out_thread == tok_thread
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

endmodule
