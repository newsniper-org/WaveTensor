// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// Wt64Top step sequencer 조립 검사자 — StepSequencer 를 절단하지 않은 최상위 조립에서 FP_STATUS `[1]` 의
// 읽기 순서(C2 — 아래 정본 인용)를 잰다 (판 값 커밋 전 측정 파도 W7 — M1, 2026-10-23).
// 태스크: rtl/formal/sby/Wt64Top/fporder.sby (머리가 절단 정의역 · 소거 뒤 시작 상태 · 엔진 · 역-변이 표를 소유한다).
//
// ## 정본 (좌표 뒤 「」 는 그 줄의 축자)
//
//   e-defined.typ:463 「그 읽기의 수락 사이클 *앞에* 그 열쇠를 조회한 걷기가」
//   e-defined.typ:463 「모두 끝났음을 뜻한다」
//   e-defined.typ:463 「그 읽기의 수락 사이클*부터*(같은 사이클 포함) 시작하는 조회는 그 기입이 반영된 선택자 표를 본다」
//   e-defined.typ:463 「`[1]` 걷기 진행 중」
//   e-defined.typ:738 「재구현의 형상($P$ = 10 · stepMax = 32 — RTL 사실)」 — F_P 의 출처 (RTL 상수를 베끼지 않는다)
//
// ## 오라클 — MMIO 이력에서 다시 짓는다
//
// 자유 상수 열쇠 f_key 하나의 결속 그림자(f_kv · f_ks)를 수락된 정렬 0xF04 기입에서 짓는다 —
// 예약 [30:24] 비0 은 거절(무효과) · en = 1 이고 슬롯 ≥ P 이면 거절(무효과) · en = 0 이면 해제 · 그 밖이면
// 결속. RTL 의 bindWrBad · selWrEn 을 읽지 않는다. 조회의 「본 값」은 StepSequencer 의 selRd(선택자 표
// 동기 읽기 데이터 — 접수 다음 사이클)를 expose 해 DUT 측으로만 본다 (ownershiptable.sby 의 expose 선례).
// 끝-끝 포트 판(a_ord_cap)은 expose 없이 최상위 io_fp_capAbsent 로 V 축을 잰다.
module Wt64TopFp_props (
  input logic        clk,
  input logic        reset,
  input logic [11:0] io_mmio_addr,
  input logic        io_mmio_wstrobe,
  input logic [31:0] io_mmio_wdata,
  input logic        io_mmio_rstrobe,
  input logic [31:0] io_mmio_rdata,
  input logic        io_mmio_rvalid,
  input logic        io_mmio_ready,
  input logic        io_fp_reqValid,
  input logic [7:0]  io_fp_opKind,
  input logic [7:0]  io_fp_precision,
  input logic        io_fp_reqReady,
  input logic        io_fp_done,
  input logic        io_fp_capAbsent,
  input logic        fps_io_oBusy,       // 구체 유닛 출력 핀 — 귀납 보조 h_open 에만 쓴다
  input logic [4:0]  fpsx_selRd,         // expose: StepSequencer.selRd (조회가 본 선택자 표 항목 {V, 슬롯[3:0]})
  input logic        fpsx_initDone       // expose: StepSequencer.initDone — 「소거 완료 직후」 시작 가정에만 쓴다
);
  localparam integer F_P = 10;

`ifdef WT64TOPFP_POSTINIT
  // 「소거 완료 직후」 시작 (MmioConfig/mmio_config.sby cover · post 선례 — 정직 표기는 .sby 머리): reset 을 인가하지 않고
  // t0 에 소거 완료(initDone)와 걷기 없음(!busy)만 가정한다. 선택자 표 내용 · 나머지 레지스터는 자유다 (과대근사).
  initial assume (fpsx_initDone && !fps_io_oBusy);
  always @(*) assume (!reset);
  logic f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;
  logic f_rst_d = 1'b0;
  always @(posedge clk) f_rst_d <= reset;
`else
  logic f_init = 1'b1;
  always @(posedge clk) f_init <= 1'b0;
  always @(*) begin
    if (f_init) assume (reset);
    else        assume (!reset);
  end
  logic f_past_valid = 1'b0;
  logic f_rst_d = 1'b1;
  always @(posedge clk) begin f_past_valid <= 1'b1; f_rst_d <= reset; end
`endif
  wire f_step = f_past_valid && !reset && !f_rst_d;

  wire [11:0] A = io_mmio_addr;
  wire [31:0] D = io_mmio_wdata;
  wire W  = io_mmio_wstrobe;
  wire R  = io_mmio_rstrobe && !io_mmio_wstrobe;
  wire al = (A[1:0] == 2'b00);

  (* anyconst *) logic [15:0] f_key;

  wire bindK  = W && al && (A == 12'hF04) && io_mmio_ready && (D[15:0] == f_key) &&
                (D[30:24] == 7'd0) && (!D[31] || ({24'd0, D[23:16]} < F_P));   // 효과 있는 결속 기입
  wire rdSt   = R && al && (A == 12'hF08) && io_mmio_ready;                    // 수락된 FP_STATUS 읽기
  wire lookA  = io_fp_reqValid && io_fp_reqReady;                               // 걷기 접수 = 조회 발사
  wire lookK  = lookA && ({io_fp_opKind, io_fp_precision} == f_key);

  logic       f_kv = 1'b0;   // 그림자 결속 V
  logic [3:0] f_ks = 4'd0;   // 그림자 결속 슬롯
  logic       f_wr = 1'b0;   // 이 열쇠의 효과 있는 결속 기입이 (이 사이클 *앞에*) 수락됐다
  logic       f_ord = 1'b0;  // 마지막 그 기입 뒤에 수락된 0xF08 읽기가 [1] = 0 을 냈다
  logic       f_open = 1'b0; // 접수되고 아직 done 이 나지 않은 걷기
  logic       f_rdPend = 1'b0;   // 직전 사이클에 「그 기입 뒤」 0xF08 읽기가 수락됐다 (같은 사이클 기입 없음)
  logic       f_rb = 1'b0;       // 증인 전용 — 마지막 그 기입이 다른 슬롯으로의 en = 1 재결속이었다
  logic       f_rel = 1'b0;      // 증인 전용 — 마지막 그 기입이 결속(V = 1)을 거둔 en = 0 해제였다
  always @(posedge clk) begin
    if (reset) begin
      f_kv <= 1'b0; f_ks <= 4'd0; f_wr <= 1'b0; f_ord <= 1'b0; f_open <= 1'b0; f_rdPend <= 1'b0; f_rb <= 1'b0; f_rel <= 1'b0;
    end else begin
      f_rdPend <= rdSt && f_wr && !bindK;
      if (bindK) begin
        f_kv <= D[31]; f_ks <= D[31] ? D[19:16] : 4'd0; f_wr <= 1'b1; f_ord <= 1'b0;
        f_rb <= D[31] && f_kv && (D[19:16] != f_ks);
        f_rel <= !D[31] && f_kv;
      end else if (f_rdPend && !io_mmio_rdata[1]) begin
        f_ord <= 1'b1;
      end
      if (lookA)           f_open <= 1'b1;
      else if (io_fp_done) f_open <= 1'b0;
    end
  end
  // 조회 사이클 c 가 C2 둘째 절의 범위에 드는가 — c 가 그 읽기의 수락 사이클 r 다음부터면 ordNow(c) 다: c = r + 1 은
  // 응답 사이클의 f_rdPend ∧ [1] = 0 (f_ord 는 r + 2 에야 선다), c ≥ r + 2 는 f_ord. c = r 자신은 아래 단언의 둘째 항
  // (검사 사이클 r + 1 의 f_rdPend ∧ [1] = 0)이 받는다. 둘을 합쳐 「수락 사이클부터 모든 사이클」이다 (W7 검증 V1-1 — 옛 식
  // $past(f_ord) 는 c = r + 1 을 빠뜨렸다).
  wire ordNow = f_ord || (f_rdPend && !io_mmio_rdata[1]);

  logic       f_lo2 = 1'b0;
  logic       f_kv2 = 1'b0;
  always @(posedge clk) begin
    f_lo2 <= f_step && $past(lookK) && ($past(ordNow) || (f_rdPend && !io_mmio_rdata[1] && !$past(bindK)));
    f_kv2 <= $past(f_kv);
  end

  always @(posedge clk) if (f_step) begin
    // C2 첫째 절 — 수락된 0xF08 읽기가 [1] = 0 을 내면 그 수락 사이클 앞에 접수된 걷기는 그 사이클까지 끝났다
    // (done 은 그 사이클이어도 된다). 열쇠를 가리지 않아 정본(그 열쇠의 걷기)보다 강하다.
    if ($past(rdSt) && !io_mmio_rdata[1])
      a_ord_done: assert (!$past(f_open) || $past(io_fp_done));
`ifndef WT64TOPFP_INDUCT
    // C2 둘째 절 — 그 읽기의 수락 사이클부터 시작한 f_key 조회는 그 기입이 반영된 항목을 본다
    if ($past(lookK) && ($past(ordNow) || (f_rdPend && !io_mmio_rdata[1] && !$past(bindK))))
      a_ord_sel: assert (fpsx_selRd == {$past(f_kv), $past(f_kv) ? $past(f_ks) : 4'd0});
    // 같은 절의 끝-끝 포트 판 (V 축) — 그 조회의 걷기는 V = 0 이면 다음 사이클 capAbsent 로 끝나고 V = 1 이면 아니다
    if (f_lo2)
      a_ord_cap: assert (io_fp_capAbsent == !f_kv2);
`endif
    // 귀납 보조 — 열린 걷기 ⇔ 유닛 busy ∨ 이번 사이클 done (a_ord_done 의 k-귀납에 필요하다)
    h_open: assert (f_open == (fps_io_oBusy || io_fp_done));
  end

`ifdef WT64TOPFP_COVER
  // W1 ← Wt64Top.fp_bind_order · a_ord_done · h_open — 걷기가 열린 동안 수락된 0xF08 읽기가 [1] = 1 을 본다 (전건의 반대 쪽 실재)
  // W2 ← Wt64Top.fp_bind_order · a_ord_done — 결속 기입 · 걷기 뒤 [1] = 0 읽기 (걷기가 그 사이클 앞에 끝났다)
  // W3 ← Wt64Top.fp_bind_order · a_ord_sel — en = 0 해제 뒤 [1] = 0 읽기와 *같은 사이클*(수락 사이클 r)에 접수된 그 열쇠 조회가 V = 0 을 본다 (a_ord_sel 둘째 항 — 검사 사이클 r + 1 의 f_rdPend ∧ [1] = 0 은 그 읽기 자신의 응답이다; W7 검증 V4-2 — 옛 식은 조회를 r + 1 에 두어 W6 과 같은 칸이었다)
  // W4 ← Wt64Top.fp_bind_order · a_ord_sel — 다른 슬롯으로의 en = 1 재결속 뒤 순서 잡힌 조회가 새 슬롯을 본다
  // W5 ← Wt64Top.fp_bind_order · a_ord_cap — 순서 잡힌 해제 뒤 조회의 걷기가 capAbsent 로 끝난다
  // W6 ← Wt64Top.fp_bind_order · a_ord_sel — en = 0 해제 뒤 [1] = 0 읽기의 *다음* 사이클(응답 사이클)에 접수된 그 열쇠 조회가 V = 0 을 본다 (f_ord 가 아직 0 인 r + 1)
  always @(posedge clk) if (f_step) begin
    w1_busy_rd:  cover ($past(rdSt && f_open && !io_fp_done) && io_mmio_rdata[1]);
    w2_done_rd:  cover ($past(rdSt && f_wr) && !io_mmio_rdata[1] && $past(f_open, 2));
    w3_rel_same: cover ($past(lookK && rdSt && f_wr && !bindK && !f_ord && f_rel) && f_rdPend && !io_mmio_rdata[1] && fpsx_selRd == 5'd0);
    w4_rebind:   cover ($past(lookK && f_ord && f_rb) && fpsx_selRd[4] && fpsx_selRd[3:0] == $past(f_ks));
    w5_cap:      cover (f_lo2 && !f_kv2 && $past(f_rel, 2) && io_fp_capAbsent);
    w6_gap:      cover ($past(lookK && f_rdPend && !io_mmio_rdata[1] && !f_ord && !bindK && !rdSt && f_rel) && fpsx_selRd == 5'd0);
  end
`endif
endmodule

bind Wt64Top wire [4:0] fpsx_selRd;
bind Wt64Top wire fpsx_initDone;
bind Wt64Top Wt64TopFp_props chk (.*);
