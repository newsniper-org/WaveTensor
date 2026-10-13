// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// XlateStore 후-formal 하네스 (§6.3) — CHECK 축: valid_check ·
// partition_check · flush_keeps_data (+ Isolation 의 채움·커밋 격리 가드 ·
// XlateSurface.commit_v_carried 저장 절반 — V 의 유효 비트 운반과 채움 가림 (파도 3 ·
// W3 개명 hi_v_carried → commit_v_carried) · W3 의 하류 정지 유계 s_pend_bounded).
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
  input wire        f_install_fire,      // installFire = install.fire (W3 DP-22 — 이름 있는 val, 줄 번호 생성 이름 함정 해소)
  input wire        io_install_valid,    // 파도 4 SLOTFREE — 증인 W13 전용
  input wire        io_install_ready,    // 파도 4 SLOTFREE — 아래 a_ready_split
  input wire        installSlotFree,     // 파도 4 SLOTFREE — 클래스 끝 포트 (io_ 접두 없음)
  input wire [1:0]  io_install_part,
  input wire [3:0]  io_install_idx,
  input wire [27:0] io_install_tag,
  input wire [31:0] io_install_frame,
  input wire        io_install_perm_r,
  input wire        io_install_perm_w,
  input wire        io_install_perm_x,
  input wire        io_install_v,        // XLATE_ENTRY_COMMIT [31] (파도 3 · W3 표면)
  input wire        io_flush_valid,
  input wire [1:0]  io_flush_part,
  input wire [15:0] f_vb0,               // validBits_0..3 — 파티션별 유효 비트
  input wire [15:0] f_vb1,
  input wire [15:0] f_vb2,
  input wire [15:0] f_vb3,
  input wire [3:0]  f_pend,              // {fillPend_3..0}
  input wire [67:0] f_slot0,             // {idx, tag, frame, perm_x, w, r, v}
  input wire [67:0] f_slot1,
  input wire [67:0] f_slot2,
  input wire [67:0] f_slot3,
  input wire        commitFire,
  input wire [1:0]  commitSel,
  input wire [3:0]  commitLine_idx,      // DUT 커밋 줄 mux 출력 — 오라클에 쓰지 않는다 (f_slot_c 주석)
  input wire        commitLine_v,
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
  wire [67:0] f_slot [0:3];
  assign f_vb[0] = f_vb0;  assign f_vb[1] = f_vb1;
  assign f_vb[2] = f_vb2;  assign f_vb[3] = f_vb3;
  assign f_slot[0] = f_slot0;  assign f_slot[1] = f_slot1;
  assign f_slot[2] = f_slot2;  assign f_slot[3] = f_slot3;

  wire [27:0] f_body_tag   = f_body[27:0];
  wire [67:0] f_slot_sel   = f_slot[io_lookup_part];
  wire [3:0]  f_slot_sel_idx = f_slot_sel[67:64];
  wire [27:0] f_slot_sel_tag = f_slot_sel[63:36];
  wire        f_slot_sel_v   = f_slot_sel[0];
  // 채움 가림 — 요청 파티션 슬롯이 대기 중이고 같은 색인이다 (DUT 어휘가 아니라
  // 슬롯 몸체·pend 탭에서 다시 짓는다)
  wire        f_shadow       = f_pend[io_lookup_part] && (f_slot_sel_idx == reqIdx);
  wire [15:0] f_vb_sel     = f_vb[io_lookup_part];
  // 커밋되는 줄 — DUT 의 커밋 줄 mux(commitLine_*) 가 아니라 슬롯 몸체 탭에서
  // commitSel 로 다시 고른다. 오라클이 mux 출력이면 그 mux 의 결함(다른 슬롯의
  // v·idx 를 고름)이 오라클과 DUT 에 함께 실려 등식이 선다 — 2026-09-26 반증
  // 검토 실측: `_zz_commitLine_v = fillSlot_1_v` (case 2'b00) 변이가 bmc · prove ·
  // cover 12/12 를 전부 통과했다 (XS1).
  wire [67:0] f_slot_c     = f_slot[commitSel];
  wire [3:0]  f_cl_idx     = f_slot_c[67:64];

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
      // XlateSurface.commit_v_carried (저장 절반) — 채움 적중은 줄의 v 를 요구하고
      // (V=0 줄은 적중하지 않는다), 대기 중인 줄은 같은 항목의 옛 저장 판을
      // 가린다 (COMMIT 수락 다음 에지부터 그 항목은 새 판으로만 보인다).
      if (fillHit)
        assert (f_slot_sel_v);
      if (io_lookup_valid && f_shadow)
        assert (!storeHit && (io_rsp_hit == (f_slot_sel_v && (f_slot_sel_tag == reqTag))));
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
      // Isolation.fill_slot_per_partition — 슬롯 여유 (파도 4 SLOTFREE). 조립의 MMIO ready ·
      // 문의 installReady 가 먹는 installSlotFree 는 *자기 파티션 슬롯의 점유만*의 함수다
      // (flush 와 무관 — 그래서 wdata → ready 조합 경로가 없다). 지상 진리는 pend 탭이다.
      a_slot_free: assert (installSlotFree == !f_pend[io_install_part]);
      // install.ready 는 그 슬롯 여유와 같은 사이클 · 같은 파티션 flush 의 부정의 논리곱 —
      // 둘의 차이는 flush 충돌 항 *하나*다. 조립이 ready 를 슬롯 여유로 바꿔도 이 블록의
      // 수락 규칙(flush 우선)은 그대로라는 핀이다. 배타가 깨진 사이클의 설치는 여기서
      // 버려진다 — 그 배타는 조립 하네스 a_xonehot 이 잰다 (assembly.sby 머리).
      a_ready_split: assert (io_install_ready ==
                             (installSlotFree && !(io_flush_valid && (io_flush_part == io_install_part))));
    end
  end

  // ── 파티션별 상태 전이 범위 (Isolation.capacity_partitioned ·
  //    Isolation.install_scoped · Isolation.fill_slot_per_partition ·
  //    XlateStore.flush_keeps_data 의 유효 비트 축) ─────────────────────────
  genvar p;
  generate for (p = 0; p < 4; p = p + 1) begin : g_part
    // 이 파티션의 슬롯 몸체 — 아래 커밋 가지는 commitSel == p 이므로 커밋된 줄이 곧 이것이다.
    wire [67:0] f_sl = f_slot[p];
    always @(posedge clk) begin
      if (f_ok) begin
        // validBits — flush(자기 파티션 전소거) · 커밋(자기 파티션 한 비트
        // 세움) 외의 변화 부재. q 파티션 사건이 p 구간을 못 건드린다.
        if ($past(io_flush_valid) && ($past(io_flush_part) == p[1:0]))
          assert (f_vb[p] == 16'h0);                       // flush 는 유효만 지운다
        else if ($past(commitFire) && ($past(commitSel) == p[1:0]))
          // XlateSurface.commit_v_carried — 커밋은 그 비트를 줄의 v 로 쓴다 (1 세움 · 0 내림).
          // v·idx 는 슬롯 p 의 몸체에서 읽는다 (DUT 커밋 줄 mux 가 아니다 — 위 f_slot_c 주석).
          assert (f_vb[p] == ($past(f_sl[0])
                                ? ($past(f_vb[p]) |  (16'h1 << $past(f_sl[67:64])))
                                : ($past(f_vb[p]) & ~(16'h1 << $past(f_sl[67:64])))));
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
                                      io_install_perm_w, io_install_perm_r,
                                      io_install_v}));
        else
          assert ($stable(f_slot[p]));

        // flush 다음 사이클, 그 파티션 조회는 어둡다 (비유효 항목이 rsp 에
        // 닿는 사이클 부재의 시제형 — valid_check × flush_keeps_data 접점)
        if ($past(io_flush_valid) && (io_lookup_part == $past(io_flush_part)))
          assert (!storeHit && !fillHit);
      end
    end
  end endgenerate

  // ── 하류 정지 유계 — DP-21 · XlateSurface.stall_independent (3.10 v1.0 묶음 W3) ──────
  // 정본 e-defined.typ:308 「정지는 *장치 의무로서 유계 시간 안에 풀린다*」 ·
  // e-defined.typ:308 「호스트 조치에 기대지 않고 다른 정지(미적중 정지 · 초기화 소거 구간)와 독립이다」. 문의 정지는 installSlotFree
  // (= !fillPend(part))가 0 인 동안이므로, 유계는 「대기 줄이 설치 없이 유계 사이클 안에 빠진다」다.
  // 전건 「설치가 오지 않는 동안」 — 실제 장치에서는 정지된 COMMIT 이 버스를 잡고 있어 새 설치가
  // 오지 않는다 (모델 XlateSurface 의 버스 단일성: held 동안 Present 꺼짐 — 닫힌 목록 3).
  // f_quiet = 설치 발화(installFire)가 없는 연속 사이클 수 (포화 7). 상수 PARTS = 4 = 형상 파티션
  // 수 (DP-21 「설치가 오지 않는 동안 ≤ xlateParts 사이클」). 이 블록에는 hold · 미적중 정지 ·
  // 초기화 소거 입력이 포트로 없다 — 조회 입력(io_lookup_*)은 자유이므로 「조회가 커밋을 막는」
  // 꼴의 결함(commitFire 에 조회 항)은 이 단언이 운다 (변이 표 S1).
  localparam F_PARTS = 4;
  reg [2:0] f_quiet = 3'd0;
  always @(posedge clk) begin
    if (reset || f_install_fire) f_quiet <= 3'd0;
    else if (f_quiet != 3'd7)    f_quiet <= f_quiet + 3'd1;
  end
  always @(*) begin
    if (f_ok)
      s_pend_bounded: assert (!((f_quiet >= F_PARTS) && (f_pend != 4'd0)));
  end

  // ── 저장 Mem 몸체 — 읽기 포트 관측 전칭 ─────────────────────────────────
  always @(posedge clk) begin
    if (f_ok && $stable(entryAddr)) begin
      // XlateStore.flush_keeps_data — 커밋 없는 에지(flush 포함)를 건넌
      // 같은 주소 재독은 같은 몸체다: flush 에서 비롯한 Mem 쓰기 포트 부재
      if (!$past(commitFire))
        assert ($stable(f_body));
      // Isolation.install_scoped — 커밋 기입 주소는 {commitSel, idx} 하나뿐:
      // 다른 주소의 몸체는 커밋 에지에도 불변 (파티션 경계 = 주소 상위라
      // q 커밋이 p 구간 주소를 만들 수 없다). idx 는 커밋되는 슬롯의 몸체에서
      // 읽는다 — DUT 의 commitLine_idx 를 쓰면 그 mux 가 다른 슬롯의 idx 를 골라도
      // 오라클이 그 틀린 주소를 함께 빼 주어 단언이 공허하게 선다 (XS2).
      if ($past(commitFire) && ($past({commitSel, f_cl_idx}) != entryAddr))
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
  // W1 ← Isolation.fill_tagged
  //      전제: 채움 바이패스 적중이 실제로 일어난다
  always @(posedge clk) if (f_ok) w1_fill_hit: cover (fillHit);

  // W2 ← XlateStore.valid_check · XlateStore.partition_check
  //      전제: 설치→커밋→저장 기입→조회
  //      적중의 전 경로가 살아 있다 (바이패스가 아닌 저장 블록 적중)
  always @(posedge clk) if (f_ok) w2_store_hit: cover (storeHit && !fillHit);

  // W3 ← XlateStore.flush_keeps_data · Isolation.install_scoped · XlateSurface.evict_on_commit_only
  //      저장 Mem 이 *변할 수 있다*: 관측 중인 바로 그 주소를 커밋이
  //      갈아엎는 에지. 이것 없이는 아래 두 불변 단언(W4 축·flush 축)이
  //      「메모리가 아무 때도 안 변한다」로 공허하게 성립한다.
  always @(posedge clk)
    if (f_ok && $stable(entryAddr) && $past(commitFire)
        && ($past({commitSel, f_cl_idx}) == entryAddr))
      w3_body_changes: cover (f_body != $past(f_body));

  // W4 ← Isolation.install_scoped · XlateSurface.evict_in_partition
  //      단언의 전제: 커밋 에지인데 기입 주소가 관측 주소와
  //      다른 사이클이 실재한다
  always @(posedge clk)
    if (f_ok && $stable(entryAddr) && $past(commitFire))
      w4_commit_elsewhere: cover ($past({commitSel, f_cl_idx}) != entryAddr);

  // W5 ← XlateStore.flush_keeps_data
  //      본 증인 (XlateStore.tla 의
  //      Witness_DataSurvivesFlush 의 RTL 판): 자기 파티션 flush 를 건넜는데
  //      그 파티션 주소의 저장 몸체가 *비어 있지 않은 채로* 살아 있다
  always @(posedge clk)
    if (f_ok && $stable(entryAddr) && $past(io_flush_valid)
        && ($past(io_flush_part) == entryAddr[5:4]) && !$past(commitFire))
      w5_body_survives_flush: cover ((f_body != 63'h0) && $stable(f_body));

  // W6 ← XlateStore.flush_keeps_data
  //      flush 가 실제로 *지운다*: 비지 않은 유효 비트열이 0 이 되는 에지
  //      (지우지 않는 기계라면 W6 이 안 잡히고, 지워 버리는 기계라면 W5 가
  //      안 잡힌다 — 둘을 함께 두는 것이 flush_keeps_data 의 양날이다)
  always @(posedge clk)
    if (f_ok && $past(io_flush_valid) && ($past(io_flush_part) == 2'd0))
      w6_flush_clears: cover (($past(f_vb0) != 16'h0) && (f_vb0 == 16'h0));

  // W7 ← Isolation.capacity_partitioned · XlateSurface.evict_in_partition · XlateSurface.evict_on_commit_only
  //      전제: 타 파티션(q=1) 커밋 에지를 건너는데
  //      p=0 의 유효 비트열이 비어 있지 않다. 그 「불변」 단언이 0 → 0 의
  //      자명한 성립이 아니라는 증거.
  always @(posedge clk)
    if (f_ok && $past(commitFire) && ($past(commitSel) == 2'd1))
      w7_other_part_stable: cover (($past(f_vb0) != 16'h0) && (f_vb0 == $past(f_vb0)));

  // W8 ← Isolation.fill_slot_per_partition
  //      전제: 설치가 슬롯 몸체를 실제로 바꾼다
  always @(posedge clk)
    if (f_ok && $past(f_install_fire) && ($past(io_install_part) == 2'd2))
      w8_slot_written: cover (f_slot2 != $past(f_slot2));

  // W9 ← XlateStore.partition_check
  //      본 증인 (HIU-1 의 RTL 판): 같은 (색인, 태그)가
  //      파티션 1 에서는 적중하는데, 바로 다음 사이클 파티션 0 의 같은
  //      질의는 미적중이다. 파티션 필드가 방벽으로 실제 작동한다는 증거 —
  //      이것 없이는 partition_check 단언이 「무엇도 적중 못 함」으로
  //      공허하게 성립한다.
  always @(posedge clk)
    if (f_ok && $past(io_rsp_hit) && ($past(io_lookup_part) == 2'd1)
        && ($past(reqIdx) == reqIdx) && ($past(reqTag) == reqTag)
        && io_lookup_valid && (io_lookup_part == 2'd0))
      w9_part_barrier: cover (!io_rsp_hit);

  // W10 ← XlateStore.valid_check
  //       시제 증인: 직전 사이클 같은 (파티션, 색인, 태그)
  //       질의가 적중했는데 flush 를 건넌 지금은 미적중이다. 「flush 다음
  //       사이클 어둡다」 단언이 *적중할 수 있었던* 질의 위에서 재어진다.
  always @(posedge clk)
    if (f_ok && $past(io_flush_valid) && (io_lookup_part == $past(io_flush_part))
        && $past(io_rsp_hit) && ($past(io_lookup_part) == io_lookup_part)
        && ($past(reqIdx) == reqIdx) && ($past(reqTag) == reqTag))
      w10_dark_after_flush: cover (!storeHit && !fillHit);

  // W11 ← XlateSurface.commit_v_carried
  //       V=0 커밋이 *살아 있는* 유효 비트를 실제로 내린다 (단일 항목 무효화).
  //       커밋이 언제나 유효를 세우는 기계라면 이 증인이 안 잡힌다. 가드는 슬롯 0
  //       의 몸체에서 v·idx 를 읽는다 — DUT 의 커밋 줄 mux 가 아니다.
  always @(posedge clk)
    if (f_ok && $past(commitFire) && ($past(commitSel) == 2'd0) && !$past(f_slot0[0]))
      w11_v0_kills: cover (($past(f_vb0 & (16'h1 << f_slot0[67:64])) != 16'h0)
                           && ((f_vb0 & (16'h1 << $past(f_slot0[67:64]))) == 16'h0));

  // W12 ← XlateSurface.commit_v_carried
  //       가림이 실제로 일한다: 저장 블록에는 같은 태그의 유효 항목이 있는데
  //       대기 중인 V=0 줄이 그 항목을 가려 조회가 미적중이다.
  always @(posedge clk)
    if (f_ok && io_lookup_valid && f_shadow && !f_slot_sel_v
        && f_vb_sel[reqIdx] && (f_body_tag == reqTag))
      w12_shadow_hides: cover (!io_rsp_hit);

  // W13 ← Isolation.fill_slot_per_partition · a_slot_free · a_ready_split
  //       슬롯 여유와 install.ready 가 실제로 *갈린다*: 슬롯은 비었는데 같은 파티션
  //       flush 가 그 사이클의 설치를 막는다 (a_ready_split 의 flush 항이 산다) —
  //       그리고 슬롯이 실제로 차서 여유가 내려간다 (a_slot_free 가 0 == 0 이 아니다).
  always @(posedge clk) if (f_ok) w13_split_flush: cover (installSlotFree && !io_install_ready);
  always @(posedge clk) if (f_ok) w13_slot_busy:   cover (!installSlotFree && io_install_valid);

  // W14 ← XlateSurface.stall_independent · s_pend_bounded
  //       대기 줄이 설치 없이 (flush 도 없이) 커밋으로 빠진다 — 조회가 같은 사이클에 서 있어도.
  //       s_pend_bounded 의 전건(대기 줄 + 무설치 구간)이 실재한다. 「넷 다 대기」는 이 블록에서
  //       도달 불가다 (설치 포트 하나 · 커밋 사이클당 하나 — 대기는 늘 많아야 하나: 실측 기록은
  //       xlatestore.sby 「W3」 절).
  always @(posedge clk)
    if (f_ok && $past(f_pend != 4'd0) && !$past(f_install_fire) && !$past(io_flush_valid) && $past(io_lookup_valid))
      w14_pend_drains: cover (f_pend == 4'd0 && f_quiet >= 3'd1);
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
  .f_install_fire  (installFire),
  .io_install_valid (io_install_valid),
  .io_install_ready (io_install_ready),
  .installSlotFree (installSlotFree),
  .io_install_part (io_install_part),
  .io_install_idx  (io_install_idx),
  .io_install_tag  (io_install_tag),
  .io_install_frame(io_install_frame),
  .io_install_perm_r (io_install_perm_r),
  .io_install_perm_w (io_install_perm_w),
  .io_install_perm_x (io_install_perm_x),
  .io_install_v    (io_install_v),
  .io_flush_valid  (io_flush_valid),
  .io_flush_part   (io_flush_part),
  .f_vb0           (validBits_0),
  .f_vb1           (validBits_1),
  .f_vb2           (validBits_2),
  .f_vb3           (validBits_3),
  .f_pend          ({fillPend_3, fillPend_2, fillPend_1, fillPend_0}),
  .f_slot0         ({fillSlot_0_idx, fillSlot_0_tag, fillSlot_0_frame,
                     fillSlot_0_perm_x, fillSlot_0_perm_w, fillSlot_0_perm_r,
                     fillSlot_0_v}),
  .f_slot1         ({fillSlot_1_idx, fillSlot_1_tag, fillSlot_1_frame,
                     fillSlot_1_perm_x, fillSlot_1_perm_w, fillSlot_1_perm_r,
                     fillSlot_1_v}),
  .f_slot2         ({fillSlot_2_idx, fillSlot_2_tag, fillSlot_2_frame,
                     fillSlot_2_perm_x, fillSlot_2_perm_w, fillSlot_2_perm_r,
                     fillSlot_2_v}),
  .f_slot3         ({fillSlot_3_idx, fillSlot_3_tag, fillSlot_3_frame,
                     fillSlot_3_perm_x, fillSlot_3_perm_w, fillSlot_3_perm_r,
                     fillSlot_3_v}),
  .commitFire      (commitFire),
  .commitSel       (commitSel),
  .commitLine_idx  (commitLine_idx),
  .commitLine_v    (commitLine_v),
  .storeHit        (storeHit),
  .fillHit         (fillHit),
  .reqIdx          (reqIdx),
  .reqTag          (reqTag),
  .entryAddr       (entryAddr),
  .f_body          ({storeBody_perm_x, storeBody_perm_w, storeBody_perm_r,
                     storeBody_frame, storeBody_tag})
);
