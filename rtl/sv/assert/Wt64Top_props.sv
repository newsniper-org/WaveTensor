// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// Wt64Top 조립층 후-formal 검사자 — MMIO 구성 표면(4 KiB 페이지)의 조립 결선.
// 대상: rtl/generated/Wt64Top.sv 의 Wt64Top 모듈 *본문*. 태스크:
// rtl/formal/sby/Wt64Top/assembly.sby (머리가 절단 목록 · 보증 범위 · 엔진 표 ·
// 역-변이 표 · 축별 발화 우선 표를 소유한다 — 여기 되풀이하지 않는다).
//
// ## 부착 — 이 모듈은 래퍼가 아니라 Wt64Top *안*의 검사자다
//
// 파일 끝 bind 문은 .sby [script] 가 이름-고정 텍스트 전개로 Wt64Top 본문의
// endmodule 앞에 넣는다 (yosys 0.66 은 bind 를 묵살한다 — SharedUnit_props.sv
// 머리). 포트는 .* 로 같은 이름의 Wt64Top 넷에 묶인다: 이름이 사라지면
// hierarchy 가 ERROR 로 운다. 무거운 하위 인스턴스 열넷은 expose -evert 로
// 제거되고, 그 출력 핀은 Wt64Top 의 새 *입력* 포트 <인스턴스>__<포트>(매 스텝
// 자유 — 과대근사), 입력 핀은 새 *출력* 포트 <인스턴스>__<포트>(그 핀에 실제로
// 물린 신호)가 된다. 이중 밑줄 이름을 보는 것은 **핀**을 보는 것이다 — 같은
// 이름의 wire 가 아니다 (핀만 재배선한 변이를 wire 관측은 놓친다: 스파이크 실측).
// 구체로 남는 하위 유닛은 CapStatusWord(capWord) · AbortStaging(stg) 둘이다.
//
// ## 피연산자 규율
//
//   기대측(오라클)은 top 포트 · 절단 핀 · 구체 유닛 출력 · 이 파일의 그림자
//   레지스터(f_win)와 주소 리터럴로만 짓는다. DUT 어휘(sel*, *Area_*, fltClrAccept,
//   surfBadWr)를 재인용하지 않는다. DUT 측은 top 출력 포트 · 절단 핀 · 구체 유닛
//   출력뿐이다 — Wt64Top 내부 wire 와 순번 이름(_zz_*)·줄번호 매인 이름은 참조하지
//   않는다. 생성물에서 상수에 묶인 넷(축 3 set · FAULT_STATUS [17]/[18] · CAP_STATUS
//   [31:4])은 MMIO 읽기 표면으로만 잰다 — 계층 모델에서는 lint_tautology 의 상수
//   접힘 검사가 모듈 경계를 못 넘으므로, 반증력은 .sby 머리의 역-변이 표가 든다.
//
// ## 정본 (좌표 뒤 「」 는 그 줄의 축자)
//
//   e-defined.typ:137 「구역 경계가 곧 소유 경계라는 사실이 무너진다」
//   e-defined.typ:198 「0 을 반환하고 fault 를 내지 않는다」
//   e-defined.typ:202 「거절 + loud fault 다」
//   e-defined.typ:205 「이 규범의 대상이 아니다」
//   03-hiu.typ:719 「쓰기 무시·읽기 0」
//   e-defined.typ:188 「비0 기입은 거절 + loud fault」
//   e-defined.typ:414 「실재하지 않는 파티션 값의 기입은」
//   e-defined.typ:497 「해제와 발화가 같은 사이클이면 발화가 이긴다」
//   e-defined.typ:527 「이 워드에 들지 않는다」
//   e-defined.typ:499 「FAULT_STATUS 의 논리합」
//   e-defined.typ:503 「CAP_STATUS 와 같은 비트 배치의 W1C」
//   e-defined.typ:485 「태그 값은 내지 않는다」
//   e-defined.typ:1800 「거절된 기입은 무장을 세우지 않는다」
//   e-defined.typ:341 「이 창은 어느 슬롯에 쓰는가만 정한다」
//   e-defined.typ:399 「창을 재키잉의 authority 로 겸하게」
//   e-defined.typ:461 「`[30:24]` 예약 = 0 (엄격)」
//   e-defined.typ:463 「적재 수락 가능」
//   e-defined.typ:267 「정의역 나열 순서 그대로」
//   e-defined.typ:44 「이 문서가 새로 정의하지 않는다」
//   b-gaps.typ:811 「물려받은 `0x000`–`0x11F` 의 방향 처분」
//   e-defined.typ:212 「예약 오프셋 정책을 따르고」
//   03-hiu.typ:738 「드라이버가 ABI 판을 물었을 때 0 을 받는다」
//   e-defined.typ:473 「소거 대상 태그의 wave 필드」
//   e-defined.typ:475 「`[15:0]` LNID」
//   e-defined.typ:477 「`[15:8]` precision · `[7:0]` dim」
//
// ## 구역 분류 — 정의 정책과 예약 정책을 섞지 않는다 (워드 단위)
//
//   rLeg  0x000–0x11F  물려받은 기존 배정. 이 페이지의 두 정책(표의 방향 규범 ·
//                      예약 오프셋 관대 정책) 어느 쪽의 정의역도 아니고 방향
//                      처분은 정본 미결이다 — 읽기 값 · 쓰기 fault 를 둘 다
//                      열어 둔다 (읽기는 resvA 밖 · 쓰기는 surfOpen).
//   rResv 0x120–0x1FF  예약 — 정렬 쓰기 무-fault · 읽기 0.
//   미배선 네 구역(0x380 · 0xC00 · 0xE00 · 0xFC0)은 워드마다 가른다.
//     uResv  표에 없는 워드 (0x394–0x3FC · 0xE14–0xE7C · 0xFC0–0xFF8) — 예약 정책:
//            정렬 쓰기 무-fault(surfOpen 밖) · 읽기 0.
//     uWo    표의 WO 워드 (0xC00–0xDFC · 0xE00 · 0xE10) — 읽기 0 은 WO 규범이다.
//            쓰기는 효과가 있어야 하는데 흡수된다 — 판정 대기라 surfOpen.
//     uDef   표의 RW/RO 워드 (0x380–0x390 · 0xE04–0xE0C · 0xFFC) — 값을 내야 하는
//            워드인데 회로가 없다. 읽기(응답·값)와 쓰기 fault 를 둘 다 열어 둔다 —
//            0xFFC 읽기 0 을 단언하면 정본이 이름한 함정을 굳힌다.
//   비정렬 쓰기(rResv · uResv · 조립 네 구역)는 sub-word 여부가 판정 대기라 surfOpen.
//
// ## assume (전수)
//
//   initial assume (reset) 하나 — t0 의 reset. 절단 핀에는 assume 이 0 건이다
//   (.sby [script] 의 select -assert-count 가 $check(FLAVOR=assume) 수 1 을 핀한다).
//
// WITNESS-RESIDUAL: 실물 도달성 — 절단 출력 의존 증인 — 콘에 절단 핀(<인스턴스>__*)
//   이 든 증인은 과대근사 위의 도달이다. 목록과 실물 근거는 각 W 태그 산문이 적고,
//   절단 무관 증인은 cover 태스크 [script] 의 콘 판별이 기계로 강제한다.
module Wt64Top_props (
  input logic        clk,
  input logic        reset,
  // ── top ports ──
  input logic [11:0] io_mmio_addr,
  input logic        io_mmio_wstrobe,
  input logic [31:0] io_mmio_wdata,
  input logic        io_mmio_rstrobe,
  input logic [31:0] io_mmio_rdata,
  input logic        io_mmio_rvalid,
  input logic        io_mmio_ready,
  input logic        io_fault_cfgSurfBadWrite,
  input logic        io_faultClear_decodeWalk,
  input logic        io_faultClear_operandDecode,
  input logic        io_faultClear_route,
  input logic        io_faultClear_reasm,
  input logic        io_faultClear_reasmCap,
  input logic        io_faultClear_hiuPerm,
  input logic        io_faultClear_hiuMiss,
  input logic        io_faultClear_cfgDupOwner,
  input logic        io_faultClear_cfgBadWrite,
  input logic        io_faultClear_cfgSurfBadWrite,
  input logic        io_faultClear_ownCollide,
  input logic        io_faultClear_fabricBp,
  input logic        io_faultClear_sharedBp,
  input logic        io_faultClear_bankWrite,
  input logic        io_faultClear_maskNoMask,
  input logic        io_faultClear_maskNonceDup,
  input logic        io_faultClear_maskWrRekey,
  input logic        io_faultClear_fpBp,
  input logic        io_faultClear_fpBadProg,
  // ── kept (concrete) units: output wires ──
  input logic [31:0] capWord_io_word,
  input logic [2:0]  stg_io_armed,
  input logic        stg_io_fire,
  input logic [31:0] stg_io_tag_wave,
  input logic [15:0] stg_io_tag_thread,
  input logic [15:0] stg_io_tag_lnid,
  input logic [7:0]  stg_io_tag_precision,
  input logic [7:0]  stg_io_tag_dim,
  // ── evert pins ──
  input logic        walk__io_oValid, walk__io_oCapAbsent, walk__io_oFault, walk__io_iFaultClear,
  input logic        od__io_oFault, od__io_iFaultClear,
  input logic        rj__io_fault, rj__io_faultClear,
  input logic        rj__io_viewWr_valid, input logic [3:0] rj__io_viewWr_idx, input logic rj__io_viewWr_en,
  input logic [15:0] rj__io_viewWr_lnid,
  input logic        rj__io_bankWr_valid, input logic [7:0] rj__io_bankWr_lbid, input logic rj__io_bankWr_mapped,
  input logic        reasm__io_fault, reasm__io_faultClear, reasm__io_capAbsent, reasm__io_capAbsentClear,
  input logic [7:0]  reasm__io_abortCount,
  input logic [2:0]  reasm__io_incomplete,
  input logic [2:0]  reasm__io_occupancy,
  input logic        reasm__io_abort_valid,
  input logic [31:0] reasm__io_abort_tag_wave,
  input logic [15:0] reasm__io_abort_tag_thread,
  input logic [15:0] reasm__io_abort_tag_lnid,
  input logic [7:0]  reasm__io_abort_tag_precision,
  input logic [7:0]  reasm__io_abort_tag_dim,
  input logic        reasm__io_deliver_valid, reasm__io_deliver_ready,
  input logic [2:0]  mog__io_occupancy,
  input logic        hiu__io_req_ready,
  input logic [31:0] hiu__io_owner_frame,
  input logic        hiu__io_owner_devOwned,
  input logic        hiu__io_mask_req_valid, input logic [1:0] hiu__io_mask_req_part,
  input logic [31:0] hiu__io_mask_req_frame,
  input logic        hiu__io_mask_rsp_valid, input logic [31:0] hiu__io_mask_rsp_frame,
  input logic        hiu__io_faultPerm, hiu__io_faultClear, hiu__io_missClear,
  input logic [2:0]  hiu__io_occupancy,
  input logic [11:0] own__io_addr, input logic own__io_wstrobe, input logic [31:0] own__io_wdata,
  input logic        own__io_rstrobe, own__io_rvalid, own__io_ready,
  input logic [31:0] own__io_query_frame, input logic own__io_query_devOwned,
  input logic        own__io_faultCollide, own__io_faultClearCollide, own__io_faultBadWrite, own__io_faultClearBadWrite,
  input logic [11:0] cfgBlk__io_addr, input logic cfgBlk__io_wstrobe, input logic [31:0] cfgBlk__io_wdata,
  input logic        cfgBlk__io_rstrobe, cfgBlk__io_rvalid, cfgBlk__io_ready,
  input logic        cfgBlk__io_viewWr_valid, input logic [3:0] cfgBlk__io_viewWr_idx, input logic cfgBlk__io_viewWr_en,
  input logic [15:0] cfgBlk__io_viewWr_lnid,
  input logic        cfgBlk__io_bankWr_valid, input logic [7:0] cfgBlk__io_bankWr_lbid, input logic cfgBlk__io_bankWr_mapped,
  input logic        cfgBlk__io_faultDupOwner, cfgBlk__io_faultBadWrite, cfgBlk__io_faultClearDup, cfgBlk__io_faultClearBad,
  input logic        merge__io_fault, merge__io_faultClear, input logic [2:0] merge__io_occupancy,
  input logic        shared_1__io_faultBpViolation, shared_1__io_faultClear, input logic [2:0] shared_1__io_occupancy,
  input logic        bank__io_fault, bank__io_faultClear, input logic [4:0] bank__io_occupancy,
  input logic        mask__io_keyWr_valid, input logic [1:0] mask__io_keyWr_part, input logic [2:0] mask__io_keyWr_idx,
  input logic [31:0] mask__io_keyWr_data,
  input logic        mask__io_nonceWr_valid, input logic [1:0] mask__io_nonceWr_part, input logic [2:0] mask__io_nonceWr_idx,
  input logic [31:0] mask__io_nonceWr_data,
  input logic        mask__io_rekey_valid, mask__io_rekey_ready, input logic [1:0] mask__io_rekey_part,
  input logic [3:0]  mask__io_maskReady, input logic mask__io_busy, mask__io_en,
  input logic        mask__io_req_valid, input logic [1:0] mask__io_req_part, input logic [31:0] mask__io_req_frame,
  input logic        mask__io_rsp_valid, input logic [31:0] mask__io_rsp_frame,
  input logic        mask__io_faultNoMask, mask__io_faultNonceDup, mask__io_faultWrDuringRekey,
  input logic        mask__io_faultClearNoMask, mask__io_faultClearNonceDup, mask__io_faultClearWrRekey,
  input logic        fps__io_oCapAbsent, fps__io_oBusy,
  input logic        fps__io_progWr_valid, input logic [7:0] fps__io_progWr_slot, input logic [7:0] fps__io_progWr_idx,
  input logic [15:0] fps__io_progWr_step,
  input logic        fps__io_bindWr_valid, input logic [15:0] fps__io_bindWr_key, input logic fps__io_bindWr_en,
  input logic [7:0]  fps__io_bindWr_slot,
  input logic        fps__io_loadReady, fps__io_faultBpViolation, fps__io_faultBadProg, fps__io_faultClearBp, fps__io_faultClearBadProg,
  input logic [7:0]  cq__io_addr, input logic cq__io_wstrobe, input logic [31:0] cq__io_wdata,
  input logic        cq__io_rstrobe, cq__io_rvalid, cq__io_ready,
  input logic        cq__io_comp_valid, cq__io_comp_ready,
  input logic [15:0] cq__io_drain_pipe, cq__io_drain_pending, cq__io_drain_output,
  input logic [15:0] cq__io_drain_ownSlots, cq__io_drain_contexts, cq__io_drain_tokens,
  input logic        cq__io_faultOverflow, cq__io_faultClearOverflow, cq__io_faultBadWrite, cq__io_faultClearBadWrite
);
  initial assume (reset);

  logic f_past_valid = 1'b0;
  logic f_past_reset = 1'b1;
  always @(posedge clk) begin
    f_past_valid <= 1'b1;
    f_past_reset <= reset;
  end
  wire f_step = f_past_valid && !reset && !f_past_reset;

  wire [11:0] A = io_mmio_addr;
  wire [31:0] D = io_mmio_wdata;
  wire W  = io_mmio_wstrobe;
  wire R  = io_mmio_rstrobe && !io_mmio_wstrobe;
  wire al = (A[1:0] == 2'b00);

  wire rLeg   = (A <  12'h120);
  wire rResv  = (A >= 12'h120) && (A < 12'h200);
  wire rOwn   = (A >= 12'h200) && (A < 12'h300);
  wire rCq    = (A >= 12'h300) && (A < 12'h380);
  wire rCfg   = (A >= 12'h400) && (A < 12'hC00);
  wire rXent  = (A >= 12'hC00) && (A < 12'hE00);
  wire rMask  = (A >= 12'hE80) && (A < 12'hF00);
  wire rFp    = (A >= 12'hF00) && (A < 12'hF40);
  wire rAbort = (A >= 12'hF40) && (A < 12'hF80);
  wire rFault = (A >= 12'hF80) && (A < 12'hFC0);
  wire rAsm   = rMask || rFp || rAbort || rFault;
  wire uResv  = ((A >= 12'h394) && (A < 12'h400)) || ((A >= 12'hE14) && (A < 12'hE80)) ||
                ((A >= 12'hFC0) && (A < 12'hFFC));
  wire uWo    = rXent || ((A >= 12'hE00) && (A < 12'hE04)) || ((A >= 12'hE10) && (A < 12'hE14));
  wire uDef   = ((A >= 12'h380) && (A < 12'h394)) || ((A >= 12'hE04) && (A < 12'hE10)) || (A >= 12'hFFC);

  wire aKey   = (A >= 12'hE80) && (A <= 12'hE9C);
  wire aNonce = (A >= 12'hEA4) && (A <= 12'hEB8);
  wire aTag   = (A >= 12'hF40) && (A <= 12'hF4C);
  wire woA    = aKey || aNonce || (A == 12'hEBC) || (A == 12'hF00) || (A == 12'hF04) ||
                aTag || (A == 12'hF84) || (A == 12'hF90);
  wire undefA = ((A >= 12'hEC4) && (A <= 12'hEFC)) || ((A >= 12'hF0C) && (A <= 12'hF3C)) ||
                ((A >= 12'hF5C) && (A <= 12'hF7C)) || ((A >= 12'hF94) && (A <= 12'hFBC));
  wire resvA  = rResv || uResv || uWo || (rAsm && !al);
  wire [11:0] f_kOff = A - 12'hE80;
  wire [11:0] f_nOff = A - 12'hEA4;

  wire partOk = (D[31:8] == 24'd0) && (D[7:0] < 8'd4);
  wire acF84  = W && (A == 12'hF84) && (D[31:19] == 13'd0);
  wire acF90  = W && (A == 12'hF90) && (D[31:4]  == 28'd0);

  wire surfMust = W && al && (
      ((A == 12'hEA0) && !partOk) || ((A == 12'hEBC) && !partOk) || (A == 12'hEC0) ||
      ((A == 12'hF04) && (D[30:24] != 7'd0) && io_mmio_ready) || (A == 12'hF08) ||
      ((A == 12'hF48) && (D[31:16] != 16'd0)) || ((A == 12'hF4C) && (D[31:1] != 31'd0)) ||
      (A == 12'hF50) || (A == 12'hF54) || (A == 12'hF58) ||
      (A == 12'hF80) || ((A == 12'hF84) && (D[31:19] != 13'd0)) || (A == 12'hF88) || (A == 12'hF8C) ||
      ((A == 12'hF90) && (D[31:4] != 28'd0)));
  wire surfOpen = W && (rLeg || uWo || uDef || (!al && (rResv || uResv || rAsm)) ||
      (al && (A == 12'hF44) && (D[27:16] != 12'd0)) ||
      (al && (A == 12'hF04) && (D[30:24] != 7'd0) && !io_mmio_ready));
  wire clrS = io_faultClear_cfgSurfBadWrite || (acF84 && D[6]);

  logic [1:0] f_win = 2'b00;
  always @(posedge clk) begin
    if (reset) f_win <= 2'b00;
    else if (W && al && (A == 12'hEA0) && partOk) f_win <= D[1:0];
  end

  wire [18:0] f_expSt = {2'b00, cq__io_faultOverflow, fps__io_faultBadProg, fps__io_faultBpViolation,
      mask__io_faultWrDuringRekey, mask__io_faultNonceDup, mask__io_faultNoMask, bank__io_fault,
      shared_1__io_faultBpViolation, merge__io_fault, own__io_faultCollide,
      (cfgBlk__io_faultBadWrite || io_fault_cfgSurfBadWrite || cq__io_faultBadWrite || own__io_faultBadWrite),
      cfgBlk__io_faultDupOwner, hiu__io_faultPerm, reasm__io_fault, rj__io_fault, od__io_oFault, walk__io_oFault};

  wire src1 = fps__io_oCapAbsent;
  wire src2 = walk__io_oValid && walk__io_oCapAbsent;

`ifndef WT64TOP_COVER
  always @(*) if (!reset) begin
    // region routing
    a_own_strb: assert (own__io_wstrobe == (W && rOwn) && own__io_rstrobe == (io_mmio_rstrobe && rOwn));
    a_cq_strb:  assert (cq__io_wstrobe  == (W && rCq)  && cq__io_rstrobe  == (io_mmio_rstrobe && rCq));
    a_cfg_strb: assert (cfgBlk__io_wstrobe == (W && rCfg) && cfgBlk__io_rstrobe == (io_mmio_rstrobe && rCfg));
    a_blk_bus:  assert (own__io_addr == A && cfgBlk__io_addr == A && cq__io_addr == A[7:0] &&
                        own__io_wdata == D && cfgBlk__io_wdata == D && cq__io_wdata == D &&
                        mask__io_keyWr_data == D && mask__io_nonceWr_data == D);
    a_ready_unit: assert ((!rOwn || io_mmio_ready == own__io_ready) && (!rCq || io_mmio_ready == cq__io_ready) &&
                          (!rCfg || io_mmio_ready == cfgBlk__io_ready));
    a_ready_fpw: assert (!(W && (A >= 12'hF00) && (A < 12'hF08)) || io_mmio_ready == fps__io_loadReady);
    a_ready_one: assert ((rOwn || rCq || rCfg || ((A >= 12'hF00) && (A < 12'hF08))) || io_mmio_ready);
    // mask
    a_key_valid:   assert (mask__io_keyWr_valid == (W && al && aKey));
    a_key_idx:     assert (!mask__io_keyWr_valid || mask__io_keyWr_idx == f_kOff[4:2]);
    a_nonce_valid: assert (mask__io_nonceWr_valid == (W && al && aNonce));
    a_nonce_idx:   assert (!mask__io_nonceWr_valid || mask__io_nonceWr_idx == f_nOff[4:2]);
    a_win_pins:    assert (mask__io_keyWr_part == f_win && mask__io_nonceWr_part == f_win);
    a_mask_env:    assert ($onehot0({mask__io_keyWr_valid, mask__io_nonceWr_valid, mask__io_rekey_valid}));
    a_rekey_iff:   assert (mask__io_rekey_valid == (W && al && (A == 12'hEBC) && partOk));
    a_rekey_part:  assert (!mask__io_rekey_valid || mask__io_rekey_part == D[1:0]);
    // fp
    a_prog_src:    assert (!fps__io_progWr_valid || (W && al && (A == 12'hF00)));
    a_prog_acc:    assert (!(W && al && (A == 12'hF00) && io_mmio_ready) || fps__io_progWr_valid);
    a_prog_fields: assert (!fps__io_progWr_valid || (fps__io_progWr_slot == D[31:24] &&
                           fps__io_progWr_idx == D[23:16] && fps__io_progWr_step == D[15:0]));
    a_bind_src:    assert (!fps__io_bindWr_valid || (W && al && (A == 12'hF04) && (D[30:24] == 7'd0)));
    a_bind_acc:    assert (!(W && al && (A == 12'hF04) && (D[30:24] == 7'd0) && io_mmio_ready) || fps__io_bindWr_valid);
    a_bind_fields: assert (!fps__io_bindWr_valid || (fps__io_bindWr_en == D[31] &&
                           fps__io_bindWr_slot == D[23:16] && fps__io_bindWr_key == D[15:0]));
    // abort
    a_fire_src:   assert (!reasm__io_abort_valid || (W && al && (A == 12'hF4C) && (D[31:1] == 31'd0) && D[0]));
    a_fire_route: assert (reasm__io_abort_valid == stg_io_fire && reasm__io_abort_tag_wave == stg_io_tag_wave &&
                          reasm__io_abort_tag_thread == stg_io_tag_thread && reasm__io_abort_tag_lnid == stg_io_tag_lnid &&
                          reasm__io_abort_tag_precision == stg_io_tag_precision && reasm__io_abort_tag_dim == stg_io_tag_dim);
    // fault clear routing
    a_fclr_b0:  assert (walk__io_iFaultClear == (io_faultClear_decodeWalk || (acF84 && D[0])));
    a_fclr_b1:  assert (od__io_iFaultClear   == (io_faultClear_operandDecode || (acF84 && D[1])));
    a_fclr_b2:  assert (rj__io_faultClear    == (io_faultClear_route || (acF84 && D[2])));
    a_fclr_b3:  assert (reasm__io_faultClear == (io_faultClear_reasm || (acF84 && D[3])));
    a_fclr_b4:  assert (hiu__io_faultClear   == (io_faultClear_hiuPerm || (acF84 && D[4])));
    a_fclr_b5:  assert (cfgBlk__io_faultClearDup == (io_faultClear_cfgDupOwner || (acF84 && D[5])));
    a_fclr_b6:  assert (cfgBlk__io_faultClearBad == (io_faultClear_cfgBadWrite || (acF84 && D[6])) &&
                        own__io_faultClearBadWrite == (acF84 && D[6]) && cq__io_faultClearBadWrite == (acF84 && D[6]));
    a_fclr_b7:  assert (own__io_faultClearCollide == (io_faultClear_ownCollide || (acF84 && D[7])));
    a_fclr_b8:  assert (merge__io_faultClear == (io_faultClear_fabricBp || (acF84 && D[8])));
    a_fclr_b9:  assert (shared_1__io_faultClear == (io_faultClear_sharedBp || (acF84 && D[9])));
    a_fclr_b10: assert (bank__io_faultClear == (io_faultClear_bankWrite || (acF84 && D[10])));
    a_fclr_b11: assert (mask__io_faultClearNoMask == (io_faultClear_maskNoMask || (acF84 && D[11])));
    a_fclr_b12: assert (mask__io_faultClearNonceDup == (io_faultClear_maskNonceDup || (acF84 && D[12])));
    a_fclr_b13: assert (mask__io_faultClearWrRekey == (io_faultClear_maskWrRekey || (acF84 && D[13])));
    a_fclr_b14: assert (fps__io_faultClearBp == (io_faultClear_fpBp || (acF84 && D[14])));
    a_fclr_b15: assert (fps__io_faultClearBadProg == (io_faultClear_fpBadProg || (acF84 && D[15])));
    a_fclr_b16: assert (cq__io_faultClearOverflow == (acF84 && D[16]));
    a_miss_clr: assert (hiu__io_missClear == io_faultClear_hiuMiss);
    // cap axis 0
    a_cap0_lvl: assert (capWord_io_word[0] == reasm__io_capAbsent);
    a_cap0_clr: assert (reasm__io_capAbsentClear == (io_faultClear_reasmCap || (acF90 && D[0])));
    // drain + composite wiring
    a_drain_order: assert (cq__io_drain_pipe == {13'd0, hiu__io_occupancy} && cq__io_drain_pending == {13'd0, shared_1__io_occupancy} &&
                           cq__io_drain_output == {13'd0, merge__io_occupancy} && cq__io_drain_ownSlots == {11'd0, bank__io_occupancy} &&
                           cq__io_drain_contexts == {13'd0, reasm__io_occupancy} && cq__io_drain_tokens == {13'd0, mog__io_occupancy});
    a_hm_en:     assert (mask__io_en == hiu__io_req_ready);
    a_hm_req:    assert (mask__io_req_valid == hiu__io_mask_req_valid && mask__io_req_part == hiu__io_mask_req_part &&
                         mask__io_req_frame == hiu__io_mask_req_frame);
    a_hm_rsp:    assert (hiu__io_mask_rsp_valid == mask__io_rsp_valid && hiu__io_mask_rsp_frame == mask__io_rsp_frame);
    a_own_query: assert (hiu__io_owner_devOwned == own__io_query_devOwned && own__io_query_frame == hiu__io_owner_frame);
    a_route_wr:  assert (rj__io_viewWr_valid == cfgBlk__io_viewWr_valid && rj__io_viewWr_idx == cfgBlk__io_viewWr_idx &&
                         rj__io_viewWr_en == cfgBlk__io_viewWr_en && rj__io_viewWr_lnid == cfgBlk__io_viewWr_lnid &&
                         rj__io_bankWr_valid == cfgBlk__io_bankWr_valid && rj__io_bankWr_lbid == cfgBlk__io_bankWr_lbid &&
                         rj__io_bankWr_mapped == cfgBlk__io_bankWr_mapped);
    a_bp_relief: assert (reasm__io_deliver_ready == cq__io_comp_ready && cq__io_comp_valid == reasm__io_deliver_valid);
  end

  always @(posedge clk) if (f_step) begin
    // reads
    if ($past(R && io_mmio_ready && resvA)) begin
      a_rd_resv_rv: assert (io_mmio_rvalid);
      a_rd_resv0:   assert ((own__io_rvalid || cq__io_rvalid || cfgBlk__io_rvalid) || io_mmio_rdata == 32'd0);
    end
    if ($past(R && al && undefA))                  a_rd_undef: assert (io_mmio_rvalid && io_mmio_rdata == 32'd0);
    if ($past(R && al && io_mmio_ready && woA))    a_rd_wo:    assert (io_mmio_rvalid && io_mmio_rdata == 32'd0);
    if ($past(R && al && (A == 12'hEA0)))          a_rd_mpart: assert (io_mmio_rvalid && io_mmio_rdata == {30'd0, $past(f_win)});
    if ($past(R && al && (A == 12'hEC0)))          a_rd_mstat: assert (io_mmio_rvalid && io_mmio_rdata ==
        {22'd0, $past(mask__io_rekey_ready), $past(mask__io_busy), 4'd0, $past(mask__io_maskReady)});
    if ($past(R && al && (A == 12'hF08)))          a_rd_fstat: assert (io_mmio_rvalid && io_mmio_rdata ==
        {30'd0, $past(fps__io_oBusy), $past(fps__io_loadReady)});
    if ($past(R && al && (A == 12'hF50)))          a_rd_acnt:  assert (io_mmio_rvalid && io_mmio_rdata == {24'd0, $past(reasm__io_abortCount)});
    if ($past(R && al && (A == 12'hF54)))          a_rd_ainc:  assert (io_mmio_rvalid && io_mmio_rdata == {29'd0, $past(reasm__io_incomplete)});
    if ($past(R && al && (A == 12'hF58)))          a_rd_arm:   assert (io_mmio_rvalid && io_mmio_rdata == {29'd0, $past(stg_io_armed)});
    if ($past(R && al && (A == 12'hF80)))          a_rd_fst:   assert (io_mmio_rvalid && io_mmio_rdata == {13'd0, $past(f_expSt)});
    if ($past(R && al && (A == 12'hF88)))          a_rd_fsum:  assert (io_mmio_rvalid && io_mmio_rdata == {31'd0, |$past(f_expSt)});
    if ($past(R && al && (A == 12'hF8C))) begin
      a_rd_capst: assert (io_mmio_rvalid && io_mmio_rdata == {28'd0, $past(capWord_io_word[3:1]), $past(reasm__io_capAbsent)});
      a_rd_capb3: assert (!io_mmio_rdata[3]);
    end
    // surf sticky
    a_surf_fire:  assert (!$past(surfMust) || io_fault_cfgSurfBadWrite);
    a_surf_rise:  assert (!(io_fault_cfgSurfBadWrite && !$past(io_fault_cfgSurfBadWrite)) || $past(surfMust || surfOpen));
    a_surf_hold:  assert (!($past(io_fault_cfgSurfBadWrite) && !$past(clrS)) || io_fault_cfgSurfBadWrite);
    a_surf_clear: assert (!$past(io_fault_cfgSurfBadWrite && clrS && !surfMust && !surfOpen) || !io_fault_cfgSurfBadWrite);
    // abort arm
    a_arm_src:  assert (stg_io_armed == $past(stg_io_armed) || $past(W && al && aTag));
    a_arm_set0: assert (!$past(W && al && (A == 12'hF40)) || stg_io_armed[0]);
    a_arm_set1: assert (!$past(W && al && (A == 12'hF44) && (D[27:16] == 12'd0)) || stg_io_armed[1]);
    a_arm_set2: assert (!$past(W && al && (A == 12'hF48) && (D[31:16] == 16'd0)) || stg_io_armed[2]);
    // abort staging value — wdata pin to stg; TAG1 checks only the canon LNID field
    a_tag0_val:  assert (!$past(W && al && (A == 12'hF40)) || stg_io_tag_wave == $past(D));
    a_tag1_lnid: assert (!$past(W && al && (A == 12'hF44) && (D[27:16] == 12'd0)) || stg_io_tag_lnid == $past(D[15:0]));
    a_tag2_val:  assert (!$past(W && al && (A == 12'hF48) && (D[31:16] == 16'd0)) || {stg_io_tag_precision, stg_io_tag_dim} == $past(D[15:0]));
    // cap axes 1/2
    a_cap1_set:  assert (!$past(src1) || capWord_io_word[1]);
    a_cap1_rise: assert (!(capWord_io_word[1] && !$past(capWord_io_word[1])) || $past(src1));
    a_cap1_fall: assert (!($past(capWord_io_word[1]) && !capWord_io_word[1]) || $past(acF90 && D[1]));
    a_cap1_clr:  assert (!$past(capWord_io_word[1] && acF90 && D[1] && !src1) || !capWord_io_word[1]);
    a_cap2_set:  assert (!$past(src2) || capWord_io_word[2]);
    a_cap2_rise: assert (!(capWord_io_word[2] && !$past(capWord_io_word[2])) || $past(src2));
    a_cap2_fall: assert (!($past(capWord_io_word[2]) && !capWord_io_word[2]) || $past(acF90 && D[2]));
    a_cap2_clr:  assert (!$past(capWord_io_word[2] && acF90 && D[2] && !src2) || !capWord_io_word[2]);
  end
`endif

`ifdef WT64TOP_COVER
  // 부류: [무관] = 콘에 절단 핀 없음 (cover [script] 가 강제) · [의존] = 콘에 절단 핀 있음.
  // W1 ← Wt64Top.region_routing · a_cq_strb · a_own_strb — [무관] 완료 구역 마지막 워드와 명령 링 첫 워드의 경계
  always @(posedge clk) if (f_step) w1_cq_last:  cover (cq__io_wstrobe && A == 12'h37C);
  always @(posedge clk) if (f_step) w1_sq_first: cover (W && A == 12'h380 && !own__io_wstrobe && !cq__io_wstrobe && !cfgBlk__io_wstrobe);
  // W2 ← Wt64Top.undefined_offset · a_rd_resv_rv · a_rd_undef — [의존: rvalid OR·rdata mux 콘에 유닛 rvalid 핀] 값은 resvRv/mapRv 만으로 선다 — 실물 도달은 MMIO 궤적뿐
  always @(posedge clk) if (f_step) w2_resv_rd:  cover ($past(R && A == 12'h1FC) && io_mmio_rvalid);
  always @(posedge clk) if (f_step) w2_undef_rd: cover ($past(R && A == 12'hEFC) && io_mmio_rvalid && io_mmio_rdata == 32'd0);
  // W3 ← Wt64Top.wo_read_zero · a_rd_wo — [의존: rdata mux] 키 기입 직후의 되읽기가 0 (mapRv 가 mux 최우선이라 값은 유닛 핀과 무관)
  always @(posedge clk) if (f_step) w3_key_rd_after_wr: cover ($past(R && A == 12'hE80) && $past(W && A == 12'hE80 && D != 32'd0, 2) && io_mmio_rvalid && io_mmio_rdata == 32'd0);
  // W4 ← Wt64Top.ro_write_loud · a_surf_fire — [무관] RO 오프셋(0xF58) 쓰기로 조립 sticky 첫 상승
  always @(posedge clk) if (f_step) w4_ro_wr: cover ($past(W && al && A == 12'hF58 && !io_fault_cfgSurfBadWrite) && io_fault_cfgSurfBadWrite);
  // W5 ← Wt64Top.word_reserved_strict · a_rekey_iff · a_fclr_b0 — [무관] 예약 비0 기입은 거절+loud 이고 효과가 없다
  always @(posedge clk) if (f_step) w5_rekey_rsv: cover ($past(W && al && A == 12'hEBC && D[31:8] != 24'd0 && !io_fault_cfgSurfBadWrite) && io_fault_cfgSurfBadWrite && !$past(mask__io_rekey_valid));
  always @(posedge clk) if (f_step) w5_fclr_rsv:  cover (W && al && A == 12'hF84 && D[19] && D[0] && !io_faultClear_decodeWalk && !walk__io_iFaultClear);
  // W6 ← Wt64Top.partition_reject · a_win_pins — [무관] MASK_PART [7:0]=4 (형상 파티션 수 밖) 거절
  always @(posedge clk) if (f_step) w6_part_rej: cover ($past(W && al && A == 12'hEA0 && D == 32'd4 && !io_fault_cfgSurfBadWrite) && io_fault_cfgSurfBadWrite);
  // W7 ← Wt64Top.surf_fire_beats_clear · a_surf_fire · a_surf_clear — [무관] 해제선과 거절 사건의 겹침 · MMIO W1C 해제
  always @(posedge clk) if (f_step) w7_surf_overlap: cover ($past(W && al && A == 12'hEC0 && io_faultClear_cfgSurfBadWrite && io_fault_cfgSurfBadWrite) && io_fault_cfgSurfBadWrite);
  always @(posedge clk) if (f_step) w7_surf_clear:   cover ($past(io_fault_cfgSurfBadWrite && W && A == 12'hF84 && D == 32'h40) && !io_fault_cfgSurfBadWrite);
  // W8 ← Wt64Top.fault_status_map · a_rd_fst · a_rd_fsum — [의존: rdata mux] [6] 은 조립 sticky 로도 선다 — 실물 도달은 W4 궤적 + 읽기
  always @(posedge clk) if (f_step) w8_fst_rd6: cover ($past(R && A == 12'hF80) && io_mmio_rdata[6]);
  always @(posedge clk) if (f_step) w8_fsum_rd: cover ($past(R && A == 12'hF88) && io_mmio_rdata[0]);
  // W9 ← Wt64Top.fault_clear_routing · a_fclr_b16 — [무관] 19비트 전부 1 인 수락 W1C 가 첫·끝 축에 닿는다
  always @(posedge clk) if (f_step) w9_fclr_all: cover (W && A == 12'hF84 && D[31:19] == 13'd0 && D[18:0] == 19'h7FFFF && walk__io_iFaultClear && cq__io_faultClearOverflow);
  // W10 ← Wt64Top.cap_status_wiring · a_cap0_clr · a_cap2_rise · a_rd_capst — w10_cap0_clr [무관] ·
  //       w10_cap2_gate [의존: walk 핀 — 실물 근거 없음(DecodeWalk 의 등급이 iValid 와 무관하게 계산된다는 설계 서술뿐)] ·
  //       w10_capst_rd2 [의존: walk 핀 — 실물 근거 DecodeWalk_props.sv w3_capabsent]
  always @(posedge clk) if (f_step) w10_cap0_clr:  cover (reasm__io_capAbsentClear && !io_faultClear_reasmCap);
  always @(posedge clk) if (f_step) w10_cap2_gate: cover ($past(walk__io_oCapAbsent && !walk__io_oValid) && !capWord_io_word[2]);
  always @(posedge clk) if (f_step) w10_capst_rd2: cover ($past(R && A == 12'hF8C) && io_mmio_rdata[2]);
  // W11 ← Wt64Top.abort_surface · a_rd_arm · a_fire_route — w11_fire [무관] · w11_arm_rd_full [의존: rdata mux — 무장·태그는 구체 stg]
  always @(posedge clk) if (f_step) w11_fire:        cover (reasm__io_abort_valid);
  always @(posedge clk) if (f_step) w11_arm_rd_full: cover ($past(R && A == 12'hF58) && io_mmio_rdata[2:0] == 3'b111 && $past(stg_io_tag_wave) != 32'd0);
  // W12 ← Wt64Top.mask_surface · a_win_pins · a_key_valid — [무관] 창 3 으로 옮긴 뒤의 키 기입
  always @(posedge clk) if (f_step) w12_key_win3: cover (mask__io_keyWr_valid && mask__io_keyWr_part == 2'd3);
  // W13 ← Mask.rekey_explicit_target · a_rekey_part · a_rekey_iff — [무관] 창과 다른 파티션의 재키잉 (Mask.tla Witness_NoWindowTargetDrift 의 RTL 판)
  always @(posedge clk) if (f_step) w13_rekey_drift: cover (mask__io_rekey_valid && mask__io_rekey_part != mask__io_keyWr_part);
  // W14 ← Wt64Top.fp_surface · a_bind_src — [무관] 결속(en=1) 기입의 발행
  always @(posedge clk) if (f_step) w14_bind_en: cover (fps__io_bindWr_valid && fps__io_bindWr_en);
  // W15 ← Wt64Top.drain_wiring · a_drain_order — [의존: 점유 핀 — 실물 근거 없음]
  always @(posedge clk) if (f_step) w15_drain_nz: cover (cq__io_drain_pipe != 16'd0 && cq__io_drain_tokens != 16'd0);
  // W16 ← Wt64Top.composite_wiring · a_hm_en · a_hm_req — [의존: hiu 핀 — 실물 근거 HiuMask_props.sv w4_misswait_stall · w8_mask_frozen_loaded]
  always @(posedge clk) if (f_step) w16_hm_stall: cover (!mask__io_en && mask__io_req_valid);
  // W17 ← Wt64Top.undefined_offset · a_surf_rise — [무관] 미배선 구역의 표에 없는 워드(0xFC0) 정렬 쓰기 뒤 조립 sticky 가 서지 않는다
  always @(posedge clk) if (f_step) w17_resv_wr: cover ($past(W && al && A == 12'hFC0 && !io_fault_cfgSurfBadWrite) && !io_fault_cfgSurfBadWrite);
`endif
endmodule

bind Wt64Top Wt64Top_props chk (.*);
