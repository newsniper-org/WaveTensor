// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// FP_AccLattice_gate_top.v — GATE V20-2 wrapper (spec §27.6 — 528-bit
// exact-integer lattice unit gate; xcu55c 반쪽이 유일한 merge-blocker
// binding). 출하 microarchitecture = beat-serial (spec §27.2.1 말미
// [amendment 2026-08-16]) 에 맞춘 beat-serial 인터페이스 — PRODUCTS_PER_BEAT
// 파라미터를 core 로 그대로 인가한다 (기본 8 = 출하 형상; N=2 구성은 같은
// wrapper 에 파라미터만 바꿔 합성 — 파라미터화 정합 확인용).
//
// FP_FmaLaneBf16_gate_top.v 와 동일한 규약: 전 입력/출력을 정확히 1회
// 등록해, out-of-context run 이 재는 모든 timing path 가 unit 의 실제
// FF-to-FF path 가 되게 한다:
//   in-regs -> B  beat 스테이지 (decode/barrel/demux/compressor tree)
//   B       -> R  resolve (병렬 1-cycle 576-bit carry-propagate 가산 1회 —
//                 §27.2.1 "resolve 1회"; 100 MHz 문맥의 관심 path)
//   R       -> S3 sign/magnitude + coarse 우선순위 + window/CLZ
//   S3      -> S4 normalize + RTO_48 + wide/bank/fp32 인코딩 -> out-regs
// wrapper 는 flop 만 더한다 — LUT 기여 ~0 이므로 리포트의 LUT 수는 정직한
// (보수적) core 수치다.
//
// Wrapper I/O flop (N=8) = 1,267: 입력 577 (start 1 + ops 8x64 + carry 64) +
// 출력 690 (resolved 528 + wide 64 + bank 64 + fp32 32 + fault 1 + done 1).
// FF 는 GATE V20-2 에서 추적만 한다 (V9-4 관례) — LUT 만이 hard ceiling.
//
// 같은 wrapper 를 ECP5 feasibility 반쪽과 xcu55c 가 공유해 두 fabric 이
// 동일한 netlist boundary 를 재는 fp_ops 관례를 따른다.

module FP_AccLattice_gate_top #(
    parameter integer PRODUCTS_PER_BEAT = 8   // core 로 그대로 인가 (기본 8)
) (
    input                             clk,

    input                             start_i,   // beat 0 marker
    input  [PRODUCTS_PER_BEAT*64-1:0] ops_i,     // beat b: addend N*b+j
    input  [63:0]                     carry_i,   // bank carry-in (beat 0 샘플)

    output reg [527:0]                resolved_o,
    output reg [63:0]                 wide_o,
    output reg [63:0]                 bank_o,
    output reg [31:0]                 fp32_o,
    output reg                        fault_o,
    output reg                        done_o
);

    reg                              start_q;
    reg [PRODUCTS_PER_BEAT*64-1:0]   ops_q;
    reg [63:0]                       carry_q;

    wire [527:0] resolved_w;
    wire [63:0]  wide_w, bank_w;
    wire [31:0]  fp32_w;
    wire         fault_w, done_w;

    always @(posedge clk) begin
        start_q <= start_i;
        ops_q   <= ops_i;
        carry_q <= carry_i;

        resolved_o <= resolved_w;
        wide_o     <= wide_w;
        bank_o     <= bank_w;
        fp32_o     <= fp32_w;
        fault_o    <= fault_w;
        done_o     <= done_w;
    end

    FP_AccLattice #(
        .PRODUCTS_PER_BEAT (PRODUCTS_PER_BEAT)
    ) u_core (
        .clk        (clk),
        .start_i    (start_q),
        .ops_i      (ops_q),
        .carry_i    (carry_q),
        .resolved_q (resolved_w),
        .wide_q     (wide_w),
        .bank_q     (bank_w),
        .fp32_q     (fp32_w),
        .fault_q    (fault_w),
        .done_q     (done_w)
    );

endmodule
