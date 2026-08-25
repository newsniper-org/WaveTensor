// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// XlateStore 후-formal 하네스 (§6.3) — CHECK 축: valid_check ·
// partition_check · flush_keeps_data (+ Isolation 의 채움·커밋 격리 가드).
//
// 저장 Mem 내용의 불변성은 bind 모듈이 Mem 을 직접 들 수 없으므로 설계
// 자신의 읽기 포트(storeBody_* = store[entryAddr])를 관측 창으로 쓴다:
// 조회 주소가 자유 입력이라, "같은 주소를 이틀 연속 읽으면 (그 주소에 커밋이
// 없는 한) 같은 몸체" 를 전 주소에 대해 솔버가 전칭으로 잰다 — flush 사이클
// 도 이 전칭의 부분집합이다 (flush 에서 비롯한 Mem 쓰기 포트 부재의 관측형).
//
// 대상 SV 는 rtl/generated/XlateStore.sv 커밋본 그대로.
//
// ## 부착 방식 — bind 텍스트 전개 (2026-08-25 수리)
//
// 이 파일은 bind 형태를 유지한다 (bind 를 지원하는 도구에서는 그대로 선다).
// 그러나 yosys 0.66 자유 프론트엔드는 SV `bind` 를 오류 없이 파싱하고
// *조용히 무시*한다. 2026-08-25 이전의 xlatestore.sby 는 `prep -top
// XlateStore` 로 DUT 자신을 top 으로 삼았고, 그 결과 이 모듈은 unused 로
// 제거되어 (yosys 로그: Removing unused module `$abstract\XlateStore_props')
// **전 태스크가 assert=0 인 설계 위에서 통과했다 — 공허 PASS 였다.**
// 그동안 이 파일의 본문은 한 번도 정련된 적이 없었고, 붙이자마자 yosys 가
// 문법 오류를 냈다 (clocked block 밖의 $past — 아래 f_ok 에서 수리).
//
// 부착은 xlatestore.sby 의 `[script]` 가 MemOrderGate/Reassembly 선례대로
// bind 문을 대상 모듈 본문 안 인스턴스로 텍스트 전개해서 한다 (전개 대상은
// 워크디렉터리 사본 — 이 파일은 불변).

`timescale 1ns/1ps

module XlateStore_props (
  input wire        clk,
  input wire        reset,
  input wire        io_lookup_valid,
  input wire [1:0]  io_lookup_part,
  input wire        io_rsp_hit,
  input wire        io_rsp_fromFill,
  input wire [31:0] io_rsp_frame,
  input wire        io_rsp_perm_r,
  input wire        io_rsp_perm_w,
  input wire        io_rsp_perm_x,
  input wire        f_install_fire,      // when_XlateStore_l200 = install.fire
  input wire [1:0]  io_install_part,
  input wire [3:0]  io_install_idx,
  input wire [27:0] io_install_tag,
  input wire [31:0] io_install_frame,
  input wire        io_install_perm_r,
  input wire        io_install_perm_w,
  input wire        io_install_perm_x,
  input wire        io_flush_valid,
  input wire [1:0]  io_flush_part,
  input wire [15:0] f_vb0,               // validBits_0..3 — 파티션별 유효 비트
  input wire [15:0] f_vb1,
  input wire [15:0] f_vb2,
  input wire [15:0] f_vb3,
  input wire [3:0]  f_pend,              // {fillPend_3..0}
  input wire [66:0] f_slot0,             // {idx, tag, frame, perm_x, w, r}
  input wire [66:0] f_slot1,
  input wire [66:0] f_slot2,
  input wire [66:0] f_slot3,
  input wire        commitFire,
  input wire [1:0]  commitSel,
  input wire [3:0]  commitLine_idx,
  input wire        storeHit,
  input wire        fillHit,
  input wire [3:0]  reqIdx,
  input wire [27:0] reqTag,
  input wire [5:0]  entryAddr,
  input wire [62:0] f_body               // {perm_x, w, r, frame, tag} = store[entryAddr]
);
  // ── ENV assume: 단발 reset 프로토콜 (근거: HiuMask_props.sv 동일 —
  // async-reset 레지스터의 형식 검사 초기화 규약. 그 외 assume 없음) ──
  reg f_init = 1'b1;
  always @(posedge clk) f_init <= 1'b0;
  always @(*) begin
    if (f_init) assume (reset);
    else        assume (!reset);
  end

  // f_ok — 「직전 에지도 이번 에지도 reset 밖」. $past(reset) 을 쓰지 않고
  // 명시 레지스터로 지연시킨다: yosys 0.66 은 clocked block 밖의 $past 를
  // 거절한다 (실측 ERROR "System function $past is only allowed in clocked
  // blocks"). 의미는 동일하며 MemOrderGate/Reassembly 하네스와 같은 관용구다.
  reg f_past_valid = 1'b0;
  reg f_past_reset = 1'b1;
  always @(posedge clk) begin
    f_past_valid <= 1'b1;
    f_past_reset <= reset;
  end
  wire f_ok = f_past_valid && !reset && !f_past_reset;

  // 파티션 색인용 배열 뷰
  wire [15:0] f_vb   [0:3];
  wire [66:0] f_slot [0:3];
  assign f_vb[0] = f_vb0;  assign f_vb[1] = f_vb1;
  assign f_vb[2] = f_vb2;  assign f_vb[3] = f_vb3;
  assign f_slot[0] = f_slot0;  assign f_slot[1] = f_slot1;
  assign f_slot[2] = f_slot2;  assign f_slot[3] = f_slot3;

  wire [27:0] f_body_tag   = f_body[27:0];
  wire [66:0] f_slot_sel   = f_slot[io_lookup_part];
  wire [3:0]  f_slot_sel_idx = f_slot_sel[66:63];
  wire [27:0] f_slot_sel_tag = f_slot_sel[62:35];
  wire [15:0] f_vb_sel     = f_vb[io_lookup_part];

  // ── 조합 축 ──────────────────────────────────────────────────────────────
  always @(*) begin
    if (f_past_valid && !reset) begin
      // XlateStore.valid_check — 적중 = 유효 ∧ 파티션 ∧ 태그 논리곱.
      // 저장 블록 적중은 요청 파티션의 유효 비트와 태그 일치를 모두 요구한다.
      if (storeHit)
        assert (io_lookup_valid && f_vb_sel[reqIdx] && (f_body_tag == reqTag));
      // Isolation.fill_tagged — 채움 바이패스 적중도 자기 파티션 슬롯의
      // pend ∧ idx ∧ tag 논리곱이다 (타 파티션 슬롯은 후보조차 아니다).
      if (fillHit)
        assert (io_lookup_valid && f_pend[io_lookup_part]
                && (f_slot_sel_idx == reqIdx) && (f_slot_sel_tag == reqTag));
      // XlateStore.valid_check — 비유효/미적중이 rsp 값에 닿는 사이클 부재
      assert (io_rsp_hit == (storeHit || fillHit));
      assert (io_rsp_fromFill == fillHit);
      if (!io_rsp_hit)
        assert (io_rsp_frame == 32'h0 && !io_rsp_perm_r
                && !io_rsp_perm_w && !io_rsp_perm_x);
      if (!io_lookup_valid)
        assert (!io_rsp_hit);
      // XlateStore.partition_check — 조회 주소 상위 = 요청 파티션 그 자체
      assert (entryAddr == {io_lookup_part, reqIdx});
    end
  end

  // ── 파티션별 상태 전이 범위 (Isolation.capacity_partitioned ·
  //    Isolation.install_scoped · Isolation.fill_slot_per_partition ·
  //    XlateStore.flush_keeps_data 의 유효 비트 축) ─────────────────────────
  genvar p;
  generate for (p = 0; p < 4; p = p + 1) begin : g_part
    always @(posedge clk) begin
      if (f_ok) begin
        // validBits — flush(자기 파티션 전소거) · 커밋(자기 파티션 한 비트
        // 세움) 외의 변화 부재. q 파티션 사건이 p 구간을 못 건드린다.
        if ($past(io_flush_valid) && ($past(io_flush_part) == p[1:0]))
          assert (f_vb[p] == 16'h0);                       // flush 는 유효만 지운다
        else if ($past(commitFire) && ($past(commitSel) == p[1:0]))
          assert (f_vb[p] == ($past(f_vb[p]) | (16'h1 << $past(commitLine_idx))));
        else
          assert ($stable(f_vb[p]));

        // fillPend — 설치(세움)/커밋·flush(내림) 외 변화 부재
        if ($past(io_flush_valid) && ($past(io_flush_part) == p[1:0]))
          assert (!f_pend[p]);                             // flush 는 자기 채움 버퍼 취하
        else if ($past(f_install_fire) && ($past(io_install_part) == p[1:0]))
          assert (f_pend[p]);
        else if ($past(commitFire) && ($past(commitSel) == p[1:0]))
          assert (!f_pend[p]);
        else
          assert ($stable(f_pend[p]));

        // fillSlot 몸체 — 자기 파티션 설치 사이클에만 기입 (flush 는 pend 만
        // 지우고 슬롯 몸체·태그는 불변 — flush_keeps_data 의 채움 버퍼 축)
        if ($past(f_install_fire) && ($past(io_install_part) == p[1:0]))
          assert (f_slot[p] == $past({io_install_idx, io_install_tag,
                                      io_install_frame, io_install_perm_x,
                                      io_install_perm_w, io_install_perm_r}));
        else
          assert ($stable(f_slot[p]));

        // flush 다음 사이클, 그 파티션 조회는 어둡다 (비유효 항목이 rsp 에
        // 닿는 사이클 부재의 시제형 — valid_check × flush_keeps_data 접점)
        if ($past(io_flush_valid) && (io_lookup_part == $past(io_flush_part)))
          assert (!storeHit && !fillHit);
      end
    end
  end endgenerate

  // ── 저장 Mem 몸체 — 읽기 포트 관측 전칭 ─────────────────────────────────
  always @(posedge clk) begin
    if (f_ok && $stable(entryAddr)) begin
      // XlateStore.flush_keeps_data — 커밋 없는 에지(flush 포함)를 건넌
      // 같은 주소 재독은 같은 몸체다: flush 에서 비롯한 Mem 쓰기 포트 부재
      if (!$past(commitFire))
        assert ($stable(f_body));
      // Isolation.install_scoped — 커밋 기입 주소는 {commitSel, idx} 하나뿐:
      // 다른 주소의 몸체는 커밋 에지에도 불변 (파티션 경계 = 주소 상위라
      // q 커밋이 p 구간 주소를 만들 수 없다)
      if ($past(commitFire) && ($past({commitSel, commitLine_idx}) != entryAddr))
        assert ($stable(f_body));
    end
  end

  // ── cover 증인 — 공허 아님의 증거 (2026-08-25 신설) ─────────────────────
  //
  // 위 단언은 대부분 「A 이면 B」 꼴이라, A 가 도달 불가능하면 전부 공허하게
  // 통과한다. 특히 f_body 불변 단언들은 「저장 Mem 이 아무 때도 안 변한다」
  // 는 세계에서 자명하게 선다. 아래 증인이 그 전제들이 *reset 으로부터*
  // 실제로 도달함을 보인다.
  //
  // 증인의 시작 상태 (정직 표기): 전부 **reset 기점**이다. 이 설계에는
  // MmioConfig 같은 긴 초기화 소거가 없어 (reset 이 validBits/fillPend 를
  // 즉시 0 으로 놓는다) 도달성이 그대로 살아 있다 — 그래서 아래 증인은
  // 「단언의 전제가 충족 *가능*하다」가 아니라 「reset 으로부터 실제로
  // 도달한다」를 주장한다. 실측 도달 스텝 3~5.
  //   ※ sby 의 cover 모드는 `chformal -assert -remove` 로 단언을 스스로
  //     떼어낸다 (하네스가 끄는 것이 아니다). 그래도 증인이 적법 궤적 위에
  //     있다는 것은 bmc 태스크가 따로 보증한다 — 깊이 20 까지 reset 기점의
  //     모든 궤적에서 단언이 서므로, 스텝 3~5 의 이 증인들도 그 안이다.
  //
  // 증인은 cover 태스크에서만 컴파일한다 (-DXLATE_COVER). bmc/prove 모델을
  // 종전과 한 비트도 다르지 않게 유지하기 위한 규율이다.
`ifdef XLATE_COVER
  // W1 — fill_tagged 의 전제: 채움 바이패스 적중이 실제로 일어난다
  always @(posedge clk) if (f_ok) cover (fillHit);

  // W2 — valid_check/partition_check 의 전제: 설치→커밋→저장 기입→조회
  //      적중의 전 경로가 살아 있다 (바이패스가 아닌 저장 블록 적중)
  always @(posedge clk) if (f_ok) cover (storeHit && !fillHit);

  // W3 — 저장 Mem 이 *변할 수 있다*: 관측 중인 바로 그 주소를 커밋이
  //      갈아엎는 에지. 이것 없이는 아래 두 불변 단언(W4 축·flush 축)이
  //      「메모리가 아무 때도 안 변한다」로 공허하게 성립한다.
  always @(posedge clk)
    if (f_ok && $stable(entryAddr) && $past(commitFire)
        && ($past({commitSel, commitLine_idx}) == entryAddr))
      cover (f_body != $past(f_body));

  // W4 — install_scoped 단언의 전제: 커밋 에지인데 기입 주소가 관측 주소와
  //      다른 사이클이 실재한다
  always @(posedge clk)
    if (f_ok && $stable(entryAddr) && $past(commitFire))
      cover ($past({commitSel, commitLine_idx}) != entryAddr);

  // W5 — flush_keeps_data 의 본 증인 (XlateStore.tla 의
  //      Witness_DataSurvivesFlush 의 RTL 판): 자기 파티션 flush 를 건넜는데
  //      그 파티션 주소의 저장 몸체가 *비어 있지 않은 채로* 살아 있다
  always @(posedge clk)
    if (f_ok && $stable(entryAddr) && $past(io_flush_valid)
        && ($past(io_flush_part) == entryAddr[5:4]) && !$past(commitFire))
      cover ((f_body != 63'h0) && $stable(f_body));

  // W6 — flush 가 실제로 *지운다*: 비지 않은 유효 비트열이 0 이 되는 에지
  //      (지우지 않는 기계라면 W6 이 안 잡히고, 지워 버리는 기계라면 W5 가
  //      안 잡힌다 — 둘을 함께 두는 것이 flush_keeps_data 의 양날이다)
  always @(posedge clk)
    if (f_ok && $past(io_flush_valid) && ($past(io_flush_part) == 2'd0))
      cover (($past(f_vb0) != 16'h0) && (f_vb0 == 16'h0));

  // W7 — capacity_partitioned 의 전제: 타 파티션(q=1) 커밋 에지를 건너는데
  //      p=0 의 유효 비트열이 비어 있지 않다. 그 「불변」 단언이 0 → 0 의
  //      자명한 성립이 아니라는 증거.
  always @(posedge clk)
    if (f_ok && $past(commitFire) && ($past(commitSel) == 2'd1))
      cover (($past(f_vb0) != 16'h0) && (f_vb0 == $past(f_vb0)));

  // W8 — fill_slot_per_partition 의 전제: 설치가 슬롯 몸체를 실제로 바꾼다
  always @(posedge clk)
    if (f_ok && $past(f_install_fire) && ($past(io_install_part) == 2'd2))
      cover (f_slot2 != $past(f_slot2));

  // W9 — partition_check 의 본 증인 (HIU-1 의 RTL 판): 같은 (색인, 태그)가
  //      파티션 1 에서는 적중하는데, 바로 다음 사이클 파티션 0 의 같은
  //      질의는 미적중이다. 파티션 필드가 방벽으로 실제 작동한다는 증거 —
  //      이것 없이는 partition_check 단언이 「무엇도 적중 못 함」으로
  //      공허하게 성립한다.
  always @(posedge clk)
    if (f_ok && $past(io_rsp_hit) && ($past(io_lookup_part) == 2'd1)
        && ($past(reqIdx) == reqIdx) && ($past(reqTag) == reqTag)
        && io_lookup_valid && (io_lookup_part == 2'd0))
      cover (!io_rsp_hit);

  // W10 — valid_check 의 시제 증인: 직전 사이클 같은 (파티션, 색인, 태그)
  //       질의가 적중했는데 flush 를 건넌 지금은 미적중이다. 「flush 다음
  //       사이클 어둡다」 단언이 *적중할 수 있었던* 질의 위에서 재어진다.
  always @(posedge clk)
    if (f_ok && $past(io_flush_valid) && (io_lookup_part == $past(io_flush_part))
        && $past(io_rsp_hit) && ($past(io_lookup_part) == io_lookup_part)
        && ($past(reqIdx) == reqIdx) && ($past(reqTag) == reqTag))
      cover (!storeHit && !fillHit);
`endif // XLATE_COVER
endmodule

bind XlateStore XlateStore_props u_xlate_props (
  .clk             (clk),
  .reset           (reset),
  .io_lookup_valid (io_lookup_valid),
  .io_lookup_part  (io_lookup_part),
  .io_rsp_hit      (io_rsp_hit),
  .io_rsp_fromFill (io_rsp_fromFill),
  .io_rsp_frame    (io_rsp_frame),
  .io_rsp_perm_r   (io_rsp_perm_r),
  .io_rsp_perm_w   (io_rsp_perm_w),
  .io_rsp_perm_x   (io_rsp_perm_x),
  .f_install_fire  (when_XlateStore_l200),
  .io_install_part (io_install_part),
  .io_install_idx  (io_install_idx),
  .io_install_tag  (io_install_tag),
  .io_install_frame(io_install_frame),
  .io_install_perm_r (io_install_perm_r),
  .io_install_perm_w (io_install_perm_w),
  .io_install_perm_x (io_install_perm_x),
  .io_flush_valid  (io_flush_valid),
  .io_flush_part   (io_flush_part),
  .f_vb0           (validBits_0),
  .f_vb1           (validBits_1),
  .f_vb2           (validBits_2),
  .f_vb3           (validBits_3),
  .f_pend          ({fillPend_3, fillPend_2, fillPend_1, fillPend_0}),
  .f_slot0         ({fillSlot_0_idx, fillSlot_0_tag, fillSlot_0_frame,
                     fillSlot_0_perm_x, fillSlot_0_perm_w, fillSlot_0_perm_r}),
  .f_slot1         ({fillSlot_1_idx, fillSlot_1_tag, fillSlot_1_frame,
                     fillSlot_1_perm_x, fillSlot_1_perm_w, fillSlot_1_perm_r}),
  .f_slot2         ({fillSlot_2_idx, fillSlot_2_tag, fillSlot_2_frame,
                     fillSlot_2_perm_x, fillSlot_2_perm_w, fillSlot_2_perm_r}),
  .f_slot3         ({fillSlot_3_idx, fillSlot_3_tag, fillSlot_3_frame,
                     fillSlot_3_perm_x, fillSlot_3_perm_w, fillSlot_3_perm_r}),
  .commitFire      (commitFire),
  .commitSel       (commitSel),
  .commitLine_idx  (commitLine_idx),
  .storeHit        (storeHit),
  .fillHit         (fillHit),
  .reqIdx          (reqIdx),
  .reqTag          (reqTag),
  .entryAddr       (entryAddr),
  .f_body          ({storeBody_perm_x, storeBody_perm_w, storeBody_perm_r,
                     storeBody_frame, storeBody_tag})
);
