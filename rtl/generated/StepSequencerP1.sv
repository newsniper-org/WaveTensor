// Generator : SpinalHDL v1.14.2    git head : 78f29dc66110fc099a777992b6daa2f803ab445e
// Component : StepSequencerP1
// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
// 
// === 생성물이다. 손으로 고치지 말 것. ===
// 고칠 곳은 rtl/spinal/ 의 생성기이고, 고친 뒤 `make rtl-gen` 으로 다시 낸다.
// 여기 직접 쓴 수정은 다음 생성에서 조용히 사라진다.

`timescale 1ns/1ps

module StepSequencerP1 (
  input  wire          io_req_valid,
  input  wire [7:0]    io_req_opKind,
  input  wire [7:0]    io_req_precision,
  input  wire [31:0]   io_req_a,
  input  wire [31:0]   io_req_b,
  input  wire [31:0]   io_req_c,
  output wire          io_req_ready,
  output wire          io_oDone,
  output wire          io_oExecValid,
  output wire          io_oCapAbsent,
  output wire          io_oProgMal,
  output wire [31:0]   io_oResult,
  output wire          io_oBusy,
  input  wire          io_progWr_valid,
  input  wire [7:0]    io_progWr_slot,
  input  wire [7:0]    io_progWr_idx,
  input  wire [15:0]   io_progWr_step,
  input  wire          io_bindWr_valid,
  input  wire [15:0]   io_bindWr_key,
  input  wire          io_bindWr_en,
  input  wire [7:0]    io_bindWr_slot,
  output wire          io_loadReady,
  output wire          io_faultBpViolation,
  output wire          io_faultBadProg,
  input  wire          io_faultClearBp,
  input  wire          io_faultClearBadProg,
  input  wire          clk,
  input  wire          reset
);

  reg        [13:0]   progMem_spinal_port1;
  reg        [1:0]    selMem_spinal_port1;
  wire       [5:0]    _zz_progMem_port;
  wire       [13:0]   _zz_progMem_port_1;
  reg        [31:0]   _zz_opA;
  reg        [31:0]   _zz_opB;
  reg        [15:0]   initCnt;
  reg                 initDone;
  wire                when_StepSequencer_l280;
  wire                when_StepSequencer_l282;
  wire                stepResvBad;
  wire                progWrBad;
  wire                progWrOk;
  wire                bindWrBad;
  reg                 selWrEn;
  reg        [15:0]   selWrAddr;
  reg        [1:0]    selWrData;
  wire                when_StepSequencer_l317;
  wire                when_StepSequencer_l320;
  reg        [1:0]    state;
  wire                bpViolation;
  reg                 _zz_io_faultBpViolation;
  wire                accept;
  reg        [31:0]   scratch_0;
  reg        [31:0]   scratch_1;
  reg        [31:0]   scratch_2;
  reg        [31:0]   scratch_3;
  reg        [31:0]   scratch_4;
  reg        [31:0]   scratch_5;
  reg        [31:0]   scratch_6;
  reg        [31:0]   scratch_7;
  reg        [31:0]   scratch_8;
  reg        [31:0]   scratch_9;
  reg        [31:0]   scratch_10;
  reg        [31:0]   scratch_11;
  reg        [31:0]   scratch_12;
  reg        [31:0]   scratch_13;
  reg        [31:0]   scratch_14;
  reg        [31:0]   scratch_15;
  wire       [15:0]   key;
  wire       [15:0]   _zz_selRd;
  wire       [1:0]    selRd;
  wire                selV;
  wire       [0:0]    selSlot;
  reg        [0:0]    slotReg;
  reg        [4:0]    fetchPc;
  reg        [4:0]    execCnt;
  reg                 fetchEn;
  reg        [5:0]    fetchAddr;
  wire       [13:0]   stepWord;
  reg                 rDone;
  reg                 rCapa;
  reg                 rMal;
  reg        [31:0]   rResult;
  wire                when_StepSequencer_l387;
  wire                stLast;
  wire                stUnit;
  wire       [3:0]    stSrcA;
  wire       [3:0]    stSrcB;
  wire       [3:0]    stDst;
  wire       [31:0]   opA;
  wire       [31:0]   opB;
  wire       [63:0]   mulProd;
  wire       [31:0]   addSum;
  wire       [31:0]   wb;
  wire                when_StepSequencer_l433;
  wire       [15:0]   _zz_5;
  wire                when_StepSequencer_l444;
  wire                runaway;
  wire                when_Common_l337;
  reg                 _zz_io_faultBadProg;
  reg [13:0] progMem [0:63];
  reg [1:0] selMem [0:65535];

  assign _zz_progMem_port = {io_progWr_slot[0 : 0],io_progWr_idx[4 : 0]};
  assign _zz_progMem_port_1 = io_progWr_step[13 : 0];
  always @(posedge clk) begin
    if(progWrOk) begin
      progMem[_zz_progMem_port] <= _zz_progMem_port_1;
    end
  end

  always @(posedge clk) begin
    if(fetchEn) begin
      progMem_spinal_port1 <= progMem[fetchAddr];
    end
  end

  always @(posedge clk) begin
    if(selWrEn) begin
      selMem[selWrAddr] <= selWrData;
    end
  end

  always @(posedge clk) begin
    if(accept) begin
      selMem_spinal_port1 <= selMem[_zz_selRd];
    end
  end

  always @(*) begin
    case(stSrcA)
      4'b0000 : _zz_opA = scratch_0;
      4'b0001 : _zz_opA = scratch_1;
      4'b0010 : _zz_opA = scratch_2;
      4'b0011 : _zz_opA = scratch_3;
      4'b0100 : _zz_opA = scratch_4;
      4'b0101 : _zz_opA = scratch_5;
      4'b0110 : _zz_opA = scratch_6;
      4'b0111 : _zz_opA = scratch_7;
      4'b1000 : _zz_opA = scratch_8;
      4'b1001 : _zz_opA = scratch_9;
      4'b1010 : _zz_opA = scratch_10;
      4'b1011 : _zz_opA = scratch_11;
      4'b1100 : _zz_opA = scratch_12;
      4'b1101 : _zz_opA = scratch_13;
      4'b1110 : _zz_opA = scratch_14;
      default : _zz_opA = scratch_15;
    endcase
  end

  always @(*) begin
    case(stSrcB)
      4'b0000 : _zz_opB = scratch_0;
      4'b0001 : _zz_opB = scratch_1;
      4'b0010 : _zz_opB = scratch_2;
      4'b0011 : _zz_opB = scratch_3;
      4'b0100 : _zz_opB = scratch_4;
      4'b0101 : _zz_opB = scratch_5;
      4'b0110 : _zz_opB = scratch_6;
      4'b0111 : _zz_opB = scratch_7;
      4'b1000 : _zz_opB = scratch_8;
      4'b1001 : _zz_opB = scratch_9;
      4'b1010 : _zz_opB = scratch_10;
      4'b1011 : _zz_opB = scratch_11;
      4'b1100 : _zz_opB = scratch_12;
      4'b1101 : _zz_opB = scratch_13;
      4'b1110 : _zz_opB = scratch_14;
      default : _zz_opB = scratch_15;
    endcase
  end

  assign when_StepSequencer_l280 = (! initDone);
  assign when_StepSequencer_l282 = (initCnt == 16'hffff);
  assign io_loadReady = initDone;
  assign stepResvBad = (io_progWr_step[15 : 14] != 2'b00);
  assign progWrBad = ((io_progWr_valid && io_loadReady) && (((8'h01 <= io_progWr_slot) || (8'h20 <= io_progWr_idx)) || stepResvBad));
  assign progWrOk = ((io_progWr_valid && io_loadReady) && (! progWrBad));
  assign bindWrBad = (((io_bindWr_valid && io_loadReady) && io_bindWr_en) && (8'h01 <= io_bindWr_slot));
  always @(*) begin
    selWrEn = 1'b0;
    if(when_StepSequencer_l317) begin
      selWrEn = 1'b1;
    end else begin
      if(when_StepSequencer_l320) begin
        selWrEn = 1'b1;
      end
    end
  end

  always @(*) begin
    selWrAddr = 16'h0;
    if(when_StepSequencer_l317) begin
      selWrAddr = initCnt;
    end else begin
      if(when_StepSequencer_l320) begin
        selWrAddr = io_bindWr_key;
      end
    end
  end

  always @(*) begin
    selWrData = 2'b00;
    if(!when_StepSequencer_l317) begin
      if(when_StepSequencer_l320) begin
        if(io_bindWr_en) begin
          selWrData = {1'b1,io_bindWr_slot[0 : 0]};
        end
      end
    end
  end

  assign when_StepSequencer_l317 = (! initDone);
  assign when_StepSequencer_l320 = (io_bindWr_valid && (! bindWrBad));
  assign io_req_ready = (initDone && (state == 2'b00));
  assign io_oBusy = (state != 2'b00);
  assign bpViolation = (io_req_valid && (! io_req_ready));
  assign io_faultBpViolation = _zz_io_faultBpViolation;
  assign accept = (io_req_valid && io_req_ready);
  assign key = {io_req_opKind,io_req_precision};
  assign _zz_selRd = key;
  assign selRd = selMem_spinal_port1;
  assign selV = selRd[1];
  assign selSlot = selRd[0 : 0];
  always @(*) begin
    fetchEn = 1'b0;
    if(when_StepSequencer_l387) begin
      if(selV) begin
        fetchEn = 1'b1;
      end
    end
    if(when_StepSequencer_l433) begin
      if(!stLast) begin
        if(!when_StepSequencer_l444) begin
          fetchEn = 1'b1;
        end
      end
    end
  end

  always @(*) begin
    fetchAddr = {slotReg,fetchPc};
    if(when_StepSequencer_l387) begin
      if(selV) begin
        fetchAddr = {selSlot,5'h0};
      end
    end
  end

  assign stepWord = progMem_spinal_port1;
  assign when_StepSequencer_l387 = (state == 2'b01);
  assign stLast = stepWord[0];
  assign stUnit = stepWord[1];
  assign stSrcA = stepWord[5 : 2];
  assign stSrcB = stepWord[9 : 6];
  assign stDst = stepWord[13 : 10];
  assign opA = _zz_opA;
  assign opB = _zz_opB;
  assign mulProd = (opA * opB);
  assign addSum = (opA + opB);
  assign wb = (stUnit ? mulProd[31 : 0] : addSum);
  assign when_StepSequencer_l433 = (state == 2'b10);
  assign _zz_5 = ({15'd0,1'b1} <<< stDst);
  assign when_StepSequencer_l444 = (execCnt == 5'h1f);
  assign runaway = (((state == 2'b10) && (! stLast)) && (execCnt == 5'h1f));
  assign when_Common_l337 = ((progWrBad || bindWrBad) || runaway);
  assign io_faultBadProg = _zz_io_faultBadProg;
  assign io_oDone = rDone;
  assign io_oCapAbsent = (rDone && rCapa);
  assign io_oProgMal = (rDone && rMal);
  assign io_oExecValid = ((rDone && (! rCapa)) && (! rMal));
  assign io_oResult = rResult;
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      initCnt <= 16'h0;
      initDone <= 1'b0;
      state <= 2'b00;
      _zz_io_faultBpViolation <= 1'b0;
      scratch_0 <= 32'h0;
      scratch_1 <= 32'h0;
      scratch_2 <= 32'h0;
      scratch_3 <= 32'h0;
      scratch_4 <= 32'h0;
      scratch_5 <= 32'h0;
      scratch_6 <= 32'h0;
      scratch_7 <= 32'h0;
      scratch_8 <= 32'h0;
      scratch_9 <= 32'h0;
      scratch_10 <= 32'h0;
      scratch_11 <= 32'h0;
      scratch_12 <= 32'h0;
      scratch_13 <= 32'h0;
      scratch_14 <= 32'h0;
      scratch_15 <= 32'h0;
      slotReg <= 1'b0;
      fetchPc <= 5'h0;
      execCnt <= 5'h0;
      rDone <= 1'b0;
      rCapa <= 1'b0;
      rMal <= 1'b0;
      rResult <= 32'h0;
      _zz_io_faultBadProg <= 1'b0;
    end else begin
      if(when_StepSequencer_l280) begin
        initCnt <= (initCnt + 16'h0001);
        if(when_StepSequencer_l282) begin
          initDone <= 1'b1;
        end
      end
      if(io_faultClearBp) begin
        _zz_io_faultBpViolation <= 1'b0;
      end
      if(bpViolation) begin
        _zz_io_faultBpViolation <= 1'b1;
      end
      if(accept) begin
        scratch_0 <= io_req_a;
        scratch_1 <= io_req_b;
        scratch_2 <= io_req_c;
        state <= 2'b01;
      end
      rDone <= 1'b0;
      rCapa <= 1'b0;
      rMal <= 1'b0;
      if(when_StepSequencer_l387) begin
        if(selV) begin
          slotReg <= selSlot;
          fetchPc <= 5'h01;
          execCnt <= 5'h0;
          state <= 2'b10;
        end else begin
          rDone <= 1'b1;
          rCapa <= 1'b1;
          state <= 2'b00;
        end
      end
      if(when_StepSequencer_l433) begin
        if(_zz_5[0]) begin
          scratch_0 <= wb;
        end
        if(_zz_5[1]) begin
          scratch_1 <= wb;
        end
        if(_zz_5[2]) begin
          scratch_2 <= wb;
        end
        if(_zz_5[3]) begin
          scratch_3 <= wb;
        end
        if(_zz_5[4]) begin
          scratch_4 <= wb;
        end
        if(_zz_5[5]) begin
          scratch_5 <= wb;
        end
        if(_zz_5[6]) begin
          scratch_6 <= wb;
        end
        if(_zz_5[7]) begin
          scratch_7 <= wb;
        end
        if(_zz_5[8]) begin
          scratch_8 <= wb;
        end
        if(_zz_5[9]) begin
          scratch_9 <= wb;
        end
        if(_zz_5[10]) begin
          scratch_10 <= wb;
        end
        if(_zz_5[11]) begin
          scratch_11 <= wb;
        end
        if(_zz_5[12]) begin
          scratch_12 <= wb;
        end
        if(_zz_5[13]) begin
          scratch_13 <= wb;
        end
        if(_zz_5[14]) begin
          scratch_14 <= wb;
        end
        if(_zz_5[15]) begin
          scratch_15 <= wb;
        end
        if(stUnit) begin
          scratch_15 <= mulProd[63 : 32];
        end
        if(stLast) begin
          rResult <= wb;
          rDone <= 1'b1;
          state <= 2'b00;
        end else begin
          if(when_StepSequencer_l444) begin
            rDone <= 1'b1;
            rMal <= 1'b1;
            state <= 2'b00;
          end else begin
            execCnt <= (execCnt + 5'h01);
            fetchPc <= (fetchPc + 5'h01);
          end
        end
      end
      if(io_faultClearBadProg) begin
        _zz_io_faultBadProg <= 1'b0;
      end
      if(when_Common_l337) begin
        _zz_io_faultBadProg <= 1'b1;
      end
    end
  end


endmodule
