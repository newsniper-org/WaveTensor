// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// XlateStaging 후-formal 하네스 — 변환 저장소의 호스트 쪽 문, `0xC00` 형상 비노출 항목 표면
// (3.10 v1.0 묶음 RTL 파도 W3, 2026-10-13 전면 재작성 — 앞판은 호스트가 색인을 고르는 LO/HI
// 직접 배열의 문이었다(파도 3 · 4, 2026-09-26). 그 표면은 정본에서 사라졌다).
// 선-formal 계약: rtl/formal/tla/XlateSurface.tla (W3 재작성 — 가드 스물아홉). 태스크 둘 — 머리가
// 앵커 · 엔진 · 깊이를 소유한다:
//   rtl/formal/sby/XlateStaging/props.sby  기본 형상(파티션 4) — Wt64Top.sv 안의 문
//   rtl/formal/sby/XlateStaging/p2.sby     상한 아래 형상(파티션 2) — XlateStagingP2.sv,
//                                           매크로 XLATESTG_P2 (아래 「형상」)
// 문 → 저장 끝-끝(커밋 뒤 적중 · V=0 미적중 · 정지 유계)은 이 태스크가 아니라
// rtl/formal/sby/XlateDoor/door.sby (XlateDoor_props.sv) 다.
//
// ## 부착 — AbortStaging_check 와 같은 래퍼다 (bind 없음)
//
// 대상이 담긴 Wt64Top.sv 는 모듈 스물을 담은 파일이라 「첫 endmodule 앞 주입」
// 관용구가 파일 순서에 매인다. 그래서 이 검사자가 대상을 **직접 인스턴스**하고
// 포트만 본다 — 단언이 top 모듈 본문에 살아 yosys 의 bind 묵살 함정이 없다.
//
// ## 오라클 — 모델의 스테이징 `stg = [vv, fv, p, vpn, fr]` 를 그림자로 든다
//
// 스테이징은 호스트에게 보이지 않는다 (네 워드 다 WO · 읽기 0). 그래서 그림자
// f_vv(VPN 유효) · f_fv(FRAME 유효) · f_lp(래치 파티션) · f_vpn · f_fr 가 모델 XlateSurface.tla 의
// `stg` 를 그대로 옮긴다 — 갱신 원천은 넷뿐이다:
//   수락된 VPN    (기저 실재)                 vv := 1 · fv := 0 · lp := p · vpn := wdata   (f) 1항
//   수락된 FRAME  (래치 기저 ∧ VPN 유효)      fv := 1 · fr := wdata                       (f) 2항
//   수락된 VPN_HI (래치 기저 ∧ VPN 유효 ∧ 0)  fv := 0                                     :308
//   래치 파티션의 *수락된* XLATE_FLUSH        vv := 0 · fv := 0 (값은 남는다)              (f) 7항
// COMMIT(커밋 · 거절 · 정지 어느 것이든) · 거절된 기입 · 다른 파티션의 flush · MISS_CLEAR ·
// RO 쓰기는 그림자를 건드리지 않는다 — e-defined.typ:306 「커밋은 스테이징을 소진하지 않는다」.
// 두 구역 스트로브가 같은 사이클에 서면 (조립에서는 주소 디코드로 배타 — 문 단독은 자유 입력)
// VPN 이 flush 를 이기고(직렬화 flush → VPN) flush 가 FRAME · VPN_HI 를 이긴다(직렬화
// FRAME → flush) — 이 하네스가 그 선택을 핀한다 (RTL 지도의 flushDrop = flush.valid ∧ ¬vpnOk ∧ …).
// DUT 의 스테이징과 그림자의 일치는 prove 엔진(abc pdr)이 귀납 불변식으로 스스로 찾는다 — 포트를
// 늘려 내부 상태를 드러내지 않는다 (호스트에게 보이지 않는 것이 이 계약의 성질이다). DUT 의
// 레지스터 이름(stgVpnValid …)은 이 파일에 한 번도 나오지 않는다.
//
// ## 판정 — 정지는 주소 · 스테이징 상태만 본다 (모델 RefuseDomain = "addrstate")
//
//   cmLegal = COMMIT ∧ 기저 실재 ∧ f_vv ∧ f_lp == p     — 주소 · 상태 적법 (정지 대상)
//   cmBad   = wdata[27:0] ≠ 0 ∨ (wdata[31] ∧ ¬f_fv)      — 데이터 사유 (V=0 의 [30:28] 은 항이 아니다 — DP-20)
//   needReady ⇔ cmLegal                                   — 오라클에 wdata 가 없다 (p_need_iff)
//   commit.valid ⇔ cmLegal ∧ installReady ∧ ¬cmBad        (p_commit_iff)
//   badData ⇔ cmLegal ∧ installReady ∧ cmBad               — *수락 사이클*의 거절 (p_baddata_iff)
//   badWrite ⇔ 주소 · 상태 사유 거절 (정지 없이 곧장)      (p_bad_iff)
// 데이터 사유 거절이 badWrite 가 아니라 별도 출력 badData 인 것은 DP-15 다: 그 콘에
// installReady(조립의 절단 핀 hiu__installSlotFree)가 들어오므로 조립 sticky surfBadWr 이 아니라
// 원천별 sticky → FAULT_STATUS [6] 합류로 간다 (fpBindArea 선례). 그 결선은 Wt64Top/assembly.sby.
//
// ## 형상 — 매크로 XLATESTG_P2 (판정 T4 (ii))
//
// 기본 형상(파티션 4)의 생성물에서는 형상 밖 기저 가지가 elaborate 상수 False 라
// props.sby 가 그 가지를 재지 못한다. p2.sby 가 `-DXLATESTG_P2` 로 이 하네스를
// 파티션 2 판(XlateStagingP2 — GenXlateStaging)에 붙인다. 매크로가 바꾸는 것은
// 형상 상수(PARTS · 파티션 포트 폭 PW)와 대상 모듈 이름, 그리고 형상 밖 기저가
// 실재하는 형상에서만 뜻이 있는 단언 하나(p_ent_phantom)와 증인 셋(W27–W29)이다.
// 나머지 단언은 두 형상에서 *같은 문면*이다: ePh 는 기본 형상에서 0 으로 접힌다.
//
// 입력은 전부 자유다 — 두 구역 스트로브의 배타(상위 디코더가 보장한다)조차
// assume 으로 깔지 않는다.
//
// 정본 (좌표 뒤 「」 는 그 줄의 축자):
//   e-defined.typ:305 「수락된 기입이 그 주소의 파티션을 래치한다」
//   e-defined.typ:306 「래치 파티션의 기저에서만 수락한다」
//   e-defined.typ:306 「커밋은 스테이징을 소진하지 않는다」
//   e-defined.typ:308 「`[27:0]` 예약 = 0 (엄격)」
//   e-defined.typ:308 「기다리지 않고 곧장 거절 + `[6]` 이다」
//   e-defined.typ:308 「수락 사이클에 거절된다 — 그 수락은 위 유계 정지 뒤일 수 있다」
//   e-defined.typ:308 「비0 기입은 거절 + `[6]` · 스테이징 불변이며」
//   e-defined.typ:308 「수락된 VPN_HI 기입은 FRAME 스테이징 유효를 내린다.」
//   e-defined.typ:308 「*표의 워드로 등재한다* — 쓰기는 거절 + `[6]`, 읽기는 0」
//   e-defined.typ:311 「VPN 기입은 기입 주소의 파티션을 래치하고 FRAME 스테이징 유효를 내린다」
//   e-defined.typ:311 「V=1 COMMIT 은 *FRAME 유효*를 요구한다」
//   e-defined.typ:311 「V=0 COMMIT 은 VPN 유효만 요구한다」
//   e-defined.typ:311 「래치 파티션에 대한 *수락된* flush 가 두 스테이징 유효를 모두 내린다」
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
`ifdef XLATESTG_P2
  localparam PARTS = 2;   // 형상 파티션 수 — 인코딩 상한(4) 아래
  localparam PW    = 1;   // commit.part · flush.part 포트 폭 = log2Up(PARTS) max 1
`else
  localparam PARTS = 4;   // 인코딩 상한 — addr[8:7] 이 전부 실재 파티션
  localparam PW    = 2;
`endif
  // ENV: 기계는 reset 에서 시작한다. 이 하네스의 유일한 assume 이다.
  initial assume (reset);

  logic f_past_valid = 1'b0;
  logic f_past_reset = 1'b1;
  always @(posedge clk) begin
    f_past_valid <= 1'b1;
    f_past_reset <= reset;
  end
  wire f_step = f_past_valid && !reset && !f_past_reset;

  wire          io_commit_valid;
  wire [PW-1:0] io_commit_part;
  wire [31:0]   io_commit_vpn;
  wire [31:0]   io_commit_frame;
  wire          io_commit_perm_r;
  wire          io_commit_perm_w;
  wire          io_commit_perm_x;
  wire          io_commit_v;
  wire          io_flush_valid;
  wire [PW-1:0] io_flush_part;
  wire          io_missClr;
  wire          io_badWrite;
  wire          io_badData;
  wire          io_needReady;

`ifdef XLATESTG_P2
  XlateStagingP2 dut (
`else
  XlateStaging dut (
`endif
    .io_wrEnt(io_wrEnt), .io_wrCtl(io_wrCtl), .io_woff(io_woff), .io_wdata(io_wdata),
    .io_installReady(io_installReady), .io_needReady(io_needReady),
    .io_commit_valid(io_commit_valid), .io_commit_part(io_commit_part),
    .io_commit_vpn(io_commit_vpn),
    .io_commit_frame(io_commit_frame), .io_commit_perm_r(io_commit_perm_r),
    .io_commit_perm_w(io_commit_perm_w), .io_commit_perm_x(io_commit_perm_x),
    .io_commit_v(io_commit_v), .io_flush_valid(io_flush_valid),
    .io_flush_part(io_flush_part), .io_missClr(io_missClr), .io_badWrite(io_badWrite),
    .io_badData(io_badData),
    .clk(clk), .reset(reset)
  );

  // ── 워드 디코드 — 정본 배치에서 다시 짓는다 (DUT 어휘를 재인용하지 않는다) ──
  // 항목 구역 0xC00 + (p≪7): addr[8:7] = 파티션 · addr[6:2] = 기저 안 워드 색인.
  // woff = addr[8:2] 이므로 p = woff[6:5] · w = woff[4:0].
  wire [1:0] p    = io_woff[6:5];
  wire [4:0] w    = io_woff[4:0];
  wire [4:0] cw   = io_woff[4:0];           // 0xE00 구역 안 워드 색인
  // 형상 밖 파티션의 기저 (판정 T4) — 기본 형상에서 상수 0.
  wire ePh    = (p >= PARTS);
  wire vpnW   = io_wrEnt && (w == 5'd0);    // +0x00 XLATE_ENTRY_VPN
  wire frW    = io_wrEnt && (w == 5'd1);    // +0x04 XLATE_ENTRY_FRAME
  wire cmW    = io_wrEnt && (w == 5'd2);    // +0x08 XLATE_ENTRY_COMMIT
  wire vhW    = io_wrEnt && (w == 5'd3);    // +0x0C XLATE_ENTRY_VPN_HI
  wire rsW    = io_wrEnt && (w >= 5'd4);    // +0x10..+0x7C 예약-엄격 28 워드
  wire flWr   = io_wrCtl && (cw == 5'd0);   // 0xE00 XLATE_FLUSH
  wire mcWr   = io_wrCtl && (cw == 5'd4);   // 0xE10 XLATE_MISS_CLEAR
  wire roWr   = io_wrCtl && ((cw == 5'd1) || (cw == 5'd2) || (cw == 5'd3)); // 0xE04–0xE0C
  wire flOk   = (io_wdata[31:8] == 24'd0) && (io_wdata[7:0] < PARTS);
  wire mcOk   = (io_wdata[31:1] == 31'd0);

  // ── 그림자 스테이징 — 모델의 stg ───────────────────────────────────────
  logic        f_vv  = 1'b0;
  logic        f_fv  = 1'b0;
  logic [1:0]  f_lp  = 2'd0;
  logic [31:0] f_vpn = 32'd0;
  logic [31:0] f_fr  = 32'd0;
  wire pairOk = !ePh && f_vv && (f_lp == p);          // 래치 기저 ∧ VPN 유효
  wire vpnAcc = vpnW && !ePh;
  wire frAcc  = frW && pairOk;
  wire vhAcc  = vhW && pairOk && (io_wdata == 32'd0);
  wire flDrop = flWr && flOk && (io_wdata[1:0] == f_lp) && !vpnAcc;
  always @(posedge clk) begin
    if (reset) begin
      f_vv <= 1'b0;
      f_fv <= 1'b0;
    end else begin
      if (vpnAcc) begin
        f_vv  <= 1'b1;
        f_fv  <= 1'b0;
        f_lp  <= p;
        f_vpn <= io_wdata;
      end
      if (frAcc) begin
        f_fv  <= 1'b1;
        f_fr  <= io_wdata;
      end
      if (vhAcc) f_fv <= 1'b0;
      if (flDrop) begin          // flush 가 같은 사이클의 FRAME · VPN_HI 를 이긴다 (머리 「오라클」)
        f_vv <= 1'b0;
        f_fv <= 1'b0;
      end
    end
  end
  // 정본 판정 — 주소 · 상태 적법(정지 대상) · 데이터 사유 · 수락.
  wire cmLegal = cmW && pairOk;
  wire cmBad   = (io_wdata[27:0] != 28'd0) || (io_wdata[31] && !f_fv);
  wire cmAcc   = cmLegal && io_installReady;
  // 주소 · 상태 사유 — 하류 상태를 보지 않고 곧장 거절이다.
  wire entRej  = (io_wrEnt && ePh) || (frW && !pairOk) || (cmW && !pairOk) ||
                 (vhW && !(pairOk && io_wdata == 32'd0)) || rsW;
  wire stageW  = vpnAcc || frAcc || vhAcc;            // 스테이징만 움직이는 수락된 기입

`ifndef XLATESTG_COVER
  always @(*) if (f_step) begin
    // ── commit_fires · commit_base_match · commit_needs_vpn · commit_needs_frame ·
    //    commit_rsv_strict — 커밋의 전건 전수 ────────────────────────────
    // 수락된(installReady) 주소 · 상태 적법 COMMIT 중 데이터가 적법한 것 ⇔ 커밋. 흡수 가지도,
    // 다른 기저 · VPN 없음 · FRAME 없는 V=1 · [27:0] 비0 의 커밋도 이 등식이 막는다.
    p_commit_iff:    assert (io_commit_valid == (cmAcc && !cmBad));
    // ── commit_whole · commit_v_carried(문 절반) — 한 번들이 항목 전체 ─────
    // vpn = 스테이징 VPN · frame = 스테이징 FRAME(V=1 일 때 — V=0 의 프레임은 관측 불가) ·
    // perm · v = 이 COMMIT 워드. 권한 비트 배정 [30]=R · [29]=W · [28]=X 을 여기서 핀한다.
    p_commit_fields: assert (!io_commit_valid ||
                             (io_commit_vpn == f_vpn &&
                              io_commit_perm_r == io_wdata[30] && io_commit_perm_w == io_wdata[29] &&
                              io_commit_perm_x == io_wdata[28] && io_commit_v == io_wdata[31] &&
                              (!io_commit_v || io_commit_frame == f_fr)));
    // part 는 래치 파티션이다 — 주소 · 상태 적법 COMMIT 의 사이클이면 valid · installReady 와
    // 무관하게 (상위의 installSlotFree 가 *그 COMMIT 의 파티션* 슬롯을 보게 하는 전제).
    // 그 사이클에는 p == f_lp 이므로 주소 기저와도 같다.
    p_commit_part:   assert (!cmLegal || io_commit_part == f_lp[PW-1:0]);
    // ── 하류 수락을 기다리는 쓰기 = 주소 · 상태로 적법한 COMMIT — 데이터 필드 무관 ──
    // 오라클에 wdata 가 없다: 모델 Prop_StallDataBlind(⇐ — 데이터 사유도 정지를 받는다)와
    // Prop_AddrRejectNoWait(⇒ — 주소 · 상태 사유는 정지하지 않는다)의 RTL 쪽.
    p_need_iff:      assert (io_needReady == cmLegal);
    // ── 데이터 사유는 *수락 사이클*에 거절 (badData — 원천별 sticky 로 간다) ─────
    p_baddata_iff:   assert (io_badData == (cmAcc && cmBad));
    // ── frame_stages_only — VPN · FRAME · VPN_HI 는 표에 닿는 출력을 하나도 세우지 않는다 ──
    p_stage_quiet:   assert (!(stageW && !io_wrCtl) ||
                             (!io_commit_valid && !io_flush_valid && !io_missClr &&
                              !io_badWrite && !io_badData));
    // ── 정지된 COMMIT 은 아무것도 움직이지 않는다 (:308 「정지 중에는 효과가 없고」) ──
    p_stall_quiet:   assert (!(cmLegal && !io_installReady && !io_wrCtl) ||
                             (!io_commit_valid && !io_flush_valid && !io_missClr &&
                              !io_badWrite && !io_badData));
    // ── flush_fires · flush_part_exists · flush_rsv_strict ──────────────────
    p_flush_iff:     assert (io_flush_valid == (flWr && flOk));
    // ── flush_scoped — 발화는 파티션 하나, 그 기입의 [7:0] 그 자체 ──────────
    p_flush_part:    assert (!io_flush_valid || io_flush_part == io_wdata[PW-1:0]);
    // ── mclr_fires · mclr_needs_one · mclr_rsv_strict — 0xE10 의 해제 발화 ──
    p_missclr_iff:   assert (io_missClr == (mcWr && mcOk && io_wdata[0]));
    // ── reject_loud — 주소 · 상태 사유 거절 사건의 전수 = badWrite (두 방향) ────
    // 기저 없음 · 짝 불일치 FRAME · VPN 없는/다른 기저 COMMIT · VPN_HI 비0 또는 짝 불일치 ·
    // 예약-엄격 28 워드 · flush 예약/없는 값 · MISS_CLEAR 예약 · RO 쓰기. 하류 거부는 거절이
    // 아니다 — 적법 COMMIT 은 installReady 가 0 이어도 badWrite 에 들지 않고, 데이터 사유는
    // badData(위)다.
    p_bad_iff:       assert (io_badWrite == (entRej || (flWr && !flOk) || (mcWr && !mcOk) || roWr));
`ifdef XLATESTG_P2
    // ── ent_part_exists — 형상 밖 기저의 *어느 워드든* 거절 + badWrite 이고 커밋 · 정지 ·
    // 데이터 거절이 없다. 스테이징 부동은 그림자 갱신 규칙(vpnAcc 가 ¬ePh 를 요구)과
    // p_commit_iff 가 잰다 — 형상 밖 VPN 을 스테이징하는 DUT 는 앞서 래치된 실재 기저의
    // COMMIT 에서 p_commit_iff 가 깨진다.
    p_ent_phantom:   assert (!(io_wrEnt && ePh) ||
                             (io_badWrite && !io_commit_valid && !io_needReady && !io_badData));
`endif
  end

  always @(posedge clk) if (f_step) begin
    // ── 커밋은 스테이징을 소진하지 않는다 (:306) — 관측형 ─────────────────
    // 직전 사이클이 커밋이고 지금 같은 기저의 COMMIT 이 수락되며 데이터가 적법하면(V=1 은
    // 직전 커밋도 V=1 — 그때 FRAME 유효가 서 있었다) 다시 커밋된다. 그림자의 귀결이지만
    // 문장을 따로 세운다 — 다음 사람이 이 파일에서 찾는 것은 그 문장이다.
    t_no_drain: assert (!($past(io_commit_valid) && cmW && (p == $past(p)) && io_installReady &&
                          (io_wdata[27:0] == 28'd0) && (!io_wdata[31] || $past(io_commit_v))) ||
                        io_commit_valid);
    // ── flush_drops_staging 의 관측형 (판정 T5 (a) · (f) 7항) ─────────────
    // 직전 사이클에 파티션 q 의 flush 가 수락됐고(같은 사이클 VPN 없음) 지금 기저 q 의
    // FRAME · COMMIT · VPN_HI 가 오면, 스테이징이 무엇을 들고 있었든 거절 + badWrite 이고
    // 커밋 · 정지 · 데이터 거절이 없다. 그림자에 기대지 않는 문장이다.
    t_flush_ends: assert (!($past(flWr && flOk && !vpnAcc) && ($past(io_wdata[1:0]) == p) &&
                            (frW || cmW || vhW)) ||
                          (io_badWrite && !io_commit_valid && !io_needReady && !io_badData));
    // ── vpn_drops_frame · commit_needs_frame 의 관측형 ─────────────────────
    // 직전 사이클에 VPN(또는 0 의 VPN_HI)이 수락됐으면 지금 같은 기저의 V=1 COMMIT 은 커밋되지
    // 않는다 — 묶을 FRAME 이 없다(정지했다면 정지, 수락됐다면 badData). 직전 사이클에 제어
    // 구역 스트로브가 함께 섰으면(문 단독의 자유 입력 — 조립에서는 배타) 전건에서 뺀다.
    t_vpn_drops: assert (!($past((vpnAcc || vhAcc) && !io_wrCtl) && cmW && (p == $past(p)) && io_wdata[31]) ||
                         (!io_commit_valid && (!io_installReady || io_badData)));
  end
`endif

  // ── cover 증인 — 공허 아님의 증거 (전부 reset 기점) ───────────────────────
  // 기본 형상(props.sby)은 W1–W26, 상한 아래 형상(p2.sby)은 W27–W29 만 컴파일한다 — 증인의
  // 대상 가드는 그 태스크가 앵커를 세운 가드여야 하고(lint_witness_map (3)), p2.sby 의
  // 앵커는 형상에 매인 둘(ent_part_exists · flush_part_exists)뿐이다.
  // 거절(badWrite)이나 데이터 거절을 전건에 쓰는 증인은 다른 구역의 스트로브를 끈다 (!io_wrCtl /
  // !io_wrEnt — 조립에서는 디코드로 배타). 자유 입력의 동시 스트로브가 다른 구역의 거절로 증인을
  // 채우면 그 증인은 결함 자체에 매이지 않는다 — W3 통합 실측에서 RO_OK · VH_ANY · FLUSH_KEEPS ·
  // P2_PH_NOREJ 변이 아래 W11 · W20 · W15 · W27 이 그 구멍으로 도달했다 (props.sby 「W3」 절).
`ifdef XLATESTG_COVER
`ifndef XLATESTG_P2
  // W1 ← XlateSurface.commit_fires · XlateSurface.commit_whole · p_commit_iff · p_commit_fields — VPN · FRAME 로 실은 비0 프레임이 V=1 COMMIT 으로 커밋된다
  always @(posedge clk) if (f_step) w1_commit: cover (io_commit_valid && io_commit_frame != 32'd0 && io_commit_v && io_commit_vpn != 32'd0);
  // W2 ← XlateSurface.commit_base_match · XlateSurface.reject_loud · p_bad_iff — 래치 파티션과 다른 기저의 COMMIT 이 곧장 거절되고 loud 다 (정지 없음)
  always @(posedge clk) if (f_step) w2_mismatch: cover (cmW && !io_wrCtl && f_vv && (f_lp != p) && io_badWrite && !io_commit_valid && !io_needReady);
  // W3 ← XlateSurface.commit_needs_vpn · p_bad_iff — reset 뒤 VPN 없이 온 COMMIT(래치 파티션 reset 값 0 과 같은 기저 0)이 거절된다
  always @(posedge clk) if (f_step) w3_unstaged: cover (cmW && !io_wrCtl && !f_vv && (p == 2'd0) && io_badWrite && !io_needReady);
  // W4 ← XlateSurface.commit_v_carried · p_commit_fields — V=0 커밋 (단일 항목 무효화 — FRAME 없이도)
  always @(posedge clk) if (f_step) w4_v0_commit: cover (io_commit_valid && !io_commit_v && !f_fv);
  // W5 ← XlateSurface.frame_stages_only · XlateSurface.vpn_drops_frame · p_stage_quiet — FRAME 까지 찬 스테이징을 다른 VPN 이 덮고, 조용하다
  always @(posedge clk) if (f_step) w5_vpn_over: cover (vpnW && !io_wrCtl && f_vv && f_fv && (io_wdata != f_vpn) && !io_badWrite);
  // W6 ← XlateSurface.flush_fires · XlateSurface.flush_scoped · p_flush_iff — 마지막 실재 파티션(PARTS-1) flush 발화
  always @(posedge clk) if (f_step) w6_flush3: cover (io_flush_valid && io_flush_part == (PARTS - 1));
  // W7 ← XlateSurface.flush_part_exists · XlateSurface.reject_loud — 예약은 0 인데 [7:0]=4 (없는 파티션) — 절단 별칭 없이 거절
  always @(posedge clk) if (f_step) w7_phantom: cover (flWr && !io_wrEnt && io_wdata == 32'd4 && io_badWrite && !io_flush_valid);
  // W8 ← XlateSurface.flush_rsv_strict · XlateSurface.reject_loud — 실재 파티션이지만 [31:8] 비0
  always @(posedge clk) if (f_step) w8_rsv: cover (flWr && !io_wrEnt && io_wdata[31:8] != 24'd0 && io_wdata[7:0] < PARTS && io_badWrite && !io_flush_valid);
  // W9 ← XlateSurface.commit_fires · t_no_drain — 같은 스테이징으로 COMMIT 두 번 — 둘 다 커밋 (소진 없음, :306)
  always @(posedge clk) if (f_step) w9_recommit: cover (io_commit_valid && $past(io_commit_valid) && io_commit_v && $past(io_commit_v));
  // W10 ← XlateStaging.stall_quiet · p_stall_quiet · p_need_iff — 적법한 COMMIT 이 하류 거부로 정지한다 (아무것도 움직이지 않는다)
  always @(posedge clk) if (f_step) w10_stall: cover (cmLegal && !io_installReady && !io_wrCtl && io_needReady && !cmBad);
  // W11 ← XlateSurface.ro_rejected · XlateSurface.reject_loud · p_bad_iff — RO 워드(0xE08) 쓰기가 거절되고 아무것도 세우지 않는다
  always @(posedge clk) if (f_step) w11_ro_wr:    cover (io_wrCtl && !io_wrEnt && cw == 5'd2 && io_badWrite && !io_missClr && !io_flush_valid);
  // W12 ← XlateSurface.mclr_fires · XlateSurface.mclr_keeps_stall · p_missclr_iff — 적법한 해제가 발화하고 커밋 · flush · 거절이 없다
  always @(posedge clk) if (f_step) w12_missclr:  cover (io_missClr && !io_commit_valid && !io_flush_valid && !io_badWrite);
  // W13 ← XlateSurface.mclr_needs_one · p_missclr_iff · p_bad_iff — [0]=0 · 예약 0 의 0xE10 기입이 조용히 수락된다 (해제도 거절도 없음)
  always @(posedge clk) if (f_step) w13_mclr_zero: cover (mcWr && io_wdata == 32'd0 && !io_missClr && !io_badWrite);
  // W14 ← XlateSurface.mclr_rsv_strict · XlateSurface.reject_loud — [0]=1 이지만 [31:1] 비0 인 해제가 거절되고 발화하지 않는다
  always @(posedge clk) if (f_step) w14_mclr_rsv: cover (mcWr && !io_wrEnt && io_wdata[0] && io_wdata[31:1] != 31'd0 && io_badWrite && !io_missClr);
  // W15 ← XlateSurface.flush_drops_staging · XlateSurface.commit_needs_vpn · p_commit_iff · t_flush_ends — 직전 사이클의 수락된 flush 가 래치 파티션의 두 유효를 내렸고, 같은 기저의 V=1 COMMIT 이 거절 + badWrite 이고 커밋이 없다
  always @(posedge clk) if (f_step) w15_flush_ends: cover (cmW && !io_wrCtl && io_wdata[31] && $past(f_vv && f_fv) && !f_vv && !f_fv && $past(flWr) && (f_lp == p) && io_badWrite && !io_commit_valid);
  // W16 ← XlateSurface.flush_drops_staging · p_commit_iff — 직전 사이클의 수락된 flush 가 *다른* 파티션이었고 스테이징이 남아, 그 기저의 V=1 COMMIT 이 커밋된다 (전역 비움이 아니다)
  always @(posedge clk) if (f_step) w16_other_keeps: cover (io_commit_valid && io_commit_v && $past(flWr && flOk && f_vv && !io_wrEnt) && ($past(io_wdata[1:0]) != p));
  // W17 ← XlateSurface.vpn_drops_frame · XlateSurface.commit_needs_frame · t_vpn_drops · p_baddata_iff — VPN · FRAME · VPN 뒤 V=1 COMMIT 이 수락 사이클에 데이터 사유로 거절된다 (묵은 프레임이 새 VPN 에 묶이지 않는다)
  always @(posedge clk) if (f_step) w17_vpn_drops: cover (cmAcc && io_wdata[31] && (io_wdata[27:0] == 28'd0) && !f_fv && $past(vpnAcc && f_fv) && io_badData && !io_commit_valid);
  // W18 ← XlateSurface.commit_needs_frame · XlateSurface.reject_loud · p_baddata_iff — FRAME 없이 VPN 만 래치한 채 V=1 COMMIT 이 수락되면 badData 이고 커밋이 없다 (badWrite 아님)
  always @(posedge clk) if (f_step) w18_no_frame: cover (cmAcc && io_wdata[31] && (io_wdata[27:0] == 28'd0) && !f_fv && io_badData && !io_badWrite);
  // W19 ← XlateSurface.frame_pair_check · XlateSurface.reject_loud · p_bad_iff — 래치와 다른 기저의 FRAME 이 거절되고 스테이징을 쓰지 않는다
  always @(posedge clk) if (f_step) w19_frame_pair: cover (frW && !io_wrCtl && f_vv && (f_lp != p) && io_badWrite);
  // W20 ← XlateSurface.vpnhi_strict · XlateSurface.reject_loud · p_bad_iff — 래치 기저의 비0 VPN_HI 가 거절된다 (FRAME 유효 부동)
  always @(posedge clk) if (f_step) w20_vpnhi_bad: cover (vhW && !io_wrCtl && pairOk && f_fv && (io_wdata != 32'd0) && io_badWrite);
  // W21 ← XlateSurface.vpn_drops_frame · XlateSurface.vpnhi_strict · t_vpn_drops — 0 의 VPN_HI 가 수락되어 FRAME 유효를 내리고 조용하다
  always @(posedge clk) if (f_step) w21_vpnhi_zero: cover (vhAcc && f_fv && !io_badWrite && !io_wrCtl);
  // W22 ← XlateSurface.rsvw_rejected · XlateSurface.reject_loud · p_bad_iff — 예약-엄격 워드(+0x7C)의 쓰기가 래치 기저에서도 거절되고 아무것도 세우지 않는다
  always @(posedge clk) if (f_step) w22_rsvw: cover (io_wrEnt && !io_wrCtl && (w == 5'd31) && pairOk && io_badWrite && !io_commit_valid && !io_needReady);
  // W23 ← XlateSurface.commit_rsv_strict · p_baddata_iff — [27:0] 비0 의 V=1 COMMIT 이 FRAME 이 차 있어도 수락 사이클에 거절된다
  always @(posedge clk) if (f_step) w23_cm_rsv: cover (cmAcc && f_fv && io_wdata[31] && (io_wdata[27:0] != 28'd0) && io_badData && !io_commit_valid);
  // W24 ← XlateStaging.stall_quiet · p_need_iff · p_baddata_iff — 데이터 사유 COMMIT 도 하류가 찬 사이클에는 정지하고(거절 없음), 다음 사이클 수락에서 거절된다
  always @(posedge clk) if (f_step) w24_bad_after_stall: cover (io_badData && $past(cmLegal && cmBad && !io_installReady && io_needReady && !io_badData && !io_badWrite) && ($past(io_wdata) == io_wdata) && ($past(io_woff) == io_woff));
  // W25 ← XlateSurface.commit_v_carried · p_commit_iff — V=0 COMMIT 의 [30:28] 비0 은 수락 · 커밋된다 (DP-20 — 거절 근거 없음)
  always @(posedge clk) if (f_step) w25_v0_perm: cover (io_commit_valid && !io_commit_v && (io_wdata[30:28] != 3'd0));
  // W26 ← XlateSurface.frame_stages_only · p_stage_quiet — 찬 FRAME 을 다른 FRAME 이 덮고 조용하다 (표에 닿지 않는다)
  always @(posedge clk) if (f_step) w26_frame_over: cover (frAcc && f_fv && (io_wdata != f_fr) && !io_badWrite && !io_wrCtl);
`else
  // W27 ← XlateSurface.ent_part_exists · p_ent_phantom · p_bad_iff — 형상 밖 기저(addr[8:7] ≥ 2)의 VPN 이 거절되고(badWrite) 래치된 스테이징이 그대로다
  always @(posedge clk) if (f_step) w27_ent_ph_vpn: cover (vpnW && !io_wrCtl && ePh && io_badWrite && f_vv);
  // W28 ← XlateSurface.ent_part_exists · p_ent_phantom · p_commit_iff — 1b 절단이면 닿을 실재 기저가 래치돼 있는데도 형상 밖 기저의 V=1 COMMIT 이 거절되고 커밋 · 정지가 없다 — 절단 별칭의 입력
  always @(posedge clk) if (f_step) w28_ent_ph_cm: cover (cmW && !io_wrCtl && ePh && f_vv && f_fv && (f_lp[0] == p[0]) && io_wdata[31] && io_badWrite && !io_commit_valid && !io_needReady);
  // W29 ← XlateSurface.flush_part_exists · p_flush_iff · p_bad_iff — [7:0]=2 (파티션 2 형상에서 없는 값)의 XLATE_FLUSH 가 거절되고 발화하지 않는다 — 1b 절단으로 파티션 0 을 지우는 별칭이 없다
  always @(posedge clk) if (f_step) w29_flush_ph2: cover (flWr && !io_wrEnt && io_wdata == 32'd2 && io_badWrite && !io_flush_valid);
`endif
`endif
endmodule
