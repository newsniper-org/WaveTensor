// Generator : SpinalHDL v1.14.2    git head : 78f29dc66110fc099a777992b6daa2f803ab445e
// Component : HiuPipeline
// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
// 
// === 생성물이다. 손으로 고치지 말 것. ===
// 고칠 곳은 rtl/spinal/ 의 생성기이고, 고친 뒤 `make rtl-gen` 으로 다시 낸다.
// 여기 직접 쓴 수정은 다음 생성에서 조용히 사라진다.

`timescale 1ns/1ps

module HiuPipeline (
  input  wire          io_req_valid,
  output wire          io_req_ready,
  input  wire [1:0]    io_req_part,
  input  wire [31:0]   io_req_vpn,
  input  wire          io_req_write,
  input  wire          io_hold,
  output reg  [31:0]   io_owner_frame,
  input  wire          io_owner_devOwned,
  output wire          io_mask_req_valid,
  output wire [1:0]    io_mask_req_part,
  output wire [31:0]   io_mask_req_frame,
  input  wire          io_mask_rsp_valid,
  input  wire [31:0]   io_mask_rsp_frame,
  input  wire          io_install_valid,
  output wire          io_install_ready,
  input  wire [1:0]    io_install_part,
  input  wire [3:0]    io_install_idx,
  input  wire [27:0]   io_install_tag,
  input  wire [31:0]   io_install_frame,
  input  wire          io_install_perm_r,
  input  wire          io_install_perm_w,
  input  wire          io_install_perm_x,
  input  wire          io_install_v,
  input  wire          io_flush_valid,
  input  wire [1:0]    io_flush_part,
  input  wire          io_hostRsp_valid,
  input  wire [31:0]   io_hostRsp_frame,
  input  wire          io_hostRsp_perm_r,
  input  wire          io_hostRsp_perm_w,
  input  wire          io_hostRsp_perm_x,
  output wire          io_rsp_valid,
  output wire          io_rsp_granted,
  output wire [1:0]    io_rsp_part,
  output wire          io_rsp_write,
  output wire          io_rsp_fromFill,
  output reg  [31:0]   io_rsp_frame,
  output reg           io_rsp_perm_r,
  output reg           io_rsp_perm_w,
  output reg           io_rsp_perm_x,
  output wire [2:0]    io_occupancy,
  output wire          io_faultPerm,
  input  wire          io_faultClear,
  output wire          io_missNotice,
  input  wire          io_missClear,
  output wire          installSlotFree,
  output wire          missStall,
  output wire [1:0]    missPart,
  output wire [31:0]   missVpn,
  output wire          faultOwn,
  input  wire          faultOwnClear,
  input  wire          clk,
  input  wire          reset
);

  wire                xlate_io_rsp_hit;
  wire                xlate_io_rsp_fromFill;
  wire       [31:0]   xlate_io_rsp_frame;
  wire                xlate_io_rsp_perm_r;
  wire                xlate_io_rsp_perm_w;
  wire                xlate_io_rsp_perm_x;
  wire                xlate_io_rsp_hostPresent;
  wire       [31:0]   xlate_io_rsp_hostFrame;
  wire                xlate_io_rsp_hostPerm_r;
  wire                xlate_io_rsp_hostPerm_w;
  wire                xlate_io_rsp_hostPerm_x;
  wire                xlate_io_install_ready;
  wire                xlate_installSlotFree;
  wire       [2:0]    _zz_io_occupancy;
  wire       [2:0]    _zz_io_occupancy_1;
  wire       [2:0]    _zz_io_occupancy_2;
  wire       [2:0]    _zz_io_occupancy_3;
  wire       [2:0]    _zz_io_occupancy_4;
  wire       [0:0]    _zz_io_occupancy_5;
  wire       [2:0]    _zz_io_occupancy_6;
  wire       [0:0]    _zz_io_occupancy_7;
  wire       [2:0]    _zz_io_occupancy_8;
  wire       [0:0]    _zz_io_occupancy_9;
  wire       [2:0]    _zz_io_occupancy_10;
  wire       [0:0]    _zz_io_occupancy_11;
  wire       [2:0]    _zz_io_occupancy_12;
  wire       [0:0]    _zz_io_occupancy_13;
  wire       [2:0]    _zz_io_occupancy_14;
  wire       [0:0]    _zz_io_occupancy_15;
  reg                 s1_valid;
  reg        [1:0]    s1_part;
  reg        [31:0]   s1_vpn;
  reg                 s1_write;
  reg                 s2_valid;
  reg        [1:0]    s2_part;
  reg        [31:0]   s2_vpn;
  reg                 s2_write;
  reg                 s3_valid;
  reg        [1:0]    s3_part;
  reg        [31:0]   s3_vpn;
  reg                 s3_write;
  reg        [31:0]   lookFrame;
  reg                 lookPerm_r;
  reg                 lookPerm_w;
  reg                 lookPerm_x;
  wire                lookAny;
  wire                lookFill;
  reg        [1:0]    s4_part;
  reg                 s4_write;
  reg                 s4_anyHit;
  reg                 s4_fromFill;
  reg        [31:0]   s4_frame;
  reg                 s4_perm_r;
  reg                 s4_perm_w;
  reg                 s4_perm_x;
  reg                 s5_valid;
  reg        [1:0]    s5_part;
  reg                 s5_write;
  reg                 s5_anyHit;
  reg                 s5_fromFill;
  reg        [31:0]   s5_frame;
  reg        [31:0]   s5_masked;
  reg                 s5_perm_r;
  reg                 s5_perm_w;
  reg                 s5_perm_x;
  reg                 s6_valid;
  reg        [1:0]    s6_part;
  reg                 s6_write;
  reg                 s6_anyHit;
  reg                 s6_fromFill;
  reg        [31:0]   s6_frame;
  reg        [31:0]   s6_masked;
  reg                 s6_perm_r;
  reg                 s6_perm_w;
  reg                 s6_perm_x;
  wire                missWait;
  wire                advance;
  wire                when_HiuPipeline_l405;
  wire                entitle;
  wire                granted;
  wire                permViol;
  reg                 _zz_io_faultPerm;
  reg                 _zz_io_missNotice;
  wire                ownViol;
  reg                 _zz_faultOwn;
  reg                 lat_hit;
  reg        [31:0]   lat_frame;
  reg                 lat_perm_r;
  reg                 lat_perm_w;
  reg                 lat_perm_x;
  reg                 lat_fromFill;
  wire                latCapture;

  assign _zz_io_occupancy = (_zz_io_occupancy_1 + _zz_io_occupancy_12);
  assign _zz_io_occupancy_1 = (_zz_io_occupancy_2 + _zz_io_occupancy_10);
  assign _zz_io_occupancy_2 = (_zz_io_occupancy_3 + _zz_io_occupancy_8);
  assign _zz_io_occupancy_3 = (_zz_io_occupancy_4 + _zz_io_occupancy_6);
  assign _zz_io_occupancy_5 = s1_valid;
  assign _zz_io_occupancy_4 = {2'd0, _zz_io_occupancy_5};
  assign _zz_io_occupancy_7 = s2_valid;
  assign _zz_io_occupancy_6 = {2'd0, _zz_io_occupancy_7};
  assign _zz_io_occupancy_9 = s3_valid;
  assign _zz_io_occupancy_8 = {2'd0, _zz_io_occupancy_9};
  assign _zz_io_occupancy_11 = io_mask_rsp_valid;
  assign _zz_io_occupancy_10 = {2'd0, _zz_io_occupancy_11};
  assign _zz_io_occupancy_13 = s5_valid;
  assign _zz_io_occupancy_12 = {2'd0, _zz_io_occupancy_13};
  assign _zz_io_occupancy_15 = s6_valid;
  assign _zz_io_occupancy_14 = {2'd0, _zz_io_occupancy_15};
  XlateStore xlate (
    .io_lookup_valid    (s3_valid                    ), //i
    .io_lookup_part     (s3_part[1:0]                ), //i
    .io_lookup_vpn      (s3_vpn[31:0]                ), //i
    .io_rsp_hit         (xlate_io_rsp_hit            ), //o
    .io_rsp_fromFill    (xlate_io_rsp_fromFill       ), //o
    .io_rsp_frame       (xlate_io_rsp_frame[31:0]    ), //o
    .io_rsp_perm_r      (xlate_io_rsp_perm_r         ), //o
    .io_rsp_perm_w      (xlate_io_rsp_perm_w         ), //o
    .io_rsp_perm_x      (xlate_io_rsp_perm_x         ), //o
    .io_rsp_hostPresent (xlate_io_rsp_hostPresent    ), //o
    .io_rsp_hostFrame   (xlate_io_rsp_hostFrame[31:0]), //o
    .io_rsp_hostPerm_r  (xlate_io_rsp_hostPerm_r     ), //o
    .io_rsp_hostPerm_w  (xlate_io_rsp_hostPerm_w     ), //o
    .io_rsp_hostPerm_x  (xlate_io_rsp_hostPerm_x     ), //o
    .io_hostRsp_valid   (io_hostRsp_valid            ), //i
    .io_hostRsp_frame   (io_hostRsp_frame[31:0]      ), //i
    .io_hostRsp_perm_r  (io_hostRsp_perm_r           ), //i
    .io_hostRsp_perm_w  (io_hostRsp_perm_w           ), //i
    .io_hostRsp_perm_x  (io_hostRsp_perm_x           ), //i
    .io_install_valid   (io_install_valid            ), //i
    .io_install_ready   (xlate_io_install_ready      ), //o
    .io_install_part    (io_install_part[1:0]        ), //i
    .io_install_idx     (io_install_idx[3:0]         ), //i
    .io_install_tag     (io_install_tag[27:0]        ), //i
    .io_install_frame   (io_install_frame[31:0]      ), //i
    .io_install_perm_r  (io_install_perm_r           ), //i
    .io_install_perm_w  (io_install_perm_w           ), //i
    .io_install_perm_x  (io_install_perm_x           ), //i
    .io_install_v       (io_install_v                ), //i
    .io_flush_valid     (io_flush_valid              ), //i
    .io_flush_part      (io_flush_part[1:0]          ), //i
    .installSlotFree    (xlate_installSlotFree       ), //o
    .clk                (clk                         ), //i
    .reset              (reset                       )  //i
  );
  assign io_install_ready = xlate_io_install_ready;
  always @(*) begin
    lookFrame = 32'h0;
    if(xlate_io_rsp_hit) begin
      lookFrame = xlate_io_rsp_frame;
    end
    if(lat_hit) begin
      lookFrame = lat_frame;
    end
  end

  always @(*) begin
    lookPerm_r = 1'b0;
    if(xlate_io_rsp_hit) begin
      lookPerm_r = xlate_io_rsp_perm_r;
    end
    if(lat_hit) begin
      lookPerm_r = lat_perm_r;
    end
  end

  always @(*) begin
    lookPerm_w = 1'b0;
    if(xlate_io_rsp_hit) begin
      lookPerm_w = xlate_io_rsp_perm_w;
    end
    if(lat_hit) begin
      lookPerm_w = lat_perm_w;
    end
  end

  always @(*) begin
    lookPerm_x = 1'b0;
    if(xlate_io_rsp_hit) begin
      lookPerm_x = xlate_io_rsp_perm_x;
    end
    if(lat_hit) begin
      lookPerm_x = lat_perm_x;
    end
  end

  assign io_mask_req_valid = s3_valid;
  assign io_mask_req_part = s3_part;
  assign io_mask_req_frame = lookFrame;
  assign missWait = (s3_valid && (! lookAny));
  assign advance = ((! io_hold) && (! missWait));
  assign io_req_ready = advance;
  always @(*) begin
    io_owner_frame = 32'h0;
    if(when_HiuPipeline_l405) begin
      io_owner_frame = s6_frame;
    end
  end

  assign when_HiuPipeline_l405 = (s6_valid && s6_anyHit);
  assign entitle = (s6_write ? s6_perm_w : s6_perm_r);
  assign granted = (((s6_valid && s6_anyHit) && io_owner_devOwned) && entitle);
  assign permViol = ((s6_valid && s6_anyHit) && (! entitle));
  assign io_rsp_valid = (s6_valid && advance);
  assign io_rsp_granted = granted;
  assign io_rsp_part = s6_part;
  assign io_rsp_write = s6_write;
  assign io_rsp_fromFill = s6_fromFill;
  always @(*) begin
    io_rsp_frame = 32'h0;
    if(granted) begin
      io_rsp_frame = s6_masked;
    end
  end

  always @(*) begin
    io_rsp_perm_r = 1'b0;
    if(granted) begin
      io_rsp_perm_r = s6_perm_r;
    end
  end

  always @(*) begin
    io_rsp_perm_w = 1'b0;
    if(granted) begin
      io_rsp_perm_w = s6_perm_w;
    end
  end

  always @(*) begin
    io_rsp_perm_x = 1'b0;
    if(granted) begin
      io_rsp_perm_x = s6_perm_x;
    end
  end

  assign io_occupancy = (_zz_io_occupancy + _zz_io_occupancy_14);
  assign io_faultPerm = _zz_io_faultPerm;
  assign io_missNotice = _zz_io_missNotice;
  assign installSlotFree = xlate_installSlotFree;
  assign missStall = missWait;
  assign missPart = (missWait ? s3_part : 2'b00);
  assign missVpn = (missWait ? s3_vpn : 32'h0);
  assign ownViol = (((s6_valid && s6_anyHit) && entitle) && (! io_owner_devOwned));
  assign faultOwn = _zz_faultOwn;
  assign latCapture = ((s3_valid && (! lat_hit)) && xlate_io_rsp_hit);
  assign lookAny = (lat_hit || xlate_io_rsp_hit);
  assign lookFill = (lat_hit ? lat_fromFill : xlate_io_rsp_fromFill);
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      s1_valid <= 1'b0;
      s2_valid <= 1'b0;
      s3_valid <= 1'b0;
      s5_valid <= 1'b0;
      s6_valid <= 1'b0;
      _zz_io_faultPerm <= 1'b0;
      _zz_io_missNotice <= 1'b0;
      _zz_faultOwn <= 1'b0;
      lat_hit <= 1'b0;
    end else begin
      if(advance) begin
        s1_valid <= io_req_valid;
        s2_valid <= s1_valid;
        s3_valid <= s2_valid;
        s5_valid <= io_mask_rsp_valid;
        s6_valid <= s5_valid;
      end
      if(io_faultClear) begin
        _zz_io_faultPerm <= 1'b0;
      end
      if(permViol) begin
        _zz_io_faultPerm <= 1'b1;
      end
      if(io_missClear) begin
        _zz_io_missNotice <= 1'b0;
      end
      if(missWait) begin
        _zz_io_missNotice <= 1'b1;
      end
      if(faultOwnClear) begin
        _zz_faultOwn <= 1'b0;
      end
      if(ownViol) begin
        _zz_faultOwn <= 1'b1;
      end
      if(advance) begin
        lat_hit <= 1'b0;
      end else begin
        if(latCapture) begin
          lat_hit <= 1'b1;
        end
      end
    end
  end

  always @(posedge clk) begin
    if(advance) begin
      s1_part <= io_req_part;
      s1_vpn <= io_req_vpn;
      s1_write <= io_req_write;
      s2_part <= s1_part;
      s2_vpn <= s1_vpn;
      s2_write <= s1_write;
      s3_part <= s2_part;
      s3_vpn <= s2_vpn;
      s3_write <= s2_write;
      s4_part <= s3_part;
      s4_write <= s3_write;
      s4_anyHit <= lookAny;
      s4_fromFill <= lookFill;
      s4_frame <= lookFrame;
      s4_perm_r <= lookPerm_r;
      s4_perm_w <= lookPerm_w;
      s4_perm_x <= lookPerm_x;
      s5_part <= s4_part;
      s5_write <= s4_write;
      s5_anyHit <= s4_anyHit;
      s5_fromFill <= s4_fromFill;
      s5_frame <= s4_frame;
      s5_masked <= io_mask_rsp_frame;
      s5_perm_r <= s4_perm_r;
      s5_perm_w <= s4_perm_w;
      s5_perm_x <= s4_perm_x;
      s6_part <= s5_part;
      s6_write <= s5_write;
      s6_anyHit <= s5_anyHit;
      s6_fromFill <= s5_fromFill;
      s6_frame <= s5_frame;
      s6_masked <= s5_masked;
      s6_perm_r <= s5_perm_r;
      s6_perm_w <= s5_perm_w;
      s6_perm_x <= s5_perm_x;
    end
    if(!advance) begin
      if(latCapture) begin
        lat_frame <= xlate_io_rsp_frame;
        lat_perm_r <= xlate_io_rsp_perm_r;
        lat_perm_w <= xlate_io_rsp_perm_w;
        lat_perm_x <= xlate_io_rsp_perm_x;
        lat_fromFill <= xlate_io_rsp_fromFill;
      end
    end
  end


endmodule

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
  input  wire          io_install_v,
  input  wire          io_flush_valid,
  input  wire [1:0]    io_flush_part,
  output wire          installSlotFree,
  input  wire          clk,
  input  wire          reset
);

  wire       [62:0]   store_spinal_port1;
  reg                 _zz__zz_io_install_ready;
  reg        [3:0]    _zz_commitLine_idx;
  reg        [27:0]   _zz_commitLine_tag;
  reg        [31:0]   _zz_commitLine_frame;
  reg                 _zz_commitLine_perm_r;
  reg                 _zz_commitLine_perm_w;
  reg                 _zz_commitLine_perm_x;
  reg                 _zz_commitLine_v;
  wire       [5:0]    _zz_store_port;
  wire       [62:0]   _zz_store_port_1;
  reg        [3:0]    _zz_fillLine_idx;
  reg        [27:0]   _zz_fillLine_tag;
  reg        [31:0]   _zz_fillLine_frame;
  reg                 _zz_fillLine_perm_r;
  reg                 _zz_fillLine_perm_w;
  reg                 _zz_fillLine_perm_x;
  reg                 _zz_fillLine_v;
  reg                 _zz_fillShadow;
  reg        [15:0]   _zz_storeValid;
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
  reg                 fillSlot_0_v;
  reg        [3:0]    fillSlot_1_idx;
  reg        [27:0]   fillSlot_1_tag;
  reg        [31:0]   fillSlot_1_frame;
  reg                 fillSlot_1_perm_r;
  reg                 fillSlot_1_perm_w;
  reg                 fillSlot_1_perm_x;
  reg                 fillSlot_1_v;
  reg        [3:0]    fillSlot_2_idx;
  reg        [27:0]   fillSlot_2_tag;
  reg        [31:0]   fillSlot_2_frame;
  reg                 fillSlot_2_perm_r;
  reg                 fillSlot_2_perm_w;
  reg                 fillSlot_2_perm_x;
  reg                 fillSlot_2_v;
  reg        [3:0]    fillSlot_3_idx;
  reg        [27:0]   fillSlot_3_tag;
  reg        [31:0]   fillSlot_3_frame;
  reg                 fillSlot_3_perm_r;
  reg                 fillSlot_3_perm_w;
  reg                 fillSlot_3_perm_x;
  reg                 fillSlot_3_v;
  wire                installFire;
  wire                flushSamePart;
  wire                _zz_io_install_ready;
  wire       [3:0]    _zz_1;
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
  wire                commitLine_v;
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
  wire       [3:0]    fillLine_idx;
  wire       [27:0]   fillLine_tag;
  wire       [31:0]   fillLine_frame;
  wire                fillLine_perm_r;
  wire                fillLine_perm_w;
  wire                fillLine_perm_x;
  wire                fillLine_v;
  wire                fillShadow;
  wire                storeValid;
  wire                storeHit;
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
      2'b00 : _zz__zz_io_install_ready = fillPend_0;
      2'b01 : _zz__zz_io_install_ready = fillPend_1;
      2'b10 : _zz__zz_io_install_ready = fillPend_2;
      default : _zz__zz_io_install_ready = fillPend_3;
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
        _zz_commitLine_v = fillSlot_0_v;
      end
      2'b01 : begin
        _zz_commitLine_idx = fillSlot_1_idx;
        _zz_commitLine_tag = fillSlot_1_tag;
        _zz_commitLine_frame = fillSlot_1_frame;
        _zz_commitLine_perm_r = fillSlot_1_perm_r;
        _zz_commitLine_perm_w = fillSlot_1_perm_w;
        _zz_commitLine_perm_x = fillSlot_1_perm_x;
        _zz_commitLine_v = fillSlot_1_v;
      end
      2'b10 : begin
        _zz_commitLine_idx = fillSlot_2_idx;
        _zz_commitLine_tag = fillSlot_2_tag;
        _zz_commitLine_frame = fillSlot_2_frame;
        _zz_commitLine_perm_r = fillSlot_2_perm_r;
        _zz_commitLine_perm_w = fillSlot_2_perm_w;
        _zz_commitLine_perm_x = fillSlot_2_perm_x;
        _zz_commitLine_v = fillSlot_2_v;
      end
      default : begin
        _zz_commitLine_idx = fillSlot_3_idx;
        _zz_commitLine_tag = fillSlot_3_tag;
        _zz_commitLine_frame = fillSlot_3_frame;
        _zz_commitLine_perm_r = fillSlot_3_perm_r;
        _zz_commitLine_perm_w = fillSlot_3_perm_w;
        _zz_commitLine_perm_x = fillSlot_3_perm_x;
        _zz_commitLine_v = fillSlot_3_v;
      end
    endcase
  end

  always @(*) begin
    case(io_lookup_part)
      2'b00 : begin
        _zz_fillLine_idx = fillSlot_0_idx;
        _zz_fillLine_tag = fillSlot_0_tag;
        _zz_fillLine_frame = fillSlot_0_frame;
        _zz_fillLine_perm_r = fillSlot_0_perm_r;
        _zz_fillLine_perm_w = fillSlot_0_perm_w;
        _zz_fillLine_perm_x = fillSlot_0_perm_x;
        _zz_fillLine_v = fillSlot_0_v;
        _zz_fillShadow = fillPend_0;
        _zz_storeValid = validBits_0;
      end
      2'b01 : begin
        _zz_fillLine_idx = fillSlot_1_idx;
        _zz_fillLine_tag = fillSlot_1_tag;
        _zz_fillLine_frame = fillSlot_1_frame;
        _zz_fillLine_perm_r = fillSlot_1_perm_r;
        _zz_fillLine_perm_w = fillSlot_1_perm_w;
        _zz_fillLine_perm_x = fillSlot_1_perm_x;
        _zz_fillLine_v = fillSlot_1_v;
        _zz_fillShadow = fillPend_1;
        _zz_storeValid = validBits_1;
      end
      2'b10 : begin
        _zz_fillLine_idx = fillSlot_2_idx;
        _zz_fillLine_tag = fillSlot_2_tag;
        _zz_fillLine_frame = fillSlot_2_frame;
        _zz_fillLine_perm_r = fillSlot_2_perm_r;
        _zz_fillLine_perm_w = fillSlot_2_perm_w;
        _zz_fillLine_perm_x = fillSlot_2_perm_x;
        _zz_fillLine_v = fillSlot_2_v;
        _zz_fillShadow = fillPend_2;
        _zz_storeValid = validBits_2;
      end
      default : begin
        _zz_fillLine_idx = fillSlot_3_idx;
        _zz_fillLine_tag = fillSlot_3_tag;
        _zz_fillLine_frame = fillSlot_3_frame;
        _zz_fillLine_perm_r = fillSlot_3_perm_r;
        _zz_fillLine_perm_w = fillSlot_3_perm_w;
        _zz_fillLine_perm_x = fillSlot_3_perm_x;
        _zz_fillLine_v = fillSlot_3_v;
        _zz_fillShadow = fillPend_3;
        _zz_storeValid = validBits_3;
      end
    endcase
  end

  assign installFire = (io_install_valid && io_install_ready);
  assign flushSamePart = (io_flush_valid && (io_flush_part == io_install_part));
  assign _zz_io_install_ready = _zz__zz_io_install_ready;
  assign _zz_1 = ({3'd0,1'b1} <<< io_install_part);
  assign io_install_ready = ((! _zz_io_install_ready) && (! flushSamePart));
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
  assign commitLine_v = _zz_commitLine_v;
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
  assign fillLine_idx = _zz_fillLine_idx;
  assign fillLine_tag = _zz_fillLine_tag;
  assign fillLine_frame = _zz_fillLine_frame;
  assign fillLine_perm_r = _zz_fillLine_perm_r;
  assign fillLine_perm_w = _zz_fillLine_perm_w;
  assign fillLine_perm_x = _zz_fillLine_perm_x;
  assign fillLine_v = _zz_fillLine_v;
  assign fillShadow = (_zz_fillShadow && (fillLine_idx == reqIdx));
  assign storeValid = _zz_storeValid[reqIdx];
  assign storeHit = (((io_lookup_valid && storeValid) && (storeBody_tag == reqTag)) && (! fillShadow));
  assign fillHit = (((io_lookup_valid && fillShadow) && (fillLine_tag == reqTag)) && fillLine_v);
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
  assign installSlotFree = (! _zz_io_install_ready);
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
      if(installFire) begin
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
          validBits_0[commitLine_idx] <= commitLine_v;
        end
        if(_zz_8[1]) begin
          validBits_1[commitLine_idx] <= commitLine_v;
        end
        if(_zz_8[2]) begin
          validBits_2[commitLine_idx] <= commitLine_v;
        end
        if(_zz_8[3]) begin
          validBits_3[commitLine_idx] <= commitLine_v;
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
    if(installFire) begin
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
      if(_zz_3) begin
        fillSlot_0_v <= io_install_v;
      end
      if(_zz_4) begin
        fillSlot_1_v <= io_install_v;
      end
      if(_zz_5) begin
        fillSlot_2_v <= io_install_v;
      end
      if(_zz_6) begin
        fillSlot_3_v <= io_install_v;
      end
    end
  end


endmodule
