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
//   MUL_OPS_SUPPORTED      — when 0, MUL/MATMUL/EINSUM/EUCLID_NORM
//                            short-circuit to lower_required and Vivado
//                            DCEs the matmul/einsum-mul helpers + 64-bit
//                            mul pipeline.
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
    // v1.6.2 §22.13 — 4D→3D reduction family. Input via legacy 64-bit
    // dec_input_payload (zero-padded wide[63:0] on fabric side; wide_valid
    // guard skipped in dispatch). A_hi = 0x0004 as family discriminator
    // (mirrors 5D4D's A_hi=0x0005) — guarantees subscript_hi != 48'h0 for
    // any 4D-family wave, preventing OP_SUM (marker=0x0) legacy fall-through
    // bug (workflow adversarial review, wi87dl8lh).
    localparam [47:0] SIG_4D3D_FAMILY_LO      = {16'h4321, 16'h0000, 16'h0321};
    localparam [43:0] SIG_4D3D_FAMILY_HI_BASE = {16'h0004, 16'h0000, 12'h000};
    // Op-marker constants (family-local nibbles)
    localparam [3:0] OP_SUM     = 4'h0;
    localparam [3:0] OP_MAX     = 4'h1;
    localparam [3:0] OP_ARGMAX  = 4'h2;
    localparam [3:0] OP_L1      = 4'h3;
    localparam [3:0] OP_L2SQ    = 4'h4;
    localparam [3:0] OP_MEAN    = 4'h5;
    localparam [3:0] OP_MIN     = 4'h6;
    localparam [3:0] OP_ARGMIN  = 4'h7;
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

    // 5D→4D SUM: reduce over axis m. R[idx4] = A[idx4*2] + A[idx4*2+1] mod 2^4.
    // idx4 = i*8 + j*4 + k*2 + l (16 output nibbles = 64-bit).
    function [ADDR_WIDTH-1:0] einsum_sum_5d_to_4d_int4;
        input [127:0] a;
        reg [3:0] r [0:15];
        reg [63:0] out;
        integer idx;
        begin
            for (idx = 0; idx < 16; idx = idx + 1) begin
                r[idx] = a[idx*8 +: 4] + a[idx*8 + 4 +: 4];
            end
            out = 64'h0;
            for (idx = 0; idx < 16; idx = idx + 1)
                out[idx*4 +: 4] = r[idx];
            einsum_sum_5d_to_4d_int4 = out;
        end
    endfunction

    // 5D→4D MAX: signed pairwise max over m. Tie: prefer m=0.
    function [ADDR_WIDTH-1:0] einsum_max_5d_to_4d_int4;
        input [127:0] a;
        reg signed [3:0] a0, a1, rm;
        reg [3:0] r [0:15];
        reg [63:0] out;
        integer idx;
        begin
            for (idx = 0; idx < 16; idx = idx + 1) begin
                a0 = $signed(a[idx*8 +: 4]);
                a1 = $signed(a[idx*8 + 4 +: 4]);
                rm = (a0 >= a1) ? a0 : a1;
                r[idx] = rm[3:0];
            end
            out = 64'h0;
            for (idx = 0; idx < 16; idx = idx + 1)
                out[idx*4 +: 4] = r[idx];
            einsum_max_5d_to_4d_int4 = out;
        end
    endfunction

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

    // 5D→4D L2SQ: sum of squares over m. Each pair contributes A0²+A1² ∈ [0,128].
    // Truncate to int4 for downstream chaining (SDK expects int4 or handles overflow).
    // For LayerNorm variance: SDK typically wants int8 accumulation; this int4
    // form is the naive baseline. v1.6.2 candidate: int8-widened variant.
    function [ADDR_WIDTH-1:0] einsum_l2sq_5d_to_4d_int4;
        input [127:0] a;
        reg signed [3:0] a0, a1;
        reg signed [7:0] sq0, sq1;
        reg [7:0]  sum8;
        reg [3:0] r [0:15];
        reg [63:0] out;
        integer idx;
        begin
            for (idx = 0; idx < 16; idx = idx + 1) begin
                a0   = $signed(a[idx*8 +: 4]);
                a1   = $signed(a[idx*8 + 4 +: 4]);
                sq0  = a0 * a0;
                sq1  = a1 * a1;
                sum8 = sq0[7:0] + sq1[7:0];
                r[idx] = sum8[3:0];   // truncate to int4 (spec §22 caveat)
            end
            out = 64'h0;
            for (idx = 0; idx < 16; idx = idx + 1)
                out[idx*4 +: 4] = r[idx];
            einsum_l2sq_5d_to_4d_int4 = out;
        end
    endfunction

    // v1.6.2 §22.13 — 5D→4D MIN (symmetric backfill for op-marker family).
    // op_marker=0x6 mirrors 5D→scalar MIN. Pair-min over axis m.
    function [ADDR_WIDTH-1:0] einsum_min_5d_to_4d_int4;
        input [127:0] a;
        reg signed [3:0] a0, a1, rm;
        reg [3:0] r [0:15];
        reg [63:0] out;
        integer idx;
        begin
            for (idx = 0; idx < 16; idx = idx + 1) begin
                a0 = $signed(a[idx*8 +: 4]);
                a1 = $signed(a[idx*8 + 4 +: 4]);
                rm = (a0 <= a1) ? a0 : a1;
                r[idx] = rm[3:0];
            end
            out = 64'h0;
            for (idx = 0; idx < 16; idx = idx + 1)
                out[idx*4 +: 4] = r[idx];
            einsum_min_5d_to_4d_int4 = out;
        end
    endfunction

    // v1.6.2 §22.13 — 4D→3D reduction primitives.
    // Input 4D 2×2×2×2 = 16 nibbles = 64-bit via dec_input_payload (legacy).
    // Output 3D 2×2×2 = 8 nibbles = 32-bit single-fragment (no FSM).
    // Nibble layout: A[i][j][k][l] at nibble (i*8 + j*4 + k*2 + l).
    // Reduce pair over axis l → R[i][j][k] at nibble (i*4 + j*2 + k).

    function [ADDR_WIDTH-1:0] einsum_sum_4d_to_3d_int4;
        input [63:0] a;
        reg [3:0] r [0:7];
        reg [31:0] out;
        integer idx;
        begin
            for (idx = 0; idx < 8; idx = idx + 1)
                r[idx] = a[idx*8 +: 4] + a[idx*8 + 4 +: 4];
            out = 32'h0;
            for (idx = 0; idx < 8; idx = idx + 1)
                out[idx*4 +: 4] = r[idx];
            einsum_sum_4d_to_3d_int4 = {32'h0, out};
        end
    endfunction

    function [ADDR_WIDTH-1:0] einsum_max_4d_to_3d_int4;
        input [63:0] a;
        reg signed [3:0] a0, a1, rm;
        reg [3:0] r [0:7];
        reg [31:0] out;
        integer idx;
        begin
            for (idx = 0; idx < 8; idx = idx + 1) begin
                a0 = $signed(a[idx*8 +: 4]);
                a1 = $signed(a[idx*8 + 4 +: 4]);
                rm = (a0 >= a1) ? a0 : a1;
                r[idx] = rm[3:0];
            end
            out = 32'h0;
            for (idx = 0; idx < 8; idx = idx + 1)
                out[idx*4 +: 4] = r[idx];
            einsum_max_4d_to_3d_int4 = {32'h0, out};
        end
    endfunction

    function [ADDR_WIDTH-1:0] einsum_min_4d_to_3d_int4;
        input [63:0] a;
        reg signed [3:0] a0, a1, rm;
        reg [3:0] r [0:7];
        reg [31:0] out;
        integer idx;
        begin
            for (idx = 0; idx < 8; idx = idx + 1) begin
                a0 = $signed(a[idx*8 +: 4]);
                a1 = $signed(a[idx*8 + 4 +: 4]);
                rm = (a0 <= a1) ? a0 : a1;
                r[idx] = rm[3:0];
            end
            out = 32'h0;
            for (idx = 0; idx < 8; idx = idx + 1)
                out[idx*4 +: 4] = r[idx];
            einsum_min_4d_to_3d_int4 = {32'h0, out};
        end
    endfunction

    function [ADDR_WIDTH-1:0] einsum_mean_4d_to_3d_int4;
        input [63:0] a;
        reg signed [4:0] sum5;
        reg [3:0] r [0:7];
        reg [31:0] out;
        integer idx;
        begin
            for (idx = 0; idx < 8; idx = idx + 1) begin
                sum5 = $signed(a[idx*8 +: 4]) + $signed(a[idx*8 + 4 +: 4]);
                r[idx] = sum5[4:1];
            end
            out = 32'h0;
            for (idx = 0; idx < 8; idx = idx + 1)
                out[idx*4 +: 4] = r[idx];
            einsum_mean_4d_to_3d_int4 = {32'h0, out};
        end
    endfunction

    function [ADDR_WIDTH-1:0] einsum_l2sq_4d_to_3d_int4;
        input [63:0] a;
        reg signed [3:0] a0, a1;
        reg signed [7:0] sq0, sq1;
        reg [7:0]  sum8;
        reg [3:0] r [0:7];
        reg [31:0] out;
        integer idx;
        begin
            for (idx = 0; idx < 8; idx = idx + 1) begin
                a0   = $signed(a[idx*8 +: 4]);
                a1   = $signed(a[idx*8 + 4 +: 4]);
                sq0  = a0 * a0;
                sq1  = a1 * a1;
                sum8 = sq0[7:0] + sq1[7:0];
                r[idx] = sum8[3:0];
            end
            out = 32'h0;
            for (idx = 0; idx < 8; idx = idx + 1)
                out[idx*4 +: 4] = r[idx];
            einsum_l2sq_4d_to_3d_int4 = {32'h0, out};
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

    // v1.6.5a §22.14 — Q4.4 wide-scalar mul (precision improvement over 0x62).
    // B is signed Q4.4 (dec_eff_b_value[7:0]): sign + 3 int + 4 frac bits.
    // Range [-8.0, +7.9375], LSB = 1/16.
    // Per-lane: p = signed(A[3:0]) * signed(B[7:0])  → 12-bit signed (Q8.4)
    //           output = (p + 8) >>> 4 → int4 (round-half-up)
    // Mathematical bound |A|<=8, |B|<=8 → |A*B/16|<=4 fits int4, no saturation.
    // Recovers ~4-bit precision at the RMSNORM/LAYERNORM scale-multiplication
    // step vs the int4 truncation in 0x62 (workflow wj6ewzd50 analysis).
    function [127:0] simd_mul_wide_q4_4_scalar_128;
        input [127:0] a;
        input [7:0]   b;
        reg [127:0] out;
        reg signed [3:0]  ai;
        reg signed [7:0]  bi;
        reg signed [11:0] p;
        reg signed [11:0] p_round;
        integer i;
        begin
            out = 128'h0;
            for (i = 0; i < 32; i = i + 1) begin
                ai      = $signed(a[i*4 +: 4]);
                bi      = $signed(b);
                p       = ai * bi;                    // Q8.4 signed (12-bit)
                p_round = p + 12'sd8;                  // round-half-up bias
                out[i*4 +: 4] = p_round[7:4];          // arith shift right 4, low 4 bits
            end
            simd_mul_wide_q4_4_scalar_128 = out;
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

    // =========================================================================
    // v1.6.3 §22.13 — Group C scalar rsqrt with 16-entry mantissa LUT
    // =========================================================================
    // Refinement of v1.6.1b baseline (power-of-2 → mantissa LUT ~4-bit precision).
    //
    //   Input:  Q16.16 unsigned variance (bits [30:0] valid; bit 31 = caller error)
    //   Output: Q16.16 approximation of 1/sqrt(input)
    //
    // Method (workflow wi87dl8lh design):
    //   1. Priority encoder: find MSB position m in [0, 30]
    //   2. Extract 3-bit mantissa below MSB (guard msb<3 with zero-pad)
    //   3. LUT index = {m[0] parity, mantissa[2:0]} — 4-bit
    //   4. LUT[0..7] = rsqrt(1 + f/8) * 2^15  (Q0.15, even m)
    //      LUT[8..15] = 1/sqrt(2) * rsqrt(1 + f/8) * 2^15  (Q0.15, odd m,
    //                                                       absorbs sqrt(2))
    //   5. Output = LUT_val << (9 - (m >> 1))  for shift >= 0
    //             = (LUT_val + round_bit) >> |shift|  for shift < 0 (round-to-nearest)
    //   6. Saturate 0x7FFF_FFFF on left-shift overflow
    //
    //   Backward compat: LUT[0]=0x8000 → for x=0x10000 (m=16, mant=0)
    //     shift = 9-8 = 1, output = 0x8000 << 1 = 0x10000 (bit-identical to v1.6.1b)
    //     for x=0x40000 (m=18): shift=0, output=0x8000 (bit-identical)
    //     for x=0: saturate 0x7FFF_FFFF (bit-identical)
    //     → v1.6.1b's 3 tests pass unchanged.
    //
    //   Special: x=0 → saturate; x[31]=1 → caller error (undefined; per §22.7 contract)
    //   Precision: ~4-bit mantissa (LUT bin ≤ 6.25% relative error)

    function [31:0] scalar_rsqrt_approx_q16_16;
        input [31:0] x;
        reg [5:0]  msb;
        reg        found;
        reg [3:0]  mant;
        reg [3:0]  lut_idx;
        reg [15:0] lut_val;
        reg signed [6:0] shift_signed;   // shift = 9 - (msb>>1), range [-6, +9]
        reg [4:0]  right_shift;
        reg [31:0] out;
        integer i;
        begin
            if (x == 32'h0) begin
                scalar_rsqrt_approx_q16_16 = 32'h7FFF_FFFF;
            end else begin
                // Priority encoder: find highest set bit in bits 30..0
                msb   = 6'd0;
                found = 1'b0;
                for (i = 30; i >= 0; i = i - 1) begin
                    if (x[i] && !found) begin
                        msb   = i[5:0];
                        found = 1'b1;
                    end
                end
                // Extract 3-bit mantissa below MSB with zero-pad for small msb
                if (msb >= 6'd3) begin
                    mant = {1'b0, x[msb - 6'd1 -: 3]};
                end else if (msb == 6'd2) begin
                    mant = {1'b0, x[1:0], 1'b0};
                end else if (msb == 6'd1) begin
                    mant = {1'b0, x[0], 2'b00};
                end else begin
                    mant = 4'h0;
                end
                // LUT index: {msb parity, mantissa[2:0]}
                lut_idx = {msb[0], mant[2:0]};
                // 16-entry Q0.15 LUT
                //   Even m (LUT[0..7]): rsqrt(1 + f/8), f=0..7
                //   Odd m (LUT[8..15]): 1/sqrt(2) * rsqrt(1 + f/8)
                case (lut_idx)
                    4'h0: lut_val = 16'h8000;  // rsqrt(1.0)   = 1.0000
                    4'h1: lut_val = 16'h78AE;  // rsqrt(1.125) = 0.9428
                    4'h2: lut_val = 16'h727D;  // rsqrt(1.25)  = 0.8944
                    4'h3: lut_val = 16'h6D2B;  // rsqrt(1.375) = 0.8528
                    4'h4: lut_val = 16'h6886;  // rsqrt(1.5)   = 0.8165
                    4'h5: lut_val = 16'h646D;  // rsqrt(1.625) = 0.7845
                    4'h6: lut_val = 16'h60C5;  // rsqrt(1.75)  = 0.7559
                    4'h7: lut_val = 16'h5D7E;  // rsqrt(1.875) = 0.7303
                    4'h8: lut_val = 16'h5A82;  // 1/√2 · 1.0000 = 0.7071
                    4'h9: lut_val = 16'h5555;  // 1/√2 · 0.9428 = 0.6667
                    4'hA: lut_val = 16'h50F4;  // 1/√2 · 0.8944 = 0.6325
                    4'hB: lut_val = 16'h4D2E;  // 1/√2 · 0.8528 = 0.6030
                    4'hC: lut_val = 16'h49E6;  // 1/√2 · 0.8165 = 0.5774
                    4'hD: lut_val = 16'h46FF;  // 1/√2 · 0.7845 = 0.5547
                    4'hE: lut_val = 16'h446A;  // 1/√2 · 0.7559 = 0.5345
                    4'hF: lut_val = 16'h4218;  // 1/√2 · 0.7303 = 0.5164
                    default: lut_val = 16'h8000;
                endcase
                // shift = 9 - (msb >> 1). Range: [9-15, 9-0] = [-6, +9].
                shift_signed = $signed({1'b0, 6'd9}) - $signed({2'b00, msb[5:1]});
                if (shift_signed >= 7'sd16) begin
                    // Saturate on extreme left-shift overflow (msb too small)
                    out = 32'h7FFF_FFFF;
                end else if (shift_signed >= 7'sd0) begin
                    // Left shift: value grows
                    out = {16'h0, lut_val} << shift_signed[4:0];
                    if (out[31]) out = 32'h7FFF_FFFF;   // signed overflow → saturate
                end else begin
                    // Right shift with round-to-nearest
                    right_shift = (~shift_signed[4:0]) + 5'd1;   // abs value
                    if (right_shift >= 5'd16) begin
                        out = 32'h0;   // underflow to zero
                    end else begin
                        out = ({16'h0, lut_val} + ({16'h0, 15'h0, 1'b1} << (right_shift - 5'd1)))
                              >> right_shift;
                    end
                end
                scalar_rsqrt_approx_q16_16 = out;
            end
        end
    endfunction

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
    wire dec_is_mul_op = (dec_opcode == 8'h12) || (dec_opcode == 8'h30)
                      || (dec_opcode == 8'h32) || (dec_opcode == 8'h43);
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
    // v1.5.3a §20 — fragment-emit FSM. 1-bit Moore machine mirroring the
    // div_state idiom. On SIG_BMM_3 dispatch (frag_state=FRAG_IDLE cycle N):
    //   - drives output_valid=1, output_payload=lo, output_frag_hdr=8'h01
    //   - latches result[127:64] into frag_hi_pending + tag/opcode holds
    //   - transitions to FRAG_EMIT_HI
    // On cycle N+1 (FRAG_EMIT_HI): absolute-priority override at the top of
    // the output mux drives fragment 1 (frag_hdr=8'h11) and returns to IDLE.
    //
    // Backpressure: the compound `output_regs_free` wire (derived below in
    // the always block) gates SIG_BMM_3 dispatch when ANY output-mux source
    // is in flight (MUL p1/p2, DIV any-state, DIV b_zero pulse). This closes
    // the MUL/DIV drain hazard the verify:fsm agent flagged.
    // -------------------------------------------------------------------------
    localparam           FRAG_IDLE    = 1'b0;
    localparam           FRAG_EMIT_HI = 1'b1;

    reg                  frag_state;
    reg [ADDR_WIDTH-1:0] frag_hi_pending;
    reg [TAG_WIDTH-1:0]  frag_tag_held;
    reg [7:0]            frag_opcode_held;

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
            frag_state       <= FRAG_IDLE;
            frag_hi_pending  <= {ADDR_WIDTH{1'b0}};
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
            // frag_state == FRAG_IDLE so a MUL cannot enter the pipeline
            // during a fragment-emit cycle and collide with FRAG_EMIT_HI.
            if (MUL_OPS_SUPPORTED) begin
                mul_a_p1     <= dec_input_payload;
                mul_b_p1     <= dec_eff_b_value;
                mul_tag_p1   <= dec_forwarded_tag;
                mul_valid_p1 <= pe_active && dec_valid && !dec_decode_error
                              && dec_tag_match && (dec_opcode == 8'h12)
                              && (frag_state == FRAG_IDLE);
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
                        // v1.5.3a: gate DIV launch on frag_state == FRAG_IDLE
                        // — a new DIV entering ITER during FRAG_EMIT_HI would
                        // land its FINISH pulse 64+ cycles later during ANY
                        // subsequent fragment emit, silently dropping DIV.
                        if (pe_active && dec_valid && !dec_decode_error
                                && dec_tag_match
                                && ((dec_opcode == 8'h13) ||
                                    (dec_opcode == 8'h1C) ||
                                    (dec_opcode == 8'h1D))
                                && (frag_state == FRAG_IDLE)) begin
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

            // v1.5.3a §20 — ABSOLUTE-PRIORITY fragment-emit override.
            // Placed at the very top of the output priority chain so
            // fragment 1 lands EXACTLY on cycle N+1 after SIG_BMM_3
            // dispatch. The launch-gate below prevents MUL/DIV from
            // starting new operations while frag_state == FRAG_EMIT_HI,
            // so this override never collides with a mul_valid_p2 or
            // div_valid_p2 pulse (compound gate closes the drain window).
            if (frag_state == FRAG_EMIT_HI) begin
                output_payload  <= frag_hi_pending;
                output_tag      <= frag_tag_held;
                opcode_out      <= frag_opcode_held;
                output_frag_hdr <= 8'h11;   // idx=1, total-1=1
                output_valid    <= 1'b1;
                frag_state      <= FRAG_IDLE;
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
                                    end else if (!((frag_state == FRAG_IDLE)
                                                && !mul_valid_p1 && !mul_valid_p2
                                                && (div_state == DIV_IDLE)
                                                && !div_valid_p2 && !div_b_zero_p2)) begin
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
                                        frag_hi_pending  <= einsum_bmm_3_int4_hi(
                                            dec_input_payload_wide[127:0],
                                            dec_input_payload_wide[255:128]);
                                        frag_tag_held    <= dec_forwarded_tag;
                                        frag_opcode_held <= dec_opcode;
                                        frag_state       <= FRAG_EMIT_HI;
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
                                    end else if (!((frag_state == FRAG_IDLE)
                                                && !mul_valid_p1 && !mul_valid_p2
                                                && (div_state == DIV_IDLE)
                                                && !div_valid_p2 && !div_b_zero_p2)) begin
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
                                    // Op marker: 0=SUM, 1=MAX, 4=L2SQ, 5=MEAN.
                                    if (!dec_input_payload_wide_valid) begin
                                        error_flag   <= 1'b1;
                                        output_valid <= 1'b0;
                                    end else if (!((frag_state == FRAG_IDLE)
                                                && !mul_valid_p1 && !mul_valid_p2
                                                && (div_state == DIV_IDLE)
                                                && !div_valid_p2 && !div_b_zero_p2)) begin
                                        lower_required <= 1'b1;
                                        output_valid   <= 1'b0;
                                    end else case (dec_eff_subscript_hi[3:0])
                                        OP_SUM: begin
                                            output_payload <= einsum_sum_5d_to_4d_int4(dec_input_payload_wide[127:0]);
                                            output_tag <= {dec_wave_number, dec_thread_id,
                                                           8'h00, dec_eff_output_port_id,
                                                           dec_eff_precision, 8'h55};
                                            output_valid <= 1'b1;
                                        end
                                        OP_MAX: begin
                                            output_payload <= einsum_max_5d_to_4d_int4(dec_input_payload_wide[127:0]);
                                            output_tag <= {dec_wave_number, dec_thread_id,
                                                           8'h00, dec_eff_output_port_id,
                                                           dec_eff_precision, 8'h55};
                                            output_valid <= 1'b1;
                                        end
                                        OP_L2SQ: begin
                                            output_payload <= einsum_l2sq_5d_to_4d_int4(dec_input_payload_wide[127:0]);
                                            output_tag <= {dec_wave_number, dec_thread_id,
                                                           8'h00, dec_eff_output_port_id,
                                                           dec_eff_precision, 8'h55};
                                            output_valid <= 1'b1;
                                        end
                                        OP_MEAN: begin
                                            output_payload <= einsum_mean_5d_to_4d_int4(dec_input_payload_wide[127:0]);
                                            output_tag <= {dec_wave_number, dec_thread_id,
                                                           8'h00, dec_eff_output_port_id,
                                                           dec_eff_precision, 8'h55};
                                            output_valid <= 1'b1;
                                        end
                                        OP_MIN: begin
                                            // v1.6.2 §22.13 — 5D→4D MIN symmetric backfill.
                                            output_payload <= einsum_min_5d_to_4d_int4(dec_input_payload_wide[127:0]);
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
                                end else if ((dec_eff_subscript == SIG_4D3D_FAMILY_LO)
                                             && (dec_eff_subscript_hi[47:4] == SIG_4D3D_FAMILY_HI_BASE)) begin
                                    // v1.6.2 §22.13 — 4D→3D reduction family.
                                    // Legacy 64-bit input via dec_input_payload
                                    // (fabric zero-pads wide[127:64]). wide_valid
                                    // check intentionally omitted — no fragment
                                    // reassembly required for 64-bit A. dim_sizes
                                    // must be 0x55 (4D 2×2×2×2). Compound drain
                                    // gate reused (shared output regs).
                                    if (dec_eff_dim_sizes != 8'h55) begin
                                        lower_required <= 1'b1;
                                        output_valid   <= 1'b0;
                                    end else if (!((frag_state == FRAG_IDLE)
                                                && !mul_valid_p1 && !mul_valid_p2
                                                && (div_state == DIV_IDLE)
                                                && !div_valid_p2 && !div_b_zero_p2)) begin
                                        lower_required <= 1'b1;
                                        output_valid   <= 1'b0;
                                    end else case (dec_eff_subscript_hi[3:0])
                                        OP_SUM: begin
                                            output_payload <= einsum_sum_4d_to_3d_int4(dec_input_payload);
                                            output_tag <= {dec_wave_number, dec_thread_id,
                                                           8'h00, dec_eff_output_port_id,
                                                           dec_eff_precision, 8'h15};
                                            output_valid    <= 1'b1;
                                            output_frag_hdr <= 8'h00;
                                        end
                                        OP_MAX: begin
                                            output_payload <= einsum_max_4d_to_3d_int4(dec_input_payload);
                                            output_tag <= {dec_wave_number, dec_thread_id,
                                                           8'h00, dec_eff_output_port_id,
                                                           dec_eff_precision, 8'h15};
                                            output_valid    <= 1'b1;
                                            output_frag_hdr <= 8'h00;
                                        end
                                        OP_MIN: begin
                                            output_payload <= einsum_min_4d_to_3d_int4(dec_input_payload);
                                            output_tag <= {dec_wave_number, dec_thread_id,
                                                           8'h00, dec_eff_output_port_id,
                                                           dec_eff_precision, 8'h15};
                                            output_valid    <= 1'b1;
                                            output_frag_hdr <= 8'h00;
                                        end
                                        OP_L2SQ: begin
                                            output_payload <= einsum_l2sq_4d_to_3d_int4(dec_input_payload);
                                            output_tag <= {dec_wave_number, dec_thread_id,
                                                           8'h00, dec_eff_output_port_id,
                                                           dec_eff_precision, 8'h15};
                                            output_valid    <= 1'b1;
                                            output_frag_hdr <= 8'h00;
                                        end
                                        OP_MEAN: begin
                                            output_payload <= einsum_mean_4d_to_3d_int4(dec_input_payload);
                                            output_tag <= {dec_wave_number, dec_thread_id,
                                                           8'h00, dec_eff_output_port_id,
                                                           dec_eff_precision, 8'h15};
                                            output_valid    <= 1'b1;
                                            output_frag_hdr <= 8'h00;
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
                                    end else if (!((frag_state == FRAG_IDLE)
                                                && !mul_valid_p1 && !mul_valid_p2
                                                && (div_state == DIV_IDLE)
                                                && !div_valid_p2 && !div_b_zero_p2)) begin
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
                                    end else if (!((frag_state == FRAG_IDLE)
                                                && !mul_valid_p1 && !mul_valid_p2
                                                && (div_state == DIV_IDLE)
                                                && !div_valid_p2 && !div_b_zero_p2)) begin
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
                        // 0x67 Q4.4 SCALAR (v1.6.5a): B via dec_eff_b_value[7:0]
                        //   as signed Q4.4 — precision recovery for norm scale.
                        8'h60, 8'h61, 8'h62, 8'h63, 8'h64, 8'h65, 8'h67: begin
                            if (!dec_input_payload_wide_valid) begin
                                error_flag   <= 1'b1;
                                output_valid <= 1'b0;
                            end else if (!((frag_state == FRAG_IDLE)
                                        && !mul_valid_p1 && !mul_valid_p2
                                        && (div_state == DIV_IDLE)
                                        && !div_valid_p2 && !div_b_zero_p2)) begin
                                lower_required <= 1'b1;
                                output_valid   <= 1'b0;
                            end else begin
                                // Compute lo and hi halves per opcode
                                case (dec_opcode)
                                    8'h60: begin
                                        output_payload   <= simd_add_wide_scalar_128(
                                            dec_input_payload_wide[127:0],
                                            dec_eff_b_value[3:0])[63:0];
                                        frag_hi_pending  <= simd_add_wide_scalar_128(
                                            dec_input_payload_wide[127:0],
                                            dec_eff_b_value[3:0])[127:64];
                                    end
                                    8'h61: begin
                                        output_payload   <= simd_sub_wide_scalar_128(
                                            dec_input_payload_wide[127:0],
                                            dec_eff_b_value[3:0])[63:0];
                                        frag_hi_pending  <= simd_sub_wide_scalar_128(
                                            dec_input_payload_wide[127:0],
                                            dec_eff_b_value[3:0])[127:64];
                                    end
                                    8'h62: begin
                                        output_payload   <= simd_mul_wide_scalar_128(
                                            dec_input_payload_wide[127:0],
                                            dec_eff_b_value[3:0])[63:0];
                                        frag_hi_pending  <= simd_mul_wide_scalar_128(
                                            dec_input_payload_wide[127:0],
                                            dec_eff_b_value[3:0])[127:64];
                                    end
                                    8'h63: begin
                                        output_payload   <= simd_add_wide_vec_128(
                                            dec_input_payload_wide[127:0],
                                            dec_input_payload_b)[63:0];
                                        frag_hi_pending  <= simd_add_wide_vec_128(
                                            dec_input_payload_wide[127:0],
                                            dec_input_payload_b)[127:64];
                                    end
                                    8'h64: begin
                                        output_payload   <= simd_sub_wide_vec_128(
                                            dec_input_payload_wide[127:0],
                                            dec_input_payload_b)[63:0];
                                        frag_hi_pending  <= simd_sub_wide_vec_128(
                                            dec_input_payload_wide[127:0],
                                            dec_input_payload_b)[127:64];
                                    end
                                    8'h65: begin
                                        output_payload   <= simd_mul_wide_vec_128(
                                            dec_input_payload_wide[127:0],
                                            dec_input_payload_b)[63:0];
                                        frag_hi_pending  <= simd_mul_wide_vec_128(
                                            dec_input_payload_wide[127:0],
                                            dec_input_payload_b)[127:64];
                                    end
                                    8'h67: begin
                                        // v1.6.5a — Q4.4 wide-scalar mul.
                                        // B via dec_eff_b_value[7:0] as signed Q4.4.
                                        output_payload   <= simd_mul_wide_q4_4_scalar_128(
                                            dec_input_payload_wide[127:0],
                                            dec_eff_b_value[7:0])[63:0];
                                        frag_hi_pending  <= simd_mul_wide_q4_4_scalar_128(
                                            dec_input_payload_wide[127:0],
                                            dec_eff_b_value[7:0])[127:64];
                                    end
                                    default: ;
                                endcase
                                output_valid     <= 1'b1;
                                output_frag_hdr  <= 8'h01;   // idx=0, total-1=1
                                opcode_out       <= dec_opcode;
                                frag_tag_held    <= dec_forwarded_tag;
                                frag_opcode_held <= dec_opcode;
                                frag_state       <= FRAG_EMIT_HI;
                            end
                        end
                        // v1.6.1b §22 — SCALAR_RSQRT_APPROX (Q16.16, no FSM)
                        8'h66: begin
                            output_payload <= {32'h0,
                                scalar_rsqrt_approx_q16_16(dec_input_payload[31:0])};
                            output_valid   <= 1'b1;
                            // Output tag dim_sizes = 0x00 (scalar)
                            output_tag <= {dec_wave_number, dec_thread_id,
                                           8'h00, dec_eff_output_port_id,
                                           dec_eff_precision, 8'h00};
                        end
                        default: begin
                            output_valid <= 1'b0;
                            error_flag <= 1'b1;
                        end
                    endcase
                end
            end
        end
    end

    // v1.6.6 §22.14 — pe_ready back-pressure signal (combinational).
    // Same 6-term compound as internal drain gate. Upstream fabric can
    // observe this to STALL new dispatches instead of retrying after
    // lower_required. MVP: observe-only, no ext_valid gating change.
    assign pe_ready = (frag_state == FRAG_IDLE)
                   && !mul_valid_p1 && !mul_valid_p2
                   && (div_state == DIV_IDLE)
                   && !div_valid_p2 && !div_b_zero_p2;

endmodule

/* verilator lint_on UNUSEDSIGNAL */
