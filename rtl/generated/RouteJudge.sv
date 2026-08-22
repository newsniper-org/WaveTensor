// Generator : SpinalHDL v1.14.2    git head : 78f29dc66110fc099a777992b6daa2f803ab445e
// Component : RouteJudge
// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
// 
// === 생성물이다. 손으로 고치지 말 것. ===
// 고칠 곳은 rtl/spinal/ 의 생성기이고, 고친 뒤 `make rtl-gen` 으로 다시 낸다.
// 여기 직접 쓴 수정은 다음 생성에서 조용히 사라진다.

`timescale 1ns/1ps

module RouteJudge (
  input  wire          io_tokIn_valid,
  input  wire [31:0]   io_tokIn_payload_tag_wave,
  input  wire [15:0]   io_tokIn_payload_tag_thread,
  input  wire [15:0]   io_tokIn_payload_tag_lnid,
  input  wire [7:0]    io_tokIn_payload_tag_precision,
  input  wire [7:0]    io_tokIn_payload_tag_dim,
  input  wire [7:0]    io_tokIn_payload_lbid,
  input  wire [3:0]    io_tokIn_payload_srcKind,
  output wire          io_tokOut_valid,
  output wire [31:0]   io_tokOut_payload_tag_wave,
  output wire [15:0]   io_tokOut_payload_tag_thread,
  output wire [15:0]   io_tokOut_payload_tag_lnid,
  output wire [7:0]    io_tokOut_payload_tag_precision,
  output wire [7:0]    io_tokOut_payload_tag_dim,
  output wire [7:0]    io_tokOut_payload_lbid,
  output wire [3:0]    io_tokOut_payload_srcKind,
  input  wire          io_viewWr_valid,
  input  wire [3:0]    io_viewWr_idx,
  input  wire          io_viewWr_en,
  input  wire [15:0]   io_viewWr_lnid,
  input  wire          io_bankWr_valid,
  input  wire [7:0]    io_bankWr_lbid,
  input  wire          io_bankWr_mapped,
  output wire          io_fault,
  input  wire          io_faultClear,
  output wire          io_faultFire,
  input  wire          clk,
  input  wire          reset
);

  wire                _zz_viewHit;
  wire                _zz_viewHit_1;
  wire                _zz_viewHit_2;
  wire                _zz_viewHit_3;
  wire                _zz_viewHit_4;
  wire                _zz_viewHit_5;
  reg                 viewValid_0;
  reg                 viewValid_1;
  reg                 viewValid_2;
  reg                 viewValid_3;
  reg                 viewValid_4;
  reg                 viewValid_5;
  reg                 viewValid_6;
  reg                 viewValid_7;
  reg                 viewValid_8;
  reg                 viewValid_9;
  reg                 viewValid_10;
  reg                 viewValid_11;
  reg                 viewValid_12;
  reg                 viewValid_13;
  reg                 viewValid_14;
  reg                 viewValid_15;
  reg        [15:0]   viewName_0;
  reg        [15:0]   viewName_1;
  reg        [15:0]   viewName_2;
  reg        [15:0]   viewName_3;
  reg        [15:0]   viewName_4;
  reg        [15:0]   viewName_5;
  reg        [15:0]   viewName_6;
  reg        [15:0]   viewName_7;
  reg        [15:0]   viewName_8;
  reg        [15:0]   viewName_9;
  reg        [15:0]   viewName_10;
  reg        [15:0]   viewName_11;
  reg        [15:0]   viewName_12;
  reg        [15:0]   viewName_13;
  reg        [15:0]   viewName_14;
  reg        [15:0]   viewName_15;
  reg        [255:0]  bankPresent;
  wire       [15:0]   _zz_1;
  wire       [15:0]   _zz_2;
  wire                viewHit;
  wire                missLnid;
  wire                missLbid;
  wire                anyMiss;
  wire                faultFire;
  reg                 _zz_io_fault;

  assign _zz_viewHit = (((((((_zz_viewHit_1 || _zz_viewHit_2) || (viewValid_3 && _zz_viewHit_3)) || (viewValid_4 && (viewName_4 == io_tokIn_payload_tag_lnid))) || (viewValid_5 && (viewName_5 == io_tokIn_payload_tag_lnid))) || (viewValid_6 && (viewName_6 == io_tokIn_payload_tag_lnid))) || (viewValid_7 && (viewName_7 == io_tokIn_payload_tag_lnid))) || (viewValid_8 && (viewName_8 == io_tokIn_payload_tag_lnid)));
  assign _zz_viewHit_4 = (viewValid_9 && (viewName_9 == io_tokIn_payload_tag_lnid));
  assign _zz_viewHit_5 = (viewName_10 == io_tokIn_payload_tag_lnid);
  assign _zz_viewHit_1 = ((viewValid_0 && (viewName_0 == io_tokIn_payload_tag_lnid)) || (viewValid_1 && (viewName_1 == io_tokIn_payload_tag_lnid)));
  assign _zz_viewHit_2 = (viewValid_2 && (viewName_2 == io_tokIn_payload_tag_lnid));
  assign _zz_viewHit_3 = (viewName_3 == io_tokIn_payload_tag_lnid);
  assign _zz_1 = ({15'd0,1'b1} <<< io_viewWr_idx);
  assign _zz_2 = ({15'd0,1'b1} <<< io_viewWr_idx);
  assign viewHit = (((((((_zz_viewHit || _zz_viewHit_4) || (viewValid_10 && _zz_viewHit_5)) || (viewValid_11 && (viewName_11 == io_tokIn_payload_tag_lnid))) || (viewValid_12 && (viewName_12 == io_tokIn_payload_tag_lnid))) || (viewValid_13 && (viewName_13 == io_tokIn_payload_tag_lnid))) || (viewValid_14 && (viewName_14 == io_tokIn_payload_tag_lnid))) || (viewValid_15 && (viewName_15 == io_tokIn_payload_tag_lnid)));
  assign missLnid = (! viewHit);
  assign missLbid = ((io_tokIn_payload_srcKind == 4'b0001) && (! bankPresent[io_tokIn_payload_lbid]));
  assign anyMiss = (missLnid || missLbid);
  assign faultFire = (io_tokIn_valid && anyMiss);
  assign io_tokOut_valid = io_tokIn_valid;
  assign io_tokOut_payload_tag_wave = io_tokIn_payload_tag_wave;
  assign io_tokOut_payload_tag_thread = io_tokIn_payload_tag_thread;
  assign io_tokOut_payload_tag_lnid = io_tokIn_payload_tag_lnid;
  assign io_tokOut_payload_tag_precision = io_tokIn_payload_tag_precision;
  assign io_tokOut_payload_tag_dim = io_tokIn_payload_tag_dim;
  assign io_tokOut_payload_lbid = io_tokIn_payload_lbid;
  assign io_tokOut_payload_srcKind = io_tokIn_payload_srcKind;
  assign io_faultFire = faultFire;
  assign io_fault = _zz_io_fault;
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      viewValid_0 <= 1'b0;
      viewValid_1 <= 1'b0;
      viewValid_2 <= 1'b0;
      viewValid_3 <= 1'b0;
      viewValid_4 <= 1'b0;
      viewValid_5 <= 1'b0;
      viewValid_6 <= 1'b0;
      viewValid_7 <= 1'b0;
      viewValid_8 <= 1'b0;
      viewValid_9 <= 1'b0;
      viewValid_10 <= 1'b0;
      viewValid_11 <= 1'b0;
      viewValid_12 <= 1'b0;
      viewValid_13 <= 1'b0;
      viewValid_14 <= 1'b0;
      viewValid_15 <= 1'b0;
      viewName_0 <= 16'h0;
      viewName_1 <= 16'h0;
      viewName_2 <= 16'h0;
      viewName_3 <= 16'h0;
      viewName_4 <= 16'h0;
      viewName_5 <= 16'h0;
      viewName_6 <= 16'h0;
      viewName_7 <= 16'h0;
      viewName_8 <= 16'h0;
      viewName_9 <= 16'h0;
      viewName_10 <= 16'h0;
      viewName_11 <= 16'h0;
      viewName_12 <= 16'h0;
      viewName_13 <= 16'h0;
      viewName_14 <= 16'h0;
      viewName_15 <= 16'h0;
      bankPresent <= 256'h0;
      _zz_io_fault <= 1'b0;
    end else begin
      if(io_viewWr_valid) begin
        if(_zz_1[0]) begin
          viewValid_0 <= io_viewWr_en;
        end
        if(_zz_1[1]) begin
          viewValid_1 <= io_viewWr_en;
        end
        if(_zz_1[2]) begin
          viewValid_2 <= io_viewWr_en;
        end
        if(_zz_1[3]) begin
          viewValid_3 <= io_viewWr_en;
        end
        if(_zz_1[4]) begin
          viewValid_4 <= io_viewWr_en;
        end
        if(_zz_1[5]) begin
          viewValid_5 <= io_viewWr_en;
        end
        if(_zz_1[6]) begin
          viewValid_6 <= io_viewWr_en;
        end
        if(_zz_1[7]) begin
          viewValid_7 <= io_viewWr_en;
        end
        if(_zz_1[8]) begin
          viewValid_8 <= io_viewWr_en;
        end
        if(_zz_1[9]) begin
          viewValid_9 <= io_viewWr_en;
        end
        if(_zz_1[10]) begin
          viewValid_10 <= io_viewWr_en;
        end
        if(_zz_1[11]) begin
          viewValid_11 <= io_viewWr_en;
        end
        if(_zz_1[12]) begin
          viewValid_12 <= io_viewWr_en;
        end
        if(_zz_1[13]) begin
          viewValid_13 <= io_viewWr_en;
        end
        if(_zz_1[14]) begin
          viewValid_14 <= io_viewWr_en;
        end
        if(_zz_1[15]) begin
          viewValid_15 <= io_viewWr_en;
        end
        if(_zz_2[0]) begin
          viewName_0 <= io_viewWr_lnid;
        end
        if(_zz_2[1]) begin
          viewName_1 <= io_viewWr_lnid;
        end
        if(_zz_2[2]) begin
          viewName_2 <= io_viewWr_lnid;
        end
        if(_zz_2[3]) begin
          viewName_3 <= io_viewWr_lnid;
        end
        if(_zz_2[4]) begin
          viewName_4 <= io_viewWr_lnid;
        end
        if(_zz_2[5]) begin
          viewName_5 <= io_viewWr_lnid;
        end
        if(_zz_2[6]) begin
          viewName_6 <= io_viewWr_lnid;
        end
        if(_zz_2[7]) begin
          viewName_7 <= io_viewWr_lnid;
        end
        if(_zz_2[8]) begin
          viewName_8 <= io_viewWr_lnid;
        end
        if(_zz_2[9]) begin
          viewName_9 <= io_viewWr_lnid;
        end
        if(_zz_2[10]) begin
          viewName_10 <= io_viewWr_lnid;
        end
        if(_zz_2[11]) begin
          viewName_11 <= io_viewWr_lnid;
        end
        if(_zz_2[12]) begin
          viewName_12 <= io_viewWr_lnid;
        end
        if(_zz_2[13]) begin
          viewName_13 <= io_viewWr_lnid;
        end
        if(_zz_2[14]) begin
          viewName_14 <= io_viewWr_lnid;
        end
        if(_zz_2[15]) begin
          viewName_15 <= io_viewWr_lnid;
        end
      end
      if(io_bankWr_valid) begin
        bankPresent[io_bankWr_lbid] <= io_bankWr_mapped;
      end
      if(io_faultClear) begin
        _zz_io_fault <= 1'b0;
      end
      if(faultFire) begin
        _zz_io_fault <= 1'b1;
      end
    end
  end


endmodule
