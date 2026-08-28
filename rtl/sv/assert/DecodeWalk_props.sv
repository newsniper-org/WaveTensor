// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// DecodeWalk 후-formal 하네스 (§6.3) — GUARD-MAP CHECK 줄의 참을 구현 RTL 위에서
// 다시 잰다. 방법: 하네스가 명령 버퍼 입력만으로 순회·판정 전체를 독립
// 재유도(참조 모델)하고, RTL 방출면과의 등가를 단언한다. 참조 모델의 원천은
// 정본 §4.2/§1.3 문면과 GUARD-MAP 줄 자체다 — RTL 표현을 옮겨 적은 것이
// 아니라 같은 명세의 두 번째 구현이며, 전 입력 공간에서의 등가가 곧
// CHECK 줄의 참이다.
//
// 부착 방식 (계획 이탈 기록): 원계획은 bind 부착이었으나, 컨테이너의
// yosys 0.66 은 bind 지시어를 파싱만 하고 AST 에 싣지 않는다 (실측 —
// 최소 재현: bind 된 검사 모듈이 "Removing unused module" 로 소거되고
// -dump_ast1 에 bind 노드 부재). 따라서 부착은 이 파일 말미의 formal 전용
// 래퍼(DecodeWalk_formal)가 대신한다. 하네스는 DUT 포트면만 관측하므로
// bind 지원 도구가 오면 래퍼 삭제 + bind 한 줄로 무변경 이행 가능하다.
// 내부 비교기(judge.*) 탭도 같은 이유로 불가 — 각 비교기 주장은 그것의
// 유일한 관측면(1사이클 뒤 방출)에서 검사한다. 판정 비트들은 mal 로
// 접혀 방출되므로 개별 비교기의 상호 상쇄 오류는 이 검사가 원리적으로
// 구별하지 못한다 — 단 접힌 판정 자체는 전 입력에서 등가가 강제된다.
//
// 하네스 결함 수리 기록 (반례 규율 (1)갈래, k-귀납 반례 2건 + 완주 불능 1건):
//  1) 초판은 참조 모델을 always_comb + unpacked 배열 + 공유 임시변수로 썼고,
//     yosys 가 이를 $mem_v2/$anyinit 상태 셀로 컴파일했다 — 귀납 창의 임의
//     초기 상태가 참조값을 오염시켰다. wire 연속 대입으로 평탄화해 수리.
//  2) 평탄화 판에서 연속 대입 우변의 함수 호출(kind_words 등)을 yosys 0.66 이
//     미구동 $func$…$result 와이어로 남겼다 (eval 실측: "Missing value for
//     \kind_defined$func$…") — formal 모델에서 자유 변수가 되어 귀납 반례가
//     참조 판정을 임의로 뒤집었다 (실측 반례: PRECISION EH, 워드 수 필드 0 —
//     RTL judge_mal=1 [iverilog 대조로 옳음 확인], 하네스 f_mal=0 [오염]).
//     함수를 전부 매크로/명시 시프트 와이어로 인라인해 수리했다.
//  3) CH(W8) 도입판은 CRC 참조를 비트-직렬 448단(워드 14 × 비트 32) ITE
//     사슬로 전개했다. mal 등가 단언의 조합 콘에 「같은 GF(2) 선형 함수의
//     구조적으로 정렬 불가능한 두 전개」(비트-직렬 사슬 vs RTL 의 워드 단위
//     행렬 평탄화)의 등가 miter 가 삽입됐고, 비트-블라스트 후 자유 메시지
//     416비트 위의 XOR 등가 문제 — 가우스식 추론 없는 CDCL SAT 의 최악
//     부류 — 가 되어 prove depth 20 이 그것을 basecase·귀납 양쪽에 ~20벌
//     복제했다 (실측: 종전 prove 20초 → 2시간 39분 미완주, z3 이탈 0 =
//     순수 폭발. 참조가 보태는 귀납 *상태*는 0 — 상태 공간 문제가 아니라
//     조합 miter 구조 문제다). 참조를 RTL 과 같은 워드 절단면(15개 상태
//     경계)의 스펙-유도 행렬 상수 전개(wt_crc32c_word_ref, 파일 말미)로
//     재구조해 수리 — 두 콘이 워드 단계별 국소로 닫힌다. 단언·cover 무변경.
//     결과 실측 (2026-08-28): 트리 형상·항 순서·mux 셀형까지 동형이 되어
//     walk_decode.sby 의 flatten+opt 가 두 콘을 물리 병합, CRC 등가 miter 는
//     넷리스트에서 소거되고 k-귀납 귀납 다리가 4분 29초에 닫힌다. 잔여:
//     basecase BMC 의 z3 웨지 (하네스 밖 원인 — .sby 의 미해결 상태 기록).
//
// 검사 대상 가드 (rtl/spinal/.../decode/DecodeWalk.scala GUARD-MAP):
//   Walk.end_authority   — 종료·보폭 콘이 END(0x0)만 소비. 참조 순회는 선언
//                          길이(word0[7:0])·예약(word0[15:12])을 구조적으로
//                          읽지 않는다 — 등가가 곧 불참의 증명이다. (CH 참조
//                          모델은 별개 콘이다 — 전 워드를 읽되 산출은
//                          f_chBad 비교기 하나로만 나간다.)
//   Walk.len_check       — lenBad: endSeen && (declLen != off_final), 8b 전폭.
//   Walk.cap_declared    — capAbsent = declLen > 14, 8b 전폭, 순회 전 선언만.
//   Walk.cap_check       — capBad = !capAbsent && !endSeen — capAbsent 와
//                          서로소 (ISA-5 구조 성립).
//   Walk.junk_check      — junkBad = 표 조회 (16진 코드 전체가 표를 지난다).
//   Walk.post_end_gated  — walked 단조 강하 · END 뒤 off 동결 · 방출 게이트.
//   Decode.resv_judged   — resvBad = (word0[15:12] != 0) 가 mal 에 합류
//                          ([11:8] 은 W1 부터 opcode_ext — 판정하지 않는다).
//   Decode.ch_judged     — chBad = (next_hdr != END) && (CRC-32C 재계산 !=
//                          word1) 가 mal 에 합류 (W8 · §1.3.4). 참조는
//                          스펙-유도 워드 행렬 상수 전개 — RTL elaborate 와
//                          유도 파이프라인이 독립인 같은 명세의 두 번째 구현.
//   Decode.mal_carried   — oMalformed/oCapAbsent == $past(판정) — 소비 지점
//                          전부가 같은 래치 값과 등가 (재계산 없음의 관측형).
//   Decode.resv_not_indexed — 참조 순회의 head 색인이 off>=1 (word0 의 lo16 을
//                          결코 재독하지 않음) + 방출 색인 등가 → 예약 비트가
//                          어떤 색인에도 불참.
//   Decode.resv_not_timed — oValid == $past(iValid): 지연 1 균일, 내용 무관.
//   Decode.resv_not_echoed — oInstr_0[15:12] == 0 상시 + 방출면 전체 등가.
//   Decode.fault_not_folded — oFault 상승은 oMalformed 에피소드에서만,
//                          capability 는 sticky 에 불참 (배타 + 상승 조건).
//   Decode.verdict_ungated — oSlot*·oInstr·oValid 가 판정과 무관한 순수 함수의
//                          $past 와 등가 (D14 상태열 균일 — 판정은 게이트만).
module DecodeWalk_props (
  input  wire        clk,
  input  wire        reset,
  input  wire        io_iValid,
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
  input  wire        io_iFaultClear,
  input  wire        io_oValid,
  input  wire        io_oMalformed,
  input  wire        io_oCapAbsent,
  input  wire        io_oExecValid,
  input  wire [31:0] io_oInstr_0,
  input  wire [31:0] io_oInstr_1,
  input  wire [31:0] io_oInstr_2,
  input  wire [31:0] io_oInstr_3,
  input  wire [31:0] io_oInstr_4,
  input  wire [31:0] io_oInstr_5,
  input  wire [31:0] io_oInstr_6,
  input  wire [31:0] io_oInstr_7,
  input  wire [31:0] io_oInstr_8,
  input  wire [31:0] io_oInstr_9,
  input  wire [31:0] io_oInstr_10,
  input  wire [31:0] io_oInstr_11,
  input  wire [31:0] io_oInstr_12,
  input  wire [31:0] io_oInstr_13,
  input  wire        io_oSlotPresent_0,
  input  wire        io_oSlotPresent_1,
  input  wire        io_oSlotPresent_2,
  input  wire        io_oSlotPresent_3,
  input  wire [3:0]  io_oSlotCode_0,
  input  wire [3:0]  io_oSlotCode_1,
  input  wire [3:0]  io_oSlotCode_2,
  input  wire [3:0]  io_oSlotCode_3,
  input  wire [7:0]  io_oSlotOff_0,
  input  wire [7:0]  io_oSlotOff_1,
  input  wire [7:0]  io_oSlotOff_2,
  input  wire [7:0]  io_oSlotOff_3,
  input  wire        io_oFault
);

  // ── ENV: 부팅 reset 프로토콜 ──────────────────────────────────────────────
  // assume 근거: 리셋 인가 후 해제는 §1.5 (초기 상태 규정) 의 환경 계약이다 —
  // GUARD-MAP 의 어떤 CHECK 줄도 리셋 *중* 의 거동을 주장하지 않으며, 검사
  // 대상 속성 전부가 리셋 해제 후 정상 동작의 문장이다. 입력(iValid·iInstr·
  // iFaultClear)에는 어떤 가정도 걸지 않는다 — 전 입력 공간 검사.
  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;
  always @* begin
    if (!f_past_valid) assume (reset);
    else               assume (!reset);
  end

  // ── 참조 모델 — §4.2/§1.3 의 독립 재구현 (순수 wire — 위 수리 기록 참조) ──
  // ISA 사실 (정본 §1.3.2 카탈로그 + §1.4.7 ACCTGT): 종류 1..9,F 만 정의,
  // 워드 수 {IMM32,MEM,SUBSCRIPT}→2, {IMM64}→3, 나머지 1 (미지 종류의 순회
  // 보폭 1 은 RTL 환류 기록 「미지 EH 보폭 = 1 워드 고정」과 같은 결정).
  // 함수 금지 — 매크로 인라인만 (위 수리 기록 2 참조).
`define WT_KD(p) ((((p) >= 4'h1) && ((p) <= 4'h9)) || ((p) == 4'hF))
`define WT_KW(p) ((((p) == 4'h3) || ((p) == 4'h5) || ((p) == 4'h6)) ? 8'd2 : \
                  (((p) == 4'h4) ? 8'd3 : 8'd1))

  localparam [7:0] MAXW = 8'd14; // 1(기본 헤더) + 1(CH, W8) + 4슬롯 * 3워드 (§1.3)

  // 각 워드의 하위 16비트 — 순회가 읽는 유일한 사슬 표면.
  wire [16*14-1:0] f_lo16bus = {
    io_iInstr_13[15:0], io_iInstr_12[15:0], io_iInstr_11[15:0],
    io_iInstr_10[15:0], io_iInstr_9[15:0],  io_iInstr_8[15:0],
    io_iInstr_7[15:0],  io_iInstr_6[15:0],  io_iInstr_5[15:0],
    io_iInstr_4[15:0],  io_iInstr_3[15:0],  io_iInstr_2[15:0],
    io_iInstr_1[15:0],  io_iInstr_0[15:0] };

  // 순회 — END(사슬 포인터의 0x0)만이 종료 authority (Walk.end_authority).
  // 선언 길이 word0[7:0] 과 예약 word0[15:12] 은 아래 어디에도 등장하지 않는다
  // (head 색인은 항상 >= 1 — word0 의 lo16 은 결코 head 로 재독되지 않는다).
  // 워드 색인은 명시 시프트 — 임의 off 에도 전정의 (표 밖 = 0, §1.3 절단
  // 금지 부류). 시프트 중간 와이어를 두는 것은 함수 금지의 귀결이다.
  // W8: next_hdr ≠ END 이면 word1 = CH(둘째 헤더 — EH 아님·순회 대상 아님)
  // 라 순회 시작 워드가 word2 다 (§4.2.1). = END 면 걷지 않는 시작 1.
  wire [3:0]  f_ptr0  = io_iInstr_0[23:20];
  wire        f_end0  = (f_ptr0 == 4'h0);
  wire        f_wlk0  = !f_end0;
  wire [7:0]  f_off0  = f_end0 ? 8'd1 : 8'd2;
  wire [16*14-1:0] f_sh0 = f_lo16bus >> (f_off0 * 16);
  wire [15:0] f_head0 = f_sh0[15:0];

  wire [3:0]  f_ptr1  = f_head0[15:12];
  wire        f_end1  = f_end0 || (f_ptr1 == 4'h0);
  wire        f_wlk1  = !f_end1;
  // END 뒤 슬롯은 오프셋에 기여하지 않는다 (Walk.post_end_gated).
  wire [7:0]  f_off1  = f_off0 + (f_wlk0 ? `WT_KW(f_ptr0) : 8'd0);
  wire [16*14-1:0] f_sh1 = f_lo16bus >> (f_off1 * 16);
  wire [15:0] f_head1 = f_sh1[15:0];

  wire [3:0]  f_ptr2  = f_head1[15:12];
  wire        f_end2  = f_end1 || (f_ptr2 == 4'h0);
  wire        f_wlk2  = !f_end2;
  wire [7:0]  f_off2  = f_off1 + (f_wlk1 ? `WT_KW(f_ptr1) : 8'd0);
  wire [16*14-1:0] f_sh2 = f_lo16bus >> (f_off2 * 16);
  wire [15:0] f_head2 = f_sh2[15:0];

  wire [3:0]  f_ptr3  = f_head2[15:12];
  wire        f_end3  = f_end2 || (f_ptr3 == 4'h0);
  wire        f_wlk3  = !f_end3;
  wire [7:0]  f_off3  = f_off2 + (f_wlk2 ? `WT_KW(f_ptr2) : 8'd0);
  wire [16*14-1:0] f_sh3 = f_lo16bus >> (f_off3 * 16);
  wire [15:0] f_head3 = f_sh3[15:0];

  wire [3:0]  f_ptr4  = f_head3[15:12];
  wire        f_end4  = f_end3 || (f_ptr4 == 4'h0);
  wire [7:0]  f_off4  = f_off3 + (f_wlk3 ? `WT_KW(f_ptr3) : 8'd0);

  // 판정 — 순회 종료 직후 한 번 (D14).
  wire f_capAbsent = (io_iInstr_0[7:0] > MAXW);              // Walk.cap_declared
  wire f_endSeen   = f_end4;
  wire f_lenBad    = f_endSeen && (io_iInstr_0[7:0] != f_off4); // Walk.len_check
  wire f_capBad    = !f_capAbsent && !f_endSeen;             // Walk.cap_check
  wire f_junkBad   = (f_wlk0 && !`WT_KD(f_ptr0)) ||          // Walk.junk_check
                     (f_wlk1 && !`WT_KD(f_ptr1)) ||
                     (f_wlk2 && !`WT_KD(f_ptr2)) ||
                     (f_wlk3 && !`WT_KD(f_ptr3));
  wire f_selfBad   = (f_wlk0 && (f_head0[11:8] != f_ptr0)) || // 자기 종류 검산
                     (f_wlk1 && (f_head1[11:8] != f_ptr1)) ||
                     (f_wlk2 && (f_head2[11:8] != f_ptr2)) ||
                     (f_wlk3 && (f_head3[11:8] != f_ptr3));
  wire f_wordsBad  = (f_wlk0 && `WT_KD(f_ptr0) && (f_head0[7:0] != `WT_KW(f_ptr0))) ||
                     (f_wlk1 && `WT_KD(f_ptr1) && (f_head1[7:0] != `WT_KW(f_ptr1))) ||
                     (f_wlk2 && `WT_KD(f_ptr2) && (f_head2[7:0] != `WT_KW(f_ptr2))) ||
                     (f_wlk3 && `WT_KD(f_ptr3) && (f_head3[7:0] != `WT_KW(f_ptr3)));

  // §4.2.3 반복 규약 — {PORT,IMM16,IMM32,IMM64,MEM,PRECISION,ACCTGT} <= 1,
  // OPREF <= 2, SUBSCRIPT·NOP_PAD 무제한.
`define WT_OCC(code) \
  ({2'b0, (f_wlk0 && (f_ptr0 == (code)))} + {2'b0, (f_wlk1 && (f_ptr1 == (code)))} + \
   {2'b0, (f_wlk2 && (f_ptr2 == (code)))} + {2'b0, (f_wlk3 && (f_ptr3 == (code)))})
  wire f_dupBad =
    (`WT_OCC(4'h1) > 3'd1) || (`WT_OCC(4'h2) > 3'd1) || (`WT_OCC(4'h3) > 3'd1) ||
    (`WT_OCC(4'h4) > 3'd1) || (`WT_OCC(4'h5) > 3'd1) || (`WT_OCC(4'h8) > 3'd1) ||
    (`WT_OCC(4'h9) > 3'd1) || (`WT_OCC(4'h7) > 3'd2);
`undef WT_OCC

  // W1: 예약은 [15:12] 로 좁아졌다 — [11:8] 은 opcode_ext 라 판정하지 않는다.
  wire f_resvBad = (io_iInstr_0[15:12] != 4'h0);             // Decode.resv_judged

  // ── CH (둘째 헤더, W8 · §1.3.4) 참조 모델 — CRC-32C, RFC 3720 관례 ──────
  // 다항식 0x1EDC6F41(정규형)/0x82F63B78(반사형) · 입출력 반사 · init/xorout
  // 0xFFFFFFFF. 메시지 = CH 자기 워드(word1)를 *제외한* word0·word2‥
  // (bh_len−1), 워드 오름차순 · 워드당 리틀엔디언 바이트 직렬 — 반사 관례
  // + 리틀엔디언이라 워드 안 처리 순서는 정확히 비트 0→31 이고, 그 사실이
  // 워드 스텝 상수의 유도(반사형 우시프트 fb = s[0]^m → s' = (s>>1) ^
  // (fb ? 0x82F63B78 : 0) 를 워드당 32단 GF(2) 합성)의 근거다. 패딩
  // (≥ bh_len) 불포함.
  //
  // 구현 형태 (수리 기록 3 — 재구조): 워드당 모듈 wt_crc32c_word_ref(파일
  // 말미 — 스펙-유도 행렬 상수 S' = A·S ⊕ B·W 의 순수 XOR 전개)를 14단
  // 인스턴스하고, 워드 절단면 15개(상태 경계)를 RTL 의 워드 단위 평탄화와
  // 같은 자리에 둔다 — mal 등가 단언의 두 조합 콘이 동형이 되어 등가가
  // 워드 단계별 국소로 닫힌다 (448단 비트-직렬 사슬 하나로 묶이지 않는다).
  // 독립성 논거는 전개 형태가 아니라 *유도 파이프라인*이다: 이쪽 상수는
  // 곁의 gen_crc32c_matrix.py 가 RFC 3720 비트-직렬 정의만으로 GF(2)
  // 기호 합성해 유도했고(기지값 3종 + 무작위 (S,W) 10^4 스텝 등가 + LE
  // 워드 폴드 교차의 3중 자기시험을 실행마다 전부 재측정 — RTL 무열람),
  // RTL 쪽 상수는 SpinalHDL elaborate 의 평탄화다 — 같은 명세의 독립
  // 두 번째 구현. 함수 금지(수리 기록 2)·표 조회 금지(walk_decode.sby 의
  // $mem_v2 실측) 규율은 그대로고, 단언은 generate 안에 두지 않는다
  // (yosys 0.66 이 generate 안 단언 라벨을 버린다 — ResultBank_props 실측).
  // 기지값 (RFC 3720): "123456789"→0xE3069283 · 32B×0x00→0x8A9136AA ·
  // 32B×0xFF→0x62A8AB43 — 핀 명세와 어셈블러·RTL elaborate 자기시험과
  // gen_crc32c_matrix.py 자기시험이 이 값들을 못박고, 여기서는 상수
  // 자기시험을 두지 않는다 (상수 접힘 단언은 lint_postformal 의 3형 계수가
  // 잡는 부류라 거짓 신호가 된다).
  wire [7:0]       f_bhlen  = io_iInstr_0[7:0];
  wire [32*14-1:0] f_chwbus = {
    io_iInstr_13, io_iInstr_12, io_iInstr_11, io_iInstr_10,
    io_iInstr_9,  io_iInstr_8,  io_iInstr_7,  io_iInstr_6,
    io_iInstr_5,  io_iInstr_4,  io_iInstr_3,  io_iInstr_2,
    io_iInstr_1,  io_iInstr_0 };
  // 메시지 포함 마스크 — word0 상시 · word1(CH 자기 워드) 상시 제외 ·
  // word2.. 는 bh_len 미만일 때만. 비교 형태를 8비트 (상수 < 신호) 로 두는
  // 것은 의미가 아니라 솔버 유도다 — flatten 후 opt_merge 가 단계 mux 를
  // 물리 공유하려면 셀형까지 같아야 한다 (수리 기록 3: $gt(신호,상수) 로
  // 썼더니 mux 불일치가 워드 2 에서 병합 연쇄를 끊었다). 의미는 동일
  // (bh_len > i ⟺ i < bh_len) — 판정 내용은 바뀌지 않는다.
  wire [13:0] f_chincl;
  assign f_chincl[0] = 1'b1;
  assign f_chincl[1] = 1'b0;
  genvar g_ci;
  generate
    for (g_ci = 2; g_ci < 14; g_ci = g_ci + 1) begin : g_chincl
      localparam [7:0] GI = g_ci;
      assign f_chincl[g_ci] = (GI < f_bhlen);
    end
  endgenerate
  // 상태 사슬 — f_chst[32i +: 32] = 워드 i 처리 *전* 상태. 워드 경계
  // 절단면 15개 유지 — 각 단은 워드 스텝 모듈 하나 + 포함 mux 하나다
  // (수리 기록 3).
  wire [32*15-1:0] f_chst;
  assign f_chst[31:0] = 32'hFFFF_FFFF;
  genvar g_cw;
  generate
    for (g_cw = 0; g_cw < 14; g_cw = g_cw + 1) begin : g_chw
      // 이 워드 처리 *후* 상태 (포함 여부와 무관하게 계산 — mux 가 고른다).
      wire [31:0] sn;
      wt_crc32c_word_ref u_ref (
        .s  (f_chst[32*g_cw +: 32]),
        .w  (f_chwbus[32*g_cw +: 32]),
        .sn (sn)
      );
      assign f_chst[32*(g_cw+1) +: 32] =
        f_chincl[g_cw] ? sn : f_chst[32*g_cw +: 32];
    end
  endgenerate
  wire [31:0] f_chcrc = ~f_chst[32*14 +: 32];
  // Decode.ch_judged — EH-조건부: next_hdr = END 면 CH 가 없어 판정이 서지
  // 않는다. bh_len 은 여기서 메시지 경계로만 쓰인다 — 종료 판정·보폭 불참
  // (Walk.end_authority 유지).
  wire f_chBad = f_wlk0 && (f_chcrc != io_iInstr_1);

  // capability 가 맨 앞 — 두 종결의 상호 배타 (ISA-5). 여덟 검산의 논리합.
  wire f_mal = !f_capAbsent &&
               (f_resvBad || f_chBad || f_capBad || f_lenBad || f_junkBad ||
                f_selfBad || f_wordsBad || f_dupBad);
`undef WT_KD
`undef WT_KW

  // ── 조합 단언 — 참조 모델 자체의 구조 상계 + 방출면 등식 ─────────────────
  always @* begin
    // Decode.resv_not_indexed 의 한 축: head 색인은 항상 >= 1 — word0 의
    // lo16(예약 [15:12] 포함)은 결코 head 로 재독되지 않는다. off 상계는
    // RTL 의 resize(4b) 색인이 값을 잃지 않는다는 주석 주장의 재검산
    // (시작 오프셋 상한 2 = CH 존재 갈래, W8).
    assert (f_off0 >= 8'd1 && f_off1 >= 8'd1 && f_off2 >= 8'd1 && f_off3 >= 8'd1);
    assert (f_off3 <= 8'd11 && f_off4 <= 8'd14);
    // ISA-5: 두 종결의 상호 배타 — 방출면 (1-스텝 귀납 성립: 다음 상태의
    // rMal·rCapa 는 구조적으로 배타인 judge 값이다).
    assert (!(io_oMalformed && io_oCapAbsent));
    // Decode.verdict_ungated 의 게이트 등식: 판정은 oExecValid 게이트로만
    // 작용한다 — 경로(상태열)는 가르지 않는다 (아래 클록 단언들이 상태열
    // 균일을 마저 증명한다).
    assert (io_oExecValid == (io_oValid && !io_oMalformed && !io_oCapAbsent));
  end

  // ── 클록 단언 — 판정·서술자·명령의 1사이클 운반 등가 ────────────────────
  always @(posedge clk) begin
    if (f_past_valid) begin
      // Decode.resv_not_echoed: 방출 명령 워드0 의 예약 [15:12] 은 상시 0
      // (레지스터는 리셋 사이클에도 마스킹된 값을 실었다). [11:8] 은
      // opcode_ext(W1) 라 지우지 않는다 — SEC-7 (ii) 재유도.
      assert (io_oInstr_0[15:12] == 4'h0);
      // walked 단조 강하의 방출면 (Walk.post_end_gated — END 뒤 재개 없음).
      // 하네스 결함 수리 기록 (반례 규율 (1)갈래): 처음엔 조합 단언으로 두어
      // 초기 상태(첫 에지 이전, rPresent 무리셋·무의미)까지 주장했다가 반례 —
      // 서술자 레지스터는 첫 래치부터 의미를 갖는다. 그 시점부터로 한정.
      assert (!io_oSlotPresent_1 || io_oSlotPresent_0);
      assert (!io_oSlotPresent_2 || io_oSlotPresent_1);
      assert (!io_oSlotPresent_3 || io_oSlotPresent_2);
    end
    if (f_past_valid && !reset && !$past(reset)) begin
      // Decode.resv_not_timed + D14: 지연 정확히 1, 명령 내용·판정 무관.
      assert (io_oValid == $past(io_iValid));
      // Decode.mal_carried + 판정 등가: 방출 판정 == 참조 판정의 1사이클 지연.
      // Walk.len_check · cap_check · junk_check · resv_judged · §4.2.3 ·
      // 자기종류·워드수 검산 전부가 이 등식의 우변(f_mal)에 접혀 있다.
      assert (io_oMalformed == $past(f_mal));
      // Walk.cap_declared: 선언만으로, 8b 전폭, malformed 와 별도 신호.
      assert (io_oCapAbsent == $past(f_capAbsent));
      // D14 상태열 균일 + Walk.post_end_gated + Walk.end_authority 방출면:
      // 슬롯 서술자는 판정과 무관한 순수 함수의 1사이클 지연 — malformed 여도
      // 순회는 상한까지 완주했고, END 뒤 슬롯은 어떤 값도 방출하지 않는다.
      assert (io_oSlotPresent_0 == $past(f_wlk0));
      assert (io_oSlotPresent_1 == $past(f_wlk1));
      assert (io_oSlotPresent_2 == $past(f_wlk2));
      assert (io_oSlotPresent_3 == $past(f_wlk3));
      assert (io_oSlotCode_0 == $past(f_wlk0 ? f_ptr0 : 4'h0));
      assert (io_oSlotCode_1 == $past(f_wlk1 ? f_ptr1 : 4'h0));
      assert (io_oSlotCode_2 == $past(f_wlk2 ? f_ptr2 : 4'h0));
      assert (io_oSlotCode_3 == $past(f_wlk3 ? f_ptr3 : 4'h0));
      assert (io_oSlotOff_0 == $past(f_wlk0 ? f_off0 : 8'h00));
      assert (io_oSlotOff_1 == $past(f_wlk1 ? f_off1 : 8'h00));
      assert (io_oSlotOff_2 == $past(f_wlk2 ? f_off2 : 8'h00));
      assert (io_oSlotOff_3 == $past(f_wlk3 ? f_off3 : 8'h00));
      // Decode.resv_not_echoed: 방출면 전체 등가 — 워드0 은 예약 [15:12] 만
      // 지워진 원문([11:8] opcode_ext 는 방출 — W1), 나머지 워드는 축자 통과
      // (CH 워드 포함 — 명령 비트열의 결정론적 함수라 신규 구별 인자가
      // 아니다). 같은 판정의 두 명령은 방출면에서 구별 불가.
      assert (io_oInstr_0 == $past({io_iInstr_0[31:16], 4'h0, io_iInstr_0[11:0]}));
      assert (io_oInstr_1  == $past(io_iInstr_1));
      assert (io_oInstr_2  == $past(io_iInstr_2));
      assert (io_oInstr_3  == $past(io_iInstr_3));
      assert (io_oInstr_4  == $past(io_iInstr_4));
      assert (io_oInstr_5  == $past(io_iInstr_5));
      assert (io_oInstr_6  == $past(io_iInstr_6));
      assert (io_oInstr_7  == $past(io_iInstr_7));
      assert (io_oInstr_8  == $past(io_iInstr_8));
      assert (io_oInstr_9  == $past(io_iInstr_9));
      assert (io_oInstr_10 == $past(io_iInstr_10));
      assert (io_oInstr_11 == $past(io_iInstr_11));
      assert (io_oInstr_12 == $past(io_iInstr_12));
      assert (io_oInstr_13 == $past(io_iInstr_13));
      // Decode.fault_not_folded + §5.5 sticky 규율:
      // 상승은 malformation 방출 에피소드에서만 — capability 는 배타(위)라 불참.
      if (io_oFault && !$past(io_oFault))
        assert ($past(io_oValid && io_oMalformed));
      // 하강은 명시적 해제에서만.
      if (!io_oFault && $past(io_oFault))
        assert ($past(io_iFaultClear));
      // 세움은 유실되지 않는다 (해제와 동시 제시 시 세움 우선).
      if ($past(io_oValid && io_oMalformed))
        assert (io_oFault);
      // 해제 없인 내려가지 않는다 (sticky 유지).
      if ($past(io_oFault) && !$past(io_iFaultClear))
        assert (io_oFault);
    end
  end

  // ── cover 증인 (cover 태스크에서만 컴파일) ───────────────────────────────
  //
  // 왜 있는가. 위 단언 41개 중 다수가 *전건이 붙은 함의*(판정 에피소드 ·
  // sticky 상승/하강 · END 뒤 게이트)이고, 결정적으로 등가식 하나
  // (`io_oMalformed == $past(f_mal)`)가 **여덟 검산의 논리합을 통째로 접는다**.
  // 그 논리합의 어느 항이 도달 불가능해도 등가식은 그대로 참이고 증명은
  // 통과한다 — 그런데 그 항에 걸린 CHECK 줄(len_check · junk_check · …)은
  // 아무것도 재지 못한 것이다. 단언만으로는 「참이라서 통과」와 「전제가
  // 도달 불가능해서 통과」를 구별할 수 없다. 아래 증인이 그 구별을 만든다.
  //
  // 항진명제 검사(A 입력 상수 여부)는 이 결을 못 잡는다는 점이 요점이다 —
  // `!전건 || 후건` 형태의 A 는 전건이 죽어 있어도 상수로 접히지 않는다.
  // 셀 수 · A 상수성 · 증인 도달, 셋이 각각 다른 공허를 닫는다.
  //
  // cover 태스크 전용 컴파일은 HiuMask 선례(-DHIUMASK_COVER)를 따른다 —
  // prove 모델은 단언만 들어 태스크별 셀 수가 정확히 대조된다.
`ifdef DECODEWALK_COVER
  reg f_past_reset = 1'b1;
  always @(posedge clk) f_past_reset <= reset;
  wire f_ok = f_past_valid && !reset && !f_past_reset;

  // 단독 원인 — 여덟 검산이 *각각 혼자서* mal 을 세우는 조건. 논리합의 어느
  // 항도 죽어 있지 않다는 것이 각 CHECK 줄의 비공허 조건이다. capability 는
  // 맨 앞 배타항이므로 !f_capAbsent 를 함께 든다 (그래야 「malformed 가 실제로
  // 방출되는」 궤적이다). W8 부터 CH 검산이 여덟째 항이다 — EH ≥ 1 궤적은
  // word1 이 옳은 CRC 일 때만 f_chBad 가 꺼지므로, 다른 항의 단독 원인
  // 증인들도 전부 !f_chBad 를 배제 목록에 든다.
  wire f_only_resv  = !f_capAbsent && f_resvBad &&
    !(f_chBad || f_capBad || f_lenBad || f_junkBad || f_selfBad || f_wordsBad || f_dupBad);
  wire f_only_ch    = !f_capAbsent && f_chBad &&
    !(f_resvBad || f_capBad || f_lenBad || f_junkBad || f_selfBad || f_wordsBad || f_dupBad);
  wire f_only_len   = !f_capAbsent && f_lenBad &&
    !(f_resvBad || f_chBad || f_capBad || f_junkBad || f_selfBad || f_wordsBad || f_dupBad);
  wire f_only_cap   = !f_capAbsent && f_capBad &&
    !(f_resvBad || f_chBad || f_lenBad || f_junkBad || f_selfBad || f_wordsBad || f_dupBad);
  wire f_only_junk  = !f_capAbsent && f_junkBad &&
    !(f_resvBad || f_chBad || f_capBad || f_lenBad || f_selfBad || f_wordsBad || f_dupBad);
  wire f_only_self  = !f_capAbsent && f_selfBad &&
    !(f_resvBad || f_chBad || f_capBad || f_lenBad || f_junkBad || f_wordsBad || f_dupBad);
  wire f_only_words = !f_capAbsent && f_wordsBad &&
    !(f_resvBad || f_chBad || f_capBad || f_lenBad || f_junkBad || f_selfBad || f_dupBad);
  wire f_only_dup   = !f_capAbsent && f_dupBad &&
    !(f_resvBad || f_chBad || f_capBad || f_lenBad || f_junkBad || f_selfBad || f_wordsBad);

  // W1 ← Decode.verdict_ungated
  //      정상 승인이 실제로 난다. 없으면 게이트 등식(oExecValid 조합 단언)과 D14 상태열
  //      균일이 「무엇도 통과하지 않는 기계」 위에서 참이 된다.
  always @(posedge clk) if (f_ok) w1_accept: cover (io_oValid && io_oExecValid);
  // W2 ← Decode.mal_carried
  //      malformed 종결 도달 (등식의 활성면)
  always @(posedge clk) if (f_ok) w2_malformed: cover (io_oValid && io_oMalformed);
  // W3 ← Walk.cap_declared · Walk.cap_check
  //      capability 종결 도달 — ISA-5 배타 단언이 「capAbsent 가 영영 0」으로
  //      자명해지지 않는다.
  always @(posedge clk) if (f_ok) w3_capabsent: cover (io_oValid && io_oCapAbsent);

  // W4..W10 (+W20) — 여덟 검산의 단독 원인. 이것이 `oMalformed == $past(f_mal)`
  //      이 실제로 여덟 CHECK 줄을 나눠 재고 있다는 유일한 증거다. 「단독」이
  //      알맹이다: 원인 하나만 켜진 궤적이 없으면 그 CHECK 줄은 다른 원인에
  //      가려 한 번도 독립으로 재어지지 않는다.
  // W4  ← Decode.resv_judged · Decode.mal_carried
  always @(posedge clk) if (f_ok) w4_only_resv: cover (io_oMalformed && $past(f_only_resv));
  // W5  ← Walk.len_check · Decode.mal_carried
  always @(posedge clk) if (f_ok) w5_only_len: cover (io_oMalformed && $past(f_only_len));
  // W6  ← Walk.cap_check · Decode.mal_carried
  always @(posedge clk) if (f_ok) w6_only_cap: cover (io_oMalformed && $past(f_only_cap));
  // W7  ← Walk.junk_check · Decode.mal_carried
  always @(posedge clk) if (f_ok) w7_only_junk: cover (io_oMalformed && $past(f_only_junk));
  // W8  ← Decode.mal_carried — 자기 종류 검산 (전용 가드 없음: 이 축은
  //       mal 합성의 한 항이고 그 합성의 단일 원천 주장이 mal_carried 다)
  always @(posedge clk) if (f_ok) w8_only_self: cover (io_oMalformed && $past(f_only_self));
  // W9  ← Decode.mal_carried — 워드 수 검산 (같은 사유)
  always @(posedge clk) if (f_ok) w9_only_words: cover (io_oMalformed && $past(f_only_words));
  // W10 ← Decode.mal_carried — §4.2.3 반복 규약 (같은 사유)
  always @(posedge clk) if (f_ok) w10_only_dup: cover (io_oMalformed && $past(f_only_dup));

  // W11 ← Walk.post_end_gated · Decode.resv_not_indexed
  //       4슬롯 완주: 단조 사슬(oSlotPresent 단조 강하 3건)과 서술자 등식이
  //       사슬 끝까지 간다 (전부 END 인 세계에서는 그 단조가 자명하다)
  always @(posedge clk) if (f_ok) w11_four_slots: cover (io_oValid && io_oSlotPresent_3);
  // W12 ← Walk.end_authority
  //       즉시 END: 슬롯 0개. 사슬 포인터 0x0 하나가 곧 종료라는 것이
  //       실제로 관측된다.
  always @(posedge clk) if (f_ok) w12_immediate_end: cover (io_oValid && !io_oSlotPresent_0);
  // W13 ← Walk.post_end_gated · Decode.resv_not_indexed
  //       off 상계 도달: 앞 세 슬롯이 3워드씩이면 oSlotOff_3 = 11 (시작 2 =
  //       CH 갈래, W8). 조합 단언의 상계(f_off3 <= 11)가 느슨한 상한이
  //       아니라 실제로 닿는 값이라는 증거.
  always @(posedge clk) if (f_ok)
    w13_off_bound: cover (io_oValid && io_oSlotPresent_3 && (io_oSlotOff_3 == 8'd11));

  // W14 ← Decode.fault_not_folded
  //       sticky 상승이 실제로 난다 (상승 함의의 전건 도달성)
  always @(posedge clk) if (f_ok) w14_fault_rise: cover (io_oFault && !$past(io_oFault));
  // W15 ← Decode.fault_not_folded
  //       sticky 하강이 실제로 가능하다. 이 증인이 없으면 「해제 없인
  //       내려가지 않는다」가 「영영 내려가지 않는다」로 자명해진다.
  always @(posedge clk) if (f_ok) w15_fault_fall: cover (!io_oFault && $past(io_oFault));
  // W16 ← Decode.fault_not_folded
  //       유지 구간 (해제 미제시) — sticky 유지 함의의 전건 도달성
  always @(posedge clk) if (f_ok)
    w16_fault_hold: cover (io_oFault && $past(io_oFault) && !$past(io_iFaultClear));
  // W17 ← Walk.cap_declared · Decode.fault_not_folded
  //       능력 부재는 fault 를 세우지 않는다 (cap_declared 의 「StickyFault
  //      불참」). 상승 함의는 상승 *원인*을 malformed 로 못박을 뿐이고, 능력
  //      부재가 fault 없이 지나가는 궤적을 보여야 그 문면이 재어진다.
  always @(posedge clk) if (f_ok) w17_capabsent_quiet: cover (io_oValid && io_oCapAbsent && !io_oFault);

  // W18 ← Decode.resv_not_echoed · Decode.resv_not_indexed
  //       예약 비트([15:12], W1)가 비0 인 명령이 실제로 방출면을 지난다.
  //      resv_not_echoed 의 마스킹 단언이 「예약이 늘 0 인 세계」에서
  //      자명해지지 않는다. 구조 skip 으로 닫은 Decode.out_no_reason 의
  //      관측 가능한 잔여분이 이 증인 위에서 재어진다 (walk_decode.sby 의
  //      STRUCTURAL 절 참조).
  always @(posedge clk) if (f_ok) w18_resv_nonzero: cover (io_oValid && ($past(io_iInstr_0[15:12]) != 4'h0));
  // W19 ← Decode.resv_not_timed
  //       무효 사이클 — 지연 등식이 양 극성에서 재어진다 (늘 유효한
  //       세계에서는 절반만 실측된 것이다)
  always @(posedge clk) if (f_ok) w19_invalid_cycle: cover (!io_oValid);

  // W20 ← Decode.ch_judged · Decode.mal_carried
  //       CH 단독 원인 (W8) — 여덟 검산의 논리합에서 재계산 대조 불일치
  //       하나만 켜진 궤적. 이것이 없으면 f_chBad 항이 죽어 있어도
  //       `oMalformed == $past(f_mal)` 은 그대로 참이고, ch_judged 의
  //       CHECK 줄은 아무것도 재지 못한 것이다.
  always @(posedge clk) if (f_ok) w20_only_ch: cover (io_oMalformed && $past(f_only_ch));
  // W21 ← Decode.ch_judged
  //       CH-ok 도달 — EH ≥ 1 (word1 = CH 실재) 명령이 재계산 대조를
  //       통과해 실행 유효로 방출된다. 이 증인이 없으면 「CH 있는 명령이
  //       전부 거절되는 세계」(참조·RTL 이 같은 방식으로 틀린 경우까지
  //       포함)에서 등가 단언이 자명하게 참일 수 있다 — 대조 일치의 양
  //       극성 중 통과 쪽이 실재함을 못박는다.
  always @(posedge clk) if (f_ok) w21_ch_ok: cover (io_oExecValid && $past(f_wlk0));
  // W22 ← Decode.ch_judged
  //       EH-0 판정 부재 — next_hdr = END 면 word1 은 CH 가 아니라 버퍼
  //       잔여이고 어떤 값이어도 판정이 서지 않는다 (EH-조건부 존재의
  //       반대 극성 — §1.3.4 「EH-0 명령에는 CH 가 없다」).
  always @(posedge clk) if (f_ok)
    w22_eh0_unjudged: cover (io_oExecValid && $past(f_end0) && ($past(io_iInstr_1) != 32'h0));
`endif // DECODEWALK_COVER

endmodule

// ── formal 전용 래퍼 — bind 의 대체 (파일 머리의 이탈 기록 참조) ───────────
// 생성물은 손대지 않고 여기서 인스턴스만 한다. 래퍼 입력이 자유 변수 =
// 전 입력 공간 검사.
module DecodeWalk_formal (
  input  wire        clk,
  input  wire        reset,
  input  wire        iValid,
  input  wire [31:0] i0, i1, i2, i3, i4, i5, i6, i7, i8, i9, i10, i11, i12, i13,
  input  wire        iFaultClear
);
  wire oValid, oMalformed, oCapAbsent, oExecValid, oFault;
  wire [31:0] o0, o1, o2, o3, o4, o5, o6, o7, o8, o9, o10, o11, o12, o13;
  wire oP0, oP1, oP2, oP3;
  wire [3:0] oC0, oC1, oC2, oC3;
  wire [7:0] oO0, oO1, oO2, oO3;

  DecodeWalk dut (
    .clk(clk), .reset(reset),
    .io_iValid(iValid),
    .io_iInstr_0(i0), .io_iInstr_1(i1), .io_iInstr_2(i2), .io_iInstr_3(i3),
    .io_iInstr_4(i4), .io_iInstr_5(i5), .io_iInstr_6(i6), .io_iInstr_7(i7),
    .io_iInstr_8(i8), .io_iInstr_9(i9), .io_iInstr_10(i10), .io_iInstr_11(i11),
    .io_iInstr_12(i12), .io_iInstr_13(i13),
    .io_iFaultClear(iFaultClear),
    .io_oValid(oValid), .io_oMalformed(oMalformed), .io_oCapAbsent(oCapAbsent),
    .io_oExecValid(oExecValid),
    .io_oInstr_0(o0), .io_oInstr_1(o1), .io_oInstr_2(o2), .io_oInstr_3(o3),
    .io_oInstr_4(o4), .io_oInstr_5(o5), .io_oInstr_6(o6), .io_oInstr_7(o7),
    .io_oInstr_8(o8), .io_oInstr_9(o9), .io_oInstr_10(o10), .io_oInstr_11(o11),
    .io_oInstr_12(o12), .io_oInstr_13(o13),
    .io_oSlotPresent_0(oP0), .io_oSlotPresent_1(oP1),
    .io_oSlotPresent_2(oP2), .io_oSlotPresent_3(oP3),
    .io_oSlotCode_0(oC0), .io_oSlotCode_1(oC1),
    .io_oSlotCode_2(oC2), .io_oSlotCode_3(oC3),
    .io_oSlotOff_0(oO0), .io_oSlotOff_1(oO1),
    .io_oSlotOff_2(oO2), .io_oSlotOff_3(oO3),
    .io_oFault(oFault)
  );

  DecodeWalk_props props (
    .clk(clk), .reset(reset),
    .io_iValid(iValid),
    .io_iInstr_0(i0), .io_iInstr_1(i1), .io_iInstr_2(i2), .io_iInstr_3(i3),
    .io_iInstr_4(i4), .io_iInstr_5(i5), .io_iInstr_6(i6), .io_iInstr_7(i7),
    .io_iInstr_8(i8), .io_iInstr_9(i9), .io_iInstr_10(i10), .io_iInstr_11(i11),
    .io_iInstr_12(i12), .io_iInstr_13(i13),
    .io_iFaultClear(iFaultClear),
    .io_oValid(oValid), .io_oMalformed(oMalformed), .io_oCapAbsent(oCapAbsent),
    .io_oExecValid(oExecValid),
    .io_oInstr_0(o0), .io_oInstr_1(o1), .io_oInstr_2(o2), .io_oInstr_3(o3),
    .io_oInstr_4(o4), .io_oInstr_5(o5), .io_oInstr_6(o6), .io_oInstr_7(o7),
    .io_oInstr_8(o8), .io_oInstr_9(o9), .io_oInstr_10(o10), .io_oInstr_11(o11),
    .io_oInstr_12(o12), .io_oInstr_13(o13),
    .io_oSlotPresent_0(oP0), .io_oSlotPresent_1(oP1),
    .io_oSlotPresent_2(oP2), .io_oSlotPresent_3(oP3),
    .io_oSlotCode_0(oC0), .io_oSlotCode_1(oC1),
    .io_oSlotCode_2(oC2), .io_oSlotCode_3(oC3),
    .io_oSlotOff_0(oO0), .io_oSlotOff_1(oO1),
    .io_oSlotOff_2(oO2), .io_oSlotOff_3(oO3),
    .io_oFault(oFault)
  );
endmodule

// ── CRC-32C 워드 스텝 참조 — 스펙-유도 행렬 상수 (수리 기록 3) ────────────
//
// S' = A·S ⊕ B·W (GF(2), 상수항 없음). A·B 의 유도 출처는 RFC 3720 의
// 반사형 비트-직렬 정의뿐이다 — 곁의 gen_crc32c_matrix.py 가 워드당
// 32 비트-스텝을 기호 합성해 만들었고, 실행마다 (i) 무작위 (S,W) 10^4
// 스텝 등가 (ii) RFC 3720 기지값 3종 (iii) LE 워드 폴드 == 바이트
// 비트-직렬 교차 검사를 전부 다시 잰다. RTL 을 읽지 않는다 (clean-room).
// 아래 본문은 그 스크립트의 출력 그대로다 — XOR 항 총 1068개,
// 함수·표·감산 없음 (yosys 0.66 규율: 함수 미구동·$mem_v2 귀납 임의화).
module wt_crc32c_word_ref (
  input  wire [31:0] s,   // 워드 처리 전 상태
  input  wire [31:0] w,   // 메시지 워드 (LE 직렬화 → 비트 0→31)
  output wire [31:0] sn   // 워드 처리 후 상태
);
  assign sn[0] = (((((s[1] ^ s[2]) ^ (s[4] ^ s[5])) ^ ((s[6] ^ s[7]) ^ (s[9] ^
    (s[11] ^ s[14])))) ^ (((s[15] ^ s[16]) ^ (s[20] ^ s[23])) ^ ((s[24] ^
    s[25]) ^ (s[26] ^ (s[27] ^ s[28]))))) ^ ((((w[1] ^ w[2]) ^ (w[4] ^ w[5]))
    ^ ((w[6] ^ w[7]) ^ (w[9] ^ (w[11] ^ w[14])))) ^ (((w[15] ^ w[16]) ^ (w[20]
    ^ w[23])) ^ ((w[24] ^ w[25]) ^ (w[26] ^ (w[27] ^ w[28]))))));
  assign sn[1] = (((((s[2] ^ s[3]) ^ (s[5] ^ s[6])) ^ ((s[7] ^ s[8]) ^ (s[10]
    ^ (s[12] ^ s[15])))) ^ (((s[16] ^ s[17]) ^ (s[21] ^ s[24])) ^ ((s[25] ^
    s[26]) ^ (s[27] ^ (s[28] ^ s[29]))))) ^ ((((w[2] ^ w[3]) ^ (w[5] ^ w[6]))
    ^ ((w[7] ^ w[8]) ^ (w[10] ^ (w[12] ^ w[15])))) ^ (((w[16] ^ w[17]) ^
    (w[21] ^ w[24])) ^ ((w[25] ^ w[26]) ^ (w[27] ^ (w[28] ^ w[29]))))));
  assign sn[2] = (((((s[3] ^ s[4]) ^ (s[6] ^ s[7])) ^ ((s[8] ^ s[9]) ^ (s[11]
    ^ (s[13] ^ s[16])))) ^ (((s[17] ^ s[18]) ^ (s[22] ^ s[25])) ^ ((s[26] ^
    s[27]) ^ (s[28] ^ (s[29] ^ s[30]))))) ^ ((((w[3] ^ w[4]) ^ (w[6] ^ w[7]))
    ^ ((w[8] ^ w[9]) ^ (w[11] ^ (w[13] ^ w[16])))) ^ (((w[17] ^ w[18]) ^
    (w[22] ^ w[25])) ^ ((w[26] ^ w[27]) ^ (w[28] ^ (w[29] ^ w[30]))))));
  assign sn[3] = (((((s[0] ^ s[4]) ^ (s[5] ^ s[7])) ^ ((s[8] ^ s[9]) ^ (s[10]
    ^ (s[12] ^ s[14])))) ^ (((s[17] ^ s[18]) ^ (s[19] ^ (s[23] ^ s[26]))) ^
    ((s[27] ^ s[28]) ^ (s[29] ^ (s[30] ^ s[31]))))) ^ ((((w[0] ^ w[4]) ^ (w[5]
    ^ w[7])) ^ ((w[8] ^ w[9]) ^ (w[10] ^ (w[12] ^ w[14])))) ^ (((w[17] ^
    w[18]) ^ (w[19] ^ (w[23] ^ w[26]))) ^ ((w[27] ^ w[28]) ^ (w[29] ^ (w[30] ^
    w[31]))))));
  assign sn[4] = (((((s[0] ^ s[2]) ^ (s[4] ^ s[7])) ^ ((s[8] ^ s[10]) ^ (s[13]
    ^ s[14]))) ^ (((s[16] ^ s[18]) ^ (s[19] ^ s[23])) ^ ((s[25] ^ s[26]) ^
    (s[29] ^ (s[30] ^ s[31]))))) ^ ((((w[0] ^ w[2]) ^ (w[4] ^ w[7])) ^ ((w[8]
    ^ w[10]) ^ (w[13] ^ w[14]))) ^ (((w[16] ^ w[18]) ^ (w[19] ^ w[23])) ^
    ((w[25] ^ w[26]) ^ (w[29] ^ (w[30] ^ w[31]))))));
  assign sn[5] = ((((s[0] ^ (s[2] ^ s[3])) ^ ((s[4] ^ s[6]) ^ (s[7] ^ s[8])))
    ^ (((s[16] ^ s[17]) ^ (s[19] ^ s[23])) ^ ((s[25] ^ s[28]) ^ (s[30] ^
    s[31])))) ^ (((w[0] ^ (w[2] ^ w[3])) ^ ((w[4] ^ w[6]) ^ (w[7] ^ w[8]))) ^
    (((w[16] ^ w[17]) ^ (w[19] ^ w[23])) ^ ((w[25] ^ w[28]) ^ (w[30] ^
    w[31])))));
  assign sn[6] = (((((s[2] ^ s[3]) ^ (s[6] ^ s[8])) ^ ((s[11] ^ s[14]) ^
    (s[15] ^ s[16]))) ^ (((s[17] ^ s[18]) ^ (s[23] ^ s[25])) ^ ((s[27] ^
    s[28]) ^ (s[29] ^ s[31])))) ^ ((((w[2] ^ w[3]) ^ (w[6] ^ w[8])) ^ ((w[11]
    ^ w[14]) ^ (w[15] ^ w[16]))) ^ (((w[17] ^ w[18]) ^ (w[23] ^ w[25])) ^
    ((w[27] ^ w[28]) ^ (w[29] ^ w[31])))));
  assign sn[7] = (((((s[0] ^ s[1]) ^ (s[2] ^ s[3])) ^ ((s[5] ^ s[6]) ^ (s[11]
    ^ (s[12] ^ s[14])))) ^ (((s[17] ^ s[18]) ^ (s[19] ^ s[20])) ^ ((s[23] ^
    s[25]) ^ (s[27] ^ (s[29] ^ s[30]))))) ^ ((((w[0] ^ w[1]) ^ (w[2] ^ w[3]))
    ^ ((w[5] ^ w[6]) ^ (w[11] ^ (w[12] ^ w[14])))) ^ (((w[17] ^ w[18]) ^
    (w[19] ^ w[20])) ^ ((w[23] ^ w[25]) ^ (w[27] ^ (w[29] ^ w[30]))))));
  assign sn[8] = (((((s[1] ^ s[2]) ^ (s[3] ^ s[4])) ^ ((s[6] ^ s[7]) ^ (s[12]
    ^ (s[13] ^ s[15])))) ^ (((s[18] ^ s[19]) ^ (s[20] ^ s[21])) ^ ((s[24] ^
    s[26]) ^ (s[28] ^ (s[30] ^ s[31]))))) ^ ((((w[1] ^ w[2]) ^ (w[3] ^ w[4]))
    ^ ((w[6] ^ w[7]) ^ (w[12] ^ (w[13] ^ w[15])))) ^ (((w[18] ^ w[19]) ^
    (w[20] ^ w[21])) ^ ((w[24] ^ w[26]) ^ (w[28] ^ (w[30] ^ w[31]))))));
  assign sn[9] = (((((s[0] ^ s[1]) ^ (s[3] ^ s[6])) ^ ((s[8] ^ s[9]) ^ (s[11]
    ^ (s[13] ^ s[15])))) ^ (((s[19] ^ s[21]) ^ (s[22] ^ s[23])) ^ ((s[24] ^
    s[26]) ^ (s[28] ^ (s[29] ^ s[31]))))) ^ ((((w[0] ^ w[1]) ^ (w[3] ^ w[6]))
    ^ ((w[8] ^ w[9]) ^ (w[11] ^ (w[13] ^ w[15])))) ^ (((w[19] ^ w[21]) ^
    (w[22] ^ w[23])) ^ ((w[24] ^ w[26]) ^ (w[28] ^ (w[29] ^ w[31]))))));
  assign sn[10] = ((((s[5] ^ s[6]) ^ (s[10] ^ (s[11] ^ s[12]))) ^ ((s[15] ^
    (s[22] ^ s[26])) ^ (s[28] ^ (s[29] ^ s[30])))) ^ (((w[5] ^ w[6]) ^ (w[10]
    ^ (w[11] ^ w[12]))) ^ ((w[15] ^ (w[22] ^ w[26])) ^ (w[28] ^ (w[29] ^
    w[30])))));
  assign sn[11] = ((((s[0] ^ (s[6] ^ s[7])) ^ (s[11] ^ (s[12] ^ s[13]))) ^
    ((s[16] ^ (s[23] ^ s[27])) ^ (s[29] ^ (s[30] ^ s[31])))) ^ (((w[0] ^ (w[6]
    ^ w[7])) ^ (w[11] ^ (w[12] ^ w[13]))) ^ ((w[16] ^ (w[23] ^ w[27])) ^
    (w[29] ^ (w[30] ^ w[31])))));
  assign sn[12] = (((((s[2] ^ s[4]) ^ (s[5] ^ s[6])) ^ ((s[8] ^ s[9]) ^ (s[11]
    ^ (s[12] ^ s[13])))) ^ (((s[15] ^ s[16]) ^ (s[17] ^ (s[20] ^ s[23]))) ^
    ((s[25] ^ s[26]) ^ (s[27] ^ (s[30] ^ s[31]))))) ^ ((((w[2] ^ w[4]) ^ (w[5]
    ^ w[6])) ^ ((w[8] ^ w[9]) ^ (w[11] ^ (w[12] ^ w[13])))) ^ (((w[15] ^
    w[16]) ^ (w[17] ^ (w[20] ^ w[23]))) ^ ((w[25] ^ w[26]) ^ (w[27] ^ (w[30] ^
    w[31]))))));
  assign sn[13] = (((((s[0] ^ s[1]) ^ (s[2] ^ s[3])) ^ ((s[4] ^ s[10]) ^
    (s[11] ^ s[12]))) ^ (((s[13] ^ s[15]) ^ (s[17] ^ s[18])) ^ ((s[20] ^
    s[21]) ^ (s[23] ^ (s[25] ^ s[31]))))) ^ ((((w[0] ^ w[1]) ^ (w[2] ^ w[3]))
    ^ ((w[4] ^ w[10]) ^ (w[11] ^ w[12]))) ^ (((w[13] ^ w[15]) ^ (w[17] ^
    w[18])) ^ ((w[20] ^ w[21]) ^ (w[23] ^ (w[25] ^ w[31]))))));
  assign sn[14] = (((((s[3] ^ s[6]) ^ (s[7] ^ s[9])) ^ ((s[12] ^ s[13]) ^
    (s[15] ^ s[18]))) ^ (((s[19] ^ s[20]) ^ (s[21] ^ s[22])) ^ ((s[23] ^
    s[25]) ^ (s[27] ^ s[28])))) ^ ((((w[3] ^ w[6]) ^ (w[7] ^ w[9])) ^ ((w[12]
    ^ w[13]) ^ (w[15] ^ w[18]))) ^ (((w[19] ^ w[20]) ^ (w[21] ^ w[22])) ^
    ((w[23] ^ w[25]) ^ (w[27] ^ w[28])))));
  assign sn[15] = (((((s[0] ^ s[4]) ^ (s[7] ^ s[8])) ^ ((s[10] ^ s[13]) ^
    (s[14] ^ s[16]))) ^ (((s[19] ^ s[20]) ^ (s[21] ^ s[22])) ^ ((s[23] ^
    s[24]) ^ (s[26] ^ (s[28] ^ s[29]))))) ^ ((((w[0] ^ w[4]) ^ (w[7] ^ w[8]))
    ^ ((w[10] ^ w[13]) ^ (w[14] ^ w[16]))) ^ (((w[19] ^ w[20]) ^ (w[21] ^
    w[22])) ^ ((w[23] ^ w[24]) ^ (w[26] ^ (w[28] ^ w[29]))))));
  assign sn[16] = (((((s[0] ^ s[1]) ^ (s[5] ^ s[8])) ^ ((s[9] ^ s[11]) ^
    (s[14] ^ (s[15] ^ s[17])))) ^ (((s[20] ^ s[21]) ^ (s[22] ^ s[23])) ^
    ((s[24] ^ s[25]) ^ (s[27] ^ (s[29] ^ s[30]))))) ^ ((((w[0] ^ w[1]) ^ (w[5]
    ^ w[8])) ^ ((w[9] ^ w[11]) ^ (w[14] ^ (w[15] ^ w[17])))) ^ (((w[20] ^
    w[21]) ^ (w[22] ^ w[23])) ^ ((w[24] ^ w[25]) ^ (w[27] ^ (w[29] ^
    w[30]))))));
  assign sn[17] = (((((s[1] ^ s[2]) ^ (s[6] ^ s[9])) ^ ((s[10] ^ s[12]) ^
    (s[15] ^ (s[16] ^ s[18])))) ^ (((s[21] ^ s[22]) ^ (s[23] ^ s[24])) ^
    ((s[25] ^ s[26]) ^ (s[28] ^ (s[30] ^ s[31]))))) ^ ((((w[1] ^ w[2]) ^ (w[6]
    ^ w[9])) ^ ((w[10] ^ w[12]) ^ (w[15] ^ (w[16] ^ w[18])))) ^ (((w[21] ^
    w[22]) ^ (w[23] ^ w[24])) ^ ((w[25] ^ w[26]) ^ (w[28] ^ (w[30] ^
    w[31]))))));
  assign sn[18] = (((((s[0] ^ s[1]) ^ (s[3] ^ s[4])) ^ ((s[5] ^ s[6]) ^ (s[9]
    ^ (s[10] ^ s[13])))) ^ (((s[14] ^ s[15]) ^ (s[17] ^ s[19])) ^ ((s[20] ^
    s[22]) ^ (s[28] ^ (s[29] ^ s[31]))))) ^ ((((w[0] ^ w[1]) ^ (w[3] ^ w[4]))
    ^ ((w[5] ^ w[6]) ^ (w[9] ^ (w[10] ^ w[13])))) ^ (((w[14] ^ w[15]) ^ (w[17]
    ^ w[19])) ^ ((w[20] ^ w[22]) ^ (w[28] ^ (w[29] ^ w[31]))))));
  assign sn[19] = ((((s[9] ^ s[10]) ^ (s[18] ^ (s[21] ^ s[24]))) ^ ((s[25] ^
    (s[26] ^ s[27])) ^ (s[28] ^ (s[29] ^ s[30])))) ^ (((w[9] ^ w[10]) ^ (w[18]
    ^ (w[21] ^ w[24]))) ^ ((w[25] ^ (w[26] ^ w[27])) ^ (w[28] ^ (w[29] ^
    w[30])))));
  assign sn[20] = ((((s[10] ^ s[11]) ^ (s[19] ^ (s[22] ^ s[25]))) ^ ((s[26] ^
    (s[27] ^ s[28])) ^ (s[29] ^ (s[30] ^ s[31])))) ^ (((w[10] ^ w[11]) ^
    (w[19] ^ (w[22] ^ w[25]))) ^ ((w[26] ^ (w[27] ^ w[28])) ^ (w[29] ^ (w[30]
    ^ w[31])))));
  assign sn[21] = (((((s[1] ^ s[2]) ^ (s[4] ^ s[5])) ^ ((s[6] ^ s[7]) ^ (s[9]
    ^ s[12]))) ^ (((s[14] ^ s[15]) ^ (s[16] ^ s[24])) ^ ((s[25] ^ s[29]) ^
    (s[30] ^ s[31])))) ^ ((((w[1] ^ w[2]) ^ (w[4] ^ w[5])) ^ ((w[6] ^ w[7]) ^
    (w[9] ^ w[12]))) ^ (((w[14] ^ w[15]) ^ (w[16] ^ w[24])) ^ ((w[25] ^ w[29])
    ^ (w[30] ^ w[31])))));
  assign sn[22] = (((((s[0] ^ s[1]) ^ (s[3] ^ s[4])) ^ ((s[8] ^ s[9]) ^ (s[10]
    ^ (s[11] ^ s[13])))) ^ (((s[14] ^ s[17]) ^ (s[20] ^ s[23])) ^ ((s[24] ^
    s[27]) ^ (s[28] ^ (s[30] ^ s[31]))))) ^ ((((w[0] ^ w[1]) ^ (w[3] ^ w[4]))
    ^ ((w[8] ^ w[9]) ^ (w[10] ^ (w[11] ^ w[13])))) ^ (((w[14] ^ w[17]) ^
    (w[20] ^ w[23])) ^ ((w[24] ^ w[27]) ^ (w[28] ^ (w[30] ^ w[31]))))));
  assign sn[23] = ((((s[6] ^ (s[7] ^ s[10])) ^ (s[12] ^ (s[16] ^ s[18]))) ^
    ((s[20] ^ (s[21] ^ s[23])) ^ ((s[26] ^ s[27]) ^ (s[29] ^ s[31])))) ^
    (((w[6] ^ (w[7] ^ w[10])) ^ (w[12] ^ (w[16] ^ w[18]))) ^ ((w[20] ^ (w[21]
    ^ w[23])) ^ ((w[26] ^ w[27]) ^ (w[29] ^ w[31])))));
  assign sn[24] = (((((s[0] ^ s[1]) ^ (s[2] ^ (s[4] ^ s[5]))) ^ ((s[6] ^ s[8])
    ^ (s[9] ^ (s[13] ^ s[14])))) ^ (((s[15] ^ s[16]) ^ (s[17] ^ (s[19] ^
    s[20]))) ^ ((s[21] ^ (s[22] ^ s[23])) ^ (s[25] ^ (s[26] ^ s[30]))))) ^
    ((((w[0] ^ w[1]) ^ (w[2] ^ (w[4] ^ w[5]))) ^ ((w[6] ^ w[8]) ^ (w[9] ^
    (w[13] ^ w[14])))) ^ (((w[15] ^ w[16]) ^ (w[17] ^ (w[19] ^ w[20]))) ^
    ((w[21] ^ (w[22] ^ w[23])) ^ (w[25] ^ (w[26] ^ w[30]))))));
  assign sn[25] = (((((s[1] ^ s[2]) ^ (s[3] ^ (s[5] ^ s[6]))) ^ ((s[7] ^ s[9])
    ^ (s[10] ^ (s[14] ^ s[15])))) ^ (((s[16] ^ s[17]) ^ (s[18] ^ (s[20] ^
    s[21]))) ^ ((s[22] ^ (s[23] ^ s[24])) ^ (s[26] ^ (s[27] ^ s[31]))))) ^
    ((((w[1] ^ w[2]) ^ (w[3] ^ (w[5] ^ w[6]))) ^ ((w[7] ^ w[9]) ^ (w[10] ^
    (w[14] ^ w[15])))) ^ (((w[16] ^ w[17]) ^ (w[18] ^ (w[20] ^ w[21]))) ^
    ((w[22] ^ (w[23] ^ w[24])) ^ (w[26] ^ (w[27] ^ w[31]))))));
  assign sn[26] = ((((s[0] ^ (s[1] ^ s[3])) ^ ((s[5] ^ s[8]) ^ (s[9] ^
    s[10]))) ^ (((s[14] ^ s[17]) ^ (s[18] ^ s[19])) ^ ((s[20] ^ s[21]) ^
    (s[22] ^ s[26])))) ^ (((w[0] ^ (w[1] ^ w[3])) ^ ((w[5] ^ w[8]) ^ (w[9] ^
    w[10]))) ^ (((w[14] ^ w[17]) ^ (w[18] ^ w[19])) ^ ((w[20] ^ w[21]) ^
    (w[22] ^ w[26])))));
  assign sn[27] = (((((s[0] ^ s[1]) ^ (s[2] ^ s[4])) ^ ((s[6] ^ s[9]) ^ (s[10]
    ^ s[11]))) ^ (((s[15] ^ s[18]) ^ (s[19] ^ s[20])) ^ ((s[21] ^ s[22]) ^
    (s[23] ^ s[27])))) ^ ((((w[0] ^ w[1]) ^ (w[2] ^ w[4])) ^ ((w[6] ^ w[9]) ^
    (w[10] ^ w[11]))) ^ (((w[15] ^ w[18]) ^ (w[19] ^ w[20])) ^ ((w[21] ^
    w[22]) ^ (w[23] ^ w[27])))));
  assign sn[28] = (((((s[0] ^ s[1]) ^ (s[2] ^ s[3])) ^ ((s[5] ^ s[7]) ^ (s[10]
    ^ s[11]))) ^ (((s[12] ^ s[16]) ^ (s[19] ^ s[20])) ^ ((s[21] ^ s[22]) ^
    (s[23] ^ (s[24] ^ s[28]))))) ^ ((((w[0] ^ w[1]) ^ (w[2] ^ w[3])) ^ ((w[5]
    ^ w[7]) ^ (w[10] ^ w[11]))) ^ (((w[12] ^ w[16]) ^ (w[19] ^ w[20])) ^
    ((w[21] ^ w[22]) ^ (w[23] ^ (w[24] ^ w[28]))))));
  assign sn[29] = (((((s[1] ^ s[2]) ^ (s[3] ^ s[4])) ^ ((s[6] ^ s[8]) ^ (s[11]
    ^ s[12]))) ^ (((s[13] ^ s[17]) ^ (s[20] ^ s[21])) ^ ((s[22] ^ s[23]) ^
    (s[24] ^ (s[25] ^ s[29]))))) ^ ((((w[1] ^ w[2]) ^ (w[3] ^ w[4])) ^ ((w[6]
    ^ w[8]) ^ (w[11] ^ w[12]))) ^ (((w[13] ^ w[17]) ^ (w[20] ^ w[21])) ^
    ((w[22] ^ w[23]) ^ (w[24] ^ (w[25] ^ w[29]))))));
  assign sn[30] = (((((s[0] ^ s[2]) ^ (s[3] ^ s[4])) ^ ((s[5] ^ s[7]) ^ (s[9]
    ^ (s[12] ^ s[13])))) ^ (((s[14] ^ s[18]) ^ (s[21] ^ s[22])) ^ ((s[23] ^
    s[24]) ^ (s[25] ^ (s[26] ^ s[30]))))) ^ ((((w[0] ^ w[2]) ^ (w[3] ^ w[4]))
    ^ ((w[5] ^ w[7]) ^ (w[9] ^ (w[12] ^ w[13])))) ^ (((w[14] ^ w[18]) ^ (w[21]
    ^ w[22])) ^ ((w[23] ^ w[24]) ^ (w[25] ^ (w[26] ^ w[30]))))));
  assign sn[31] = (((((s[0] ^ s[1]) ^ (s[3] ^ s[4])) ^ ((s[5] ^ s[6]) ^ (s[8]
    ^ (s[10] ^ s[13])))) ^ (((s[14] ^ s[15]) ^ (s[19] ^ (s[22] ^ s[23]))) ^
    ((s[24] ^ s[25]) ^ (s[26] ^ (s[27] ^ s[31]))))) ^ ((((w[0] ^ w[1]) ^ (w[3]
    ^ w[4])) ^ ((w[5] ^ w[6]) ^ (w[8] ^ (w[10] ^ w[13])))) ^ (((w[14] ^ w[15])
    ^ (w[19] ^ (w[22] ^ w[23]))) ^ ((w[24] ^ w[25]) ^ (w[26] ^ (w[27] ^
    w[31]))))));
endmodule
