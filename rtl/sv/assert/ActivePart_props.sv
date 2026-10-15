// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// ActivePart 후-formal 하네스 — `0xE14` XLATE_ACTIVE_PART 결속 워드의 수락 판정 (A, D) 단독 측정
// (3.10 v1.0 묶음 RTL 파도 W4, 2026-10-15 · 설계 결정 DP-4 α · DP-6). 태스크:
// rtl/formal/sby/ActivePart/activepart.sby (머리가 앵커 · 엔진 · 깊이 · 역-변이 표를 소유한다).
// 선-formal 계약: rtl/formal/tla/ActivePart.tla — 가드 12 · 고정 속성 여섯(Inv_ObsIsSpec ·
// Inv_WorkUnderBound · Prop_NoStaleWorkAfterSwitch · Prop_LoudOnlySpec · Prop_A0D1IsValueReject ·
// Prop_StallOnlyPend).
//
// ## 왜 이 하네스가 따로 있는가 (DP-6 — AbortStaging · CapStatusWord 선례)
//
// 조립 태스크(Wt64Top/assembly.sby)는 actp 를 절단하지 않고 버스 이력 그림자(f_bound · f_A · f_D)로
// 끝-끝을 재지만, 그 오라클은 D 의 원천(cq.drainAllZero)이 절단 핀이고 rdata 가 다음 사이클 mux 라
// 「판정 사이클의 조합 출력(badWrite · stall)」 을 사이클 단위로 재기 어렵다. 이 하네스는 컴포넌트
// 포트 여덟만으로 가드 열(둘은 Top 결선 — 아래)을 사이클 정확 등식으로 앵커한다.
//
// ## 부착 — 래퍼 인스턴스 (bind 없음)
//
// ActivePart_check 가 ActivePart 를 직접 인스턴스한다 (XlateDoor_check 선례). 모듈은 Wt64Top.sv 안에
// 있다 — `prep -top ActivePart_check` 가 나머지 모듈을 지운다.
//
// ## 포트 계약 (이 하네스의 환경 — 정본 · 모델 · W4-5 포트 목록에서)
//
//   io_wr        Top 의 `0xE14` *정렬* 쓰기 스트로브 (xlateArea 쓰기 스트로브 ∧ isAct ∧ mmioAligned —
//                unaligned_outside 의 Top 절반). 버스 ready 로 게이트되지 *않는다* — 버스 수락은 이 유닛의
//                ready 하강(io_stallMmio)과의 논리곱이다: acc = io_wr ∧ ¬io_stallMmio. 정지 중의 io_wr 은
//                버스가 잡고 있는 접근이고 수락이 아니다 (MmioPage.effect_on_accept — 효과도 거절도 없다).
//   io_wdata     쓰기 데이터 — 자유.
//   io_drainNow  cq.drainAllZero (`0x37C` 와 같은 식 — descriptor.sby). 매 사이클 자유: 이 하네스는
//                D 원천의 시점 · 완전성을 재지 않는다 (모델 닫힌 목록 3 — (a) descriptor.sby · (b) HiuMask/occ.sby).
//
// ## 오라클 — 정본 · 모델 · 포트로만 짓는다 (DUT 레지스터 이름을 한 번도 읽지 않는다)
//
// 그림자 f_pend · f_pv · f_pok(모델 pend) · f_bound · f_A · f_D(모델 bound · regA · regD — 판정이 끝난
// 상태의 장치 레지스터 = 정본 유령, Inv_ObsIsSpec)를 포트 사건으로만 갱신한다:
//   · 수락(acc)된 기입은 값 검사와 무관하게 판정 사이클을 하나 연다 — f_pend ← acc (α · ad_every_accept 의
//     「버스 수락된 `0xE14` 기입은 어느 것이든」).
//   · 판정 사이클(f_pend)에: apply = f_pok ∧ (f_pv = f_bound ∨ drainNow) · A ← apply · D ← drainNow ·
//     apply 이면 결속 ← f_pv. 판정 사이클의 drainNow 가 곧 「수락 에지 직후의 상태」다 (DP-4 α).
//   · 값 검사 f_valOk = [7:0] < F_PARTS ∧ [31:10] = 0 — [9:8] 은 어느 식에도 없다 (ro_field_ignored).
//     F_PARTS = 4 는 정본 참조 형상(아래 「정본」 절의 참조 구현 형상 인용)에서 독립 유도한다 — RTL cfg 를 베끼지 않는다.
//
// 정본 (좌표 뒤 「」 는 그 줄의 축자):
//   e-defined.typ:329 「`[8]` APPLIED (A — 마지막 기입이 적용됐는가)」
//   e-defined.typ:329 「`[9]` DRAINED (D — 마지막 기입 수락 에지의 드레인 판정)」
//   e-defined.typ:329 「`[9:8]` *쓰기 무시* (RW 워드 안의 RO 필드」
//   e-defined.typ:329 「`[31:10]` 예약 = 0 (엄격)」
//   e-defined.typ:332 「*값 검사가 먼저다.*」
//   e-defined.typ:332 「D 는 값 검사와 무관하게 늘 *그 기입 수락 에지 직후의 상태*(같은 사이클의 요청 접수 포함)에 대해 표집한다」
//   e-defined.typ:332 「버스 수락된 `0xE14` 기입은 어느 것이든 A · D 를 갱신한다」
//   e-defined.typ:332 「어떤 사유든(값 검사 · 드레인 판정) 거절이면 A = 0 이다」
//   e-defined.typ:332 「A = 1 · 무동작 · *fault 없음* — D = 0 이 보고된다」
//   e-defined.typ:765 「참조 구현의 형상은 *파티션 4 × 항목 16 = 64 항목 · 직접 사상 · 항목 8 B* 이며」
//
// 문체: yosys 개방판은 SVA 시퀀스를 받지 않으므로 즉시 단언(always + $past).
module ActivePart_check (
  input logic        clk,
  input logic        reset,
  input logic        io_wr,
  input logic [31:0] io_wdata,
  input logic        io_drainNow
);
  localparam [7:0] F_PARTS = 8'd4;   // 정본 참조 형상의 실재 파티션 수 (머리 「정본」 절의 참조 형상 인용)

  // ENV: 기계는 reset 에서 시작한다. 유일한 assume 이다 — 입력 셋은 매 사이클 자유.
  initial assume (reset);

  logic f_past_valid = 1'b0;
  logic f_past_reset = 1'b1;
  logic f_past_reset2 = 1'b1;
  always @(posedge clk) begin
    f_past_valid <= 1'b1;
    f_past_reset <= reset;
    f_past_reset2 <= f_past_reset;
  end
  wire f_live = f_past_valid && !reset;
  wire f_step = f_past_valid && !reset && !f_past_reset;
  // 두 사이클 전을 보는 증인(W8 · W9 · W11)의 전건 — 그 사이클도 reset 밖이어야 한다. reset 중의 io_wr 은 포트상
  // acc 로 보이지만(유닛 레지스터는 비동기 reset 에 묶여 있다) 수락이 아니다: 이 전건 없이는 W9 가 reset 사이클의
  // 조합 거절선으로, W11 이 reset 직후 기입의 D 로 도달해 ALIAS_SAME · D_EARLY 변이 아래에서도 살았다 (W4H 실측).
  wire f_step2 = f_step && !f_past_reset2;

  wire [1:0]  ap_activePart;
  wire [31:0] ap_actWord;
  wire        ap_badWrite, ap_stallMmio, ap_stallReq;

  ActivePart actp (
    .io_wr(io_wr), .io_wdata(io_wdata), .io_drainNow(io_drainNow),
    .io_activePart(ap_activePart), .io_actWord(ap_actWord), .io_badWrite(ap_badWrite),
    .io_stallMmio(ap_stallMmio), .io_stallReq(ap_stallReq),
    .clk(clk), .reset(reset)
  );

  // ── 그림자 (모델 pend · bound · regA · regD) ───────────────────────────────
  wire        acc     = io_wr && !ap_stallMmio;                                  // 버스 수락
  wire        f_valOk = (io_wdata[7:0] < F_PARTS) && (io_wdata[31:10] == 22'd0); // value_first · rsv_strict
  logic       f_pend  = 1'b0;
  logic       f_pok   = 1'b0;
  logic [7:0] f_pv    = 8'd0;
  logic [7:0] f_bound = 8'd0;
  logic       f_A     = 1'b0;
  logic       f_D     = 1'b0;
  wire        f_same  = (f_pv == f_bound);                                       // 8b 비교 — 절단 별칭 없음
  wire        f_apply = f_pend && f_pok && (f_same || io_drainNow);
  wire        f_dRej  = f_pend && f_pok && !f_same && !io_drainNow;              // 드레인 판정 거절 (t+1)
  wire        f_vRej  = acc && !f_valOk;                                         // 값 검사 거절 (t)
  always @(posedge clk) begin
    if (reset) begin
      f_pend <= 1'b0; f_pok <= 1'b0; f_pv <= 8'd0;
      f_bound <= 8'd0; f_A <= 1'b0; f_D <= 1'b0;
    end else begin
      f_pend <= acc;
      if (acc) begin
        f_pv  <= io_wdata[7:0];
        f_pok <= f_valOk;
      end
      if (f_pend) begin
        f_A <= f_apply;
        f_D <= io_drainNow;
        if (f_apply) f_bound <= f_pv;
      end
    end
  end

`ifndef ACTIVEPART_COVER
  always @(*) if (f_live) begin
    // 읽기 워드 — 판정이 끝난 레지스터 = 정본 유령 (Inv_ObsIsSpec). 판정 사이클(f_pend)에는 판정 *전*
    // 값이다 — 그 사이클의 되읽기는 Top 이 정지로 막는다 (pend_stalls_mmio · assembly a_ready_act).
    p_word_bound: assert (ap_actWord[7:0] == f_bound);
    p_word_a:     assert (ap_actWord[8] == f_A);         // ad_every_accept · drain_gates_switch · same_value_noop · value_first
    p_word_d:     assert (ap_actWord[9] == f_D);         // d_includes_same_cycle · ad_every_accept (D 절반)
    p_word_rsv:   assert (ap_actWord[31:10] == 22'd0);   // 읽기 [31:10] = 0 (모델 닫힌 목록 10 의 유닛 절반)
    // req_part_from_bound (유닛 절반) — 요청 파티션 포트 = 결속. Top 의 hiu.io.req.part 결선은 assembly a_hiu_part.
    p_part:       assert (ap_activePart == f_bound[1:0]);
    // pend_stalls_mmio · pend_stalls_req — 정지 = 판정 사이클 그 자체 (Prop_StallOnlyPend: 늘이지도 래치하지도 않는다)
    p_stall_mmio: assert (ap_stallMmio == f_pend);
    p_stall_req:  assert (ap_stallReq == f_pend);
    // reject_loud — 거절선 = 값 거절(수락 사이클 t) ∨ 드레인 거절(판정 사이클 t+1). 등식이라 조용한 거절 ·
    // 같은 값 D=0 의 발화(same_value_noop) · 정지 중 기입의 발화(수락 전 효과)가 전부 여기서 깨진다.
    p_bad_iff:    assert (ap_badWrite == (f_vRej || f_dRej));
  end
`endif

`ifdef ACTIVEPART_COVER
  // 증인 — (A, D) 표 네 칸 × 사유 · 같은 사이클 · 절단 별칭 · 정지 중 기입. 판정 사이클 다음의 워드로 본다.
  // W1 ← ActivePart.drain_gates_switch · ActivePart.req_part_from_bound · p_word_a · p_part — 다른 값 ∧ D=1: A=1 · D=1 · 결속 교체
  always @(posedge clk) if (f_step) w1_switch: cover ($past(f_pend && f_pok && !f_same && io_drainNow) && ap_actWord[9:8] == 2'b11 && ap_activePart != $past(ap_activePart));
  // W2 ← ActivePart.drain_gates_switch · ActivePart.reject_loud · p_bad_iff · p_word_a — 다른 값 ∧ D=0: 판정 사이클에 거절선 · A=0 · D=0 · 결속 불변
  always @(posedge clk) if (f_step) w2_drain_rej: cover ($past(f_dRej && ap_badWrite) && ap_actWord[9:8] == 2'b00 && ap_activePart == $past(ap_activePart));
  // W3 ← ActivePart.same_value_noop · p_word_a — 같은 값 ∧ D=1: A=1 · D=1
  always @(posedge clk) if (f_step) w3_same_d1: cover ($past(f_pend && f_pok && f_same && io_drainNow) && ap_actWord[9:8] == 2'b11);
  // W4 ← ActivePart.same_value_noop · ActivePart.reject_loud · p_bad_iff · p_word_d — 같은 값 ∧ D=0: 거절선 없이 A=1 · D=0
  always @(posedge clk) if (f_step) w4_same_d0: cover ($past(f_pend && f_pok && f_same && !io_drainNow && !ap_badWrite) && ap_actWord[9:8] == 2'b01);
  // W5 ← ActivePart.ad_every_accept · ActivePart.value_first · p_word_a · p_word_d — 값 거절 ∧ D=1: A=0 · D=1 (Prop_A0D1IsValueReject — 앞 기입이 A=1 을 남긴 위에서)
  always @(posedge clk) if (f_step) w5_vrej_d1: cover ($past(f_pend && !f_pok && io_drainNow && f_A) && ap_actWord[9:8] == 2'b10);
  // W6 ← ActivePart.ad_every_accept · ActivePart.d_includes_same_cycle · p_word_d — 값 거절 ∧ D=0: 앞 기입의 D=1 이 0 으로 갱신된다
  always @(posedge clk) if (f_step) w6_vrej_d0: cover ($past(f_pend && !f_pok && !io_drainNow && f_D) && ap_actWord[9:8] == 2'b00);
  // W7 ← ActivePart.rsv_strict · ActivePart.reject_loud · p_bad_iff — 실재 파티션 값 · [31:10] 비0 의 수락 기입이 수락 사이클에 거절선
  always @(posedge clk) if (f_step) w7_rsv: cover (acc && io_wdata[7:0] < F_PARTS && io_wdata[31:10] != 22'd0 && ap_badWrite);
  // W8 ← ActivePart.ro_field_ignored · p_bad_iff · p_word_bound — [9:8] = 11 인 다른 값 기입이 D=1 에 적용된다 (거절 없음)
  always @(posedge clk) if (f_step2) w8_ro: cover ($past(acc && io_wdata[9:8] == 2'b11 && io_wdata[7:0] != f_bound && f_valOk && !ap_badWrite, 2) && ap_actWord[8] && ap_actWord[7:0] == $past(io_wdata[7:0], 2));
  // W9 ← ActivePart.value_first · p_bad_iff · p_word_a — 절단 별칭: 없는 값의 하위 두 비트가 현재 결속과 같아도 거절 (같은 값 무동작이 아니다)
  always @(posedge clk) if (f_step2) w9_alias: cover ($past(acc && io_wdata[7:0] >= F_PARTS && io_wdata[31:10] == 22'd0 && io_wdata[1:0] == f_bound[1:0] && ap_badWrite, 2) && !ap_actWord[8]);
  // W10 ← ActivePart.pend_stalls_mmio · p_stall_mmio · p_bad_iff — 판정 사이클의 기입은 잡히고(거절선 없음 — 없는 값이어도) 다음 사이클에 수락된다
  always @(posedge clk) if (f_step) w10_held: cover ($past(io_wr && ap_stallMmio && !ap_badWrite && io_wdata[7:0] >= F_PARTS) && acc && io_wdata[7:0] >= F_PARTS && ap_badWrite);
  // W11 ← ActivePart.d_includes_same_cycle · p_word_d — 수락 사이클 drainNow = 0 · 판정 사이클 = 1 이면 D = 1 (에지 *직후* 표집)
  always @(posedge clk) if (f_step2) w11_d_post: cover ($past(acc && !io_drainNow, 2) && $past(io_drainNow) && ap_actWord[9]);
  // W12 ← ActivePart.pend_stalls_req · p_stall_req — 요청 정지가 판정 사이클 하나로 끝나고 바로 다음 기입이 수락된다 (정지 펄스)
  always @(posedge clk) if (f_step) w12_pulse: cover ($past(ap_stallReq) && !ap_stallReq && acc);
`endif
endmodule
