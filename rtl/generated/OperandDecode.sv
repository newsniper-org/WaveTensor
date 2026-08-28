// Generator : SpinalHDL v1.14.2    git head : 78f29dc66110fc099a777992b6daa2f803ab445e
// Component : OperandDecode
// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
// 
// === 생성물이다. 손으로 고치지 말 것. ===
// 고칠 곳은 rtl/spinal/ 의 생성기이고, 고친 뒤 `make rtl-gen` 으로 다시 낸다.
// 여기 직접 쓴 수정은 다음 생성에서 조용히 사라진다.

`timescale 1ns/1ps

module OperandDecode (
  input  wire          io_iValid,
  input  wire          io_iMalformed,
  input  wire          io_iCapAbsent,
  input  wire          io_iExecValid,
  input  wire [31:0]   io_iInstr_0,
  input  wire [31:0]   io_iInstr_1,
  input  wire [31:0]   io_iInstr_2,
  input  wire [31:0]   io_iInstr_3,
  input  wire [31:0]   io_iInstr_4,
  input  wire [31:0]   io_iInstr_5,
  input  wire [31:0]   io_iInstr_6,
  input  wire [31:0]   io_iInstr_7,
  input  wire [31:0]   io_iInstr_8,
  input  wire [31:0]   io_iInstr_9,
  input  wire [31:0]   io_iInstr_10,
  input  wire [31:0]   io_iInstr_11,
  input  wire [31:0]   io_iInstr_12,
  input  wire [31:0]   io_iInstr_13,
  input  wire          io_iSlotPresent_0,
  input  wire          io_iSlotPresent_1,
  input  wire          io_iSlotPresent_2,
  input  wire          io_iSlotPresent_3,
  input  wire [3:0]    io_iSlotCode_0,
  input  wire [3:0]    io_iSlotCode_1,
  input  wire [3:0]    io_iSlotCode_2,
  input  wire [3:0]    io_iSlotCode_3,
  input  wire [7:0]    io_iSlotOff_0,
  input  wire [7:0]    io_iSlotOff_1,
  input  wire [7:0]    io_iSlotOff_2,
  input  wire [7:0]    io_iSlotOff_3,
  input  wire          io_iFaultClear,
  output wire          io_oValid,
  output wire          io_oMalformed,
  output wire          io_oCapAbsent,
  output wire          io_oExecValid,
  output wire          io_oPortPresent,
  output wire [15:0]   io_oPortDest,
  output wire          io_oImm16Present,
  output wire [15:0]   io_oImm16,
  output wire          io_oImm32Present,
  output wire [31:0]   io_oImm32,
  output wire          io_oImm64Present,
  output wire [63:0]   io_oImm64,
  output wire          io_oMemPresent,
  output wire [3:0]    io_oMemAddrMode,
  output wire [11:0]   io_oMemStride,
  output wire [31:0]   io_oMemOffset,
  output wire          io_oSubValid_0,
  output wire          io_oSubValid_1,
  output wire          io_oSubValid_2,
  output wire          io_oSubValid_3,
  output wire [15:0]   io_oSubO_0,
  output wire [15:0]   io_oSubO_1,
  output wire [15:0]   io_oSubO_2,
  output wire [15:0]   io_oSubO_3,
  output wire [15:0]   io_oSubA_0,
  output wire [15:0]   io_oSubA_1,
  output wire [15:0]   io_oSubA_2,
  output wire [15:0]   io_oSubA_3,
  output wire [15:0]   io_oSubB_0,
  output wire [15:0]   io_oSubB_1,
  output wire [15:0]   io_oSubB_2,
  output wire [15:0]   io_oSubB_3,
  output wire [2:0]    io_oSubCount,
  output wire          io_oOprefAValid,
  output wire [7:0]    io_oOprefALbid,
  output wire [3:0]    io_oOprefASrcKind,
  output wire          io_oOprefBValid,
  output wire [7:0]    io_oOprefBLbid,
  output wire [3:0]    io_oOprefBSrcKind,
  output wire          io_oPrecPresent,
  output wire [7:0]    io_oPrecMode,
  output wire [7:0]    io_oPrecDim,
  output wire          io_oReasmBind_valid,
  output wire [7:0]    io_oReasmBind_payload,
  output wire [7:0]    io_oAcctgtTotal,
  output wire          io_oFault,
  input  wire          clk,
  input  wire          reset
);

  wire       [15:0]   _zz_slots_body_0;
  wire       [15:0]   _zz_slots_body_0_1;
  wire       [15:0]   _zz_slots_body_0_2;
  wire                _zz_slots_body_0_3;
  wire       [15:0]   _zz_slots_body_0_4;
  wire       [7:0]    _zz_slots_body_0_5;
  wire       [15:0]   _zz_slots_body_0_6;
  wire                _zz_slots_body_0_7;
  wire       [15:0]   _zz_slots_body_0_8;
  wire       [7:0]    _zz_slots_body_0_9;
  wire       [31:0]   _zz_slots_w1_0_1;
  wire       [31:0]   _zz_slots_w1_0_2;
  wire       [31:0]   _zz_slots_w1_0_3;
  wire                _zz_slots_w1_0_4;
  wire       [31:0]   _zz_slots_w1_0_5;
  wire       [7:0]    _zz_slots_w1_0_6;
  wire       [31:0]   _zz_slots_w1_0_7;
  wire                _zz_slots_w1_0_8;
  wire       [31:0]   _zz_slots_w1_0_9;
  wire       [7:0]    _zz_slots_w1_0_10;
  wire       [31:0]   _zz_slots_w2_0_1;
  wire       [31:0]   _zz_slots_w2_0_2;
  wire       [31:0]   _zz_slots_w2_0_3;
  wire                _zz_slots_w2_0_4;
  wire       [31:0]   _zz_slots_w2_0_5;
  wire       [7:0]    _zz_slots_w2_0_6;
  wire       [31:0]   _zz_slots_w2_0_7;
  wire                _zz_slots_w2_0_8;
  wire       [31:0]   _zz_slots_w2_0_9;
  wire       [7:0]    _zz_slots_w2_0_10;
  wire       [15:0]   _zz_slots_body_1;
  wire       [15:0]   _zz_slots_body_1_1;
  wire       [15:0]   _zz_slots_body_1_2;
  wire                _zz_slots_body_1_3;
  wire       [15:0]   _zz_slots_body_1_4;
  wire       [7:0]    _zz_slots_body_1_5;
  wire       [15:0]   _zz_slots_body_1_6;
  wire                _zz_slots_body_1_7;
  wire       [15:0]   _zz_slots_body_1_8;
  wire       [7:0]    _zz_slots_body_1_9;
  wire       [31:0]   _zz_slots_w1_1_1;
  wire       [31:0]   _zz_slots_w1_1_2;
  wire       [31:0]   _zz_slots_w1_1_3;
  wire                _zz_slots_w1_1_4;
  wire       [31:0]   _zz_slots_w1_1_5;
  wire       [7:0]    _zz_slots_w1_1_6;
  wire       [31:0]   _zz_slots_w1_1_7;
  wire                _zz_slots_w1_1_8;
  wire       [31:0]   _zz_slots_w1_1_9;
  wire       [7:0]    _zz_slots_w1_1_10;
  wire       [31:0]   _zz_slots_w2_1_1;
  wire       [31:0]   _zz_slots_w2_1_2;
  wire       [31:0]   _zz_slots_w2_1_3;
  wire                _zz_slots_w2_1_4;
  wire       [31:0]   _zz_slots_w2_1_5;
  wire       [7:0]    _zz_slots_w2_1_6;
  wire       [31:0]   _zz_slots_w2_1_7;
  wire                _zz_slots_w2_1_8;
  wire       [31:0]   _zz_slots_w2_1_9;
  wire       [7:0]    _zz_slots_w2_1_10;
  wire       [15:0]   _zz_slots_body_2;
  wire       [15:0]   _zz_slots_body_2_1;
  wire       [15:0]   _zz_slots_body_2_2;
  wire                _zz_slots_body_2_3;
  wire       [15:0]   _zz_slots_body_2_4;
  wire       [7:0]    _zz_slots_body_2_5;
  wire       [15:0]   _zz_slots_body_2_6;
  wire                _zz_slots_body_2_7;
  wire       [15:0]   _zz_slots_body_2_8;
  wire       [7:0]    _zz_slots_body_2_9;
  wire       [31:0]   _zz_slots_w1_2_1;
  wire       [31:0]   _zz_slots_w1_2_2;
  wire       [31:0]   _zz_slots_w1_2_3;
  wire                _zz_slots_w1_2_4;
  wire       [31:0]   _zz_slots_w1_2_5;
  wire       [7:0]    _zz_slots_w1_2_6;
  wire       [31:0]   _zz_slots_w1_2_7;
  wire                _zz_slots_w1_2_8;
  wire       [31:0]   _zz_slots_w1_2_9;
  wire       [7:0]    _zz_slots_w1_2_10;
  wire       [31:0]   _zz_slots_w2_2_1;
  wire       [31:0]   _zz_slots_w2_2_2;
  wire       [31:0]   _zz_slots_w2_2_3;
  wire                _zz_slots_w2_2_4;
  wire       [31:0]   _zz_slots_w2_2_5;
  wire       [7:0]    _zz_slots_w2_2_6;
  wire       [31:0]   _zz_slots_w2_2_7;
  wire                _zz_slots_w2_2_8;
  wire       [31:0]   _zz_slots_w2_2_9;
  wire       [7:0]    _zz_slots_w2_2_10;
  wire       [15:0]   _zz_slots_body_3;
  wire       [15:0]   _zz_slots_body_3_1;
  wire       [15:0]   _zz_slots_body_3_2;
  wire                _zz_slots_body_3_3;
  wire       [15:0]   _zz_slots_body_3_4;
  wire       [7:0]    _zz_slots_body_3_5;
  wire       [15:0]   _zz_slots_body_3_6;
  wire                _zz_slots_body_3_7;
  wire       [15:0]   _zz_slots_body_3_8;
  wire       [7:0]    _zz_slots_body_3_9;
  wire       [31:0]   _zz_slots_w1_3_1;
  wire       [31:0]   _zz_slots_w1_3_2;
  wire       [31:0]   _zz_slots_w1_3_3;
  wire                _zz_slots_w1_3_4;
  wire       [31:0]   _zz_slots_w1_3_5;
  wire       [7:0]    _zz_slots_w1_3_6;
  wire       [31:0]   _zz_slots_w1_3_7;
  wire                _zz_slots_w1_3_8;
  wire       [31:0]   _zz_slots_w1_3_9;
  wire       [7:0]    _zz_slots_w1_3_10;
  wire       [31:0]   _zz_slots_w2_3_1;
  wire       [31:0]   _zz_slots_w2_3_2;
  wire       [31:0]   _zz_slots_w2_3_3;
  wire                _zz_slots_w2_3_4;
  wire       [31:0]   _zz_slots_w2_3_5;
  wire       [7:0]    _zz_slots_w2_3_6;
  wire       [31:0]   _zz_slots_w2_3_7;
  wire                _zz_slots_w2_3_8;
  wire       [31:0]   _zz_slots_w2_3_9;
  wire       [7:0]    _zz_slots_w2_3_10;
  wire       [31:0]   _zz_parse_imm64;
  wire       [31:0]   _zz_parse_imm64_1;
  wire       [31:0]   _zz_parse_imm64_2;
  wire       [31:0]   _zz_parse_imm64_3;
  wire       [2:0]    _zz_parse_oprefA_1;
  wire       [0:0]    _zz_parse_oprefA_1_1;
  wire       [2:0]    _zz_parse_oprefA_2;
  wire       [2:0]    _zz_parse_oprefA_2_1;
  wire       [0:0]    _zz_parse_oprefA_2_2;
  wire       [2:0]    _zz_parse_oprefA_2_3;
  wire       [0:0]    _zz_parse_oprefA_2_4;
  wire       [2:0]    _zz_parse_oprefA_3;
  wire       [2:0]    _zz_parse_oprefA_3_1;
  wire       [2:0]    _zz_parse_oprefA_3_2;
  wire       [0:0]    _zz_parse_oprefA_3_3;
  wire       [2:0]    _zz_parse_oprefA_3_4;
  wire       [0:0]    _zz_parse_oprefA_3_5;
  wire       [2:0]    _zz_parse_oprefA_3_6;
  wire       [0:0]    _zz_parse_oprefA_3_7;
  wire       [2:0]    _zz_parse_oprefB_1;
  wire       [0:0]    _zz_parse_oprefB_1_1;
  wire       [2:0]    _zz_parse_oprefB_2;
  wire       [2:0]    _zz_parse_oprefB_2_1;
  wire       [0:0]    _zz_parse_oprefB_2_2;
  wire       [2:0]    _zz_parse_oprefB_2_3;
  wire       [0:0]    _zz_parse_oprefB_2_4;
  wire       [2:0]    _zz_parse_oprefB_3;
  wire       [2:0]    _zz_parse_oprefB_3_1;
  wire       [2:0]    _zz_parse_oprefB_3_2;
  wire       [0:0]    _zz_parse_oprefB_3_3;
  wire       [2:0]    _zz_parse_oprefB_3_4;
  wire       [0:0]    _zz_parse_oprefB_3_5;
  wire       [2:0]    _zz_parse_oprefB_3_6;
  wire       [0:0]    _zz_parse_oprefB_3_7;
  wire       [2:0]    _zz_parse_subSel_0_1;
  wire       [0:0]    _zz_parse_subSel_0_1_1;
  wire       [2:0]    _zz_parse_subSel_0_2;
  wire       [2:0]    _zz_parse_subSel_0_2_1;
  wire       [0:0]    _zz_parse_subSel_0_2_2;
  wire       [2:0]    _zz_parse_subSel_0_2_3;
  wire       [0:0]    _zz_parse_subSel_0_2_4;
  wire       [2:0]    _zz_parse_subSel_0_3;
  wire       [2:0]    _zz_parse_subSel_0_3_1;
  wire       [2:0]    _zz_parse_subSel_0_3_2;
  wire       [0:0]    _zz_parse_subSel_0_3_3;
  wire       [2:0]    _zz_parse_subSel_0_3_4;
  wire       [0:0]    _zz_parse_subSel_0_3_5;
  wire       [2:0]    _zz_parse_subSel_0_3_6;
  wire       [0:0]    _zz_parse_subSel_0_3_7;
  wire       [2:0]    _zz_parse_subSel_1_1;
  wire       [0:0]    _zz_parse_subSel_1_1_1;
  wire       [2:0]    _zz_parse_subSel_1_2;
  wire       [2:0]    _zz_parse_subSel_1_2_1;
  wire       [0:0]    _zz_parse_subSel_1_2_2;
  wire       [2:0]    _zz_parse_subSel_1_2_3;
  wire       [0:0]    _zz_parse_subSel_1_2_4;
  wire       [2:0]    _zz_parse_subSel_1_3;
  wire       [2:0]    _zz_parse_subSel_1_3_1;
  wire       [2:0]    _zz_parse_subSel_1_3_2;
  wire       [0:0]    _zz_parse_subSel_1_3_3;
  wire       [2:0]    _zz_parse_subSel_1_3_4;
  wire       [0:0]    _zz_parse_subSel_1_3_5;
  wire       [2:0]    _zz_parse_subSel_1_3_6;
  wire       [0:0]    _zz_parse_subSel_1_3_7;
  wire       [2:0]    _zz_parse_subSel_2_1;
  wire       [0:0]    _zz_parse_subSel_2_1_1;
  wire       [2:0]    _zz_parse_subSel_2_2;
  wire       [2:0]    _zz_parse_subSel_2_2_1;
  wire       [0:0]    _zz_parse_subSel_2_2_2;
  wire       [2:0]    _zz_parse_subSel_2_2_3;
  wire       [0:0]    _zz_parse_subSel_2_2_4;
  wire       [2:0]    _zz_parse_subSel_2_3;
  wire       [2:0]    _zz_parse_subSel_2_3_1;
  wire       [2:0]    _zz_parse_subSel_2_3_2;
  wire       [0:0]    _zz_parse_subSel_2_3_3;
  wire       [2:0]    _zz_parse_subSel_2_3_4;
  wire       [0:0]    _zz_parse_subSel_2_3_5;
  wire       [2:0]    _zz_parse_subSel_2_3_6;
  wire       [0:0]    _zz_parse_subSel_2_3_7;
  wire       [2:0]    _zz_parse_subSel_3_1;
  wire       [0:0]    _zz_parse_subSel_3_1_1;
  wire       [2:0]    _zz_parse_subSel_3_2;
  wire       [2:0]    _zz_parse_subSel_3_2_1;
  wire       [0:0]    _zz_parse_subSel_3_2_2;
  wire       [2:0]    _zz_parse_subSel_3_2_3;
  wire       [0:0]    _zz_parse_subSel_3_2_4;
  wire       [2:0]    _zz_parse_subSel_3_3;
  wire       [2:0]    _zz_parse_subSel_3_3_1;
  wire       [2:0]    _zz_parse_subSel_3_3_2;
  wire       [0:0]    _zz_parse_subSel_3_3_3;
  wire       [2:0]    _zz_parse_subSel_3_3_4;
  wire       [0:0]    _zz_parse_subSel_3_3_5;
  wire       [2:0]    _zz_parse_subSel_3_3_6;
  wire       [0:0]    _zz_parse_subSel_3_3_7;
  wire       [2:0]    _zz_parse_subCount;
  wire       [2:0]    _zz_parse_subCount_1;
  wire       [2:0]    _zz_parse_subCount_2;
  wire       [0:0]    _zz_parse_subCount_3;
  wire       [2:0]    _zz_parse_subCount_4;
  wire       [0:0]    _zz_parse_subCount_5;
  wire       [2:0]    _zz_parse_subCount_6;
  wire       [0:0]    _zz_parse_subCount_7;
  wire       [2:0]    _zz_parse_subCount_8;
  wire       [0:0]    _zz_parse_subCount_9;
  wire       [3:0]    _zz_judge_oprefCrcBad_48;
  wire       [3:0]    _zz_judge_oprefCrcBad_49;
  wire                _zz_judge_oprefCrcBad_50;
  wire                _zz_judge_oprefCrcBad_51;
  wire       [3:0]    _zz_judge_oprefCrcBad_52;
  wire       [3:0]    _zz_judge_oprefCrcBad_53;
  wire                _zz_judge_oprefCrcBad_54;
  wire                _zz_judge_oprefCrcBad_55;
  wire       [3:0]    _zz_judge_oprefCrcBad_56;
  wire       [3:0]    _zz_judge_oprefCrcBad_57;
  wire       [2:0]    _zz_judge_oprefCrcBad_58;
  wire       [0:0]    _zz_judge_oprefCrcBad_59;
  wire                _zz_judge_oprefCrcBad_60;
  wire       [3:0]    _zz_judge_oprefCrcBad_61;
  wire       [3:0]    _zz_judge_oprefCrcBad_62;
  wire       [15:0]   slots_hi16_0;
  wire       [15:0]   slots_hi16_1;
  wire       [15:0]   slots_hi16_2;
  wire       [15:0]   slots_hi16_3;
  wire       [15:0]   slots_hi16_4;
  wire       [15:0]   slots_hi16_5;
  wire       [15:0]   slots_hi16_6;
  wire       [15:0]   slots_hi16_7;
  wire       [15:0]   slots_hi16_8;
  wire       [15:0]   slots_hi16_9;
  wire       [15:0]   slots_hi16_10;
  wire       [15:0]   slots_hi16_11;
  wire       [15:0]   slots_hi16_12;
  wire       [15:0]   slots_hi16_13;
  wire       [15:0]   slots_body_0;
  wire       [15:0]   slots_body_1;
  wire       [15:0]   slots_body_2;
  wire       [15:0]   slots_body_3;
  wire       [31:0]   slots_w1_0;
  wire       [31:0]   slots_w1_1;
  wire       [31:0]   slots_w1_2;
  wire       [31:0]   slots_w1_3;
  wire       [31:0]   slots_w2_0;
  wire       [31:0]   slots_w2_1;
  wire       [31:0]   slots_w2_2;
  wire       [31:0]   slots_w2_3;
  wire       [7:0]    _zz_slots_w1_0;
  wire       [7:0]    _zz_slots_w2_0;
  wire       [7:0]    _zz_slots_w1_1;
  wire       [7:0]    _zz_slots_w2_1;
  wire       [7:0]    _zz_slots_w1_2;
  wire       [7:0]    _zz_slots_w2_2;
  wire       [7:0]    _zz_slots_w1_3;
  wire       [7:0]    _zz_slots_w2_3;
  wire                parse_isPort_0;
  wire                parse_isPort_1;
  wire                parse_isPort_2;
  wire                parse_isPort_3;
  wire                parse_isImm16_0;
  wire                parse_isImm16_1;
  wire                parse_isImm16_2;
  wire                parse_isImm16_3;
  wire                parse_isImm32_0;
  wire                parse_isImm32_1;
  wire                parse_isImm32_2;
  wire                parse_isImm32_3;
  wire                parse_isImm64_0;
  wire                parse_isImm64_1;
  wire                parse_isImm64_2;
  wire                parse_isImm64_3;
  wire                parse_isMem_0;
  wire                parse_isMem_1;
  wire                parse_isMem_2;
  wire                parse_isMem_3;
  wire                parse_isSub_0;
  wire                parse_isSub_1;
  wire                parse_isSub_2;
  wire                parse_isSub_3;
  wire                parse_isOpref_0;
  wire                parse_isOpref_1;
  wire                parse_isOpref_2;
  wire                parse_isOpref_3;
  wire                parse_isPrec_0;
  wire                parse_isPrec_1;
  wire                parse_isPrec_2;
  wire                parse_isPrec_3;
  wire                parse_isAcctgt_0;
  wire                parse_isAcctgt_1;
  wire                parse_isAcctgt_2;
  wire                parse_isAcctgt_3;
  wire                parse_portPresent;
  wire       [15:0]   parse_portDest;
  wire                parse_imm16Present;
  wire       [15:0]   parse_imm16;
  wire                parse_imm32Present;
  wire       [31:0]   parse_imm32;
  wire                parse_imm64Present;
  wire       [63:0]   parse_imm64;
  wire                parse_memPresent;
  wire       [3:0]    parse_memAddrMode;
  wire       [11:0]   parse_memStride;
  wire       [31:0]   parse_memOffset;
  wire                parse_precPresent;
  wire       [7:0]    parse_precMode;
  wire       [7:0]    parse_precDim;
  wire                parse_acctgtPresent;
  wire       [7:0]    parse_acctgtLbid;
  wire       [7:0]    parse_acctgtTotal;
  wire                parse_oprefA_0;
  wire                parse_oprefA_1;
  wire                parse_oprefA_2;
  wire                parse_oprefA_3;
  wire                parse_oprefB_0;
  wire                parse_oprefB_1;
  wire                parse_oprefB_2;
  wire                parse_oprefB_3;
  wire                parse_oprefAValid;
  wire                parse_oprefBValid;
  wire       [7:0]    parse_oprefALbid;
  wire       [3:0]    parse_oprefASrcKind;
  wire       [7:0]    parse_oprefBLbid;
  wire       [3:0]    parse_oprefBSrcKind;
  wire                parse_subSel_0_0;
  wire                parse_subSel_0_1;
  wire                parse_subSel_0_2;
  wire                parse_subSel_0_3;
  wire                parse_subSel_1_0;
  wire                parse_subSel_1_1;
  wire                parse_subSel_1_2;
  wire                parse_subSel_1_3;
  wire                parse_subSel_2_0;
  wire                parse_subSel_2_1;
  wire                parse_subSel_2_2;
  wire                parse_subSel_2_3;
  wire                parse_subSel_3_0;
  wire                parse_subSel_3_1;
  wire                parse_subSel_3_2;
  wire                parse_subSel_3_3;
  wire                parse_subValid_0;
  wire                parse_subValid_1;
  wire                parse_subValid_2;
  wire                parse_subValid_3;
  wire       [15:0]   parse_subO_0;
  wire       [15:0]   parse_subO_1;
  wire       [15:0]   parse_subO_2;
  wire       [15:0]   parse_subO_3;
  wire       [15:0]   parse_subA_0;
  wire       [15:0]   parse_subA_1;
  wire       [15:0]   parse_subA_2;
  wire       [15:0]   parse_subA_3;
  wire       [15:0]   parse_subB_0;
  wire       [15:0]   parse_subB_1;
  wire       [15:0]   parse_subB_2;
  wire       [15:0]   parse_subB_3;
  wire       [2:0]    parse_subCount;
  wire       [3:0]    _zz_judge_oprefCrcBad;
  wire       [3:0]    _zz_judge_oprefCrcBad_1;
  wire       [3:0]    _zz_judge_oprefCrcBad_2;
  wire       [3:0]    _zz_judge_oprefCrcBad_3;
  wire       [3:0]    _zz_judge_oprefCrcBad_4;
  wire       [3:0]    _zz_judge_oprefCrcBad_5;
  wire       [3:0]    _zz_judge_oprefCrcBad_6;
  wire       [3:0]    _zz_judge_oprefCrcBad_7;
  wire       [3:0]    _zz_judge_oprefCrcBad_8;
  wire       [3:0]    _zz_judge_oprefCrcBad_9;
  wire       [3:0]    _zz_judge_oprefCrcBad_10;
  wire       [3:0]    _zz_judge_oprefCrcBad_11;
  wire       [3:0]    _zz_judge_oprefCrcBad_12;
  wire       [3:0]    _zz_judge_oprefCrcBad_13;
  wire       [3:0]    _zz_judge_oprefCrcBad_14;
  wire       [3:0]    _zz_judge_oprefCrcBad_15;
  wire       [3:0]    _zz_judge_oprefCrcBad_16;
  wire       [3:0]    _zz_judge_oprefCrcBad_17;
  wire       [3:0]    _zz_judge_oprefCrcBad_18;
  wire       [3:0]    _zz_judge_oprefCrcBad_19;
  wire       [3:0]    _zz_judge_oprefCrcBad_20;
  wire       [3:0]    _zz_judge_oprefCrcBad_21;
  wire       [3:0]    _zz_judge_oprefCrcBad_22;
  wire       [3:0]    _zz_judge_oprefCrcBad_23;
  wire       [3:0]    _zz_judge_oprefCrcBad_24;
  wire       [3:0]    _zz_judge_oprefCrcBad_25;
  wire       [3:0]    _zz_judge_oprefCrcBad_26;
  wire       [3:0]    _zz_judge_oprefCrcBad_27;
  wire       [3:0]    _zz_judge_oprefCrcBad_28;
  wire       [3:0]    _zz_judge_oprefCrcBad_29;
  wire       [3:0]    _zz_judge_oprefCrcBad_30;
  wire       [3:0]    _zz_judge_oprefCrcBad_31;
  wire       [3:0]    _zz_judge_oprefCrcBad_32;
  wire       [3:0]    _zz_judge_oprefCrcBad_33;
  wire       [3:0]    _zz_judge_oprefCrcBad_34;
  wire       [3:0]    _zz_judge_oprefCrcBad_35;
  wire       [3:0]    _zz_judge_oprefCrcBad_36;
  wire       [3:0]    _zz_judge_oprefCrcBad_37;
  wire       [3:0]    _zz_judge_oprefCrcBad_38;
  wire       [3:0]    _zz_judge_oprefCrcBad_39;
  wire       [3:0]    _zz_judge_oprefCrcBad_40;
  wire       [3:0]    _zz_judge_oprefCrcBad_41;
  wire       [3:0]    _zz_judge_oprefCrcBad_42;
  wire       [3:0]    _zz_judge_oprefCrcBad_43;
  wire       [3:0]    _zz_judge_oprefCrcBad_44;
  wire       [3:0]    _zz_judge_oprefCrcBad_45;
  wire       [3:0]    _zz_judge_oprefCrcBad_46;
  wire       [3:0]    _zz_judge_oprefCrcBad_47;
  wire                judge_oprefCrcBad;
  wire                judge_srcKindBad;
  wire                judge_bodyMal;
  wire                when_Common_l259;
  reg                 _zz_io_oFault;

  assign _zz_parse_oprefA_1_1 = parse_isOpref_0;
  assign _zz_parse_oprefA_1 = {2'd0, _zz_parse_oprefA_1_1};
  assign _zz_parse_oprefA_2 = (_zz_parse_oprefA_2_1 + _zz_parse_oprefA_2_3);
  assign _zz_parse_oprefA_2_2 = parse_isOpref_0;
  assign _zz_parse_oprefA_2_1 = {2'd0, _zz_parse_oprefA_2_2};
  assign _zz_parse_oprefA_2_4 = parse_isOpref_1;
  assign _zz_parse_oprefA_2_3 = {2'd0, _zz_parse_oprefA_2_4};
  assign _zz_parse_oprefA_3 = (_zz_parse_oprefA_3_1 + _zz_parse_oprefA_3_6);
  assign _zz_parse_oprefA_3_1 = (_zz_parse_oprefA_3_2 + _zz_parse_oprefA_3_4);
  assign _zz_parse_oprefA_3_3 = parse_isOpref_0;
  assign _zz_parse_oprefA_3_2 = {2'd0, _zz_parse_oprefA_3_3};
  assign _zz_parse_oprefA_3_5 = parse_isOpref_1;
  assign _zz_parse_oprefA_3_4 = {2'd0, _zz_parse_oprefA_3_5};
  assign _zz_parse_oprefA_3_7 = parse_isOpref_2;
  assign _zz_parse_oprefA_3_6 = {2'd0, _zz_parse_oprefA_3_7};
  assign _zz_parse_oprefB_1_1 = parse_isOpref_0;
  assign _zz_parse_oprefB_1 = {2'd0, _zz_parse_oprefB_1_1};
  assign _zz_parse_oprefB_2 = (_zz_parse_oprefB_2_1 + _zz_parse_oprefB_2_3);
  assign _zz_parse_oprefB_2_2 = parse_isOpref_0;
  assign _zz_parse_oprefB_2_1 = {2'd0, _zz_parse_oprefB_2_2};
  assign _zz_parse_oprefB_2_4 = parse_isOpref_1;
  assign _zz_parse_oprefB_2_3 = {2'd0, _zz_parse_oprefB_2_4};
  assign _zz_parse_oprefB_3 = (_zz_parse_oprefB_3_1 + _zz_parse_oprefB_3_6);
  assign _zz_parse_oprefB_3_1 = (_zz_parse_oprefB_3_2 + _zz_parse_oprefB_3_4);
  assign _zz_parse_oprefB_3_3 = parse_isOpref_0;
  assign _zz_parse_oprefB_3_2 = {2'd0, _zz_parse_oprefB_3_3};
  assign _zz_parse_oprefB_3_5 = parse_isOpref_1;
  assign _zz_parse_oprefB_3_4 = {2'd0, _zz_parse_oprefB_3_5};
  assign _zz_parse_oprefB_3_7 = parse_isOpref_2;
  assign _zz_parse_oprefB_3_6 = {2'd0, _zz_parse_oprefB_3_7};
  assign _zz_parse_subSel_0_1_1 = parse_isSub_0;
  assign _zz_parse_subSel_0_1 = {2'd0, _zz_parse_subSel_0_1_1};
  assign _zz_parse_subSel_0_2 = (_zz_parse_subSel_0_2_1 + _zz_parse_subSel_0_2_3);
  assign _zz_parse_subSel_0_2_2 = parse_isSub_0;
  assign _zz_parse_subSel_0_2_1 = {2'd0, _zz_parse_subSel_0_2_2};
  assign _zz_parse_subSel_0_2_4 = parse_isSub_1;
  assign _zz_parse_subSel_0_2_3 = {2'd0, _zz_parse_subSel_0_2_4};
  assign _zz_parse_subSel_0_3 = (_zz_parse_subSel_0_3_1 + _zz_parse_subSel_0_3_6);
  assign _zz_parse_subSel_0_3_1 = (_zz_parse_subSel_0_3_2 + _zz_parse_subSel_0_3_4);
  assign _zz_parse_subSel_0_3_3 = parse_isSub_0;
  assign _zz_parse_subSel_0_3_2 = {2'd0, _zz_parse_subSel_0_3_3};
  assign _zz_parse_subSel_0_3_5 = parse_isSub_1;
  assign _zz_parse_subSel_0_3_4 = {2'd0, _zz_parse_subSel_0_3_5};
  assign _zz_parse_subSel_0_3_7 = parse_isSub_2;
  assign _zz_parse_subSel_0_3_6 = {2'd0, _zz_parse_subSel_0_3_7};
  assign _zz_parse_subSel_1_1_1 = parse_isSub_0;
  assign _zz_parse_subSel_1_1 = {2'd0, _zz_parse_subSel_1_1_1};
  assign _zz_parse_subSel_1_2 = (_zz_parse_subSel_1_2_1 + _zz_parse_subSel_1_2_3);
  assign _zz_parse_subSel_1_2_2 = parse_isSub_0;
  assign _zz_parse_subSel_1_2_1 = {2'd0, _zz_parse_subSel_1_2_2};
  assign _zz_parse_subSel_1_2_4 = parse_isSub_1;
  assign _zz_parse_subSel_1_2_3 = {2'd0, _zz_parse_subSel_1_2_4};
  assign _zz_parse_subSel_1_3 = (_zz_parse_subSel_1_3_1 + _zz_parse_subSel_1_3_6);
  assign _zz_parse_subSel_1_3_1 = (_zz_parse_subSel_1_3_2 + _zz_parse_subSel_1_3_4);
  assign _zz_parse_subSel_1_3_3 = parse_isSub_0;
  assign _zz_parse_subSel_1_3_2 = {2'd0, _zz_parse_subSel_1_3_3};
  assign _zz_parse_subSel_1_3_5 = parse_isSub_1;
  assign _zz_parse_subSel_1_3_4 = {2'd0, _zz_parse_subSel_1_3_5};
  assign _zz_parse_subSel_1_3_7 = parse_isSub_2;
  assign _zz_parse_subSel_1_3_6 = {2'd0, _zz_parse_subSel_1_3_7};
  assign _zz_parse_subSel_2_1_1 = parse_isSub_0;
  assign _zz_parse_subSel_2_1 = {2'd0, _zz_parse_subSel_2_1_1};
  assign _zz_parse_subSel_2_2 = (_zz_parse_subSel_2_2_1 + _zz_parse_subSel_2_2_3);
  assign _zz_parse_subSel_2_2_2 = parse_isSub_0;
  assign _zz_parse_subSel_2_2_1 = {2'd0, _zz_parse_subSel_2_2_2};
  assign _zz_parse_subSel_2_2_4 = parse_isSub_1;
  assign _zz_parse_subSel_2_2_3 = {2'd0, _zz_parse_subSel_2_2_4};
  assign _zz_parse_subSel_2_3 = (_zz_parse_subSel_2_3_1 + _zz_parse_subSel_2_3_6);
  assign _zz_parse_subSel_2_3_1 = (_zz_parse_subSel_2_3_2 + _zz_parse_subSel_2_3_4);
  assign _zz_parse_subSel_2_3_3 = parse_isSub_0;
  assign _zz_parse_subSel_2_3_2 = {2'd0, _zz_parse_subSel_2_3_3};
  assign _zz_parse_subSel_2_3_5 = parse_isSub_1;
  assign _zz_parse_subSel_2_3_4 = {2'd0, _zz_parse_subSel_2_3_5};
  assign _zz_parse_subSel_2_3_7 = parse_isSub_2;
  assign _zz_parse_subSel_2_3_6 = {2'd0, _zz_parse_subSel_2_3_7};
  assign _zz_parse_subSel_3_1_1 = parse_isSub_0;
  assign _zz_parse_subSel_3_1 = {2'd0, _zz_parse_subSel_3_1_1};
  assign _zz_parse_subSel_3_2 = (_zz_parse_subSel_3_2_1 + _zz_parse_subSel_3_2_3);
  assign _zz_parse_subSel_3_2_2 = parse_isSub_0;
  assign _zz_parse_subSel_3_2_1 = {2'd0, _zz_parse_subSel_3_2_2};
  assign _zz_parse_subSel_3_2_4 = parse_isSub_1;
  assign _zz_parse_subSel_3_2_3 = {2'd0, _zz_parse_subSel_3_2_4};
  assign _zz_parse_subSel_3_3 = (_zz_parse_subSel_3_3_1 + _zz_parse_subSel_3_3_6);
  assign _zz_parse_subSel_3_3_1 = (_zz_parse_subSel_3_3_2 + _zz_parse_subSel_3_3_4);
  assign _zz_parse_subSel_3_3_3 = parse_isSub_0;
  assign _zz_parse_subSel_3_3_2 = {2'd0, _zz_parse_subSel_3_3_3};
  assign _zz_parse_subSel_3_3_5 = parse_isSub_1;
  assign _zz_parse_subSel_3_3_4 = {2'd0, _zz_parse_subSel_3_3_5};
  assign _zz_parse_subSel_3_3_7 = parse_isSub_2;
  assign _zz_parse_subSel_3_3_6 = {2'd0, _zz_parse_subSel_3_3_7};
  assign _zz_parse_subCount = (_zz_parse_subCount_1 + _zz_parse_subCount_6);
  assign _zz_parse_subCount_1 = (_zz_parse_subCount_2 + _zz_parse_subCount_4);
  assign _zz_parse_subCount_3 = parse_isSub_0;
  assign _zz_parse_subCount_2 = {2'd0, _zz_parse_subCount_3};
  assign _zz_parse_subCount_5 = parse_isSub_1;
  assign _zz_parse_subCount_4 = {2'd0, _zz_parse_subCount_5};
  assign _zz_parse_subCount_7 = parse_isSub_2;
  assign _zz_parse_subCount_6 = {2'd0, _zz_parse_subCount_7};
  assign _zz_parse_subCount_9 = parse_isSub_3;
  assign _zz_parse_subCount_8 = {2'd0, _zz_parse_subCount_9};
  assign _zz_slots_body_0 = ((((((_zz_slots_body_0_1 | _zz_slots_body_0_2) | (_zz_slots_body_0_3 ? slots_hi16_3 : _zz_slots_body_0_4)) | ((io_iSlotOff_0 == _zz_slots_body_0_5) ? slots_hi16_4 : 16'h0)) | ((io_iSlotOff_0 == 8'h05) ? slots_hi16_5 : 16'h0)) | ((io_iSlotOff_0 == 8'h06) ? slots_hi16_6 : 16'h0)) | ((io_iSlotOff_0 == 8'h07) ? slots_hi16_7 : 16'h0));
  assign _zz_slots_body_0_6 = ((io_iSlotOff_0 == 8'h08) ? slots_hi16_8 : 16'h0);
  assign _zz_slots_body_0_7 = (io_iSlotOff_0 == 8'h09);
  assign _zz_slots_body_0_8 = 16'h0;
  assign _zz_slots_body_0_9 = 8'h0a;
  assign _zz_slots_body_0_1 = (((io_iSlotOff_0 == 8'h0) ? slots_hi16_0 : 16'h0) | ((io_iSlotOff_0 == 8'h01) ? slots_hi16_1 : 16'h0));
  assign _zz_slots_body_0_2 = ((io_iSlotOff_0 == 8'h02) ? slots_hi16_2 : 16'h0);
  assign _zz_slots_body_0_3 = (io_iSlotOff_0 == 8'h03);
  assign _zz_slots_body_0_4 = 16'h0;
  assign _zz_slots_body_0_5 = 8'h04;
  assign _zz_slots_w1_0_1 = ((((((_zz_slots_w1_0_2 | _zz_slots_w1_0_3) | (_zz_slots_w1_0_4 ? io_iInstr_3 : _zz_slots_w1_0_5)) | ((_zz_slots_w1_0 == _zz_slots_w1_0_6) ? io_iInstr_4 : 32'h0)) | ((_zz_slots_w1_0 == 8'h05) ? io_iInstr_5 : 32'h0)) | ((_zz_slots_w1_0 == 8'h06) ? io_iInstr_6 : 32'h0)) | ((_zz_slots_w1_0 == 8'h07) ? io_iInstr_7 : 32'h0));
  assign _zz_slots_w1_0_7 = ((_zz_slots_w1_0 == 8'h08) ? io_iInstr_8 : 32'h0);
  assign _zz_slots_w1_0_8 = (_zz_slots_w1_0 == 8'h09);
  assign _zz_slots_w1_0_9 = 32'h0;
  assign _zz_slots_w1_0_10 = 8'h0a;
  assign _zz_slots_w1_0_2 = (((_zz_slots_w1_0 == 8'h0) ? io_iInstr_0 : 32'h0) | ((_zz_slots_w1_0 == 8'h01) ? io_iInstr_1 : 32'h0));
  assign _zz_slots_w1_0_3 = ((_zz_slots_w1_0 == 8'h02) ? io_iInstr_2 : 32'h0);
  assign _zz_slots_w1_0_4 = (_zz_slots_w1_0 == 8'h03);
  assign _zz_slots_w1_0_5 = 32'h0;
  assign _zz_slots_w1_0_6 = 8'h04;
  assign _zz_slots_w2_0_1 = ((((((_zz_slots_w2_0_2 | _zz_slots_w2_0_3) | (_zz_slots_w2_0_4 ? io_iInstr_3 : _zz_slots_w2_0_5)) | ((_zz_slots_w2_0 == _zz_slots_w2_0_6) ? io_iInstr_4 : 32'h0)) | ((_zz_slots_w2_0 == 8'h05) ? io_iInstr_5 : 32'h0)) | ((_zz_slots_w2_0 == 8'h06) ? io_iInstr_6 : 32'h0)) | ((_zz_slots_w2_0 == 8'h07) ? io_iInstr_7 : 32'h0));
  assign _zz_slots_w2_0_7 = ((_zz_slots_w2_0 == 8'h08) ? io_iInstr_8 : 32'h0);
  assign _zz_slots_w2_0_8 = (_zz_slots_w2_0 == 8'h09);
  assign _zz_slots_w2_0_9 = 32'h0;
  assign _zz_slots_w2_0_10 = 8'h0a;
  assign _zz_slots_w2_0_2 = (((_zz_slots_w2_0 == 8'h0) ? io_iInstr_0 : 32'h0) | ((_zz_slots_w2_0 == 8'h01) ? io_iInstr_1 : 32'h0));
  assign _zz_slots_w2_0_3 = ((_zz_slots_w2_0 == 8'h02) ? io_iInstr_2 : 32'h0);
  assign _zz_slots_w2_0_4 = (_zz_slots_w2_0 == 8'h03);
  assign _zz_slots_w2_0_5 = 32'h0;
  assign _zz_slots_w2_0_6 = 8'h04;
  assign _zz_slots_body_1 = ((((((_zz_slots_body_1_1 | _zz_slots_body_1_2) | (_zz_slots_body_1_3 ? slots_hi16_3 : _zz_slots_body_1_4)) | ((io_iSlotOff_1 == _zz_slots_body_1_5) ? slots_hi16_4 : 16'h0)) | ((io_iSlotOff_1 == 8'h05) ? slots_hi16_5 : 16'h0)) | ((io_iSlotOff_1 == 8'h06) ? slots_hi16_6 : 16'h0)) | ((io_iSlotOff_1 == 8'h07) ? slots_hi16_7 : 16'h0));
  assign _zz_slots_body_1_6 = ((io_iSlotOff_1 == 8'h08) ? slots_hi16_8 : 16'h0);
  assign _zz_slots_body_1_7 = (io_iSlotOff_1 == 8'h09);
  assign _zz_slots_body_1_8 = 16'h0;
  assign _zz_slots_body_1_9 = 8'h0a;
  assign _zz_slots_body_1_1 = (((io_iSlotOff_1 == 8'h0) ? slots_hi16_0 : 16'h0) | ((io_iSlotOff_1 == 8'h01) ? slots_hi16_1 : 16'h0));
  assign _zz_slots_body_1_2 = ((io_iSlotOff_1 == 8'h02) ? slots_hi16_2 : 16'h0);
  assign _zz_slots_body_1_3 = (io_iSlotOff_1 == 8'h03);
  assign _zz_slots_body_1_4 = 16'h0;
  assign _zz_slots_body_1_5 = 8'h04;
  assign _zz_slots_w1_1_1 = ((((((_zz_slots_w1_1_2 | _zz_slots_w1_1_3) | (_zz_slots_w1_1_4 ? io_iInstr_3 : _zz_slots_w1_1_5)) | ((_zz_slots_w1_1 == _zz_slots_w1_1_6) ? io_iInstr_4 : 32'h0)) | ((_zz_slots_w1_1 == 8'h05) ? io_iInstr_5 : 32'h0)) | ((_zz_slots_w1_1 == 8'h06) ? io_iInstr_6 : 32'h0)) | ((_zz_slots_w1_1 == 8'h07) ? io_iInstr_7 : 32'h0));
  assign _zz_slots_w1_1_7 = ((_zz_slots_w1_1 == 8'h08) ? io_iInstr_8 : 32'h0);
  assign _zz_slots_w1_1_8 = (_zz_slots_w1_1 == 8'h09);
  assign _zz_slots_w1_1_9 = 32'h0;
  assign _zz_slots_w1_1_10 = 8'h0a;
  assign _zz_slots_w1_1_2 = (((_zz_slots_w1_1 == 8'h0) ? io_iInstr_0 : 32'h0) | ((_zz_slots_w1_1 == 8'h01) ? io_iInstr_1 : 32'h0));
  assign _zz_slots_w1_1_3 = ((_zz_slots_w1_1 == 8'h02) ? io_iInstr_2 : 32'h0);
  assign _zz_slots_w1_1_4 = (_zz_slots_w1_1 == 8'h03);
  assign _zz_slots_w1_1_5 = 32'h0;
  assign _zz_slots_w1_1_6 = 8'h04;
  assign _zz_slots_w2_1_1 = ((((((_zz_slots_w2_1_2 | _zz_slots_w2_1_3) | (_zz_slots_w2_1_4 ? io_iInstr_3 : _zz_slots_w2_1_5)) | ((_zz_slots_w2_1 == _zz_slots_w2_1_6) ? io_iInstr_4 : 32'h0)) | ((_zz_slots_w2_1 == 8'h05) ? io_iInstr_5 : 32'h0)) | ((_zz_slots_w2_1 == 8'h06) ? io_iInstr_6 : 32'h0)) | ((_zz_slots_w2_1 == 8'h07) ? io_iInstr_7 : 32'h0));
  assign _zz_slots_w2_1_7 = ((_zz_slots_w2_1 == 8'h08) ? io_iInstr_8 : 32'h0);
  assign _zz_slots_w2_1_8 = (_zz_slots_w2_1 == 8'h09);
  assign _zz_slots_w2_1_9 = 32'h0;
  assign _zz_slots_w2_1_10 = 8'h0a;
  assign _zz_slots_w2_1_2 = (((_zz_slots_w2_1 == 8'h0) ? io_iInstr_0 : 32'h0) | ((_zz_slots_w2_1 == 8'h01) ? io_iInstr_1 : 32'h0));
  assign _zz_slots_w2_1_3 = ((_zz_slots_w2_1 == 8'h02) ? io_iInstr_2 : 32'h0);
  assign _zz_slots_w2_1_4 = (_zz_slots_w2_1 == 8'h03);
  assign _zz_slots_w2_1_5 = 32'h0;
  assign _zz_slots_w2_1_6 = 8'h04;
  assign _zz_slots_body_2 = ((((((_zz_slots_body_2_1 | _zz_slots_body_2_2) | (_zz_slots_body_2_3 ? slots_hi16_3 : _zz_slots_body_2_4)) | ((io_iSlotOff_2 == _zz_slots_body_2_5) ? slots_hi16_4 : 16'h0)) | ((io_iSlotOff_2 == 8'h05) ? slots_hi16_5 : 16'h0)) | ((io_iSlotOff_2 == 8'h06) ? slots_hi16_6 : 16'h0)) | ((io_iSlotOff_2 == 8'h07) ? slots_hi16_7 : 16'h0));
  assign _zz_slots_body_2_6 = ((io_iSlotOff_2 == 8'h08) ? slots_hi16_8 : 16'h0);
  assign _zz_slots_body_2_7 = (io_iSlotOff_2 == 8'h09);
  assign _zz_slots_body_2_8 = 16'h0;
  assign _zz_slots_body_2_9 = 8'h0a;
  assign _zz_slots_body_2_1 = (((io_iSlotOff_2 == 8'h0) ? slots_hi16_0 : 16'h0) | ((io_iSlotOff_2 == 8'h01) ? slots_hi16_1 : 16'h0));
  assign _zz_slots_body_2_2 = ((io_iSlotOff_2 == 8'h02) ? slots_hi16_2 : 16'h0);
  assign _zz_slots_body_2_3 = (io_iSlotOff_2 == 8'h03);
  assign _zz_slots_body_2_4 = 16'h0;
  assign _zz_slots_body_2_5 = 8'h04;
  assign _zz_slots_w1_2_1 = ((((((_zz_slots_w1_2_2 | _zz_slots_w1_2_3) | (_zz_slots_w1_2_4 ? io_iInstr_3 : _zz_slots_w1_2_5)) | ((_zz_slots_w1_2 == _zz_slots_w1_2_6) ? io_iInstr_4 : 32'h0)) | ((_zz_slots_w1_2 == 8'h05) ? io_iInstr_5 : 32'h0)) | ((_zz_slots_w1_2 == 8'h06) ? io_iInstr_6 : 32'h0)) | ((_zz_slots_w1_2 == 8'h07) ? io_iInstr_7 : 32'h0));
  assign _zz_slots_w1_2_7 = ((_zz_slots_w1_2 == 8'h08) ? io_iInstr_8 : 32'h0);
  assign _zz_slots_w1_2_8 = (_zz_slots_w1_2 == 8'h09);
  assign _zz_slots_w1_2_9 = 32'h0;
  assign _zz_slots_w1_2_10 = 8'h0a;
  assign _zz_slots_w1_2_2 = (((_zz_slots_w1_2 == 8'h0) ? io_iInstr_0 : 32'h0) | ((_zz_slots_w1_2 == 8'h01) ? io_iInstr_1 : 32'h0));
  assign _zz_slots_w1_2_3 = ((_zz_slots_w1_2 == 8'h02) ? io_iInstr_2 : 32'h0);
  assign _zz_slots_w1_2_4 = (_zz_slots_w1_2 == 8'h03);
  assign _zz_slots_w1_2_5 = 32'h0;
  assign _zz_slots_w1_2_6 = 8'h04;
  assign _zz_slots_w2_2_1 = ((((((_zz_slots_w2_2_2 | _zz_slots_w2_2_3) | (_zz_slots_w2_2_4 ? io_iInstr_3 : _zz_slots_w2_2_5)) | ((_zz_slots_w2_2 == _zz_slots_w2_2_6) ? io_iInstr_4 : 32'h0)) | ((_zz_slots_w2_2 == 8'h05) ? io_iInstr_5 : 32'h0)) | ((_zz_slots_w2_2 == 8'h06) ? io_iInstr_6 : 32'h0)) | ((_zz_slots_w2_2 == 8'h07) ? io_iInstr_7 : 32'h0));
  assign _zz_slots_w2_2_7 = ((_zz_slots_w2_2 == 8'h08) ? io_iInstr_8 : 32'h0);
  assign _zz_slots_w2_2_8 = (_zz_slots_w2_2 == 8'h09);
  assign _zz_slots_w2_2_9 = 32'h0;
  assign _zz_slots_w2_2_10 = 8'h0a;
  assign _zz_slots_w2_2_2 = (((_zz_slots_w2_2 == 8'h0) ? io_iInstr_0 : 32'h0) | ((_zz_slots_w2_2 == 8'h01) ? io_iInstr_1 : 32'h0));
  assign _zz_slots_w2_2_3 = ((_zz_slots_w2_2 == 8'h02) ? io_iInstr_2 : 32'h0);
  assign _zz_slots_w2_2_4 = (_zz_slots_w2_2 == 8'h03);
  assign _zz_slots_w2_2_5 = 32'h0;
  assign _zz_slots_w2_2_6 = 8'h04;
  assign _zz_slots_body_3 = ((((((_zz_slots_body_3_1 | _zz_slots_body_3_2) | (_zz_slots_body_3_3 ? slots_hi16_3 : _zz_slots_body_3_4)) | ((io_iSlotOff_3 == _zz_slots_body_3_5) ? slots_hi16_4 : 16'h0)) | ((io_iSlotOff_3 == 8'h05) ? slots_hi16_5 : 16'h0)) | ((io_iSlotOff_3 == 8'h06) ? slots_hi16_6 : 16'h0)) | ((io_iSlotOff_3 == 8'h07) ? slots_hi16_7 : 16'h0));
  assign _zz_slots_body_3_6 = ((io_iSlotOff_3 == 8'h08) ? slots_hi16_8 : 16'h0);
  assign _zz_slots_body_3_7 = (io_iSlotOff_3 == 8'h09);
  assign _zz_slots_body_3_8 = 16'h0;
  assign _zz_slots_body_3_9 = 8'h0a;
  assign _zz_slots_body_3_1 = (((io_iSlotOff_3 == 8'h0) ? slots_hi16_0 : 16'h0) | ((io_iSlotOff_3 == 8'h01) ? slots_hi16_1 : 16'h0));
  assign _zz_slots_body_3_2 = ((io_iSlotOff_3 == 8'h02) ? slots_hi16_2 : 16'h0);
  assign _zz_slots_body_3_3 = (io_iSlotOff_3 == 8'h03);
  assign _zz_slots_body_3_4 = 16'h0;
  assign _zz_slots_body_3_5 = 8'h04;
  assign _zz_slots_w1_3_1 = ((((((_zz_slots_w1_3_2 | _zz_slots_w1_3_3) | (_zz_slots_w1_3_4 ? io_iInstr_3 : _zz_slots_w1_3_5)) | ((_zz_slots_w1_3 == _zz_slots_w1_3_6) ? io_iInstr_4 : 32'h0)) | ((_zz_slots_w1_3 == 8'h05) ? io_iInstr_5 : 32'h0)) | ((_zz_slots_w1_3 == 8'h06) ? io_iInstr_6 : 32'h0)) | ((_zz_slots_w1_3 == 8'h07) ? io_iInstr_7 : 32'h0));
  assign _zz_slots_w1_3_7 = ((_zz_slots_w1_3 == 8'h08) ? io_iInstr_8 : 32'h0);
  assign _zz_slots_w1_3_8 = (_zz_slots_w1_3 == 8'h09);
  assign _zz_slots_w1_3_9 = 32'h0;
  assign _zz_slots_w1_3_10 = 8'h0a;
  assign _zz_slots_w1_3_2 = (((_zz_slots_w1_3 == 8'h0) ? io_iInstr_0 : 32'h0) | ((_zz_slots_w1_3 == 8'h01) ? io_iInstr_1 : 32'h0));
  assign _zz_slots_w1_3_3 = ((_zz_slots_w1_3 == 8'h02) ? io_iInstr_2 : 32'h0);
  assign _zz_slots_w1_3_4 = (_zz_slots_w1_3 == 8'h03);
  assign _zz_slots_w1_3_5 = 32'h0;
  assign _zz_slots_w1_3_6 = 8'h04;
  assign _zz_slots_w2_3_1 = ((((((_zz_slots_w2_3_2 | _zz_slots_w2_3_3) | (_zz_slots_w2_3_4 ? io_iInstr_3 : _zz_slots_w2_3_5)) | ((_zz_slots_w2_3 == _zz_slots_w2_3_6) ? io_iInstr_4 : 32'h0)) | ((_zz_slots_w2_3 == 8'h05) ? io_iInstr_5 : 32'h0)) | ((_zz_slots_w2_3 == 8'h06) ? io_iInstr_6 : 32'h0)) | ((_zz_slots_w2_3 == 8'h07) ? io_iInstr_7 : 32'h0));
  assign _zz_slots_w2_3_7 = ((_zz_slots_w2_3 == 8'h08) ? io_iInstr_8 : 32'h0);
  assign _zz_slots_w2_3_8 = (_zz_slots_w2_3 == 8'h09);
  assign _zz_slots_w2_3_9 = 32'h0;
  assign _zz_slots_w2_3_10 = 8'h0a;
  assign _zz_slots_w2_3_2 = (((_zz_slots_w2_3 == 8'h0) ? io_iInstr_0 : 32'h0) | ((_zz_slots_w2_3 == 8'h01) ? io_iInstr_1 : 32'h0));
  assign _zz_slots_w2_3_3 = ((_zz_slots_w2_3 == 8'h02) ? io_iInstr_2 : 32'h0);
  assign _zz_slots_w2_3_4 = (_zz_slots_w2_3 == 8'h03);
  assign _zz_slots_w2_3_5 = 32'h0;
  assign _zz_slots_w2_3_6 = 8'h04;
  assign _zz_parse_imm64 = 32'h0;
  assign _zz_parse_imm64_1 = 32'h0;
  assign _zz_parse_imm64_2 = 32'h0;
  assign _zz_parse_imm64_3 = 32'h0;
  assign _zz_judge_oprefCrcBad_48 = slots_body_0[7 : 4];
  assign _zz_judge_oprefCrcBad_49 = ({_zz_judge_oprefCrcBad_11[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_50 ^ _zz_judge_oprefCrcBad_51) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_52 = slots_body_1[7 : 4];
  assign _zz_judge_oprefCrcBad_53 = ({_zz_judge_oprefCrcBad_23[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_54 ^ _zz_judge_oprefCrcBad_55) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_56 = {_zz_judge_oprefCrcBad_35[2 : 0],1'b0};
  assign _zz_judge_oprefCrcBad_57 = ((_zz_judge_oprefCrcBad_35[3] ^ slots_body_2[0]) ? 4'b0011 : 4'b0000);
  assign _zz_judge_oprefCrcBad_58 = _zz_judge_oprefCrcBad_47[2 : 0];
  assign _zz_judge_oprefCrcBad_59 = 1'b0;
  assign _zz_judge_oprefCrcBad_60 = (_zz_judge_oprefCrcBad_47[3] ^ slots_body_3[0]);
  assign _zz_judge_oprefCrcBad_61 = 4'b0011;
  assign _zz_judge_oprefCrcBad_62 = 4'b0000;
  assign _zz_judge_oprefCrcBad_50 = _zz_judge_oprefCrcBad_11[3];
  assign _zz_judge_oprefCrcBad_51 = slots_body_0[0];
  assign _zz_judge_oprefCrcBad_54 = _zz_judge_oprefCrcBad_23[3];
  assign _zz_judge_oprefCrcBad_55 = slots_body_1[0];
  assign slots_hi16_0 = io_iInstr_0[31 : 16];
  assign slots_hi16_1 = io_iInstr_1[31 : 16];
  assign slots_hi16_2 = io_iInstr_2[31 : 16];
  assign slots_hi16_3 = io_iInstr_3[31 : 16];
  assign slots_hi16_4 = io_iInstr_4[31 : 16];
  assign slots_hi16_5 = io_iInstr_5[31 : 16];
  assign slots_hi16_6 = io_iInstr_6[31 : 16];
  assign slots_hi16_7 = io_iInstr_7[31 : 16];
  assign slots_hi16_8 = io_iInstr_8[31 : 16];
  assign slots_hi16_9 = io_iInstr_9[31 : 16];
  assign slots_hi16_10 = io_iInstr_10[31 : 16];
  assign slots_hi16_11 = io_iInstr_11[31 : 16];
  assign slots_hi16_12 = io_iInstr_12[31 : 16];
  assign slots_hi16_13 = io_iInstr_13[31 : 16];
  assign _zz_slots_w1_0 = (io_iSlotOff_0 + 8'h01);
  assign _zz_slots_w2_0 = (io_iSlotOff_0 + 8'h02);
  assign slots_body_0 = ((((((_zz_slots_body_0 | _zz_slots_body_0_6) | (_zz_slots_body_0_7 ? slots_hi16_9 : _zz_slots_body_0_8)) | ((io_iSlotOff_0 == _zz_slots_body_0_9) ? slots_hi16_10 : 16'h0)) | ((io_iSlotOff_0 == 8'h0b) ? slots_hi16_11 : 16'h0)) | ((io_iSlotOff_0 == 8'h0c) ? slots_hi16_12 : 16'h0)) | ((io_iSlotOff_0 == 8'h0d) ? slots_hi16_13 : 16'h0));
  assign slots_w1_0 = ((((((_zz_slots_w1_0_1 | _zz_slots_w1_0_7) | (_zz_slots_w1_0_8 ? io_iInstr_9 : _zz_slots_w1_0_9)) | ((_zz_slots_w1_0 == _zz_slots_w1_0_10) ? io_iInstr_10 : 32'h0)) | ((_zz_slots_w1_0 == 8'h0b) ? io_iInstr_11 : 32'h0)) | ((_zz_slots_w1_0 == 8'h0c) ? io_iInstr_12 : 32'h0)) | ((_zz_slots_w1_0 == 8'h0d) ? io_iInstr_13 : 32'h0));
  assign slots_w2_0 = ((((((_zz_slots_w2_0_1 | _zz_slots_w2_0_7) | (_zz_slots_w2_0_8 ? io_iInstr_9 : _zz_slots_w2_0_9)) | ((_zz_slots_w2_0 == _zz_slots_w2_0_10) ? io_iInstr_10 : 32'h0)) | ((_zz_slots_w2_0 == 8'h0b) ? io_iInstr_11 : 32'h0)) | ((_zz_slots_w2_0 == 8'h0c) ? io_iInstr_12 : 32'h0)) | ((_zz_slots_w2_0 == 8'h0d) ? io_iInstr_13 : 32'h0));
  assign _zz_slots_w1_1 = (io_iSlotOff_1 + 8'h01);
  assign _zz_slots_w2_1 = (io_iSlotOff_1 + 8'h02);
  assign slots_body_1 = ((((((_zz_slots_body_1 | _zz_slots_body_1_6) | (_zz_slots_body_1_7 ? slots_hi16_9 : _zz_slots_body_1_8)) | ((io_iSlotOff_1 == _zz_slots_body_1_9) ? slots_hi16_10 : 16'h0)) | ((io_iSlotOff_1 == 8'h0b) ? slots_hi16_11 : 16'h0)) | ((io_iSlotOff_1 == 8'h0c) ? slots_hi16_12 : 16'h0)) | ((io_iSlotOff_1 == 8'h0d) ? slots_hi16_13 : 16'h0));
  assign slots_w1_1 = ((((((_zz_slots_w1_1_1 | _zz_slots_w1_1_7) | (_zz_slots_w1_1_8 ? io_iInstr_9 : _zz_slots_w1_1_9)) | ((_zz_slots_w1_1 == _zz_slots_w1_1_10) ? io_iInstr_10 : 32'h0)) | ((_zz_slots_w1_1 == 8'h0b) ? io_iInstr_11 : 32'h0)) | ((_zz_slots_w1_1 == 8'h0c) ? io_iInstr_12 : 32'h0)) | ((_zz_slots_w1_1 == 8'h0d) ? io_iInstr_13 : 32'h0));
  assign slots_w2_1 = ((((((_zz_slots_w2_1_1 | _zz_slots_w2_1_7) | (_zz_slots_w2_1_8 ? io_iInstr_9 : _zz_slots_w2_1_9)) | ((_zz_slots_w2_1 == _zz_slots_w2_1_10) ? io_iInstr_10 : 32'h0)) | ((_zz_slots_w2_1 == 8'h0b) ? io_iInstr_11 : 32'h0)) | ((_zz_slots_w2_1 == 8'h0c) ? io_iInstr_12 : 32'h0)) | ((_zz_slots_w2_1 == 8'h0d) ? io_iInstr_13 : 32'h0));
  assign _zz_slots_w1_2 = (io_iSlotOff_2 + 8'h01);
  assign _zz_slots_w2_2 = (io_iSlotOff_2 + 8'h02);
  assign slots_body_2 = ((((((_zz_slots_body_2 | _zz_slots_body_2_6) | (_zz_slots_body_2_7 ? slots_hi16_9 : _zz_slots_body_2_8)) | ((io_iSlotOff_2 == _zz_slots_body_2_9) ? slots_hi16_10 : 16'h0)) | ((io_iSlotOff_2 == 8'h0b) ? slots_hi16_11 : 16'h0)) | ((io_iSlotOff_2 == 8'h0c) ? slots_hi16_12 : 16'h0)) | ((io_iSlotOff_2 == 8'h0d) ? slots_hi16_13 : 16'h0));
  assign slots_w1_2 = ((((((_zz_slots_w1_2_1 | _zz_slots_w1_2_7) | (_zz_slots_w1_2_8 ? io_iInstr_9 : _zz_slots_w1_2_9)) | ((_zz_slots_w1_2 == _zz_slots_w1_2_10) ? io_iInstr_10 : 32'h0)) | ((_zz_slots_w1_2 == 8'h0b) ? io_iInstr_11 : 32'h0)) | ((_zz_slots_w1_2 == 8'h0c) ? io_iInstr_12 : 32'h0)) | ((_zz_slots_w1_2 == 8'h0d) ? io_iInstr_13 : 32'h0));
  assign slots_w2_2 = ((((((_zz_slots_w2_2_1 | _zz_slots_w2_2_7) | (_zz_slots_w2_2_8 ? io_iInstr_9 : _zz_slots_w2_2_9)) | ((_zz_slots_w2_2 == _zz_slots_w2_2_10) ? io_iInstr_10 : 32'h0)) | ((_zz_slots_w2_2 == 8'h0b) ? io_iInstr_11 : 32'h0)) | ((_zz_slots_w2_2 == 8'h0c) ? io_iInstr_12 : 32'h0)) | ((_zz_slots_w2_2 == 8'h0d) ? io_iInstr_13 : 32'h0));
  assign _zz_slots_w1_3 = (io_iSlotOff_3 + 8'h01);
  assign _zz_slots_w2_3 = (io_iSlotOff_3 + 8'h02);
  assign slots_body_3 = ((((((_zz_slots_body_3 | _zz_slots_body_3_6) | (_zz_slots_body_3_7 ? slots_hi16_9 : _zz_slots_body_3_8)) | ((io_iSlotOff_3 == _zz_slots_body_3_9) ? slots_hi16_10 : 16'h0)) | ((io_iSlotOff_3 == 8'h0b) ? slots_hi16_11 : 16'h0)) | ((io_iSlotOff_3 == 8'h0c) ? slots_hi16_12 : 16'h0)) | ((io_iSlotOff_3 == 8'h0d) ? slots_hi16_13 : 16'h0));
  assign slots_w1_3 = ((((((_zz_slots_w1_3_1 | _zz_slots_w1_3_7) | (_zz_slots_w1_3_8 ? io_iInstr_9 : _zz_slots_w1_3_9)) | ((_zz_slots_w1_3 == _zz_slots_w1_3_10) ? io_iInstr_10 : 32'h0)) | ((_zz_slots_w1_3 == 8'h0b) ? io_iInstr_11 : 32'h0)) | ((_zz_slots_w1_3 == 8'h0c) ? io_iInstr_12 : 32'h0)) | ((_zz_slots_w1_3 == 8'h0d) ? io_iInstr_13 : 32'h0));
  assign slots_w2_3 = ((((((_zz_slots_w2_3_1 | _zz_slots_w2_3_7) | (_zz_slots_w2_3_8 ? io_iInstr_9 : _zz_slots_w2_3_9)) | ((_zz_slots_w2_3 == _zz_slots_w2_3_10) ? io_iInstr_10 : 32'h0)) | ((_zz_slots_w2_3 == 8'h0b) ? io_iInstr_11 : 32'h0)) | ((_zz_slots_w2_3 == 8'h0c) ? io_iInstr_12 : 32'h0)) | ((_zz_slots_w2_3 == 8'h0d) ? io_iInstr_13 : 32'h0));
  assign parse_isPort_0 = (io_iSlotPresent_0 && (io_iSlotCode_0 == 4'b0001));
  assign parse_isPort_1 = (io_iSlotPresent_1 && (io_iSlotCode_1 == 4'b0001));
  assign parse_isPort_2 = (io_iSlotPresent_2 && (io_iSlotCode_2 == 4'b0001));
  assign parse_isPort_3 = (io_iSlotPresent_3 && (io_iSlotCode_3 == 4'b0001));
  assign parse_isImm16_0 = (io_iSlotPresent_0 && (io_iSlotCode_0 == 4'b0010));
  assign parse_isImm16_1 = (io_iSlotPresent_1 && (io_iSlotCode_1 == 4'b0010));
  assign parse_isImm16_2 = (io_iSlotPresent_2 && (io_iSlotCode_2 == 4'b0010));
  assign parse_isImm16_3 = (io_iSlotPresent_3 && (io_iSlotCode_3 == 4'b0010));
  assign parse_isImm32_0 = (io_iSlotPresent_0 && (io_iSlotCode_0 == 4'b0011));
  assign parse_isImm32_1 = (io_iSlotPresent_1 && (io_iSlotCode_1 == 4'b0011));
  assign parse_isImm32_2 = (io_iSlotPresent_2 && (io_iSlotCode_2 == 4'b0011));
  assign parse_isImm32_3 = (io_iSlotPresent_3 && (io_iSlotCode_3 == 4'b0011));
  assign parse_isImm64_0 = (io_iSlotPresent_0 && (io_iSlotCode_0 == 4'b0100));
  assign parse_isImm64_1 = (io_iSlotPresent_1 && (io_iSlotCode_1 == 4'b0100));
  assign parse_isImm64_2 = (io_iSlotPresent_2 && (io_iSlotCode_2 == 4'b0100));
  assign parse_isImm64_3 = (io_iSlotPresent_3 && (io_iSlotCode_3 == 4'b0100));
  assign parse_isMem_0 = (io_iSlotPresent_0 && (io_iSlotCode_0 == 4'b0101));
  assign parse_isMem_1 = (io_iSlotPresent_1 && (io_iSlotCode_1 == 4'b0101));
  assign parse_isMem_2 = (io_iSlotPresent_2 && (io_iSlotCode_2 == 4'b0101));
  assign parse_isMem_3 = (io_iSlotPresent_3 && (io_iSlotCode_3 == 4'b0101));
  assign parse_isSub_0 = (io_iSlotPresent_0 && (io_iSlotCode_0 == 4'b0110));
  assign parse_isSub_1 = (io_iSlotPresent_1 && (io_iSlotCode_1 == 4'b0110));
  assign parse_isSub_2 = (io_iSlotPresent_2 && (io_iSlotCode_2 == 4'b0110));
  assign parse_isSub_3 = (io_iSlotPresent_3 && (io_iSlotCode_3 == 4'b0110));
  assign parse_isOpref_0 = (io_iSlotPresent_0 && (io_iSlotCode_0 == 4'b0111));
  assign parse_isOpref_1 = (io_iSlotPresent_1 && (io_iSlotCode_1 == 4'b0111));
  assign parse_isOpref_2 = (io_iSlotPresent_2 && (io_iSlotCode_2 == 4'b0111));
  assign parse_isOpref_3 = (io_iSlotPresent_3 && (io_iSlotCode_3 == 4'b0111));
  assign parse_isPrec_0 = (io_iSlotPresent_0 && (io_iSlotCode_0 == 4'b1000));
  assign parse_isPrec_1 = (io_iSlotPresent_1 && (io_iSlotCode_1 == 4'b1000));
  assign parse_isPrec_2 = (io_iSlotPresent_2 && (io_iSlotCode_2 == 4'b1000));
  assign parse_isPrec_3 = (io_iSlotPresent_3 && (io_iSlotCode_3 == 4'b1000));
  assign parse_isAcctgt_0 = (io_iSlotPresent_0 && (io_iSlotCode_0 == 4'b1001));
  assign parse_isAcctgt_1 = (io_iSlotPresent_1 && (io_iSlotCode_1 == 4'b1001));
  assign parse_isAcctgt_2 = (io_iSlotPresent_2 && (io_iSlotCode_2 == 4'b1001));
  assign parse_isAcctgt_3 = (io_iSlotPresent_3 && (io_iSlotCode_3 == 4'b1001));
  assign parse_portPresent = (((parse_isPort_0 || parse_isPort_1) || parse_isPort_2) || parse_isPort_3);
  assign parse_portDest = ((((parse_isPort_0 ? slots_body_0 : 16'h0) | (parse_isPort_1 ? slots_body_1 : 16'h0)) | (parse_isPort_2 ? slots_body_2 : 16'h0)) | (parse_isPort_3 ? slots_body_3 : 16'h0));
  assign parse_imm16Present = (((parse_isImm16_0 || parse_isImm16_1) || parse_isImm16_2) || parse_isImm16_3);
  assign parse_imm16 = ((((parse_isImm16_0 ? slots_body_0 : 16'h0) | (parse_isImm16_1 ? slots_body_1 : 16'h0)) | (parse_isImm16_2 ? slots_body_2 : 16'h0)) | (parse_isImm16_3 ? slots_body_3 : 16'h0));
  assign parse_imm32Present = (((parse_isImm32_0 || parse_isImm32_1) || parse_isImm32_2) || parse_isImm32_3);
  assign parse_imm32 = ((((parse_isImm32_0 ? slots_w1_0 : 32'h0) | (parse_isImm32_1 ? slots_w1_1 : 32'h0)) | (parse_isImm32_2 ? slots_w1_2 : 32'h0)) | (parse_isImm32_3 ? slots_w1_3 : 32'h0));
  assign parse_imm64Present = (((parse_isImm64_0 || parse_isImm64_1) || parse_isImm64_2) || parse_isImm64_3);
  assign parse_imm64 = {((((parse_isImm64_0 ? slots_w2_0 : _zz_parse_imm64) | (parse_isImm64_1 ? slots_w2_1 : _zz_parse_imm64_1)) | (parse_isImm64_2 ? slots_w2_2 : 32'h0)) | (parse_isImm64_3 ? slots_w2_3 : 32'h0)),((((parse_isImm64_0 ? slots_w1_0 : _zz_parse_imm64_2) | (parse_isImm64_1 ? slots_w1_1 : _zz_parse_imm64_3)) | (parse_isImm64_2 ? slots_w1_2 : 32'h0)) | (parse_isImm64_3 ? slots_w1_3 : 32'h0))};
  assign parse_memPresent = (((parse_isMem_0 || parse_isMem_1) || parse_isMem_2) || parse_isMem_3);
  assign parse_memAddrMode = ((((parse_isMem_0 ? slots_body_0[3 : 0] : 4'b0000) | (parse_isMem_1 ? slots_body_1[3 : 0] : 4'b0000)) | (parse_isMem_2 ? slots_body_2[3 : 0] : 4'b0000)) | (parse_isMem_3 ? slots_body_3[3 : 0] : 4'b0000));
  assign parse_memStride = ((((parse_isMem_0 ? slots_body_0[15 : 4] : 12'h0) | (parse_isMem_1 ? slots_body_1[15 : 4] : 12'h0)) | (parse_isMem_2 ? slots_body_2[15 : 4] : 12'h0)) | (parse_isMem_3 ? slots_body_3[15 : 4] : 12'h0));
  assign parse_memOffset = ((((parse_isMem_0 ? slots_w1_0 : 32'h0) | (parse_isMem_1 ? slots_w1_1 : 32'h0)) | (parse_isMem_2 ? slots_w1_2 : 32'h0)) | (parse_isMem_3 ? slots_w1_3 : 32'h0));
  assign parse_precPresent = (((parse_isPrec_0 || parse_isPrec_1) || parse_isPrec_2) || parse_isPrec_3);
  assign parse_precMode = ((((parse_isPrec_0 ? slots_body_0[7 : 0] : 8'h0) | (parse_isPrec_1 ? slots_body_1[7 : 0] : 8'h0)) | (parse_isPrec_2 ? slots_body_2[7 : 0] : 8'h0)) | (parse_isPrec_3 ? slots_body_3[7 : 0] : 8'h0));
  assign parse_precDim = ((((parse_isPrec_0 ? slots_body_0[15 : 8] : 8'h0) | (parse_isPrec_1 ? slots_body_1[15 : 8] : 8'h0)) | (parse_isPrec_2 ? slots_body_2[15 : 8] : 8'h0)) | (parse_isPrec_3 ? slots_body_3[15 : 8] : 8'h0));
  assign parse_acctgtPresent = (((parse_isAcctgt_0 || parse_isAcctgt_1) || parse_isAcctgt_2) || parse_isAcctgt_3);
  assign parse_acctgtLbid = ((((parse_isAcctgt_0 ? slots_body_0[15 : 8] : 8'h0) | (parse_isAcctgt_1 ? slots_body_1[15 : 8] : 8'h0)) | (parse_isAcctgt_2 ? slots_body_2[15 : 8] : 8'h0)) | (parse_isAcctgt_3 ? slots_body_3[15 : 8] : 8'h0));
  assign parse_acctgtTotal = ((((parse_isAcctgt_0 ? slots_body_0[7 : 0] : 8'h0) | (parse_isAcctgt_1 ? slots_body_1[7 : 0] : 8'h0)) | (parse_isAcctgt_2 ? slots_body_2[7 : 0] : 8'h0)) | (parse_isAcctgt_3 ? slots_body_3[7 : 0] : 8'h0));
  assign parse_oprefA_0 = (parse_isOpref_0 && (3'b000 == 3'b000));
  assign parse_oprefA_1 = (parse_isOpref_1 && (_zz_parse_oprefA_1 == 3'b000));
  assign parse_oprefA_2 = (parse_isOpref_2 && (_zz_parse_oprefA_2 == 3'b000));
  assign parse_oprefA_3 = (parse_isOpref_3 && (_zz_parse_oprefA_3 == 3'b000));
  assign parse_oprefB_0 = (parse_isOpref_0 && (3'b000 == 3'b001));
  assign parse_oprefB_1 = (parse_isOpref_1 && (_zz_parse_oprefB_1 == 3'b001));
  assign parse_oprefB_2 = (parse_isOpref_2 && (_zz_parse_oprefB_2 == 3'b001));
  assign parse_oprefB_3 = (parse_isOpref_3 && (_zz_parse_oprefB_3 == 3'b001));
  assign parse_oprefAValid = (((parse_oprefA_0 || parse_oprefA_1) || parse_oprefA_2) || parse_oprefA_3);
  assign parse_oprefBValid = (((parse_oprefB_0 || parse_oprefB_1) || parse_oprefB_2) || parse_oprefB_3);
  assign parse_oprefALbid = ((((parse_oprefA_0 ? slots_body_0[15 : 8] : 8'h0) | (parse_oprefA_1 ? slots_body_1[15 : 8] : 8'h0)) | (parse_oprefA_2 ? slots_body_2[15 : 8] : 8'h0)) | (parse_oprefA_3 ? slots_body_3[15 : 8] : 8'h0));
  assign parse_oprefASrcKind = ((((parse_oprefA_0 ? slots_body_0[3 : 0] : 4'b0000) | (parse_oprefA_1 ? slots_body_1[3 : 0] : 4'b0000)) | (parse_oprefA_2 ? slots_body_2[3 : 0] : 4'b0000)) | (parse_oprefA_3 ? slots_body_3[3 : 0] : 4'b0000));
  assign parse_oprefBLbid = ((((parse_oprefB_0 ? slots_body_0[15 : 8] : 8'h0) | (parse_oprefB_1 ? slots_body_1[15 : 8] : 8'h0)) | (parse_oprefB_2 ? slots_body_2[15 : 8] : 8'h0)) | (parse_oprefB_3 ? slots_body_3[15 : 8] : 8'h0));
  assign parse_oprefBSrcKind = ((((parse_oprefB_0 ? slots_body_0[3 : 0] : 4'b0000) | (parse_oprefB_1 ? slots_body_1[3 : 0] : 4'b0000)) | (parse_oprefB_2 ? slots_body_2[3 : 0] : 4'b0000)) | (parse_oprefB_3 ? slots_body_3[3 : 0] : 4'b0000));
  assign parse_subSel_0_0 = (parse_isSub_0 && (3'b000 == 3'b000));
  assign parse_subSel_0_1 = (parse_isSub_1 && (_zz_parse_subSel_0_1 == 3'b000));
  assign parse_subSel_0_2 = (parse_isSub_2 && (_zz_parse_subSel_0_2 == 3'b000));
  assign parse_subSel_0_3 = (parse_isSub_3 && (_zz_parse_subSel_0_3 == 3'b000));
  assign parse_subSel_1_0 = (parse_isSub_0 && (3'b000 == 3'b001));
  assign parse_subSel_1_1 = (parse_isSub_1 && (_zz_parse_subSel_1_1 == 3'b001));
  assign parse_subSel_1_2 = (parse_isSub_2 && (_zz_parse_subSel_1_2 == 3'b001));
  assign parse_subSel_1_3 = (parse_isSub_3 && (_zz_parse_subSel_1_3 == 3'b001));
  assign parse_subSel_2_0 = (parse_isSub_0 && (3'b000 == 3'b010));
  assign parse_subSel_2_1 = (parse_isSub_1 && (_zz_parse_subSel_2_1 == 3'b010));
  assign parse_subSel_2_2 = (parse_isSub_2 && (_zz_parse_subSel_2_2 == 3'b010));
  assign parse_subSel_2_3 = (parse_isSub_3 && (_zz_parse_subSel_2_3 == 3'b010));
  assign parse_subSel_3_0 = (parse_isSub_0 && (3'b000 == 3'b011));
  assign parse_subSel_3_1 = (parse_isSub_1 && (_zz_parse_subSel_3_1 == 3'b011));
  assign parse_subSel_3_2 = (parse_isSub_2 && (_zz_parse_subSel_3_2 == 3'b011));
  assign parse_subSel_3_3 = (parse_isSub_3 && (_zz_parse_subSel_3_3 == 3'b011));
  assign parse_subValid_0 = (((parse_subSel_0_0 || parse_subSel_0_1) || parse_subSel_0_2) || parse_subSel_0_3);
  assign parse_subValid_1 = (((parse_subSel_1_0 || parse_subSel_1_1) || parse_subSel_1_2) || parse_subSel_1_3);
  assign parse_subValid_2 = (((parse_subSel_2_0 || parse_subSel_2_1) || parse_subSel_2_2) || parse_subSel_2_3);
  assign parse_subValid_3 = (((parse_subSel_3_0 || parse_subSel_3_1) || parse_subSel_3_2) || parse_subSel_3_3);
  assign parse_subO_0 = ((((parse_subSel_0_0 ? slots_body_0 : 16'h0) | (parse_subSel_0_1 ? slots_body_1 : 16'h0)) | (parse_subSel_0_2 ? slots_body_2 : 16'h0)) | (parse_subSel_0_3 ? slots_body_3 : 16'h0));
  assign parse_subO_1 = ((((parse_subSel_1_0 ? slots_body_0 : 16'h0) | (parse_subSel_1_1 ? slots_body_1 : 16'h0)) | (parse_subSel_1_2 ? slots_body_2 : 16'h0)) | (parse_subSel_1_3 ? slots_body_3 : 16'h0));
  assign parse_subO_2 = ((((parse_subSel_2_0 ? slots_body_0 : 16'h0) | (parse_subSel_2_1 ? slots_body_1 : 16'h0)) | (parse_subSel_2_2 ? slots_body_2 : 16'h0)) | (parse_subSel_2_3 ? slots_body_3 : 16'h0));
  assign parse_subO_3 = ((((parse_subSel_3_0 ? slots_body_0 : 16'h0) | (parse_subSel_3_1 ? slots_body_1 : 16'h0)) | (parse_subSel_3_2 ? slots_body_2 : 16'h0)) | (parse_subSel_3_3 ? slots_body_3 : 16'h0));
  assign parse_subA_0 = ((((parse_subSel_0_0 ? slots_w1_0[31 : 16] : 16'h0) | (parse_subSel_0_1 ? slots_w1_1[31 : 16] : 16'h0)) | (parse_subSel_0_2 ? slots_w1_2[31 : 16] : 16'h0)) | (parse_subSel_0_3 ? slots_w1_3[31 : 16] : 16'h0));
  assign parse_subA_1 = ((((parse_subSel_1_0 ? slots_w1_0[31 : 16] : 16'h0) | (parse_subSel_1_1 ? slots_w1_1[31 : 16] : 16'h0)) | (parse_subSel_1_2 ? slots_w1_2[31 : 16] : 16'h0)) | (parse_subSel_1_3 ? slots_w1_3[31 : 16] : 16'h0));
  assign parse_subA_2 = ((((parse_subSel_2_0 ? slots_w1_0[31 : 16] : 16'h0) | (parse_subSel_2_1 ? slots_w1_1[31 : 16] : 16'h0)) | (parse_subSel_2_2 ? slots_w1_2[31 : 16] : 16'h0)) | (parse_subSel_2_3 ? slots_w1_3[31 : 16] : 16'h0));
  assign parse_subA_3 = ((((parse_subSel_3_0 ? slots_w1_0[31 : 16] : 16'h0) | (parse_subSel_3_1 ? slots_w1_1[31 : 16] : 16'h0)) | (parse_subSel_3_2 ? slots_w1_2[31 : 16] : 16'h0)) | (parse_subSel_3_3 ? slots_w1_3[31 : 16] : 16'h0));
  assign parse_subB_0 = ((((parse_subSel_0_0 ? slots_w1_0[15 : 0] : 16'h0) | (parse_subSel_0_1 ? slots_w1_1[15 : 0] : 16'h0)) | (parse_subSel_0_2 ? slots_w1_2[15 : 0] : 16'h0)) | (parse_subSel_0_3 ? slots_w1_3[15 : 0] : 16'h0));
  assign parse_subB_1 = ((((parse_subSel_1_0 ? slots_w1_0[15 : 0] : 16'h0) | (parse_subSel_1_1 ? slots_w1_1[15 : 0] : 16'h0)) | (parse_subSel_1_2 ? slots_w1_2[15 : 0] : 16'h0)) | (parse_subSel_1_3 ? slots_w1_3[15 : 0] : 16'h0));
  assign parse_subB_2 = ((((parse_subSel_2_0 ? slots_w1_0[15 : 0] : 16'h0) | (parse_subSel_2_1 ? slots_w1_1[15 : 0] : 16'h0)) | (parse_subSel_2_2 ? slots_w1_2[15 : 0] : 16'h0)) | (parse_subSel_2_3 ? slots_w1_3[15 : 0] : 16'h0));
  assign parse_subB_3 = ((((parse_subSel_3_0 ? slots_w1_0[15 : 0] : 16'h0) | (parse_subSel_3_1 ? slots_w1_1[15 : 0] : 16'h0)) | (parse_subSel_3_2 ? slots_w1_2[15 : 0] : 16'h0)) | (parse_subSel_3_3 ? slots_w1_3[15 : 0] : 16'h0));
  assign parse_subCount = (_zz_parse_subCount + _zz_parse_subCount_8);
  assign _zz_judge_oprefCrcBad = 4'b0000;
  assign _zz_judge_oprefCrcBad_1 = ({_zz_judge_oprefCrcBad[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad[3] ^ slots_body_0[15]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_2 = ({_zz_judge_oprefCrcBad_1[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_1[3] ^ slots_body_0[14]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_3 = ({_zz_judge_oprefCrcBad_2[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_2[3] ^ slots_body_0[13]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_4 = ({_zz_judge_oprefCrcBad_3[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_3[3] ^ slots_body_0[12]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_5 = ({_zz_judge_oprefCrcBad_4[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_4[3] ^ slots_body_0[11]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_6 = ({_zz_judge_oprefCrcBad_5[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_5[3] ^ slots_body_0[10]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_7 = ({_zz_judge_oprefCrcBad_6[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_6[3] ^ slots_body_0[9]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_8 = ({_zz_judge_oprefCrcBad_7[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_7[3] ^ slots_body_0[8]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_9 = ({_zz_judge_oprefCrcBad_8[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_8[3] ^ slots_body_0[3]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_10 = ({_zz_judge_oprefCrcBad_9[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_9[3] ^ slots_body_0[2]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_11 = ({_zz_judge_oprefCrcBad_10[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_10[3] ^ slots_body_0[1]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_12 = 4'b0000;
  assign _zz_judge_oprefCrcBad_13 = ({_zz_judge_oprefCrcBad_12[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_12[3] ^ slots_body_1[15]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_14 = ({_zz_judge_oprefCrcBad_13[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_13[3] ^ slots_body_1[14]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_15 = ({_zz_judge_oprefCrcBad_14[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_14[3] ^ slots_body_1[13]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_16 = ({_zz_judge_oprefCrcBad_15[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_15[3] ^ slots_body_1[12]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_17 = ({_zz_judge_oprefCrcBad_16[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_16[3] ^ slots_body_1[11]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_18 = ({_zz_judge_oprefCrcBad_17[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_17[3] ^ slots_body_1[10]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_19 = ({_zz_judge_oprefCrcBad_18[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_18[3] ^ slots_body_1[9]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_20 = ({_zz_judge_oprefCrcBad_19[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_19[3] ^ slots_body_1[8]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_21 = ({_zz_judge_oprefCrcBad_20[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_20[3] ^ slots_body_1[3]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_22 = ({_zz_judge_oprefCrcBad_21[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_21[3] ^ slots_body_1[2]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_23 = ({_zz_judge_oprefCrcBad_22[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_22[3] ^ slots_body_1[1]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_24 = 4'b0000;
  assign _zz_judge_oprefCrcBad_25 = ({_zz_judge_oprefCrcBad_24[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_24[3] ^ slots_body_2[15]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_26 = ({_zz_judge_oprefCrcBad_25[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_25[3] ^ slots_body_2[14]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_27 = ({_zz_judge_oprefCrcBad_26[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_26[3] ^ slots_body_2[13]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_28 = ({_zz_judge_oprefCrcBad_27[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_27[3] ^ slots_body_2[12]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_29 = ({_zz_judge_oprefCrcBad_28[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_28[3] ^ slots_body_2[11]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_30 = ({_zz_judge_oprefCrcBad_29[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_29[3] ^ slots_body_2[10]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_31 = ({_zz_judge_oprefCrcBad_30[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_30[3] ^ slots_body_2[9]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_32 = ({_zz_judge_oprefCrcBad_31[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_31[3] ^ slots_body_2[8]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_33 = ({_zz_judge_oprefCrcBad_32[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_32[3] ^ slots_body_2[3]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_34 = ({_zz_judge_oprefCrcBad_33[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_33[3] ^ slots_body_2[2]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_35 = ({_zz_judge_oprefCrcBad_34[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_34[3] ^ slots_body_2[1]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_36 = 4'b0000;
  assign _zz_judge_oprefCrcBad_37 = ({_zz_judge_oprefCrcBad_36[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_36[3] ^ slots_body_3[15]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_38 = ({_zz_judge_oprefCrcBad_37[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_37[3] ^ slots_body_3[14]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_39 = ({_zz_judge_oprefCrcBad_38[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_38[3] ^ slots_body_3[13]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_40 = ({_zz_judge_oprefCrcBad_39[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_39[3] ^ slots_body_3[12]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_41 = ({_zz_judge_oprefCrcBad_40[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_40[3] ^ slots_body_3[11]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_42 = ({_zz_judge_oprefCrcBad_41[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_41[3] ^ slots_body_3[10]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_43 = ({_zz_judge_oprefCrcBad_42[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_42[3] ^ slots_body_3[9]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_44 = ({_zz_judge_oprefCrcBad_43[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_43[3] ^ slots_body_3[8]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_45 = ({_zz_judge_oprefCrcBad_44[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_44[3] ^ slots_body_3[3]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_46 = ({_zz_judge_oprefCrcBad_45[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_45[3] ^ slots_body_3[2]) ? 4'b0011 : 4'b0000));
  assign _zz_judge_oprefCrcBad_47 = ({_zz_judge_oprefCrcBad_46[2 : 0],1'b0} ^ ((_zz_judge_oprefCrcBad_46[3] ^ slots_body_3[1]) ? 4'b0011 : 4'b0000));
  assign judge_oprefCrcBad = ((((parse_isOpref_0 && (_zz_judge_oprefCrcBad_48 != _zz_judge_oprefCrcBad_49)) || (parse_isOpref_1 && (_zz_judge_oprefCrcBad_52 != _zz_judge_oprefCrcBad_53))) || (parse_isOpref_2 && (slots_body_2[7 : 4] != (_zz_judge_oprefCrcBad_56 ^ _zz_judge_oprefCrcBad_57)))) || (parse_isOpref_3 && (slots_body_3[7 : 4] != ({_zz_judge_oprefCrcBad_58,_zz_judge_oprefCrcBad_59} ^ (_zz_judge_oprefCrcBad_60 ? _zz_judge_oprefCrcBad_61 : _zz_judge_oprefCrcBad_62)))));
  assign judge_srcKindBad = ((((parse_isOpref_0 && (4'b0011 <= slots_body_0[3 : 0])) || (parse_isOpref_1 && (4'b0011 <= slots_body_1[3 : 0]))) || (parse_isOpref_2 && (4'b0011 <= slots_body_2[3 : 0]))) || (parse_isOpref_3 && (4'b0011 <= slots_body_3[3 : 0])));
  assign judge_bodyMal = ((! io_iCapAbsent) && (judge_oprefCrcBad || judge_srcKindBad));
  assign io_oValid = io_iValid;
  assign io_oMalformed = (io_iMalformed || judge_bodyMal);
  assign io_oCapAbsent = io_iCapAbsent;
  assign io_oExecValid = (io_iExecValid && (! judge_bodyMal));
  assign io_oPortPresent = (io_oExecValid && parse_portPresent);
  assign io_oPortDest = ((io_oExecValid && parse_portPresent) ? parse_portDest : 16'h0);
  assign io_oImm16Present = (io_oExecValid && parse_imm16Present);
  assign io_oImm16 = ((io_oExecValid && parse_imm16Present) ? parse_imm16 : 16'h0);
  assign io_oImm32Present = (io_oExecValid && parse_imm32Present);
  assign io_oImm32 = ((io_oExecValid && parse_imm32Present) ? parse_imm32 : 32'h0);
  assign io_oImm64Present = (io_oExecValid && parse_imm64Present);
  assign io_oImm64 = ((io_oExecValid && parse_imm64Present) ? parse_imm64 : 64'h0);
  assign io_oMemPresent = (io_oExecValid && parse_memPresent);
  assign io_oMemAddrMode = ((io_oExecValid && parse_memPresent) ? parse_memAddrMode : 4'b0000);
  assign io_oMemStride = ((io_oExecValid && parse_memPresent) ? parse_memStride : 12'h0);
  assign io_oMemOffset = ((io_oExecValid && parse_memPresent) ? parse_memOffset : 32'h0);
  assign io_oSubValid_0 = (io_oExecValid && parse_subValid_0);
  assign io_oSubO_0 = ((io_oExecValid && parse_subValid_0) ? parse_subO_0 : 16'h0);
  assign io_oSubA_0 = ((io_oExecValid && parse_subValid_0) ? parse_subA_0 : 16'h0);
  assign io_oSubB_0 = ((io_oExecValid && parse_subValid_0) ? parse_subB_0 : 16'h0);
  assign io_oSubValid_1 = (io_oExecValid && parse_subValid_1);
  assign io_oSubO_1 = ((io_oExecValid && parse_subValid_1) ? parse_subO_1 : 16'h0);
  assign io_oSubA_1 = ((io_oExecValid && parse_subValid_1) ? parse_subA_1 : 16'h0);
  assign io_oSubB_1 = ((io_oExecValid && parse_subValid_1) ? parse_subB_1 : 16'h0);
  assign io_oSubValid_2 = (io_oExecValid && parse_subValid_2);
  assign io_oSubO_2 = ((io_oExecValid && parse_subValid_2) ? parse_subO_2 : 16'h0);
  assign io_oSubA_2 = ((io_oExecValid && parse_subValid_2) ? parse_subA_2 : 16'h0);
  assign io_oSubB_2 = ((io_oExecValid && parse_subValid_2) ? parse_subB_2 : 16'h0);
  assign io_oSubValid_3 = (io_oExecValid && parse_subValid_3);
  assign io_oSubO_3 = ((io_oExecValid && parse_subValid_3) ? parse_subO_3 : 16'h0);
  assign io_oSubA_3 = ((io_oExecValid && parse_subValid_3) ? parse_subA_3 : 16'h0);
  assign io_oSubB_3 = ((io_oExecValid && parse_subValid_3) ? parse_subB_3 : 16'h0);
  assign io_oSubCount = (io_oExecValid ? parse_subCount : 3'b000);
  assign io_oOprefAValid = (io_oExecValid && parse_oprefAValid);
  assign io_oOprefALbid = ((io_oExecValid && parse_oprefAValid) ? parse_oprefALbid : 8'h0);
  assign io_oOprefASrcKind = ((io_oExecValid && parse_oprefAValid) ? parse_oprefASrcKind : 4'b0000);
  assign io_oOprefBValid = (io_oExecValid && parse_oprefBValid);
  assign io_oOprefBLbid = ((io_oExecValid && parse_oprefBValid) ? parse_oprefBLbid : 8'h0);
  assign io_oOprefBSrcKind = ((io_oExecValid && parse_oprefBValid) ? parse_oprefBSrcKind : 4'b0000);
  assign io_oPrecPresent = (io_oExecValid && parse_precPresent);
  assign io_oPrecMode = ((io_oExecValid && parse_precPresent) ? parse_precMode : 8'h0);
  assign io_oPrecDim = ((io_oExecValid && parse_precPresent) ? parse_precDim : 8'h0);
  assign io_oReasmBind_valid = (io_oExecValid && parse_acctgtPresent);
  assign io_oReasmBind_payload = ((io_oExecValid && parse_acctgtPresent) ? parse_acctgtLbid : 8'h0);
  assign io_oAcctgtTotal = ((io_oExecValid && parse_acctgtPresent) ? parse_acctgtTotal : 8'h0);
  assign when_Common_l259 = (io_iValid && judge_bodyMal);
  assign io_oFault = _zz_io_oFault;
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      _zz_io_oFault <= 1'b0;
    end else begin
      if(io_iFaultClear) begin
        _zz_io_oFault <= 1'b0;
      end
      if(when_Common_l259) begin
        _zz_io_oFault <= 1'b1;
      end
    end
  end


endmodule
