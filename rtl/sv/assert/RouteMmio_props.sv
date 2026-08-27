// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// RouteMmio 후-formal 합성 하네스 — 이 파도의 첫 합성 증명 (§6.3).
//
// MmioConfig 의 viewWr·bankWr 출력을 RouteJudge 의 같은 이름 입력에 잇는
// 작은 합성 top 이다 (수기 SV top 허용 — bind 하네스의 연장. 실제 bind 는
// yosys 0.66 이 조용히 버리므로 — RouteJudge_props.sv 머리 실측 참조 —
// expose+인스턴스로 부착한다).
//
// ## 무엇을 재는가 — Route.tla M3 스큐 결함형의 RTL 판
//
// 선-formal 에서 ConfigOwn 은 표 반영과 뷰 갱신을 *한 원자 대입*으로
// 묶었고, view_sync 삭제 배터리는 그 묶음이 풀리면 「뷰가 표보다 뒤처지는」
// 스큐(M3)가 생김을 보였다. RTL 에서 그 원자 대입은 두 모듈 사이의 계약
// 「기입 1회 = 뷰 구동 1회」(§3.7.1)가 됐다. 이 하네스는 실제 배선 위에서
// 그 계약의 세 마디를 함께 잰다:
//
//   C1  뷰(RouteJudge 내부 레지스터) ≡ viewWr/bankWr 배선 이력
//   C2  표(MmioConfig 기입 신호 이력) ≡ 같은 배선 이력  (내용까지 동일)
//   C3  판정 출력(faultFire) ≡ 배선 이력이 정하는 소유 집합의 함수
//
// C1·C2 가 함께 서면 「뷰와 표가 어긋난 관측 사이클」은 표현 자체가
// 불가능하다 — 둘 다 같은 배선 이력과 사이클 단위로 일치하기 때문이다.
// C3 는 그 일치가 관측면(판정)까지 닿음을 잰다.
//
// ## 표 쪽의 다리 (정직 표기)
//
// 표 *내용*은 Mem 이라 하네스가 직접 못 읽는다 (yosys 자유 프론트엔드의
// Mem 접근 수단 부재 — 실측). C2 의 「표」는 단일 쓰기 포트 신호의 거울
// (그림자)이고, Mem 판독이 그 거울과 일치한다는 다리는 MmioConfig 심층
// 태스크(mmio_deep.sby)의 assume ①·② 소관이다. bmc/prove 에서 이 하네스의
// 내용 assume 은 아래 한 개 — 근거는 그 자리에 적었다 (cover 태스크만
// 시작 상태 가정을 더 얹는다. 바로 아래 절).
//
// ## ROUTEMMIO_COVER (route_mmio.sby 의 cover 태스크) — 공허 방지
//
// C1·C2·C3 는 문법상 무전건이지만 **배선이 한 번도 움직이지 않으면 아무것도
// 재지 않는다**: 뷰도 표도 영원히 공집합이면 「뷰 ≡ 표」는 0 ≡ 0 이다.
// 합성 증명의 도달성 질문은 그래서 「기입과 뷰 구동이 실제로 짝지어지는
// 궤적이 있는가」이고, 아래 증인들이 그 궤적이다. 전건이 문면에 붙은 것도
// 넷 있다 — initDone(p_pair_*) · h_commit · h_release · h_lbidCommit —
// 그리고 C2 이름 단언 16건의 `if (shVV[i])`, p_sweep_quiet 의 `!initDone`.
// 각 증인의 주석에 어느 전건에 대응하는지 적었다.
//
// 시작 상태: reset 기점 BMC 는 소거 2^16 사이클을 건너지 못한다(위 .sby
// 주석의 정직 표기). 그래서 이 태스크만 reset 을 인가하지 않고 t=0 을
// 「전부 공집합」 — 뷰 레지스터·세 그림자 모두 0, busy 없음, fault 없음 —
// 으로 가정한다. **initDone 은 자유로 둔다**: p_sweep_quiet 의 전건
// (!initDone)도 이 태스크에서 증인이 필요하고, 소거 구간은 이 시작 상태
// 에서 곧바로 닿기 때문이다. 공집합을 못박는 이유는 그림자를 자유로 두면
// 솔버가 t=0 에 아무 소유나 놓고 증인을 만족시켜 「기입 궤적이 뷰를
// 만든다」를 하나도 보이지 못하기 때문이다.
//
// 단언은 끄지 않는다 — 끌 필요가 없다. sby 는 cover 모드에서
// `chformal -live -fair -assert -remove` 로 단언을 모델에서 제거한다
// (2026-08-26 실측, model/design_prep.ys). assume 은 살아남으므로 이
// 태스크의 증인은 아래 Mem 다리 assume 아래에서 잡힌 것이다.

`timescale 1ns/1ps

module RouteMmio_props (
  input wire        clk,
  input wire        reset,
  // ── MMIO 자유 입력 ──────────────────────────────────────────────────
  input wire [11:0] addr,
  input wire        wstrobe,
  input wire [31:0] wdata,
  input wire        rstrobe,
  input wire        clr_dup,
  input wire        clr_bad,
  // ── 토큰 자유 입력 ──────────────────────────────────────────────────
  input wire        tok_valid,
  input wire [31:0] tok_wave,
  input wire [15:0] tok_thread,
  input wire [15:0] tok_lnid,
  input wire [7:0]  tok_precision,
  input wire [7:0]  tok_dim,
  input wire [7:0]  tok_lbid,
  input wire [3:0]  tok_srcKind,
  input wire        fault_clear
);

  // ── 모듈 간 배선 — 이 이음이 곧 §3.7.1 계약의 실물이다 ─────────────
  wire        vw_valid, vw_en;
  wire [3:0]  vw_idx;
  wire [15:0] vw_lnid;
  wire        bw_valid, bw_mapped;
  wire [7:0]  bw_lbid;

  wire [31:0] rdata;
  wire        rvalid, ready, f_dup, f_bad;
  // MmioConfig 내부 (expose)
  wire        w_initDone, w_busy;
  wire [7:0]  w_pSlot;
  wire [31:0] w_pWord;
  wire        w_revChkPresent;
  wire [31:0] w_fwdRd;
  wire        w_fwdWrEn, w_lbWrEn;
  wire [7:0]  w_fwdWrAddr, w_lbWrAddr;
  wire [31:0] w_fwdWrData, w_lbWrData;

  MmioConfig mm (
    .io_addr(addr), .io_wstrobe(wstrobe), .io_wdata(wdata), .io_rstrobe(rstrobe),
    .io_rdata(rdata), .io_rvalid(rvalid), .io_ready(ready),
    .io_viewWr_valid(vw_valid), .io_viewWr_idx(vw_idx),
    .io_viewWr_en(vw_en), .io_viewWr_lnid(vw_lnid),
    .io_bankWr_valid(bw_valid), .io_bankWr_lbid(bw_lbid), .io_bankWr_mapped(bw_mapped),
    .io_faultDupOwner(f_dup), .io_faultBadWrite(f_bad),
    .io_faultClearDup(clr_dup), .io_faultClearBad(clr_bad),
    .clk(clk), .reset(reset),
    .initDone(w_initDone), .busy(w_busy), .pSlot(w_pSlot), .pWord(w_pWord),
    .revChkPresent(w_revChkPresent), .fwdRd(w_fwdRd),
    .fwdWrEn(w_fwdWrEn), .fwdWrAddr(w_fwdWrAddr), .fwdWrData(w_fwdWrData),
    .lbWrEn(w_lbWrEn), .lbWrAddr(w_lbWrAddr), .lbWrData(w_lbWrData)
  );

  // 토큰 통과 출력 + RouteJudge 내부 (expose)
  wire        out_valid;
  wire [31:0] out_wave;
  wire [15:0] out_thread;
  wire [15:0] out_lnid;
  wire [7:0]  out_precision;
  wire [7:0]  out_dim;
  wire [7:0]  out_lbid;
  wire [3:0]  out_srcKind;
  wire        o_fault, o_fire;
  wire        vv0, vv1, vv2, vv3, vv4, vv5, vv6, vv7;
  wire        vv8, vv9, vv10, vv11, vv12, vv13, vv14, vv15;
  wire [15:0] vn0, vn1, vn2, vn3, vn4, vn5, vn6, vn7;
  wire [15:0] vn8, vn9, vn10, vn11, vn12, vn13, vn14, vn15;
  wire [255:0] bank;

  RouteJudge rj (
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
    // ← MmioConfig 구동 표면이 그대로 들어간다 (구동 규약의 실배선)
    .io_viewWr_valid(vw_valid), .io_viewWr_idx(vw_idx),
    .io_viewWr_en(vw_en), .io_viewWr_lnid(vw_lnid),
    .io_bankWr_valid(bw_valid), .io_bankWr_lbid(bw_lbid), .io_bankWr_mapped(bw_mapped),
    .io_fault(o_fault), .io_faultClear(fault_clear), .io_faultFire(o_fire),
    .clk(clk), .reset(reset),
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

  wire [15:0]  rj_vv = {vv15, vv14, vv13, vv12, vv11, vv10, vv9, vv8,
                        vv7, vv6, vv5, vv4, vv3, vv2, vv1, vv0};
  wire [255:0] rj_vn = {vn15, vn14, vn13, vn12, vn11, vn10, vn9, vn8,
                        vn7, vn6, vn5, vn4, vn3, vn2, vn1, vn0};

  // ── 하네스 재계산 (MmioConfig_props 와 동일 식) ─────────────────────
  wire        h_aligned = (addr[1:0] == 2'b00);
  wire [1:0]  h_region  = addr[11:10];
  wire [7:0]  h_wordIdx = addr[9:2];
  wire        h_acceptW = ready && wstrobe;
  wire        h_lbidWrite = h_acceptW && h_aligned && (h_region == 2'd2);
  wire        h_pV     = w_pWord[31];
  wire [7:0]  h_pPoint = w_pWord[23:16];
  wire [15:0] h_pLnid  = w_pWord[15:0];
  wire        h_oldV   = w_fwdRd[31];
  wire [15:0] h_oldLnid = w_fwdRd[15:0];
  // 예약 비트 비0 은 *거절*이다 (§3.7.1 「기입 시점의 거절」 네 원인 중 넷째,
  // 결정 df49b24). 워드 전체의 규범이므로 V 갈래보다 앞선다 — 등록(V=1)뿐
  // 아니라 해제(V=0) 기입도 예약 비트가 서면 커밋되지 않는다.
  // 이 셋은 MmioConfig_props 의 h_rsvL/h_rsvB/h_bad3 와 같은 식이어야 한다 —
  // 실제로 어긋났고 그것이 이 태스크를 회귀시켰다 (LBID 축 p_bank_iff ·
  // p_pair_bank 가 induction 에서 실패). 모듈 태스크만 돌리고 그 모듈을
  // *인스턴스하는 합성 태스크*를 돌리지 않으면 이 형태를 놓친다.
  wire        h_rsvL   = |w_pWord[30:24];       // LNID 엔트리 예약
  wire        h_rsvB   = |wdata[30:16];         // LBID 엔트리 예약
  wire        h_bad3   = (w_pSlot >= 8'h10) || h_oldV || (h_pPoint >= 8'h04);
  wire        h_commit  = w_busy && !h_rsvL && h_pV && !h_bad3 && !w_revChkPresent;
  wire        h_release = w_busy && !h_rsvL && !h_pV && h_oldV;
  wire        h_lbidCommit = h_lbidWrite && !h_rsvB;

  // ── 배선 이력 그림자 — C1 의 기준 (viewWr/bankWr 배선에서 뜬다) ────
  reg [15:0]  shVV;
  reg [255:0] shVN;
  reg [255:0] shBank;
  always @(posedge clk) begin
    if (reset) begin
      shVV <= 16'b0; shVN <= 256'b0; shBank <= 256'b0;
    end else begin
      if (vw_valid) begin
        shVV[vw_idx] <= vw_en;
        shVN[vw_idx*16 +: 16] <= vw_lnid; // RouteJudge 와 동일: en 무관 기록
      end
      if (bw_valid) shBank[bw_lbid] <= bw_mapped;
    end
  end

  // ── 표 기입 이력 그림자 — C2 의 기준 (fwd/lbid 단일 쓰기 포트에서 뜬다).
  //    소거 기입(initDone 전, 데이터 0)은 거울에 싣지 않는다 — reset 초기값
  //    이 이미 공집합이고, 소거는 Mem 을 같은 공집합으로 만드는 조작이라
  //    (§1.5) 이력상 무연산이다. 이렇게 하면 C2 를 게이트 없이 귀납으로
  //    닫을 수 있다 (소거 중 viewWr 부재는 아래 p_sweep_quiet 가 강제).
  reg [15:0]  shTV;
  reg [255:0] shTL;
  reg [255:0] shTB;
  always @(posedge clk) begin
    if (reset) begin
      shTV <= 16'b0; shTL <= 256'b0; shTB <= 256'b0;
    end else begin
      if (w_fwdWrEn && w_initDone && w_fwdWrAddr < 8'h10) begin
        shTV[w_fwdWrAddr[3:0]] <= w_fwdWrData[31];
        shTL[w_fwdWrAddr[3:0]*16 +: 16] <= w_fwdWrData[15:0];
      end
      if (w_lbWrEn && w_initDone) shTB[w_lbWrAddr] <= w_lbWrData[31];
    end
  end

  // ── 판정 함수의 그림자 판 재계산 — C3 의 기준 ───────────────────────
  integer i;
  reg h_hit;
  always @* begin
    h_hit = 1'b0;
    for (i = 0; i < 16; i = i + 1)
      if (shVV[i] && shVN[i*16 +: 16] == tok_lnid) h_hit = 1'b1;
  end
  wire h_anyMiss = !h_hit || ((tok_srcKind == 4'd1) && !shBank[tok_lbid]);

  // ── reset 프로토콜 (환경 assume — RouteJudge_props 와 동일 근거) ────
  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;
`ifndef ROUTEMMIO_COVER
  always @* begin
    if (!f_past_valid) assume (reset);
    else               assume (!reset);
  end
`else
  // 증인 태스크의 시작 상태 — 「전부 공집합」. 근거는 하네스 머리
  // ROUTEMMIO_COVER 절. initDone 은 일부러 자유로 둔다 (소거 구간 증인).
  always @* begin
    assume (!reset);
    if (!f_past_valid) begin
      assume (!w_busy);
      assume (!o_fault);
      // 뷰(RouteJudge 실레지스터)
      assume (rj_vv == 16'b0);
      assume (rj_vn == 256'b0);
      assume (bank == 256'b0);
      // 배선 이력 그림자 (C1 의 기준)
      assume (shVV == 16'b0);
      assume (shVN == 256'b0);
      assume (shBank == 256'b0);
      // 표 기입 이력 그림자 (C2 의 기준)
      assume (shTV == 16'b0);
      assume (shTL == 256'b0);
      assume (shTB == 256'b0);
    end
  end
`endif

  // ── Mem 다리 assume (bmc/prove 에서 이 하네스의 유일한 내용 가정 —
  //    cover 태스크는 위 「전부 공집합」 시작 상태를 더 얹는다) ─────────
  // 슬롯>=16 의 CHECK 판독은 V=0 이다. 근거: (a) V=1 기입의 커밋은 아래
  // p_pair_commit 이 pSlot<16 을 강제한다 (t 이전 사이클의 보증);
  // (b) reset 후 소거가 fwdMem 전 슬롯을 0 으로 쓴다 (§1.5); (c) 판독=
  // 최후기입 (Mem 의미론 — mmio_deep.sby 다리와 같은 성격의 기계 밖 항).
  // 이 다리가 없으면 귀납 시작 상태의 「슬롯>=16 유령 점유」가 해제 경로로
  // 흘러들어 C2 에 도달 불가능한 반례를 만든다.
  always @* begin
    if (!reset && w_busy && w_pSlot >= 8'h10) assume (!h_oldV);
  end

  always @(posedge clk) begin
    if (!reset) begin
      // ── 계약 절반 A — 「기입에서만, 기입마다 정확히 1회」 (§3.7.1):
      //    뷰 구동은 커밋·해제와 동치이고, 표 기입과 1:1 로 짝지어진다.
      p_drive_iff: assert (vw_valid == (h_commit || h_release));
      p_bank_iff:  assert (bw_valid == h_lbidCommit);
      if (w_initDone) begin
        p_pair_lnid: assert (w_fwdWrEn == vw_valid);
        p_pair_lbid: assert (w_lbWrEn == bw_valid);
      end
      // ── 계약 절반 B — 「같은 내용」: 배선에 실리는 것과 표에 실리는
      //    것이 같은 사이클에 같은 값이다 (M3 스큐의 부정).
      if (h_commit) begin
        p_pair_commit: assert (vw_en && vw_idx == w_pSlot[3:0] && w_pSlot < 8'h10
                               && w_fwdWrAddr == w_pSlot
                               && w_fwdWrData == w_pWord
                               && vw_lnid == w_fwdWrData[15:0]
                               && vw_en == w_fwdWrData[31]);
      end
      if (h_release) begin
        p_pair_release: assert (!vw_en && vw_idx == w_pSlot[3:0]
                                && w_fwdWrAddr == w_pSlot
                                && w_fwdWrData == 32'h0);
      end
      if (h_lbidCommit) begin
        p_pair_bank: assert (w_lbWrAddr == h_wordIdx && bw_lbid == h_wordIdx
                             && bw_mapped == w_lbWrData[31]);
      end
      // 소거 중 침묵 — 뷰를 움직이는 것은 기입 커밋뿐이다.
      p_busy_done: assert (!w_busy || w_initDone);
      if (!w_initDone) p_sweep_quiet: assert (!vw_valid && !bw_valid);

      // ── C1 — 뷰 ≡ 배선 이력: RouteJudge 의 실제 레지스터가 그림자와
      //    사이클 단위로 일치한다 (view_sync 반영 절반의 합성 판).
      p_c1_vv: assert (rj_vv == shVV);
      p_c1_vn: assert (rj_vn == shVN);
      p_c1_bank: assert (bank == shBank);

      // ── C2 — 표 기입 이력 ≡ 배선 이력: 같은 사이클, 같은 내용.
      //    C1 과 함께 「뷰와 표가 어긋난 관측 사이클 없음」이 선다.
      p_c2_v: assert (shVV == shTV);
      p_c2_bank: assert (shBank == shTB);
      for (i = 0; i < 16; i = i + 1)
        if (shVV[i]) assert (shVN[i*16 +: 16] == shTL[i*16 +: 16]);

      // ── C3 — 관측면: 판정 출력이 구성 이력이 정한 소유 집합의 함수다.
      //    (RouteJudge 단독 태스크의 global_judge 를 합성 배선 위에서 재확인)
      p_c3_judge: assert (o_fire == (tok_valid && h_anyMiss));
    end
  end

`ifdef ROUTEMMIO_COVER
  // ═══ 합성 도달성 증인 (cover 태스크 전용) ═════════════════════════════
  //
  // 대응표 — 증인 ↔ 그 증인이 성립시키는 전건:
  //   c_rm_sweeping        !w_initDone            (p_sweep_quiet)
  //   c_rm_commit_pair     w_initDone · h_commit  (p_pair_lnid · p_pair_commit)
  //   c_rm_view_landed     shVV[i] (어떤 i)        (C2 이름 단언 16건)
  //   c_rm_release_pair    h_release              (p_pair_release)
  //   c_rm_view_cleared    (같은 전건의 되돌림 방향 — 뷰가 줄어드는 궤적)
  //   c_rm_bank_pair       h_lbidCommit           (p_pair_bank · p_pair_lbid)
  //   c_rm_bank_landed     bankPresent 비0        (C2 bank 축의 실물)
  //   c_rm_judge_pass/fire (무전건인 p_c3_judge 의 두 극성 — 아래 주석)
  always @(posedge clk) begin
    if (!reset) begin
      // ── 소거 구간이 이 시작 상태에서 도달 가능하다.
      c_rm_sweeping: cover (!w_initDone);

      // ── **이 태스크의 알맹이** — 표 기입과 뷰 구동이 같은 사이클에
      //    실제로 짝지어진다. p_pair_lnid(w_fwdWrEn == vw_valid)는 양변이
      //    영원히 0 이어도 통과하므로, 이 증인이 없으면 계약 절반 A 는
      //    「아무 기입도 없다」로 만족될 수 있다.
      c_rm_commit_pair: cover (w_initDone && h_commit
                               && w_fwdWrEn && vw_valid && vw_en);

      // ── 그 구동이 RouteJudge 의 실레지스터까지 닿았다 (C1 의 알맹이).
      //    동시에 C2 이름 단언 16건의 전건 `shVV[i]` 가 성립하는 궤적이다
      //    — C1 이 rj_vv == shVV 를 세우므로 rj_vv 비0 이 곧 그 전건이다.
      c_rm_view_landed: cover (|rj_vv);

      // ── 해제 방향 (p_pair_release 의 전건). 커밋 증인만 두면 「등록만
      //    되고 해제는 못 하는 기계」도 전부 통과한다.
      //    정직 표기: 이 증인만으로는 약하다 — 시작 상태에서 *Mem 내용은
      //    자유*라 (그림자만 공집합으로 못박았다) 솔버가 fwdMem 에 유령
      //    점유를 놓고 앞선 커밋 없이 해제를 일으킬 수 있다. 실측에서도
      //    이것은 2스텝에 잡혔다. 그래서 아래를 짝으로 둔다:
      c_rm_view_cleared: cover (vw_valid && !vw_en && rj_vv[vw_idx]);
      c_rm_release_pair: cover (h_release && w_fwdWrEn && vw_valid && !vw_en);
      //    c_rm_view_cleared 는 rj_vv 가 t=0 에 0 으로 못박혀 있어 *반드시*
      //    앞선 실제 커밋을 거쳐야 성립한다 (실측 4스텝). 즉 「기입→구동→
      //    뷰 반영→해제 구동→뷰 회수」의 온전한 왕복이 이 한 줄에 걸린다.

      // ── LBID 축 (p_pair_bank · p_pair_lbid 의 전건) 과 그 착지.
      c_rm_bank_pair: cover (w_initDone && h_lbidCommit
                             && w_lbWrEn && bw_valid && bw_mapped);
      c_rm_bank_landed: cover (|bank);

      // ── p_c3_judge 는 무전건이지만 등식이라 *두 극성이 모두 도달
      //    가능해야* 내용이 있다. 특히 통과(!o_fire) 쪽은 구성된 소유가
      //    실제로 토큰을 통과시킨다는 뜻이라, 이것이 없으면 「전부
      //    발화하는 기계」도 C3 를 만족한다 (h_anyMiss 도 항상 참이므로).
      c_rm_judge_pass: cover (tok_valid && !o_fire && (|rj_vv));
      c_rm_judge_fire: cover (tok_valid && o_fire);
    end
  end
`endif

endmodule
