// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

// =============================================================================
// Top_Core.v — Single-PE top-level wrapper.
//
// Wires ISA_Decoder.v together with HIU.v so a token-driven LOAD/STORE
// reaches the IOMMU/DMA engine without any external glue logic. This is
// the structural integration step on the roadmap (claude.md §7) and
// stands in as the minimal synthesizable unit before the PE/Cluster/Pod
// hierarchy is built up.
//
// Internal wiring summary:
//
//   ISA_Decoder.memory_req   →  HIU.dma_req
//   ISA_Decoder.mem_addr     →  HIU.virt_addr
//   HIU.dma_ack              →  observable at top-level (mem_dma_ack)
//   HIU.phys_addr            →  observable at top-level (mem_phys_addr)
//   HIU.dma_data_out         →  observable at top-level (mem_data_out)
//
// HIU's security / IOMMU configuration inputs (chacha_*, partition_id,
// shadow_*, ats_req, pri_req, context_switch, interface_type) are exposed
// as top-level inputs so a higher layer (Pod-level controller) can drive
// them; in single-core unit tests the testbench ties most of them to 0.
//
// Notes / scope of this iteration:
//   * The HIU latches a memory request and processes it over many cycles
//     (TLB lookup → ChaCha20 mask → DMA exec). ISA_Decoder is single-cycle.
//     This module does **not** loop returned data back into the decoder
//     yet — that is the responsibility of the future PE-level instruction
//     scheduler (claude.md §7 / stage 2). Here we simply guarantee the
//     request flows out and the ack flows back at the top boundary.
//   * `memory_req` is a one-cycle pulse from ISA_Decoder. HIU has its own
//     `dma_req_pending` latch internally, so the pulse is captured.
// =============================================================================

module Top_Core #(
    parameter ADDR_WIDTH       = 64,
    parameter TAG_WIDTH        = 80,
    parameter MAX_EH           = 4,
    parameter INSTR_WIDTH      = 32 + MAX_EH*96,    // = 416
    parameter DMA_DATA_WIDTH   = 32,
    parameter MAX_REGIONS      = 16,
    parameter TLB_ENTRIES      = 16,
    parameter NUM_PARTITIONS   = 4,
    parameter CHACHA_ROUNDS    = 20,
    parameter DUMMY_CYCLES     = 8
) (
    input                              clk,
    input                              rst,

    // ---- Token-side interface ----
    input                              token_valid,
    input  [INSTR_WIDTH-1:0]           instruction,
    input  [TAG_WIDTH-1:0]             input_tag,
    input  [ADDR_WIDTH-1:0]            input_payload,
    input  [ADDR_WIDTH-1:0]            input_payload_b,
    input                              input_payload_b_valid,

    output [ADDR_WIDTH-1:0]            output_payload,
    output [TAG_WIDTH-1:0]             output_tag,
    output                             output_valid,
    output [7:0]                       opcode_out,
    output                             error_flag,
    output                             lower_required,

    // ---- OPREF reflection (used by Pod-level routing controller) ----
    output [3:0]                       opref_src_kind,
    output [3:0]                       opref_port_id,
    output [7:0]                       opref_noc_route,

    // ---- HIU memory-side interface ----
    input  [DMA_DATA_WIDTH-1:0]        mem_data_in,
    output [DMA_DATA_WIDTH-1:0]        mem_data_out,
    output [ADDR_WIDTH-1:0]            mem_phys_addr,
    output                             mem_access_granted,
    output                             mem_dma_ack,

    // ---- HIU configuration (typically driven by Pod-level controller) ----
    input  [191:0]                     chacha_nonce,
    input  [255:0]                     chacha_key,
    input                              context_switch,
    input  [1:0]                       partition_id,
    input  [1:0]                       interface_type,
    input                              ats_req,
    input                              pri_req,
    input  [ADDR_WIDTH-1:0]            shadow_write_start,
    input  [ADDR_WIDTH-1:0]            shadow_write_end,
    input                              shadow_write_en,
    input  [3:0]                       shadow_index,

    // ---- HIU response signals exposed for system-level observability ----
    output                             ats_resp,
    output                             pri_resp,

    // ---- TRNG outputs (forwarded from HIU) ----
    output [7:0]                       rng_raw,
    output                             rng_raw_valid,
    output [63:0]                      rng_word,
    output                             rng_word_valid,
    output                             trng_unhealthy
);

    // -------------------------------------------------------------------------
    // Decoder ↔ HIU wiring
    // -------------------------------------------------------------------------
    wire                       dec_memory_req;
    wire [ADDR_WIDTH-1:0]      dec_mem_addr;

    // -------------------------------------------------------------------------
    // ISA_Decoder instance — execution + control
    // -------------------------------------------------------------------------
    ISA_Decoder #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .TAG_WIDTH  (TAG_WIDTH),
        .MAX_EH     (MAX_EH),
        .INSTR_WIDTH(INSTR_WIDTH)
    ) u_decoder (
        .clk                  (clk),
        .rst                  (rst),
        .token_valid          (token_valid),
        .instruction          (instruction),
        .input_tag            (input_tag),
        .input_payload        (input_payload),
        .input_payload_b      (input_payload_b),
        .input_payload_b_valid(input_payload_b_valid),
        .output_payload       (output_payload),
        .output_tag           (output_tag),
        .output_valid         (output_valid),
        .opcode_out           (opcode_out),
        .memory_req           (dec_memory_req),
        .mem_addr             (dec_mem_addr),
        .error_flag           (error_flag),
        .lower_required       (lower_required),
        .opref_src_kind_out   (opref_src_kind),
        .opref_port_id_out    (opref_port_id),
        .opref_noc_route_out  (opref_noc_route)
    );

    // -------------------------------------------------------------------------
    // HIU instance — IOMMU / Zero-Copy DMA / ChaCha20 masking
    //
    // ISA_Decoder.memory_req is a one-cycle pulse; HIU latches it
    // internally as `dma_req_pending`, so the pulse is sufficient.
    //
    // For STORE the data to write is taken from the low half of the
    // outgoing payload (the operand the decoder produced); for LOAD
    // the bus brings the loaded word in via mem_data_in.
    // -------------------------------------------------------------------------
    wire [DMA_DATA_WIDTH-1:0] hiu_data_in;
    assign hiu_data_in = (opcode_out == 8'h05)                        // STORE
                       ? input_payload[DMA_DATA_WIDTH-1:0]
                       : mem_data_in;

    HIU #(
        .ADDR_WIDTH    (ADDR_WIDTH),
        .MAX_REGIONS   (MAX_REGIONS),
        .DATA_WIDTH    (DMA_DATA_WIDTH),
        .TLB_ENTRIES   (TLB_ENTRIES),
        .NUM_PARTITIONS(NUM_PARTITIONS),
        .CHACHA_ROUNDS (CHACHA_ROUNDS),
        .DUMMY_CYCLES  (DUMMY_CYCLES)
    ) u_hiu (
        .clk               (clk),
        .rst               (rst),
        .virt_addr         (dec_mem_addr),
        .dma_req           (dec_memory_req),
        .dma_data_in       (hiu_data_in),
        .interface_type    (interface_type),
        .ats_req           (ats_req),
        .pri_req           (pri_req),
        .shadow_write_start(shadow_write_start),
        .shadow_write_end  (shadow_write_end),
        .shadow_write_en   (shadow_write_en),
        .shadow_index      (shadow_index),
        .context_switch    (context_switch),
        .partition_id      (partition_id),
        .chacha_nonce      (chacha_nonce),
        .chacha_key        (chacha_key),
        .phys_addr         (mem_phys_addr),
        .dma_data_out      (mem_data_out),
        .dma_ack           (mem_dma_ack),
        .access_granted    (mem_access_granted),
        .ats_resp          (ats_resp),
        .pri_resp          (pri_resp),
        .rng_raw           (rng_raw),
        .rng_raw_valid     (rng_raw_valid),
        .rng_word          (rng_word),
        .rng_word_valid    (rng_word_valid),
        .trng_unhealthy    (trng_unhealthy)
    );

endmodule
