// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// FP_AccLatticeBeat2_gate_top.v — GATE V20-2 ECP5 반쪽 feasibility
// MEASUREMENT (spec §27.6 — gate 판정 대상 아님) 의 beat-serial 측정 wrapper.
//
// 전 입력/출력을 정확히 1회 레지스터해 out-of-context run 이 재는 모든
// timing path 가 실제 FF-to-FF path 가 되게 한다 (fp_ops wrapper 관례 —
// FP_FmaLaneBf16_gate_top.v 동형). wrapper 는 flop 만 더한다 (LUT4 ~0).
//
// Wrapper I/O flops = 819: 입력 129 (start 1 + op_a 64 + op_b 64) +
// 출력 690 (resolved 528 + wide 64 + bank 64 + fp32 32 + fault 1 + done 1).
// gate_check.py 의 measurement 항이 FF 보고에서 이 수를 뺀다 (추적만).

module FP_AccLatticeBeat2_gate_top (
    input              clk,

    input              start_i,
    input      [63:0]  op_a_i,
    input      [63:0]  op_b_i,

    output reg [527:0] resolved_o,
    output reg [63:0]  wide_o,
    output reg [63:0]  bank_o,
    output reg [31:0]  fp32_o,
    output reg         fault_o,
    output reg         done_o
);

    reg         start_q;
    reg  [63:0] op_a_q, op_b_q;

    wire [527:0] resolved_w;
    wire [63:0]  wide_w, bank_w;
    wire [31:0]  fp32_w;
    wire         fault_w, done_w;

    always @(posedge clk) begin
        start_q <= start_i;
        op_a_q  <= op_a_i;
        op_b_q  <= op_b_i;

        resolved_o <= resolved_w;
        wide_o     <= wide_w;
        bank_o     <= bank_w;
        fp32_o     <= fp32_w;
        fault_o    <= fault_w;
        done_o     <= done_w;
    end

    FP_AccLatticeBeat2 u_core (
        .clk        (clk),
        .start_i    (start_q),
        .op_a_i     (op_a_q),
        .op_b_i     (op_b_q),
        .resolved_q (resolved_w),
        .wide_q     (wide_w),
        .bank_q     (bank_w),
        .fp32_q     (fp32_w),
        .fault_q    (fault_w),
        .done_q     (done_w)
    );

endmodule
