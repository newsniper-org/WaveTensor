// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// XlateStaging 후-formal 하네스 — 변환 저장소의 호스트 쪽 문 (파도 3, 2026-09-26).
// 선-formal 계약: rtl/formal/tla/XlateSurface.tla. 태스크:
// rtl/formal/sby/XlateStaging/props.sby (머리가 앵커 · 엔진 · 깊이를 소유한다).
//
// ## 부착 — AbortStaging_check 와 같은 래퍼다 (bind 없음)
//
// 대상이 담긴 Wt64Top.sv 는 모듈 스물을 담은 파일이라 「첫 endmodule 앞 주입」
// 관용구가 파일 순서에 매인다. 그래서 이 검사자가 대상을 **직접 인스턴스**하고
// 포트만 본다 — 단언이 top 모듈 본문에 살아 yosys 의 bind 묵살 함정이 없다.
//
// ## 오라클 — 모델의 스테이징 레지스터 `stg` 를 그림자로 든다
//
// 스테이징은 호스트에게 보이지 않는다 (두 워드 다 WO · 읽기 0). 그래서 그림자
// (f_sv · f_num · f_fr)가 모델 XlateSurface.tla 의 `stg` 를 그대로 옮긴다 —
// **갱신 원천은 수락된 LO 기입 하나뿐**이다. HI 커밋 · HI 거절 · 정지된 HI ·
// flush · MISS_CLEAR · RO 쓰기는 그림자를 건드리지 않는다. 이 한 규칙이 설계
// 판정 D-3 여섯 사실을 모두 싣는다: (1) 커밋이 스테이징을 소진하지 않는다 —
// 소진하는 DUT 는 같은 LO 로 온 두 번째 HI 에서 p_commit_iff 가 깨진다 ·
// (2) reset = 빈 스테이징 · (3) 거절은 기입이 아니다 · (4) flush 무관 · (5) LO 는
// 덮는다 · (6) 정지된 HI 는 아무것도 움직이지 않는다. DUT 의 스테이징과 그림자의
// 일치는 prove 엔진(abc pdr)이 귀납 불변식으로 스스로 찾는다 — 포트를 늘려
// 내부 상태를 드러내지 않는다 (호스트에게 보이지 않는 것이 이 계약의 성질이다).
//
// 기본 형상(파티션 4)의 생성물이라 형상 밖 파티션 가지는 elaborate 상수 False 다 —
// 그 가지는 이 태스크가 재지 않는다 (props.sby 「재지 않는 것」).
//
// 입력은 전부 자유다 — 두 구역 스트로브의 배타(상위 디코더가 보장한다)조차
// assume 으로 깔지 않는다. 아래 단언은 배타를 가정하지 않고 성립하도록 적었다.
//
// 정본 (좌표 뒤 「」 는 그 줄의 축자):
//   e-defined.typ:306 「스테이징 레지스터는 *항목 번호를 함께 래치*하고」
//   e-defined.typ:308 「기입이 항목 전체(스테이징 LO + 이 워드)를 *단일 에지에 커밋*한다」
//   e-defined.typ:321 「`[7:0]` 파티션 — *기입이 곧 발화*다 · `[31:8]` 예약 = 0 (엄격)」
//   e-defined.typ:329 「`[0]` 에 1 기입 = 미적중 sticky 해제 · `[31:1]` 예약 = 0 (엄격)」
//   e-defined.typ:202 「*RO 오프셋의 쓰기* — 거절 + loud fault 다」
//   e-defined.typ:419 「*조용한 무시는 금지다.*」
//
// 문체: yosys 개방판은 SVA 시퀀스를 받지 않으므로 즉시 단언(always + $past).
module XlateStaging_check (
  input logic        clk,
  input logic        reset,
  input logic        io_wrEnt,
  input logic        io_wrCtl,
  input logic [6:0]  io_woff,
  input logic [31:0] io_wdata,
  input logic        io_installReady
);
  // ENV: 기계는 reset 에서 시작한다. 이 하네스의 유일한 assume 이다.
  initial assume (reset);

  logic f_past_valid = 1'b0;
  logic f_past_reset = 1'b1;
  always @(posedge clk) begin
    f_past_valid <= 1'b1;
    f_past_reset <= reset;
  end
  wire f_step = f_past_valid && !reset && !f_past_reset;

  wire        io_commit_valid;
  wire [1:0]  io_commit_part;
  wire [3:0]  io_commit_idx;
  wire [27:0] io_commit_tag;
  wire [31:0] io_commit_frame;
  wire        io_commit_perm_r;
  wire        io_commit_perm_w;
  wire        io_commit_perm_x;
  wire        io_commit_v;
  wire        io_flush_valid;
  wire [1:0]  io_flush_part;
  wire        io_missClr;
  wire        io_badWrite;
  wire        io_needReady;

  XlateStaging dut (
    .io_wrEnt(io_wrEnt), .io_wrCtl(io_wrCtl), .io_woff(io_woff), .io_wdata(io_wdata),
    .io_installReady(io_installReady), .io_needReady(io_needReady),
    .io_commit_valid(io_commit_valid), .io_commit_part(io_commit_part),
    .io_commit_idx(io_commit_idx), .io_commit_tag(io_commit_tag),
    .io_commit_frame(io_commit_frame), .io_commit_perm_r(io_commit_perm_r),
    .io_commit_perm_w(io_commit_perm_w), .io_commit_perm_x(io_commit_perm_x),
    .io_commit_v(io_commit_v), .io_flush_valid(io_flush_valid),
    .io_flush_part(io_flush_part), .io_missClr(io_missClr), .io_badWrite(io_badWrite),
    .clk(clk), .reset(reset)
  );

  // ── 워드 디코드 — 정본 배치에서 다시 짓는다 (DUT 어휘를 재인용하지 않는다) ──
  wire       hi   = io_woff[0];             // addr[2]
  wire [5:0] num  = io_woff[6:1];           // addr[8:3] = {파티션, 색인}
  wire [4:0] cw   = io_woff[4:0];           // 0xE00 구역 안 워드 색인
  wire loWr   = io_wrEnt && !hi;
  wire hiWr   = io_wrEnt && hi;
  wire hiAcc  = hiWr && io_installReady;    // 하류가 받을 수 있는 HI 쓰기
  wire flWr   = io_wrCtl && (cw == 5'd0);   // 0xE00 XLATE_FLUSH
  wire mcWr   = io_wrCtl && (cw == 5'd4);   // 0xE10 XLATE_MISS_CLEAR
  wire roWr   = io_wrCtl && ((cw == 5'd1) || (cw == 5'd2) || (cw == 5'd3)); // 0xE04–0xE0C
  wire flOk   = (io_wdata[31:8] == 24'd0) && (io_wdata[7:0] < 8'd4);
  wire mcOk   = (io_wdata[31:1] == 31'd0);

  // ── 그림자 스테이징 — 모델의 stg. 갱신 원천은 수락된 LO 하나뿐 ──────────
  logic       f_sv  = 1'b0;
  logic [5:0] f_num = 6'd0;
  logic [31:0] f_fr = 32'd0;
  always @(posedge clk) begin
    if (reset) f_sv <= 1'b0;
    else if (loWr) begin
      f_sv  <= 1'b1;
      f_num <= num;
      f_fr  <= io_wdata;
    end
  end
  // 정본의 적법성 — SpecHiOK (모델): 스테이징이 차 있고 번호가 같다.
  wire hiLegal = f_sv && (f_num == num);
  // 거절은 하류 상태를 보지 않는다 — 적법하지 않은 HI 는 기다리지 않고 곧장 거절이다
  // (모델의 Refused(w) 는 ~DevHiBad(w) 를 전건에 든다: 정지는 적법 HI 에만).
  wire hiRej   = hiWr && !hiLegal;

`ifndef XLATESTG_COVER
  always @(*) if (f_step) begin
    // ── hi_fires · hi_entry_match · hi_needs_staging — 커밋의 전건 전수 ──
    // 수락된 적법한 HI ⇔ 커밋. 흡수 가지(적법한데 커밋 없음)도, 불일치·빈
    // 스테이징의 커밋도 이 등식이 막는다.
    p_commit_iff:    assert (io_commit_valid == (hiAcc && hiLegal));
    // ── hi_commit_whole · hi_v_carried(문 절반) — 한 번들이 항목 전체 ────
    // frame = 스테이징 LO · tag/perm/v = 이 HI 워드 · idx = 이 워드의 번호.
    // 권한 비트 배정 [30]=R · [29]=W · [28]=X 을 여기서 핀한다 (ABI 입력).
    p_commit_fields: assert (!io_commit_valid ||
                             (io_commit_frame == f_fr && io_commit_tag == io_wdata[27:0] &&
                              io_commit_perm_r == io_wdata[30] && io_commit_perm_w == io_wdata[29] &&
                              io_commit_perm_x == io_wdata[28] && io_commit_v == io_wdata[31] &&
                              io_commit_idx == num[3:0]));
    // part 는 valid 와 무관하게 그 기입의 번호다 — 상위의 install.ready(→ mmio
    // ready)가 *그 HI 의 파티션* 슬롯을 보게 하는 전제 (D-2).
    p_commit_part:   assert (io_commit_part == num[5:4]);
    // 하류 수락을 기다리는 쓰기 = 적법한 HI 쓰기 — 상위가 이것으로 mmio ready 를
    // 덮는다 (D-2). wdata 를 보지 않는다(오라클에 wdata 가 없다).
    p_need_iff:      assert (io_needReady == (hiWr && hiLegal));
    // ── lo_stages_only — LO 는 표에 닿는 출력을 하나도 세우지 않는다 ───────
    p_lo_quiet:      assert (!(loWr && !io_wrCtl) ||
                             (!io_commit_valid && !io_flush_valid && !io_missClr && !io_badWrite));
    // ── D-2 — 수락되지 않은(정지된) HI 는 아무것도 움직이지 않는다 ─────────
    p_stall_quiet:   assert (!(hiWr && hiLegal && !io_installReady && !io_wrCtl) ||
                             (!io_commit_valid && !io_flush_valid && !io_missClr && !io_badWrite));
    // ── flush_fires · flush_part_exists · flush_rsv_strict ──────────────────
    p_flush_iff:     assert (io_flush_valid == (flWr && flOk));
    // ── flush_scoped — 발화는 파티션 하나, 그 기입의 [7:0] 그 자체 ──────────
    p_flush_part:    assert (!io_flush_valid || io_flush_part == io_wdata[1:0]);
    // ── mclr_fires · mclr_needs_one · mclr_rsv_strict — 0xE10 의 해제 발화 ──
    p_missclr_iff:   assert (io_missClr == (mcWr && mcOk && io_wdata[0]));
    // ── reject_loud — 거절 사건의 전수 = badWrite (두 방향) ────────────────
    // 조용한 거절(⇐ 방향)도 허위 fault(⇒ 방향)도 이 등식이 막는다. 하류 거부는
    // 거절이 아니다 — 적법 HI 는 installReady 가 0 이어도 badWrite 에 들지 않는다.
    p_bad_iff:       assert (io_badWrite == (hiRej || (flWr && !flOk) || (mcWr && !mcOk) || roWr));
  end

  always @(posedge clk) if (f_step) begin
    // ── D-3 (1) 의 관측형 — 커밋은 스테이징을 소진하지 않는다 ──────────────
    // 직전 사이클의 커밋 뒤, LO 없이 같은 번호의 HI 가 수락되면 다시 커밋된다
    // (그림자가 그대로이므로 p_commit_iff 의 귀결이지만, 판정 D-3 (1) 의 문장을
    // 따로 세운다 — 다음 사람이 이 파일에서 찾는 것은 그 문장이다).
    // (커밋 사이클에는 LO 가 없다 — 한 스트로브가 한 워드다 — 그래서 직전 커밋의
    // 번호가 곧 지금의 스테이징 번호다.)
    t_no_drain: assert (!($past(io_commit_valid) && hiAcc && ($past(num) == num)) || io_commit_valid);
  end
`endif

  // ── cover 증인 — 공허 아님의 증거 (전부 reset 기점) ───────────────────────
`ifdef XLATESTG_COVER
  // W1 ← XlateSurface.hi_fires · XlateSurface.hi_commit_whole · p_commit_iff — LO 로 실은 비0 프레임이 HI 로 커밋된다
  always @(posedge clk) if (f_step) w1_commit: cover (io_commit_valid && io_commit_frame != 32'd0 && io_commit_v);
  // W2 ← XlateSurface.hi_entry_match · XlateSurface.reject_loud — 스테이징된 번호와 다른 항목의 HI 가 거절되고 loud 다
  always @(posedge clk) if (f_step) w2_mismatch: cover (hiWr && f_sv && (f_num != num) && io_badWrite && !io_commit_valid);
  // W3 ← XlateSurface.hi_needs_staging — reset 뒤 LO 없이 온 HI (래치 번호 reset 값 0 과 같은 항목 0) 가 거절된다
  always @(posedge clk) if (f_step) w3_unstaged: cover (hiWr && !f_sv && (num == 6'd0) && io_badWrite);
  // W4 ← XlateSurface.hi_v_carried · p_commit_fields — V=0 커밋 (단일 항목 무효화)
  always @(posedge clk) if (f_step) w4_v0_commit: cover (io_commit_valid && !io_commit_v);
  // W5 ← XlateSurface.lo_stages_only · p_lo_quiet — 이미 찬 스테이징을 다른 프레임의 LO 가 덮고, 조용하다
  always @(posedge clk) if (f_step) w5_lo_over: cover (loWr && !io_wrCtl && f_sv && (io_wdata != f_fr) && !io_badWrite);
  // W6 ← XlateSurface.flush_fires · XlateSurface.flush_scoped · p_flush_iff — 파티션 3 flush 발화
  always @(posedge clk) if (f_step) w6_flush3: cover (io_flush_valid && io_flush_part == 2'd3);
  // W7 ← XlateSurface.flush_part_exists · XlateSurface.reject_loud — 예약은 0 인데 [7:0]=4 (없는 파티션) — 절단 별칭 없이 거절
  always @(posedge clk) if (f_step) w7_phantom: cover (flWr && io_wdata == 32'd4 && io_badWrite && !io_flush_valid);
  // W8 ← XlateSurface.flush_rsv_strict · XlateSurface.reject_loud — 실재 파티션이지만 [31:8] 비0
  always @(posedge clk) if (f_step) w8_rsv: cover (flWr && io_wdata[31:8] != 24'd0 && io_wdata[7:0] < 8'd4 && io_badWrite && !io_flush_valid);
  // W9 ← XlateSurface.hi_fires · t_no_drain — 같은 LO 로 HI 두 번 — 둘 다 커밋 (소진 없음, D-3 (1))
  always @(posedge clk) if (f_step) w9_recommit: cover (io_commit_valid && $past(io_commit_valid) && ($past(num) == num));
  // W10 ← XlateStaging.stall_quiet · p_stall_quiet · p_need_iff — 적법한 HI 가 하류 거부로 정지한다 (아무것도 움직이지 않는다)
  always @(posedge clk) if (f_step) w10_stall: cover (hiWr && !io_installReady && hiLegal && !io_wrCtl);
  // W11 ← XlateSurface.ro_rejected · XlateSurface.reject_loud · p_bad_iff — RO 워드(0xE08) 쓰기가 거절되고 아무것도 세우지 않는다
  always @(posedge clk) if (f_step) w11_ro_wr:    cover (io_wrCtl && cw == 5'd2 && io_badWrite && !io_missClr && !io_flush_valid);
  // W12 ← XlateSurface.mclr_fires · XlateSurface.mclr_keeps_stall · p_missclr_iff — 적법한 해제가 발화하고 커밋·flush·거절이 없다
  always @(posedge clk) if (f_step) w12_missclr:  cover (io_missClr && !io_commit_valid && !io_flush_valid && !io_badWrite);
  // W13 ← XlateSurface.mclr_needs_one · p_missclr_iff · p_bad_iff — [0]=0 · 예약 0 의 0xE10 기입이 조용히 수락된다 (해제도 거절도 없음)
  always @(posedge clk) if (f_step) w13_mclr_zero: cover (mcWr && io_wdata == 32'd0 && !io_missClr && !io_badWrite);
  // W14 ← XlateSurface.mclr_rsv_strict · XlateSurface.reject_loud — [0]=1 이지만 [31:1] 비0 인 해제가 거절되고 발화하지 않는다
  always @(posedge clk) if (f_step) w14_mclr_rsv: cover (mcWr && io_wdata[0] && io_wdata[31:1] != 31'd0 && io_badWrite && !io_missClr);
`endif
endmodule
