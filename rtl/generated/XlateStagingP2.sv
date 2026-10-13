// Generator : SpinalHDL v1.14.2    git head : 78f29dc66110fc099a777992b6daa2f803ab445e
// Component : XlateStagingP2
// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
// 
// === 생성물이다. 손으로 고치지 말 것. ===
// 고칠 곳은 rtl/spinal/ 의 생성기이고, 고친 뒤 `make rtl-gen` 으로 다시 낸다.
// 여기 직접 쓴 수정은 다음 생성에서 조용히 사라진다.

`timescale 1ns/1ps

module XlateStagingP2 (
  input  wire          io_wrEnt,
  input  wire          io_wrCtl,
  input  wire [6:0]    io_woff,
  input  wire [31:0]   io_wdata,
  input  wire          io_installReady,
  output wire          io_needReady,
  output wire          io_commit_valid,
  output wire [0:0]    io_commit_part,
  output wire [31:0]   io_commit_vpn,
  output wire [31:0]   io_commit_frame,
  output wire          io_commit_perm_r,
  output wire          io_commit_perm_w,
  output wire          io_commit_perm_x,
  output wire          io_commit_v,
  output wire          io_flush_valid,
  output wire [0:0]    io_flush_part,
  output wire          io_missClr,
  output wire          io_badWrite,
  output wire          io_badData,
  input  wire          clk,
  input  wire          reset
);

  wire       [1:0]    entPart;
  wire       [4:0]    entWord;
  wire                isVpn;
  wire                isFrame;
  wire                isCommit;
  wire                isVpnHi;
  wire                isRsvw;
  wire       [4:0]    ctlWord;
  wire                isFlush;
  wire                isMissC;
  wire                isCtlRo;
  wire                phantom;
  reg                 stgVpnValid;
  reg                 stgFrameValid;
  reg        [1:0]    stgPart;
  reg        [31:0]   stgVpn;
  reg        [31:0]   stgFrame;
  wire                pairOk;
  wire                vhLegal;
  wire                vpnOk;
  wire                frOk;
  wire                vhOk;
  wire                cmAcc;
  wire                cmDataBad;
  wire       [7:0]    partField;
  wire                flRsvBad;
  wire                flPartBad;
  wire                flWr;
  wire                mcRsvBad;
  wire                mcWr;
  wire                entRej;
  wire                stgFlushDrop;

  assign entPart = io_woff[6 : 5];
  assign entWord = io_woff[4 : 0];
  assign isVpn = (entWord == 5'h0);
  assign isFrame = (entWord == 5'h01);
  assign isCommit = (entWord == 5'h02);
  assign isVpnHi = (entWord == 5'h03);
  assign isRsvw = (5'h04 <= entWord);
  assign ctlWord = io_woff[4 : 0];
  assign isFlush = (ctlWord == 5'h0);
  assign isMissC = (ctlWord == 5'h04);
  assign isCtlRo = (((ctlWord == 5'h01) || (ctlWord == 5'h02)) || (ctlWord == 5'h03));
  assign phantom = (2'b10 <= entPart);
  assign pairOk = (((! phantom) && stgVpnValid) && (stgPart == entPart));
  assign vhLegal = (pairOk && ((io_wdata & 32'hffffffff) == 32'h0));
  assign vpnOk = ((io_wrEnt && isVpn) && (! phantom));
  assign frOk = ((io_wrEnt && isFrame) && pairOk);
  assign vhOk = ((io_wrEnt && isVpnHi) && vhLegal);
  assign io_needReady = ((io_wrEnt && isCommit) && pairOk);
  assign cmAcc = (io_needReady && io_installReady);
  assign cmDataBad = (((io_wdata & 32'h0fffffff) != 32'h0) || (io_wdata[31] && (! stgFrameValid)));
  assign io_commit_valid = (cmAcc && (! cmDataBad));
  assign io_commit_part = entPart[0:0];
  assign io_commit_vpn = stgVpn;
  assign io_commit_frame = stgFrame;
  assign io_commit_perm_r = io_wdata[30];
  assign io_commit_perm_w = io_wdata[29];
  assign io_commit_perm_x = io_wdata[28];
  assign io_commit_v = io_wdata[31];
  assign io_badData = (cmAcc && cmDataBad);
  assign partField = io_wdata[7 : 0];
  assign flRsvBad = ((io_wdata & 32'hffffff00) != 32'h0);
  assign flPartBad = (8'h02 <= partField);
  assign flWr = (io_wrCtl && isFlush);
  assign io_flush_valid = ((flWr && (! flRsvBad)) && (! flPartBad));
  assign io_flush_part = partField[0:0];
  assign mcRsvBad = ((io_wdata & 32'hfffffffe) != 32'h0);
  assign mcWr = (io_wrCtl && isMissC);
  assign io_missClr = ((mcWr && (! mcRsvBad)) && io_wdata[0]);
  assign entRej = (io_wrEnt && (((phantom || isRsvw) || ((isFrame || isCommit) && (! pairOk))) || (isVpnHi && (! vhLegal))));
  assign io_badWrite = (((entRej || (flWr && (flRsvBad || flPartBad))) || (mcWr && mcRsvBad)) || (io_wrCtl && isCtlRo));
  assign stgFlushDrop = ((io_flush_valid && (! vpnOk)) && (stgPart == partField[1 : 0]));
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      stgVpnValid <= 1'b0;
      stgFrameValid <= 1'b0;
      stgPart <= 2'b00;
      stgVpn <= 32'h0;
      stgFrame <= 32'h0;
    end else begin
      if(vpnOk) begin
        stgVpn <= io_wdata;
        stgPart <= entPart;
        stgVpnValid <= 1'b1;
        stgFrameValid <= 1'b0;
      end
      if(frOk) begin
        stgFrame <= io_wdata;
        stgFrameValid <= 1'b1;
      end
      if(vhOk) begin
        stgFrameValid <= 1'b0;
      end
      if(stgFlushDrop) begin
        stgVpnValid <= 1'b0;
        stgFrameValid <= 1'b0;
      end
    end
  end


endmodule
