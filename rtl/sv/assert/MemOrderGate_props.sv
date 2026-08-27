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

  // ── cover 증인 (cover 태스크에서만 컴파일) ───────────────────────────────
  //
  // 왜 있는가. 위 단언 24개 중 t_rise_* 넷은 문면 그대로 전건 붙은 함의
  // (`!(상승) || $past(complete)`)이고, 나머지 등식 스무 개는 *전건을 논리합
  // 안에 숨긴다*: g_open_eq_i 하나가 「지목 선행 k 가 미완」 세 항의 논리합을
  // 통째로 접고, g_fire_eq_* 와 g_payload_* 는 **gateOpen 이 영영 1 인 세계**
  // 에서도 그대로 참이다. 그런 세계에서 이 태스크의 앵커 일곱은 「순서 의존을
  // 재는 증명」이 아니라 「순서 의존이 걸리지 않는 기계에 대한 참인 항등식」
  // 이고, token_gate 의 「선행 미완이면 발화 억제」는 한 번도 측정되지 않는다.
  // 단언만으로는 「참이라서 통과」와 「전제가 도달 불가능해서 통과」가 구분되지
  // 않는다 — 그 구별을 만드는 것이 아래 증인이다.
  //
  // 앞선 두 게이트가 이 결을 못 잡는 이유(중요): 셀 수는 24 그대로 세어지고,
  // 항진 검사(연결된 `\A` 가 상수인가)도 통과한다 — gateOpen 은 자유 입력
  // cfgPreds 의 함수라 상수로 접히지 않기 때문이다. 셀 수 · A 상수성 · 증인
  // 도달, 셋이 각각 다른 공허를 닫는다.
  //
  // cover 태스크 전용 컴파일은 HiuMask·DecodeWalk 선례를 따른다 — prove/bmc
  // 모델에는 단언만 들어 태스크별 셀 수가 정확히 대조된다.
`ifdef MEMORDERGATE_COVER
  // 지목 선행 k 가 *미완*이라는 사실 — predIdx 표(파일 머리) 그대로.
  wire f_miss_0_0 = io_cfgPreds_0[0] && !io_token[1];
  wire f_miss_0_1 = io_cfgPreds_0[1] && !io_token[2];
  wire f_miss_0_2 = io_cfgPreds_0[2] && !io_token[3];
  wire f_miss_1_0 = io_cfgPreds_1[0] && !io_token[0];
  wire f_miss_1_1 = io_cfgPreds_1[1] && !io_token[2];
  wire f_miss_1_2 = io_cfgPreds_1[2] && !io_token[3];
  wire f_miss_2_0 = io_cfgPreds_2[0] && !io_token[0];
  wire f_miss_2_1 = io_cfgPreds_2[1] && !io_token[1];
  wire f_miss_2_2 = io_cfgPreds_2[2] && !io_token[3];
  wire f_miss_3_0 = io_cfgPreds_3[0] && !io_token[0];
  wire f_miss_3_1 = io_cfgPreds_3[1] && !io_token[1];
  wire f_miss_3_2 = io_cfgPreds_3[2] && !io_token[2];

  // 그 미완이 게이트를 닫은 **단독** 원인 — g_open_eq_i 가 접은 세 항 중
  // 정확히 하나만 살아 있는 궤적. 어느 항이 죽어 있어도 등식은 참이므로,
  // 항마다 단독 원인 증인을 요구하는 것이 그 결을 닫는 유일한 수단이다.
  wire f_only_0_0 = f_miss_0_0 && !f_miss_0_1 && !f_miss_0_2;
  wire f_only_0_1 = f_miss_0_1 && !f_miss_0_0 && !f_miss_0_2;
  wire f_only_0_2 = f_miss_0_2 && !f_miss_0_0 && !f_miss_0_1;
  wire f_only_1_0 = f_miss_1_0 && !f_miss_1_1 && !f_miss_1_2;
  wire f_only_1_1 = f_miss_1_1 && !f_miss_1_0 && !f_miss_1_2;
  wire f_only_1_2 = f_miss_1_2 && !f_miss_1_0 && !f_miss_1_1;
  wire f_only_2_0 = f_miss_2_0 && !f_miss_2_1 && !f_miss_2_2;
  wire f_only_2_1 = f_miss_2_1 && !f_miss_2_0 && !f_miss_2_2;
  wire f_only_2_2 = f_miss_2_2 && !f_miss_2_0 && !f_miss_2_1;
  wire f_only_3_0 = f_miss_3_0 && !f_miss_3_1 && !f_miss_3_2;
  wire f_only_3_1 = f_miss_3_1 && !f_miss_3_0 && !f_miss_3_2;
  wire f_only_3_2 = f_miss_3_2 && !f_miss_3_0 && !f_miss_3_1;

  // 「순서 의존이 실제로 걸린다」의 문면: 상류가 내밀고(up.valid) 하류가 받을
  // 준비가 됐는데(down.ready) 게이트가 닫혀 **아무것도 지나지 않는다**.
  // down.ready 를 함께 요구하는 것이 요점 — 그래야 억제의 원인이 배압이 아니라
  // 게이트임이 궤적 자체로 갈린다 (inflight_not_gating 의 짝).
  wire f_block_0 = io_up_0_valid && io_down_0_ready && !io_gateOpen[0]
                && !io_down_0_valid && !io_up_0_ready;
  wire f_block_1 = io_up_1_valid && io_down_1_ready && !io_gateOpen[1]
                && !io_down_1_valid && !io_up_1_ready;
  wire f_block_2 = io_up_2_valid && io_down_2_ready && !io_gateOpen[2]
                && !io_down_2_valid && !io_up_2_ready;
  wire f_block_3 = io_up_3_valid && io_down_3_ready && !io_gateOpen[3]
                && !io_down_3_valid && !io_up_3_ready;

  // 발화 면 — 게이트가 열려 실제로 handshake 가 완성된다.
  wire f_fire_0 = io_up_0_valid && io_down_0_ready && io_gateOpen[0]
               && io_down_0_valid && io_up_0_ready;
  wire f_fire_1 = io_up_1_valid && io_down_1_ready && io_gateOpen[1]
               && io_down_1_valid && io_up_1_ready;
  wire f_fire_2 = io_up_2_valid && io_down_2_ready && io_gateOpen[2]
               && io_down_2_valid && io_up_2_ready;
  wire f_fire_3 = io_up_3_valid && io_down_3_ready && io_gateOpen[3]
               && io_down_3_valid && io_up_3_ready;

  // ── M1..M12 — g_open_eq_0..3 이 접은 12개 선행 항의 단독 원인 ────────────
  // 각 줄의 `←` 오른쪽이 **그 증인이 살리는 대상**이다: `<Model>.<guard>` 는
  // 이 태스크의 `# PROVES:` 앵커, 소문자 식별자는 이 하네스의 단언 라벨.
  // 줄번호로 매지 않는다. scripts/lint_witness_map.py 가 참조 실재성만 재고
  // 「그 궤적이 정말 그 전건을 세우는가」는 재지 못한다.
  //
  // 대응 M(3i+k+1) ↔ g_open_eq_<i> 우변의 (io_cfgPreds_<i>[<k>] && !io_token[·])
  // 항. 같은 증인이 g_fire_eq_<i>v · g_fire_eq_<i>r 의 **억제면**도 함께
  // 재운다 (down.valid=0 · up.ready=0 을 궤적 조건에 넣었다).
  // M1  ← MemOrder.token_gate · MemOrder.gate_matches_dep · g_open_eq_0 · g_fire_eq_0v · g_fire_eq_0r
  // M2  ← MemOrder.token_gate · MemOrder.gate_matches_dep · g_open_eq_0 · g_fire_eq_0v · g_fire_eq_0r
  // M3  ← MemOrder.token_gate · MemOrder.gate_matches_dep · g_open_eq_0 · g_fire_eq_0v · g_fire_eq_0r
  // M4  ← MemOrder.token_gate · MemOrder.gate_matches_dep · g_open_eq_1 · g_fire_eq_1v · g_fire_eq_1r
  // M5  ← MemOrder.token_gate · MemOrder.gate_matches_dep · g_open_eq_1 · g_fire_eq_1v · g_fire_eq_1r
  // M6  ← MemOrder.token_gate · MemOrder.gate_matches_dep · g_open_eq_1 · g_fire_eq_1v · g_fire_eq_1r
  // M7  ← MemOrder.token_gate · MemOrder.gate_matches_dep · g_open_eq_2 · g_fire_eq_2v · g_fire_eq_2r
  // M8  ← MemOrder.token_gate · MemOrder.gate_matches_dep · g_open_eq_2 · g_fire_eq_2v · g_fire_eq_2r
  // M9  ← MemOrder.token_gate · MemOrder.gate_matches_dep · g_open_eq_2 · g_fire_eq_2v · g_fire_eq_2r
  // M10 ← MemOrder.token_gate · MemOrder.gate_matches_dep · g_open_eq_3 · g_fire_eq_3v · g_fire_eq_3r
  // M11 ← MemOrder.token_gate · MemOrder.gate_matches_dep · g_open_eq_3 · g_fire_eq_3v · g_fire_eq_3r
  // M12 ← MemOrder.token_gate · MemOrder.gate_matches_dep · g_open_eq_3 · g_fire_eq_3v · g_fire_eq_3r
  always @(posedge clk) if (f_step) m1_block_0_0: cover (f_block_0 && f_only_0_0);
  always @(posedge clk) if (f_step) m2_block_0_1: cover (f_block_0 && f_only_0_1);
  always @(posedge clk) if (f_step) m3_block_0_2: cover (f_block_0 && f_only_0_2);
  always @(posedge clk) if (f_step) m4_block_1_0: cover (f_block_1 && f_only_1_0);
  always @(posedge clk) if (f_step) m5_block_1_1: cover (f_block_1 && f_only_1_1);
  always @(posedge clk) if (f_step) m6_block_1_2: cover (f_block_1 && f_only_1_2);
  always @(posedge clk) if (f_step) m7_block_2_0: cover (f_block_2 && f_only_2_0);
  always @(posedge clk) if (f_step) m8_block_2_1: cover (f_block_2 && f_only_2_1);
  always @(posedge clk) if (f_step) m9_block_2_2: cover (f_block_2 && f_only_2_2);
  always @(posedge clk) if (f_step) m10_block_3_0: cover (f_block_3 && f_only_3_0);
  always @(posedge clk) if (f_step) m11_block_3_1: cover (f_block_3 && f_only_3_1);
  always @(posedge clk) if (f_step) m12_block_3_2: cover (f_block_3 && f_only_3_2);

  // ── M13 — g_open_eq_0 의 반대 방향(모든 선행 완료 → 열림)이 닿는다 ──────
  // M13 ← MemOrder.token_gate · g_open_eq_0 · g_fire_eq_0v
  //       세 선행 전부를 지목한 채 셋 다 완료된 궤적. 이것이 없으면 등식의
  //       왼쪽 방향만 재어진 셈이다 (닫힘만 관측되는 세계).
  always @(posedge clk) if (f_step)
    m13_all_preds_done: cover (f_fire_0 && (io_cfgPreds_0 == 3'b111)
           && io_token[1] && io_token[2] && io_token[3]);
  // ── M14 — 과잉 게이팅 부재 ───────────────────────────────────────────────
  // M14 ← MemOrder.gate_matches_dep · g_open_eq_1
  //       무의존 슬롯은 **타 슬롯 토큰이 전무해도** 연다. 기계가 cfgPreds 에
  //       없는 원소를 더하지 않는다는 주장의 활성면.
  always @(posedge clk) if (f_step)
    m14_no_overgating: cover (f_fire_1 && (io_cfgPreds_1 == 3'b000) && (io_token == 4'b0000));

  // ── M15..M16 — MemOrder.inflight_not_gating: 배압은 게이팅이 아니다 ──────
  // M15 ← MemOrder.inflight_not_gating · g_fire_eq_2r
  //       게이트는 열려 있는데 하류 배압만으로 up.ready 가 죽는다 —
  //       down.valid 는 살아 있다. g_fire_eq_2r 의 down.ready 항이 실제로
  //       구분력을 갖는다.
  always @(posedge clk) if (f_step)
    m15_backpressure_only: cover (io_gateOpen[2] && io_up_2_valid && !io_down_2_ready
           && !io_up_2_ready && io_down_2_valid);
  // M16 ← MemOrder.inflight_not_gating · g_fire_eq_1r
  //       슬롯 0 이 발화 중인데 슬롯 1 은 배압으로 정체 — 타 슬롯 handshake
  //       가 서로의 콘에 없다는 주장(등식의 콘 폐쇄)의 활성면.
  always @(posedge clk) if (f_step)
    m16_cross_slot_stall: cover (f_fire_0 && io_up_1_valid && io_gateOpen[1] && !io_down_1_ready
           && !io_up_1_ready);

  // ── M17..M18 — g_payload_* / addr·wave_not_gating 의 활성면 ──────────────
  // M17 ← MemOrder.addr_not_gating · MemOrder.wave_not_gating · g_payload_0
  //       비0 payload 가 실제로 handshake 를 지난다 (「payload 가 늘 0 인
  //       세계」에서 전량 통과 등식은 자명하다).
  always @(posedge clk) if (f_step)
    m17_payload_nonzero: cover (io_down_0_valid && io_down_0_ready && (io_down_0_payload != 16'h0));
  // M18 ← MemOrder.addr_not_gating · MemOrder.wave_not_gating · g_payload_0 ·
  //       g_payload_1 — 두 슬롯이 **서로 다른** 비0 payload 로 동시 발화:
  //       슬롯 간 payload 혼선이 없다는 것이 관측 가능한 궤적 위에서 재어진다.
  always @(posedge clk) if (f_step)
    m18_payload_distinct: cover (io_down_0_valid && io_down_1_valid
           && (io_down_0_payload != io_down_1_payload)
           && (io_down_0_payload != 16'h0) && (io_down_1_payload != 16'h0));

  // ── M19..M22 — 토큰 상태 함수 t_next_eq_* 의 네 국면 ─────────────────────
  // M19 ← MemOrder.token_on_complete · t_rise_0 · t_next_eq_0
  //       상승 — t_rise_0 의 전건 도달성. 이 증인이 없으면 t_rise_* 넷은
  //       「토큰이 영영 서지 않는 기계」 위에서 공허하게 참이다.
  always @(posedge clk) if (f_step)
    m19_token_rise: cover (io_token[0] && !$past(io_token[0]));
  // M20 ← MemOrder.token_on_complete · t_next_eq_1
  //       epochClear 하강 — 우변의 `&& !$past(io_epochClear)` 항이 실제로
  //       0 을 만든다. 없으면 소거 경로가 미측정이다.
  always @(posedge clk) if (f_step)
    m20_epoch_clear: cover (!io_token[1] && $past(io_token[1]) && $past(io_epochClear));
  // M21 ← MemOrder.token_on_complete · t_next_eq_2
  //       유지 — complete 없이 epoch 안에서 토큰이 남는다 (우변의
  //       `$past(io_token[2]) && !$past(epochClear)` 항).
  always @(posedge clk) if (f_step)
    m21_token_hold: cover (io_token[2] && $past(io_token[2]) && !$past(io_complete[2])
           && !$past(io_epochClear));
  // M22 ← MemOrder.token_on_complete · t_next_eq_3 · t_rise_3
  //       set 우선 — 소거와 완료가 같은 사이클에 오면 토큰은 선다 (RTL 기술
  //       순서 「epochClear 소거 후 complete set」의 관측면).
  always @(posedge clk) if (f_step)
    m22_set_beats_clear: cover (io_token[3] && $past(io_epochClear) && $past(io_complete[3]));

  // ── M23..M24 — MemOrder.complete_not_ordered 의 활성면 ───────────────────
  // M23 ← MemOrder.complete_not_ordered · t_next_eq_0 · t_rise_0
  //       **역순 완료 수락** — 슬롯 0 이 슬롯 3 을 선행으로 지목했고 그 선행이
  //      아직 미완이라 게이트가 닫혀 있는데도, 슬롯 0 자신의 완료는 그대로
  //      접수된다. 완료 경로에 순서 비교가 없다는 주장의 유일한 관측 형태.
  always @(posedge clk) if (f_step)
    m23_out_of_order_complete: cover (io_cfgPreds_0[2] && !io_token[3] && !io_gateOpen[0]
           && io_token[0] && !$past(io_token[0]));
  // M24 ← MemOrder.complete_not_ordered · t_next_eq_0 · t_next_eq_1 ·
  //       t_next_eq_2 · t_next_eq_3 — **동시 완료**: 네 슬롯이 한 사이클에
  //       함께 선다 (슬롯별 독립).
  always @(posedge clk) if (f_step)
    m24_simultaneous_complete: cover ((io_token == 4'b1111) && ($past(io_token) == 4'b0000));
`endif // MEMORDERGATE_COVER

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
