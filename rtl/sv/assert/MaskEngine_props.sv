// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// MaskEngine 후-formal 하네스 — MaskUnit 재키잉 엔진 창의 **시간 축**.
// FINAL 엣지 동시 기입 모서리 (파도 D, 2026-09-22). 선-formal
// rtl/formal/tla/MaskEngine.tla 의 가드 넷을 생성물 rtl/generated/MaskUnit.sv
// 위에서 다시 잰다. Mask.tla / HiuMask 합성(hiumask.sby)이 「어느 파티션」을,
// 이 하네스가 「언제」를 든다 — E.9 4항의 두 면.
//
// 정본 (좌표 뒤 「」 는 그 줄의 축자 — lint_section_refs 축 1 이 대조한다):
//   e-defined.typ:518 「재키잉 중 입력 기입」 — FAULT_STATUS [13]. 시점 예외가
//     없다: 재키잉 *중*이면 어느 사이클의 기입이든 이 비트다.
//   e-defined.typ:347 「`[8]` 엔진 busy · `[9]` 재키잉 수락 가능」 — MASK_STATUS.
//     「재키잉 중」의 정의는 장치 자신의 관측 busy=1 이고, 이 하네스의 busy 창은
//     그 포트(io_busy) 그대로다.
//   e-defined.typ:1549 「재계산 중(`0xEC0` `[8]`)」 — 정본 자신이 「재키잉 중」의
//     정의역을 [8] 로 준다.
//   e-defined.typ:1525 「옛 키로 만든 주소와 새 키로 만든 주소가 섞이면 안 된다」
//     — 오염 완료는 유효화하지 않는다.
//   e-defined.typ:1526 「다른 파티션이 그 변경의 사정권 밖」 — 타 파티션 기입은
//     오염이 아니다 (dirty_scoped).
//   05-security.typ:384 「소실도 loud 여야 한다」 — 유효화하지 않은 완료는
//     반드시 sticky 를 세운다. 오염이 아니어도 관측이 없으면 결손이다.
//   MaskUnit.scala:148 「계산 중 입력이 바뀐 재키잉은 결과를 유효화하지 않는다」
//     — 그 파일 자신의 계약. 파도 D 가 「FINAL 사이클 포함」을 더했다.
//   MaskUnit.scala:473 「val dirtyNow = compDirty || wrActNow」 — 파도 D 의 RTL:
//     FINAL 가지가 레지스터에 더해 **같은 사이클 항**을 직접 본다.
//   MaskUnit.scala:481 「maskValid(actPart) := !dirtyNow」 — 유효화의 식.
//   MaskUnit.scala:238 「워드 0..5. 6·7 기입은 무시한다」 — 논스 예약 오프셋
//     정책. 이 하네스는 그 경계를 리터럴(idx < 6)로 다시 적는다.
//   Common.scala:256 「해제와 발화가 같은 사이클이면 발화가 이긴다」 — StickyFault
//     규약. a_dirty_final_loud 의 전건은 해제를 배제하지 않으므로 그 겹침도
//     이 유닛에서 잰다 (도달은 증인 W6).
//
// ## 이 하네스가 잡는 정확한 결함
//
// 파도 D 이전 판(1666c7a)의 RTL: 활성 파티션으로 향한 키·논스 기입이 정확히
// FINAL 사이클(io_busy=1 · io_rekey_ready=0 — 장치 자신이 「재키잉 중」이라
// 말한다)에 실리면, 기입 표면의 compDirty := True 는 레지스터라 다음 사이클에야
// 1 이 되고 FINAL 가지는 레지스터의 엣지 전 값 0 만 실어 sticky 가 서지
// 않았다. 유효는 기입 표면의 텍스트 순서로 떨어진다. 실측: 수락+42 엣지 기입
// → maskReady[p]=0 · faultWrDuringRekey=0, 수락+40·+41 → fault=1. 안전 결손이
// 아니라 **관측 결손**이다 — 같은 호스트 행위가 1사이클 타이밍에 두 판정을
// 받고, 호스트는 「아직 안 끝남」과 「내 기입이 결과를 버렸다」를 가를 수 없다.
// a_final_overlap_loud 가 그 판에 bmc 반례를 낸다 (engine.sby §역-변이 mutA).
//
// ## 부착 방식
//
// 래퍼 모듈 MaskUnit_formal 이 DUT 를 인스턴스하고 **포트에만** 검사자를
// 붙인다. bind 는 yosys 0.66 이 조용히 무시한다 (SharedUnit_props.sv 파일
// 머리의 실측). 필요한 신호가 전부 포트라 expose 도 없다 — 내부 이름(phase ·
// compDirty · actPart · 줄번호 매인 when 이름)을 하나도 참조하지 않으므로 Scala
// 줄 밀림에 이 하네스가 무력화될 자리가 없다.
//
// ## 지상 진리는 포트에서 다시 적는다 (DUT 어휘를 재인용하지 않는다)
//
//   f_fire   = io_rekey_valid && io_rekey_ready — 수락 엣지.
//   f_act    — 수락 엣지에서 io_rekey_part 를 래치 (RTL actPart 의 독립 사본).
//   f_dirty  — busy 창 안에서 활성 파티션으로 향한 기입이 **직전 사이클까지**
//              있었는가. 두 갈래: (i) 수락 사이클 자체의 io_rekey_part 기입
//              (RTL 기입 표면의 rekeyFire ∧ part = rekey.part 가지 — 유도 초기
//              상태가 그 사이클의 옛 값을 래치한다) · (ii) io_busy 중 f_act 기입.
//              수락에서 (i) 로 다시 시작한다. 이 레지스터가 RTL compDirty 와
//              같은 시점 의미다 — 이번 사이클의 기입은 아직 아니다.
//   wrAct    — **이 사이클**의 활성 파티션 기입 (io_busy 중). FINAL 사이클의
//              wrAct 가 모서리다: 레지스터 f_dirty 는 그것을 보지 못한다.
//   완료 엣지 = $past(io_busy) && !io_busy — 직전 사이클이 FINAL 이었다.
//   기입 = 키 워드 기입(어느 idx 든) 또는 논스 워드 기입 idx < 6 (리터럴 —
//          예약 오프셋 6·7 은 기입이 아니다; 그 경계를 넓힌 변이는
//          a_clean_final_validates 에서 반례가 난다. 도달은 증인 W10).
//   f_act 는 완료 엣지 사이클에 $past(f_act) 와 같다 — busy 중에는 수락이 없어
//   f_act 가 바뀌지 않고, 완료 사이클의 새 수락은 다음 엣지에야 래치된다.
//   그래서 완료 사이클의 관측은 io_maskReady[f_act] 로 적는다.
//
// 가드 ↔ 단언 대응:
//   MaskEngine.dirty_loud
//     : a_final_overlap_loud (완료 직전 사이클 = FINAL 에 활성 파티션 기입이
//       있었으면 sticky 가 섰다 — **모서리 자체**) · a_dirty_final_loud
//       (직전 사이클까지의 오염이 있었으면 sticky 가 섰다 — 레지스터 경로) ·
//       a_fault_rise_at_final_only (sticky 상승 원천은 완료 엣지뿐)
//   MaskEngine.invalidate_beats_validate
//     : a_final_overlap_no_validate (FINAL 사이클의 활성 파티션 기입은 유효화를
//       이긴다 — 완료 뒤 그 비트는 0)
//   MaskEngine.dirty_no_validate
//     : a_dirty_final_no_validate (오염 완료는 유효화하지 않는다)
//   MaskEngine.dirty_scoped
//     : a_clean_final_validates (오염도 겹침도 없는 완료는 유효화한다 — 타
//       파티션 기입만 있었던 창도 「깨끗」이다: f_dirty 는 f_act 한정) ·
//       a_clean_final_quiet (그 완료는 sticky 를 세우지 않는다) ·
//       a_dirty_scoped (위 둘의 특수형 — 전건을 「busy 중 타 파티션 기입이
//       실재했던 창」으로 못박아 가드의 정의역 자체를 이름으로 든다. 위 둘에서
//       따라오지만, 이 가드가 그 전건에서 시험됐다는 것을 라벨로 남긴다;
//       전건 도달은 증인 W3). 파티션 무관 오염 변이(mutB)는 셋 다 깨뜨린다.
//   (앵커 없음 — 모델의 고정 불변식·규약 승계)
//     : a_fault_sticky (해제 없이 안 내려감) · a_accept_invalidates (수락은 옛
//       마스크를 즉시 무효화 — MaskEngine.tla Inv_BusyTargetInvalid 의 수락
//       엣지 면) · a_busy_target_invalid (busy 중 활성 파티션은 유효로 보이지
//       않는다 — 같은 불변식의 상태 면)
//
// assume 목록 (전수):
//   as_reset_shape — reset 은 시각 0 에만 활성. 근거: 정본 1장의 ENV 계약
//   (모델 Init 대응이 reset 직후 상태) — CapStatusWord_props.sv 와 동일.
//   기능 입력(io_keyWr_* · io_nonceWr_* · io_rekey_valid/part · io_en ·
//   io_req_* · io_faultClear*)은 전부 자유다 — busy 중 기입도, 수락과 같은
//   사이클의 기입도, 완료와 같은 사이클의 해제도 제약하지 않는다 (그것을
//   가정하면 이 하네스가 재러 온 모서리가 반례 공간에서 사라진다).
//
// 이 태스크가 재지 **않는** 것 (각각 어디가 재는가):
//   · busy 창의 정확한 길이(수락 뒤 42 엣지) · 라운드 수 · 마스크 값 — 여기서
//     busy 는 포트 io_busy 의 관측 그대로다. 증인이 깊이 안에서 도달한다는
//     것은 「창이 유한하고 깊이 안에 닫힌다」까지만 말한다. 정확한 오프셋
//     40·41·42·43·44 의 판정은 rtl/sim/test_mask_golden.py 의 지향 시험
//     wr_same_partition_at_final_edge_is_loud 이, 마스크 값은 golden 대조가 잰다.
//   · 저장의 파티션 범위(key_scoped_storage · key_write_own_only) · REKEY 유휴
//     수락(rekey_idle_only) — HiuMask/hiumask.sby. MASK_PART 창 라우팅
//     (rekey_explicit_target) — Wt64Top/assembly.sby (CHECK — 파도 2 승격).
//   · 논스 재사용 검사(faultNonceDup) · 미준비 통과(faultNoMask) · 요청 경로의
//     고정 1사이클 — hiumask.sby 와 cocotb.
//   · 수락과 같은 사이클의 기입이 유도 초기 상태에 **값**으로 어떻게 실리는가 —
//     hiumask.sby 의 key_scoped_storage (섀도우 대조). 여기서는 그 기입이
//     오염(f_dirty 갈래 (i))으로 계수된다는 것까지다 (도달은 증인 W8).
//
// 이 파일의 cover 는 태스크 구분 없이 컴파일된다 — bmc·prove 모델에서는 sby 가
// chformal 로 제거한다 (CapStatusWord_props.sv 와 같은 배치).

`default_nettype none

module MaskEngine_props (
    input wire        clk,
    input wire        reset,
    input wire        io_keyWr_valid,
    input wire [1:0]  io_keyWr_part,
    input wire        io_nonceWr_valid,
    input wire [1:0]  io_nonceWr_part,
    input wire [2:0]  io_nonceWr_idx,
    input wire        io_rekey_valid,
    input wire        io_rekey_ready,
    input wire [1:0]  io_rekey_part,
    input wire [3:0]  io_maskReady,
    input wire        io_busy,
    input wire        io_faultWrDuringRekey,
    input wire        io_faultClearWrRekey
);

  reg f_past_valid = 1'b0;
  reg f_past_reset = 1'b1;
  always @(posedge clk) begin
    f_past_valid <= 1'b1;
    f_past_reset <= reset;
  end
  wire f_ok = f_past_valid && !reset && !f_past_reset;

  // as_reset_shape (근거는 파일 머리 참조)
  always @(*) as_reset_shape: assume (reset == !f_past_valid);

  // ═══ 지상 진리 — 포트에서 다시 적는다 ═══════════════════════════════
  wire f_fire     = io_rekey_valid && io_rekey_ready;
  // 논스 기입 적중 — 워드 0..5 만. 6 은 이 파일의 리터럴이다.
  wire f_nonceHit = io_nonceWr_valid && (io_nonceWr_idx < 3'd6);

  reg [1:0] f_act;        // 수락 엣지에 래치한 파티션
  reg       f_dirty;      // 직전 사이클까지의 활성 파티션 기입 (두 갈래 — 머리)
  reg       f_otherSeen;  // 이번 busy 창에 활성 아닌 파티션 기입이 있었는가
  reg       f_acceptWr;   // 이번 창의 오염이 수락 사이클 자체의 기입에서 시작했는가

  wire f_wrAct   = (io_keyWr_valid && (io_keyWr_part == f_act)) ||
                   (f_nonceHit     && (io_nonceWr_part == f_act));
  wire f_wrNew   = (io_keyWr_valid && (io_keyWr_part == io_rekey_part)) ||
                   (f_nonceHit     && (io_nonceWr_part == io_rekey_part));
  wire f_wrOther = (io_keyWr_valid && (io_keyWr_part != f_act)) ||
                   (f_nonceHit     && (io_nonceWr_part != f_act));
  // 이 사이클의 활성 파티션 기입 — busy 중 (FINAL 사이클 포함).
  wire wrAct = io_busy && f_wrAct;

  always @(posedge clk) begin
    if (reset) begin
      f_act       <= 2'd0;
      f_dirty     <= 1'b0;
      f_otherSeen <= 1'b0;
      f_acceptWr  <= 1'b0;
    end else if (f_fire) begin
      // 갈래 (i) — 수락 사이클 자체의 같은-파티션 기입은 오염이다.
      f_act       <= io_rekey_part;
      f_dirty     <= f_wrNew;
      f_acceptWr  <= f_wrNew;
      f_otherSeen <= 1'b0;
    end else if (io_busy) begin
      // 갈래 (ii) — busy 중 활성 파티션 기입. 타 파티션 기입은 오염이 아니다.
      if (f_wrAct)   f_dirty     <= 1'b1;
      if (f_wrOther) f_otherSeen <= 1'b1;
    end
  end

  // ═══ 단언 ═════════════════════════════════════════════════════════════
  always @(posedge clk) if (f_ok) begin
    // ── 완료 엣지 — 직전 사이클이 FINAL 이었다 ──
    if ($past(io_busy) && !io_busy) begin
      // dirty_loud — **모서리**: FINAL 사이클 자체의 활성 파티션 기입도
      // sticky 를 세운다. 파도 D 이전 판(레지스터만 실음)은 여기서 반례.
      if ($past(wrAct))
        a_final_overlap_loud: assert (io_faultWrDuringRekey);
      // invalidate_beats_validate — 그 기입은 유효화를 이긴다.
      if ($past(wrAct))
        a_final_overlap_no_validate: assert (!io_maskReady[f_act]);
      // dirty_loud — 레지스터 경로: 직전 사이클까지의 오염도 loud.
      if ($past(f_dirty))
        a_dirty_final_loud: assert (io_faultWrDuringRekey);
      // dirty_no_validate — 오염 완료는 유효화하지 않는다.
      if ($past(f_dirty))
        a_dirty_final_no_validate: assert (!io_maskReady[f_act]);
      // 깨끗한 완료는 유효화한다 — 「아무것도 유효화하지 않는」 기계와 파티션
      // 무관 오염(dirty_scoped 삭제)을 함께 막는 양성면.
      if (!$past(f_dirty) && !$past(wrAct))
        a_clean_final_validates: assert (io_maskReady[f_act]);
      // 깨끗한 완료는 sticky 를 세우지 않는다 — 등식: 그 엣지의 sticky 는
      // 해제 규약(선 채 ∧ ¬해제)만으로 결정된다.
      if (!$past(f_dirty) && !$past(wrAct))
        a_clean_final_quiet: assert (io_faultWrDuringRekey ==
                                     ($past(io_faultWrDuringRekey) && !$past(io_faultClearWrRekey)));
      // dirty_scoped 직접형 — busy 중 타 파티션 기입이 실재했던 창의 완료는
      // 유효화하고 sticky 를 세우지 않는다 (E.9 4항 「사정권 밖」).
      if ($past(f_otherSeen) && !$past(f_dirty) && !$past(wrAct))
        a_dirty_scoped: assert (io_maskReady[f_act] &&
                                !(io_faultWrDuringRekey && !$past(io_faultWrDuringRekey)));
    end
    // ── sticky 규약 ──
    // 해제 없이 내려가지 않는다.
    if ($past(io_faultWrDuringRekey) && !$past(io_faultClearWrRekey))
      a_fault_sticky: assert (io_faultWrDuringRekey);
    // 상승 원천은 완료 엣지뿐 — busy 중 기입 자체가 sticky 를 세우지 않는다.
    if (io_faultWrDuringRekey && !$past(io_faultWrDuringRekey))
      a_fault_rise_at_final_only: assert ($past(io_busy) && !io_busy);
    // ── 수락·busy 중 유효 (모델 Inv_BusyTargetInvalid — 앵커 없음) ──
    // 수락은 옛 마스크를 즉시 무효화한다. f_act 는 이 엣지에 막 래치됐다.
    if ($past(f_fire))
      a_accept_invalidates: assert (!io_maskReady[f_act]);
    // busy 중 활성 파티션은 유효로 보이지 않는다 — 「재계산 중」인 파티션이
    // 유효로 보이는 창은 없다.
    if (io_busy)
      a_busy_target_invalid: assert (!io_maskReady[f_act]);
  end

  // ── 도달성 증인 (cover 태스크 전용 — 단언의 공허 방지) ──────────────
  //
  // 각 줄의 `←` 오른쪽이 **그 증인이 살리는 대상**이다: `<Model>.<guard>` 는
  // 이 태스크의 `# PROVES:` 앵커, 소문자 식별자는 이 하네스의 단언 라벨.
  // 줄번호로 매지 않는다. scripts/lint_witness_map.py 가 이 선언의 **참조
  // 실재성**을 재고, 뜻은 재지 못한다. 완료 엣지에 닿으려면 수락 뒤 43 엣지가
  // 필요하다 — cover 깊이 근거는 engine.sby 머리.

  // W1 ← MaskEngine.dirty_loud · MaskEngine.invalidate_beats_validate
  //      완료 직전 사이클(FINAL)에 활성 파티션 기입이 실렸다 — 겹침이 실재한다.
  //      없으면 a_final_overlap_loud · a_final_overlap_no_validate 의 전건이
  //      한 번도 서지 않은 채 통과한다 (선-formal Witness_NoOverlap 과 같은 자리).
  // W2 ← MaskEngine.dirty_no_validate
  //      직전 사이클까지의 오염이 있는 완료 — FINAL 사이클 자체에는 기입이
  //      없다 (W1 과 갈라 둔다: 같은 사이클 항이 아니라 누적 항이 결과를 버린
  //      궤적). a_dirty_final_* 의 전건 도달.
  // W3 ← MaskEngine.dirty_scoped
  //      busy 중 활성 아닌 파티션 기입만 있었던 창의 완료가 유효화한다 —
  //      a_dirty_scoped 의 전건 도달 (선-formal Witness_NoOtherWriteBusy).
  // W4 ← a_clean_final_validates
  //      깨끗한 완료가 활성 파티션 비트를 실제로 0→1 로 올린다 — 「아무것도
  //      유효화하지 않는」 기계에서 무효화 류 단언 전부가 공허해지는 것을 막는다
  //      (선-formal Witness_NoCleanComplete).
  // W5 ← a_fault_sticky
  //      선 sticky 가 해제로 실제로 내려간다 — a_fault_sticky 만으로는 「영영
  //      안 내려가는」 구현이 통과한다.
  // W6 ← a_dirty_final_loud
  //      오염 완료와 해제가 같은 사이클 — 발화가 이긴다 (StickyFault 규약 승계,
  //      CapWord.set_beats_clear 와 같은 결). a_dirty_final_loud 의 전건이
  //      해제를 배제하지 않았음이 이 궤적에서 실제로 시험된다.
  // W7 ← a_accept_invalidates
  //      유효했던 파티션의 재키잉 수락이 그 비트를 1→0 으로 실제로 떨어뜨린다
  //      — 두 번째 재키잉이 깊이 안에 있다는 것도 함께 든다.
  // W8 ← a_dirty_final_loud · MaskEngine.dirty_no_validate
  //      수락 사이클 자체의 같은-파티션 기입(f_dirty 갈래 (i))이 오염을 세워
  //      완료가 loud 이고 무효다 — 그 갈래를 뺀 하네스는 a_clean_final_validates
  //      에서 반례가 나므로, 이 증인은 갈래가 실물로 도달함을 든다.
  // W9 ← MaskEngine.dirty_loud
  //      FINAL 사이클의 겹침이 **논스** 워드 기입(idx < 6)이다 — 키 기입 없이.
  //      키·논스 두 when 이 동형이라는 것이 한쪽만으로 시험되지 않게 한다.
  // W10 ← a_clean_final_validates
  //      FINAL 사이클에 활성 파티션의 논스 **예약 오프셋**(idx 6·7) 기입이
  //      있었는데 완료가 깨끗하게 유효화한다 — 하네스 리터럴 idx < 6 의 경계가
  //      DUT 의 무시 정책과 같은 자리에 있음을 도달로 든다.
  always @(posedge clk) if (f_ok) begin
    w1_final_overlap_write: cover ($past(io_busy) && !io_busy && $past(wrAct));
    w2_dirty_final: cover ($past(io_busy) && !io_busy && $past(f_dirty) && !$past(wrAct));
    w3_other_write_busy_then_clean_final: cover ($past(io_busy) && !io_busy && $past(f_otherSeen)
                                                 && !$past(f_dirty) && !$past(wrAct) && io_maskReady[f_act]);
    w4_clean_final: cover ($past(io_busy) && !io_busy && !$past(f_dirty) && !$past(wrAct)
                           && io_maskReady[f_act] && !$past(io_maskReady[f_act]));
    w5_fault_clear: cover ($past(io_faultWrDuringRekey) && $past(io_faultClearWrRekey) && !io_faultWrDuringRekey);
    w6_dirty_final_with_clear: cover ($past(io_busy) && !io_busy && $past(f_dirty)
                                      && $past(io_faultClearWrRekey) && io_faultWrDuringRekey);
    w7_accept_drops_ready: cover ($past(f_fire) && $past(io_maskReady[io_rekey_part]) && !io_maskReady[f_act]);
    w8_accept_write_dirty_final: cover ($past(io_busy) && !io_busy && $past(f_acceptWr) && !$past(wrAct)
                                        && !io_maskReady[f_act] && io_faultWrDuringRekey);
    w9_final_overlap_nonce_only: cover ($past(io_busy) && !io_busy && $past(wrAct)
                                        && !$past(io_keyWr_valid) && $past(f_nonceHit));
    w10_final_reserved_nonce_is_clean: cover ($past(io_busy) && !io_busy
                                              && $past(io_nonceWr_valid && (io_nonceWr_idx >= 3'd6)
                                                       && (io_nonceWr_part == f_act))
                                              && !$past(f_dirty) && !$past(wrAct) && io_maskReady[f_act]);
  end

endmodule

// 형식 검증 톱 — 대상 + props 결선. 내부 포트 없음 (expose 불필요). 요청
// 경로·fault 해제 두 갈래·논스 기입 데이터는 자유 입력으로 두되 검사자에는
// 잇지 않는다 (이 하네스의 정의역 밖 — 파일 머리 「재지 않는 것」).
module MaskUnit_formal (
    input wire        clk,
    input wire        reset,
    input wire        io_keyWr_valid,
    input wire [1:0]  io_keyWr_part,
    input wire [2:0]  io_keyWr_idx,
    input wire [31:0] io_keyWr_data,
    input wire        io_nonceWr_valid,
    input wire [1:0]  io_nonceWr_part,
    input wire [2:0]  io_nonceWr_idx,
    input wire [31:0] io_nonceWr_data,
    input wire        io_rekey_valid,
    input wire [1:0]  io_rekey_part,
    input wire        io_en,
    input wire        io_req_valid,
    input wire [1:0]  io_req_part,
    input wire [31:0] io_req_frame,
    input wire        io_faultClearNoMask,
    input wire        io_faultClearNonceDup,
    input wire        io_faultClearWrRekey
);
  wire        io_rekey_ready;
  wire [3:0]  io_maskReady;
  wire        io_busy;
  wire        io_rsp_valid;
  wire [31:0] io_rsp_frame;
  wire        io_faultNoMask;
  wire        io_faultNonceDup;
  wire        io_faultWrDuringRekey;

  MaskUnit dut (
    .io_keyWr_valid(io_keyWr_valid), .io_keyWr_part(io_keyWr_part),
    .io_keyWr_idx(io_keyWr_idx), .io_keyWr_data(io_keyWr_data),
    .io_nonceWr_valid(io_nonceWr_valid), .io_nonceWr_part(io_nonceWr_part),
    .io_nonceWr_idx(io_nonceWr_idx), .io_nonceWr_data(io_nonceWr_data),
    .io_rekey_valid(io_rekey_valid), .io_rekey_ready(io_rekey_ready),
    .io_rekey_part(io_rekey_part),
    .io_maskReady(io_maskReady), .io_busy(io_busy),
    .io_en(io_en), .io_req_valid(io_req_valid), .io_req_part(io_req_part),
    .io_req_frame(io_req_frame),
    .io_rsp_valid(io_rsp_valid), .io_rsp_frame(io_rsp_frame),
    .io_faultNoMask(io_faultNoMask), .io_faultNonceDup(io_faultNonceDup),
    .io_faultWrDuringRekey(io_faultWrDuringRekey),
    .io_faultClearNoMask(io_faultClearNoMask),
    .io_faultClearNonceDup(io_faultClearNonceDup),
    .io_faultClearWrRekey(io_faultClearWrRekey),
    .clk(clk), .reset(reset)
  );

  MaskEngine_props u_MaskEngine_props (
    .clk(clk), .reset(reset),
    .io_keyWr_valid(io_keyWr_valid), .io_keyWr_part(io_keyWr_part),
    .io_nonceWr_valid(io_nonceWr_valid), .io_nonceWr_part(io_nonceWr_part),
    .io_nonceWr_idx(io_nonceWr_idx),
    .io_rekey_valid(io_rekey_valid), .io_rekey_ready(io_rekey_ready),
    .io_rekey_part(io_rekey_part),
    .io_maskReady(io_maskReady), .io_busy(io_busy),
    .io_faultWrDuringRekey(io_faultWrDuringRekey),
    .io_faultClearWrRekey(io_faultClearWrRekey)
  );
endmodule

`default_nettype wire
