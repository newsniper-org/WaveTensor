// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

// =============================================================================
// PE.v — Processing Element wrapper.
//
// A PE is the smallest reconfigurable execution unit in the WaveTensor
// hierarchy:
//
//     PE   →   Cluster (4 PE_ROWS × PE_COLS, ∈ {(2,2),(2,4),(4,2),(4,4)})
//          →   Pod     (4 CLUSTER_ROWS × CLUSTER_COLS, same set)
//          →   Global Grid (multi-Pod)
//
// In this iteration the PE is a thin wrapper around `ISA_Decoder.v`. It:
//
//   * Carries `(PE_X, PE_Y)` as parameters so the Cluster's router can
//     identify each PE instance during multicast / NoC traversal.
//   * Exposes a 2-port token interface — primary (input_payload,
//     input_tag, instruction) and secondary (input_payload_b, valid).
//     The secondary port is filled by the Cluster's NoC when an instruction
//     carries `OPERAND_REF.src_kind=1`; for `src_kind=0` the secondary port
//     is driven directly by whatever feeds it locally.
//   * Forwards `output_*` plus `memory_req`/`mem_addr` to the Cluster
//     for routing.
//   * Surfaces both `error_flag` (structurally invalid) and
//     `lower_required` (HW-direct fast path missing) so the Cluster
//     can route violators back to a runtime/lowering controller.
//
// No internal token buffer is added at this level: WaveScalar dataflow
// matching across multiple inputs is handled by the Cluster's NoC, not by
// the PE itself. The PE simply consumes whatever token reaches its primary
// input on a cycle when `in_valid=1`.
// =============================================================================

module PE #(
    parameter ADDR_WIDTH         = 64,
    parameter TAG_WIDTH          = 80,
    parameter MAX_EH             = 4,
    parameter INSTR_WIDTH        = 32 + MAX_EH*96,   // = 416
    parameter PE_X               = 0,
    parameter PE_Y               = 0,
    // Heterogeneous-PE control passed to the inner ISA_Decoder.
    //   1 → full PE (stand-alone) or M-UNIT (Cluster's mul-heavy unit)
    //   0 → L-PE (mul-heavy opcodes short-circuit to lower_required)
    parameter MUL_OPS_SUPPORTED      = 1,
    parameter DIV_OPS_SUPPORTED      = 1,
    parameter NON_MUL_OPS_SUPPORTED  = 1
) (
    input                       clk,
    input                       rst,

    // ---- Primary input token ----
    input                       in_valid,
    input  [INSTR_WIDTH-1:0]    in_instruction,
    input  [TAG_WIDTH-1:0]      in_tag,
    input  [ADDR_WIDTH-1:0]     in_payload,

    // ---- Secondary operand input (B-side) ----
    input                       in_b_valid,
    input  [ADDR_WIDTH-1:0]     in_b_payload,

    // ---- Output token ----
    output [TAG_WIDTH-1:0]      out_tag,
    output [ADDR_WIDTH-1:0]     out_payload,
    output [7:0]                out_opcode,
    output [7:0]                out_frag_hdr,   // v1.5 §17
    output                      out_valid,

    // ---- Memory side-channel (forwarded by the Cluster to HIU) ----
    output                      memory_req,
    output [ADDR_WIDTH-1:0]     mem_addr,

    // ---- Diagnostics ----
    output                      error_flag,
    output                      lower_required,

    // ---- OPREF reflection (combinational; used by Cluster routing) ----
    output [3:0]                opref_src_kind_out,
    output [3:0]                opref_port_id_out,
    output [7:0]                opref_noc_route_out
);

    /* verilator lint_off UNUSEDPARAM */
    /* verilator lint_off UNUSEDSIGNAL */
    /* verilator lint_off WIDTHEXPAND */
    // PE_X / PE_Y are reserved for future use by the Cluster router (per-PE
    // diagnostics, NoC source identification when answering
    // OPERAND_REF.src_kind=1 requests). They have no effect on the current
    // decoder, but we keep them in the port list (and a localparam reference
    // here) so the synthesizer doesn't strip them away — future passes will
    // bind them to the routing layer.
    localparam [31:0] _PE_COORD_RESERVED =
        ({28'h0, PE_X[3:0]} << 16) | {28'h0, PE_Y[3:0]};
    /* verilator lint_on WIDTHEXPAND */
    /* verilator lint_on UNUSEDSIGNAL */
    /* verilator lint_on UNUSEDPARAM */

    // v1.5.2 §19 — PE.v is a single-PE wrapper without upstream fabric
    // fragment reassembly. Tie wide input to 0; wide outputs are exposed
    // internally only (no external port).
    /* verilator lint_off UNUSEDSIGNAL */
    wire [1023:0] pe_dec_input_payload_wide_out;
    wire          pe_dec_input_payload_wide_valid_out;
    /* verilator lint_on UNUSEDSIGNAL */

    ISA_Decoder #(
        .ADDR_WIDTH            (ADDR_WIDTH),
        .TAG_WIDTH             (TAG_WIDTH),
        .MAX_EH                (MAX_EH),
        .INSTR_WIDTH           (INSTR_WIDTH),
        .MUL_OPS_SUPPORTED     (MUL_OPS_SUPPORTED),
        .DIV_OPS_SUPPORTED     (DIV_OPS_SUPPORTED),
        .NON_MUL_OPS_SUPPORTED (NON_MUL_OPS_SUPPORTED)
    ) u_decoder (
        .clk                  (clk),
        .rst                  (rst),
        .token_valid          (in_valid),
        .instruction          (in_instruction),
        .input_tag            (in_tag),
        .input_payload        (in_payload),
        .input_payload_b      (in_b_payload),
        .input_payload_b_valid(in_b_valid),
        .input_payload_wide        (1024'h0),
        .input_payload_wide_valid  (1'b0),
        .output_payload       (out_payload),
        .output_tag           (out_tag),
        .output_valid         (out_valid),
        .opcode_out           (out_opcode),
        .output_frag_hdr      (out_frag_hdr),
        .dec_input_payload_wide_out       (pe_dec_input_payload_wide_out),
        .dec_input_payload_wide_valid_out (pe_dec_input_payload_wide_valid_out),
        .memory_req           (memory_req),
        .mem_addr             (mem_addr),
        .error_flag           (error_flag),
        .lower_required       (lower_required),
        .opref_src_kind_out   (opref_src_kind_out),
        .opref_port_id_out    (opref_port_id_out),
        .opref_noc_route_out  (opref_noc_route_out)
    );

endmodule
