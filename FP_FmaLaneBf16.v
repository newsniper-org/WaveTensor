// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

`include "attributes.vh"

// =============================================================================
// FP_FmaLaneBf16.v — v2.0 TRAIN unified bf16/f16 fused-FMA lane
// (spec §23.1 normative bullet; the spec-risk-2 "v2.0's first milestone is
// producing an Fmax" pre-synth gate deliverable).
//
// ONE lane of the v2.0 FP_LANES array. Computes
//
//       result_fp32 = RN( widen(a_narrow) * widen(b_narrow) + DAZ(c_fp32) )
//
// with the product held EXACT and exactly ONE round-to-nearest-even, taken
// in the fp32 accumulate. There is no bf16/f16 accumulator anywhere in the
// block: the only pack path out of this lane is fp32 (see STRUCTURAL
// PROHIBITION below).
//
// -----------------------------------------------------------------------------
// NORMATIVE CONTRACT (spec §23.1, one bullet — transcribed and pinned here)
// -----------------------------------------------------------------------------
//   C1  ONE 11-bit-mantissa multiplier covers BOTH formats. f16 has an
//       11-bit significand (10 explicit + hidden); bf16 has an 8-bit
//       significand (7 explicit + hidden). The multiplier is therefore
//       sized by the WIDER of the two — f16 — and bf16 rides underneath by
//       zero-extending its 8-bit significand into the 11-bit operand port
//       (the top 3 bits are simply zero). There is no packing and no
//       dual-issue trick; bf16 wastes 3 bits of each operand. The spec's
//       terse "11-bit mantissa multiplier covers both" does NOT mean bf16
//       has an 11-bit mantissa.
//   C2  The product is kept EXACT in the wide-exponent internal format —
//       no rounding at the product. The internal format is FP_AddWide's
//       pinned operand convention, value = (-1)^sign * sig * 2^(exp-47)
//       with a 48-bit significand (unit at bit 47) and a signed 11-bit
//       exponent. Both narrow products land in [2^46, 2^48) EXACTLY under
//       a STATIC left-align (see ALIGN ALGEBRA), so C2 costs one 2:1 wire
//       mux and zero rounding logic.
//   C3  Exactly ONE RNE, in the fp32 accumulate — FP_AddWide's PACK_FINAL
//       (single RNE with unbounded-exponent semantics, then flush-after-
//       round FTZ, overflow to +/-Inf).
//   C4  bf16-accumulate is STRUCTURALLY forbidden (no industry precedent).
//   C5  FP_LANES is a v2.0 array parameter; this module is ONE lane and
//       carries no lane count. (The gate report re-derives the per-fabric
//       lane ceiling from measurement — the spec's "ECP5 caps FP_LANES=2"
//       was a multiplier-headroom claim measured on the v1.8.0a-era Pod.)
//
// -----------------------------------------------------------------------------
// C4 IS STRUCTURAL, NOT POLICY
// -----------------------------------------------------------------------------
// The only pack path in this lane is FP_AddWide's PACK_FINAL, whose result
// port is a hard 32-bit fp32 (`output reg [31:0] final_fp32`). FP_AddWide
// has exactly two pack modes and neither is a narrow format, so there is no
// bf16/f16 rounding hardware anywhere in the lane to accumulate INTO. C4 is
// therefore enforced by construction, not merely by decode legality.
// Narrowing back to bf16/f16 remains reachable ONLY through the named
// program-visible 0x7C STORE_QUANT / 0x77 CVT path (the §23.3 single rule),
// which is outside this block.
//
// -----------------------------------------------------------------------------
// OPERAND-LOAD POLICY (pinned here; mirrored by golden ref_fma_bf16/_f16)
// -----------------------------------------------------------------------------
// The lane is defined to be BIT-IDENTICAL to "CVT WIDEN to fp32, then fused
// fp32 FMA". That makes the already-normative §23.10.5 widen semantics the
// operand-load contract instead of inventing a second one, and it closes
// the WIDEN-then-FMA vs fused-FMA drift hole by construction:
//   * bf16 exponent field 0  -> SIGNED ZERO (true zero AND all 254 bf16
//     subnormals) — COMMIT-0 pin 6, the DAZ-consistent flush.
//   * f16 exponent field 0, mantissa != 0 -> HONORED EXACTLY. Every f16
//     subnormal is an fp32 NORMAL (min f16 subnormal 2^-24 >> fp32 min
//     normal 2^-126), so ref_widen_f16 injects it exactly and this lane
//     must too. It costs one 10-bit leading-one scan + one 10-bit left
//     shift (the ASYMMETRY with bf16 is deliberate and is the pinned
//     §23.10.5 behaviour, not an oversight).
//   * ANY narrow NaN (sNaN included) -> fp32 canonical qNaN 0x7FC00000,
//     sign dropped (COMMIT-0 pin 2).
//   * c_fp32 exponent field 0 -> same-signed zero (DAZ at operand capture,
//     COMMIT-0 pin 7 / golden `decode`). This is also STRUCTURALLY forced:
//     FP_AddWide's C convention is a 24-bit significand with the hidden
//     bit, i.e. normals only.
// The IEEE special-case result table is ref_fma's verbatim, in ref_fma's
// order (NaN; then Inf from the product side incl. Inf*0 and Inf-Inf;
// then Inf addend; then zero product with zero addend).
//
// -----------------------------------------------------------------------------
// ALIGN ALGEBRA (why C2 is free)
// -----------------------------------------------------------------------------
// Let ma,mb be the significands and ea_eff,eb_eff the fp32-style unbiased
// exponents of the leading significand bit.
//   bf16: ma,mb in [2^7,2^8)   -> ma*mb in [2^14,2^16); << 32 -> [2^46,2^48)
//   f16 : ma,mb in [2^10,2^11) -> ma*mb in [2^20,2^22); << 26 -> [2^46,2^48)
// Both land in FP_AddWide's required window under a STATIC shift, so the
// "shifter" is a 2:1 mux of two fixed wire slices — no barrel, no rounding.
// The exponent is DTYPE-AGNOSTIC and identical to the shipped fp32 path
// (FP_StepSeq: aw_pexp = ex_ab1):
//       p_exp = ea_eff + eb_eff + 1
// Proof for bf16: value = ma*mb*2^(ea_eff-7+eb_eff-7) = (ma*mb<<32) *
// 2^(ea_eff+eb_eff+1-47). For f16 replace 7->10 and 32->26. Both reduce to
// the same p_exp. Range: bf16 p_exp in [-251,255], f16 in [-47,31] — both
// fit the signed 11-bit port [-1024,1023] with margin and never collide
// with the -1024 zero sentinel.
//
// -----------------------------------------------------------------------------
// REUSE DECISIONS
// -----------------------------------------------------------------------------
// FP_AddWide.v — REUSED VERBATIM, no datapath change. It was built for
//   exactly the C2+C3 contract ("this wide path is load-bearing for the
//   fused-FMA contract (single final RNE)"), its operand window is exactly
//   what the static align produces, its C operand is exactly the fp32
//   accumulator shape, and PACK_FINAL is exactly one RNE + flush-after-
//   round FTZ. pack_mode is tied to PACK_FINAL, so the PACK_WIDE
//   round-to-odd cone and the entire wide output register group constant-
//   fold away in this instance.
//
// FP_Mul36.v — DELIBERATELY NOT REUSED. Two independent reasons:
//   (a) SHAPE. FP_Mul36 is a 36x36->72 multiplier decomposed into exactly
//       four 18x18 partial products to map to exactly 4 MULT18X18D (its
//       Gate 1 hard criterion). This lane needs 11x11->22, i.e. at most
//       ONE 18x18. Instantiating FP_Mul36 per lane would burn 4x the
//       multiplier budget at ~8% utilization — and multipliers are the
//       scarce resource on the ECP5 verification vehicle.
//   (b) ARCHITECTURE. FP_Mul36 is a SHARED, sequentially-scheduled
//       resource: exactly one instance per Cluster, inside the single
//       FP_StepSeq behind MUL_OPS_SUPPORTED. FP_LANES demands INDEPENDENT
//       per-lane multipliers running CONCURRENTLY. A shared sequential
//       multiplier cannot serve a lane array.
//   What IS inherited from FP_Mul36 is its contract template, verbatim:
//   fixed latency, always-flowing, no handshake / no stall / no reset,
//   validity bookkeeping owned by the caller, and the vendor-neutral
//   `WT_USE_DSP attribute on the product register.
//
// -----------------------------------------------------------------------------
// PIPELINE — LATENCY EXACTLY 6, one result per cycle
// -----------------------------------------------------------------------------
//   S1 (reg): unpack + classify + f16-subnormal normalize; exponent add
//             p_exp = ea_eff + eb_eff + 1; fp32 addend unpack + DAZ;
//             IEEE special-case encode.
//   S2 (reg): the 11x11 -> 22 significand multiply (`WT_USE_DSP).
//   S3 (reg): FP_AddWide stage A  (static align mux feeds it combinationally)
//   S4 (reg): FP_AddWide stage B1 (add/sub + LZC)
//   S5 (reg): FP_AddWide stage B2 (normalize + single RNE + fp32 pack)
//   S6 (reg): IEEE special-case output mux.
// Six registered stages == the upper end of the spec-risk-2 "5-6 stage
// fused FMA" assumption the gate exists to test.
//
// The special-case result is NOT pipelined as 32 bits: it is carried as a
// 3-bit {kind,sign} code (none / qNaN / Inf / zero) and re-expanded at S6.
// The one special case whose result is a full 32-bit value — zero product
// with a finite nonzero addend, result = the addend — rides the DATAPATH
// instead (P presented as a zero operand, exp -1024, per FP_AddWide's
// "FMUL pack-only pass" convention), so it costs no pipeline registers at
// all. When a multiplicand is zero/Inf/NaN its significand is forced to 0
// and p_exp to the -1024 sentinel, so FP_AddWide's operand preconditions
// hold on EVERY cycle, special or not — the block never sees an
// out-of-window operand and never emits X.
//
// This is an always-flowing fixed-latency pipeline: no handshake, no
// stall, no reset (same contract as FP_Mul36 / FP_AddWide / the PE_Core
// 64-bit MUL pipeline).
//
// -----------------------------------------------------------------------------
// SINGLE-ROUNDING DISCRIMINATION (what the TB must and must not claim)
// -----------------------------------------------------------------------------
// For narrow inputs the exact product has at most 22 significand bits
// (f16) or 16 (bf16), so it is EXACTLY fp32-representable whenever its
// exponent is in fp32's normal range. In that band the fused result and a
// naive round(a*b)-then-add are provably IDENTICAL, and no test vector can
// separate them. The contract is observationally discriminated ONLY where
// a separate fp32 multiply would lose the product:
//   * product UNDERFLOW: |a*b| below fp32 min normal (reachable — bf16
//     product exponents reach -251, f16 -47). A naive fp32 multiply
//     FTZ-flushes it to zero; the fused lane still contributes it to the
//     sum, which can change the result by many ulps of the addend.
//   * product OVERFLOW: |a*b| >= 2^128 (reachable — bf16 product exponents
//     reach +255). A naive fp32 multiply returns +/-Inf and the add is
//     then stuck at Inf; the fused lane can be pulled back into range by a
//     large opposite-signed addend.
// tb_fp_fmalane_bf16.py encodes exactly this: it builds vectors in both
// bands, asserts the RTL matches the FUSED reference AND differs from the
// naive one, and separately asserts fused == naive everywhere else (so the
// claim is bounded, not overstated).
// =============================================================================

/* verilator lint_off UNUSEDSIGNAL */

module FP_FmaLaneBf16 (
    input             clk,

    // ---- narrow multiplicands ----
    input      [15:0] a_narrow,
    input      [15:0] b_narrow,
    // 1 = bf16 (ISA dtype code 0x3), 0 = f16 (ISA dtype code 0x2).
    // PE_Core-side decode reduces the 4-bit mode-byte dtype to this bit;
    // the lane deliberately does not re-decode unrelated dtype codes.
    input             dtype_bf16,

    // ---- fp32 accumulate addend (the ACC-bank / C operand) ----
    input      [31:0] c_fp32,

    // ---- fp32 result, exactly LATENCY (6) cycles after the operands ----
    output reg [31:0] result_fp32
);

    // operand / addend classes
    localparam [1:0] K_NUM  = 2'd0;   // finite nonzero (post-widen, post-DAZ)
    localparam [1:0] K_ZERO = 2'd1;
    localparam [1:0] K_INF  = 2'd2;
    localparam [1:0] K_NAN  = 2'd3;

    // special-case output codes
    localparam [1:0] SPC_NONE = 2'd0; // take the datapath result
    localparam [1:0] SPC_QNAN = 2'd1;
    localparam [1:0] SPC_INF  = 2'd2;
    localparam [1:0] SPC_ZERO = 2'd3;

    localparam PACK_FINAL = 1'b1;

    // -------------------------------------------------------------------------
    // S1 combinational — narrow operand unpack / widen / classify
    //
    // Returns {sig[10:0], eef[8:0], sign, kind[1:0]} as one packed vector; the
    // caller assigns it to a wire before indexing (repo law: never index a
    // function-call result).
    //
    //   sig — the 11-bit significand fed to the multiplier, normalized so a
    //         K_NUM operand has its leading one at a known position:
    //         bf16 in [2^7,2^8) (zero-extended), f16 in [2^10,2^11).
    //         FORCED TO ZERO for every non-K_NUM class, which makes the raw
    //         product zero and keeps FP_AddWide's "zero operand" precondition
    //         satisfiable with only an exponent mux.
    //   eef — the fp32-style unbiased exponent of sig's leading one.
    //         bf16 normal    : e8 - 127
    //         f16  normal    : e5 - 15
    //         f16  subnormal : bl - 25, where bl is the 1-based position of
    //                          the highest set mantissa bit (m * 2^-24 with
    //                          m normalized to 11 bits by << (11-bl)).
    // -------------------------------------------------------------------------
    function [22:0] nunpack;
        input [15:0]     x;
        input            is_bf16;
        reg              s;
        reg  [7:0]       e8;
        reg  [6:0]       m7;
        reg  [4:0]       e5;
        reg  [9:0]       m10;
        reg  [3:0]       bl;
        reg  [10:0]      sig;
        reg signed [8:0] eef;
        reg  [1:0]       knd;
        integer          j;
        begin
            s   = x[15];
            e8  = x[14:7];
            m7  = x[6:0];
            e5  = x[14:10];
            m10 = x[9:0];

            // 1-based leading-one position of the f16 subnormal mantissa —
            // priority scan, last assignment wins on the highest set bit
            // (the FP_AddWide lzc51 idiom). bl == 0 only when m10 == 0,
            // which is the true-zero case and never reaches the shifter's
            // result.
            bl = 4'd0;
            for (j = 0; j <= 9; j = j + 1)
                if (m10[j]) bl = j[3:0] + 4'd1;

            if (is_bf16) begin
                if (e8 == 8'hFF)      knd = (|m7) ? K_NAN : K_INF;
                else if (e8 == 8'h00) knd = K_ZERO;   // + all 254 subnormals
                else                  knd = K_NUM;
                sig = {3'b000, 1'b1, m7};             // 8b, zero-extended to 11
                eef = $signed({1'b0, e8}) - 9'sd127;
            end else begin
                if (e5 == 5'h1F)      knd = (|m10) ? K_NAN : K_INF;
                else if (e5 == 5'h00) knd = (|m10) ? K_NUM : K_ZERO;
                else                  knd = K_NUM;
                if (e5 == 5'h00) begin
                    sig = {1'b0, m10} << (4'd11 - bl);       // f16 subnormal
                    eef = $signed({5'b0, bl}) - 9'sd25;
                end else begin
                    sig = {1'b1, m10};
                    eef = $signed({4'b0, e5}) - 9'sd15;
                end
            end

            if (knd != K_NUM) sig = 11'd0;
            nunpack = {sig, eef, s, knd};
        end
    endfunction

    wire [22:0]       au = nunpack(a_narrow, dtype_bf16);
    wire [22:0]       bu = nunpack(b_narrow, dtype_bf16);

    wire [10:0]       a_sig = au[22:12];
    wire signed [8:0] a_eef = au[11:3];
    wire              a_sgn = au[2];
    wire [1:0]        a_knd = au[1:0];

    wire [10:0]       b_sig = bu[22:12];
    wire signed [8:0] b_eef = bu[11:3];
    wire              b_sgn = bu[2];
    wire [1:0]        b_knd = bu[1:0];

    // ---- fp32 addend unpack, DAZ folded in (exp field 0 -> signed zero) ----
    wire              c_sgn = c_fp32[31];
    wire [7:0]        c_e   = c_fp32[30:23];
    wire [22:0]       c_m   = c_fp32[22:0];
    wire [1:0]        c_knd = (c_e == 8'hFF) ? ((|c_m) ? K_NAN : K_INF)
                            : (c_e == 8'h00) ? K_ZERO
                            :                  K_NUM;

    // ---- exponents in FP_AddWide's convention -------------------------------
    // p_exp = ea_eff + eb_eff + 1 (dtype-agnostic; see ALIGN ALGEBRA).
    // A zero/Inf/NaN multiplicand forces the -1024 zero sentinel so the
    // product operand can never anchor the alignment.
    wire signed [10:0] p_exp_num = {{2{a_eef[8]}}, a_eef}
                                 + {{2{b_eef[8]}}, b_eef}
                                 + 11'sd1;
    wire               p_is_zero = (a_knd != K_NUM) | (b_knd != K_NUM);
    wire signed [10:0] p_exp_w   = p_is_zero ? -11'sd1024 : p_exp_num;

    wire signed [10:0] c_exp_w   = (c_knd == K_NUM)
                                 ? ($signed({3'b000, c_e}) - 11'sd127)
                                 : -11'sd1024;
    // C convention: 24-bit significand (hidden bit) left-aligned into [47:24]
    wire [47:0]        c_sig_w   = (c_knd == K_NUM) ? {1'b1, c_m, 24'd0}
                                                    : 48'd0;

    // ---- IEEE special-case encode (ref_fma's table, in ref_fma's order) -----
    wire sp       = a_sgn ^ b_sgn;
    wire any_nan  = (a_knd == K_NAN) | (b_knd == K_NAN) | (c_knd == K_NAN);
    wire ab_inf   = (a_knd == K_INF) | (b_knd == K_INF);
    wire ab_zero  = (a_knd == K_ZERO) | (b_knd == K_ZERO);
    wire c_inf    = (c_knd == K_INF);
    wire c_zero   = (c_knd == K_ZERO);

    wire qnan_w   = any_nan                       // NaN anywhere
                  | (ab_inf & ab_zero)            // Inf * 0
                  | (ab_inf & c_inf & (c_sgn ^ sp));   // (+-Inf) + (-+Inf)

    wire [1:0] spc_kind_w = qnan_w                 ? SPC_QNAN
                          : (ab_inf | c_inf)       ? SPC_INF
                          : (ab_zero & c_zero)     ? SPC_ZERO
                          :                          SPC_NONE;
    // Inf from the product side outranks an Inf addend (ref_fma order); the
    // zero-zero sign rule is (+0)+(-0) = +0, otherwise the common sign.
    wire       spc_sign_w = ab_inf ? sp
                          : c_inf  ? c_sgn
                          :          ((sp == c_sgn) ? sp : 1'b0);

    // -------------------------------------------------------------------------
    // S1 registers
    // -------------------------------------------------------------------------
    reg        [10:0]  a_sig_s1, b_sig_s1;
    reg signed [10:0]  p_exp_s1, c_exp_s1;
    reg        [47:0]  c_sig_s1;
    reg                p_sgn_s1, c_sgn_s1, bf16_s1;
    reg        [2:0]   spc_s1;

    always @(posedge clk) begin
        a_sig_s1 <= a_sig;
        b_sig_s1 <= b_sig;
        p_exp_s1 <= p_exp_w;
        c_exp_s1 <= c_exp_w;
        c_sig_s1 <= c_sig_w;
        p_sgn_s1 <= sp;
        c_sgn_s1 <= c_sgn;
        bf16_s1  <= dtype_bf16;
        spc_s1   <= {spc_kind_w, spc_sign_w};
    end

    // -------------------------------------------------------------------------
    // S2 — the ONE 11x11 -> 22 significand multiplier (C1).
    // Vendor-neutral DSP hint per the FP_Mul36 / PE_Core.v:1569 precedent:
    // a no-op under yosys (techmap decides), (* use_dsp = "yes" *) under
    // Vivado, syn_multstyle under Radiant.
    // -------------------------------------------------------------------------
    `WT_USE_DSP reg [21:0] prod_s2;

    reg signed [10:0]  p_exp_s2, c_exp_s2;
    reg        [47:0]  c_sig_s2;
    reg                p_sgn_s2, c_sgn_s2, bf16_s2;
    reg        [2:0]   spc_s2;

    always @(posedge clk) begin
        prod_s2  <= a_sig_s1 * b_sig_s1;
        p_exp_s2 <= p_exp_s1;
        c_exp_s2 <= c_exp_s1;
        c_sig_s2 <= c_sig_s1;
        p_sgn_s2 <= p_sgn_s1;
        c_sgn_s2 <= c_sgn_s1;
        bf16_s2  <= bf16_s1;
        spc_s2   <= spc_s1;
    end

    // -------------------------------------------------------------------------
    // Static align into FP_AddWide's [2^46,2^48) window — a 2:1 wire mux.
    //   bf16: prod in [2^14,2^16) -> << 32   (prod[21:16] are structurally 0)
    //   f16 : prod in [2^20,2^22) -> << 26
    // No rounding, no barrel shifter: this is the whole of contract C2.
    // -------------------------------------------------------------------------
    wire [47:0] p_sig_w = bf16_s2 ? {prod_s2[15:0], 32'd0}
                                  : {prod_s2[21:0], 26'd0};

    // -------------------------------------------------------------------------
    // S3/S4/S5 — FP_AddWide, reused verbatim, pack_mode tied to PACK_FINAL
    // (single RNE, flush-after-round FTZ, RNE overflow to +/-Inf). The
    // PACK_WIDE cone and the entire wide output register group have no
    // fanout here and constant-fold away.
    // -------------------------------------------------------------------------
    wire [31:0] aw_final;

    // The wide output group is DELIBERATELY left unconnected: with
    // pack_mode tied to PACK_FINAL those registers never update and have
    // no fanout, so synthesis prunes them along with the PACK_WIDE cone.
    // That absence is also what makes contract C4 structural — there is no
    // narrow (or even wide-internal) pack path out of this lane.
    /* verilator lint_off PINCONNECTEMPTY */
    FP_AddWide u_addwide (
        .clk        (clk),
        .p_sign     (p_sgn_s2),
        .p_exp      (p_exp_s2),
        .p_sig      (p_sig_w),
        .c_sign     (c_sgn_s2),
        .c_exp      (c_exp_s2),
        .c_sig      (c_sig_s2),
        .pack_mode  (PACK_FINAL),
        .final_fp32 (aw_final),
        .wide_sign  (),
        .wide_exp   (),
        .wide_sig   (),
        .wide_zero  ()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // -------------------------------------------------------------------------
    // Special-case code delay line — 3 bits, aligned to FP_AddWide's latency
    // of 3 (operands presented from the S2 registers -> aw_final valid three
    // cycles later, i.e. at the same cycle spc_s5 is valid).
    // -------------------------------------------------------------------------
    reg [2:0] spc_s3, spc_s4, spc_s5;

    always @(posedge clk) begin
        spc_s3 <= spc_s2;
        spc_s4 <= spc_s3;
        spc_s5 <= spc_s4;
    end

    // -------------------------------------------------------------------------
    // S6 — IEEE special-case output mux + result register
    // -------------------------------------------------------------------------
    wire [1:0]  spc_kind_s5 = spc_s5[2:1];
    wire        spc_sign_s5 = spc_s5[0];

    wire [31:0] spc_val_s5 = (spc_kind_s5 == SPC_QNAN) ? 32'h7FC0_0000
                           : (spc_kind_s5 == SPC_INF)  ? {spc_sign_s5,
                                                          8'hFF, 23'd0}
                           :                             {spc_sign_s5, 31'd0};

    always @(posedge clk) begin
        result_fp32 <= (spc_kind_s5 == SPC_NONE) ? aw_final : spc_val_s5;
    end

endmodule

/* verilator lint_on UNUSEDSIGNAL */
