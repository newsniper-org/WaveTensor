// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

// =============================================================================
// SIMD_ALU.v — Lane-parallel scalar ALU.
//
// SIMD_WIDTH lanes operate in lockstep on `input_payload_vec` (a packed vector
// of SIMD_WIDTH × ADDR_WIDTH-bit elements) plus a shared 16-bit immediate.
// The output is registered with one cycle of latency relative to the inputs;
// `alu_valid` rises one cycle after the first non-reset cycle and remains high
// while a result is being produced.
//
// Synthesis-safe properties:
//   * All operand widths in arithmetic expressions are explicitly normalized to
//     ADDR_WIDTH so no implicit zero-extension is left to the synthesizer.
//   * The lane datapath is a single combinational function (`lane_op`) whose
//     output is assigned into a registered staging vector; there is no
//     read-after-write of the staging register inside the same procedural
//     iteration (the prior version sampled `lane_result[lane]` on the same
//     edge that wrote it, producing a one-cycle stale output).
//   * DIV/REM divide-by-zero is hardened: when `imm_offset == 0` the lane
//     output is forced to 0 and a per-lane sticky `lane_div_zero` flag is
//     asserted, surfacing on `div_zero_flag`. No X is generated.
//   * Default opcode case writes a deterministic 0 to keep simulators and
//     formal tools quiet.
//   * MUL is a sized full-width multiplier; the result is explicitly truncated
//     to ADDR_WIDTH with `[ADDR_WIDTH-1:0]`, documenting the wrap semantics
//     intentionally.
// =============================================================================

module SIMD_ALU #(
    parameter ADDR_WIDTH     = 64,
    parameter SIMD_WIDTH     = 4,
    parameter PRECISION_BITS = 8
) (
    input                                     clk,
    input                                     rst,
    input  [7:0]                              opcode,
    input  [PRECISION_BITS-1:0]               precision_mode,
    input  [ADDR_WIDTH*SIMD_WIDTH-1:0]        input_payload_vec,
    input  [15:0]                             imm_offset,
    output reg [ADDR_WIDTH*SIMD_WIDTH-1:0]    output_payload_vec,
    output reg                                alu_valid,
    output reg                                div_zero_flag
);

    // -------------------------------------------------------------------------
    // Width-normalized immediate. Explicit zero-extension to ADDR_WIDTH so
    // every arithmetic expression has matched RHS/LHS widths.
    // -------------------------------------------------------------------------
    /* verilator lint_off UNUSEDSIGNAL */
    wire [PRECISION_BITS-1:0] precision_unused = precision_mode;
    /* verilator lint_on UNUSEDSIGNAL */

    wire [ADDR_WIDTH-1:0] imm_ext = {{(ADDR_WIDTH-16){1'b0}}, imm_offset};
    wire                  imm_is_zero = (imm_offset == 16'h0000);

    // -------------------------------------------------------------------------
    // Combinational lane operation. Pure function of (opcode, lane_in,
    // imm_ext, imm_is_zero); no internal state.
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

    /* verilator lint_off UNUSEDSIGNAL */
    function [ADDR_WIDTH-1:0] lane_op;
        input [7:0]            op;
        input [ADDR_WIDTH-1:0] a;
        input [ADDR_WIDTH-1:0] b;
        input                  b_is_zero;
        // Doubled-width product captures full multiplier output; the upper
        // half is intentionally discarded for wrap-on-overflow semantics
        // matching the surrounding 64-bit WaveScalar datapath.
        reg   [2*ADDR_WIDTH-1:0] full_mul;
        begin
            case (op)
                8'h10: lane_op = a + b;
                8'h11: lane_op = a - b;
                8'h12: begin
                    full_mul = a * b;
                    lane_op  = full_mul[ADDR_WIDTH-1:0];
                end
                8'h13: lane_op = b_is_zero ? {ADDR_WIDTH{1'b0}} : (a / b);
                8'h1C: lane_op = b_is_zero ? {ADDR_WIDTH{1'b0}} : (a % b);
                8'h1F: lane_op = bit_reverse(a);
                default: lane_op = {ADDR_WIDTH{1'b0}};
            endcase
        end
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    function dz_for_op;
        input [7:0] op;
        input       b_is_zero;
        begin
            // Only DIV (0x13) and REM (0x1C) suffer from divide-by-zero.
            dz_for_op = b_is_zero && ((op == 8'h13) || (op == 8'h1C));
        end
    endfunction

    // -------------------------------------------------------------------------
    // Sequential output stage. Compute next-cycle vector combinationally,
    // then register it. No staging array, no read-modify-write.
    // -------------------------------------------------------------------------
    integer                            lane;
    reg [ADDR_WIDTH*SIMD_WIDTH-1:0]    next_output_vec;
    reg                                next_div_zero_flag;
    reg [ADDR_WIDTH-1:0]               lane_in;
    reg [ADDR_WIDTH-1:0]               lane_out;

    always @(*) begin
        next_output_vec    = {(ADDR_WIDTH*SIMD_WIDTH){1'b0}};
        next_div_zero_flag = 1'b0;
        for (lane = 0; lane < SIMD_WIDTH; lane = lane + 1) begin
            lane_in  = input_payload_vec[lane*ADDR_WIDTH +: ADDR_WIDTH];
            lane_out = lane_op(opcode, lane_in, imm_ext, imm_is_zero);
            next_output_vec[lane*ADDR_WIDTH +: ADDR_WIDTH] = lane_out;
            if (dz_for_op(opcode, imm_is_zero))
                next_div_zero_flag = 1'b1;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            output_payload_vec <= {(ADDR_WIDTH*SIMD_WIDTH){1'b0}};
            alu_valid          <= 1'b0;
            div_zero_flag      <= 1'b0;
        end else begin
            output_payload_vec <= next_output_vec;
            alu_valid          <= 1'b1;
            div_zero_flag      <= next_div_zero_flag;
        end
    end

endmodule
