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
//     그리고 **정지 원천 자체가 그 둘뿐**이다 (2026-08-31 신설):
//     advance == !io_hold && !(s3_valid && !x_hit). E.3 2항 파생 요건
//     「정지를 푸는 것은 항목 기입뿐이다」의 관측형이며, 호스트 응답이
//     정지 해제 주체가 될 수 없음을 기계로 세운다.
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
//   · Isolation.query_no_serve / Platform.xlate_local — **양 면 다** 잰다
//     (2026-08-31 확장). 적중 면: 로컬 저장 leg 이 답하면 s4 로 들어가는
//     값은 저장 leg 값 그 자체다. **미적중 면**: 로컬이 미적중이면 값은
//     0 이고 판정 비트는 0 이다 — 호스트 응답이 서 있어도 그렇다.
//     종전 판은 적중 면만 재서 정의역이 구멍의 *여집합*이었다: 실제 구멍은
//     「로컬이 답할 때」가 아니라 「로컬이 미적중일 때」에 있었고, 그
//     사이클에 호스트 leg 이 값·판정·정지 셋 다에 들어갔다
//     (§3.3.1 규범 2 「늘어도 안 된다」 위반 · HIU-11 세 축).
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
  //
  // ※ `lookAny` tap 은 2026-08-31 파도가 **뺐다**. 그것은 DUT 자신의 판정
  //    어휘였고, 지상 진리로 쓰는 순간 「lookAny 가 무엇으로 정의되든 참」인
  //    등식이 된다 — 아래 `f_nonowned_hit` 선언이 permViol 에 대해 스스로
  //    적어 둔 함정을 이 자리에서만 어기고 있었다 (「검사 어휘로 지상 진리를
  //    적으면 그 신호를 지운 구현에서 전건이 함께 사라진다」 — 좌표가 아니라
  //    식별자로 가리킨다. 줄 좌표는 이 파일을 고칠 때마다 미끄러지고, 실제로
  //    이 파도의 첫 판이 그렇게 미끄러졌다). 판정 축의 지상 진리는 XlateStore 의
  //    독립 출력 `x_hit` 하나다. (수리로 lookAny 는 넷 자체가 사라졌다 —
  //    「그 신호를 지운 구현에서 전건이 함께 사라진다」의 실물이다.)
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
      //   ※ 판정 비트의 우변은 `x_hit` 다 — 종전 판(2026-08-26)은
      //     `$past(lookAny)` 였고, 그것은 DUT 의 판정 어휘를 지상 진리로
      //     삼아 lookAny 의 정의가 무엇이든(hit || hostPresent 여도) 참이
      //     되는 등식이었다. `f_nonowned_hit` 선언의 규율을 permViol 에만
      //     지키고 이 자리에 빠뜨린 결함이다 (2026-08-31 수리). x_hit 는
      //     XlateStore 소유의 독립 출력이라 접기 정의와 무관하다.
      //   ※ 반증력 실측 — 아래 §반증력 실측표의 ① 항.
      if ($past(advance)) begin
        assert (s4_anyHit   == $past(x_hit));
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

      // Isolation.query_no_serve + Platform.xlate_local — *적중 면*.
      // 로컬 저장 leg 이 답하는 사이클에 s4 로 들어가는 값(= io.mask.req
      // .frame 과 같은 그물)은 저장 leg 값 그 자체다. 두 leg 이 다른 값을
      // 들고 있는 궤적의 도달성은 증인 W9 가 든다.
      //
      //   ※ 2026-08-31 주석 수리. 종전 문면은 이 단언이 무는 변이를
      //     「elsewhen 순서를 뒤집으면」이라 적었는데, 그 문법은 이 파도가
      //     지웠다 — HiuPipeline.scala 의 접기에는 `when(xlate.io.rsp.hit)`
      //     한 가지뿐이라 「순서 뒤집기」가 표현 불가다. 오늘 이 단언이 무는
      //     변이는 **접기에 호스트 가지를 다시 넣는 것**이고, 그 변이가
      //     적중 사이클의 값을 바꾸는 형태(호스트 우선)일 때만 여기서 잡힌다.
      //     호스트 가지를 *미적중* 쪽에만 넣는 형태 — 즉 실제로 있었던 결함 —
      //     은 이 전건 밖이라 아래 미적중 면이 잡는다.
      //   ※ 「우선순위 축」이라는 부제도 뗐다. `.sby` 앵커와 _PARTIAL 은
      //     이 파도부터 「판정·값·정지 세 축」으로 적으며, 순위는 leg 이
      //     둘일 때만 뜻을 갖는 낱말이다 (오늘 leg 은 하나다).
      if (x_hit) begin
        assert (lookFrame == x_frame);
        assert ({lookPerm_x, lookPerm_w, lookPerm_r} == {x_perm_x, x_perm_w, x_perm_r});
      end

      // ── Isolation.query_no_serve — *미적중 면* (2026-08-31 신설) ────────
      //
      // 위 두 줄의 전건은 `x_hit` 다. 그런데 구멍은 「로컬이 답할 때」가
      // 아니라 **「로컬이 미적중일 때」**에 있었다 — 전건이 정확히 구멍의
      // 여집합이라 도메인이 어긋나 있었다. 이 아래가 그 여집합을 잰다.
      //
      // 종전 판은 이 축을 「항진이라 못 잰다」로 포기했다 (hiumask.sby
      // §미측정 잔여 ⑤: `hit -> lookAny` 는 lookAny = hit || hostPresent
      // 에서 흡수 법칙으로 접힌다 — 공허 3형). 진단은 옳았고 결론이
      // 틀렸다: **함의를 등식으로 바꾸면 접히지 않는다.** 아래 값 축
      // 단언은 `x_hit ->` 함의가 아니라 미적중 면의 *값 지정*이다.
      //
      // 근거: §3.3.1 규범 2 「지원하는 호스트에서 기능이 *늘어도* 안 된다.
      // 서비스 없는 구성이 미적중하는 접근을 서비스 있는 구성이 적중시키면,
      // 그 순간 PE 가 보는 세계가 호스트에 따라 달라진다」 · HIU-11 의
      // 값 축 「같은 값을 관측한다」.
      //
      // 반증력 실측 — 아래 §반증력 실측표의 ②③ 항.
      if (!x_hit) begin
        assert (lookFrame == 32'h0);
        assert (!lookPerm_r && !lookPerm_w && !lookPerm_x);
      end

      // ── Decode.stall_uniform — *정지 원천* 축 (2026-08-31 신설) ─────────
      //
      // 위 $stable 두 줄은 「정지가 걸리면 전 단이 함께 선다」만 재고
      // **「무엇이 세우고 무엇이 푸는가」**는 재지 않는다. advance 가
      // hostRsp 의 함수여도 거울과 DUT 가 같은 advance 로 시프트하므로
      // 상태열 등식은 그대로 성립한다 — 거울 축의 구조적 사각지대다.
      //
      // E.3 2항 파생 요건이 정지 해제의 주체를 배타적으로 못박는다:
      // 「해제는 정지를 풀지 않는다 — 정지를 푸는 것은 2항의 *항목 기입*
      // 뿐이다」. hostRsp 는 install 이 아니므로 이 식의 항이 될 수 없다.
      // 그것이 항이면 서비스 없는 구성이 영구 정지하는 접근을 서비스 있는
      // 구성이 통과시켜 HIU-11 의 *상태열* 축이 깨진다.
      //
      // 정지 원천은 정확히 둘이다: 외부 io_hold, 그리고 조회 지점의 로컬
      // 미적중(E.4 3항이 명시 허용한 그 한 지점). 셋째 원천도, 셋째
      // 해제 주체도 없다.
      //
      // 반증력 실측 — 아래 §반증력 실측표의 ④ 항.
      assert (advance == (!io_hold && !(s3_valid && !x_hit)));
    end
  end

  // ── §반증력 실측표 — 「이 단언들이 오늘의 결함을 실제로 무는가」 ─────────
  //
  // 규율: 반증력은 **주장이 아니라 실행 결과**다. 수리한 단언을 **수리 전
  // RTL** 에 걸어 반례가 나는지를 재지 않으면, 그 단언이 여전히 헛것인지
  // 사람이 알 수 없다 (저장소가 반복해 밟은 형태 — 무변이 GREEN 은 수락
  // 기준이 아니다).
  //
  // 방법 (2026-08-31 실측). 격리 사본 /tmp/wt-mut 에
  //   · rtl/generated/HiuPipeline.sv ← **수리 전** 생성 SV (git HEAD 판:
  //     lookAny = hit || hostPresent · missWait = … && !hostPresent)
  //   · rtl/sv/assert/HiuMask_props.sv ← **이 파일(수리 후)**
  //   · MaskUnit.sv · hiumask.sby ← 저장소 사본 그대로
  // 를 두고 `sby -f … bmc` (mode bmc · depth 24 · smtbmc z3) 를 돌렸다.
  // bmc 는 첫 반례에서 멈추므로 **네 단언을 하나씩만 살리고** 나머지 셋은
  // `assert (1'b1);` 로 중화해 네 번 따로 돌렸다 — 그러지 않으면 「하나가
  // 물었다」가 「넷이 문다」로 오독된다.
  //
  //   ① 캡처 등식 판정 비트 `s4_anyHit == $past(x_hit)`
  //        → FAIL, step 3   (수리 전 우변 $past(lookAny) 로는 통과했다)
  //   ② 미적중 면 값   `!x_hit -> lookFrame == 32'h0`
  //        → FAIL, step 1
  //   ③ 미적중 면 권한 `!x_hit -> perm 삼비트 0`
  //        → FAIL, step 1
  //   ④ 정지 원천 등식 `advance == !io_hold && !(s3_valid && !x_hit)`
  //        → FAIL, step 4
  //
  // 넷 다 물었다. 그리고 ②④ 가 수리 후 설계에서 **통과**한다는 사실이
  // 곧 「W10 의 결론 두 항은 전건에서 따라온다」의 증명이다 — W10 주석의
  // ⚠⚠ 문단이 그 함의를 자기 자신에 대한 공허 고지로 쓰는 근거다.
  //
  // 종전 이 자리에는 실측이 단언마다 한 줄씩 흩어져 있었고 그중 하나는
  // 「전부 살린 채 한 번 돌린」 결과를 단언 하나의 반증력으로 적었다.
  // 한 곳에 모으고 방법을 함께 적는다 — 재현 없는 수치는 증거가 아니다.

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

  // 대체 미적중이 조회 단에 *섰다*는 사실을 붙드는 대기 비트.
  //
  // 2026-08-31 신설. 종전 판은 f_rep 의 입력에 `f_replace && !x_hit` 를
  // 직접 물렸는데, 그 식은 **정지가 풀리는 사이클에 이미 거짓**이다 —
  // E.3 이 정한 해제 주체가 항목 기입이므로 대체 미적중은 install 로
  // x_hit 가 서야 전진하고, 전진 에지에서는 `!x_hit` 가 거짓이다. 즉
  // 꼬리표가 영영 0 이라 W12 가 도달 불가가 된다.
  //   ※ 수리 전 RTL 에서 이 꼬리표가 실렸던 이유는 **결함 그 자체**였다:
  //     hostPresent 가 미적중 정지를 풀어 미적중 요청이 여섯 단을 완주했다.
  //     W12 도 W10 과 같이 위반에 매인 증인이었다 — W10 은 *전건*이
  //     위반이었고, 이쪽은 *도달 경로*가 위반이었다. 결함을 고치자
  //     증인이 함께 죽는 것이 그 매임의 증거다.
  //   ⇒ 올바른 궤적은 E.3 그대로다: 대체 미적중이 조회에 서서 정지 →
  //     호스트가 항목을 기입 → 채움 바이패스 적중 → 전진. 아래 대기
  //     비트가 「조회에 선 그 요청이 대체였다」를 정지 구간 너머로 나른다.
  reg f_rep_pend = 1'b0;
  always @(posedge clk) begin
    if (reset)                    f_rep_pend <= 1'b0;
    else if (f_replace && !x_hit) f_rep_pend <= 1'b1;  // 대체 미적중이 조회에 섰다
    else if (advance)             f_rep_pend <= 1'b0;  // 그 요청이 s4 로 떠났다
  end

  // 그 대체 요청을 단으로 실어 나르는 꼬리표 (거울과 같은 enable)
  reg [6:4] f_rep = 3'h0;
  always @(posedge clk) begin
    if (reset)        f_rep <= 3'h0;
    else if (advance) f_rep <= {f_rep[5:4], f_rep_pend};
  end

  // W9 ← Isolation.query_no_serve · Platform.xlate_local
  //      활성면: 두 leg 이 실제로 *충돌*
  //      한다 (같은 사이클에 로컬 적중 + 호스트 응답이 다른 frame).
  //      이것 없이는 우선순위 단언이 「호스트 leg 이 죽어 있는 세계」에서
  //      자명하다.
  always @(posedge clk)
    if (f_ok) w9_leg_clash: cover (x_hit && io_hostRsp_valid && (io_hostRsp_frame != x_frame));

  // W10 ← Isolation.query_no_serve(미적중 면) · Decode.stall_uniform(정지 원천)
  //
  //       **이 증인이 재는 것은 전건 도달성 하나다.** 위 두 신설 단언
  //       (미적중 면 값 지정 · 정지 원천 등식)의 전건이 살아 있는 궤적 —
  //       로컬 미적중이면서 호스트 leg 이 실제로 서 있고(x_hostPresent ·
  //       비0 frame) 자유 입력이 흔들리는 사이클 — 이 도달 가능하다.
  //
  //       ⚠ 2026-08-31 교체. 종전 판은
  //         cover (s3_valid && !x_hit && x_hostPresent
  //                && lookFrame == io_hostRsp_frame && io_hostRsp_frame != 0)
  //       였고 「최하 순위 가지가 살아 있어야 「최하 순위」가 명제다」로
  //       스스로를 정당화했다. 그러나 그 전건은 **정확히 §3.3.1 규범 2
  //       「지원하는 호스트에서 기능이 *늘어도* 안 된다」 위반 궤적**이다 —
  //       로컬이 미적중한 사이클에 호스트 프레임이 값 축에 실리는 것.
  //       증거층은 그것을 `reached` 로 세어 verdict PASS 에 실었다. 공허
  //       검출을 위해 지은 증인 층이 위반의 *도달성*을 증명해 게이트에
  //       초록으로 올린 셈이다.
  //
  //       ⚠⚠ **이 증인은 「호스트 leg 이 죽은 세계」에서 자명하다.** 결론
  //       두 항(`lookFrame == 0` · `!advance`)은 오늘 설계에서 전건으로부터
  //       *구조적으로* 따라온다 — 접기의 기본 구동이 0 이고 미적중 가지가
  //       없으므로 `!x_hit → lookFrame == 0` 이고, `missWait = s3_valid &&
  //       !x_hit` 이므로 `s3_valid && !x_hit → !advance` 다. 즉 남는 자유도는
  //       `x_hostPresent && io_hostRsp_frame != 0` 뿐이고 그 둘은 팬아웃이
  //       없는 자유 입력이다 (HiuPipeline.sv 에서 io_hostRsp_* 는 XlateStore
  //       를 통과해 미결선 넷 다섯으로 끝난다). **그러므로 이 cover 가
  //       도달했다는 사실은 호스트 leg 이 무언가를 한다는 증거가 아니다.**
  //         · 2026-08-31 첫 판의 주석은 이 자리에 「호스트 leg 이 죽은
  //           세계에서 자명해지지 않는다」라 적었다. 그것이 거짓이었다 —
  //           §3.4.2 「아무것도 하지 않는 선택적 경로는 HIU-11 을 자명하게
  //           만족한다」가 경계하는 그 형태를 **피하지 못한다.**
  //         · 피할 수 없는 것이 오늘의 상태다. 정본 §3.3.1 측정 트랙이
  //           이 leg 을 「의도된 미결선」이라 부르고 승격 조건을 적어 두었고,
  //           승격 전까지 §3.4.2 「요구할 것은 셋이다」 — 두 구성의 내부
  //           상태가 *실제로 어긋난다* · 그 상태가 *관측 경로 위에 있다* ·
  //           중립성이 *가드가 만든 참이다* — 는 셋 다 성립하지 않는다.
  //           그 사실은 `.sby` §미측정 잔여 ③ 와 lint_postformal 의
  //           `_PARTIAL` 이 기계가 읽는 칸에 적는다.
  //         ⇒ 이 증인의 정직한 이름은 「전건이 도달한다」이지 「leg 이
  //           불활성임을 증명한다」가 아니다. 불활성을 *증명*하는 것은 위
  //           두 단언(값 0 · 정지 유지)이고, 이 cover 는 그 단언들이
  //           공허하지 않다는 것만 든다.
  always @(posedge clk)
    if (f_ok) w10_host_leg_inert: cover (s3_valid && !x_hit && x_hostPresent
                     && (io_hostRsp_frame != 32'h0)
                     && (lookFrame == 32'h0) && !advance);

  // W11 ← Decode.evict_inline
  //       본체: 대체 궤적이 실제로 도달 가능하다
  //       (유효한 칸을 다른 태그로 조회 → 미적중으로만 나타난다)
  always @(posedge clk) if (f_ok) w11_replace_reached: cover (f_replace && !x_hit);

  // W12 ← Decode.evict_inline · Isolation.coh_no_shortcut
  //       그 대체 요청이 여섯 단을 완주해 응답이 난다. 거울 등식은 전
  //       궤적에 대해 서 있으므로, 대체 궤적이 도달 가능하다는 이 증인이
  //       「대체가 단계열을 바꾸지 않는다」의 실측이다.
  //       2026-08-31 이후 도달 경로는 E.3 규범 그대로다 — 대체 미적중이
  //       조회에 서서 정지하고, 호스트가 항목을 기입해야 풀린다. 즉 이
  //       증인은 「축출 단 부재」와 「정지 해제 주체가 항목 기입」을
  //       한 궤적으로 함께 든다 (위 f_rep_pend 주석).
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
  .lookFrame         (lookFrame),
  .lookPerm_r        (lookPerm_r),
  .lookPerm_w        (lookPerm_w),
  .lookPerm_x        (lookPerm_x)
);
