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
//   · Isolation.approve_gates_value — **값축**: io.rsp 값축(frame·perm)이
//     비0 인 사이클은 granted 인 사이클뿐. 승인 게이트가 값을 통제하는
//     유일 지점이다 (Isolation.tla:585-588 RequestApprove 의 obsVal').
//   · Isolation.no_early_forward — **시간축**: 그 값이 실리는 사이클은 거울의
//     6번째 지점(f_v[6] = 승인 단)뿐. 실행(s5)과 승인(s6) 사이의 일시
//     누출 부재 (Isolation.tla:554-558 — 「둘은 같은 규범의 서로 다른 두 항」).
//   · Isolation.query_no_serve / Platform.xlate_local(우선순위 축) — 로컬
//     저장 leg 이 답하면 s4 로 들어가는 값은 저장 leg 값 그 자체다.
//     호스트 leg 은 로컬 미적중일 때만 소비되는 최하 순위다.
//   · Decode.evict_inline — advance 에지의 s4 몸은 조회 데이터 그 자체.
//     대체 전용 상태도 대체 전용 데이터 경로도 없다 (+ 대체 궤적 도달 증인).
//   · Platform.owner_check — granted ⊆ devOwned · 비소유의 값 차단 ·
//     비소유 적중의 loud fault (sticky 상승 + 명시 해제 없는 비하강).
//   · (결선 계약) MaskUnit 고정 1사이클 왕복 — req.valid → 다음 enable 에
//     rsp.valid. 계약 문면: MaskUnit.scala io.en/io.req 주석.
//
// 이 태스크가 **재지 않는** 것과 그 근거는 hiumask.sby 머리의
// 「§미측정 잔여」에 적는다 (Isolation.query_offpath 구조 skip ·
// no_early_forward 문면의 오계수 · xlate_local 지속 상태 축 · evict_inline
// 기입 축의 XlateStore 귀속). 거짓 앵커를 다느니 안 재는 것이 낫다.
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
  input wire         io_hold,             // 증인 전용 — 정지 *원천*을 갈라 본다
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
  input wire [288:0] f_stage_data,        // 전 단 수송 몸체 레지스터 연접
  // ── 2차 파도 신설 tap (전부 HiuPipeline 스코프의 평범한 신호다 —
  //    줄번호 매인 생성 이름 when_*_l<N> 은 하나도 쓰지 않는다) ───────────
  input wire         io_owner_devOwned,   // 소유권 판정 입력 (자유 입력)
  input wire         io_faultPerm,        // sticky 권한 위반 (관측면 출력)
  input wire         io_faultClear,       // 그 명시 해제 (자유 입력)
  input wire         io_flush_valid,
  input wire [1:0]   io_flush_part,
  input wire         io_hostRsp_valid,
  input wire [31:0]  io_hostRsp_frame,
  input wire [1:0]   s3_part,
  input wire [31:0]  s3_vpn,
  input wire         s4_anyHit,
  input wire         s4_fromFill,
  input wire [31:0]  s4_frame,
  input wire         s4_perm_r,
  input wire         s4_perm_w,
  input wire         s4_perm_x,
  input wire         s6_anyHit,
  input wire         s6_write,
  input wire         s6_perm_r,
  input wire         s6_perm_w,
  // 조회 응답 — XlateStore 인스턴스 출력 (로컬 저장 leg + 호스트 leg 분리)
  input wire         x_hit,               // xlate.io_rsp_hit   (로컬 leg 판정)
  input wire         x_fromFill,          // xlate.io_rsp_fromFill
  input wire [31:0]  x_frame,             // xlate.io_rsp_frame (로컬 leg 값)
  input wire         x_perm_r,
  input wire         x_perm_w,
  input wire         x_perm_x,
  input wire         x_hostPresent,       // xlate.io_rsp_hostPresent (호스트 leg)
  // 값 접기 결과 — s4 로 들어가는 것 (io.mask.req.frame 과 같은 그물)
  input wire         lookAny,
  input wire [31:0]  lookFrame,
  input wire         lookPerm_r,
  input wire         lookPerm_w,
  input wire         lookPerm_x
);
  // f_ok — 「직전 에지도 이번 에지도 reset 밖」. $past(reset) 을 쓰지 않고
  // 명시 레지스터로 지연시킨다: yosys 0.66 은 clocked block 밖의 $past 를
  // 거절한다 (실측 ERROR). 의미는 동일하며 MemOrderGate/Reassembly/XlateStore
  // 하네스와 같은 관용구다.
  reg f_past_valid = 1'b0;
  reg f_past_reset = 1'b1;
  always @(posedge clk) begin
    f_past_valid <= 1'b1;
    f_past_reset <= reset;
  end
  wire f_ok = f_past_valid && !reset && !f_past_reset;

  // 상태열 거울 — io_req_valid 만 advance 로 시프트. 조회 결과·판정을 일절
  // 보지 않는 수리이므로, 아래 일치 assert 가 서면 단 통과가 요청 내용과
  // 무관(상수 6 enable-사이클)임이 증명된다.
  reg [6:1] f_v = 6'h0;
  always @(posedge clk) begin
    if (reset)        f_v <= 6'h0;
    else if (advance) f_v <= {f_v[5:1], io_req_valid};
  end

  // 지상 진리 — 승인 단에 선 비소유(또는 무자격) 적중. DUT 의 permViol
  // 신호를 참조하지 않고 단 몸과 자유 입력으로 다시 쓴다 (검사 어휘로
  // 지상 진리를 적으면 그 신호를 지운 구현에서 전건이 함께 사라진다).
  wire f_nonowned_hit = s6_valid && s6_anyHit
                        && !(io_owner_devOwned && (s6_write ? s6_perm_w : s6_perm_r));

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

      // ── Decode.evict_inline — 캡처 축 (2026-08-26 신설) ─────────────────
      // 전진 에지의 s4 몸은 *그 사이클의 조회 데이터 그 자체*다. 대체
      // (유효 ∧ 태그 불일치)에 전용 상태도, 전용 데이터 경로도, 전용
      // 판정 비트도 없다 — 대체는 미적중과 똑같이 anyHit=0 캡처로만
      // 나타난다. 축출 상태를 둔 구현(대체 사이클에 다른 것을 싣거나
      // 단을 한 번 더 도는 구현)이면 여기서 반례가 난다.
      //   ※ 항진 아님: s4_* 는 EN=advance 인 DFF, $past(·) 는 EN=1 인
      //     별개의 그림자 DFF 다. 두 셀이 병합될 수 없으므로 등식이
      //     상수로 접히지 않는다 (완료 기준 ②).
      if ($past(advance)) begin
        assert (s4_anyHit   == $past(lookAny));
        assert (s4_fromFill == $past(x_fromFill));
        assert (s4_frame    == $past(lookFrame));
        assert ({s4_perm_x, s4_perm_w, s4_perm_r}
                  == $past({lookPerm_x, lookPerm_w, lookPerm_r}));
      end

      // ── Platform.owner_check ③ — loud fault (승격 항목 1: fault 축) ─────
      // 비소유(또는 무자격) 적중이 승인 단에 서면 *다음 에지에* sticky 가
      // 선다. 전건은 permViol 의 재인용이 아니라 지상 진리(승인 단의 단
      // 몸 + 자유 입력 devOwned)로 적는다 — 그래야 permViol 을 지워도
      // 반례가 난다. 해제와의 우선순위는 RTL 이 permViol 우선이므로
      // faultClear 를 전건에서 빼지 않는다 (뺐다면 그것이 반례 원천).
      if ($past(f_nonowned_hit))
        assert (io_faultPerm);
      // 그리고 명시 해제 없이는 내려가지 않는다 — 「크게 알린다」의 둘째 항.
      if ($past(io_faultPerm) && !$past(io_faultClear))
        assert (io_faultPerm);
    end
  end

  // ── 승인 게이트의 두 항 + 소유권 축 + 조회 leg 우선순위 (조합) ─────────
  always @(*) begin
    if (f_past_valid && !reset) begin
      // Isolation.approve_gates_value — **값축**. 값이 실린 사이클은 승인
      // 사이클뿐이다. 미승인 요청의 값 축 관측은 0 (Isolation.tla:585-588).
      if (io_rsp_frame != 32'h0 || io_rsp_perm_r || io_rsp_perm_w || io_rsp_perm_x)
        assert (io_rsp_granted);

      // Isolation.no_early_forward — **시간축**. 그 값이 실리는 사이클은
      // 거울의 6번째 지점뿐이다. 거울 f_v 는 조회·판정을 일절 보지 않고
      // io_req_valid 만 advance 로 시프트하므로, 승인 판정을 s5 로 당기고
      // 값도 함께 당기는 구현(모델의 fwd = 실행·승인 사이 일시 누출)이면
      // f_v[6]=0 인 사이클에 값이 실려 반례가 난다. approve_gates_value 는
      // 그것을 잡지 못한다 — 값축은 「granted 라는 이름의 게이트」만 보고
      // 그 게이트가 *어느 단에 앉아 있는지*를 보지 않기 때문이다
      // (Isolation.tla:554-558 의 분업 문면 그대로).
      if (io_rsp_frame != 32'h0 || io_rsp_perm_r || io_rsp_perm_w || io_rsp_perm_x)
        assert (f_v[6]);

      // Platform.owner_check ① — granted 는 devOwned 를 논리곱의 항으로
      // 요구한다. A 입력이 모듈 자유 입력 그 자체라 상수가 될 수 없다.
      if (io_rsp_granted)
        assert (io_owner_devOwned);

      // Platform.owner_check ② — 비소유의 **값 차단**. 전건을 devOwned 로
      // 두는 것이 요점이다: !granted 로 두면 approve_gates_value 의
      // 재인용이 되어 자격(entitle)만 다른 경우와 갈리지 않는다.
      if (!io_owner_devOwned)
        assert (io_rsp_frame == 32'h0
                && !io_rsp_perm_r && !io_rsp_perm_w && !io_rsp_perm_x);

      // Isolation.query_no_serve + Platform.xlate_local(우선순위 축) —
      // 로컬 저장 leg 이 답하는 사이클에 s4 로 들어가는 값(= io.mask.req
      // .frame 과 같은 그물)은 저장 leg 값 그 자체다. 호스트 leg 이 그
      // 자리를 이기는 구현이면(elsewhen 순서를 뒤집으면) 두 leg 이 다른
      // 값을 들고 있는 궤적에서 즉시 반례가 난다 — 그 궤적의 도달성은
      // 증인 W9 가 든다.
      if (x_hit) begin
        assert (lookFrame == x_frame);
        assert ({lookPerm_x, lookPerm_w, lookPerm_r} == {x_perm_x, x_perm_w, x_perm_r});
      end
    end
  end

  // ── cover 증인 — 공허 아님의 증거 (2026-08-25 신설) ─────────────────────
  //
  // 위 여섯 일치 assert 는 *등식*이라 「아무것도 흐르지 않는 세계」에서
  // 0 == 0 으로 자명하게 선다. stall_uniform 의 $stable 단언도 마찬가지로
  // 「단이 언제나 비어 있다」면 공허하다. 아래 증인이 reset 으로부터
  // 실제로 요청이 흐르고, 실제로 멈추고, 실제로 승인·거절된다는 것을 보인다.
  //   ※ sby 의 cover 모드는 chformal -assert -remove 로 단언을 스스로
  //     떼어낸다. 증인이 적법 궤적 위에 있다는 것은 bmc 태스크가 보증한다.
`ifdef HIUMASK_COVER
  // W1 ← Isolation.coh_no_shortcut · Decode.lookup_unbranched
  //      6단 전 구간을 요청이 실제로 통과해 응답이 나온다 (거울 전 지점이
  //      1 을 실어 본다 — 등식 여섯이 0==0 이 아니다)
  always @(posedge clk) if (f_ok) w1_rsp: cover (io_rsp_valid);

  // W2 ← Isolation.coh_no_shortcut · Decode.lookup_unbranched
  //      파이프가 실제로 파이프다: 서로 다른 두 요청이 동시에 비행 중
  //      (거울 양 끝이 동시에 1)
  always @(posedge clk) if (f_ok) w2_two_inflight: cover (f_v[1] && f_v[6]);

  // W3 ← Decode.stall_uniform
  //      전제 ①: io_hold 발 정지를 *내용이 실린* 단이 건넌다
  always @(posedge clk)
    if (f_ok && !$past(advance) && $past(io_hold))
      w3_hold_loaded: cover (s3_valid || s5_valid || s6_valid);

  // W4 ← Decode.stall_uniform
  //      전제 ②: io_hold 가 아닌 정지 — E.3 미적중 채움
  //      대기(missWait) 발. 「정지 원천 무관」이 두 원천 모두에서 재어진다는
  //      증거 (하나뿐이면 그 문면이 절반만 실측된 것이다)
  always @(posedge clk)
    if (f_ok && !$past(advance) && !$past(io_hold))
      w4_misswait_stall: cover (s3_valid);

  // W5 ← Isolation.approve_gates_value · Isolation.no_early_forward
  //      활성면: 승인이 실제로 나고 값축이 비0 이다
  //      (이것 없이는 「무엇도 승인되지 않는 기계」가 단언을 통과한다)
  always @(posedge clk) if (f_ok) w5_granted_nonzero: cover (io_rsp_granted && (io_rsp_frame != 32'h0));

  // W6 ← Isolation.approve_gates_value
  //      그 반대면: 유효 응답인데 승인이 없고, 그래서 값축이 0 이다
  //      (거절이 실제로 값을 지운다 — 두 면을 함께 둬야 계약이 잠긴다)
  always @(posedge clk)
    if (f_ok) w6_denied_zero: cover (io_rsp_valid && !io_rsp_granted && (io_rsp_frame == 32'h0)
                     && !io_rsp_perm_r && !io_rsp_perm_w && !io_rsp_perm_x);

  // ── 2차 파도 증인 (2026-08-26 신설) ────────────────────────────────────
  //
  // 대체 궤적 추적기 — 「축출 상태 없음」의 도달성 증거를 만드는 도구다.
  // 저장 leg 적중(fromFill=0)을 한 번 관측하면 그 순간 그 칸의 유효 비트가
  // 1 이었다는 뜻이다. XlateStore 의 유효 비트는 커밋이 *세우기만* 하고
  // flush 만 내리므로(생성 SV 의 validBits 전이 전수), flush 가 없는 한
  // 그 칸은 계속 유효하다. 그래서 「같은 파티션·같은 idx 를 *다른 태그*로
  // 조회하는 사이클」 = 유효 ∧ 태그 불일치 = §3.6.2 규범 4 의 대체다.
  // 사이 커밋이 태그를 갈아치웠더라도 증인은 건전하다 — 그때는 적중이
  // 나므로 `!x_hit` 가 그 경우를 그 자리에서 배제한다.
  reg        f_ev_seen = 1'b0;
  reg [1:0]  f_ev_part;
  reg [3:0]  f_ev_idx;
  reg [27:0] f_ev_tag;
  always @(posedge clk) begin
    if (reset) f_ev_seen <= 1'b0;
    else if (s3_valid && x_hit && !x_fromFill
             && !(io_flush_valid && (io_flush_part == s3_part))) begin
      f_ev_seen <= 1'b1;
      f_ev_part <= s3_part;
      f_ev_idx  <= s3_vpn[3:0];      // XlateStore reqIdx = vpn(3 downto 0)
      f_ev_tag  <= s3_vpn[31:4];     // XlateStore reqTag = vpn(31 downto 4)
    end else if (io_flush_valid && (io_flush_part == f_ev_part)) begin
      f_ev_seen <= 1'b0;
    end
  end
  wire f_replace = f_ev_seen && s3_valid && (s3_part == f_ev_part)
                   && (s3_vpn[3:0] == f_ev_idx) && (s3_vpn[31:4] != f_ev_tag);

  // 그 대체 요청을 단으로 실어 나르는 꼬리표 (거울과 같은 enable)
  reg [6:4] f_rep = 3'h0;
  always @(posedge clk) begin
    if (reset)        f_rep <= 3'h0;
    else if (advance) f_rep <= {f_rep[5:4], (f_replace && !x_hit)};
  end

  // W9 ← Isolation.query_no_serve · Platform.xlate_local
  //      활성면: 두 leg 이 실제로 *충돌*
  //      한다 (같은 사이클에 로컬 적중 + 호스트 응답이 다른 frame).
  //      이것 없이는 우선순위 단언이 「호스트 leg 이 죽어 있는 세계」에서
  //      자명하다.
  always @(posedge clk)
    if (f_ok) w9_leg_clash: cover (x_hit && io_hostRsp_valid && (io_hostRsp_frame != x_frame));

  // W10 ← Isolation.query_no_serve · Platform.xlate_local
  //       그 반대면: 로컬 미적중일 때 호스트 leg 이 실제로 소비된다.
  //       (최하 순위 가지가 살아 있어야 「최하 순위」가 명제다)
  always @(posedge clk)
    if (f_ok) w10_host_leg_used: cover (s3_valid && !x_hit && x_hostPresent
                     && (lookFrame == io_hostRsp_frame) && (io_hostRsp_frame != 32'h0));

  // W11 ← Decode.evict_inline
  //       본체: 대체 궤적이 실제로 도달 가능하다
  //       (유효한 칸을 다른 태그로 조회 → 미적중으로만 나타난다)
  always @(posedge clk) if (f_ok) w11_replace_reached: cover (f_replace && !x_hit);

  // W12 ← Decode.evict_inline · Isolation.coh_no_shortcut
  //       그 대체 요청이 여섯 단을 완주해 응답이 난다. 거울 등식은 전
  //       궤적에 대해 서 있으므로, 대체 궤적이 도달 가능하다는 이 증인이
  //       「대체가 단계열을 바꾸지 않는다」의 실측이다.
  always @(posedge clk) if (f_ok) w12_replace_completes: cover (f_rep[6] && io_rsp_valid);

  // W13 ← Platform.owner_check · Isolation.approve_gates_value
  //       비소유 적중이 실제로 일어나고, 값이 차단된 채로
  //       크게 알려진다 (fault 축의 활성면 — 승격 항목 1)
  always @(posedge clk)
    if (f_ok) w13_nonowner_loud: cover (io_rsp_valid && !io_owner_devOwned && !io_rsp_granted
                     && (io_rsp_frame == 32'h0) && io_faultPerm);

  // W14 ← Platform.owner_check
  //       sticky 가 *처음* 서는 순간. 이미 서 있는 상태를 지나가는 것과
  //       구분되지 않으면 loud 단언이 「늘 1 인 비트」로 자명해진다.
  always @(posedge clk) if (f_ok) w14_fault_rise: cover (!$past(io_faultPerm) && io_faultPerm);

  // W15 ← Platform.owner_check
  //       해제가 실제로 가능하다 (영구 1 이 아니다 — 위 자명화의 반대면)
  always @(posedge clk) if (f_ok) w15_fault_clear: cover ($past(io_faultPerm) && !io_faultPerm);
`endif // HIUMASK_COVER
endmodule

// ── MaskUnit 쪽 검사자 (bind) ─────────────────────────────────────────────
module MaskUnit_props (
  input wire        clk,
  input wire        reset,
  input wire        io_en,
  input wire        io_req_valid,
  input wire        io_rsp_valid,
  input wire [31:0] io_rsp_frame
);
  // f_ok — HiuPipeline_props 와 같은 관용구 (위 주석 참조).
  reg f_past_valid = 1'b0;
  reg f_past_reset = 1'b1;
  always @(posedge clk) begin
    f_past_valid <= 1'b1;
    f_past_reset <= reset;
  end
  wire f_ok = f_past_valid && !reset && !f_past_reset;

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

  // ── cover 증인 ──────────────────────────────────────────────────────────
`ifdef HIUMASK_COVER
  // W7 ← Decode.stall_uniform
  //      마스크 왕복이 실제로 돈다: 응답이 서고 값축이 비0 이다
  //      (rValid 가 늘 0 이면 위 왕복 등식이 0==0 으로 공허하다)
  always @(posedge clk) if (f_ok) w7_mask_roundtrip: cover (io_rsp_valid && (io_rsp_frame != 32'h0));

  // W8 ← Decode.stall_uniform
  //      MaskUnit 쪽 전제: en 이 낮은 에지를 *실린* 응답이
  //      건넌다 (rsp_valid 가 1 인 채로 동결 — 0 인 채 동결이 아니다)
  always @(posedge clk)
    if (f_ok && !$past(io_en)) w8_mask_frozen_loaded: cover (io_rsp_valid && (io_rsp_frame != 32'h0));
`endif // HIUMASK_COVER
endmodule

bind MaskUnit MaskUnit_props u_mask_props (
  .clk          (clk),
  .reset        (reset),
  .io_en        (io_en),
  .io_req_valid (io_req_valid),
  .io_rsp_valid (io_rsp_valid),
  .io_rsp_frame (io_rsp_frame)
);

// ── HiuPipeline 쪽 bind — 파일 *맨 끝*이어야 한다.
// hiumask.sby 의 텍스트 전개가 두 bind 를 「MaskUnit 것 먼저, HiuPipeline 것
// 마지막」 순서로 잘라낸다 (sed 종료 주소에 ';' 와 ')' 를 쓸 수 없어 — yosys
// exec 의 인용 전달이 깨진다 — 시작 패턴 + 파일 끝으로만 구간을 짚는다).
bind HiuPipeline HiuPipeline_props u_hiu_props (
  .clk               (clk),
  .reset             (reset),
  .advance           (advance),
  .io_hold           (io_hold),
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
                       s6_masked, s6_perm_r, s6_perm_w, s6_perm_x}),
  .io_owner_devOwned (io_owner_devOwned),
  .io_faultPerm      (io_faultPerm),
  .io_faultClear     (io_faultClear),
  .io_flush_valid    (io_flush_valid),
  .io_flush_part     (io_flush_part),
  .io_hostRsp_valid  (io_hostRsp_valid),
  .io_hostRsp_frame  (io_hostRsp_frame),
  .s3_part           (s3_part),
  .s3_vpn            (s3_vpn),
  .s4_anyHit         (s4_anyHit),
  .s4_fromFill       (s4_fromFill),
  .s4_frame          (s4_frame),
  .s4_perm_r         (s4_perm_r),
  .s4_perm_w         (s4_perm_w),
  .s4_perm_x         (s4_perm_x),
  .s6_anyHit         (s6_anyHit),
  .s6_write          (s6_write),
  .s6_perm_r         (s6_perm_r),
  .s6_perm_w         (s6_perm_w),
  .x_hit             (xlate_io_rsp_hit),
  .x_fromFill        (xlate_io_rsp_fromFill),
  .x_frame           (xlate_io_rsp_frame),
  .x_perm_r          (xlate_io_rsp_perm_r),
  .x_perm_w          (xlate_io_rsp_perm_w),
  .x_perm_x          (xlate_io_rsp_perm_x),
  .x_hostPresent     (xlate_io_rsp_hostPresent),
  .lookAny           (lookAny),
  .lookFrame         (lookFrame),
  .lookPerm_r        (lookPerm_r),
  .lookPerm_w        (lookPerm_w),
  .lookPerm_x        (lookPerm_x)
);
