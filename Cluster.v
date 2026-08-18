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
    parameter PE_COLS     = 2,
    // v1.6.5c §22.16 — fragment-buffer slot count. FRAG_SLOTS=1 (default)
    // reproduces v1.5.1/v1.6.5b single-slot behavior bit-for-bit (see
    // proof in the buffer section below). FRAG_SLOTS>1 enables persistent
    // multi-slot caching for CACHE_LOAD_WIDE (0x68).
    parameter FRAG_SLOTS  = 1
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
    output                      any_lower_required,
    // v1.5.3 §20 (adversarial review bug 3+4): dedicated output-collision
    // pulse — asserts on any cycle where >1 unit (MU / DU / L-PE) drove
    // output_valid or mem_req simultaneously. Losers are silently dropped
    // by atomic per-source arbitration; software should observe this flag
    // to detect and recover. Also folded into any_error_flag so legacy
    // consumers surface it as a generic error.
    output                      any_output_collision,
    // v1.6.6 §22.14 — Cluster-level back-pressure aggregate. AND-reduce
    // of all PE_Core pe_ready signals. High only when EVERY PE can accept
    // a new dispatch. Upstream fabric can observe (MVP: observe-only).
    output                      cluster_ready,
    // v1.9 §26.5 — sticky synthesizable fault: a launch into the MU or DU
    // tag-indexed bank table found no free row (both MU rows busy, or the
    // DU row busy). Reset-clearable only — see the bank-table section
    // below for the interlock this closes (a real hardware fault, not a
    // sim-only assertion).
    output                      bank_tag_collision_error
);

    localparam NUM_PES = PE_ROWS * PE_COLS;

    // Opcode extracted combinationally up-front — needed by both the
    // fragment/cache buffer below (CACHE_LOAD_WIDE detection) and the
    // op-class classifiers further down.
    wire [7:0] ext_opcode = ext_instruction[31:24];

    // -------------------------------------------------------------------------
    // v1.5.1/v1.6.5c §18/§22.16 — Fragment reassembly + persistent cache
    // buffer (N-way).
    //
    // Collects wave-token fragments and combinationally assembles them into
    // a wide payload when the LAST fragment arrives. Legacy single-fragment
    // (ext_frag_hdr = 0x00) bypasses the buffer entirely for zero-latency
    // legacy path — all v1.0..1.4 primitives take this fast path.
    //
    // FRAG_SLOTS-way full-80-bit-tag CAM with monotonic-timestamp LRU
    // eviction. At FRAG_SLOTS=1 this reduces to EXACTLY the v1.5.1/v1.6.5b
    // single-slot semantics (proof: frag_ready never latches 1 when
    // FRAG_SLOTS=1 since the persistence branch below is gated off, so
    // hit_ready/any_ready_hit are permanently false, collapsing the
    // 4-way alloc priority to a pure continue-vs-fresh-allocate binary
    // identical to the original `frag_active && frag_same_tag` check, and
    // the completion branch takes the unconditional-clear path — see
    // wt64v1_spec.md §22.16 for the full derivation). FRAG_SLOTS>1 adds:
    //   - persistent (non-destructive) completed-slot storage
    //     (frag_ready), enabling CACHE_LOAD_WIDE (0x68) to re-read a
    //     completed wave without recompute/re-fanout;
    //   - LRU eviction via a shared monotonic touch counter (frag_age_ctr)
    //     snapshotted per-slot on every touch — correct-by-construction on
    //     cold-fill (every touch gets a strictly larger, hence unique,
    //     timestamp; no rank-permutation tie is possible), unlike a
    //     per-slot-rank scheme;
    //   - safe reallocation (not silent merge) when a NEW fragment's tag
    //     collides with an already-cached (ready) slot.
    //
    // See wt64v1_spec.md §18 (legacy) and §22.16 (v1.6.5c) and
    // noc_fragmentation_design.md §5.
    // -------------------------------------------------------------------------
    localparam FRAG_MAX = 16;
    localparam AGE_W    = 32;
    localparam SLOT_W   = (FRAG_SLOTS <= 1) ? 1 : $clog2(FRAG_SLOTS);

    /* verilator lint_off UNUSEDSIGNAL */
    reg [ADDR_WIDTH-1:0] frag_data     [0:FRAG_SLOTS-1][0:FRAG_MAX-1];
    reg [FRAG_MAX-1:0]   frag_mask     [0:FRAG_SLOTS-1];
    reg [3:0]            frag_total_m1 [0:FRAG_SLOTS-1];
    reg [TAG_WIDTH-1:0]  frag_tag_reg  [0:FRAG_SLOTS-1];
    reg [FRAG_SLOTS-1:0] frag_active;
    // v1.6.5c — persistent-complete flag. Stays 0 forever at FRAG_SLOTS=1
    // (persistence branch below is gated off), so hit_ready is always
    // false and the tag-reuse-collision / cache-hit paths never engage —
    // exactly reproducing pre-v1.6.5c behavior.
    reg [FRAG_SLOTS-1:0] frag_ready;
    reg [AGE_W-1:0]      frag_age      [0:FRAG_SLOTS-1];
    reg [AGE_W-1:0]      frag_age_ctr;
    /* verilator lint_on UNUSEDSIGNAL */

    wire [3:0] frag_in_idx    = ext_frag_hdr[7:4];
    wire [3:0] frag_in_tot_m1 = ext_frag_hdr[3:0];
    wire       frag_in_multi  = ext_valid && (ext_frag_hdr != 8'h00);
    // v1.6.5c §22.16 — CACHE_LOAD_WIDE (0x68) request: a normal (non-
    // fragment) dispatch whose own ext_tag IS the cache lookup key (see
    // §22.16's tag-stability derivation for why this equals the producer's
    // stored tag once the assembler's PRECISION-EH dim_sizes guard is in
    // place).
    wire cache_load_req = ext_valid && (ext_frag_hdr == 8'h00)
                                     && (ext_opcode == 8'h68);
    // v1.6.5d §22.17 — FRAG_INVAL (0x6A) request: mirrors cache_load_req's
    // shape exactly. Mutually exclusive with cache_load_req since
    // ext_opcode is a single 8-bit value per cycle (0x68 vs 0x6A cannot
    // both be true), so inval_hit/cache_hit are automatically disjoint
    // with zero extra interlock logic.
    wire inval_req = ext_valid && (ext_frag_hdr == 8'h00)
                                && (ext_opcode == 8'h6A);

    // Per-slot hit classification (combinational). At most one of
    // hit_continue[s]/hit_ready[s] can be true for a given s (mutually
    // exclusive on frag_ready[s]).
    reg hit_continue [0:FRAG_SLOTS-1];
    reg hit_ready    [0:FRAG_SLOTS-1];
    integer ghi;
    always @(*) begin
        for (ghi = 0; ghi < FRAG_SLOTS; ghi = ghi + 1) begin
            hit_continue[ghi] = frag_active[ghi] && !frag_ready[ghi]
                              && (ext_tag == frag_tag_reg[ghi]);
            hit_ready[ghi]    = frag_active[ghi] &&  frag_ready[ghi]
                              && (ext_tag == frag_tag_reg[ghi]);
        end
    end

    // Priority-encoded slot selection (combinational): continue > cached-
    // tag-collision/cache-hit > free slot > LRU-eviction victim.
    reg                 any_continue;
    reg [SLOT_W-1:0]    continue_idx;
    reg                 any_ready_hit;
    reg [SLOT_W-1:0]    ready_idx;
    reg                 any_free;
    reg [SLOT_W-1:0]    free_idx;
    reg [SLOT_W-1:0]    evict_idx;
    reg [AGE_W-1:0]     evict_age;
    integer si;
    always @(*) begin
        any_continue  = 1'b0; continue_idx = {SLOT_W{1'b0}};
        any_ready_hit = 1'b0; ready_idx    = {SLOT_W{1'b0}};
        any_free      = 1'b0; free_idx     = {SLOT_W{1'b0}};
        evict_idx     = {SLOT_W{1'b0}};
        evict_age     = {AGE_W{1'b1}};
        for (si = 0; si < FRAG_SLOTS; si = si + 1) begin
            if (hit_continue[si] && !any_continue) begin
                any_continue = 1'b1; continue_idx = si[SLOT_W-1:0];
            end
            if (hit_ready[si] && !any_ready_hit) begin
                any_ready_hit = 1'b1; ready_idx = si[SLOT_W-1:0];
            end
            if (!frag_active[si] && !any_free) begin
                any_free = 1'b1; free_idx = si[SLOT_W-1:0];
            end
            if (frag_active[si] && (frag_age[si] < evict_age)) begin
                evict_age = frag_age[si]; evict_idx = si[SLOT_W-1:0];
            end
        end
    end

    // Target slot for an incoming fragment beat: continue the in-progress
    // wave, safely reallocate over a collided cached slot, take a free
    // slot, or evict the LRU victim — in that priority order.
    wire alloc_is_continue = any_continue;
    wire [SLOT_W-1:0] alloc_idx =
        any_continue  ? continue_idx :
        any_ready_hit ? ready_idx    :
        any_free      ? free_idx     :
                        evict_idx;

    // Mask bit for the arriving fragment
    wire [FRAG_MAX-1:0] frag_mask_add = frag_in_multi
                                       ? ({15'h0, 1'b1} << frag_in_idx)
                                       : {FRAG_MAX{1'b0}};

    // Mask AFTER this cycle's write:
    //   - continue existing:                  OR into accumulated mask
    //   - new slot start (free OR evicted OR collided-reallocated):
    //     just the arriving bit
    wire [FRAG_MAX-1:0] frag_mask_after =
        alloc_is_continue ? (frag_mask[alloc_idx] | frag_mask_add)
                          : frag_mask_add;

    // Total field to compare against — from either the arriving fragment
    // (new slot) or the stored slot (continuing).
    wire [3:0] frag_tot_ref =
        alloc_is_continue ? frag_total_m1[alloc_idx] : frag_in_tot_m1;

    // Full mask: bits [0 .. tot_ref] set.
    // v1.8.0e §25.3 — LATENT-BUG FIX, recorded as a repair (mandatory
    // repair 2): the shift amount is widened to 5 bits. The old form
    // `frag_tot_ref + 4'h1` is a SELF-DETERMINED 4-bit addition inside
    // the shift-amount context, so tot_m1 = 15 wrapped 15+1 to 0 —
    // mask 0x0000, frag_mask_after never equals frag_mask_full, and a
    // 16-fragment wave was permanently unreassemblable (silent CAM-slot
    // rot; verilator-confirmed). With the 5-bit amount, a shift by 16
    // of the 16-bit one-hot yields 0 and 0 - 1 = 0xFFFF — the correct
    // full mask. Precondition for the 0e2 16-fragment VFMA emit; pinned
    // by test_cluster_frag_reass_16 (tot_m1 = 7 / 14 / 15).
    wire [4:0] frag_tot_p1 = {1'b0, frag_tot_ref} + 5'd1;
    wire [FRAG_MAX-1:0] frag_mask_full =
        ({15'h0, 1'b1} << frag_tot_p1) - {{(FRAG_MAX-1){1'b0}}, 1'b1};

    // Completion pulse (combinational): fires the same cycle as the last
    // fragment arrival. Consumers must sample on this cycle.
    /* verilator lint_off UNUSEDSIGNAL */
    wire frag_reass_valid = frag_in_multi && (frag_mask_after == frag_mask_full);
    /* verilator lint_on UNUSEDSIGNAL */

    // Wide payload (combinational): overlays this-cycle's fragment onto
    // the selected slot's stored data. On the completion cycle, this holds
    // the fully assembled wave payload — up to 16 × 64 = 1024 bits.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [FRAG_MAX*ADDR_WIDTH-1:0] frag_reass_wide;
    /* verilator lint_on UNUSEDSIGNAL */
    genvar gfw;
    generate
        for (gfw = 0; gfw < FRAG_MAX; gfw = gfw + 1) begin : g_frag_wide
            assign frag_reass_wide[gfw*ADDR_WIDTH +: ADDR_WIDTH] =
                (frag_in_multi && (frag_in_idx == gfw[3:0])) ? ext_payload
                                                             : frag_data[alloc_idx][gfw];
        end
    endgenerate

    // v1.6.5c — CACHE_LOAD_WIDE hit data (combinational): the matched
    // ready slot's stored payload, exposed independent of frag_reass_wide
    // since a cache-load request is never a fragment beat.
    wire cache_hit = cache_load_req && any_ready_hit;
    // v1.6.5d §22.17 — FRAG_INVAL hit: reuses the SAME hit_ready/
    // any_ready_hit CAM match as cache_hit, zero new comparator logic.
    // Only matches READY (persisted/complete) slots — a slot mid-
    // assembly (frag_active && !frag_ready) reports a miss, not a
    // cancel. This is deliberate, minimal scope: FRAG_INVAL reclaims a
    // completed cached slot, it is not an in-flight-fragment-abort
    // primitive.
    wire inval_hit = inval_req && any_ready_hit;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [FRAG_MAX*ADDR_WIDTH-1:0] cache_hit_wide;
    /* verilator lint_on UNUSEDSIGNAL */
    genvar gch;
    generate
        for (gch = 0; gch < FRAG_MAX; gch = gch + 1) begin : g_cache_wide
            assign cache_hit_wide[gch*ADDR_WIDTH +: ADDR_WIDTH] = frag_data[ready_idx][gch];
        end
    endgenerate

    integer ffi, ffs;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (ffs = 0; ffs < FRAG_SLOTS; ffs = ffs + 1) begin
                for (ffi = 0; ffi < FRAG_MAX; ffi = ffi + 1)
                    frag_data[ffs][ffi] <= {ADDR_WIDTH{1'b0}};
                frag_mask[ffs]     <= {FRAG_MAX{1'b0}};
                frag_total_m1[ffs] <= 4'h0;
                frag_tag_reg[ffs]  <= {TAG_WIDTH{1'b0}};
                frag_age[ffs]      <= {AGE_W{1'b0}};
            end
            frag_active  <= {FRAG_SLOTS{1'b0}};
            frag_ready   <= {FRAG_SLOTS{1'b0}};
            frag_age_ctr <= {AGE_W{1'b0}};
        end else if (frag_in_multi) begin
            frag_data[alloc_idx][frag_in_idx] <= ext_payload;
            if (!alloc_is_continue) begin
                // Fresh allocation at alloc_idx: free slot, LRU-evicted
                // slot, or safe reallocation over a tag-collided cached
                // (ready) slot — never a silent merge into stale data.
                frag_tag_reg[alloc_idx]  <= ext_tag;
                frag_total_m1[alloc_idx] <= frag_in_tot_m1;
                frag_mask[alloc_idx]     <= frag_mask_add;
                frag_active[alloc_idx]   <= 1'b1;
                frag_ready[alloc_idx]    <= 1'b0;
            end else begin
                frag_mask[alloc_idx] <= frag_mask[alloc_idx] | frag_mask_add;
            end
            // Touch: every beat (allocate or continue) refreshes this
            // slot's monotonic timestamp.
            frag_age_ctr        <= frag_age_ctr + 1'b1;
            frag_age[alloc_idx] <= frag_age_ctr + 1'b1;
            // Completion: gate persistence by FRAG_SLOTS. FRAG_SLOTS=1
            // reproduces the original unconditional clear exactly.
            if (frag_reass_valid) begin
                if (FRAG_SLOTS > 1) begin
                    frag_ready[alloc_idx] <= 1'b1;
                end else begin
                    frag_active[alloc_idx] <= 1'b0;
                    frag_mask[alloc_idx]   <= {FRAG_MAX{1'b0}};
                end
            end
        end else if (cache_hit) begin
            // Non-destructive read: still a "touch" for LRU purposes so a
            // hot cached value doesn't get evicted while in active use.
            frag_age_ctr            <= frag_age_ctr + 1'b1;
            frag_age[ready_idx]      <= frag_age_ctr + 1'b1;
        end else if (inval_hit) begin
            // v1.6.5d §22.17 — explicit invalidate: clear active+ready so
            // the slot immediately qualifies for any_free (checked ahead
            // of evict_idx in the alloc_idx priority mux above) rather
            // than lingering as an LRU-eviction candidate. frag_age is
            // deliberately left untouched (irrelevant once inactive).
            frag_active[ready_idx] <= 1'b0;
            frag_ready[ready_idx]  <= 1'b0;
        end
    end

    // v1.6.5c/v1.6.5d — CACHE_LOAD_WIDE / FRAG_INVAL hit/miss mux feeding
    // EHDecode's wide-input port. A miss (cache_load_req && !cache_hit,
    // or inval_req && !inval_hit) yields wide_valid=0, which PE_Core's
    // 0x68/0x6A case arms turn into the existing error_flag guard — a
    // loud, safe miss rather than a silent wrong-data hit or a silent
    // no-op invalidate. FRAG_INVAL's payload is never read by PE_Core's
    // 0x6A arm (it only checks wide_valid), so the zero fill is inert.
    wire                            final_wide_valid =
        cache_load_req ? cache_hit  :
        inval_req      ? inval_hit :
                          frag_reass_valid;
    wire [FRAG_MAX*ADDR_WIDTH-1:0]  final_wide =
        cache_load_req ? cache_hit_wide                    :
        inval_req      ? {(FRAG_MAX*ADDR_WIDTH){1'b0}}      :
                          frag_reass_wide;

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
    // (ext_opcode itself is declared up in the fragment/cache buffer
    // section above, since cache_load_req also needs it.)
    // -------------------------------------------------------------------------
    // v1.8.0b §23.9 — TWIN CLASSIFIER invariant: this list and PE_Core.v's
    // dec_is_mul_op must stay in lockstep. 0x71 VDOT_ACC / 0x72 ACC_REDUCE
    // route to the MATMUL_UNIT (MAC tree lives only there); 0x7C
    // STORE_QUANT deliberately NOT listed — no multipliers, runs on L-PEs.
    // v1.8.0c §23.10 — 0x74 FSCALAR / 0x75 FRSQRT32 / 0x76 FEXP2_32 route
    // to the MATMUL_UNIT too (the fp32 step sequencer lives only there);
    // a missed twin side is a silent permanent lower_required dead-end,
    // pinned by test_fp_mu_routing_end_to_end in the same commit.
    // RETIRED (v1.9 §26.5/§26.8 item 10, closed in the residual-risk-11
    // fix commit): the former SDK software rule "no intervening mul-class
    // dispatch on the hosting MU between a chained VDOT/OPREF kind-1 read
    // (or a dependent fp/DEQUANT/VFMA/... read) and its producer" — the
    // NoC bank used to be positional (mu_target_pipe_s2/s3/s4), so an
    // intervening dispatch during a producer's multi-cycle flight would
    // retarget the shared shift-register slot before the read landed.
    // §26.5's tag-indexed launch-time latch table (MU depth-2, DU
    // depth-1, keyed by launch tag + `row_is_mul`, not shift depth)
    // replaced the positional mechanism outright, and the residual-risk-11
    // fix (this commit, Cluster.v `mu_launch_mul`/`mu_launch_other_now`
    // above) closed the one gap that table shipped with: a busy-rejected
    // non-MUL dispatch could still phantom-allocate a row, which could —
    // in principle — exhaust the depth-2 table exactly during a chained
    // read's window. With that gap closed and directed-test-confirmed
    // (test_bank_tag_latch_no_intervening_hazard,
    // test_bank_tag_collision_interlock, test_mu_busy_reject_no_phantom_row,
    // test_output_regs_free_live_at_stage2, test_uniform_case_dispatch_
    // plus1_sweep — spec §26.7 items 9-12), back-to-back dispatch with NO
    // gap is provably hazard-free by tag match, not merely
    // hazard-avoided by a software spacing discipline — so the rule text
    // is deleted rather than kept as dead documentation (§26.5's own
    // retirement plan: delete in the same commit the closing tests go
    // green, not preemptively alongside unverified RTL).
    // v1.8.0d §23.10.10 — 0x73 ACC_ELEMWISE / 0x77 CVT join OPCODE-ONLY
    // (MU-hosted OPS_ACCEW/OPS_CVT step programs; same commit as the
    // PE_Core dec_is_mul_op edit + the lockstep/reachability tests). NO
    // dtype conditionality anywhere in this classifier: 0x7C STORE_QUANT
    // stays L-PE-routed for ALL dtypes including the new fp-dest forms
    // (§23.10.10(d) twin-classifier-untouched clause — the narrow packer
    // is combinational on the L-PEs, no multipliers).
    // v1.8.0e §25.3/§25.6 item 6 — 0x6B GAMMA_MUL_W / 0x78 DEQUANT /
    // 0x79 FMINMAX join OPCODE-ONLY in lockstep with PE_Core's
    // dec_is_mul_op (their arms are all MU-hosted: the gamma shift-add
    // arm and the FMINMAX comparator live in the parameter-gated region,
    // DEQUANT rides the MU's FP_StepSeq OPS_DEQ lane loop). v1.8.0e 0e2
    // — 0x70 VFMA_ACC joins WITH its lane-loop launch arm (spec
    // §25.2.4; the shared MAC step is MU-gated, so L-PEs synthesize
    // nothing — the static lockstep test flips 0x70 from staged-out to
    // IN in this same commit).
    // (§25.6 item 4's SDK-rule extension to 0x6B/0x70/0x78/0x79 is RETIRED
    // along with the base rule above — see the RETIRED note preceding
    // this comment block.)
    wire is_mul_op = (ext_opcode == 8'h12)
                  || (ext_opcode == 8'h30)
                  || (ext_opcode == 8'h32)
                  || (ext_opcode == 8'h43)
                  || (ext_opcode == 8'h6B)
                  || (ext_opcode == 8'h70)
                  || (ext_opcode == 8'h71)
                  || (ext_opcode == 8'h72)
                  || (ext_opcode == 8'h73)
                  || (ext_opcode == 8'h74)
                  || (ext_opcode == 8'h75)
                  || (ext_opcode == 8'h76)
                  || (ext_opcode == 8'h77)
                  || (ext_opcode == 8'h78)
                  || (ext_opcode == 8'h79);
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

    // -------------------------------------------------------------------------
    // v1.9.1 §31.14 — NoC bank 저장소 계약 (normative). **읽기 전에 이걸 읽어라.**
    //
    // 세 소스의 저장소 형태가 다르다:
    //   * MU / DU 슬롯 — `mu_bank_reg` / `du_bank_reg` 라는 **전용 뱅크
    //     레지스터**를 두고 `mu_out_valid` / `du_out_valid` 로 write-enable 한다.
    //   * L-PE 슬롯 — 전용 레지스터를 두지 **않는다.** `PE_Core` 의 출력
    //     레지스터(`output_payload`)를 **뱅크 저장소로 그대로 재사용**하고
    //     여기서 조합적으로 읽는다. PE 당 64-bit 레지스터 1개를 아끼는
    //     의도적 면적 최적화다 (Pod 문맥에서는 × 클러스터 수).
    //
    // 따라서 아래 `pe_out_payload[kbank]` 읽기에 `pe_out_valid` 게이트가 없는
    // 것은 누락이 아니라 **계약**이다. 그 계약의 이름과 내용:
    //
    //     불변식 H1 — `PE_Core.output_payload` 는 `output_valid` 가 뜨는
    //     사이클에만 바뀐다. 즉 토큰을 내지 않는 명령은 뱅크를 오염시킬 수
    //     없고, 이 조합 읽기는 항상 "그 슬롯이 마지막으로 **실제 발행한**
    //     토큰의 payload" 를 돌려준다 — `:552-554` 주석의 계약 그대로다.
    //
    // **이 계약은 v1.9 에서 실제로 깨져 있었다.** stage-2 성공 arm 이
    // `cr_valid_out` 과 무관하게 `output_payload <= cr_payload` 를 수행했으므로,
    // 토큰을 내지 않는 명령 1건(예: LD 0x04)이 앞선 wave 가 뱅크에 남긴 값을
    // 되돌려 놓았다. §31.13.3 은 그 차이를 "자격자가 0 이라 masked(SOFT)" 로
    // 분류했는데, **이 소비자에게는 masked 가 아니다** — 적대 검증이 Cluster
    // 경계에서 관측 가능한 값 변화로 실증했다 (§31.14.2). D11 수리(PE_Core
    // stage-2 자격 가드)가 H1 을 복원했고, 그 복원이 본 뱅크 계약의 전제다.
    //
    // 집행 (계약을 주석으로만 두지 않는다 — §31.4 가 지적한 바로 그 실패를
    // 여기서 반복하지 않기 위해):
    //   * `scripts/lint_output_payload_hold.py` — H1/H2 정적 집행 (`make lint`).
    //     v1.9 baseline 에 걸어 보면 정확히 두 대입 site 를 잡는다.
    //   * `test_pe.py::test_pe_output_payload_hold_invariant` — 런타임 감시.
    //   * `test_cluster.py::test_cluster_noc_bank_*` — 뱅크 값 의미론 pin.
    //
    // 왜 여기에 `pe_bank_reg` 를 달지 않는가: `PE_Core.output_payload` 와
    // 완전히 중복되는 NUM_PES × 64-bit 레지스터가 생기고, 무엇보다 **미래의
    // H1 위반을 조용히 덮는다.** 침묵시키는 대신 소리내는 쪽을 고른다.
    //
    // 다중 fragment wave 의 뱅크 의미론 (정직 명기): 뱅크 슬롯은 64-bit 이고
    // wave 는 여러 fragment 일 수 있다. 현행 의미론은 **마지막 fragment 의
    // payload** 이며, ISA 가 이를 규정한 바는 없다 (§31.14.5 이월).
    // -------------------------------------------------------------------------
    reg [ADDR_WIDTH-1:0] bank_selected;
    integer kbank;
    always @(*) begin
        bank_selected = {ADDR_WIDTH{1'b0}};
        for (kbank = 0; kbank < NUM_PES; kbank = kbank + 1) begin
            if ({4'h0, eff_opref_route_c[3:0]} == kbank[7:0]) begin
                if      (last_was_mu[kbank]) bank_selected = mu_bank_reg[kbank];
                else if (last_was_du[kbank]) bank_selected = du_bank_reg[kbank];
                // 불변식 H1 하에서 이것이 "마지막으로 발행한 토큰의 payload"
                // 다. `last_was_mu/du` 의 clear 조건이 `pe_out_valid[ksrc]`
                // 인 것(아래 last-writer 추적)과 정합한다 — 즉 L-PE 슬롯의
                // write-enable 은 이미 설계 안에서 `pe_out_valid` 다.
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
        .input_payload_wide        (final_wide),
        .input_payload_wide_valid  (final_wide_valid),
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
    wire                   pe_ready_lpe   [0:NUM_PES-1];   // v1.6.6 §22.14
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
                    .dec_eff_subscript_hi      (dec_eff_subscript_hi),
                    .dec_eff_imm64_hi          (dec_eff_imm64_hi),
                    .dec_input_payload_wide    (dec_input_payload_wide),
                    .dec_input_payload_wide_valid (dec_input_payload_wide_valid),
                    .dec_eff_output_port_id    (dec_eff_output_port_id),
                    .dec_eff_precision         (dec_eff_precision),
                    .dec_wave_number           (dec_wave_number),
                    .dec_thread_id             (dec_thread_id),
                    .output_payload            (pe_out_payload[IDX]),
                    .output_tag                (pe_out_tag[IDX]),
                    .output_valid              (pe_out_valid[IDX]),
                    .opcode_out                (pe_out_opcode[IDX]),
                    .output_frag_hdr           (pe_out_frag_hdr[IDX]),
                    .pe_ready                  (pe_ready_lpe[IDX]),
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
    wire                  mu_pe_ready;       // v1.6.6 §22.14
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
        .dec_eff_subscript_hi      (dec_eff_subscript_hi),
        .dec_eff_imm64_hi          (dec_eff_imm64_hi),
        .dec_input_payload_wide    (dec_input_payload_wide),
        .dec_input_payload_wide_valid (dec_input_payload_wide_valid),
        .dec_eff_output_port_id    (dec_eff_output_port_id),
        .dec_eff_precision         (dec_eff_precision),
        .dec_wave_number           (dec_wave_number),
        .dec_thread_id             (dec_thread_id),
        .output_payload            (mu_out_payload),
        .output_tag                (mu_out_tag),
        .output_valid              (mu_out_valid),
        .opcode_out                (mu_out_opcode),
        .output_frag_hdr           (mu_out_frag_hdr),
        .pe_ready                  (mu_pe_ready),
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
    wire                  du_pe_ready;       // v1.6.6 §22.14
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
        .dec_eff_subscript_hi      (dec_eff_subscript_hi),
        .dec_eff_imm64_hi          (dec_eff_imm64_hi),
        .dec_input_payload_wide    (dec_input_payload_wide),
        .dec_input_payload_wide_valid (dec_input_payload_wide_valid),
        .dec_eff_output_port_id    (dec_eff_output_port_id),
        .dec_eff_precision         (dec_eff_precision),
        .dec_wave_number           (dec_wave_number),
        .dec_thread_id             (dec_thread_id),
        .output_payload            (du_out_payload),
        .output_tag                (du_out_tag),
        .output_valid              (du_out_valid),
        .opcode_out                (du_out_opcode),
        .output_frag_hdr           (du_out_frag_hdr),
        .pe_ready                  (du_pe_ready),
        .memory_req                (du_mem_req),
        .mem_addr                  (du_mem_addr),
        .error_flag                (du_error),
        .lower_required            (du_lower)
    );

    // -------------------------------------------------------------------------
    // v1.9 §26.5 — MU/DU bank tag-indexed launch-time latch tables, replacing
    // the positional shift-tap mechanism above (mu_target_pipe_s2/s3/s4 —
    // s3/s4 already dead code per the comment this section replaces —, and
    // du_target_pipe_s2). The positional shift-tap assumed a FIXED
    // dispatch-to-completion latency for every opcode sharing it; v1.9's
    // case_result_s2 split breaks that assumption for the case-dispatched
    // MU-hosted opcodes (compute-inline arms now land 2 cycles after
    // dispatch instead of 1), so a later dispatch could silently overwrite
    // the positional register before an earlier dispatch's completion reads
    // it back. Fix: latch {target_idx} at LAUNCH time into a small table
    // row keyed by a launch tag, and look the row up by TAG MATCH (not
    // shift depth) at completion.
    //
    // Depth: MU=2, DU=1 — see spec §26.5 for the full proof (MUL's own
    // fixed p1/p2 sub-pipeline is the only scenario needing 2 concurrent
    // MU-table rows; every other MU-hosted opcode is single-flight and
    // mutually exclusive with MUL, per output_regs_free in PE_Core.v. DIV
    // is a strict single-flight FSM, so DU needs exactly 1 row.)
    //
    // Tag-value caveat, verified against PE_Core.v (not assumed): 0x12 MUL
    // preserves dec_forwarded_tag verbatim into its eventual output_tag
    // (mul_tag_p1/p2 never rebuild it) and DIV/MOD/DIVMOD do likewise
    // (div_tag_held/div_tag_p2), so an exact launch-tag == out_tag compare
    // is exact for both. Several OTHER MU-hosted opcodes (0x71 VDOT_ACC,
    // 0x72 ACC_REDUCE, the 0x73/0x74/0x75/0x76/0x77 fp-family via
    // fp_tag_held, and a subset of 0x32 EINSUM's sub-signatures) REBUILD
    // output_tag from {dec_wave_number, dec_thread_id, ..., a per-opcode
    // fixed dim byte} instead of preserving dec_forwarded_tag verbatim.
    // Replicating each of those per-opcode rebuild formulas here would
    // duplicate PE_Core's internal tag-construction logic — a
    // maintenance/drift risk this project avoids elsewhere — and isn't
    // necessary for correctness: output_regs_free guarantees at most ONE
    // non-MUL MU-table row is ever busy at a time, so that row's identity
    // needs no tag disambiguation at all once no MUL row's tag matches —
    // it is unconditionally the completing row. Each row therefore also
    // carries a `row_is_mul` bit (captured at launch from the literal
    // dec_opcode == 8'h12 check, which Cluster already has visibility
    // into) and completion resolves as: prefer an exact tag match among
    // busy MUL rows; otherwise take the (at most one) busy non-MUL row.
    // This is still entirely tag-indexed (reuses the existing
    // dec_forwarded_tag / mu_out_tag wire — Cluster.v:794 — no new tag
    // namespace) and is a strict superset of a literal always-tag-match
    // design's correctness.
    //
    // RESOLVED (was: residual risk 11, §26.8 item 11) — timing-class fix.
    // For the MU-hosted opcodes routed through case_result_s2 (everything
    // in is_mul_op except literal 0x12 MUL), PE_Core's stage-2 arbitration
    // decides ACCEPT-vs-busy-reject one cycle AFTER the externally-visible
    // dispatch (cycle T): the busy-check (`cr_needs_regs_free &&
    // !output_regs_free`, PE_Core.v ~3395) reads output_regs_free LIVE at
    // T+1, not T. A launch-time row allocation keyed off the T-time
    // dispatch alone therefore allocates a row for every attempt
    // regardless of whether PE_Core will actually accept it at T+1 — a
    // busy-rejected dispatch (PASSES dec_decode_error/dec_tag_match at T,
    // but loses the T+1 busy-check) would consume a table row that no
    // completion ever frees: a permanent phantom-occupied row.
    //
    // Fix (TIMING alignment, not a new cross-module signal — Cluster
    // already has `mu_pe_ready`, wired straight from PE_Core's own
    // `pe_ready = output_regs_free` port, Cluster.v ~849): split the
    // launch signal by opcode class.
    //   - MUL (0x12): launches from PE_Core's own always-block
    //     (mul_valid_p1, PE_Core.v ~1888), structurally parallel to
    //     case_result_s2 and UNCHANGED by v1.9 (spec §26.3 finding 4) —
    //     its accept/reject decision is still made live at T, the SAME
    //     cycle `mu_launch_mul` fires below. T-timed, unconditional
    //     allocation (today's behavior, untouched) still matches exactly.
    //   - every other is_mul_op opcode: `mu_launch_other_now` fires at T
    //     (same detection as before), but the table-row COMMIT is
    //     deferred one cycle into `mu_pending_other` and only lands at
    //     T+1 if `mu_pe_ready` reads true THEN — the identical cycle and
    //     the identical signal (mu_pe_ready IS output_regs_free) PE_Core's
    //     own stage-2 arbitration checks. A busy-rejected dispatch
    //     (mu_pe_ready false at T+1) allocates nothing: no phantom row.
    //
    // du_launch needs NO such fix, confirmed by reading PE_Core.v's DIV
    // FSM (not assumed): the DIV_IDLE launch check (PE_Core.v ~1909) is
    // entirely T-time-local (dec_opcode literal + frag_idx==FRAG_IDLE) —
    // DIV bypasses case_result_s2 exactly like MUL (spec §26.3 finding 4,
    // "MUL, DIV ... unchanged, 0 cycles"), so its accept/reject decision
    // was never re-homed to T+1 and du_launch's existing T-timed
    // unconditional allocation already matches it.
    //
    // MUL-vs-non-MUL same-cycle overlap: `mu_launch_mul` (a brand-new T-
    // time MUL dispatch) and a pending non-MUL commit resolving THIS same
    // T (dispatched at T-1) are ordinary back-to-back dispatch, not a
    // hazard, and CAN legitimately coincide — the row-claim wires below
    // resolve this combinationally (MUL preferred for row0) so neither
    // path's non-blocking write silently clobbers the other's.
    // -------------------------------------------------------------------------
    reg                  mu_row0_busy,   mu_row1_busy;
    reg [TAG_WIDTH-1:0]  mu_row0_tag,    mu_row1_tag;
    reg [3:0]            mu_row0_target, mu_row1_target;
    reg                  mu_row0_is_mul, mu_row1_is_mul;

    reg                  du_row_busy;
    // du_row_tag is captured (dec_forwarded_tag at launch) for structural
    // symmetry with the MU table and future debug visibility, but is never
    // READ: DIV is single-flight (depth 1, at most one busy row), so
    // completion attribution needs no tag comparison — see the header note.
    /* verilator lint_off UNUSEDSIGNAL */
    reg [TAG_WIDTH-1:0]  du_row_tag;
    /* verilator lint_on UNUSEDSIGNAL */
    reg [3:0]            du_row_target;

    // v1.9 §26.5 — synthesizable sticky fault: a launch finds no free row.
    // NOT sim-only — a real status bit exposed on the bank_tag_collision_error
    // output port. Sticky: reset-clearable only, so a collision cannot be
    // silently absorbed by the next idle cycle.
    reg bank_tag_collision_error_r;

    // v1.9 residual-risk-11 fix — deferred-commit staging for the non-MUL
    // launch class (see the header note above). Captured every cycle from
    // `mu_launch_other_now`; consumed exactly one cycle later, gated on
    // live `mu_pe_ready`.
    reg                  mu_pending_other;
    reg [TAG_WIDTH-1:0]  mu_pending_tag;
    reg [3:0]            mu_pending_target;

    // Launch detection: dispatch reaching the unit's dec_valid cycle, with
    // the two rejection causes Cluster can observe from outside PE_Core
    // (decode error / tag mismatch) filtered out. Split by opcode timing
    // class — see the header note above.
    wire mu_launch_mul       = pe_active_mu_p && dec_valid && !dec_decode_error
                             && dec_tag_match && (dec_opcode == 8'h12);
    wire mu_launch_other_now = pe_active_mu_p && dec_valid && !dec_decode_error
                             && dec_tag_match && (dec_opcode != 8'h12);
    wire du_launch = pe_active_du_p && dec_valid && !dec_decode_error && dec_tag_match;

    // Completion match — see the header note for the tag-hit / non-MUL
    // fallback rule. Cross-referencing only tag_hit wires (not the other
    // row's match wire) avoids a combinational self-reference.
    wire mu_r0_tag_hit     = mu_row0_busy && mu_row0_is_mul && (mu_row0_tag == mu_out_tag);
    wire mu_r1_tag_hit     = mu_row1_busy && mu_row1_is_mul && (mu_row1_tag == mu_out_tag);
    wire mu_r0_nonmul_busy = mu_row0_busy && !mu_row0_is_mul;
    wire mu_r1_nonmul_busy = mu_row1_busy && !mu_row1_is_mul;
    wire mu_match0 = mu_out_valid && (mu_r0_tag_hit
                        || (!mu_r0_tag_hit && !mu_r1_tag_hit && mu_r0_nonmul_busy));
    wire mu_match1 = mu_out_valid && (mu_r1_tag_hit
                        || (!mu_r0_tag_hit && !mu_r1_tag_hit && mu_r1_nonmul_busy));
    wire [3:0] mu_resolved_target = mu_match0 ? mu_row0_target :
                                     mu_match1 ? mu_row1_target : 4'h0;

    wire du_match = du_out_valid && du_row_busy;
    wire [3:0] du_resolved_target = du_row_target;

    // Row-free-for-allocation, accounting for a completion vacating the row
    // THIS SAME cycle (so sustained back-to-back MUL dispatch never falsely
    // collides — the launch write below is textually after the completion
    // clear, so a same-cycle free-then-reallocate lands the new occupant).
    wire mu_row0_free = !mu_row0_busy || mu_match0;
    wire mu_row1_free = !mu_row1_busy || mu_match1;
    wire du_row_free  = !du_row_busy  || du_match;

    // v1.9 residual-risk-11 fix — row-claim resolution, combinational.
    // `mu_launch_mul` (T-timed, unconditional) and the deferred non-MUL
    // commit `mu_pending_other && mu_pe_ready` (checked live at T+1) are
    // two INDEPENDENT triggers that can legitimately coincide on the same
    // cycle (see the header note). Resolving row assignment here, instead
    // of as two separate sequential `if` blocks both reading the same
    // (this-cycle-constant) mu_row*_free wires, avoids a same-cycle
    // write race where both triggers would see the row as free and both
    // try to claim it (last-nonblocking-assignment-wins silently drops
    // one). MUL is given priority for row0 by construction below; this
    // tie-break is arbitrary and not load-bearing — output_regs_free
    // mutual exclusion means the cases spec §26.5 reasons about never
    // actually contend for the same row.
    wire mu_pending_commit_now = mu_pending_other && mu_pe_ready;

    wire mu_mul_takes_row0    = mu_launch_mul && mu_row0_free;
    wire mu_mul_takes_row1    = mu_launch_mul && !mu_row0_free && mu_row1_free;
    wire mu_mul_collision     = mu_launch_mul && !mu_row0_free && !mu_row1_free;

    wire mu_nonmul_row0_avail = mu_row0_free && !mu_mul_takes_row0;
    wire mu_nonmul_row1_avail = mu_row1_free && !mu_mul_takes_row1;
    wire mu_nonmul_takes_row0 = mu_pending_commit_now && mu_nonmul_row0_avail;
    wire mu_nonmul_takes_row1 = mu_pending_commit_now && !mu_nonmul_row0_avail
                              && mu_nonmul_row1_avail;
    wire mu_nonmul_collision  = mu_pending_commit_now && !mu_nonmul_row0_avail
                              && !mu_nonmul_row1_avail;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mu_row0_busy   <= 1'b0;
            mu_row1_busy   <= 1'b0;
            mu_row0_tag    <= {TAG_WIDTH{1'b0}};
            mu_row1_tag    <= {TAG_WIDTH{1'b0}};
            mu_row0_target <= 4'h0;
            mu_row1_target <= 4'h0;
            mu_row0_is_mul <= 1'b0;
            mu_row1_is_mul <= 1'b0;
            du_row_busy    <= 1'b0;
            du_row_tag     <= {TAG_WIDTH{1'b0}};
            du_row_target  <= 4'h0;
            bank_tag_collision_error_r <= 1'b0;
            mu_pending_other  <= 1'b0;
            mu_pending_tag    <= {TAG_WIDTH{1'b0}};
            mu_pending_target <= 4'h0;
        end else begin
            // Completions clear their matched row first (program order —
            // the launch writes below win last-assignment-wins if a launch
            // targets the same row a completion frees this cycle).
            if (mu_match0) mu_row0_busy <= 1'b0;
            if (mu_match1) mu_row1_busy <= 1'b0;
            if (du_match)  du_row_busy  <= 1'b0;

            // MUL: T-timed, unconditional — exactly today's (pre-fix)
            // behavior, untouched. PE_Core's own accept/reject for MUL is
            // still made live at this same T (mul_valid_p1), so this
            // still matches exactly.
            if (mu_mul_takes_row0) begin
                mu_row0_busy   <= 1'b1;
                mu_row0_tag    <= dec_forwarded_tag;
                mu_row0_target <= mu_target_p;
                mu_row0_is_mul <= 1'b1;
            end else if (mu_mul_takes_row1) begin
                mu_row1_busy   <= 1'b1;
                mu_row1_tag    <= dec_forwarded_tag;
                mu_row1_target <= mu_target_p;
                mu_row1_is_mul <= 1'b1;
            end

            // Non-MUL: deferred commit at T+1, gated on live mu_pe_ready
            // — the residual-risk-11 fix itself. A busy-rejected dispatch
            // (mu_pe_ready false here) allocates nothing: no phantom row.
            if (mu_nonmul_takes_row0) begin
                mu_row0_busy   <= 1'b1;
                mu_row0_tag    <= mu_pending_tag;
                mu_row0_target <= mu_pending_target;
                mu_row0_is_mul <= 1'b0;
            end else if (mu_nonmul_takes_row1) begin
                mu_row1_busy   <= 1'b1;
                mu_row1_tag    <= mu_pending_tag;
                mu_row1_target <= mu_pending_target;
                mu_row1_is_mul <= 1'b0;
            end

            if (mu_mul_collision || mu_nonmul_collision) begin
                bank_tag_collision_error_r <= 1'b1;
            end

            // Stage this cycle's non-MUL launch-intent (if any) for the
            // T+1 check above, next cycle.
            mu_pending_other  <= mu_launch_other_now;
            mu_pending_tag    <= dec_forwarded_tag;
            mu_pending_target <= mu_target_p;

            if (du_launch) begin
                if (du_row_free) begin
                    du_row_busy   <= 1'b1;
                    du_row_tag    <= dec_forwarded_tag;
                    du_row_target <= du_target_p;
                end else begin
                    bank_tag_collision_error_r <= 1'b1;
                end
            end
        end
    end

    integer mb;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (mb = 0; mb < NUM_PES; mb = mb + 1)
                mu_bank_reg[mb] <= {ADDR_WIDTH{1'b0}};
        end else if (mu_out_valid) begin
            /* verilator lint_off WIDTHTRUNC */
            mu_bank_reg[mu_resolved_target] <= mu_out_payload;
            /* verilator lint_on WIDTHTRUNC */
        end
    end

    integer db;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (db = 0; db < NUM_PES; db = db + 1)
                du_bank_reg[db] <= {ADDR_WIDTH{1'b0}};
        end else if (du_out_valid) begin
            /* verilator lint_off WIDTHTRUNC */
            du_bank_reg[du_resolved_target] <= du_out_payload;
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
                if (mu_out_valid && {4'h0, mu_resolved_target} == ksrc[7:0]) begin
                    last_was_mu[ksrc] <= 1'b1;
                    last_was_du[ksrc] <= 1'b0;
                end else if (du_out_valid && {4'h0, du_resolved_target} == ksrc[7:0]) begin
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
    reg                  m_output_collision;  // v1.5.3 §20 bug-3/4 fix
    reg                  claimed;             // per-cycle "winner already picked"
    reg [NUM_PES-1:0]    pe_any_req;

    // v1.5.3 §20 fix (adversarial review bug 3+4):
    //
    // Legacy OR-merge treated the data channel (tag/payload/opcode/frag_hdr/
    // valid) and the memory channel (mem_req/mem_addr) as INDEPENDENT priority
    // chains. On collision cycles a downstream consumer would receive one
    // source's tag paired with another source's mem_req/mem_addr — a corrupted
    // tuple. Worse, MU multi-cycle SIG_BMM_3 emit (2 sequential mu_out_valid
    // cycles) doubled the L-PE-drop window with no error indication.
    //
    // Fix: ATOMIC per-source arbitration. Whichever source wins the cycle
    // contributes BOTH its data-channel fields AND its memory-channel fields
    // (or neither). Losing sources raise `m_output_collision` so downstream
    // fabric knows a fragment/mem_req was silently dropped.
    //
    // Longer-term (v1.6+): add per-source ready/valid handshake + skid buffer.
    // For now `any_output_collision` surfaces as an error signal so software
    // can detect the drop.

    always @(*) begin
        m_tag              = {TAG_WIDTH{1'b0}};
        m_payload          = {ADDR_WIDTH{1'b0}};
        m_opcode           = 8'h00;
        m_frag_hdr         = 8'h00;
        m_valid            = 1'b0;
        m_mem_req          = 1'b0;
        m_mem_addr         = {ADDR_WIDTH{1'b0}};
        m_err              = 1'b0;
        m_lwr              = 1'b0;
        m_output_collision = 1'b0;
        claimed            = 1'b0;

        // Precompute per-PE any-request bits for collision detection.
        for (i = 0; i < NUM_PES; i = i + 1) begin
            pe_any_req[i] = pe_out_valid[i] | pe_mem_req[i];
        end

        // Priority: MU > DU > L-PE[0..N-1]. Winner is ATOMIC (data + mem
        // from same source). Losers with any_req=1 raise output_collision.
        if (mu_out_valid || mu_mem_req) begin
            m_tag      = mu_out_tag;
            m_payload  = mu_out_payload;
            m_opcode   = mu_out_opcode;
            m_frag_hdr = mu_out_frag_hdr;
            m_valid    = mu_out_valid;
            m_mem_req  = mu_mem_req;
            m_mem_addr = mu_mem_addr;
            claimed    = 1'b1;
        end
        // DU: take if MU didn't claim; otherwise flag collision.
        if (du_out_valid || du_mem_req) begin
            if (!claimed) begin
                m_tag      = du_out_tag;
                m_payload  = du_out_payload;
                m_opcode   = du_out_opcode;
                m_frag_hdr = du_out_frag_hdr;
                m_valid    = du_out_valid;
                m_mem_req  = du_mem_req;
                m_mem_addr = du_mem_addr;
                claimed    = 1'b1;
            end else begin
                m_output_collision = 1'b1;
            end
        end
        // L-PE grid: same priority + collision detection.
        for (i = 0; i < NUM_PES; i = i + 1) begin
            if (pe_any_req[i]) begin
                if (!claimed) begin
                    m_tag      = pe_out_tag[i];
                    m_payload  = pe_out_payload[i];
                    m_opcode   = pe_out_opcode[i];
                    m_frag_hdr = pe_out_frag_hdr[i];
                    m_valid    = pe_out_valid[i];
                    m_mem_req  = pe_mem_req[i];
                    m_mem_addr = pe_mem_addr[i];
                    claimed    = 1'b1;
                end else begin
                    m_output_collision = 1'b1;
                end
            end
        end

        // OR-reduce error/lower across all sources (unchanged).
        m_err = mu_error | du_error;
        m_lwr = mu_lower | du_lower;
        for (i = 0; i < NUM_PES; i = i + 1) begin
            m_err = m_err | pe_error[i];
            m_lwr = m_lwr | pe_lower[i];
        end
        // v1.9 §26.5 — fold the bank tag-collision fault into the error
        // flag too, mirroring the any_output_collision precedent
        // immediately below, so existing any_error_flag consumers see it
        // without needing to know about the dedicated port.
        m_err = m_err | bank_tag_collision_error_r;
        // Fold collision into the error flag so existing consumers surface it.
        m_err = m_err | m_output_collision;
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
    assign any_output_collision = m_output_collision;   // v1.5.3 §20 bug-3/4
    assign bank_tag_collision_error = bank_tag_collision_error_r;  // v1.9 §26.5
    // v1.6.6 §22.14 — Cluster back-pressure: AND-reduce over MU/DU/L-PE ready.
    // High only when ALL PE_Core instances can accept new dispatch this cycle.
    generate
        if (NUM_PES > 0) begin : g_ready_agg
            integer pr_i;
            reg     pe_ready_and;
            always @(*) begin
                pe_ready_and = 1'b1;
                for (pr_i = 0; pr_i < NUM_PES; pr_i = pr_i + 1)
                    pe_ready_and = pe_ready_and & pe_ready_lpe[pr_i];
            end
            assign cluster_ready = mu_pe_ready & du_pe_ready & pe_ready_and;
        end
    endgenerate

endmodule
