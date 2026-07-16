// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// FP_Mul36_gate_top.v — synth Gate 1 wrapper (spec §23.10.7).
//
// Registers all inputs and outputs once so that every timing path measured
// by the out-of-context nextpnr run is a real FF-to-FF path of the core
// (port-to-FF paths of a bare core would be unconstrained placement
// artifacts). The wrapper adds flops only — its LUT4 contribution is ~0,
// so the stat report's LUT4 count is an honest (conservative) core figure.

module FP_Mul36_gate_top (
    input             clk,
    input      [35:0] a_i,
    input      [35:0] b_i,
    output reg [71:0] p_o
);

    reg  [35:0] a_q, b_q;
    wire [71:0] p_w;

    always @(posedge clk) begin
        a_q <= a_i;
        b_q <= b_i;
        p_o <= p_w;
    end

    FP_Mul36 u_core (
        .clk (clk),
        .a   (a_q),
        .b   (b_q),
        .p   (p_w)
    );

endmodule
