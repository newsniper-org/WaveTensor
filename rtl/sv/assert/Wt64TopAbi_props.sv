// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// Wt64Top 판 0 변형 검사자 — 0xFFC 판 워드와 0xF0C FP_SHAPE 판 게이트의 쌍조건을 판 0 변형에서 잰다
// (3.10 v1.0 판 값 커밋 W8, 2026-10-26). 태스크: rtl/formal/sby/Wt64Top/abi0.sby (머리가 변형 절차 · 절단 ·
// 무결성 핀 · 역-변이 표를 소유한다).
//
// ## 왜 따로 있는가
//
// 판 v1.0 본선의 같은 단언(a_rd_abi · a_rd_fpshape · a_pair_sh · a_pair_abi)은 assembly.sby 의 Wt64Top_props.sv 가
// 든다. v1.0 에서는 FP_SHAPE 의 판 게이트를 판 넷 대신 *별도 리터럴 1* 에 묶은 생성물이 포트로 갈리지 않는다 — 두
// 워드가 우연히 둘 다 0 이 아니기 때문이다. 판 0 변형(생성물의 판 상수 대입 한 줄만 0 으로 바꾼 사본 — Ident.VERSION
// 만 0 으로 바꾼 Spinal elaboration 의 생성물과 바이트 동일)에서는 그 생성물의 0xF0C 가 0 이 아니고 0xFFC 는 0 이라
// 쌍조건이 운다. 같은 하네스에 cover 태스크를 둘 두면 증거 계수 항등이 깨져 태스크를 갈랐다(assembly.sby W8 절).
//
// ## 정본 (좌표 뒤 「」 는 그 줄의 축자)
//
//   e-defined.typ:505 「합의 전 값은 0 이고」 — 판 0 의 0xFFC 읽기 기대 (F_ABI = 0).
//   e-defined.typ:463 「*번호 ≠ 0 도 `0xFFC` ≠ 0 과 함께만 낸다*」 — 쌍조건의 한 방향.
//   e-defined.typ:463 「번호가 0 이면 워드 전체가 0 이다」 — 판 0 의 FP_SHAPE 기대 (F_FP_SHAPE = 0).
//   e-defined.typ:463 「`0xFFC` 가 0 이 아닌 장치는 번호 ≠ 0 과 실제 $P$ · stepMax 를 알리고」 — 쌍조건의 다른 방향.
//
// ## 피연산자 규율
//
//   DUT 측은 top 의 MMIO 포트뿐이다 — Wt64Top 내부 넷(abiArea_* · fpShapeArea_*)을 읽지 않는다. 기대는 판 리터럴
//   (F_MAJOR = F_MINOR = 0)에서 짓는다. 하위 인스턴스는 전부 절단된다(.sby) — 0xFFC · 0xF0C 의 rdata 는 rdata mux 의
//   나중 대입(덮어쓰기)이라 절단된 유닛의 자유 rvalid · rdata 핀과 무관한 정확 등식이다 (assembly 의 a_rd_shape 선례).
//
// ## assume (전수)
//
//   initial assume (reset) 하나 — t0 의 reset (.sby 무결성 핀 ②).
module Wt64TopAbi_props (
  input logic        clk,
  input logic        reset,
  input logic [11:0] io_mmio_addr,
  input logic        io_mmio_wstrobe,
  input logic        io_mmio_rstrobe,
  input logic [31:0] io_mmio_rdata,
  input logic        io_mmio_rvalid
);
  initial assume (reset);

  logic f_past_valid = 1'b0;
  logic f_past_reset = 1'b1;
  always @(posedge clk) begin
    f_past_valid <= 1'b1;
    f_past_reset <= reset;
  end
  wire f_step = f_past_valid && !reset && !f_past_reset;

  wire [11:0] A = io_mmio_addr;
  wire R  = io_mmio_rstrobe && !io_mmio_wstrobe;
  wire al = (A[1:0] == 2'b00);

  // 판 0 변형의 기대 — (major << 16) | minor 와 FP_SHAPE 필드 배치에서 짓는다 (RTL 을 베끼지 않는다).
  localparam integer F_MAJOR   = 0;
  localparam integer F_MINOR   = 0;
  localparam [31:0]  F_ABI     = (F_MAJOR << 16) | F_MINOR;
  localparam integer F_ENC     = 1;
  localparam integer F_P       = 10;
  localparam integer F_STEPMAX = 32;
  localparam [31:0]  F_FP_SHAPE = (F_ABI != 32'd0) ? ((F_ENC << 24) | (F_STEPMAX << 9) | F_P) : 32'd0;

  // 쌍조건의 그림자 — 마지막으로 응답된 0xFFC · 0xF0C 정렬 읽기의 MMIO rdata (Wt64Top_props.sv 와 같은 꼴).
  logic        f_abiSeen = 1'b0;
  logic [31:0] f_abiVal  = 32'd0;
  logic        f_shSeen  = 1'b0;
  logic [31:0] f_shVal   = 32'd0;
  logic        f_rdAbiP  = 1'b0;
  logic        f_rdShP   = 1'b0;
  always @(posedge clk) begin
    f_rdAbiP <= !reset && R && al && (A == 12'hFFC);
    f_rdShP  <= !reset && R && al && (A == 12'hF0C);
    if (reset) begin
      f_abiSeen <= 1'b0;
      f_shSeen  <= 1'b0;
    end else begin
      if (f_rdAbiP && io_mmio_rvalid) begin
        f_abiSeen <= 1'b1;
        f_abiVal  <= io_mmio_rdata;
      end
      if (f_rdShP && io_mmio_rvalid) begin
        f_shSeen  <= 1'b1;
        f_shVal   <= io_mmio_rdata;
      end
    end
  end

  always @(posedge clk) if (f_step) begin
    if ($past(R && al && (A == 12'hFFC)))              a_v0_rd_abi:   assert (io_mmio_rvalid && io_mmio_rdata == F_ABI);
    if ($past(R && al && (A == 12'hF0C)))              a_v0_rd_sh:    assert (io_mmio_rvalid && io_mmio_rdata == F_FP_SHAPE);
    if ($past(R && al && (A == 12'hF0C)) && f_abiSeen) a_v0_pair_sh:  assert ((io_mmio_rdata[31:24] != 8'd0) == (f_abiVal != 32'd0));
    if ($past(R && al && (A == 12'hFFC)) && f_shSeen)  a_v0_pair_abi: assert ((io_mmio_rdata != 32'd0) == (f_shVal[31:24] != 8'd0));
  end

`ifdef WT64TOPABI_COVER
  // 각 증인은 단언의 *검사 항*으로 닿는다 — 전건이 서고 결론의 두 변이 판 0 대로(둘 다 0) 선 사이클이다.
  // Z1 ← Wt64Top.abi_version_v0 · a_v0_rd_abi — [의존: rdata mux 콘에 유닛 rdata 핀 — 값은 덮어쓰기라 핀과 무관(실물 근거 = 이 등식)] 판 0 변형의 0xFFC 읽기가 0 을 낸다
  always @(posedge clk) if (f_step) z1_abi_rd: cover ($past(R && al && A == 12'hFFC) && io_mmio_rvalid && io_mmio_rdata == F_ABI);
  // Z2 ← Wt64Top.abi_version_v0 · a_v0_rd_sh · a_v0_pair_sh — [의존: 위와 같다] 0xFFC 를 읽은 뒤의 0xF0C 응답에서 두 변이 다 0 이다
  always @(posedge clk) if (f_step) z2_pair_sh: cover ($past(R && al && A == 12'hF0C) && f_abiSeen && io_mmio_rvalid &&
      io_mmio_rdata == F_FP_SHAPE && io_mmio_rdata[31:24] == 8'd0 && f_abiVal == 32'd0);
  // Z3 ← Wt64Top.abi_version_v0 · a_v0_pair_abi — [의존: 위와 같다] 0xF0C 를 읽은 뒤의 0xFFC 응답에서 두 변이 다 0 이다
  always @(posedge clk) if (f_step) z3_pair_abi: cover ($past(R && al && A == 12'hFFC) && f_shSeen && io_mmio_rvalid &&
      io_mmio_rdata == 32'd0 && f_shVal[31:24] == 8'd0);
`endif
endmodule

bind Wt64Top Wt64TopAbi_props chk (.*);
