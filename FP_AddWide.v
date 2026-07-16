// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

`include "attributes.vh"

// =============================================================================
// FP_AddWide.v — v1.8.0c shared wide FMA-capable add/normalize/pack datapath
// (spec §23.10.1, synth Gate 2 of §23.10.7).
//
// The single shared adder of the v1.8.0c fp32 step sequencer. Sized for the
// FMA case: operand P is an UNROUNDED 24x24 significand product held wide;
// the datapath aligns, adds/subtracts sticky-preservingly, normalizes and
// rounds ONCE. Plain FADD and FMUL-pack ride the same hardware (see operand
// conventions below). This wide path is load-bearing for both the fused-FMA
// contract (single final RNE) and the FS_DIV Markstein correction.
//
// -----------------------------------------------------------------------------
// INTERFACE CONTRACT (pinned — the step sequencer builds against this)
// -----------------------------------------------------------------------------
// Operand value convention (both operands identical shape):
//     value = (-1)^sign * sig * 2^(exp - 47)
// i.e. sig is a 48-bit unsigned significand with the unit position at
// bit 47; exp is the SIGNED unbiased exponent of sig[47] (11 bits).
//
//   * FMA / FMUL product operand P: p_sig = ma*mb, the raw unrounded 48-bit
//     product of two 24-bit significands ma,mb in [2^23, 2^24) (so
//     p_sig in [2^46, 2^48), possibly UN-normalized with p_sig[47]==0);
//     p_exp = ea + eb + 1; p_sign = sa ^ sb.
//   * Plain FADD operand (and the FMA addend) C: a 24-bit significand
//     (hidden bit included) left-aligned into sig[47:24], zero elsewhere;
//     c_exp = the operand's unbiased exponent; c_sign its sign.
//   * FMUL pack-only pass: present the product as P and a zero C
//     (c_sig = 0, c_exp = -1024).
//
// pack_mode selects what the sequencer gets back (registered outputs,
// exactly 3 cycles after the operands — see the GATE 2 FALLBACK RECORD):
//   * PACK_WIDE (1'b0) — WIDE result for internal steps: sign / signed
//     exponent / 48-bit significand normalized to wide_sig[47]==1,
//     ROUND-TO-ODD to the 48-bit internal width, DAZ/FTZ-EXEMPT (no
//     exponent clamping of any kind — spec §23.10.5 pins internal
//     micro-steps as flush-exempt, else the FS_DIV Markstein residual
//     flushes and misrounds near underflow). Round-to-odd composes
//     (rto_n(rto_48(x)) == rto_n(x) for any n < 48), so the sequencer may
//     re-jam this result down to its Q2.28/Q2.30 step widths and stay
//     bit-identical to the golden micro_* models. wide_zero flags exact
//     cancellation; when wide_zero==1 the wide_sign/wide_exp/wide_sig
//     values are UNSPECIFIED (a normalized significand cannot represent
//     zero — the sequencer must branch on wide_zero first).
//   * PACK_FINAL (1'b1) — final fp32 pack: a SINGLE RNE with
//     unbounded-exponent semantics, then flush-after-round FTZ
//     (|RN_unbounded(x)| < 2^-126 -> same-signed zero), overflow to
//     +/-Inf per RNE (post-round exponent > 127). Exact cancellation
//     packs +0 (RNE rule, golden ref_add/ref_fma A4/F4 rows).
//
// Each output register group only updates when its pack_mode was selected
// LATENCY (3) cycles earlier; the other group holds its previous value.
//
// PRECONDITIONS (the step sequencer's FP_CLASSIFY state guarantees these —
// violations produce unspecified data, never X/lockup):
//   * IEEE specials (NaN / Inf / zero operands) NEVER enter this block.
//     CLASSIFY filters them and emits the normative special results
//     directly (spec §23.10.5 table).
//   * A nonzero operand's sig is in [2^46, 2^48) (i.e. at most one leading
//     zero — a raw 24x24 product or a left-aligned 24-bit significand).
//   * A zero operand (sig == 0) must carry exp strictly below the other
//     operand's exp (use -1024), so it can never anchor the alignment.
//
// This is an always-flowing fixed-latency pipeline: no handshake, no
// stall, no reset — the sequencer counts cycles (PE_Core 64-bit MUL
// pipeline contract).
//
// -----------------------------------------------------------------------------
// INTERNALS — the ~76-bit sticky-preserving path as a 50-bit window
// -----------------------------------------------------------------------------
// Architecturally (spec §23.10.1) the alignment path is ~76 bits: a 48-bit
// anchor over 28 guard bits, the shiftee losing bits into a sticky. This
// implementation carries the EXACT-equivalent 50-bit window = architectural
// bits [75:26] plus a sticky flag for everything below bit 26. Equivalence
// proof sketch (verified bit-for-bit against golden_fp32 by the TB):
//   * anchor sig >= 2^46 sits at window bits [49:2] (multiples of 4);
//   * the shiftee only loses bits below the window when shamt >= 3, and
//     then its aligned magnitude is < 2^47 (window units) while the anchor
//     is >= 2^48, so |sum| > 2^47: every rounding position (48-bit wide
//     RTO at MSB-47, fp32 RNE at MSB-23) is at or above window bit 0, and
//     the below-window residue is exactly a sticky contribution;
//   * conversely, deep cancellation (result MSB < 47) forces shamt <= 2,
//     where the window loses NOTHING (fully exact, sticky == 0).
// Sticky-in-subtraction uses the exact borrow form: for effective
// subtraction with sticky, true = (a - b) - eps with 0 < eps < 1 window
// LSB, whose integer digits are those of (a - b - 1) with a nonzero
// fraction -> mag = a - b - sticky, sticky_out = sticky (exact at window
// granularity). sticky==1 implies a > b (see MSB argument above), so the
// b > a branch (shamt <= 1) is always sticky-free and exact.
//
// =============================================================================
// *** GATE 2 FALLBACK RECORD (2026-07-16) — PRE-APPROVED +1 CYCLE TAKEN ***
// The original two-stage version (stage B = add + LZC + normalize + round
// + pack in ONE cycle) measured 24.59 MHz on the LFE5UM-85F CABGA381 -6
// out-of-context gate (critical path 40.67 ns = 14.66 ns logic + 26.01 ns
// routing through diff carry chain -> LZC -> normalize barrel -> RNE
// incrementer -> pack mux) — below the 40 MHz Gate 2 criterion. Per spec
// §23.10.7 the pre-approved fallback was applied: stage B is split into
// B1 (add/sub + LZC) and B2 (normalize + round + pack), LATENCY 2 -> 3.
// This is a sequencer STEP-COUNT change only (the §23.10.6 cycle-maxima
// table already carries the headroom); the datapath is unchanged.
// =============================================================================
//
// Stage A  (registered): exponent-difference compare, anchor select,
//   sticky-preserving right alignment shift.
// Stage B1 (registered): wide add/subtract, ~50-bit LZC.
// Stage B2 (registered): normalize left shift, RTO/RNE round, pack.
// Latency EXACTLY 3.
// =============================================================================

/* verilator lint_off UNUSEDSIGNAL */

module FP_AddWide (
    input                     clk,

    // ---- operand P (product side) ----
    input                     p_sign,
    input  signed [10:0]      p_exp,
    input         [47:0]      p_sig,

    // ---- operand C (addend side) ----
    input                     c_sign,
    input  signed [10:0]      c_exp,
    input         [47:0]      c_sig,

    input                     pack_mode,     // PACK_WIDE / PACK_FINAL

    // ---- FINAL result (valid iff pack_mode was PACK_FINAL 3 cycles ago) ----
    output reg    [31:0]      final_fp32,

    // ---- WIDE result (valid iff pack_mode was PACK_WIDE 3 cycles ago) ----
    output reg                wide_sign,
    output reg signed [11:0]  wide_exp,      // exponent of wide_sig[47]
    output reg    [47:0]      wide_sig,      // normalized, wide_sig[47]==1
    output reg                wide_zero      // exact cancellation; when set,
                                             // wide_sign/exp/sig unspecified
);

    localparam PACK_WIDE  = 1'b0;
    localparam PACK_FINAL = 1'b1;

    // -------------------------------------------------------------------------
    // Stage A — unpack / compare / align
    // -------------------------------------------------------------------------
    wire signed [11:0] exp_diff = {p_exp[10], p_exp} - {c_exp[10], c_exp};
    wire               p_anchor = ~exp_diff[11];          // p_exp >= c_exp

    wire        [47:0] anchor_sig   = p_anchor ? p_sig  : c_sig;
    wire        [47:0] shiftee_sig  = p_anchor ? c_sig  : p_sig;
    wire               anchor_sign  = p_anchor ? p_sign : c_sign;
    wire               shiftee_sign = p_anchor ? c_sign : p_sign;
    wire signed [10:0] exp_ref      = p_anchor ? p_exp  : c_exp;

    // Beyond the 50-bit window everything of the shiftee is sticky. Clamp
    // the shift to 63 in that case: the barrel then shifts EVERYTHING out
    // (1+2+4+8+16+32 = 63 >= 50), so the aligned value degenerates to 0 and
    // the per-stage sticky capture accumulates |shiftee_sig| — no separate
    // zero-mux or 48-bit reduce-OR needed. Only |exp_diff| in [0,49] must
    // shift precisely, so the abs/mux runs at 6 bits; the wide compares
    // ride the carry chains.
    wire               shift_big    = (exp_diff >= 12'sd50)
                                    | (exp_diff <= -12'sd50);
    wire        [5:0]  shamt_abs    = p_anchor ? exp_diff[5:0]
                                               : (~exp_diff[5:0] + 6'd1);
    wire        [5:0]  shamt        = shamt_abs | {6{shift_big}};

    // 50-bit window right shift with per-stage sticky capture (the bits that
    // fall off each barrel stage OR into the sticky — cheaper than a second
    // shifter or a thermometer mask).
    wire [49:0] al_s0 = {shiftee_sig, 2'b00};
    wire [49:0] al_s1 = shamt[0] ? { 1'b0, al_s0[49: 1]} : al_s0;
    wire        st_s1 = shamt[0] &   al_s0[0];
    wire [49:0] al_s2 = shamt[1] ? { 2'b0, al_s1[49: 2]} : al_s1;
    wire        st_s2 = shamt[1] & (|al_s1[ 1:0]);
    wire [49:0] al_s3 = shamt[2] ? { 4'b0, al_s2[49: 4]} : al_s2;
    wire        st_s3 = shamt[2] & (|al_s2[ 3:0]);
    wire [49:0] al_s4 = shamt[3] ? { 8'b0, al_s3[49: 8]} : al_s3;
    wire        st_s4 = shamt[3] & (|al_s3[ 7:0]);
    wire [49:0] al_s5 = shamt[4] ? {16'b0, al_s4[49:16]} : al_s4;
    wire        st_s5 = shamt[4] & (|al_s4[15:0]);
    wire [49:0] al_s6 = shamt[5] ? {32'b0, al_s5[49:32]} : al_s5;
    wire        st_s6 = shamt[5] & (|al_s5[31:0]);

    wire [49:0] aligned  = al_s6;
    wire        sticky_w = st_s1|st_s2|st_s3|st_s4|st_s5|st_s6;

    // ---- Stage A pipeline registers ----
    reg        [49:0]  a_p1, b_p1;             // anchor / aligned shiftee
    reg                sticky_p1;
    reg                anchor_sign_p1, shiftee_sign_p1, eff_sub_p1;
    reg signed [10:0]  exp_ref_p1;
    reg                pack_mode_p1;

    always @(posedge clk) begin
        a_p1            <= {anchor_sig, 2'b00};
        b_p1            <= aligned;
        sticky_p1       <= sticky_w;
        anchor_sign_p1  <= anchor_sign;
        shiftee_sign_p1 <= shiftee_sign;
        eff_sub_p1      <= p_sign ^ c_sign;
        exp_ref_p1      <= exp_ref;
        pack_mode_p1    <= pack_mode;
    end

    // -------------------------------------------------------------------------
    // Stage B1 — add/sub + ~50-bit LZC
    // -------------------------------------------------------------------------
    wire        [50:0] sum_ab  = {1'b0, a_p1} + {1'b0, b_p1};
    // Exact borrow form: subtracting the sticky models true = a - (b + eps).
    wire signed [51:0] diff_ab = $signed({2'b00, a_p1})
                               - $signed({2'b00, b_p1})
                               - $signed({51'b0, sticky_p1});
    wire               diff_neg = diff_ab[51];
    // Only reachable with shamt <= 1, where sticky_p1 == 0 (exact).
    wire        [50:0] diff_ba  = {1'b0, b_p1} - {1'b0, a_p1};

    wire        [50:0] mag = eff_sub_p1 ? (diff_neg ? diff_ba : diff_ab[50:0])
                                        : sum_ab;
    wire               res_sign = (eff_sub_p1 & diff_neg) ? shiftee_sign_p1
                                                          : anchor_sign_p1;

    // ~50-bit leading-zero count (spec §23.10.1) — priority scan, last
    // assignment wins on the highest set bit. mag==0 yields the sentinel
    // 63 (all ones), which doubles as the mag_zero flag (&lzc) and shifts
    // the barrel to all-zero — no separate 51-bit NOR tree.
    function [5:0] lzc51;
        input [50:0] v;
        integer j;
        begin
            lzc51 = 6'd63;
            for (j = 0; j <= 50; j = j + 1)
                if (v[j]) lzc51 = 6'd50 - j[5:0];
        end
    endfunction

    wire        [5:0]  lzc      = lzc51(mag);
    wire               mag_zero = &lzc;

    // exponent of the leading bit: value = mag * 2^(exp_ref - 49)
    wire signed [12:0] e_res = {exp_ref_p1[10], exp_ref_p1[10], exp_ref_p1}
                             + 13'sd1
                             - $signed({7'b0, lzc});

    // ---- Stage B1 pipeline registers ----
    reg         [50:0] mag_p2;
    reg         [5:0]  lzc_p2;
    reg signed  [12:0] e_res_p2;
    reg                sticky_p2;
    reg                res_sign_p2, mag_zero_p2;
    reg                pack_mode_p2;

    always @(posedge clk) begin
        mag_p2       <= mag;
        lzc_p2       <= lzc;
        e_res_p2     <= e_res;
        sticky_p2    <= sticky_p1;
        res_sign_p2  <= res_sign;
        mag_zero_p2  <= mag_zero;
        pack_mode_p2 <= pack_mode_p1;
    end

    // -------------------------------------------------------------------------
    // Stage B2 — normalize + round + pack
    // -------------------------------------------------------------------------
    wire        [50:0] norm = mag_p2 << lzc_p2;           // norm[50]==1 if mag!=0

    // ---- WIDE pack: round-to-odd to 48 bits, flush-exempt ----
    wire               rto_jam    = (|norm[2:0]) | sticky_p2;
    wire        [47:0] wide_sig_w = norm[50:3] | {47'b0, rto_jam};

    // ---- FINAL pack: single RNE (unbounded exponent), then FTZ / overflow ----
    wire        [23:0] m24    = norm[50:27];
    wire               guard  = norm[26];
    wire               stk    = (|norm[25:0]) | sticky_p2;
    wire               rne_up = guard & (stk | norm[27]); // G & (S | LSB)
    wire        [24:0] m24r   = {1'b0, m24} + {24'd0, rne_up};
    wire               rcarry = m24r[24];                 // 1.11..1 rounded up
    // On rcarry the mantissa becomes 2^24, whose low 23 bits are ALREADY
    // zero — m24r[22:0] is the packed fraction verbatim, no 2^23 remux.
    wire signed [12:0] e_fin  = e_res_p2 + $signed({12'b0, rcarry});

    wire               ovf    = (e_fin >  13'sd127);
    wire               udf    = (e_fin < -13'sd126);      // flush-AFTER-round
    wire        [7:0]  biased = e_fin[7:0] + 8'd127;

    wire        [31:0] final_w =
        mag_zero_p2 ? 32'h0000_0000                       // exact cancel -> +0
      : ovf         ? {res_sign_p2, 8'hFF, 23'd0}         // RNE overflow -> Inf
      : udf         ? {res_sign_p2, 31'd0}                // FTZ -> signed zero
      :               {res_sign_p2, biased, m24r[22:0]};

    // ---- Stage B2 output registers (per-group pack_mode enable) ----
    always @(posedge clk) begin
        if (pack_mode_p2 == PACK_FINAL) begin
            final_fp32 <= final_w;
        end else begin
            // on wide_zero the remaining wide_* values are unspecified
            // (contract) — no zero-muxes spent on them
            wide_zero <= mag_zero_p2;
            wide_sign <= res_sign_p2;
            wide_exp  <= e_res_p2[11:0];
            wide_sig  <= wide_sig_w;
        end
    end

endmodule

/* verilator lint_on UNUSEDSIGNAL */
