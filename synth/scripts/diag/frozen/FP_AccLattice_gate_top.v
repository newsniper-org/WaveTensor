// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// FP_AccLattice_gate_top.v — GATE V20-2 wrapper (spec §27.6 — 528-bit
// exact-integer lattice unit gate; xcu55c 반쪽이 유일한 merge-blocker
// binding).
//
// FP_FmaLaneBf16_gate_top.v 와 동일한 규약: 전 입력/출력을 정확히 1회
// 등록해, out-of-context run 이 재는 모든 timing path 가 unit 의 실제
// FF-to-FF path 가 되게 한다:
//   in-regs -> S1 decode/barrel/demux/compressor tree -> row regs
//   S1      -> S2 resolve (576-bit carry-propagate 가산 1회 — §27.2.1
//              "resolve 1회"; 100 MHz 문맥의 관심 path)
//   S2      -> S3 sign/magnitude + coarse 우선순위 + window/CLZ
//   S3      -> S4 normalize + RTO_48 + wide/bank/fp32 인코딩 -> out-regs
// wrapper 는 flop 만 더한다 — LUT 기여 ~0 이므로 리포트의 LUT 수는 정직한
// (보수적) core 수치다.
//
// Wrapper I/O flop = 2,801: 입력 2,112 (33 addend x 64b wide field) +
// 출력 689 (resolved 528 + wide 64 + bank 64 + fp32 32 + fault 1).
// FF 는 GATE V20-2 에서 추적만 한다 (V9-4 관례) — LUT 만이 hard ceiling.
//
// 같은 wrapper 를 ECP5 feasibility 반쪽(후속 beat-serial 구성)과 xcu55c
// 가 공유해 두 fabric 이 동일한 netlist boundary 를 재는 fp_ops 관례를
// 따른다 (full-parallel 기본형 자체는 xcu55c 대상 — FP_AccLattice.v 헤더).

module FP_AccLattice_gate_top (
    input                  clk,

    // 33 x 64-bit wide field — addend k = [64k+63 : 64k], k=32 = carry-in
    input  [33*64-1:0]     addends_flat_i,

    output reg [527:0]     resolved_o,
    output reg [63:0]      wide_o,
    output reg [63:0]      bank_o,
    output reg [31:0]      fp32_o,
    output reg             fault_o
);

    reg  [33*64-1:0] addends_flat_q;

    wire [527:0] resolved_w;
    wire [63:0]  wide_w;
    wire [63:0]  bank_w;
    wire [31:0]  fp32_w;
    wire         fault_w;

    always @(posedge clk) begin
        addends_flat_q <= addends_flat_i;

        resolved_o <= resolved_w;
        wide_o     <= wide_w;
        bank_o     <= bank_w;
        fp32_o     <= fp32_w;
        fault_o    <= fault_w;
    end

    FP_AccLattice u_core (
        .clk          (clk),
        .addends_flat (addends_flat_q),
        .resolved_q   (resolved_w),
        .wide_q       (wide_w),
        .bank_q       (bank_w),
        .fp32_q       (fp32_w),
        .fault_q      (fault_w)
    );

endmodule
