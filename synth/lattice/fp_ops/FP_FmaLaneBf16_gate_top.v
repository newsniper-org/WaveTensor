// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// FP_FmaLaneBf16_gate_top.v — v2.0 GATE F1 wrapper (spec §23.1 bf16/f16
// fused-FMA lane; the spec-risk-2 "produce an Fmax" deliverable).
//
// Registers all inputs and outputs exactly once so that every timing path
// measured by the out-of-context run is a real FF-to-FF path of the lane:
//   in-regs -> S1 unpack/classify/normalize
//   S1      -> S2 11x11 multiplier
//   S2      -> FP_AddWide stage A (through the static align mux)
//   A -> B1 -> B2                  (inside FP_AddWide)
//   B2      -> S6 special mux + result register
//   result  -> out-regs
// The wrapper adds flops only — its LUT4 contribution is ~0, so the stat
// report's LUT4 count is an honest (conservative) core figure.
//
// Wrapper I/O flops = 97: 65 input bits (16 a_narrow + 16 b_narrow +
// 32 c_fp32 + 1 dtype_bf16) + 32 output bits. gate_check.py subtracts
// exactly that number before applying the lane FF criterion.
//
// The SAME wrapper is used by the UltraScale+ per-operator gate
// (synth/scripts/synth_fp_op.tcl) so the two fabrics measure an identical
// netlist boundary and the LUT/DSP/Fmax numbers are directly comparable.

module FP_FmaLaneBf16_gate_top (
    input             clk,

    input      [15:0] a_narrow_i,
    input      [15:0] b_narrow_i,
    input             dtype_bf16_i,
    input      [31:0] c_fp32_i,

    output reg [31:0] result_fp32_o
);

    reg  [15:0] a_narrow_q, b_narrow_q;
    reg         dtype_bf16_q;
    reg  [31:0] c_fp32_q;

    wire [31:0] result_fp32_w;

    always @(posedge clk) begin
        a_narrow_q    <= a_narrow_i;
        b_narrow_q    <= b_narrow_i;
        dtype_bf16_q  <= dtype_bf16_i;
        c_fp32_q      <= c_fp32_i;

        result_fp32_o <= result_fp32_w;
    end

    FP_FmaLaneBf16 u_core (
        .clk         (clk),
        .a_narrow    (a_narrow_q),
        .b_narrow    (b_narrow_q),
        .dtype_bf16  (dtype_bf16_q),
        .c_fp32      (c_fp32_q),
        .result_fp32 (result_fp32_w)
    );

endmodule
