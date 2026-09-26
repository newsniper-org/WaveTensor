// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// CapStatusWord 후-formal 하네스 — 능력 부재 관측 워드 CAP_STATUS(0xF8C, RO) ·
// CAP_CLEAR(0xF90, WO W1C) 의 행위. 선-formal rtl/formal/tla/CapWord.tla 의
// 가드 넷을 생성물 rtl/generated/CapStatusWord.sv 위에서 다시 잰다
// (2026-09-21 CAP_STATUS 파도, 정본 1126a38 — 축 둘→넷).
//
// 정본 (좌표 뒤 「」 는 그 줄의 축자 — lint_section_refs 축 1 이 대조한다):
//   e-defined.typ:500-503 「능력 부재도 관측이 sticky 여야 재시도 주체가 놓치지 않는다」
//     — 0xF8C RO 축 넷 + [31:4] RO 예약 = 0, 0xF90 WO 는 같은 비트 배치의
//     W1C 이고 [31:4] 예약 = 0 (엄격).
//   e-defined.typ:566-616 「넷은 서로 접지 않는다」 — 축은 「고칠 동작」으로 가른다.
//   01-isa-asm.typ:1540-1563 「관측은 sticky 다」 — 능력 부재는 fault 가 아니다.
//   rtl/spinal/src/main/scala/wt64/Common.scala:334 「해제와 발화가 같은 사이클이면 발화가 이긴다」
//     — StickyFault 규약. 이 워드는 그 순서만 승계한다.
//
// 부착 방식: 래퍼 모듈 CapStatusWord_formal 이 DUT 를 인스턴스하고 포트에
// 검사자를 붙인다. bind 는 yosys 0.66 이 조용히 무시한다 (SharedUnit_props.sv
// 파일 머리의 실측). 필요한 신호가 전부 포트라 expose 도 없다 — 내부 이름
// (defined_k · StickyFault 의 줄번호 매인 when 이름) 을 하나도 참조하지
// 않으므로 Scala 줄 밀림에 이 하네스가 무력화될 자리가 없다. (그 이름을
// 여기 축자로 적지 않는 이유: lint_generated_names 는 주석도 훑으므로 적는
// 순간 이 파일이 그 핀의 보유자로 계수된다 — 미끼 주석.)
//
// 지상 진리는 DUT 어휘를 재인용하지 않는다: 예약 마스크 [31:4] 는 이 파일의
// 리터럴(f_rsvHit = |io_wdata[31:4])이고, 수락 판정 f_accept 도 그것에서
// 다시 유도한다. DUT 의 io_rsvBad·io_clrAcc 는 그 독립 유도와 *등식*으로
// 대조된다 — 마스크를 [31:2] 로 넓힌 변이가 a_rsvbad_def 에서 반례를 낸다.
//
// 가드 ↔ 단언 대응:
//   CapWord.axis_isolated      : a_isolated_1/2/3 (축 k 의 사건이 있어도 다른
//                                축은 자기 법칙대로만 움직인다 — 사건 쪽 문면)
//                                · a_rise_only_by_set_1/2/3 (비트 k 의 상승은
//                                set(k) 뿐 — 비트 쪽 문면) · a_passthru_0
//                                (축 0 은 set(0) 의 레벨 그 자체)
//   CapWord.sticky_until_clear : a_sticky_1/2/3 (선 비트는 그 축의 수락된
//                                W1C 없이는 내려가지 않는다) · a_clear_1/2/3
//                                (수락된 W1C 는 실제로 내린다 — 사건이 겹치지
//                                않는 한). 축 0 은 pass-through 라 여기 없다:
//                                그 sticky 는 Reassembly.capBit 이고
//                                Reassembly_props.sv 의 t_capa_next_eq 가 잰다
//                                (lint_postformal `_PARTIAL` 등재)
//   CapWord.clear_atomic       : a_clear_atomic (거절된 기입은 어느 축의 해제도
//                                수락하지 않고 한 비트도 내리지 않는다) ·
//                                a_rsvbad_def (거절 = wr ∧ [31:4] 비0, 하네스
//                                리터럴) · a_clracc_def (수락 W1C = accept ∧
//                                wdata[k], 축 넷 전부)
//   CapWord.set_beats_clear    : a_set_beats_clear_1/2/3 (set(k) 가 있었던
//                                축은 다음 사이클에 서 있다 — 같은 사이클에
//                                그 축의 W1C 가 수락됐더라도). 일반형(전건이
//                                set 하나)으로 적어 「사건이 관측된다」도 함께
//                                잰다 — 겹침 도달성은 증인 W4 가 든다. 축 0 은
//                                이 컴포넌트에 그 겹침이 없다 (`_PARTIAL`)
//   워드 인코딩               : a_rsv_reads_zero (CAP_STATUS [31:4] 읽기 0)
//
// assume 목록 (전수):
//   as_reset_shape — reset 은 시각 0 에만 활성. 근거: 정본 §1.5 (모델 Init
//   대응이 reset 직후 상태라는 ENV 계약) — SharedUnitDepth0_props.sv 와 동일.
//   기능 입력(io_set · io_wr · io_wdata)은 전부 자유다 — 상류 sticky 의 레벨
//   형상도, 기입의 정렬·구역 선택도 가정하지 않는다 (그것은 Top 의 몫이고
//   여기서 가정하면 반례 공간이 준다).
//
// 이 태스크가 재지 **않는** 것 (각각 어디가 재는가):
//   · Top 이 set(3) := False 로 묶어 [3] 이 상수 0 이라는 것 — Wt64Top 의
//     결선이며 2026-09-26 부터 조립층 rtl/formal/sby/Wt64Top/assembly.sby 가
//     MMIO 읽기 표면으로 잰다 (a_rd_capb3 — 내부 넷 상수 단언은 계층 모델에서
//     상수 접힘 검사를 비껴가므로 쓰지 않았다).
//     원천 부재는 rtl/README.md 「자리는 있고 회로는 없다」 표의 CAP_STATUS[3]
//     행이 든다.
//     여기서 io_set[3] 은 자유 입력이다 — 컴포넌트 계약은 네 축 대칭이다.
//   · [2] 의 set 이 walk.oValid 로 유효 한정된다는 것(쓰레기 헤더로 [2] 가
//     서지 않는다) — 같은 Top 결선(`capSet_2 = walk_io_oValid && …`)이고 조립층
//     assembly.sby 의 a_cap2_rise 가 잰다. DecodeWalk 자신의 판정(capAbsent = declLen > 14)은
//     DecodeWalk/walk_decode.sby 의 Walk.cap_declared · Decode.mal_carried 가 잰다.
//   · 능력 부재가 fault 워드에 들지 않는 것 — 이 컴포넌트에 fault 포트가 없는
//     것이 그 이행이고(구조), 원천 쪽은 Reassembly/props.sby 의
//     Payload.capability_not_fault · DecodeWalk/walk_decode.sby 의
//     Decode.fault_not_folded 가 잰다. 거절(io_rsvBad)을 FAULT_STATUS[6] 에
//     잇는 Top 결선(surfBadWr)은 조립층 assembly.sby 의 a_surf_fire · a_rd_fst 가 잰다.
//   · clrAcc(0) 이 Reassembly 의 capAbsentClear 로 실제로 이어지는 것 —
//     Top 결선 — 조립층 assembly.sby 의 a_cap0_clr 가 잰다. 이 하네스는 clrAcc(0) 이 *옳게 나온다*
//     (a_clracc_def) 까지만 잰다.

`default_nettype none

module CapStatusWord_props (
    input wire        clk,
    input wire        reset,
    input wire [3:0]  io_set,
    input wire        io_wr,
    input wire [31:0] io_wdata,
    input wire [31:0] io_word,
    input wire        io_rsvBad,
    input wire [3:0]  io_clrAcc
);

  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;

  // as_reset_shape (근거는 파일 머리 참조)
  always @(*) as_reset_shape: assume (reset == !f_past_valid);

  // 지상 진리 — 정본 마스크 [31:4] 를 이 파일의 리터럴로 다시 적는다.
  wire        f_rsvHit = |io_wdata[31:4];
  wire        f_accept = io_wr && !f_rsvHit;
  wire [3:0]  f_clrAcc = {4{f_accept}} & io_wdata[3:0];

  // ═══ 조합 단언 (리셋 밖 매 사이클) ═══════════════════════════════════
  always @(posedge clk) if (!reset) begin
    // 워드 인코딩 — [31:4] 는 RO 예약, 읽기 0.
    a_rsv_reads_zero: assert (io_word[31:4] == 28'h0);
    // clear_atomic — 거절 판정의 정의. 마스크는 하네스 리터럴이다.
    a_rsvbad_def: assert (io_rsvBad == (io_wr && f_rsvHit));
    // clear_atomic — 수락된 축별 W1C 의 정의 (축 넷 전부, pass-through 축
    // 포함 — 그 펄스는 Top 이 상류 sticky 의 clear 로 나른다).
    a_clracc_def: assert (io_clrAcc == f_clrAcc);
    // axis_isolated (축 0) — pass-through: 워드 비트는 상류 레벨 그 자체다.
    // sticky 로 바꾼 변이는 set(0) 이 오른 그 사이클에 여기서 반례가 난다
    // (등록된 비트는 한 사이클 늦다) — 이중 sticky 레이스의 방지 조항.
    a_passthru_0: assert (io_word[0] == io_set[0]);
  end

  // ═══ 전이 단언 (연속 두 사이클 리셋 밖) ═══════════════════════════
  always @(posedge clk) if (f_past_valid && !reset && !$past(reset)) begin
    // ── sticky_until_clear — 선 비트는 그 축의 수락된 W1C 로만 내려간다 ──
    // 읽기도, 시간도, 다른 축의 해제도, 거절된 기입도 아니다.
    a_sticky_1: assert (!($past(io_word[1]) && !$past(io_clrAcc[1])) || io_word[1]);
    a_sticky_2: assert (!($past(io_word[2]) && !$past(io_clrAcc[2])) || io_word[2]);
    a_sticky_3: assert (!($past(io_word[3]) && !$past(io_clrAcc[3])) || io_word[3]);
    // ── sticky_until_clear — 수락된 W1C 는 실제로 내린다 (사건이 안 겹치면) ──
    // a_sticky_k 만으로는 「영영 안 내려가는」 구현이 통과한다 — 이 등식의
    // 반쪽이 그 구멍을 막는다.
    a_clear_1: assert (!($past(io_clrAcc[1]) && !$past(io_set[1])) || !io_word[1]);
    a_clear_2: assert (!($past(io_clrAcc[2]) && !$past(io_set[2])) || !io_word[2]);
    a_clear_3: assert (!($past(io_clrAcc[3]) && !$past(io_set[3])) || !io_word[3]);
    // ── set_beats_clear — set(k) 가 있었던 축은 다음 사이클에 서 있다 ──
    // 같은 사이클에 그 축의 W1C 가 수락됐더라도 (StickyFault 규약 승계).
    // 전건을 set 하나로 두어 「사건이 관측된다」까지 함께 잰다 — 해제가
    // 이기게 한 변이는 겹침 사이클에서, set 을 무시하는 변이는 첫 사건에서
    // 각각 반례가 난다.
    a_set_beats_clear_1: assert (!$past(io_set[1]) || io_word[1]);
    a_set_beats_clear_2: assert (!$past(io_set[2]) || io_word[2]);
    a_set_beats_clear_3: assert (!$past(io_set[3]) || io_word[3]);
    // ── axis_isolated — 비트 k 의 상승 원천은 set(k) 하나 ──
    a_rise_only_by_set_1: assert (!(io_word[1] && !$past(io_word[1])) || $past(io_set[1]));
    a_rise_only_by_set_2: assert (!(io_word[2] && !$past(io_word[2])) || $past(io_set[2]));
    a_rise_only_by_set_3: assert (!(io_word[3] && !$past(io_word[3])) || $past(io_set[3]));
    // ── axis_isolated — 축 k 의 사건이 있어도 다른 축은 자기 법칙대로만 ──
    // 움직인다: sticky 축 j 는 set(j) ∨ (선 채 ∧ ¬clrAcc(j)), 축 0 은 레벨.
    // 「축 k 의 set 이 축 j 도 세운다」 변이는 set(j)=0 · word(j)=0 인 사건
    // 사이클에서 여기서 반례가 난다.
    a_isolated_1: assert (!$past(io_set[1]) || (
        io_word[0] == io_set[0] &&
        io_word[2] == ($past(io_set[2]) || ($past(io_word[2]) && !$past(io_clrAcc[2]))) &&
        io_word[3] == ($past(io_set[3]) || ($past(io_word[3]) && !$past(io_clrAcc[3])))));
    a_isolated_2: assert (!$past(io_set[2]) || (
        io_word[0] == io_set[0] &&
        io_word[1] == ($past(io_set[1]) || ($past(io_word[1]) && !$past(io_clrAcc[1]))) &&
        io_word[3] == ($past(io_set[3]) || ($past(io_word[3]) && !$past(io_clrAcc[3])))));
    a_isolated_3: assert (!$past(io_set[3]) || (
        io_word[0] == io_set[0] &&
        io_word[1] == ($past(io_set[1]) || ($past(io_word[1]) && !$past(io_clrAcc[1]))) &&
        io_word[2] == ($past(io_set[2]) || ($past(io_word[2]) && !$past(io_clrAcc[2])))));
    // ── clear_atomic — 거절된 기입은 반쯤 수락이 없다 ──
    // 어느 축의 해제도 수락되지 않았고(축 0 의 상류행 펄스 포함), sticky 축
    // 어느 비트도 내려가지 않았다. 축 0 의 레벨은 상류가 따로 내릴 수 있어
    // 「내려가지 않음」 항에서 뺀다 (그 상류의 해제 authority 는 이 하네스
    // 밖이다).
    a_clear_atomic: assert (!$past(io_rsvBad) || (
        $past(io_clrAcc) == 4'b0 &&
        ($past(io_word[3:1]) & ~io_word[3:1]) == 3'b0));
  end

  // ── 도달성 증인 (cover 태스크 전용 — 단언의 공허 방지) ──────────────
  //
  // 각 줄의 `←` 오른쪽이 **그 증인이 살리는 대상**이다: `<Model>.<guard>` 는
  // 이 태스크의 `# PROVES:` 앵커, 소문자 식별자는 이 하네스의 단언 라벨.
  // 줄번호로 매지 않는다. scripts/lint_witness_map.py 가 이 선언의 **참조
  // 실재성**을 재고, 뜻은 재지 못한다.

  // W1 ← CapWord.sticky_until_clear · CapWord.set_beats_clear
  //      sticky 축 각각의 비트가 실제로 선다. 서지 않으면 a_sticky_k 의 전건도
  //      a_set_beats_clear_k 의 결론도 관측된 적이 없는 채 통과한다.
  // W2 ← CapWord.sticky_until_clear
  //      선 비트가 그 축의 수락된 W1C 로 실제로 내려간다 — a_clear_k 의 전건
  //      도달. CAP_CLEAR 예약이 [31:2] 인 기계에서는 축 2·3 의 이 증인이
  //      도달 불가다 (선-formal Witness_NoClear 가 잡는 것과 같은 결함).
  // W3 ← CapWord.clear_atomic
  //      sticky 비트가 선 채로 예약 위반 기입이 거절된다 — a_clear_atomic 의
  //      「한 비트도 내려가지 않았다」 항이 빈 워드 위에서 자명하게 참이
  //      되는 것을 막는다.
  // W4 ← CapWord.set_beats_clear
  //      선 비트에 같은 사이클 사건과 수락된 해제가 겹친다 — 그 겹침이 없는
  //      세계에서 「발화가 이긴다」는 한 번도 시험되지 않는다.
  // W5 ← CapWord.axis_isolated
  //      축 1 단독 사건 앞뒤로 축 2 는 선 채 · 축 3 은 내린 채 그대로다 —
  //      a_isolated_1 의 전건이 「그대로 둘 것이 있는」 상태에서 도달한다.
  // W6 ← a_passthru_0
  //      축 0 의 레벨이 기입 없이 내려간다 — sticky 축이라면 원리적으로 불가한
  //      궤적이다 (내려가려면 수락된 W1C 가 있어야 한다). pass-through 를
  //      sticky 로 바꾼 변이는 a_passthru_0 의 반례에 더해 이 증인을 잃는다.
  always @(posedge clk) if (!reset) begin
    w1_set_1: cover (io_word[1]);
    w1_set_2: cover (io_word[2]);
    w1_set_3: cover (io_word[3]);
    w3_rejected_while_set: cover (io_rsvBad && (io_word[3:1] != 3'b0));
    w4_set_and_clear_same_cycle: cover (|(io_word[3:1] & io_set[3:1] & io_clrAcc[3:1]));
  end

  always @(posedge clk) if (f_past_valid && !reset && !$past(reset)) begin
    w2_clear_1: cover ($past(io_word[1]) && $past(io_clrAcc[1]) && !io_word[1]);
    w2_clear_2: cover ($past(io_word[2]) && $past(io_clrAcc[2]) && !io_word[2]);
    w2_clear_3: cover ($past(io_word[3]) && $past(io_clrAcc[3]) && !io_word[3]);
    w5_other_axis_stays: cover ($past(io_set[1] && !io_set[2] && !io_set[3] && io_word[2] && !io_word[3])
                                && io_word[1] && io_word[2] && !io_word[3]);
    w6_passthru_toggle: cover ($past(io_word[0]) && !io_word[0] && !$past(io_wr) && !io_wr);
  end

endmodule

// 형식 검증 톱 — 대상 + props 결선. 내부 포트 없음 (expose 불필요).
module CapStatusWord_formal (
    input wire        clk,
    input wire        reset,
    input wire [3:0]  io_set,
    input wire        io_wr,
    input wire [31:0] io_wdata
);
  wire [31:0] io_word;
  wire        io_rsvBad;
  wire [3:0]  io_clrAcc;

  CapStatusWord dut (
    .io_set(io_set), .io_wr(io_wr), .io_wdata(io_wdata),
    .io_word(io_word), .io_rsvBad(io_rsvBad), .io_clrAcc(io_clrAcc),
    .clk(clk), .reset(reset)
  );

  CapStatusWord_props u_CapStatusWord_props (
    .clk(clk), .reset(reset),
    .io_set(io_set), .io_wr(io_wr), .io_wdata(io_wdata),
    .io_word(io_word), .io_rsvBad(io_rsvBad), .io_clrAcc(io_clrAcc)
  );
endmodule

`default_nettype wire
