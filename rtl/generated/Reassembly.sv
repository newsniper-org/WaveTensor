// Generator : SpinalHDL v1.14.2    git head : 78f29dc66110fc099a777992b6daa2f803ab445e
// Component : Reassembly
// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
// 
// === 생성물이다. 손으로 고치지 말 것. ===
// 고칠 곳은 rtl/spinal/ 의 생성기이고, 고친 뒤 `make rtl-gen` 으로 다시 낸다.
// 여기 직접 쓴 수정은 다음 생성에서 조용히 사라진다.

`timescale 1ns/1ps

module Reassembly (
  input  wire          io_open_valid,
  input  wire [31:0]   io_open_tag_wave,
  input  wire [15:0]   io_open_tag_thread,
  input  wire [15:0]   io_open_tag_lnid,
  input  wire [7:0]    io_open_tag_precision,
  input  wire [7:0]    io_open_tag_dim,
  input  wire [7:0]    io_open_base,
  output wire          io_open_granted,
  input  wire          io_frag_valid,
  input  wire [31:0]   io_frag_head_tag_wave,
  input  wire [15:0]   io_frag_head_tag_thread,
  input  wire [15:0]   io_frag_head_tag_lnid,
  input  wire [7:0]    io_frag_head_tag_precision,
  input  wire [7:0]    io_frag_head_tag_dim,
  input  wire [7:0]    io_frag_head_seq,
  input  wire [7:0]    io_frag_head_total,
  input  wire          io_frag_head_last,
  input  wire [63:0]   io_frag_body,
  output wire          io_wr_valid,
  output wire [7:0]    io_wr_base,
  output wire [3:0]    io_wr_off,
  output wire [63:0]   io_wr_body,
  output wire          io_deliver_valid,
  input  wire          io_deliver_ready,
  output wire [31:0]   io_deliver_payload_tag_wave,
  output wire [15:0]   io_deliver_payload_tag_thread,
  output wire [15:0]   io_deliver_payload_tag_lnid,
  output wire [7:0]    io_deliver_payload_tag_precision,
  output wire [7:0]    io_deliver_payload_tag_dim,
  output wire [7:0]    io_deliver_payload_base,
  output wire [7:0]    io_deliver_payload_total,
  output wire [2:0]    io_incomplete,
  input  wire          io_abort_valid,
  input  wire [31:0]   io_abort_tag_wave,
  input  wire [15:0]   io_abort_tag_thread,
  input  wire [15:0]   io_abort_tag_lnid,
  input  wire [7:0]    io_abort_tag_precision,
  input  wire [7:0]    io_abort_tag_dim,
  output wire [7:0]    io_abortCount,
  output wire          io_fault,
  input  wire          io_faultClear,
  output wire          io_capAbsent,
  input  wire          io_capAbsentClear,
  input  wire          clk,
  input  wire          reset
);

  reg        [7:0]    _zz_fr_cBase_3;
  reg        [7:0]    _zz_fr_cTotal;
  reg                 _zz_fr_cKnown;
  reg        [15:0]   _zz_fr_cSeen;
  wire       [3:0]    _zz_fr_off;
  reg        [15:0]   _zz_fr_endBad;
  wire       [4:0]    _zz_fr_endBad_1;
  wire                _zz_op_clash;
  wire                _zz_op_clash_1;
  wire                _zz_op_clash_2;
  wire                _zz_op_clash_3;
  wire                _zz_op_clash_4;
  wire                _zz_op_clash_5;
  wire                _zz_op_clash_6;
  wire                _zz_op_clash_7;
  wire                _zz_op_clash_8;
  wire                _zz_op_clash_9;
  wire                _zz_op_clash_10;
  wire                _zz_op_clash_11;
  wire       [3:0]    _zz_op_freeOh_1;
  reg        [15:0]   _zz_dv_done_0;
  wire       [4:0]    _zz_dv_done_0_1;
  reg        [15:0]   _zz_dv_done_1;
  wire       [4:0]    _zz_dv_done_1_1;
  reg        [15:0]   _zz_dv_done_2;
  wire       [4:0]    _zz_dv_done_2_1;
  reg        [15:0]   _zz_dv_done_3;
  wire       [4:0]    _zz_dv_done_3_1;
  wire       [3:0]    _zz_dv_grantOh_1;
  reg        [31:0]   _zz_io_deliver_payload_tag_wave_4;
  reg        [15:0]   _zz_io_deliver_payload_tag_thread;
  reg        [15:0]   _zz_io_deliver_payload_tag_lnid;
  reg        [7:0]    _zz_io_deliver_payload_tag_precision;
  reg        [7:0]    _zz_io_deliver_payload_tag_dim;
  reg        [7:0]    _zz_io_deliver_payload_base;
  reg        [7:0]    _zz_io_deliver_payload_total;
  reg        [2:0]    _zz_io_incomplete_8;
  wire       [2:0]    _zz_io_incomplete_9;
  reg        [2:0]    _zz_io_incomplete_10;
  wire       [2:0]    _zz_io_incomplete_11;
  wire       [0:0]    _zz_io_incomplete_12;
  reg                 ctx_0_active;
  reg        [31:0]   ctx_0_tag_wave;
  reg        [15:0]   ctx_0_tag_thread;
  reg        [15:0]   ctx_0_tag_lnid;
  reg        [7:0]    ctx_0_tag_precision;
  reg        [7:0]    ctx_0_tag_dim;
  reg        [7:0]    ctx_0_base;
  reg        [7:0]    ctx_0_total;
  reg                 ctx_0_totalKnown;
  reg        [15:0]   ctx_0_seen;
  reg                 ctx_0_last;
  reg                 ctx_1_active;
  reg        [31:0]   ctx_1_tag_wave;
  reg        [15:0]   ctx_1_tag_thread;
  reg        [15:0]   ctx_1_tag_lnid;
  reg        [7:0]    ctx_1_tag_precision;
  reg        [7:0]    ctx_1_tag_dim;
  reg        [7:0]    ctx_1_base;
  reg        [7:0]    ctx_1_total;
  reg                 ctx_1_totalKnown;
  reg        [15:0]   ctx_1_seen;
  reg                 ctx_1_last;
  reg                 ctx_2_active;
  reg        [31:0]   ctx_2_tag_wave;
  reg        [15:0]   ctx_2_tag_thread;
  reg        [15:0]   ctx_2_tag_lnid;
  reg        [7:0]    ctx_2_tag_precision;
  reg        [7:0]    ctx_2_tag_dim;
  reg        [7:0]    ctx_2_base;
  reg        [7:0]    ctx_2_total;
  reg                 ctx_2_totalKnown;
  reg        [15:0]   ctx_2_seen;
  reg                 ctx_2_last;
  reg                 ctx_3_active;
  reg        [31:0]   ctx_3_tag_wave;
  reg        [15:0]   ctx_3_tag_thread;
  reg        [15:0]   ctx_3_tag_lnid;
  reg        [7:0]    ctx_3_tag_precision;
  reg        [7:0]    ctx_3_tag_dim;
  reg        [7:0]    ctx_3_base;
  reg        [7:0]    ctx_3_total;
  reg                 ctx_3_totalKnown;
  reg        [15:0]   ctx_3_seen;
  reg                 ctx_3_last;
  wire       [15:0]   fullMask_0;
  wire       [15:0]   fullMask_1;
  wire       [15:0]   fullMask_2;
  wire       [15:0]   fullMask_3;
  wire       [15:0]   fullMask_4;
  wire       [15:0]   fullMask_5;
  wire       [15:0]   fullMask_6;
  wire       [15:0]   fullMask_7;
  wire       [15:0]   fullMask_8;
  wire       [15:0]   fullMask_9;
  wire       [15:0]   fullMask_10;
  wire       [15:0]   fullMask_11;
  wire       [15:0]   fullMask_12;
  wire       [15:0]   fullMask_13;
  wire       [15:0]   fullMask_14;
  wire       [15:0]   fullMask_15;
  wire       [15:0]   fullMask_16;
  wire                fr_hit_0;
  wire                fr_hit_1;
  wire                fr_hit_2;
  wire                fr_hit_3;
  wire                fr_hitAny;
  wire                _zz_fr_cBase;
  wire                _zz_fr_cBase_1;
  wire       [1:0]    _zz_fr_cBase_2;
  wire       [7:0]    fr_cBase;
  wire       [7:0]    fr_cTotal;
  wire                fr_cKnown;
  wire       [15:0]   fr_cSeen;
  wire       [7:0]    fr_effTotal;
  wire                fr_capaRej;
  wire                fr_strayRej;
  wire                fr_totBad;
  wire                fr_overRej;
  wire       [3:0]    fr_off;
  wire       [15:0]   fr_ohSeq;
  wire                fr_dupRej;
  wire                fr_accept;
  wire       [15:0]   fr_newSeen;
  wire                fr_endBad;
  wire                when_Reassembly_l297;
  wire                when_Reassembly_l297_1;
  wire                when_Reassembly_l297_2;
  wire                when_Reassembly_l297_3;
  wire                fr_rejEvt;
  wire                fr_endEvt;
  wire                fr_capaEvt;
  wire                op_clash;
  wire                op_free_0;
  wire                op_free_1;
  wire                op_free_2;
  wire                op_free_3;
  wire                op_freeAny;
  wire       [3:0]    _zz_op_freeOh;
  wire       [3:0]    op_freeOh;
  wire                op_grant;
  wire                when_Reassembly_l330;
  wire                when_Reassembly_l330_1;
  wire                when_Reassembly_l330_2;
  wire                when_Reassembly_l330_3;
  wire                op_clashEvt;
  wire                dv_done_0;
  wire                dv_done_1;
  wire                dv_done_2;
  wire                dv_done_3;
  wire                dv_doneAny;
  wire       [3:0]    _zz_dv_grantOh;
  wire       [3:0]    dv_grantOh;
  wire                _zz_io_deliver_payload_tag_wave;
  wire                _zz_io_deliver_payload_tag_wave_1;
  wire                _zz_io_deliver_payload_tag_wave_2;
  wire       [1:0]    _zz_io_deliver_payload_tag_wave_3;
  wire                io_deliver_fire;
  wire                when_Reassembly_l369;
  wire                when_Reassembly_l369_1;
  wire                when_Reassembly_l369_2;
  wire                when_Reassembly_l369_3;
  wire                ab_hit_0;
  wire                ab_hit_1;
  wire                ab_hit_2;
  wire                ab_hit_3;
  wire                ab_hitAny;
  wire                ab_fire;
  wire                when_Reassembly_l401;
  wire                when_Reassembly_l401_1;
  wire                when_Reassembly_l401_2;
  wire                when_Reassembly_l401_3;
  reg        [7:0]    ab_cnt;
  wire                when_Reassembly_l412;
  wire       [2:0]    _zz_io_incomplete;
  wire       [2:0]    _zz_io_incomplete_1;
  wire       [2:0]    _zz_io_incomplete_2;
  wire       [2:0]    _zz_io_incomplete_3;
  wire       [2:0]    _zz_io_incomplete_4;
  wire       [2:0]    _zz_io_incomplete_5;
  wire       [2:0]    _zz_io_incomplete_6;
  wire       [2:0]    _zz_io_incomplete_7;
  wire                when_Common_l141;
  reg                 _zz_io_fault;
  reg                 capBit;

  assign _zz_fr_off = io_frag_head_seq[3:0];
  assign _zz_fr_endBad_1 = fr_effTotal[4:0];
  assign _zz_op_freeOh_1 = (_zz_op_freeOh - 4'b0001);
  assign _zz_dv_done_0_1 = ctx_0_total[4:0];
  assign _zz_dv_done_1_1 = ctx_1_total[4:0];
  assign _zz_dv_done_2_1 = ctx_2_total[4:0];
  assign _zz_dv_done_3_1 = ctx_3_total[4:0];
  assign _zz_dv_grantOh_1 = (_zz_dv_grantOh - 4'b0001);
  assign _zz_io_incomplete_12 = (ctx_3_active && (! ctx_3_last));
  assign _zz_io_incomplete_11 = {2'd0, _zz_io_incomplete_12};
  assign _zz_io_incomplete_9 = {(ctx_2_active && (! ctx_2_last)),{(ctx_1_active && (! ctx_1_last)),(ctx_0_active && (! ctx_0_last))}};
  assign _zz_op_clash = (((_zz_op_clash_1 && _zz_op_clash_2) && (ctx_0_tag_lnid == io_open_tag_lnid)) && (ctx_0_tag_precision == io_open_tag_precision));
  assign _zz_op_clash_3 = (ctx_0_tag_dim == io_open_tag_dim);
  assign _zz_op_clash_4 = (((_zz_op_clash_5 && _zz_op_clash_6) && (ctx_1_tag_lnid == io_open_tag_lnid)) && (ctx_1_tag_precision == io_open_tag_precision));
  assign _zz_op_clash_7 = (ctx_1_tag_dim == io_open_tag_dim);
  assign _zz_op_clash_8 = (((ctx_2_tag_wave == io_open_tag_wave) && (ctx_2_tag_thread == io_open_tag_thread)) && (ctx_2_tag_lnid == io_open_tag_lnid));
  assign _zz_op_clash_9 = (ctx_2_tag_precision == io_open_tag_precision);
  assign _zz_op_clash_10 = ((ctx_3_tag_wave == io_open_tag_wave) && (ctx_3_tag_thread == io_open_tag_thread));
  assign _zz_op_clash_11 = (ctx_3_tag_lnid == io_open_tag_lnid);
  assign _zz_op_clash_1 = (ctx_0_tag_wave == io_open_tag_wave);
  assign _zz_op_clash_2 = (ctx_0_tag_thread == io_open_tag_thread);
  assign _zz_op_clash_5 = (ctx_1_tag_wave == io_open_tag_wave);
  assign _zz_op_clash_6 = (ctx_1_tag_thread == io_open_tag_thread);
  always @(*) begin
    case(_zz_fr_cBase_2)
      2'b00 : begin
        _zz_fr_cBase_3 = ctx_0_base;
        _zz_fr_cTotal = ctx_0_total;
        _zz_fr_cKnown = ctx_0_totalKnown;
        _zz_fr_cSeen = ctx_0_seen;
      end
      2'b01 : begin
        _zz_fr_cBase_3 = ctx_1_base;
        _zz_fr_cTotal = ctx_1_total;
        _zz_fr_cKnown = ctx_1_totalKnown;
        _zz_fr_cSeen = ctx_1_seen;
      end
      2'b10 : begin
        _zz_fr_cBase_3 = ctx_2_base;
        _zz_fr_cTotal = ctx_2_total;
        _zz_fr_cKnown = ctx_2_totalKnown;
        _zz_fr_cSeen = ctx_2_seen;
      end
      default : begin
        _zz_fr_cBase_3 = ctx_3_base;
        _zz_fr_cTotal = ctx_3_total;
        _zz_fr_cKnown = ctx_3_totalKnown;
        _zz_fr_cSeen = ctx_3_seen;
      end
    endcase
  end

  always @(*) begin
    case(_zz_fr_endBad_1)
      5'b00000 : _zz_fr_endBad = fullMask_0;
      5'b00001 : _zz_fr_endBad = fullMask_1;
      5'b00010 : _zz_fr_endBad = fullMask_2;
      5'b00011 : _zz_fr_endBad = fullMask_3;
      5'b00100 : _zz_fr_endBad = fullMask_4;
      5'b00101 : _zz_fr_endBad = fullMask_5;
      5'b00110 : _zz_fr_endBad = fullMask_6;
      5'b00111 : _zz_fr_endBad = fullMask_7;
      5'b01000 : _zz_fr_endBad = fullMask_8;
      5'b01001 : _zz_fr_endBad = fullMask_9;
      5'b01010 : _zz_fr_endBad = fullMask_10;
      5'b01011 : _zz_fr_endBad = fullMask_11;
      5'b01100 : _zz_fr_endBad = fullMask_12;
      5'b01101 : _zz_fr_endBad = fullMask_13;
      5'b01110 : _zz_fr_endBad = fullMask_14;
      5'b01111 : _zz_fr_endBad = fullMask_15;
      default : _zz_fr_endBad = fullMask_16;
    endcase
  end

  always @(*) begin
    case(_zz_dv_done_0_1)
      5'b00000 : _zz_dv_done_0 = fullMask_0;
      5'b00001 : _zz_dv_done_0 = fullMask_1;
      5'b00010 : _zz_dv_done_0 = fullMask_2;
      5'b00011 : _zz_dv_done_0 = fullMask_3;
      5'b00100 : _zz_dv_done_0 = fullMask_4;
      5'b00101 : _zz_dv_done_0 = fullMask_5;
      5'b00110 : _zz_dv_done_0 = fullMask_6;
      5'b00111 : _zz_dv_done_0 = fullMask_7;
      5'b01000 : _zz_dv_done_0 = fullMask_8;
      5'b01001 : _zz_dv_done_0 = fullMask_9;
      5'b01010 : _zz_dv_done_0 = fullMask_10;
      5'b01011 : _zz_dv_done_0 = fullMask_11;
      5'b01100 : _zz_dv_done_0 = fullMask_12;
      5'b01101 : _zz_dv_done_0 = fullMask_13;
      5'b01110 : _zz_dv_done_0 = fullMask_14;
      5'b01111 : _zz_dv_done_0 = fullMask_15;
      default : _zz_dv_done_0 = fullMask_16;
    endcase
  end

  always @(*) begin
    case(_zz_dv_done_1_1)
      5'b00000 : _zz_dv_done_1 = fullMask_0;
      5'b00001 : _zz_dv_done_1 = fullMask_1;
      5'b00010 : _zz_dv_done_1 = fullMask_2;
      5'b00011 : _zz_dv_done_1 = fullMask_3;
      5'b00100 : _zz_dv_done_1 = fullMask_4;
      5'b00101 : _zz_dv_done_1 = fullMask_5;
      5'b00110 : _zz_dv_done_1 = fullMask_6;
      5'b00111 : _zz_dv_done_1 = fullMask_7;
      5'b01000 : _zz_dv_done_1 = fullMask_8;
      5'b01001 : _zz_dv_done_1 = fullMask_9;
      5'b01010 : _zz_dv_done_1 = fullMask_10;
      5'b01011 : _zz_dv_done_1 = fullMask_11;
      5'b01100 : _zz_dv_done_1 = fullMask_12;
      5'b01101 : _zz_dv_done_1 = fullMask_13;
      5'b01110 : _zz_dv_done_1 = fullMask_14;
      5'b01111 : _zz_dv_done_1 = fullMask_15;
      default : _zz_dv_done_1 = fullMask_16;
    endcase
  end

  always @(*) begin
    case(_zz_dv_done_2_1)
      5'b00000 : _zz_dv_done_2 = fullMask_0;
      5'b00001 : _zz_dv_done_2 = fullMask_1;
      5'b00010 : _zz_dv_done_2 = fullMask_2;
      5'b00011 : _zz_dv_done_2 = fullMask_3;
      5'b00100 : _zz_dv_done_2 = fullMask_4;
      5'b00101 : _zz_dv_done_2 = fullMask_5;
      5'b00110 : _zz_dv_done_2 = fullMask_6;
      5'b00111 : _zz_dv_done_2 = fullMask_7;
      5'b01000 : _zz_dv_done_2 = fullMask_8;
      5'b01001 : _zz_dv_done_2 = fullMask_9;
      5'b01010 : _zz_dv_done_2 = fullMask_10;
      5'b01011 : _zz_dv_done_2 = fullMask_11;
      5'b01100 : _zz_dv_done_2 = fullMask_12;
      5'b01101 : _zz_dv_done_2 = fullMask_13;
      5'b01110 : _zz_dv_done_2 = fullMask_14;
      5'b01111 : _zz_dv_done_2 = fullMask_15;
      default : _zz_dv_done_2 = fullMask_16;
    endcase
  end

  always @(*) begin
    case(_zz_dv_done_3_1)
      5'b00000 : _zz_dv_done_3 = fullMask_0;
      5'b00001 : _zz_dv_done_3 = fullMask_1;
      5'b00010 : _zz_dv_done_3 = fullMask_2;
      5'b00011 : _zz_dv_done_3 = fullMask_3;
      5'b00100 : _zz_dv_done_3 = fullMask_4;
      5'b00101 : _zz_dv_done_3 = fullMask_5;
      5'b00110 : _zz_dv_done_3 = fullMask_6;
      5'b00111 : _zz_dv_done_3 = fullMask_7;
      5'b01000 : _zz_dv_done_3 = fullMask_8;
      5'b01001 : _zz_dv_done_3 = fullMask_9;
      5'b01010 : _zz_dv_done_3 = fullMask_10;
      5'b01011 : _zz_dv_done_3 = fullMask_11;
      5'b01100 : _zz_dv_done_3 = fullMask_12;
      5'b01101 : _zz_dv_done_3 = fullMask_13;
      5'b01110 : _zz_dv_done_3 = fullMask_14;
      5'b01111 : _zz_dv_done_3 = fullMask_15;
      default : _zz_dv_done_3 = fullMask_16;
    endcase
  end

  always @(*) begin
    case(_zz_io_deliver_payload_tag_wave_3)
      2'b00 : begin
        _zz_io_deliver_payload_tag_wave_4 = ctx_0_tag_wave;
        _zz_io_deliver_payload_tag_thread = ctx_0_tag_thread;
        _zz_io_deliver_payload_tag_lnid = ctx_0_tag_lnid;
        _zz_io_deliver_payload_tag_precision = ctx_0_tag_precision;
        _zz_io_deliver_payload_tag_dim = ctx_0_tag_dim;
        _zz_io_deliver_payload_base = ctx_0_base;
        _zz_io_deliver_payload_total = ctx_0_total;
      end
      2'b01 : begin
        _zz_io_deliver_payload_tag_wave_4 = ctx_1_tag_wave;
        _zz_io_deliver_payload_tag_thread = ctx_1_tag_thread;
        _zz_io_deliver_payload_tag_lnid = ctx_1_tag_lnid;
        _zz_io_deliver_payload_tag_precision = ctx_1_tag_precision;
        _zz_io_deliver_payload_tag_dim = ctx_1_tag_dim;
        _zz_io_deliver_payload_base = ctx_1_base;
        _zz_io_deliver_payload_total = ctx_1_total;
      end
      2'b10 : begin
        _zz_io_deliver_payload_tag_wave_4 = ctx_2_tag_wave;
        _zz_io_deliver_payload_tag_thread = ctx_2_tag_thread;
        _zz_io_deliver_payload_tag_lnid = ctx_2_tag_lnid;
        _zz_io_deliver_payload_tag_precision = ctx_2_tag_precision;
        _zz_io_deliver_payload_tag_dim = ctx_2_tag_dim;
        _zz_io_deliver_payload_base = ctx_2_base;
        _zz_io_deliver_payload_total = ctx_2_total;
      end
      default : begin
        _zz_io_deliver_payload_tag_wave_4 = ctx_3_tag_wave;
        _zz_io_deliver_payload_tag_thread = ctx_3_tag_thread;
        _zz_io_deliver_payload_tag_lnid = ctx_3_tag_lnid;
        _zz_io_deliver_payload_tag_precision = ctx_3_tag_precision;
        _zz_io_deliver_payload_tag_dim = ctx_3_tag_dim;
        _zz_io_deliver_payload_base = ctx_3_base;
        _zz_io_deliver_payload_total = ctx_3_total;
      end
    endcase
  end

  always @(*) begin
    case(_zz_io_incomplete_9)
      3'b000 : _zz_io_incomplete_8 = _zz_io_incomplete;
      3'b001 : _zz_io_incomplete_8 = _zz_io_incomplete_1;
      3'b010 : _zz_io_incomplete_8 = _zz_io_incomplete_2;
      3'b011 : _zz_io_incomplete_8 = _zz_io_incomplete_3;
      3'b100 : _zz_io_incomplete_8 = _zz_io_incomplete_4;
      3'b101 : _zz_io_incomplete_8 = _zz_io_incomplete_5;
      3'b110 : _zz_io_incomplete_8 = _zz_io_incomplete_6;
      default : _zz_io_incomplete_8 = _zz_io_incomplete_7;
    endcase
  end

  always @(*) begin
    case(_zz_io_incomplete_11)
      3'b000 : _zz_io_incomplete_10 = _zz_io_incomplete;
      3'b001 : _zz_io_incomplete_10 = _zz_io_incomplete_1;
      3'b010 : _zz_io_incomplete_10 = _zz_io_incomplete_2;
      3'b011 : _zz_io_incomplete_10 = _zz_io_incomplete_3;
      3'b100 : _zz_io_incomplete_10 = _zz_io_incomplete_4;
      3'b101 : _zz_io_incomplete_10 = _zz_io_incomplete_5;
      3'b110 : _zz_io_incomplete_10 = _zz_io_incomplete_6;
      default : _zz_io_incomplete_10 = _zz_io_incomplete_7;
    endcase
  end

  assign fullMask_0 = 16'h0;
  assign fullMask_1 = 16'h0001;
  assign fullMask_2 = 16'h0003;
  assign fullMask_3 = 16'h0007;
  assign fullMask_4 = 16'h000f;
  assign fullMask_5 = 16'h001f;
  assign fullMask_6 = 16'h003f;
  assign fullMask_7 = 16'h007f;
  assign fullMask_8 = 16'h00ff;
  assign fullMask_9 = 16'h01ff;
  assign fullMask_10 = 16'h03ff;
  assign fullMask_11 = 16'h07ff;
  assign fullMask_12 = 16'h0fff;
  assign fullMask_13 = 16'h1fff;
  assign fullMask_14 = 16'h3fff;
  assign fullMask_15 = 16'h7fff;
  assign fullMask_16 = 16'hffff;
  assign fr_hit_0 = (ctx_0_active && (((((ctx_0_tag_wave == io_frag_head_tag_wave) && (ctx_0_tag_thread == io_frag_head_tag_thread)) && (ctx_0_tag_lnid == io_frag_head_tag_lnid)) && (ctx_0_tag_precision == io_frag_head_tag_precision)) && (ctx_0_tag_dim == io_frag_head_tag_dim)));
  assign fr_hit_1 = (ctx_1_active && (((((ctx_1_tag_wave == io_frag_head_tag_wave) && (ctx_1_tag_thread == io_frag_head_tag_thread)) && (ctx_1_tag_lnid == io_frag_head_tag_lnid)) && (ctx_1_tag_precision == io_frag_head_tag_precision)) && (ctx_1_tag_dim == io_frag_head_tag_dim)));
  assign fr_hit_2 = (ctx_2_active && (((((ctx_2_tag_wave == io_frag_head_tag_wave) && (ctx_2_tag_thread == io_frag_head_tag_thread)) && (ctx_2_tag_lnid == io_frag_head_tag_lnid)) && (ctx_2_tag_precision == io_frag_head_tag_precision)) && (ctx_2_tag_dim == io_frag_head_tag_dim)));
  assign fr_hit_3 = (ctx_3_active && (((((ctx_3_tag_wave == io_frag_head_tag_wave) && (ctx_3_tag_thread == io_frag_head_tag_thread)) && (ctx_3_tag_lnid == io_frag_head_tag_lnid)) && (ctx_3_tag_precision == io_frag_head_tag_precision)) && (ctx_3_tag_dim == io_frag_head_tag_dim)));
  assign fr_hitAny = (((fr_hit_0 || fr_hit_1) || fr_hit_2) || fr_hit_3);
  assign _zz_fr_cBase = (fr_hit_1 || fr_hit_3);
  assign _zz_fr_cBase_1 = (fr_hit_2 || fr_hit_3);
  assign _zz_fr_cBase_2 = {_zz_fr_cBase_1,_zz_fr_cBase};
  assign fr_cBase = _zz_fr_cBase_3;
  assign fr_cTotal = _zz_fr_cTotal;
  assign fr_cKnown = _zz_fr_cKnown;
  assign fr_cSeen = _zz_fr_cSeen;
  assign fr_effTotal = (fr_cKnown ? fr_cTotal : io_frag_head_total);
  assign fr_capaRej = (8'h10 < io_frag_head_total);
  assign fr_strayRej = ((! fr_capaRej) && (! fr_hitAny));
  assign fr_totBad = ((((! fr_capaRej) && fr_hitAny) && fr_cKnown) && (io_frag_head_total != fr_cTotal));
  assign fr_overRej = ((((! fr_capaRej) && fr_hitAny) && (! fr_totBad)) && ((io_frag_head_seq == 8'h0) || (fr_effTotal < io_frag_head_seq)));
  assign fr_off = (_zz_fr_off - 4'b0001);
  assign fr_ohSeq = (16'h0001 <<< fr_off);
  assign fr_dupRej = (((((! fr_capaRej) && fr_hitAny) && (! fr_totBad)) && (! fr_overRej)) && (|(fr_cSeen & fr_ohSeq)));
  assign fr_accept = (((((io_frag_valid && fr_hitAny) && (! fr_capaRej)) && (! fr_totBad)) && (! fr_overRej)) && (! fr_dupRej));
  assign fr_newSeen = (fr_cSeen | fr_ohSeq);
  assign fr_endBad = (io_frag_head_last && (fr_newSeen != _zz_fr_endBad));
  assign when_Reassembly_l297 = (fr_accept && fr_hit_0);
  assign when_Reassembly_l297_1 = (fr_accept && fr_hit_1);
  assign when_Reassembly_l297_2 = (fr_accept && fr_hit_2);
  assign when_Reassembly_l297_3 = (fr_accept && fr_hit_3);
  assign fr_rejEvt = (io_frag_valid && (((fr_strayRej || fr_totBad) || fr_overRej) || fr_dupRej));
  assign fr_endEvt = (fr_accept && fr_endBad);
  assign fr_capaEvt = (io_frag_valid && fr_capaRej);
  assign io_wr_valid = fr_accept;
  assign io_wr_base = fr_cBase;
  assign io_wr_off = fr_off;
  assign io_wr_body = io_frag_body;
  assign op_clash = ((((ctx_0_active && (_zz_op_clash && _zz_op_clash_3)) || (ctx_1_active && (_zz_op_clash_4 && _zz_op_clash_7))) || (ctx_2_active && ((_zz_op_clash_8 && _zz_op_clash_9) && (ctx_2_tag_dim == io_open_tag_dim)))) || (ctx_3_active && (((_zz_op_clash_10 && _zz_op_clash_11) && (ctx_3_tag_precision == io_open_tag_precision)) && (ctx_3_tag_dim == io_open_tag_dim))));
  assign op_free_0 = (! ctx_0_active);
  assign op_free_1 = (! ctx_1_active);
  assign op_free_2 = (! ctx_2_active);
  assign op_free_3 = (! ctx_3_active);
  assign op_freeAny = (((op_free_0 || op_free_1) || op_free_2) || op_free_3);
  assign _zz_op_freeOh = {op_free_3,{op_free_2,{op_free_1,op_free_0}}};
  assign op_freeOh = (_zz_op_freeOh & (~ _zz_op_freeOh_1));
  assign op_grant = ((io_open_valid && (! op_clash)) && op_freeAny);
  assign io_open_granted = op_grant;
  assign when_Reassembly_l330 = (op_grant && op_freeOh[0]);
  assign when_Reassembly_l330_1 = (op_grant && op_freeOh[1]);
  assign when_Reassembly_l330_2 = (op_grant && op_freeOh[2]);
  assign when_Reassembly_l330_3 = (op_grant && op_freeOh[3]);
  assign op_clashEvt = (io_open_valid && op_clash);
  assign dv_done_0 = (((ctx_0_active && ctx_0_last) && ctx_0_totalKnown) && (ctx_0_seen == _zz_dv_done_0));
  assign dv_done_1 = (((ctx_1_active && ctx_1_last) && ctx_1_totalKnown) && (ctx_1_seen == _zz_dv_done_1));
  assign dv_done_2 = (((ctx_2_active && ctx_2_last) && ctx_2_totalKnown) && (ctx_2_seen == _zz_dv_done_2));
  assign dv_done_3 = (((ctx_3_active && ctx_3_last) && ctx_3_totalKnown) && (ctx_3_seen == _zz_dv_done_3));
  assign dv_doneAny = (((dv_done_0 || dv_done_1) || dv_done_2) || dv_done_3);
  assign _zz_dv_grantOh = {dv_done_3,{dv_done_2,{dv_done_1,dv_done_0}}};
  assign dv_grantOh = (_zz_dv_grantOh & (~ _zz_dv_grantOh_1));
  assign io_deliver_valid = dv_doneAny;
  assign _zz_io_deliver_payload_tag_wave = dv_grantOh[3];
  assign _zz_io_deliver_payload_tag_wave_1 = (dv_grantOh[1] || _zz_io_deliver_payload_tag_wave);
  assign _zz_io_deliver_payload_tag_wave_2 = (dv_grantOh[2] || _zz_io_deliver_payload_tag_wave);
  assign _zz_io_deliver_payload_tag_wave_3 = {_zz_io_deliver_payload_tag_wave_2,_zz_io_deliver_payload_tag_wave_1};
  assign io_deliver_payload_tag_wave = _zz_io_deliver_payload_tag_wave_4;
  assign io_deliver_payload_tag_thread = _zz_io_deliver_payload_tag_thread;
  assign io_deliver_payload_tag_lnid = _zz_io_deliver_payload_tag_lnid;
  assign io_deliver_payload_tag_precision = _zz_io_deliver_payload_tag_precision;
  assign io_deliver_payload_tag_dim = _zz_io_deliver_payload_tag_dim;
  assign io_deliver_payload_base = _zz_io_deliver_payload_base;
  assign io_deliver_payload_total = _zz_io_deliver_payload_total;
  assign io_deliver_fire = (io_deliver_valid && io_deliver_ready);
  assign when_Reassembly_l369 = (io_deliver_fire && dv_grantOh[0]);
  assign when_Reassembly_l369_1 = (io_deliver_fire && dv_grantOh[1]);
  assign when_Reassembly_l369_2 = (io_deliver_fire && dv_grantOh[2]);
  assign when_Reassembly_l369_3 = (io_deliver_fire && dv_grantOh[3]);
  assign ab_hit_0 = (ctx_0_active && (((((ctx_0_tag_wave == io_abort_tag_wave) && (ctx_0_tag_thread == io_abort_tag_thread)) && (ctx_0_tag_lnid == io_abort_tag_lnid)) && (ctx_0_tag_precision == io_abort_tag_precision)) && (ctx_0_tag_dim == io_abort_tag_dim)));
  assign ab_hit_1 = (ctx_1_active && (((((ctx_1_tag_wave == io_abort_tag_wave) && (ctx_1_tag_thread == io_abort_tag_thread)) && (ctx_1_tag_lnid == io_abort_tag_lnid)) && (ctx_1_tag_precision == io_abort_tag_precision)) && (ctx_1_tag_dim == io_abort_tag_dim)));
  assign ab_hit_2 = (ctx_2_active && (((((ctx_2_tag_wave == io_abort_tag_wave) && (ctx_2_tag_thread == io_abort_tag_thread)) && (ctx_2_tag_lnid == io_abort_tag_lnid)) && (ctx_2_tag_precision == io_abort_tag_precision)) && (ctx_2_tag_dim == io_abort_tag_dim)));
  assign ab_hit_3 = (ctx_3_active && (((((ctx_3_tag_wave == io_abort_tag_wave) && (ctx_3_tag_thread == io_abort_tag_thread)) && (ctx_3_tag_lnid == io_abort_tag_lnid)) && (ctx_3_tag_precision == io_abort_tag_precision)) && (ctx_3_tag_dim == io_abort_tag_dim)));
  assign ab_hitAny = (((ab_hit_0 || ab_hit_1) || ab_hit_2) || ab_hit_3);
  assign ab_fire = (io_abort_valid && ab_hitAny);
  assign when_Reassembly_l401 = (ab_fire && ab_hit_0);
  assign when_Reassembly_l401_1 = (ab_fire && ab_hit_1);
  assign when_Reassembly_l401_2 = (ab_fire && ab_hit_2);
  assign when_Reassembly_l401_3 = (ab_fire && ab_hit_3);
  assign when_Reassembly_l412 = (ab_fire && (ab_cnt != 8'hff));
  assign io_abortCount = ab_cnt;
  assign _zz_io_incomplete = 3'b000;
  assign _zz_io_incomplete_1 = 3'b001;
  assign _zz_io_incomplete_2 = 3'b001;
  assign _zz_io_incomplete_3 = 3'b010;
  assign _zz_io_incomplete_4 = 3'b001;
  assign _zz_io_incomplete_5 = 3'b010;
  assign _zz_io_incomplete_6 = 3'b010;
  assign _zz_io_incomplete_7 = 3'b011;
  assign io_incomplete = (_zz_io_incomplete_8 + _zz_io_incomplete_10);
  assign when_Common_l141 = ((fr_rejEvt || fr_endEvt) || op_clashEvt);
  assign io_fault = _zz_io_fault;
  assign io_capAbsent = capBit;
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      ctx_0_active <= 1'b0;
      ctx_0_totalKnown <= 1'b0;
      ctx_0_seen <= 16'h0;
      ctx_0_last <= 1'b0;
      ctx_1_active <= 1'b0;
      ctx_1_totalKnown <= 1'b0;
      ctx_1_seen <= 16'h0;
      ctx_1_last <= 1'b0;
      ctx_2_active <= 1'b0;
      ctx_2_totalKnown <= 1'b0;
      ctx_2_seen <= 16'h0;
      ctx_2_last <= 1'b0;
      ctx_3_active <= 1'b0;
      ctx_3_totalKnown <= 1'b0;
      ctx_3_seen <= 16'h0;
      ctx_3_last <= 1'b0;
      ab_cnt <= 8'h0;
      _zz_io_fault <= 1'b0;
      capBit <= 1'b0;
    end else begin
      if(when_Reassembly_l297) begin
        ctx_0_seen <= fr_newSeen;
        ctx_0_last <= (ctx_0_last || io_frag_head_last);
        ctx_0_totalKnown <= 1'b1;
      end
      if(when_Reassembly_l297_1) begin
        ctx_1_seen <= fr_newSeen;
        ctx_1_last <= (ctx_1_last || io_frag_head_last);
        ctx_1_totalKnown <= 1'b1;
      end
      if(when_Reassembly_l297_2) begin
        ctx_2_seen <= fr_newSeen;
        ctx_2_last <= (ctx_2_last || io_frag_head_last);
        ctx_2_totalKnown <= 1'b1;
      end
      if(when_Reassembly_l297_3) begin
        ctx_3_seen <= fr_newSeen;
        ctx_3_last <= (ctx_3_last || io_frag_head_last);
        ctx_3_totalKnown <= 1'b1;
      end
      if(when_Reassembly_l330) begin
        ctx_0_active <= 1'b1;
        ctx_0_seen <= 16'h0;
        ctx_0_last <= 1'b0;
        ctx_0_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l330_1) begin
        ctx_1_active <= 1'b1;
        ctx_1_seen <= 16'h0;
        ctx_1_last <= 1'b0;
        ctx_1_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l330_2) begin
        ctx_2_active <= 1'b1;
        ctx_2_seen <= 16'h0;
        ctx_2_last <= 1'b0;
        ctx_2_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l330_3) begin
        ctx_3_active <= 1'b1;
        ctx_3_seen <= 16'h0;
        ctx_3_last <= 1'b0;
        ctx_3_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l369) begin
        ctx_0_active <= 1'b0;
        ctx_0_seen <= 16'h0;
        ctx_0_last <= 1'b0;
        ctx_0_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l369_1) begin
        ctx_1_active <= 1'b0;
        ctx_1_seen <= 16'h0;
        ctx_1_last <= 1'b0;
        ctx_1_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l369_2) begin
        ctx_2_active <= 1'b0;
        ctx_2_seen <= 16'h0;
        ctx_2_last <= 1'b0;
        ctx_2_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l369_3) begin
        ctx_3_active <= 1'b0;
        ctx_3_seen <= 16'h0;
        ctx_3_last <= 1'b0;
        ctx_3_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l401) begin
        ctx_0_active <= 1'b0;
        ctx_0_seen <= 16'h0;
        ctx_0_last <= 1'b0;
        ctx_0_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l401_1) begin
        ctx_1_active <= 1'b0;
        ctx_1_seen <= 16'h0;
        ctx_1_last <= 1'b0;
        ctx_1_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l401_2) begin
        ctx_2_active <= 1'b0;
        ctx_2_seen <= 16'h0;
        ctx_2_last <= 1'b0;
        ctx_2_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l401_3) begin
        ctx_3_active <= 1'b0;
        ctx_3_seen <= 16'h0;
        ctx_3_last <= 1'b0;
        ctx_3_totalKnown <= 1'b0;
      end
      if(when_Reassembly_l412) begin
        ab_cnt <= (ab_cnt + 8'h01);
      end
      if(io_faultClear) begin
        _zz_io_fault <= 1'b0;
      end
      if(when_Common_l141) begin
        _zz_io_fault <= 1'b1;
      end
      if(io_capAbsentClear) begin
        capBit <= 1'b0;
      end
      if(fr_capaEvt) begin
        capBit <= 1'b1;
      end
    end
  end

  always @(posedge clk) begin
    if(when_Reassembly_l297) begin
      ctx_0_total <= fr_effTotal;
    end
    if(when_Reassembly_l297_1) begin
      ctx_1_total <= fr_effTotal;
    end
    if(when_Reassembly_l297_2) begin
      ctx_2_total <= fr_effTotal;
    end
    if(when_Reassembly_l297_3) begin
      ctx_3_total <= fr_effTotal;
    end
    if(when_Reassembly_l330) begin
      ctx_0_tag_wave <= io_open_tag_wave;
      ctx_0_tag_thread <= io_open_tag_thread;
      ctx_0_tag_lnid <= io_open_tag_lnid;
      ctx_0_tag_precision <= io_open_tag_precision;
      ctx_0_tag_dim <= io_open_tag_dim;
      ctx_0_base <= io_open_base;
    end
    if(when_Reassembly_l330_1) begin
      ctx_1_tag_wave <= io_open_tag_wave;
      ctx_1_tag_thread <= io_open_tag_thread;
      ctx_1_tag_lnid <= io_open_tag_lnid;
      ctx_1_tag_precision <= io_open_tag_precision;
      ctx_1_tag_dim <= io_open_tag_dim;
      ctx_1_base <= io_open_base;
    end
    if(when_Reassembly_l330_2) begin
      ctx_2_tag_wave <= io_open_tag_wave;
      ctx_2_tag_thread <= io_open_tag_thread;
      ctx_2_tag_lnid <= io_open_tag_lnid;
      ctx_2_tag_precision <= io_open_tag_precision;
      ctx_2_tag_dim <= io_open_tag_dim;
      ctx_2_base <= io_open_base;
    end
    if(when_Reassembly_l330_3) begin
      ctx_3_tag_wave <= io_open_tag_wave;
      ctx_3_tag_thread <= io_open_tag_thread;
      ctx_3_tag_lnid <= io_open_tag_lnid;
      ctx_3_tag_precision <= io_open_tag_precision;
      ctx_3_tag_dim <= io_open_tag_dim;
      ctx_3_base <= io_open_base;
    end
  end


endmodule
