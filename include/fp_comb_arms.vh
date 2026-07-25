// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// fp_comb_arms.vh — the v1.8.0e 0e1 combinational MU-arm datapaths
// (spec §25.2.1 / §25.2.3): 0x79 FMINMAX per-lane frozen-IEEE compare
// cell and the 0x6B GAMMA_MUL_W 16-lane exact widening multiply.
//
// SINGLE-SOURCE FUNCTION INCLUDE (the fp_narrow_f32.vh convention,
// `include`d inside the module body): the same two functions are
// instantiated by the PE_Core.v MU-gated dispatch arms AND by the
// standalone unit-test top synth/lattice/fp_ops/FP_CombArms.v, so the
// unit TB proves exactly the cells the MU arm dispatches. Golden twins:
// scripts/golden_fp32.py ref_fminmax_lane / ref_gamma_mul_w_lane.
//
// Both arms are combinational, single-cycle, and NEVER touch the fp
// step sequencer (§25 staging pin). Neither may infer a multiplier:
// FMINMAX is compare-only; the GAMMA products are built LUT-STRUCTURAL
// as signed shift-adds (the §25.5.1 MULT-pin suppression mechanism —
// the named C6 +1-drift lesson; a bare `*` could tempt DSP inference).
//
// yosys note (§23.8): callers assign each function result to a wire and
// consume the WIRE — no function-call result indexing.

// ---------------------------------------------------------------------------
// 0x79 FMINMAX — one f32 lane vs the broadcast B (frozen IEEE-2019
// minimumNumber/maximumNumber, six pinned rows of §25.2.1):
//   (1) -0 < +0 natively            (key(-0)=0x7FFFFFFF < key(+0)=0x80000000)
//   (2) one NaN -> the NUMBER, bit pattern unchanged (denormals included)
//   (3) both NaN -> canonical qNaN 0x7FC00000
//   (4) sNaN quieted to canonical (any NaN-producing cell emits canonical;
//       a lone sNaN against a number still loses per row 2)
//   (5) offset-transform total order: dedicated comparator key
//       fca_key = a[31] ? ~a : (a ^ 0x80000000), then EXACTLY ONE unsigned
//       32-bit compare per lane (signed-int-tree reuse stays forbidden)
//   (6) denormal cells BIT-PATTERN-PRESERVING, DAZ-EXEMPT — raw bits only,
//       never a decode/DAZ stage (golden ref_fminmax_lane pin)
// Tie note: the key is a bijection, so key equality <=> identical bit
// patterns — the min/max tie select is value-indifferent by construction.
// ---------------------------------------------------------------------------
function [31:0] fminmax_lane_f32;
    input [31:0] fca_a;       // lane bits, RAW (DAZ-exempt)
    input [31:0] fca_b;       // broadcast B bits, RAW
    input        fca_max;     // 0: minimumNumber, 1: maximumNumber
    reg          fca_an, fca_bn, fca_a_wins_min;
    reg [31:0]   fca_ka, fca_kb;
    begin
        fca_an = (fca_a[30:23] == 8'hFF) && (|fca_a[22:0]);
        fca_bn = (fca_b[30:23] == 8'hFF) && (|fca_b[22:0]);
        fca_ka = fca_a[31] ? ~fca_a : (fca_a ^ 32'h8000_0000);
        fca_kb = fca_b[31] ? ~fca_b : (fca_b ^ 32'h8000_0000);
        fca_a_wins_min = (fca_ka <= fca_kb);        // the ONE compare
        if (fca_an && fca_bn)
            fminmax_lane_f32 = 32'h7FC0_0000;       // rows 3+4
        else if (fca_an)
            fminmax_lane_f32 = fca_b;               // row 2 (bit-preserved)
        else if (fca_bn)
            fminmax_lane_f32 = fca_a;
        else
            fminmax_lane_f32 = (fca_a_wins_min ^ fca_max) ? fca_a : fca_b;
    end
endfunction

// ---------------------------------------------------------------------------
// 0x6B GAMMA_MUL_W — 16 lanes of EXACT widening int4 x int4 -> int8
// (§25.2.3): out lane i = sext8(a4[i]) * sext8(g4[i]) at bits [8i+7:8i]
// (the lane-order pin, spec+golden+SDK together). RANGE PROOF: products
// lie in [-56, +64] ⊂ int8 — rounding-free AND saturation-free.
//
// LUT-STRUCTURAL product (DSP-inference suppression by construction):
// with g = g0 + 2*g1 + 4*g2 - 8*g3 (two's-complement bit weights of the
// signed 4-bit gamma), the product is the mod-2^8 sum
//     (g0 ? va : 0) + (g1 ? va<<1 : 0) + (g2 ? va<<2 : 0) - (g3 ? va<<3 : 0)
// over the sign-extended va — exact in 8-bit arithmetic because the true
// value fits int8. A map loop over independent lanes (not a reduction —
// the §23.8 tree law binds reductions).
// ---------------------------------------------------------------------------
function [127:0] gamma_mul_w_128;
    input [63:0] gmw_a;       // 16 int4 lanes, lane i at [4i+3:4i]
    input [63:0] gmw_g;       // 16 int4 gamma lanes, same lane map
    integer      gmw_i;
    reg [3:0]    gmw_a4, gmw_g4;
    reg [7:0]    gmw_va, gmw_p;
    begin
        gamma_mul_w_128 = 128'h0;
        for (gmw_i = 0; gmw_i < 16; gmw_i = gmw_i + 1) begin
            gmw_a4 = gmw_a[4*gmw_i +: 4];
            gmw_g4 = gmw_g[4*gmw_i +: 4];
            gmw_va = {{4{gmw_a4[3]}}, gmw_a4};      // sext8(a4)
            gmw_p  = (gmw_g4[0] ? gmw_va : 8'h0)
                   + (gmw_g4[1] ? {gmw_va[6:0], 1'b0} : 8'h0)
                   + (gmw_g4[2] ? {gmw_va[5:0], 2'b0} : 8'h0)
                   - (gmw_g4[3] ? {gmw_va[4:0], 3'b0} : 8'h0);
            gamma_mul_w_128[8*gmw_i +: 8] = gmw_p;
        end
    end
endfunction
