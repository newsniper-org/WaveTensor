// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// SharedUnitDepth0 후-formal 하네스 — 깊이 0 (「항상 배압」, 정본 §2.2 3항)
// 형상의 재검사. GUARD-MAP queue_room 줄이 명시한 「깊이 0 이면
// queueRoom = False 상수」 문면과, 그 형상에서도 무처분-없음이 서는지를 잰다.
// 대상: rtl/generated/SharedUnitDepth0.sv (커밋본, 재생성 금지).
//
// 부착 방식: expose + 래퍼 — yosys 0.66 이 bind 를 조용히 무시함을 실측
// (경위는 SharedUnit_props.sv 파일 머리 참조).
//
// 가드 ↔ 단언 대응:
//   SharedUnit.busy_check   : a_busy_check
//   SharedUnit.queue_room   : a_always_bp — queueRoom/acceptQueue 상수 False
//                             (보류 자원이 없으니 덮어쓸 슬롯 자체가 없다)
//   SharedUnit.backpressure : a_bp_ready_def · a_bp_fault_set · a_bp_fault_sticky ·
//                             a_fab10_no_start
//   SharedUnit.no_overtake  : 공허 — 보류 열이 없어 추월 창이 존재하지 않는다
//                             (queueEmpty = True 상수를 a_always_bp 가 함께 재확인)
//   무처분-없음 (FAB-2 심장) : a_no_silent_drop — 직행 아니면 배압위반, 둘 중 하나
//
// assume 목록 (전수):
//   as_reset_shape — reset 은 시각 0 에만 활성. 근거: 정본 §1.5 (모델 Init
//   대응이 reset 직후 상태라는 ENV 계약) — SharedUnit_props.sv 와 동일.

`default_nettype none

module SharedUnitDepth0_props (
    input wire clk,
    input wire reset,
    input wire io_req_valid,
    input wire io_req_ready,
    input wire io_faultBpViolation,
    input wire io_faultClear,
    input wire body_1_io_busy,
    input wire body_1_io_start,
    input wire queueEmpty,
    input wire queueRoom,
    input wire acceptDirect,
    input wire acceptQueue,
    input wire bpViolation
);

  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;

  // as_reset_shape (근거는 파일 머리 참조)
  always @(*) as_reset_shape: assume (reset == !f_past_valid);

  wire startDirect = io_req_valid && acceptDirect;

  always @(posedge clk) if (!reset) begin
    // busy_check — 점유 중 직행 없음.
    a_busy_check: assert (!(body_1_io_start && body_1_io_busy));
    // queue_room (깊이 0 문면) — 보류 수락 경로가 상수로 닫혀 있고, 빈 열
    // 상수가 직행 판정을 본체 점유 하나로 접는다.
    a_always_bp: assert (!queueRoom && !acceptQueue && queueEmpty);
    // backpressure — ready 는 본체 점유의 즉각 반영이다 (받을 수 없음이
    // 언제나 상류에 보인다).
    a_bp_ready_def: assert (io_req_ready == !body_1_io_busy);
    // 무처분-없음 — 도착은 직행 아니면 배압위반, 정확히 하나.
    a_no_silent_drop: assert (!io_req_valid || $onehot({startDirect, bpViolation}));
    // FAB-10 — 위반 사이클에 본체가 시동되지 않는다 (pop 경로 자체가 없다).
    a_fab10_no_start: assert (!bpViolation || !body_1_io_start);
  end

  always @(posedge clk) if (f_past_valid && !reset && !$past(reset)) begin
    // backpressure — ready 무시 push 는 sticky fault 로 선다 / 명시적 해제
    // 외엔 내려가지 않는다.
    a_bp_fault_set:    assert (!$past(bpViolation) || io_faultBpViolation);
    a_bp_fault_sticky: assert (!$past(io_faultBpViolation && !io_faultClear) || io_faultBpViolation);
  end

  always @(posedge clk) if (!reset) begin
    c_direct: cover (startDirect);
    c_bp:     cover (bpViolation);
    c_fault:  cover (io_faultBpViolation);
  end

endmodule

// 형식 검증 톱 — 대상 + props 결선 (내부 포트는 sby [script] 의 expose 가 만든다).
module SharedUnitDepth0_formal (
    input wire        clk,
    input wire        reset,
    input wire        io_req_valid,
    input wire [15:0] io_req_payload,
    input wire        io_faultClear
);
  wire        io_req_ready;
  wire        io_rsp_valid;
  wire [15:0] io_rsp_payload;
  wire        io_faultBpViolation;
  wire [0:0]  io_occupancy;
  wire        body_1_io_busy, body_1_io_start;
  wire        queueEmpty, queueRoom, acceptDirect, acceptQueue, bpViolation;

  SharedUnitDepth0 dut (
    .clk(clk), .reset(reset),
    .io_req_valid(io_req_valid), .io_req_payload(io_req_payload),
    .io_req_ready(io_req_ready),
    .io_rsp_valid(io_rsp_valid), .io_rsp_payload(io_rsp_payload),
    .io_faultBpViolation(io_faultBpViolation), .io_faultClear(io_faultClear),
    .io_occupancy(io_occupancy),
    // ── expose 로 올린 내부 관측 포트 ──
    .body_1_io_busy(body_1_io_busy), .body_1_io_start(body_1_io_start),
    .queueEmpty(queueEmpty), .queueRoom(queueRoom),
    .acceptDirect(acceptDirect), .acceptQueue(acceptQueue),
    .bpViolation(bpViolation)
  );

  SharedUnitDepth0_props u_SharedUnitDepth0_props (
    .clk(clk), .reset(reset),
    .io_req_valid(io_req_valid), .io_req_ready(io_req_ready),
    .io_faultBpViolation(io_faultBpViolation), .io_faultClear(io_faultClear),
    .body_1_io_busy(body_1_io_busy), .body_1_io_start(body_1_io_start),
    .queueEmpty(queueEmpty), .queueRoom(queueRoom),
    .acceptDirect(acceptDirect), .acceptQueue(acceptQueue),
    .bpViolation(bpViolation)
  );
endmodule

`default_nettype wire
