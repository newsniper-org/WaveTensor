// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

// =============================================================================
// Cluster.v — PE_ROWS × PE_COLS grid of L-PE_Cores + 1 stripped MATMUL_UNIT
//             with a single shared EHDecode frontend.
//
// Permitted geometries (validated at elaboration time):
//     (PE_ROWS, PE_COLS) ∈ {(2,2), (2,4), (4,2), (4,4)}
//
// (j) Cluster-shared-frontend layout (this iteration):
//
//                       ext_instruction / tag / payload(s)
//                                  │
//                                  ▼
//     ┌────────────────────────────────────────────────────┐
//     │              EHDecode  (×1 per cluster)             │
//     │  - chain walk, EH parse, legality, tag match,        │
//     │    forwarded_tag, dec_* stage-1 register pipeline    │
//     └──────────┬─────────────────────────────┬───────────┘
//                │ DecodedBus (broadcast)        │ opref_*_out (combinational)
//                ▼                                ▼
//      ┌──────────────────┐               ┌─────────────────┐
//      │  N L-PE_Cores    │ ───outputs──> │  Cluster output │
//      │  (per port_idx)  │               │   OR-merge       │
//      └──────────────────┘               └─────────────────┘
//      ┌──────────────────┐
//      │ M-UNIT PE_Core   │ (mul-only, NON_MUL_OPS_SUPPORTED=0)
//      │   (mul-heavy)    │
//      └──────────────────┘
//
// Routing
// -------
//   * Cluster combinationally extracts opcode (= ext_instruction[31:24]).
//   * `is_mul_op` (∈ {MUL,MATMUL,EINSUM,EUCLID_NORM}) → MATMUL_UNIT.
//   * Otherwise → the L-PE_Core whose linear index matches
//     port_context_id[3:0] from the tag.
//   * `pe_active[i]` is the per-unit gate; only one unit fires per cycle.
//
// Outputs OR-merge across all N L-PE_Cores + the MATMUL_UNIT. Bank for
// OPREF.src_kind=1 lookups uses (L-PE registered output | MATMUL_UNIT
// per-target bank), tracked by `last_was_mu[k]`.
//
// Topology-independence is preserved: the binary still names only
// `port_context_id`; physical (PE_X, PE_Y) and the MATMUL_UNIT location
// are all routing decisions handled here.
// =============================================================================

module Cluster #(
    parameter ADDR_WIDTH  = 64,
    parameter TAG_WIDTH   = 80,
    parameter MAX_EH      = 4,
    parameter INSTR_WIDTH = 32 + MAX_EH*96,    // = 416
    parameter PE_ROWS     = 2,
    parameter PE_COLS     = 2
) (
    input                       clk,
    input                       rst,

    input                       ext_valid,
    input  [INSTR_WIDTH-1:0]    ext_instruction,
    input  [TAG_WIDTH-1:0]      ext_tag,
    input  [ADDR_WIDTH-1:0]     ext_payload,
    input  [ADDR_WIDTH-1:0]     ext_payload_b,
    input                       ext_payload_b_valid,
    // v1.5.1 §18 — incoming wave-token fragment header. 0x00 = single-
    // fragment (legacy); non-zero enters the reassembly buffer. See
    // wt64v1_spec.md §18 and noc_fragmentation_design.md.
    input  [7:0]                ext_frag_hdr,

    // ---- TRNG broadcast (Phase 2 — OPREF.src_kind=2 source) ----
    input  [63:0]               rng_word,
    input                       rng_word_valid,

    output [TAG_WIDTH-1:0]      ext_out_tag,
    output [ADDR_WIDTH-1:0]     ext_out_payload,
    output [7:0]                ext_out_opcode,
    output [7:0]                ext_out_frag_hdr,   // v1.5 §17
    output                      ext_out_valid,

    output                      mem_req,
    output [ADDR_WIDTH-1:0]     mem_addr,

    output                      any_error_flag,
    output                      any_lower_required
);

    localparam NUM_PES = PE_ROWS * PE_COLS;

    // -------------------------------------------------------------------------
    // v1.5.1 §18 — Fragment reassembly buffer (single-slot MVP)
    //
    // Collects wave-token fragments and combinationally assembles them into
    // a wide payload when the LAST fragment arrives. Legacy single-fragment
    // (ext_frag_hdr = 0x00) bypasses the buffer entirely for zero-latency
    // legacy path — all v1.0..1.4 primitives take this fast path.
    //
    // Single-slot: supports 1 concurrent multi-fragment wave. Fragment
    // sequences from different tags cannot interleave in v1.5.1; the second
    // wave silently displaces the first's partial state. Multi-slot buffer
    // is a v1.5.1b extension. See wt64v1_spec.md §18 and
    // noc_fragmentation_design.md §5.
    //
    // Downstream consumption (thread `frag_reass_wide` into a wide
    // dec_input_payload path) is deferred to v1.5.2. For v1.5.1 the signals
    // are exposed for hierarchical test access (`dut.u_cluster.frag_...`).
    // -------------------------------------------------------------------------
    localparam FRAG_MAX = 16;

    /* verilator lint_off UNUSEDSIGNAL */
    reg [ADDR_WIDTH-1:0] frag_data [0:FRAG_MAX-1];
    reg [FRAG_MAX-1:0]   frag_mask;
    reg [3:0]            frag_total_m1;
    reg [TAG_WIDTH-1:0]  frag_tag_reg;
    reg                  frag_active;
    /* verilator lint_on UNUSEDSIGNAL */

    wire [3:0] frag_in_idx    = ext_frag_hdr[7:4];
    wire [3:0] frag_in_tot_m1 = ext_frag_hdr[3:0];
    wire       frag_in_multi  = ext_valid && (ext_frag_hdr != 8'h00);
    wire       frag_same_tag  = frag_active && (ext_tag == frag_tag_reg);

    // Mask bit for the arriving fragment
    wire [FRAG_MAX-1:0] frag_mask_add = frag_in_multi
                                       ? ({15'h0, 1'b1} << frag_in_idx)
                                       : {FRAG_MAX{1'b0}};

    // Mask AFTER this cycle's write:
    //   - new slot start (idle OR mismatched tag): just the arriving bit
    //   - continue existing:                       OR into accumulated mask
    wire [FRAG_MAX-1:0] frag_mask_after =
        (frag_active && frag_same_tag) ? (frag_mask | frag_mask_add)
                                       : frag_mask_add;

    // Total field to compare against — from either the arriving fragment
    // (new slot) or the stored slot (continuing).
    wire [3:0] frag_tot_ref =
        (frag_active && frag_same_tag) ? frag_total_m1 : frag_in_tot_m1;

    // Full mask: bits [0 .. tot_ref] set.
    wire [FRAG_MAX-1:0] frag_mask_full =
        ({15'h0, 1'b1} << (frag_tot_ref + 4'h1)) - {{(FRAG_MAX-1){1'b0}}, 1'b1};

    // Completion pulse (combinational): fires the same cycle as the last
    // fragment arrival. Consumers must sample on this cycle.
    /* verilator lint_off UNUSEDSIGNAL */
    wire frag_reass_valid = frag_in_multi && (frag_mask_after == frag_mask_full);
    /* verilator lint_on UNUSEDSIGNAL */

    // Wide payload (combinational): overlays this-cycle's fragment onto
    // stored data. On the completion cycle, this holds the fully assembled
    // wave payload — up to 16 × 64 = 1024 bits.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [FRAG_MAX*ADDR_WIDTH-1:0] frag_reass_wide;
    /* verilator lint_on UNUSEDSIGNAL */
    genvar gfw;
    generate
        for (gfw = 0; gfw < FRAG_MAX; gfw = gfw + 1) begin : g_frag_wide
            assign frag_reass_wide[gfw*ADDR_WIDTH +: ADDR_WIDTH] =
                (frag_in_multi && (frag_in_idx == gfw[3:0])) ? ext_payload
                                                             : frag_data[gfw];
        end
    endgenerate

    integer ffi;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (ffi = 0; ffi < FRAG_MAX; ffi = ffi + 1)
                frag_data[ffi] <= {ADDR_WIDTH{1'b0}};
            frag_mask     <= {FRAG_MAX{1'b0}};
            frag_total_m1 <= 4'h0;
            frag_tag_reg  <= {TAG_WIDTH{1'b0}};
            frag_active   <= 1'b0;
        end else if (frag_in_multi) begin
            frag_data[frag_in_idx] <= ext_payload;
            if (!frag_active || !frag_same_tag) begin
                // Allocate new slot (from idle OR displace mismatched tag)
                frag_tag_reg  <= ext_tag;
                frag_total_m1 <= frag_in_tot_m1;
                frag_mask     <= frag_mask_add;
                frag_active   <= 1'b1;
            end else begin
                frag_mask <= frag_mask | frag_mask_add;
            end
            // Deactivate on completion (last non-blocking wins)
            if (frag_reass_valid) begin
                frag_active <= 1'b0;
                frag_mask   <= {FRAG_MAX{1'b0}};
            end
        end
    end

    // ---- Compile-time geometry guard ----------------------------------------
    localparam VALID_GEOM =
        ((PE_ROWS == 2) && (PE_COLS == 2 || PE_COLS == 4)) ||
        ((PE_ROWS == 4) && (PE_COLS == 2 || PE_COLS == 4));
    initial begin
        if (!VALID_GEOM) begin
            $display("Cluster: (PE_ROWS=%0d, PE_COLS=%0d) not in {(2,2),(2,4),(4,2),(4,4)}", PE_ROWS, PE_COLS);
            $fatal(1);
        end
    end

    // -------------------------------------------------------------------------
    // Op-class classifiers (combinational, before EHDecode latches).
    //
    // L-PE handles the simple integer/shape ops; MATMUL_UNIT handles the
    // mul-heavy ops; DIV-UNIT handles the 64-bit divide/modulo ops. Each
    // op-class group routes to exactly ONE unit per cluster.
    // -------------------------------------------------------------------------
    wire [7:0] ext_opcode = ext_instruction[31:24];
    wire is_mul_op = (ext_opcode == 8'h12)
                  || (ext_opcode == 8'h30)
                  || (ext_opcode == 8'h32)
                  || (ext_opcode == 8'h43);
    wire is_div_op = (ext_opcode == 8'h13)   // DIV
                  || (ext_opcode == 8'h1C)   // MOD
                  || (ext_opcode == 8'h1D);  // DIVMOD
    // v1.5.2 §19 — wave-complete gate. Legacy single-fragment
    // (ext_frag_hdr == 0x00) fires immediately. Multi-fragment waves
    // fire ONLY on the last fragment's cycle (frag_reass_valid pulse).
    // Intermediate fragments are absorbed by the reassembly buffer without
    // triggering EHDecode or PE_active pipelines.
    wire wave_complete = ext_valid
                       && ((ext_frag_hdr == 8'h00) || frag_reass_valid);
    wire ext_to_mu  = wave_complete &&  is_mul_op;
    wire ext_to_du  = wave_complete &&  is_div_op;
    wire ext_to_lpe = wave_complete && !is_mul_op && !is_div_op;

    // -------------------------------------------------------------------------
    // Logical port_context_id → linear PE index
    // -------------------------------------------------------------------------
    /* verilator lint_off UNUSEDSIGNAL */
    wire [15:0] in_pcid = ext_tag[31:16];
    /* verilator lint_on UNUSEDSIGNAL */
    wire [3:0]  target_idx = in_pcid[3:0];

    // -------------------------------------------------------------------------
    // Cluster-shared EHDecode — one instance for all units.
    // The `in_valid` pulse is gated to whichever destination the opcode
    // selects so EHDecode's stage-1 dec_valid only rises for the cycle that
    // actually consumes data.
    // -------------------------------------------------------------------------
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
    /* verilator lint_off UNUSEDSIGNAL */
    wire [47:0]                dec_eff_subscript_hi;   // v1.3 §16
    wire [63:0]                dec_eff_imm64_hi;       // v1.4 §17
    wire [1023:0]              dec_input_payload_wide; // v1.5.2 §19
    wire                       dec_input_payload_wide_valid;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [7:0]                 dec_eff_output_port_id;
    wire [7:0]                 dec_eff_precision;
    wire [31:0]                dec_wave_number;
    wire [15:0]                dec_thread_id;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [15:0]                dec_port_context_id;
    /* verilator lint_on UNUSEDSIGNAL */

    // OPREF reflection (combinational from ext_instruction) — used by the
    // bank-routing combinational logic so the chosen `cluster_b_payload` is
    // ready in time for EHDecode's stage-1 latch on the same edge.
    wire [3:0] eff_opref_kind_c;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [3:0] eff_opref_port_c;
    wire [7:0] eff_opref_route_c;
    /* verilator lint_on UNUSEDSIGNAL */

    // -------------------------------------------------------------------------
    // Bank routing (OPREF.src_kind=1) — must compute cluster_b_payload before
    // EHDecode's stage-1 latch, since input_payload_b feeds dec_input_payload_b.
    // We use the combinational opref reflection from EHDecode's parallel path.
    // -------------------------------------------------------------------------
    // OPREF.src_kind decoding for the B-side operand:
    //   0 — direct ext_payload_b (default)
    //   1 — NoC bank (last L-PE / M-UNIT / DIV-UNIT output at bank[route])
    //   2 — TRNG (Phase 2): rng_word from Pod broadcast
    wire use_noc_b = (eff_opref_kind_c == 4'h1);
    wire use_rng_b = (eff_opref_kind_c == 4'h2);

    // (Forward declarations of bank sources — defined below the unit array.)
    wire [ADDR_WIDTH-1:0] pe_out_payload   [0:NUM_PES-1];
    wire                  pe_out_valid     [0:NUM_PES-1];
    reg  [ADDR_WIDTH-1:0] mu_bank_reg      [0:NUM_PES-1];
    reg  [ADDR_WIDTH-1:0] du_bank_reg      [0:NUM_PES-1];
    reg  [NUM_PES-1:0]    last_was_mu;
    reg  [NUM_PES-1:0]    last_was_du;

    reg [ADDR_WIDTH-1:0] bank_selected;
    integer kbank;
    always @(*) begin
        bank_selected = {ADDR_WIDTH{1'b0}};
        for (kbank = 0; kbank < NUM_PES; kbank = kbank + 1) begin
            if ({4'h0, eff_opref_route_c[3:0]} == kbank[7:0]) begin
                if      (last_was_mu[kbank]) bank_selected = mu_bank_reg[kbank];
                else if (last_was_du[kbank]) bank_selected = du_bank_reg[kbank];
                else                         bank_selected = pe_out_payload[kbank];
            end
        end
    end

    wire [ADDR_WIDTH-1:0] cluster_b_payload =
        use_rng_b ? rng_word
      : use_noc_b ? bank_selected
      :             ext_payload_b;
    wire                  cluster_b_valid   =
        use_rng_b ? rng_word_valid
      : use_noc_b ? 1'b1
      :             ext_payload_b_valid;

    // -------------------------------------------------------------------------
    // EHDecode instance — its `in_valid` rises whenever the cluster has any
    // valid input (mul or non-mul); per-unit gating happens inside each
    // PE_Core via `pe_active`.
    // -------------------------------------------------------------------------
    // v1.5.2 §19 — payload selection: for multi-fragment waves, the low
    // 64-bit slot of the reassembled wide payload feeds legacy consumers;
    // for single-fragment (legacy), ext_payload passes through unchanged.
    wire [ADDR_WIDTH-1:0] ehdec_input_payload =
        (ext_frag_hdr == 8'h00) ? ext_payload
                                : frag_reass_wide[ADDR_WIDTH-1:0];

    EHDecode #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .TAG_WIDTH  (TAG_WIDTH),
        .MAX_EH     (MAX_EH),
        .INSTR_WIDTH(INSTR_WIDTH)
    ) u_ehdec (
        .clk                       (clk),
        .rst                       (rst),
        .in_valid                  (wave_complete),
        .instruction               (ext_instruction),
        .input_tag                 (ext_tag),
        .input_payload             (ehdec_input_payload),
        .input_payload_b           (cluster_b_payload),
        .input_payload_b_valid     (cluster_b_valid),
        .input_payload_wide        (frag_reass_wide),
        .input_payload_wide_valid  (frag_reass_valid),
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
        .dec_eff_subscript_hi      (dec_eff_subscript_hi),
        .dec_eff_imm64_hi          (dec_eff_imm64_hi),
        .dec_input_payload_wide       (dec_input_payload_wide),
        .dec_input_payload_wide_valid (dec_input_payload_wide_valid),
        .dec_eff_output_port_id    (dec_eff_output_port_id),
        .dec_eff_precision         (dec_eff_precision),
        .dec_wave_number           (dec_wave_number),
        .dec_thread_id             (dec_thread_id),
        .dec_port_context_id       (dec_port_context_id),
        .opref_src_kind_out        (eff_opref_kind_c),
        .opref_port_id_out         (eff_opref_port_c),
        .opref_noc_route_out       (eff_opref_route_c)
    );

    // -------------------------------------------------------------------------
    // Per-unit `pe_active` — pipelined to align with EHDecode's stage-1
    // latency. `pe_active_p` is what the corresponding PE_Core sees on the
    // cycle when its dec_* operand-bus carries the matching instruction.
    // -------------------------------------------------------------------------
    // 6-stage pipe to align with EHDecode's pipelined chain walk:
    //   ext_valid edge (1) → SLOT 0 (2) → SLOT 1 (3) → SLOT 2 (4) → SLOT 3 (5)
    //   → dec_* latch (6). pe_active is what PE_Core sees on the cycle when
    //   dec_valid=1 (Edge 6→7), so the registered value must be held in
    //   stage s6 during that interval.
    reg [NUM_PES-1:0] pe_active_lpe_s1, pe_active_lpe_s2, pe_active_lpe_s3,
                      pe_active_lpe_s4, pe_active_lpe_s5, pe_active_lpe_s6;
    reg               pe_active_mu_s1,  pe_active_mu_s2,  pe_active_mu_s3,
                      pe_active_mu_s4,  pe_active_mu_s5,  pe_active_mu_s6;
    reg               pe_active_du_s1,  pe_active_du_s2,  pe_active_du_s3,
                      pe_active_du_s4,  pe_active_du_s5,  pe_active_du_s6;
    reg [3:0]         mu_target_s1, mu_target_s2, mu_target_s3,
                      mu_target_s4, mu_target_s5, mu_target_s6;
    reg [3:0]         du_target_s1, du_target_s2, du_target_s3,
                      du_target_s4, du_target_s5, du_target_s6;
    wire [NUM_PES-1:0] pe_active_lpe_p = pe_active_lpe_s6;
    wire               pe_active_mu_p  = pe_active_mu_s6;
    wire               pe_active_du_p  = pe_active_du_s6;
    wire [3:0]         mu_target_p     = mu_target_s6;
    wire [3:0]         du_target_p     = du_target_s6;
    integer kk;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pe_active_lpe_s1 <= {NUM_PES{1'b0}};
            pe_active_lpe_s2 <= {NUM_PES{1'b0}};
            pe_active_lpe_s3 <= {NUM_PES{1'b0}};
            pe_active_lpe_s4 <= {NUM_PES{1'b0}};
            pe_active_lpe_s5 <= {NUM_PES{1'b0}};
            pe_active_lpe_s6 <= {NUM_PES{1'b0}};
            pe_active_mu_s1  <= 1'b0;
            pe_active_mu_s2  <= 1'b0;
            pe_active_mu_s3  <= 1'b0;
            pe_active_mu_s4  <= 1'b0;
            pe_active_mu_s5  <= 1'b0;
            pe_active_mu_s6  <= 1'b0;
            pe_active_du_s1  <= 1'b0;
            pe_active_du_s2  <= 1'b0;
            pe_active_du_s3  <= 1'b0;
            pe_active_du_s4  <= 1'b0;
            pe_active_du_s5  <= 1'b0;
            pe_active_du_s6  <= 1'b0;
            mu_target_s1     <= 4'h0;
            mu_target_s2     <= 4'h0;
            mu_target_s3     <= 4'h0;
            mu_target_s4     <= 4'h0;
            mu_target_s5     <= 4'h0;
            mu_target_s6     <= 4'h0;
            du_target_s1     <= 4'h0;
            du_target_s2     <= 4'h0;
            du_target_s3     <= 4'h0;
            du_target_s4     <= 4'h0;
            du_target_s5     <= 4'h0;
            du_target_s6     <= 4'h0;
        end else begin
            for (kk = 0; kk < NUM_PES; kk = kk + 1)
                pe_active_lpe_s1[kk] <= ext_to_lpe && (target_idx == kk[3:0]);
            pe_active_lpe_s2 <= pe_active_lpe_s1;
            pe_active_lpe_s3 <= pe_active_lpe_s2;
            pe_active_lpe_s4 <= pe_active_lpe_s3;
            pe_active_lpe_s5 <= pe_active_lpe_s4;
            pe_active_lpe_s6 <= pe_active_lpe_s5;
            pe_active_mu_s1  <= ext_to_mu;
            pe_active_mu_s2  <= pe_active_mu_s1;
            pe_active_mu_s3  <= pe_active_mu_s2;
            pe_active_mu_s4  <= pe_active_mu_s3;
            pe_active_mu_s5  <= pe_active_mu_s4;
            pe_active_mu_s6  <= pe_active_mu_s5;
            pe_active_du_s1  <= ext_to_du;
            pe_active_du_s2  <= pe_active_du_s1;
            pe_active_du_s3  <= pe_active_du_s2;
            pe_active_du_s4  <= pe_active_du_s3;
            pe_active_du_s5  <= pe_active_du_s4;
            pe_active_du_s6  <= pe_active_du_s5;
            mu_target_s1     <= target_idx;
            mu_target_s2     <= mu_target_s1;
            mu_target_s3     <= mu_target_s2;
            mu_target_s4     <= mu_target_s3;
            mu_target_s5     <= mu_target_s4;
            mu_target_s6     <= mu_target_s5;
            du_target_s1     <= target_idx;
            du_target_s2     <= du_target_s1;
            du_target_s3     <= du_target_s2;
            du_target_s4     <= du_target_s3;
            du_target_s5     <= du_target_s4;
            du_target_s6     <= du_target_s5;
        end
    end

    // -------------------------------------------------------------------------
    // Per-unit output buses
    // -------------------------------------------------------------------------
    wire [TAG_WIDTH-1:0]   pe_out_tag     [0:NUM_PES-1];
    wire [7:0]             pe_out_opcode  [0:NUM_PES-1];
    wire [7:0]             pe_out_frag_hdr[0:NUM_PES-1];   // v1.5 §17
    wire                   pe_mem_req     [0:NUM_PES-1];
    wire [ADDR_WIDTH-1:0]  pe_mem_addr    [0:NUM_PES-1];
    wire                   pe_error       [0:NUM_PES-1];
    wire                   pe_lower       [0:NUM_PES-1];

    // -------------------------------------------------------------------------
    // L-PE_Core grid
    // -------------------------------------------------------------------------
    genvar gx, gy;
    generate
        for (gy = 0; gy < PE_ROWS; gy = gy + 1) begin : g_row
            for (gx = 0; gx < PE_COLS; gx = gx + 1) begin : g_col
                localparam IDX = gy * PE_COLS + gx;
                PE_Core #(
                    .ADDR_WIDTH            (ADDR_WIDTH),
                    .TAG_WIDTH             (TAG_WIDTH),
                    .MUL_OPS_SUPPORTED     (0),
                    .DIV_OPS_SUPPORTED     (0),
                    .NON_MUL_OPS_SUPPORTED (1)
                ) u_lpe (
                    .clk                       (clk),
                    .rst                       (rst),
                    .pe_active                 (pe_active_lpe_p[IDX]),
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
                    .output_payload            (pe_out_payload[IDX]),
                    .output_tag                (pe_out_tag[IDX]),
                    .output_valid              (pe_out_valid[IDX]),
                    .opcode_out                (pe_out_opcode[IDX]),
                    .output_frag_hdr           (pe_out_frag_hdr[IDX]),
                    .memory_req                (pe_mem_req[IDX]),
                    .mem_addr                  (pe_mem_addr[IDX]),
                    .error_flag                (pe_error[IDX]),
                    .lower_required            (pe_lower[IDX])
                );
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // MATMUL_UNIT (stripped PE_Core: mul-only)
    // -------------------------------------------------------------------------
    wire [TAG_WIDTH-1:0]  mu_out_tag;
    wire [ADDR_WIDTH-1:0] mu_out_payload;
    wire [7:0]            mu_out_opcode;
    wire [7:0]            mu_out_frag_hdr;   // v1.5 §17
    wire                  mu_out_valid;
    wire                  mu_mem_req;
    wire [ADDR_WIDTH-1:0] mu_mem_addr;
    wire                  mu_error;
    wire                  mu_lower;

    PE_Core #(
        .ADDR_WIDTH            (ADDR_WIDTH),
        .TAG_WIDTH             (TAG_WIDTH),
        .MUL_OPS_SUPPORTED     (1),
        .DIV_OPS_SUPPORTED     (0),
        .NON_MUL_OPS_SUPPORTED (0)
    ) u_matmul_unit (
        .clk                       (clk),
        .rst                       (rst),
        .pe_active                 (pe_active_mu_p),
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
        .output_payload            (mu_out_payload),
        .output_tag                (mu_out_tag),
        .output_valid              (mu_out_valid),
        .opcode_out                (mu_out_opcode),
        .output_frag_hdr           (mu_out_frag_hdr),
        .memory_req                (mu_mem_req),
        .mem_addr                  (mu_mem_addr),
        .error_flag                (mu_error),
        .lower_required            (mu_lower)
    );

    // -------------------------------------------------------------------------
    // DIV-UNIT (stripped PE_Core: div/mod-only). Mirror of MATMUL_UNIT —
    // one per cluster, handles 0x13 / 0x1C / 0x1D so the four L-PEs can
    // DCE their 64-bit fabric divider (the per-PE LUT hog at ~10 K LUT).
    // -------------------------------------------------------------------------
    wire [TAG_WIDTH-1:0]  du_out_tag;
    wire [ADDR_WIDTH-1:0] du_out_payload;
    wire [7:0]            du_out_opcode;
    wire [7:0]            du_out_frag_hdr;   // v1.5 §17
    wire                  du_out_valid;
    wire                  du_mem_req;
    wire [ADDR_WIDTH-1:0] du_mem_addr;
    wire                  du_error;
    wire                  du_lower;

    PE_Core #(
        .ADDR_WIDTH            (ADDR_WIDTH),
        .TAG_WIDTH             (TAG_WIDTH),
        .MUL_OPS_SUPPORTED     (0),
        .DIV_OPS_SUPPORTED     (1),
        .NON_MUL_OPS_SUPPORTED (0)
    ) u_div_unit (
        .clk                       (clk),
        .rst                       (rst),
        .pe_active                 (pe_active_du_p),
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
        .output_payload            (du_out_payload),
        .output_tag                (du_out_tag),
        .output_valid              (du_out_valid),
        .opcode_out                (du_out_opcode),
        .output_frag_hdr           (du_out_frag_hdr),
        .memory_req                (du_mem_req),
        .mem_addr                  (du_mem_addr),
        .error_flag                (du_error),
        .lower_required            (du_lower)
    );

    // -------------------------------------------------------------------------
    // M-UNIT bank tracking — output is associated with the original target_idx.
    // We pipeline mu_target_p through a few extra stages to align with the
    // PE_Core's 2-cycle (dispatch + output reg) latency. The M-UNIT also has
    // up to a 4-cycle latency for MUL via its multi-cycle pipeline; for that
    // case the original target index is captured at the same time as the
    // pe_active_mu_p flag, so we just delay it by the same number of stages.
    //
    // For simplicity (mul-heavy ops are rare and pipeline depth varies
    // across opcodes), we track the most recent target_idx that fired into
    // the M-UNIT and update mu_bank_reg whenever mu_out_valid asserts.
    // -------------------------------------------------------------------------
    /* verilator lint_off UNUSEDSIGNAL */
    // s3/s4 stages reserved for future MUL-pipeline alignment (currently
    // mu_out_valid lands at s2 for case-dispatch path; the multi-cycle
    // MUL path reaches s4 but writes to mu_bank_reg via s2 because
    // target_idx is held stable across the wait).
    reg [3:0] mu_target_pipe_s2, mu_target_pipe_s3, mu_target_pipe_s4;
    reg       mu_active_pipe_s2, mu_active_pipe_s3, mu_active_pipe_s4;
    /* verilator lint_on UNUSEDSIGNAL */
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mu_target_pipe_s2 <= 4'h0;
            mu_target_pipe_s3 <= 4'h0;
            mu_target_pipe_s4 <= 4'h0;
            mu_active_pipe_s2 <= 1'b0;
            mu_active_pipe_s3 <= 1'b0;
            mu_active_pipe_s4 <= 1'b0;
        end else begin
            mu_target_pipe_s2 <= mu_target_p;
            mu_target_pipe_s3 <= mu_target_pipe_s2;
            mu_target_pipe_s4 <= mu_target_pipe_s3;
            mu_active_pipe_s2 <= pe_active_mu_p;
            mu_active_pipe_s3 <= mu_active_pipe_s2;
            mu_active_pipe_s4 <= mu_active_pipe_s3;
        end
    end

    integer mb;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (mb = 0; mb < NUM_PES; mb = mb + 1)
                mu_bank_reg[mb] <= {ADDR_WIDTH{1'b0}};
        end else if (mu_out_valid) begin
            // Track the M-UNIT result by whichever pipelined target_idx is
            // currently aligned with mu_out_valid. For simplicity we use s2
            // (matches the case-dispatch path); MUL pipeline (s4) results are
            // also valid against the s2 target since target_idx changes only
            // when a new mul-heavy op fires, which would re-prime the chain.
            /* verilator lint_off WIDTHTRUNC */
            mu_bank_reg[mu_target_pipe_s2] <= mu_out_payload;
            /* verilator lint_on WIDTHTRUNC */
        end
    end

    // DIV-UNIT bank tracking (mirror of M-UNIT). DIV/MOD pipeline = 2 cycles,
    // so use du_target_p which already aligns at s6 with dec_valid.
    reg [3:0] du_target_pipe_s2;
    always @(posedge clk or posedge rst) begin
        if (rst) du_target_pipe_s2 <= 4'h0;
        else     du_target_pipe_s2 <= du_target_p;
    end
    integer db;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (db = 0; db < NUM_PES; db = db + 1)
                du_bank_reg[db] <= {ADDR_WIDTH{1'b0}};
        end else if (du_out_valid) begin
            /* verilator lint_off WIDTHTRUNC */
            du_bank_reg[du_target_pipe_s2] <= du_out_payload;
            /* verilator lint_on WIDTHTRUNC */
        end
    end

    // last-writer tracking: last_was_mu[k] / last_was_du[k] indicate which
    // unit produced the most recent value at bank slot k. For OPREF.src_kind=1
    // lookups the bank-selection logic picks among (L-PE | M-UNIT | DIV-UNIT).
    integer ksrc;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            last_was_mu <= {NUM_PES{1'b0}};
            last_was_du <= {NUM_PES{1'b0}};
        end else begin
            for (ksrc = 0; ksrc < NUM_PES; ksrc = ksrc + 1) begin
                if (mu_out_valid && {4'h0, mu_target_pipe_s2} == ksrc[7:0]) begin
                    last_was_mu[ksrc] <= 1'b1;
                    last_was_du[ksrc] <= 1'b0;
                end else if (du_out_valid && {4'h0, du_target_pipe_s2} == ksrc[7:0]) begin
                    last_was_du[ksrc] <= 1'b1;
                    last_was_mu[ksrc] <= 1'b0;
                end else if (pe_out_valid[ksrc]) begin
                    last_was_mu[ksrc] <= 1'b0;
                    last_was_du[ksrc] <= 1'b0;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Output OR-merge across L-PE grid + M-UNIT
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
        m_tag       = {TAG_WIDTH{1'b0}};
        m_payload   = {ADDR_WIDTH{1'b0}};
        m_opcode    = 8'h00;
        m_frag_hdr  = 8'h00;
        m_valid     = 1'b0;
        m_mem_req   = 1'b0;
        m_mem_addr  = {ADDR_WIDTH{1'b0}};
        m_err       = 1'b0;
        m_lwr       = 1'b0;
        if (mu_out_valid) begin
            m_tag      = mu_out_tag;
            m_payload  = mu_out_payload;
            m_opcode   = mu_out_opcode;
            m_frag_hdr = mu_out_frag_hdr;
            m_valid    = 1'b1;
        end
        if (mu_mem_req) begin
            m_mem_req  = 1'b1;
            m_mem_addr = mu_mem_addr;
        end
        m_err = m_err | mu_error;
        m_lwr = m_lwr | mu_lower;
        if (du_out_valid && !m_valid) begin
            m_tag      = du_out_tag;
            m_payload  = du_out_payload;
            m_opcode   = du_out_opcode;
            m_frag_hdr = du_out_frag_hdr;
            m_valid    = 1'b1;
        end
        if (du_mem_req && !m_mem_req) begin
            m_mem_req  = 1'b1;
            m_mem_addr = du_mem_addr;
        end
        m_err = m_err | du_error;
        m_lwr = m_lwr | du_lower;
        for (i = 0; i < NUM_PES; i = i + 1) begin
            if (pe_out_valid[i] && !m_valid) begin
                m_tag      = pe_out_tag[i];
                m_payload  = pe_out_payload[i];
                m_opcode   = pe_out_opcode[i];
                m_frag_hdr = pe_out_frag_hdr[i];
                m_valid    = 1'b1;
            end
            if (pe_mem_req[i] && !m_mem_req) begin
                m_mem_req  = 1'b1;
                m_mem_addr = pe_mem_addr[i];
            end
            m_err = m_err | pe_error[i];
            m_lwr = m_lwr | pe_lower[i];
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
