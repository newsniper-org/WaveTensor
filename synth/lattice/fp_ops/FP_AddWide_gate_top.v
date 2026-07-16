// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// FP_AddWide_gate_top.v — synth Gate 2 wrapper (spec §23.10.7).
//
// Registers all inputs and outputs once so that every timing path measured
// by the out-of-context nextpnr run is a real FF-to-FF path of the core
// (stage A: in-regs -> A/B pipeline regs through the alignment shifter;
// stage B: pipeline regs -> pack output regs through add+LZC+normalize+
// round). The wrapper adds flops only — its LUT4 contribution is ~0, so
// the stat report's LUT4 count is an honest (conservative) core figure.

module FP_AddWide_gate_top (
    input                     clk,

    input                     p_sign_i,
    input  signed [10:0]      p_exp_i,
    input         [47:0]      p_sig_i,
    input                     c_sign_i,
    input  signed [10:0]      c_exp_i,
    input         [47:0]      c_sig_i,
    input                     pack_mode_i,

    output reg    [31:0]      final_fp32_o,
    output reg                wide_sign_o,
    output reg signed [11:0]  wide_exp_o,
    output reg    [47:0]      wide_sig_o,
    output reg                wide_zero_o
);

    reg                p_sign_q, c_sign_q, pack_mode_q;
    reg signed [10:0]  p_exp_q, c_exp_q;
    reg        [47:0]  p_sig_q, c_sig_q;

    wire       [31:0]  final_fp32_w;
    wire               wide_sign_w, wide_zero_w;
    wire signed [11:0] wide_exp_w;
    wire       [47:0]  wide_sig_w;

    always @(posedge clk) begin
        p_sign_q     <= p_sign_i;
        p_exp_q      <= p_exp_i;
        p_sig_q      <= p_sig_i;
        c_sign_q     <= c_sign_i;
        c_exp_q      <= c_exp_i;
        c_sig_q      <= c_sig_i;
        pack_mode_q  <= pack_mode_i;

        final_fp32_o <= final_fp32_w;
        wide_sign_o  <= wide_sign_w;
        wide_exp_o   <= wide_exp_w;
        wide_sig_o   <= wide_sig_w;
        wide_zero_o  <= wide_zero_w;
    end

    FP_AddWide u_core (
        .clk        (clk),
        .p_sign     (p_sign_q),
        .p_exp      (p_exp_q),
        .p_sig      (p_sig_q),
        .c_sign     (c_sign_q),
        .c_exp      (c_exp_q),
        .c_sig      (c_sig_q),
        .pack_mode  (pack_mode_q),
        .final_fp32 (final_fp32_w),
        .wide_sign  (wide_sign_w),
        .wide_exp   (wide_exp_w),
        .wide_sig   (wide_sig_w),
        .wide_zero  (wide_zero_w)
    );

endmodule
