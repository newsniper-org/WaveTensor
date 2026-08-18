// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// FP_StepSeq_gate_top.v — synth Gate 3 wrapper (spec §23.10.7).
//
// Registers all inputs and outputs once so every timing path measured by
// the out-of-context nextpnr run is a real FF-to-FF path of the unit
// (FP_Mul36/FP_AddWide gate-top precedent). The wrapper adds flops only
// (~0 LUT4); its exact FF count (113 input bits + 36 output bits = 149 —
// v1.8.0d added the 4-bit dtype_i for the CVT op class; v1.8.0e 3a-C4
// added the two 1-bit FDOT32_CR sticky outputs, 147 -> 149) is subtracted
// by gate_check.py so the Gate 3/C3 FF criterion measures the unit itself.
//
// v1.8.0e 3a-C4 §35.4 — BASE REPRODUCTION RECIPE IS NOW TWO FILES.
// The GATE V20-4 anchor (tag `fp_stepseq_base`, spec §34.3) was measured
// against the ELEVEN-port FP_StepSeq and the eleven-connection wrapper.
// Reproducing that base = current tree + `FP_StepSeq.v` at `e22e182` +
// THIS FILE at `6c84cc1`. Elaborating the 11-port base FP_StepSeq with
// the 13-connection wrapper below dies with PINMISSING. §34.2's "the
// only thing that differs is one file" is preserved as a statement about
// the anchor measurement moment; from 3a-C4 on, the two-file pin above
// replaces it. The anchor itself stays valid: the wrapper's own row in
// `fp_stepseq_base_impl_util.rpt` is LUT 0 / FF 147 / RAMB18 0 / DSP 0,
// so two 1-bit ports move the FF axis (tracking-only) and NOTHING else.
// FALSIFIER: if the C4 report's `(FP_StepSeq_gate_top)` row is not LUT 0,
// that argument is broken and the anchor must be re-measured.

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
    output reg [31:0] result_o,
    output reg        fd_special_sticky_o,
    output reg        fd_unit_fault_o
);

    reg         start_q;
    reg  [7:0]  opcode_q;
    reg  [3:0]  subop_q;
    reg  [3:0]  dtype_q;
    reg  [31:0] a_q, b_q, c_q;
    wire        busy_w, done_w;
    wire [31:0] result_w;
    wire        fd_spec_w, fd_fault_w;

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
        fd_special_sticky_o <= fd_spec_w;
        fd_unit_fault_o     <= fd_fault_w;
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
        .result    (result_w),
        .fd_special_sticky (fd_spec_w),
        .fd_unit_fault     (fd_fault_w)
    );

endmodule
