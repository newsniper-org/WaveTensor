// Generator : SpinalHDL v1.14.2    git head : 78f29dc66110fc099a777992b6daa2f803ab445e
// Component : MaskUnit
// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
// 
// === 생성물이다. 손으로 고치지 말 것. ===
// 고칠 곳은 rtl/spinal/ 의 생성기이고, 고친 뒤 `make rtl-gen` 으로 다시 낸다.
// 여기 직접 쓴 수정은 다음 생성에서 조용히 사라진다.

`timescale 1ns/1ps

module MaskUnit (
  input  wire          io_keyWr_valid,
  input  wire [1:0]    io_keyWr_part,
  input  wire [2:0]    io_keyWr_idx,
  input  wire [31:0]   io_keyWr_data,
  input  wire          io_nonceWr_valid,
  input  wire [1:0]    io_nonceWr_part,
  input  wire [2:0]    io_nonceWr_idx,
  input  wire [31:0]   io_nonceWr_data,
  input  wire          io_rekey_valid,
  output wire          io_rekey_ready,
  input  wire [1:0]    io_rekey_part,
  output wire [3:0]    io_maskReady,
  output wire          io_busy,
  input  wire          io_en,
  input  wire          io_req_valid,
  input  wire [1:0]    io_req_part,
  input  wire [31:0]   io_req_frame,
  output wire          io_rsp_valid,
  output wire [31:0]   io_rsp_frame,
  output wire          io_faultNoMask,
  output wire          io_faultNonceDup,
  output wire          io_faultWrDuringRekey,
  input  wire          io_faultClearNoMask,
  input  wire          io_faultClearNonceDup,
  input  wire          io_faultClearWrRekey,
  input  wire          clk,
  input  wire          reset
);

  reg        [191:0]  _zz_reqNonce;
  wire                _zz_nonceDup;
  wire                _zz_nonceDup_1;
  wire       [1:0]    _zz_nonceDup_2;
  reg        [31:0]   _zz_st_4;
  reg        [31:0]   _zz_st_5;
  reg        [31:0]   _zz_st_6;
  reg        [31:0]   _zz_st_7;
  reg        [31:0]   _zz_st_8;
  reg        [31:0]   _zz_st_9;
  reg        [31:0]   _zz_st_10;
  reg        [31:0]   _zz_st_11;
  reg        [31:0]   _zz_st_12;
  reg        [31:0]   _zz_st_13;
  reg        [31:0]   _zz_st_14;
  reg        [31:0]   _zz_st_15;
  reg        [31:0]   _zz_st_14_1;
  reg        [31:0]   _zz_st_15_1;
  wire       [11:0]   _zz__zz_maskFrame_0;
  wire       [19:0]   _zz__zz_maskFrame_0_1;
  wire       [19:0]   _zz__zz_maskFrame_0_2;
  wire       [19:0]   _zz__zz_maskFrame_0_3;
  wire       [0:0]    _zz__zz_maskFrame_0_4;
  reg        [31:0]   _zz_rFrame;
  reg                 _zz_noMaskFire;
  reg        [31:0]   key_0_0;
  reg        [31:0]   key_0_1;
  reg        [31:0]   key_0_2;
  reg        [31:0]   key_0_3;
  reg        [31:0]   key_0_4;
  reg        [31:0]   key_0_5;
  reg        [31:0]   key_0_6;
  reg        [31:0]   key_0_7;
  reg        [31:0]   key_1_0;
  reg        [31:0]   key_1_1;
  reg        [31:0]   key_1_2;
  reg        [31:0]   key_1_3;
  reg        [31:0]   key_1_4;
  reg        [31:0]   key_1_5;
  reg        [31:0]   key_1_6;
  reg        [31:0]   key_1_7;
  reg        [31:0]   key_2_0;
  reg        [31:0]   key_2_1;
  reg        [31:0]   key_2_2;
  reg        [31:0]   key_2_3;
  reg        [31:0]   key_2_4;
  reg        [31:0]   key_2_5;
  reg        [31:0]   key_2_6;
  reg        [31:0]   key_2_7;
  reg        [31:0]   key_3_0;
  reg        [31:0]   key_3_1;
  reg        [31:0]   key_3_2;
  reg        [31:0]   key_3_3;
  reg        [31:0]   key_3_4;
  reg        [31:0]   key_3_5;
  reg        [31:0]   key_3_6;
  reg        [31:0]   key_3_7;
  reg        [31:0]   nonce_0_0;
  reg        [31:0]   nonce_0_1;
  reg        [31:0]   nonce_0_2;
  reg        [31:0]   nonce_0_3;
  reg        [31:0]   nonce_0_4;
  reg        [31:0]   nonce_0_5;
  reg        [31:0]   nonce_1_0;
  reg        [31:0]   nonce_1_1;
  reg        [31:0]   nonce_1_2;
  reg        [31:0]   nonce_1_3;
  reg        [31:0]   nonce_1_4;
  reg        [31:0]   nonce_1_5;
  reg        [31:0]   nonce_2_0;
  reg        [31:0]   nonce_2_1;
  reg        [31:0]   nonce_2_2;
  reg        [31:0]   nonce_2_3;
  reg        [31:0]   nonce_2_4;
  reg        [31:0]   nonce_2_5;
  reg        [31:0]   nonce_3_0;
  reg        [31:0]   nonce_3_1;
  reg        [31:0]   nonce_3_2;
  reg        [31:0]   nonce_3_3;
  reg        [31:0]   nonce_3_4;
  reg        [31:0]   nonce_3_5;
  reg        [31:0]   maskFrame_0;
  reg        [31:0]   maskFrame_1;
  reg        [31:0]   maskFrame_2;
  reg        [31:0]   maskFrame_3;
  reg                 maskValid_0;
  reg                 maskValid_1;
  reg                 maskValid_2;
  reg                 maskValid_3;
  reg        [2:0]    phase;
  reg        [31:0]   st_0;
  reg        [31:0]   st_1;
  reg        [31:0]   st_2;
  reg        [31:0]   st_3;
  reg        [31:0]   st_4;
  reg        [31:0]   st_5;
  reg        [31:0]   st_6;
  reg        [31:0]   st_7;
  reg        [31:0]   st_8;
  reg        [31:0]   st_9;
  reg        [31:0]   st_10;
  reg        [31:0]   st_11;
  reg        [31:0]   st_12;
  reg        [31:0]   st_13;
  reg        [31:0]   st_14;
  reg        [31:0]   st_15;
  reg        [4:0]    cnt;
  reg        [1:0]    actPart;
  reg                 compDirty;
  wire                engineBusy;
  wire                rekeyFire;
  wire                _zz_roundNext_0;
  wire       [31:0]   _zz_roundNext_0_1;
  wire       [31:0]   _zz_roundNext_10;
  wire       [31:0]   _zz_roundNext_10_1;
  wire       [31:0]   _zz_roundNext_10_2;
  wire       [31:0]   _zz_roundNext_0_2;
  wire       [31:0]   _zz_roundNext_0_3;
  wire       [31:0]   _zz_roundNext_0_4;
  wire       [31:0]   _zz_roundNext_15;
  wire       [31:0]   _zz_roundNext_15_1;
  wire       [31:0]   _zz_roundNext_10_3;
  wire       [31:0]   _zz_roundNext_5;
  wire       [31:0]   _zz_roundNext_1;
  wire       [31:0]   _zz_roundNext_11;
  wire       [31:0]   _zz_roundNext_11_1;
  wire       [31:0]   _zz_roundNext_11_2;
  wire       [31:0]   _zz_roundNext_1_1;
  wire       [31:0]   _zz_roundNext_1_2;
  wire       [31:0]   _zz_roundNext_1_3;
  wire       [31:0]   _zz_roundNext_12;
  wire       [31:0]   _zz_roundNext_12_1;
  wire       [31:0]   _zz_roundNext_11_3;
  wire       [31:0]   _zz_roundNext_6;
  wire       [31:0]   _zz_roundNext_2;
  wire       [31:0]   _zz_roundNext_8;
  wire       [31:0]   _zz_roundNext_8_1;
  wire       [31:0]   _zz_roundNext_8_2;
  wire       [31:0]   _zz_roundNext_2_1;
  wire       [31:0]   _zz_roundNext_2_2;
  wire       [31:0]   _zz_roundNext_2_3;
  wire       [31:0]   _zz_roundNext_13;
  wire       [31:0]   _zz_roundNext_13_1;
  wire       [31:0]   _zz_roundNext_8_3;
  wire       [31:0]   _zz_roundNext_7;
  wire       [31:0]   _zz_roundNext_3;
  wire       [31:0]   _zz_roundNext_9;
  wire       [31:0]   _zz_roundNext_9_1;
  wire       [31:0]   _zz_roundNext_9_2;
  wire       [31:0]   _zz_roundNext_3_1;
  wire       [31:0]   _zz_roundNext_3_2;
  wire       [31:0]   _zz_roundNext_3_3;
  wire       [31:0]   _zz_roundNext_14;
  wire       [31:0]   _zz_roundNext_14_1;
  wire       [31:0]   _zz_roundNext_9_3;
  wire       [31:0]   _zz_roundNext_4;
  wire       [31:0]   _zz_roundNext_0_5;
  wire       [31:0]   _zz_roundNext_8_4;
  wire       [31:0]   _zz_roundNext_8_5;
  wire       [31:0]   _zz_roundNext_8_6;
  wire       [31:0]   _zz_roundNext_0_6;
  wire       [31:0]   _zz_roundNext_0_7;
  wire       [31:0]   _zz_roundNext_0_8;
  wire       [31:0]   _zz_roundNext_12_2;
  wire       [31:0]   _zz_roundNext_12_3;
  wire       [31:0]   _zz_roundNext_8_7;
  wire       [31:0]   _zz_roundNext_4_1;
  wire       [31:0]   _zz_roundNext_1_4;
  wire       [31:0]   _zz_roundNext_9_4;
  wire       [31:0]   _zz_roundNext_9_5;
  wire       [31:0]   _zz_roundNext_9_6;
  wire       [31:0]   _zz_roundNext_1_5;
  wire       [31:0]   _zz_roundNext_1_6;
  wire       [31:0]   _zz_roundNext_1_7;
  wire       [31:0]   _zz_roundNext_13_2;
  wire       [31:0]   _zz_roundNext_13_3;
  wire       [31:0]   _zz_roundNext_9_7;
  wire       [31:0]   _zz_roundNext_5_1;
  wire       [31:0]   _zz_roundNext_2_4;
  wire       [31:0]   _zz_roundNext_10_4;
  wire       [31:0]   _zz_roundNext_10_5;
  wire       [31:0]   _zz_roundNext_10_6;
  wire       [31:0]   _zz_roundNext_2_5;
  wire       [31:0]   _zz_roundNext_2_6;
  wire       [31:0]   _zz_roundNext_2_7;
  wire       [31:0]   _zz_roundNext_14_2;
  wire       [31:0]   _zz_roundNext_14_3;
  wire       [31:0]   _zz_roundNext_10_7;
  wire       [31:0]   _zz_roundNext_6_1;
  wire       [31:0]   _zz_roundNext_3_4;
  wire       [31:0]   _zz_roundNext_11_4;
  wire       [31:0]   _zz_roundNext_11_5;
  wire       [31:0]   _zz_roundNext_11_6;
  wire       [31:0]   _zz_roundNext_3_5;
  wire       [31:0]   _zz_roundNext_3_6;
  wire       [31:0]   _zz_roundNext_3_7;
  wire       [31:0]   _zz_roundNext_15_2;
  wire       [31:0]   _zz_roundNext_15_3;
  wire       [31:0]   _zz_roundNext_11_7;
  wire       [31:0]   _zz_roundNext_7_1;
  wire       [31:0]   roundNext_0;
  wire       [31:0]   roundNext_1;
  wire       [31:0]   roundNext_2;
  wire       [31:0]   roundNext_3;
  wire       [31:0]   roundNext_4;
  wire       [31:0]   roundNext_5;
  wire       [31:0]   roundNext_6;
  wire       [31:0]   roundNext_7;
  wire       [31:0]   roundNext_8;
  wire       [31:0]   roundNext_9;
  wire       [31:0]   roundNext_10;
  wire       [31:0]   roundNext_11;
  wire       [31:0]   roundNext_12;
  wire       [31:0]   roundNext_13;
  wire       [31:0]   roundNext_14;
  wire       [31:0]   roundNext_15;
  wire       [191:0]  nonceFlat_0;
  wire       [191:0]  nonceFlat_1;
  wire       [191:0]  nonceFlat_2;
  wire       [191:0]  nonceFlat_3;
  wire       [191:0]  reqNonce;
  wire                nonceDup;
  wire                nonceDupFire;
  wire                nonceWrHit;
  wire                wrActNow;
  reg                 dirtyAtFinal;
  wire       [3:0]    _zz_1;
  wire                when_MaskUnit_l406;
  wire                when_MaskUnit_l439;
  wire       [3:0]    _zz_2;
  wire       [31:0]   _zz_maskFrame_0;
  wire                _zz_dirtyAtFinal;
  wire       [3:0]    _zz_3;
  wire                _zz_maskValid_0;
  wire       [3:0]    _zz_4;
  wire                _zz_5;
  wire                _zz_6;
  wire                _zz_7;
  wire                _zz_8;
  wire       [7:0]    _zz_9;
  wire       [3:0]    _zz_10;
  wire                when_MaskUnit_l502;
  wire                when_MaskUnit_l510;
  wire       [3:0]    _zz_11;
  wire                _zz_12;
  wire                _zz_13;
  wire                _zz_14;
  wire                _zz_15;
  wire                when_MaskUnit_l510_1;
  wire                when_MaskUnit_l510_2;
  wire                when_MaskUnit_l510_3;
  wire                when_MaskUnit_l510_4;
  wire                when_MaskUnit_l510_5;
  wire       [3:0]    _zz_16;
  wire                when_MaskUnit_l517;
  reg                 rValid;
  reg        [31:0]   rFrame;
  wire                noMaskFire;
  reg                 _zz_io_faultNoMask;
  reg                 _zz_io_faultNonceDup;
  reg                 _zz_io_faultWrDuringRekey;

  assign _zz__zz_maskFrame_0 = (st_1[11 : 0] + 12'h46e);
  assign _zz__zz_maskFrame_0_1 = (_zz__zz_maskFrame_0_2 + _zz__zz_maskFrame_0_3);
  assign _zz__zz_maskFrame_0_2 = (st_0[31 : 12] + 20'h61707);
  assign _zz__zz_maskFrame_0_4 = (12'h79b <= st_0[11 : 0]);
  assign _zz__zz_maskFrame_0_3 = {19'd0, _zz__zz_maskFrame_0_4};
  assign _zz_nonceDup = (2'b00 != io_rekey_part);
  assign _zz_nonceDup_1 = (2'b01 != io_rekey_part);
  assign _zz_nonceDup_2 = 2'b10;
  always @(*) begin
    case(io_rekey_part)
      2'b00 : begin
        _zz_reqNonce = nonceFlat_0;
        _zz_st_4 = key_0_0;
        _zz_st_5 = key_0_1;
        _zz_st_6 = key_0_2;
        _zz_st_7 = key_0_3;
        _zz_st_8 = key_0_4;
        _zz_st_9 = key_0_5;
        _zz_st_10 = key_0_6;
        _zz_st_11 = key_0_7;
        _zz_st_12 = nonce_0_0;
        _zz_st_13 = nonce_0_1;
        _zz_st_14 = nonce_0_2;
        _zz_st_15 = nonce_0_3;
      end
      2'b01 : begin
        _zz_reqNonce = nonceFlat_1;
        _zz_st_4 = key_1_0;
        _zz_st_5 = key_1_1;
        _zz_st_6 = key_1_2;
        _zz_st_7 = key_1_3;
        _zz_st_8 = key_1_4;
        _zz_st_9 = key_1_5;
        _zz_st_10 = key_1_6;
        _zz_st_11 = key_1_7;
        _zz_st_12 = nonce_1_0;
        _zz_st_13 = nonce_1_1;
        _zz_st_14 = nonce_1_2;
        _zz_st_15 = nonce_1_3;
      end
      2'b10 : begin
        _zz_reqNonce = nonceFlat_2;
        _zz_st_4 = key_2_0;
        _zz_st_5 = key_2_1;
        _zz_st_6 = key_2_2;
        _zz_st_7 = key_2_3;
        _zz_st_8 = key_2_4;
        _zz_st_9 = key_2_5;
        _zz_st_10 = key_2_6;
        _zz_st_11 = key_2_7;
        _zz_st_12 = nonce_2_0;
        _zz_st_13 = nonce_2_1;
        _zz_st_14 = nonce_2_2;
        _zz_st_15 = nonce_2_3;
      end
      default : begin
        _zz_reqNonce = nonceFlat_3;
        _zz_st_4 = key_3_0;
        _zz_st_5 = key_3_1;
        _zz_st_6 = key_3_2;
        _zz_st_7 = key_3_3;
        _zz_st_8 = key_3_4;
        _zz_st_9 = key_3_5;
        _zz_st_10 = key_3_6;
        _zz_st_11 = key_3_7;
        _zz_st_12 = nonce_3_0;
        _zz_st_13 = nonce_3_1;
        _zz_st_14 = nonce_3_2;
        _zz_st_15 = nonce_3_3;
      end
    endcase
  end

  always @(*) begin
    case(actPart)
      2'b00 : begin
        _zz_st_14_1 = nonce_0_4;
        _zz_st_15_1 = nonce_0_5;
      end
      2'b01 : begin
        _zz_st_14_1 = nonce_1_4;
        _zz_st_15_1 = nonce_1_5;
      end
      2'b10 : begin
        _zz_st_14_1 = nonce_2_4;
        _zz_st_15_1 = nonce_2_5;
      end
      default : begin
        _zz_st_14_1 = nonce_3_4;
        _zz_st_15_1 = nonce_3_5;
      end
    endcase
  end

  always @(*) begin
    case(io_req_part)
      2'b00 : begin
        _zz_rFrame = maskFrame_0;
        _zz_noMaskFire = maskValid_0;
      end
      2'b01 : begin
        _zz_rFrame = maskFrame_1;
        _zz_noMaskFire = maskValid_1;
      end
      2'b10 : begin
        _zz_rFrame = maskFrame_2;
        _zz_noMaskFire = maskValid_2;
      end
      default : begin
        _zz_rFrame = maskFrame_3;
        _zz_noMaskFire = maskValid_3;
      end
    endcase
  end

  assign engineBusy = (phase != 3'b000);
  assign io_busy = engineBusy;
  assign io_rekey_ready = (! engineBusy);
  assign rekeyFire = (io_rekey_valid && io_rekey_ready);
  assign _zz_roundNext_0 = cnt[0];
  assign _zz_roundNext_0_1 = (st_0 + st_5);
  assign _zz_roundNext_10 = (st_15 ^ _zz_roundNext_0_1);
  assign _zz_roundNext_10_1 = {_zz_roundNext_10[15 : 0],_zz_roundNext_10[31 : 16]};
  assign _zz_roundNext_10_2 = (st_10 + _zz_roundNext_10_1);
  assign _zz_roundNext_0_2 = (st_5 ^ _zz_roundNext_10_2);
  assign _zz_roundNext_0_3 = {_zz_roundNext_0_2[19 : 0],_zz_roundNext_0_2[31 : 20]};
  assign _zz_roundNext_0_4 = (_zz_roundNext_0_1 + _zz_roundNext_0_3);
  assign _zz_roundNext_15 = (_zz_roundNext_10_1 ^ _zz_roundNext_0_4);
  assign _zz_roundNext_15_1 = {_zz_roundNext_15[23 : 0],_zz_roundNext_15[31 : 24]};
  assign _zz_roundNext_10_3 = (_zz_roundNext_10_2 + _zz_roundNext_15_1);
  assign _zz_roundNext_5 = (_zz_roundNext_0_3 ^ _zz_roundNext_10_3);
  assign _zz_roundNext_1 = (st_1 + st_6);
  assign _zz_roundNext_11 = (st_12 ^ _zz_roundNext_1);
  assign _zz_roundNext_11_1 = {_zz_roundNext_11[15 : 0],_zz_roundNext_11[31 : 16]};
  assign _zz_roundNext_11_2 = (st_11 + _zz_roundNext_11_1);
  assign _zz_roundNext_1_1 = (st_6 ^ _zz_roundNext_11_2);
  assign _zz_roundNext_1_2 = {_zz_roundNext_1_1[19 : 0],_zz_roundNext_1_1[31 : 20]};
  assign _zz_roundNext_1_3 = (_zz_roundNext_1 + _zz_roundNext_1_2);
  assign _zz_roundNext_12 = (_zz_roundNext_11_1 ^ _zz_roundNext_1_3);
  assign _zz_roundNext_12_1 = {_zz_roundNext_12[23 : 0],_zz_roundNext_12[31 : 24]};
  assign _zz_roundNext_11_3 = (_zz_roundNext_11_2 + _zz_roundNext_12_1);
  assign _zz_roundNext_6 = (_zz_roundNext_1_2 ^ _zz_roundNext_11_3);
  assign _zz_roundNext_2 = (st_2 + st_7);
  assign _zz_roundNext_8 = (st_13 ^ _zz_roundNext_2);
  assign _zz_roundNext_8_1 = {_zz_roundNext_8[15 : 0],_zz_roundNext_8[31 : 16]};
  assign _zz_roundNext_8_2 = (st_8 + _zz_roundNext_8_1);
  assign _zz_roundNext_2_1 = (st_7 ^ _zz_roundNext_8_2);
  assign _zz_roundNext_2_2 = {_zz_roundNext_2_1[19 : 0],_zz_roundNext_2_1[31 : 20]};
  assign _zz_roundNext_2_3 = (_zz_roundNext_2 + _zz_roundNext_2_2);
  assign _zz_roundNext_13 = (_zz_roundNext_8_1 ^ _zz_roundNext_2_3);
  assign _zz_roundNext_13_1 = {_zz_roundNext_13[23 : 0],_zz_roundNext_13[31 : 24]};
  assign _zz_roundNext_8_3 = (_zz_roundNext_8_2 + _zz_roundNext_13_1);
  assign _zz_roundNext_7 = (_zz_roundNext_2_2 ^ _zz_roundNext_8_3);
  assign _zz_roundNext_3 = (st_3 + st_4);
  assign _zz_roundNext_9 = (st_14 ^ _zz_roundNext_3);
  assign _zz_roundNext_9_1 = {_zz_roundNext_9[15 : 0],_zz_roundNext_9[31 : 16]};
  assign _zz_roundNext_9_2 = (st_9 + _zz_roundNext_9_1);
  assign _zz_roundNext_3_1 = (st_4 ^ _zz_roundNext_9_2);
  assign _zz_roundNext_3_2 = {_zz_roundNext_3_1[19 : 0],_zz_roundNext_3_1[31 : 20]};
  assign _zz_roundNext_3_3 = (_zz_roundNext_3 + _zz_roundNext_3_2);
  assign _zz_roundNext_14 = (_zz_roundNext_9_1 ^ _zz_roundNext_3_3);
  assign _zz_roundNext_14_1 = {_zz_roundNext_14[23 : 0],_zz_roundNext_14[31 : 24]};
  assign _zz_roundNext_9_3 = (_zz_roundNext_9_2 + _zz_roundNext_14_1);
  assign _zz_roundNext_4 = (_zz_roundNext_3_2 ^ _zz_roundNext_9_3);
  assign _zz_roundNext_0_5 = (st_0 + st_4);
  assign _zz_roundNext_8_4 = (st_12 ^ _zz_roundNext_0_5);
  assign _zz_roundNext_8_5 = {_zz_roundNext_8_4[15 : 0],_zz_roundNext_8_4[31 : 16]};
  assign _zz_roundNext_8_6 = (st_8 + _zz_roundNext_8_5);
  assign _zz_roundNext_0_6 = (st_4 ^ _zz_roundNext_8_6);
  assign _zz_roundNext_0_7 = {_zz_roundNext_0_6[19 : 0],_zz_roundNext_0_6[31 : 20]};
  assign _zz_roundNext_0_8 = (_zz_roundNext_0_5 + _zz_roundNext_0_7);
  assign _zz_roundNext_12_2 = (_zz_roundNext_8_5 ^ _zz_roundNext_0_8);
  assign _zz_roundNext_12_3 = {_zz_roundNext_12_2[23 : 0],_zz_roundNext_12_2[31 : 24]};
  assign _zz_roundNext_8_7 = (_zz_roundNext_8_6 + _zz_roundNext_12_3);
  assign _zz_roundNext_4_1 = (_zz_roundNext_0_7 ^ _zz_roundNext_8_7);
  assign _zz_roundNext_1_4 = (st_1 + st_5);
  assign _zz_roundNext_9_4 = (st_13 ^ _zz_roundNext_1_4);
  assign _zz_roundNext_9_5 = {_zz_roundNext_9_4[15 : 0],_zz_roundNext_9_4[31 : 16]};
  assign _zz_roundNext_9_6 = (st_9 + _zz_roundNext_9_5);
  assign _zz_roundNext_1_5 = (st_5 ^ _zz_roundNext_9_6);
  assign _zz_roundNext_1_6 = {_zz_roundNext_1_5[19 : 0],_zz_roundNext_1_5[31 : 20]};
  assign _zz_roundNext_1_7 = (_zz_roundNext_1_4 + _zz_roundNext_1_6);
  assign _zz_roundNext_13_2 = (_zz_roundNext_9_5 ^ _zz_roundNext_1_7);
  assign _zz_roundNext_13_3 = {_zz_roundNext_13_2[23 : 0],_zz_roundNext_13_2[31 : 24]};
  assign _zz_roundNext_9_7 = (_zz_roundNext_9_6 + _zz_roundNext_13_3);
  assign _zz_roundNext_5_1 = (_zz_roundNext_1_6 ^ _zz_roundNext_9_7);
  assign _zz_roundNext_2_4 = (st_2 + st_6);
  assign _zz_roundNext_10_4 = (st_14 ^ _zz_roundNext_2_4);
  assign _zz_roundNext_10_5 = {_zz_roundNext_10_4[15 : 0],_zz_roundNext_10_4[31 : 16]};
  assign _zz_roundNext_10_6 = (st_10 + _zz_roundNext_10_5);
  assign _zz_roundNext_2_5 = (st_6 ^ _zz_roundNext_10_6);
  assign _zz_roundNext_2_6 = {_zz_roundNext_2_5[19 : 0],_zz_roundNext_2_5[31 : 20]};
  assign _zz_roundNext_2_7 = (_zz_roundNext_2_4 + _zz_roundNext_2_6);
  assign _zz_roundNext_14_2 = (_zz_roundNext_10_5 ^ _zz_roundNext_2_7);
  assign _zz_roundNext_14_3 = {_zz_roundNext_14_2[23 : 0],_zz_roundNext_14_2[31 : 24]};
  assign _zz_roundNext_10_7 = (_zz_roundNext_10_6 + _zz_roundNext_14_3);
  assign _zz_roundNext_6_1 = (_zz_roundNext_2_6 ^ _zz_roundNext_10_7);
  assign _zz_roundNext_3_4 = (st_3 + st_7);
  assign _zz_roundNext_11_4 = (st_15 ^ _zz_roundNext_3_4);
  assign _zz_roundNext_11_5 = {_zz_roundNext_11_4[15 : 0],_zz_roundNext_11_4[31 : 16]};
  assign _zz_roundNext_11_6 = (st_11 + _zz_roundNext_11_5);
  assign _zz_roundNext_3_5 = (st_7 ^ _zz_roundNext_11_6);
  assign _zz_roundNext_3_6 = {_zz_roundNext_3_5[19 : 0],_zz_roundNext_3_5[31 : 20]};
  assign _zz_roundNext_3_7 = (_zz_roundNext_3_4 + _zz_roundNext_3_6);
  assign _zz_roundNext_15_2 = (_zz_roundNext_11_5 ^ _zz_roundNext_3_7);
  assign _zz_roundNext_15_3 = {_zz_roundNext_15_2[23 : 0],_zz_roundNext_15_2[31 : 24]};
  assign _zz_roundNext_11_7 = (_zz_roundNext_11_6 + _zz_roundNext_15_3);
  assign _zz_roundNext_7_1 = (_zz_roundNext_3_6 ^ _zz_roundNext_11_7);
  assign roundNext_0 = (_zz_roundNext_0 ? _zz_roundNext_0_4 : _zz_roundNext_0_8);
  assign roundNext_1 = (_zz_roundNext_0 ? _zz_roundNext_1_3 : _zz_roundNext_1_7);
  assign roundNext_2 = (_zz_roundNext_0 ? _zz_roundNext_2_3 : _zz_roundNext_2_7);
  assign roundNext_3 = (_zz_roundNext_0 ? _zz_roundNext_3_3 : _zz_roundNext_3_7);
  assign roundNext_4 = (_zz_roundNext_0 ? {_zz_roundNext_4[24 : 0],_zz_roundNext_4[31 : 25]} : {_zz_roundNext_4_1[24 : 0],_zz_roundNext_4_1[31 : 25]});
  assign roundNext_5 = (_zz_roundNext_0 ? {_zz_roundNext_5[24 : 0],_zz_roundNext_5[31 : 25]} : {_zz_roundNext_5_1[24 : 0],_zz_roundNext_5_1[31 : 25]});
  assign roundNext_6 = (_zz_roundNext_0 ? {_zz_roundNext_6[24 : 0],_zz_roundNext_6[31 : 25]} : {_zz_roundNext_6_1[24 : 0],_zz_roundNext_6_1[31 : 25]});
  assign roundNext_7 = (_zz_roundNext_0 ? {_zz_roundNext_7[24 : 0],_zz_roundNext_7[31 : 25]} : {_zz_roundNext_7_1[24 : 0],_zz_roundNext_7_1[31 : 25]});
  assign roundNext_8 = (_zz_roundNext_0 ? _zz_roundNext_8_3 : _zz_roundNext_8_7);
  assign roundNext_9 = (_zz_roundNext_0 ? _zz_roundNext_9_3 : _zz_roundNext_9_7);
  assign roundNext_10 = (_zz_roundNext_0 ? _zz_roundNext_10_3 : _zz_roundNext_10_7);
  assign roundNext_11 = (_zz_roundNext_0 ? _zz_roundNext_11_3 : _zz_roundNext_11_7);
  assign roundNext_12 = (_zz_roundNext_0 ? _zz_roundNext_12_1 : _zz_roundNext_12_3);
  assign roundNext_13 = (_zz_roundNext_0 ? _zz_roundNext_13_1 : _zz_roundNext_13_3);
  assign roundNext_14 = (_zz_roundNext_0 ? _zz_roundNext_14_1 : _zz_roundNext_14_3);
  assign roundNext_15 = (_zz_roundNext_0 ? _zz_roundNext_15_1 : _zz_roundNext_15_3);
  assign nonceFlat_0 = {nonce_0_5,{nonce_0_4,{nonce_0_3,{nonce_0_2,{nonce_0_1,nonce_0_0}}}}};
  assign nonceFlat_1 = {nonce_1_5,{nonce_1_4,{nonce_1_3,{nonce_1_2,{nonce_1_1,nonce_1_0}}}}};
  assign nonceFlat_2 = {nonce_2_5,{nonce_2_4,{nonce_2_3,{nonce_2_2,{nonce_2_1,nonce_2_0}}}}};
  assign nonceFlat_3 = {nonce_3_5,{nonce_3_4,{nonce_3_3,{nonce_3_2,{nonce_3_1,nonce_3_0}}}}};
  assign reqNonce = _zz_reqNonce;
  assign nonceDup = (((((maskValid_0 && _zz_nonceDup) && (nonceFlat_0 == reqNonce)) || ((maskValid_1 && _zz_nonceDup_1) && (nonceFlat_1 == reqNonce))) || ((maskValid_2 && (_zz_nonceDup_2 != io_rekey_part)) && (nonceFlat_2 == reqNonce))) || ((maskValid_3 && (2'b11 != io_rekey_part)) && (nonceFlat_3 == reqNonce)));
  assign nonceDupFire = (rekeyFire && nonceDup);
  assign nonceWrHit = (io_nonceWr_valid && (io_nonceWr_idx < 3'b110));
  assign wrActNow = ((io_keyWr_valid && (io_keyWr_part == actPart)) || (nonceWrHit && (io_nonceWr_part == actPart)));
  always @(*) begin
    dirtyAtFinal = 1'b0;
    case(phase)
      3'b100 : begin
        dirtyAtFinal = _zz_dirtyAtFinal;
      end
      default : begin
      end
    endcase
  end

  assign _zz_1 = ({3'd0,1'b1} <<< io_rekey_part);
  assign when_MaskUnit_l406 = (cnt == 5'h13);
  assign when_MaskUnit_l439 = (cnt == 5'h13);
  assign _zz_2 = ({3'd0,1'b1} <<< actPart);
  assign _zz_maskFrame_0 = {_zz__zz_maskFrame_0,_zz__zz_maskFrame_0_1};
  assign _zz_dirtyAtFinal = (compDirty || wrActNow);
  assign _zz_3 = ({3'd0,1'b1} <<< actPart);
  assign _zz_maskValid_0 = (! _zz_dirtyAtFinal);
  assign _zz_4 = ({3'd0,1'b1} <<< io_keyWr_part);
  assign _zz_5 = _zz_4[0];
  assign _zz_6 = _zz_4[1];
  assign _zz_7 = _zz_4[2];
  assign _zz_8 = _zz_4[3];
  assign _zz_9 = ({7'd0,1'b1} <<< io_keyWr_idx);
  assign _zz_10 = ({3'd0,1'b1} <<< io_keyWr_part);
  assign when_MaskUnit_l502 = ((engineBusy && (io_keyWr_part == actPart)) || (rekeyFire && (io_keyWr_part == io_rekey_part)));
  assign when_MaskUnit_l510 = (io_nonceWr_valid && (io_nonceWr_idx == 3'b000));
  assign _zz_11 = ({3'd0,1'b1} <<< io_nonceWr_part);
  assign _zz_12 = _zz_11[0];
  assign _zz_13 = _zz_11[1];
  assign _zz_14 = _zz_11[2];
  assign _zz_15 = _zz_11[3];
  assign when_MaskUnit_l510_1 = (io_nonceWr_valid && (io_nonceWr_idx == 3'b001));
  assign when_MaskUnit_l510_2 = (io_nonceWr_valid && (io_nonceWr_idx == 3'b010));
  assign when_MaskUnit_l510_3 = (io_nonceWr_valid && (io_nonceWr_idx == 3'b011));
  assign when_MaskUnit_l510_4 = (io_nonceWr_valid && (io_nonceWr_idx == 3'b100));
  assign when_MaskUnit_l510_5 = (io_nonceWr_valid && (io_nonceWr_idx == 3'b101));
  assign _zz_16 = ({3'd0,1'b1} <<< io_nonceWr_part);
  assign when_MaskUnit_l517 = ((engineBusy && (io_nonceWr_part == actPart)) || (rekeyFire && (io_nonceWr_part == io_rekey_part)));
  assign io_maskReady = {maskValid_3,{maskValid_2,{maskValid_1,maskValid_0}}};
  assign io_rsp_valid = rValid;
  assign io_rsp_frame = rFrame;
  assign noMaskFire = ((io_en && io_req_valid) && (! _zz_noMaskFire));
  assign io_faultNoMask = _zz_io_faultNoMask;
  assign io_faultNonceDup = _zz_io_faultNonceDup;
  assign io_faultWrDuringRekey = _zz_io_faultWrDuringRekey;
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      key_0_0 <= 32'h0;
      key_0_1 <= 32'h0;
      key_0_2 <= 32'h0;
      key_0_3 <= 32'h0;
      key_0_4 <= 32'h0;
      key_0_5 <= 32'h0;
      key_0_6 <= 32'h0;
      key_0_7 <= 32'h0;
      key_1_0 <= 32'h0;
      key_1_1 <= 32'h0;
      key_1_2 <= 32'h0;
      key_1_3 <= 32'h0;
      key_1_4 <= 32'h0;
      key_1_5 <= 32'h0;
      key_1_6 <= 32'h0;
      key_1_7 <= 32'h0;
      key_2_0 <= 32'h0;
      key_2_1 <= 32'h0;
      key_2_2 <= 32'h0;
      key_2_3 <= 32'h0;
      key_2_4 <= 32'h0;
      key_2_5 <= 32'h0;
      key_2_6 <= 32'h0;
      key_2_7 <= 32'h0;
      key_3_0 <= 32'h0;
      key_3_1 <= 32'h0;
      key_3_2 <= 32'h0;
      key_3_3 <= 32'h0;
      key_3_4 <= 32'h0;
      key_3_5 <= 32'h0;
      key_3_6 <= 32'h0;
      key_3_7 <= 32'h0;
      nonce_0_0 <= 32'h0;
      nonce_0_1 <= 32'h0;
      nonce_0_2 <= 32'h0;
      nonce_0_3 <= 32'h0;
      nonce_0_4 <= 32'h0;
      nonce_0_5 <= 32'h0;
      nonce_1_0 <= 32'h0;
      nonce_1_1 <= 32'h0;
      nonce_1_2 <= 32'h0;
      nonce_1_3 <= 32'h0;
      nonce_1_4 <= 32'h0;
      nonce_1_5 <= 32'h0;
      nonce_2_0 <= 32'h0;
      nonce_2_1 <= 32'h0;
      nonce_2_2 <= 32'h0;
      nonce_2_3 <= 32'h0;
      nonce_2_4 <= 32'h0;
      nonce_2_5 <= 32'h0;
      nonce_3_0 <= 32'h0;
      nonce_3_1 <= 32'h0;
      nonce_3_2 <= 32'h0;
      nonce_3_3 <= 32'h0;
      nonce_3_4 <= 32'h0;
      nonce_3_5 <= 32'h0;
      maskFrame_0 <= 32'h0;
      maskFrame_1 <= 32'h0;
      maskFrame_2 <= 32'h0;
      maskFrame_3 <= 32'h0;
      maskValid_0 <= 1'b0;
      maskValid_1 <= 1'b0;
      maskValid_2 <= 1'b0;
      maskValid_3 <= 1'b0;
      phase <= 3'b000;
      st_0 <= 32'h0;
      st_1 <= 32'h0;
      st_2 <= 32'h0;
      st_3 <= 32'h0;
      st_4 <= 32'h0;
      st_5 <= 32'h0;
      st_6 <= 32'h0;
      st_7 <= 32'h0;
      st_8 <= 32'h0;
      st_9 <= 32'h0;
      st_10 <= 32'h0;
      st_11 <= 32'h0;
      st_12 <= 32'h0;
      st_13 <= 32'h0;
      st_14 <= 32'h0;
      st_15 <= 32'h0;
      cnt <= 5'h0;
      actPart <= 2'b00;
      compDirty <= 1'b0;
      rValid <= 1'b0;
      rFrame <= 32'h0;
      _zz_io_faultNoMask <= 1'b0;
      _zz_io_faultNonceDup <= 1'b0;
      _zz_io_faultWrDuringRekey <= 1'b0;
    end else begin
      case(phase)
        3'b000 : begin
          if(rekeyFire) begin
            st_0 <= 32'h61707865;
            st_1 <= 32'h3320646e;
            st_2 <= 32'h79622d32;
            st_3 <= 32'h6b206574;
            st_4 <= _zz_st_4;
            st_5 <= _zz_st_5;
            st_6 <= _zz_st_6;
            st_7 <= _zz_st_7;
            st_8 <= _zz_st_8;
            st_9 <= _zz_st_9;
            st_10 <= _zz_st_10;
            st_11 <= _zz_st_11;
            st_12 <= _zz_st_12;
            st_13 <= _zz_st_13;
            st_14 <= _zz_st_14;
            st_15 <= _zz_st_15;
            actPart <= io_rekey_part;
            cnt <= 5'h0;
            compDirty <= 1'b0;
            if(_zz_1[0]) begin
              maskValid_0 <= 1'b0;
            end
            if(_zz_1[1]) begin
              maskValid_1 <= 1'b0;
            end
            if(_zz_1[2]) begin
              maskValid_2 <= 1'b0;
            end
            if(_zz_1[3]) begin
              maskValid_3 <= 1'b0;
            end
            phase <= 3'b001;
          end
        end
        3'b001 : begin
          st_0 <= roundNext_0;
          st_1 <= roundNext_1;
          st_2 <= roundNext_2;
          st_3 <= roundNext_3;
          st_4 <= roundNext_4;
          st_5 <= roundNext_5;
          st_6 <= roundNext_6;
          st_7 <= roundNext_7;
          st_8 <= roundNext_8;
          st_9 <= roundNext_9;
          st_10 <= roundNext_10;
          st_11 <= roundNext_11;
          st_12 <= roundNext_12;
          st_13 <= roundNext_13;
          st_14 <= roundNext_14;
          st_15 <= roundNext_15;
          cnt <= (cnt + 5'h01);
          if(when_MaskUnit_l406) begin
            phase <= 3'b010;
            cnt <= 5'h0;
          end
        end
        3'b010 : begin
          st_0 <= 32'h61707865;
          st_1 <= 32'h3320646e;
          st_2 <= 32'h79622d32;
          st_3 <= 32'h6b206574;
          st_4 <= st_0;
          st_5 <= st_1;
          st_6 <= st_2;
          st_7 <= st_3;
          st_8 <= st_12;
          st_9 <= st_13;
          st_10 <= st_14;
          st_11 <= st_15;
          st_12 <= 32'h0;
          st_13 <= 32'h0;
          st_14 <= _zz_st_14_1;
          st_15 <= _zz_st_15_1;
          phase <= 3'b011;
        end
        3'b011 : begin
          st_0 <= roundNext_0;
          st_1 <= roundNext_1;
          st_2 <= roundNext_2;
          st_3 <= roundNext_3;
          st_4 <= roundNext_4;
          st_5 <= roundNext_5;
          st_6 <= roundNext_6;
          st_7 <= roundNext_7;
          st_8 <= roundNext_8;
          st_9 <= roundNext_9;
          st_10 <= roundNext_10;
          st_11 <= roundNext_11;
          st_12 <= roundNext_12;
          st_13 <= roundNext_13;
          st_14 <= roundNext_14;
          st_15 <= roundNext_15;
          cnt <= (cnt + 5'h01);
          if(when_MaskUnit_l439) begin
            phase <= 3'b100;
          end
        end
        3'b100 : begin
          if(_zz_2[0]) begin
            maskFrame_0 <= _zz_maskFrame_0;
          end
          if(_zz_2[1]) begin
            maskFrame_1 <= _zz_maskFrame_0;
          end
          if(_zz_2[2]) begin
            maskFrame_2 <= _zz_maskFrame_0;
          end
          if(_zz_2[3]) begin
            maskFrame_3 <= _zz_maskFrame_0;
          end
          if(_zz_3[0]) begin
            maskValid_0 <= _zz_maskValid_0;
          end
          if(_zz_3[1]) begin
            maskValid_1 <= _zz_maskValid_0;
          end
          if(_zz_3[2]) begin
            maskValid_2 <= _zz_maskValid_0;
          end
          if(_zz_3[3]) begin
            maskValid_3 <= _zz_maskValid_0;
          end
          phase <= 3'b000;
        end
        default : begin
        end
      endcase
      if(io_keyWr_valid) begin
        if(_zz_9[0]) begin
          if(_zz_5) begin
            key_0_0 <= io_keyWr_data;
          end
          if(_zz_6) begin
            key_1_0 <= io_keyWr_data;
          end
          if(_zz_7) begin
            key_2_0 <= io_keyWr_data;
          end
          if(_zz_8) begin
            key_3_0 <= io_keyWr_data;
          end
        end
        if(_zz_9[1]) begin
          if(_zz_5) begin
            key_0_1 <= io_keyWr_data;
          end
          if(_zz_6) begin
            key_1_1 <= io_keyWr_data;
          end
          if(_zz_7) begin
            key_2_1 <= io_keyWr_data;
          end
          if(_zz_8) begin
            key_3_1 <= io_keyWr_data;
          end
        end
        if(_zz_9[2]) begin
          if(_zz_5) begin
            key_0_2 <= io_keyWr_data;
          end
          if(_zz_6) begin
            key_1_2 <= io_keyWr_data;
          end
          if(_zz_7) begin
            key_2_2 <= io_keyWr_data;
          end
          if(_zz_8) begin
            key_3_2 <= io_keyWr_data;
          end
        end
        if(_zz_9[3]) begin
          if(_zz_5) begin
            key_0_3 <= io_keyWr_data;
          end
          if(_zz_6) begin
            key_1_3 <= io_keyWr_data;
          end
          if(_zz_7) begin
            key_2_3 <= io_keyWr_data;
          end
          if(_zz_8) begin
            key_3_3 <= io_keyWr_data;
          end
        end
        if(_zz_9[4]) begin
          if(_zz_5) begin
            key_0_4 <= io_keyWr_data;
          end
          if(_zz_6) begin
            key_1_4 <= io_keyWr_data;
          end
          if(_zz_7) begin
            key_2_4 <= io_keyWr_data;
          end
          if(_zz_8) begin
            key_3_4 <= io_keyWr_data;
          end
        end
        if(_zz_9[5]) begin
          if(_zz_5) begin
            key_0_5 <= io_keyWr_data;
          end
          if(_zz_6) begin
            key_1_5 <= io_keyWr_data;
          end
          if(_zz_7) begin
            key_2_5 <= io_keyWr_data;
          end
          if(_zz_8) begin
            key_3_5 <= io_keyWr_data;
          end
        end
        if(_zz_9[6]) begin
          if(_zz_5) begin
            key_0_6 <= io_keyWr_data;
          end
          if(_zz_6) begin
            key_1_6 <= io_keyWr_data;
          end
          if(_zz_7) begin
            key_2_6 <= io_keyWr_data;
          end
          if(_zz_8) begin
            key_3_6 <= io_keyWr_data;
          end
        end
        if(_zz_9[7]) begin
          if(_zz_5) begin
            key_0_7 <= io_keyWr_data;
          end
          if(_zz_6) begin
            key_1_7 <= io_keyWr_data;
          end
          if(_zz_7) begin
            key_2_7 <= io_keyWr_data;
          end
          if(_zz_8) begin
            key_3_7 <= io_keyWr_data;
          end
        end
        if(_zz_10[0]) begin
          maskValid_0 <= 1'b0;
        end
        if(_zz_10[1]) begin
          maskValid_1 <= 1'b0;
        end
        if(_zz_10[2]) begin
          maskValid_2 <= 1'b0;
        end
        if(_zz_10[3]) begin
          maskValid_3 <= 1'b0;
        end
        if(when_MaskUnit_l502) begin
          compDirty <= 1'b1;
        end
      end
      if(when_MaskUnit_l510) begin
        if(_zz_12) begin
          nonce_0_0 <= io_nonceWr_data;
        end
        if(_zz_13) begin
          nonce_1_0 <= io_nonceWr_data;
        end
        if(_zz_14) begin
          nonce_2_0 <= io_nonceWr_data;
        end
        if(_zz_15) begin
          nonce_3_0 <= io_nonceWr_data;
        end
      end
      if(when_MaskUnit_l510_1) begin
        if(_zz_12) begin
          nonce_0_1 <= io_nonceWr_data;
        end
        if(_zz_13) begin
          nonce_1_1 <= io_nonceWr_data;
        end
        if(_zz_14) begin
          nonce_2_1 <= io_nonceWr_data;
        end
        if(_zz_15) begin
          nonce_3_1 <= io_nonceWr_data;
        end
      end
      if(when_MaskUnit_l510_2) begin
        if(_zz_12) begin
          nonce_0_2 <= io_nonceWr_data;
        end
        if(_zz_13) begin
          nonce_1_2 <= io_nonceWr_data;
        end
        if(_zz_14) begin
          nonce_2_2 <= io_nonceWr_data;
        end
        if(_zz_15) begin
          nonce_3_2 <= io_nonceWr_data;
        end
      end
      if(when_MaskUnit_l510_3) begin
        if(_zz_12) begin
          nonce_0_3 <= io_nonceWr_data;
        end
        if(_zz_13) begin
          nonce_1_3 <= io_nonceWr_data;
        end
        if(_zz_14) begin
          nonce_2_3 <= io_nonceWr_data;
        end
        if(_zz_15) begin
          nonce_3_3 <= io_nonceWr_data;
        end
      end
      if(when_MaskUnit_l510_4) begin
        if(_zz_12) begin
          nonce_0_4 <= io_nonceWr_data;
        end
        if(_zz_13) begin
          nonce_1_4 <= io_nonceWr_data;
        end
        if(_zz_14) begin
          nonce_2_4 <= io_nonceWr_data;
        end
        if(_zz_15) begin
          nonce_3_4 <= io_nonceWr_data;
        end
      end
      if(when_MaskUnit_l510_5) begin
        if(_zz_12) begin
          nonce_0_5 <= io_nonceWr_data;
        end
        if(_zz_13) begin
          nonce_1_5 <= io_nonceWr_data;
        end
        if(_zz_14) begin
          nonce_2_5 <= io_nonceWr_data;
        end
        if(_zz_15) begin
          nonce_3_5 <= io_nonceWr_data;
        end
      end
      if(nonceWrHit) begin
        if(_zz_16[0]) begin
          maskValid_0 <= 1'b0;
        end
        if(_zz_16[1]) begin
          maskValid_1 <= 1'b0;
        end
        if(_zz_16[2]) begin
          maskValid_2 <= 1'b0;
        end
        if(_zz_16[3]) begin
          maskValid_3 <= 1'b0;
        end
        if(when_MaskUnit_l517) begin
          compDirty <= 1'b1;
        end
      end
      if(io_en) begin
        rValid <= io_req_valid;
        rFrame <= (io_req_frame ^ _zz_rFrame);
      end
      if(io_faultClearNoMask) begin
        _zz_io_faultNoMask <= 1'b0;
      end
      if(noMaskFire) begin
        _zz_io_faultNoMask <= 1'b1;
      end
      if(io_faultClearNonceDup) begin
        _zz_io_faultNonceDup <= 1'b0;
      end
      if(nonceDupFire) begin
        _zz_io_faultNonceDup <= 1'b1;
      end
      if(io_faultClearWrRekey) begin
        _zz_io_faultWrDuringRekey <= 1'b0;
      end
      if(dirtyAtFinal) begin
        _zz_io_faultWrDuringRekey <= 1'b1;
      end
    end
  end


endmodule
