// Generator : SpinalHDL v1.14.2    git head : 78f29dc66110fc099a777992b6daa2f803ab445e
// Component : CompletionUnit
// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
// 
// === 생성물이다. 손으로 고치지 말 것. ===
// 고칠 곳은 rtl/spinal/ 의 생성기이고, 고친 뒤 `make rtl-gen` 으로 다시 낸다.
// 여기 직접 쓴 수정은 다음 생성에서 조용히 사라진다.

`timescale 1ns/1ps

module CompletionUnit (
  input  wire [7:0]    io_addr,
  input  wire          io_wstrobe,
  input  wire [31:0]   io_wdata,
  input  wire          io_rstrobe,
  output wire [31:0]   io_rdata,
  output wire          io_rvalid,
  output wire          io_ready,
  input  wire          io_comp_valid,
  input  wire [255:0]  io_comp_payload,
  output wire          io_comp_ready,
  output wire          io_irq,
  input  wire [15:0]   io_drain_pipe,
  input  wire [15:0]   io_drain_pending,
  input  wire [15:0]   io_drain_output,
  input  wire [15:0]   io_drain_ownSlots,
  input  wire [15:0]   io_drain_contexts,
  input  wire [15:0]   io_drain_tokens,
  output wire          io_faultOverflow,
  input  wire          clk,
  input  wire          reset
);

  reg        [255:0]  ring_spinal_port1;
  wire       [2:0]    _zz_full;
  wire       [31:0]   _zz_readValue;
  wire       [0:0]    _zz_readValue_1;
  wire       [0:0]    _zz_readValue_2;
  wire       [31:0]   _zz_readValue_3;
  wire       [0:0]    _zz_readValue_4;
  wire       [31:0]   _zz_readValue_5;
  wire       [31:0]   _zz_readValue_6;
  wire       [31:0]   _zz_readValue_7;
  wire       [31:0]   _zz_readValue_8;
  wire       [31:0]   _zz_readValue_9;
  wire       [31:0]   _zz_readValue_10;
  reg        [31:0]   _zz_io_rdata;
  reg        [31:0]   headReg;
  wire       [2:0]    head;
  reg        [2:0]    tail;
  wire                empty;
  wire                full;
  wire       [2:0]    occ;
  wire                doPush;
  wire                shove;
  wire                aligned;
  wire                acceptR;
  wire                doWr;
  wire                irqClrPulse;
  wire                fltClrPulse;
  reg        [31:0]   irqMaskReg;
  wire                irqMask;
  reg                 irqSticky;
  reg                 faultOv;
  wire                allZero;
  reg        [31:0]   readValue;
  wire                isWindow;
  wire       [255:0]  ringRd;
  reg        [31:0]   rdataReg;
  reg                 winSel;
  reg        [2:0]    winWord;
  reg                 acceptR_regNext;
  reg [255:0] ring [0:7];

  assign _zz_full = (tail + 3'b001);
  assign _zz_readValue = {29'd0, tail};
  assign _zz_readValue_1 = irqSticky;
  assign _zz_readValue_2 = faultOv;
  assign _zz_readValue_3 = {29'd0, occ};
  assign _zz_readValue_4 = allZero;
  assign _zz_readValue_5 = {16'd0, io_drain_pipe};
  assign _zz_readValue_6 = {16'd0, io_drain_pending};
  assign _zz_readValue_7 = {16'd0, io_drain_output};
  assign _zz_readValue_8 = {16'd0, io_drain_ownSlots};
  assign _zz_readValue_9 = {16'd0, io_drain_contexts};
  assign _zz_readValue_10 = {16'd0, io_drain_tokens};
  always @(posedge clk) begin
    if(doPush) begin
      ring[tail] <= io_comp_payload;
    end
  end

  always @(posedge clk) begin
    if(acceptR) begin
      ring_spinal_port1 <= ring[head];
    end
  end

  always @(*) begin
    case(winWord)
      3'b000 : _zz_io_rdata = ringRd[31 : 0];
      3'b001 : _zz_io_rdata = ringRd[63 : 32];
      3'b010 : _zz_io_rdata = ringRd[95 : 64];
      3'b011 : _zz_io_rdata = ringRd[127 : 96];
      3'b100 : _zz_io_rdata = ringRd[159 : 128];
      3'b101 : _zz_io_rdata = ringRd[191 : 160];
      3'b110 : _zz_io_rdata = ringRd[223 : 192];
      default : _zz_io_rdata = ringRd[255 : 224];
    endcase
  end

  assign io_ready = 1'b1;
  assign head = headReg[2 : 0];
  assign empty = (head == tail);
  assign full = (_zz_full == head);
  assign occ = (tail - head);
  assign io_comp_ready = (! full);
  assign doPush = (io_comp_valid && (! full));
  assign shove = (io_comp_valid && full);
  assign aligned = (io_addr[1 : 0] == 2'b00);
  assign acceptR = ((! io_wstrobe) && io_rstrobe);
  assign doWr = (io_wstrobe && aligned);
  assign irqClrPulse = ((doWr && (io_addr == 8'h18)) && io_wdata[0]);
  assign fltClrPulse = ((doWr && (io_addr == 8'h20)) && io_wdata[0]);
  assign irqMask = irqMaskReg[0];
  assign io_irq = (irqSticky && (! irqMask));
  assign io_faultOverflow = faultOv;
  assign allZero = (((((((io_drain_pipe == 16'h0) && (io_drain_pending == 16'h0)) && (io_drain_output == 16'h0)) && (io_drain_ownSlots == 16'h0)) && (io_drain_contexts == 16'h0)) && (io_drain_tokens == 16'h0)) && (occ == 3'b000));
  always @(*) begin
    readValue = 32'h0;
    if(aligned) begin
      case(io_addr)
        8'h0 : begin
          readValue = 32'h00000008;
        end
        8'h04 : begin
          readValue = headReg;
        end
        8'h08 : begin
          readValue = _zz_readValue;
        end
        8'h10 : begin
          readValue = {31'd0, _zz_readValue_1};
        end
        8'h14 : begin
          readValue = irqMaskReg;
        end
        8'h1c : begin
          readValue = {31'd0, _zz_readValue_2};
        end
        8'h78 : begin
          readValue = _zz_readValue_3;
        end
        8'h7c : begin
          readValue = {31'd0, _zz_readValue_4};
        end
        8'h60 : begin
          readValue = _zz_readValue_5;
        end
        8'h64 : begin
          readValue = _zz_readValue_6;
        end
        8'h68 : begin
          readValue = _zz_readValue_7;
        end
        8'h6c : begin
          readValue = _zz_readValue_8;
        end
        8'h70 : begin
          readValue = _zz_readValue_9;
        end
        8'h74 : begin
          readValue = _zz_readValue_10;
        end
        default : begin
        end
      endcase
    end
  end

  assign isWindow = (io_addr[7 : 5] == 3'b010);
  assign ringRd = ring_spinal_port1;
  assign io_rvalid = acceptR_regNext;
  assign io_rdata = (winSel ? _zz_io_rdata : rdataReg);
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      headReg <= 32'h0;
      tail <= 3'b000;
      irqMaskReg <= 32'h00000001;
      irqSticky <= 1'b0;
      faultOv <= 1'b0;
      rdataReg <= 32'h0;
      winSel <= 1'b0;
      winWord <= 3'b000;
      acceptR_regNext <= 1'b0;
    end else begin
      if(doPush) begin
        tail <= (tail + 3'b001);
      end
      if(doWr) begin
        case(io_addr)
          8'h04 : begin
            headReg <= (io_wdata & 32'h00000007);
          end
          8'h14 : begin
            irqMaskReg <= (io_wdata & 32'h00000001);
          end
          default : begin
          end
        endcase
      end
      if(irqClrPulse) begin
        irqSticky <= 1'b0;
      end
      if(doPush) begin
        irqSticky <= 1'b1;
      end
      if(fltClrPulse) begin
        faultOv <= 1'b0;
      end
      if(shove) begin
        faultOv <= 1'b1;
      end
      acceptR_regNext <= acceptR;
      if(acceptR) begin
        rdataReg <= readValue;
        winSel <= ((aligned && isWindow) && (! empty));
        winWord <= io_addr[4 : 2];
      end
    end
  end


endmodule
