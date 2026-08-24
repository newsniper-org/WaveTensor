// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// HiuMask — HiuPipeline × MaskUnit 합성 후-formal 하네스 (§6.3)
//
// 어느 선-formal 모델도 단독 소유하지 않는 첫 **상태열 합성**이다. 결선
// 계약(HiuPipeline.scala io.mask 주석 — 통합자 의무)을 그대로 실물로 잇는다:
//
//   · MaskUnit.io_en   = advance (= HiuPipeline.io_req_ready — 같은 그물)
//   · io.mask.req ↔ MaskUnit.io_req · io.mask.rsp ↔ MaskUnit.io_rsp 직결
//     (io.mask 는 MaskUnit 외에 결선하지 않는다)
//
// 여기서 재는 것 (각 assert 옆에 GUARD-MAP 가드명):
//   · Decode.stall_uniform    — advance 하나가 합성 전 단의 공통 enable.
//     정지 원천(io_hold · E.3 미적중 채움 대기) 무관 전 단이 함께 선다 —
//     MaskUnit 쪽 s4 몸(rValid/rFrame = io_rsp_valid/frame) 포함.
//   · Isolation.coh_no_shortcut / Decode.lookup_unbranched — 상태열 균일:
//     검사자 수리(shift 거울 f_v)가 조회 결과·판정·구성 어느 것도 보지 않고
//     io_req_valid 만 advance 로 시프트하는데, 그것이 단 valid 열과 항상
//     일치한다 → 유효 요청의 단 통과 enable-사이클 수는 상수 6 이다
//     (미적중은 advance 정지로만 나타나고 단 배치는 불변 — §5.3·E.4).
//   · Isolation.no_early_forward — granted 없이 io.rsp 값축(frame·perm)
//     비0 사이클 부재. 승인 전 소비자 관측값은 0 이다.
//   · (결선 계약) MaskUnit 고정 1사이클 왕복 — req.valid → 다음 enable 에
//     rsp.valid. 계약 문면: MaskUnit.scala io.en/io.req 주석.
//
// 대상 SV 는 rtl/generated/ 의 커밋본 그대로 (재생성 금지 — 통합자 보증).

`timescale 1ns/1ps

// ── 합성 top ──────────────────────────────────────────────────────────────
module HiuMask_comp (
  input  wire        clk,
  input  wire        reset,
  // HiuPipeline 외부 표면 (io.mask 제외 전부 노출 — 환경은 자유 입력)
  input  wire        io_req_valid,
  output wire        io_req_ready,
  input  wire [1:0]  io_req_part,
  input  wire [31:0] io_req_vpn,
  input  wire        io_req_write,
  input  wire        io_hold,
  output wire [31:0] io_owner_frame,
  input  wire        io_owner_devOwned,
  input  wire        io_install_valid,
  output wire        io_install_ready,
  input  wire [1:0]  io_install_part,
  input  wire [3:0]  io_install_idx,
  input  wire [27:0] io_install_tag,
  input  wire [31:0] io_install_frame,
  input  wire        io_install_perm_r,
  input  wire        io_install_perm_w,
  input  wire        io_install_perm_x,
  input  wire        io_flush_valid,
  input  wire [1:0]  io_flush_part,
  input  wire        io_hostRsp_valid,
  input  wire [31:0] io_hostRsp_frame,
  input  wire        io_hostRsp_perm_r,
  input  wire        io_hostRsp_perm_w,
  input  wire        io_hostRsp_perm_x,
  output wire        io_rsp_valid,
  output wire        io_rsp_granted,
  output wire [1:0]  io_rsp_part,
  output wire        io_rsp_write,
  output wire        io_rsp_fromFill,
  output wire [31:0] io_rsp_frame,
  output wire        io_rsp_perm_r,
  output wire        io_rsp_perm_w,
  output wire        io_rsp_perm_x,
  output wire [2:0]  io_occupancy,
  output wire        io_faultPerm,
  input  wire        io_faultClear,
  output wire        io_missNotice,
  input  wire        io_missClear,
  // MaskUnit 구성 표면 (자유 입력 — 속성은 구성 무관하게 서야 한다)
  input  wire        io_keyWr_valid,
  input  wire [2:0]  io_keyWr_idx,
  input  wire [31:0] io_keyWr_data,
  input  wire        io_nonceWr_valid,
  input  wire [1:0]  io_nonceWr_part,
  input  wire [2:0]  io_nonceWr_idx,
  input  wire [31:0] io_nonceWr_data,
  input  wire        io_rekey_valid,
  output wire        io_rekey_ready,
  input  wire [1:0]  io_rekey_part,
  output wire [3:0]  io_maskReady,
  output wire        io_busy,
  output wire        io_faultNoMask,
  output wire        io_faultNonceDup,
  output wire        io_faultWrDuringRekey,
  input  wire        io_faultClearNoMask,
  input  wire        io_faultClearNonceDup,
  input  wire        io_faultClearWrRekey
);

  // 결선 계약의 실물 — req↔rsp 직결, en = advance(= io_req_ready)
  wire        mask_req_valid;
  wire [1:0]  mask_req_part;
  wire [31:0] mask_req_frame;
  wire        mask_rsp_valid;
  wire [31:0] mask_rsp_frame;

  HiuPipeline u_pipe (
    .io_req_valid       (io_req_valid),
    .io_req_ready       (io_req_ready),
    .io_req_part        (io_req_part),
    .io_req_vpn         (io_req_vpn),
    .io_req_write       (io_req_write),
    .io_hold            (io_hold),
    .io_owner_frame     (io_owner_frame),
    .io_owner_devOwned  (io_owner_devOwned),
    .io_mask_req_valid  (mask_req_valid),
    .io_mask_req_part   (mask_req_part),
    .io_mask_req_frame  (mask_req_frame),
    .io_mask_rsp_valid  (mask_rsp_valid),
    .io_mask_rsp_frame  (mask_rsp_frame),
    .io_install_valid   (io_install_valid),
    .io_install_ready   (io_install_ready),
    .io_install_part    (io_install_part),
    .io_install_idx     (io_install_idx),
    .io_install_tag     (io_install_tag),
    .io_install_frame   (io_install_frame),
    .io_install_perm_r  (io_install_perm_r),
    .io_install_perm_w  (io_install_perm_w),
    .io_install_perm_x  (io_install_perm_x),
    .io_flush_valid     (io_flush_valid),
    .io_flush_part      (io_flush_part),
    .io_hostRsp_valid   (io_hostRsp_valid),
    .io_hostRsp_frame   (io_hostRsp_frame),
    .io_hostRsp_perm_r  (io_hostRsp_perm_r),
    .io_hostRsp_perm_w  (io_hostRsp_perm_w),
    .io_hostRsp_perm_x  (io_hostRsp_perm_x),
    .io_rsp_valid       (io_rsp_valid),
    .io_rsp_granted     (io_rsp_granted),
    .io_rsp_part        (io_rsp_part),
    .io_rsp_write       (io_rsp_write),
    .io_rsp_fromFill    (io_rsp_fromFill),
    .io_rsp_frame       (io_rsp_frame),
    .io_rsp_perm_r      (io_rsp_perm_r),
    .io_rsp_perm_w      (io_rsp_perm_w),
    .io_rsp_perm_x      (io_rsp_perm_x),
    .io_occupancy       (io_occupancy),
    .io_faultPerm       (io_faultPerm),
    .io_faultClear      (io_faultClear),
    .io_missNotice      (io_missNotice),
    .io_missClear       (io_missClear),
    .clk                (clk),
    .reset              (reset)
  );

  MaskUnit u_mask (
    .io_keyWr_valid         (io_keyWr_valid),
    .io_keyWr_idx           (io_keyWr_idx),
    .io_keyWr_data          (io_keyWr_data),
    .io_nonceWr_valid       (io_nonceWr_valid),
    .io_nonceWr_part        (io_nonceWr_part),
    .io_nonceWr_idx         (io_nonceWr_idx),
    .io_nonceWr_data        (io_nonceWr_data),
    .io_rekey_valid         (io_rekey_valid),
    .io_rekey_ready         (io_rekey_ready),
    .io_rekey_part          (io_rekey_part),
    .io_maskReady           (io_maskReady),
    .io_busy                (io_busy),
    .io_en                  (io_req_ready),   // ← 결선 계약: en = advance
    .io_req_valid           (mask_req_valid),
    .io_req_part            (mask_req_part),
    .io_req_frame           (mask_req_frame),
    .io_rsp_valid           (mask_rsp_valid),
    .io_rsp_frame           (mask_rsp_frame),
    .io_faultNoMask         (io_faultNoMask),
    .io_faultNonceDup       (io_faultNonceDup),
    .io_faultWrDuringRekey  (io_faultWrDuringRekey),
    .io_faultClearNoMask    (io_faultClearNoMask),
    .io_faultClearNonceDup  (io_faultClearNonceDup),
    .io_faultClearWrRekey   (io_faultClearWrRekey),
    .clk                    (clk),
    .reset                  (reset)
  );

  // ── ENV assume: 단발 reset 프로토콜 ──────────────────────────────────────
  // 근거: 전원 인가 시 reset 어서션 후 해제 — async-reset 레지스터의 형식
  // 검사 초기화 규약 (설계 자체가 reset 으로 초기 상태를 정의한다. 재어서션
  // 없는 정상 동작 구간이 검사 대상 — GUARD-MAP 의 모든 속성은 reset 밖
  // 문면이다). 그 외 assume 없음 — 모든 기능 입력은 자유.
  reg f_init = 1'b1;
  always @(posedge clk) f_init <= 1'b0;
  always @(*) begin
    if (f_init) assume (reset);
    else        assume (!reset);
  end
endmodule

// ── HiuPipeline 쪽 검사자 (bind) ──────────────────────────────────────────
module HiuPipeline_props (
  input wire         clk,
  input wire         reset,
  input wire         advance,
  input wire         io_req_valid,
  input wire         io_mask_rsp_valid,   // 합성에서 MaskUnit.rValid — s4 valid
  input wire         io_rsp_valid,
  input wire         io_rsp_granted,
  input wire [31:0]  io_rsp_frame,
  input wire         io_rsp_perm_r,
  input wire         io_rsp_perm_w,
  input wire         io_rsp_perm_x,
  input wire         s1_valid,
  input wire         s2_valid,
  input wire         s3_valid,
  input wire         s5_valid,
  input wire         s6_valid,
  input wire [288:0] f_stage_data         // 전 단 수송 몸체 레지스터 연접
);
  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;
  wire f_ok = f_past_valid && !reset && !$past(reset);

  // 상태열 거울 — io_req_valid 만 advance 로 시프트. 조회 결과·판정을 일절
  // 보지 않는 수리이므로, 아래 일치 assert 가 서면 단 통과가 요청 내용과
  // 무관(상수 6 enable-사이클)임이 증명된다.
  reg [6:1] f_v = 6'h0;
  always @(posedge clk) begin
    if (reset)        f_v <= 6'h0;
    else if (advance) f_v <= {f_v[5:1], io_req_valid};
  end

  always @(posedge clk) begin
    if (f_ok) begin
      // Isolation.coh_no_shortcut · Decode.lookup_unbranched — 상태열 균일:
      // 거울과 단 valid 열의 전 지점 일치 (s4 는 MaskUnit rValid — 합성 결선)
      assert (f_v[1] == s1_valid);
      assert (f_v[2] == s2_valid);
      assert (f_v[3] == s3_valid);
      assert (f_v[4] == io_mask_rsp_valid);
      assert (f_v[5] == s5_valid);
      assert (f_v[6] == s6_valid);
      // 응답은 정확히 6번째 enable 지점에서만 — 이르지도 늦지도 않다
      assert (io_rsp_valid == (f_v[6] && advance));

      // Decode.stall_uniform — advance 하나가 전 단의 공통 enable. 정지
      // 원천 무관 전 단이 함께 선다. (sticky fault 레지스터
      // _zz_io_faultPerm/_zz_io_missNotice 는 단 수송 몸체가 아니라 제외 —
      // GUARD-MAP 문면의 "나머지 단·필드" = when(advance) 안의 것들.)
      if (!$past(advance)) begin
        assert ($stable({s1_valid, s2_valid, s3_valid, s5_valid, s6_valid}));
        assert ($stable(f_stage_data));
      end
    end
  end

  // Isolation.no_early_forward — granted 없이 값축 비0 사이클 부재 (조합).
  // 승인(s6 조합 판정) 전의 어떤 단 값도 io.rsp 에 닿지 않는다.
  always @(*) begin
    if (f_past_valid && !reset) begin
      if (io_rsp_frame != 32'h0 || io_rsp_perm_r || io_rsp_perm_w || io_rsp_perm_x)
        assert (io_rsp_granted);
    end
  end
endmodule

bind HiuPipeline HiuPipeline_props u_hiu_props (
  .clk               (clk),
  .reset             (reset),
  .advance           (advance),
  .io_req_valid      (io_req_valid),
  .io_mask_rsp_valid (io_mask_rsp_valid),
  .io_rsp_valid      (io_rsp_valid),
  .io_rsp_granted    (io_rsp_granted),
  .io_rsp_frame      (io_rsp_frame),
  .io_rsp_perm_r     (io_rsp_perm_r),
  .io_rsp_perm_w     (io_rsp_perm_w),
  .io_rsp_perm_x     (io_rsp_perm_x),
  .s1_valid          (s1_valid),
  .s2_valid          (s2_valid),
  .s3_valid          (s3_valid),
  .s5_valid          (s5_valid),
  .s6_valid          (s6_valid),
  .f_stage_data      ({s1_part, s1_vpn, s1_write,
                       s2_part, s2_vpn, s2_write,
                       s3_part, s3_vpn, s3_write,
                       s4_part, s4_write, s4_anyHit, s4_fromFill, s4_frame,
                       s4_perm_r, s4_perm_w, s4_perm_x,
                       s5_part, s5_write, s5_anyHit, s5_fromFill, s5_frame,
                       s5_masked, s5_perm_r, s5_perm_w, s5_perm_x,
                       s6_part, s6_write, s6_anyHit, s6_fromFill, s6_frame,
                       s6_masked, s6_perm_r, s6_perm_w, s6_perm_x})
);

// ── MaskUnit 쪽 검사자 (bind) ─────────────────────────────────────────────
module MaskUnit_props (
  input wire        clk,
  input wire        reset,
  input wire        io_en,
  input wire        io_req_valid,
  input wire        io_rsp_valid,
  input wire [31:0] io_rsp_frame
);
  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;
  wire f_ok = f_past_valid && !reset && !$past(reset);

  always @(posedge clk) begin
    if (f_ok) begin
      // Decode.stall_uniform — MaskUnit 쪽 s4 몸(rValid/rFrame)도 en(=advance)
      // 이 낮으면 함께 선다. 구성 기입(keyWr/nonceWr/rekey)이 무엇을 하든.
      if (!$past(io_en))
        assert ($stable({io_rsp_valid, io_rsp_frame}));
      // (결선 계약) 고정 1사이클 왕복 — req.valid → 바로 다음 enable 에
      // rsp.valid. 가변 지연·조기 응답 부재 (MaskUnit.scala io.req 문면).
      if ($past(io_en))
        assert (io_rsp_valid == $past(io_req_valid));
    end
  end
endmodule

bind MaskUnit MaskUnit_props u_mask_props (
  .clk          (clk),
  .reset        (reset),
  .io_en        (io_en),
  .io_req_valid (io_req_valid),
  .io_rsp_valid (io_rsp_valid),
  .io_rsp_frame (io_rsp_frame)
);
