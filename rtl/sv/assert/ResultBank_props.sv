// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// ResultBank 후-formal 하네스 (§6.3) — 소유 구간 [t, t+L] 의 GUARD-MAP CHECK
// 3줄을 구현된 회로(rtl/generated/ResultBank.sv — 커밋본, 재생성 금지)에 대해
// 재검사한다. 형상: slotCap = 16 · prodW = 4 · L(ownL) = 2 · dataW = 64.
// yosys+sby(smtbmc z3) 용 — $past 기반 즉시 단언.
//
// 부착 방식: expose + 래퍼 — yosys 0.66 이 bind 를 조용히 무시함을 실측
// (경위는 SharedUnit_props.sv 파일 머리 참조). props 모듈은 bind 가능한
// 형태 그대로이며, 아래 ResultBank_formal 래퍼가 결선을 맡는다.
//
// 가드 ↔ 단언 대응 (가드명 = rtl/spinal/src/main/scala/wt64/fabric/ResultBank.scala
// 의 GUARD-MAP 줄과 동일):
//   ResultBank.owner_check  : a_store_untouched (비소유·비기입 사이클에 store
//                             불변 — anyconst 슬롯 보편 검사) · a_write_lands
//                             (자격 기입은 무조건 성사 — 제3의 결과 부재) ·
//                             a_fault_loud · a_fault_sticky
//   ResultBank.acquire_free : g_slot[*] 블록의 acq_deny (소유 슬롯 요청은
//                             granted=False 명시 거절) · rise_grant (소유
//                             상승의 유일 경로는 grant) · grant_start (허가
//                             다음 사이클부터 소유·age=0·소유자 기록)
//   ResultBank.interval_end : g_slot[*] 블록의 age_le (나이 <= L 불변 — L+1
//                             상태의 구조적 부재, 「해제가 판정과 융합」의
//                             실물 검사) · release_at_L (age=L 사이클 말 해제 —
//                             그 사이클까지 소유이므로 [t, t+L] 양끝 포함) ·
//                             tick (진행 +1) · free_age0
//   (g_slot 내부 단언은 라벨 없음 — yosys 0.66 이 generate 루프 안의 단언
//    라벨을 유일화하지 못해 「cell with the same name」 오류를 냄을 실측.
//    각 단언 위 주석의 이름이 위 대응의 이름이다.)
//   관측 정합                : a_read_owned — 읽기 포트의 owned 는 소유 장부
//                             그대로다
//
// assume 목록 (전수):
//   as_reset_shape — reset 은 시각 0 에만 활성, 이후 비활성.
//     근거: 정본 §1.5 (초기 상태 계약) — 선-formal 모델 Init 이 reset 직후
//     상태에 대응한다는 ENV 계약. 모델에 리셋 재진입 시간축이 없다.
//   그 외 입력(acquire/write/read/faultClear)은 전부 자유 — 비소유 기입·소유
//   슬롯 재획득 시도 자체가 검사 대상이므로 어떤 프로토콜도 assume 하지 않는다.

`default_nettype none

module ResultBank_props (
    input wire        clk,
    input wire        reset,
    input wire        io_acquire_valid,
    input wire [3:0]  io_acquire_slot,
    input wire [3:0]  io_acquire_prod,
    input wire        io_acquire_granted,
    input wire        io_write_valid,
    input wire [3:0]  io_write_slot,
    input wire [3:0]  io_write_prod,
    input wire [63:0] io_write_data,
    input wire [3:0]  io_read_slot,
    input wire [63:0] io_read_data,
    input wire        io_read_owned,
    input wire        io_fault,
    input wire        io_faultClear,
    input wire        acqFree,
    input wire        wrQualified,
    input wire        when_ResultBank_l163,   // 획득 허가 fire (valid && acqFree)
    input wire        when_ResultBank_l181,   // 자격 기입 fire (valid && wrQualified)
    input wire        ownerValid_0,  input wire ownerValid_1,  input wire ownerValid_2,  input wire ownerValid_3,
    input wire        ownerValid_4,  input wire ownerValid_5,  input wire ownerValid_6,  input wire ownerValid_7,
    input wire        ownerValid_8,  input wire ownerValid_9,  input wire ownerValid_10, input wire ownerValid_11,
    input wire        ownerValid_12, input wire ownerValid_13, input wire ownerValid_14, input wire ownerValid_15,
    input wire [3:0]  ownerId_0,  input wire [3:0] ownerId_1,  input wire [3:0] ownerId_2,  input wire [3:0] ownerId_3,
    input wire [3:0]  ownerId_4,  input wire [3:0] ownerId_5,  input wire [3:0] ownerId_6,  input wire [3:0] ownerId_7,
    input wire [3:0]  ownerId_8,  input wire [3:0] ownerId_9,  input wire [3:0] ownerId_10, input wire [3:0] ownerId_11,
    input wire [3:0]  ownerId_12, input wire [3:0] ownerId_13, input wire [3:0] ownerId_14, input wire [3:0] ownerId_15,
    input wire [1:0]  age_0,  input wire [1:0] age_1,  input wire [1:0] age_2,  input wire [1:0] age_3,
    input wire [1:0]  age_4,  input wire [1:0] age_5,  input wire [1:0] age_6,  input wire [1:0] age_7,
    input wire [1:0]  age_8,  input wire [1:0] age_9,  input wire [1:0] age_10, input wire [1:0] age_11,
    input wire [1:0]  age_12, input wire [1:0] age_13, input wire [1:0] age_14, input wire [1:0] age_15,
    input wire [63:0] store_0,  input wire [63:0] store_1,  input wire [63:0] store_2,  input wire [63:0] store_3,
    input wire [63:0] store_4,  input wire [63:0] store_5,  input wire [63:0] store_6,  input wire [63:0] store_7,
    input wire [63:0] store_8,  input wire [63:0] store_9,  input wire [63:0] store_10, input wire [63:0] store_11,
    input wire [63:0] store_12, input wire [63:0] store_13, input wire [63:0] store_14, input wire [63:0] store_15
);

  localparam [1:0] L = 2'd2;   // Wt64Config.ownL — 생성물의 age == 2'b10 판정과 일치

  // ── 시간 기준 · reset 형상 ──────────────────────────────────────────
  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;

  // as_reset_shape (근거는 파일 머리 assume 목록 참조)
  always @(*) as_reset_shape: assume (reset == !f_past_valid);

  // ── 슬롯 상태의 벡터 뷰 ─────────────────────────────────────────────
  wire [15:0] ovVec = {ownerValid_15, ownerValid_14, ownerValid_13, ownerValid_12,
                       ownerValid_11, ownerValid_10, ownerValid_9,  ownerValid_8,
                       ownerValid_7,  ownerValid_6,  ownerValid_5,  ownerValid_4,
                       ownerValid_3,  ownerValid_2,  ownerValid_1,  ownerValid_0};
  wire [31:0] ageVec = {age_15, age_14, age_13, age_12, age_11, age_10, age_9, age_8,
                        age_7,  age_6,  age_5,  age_4,  age_3,  age_2,  age_1, age_0};
  wire [63:0] oidVec = {ownerId_15, ownerId_14, ownerId_13, ownerId_12,
                        ownerId_11, ownerId_10, ownerId_9,  ownerId_8,
                        ownerId_7,  ownerId_6,  ownerId_5,  ownerId_4,
                        ownerId_3,  ownerId_2,  ownerId_1,  ownerId_0};
  wire [1023:0] storeVec = {store_15, store_14, store_13, store_12,
                            store_11, store_10, store_9,  store_8,
                            store_7,  store_6,  store_5,  store_4,
                            store_3,  store_2,  store_1,  store_0};

  // ── 슬롯별 단언 — acquire_free · interval_end ──────────────────────
  genvar gi;
  generate
    for (gi = 0; gi < 16; gi = gi + 1) begin : g_slot
      wire        s_own   = ovVec[gi];
      wire [1:0]  s_age   = ageVec[2*gi +: 2];
      wire [3:0]  s_oid   = oidVec[4*gi +: 4];
      wire        s_end   = s_own && (s_age == L);
      wire        s_grant = when_ResultBank_l163 && (io_acquire_slot == gi[3:0]);

      always @(posedge clk) if (!reset) begin
        // acquire_free — 소유 슬롯 요청은 명시적 거절(granted=False)을 받는다.
        assert (!(io_acquire_valid && (io_acquire_slot == gi[3:0]) && s_own)
                            || !io_acquire_granted);
        // interval_end — 나이는 L 을 넘는 상태를 표현하지 않는다 (해제가
        // 판정과 융합돼 age > L 이 구조적으로 생성 불가라는 근거의 실측).
        assert (!s_own || (s_age <= L));
        // interval_end 보조 불변 — 비소유 슬롯의 나이는 0 이다 (k-귀납 보강).
        assert (s_own || (s_age == 2'd0));
      end

      always @(posedge clk) if (f_past_valid && !reset && !$past(reset)) begin
        // acquire_free — 소유 상승(0→1)의 유일한 경로는 이 슬롯으로의 grant 다.
        assert (!(s_own && !$past(s_own)) || $past(s_grant));
        // acquire_free/구간 시작 — 허가 다음 사이클부터 소유가 관측되고
        // (구간 시작 t), age=0 · 소유자 = 허가 사이클의 prod 다.
        assert (!$past(s_grant)
                               || (s_own && (s_age == 2'd0) && (s_oid == $past(io_acquire_prod))));
        // interval_end — age=L 사이클 말에 해제된다. 그 사이클까지는 소유
        // (기입 자격 유지)이므로 [t, t+L] 양끝 포함 의미 그대로다.
        assert (!$past(s_end) || (!s_own && (s_age == 2'd0)));
        // interval_end — 구간 안에서는 매 사이클 +1 로만 진행하고 소유가
        // 유지된다 (grant 는 소유 슬롯에 불가능하므로 다른 간섭 경로가 없다).
        assert (!$past(s_own && !s_end)
                        || (s_own && (s_age == ($past(s_age) + 2'd1))));
      end
    end
  endgenerate

  // ── owner_check — 비소유 기입은 store 에 닿지 않는다 ───────────────
  // anyconst 슬롯 f_slot: 임의 고정 슬롯에 대해 증명 = 전 슬롯 보편 증명.
  // ($past 64b 를 슬롯당 두지 않기 위한 선택 — 상태 최소화.)
  (* anyconst *) wire [3:0] f_slot;
  wire [63:0] f_store = storeVec[64*f_slot +: 64];
  wire        f_wrq   = io_write_valid && wrQualified && (io_write_slot == f_slot);

  always @(posedge clk) if (f_past_valid && !reset && !$past(reset)) begin
    // owner_check — 자격자 기입 사이클이 아니면 store 는 불변이다. 비소유
    // 기입(valid && !wrQualified)이 어느 슬롯의 저장에도 닿지 않음을 포함한다.
    a_store_untouched: assert ($past(f_wrq) || (f_store == $past(f_store)));
    // owner_check 짝 — 자격 있는 기입은 무조건 성사된다 (제3의 결과 부재:
    // 성사 아니면 loud fault, 조용한 무시 없음).
    a_write_lands: assert (!$past(f_wrq) || (f_store == $past(io_write_data)));
    // owner_check — 자격 없는 기입 시도는 다음 에지에 sticky fault 로 선다
    // (해제 동시 제시면 발화가 이긴다 — StickyFault 계약).
    a_fault_loud: assert (!$past(io_write_valid && !wrQualified) || io_fault);
    // sticky — 명시적 해제 외엔 내려가지 않는다.
    a_fault_sticky: assert (!$past(io_fault && !io_faultClear) || io_fault);
  end

  // ── 관측 정합 ───────────────────────────────────────────────────────
  always @(posedge clk) if (!reset) begin
    // 읽기 포트의 owned 관측은 소유 장부 그대로다 (§2.4 자격 관측면).
    a_read_owned: assert (io_read_owned == ovVec[io_read_slot]);
  end

  // ── 도달성 증인 (cover 태스크 전용) ─────────────────────────────────
  always @(posedge clk) if (!reset) begin
    c_grant:    cover (io_acquire_granted);
    c_deny:     cover (io_acquire_valid && !io_acquire_granted);
    c_write_ok: cover (when_ResultBank_l181);
    c_write_no: cover (io_write_valid && !wrQualified);
    c_full_interval: cover (ovVec[0] && (ageVec[1:0] == L));   // 구간이 끝까지 간다
    c_fault:    cover (io_fault);
  end

endmodule

// 형식 검증 톱 — 대상 + props 결선 (내부 포트는 sby [script] 의 expose 가 만든다).
module ResultBank_formal (
    input wire        clk,
    input wire        reset,
    input wire        io_acquire_valid,
    input wire [3:0]  io_acquire_slot,
    input wire [3:0]  io_acquire_prod,
    input wire        io_write_valid,
    input wire [3:0]  io_write_slot,
    input wire [3:0]  io_write_prod,
    input wire [63:0] io_write_data,
    input wire [3:0]  io_read_slot,
    input wire        io_faultClear
);
  wire        io_acquire_granted;
  wire [63:0] io_read_data;
  wire        io_read_owned;
  wire        io_fault;
  wire [4:0]  io_occupancy;
  wire        acqFree, wrQualified, when_ResultBank_l163, when_ResultBank_l181;
  wire        ownerValid_0,  ownerValid_1,  ownerValid_2,  ownerValid_3,
              ownerValid_4,  ownerValid_5,  ownerValid_6,  ownerValid_7,
              ownerValid_8,  ownerValid_9,  ownerValid_10, ownerValid_11,
              ownerValid_12, ownerValid_13, ownerValid_14, ownerValid_15;
  wire [3:0]  ownerId_0,  ownerId_1,  ownerId_2,  ownerId_3,
              ownerId_4,  ownerId_5,  ownerId_6,  ownerId_7,
              ownerId_8,  ownerId_9,  ownerId_10, ownerId_11,
              ownerId_12, ownerId_13, ownerId_14, ownerId_15;
  wire [1:0]  age_0,  age_1,  age_2,  age_3,  age_4,  age_5,  age_6,  age_7,
              age_8,  age_9,  age_10, age_11, age_12, age_13, age_14, age_15;
  wire [63:0] store_0,  store_1,  store_2,  store_3,  store_4,  store_5,
              store_6,  store_7,  store_8,  store_9,  store_10, store_11,
              store_12, store_13, store_14, store_15;

  ResultBank dut (
    .clk(clk), .reset(reset),
    .io_acquire_valid(io_acquire_valid), .io_acquire_slot(io_acquire_slot),
    .io_acquire_prod(io_acquire_prod), .io_acquire_granted(io_acquire_granted),
    .io_write_valid(io_write_valid), .io_write_slot(io_write_slot),
    .io_write_prod(io_write_prod), .io_write_data(io_write_data),
    .io_read_slot(io_read_slot), .io_read_data(io_read_data), .io_read_owned(io_read_owned),
    .io_fault(io_fault), .io_faultClear(io_faultClear),
    .io_occupancy(io_occupancy),
    // ── expose 로 올린 내부 관측 포트 ──
    .acqFree(acqFree), .wrQualified(wrQualified),
    .when_ResultBank_l163(when_ResultBank_l163), .when_ResultBank_l181(when_ResultBank_l181),
    .ownerValid_0(ownerValid_0),   .ownerValid_1(ownerValid_1),   .ownerValid_2(ownerValid_2),   .ownerValid_3(ownerValid_3),
    .ownerValid_4(ownerValid_4),   .ownerValid_5(ownerValid_5),   .ownerValid_6(ownerValid_6),   .ownerValid_7(ownerValid_7),
    .ownerValid_8(ownerValid_8),   .ownerValid_9(ownerValid_9),   .ownerValid_10(ownerValid_10), .ownerValid_11(ownerValid_11),
    .ownerValid_12(ownerValid_12), .ownerValid_13(ownerValid_13), .ownerValid_14(ownerValid_14), .ownerValid_15(ownerValid_15),
    .ownerId_0(ownerId_0),   .ownerId_1(ownerId_1),   .ownerId_2(ownerId_2),   .ownerId_3(ownerId_3),
    .ownerId_4(ownerId_4),   .ownerId_5(ownerId_5),   .ownerId_6(ownerId_6),   .ownerId_7(ownerId_7),
    .ownerId_8(ownerId_8),   .ownerId_9(ownerId_9),   .ownerId_10(ownerId_10), .ownerId_11(ownerId_11),
    .ownerId_12(ownerId_12), .ownerId_13(ownerId_13), .ownerId_14(ownerId_14), .ownerId_15(ownerId_15),
    .age_0(age_0),   .age_1(age_1),   .age_2(age_2),   .age_3(age_3),
    .age_4(age_4),   .age_5(age_5),   .age_6(age_6),   .age_7(age_7),
    .age_8(age_8),   .age_9(age_9),   .age_10(age_10), .age_11(age_11),
    .age_12(age_12), .age_13(age_13), .age_14(age_14), .age_15(age_15),
    .store_0(store_0),   .store_1(store_1),   .store_2(store_2),   .store_3(store_3),
    .store_4(store_4),   .store_5(store_5),   .store_6(store_6),   .store_7(store_7),
    .store_8(store_8),   .store_9(store_9),   .store_10(store_10), .store_11(store_11),
    .store_12(store_12), .store_13(store_13), .store_14(store_14), .store_15(store_15)
  );

  ResultBank_props u_ResultBank_props (
    .clk(clk), .reset(reset),
  .io_acquire_valid(io_acquire_valid), .io_acquire_slot(io_acquire_slot),
  .io_acquire_prod(io_acquire_prod), .io_acquire_granted(io_acquire_granted),
  .io_write_valid(io_write_valid), .io_write_slot(io_write_slot),
  .io_write_prod(io_write_prod), .io_write_data(io_write_data),
  .io_read_slot(io_read_slot), .io_read_data(io_read_data), .io_read_owned(io_read_owned),
  .io_fault(io_fault), .io_faultClear(io_faultClear),
  .acqFree(acqFree), .wrQualified(wrQualified),
  .when_ResultBank_l163(when_ResultBank_l163), .when_ResultBank_l181(when_ResultBank_l181),
  .ownerValid_0(ownerValid_0),   .ownerValid_1(ownerValid_1),   .ownerValid_2(ownerValid_2),   .ownerValid_3(ownerValid_3),
  .ownerValid_4(ownerValid_4),   .ownerValid_5(ownerValid_5),   .ownerValid_6(ownerValid_6),   .ownerValid_7(ownerValid_7),
  .ownerValid_8(ownerValid_8),   .ownerValid_9(ownerValid_9),   .ownerValid_10(ownerValid_10), .ownerValid_11(ownerValid_11),
  .ownerValid_12(ownerValid_12), .ownerValid_13(ownerValid_13), .ownerValid_14(ownerValid_14), .ownerValid_15(ownerValid_15),
  .ownerId_0(ownerId_0),   .ownerId_1(ownerId_1),   .ownerId_2(ownerId_2),   .ownerId_3(ownerId_3),
  .ownerId_4(ownerId_4),   .ownerId_5(ownerId_5),   .ownerId_6(ownerId_6),   .ownerId_7(ownerId_7),
  .ownerId_8(ownerId_8),   .ownerId_9(ownerId_9),   .ownerId_10(ownerId_10), .ownerId_11(ownerId_11),
  .ownerId_12(ownerId_12), .ownerId_13(ownerId_13), .ownerId_14(ownerId_14), .ownerId_15(ownerId_15),
  .age_0(age_0),   .age_1(age_1),   .age_2(age_2),   .age_3(age_3),
  .age_4(age_4),   .age_5(age_5),   .age_6(age_6),   .age_7(age_7),
  .age_8(age_8),   .age_9(age_9),   .age_10(age_10), .age_11(age_11),
  .age_12(age_12), .age_13(age_13), .age_14(age_14), .age_15(age_15),
  .store_0(store_0),   .store_1(store_1),   .store_2(store_2),   .store_3(store_3),
  .store_4(store_4),   .store_5(store_5),   .store_6(store_6),   .store_7(store_7),
  .store_8(store_8),   .store_9(store_9),   .store_10(store_10), .store_11(store_11),
  .store_12(store_12), .store_13(store_13), .store_14(store_14), .store_15(store_15)
  );
endmodule

`default_nettype wire
