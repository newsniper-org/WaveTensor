// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

`include "attributes.vh"

// =============================================================================
// FP_StepSeq.v — v1.8.0c MU-hosted fp32 step-sequencer unit (spec §23.10,
// synth Gate 3 of §23.10.7) + v1.8.0d OPS_CVT / OPS_ACCEW extension
// (spec §23.10.10, synth Gate C3 of §23.10.10(g)) + v1.8.0e OPS_DEQ
// fused per-lane DEQUANT program (spec §25.2.2, 0e1).
//
// v1.8.0e adds ONE op class (op_sel already 4-bit — no widening; the
// standing rule re-proves ALL existing step programs at the unit TB):
//   OPS_DEQ   0x78 DEQUANT — one int4/int8 lane x the fp32 broadcast
//             scale -> bf16, ROUND-ONCE definition (a). dtype_in selects
//             the source lane field (0x0 int4 = a_in[3:0], 0x1 int8 =
//             a_in[7:0]; upper a_in bits ignored). The exact I2F is
//             FOLDED into the scale multiply: |k| (<= 128, at most 8
//             bits) enters FP_Mul36 UNNORMALIZED against the scale
//             significand m_s during FP_CLASSIFY (the FS_MUL launch
//             trick), so the raw product P = |k| * m_s <= 31 bits is
//             EXACT — nothing rounds before the single RNE to bf16.
//             The pack normalizes P (bl in [24,31] — an 8-way priority
//             encode), jams the dropped bits ROUND-TO-ODD into a 24-bit
//             fp32-format intermediate (golden ref_dequant twin;
//             narrow(RTO24(v)) == RNE_bf16(v) for all v — the
//             micro_i2f_acc margin theorem, 24 >= 8+2), and hands it to
//             the ONE shared narrow authority include/fp_narrow_f32.vh
//             (bit-identity with the CVT/0x7C narrow sites BY
//             CONSTRUCTION; overflow substitutes max-finite-with-sticky
//             so the narrow increment ripples to Inf, never max-finite).
//             Specials resolve in FP_CLASSIFY on the DAZ'd scale: NaN ->
//             bf16 qNaN 0x7FC0; +-Inf -> qNaN if k == 0 else signed
//             bf16 Inf; scale zero (incl. DAZ-flushed denormal) or
//             k == 0 -> SIGNED zero, sign = sign(k) XOR sign(scale).
//             Operand-load DAZ is BYPASSED for the a_in lane field (raw
//             integer bits — the OPS_CVT I2F bypass rule verbatim); the
//             fp32 scale on b_in IS DAZ-flushed (pinned).
//             The PE_Core lane loop (launch-capture, relaunch, fragment
//             pack, loop-completion emit) lives in the 0e1 integration
//             commit; this unit sees one lane per launch.
//
// v1.8.0d adds two op classes (op_sel widened 3 -> 4 bits — every
// (op_sel, fp_step) case tree touched consistently, all six 0c programs
// re-proven at Gate C3):
//   OPS_CVT   0x77 CVT — six scalar conversions as a uniform K_INT-only
//             3-step program (zero multiplier / FP_AddWide passes):
//             f16/bf16 -> f32 widen (exact injection incl. f16
//             subnormals; bf16-subnormal -> signed zero pin; any NaN ->
//             canonical qNaN), f32 -> f16/bf16 narrow through the ONE
//             shared include/fp_narrow_f32.vh function (bit-identity
//             clause with the PE_Core 0x7C fp-dest arm), I2F int4/int8/
//             int64-sext64 (dtype 0x4, covers int32) with the PINNED
//             two-pass pass-1-RTO / pass-2-RNE normalize, and F2I
//             RNE-then-saturate (NaN -> 0, +/-Inf -> rails).
//             MANDATORY RTL RULE (§23.10.10(b), confirmed-bug fix):
//             operand-load DAZ is BYPASSED for OPS_CVT sources that are
//             not fp32-format (all WIDEN directions and all I2F) — an
//             op-class-conditional term in the capture mux; the fp32
//             sources of NARROW/F2I ARE DAZ-flushed (pinned identically
//             at the 0x7C site).
//   OPS_ACCEW 0x73 ACC_ELEMWISE — fused single-rounding fp32
//             a*B[63:32] + B[31:0] riding the FS_FMA step program
//             verbatim (a = a_in, B_hi = b_in, B_lo = c_in); bit-exact
//             to golden ref_fma == micro_fscalar(FS_FMA).
//
// The self-contained fp32 scalar unit: one shared FP_Mul36 (raw 36x36
// integer multiplier, latency exactly 2) and one shared FP_AddWide (wide
// FMA-capable add/normalize/pack datapath, latency exactly 3) are walked
// through per-op step programs by a small FSM. That operator sharing IS
// the design (spec §23.10.1). Bit-exactness authority is
// scripts/golden_fp32.py: the FS_ADD/SUB/MUL/FMA paths realize the
// REFERENCE-layer semantics through the exact-then-round-once FP_AddWide
// datapath (proven bit-identical by the Gate 2 TB), and the FS_DIV /
// FRSQRT32 / FEXP2_32 step programs mirror golden micro_div / micro_rsqrt
// / micro_exp2 STEP FOR STEP: same fixed-point widths (Q2.28 rsqrt,
// Q2.30 div and exp2), same round-to-odd placement after each multiplier
// pass, same operand order (h*y FIRST in the rsqrt NR body — §23.10.9
// pins that a step-order deviation silently eats the FRSQRT margin), same
// seed ROM indexing ({exp[0], mant[22:16]} rsqrt / mant[22:15] div), same
// Horner coefficient order with c0 == 1.0, same integer bypass and
// boundary fast paths for exp2, same DAZ-at-load / internal-steps-exempt
// / FTZ-at-final-pack placement, canonical qNaN 0x7FC00000 everywhere.
//
// -----------------------------------------------------------------------------
// INTERFACE CONTRACT
// -----------------------------------------------------------------------------
//   start      1-cycle pulse, asserted only while busy == 0 (PE_Core's
//              launch ladder guarantees this). Operands/opcode/sub-op are
//              sampled on the start edge.
//   busy       combinational start | (state != IDLE): rises WITH start,
//              holds through the done cycle.
//   done       1-cycle pulse; result is valid exactly during that cycle.
//              Back-to-back operation: busy is 0 in the cycle after done
//              and a new start may be asserted immediately in that cycle.
//   opcode_in  0x74 FSCALAR / 0x75 FRSQRT32 / 0x76 FEXP2_32 /
//              0x73 ACC_ELEMWISE / 0x77 CVT (v1.8.0d) / 0x78 DEQUANT
//              (v1.8.0e, one lane per launch).
//   subop_in   FSCALAR or CVT sub-op (imm16[7:4], generated single-source
//              tables in include/generated/isa_subop_codes.vh); ignored
//              by the unary ops and DEQUANT. Absent imm16 decodes as 0
//              upstream = FS_ADD / CVT WIDEN_TO_F32 defaults.
//   dtype_in   CVT dtype (eff_precision[3:0]): 0x0 int4 / 0x1 int8 /
//              0x2 f16 / 0x3 bf16 / 0x4 accumulator-format integer
//              endpoint (int32/int64, direction from the sub-op).
//              DEQUANT SOURCE dtype: 0x0 int4 (a_in[3:0]) / 0x1 int8
//              (a_in[7:0]) — dest pinned bf16-ONLY in 0e. Ignored by
//              every other op class.
//
//   DON'T-CARE INPUTS: PE_Core's decode guards ensure an unknown opcode,
//   an FSCALAR sub-op > 0x4, a CVT sub-op > 0x1 or a CVT dtype > 0x4
//   (reserved-field rungs -> lower_required) is never presented. If presented anyway,
//   this implementation deterministically returns the canonical qNaN
//   after 2 cycles (chosen to keep simulation X-free); that behavior is
//   NOT contractual and may change.
//
//   NO RESET: like FP_Mul36/FP_AddWide this block is reset-free; the
//   control state powers up via FPGA initialization (declaration
//   initializers below — same reset-light philosophy as the PE_Core
//   FSMs, whose reset lives in the parent's clause). Tag handling stays
//   in PE_Core (fp_tag_held); a parent reset mid-op simply lets the
//   in-flight op self-complete within its cycle bound, and the re-armed
//   parent ignores the stray done pulse (the launch ladder consults busy).
//
// -----------------------------------------------------------------------------
// FSM / STEP TIMING MODEL
// -----------------------------------------------------------------------------
// States: FP_IDLE -> FP_CLASSIFY (1 cycle) -> FP_EXEC (step program) ->
// FP_FINISH (1 cycle, done) -> FP_IDLE. IEEE specials (NaN/Inf/zero
// operands and the exp2 comparator fast paths) resolve entirely in
// FP_CLASSIFY and skip FP_EXEC, so FP_AddWide never receives special
// operands (its pinned precondition; FP_Mul36 is a pure integer
// multiplier with no operand-value precondition — whatever flows through
// it outside an executed step is never consumed).
//
// Step kinds and durations (fp_wait down-counter, loaded with kind):
//   K_INT (1 cy)  pure-integer step: round-to-odd jam, fixed-point
//                 subtract-from-constant folded into the operand mux,
//                 exponent bookkeeping, RNE packs. Never uses FP_AddWide.
//   K_MUL (2 cy)  one FP_Mul36 pass (latency 2).
//   K_ADD (3 cy)  one FP_AddWide pass (latency 3, Gate-2 fallback).
//
// Data hand-off invariant: a step's operator inputs are held constant for
// all its cycles; the producing operator output register is therefore
// valid during the FIRST cycle of the following step and is (a) consumed
// live through the fp_first operand-mux leg and (b) captured into a temp
// register at the edge ending that first cycle — later cycles read the
// temp, which carries the identical value. K_INT steps read the live
// output and perform their whole action at their single edge.
//
// Per-op step programs and worst-case start->done cycle counts (§23.10.6
// normative maxima in parentheses; specials finish in 2 cycles):
//   FS_ADD/SUB   classify, ADD(final)                     =  5  (<= 6)
//   FS_MUL/FMA   classify*, INT(mul tail), ADD(final)     =  6  (<= 6/10)
//                *the classify cycle doubles as the first multiplier
//                 cycle: the mul operand mux presents the significand
//                 pair during FP_CLASSIFY (required to meet the FS_MUL
//                 bound of 6 with the latency-3 adder)
//   FS_DIV       classify, 7xMUL, INT, MUL, INT, MUL, ADD = 25  (<= 32)
//   FRSQRT32     classify, 9xMUL, INT(pack)               = 21  (<= 34)
//   FEXP2_32     classify, INT(split), 6xMUL, INT(pack)   = 16  (<= 30)
//                integer bypass: classify, INT            =  3
//   CVT (all)    classify, 3xINT                          =  5  (<= 8;
//                int64 I2F <= 10 — §23.10.10(e); the uniform 3-step
//                program exists FOR the int64 two-pass, the simple
//                conversions just compute combinationally at the pack)
//   ACC_ELEMWISE = FS_FMA shape                           =  6  (<= 10)
//   DEQUANT      classify*, INT(mul tail), INT(normalize
//                + RTO-24 capture), INT(narrow pack)      =  5  (<= 8;
//                the §25.4 L=8 ceiling — the spec's L=6-7 ESTIMATE
//                graduates to the measured count at the unit TB;
//                specials finish in 2)
//                *the classify cycle doubles as the first multiplier
//                 cycle — the FS_MUL launch trick verbatim
//
// -----------------------------------------------------------------------------
// FS_DIV MARKSTEIN PACK — analyzed FP_AddWide usage (documented deviation
// in REPRESENTATION, proven bit-identical in RESULT)
// -----------------------------------------------------------------------------
// golden micro_div forms T = (q24 << 53) + resid*r exactly and rounds
// once. Here the correction q = RNE(q0 + resid*r) rides the shared
// FP_AddWide FINAL pass: C = q0 as a left-aligned 24-bit addend, P =
// resid*r. The raw product |resid|*r spans up to 2^55 and cannot fit the
// 48-bit P significand, so P carries rto(|resid|*r, 7) with the exponent
// raised by 7. Round-to-odd jamming below bit 7 preserves every bit at
// and above bit 7 and ORs the rest into bit 7; the final RNE decision
// point sits ~30 bits higher (|q0| >= 2^qe vs |resid*r| <= 2^(qe-21)),
// so guard/round bits are untouched and stickiness is preserved exactly
// => RNE(q0 + P_encoded) == RNE(q0 + resid*r) bit-for-bit. The exponent
// offset ea-eb is folded into BOTH operand exponents, so the fp32
// exponent is assembled (and overflow/FTZ decided) exactly once, at this
// pack (golden pack placement). Two analyzed extensions of the pinned
// FP_AddWide preconditions, both safe here:
//   * P may be UN-normalized or zero: C (>= 2^47 left-aligned) always
//     anchors (c_exp - p_exp == 22 by construction, and a zero P carries
//     that same strictly-lower exponent), and with shamt == 22 >= 3 the
//     50-bit-window equivalence argument of the FP_AddWide header holds
//     with margin (aligned |P| < 2^28 window units vs anchor >= 2^49).
//   * |resid| < 2^24 is guaranteed by the Markstein premise (q0 within
//     1 ulp of ma/mb ==> |resid| = mb * |ma/mb - q0| * 2^(23-qe) <= mb).
// This mapping was validated bit-exactly against golden micro_div on
// 245,000 vectors (random, midpoint-adjacent quotients, x/x carry cases,
// exponent extremes) before RTL entry; the TB re-proves it in RTL.
//
// FEXP2 note: the exact n+f split is computed as x30 = floor(x * 2^30)
// via a clamped arithmetic shift (clamp >= 31 only affects |x| < 2^-56
// where the floor is 0 or -1 anyway), n = x30 >> 30, f = x30 mod 2^30 —
// identical to golden micro_exp2 by the nested-floor identity; the final
// Horner value P(f) lies in [1, 2) (the shipped coefficients sum to
// 2^31 - 5), so the normalize is a 1-bit case exactly as in the golden
// twin vexp2 model. Validated on 376,000 vectors before RTL entry.
//
// ROMs: the two 256x9 seed ROMs and the 7 Q1.30 Horner coefficients come
// verbatim from the shipped include/generated sidecars (localparam bit
// vectors sliced at CONSTANT offsets into a wire array by a generate
// loop; the read indexes that constant array => pure distributed LUT ROM,
// no memory inference, 0 EBR by construction — see the seed-ROM block
// comment for why a dynamic part-select is NOT an equivalent shape).
//
// yosys note (§23.8 precedent): no function-call result is ever indexed;
// multi-bit intermediates are hoisted to wires and the WIRES are sliced.
// =============================================================================

/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNUSEDPARAM */
// PROCASSINIT: the control state deliberately combines power-on
// initializers with procedural writes (reset-free block, see header)
/* verilator lint_off PROCASSINIT */

module FP_StepSeq (
    input             clk,
    input             start,
    input      [7:0]  opcode_in,
    input      [3:0]  subop_in,
    input      [3:0]  dtype_in,
    input      [31:0] a_in,
    input      [31:0] b_in,
    input      [31:0] c_in,
    output            busy,
    output            done,
    output     [31:0] result
);

    `include "generated/isa_subop_codes.vh"
    `include "generated/fp_frsqrt_seed_rom.vh"
    `include "generated/fp_fdiv_seed_rom.vh"
    `include "generated/fp_fexp2_coeffs.vh"
    `include "fp_narrow_f32.vh"

    // ---- opcodes (spec §23.10 block 0x70) ----
    localparam [7:0] OPC_ACCEW   = 8'h73;    // v1.8.0d §23.10.10(c)
    localparam [7:0] OPC_FSCALAR = 8'h74;
    localparam [7:0] OPC_FRSQRT  = 8'h75;
    localparam [7:0] OPC_FEXP2   = 8'h76;
    localparam [7:0] OPC_CVT     = 8'h77;    // v1.8.0d §23.10.10(b)
    localparam [7:0] OPC_DEQUANT = 8'h78;    // v1.8.0e §25.2.2 (0e1)

    // ---- FSM ----
    localparam [1:0] FP_IDLE     = 2'd0;
    localparam [1:0] FP_CLASSIFY = 2'd1;
    localparam [1:0] FP_EXEC     = 2'd2;
    localparam [1:0] FP_FINISH   = 2'd3;

    // step kind == cycle count - 1 == fp_wait load value
    localparam [1:0] K_INT = 2'd0;
    localparam [1:0] K_MUL = 2'd1;
    localparam [1:0] K_ADD = 2'd2;

    // internal op selector (FS_MUL/FS_FMA share one step table).
    // v1.8.0d: widened 3 -> 4 bits for the two new classes (§23.10.10;
    // Gate C3 re-proves all six 0c programs against this widening).
    localparam [3:0] OPS_FSADD = 4'd0;   // FS_ADD / FS_SUB (B sign-flipped)
    localparam [3:0] OPS_FSMUL = 4'd1;
    localparam [3:0] OPS_FSFMA = 4'd2;
    localparam [3:0] OPS_FSDIV = 4'd3;
    localparam [3:0] OPS_RSQRT = 4'd4;
    localparam [3:0] OPS_FEXP2 = 4'd5;
    localparam [3:0] OPS_BAD   = 4'd6;   // don't-care inputs (see header)
    localparam [3:0] OPS_CVT   = 4'd7;   // v1.8.0d 0x77 (3x K_INT program)
    localparam [3:0] OPS_ACCEW = 4'd8;   // v1.8.0d 0x73 (FS_FMA shape)
    localparam [3:0] OPS_DEQ   = 4'd9;   // v1.8.0e 0x78 (3x K_INT, fused
                                         // I2F-x-scale via FP_Mul36)

    localparam [31:0] QNAN = 32'h7FC0_0000;
    localparam [31:0] PINF = 32'h7F80_0000;
    localparam [31:0] FONE = 32'h3F80_0000;

    // -------------------------------------------------------------------------
    // control / data registers (control state carries power-on initializers
    // — reset-free block, see header)
    // -------------------------------------------------------------------------
    reg [1:0]  fp_state = FP_IDLE;
    reg [5:0]  fp_step  = 6'd0;
    reg [1:0]  fp_wait  = 2'd0;
    reg        fp_first = 1'b0;

    reg [31:0] a_q, b_q, c_q;            // operands, DAZ applied at load
                                         // (BYPASSED for CVT widen/I2F —
                                         // op-class-conditional, §23.10.10(b))
    reg [3:0]  op_sel;

    reg        cvt_nar_q;                // CVT sub-op: 0 widen / 1 narrow
    reg [2:0]  cvt_dt_q;                 // CVT dtype (low 3 bits, 0x0-0x4)
    reg [63:0] i64_q;                    // CVT I2F |sext64 source| (step 0)

    reg [29:0] h_q;                      // rsqrt h = x'/2, Q2.28 (exact)
    reg [31:0] y_r;                      // rsqrt y / div r / exp2 f (Q2.30)
    reg [35:0] t_u;                      // step temp (rto captures, |resid|)
    reg [47:0] t_prod;                   // 48-bit product / jam capture
    reg [23:0] q24_q;                    // div q0 significand
    reg signed [1:0] qe_q;               // div q0 exponent (-1/0/+1)
    reg        sres_q;                   // div Markstein residual sign
    reg signed [9:0] exp_r;              // div ea-eb / rsqrt -k
    reg signed [8:0] n_q;                // exp2 integer part n
    reg        useaw_q;                  // FINISH source: FP_AddWide vs res_reg
    reg        orsign_q;                 // FS_DIV sign OR-mask into bit 31
    reg [31:0] res_reg;                  // specials + INT-packed results

    // -------------------------------------------------------------------------
    // operand field / classify wires (post-DAZ registers)
    // -------------------------------------------------------------------------
    wire [7:0]  ea_f = a_q[30:23];
    wire [7:0]  eb_f = b_q[30:23];
    wire [7:0]  ec_f = c_q[30:23];
    wire        sa = a_q[31], sb = b_q[31], sc = c_q[31];

    wire a_nan  = (ea_f == 8'hFF) &&  (|a_q[22:0]);
    wire a_inf  = (ea_f == 8'hFF) && !(|a_q[22:0]);
    wire a_zero = (ea_f == 8'h00);       // true zero == DAZ-flushed operand
    wire b_nan  = (eb_f == 8'hFF) &&  (|b_q[22:0]);
    wire b_inf  = (eb_f == 8'hFF) && !(|b_q[22:0]);
    wire b_zero = (eb_f == 8'h00);
    wire c_nan  = (ec_f == 8'hFF) &&  (|c_q[22:0]);
    wire c_inf  = (ec_f == 8'hFF) && !(|c_q[22:0]);
    wire c_zero = (ec_f == 8'h00);

    wire [23:0] ma = {1'b1, a_q[22:0]};  // significands with hidden bit
    wire [23:0] mb = {1'b1, b_q[22:0]};
    wire [23:0] mc = {1'b1, c_q[22:0]};

    wire signed [9:0] ex_a = $signed({2'b00, ea_f}) - 10'sd127;
    wire signed [9:0] ex_b = $signed({2'b00, eb_f}) - 10'sd127;
    wire signed [9:0] ex_c = $signed({2'b00, ec_f}) - 10'sd127;

    // -------------------------------------------------------------------------
    // seed ROM reads (distributed LUT ROM). The generate loop slices each
    // 9-bit entry out of the localparam bit vector at a CONSTANT offset and
    // the read indexes the resulting constant array — yosys turns that into
    // a plain 256:1 constant mux tree (~260 LUT4 per ROM). A dynamic part-
    // select of the 2304-bit localparam is NOT equivalent in synthesis: it
    // infers a 2304-bit barrel shifter (~5x the LUTs, measured — the Gate 3
    // LUT4 criterion is why this shape is load-bearing).
    // -------------------------------------------------------------------------
    wire [7:0] rsq_idx = {a_q[23], a_q[22:16]};    // {exp[0], mant[22:16]}
    wire [7:0] div_idx = b_q[22:15];               // mant[22:15] of B

    wire [8:0] rsq_rom_q [0:255];
    wire [8:0] div_rom_q [0:255];
    genvar gi;
    generate
        for (gi = 0; gi < 256; gi = gi + 1) begin : g_seed_rom
            assign rsq_rom_q[gi] = FP_FRSQRT_SEED_ROM[9*gi +: 9];
            assign div_rom_q[gi] = FP_FDIV_SEED_ROM[9*gi +: 9];
        end
    endgenerate

    wire [8:0] rsq_seed = rsq_rom_q[rsq_idx];
    wire [8:0] div_seed = div_rom_q[div_idx];

    // -------------------------------------------------------------------------
    // step-program table: {last, kind}. INT actions and operand muxes case
    // on (op_sel, fp_step) below.
    // -------------------------------------------------------------------------
    //   OPS_FSADD : 0 ADD(last)
    //   OPS_FSMUL/FSFMA : 0 INT (mul tail — mul launched during CLASSIFY),
    //                     1 ADD(last)
    //   OPS_FSDIV : 0..5 MUL (3x Newton: mb*r then r*(2^31-t)),
    //               6 MUL (ma*r), 7 INT (q24/qe RNE), 8 MUL (q24*mb),
    //               9 INT (residual), 10 MUL (|resid|*r), 11 ADD(last)
    //   OPS_RSQRT : 0..8 MUL (3x NR: h*y, t1*y, y*(1.5-t2) — pinned order),
    //               9 INT(pack, last)
    //   OPS_FEXP2 : 0 INT (n+f split / integer bypass), 1..6 MUL (Horner),
    //               7 INT(pack, last)
    //   OPS_CVT   : 0 INT (I2F |sext64| capture), 1 INT (I2F LZC/normalize
    //               + pass-1 RTO jam | F2I shift/round pre-stage into y_r),
    //               2 INT (pack, last — pass-2 RNE for I2F, F2I saturate/
    //               negate, pure comb select for widen/narrow). Uniform
    //               3-step shape for every direction (§23.10.10(e) bounds
    //               have headroom; a per-dtype 1-step variant would buy 2
    //               cycles nobody needs, cost a dtype leg in this table,
    //               and put the measured-28.4ns F2I cone back in 1 cycle).
    //   OPS_ACCEW : rides the FS_FMA rows verbatim (0 INT mul tail, 1 ADD)
    //   OPS_DEQ   : 0 INT (mul tail — |k| x m_s launched during CLASSIFY,
    //               the FS_MUL trick), 1 INT (normalize + RTO-24 capture
    //               into i64_q[31:0] as an fp32-format intermediate —
    //               i64_q is the single-writer CVT-I2F temp, free here;
    //               overflow substitutes signed max-finite-with-sticky),
    //               2 INT (pack, last — the ONE shared fp_narrow_f32
    //               instance, input-muxed). Same uniform 3x K_INT shape
    //               as OPS_CVT.
    reg [2:0] info_cur, info_nxt, info_ent;   // {last, kind}

    function [2:0] f_step_info;
        input [3:0] sel;
        input [5:0] st;
        begin
            f_step_info = {1'b1, K_INT};      // default: terminate
            case (sel)
                OPS_FSADD: f_step_info = {1'b1, K_ADD};
                OPS_FSMUL,
                OPS_FSFMA,
                OPS_ACCEW: f_step_info = (st == 6'd0) ? {1'b0, K_INT}
                                                      : {1'b1, K_ADD};
                OPS_FSDIV: case (st)
                    6'd7, 6'd9: f_step_info = {1'b0, K_INT};
                    6'd11:      f_step_info = {1'b1, K_ADD};
                    default:    f_step_info = {1'b0, K_MUL};
                endcase
                OPS_RSQRT: f_step_info = (st == 6'd9) ? {1'b1, K_INT}
                                                      : {1'b0, K_MUL};
                OPS_FEXP2: case (st)
                    6'd0:    f_step_info = {1'b0, K_INT};
                    6'd7:    f_step_info = {1'b1, K_INT};
                    default: f_step_info = {1'b0, K_MUL};
                endcase
                OPS_CVT,
                OPS_DEQ: f_step_info = (st == 6'd2) ? {1'b1, K_INT}
                                                    : {1'b0, K_INT};
                default: ;
            endcase
        end
    endfunction

    wire [5:0] step_p1 = fp_step + 6'd1;
    always @* begin
        info_cur = f_step_info(op_sel, fp_step);
        info_nxt = f_step_info(op_sel, step_p1);
        info_ent = f_step_info(op_sel, 6'd0);
    end
    wire       cur_last = info_cur[2];
    wire [1:0] nxt_kind = info_nxt[1:0];
    wire [1:0] ent_kind = info_ent[1:0];

    // -------------------------------------------------------------------------
    // shared multiplier + round-to-odd taps
    // -------------------------------------------------------------------------
    reg  [35:0] mul_a, mul_b;
    wire [71:0] p;

    FP_Mul36 u_mul (
        .clk (clk),
        .a   (mul_a),
        .b   (mul_b),
        .p   (p)
    );

    // Round-to-odd jams of the previous multiplier pass (upper p bits are
    // provably zero at each use site — operand bounds in the step table):
    //   rto23: div t = rto(mb*r, 23),      p < 2^55  (mb < 2^24, r < 2^31)
    //   rto30: div r' / exp2 acc, F = 30,  p < 2^62
    //   rto28: rsqrt Q2.28 steps,          p < 2^58
    //   rto7 : div Markstein P jam,        p < 2^55  (|resid| < 2^24)
    wire [32:0] rto23_w = p[55:23] | {32'b0, |p[22:0]};
    wire [31:0] rto30_w = p[61:30] | {31'b0, |p[29:0]};
    wire [29:0] rto28_w = p[57:28] | {29'b0, |p[27:0]};
    wire [47:0] rto7_w  = p[54:7]  | {47'b0, |p[6:0]};

    // ---- div INT step 7: q24/qe = RNE24 of q0 = ma*r (value in (0.5, 2)) ----
    wire        q_ge1  = |p[71:53];                    // q0 >= 1
    wire [24:0] q_pre  = q_ge1 ? p[54:30] : p[53:29];
    wire        q_grd  = q_ge1 ? p[29] : p[28];
    wire        q_stk  = q_ge1 ? (|p[28:0]) : (|p[27:0]);
    wire        q_up   = q_grd & (q_stk | q_pre[0]);
    wire [24:0] q_rnd  = q_pre + {24'b0, q_up};

    // ---- div INT step 9: resid = ma*2^(23-qe) - q24*mb (exact, signed) ----
    reg [49:0] ma_shift;
    always @* case (qe_q)
        -2'sd1:  ma_shift = {2'b00, ma, 24'b0};        // << 24
        2'sd1:   ma_shift = {4'b0000, ma, 22'b0};      // << 22
        default: ma_shift = {3'b000, ma, 23'b0};       // << 23
    endcase
    wire signed [50:0] resid_w  = $signed({1'b0, ma_shift})
                                - $signed({3'b000, p[47:0]});
    wire               resid_neg = resid_w[50];
    wire        [50:0] resid_mag = resid_neg ? (~resid_w + 51'd1)
                                             : resid_w;

    // ---- rsqrt INT step 9: normalize + single RNE pack (always normal) ----
    wire        rs_ge1  = |rto28_w[29:28];             // y3 >= 1.0 (Q2.28)
    wire [30:0] rs_frac = rs_ge1 ? {1'b0, rto28_w} : {rto28_w, 1'b0};
    wire [24:0] rs_pre  = rs_frac[29:5];
    wire        rs_up   = rs_frac[4] & ((|rs_frac[3:0]) | rs_frac[5]);
    wire [24:0] rs_m    = rs_pre + {24'b0, rs_up};
    wire signed [9:0] rs_e = exp_r - {9'b0, ~rs_ge1} + {9'b0, rs_m[24]};
    wire [7:0]  rs_bias = rs_e[7:0] + 8'd127;
    // rs_m[24] set => low 23 bits already zero (FP_AddWide rcarry trick)
    wire [31:0] rsq_pack_res = {1'b0, rs_bias, rs_m[22:0]};

    // ---- exp2 INT step 0: exact split x30 = floor(x*2^30), n, f ----
    wire signed [24:0] e2_sx  = sa ? -$signed({1'b0, ma})
                                   : $signed({1'b0, ma});
    wire signed [38:0] e2_sx39 = {{14{e2_sx[24]}}, e2_sx};
    wire signed [9:0]  e2_tsh = $signed({2'b00, ea_f}) - 10'sd120;
    wire signed [9:0]  e2_negt = -e2_tsh;
    wire        [4:0]  e2_shr = (e2_negt >= 10'sd31) ? 5'd31 : e2_negt[4:0];
    // in-domain |x| < 150 => e2_tsh <= 14; clamp-to-31 right shifts only
    // fire for |x| < 2^-56 where floor(x*2^30) is 0 or -1 (golden twin)
    wire signed [38:0] e2_x30 = (e2_tsh >= 10'sd0)
                                ? (e2_sx39 <<< e2_tsh[3:0])
                                : (e2_sx39 >>> e2_shr);
    wire signed [8:0]  e2_n  = e2_x30[38:30];
    wire        [29:0] e2_ff = e2_x30[29:0];
    wire [7:0]  e2_nbias = e2_n[7:0] + 8'd127;
    wire [31:0] e2_bypass_res = (e2_n < -9'sd126) ? 32'h0
                                : {1'b0, e2_nbias, 23'b0};

    // ---- exp2 Horner coefficient schedule (C6 first, C0 at the pack) ----
    reg [30:0] e2_cnext;
    always @* case (fp_step)
        6'd2:    e2_cnext = FP_FEXP2_C5;
        6'd3:    e2_cnext = FP_FEXP2_C4;
        6'd4:    e2_cnext = FP_FEXP2_C3;
        6'd5:    e2_cnext = FP_FEXP2_C2;
        6'd6:    e2_cnext = FP_FEXP2_C1;
        default: e2_cnext = FP_FEXP2_C0;               // step 7 (pack)
    endcase
    wire [32:0] e2_acc = {1'b0, rto30_w} + {2'b00, e2_cnext};

    // ---- exp2 INT step 7: P(f) in [1,2) => 1-bit normalize, RNE, pack ----
    wire        e2_bl31 = e2_acc[31];
    wire [24:0] e2_pre  = e2_bl31 ? {1'b0, e2_acc[31:8]}
                                  : {1'b0, e2_acc[30:7]};
    wire        e2_grd  = e2_bl31 ? e2_acc[7] : e2_acc[6];
    wire        e2_stk  = e2_bl31 ? (|e2_acc[6:0]) : (|e2_acc[5:0]);
    wire        e2_up   = e2_grd & (e2_stk | e2_pre[0]);
    wire [24:0] e2_m    = e2_pre + {24'b0, e2_up};
    wire signed [9:0] e2_ev = {n_q[8], n_q} + {9'b0, e2_bl31}
                            + {9'b0, e2_m[24]};
    wire [7:0]  e2_ebias = e2_ev[7:0] + 8'd127;
    wire [31:0] e2_pack_res = (e2_ev > 10'sd127)  ? PINF
                            : (e2_ev < -10'sd126) ? 32'h0
                            : {1'b0, e2_ebias, e2_m[22:0]};

    // -------------------------------------------------------------------------
    // v1.8.0d OPS_CVT datapath (§23.10.10(b)) — K_INT-only, no multiplier or
    // FP_AddWide pass. Sources arrive RAW for WIDEN/I2F (op-class-conditional
    // DAZ bypass at the capture mux — the confirmed I2F(5)-flushes-to-zero
    // bug fix); the fp32 sources of NARROW/F2I are DAZ-flushed at capture
    // (pinned identically at the PE_Core 0x7C site — bit-identity clause).
    // Golden twins: ref_widen_f16 / ref_widen_bf16 / ref_narrow_f32 /
    // micro_i2f_acc / ref_f2i (scripts/golden_fp32.py).
    // -------------------------------------------------------------------------

    // ---- WIDEN dtype 0x2: f16 -> f32 exact injection (subnormals honored:
    //      value = m * 2^-24, normalized via a 10-bit priority encode) ----
    wire        wf16_s = a_q[15];
    wire [4:0]  wf16_e = a_q[14:10];
    wire [9:0]  wf16_m = a_q[9:0];
    reg  [3:0]  wf16_bl;                     // bit_length(m), m != 0 path only
    always @* casez (wf16_m)
        10'b1?????????: wf16_bl = 4'd10;
        10'b01????????: wf16_bl = 4'd9;
        10'b001???????: wf16_bl = 4'd8;
        10'b0001??????: wf16_bl = 4'd7;
        10'b00001?????: wf16_bl = 4'd6;
        10'b000001????: wf16_bl = 4'd5;
        10'b0000001???: wf16_bl = 4'd4;
        10'b00000001??: wf16_bl = 4'd3;
        10'b000000001?: wf16_bl = 4'd2;
        default:        wf16_bl = 4'd1;
    endcase
    // m << (24 - bl) with the leading 1 landing at bit 23; fp32 exponent
    // field = bl + 102 (= (bl - 25) + 127, value m * 2^-24 in binade bl-25)
    wire [23:0] wf16_sub = {wf16_m, 14'b0} << (4'd10 - wf16_bl);
    reg  [31:0] wf16_res;
    always @* begin
        if (wf16_e == 5'h1F)
            wf16_res = (|wf16_m) ? QNAN : {wf16_s, 8'hFF, 23'b0};
        else if (wf16_e == 5'h00)
            wf16_res = (|wf16_m)
                     ? {wf16_s, ({4'b0, wf16_bl} + 8'd102), wf16_sub[22:0]}
                     : {wf16_s, 31'b0};
        else
            wf16_res = {wf16_s, ({3'b0, wf16_e} + 8'd112), wf16_m, 13'b0};
    end

    // ---- WIDEN dtype 0x3: bf16 -> f32 exact splice; subnormal input ->
    //      signed zero (§23.10.10(f) pin 6); any NaN -> canonical qNaN ----
    reg [31:0] wbf_res;
    always @* begin
        if (a_q[14:7] == 8'hFF)
            wbf_res = (|a_q[6:0]) ? QNAN : {a_q[15], 8'hFF, 23'b0};
        else if (a_q[14:7] == 8'h00)
            wbf_res = {a_q[15], 31'b0};      // true zero + the 254 subnormals
        else
            wbf_res = {a_q[15:0], 16'b0};
    end

    // ---- I2F step 0: signed source -> sign + |magnitude|. int4/int8 ride
    //      the same 64-bit two-pass path (both passes exact for them, so
    //      bit-identical to golden ref_i2f); dtype 0x4 ingress is PINNED
    //      payload[63:32] -> c_in, payload[31:0] -> a_in (FSCALAR split) ----
    reg [63:0] i2f_src;
    always @* case (cvt_dt_q)
        3'd0:    i2f_src = {{60{a_q[3]}}, a_q[3:0]};
        3'd1:    i2f_src = {{56{a_q[7]}}, a_q[7:0]};
        default: i2f_src = {c_q, a_q};
    endcase
    wire        i2f_sgn = i2f_src[63];
    wire [63:0] i2f_mag = i2f_sgn ? (~i2f_src + 64'd1) : i2f_src;

    // ---- I2F step 1: LZC64 + normalize (log-stage shifter — §23.8 tree
    //      shapes, no linear mux chain), then pass-1 RTO into the 32-bit
    //      intermediate: jam = OR of the dropped low half (sticky-
    //      preserving; golden micro_i2f_acc, I2F_PASS1_BITS = 32) ----
    wire        i2f_z32 = ~|i64_q[63:32];
    wire [63:0] i2f_n0  = i2f_z32 ? {i64_q[31:0], 32'b0} : i64_q;
    wire        i2f_z16 = ~|i2f_n0[63:48];
    wire [63:0] i2f_n1  = i2f_z16 ? {i2f_n0[47:0], 16'b0} : i2f_n0;
    wire        i2f_z8  = ~|i2f_n1[63:56];
    wire [63:0] i2f_n2  = i2f_z8 ? {i2f_n1[55:0], 8'b0} : i2f_n1;
    wire        i2f_z4  = ~|i2f_n2[63:60];
    wire [63:0] i2f_n3  = i2f_z4 ? {i2f_n2[59:0], 4'b0} : i2f_n2;
    wire        i2f_z2  = ~|i2f_n3[63:62];
    wire [63:0] i2f_n4  = i2f_z2 ? {i2f_n3[61:0], 2'b0} : i2f_n3;
    wire        i2f_z1  = ~i2f_n4[63];
    wire [63:0] i2f_n5  = i2f_z1 ? {i2f_n4[62:0], 1'b0} : i2f_n4;
    wire [5:0]  i2f_lzc = {i2f_z32, i2f_z16, i2f_z8, i2f_z4, i2f_z2, i2f_z1};
    wire [31:0] i2f_inter = i2f_n5[63:32] | {31'b0, |i2f_n5[31:0]};
    wire signed [8:0] i2f_exp = 9'sd63 - $signed({3'b0, i2f_lzc});

    // ---- I2F step 2: pass-2 final RNE (32 -> 24 bits, disjoint R/S; the
    //      +1 carry only fires off an all-ones field, so the carried
    //      mantissa bits are already zero — rsqrt rs_m[24] precedent).
    //      y_r[31] == 0 iff the source was 0 (normalize pins the MSB). ----
    wire [24:0] i2f_m25  = {1'b0, y_r[31:8]}
                         + {24'b0, (y_r[7] & ((|y_r[6:0]) | y_r[8]))};
    wire [7:0]  i2f_ebia = n_q[7:0] + 8'd127 + {7'b0, i2f_m25[24]};
    wire [31:0] i2f_pack = y_r[31] ? {sres_q, i2f_ebia, i2f_m25[22:0]}
                                   : 32'h0;

    // ---- F2I (NARROW sub-op, dtype 0x0/0x1/0x4): RNE then saturate
    //      (§23.10.10(f) pin 9): NaN -> 0 (deterministic DATA, CUDA
    //      cvt.sat precedent), +/-Inf -> rails; a_q is post-DAZ.
    //      TWO-staged across the uniform program (single-cycle the
    //      shift+round+saturate+negate cone measured 28.4 ns at the C3
    //      seed sweep — re-staged, not redesigned; cycle count and
    //      §23.10.10(e) bounds unchanged): STEP 1 registers {big, RNE
    //      magnitude} into y_r — free on the NARROW sub-op, I2F owns
    //      y_r only on WIDEN — and STEP 2 saturates/negates/selects. ----
    wire signed [9:0] f2i_shl = ex_a - 10'sd23;        // 23 <= e <= 30 leg
    wire [30:0] f2i_ls = {7'b0, ma} << f2i_shl[2:0];
    wire signed [9:0] f2i_shr_raw = 10'sd23 - ex_a;    // e < 23 leg, >= 1
    wire [4:0]  f2i_shr = (f2i_shr_raw >= 10'sd26) ? 5'd26 : f2i_shr_raw[4:0];
    wire [49:0] f2i_fx  = {ma, 26'b0} >> f2i_shr;      // Q24.26 fixed point
    wire [24:0] f2i_rn  = {1'b0, f2i_fx[49:26]}
                        + {24'b0, (f2i_fx[25] & ((|f2i_fx[24:0]) | f2i_fx[26]))};
    wire [30:0] f2i_mag = (ex_a >= 10'sd23) ? f2i_ls : {6'b0, f2i_rn};
    // big covers +/-Inf too (e field 0xFF => ex_a = 128); NaN wins first
    wire        f2i_big = (ex_a >= 10'sd31);           // |RNE(x)| >= 2^31
    reg  [31:0] f2i_rail_hi, f2i_rail_lo;
    reg  [30:0] f2i_mag_hi, f2i_mag_lo;
    always @* case (cvt_dt_q)
        3'd0: begin                                    // int4 [-8, 7]
            f2i_rail_hi = 32'd7;   f2i_rail_lo = 32'hFFFF_FFF8;
            f2i_mag_hi  = 31'd7;   f2i_mag_lo  = 31'd8;
        end
        3'd1: begin                                    // int8 [-128, 127]
            f2i_rail_hi = 32'd127; f2i_rail_lo = 32'hFFFF_FF80;
            f2i_mag_hi  = 31'd127; f2i_mag_lo  = 31'd128;
        end
        default: begin                                 // int32 (dtype 0x4)
            // in-range magnitudes cap at 0x7FFFFF80 (m24 << 7), so the
            // magnitude compares never fire — only f2i_big rails
            f2i_rail_hi = 32'h7FFF_FFFF; f2i_rail_lo = 32'h8000_0000;
            f2i_mag_hi  = 31'h7FFF_FFFF; f2i_mag_lo  = 31'h7FFF_FFFF;
        end
    endcase
    // step-2 leg, from the step-1 capture (y_r = {big, mag31})
    wire        f2i_big_q = y_r[31];
    wire [30:0] f2i_mag_q = y_r[30:0];
    reg  [31:0] f2i_res;
    always @* begin
        if (a_nan | a_zero)
            f2i_res = 32'h0;                           // NaN -> 0; DAZ/zero
        else if (sa)
            f2i_res = (f2i_big_q | (f2i_mag_q > f2i_mag_lo))
                    ? f2i_rail_lo : (32'h0 - {1'b0, f2i_mag_q});
        else
            f2i_res = (f2i_big_q | (f2i_mag_q > f2i_mag_hi))
                    ? f2i_rail_hi : {1'b0, f2i_mag_q};
    end

    // ---- NARROW dtype 0x2/0x3: the ONE shared function (bit-identity
    //      clause §23.10.10(d)) — result consumed whole, never indexed.
    //      v1.8.0e: the SAME single instance also serves the OPS_DEQ
    //      bf16 round-once pack (input-muxed on op_sel — the DEQ
    //      intermediate parks in i64_q[31:0], which is free outside the
    //      CVT I2F leg; a second narrow instance measurably broke the
    //      C3 LUT budget and the y_r-mux Fmax margin). ----
    wire        nar_deq = (op_sel == OPS_DEQ);
    wire [31:0] nar_src = nar_deq ? i64_q[31:0] : a_q;
    wire [15:0] nar_h   = fp_narrow_f32(nar_src, nar_deq | cvt_dt_q[0]);

    // ---- step-2 result select (result-row low 32 bits: f16/bf16 zero-
    //      extend, f32 verbatim, ints int32-pattern — PE_Core builds the
    //      sext64 payload row at the integration stage) ----
    reg [31:0] cvt_res;
    always @* begin
        if (cvt_nar_q)
            cvt_res = (cvt_dt_q == 3'd2 || cvt_dt_q == 3'd3)
                    ? {16'h0, nar_h} : f2i_res;
        else
            cvt_res = (cvt_dt_q == 3'd2) ? wf16_res
                    : (cvt_dt_q == 3'd3) ? wbf_res
                    : i2f_pack;
    end

    // -------------------------------------------------------------------------
    // v1.8.0e OPS_DEQ datapath (§25.2.2) — fused exact-I2F x scale, bf16
    // ROUND-ONCE pack through the ONE shared narrow authority. Golden
    // twins: ref_dequant_lane == micro_dequant_lane (scripts/
    // golden_fp32.py; bit-equivalence proven model-side by
    // fp_release_sweep sweep_dequant_0e incl. the round-once
    // discriminator ties). Lane field arrives RAW in a_q (op-class DAZ
    // bypass at the capture mux); the scale in b_q is post-DAZ.
    // -------------------------------------------------------------------------
    wire [7:0] deq_k8    = (cvt_dt_q == 3'd0) ? {{4{a_q[3]}}, a_q[3:0]}
                                              : a_q[7:0];
    wire       deq_ksgn  = deq_k8[7];
    wire [7:0] deq_kmag  = deq_ksgn ? (~deq_k8 + 8'd1) : deq_k8;
    wire       deq_kzero = (deq_k8 == 8'h00);
    wire       deq_sign  = deq_ksgn ^ sb;      // sign(k) XOR sign(scale) pin

    // ---- step 1: normalize + RTO-24 into an fp32-format intermediate ----
    // P = |k| * m_s is EXACT in p[30:0] (|k| <= 128 = 2^7, m_s < 2^24 =>
    // P < 2^31; upper p bits provably zero at this use site). bl(P) in
    // [24, 31] (|k| >= 1 => P >= m_s >= 2^23), so the normalize shift
    // deq_sh = bl - 24 is an 8-way priority encode of p[30:23].
    reg [2:0] deq_sh;
    always @* casez (p[30:23])
        8'b1???????: deq_sh = 3'd7;
        8'b01??????: deq_sh = 3'd6;
        8'b001?????: deq_sh = 3'd5;
        8'b0001????: deq_sh = 3'd4;
        8'b00001???: deq_sh = 3'd3;
        8'b000001??: deq_sh = 3'd2;
        8'b0000001?: deq_sh = 3'd1;
        default:     deq_sh = 3'd0;            // bl == 24 (p[23] == 1)
    endcase
    wire [30:0] deq_pm      = p[30:0];
    wire [30:0] deq_shifted = deq_pm >> deq_sh;
    // dropped field = p[deq_sh-1:0] with deq_sh <= 7, so the sticky mask
    // only needs the low 7 bits (a 31-bit mask measurably overshot the
    // C3 LUT budget for zero coverage gain)
    wire [6:0]  deq_lowmask = ~(7'h7F << deq_sh);
    wire        deq_stk     = |(deq_pm[6:0] & deq_lowmask);
    // ROUND-TO-ODD jam into the LSB (golden _rto): sticky-preserving,
    // never carries — narrow(RTO24(v)) == RNE_bf16(v) for ALL v (the
    // micro_i2f_acc margin theorem, 24 >= 8 + 2), which is what makes
    // the single narrow below the ONE rounding of definition (a).
    wire [23:0] deq_m24 = deq_shifted[23:0] | {23'b0, deq_stk};
    // biased exponent = eb_f + deq_sh  (e_s = eb_f - 127, e_u = e_s +
    // bl - 24). Never below 1: eb_f >= 1 post-DAZ (the FTZ-at-dest cell
    // is vacuous, pinned). Above 254 = product >= 2^128: substitute
    // signed max-finite-with-sticky — the narrow authority's RNE
    // increment ripples 0x7F7F -> 0x7F80 = Inf (overflow -> Inf, never
    // max-finite, pinned).
    wire [8:0]  deq_ebias = {1'b0, eb_f} + {6'b0, deq_sh};
    wire        deq_ovf   = (deq_ebias > 9'd254);
    wire [31:0] deq_inter = deq_ovf
                          ? {deq_sign, 31'h7F7F_FFFF}
                          : {deq_sign, deq_ebias[7:0], deq_m24[22:0]};
    // step 1 parks deq_inter in i64_q[31:0] (single-writer register,
    // free outside the CVT I2F leg — deliberately NOT y_r, whose deep
    // write mux carries the re-staged F2I critical path); step 2 packs
    // through the ONE shared fp_narrow_f32 instance (nar_h, input-muxed
    // on op_sel — see the NARROW block) — bit-identity with the
    // CVT/0x7C sites by construction.

    // -------------------------------------------------------------------------
    // multiplier operand mux (held constant per step; fp_first legs consume
    // the previous pass live, temps take over from cycle 2 with the same
    // value). Default (ma, mb) also serves as the CLASSIFY-cycle launch of
    // the FS_MUL/FS_FMA significand product (the FS_MUL <= 6 enabler).
    // -------------------------------------------------------------------------
    wire [32:0] div_tmt = 33'h0_8000_0000
                        - (fp_first ? rto23_w : {1'b0, t_u[31:0]});
    wire [29:0] rsq_t2v = fp_first ? rto28_w : t_u[29:0];
    wire [29:0] rsq_omt = 30'h1800_0000 - rsq_t2v;     // 1.5 - t2 (Q2.28)

    always @* begin
        mul_a = {12'b0, ma};
        mul_b = {12'b0, mb};
        // v1.8.0e OPS_DEQ: |k| x m_s presented from FP_CLASSIFY on (the
        // FS_MUL classify-launch trick) and held constant through the
        // three K_INT steps, so p re-registers the same exact product.
        if (op_sel == OPS_DEQ)
            mul_a = {28'b0, deq_kmag};
        if (fp_state == FP_EXEC) begin
            case (op_sel)
                OPS_FSDIV: case (fp_step)
                    6'd0: begin                        // mb * r0
                        mul_a = {12'b0, mb};
                        mul_b = {4'b0, y_r};
                    end
                    6'd1, 6'd3, 6'd5: begin            // r * (2 - t)
                        mul_a = {4'b0, y_r};
                        mul_b = {3'b0, div_tmt};
                    end
                    6'd2, 6'd4: begin                  // mb * r'
                        mul_a = {12'b0, mb};
                        mul_b = fp_first ? {4'b0, rto30_w} : {4'b0, y_r};
                    end
                    6'd6: begin                        // ma * r3
                        mul_a = {12'b0, ma};
                        mul_b = fp_first ? {4'b0, rto30_w} : {4'b0, y_r};
                    end
                    6'd8: begin                        // q24 * mb
                        mul_a = {12'b0, q24_q};
                        mul_b = {12'b0, mb};
                    end
                    6'd10: begin                       // |resid| * r3
                        mul_a = {11'b0, t_u[24:0]};
                        mul_b = {4'b0, y_r};
                    end
                    default: ;                         // 7/9/11: unused
                endcase
                OPS_RSQRT: case (fp_step)
                    6'd0: begin                        // h * y0
                        mul_a = {6'b0, h_q};
                        mul_b = {4'b0, y_r};
                    end
                    6'd3, 6'd6: begin                  // h * y (pinned FIRST)
                        mul_a = {6'b0, h_q};
                        mul_b = fp_first ? {6'b0, rto28_w} : {4'b0, y_r};
                    end
                    6'd1, 6'd4, 6'd7: begin            // t1 * y
                        mul_a = fp_first ? {6'b0, rto28_w} : t_u;
                        mul_b = {4'b0, y_r};
                    end
                    6'd2, 6'd5, 6'd8: begin            // y * (1.5 - t2)
                        mul_a = {4'b0, y_r};
                        mul_b = {6'b0, rsq_omt};
                    end
                    default: ;                         // 9: unused
                endcase
                OPS_FEXP2: case (fp_step)
                    6'd1: begin                        // c6 * f
                        mul_a = {5'b0, FP_FEXP2_C6};
                        mul_b = {6'b0, y_r[29:0]};
                    end
                    6'd2, 6'd3, 6'd4, 6'd5, 6'd6: begin // acc * f
                        mul_a = fp_first ? {3'b0, e2_acc} : t_u;
                        mul_b = {6'b0, y_r[29:0]};
                    end
                    default: ;                         // 0/7: unused
                endcase
                default: ;                             // FSADD/MUL/FMA: (ma,mb)
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // shared wide adder + operand mux (FINAL packs only — internal div/rsqrt/
    // exp2 steps never touch FP_AddWide; WIDE mode is just the idle default
    // that keeps the FINAL output group untouched between ops)
    // -------------------------------------------------------------------------
    localparam PACK_WIDE  = 1'b0;
    localparam PACK_FINAL = 1'b1;
    localparam signed [10:0] EXP_Z = -11'sd1024;       // zero-operand exponent

    reg                aw_psign, aw_csign, aw_mode;
    reg  signed [10:0] aw_pexp, aw_cexp;
    reg         [47:0] aw_psig, aw_csig;

    wire signed [10:0] ex_ab1  = {ex_a[9], ex_a} + {ex_b[9], ex_b} + 11'sd1;
    wire signed [10:0] div_cxp = {exp_r[9], exp_r} + {{9{qe_q[1]}}, qe_q};
    wire signed [10:0] div_pxp = div_cxp - 11'sd22;

    always @* begin
        aw_psign = 1'b0;  aw_pexp = EXP_Z;  aw_psig = 48'b0;
        aw_csign = 1'b0;  aw_cexp = EXP_Z;  aw_csig = 48'b0;
        aw_mode  = PACK_WIDE;
        if (fp_state == FP_EXEC) begin
            case (op_sel)
                OPS_FSADD: begin                       // step 0
                    aw_mode = PACK_FINAL;
                    if (!a_zero) begin
                        aw_psign = sa;
                        aw_pexp  = {ex_a[9], ex_a};
                        aw_psig  = {ma, 24'b0};
                    end
                    if (!b_zero) begin
                        aw_csign = sb;
                        aw_cexp  = {ex_b[9], ex_b};
                        aw_csig  = {mb, 24'b0};
                    end
                end
                OPS_FSMUL, OPS_FSFMA,
                OPS_ACCEW: if (fp_step == 6'd1) begin
                    aw_mode  = PACK_FINAL;
                    aw_psign = sa ^ sb;
                    aw_pexp  = ex_ab1;
                    aw_psig  = fp_first ? p[47:0] : t_prod;
                    if (op_sel != OPS_FSMUL && !c_zero) begin
                        aw_csign = sc;
                        aw_cexp  = {ex_c[9], ex_c};
                        aw_csig  = {mc, 24'b0};
                    end
                end
                OPS_FSDIV: if (fp_step == 6'd11) begin
                    aw_mode  = PACK_FINAL;
                    aw_psign = sres_q;
                    aw_pexp  = div_pxp;
                    aw_psig  = fp_first ? rto7_w : t_prod;
                    aw_cexp  = div_cxp;                // sign 0: q0 > 0
                    aw_csig  = {q24_q, 24'b0};
                end
                default: ;
            endcase
        end
    end

    wire        [31:0] aw_final;
    wire               aw_wsign, aw_wzero;
    wire signed [11:0] aw_wexp;
    wire        [47:0] aw_wsig;

    FP_AddWide u_add (
        .clk       (clk),
        .p_sign    (aw_psign),
        .p_exp     (aw_pexp),
        .p_sig     (aw_psig),
        .c_sign    (aw_csign),
        .c_exp     (aw_cexp),
        .c_sig     (aw_csig),
        .pack_mode (aw_mode),
        .final_fp32(aw_final),
        .wide_sign (aw_wsign),
        .wide_exp  (aw_wexp),
        .wide_sig  (aw_wsig),
        .wide_zero (aw_wzero)
    );
    // wide outputs deliberately unconsumed: every internal fixed-point step
    // runs on FP_Mul36 + integer jams; FP_AddWide is FINAL-pack only here.

    // -------------------------------------------------------------------------
    // FP_CLASSIFY — specials resolve here and skip FP_EXEC entirely
    // (spec §23.10.5 table; ordering mirrors the golden decode chains)
    // -------------------------------------------------------------------------
    reg        spec_hit;
    reg [31:0] spec_res;

    wire mul_sign = sa ^ sb;
    wire [31:0] inf_a  = {sa, PINF[30:0]};
    wire [31:0] inf_b  = {sb, PINF[30:0]};
    wire [31:0] inf_c  = {sc, PINF[30:0]};
    wire [31:0] inf_ab = {mul_sign, PINF[30:0]};
    wire [31:0] zero_ab = {mul_sign, 31'b0};

    always @* begin
        spec_hit = 1'b1;
        spec_res = QNAN;
        case (op_sel)
            OPS_FSADD: begin                           // A1/A2/A3/A5(+add A6
                if (a_nan | b_nan)        spec_res = QNAN;      // via EXEC)
                else if (a_inf & b_inf)   spec_res = (sa == sb) ? inf_a : QNAN;
                else if (a_inf)           spec_res = inf_a;
                else if (b_inf)           spec_res = inf_b;
                else if (a_zero & b_zero) spec_res = (sa == sb) ? {sa, 31'b0}
                                                                : 32'h0;
                else                      spec_hit = 1'b0;
            end
            OPS_FSMUL: begin                           // M1/M2/M3/A5/Z1
                if (a_nan | b_nan)          spec_res = QNAN;
                else if (a_inf | b_inf)     spec_res = (a_zero | b_zero)
                                                       ? QNAN : inf_ab;
                else if (a_zero | b_zero)   spec_res = zero_ab;
                else                        spec_hit = 1'b0;
            end
            OPS_FSFMA,
            OPS_ACCEW: begin                           // F2/F3/F5 + NaN rule
                if (a_nan | b_nan | c_nan)  spec_res = QNAN;
                else if (a_inf | b_inf)
                    spec_res = (a_zero | b_zero) ? QNAN
                             : (c_inf && (sc != mul_sign)) ? QNAN
                             : inf_ab;
                else if (c_inf)             spec_res = inf_c;
                else if (a_zero | b_zero)
                    // exact (+-0) + c: signed-zero RNE rule / c verbatim
                    spec_res = c_zero ? ((mul_sign == sc) ? zero_ab : 32'h0)
                                      : c_q;
                else                        spec_hit = 1'b0;
            end
            OPS_FSDIV: begin                           // V1..V7
                if (a_nan | b_nan)   spec_res = QNAN;
                else if (a_inf)      spec_res = b_inf ? QNAN : inf_ab;
                else if (b_inf)      spec_res = zero_ab;
                else if (b_zero)     spec_res = a_zero ? QNAN : inf_ab;
                else if (a_zero)     spec_res = zero_ab;
                else                 spec_hit = 1'b0;
            end
            OPS_RSQRT: begin                           // R1..R5 (golden order)
                if (a_nan)        spec_res = QNAN;
                else if (a_zero)  spec_res = inf_a;
                else if (sa)      spec_res = QNAN;     // x < 0 incl. -Inf
                else if (a_inf)   spec_res = 32'h0;
                else              spec_hit = 1'b0;
            end
            OPS_FEXP2: begin                           // E1/E2/E5/E7 + Inf
                if (a_nan)        spec_res = QNAN;
                else if (a_inf)   spec_res = sa ? 32'h0 : PINF;
                else if (a_zero)  spec_res = FONE;
                else if (!sa && (a_q >= 32'h4300_0000)) spec_res = PINF;
                else if ( sa && (a_q >= 32'hC316_0000)) spec_res = 32'h0;
                else              spec_hit = 1'b0;
            end
            OPS_CVT: spec_hit = 1'b0;                  // no classify specials:
                                                       // NaN/Inf/zero are DATA
                                                       // inside each conversion
                                                       // (golden ref_cvt order)
            OPS_DEQ: begin                             // §25.2.2 pinned cells
                                                       // on the DAZ'd scale
                                                       // (bf16 result in the
                                                       // low result halfword)
                if (b_nan)        spec_res = {16'h0, 16'h7FC0};
                else if (b_inf)   spec_res = deq_kzero
                                           ? {16'h0, 16'h7FC0}
                                           : {16'h0, deq_sign, 15'h7F80};
                else if (b_zero | deq_kzero)
                                  spec_res = {16'h0, deq_sign, 15'h0000};
                else              spec_hit = 1'b0;
            end
            default: ;                                 // OPS_BAD: qNaN
        endcase
    end

    // rsqrt range reduction (pinned): x = x' * 4^k, x' in [1,4)
    wire       rs_par = ~a_q[23];                      // (E-127) & 1
    wire signed [8:0] rs_exa9 = $signed({1'b0, ea_f}) - 9'sd127;
    wire signed [8:0] rs_kk = (rs_exa9 - $signed({8'b0, rs_par})) >>> 1;

    // -------------------------------------------------------------------------
    // operand load helper — DAZ at load (denormal -> same-signed zero;
    // min_normal E=1 passes), FS_SUB folds into a B sign flip at load
    // -------------------------------------------------------------------------
    function [31:0] f_daz;
        input [31:0] v;
        f_daz = (v[30:23] == 8'h00) ? {v[31], 31'b0} : v;
    endfunction

    wire is_sub_in = (opcode_in == OPC_FSCALAR) && (subop_in == FS_SUB);
    wire [31:0] daz_a = f_daz(a_in);
    wire [31:0] daz_b = f_daz(b_in);
    wire [31:0] daz_c = f_daz(c_in);

    reg [3:0] op_sel_in;
    always @* begin
        op_sel_in = OPS_BAD;
        case (opcode_in)
            OPC_FRSQRT:  op_sel_in = OPS_RSQRT;
            OPC_FEXP2:   op_sel_in = OPS_FEXP2;
            OPC_ACCEW:   op_sel_in = OPS_ACCEW;
            OPC_FSCALAR: case (subop_in)
                FS_ADD, FS_SUB: op_sel_in = OPS_FSADD;
                FS_MUL:         op_sel_in = OPS_FSMUL;
                FS_FMA:         op_sel_in = OPS_FSFMA;
                FS_DIV:         op_sel_in = OPS_FSDIV;
                default:        op_sel_in = OPS_BAD;
            endcase
            // reserved sub-op / dtype rungs are lower_required upstream and
            // never presented; don't-care fallback = OPS_BAD (see header)
            OPC_CVT: if (subop_in <= CVT_NARROW_FROM_F32 && dtype_in <= 4'd4)
                op_sel_in = OPS_CVT;
            // v1.8.0e §25.2.2 — DEQUANT source dtype 0x0 int4 / 0x1 int8
            // (bf16-dest-only pin; other dtypes never presented)
            OPC_DEQUANT: if (dtype_in[3:1] == 3'b000)
                op_sel_in = OPS_DEQ;
            default: ;
        endcase
    end

    // MANDATORY RTL RULE (§23.10.10(b), confirmed-bug fix): operand-load
    // DAZ is BYPASSED for OPS_CVT sources that are not fp32-format — ALL
    // WIDEN directions (f16/bf16 widen and every I2F, whose raw narrow /
    // integer bits an unconditional DAZ would flush to 0, e.g. I2F(5)).
    // The fp32 sources of NARROW/F2I keep the DAZ flush (pin 7 — and the
    // same rule is pinned at the PE_Core 0x7C site, bit-identity clause).
    wire cvt_daz_bypass = (op_sel_in == OPS_CVT)
                       && (subop_in == CVT_WIDEN_TO_F32);
    // v1.8.0e §25.2.2 — the OPS_DEQ a_in lane field is RAW integer bits:
    // the same op-class-conditional bypass (an unconditional DAZ would
    // flush e.g. the int4 lane 5 to 0, the confirmed I2F bug class). The
    // fp32 scale on b_in KEEPS the DAZ flush (scale-denormal -> DAZ pin).
    wire deq_daz_bypass = (op_sel_in == OPS_DEQ);

    // -------------------------------------------------------------------------
    // the sequencer
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        case (fp_state)
            FP_IDLE: if (start) begin
                a_q       <= (cvt_daz_bypass | deq_daz_bypass) ? a_in : daz_a;
                b_q       <= daz_b ^ {is_sub_in, 31'b0};
                c_q       <= cvt_daz_bypass ? c_in : daz_c;
                op_sel    <= op_sel_in;
                cvt_nar_q <= (subop_in == CVT_NARROW_FROM_F32);
                cvt_dt_q  <= dtype_in[2:0];
                fp_state  <= FP_CLASSIFY;
            end

            FP_CLASSIFY: begin
                if (spec_hit) begin
                    res_reg  <= spec_res;
                    useaw_q  <= 1'b0;
                    fp_state <= FP_FINISH;
                end else begin
                    fp_state <= FP_EXEC;
                    fp_step  <= 6'd0;
                    fp_first <= 1'b1;
                    fp_wait  <= ent_kind;
                    useaw_q  <= (op_sel == OPS_FSADD) || (op_sel == OPS_FSMUL)
                             || (op_sel == OPS_FSFMA) || (op_sel == OPS_FSDIV)
                             || (op_sel == OPS_ACCEW);
                    orsign_q <= (op_sel == OPS_FSDIV) & mul_sign;
                    case (op_sel)
                        OPS_RSQRT: begin
                            // h = x'/2 exact: x' = 1.m * 2^rs_par (Q2.28)
                            h_q   <= rs_par ? {1'b0, ma, 5'b0}
                                            : {2'b00, ma, 4'b0};
                            y_r   <= {4'b0, rsq_seed, 19'b0};   // Q2.28 seed
                            exp_r <= -{rs_kk[8], rs_kk};
                        end
                        OPS_FSDIV: begin
                            y_r   <= {2'b0, div_seed, 21'b0};   // Q2.30 seed
                            exp_r <= ex_a - ex_b;
                        end
                        default: ;
                    endcase
                end
            end

            FP_EXEC: begin
                fp_first <= 1'b0;

                // ---- first-cycle captures / K_INT step actions ----
                if (fp_first) begin
                    case (op_sel)
                        OPS_FSMUL, OPS_FSFMA, OPS_ACCEW:
                            if (fp_step == 6'd1) t_prod <= p[47:0];
                        OPS_CVT: case (fp_step)
                            6'd0: begin    // I2F |sext64| capture (widen/
                                           // narrow legs park don't-cares)
                                i64_q  <= i2f_mag;
                                sres_q <= i2f_sgn;
                            end
                            6'd1: if (cvt_nar_q)
                                // F2I round pre-stage (f16/bf16 narrow
                                // parks a don't-care in y_r)
                                y_r <= {f2i_big, f2i_mag};
                            else begin
                                // I2F normalize + pass-1 RTO jam
                                y_r <= i2f_inter;
                                n_q <= i2f_exp;
                            end
                            6'd2: res_reg <= cvt_res;   // pack (all forms)
                            default: ;
                        endcase
                        OPS_DEQ: case (fp_step)
                            // 0: mul tail (second FP_Mul36 cycle) — no
                            //    action; p is valid during step 1.
                            // 1: park the intermediate in i64_q[31:0]
                            //    ONLY (partial write — the upper half
                            //    keeps its stale value so the CVT leg's
                            //    mux stays 1-deep there; nar_src reads
                            //    just [31:0]).
                            6'd1: i64_q[31:0] <= deq_inter;     // norm+RTO-24
                            6'd2: res_reg <= {16'h0, nar_h};    // the shared
                                                                // narrow (bf16
                                                                // leg via the
                                                                // nar_src mux)
                            default: ;
                        endcase
                        OPS_FSDIV: case (fp_step)
                            6'd1, 6'd3, 6'd5: t_u <= {3'b0, rto23_w};
                            6'd2, 6'd4, 6'd6: y_r <= rto30_w;
                            6'd7: begin        // q24/qe (RNE24 with carry)
                                if (q_rnd[24]) begin
                                    q24_q <= 24'h80_0000;
                                    qe_q  <= q_ge1 ? 2'sd1 : 2'sd0;
                                end else begin
                                    q24_q <= q_rnd[23:0];
                                    qe_q  <= q_ge1 ? 2'sd0 : -2'sd1;
                                end
                            end
                            6'd9: begin        // Markstein residual (exact)
                                sres_q <= resid_neg;
                                t_u    <= {11'b0, resid_mag[24:0]};
                            end
                            6'd11: t_prod <= rto7_w;
                            default: ;
                        endcase
                        OPS_RSQRT: case (fp_step)
                            6'd1, 6'd2, 6'd4,
                            6'd5, 6'd7, 6'd8: t_u <= {6'b0, rto28_w};
                            6'd3, 6'd6:       y_r <= {2'b0, rto28_w};
                            6'd9:             res_reg <= rsq_pack_res;
                            default: ;
                        endcase
                        OPS_FEXP2: case (fp_step)
                            6'd0: begin        // exact n+f split
                                n_q <= e2_n;
                                y_r <= {2'b0, e2_ff};
                            end
                            6'd2, 6'd3, 6'd4,
                            6'd5, 6'd6: t_u <= {3'b0, e2_acc};
                            6'd7:       res_reg <= e2_pack_res;
                            default: ;
                        endcase
                        default: ;
                    endcase
                end

                // ---- step advance ----
                if (fp_wait != 2'd0)
                    fp_wait <= fp_wait - 2'd1;
                else begin
                    if (cur_last)
                        fp_state <= FP_FINISH;
                    else begin
                        fp_step  <= step_p1;
                        fp_first <= 1'b1;
                        fp_wait  <= nxt_kind;
                    end
                end

                // exp2 integer bypass (E3/E4): f == 0 -> exact 2^n now
                // (last write wins over the generic advance above)
                if (fp_first && op_sel == OPS_FEXP2 && fp_step == 6'd0
                        && !(|e2_ff)) begin
                    res_reg  <= e2_bypass_res;
                    fp_state <= FP_FINISH;
                end
            end

            FP_FINISH: fp_state <= FP_IDLE;

            default: fp_state <= FP_IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // outputs
    // -------------------------------------------------------------------------
    assign busy   = start | (fp_state != FP_IDLE);
    assign done   = (fp_state == FP_FINISH);
    // FS_DIV runs on positive significands and ORs the quotient sign in at
    // the end (works verbatim for the Inf / FTZ-zero pack outcomes too);
    // all other FP_AddWide users carry their signs through the datapath.
    assign result = useaw_q ? (aw_final | {orsign_q, 31'b0}) : res_reg;

endmodule

/* verilator lint_on PROCASSINIT */
/* verilator lint_on UNUSEDPARAM */
/* verilator lint_on UNUSEDSIGNAL */
