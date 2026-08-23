// Generator : SpinalHDL v1.14.2    git head : 78f29dc66110fc099a777992b6daa2f803ab445e
// Component : SharedUnit
// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
// 
// === 생성물이다. 손으로 고치지 말 것. ===
// 고칠 곳은 rtl/spinal/ 의 생성기이고, 고친 뒤 `make rtl-gen` 으로 다시 낸다.
// 여기 직접 쓴 수정은 다음 생성에서 조용히 사라진다.

`timescale 1ns/1ps

module SharedUnit (
  input  wire          io_req_valid,
  input  wire [15:0]   io_req_payload,
  output wire          io_req_ready,
  output wire          io_rsp_valid,
  output wire [15:0]   io_rsp_payload,
  output wire          io_faultBpViolation,
  input  wire          io_faultClear,
  input  wire          clk,
  input  wire          reset
);

  reg                 body_1_io_start;
  reg        [15:0]   body_1_io_req;
  wire                body_1_io_busy;
  wire                body_1_io_done;
  wire       [15:0]   body_1_io_rsp;
  reg        [15:0]   _zz_queue_head;
  wire       [1:0]    _zz_queue_rdPtr;
  wire       [1:0]    _zz_queue_wrPtr;
  wire       [2:0]    _zz_queue_cnt;
  wire       [2:0]    _zz_queue_cnt_1;
  wire       [0:0]    _zz_queue_cnt_2;
  wire       [2:0]    _zz_queue_cnt_3;
  wire       [0:0]    _zz_queue_cnt_4;
  reg        [15:0]   queue_slots_0;
  reg        [15:0]   queue_slots_1;
  reg        [15:0]   queue_slots_2;
  reg        [15:0]   queue_slots_3;
  reg        [1:0]    queue_rdPtr;
  reg        [1:0]    queue_wrPtr;
  reg        [2:0]    queue_cnt;
  wire       [15:0]   queue_head;
  wire                queueEmpty;
  wire                queueRoom;
  wire                acceptDirect;
  wire                acceptQueue;
  wire                bpViolation;
  reg                 _zz_io_faultBpViolation;
  wire                when_SharedUnit_l185;
  wire       [3:0]    _zz_1;

  assign _zz_queue_rdPtr = (queue_rdPtr + 2'b01);
  assign _zz_queue_wrPtr = (queue_wrPtr + 2'b01);
  assign _zz_queue_cnt = (queue_cnt + _zz_queue_cnt_1);
  assign _zz_queue_cnt_2 = (io_req_valid && acceptQueue);
  assign _zz_queue_cnt_1 = {2'd0, _zz_queue_cnt_2};
  assign _zz_queue_cnt_4 = when_SharedUnit_l185;
  assign _zz_queue_cnt_3 = {2'd0, _zz_queue_cnt_4};
  SharedUnitOccupyStub body_1 (
    .io_start (body_1_io_start    ), //i
    .io_req   (body_1_io_req[15:0]), //i
    .io_busy  (body_1_io_busy     ), //o
    .io_done  (body_1_io_done     ), //o
    .io_rsp   (body_1_io_rsp[15:0]), //o
    .clk      (clk                ), //i
    .reset    (reset              )  //i
  );
  always @(*) begin
    case(queue_rdPtr)
      2'b00 : _zz_queue_head = queue_slots_0;
      2'b01 : _zz_queue_head = queue_slots_1;
      2'b10 : _zz_queue_head = queue_slots_2;
      default : _zz_queue_head = queue_slots_3;
    endcase
  end

  assign queue_head = _zz_queue_head;
  assign queueEmpty = (queue_cnt == 3'b000);
  assign queueRoom = (queue_cnt < 3'b100);
  assign acceptDirect = ((! body_1_io_busy) && queueEmpty);
  assign acceptQueue = ((! acceptDirect) && queueRoom);
  assign io_req_ready = (acceptDirect || acceptQueue);
  assign bpViolation = (io_req_valid && (! io_req_ready));
  assign io_faultBpViolation = _zz_io_faultBpViolation;
  always @(*) begin
    body_1_io_start = 1'b0;
    if(when_SharedUnit_l185) begin
      body_1_io_start = 1'b1;
    end
    if(io_req_valid) begin
      if(acceptDirect) begin
        body_1_io_start = 1'b1;
      end
    end
  end

  always @(*) begin
    body_1_io_req = io_req_payload;
    if(when_SharedUnit_l185) begin
      body_1_io_req = queue_head;
    end
  end

  assign when_SharedUnit_l185 = ((! body_1_io_busy) && (! queueEmpty));
  assign _zz_1 = ({3'd0,1'b1} <<< queue_wrPtr);
  assign io_rsp_valid = body_1_io_done;
  assign io_rsp_payload = body_1_io_rsp;
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      queue_slots_0 <= 16'h0;
      queue_slots_1 <= 16'h0;
      queue_slots_2 <= 16'h0;
      queue_slots_3 <= 16'h0;
      queue_rdPtr <= 2'b00;
      queue_wrPtr <= 2'b00;
      queue_cnt <= 3'b000;
      _zz_io_faultBpViolation <= 1'b0;
    end else begin
      if(io_faultClear) begin
        _zz_io_faultBpViolation <= 1'b0;
      end
      if(bpViolation) begin
        _zz_io_faultBpViolation <= 1'b1;
      end
      if(when_SharedUnit_l185) begin
        queue_rdPtr <= ((queue_rdPtr == 2'b11) ? 2'b00 : _zz_queue_rdPtr);
      end
      if(io_req_valid) begin
        if(!acceptDirect) begin
          if(acceptQueue) begin
            if(_zz_1[0]) begin
              queue_slots_0 <= io_req_payload;
            end
            if(_zz_1[1]) begin
              queue_slots_1 <= io_req_payload;
            end
            if(_zz_1[2]) begin
              queue_slots_2 <= io_req_payload;
            end
            if(_zz_1[3]) begin
              queue_slots_3 <= io_req_payload;
            end
            queue_wrPtr <= ((queue_wrPtr == 2'b11) ? 2'b00 : _zz_queue_wrPtr);
          end
        end
      end
      queue_cnt <= (_zz_queue_cnt - _zz_queue_cnt_3);
    end
  end


endmodule

module SharedUnitOccupyStub (
  input  wire          io_start,
  input  wire [15:0]   io_req,
  output wire          io_busy,
  output reg           io_done,
  output wire [15:0]   io_rsp,
  input  wire          clk,
  input  wire          reset
);

  reg        [3:0]    remain;
  reg        [15:0]   held;
  reg                 busyReg;
  wire                when_SharedUnit_l95;

  assign io_busy = busyReg;
  always @(*) begin
    io_done = 1'b0;
    if(!io_start) begin
      if(busyReg) begin
        if(when_SharedUnit_l95) begin
          io_done = 1'b1;
        end
      end
    end
  end

  assign io_rsp = held;
  assign when_SharedUnit_l95 = (remain == 4'b0001);
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      remain <= 4'b0000;
      held <= 16'h0;
      busyReg <= 1'b0;
    end else begin
      if(io_start) begin
        busyReg <= 1'b1;
        held <= io_req;
        remain <= 4'b1000;
      end else begin
        if(busyReg) begin
          remain <= (remain - 4'b0001);
          if(when_SharedUnit_l95) begin
            busyReg <= 1'b0;
          end
        end
      end
    end
  end


endmodule
