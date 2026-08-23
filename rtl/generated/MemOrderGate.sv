// Generator : SpinalHDL v1.14.2    git head : 78f29dc66110fc099a777992b6daa2f803ab445e
// Component : MemOrderGate
// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
// 
// === 생성물이다. 손으로 고치지 말 것. ===
// 고칠 곳은 rtl/spinal/ 의 생성기이고, 고친 뒤 `make rtl-gen` 으로 다시 낸다.
// 여기 직접 쓴 수정은 다음 생성에서 조용히 사라진다.

`timescale 1ns/1ps

module MemOrderGate (
  input  wire [2:0]    io_cfgPreds_0,
  input  wire [2:0]    io_cfgPreds_1,
  input  wire [2:0]    io_cfgPreds_2,
  input  wire [2:0]    io_cfgPreds_3,
  input  wire          io_epochClear,
  input  wire          io_up_0_valid,
  output wire          io_up_0_ready,
  input  wire [15:0]   io_up_0_payload,
  input  wire          io_up_1_valid,
  output wire          io_up_1_ready,
  input  wire [15:0]   io_up_1_payload,
  input  wire          io_up_2_valid,
  output wire          io_up_2_ready,
  input  wire [15:0]   io_up_2_payload,
  input  wire          io_up_3_valid,
  output wire          io_up_3_ready,
  input  wire [15:0]   io_up_3_payload,
  output wire          io_down_0_valid,
  input  wire          io_down_0_ready,
  output wire [15:0]   io_down_0_payload,
  output wire          io_down_1_valid,
  input  wire          io_down_1_ready,
  output wire [15:0]   io_down_1_payload,
  output wire          io_down_2_valid,
  input  wire          io_down_2_ready,
  output wire [15:0]   io_down_2_payload,
  output wire          io_down_3_valid,
  input  wire          io_down_3_ready,
  output wire [15:0]   io_down_3_payload,
  input  wire [3:0]    io_complete,
  output wire [3:0]    io_token,
  output reg  [3:0]    io_gateOpen,
  output wire [2:0]    io_occupancy,
  input  wire          clk,
  input  wire          reset
);

  reg        [2:0]    _zz_io_occupancy_8;
  wire       [2:0]    _zz_io_occupancy_9;
  reg        [2:0]    _zz_io_occupancy_10;
  wire       [2:0]    _zz_io_occupancy_11;
  wire       [0:0]    _zz_io_occupancy_12;
  reg                 token_0;
  reg                 token_1;
  reg                 token_2;
  reg                 token_3;
  wire                when_MemOrderGate_l155;
  wire                when_MemOrderGate_l155_1;
  wire                when_MemOrderGate_l155_2;
  wire                when_MemOrderGate_l155_3;
  wire                gates_0_waitVec_0;
  wire                gates_0_waitVec_1;
  wire                gates_0_waitVec_2;
  wire                gates_0_open;
  wire                gates_1_waitVec_0;
  wire                gates_1_waitVec_1;
  wire                gates_1_waitVec_2;
  wire                gates_1_open;
  wire                gates_2_waitVec_0;
  wire                gates_2_waitVec_1;
  wire                gates_2_waitVec_2;
  wire                gates_2_open;
  wire                gates_3_waitVec_0;
  wire                gates_3_waitVec_1;
  wire                gates_3_waitVec_2;
  wire                gates_3_open;
  wire                referenced_0;
  wire                referenced_1;
  wire                referenced_2;
  wire                referenced_3;
  wire       [2:0]    _zz_io_occupancy;
  wire       [2:0]    _zz_io_occupancy_1;
  wire       [2:0]    _zz_io_occupancy_2;
  wire       [2:0]    _zz_io_occupancy_3;
  wire       [2:0]    _zz_io_occupancy_4;
  wire       [2:0]    _zz_io_occupancy_5;
  wire       [2:0]    _zz_io_occupancy_6;
  wire       [2:0]    _zz_io_occupancy_7;

  assign _zz_io_occupancy_12 = (referenced_3 && (! token_3));
  assign _zz_io_occupancy_11 = {2'd0, _zz_io_occupancy_12};
  assign _zz_io_occupancy_9 = {(referenced_2 && (! token_2)),{(referenced_1 && (! token_1)),(referenced_0 && (! token_0))}};
  always @(*) begin
    case(_zz_io_occupancy_9)
      3'b000 : _zz_io_occupancy_8 = _zz_io_occupancy;
      3'b001 : _zz_io_occupancy_8 = _zz_io_occupancy_1;
      3'b010 : _zz_io_occupancy_8 = _zz_io_occupancy_2;
      3'b011 : _zz_io_occupancy_8 = _zz_io_occupancy_3;
      3'b100 : _zz_io_occupancy_8 = _zz_io_occupancy_4;
      3'b101 : _zz_io_occupancy_8 = _zz_io_occupancy_5;
      3'b110 : _zz_io_occupancy_8 = _zz_io_occupancy_6;
      default : _zz_io_occupancy_8 = _zz_io_occupancy_7;
    endcase
  end

  always @(*) begin
    case(_zz_io_occupancy_11)
      3'b000 : _zz_io_occupancy_10 = _zz_io_occupancy;
      3'b001 : _zz_io_occupancy_10 = _zz_io_occupancy_1;
      3'b010 : _zz_io_occupancy_10 = _zz_io_occupancy_2;
      3'b011 : _zz_io_occupancy_10 = _zz_io_occupancy_3;
      3'b100 : _zz_io_occupancy_10 = _zz_io_occupancy_4;
      3'b101 : _zz_io_occupancy_10 = _zz_io_occupancy_5;
      3'b110 : _zz_io_occupancy_10 = _zz_io_occupancy_6;
      default : _zz_io_occupancy_10 = _zz_io_occupancy_7;
    endcase
  end

  assign when_MemOrderGate_l155 = io_complete[0];
  assign when_MemOrderGate_l155_1 = io_complete[1];
  assign when_MemOrderGate_l155_2 = io_complete[2];
  assign when_MemOrderGate_l155_3 = io_complete[3];
  assign io_token = {token_3,{token_2,{token_1,token_0}}};
  assign gates_0_waitVec_0 = (io_cfgPreds_0[0] && (! token_1));
  assign gates_0_waitVec_1 = (io_cfgPreds_0[1] && (! token_2));
  assign gates_0_waitVec_2 = (io_cfgPreds_0[2] && (! token_3));
  assign gates_0_open = (! (|{gates_0_waitVec_2,{gates_0_waitVec_1,gates_0_waitVec_0}}));
  always @(*) begin
    io_gateOpen[0] = gates_0_open;
    io_gateOpen[1] = gates_1_open;
    io_gateOpen[2] = gates_2_open;
    io_gateOpen[3] = gates_3_open;
  end

  assign io_down_0_valid = (io_up_0_valid && gates_0_open);
  assign io_down_0_payload = io_up_0_payload;
  assign io_up_0_ready = (gates_0_open && io_down_0_ready);
  assign gates_1_waitVec_0 = (io_cfgPreds_1[0] && (! token_0));
  assign gates_1_waitVec_1 = (io_cfgPreds_1[1] && (! token_2));
  assign gates_1_waitVec_2 = (io_cfgPreds_1[2] && (! token_3));
  assign gates_1_open = (! (|{gates_1_waitVec_2,{gates_1_waitVec_1,gates_1_waitVec_0}}));
  assign io_down_1_valid = (io_up_1_valid && gates_1_open);
  assign io_down_1_payload = io_up_1_payload;
  assign io_up_1_ready = (gates_1_open && io_down_1_ready);
  assign gates_2_waitVec_0 = (io_cfgPreds_2[0] && (! token_0));
  assign gates_2_waitVec_1 = (io_cfgPreds_2[1] && (! token_1));
  assign gates_2_waitVec_2 = (io_cfgPreds_2[2] && (! token_3));
  assign gates_2_open = (! (|{gates_2_waitVec_2,{gates_2_waitVec_1,gates_2_waitVec_0}}));
  assign io_down_2_valid = (io_up_2_valid && gates_2_open);
  assign io_down_2_payload = io_up_2_payload;
  assign io_up_2_ready = (gates_2_open && io_down_2_ready);
  assign gates_3_waitVec_0 = (io_cfgPreds_3[0] && (! token_0));
  assign gates_3_waitVec_1 = (io_cfgPreds_3[1] && (! token_1));
  assign gates_3_waitVec_2 = (io_cfgPreds_3[2] && (! token_2));
  assign gates_3_open = (! (|{gates_3_waitVec_2,{gates_3_waitVec_1,gates_3_waitVec_0}}));
  assign io_down_3_valid = (io_up_3_valid && gates_3_open);
  assign io_down_3_payload = io_up_3_payload;
  assign io_up_3_ready = (gates_3_open && io_down_3_ready);
  assign referenced_0 = ((io_cfgPreds_1[0] || io_cfgPreds_2[0]) || io_cfgPreds_3[0]);
  assign referenced_1 = ((io_cfgPreds_0[0] || io_cfgPreds_2[1]) || io_cfgPreds_3[1]);
  assign referenced_2 = ((io_cfgPreds_0[1] || io_cfgPreds_1[1]) || io_cfgPreds_3[2]);
  assign referenced_3 = ((io_cfgPreds_0[2] || io_cfgPreds_1[2]) || io_cfgPreds_2[2]);
  assign _zz_io_occupancy = 3'b000;
  assign _zz_io_occupancy_1 = 3'b001;
  assign _zz_io_occupancy_2 = 3'b001;
  assign _zz_io_occupancy_3 = 3'b010;
  assign _zz_io_occupancy_4 = 3'b001;
  assign _zz_io_occupancy_5 = 3'b010;
  assign _zz_io_occupancy_6 = 3'b010;
  assign _zz_io_occupancy_7 = 3'b011;
  assign io_occupancy = (_zz_io_occupancy_8 + _zz_io_occupancy_10);
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      token_0 <= 1'b0;
      token_1 <= 1'b0;
      token_2 <= 1'b0;
      token_3 <= 1'b0;
    end else begin
      if(io_epochClear) begin
        token_0 <= 1'b0;
      end
      if(when_MemOrderGate_l155) begin
        token_0 <= 1'b1;
      end
      if(io_epochClear) begin
        token_1 <= 1'b0;
      end
      if(when_MemOrderGate_l155_1) begin
        token_1 <= 1'b1;
      end
      if(io_epochClear) begin
        token_2 <= 1'b0;
      end
      if(when_MemOrderGate_l155_2) begin
        token_2 <= 1'b1;
      end
      if(io_epochClear) begin
        token_3 <= 1'b0;
      end
      if(when_MemOrderGate_l155_3) begin
        token_3 <= 1'b1;
      end
    end
  end


endmodule
