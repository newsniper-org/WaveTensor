// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// MemOrderGate 후-formal 하네스 — 선-formal MemOrder.tla 의 AllGuards(7)를
// 커밋된 rtl/generated/MemOrderGate.sv (N=4, cfgPreds 폭 3) 에 대해 재검사.
// bind 로 대상 안에 부착 — 포트는 대상 내부 신호명 그대로 결선한다.
//
// 검사 문체: yosys 개방판은 SVA 시퀀스 연산자를 받지 않으므로 즉시 단언
// (always 블록 + $past) 로 쓴다. 게이트/발화 속성은 부등식이 아니라
// *등식*으로 쓴다 — 등식이 서면 「콘에 그 신호뿐」이 기계 검증되므로
// wave/addr/inflight_not_gating 의 구조 주장을 문면 그대로 재는 셈이다.
//
// predIdx(i)(k) = (k < i ? k : k+1)  — cfgPreds 비트가 가리키는 선행 슬롯:
//   슬롯0: preds = {1,2,3} / 슬롯1: {0,2,3} / 슬롯2: {0,1,3} / 슬롯3: {0,1,2}
module MemOrderGate_props (
  input logic        clk,
  input logic        reset,
  input logic [2:0]  io_cfgPreds_0,
  input logic [2:0]  io_cfgPreds_1,
  input logic [2:0]  io_cfgPreds_2,
  input logic [2:0]  io_cfgPreds_3,
  input logic        io_epochClear,
  input logic [3:0]  io_complete,
  input logic [3:0]  io_token,
  input logic [3:0]  io_gateOpen,
  input logic        io_up_0_valid,
  input logic        io_up_0_ready,
  input logic [15:0] io_up_0_payload,
  input logic        io_up_1_valid,
  input logic        io_up_1_ready,
  input logic [15:0] io_up_1_payload,
  input logic        io_up_2_valid,
  input logic        io_up_2_ready,
  input logic [15:0] io_up_2_payload,
  input logic        io_up_3_valid,
  input logic        io_up_3_ready,
  input logic [15:0] io_up_3_payload,
  input logic        io_down_0_valid,
  input logic        io_down_0_ready,
  input logic [15:0] io_down_0_payload,
  input logic        io_down_1_valid,
  input logic        io_down_1_ready,
  input logic [15:0] io_down_1_payload,
  input logic        io_down_2_valid,
  input logic        io_down_2_ready,
  input logic [15:0] io_down_2_payload,
  input logic        io_down_3_valid,
  input logic        io_down_3_ready,
  input logic [15:0] io_down_3_payload
);

  // ── 리셋 규율 ────────────────────────────────────────────────────────
  // ENV: 기계는 리셋에서 시작한다 (선-formal Init 대응 — 모델 초기 상태
  // token=FALSE 전원). 근거: 모델 Init 이 유일한 시작점이고, RTL 의
  // 대응물이 리셋이다. 이것이 이 하네스의 유일한 assume 이다.
  initial assume (reset);

  logic f_past_valid = 1'b0;
  logic f_past_reset = 1'b1;
  always @(posedge clk) begin
    f_past_valid <= 1'b1;
    f_past_reset <= reset;
  end

  // 전이 단언 게이트: 직전·현재 사이클 모두 리셋 밖일 때만 잰다.
  wire f_step = f_past_valid && !reset && !f_past_reset;

  // ── MemOrder.token_gate + MemOrder.gate_matches_dep ─────────────────
  // 게이트 열림 = cfgPreds 가 지목한 선행 토큰 전량 완료 — *등식*.
  //   ← 방향(모든 선행 완료 → 열림)이 gate_matches_dep 의 「기계가 더하지
  //     않는다」(과잉 게이팅 부재), → 방향(열림 → 모든 선행 완료)이
  //     token_gate 의 「선행 미완이면 발화 억제」다.
  always @(*) if (!reset) begin
    g_open_eq_0: assert (io_gateOpen[0] == !((io_cfgPreds_0[0] && !io_token[1])
                                          || (io_cfgPreds_0[1] && !io_token[2])
                                          || (io_cfgPreds_0[2] && !io_token[3])));
    g_open_eq_1: assert (io_gateOpen[1] == !((io_cfgPreds_1[0] && !io_token[0])
                                          || (io_cfgPreds_1[1] && !io_token[2])
                                          || (io_cfgPreds_1[2] && !io_token[3])));
    g_open_eq_2: assert (io_gateOpen[2] == !((io_cfgPreds_2[0] && !io_token[0])
                                          || (io_cfgPreds_2[1] && !io_token[1])
                                          || (io_cfgPreds_2[2] && !io_token[3])));
    g_open_eq_3: assert (io_gateOpen[3] == !((io_cfgPreds_3[0] && !io_token[0])
                                          || (io_cfgPreds_3[1] && !io_token[1])
                                          || (io_cfgPreds_3[2] && !io_token[2])));

    // 발화 면 = 게이트 연언 — 등식. down.valid 콘 = {up.valid, gateOpen},
    // up.ready 콘 = {gateOpen, down.ready}. 여기에 payload·타 슬롯 handshake
    // 항이 없음이 등식으로 닫힌다 (wave/addr/inflight_not_gating 의 콘 폐쇄).
    g_fire_eq_0v: assert (io_down_0_valid == (io_up_0_valid && io_gateOpen[0]));
    g_fire_eq_1v: assert (io_down_1_valid == (io_up_1_valid && io_gateOpen[1]));
    g_fire_eq_2v: assert (io_down_2_valid == (io_up_2_valid && io_gateOpen[2]));
    g_fire_eq_3v: assert (io_down_3_valid == (io_up_3_valid && io_gateOpen[3]));
    g_fire_eq_0r: assert (io_up_0_ready == (io_gateOpen[0] && io_down_0_ready));
    g_fire_eq_1r: assert (io_up_1_ready == (io_gateOpen[1] && io_down_1_ready));
    g_fire_eq_2r: assert (io_up_2_ready == (io_gateOpen[2] && io_down_2_ready));
    g_fire_eq_3r: assert (io_up_3_ready == (io_gateOpen[3] && io_down_3_ready));

    // MemOrder.addr_not_gating / wave_not_gating 보강: payload 는 불투명
    // 전량 통과 — 게이트가 내용을 읽지도 바꾸지도 않는다.
    g_payload_0: assert (io_down_0_payload == io_up_0_payload);
    g_payload_1: assert (io_down_1_payload == io_up_1_payload);
    g_payload_2: assert (io_down_2_payload == io_up_2_payload);
    g_payload_3: assert (io_down_3_payload == io_up_3_payload);
  end

  // ── MemOrder.token_on_complete + MemOrder.complete_not_ordered ──────
  // 토큰 차기 상태 함수의 *등식*: token(j)' = complete(j) ∨ (token(j) ∧
  // ¬epochClear). RTL 기술 순서(epochClear 소거 후 complete set)까지 문면
  // 그대로다. 등식이 서면:
  //   - 토큰 상승의 유일 원천이 자기 complete 비트 (token_on_complete —
  //     발화 사건 down.fire 는 콘에 없음),
  //   - 타 슬롯 complete·token·handshake 가 콘에 없음 (complete_not_ordered
  //     — 완료 경로에 FIFO·순서 비교·상호 게이트 부재),
  // 둘이 한꺼번에 기계 검증된다. 동시·역순 완료 수락은 이 함수의 슬롯별
  // 독립에서 자명하다.
  always @(posedge clk) if (f_step) begin
    t_next_eq_0: assert (io_token[0] == ($past(io_complete[0]) || ($past(io_token[0]) && !$past(io_epochClear))));
    t_next_eq_1: assert (io_token[1] == ($past(io_complete[1]) || ($past(io_token[1]) && !$past(io_epochClear))));
    t_next_eq_2: assert (io_token[2] == ($past(io_complete[2]) || ($past(io_token[2]) && !$past(io_epochClear))));
    t_next_eq_3: assert (io_token[3] == ($past(io_complete[3]) || ($past(io_token[3]) && !$past(io_epochClear))));

    // token_on_complete 의 문면 재확인: 상승 에지 → 직전 사이클 완료.
    t_rise_0: assert (!(io_token[0] && !$past(io_token[0])) || $past(io_complete[0]));
    t_rise_1: assert (!(io_token[1] && !$past(io_token[1])) || $past(io_complete[1]));
    t_rise_2: assert (!(io_token[2] && !$past(io_token[2])) || $past(io_complete[2]));
    t_rise_3: assert (!(io_token[3] && !$past(io_token[3])) || $past(io_complete[3]));
  end

endmodule

// 대상 안에 부착 — 내부 신호는 대상 스코프에서 이름으로 결선된다.
bind MemOrderGate MemOrderGate_props u_props (
  .clk(clk), .reset(reset),
  .io_cfgPreds_0(io_cfgPreds_0), .io_cfgPreds_1(io_cfgPreds_1),
  .io_cfgPreds_2(io_cfgPreds_2), .io_cfgPreds_3(io_cfgPreds_3),
  .io_epochClear(io_epochClear), .io_complete(io_complete),
  .io_token(io_token), .io_gateOpen(io_gateOpen),
  .io_up_0_valid(io_up_0_valid), .io_up_0_ready(io_up_0_ready), .io_up_0_payload(io_up_0_payload),
  .io_up_1_valid(io_up_1_valid), .io_up_1_ready(io_up_1_ready), .io_up_1_payload(io_up_1_payload),
  .io_up_2_valid(io_up_2_valid), .io_up_2_ready(io_up_2_ready), .io_up_2_payload(io_up_2_payload),
  .io_up_3_valid(io_up_3_valid), .io_up_3_ready(io_up_3_ready), .io_up_3_payload(io_up_3_payload),
  .io_down_0_valid(io_down_0_valid), .io_down_0_ready(io_down_0_ready), .io_down_0_payload(io_down_0_payload),
  .io_down_1_valid(io_down_1_valid), .io_down_1_ready(io_down_1_ready), .io_down_1_payload(io_down_1_payload),
  .io_down_2_valid(io_down_2_valid), .io_down_2_ready(io_down_2_ready), .io_down_2_payload(io_down_2_payload),
  .io_down_3_valid(io_down_3_valid), .io_down_3_ready(io_down_3_ready), .io_down_3_payload(io_down_3_payload)
);
