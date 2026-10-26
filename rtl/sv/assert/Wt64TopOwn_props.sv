// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// Wt64Top 소유권 조립 검사자 — OwnershipTable 을 절단하지 않은 최상위 조립에서 FAULT_STATUS [7] 과
// E.7 7항 읽기 순서를 MMIO 끝-끝으로 잰다 (판 값 커밋 전 측정 파도 W7 — M2 · M3, 2026-10-23).
// 태스크: rtl/formal/sby/Wt64Top/ownasm.sby (머리가 절단 정의역 · 엔진 · 역-변이 표를 소유한다).
//
// ## 왜 assembly.sby 가 아닌가
//
// assembly 는 own 을 절단하므로 own 의 faultCollide 핀이 자유다 — FAULT_STATUS [7] = 그 핀(a_rd_fst ·
// a_fsrc_b7)과 「그 핀은 OWN_SET 거절에서만 선다」(ownershiptable.sby s_col_*)의 합성이 서술이었다
// (lint_postformal _PARTIAL 의 Platform.set_reject_loud · seven_reject_only 넷). 여기서는 같은 기제
// (Wt64Top 본문에 검사자를 텍스트 전개로 넣고 expose -evert 로 절단)로 *own 만 남기고* 나머지를 뗀다 —
// 한 모델 안에서 MMIO 기입 → own → 최상위 포트 · 0xF80 읽기가 끝-끝이다.
//
// ## 오라클 — MMIO 이력에서 다시 짓는다 (OwnershipTable_props.sv 의 독립 재구성 원칙)
//
// 자유 상수 칸 f_idx 하나의 그림자(f_shV · f_shTag)를 정본 규칙으로 짓는다 — 아래 E.7 6항 인용의
// 거절 · 무연산 · 회수 규칙과 참조 형상(직접 사상 — 후보 칸 = 프레임 [5:0], RTL 사실 · ownershiptable.sby
// 의 f_wIdx 와 같은 함수). RTL 의 validBits · tagVec · collide 를 읽지 않는다. f_idx 가 자유 상수라
// 칸 단언은 64 칸 전칭이다 (OwnershipTable_props.sv 「시제 축」의 사영 논거).
//
//   e-defined.typ:1387 「그 프레임이 장치 소유로 앉을 수 있는 저장 칸이 전부 *다른* 장치 소유 페이지로 차 있는 경우다」
//   e-defined.typ:1387 「거절은 loud sticky fault FAULT_STATUS `[7]` 을 세운다」
//   e-defined.typ:527 「`[7]` 은 E.7 6항의 OWN_SET 거절 *하나*」
//   e-defined.typ:1388 「그 전이 기입의 결과 — 커밋이든 거절이든 — 를 본다」
//   e-defined.typ:497 「해제와 발화가 같은 사이클이면 발화가 이긴다」
//   e-defined.typ:216 「`0x320` IRQ_STATUS 의 sticky 전부 = 0」 — FAULT_STATUS 를 포함한 reset 값 (t7_rst)
//
// ## assume (전수)
//
//   reset 은 t0 에만 1 이고 그 뒤 0 이다 (OwnershipTable_props.sv 의 단발 reset 규약 — .sby 가 수 2 를 핀한다).
module Wt64TopOwn_props (
  input logic        clk,
  input logic        reset,
  input logic [11:0] io_mmio_addr,
  input logic        io_mmio_wstrobe,
  input logic [31:0] io_mmio_wdata,
  input logic        io_mmio_rstrobe,
  input logic [31:0] io_mmio_rdata,
  input logic        io_mmio_rvalid,
  input logic        io_mmio_ready,
  input logic        io_fault_ownCollide,
  input logic        io_faultClear_ownCollide,
  // 절단 핀 (출력 — 매 스텝 자유) — rdata mux 에서 own 응답을 덮어쓸 수 있는 두 유닛의 rvalid (o_rd 의 예외 항 · 증인 W3–W5 의 0 조건)
  input logic        cq__io_rvalid,
  input logic        cfgBlk__io_rvalid
);
  logic f_init = 1'b1;
  always @(posedge clk) f_init <= 1'b0;
  always @(*) begin
    if (f_init) assume (reset);
    else        assume (!reset);
  end
  logic f_past_valid = 1'b0;
  logic f_rst_d = 1'b1;
  always @(posedge clk) begin f_past_valid <= 1'b1; f_rst_d <= reset; end
  wire f_step = f_past_valid && !reset && !f_rst_d;

  wire [11:0] A = io_mmio_addr;
  wire [31:0] D = io_mmio_wdata;
  wire W  = io_mmio_wstrobe;
  wire R  = io_mmio_rstrobe && !io_mmio_wstrobe;
  wire al = (A[1:0] == 2'b00);
  wire acc = io_mmio_ready;

  // 수락된 정렬 기입 (E.7 · 3.9 「sub-word 쓰기 거절」 — 비정렬은 전이가 아니다)
  wire idxA = W && al && (A == 12'h200) && acc;
  wire setA = W && al && (A == 12'h208) && acc;
  wire clrA = W && al && (A == 12'h20C) && acc;
  // [7] 해제 — IO 해제선 또는 수락된 0xF84 W1C [7] (예약 [31:20] 엄격 — assembly 의 acF84 와 같은 식)
  wire clr7 = io_faultClear_ownCollide || (W && (A == 12'hF84) && (D[31:20] == 12'd0) && D[7]);

  (* anyconst *) logic [5:0] f_idx;
  wire        hit = (D[5:0] == f_idx);
  wire [25:0] tg  = D[31:6];

  logic        f_shV   = 1'b0;
  logic [25:0] f_shTag = 26'd0;
  logic [31:0] f_iReg  = 32'd0;
  always @(posedge clk) begin
    if (reset) begin
      f_shV <= 1'b0; f_shTag <= 26'd0; f_iReg <= 32'd0;
    end else begin
      if (idxA) f_iReg <= D;
      if (setA && hit && !f_shV) begin f_shV <= 1'b1; f_shTag <= tg; end
      if (clrA && hit && f_shV && (f_shTag == tg)) f_shV <= 1'b0;
    end
  end
  wire collK = setA && hit && f_shV && (f_shTag != tg);   // f_idx 칸의 형상 · 점유 거절

  // [7] 의 세움 사건 — 0→1 과 1 인 채 해제 사이클의 재세움 (ownershiptable.sby W6 F1 의 전건 꼴)
  logic f_hold7 = 1'b0;                     // 직전 사이클 「[7] = 1 ∧ 해제 아님」
  always @(posedge clk) f_hold7 <= io_fault_ownCollide && !clr7;
  wire rise7 = io_fault_ownCollide && !f_hold7;

  // M2 — reset 출구 (W7 검증 V4-1): f_step 은 t0 reset 바로 다음 사이클을 빼고, f_hold7 은 그 사이클의 포트 값을 싣는다 —
  // 그래서 reset 에서 이미 1 로 나온 [7] 은 세움 사건(rise7)이 되지 않아 t7_src · t7_slot 이 보지 못하고, t7_hold · t7_rd
  // 는 상수 1 로도 참이다. 그 칸을 이 단언이 받는다: reset 바로 다음 사이클의 최상위 [7] 은 0 (E.1 reset 값 규범 3항).
  // 이 사이클이 0 이면 그 뒤의 모든 1 은 0→1 을 거쳐야 하므로 rise7 로 잡힌다 — 세움 건전성이 reset 출구부터 닫힌다.
  always @(posedge clk) if (f_past_valid && !reset && f_rst_d)
                                     t7_rst:  assert (!io_fault_ownCollide);

  always @(posedge clk) if (f_step) begin
    // M2 — 최상위 [7] 의 세움 건전성 (Platform.seven_reject_only): 원천은 직전 사이클의 수락된 정렬 OWN_SET 하나
    if (rise7)                       t7_src:  assert ($past(setA));
    // 그 기입이 f_idx 칸을 지목했으면 그 칸은 다른 태그의 페이지가 차지하고 있었다 (그림자 — 64 칸 전칭)
    if (rise7 && $past(setA && hit)) t7_slot: assert ($past(f_shV && (f_shTag != tg)));
    // M2 — 완전성 (Platform.set_reject_loud): f_idx 칸의 거절 ⇒ 다음 사이클 최상위 [7]
    if ($past(collK))                t7_cmp:  assert (io_fault_ownCollide);
    // M2 — sticky: 해제(clr7 — IO 해제선 또는 D[7] = 1 인 0xF84 W1C, assembly a_fclr_b7 의 acF84 와 같은 정확한 식)가
    // 없으면 [7] 은 내려가지 않는다. D[7] = 0 인 0xF84 기입 · 예약 비트가 선 0xF84 기입도 [7] 을 내리지 않는다는 것이 이 식에
    // 든다 (W7 검증 V1-2). 해제가 실제로 내린다는 반대 절반은 t7_src · t7_slot 이 함의한다 — 해제 사이클 다음에 [7] 이 1 이면 그것은
    // 세움 사건(rise7)이라 직전 OWN_SET 을 요구한다.
    if ($past(io_fault_ownCollide && !clr7)) t7_hold: assert (io_fault_ownCollide);
    // M2 — 0xF80 읽기의 [7] = 수락 사이클의 최상위 [7] (같은 모델 안에서 읽기까지 닫는다)
    if ($past(R && al && (A == 12'hF80)))
                                     t7_rd:   assert (io_mmio_rvalid && io_mmio_rdata[7] == $past(io_fault_ownCollide));
    // M3 — E.7 7항의 최상위 판: OWN_IDX(그림자) = f 인 0x204 읽기의 응답 = 수락 사이클까지 수락된 전이의 결과
    if ($past(R && al && (A == 12'h204) && acc && (f_iReg[5:0] == f_idx)))
                                     o_rd:    assert (io_mmio_rvalid && ((cq__io_rvalid || cfgBlk__io_rvalid) ||
                                                      io_mmio_rdata == {31'd0, $past(f_shV && (f_shTag == f_iReg[31:6]))}));
  end

`ifdef WT64TOPOWN_COVER
  // W1 ← Platform.set_reject_loud · Platform.seven_reject_only · t7_cmp · t7_src · t7_slot · t7_rd — f_idx 칸의 거절이 [7] 을
  //      처음 세우고 다음 0xF80 읽기가 [7] = 1 을 낸다
  // W2 ← Platform.seven_reject_only · t7_src — [7] = 1 인 채 해제와 같은 사이클의 거절이 [7] 을 다시 세운다 (세움 사건의 둘째 꼴)
  // W3 ← Wt64Top.own_read_order · o_rd — OWN_SET 커밋 바로 다음 사이클에 수락된 OWN_STATUS 읽기가 [0] = 1 을 본다
  // W4 ← Wt64Top.own_read_order · o_rd — 거절된 OWN_SET 의 프레임을 다음 사이클에 읽으면 [0] = 0
  // W5 ← Wt64Top.own_read_order · o_rd — 회수(OWN_CLR) 바로 다음 사이클의 읽기가 [0] = 0 을 본다
  //      W3–W5 공통 (W7 검증 V7-1): 전이 기입은 reset 밖(!$past(reset, 2) — t0 reset 사이클의 기입은 그림자를 바꾸지 않는다)이고,
  //      응답 사이클의 절단 핀 cq · cfgBlk rvalid 는 0 이다 — o_rd 의 예외 항이 아니라 검사 항으로 닿는다 (rdata mux 에서 cfgBlk 가
  //      own 을 덮으므로, 이 항이 없으면 풀이기가 [0] 을 자유 핀 cfgBlk__io_rdata 로 지어 낸다)
  // W6 ← Platform.set_reject_loud · t7_hold — [7] = 1 인 채 D[7] = 0 인 0xF84 기입(다른 비트의 W1C)이 [7] 을 내리지 않는다
  always @(posedge clk) if (f_step) begin
    w1_rej_rd:    cover ($past(R && al && (A == 12'hF80)) && io_mmio_rdata[7] && $past(collK, 2) && !$past(io_fault_ownCollide, 2));
    w2_rerise:    cover ($past(collK && clr7 && io_fault_ownCollide) && io_fault_ownCollide);
    w3_rd_commit: cover ($past(R && al && (A == 12'h204) && acc && (f_iReg[5:0] == f_idx)) &&
                         !$past(reset, 2) && $past(setA && hit && !f_shV && (tg == f_iReg[31:6]), 2) &&
                         io_mmio_rvalid && io_mmio_rdata[0] && !cq__io_rvalid && !cfgBlk__io_rvalid);
    w4_rd_reject: cover ($past(R && al && (A == 12'h204) && acc && (f_iReg[5:0] == f_idx)) &&
                         !$past(reset, 2) && $past(collK && (tg == f_iReg[31:6]), 2) &&
                         io_mmio_rvalid && !io_mmio_rdata[0] && !cq__io_rvalid && !cfgBlk__io_rvalid);
    w5_rd_clr:    cover ($past(R && al && (A == 12'h204) && acc && (f_iReg[5:0] == f_idx)) &&
                         !$past(reset, 2) && $past(clrA && hit && f_shV && (f_shTag == tg) && (tg == f_iReg[31:6]), 2) &&
                         io_mmio_rvalid && !io_mmio_rdata[0] && !cq__io_rvalid && !cfgBlk__io_rvalid);
    w6_hold:      cover ($past(io_fault_ownCollide && W && (A == 12'hF84) && (D[31:20] == 12'd0) && !D[7] && !io_faultClear_ownCollide) &&
                         io_fault_ownCollide);
  end
`endif
endmodule

bind Wt64Top Wt64TopOwn_props chk (.*);
