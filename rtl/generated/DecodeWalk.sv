// Generator : SpinalHDL v1.14.2    git head : 78f29dc66110fc099a777992b6daa2f803ab445e
// Component : DecodeWalk
// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
// 
// === 생성물이다. 손으로 고치지 말 것. ===
// 고칠 곳은 rtl/spinal/ 의 생성기이고, 고친 뒤 `make rtl-gen` 으로 다시 낸다.
// 여기 직접 쓴 수정은 다음 생성에서 조용히 사라진다.

`timescale 1ns/1ps

module DecodeWalk (
  input  wire          io_iValid,
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
  input  wire          io_iFaultClear,
  output wire          io_oValid,
  output wire          io_oMalformed,
  output wire          io_oCapAbsent,
  output wire          io_oExecValid,
  output wire [31:0]   io_oInstr_0,
  output wire [31:0]   io_oInstr_1,
  output wire [31:0]   io_oInstr_2,
  output wire [31:0]   io_oInstr_3,
  output wire [31:0]   io_oInstr_4,
  output wire [31:0]   io_oInstr_5,
  output wire [31:0]   io_oInstr_6,
  output wire [31:0]   io_oInstr_7,
  output wire [31:0]   io_oInstr_8,
  output wire [31:0]   io_oInstr_9,
  output wire [31:0]   io_oInstr_10,
  output wire [31:0]   io_oInstr_11,
  output wire [31:0]   io_oInstr_12,
  output wire          io_oSlotPresent_0,
  output wire          io_oSlotPresent_1,
  output wire          io_oSlotPresent_2,
  output wire          io_oSlotPresent_3,
  output wire [3:0]    io_oSlotCode_0,
  output wire [3:0]    io_oSlotCode_1,
  output wire [3:0]    io_oSlotCode_2,
  output wire [3:0]    io_oSlotCode_3,
  output wire [7:0]    io_oSlotOff_0,
  output wire [7:0]    io_oSlotOff_1,
  output wire [7:0]    io_oSlotOff_2,
  output wire [7:0]    io_oSlotOff_3,
  output wire          io_oFault,
  input  wire          clk,
  input  wire          reset
);

  reg        [15:0]   _zz_walk_head_0;
  wire       [3:0]    _zz_walk_head_0_1;
  reg                 _zz_walk_defd_0;
  wire       [3:0]    _zz_walk_defd_0_1;
  reg        [7:0]    _zz_walk_stepW_0;
  wire       [3:0]    _zz_walk_stepW_0_1;
  reg        [15:0]   _zz_walk_head_1;
  wire       [3:0]    _zz_walk_head_1_1;
  reg                 _zz_walk_defd_1;
  wire       [3:0]    _zz_walk_defd_1_1;
  reg        [7:0]    _zz_walk_stepW_1;
  wire       [3:0]    _zz_walk_stepW_1_1;
  reg        [15:0]   _zz_walk_head_2;
  wire       [3:0]    _zz_walk_head_2_1;
  reg                 _zz_walk_defd_2;
  wire       [3:0]    _zz_walk_defd_2_1;
  reg        [7:0]    _zz_walk_stepW_2;
  wire       [3:0]    _zz_walk_stepW_2_1;
  reg        [15:0]   _zz_walk_head_3;
  wire       [3:0]    _zz_walk_head_3_1;
  reg                 _zz_walk_defd_3;
  wire       [3:0]    _zz_walk_defd_3_1;
  reg        [7:0]    _zz_walk_stepW_3;
  wire       [3:0]    _zz_walk_stepW_3_1;
  wire       [2:0]    _zz_judge_dupBad;
  wire       [2:0]    _zz_judge_dupBad_1;
  wire       [2:0]    _zz_judge_dupBad_2;
  wire       [2:0]    _zz_judge_dupBad_3;
  wire       [0:0]    _zz_judge_dupBad_4;
  wire       [2:0]    _zz_judge_dupBad_5;
  wire       [0:0]    _zz_judge_dupBad_6;
  wire       [2:0]    _zz_judge_dupBad_7;
  wire       [0:0]    _zz_judge_dupBad_8;
  wire       [2:0]    _zz_judge_dupBad_9;
  wire       [0:0]    _zz_judge_dupBad_10;
  wire       [2:0]    _zz_judge_dupBad_11;
  wire       [2:0]    _zz_judge_dupBad_12;
  wire       [2:0]    _zz_judge_dupBad_13;
  wire       [2:0]    _zz_judge_dupBad_14;
  wire       [0:0]    _zz_judge_dupBad_15;
  wire       [2:0]    _zz_judge_dupBad_16;
  wire       [0:0]    _zz_judge_dupBad_17;
  wire       [2:0]    _zz_judge_dupBad_18;
  wire       [0:0]    _zz_judge_dupBad_19;
  wire       [2:0]    _zz_judge_dupBad_20;
  wire       [0:0]    _zz_judge_dupBad_21;
  wire       [2:0]    _zz_judge_dupBad_22;
  wire       [2:0]    _zz_judge_dupBad_23;
  wire       [2:0]    _zz_judge_dupBad_24;
  wire       [2:0]    _zz_judge_dupBad_25;
  wire       [0:0]    _zz_judge_dupBad_26;
  wire       [2:0]    _zz_judge_dupBad_27;
  wire       [0:0]    _zz_judge_dupBad_28;
  wire       [2:0]    _zz_judge_dupBad_29;
  wire       [0:0]    _zz_judge_dupBad_30;
  wire       [2:0]    _zz_judge_dupBad_31;
  wire       [0:0]    _zz_judge_dupBad_32;
  wire       [2:0]    _zz_judge_dupBad_33;
  wire       [2:0]    _zz_judge_dupBad_34;
  wire       [2:0]    _zz_judge_dupBad_35;
  wire       [2:0]    _zz_judge_dupBad_36;
  wire       [0:0]    _zz_judge_dupBad_37;
  wire       [2:0]    _zz_judge_dupBad_38;
  wire       [0:0]    _zz_judge_dupBad_39;
  wire       [2:0]    _zz_judge_dupBad_40;
  wire       [0:0]    _zz_judge_dupBad_41;
  wire       [2:0]    _zz_judge_dupBad_42;
  wire       [0:0]    _zz_judge_dupBad_43;
  wire       [2:0]    _zz_judge_dupBad_44;
  wire       [2:0]    _zz_judge_dupBad_45;
  wire       [2:0]    _zz_judge_dupBad_46;
  wire       [2:0]    _zz_judge_dupBad_47;
  wire       [0:0]    _zz_judge_dupBad_48;
  wire       [2:0]    _zz_judge_dupBad_49;
  wire       [0:0]    _zz_judge_dupBad_50;
  wire       [2:0]    _zz_judge_dupBad_51;
  wire       [0:0]    _zz_judge_dupBad_52;
  wire       [2:0]    _zz_judge_dupBad_53;
  wire       [0:0]    _zz_judge_dupBad_54;
  wire       [2:0]    _zz_judge_dupBad_55;
  wire       [2:0]    _zz_judge_dupBad_56;
  wire       [2:0]    _zz_judge_dupBad_57;
  wire       [2:0]    _zz_judge_dupBad_58;
  wire       [0:0]    _zz_judge_dupBad_59;
  wire       [2:0]    _zz_judge_dupBad_60;
  wire       [0:0]    _zz_judge_dupBad_61;
  wire       [2:0]    _zz_judge_dupBad_62;
  wire       [0:0]    _zz_judge_dupBad_63;
  wire       [2:0]    _zz_judge_dupBad_64;
  wire       [0:0]    _zz_judge_dupBad_65;
  wire       [2:0]    _zz_judge_dupBad_66;
  wire       [2:0]    _zz_judge_dupBad_67;
  wire       [2:0]    _zz_judge_dupBad_68;
  wire       [2:0]    _zz_judge_dupBad_69;
  wire       [0:0]    _zz_judge_dupBad_70;
  wire       [2:0]    _zz_judge_dupBad_71;
  wire       [0:0]    _zz_judge_dupBad_72;
  wire       [2:0]    _zz_judge_dupBad_73;
  wire       [0:0]    _zz_judge_dupBad_74;
  wire       [2:0]    _zz_judge_dupBad_75;
  wire       [0:0]    _zz_judge_dupBad_76;
  wire       [2:0]    _zz_judge_dupBad_77;
  wire       [2:0]    _zz_judge_dupBad_78;
  wire       [2:0]    _zz_judge_dupBad_79;
  wire       [2:0]    _zz_judge_dupBad_80;
  wire       [0:0]    _zz_judge_dupBad_81;
  wire       [2:0]    _zz_judge_dupBad_82;
  wire       [0:0]    _zz_judge_dupBad_83;
  wire       [2:0]    _zz_judge_dupBad_84;
  wire       [0:0]    _zz_judge_dupBad_85;
  wire       [2:0]    _zz_judge_dupBad_86;
  wire       [0:0]    _zz_judge_dupBad_87;
  wire                kindDefined_0;
  wire                kindDefined_1;
  wire                kindDefined_2;
  wire                kindDefined_3;
  wire                kindDefined_4;
  wire                kindDefined_5;
  wire                kindDefined_6;
  wire                kindDefined_7;
  wire                kindDefined_8;
  wire                kindDefined_9;
  wire                kindDefined_10;
  wire                kindDefined_11;
  wire                kindDefined_12;
  wire                kindDefined_13;
  wire                kindDefined_14;
  wire                kindDefined_15;
  wire       [7:0]    kindWords_0;
  wire       [7:0]    kindWords_1;
  wire       [7:0]    kindWords_2;
  wire       [7:0]    kindWords_3;
  wire       [7:0]    kindWords_4;
  wire       [7:0]    kindWords_5;
  wire       [7:0]    kindWords_6;
  wire       [7:0]    kindWords_7;
  wire       [7:0]    kindWords_8;
  wire       [7:0]    kindWords_9;
  wire       [7:0]    kindWords_10;
  wire       [7:0]    kindWords_11;
  wire       [7:0]    kindWords_12;
  wire       [7:0]    kindWords_13;
  wire       [7:0]    kindWords_14;
  wire       [7:0]    kindWords_15;
  wire       [15:0]   walk_lo16_0;
  wire       [15:0]   walk_lo16_1;
  wire       [15:0]   walk_lo16_2;
  wire       [15:0]   walk_lo16_3;
  wire       [15:0]   walk_lo16_4;
  wire       [15:0]   walk_lo16_5;
  wire       [15:0]   walk_lo16_6;
  wire       [15:0]   walk_lo16_7;
  wire       [15:0]   walk_lo16_8;
  wire       [15:0]   walk_lo16_9;
  wire       [15:0]   walk_lo16_10;
  wire       [15:0]   walk_lo16_11;
  wire       [15:0]   walk_lo16_12;
  wire       [3:0]    walk_ptr_0;
  wire       [3:0]    walk_ptr_1;
  wire       [3:0]    walk_ptr_2;
  wire       [3:0]    walk_ptr_3;
  wire       [3:0]    walk_ptr_4;
  wire                walk_ended_0;
  wire                walk_ended_1;
  wire                walk_ended_2;
  wire                walk_ended_3;
  wire                walk_ended_4;
  wire                walk_walked_0;
  wire                walk_walked_1;
  wire                walk_walked_2;
  wire                walk_walked_3;
  wire       [7:0]    walk_off_0;
  wire       [7:0]    walk_off_1;
  wire       [7:0]    walk_off_2;
  wire       [7:0]    walk_off_3;
  wire       [7:0]    walk_off_4;
  wire       [15:0]   walk_head_0;
  wire       [15:0]   walk_head_1;
  wire       [15:0]   walk_head_2;
  wire       [15:0]   walk_head_3;
  wire       [3:0]    walk_selfCode_0;
  wire       [3:0]    walk_selfCode_1;
  wire       [3:0]    walk_selfCode_2;
  wire       [3:0]    walk_selfCode_3;
  wire       [7:0]    walk_wordsFld_0;
  wire       [7:0]    walk_wordsFld_1;
  wire       [7:0]    walk_wordsFld_2;
  wire       [7:0]    walk_wordsFld_3;
  wire                walk_defd_0;
  wire                walk_defd_1;
  wire                walk_defd_2;
  wire                walk_defd_3;
  wire       [7:0]    walk_stepW_0;
  wire       [7:0]    walk_stepW_1;
  wire       [7:0]    walk_stepW_2;
  wire       [7:0]    walk_stepW_3;
  wire       [7:0]    judge_declLen;
  wire       [7:0]    judge_resvFld;
  wire                judge_capAbsent;
  wire                judge_lenBad;
  wire                judge_capBad;
  wire                judge_junkBad;
  wire                judge_selfBad;
  wire                judge_wordsBad;
  wire                judge_dupBad;
  wire                judge_resvBad;
  wire                judge_mal;
  reg                 outStage_rValid;
  reg                 outStage_rMal;
  reg                 outStage_rCapa;
  reg        [31:0]   outStage_masked_0;
  wire       [31:0]   outStage_masked_1;
  wire       [31:0]   outStage_masked_2;
  wire       [31:0]   outStage_masked_3;
  wire       [31:0]   outStage_masked_4;
  wire       [31:0]   outStage_masked_5;
  wire       [31:0]   outStage_masked_6;
  wire       [31:0]   outStage_masked_7;
  wire       [31:0]   outStage_masked_8;
  wire       [31:0]   outStage_masked_9;
  wire       [31:0]   outStage_masked_10;
  wire       [31:0]   outStage_masked_11;
  wire       [31:0]   outStage_masked_12;
  reg        [31:0]   outStage_rInstr_0;
  reg        [31:0]   outStage_rInstr_1;
  reg        [31:0]   outStage_rInstr_2;
  reg        [31:0]   outStage_rInstr_3;
  reg        [31:0]   outStage_rInstr_4;
  reg        [31:0]   outStage_rInstr_5;
  reg        [31:0]   outStage_rInstr_6;
  reg        [31:0]   outStage_rInstr_7;
  reg        [31:0]   outStage_rInstr_8;
  reg        [31:0]   outStage_rInstr_9;
  reg        [31:0]   outStage_rInstr_10;
  reg        [31:0]   outStage_rInstr_11;
  reg        [31:0]   outStage_rInstr_12;
  reg                 outStage_rPresent_0;
  reg                 outStage_rPresent_1;
  reg                 outStage_rPresent_2;
  reg                 outStage_rPresent_3;
  reg        [3:0]    outStage_rCode_0;
  reg        [3:0]    outStage_rCode_1;
  reg        [3:0]    outStage_rCode_2;
  reg        [3:0]    outStage_rCode_3;
  reg        [7:0]    outStage_rOff_0;
  reg        [7:0]    outStage_rOff_1;
  reg        [7:0]    outStage_rOff_2;
  reg        [7:0]    outStage_rOff_3;
  wire                when_Common_l259;
  reg                 _zz_io_oFault;

  assign _zz_walk_head_0_1 = walk_off_0[3:0];
  assign _zz_walk_head_1_1 = walk_off_1[3:0];
  assign _zz_walk_head_2_1 = walk_off_2[3:0];
  assign _zz_walk_head_3_1 = walk_off_3[3:0];
  assign _zz_judge_dupBad = (_zz_judge_dupBad_1 + _zz_judge_dupBad_9);
  assign _zz_judge_dupBad_1 = (_zz_judge_dupBad_2 + _zz_judge_dupBad_7);
  assign _zz_judge_dupBad_2 = (_zz_judge_dupBad_3 + _zz_judge_dupBad_5);
  assign _zz_judge_dupBad_4 = (walk_walked_0 && (walk_ptr_0 == 4'b0101));
  assign _zz_judge_dupBad_3 = {2'd0, _zz_judge_dupBad_4};
  assign _zz_judge_dupBad_6 = (walk_walked_1 && (walk_ptr_1 == 4'b0101));
  assign _zz_judge_dupBad_5 = {2'd0, _zz_judge_dupBad_6};
  assign _zz_judge_dupBad_8 = (walk_walked_2 && (walk_ptr_2 == 4'b0101));
  assign _zz_judge_dupBad_7 = {2'd0, _zz_judge_dupBad_8};
  assign _zz_judge_dupBad_10 = (walk_walked_3 && (walk_ptr_3 == 4'b0101));
  assign _zz_judge_dupBad_9 = {2'd0, _zz_judge_dupBad_10};
  assign _zz_judge_dupBad_11 = (_zz_judge_dupBad_12 + _zz_judge_dupBad_20);
  assign _zz_judge_dupBad_12 = (_zz_judge_dupBad_13 + _zz_judge_dupBad_18);
  assign _zz_judge_dupBad_13 = (_zz_judge_dupBad_14 + _zz_judge_dupBad_16);
  assign _zz_judge_dupBad_15 = (walk_walked_0 && (walk_ptr_0 == 4'b0001));
  assign _zz_judge_dupBad_14 = {2'd0, _zz_judge_dupBad_15};
  assign _zz_judge_dupBad_17 = (walk_walked_1 && (walk_ptr_1 == 4'b0001));
  assign _zz_judge_dupBad_16 = {2'd0, _zz_judge_dupBad_17};
  assign _zz_judge_dupBad_19 = (walk_walked_2 && (walk_ptr_2 == 4'b0001));
  assign _zz_judge_dupBad_18 = {2'd0, _zz_judge_dupBad_19};
  assign _zz_judge_dupBad_21 = (walk_walked_3 && (walk_ptr_3 == 4'b0001));
  assign _zz_judge_dupBad_20 = {2'd0, _zz_judge_dupBad_21};
  assign _zz_judge_dupBad_22 = (_zz_judge_dupBad_23 + _zz_judge_dupBad_31);
  assign _zz_judge_dupBad_23 = (_zz_judge_dupBad_24 + _zz_judge_dupBad_29);
  assign _zz_judge_dupBad_24 = (_zz_judge_dupBad_25 + _zz_judge_dupBad_27);
  assign _zz_judge_dupBad_26 = (walk_walked_0 && (walk_ptr_0 == 4'b1001));
  assign _zz_judge_dupBad_25 = {2'd0, _zz_judge_dupBad_26};
  assign _zz_judge_dupBad_28 = (walk_walked_1 && (walk_ptr_1 == 4'b1001));
  assign _zz_judge_dupBad_27 = {2'd0, _zz_judge_dupBad_28};
  assign _zz_judge_dupBad_30 = (walk_walked_2 && (walk_ptr_2 == 4'b1001));
  assign _zz_judge_dupBad_29 = {2'd0, _zz_judge_dupBad_30};
  assign _zz_judge_dupBad_32 = (walk_walked_3 && (walk_ptr_3 == 4'b1001));
  assign _zz_judge_dupBad_31 = {2'd0, _zz_judge_dupBad_32};
  assign _zz_judge_dupBad_33 = (_zz_judge_dupBad_34 + _zz_judge_dupBad_42);
  assign _zz_judge_dupBad_34 = (_zz_judge_dupBad_35 + _zz_judge_dupBad_40);
  assign _zz_judge_dupBad_35 = (_zz_judge_dupBad_36 + _zz_judge_dupBad_38);
  assign _zz_judge_dupBad_37 = (walk_walked_0 && (walk_ptr_0 == 4'b0010));
  assign _zz_judge_dupBad_36 = {2'd0, _zz_judge_dupBad_37};
  assign _zz_judge_dupBad_39 = (walk_walked_1 && (walk_ptr_1 == 4'b0010));
  assign _zz_judge_dupBad_38 = {2'd0, _zz_judge_dupBad_39};
  assign _zz_judge_dupBad_41 = (walk_walked_2 && (walk_ptr_2 == 4'b0010));
  assign _zz_judge_dupBad_40 = {2'd0, _zz_judge_dupBad_41};
  assign _zz_judge_dupBad_43 = (walk_walked_3 && (walk_ptr_3 == 4'b0010));
  assign _zz_judge_dupBad_42 = {2'd0, _zz_judge_dupBad_43};
  assign _zz_judge_dupBad_44 = (_zz_judge_dupBad_45 + _zz_judge_dupBad_53);
  assign _zz_judge_dupBad_45 = (_zz_judge_dupBad_46 + _zz_judge_dupBad_51);
  assign _zz_judge_dupBad_46 = (_zz_judge_dupBad_47 + _zz_judge_dupBad_49);
  assign _zz_judge_dupBad_48 = (walk_walked_0 && (walk_ptr_0 == 4'b0111));
  assign _zz_judge_dupBad_47 = {2'd0, _zz_judge_dupBad_48};
  assign _zz_judge_dupBad_50 = (walk_walked_1 && (walk_ptr_1 == 4'b0111));
  assign _zz_judge_dupBad_49 = {2'd0, _zz_judge_dupBad_50};
  assign _zz_judge_dupBad_52 = (walk_walked_2 && (walk_ptr_2 == 4'b0111));
  assign _zz_judge_dupBad_51 = {2'd0, _zz_judge_dupBad_52};
  assign _zz_judge_dupBad_54 = (walk_walked_3 && (walk_ptr_3 == 4'b0111));
  assign _zz_judge_dupBad_53 = {2'd0, _zz_judge_dupBad_54};
  assign _zz_judge_dupBad_55 = (_zz_judge_dupBad_56 + _zz_judge_dupBad_64);
  assign _zz_judge_dupBad_56 = (_zz_judge_dupBad_57 + _zz_judge_dupBad_62);
  assign _zz_judge_dupBad_57 = (_zz_judge_dupBad_58 + _zz_judge_dupBad_60);
  assign _zz_judge_dupBad_59 = (walk_walked_0 && (walk_ptr_0 == 4'b0011));
  assign _zz_judge_dupBad_58 = {2'd0, _zz_judge_dupBad_59};
  assign _zz_judge_dupBad_61 = (walk_walked_1 && (walk_ptr_1 == 4'b0011));
  assign _zz_judge_dupBad_60 = {2'd0, _zz_judge_dupBad_61};
  assign _zz_judge_dupBad_63 = (walk_walked_2 && (walk_ptr_2 == 4'b0011));
  assign _zz_judge_dupBad_62 = {2'd0, _zz_judge_dupBad_63};
  assign _zz_judge_dupBad_65 = (walk_walked_3 && (walk_ptr_3 == 4'b0011));
  assign _zz_judge_dupBad_64 = {2'd0, _zz_judge_dupBad_65};
  assign _zz_judge_dupBad_66 = (_zz_judge_dupBad_67 + _zz_judge_dupBad_75);
  assign _zz_judge_dupBad_67 = (_zz_judge_dupBad_68 + _zz_judge_dupBad_73);
  assign _zz_judge_dupBad_68 = (_zz_judge_dupBad_69 + _zz_judge_dupBad_71);
  assign _zz_judge_dupBad_70 = (walk_walked_0 && (walk_ptr_0 == 4'b1000));
  assign _zz_judge_dupBad_69 = {2'd0, _zz_judge_dupBad_70};
  assign _zz_judge_dupBad_72 = (walk_walked_1 && (walk_ptr_1 == 4'b1000));
  assign _zz_judge_dupBad_71 = {2'd0, _zz_judge_dupBad_72};
  assign _zz_judge_dupBad_74 = (walk_walked_2 && (walk_ptr_2 == 4'b1000));
  assign _zz_judge_dupBad_73 = {2'd0, _zz_judge_dupBad_74};
  assign _zz_judge_dupBad_76 = (walk_walked_3 && (walk_ptr_3 == 4'b1000));
  assign _zz_judge_dupBad_75 = {2'd0, _zz_judge_dupBad_76};
  assign _zz_judge_dupBad_77 = (_zz_judge_dupBad_78 + _zz_judge_dupBad_86);
  assign _zz_judge_dupBad_78 = (_zz_judge_dupBad_79 + _zz_judge_dupBad_84);
  assign _zz_judge_dupBad_79 = (_zz_judge_dupBad_80 + _zz_judge_dupBad_82);
  assign _zz_judge_dupBad_81 = (walk_walked_0 && (walk_ptr_0 == 4'b0100));
  assign _zz_judge_dupBad_80 = {2'd0, _zz_judge_dupBad_81};
  assign _zz_judge_dupBad_83 = (walk_walked_1 && (walk_ptr_1 == 4'b0100));
  assign _zz_judge_dupBad_82 = {2'd0, _zz_judge_dupBad_83};
  assign _zz_judge_dupBad_85 = (walk_walked_2 && (walk_ptr_2 == 4'b0100));
  assign _zz_judge_dupBad_84 = {2'd0, _zz_judge_dupBad_85};
  assign _zz_judge_dupBad_87 = (walk_walked_3 && (walk_ptr_3 == 4'b0100));
  assign _zz_judge_dupBad_86 = {2'd0, _zz_judge_dupBad_87};
  assign _zz_walk_defd_0_1 = walk_ptr_0;
  assign _zz_walk_stepW_0_1 = walk_ptr_0;
  assign _zz_walk_defd_1_1 = walk_ptr_1;
  assign _zz_walk_stepW_1_1 = walk_ptr_1;
  assign _zz_walk_defd_2_1 = walk_ptr_2;
  assign _zz_walk_stepW_2_1 = walk_ptr_2;
  assign _zz_walk_defd_3_1 = walk_ptr_3;
  assign _zz_walk_stepW_3_1 = walk_ptr_3;
  always @(*) begin
    case(_zz_walk_head_0_1)
      4'b0000 : _zz_walk_head_0 = walk_lo16_0;
      4'b0001 : _zz_walk_head_0 = walk_lo16_1;
      4'b0010 : _zz_walk_head_0 = walk_lo16_2;
      4'b0011 : _zz_walk_head_0 = walk_lo16_3;
      4'b0100 : _zz_walk_head_0 = walk_lo16_4;
      4'b0101 : _zz_walk_head_0 = walk_lo16_5;
      4'b0110 : _zz_walk_head_0 = walk_lo16_6;
      4'b0111 : _zz_walk_head_0 = walk_lo16_7;
      4'b1000 : _zz_walk_head_0 = walk_lo16_8;
      4'b1001 : _zz_walk_head_0 = walk_lo16_9;
      4'b1010 : _zz_walk_head_0 = walk_lo16_10;
      4'b1011 : _zz_walk_head_0 = walk_lo16_11;
      default : _zz_walk_head_0 = walk_lo16_12;
    endcase
  end

  always @(*) begin
    case(_zz_walk_defd_0_1)
      4'b0000 : _zz_walk_defd_0 = kindDefined_0;
      4'b0001 : _zz_walk_defd_0 = kindDefined_1;
      4'b0010 : _zz_walk_defd_0 = kindDefined_2;
      4'b0011 : _zz_walk_defd_0 = kindDefined_3;
      4'b0100 : _zz_walk_defd_0 = kindDefined_4;
      4'b0101 : _zz_walk_defd_0 = kindDefined_5;
      4'b0110 : _zz_walk_defd_0 = kindDefined_6;
      4'b0111 : _zz_walk_defd_0 = kindDefined_7;
      4'b1000 : _zz_walk_defd_0 = kindDefined_8;
      4'b1001 : _zz_walk_defd_0 = kindDefined_9;
      4'b1010 : _zz_walk_defd_0 = kindDefined_10;
      4'b1011 : _zz_walk_defd_0 = kindDefined_11;
      4'b1100 : _zz_walk_defd_0 = kindDefined_12;
      4'b1101 : _zz_walk_defd_0 = kindDefined_13;
      4'b1110 : _zz_walk_defd_0 = kindDefined_14;
      default : _zz_walk_defd_0 = kindDefined_15;
    endcase
  end

  always @(*) begin
    case(_zz_walk_stepW_0_1)
      4'b0000 : _zz_walk_stepW_0 = kindWords_0;
      4'b0001 : _zz_walk_stepW_0 = kindWords_1;
      4'b0010 : _zz_walk_stepW_0 = kindWords_2;
      4'b0011 : _zz_walk_stepW_0 = kindWords_3;
      4'b0100 : _zz_walk_stepW_0 = kindWords_4;
      4'b0101 : _zz_walk_stepW_0 = kindWords_5;
      4'b0110 : _zz_walk_stepW_0 = kindWords_6;
      4'b0111 : _zz_walk_stepW_0 = kindWords_7;
      4'b1000 : _zz_walk_stepW_0 = kindWords_8;
      4'b1001 : _zz_walk_stepW_0 = kindWords_9;
      4'b1010 : _zz_walk_stepW_0 = kindWords_10;
      4'b1011 : _zz_walk_stepW_0 = kindWords_11;
      4'b1100 : _zz_walk_stepW_0 = kindWords_12;
      4'b1101 : _zz_walk_stepW_0 = kindWords_13;
      4'b1110 : _zz_walk_stepW_0 = kindWords_14;
      default : _zz_walk_stepW_0 = kindWords_15;
    endcase
  end

  always @(*) begin
    case(_zz_walk_head_1_1)
      4'b0000 : _zz_walk_head_1 = walk_lo16_0;
      4'b0001 : _zz_walk_head_1 = walk_lo16_1;
      4'b0010 : _zz_walk_head_1 = walk_lo16_2;
      4'b0011 : _zz_walk_head_1 = walk_lo16_3;
      4'b0100 : _zz_walk_head_1 = walk_lo16_4;
      4'b0101 : _zz_walk_head_1 = walk_lo16_5;
      4'b0110 : _zz_walk_head_1 = walk_lo16_6;
      4'b0111 : _zz_walk_head_1 = walk_lo16_7;
      4'b1000 : _zz_walk_head_1 = walk_lo16_8;
      4'b1001 : _zz_walk_head_1 = walk_lo16_9;
      4'b1010 : _zz_walk_head_1 = walk_lo16_10;
      4'b1011 : _zz_walk_head_1 = walk_lo16_11;
      default : _zz_walk_head_1 = walk_lo16_12;
    endcase
  end

  always @(*) begin
    case(_zz_walk_defd_1_1)
      4'b0000 : _zz_walk_defd_1 = kindDefined_0;
      4'b0001 : _zz_walk_defd_1 = kindDefined_1;
      4'b0010 : _zz_walk_defd_1 = kindDefined_2;
      4'b0011 : _zz_walk_defd_1 = kindDefined_3;
      4'b0100 : _zz_walk_defd_1 = kindDefined_4;
      4'b0101 : _zz_walk_defd_1 = kindDefined_5;
      4'b0110 : _zz_walk_defd_1 = kindDefined_6;
      4'b0111 : _zz_walk_defd_1 = kindDefined_7;
      4'b1000 : _zz_walk_defd_1 = kindDefined_8;
      4'b1001 : _zz_walk_defd_1 = kindDefined_9;
      4'b1010 : _zz_walk_defd_1 = kindDefined_10;
      4'b1011 : _zz_walk_defd_1 = kindDefined_11;
      4'b1100 : _zz_walk_defd_1 = kindDefined_12;
      4'b1101 : _zz_walk_defd_1 = kindDefined_13;
      4'b1110 : _zz_walk_defd_1 = kindDefined_14;
      default : _zz_walk_defd_1 = kindDefined_15;
    endcase
  end

  always @(*) begin
    case(_zz_walk_stepW_1_1)
      4'b0000 : _zz_walk_stepW_1 = kindWords_0;
      4'b0001 : _zz_walk_stepW_1 = kindWords_1;
      4'b0010 : _zz_walk_stepW_1 = kindWords_2;
      4'b0011 : _zz_walk_stepW_1 = kindWords_3;
      4'b0100 : _zz_walk_stepW_1 = kindWords_4;
      4'b0101 : _zz_walk_stepW_1 = kindWords_5;
      4'b0110 : _zz_walk_stepW_1 = kindWords_6;
      4'b0111 : _zz_walk_stepW_1 = kindWords_7;
      4'b1000 : _zz_walk_stepW_1 = kindWords_8;
      4'b1001 : _zz_walk_stepW_1 = kindWords_9;
      4'b1010 : _zz_walk_stepW_1 = kindWords_10;
      4'b1011 : _zz_walk_stepW_1 = kindWords_11;
      4'b1100 : _zz_walk_stepW_1 = kindWords_12;
      4'b1101 : _zz_walk_stepW_1 = kindWords_13;
      4'b1110 : _zz_walk_stepW_1 = kindWords_14;
      default : _zz_walk_stepW_1 = kindWords_15;
    endcase
  end

  always @(*) begin
    case(_zz_walk_head_2_1)
      4'b0000 : _zz_walk_head_2 = walk_lo16_0;
      4'b0001 : _zz_walk_head_2 = walk_lo16_1;
      4'b0010 : _zz_walk_head_2 = walk_lo16_2;
      4'b0011 : _zz_walk_head_2 = walk_lo16_3;
      4'b0100 : _zz_walk_head_2 = walk_lo16_4;
      4'b0101 : _zz_walk_head_2 = walk_lo16_5;
      4'b0110 : _zz_walk_head_2 = walk_lo16_6;
      4'b0111 : _zz_walk_head_2 = walk_lo16_7;
      4'b1000 : _zz_walk_head_2 = walk_lo16_8;
      4'b1001 : _zz_walk_head_2 = walk_lo16_9;
      4'b1010 : _zz_walk_head_2 = walk_lo16_10;
      4'b1011 : _zz_walk_head_2 = walk_lo16_11;
      default : _zz_walk_head_2 = walk_lo16_12;
    endcase
  end

  always @(*) begin
    case(_zz_walk_defd_2_1)
      4'b0000 : _zz_walk_defd_2 = kindDefined_0;
      4'b0001 : _zz_walk_defd_2 = kindDefined_1;
      4'b0010 : _zz_walk_defd_2 = kindDefined_2;
      4'b0011 : _zz_walk_defd_2 = kindDefined_3;
      4'b0100 : _zz_walk_defd_2 = kindDefined_4;
      4'b0101 : _zz_walk_defd_2 = kindDefined_5;
      4'b0110 : _zz_walk_defd_2 = kindDefined_6;
      4'b0111 : _zz_walk_defd_2 = kindDefined_7;
      4'b1000 : _zz_walk_defd_2 = kindDefined_8;
      4'b1001 : _zz_walk_defd_2 = kindDefined_9;
      4'b1010 : _zz_walk_defd_2 = kindDefined_10;
      4'b1011 : _zz_walk_defd_2 = kindDefined_11;
      4'b1100 : _zz_walk_defd_2 = kindDefined_12;
      4'b1101 : _zz_walk_defd_2 = kindDefined_13;
      4'b1110 : _zz_walk_defd_2 = kindDefined_14;
      default : _zz_walk_defd_2 = kindDefined_15;
    endcase
  end

  always @(*) begin
    case(_zz_walk_stepW_2_1)
      4'b0000 : _zz_walk_stepW_2 = kindWords_0;
      4'b0001 : _zz_walk_stepW_2 = kindWords_1;
      4'b0010 : _zz_walk_stepW_2 = kindWords_2;
      4'b0011 : _zz_walk_stepW_2 = kindWords_3;
      4'b0100 : _zz_walk_stepW_2 = kindWords_4;
      4'b0101 : _zz_walk_stepW_2 = kindWords_5;
      4'b0110 : _zz_walk_stepW_2 = kindWords_6;
      4'b0111 : _zz_walk_stepW_2 = kindWords_7;
      4'b1000 : _zz_walk_stepW_2 = kindWords_8;
      4'b1001 : _zz_walk_stepW_2 = kindWords_9;
      4'b1010 : _zz_walk_stepW_2 = kindWords_10;
      4'b1011 : _zz_walk_stepW_2 = kindWords_11;
      4'b1100 : _zz_walk_stepW_2 = kindWords_12;
      4'b1101 : _zz_walk_stepW_2 = kindWords_13;
      4'b1110 : _zz_walk_stepW_2 = kindWords_14;
      default : _zz_walk_stepW_2 = kindWords_15;
    endcase
  end

  always @(*) begin
    case(_zz_walk_head_3_1)
      4'b0000 : _zz_walk_head_3 = walk_lo16_0;
      4'b0001 : _zz_walk_head_3 = walk_lo16_1;
      4'b0010 : _zz_walk_head_3 = walk_lo16_2;
      4'b0011 : _zz_walk_head_3 = walk_lo16_3;
      4'b0100 : _zz_walk_head_3 = walk_lo16_4;
      4'b0101 : _zz_walk_head_3 = walk_lo16_5;
      4'b0110 : _zz_walk_head_3 = walk_lo16_6;
      4'b0111 : _zz_walk_head_3 = walk_lo16_7;
      4'b1000 : _zz_walk_head_3 = walk_lo16_8;
      4'b1001 : _zz_walk_head_3 = walk_lo16_9;
      4'b1010 : _zz_walk_head_3 = walk_lo16_10;
      4'b1011 : _zz_walk_head_3 = walk_lo16_11;
      default : _zz_walk_head_3 = walk_lo16_12;
    endcase
  end

  always @(*) begin
    case(_zz_walk_defd_3_1)
      4'b0000 : _zz_walk_defd_3 = kindDefined_0;
      4'b0001 : _zz_walk_defd_3 = kindDefined_1;
      4'b0010 : _zz_walk_defd_3 = kindDefined_2;
      4'b0011 : _zz_walk_defd_3 = kindDefined_3;
      4'b0100 : _zz_walk_defd_3 = kindDefined_4;
      4'b0101 : _zz_walk_defd_3 = kindDefined_5;
      4'b0110 : _zz_walk_defd_3 = kindDefined_6;
      4'b0111 : _zz_walk_defd_3 = kindDefined_7;
      4'b1000 : _zz_walk_defd_3 = kindDefined_8;
      4'b1001 : _zz_walk_defd_3 = kindDefined_9;
      4'b1010 : _zz_walk_defd_3 = kindDefined_10;
      4'b1011 : _zz_walk_defd_3 = kindDefined_11;
      4'b1100 : _zz_walk_defd_3 = kindDefined_12;
      4'b1101 : _zz_walk_defd_3 = kindDefined_13;
      4'b1110 : _zz_walk_defd_3 = kindDefined_14;
      default : _zz_walk_defd_3 = kindDefined_15;
    endcase
  end

  always @(*) begin
    case(_zz_walk_stepW_3_1)
      4'b0000 : _zz_walk_stepW_3 = kindWords_0;
      4'b0001 : _zz_walk_stepW_3 = kindWords_1;
      4'b0010 : _zz_walk_stepW_3 = kindWords_2;
      4'b0011 : _zz_walk_stepW_3 = kindWords_3;
      4'b0100 : _zz_walk_stepW_3 = kindWords_4;
      4'b0101 : _zz_walk_stepW_3 = kindWords_5;
      4'b0110 : _zz_walk_stepW_3 = kindWords_6;
      4'b0111 : _zz_walk_stepW_3 = kindWords_7;
      4'b1000 : _zz_walk_stepW_3 = kindWords_8;
      4'b1001 : _zz_walk_stepW_3 = kindWords_9;
      4'b1010 : _zz_walk_stepW_3 = kindWords_10;
      4'b1011 : _zz_walk_stepW_3 = kindWords_11;
      4'b1100 : _zz_walk_stepW_3 = kindWords_12;
      4'b1101 : _zz_walk_stepW_3 = kindWords_13;
      4'b1110 : _zz_walk_stepW_3 = kindWords_14;
      default : _zz_walk_stepW_3 = kindWords_15;
    endcase
  end

  assign kindDefined_0 = 1'b0;
  assign kindDefined_1 = 1'b1;
  assign kindDefined_2 = 1'b1;
  assign kindDefined_3 = 1'b1;
  assign kindDefined_4 = 1'b1;
  assign kindDefined_5 = 1'b1;
  assign kindDefined_6 = 1'b1;
  assign kindDefined_7 = 1'b1;
  assign kindDefined_8 = 1'b1;
  assign kindDefined_9 = 1'b1;
  assign kindDefined_10 = 1'b0;
  assign kindDefined_11 = 1'b0;
  assign kindDefined_12 = 1'b0;
  assign kindDefined_13 = 1'b0;
  assign kindDefined_14 = 1'b0;
  assign kindDefined_15 = 1'b1;
  assign kindWords_0 = 8'h01;
  assign kindWords_1 = 8'h01;
  assign kindWords_2 = 8'h01;
  assign kindWords_3 = 8'h02;
  assign kindWords_4 = 8'h03;
  assign kindWords_5 = 8'h02;
  assign kindWords_6 = 8'h02;
  assign kindWords_7 = 8'h01;
  assign kindWords_8 = 8'h01;
  assign kindWords_9 = 8'h01;
  assign kindWords_10 = 8'h01;
  assign kindWords_11 = 8'h01;
  assign kindWords_12 = 8'h01;
  assign kindWords_13 = 8'h01;
  assign kindWords_14 = 8'h01;
  assign kindWords_15 = 8'h01;
  assign walk_lo16_0 = io_iInstr_0[15 : 0];
  assign walk_lo16_1 = io_iInstr_1[15 : 0];
  assign walk_lo16_2 = io_iInstr_2[15 : 0];
  assign walk_lo16_3 = io_iInstr_3[15 : 0];
  assign walk_lo16_4 = io_iInstr_4[15 : 0];
  assign walk_lo16_5 = io_iInstr_5[15 : 0];
  assign walk_lo16_6 = io_iInstr_6[15 : 0];
  assign walk_lo16_7 = io_iInstr_7[15 : 0];
  assign walk_lo16_8 = io_iInstr_8[15 : 0];
  assign walk_lo16_9 = io_iInstr_9[15 : 0];
  assign walk_lo16_10 = io_iInstr_10[15 : 0];
  assign walk_lo16_11 = io_iInstr_11[15 : 0];
  assign walk_lo16_12 = io_iInstr_12[15 : 0];
  assign walk_ptr_0 = io_iInstr_0[23 : 20];
  assign walk_ended_0 = (walk_ptr_0 == 4'b0000);
  assign walk_off_0 = 8'h01;
  assign walk_walked_0 = (! walk_ended_0);
  assign walk_head_0 = _zz_walk_head_0;
  assign walk_selfCode_0 = walk_head_0[11 : 8];
  assign walk_wordsFld_0 = walk_head_0[7 : 0];
  assign walk_defd_0 = _zz_walk_defd_0;
  assign walk_stepW_0 = _zz_walk_stepW_0;
  assign walk_ptr_1 = walk_head_0[15 : 12];
  assign walk_ended_1 = (walk_ended_0 || (walk_ptr_1 == 4'b0000));
  assign walk_off_1 = (walk_off_0 + (walk_walked_0 ? walk_stepW_0 : 8'h0));
  assign walk_walked_1 = (! walk_ended_1);
  assign walk_head_1 = _zz_walk_head_1;
  assign walk_selfCode_1 = walk_head_1[11 : 8];
  assign walk_wordsFld_1 = walk_head_1[7 : 0];
  assign walk_defd_1 = _zz_walk_defd_1;
  assign walk_stepW_1 = _zz_walk_stepW_1;
  assign walk_ptr_2 = walk_head_1[15 : 12];
  assign walk_ended_2 = (walk_ended_1 || (walk_ptr_2 == 4'b0000));
  assign walk_off_2 = (walk_off_1 + (walk_walked_1 ? walk_stepW_1 : 8'h0));
  assign walk_walked_2 = (! walk_ended_2);
  assign walk_head_2 = _zz_walk_head_2;
  assign walk_selfCode_2 = walk_head_2[11 : 8];
  assign walk_wordsFld_2 = walk_head_2[7 : 0];
  assign walk_defd_2 = _zz_walk_defd_2;
  assign walk_stepW_2 = _zz_walk_stepW_2;
  assign walk_ptr_3 = walk_head_2[15 : 12];
  assign walk_ended_3 = (walk_ended_2 || (walk_ptr_3 == 4'b0000));
  assign walk_off_3 = (walk_off_2 + (walk_walked_2 ? walk_stepW_2 : 8'h0));
  assign walk_walked_3 = (! walk_ended_3);
  assign walk_head_3 = _zz_walk_head_3;
  assign walk_selfCode_3 = walk_head_3[11 : 8];
  assign walk_wordsFld_3 = walk_head_3[7 : 0];
  assign walk_defd_3 = _zz_walk_defd_3;
  assign walk_stepW_3 = _zz_walk_stepW_3;
  assign walk_ptr_4 = walk_head_3[15 : 12];
  assign walk_ended_4 = (walk_ended_3 || (walk_ptr_4 == 4'b0000));
  assign walk_off_4 = (walk_off_3 + (walk_walked_3 ? walk_stepW_3 : 8'h0));
  assign judge_declLen = io_iInstr_0[7 : 0];
  assign judge_resvFld = io_iInstr_0[15 : 8];
  assign judge_capAbsent = (8'h0d < judge_declLen);
  assign judge_lenBad = (walk_ended_4 && (judge_declLen != walk_off_4));
  assign judge_capBad = ((! judge_capAbsent) && (! walk_ended_4));
  assign judge_junkBad = ((((walk_walked_0 && (! walk_defd_0)) || (walk_walked_1 && (! walk_defd_1))) || (walk_walked_2 && (! walk_defd_2))) || (walk_walked_3 && (! walk_defd_3)));
  assign judge_selfBad = ((((walk_walked_0 && (walk_selfCode_0 != walk_ptr_0)) || (walk_walked_1 && (walk_selfCode_1 != walk_ptr_1))) || (walk_walked_2 && (walk_selfCode_2 != walk_ptr_2))) || (walk_walked_3 && (walk_selfCode_3 != walk_ptr_3)));
  assign judge_wordsBad = (((((walk_walked_0 && walk_defd_0) && (walk_wordsFld_0 != walk_stepW_0)) || ((walk_walked_1 && walk_defd_1) && (walk_wordsFld_1 != walk_stepW_1))) || ((walk_walked_2 && walk_defd_2) && (walk_wordsFld_2 != walk_stepW_2))) || ((walk_walked_3 && walk_defd_3) && (walk_wordsFld_3 != walk_stepW_3)));
  assign judge_dupBad = ((((((((3'b001 < _zz_judge_dupBad) || (3'b001 < _zz_judge_dupBad_11)) || (3'b001 < _zz_judge_dupBad_22)) || (3'b001 < _zz_judge_dupBad_33)) || (3'b010 < _zz_judge_dupBad_44)) || (3'b001 < _zz_judge_dupBad_55)) || (3'b001 < _zz_judge_dupBad_66)) || (3'b001 < _zz_judge_dupBad_77));
  assign judge_resvBad = (judge_resvFld != 8'h0);
  assign judge_mal = ((! judge_capAbsent) && ((((((judge_resvBad || judge_capBad) || judge_lenBad) || judge_junkBad) || judge_selfBad) || judge_wordsBad) || judge_dupBad));
  always @(*) begin
    outStage_masked_0 = io_iInstr_0;
    outStage_masked_0[15 : 8] = 8'h0;
  end

  assign outStage_masked_1 = io_iInstr_1;
  assign outStage_masked_2 = io_iInstr_2;
  assign outStage_masked_3 = io_iInstr_3;
  assign outStage_masked_4 = io_iInstr_4;
  assign outStage_masked_5 = io_iInstr_5;
  assign outStage_masked_6 = io_iInstr_6;
  assign outStage_masked_7 = io_iInstr_7;
  assign outStage_masked_8 = io_iInstr_8;
  assign outStage_masked_9 = io_iInstr_9;
  assign outStage_masked_10 = io_iInstr_10;
  assign outStage_masked_11 = io_iInstr_11;
  assign outStage_masked_12 = io_iInstr_12;
  assign io_oValid = outStage_rValid;
  assign io_oMalformed = outStage_rMal;
  assign io_oCapAbsent = outStage_rCapa;
  assign io_oExecValid = ((outStage_rValid && (! outStage_rMal)) && (! outStage_rCapa));
  assign io_oInstr_0 = outStage_rInstr_0;
  assign io_oInstr_1 = outStage_rInstr_1;
  assign io_oInstr_2 = outStage_rInstr_2;
  assign io_oInstr_3 = outStage_rInstr_3;
  assign io_oInstr_4 = outStage_rInstr_4;
  assign io_oInstr_5 = outStage_rInstr_5;
  assign io_oInstr_6 = outStage_rInstr_6;
  assign io_oInstr_7 = outStage_rInstr_7;
  assign io_oInstr_8 = outStage_rInstr_8;
  assign io_oInstr_9 = outStage_rInstr_9;
  assign io_oInstr_10 = outStage_rInstr_10;
  assign io_oInstr_11 = outStage_rInstr_11;
  assign io_oInstr_12 = outStage_rInstr_12;
  assign io_oSlotPresent_0 = outStage_rPresent_0;
  assign io_oSlotPresent_1 = outStage_rPresent_1;
  assign io_oSlotPresent_2 = outStage_rPresent_2;
  assign io_oSlotPresent_3 = outStage_rPresent_3;
  assign io_oSlotCode_0 = outStage_rCode_0;
  assign io_oSlotCode_1 = outStage_rCode_1;
  assign io_oSlotCode_2 = outStage_rCode_2;
  assign io_oSlotCode_3 = outStage_rCode_3;
  assign io_oSlotOff_0 = outStage_rOff_0;
  assign io_oSlotOff_1 = outStage_rOff_1;
  assign io_oSlotOff_2 = outStage_rOff_2;
  assign io_oSlotOff_3 = outStage_rOff_3;
  assign when_Common_l259 = (outStage_rValid && outStage_rMal);
  assign io_oFault = _zz_io_oFault;
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      outStage_rValid <= 1'b0;
      outStage_rMal <= 1'b0;
      outStage_rCapa <= 1'b0;
      _zz_io_oFault <= 1'b0;
    end else begin
      outStage_rValid <= io_iValid;
      outStage_rMal <= judge_mal;
      outStage_rCapa <= judge_capAbsent;
      if(io_iFaultClear) begin
        _zz_io_oFault <= 1'b0;
      end
      if(when_Common_l259) begin
        _zz_io_oFault <= 1'b1;
      end
    end
  end

  always @(posedge clk) begin
    outStage_rInstr_0 <= outStage_masked_0;
    outStage_rInstr_1 <= outStage_masked_1;
    outStage_rInstr_2 <= outStage_masked_2;
    outStage_rInstr_3 <= outStage_masked_3;
    outStage_rInstr_4 <= outStage_masked_4;
    outStage_rInstr_5 <= outStage_masked_5;
    outStage_rInstr_6 <= outStage_masked_6;
    outStage_rInstr_7 <= outStage_masked_7;
    outStage_rInstr_8 <= outStage_masked_8;
    outStage_rInstr_9 <= outStage_masked_9;
    outStage_rInstr_10 <= outStage_masked_10;
    outStage_rInstr_11 <= outStage_masked_11;
    outStage_rInstr_12 <= outStage_masked_12;
    outStage_rPresent_0 <= walk_walked_0;
    outStage_rPresent_1 <= walk_walked_1;
    outStage_rPresent_2 <= walk_walked_2;
    outStage_rPresent_3 <= walk_walked_3;
    outStage_rCode_0 <= (walk_walked_0 ? walk_ptr_0 : 4'b0000);
    outStage_rCode_1 <= (walk_walked_1 ? walk_ptr_1 : 4'b0000);
    outStage_rCode_2 <= (walk_walked_2 ? walk_ptr_2 : 4'b0000);
    outStage_rCode_3 <= (walk_walked_3 ? walk_ptr_3 : 4'b0000);
    outStage_rOff_0 <= (walk_walked_0 ? walk_off_0 : 8'h0);
    outStage_rOff_1 <= (walk_walked_1 ? walk_off_1 : 8'h0);
    outStage_rOff_2 <= (walk_walked_2 ? walk_off_2 : 8'h0);
    outStage_rOff_3 <= (walk_walked_3 ? walk_off_3 : 8'h0);
  end


endmodule
