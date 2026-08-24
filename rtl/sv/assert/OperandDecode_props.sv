// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// OperandDecode 후-formal 하네스 (§6.3) — 조합 모듈. 선-formal 모델은 없다
// (관측 기반 착지) — 검사 원천은 정본 문면과 DecodeWalk GUARD-MAP 이 예고한
// 합류 계약(Decode.resv_judged 「2차 파도가 같은 판정점에 합류」)이다.
//
// 부착 방식 (계획 이탈 기록): 원계획 bind 는 컨테이너 yosys 0.66 이 파싱만
// 하고 적용하지 않아 (실측 — DecodeWalk_props.sv 머리 참조) 파일 말미의
// formal 전용 래퍼(OperandDecode_formal)로 대체한다. 내부 비교기(judge.*)
// 탭도 불가 — 다행히 이 모듈은 조합이라 판정 합류식 oMalformed =
// iMalformed ∨ bodyMal 에서 iMalformed=0 단면이 bodyMal 을 그대로 노출하므로,
// 출력 등가가 곧 비교기 등가다 (정보 손실 없음).
//
// 하네스 작법 규율 (DecodeWalk 쪽 실측 2건의 이식): 참조 논리는 순수 wire
// 연속 대입 + 매크로만 쓴다 — always_comb 배열은 $mem_v2/$anyinit 상태로,
// 연속 대입 우변의 함수 호출은 미구동 $func$…$result 자유 변수로 각각
// 오염된다 (yosys 0.66 실측 — DecodeWalk_props.sv 수리 기록 참조).
//
// 검사 항목 (아래 이름이 .sby 의 PROVES 앵커):
//   OperandDecode.body_resv_judged — 본문 예약 판정 3종의 등가:
//       OPREF [23:20] 폐지 니블 != 0 (§1.4.6 · §5.7) /
//       OPREF src_kind >= 3 예약값 (§1.4.3 표 — RouteJudge 가 디코드 경계로
//       넘긴 거절의 실물) / ACCTGT [23:16] 예약 바이트 != 0 (§1.4.7 · §5.7).
//       판정은 실재(present) 슬롯에 대해서만 발화 (§1.6.1 함정 — 부재 EH 의
//       본문 잔여값은 판정 대상이 아니다). 참조 판정이 슬롯 서술자 + 해당
//       예약 슬라이스만 읽으므로, 등가가 곧 판정 콘의 협소성(비교기 콘) 증명.
//   OperandDecode.verdict_join — 판정 합류: oMalformed = iMalformed ∨ bodyMal ·
//       oCapAbsent 무변경 통과 · oExecValid = iExecValid ∧ ¬bodyMal ·
//       bodyMal 은 ¬iCapAbsent 게이트 (ISA-5 — 능력 밖 사슬은 판정 대상 아님).
//   OperandDecode.exec_gate — oExecValid 아래 산출 전면 억제: 비유효 명령의
//       해석 산출은 전부 0 — 방출면 구별 불가능 (SEC-7 (ii) 부류).
//   OperandDecode.resv_not_echoed — 예약 슬라이스 인접 필드(OPREF LBID·
//       src_kind, ACCTGT LBID, 재조립 결속)의 등가: 예약 비트는 1비트 판정
//       등급 외 어떤 방출면에도 실리지 않는다.
//   OperandDecode.fault_sticky — 본문 malformation 전용 sticky (§5.5 ·
//       §5.6 폴딩 명시: 세 원인을 이 1비트로 접고, DecodeWalk.oFault 와는
//       접지 않는다 — 별도 신호라는 사실은 포트 분리가 구조로 보증).
//
// 반례 규율: 참조 판정이 틀리면 (1)갈래 — 고치고 경위를 주석으로.
module OperandDecode_props (
  input  wire        clk,
  input  wire        reset,
  input  wire        io_iValid,
  input  wire        io_iMalformed,
  input  wire        io_iCapAbsent,
  input  wire        io_iExecValid,
  input  wire [31:0] io_iInstr_0,
  input  wire [31:0] io_iInstr_1,
  input  wire [31:0] io_iInstr_2,
  input  wire [31:0] io_iInstr_3,
  input  wire [31:0] io_iInstr_4,
  input  wire [31:0] io_iInstr_5,
  input  wire [31:0] io_iInstr_6,
  input  wire [31:0] io_iInstr_7,
  input  wire [31:0] io_iInstr_8,
  input  wire [31:0] io_iInstr_9,
  input  wire [31:0] io_iInstr_10,
  input  wire [31:0] io_iInstr_11,
  input  wire [31:0] io_iInstr_12,
  input  wire        io_iSlotPresent_0,
  input  wire        io_iSlotPresent_1,
  input  wire        io_iSlotPresent_2,
  input  wire        io_iSlotPresent_3,
  input  wire [3:0]  io_iSlotCode_0,
  input  wire [3:0]  io_iSlotCode_1,
  input  wire [3:0]  io_iSlotCode_2,
  input  wire [3:0]  io_iSlotCode_3,
  input  wire [7:0]  io_iSlotOff_0,
  input  wire [7:0]  io_iSlotOff_1,
  input  wire [7:0]  io_iSlotOff_2,
  input  wire [7:0]  io_iSlotOff_3,
  input  wire        io_iFaultClear,
  input  wire        io_oValid,
  input  wire        io_oMalformed,
  input  wire        io_oCapAbsent,
  input  wire        io_oExecValid,
  input  wire        io_oPortPresent,
  input  wire [15:0] io_oPortDest,
  input  wire        io_oImm16Present,
  input  wire [15:0] io_oImm16,
  input  wire        io_oImm32Present,
  input  wire [31:0] io_oImm32,
  input  wire        io_oImm64Present,
  input  wire [63:0] io_oImm64,
  input  wire        io_oMemPresent,
  input  wire [3:0]  io_oMemAddrMode,
  input  wire [11:0] io_oMemStride,
  input  wire [31:0] io_oMemOffset,
  input  wire        io_oSubValid_0,
  input  wire        io_oSubValid_1,
  input  wire        io_oSubValid_2,
  input  wire        io_oSubValid_3,
  input  wire [15:0] io_oSubO_0,
  input  wire [15:0] io_oSubO_1,
  input  wire [15:0] io_oSubO_2,
  input  wire [15:0] io_oSubO_3,
  input  wire [15:0] io_oSubA_0,
  input  wire [15:0] io_oSubA_1,
  input  wire [15:0] io_oSubA_2,
  input  wire [15:0] io_oSubA_3,
  input  wire [15:0] io_oSubB_0,
  input  wire [15:0] io_oSubB_1,
  input  wire [15:0] io_oSubB_2,
  input  wire [15:0] io_oSubB_3,
  input  wire [2:0]  io_oSubCount,
  input  wire        io_oOprefAValid,
  input  wire [7:0]  io_oOprefALbid,
  input  wire [3:0]  io_oOprefASrcKind,
  input  wire        io_oOprefBValid,
  input  wire [7:0]  io_oOprefBLbid,
  input  wire [3:0]  io_oOprefBSrcKind,
  input  wire        io_oPrecPresent,
  input  wire [7:0]  io_oPrecMode,
  input  wire [7:0]  io_oPrecDim,
  input  wire        io_oReasmBind_valid,
  input  wire [7:0]  io_oReasmBind_payload,
  input  wire        io_oFault
);

  // ── ENV: 부팅 reset 프로토콜 ──────────────────────────────────────────────
  // assume 근거: §1.5 초기 상태 — 리셋 인가 후 해제. sticky 레지스터 외에는
  // 조합 논리뿐이라 리셋은 oFault 초기화에만 관여한다.
  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;
  always @* begin
    if (!f_past_valid) assume (reset);
    else               assume (!reset);
  end

  // ── ENV: DecodeWalk 방출면 계약 (io 주석 「DecodeWalk 방출면과 1:1」) ─────
  // assume 근거 1: DecodeWalk 의 두 종결은 배타로 방출된다 (ISA-5 —
  //   DecodeWalk GUARD-MAP judge.mal 의 !capAbsent 구조 + DecodeWalk_props 가
  //   같은 파도에서 증명하는 !(oMalformed && oCapAbsent)).
  // assume 근거 2: DecodeWalk oExecValid 의 정의 —
  //   oExecValid = oValid && !oMalformed && !oCapAbsent (Decode.verdict_ungated
  //   문면 + DecodeWalk_props 의 게이트 등식 증명 항목).
  // 이 두 가정은 아래 출력 배타성 단언 2건에만 필요하다 — 등가 단언들은
  // 가정 없이도 전 입력에서 성립한다.
  always @* begin
    assume (!(io_iMalformed && io_iCapAbsent));
    assume (!(io_iExecValid && (io_iMalformed || io_iCapAbsent)));
  end

  // ── 참조 판정 — §1.4.3 · §1.4.6 · §1.4.7 · §5.7 의 독립 재구현 ───────────
  // 각 워드의 [31:16] — EH 워드0 본문 상위 16비트 (§1.3.3 배치).
  wire [16*13-1:0] f_hi16bus = {
    io_iInstr_12[31:16], io_iInstr_11[31:16], io_iInstr_10[31:16],
    io_iInstr_9[31:16],  io_iInstr_8[31:16],  io_iInstr_7[31:16],
    io_iInstr_6[31:16],  io_iInstr_5[31:16],  io_iInstr_4[31:16],
    io_iInstr_3[31:16],  io_iInstr_2[31:16],  io_iInstr_1[31:16],
    io_iInstr_0[31:16] };

  // 표 조회 — 8비트 오프셋 전폭 등가 비교와 동치: 표 밖 값은 0 (RTL 의
  // one-hot 마스킹 OR 과 같은 의미론 — §1.3 부류의 절단 금지). 명시 시프트.
  wire [16*13-1:0] f_sh0 = f_hi16bus >> (io_iSlotOff_0 * 16);
  wire [16*13-1:0] f_sh1 = f_hi16bus >> (io_iSlotOff_1 * 16);
  wire [16*13-1:0] f_sh2 = f_hi16bus >> (io_iSlotOff_2 * 16);
  wire [16*13-1:0] f_sh3 = f_hi16bus >> (io_iSlotOff_3 * 16);
  wire [15:0] f_body0 = (io_iSlotOff_0 < 8'd13) ? f_sh0[15:0] : 16'h0;
  wire [15:0] f_body1 = (io_iSlotOff_1 < 8'd13) ? f_sh1[15:0] : 16'h0;
  wire [15:0] f_body2 = (io_iSlotOff_2 < 8'd13) ? f_sh2[15:0] : 16'h0;
  wire [15:0] f_body3 = (io_iSlotOff_3 < 8'd13) ? f_sh3[15:0] : 16'h0;

  // 실재 + 4비트 코드 전체 비교 (§1.6.1 함정 — present 전건).
  wire f_isOpref0  = io_iSlotPresent_0 && (io_iSlotCode_0 == 4'h7);
  wire f_isOpref1  = io_iSlotPresent_1 && (io_iSlotCode_1 == 4'h7);
  wire f_isOpref2  = io_iSlotPresent_2 && (io_iSlotCode_2 == 4'h7);
  wire f_isOpref3  = io_iSlotPresent_3 && (io_iSlotCode_3 == 4'h7);
  wire f_isAcctgt0 = io_iSlotPresent_0 && (io_iSlotCode_0 == 4'h9);
  wire f_isAcctgt1 = io_iSlotPresent_1 && (io_iSlotCode_1 == 4'h9);
  wire f_isAcctgt2 = io_iSlotPresent_2 && (io_iSlotCode_2 == 4'h9);
  wire f_isAcctgt3 = io_iSlotPresent_3 && (io_iSlotCode_3 == 4'h9);

  // 판정 3종 — 대응 예약 슬라이스만 소비한다.
  wire f_oprefResvBad =                                    // §1.4.6 · §5.7
    (f_isOpref0 && (f_body0[7:4] != 4'h0)) || (f_isOpref1 && (f_body1[7:4] != 4'h0)) ||
    (f_isOpref2 && (f_body2[7:4] != 4'h0)) || (f_isOpref3 && (f_body3[7:4] != 4'h0));
  wire f_srcKindBad =                                      // §1.4.3 표
    (f_isOpref0 && (f_body0[3:0] >= 4'd3)) || (f_isOpref1 && (f_body1[3:0] >= 4'd3)) ||
    (f_isOpref2 && (f_body2[3:0] >= 4'd3)) || (f_isOpref3 && (f_body3[3:0] >= 4'd3));
  wire f_acctgtResvBad =                                   // §1.4.7 · §5.7
    (f_isAcctgt0 && (f_body0[7:0] != 8'h00)) || (f_isAcctgt1 && (f_body1[7:0] != 8'h00)) ||
    (f_isAcctgt2 && (f_body2[7:0] != 8'h00)) || (f_isAcctgt3 && (f_body3[7:0] != 8'h00));
  // capability 종결이 맨 앞 (ISA-5) — 능력 밖 사슬은 본문 판정 대상 아님.
  wire f_bodyMal = !io_iCapAbsent && (f_oprefResvBad || f_srcKindBad || f_acctgtResvBad);

  // OPREF 등장 순서 A·B (§4.2.3) — 예약 슬라이스 불참의 참조 필드.
  wire f_a0 = f_isOpref0;
  wire f_a1 = f_isOpref1 && !f_isOpref0;
  wire f_a2 = f_isOpref2 && !f_isOpref0 && !f_isOpref1;
  wire f_a3 = f_isOpref3 && !f_isOpref0 && !f_isOpref1 && !f_isOpref2;
  wire f_b1 = f_isOpref1 && f_isOpref0;
  wire f_b2 = f_isOpref2 && (({2'b0, f_isOpref0} + {2'b0, f_isOpref1}) == 3'd1);
  wire f_b3 = f_isOpref3 &&
              (({2'b0, f_isOpref0} + {2'b0, f_isOpref1} + {2'b0, f_isOpref2}) == 3'd1);
  wire f_aValid = f_a0 || f_a1 || f_a2 || f_a3;
  wire f_bValid = f_b1 || f_b2 || f_b3;
  // noc_route 전폭 = LBID (§1.4.3) — 마스킹 OR (RTL gather 와 같은 접기).
  wire [7:0] f_aLbid = (f_a0 ? f_body0[15:8] : 8'h0) | (f_a1 ? f_body1[15:8] : 8'h0) |
                       (f_a2 ? f_body2[15:8] : 8'h0) | (f_a3 ? f_body3[15:8] : 8'h0);
  wire [3:0] f_aKind = (f_a0 ? f_body0[3:0] : 4'h0) | (f_a1 ? f_body1[3:0] : 4'h0) |
                       (f_a2 ? f_body2[3:0] : 4'h0) | (f_a3 ? f_body3[3:0] : 4'h0);
  wire [7:0] f_bLbid = (f_b1 ? f_body1[15:8] : 8'h0) |
                       (f_b2 ? f_body2[15:8] : 8'h0) | (f_b3 ? f_body3[15:8] : 8'h0);
  wire [3:0] f_bKind = (f_b1 ? f_body1[3:0] : 4'h0) |
                       (f_b2 ? f_body2[3:0] : 4'h0) | (f_b3 ? f_body3[3:0] : 4'h0);
  // ACCTGT — 목적 LBID = body[15:8] (§1.4.7). RTL gather 와 같은 OR 접기.
  wire f_acctgtPresent = f_isAcctgt0 || f_isAcctgt1 || f_isAcctgt2 || f_isAcctgt3;
  wire [7:0] f_acctgtLbid =
    (f_isAcctgt0 ? f_body0[15:8] : 8'h0) | (f_isAcctgt1 ? f_body1[15:8] : 8'h0) |
    (f_isAcctgt2 ? f_body2[15:8] : 8'h0) | (f_isAcctgt3 ? f_body3[15:8] : 8'h0);

  // ── 조합 단언 ────────────────────────────────────────────────────────────
  always_comb begin
    // OperandDecode.body_resv_judged + verdict_join — 합류면의 등가.
    // iMalformed=0 단면이 bodyMal 등가를 그대로 노출한다 (전 입력 검사).
    assert (io_oValid     == io_iValid);
    assert (io_oCapAbsent == io_iCapAbsent);
    assert (io_oMalformed == (io_iMalformed || f_bodyMal));
    assert (io_oExecValid == (io_iExecValid && !f_bodyMal));
    // ISA-5 — 출력 배타 (위 ENV 가정 2건에 의존).
    assert (!(io_oMalformed && io_oCapAbsent));
    assert (!(io_oExecValid && (io_oMalformed || io_oCapAbsent)));

    // OperandDecode.exec_gate — 비유효 명령의 해석 산출 전면 억제.
    if (!io_oExecValid) begin
      assert (io_oPortPresent == 1'b0 && io_oPortDest == 16'h0);
      assert (io_oImm16Present == 1'b0 && io_oImm16 == 16'h0);
      assert (io_oImm32Present == 1'b0 && io_oImm32 == 32'h0);
      assert (io_oImm64Present == 1'b0 && io_oImm64 == 64'h0);
      assert (io_oMemPresent == 1'b0 && io_oMemAddrMode == 4'h0
              && io_oMemStride == 12'h0 && io_oMemOffset == 32'h0);
      assert (io_oSubValid_0 == 1'b0 && io_oSubValid_1 == 1'b0
              && io_oSubValid_2 == 1'b0 && io_oSubValid_3 == 1'b0);
      assert (io_oSubO_0 == 16'h0 && io_oSubO_1 == 16'h0
              && io_oSubO_2 == 16'h0 && io_oSubO_3 == 16'h0);
      assert (io_oSubA_0 == 16'h0 && io_oSubA_1 == 16'h0
              && io_oSubA_2 == 16'h0 && io_oSubA_3 == 16'h0);
      assert (io_oSubB_0 == 16'h0 && io_oSubB_1 == 16'h0
              && io_oSubB_2 == 16'h0 && io_oSubB_3 == 16'h0);
      assert (io_oSubCount == 3'h0);
      assert (io_oOprefAValid == 1'b0 && io_oOprefALbid == 8'h0
              && io_oOprefASrcKind == 4'h0);
      assert (io_oOprefBValid == 1'b0 && io_oOprefBLbid == 8'h0
              && io_oOprefBSrcKind == 4'h0);
      assert (io_oPrecPresent == 1'b0 && io_oPrecMode == 8'h0 && io_oPrecDim == 8'h0);
      assert (io_oReasmBind_valid == 1'b0 && io_oReasmBind_payload == 8'h0);
    end

    // OperandDecode.resv_not_echoed — 예약 인접 필드의 등가: OPREF 예약 니블
    // body[7:4] 과 ACCTGT 예약 바이트 body[7:0] 은 아래 어떤 우변에도 없다.
    assert (io_oOprefAValid   == (io_oExecValid && f_aValid));
    assert (io_oOprefALbid    == ((io_oExecValid && f_aValid) ? f_aLbid : 8'h0));
    assert (io_oOprefASrcKind == ((io_oExecValid && f_aValid) ? f_aKind : 4'h0));
    assert (io_oOprefBValid   == (io_oExecValid && f_bValid));
    assert (io_oOprefBLbid    == ((io_oExecValid && f_bValid) ? f_bLbid : 8'h0));
    assert (io_oOprefBSrcKind == ((io_oExecValid && f_bValid) ? f_bKind : 4'h0));
    // 재조립 결속 (§4.3 D8 부류) — malformed wave 는 문맥을 열지 못한다.
    assert (io_oReasmBind_valid   == (io_oExecValid && f_acctgtPresent));
    assert (io_oReasmBind_payload ==
            ((io_oExecValid && f_acctgtPresent) ? f_acctgtLbid : 8'h0));
  end

  // ── 클록 단언 — 본문 malformation 전용 sticky (§5.5) ─────────────────────
  always @(posedge clk) begin
    if (f_past_valid && !reset && !$past(reset)) begin
      // 상승은 유효한 본문 판정 에피소드에서만 (f_bodyMal 은 bodyMal 과
      // 조합 등가 — 위 합류면 단언이 강제).
      if (io_oFault && !$past(io_oFault))
        assert ($past(io_iValid && f_bodyMal));
      // 하강은 명시적 해제에서만.
      if (!io_oFault && $past(io_oFault))
        assert ($past(io_iFaultClear));
      // 세움 유실 없음 (해제 동시 제시에도 세움 우선).
      if ($past(io_iValid && f_bodyMal))
        assert (io_oFault);
      // 해제 없인 유지.
      if ($past(io_oFault) && !$past(io_iFaultClear))
        assert (io_oFault);
      // capability 불참 (§1.6.2): bodyMal 의 !iCapAbsent 게이트가 구조 —
      // 상승 조건이 bodyMal 을 전건으로 요구하므로 함께 증명된다.
    end
  end

endmodule

// ── formal 전용 래퍼 — bind 의 대체 (파일 머리의 이탈 기록 참조) ───────────
module OperandDecode_formal (
  input  wire        clk,
  input  wire        reset,
  input  wire        iValid, iMalformed, iCapAbsent, iExecValid,
  input  wire [31:0] i0, i1, i2, i3, i4, i5, i6, i7, i8, i9, i10, i11, i12,
  input  wire        p0, p1, p2, p3,
  input  wire [3:0]  c0, c1, c2, c3,
  input  wire [7:0]  f0, f1, f2, f3,
  input  wire        iFaultClear
);
  wire oValid, oMalformed, oCapAbsent, oExecValid, oFault;
  wire oPortPresent, oImm16Present, oImm32Present, oImm64Present, oMemPresent;
  wire [15:0] oPortDest, oImm16;
  wire [31:0] oImm32, oMemOffset;
  wire [63:0] oImm64;
  wire [3:0]  oMemAddrMode;
  wire [11:0] oMemStride;
  wire oSV0, oSV1, oSV2, oSV3;
  wire [15:0] oSO0, oSO1, oSO2, oSO3, oSA0, oSA1, oSA2, oSA3, oSB0, oSB1, oSB2, oSB3;
  wire [2:0]  oSubCount;
  wire oAV, oBV;
  wire [7:0] oALbid, oBLbid;
  wire [3:0] oAKind, oBKind;
  wire oPrecPresent;
  wire [7:0] oPrecMode, oPrecDim;
  wire oBindV;
  wire [7:0] oBindP;

  OperandDecode dut (
    .clk(clk), .reset(reset),
    .io_iValid(iValid), .io_iMalformed(iMalformed),
    .io_iCapAbsent(iCapAbsent), .io_iExecValid(iExecValid),
    .io_iInstr_0(i0), .io_iInstr_1(i1), .io_iInstr_2(i2), .io_iInstr_3(i3),
    .io_iInstr_4(i4), .io_iInstr_5(i5), .io_iInstr_6(i6), .io_iInstr_7(i7),
    .io_iInstr_8(i8), .io_iInstr_9(i9), .io_iInstr_10(i10), .io_iInstr_11(i11),
    .io_iInstr_12(i12),
    .io_iSlotPresent_0(p0), .io_iSlotPresent_1(p1),
    .io_iSlotPresent_2(p2), .io_iSlotPresent_3(p3),
    .io_iSlotCode_0(c0), .io_iSlotCode_1(c1), .io_iSlotCode_2(c2), .io_iSlotCode_3(c3),
    .io_iSlotOff_0(f0), .io_iSlotOff_1(f1), .io_iSlotOff_2(f2), .io_iSlotOff_3(f3),
    .io_iFaultClear(iFaultClear),
    .io_oValid(oValid), .io_oMalformed(oMalformed), .io_oCapAbsent(oCapAbsent),
    .io_oExecValid(oExecValid),
    .io_oPortPresent(oPortPresent), .io_oPortDest(oPortDest),
    .io_oImm16Present(oImm16Present), .io_oImm16(oImm16),
    .io_oImm32Present(oImm32Present), .io_oImm32(oImm32),
    .io_oImm64Present(oImm64Present), .io_oImm64(oImm64),
    .io_oMemPresent(oMemPresent), .io_oMemAddrMode(oMemAddrMode),
    .io_oMemStride(oMemStride), .io_oMemOffset(oMemOffset),
    .io_oSubValid_0(oSV0), .io_oSubValid_1(oSV1),
    .io_oSubValid_2(oSV2), .io_oSubValid_3(oSV3),
    .io_oSubO_0(oSO0), .io_oSubO_1(oSO1), .io_oSubO_2(oSO2), .io_oSubO_3(oSO3),
    .io_oSubA_0(oSA0), .io_oSubA_1(oSA1), .io_oSubA_2(oSA2), .io_oSubA_3(oSA3),
    .io_oSubB_0(oSB0), .io_oSubB_1(oSB1), .io_oSubB_2(oSB2), .io_oSubB_3(oSB3),
    .io_oSubCount(oSubCount),
    .io_oOprefAValid(oAV), .io_oOprefALbid(oALbid), .io_oOprefASrcKind(oAKind),
    .io_oOprefBValid(oBV), .io_oOprefBLbid(oBLbid), .io_oOprefBSrcKind(oBKind),
    .io_oPrecPresent(oPrecPresent), .io_oPrecMode(oPrecMode), .io_oPrecDim(oPrecDim),
    .io_oReasmBind_valid(oBindV), .io_oReasmBind_payload(oBindP),
    .io_oFault(oFault)
  );

  OperandDecode_props props (
    .clk(clk), .reset(reset),
    .io_iValid(iValid), .io_iMalformed(iMalformed),
    .io_iCapAbsent(iCapAbsent), .io_iExecValid(iExecValid),
    .io_iInstr_0(i0), .io_iInstr_1(i1), .io_iInstr_2(i2), .io_iInstr_3(i3),
    .io_iInstr_4(i4), .io_iInstr_5(i5), .io_iInstr_6(i6), .io_iInstr_7(i7),
    .io_iInstr_8(i8), .io_iInstr_9(i9), .io_iInstr_10(i10), .io_iInstr_11(i11),
    .io_iInstr_12(i12),
    .io_iSlotPresent_0(p0), .io_iSlotPresent_1(p1),
    .io_iSlotPresent_2(p2), .io_iSlotPresent_3(p3),
    .io_iSlotCode_0(c0), .io_iSlotCode_1(c1), .io_iSlotCode_2(c2), .io_iSlotCode_3(c3),
    .io_iSlotOff_0(f0), .io_iSlotOff_1(f1), .io_iSlotOff_2(f2), .io_iSlotOff_3(f3),
    .io_iFaultClear(iFaultClear),
    .io_oValid(oValid), .io_oMalformed(oMalformed), .io_oCapAbsent(oCapAbsent),
    .io_oExecValid(oExecValid),
    .io_oPortPresent(oPortPresent), .io_oPortDest(oPortDest),
    .io_oImm16Present(oImm16Present), .io_oImm16(oImm16),
    .io_oImm32Present(oImm32Present), .io_oImm32(oImm32),
    .io_oImm64Present(oImm64Present), .io_oImm64(oImm64),
    .io_oMemPresent(oMemPresent), .io_oMemAddrMode(oMemAddrMode),
    .io_oMemStride(oMemStride), .io_oMemOffset(oMemOffset),
    .io_oSubValid_0(oSV0), .io_oSubValid_1(oSV1),
    .io_oSubValid_2(oSV2), .io_oSubValid_3(oSV3),
    .io_oSubO_0(oSO0), .io_oSubO_1(oSO1), .io_oSubO_2(oSO2), .io_oSubO_3(oSO3),
    .io_oSubA_0(oSA0), .io_oSubA_1(oSA1), .io_oSubA_2(oSA2), .io_oSubA_3(oSA3),
    .io_oSubB_0(oSB0), .io_oSubB_1(oSB1), .io_oSubB_2(oSB2), .io_oSubB_3(oSB3),
    .io_oSubCount(oSubCount),
    .io_oOprefAValid(oAV), .io_oOprefALbid(oALbid), .io_oOprefASrcKind(oAKind),
    .io_oOprefBValid(oBV), .io_oOprefBLbid(oBLbid), .io_oOprefBSrcKind(oBKind),
    .io_oPrecPresent(oPrecPresent), .io_oPrecMode(oPrecMode), .io_oPrecDim(oPrecDim),
    .io_oReasmBind_valid(oBindV), .io_oReasmBind_payload(oBindP),
    .io_oFault(oFault)
  );
endmodule
