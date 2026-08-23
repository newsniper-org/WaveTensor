// Generator : SpinalHDL v1.14.2    git head : 78f29dc66110fc099a777992b6daa2f803ab445e
// Component : SharedUnitDepth0
// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
// 
// === 생성물이다. 손으로 고치지 말 것. ===
// 고칠 곳은 rtl/spinal/ 의 생성기이고, 고친 뒤 `make rtl-gen` 으로 다시 낸다.
// 여기 직접 쓴 수정은 다음 생성에서 조용히 사라진다.

`timescale 1ns/1ps

module SharedUnitDepth0 (
  input  wire          io_req_valid,
  input  wire [15:0]   io_req_payload,
  output wire          io_req_ready,
  output wire          io_rsp_valid,
  output wire [15:0]   io_rsp_payload,
  output wire          io_faultBpViolation,
  input  wire          io_faultClear,
  output wire [0:0]    io_occupancy,
  input  wire          clk,
  input  wire          reset
);

  reg                 body_1_io_start;
  wire                body_1_io_busy;
  wire                body_1_io_done;
  wire       [15:0]   body_1_io_rsp;
  wire                queueEmpty;
  wire                queueRoom;
  wire                acceptDirect;
  wire                acceptQueue;
  wire                bpViolation;
  reg                 _zz_io_faultBpViolation;
  wire                when_SharedUnit_l220;

  SharedUnitOccupyStub body_1 (
    .io_start (body_1_io_start     ), //i
    .io_req   (io_req_payload[15:0]), //i
    .io_busy  (body_1_io_busy      ), //o
    .io_done  (body_1_io_done      ), //o
    .io_rsp   (body_1_io_rsp[15:0] ), //o
    .clk      (clk                 ), //i
    .reset    (reset               )  //i
  );
  assign queueEmpty = 1'b1;
  assign queueRoom = 1'b0;
  assign acceptDirect = ((! body_1_io_busy) && queueEmpty);
  assign acceptQueue = ((! acceptDirect) && queueRoom);
  assign io_req_ready = (acceptDirect || acceptQueue);
  assign bpViolation = (io_req_valid && (! io_req_ready));
  assign io_faultBpViolation = _zz_io_faultBpViolation;
  always @(*) begin
    body_1_io_start = 1'b0;
    if(when_SharedUnit_l220) begin
      body_1_io_start = 1'b1;
    end
  end

  assign when_SharedUnit_l220 = (io_req_valid && acceptDirect);
  assign io_rsp_valid = body_1_io_done;
  assign io_rsp_payload = body_1_io_rsp;
  assign io_occupancy = body_1_io_busy;
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      _zz_io_faultBpViolation <= 1'b0;
    end else begin
      if(io_faultClear) begin
        _zz_io_faultBpViolation <= 1'b0;
      end
      if(bpViolation) begin
        _zz_io_faultBpViolation <= 1'b1;
      end
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
