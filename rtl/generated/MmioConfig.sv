// Generator : SpinalHDL v1.14.2    git head : 78f29dc66110fc099a777992b6daa2f803ab445e
// Component : MmioConfig
// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
// 
// === 생성물이다. 손으로 고치지 말 것. ===
// 고칠 곳은 rtl/spinal/ 의 생성기이고, 고친 뒤 `make rtl-gen` 으로 다시 낸다.
// 여기 직접 쓴 수정은 다음 생성에서 조용히 사라진다.

`timescale 1ns/1ps

module MmioConfig (
  input  wire [11:0]   io_addr,
  input  wire          io_wstrobe,
  input  wire [31:0]   io_wdata,
  input  wire          io_rstrobe,
  output reg  [31:0]   io_rdata,
  output wire          io_rvalid,
  output wire          io_ready,
  output reg           io_viewWr_valid,
  output reg  [3:0]    io_viewWr_idx,
  output reg           io_viewWr_en,
  output reg  [15:0]   io_viewWr_lnid,
  output reg           io_bankWr_valid,
  output reg  [7:0]    io_bankWr_lbid,
  output reg           io_bankWr_mapped,
  output wire          io_faultDupOwner,
  output wire          io_faultBadWrite,
  input  wire          io_faultClearDup,
  input  wire          io_faultClearBad,
  input  wire          clk,
  input  wire          reset
);

  reg        [31:0]   fwdMem_spinal_port0;
  reg        [0:0]    revMem_spinal_port0;
  reg        [31:0]   lbidMem_spinal_port0;
  reg        [15:0]   initCnt;
  reg                 initDone;
  wire                sweeping;
  wire                when_MmioConfig_l175;
  reg                 revWrEn;
  reg        [15:0]   revWrAddr;
  reg        [0:0]    revWrData;
  reg                 fwdWrEn;
  reg        [7:0]    fwdWrAddr;
  reg        [31:0]   fwdWrData;
  reg                 lbWrEn;
  reg        [7:0]    lbWrAddr;
  reg        [31:0]   lbWrData;
  wire                when_MmioConfig_l202;
  reg                 busy;
  wire                aligned;
  wire       [1:0]    region;
  wire       [7:0]    wordIdx;
  wire                acceptW;
  wire                acceptR;
  wire                memRdEn;
  wire       [31:0]   fwdRd;
  wire       [31:0]   lbRd;
  reg        [1:0]    rdSel;
  reg                 acceptR_regNext;
  wire                lbidWrite;
  wire                lnidWrite;
  reg        [7:0]    pSlot;
  reg        [31:0]   pWord;
  wire                pV;
  wire       [7:0]    pPoint;
  wire       [15:0]   pLnid;
  wire       [15:0]   revChkAddr;
  wire       [0:0]    revChk;
  wire                revChkPresent;
  wire                oldV;
  wire       [15:0]   oldLnid;
  reg                 chkDupOwn;
  reg                 chkBadWr;
  wire                when_MmioConfig_l311;
  reg                 _zz_io_faultDupOwner;
  reg                 _zz_io_faultBadWrite;
  reg [31:0] fwdMem [0:255];
  reg [0:0] revMem [0:65535];
  reg [31:0] lbidMem [0:255];

  always @(posedge clk) begin
    if(memRdEn) begin
      fwdMem_spinal_port0 <= fwdMem[wordIdx];
    end
  end

  always @(posedge clk) begin
    if(fwdWrEn) begin
      fwdMem[fwdWrAddr] <= fwdWrData;
    end
  end

  always @(posedge clk) begin
    if(memRdEn) begin
      revMem_spinal_port0 <= revMem[revChkAddr];
    end
  end

  always @(posedge clk) begin
    if(revWrEn) begin
      revMem[revWrAddr] <= revWrData;
    end
  end

  always @(posedge clk) begin
    if(memRdEn) begin
      lbidMem_spinal_port0 <= lbidMem[wordIdx];
    end
  end

  always @(posedge clk) begin
    if(lbWrEn) begin
      lbidMem[lbWrAddr] <= lbWrData;
    end
  end

  assign sweeping = (! initDone);
  assign when_MmioConfig_l175 = (initCnt == 16'hffff);
  always @(*) begin
    revWrEn = 1'b0;
    if(sweeping) begin
      revWrEn = 1'b1;
    end
    if(busy) begin
      if(pV) begin
        if(!when_MmioConfig_l311) begin
          if(!revChkPresent) begin
            revWrEn = 1'b1;
          end
        end
      end else begin
        if(oldV) begin
          revWrEn = 1'b1;
        end
      end
    end
  end

  always @(*) begin
    revWrAddr = 16'h0;
    if(sweeping) begin
      revWrAddr = initCnt;
    end
    if(busy) begin
      if(pV) begin
        if(!when_MmioConfig_l311) begin
          if(!revChkPresent) begin
            revWrAddr = pLnid;
          end
        end
      end else begin
        if(oldV) begin
          revWrAddr = oldLnid;
        end
      end
    end
  end

  always @(*) begin
    revWrData = 1'b0;
    if(busy) begin
      if(pV) begin
        if(!when_MmioConfig_l311) begin
          if(!revChkPresent) begin
            revWrData = 1'b1;
          end
        end
      end else begin
        if(oldV) begin
          revWrData = 1'b0;
        end
      end
    end
  end

  always @(*) begin
    fwdWrEn = 1'b0;
    if(sweeping) begin
      if(when_MmioConfig_l202) begin
        fwdWrEn = 1'b1;
      end
    end
    if(busy) begin
      if(pV) begin
        if(!when_MmioConfig_l311) begin
          if(!revChkPresent) begin
            fwdWrEn = 1'b1;
          end
        end
      end else begin
        if(oldV) begin
          fwdWrEn = 1'b1;
        end
      end
    end
  end

  always @(*) begin
    fwdWrAddr = 8'h0;
    if(sweeping) begin
      if(when_MmioConfig_l202) begin
        fwdWrAddr = initCnt[7:0];
      end
    end
    if(busy) begin
      if(pV) begin
        if(!when_MmioConfig_l311) begin
          if(!revChkPresent) begin
            fwdWrAddr = pSlot;
          end
        end
      end else begin
        if(oldV) begin
          fwdWrAddr = pSlot;
        end
      end
    end
  end

  always @(*) begin
    fwdWrData = 32'h0;
    if(busy) begin
      if(pV) begin
        if(!when_MmioConfig_l311) begin
          if(!revChkPresent) begin
            fwdWrData = pWord;
          end
        end
      end else begin
        if(oldV) begin
          fwdWrData = 32'h0;
        end
      end
    end
  end

  always @(*) begin
    lbWrEn = 1'b0;
    if(sweeping) begin
      if(when_MmioConfig_l202) begin
        lbWrEn = 1'b1;
      end
    end
    if(lbidWrite) begin
      lbWrEn = 1'b1;
    end
  end

  always @(*) begin
    lbWrAddr = 8'h0;
    if(sweeping) begin
      if(when_MmioConfig_l202) begin
        lbWrAddr = initCnt[7:0];
      end
    end
    if(lbidWrite) begin
      lbWrAddr = wordIdx;
    end
  end

  always @(*) begin
    lbWrData = 32'h0;
    if(lbidWrite) begin
      lbWrData = (io_wdata & 32'h8000ffff);
    end
  end

  assign when_MmioConfig_l202 = (initCnt < 16'h0100);
  assign io_ready = (initDone && (! busy));
  assign aligned = (io_addr[1 : 0] == 2'b00);
  assign region = io_addr[11 : 10];
  assign wordIdx = io_addr[9 : 2];
  assign acceptW = (io_ready && io_wstrobe);
  assign acceptR = ((io_ready && (! io_wstrobe)) && io_rstrobe);
  assign memRdEn = (acceptR || acceptW);
  assign fwdRd = fwdMem_spinal_port0;
  assign lbRd = lbidMem_spinal_port0;
  assign io_rvalid = acceptR_regNext;
  always @(*) begin
    io_rdata = 32'h0;
    case(rdSel)
      2'b01 : begin
        io_rdata = fwdRd;
      end
      2'b10 : begin
        io_rdata = lbRd;
      end
      default : begin
      end
    endcase
  end

  always @(*) begin
    io_viewWr_valid = 1'b0;
    if(busy) begin
      if(pV) begin
        if(!when_MmioConfig_l311) begin
          if(!revChkPresent) begin
            io_viewWr_valid = 1'b1;
          end
        end
      end else begin
        if(oldV) begin
          io_viewWr_valid = 1'b1;
        end
      end
    end
  end

  always @(*) begin
    io_viewWr_idx = 4'b0000;
    if(busy) begin
      if(pV) begin
        if(!when_MmioConfig_l311) begin
          if(!revChkPresent) begin
            io_viewWr_idx = pSlot[3:0];
          end
        end
      end else begin
        if(oldV) begin
          io_viewWr_idx = pSlot[3:0];
        end
      end
    end
  end

  always @(*) begin
    io_viewWr_en = 1'b0;
    if(busy) begin
      if(pV) begin
        if(!when_MmioConfig_l311) begin
          if(!revChkPresent) begin
            io_viewWr_en = 1'b1;
          end
        end
      end else begin
        if(oldV) begin
          io_viewWr_en = 1'b0;
        end
      end
    end
  end

  always @(*) begin
    io_viewWr_lnid = 16'h0;
    if(busy) begin
      if(pV) begin
        if(!when_MmioConfig_l311) begin
          if(!revChkPresent) begin
            io_viewWr_lnid = pLnid;
          end
        end
      end else begin
        if(oldV) begin
          io_viewWr_lnid = oldLnid;
        end
      end
    end
  end

  always @(*) begin
    io_bankWr_valid = 1'b0;
    if(lbidWrite) begin
      io_bankWr_valid = 1'b1;
    end
  end

  always @(*) begin
    io_bankWr_lbid = 8'h0;
    if(lbidWrite) begin
      io_bankWr_lbid = wordIdx;
    end
  end

  always @(*) begin
    io_bankWr_mapped = 1'b0;
    if(lbidWrite) begin
      io_bankWr_mapped = io_wdata[31];
    end
  end

  assign lbidWrite = ((acceptW && aligned) && (region == 2'b10));
  assign lnidWrite = ((acceptW && aligned) && (region == 2'b01));
  assign pV = pWord[31];
  assign pPoint = pWord[23 : 16];
  assign pLnid = pWord[15 : 0];
  assign revChkAddr = io_wdata[15 : 0];
  assign revChk = revMem_spinal_port0;
  assign revChkPresent = revChk[0];
  assign oldV = fwdRd[31];
  assign oldLnid = fwdRd[15 : 0];
  always @(*) begin
    chkDupOwn = 1'b0;
    if(busy) begin
      if(pV) begin
        if(!when_MmioConfig_l311) begin
          if(revChkPresent) begin
            chkDupOwn = 1'b1;
          end
        end
      end
    end
  end

  always @(*) begin
    chkBadWr = 1'b0;
    if(busy) begin
      if(pV) begin
        if(when_MmioConfig_l311) begin
          chkBadWr = 1'b1;
        end
      end
    end
  end

  assign when_MmioConfig_l311 = (((8'h10 <= pSlot) || oldV) || (8'h04 <= pPoint));
  assign io_faultDupOwner = _zz_io_faultDupOwner;
  assign io_faultBadWrite = _zz_io_faultBadWrite;
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      initCnt <= 16'h0;
      initDone <= 1'b0;
      busy <= 1'b0;
      rdSel <= 2'b00;
      acceptR_regNext <= 1'b0;
      pSlot <= 8'h0;
      pWord <= 32'h0;
      _zz_io_faultDupOwner <= 1'b0;
      _zz_io_faultBadWrite <= 1'b0;
    end else begin
      if(sweeping) begin
        initCnt <= (initCnt + 16'h0001);
        if(when_MmioConfig_l175) begin
          initDone <= 1'b1;
        end
      end
      acceptR_regNext <= acceptR;
      if(acceptR) begin
        rdSel <= 2'b00;
        if(aligned) begin
          rdSel <= region;
        end
      end
      if(lnidWrite) begin
        busy <= 1'b1;
        pSlot <= wordIdx;
        pWord <= (io_wdata & 32'h80ffffff);
      end
      if(busy) begin
        busy <= 1'b0;
      end
      if(io_faultClearDup) begin
        _zz_io_faultDupOwner <= 1'b0;
      end
      if(chkDupOwn) begin
        _zz_io_faultDupOwner <= 1'b1;
      end
      if(io_faultClearBad) begin
        _zz_io_faultBadWrite <= 1'b0;
      end
      if(chkBadWr) begin
        _zz_io_faultBadWrite <= 1'b1;
      end
    end
  end


endmodule
