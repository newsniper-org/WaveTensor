// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

`include "attributes.vh"

// =============================================================================
// PE_Core.v — Stage-2 ALU dispatch for a single PE.
//
// Takes the registered `dec_*` bus produced by EHDecode and a per-PE
// `pe_active` gate from the Cluster routing layer, and runs the case-based
// dispatch + ALU helpers + multi-cycle MUL pipeline + output register stage
// that used to live in the back half of ISA_Decoder.v.
//
// Pairs with EHDecode.v under the (j) Cluster-shared-frontend mitigation:
// one EHDecode per Cluster broadcasts dec_* to N L-PE_Cores and 1
// MATMUL_UNIT-flavored PE_Core, eliminating the per-PE chain-walk
// duplication (~5 K LUT/PE × N saved).
//
// Parameter semantics:
//   MUL_OPS_SUPPORTED      — when 0, MUL/MATMUL/EINSUM/EUCLID_NORM (plus
//                            the v1.8.0b MU-hosted 0x71/0x72 and the
//                            v1.8.0c fp32 scalar ops 0x74/0x75/0x76)
//                            short-circuit to lower_required and synthesis
//                            DCEs the matmul/einsum-mul helpers + 64-bit
//                            mul pipeline + MAC trees + FP_StepSeq.
//   DIV_OPS_SUPPORTED      — when 0, DIV/MOD/DIVMOD short-circuit to
//                            lower_required so Vivado DCEs the 64-bit
//                            fabric divider/modulo (the LUT hog: each
//                            64-bit div/mod costs ~3-5 K LUT on its own).
//   NON_MUL_OPS_SUPPORTED  — when 0, every non-mul opcode short-circuits
//                            to lower_required so Vivado DCEs the shape /
//                            scalar-ALU helpers (M-UNIT stripping).
// =============================================================================

/* verilator lint_off UNUSEDSIGNAL */

module PE_Core #(
    parameter ADDR_WIDTH            = 64,
    parameter TAG_WIDTH             = 80,
    parameter MUL_OPS_SUPPORTED     = 1,
    parameter DIV_OPS_SUPPORTED     = 1,
    parameter NON_MUL_OPS_SUPPORTED = 1,
    // v1.5.2b §19 — wide input path (fragment-reassembled payload).
    // Matched to Cluster's fragment buffer FRAG_MAX=16.
    parameter FRAG_MAX              = 16,
    parameter WIDE_W                = FRAG_MAX * ADDR_WIDTH
) (
    input                        clk,
    input                        rst,
    input                        pe_active,    // gate from Cluster

    // ---- Stage-1 dec_* bus (from EHDecode) ----
    input                        dec_valid,
    input  [7:0]                 dec_opcode,
    input                        dec_decode_error,
    input                        dec_tag_match,
    input  [TAG_WIDTH-1:0]       dec_forwarded_tag,
    input  [TAG_WIDTH-1:0]       dec_wave_advanced_tag,
    input  [ADDR_WIDTH-1:0]      dec_input_payload,
    input  [ADDR_WIDTH-1:0]      dec_input_payload_b,
    input                        dec_input_payload_b_valid,
    input  [ADDR_WIDTH-1:0]      dec_eff_b_value,
    input  [15:0]                dec_eff_imm16,
    input  [7:0]                 dec_eff_dim_sizes,
    input  [3:0]                 dec_eff_opref_kind,
    input  [31:0]                dec_eff_mem_offset,
    input  [47:0]                dec_eff_subscript,
    // v1.5.3 §20 — second SUBSCRIPT EH body (axes 4-7 for {A,B,O}).
    // For v1.0..v1.2 signatures MUST be 48'h0 (guarded at dispatch);
    // for v1.5.3+ wide-consumer primitives (SIG_BMM_3) it carries the
    // hi-half of the multi-SUBSCRIPT chain.
    input  [47:0]                dec_eff_subscript_hi,
    // v1.5.3 §20 — second IMM64 EH body slot (upper 64 bits of the
    // v1.4 multi-IMM64 chain). RESERVED / currently UNUSED inside
    // PE_Core: no v1.5.3 primitive consumes it. SIG_BMM_3 CANNOT use
    // this chain because EINSUM (opcode 0x32) is `forbid_imm_any` at
    // EHDecode legality (see dispatch note at ~L1107); it sources its
    // 128-bit B operand from `dec_input_payload_wide[255:128]` via
    // the v1.5.1/1.5.2 fragment reassembly path instead. Wire is kept
    // live in the port list + Cluster/ISA_Decoder routing so a future
    // NON-EINSUM wide-consumer primitive that opts back into IMM64
    // dual-slot needs no re-wiring surgery.
    /* verilator lint_off UNUSEDSIGNAL */
    input  [63:0]                dec_eff_imm64_hi,
    /* verilator lint_on UNUSEDSIGNAL */
    input  [7:0]                 dec_eff_output_port_id,
    input  [7:0]                 dec_eff_precision,
    input  [31:0]                dec_wave_number,
    input  [15:0]                dec_thread_id,
    // v1.5.2b §19 — reassembled wide payload (from EHDecode wide latch).
    // Legacy v1.0..v1.5.2 primitives ignore this signal; wide-consumer
    // primitives (v1.5.3+, SIG_BMM_3 등) will read alongside
    // dec_input_payload. Verilator lint suppressed since legacy dispatch
    // has no reference.
    /* verilator lint_off UNUSEDSIGNAL */
    input  [WIDE_W-1:0]          dec_input_payload_wide,
    input                        dec_input_payload_wide_valid,
    /* verilator lint_on UNUSEDSIGNAL */

    // ---- Outputs ----
    output reg [ADDR_WIDTH-1:0]  output_payload,
    output reg [TAG_WIDTH-1:0]   output_tag,
    output reg                   output_valid,
    output reg [7:0]             opcode_out,
    // v1.6.6 §22.14 — pe_ready back-pressure signal (combinational).
    // High when PE_Core can accept a new dispatch. Same compound expression
    // as the internal drain gate (§20.6, §22.13.1) but exposed as an
    // observable output. External (Cluster/upstream fabric) can either
    // gate ext_valid on this or observe only (MVP: observe-only, no
    // ext_valid gating change).
    output                       pe_ready,
    // v1.5 §17 — NoC wave-token fragment header (IPv6-style Fragment
    // Extension Header analog). Layout:
    //   [7:4] = fragment_index (this fragment's position, 0..15)
    //   [3:0] = total_fragments_minus_1 (0..15, meaning 1..16 fragments)
    //   0x00  = legacy single-fragment token (all v1.0..1.4 primitives).
    // Downstream fabric collects fragments sharing tag until frag_index ==
    // total-1 to reassemble the logical wide payload (up to 16×64 = 1024
    // bits). See wt64v1_spec.md §17 and eh_encoding_expansion.md §12.
    output reg [7:0]             output_frag_hdr,
    output reg                   memory_req,
    output reg [ADDR_WIDTH-1:0]  mem_addr,
    output reg                   error_flag,
    output reg                   lower_required
);

    // -------------------------------------------------------------------------
    // EINSUM signature constants — must mirror ISA_Decoder.v
    // -------------------------------------------------------------------------
    localparam [47:0] SIG_SUM_I       = {16'h0001, 16'h0000, 16'h0000};
    localparam [47:0] SIG_TRACE_II    = {16'h0011, 16'h0000, 16'h0000};
    localparam [47:0] SIG_TRANSPOSE   = {16'h0021, 16'h0000, 16'h0012};
    localparam [47:0] SIG_MATMUL      = {16'h0021, 16'h0032, 16'h0031};
    localparam [47:0] SIG_HADAMARD    = {16'h0021, 16'h0021, 16'h0021};
    localparam [47:0] SIG_OUTER       = {16'h0001, 16'h0002, 16'h0021};
    localparam [47:0] SIG_PARTIAL_IJK = {16'h0321, 16'h0000, 16'h0021};
    localparam [47:0] SIG_DIAGONAL    = {16'h0011, 16'h0000, 16'h0001};
    localparam [47:0] SIG_DOT     = {16'h0001, 16'h0001, 16'h0000};
    localparam [47:0] SIG_MAT_VEC = {16'h0021, 16'h0002, 16'h0001};
    // v1.1 amendment (2026-07-14): EINSUM completeness.
    // SIG_BMM: 'bik,bkj->bij' — batched matmul. Labels canonicalized in A→B→O
    //   first-appearance order: b=1, i=2, k=3 (from A); j=4 (new in B); O uses
    //   1,2,4. Packed: A=b,i,k → 0x0321; B=b,k,j → 0x0431; O=b,i,j → 0x0421.
    // SIG_TRACE_IIJ: 'iij->j' — 3D trace w/ kept axis. Labels: i=1, j=2.
    //   Packed: A=i,i,j → 0x0211; B=(empty) → 0x0000; O=j → 0x0002.
    // Both operate on int8 packed 8-lane payload (WT64v1 v1.1 §14.3 constraint):
    // int16 precision inputs to these signatures produce lower_required.
    localparam [47:0] SIG_BMM       = {16'h0321, 16'h0431, 16'h0421};
    localparam [47:0] SIG_TRACE_IIJ = {16'h0211, 16'h0000, 16'h0002};
    // v1.2 amendment (2026-07-14): int4 packed 16-lane 4D EINSUM.
    // 64-bit payload = 16 signed int4 nibbles enables 4D 2×2×2×2 tensors.
    // SIG_BMM_2: 'abij,abjk->abik' — 2-batch matmul (4 independent 2×2).
    //   Canonicalized: a=1, b=2, i=3, j=4 (A→B), k=5 (new in B).
    //   Packed: A=a,b,i,j → 0x4321; B=a,b,j,k → 0x5421; O=a,b,i,k → 0x5321.
    // SIG_TRACE_IIJK: 'iijk->jk' — 3D trace w/ 2 kept axes.
    //   Canonicalized: i=1, j=2, k=3.
    //   Packed: A=i,i,j,k → 0x3211; B=(empty) → 0x0000; O=j,k → 0x0032.
    // Both require dim_sizes = 0x55 (4D 2×2×2×2); otherwise lower_required.
    localparam [47:0] SIG_BMM_2       = {16'h4321, 16'h5421, 16'h5321};
    localparam [47:0] SIG_TRACE_IIJK  = {16'h3211, 16'h0000, 16'h0032};
    // v1.5.3 §20 — SIG_BMM_3: 'abcij,abcjk->abcik' (3-batch matmul at int4).
    // Labels canonicalized in A→B→O first-appearance: a=1, b=2, c=3, i=4, j=5, k=6.
    // Multi-SUBSCRIPT (v1.3 §16.5) split: lo half = axes 0-3, hi half = axes 4-7.
    //   A = [a,b,c,i,j] → lo=0x4321, hi=0x0005
    //   B = [a,b,c,j,k] → lo=0x5321, hi=0x0006
    //   O = [a,b,c,i,k] → lo=0x4321, hi=0x0006
    // Verilog concat order {A_pack, B_pack, O_pack} with A at MSB (matches SIG_BMM_2).
    // 5D 2×2×2×2×2 = 32 elements × int4 = 128-bit A/B/O.
    // Signature-only dispatch (dim_sizes ignored) — assembler validates shape.
    localparam [47:0] SIG_BMM_3_LO    = {16'h4321, 16'h5321, 16'h4321};
    localparam [47:0] SIG_BMM_3_HI    = {16'h0005, 16'h0006, 16'h0006};
    // v1.5.5 §21 — SIG_TRACE_IIJKL: 'iijkl->jkl' (5D trace + 3 kept axes at int4).
    // Labels canonicalized: i=1, j=2, k=3, l=4. B is empty.
    // Multi-SUBSCRIPT split:
    //   A = [i,i,j,k,l] → lo=0x3211 (axes 0-3), hi=0x0004 (axis 4)
    //   B = []          → lo=0x0000, hi=0x0000
    //   O = [j,k,l]     → lo=0x0432 (3 axes fit in lo), hi=0x0000
    // Input via wide[127:0] (2-fragment wave, A only — no B). Output 32-bit
    // reduces to 8 int4 nibbles → single-fragment (no FSM engagement).
    // Output tag dim_sizes = 0x15 (3D 2×2×2 result).
    localparam [47:0] SIG_TRACE_IIJKL_LO = {16'h3211, 16'h0000, 16'h0432};
    localparam [47:0] SIG_TRACE_IIJKL_HI = {16'h0004, 16'h0000, 16'h0000};
    // v1.6.1 §22 — reduction primitive families with op_marker convention.
    //
    // Families that share the same SUBSCRIPT einsum shape are disambiguated
    // by an op_marker nibble at `dec_eff_subscript_hi[3:0]` (= O_hi[3:0]).
    // O_hi is naturally zero for scalar / 4D outputs, so the low nibble
    // repurposes as a discriminator without conflict.
    //
    // FAMILY: 5D→scalar (A_lo=0x4321, A_hi=0x0005, B/O_lo/hi=0, marker in O_hi[3:0])
    //   0x0=SUM, 0x1=MAX, 0x2=ARGMAX, 0x3=L1, 0x4=L2SQ, 0x6=MIN, 0x7=ARGMIN
    //   (0x5 reserved to keep 4D family's MEAN marker consistent)
    // FAMILY: 5D→4D (A_lo=0x4321, A_hi=0x0005, O_lo=0x4321, marker in O_hi[3:0])
    //   0x0=SUM_5D_TO_4D, 0x1=MAX_5D_TO_4D, 0x4=L2SQ_5D_TO_4D, 0x5=MEAN_5D_TO_4D
    // 5D→3D SIG_TRACE_IJJKL has unique shape (A_lo=0x3221, O_lo=0x0431) →
    //   no marker needed (single-slot dispatch like SIG_TRACE_IIJKL).
    localparam [47:0] SIG_SCALAR_FAMILY_LO      = {16'h4321, 16'h0000, 16'h0000};
    localparam [43:0] SIG_SCALAR_FAMILY_HI_BASE = {16'h0005, 16'h0000, 12'h000};
    localparam [47:0] SIG_5D4D_FAMILY_LO        = {16'h4321, 16'h0000, 16'h4321};
    localparam [43:0] SIG_5D4D_FAMILY_HI_BASE   = {16'h0005, 16'h0000, 12'h000};
    localparam [47:0] SIG_TRACE_IJJKL_LO        = {16'h3221, 16'h0000, 16'h0431};
    localparam [47:0] SIG_TRACE_IJJKL_HI        = {16'h0004, 16'h0000, 16'h0000};
    // (4D→3D reduction family SIG_4D3D_* removed pre-stable in the
    // opcode cleanup — zero asm/SDK consumers; unknown-A_hi waves fall
    // to the einsum lower_required tail. See spec removal record.)
    // Op-marker constants (family-local nibbles)
    localparam [3:0] OP_SUM     = 4'h0;
    localparam [3:0] OP_MAX     = 4'h1;
    localparam [3:0] OP_ARGMAX  = 4'h2;
    localparam [3:0] OP_L1      = 4'h3;
    localparam [3:0] OP_L2SQ    = 4'h4;
    localparam [3:0] OP_MEAN    = 4'h5;
    localparam [3:0] OP_MIN     = 4'h6;
    localparam [3:0] OP_ARGMIN  = 4'h7;
    // v1.8.0b — generated sub-op codes (single source isa/wt64v1_isa.json)
    `include "generated/isa_subop_codes.vh"
    // v1.8.0d §23.10.10(d) — THE single f32 -> f16/bf16 narrow function,
    // shared with FP_StepSeq's CVT NARROW step (bit-identity clause:
    // 0x7C fp-dest == 0x77 NARROW_FROM_F32 for all 2^32 inputs incl. the
    // DAZ pre-stage). Module-body include, isa_subop_codes.vh convention.
    `include "fp_narrow_f32.vh"
    // v1.8.0e §25.2.1/§25.2.3 — the 0x79 FMINMAX / 0x6B GAMMA_MUL_W
    // combinational MU-arm datapaths. Single-source function include
    // (fp_narrow_f32.vh convention): the SAME functions are instantiated
    // by the standalone unit-test top synth/lattice/fp_ops/FP_CombArms.v,
    // so the unit TB proves exactly the cells these arms dispatch.
    `include "fp_comb_arms.vh"
    localparam [3:0] RED_OP_SUM = 4'h0;
    localparam [3:0] RED_OP_MAX = 4'h1;
    localparam [3:0] RED_OP_MIN = 4'h2;

    // -------------------------------------------------------------------------
    // Helper functions (identical to ISA_Decoder.v)
    // -------------------------------------------------------------------------
    function [ADDR_WIDTH-1:0] bit_reverse;
        input [ADDR_WIDTH-1:0] in_val;
        integer i;
        begin
            bit_reverse = {ADDR_WIDTH{1'b0}};
            for (i = 0; i < ADDR_WIDTH; i = i + 1)
                bit_reverse[i] = in_val[ADDR_WIDTH - 1 - i];
        end
    endfunction

    function [ADDR_WIDTH-1:0] euclid_norm_sq;
        input [ADDR_WIDTH-1:0] in_val;
        reg [31:0] re; reg [31:0] im;
        `WT_USE_DSP reg [63:0] re_sq, im_sq;
        begin
            re = in_val[63:32]; im = in_val[31:0];
            re_sq = re*re; im_sq = im*im;
            euclid_norm_sq = re_sq + im_sq;
        end
    endfunction

    function [ADDR_WIDTH-1:0] conjugate_fn;
        input [ADDR_WIDTH-1:0] in_val;
        reg [31:0] re; reg [31:0] im;
        begin
            re = in_val[63:32]; im = in_val[31:0];
            conjugate_fn = {re, (~im + 32'd1)};
        end
    endfunction

    function [ADDR_WIDTH-1:0] rotate_right_64;
        input [ADDR_WIDTH-1:0] val;
        input [5:0]            n;
        begin
            if (n == 6'd0) rotate_right_64 = val;
            else rotate_right_64 = (val >> n) | (val << (7'd64 - {1'b0,n}));
        end
    endfunction

    function [ADDR_WIDTH-1:0] rotate_left_64;
        input [ADDR_WIDTH-1:0] val;
        input [5:0]            n;
        begin
            if (n == 6'd0) rotate_left_64 = val;
            else rotate_left_64 = (val << n) | (val >> (7'd64 - {1'b0,n}));
        end
    endfunction

    // POPCOUNT (Hamming weight) — 64-bit. Returns 0..64 in low 7 bits.
    function [ADDR_WIDTH-1:0] popcount_64;
        input [ADDR_WIDTH-1:0] val;
        integer i_pc;
        reg [6:0] cnt;
        begin
            cnt = 7'd0;
            for (i_pc = 0; i_pc < 64; i_pc = i_pc + 1)
                cnt = cnt + {6'd0, val[i_pc]};
            popcount_64 = {57'd0, cnt};
        end
    endfunction

    // Count Leading Zeros — 64-bit. Returns 64 for input=0.
    function [ADDR_WIDTH-1:0] clz_64;
        input [ADDR_WIDTH-1:0] val;
        integer i_cl;
        reg [6:0] cnt;
        reg       found;
        begin
            cnt = 7'd0; found = 1'b0;
            for (i_cl = 63; i_cl >= 0; i_cl = i_cl - 1) begin
                if (!found) begin
                    if (val[i_cl]) found = 1'b1;
                    else           cnt = cnt + 7'd1;
                end
            end
            clz_64 = {57'd0, cnt};
        end
    endfunction

    // Count Trailing Zeros — 64-bit. Returns 64 for input=0.
    function [ADDR_WIDTH-1:0] ctz_64;
        input [ADDR_WIDTH-1:0] val;
        integer i_ct;
        reg [6:0] cnt;
        reg       found;
        begin
            cnt = 7'd0; found = 1'b0;
            for (i_ct = 0; i_ct < 64; i_ct = i_ct + 1) begin
                if (!found) begin
                    if (val[i_ct]) found = 1'b1;
                    else           cnt = cnt + 7'd1;
                end
            end
            ctz_64 = {57'd0, cnt};
        end
    endfunction

    function [1:0] axis_sz;
        input [7:0] dim; input [1:0] ax;
        begin
            case (ax)
                2'd0: axis_sz = dim[1:0];
                2'd1: axis_sz = dim[3:2];
                2'd2: axis_sz = dim[5:4];
                2'd3: axis_sz = dim[7:6];
            endcase
        end
    endfunction

    // -------------------------------------------------------------------------
    // v1.1 amendment (2026-07-14) — EINSUM completeness helpers
    // Both operate on the 64-bit payload as 8 packed signed int8 lanes.
    // -------------------------------------------------------------------------

    // SIG_BMM: 'bik,bkj->bij' — batched matrix multiplication, all axes size 2.
    // Layout: input A[b][i][k] at bit range [(b*4+i*2+k)*8 +: 8].
    //         input B[b][k][j] at bit range [(b*4+k*2+j)*8 +: 8].
    //         output R[b][i][j] at bit range [(b*4+i*2+j)*8 +: 8].
    // R[b][i][j] = sum_k A[b][i][k] * B[b][k][j], truncated to int8.
    function [ADDR_WIDTH-1:0] einsum_bmm_int8;
        input [ADDR_WIDTH-1:0] a;
        input [ADDR_WIDTH-1:0] b;
        reg signed [7:0] a000, a001, a010, a011, a100, a101, a110, a111;
        reg signed [7:0] b000, b001, b010, b011, b100, b101, b110, b111;
        reg signed [7:0] r000, r001, r010, r011, r100, r101, r110, r111;
        begin
            a000 = a[ 0 +: 8]; a001 = a[ 8 +: 8]; a010 = a[16 +: 8]; a011 = a[24 +: 8];
            a100 = a[32 +: 8]; a101 = a[40 +: 8]; a110 = a[48 +: 8]; a111 = a[56 +: 8];
            b000 = b[ 0 +: 8]; b001 = b[ 8 +: 8]; b010 = b[16 +: 8]; b011 = b[24 +: 8];
            b100 = b[32 +: 8]; b101 = b[40 +: 8]; b110 = b[48 +: 8]; b111 = b[56 +: 8];
            // batch b=0
            r000 = a000*b000 + a001*b010;
            r001 = a000*b001 + a001*b011;
            r010 = a010*b000 + a011*b010;
            r011 = a010*b001 + a011*b011;
            // batch b=1
            r100 = a100*b100 + a101*b110;
            r101 = a100*b101 + a101*b111;
            r110 = a110*b100 + a111*b110;
            r111 = a110*b101 + a111*b111;
            einsum_bmm_int8 = {r111, r110, r101, r100, r011, r010, r001, r000};
        end
    endfunction

    // SIG_TRACE_IIJ: 'iij->j' — 3D trace with kept axis j. All axes size 2.
    // Layout: input A[i][i'][j] at bit range [(i*4+i_prime*2+j)*8 +: 8].
    //         output R[j] at bit range [j*8 +: 8].
    // R[j] = A[0][0][j] + A[1][1][j], truncated to int8.
    function [ADDR_WIDTH-1:0] einsum_trace_iij_int8;
        input [ADDR_WIDTH-1:0] a;
        reg signed [7:0] r0, r1;
        begin
            r0 = $signed(a[ 0 +: 8]) + $signed(a[48 +: 8]);
            r1 = $signed(a[ 8 +: 8]) + $signed(a[56 +: 8]);
            einsum_trace_iij_int8 = {48'h0, r1, r0};
        end
    endfunction

    // -------------------------------------------------------------------------
    // v1.2 amendment (2026-07-14) — 4D EINSUM at int4 (16 packed nibbles / 64b)
    // -------------------------------------------------------------------------

    // Helper: 2x2 int4 matmul on a 16-bit sub-payload holding 4 int4 nibbles.
    // Layout: nibbles [A00 A01 A10 A11] (row-major, low-nibble = A[0][0]).
    // Returns 16-bit packed [R00 R01 R10 R11] with R = A × B, truncated to int4.
    function [15:0] matmul_2x2_int4;
        input [15:0] a;
        input [15:0] b;
        reg signed [3:0] a00, a01, a10, a11;
        reg signed [3:0] b00, b01, b10, b11;
        reg signed [7:0] r00, r01, r10, r11;
        begin
            a00 = a[ 0 +: 4]; a01 = a[ 4 +: 4]; a10 = a[ 8 +: 4]; a11 = a[12 +: 4];
            b00 = b[ 0 +: 4]; b01 = b[ 4 +: 4]; b10 = b[ 8 +: 4]; b11 = b[12 +: 4];
            r00 = a00*b00 + a01*b10;
            r01 = a00*b01 + a01*b11;
            r10 = a10*b00 + a11*b10;
            r11 = a10*b01 + a11*b11;
            matmul_2x2_int4 = {r11[3:0], r10[3:0], r01[3:0], r00[3:0]};
        end
    endfunction

    // SIG_BMM_2: 'abij,abjk->abik' — 2-batch matmul at int4.
    // 64-bit payload = 4 independent 2×2 matrices in 16-bit sub-payloads.
    // Layout: sub-payload for (a,b) = payload[(a*2+b)*16 +: 16].
    function [ADDR_WIDTH-1:0] einsum_bmm_2_int4;
        input [ADDR_WIDTH-1:0] a;
        input [ADDR_WIDTH-1:0] b;
        reg [15:0] r00, r01, r10, r11;
        begin
            r00 = matmul_2x2_int4(a[ 0 +: 16], b[ 0 +: 16]);  // batch (0,0)
            r01 = matmul_2x2_int4(a[16 +: 16], b[16 +: 16]);  // batch (0,1)
            r10 = matmul_2x2_int4(a[32 +: 16], b[32 +: 16]);  // batch (1,0)
            r11 = matmul_2x2_int4(a[48 +: 16], b[48 +: 16]);  // batch (1,1)
            einsum_bmm_2_int4 = {r11, r10, r01, r00};
        end
    endfunction

    // SIG_TRACE_IIJK: 'iijk->jk' — 3D trace w/ 2 kept axes at int4.
    // Layout: A[i][i'][j][k] at nibble (i*8+i'*4+j*2+k). All size 2.
    //         R[j][k] at nibble (j*2+k). Upper 12 nibbles = 0.
    // R[j][k] = A[0][0][j][k] + A[1][1][j][k], truncated to int4.
    function [ADDR_WIDTH-1:0] einsum_trace_iijk_int4;
        input [ADDR_WIDTH-1:0] a;
        reg signed [3:0] r0, r1, r2, r3;
        begin
            r0 = $signed(a[ 0 +: 4]) + $signed(a[48 +: 4]);  // A[0,0,0,0] + A[1,1,0,0]
            r1 = $signed(a[ 4 +: 4]) + $signed(a[52 +: 4]);  // A[0,0,0,1] + A[1,1,0,1]
            r2 = $signed(a[ 8 +: 4]) + $signed(a[56 +: 4]);  // A[0,0,1,0] + A[1,1,1,0]
            r3 = $signed(a[12 +: 4]) + $signed(a[60 +: 4]);  // A[0,0,1,1] + A[1,1,1,1]
            einsum_trace_iijk_int4 = {48'h0, r3, r2, r1, r0};
        end
    endfunction

    // v1.5.3 §20 — SIG_BMM_3: 'abcij,abcjk->abcik' (3-batch matmul at int4).
    // 128-bit A/B/O payloads = 8 independent 2×2 matmuls (one per (a,b,c) batch).
    // Layout: A[a][b][c][i][j] at nibble (a*16 + b*8 + c*4 + i*2 + j).
    // Per-batch 16-bit sub-payload = payload[(a*4 + b*2 + c)*16 +: 16].
    // Reuses matmul_2x2_int4 × 8 — no new arithmetic.
    //
    // Output split by outermost axis a (per §20 verify:math finding):
    //   fragment 0 = batches (0,0,0), (0,0,1), (0,1,0), (0,1,1) = a=0
    //   fragment 1 = batches (1,0,0), (1,0,1), (1,1,0), (1,1,1) = a=1
    // No cross-lane shuffling needed since a stride is exactly 64 bits.
    //
    // Split into _lo (fragment 0, a=0) and _hi (fragment 1, a=1) functions
    // to let dispatch call each independently — supports timing hedge where
    // compute is spread across cycles if needed (currently both fire cycle N).
    function [ADDR_WIDTH-1:0] einsum_bmm_3_int4_lo;
        input [127:0] a;   // 128-bit A tensor
        input [127:0] b;   // 128-bit B tensor
        reg [15:0] r000, r001, r010, r011;
        begin
            // a=0 batches: (0,0,0)=slot 0, (0,0,1)=slot 1, (0,1,0)=slot 2, (0,1,1)=slot 3
            r000 = matmul_2x2_int4(a[  0 +: 16], b[  0 +: 16]);
            r001 = matmul_2x2_int4(a[ 16 +: 16], b[ 16 +: 16]);
            r010 = matmul_2x2_int4(a[ 32 +: 16], b[ 32 +: 16]);
            r011 = matmul_2x2_int4(a[ 48 +: 16], b[ 48 +: 16]);
            einsum_bmm_3_int4_lo = {r011, r010, r001, r000};
        end
    endfunction

    function [ADDR_WIDTH-1:0] einsum_bmm_3_int4_hi;
        input [127:0] a;
        input [127:0] b;
        reg [15:0] r100, r101, r110, r111;
        begin
            // a=1 batches: (1,0,0)=slot 4, (1,0,1)=slot 5, (1,1,0)=slot 6, (1,1,1)=slot 7
            r100 = matmul_2x2_int4(a[ 64 +: 16], b[ 64 +: 16]);
            r101 = matmul_2x2_int4(a[ 80 +: 16], b[ 80 +: 16]);
            r110 = matmul_2x2_int4(a[ 96 +: 16], b[ 96 +: 16]);
            r111 = matmul_2x2_int4(a[112 +: 16], b[112 +: 16]);
            einsum_bmm_3_int4_hi = {r111, r110, r101, r100};
        end
    endfunction

    // v1.5.5 §21 — SIG_TRACE_IIJKL: 'iijkl->jkl' (5D trace + 3 kept axes).
    // 128-bit A payload, 32-bit output (single-fragment, no FSM).
    // Nibble layout: A[i][i2][j][k][l] at nibble (i*16 + i2*8 + j*4 + k*2 + l).
    // Only diagonal i==i2 contributes:
    //   (i=0, i2=0) base = nibble 0  (bits [0 +: 32])
    //   (i=1, i2=1) base = nibble 24 (bits [96 +: 32])
    // Off-diagonal nibbles 8..23 read but discarded.
    // R[j][k][l] = A[0][0][j][k][l] + A[1][1][j][k][l], signed int4 wrap.
    function [ADDR_WIDTH-1:0] einsum_trace_iijkl_int4;
        input [127:0] a;
        reg signed [3:0] r0, r1, r2, r3, r4, r5, r6, r7;
        begin
            // Output nibble idx = j*4 + k*2 + l. Diagonal-0 offset = idx*4 bits,
            // diagonal-1 offset = 96 + idx*4 bits (24 nibbles = 96 bits).
            r0 = $signed(a[  0 +: 4]) + $signed(a[ 96 +: 4]);
            r1 = $signed(a[  4 +: 4]) + $signed(a[100 +: 4]);
            r2 = $signed(a[  8 +: 4]) + $signed(a[104 +: 4]);
            r3 = $signed(a[ 12 +: 4]) + $signed(a[108 +: 4]);
            r4 = $signed(a[ 16 +: 4]) + $signed(a[112 +: 4]);
            r5 = $signed(a[ 20 +: 4]) + $signed(a[116 +: 4]);
            r6 = $signed(a[ 24 +: 4]) + $signed(a[120 +: 4]);
            r7 = $signed(a[ 28 +: 4]) + $signed(a[124 +: 4]);
            einsum_trace_iijkl_int4 = {32'h0, r7, r6, r5, r4, r3, r2, r1, r0};
        end
    endfunction

    // v1.6.1 §22 — Group A reduction primitives.
    // All take 128-bit A (via dec_input_payload_wide[127:0]) and return
    // ≤64-bit result. No FSM engagement — single output_valid pulse with
    // output_frag_hdr=0x00.

    // 5D→scalar SUM: R = Σ_all A[idx] mod 2^4.  Output: int4 in bits[3:0].
    function [ADDR_WIDTH-1:0] einsum_sum_ijklm_int4;
        input [127:0] a;
        reg [3:0] acc;
        integer i;
        begin
            acc = 4'h0;
            for (i = 0; i < 32; i = i + 1)
                acc = acc + a[i*4 +: 4];
            einsum_sum_ijklm_int4 = {60'h0, acc};
        end
    endfunction

    // 5D→scalar MAX/MIN helpers: tournament-tree of 31 signed compare-selects.
    function [ADDR_WIDTH-1:0] einsum_max_ijklm_int4;
        input [127:0] a;
        reg signed [3:0] mx, x;
        integer i;
        begin
            mx = $signed(a[0 +: 4]);
            for (i = 1; i < 32; i = i + 1) begin
                x = $signed(a[i*4 +: 4]);
                if (x > mx) mx = x;
            end
            einsum_max_ijklm_int4 = {{60{mx[3]}}, mx};
        end
    endfunction

    function [ADDR_WIDTH-1:0] einsum_min_ijklm_int4;
        input [127:0] a;
        reg signed [3:0] mn, x;
        integer i;
        begin
            mn = $signed(a[0 +: 4]);
            for (i = 1; i < 32; i = i + 1) begin
                x = $signed(a[i*4 +: 4]);
                if (x < mn) mn = x;
            end
            einsum_min_ijklm_int4 = {{60{mn[3]}}, mn};
        end
    endfunction

    // 5D→scalar ARGMAX: return 5-bit index (0..31) of max value.
    // Tie-break: earlier index wins.
    function [ADDR_WIDTH-1:0] einsum_argmax_ijklm_int4;
        input [127:0] a;
        reg signed [3:0] mx, x;
        reg [4:0] idx;
        integer i;
        begin
            mx  = $signed(a[0 +: 4]);
            idx = 5'd0;
            for (i = 1; i < 32; i = i + 1) begin
                x = $signed(a[i*4 +: 4]);
                if (x > mx) begin
                    mx  = x;
                    idx = i[4:0];
                end
            end
            einsum_argmax_ijklm_int4 = {59'h0, idx};
        end
    endfunction

    // 5D→scalar ARGMIN: return index of min value. Central for Fréchet
    // medoid, k-means assignment step, KNN classifier, VQ-VAE codebook.
    function [ADDR_WIDTH-1:0] einsum_argmin_ijklm_int4;
        input [127:0] a;
        reg signed [3:0] mn, x;
        reg [4:0] idx;
        integer i;
        begin
            mn  = $signed(a[0 +: 4]);
            idx = 5'd0;
            for (i = 1; i < 32; i = i + 1) begin
                x = $signed(a[i*4 +: 4]);
                if (x < mn) begin
                    mn  = x;
                    idx = i[4:0];
                end
            end
            einsum_argmin_ijklm_int4 = {59'h0, idx};
        end
    endfunction

    // 5D→scalar L1: Σ |A[i]|. int4 |x| ∈ [0,8] → 4-bit unsigned. 32 lanes → sum
    // fits in 9 bits. Output int32 accumulator for future consumer flexibility.
    // 2's complement negation: -x = ~x + 1 (avoids unsigned underflow bug).
    function [ADDR_WIDTH-1:0] einsum_l1_ijklm_int4;
        input [127:0] a;
        reg [3:0]  x;
        reg [4:0]  abs_x;
        reg [31:0] acc;
        integer i;
        begin
            acc = 32'h0;
            for (i = 0; i < 32; i = i + 1) begin
                x     = a[i*4 +: 4];
                // x[3]=1 → negative int4; abs = ~x + 1 (2's complement).
                // Zero-extend to 5-bit (needed since |-8|=8 = 5'b01000).
                abs_x = x[3] ? {1'b0, (~x + 4'h1)} : {1'b0, x};
                acc   = acc + {27'h0, abs_x};
            end
            einsum_l1_ijklm_int4 = {32'h0, acc};
        end
    endfunction

    // 5D→scalar L2SQ: Σ A[i]². int4² ∈ [0,64] → 7-bit. 32 lanes → sum fits in
    // 12 bits. Output int32 accumulator. Central for LayerNorm variance.
    function [ADDR_WIDTH-1:0] einsum_l2sq_ijklm_int4;
        input [127:0] a;
        reg signed [3:0] x;
        reg signed [7:0] sq;
        reg [31:0] acc;
        integer i;
        begin
            acc = 32'h0;
            for (i = 0; i < 32; i = i + 1) begin
                x   = $signed(a[i*4 +: 4]);
                sq  = x * x;   // always ≥0 (x*x)
                acc = acc + {24'h0, sq[7:0]};
            end
            einsum_l2sq_ijklm_int4 = {32'h0, acc};
        end
    endfunction

    // (5D→4D SUM/MAX/L2SQ/MIN variants removed pre-stable in the opcode
    // cleanup — zero asm/SDK consumers. MEAN below is the one live member:
    // rmsnorm/layernorm mean step, asm/wavetensor_asm.py.)

    // 5D→4D MEAN: (A[m=0] + A[m=1]) arithmetically right-shifted by 1.
    // Uses 5-bit signed sum then bits[4:1] → floor((A0+A1)/2).
    function [ADDR_WIDTH-1:0] einsum_mean_5d_to_4d_int4;
        input [127:0] a;
        reg signed [4:0] sum5;
        reg [3:0] r [0:15];
        reg [63:0] out;
        integer idx;
        begin
            for (idx = 0; idx < 16; idx = idx + 1) begin
                sum5 = $signed(a[idx*8 +: 4]) + $signed(a[idx*8 + 4 +: 4]);
                r[idx] = sum5[4:1];   // ASR by 1
            end
            out = 64'h0;
            for (idx = 0; idx < 16; idx = idx + 1)
                out[idx*4 +: 4] = r[idx];
            einsum_mean_5d_to_4d_int4 = out;
        end
    endfunction

    // 5D→3D SIG_TRACE_IJJKL: 'ijjkl->ikl' — trace over j (symmetric to
    // SIG_TRACE_IIJKL which traces over i). Nibble layout: A[i][j][j2][k][l]
    // at (i*16 + j*8 + j2*4 + k*2 + l). Diagonal j==j2 contributes:
    //   (j=0,j2=0) offset within i: 0
    //   (j=1,j2=1) offset within i: 12 nibbles (=48 bits within i-block)
    // R[i][k][l] at nibble idx = i*4 + k*2 + l (8 output nibbles).
    function [ADDR_WIDTH-1:0] einsum_trace_ijjkl_int4;
        input [127:0] a;
        reg signed [3:0] r0, r1, r2, r3, r4, r5, r6, r7;
        begin
            // i=0 block (bits 0-63):   diag (0,0) offset 0, diag (1,1) offset 48
            r0 = $signed(a[  0 +: 4]) + $signed(a[ 48 +: 4]);
            r1 = $signed(a[  4 +: 4]) + $signed(a[ 52 +: 4]);
            r2 = $signed(a[  8 +: 4]) + $signed(a[ 56 +: 4]);
            r3 = $signed(a[ 12 +: 4]) + $signed(a[ 60 +: 4]);
            // i=1 block (bits 64-127): diag (0,0) offset 64, diag (1,1) offset 112
            r4 = $signed(a[ 64 +: 4]) + $signed(a[112 +: 4]);
            r5 = $signed(a[ 68 +: 4]) + $signed(a[116 +: 4]);
            r6 = $signed(a[ 72 +: 4]) + $signed(a[120 +: 4]);
            r7 = $signed(a[ 76 +: 4]) + $signed(a[124 +: 4]);
            einsum_trace_ijjkl_int4 = {32'h0, r7, r6, r5, r4, r3, r2, r1, r0};
        end
    endfunction

    // =========================================================================
    // v1.6.1b §22 — Group B broadcast SIMD helpers (RISC-ish norm primitives)
    // =========================================================================
    // SCALAR: 32 int4 lanes op broadcast 4-bit scalar. Output 128-bit.
    // VEC:    32 int4 lanes op broadcast 4D vector V (16 nibbles = 64-bit),
    //         V[idx>>1] broadcasts to each pair of A lanes.
    // All ops are mod 2^4 (int4 wrap). Signed/unsigned semantics equivalent
    // for ADD/SUB (2's complement wrap); MUL truncates to low 4 bits.

    function [127:0] simd_add_wide_scalar_128;
        input [127:0] a;
        input [3:0]   b;
        reg [127:0] out;
        integer i;
        begin
            out = 128'h0;
            for (i = 0; i < 32; i = i + 1)
                out[i*4 +: 4] = a[i*4 +: 4] + b;
            simd_add_wide_scalar_128 = out;
        end
    endfunction

    function [127:0] simd_sub_wide_scalar_128;
        input [127:0] a;
        input [3:0]   b;
        reg [127:0] out;
        integer i;
        begin
            out = 128'h0;
            for (i = 0; i < 32; i = i + 1)
                out[i*4 +: 4] = a[i*4 +: 4] - b;
            simd_sub_wide_scalar_128 = out;
        end
    endfunction

    function [127:0] simd_mul_wide_scalar_128;
        input [127:0] a;
        input [3:0]   b;
        reg [127:0] out;
        reg signed [3:0] ai, bi;
        reg signed [7:0] p;
        integer i;
        begin
            out = 128'h0;
            for (i = 0; i < 32; i = i + 1) begin
                ai = $signed(a[i*4 +: 4]);
                bi = $signed(b);
                p  = ai * bi;
                out[i*4 +: 4] = p[3:0];   // int4 truncation (spec §22 caveat)
            end
            simd_mul_wide_scalar_128 = out;
        end
    endfunction

    // v1.6.7 §22.14c — Q8.8 wide-scalar mul (further precision recovery
    // beyond the retired 0x67 Q4.4 form — removed pre-stable in the
    // opcode cleanup along with 0x66/0x6B/0x6C). B is signed Q8.8
    // (dec_eff_b_value[15:0]): sign + 7 int + 8 frac bits. LSB = 1/256 —
    // fine enough to push B-side quantization noise below the retired
    // rsqrt LUT's ~6.25% relative-error floor (workflow whro79brj
    // precision analysis).
    // Per-lane: p = signed(A[3:0]) * signed(B[15:0]) → 20-bit signed (Q4.8)
    //           output = (p + 128) >>> 8 → int4 (round-half-up; half of
    //           one output-LSB = 128 Q8.8 ticks)
    // Mathematical bound |A|<=8, |B|<=8 → |A*B/256|<=4 fits int4
    // (saturation-free by construction).
    function [127:0] simd_mul_wide_q8_8_scalar_128;
        input [127:0] a;
        input [15:0]  b;
        reg [127:0] out;
        reg signed [3:0]  ai;
        reg signed [15:0] bi;
        reg signed [19:0] p;
        reg signed [19:0] p_round;
        integer i;
        begin
            out = 128'h0;
            for (i = 0; i < 32; i = i + 1) begin
                ai      = $signed(a[i*4 +: 4]);
                bi      = $signed(b);
                p       = ai * bi;                    // Q4.8 signed (20-bit)
                p_round = p + 20'sd128;                // round-half-up bias
                out[i*4 +: 4] = p_round[11:8];         // arith shift right 8, low 4 bits
            end
            simd_mul_wide_q8_8_scalar_128 = out;
        end
    endfunction

    // (v1.7 §22.18 WIDEN/REQUANTIZE helper functions removed pre-stable in
    // the opcode cleanup — 0x6B/0x6C had zero asm/SDK consumers. The
    // 4-fragment frag-emit FSM they motivated STAYS: reserved for the
    // v1.8.0e wide package.)

    // -------------------------------------------------------------------------
    // v1.8.0b §23.9 — stateless int accumulate datapath (workflow wwov1b5i3).
    // NO architectural state: every op below is a pure function of one
    // dispatch's inputs; K-loop accumulation is SDK dataflow (serial
    // carry-in chains or VDOT partials + scalar ADD 0x10 trees), whose
    // low-32 channel equals numpy int32 wrap (IMMA semantics) and whose
    // full-64 channel is exact for any realistic K — order-free by
    // commutativity/associativity of mod-2^64 addition, no ordering
    // contract, no formal work.
    // -------------------------------------------------------------------------

    // v1.8.0c Gate-4 fix (2026-07-17): the v1.8.0b linear accumulation
    // loops (acc = acc + lane[i]) synthesized as 16-32 SERIAL carry-chain
    // adds — a ~1,000-logic-stage ripple in the MU dispatch cone that
    // halved Cluster Fmax (10.85 → 5.88 MHz). All six reductions are now
    // balanced trees with minimal per-stage widths. Bit-exact with the
    // 32-bit-wrap linear form: every true partial magnitude fits its
    // stage width (bounds below), so no wrap can occur at any node and
    // reassociation cannot change the value (max is associative too).

    // 32-lane int4 dot: |dot| <= 32*8*8 = 2^11 — cannot wrap int32.
    // Products fit signed 8-bit ([-56, 64]); +1 bit per tree level.
    function signed [31:0] vdot_int4_256;
        input [127:0] a;
        input [127:0] b;
        reg signed [7:0]  s0 [0:31];
        reg signed [8:0]  s1 [0:15];
        reg signed [9:0]  s2 [0:7];
        reg signed [10:0] s3 [0:3];
        reg signed [11:0] s4 [0:1];
        reg signed [12:0] r13;
        integer i;
        begin
            for (i = 0; i < 32; i = i + 1)
                s0[i] = $signed(a[i*4 +: 4]) * $signed(b[i*4 +: 4]);
            for (i = 0; i < 16; i = i + 1) s1[i] = s0[2*i] + s0[2*i+1];
            for (i = 0; i < 8;  i = i + 1) s2[i] = s1[2*i] + s1[2*i+1];
            for (i = 0; i < 4;  i = i + 1) s3[i] = s2[2*i] + s2[2*i+1];
            for (i = 0; i < 2;  i = i + 1) s4[i] = s3[2*i] + s3[2*i+1];
            r13 = s4[0] + s4[1];
            vdot_int4_256 = {{19{r13[12]}}, r13};
        end
    endfunction

    // 16-lane int8 dot: |dot| <= 16*128*128 = 2^18 — cannot wrap int32.
    // Products fit signed 16-bit ([-16256, 16384]); +1 bit per level.
    function signed [31:0] vdot_int8_256;
        input [127:0] a;
        input [127:0] b;
        reg signed [15:0] s0 [0:15];
        reg signed [16:0] s1 [0:7];
        reg signed [17:0] s2 [0:3];
        reg signed [18:0] s3 [0:1];
        reg signed [19:0] r20;
        integer i;
        begin
            for (i = 0; i < 16; i = i + 1)
                s0[i] = $signed(a[i*8 +: 8]) * $signed(b[i*8 +: 8]);
            for (i = 0; i < 8; i = i + 1) s1[i] = s0[2*i] + s0[2*i+1];
            for (i = 0; i < 4; i = i + 1) s2[i] = s1[2*i] + s1[2*i+1];
            for (i = 0; i < 2; i = i + 1) s3[i] = s2[2*i] + s2[2*i+1];
            r20 = s3[0] + s3[1];
            vdot_int8_256 = {{12{r20[19]}}, r20};
        end
    endfunction

    // |sum| <= 32*8 = 256 — fits signed 10-bit at the root.
    function signed [31:0] vsum_int4_128;
        input [127:0] a;
        reg signed [4:0] s0 [0:31];
        reg signed [5:0] s1 [0:15];
        reg signed [6:0] s2 [0:7];
        reg signed [7:0] s3 [0:3];
        reg signed [8:0] s4 [0:1];
        reg signed [9:0] r10;
        integer i;
        begin
            for (i = 0; i < 32; i = i + 1)
                s0[i] = {a[i*4+3], a[i*4 +: 4]};
            for (i = 0; i < 16; i = i + 1) s1[i] = s0[2*i] + s0[2*i+1];
            for (i = 0; i < 8;  i = i + 1) s2[i] = s1[2*i] + s1[2*i+1];
            for (i = 0; i < 4;  i = i + 1) s3[i] = s2[2*i] + s2[2*i+1];
            for (i = 0; i < 2;  i = i + 1) s4[i] = s3[2*i] + s3[2*i+1];
            r10 = s4[0] + s4[1];
            vsum_int4_128 = {{22{r10[9]}}, r10};
        end
    endfunction

    // |sum| <= 16*128 = 2^11 — fits signed 13-bit at the root.
    function signed [31:0] vsum_int8_128;
        input [127:0] a;
        reg signed [8:0]  s0 [0:15];
        reg signed [9:0]  s1 [0:7];
        reg signed [10:0] s2 [0:3];
        reg signed [11:0] s3 [0:1];
        reg signed [12:0] r13;
        integer i;
        begin
            for (i = 0; i < 16; i = i + 1)
                s0[i] = {a[i*8+7], a[i*8 +: 8]};
            for (i = 0; i < 8; i = i + 1) s1[i] = s0[2*i] + s0[2*i+1];
            for (i = 0; i < 4; i = i + 1) s2[i] = s1[2*i] + s1[2*i+1];
            for (i = 0; i < 2; i = i + 1) s3[i] = s2[2*i] + s2[2*i+1];
            r13 = s3[0] + s3[1];
            vsum_int8_128 = {{19{r13[12]}}, r13};
        end
    endfunction

    function signed [31:0] vmax_int4_128;
        input [127:0] a;
        reg signed [3:0] m0 [0:31];
        reg signed [3:0] m1 [0:15];
        reg signed [3:0] m2 [0:7];
        reg signed [3:0] m3 [0:3];
        reg signed [3:0] m4 [0:1];
        reg signed [3:0] r4;
        integer i;
        begin
            for (i = 0; i < 32; i = i + 1)
                m0[i] = a[i*4 +: 4];
            for (i = 0; i < 16; i = i + 1) m1[i] = (m0[2*i] > m0[2*i+1]) ? m0[2*i] : m0[2*i+1];
            for (i = 0; i < 8;  i = i + 1) m2[i] = (m1[2*i] > m1[2*i+1]) ? m1[2*i] : m1[2*i+1];
            for (i = 0; i < 4;  i = i + 1) m3[i] = (m2[2*i] > m2[2*i+1]) ? m2[2*i] : m2[2*i+1];
            for (i = 0; i < 2;  i = i + 1) m4[i] = (m3[2*i] > m3[2*i+1]) ? m3[2*i] : m3[2*i+1];
            r4 = (m4[0] > m4[1]) ? m4[0] : m4[1];
            vmax_int4_128 = {{28{r4[3]}}, r4};
        end
    endfunction

    function signed [31:0] vmax_int8_128;
        input [127:0] a;
        reg signed [7:0] m0 [0:15];
        reg signed [7:0] m1 [0:7];
        reg signed [7:0] m2 [0:3];
        reg signed [7:0] m3 [0:1];
        reg signed [7:0] r8;
        integer i;
        begin
            for (i = 0; i < 16; i = i + 1)
                m0[i] = a[i*8 +: 8];
            for (i = 0; i < 8; i = i + 1) m1[i] = (m0[2*i] > m0[2*i+1]) ? m0[2*i] : m0[2*i+1];
            for (i = 0; i < 4; i = i + 1) m2[i] = (m1[2*i] > m1[2*i+1]) ? m1[2*i] : m1[2*i+1];
            for (i = 0; i < 2; i = i + 1) m3[i] = (m2[2*i] > m2[2*i+1]) ? m2[2*i] : m2[2*i+1];
            r8 = (m3[0] > m3[1]) ? m3[0] : m3[1];
            vmax_int8_128 = {{24{r8[7]}}, r8};
        end
    endfunction

    // RNE (ties-to-even) division by 2^k. >>> floors, so rem is always in
    // [0, 2^k) even for negative s; ties round toward the even quotient —
    // explicitly NOT the retired 5D->4D MEAN ASR floor (spec §23.6a).
    function signed [31:0] rne_shr32;
        input signed [31:0] s;
        input [5:0]  k;
        reg signed [31:0] t;
        reg [31:0] rem;
        reg [31:0] half;
        begin
            if (k == 6'd0) rne_shr32 = s;
            else begin
                t    = s >>> k;
                rem  = s - (t <<< k);
                half = 32'd1 << (k - 1);
                if (rem > half)       rne_shr32 = t + 32'sd1;
                else if (rem == half) rne_shr32 = t + {31'b0, t[0]};
                else                  rne_shr32 = t;
            end
        end
    endfunction

    function signed [63:0] rne_shr64;
        input signed [63:0] s;
        input [5:0]  k;
        reg signed [63:0] t;
        reg [63:0] rem;
        reg [63:0] half;
        begin
            if (k == 6'd0) rne_shr64 = s;
            else begin
                t    = s >>> k;
                rem  = s - (t <<< k);
                half = 64'd1 << (k - 1);
                if (rem > half)       rne_shr64 = t + 64'sd1;
                else if (rem == half) rne_shr64 = t + {63'b0, t[0]};
                else                  rne_shr64 = t;
            end
        end
    endfunction

    // Saturating clamp of a signed 64-bit value into a signed dtype range,
    // sign-extended back to 64 bits. The explicit clamp is a mandatory
    // structural stage (v1.7 §22.18 REQUANTIZE lesson).
    function signed [63:0] clamp_sext64;
        input signed [63:0] x;
        input signed [63:0] lo;
        input signed [63:0] hi;
        begin
            if (x > hi)      clamp_sext64 = hi;
            else if (x < lo) clamp_sext64 = lo;
            else             clamp_sext64 = x;
        end
    endfunction

    function [127:0] simd_add_wide_vec_128;
        input [127:0] a;
        input [ 63:0] v;
        reg [127:0] out;
        integer i, v_idx;
        begin
            out = 128'h0;
            // V is 4D (16 nibbles). Each V[i,j,k,l] broadcasts to A's pair over m.
            // A[idx] pairs with V[idx>>1]: A[0],A[1] both use V[0]; A[2],A[3] both V[1]; etc.
            for (i = 0; i < 32; i = i + 1) begin
                v_idx = i >> 1;
                out[i*4 +: 4] = a[i*4 +: 4] + v[v_idx*4 +: 4];
            end
            simd_add_wide_vec_128 = out;
        end
    endfunction

    function [127:0] simd_sub_wide_vec_128;
        input [127:0] a;
        input [ 63:0] v;
        reg [127:0] out;
        integer i, v_idx;
        begin
            out = 128'h0;
            for (i = 0; i < 32; i = i + 1) begin
                v_idx = i >> 1;
                out[i*4 +: 4] = a[i*4 +: 4] - v[v_idx*4 +: 4];
            end
            simd_sub_wide_vec_128 = out;
        end
    endfunction

    function [127:0] simd_mul_wide_vec_128;
        input [127:0] a;
        input [ 63:0] v;
        reg [127:0] out;
        reg signed [3:0] ai, vi;
        reg signed [7:0] p;
        integer i, v_idx;
        begin
            out = 128'h0;
            for (i = 0; i < 32; i = i + 1) begin
                v_idx = i >> 1;
                ai = $signed(a[i*4 +: 4]);
                vi = $signed(v[v_idx*4 +: 4]);
                p  = ai * vi;
                out[i*4 +: 4] = p[3:0];
            end
            simd_mul_wide_vec_128 = out;
        end
    endfunction

    // (v1.6.3 §22.13 Group C scalar rsqrt LUT function removed pre-stable
    // in the opcode cleanup — 0x66 had zero asm/SDK consumers; its ~6.25%
    // LUT relative-error floor analysis remains recorded in the spec and
    // the precision-recovery roadmap memo.)

    function [7:0] dim_squeeze;
        input [7:0] dim; input [1:0] ax;
        begin
            case (ax)
                2'd0: dim_squeeze = {2'b00, dim[7:2]};
                2'd1: dim_squeeze = {2'b00, dim[7:4], dim[1:0]};
                2'd2: dim_squeeze = {2'b00, dim[7:6], dim[3:0]};
                2'd3: dim_squeeze = {2'b00, dim[5:0]};
            endcase
        end
    endfunction

    function [7:0] dim_unsqueeze;
        input [7:0] dim; input [1:0] ax;
        begin
            case (ax)
                2'd0: dim_unsqueeze = {dim[5:0], 2'b00};
                2'd1: dim_unsqueeze = {dim[5:2], 2'b00, dim[1:0]};
                2'd2: dim_unsqueeze = {dim[5:4], 2'b00, dim[3:0]};
                2'd3: dim_unsqueeze = {2'b00, dim[5:0]};
            endcase
        end
    endfunction

    function [15:0] elem_count;
        input [7:0] dim;
        reg [3:0] s0, s1, s2, s3;
        begin
            s0 = {2'b00, dim[1:0]} + 4'd1;
            s1 = {2'b00, dim[3:2]} + 4'd1;
            s2 = {2'b00, dim[5:4]} + 4'd1;
            s3 = {2'b00, dim[7:6]} + 4'd1;
            elem_count = ({12'h0,s0}*{12'h0,s1}) * ({12'h0,s2}*{12'h0,s3});
        end
    endfunction

    function [ADDR_WIDTH-1:0] einsum_dot;
        input [ADDR_WIDTH-1:0] a; input [ADDR_WIDTH-1:0] b;
        `WT_USE_DSP reg [31:0] m0, m1, m2, m3;
        reg [31:0] acc;
        begin
            m0 = {16'h0,a[15:0]}*{16'h0,b[15:0]};
            m1 = {16'h0,a[31:16]}*{16'h0,b[31:16]};
            m2 = {16'h0,a[47:32]}*{16'h0,b[47:32]};
            m3 = {16'h0,a[63:48]}*{16'h0,b[63:48]};
            acc = m0+m1+m2+m3;
            einsum_dot = {32'h0, acc};
        end
    endfunction

    function [ADDR_WIDTH-1:0] einsum_mat_vec;
        input [ADDR_WIDTH-1:0] a; input [ADDR_WIDTH-1:0] b;
        reg [15:0] a00,a01,a10,a11,b0,b1;
        `WT_USE_DSP reg [15:0] r0, r1;
        begin
            a00=a[0+:16]; a01=a[16+:16]; a10=a[32+:16]; a11=a[48+:16];
            b0=b[0+:16]; b1=b[16+:16];
            r0 = a00*b0 + a01*b1;
            r1 = a10*b0 + a11*b1;
            einsum_mat_vec = {32'h0, r1, r0};
        end
    endfunction

    function [ADDR_WIDTH-1:0] permute_2x2_transpose;
        input [ADDR_WIDTH-1:0] a;
        reg [15:0] a00,a01,a10,a11;
        begin
            a00=a[0+:16]; a01=a[16+:16]; a10=a[32+:16]; a11=a[48+:16];
            permute_2x2_transpose = {a11, a01, a10, a00};
        end
    endfunction

    function [ADDR_WIDTH-1:0] reduce_axis0_1d;
        input [3:0] op; input [ADDR_WIDTH-1:0] a;
        reg [15:0] e0,e1,e2,e3,t0,t1,m;
        begin
            e0=a[0+:16]; e1=a[16+:16]; e2=a[32+:16]; e3=a[48+:16];
            case (op)
                RED_OP_SUM: m = e0+e1+e2+e3;
                RED_OP_MAX: begin
                    t0 = (e0>e1)?e0:e1; t1 = (e2>e3)?e2:e3;
                    m  = (t0>t1)?t0:t1;
                end
                RED_OP_MIN: begin
                    t0 = (e0<e1)?e0:e1; t1 = (e2<e3)?e2:e3;
                    m  = (t0<t1)?t0:t1;
                end
                default: m = 16'h0;
            endcase
            reduce_axis0_1d = {48'h0, m};
        end
    endfunction

    function [ADDR_WIDTH-1:0] matmul_func;
        input [ADDR_WIDTH-1:0] a; input [ADDR_WIDTH-1:0] b;
        reg [15:0] a00,a01,a10,a11,b00,b01,b10,b11;
        `WT_USE_DSP reg [15:0] r00,r01,r10,r11;
        begin
            a00=a[0+:16]; a01=a[16+:16]; a10=a[32+:16]; a11=a[48+:16];
            b00=b[0+:16]; b01=b[16+:16]; b10=b[32+:16]; b11=b[48+:16];
            r00 = a00*b00 + a01*b10;
            r01 = a00*b01 + a01*b11;
            r10 = a10*b00 + a11*b10;
            r11 = a10*b01 + a11*b11;
            matmul_func = {r11, r10, r01, r00};
        end
    endfunction

    function [ADDR_WIDTH-1:0] einsum_sum_i;
        input [ADDR_WIDTH-1:0] a;
        reg [15:0] s0;
        begin
            s0 = a[15:0]+a[31:16]+a[47:32]+a[63:48];
            einsum_sum_i = {48'h0, s0};
        end
    endfunction

    function [ADDR_WIDTH-1:0] einsum_trace_ii;
        input [ADDR_WIDTH-1:0] a;
        reg [15:0] t;
        begin
            t = a[0+:16] + a[48+:16];
            einsum_trace_ii = {48'h0, t};
        end
    endfunction

    function [ADDR_WIDTH-1:0] einsum_transpose_ij;
        input [ADDR_WIDTH-1:0] a;
        reg [15:0] a00,a01,a10,a11;
        begin
            a00=a[0+:16]; a01=a[16+:16]; a10=a[32+:16]; a11=a[48+:16];
            einsum_transpose_ij = {a11, a01, a10, a00};
        end
    endfunction

    function [ADDR_WIDTH-1:0] einsum_hadamard;
        input [ADDR_WIDTH-1:0] a; input [ADDR_WIDTH-1:0] b;
        `WT_USE_DSP reg [15:0] r0,r1,r2,r3;
        begin
            r0 = a[0+:16]*b[0+:16];
            r1 = a[16+:16]*b[16+:16];
            r2 = a[32+:16]*b[32+:16];
            r3 = a[48+:16]*b[48+:16];
            einsum_hadamard = {r3,r2,r1,r0};
        end
    endfunction

    function [ADDR_WIDTH-1:0] einsum_outer;
        input [ADDR_WIDTH-1:0] a; input [ADDR_WIDTH-1:0] b;
        reg [15:0] a0,a1,b0,b1;
        `WT_USE_DSP reg [15:0] r00,r01,r10,r11;
        begin
            a0=a[0+:16]; a1=a[16+:16]; b0=b[0+:16]; b1=b[16+:16];
            r00=a0*b0; r01=a0*b1; r10=a1*b0; r11=a1*b1;
            einsum_outer = {r11,r10,r01,r00};
        end
    endfunction

    function [ADDR_WIDTH-1:0] einsum_partial_ijk;
        input [ADDR_WIDTH-1:0] a;
        reg [15:0] r00,r01,r10,r11;
        begin
            r00 = a[0+:16] + a[16+:16];
            r01 = a[32+:16] + a[48+:16];
            r10 = 16'h0; r11 = 16'h0;
            einsum_partial_ijk = {r11,r10,r01,r00};
        end
    endfunction

    function [ADDR_WIDTH-1:0] einsum_diagonal;
        input [ADDR_WIDTH-1:0] a;
        reg [15:0] d0,d1;
        begin
            d0 = a[0+:16]; d1 = a[48+:16];
            einsum_diagonal = {32'h0, d1, d0};
        end
    endfunction

    // -------------------------------------------------------------------------
    // Op-class classifiers
    // -------------------------------------------------------------------------
    // v1.8.0b §23.9 — TWIN CLASSIFIER invariant: this list and Cluster.v's
    // is_mul_op must stay in lockstep. 0x71 VDOT_ACC / 0x72 ACC_REDUCE are
    // MU-hosted (MAC tree lives only where MUL_OPS_SUPPORTED); without the
    // PE_Core half, the MU gate below lowers both ops forever and no L-PE
    // ever receives them (verified dead-end in the design workflow).
    // v1.8.0c §23.10 — 0x74 FSCALAR / 0x75 FRSQRT32 / 0x76 FEXP2_32 are
    // MU-hosted too (the fp32 step sequencer lives only where
    // MUL_OPS_SUPPORTED); same lockstep rule, same silent-dead-end failure
    // mode if either twin misses them (pinned by the Cluster reachability
    // test test_fp_mu_routing_end_to_end).
    // v1.8.0d §23.10.10 — 0x77 CVT / 0x73 ACC_ELEMWISE join OPCODE-ONLY
    // (both ride the MU's FP_StepSeq: OPS_CVT / OPS_ACCEW). 0x7C is
    // DELIBERATELY absent for ALL dtypes including the new fp-dest forms
    // (no multipliers — the shared narrow packer is combinational on the
    // L-PEs; §23.10.10(d) twin-classifier-untouched clause).
    // v1.8.0e §25.3/§25.6 item 6 — 0x6B GAMMA_MUL_W / 0x78 DEQUANT /
    // 0x79 FMINMAX join OPCODE-ONLY in lockstep with Cluster.v's
    // is_mul_op (all three arms are MU-hosted; a one-sided edit is the
    // silent permanent lower_required dead-end — pinned by the static
    // lockstep test + test_fp_mu_routing_end_to_end_0e in this commit).
    // 0x70 VFMA_ACC joins with its 0e2 arm, not before (staged).
    wire dec_is_mul_op = (dec_opcode == 8'h12) || (dec_opcode == 8'h30)
                      || (dec_opcode == 8'h32) || (dec_opcode == 8'h43)
                      || (dec_opcode == 8'h6B)
                      || (dec_opcode == 8'h71) || (dec_opcode == 8'h72)
                      || (dec_opcode == 8'h73) || (dec_opcode == 8'h74)
                      || (dec_opcode == 8'h75) || (dec_opcode == 8'h76)
                      || (dec_opcode == 8'h77) || (dec_opcode == 8'h78)
                      || (dec_opcode == 8'h79);
    wire dec_is_div_op = (dec_opcode == 8'h13)   // DIV
                      || (dec_opcode == 8'h1C)   // MOD
                      || (dec_opcode == 8'h1D);  // DIVMOD

    // -------------------------------------------------------------------------
    // 64-bit MUL multi-cycle pipeline
    // -------------------------------------------------------------------------
    reg [ADDR_WIDTH-1:0] mul_a_p1, mul_b_p1;
    reg                  mul_valid_p1;
    reg [TAG_WIDTH-1:0]  mul_tag_p1;
    `WT_USE_DSP reg [ADDR_WIDTH-1:0] mul_result_p2;
    reg                  mul_valid_p2;
    reg [TAG_WIDTH-1:0]  mul_tag_p2;

    // -------------------------------------------------------------------------
    // 64-bit DIV/MOD/DIVMOD bit-serial divider
    //
    // Long-division (restoring algorithm), one quotient bit per cycle. Each
    // iteration's critical path is a 64-bit subtract + select (~8 CARRY8
    // levels), trivial to close at 100 MHz. Cost: 64 cycles for full 64-bit
    // DIV/MOD, 32 cycles for 32-bit DIVMOD.
    //
    // Why serial? A combinational 64-bit divider (`a / b`) unrolls into
    // ~640 cascaded CARRY8 levels (~50 ns @ XCAU25P -2 grade), which was the
    // single critical path in the previous WNS = -55 ns post-route. Pipelined
    // 2-stage register split was insufficient because the dividend cascade
    // is still combinational within one cycle. Bit-serial breaks the chain
    // entirely — each cycle only runs ONE subtract-and-select.
    //
    // States:
    //   IDLE      — wait for dec_valid + DIV/MOD/DIVMOD opcode
    //   ITER      — long-division loop (count down `iter_left`)
    //   FINISH    — present result (output_valid pulses for one cycle)
    //
    // The DIV-UNIT is shared across the cluster — typical workloads use
    // DIV/MOD rarely, so the multi-cycle latency is acceptable.
    // -------------------------------------------------------------------------
    localparam DIV_IDLE   = 2'd0;
    localparam DIV_ITER   = 2'd1;
    localparam DIV_FINISH = 2'd2;

    reg [1:0]            div_state;
    reg [6:0]            div_iter_left;        // 64..0 (or 32..0 for DIVMOD)
    reg [ADDR_WIDTH-1:0] div_dividend;         // shifts left, gathers quotient
    reg [ADDR_WIDTH-1:0] div_remainder;
    reg [ADDR_WIDTH-1:0] div_divisor;
    reg                  div_is_mod;
    reg                  div_is_divmod;
    reg                  div_b_zero;
    reg [TAG_WIDTH-1:0]  div_tag_held;
    reg                  div_valid_p2;          // output strobe
    reg [ADDR_WIDTH-1:0] div_result_p2;
    reg [TAG_WIDTH-1:0]  div_tag_p2;
    reg                  div_b_zero_p2;

    // -------------------------------------------------------------------------
    // v1.8.0c §23.10 — fp32 scalar step-sequencer unit (FP_StepSeq) hosting
    // state. Declared UNCONDITIONALLY (the div_state pattern): the hoisted
    // output_regs_free / pe_ready expression below references fp_busy and
    // fp_valid_p2 in every PE_Core flavor, so these signals must elaborate
    // in all instances. They are DRIVEN only under MUL_OPS_SUPPORTED — the
    // launch/finish clauses in the dispatch block sit behind the parameter
    // (constant-folded away on L-PEs / DIV-UNIT) and the FP_StepSeq
    // instance itself lives in the g_v180c_fp generate; the else-branch
    // (g_v180c_fp_off) zero-ties the data wires (wres_vdot32 idiom).
    //
    // fp_start is a REGISTERED 1-cycle pulse set by the launch arm (the
    // dispatch is register-load only, §23.10.1). FP_StepSeq's busy output
    // is combinational `start | (state != FP_IDLE)`, so fp_busy is already
    // 1 during the whole first cycle after the launch edge — there is NO
    // 1-cycle double-dispatch window and fp_start needs no separate term
    // in output_regs_free (fp_busy covers it; verified by
    // test_fp_busy_reject_is_lower_required back-to-back retry).
    //
    // fp_armed guards the done capture: FP_StepSeq is reset-free, so a
    // parent rst mid-op lets the in-flight op self-complete; fp_armed
    // (cleared by rst) makes the parent ignore that stray done pulse
    // instead of emitting a stale result with a zeroed tag.
    reg         fp_start;                       // 1-cycle launch pulse
    reg         fp_armed;                       // launch..done ownership flag
    reg  [31:0] fp_a_q, fp_b_q, fp_c_q;         // operands latched at launch
    reg  [3:0]  fp_subop_q;                     // FSCALAR/CVT sub-op (imm16[7:4])
    // v1.8.0d §23.10.10(b) — CVT dtype (eff_precision[3:0]) latched at the
    // 0x77 launch only; FP_StepSeq ignores dtype_in for every other op
    // class, and the sext-vs-zext result capture below additionally keys
    // on fp_opcode_held == 8'h77, so a stale value is harmless.
    reg  [3:0]  fp_dtype_q;
    reg  [7:0]  fp_opcode_held;                 // opcode_out at result cycle
    reg  [TAG_WIDTH-1:0]  fp_tag_held;          // scalar tag rebuilt at launch
    reg                   fp_valid_p2;          // output strobe (div_valid_p2 idiom)
    reg  [ADDR_WIDTH-1:0] fp_result_p2;         // {32'h0, fp32} payload
    reg  [TAG_WIDTH-1:0]  fp_tag_p2;
    wire        fp_busy;                        // FP_StepSeq busy (see above)
    wire        fp_done;                        // 1-cycle done pulse
    wire [31:0] fp_result_w;                    // valid exactly during done

    // -------------------------------------------------------------------------
    // v1.5.3a §20 — fragment-emit FSM. Originally a 1-bit Moore machine
    // mirroring the div_state idiom (frag_state: FRAG_IDLE/FRAG_EMIT_HI,
    // one pending 64-bit fragment). On SIG_BMM_3 dispatch (frag_idx=
    // FRAG_IDLE cycle N):
    //   - drives output_valid=1, output_payload=lo, output_frag_hdr=8'h01
    //   - latches result[127:64] into frag_pending[1] + tag/opcode holds
    //   - transitions to FRAG_EMIT_1
    // On cycle N+1 (FRAG_EMIT_1): absolute-priority override at the top of
    // the output mux drives fragment 1 (frag_hdr=8'h11) and returns to IDLE
    // (since frag_total_m1_held==1 for every 2-fragment emitter).
    //
    // v1.7 §22.18 — widened from 1-bit {IDLE,EMIT_HI} to a 2-bit up-counter
    // {IDLE, EMIT_1, EMIT_2, EMIT_3} supporting up to 4 sequential fragment
    // emissions. Originally motivated by the retired 0x6B WIDEN 256-bit/
    // 4-fragment output (removed pre-stable in the opcode cleanup).
    //
    // v1.8.0e §25.3 — EMIT-SIDE 2 -> 4-bit widening (0e1 groundwork,
    // edit list (a)-(g)): frag_idx/frag_total_m1_held are now [3:0]
    // (the FSM stays a plain up-counter, FRAG_IDLE = 4'd0) and
    // frag_pending is [0:15] (+768 FF), so up to 16 sequential fragment
    // emissions drain 1/cycle (the 0x78 DEQUANT 8-frag and 0e2 0x70
    // VFMA 16-frag consumers; Cluster CAM storage is already 16-deep —
    // receive parsing unchanged). The drain read frag_pending[frag_idx]
    // is a genuine 16:1 x 64b reg-array mux (NOT the Gate-3
    // constant-array pathology). Row 0 REMAINS the reset-only dummy:
    // frag_idx == 0 aliases fragment 0, which is ALWAYS emitted
    // directly at the arm cycle and never drained (loop-form ops emit
    // fragment 0 from a dedicated frag0_hold at LOOP COMPLETION — the
    // §25.3 invariant; that writer lands with the 0e1 integration
    // commit). frag_total_m1_held records how many fragments THIS wave
    // actually has (1 for every live 2-fragment emitter incl. the new
    // 0x79/0x6B comb arms; >3 becomes writer-live with the DEQUANT
    // loop). frag_tag_held/frag_opcode_held are UNCHANGED (tag/opcode
    // are constant across all fragments of one wave — confirmed no
    // widening needed, workflow wgcq5jc68 investigator 0).
    //
    // MANDATORY INVARIANT (CI-enforced, scripts/lint_frag_total_m1_held.py):
    // every dispatch site that writes `frag_idx <= FRAG_EMIT_1` (entering
    // the drain) MUST also write `frag_total_m1_held` in the SAME begin/end
    // block. Violating this leaves a stale total_m1_held from a PRIOR
    // dispatch, causing the drain loop to emit the wrong number of
    // fragments (either truncating a real multi-fragment wave, or emitting
    // spurious extra fragments from garbage frag_pending[] slots).
    //
    // Backpressure: the compound `output_regs_free` wire (declared below)
    // gates SIG_BMM_3/wide-emit dispatch when ANY output-mux
    // source is in flight (MUL p1/p2, DIV any-state, DIV b_zero pulse).
    // This closes the MUL/DIV drain hazard the verify:fsm agent flagged.
    // pe_ready's worst-case deassertion window is 1 cycle for the live
    // 2-fragment emitters; a 16-fragment result drains rows 1..15 at
    // 1/cycle after the arm-cycle fragment 0, so the worst deassertion
    // window becomes ~15 cycles (v1.8.0e §25.3 amendment — an accepted
    // throughput tradeoff, not a correctness hazard).
    // -------------------------------------------------------------------------
    localparam [3:0]      FRAG_IDLE    = 4'd0;
    localparam [3:0]      FRAG_EMIT_1  = 4'd1;
    localparam [3:0]      FRAG_EMIT_2  = 4'd2;
    localparam [3:0]      FRAG_EMIT_3  = 4'd3;

    reg [3:0]             frag_idx;
    reg [3:0]             frag_total_m1_held;
    // Index 0 exists only so the dynamic read frag_pending[frag_idx]
    // never references an undeclared row (frag_idx==FRAG_IDLE==0 is
    // gated out of the drain path, but the read MUX still sees the
    // index) — kept reset-driven, never written by any dispatch.
    reg [ADDR_WIDTH-1:0]  frag_pending [0:15];
    reg [TAG_WIDTH-1:0]  frag_tag_held;
    reg [7:0]            frag_opcode_held;

    // -------------------------------------------------------------------------
    // v1.8.0e §25.2.2/§25.3 — 0x78 DEQUANT lane-loop state (0e1
    // integration). Declared UNCONDITIONALLY (the fp-reg pattern):
    // output_regs_free below references deq_loop_active in every PE_Core
    // flavor; all writers sit behind MUL_OPS_SUPPORTED (constant-folded
    // away on L-PEs / DIV-UNIT).
    //
    // Loop shape (one FP_StepSeq OPS_DEQ launch per lane, strictly
    // serial): the 0x78 arm captures A(128b)+scale+tag into MU-local
    // regs at launch (0x74 idiom — EHDecode is cluster-shared) and
    // fires lane 0. Each per-lane fp_done is DIVERTED from the fp
    // output arm (fp_armed stays LOW for the whole loop — no spurious
    // per-lane emits, the confirmed 1701/1768-class hazard) into the
    // lane-loop advance block: the bf16 result packs into a 64-bit
    // staging word (4 bf16 lanes/word — the §25.3 packing pin), word 0
    // goes to the dedicated frag0_hold (row-0-dummy invariant
    // preserved), words >= 1 go to frag_pending[word] — THE
    // accumulation buffer IS the widened frag_pending, no second
    // structure. The registered relaunch (fp_start <= 1 at the done
    // edge) lands in FP_StepSeq's first idle cycle, so fp_busy holds
    // output_regs_free low continuously across lane turnarounds;
    // deq_loop_active additionally covers the pack/arm window
    // (belt-and-braces per the spec pin). Fragment 0 emits at LOOP
    // COMPLETION, not dispatch (§25.6 item 8 invariant) — the atomic
    // frag0_hold handoff block after the dispatch chain below.
    // -------------------------------------------------------------------------
    reg               deq_loop_active;   // launch .. final-lane done cycle
    reg [4:0]         deq_lane;          // lane in flight (0..N-1)
    reg               deq_is_int8;       // form: 0 = int4-32, 1 = int8-16
    reg [47:0]        deq_stage;         // lanes 4w+0..4w+2 of the open word
    reg [127:0]       deq_a_q;           // launch-captured A (128b wide)
    reg [63:0]        frag0_hold;        // fragment 0 word (§25.3 pin)
    wire [3:0]        deq_total_m1  = deq_is_int8 ? 4'd3  : 4'd7;
    wire [4:0]        deq_lane_last = deq_is_int8 ? 5'd15 : 5'd31;
    wire [4:0]        deq_lane_nxt  = deq_lane + 5'd1;
    // Next-lane operand extract (32:1x4b / 16:1x8b mux — priced in the
    // §25.5.1 OPS_DEQ itemization; a reg read, NOT a ROM part-select).
    // Assigned inside the MU-gated generate below (wres_vdot32 idiom).
    wire [31:0]       deq_fp_a_nxt;

    // v1.8.0c §23.10 — widened to the 8-term compound of the spec: the fp
    // step sequencer holds the output stage from launch (fp_busy rises
    // WITH the registered start pulse — no gap cycle, see the fp state
    // declaration comment) through the fp_valid_p2 result strobe.
    // pe_ready follows automatically (same wire, assigned at the bottom).
    // v1.8.0e §25.3 — + the deq_loop_active occupancy term (the DEQUANT
    // lane loop's pack/arm window; fp_busy already covers every lane
    // flight and turnaround cycle, the extra term is the pinned cover).
    wire output_regs_free = (frag_idx == FRAG_IDLE)
        && !mul_valid_p1 && !mul_valid_p2
        && (div_state == DIV_IDLE) && !div_valid_p2 && !div_b_zero_p2
        && !fp_busy && !fp_valid_p2 && !deq_loop_active;

    // -------------------------------------------------------------------------
    // v1.8 §23.8 synth-gate fix (2026-07-16) — yosys (Verilog-2005) does not
    // allow indexing a function-call result directly (func(...)[63:0]);
    // the simulator accepted the old form as a SystemVerilog extension,
    // so the incompatibility sat latent since v1.6.1b until the first
    // yosys run of the §23.8 hard gate hit it (PE_Core.v syntax error).
    // Standard fix: hoist each wide-op result into a combinational wire and
    // slice the WIRE at the dispatch site. Bit-identical behavior (the
    // function calls in the always block were already evaluated
    // combinationally each cycle); unused results for a given dispatch are
    // pruned by synthesis exactly as before.
    // -------------------------------------------------------------------------
    wire [127:0] wres_add_wide_scalar = simd_add_wide_scalar_128(
        dec_input_payload_wide[127:0], dec_eff_b_value[3:0]);
    wire [127:0] wres_sub_wide_scalar = simd_sub_wide_scalar_128(
        dec_input_payload_wide[127:0], dec_eff_b_value[3:0]);
    wire [127:0] wres_mul_wide_scalar = simd_mul_wide_scalar_128(
        dec_input_payload_wide[127:0], dec_eff_b_value[3:0]);
    wire [127:0] wres_add_wide_vec = simd_add_wide_vec_128(
        dec_input_payload_wide[127:0], dec_input_payload_b);
    wire [127:0] wres_sub_wide_vec = simd_sub_wide_vec_128(
        dec_input_payload_wide[127:0], dec_input_payload_b);
    wire [127:0] wres_mul_wide_vec = simd_mul_wide_vec_128(
        dec_input_payload_wide[127:0], dec_input_payload_b);
    wire [127:0] wres_mul_q8_8 = simd_mul_wide_q8_8_scalar_128(
        dec_input_payload_wide[127:0], dec_eff_b_value[15:0]);

    // v1.8.0b — stateless int-path hoisted results. MU-gated generate:
    // the MAC/reduce trees synthesize ONLY where MUL_OPS_SUPPORTED (the
    // 0x71/0x72 arms are unreachable elsewhere — dec_is_mul_op routes
    // them, and the !MUL_OPS_SUPPORTED prologue lowers on direct
    // dispatch) so the 16 L-PEs pay zero area for them.
    wire v180b_int8_mode = (dec_eff_precision[3:0] == 4'h1);
    wire signed [31:0] wres_vdot32;
    wire signed [31:0] wres_acc_sum;
    wire signed [31:0] wres_acc_max;
    wire signed [31:0] wres_acc_l2sq;
    wire signed [31:0] wres_acc_mean;
    generate if (MUL_OPS_SUPPORTED) begin : g_v180b_mac
        assign wres_vdot32 = v180b_int8_mode
            ? vdot_int8_256(dec_input_payload_wide[127:0], dec_input_payload_wide[255:128])
            : vdot_int4_256(dec_input_payload_wide[127:0], dec_input_payload_wide[255:128]);
        assign wres_acc_sum = v180b_int8_mode
            ? vsum_int8_128(dec_input_payload_wide[127:0])
            : vsum_int4_128(dec_input_payload_wide[127:0]);
        assign wres_acc_max = v180b_int8_mode
            ? vmax_int8_128(dec_input_payload_wide[127:0])
            : vmax_int4_128(dec_input_payload_wide[127:0]);
        assign wres_acc_l2sq = v180b_int8_mode
            ? vdot_int8_256(dec_input_payload_wide[127:0], dec_input_payload_wide[127:0])
            : vdot_int4_256(dec_input_payload_wide[127:0], dec_input_payload_wide[127:0]);
        assign wres_acc_mean = rne_shr32(wres_acc_sum, v180b_int8_mode ? 6'd4 : 6'd5);
    end else begin : g_v180b_mac_off
        assign wres_vdot32   = 32'sd0;
        assign wres_acc_sum  = 32'sd0;
        assign wres_acc_max  = 32'sd0;
        assign wres_acc_l2sq = 32'sd0;
        assign wres_acc_mean = 32'sd0;
    end endgenerate

    // -------------------------------------------------------------------------
    // v1.8.0c §23.10 — MU-hosted fp32 step-sequencer unit. One shared
    // FP_StepSeq per MU walks the 0x74/0x75/0x76 step programs (5-34
    // cycles); operands/opcode/sub-op are sampled on the fp_start edge and
    // held stable until the next launch (the launch ladder guarantees
    // start only fires while busy == 0). Synthesizes ONLY on the
    // MATMUL_UNIT (Gate 3 §23.10.7: 3,345 LUT4 / 4 MULT18X18D — amended
    // budget); the off-branch zero-ties the data wires so the 16 L-PEs +
    // DIV-UNIT pay zero area (wres_vdot32 idiom).
    generate if (MUL_OPS_SUPPORTED) begin : g_v180c_fp
        FP_StepSeq u_fp_stepseq (
            .clk       (clk),
            .start     (fp_start),
            .opcode_in (fp_opcode_held),
            .subop_in  (fp_subop_q),
            // v1.8.0d §23.10.10(b) — dtype feeds the OPS_CVT programs
            // (latched by the 0x77 launch arm; don't-care elsewhere).
            .dtype_in  (fp_dtype_q),
            .a_in      (fp_a_q),
            .b_in      (fp_b_q),
            .c_in      (fp_c_q),
            .busy      (fp_busy),
            .done      (fp_done),
            .result    (fp_result_w)
        );
    end else begin : g_v180c_fp_off
        assign fp_busy     = 1'b0;
        assign fp_done     = 1'b0;
        assign fp_result_w = 32'h0;
    end endgenerate

    // v1.8.0e §25.2.1/§25.2.3 — 0x79 FMINMAX + 0x6B GAMMA_MUL_W hoisted
    // combinational results (einsum-arm pattern: functions -> wres_
    // wires sliced at the dispatch site, §23.8 — never index a function
    // call). MU-GATED generate (wres_vdot32 idiom): the compare cells
    // and the LUT-structural gamma shift-adds synthesize ONLY where
    // MUL_OPS_SUPPORTED, so the 16 L-PEs + DIV-UNIT pay zero area
    // (§25.2.3 MU-hosting pin; L-PE zero-growth is a unit-gate proof).
    // FMINMAX: lane i of A at wide[32i+31:32i] vs the ONE broadcast B in
    // payload_b[31:0] (the 0x74 low-word convention, cloned); sub-op
    // imm16[7:4] via the generated FMM_* localparams (absent imm16 = 0 =
    // minimumNumber). GAMMA: A = 16 int4 lanes in payload_a[63:0], gamma
    // = eff_b_value (IMM64 XOR OPREF, alu-binary XOR enforced at
    // EHDecode); both emit 128b = 2 fragments through the widened FSM.
    wire [127:0] wres_fminmax;
    wire [127:0] wres_gamma_w;
    generate if (MUL_OPS_SUPPORTED) begin : g_v180e_comb
        wire fmm_is_max = (dec_eff_imm16[7:4] == FMM_MAXIMUMNUM);
        assign wres_fminmax = {
            fminmax_lane_f32(dec_input_payload_wide[127:96],
                             dec_input_payload_b[31:0], fmm_is_max),
            fminmax_lane_f32(dec_input_payload_wide[95:64],
                             dec_input_payload_b[31:0], fmm_is_max),
            fminmax_lane_f32(dec_input_payload_wide[63:32],
                             dec_input_payload_b[31:0], fmm_is_max),
            fminmax_lane_f32(dec_input_payload_wide[31:0],
                             dec_input_payload_b[31:0], fmm_is_max)};
        assign wres_gamma_w = gamma_mul_w_128(dec_input_payload[63:0],
                                              dec_eff_b_value);
        // v1.8.0e §25.2.2 — DEQUANT next-lane operand extract from the
        // launch-captured A: int4 lane at [4i+3:4i], int8 lane at
        // [8i+7:8i] (the golden dequant_frags lane-map pin); upper a_in
        // bits are ignored by FP_StepSeq's OPS_DEQ field select.
        assign deq_fp_a_nxt = deq_is_int8
            ? {24'h0, deq_a_q[{deq_lane_nxt[3:0], 3'b000} +: 8]}
            : {28'h0, deq_a_q[{deq_lane_nxt, 2'b00} +: 4]};
    end else begin : g_v180e_comb_off
        assign wres_fminmax = 128'h0;
        assign wres_gamma_w = 128'h0;
        assign deq_fp_a_nxt = 32'h0;
    end endgenerate

    // v1.8.0d §23.10.10(b) — CVT F2I results are int32-patterned and the
    // result payload row is SEXT64 (ints sext64; everything else keeps the
    // {32'h0, low32} zero-extend: f32 rows and the {48'h0, h} f16/bf16
    // rows, whose FP_StepSeq low-32 word is already {16'h0, h}). The held
    // launch registers identify the F2I forms: opcode 0x77, sub-op
    // NARROW_FROM_F32, dtype not f16/bf16. fp_subop_q/fp_dtype_q are only
    // meaningful when fp_opcode_held selects them (same held-register
    // convention as the FSCALAR sub-op).
    wire fp_res_int_sext = (fp_opcode_held == 8'h77)
                        && (fp_subop_q == CVT_NARROW_FROM_F32)
                        && (fp_dtype_q != 4'h2) && (fp_dtype_q != 4'h3);
    // VDOT result: r = (sext64(dot) + carry_in) mod 2^64. Full 64-bit
    // payload convention (spec §23.6a payload-format table) — NOT the
    // legacy {32'h0, acc} zero-extend.
    wire [63:0] wres_vdot_r = {{32{wres_vdot32[31]}}, wres_vdot32} + dec_eff_b_value;

    // STORE_QUANT (L-PE hosted — no multipliers, hence ungated):
    // out = clamp_dtype(RNE(x >>_arith s)), s = imm16[5:0].
    wire signed [63:0] wres_sq_shifted = rne_shr64($signed(dec_input_payload), dec_eff_imm16[5:0]);
    wire [63:0] wres_sq_int4 = clamp_sext64(wres_sq_shifted, -64'sd8,   64'sd7);
    wire [63:0] wres_sq_int8 = clamp_sext64(wres_sq_shifted, -64'sd128, 64'sd127);
    // v1.8.0d §23.10.10(d) — STORE_QUANT fp-dest packer (dtype 0x2/0x3):
    // source = fp32 payload[31:0], DAZ-flushed AT SOURCE (pinned
    // identically to the FP_StepSeq CVT-narrow capture site — the
    // bit-identity precondition; the shared function's e==0 arm makes the
    // result caller-DAZ-agnostic, but the pin is kept explicit so the two
    // sites read the same). Function-call results are hoisted to wires
    // and consumed whole (§23.8 — no function-call result indexing).
    wire [31:0] wres_sq_fp_src = (dec_input_payload[30:23] == 8'h00)
                               ? {dec_input_payload[31], 31'h0}
                               : dec_input_payload[31:0];
    wire [15:0] wres_sq_f16  = fp_narrow_f32(wres_sq_fp_src, 1'b0);
    wire [15:0] wres_sq_bf16 = fp_narrow_f32(wres_sq_fp_src, 1'b1);

    // -------------------------------------------------------------------------
    // Stage-2 sequential dispatch
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            output_payload  <= {ADDR_WIDTH{1'b0}};
            output_tag      <= {TAG_WIDTH{1'b0}};
            output_valid    <= 1'b0;
            opcode_out      <= 8'h00;
            output_frag_hdr <= 8'h00;
            memory_req      <= 1'b0;
            mem_addr        <= {ADDR_WIDTH{1'b0}};
            error_flag      <= 1'b0;
            lower_required  <= 1'b0;
            mul_valid_p1   <= 1'b0;
            mul_valid_p2   <= 1'b0;
            div_state      <= DIV_IDLE;
            div_valid_p2   <= 1'b0;
            div_b_zero_p2  <= 1'b0;
            // v1.8.0c fp control bits (FP_StepSeq itself is reset-free; a
            // mid-op rst clears fp_armed so the stray done pulse of the
            // self-completing op is ignored — see the declaration block).
            fp_start       <= 1'b0;
            fp_armed       <= 1'b0;
            fp_valid_p2    <= 1'b0;
            // v1.8.0e §25.3 — a mid-loop rst abandons the DEQUANT lane
            // loop: the in-flight lane self-completes inside FP_StepSeq
            // and its done pulse is ignored (deq_loop_active cleared,
            // fp_armed already low) — the fp_armed mid-op-rst contract
            // extended to the loop. Data regs (deq_a_q/deq_stage/
            // frag0_hold) are reset-free like the fp operand regs.
            deq_loop_active <= 1'b0;
            frag_idx            <= FRAG_IDLE;
            frag_total_m1_held  <= 4'd0;
            // v1.8.0e §25.3 (c): all 16 rows reset-written (row 0 is the
            // reset-only dummy — see the frag FSM declaration block).
            frag_pending[0]     <= {ADDR_WIDTH{1'b0}};
            frag_pending[1]     <= {ADDR_WIDTH{1'b0}};
            frag_pending[2]     <= {ADDR_WIDTH{1'b0}};
            frag_pending[3]     <= {ADDR_WIDTH{1'b0}};
            frag_pending[4]     <= {ADDR_WIDTH{1'b0}};
            frag_pending[5]     <= {ADDR_WIDTH{1'b0}};
            frag_pending[6]     <= {ADDR_WIDTH{1'b0}};
            frag_pending[7]     <= {ADDR_WIDTH{1'b0}};
            frag_pending[8]     <= {ADDR_WIDTH{1'b0}};
            frag_pending[9]     <= {ADDR_WIDTH{1'b0}};
            frag_pending[10]    <= {ADDR_WIDTH{1'b0}};
            frag_pending[11]    <= {ADDR_WIDTH{1'b0}};
            frag_pending[12]    <= {ADDR_WIDTH{1'b0}};
            frag_pending[13]    <= {ADDR_WIDTH{1'b0}};
            frag_pending[14]    <= {ADDR_WIDTH{1'b0}};
            frag_pending[15]    <= {ADDR_WIDTH{1'b0}};
            frag_tag_held    <= {TAG_WIDTH{1'b0}};
            frag_opcode_held <= 8'h00;
        end else begin
            output_valid    <= 1'b0;
            memory_req      <= 1'b0;
            error_flag      <= 1'b0;
            lower_required  <= 1'b0;
            opcode_out      <= dec_opcode;
            // v1.5 §17 — single-fragment default. Wide-output primitives
            // (future v1.x amendments) will drive multi-cycle fragment
            // sequences and set this per-fragment.
            output_frag_hdr <= 8'h00;

            // Multi-cycle MUL pipeline advance. v1.5.3a: launch gated on
            // frag_idx == FRAG_IDLE so a MUL cannot enter the pipeline
            // during a fragment-emit cycle and collide with FRAG_EMIT_HI.
            if (MUL_OPS_SUPPORTED) begin
                mul_a_p1     <= dec_input_payload;
                mul_b_p1     <= dec_eff_b_value;
                mul_tag_p1   <= dec_forwarded_tag;
                // v1.8.0c §23.10 MANDATORY MUL-launch fp-idle guard
                // (amendment 1): without !fp_busy && !fp_valid_p2 a
                // mul_valid_p2 pulse can coincide with the 1-cycle
                // fp_valid_p2 FINISH pulse and, because MUL outranks FP in
                // the output priority chain, SILENTLY drop the fp result.
                // Same silent-drop-on-busy semantics as the existing
                // frag_idx gate (pinned by
                // test_fp_mul_collision_fp_result_preserved).
                mul_valid_p1 <= pe_active && dec_valid && !dec_decode_error
                              && dec_tag_match && (dec_opcode == 8'h12)
                              && (frag_idx == FRAG_IDLE)
                              && !fp_busy && !fp_valid_p2;
                mul_result_p2 <= mul_a_p1 * mul_b_p1;
                mul_tag_p2    <= mul_tag_p1;
                mul_valid_p2  <= mul_valid_p1;
            end else begin
                mul_valid_p1 <= 1'b0;
                mul_valid_p2 <= 1'b0;
            end

            // Bit-serial DIV/MOD/DIVMOD state machine
            if (DIV_OPS_SUPPORTED) begin
                div_valid_p2 <= 1'b0;
                case (div_state)
                    DIV_IDLE: begin
                        // v1.5.3a: gate DIV launch on frag_idx == FRAG_IDLE
                        // — a new DIV entering ITER during FRAG_EMIT_HI would
                        // land its FINISH pulse 64+ cycles later during ANY
                        // subsequent fragment emit, silently dropping DIV.
                        if (pe_active && dec_valid && !dec_decode_error
                                && dec_tag_match
                                && ((dec_opcode == 8'h13) ||
                                    (dec_opcode == 8'h1C) ||
                                    (dec_opcode == 8'h1D))
                                && (frag_idx == FRAG_IDLE)) begin
                            div_b_zero    <= (dec_eff_b_value == 64'h0);
                            div_is_mod    <= (dec_opcode == 8'h1C);
                            div_is_divmod <= (dec_opcode == 8'h1D);
                            div_tag_held  <= dec_forwarded_tag;
                            if (dec_opcode == 8'h1D) begin
                                // 32-bit DIVMOD: pack the 32-bit dividend
                                // into the TOP half of the 64-bit register.
                                // The MSB-first long-division loop reads
                                // div_dividend[63] each iter, so 32 iters
                                // suffice to shift every input bit through.
                                // Quotient gathers in [31:0]; remainder is
                                // captured from the top of div_remainder.
                                div_dividend  <= {dec_input_payload[31:0], 32'h0};
                                div_divisor   <= {32'h0, dec_eff_b_value[31:0]};
                                div_iter_left <= 7'd32;
                            end else begin
                                div_dividend  <= dec_input_payload;
                                div_divisor   <= dec_eff_b_value;
                                div_iter_left <= 7'd64;
                            end
                            div_remainder <= 64'h0;
                            if (dec_eff_b_value == 64'h0) begin
                                // Skip iter — error pulse on the next cycle
                                div_state <= DIV_FINISH;
                            end else begin
                                div_state <= DIV_ITER;
                            end
                        end
                    end
                    DIV_ITER: begin
                        // One restoring-division step.
                        if (div_iter_left == 7'd0) begin
                            div_state <= DIV_FINISH;
                        end else begin
                            // shifted_rem = (rem << 1) | dividend[63]
                            // shifted_dividend = dividend << 1
                            // if (shifted_rem >= divisor):
                            //   rem      <= shifted_rem - divisor
                            //   dividend <= (shifted_dividend) | 1
                            // else:
                            //   rem      <= shifted_rem
                            //   dividend <= shifted_dividend
                            if (({div_remainder[62:0], div_dividend[63]}) >= div_divisor) begin
                                div_remainder <= {div_remainder[62:0], div_dividend[63]} - div_divisor;
                                div_dividend  <= {div_dividend[62:0], 1'b1};
                            end else begin
                                div_remainder <= {div_remainder[62:0], div_dividend[63]};
                                div_dividend  <= {div_dividend[62:0], 1'b0};
                            end
                            div_iter_left <= div_iter_left - 7'd1;
                        end
                    end
                    DIV_FINISH: begin
                        // Pulse output_valid (or error) for one cycle.
                        div_valid_p2  <= !div_b_zero;
                        div_b_zero_p2 <= div_b_zero;
                        div_tag_p2    <= div_tag_held;
                        if (div_is_divmod) begin
                            // pack {quotient[31:0], remainder[31:0]}
                            div_result_p2 <= {div_dividend[31:0], div_remainder[31:0]};
                        end else if (div_is_mod) begin
                            div_result_p2 <= div_remainder;
                        end else begin
                            div_result_p2 <= div_dividend;
                        end
                        div_state <= DIV_IDLE;
                    end
                    default: div_state <= DIV_IDLE;
                endcase
            end

            // v1.8.0c §23.10 — fp step-sequencer launch/finish strobes.
            // fp_start default-clears here (1-cycle pulse; the launch arms
            // in the case dispatch below override it on the launch edge —
            // last-assignment-wins within the block). On done: capture the
            // result into a 1-cycle fp_valid_p2 output strobe with the
            // default-clear pattern of div_valid_p2. The {32'h0, fp32}
            // upper-32-zero scalar payload convention is pinned by
            // test_fp_ieee_directed_cells_e2e.
            if (MUL_OPS_SUPPORTED) begin
                fp_start    <= 1'b0;
                fp_valid_p2 <= 1'b0;
                if (fp_done && fp_armed) begin
                    fp_armed     <= 1'b0;
                    fp_valid_p2  <= 1'b1;
                    // v1.8.0d §23.10.10(b) — result payload rows: ints
                    // (CVT F2I) sext64; f32 {32'h0, f}; f16/bf16
                    // {48'h0, h} (low32 already {16'h0, h}).
                    fp_result_p2 <= fp_res_int_sext
                                  ? {{32{fp_result_w[31]}}, fp_result_w}
                                  : {32'h0, fp_result_w};
                    fp_tag_p2    <= fp_tag_held;
                end
                // v1.8.0e §25.3 — DEQUANT lane-loop advance. fp_armed is
                // LOW for the whole loop, so per-lane done pulses land
                // HERE and never in the fp output arm (fp_valid_p2 stays
                // 0 — no spurious per-lane emits). Pack the completed
                // lane's bf16 (fp_result_w[15:0], the {16'h0, h} low-32
                // row) into the staging word; on each word's 4th lane
                // commit the assembled 64 bits (word 0 -> frag0_hold,
                // words >= 1 -> frag_pending[word] — the accumulation
                // buffer IS frag_pending). Non-final lanes relaunch with
                // a REGISTERED fp_start that lands in FP_StepSeq's first
                // idle cycle (no fp_busy gap — verified); the final
                // lane's completion cycle clears deq_loop_active and the
                // atomic handoff block below emits fragment 0.
                if (fp_done && deq_loop_active) begin
                    case (deq_lane[1:0])
                        2'd0: deq_stage[15:0]  <= fp_result_w[15:0];
                        2'd1: deq_stage[31:16] <= fp_result_w[15:0];
                        2'd2: deq_stage[47:32] <= fp_result_w[15:0];
                        2'd3: begin
                            if (deq_lane[4:2] == 3'd0)
                                frag0_hold <= {fp_result_w[15:0], deq_stage};
                            else
                                frag_pending[{1'b0, deq_lane[4:2]}]
                                    <= {fp_result_w[15:0], deq_stage};
                        end
                    endcase
                    if (deq_lane == deq_lane_last) begin
                        deq_loop_active <= 1'b0;   // handoff cycle
                    end else begin
                        deq_lane <= deq_lane_nxt;
                        fp_start <= 1'b1;          // registered relaunch
                        fp_a_q   <= deq_fp_a_nxt;
                    end
                end
            end else begin
                fp_start    <= 1'b0;
                fp_valid_p2 <= 1'b0;
            end

            // v1.5.3a/v1.7 §20/§22.18 — ABSOLUTE-PRIORITY fragment-emit
            // override. Placed at the very top of the output priority
            // chain so fragment 1 lands EXACTLY on cycle N+1 after
            // dispatch (and fragments 2/3 on N+2/N+3 for a future
            // 4-fragment v1.8.0e wave). The launch-gate below prevents
            // MUL/DIV from starting new operations while
            // frag_idx != FRAG_IDLE, so this override never collides with
            // a mul_valid_p2 or div_valid_p2 pulse (compound gate closes
            // the drain window).
            //
            // frag_idx counts UP from FRAG_EMIT_1 and returns to FRAG_IDLE
            // once it reaches frag_total_m1_held (1 for every live
            // 2-fragment emitter's single drain beat; up to 15 once the
            // v1.8.0e loop-form emitters populate rows 2..15).
            // v1.8.0e §25.3 (e): output_frag_hdr = {frag_idx,
            // frag_total_m1_held} — both nibbles now carry the full
            // 4-bit fields (the nibble positions were already reserved;
            // bit-identical to the old zero-padded pack for every
            // existing 2-fragment wave, e.g. 8'h11 at idx=1/total_m1=1).
            if (frag_idx != FRAG_IDLE) begin
                output_payload  <= frag_pending[frag_idx];
                output_tag      <= frag_tag_held;
                opcode_out      <= frag_opcode_held;
                output_frag_hdr <= {frag_idx, frag_total_m1_held};
                output_valid    <= 1'b1;
                if (frag_idx == frag_total_m1_held)
                    frag_idx <= FRAG_IDLE;
                else
                    frag_idx <= frag_idx + 4'd1;
            end
            // Output priority: MUL > DIV pipeline > case dispatch.
            else if (MUL_OPS_SUPPORTED && mul_valid_p2) begin
                output_payload <= mul_result_p2;
                output_tag     <= mul_tag_p2;
                output_valid   <= 1'b1;
                opcode_out     <= 8'h12;
            end
            else if (DIV_OPS_SUPPORTED && div_valid_p2) begin
                output_payload <= div_result_p2;
                output_tag     <= div_tag_p2;
                output_valid   <= 1'b1;
            end
            else if (DIV_OPS_SUPPORTED && div_b_zero_p2) begin
                // Divide-by-zero pulse from the FSM's FINISH stage.
                error_flag   <= 1'b1;
                output_valid <= 1'b0;
            end
            // v1.8.0c §23.10 — fp32 result arm. Priority chain is
            // frag-drain > MUL p2 > DIV p2 > FP p2 > case dispatch.
            // opcode_out <= fp_opcode_held is a DELIBERATE divergence from
            // DIV's stale-opcode quirk (the DIV arm leaves the default
            // `opcode_out <= dec_opcode` assignment standing); pinned by
            // test_fp_tag_and_opcode_out_preservation.
            else if (MUL_OPS_SUPPORTED && fp_valid_p2) begin
                output_payload <= fp_result_p2;   // {32'h0, fp32}
                output_tag     <= fp_tag_p2;
                output_valid   <= 1'b1;
                opcode_out     <= fp_opcode_held;
            end
            else if (pe_active && dec_valid) begin
                if (dec_decode_error) begin
                    error_flag   <= 1'b1;
                    output_valid <= 1'b0;
                end else if (!dec_tag_match) begin
                    output_valid <= 1'b0;
                end
                else if (!NON_MUL_OPS_SUPPORTED && !dec_is_mul_op
                                                 && !dec_is_div_op) begin
                    // M-UNIT (mul-only) and DIV-UNIT (div-only) both have
                    // NON_MUL_OPS_SUPPORTED=0; the unit that owns the
                    // current op-class still needs to handle dispatch via
                    // its own pipeline (MUL or DIV). Only opcodes that
                    // belong to NEITHER class are lowered here.
                    lower_required <= 1'b1;
                    output_valid   <= 1'b0;
                end
                else begin
                    output_tag <= dec_forwarded_tag;
                    case (dec_opcode)
                        8'h00: output_valid <= 1'b0;
                        8'h01: begin
                            output_tag     <= dec_wave_advanced_tag;
                            output_payload <= dec_input_payload;
                            output_valid   <= 1'b1;
                        end
                        8'h02, 8'h03: begin
                            output_payload <= dec_input_payload;
                            output_valid   <= 1'b1;
                        end
                        8'h04: begin
                            mem_addr   <= dec_input_payload + {32'h0, dec_eff_mem_offset};
                            memory_req <= 1'b1;
                            output_valid <= 1'b0;
                        end
                        8'h05: begin
                            mem_addr   <= dec_input_payload + {32'h0, dec_eff_mem_offset};
                            memory_req <= 1'b1;
                            output_valid <= 1'b1;
                        end
                        8'h10: begin
                            output_payload <= dec_input_payload + dec_eff_b_value;
                            output_valid   <= 1'b1;
                        end
                        8'h11: begin
                            output_payload <= dec_input_payload - dec_eff_b_value;
                            output_valid   <= 1'b1;
                        end
                        8'h12: begin // MUL — handled by pipeline
                            if (!MUL_OPS_SUPPORTED) lower_required <= 1'b1;
                            output_valid <= 1'b0;
                        end
                        8'h13: begin // DIV — handled by pipeline
                            if (!DIV_OPS_SUPPORTED) lower_required <= 1'b1;
                            output_valid <= 1'b0;
                        end
                        8'h14: begin // AND
                            output_payload <= dec_input_payload & dec_eff_b_value;
                            output_valid   <= 1'b1;
                        end
                        8'h15: begin // OR
                            output_payload <= dec_input_payload | dec_eff_b_value;
                            output_valid   <= 1'b1;
                        end
                        8'h16: begin // XOR
                            output_payload <= dec_input_payload ^ dec_eff_b_value;
                            output_valid   <= 1'b1;
                        end
                        8'h17: begin // SHL (logical shift left)
                            output_payload <= dec_input_payload << dec_eff_imm16[5:0];
                            output_valid <= 1'b1;
                        end
                        8'h18: begin // SHR (logical shift right)
                            output_payload <= dec_input_payload >> dec_eff_imm16[5:0];
                            output_valid   <= 1'b1;
                        end
                        8'h19: begin // SAR (arithmetic shift right)
                            output_payload <= $signed(dec_input_payload) >>> dec_eff_imm16[5:0];
                            output_valid   <= 1'b1;
                        end
                        8'h1A: begin // ROR
                            output_payload <= rotate_right_64(dec_input_payload, dec_eff_imm16[5:0]);
                            output_valid <= 1'b1;
                        end
                        8'h1B: begin // NEG (two's complement)
                            output_payload <= ~dec_input_payload + 64'd1;
                            output_valid <= 1'b1;
                        end
                        8'h1C: begin // MOD — handled by pipeline
                            if (!DIV_OPS_SUPPORTED) lower_required <= 1'b1;
                            output_valid <= 1'b0;
                        end
                        8'h1D: begin // DIVMOD — handled by pipeline
                            if (!DIV_OPS_SUPPORTED) lower_required <= 1'b1;
                            output_valid <= 1'b0;
                        end
                        8'h1E: begin // ROL
                            output_payload <= rotate_left_64(dec_input_payload, dec_eff_imm16[5:0]);
                            output_valid   <= 1'b1;
                        end
                        8'h1F: begin // BITREV
                            output_payload <= bit_reverse(dec_input_payload);
                            output_valid <= 1'b1;
                        end
                        8'h50: begin // NOT (bitwise complement)
                            output_payload <= ~dec_input_payload;
                            output_valid   <= 1'b1;
                        end
                        8'h51: begin // NAND
                            output_payload <= ~(dec_input_payload & dec_eff_b_value);
                            output_valid   <= 1'b1;
                        end
                        8'h52: begin // NOR
                            output_payload <= ~(dec_input_payload | dec_eff_b_value);
                            output_valid   <= 1'b1;
                        end
                        8'h53: begin // XNOR
                            output_payload <= ~(dec_input_payload ^ dec_eff_b_value);
                            output_valid   <= 1'b1;
                        end
                        8'h54: begin // POPCOUNT
                            output_payload <= popcount_64(dec_input_payload);
                            output_valid   <= 1'b1;
                        end
                        8'h55: begin // CLZ (Count Leading Zeros)
                            output_payload <= clz_64(dec_input_payload);
                            output_valid   <= 1'b1;
                        end
                        8'h56: begin // CTZ (Count Trailing Zeros)
                            output_payload <= ctz_64(dec_input_payload);
                            output_valid   <= 1'b1;
                        end
                        8'h20: begin
                            if (axis_sz(dec_eff_dim_sizes, dec_eff_imm16[1:0]) != 2'b00) begin
                                error_flag <= 1'b1; output_valid <= 1'b0;
                            end else begin
                                output_tag <= {dec_wave_number, dec_thread_id,
                                               8'h00, dec_eff_output_port_id,
                                               dec_eff_precision,
                                               dim_squeeze(dec_eff_dim_sizes, dec_eff_imm16[1:0])};
                                output_payload <= dec_input_payload;
                                output_valid <= 1'b1;
                            end
                        end
                        8'h21: begin
                            if (dec_eff_dim_sizes[7:6] != 2'b00) begin
                                error_flag <= 1'b1; output_valid <= 1'b0;
                            end else begin
                                output_tag <= {dec_wave_number, dec_thread_id,
                                               8'h00, dec_eff_output_port_id,
                                               dec_eff_precision,
                                               dim_unsqueeze(dec_eff_dim_sizes, dec_eff_imm16[1:0])};
                                output_payload <= dec_input_payload;
                                output_valid <= 1'b1;
                            end
                        end
                        8'h22: begin
                            if (elem_count(dec_eff_dim_sizes) != elem_count(dec_eff_imm16[7:0])) begin
                                error_flag <= 1'b1; output_valid <= 1'b0;
                            end else begin
                                output_tag <= {dec_wave_number, dec_thread_id,
                                               8'h00, dec_eff_output_port_id,
                                               dec_eff_precision,
                                               dec_eff_imm16[7:0]};
                                output_payload <= dec_input_payload;
                                output_valid <= 1'b1;
                            end
                        end
                        8'h23: begin
                            if ((dec_eff_imm16[7:0] == 8'h01) && (dec_eff_dim_sizes == 8'h05)) begin
                                output_payload <= permute_2x2_transpose(dec_input_payload);
                                output_tag <= {dec_wave_number, dec_thread_id,
                                               8'h00, dec_eff_output_port_id,
                                               dec_eff_precision, dec_eff_dim_sizes};
                                output_valid <= 1'b1;
                            end else begin
                                lower_required <= 1'b1; output_valid <= 1'b0;
                            end
                        end
                        8'h24: begin
                            lower_required <= 1'b1; output_valid <= 1'b0;
                        end
                        8'h25: begin
                            if ((dec_eff_imm16[3:0] == 4'd0) && (dec_eff_dim_sizes == 8'h03)
                                && ((dec_eff_imm16[7:4] == RED_OP_SUM)
                                    || (dec_eff_imm16[7:4] == RED_OP_MAX)
                                    || (dec_eff_imm16[7:4] == RED_OP_MIN))) begin
                                output_payload <= reduce_axis0_1d(dec_eff_imm16[7:4], dec_input_payload);
                                output_tag <= {dec_wave_number, dec_thread_id,
                                               8'h00, dec_eff_output_port_id,
                                               dec_eff_precision,
                                               dim_squeeze(dec_eff_dim_sizes, 2'd0)};
                                output_valid <= 1'b1;
                            end else begin
                                lower_required <= 1'b1; output_valid <= 1'b0;
                            end
                        end
                        8'h26: begin
                            // SPLAT (v1.1 amendment, 2026-07-14). Sign-extend
                            // the 8-bit signed scalar in dec_eff_imm16[7:0]
                            // to int16, then replicate across all 4 lanes of
                            // the 64-bit payload. Result tensor is 1-D of
                            // size 4 (dim_sizes = 8'h03 → first axis = 3+1 = 4
                            // elements, others = size 1).
                            //
                            // Input tensor semantics: N/A — SPLAT is a source
                            // op that generates a constant. The input payload
                            // is ignored; forwarded_tag's non-dim fields are
                            // preserved (wave_number, thread_id, port,
                            // precision).
                            //
                            // Primary use case: broadcast lowering. See
                            // `.claude-memos/einsum_trace_broadcast_analysis.md`
                            // and `wt64v1_spec.md` §14.
                            output_tag <= {dec_wave_number, dec_thread_id,
                                           8'h00, dec_eff_output_port_id,
                                           dec_eff_precision,
                                           8'h03};
                            output_payload <= {4{ {{8{dec_eff_imm16[7]}}, dec_eff_imm16[7:0]} }};
                            output_valid <= 1'b1;
                        end
                        8'h30: begin
                            if (!MUL_OPS_SUPPORTED) begin
                                lower_required <= 1'b1; output_valid <= 1'b0;
                            end else if (dec_eff_dim_sizes != 8'h05) begin
                                error_flag <= 1'b1; output_valid <= 1'b0;
                            end else begin
                                output_payload <= matmul_func(dec_input_payload, dec_input_payload_b);
                                output_valid <= 1'b1;
                            end
                        end
                        8'h31: begin
                            output_payload <= {
                                dec_input_payload[63:48] + dec_input_payload_b[63:48],
                                dec_input_payload[47:32] + dec_input_payload_b[47:32],
                                dec_input_payload[31:16] + dec_input_payload_b[31:16],
                                dec_input_payload[15: 0] + dec_input_payload_b[15: 0]
                            };
                            output_valid <= 1'b1;
                        end
                        8'h32: begin
                            // v1.5.3 §20 — two-level SUBSCRIPT dispatch.
                            // Legacy v1.0..v1.2 signatures (SUM_I..TRACE_IIJK)
                            // require `dec_eff_subscript_hi == 48'h0` (no
                            // second SUBSCRIPT EH); v1.5.3+ wide-consumer
                            // signatures (SIG_BMM_3) require non-zero hi.
                            // This guards against a malformed wave whose
                            // lo-half accidentally aliases a legacy sig.
                            if (!MUL_OPS_SUPPORTED) begin
                                lower_required <= 1'b1; output_valid <= 1'b0;
                            end else if (dec_eff_subscript_hi != 48'h0) begin
                                // v1.5.3 wide-consumer path
                                if ((dec_eff_subscript == SIG_BMM_3_LO)
                                     && (dec_eff_subscript_hi == SIG_BMM_3_HI)) begin
                                    // SIG_BMM_3: 'abcij,abcjk->abcik' at int4.
                                    // Input A + B both packed into
                                    // dec_input_payload_wide (v1.5.2 fragment
                                    // reassembly): A at wide[127:0], B at
                                    // wide[255:128] — 4-fragment wave
                                    // (frag_hdr indices 0..3). Cannot use
                                    // IMM64 chain because EINSUM (0x32) is
                                    // forbid_imm_any at EHDecode legality.
                                    // Output 128-bit split into 2 wave tokens
                                    // with frag_hdr = 8'h01, 8'h11.
                                    if (!dec_input_payload_wide_valid) begin
                                        // Illegal per §20 contract — Cluster's
                                        // wave_complete guarantees wide_valid=1
                                        // for any wide-consumer wave.
                                        error_flag   <= 1'b1;
                                        output_valid <= 1'b0;
                                    end else if (!output_regs_free) begin
                                        // Compound drain gate (per verify:fsm):
                                        // reject if any MUL/DIV pulse would
                                        // collide with fragment 0 (cycle N) or
                                        // fragment 1 (cycle N+1).
                                        lower_required <= 1'b1;
                                        output_valid   <= 1'b0;
                                    end else begin
                                        // Fragment 0 emit (a=0 batches, 4×2×2)
                                        output_payload  <= einsum_bmm_3_int4_lo(
                                            dec_input_payload_wide[127:0],
                                            dec_input_payload_wide[255:128]);
                                        output_valid    <= 1'b1;
                                        output_frag_hdr <= 8'h01;   // idx=0 total-1=1
                                        opcode_out      <= dec_opcode;
                                        // Latch fragment 1 (a=1 batches) +
                                        // tag/opcode for the N+1 override.
                                        frag_pending[1]  <= einsum_bmm_3_int4_hi(
                                            dec_input_payload_wide[127:0],
                                            dec_input_payload_wide[255:128]);
                                        frag_tag_held      <= dec_forwarded_tag;
                                        frag_opcode_held   <= dec_opcode;
                                        frag_total_m1_held <= 4'd1;
                                        frag_idx           <= FRAG_EMIT_1;
                                    end
                                end else if ((dec_eff_subscript == SIG_SCALAR_FAMILY_LO)
                                             && (dec_eff_subscript_hi[47:4] == SIG_SCALAR_FAMILY_HI_BASE)) begin
                                    // v1.6.1 §22 — 5D→scalar reduction family.
                                    // Op marker in dec_eff_subscript_hi[3:0]:
                                    //   0=SUM, 1=MAX, 2=ARGMAX, 3=L1, 4=L2SQ, 6=MIN, 7=ARGMIN.
                                    // (0x5 reserved for MEAN in 5D→4D family; unused here.)
                                    if (!dec_input_payload_wide_valid) begin
                                        error_flag   <= 1'b1;
                                        output_valid <= 1'b0;
                                    end else if (!output_regs_free) begin
                                        lower_required <= 1'b1;
                                        output_valid   <= 1'b0;
                                    end else case (dec_eff_subscript_hi[3:0])
                                        OP_SUM: begin
                                            output_payload <= einsum_sum_ijklm_int4(dec_input_payload_wide[127:0]);
                                            output_tag <= {dec_wave_number, dec_thread_id,
                                                           8'h00, dec_eff_output_port_id,
                                                           dec_eff_precision, 8'h00};
                                            output_valid <= 1'b1;
                                        end
                                        OP_MAX: begin
                                            output_payload <= einsum_max_ijklm_int4(dec_input_payload_wide[127:0]);
                                            output_tag <= {dec_wave_number, dec_thread_id,
                                                           8'h00, dec_eff_output_port_id,
                                                           dec_eff_precision, 8'h00};
                                            output_valid <= 1'b1;
                                        end
                                        OP_ARGMAX: begin
                                            output_payload <= einsum_argmax_ijklm_int4(dec_input_payload_wide[127:0]);
                                            output_tag <= {dec_wave_number, dec_thread_id,
                                                           8'h00, dec_eff_output_port_id,
                                                           dec_eff_precision, 8'h00};
                                            output_valid <= 1'b1;
                                        end
                                        OP_L1: begin
                                            output_payload <= einsum_l1_ijklm_int4(dec_input_payload_wide[127:0]);
                                            output_tag <= {dec_wave_number, dec_thread_id,
                                                           8'h00, dec_eff_output_port_id,
                                                           dec_eff_precision, 8'h00};
                                            output_valid <= 1'b1;
                                        end
                                        OP_L2SQ: begin
                                            output_payload <= einsum_l2sq_ijklm_int4(dec_input_payload_wide[127:0]);
                                            output_tag <= {dec_wave_number, dec_thread_id,
                                                           8'h00, dec_eff_output_port_id,
                                                           dec_eff_precision, 8'h00};
                                            output_valid <= 1'b1;
                                        end
                                        OP_MIN: begin
                                            output_payload <= einsum_min_ijklm_int4(dec_input_payload_wide[127:0]);
                                            output_tag <= {dec_wave_number, dec_thread_id,
                                                           8'h00, dec_eff_output_port_id,
                                                           dec_eff_precision, 8'h00};
                                            output_valid <= 1'b1;
                                        end
                                        OP_ARGMIN: begin
                                            output_payload <= einsum_argmin_ijklm_int4(dec_input_payload_wide[127:0]);
                                            output_tag <= {dec_wave_number, dec_thread_id,
                                                           8'h00, dec_eff_output_port_id,
                                                           dec_eff_precision, 8'h00};
                                            output_valid <= 1'b1;
                                        end
                                        default: begin
                                            lower_required <= 1'b1;
                                            output_valid   <= 1'b0;
                                        end
                                    endcase
                                end else if ((dec_eff_subscript == SIG_5D4D_FAMILY_LO)
                                             && (dec_eff_subscript_hi[47:4] == SIG_5D4D_FAMILY_HI_BASE)) begin
                                    // v1.6.1 §22 — 5D→4D reduction family (reduce over axis m).
                                    // Op marker: 5=MEAN is the ONLY live member (rmsnorm/
                                    // layernorm mean step). SUM/MAX/L2SQ/MIN markers were
                                    // removed pre-stable in the opcode cleanup — they now
                                    // fall to the default lower_required arm, same as any
                                    // other unknown marker. The 4D→3D family (SIG_4D3D_*)
                                    // was removed entirely in the same cleanup.
                                    if (!dec_input_payload_wide_valid) begin
                                        error_flag   <= 1'b1;
                                        output_valid <= 1'b0;
                                    end else if (!output_regs_free) begin
                                        lower_required <= 1'b1;
                                        output_valid   <= 1'b0;
                                    end else case (dec_eff_subscript_hi[3:0])
                                        OP_MEAN: begin
                                            output_payload <= einsum_mean_5d_to_4d_int4(dec_input_payload_wide[127:0]);
                                            output_tag <= {dec_wave_number, dec_thread_id,
                                                           8'h00, dec_eff_output_port_id,
                                                           dec_eff_precision, 8'h55};
                                            output_valid <= 1'b1;
                                        end
                                        default: begin
                                            lower_required <= 1'b1;
                                            output_valid   <= 1'b0;
                                        end
                                    endcase
                                end else if ((dec_eff_subscript == SIG_TRACE_IJJKL_LO)
                                             && (dec_eff_subscript_hi == SIG_TRACE_IJJKL_HI)) begin
                                    // v1.6.1 §22 — SIG_TRACE_IJJKL: 5D trace over j (variant of IIJKL).
                                    if (!dec_input_payload_wide_valid) begin
                                        error_flag   <= 1'b1;
                                        output_valid <= 1'b0;
                                    end else if (!output_regs_free) begin
                                        lower_required <= 1'b1;
                                        output_valid   <= 1'b0;
                                    end else begin
                                        output_payload <= einsum_trace_ijjkl_int4(dec_input_payload_wide[127:0]);
                                        output_tag <= {dec_wave_number, dec_thread_id,
                                                       8'h00, dec_eff_output_port_id,
                                                       dec_eff_precision, 8'h15};
                                        output_valid <= 1'b1;
                                    end
                                end else if ((dec_eff_subscript == SIG_TRACE_IIJKL_LO)
                                             && (dec_eff_subscript_hi == SIG_TRACE_IIJKL_HI)) begin
                                    // v1.5.5 §21 — SIG_TRACE_IIJKL: 5D trace.
                                    // Input A via dec_input_payload_wide[127:0]
                                    // (2-fragment wave). B unused. Output 32-bit
                                    // single-fragment (no FSM engagement).
                                    if (!dec_input_payload_wide_valid) begin
                                        // §20.7 wide-consumer contract violation.
                                        error_flag   <= 1'b1;
                                        output_valid <= 1'b0;
                                    end else if (!output_regs_free) begin
                                        // Reuse §20.6 compound drain gate — no
                                        // cycle-N+1 hazard (single-fragment
                                        // emit) but a MUL/DIV pulse on cycle N
                                        // would still clobber the output.
                                        lower_required <= 1'b1;
                                        output_valid   <= 1'b0;
                                    end else begin
                                        output_payload <= einsum_trace_iijkl_int4(
                                            dec_input_payload_wide[127:0]);
                                        output_tag     <= {dec_wave_number, dec_thread_id,
                                                           8'h00, dec_eff_output_port_id,
                                                           dec_eff_precision, 8'h15};
                                        output_valid   <= 1'b1;
                                        // output_frag_hdr default = 0x00 already
                                        // set at line ~705 — no explicit write.
                                    end
                                end else begin
                                    lower_required <= 1'b1;
                                    output_valid   <= 1'b0;
                                end
                            end else case (dec_eff_subscript)
                                SIG_SUM_I: begin
                                    output_payload <= einsum_sum_i(dec_input_payload);
                                    output_valid <= 1'b1;
                                end
                                SIG_TRACE_II: begin
                                    output_payload <= einsum_trace_ii(dec_input_payload);
                                    output_valid <= 1'b1;
                                end
                                SIG_TRANSPOSE: begin
                                    output_payload <= einsum_transpose_ij(dec_input_payload);
                                    output_valid <= 1'b1;
                                end
                                SIG_MATMUL: begin
                                    output_payload <= matmul_func(dec_input_payload, dec_input_payload_b);
                                    output_valid <= 1'b1;
                                end
                                SIG_HADAMARD: begin
                                    output_payload <= einsum_hadamard(dec_input_payload, dec_input_payload_b);
                                    output_valid <= 1'b1;
                                end
                                SIG_OUTER: begin
                                    output_payload <= einsum_outer(dec_input_payload, dec_input_payload_b);
                                    output_valid <= 1'b1;
                                end
                                SIG_PARTIAL_IJK: begin
                                    output_payload <= einsum_partial_ijk(dec_input_payload);
                                    output_valid <= 1'b1;
                                end
                                SIG_DIAGONAL: begin
                                    output_payload <= einsum_diagonal(dec_input_payload);
                                    output_valid <= 1'b1;
                                end
                                SIG_DOT: begin
                                    output_payload <= einsum_dot(dec_input_payload, dec_input_payload_b);
                                    output_valid <= 1'b1;
                                end
                                SIG_MAT_VEC: begin
                                    output_payload <= einsum_mat_vec(dec_input_payload, dec_input_payload_b);
                                    output_valid <= 1'b1;
                                end
                                SIG_BMM: begin
                                    // v1.1 amendment §14.3. Batched matmul at
                                    // int8. dim_sizes must be 0x15 (3D 2×2×2).
                                    // Result has same shape (3D 2×2×2).
                                    if (dec_eff_dim_sizes != 8'h15) begin
                                        lower_required <= 1'b1; output_valid <= 1'b0;
                                    end else begin
                                        output_payload <= einsum_bmm_int8(dec_input_payload, dec_input_payload_b);
                                        output_valid <= 1'b1;
                                    end
                                end
                                SIG_TRACE_IIJ: begin
                                    // v1.1 amendment §14.3. 3D trace w/ kept
                                    // axis j at int8. A dim_sizes must be 0x15.
                                    // Result is 1D size 2 → dim_sizes = 0x01.
                                    if (dec_eff_dim_sizes != 8'h15) begin
                                        lower_required <= 1'b1; output_valid <= 1'b0;
                                    end else begin
                                        output_payload <= einsum_trace_iij_int8(dec_input_payload);
                                        output_tag <= {dec_wave_number, dec_thread_id,
                                                       8'h00, dec_eff_output_port_id,
                                                       dec_eff_precision, 8'h01};
                                        output_valid <= 1'b1;
                                    end
                                end
                                SIG_BMM_2: begin
                                    // v1.2 amendment §15. 2-batch matmul at int4.
                                    // dim_sizes = 0x55 (4D 2×2×2×2). Same shape out.
                                    if (dec_eff_dim_sizes != 8'h55) begin
                                        lower_required <= 1'b1; output_valid <= 1'b0;
                                    end else begin
                                        output_payload <= einsum_bmm_2_int4(dec_input_payload, dec_input_payload_b);
                                        output_valid <= 1'b1;
                                    end
                                end
                                SIG_TRACE_IIJK: begin
                                    // v1.2 amendment §15. 3D trace w/ 2 kept axes.
                                    // A dim_sizes = 0x55. Result 2D 2×2 = 0x05.
                                    if (dec_eff_dim_sizes != 8'h55) begin
                                        lower_required <= 1'b1; output_valid <= 1'b0;
                                    end else begin
                                        output_payload <= einsum_trace_iijk_int4(dec_input_payload);
                                        output_tag <= {dec_wave_number, dec_thread_id,
                                                       8'h00, dec_eff_output_port_id,
                                                       dec_eff_precision, 8'h05};
                                        output_valid <= 1'b1;
                                    end
                                end
                                default: begin
                                    lower_required <= 1'b1; output_valid <= 1'b0;
                                end
                            endcase
                        end
                        8'h40, 8'h41, 8'h42: begin
                            output_payload <= dec_input_payload;
                            output_valid <= 1'b1;
                        end
                        8'h43: begin
                            if (MUL_OPS_SUPPORTED) begin
                                output_payload <= euclid_norm_sq(dec_input_payload);
                                output_valid <= 1'b1;
                            end else begin
                                lower_required <= 1'b1; output_valid <= 1'b0;
                            end
                        end
                        8'h44: begin
                            output_payload <= conjugate_fn(dec_input_payload);
                            output_valid <= 1'b1;
                        end
                        // v1.6.1b §22 — SIMD broadcast wide-consumer ops
                        // (RISC-ish norm primitives). Wide input via
                        // dec_input_payload_wide[127:0]; wide output as
                        // 2-fragment emit (reuse frag_state FSM).
                        // 0x60/61/62 SCALAR: B via dec_eff_b_value[3:0]
                        // 0x63/64/65 VEC:    V via dec_input_payload_b[63:0]
                        //   (requires F_HAS_OPB flag)
                        // (0x67 Q4.4 SCALAR removed pre-stable in the opcode
                        //   cleanup — superseded by 0x69 Q8.8.)
                        // 0x68 CACHE_LOAD_WIDE (v1.6.5c §22.16): pure
                        //   passthrough of a persisted Cluster-buffer slot
                        //   (Cluster.v resolves the CAM lookup and drives
                        //   dec_input_payload_wide/valid; a cache MISS
                        //   surfaces as dec_input_payload_wide_valid=0,
                        //   which the guard below turns into error_flag —
                        //   no separate miss signal needed). output_tag is
                        //   deliberately left at its default
                        //   dec_forwarded_tag (set above, before this case
                        //   statement) — the assembler's PRECISION-EH
                        //   dim_sizes guard on the CACHE_LOAD_WIDE
                        //   instruction is what makes that tag equal the
                        //   producer's stored frag_tag_reg; adding a
                        //   second override here would be redundant and
                        //   risks reintroducing the exact literal-drift
                        //   bug the guard fixes.
                        // 0x69 Q8.8 SCALAR (v1.6.7): B via dec_eff_b_value[15:0]
                        //   as signed Q8.8 — the surviving precision-recovery
                        //   scale mul (0x67/0x6B/0x6C removed pre-stable in
                        //   the opcode cleanup).
                        8'h60, 8'h61, 8'h62, 8'h63, 8'h64, 8'h65, 8'h68, 8'h69: begin
                            if (!dec_input_payload_wide_valid) begin
                                error_flag   <= 1'b1;
                                output_valid <= 1'b0;
                            end else if (!output_regs_free) begin
                                lower_required <= 1'b1;
                                output_valid   <= 1'b0;
                            end else begin
                                // Compute lo and hi halves per opcode
                                case (dec_opcode)
                                    8'h60: begin
                                        output_payload   <= wres_add_wide_scalar[63:0];
                                        frag_pending[1]  <= wres_add_wide_scalar[127:64];
                                    end
                                    8'h61: begin
                                        output_payload   <= wres_sub_wide_scalar[63:0];
                                        frag_pending[1]  <= wres_sub_wide_scalar[127:64];
                                    end
                                    8'h62: begin
                                        output_payload   <= wres_mul_wide_scalar[63:0];
                                        frag_pending[1]  <= wres_mul_wide_scalar[127:64];
                                    end
                                    8'h63: begin
                                        output_payload   <= wres_add_wide_vec[63:0];
                                        frag_pending[1]  <= wres_add_wide_vec[127:64];
                                    end
                                    8'h64: begin
                                        output_payload   <= wres_sub_wide_vec[63:0];
                                        frag_pending[1]  <= wres_sub_wide_vec[127:64];
                                    end
                                    8'h65: begin
                                        output_payload   <= wres_mul_wide_vec[63:0];
                                        frag_pending[1]  <= wres_mul_wide_vec[127:64];
                                    end
                                    8'h68: begin
                                        // v1.6.5c §22.16 — CACHE_LOAD_WIDE:
                                        // pure passthrough of the resolved
                                        // wide bus (Cluster.v already muxed
                                        // in the cached slot on a hit).
                                        output_payload   <= dec_input_payload_wide[63:0];
                                        frag_pending[1]  <= dec_input_payload_wide[127:64];
                                    end
                                    8'h69: begin
                                        // v1.6.7 §22.14c — Q8.8 wide-scalar mul.
                                        // B via dec_eff_b_value[15:0] as signed Q8.8.
                                        output_payload   <= wres_mul_q8_8[63:0];
                                        frag_pending[1]  <= wres_mul_q8_8[127:64];
                                    end
                                    default: ;
                                endcase
                                output_valid       <= 1'b1;
                                output_frag_hdr    <= 8'h01;   // idx=0, total_m1=1
                                opcode_out         <= dec_opcode;
                                frag_tag_held      <= dec_forwarded_tag;
                                frag_opcode_held   <= dec_opcode;
                                frag_total_m1_held <= 4'd1;
                                frag_idx           <= FRAG_EMIT_1;
                            end
                        end
                        // (8'h66 SCALAR_RSQRT arm removed pre-stable in the
                        // opcode cleanup — 0x66 is now a decode_error at
                        // EHDecode via the regenerated opcode_supported.)
                        // v1.6.5d §22.17 — FRAG_INVAL: single-cycle ack of
                        // a Cluster-buffer slot invalidate. Deliberately
                        // STANDALONE (outside the 8'h60-69 shared wide-emit
                        // case-item group above) rather than "mirroring
                        // 0x68" into that group: the shared group's
                        // epilogue unconditionally drives output_frag_hdr
                        // and frag_state<=FRAG_EMIT_HI, which would emit a
                        // SECOND (garbage) fragment on the next cycle from
                        // frag_hi_pending/frag_tag_held — registers
                        // FRAG_INVAL never writes. Reusing
                        // dec_input_payload_wide_valid as the hit/miss
                        // signal is intentional: Cluster.v's inval_hit
                        // (mirroring cache_hit's CAM reuse) drives it, and
                        // this signal is opcode-independent — latched and
                        // forwarded unconditionally by EHDecode regardless
                        // of dec_opcode. output_tag/output_frag_hdr are
                        // left at their pre-case defaults (dec_forwarded_tag,
                        // 8'h00) since an ack carries no payload of its own.
                        8'h6A: begin
                            if (!dec_input_payload_wide_valid) begin
                                error_flag   <= 1'b1;
                                output_valid <= 1'b0;
                            end else begin
                                output_valid <= 1'b1;
                            end
                        end
                        // (The old 8'h6B WIDEN 4-fragment arm — with its
                        // 8'h6C REQUANTIZE companion — was removed
                        // pre-stable in the opcode cleanup; 0x6C stays
                        // decode_error at EHDecode.)
                        // v1.8.0e §25.2.3 — 0x6B GAMMA_MUL_W: pre-stable
                        // REALLOCATION of the retired code point (§12a
                        // rule 4, slot reuse recorded in the isa JSON
                        // notes + the domain_version-3 truth-table
                        // recapture). MU-hosted exact widening per-lane
                        // int4 x int4 -> int8: A = 16 int4 lanes in
                        // payload_a (single-fragment op — NO wide_valid
                        // guard, the STORE_QUANT precedent), gamma = 16
                        // int4 lanes via IMM64 XOR OPREF (dec_eff_b_value
                        // — the alu-binary XOR trap at EHDecode
                        // guarantees exactly one source, so there is no
                        // missing-B rung). EXACT (|p| <= 64 ⊂ int8):
                        // rounding-free, saturation-free, combinational
                        // 1-cycle (wres_gamma_w, LUT-structural
                        // shift-adds — the §25.5.1 DSP-suppression
                        // mechanism); 128b out = 2 fragments via the
                        // widened frag FSM (the 0x60-69 emit epilogue
                        // verbatim). Launch ladder: MU gate ->
                        // busy-reject (lower_required, VDOT rung) ->
                        // emit. Reachability rides the twin-classifier
                        // lockstep edit (is_mul_op/dec_is_mul_op +=
                        // {0x6B, 0x70, 0x78, 0x79}, §25.3) landing with
                        // the 0e1 integration commit.
                        8'h6B: begin
                            if (!MUL_OPS_SUPPORTED) begin
                                lower_required <= 1'b1; output_valid <= 1'b0;
                            end else if (!output_regs_free) begin
                                lower_required <= 1'b1;
                                output_valid   <= 1'b0;
                            end else begin
                                output_payload     <= wres_gamma_w[63:0];
                                output_valid       <= 1'b1;
                                output_frag_hdr    <= 8'h01;  // idx=0 total_m1=1
                                opcode_out         <= dec_opcode;
                                frag_pending[1]    <= wres_gamma_w[127:64];
                                frag_tag_held      <= dec_forwarded_tag;
                                frag_opcode_held   <= dec_opcode;
                                frag_total_m1_held <= 4'd1;
                                frag_idx           <= FRAG_EMIT_1;
                            end
                        end
                        // v1.8.0a/0b §23.9 — remaining WIDE-ACC block STUBS
                        // (0x71/0x72/0x7C graduated to real datapaths in
                        // v1.8.0b, 0x74/0x75/0x76 in v1.8.0c, 0x73/0x77 in
                        // v1.8.0d, 0x79 in v1.8.0e 0e1 — see their
                        // standalone arms below). Decode-legal
                        // (opcode_supported + EH shape +
                        // mode-byte ROM all pass at EHDecode) but not yet
                        // implemented — capability absence, so this arm is
                        // exactly the shipped BCAST 0x24 body: lower_required,
                        // error_flag untouched. An EXPLICIT arm, never
                        // fall-through: the case default below raises
                        // error_flag, which would misclassify
                        // legal-but-unimplemented as malformed (the invariant
                        // the suite encodes: unsupported-but-legal =>
                        // lower_required). Membership is pinned by the
                        // all-ops live-extraction test — adding an op to
                        // isa/wt64v1_isa.json without listing it here falls
                        // to the default arm and fails that test.
                        // v1.8.0e 0e1 INTEGRATION: 0x78 DEQUANT
                        // graduated to its lane-loop launch arm below
                        // (the sequencer-side OPS_DEQ program landed one
                        // commit earlier). 0x70 VFMA_ACC is 0e2;
                        // 0x7D/0x7E stay unscheduled.
                        8'h70, 8'h7D, 8'h7E: begin
                            lower_required <= 1'b1; output_valid <= 1'b0;
                        end
                        // v1.8.0b §23.9 — VDOT_ACC: stateless 4-fragment
                        // wide dot. A=wide[127:0], B=wide[255:128]
                        // (SIG_BMM_3 input pattern), carry-in =
                        // dec_eff_b_value (IMM XOR OPREF, alu_binary).
                        // Emits r=(sext64(dot)+c) mod 2^64 immediately —
                        // full 64-bit payload, scalar tag rebuild. NO
                        // accumulator state anywhere.
                        8'h71: begin
                            if (!MUL_OPS_SUPPORTED) begin
                                // MAC tree lives on MATMUL_UNITs only.
                                lower_required <= 1'b1; output_valid <= 1'b0;
                            end else if (!dec_input_payload_wide_valid) begin
                                error_flag   <= 1'b1;
                                output_valid <= 1'b0;
                            end else if (!output_regs_free) begin
                                lower_required <= 1'b1;
                                output_valid   <= 1'b0;
                            end else begin
                                output_payload <= wres_vdot_r;
                                output_valid   <= 1'b1;
                                output_tag <= {dec_wave_number, dec_thread_id,
                                               8'h00, dec_eff_output_port_id,
                                               dec_eff_precision, 8'h00};
                            end
                        end
                        // v1.8.0b §23.9 — ACC_REDUCE: stateless reduction
                        // over wide[127:0]. Sub-op = imm16[7:4] per the
                        // generated acc_reduce_op_codes (absent imm16 =
                        // 0 = SUM — the monotonic loosening default);
                        // imm16[3:0] reserved-zero; unknown sub-op →
                        // lower_required, never error_flag. MEAN =
                        // RNE(sum/N) ties-to-even, full lane set only.
                        8'h72: begin
                            if (!MUL_OPS_SUPPORTED) begin
                                lower_required <= 1'b1; output_valid <= 1'b0;
                            end else if (!dec_input_payload_wide_valid) begin
                                error_flag   <= 1'b1;
                                output_valid <= 1'b0;
                            end else if (!output_regs_free) begin
                                lower_required <= 1'b1;
                                output_valid   <= 1'b0;
                            end else if (dec_eff_imm16[3:0] != 4'h0) begin
                                lower_required <= 1'b1;
                                output_valid   <= 1'b0;
                            end else begin
                                case (dec_eff_imm16[7:4])
                                    ACC_RED_OP_SUM: begin
                                        output_payload <= {{32{wres_acc_sum[31]}}, wres_acc_sum};
                                        output_valid   <= 1'b1;
                                    end
                                    ACC_RED_OP_MAX: begin
                                        output_payload <= {{32{wres_acc_max[31]}}, wres_acc_max};
                                        output_valid   <= 1'b1;
                                    end
                                    ACC_RED_OP_L2SQ: begin
                                        output_payload <= {{32{wres_acc_l2sq[31]}}, wres_acc_l2sq};
                                        output_valid   <= 1'b1;
                                    end
                                    ACC_RED_OP_MEAN: begin
                                        output_payload <= {{32{wres_acc_mean[31]}}, wres_acc_mean};
                                        output_valid   <= 1'b1;
                                    end
                                    default: begin
                                        lower_required <= 1'b1;
                                        output_valid   <= 1'b0;
                                    end
                                endcase
                                if (dec_eff_imm16[7:4] == ACC_RED_OP_SUM
                                 || dec_eff_imm16[7:4] == ACC_RED_OP_MAX
                                 || dec_eff_imm16[7:4] == ACC_RED_OP_L2SQ
                                 || dec_eff_imm16[7:4] == ACC_RED_OP_MEAN) begin
                                    output_tag <= {dec_wave_number, dec_thread_id,
                                                   8'h00, dec_eff_output_port_id,
                                                   dec_eff_precision, 8'h00};
                                end
                            end
                        end
                        // v1.8.0c §23.10 — FSCALAR: fp32 scalar A op B,
                        // sub-op imm16[7:4] per the generated
                        // fscalar_op_codes (absent imm16 = 0 = FS_ADD —
                        // monotonic loosening default); B = payload_b
                        // (eff_b_value is NEVER read); FS_FMA addend C =
                        // payload_a[63:32]. Launch ladder (4 rungs, order
                        // normative §23.10.1): MU gate -> busy-reject
                        // (VDOT pattern — a gated op arriving during a
                        // 5-34 cycle fp flight gets lower_required, NEVER
                        // the DIV silent-swallow) -> decode guards ->
                        // launch (register-load only; FP_StepSeq walks the
                        // step program and fp_valid_p2 returns the result
                        // through the output priority chain above).
                        8'h74: begin
                            if (!MUL_OPS_SUPPORTED) begin
                                // fp step sequencer lives on the MU only.
                                lower_required <= 1'b1; output_valid <= 1'b0;
                            end else if (!output_regs_free) begin
                                lower_required <= 1'b1;
                                output_valid   <= 1'b0;
                            end else if (dec_eff_imm16[3:0] != 4'h0) begin
                                // imm16[3:0] reserved-zero (0x72 precedent)
                                lower_required <= 1'b1;
                                output_valid   <= 1'b0;
                            end else if (dec_eff_imm16[7:4] > 4'h4) begin
                                // unknown sub-op 0x5-0xF -> lower_required,
                                // never error_flag (capability absence).
                                lower_required <= 1'b1;
                                output_valid   <= 1'b0;
                            end else if (!dec_input_payload_b_valid) begin
                                // Missing-B: malformed program — a
                                // deterministic error_flag, NOT capability
                                // absence (§23.10.2 dispatch-side guard;
                                // first consumer of the
                                // dec_input_payload_b_valid input).
                                error_flag   <= 1'b1;
                                output_valid <= 1'b0;
                            end else begin
                                fp_start       <= 1'b1;
                                fp_a_q         <= dec_input_payload[31:0];
                                fp_c_q         <= dec_input_payload[63:32];
                                fp_b_q         <= dec_input_payload_b[31:0];
                                fp_subop_q     <= dec_eff_imm16[7:4];
                                fp_armed       <= 1'b1;
                                fp_opcode_held <= dec_opcode;
                                // scalar dim=0x00 tag rebuild (VDOT arm
                                // convention); tag[15:8] carries the mode
                                // byte verbatim.
                                fp_tag_held <= {dec_wave_number, dec_thread_id,
                                                8'h00, dec_eff_output_port_id,
                                                dec_eff_precision, 8'h00};
                                output_valid   <= 1'b0;
                            end
                        end
                        // v1.8.0c §23.10.3 — FRSQRT32: strictly port-only
                        // unary fp32 rsqrt (LUT seed + 3 NR iterations,
                        // <=2 ulp). Same ladder, no extra decode guards.
                        8'h75: begin
                            if (!MUL_OPS_SUPPORTED) begin
                                lower_required <= 1'b1; output_valid <= 1'b0;
                            end else if (!output_regs_free) begin
                                lower_required <= 1'b1;
                                output_valid   <= 1'b0;
                            end else begin
                                fp_start       <= 1'b1;
                                fp_a_q         <= dec_input_payload[31:0];
                                fp_b_q         <= 32'h0;
                                fp_c_q         <= 32'h0;
                                fp_subop_q     <= 4'h0;
                                fp_armed       <= 1'b1;
                                fp_opcode_held <= dec_opcode;
                                fp_tag_held <= {dec_wave_number, dec_thread_id,
                                                8'h00, dec_eff_output_port_id,
                                                dec_eff_precision, 8'h00};
                                output_valid   <= 1'b0;
                            end
                        end
                        // v1.8.0c §23.10.4 — FEXP2_32: strictly port-only
                        // unary fp32 exp2 (degree-6 Horner + integer
                        // bypass, <=2 ulp). Same ladder, no extra guards.
                        8'h76: begin
                            if (!MUL_OPS_SUPPORTED) begin
                                lower_required <= 1'b1; output_valid <= 1'b0;
                            end else if (!output_regs_free) begin
                                lower_required <= 1'b1;
                                output_valid   <= 1'b0;
                            end else begin
                                fp_start       <= 1'b1;
                                fp_a_q         <= dec_input_payload[31:0];
                                fp_b_q         <= 32'h0;
                                fp_c_q         <= 32'h0;
                                fp_subop_q     <= 4'h0;
                                fp_armed       <= 1'b1;
                                fp_opcode_held <= dec_opcode;
                                fp_tag_held <= {dec_wave_number, dec_thread_id,
                                                8'h00, dec_eff_output_port_id,
                                                dec_eff_precision, 8'h00};
                                output_valid   <= 1'b0;
                            end
                        end
                        // v1.8.0d §23.10.10(c) — ACC_ELEMWISE: fused
                        // round-once fp32 FMA a*B[63:32]+B[31:0], OPREF
                        // form ONLY (OPS_ACCEW rides the FS_FMA-shaped
                        // step program). Launch ladder = the 0x74/0x75
                        // mirror + the OPREF-only rung: ANY imm present
                        // -> lower_required (capability absence — the
                        // sub-op table was deleted; an imm carve-out
                        // under EHDecode's alu_binary XOR trap would be
                        // decode_error, and this is NOT that). OPREF
                        // presence = dec_eff_opref_kind[3] (the v1.8.0d
                        // {presence, src_kind} packing — kind 0 direct-
                        // payload_b OPREF would otherwise alias the imm
                        // form's 4'h0). Under the XOR trap, a clean
                        // decode of this alu-binary opcode has EXACTLY
                        // one of {imm, OPREF}, so !bit3 == imm present.
                        8'h73: begin
                            if (!MUL_OPS_SUPPORTED) begin
                                lower_required <= 1'b1; output_valid <= 1'b0;
                            end else if (!output_regs_free) begin
                                lower_required <= 1'b1;
                                output_valid   <= 1'b0;
                            end else if (!dec_eff_opref_kind[3]) begin
                                // imm16/imm32/imm64 form — implemented
                                // capability is OPREF-only (§23.10.10(c)).
                                lower_required <= 1'b1;
                                output_valid   <= 1'b0;
                            end else begin
                                fp_start       <= 1'b1;
                                fp_a_q         <= dec_input_payload[31:0];
                                fp_b_q         <= dec_eff_b_value[63:32];
                                fp_c_q         <= dec_eff_b_value[31:0];
                                fp_subop_q     <= 4'h0;
                                fp_dtype_q     <= dec_eff_precision[3:0];
                                fp_armed       <= 1'b1;
                                fp_opcode_held <= dec_opcode;
                                fp_tag_held <= {dec_wave_number, dec_thread_id,
                                                8'h00, dec_eff_output_port_id,
                                                dec_eff_precision, 8'h00};
                                output_valid   <= 1'b0;
                            end
                        end
                        // v1.8.0d §23.10.10(b) — CVT: six scalar
                        // conversions on the MU step sequencer (OPS_CVT).
                        // Sub-op = imm16[7:4] from the generated
                        // cvt_op_codes (absent imm16 = WIDEN_TO_F32, the
                        // monotonic default); dtype = the mode byte's
                        // dtype nibble (ROM-legal set {0,1,2,3,4}; 0x4 =
                        // accumulator-format integer endpoint, direction
                        // from the sub-op — pin 10). eff_b_value is NEVER
                        // read (imm32/imm64 asm-forbidden/RTL-tolerated,
                        // FSCALAR semantics). Ladder rungs are 0x72's
                        // exactly: imm16[3:0]/[15:8] reserved-zero and
                        // sub-op > NARROW_FROM_F32 -> lower_required,
                        // never error_flag. int64 I2F ingress is the
                        // pinned FSCALAR-style split: payload[63:32] ->
                        // c_in, payload[31:0] -> a_in.
                        8'h77: begin
                            if (!MUL_OPS_SUPPORTED) begin
                                lower_required <= 1'b1; output_valid <= 1'b0;
                            end else if (!output_regs_free) begin
                                lower_required <= 1'b1;
                                output_valid   <= 1'b0;
                            end else if (dec_eff_imm16[3:0] != 4'h0
                                      || dec_eff_imm16[15:8] != 8'h0) begin
                                lower_required <= 1'b1;
                                output_valid   <= 1'b0;
                            end else if (dec_eff_imm16[7:4] > CVT_NARROW_FROM_F32) begin
                                lower_required <= 1'b1;
                                output_valid   <= 1'b0;
                            end else begin
                                fp_start       <= 1'b1;
                                fp_a_q         <= dec_input_payload[31:0];
                                fp_b_q         <= 32'h0;
                                fp_c_q         <= dec_input_payload[63:32];
                                fp_subop_q     <= dec_eff_imm16[7:4];
                                fp_dtype_q     <= dec_eff_precision[3:0];
                                fp_armed       <= 1'b1;
                                fp_opcode_held <= dec_opcode;
                                fp_tag_held <= {dec_wave_number, dec_thread_id,
                                                8'h00, dec_eff_output_port_id,
                                                dec_eff_precision, 8'h00};
                                output_valid   <= 1'b0;
                            end
                        end
                        // v1.8.0e §25.2.2 — 0x78 DEQUANT: int4/int8
                        // lanes x the fp32 broadcast scale -> bf16
                        // (dest bf16-ONLY in 0e; the mode dtype names
                        // the SOURCE — int4-32 form emits 8 fragments,
                        // int8-16 form emits 4). LAUNCH ARM ONLY: the
                        // per-lane compute is the fused FP_StepSeq
                        // OPS_DEQ program (one launch per lane, round-
                        // once bf16 pack inside the sequencer); the
                        // lane-loop advance lives in the fp strobe
                        // block above and the loop-completion frag0
                        // handoff in the atomic block below (§25.3).
                        // Launch ladder (0x79 mirror): MU gate ->
                        // missing-wide error (§20 wave contract — A is
                        // a 2-fragment 128b wave for BOTH forms) ->
                        // busy-reject (lower_required, VDOT rung) ->
                        // missing-scale error_flag (the fp32 scale
                        // rides ext_payload_b + valid on the wave-
                        // COMPLETING fragment beat, 0x63-65 precedent;
                        // beat placement is an SDK/NoC contract pin) ->
                        // launch (register-load only: A(128b) + scale +
                        // tag captured into MU-local regs — the 0x74
                        // idiom, EHDecode is cluster-shared). fp_armed
                        // deliberately NOT set: per-lane done pulses
                        // are diverted from the fp output arm (§25.3
                        // loop suppression). Legal source dtypes {int4,
                        // int8} are ROM-enforced at EHDecode, so the
                        // int8/int4 select below is total. Reachability
                        // rides the twin-classifier lockstep edit.
                        8'h78: begin
                            if (!MUL_OPS_SUPPORTED) begin
                                lower_required <= 1'b1; output_valid <= 1'b0;
                            end else if (!dec_input_payload_wide_valid) begin
                                error_flag   <= 1'b1;
                                output_valid <= 1'b0;
                            end else if (!output_regs_free) begin
                                lower_required <= 1'b1;
                                output_valid   <= 1'b0;
                            end else if (!dec_input_payload_b_valid) begin
                                error_flag   <= 1'b1;   // missing scale
                                output_valid <= 1'b0;
                            end else begin
                                fp_start   <= 1'b1;     // lane 0 launch
                                fp_a_q     <= (dec_eff_precision[3:0] == 4'h1)
                                            ? {24'h0, dec_input_payload_wide[7:0]}
                                            : {28'h0, dec_input_payload_wide[3:0]};
                                fp_b_q     <= dec_input_payload_b[31:0];
                                fp_c_q     <= 32'h0;
                                fp_subop_q <= 4'h0;
                                fp_dtype_q <= dec_eff_precision[3:0];
                                fp_opcode_held <= dec_opcode;
                                // loop-diverted: fp_armed stays 0
                                deq_a_q         <= dec_input_payload_wide[127:0];
                                deq_is_int8     <= (dec_eff_precision[3:0] == 4'h1);
                                deq_lane        <= 5'd0;
                                deq_loop_active <= 1'b1;
                                // tag/opcode capture at launch is safe:
                                // every frag-emitting dispatch is
                                // busy-rejected while deq_loop_active
                                // (output_regs_free covers the loop).
                                frag_tag_held    <= dec_forwarded_tag;
                                frag_opcode_held <= dec_opcode;
                                output_valid   <= 1'b0;
                            end
                        end
                        // v1.8.0e §25.2.1 — 0x79 FMINMAX: frozen
                        // IEEE-2019 minimumNumber/maximumNumber, 4 f32
                        // lanes (128b = 2-fragment wave in) vs the ONE
                        // broadcast B on dec_input_payload_b (FSCALAR-
                        // clone legality re-row: B port ONLY — the
                        // alu-binary XOR trap stays dormant; OPREF-B is
                        // a recorded post-0e loosening). Combinational
                        // arm (wres_fminmax — the dedicated offset-key
                        // comparator cells, one unsigned 32b compare per
                        // lane, signed-int-tree reuse forbidden), zero
                        // FP_StepSeq contact; 128b out = 2 fragments via
                        // the widened frag FSM. Launch ladder (0x74
                        // mirror + the wide-input guard): MU gate ->
                        // missing-wide error (§20 wave contract) ->
                        // busy-reject -> imm16[3:0]/[15:8] reserved-zero
                        // and sub-op > MAXIMUMNUM -> lower_required ->
                        // missing-B error_flag (0x74 idiom) -> emit.
                        // Reachability rides the twin-classifier
                        // lockstep edit (§25.3, 0e1 integration commit).
                        8'h79: begin
                            if (!MUL_OPS_SUPPORTED) begin
                                lower_required <= 1'b1; output_valid <= 1'b0;
                            end else if (!dec_input_payload_wide_valid) begin
                                error_flag   <= 1'b1;
                                output_valid <= 1'b0;
                            end else if (!output_regs_free) begin
                                lower_required <= 1'b1;
                                output_valid   <= 1'b0;
                            end else if (dec_eff_imm16[3:0] != 4'h0
                                      || dec_eff_imm16[15:8] != 8'h0) begin
                                lower_required <= 1'b1;
                                output_valid   <= 1'b0;
                            end else if (dec_eff_imm16[7:4] > FMM_MAXIMUMNUM) begin
                                lower_required <= 1'b1;
                                output_valid   <= 1'b0;
                            end else if (!dec_input_payload_b_valid) begin
                                error_flag   <= 1'b1;
                                output_valid <= 1'b0;
                            end else begin
                                output_payload     <= wres_fminmax[63:0];
                                output_valid       <= 1'b1;
                                output_frag_hdr    <= 8'h01;  // idx=0 total_m1=1
                                opcode_out         <= dec_opcode;
                                frag_pending[1]    <= wres_fminmax[127:64];
                                frag_tag_held      <= dec_forwarded_tag;
                                frag_opcode_held   <= dec_opcode;
                                frag_total_m1_held <= 4'd1;
                                frag_idx           <= FRAG_EMIT_1;
                            end
                        end
                        // v1.8.0b §23.9 — STORE_QUANT: scalar int-dest
                        // requant, out = clamp_dtype(RNE(x >> s)),
                        // s = imm16[5:0] (absent = 0 = pure clamp).
                        // L-PE hosted (no multipliers, no MUL prologue),
                        // single-fragment op (NO wide_valid guard — that
                        // would error every legal dispatch). mem EH
                        // (if present) is IGNORED in v1.8.0b — reserved
                        // for the v1.8.0d memory-destination store form;
                        // memory_req is NEVER asserted here. dtype
                        // 0x2/0x3 (f16/bf16) lower_required until 0d.
                        // output_payload assigned EXPLICITLY (the 0x05
                        // stale-payload copy trap).
                        8'h7C: begin
                            if (!output_regs_free) begin
                                lower_required <= 1'b1;
                                output_valid   <= 1'b0;
                            end else if (dec_eff_imm16[15:6] != 10'h0) begin
                                lower_required <= 1'b1;
                                output_valid   <= 1'b0;
                            end else if (dec_eff_precision[3:0] == 4'h0) begin
                                output_payload <= wres_sq_int4;
                                output_valid   <= 1'b1;
                                output_tag <= {dec_wave_number, dec_thread_id,
                                               8'h00, dec_eff_output_port_id,
                                               dec_eff_precision, 8'h00};
                            end else if (dec_eff_precision[3:0] == 4'h1) begin
                                output_payload <= wres_sq_int8;
                                output_valid   <= 1'b1;
                                output_tag <= {dec_wave_number, dec_thread_id,
                                               8'h00, dec_eff_output_port_id,
                                               dec_eff_precision, 8'h00};
                            end else if (dec_eff_imm16[5:0] != 6'h0) begin
                                // v1.8.0d §23.10.10(d) — fp-dest reserved
                                // rung: the int forms' shift field s =
                                // imm16[5:0] is meaningless for an fp
                                // destination, so nonzero bits there are
                                // reserved -> lower_required (mirrors the
                                // imm16[15:6] rung above; together the
                                // fp-dest forms require imm16 == 0/absent).
                                lower_required <= 1'b1;
                                output_valid   <= 1'b0;
                            end else begin
                                // v1.8.0d §23.10.10(d) — fp-dest packer
                                // (dtype 0x2 f16 / 0x3 bf16; the mode-byte
                                // ROM admits no other dtype here). One
                                // shared narrow function + DAZ-at-source
                                // (wres_sq_* wires above) == 0x77
                                // NARROW_FROM_F32 bit-identity, all 2^32
                                // inputs. Result row {48'h0, h}; 0 added
                                // cycles (combinational, same-cycle emit
                                // as the int arms).
                                output_payload <= {48'h0,
                                    (dec_eff_precision[3:0] == 4'h3)
                                        ? wres_sq_bf16 : wres_sq_f16};
                                output_valid   <= 1'b1;
                                output_tag <= {dec_wave_number, dec_thread_id,
                                               8'h00, dec_eff_output_port_id,
                                               dec_eff_precision, 8'h00};
                            end
                        end
                        default: begin
                            output_valid <= 1'b0;
                            error_flag <= 1'b1;
                        end
                    endcase
                end
            end

            // -----------------------------------------------------------------
            // v1.8.0e §25.3 — DEQUANT loop-completion frag0_hold handoff
            // (ATOMIC, pinned). On the FINAL lane's completion cycle —
            // while deq_loop_active still holds output_regs_free low, so
            // this cycle has NO dispatch-launch window — emit fragment 0
            // from frag0_hold with hdr {4'd0, total_m1} and enter the
            // drain by writing frag_idx <= FRAG_EMIT_1 (the SYMBOL — the
            // lint enforces discoverability) + frag_total_m1_held in
            // this same begin/end block (lint co-location). Rows 1..N-1
            // then drain 1/cycle through the untouched priority
            // override. Loop-form fragment 0 emits at LOOP COMPLETION,
            // never at dispatch (§25.6 item 8 invariant; row 0 of
            // frag_pending stays the reset-only dummy).
            //
            // Placed AFTER the dispatch chain DELIBERATELY (last-
            // assignment-wins): a mul-class dispatch landing on this
            // exact cycle still walks its busy-reject rung above
            // (loudly lower_required — never launched, output_regs_free
            // is low), and this block then reclaims the output regs for
            // the fragment-0 beat. The drain override cannot be active
            // this cycle (frag_idx is FRAG_IDLE throughout the loop)
            // and no MUL/DIV/FP pulse can coincide (their launches are
            // all busy-rejected during the loop; fp_valid_p2 never
            // fires with fp_armed low).
            // -----------------------------------------------------------------
            if (MUL_OPS_SUPPORTED && fp_done && deq_loop_active
                    && (deq_lane == deq_lane_last)) begin
                output_payload  <= frag0_hold;
                output_tag      <= frag_tag_held;
                opcode_out      <= frag_opcode_held;
                output_frag_hdr <= {4'd0, deq_total_m1};
                output_valid    <= 1'b1;
                frag_total_m1_held <= deq_total_m1;
                frag_idx           <= FRAG_EMIT_1;
            end
        end
    end

    // v1.6.6 §22.14 — pe_ready back-pressure signal (combinational).
    // Same compound as the internal drain gate (8-term since v1.8.0c: the
    // fp step sequencer's fp_busy/fp_valid_p2 joined the expression, so
    // pe_ready deasserts for the whole 5-34 cycle fp flight; 9-term since
    // v1.8.0e: deq_loop_active covers the DEQUANT lane loop, so pe_ready
    // stays low for the whole ~100-300 cycle loop + drain window — the
    // §25.4 MU-occupancy re-acceptance, observe-only as before). Upstream
    // fabric can observe this to STALL new dispatches instead of retrying
    // after lower_required. MVP: observe-only, no ext_valid gating change.
    assign pe_ready = output_regs_free;

endmodule

/* verilator lint_on UNUSEDSIGNAL */
