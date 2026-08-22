// Generator : SpinalHDL v1.14.2    git head : 78f29dc66110fc099a777992b6daa2f803ab445e
// Component : FabricMerge
// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
// 
// === 생성물이다. 손으로 고치지 말 것. ===
// 고칠 곳은 rtl/spinal/ 의 생성기이고, 고친 뒤 `make rtl-gen` 으로 다시 낸다.
// 여기 직접 쓴 수정은 다음 생성에서 조용히 사라진다.

`timescale 1ns/1ps

module FabricMerge (
  output wire          io_fault,
  input  wire          io_faultClear,
  input  wire          io_push_0_strb,
  input  wire [31:0]   io_push_0_result_head_tag_wave,
  input  wire [15:0]   io_push_0_result_head_tag_thread,
  input  wire [15:0]   io_push_0_result_head_tag_lnid,
  input  wire [7:0]    io_push_0_result_head_tag_precision,
  input  wire [7:0]    io_push_0_result_head_tag_dim,
  input  wire [7:0]    io_push_0_result_head_seq,
  input  wire [7:0]    io_push_0_result_head_total,
  input  wire          io_push_0_result_head_last,
  input  wire [63:0]   io_push_0_result_body,
  output wire          io_push_0_stall,
  input  wire          io_push_1_strb,
  input  wire [31:0]   io_push_1_result_head_tag_wave,
  input  wire [15:0]   io_push_1_result_head_tag_thread,
  input  wire [15:0]   io_push_1_result_head_tag_lnid,
  input  wire [7:0]    io_push_1_result_head_tag_precision,
  input  wire [7:0]    io_push_1_result_head_tag_dim,
  input  wire [7:0]    io_push_1_result_head_seq,
  input  wire [7:0]    io_push_1_result_head_total,
  input  wire          io_push_1_result_head_last,
  input  wire [63:0]   io_push_1_result_body,
  output wire          io_push_1_stall,
  input  wire          io_push_2_strb,
  input  wire [31:0]   io_push_2_result_head_tag_wave,
  input  wire [15:0]   io_push_2_result_head_tag_thread,
  input  wire [15:0]   io_push_2_result_head_tag_lnid,
  input  wire [7:0]    io_push_2_result_head_tag_precision,
  input  wire [7:0]    io_push_2_result_head_tag_dim,
  input  wire [7:0]    io_push_2_result_head_seq,
  input  wire [7:0]    io_push_2_result_head_total,
  input  wire          io_push_2_result_head_last,
  input  wire [63:0]   io_push_2_result_body,
  output wire          io_push_2_stall,
  input  wire          io_push_3_strb,
  input  wire [31:0]   io_push_3_result_head_tag_wave,
  input  wire [15:0]   io_push_3_result_head_tag_thread,
  input  wire [15:0]   io_push_3_result_head_tag_lnid,
  input  wire [7:0]    io_push_3_result_head_tag_precision,
  input  wire [7:0]    io_push_3_result_head_tag_dim,
  input  wire [7:0]    io_push_3_result_head_seq,
  input  wire [7:0]    io_push_3_result_head_total,
  input  wire          io_push_3_result_head_last,
  input  wire [63:0]   io_push_3_result_body,
  output wire          io_push_3_stall,
  output wire          io_consumer_valid,
  input  wire          io_consumer_ready,
  output wire [31:0]   io_consumer_payload_head_tag_wave,
  output wire [15:0]   io_consumer_payload_head_tag_thread,
  output wire [15:0]   io_consumer_payload_head_tag_lnid,
  output wire [7:0]    io_consumer_payload_head_tag_precision,
  output wire [7:0]    io_consumer_payload_head_tag_dim,
  output wire [7:0]    io_consumer_payload_head_seq,
  output wire [7:0]    io_consumer_payload_head_total,
  output wire          io_consumer_payload_head_last,
  output wire [63:0]   io_consumer_payload_body,
  input  wire          clk,
  input  wire          reset
);

  wire       [0:0]    _zz_lanes_0_wIdx;
  wire       [0:0]    _zz_lanes_1_wIdx;
  wire       [0:0]    _zz_lanes_2_wIdx;
  wire       [0:0]    _zz_lanes_3_wIdx;
  wire       [7:0]    _zz__zz_select_rrOh_2;
  wire       [7:0]    _zz__zz_select_rrOh_2_1;
  wire       [3:0]    _zz__zz_select_rrOh_2_2;
  reg        [31:0]   lanes_0_slots_0_head_tag_wave;
  reg        [15:0]   lanes_0_slots_0_head_tag_thread;
  reg        [15:0]   lanes_0_slots_0_head_tag_lnid;
  reg        [7:0]    lanes_0_slots_0_head_tag_precision;
  reg        [7:0]    lanes_0_slots_0_head_tag_dim;
  reg        [7:0]    lanes_0_slots_0_head_seq;
  reg        [7:0]    lanes_0_slots_0_head_total;
  reg                 lanes_0_slots_0_head_last;
  reg        [63:0]   lanes_0_slots_0_body;
  reg        [0:0]    lanes_0_cnt;
  wire                lanes_0_full;
  wire                lanes_0_vld;
  wire                lanes_0_doPush;
  wire                lanes_0_shove;
  wire                lanes_0_doPop;
  wire       [0:0]    lanes_0_wIdx;
  wire                when_FabricMerge_l128;
  wire                when_FabricMerge_l133;
  wire                when_FabricMerge_l134;
  reg        [31:0]   lanes_1_slots_0_head_tag_wave;
  reg        [15:0]   lanes_1_slots_0_head_tag_thread;
  reg        [15:0]   lanes_1_slots_0_head_tag_lnid;
  reg        [7:0]    lanes_1_slots_0_head_tag_precision;
  reg        [7:0]    lanes_1_slots_0_head_tag_dim;
  reg        [7:0]    lanes_1_slots_0_head_seq;
  reg        [7:0]    lanes_1_slots_0_head_total;
  reg                 lanes_1_slots_0_head_last;
  reg        [63:0]   lanes_1_slots_0_body;
  reg        [0:0]    lanes_1_cnt;
  wire                lanes_1_full;
  wire                lanes_1_vld;
  wire                lanes_1_doPush;
  wire                lanes_1_shove;
  wire                lanes_1_doPop;
  wire       [0:0]    lanes_1_wIdx;
  wire                when_FabricMerge_l128_1;
  wire                when_FabricMerge_l133_1;
  wire                when_FabricMerge_l134_1;
  reg        [31:0]   lanes_2_slots_0_head_tag_wave;
  reg        [15:0]   lanes_2_slots_0_head_tag_thread;
  reg        [15:0]   lanes_2_slots_0_head_tag_lnid;
  reg        [7:0]    lanes_2_slots_0_head_tag_precision;
  reg        [7:0]    lanes_2_slots_0_head_tag_dim;
  reg        [7:0]    lanes_2_slots_0_head_seq;
  reg        [7:0]    lanes_2_slots_0_head_total;
  reg                 lanes_2_slots_0_head_last;
  reg        [63:0]   lanes_2_slots_0_body;
  reg        [0:0]    lanes_2_cnt;
  wire                lanes_2_full;
  wire                lanes_2_vld;
  wire                lanes_2_doPush;
  wire                lanes_2_shove;
  wire                lanes_2_doPop;
  wire       [0:0]    lanes_2_wIdx;
  wire                when_FabricMerge_l128_2;
  wire                when_FabricMerge_l133_2;
  wire                when_FabricMerge_l134_2;
  reg        [31:0]   lanes_3_slots_0_head_tag_wave;
  reg        [15:0]   lanes_3_slots_0_head_tag_thread;
  reg        [15:0]   lanes_3_slots_0_head_tag_lnid;
  reg        [7:0]    lanes_3_slots_0_head_tag_precision;
  reg        [7:0]    lanes_3_slots_0_head_tag_dim;
  reg        [7:0]    lanes_3_slots_0_head_seq;
  reg        [7:0]    lanes_3_slots_0_head_total;
  reg                 lanes_3_slots_0_head_last;
  reg        [63:0]   lanes_3_slots_0_body;
  reg        [0:0]    lanes_3_cnt;
  wire                lanes_3_full;
  wire                lanes_3_vld;
  wire                lanes_3_doPush;
  wire                lanes_3_shove;
  wire                lanes_3_doPop;
  wire       [0:0]    lanes_3_wIdx;
  wire                when_FabricMerge_l128_3;
  wire                when_FabricMerge_l133_3;
  wire                when_FabricMerge_l134_3;
  reg        [3:0]    select_req;
  reg        [3:0]    select_ptrOh;
  wire       [3:0]    _zz_select_rrOh;
  wire       [7:0]    _zz_select_rrOh_1;
  wire       [7:0]    _zz_select_rrOh_2;
  wire       [3:0]    select_rrOh;
  reg                 select_locked;
  reg        [3:0]    select_lockedOh;
  wire       [3:0]    select_selOh;
  wire       [3:0]    select_drive;
  wire                when_FabricMerge_l170;
  wire                io_consumer_fire;
  wire       [160:0]  merge_contribs_0;
  wire       [160:0]  merge_contribs_1;
  wire       [160:0]  merge_contribs_2;
  wire       [160:0]  merge_contribs_3;
  wire       [160:0]  merge_merged;
  wire       [96:0]   _zz_io_consumer_payload_head_seq;
  wire       [79:0]   _zz_io_consumer_payload_head_tag_wave;
  wire                shoveAny;
  reg                 _zz_io_fault;

  assign _zz_lanes_0_wIdx = (lanes_0_cnt - 1'b1);
  assign _zz_lanes_1_wIdx = (lanes_1_cnt - 1'b1);
  assign _zz_lanes_2_wIdx = (lanes_2_cnt - 1'b1);
  assign _zz_lanes_3_wIdx = (lanes_3_cnt - 1'b1);
  assign _zz__zz_select_rrOh_2 = (_zz_select_rrOh_1 - _zz__zz_select_rrOh_2_1);
  assign _zz__zz_select_rrOh_2_2 = select_ptrOh;
  assign _zz__zz_select_rrOh_2_1 = {4'd0, _zz__zz_select_rrOh_2_2};
  assign lanes_0_full = (lanes_0_cnt == 1'b1);
  assign lanes_0_vld = (lanes_0_cnt != 1'b0);
  assign io_push_0_stall = lanes_0_full;
  assign lanes_0_doPush = (io_push_0_strb && (! lanes_0_full));
  assign lanes_0_shove = (io_push_0_strb && lanes_0_full);
  assign lanes_0_wIdx = (lanes_0_doPop ? _zz_lanes_0_wIdx : lanes_0_cnt);
  assign when_FabricMerge_l128 = (lanes_0_wIdx == 1'b0);
  assign when_FabricMerge_l133 = (lanes_0_doPush && (! lanes_0_doPop));
  assign when_FabricMerge_l134 = ((! lanes_0_doPush) && lanes_0_doPop);
  assign lanes_1_full = (lanes_1_cnt == 1'b1);
  assign lanes_1_vld = (lanes_1_cnt != 1'b0);
  assign io_push_1_stall = lanes_1_full;
  assign lanes_1_doPush = (io_push_1_strb && (! lanes_1_full));
  assign lanes_1_shove = (io_push_1_strb && lanes_1_full);
  assign lanes_1_wIdx = (lanes_1_doPop ? _zz_lanes_1_wIdx : lanes_1_cnt);
  assign when_FabricMerge_l128_1 = (lanes_1_wIdx == 1'b0);
  assign when_FabricMerge_l133_1 = (lanes_1_doPush && (! lanes_1_doPop));
  assign when_FabricMerge_l134_1 = ((! lanes_1_doPush) && lanes_1_doPop);
  assign lanes_2_full = (lanes_2_cnt == 1'b1);
  assign lanes_2_vld = (lanes_2_cnt != 1'b0);
  assign io_push_2_stall = lanes_2_full;
  assign lanes_2_doPush = (io_push_2_strb && (! lanes_2_full));
  assign lanes_2_shove = (io_push_2_strb && lanes_2_full);
  assign lanes_2_wIdx = (lanes_2_doPop ? _zz_lanes_2_wIdx : lanes_2_cnt);
  assign when_FabricMerge_l128_2 = (lanes_2_wIdx == 1'b0);
  assign when_FabricMerge_l133_2 = (lanes_2_doPush && (! lanes_2_doPop));
  assign when_FabricMerge_l134_2 = ((! lanes_2_doPush) && lanes_2_doPop);
  assign lanes_3_full = (lanes_3_cnt == 1'b1);
  assign lanes_3_vld = (lanes_3_cnt != 1'b0);
  assign io_push_3_stall = lanes_3_full;
  assign lanes_3_doPush = (io_push_3_strb && (! lanes_3_full));
  assign lanes_3_shove = (io_push_3_strb && lanes_3_full);
  assign lanes_3_wIdx = (lanes_3_doPop ? _zz_lanes_3_wIdx : lanes_3_cnt);
  assign when_FabricMerge_l128_3 = (lanes_3_wIdx == 1'b0);
  assign when_FabricMerge_l133_3 = (lanes_3_doPush && (! lanes_3_doPop));
  assign when_FabricMerge_l134_3 = ((! lanes_3_doPush) && lanes_3_doPop);
  always @(*) begin
    select_req[0] = lanes_0_vld;
    select_req[1] = lanes_1_vld;
    select_req[2] = lanes_2_vld;
    select_req[3] = lanes_3_vld;
  end

  assign _zz_select_rrOh = select_req;
  assign _zz_select_rrOh_1 = {_zz_select_rrOh,_zz_select_rrOh};
  assign _zz_select_rrOh_2 = (_zz_select_rrOh_1 & (~ _zz__zz_select_rrOh_2));
  assign select_rrOh = (_zz_select_rrOh_2[7 : 4] | _zz_select_rrOh_2[3 : 0]);
  assign select_selOh = (select_locked ? select_lockedOh : select_rrOh);
  assign select_drive = (select_selOh & select_req);
  assign when_FabricMerge_l170 = (io_consumer_valid && (! io_consumer_ready));
  assign io_consumer_fire = (io_consumer_valid && io_consumer_ready);
  assign merge_contribs_0 = (select_drive[0] ? {lanes_0_slots_0_body,{lanes_0_slots_0_head_last,{lanes_0_slots_0_head_total,{lanes_0_slots_0_head_seq,{lanes_0_slots_0_head_tag_dim,{lanes_0_slots_0_head_tag_precision,{lanes_0_slots_0_head_tag_lnid,{lanes_0_slots_0_head_tag_thread,lanes_0_slots_0_head_tag_wave}}}}}}}} : 161'h0);
  assign merge_contribs_1 = (select_drive[1] ? {lanes_1_slots_0_body,{lanes_1_slots_0_head_last,{lanes_1_slots_0_head_total,{lanes_1_slots_0_head_seq,{lanes_1_slots_0_head_tag_dim,{lanes_1_slots_0_head_tag_precision,{lanes_1_slots_0_head_tag_lnid,{lanes_1_slots_0_head_tag_thread,lanes_1_slots_0_head_tag_wave}}}}}}}} : 161'h0);
  assign merge_contribs_2 = (select_drive[2] ? {lanes_2_slots_0_body,{lanes_2_slots_0_head_last,{lanes_2_slots_0_head_total,{lanes_2_slots_0_head_seq,{lanes_2_slots_0_head_tag_dim,{lanes_2_slots_0_head_tag_precision,{lanes_2_slots_0_head_tag_lnid,{lanes_2_slots_0_head_tag_thread,lanes_2_slots_0_head_tag_wave}}}}}}}} : 161'h0);
  assign merge_contribs_3 = (select_drive[3] ? {lanes_3_slots_0_body,{lanes_3_slots_0_head_last,{lanes_3_slots_0_head_total,{lanes_3_slots_0_head_seq,{lanes_3_slots_0_head_tag_dim,{lanes_3_slots_0_head_tag_precision,{lanes_3_slots_0_head_tag_lnid,{lanes_3_slots_0_head_tag_thread,lanes_3_slots_0_head_tag_wave}}}}}}}} : 161'h0);
  assign merge_merged = (((merge_contribs_0 | merge_contribs_1) | merge_contribs_2) | merge_contribs_3);
  assign io_consumer_valid = (|select_drive);
  assign _zz_io_consumer_payload_head_seq = merge_merged[96 : 0];
  assign _zz_io_consumer_payload_head_tag_wave = _zz_io_consumer_payload_head_seq[79 : 0];
  assign io_consumer_payload_head_tag_wave = _zz_io_consumer_payload_head_tag_wave[31 : 0];
  assign io_consumer_payload_head_tag_thread = _zz_io_consumer_payload_head_tag_wave[47 : 32];
  assign io_consumer_payload_head_tag_lnid = _zz_io_consumer_payload_head_tag_wave[63 : 48];
  assign io_consumer_payload_head_tag_precision = _zz_io_consumer_payload_head_tag_wave[71 : 64];
  assign io_consumer_payload_head_tag_dim = _zz_io_consumer_payload_head_tag_wave[79 : 72];
  assign io_consumer_payload_head_seq = _zz_io_consumer_payload_head_seq[87 : 80];
  assign io_consumer_payload_head_total = _zz_io_consumer_payload_head_seq[95 : 88];
  assign io_consumer_payload_head_last = _zz_io_consumer_payload_head_seq[96];
  assign io_consumer_payload_body = merge_merged[160 : 97];
  assign lanes_0_doPop = (select_drive[0] && io_consumer_fire);
  assign lanes_1_doPop = (select_drive[1] && io_consumer_fire);
  assign lanes_2_doPop = (select_drive[2] && io_consumer_fire);
  assign lanes_3_doPop = (select_drive[3] && io_consumer_fire);
  assign shoveAny = (((lanes_0_shove || lanes_1_shove) || lanes_2_shove) || lanes_3_shove);
  assign io_fault = _zz_io_fault;
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      lanes_0_cnt <= 1'b0;
      lanes_1_cnt <= 1'b0;
      lanes_2_cnt <= 1'b0;
      lanes_3_cnt <= 1'b0;
      select_ptrOh <= 4'b0001;
      select_locked <= 1'b0;
      select_lockedOh <= 4'b0000;
      _zz_io_fault <= 1'b0;
    end else begin
      if(when_FabricMerge_l133) begin
        lanes_0_cnt <= (lanes_0_cnt + 1'b1);
      end else begin
        if(when_FabricMerge_l134) begin
          lanes_0_cnt <= (lanes_0_cnt - 1'b1);
        end
      end
      if(when_FabricMerge_l133_1) begin
        lanes_1_cnt <= (lanes_1_cnt + 1'b1);
      end else begin
        if(when_FabricMerge_l134_1) begin
          lanes_1_cnt <= (lanes_1_cnt - 1'b1);
        end
      end
      if(when_FabricMerge_l133_2) begin
        lanes_2_cnt <= (lanes_2_cnt + 1'b1);
      end else begin
        if(when_FabricMerge_l134_2) begin
          lanes_2_cnt <= (lanes_2_cnt - 1'b1);
        end
      end
      if(when_FabricMerge_l133_3) begin
        lanes_3_cnt <= (lanes_3_cnt + 1'b1);
      end else begin
        if(when_FabricMerge_l134_3) begin
          lanes_3_cnt <= (lanes_3_cnt - 1'b1);
        end
      end
      if(when_FabricMerge_l170) begin
        select_locked <= 1'b1;
        select_lockedOh <= select_selOh;
      end else begin
        select_locked <= 1'b0;
      end
      if(io_consumer_fire) begin
        select_ptrOh <= {select_selOh[2 : 0],select_selOh[3 : 3]};
      end
      if(io_faultClear) begin
        _zz_io_fault <= 1'b0;
      end
      if(shoveAny) begin
        _zz_io_fault <= 1'b1;
      end
    end
  end

  always @(posedge clk) begin
    if(lanes_0_doPush) begin
      if(when_FabricMerge_l128) begin
        lanes_0_slots_0_head_tag_wave <= io_push_0_result_head_tag_wave;
        lanes_0_slots_0_head_tag_thread <= io_push_0_result_head_tag_thread;
        lanes_0_slots_0_head_tag_lnid <= io_push_0_result_head_tag_lnid;
        lanes_0_slots_0_head_tag_precision <= io_push_0_result_head_tag_precision;
        lanes_0_slots_0_head_tag_dim <= io_push_0_result_head_tag_dim;
        lanes_0_slots_0_head_seq <= io_push_0_result_head_seq;
        lanes_0_slots_0_head_total <= io_push_0_result_head_total;
        lanes_0_slots_0_head_last <= io_push_0_result_head_last;
        lanes_0_slots_0_body <= io_push_0_result_body;
      end
    end
    if(lanes_1_doPush) begin
      if(when_FabricMerge_l128_1) begin
        lanes_1_slots_0_head_tag_wave <= io_push_1_result_head_tag_wave;
        lanes_1_slots_0_head_tag_thread <= io_push_1_result_head_tag_thread;
        lanes_1_slots_0_head_tag_lnid <= io_push_1_result_head_tag_lnid;
        lanes_1_slots_0_head_tag_precision <= io_push_1_result_head_tag_precision;
        lanes_1_slots_0_head_tag_dim <= io_push_1_result_head_tag_dim;
        lanes_1_slots_0_head_seq <= io_push_1_result_head_seq;
        lanes_1_slots_0_head_total <= io_push_1_result_head_total;
        lanes_1_slots_0_head_last <= io_push_1_result_head_last;
        lanes_1_slots_0_body <= io_push_1_result_body;
      end
    end
    if(lanes_2_doPush) begin
      if(when_FabricMerge_l128_2) begin
        lanes_2_slots_0_head_tag_wave <= io_push_2_result_head_tag_wave;
        lanes_2_slots_0_head_tag_thread <= io_push_2_result_head_tag_thread;
        lanes_2_slots_0_head_tag_lnid <= io_push_2_result_head_tag_lnid;
        lanes_2_slots_0_head_tag_precision <= io_push_2_result_head_tag_precision;
        lanes_2_slots_0_head_tag_dim <= io_push_2_result_head_tag_dim;
        lanes_2_slots_0_head_seq <= io_push_2_result_head_seq;
        lanes_2_slots_0_head_total <= io_push_2_result_head_total;
        lanes_2_slots_0_head_last <= io_push_2_result_head_last;
        lanes_2_slots_0_body <= io_push_2_result_body;
      end
    end
    if(lanes_3_doPush) begin
      if(when_FabricMerge_l128_3) begin
        lanes_3_slots_0_head_tag_wave <= io_push_3_result_head_tag_wave;
        lanes_3_slots_0_head_tag_thread <= io_push_3_result_head_tag_thread;
        lanes_3_slots_0_head_tag_lnid <= io_push_3_result_head_tag_lnid;
        lanes_3_slots_0_head_tag_precision <= io_push_3_result_head_tag_precision;
        lanes_3_slots_0_head_tag_dim <= io_push_3_result_head_tag_dim;
        lanes_3_slots_0_head_seq <= io_push_3_result_head_seq;
        lanes_3_slots_0_head_total <= io_push_3_result_head_total;
        lanes_3_slots_0_head_last <= io_push_3_result_head_last;
        lanes_3_slots_0_body <= io_push_3_result_body;
      end
    end
  end


endmodule
