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
    parameter NON_MUL_OPS_SUPPORTED = 1
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
    input  [7:0]                 dec_eff_output_port_id,
    input  [7:0]                 dec_eff_precision,
    input  [31:0]                dec_wave_number,
    input  [15:0]                dec_thread_id,

    // ---- Outputs ----
    output reg [ADDR_WIDTH-1:0]  output_payload,
    output reg [TAG_WIDTH-1:0]   output_tag,
    output reg                   output_valid,
    output reg [7:0]             opcode_out,
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
    // Stage-2 sequential dispatch
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            output_payload <= {ADDR_WIDTH{1'b0}};
            output_tag     <= {TAG_WIDTH{1'b0}};
            output_valid   <= 1'b0;
            opcode_out     <= 8'h00;
            memory_req     <= 1'b0;
            mem_addr       <= {ADDR_WIDTH{1'b0}};
            error_flag     <= 1'b0;
            lower_required <= 1'b0;
            mul_valid_p1   <= 1'b0;
            mul_valid_p2   <= 1'b0;
            div_state      <= DIV_IDLE;
            div_valid_p2   <= 1'b0;
            div_b_zero_p2  <= 1'b0;
        end else begin
            output_valid   <= 1'b0;
            memory_req     <= 1'b0;
            error_flag     <= 1'b0;
            lower_required <= 1'b0;
            opcode_out     <= dec_opcode;

            // Multi-cycle MUL pipeline advance
            if (MUL_OPS_SUPPORTED) begin
                mul_a_p1     <= dec_input_payload;
                mul_b_p1     <= dec_eff_b_value;
                mul_tag_p1   <= dec_forwarded_tag;
                mul_valid_p1 <= pe_active && dec_valid && !dec_decode_error
                              && dec_tag_match && (dec_opcode == 8'h12);
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
                        if (pe_active && dec_valid && !dec_decode_error
                                && dec_tag_match
                                && ((dec_opcode == 8'h13) ||
                                    (dec_opcode == 8'h1C) ||
                                    (dec_opcode == 8'h1D))) begin
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

            // Output priority: MUL > DIV pipeline > case dispatch.
            if (MUL_OPS_SUPPORTED && mul_valid_p2) begin
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
                            if (!MUL_OPS_SUPPORTED) begin
                                lower_required <= 1'b1; output_valid <= 1'b0;
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
                        default: begin
                            output_valid <= 1'b0;
                            error_flag <= 1'b1;
                        end
                    endcase
                end
            end
        end
    end

endmodule

/* verilator lint_on UNUSEDSIGNAL */
