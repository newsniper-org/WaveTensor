// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

`include "attributes.vh"

// =============================================================================
// ALU_Extended.v — Multi-precision arithmetic + unary FP ALU.
//
// Two orthogonal control paths:
//   1) `precision_mode` selects the binary arithmetic family (Int4, Int128,
//      Cfloat32, Qfloat64, Gauss8).
//   2) `opcode` selects between the binary arithmetic above (when opcode is
//      one of 0x10..0x1F) and the unary FP family (FLOOR/ROUND/CEIL/
//      EUCLID_NORM/CONJUGATE in 0x40..0x44).
//
// In the original module the two case statements both wrote `result` from the
// same always block, so the unary case silently overrode the binary case when
// both paths matched. Here the two paths are explicitly arbitrated: the unary
// opcodes 0x40..0x44 win when present; otherwise the precision-mode result
// is selected. All helper functions are defined locally — no external
// dependency on ISA_Decoder.
//
// Cfloat32 multiplication is performed with explicitly signed 33-bit
// multiplications so that the conventional (a+bi)(c+di) = (ac-bd)+(ad+bc)i
// identity produces the correct two's-complement result. The earlier
// implementation used unsigned `*` and silently dropped sign for negative
// products.
// =============================================================================

module ALU_Extended #(
    parameter ADDR_WIDTH     = 64,
    parameter PRECISION_BITS = 8
) (
    input                       clk,
    input                       rst,
    input  [7:0]                opcode,
    input  [PRECISION_BITS-1:0] precision_mode,
    input  [ADDR_WIDTH-1:0]     input_a,
    input  [ADDR_WIDTH-1:0]     input_b,
    output reg [ADDR_WIDTH-1:0] result,
    output reg                  alu_valid
);

    // -------------------------------------------------------------------------
    // Helper functions — all defined inside the module so synthesis is
    // self-contained.
    // -------------------------------------------------------------------------

    // FLOOR / ROUND / CEIL — placeholder integer-passthrough semantics
    // matching ISA_Decoder. Real fixed-point/float implementations are a
    // future Bit-Fusion ALU expansion.
    function [ADDR_WIDTH-1:0] floor_func;
        input [ADDR_WIDTH-1:0] in_val;
        begin
            floor_func = in_val;
        end
    endfunction

    function [ADDR_WIDTH-1:0] round_func;
        input [ADDR_WIDTH-1:0] in_val;
        begin
            round_func = in_val;
        end
    endfunction

    function [ADDR_WIDTH-1:0] ceil_func;
        input [ADDR_WIDTH-1:0] in_val;
        begin
            ceil_func = in_val;
        end
    endfunction

    // Squared Euclidean norm of a 32+32-bit complex number packed in 64 bits:
    // re = in_val[63:32], im = in_val[31:0]; output = re*re + im*im.
    function [ADDR_WIDTH-1:0] euclid_norm;
        input [ADDR_WIDTH-1:0] in_val;
        reg signed [31:0]      re;
        reg signed [31:0]      im;
        reg signed [63:0]      re_sq;
        reg signed [63:0]      im_sq;
        begin
            re    = in_val[63:32];
            im    = in_val[31: 0];
            re_sq = re * re;
            im_sq = im * im;
            euclid_norm = re_sq + im_sq;
        end
    endfunction

    // Complex conjugate: negate the imaginary half (32-bit two's complement).
    function [ADDR_WIDTH-1:0] conjugate;
        input [ADDR_WIDTH-1:0] in_val;
        reg [31:0] re;
        reg [31:0] im_neg;
        begin
            re     = in_val[63:32];
            im_neg = (~in_val[31:0]) + 32'd1;
            conjugate = {re, im_neg};
        end
    endfunction

    // Cfloat32 multiplication (signed). Treats input_a as (a_re + a_im*i),
    // input_b as (b_re + b_im*i). Returns
    //   (a_re*b_re - a_im*b_im) || (a_re*b_im + a_im*b_re)
    // in {real, imag} order, each half saturated/wrapped to 32 bits.
    /* verilator lint_off UNUSEDSIGNAL */
    function [ADDR_WIDTH-1:0] cfloat32_mul;
        input [ADDR_WIDTH-1:0] a;
        input [ADDR_WIDTH-1:0] b;
        reg signed [31:0]      a_re, a_im, b_re, b_im;
        // Doubled-width products: the upper 32 bits absorb potential overflow
        // from the signed multiply-subtract / multiply-add. The high half is
        // intentionally discarded to wrap into a 32-bit fixed-point lane,
        // matching the convention used by the surrounding 64-bit datapath.
        // `use_dsp` hints map these signed multiply-and-add lines into DSP58
        // slices on UltraScale+, freeing LUTs.
        `WT_USE_DSP reg signed [63:0] re_part;
        `WT_USE_DSP reg signed [63:0] im_part;
        begin
            a_re = a[63:32];
            a_im = a[31: 0];
            b_re = b[63:32];
            b_im = b[31: 0];
            re_part = (a_re * b_re) - (a_im * b_im);
            im_part = (a_re * b_im) + (a_im * b_re);
            cfloat32_mul = {re_part[31:0], im_part[31:0]};
        end
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    // -------------------------------------------------------------------------
    // Combinational next-state computation.
    // -------------------------------------------------------------------------
    function is_unary_fp_opcode;
        input [7:0] op;
        begin
            is_unary_fp_opcode = (op == 8'h40) || (op == 8'h41) || (op == 8'h42)
                              || (op == 8'h43) || (op == 8'h44);
        end
    endfunction

    function [ADDR_WIDTH-1:0] precision_op;
        input [PRECISION_BITS-1:0] pmode;
        input [ADDR_WIDTH-1:0]     a;
        input [ADDR_WIDTH-1:0]     b;
        reg   [31:0]               hi_sum, lo_sum;
        begin
            case (pmode)
                8'h01: precision_op = a + b;                              // Int4
                8'h0A: begin                                              // Int128 packed
                    hi_sum = a[63:32] + b[63:32];
                    lo_sum = a[31: 0] + b[31: 0];
                    precision_op = {hi_sum, lo_sum};
                end
                8'h20: precision_op = cfloat32_mul(a, b);                 // Cfloat32 mul
                8'h30: precision_op = a + b;                              // Qfloat64 add
                8'h40: precision_op = a + b;                              // Gauss8 add
                default: precision_op = {ADDR_WIDTH{1'b0}};
            endcase
        end
    endfunction

    function [ADDR_WIDTH-1:0] unary_op;
        input [7:0]            op;
        input [ADDR_WIDTH-1:0] a;
        begin
            case (op)
                8'h40:   unary_op = floor_func(a);
                8'h41:   unary_op = round_func(a);
                8'h42:   unary_op = ceil_func(a);
                8'h43:   unary_op = euclid_norm(a);
                8'h44:   unary_op = conjugate(a);
                default: unary_op = {ADDR_WIDTH{1'b0}};
            endcase
        end
    endfunction

    reg [ADDR_WIDTH-1:0] next_result;

    always @(*) begin
        if (is_unary_fp_opcode(opcode))
            next_result = unary_op(opcode, input_a);
        else
            next_result = precision_op(precision_mode, input_a, input_b);
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result    <= {ADDR_WIDTH{1'b0}};
            alu_valid <= 1'b0;
        end else begin
            result    <= next_result;
            alu_valid <= 1'b1;
        end
    end

endmodule
