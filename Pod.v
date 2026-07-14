// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

// =============================================================================
// Pod.v — CLUSTER_ROWS × CLUSTER_COLS grid of Clusters.
//
// Permitted geometries (validated at elaboration time):
//     (CLUSTER_ROWS, CLUSTER_COLS) ∈ {(2,2), (2,4), (4,2), (4,4)}
//
// The CLUSTER_ROWS / CLUSTER_COLS parameters are independent of the
// underlying PE_ROWS / PE_COLS in each Cluster. A "256-PE" research-spec
// pod is reached by setting (CLUSTER_ROWS, CLUSTER_COLS) = (4,4) AND each
// instantiated Cluster's (PE_ROWS, PE_COLS) = (4,4). Default values give a
// 16-PE debug Pod.
//
// Routing model
// -------------
//   * One external input port drives the Pod.
//   * Tag's `port_context_id[7:4]` selects the target Cluster within the
//     Pod; `[3:0]` continues to select the PE inside that Cluster (handled
//     by Cluster.v's existing routing logic).
//   * All Clusters' external outputs are OR-merged at the Pod boundary,
//     same pattern as Cluster's PE-level merge.
//
// NoC operand routing across Clusters is *not* yet supported at this
// level — the bank backing `OPERAND_REF.src_kind=1` lookups is a per-
// Cluster structure. Cross-Cluster operand routing is a future iteration.
//
// Topology-independence
// ---------------------
//   The binary stream never references CLUSTER_X / CLUSTER_Y. The Pod
//   simply maps the 4-bit cluster index from the tag onto a physical
//   grid coordinate at elaboration time, exactly mirroring the
//   intra-Cluster mapping in Cluster.v.
// =============================================================================

module Pod #(
    parameter ADDR_WIDTH    = 64,
    parameter TAG_WIDTH     = 80,
    parameter MAX_EH        = 4,
    parameter INSTR_WIDTH   = 32 + MAX_EH*96,    // = 416
    parameter PE_ROWS       = 2,
    parameter PE_COLS       = 2,
    parameter CLUSTER_ROWS  = 2,
    parameter CLUSTER_COLS  = 2
) (
    input                       clk,
    input                       rst,

    // ---- External input ----
    input                       ext_valid,
    input  [INSTR_WIDTH-1:0]    ext_instruction,
    input  [TAG_WIDTH-1:0]      ext_tag,
    input  [ADDR_WIDTH-1:0]     ext_payload,
    input  [ADDR_WIDTH-1:0]     ext_payload_b,
    input                       ext_payload_b_valid,

    // ---- TRNG broadcast (Pod-wide; sourced from HIU one level up) ----
    // Phase 2: clusters use this to satisfy OPREF.src_kind=2 (RNG bank).
    input  [63:0]               rng_word,
    input                       rng_word_valid,

    // ---- External output ----
    output [TAG_WIDTH-1:0]      ext_out_tag,
    output [ADDR_WIDTH-1:0]     ext_out_payload,
    output [7:0]                ext_out_opcode,
    output [7:0]                ext_out_frag_hdr,   // v1.5 §17
    output                      ext_out_valid,

    // ---- Memory side-channel (forwarded from any Cluster to a Pod-level HIU) ----
    output                      mem_req,
    output [ADDR_WIDTH-1:0]     mem_addr,

    // ---- Aggregated diagnostics ----
    output                      any_error_flag,
    output                      any_lower_required
);

    localparam NUM_CLUSTERS = CLUSTER_ROWS * CLUSTER_COLS;

    // -------------------------------------------------------------------------
    // Compile-time geometry guard
    // -------------------------------------------------------------------------
    localparam VALID_CLUSTER_GEOM =
        ((CLUSTER_ROWS == 2) && (CLUSTER_COLS == 2 || CLUSTER_COLS == 4)) ||
        ((CLUSTER_ROWS == 4) && (CLUSTER_COLS == 2 || CLUSTER_COLS == 4));

    initial begin
        if (!VALID_CLUSTER_GEOM) begin
            $display("Pod: (CLUSTER_ROWS=%0d, CLUSTER_COLS=%0d) not in {(2,2),(2,4),(4,2),(4,4)}", CLUSTER_ROWS, CLUSTER_COLS);
            $fatal(1);
        end
    end

    // -------------------------------------------------------------------------
    // Per-Cluster output buses
    // -------------------------------------------------------------------------
    wire [TAG_WIDTH-1:0]   cl_out_tag       [0:NUM_CLUSTERS-1];
    wire [ADDR_WIDTH-1:0]  cl_out_payload   [0:NUM_CLUSTERS-1];
    wire [7:0]             cl_out_opcode    [0:NUM_CLUSTERS-1];
    wire [7:0]             cl_out_frag_hdr  [0:NUM_CLUSTERS-1];   // v1.5 §17
    wire                   cl_out_valid     [0:NUM_CLUSTERS-1];
    wire                   cl_mem_req     [0:NUM_CLUSTERS-1];
    wire [ADDR_WIDTH-1:0]  cl_mem_addr    [0:NUM_CLUSTERS-1];
    wire                   cl_error       [0:NUM_CLUSTERS-1];
    wire                   cl_lower       [0:NUM_CLUSTERS-1];

    // -------------------------------------------------------------------------
    // Cluster index from port_context_id[7:4]; PE index within each
    // Cluster comes from [3:0] (handled inside Cluster.v).
    // -------------------------------------------------------------------------
    /* verilator lint_off UNUSEDSIGNAL */
    wire [15:0] in_pcid = ext_tag[31:16];
    /* verilator lint_on UNUSEDSIGNAL */
    wire [3:0]  cluster_idx = in_pcid[7:4];

    // -------------------------------------------------------------------------
    // Cluster grid
    // -------------------------------------------------------------------------
    genvar cx, cy;
    generate
        for (cy = 0; cy < CLUSTER_ROWS; cy = cy + 1) begin : g_crow
            for (cx = 0; cx < CLUSTER_COLS; cx = cx + 1) begin : g_ccol
                localparam CIDX = cy * CLUSTER_COLS + cx;
                wire cl_valid = ext_valid && (cluster_idx == CIDX[3:0]);

                Cluster #(
                    .ADDR_WIDTH (ADDR_WIDTH),
                    .TAG_WIDTH  (TAG_WIDTH),
                    .MAX_EH     (MAX_EH),
                    .INSTR_WIDTH(INSTR_WIDTH),
                    .PE_ROWS    (PE_ROWS),
                    .PE_COLS    (PE_COLS)
                ) u_cluster (
                    .clk                 (clk),
                    .rst                 (rst),
                    .ext_valid           (cl_valid),
                    .ext_instruction     (ext_instruction),
                    .ext_tag             (ext_tag),
                    .ext_payload         (ext_payload),
                    .ext_payload_b       (ext_payload_b),
                    .ext_payload_b_valid (cl_valid && ext_payload_b_valid),
                    .rng_word            (rng_word),
                    .rng_word_valid      (rng_word_valid),
                    .ext_out_tag         (cl_out_tag[CIDX]),
                    .ext_out_payload     (cl_out_payload[CIDX]),
                    .ext_out_opcode      (cl_out_opcode[CIDX]),
                    .ext_out_frag_hdr    (cl_out_frag_hdr[CIDX]),
                    .ext_out_valid       (cl_out_valid[CIDX]),
                    .mem_req             (cl_mem_req[CIDX]),
                    .mem_addr            (cl_mem_addr[CIDX]),
                    .any_error_flag      (cl_error[CIDX]),
                    .any_lower_required  (cl_lower[CIDX])
                );
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // OR-merge across clusters. Single Cluster active per cycle in this
    // routing model, so OR is unambiguous.
    // -------------------------------------------------------------------------
    integer i;
    reg [TAG_WIDTH-1:0]  m_tag;
    reg [ADDR_WIDTH-1:0] m_payload;
    reg [7:0]            m_opcode;
    reg [7:0]            m_frag_hdr;   // v1.5 §17
    reg                  m_valid;
    reg                  m_mem_req;
    reg [ADDR_WIDTH-1:0] m_mem_addr;
    reg                  m_err, m_lwr;

    always @(*) begin
        m_tag      = {TAG_WIDTH{1'b0}};
        m_payload  = {ADDR_WIDTH{1'b0}};
        m_opcode   = 8'h00;
        m_frag_hdr = 8'h00;
        m_valid    = 1'b0;
        m_mem_req  = 1'b0;
        m_mem_addr = {ADDR_WIDTH{1'b0}};
        m_err      = 1'b0;
        m_lwr      = 1'b0;
        for (i = 0; i < NUM_CLUSTERS; i = i + 1) begin
            if (cl_out_valid[i] && !m_valid) begin
                m_tag      = cl_out_tag[i];
                m_payload  = cl_out_payload[i];
                m_opcode   = cl_out_opcode[i];
                m_frag_hdr = cl_out_frag_hdr[i];
                m_valid    = 1'b1;
            end
            if (cl_mem_req[i] && !m_mem_req) begin
                m_mem_req  = 1'b1;
                m_mem_addr = cl_mem_addr[i];
            end
            m_err = m_err | cl_error[i];
            m_lwr = m_lwr | cl_lower[i];
        end
    end

    assign ext_out_tag        = m_tag;
    assign ext_out_payload    = m_payload;
    assign ext_out_opcode     = m_opcode;
    assign ext_out_frag_hdr   = m_frag_hdr;
    assign ext_out_valid      = m_valid;
    assign mem_req            = m_mem_req;
    assign mem_addr           = m_mem_addr;
    assign any_error_flag     = m_err;
    assign any_lower_required = m_lwr;

endmodule
