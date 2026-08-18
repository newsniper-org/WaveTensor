// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

`include "attributes.vh"

// =============================================================================
// FP_StepSeq.v — v1.8.0c MU-hosted fp32 step-sequencer unit (spec §23.10,
// synth Gate 3 of §23.10.7) + v1.8.0d OPS_CVT / OPS_ACCEW extension
// (spec §23.10.10, synth Gate C3 of §23.10.10(g)) + v1.8.0e OPS_DEQ
// fused per-lane DEQUANT program (spec §25.2.2, 0e1) + 3a-C3 OPS_FDOTCR
// audit dot program (spec §27.7a, GATE V20-4).
//
// 3a-C3 adds ONE op class (op_sel already 4-bit — no widening; the
// standing rule §25.1 item 9 / §27.7a.4 re-proves ALL NINE existing step
// programs at the unit TB, which the appended-only tb_fp_stepseq suites
// do by running the pre-3a set byte-unchanged):
//   OPS_FDOTCR 0x7A FDOT32_CR — audit-only correctly-rounded 32-term
//             narrow dot: r == pack_signed(exact Σ a_i·b_i) as fp32.
//             Non-pipelined, busy-interlocked, ACC bank untouched. The
//             whole program lives in an OP-GATED sub-sequencer at the
//             bottom of this file (its own state, its own registers);
//             the generic (op_sel, fp_step) machinery is parked at step
//             0 and termination is taken from fd_fin. Both shared
//             operators are REUSED verbatim — FP_Mul36 for the exact
//             narrow significand products (no new multiplier: the GATE
//             V20-4 premap $mul delta == 0 criterion) and FP_AddWide for
//             both the exact TwoSum merges (PACK_WIDE, vacuous RTO) and
//             the descending RTO-48 fold, with exactly ONE PACK_FINAL.
//             ALGORITHM AUTHORITY = spec §27.7a.2a (the C1-amended text):
//             descending fold + the refined "merge the two lowest"
//             insertion walk. The original ASCENDING fold pin was
//             REFUTED by 3a-C1 measurement (2 value-contract
//             counterexamples, 23.8% relative error) — an
//             insertion-fused ascending streaming fold is the RECORDED
//             REGRESSION PATH and is forbidden. Keeping that ban
//             CHECKABLE constrains the component geometry: the
//             non-overlap test must be golden's `top(a) <= e_b`
//             EXACTLY (e restored from the stored magnitude's trailing
//             zeros — see the datapath block), because the stricter
//             approximation `xe_b - xe_a >= 24` merges the column so
//             coarse that the ASC failure mode becomes unreachable and
//             an ascending mutant survives every vector. Repaired in
//             3a-C3 (spec §27.7a.2b);
//             tb_fp_stepseq's fdotcr_descending_fold_discriminator now
//             reads the RTL's OWN expansion out of fd_xp and shows the
//             ASC fold of that very column disagrees with the value
//             contract.
//             Golden twin: scripts/golden_fdotcr.py +
//             include/generated/fdotcr_vectors.hex (450 directed lines,
//             RESULT is ALWAYS the value-contract right-hand side).
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
//              (v1.8.0e, one lane per launch) / 0x7A FDOT32_CR (3a-C3,
//              see the OPERAND INGRESS note below).
//
//   OPERAND INGRESS, 0x7A ONLY (3a-C3 — the ONLY protocol addition):
//              FDOT32_CR eats a 1,024-bit A||B wave, which does not fit
//              a_in/b_in/c_in. It arrives ONE 64-bit fragment per cycle
//              on {b_in, a_in} over 16 cycles: fragment 0 on the launch
//              edge, fragments 1..15 on the 15 cycles that follow, then
//              a_in/b_in/c_in are don't-care for the rest of the
//              program. The 1,024-bit buffer is MU-LOCAL (this module)
//              exactly as §27.7a.1 requires — EHDecode is cluster-shared
//              and cannot hold it across the program. The port list is
//              deliberately UNCHANGED: a new 1,024-bit port would leave
//              PE_Core's existing instantiation with a missing pin,
//              which is a FATAL verilator elaboration error for every
//              PE_Core-including suite, and that wiring is 3a-C4's. C4
//              may keep this streamed form or replace it with a wide
//              port — the program logic is identical either way.
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
//   FDOT32_CR    classify, 16x ingress, per-lane {classify, 2x mul,
//                insert scan, walk (emit | merge+reinsert)}, descending
//                fold, PACK_FINAL          = 1,167 measured worst
//                                            (<= 10,000 HARD, §27.7a.2)
//                measured over 450 golden vectors + 3,000 fresh
//                family-generator trials (tb_fp_stepseq
//                fdotcr_golden_vectors / fdotcr_extended_family_sweep);
//                the draft's 1,616 predates the STEP I exact-overlap
//                correction (§27.7a.2b amendment-12): dropping the
//                approximate test removed merges that cost more than
//                the fold passes they saved, so the worst case FELL.
//                this is the number that graduates the §27.7a.2a
//                amendment-3 UNCOUNTED insertion-queue cycle axis.
//                specials (any NaN/Inf lane) finish in 17 (measured):
//                the EFT is never entered, so FP_AddWide's "no special
//                operands" precondition is preserved exactly as the
//                other programs preserve it in FP_CLASSIFY.
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
    output     [31:0] result,
    // v1.8.0e 3a-C4 §27.7a.4/§35.3 — FDOT32_CR sticky status, DELIBERATELY
    // two separate ports. Merging them is forbidden: §27.7a.3 check (i)
    // consumes `fd_special_sticky` as NORMAL audit data (the SDK feeds
    // special operands on purpose and compares sticky presence across the
    // two datapaths), while `fd_unit_fault` is an RTL defect signal that
    // the parent folds into any_error_flag. One port cannot carry both —
    // the OR-reduce upstream is irreversible.
    //
    // GRADE (read before rewiring): both are PER-OP latches — every
    // `fd_launch` edge overwrites them (see the sub-sequencer's launch
    // arm). This block has NO reset port, so a reset-clearable sticky
    // CANNOT be built here; §26.5-grade promotion of the FAULT belongs to
    // the first ancestor that owns `rst` (Cluster). `fd_special_sticky`
    // MUST stay per-op — §27.7a.3 recovers (result, sticky) pairs per op.
    // Both are valid from the fragment-0 receiving edge through the next
    // launch, hence stable across the `done` beat.
    output            fd_special_sticky,
    output            fd_unit_fault
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
    localparam [3:0] OPS_FDOTCR = 4'd10; // v1.8.0e 3a-C3 0x7A (spec §27.7a —
                                         // op-gated sub-sequencer, 아래
                                         // OPS_FDOTCR datapath 블록)

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
                // 3a-C3 §27.7a: 0x7A 는 자체 sub-sequencer 가 종료를 소유한다
                // (generic step 기계는 step 0 에 고정 — 아래 FP_EXEC 절).
                // last 를 절대 세우지 않아 generic 경로로는 종료 불가능.
                OPS_FDOTCR: f_step_info = {1'b0, K_INT};
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

    // =========================================================================
    // v1.8.0e 3a-C3 OPS_FDOTCR datapath (spec §27.7a, 0x7A FDOT32_CR)
    //
    // 32-항 narrow dot 의 correctly-rounded fp32 — audit 전용, non-pipelined.
    // 값 계약 (§27.7a.1): r == pack_signed(exact Σ a_i·b_i). 알고리즘 정본은
    // **§27.7a.2a** (C1 실측이 C0 의 ascending pin 을 부정한 뒤의 개정본):
    //
    //   STEP M  classify + exact 곱 — FP_Mul36 재사용 (신규 곱셈기 금지,
    //           GATE V20-4 의 premap $mul delta == 0 조건). bf16 8x8->16b /
    //           f16 11x11->22b, 반올림 0회.
    //   STEP T  TwoSumExact = FP_AddWide PACK_WIDE 1 pass. 겹침 쌍의 정렬
    //           폭은 구조적으로 <= 48 이므로 RTO-48 이 vacuous == exact,
    //           산출은 wide_sig 의 24|24 **field-slice** (동적 shift 없음).
    //           그 전제가 깨지면 (pass 가 실제로 반올림하면) golden 의
    //           `vacuous-RTO violated` 와 같은 loud fault 를 낸다.
    //   STEP I  grow-expansion 삽입 — §27.7a.2a amendment-2 의 정련 walk
    //           ("최저 2개 순서 merge"). 원문의 chain 독해는 비겹침 invariant
    //           을 스스로 위반하므로 폐기됐다 (미러링 금지). 비겹침·정렬
    //           키는 golden 판정을 **근사 없이** 미러링한다 (아래 표현 블록).
    //   STEP F  **descending** RTO-48 fold (최상위 component 부터).
    //           amendment-1 — ascending 은 C1 반례 2건 (상대오차 24%) 로
    //           부정된 pin 이며 삽입-융합 스트리밍 오름차순 fold 는 **금지
    //           경로**다. freeze (jam 이후 acc 불변) 는 정리의 정보 축이라
    //           여기서 loud fault 로 검사한다 — 감시 창은 golden 과 같이
    //           **첫 실질 jam 직후 첫 pass 부터** 열린다 (fd_jam).
    //   STEP P  PACK_FINAL 1회 → §27.2.1 추출 정리로 값 계약이 닫힌다.
    //
    // component 표현 (REPRESENTATION 편차 — 값은 golden 과 동일, FS_DIV
    // Markstein pack 의 선례와 같은 등급): golden 의 (m, e) 는 임의 폭 m 을
    // 쓰지만 본 RTL 은 **정규화 저장** {sign, xe[11:0], mag[23:0]} 37b 를
    // 쓴다 — mag[23] == 1 이 항상 성립하고 값 = mag * 2^(xe-23) 이다. 이
    // 형이 load-bearing 인 이유: FP_AddWide 피연산자 규약 (sig 는
    // [2^46,2^48), 단위가 bit47) 이 고정 shift {mag,24'b0} 로 충족되어
    // 정렬용 barrel shifter 가 **불필요**하다.
    //
    // 정규화 저장은 golden 의 기하 두 축을 **복원해서** 써야 한다 (생략 =
    // 다른 알고리즘):
    //   e   (최저 set bit)  = xe - 23 + tz(mag)   — fd_tz24 로 복원
    //   top (배타 상한)      = xe + 1
    // 이로써 비겹침 판정은 golden grow_insert 의 `comp_top(a) <= b[1]` 과,
    // 정렬 키는 golden _insort 의 `(e, top)` 과 **정확히** 같아진다.
    // (golden 의 m 은 trailing zero 를 남길 수 있어 그 e 는 '선언된 scale'
    // 이고 본 RTL 의 e 는 '실제 최저 set bit' 이다 — 후자 >= 전자이므로
    // 판정이 golden 보다 느슨해지는 일은 없고, 정리 전건 (비겹침·오름차순)
    // 은 실제 bit 구간 기준으로 성립한다. 열은 golden 과 같거나 더 잘다.)
    //
    // *** 3a-C3 정정 기록 (spec §27.7a.2b) ***: 본 프로그램의 초안은 tz 복원을
    // 생략하고 비겹침을 `xe_b - xe_a >= 24` 로 근사했다. 그 근사는 golden
    // 판정보다 **엄격**해서 (tz(mag_b) 만큼) 열이 뭉치고 (실측 최대 열
    // 길이 17 vs golden 25), 그 결과 §27.7a.2a 가 **금지 pin** 으로 못박은
    // ASC fold 실패 모드가 구조적으로 도달 불가가 됐다 — 즉 금지 pin 이
    // 지켜졌음을 실증한 것이 아니라 **검사할 수 없게** 만든 것이다 (ASC
    // 변이가 전 벡터를 생존). 정확 미러로 정정한 뒤의 실측 (TB 가 RTL 자신의
    // fd_xp 를 읽어 센 값): 열이 빈 행을 뺀 finite 311 행 중 **2 행**,
    // 신규 eft_top_cancel 120 trial 중 **3 건**에서 ASC != 값 계약 (golden
    // report 의 asc_detection_rate_by_family eft_top_cancel 4% 와 같은 급)
    // — ASC 변이는 이제 사살된다 (33 suite 중 4 FAIL).
    //
    // 최종 값이 golden 과 bit-동일한 근거는 §27.7a.2a amendment-1 정리의
    // **일반형** (임의의 비겹침 오름차순 열에 대해 fold == RTO_48(exact))
    // 이다 — 결과는 열의 구체적 분해가 아니라 exact 합에만 의존한다.
    //
    // 배열/포인터: xp[0..FD_TOP] 가 오름차순 열이고 [0, w) = 확정 방출분
    // (golden 의 out), [w, n) = 대기열 (golden 의 pend) 이다. 두 영역이
    // 하나의 배열에 연접 저장될 수 있는 이유는 방출된 component 가 항상
    // 남은 전부의 아래라는 walk 불변식 그 자체다.
    // =========================================================================
    localparam [7:0] OPC_FDOTCR = 8'h7A;      // §27.7a.1 (C2 ISA row 0x7A)
    localparam [5:0] FD_CAP = 6'd33;          // §27.7a.2 용량 (32 삽입 + carry 1)
    localparam [5:0] FD_TOP = 6'd34;          // 배열 최상단 index (전이 guard 1)

    localparam [3:0] FDS_LOAD  = 4'd0;        // 16-fragment 수납
    localparam [3:0] FDS_PRIME = 4'd1;        // 첫 fragment 를 lane 창으로
    localparam [3:0] FDS_LANE  = 4'd2;        // STEP M: classify + mul launch
    localparam [3:0] FDS_MUL1  = 4'd3;        // FP_Mul36 latency 2 의 2번째
    localparam [3:0] FDS_PROD  = 4'd4;        // 곱 -> component
    localparam [3:0] FDS_INS   = 4'd5;        // STEP I: 정렬 삽입 (하강 스캔)
    localparam [3:0] FDS_WALK  = 4'd6;        // STEP I: 최저 2개 walk
    localparam [3:0] FDS_MRGW  = 4'd7;        // STEP T: AddWide pass + split
    localparam [3:0] FDS_REINS = 4'd8;        // split 조각 재삽입 + 압축
    localparam [3:0] FDS_NEXT  = 4'd9;        // lane 전진 / 용량 assert
    localparam [3:0] FDS_FOLDW = 4'd10;       // STEP F: descending fold pass
    localparam [3:0] FDS_PACKW = 4'd11;       // STEP P: PACK_FINAL pass
    localparam [3:0] FDS_DONE  = 4'd12;

    localparam [1:0] FDR_AW   = 2'd0;         // 결과 = FP_AddWide PACK_FINAL
    localparam [1:0] FDR_ZERO = 2'd1;         // 결과 = +0 (exact cancellation)
    localparam [1:0] FDR_QNAN = 2'd2;         // 결과 = canonical qNaN

    // 제어 상태 (reset-free — 선언 초기화, 본 파일 헤더 규약)
    reg  [3:0]  fd_st = FDS_DONE;
    reg  [5:0]  fd_cnt;                       // fragment idx / lane idx
    reg         fd_bf16;                      // dtype latch (1 = bf16)
    reg         fd_spec = 1'b0;               // §27.7a.1 (iii) special sticky
    reg         fd_fault = 1'b0;              // loud fault (용량/RTO/freeze)
    reg         fd_jam;                       // 첫 실질 jam 관측 (정리 (2)(3))
    reg  [1:0]  fd_rsel;                      // 결과 소스 선택
    reg  [1:0]  fd_wait;                      // FP_AddWide latency 카운터
    reg  [5:0]  fd_n, fd_w, fd_j, fd_dst;     // 열 길이 / walk / 스캔 포인터
    reg         fd_hi_done;                   // 재삽입: hi 배치 완료
    reg  [36:0] fd_ins, fd_hi;                // 삽입 대상 / split 상위 조각
    reg  signed [11:0] fd_pe;                 // 곱 지수 ea+eb
    reg         fd_ps;                        // 곱 부호 sa^sb

    // capture: 1,024b operand wave (MU-local — EHDecode 는 cluster-shared 라
    // 1,167 cycle 급 프로그램 (실측; 초안 추정 ~5k) 동안 보존 불가, §27.7a.1). 큰 두 레지스터는 **64b
    // 하강 shift 하나**만 갖는다 (상위 64b 만 mux; 하위 448b 는 순수 shift)
    // — 16b 소비 shift 와 64b 수납 shift 를 같은 레지스터에 얹으면 1,024b
    // 전폭 2:1 mux 가 되어 GATE V20-4 의 LUT delta 예산을 혼자 먹는다.
    // lane 창 (fd_fa/fd_fb) 이 fragment 안의 4 lane 을 16b 씩 소비한다.
    reg  [511:0] fd_asr, fd_bsr;              // frag 0-7 = A / 8-15 = B
    reg  [63:0]  fd_fa, fd_fb;                // 현재 fragment (4 lane 창)

    // expansion 저장 (동기 write / 비동기 read — 분산 RAM 추론 형).
    // 초기화 없음: 매 launch 가 fd_n <= 0 으로 논리적으로 비운다.
    reg  [36:0] fd_xp [0:FD_TOP];

    // fold accumulator = FP_AddWide PACK_WIDE 형식 그대로 (형식이 I/O 하에
    // 닫혀 있다 — FP_AddWide 헤더의 canonical zero 규약)
    reg         fd_accs;
    reg  signed [11:0] fd_acce;
    reg  [47:0] fd_accm;

    // ---- STEP M: lane classify (§27.7a.1 (i)/(ii) 행 그대로) ----
    // 반환 = {sp, zr, sign, m11, e12}: bf16 exp field 0 -> zero 기여 (DAZ),
    // f16 subnormal -> leading-one normalize 후 exact 기여 (DAZ 아님).
    // 값 = m11 * 2^(e - frac), frac = 7 (bf16) / 10 (f16).
    // 결과는 WIRE 로 받아 WIRE 를 slice 한다 (§23.8 — 함수결과 인덱싱 금지).
    function [25:0] fd_classify;
        input        bf;
        input [15:0] x;
        reg   [7:0]  eb8;
        reg   [4:0]  ef5;
        reg   [9:0]  mf10;
        reg   [3:0]  kk;
        reg   [10:0] mn;
        reg   signed [11:0] ee;
        reg          sp, zr;
        begin
            eb8  = x[14:7];
            ef5  = x[14:10];
            mf10 = x[9:0];
            sp = 1'b0;  zr = 1'b0;  mn = 11'd0;  ee = 12'sd0;  kk = 4'd0;
            if (bf) begin
                if (eb8 == 8'hFF)       sp = 1'b1;      // NaN/Inf (sNaN 포함)
                else if (eb8 == 8'h00)  zr = 1'b1;      // zero + 254 subnormal
                else begin
                    mn = {3'b000, 1'b1, x[6:0]};
                    ee = $signed({4'b0, eb8}) - 12'sd127;
                end
            end else begin
                if (ef5 == 5'h1F)       sp = 1'b1;
                else if (ef5 == 5'h00) begin
                    if (mf10 == 10'd0)  zr = 1'b1;
                    else begin
                        casez (mf10)                    // k = 11 - bl(m)
                            10'b1?????????: kk = 4'd1;
                            10'b01????????: kk = 4'd2;
                            10'b001???????: kk = 4'd3;
                            10'b0001??????: kk = 4'd4;
                            10'b00001?????: kk = 4'd5;
                            10'b000001????: kk = 4'd6;
                            10'b0000001???: kk = 4'd7;
                            10'b00000001??: kk = 4'd8;
                            10'b000000001?: kk = 4'd9;
                            default:        kk = 4'd10;
                        endcase
                        mn = {1'b0, mf10} << kk;        // exact normalize
                        ee = -12'sd14 - $signed({8'b0, kk});
                    end
                end else begin
                    mn = {1'b1, mf10};
                    ee = $signed({7'b0, ef5}) - 12'sd15;
                end
            end
            fd_classify = {sp, zr, x[15], mn, ee};
        end
    endfunction

    wire [15:0] fd_la = fd_fa[15:0];          // 현재 lane 의 A operand (RAW —
    wire [15:0] fd_lb = fd_fb[15:0];          // DAZ 우회는 원시 tap 그 자체다)
    wire [25:0] fd_qa = fd_classify(fd_bf16, fd_la);
    wire [25:0] fd_qb = fd_classify(fd_bf16, fd_lb);
    wire        fd_skip = fd_qa[25] | fd_qa[24] | fd_qb[25] | fd_qb[24];
    wire [10:0] fd_ma = fd_qa[22:12];
    wire [10:0] fd_mb = fd_qb[22:12];

    // 곱 -> component: bl(p) 는 dtype 당 2값뿐이라 정규화가 상수 shift 다
    // (bf16 p in [2^14,2^16) / f16 p in [2^20,2^22)); xe = ea+eb+carry.
    wire        fd_pc1  = fd_bf16 ? p[15] : p[21];
    wire [23:0] fd_pmag = fd_bf16 ? (p[15] ? {p[15:0], 8'b0} : {p[14:0], 9'b0})
                                  : (p[21] ? {p[21:0], 2'b0} : {p[20:0], 3'b0});
    wire signed [11:0] fd_pxe = fd_pe + $signed({11'b0, fd_pc1});

    // ---- component 기하 복원: tz(mag) (mag[23] == 1 이라 tz <= 23) ----
    // fd_lomag 의 leading-zero cascade 와 같은 형 (고정 shift 만 — 동적
    // part-select 없음). 반환은 WIRE 로 받아 WIRE 를 쓴다 (§23.8).
    function [4:0] fd_tz24;
        input [23:0] m;
        reg   [23:0] t0, t1, t2, t3;
        reg          z16, z8, z4, z2, z1;
        begin
            z16 = ~|m[15:0];  t0 = z16 ? {16'b0, m[23:16]} : m;
            z8  = ~|t0[7:0];  t1 = z8  ? {8'b0,  t0[23:8]} : t0;
            z4  = ~|t1[3:0];  t2 = z4  ? {4'b0,  t1[23:4]} : t1;
            z2  = ~|t2[1:0];  t3 = z2  ? {2'b0,  t2[23:2]} : t2;
            z1  = ~t3[0];
            fd_tz24 = {z16, z8, z4, z2, z1};
        end
    endfunction

    // ---- 배열 read 포트 (2개 — 상태별 index mux; 포트를 늘리면 35:1 x 37b
    //      mux 가 그만큼 복제된다) ----
    wire [5:0] fd_w1  = fd_w + 6'd1;
    wire [5:0] fd_jm1 = (fd_j == 6'd0) ? 6'd0 : (fd_j - 6'd1);
    reg  [5:0] fd_ra;
    always @* case (fd_st)
        FDS_INS:   fd_ra = fd_jm1;
        FDS_REINS: fd_ra = fd_j;
        FDS_FOLDW: fd_ra = fd_j;
        default:   fd_ra = fd_w;
    endcase
    wire [36:0] fd_ca = fd_xp[fd_ra];
    wire [36:0] fd_cb = fd_xp[fd_w1];

    wire signed [12:0] fd_xa = $signed({fd_ca[35], fd_ca[35:24]});
    wire signed [12:0] fd_xb = $signed({fd_cb[35], fd_cb[35:24]});
    wire signed [12:0] fd_xi = $signed({fd_ins[35], fd_ins[35:24]});
    wire signed [12:0] fd_xh = $signed({fd_hi[35], fd_hi[35:24]});
    wire [4:0] fd_tza = fd_tz24(fd_ca[23:0]);
    wire [4:0] fd_tzb = fd_tz24(fd_cb[23:0]);
    wire [4:0] fd_tzi = fd_tz24(fd_ins[23:0]);
    wire [4:0] fd_tzh = fd_tz24(fd_hi[23:0]);
    // e = xe - 23 + tz(mag) — golden component 의 (m,e) 중 e 축
    wire signed [12:0] fd_ea = fd_xa - 13'sd23 + $signed({8'b0, fd_tza});
    wire signed [12:0] fd_eb = fd_xb - 13'sd23 + $signed({8'b0, fd_tzb});
    wire signed [12:0] fd_ei = fd_xi - 13'sd23 + $signed({8'b0, fd_tzi});
    wire signed [12:0] fd_eh = fd_xh - 13'sd23 + $signed({8'b0, fd_tzh});
    // 비겹침 = golden grow_insert 의 `comp_top(a) <= b[1]` 정확 미러
    // (top(a) = xe_a + 1 이므로 xe_a < e_b). 근사 `xe_b - xe_a >= 24` 는
    // 더 강한 판정이라 금지 pin 을 검사 불능으로 만든다 — 위 블록 주석.
    wire fd_disj   = fd_xa < fd_eb;
    // 정렬 키 = golden _insort 의 (e, top) 오름차순 사전식 비교
    wire fd_ins_gt = (fd_ea > fd_ei)
                  || ((fd_ea == fd_ei) && (fd_xa > fd_xi));  // 삽입 하강 스캔
    wire fd_hi_ge  = (fd_ea < fd_eh)
                  || ((fd_ea == fd_eh) && (fd_xa <= fd_xh)); // 재삽입 이동
                                                   // (동률에서 <= 는 golden
                                                   // insort 의 동률 처리와
                                                   // 같은 방향)

    // ---- FP_AddWide 피연산자 (전부 레지스터 함수 — pass 3 cycle 동안 불변) ----
    wire fd_aw_act  = (fd_st == FDS_MRGW) || (fd_st == FDS_FOLDW)
                   || (fd_st == FDS_PACKW);
    wire fd_aw_mode = (fd_st == FDS_PACKW);        // PACK_FINAL / PACK_WIDE
    wire        fd_p_sign = (fd_st == FDS_MRGW) ? fd_cb[36] : fd_accs;
    wire signed [10:0] fd_p_exp = (fd_st == FDS_MRGW) ? $signed(fd_cb[34:24])
                                                     : $signed(fd_acce[10:0]);
    wire [47:0] fd_p_sig = (fd_st == FDS_MRGW) ? {fd_cb[23:0], 24'b0} : fd_accm;
    wire        fd_c_sign = fd_aw_mode ? 1'b0 : fd_ca[36];
    // PACK_FINAL 의 C 는 zero operand: exp 는 반드시 상대보다 엄격히 아래여야
    // 하므로 FP_AddWide 규약의 -1024 을 쓴다 (아래 EXP_Z 와 같은 값 — 그
    // localparam 은 이 블록보다 뒤에 선언되므로 리터럴로 적는다).
    wire signed [10:0] fd_c_exp = fd_aw_mode ? -11'sd1024
                                             : $signed(fd_ca[34:24]);
    wire [47:0] fd_c_sig = fd_aw_mode ? 48'b0 : {fd_ca[23:0], 24'b0};

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
                // 3a-C3 §27.7a STEP M — narrow significand 곱을 공유
                // FP_Mul36 에 태운다 (신규 곱셈기 금지, GATE V20-4 의
                // premap $mul delta == 0). FDS_LANE/FDS_MUL1 두 cycle 동안
                // lane 창이 정지해 있으므로 피연산자는 자동으로 held 다.
                OPS_FDOTCR: begin
                    mul_a = {25'b0, fd_ma};
                    mul_b = {25'b0, fd_mb};
                end
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
                // 3a-C3 §27.7a STEP T/F/P — 공유 FP_AddWide 재사용 (merge 와
                // fold 는 PACK_WIDE, 최종 1회만 PACK_FINAL). 비활성 cycle 은
                // 블록 상단의 idle default 를 그대로 둔다.
                OPS_FDOTCR: if (fd_aw_act) begin
                    aw_mode  = fd_aw_mode;
                    aw_psign = fd_p_sign;
                    aw_pexp  = fd_p_exp;
                    aw_psig  = fd_p_sig;
                    aw_csign = fd_c_sign;
                    aw_cexp  = fd_c_exp;
                    aw_csig  = fd_c_sig;
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
    // wide outputs deliberately unconsumed by the v1.8.0c/d/e scalar step
    // programs: their internal fixed-point steps run on FP_Mul36 + integer
    // jams and FP_AddWide is FINAL-pack only there. The 3a-C3 OPS_FDOTCR
    // program below IS a wide-output consumer (STEP T merge + STEP F fold).

    // -------------------------------------------------------------------------
    // 3a-C3 §27.7a — STEP T 의 24|24 field-slice split + fold 계측
    // -------------------------------------------------------------------------
    // 겹침 쌍의 정렬 폭은 구조적으로 <= 48 이라 PACK_WIDE 의 RTO-48 은
    // vacuous == exact 다 (§27.7a.2 (ii)). 정확 미러 판정 하의 도출: merge
    // 는 not-disj, 즉 xe_a >= e_b = xe_b - 23 + tz_b 일 때만 일어나고 열은
    // (e, top) 오름차순이라 e_a <= e_b 이므로 |xe_a - xe_b| <= 23 —
    // 어느 쪽이 anchor 든 shamt <= 23 이라 shiftee 의 LSB 가 FP_AddWide
    // 50-bit 창의 bit 3 이상에 앉아 창 밖 손실이 없고, 정렬폭 <= 47 +
    // carry 1 = 48 이라 정규화 48b 결과가 정확합을 그대로 담는다 (실측
    // 정렬합 폭 max 48 == 강제 경계; 초과는 아래 fd_mrg_inexact 가 loud
    // fault 로 잡는다). 따라서 split 은 **고정 슬라이스**:
    //   hi = wide_sig[47:24] @ xe = wide_exp        (이미 정규화됨)
    //   lo = wide_sig[23:0]  @ e  = wide_exp-47     (정규화 필요)
    // lo == 0 은 golden 의 "bl <= 24 -> 단일 component" 분기와 같은 사건이다.
    wire [23:0] fd_lo_raw = aw_wsig[23:0];
    wire        fd_lz16 = ~|fd_lo_raw[23:8];
    wire [23:0] fd_ln0  = fd_lz16 ? {fd_lo_raw[7:0], 16'b0} : fd_lo_raw;
    wire        fd_lz8  = ~|fd_ln0[23:16];
    wire [23:0] fd_ln1  = fd_lz8  ? {fd_ln0[15:0], 8'b0} : fd_ln0;
    wire        fd_lz4  = ~|fd_ln1[23:20];
    wire [23:0] fd_ln2  = fd_lz4  ? {fd_ln1[19:0], 4'b0} : fd_ln1;
    wire        fd_lz2  = ~|fd_ln2[23:22];
    wire [23:0] fd_ln3  = fd_lz2  ? {fd_ln2[21:0], 2'b0} : fd_ln2;
    wire        fd_lz1  = ~fd_ln3[23];
    wire [23:0] fd_lomag = fd_lz1 ? {fd_ln3[22:0], 1'b0} : fd_ln3;
    wire [4:0]  fd_lolz  = {fd_lz16, fd_lz8, fd_lz4, fd_lz2, fd_lz1};
    wire signed [11:0] fd_loxe = aw_wexp - 12'sd24 - $signed({7'b0, fd_lolz});
    wire        fd_lonz  = |fd_lo_raw;
    wire [36:0] fd_hi_w  = {aw_wsign, aw_wexp, aw_wsig[47:24]};
    wire [36:0] fd_lo_w  = {aw_wsign, fd_loxe, fd_lomag};

    // ---- pass 의 무반올림 여부 (golden 의 "실질 jam" 판정과 동치) ----
    // golden fold_descending 은 RTO 산출과 pre-RTO exact 합을 직접 비교해
    // **첫 실질 jam 위치 자체**를 잡는다. RTL 은 exact 합을 들고 있지
    // 않으므로 같은 사건을 기하로 판정한다:
    //   pass 가 inexact  <=>  exact 합의 최저 set bit < 결과 48-bit 창 바닥
    //                          (창 바닥 = wide_exp - 47)
    // 비겹침 열에서 exact 합의 최저 set bit == **들어온 피가산 component 의
    // 최저 set bit** 다 (acc 의 bit 구간이 그보다 위에 있어 하단 상쇄가
    // 구조적으로 불가능 — top(c_k) <= e_{k+1} == acc 의 최저 bit). jam
    // 이후에도 남은 component 는 전부 grid p 아래라 같은 등식이 유지된다.
    // ⇒ 이 판정은 golden 과 **같은 pass** 에서 참이 된다 (과·미검출 없음).
    wire signed [12:0] fd_wtop = $signed({aw_wexp[11], aw_wexp});
    wire signed [12:0] fd_wlo  = fd_wtop - 13'sd47;   // 48-bit 창 바닥
    wire fd_fold_inexact = fd_ea < fd_wlo;            // STEP F pass 가 jam 했나
    // STEP T 의 vacuous-RTO 전제 (golden 의 `bl > Q48` loud fault 와 같은
    // 사건): 겹침 merge 는 구조적으로 무반올림이어야 한다. 두 피연산자
    // 중 낮은 쪽 최저 bit 이 창 밖이면 그 전제가 붕괴한 것이다.
    wire signed [12:0] fd_mlo = (fd_ea < fd_eb) ? fd_ea : fd_eb;
    wire fd_mrg_inexact = fd_mlo < fd_wlo;

    // freeze (§27.7a.2a 졸업 지표): 첫 실질 jam 이후 acc 는 불변이어야 한다.
    // 검사 창은 **jam 직후 첫 pass 부터** 열려 있어야 한다 — "acc 불변인
    // pass 를 먼저 본 뒤에 감시 시작" 은 jam 직후 첫 pass 의 붕괴를 통째로
    // 놓치는 단방향 약화다 (acc 불변 => jam 이후 는 참이지만 그 역이
    // 필요하다). 그래서 위 fd_fold_inexact 가 jam 을 직접 앵커하고,
    // fd_acc_same 는 그 특수형이라 OR 로 함께 둔다 (이중 안전망).
    wire fd_acc_same = (aw_wsign == fd_accs) && (aw_wexp == fd_acce)
                    && (aw_wsig == fd_accm);

    wire        fd_fin = (fd_st == FDS_DONE);
    wire [31:0] fd_res = (fd_rsel == FDR_QNAN) ? QNAN
                       : (fd_rsel == FDR_ZERO) ? 32'h0000_0000
                                               : aw_final;

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
            OPS_FDOTCR: spec_hit = 1'b0;               // 3a-C3 §27.7a: lane
                                                       // special 은 32 lane
                                                       // 전수 검사라 CLASSIFY
                                                       // 1 cycle 에 못 끝낸다
                                                       // — 수납 (FDS_LOAD)
                                                       // 중 누적하고, 하나라도
                                                       // 있으면 EFT 미진입으로
                                                       // qNaN+sticky 종료한다
                                                       // (FP_AddWide 의 "특수값
                                                       // 미진입" 전제는 유지)
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
            // 3a-C3 §27.7a.1 — FDOT32_CR 의 dtype 은 wave dtype 을 직접
            // 명명한다: 0x2 f16 / 0x3 bf16 **정확히 2행**, 그 외 전 조합은
            // ILLEGAL (restrictive-first) → OPS_BAD 로 남아 qNaN 을 낸다.
            OPC_FDOTCR: if (dtype_in[3:1] == 3'b001)
                op_sel_in = OPS_FDOTCR;
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

                // 3a-C3 §27.7a — OPS_FDOTCR 은 아래 op-gated sub-sequencer 가
                // 소유한다: generic step 기계는 step 0 에 주차하고 종료는
                // fd_fin 으로만 취한다 (위 FEXP2 bypass 와 같은 last-write-wins
                // 관용구). 기존 op 의 행은 하나도 건드리지 않는다.
                if (op_sel == OPS_FDOTCR) begin
                    fp_step  <= 6'd0;
                    fp_first <= 1'b0;
                    fp_wait  <= 2'd0;
                    fp_state <= fd_fin ? FP_FINISH : FP_EXEC;
                    if (fd_fin) res_reg <= fd_res;
                end
            end

            FP_FINISH: fp_state <= FP_IDLE;

            default: fp_state <= FP_IDLE;
        endcase
    end

    // =========================================================================
    // 3a-C3 §27.7a — OPS_FDOTCR sub-sequencer (op-gated 전량)
    //
    // 전 분기가 fd_launch / fd_run 안에 있으므로 다른 op 의 launch 는 이
    // 블록의 어떤 레지스터도 쓰지 않는다 (§27.7a.4 의 "신규 로직은 op-gated
    // 영역에 격리" — capture-mux 미묘 회귀 = shipped op 의 silent wrong-data
    // 선례 §23.10.10(h) 항 4 에 대한 구조적 격리).
    //
    // OPERAND INGRESS (C3 결정 — C4 확인 의무): 1,024b wave 는 **fragment
    // 당 1 cycle, 16 cycle** 로 {b_in, a_in} 위에 실려 들어온다 (frag f =
    // {b_in, a_in}, f = 0..15 — §27.7a.1 의 16-fragment 구조 그대로). launch
    // edge 가 frag 0 을 먹고 이후 15 cycle 이 나머지를 먹는다. §27.7a.1 문언
    // ("launch cycle 에 MU-local capture") 대비 차이는 **수납 창이 1 cycle 이
    // 아니라 16 cycle** 이라는 점 하나이며, 그 문언의 근거 (EHDecode 가
    // cluster-shared 라 1,167 cycle 급 프로그램 (실측; 초안 추정 ~5k) 동안 버퍼를 못 잡는다) 는 그대로
    // 지켜진다 — 버퍼는 여기 MU 안에 있다. 이 형을 고른 이유는 1,024b 병렬
    // 포트를 FP_StepSeq 경계에 새로 뚫으면 PE_Core 의 기존 instantiation 이
    // 미결선이 되어 (PINMISSING) Cluster/PE/Pod/Top_Core/ISA_Decoder 5개
    // 스위트가 **빌드 자체가 깨지고**, 그 결선은 3a-C4 몫이기 때문이다.
    // 포트 목록을 byte-불변으로 두면 C4 가 (a) 이 스트리밍 수납을 그대로
    // 쓰거나 (b) 1,024b 포트로 바꾸거나를 자유롭게 고를 수 있다 — 프로그램
    // 로직은 어느 쪽이든 동일하다 (capture 레지스터가 같은 자리에 있다).
    //
    // [3a-C4 결정, §27.7a.2c amendment-13] **(a) 채택 / (b) 기각.** 이
    // 스트리밍 수납은 그대로 남는다. PE_Core 가 `fd_ing_q` (MU-local
    // 1,024b) 에서 fragment 를 1 cycle 에 하나씩 꺼내 {b_in, a_in} 에
    // 실어 준다 (PE_Core 의 "0x7A ingress 드라이버" 블록). 기각 사유:
    // (1) 1,024b 포트는 gate_top 래퍼 I/O flop 을 147 → 1,171 로 만들어
    // GATE V20-4 anchor 의 유닛 몫 귀속을 파괴한다, (2) fd_asr/fd_bsr 가
    // 사라지면 fd_spfr 의 per-cycle special 누적 구조가 바뀌어 값 축
    // 재증명이 실제로 필요해진다, (3) 얻는 것은 수납 창 16 → 1 cycle
    // 뿐인데 cycle 상한 10,000 대비 실측 worst 는 1,167 이다.
    //
    // sticky (§27.7a.1 (iii)) 와 loud fault 는 fd_spec / fd_fault 레지스터에
    // 산다. 두 sticky 의 **포트 노출**은 §27.7a.4 가 3a-C4 로 배정한
    // 항목이고 **본 커밋에서 착지했다** — 모듈 포트 `fd_special_sticky` /
    // `fd_unit_fault` (분리 유지, §35.3). 결과값 자체는 두 경우 모두
    // canonical qNaN 이라 무모호 marker 로 이미 loud 지만, 그것만으로는
    // §27.7a.3 검사 (i) 이 두 사건을 구분하지 못한다
    // (main drain 은 NaN 을 절대 산출하지 않는다, §27.7a.1).
    // =========================================================================
    wire fd_launch = (fp_state == FP_IDLE) && start
                  && (op_sel_in == OPS_FDOTCR);
    wire fd_run    = (fp_state != FP_IDLE) && (op_sel == OPS_FDOTCR);
    wire fd_dtbf   = fd_launch ? (dtype_in == 4'd3) : fd_bf16;
    // 수납 중 fragment 의 4 lane special 검사 (NaN/Inf/sNaN — exp field all-1)
    wire fd_sp0 = fd_dtbf ? (a_in[14:7]  == 8'hFF) : (a_in[14:10]  == 5'h1F);
    wire fd_sp1 = fd_dtbf ? (a_in[30:23] == 8'hFF) : (a_in[30:26]  == 5'h1F);
    wire fd_sp2 = fd_dtbf ? (b_in[14:7]  == 8'hFF) : (b_in[14:10]  == 5'h1F);
    wire fd_sp3 = fd_dtbf ? (b_in[30:23] == 8'hFF) : (b_in[30:26]  == 5'h1F);
    wire fd_spfr = fd_sp0 | fd_sp1 | fd_sp2 | fd_sp3;

    always @(posedge clk) begin
        if (fd_launch) begin
            // launch cycle: fragment 0 수납 + 상태 초기화
            fd_asr    <= {b_in, a_in, fd_asr[511:64]};
            fd_bf16   <= (dtype_in == 4'd3);
            fd_spec   <= fd_spfr;
            fd_fault  <= 1'b0;
            fd_jam    <= 1'b0;
            fd_cnt    <= 6'd1;
            fd_n      <= 6'd0;
            fd_w      <= 6'd0;
            fd_rsel   <= FDR_AW;
            fd_st     <= FDS_LOAD;
        end else if (fd_run) begin
            case (fd_st)
                // ---- 수납: frag 1..15 (frag 0 은 launch edge 가 먹었다) ----
                FDS_LOAD: begin
                    if (fd_cnt[3]) fd_bsr <= {b_in, a_in, fd_bsr[511:64]};
                    else           fd_asr <= {b_in, a_in, fd_asr[511:64]};
                    fd_spec <= fd_spec | fd_spfr;
                    if (fd_cnt == 6'd15) begin
                        fd_cnt <= 6'd0;
                        if (fd_spec | fd_spfr) begin
                            // §27.7a.1 (iii): EFT 미진입 — qNaN + sticky
                            fd_rsel <= FDR_QNAN;
                            fd_st   <= FDS_DONE;
                        end else
                            fd_st <= FDS_PRIME;
                    end else
                        fd_cnt <= fd_cnt + 6'd1;
                end

                // ---- 첫 fragment 를 lane 창으로 (큰 레지스터는 64b 전진) ----
                FDS_PRIME: begin
                    fd_fa  <= fd_asr[63:0];
                    fd_fb  <= fd_bsr[63:0];
                    fd_asr <= {64'b0, fd_asr[511:64]};
                    fd_bsr <= {64'b0, fd_bsr[511:64]};
                    fd_st  <= FDS_LANE;
                end

                // ---- STEP M: lane classify + 곱 launch ----
                FDS_LANE: begin
                    fd_pe <= $signed(fd_qa[11:0]) + $signed(fd_qb[11:0]);
                    fd_ps <= fd_qa[23] ^ fd_qb[23];
                    if (fd_skip) begin
                        // zero 기여 lane — golden 의 prods 제외 규칙 그대로
                        // (열에 아무것도 넣지 않는다)
                        if (fd_cnt[1:0] == 2'b11) begin
                            fd_fa  <= fd_asr[63:0];
                            fd_fb  <= fd_bsr[63:0];
                            fd_asr <= {64'b0, fd_asr[511:64]};
                            fd_bsr <= {64'b0, fd_bsr[511:64]};
                        end else begin
                            fd_fa <= {16'b0, fd_fa[63:16]};
                            fd_fb <= {16'b0, fd_fb[63:16]};
                        end
                        fd_st <= FDS_NEXT;
                    end else
                        fd_st <= FDS_MUL1;
                end

                FDS_MUL1: fd_st <= FDS_PROD;

                FDS_PROD: begin
                    fd_ins <= {fd_ps, fd_pxe, fd_pmag};
                    if (fd_cnt[1:0] == 2'b11) begin
                        fd_fa  <= fd_asr[63:0];
                        fd_fb  <= fd_bsr[63:0];
                        fd_asr <= {64'b0, fd_asr[511:64]};
                        fd_bsr <= {64'b0, fd_bsr[511:64]};
                    end else begin
                        fd_fa <= {16'b0, fd_fa[63:16]};
                        fd_fb <= {16'b0, fd_fb[63:16]};
                    end
                    if (fd_n >= FD_TOP) begin      // 배열 guard — loud fault
                        fd_fault <= 1'b1;
                        fd_rsel  <= FDR_QNAN;
                        fd_st    <= FDS_DONE;
                    end else begin
                        fd_j  <= fd_n;
                        fd_st <= FDS_INS;
                    end
                end

                // ---- STEP I (a): (e, top) 오름차순 정렬 삽입 ----
                // 하강 스캔 = 비교와 이동을 한 cycle 에 겹친 삽입정렬 내루프.
                // key <= key(q) 인 원소 전부의 **뒤**에 놓는다 (golden insort).
                FDS_INS: begin
                    if ((fd_j != 6'd0) && fd_ins_gt) begin
                        fd_xp[fd_j] <= fd_ca;      // fd_ra == fd_jm1
                        fd_j <= fd_jm1;
                    end else begin
                        fd_xp[fd_j] <= fd_ins;
                        fd_n  <= fd_n + 6'd1;
                        fd_w  <= 6'd0;             // walk 은 항상 바닥부터
                        fd_st <= FDS_WALK;
                    end
                end

                // ---- STEP I (b): "최저 2개 순서 merge" walk ----
                FDS_WALK: begin
                    if (fd_w1 >= fd_n)
                        fd_st <= FDS_NEXT;         // 대기열 <= 1 — 열 확정
                    else if (fd_disj)
                        fd_w <= fd_w1;             // a 는 남은 전부의 아래
                    else begin
                        fd_wait <= 2'd3;           // 겹침 — 1 AddWide pass
                        fd_st   <= FDS_MRGW;
                    end
                end

                // ---- STEP T: exact merge (latency 3) + 24|24 split ----
                FDS_MRGW: begin
                    if (fd_wait != 2'd0) fd_wait <= fd_wait - 2'd1;
                    else if (fd_mrg_inexact) begin
                        // vacuous-RTO 전제 붕괴 = exact-합 보존 invariant 의
                        // 붕괴 (golden 은 같은 사건에 FdotFault 를 던진다).
                        // 정상 열에서는 도달 불가 (정렬폭 <= 48 이 구조적)
                        // 이지만 "도달 불가" 주장으로 검사를 대체하지 않는다.
                        fd_fault <= 1'b1;
                        fd_rsel  <= FDR_QNAN;
                        fd_st    <= FDS_DONE;
                    end else begin
                        if (aw_wzero) begin        // 정확 상쇄 — 둘 다 소멸
                            fd_hi_done <= 1'b1;
                            fd_dst     <= fd_w;
                        end else begin
                            fd_hi      <= fd_hi_w;
                            fd_hi_done <= 1'b0;
                            if (fd_lonz) begin
                                // lo 는 남은 대기열 전부의 아래이므로 바닥
                                // 자리가 확정된다 (재삽입 스캔 불요):
                                // xe_lo <= max(xe_a,xe_b) - 23 이고 열이
                                // (e, top) 오름차순이라 e_lo <= xe_lo <=
                                // e_c, 동률이면 xe_lo <= xe_c — 어느 쪽이든
                                // key(lo) <= key(c) 다.
                                fd_xp[fd_w] <= fd_lo_w;
                                fd_dst      <= fd_w1;
                            end else
                                fd_dst      <= fd_w;
                        end
                        fd_j  <= fd_w + 6'd2;
                        fd_st <= FDS_REINS;
                    end
                end

                // ---- STEP T (b): hi 재삽입 + 열 압축 ----
                FDS_REINS: begin
                    if (!fd_hi_done && (fd_j < fd_n) && fd_hi_ge) begin
                        fd_xp[fd_dst] <= fd_ca;    // fd_ra == fd_j
                        fd_dst <= fd_dst + 6'd1;
                        fd_j   <= fd_j + 6'd1;
                    end else if (!fd_hi_done) begin
                        fd_xp[fd_dst] <= fd_hi;
                        fd_dst     <= fd_dst + 6'd1;
                        fd_hi_done <= 1'b1;
                        // lo 가 있었으면 여기서 구멍이 정확히 메워진다
                        if ((fd_dst + 6'd1) == fd_j) fd_st <= FDS_WALK;
                    end else if (fd_j < fd_n) begin
                        fd_xp[fd_dst] <= fd_ca;
                        fd_dst <= fd_dst + 6'd1;
                        fd_j   <= fd_j + 6'd1;
                    end else begin
                        fd_n  <= fd_dst;
                        fd_st <= FDS_WALK;
                    end
                end

                // ---- lane 전진 / 3종 assert ① 용량 (초과 = loud fault) ----
                FDS_NEXT: begin
                    if (fd_n > FD_CAP) begin
                        fd_fault <= 1'b1;
                        fd_rsel  <= FDR_QNAN;
                        fd_st    <= FDS_DONE;
                    end else if (fd_cnt != 6'd31) begin
                        fd_cnt <= fd_cnt + 6'd1;
                        fd_st  <= FDS_LANE;
                    end else begin
                        // STEP F 진입: acc = canonical zero (FP_AddWide 의
                        // zero-operand 규약 그대로), 최상위 component 부터
                        fd_accs   <= 1'b0;
                        fd_acce   <= -12'sd1024;
                        fd_accm   <= 48'b0;
                        fd_jam    <= 1'b0;
                        if (fd_n == 6'd0) begin
                            fd_rsel <= FDR_ZERO;   // 전 lane zero 기여 -> +0
                            fd_st   <= FDS_DONE;
                        end else begin
                            fd_j    <= fd_n - 6'd1;
                            fd_wait <= 2'd3;
                            fd_st   <= FDS_FOLDW;
                        end
                    end
                end

                // ---- STEP F: descending RTO-48 fold (§27.7a.2a amendment-1) ----
                FDS_FOLDW: begin
                    if (fd_wait != 2'd0) fd_wait <= fd_wait - 2'd1;
                    else begin
                        fd_accs <= aw_wsign;
                        fd_acce <= aw_wexp;
                        fd_accm <= aw_wsig;
                        // jam 앵커 (golden 의 "첫 실질 jam" 그대로) — 이
                        // pass 가 RTO 로 정보를 버렸으면 다음 pass 부터
                        // freeze 감시가 열린다. fd_acc_same 는 그 특수형.
                        if (fd_fold_inexact || fd_acc_same) fd_jam <= 1'b1;
                        if (fd_jam && !fd_acc_same) begin
                            // freeze 위반 = 정리 (4) 붕괴 — 절대 silent 금지
                            fd_fault <= 1'b1;
                            fd_rsel  <= FDR_QNAN;
                            fd_st    <= FDS_DONE;
                        end else if (fd_j == 6'd0) begin
                            if (aw_wzero) begin
                                fd_rsel <= FDR_ZERO;
                                fd_st   <= FDS_DONE;
                            end else begin
                                fd_wait <= 2'd3;
                                fd_st   <= FDS_PACKW;
                            end
                        end else begin
                            fd_j    <= fd_j - 6'd1;
                            fd_wait <= 2'd3;
                        end
                    end
                end

                // ---- STEP P: PACK_FINAL 1회 ----
                FDS_PACKW: begin
                    if (fd_wait != 2'd0) fd_wait <= fd_wait - 2'd1;
                    else begin
                        fd_rsel <= FDR_AW;
                        fd_st   <= FDS_DONE;
                    end
                end

                FDS_DONE: ;                        // 결과는 fd_res 로 확정
                default: fd_st <= FDS_DONE;
            endcase
        end
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
    // v1.8.0e 3a-C4 §35.3 — the two FDOT32_CR sticky ports. Level, not
    // pulse: valid from the fragment-0 receiving edge until the next
    // `fd_launch`, so they are stable across the `done` beat that the
    // parent captures the result on. `fd_unit_fault` had NO reader before
    // this commit and was pruned by synthesis ([Synth 8-6014] Unused
    // sequential element fd_fault_reg was removed) — i.e. the four loud
    // faults of §27.7a.2b amendment-11 did not exist on silicon at all.
    assign fd_special_sticky = fd_spec;
    assign fd_unit_fault     = fd_fault;

endmodule

/* verilator lint_on PROCASSINIT */
/* verilator lint_on UNUSEDPARAM */
/* verilator lint_on UNUSEDSIGNAL */
