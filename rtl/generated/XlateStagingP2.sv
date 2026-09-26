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
  output wire [3:0]    io_commit_idx,
  output wire [27:0]   io_commit_tag,
  output wire [31:0]   io_commit_frame,
  output wire          io_commit_perm_r,
  output wire          io_commit_perm_w,
  output wire          io_commit_perm_x,
  output wire          io_commit_v,
  output wire          io_flush_valid,
  output wire [0:0]    io_flush_part,
  output wire          io_missClr,
  output wire          io_badWrite,
  input  wire          clk,
  input  wire          reset
);

  wire                isHi;
  wire       [5:0]    num;
  wire       [1:0]    numPart;
  wire       [4:0]    ctlWord;
  wire                isFlush;
  wire                isMissC;
  wire                isCtlRo;
  wire                entPhantom;
  reg                 stgValid;
  reg        [5:0]    stgNum;
  reg        [31:0]   stgFrame;
  wire                loWr;
  wire                loOk;
  wire                hiWr;
  wire                hiLegal;
  wire                hiRej;
  wire       [7:0]    partField;
  wire                flRsvBad;
  wire                flPartBad;
  wire                flWr;
  wire                mcRsvBad;
  wire                mcWr;
  wire                stgFlushDrop;

  assign isHi = io_woff[0];
  assign num = io_woff[6 : 1];
  assign numPart = num[5 : 4];
  assign ctlWord = io_woff[4 : 0];
  assign isFlush = (ctlWord == 5'h0);
  assign isMissC = (ctlWord == 5'h04);
  assign isCtlRo = (((ctlWord == 5'h01) || (ctlWord == 5'h02)) || (ctlWord == 5'h03));
  assign entPhantom = (2'b10 <= numPart);
  assign loWr = (io_wrEnt && (! isHi));
  assign loOk = (loWr && (! entPhantom));
  assign hiWr = (io_wrEnt && isHi);
  assign hiLegal = (((! entPhantom) && stgValid) && (stgNum == num));
  assign hiRej = (hiWr && (! hiLegal));
  assign io_needReady = (hiWr && hiLegal);
  assign io_commit_valid = ((hiWr && hiLegal) && io_installReady);
  assign io_commit_part = numPart[0:0];
  assign io_commit_idx = num[3 : 0];
  assign io_commit_tag = io_wdata[27 : 0];
  assign io_commit_frame = stgFrame;
  assign io_commit_perm_r = io_wdata[30];
  assign io_commit_perm_w = io_wdata[29];
  assign io_commit_perm_x = io_wdata[28];
  assign io_commit_v = io_wdata[31];
  assign partField = io_wdata[7 : 0];
  assign flRsvBad = ((io_wdata & 32'hffffff00) != 32'h0);
  assign flPartBad = (8'h02 <= partField);
  assign flWr = (io_wrCtl && isFlush);
  assign io_flush_valid = ((flWr && (! flRsvBad)) && (! flPartBad));
  assign io_flush_part = partField[0:0];
  assign mcRsvBad = ((io_wdata & 32'hfffffffe) != 32'h0);
  assign mcWr = (io_wrCtl && isMissC);
  assign io_missClr = ((mcWr && (! mcRsvBad)) && io_wdata[0]);
  assign io_badWrite = (((((loWr && entPhantom) || hiRej) || (flWr && (flRsvBad || flPartBad))) || (mcWr && mcRsvBad)) || (io_wrCtl && isCtlRo));
  assign stgFlushDrop = ((io_flush_valid && (! loOk)) && (stgNum[5 : 4] == partField[1 : 0]));
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      stgValid <= 1'b0;
      stgNum <= 6'h0;
      stgFrame <= 32'h0;
    end else begin
      if(loOk) begin
        stgValid <= 1'b1;
        stgNum <= num;
        stgFrame <= io_wdata;
      end
      if(stgFlushDrop) begin
        stgValid <= 1'b0;
      end
    end
  end


endmodule
