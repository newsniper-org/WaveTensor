// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// SharedUnit 후-formal 하네스 (§6.3) — FAB-2 처분 구조의 GUARD-MAP CHECK 4줄을
// 구현된 회로(rtl/generated/SharedUnit.sv — 커밋본, 재생성 금지)에 대해
// 재검사한다. yosys+sby(smtbmc z3) 용 — 시제 SVA 없이 $past 기반 즉시 단언.
//
// 부착 방식 — bind 계획의 실측 이탈 (2026-08-24): yosys 0.66 네이티브
// 프런트엔드는 `bind` 지시를 오류 없이 파싱하되 조용히 무시한다 (최소
// 재현 3변형으로 실측 — 파일 꼭대기·모듈 스코프·-defer 유무 전부, 하네스가
// 「unused module」로 제거됨). 그래서 동등물로 부착한다: sby [script] 의
// `expose` 가 대상 내부 신호를 포트로 올리고, 아래 <Module>_formal 래퍼가
// 대상과 이 props 모듈을 결선한다. props 모듈 자체는 bind 가능한 형태
// 그대로다 — bind 지원 도구가 오면 래퍼를 bind 한 줄로 되돌리면 된다.
//
// 가드 ↔ 단언 대응 (가드명 = rtl/spinal/src/main/scala/wt64/fabric/SharedUnit.scala
// 의 GUARD-MAP 줄과 동일):
//   SharedUnit.busy_check   : a_busy_check · a_no_double_start
//   SharedUnit.queue_room   : a_queue_room · a_cnt_bound · a_ptr_sync
//   SharedUnit.backpressure : a_bp_full_ready_low · a_bp_fault_set · a_bp_fault_sticky
//                             + FAB-10(위반 갈래 무기입): a_fab10_no_start ·
//                               a_fab10_wrptr_hold · a_fab10_slot_untouched · a_fab10_cnt
//   SharedUnit.no_overtake  : a_no_overtake_direct · a_order_direct · a_order_pop
//                             + 카운터 태깅 보조 논리: a_tag_count · a_tag_fifo0..3
//   무처분-없음 (FAB-2 심장) : a_no_silent_drop — 도착(valid) 사이클은
//                             직행/보류/배압위반 셋 중 정확히 하나를 받는다
//                             (ready 정의의 완전성; 수락도 배압도 아닌 도착 부재)
//   본체 입력 정합           : a_body_req_direct · a_body_req_pop — 본체에
//                             닿는 값은 직행 페이로드 아니면 큐 head 뿐
//
// assume 목록 (전수):
//   as_reset_shape — reset 은 시각 0 에만 활성, 이후 비활성.
//     근거: 정본 §1.5 (reset 후 초기 상태에서 출발) — 선-formal 모델의 Init
//     대응이 reset 직후 상태라는 ENV 계약. 모델은 리셋 재진입 시간축을 갖지
//     않으므로 (원자 인터리빙 모델) 재검사도 같은 정의역에서 한다.
//   그 외 입력(io_req_valid·payload·faultClear)은 전부 자유 — push 규약
//   위반(ready 무시 valid)도 fault 갈래의 검사 대상이므로 assume 하지 않는다.

`default_nettype none

module SharedUnit_props (
    input wire        clk,
    input wire        reset,
    input wire        io_req_valid,
    input wire [15:0] io_req_payload,
    input wire        io_req_ready,
    input wire        io_faultBpViolation,
    input wire        io_faultClear,
    input wire        body_1_io_busy,
    input wire        body_1_io_start,
    input wire [15:0] body_1_io_req,
    input wire [15:0] queue_slots_0,
    input wire [15:0] queue_slots_1,
    input wire [15:0] queue_slots_2,
    input wire [15:0] queue_slots_3,
    input wire [1:0]  queue_rdPtr,
    input wire [1:0]  queue_wrPtr,
    input wire [2:0]  queue_cnt,
    input wire        queueEmpty,
    input wire        queueRoom,
    input wire        acceptDirect,
    input wire        acceptQueue,
    input wire        bpViolation,
    input wire        when_SharedUnit_l192   // pop = !busy && !queueEmpty
);

  // ── 시간 기준 ────────────────────────────────────────────────────────
  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;

  // as_reset_shape (근거는 파일 머리 assume 목록 참조)
  always @(*) as_reset_shape: assume (reset == !f_past_valid);

  // ── 처분 세 갈래의 이름 ─────────────────────────────────────────────
  wire startDirect = io_req_valid && acceptDirect;   // 처분 1 — 즉시 점유
  wire pushQ       = io_req_valid && acceptQueue;    // 처분 2 — 보류
  wire pop         = when_SharedUnit_l192;           // 큐 → 본체 (모델 Dequeue)

  // ── 카운터 태깅 보조 논리 (no_overtake 의 FIFO 순서 관측) ───────────
  // 수락된 도착마다 일련번호(issueTag)를 발급하고, 본체 start 마다 처리
  // 일련번호(startCount)를 올린다. FIFO 보존이면 start 는 발급 순서 그대로다.
  // 8b 모듈러 산술 — cnt <= 4 이므로 차이가 감기지 않는다.
  reg [7:0] issueTag;
  reg [7:0] startCount;
  reg [7:0] shadowTag0, shadowTag1, shadowTag2, shadowTag3;

  always @(posedge clk) begin
    if (reset) begin
      issueTag   <= 8'd0;
      startCount <= 8'd0;
      shadowTag0 <= 8'd0;
      shadowTag1 <= 8'd0;
      shadowTag2 <= 8'd0;
      shadowTag3 <= 8'd0;
    end else begin
      if (pushQ) begin
        case (queue_wrPtr)
          2'd0: shadowTag0 <= issueTag;
          2'd1: shadowTag1 <= issueTag;
          2'd2: shadowTag2 <= issueTag;
          default: shadowTag3 <= issueTag;
        endcase
      end
      if (startDirect || pushQ) issueTag   <= issueTag + 8'd1;
      if (pop || startDirect)   startCount <= startCount + 8'd1;
    end
  end

  function automatic [7:0] shadow_at(
      input [1:0] i,
      input [7:0] t0, input [7:0] t1, input [7:0] t2, input [7:0] t3);
    case (i)
      2'd0: shadow_at = t0;
      2'd1: shadow_at = t1;
      2'd2: shadow_at = t2;
      default: shadow_at = t3;
    endcase
  endfunction

  wire [7:0] tag_i0 = shadow_at(queue_rdPtr + 2'd0, shadowTag0, shadowTag1, shadowTag2, shadowTag3);
  wire [7:0] tag_i1 = shadow_at(queue_rdPtr + 2'd1, shadowTag0, shadowTag1, shadowTag2, shadowTag3);
  wire [7:0] tag_i2 = shadow_at(queue_rdPtr + 2'd2, shadowTag0, shadowTag1, shadowTag2, shadowTag3);
  wire [7:0] tag_i3 = shadow_at(queue_rdPtr + 2'd3, shadowTag0, shadowTag1, shadowTag2, shadowTag3);

  function automatic [15:0] slot_at(
      input [1:0] i,
      input [15:0] s0, input [15:0] s1, input [15:0] s2, input [15:0] s3);
    case (i)
      2'd0: slot_at = s0;
      2'd1: slot_at = s1;
      2'd2: slot_at = s2;
      default: slot_at = s3;
    endcase
  endfunction

  wire [15:0] slot_wr   = slot_at(queue_wrPtr, queue_slots_0, queue_slots_1, queue_slots_2, queue_slots_3);
  wire [15:0] queueHead = slot_at(queue_rdPtr, queue_slots_0, queue_slots_1, queue_slots_2, queue_slots_3);

  // ── 조합 단언 (reset 사이클 제외) ───────────────────────────────────
  always @(posedge clk) if (!reset) begin
    // busy_check — 점유 중 직행 없음: start 는 본체가 빈 사이클에만 선다.
    a_busy_check: assert (!(body_1_io_start && body_1_io_busy));
    // busy_check — start 단일 발화: 직행과 pop 이 같은 사이클에 겹치지 않는다
    // (queueEmpty 가 두 경로를 가른다).
    a_no_double_start: assert (!(pop && startDirect));

    // queue_room — 자리 검사 없이 보류 자원에 쓰지 않는다.
    a_queue_room: assert (!pushQ || (queue_cnt < 3'd4));
    // queue_room 보조 불변 — 점유 계수는 자원 상한을 넘지 않는다 (덮어쓰기
    // 부재의 상태 표현; k-귀납 보강 불변이기도 하다).
    a_cnt_bound: assert (queue_cnt <= 3'd4);
    // queue_room 보조 불변 — 포인터·계수 정합: wr = rd + cnt (mod 4).
    // 이 정합이 서면 기입 위치(wrPtr)는 항상 비-점유 슬롯이다 — valid 이중
    // 기입(덮어쓰기) 부재가 여기서 나온다.
    a_ptr_sync: assert (queue_wrPtr == (queue_rdPtr + queue_cnt[1:0]));

    // backpressure — 가득 참이 ready 강하로 상류에 보인다.
    a_bp_full_ready_low: assert (!(queue_cnt == 3'd4) || !io_req_ready);

    // 무처분-없음 (FAB-2) — 도착은 정확히 한 갈래를 받는다. ready 정의가
    // 세 갈래를 빈틈·중복 없이 가른다는 완전성 그 자체.
    a_no_silent_drop: assert (!io_req_valid || $onehot({startDirect, pushQ, bpViolation}));

    // no_overtake — 보류 열이 비어 있지 않으면 직행이 닫힌다.
    a_no_overtake_direct: assert (!(!queueEmpty && acceptDirect));
    // no_overtake — FIFO 순서 (태깅): 직행 수락은 대기자 전무(발급=처리)일 때만.
    a_order_direct: assert (!startDirect || (issueTag == startCount));
    // no_overtake — FIFO 순서 (태깅): pop 되는 head 는 항상 다음 처리 번호다.
    a_order_pop: assert (!pop || (tag_i0 == startCount));
    // 태깅 보조 불변 — 미처리 잔량 = 큐 점유 (k-귀납 보강).
    a_tag_count: assert ((issueTag - startCount) == {5'd0, queue_cnt});
    // 태깅 보조 불변 — 큐 안 태그는 rd 부터 연번이다 (k-귀납 보강).
    a_tag_fifo0: assert ((queue_cnt < 3'd1) || (tag_i0 == startCount));
    a_tag_fifo1: assert ((queue_cnt < 3'd2) || (tag_i1 == startCount + 8'd1));
    a_tag_fifo2: assert ((queue_cnt < 3'd3) || (tag_i2 == startCount + 8'd2));
    a_tag_fifo3: assert ((queue_cnt < 3'd4) || (tag_i3 == startCount + 8'd3));

    // FAB-10 — 배압 위반 사이클에 본체 직행이 없다 (pop 은 별건 — 위반과
    // 무관하게 큐가 본체로 흐르는 정상 경로).
    a_fab10_no_start: assert (!(bpViolation && !pop) || !body_1_io_start);

    // 본체 입력 정합 — 본체에 닿는 값의 원천은 둘뿐이다.
    a_body_req_direct: assert (!startDirect || (body_1_io_req == io_req_payload));
    a_body_req_pop:    assert (!pop || (body_1_io_req == queueHead));
  end

  // ── 1사이클 시제 단언 ($past — reset 인접 2사이클 제외) ─────────────
  always @(posedge clk) if (f_past_valid && !reset && !$past(reset)) begin
    // backpressure — ready 무시 push 는 다음 에지에 sticky fault 로 선다.
    // (해제와 동시 발화면 발화가 이긴다 — StickyFault 계약. RTL 은 clear
    //  후 set 순서의 마지막-대입 우선이라 같은 문면이다.)
    a_bp_fault_set: assert (!$past(bpViolation) || io_faultBpViolation);
    // backpressure — sticky: 명시적 해제 외엔 내려가지 않는다.
    a_bp_fault_sticky: assert (!$past(io_faultBpViolation && !io_faultClear) || io_faultBpViolation);

    // FAB-10 — 위반 사이클은 보류 자원에 쓰지 않는다: 기입 포인터 부동,
    // 기입 위치 슬롯 내용 부동, 계수는 pop 유출분만 반영.
    a_fab10_wrptr_hold:     assert (!$past(bpViolation) || (queue_wrPtr == $past(queue_wrPtr)));
    a_fab10_slot_untouched: assert (!$past(bpViolation) || (slot_wr == $past(slot_wr)));
    a_fab10_cnt:            assert (!$past(bpViolation) ||
                                    (queue_cnt == $past(queue_cnt) - {2'd0, $past(pop)}));
  end

  // ── 도달성 증인 (cover 태스크 전용 — 단언의 공허 방지) ──────────────
  always @(posedge clk) if (!reset) begin
    c_direct:  cover (startDirect);
    c_queued:  cover (pushQ);
    c_pop:     cover (pop);
    c_full:    cover (queue_cnt == 3'd4);
    c_bp:      cover (bpViolation);
    c_fault:   cover (io_faultBpViolation);
    c_ovwin:   cover (!queueEmpty && !body_1_io_busy && io_req_valid); // 추월 유혹 창
  end

endmodule

// 형식 검증 톱 — 대상 + props 결선. 내부 신호 포트는 sby [script] 의
// `expose SharedUnit/w:...` 가 만든다 (파일 머리의 부착 방식 주석 참조).
module SharedUnit_formal (
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
  wire [2:0]  io_occupancy;
  wire        body_1_io_busy, body_1_io_start;
  wire [15:0] body_1_io_req;
  wire [15:0] queue_slots_0, queue_slots_1, queue_slots_2, queue_slots_3;
  wire [1:0]  queue_rdPtr, queue_wrPtr;
  wire [2:0]  queue_cnt;
  wire        queueEmpty, queueRoom, acceptDirect, acceptQueue, bpViolation;
  wire        when_SharedUnit_l192;

  SharedUnit dut (
    .clk(clk), .reset(reset),
    .io_req_valid(io_req_valid), .io_req_payload(io_req_payload),
    .io_req_ready(io_req_ready),
    .io_rsp_valid(io_rsp_valid), .io_rsp_payload(io_rsp_payload),
    .io_faultBpViolation(io_faultBpViolation), .io_faultClear(io_faultClear),
    .io_occupancy(io_occupancy),
    // ── expose 로 올린 내부 관측 포트 ──
    .body_1_io_busy(body_1_io_busy), .body_1_io_start(body_1_io_start),
    .body_1_io_req(body_1_io_req),
    .queue_slots_0(queue_slots_0), .queue_slots_1(queue_slots_1),
    .queue_slots_2(queue_slots_2), .queue_slots_3(queue_slots_3),
    .queue_rdPtr(queue_rdPtr), .queue_wrPtr(queue_wrPtr), .queue_cnt(queue_cnt),
    .queueEmpty(queueEmpty), .queueRoom(queueRoom),
    .acceptDirect(acceptDirect), .acceptQueue(acceptQueue),
    .bpViolation(bpViolation),
    .when_SharedUnit_l192(when_SharedUnit_l192)
  );

  SharedUnit_props u_SharedUnit_props (
    .clk(clk), .reset(reset),
    .io_req_valid(io_req_valid), .io_req_payload(io_req_payload),
    .io_req_ready(io_req_ready),
    .io_faultBpViolation(io_faultBpViolation), .io_faultClear(io_faultClear),
    .body_1_io_busy(body_1_io_busy), .body_1_io_start(body_1_io_start),
    .body_1_io_req(body_1_io_req),
    .queue_slots_0(queue_slots_0), .queue_slots_1(queue_slots_1),
    .queue_slots_2(queue_slots_2), .queue_slots_3(queue_slots_3),
    .queue_rdPtr(queue_rdPtr), .queue_wrPtr(queue_wrPtr), .queue_cnt(queue_cnt),
    .queueEmpty(queueEmpty), .queueRoom(queueRoom),
    .acceptDirect(acceptDirect), .acceptQueue(acceptQueue),
    .bpViolation(bpViolation),
    .when_SharedUnit_l192(when_SharedUnit_l192)
  );
endmodule

`default_nettype wire
