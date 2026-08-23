// Generator : SpinalHDL v1.14.2    git head : 78f29dc66110fc099a777992b6daa2f803ab445e
// Component : OwnershipTable
// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
// 
// === 생성물이다. 손으로 고치지 말 것. ===
// 고칠 곳은 rtl/spinal/ 의 생성기이고, 고친 뒤 `make rtl-gen` 으로 다시 낸다.
// 여기 직접 쓴 수정은 다음 생성에서 조용히 사라진다.

`timescale 1ns/1ps

module OwnershipTable (
  input  wire [11:0]   io_addr,
  input  wire          io_wstrobe,
  input  wire [31:0]   io_wdata,
  input  wire          io_rstrobe,
  output reg  [31:0]   io_rdata,
  output wire          io_rvalid,
  output wire          io_ready,
  input  wire [31:0]   io_query_frame,
  output wire          io_query_devOwned,
  output wire          io_faultCollide,
  input  wire          io_faultClearCollide,
  input  wire          clk,
  input  wire          reset
);

  reg        [24:0]   _zz_io_query_devOwned;
  reg        [24:0]   _zz_chkTag;
  reg        [63:0]   validBits;
  reg        [24:0]   tagVec_0;
  reg        [24:0]   tagVec_1;
  reg        [24:0]   tagVec_2;
  reg        [24:0]   tagVec_3;
  reg        [24:0]   tagVec_4;
  reg        [24:0]   tagVec_5;
  reg        [24:0]   tagVec_6;
  reg        [24:0]   tagVec_7;
  reg        [24:0]   tagVec_8;
  reg        [24:0]   tagVec_9;
  reg        [24:0]   tagVec_10;
  reg        [24:0]   tagVec_11;
  reg        [24:0]   tagVec_12;
  reg        [24:0]   tagVec_13;
  reg        [24:0]   tagVec_14;
  reg        [24:0]   tagVec_15;
  reg        [24:0]   tagVec_16;
  reg        [24:0]   tagVec_17;
  reg        [24:0]   tagVec_18;
  reg        [24:0]   tagVec_19;
  reg        [24:0]   tagVec_20;
  reg        [24:0]   tagVec_21;
  reg        [24:0]   tagVec_22;
  reg        [24:0]   tagVec_23;
  reg        [24:0]   tagVec_24;
  reg        [24:0]   tagVec_25;
  reg        [24:0]   tagVec_26;
  reg        [24:0]   tagVec_27;
  reg        [24:0]   tagVec_28;
  reg        [24:0]   tagVec_29;
  reg        [24:0]   tagVec_30;
  reg        [24:0]   tagVec_31;
  reg        [24:0]   tagVec_32;
  reg        [24:0]   tagVec_33;
  reg        [24:0]   tagVec_34;
  reg        [24:0]   tagVec_35;
  reg        [24:0]   tagVec_36;
  reg        [24:0]   tagVec_37;
  reg        [24:0]   tagVec_38;
  reg        [24:0]   tagVec_39;
  reg        [24:0]   tagVec_40;
  reg        [24:0]   tagVec_41;
  reg        [24:0]   tagVec_42;
  reg        [24:0]   tagVec_43;
  reg        [24:0]   tagVec_44;
  reg        [24:0]   tagVec_45;
  reg        [24:0]   tagVec_46;
  reg        [24:0]   tagVec_47;
  reg        [24:0]   tagVec_48;
  reg        [24:0]   tagVec_49;
  reg        [24:0]   tagVec_50;
  reg        [24:0]   tagVec_51;
  reg        [24:0]   tagVec_52;
  reg        [24:0]   tagVec_53;
  reg        [24:0]   tagVec_54;
  reg        [24:0]   tagVec_55;
  reg        [24:0]   tagVec_56;
  reg        [24:0]   tagVec_57;
  reg        [24:0]   tagVec_58;
  reg        [24:0]   tagVec_59;
  reg        [24:0]   tagVec_60;
  reg        [24:0]   tagVec_61;
  reg        [24:0]   tagVec_62;
  reg        [24:0]   tagVec_63;
  wire       [5:0]    qIdx;
  wire       [24:0]   qTagLow;
  wire                qHighZero;
  wire                aligned;
  wire                region;
  wire       [5:0]    word;
  wire                acceptW;
  wire                acceptR;
  reg        [31:0]   idxReg;
  wire                when_OwnershipTable_l203;
  wire       [30:0]   wFrame;
  wire       [5:0]    wIdx;
  wire       [24:0]   wTag;
  wire       [31:0]   idxFrm;
  reg        [5:0]    chkAddr;
  wire       [24:0]   chkTag;
  wire       [24:0]   idxTagLow;
  wire                idxHigh0;
  wire                devStateAtIdx;
  reg        [1:0]    rdSel;
  reg                 rState;
  reg                 acceptR_regNext;
  wire                when_OwnershipTable_l232;
  wire                when_OwnershipTable_l233;
  wire                when_OwnershipTable_l234;
  reg                 collide;
  wire                dataWr;
  wire                slotBusy;
  wire                slotMine;
  wire                when_OwnershipTable_l251;
  wire                when_OwnershipTable_l253;
  wire       [63:0]   _zz_1;
  wire                when_OwnershipTable_l256;
  wire                when_OwnershipTable_l264;
  reg                 _zz_io_faultCollide;

  always @(*) begin
    case(qIdx)
      6'b000000 : _zz_io_query_devOwned = tagVec_0;
      6'b000001 : _zz_io_query_devOwned = tagVec_1;
      6'b000010 : _zz_io_query_devOwned = tagVec_2;
      6'b000011 : _zz_io_query_devOwned = tagVec_3;
      6'b000100 : _zz_io_query_devOwned = tagVec_4;
      6'b000101 : _zz_io_query_devOwned = tagVec_5;
      6'b000110 : _zz_io_query_devOwned = tagVec_6;
      6'b000111 : _zz_io_query_devOwned = tagVec_7;
      6'b001000 : _zz_io_query_devOwned = tagVec_8;
      6'b001001 : _zz_io_query_devOwned = tagVec_9;
      6'b001010 : _zz_io_query_devOwned = tagVec_10;
      6'b001011 : _zz_io_query_devOwned = tagVec_11;
      6'b001100 : _zz_io_query_devOwned = tagVec_12;
      6'b001101 : _zz_io_query_devOwned = tagVec_13;
      6'b001110 : _zz_io_query_devOwned = tagVec_14;
      6'b001111 : _zz_io_query_devOwned = tagVec_15;
      6'b010000 : _zz_io_query_devOwned = tagVec_16;
      6'b010001 : _zz_io_query_devOwned = tagVec_17;
      6'b010010 : _zz_io_query_devOwned = tagVec_18;
      6'b010011 : _zz_io_query_devOwned = tagVec_19;
      6'b010100 : _zz_io_query_devOwned = tagVec_20;
      6'b010101 : _zz_io_query_devOwned = tagVec_21;
      6'b010110 : _zz_io_query_devOwned = tagVec_22;
      6'b010111 : _zz_io_query_devOwned = tagVec_23;
      6'b011000 : _zz_io_query_devOwned = tagVec_24;
      6'b011001 : _zz_io_query_devOwned = tagVec_25;
      6'b011010 : _zz_io_query_devOwned = tagVec_26;
      6'b011011 : _zz_io_query_devOwned = tagVec_27;
      6'b011100 : _zz_io_query_devOwned = tagVec_28;
      6'b011101 : _zz_io_query_devOwned = tagVec_29;
      6'b011110 : _zz_io_query_devOwned = tagVec_30;
      6'b011111 : _zz_io_query_devOwned = tagVec_31;
      6'b100000 : _zz_io_query_devOwned = tagVec_32;
      6'b100001 : _zz_io_query_devOwned = tagVec_33;
      6'b100010 : _zz_io_query_devOwned = tagVec_34;
      6'b100011 : _zz_io_query_devOwned = tagVec_35;
      6'b100100 : _zz_io_query_devOwned = tagVec_36;
      6'b100101 : _zz_io_query_devOwned = tagVec_37;
      6'b100110 : _zz_io_query_devOwned = tagVec_38;
      6'b100111 : _zz_io_query_devOwned = tagVec_39;
      6'b101000 : _zz_io_query_devOwned = tagVec_40;
      6'b101001 : _zz_io_query_devOwned = tagVec_41;
      6'b101010 : _zz_io_query_devOwned = tagVec_42;
      6'b101011 : _zz_io_query_devOwned = tagVec_43;
      6'b101100 : _zz_io_query_devOwned = tagVec_44;
      6'b101101 : _zz_io_query_devOwned = tagVec_45;
      6'b101110 : _zz_io_query_devOwned = tagVec_46;
      6'b101111 : _zz_io_query_devOwned = tagVec_47;
      6'b110000 : _zz_io_query_devOwned = tagVec_48;
      6'b110001 : _zz_io_query_devOwned = tagVec_49;
      6'b110010 : _zz_io_query_devOwned = tagVec_50;
      6'b110011 : _zz_io_query_devOwned = tagVec_51;
      6'b110100 : _zz_io_query_devOwned = tagVec_52;
      6'b110101 : _zz_io_query_devOwned = tagVec_53;
      6'b110110 : _zz_io_query_devOwned = tagVec_54;
      6'b110111 : _zz_io_query_devOwned = tagVec_55;
      6'b111000 : _zz_io_query_devOwned = tagVec_56;
      6'b111001 : _zz_io_query_devOwned = tagVec_57;
      6'b111010 : _zz_io_query_devOwned = tagVec_58;
      6'b111011 : _zz_io_query_devOwned = tagVec_59;
      6'b111100 : _zz_io_query_devOwned = tagVec_60;
      6'b111101 : _zz_io_query_devOwned = tagVec_61;
      6'b111110 : _zz_io_query_devOwned = tagVec_62;
      default : _zz_io_query_devOwned = tagVec_63;
    endcase
  end

  always @(*) begin
    case(chkAddr)
      6'b000000 : _zz_chkTag = tagVec_0;
      6'b000001 : _zz_chkTag = tagVec_1;
      6'b000010 : _zz_chkTag = tagVec_2;
      6'b000011 : _zz_chkTag = tagVec_3;
      6'b000100 : _zz_chkTag = tagVec_4;
      6'b000101 : _zz_chkTag = tagVec_5;
      6'b000110 : _zz_chkTag = tagVec_6;
      6'b000111 : _zz_chkTag = tagVec_7;
      6'b001000 : _zz_chkTag = tagVec_8;
      6'b001001 : _zz_chkTag = tagVec_9;
      6'b001010 : _zz_chkTag = tagVec_10;
      6'b001011 : _zz_chkTag = tagVec_11;
      6'b001100 : _zz_chkTag = tagVec_12;
      6'b001101 : _zz_chkTag = tagVec_13;
      6'b001110 : _zz_chkTag = tagVec_14;
      6'b001111 : _zz_chkTag = tagVec_15;
      6'b010000 : _zz_chkTag = tagVec_16;
      6'b010001 : _zz_chkTag = tagVec_17;
      6'b010010 : _zz_chkTag = tagVec_18;
      6'b010011 : _zz_chkTag = tagVec_19;
      6'b010100 : _zz_chkTag = tagVec_20;
      6'b010101 : _zz_chkTag = tagVec_21;
      6'b010110 : _zz_chkTag = tagVec_22;
      6'b010111 : _zz_chkTag = tagVec_23;
      6'b011000 : _zz_chkTag = tagVec_24;
      6'b011001 : _zz_chkTag = tagVec_25;
      6'b011010 : _zz_chkTag = tagVec_26;
      6'b011011 : _zz_chkTag = tagVec_27;
      6'b011100 : _zz_chkTag = tagVec_28;
      6'b011101 : _zz_chkTag = tagVec_29;
      6'b011110 : _zz_chkTag = tagVec_30;
      6'b011111 : _zz_chkTag = tagVec_31;
      6'b100000 : _zz_chkTag = tagVec_32;
      6'b100001 : _zz_chkTag = tagVec_33;
      6'b100010 : _zz_chkTag = tagVec_34;
      6'b100011 : _zz_chkTag = tagVec_35;
      6'b100100 : _zz_chkTag = tagVec_36;
      6'b100101 : _zz_chkTag = tagVec_37;
      6'b100110 : _zz_chkTag = tagVec_38;
      6'b100111 : _zz_chkTag = tagVec_39;
      6'b101000 : _zz_chkTag = tagVec_40;
      6'b101001 : _zz_chkTag = tagVec_41;
      6'b101010 : _zz_chkTag = tagVec_42;
      6'b101011 : _zz_chkTag = tagVec_43;
      6'b101100 : _zz_chkTag = tagVec_44;
      6'b101101 : _zz_chkTag = tagVec_45;
      6'b101110 : _zz_chkTag = tagVec_46;
      6'b101111 : _zz_chkTag = tagVec_47;
      6'b110000 : _zz_chkTag = tagVec_48;
      6'b110001 : _zz_chkTag = tagVec_49;
      6'b110010 : _zz_chkTag = tagVec_50;
      6'b110011 : _zz_chkTag = tagVec_51;
      6'b110100 : _zz_chkTag = tagVec_52;
      6'b110101 : _zz_chkTag = tagVec_53;
      6'b110110 : _zz_chkTag = tagVec_54;
      6'b110111 : _zz_chkTag = tagVec_55;
      6'b111000 : _zz_chkTag = tagVec_56;
      6'b111001 : _zz_chkTag = tagVec_57;
      6'b111010 : _zz_chkTag = tagVec_58;
      6'b111011 : _zz_chkTag = tagVec_59;
      6'b111100 : _zz_chkTag = tagVec_60;
      6'b111101 : _zz_chkTag = tagVec_61;
      6'b111110 : _zz_chkTag = tagVec_62;
      default : _zz_chkTag = tagVec_63;
    endcase
  end

  assign io_ready = 1'b1;
  assign qIdx = io_query_frame[5 : 0];
  assign qTagLow = io_query_frame[30 : 6];
  assign qHighZero = (io_query_frame[31 : 31] == 1'b0);
  assign io_query_devOwned = ((validBits[qIdx] && (_zz_io_query_devOwned == qTagLow)) && qHighZero);
  assign aligned = (io_addr[1 : 0] == 2'b00);
  assign region = (io_addr[11 : 8] == 4'b0010);
  assign word = io_addr[7 : 2];
  assign acceptW = (io_ready && io_wstrobe);
  assign acceptR = ((io_ready && (! io_wstrobe)) && io_rstrobe);
  assign when_OwnershipTable_l203 = (((acceptW && aligned) && region) && (word == 6'h0));
  assign wFrame = io_wdata[30 : 0];
  assign wIdx = wFrame[5 : 0];
  assign wTag = wFrame[30 : 6];
  assign idxFrm = idxReg;
  always @(*) begin
    chkAddr = idxFrm[5 : 0];
    if(io_wstrobe) begin
      chkAddr = wIdx;
    end
  end

  assign chkTag = _zz_chkTag;
  assign idxTagLow = idxFrm[30 : 6];
  assign idxHigh0 = (idxFrm[31 : 31] == 1'b0);
  assign devStateAtIdx = ((validBits[chkAddr] && (chkTag == idxTagLow)) && idxHigh0);
  assign io_rvalid = acceptR_regNext;
  assign when_OwnershipTable_l232 = (aligned && region);
  assign when_OwnershipTable_l233 = (word == 6'h0);
  assign when_OwnershipTable_l234 = (word == 6'h01);
  always @(*) begin
    io_rdata = 32'h0;
    case(rdSel)
      2'b01 : begin
        io_rdata = idxReg;
      end
      2'b10 : begin
        io_rdata[0] = rState;
      end
      default : begin
      end
    endcase
  end

  always @(*) begin
    collide = 1'b0;
    if(dataWr) begin
      if(when_OwnershipTable_l251) begin
        if(!when_OwnershipTable_l253) begin
          if(when_OwnershipTable_l256) begin
            collide = 1'b1;
          end
        end
      end
    end
  end

  assign dataWr = (((acceptW && aligned) && region) && (word == 6'h01));
  assign slotBusy = validBits[wIdx];
  assign slotMine = (chkTag == wTag);
  assign when_OwnershipTable_l251 = io_wdata[31];
  assign when_OwnershipTable_l253 = (! slotBusy);
  assign _zz_1 = ({63'd0,1'b1} <<< wIdx);
  assign when_OwnershipTable_l256 = (! slotMine);
  assign when_OwnershipTable_l264 = (slotBusy && slotMine);
  assign io_faultCollide = _zz_io_faultCollide;
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      validBits <= 64'h0;
      tagVec_0 <= 25'h0;
      tagVec_1 <= 25'h0;
      tagVec_2 <= 25'h0;
      tagVec_3 <= 25'h0;
      tagVec_4 <= 25'h0;
      tagVec_5 <= 25'h0;
      tagVec_6 <= 25'h0;
      tagVec_7 <= 25'h0;
      tagVec_8 <= 25'h0;
      tagVec_9 <= 25'h0;
      tagVec_10 <= 25'h0;
      tagVec_11 <= 25'h0;
      tagVec_12 <= 25'h0;
      tagVec_13 <= 25'h0;
      tagVec_14 <= 25'h0;
      tagVec_15 <= 25'h0;
      tagVec_16 <= 25'h0;
      tagVec_17 <= 25'h0;
      tagVec_18 <= 25'h0;
      tagVec_19 <= 25'h0;
      tagVec_20 <= 25'h0;
      tagVec_21 <= 25'h0;
      tagVec_22 <= 25'h0;
      tagVec_23 <= 25'h0;
      tagVec_24 <= 25'h0;
      tagVec_25 <= 25'h0;
      tagVec_26 <= 25'h0;
      tagVec_27 <= 25'h0;
      tagVec_28 <= 25'h0;
      tagVec_29 <= 25'h0;
      tagVec_30 <= 25'h0;
      tagVec_31 <= 25'h0;
      tagVec_32 <= 25'h0;
      tagVec_33 <= 25'h0;
      tagVec_34 <= 25'h0;
      tagVec_35 <= 25'h0;
      tagVec_36 <= 25'h0;
      tagVec_37 <= 25'h0;
      tagVec_38 <= 25'h0;
      tagVec_39 <= 25'h0;
      tagVec_40 <= 25'h0;
      tagVec_41 <= 25'h0;
      tagVec_42 <= 25'h0;
      tagVec_43 <= 25'h0;
      tagVec_44 <= 25'h0;
      tagVec_45 <= 25'h0;
      tagVec_46 <= 25'h0;
      tagVec_47 <= 25'h0;
      tagVec_48 <= 25'h0;
      tagVec_49 <= 25'h0;
      tagVec_50 <= 25'h0;
      tagVec_51 <= 25'h0;
      tagVec_52 <= 25'h0;
      tagVec_53 <= 25'h0;
      tagVec_54 <= 25'h0;
      tagVec_55 <= 25'h0;
      tagVec_56 <= 25'h0;
      tagVec_57 <= 25'h0;
      tagVec_58 <= 25'h0;
      tagVec_59 <= 25'h0;
      tagVec_60 <= 25'h0;
      tagVec_61 <= 25'h0;
      tagVec_62 <= 25'h0;
      tagVec_63 <= 25'h0;
      idxReg <= 32'h0;
      rdSel <= 2'b00;
      rState <= 1'b0;
      acceptR_regNext <= 1'b0;
      _zz_io_faultCollide <= 1'b0;
    end else begin
      if(when_OwnershipTable_l203) begin
        idxReg <= io_wdata;
      end
      acceptR_regNext <= acceptR;
      if(acceptR) begin
        rdSel <= 2'b00;
        rState <= devStateAtIdx;
        if(when_OwnershipTable_l232) begin
          if(when_OwnershipTable_l233) begin
            rdSel <= 2'b01;
          end
          if(when_OwnershipTable_l234) begin
            rdSel <= 2'b10;
          end
        end
      end
      if(dataWr) begin
        if(when_OwnershipTable_l251) begin
          if(when_OwnershipTable_l253) begin
            validBits[wIdx] <= 1'b1;
            if(_zz_1[0]) begin
              tagVec_0 <= wTag;
            end
            if(_zz_1[1]) begin
              tagVec_1 <= wTag;
            end
            if(_zz_1[2]) begin
              tagVec_2 <= wTag;
            end
            if(_zz_1[3]) begin
              tagVec_3 <= wTag;
            end
            if(_zz_1[4]) begin
              tagVec_4 <= wTag;
            end
            if(_zz_1[5]) begin
              tagVec_5 <= wTag;
            end
            if(_zz_1[6]) begin
              tagVec_6 <= wTag;
            end
            if(_zz_1[7]) begin
              tagVec_7 <= wTag;
            end
            if(_zz_1[8]) begin
              tagVec_8 <= wTag;
            end
            if(_zz_1[9]) begin
              tagVec_9 <= wTag;
            end
            if(_zz_1[10]) begin
              tagVec_10 <= wTag;
            end
            if(_zz_1[11]) begin
              tagVec_11 <= wTag;
            end
            if(_zz_1[12]) begin
              tagVec_12 <= wTag;
            end
            if(_zz_1[13]) begin
              tagVec_13 <= wTag;
            end
            if(_zz_1[14]) begin
              tagVec_14 <= wTag;
            end
            if(_zz_1[15]) begin
              tagVec_15 <= wTag;
            end
            if(_zz_1[16]) begin
              tagVec_16 <= wTag;
            end
            if(_zz_1[17]) begin
              tagVec_17 <= wTag;
            end
            if(_zz_1[18]) begin
              tagVec_18 <= wTag;
            end
            if(_zz_1[19]) begin
              tagVec_19 <= wTag;
            end
            if(_zz_1[20]) begin
              tagVec_20 <= wTag;
            end
            if(_zz_1[21]) begin
              tagVec_21 <= wTag;
            end
            if(_zz_1[22]) begin
              tagVec_22 <= wTag;
            end
            if(_zz_1[23]) begin
              tagVec_23 <= wTag;
            end
            if(_zz_1[24]) begin
              tagVec_24 <= wTag;
            end
            if(_zz_1[25]) begin
              tagVec_25 <= wTag;
            end
            if(_zz_1[26]) begin
              tagVec_26 <= wTag;
            end
            if(_zz_1[27]) begin
              tagVec_27 <= wTag;
            end
            if(_zz_1[28]) begin
              tagVec_28 <= wTag;
            end
            if(_zz_1[29]) begin
              tagVec_29 <= wTag;
            end
            if(_zz_1[30]) begin
              tagVec_30 <= wTag;
            end
            if(_zz_1[31]) begin
              tagVec_31 <= wTag;
            end
            if(_zz_1[32]) begin
              tagVec_32 <= wTag;
            end
            if(_zz_1[33]) begin
              tagVec_33 <= wTag;
            end
            if(_zz_1[34]) begin
              tagVec_34 <= wTag;
            end
            if(_zz_1[35]) begin
              tagVec_35 <= wTag;
            end
            if(_zz_1[36]) begin
              tagVec_36 <= wTag;
            end
            if(_zz_1[37]) begin
              tagVec_37 <= wTag;
            end
            if(_zz_1[38]) begin
              tagVec_38 <= wTag;
            end
            if(_zz_1[39]) begin
              tagVec_39 <= wTag;
            end
            if(_zz_1[40]) begin
              tagVec_40 <= wTag;
            end
            if(_zz_1[41]) begin
              tagVec_41 <= wTag;
            end
            if(_zz_1[42]) begin
              tagVec_42 <= wTag;
            end
            if(_zz_1[43]) begin
              tagVec_43 <= wTag;
            end
            if(_zz_1[44]) begin
              tagVec_44 <= wTag;
            end
            if(_zz_1[45]) begin
              tagVec_45 <= wTag;
            end
            if(_zz_1[46]) begin
              tagVec_46 <= wTag;
            end
            if(_zz_1[47]) begin
              tagVec_47 <= wTag;
            end
            if(_zz_1[48]) begin
              tagVec_48 <= wTag;
            end
            if(_zz_1[49]) begin
              tagVec_49 <= wTag;
            end
            if(_zz_1[50]) begin
              tagVec_50 <= wTag;
            end
            if(_zz_1[51]) begin
              tagVec_51 <= wTag;
            end
            if(_zz_1[52]) begin
              tagVec_52 <= wTag;
            end
            if(_zz_1[53]) begin
              tagVec_53 <= wTag;
            end
            if(_zz_1[54]) begin
              tagVec_54 <= wTag;
            end
            if(_zz_1[55]) begin
              tagVec_55 <= wTag;
            end
            if(_zz_1[56]) begin
              tagVec_56 <= wTag;
            end
            if(_zz_1[57]) begin
              tagVec_57 <= wTag;
            end
            if(_zz_1[58]) begin
              tagVec_58 <= wTag;
            end
            if(_zz_1[59]) begin
              tagVec_59 <= wTag;
            end
            if(_zz_1[60]) begin
              tagVec_60 <= wTag;
            end
            if(_zz_1[61]) begin
              tagVec_61 <= wTag;
            end
            if(_zz_1[62]) begin
              tagVec_62 <= wTag;
            end
            if(_zz_1[63]) begin
              tagVec_63 <= wTag;
            end
          end
        end else begin
          if(when_OwnershipTable_l264) begin
            validBits[wIdx] <= 1'b0;
          end
        end
      end
      if(io_faultClearCollide) begin
        _zz_io_faultCollide <= 1'b0;
      end
      if(collide) begin
        _zz_io_faultCollide <= 1'b1;
      end
    end
  end


endmodule
