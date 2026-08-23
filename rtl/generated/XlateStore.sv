// Generator : SpinalHDL v1.14.2    git head : 78f29dc66110fc099a777992b6daa2f803ab445e
// Component : XlateStore
// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
// 
// === 생성물이다. 손으로 고치지 말 것. ===
// 고칠 곳은 rtl/spinal/ 의 생성기이고, 고친 뒤 `make rtl-gen` 으로 다시 낸다.
// 여기 직접 쓴 수정은 다음 생성에서 조용히 사라진다.

`timescale 1ns/1ps

module XlateStore (
  input  wire          io_lookup_valid,
  input  wire [1:0]    io_lookup_part,
  input  wire [31:0]   io_lookup_vpn,
  output wire          io_rsp_hit,
  output wire          io_rsp_fromFill,
  output reg  [31:0]   io_rsp_frame,
  output reg           io_rsp_perm_r,
  output reg           io_rsp_perm_w,
  output reg           io_rsp_perm_x,
  output wire          io_rsp_hostPresent,
  output wire [31:0]   io_rsp_hostFrame,
  output wire          io_rsp_hostPerm_r,
  output wire          io_rsp_hostPerm_w,
  output wire          io_rsp_hostPerm_x,
  input  wire          io_hostRsp_valid,
  input  wire [31:0]   io_hostRsp_frame,
  input  wire          io_hostRsp_perm_r,
  input  wire          io_hostRsp_perm_w,
  input  wire          io_hostRsp_perm_x,
  input  wire          io_install_valid,
  output wire          io_install_ready,
  input  wire [1:0]    io_install_part,
  input  wire [3:0]    io_install_idx,
  input  wire [27:0]   io_install_tag,
  input  wire [31:0]   io_install_frame,
  input  wire          io_install_perm_r,
  input  wire          io_install_perm_w,
  input  wire          io_install_perm_x,
  input  wire          io_flush_valid,
  input  wire [1:0]    io_flush_part,
  input  wire          clk,
  input  wire          reset
);

  wire       [62:0]   store_spinal_port1;
  reg                 _zz_io_install_ready;
  reg        [3:0]    _zz_commitLine_idx;
  reg        [27:0]   _zz_commitLine_tag;
  reg        [31:0]   _zz_commitLine_frame;
  reg                 _zz_commitLine_perm_r;
  reg                 _zz_commitLine_perm_w;
  reg                 _zz_commitLine_perm_x;
  wire       [5:0]    _zz_store_port;
  wire       [62:0]   _zz_store_port_1;
  reg        [15:0]   _zz_storeValid;
  reg        [3:0]    _zz_fillLine_idx;
  reg        [27:0]   _zz_fillLine_tag;
  reg        [31:0]   _zz_fillLine_frame;
  reg                 _zz_fillLine_perm_r;
  reg                 _zz_fillLine_perm_w;
  reg                 _zz_fillLine_perm_x;
  reg                 _zz_fillHit;
  reg        [15:0]   validBits_0;
  reg        [15:0]   validBits_1;
  reg        [15:0]   validBits_2;
  reg        [15:0]   validBits_3;
  reg                 fillPend_0;
  reg                 fillPend_1;
  reg                 fillPend_2;
  reg                 fillPend_3;
  reg        [3:0]    fillSlot_0_idx;
  reg        [27:0]   fillSlot_0_tag;
  reg        [31:0]   fillSlot_0_frame;
  reg                 fillSlot_0_perm_r;
  reg                 fillSlot_0_perm_w;
  reg                 fillSlot_0_perm_x;
  reg        [3:0]    fillSlot_1_idx;
  reg        [27:0]   fillSlot_1_tag;
  reg        [31:0]   fillSlot_1_frame;
  reg                 fillSlot_1_perm_r;
  reg                 fillSlot_1_perm_w;
  reg                 fillSlot_1_perm_x;
  reg        [3:0]    fillSlot_2_idx;
  reg        [27:0]   fillSlot_2_tag;
  reg        [31:0]   fillSlot_2_frame;
  reg                 fillSlot_2_perm_r;
  reg                 fillSlot_2_perm_w;
  reg                 fillSlot_2_perm_x;
  reg        [3:0]    fillSlot_3_idx;
  reg        [27:0]   fillSlot_3_tag;
  reg        [31:0]   fillSlot_3_frame;
  reg                 fillSlot_3_perm_r;
  reg                 fillSlot_3_perm_w;
  reg                 fillSlot_3_perm_x;
  wire                flushSamePart;
  wire       [3:0]    _zz_1;
  wire                when_XlateStore_l200;
  wire       [3:0]    _zz_2;
  wire                _zz_3;
  wire                _zz_4;
  wire                _zz_5;
  wire                _zz_6;
  wire       [3:0]    commitPend;
  wire                commitFire;
  wire                _zz_commitSel;
  wire       [1:0]    commitSel;
  wire       [3:0]    commitLine_idx;
  wire       [27:0]   commitLine_tag;
  wire       [31:0]   commitLine_frame;
  wire                commitLine_perm_r;
  wire                commitLine_perm_w;
  wire                commitLine_perm_x;
  wire       [27:0]   commitBody_tag;
  wire       [31:0]   commitBody_frame;
  wire                commitBody_perm_r;
  wire                commitBody_perm_w;
  wire                commitBody_perm_x;
  wire       [3:0]    _zz_8;
  wire       [3:0]    _zz_9;
  wire       [3:0]    _zz_10;
  wire       [3:0]    _zz_11;
  wire       [3:0]    reqIdx;
  wire       [27:0]   reqTag;
  wire       [5:0]    entryAddr;
  wire       [27:0]   storeBody_tag;
  wire       [31:0]   storeBody_frame;
  wire                storeBody_perm_r;
  wire                storeBody_perm_w;
  wire                storeBody_perm_x;
  wire       [62:0]   _zz_storeBody_tag;
  wire       [2:0]    _zz_storeBody_perm_r;
  wire                storeValid;
  wire                storeHit;
  wire       [3:0]    fillLine_idx;
  wire       [27:0]   fillLine_tag;
  wire       [31:0]   fillLine_frame;
  wire                fillLine_perm_r;
  wire                fillLine_perm_w;
  wire                fillLine_perm_x;
  wire                fillHit;
  (* ram_style = "distributed" *) reg [62:0] store [0:63];

  assign _zz_store_port = {commitSel,commitLine_idx};
  assign _zz_store_port_1 = {{commitBody_perm_x,{commitBody_perm_w,commitBody_perm_r}},{commitBody_frame,commitBody_tag}};
  always @(posedge clk) begin
    if(commitFire) begin
      store[_zz_store_port] <= _zz_store_port_1;
    end
  end

  assign store_spinal_port1 = store[entryAddr];
  always @(*) begin
    case(io_install_part)
      2'b00 : _zz_io_install_ready = fillPend_0;
      2'b01 : _zz_io_install_ready = fillPend_1;
      2'b10 : _zz_io_install_ready = fillPend_2;
      default : _zz_io_install_ready = fillPend_3;
    endcase
  end

  always @(*) begin
    case(commitSel)
      2'b00 : begin
        _zz_commitLine_idx = fillSlot_0_idx;
        _zz_commitLine_tag = fillSlot_0_tag;
        _zz_commitLine_frame = fillSlot_0_frame;
        _zz_commitLine_perm_r = fillSlot_0_perm_r;
        _zz_commitLine_perm_w = fillSlot_0_perm_w;
        _zz_commitLine_perm_x = fillSlot_0_perm_x;
      end
      2'b01 : begin
        _zz_commitLine_idx = fillSlot_1_idx;
        _zz_commitLine_tag = fillSlot_1_tag;
        _zz_commitLine_frame = fillSlot_1_frame;
        _zz_commitLine_perm_r = fillSlot_1_perm_r;
        _zz_commitLine_perm_w = fillSlot_1_perm_w;
        _zz_commitLine_perm_x = fillSlot_1_perm_x;
      end
      2'b10 : begin
        _zz_commitLine_idx = fillSlot_2_idx;
        _zz_commitLine_tag = fillSlot_2_tag;
        _zz_commitLine_frame = fillSlot_2_frame;
        _zz_commitLine_perm_r = fillSlot_2_perm_r;
        _zz_commitLine_perm_w = fillSlot_2_perm_w;
        _zz_commitLine_perm_x = fillSlot_2_perm_x;
      end
      default : begin
        _zz_commitLine_idx = fillSlot_3_idx;
        _zz_commitLine_tag = fillSlot_3_tag;
        _zz_commitLine_frame = fillSlot_3_frame;
        _zz_commitLine_perm_r = fillSlot_3_perm_r;
        _zz_commitLine_perm_w = fillSlot_3_perm_w;
        _zz_commitLine_perm_x = fillSlot_3_perm_x;
      end
    endcase
  end

  always @(*) begin
    case(io_lookup_part)
      2'b00 : begin
        _zz_storeValid = validBits_0;
        _zz_fillLine_idx = fillSlot_0_idx;
        _zz_fillLine_tag = fillSlot_0_tag;
        _zz_fillLine_frame = fillSlot_0_frame;
        _zz_fillLine_perm_r = fillSlot_0_perm_r;
        _zz_fillLine_perm_w = fillSlot_0_perm_w;
        _zz_fillLine_perm_x = fillSlot_0_perm_x;
        _zz_fillHit = fillPend_0;
      end
      2'b01 : begin
        _zz_storeValid = validBits_1;
        _zz_fillLine_idx = fillSlot_1_idx;
        _zz_fillLine_tag = fillSlot_1_tag;
        _zz_fillLine_frame = fillSlot_1_frame;
        _zz_fillLine_perm_r = fillSlot_1_perm_r;
        _zz_fillLine_perm_w = fillSlot_1_perm_w;
        _zz_fillLine_perm_x = fillSlot_1_perm_x;
        _zz_fillHit = fillPend_1;
      end
      2'b10 : begin
        _zz_storeValid = validBits_2;
        _zz_fillLine_idx = fillSlot_2_idx;
        _zz_fillLine_tag = fillSlot_2_tag;
        _zz_fillLine_frame = fillSlot_2_frame;
        _zz_fillLine_perm_r = fillSlot_2_perm_r;
        _zz_fillLine_perm_w = fillSlot_2_perm_w;
        _zz_fillLine_perm_x = fillSlot_2_perm_x;
        _zz_fillHit = fillPend_2;
      end
      default : begin
        _zz_storeValid = validBits_3;
        _zz_fillLine_idx = fillSlot_3_idx;
        _zz_fillLine_tag = fillSlot_3_tag;
        _zz_fillLine_frame = fillSlot_3_frame;
        _zz_fillLine_perm_r = fillSlot_3_perm_r;
        _zz_fillLine_perm_w = fillSlot_3_perm_w;
        _zz_fillLine_perm_x = fillSlot_3_perm_x;
        _zz_fillHit = fillPend_3;
      end
    endcase
  end

  assign flushSamePart = (io_flush_valid && (io_flush_part == io_install_part));
  assign _zz_1 = ({3'd0,1'b1} <<< io_install_part);
  assign io_install_ready = ((! _zz_io_install_ready) && (! flushSamePart));
  assign when_XlateStore_l200 = (io_install_valid && io_install_ready);
  assign _zz_2 = ({3'd0,1'b1} <<< io_install_part);
  assign _zz_3 = _zz_2[0];
  assign _zz_4 = _zz_2[1];
  assign _zz_5 = _zz_2[2];
  assign _zz_6 = _zz_2[3];
  assign commitPend = {fillPend_3,{fillPend_2,{fillPend_1,fillPend_0}}};
  assign commitFire = (|commitPend);
  assign _zz_commitSel = commitPend[0];
  assign commitSel = ((_zz_commitSel || commitPend[1]) ? (_zz_commitSel ? 2'b00 : 2'b01) : (commitPend[2] ? 2'b10 : 2'b11));
  assign commitLine_idx = _zz_commitLine_idx;
  assign commitLine_tag = _zz_commitLine_tag;
  assign commitLine_frame = _zz_commitLine_frame;
  assign commitLine_perm_r = _zz_commitLine_perm_r;
  assign commitLine_perm_w = _zz_commitLine_perm_w;
  assign commitLine_perm_x = _zz_commitLine_perm_x;
  assign commitBody_tag = commitLine_tag;
  assign commitBody_frame = commitLine_frame;
  assign commitBody_perm_r = commitLine_perm_r;
  assign commitBody_perm_w = commitLine_perm_w;
  assign commitBody_perm_x = commitLine_perm_x;
  assign _zz_8 = ({3'd0,1'b1} <<< commitSel);
  assign _zz_9 = ({3'd0,1'b1} <<< commitSel);
  assign _zz_10 = ({3'd0,1'b1} <<< io_flush_part);
  assign _zz_11 = ({3'd0,1'b1} <<< io_flush_part);
  assign reqIdx = io_lookup_vpn[3 : 0];
  assign reqTag = io_lookup_vpn[31 : 4];
  assign entryAddr = {io_lookup_part,reqIdx};
  assign _zz_storeBody_tag = store_spinal_port1;
  assign storeBody_tag = _zz_storeBody_tag[27 : 0];
  assign storeBody_frame = _zz_storeBody_tag[59 : 28];
  assign _zz_storeBody_perm_r = _zz_storeBody_tag[62 : 60];
  assign storeBody_perm_r = _zz_storeBody_perm_r[0];
  assign storeBody_perm_w = _zz_storeBody_perm_r[1];
  assign storeBody_perm_x = _zz_storeBody_perm_r[2];
  assign storeValid = _zz_storeValid[reqIdx];
  assign storeHit = ((io_lookup_valid && storeValid) && (storeBody_tag == reqTag));
  assign fillLine_idx = _zz_fillLine_idx;
  assign fillLine_tag = _zz_fillLine_tag;
  assign fillLine_frame = _zz_fillLine_frame;
  assign fillLine_perm_r = _zz_fillLine_perm_r;
  assign fillLine_perm_w = _zz_fillLine_perm_w;
  assign fillLine_perm_x = _zz_fillLine_perm_x;
  assign fillHit = (((io_lookup_valid && _zz_fillHit) && (fillLine_idx == reqIdx)) && (fillLine_tag == reqTag));
  assign io_rsp_hit = (fillHit || storeHit);
  assign io_rsp_fromFill = fillHit;
  always @(*) begin
    io_rsp_frame = 32'h0;
    if(fillHit) begin
      io_rsp_frame = fillLine_frame;
    end else begin
      if(storeHit) begin
        io_rsp_frame = storeBody_frame;
      end
    end
  end

  always @(*) begin
    io_rsp_perm_r = 1'b0;
    if(fillHit) begin
      io_rsp_perm_r = fillLine_perm_r;
    end else begin
      if(storeHit) begin
        io_rsp_perm_r = storeBody_perm_r;
      end
    end
  end

  always @(*) begin
    io_rsp_perm_w = 1'b0;
    if(fillHit) begin
      io_rsp_perm_w = fillLine_perm_w;
    end else begin
      if(storeHit) begin
        io_rsp_perm_w = storeBody_perm_w;
      end
    end
  end

  always @(*) begin
    io_rsp_perm_x = 1'b0;
    if(fillHit) begin
      io_rsp_perm_x = fillLine_perm_x;
    end else begin
      if(storeHit) begin
        io_rsp_perm_x = storeBody_perm_x;
      end
    end
  end

  assign io_rsp_hostPresent = io_hostRsp_valid;
  assign io_rsp_hostFrame = io_hostRsp_frame;
  assign io_rsp_hostPerm_r = io_hostRsp_perm_r;
  assign io_rsp_hostPerm_w = io_hostRsp_perm_w;
  assign io_rsp_hostPerm_x = io_hostRsp_perm_x;
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      validBits_0 <= 16'h0;
      validBits_1 <= 16'h0;
      validBits_2 <= 16'h0;
      validBits_3 <= 16'h0;
      fillPend_0 <= 1'b0;
      fillPend_1 <= 1'b0;
      fillPend_2 <= 1'b0;
      fillPend_3 <= 1'b0;
    end else begin
      if(when_XlateStore_l200) begin
        if(_zz_1[0]) begin
          fillPend_0 <= 1'b1;
        end
        if(_zz_1[1]) begin
          fillPend_1 <= 1'b1;
        end
        if(_zz_1[2]) begin
          fillPend_2 <= 1'b1;
        end
        if(_zz_1[3]) begin
          fillPend_3 <= 1'b1;
        end
      end
      if(commitFire) begin
        if(_zz_8[0]) begin
          validBits_0[commitLine_idx] <= 1'b1;
        end
        if(_zz_8[1]) begin
          validBits_1[commitLine_idx] <= 1'b1;
        end
        if(_zz_8[2]) begin
          validBits_2[commitLine_idx] <= 1'b1;
        end
        if(_zz_8[3]) begin
          validBits_3[commitLine_idx] <= 1'b1;
        end
        if(_zz_9[0]) begin
          fillPend_0 <= 1'b0;
        end
        if(_zz_9[1]) begin
          fillPend_1 <= 1'b0;
        end
        if(_zz_9[2]) begin
          fillPend_2 <= 1'b0;
        end
        if(_zz_9[3]) begin
          fillPend_3 <= 1'b0;
        end
      end
      if(io_flush_valid) begin
        if(_zz_10[0]) begin
          validBits_0 <= 16'h0;
        end
        if(_zz_10[1]) begin
          validBits_1 <= 16'h0;
        end
        if(_zz_10[2]) begin
          validBits_2 <= 16'h0;
        end
        if(_zz_10[3]) begin
          validBits_3 <= 16'h0;
        end
        if(_zz_11[0]) begin
          fillPend_0 <= 1'b0;
        end
        if(_zz_11[1]) begin
          fillPend_1 <= 1'b0;
        end
        if(_zz_11[2]) begin
          fillPend_2 <= 1'b0;
        end
        if(_zz_11[3]) begin
          fillPend_3 <= 1'b0;
        end
      end
    end
  end

  always @(posedge clk) begin
    if(when_XlateStore_l200) begin
      if(_zz_3) begin
        fillSlot_0_idx <= io_install_idx;
      end
      if(_zz_4) begin
        fillSlot_1_idx <= io_install_idx;
      end
      if(_zz_5) begin
        fillSlot_2_idx <= io_install_idx;
      end
      if(_zz_6) begin
        fillSlot_3_idx <= io_install_idx;
      end
      if(_zz_3) begin
        fillSlot_0_tag <= io_install_tag;
      end
      if(_zz_4) begin
        fillSlot_1_tag <= io_install_tag;
      end
      if(_zz_5) begin
        fillSlot_2_tag <= io_install_tag;
      end
      if(_zz_6) begin
        fillSlot_3_tag <= io_install_tag;
      end
      if(_zz_3) begin
        fillSlot_0_frame <= io_install_frame;
      end
      if(_zz_4) begin
        fillSlot_1_frame <= io_install_frame;
      end
      if(_zz_5) begin
        fillSlot_2_frame <= io_install_frame;
      end
      if(_zz_6) begin
        fillSlot_3_frame <= io_install_frame;
      end
      if(_zz_3) begin
        fillSlot_0_perm_r <= io_install_perm_r;
      end
      if(_zz_4) begin
        fillSlot_1_perm_r <= io_install_perm_r;
      end
      if(_zz_5) begin
        fillSlot_2_perm_r <= io_install_perm_r;
      end
      if(_zz_6) begin
        fillSlot_3_perm_r <= io_install_perm_r;
      end
      if(_zz_3) begin
        fillSlot_0_perm_w <= io_install_perm_w;
      end
      if(_zz_4) begin
        fillSlot_1_perm_w <= io_install_perm_w;
      end
      if(_zz_5) begin
        fillSlot_2_perm_w <= io_install_perm_w;
      end
      if(_zz_6) begin
        fillSlot_3_perm_w <= io_install_perm_w;
      end
      if(_zz_3) begin
        fillSlot_0_perm_x <= io_install_perm_x;
      end
      if(_zz_4) begin
        fillSlot_1_perm_x <= io_install_perm_x;
      end
      if(_zz_5) begin
        fillSlot_2_perm_x <= io_install_perm_x;
      end
      if(_zz_6) begin
        fillSlot_3_perm_x <= io_install_perm_x;
      end
    end
  end


endmodule
