// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// OwnershipTable 후-formal 하네스 (§6.3) — 축: 전이는 명시 기입 사이클에만
// (암묵 전이·축출 부재 — E.7 이 금지한 형태) · 커밋 원자성 (유효 비트와
// 태그가 한 에지에 함께 — 혼합 관측 사이클 부재).
//
// Platform 가드의 정식 GUARD-MAP 줄은 HiuPipeline.scala 에 있다 (가드당
// 저장소 전체 한 줄 규율). 이 표는 그 판정의 데이터 원천이므로, 여기서 재는
// 것은 상태 기계 실물의 전이 규율이다 — 각 assert 옆에 가드명 주석.
//
// 대상 SV 는 rtl/generated/OwnershipTable.sv 커밋본 그대로.

`timescale 1ns/1ps

module OwnershipTable_props (
  input wire          clk,
  input wire          reset,
  input wire          io_wstrobe,
  input wire [31:0]   io_wdata,
  input wire [31:0]   io_query_frame,
  input wire          io_query_devOwned,
  input wire          io_faultCollide,
  input wire          io_faultClearCollide,
  input wire          dataWr,          // OWN_DATA 수락 기입 = 유일한 전이 관문
  input wire [5:0]    wIdx,
  input wire [24:0]   wTag,
  input wire          collide,
  input wire [63:0]   f_valid,         // validBits
  input wire [1599:0] f_tags           // {tagVec_63, …, tagVec_0}
);
  // ── ENV assume: 단발 reset 프로토콜 (근거: HiuMask_props.sv 동일 —
  // async-reset 레지스터의 형식 검사 초기화 규약. 그 외 assume 없음) ──
  reg f_init = 1'b1;
  always @(posedge clk) f_init <= 1'b0;
  always @(*) begin
    if (f_init) assume (reset);
    else        assume (!reset);
  end

  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;
  wire f_ok = f_past_valid && !reset && !$past(reset);

  wire [5:0]  f_qIdx    = io_query_frame[5:0];
  wire [24:0] f_qTagLow = io_query_frame[30:6];

  // ── 조합 축 — 조회 정의 (Platform.owner_check 의 데이터 원천) ───────────
  // devOwned = 유효 ∧ 태그 일치 ∧ 상위 0. 유효·태그가 항상 짝으로만
  // 소비되므로, 아래 시제 축이 서면 조회에 혼합 상태가 보일 표면이 없다.
  always @(*) begin
    if (f_past_valid && !reset) begin
      assert (io_query_devOwned ==
              (f_valid[f_qIdx] && (f_tags[25*f_qIdx +: 25] == f_qTagLow)
               && !io_query_frame[31]));
    end
  end

  // ── 시제 축 — 슬롯별 전이 규율 ──────────────────────────────────────────
  // RTL 의 이양/회수 조건을 검사자 쪽에서 f_valid/f_tags 로 독립 재구성한다
  // (slotBusy = validBits[wIdx] · slotMine = tagVec[wIdx]==wTag 을 그대로
  // 믿지 않고 원 레지스터에서 다시 계산 — 매핑의 참을 재는 취지).
  genvar i;
  generate for (i = 0; i < 64; i = i + 1) begin : g_slot
    always @(posedge clk) begin
      if (f_ok) begin
        if ($past(dataWr) && ($past(wIdx) == i[5:0])
            && $past(io_wdata[31]) && !$past(f_valid[i])) begin
          // Platform.state_machine_kept / E.7 — 이양 커밋 원자성: 유효 비트와
          // 태그가 같은 에지에 함께 선다 — 부분 상태 관측 사이클 부재
          assert (f_valid[i]);
          assert (f_tags[25*i +: 25] == $past(wTag));
        end else if ($past(dataWr) && ($past(wIdx) == i[5:0])
                     && !$past(io_wdata[31]) && $past(f_valid[i])
                     && ($past(f_tags[25*i +: 25]) == $past(wTag))) begin
          // 회수 — 유효만 내리고 태그는 불변 (한 에지 완결)
          assert (!f_valid[i]);
          assert ($stable(f_tags[25*i +: 25]));
        end else begin
          // Platform.state_machine_kept / E.7 — 암묵 전이 부재: 위 두 명시
          // 기입 경우 밖(기입 없는 사이클 · 타 슬롯 기입 · 충돌 기입 ·
          // 무연산 항등 · 읽기 strobe · OWN_IDX 기입)에서는 validBits 도
          // 태그도 움직이지 않는다 — 축출 배선 부재의 관측형
          assert ($stable(f_valid[i]));
          assert ($stable(f_tags[25*i +: 25]));
        end
      end
    end
  end endgenerate

  // ── 충돌은 loud — 기입 무효는 위 else 가지가 재고, fault 는 여기 ────────
  always @(posedge clk) begin
    if (f_ok) begin
      // 충돌 기입(이양 대상 슬롯이 남의 것) → sticky fault 세움 (같은
      // 사이클 clear 와 겹쳐도 세움이 이긴다 — StickyFault 규율)
      if ($past(collide))
        assert (io_faultCollide);
    end
  end
endmodule

bind OwnershipTable OwnershipTable_props u_own_props (
  .clk                  (clk),
  .reset                (reset),
  .io_wstrobe           (io_wstrobe),
  .io_wdata             (io_wdata),
  .io_query_frame       (io_query_frame),
  .io_query_devOwned    (io_query_devOwned),
  .io_faultCollide      (io_faultCollide),
  .io_faultClearCollide (io_faultClearCollide),
  .dataWr               (dataWr),
  .wIdx                 (wIdx),
  .wTag                 (wTag),
  .collide              (collide),
  .f_valid              (validBits),
  .f_tags               ({tagVec_63, tagVec_62, tagVec_61, tagVec_60,
                          tagVec_59, tagVec_58, tagVec_57, tagVec_56,
                          tagVec_55, tagVec_54, tagVec_53, tagVec_52,
                          tagVec_51, tagVec_50, tagVec_49, tagVec_48,
                          tagVec_47, tagVec_46, tagVec_45, tagVec_44,
                          tagVec_43, tagVec_42, tagVec_41, tagVec_40,
                          tagVec_39, tagVec_38, tagVec_37, tagVec_36,
                          tagVec_35, tagVec_34, tagVec_33, tagVec_32,
                          tagVec_31, tagVec_30, tagVec_29, tagVec_28,
                          tagVec_27, tagVec_26, tagVec_25, tagVec_24,
                          tagVec_23, tagVec_22, tagVec_21, tagVec_20,
                          tagVec_19, tagVec_18, tagVec_17, tagVec_16,
                          tagVec_15, tagVec_14, tagVec_13, tagVec_12,
                          tagVec_11, tagVec_10, tagVec_9,  tagVec_8,
                          tagVec_7,  tagVec_6,  tagVec_5,  tagVec_4,
                          tagVec_3,  tagVec_2,  tagVec_1,  tagVec_0})
);
