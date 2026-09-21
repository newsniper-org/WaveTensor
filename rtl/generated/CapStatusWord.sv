// Generator : SpinalHDL v1.14.2    git head : 78f29dc66110fc099a777992b6daa2f803ab445e
// Component : CapStatusWord
// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
// 
// === 생성물이다. 손으로 고치지 말 것. ===
// 고칠 곳은 rtl/spinal/ 의 생성기이고, 고친 뒤 `make rtl-gen` 으로 다시 낸다.
// 여기 직접 쓴 수정은 다음 생성에서 조용히 사라진다.

`timescale 1ns/1ps

module CapStatusWord (
  input  wire [3:0]    io_set,
  input  wire          io_wr,
  input  wire [31:0]   io_wdata,
  output wire [31:0]   io_word,
  output wire          io_rsvBad,
  output wire [3:0]    io_clrAcc,
  input  wire          clk,
  input  wire          reset
);

  wire                rsvHit;
  wire                accept;
  wire                clrAcc_0;
  wire                clrAcc_1;
  wire                clrAcc_2;
  wire                clrAcc_3;
  wire                defined_0;
  wire                when_Common_l259;
  reg                 defined_1;
  wire                when_Common_l259_1;
  reg                 defined_2;
  wire                when_Common_l259_2;
  reg                 defined_3;

  assign rsvHit = ((io_wdata & 32'hfffffff0) != 32'h0);
  assign io_rsvBad = (io_wr && rsvHit);
  assign accept = (io_wr && (! io_rsvBad));
  assign clrAcc_0 = (accept && io_wdata[0]);
  assign clrAcc_1 = (accept && io_wdata[1]);
  assign clrAcc_2 = (accept && io_wdata[2]);
  assign clrAcc_3 = (accept && io_wdata[3]);
  assign io_clrAcc = {clrAcc_3,{clrAcc_2,{clrAcc_1,clrAcc_0}}};
  assign defined_0 = io_set[0];
  assign when_Common_l259 = io_set[1];
  assign when_Common_l259_1 = io_set[2];
  assign when_Common_l259_2 = io_set[3];
  assign io_word = {28'h0,{defined_3,{defined_2,{defined_1,defined_0}}}};
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      defined_1 <= 1'b0;
      defined_2 <= 1'b0;
      defined_3 <= 1'b0;
    end else begin
      if(clrAcc_1) begin
        defined_1 <= 1'b0;
      end
      if(when_Common_l259) begin
        defined_1 <= 1'b1;
      end
      if(clrAcc_2) begin
        defined_2 <= 1'b0;
      end
      if(when_Common_l259_1) begin
        defined_2 <= 1'b1;
      end
      if(clrAcc_3) begin
        defined_3 <= 1'b0;
      end
      if(when_Common_l259_2) begin
        defined_3 <= 1'b1;
      end
    end
  end


endmodule
