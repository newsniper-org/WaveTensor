// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

`include "attributes.vh"

// =============================================================================
// FP_Mul36.v — v1.8.0c shared fp32 multiplier core (spec §23.10.1, synth
// Gate 1 of §23.10.7).
//
// One raw 36x36 -> 72 UNSIGNED integer multiplier, shared by the v1.8.0c
// step sequencer for BOTH:
//   * packed fp32 mantissa products  — 24x24 significand products held
//     unrounded (48 bits) for the wide FMA path (FP_AddWide.v), and
//   * unpacked fixed-point step-sequence products — Q2.28 rsqrt NR steps
//     (RSQRT_FRAC=28) and Q2.30 div/exp2 reciprocal/Horner steps
//     (DIV_FRAC/EXP2_FRAC=30, see scripts/golden_fp32.py). Worst operand
//     width in the pinned step programs is ~32 bits (Q2.30), so 36x36
//     covers every step with margin.
//
// There is deliberately NO fp-specific logic in here — significand
// extraction, round-to-odd jamming, RNE and packing all live in the step
// sequencer / FP_AddWide. This block is a pure integer multiplier.
//
// Structure (Gate 1 pass criteria drive the shape):
//   36 = 2x18, so the product decomposes into exactly FOUR 18x18 partial
//   products — the exact shape of the ECP5 MULT18X18D primitive. yosys
//   synth_ecp5 must map this to exactly 4 MULT18X18D (hard gate: more
//   means the mapper decomposed differently — the Vivado-35-DSP vs
//   yosys-497-MULT divergence class the gate exists for).
//
//   Stage 1 (registered): the four 18x18 partial products.
//   Stage 2 (registered): the recombination sum
//       p = hh*2^36 + (lh + hl)*2^18 + ll
//
// Latency is EXACTLY 2 cycles, one result per cycle possible. This is an
// always-flowing pipeline: no handshake, no stall, no reset — the step
// sequencer counts cycles and owns all validity bookkeeping (same contract
// as the PE_Core 64-bit MUL pipeline, whose valid flags live outside the
// arithmetic registers).
//
// DSP inference is marked with the repo's vendor-neutral `WT_USE_DSP
// attribute macro (include/attributes.vh), the PE_Core.v:1569 precedent:
// a no-op under yosys (techmap infers MULT18X18D automatically),
// (* use_dsp = "yes" *) under Vivado, syn_multstyle under Radiant.
// =============================================================================

module FP_Mul36 (
    input             clk,
    input      [35:0] a,
    input      [35:0] b,
    output reg [71:0] p        // a * b, exact, 2 cycles after a/b
);

    // -------------------------------------------------------------------------
    // Stage 1 — four 18x18 unsigned partial products, registered.
    // Each line is one MULT18X18D. The LHS context (36-bit regs) widens the
    // 18-bit operands before the multiply, so each product is exact.
    // -------------------------------------------------------------------------
    `WT_USE_DSP reg [35:0] pp_ll_p1;   // a[17:0]  * b[17:0]
    `WT_USE_DSP reg [35:0] pp_lh_p1;   // a[17:0]  * b[35:18]
    `WT_USE_DSP reg [35:0] pp_hl_p1;   // a[35:18] * b[17:0]
    `WT_USE_DSP reg [35:0] pp_hh_p1;   // a[35:18] * b[35:18]

    always @(posedge clk) begin
        pp_ll_p1 <= a[17:0]  * b[17:0];
        pp_lh_p1 <= a[17:0]  * b[35:18];
        pp_hl_p1 <= a[35:18] * b[17:0];
        pp_hh_p1 <= a[35:18] * b[35:18];
    end

    // -------------------------------------------------------------------------
    // Stage 2 — recombination sum, registered.
    //   {hh, ll} == hh*2^36 + ll  (exact: both partials are 36 bits wide)
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        p <= {pp_hh_p1, pp_ll_p1}
           + ({36'b0, pp_lh_p1} << 18)
           + ({36'b0, pp_hl_p1} << 18);
    end

endmodule
