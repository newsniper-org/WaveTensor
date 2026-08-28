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
// 검사 항목 (아래 이름이 .sby 의 VERIFIES 앵커):
//   OperandDecode.body_resv_judged — 본문 판정 2종의 등가 (인코딩 개정 파도):
//       OPREF [23:20] CRC-4 재계산 대조 (§1.4.6 · W5 — 메시지 = 논리 12b
//       LBID[7]‥[0] ∥ src_kind[3]‥[0] MSB-first, G(x)=x⁴+x+1, 비반사 ·
//       init 0 · xorout 없음, 불일치 = malformation) /
//       OPREF src_kind >= 3 예약값 (§1.4.3 표 — RouteJudge 가 디코드 경계로
//       넘긴 거절의 실물). (W4: ACCTGT [23:16] 판정 항은 소멸 — 총개수
//       필드라 어떤 값도 판정을 울리지 않는다, §1.4.7. 해석·방출의 등가는
//       resv_not_echoed 부류의 oAcctgtTotal 등식이 잰다.)
//       판정은 실재(present) 슬롯에 대해서만 발화 (§1.6.1 함정 — 부재 EH 의
//       본문 잔여값은 판정 대상이 아니다). 참조 판정이 슬롯 서술자 + 해당
//       판정 슬라이스만 읽으므로, 등가가 곧 판정 콘의 협소성(비교기 콘) 증명.
//   OperandDecode.verdict_join — 판정 합류: oMalformed = iMalformed ∨ bodyMal ·
//       oCapAbsent 무변경 통과 · oExecValid = iExecValid ∧ ¬bodyMal ·
//       bodyMal 은 ¬iCapAbsent 게이트 (ISA-5 — 능력 밖 사슬은 판정 대상 아님).
//   OperandDecode.exec_gate — oExecValid 아래 산출 전면 억제: 비유효 명령의
//       해석 산출은 전부 0 — 방출면 구별 불가능 (SEC-7 (ii) 부류).
//   OperandDecode.resv_not_echoed — 판정 슬라이스 인접 필드(OPREF LBID·
//       src_kind, ACCTGT LBID·총개수 T, 재조립 결속)의 등가: CRC 니블은
//       1비트 판정 등급 외 어떤 방출면에도 실리지 않고, ACCTGT 총개수는
//       판정 없이 해석 필드로 방출된다 (W4 — oAcctgtTotal 등식).
//   OperandDecode.fault_sticky — 본문 malformation 전용 sticky (§5.5 ·
//       §5.6 폴딩 명시: 두 원인 — OPREF CRC-4 불일치 · src_kind 예약값 —
//       을 이 1비트로 접고, DecodeWalk.oFault 와는
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
  input  wire [31:0] io_iInstr_13,
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
  input  wire [7:0]  io_oAcctgtTotal,
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

  // ── 참조 판정 — §1.4.3 · §1.4.6(W5) · §1.4.7(W4) · §5.7 의 독립 재구현 ───
  // 각 워드의 [31:16] — EH 워드0 본문 상위 16비트 (§1.3.3 배치).
  wire [16*14-1:0] f_hi16bus = {
    io_iInstr_13[31:16], io_iInstr_12[31:16], io_iInstr_11[31:16],
    io_iInstr_10[31:16], io_iInstr_9[31:16],  io_iInstr_8[31:16],
    io_iInstr_7[31:16],  io_iInstr_6[31:16],  io_iInstr_5[31:16],
    io_iInstr_4[31:16],  io_iInstr_3[31:16],  io_iInstr_2[31:16],
    io_iInstr_1[31:16],  io_iInstr_0[31:16] };

  // 표 조회 — 8비트 오프셋 전폭 등가 비교와 동치: 표 밖 값은 0 (RTL 의
  // one-hot 마스킹 OR 과 같은 의미론 — §1.3 부류의 절단 금지). 명시 시프트.
  wire [16*14-1:0] f_sh0 = f_hi16bus >> (io_iSlotOff_0 * 16);
  wire [16*14-1:0] f_sh1 = f_hi16bus >> (io_iSlotOff_1 * 16);
  wire [16*14-1:0] f_sh2 = f_hi16bus >> (io_iSlotOff_2 * 16);
  wire [16*14-1:0] f_sh3 = f_hi16bus >> (io_iSlotOff_3 * 16);
  wire [15:0] f_body0 = (io_iSlotOff_0 < 8'd14) ? f_sh0[15:0] : 16'h0;
  wire [15:0] f_body1 = (io_iSlotOff_1 < 8'd14) ? f_sh1[15:0] : 16'h0;
  wire [15:0] f_body2 = (io_iSlotOff_2 < 8'd14) ? f_sh2[15:0] : 16'h0;
  wire [15:0] f_body3 = (io_iSlotOff_3 < 8'd14) ? f_sh3[15:0] : 16'h0;

  // 실재 + 4비트 코드 전체 비교 (§1.6.1 함정 — present 전건).
  wire f_isOpref0  = io_iSlotPresent_0 && (io_iSlotCode_0 == 4'h7);
  wire f_isOpref1  = io_iSlotPresent_1 && (io_iSlotCode_1 == 4'h7);
  wire f_isOpref2  = io_iSlotPresent_2 && (io_iSlotCode_2 == 4'h7);
  wire f_isOpref3  = io_iSlotPresent_3 && (io_iSlotCode_3 == 4'h7);
  wire f_isAcctgt0 = io_iSlotPresent_0 && (io_iSlotCode_0 == 4'h9);
  wire f_isAcctgt1 = io_iSlotPresent_1 && (io_iSlotCode_1 == 4'h9);
  wire f_isAcctgt2 = io_iSlotPresent_2 && (io_iSlotCode_2 == 4'h9);
  wire f_isAcctgt3 = io_iSlotPresent_3 && (io_iSlotCode_3 == 4'h9);

  // ── OPREF CRC-4 참조 (§1.4.6 · W5) — 독립 비트-직렬 12단 명시 전개 ──────
  // G(x) = x⁴+x+1 (0b10011), 비반사 · init 0 · xorout 없음. 메시지 = 논리
  // 12b LBID[7]‥[0] ∥ src_kind[3]‥[0] (MSB-first — 물리 슬라이스 순서가
  // 아니라 논리 순서: CRC 니블 body[7:4] 가 물리적으로 둘 사이에 낀다).
  // 단계식: fb = crc[3] ^ m → crc' = {crc[2:0], 1'b0} ^ (fb ? 4'h3 : 4'h0).
  // 함수 금지 규율 그대로 — 매크로 1단 + 중간 wire (수리 기록 2 참조).
  // 기지값 (LBID,src_kind)→CRC: (0x00,0)→0x0 · (0x01,1)→0x6 · (0xA5,2)→0x8 ·
  // (0xFF,2)→0xA — 핀 명세·어셈블러 참조측·RTL elaborate 자기시험과 같은
  // 값. 여기에 상수 자기시험 단언은 두지 않는다 (상수 접힘은 3형 계수가
  // 잡는 부류라 거짓 신호가 된다).
`define WT_C4(c, m) ({c[2:0], 1'b0} ^ ((c[3] ^ (m)) ? 4'h3 : 4'h0))
  wire [3:0] f_c4z = 4'h0; // init 0 (리터럴에는 비트 선택이 안 걸려 이름을 준다)
  wire [3:0] f_c0a = `WT_C4(f_c4z, f_body0[15]);
  wire [3:0] f_c0b = `WT_C4(f_c0a, f_body0[14]);
  wire [3:0] f_c0c = `WT_C4(f_c0b, f_body0[13]);
  wire [3:0] f_c0d = `WT_C4(f_c0c, f_body0[12]);
  wire [3:0] f_c0e = `WT_C4(f_c0d, f_body0[11]);
  wire [3:0] f_c0f = `WT_C4(f_c0e, f_body0[10]);
  wire [3:0] f_c0g = `WT_C4(f_c0f, f_body0[9]);
  wire [3:0] f_c0h = `WT_C4(f_c0g, f_body0[8]);
  wire [3:0] f_c0i = `WT_C4(f_c0h, f_body0[3]);
  wire [3:0] f_c0j = `WT_C4(f_c0i, f_body0[2]);
  wire [3:0] f_c0k = `WT_C4(f_c0j, f_body0[1]);
  wire [3:0] f_crc4_0 = `WT_C4(f_c0k, f_body0[0]);
  wire [3:0] f_c1a = `WT_C4(f_c4z, f_body1[15]);
  wire [3:0] f_c1b = `WT_C4(f_c1a, f_body1[14]);
  wire [3:0] f_c1c = `WT_C4(f_c1b, f_body1[13]);
  wire [3:0] f_c1d = `WT_C4(f_c1c, f_body1[12]);
  wire [3:0] f_c1e = `WT_C4(f_c1d, f_body1[11]);
  wire [3:0] f_c1f = `WT_C4(f_c1e, f_body1[10]);
  wire [3:0] f_c1g = `WT_C4(f_c1f, f_body1[9]);
  wire [3:0] f_c1h = `WT_C4(f_c1g, f_body1[8]);
  wire [3:0] f_c1i = `WT_C4(f_c1h, f_body1[3]);
  wire [3:0] f_c1j = `WT_C4(f_c1i, f_body1[2]);
  wire [3:0] f_c1k = `WT_C4(f_c1j, f_body1[1]);
  wire [3:0] f_crc4_1 = `WT_C4(f_c1k, f_body1[0]);
  wire [3:0] f_c2a = `WT_C4(f_c4z, f_body2[15]);
  wire [3:0] f_c2b = `WT_C4(f_c2a, f_body2[14]);
  wire [3:0] f_c2c = `WT_C4(f_c2b, f_body2[13]);
  wire [3:0] f_c2d = `WT_C4(f_c2c, f_body2[12]);
  wire [3:0] f_c2e = `WT_C4(f_c2d, f_body2[11]);
  wire [3:0] f_c2f = `WT_C4(f_c2e, f_body2[10]);
  wire [3:0] f_c2g = `WT_C4(f_c2f, f_body2[9]);
  wire [3:0] f_c2h = `WT_C4(f_c2g, f_body2[8]);
  wire [3:0] f_c2i = `WT_C4(f_c2h, f_body2[3]);
  wire [3:0] f_c2j = `WT_C4(f_c2i, f_body2[2]);
  wire [3:0] f_c2k = `WT_C4(f_c2j, f_body2[1]);
  wire [3:0] f_crc4_2 = `WT_C4(f_c2k, f_body2[0]);
  wire [3:0] f_c3a = `WT_C4(f_c4z, f_body3[15]);
  wire [3:0] f_c3b = `WT_C4(f_c3a, f_body3[14]);
  wire [3:0] f_c3c = `WT_C4(f_c3b, f_body3[13]);
  wire [3:0] f_c3d = `WT_C4(f_c3c, f_body3[12]);
  wire [3:0] f_c3e = `WT_C4(f_c3d, f_body3[11]);
  wire [3:0] f_c3f = `WT_C4(f_c3e, f_body3[10]);
  wire [3:0] f_c3g = `WT_C4(f_c3f, f_body3[9]);
  wire [3:0] f_c3h = `WT_C4(f_c3g, f_body3[8]);
  wire [3:0] f_c3i = `WT_C4(f_c3h, f_body3[3]);
  wire [3:0] f_c3j = `WT_C4(f_c3i, f_body3[2]);
  wire [3:0] f_c3k = `WT_C4(f_c3j, f_body3[1]);
  wire [3:0] f_crc4_3 = `WT_C4(f_c3k, f_body3[0]);
`undef WT_C4

  // 판정 2종 — 대응 판정 슬라이스만 소비한다. 슬롯별 각자 검산 (§4.2.3 —
  // ≤2 인스턴스가 각자 자기 CRC 를 나른다).
  wire f_oprefCrcBad =                                     // §1.4.6 · W5
    (f_isOpref0 && (f_body0[7:4] != f_crc4_0)) || (f_isOpref1 && (f_body1[7:4] != f_crc4_1)) ||
    (f_isOpref2 && (f_body2[7:4] != f_crc4_2)) || (f_isOpref3 && (f_body3[7:4] != f_crc4_3));
  wire f_srcKindBad =                                      // §1.4.3 표
    (f_isOpref0 && (f_body0[3:0] >= 4'd3)) || (f_isOpref1 && (f_body1[3:0] >= 4'd3)) ||
    (f_isOpref2 && (f_body2[3:0] >= 4'd3)) || (f_isOpref3 && (f_body3[3:0] >= 4'd3));
  // (W4: f_acctgtResvBad 는 삭제 — ACCTGT [23:16] = 총개수 T, 어떤 값도
  //  판정을 울리지 않는다. §1.4.7. 해석의 등가는 아래 f_acctgtTotal 등식.)
  // capability 종결이 맨 앞 (ISA-5) — 능력 밖 사슬은 본문 판정 대상 아님.
  wire f_bodyMal = !io_iCapAbsent && (f_oprefCrcBad || f_srcKindBad);

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
  // ACCTGT 총개수 T = body[7:0] (§1.4.7 · W4) — 예약 판정이었던 자리가 해석
  // 필드가 됐다: T∈1..255 = 선언, 0 = 선언 없음(적법). 판정 불참.
  wire [7:0] f_acctgtTotal =
    (f_isAcctgt0 ? f_body0[7:0] : 8'h0) | (f_isAcctgt1 ? f_body1[7:0] : 8'h0) |
    (f_isAcctgt2 ? f_body2[7:0] : 8'h0) | (f_isAcctgt3 ? f_body3[7:0] : 8'h0);

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
      assert (io_oAcctgtTotal == 8'h0);
    end

    // OperandDecode.resv_not_echoed — 판정 슬라이스 인접 필드의 등가: OPREF
    // CRC 니블 body[7:4] 은 아래 어떤 우변에도 없다 (판정 등급 1비트로만
    // 나간다). ACCTGT body[7:0] 은 W4 부터 판정이 아니라 해석 필드다 —
    // oAcctgtTotal 등식이 그 해석의 참을 잰다 (아래).
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
    // ACCTGT 총개수 T (W4) — 해석·방출의 등가. 게이트는 다른 산출과 같은
    // emit ∧ present (무소비 방출 — 소비자 결선은 파도 밖, B.5 하위 항).
    assert (io_oAcctgtTotal ==
            ((io_oExecValid && f_acctgtPresent) ? f_acctgtTotal : 8'h0));
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

  // ── cover 증인 (cover 태스크에서만 컴파일) ───────────────────────────────
  //
  // 왜 있는가. 위 단언 34개 중 **18개가 문면 그대로 전건 붙은 함의**다 —
  // exec_gate 14개가 전부 `if (!io_oExecValid)` 아래에 있고, fault_sticky 4개는
  // 상승/하강/에피소드/유지 전건을 각각 진다. 나머지 등식들도 전건을 숨긴다:
  // `oMalformed == (iMalformed || f_bodyMal)` 하나가 **두 본문 판정의 논리합**
  // 을 접고, 그 각각이 다시 4슬롯 논리합이다.
  //
  // 그래서 다음 세계들에서 이 태스크는 전원 통과하면서 아무것도 재지 않는다:
  //   · oExecValid 가 영영 0 인 세계 — exec_gate 14개는 참, resv_not_echoed
  //     8개는 우변이 상수 0 이라 자명, 그런데 「해석 산출」은 한 번도 관측되지
  //     않았다.
  //   · oExecValid 가 영영 1 인 세계 — exec_gate 14개가 **공허하게** 참이다.
  //   · 두 판정 중 하나가 도달 불가능한 세계 — 합류 등식은 그대로 참인데
  //     body_resv_judged 가 예고한 판정 2종 중 하나만 재어졌다.
  //   · CRC 니블이 늘 기대값인 세계 · ACCTGT T 가 늘 0 인 세계 —
  //     resv_not_echoed 의 「판정 니블 비반향 · 총개수 해석 방출」이 잴 것
  //     없이 참이다.
  //   · iCapAbsent 가 영영 0 인 세계 — f_bodyMal 의 `!io_iCapAbsent` 접합
  //     (ISA-5 · §1.6.2)이 한 번도 0 을 만들지 않아 미측정이다.
  //   · sticky 가 영영 서지 않는 세계 — fault_sticky 넷 전부 공허하다.
  //
  // 셀 수 게이트도 항진 검사도 이 결을 잡지 못한다: 셀은 32개 그대로 세어지고,
  // `!전건 || 후건` 형태의 `\A` 는 전건이 죽어 있어도 상수로 접히지 않는다.
  // 셀 수 · A 상수성 · 증인 도달, 셋이 각각 다른 공허를 닫는다.
  //
  // cover 태스크 전용 컴파일은 HiuMask·DecodeWalk 선례(-D…_COVER)를 따른다 —
  // prove 모델에는 단언만 들어 태스크별 셀 수가 정확히 대조된다.
`ifdef OPERANDDECODE_COVER
  wire f_ok = f_past_valid && !reset;

  // 본문 판정 2종의 **단독 원인** — f_bodyMal 이 접은 논리합의 각 항이 혼자서
  // 판정을 세우는 조건. 어느 항이 죽어 있어도 합류 등식은 참이므로, 항마다
  // 단독 원인 증인을 요구하는 것이 그 결을 닫는 유일한 수단이다.
  // (W4: acctgt 항은 논리합에서 소멸 — 그 자리의 활성면은 o5 가 잰다.)
  wire f_only_oprefCrc = !io_iCapAbsent && f_oprefCrcBad && !f_srcKindBad;
  wire f_only_srcKind  = !io_iCapAbsent && f_srcKindBad && !f_oprefCrcBad;

  // ── O1..O2 — 판정 무관 통과면의 양 극성 ─────────────────────────────────
  // 각 줄의 `←` 오른쪽이 **그 증인이 살리는 대상**이다: `<Module>.<name>` 은
  // 이 태스크의 `# VERIFIES:` 앵커, 소문자 식별자는 이 하네스의 단언 라벨.
  // 줄번호로 매지 않는다. scripts/lint_witness_map.py 가 참조 실재성만 재고
  // 「그 궤적이 정말 그 전건을 세우는가」는 재지 못한다.
  //
  // O1 ← OperandDecode.exec_gate · OperandDecode.verdict_join ·
  //      OperandDecode.resv_not_echoed
  //     정상 승인이 실제로 난다. 이 증인이 없으면 exec_gate 14개가 「무엇도
  //     유효하지 않은 기계」 위에서 참이고, resv_not_echoed 8개는 우변 상수 0
  //     과의 등식으로 자명해진다. verdict_join 의 oExecValid 등식도 한쪽 극성만
  //     재어진 것이다.
  always @(posedge clk) if (f_ok) o1_accept: cover (io_iValid && io_oExecValid);
  // O2 ← OperandDecode.verdict_join
  //     무효 사이클 — `io_oValid == io_iValid` 가 양 극성에서 재어진다.
  always @(posedge clk) if (f_ok) o2_invalid_cycle: cover (!io_oValid);

  // ── O3..O4 — body_resv_judged 판정 2종의 단독 원인 ──────────────────────
  // O3 ← OperandDecode.body_resv_judged · OperandDecode.verdict_join ·
  //      OperandDecode.exec_gate  (§1.4.6 OPREF CRC-4 불일치 — W5)
  // O4 ← OperandDecode.body_resv_judged · OperandDecode.verdict_join ·
  //      OperandDecode.exec_gate  (§1.4.3 src_kind >= 3)
  // 대응: O3 ↔ §1.4.6 OPREF CRC-4 재계산 대조 · O4 ↔ §1.4.3 src_kind >= 3.
  //       둘 다 「상류는 유효 실행을 내밀었는데
  //       이 모듈이 혼자 꺾는다」 형태다 — 그래야 (a) 합류 등식의 f_bodyMal 항이
  //       그 판정 하나로 살고, (b) exec_gate 15개의 전건 `!oExecValid` 가
  //       **본문 판정 때문에** 성립하는 궤적으로 도달한다. 상류 무효로 도달한
  //       전건(O6)은 이 모듈의 기여를 재지 못한다 — 둘을 갈라야 하는 이유다.
  always @(posedge clk) if (f_ok)
    o3_only_opref_crc: cover (io_iValid && io_iExecValid && f_only_oprefCrc
           && io_oMalformed && !io_oExecValid);
  always @(posedge clk) if (f_ok)
    o4_only_srckind: cover (io_iValid && io_iExecValid && f_only_srcKind
           && io_oMalformed && !io_oExecValid);
  // O5 ← OperandDecode.resv_not_echoed · OperandDecode.body_resv_judged
  //      ACCTGT 총개수 T 가 비0 으로 방출된다 (W4 — 예약 판정이었던 자리가
  //      해석 필드가 됐다: 같은 슬라이스가 판정을 울리지 않고 값으로 나온다.
  //      「T 가 늘 0 인 세계」에서는 oAcctgtTotal 등식이 0==0 으로 자명하다).
  always @(posedge clk) if (f_ok)
    o5_acctgt_total_nonzero: cover (io_oReasmBind_valid && (io_oAcctgtTotal != 8'h0));

  // ── O6..O7 — 합류식의 나머지 두 항 ──────────────────────────────────────
  // O6 ← OperandDecode.exec_gate · OperandDecode.verdict_join
  //     `!oExecValid` 가 **상류 무효**로 도달하는 부류 (본문은 정상). O3..O5 와
  //     짝을 이뤄 exec_gate 전건의 두 원인이 모두 살아 있음을 가른다.
  always @(posedge clk) if (f_ok)
    o6_upstream_invalid: cover (io_iValid && !io_iExecValid && !f_bodyMal && !io_oExecValid);
  // O7 ← OperandDecode.verdict_join
  //     `oMalformed == (iMalformed || f_bodyMal)` 의 **왼쪽 항 단독** — 상류
  //     판정이 본문 판정 없이 그대로 실린다 (verdict_join 무변경 통과면).
  always @(posedge clk) if (f_ok)
    o7_upstream_mal_passthru: cover (io_iValid && io_iMalformed && !f_bodyMal && io_oMalformed);

  // ── O8 — ISA-5 / §1.6.2: 능력 부재가 본문 판정을 잠근다 ─────────────────
  // O8 ← OperandDecode.verdict_join · OperandDecode.body_resv_judged
  // 원시 판정 2종 중 하나가 서 있는데도 iCapAbsent 때문에 mal 이 서지 않는
  // 궤적. 이 증인이 없으면 f_bodyMal 의 `!io_iCapAbsent` 접합이 한 번도 0 을
  // 만들지 않는 세계에서 verdict_join 등식이 성립할 수 있다 — 그 게이트는
  // 미측정이고, capability 배타 단언 2건도 함께 공허해진다.
  always @(posedge clk) if (f_ok)
    o8_capabsent_locks: cover (io_iValid && io_iCapAbsent
           && (f_oprefCrcBad || f_srcKindBad)
           && !io_oMalformed && io_oCapAbsent);

  // ── O9..O10 — 판정 콘의 협소성: 무엇이 판정 대상이 *아닌가* ─────────────
  // O9 ← OperandDecode.body_resv_judged  (§1.6.1 함정)
  //     **부재** 슬롯의 본문 잔여값이 나쁜데도 판정되지 않는다.
  //     f_is* 의 present 접합이 실제로 구분력을 갖는다는 활성면.
  always @(posedge clk) if (f_ok)
    o9_absent_slot_ignored: cover (io_iValid && io_iExecValid && !io_iSlotPresent_0
           && (io_iSlotCode_0 == 4'h7) && (f_body0[7:4] != f_crc4_0)
           && !f_bodyMal && io_oExecValid);
  // O10 ← OperandDecode.body_resv_judged
  //      OPREF·ACCTGT 가 아닌 제3의 실재 슬롯의 같은 슬라이스가 비0 인데
  //     판정되지 않는다 — 4비트 코드 전체 비교가 실제로 갈라낸다. (ACCTGT
  //     의 불판정은 W4 부터 협소성이 아니라 정의다 — 그 활성면은 o5.)
  always @(posedge clk) if (f_ok)
    o10_other_code_ignored: cover (io_iValid && io_iExecValid && io_iSlotPresent_1
           && (io_iSlotCode_1 != 4'h7) && (io_iSlotCode_1 != 4'h9)
           && (f_body1[7:0] != 8'h00) && !f_bodyMal && io_oExecValid);

  // ── O11..O14 — resv_not_echoed 의 활성면 (방출이 실제로 값을 나른다) ────
  // O11 ← OperandDecode.resv_not_echoed
  //      OPREF A 가 **비0 LBID** 로 방출된다. 「LBID 가 늘 0 인 세계」에서는
  //      :254 의 등식이 0==0 으로 자명하다.
  always @(posedge clk) if (f_ok)
    o11_opref_a_nonzero: cover (io_oOprefAValid && (io_oOprefALbid != 8'h0));
  // O12 ← OperandDecode.resv_not_echoed
  //      OPREF 가 둘 — 등장 순서 A·B (§4.2.3) 가 실제로 둘 다 방출된다.
  //      f_b* 참조의 「앞선 OPREF 개수 == 1」 항이 도달한다.
  always @(posedge clk) if (f_ok)
    o12_opref_pair: cover (io_oOprefAValid && io_oOprefBValid && (io_oOprefBLbid != 8'h0)
           && (io_oOprefALbid != io_oOprefBLbid));
  // O13 ← OperandDecode.resv_not_echoed · OperandDecode.body_resv_judged
  //      src_kind 경계 바로 아래 값 2 가 그대로 통과한다 — 판정 문턱
  //      `>= 3` (§1.4.3 표)이 상수 참이 아니라 실제 문턱이다.
  always @(posedge clk) if (f_ok)
    o13_srckind_below_threshold: cover (io_oOprefAValid && (io_oOprefASrcKind == 4'd2));
  // O14 ← OperandDecode.resv_not_echoed
  //      ACCTGT 재조립 결속이 비0 payload 로 열린다 (§4.3 D8 부류의 활성면).
  always @(posedge clk) if (f_ok)
    o14_reasm_bind_nonzero: cover (io_oReasmBind_valid && (io_oReasmBind_payload != 8'h0));

  // ── O15..O18 — fault_sticky 네 전건의 도달성 ────────────────────────────
  // O15 ← OperandDecode.fault_sticky  (:270 상승 전건)
  // O16 ← OperandDecode.fault_sticky  (:273 하강 전건)
  // O17 ← OperandDecode.fault_sticky  (:279 유지 전건)
  // O18 ← OperandDecode.fault_sticky  (:276 에피소드 전건 — 해제 동시 제시에도
  //       세움 우선)
  always @(posedge clk) if (f_ok && !$past(reset))
    o15_fault_rise: cover (io_oFault && !$past(io_oFault));
  always @(posedge clk) if (f_ok && !$past(reset))
    o16_fault_fall: cover (!io_oFault && $past(io_oFault));
  always @(posedge clk) if (f_ok && !$past(reset))
    o17_fault_hold: cover (io_oFault && $past(io_oFault) && !$past(io_iFaultClear));
  always @(posedge clk) if (f_ok && !$past(reset))
    o18_set_beats_clear: cover (io_oFault && $past(io_iFaultClear) && $past(io_iValid && f_bodyMal));

  // ── O19..O20 — sticky 가 접지 *않는* 것 (§5.6 폴딩 명시의 반대면) ────────
  // O19 ← OperandDecode.fault_sticky
  //      능력 부재는 fault 를 세우지 않는다 — :270 의 상승 원인이 bodyMal 로
  //      못박힌 문면이 실제 궤적 위에서 재어진다.
  always @(posedge clk) if (f_ok)
    o19_capabsent_quiet: cover (io_iValid && io_oCapAbsent && !io_oFault);
  // O20 ← OperandDecode.fault_sticky
  //      본문 판정이 서 있어도 iValid 가 없으면 fault 는 서지 않는다 —
  //      :271 의 `iValid` 접합이 살아 있다.
  always @(posedge clk) if (f_ok && !$past(reset))
    o20_no_fault_without_valid: cover (!io_iValid && f_bodyMal && !io_oFault && !$past(io_oFault));
`endif // OPERANDDECODE_COVER

endmodule

// ── formal 전용 래퍼 — bind 의 대체 (파일 머리의 이탈 기록 참조) ───────────
module OperandDecode_formal (
  input  wire        clk,
  input  wire        reset,
  input  wire        iValid, iMalformed, iCapAbsent, iExecValid,
  input  wire [31:0] i0, i1, i2, i3, i4, i5, i6, i7, i8, i9, i10, i11, i12, i13,
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
  wire [7:0] oAcctgtT;

  OperandDecode dut (
    .clk(clk), .reset(reset),
    .io_iValid(iValid), .io_iMalformed(iMalformed),
    .io_iCapAbsent(iCapAbsent), .io_iExecValid(iExecValid),
    .io_iInstr_0(i0), .io_iInstr_1(i1), .io_iInstr_2(i2), .io_iInstr_3(i3),
    .io_iInstr_4(i4), .io_iInstr_5(i5), .io_iInstr_6(i6), .io_iInstr_7(i7),
    .io_iInstr_8(i8), .io_iInstr_9(i9), .io_iInstr_10(i10), .io_iInstr_11(i11),
    .io_iInstr_12(i12), .io_iInstr_13(i13),
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
    .io_oAcctgtTotal(oAcctgtT),
    .io_oFault(oFault)
  );

  OperandDecode_props props (
    .clk(clk), .reset(reset),
    .io_iValid(iValid), .io_iMalformed(iMalformed),
    .io_iCapAbsent(iCapAbsent), .io_iExecValid(iExecValid),
    .io_iInstr_0(i0), .io_iInstr_1(i1), .io_iInstr_2(i2), .io_iInstr_3(i3),
    .io_iInstr_4(i4), .io_iInstr_5(i5), .io_iInstr_6(i6), .io_iInstr_7(i7),
    .io_iInstr_8(i8), .io_iInstr_9(i9), .io_iInstr_10(i10), .io_iInstr_11(i11),
    .io_iInstr_12(i12), .io_iInstr_13(i13),
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
    .io_oAcctgtTotal(oAcctgtT),
    .io_oFault(oFault)
  );
endmodule
