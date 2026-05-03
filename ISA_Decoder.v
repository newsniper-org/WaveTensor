// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

// =============================================================================
// ISA_Decoder.v — thin wrapper around EHDecode + PE_Core.
//
// Preserves the original module interface so all stand-alone tests
// (test_isa_decoder.py, test_pe.py via PE.v, test_top_core.py via Top_Core)
// continue to drive `instruction` / `input_tag` / payloads and observe
// `output_*` exactly as before.
//
// Internally splits decoding (EHDecode) from execution (PE_Core) so that
// Cluster.v can amortize decoding across multiple PEs (one EHDecode +
// N PE_Cores), which is the (j) Cluster-shared-frontend mitigation.
// =============================================================================

module ISA_Decoder #(
    parameter ADDR_WIDTH            = 64,
    parameter TAG_WIDTH             = 80,
    parameter MAX_EH                = 4,
    parameter INSTR_WIDTH           = 32 + MAX_EH*96,
    parameter MUL_OPS_SUPPORTED     = 1,
    parameter DIV_OPS_SUPPORTED     = 1,
    parameter NON_MUL_OPS_SUPPORTED = 1
) (
    input                       clk,
    input                       rst,
    input                       token_valid,
    input  [INSTR_WIDTH-1:0]    instruction,
    input  [TAG_WIDTH-1:0]      input_tag,
    input  [ADDR_WIDTH-1:0]     input_payload,
    input  [ADDR_WIDTH-1:0]     input_payload_b,
    input                       input_payload_b_valid,
    output [ADDR_WIDTH-1:0]     output_payload,
    output [TAG_WIDTH-1:0]      output_tag,
    output                      output_valid,
    output [7:0]                opcode_out,
    output                      memory_req,
    output [ADDR_WIDTH-1:0]     mem_addr,
    output                      error_flag,
    output                      lower_required,
    output [3:0]                opref_src_kind_out,
    output [3:0]                opref_port_id_out,
    output [7:0]                opref_noc_route_out
);

    // Internal dec_* bus from EHDecode → PE_Core
    wire                       dec_valid;
    wire [7:0]                 dec_opcode;
    wire                       dec_decode_error;
    wire                       dec_tag_match;
    wire [TAG_WIDTH-1:0]       dec_forwarded_tag;
    wire [TAG_WIDTH-1:0]       dec_wave_advanced_tag;
    wire [ADDR_WIDTH-1:0]      dec_input_payload;
    wire [ADDR_WIDTH-1:0]      dec_input_payload_b;
    wire                       dec_input_payload_b_valid;
    wire [ADDR_WIDTH-1:0]      dec_eff_b_value;
    wire [15:0]                dec_eff_imm16;
    wire [7:0]                 dec_eff_dim_sizes;
    wire [3:0]                 dec_eff_opref_kind;
    wire [31:0]                dec_eff_mem_offset;
    wire [47:0]                dec_eff_subscript;
    wire [7:0]                 dec_eff_output_port_id;
    wire [7:0]                 dec_eff_precision;
    wire [31:0]                dec_wave_number;
    wire [15:0]                dec_thread_id;
    /* verilator lint_off UNUSEDSIGNAL */
    // dec_port_context_id is exposed by EHDecode for Cluster routing but
    // unused inside the standalone wrapper.
    wire [15:0]                dec_port_context_id;
    /* verilator lint_on UNUSEDSIGNAL */

    EHDecode #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .TAG_WIDTH  (TAG_WIDTH),
        .MAX_EH     (MAX_EH),
        .INSTR_WIDTH(INSTR_WIDTH)
    ) u_ehdec (
        .clk                       (clk),
        .rst                       (rst),
        .in_valid                  (token_valid),
        .instruction               (instruction),
        .input_tag                 (input_tag),
        .input_payload             (input_payload),
        .input_payload_b           (input_payload_b),
        .input_payload_b_valid     (input_payload_b_valid),
        .dec_valid                 (dec_valid),
        .dec_opcode                (dec_opcode),
        .dec_decode_error          (dec_decode_error),
        .dec_tag_match             (dec_tag_match),
        .dec_forwarded_tag         (dec_forwarded_tag),
        .dec_wave_advanced_tag     (dec_wave_advanced_tag),
        .dec_input_payload         (dec_input_payload),
        .dec_input_payload_b       (dec_input_payload_b),
        .dec_input_payload_b_valid (dec_input_payload_b_valid),
        .dec_eff_b_value           (dec_eff_b_value),
        .dec_eff_imm16             (dec_eff_imm16),
        .dec_eff_dim_sizes         (dec_eff_dim_sizes),
        .dec_eff_opref_kind        (dec_eff_opref_kind),
        .dec_eff_mem_offset        (dec_eff_mem_offset),
        .dec_eff_subscript         (dec_eff_subscript),
        .dec_eff_output_port_id    (dec_eff_output_port_id),
        .dec_eff_precision         (dec_eff_precision),
        .dec_wave_number           (dec_wave_number),
        .dec_thread_id             (dec_thread_id),
        .dec_port_context_id       (dec_port_context_id),
        .opref_src_kind_out        (opref_src_kind_out),
        .opref_port_id_out         (opref_port_id_out),
        .opref_noc_route_out       (opref_noc_route_out)
    );

    PE_Core #(
        .ADDR_WIDTH            (ADDR_WIDTH),
        .TAG_WIDTH             (TAG_WIDTH),
        .MUL_OPS_SUPPORTED     (MUL_OPS_SUPPORTED),
        .DIV_OPS_SUPPORTED     (DIV_OPS_SUPPORTED),
        .NON_MUL_OPS_SUPPORTED (NON_MUL_OPS_SUPPORTED)
    ) u_core (
        .clk                       (clk),
        .rst                       (rst),
        .pe_active                 (1'b1),  // standalone — always active
        .dec_valid                 (dec_valid),
        .dec_opcode                (dec_opcode),
        .dec_decode_error          (dec_decode_error),
        .dec_tag_match             (dec_tag_match),
        .dec_forwarded_tag         (dec_forwarded_tag),
        .dec_wave_advanced_tag     (dec_wave_advanced_tag),
        .dec_input_payload         (dec_input_payload),
        .dec_input_payload_b       (dec_input_payload_b),
        .dec_input_payload_b_valid (dec_input_payload_b_valid),
        .dec_eff_b_value           (dec_eff_b_value),
        .dec_eff_imm16             (dec_eff_imm16),
        .dec_eff_dim_sizes         (dec_eff_dim_sizes),
        .dec_eff_opref_kind        (dec_eff_opref_kind),
        .dec_eff_mem_offset        (dec_eff_mem_offset),
        .dec_eff_subscript         (dec_eff_subscript),
        .dec_eff_output_port_id    (dec_eff_output_port_id),
        .dec_eff_precision         (dec_eff_precision),
        .dec_wave_number           (dec_wave_number),
        .dec_thread_id             (dec_thread_id),
        .output_payload            (output_payload),
        .output_tag                (output_tag),
        .output_valid              (output_valid),
        .opcode_out                (opcode_out),
        .memory_req                (memory_req),
        .mem_addr                  (mem_addr),
        .error_flag                (error_flag),
        .lower_required            (lower_required)
    );

endmodule
