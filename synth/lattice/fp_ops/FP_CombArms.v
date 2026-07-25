// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// FP_CombArms.v — standalone unit-test/synth top for the v1.8.0e 0e1
// combinational MU-arm datapaths (spec §25.2.1 / §25.2.3). Instantiates
// THE single-source functions of include/fp_comb_arms.vh — the same
// functions the PE_Core.v MU-gated dispatch arms slice — so the unit TB
// (tb_fp_combarms.py) proves exactly the cells the arms dispatch, and a
// standalone yosys run measures their LUT/MULT cost in isolation (the
// informational evidence for the §25.5.1 0-new-multipliers pin: the
// gamma products are LUT-structural shift-adds, FMINMAX is compare-only).
//
// Registered I/O (the *_gate_top convention) so every measured path is
// FF-to-FF; latency exactly 1 for both arms (they are combinational in
// PE_Core — the flops here are wrapper-only).
//
// Lane maps (the §25 pins, golden lanes_to_frags):
//   fmm_a  4 f32 lanes,  lane i at [32i+31:32i]  (2-frag A wave)
//   fmm_b  the ONE broadcast B (payload_b[31:0] low-word convention)
//   gmw_a  16 int4 lanes, lane i at [4i+3:4i]    (single-frag payload_a)
//   gmw_g  16 int4 gamma lanes, same map          (imm64 XOR OPREF value)
//   *_y    128b results = 2 fragments (fmm lane i at [32i+31:32i],
//          gmw lane i at [8i+7:8i])

module FP_CombArms (
    input               clk,
    input       [127:0] fmm_a,
    input       [31:0]  fmm_b,
    input               fmm_max,     // 0: minimumNumber / 1: maximumNumber
    input       [63:0]  gmw_a,
    input       [63:0]  gmw_g,
    output reg  [127:0] fmm_y,
    output reg  [127:0] gmw_y
);

    `include "fp_comb_arms.vh"

    // hoisted function results (§23.8 — the wires are consumed, never
    // the function calls), concatenation order = lane 3 down to lane 0
    wire [127:0] fmm_w = {fminmax_lane_f32(fmm_a[127:96], fmm_b, fmm_max),
                          fminmax_lane_f32(fmm_a[95:64],  fmm_b, fmm_max),
                          fminmax_lane_f32(fmm_a[63:32],  fmm_b, fmm_max),
                          fminmax_lane_f32(fmm_a[31:0],   fmm_b, fmm_max)};
    wire [127:0] gmw_w = gamma_mul_w_128(gmw_a, gmw_g);

    always @(posedge clk) begin
        fmm_y <= fmm_w;
        gmw_y <= gmw_w;
    end

endmodule
