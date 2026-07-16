// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

`include "attributes.vh"

// =============================================================================
// FP_StepSeq.v — v1.8.0c MU-hosted fp32 step-sequencer unit (spec §23.10,
// synth Gate 3 of §23.10.7).
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
//   opcode_in  0x74 FSCALAR / 0x75 FRSQRT32 / 0x76 FEXP2_32.
//   subop_in   FSCALAR sub-op (imm16[7:4], generated single-source table
//              in include/generated/isa_subop_codes.vh); ignored by the
//              unary ops.
//
//   DON'T-CARE INPUTS: PE_Core's decode guards ensure an unknown opcode
//   or an FSCALAR sub-op > 0x4 is never presented. If presented anyway,
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

    // ---- opcodes (spec §23.10 block 0x70) ----
    localparam [7:0] OPC_FSCALAR = 8'h74;
    localparam [7:0] OPC_FRSQRT  = 8'h75;
    localparam [7:0] OPC_FEXP2   = 8'h76;

    // ---- FSM ----
    localparam [1:0] FP_IDLE     = 2'd0;
    localparam [1:0] FP_CLASSIFY = 2'd1;
    localparam [1:0] FP_EXEC     = 2'd2;
    localparam [1:0] FP_FINISH   = 2'd3;

    // step kind == cycle count - 1 == fp_wait load value
    localparam [1:0] K_INT = 2'd0;
    localparam [1:0] K_MUL = 2'd1;
    localparam [1:0] K_ADD = 2'd2;

    // internal op selector (FS_MUL/FS_FMA share one step table)
    localparam [2:0] OPS_FSADD = 3'd0;   // FS_ADD / FS_SUB (B sign-flipped)
    localparam [2:0] OPS_FSMUL = 3'd1;
    localparam [2:0] OPS_FSFMA = 3'd2;
    localparam [2:0] OPS_FSDIV = 3'd3;
    localparam [2:0] OPS_RSQRT = 3'd4;
    localparam [2:0] OPS_FEXP2 = 3'd5;
    localparam [2:0] OPS_BAD   = 3'd6;   // don't-care inputs (see header)

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
    reg [2:0]  op_sel;

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
    reg [2:0] info_cur, info_nxt, info_ent;   // {last, kind}

    function [2:0] f_step_info;
        input [2:0] sel;
        input [5:0] st;
        begin
            f_step_info = {1'b1, K_INT};      // default: terminate
            case (sel)
                OPS_FSADD: f_step_info = {1'b1, K_ADD};
                OPS_FSMUL,
                OPS_FSFMA: f_step_info = (st == 6'd0) ? {1'b0, K_INT}
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
                OPS_FSMUL, OPS_FSFMA: if (fp_step == 6'd1) begin
                    aw_mode  = PACK_FINAL;
                    aw_psign = sa ^ sb;
                    aw_pexp  = ex_ab1;
                    aw_psig  = fp_first ? p[47:0] : t_prod;
                    if (op_sel == OPS_FSFMA && !c_zero) begin
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
            OPS_FSFMA: begin                           // F2/F3/F5 + NaN rule
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

    reg [2:0] op_sel_in;
    always @* begin
        op_sel_in = OPS_BAD;
        case (opcode_in)
            OPC_FRSQRT:  op_sel_in = OPS_RSQRT;
            OPC_FEXP2:   op_sel_in = OPS_FEXP2;
            OPC_FSCALAR: case (subop_in)
                FS_ADD, FS_SUB: op_sel_in = OPS_FSADD;
                FS_MUL:         op_sel_in = OPS_FSMUL;
                FS_FMA:         op_sel_in = OPS_FSFMA;
                FS_DIV:         op_sel_in = OPS_FSDIV;
                default:        op_sel_in = OPS_BAD;
            endcase
            default: ;
        endcase
    end

    // -------------------------------------------------------------------------
    // the sequencer
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        case (fp_state)
            FP_IDLE: if (start) begin
                a_q      <= daz_a;
                b_q      <= daz_b ^ {is_sub_in, 31'b0};
                c_q      <= daz_c;
                op_sel   <= op_sel_in;
                fp_state <= FP_CLASSIFY;
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
                             || (op_sel == OPS_FSFMA) || (op_sel == OPS_FSDIV);
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
                        OPS_FSMUL, OPS_FSFMA:
                            if (fp_step == 6'd1) t_prod <= p[47:0];
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
