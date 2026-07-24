// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// FP_StepSeq_gate_top.v — synth Gate 3 wrapper (spec §23.10.7).
//
// Registers all inputs and outputs once so every timing path measured by
// the out-of-context nextpnr run is a real FF-to-FF path of the unit
// (FP_Mul36/FP_AddWide gate-top precedent). The wrapper adds flops only
// (~0 LUT4); its exact FF count (113 input bits + 34 output bits = 147 —
// v1.8.0d added the 4-bit dtype_i for the CVT op class) is subtracted by
// gate_check.py so the Gate 3/C3 FF criterion measures the unit itself.

module FP_StepSeq_gate_top (
    input             clk,
    input             start_i,
    input      [7:0]  opcode_i,
    input      [3:0]  subop_i,
    input      [3:0]  dtype_i,
    input      [31:0] a_i,
    input      [31:0] b_i,
    input      [31:0] c_i,
    output reg        busy_o,
    output reg        done_o,
    output reg [31:0] result_o
);

    reg         start_q;
    reg  [7:0]  opcode_q;
    reg  [3:0]  subop_q;
    reg  [3:0]  dtype_q;
    reg  [31:0] a_q, b_q, c_q;
    wire        busy_w, done_w;
    wire [31:0] result_w;

    always @(posedge clk) begin
        start_q  <= start_i;
        opcode_q <= opcode_i;
        subop_q  <= subop_i;
        dtype_q  <= dtype_i;
        a_q      <= a_i;
        b_q      <= b_i;
        c_q      <= c_i;
        busy_o   <= busy_w;
        done_o   <= done_w;
        result_o <= result_w;
    end

    FP_StepSeq u_core (
        .clk       (clk),
        .start     (start_q),
        .opcode_in (opcode_q),
        .subop_in  (subop_q),
        .dtype_in  (dtype_q),
        .a_in      (a_q),
        .b_in      (b_q),
        .c_in      (c_q),
        .busy      (busy_w),
        .done      (done_w),
        .result    (result_w)
    );

endmodule
