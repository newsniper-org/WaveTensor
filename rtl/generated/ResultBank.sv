// Generator : SpinalHDL v1.14.2    git head : 78f29dc66110fc099a777992b6daa2f803ab445e
// Component : ResultBank
// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
// 
// === 생성물이다. 손으로 고치지 말 것. ===
// 고칠 곳은 rtl/spinal/ 의 생성기이고, 고친 뒤 `make rtl-gen` 으로 다시 낸다.
// 여기 직접 쓴 수정은 다음 생성에서 조용히 사라진다.

`timescale 1ns/1ps

module ResultBank (
  input  wire          io_acquire_valid,
  input  wire [3:0]    io_acquire_slot,
  input  wire [3:0]    io_acquire_prod,
  output wire          io_acquire_granted,
  input  wire          io_write_valid,
  input  wire [3:0]    io_write_slot,
  input  wire [3:0]    io_write_prod,
  input  wire [63:0]   io_write_data,
  input  wire [3:0]    io_read_slot,
  output wire [63:0]   io_read_data,
  output wire          io_read_owned,
  output wire          io_fault,
  input  wire          io_faultClear,
  output wire [4:0]    io_occupancy,
  input  wire          clk,
  input  wire          reset
);

  reg                 _zz_acqFree;
  reg                 _zz_wrQualified;
  reg        [3:0]    _zz_wrQualified_1;
  reg        [63:0]   _zz_io_read_data;
  reg                 _zz_io_read_owned;
  wire       [4:0]    _zz_io_occupancy_8;
  wire       [4:0]    _zz_io_occupancy_9;
  reg        [4:0]    _zz_io_occupancy_10;
  wire       [2:0]    _zz_io_occupancy_11;
  reg        [4:0]    _zz_io_occupancy_12;
  wire       [2:0]    _zz_io_occupancy_13;
  wire       [4:0]    _zz_io_occupancy_14;
  reg        [4:0]    _zz_io_occupancy_15;
  wire       [2:0]    _zz_io_occupancy_16;
  reg        [4:0]    _zz_io_occupancy_17;
  wire       [2:0]    _zz_io_occupancy_18;
  wire       [4:0]    _zz_io_occupancy_19;
  reg        [4:0]    _zz_io_occupancy_20;
  wire       [2:0]    _zz_io_occupancy_21;
  reg        [4:0]    _zz_io_occupancy_22;
  wire       [2:0]    _zz_io_occupancy_23;
  wire       [0:0]    _zz_io_occupancy_24;
  reg                 ownerValid_0;
  reg                 ownerValid_1;
  reg                 ownerValid_2;
  reg                 ownerValid_3;
  reg                 ownerValid_4;
  reg                 ownerValid_5;
  reg                 ownerValid_6;
  reg                 ownerValid_7;
  reg                 ownerValid_8;
  reg                 ownerValid_9;
  reg                 ownerValid_10;
  reg                 ownerValid_11;
  reg                 ownerValid_12;
  reg                 ownerValid_13;
  reg                 ownerValid_14;
  reg                 ownerValid_15;
  reg        [3:0]    ownerId_0;
  reg        [3:0]    ownerId_1;
  reg        [3:0]    ownerId_2;
  reg        [3:0]    ownerId_3;
  reg        [3:0]    ownerId_4;
  reg        [3:0]    ownerId_5;
  reg        [3:0]    ownerId_6;
  reg        [3:0]    ownerId_7;
  reg        [3:0]    ownerId_8;
  reg        [3:0]    ownerId_9;
  reg        [3:0]    ownerId_10;
  reg        [3:0]    ownerId_11;
  reg        [3:0]    ownerId_12;
  reg        [3:0]    ownerId_13;
  reg        [3:0]    ownerId_14;
  reg        [3:0]    ownerId_15;
  reg        [1:0]    age_0;
  reg        [1:0]    age_1;
  reg        [1:0]    age_2;
  reg        [1:0]    age_3;
  reg        [1:0]    age_4;
  reg        [1:0]    age_5;
  reg        [1:0]    age_6;
  reg        [1:0]    age_7;
  reg        [1:0]    age_8;
  reg        [1:0]    age_9;
  reg        [1:0]    age_10;
  reg        [1:0]    age_11;
  reg        [1:0]    age_12;
  reg        [1:0]    age_13;
  reg        [1:0]    age_14;
  reg        [1:0]    age_15;
  reg        [63:0]   store_0;
  reg        [63:0]   store_1;
  reg        [63:0]   store_2;
  reg        [63:0]   store_3;
  reg        [63:0]   store_4;
  reg        [63:0]   store_5;
  reg        [63:0]   store_6;
  reg        [63:0]   store_7;
  reg        [63:0]   store_8;
  reg        [63:0]   store_9;
  reg        [63:0]   store_10;
  reg        [63:0]   store_11;
  reg        [63:0]   store_12;
  reg        [63:0]   store_13;
  reg        [63:0]   store_14;
  reg        [63:0]   store_15;
  wire                ageAtEnd_0;
  wire                ageAtEnd_1;
  wire                ageAtEnd_2;
  wire                ageAtEnd_3;
  wire                ageAtEnd_4;
  wire                ageAtEnd_5;
  wire                ageAtEnd_6;
  wire                ageAtEnd_7;
  wire                ageAtEnd_8;
  wire                ageAtEnd_9;
  wire                ageAtEnd_10;
  wire                ageAtEnd_11;
  wire                ageAtEnd_12;
  wire                ageAtEnd_13;
  wire                ageAtEnd_14;
  wire                ageAtEnd_15;
  wire                acqFree;
  wire                when_ResultBank_l163;
  wire       [15:0]   _zz_1;
  wire       [15:0]   _zz_2;
  wire       [15:0]   _zz_3;
  wire                wrQualified;
  wire                when_ResultBank_l181;
  wire       [15:0]   _zz_4;
  wire                when_Common_l337;
  reg                 _zz_io_fault;
  wire       [4:0]    _zz_io_occupancy;
  wire       [4:0]    _zz_io_occupancy_1;
  wire       [4:0]    _zz_io_occupancy_2;
  wire       [4:0]    _zz_io_occupancy_3;
  wire       [4:0]    _zz_io_occupancy_4;
  wire       [4:0]    _zz_io_occupancy_5;
  wire       [4:0]    _zz_io_occupancy_6;
  wire       [4:0]    _zz_io_occupancy_7;

  assign _zz_io_occupancy_8 = (_zz_io_occupancy_9 + _zz_io_occupancy_14);
  assign _zz_io_occupancy_9 = (_zz_io_occupancy_10 + _zz_io_occupancy_12);
  assign _zz_io_occupancy_14 = (_zz_io_occupancy_15 + _zz_io_occupancy_17);
  assign _zz_io_occupancy_19 = (_zz_io_occupancy_20 + _zz_io_occupancy_22);
  assign _zz_io_occupancy_24 = ownerValid_15;
  assign _zz_io_occupancy_23 = {2'd0, _zz_io_occupancy_24};
  assign _zz_io_occupancy_11 = {ownerValid_2,{ownerValid_1,ownerValid_0}};
  assign _zz_io_occupancy_13 = {ownerValid_5,{ownerValid_4,ownerValid_3}};
  assign _zz_io_occupancy_16 = {ownerValid_8,{ownerValid_7,ownerValid_6}};
  assign _zz_io_occupancy_18 = {ownerValid_11,{ownerValid_10,ownerValid_9}};
  assign _zz_io_occupancy_21 = {ownerValid_14,{ownerValid_13,ownerValid_12}};
  always @(*) begin
    case(io_acquire_slot)
      4'b0000 : _zz_acqFree = ownerValid_0;
      4'b0001 : _zz_acqFree = ownerValid_1;
      4'b0010 : _zz_acqFree = ownerValid_2;
      4'b0011 : _zz_acqFree = ownerValid_3;
      4'b0100 : _zz_acqFree = ownerValid_4;
      4'b0101 : _zz_acqFree = ownerValid_5;
      4'b0110 : _zz_acqFree = ownerValid_6;
      4'b0111 : _zz_acqFree = ownerValid_7;
      4'b1000 : _zz_acqFree = ownerValid_8;
      4'b1001 : _zz_acqFree = ownerValid_9;
      4'b1010 : _zz_acqFree = ownerValid_10;
      4'b1011 : _zz_acqFree = ownerValid_11;
      4'b1100 : _zz_acqFree = ownerValid_12;
      4'b1101 : _zz_acqFree = ownerValid_13;
      4'b1110 : _zz_acqFree = ownerValid_14;
      default : _zz_acqFree = ownerValid_15;
    endcase
  end

  always @(*) begin
    case(io_write_slot)
      4'b0000 : begin
        _zz_wrQualified = ownerValid_0;
        _zz_wrQualified_1 = ownerId_0;
      end
      4'b0001 : begin
        _zz_wrQualified = ownerValid_1;
        _zz_wrQualified_1 = ownerId_1;
      end
      4'b0010 : begin
        _zz_wrQualified = ownerValid_2;
        _zz_wrQualified_1 = ownerId_2;
      end
      4'b0011 : begin
        _zz_wrQualified = ownerValid_3;
        _zz_wrQualified_1 = ownerId_3;
      end
      4'b0100 : begin
        _zz_wrQualified = ownerValid_4;
        _zz_wrQualified_1 = ownerId_4;
      end
      4'b0101 : begin
        _zz_wrQualified = ownerValid_5;
        _zz_wrQualified_1 = ownerId_5;
      end
      4'b0110 : begin
        _zz_wrQualified = ownerValid_6;
        _zz_wrQualified_1 = ownerId_6;
      end
      4'b0111 : begin
        _zz_wrQualified = ownerValid_7;
        _zz_wrQualified_1 = ownerId_7;
      end
      4'b1000 : begin
        _zz_wrQualified = ownerValid_8;
        _zz_wrQualified_1 = ownerId_8;
      end
      4'b1001 : begin
        _zz_wrQualified = ownerValid_9;
        _zz_wrQualified_1 = ownerId_9;
      end
      4'b1010 : begin
        _zz_wrQualified = ownerValid_10;
        _zz_wrQualified_1 = ownerId_10;
      end
      4'b1011 : begin
        _zz_wrQualified = ownerValid_11;
        _zz_wrQualified_1 = ownerId_11;
      end
      4'b1100 : begin
        _zz_wrQualified = ownerValid_12;
        _zz_wrQualified_1 = ownerId_12;
      end
      4'b1101 : begin
        _zz_wrQualified = ownerValid_13;
        _zz_wrQualified_1 = ownerId_13;
      end
      4'b1110 : begin
        _zz_wrQualified = ownerValid_14;
        _zz_wrQualified_1 = ownerId_14;
      end
      default : begin
        _zz_wrQualified = ownerValid_15;
        _zz_wrQualified_1 = ownerId_15;
      end
    endcase
  end

  always @(*) begin
    case(io_read_slot)
      4'b0000 : begin
        _zz_io_read_data = store_0;
        _zz_io_read_owned = ownerValid_0;
      end
      4'b0001 : begin
        _zz_io_read_data = store_1;
        _zz_io_read_owned = ownerValid_1;
      end
      4'b0010 : begin
        _zz_io_read_data = store_2;
        _zz_io_read_owned = ownerValid_2;
      end
      4'b0011 : begin
        _zz_io_read_data = store_3;
        _zz_io_read_owned = ownerValid_3;
      end
      4'b0100 : begin
        _zz_io_read_data = store_4;
        _zz_io_read_owned = ownerValid_4;
      end
      4'b0101 : begin
        _zz_io_read_data = store_5;
        _zz_io_read_owned = ownerValid_5;
      end
      4'b0110 : begin
        _zz_io_read_data = store_6;
        _zz_io_read_owned = ownerValid_6;
      end
      4'b0111 : begin
        _zz_io_read_data = store_7;
        _zz_io_read_owned = ownerValid_7;
      end
      4'b1000 : begin
        _zz_io_read_data = store_8;
        _zz_io_read_owned = ownerValid_8;
      end
      4'b1001 : begin
        _zz_io_read_data = store_9;
        _zz_io_read_owned = ownerValid_9;
      end
      4'b1010 : begin
        _zz_io_read_data = store_10;
        _zz_io_read_owned = ownerValid_10;
      end
      4'b1011 : begin
        _zz_io_read_data = store_11;
        _zz_io_read_owned = ownerValid_11;
      end
      4'b1100 : begin
        _zz_io_read_data = store_12;
        _zz_io_read_owned = ownerValid_12;
      end
      4'b1101 : begin
        _zz_io_read_data = store_13;
        _zz_io_read_owned = ownerValid_13;
      end
      4'b1110 : begin
        _zz_io_read_data = store_14;
        _zz_io_read_owned = ownerValid_14;
      end
      default : begin
        _zz_io_read_data = store_15;
        _zz_io_read_owned = ownerValid_15;
      end
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

  always @(*) begin
    case(_zz_io_occupancy_13)
      3'b000 : _zz_io_occupancy_12 = _zz_io_occupancy;
      3'b001 : _zz_io_occupancy_12 = _zz_io_occupancy_1;
      3'b010 : _zz_io_occupancy_12 = _zz_io_occupancy_2;
      3'b011 : _zz_io_occupancy_12 = _zz_io_occupancy_3;
      3'b100 : _zz_io_occupancy_12 = _zz_io_occupancy_4;
      3'b101 : _zz_io_occupancy_12 = _zz_io_occupancy_5;
      3'b110 : _zz_io_occupancy_12 = _zz_io_occupancy_6;
      default : _zz_io_occupancy_12 = _zz_io_occupancy_7;
    endcase
  end

  always @(*) begin
    case(_zz_io_occupancy_16)
      3'b000 : _zz_io_occupancy_15 = _zz_io_occupancy;
      3'b001 : _zz_io_occupancy_15 = _zz_io_occupancy_1;
      3'b010 : _zz_io_occupancy_15 = _zz_io_occupancy_2;
      3'b011 : _zz_io_occupancy_15 = _zz_io_occupancy_3;
      3'b100 : _zz_io_occupancy_15 = _zz_io_occupancy_4;
      3'b101 : _zz_io_occupancy_15 = _zz_io_occupancy_5;
      3'b110 : _zz_io_occupancy_15 = _zz_io_occupancy_6;
      default : _zz_io_occupancy_15 = _zz_io_occupancy_7;
    endcase
  end

  always @(*) begin
    case(_zz_io_occupancy_18)
      3'b000 : _zz_io_occupancy_17 = _zz_io_occupancy;
      3'b001 : _zz_io_occupancy_17 = _zz_io_occupancy_1;
      3'b010 : _zz_io_occupancy_17 = _zz_io_occupancy_2;
      3'b011 : _zz_io_occupancy_17 = _zz_io_occupancy_3;
      3'b100 : _zz_io_occupancy_17 = _zz_io_occupancy_4;
      3'b101 : _zz_io_occupancy_17 = _zz_io_occupancy_5;
      3'b110 : _zz_io_occupancy_17 = _zz_io_occupancy_6;
      default : _zz_io_occupancy_17 = _zz_io_occupancy_7;
    endcase
  end

  always @(*) begin
    case(_zz_io_occupancy_21)
      3'b000 : _zz_io_occupancy_20 = _zz_io_occupancy;
      3'b001 : _zz_io_occupancy_20 = _zz_io_occupancy_1;
      3'b010 : _zz_io_occupancy_20 = _zz_io_occupancy_2;
      3'b011 : _zz_io_occupancy_20 = _zz_io_occupancy_3;
      3'b100 : _zz_io_occupancy_20 = _zz_io_occupancy_4;
      3'b101 : _zz_io_occupancy_20 = _zz_io_occupancy_5;
      3'b110 : _zz_io_occupancy_20 = _zz_io_occupancy_6;
      default : _zz_io_occupancy_20 = _zz_io_occupancy_7;
    endcase
  end

  always @(*) begin
    case(_zz_io_occupancy_23)
      3'b000 : _zz_io_occupancy_22 = _zz_io_occupancy;
      3'b001 : _zz_io_occupancy_22 = _zz_io_occupancy_1;
      3'b010 : _zz_io_occupancy_22 = _zz_io_occupancy_2;
      3'b011 : _zz_io_occupancy_22 = _zz_io_occupancy_3;
      3'b100 : _zz_io_occupancy_22 = _zz_io_occupancy_4;
      3'b101 : _zz_io_occupancy_22 = _zz_io_occupancy_5;
      3'b110 : _zz_io_occupancy_22 = _zz_io_occupancy_6;
      default : _zz_io_occupancy_22 = _zz_io_occupancy_7;
    endcase
  end

  assign ageAtEnd_0 = (ownerValid_0 && (age_0 == 2'b10));
  assign ageAtEnd_1 = (ownerValid_1 && (age_1 == 2'b10));
  assign ageAtEnd_2 = (ownerValid_2 && (age_2 == 2'b10));
  assign ageAtEnd_3 = (ownerValid_3 && (age_3 == 2'b10));
  assign ageAtEnd_4 = (ownerValid_4 && (age_4 == 2'b10));
  assign ageAtEnd_5 = (ownerValid_5 && (age_5 == 2'b10));
  assign ageAtEnd_6 = (ownerValid_6 && (age_6 == 2'b10));
  assign ageAtEnd_7 = (ownerValid_7 && (age_7 == 2'b10));
  assign ageAtEnd_8 = (ownerValid_8 && (age_8 == 2'b10));
  assign ageAtEnd_9 = (ownerValid_9 && (age_9 == 2'b10));
  assign ageAtEnd_10 = (ownerValid_10 && (age_10 == 2'b10));
  assign ageAtEnd_11 = (ownerValid_11 && (age_11 == 2'b10));
  assign ageAtEnd_12 = (ownerValid_12 && (age_12 == 2'b10));
  assign ageAtEnd_13 = (ownerValid_13 && (age_13 == 2'b10));
  assign ageAtEnd_14 = (ownerValid_14 && (age_14 == 2'b10));
  assign ageAtEnd_15 = (ownerValid_15 && (age_15 == 2'b10));
  assign acqFree = (1'b1 && (! _zz_acqFree));
  assign io_acquire_granted = (io_acquire_valid && acqFree);
  assign when_ResultBank_l163 = (io_acquire_valid && acqFree);
  assign _zz_1 = ({15'd0,1'b1} <<< io_acquire_slot);
  assign _zz_2 = ({15'd0,1'b1} <<< io_acquire_slot);
  assign _zz_3 = ({15'd0,1'b1} <<< io_acquire_slot);
  assign wrQualified = ((1'b1 && _zz_wrQualified) && (_zz_wrQualified_1 == io_write_prod));
  assign when_ResultBank_l181 = (io_write_valid && wrQualified);
  assign _zz_4 = ({15'd0,1'b1} <<< io_write_slot);
  assign when_Common_l337 = (io_write_valid && (! wrQualified));
  assign io_fault = _zz_io_fault;
  assign io_read_data = _zz_io_read_data;
  assign io_read_owned = (1'b1 && _zz_io_read_owned);
  assign _zz_io_occupancy = 5'h0;
  assign _zz_io_occupancy_1 = 5'h01;
  assign _zz_io_occupancy_2 = 5'h01;
  assign _zz_io_occupancy_3 = 5'h02;
  assign _zz_io_occupancy_4 = 5'h01;
  assign _zz_io_occupancy_5 = 5'h02;
  assign _zz_io_occupancy_6 = 5'h02;
  assign _zz_io_occupancy_7 = 5'h03;
  assign io_occupancy = (_zz_io_occupancy_8 + _zz_io_occupancy_19);
  always @(posedge clk or posedge reset) begin
    if(reset) begin
      ownerValid_0 <= 1'b0;
      ownerValid_1 <= 1'b0;
      ownerValid_2 <= 1'b0;
      ownerValid_3 <= 1'b0;
      ownerValid_4 <= 1'b0;
      ownerValid_5 <= 1'b0;
      ownerValid_6 <= 1'b0;
      ownerValid_7 <= 1'b0;
      ownerValid_8 <= 1'b0;
      ownerValid_9 <= 1'b0;
      ownerValid_10 <= 1'b0;
      ownerValid_11 <= 1'b0;
      ownerValid_12 <= 1'b0;
      ownerValid_13 <= 1'b0;
      ownerValid_14 <= 1'b0;
      ownerValid_15 <= 1'b0;
      ownerId_0 <= 4'b0000;
      ownerId_1 <= 4'b0000;
      ownerId_2 <= 4'b0000;
      ownerId_3 <= 4'b0000;
      ownerId_4 <= 4'b0000;
      ownerId_5 <= 4'b0000;
      ownerId_6 <= 4'b0000;
      ownerId_7 <= 4'b0000;
      ownerId_8 <= 4'b0000;
      ownerId_9 <= 4'b0000;
      ownerId_10 <= 4'b0000;
      ownerId_11 <= 4'b0000;
      ownerId_12 <= 4'b0000;
      ownerId_13 <= 4'b0000;
      ownerId_14 <= 4'b0000;
      ownerId_15 <= 4'b0000;
      age_0 <= 2'b00;
      age_1 <= 2'b00;
      age_2 <= 2'b00;
      age_3 <= 2'b00;
      age_4 <= 2'b00;
      age_5 <= 2'b00;
      age_6 <= 2'b00;
      age_7 <= 2'b00;
      age_8 <= 2'b00;
      age_9 <= 2'b00;
      age_10 <= 2'b00;
      age_11 <= 2'b00;
      age_12 <= 2'b00;
      age_13 <= 2'b00;
      age_14 <= 2'b00;
      age_15 <= 2'b00;
      store_0 <= 64'h0;
      store_1 <= 64'h0;
      store_2 <= 64'h0;
      store_3 <= 64'h0;
      store_4 <= 64'h0;
      store_5 <= 64'h0;
      store_6 <= 64'h0;
      store_7 <= 64'h0;
      store_8 <= 64'h0;
      store_9 <= 64'h0;
      store_10 <= 64'h0;
      store_11 <= 64'h0;
      store_12 <= 64'h0;
      store_13 <= 64'h0;
      store_14 <= 64'h0;
      store_15 <= 64'h0;
      _zz_io_fault <= 1'b0;
    end else begin
      if(ownerValid_0) begin
        if(ageAtEnd_0) begin
          ownerValid_0 <= 1'b0;
          age_0 <= 2'b00;
        end else begin
          age_0 <= (age_0 + 2'b01);
        end
      end
      if(ownerValid_1) begin
        if(ageAtEnd_1) begin
          ownerValid_1 <= 1'b0;
          age_1 <= 2'b00;
        end else begin
          age_1 <= (age_1 + 2'b01);
        end
      end
      if(ownerValid_2) begin
        if(ageAtEnd_2) begin
          ownerValid_2 <= 1'b0;
          age_2 <= 2'b00;
        end else begin
          age_2 <= (age_2 + 2'b01);
        end
      end
      if(ownerValid_3) begin
        if(ageAtEnd_3) begin
          ownerValid_3 <= 1'b0;
          age_3 <= 2'b00;
        end else begin
          age_3 <= (age_3 + 2'b01);
        end
      end
      if(ownerValid_4) begin
        if(ageAtEnd_4) begin
          ownerValid_4 <= 1'b0;
          age_4 <= 2'b00;
        end else begin
          age_4 <= (age_4 + 2'b01);
        end
      end
      if(ownerValid_5) begin
        if(ageAtEnd_5) begin
          ownerValid_5 <= 1'b0;
          age_5 <= 2'b00;
        end else begin
          age_5 <= (age_5 + 2'b01);
        end
      end
      if(ownerValid_6) begin
        if(ageAtEnd_6) begin
          ownerValid_6 <= 1'b0;
          age_6 <= 2'b00;
        end else begin
          age_6 <= (age_6 + 2'b01);
        end
      end
      if(ownerValid_7) begin
        if(ageAtEnd_7) begin
          ownerValid_7 <= 1'b0;
          age_7 <= 2'b00;
        end else begin
          age_7 <= (age_7 + 2'b01);
        end
      end
      if(ownerValid_8) begin
        if(ageAtEnd_8) begin
          ownerValid_8 <= 1'b0;
          age_8 <= 2'b00;
        end else begin
          age_8 <= (age_8 + 2'b01);
        end
      end
      if(ownerValid_9) begin
        if(ageAtEnd_9) begin
          ownerValid_9 <= 1'b0;
          age_9 <= 2'b00;
        end else begin
          age_9 <= (age_9 + 2'b01);
        end
      end
      if(ownerValid_10) begin
        if(ageAtEnd_10) begin
          ownerValid_10 <= 1'b0;
          age_10 <= 2'b00;
        end else begin
          age_10 <= (age_10 + 2'b01);
        end
      end
      if(ownerValid_11) begin
        if(ageAtEnd_11) begin
          ownerValid_11 <= 1'b0;
          age_11 <= 2'b00;
        end else begin
          age_11 <= (age_11 + 2'b01);
        end
      end
      if(ownerValid_12) begin
        if(ageAtEnd_12) begin
          ownerValid_12 <= 1'b0;
          age_12 <= 2'b00;
        end else begin
          age_12 <= (age_12 + 2'b01);
        end
      end
      if(ownerValid_13) begin
        if(ageAtEnd_13) begin
          ownerValid_13 <= 1'b0;
          age_13 <= 2'b00;
        end else begin
          age_13 <= (age_13 + 2'b01);
        end
      end
      if(ownerValid_14) begin
        if(ageAtEnd_14) begin
          ownerValid_14 <= 1'b0;
          age_14 <= 2'b00;
        end else begin
          age_14 <= (age_14 + 2'b01);
        end
      end
      if(ownerValid_15) begin
        if(ageAtEnd_15) begin
          ownerValid_15 <= 1'b0;
          age_15 <= 2'b00;
        end else begin
          age_15 <= (age_15 + 2'b01);
        end
      end
      if(when_ResultBank_l163) begin
        if(_zz_1[0]) begin
          ownerValid_0 <= 1'b1;
        end
        if(_zz_1[1]) begin
          ownerValid_1 <= 1'b1;
        end
        if(_zz_1[2]) begin
          ownerValid_2 <= 1'b1;
        end
        if(_zz_1[3]) begin
          ownerValid_3 <= 1'b1;
        end
        if(_zz_1[4]) begin
          ownerValid_4 <= 1'b1;
        end
        if(_zz_1[5]) begin
          ownerValid_5 <= 1'b1;
        end
        if(_zz_1[6]) begin
          ownerValid_6 <= 1'b1;
        end
        if(_zz_1[7]) begin
          ownerValid_7 <= 1'b1;
        end
        if(_zz_1[8]) begin
          ownerValid_8 <= 1'b1;
        end
        if(_zz_1[9]) begin
          ownerValid_9 <= 1'b1;
        end
        if(_zz_1[10]) begin
          ownerValid_10 <= 1'b1;
        end
        if(_zz_1[11]) begin
          ownerValid_11 <= 1'b1;
        end
        if(_zz_1[12]) begin
          ownerValid_12 <= 1'b1;
        end
        if(_zz_1[13]) begin
          ownerValid_13 <= 1'b1;
        end
        if(_zz_1[14]) begin
          ownerValid_14 <= 1'b1;
        end
        if(_zz_1[15]) begin
          ownerValid_15 <= 1'b1;
        end
        if(_zz_2[0]) begin
          ownerId_0 <= io_acquire_prod;
        end
        if(_zz_2[1]) begin
          ownerId_1 <= io_acquire_prod;
        end
        if(_zz_2[2]) begin
          ownerId_2 <= io_acquire_prod;
        end
        if(_zz_2[3]) begin
          ownerId_3 <= io_acquire_prod;
        end
        if(_zz_2[4]) begin
          ownerId_4 <= io_acquire_prod;
        end
        if(_zz_2[5]) begin
          ownerId_5 <= io_acquire_prod;
        end
        if(_zz_2[6]) begin
          ownerId_6 <= io_acquire_prod;
        end
        if(_zz_2[7]) begin
          ownerId_7 <= io_acquire_prod;
        end
        if(_zz_2[8]) begin
          ownerId_8 <= io_acquire_prod;
        end
        if(_zz_2[9]) begin
          ownerId_9 <= io_acquire_prod;
        end
        if(_zz_2[10]) begin
          ownerId_10 <= io_acquire_prod;
        end
        if(_zz_2[11]) begin
          ownerId_11 <= io_acquire_prod;
        end
        if(_zz_2[12]) begin
          ownerId_12 <= io_acquire_prod;
        end
        if(_zz_2[13]) begin
          ownerId_13 <= io_acquire_prod;
        end
        if(_zz_2[14]) begin
          ownerId_14 <= io_acquire_prod;
        end
        if(_zz_2[15]) begin
          ownerId_15 <= io_acquire_prod;
        end
        if(_zz_3[0]) begin
          age_0 <= 2'b00;
        end
        if(_zz_3[1]) begin
          age_1 <= 2'b00;
        end
        if(_zz_3[2]) begin
          age_2 <= 2'b00;
        end
        if(_zz_3[3]) begin
          age_3 <= 2'b00;
        end
        if(_zz_3[4]) begin
          age_4 <= 2'b00;
        end
        if(_zz_3[5]) begin
          age_5 <= 2'b00;
        end
        if(_zz_3[6]) begin
          age_6 <= 2'b00;
        end
        if(_zz_3[7]) begin
          age_7 <= 2'b00;
        end
        if(_zz_3[8]) begin
          age_8 <= 2'b00;
        end
        if(_zz_3[9]) begin
          age_9 <= 2'b00;
        end
        if(_zz_3[10]) begin
          age_10 <= 2'b00;
        end
        if(_zz_3[11]) begin
          age_11 <= 2'b00;
        end
        if(_zz_3[12]) begin
          age_12 <= 2'b00;
        end
        if(_zz_3[13]) begin
          age_13 <= 2'b00;
        end
        if(_zz_3[14]) begin
          age_14 <= 2'b00;
        end
        if(_zz_3[15]) begin
          age_15 <= 2'b00;
        end
      end
      if(when_ResultBank_l181) begin
        if(_zz_4[0]) begin
          store_0 <= io_write_data;
        end
        if(_zz_4[1]) begin
          store_1 <= io_write_data;
        end
        if(_zz_4[2]) begin
          store_2 <= io_write_data;
        end
        if(_zz_4[3]) begin
          store_3 <= io_write_data;
        end
        if(_zz_4[4]) begin
          store_4 <= io_write_data;
        end
        if(_zz_4[5]) begin
          store_5 <= io_write_data;
        end
        if(_zz_4[6]) begin
          store_6 <= io_write_data;
        end
        if(_zz_4[7]) begin
          store_7 <= io_write_data;
        end
        if(_zz_4[8]) begin
          store_8 <= io_write_data;
        end
        if(_zz_4[9]) begin
          store_9 <= io_write_data;
        end
        if(_zz_4[10]) begin
          store_10 <= io_write_data;
        end
        if(_zz_4[11]) begin
          store_11 <= io_write_data;
        end
        if(_zz_4[12]) begin
          store_12 <= io_write_data;
        end
        if(_zz_4[13]) begin
          store_13 <= io_write_data;
        end
        if(_zz_4[14]) begin
          store_14 <= io_write_data;
        end
        if(_zz_4[15]) begin
          store_15 <= io_write_data;
        end
      end
      if(io_faultClear) begin
        _zz_io_fault <= 1'b0;
      end
      if(when_Common_l337) begin
        _zz_io_fault <= 1'b1;
      end
    end
  end


endmodule
