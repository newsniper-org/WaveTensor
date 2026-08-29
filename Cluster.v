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
//   * Cluster combinationally extracts opcode (= the instruction EHDecode
//     actually latches this edge — live `ext_instruction[31:24]`, or the
//     skid-held one when a wave was deferred; see §22.14b-3 below).
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
    parameter INSTR_WIDTH = 32 + 32 + MAX_EH*96,    // W8: +CH = 448
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
    // v1.6.6 §22.14 / v1.9.2 §22.14b-3 — Cluster-level back-pressure
    // aggregate. 출력단 3항(모든 PE_Core 의 pe_ready) **AND 입력단 skid
    // 자리가 비어 있음**. v1.6.6 원문의 식은 출력단만 봤기 때문에
    // "cluster_ready=1 인데 명령이 소실된다" 가 성립했다 (§22.14b-1).
    // 이 개정으로 이 신호는 **처음으로** "지금 명령을 받아도 소실되지
    // 않는다" 를 뜻한다. 계약은 여전히 observe-only 다 (§22.14b-2).
    output                      cluster_ready,
    // v1.9 §26.5 — sticky synthesizable fault: a launch into the MU or DU
    // tag-indexed bank table found no free row (both MU rows busy, or the
    // DU row busy). Reset-clearable only — see the bank-table section
    // below for the interlock this closes (a real hardware fault, not a
    // sim-only assertion).
    output                      bank_tag_collision_error,
    // v1.9.2 §22.14b-3 — sticky synthesizable fault: 입력단 skid 가 이미
    // 점유된 상태에서 또 하나의 `wave_complete` 가 섰다. 1단 skid 에는
    // 둘째 파동을 담을 자리가 없으므로 **그 파동은 버려진다** — 포트명이
    // 그 성격(입력단 / skid / overflow)을 드러낸다. 이 상황은 곧
    // `cluster_ready==0` 인 사이클에 upstream 이 주입했다는 뜻이다
    // (skid 점유 = cluster_ready 0). 리셋으로만 지워지는 sticky 이며
    // `any_error_flag` 에도 폴딩된다. `bank_tag_collision_error` 와 같은
    // 규율: **sim-only assertion 은 쓰지 않는다** — production 보장을
    // 남기지 않기 때문이다.
    output                      input_skid_overflow_error,
    // v1.8.0e 3a-C4 §27.7a.3/§35.3 — FDOT32_CR (0x7A) 상태 2종.
    // **분리는 규범이다** (§35.3 pin 1). 하나로 합치면 §27.7a.3 검사 (i)
    // 이 성립 불가가 된다.
    //
    //   fdotcr_special_status — **정상 데이터 이벤트**. wave 의 64 lane 중
    //     하나라도 NaN/Inf/sNaN 이면 유닛이 EFT 에 들어가지 않고 canonical
    //     qNaN 을 낸다 (§27.7a.1 (iii)). SDK audit 프로그램은 이런 operand
    //     를 **일부러 투입해서** main path 와 audit path 양쪽에 sticky 가
    //     똑같이 서는지 본다. 그래서 이 신호는 **`any_error_flag` 에 절대
    //     폴딩하지 않는다** — 폴딩하면 (α) 정상적인 audit 수행 자체가 매번
    //     cluster 전역 error 를 올리고 (β) 아래 OR-reduce 는 순수 OR 라
    //     "special 이 정상 관측됐다" 와 "RTL 이 깨졌다" 를 되돌릴 수 없이
    //     뭉갠다. 폴딩 없는 전용 관측 포트다 (`any_output_collision` 형).
    //     등급도 다르다: **per-op** 이다 (§27.7a.3 이 (결과, sticky) 쌍을
    //     op 단위로 회수한다). MU 유닛에서 조합적으로 통과한다.
    //
    //   fdotcr_unit_fault_error — **RTL 결함 (loud)**. §27.7a.2b
    //     amendment-11 의 4 불변식 (expansion 배열 guard / STEP T
    //     vacuous-RTO / 용량 assert / freeze 위반) 중 하나가 무너졌다.
    //     이것만 `any_error_flag` 에 폴딩한다. 등급은 §26.5 와 같은
    //     **reset-clearable only sticky** 이며, 그 승격이 여기서 일어나는
    //     이유는 `FP_StepSeq` 에 `rst` 포트가 없어 (reset-free 블록) 유닛
    //     안에서는 launch 마다 지워지는 per-op latch 밖에 만들 수 없기
    //     때문이다. 그냥 통과시키면 "sticky 라고 이름만 붙은 pulse" 가 되어
    //     다음 launch 에 조용히 지워진다.
    output                      fdotcr_special_status,
    output                      fdotcr_unit_fault_error
);

    localparam NUM_PES = PE_ROWS * PE_COLS;

    // Opcode extracted combinationally up-front — needed by both the
    // fragment/cache buffer below (CACHE_LOAD_WIDE detection) and the
    // op-class classifiers further down.
    // W1 — opcode 는 12b 다. 8비트로 뽑으면 확장 니블이 접혀 0x4## 명령이
    // 0x0## 분류에 조용히 얹힌다 (디코더가 뒤에서 malformation 을 내더라도
    // 이 층의 라우팅·자원 예약은 이미 움직인다). 상위 니블을 함께 뽑는다.
    wire [11:0] ext_opcode = {ext_instruction[11:8], ext_instruction[31:24]};

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
                                     && (ext_opcode == 12'h068);
    // v1.6.5d §22.17 — FRAG_INVAL (0x6A) request: mirrors cache_load_req's
    // shape exactly. Mutually exclusive with cache_load_req since
    // ext_opcode is a single 8-bit value per cycle (0x68 vs 0x6A cannot
    // both be true), so inval_hit/cache_hit are automatically disjoint
    // with zero extra interlock logic.
    wire inval_req = ext_valid && (ext_frag_hdr == 8'h00)
                                && (ext_opcode == 12'h06A);

    // Per-slot hit classification (combinational). At most one of
    // hit_continue[s]/hit_ready[s] can be true for a given s (mutually
    // exclusive on frag_ready[s]).
    reg hit_continue [0:FRAG_SLOTS-1];
    reg hit_ready    [0:FRAG_SLOTS-1];
    // v1.9.2 §22.14b-4b — "이미 완성됐는데 아직 철거되지 않은" 슬롯.
    // §22.14b-4 의 accept-종속 철거가 이 상태를 **새로 만들었다** (HEAD 에는
    // 없던 상태다: 예전에는 완성 에지에 무조건 철거했으므로 full mask 가
    // 유지된 채 `frag_active && !frag_ready` 인 슬롯이 존재할 수 없었다).
    // 그 상태의 슬롯에 같은 tag 의 조각이 도착하면 가득 찬 mask 에 병합돼
    // **즉시 거짓 완성**한다 — stale wide 를 실행하는 새 오염 경로다.
    reg [FRAG_SLOTS-1:0] slot_complete_held;
    integer ghi;
    always @(*) begin
        for (ghi = 0; ghi < FRAG_SLOTS; ghi = ghi + 1) begin
            // 슬롯 자신의 `frag_total_m1` 로 만든 full mask 와의 비교.
            // shift amount 를 5 비트로 넓히는 것은 §25.3 의 latent-bug 수리와
            // **같은 이유**다 (tot_m1=15 에서 4비트 덧셈이 0 으로 랩한다).
            slot_complete_held[ghi] =
                frag_active[ghi] && !frag_ready[ghi]
                && (frag_mask[ghi] ==
                    (({15'h0, 1'b1} << ({1'b0, frag_total_m1[ghi]} + 5'd1))
                     - {{(FRAG_MAX-1){1'b0}}, 1'b1}));
            // v1.9.2 §22.14b-4b — 완성 보류 슬롯은 **continue 대상이 아니다.**
            // 정상 동작에서는 도달 불가능한 조건이므로 (완성 에지에 accept 이
            // 나면 같은 에지에 철거/ready 승격된다) 기존 동작에 대해 **no-op**
            // 이고, 위 새 오염 경로에서만 발동해 병합 대신 **새 할당**으로
            // 보낸다 — 재전송된 파동이 처음부터 다시 조립된다.
            hit_continue[ghi] = frag_active[ghi] && !frag_ready[ghi]
                              && (ext_tag == frag_tag_reg[ghi])
                              && !slot_complete_held[ghi];
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
        end else begin
            // v1.9.2 §22.14b-4b — 아래 if/else-if 사슬은 **경쟁 arm 만** 담고,
            // deferred CAM commit 은 사슬 **밖**(끝)에 따로 둔다. 초판은 그것을
            // 사슬의 마지막 arm 으로 넣었는데, 그러면 `cache_hit`(다른 tag 의
            // 0x68) 하나만 겹쳐도 commit 이 **영구히 밀려** 슬롯이 "완성됐는데
            // 철거되지 않은" 상태로 남았다 — 재시도 경로가 없으므로 그 상태는
            // 다시는 해소되지 않는다. 사슬 밖으로 빼면 `cache_hit`(frag_age 만
            // 쓴다) · `inval_hit`(ready 슬롯만 대상이라 완성 보류 슬롯과 절대
            // 겹치지 않는다) · 다른 슬롯의 조각 beat 와 **동시에** 성립할 수
            // 있고, 유일한 실 충돌(같은 슬롯을 노리는 조각 beat)만 아래
            // `skid_slot_taken` 으로 배제한다.
            if (frag_in_multi) begin
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
                //
                // v1.9.2 §22.14b-4 (normative) — **철거를 accept 에 종속시킨다.**
                // 이전에는 `frag_reass_valid` 만으로 무조건 철거했으므로,
                // EHDecode 가 그 파동을 받지 못한 사이클에는 재조립 payload 까지
                // 함께 사라졌다 (명령 1건이 아니라 파동 전체의 소실).
                // `live_accept` 는 §22.14b-3 의 **단일 accept 정의**에서 온
                // 그대로의 신호다 (조건이 갈라지면 그 자체가 다음 결함이다).
                // accept 이 나지 않으면 슬롯은 손대지 않고, 보류분이 투입되는
                // 에지에 아래 deferred-commit arm 이 같은 일을 대신 한다.
                if (frag_reass_valid && live_accept) begin
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
            // -------------------------------------------------------------------
            // v1.9.2 §22.14b-4 — **deferred CAM commit** (사슬 밖, 독립 arm).
            // 보류됐던 다중 조각 완성 파동이 투입되는 에지에, 위 완성 arm 이
            // accept 종속 때문에 미뤄 둔 슬롯 처리를 정확히 같은 형태로 수행한다.
            // 이것이 없으면 슬롯이 "완성됐는데 철거되지 않은" 상태로 남고,
            // **같은 tag 로 재전송된 파동의 첫 조각이 가득 찬 mask 에 병합돼
            // 즉시 거짓 완성**한다 — HEAD 에는 없던 오염을 새로 들이게 된다.
            //
            // v1.9.2 §22.14b-4b (적대 검증 항 3 수리) — **사슬 밖으로 옮겼다.**
            // 초판에서는 이 arm 이 `frag_in_multi`/`cache_hit`/`inval_hit` 뒤의
            // 마지막 else-if 였고, 그래서 투입 에지에 **다른 tag 의 0x68 하나만
            // 겹쳐도** commit 이 밀렸다. 재시도 경로가 없으므로 그것은 지연이
            // 아니라 **영구 누락**이고, 위 거짓 완성 경로가 그대로 열린다.
            // 이제 이 arm 은 다음 셋과 **동시에** 성립한다:
            //   * `cache_hit`  — `frag_age` 만 쓴다 (레지스터 교집합 0)
            //   * `inval_hit`  — `hit_ready` 대상(= `frag_ready==1`)만 건드리는데
            //                    완성 보류 슬롯은 `frag_ready==0` 이라 **구조적으로
            //                    같은 슬롯일 수 없다**
            //   * 다른 슬롯을 노리는 조각 beat
            // 유일한 실 충돌은 **같은 슬롯을 노리는 조각 beat** 이며, 그것은
            // `skid_slot_taken` 으로 배제한다 (그 beat 가 슬롯의 새 주인이므로
            // 여기서 철거하는 것이 오히려 파괴다). 그 경우 deferred commit 은
            // 아래 skid always 블록에서 **취소**된다 — 밀리는 것이 아니라
            // 없어진다 (§22.14b-4b).
            //
            // NBA 순서 주의: 이 arm 이 블록의 **마지막**이므로 같은 레지스터에
            // 대해서는 여기가 이긴다. 위 `skid_slot_taken` 배제가 그 승리가
            // 파괴가 되지 않도록 보장하는 유일한 장치다.
            if (skid_commit_now) begin
                if (FRAG_SLOTS > 1) begin
                    frag_ready[skid_frag_slot] <= 1'b1;
                end else begin
                    frag_active[skid_frag_slot] <= 1'b0;
                    frag_mask[skid_frag_slot]   <= {FRAG_MAX{1'b0}};
                end
            end
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

    // -------------------------------------------------------------------------
    // v1.9.2 §22.14b-3 (normative) — 입력단 **skid buffer 1단**.
    //
    // 무엇이 잘못돼 있었나 (§22.14b-1 확정 사실):
    //   공유 `EHDecode` 는 체인 워크 중(`stg_active==1`) 도착한 명령을
    //   `EHDecode.v:195`(입력 래치)·`:350`(워크 kick) 양쪽에서 **읽지 않는다**
    //   — 큐 0 · 홀드 0 · 에러 비트 0. 그런데 여기 `wave_complete` 에는
    //   `stg_active` 항이 없어 **항상 쏜다**. 결과는 오염이 아니라 **순수
    //   소실**이고, 재시도 경로가 없어 영구하며, 어떤 status 비트도 서지
    //   않으므로 loud-fault-never-silent 를 정면으로 위반했다.
    //   `MAX_EH=4` 이므로 kick 후 4 에지가 blackout 이다.
    //
    // 왜 ready 정정만으로는 못 고치는가 (§22.14b-2):
    //   `cluster_ready` 는 **RTL 소비자가 0건**이다 (Cluster → Pod →
    //   래퍼에서 끝). observe-only 를 enforced stall 로 바꿔도 강제할 상대가
    //   없어 손실을 1건도 줄이지 못하고, 결함을 관측 불가능하게 만들 뿐이다.
    //   손실을 구조적으로 0 으로 만드는 유일한 수단이 **보류 경로**다.
    //
    // 형태:
    //   * `EHDecode` 가 비어 있으면(`in_ready`) 파동은 **그대로 통과**한다
    //     (bypass mux — latency 델타 0). 점유 중이면 **보류**했다가
    //     `in_ready` 가 서는 최초 에지에 투입한다.
    //   * 보류 대상은 EHDecode 가 그 사이클에 읽는 것 **전건**이다:
    //     instruction 416b · tag 80b · payload 64b · payload_b 64b+valid 1b
    //     · wide 1,024b+valid 1b · frag_hdr 8b = 1,658b, + 점유 1b = 1,659b.
    //     **부분 보류는 금지한다** — 한 필드라도 빠지면 투입 시점에 live
    //     값과 섞여, 현재는 존재하지 않는 실패 모드인 **오염**이 새로 생긴다.
    //     (`skid_frag_slot` 은 EHDecode 입력이 아니라 §22.14b-4 deferred
    //     CAM commit 전용 부기이며, 보류 폭 회계에는 들어가지 않는다.)
    //   * 투입 시점의 값은 도착 시점의 값과 **bit-identical** 이다. 특히
    //     `cluster_b_payload` 는 **도착 사이클에 해석된 값**을 담는다 —
    //     NoC bank / TRNG 소스를 투입 시점에 다시 읽으면 최대 `MAX_EH`
    //     에지 뒤의 다른 값이 되기 때문이다.
    //   * 보류 창은 상수가 아니라 `MAX_EH` 의 함수다. blackout 이 `MAX_EH`
    //     에지이므로 skid 는 반드시 배출된다 — 무한 보류는 구조적으로
    //     불가능하다.
    //
    // 왜 mux 를 살려 두고 "상시 경유 레지스터" 로 만들지 않았는가:
    //   상시 경유는 투입 mux 를 통째로 없애 LUT 를 아끼지만 **Cluster ext
    //   경계 latency 가 균일 +1** 이 된다 (§5 표 재bump 동반). 그것은
    //   §22.14b-5 의 cut ladder rung 2 로 **미리 공표**돼 있고, gate breach
    //   가 실측으로 확인됐을 때 발동하는 축소안이다. 측정 전에 미리
    //   당겨쓰지 않는다.
    // -------------------------------------------------------------------------
    // 파동 완성 펄스 (live). 단일 조각(frag_hdr==0x00)은 즉시, 다중 조각은
    // 마지막 조각의 사이클에만 선다. **이 신호는 "도착" 이지 "accept" 가
    // 아니다** — 그 구분이 없던 것이 §22.14b-1 결함의 형태 그 자체였다.
    wire wave_complete = ext_valid
                       && ((ext_frag_hdr == 8'h00) || frag_reass_valid);

    // EHDecode 의 입력단 accept 가능 여부 (v1.9.2 신규 포트, `!stg_active`).
    // 인스턴스는 아래에 있지만 Verilog-2001 은 선언 선행을 요구하므로
    // 여기서 미리 선언한다 (EHDecode.v D3 수리와 같은 사유).
    wire ehdec_in_ready;

    // ---- 보류 저장소 (1단) ----
    reg                           skid_valid;
    reg [INSTR_WIDTH-1:0]         skid_instruction;
    reg [TAG_WIDTH-1:0]           skid_tag;
    reg [ADDR_WIDTH-1:0]          skid_payload;
    reg [ADDR_WIDTH-1:0]          skid_payload_b;
    reg                           skid_payload_b_valid;
    reg [FRAG_MAX*ADDR_WIDTH-1:0] skid_payload_wide;
    reg                           skid_payload_wide_valid;
    reg [7:0]                     skid_frag_hdr;
    // §22.14b-4 deferred CAM commit 전용 부기 — 보류분이 어느 CAM 슬롯을
    // 완성시켰는지. `skid_frag_hdr != 0` 일 때만 의미를 갖는다.
    reg [SLOT_W-1:0]              skid_frag_slot;

    // -------------------------------------------------------------------------
    // accept 조건 **단일 정의** (§22.14b-3 normative).
    //
    // "EHDecode 가 이 파동을 실제로 받았다" 를 여기 한 곳에서 정의하고,
    // (i) EHDecode `in_valid`, (ii) `pe_active_*_s1` 로드, (iii) CAM 슬롯
    // 철거 — 셋이 **같은 wire** 를 읽는다. 조건이 갈라지면 그 자체가 다음
    // 결함이다.
    //
    // 근거는 **정의 정합성**이다: EHDecode 가 명령을 래치하는 에지는
    // `in_valid && in_ready` 인 에지 하나뿐이고 (`EHDecode.v:195/:350` 의
    // 가드가 문자 그대로 그 조건이다), 위 셋은 전부 "그 래치가 일어났다"
    // 를 전제로 하는 후속 동작이다. 도착(`wave_complete`)을 읽는 판은
    // 래치가 없었던 에지에도 후속 동작을 일으킨다 — 그 자체로 정의 위반이다.
    //
    // **정직 정정 (2026-08-18 적대 검증 항 2)**: 이 자리의 초판 주석은
    // 근거로 "`MAX_EH` 가 바뀌면 그대로 오발 디스패치가 된다" 를 들었다.
    // 그 시나리오는 **실증 불가능**하다 — `MAX_EH` 를 2 나 6 으로 바꾸면
    // skid 와 무관하게 Cluster 가 무동작이 되기 때문이다 (아래 `pe_active`
    // 정렬 파이프의 깊이 6 이 하드코딩이고 `EHDecode.v:481-482` 가 이미
    // 그 lockstep 요구를 명시한다. HEAD 로도 `MAX_EH=6` 에서 49건 중 36건
    // FAIL 이므로 **pre-existing** 이며 본 개정이 만든 것이 아니다).
    // 즉 `MAX_EH` 는 독립적으로 움직일 수 있는 축이 아니고, 그것이 바뀌는
    // 순간 파이프 정렬이 먼저 깨진다. 근거는 위 **정의 정합성** 하나로
    // 충분하며, 도달 불가능한 시나리오를 근거로 들지 않는다.
    //
    // 1단 skid 의 점유 규약: `skid_valid` 가 서 있는 동안 `cluster_ready` 는
    // 0 이다. 따라서 그 사이클의 도착은 **계약 위반**이고, 투입이 같은
    // 사이클에 일어나는지와 무관하게 loud fault 로 처리한다 — 즉
    // `cluster_ready` 가 약속한 것과 fault 조건이 **정확히 같은 경계**를
    // 쓴다. (더 공격적인 "투입과 동시 적재" 를 허용하면 그 사이클의
    // EHDecode OPREF 반사는 보류분 instruction 을 보고 있으므로 새로
    // 적재되는 파동의 `cluster_b_payload` 가 **다른 명령의 src_kind 로**
    // 해석된다 — bit-identical 요건이 깨진다. 한 사이클의 처리율보다
    // 정확성을 택했다.)
    // -------------------------------------------------------------------------
    wire skid_inject = skid_valid && ehdec_in_ready;              // 보류분 투입
    wire live_accept = wave_complete && !skid_valid && ehdec_in_ready;
    wire wave_accept = skid_inject || live_accept;                // 단일 정의
    wire skid_load   = wave_complete && !skid_valid && !ehdec_in_ready;
    // 2개째 도착 = loud sticky fault. 버려지는 파동이 조용히 사라지지 않는다.
    wire skid_overflow_now = wave_complete && skid_valid;

    // -------------------------------------------------------------------------
    // v1.9.2 §22.14b-4b — deferred CAM commit 의 성립/취소 조건.
    //
    // `skid_slot_taken` = 이번 에지의 조각 beat 가 **보류분이 완성시킨 그
    // 슬롯**을 노린다. 그 beat 가 슬롯의 새 주인이므로 deferred commit 은
    // 성립하지 않으며(아래 `skid_commit_now` 에서 배제), 보류가 계속되는
    // 경우에는 skid always 블록이 `skid_frag_hdr` 를 0 으로 만들어 commit
    // 자체를 **취소**한다 — 밀리는 것이 아니라 없어진다. (보류분의 wide
    // payload 는 이미 `skid_payload_wide` 에 복제돼 있으므로 보류 파동
    // 자체는 이 취소에 아무 영향도 받지 않는다.)
    //
    // FRAG_SLOTS=1 에서 `alloc_idx`/`skid_frag_slot` 은 둘 다 1비트 0 이라
    // 이 조건은 "조각 beat 가 오면 참" 과 같다 — 슬롯이 하나뿐이니 옳다.
    wire skid_slot_taken = frag_in_multi && (alloc_idx == skid_frag_slot);
    // 가드 3건. 앞의 둘은 초판 그대로다:
    //   * `skid_frag_hdr != 0` — 보류분이 다중 조각 완성이었을 때만.
    //     단일 조각(0x00)은 애초에 CAM 을 거치지 않는다.
    //   * `frag_active[slot] && tag 일치` — 보류 창(≤ `MAX_EH` 에지) 동안
    //     그 슬롯이 **다른** tag 의 파동에 재할당됐다면 건드리지 않는다.
    // 셋째가 §22.14b-4b 에서 추가됐다 (같은 tag 재할당은 tag 비교로는
    // 잡히지 않으므로 슬롯 인덱스로 직접 배제한다):
    wire skid_commit_now = skid_inject && (skid_frag_hdr != 8'h00)
                        && frag_active[skid_frag_slot]
                        && (frag_tag_reg[skid_frag_slot] == skid_tag)
                        && !skid_slot_taken;

    // EHDecode 가 이번 에지에 래치할 명령/태그. 보류분이 있으면 그것이
    // 먼저다 (프로그램 순서 보존 — 새 파동이 보류분을 추월할 수 없다).
    wire [INSTR_WIDTH-1:0] ehdec_instruction =
        skid_valid ? skid_instruction : ext_instruction;
    wire [TAG_WIDTH-1:0]   ehdec_tag =
        skid_valid ? skid_tag         : ext_tag;
    // 라우팅 분류는 **실제로 래치되는 명령**에서 뽑아야 한다. live 값에서
    // 뽑으면 투입 사이클에 (ext_valid=0 인) 엉뚱한 워드를 분류한다.
    wire [11:0] acc_opcode = {ehdec_instruction[11:8], ehdec_instruction[31:24]};  // W1: 12b

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
    // v1.9.2 §22.14b-3 — 분류 입력이 `ext_opcode`(live)에서
    // `acc_opcode`(EHDecode 가 이번 에지에 실제로 래치하는 명령)로 바뀌었다.
    // opcode 리터럴 집합은 **한 글자도 바뀌지 않았다** — twin-classifier
    // 불변식(PE_Core.v `dec_is_mul_op` 와 lockstep)은 그대로다.
    wire is_mul_op = (acc_opcode == 12'h012)
                  || (acc_opcode == 12'h030)
                  || (acc_opcode == 12'h032)
                  || (acc_opcode == 12'h043)
                  || (acc_opcode == 12'h06B)
                  || (acc_opcode == 12'h070)
                  || (acc_opcode == 12'h071)
                  || (acc_opcode == 12'h072)
                  || (acc_opcode == 12'h073)
                  || (acc_opcode == 12'h074)
                  || (acc_opcode == 12'h075)
                  || (acc_opcode == 12'h076)
                  || (acc_opcode == 12'h077)
                  || (acc_opcode == 12'h078)
                  || (acc_opcode == 12'h079)
    // v1.8.0e 3a-C4 §35.1 — 0x7A FDOT32_CR joins OPCODE-ONLY in lockstep
    // with PE_Core.v's dec_is_mul_op (MU-hosted: the step program lives in
    // the MU's FP_StepSeq). A one-sided edit is the silent permanent
    // lower_required dead-end, and test_twin_classifier_lockstep_static
    // pins both literal sets against each other AND against a hardcoded
    // set. NOTE for future editors: that test extracts this expression by
    // scanning to the first statement terminator, so a comment INSIDE the
    // expression must not contain one — this very comment cost a debug
    // cycle when it did.
                  || (acc_opcode == 12'h07A);
    wire is_div_op = (acc_opcode == 12'h013)   // DIV
                  || (acc_opcode == 12'h01C)   // MOD
                  || (acc_opcode == 12'h01D);  // DIVMOD
    // v1.5.2 §19 — wave-complete gate. (`wave_complete` 자체의 정의는
    // §22.14b-3 skid 절로 옮겼다 — skid 제어가 그것을 먼저 읽어야 하고
    // Verilog-2001 은 선언 선행을 요구하기 때문이다. 정의식은 한 글자도
    // 바뀌지 않았다.)
    //
    // v1.9.2 §22.14b-3 — 아래 세 신호는 이제 "도착(`wave_complete`)" 이
    // 아니라 **accept(`wave_accept`)** 에 걸린다. 이것이 항 4 의 실체다:
    // `pe_active_*_s1` 로드가 EHDecode 의 실제 래치 에지와 **정의상**
    // 같아진다. 이전에는 EHDecode 가 명령을 버린 사이클에도 s1 이
    // 실려 6단 파이프를 타고 내려갔다 — 현행 파이프 깊이의 우연 일치로
    // dec_valid 가 뜨지 않아 무해했을 뿐인 **고아 펄스**였다.
    //
    // **정직 정정 (2026-08-18 적대 검증 항 2)**: 초판은 여기에 "`MAX_EH`
    // 가 바뀌면 그대로 오발 디스패치" 를 근거로 덧붙였으나 그 시나리오는
    // 실증 불가능하다 (아래 `pe_active` 파이프 깊이 6 이 하드코딩이라
    // `MAX_EH` 를 바꾸면 정렬이 먼저 깨진다 — pre-existing, `EHDecode.v:
    // 481-482` 참조). 근거는 위 **정의 정합성**(고아 펄스를 없앤다)
    // 하나이며, 그것만으로 충분하다.
    wire ext_to_mu  = wave_accept &&  is_mul_op;
    wire ext_to_du  = wave_accept &&  is_div_op;
    wire ext_to_lpe = wave_accept && !is_mul_op && !is_div_op;

    // -------------------------------------------------------------------------
    // Logical port_context_id → linear PE index
    //
    // v1.9.2 §22.14b-3 — 태그도 `ext_tag`(live)가 아니라 `ehdec_tag`
    // (이번 에지에 실제로 래치되는 태그)에서 뽑는다. 보류분 투입 사이클에는
    // `ext_valid=0` 이라 live 태그가 의미 없는 값이므로, 여기를 고치지
    // 않으면 보류분이 **엉뚱한 PE 로** 디스패치된다.
    // -------------------------------------------------------------------------
    /* verilator lint_off UNUSEDSIGNAL */
    wire [15:0] in_pcid = ehdec_tag[31:16];
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
    // `dec_port_context_id` 는 여기서 받지 않는다 (인스턴스에서 명시적 미접속).
    // Cluster 의 라우팅은 dec_* 버스가 아니라 `ext_tag[31:16]` 에서 직접 뽑은
    // 조합 신호 `in_pcid` (:498) 를 쓴다 — dec_* 는 EHDecode stage-1 만큼
    // 늦어서 같은 에지에 필요한 target_idx 를 만들 수 없기 때문이다.

    // OPREF reflection (combinational from ext_instruction) — used by the
    // bank-routing combinational logic so the chosen `cluster_b_payload` is
    // ready in time for EHDecode's stage-1 latch on the same edge.
    wire [3:0] eff_opref_kind_c;
    // `opref_port_id_out` 역시 받지 않는다 (인스턴스에서 명시적 미접속).
    // bank 선택은 아래 :613 에서 `eff_opref_route_c[3:0]` 하나로 끝난다.
    // route 상위 니블 [7:4] 은 spec 폭(8-bit noc_route)을 유지하기 위해
    // 남겨둔 것이고 현 지오메트리에서는 읽히지 않는다 — 폭을 줄이면 EH
    // 필드에서 묵시적 절단이 생기므로 줄이지 않는다.
    /* verilator lint_off UNUSEDSIGNAL */
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
    //   * `test_isa_decoder.py::test_output_payload_hold_invariant` — 런타임
    //     감시 (C-2 에서 `test_pe.py` 로부터 이식 — `PE.v` 폐기, spec §33.4).
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

    // -------------------------------------------------------------------------
    // v1.9.2 §22.14b-3 — skid 투입 mux (데이터 경로 나머지).
    // instruction / tag 는 위 skid 절에서 이미 선택했다 (분류기가 먼저
    // 읽어야 해서). 여기는 EHDecode 가 읽는 나머지 전건이다.
    //
    // 선택 신호가 `skid_valid` **하나**인 것이 핵심이다: 보류분이 있으면
    // 전 필드가 통째로 보류분에서 온다. 필드별로 다른 선택 신호를 쓰면
    // 그 순간 live 값과 섞인 오염이 생긴다 (§22.14b-3 "부분 보류 금지").
    // -------------------------------------------------------------------------
    wire [ADDR_WIDTH-1:0] ehdec_payload =
        skid_valid ? skid_payload            : ehdec_input_payload;
    wire [ADDR_WIDTH-1:0] ehdec_payload_b =
        skid_valid ? skid_payload_b          : cluster_b_payload;
    wire                  ehdec_payload_b_valid =
        skid_valid ? skid_payload_b_valid    : cluster_b_valid;
    wire [FRAG_MAX*ADDR_WIDTH-1:0] ehdec_wide =
        skid_valid ? skid_payload_wide       : final_wide;
    wire                  ehdec_wide_valid =
        skid_valid ? skid_payload_wide_valid : final_wide_valid;

    EHDecode #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .TAG_WIDTH  (TAG_WIDTH),
        .MAX_EH     (MAX_EH),
        .INSTR_WIDTH(INSTR_WIDTH)
    ) u_ehdec (
        .clk                       (clk),
        .rst                       (rst),
        // v1.9.2 §22.14b-3 — `in_valid` 은 도착이 아니라 **accept** 다.
        // `wave_accept` 는 두 항 모두 `ehdec_in_ready` 를 포함하므로
        // EHDecode 내부의 `in_valid && !stg_active` 가드와 항상 일치한다.
        .in_valid                  (wave_accept),
        .instruction               (ehdec_instruction),
        .input_tag                 (ehdec_tag),
        .input_payload             (ehdec_payload),
        .input_payload_b           (ehdec_payload_b),
        .input_payload_b_valid     (ehdec_payload_b_valid),
        .input_payload_wide        (ehdec_wide),
        .input_payload_wide_valid  (ehdec_wide_valid),
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
        // 미접속 2건은 의도적이다 — 위 wire 선언부의 사유 주석 참조.
        .dec_port_context_id       (),
        .opref_src_kind_out        (eff_opref_kind_c),
        .opref_port_id_out         (),
        .opref_noc_route_out       (eff_opref_route_c),
        .in_ready                  (ehdec_in_ready)
    );

    // -------------------------------------------------------------------------
    // v1.9.2 §22.14b-3 — skid 저장소 갱신 + overflow sticky fault.
    //
    // `skid_load` 와 `skid_inject` 는 **구조적으로 상호 배타**다
    // (`skid_load` 는 `!skid_valid`, `skid_inject` 는 `skid_valid` 를 요구).
    // else-if 는 그 사실의 표기이지 우선순위 결정이 아니다.
    //
    // 적재값은 전부 **도착 사이클의 조합 결과**다. 특히
    // `cluster_b_payload` / `cluster_b_valid` 는 이 사이클의 EHDecode OPREF
    // 반사(`eff_opref_kind_c`)로 이미 해석된 값이고, 그 반사는 이 사이클에
    // `skid_valid==0` 이므로 **live `ext_instruction` 의** src_kind 다 —
    // 즉 지금 적재하는 바로 그 파동의 것이다. (이 성립이 위 accept 정의의
    // 보수적 경계를 택한 이유다.)
    //
    // sticky fault 정책은 §26.5 `bank_tag_collision_error` 와 동일하다:
    // 리셋으로만 지워지고, `any_error_flag` 에 폴딩되며, sim-only assertion
    // 이 아니라 **합성되는 status 비트**다.
    // -------------------------------------------------------------------------
    reg input_skid_overflow_error_r;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            skid_valid                 <= 1'b0;
            skid_instruction           <= {INSTR_WIDTH{1'b0}};
            skid_tag                   <= {TAG_WIDTH{1'b0}};
            skid_payload               <= {ADDR_WIDTH{1'b0}};
            skid_payload_b             <= {ADDR_WIDTH{1'b0}};
            skid_payload_b_valid       <= 1'b0;
            skid_payload_wide          <= {(FRAG_MAX*ADDR_WIDTH){1'b0}};
            skid_payload_wide_valid    <= 1'b0;
            skid_frag_hdr              <= 8'h00;
            skid_frag_slot             <= {SLOT_W{1'b0}};
            input_skid_overflow_error_r <= 1'b0;
        end else begin
            if (skid_load) begin
                skid_valid              <= 1'b1;
                skid_instruction        <= ext_instruction;
                skid_tag                <= ext_tag;
                skid_payload            <= ehdec_input_payload;
                skid_payload_b          <= cluster_b_payload;
                skid_payload_b_valid    <= cluster_b_valid;
                skid_payload_wide       <= final_wide;
                skid_payload_wide_valid <= final_wide_valid;
                skid_frag_hdr           <= ext_frag_hdr;
                skid_frag_slot          <= alloc_idx;
            end else if (skid_inject) begin
                // 데이터 필드는 굳이 지우지 않는다 — `skid_valid` 가 유일한
                // 유효성 근거이고, 지우면 1,658 비트에 리셋 팬아웃이 하나 더
                // 생길 뿐 관측 가능한 차이가 없다.
                skid_valid <= 1'b0;
            end else if (skid_valid && (skid_frag_hdr != 8'h00)
                         && skid_slot_taken) begin
                // v1.9.2 §22.14b-4b — **deferred commit 취소.** 보류 창 동안
                // 조각 beat 가 그 슬롯을 가져갔다 (같은 tag 재전송이든 다른
                // tag 재할당이든). 슬롯의 주인이 바뀌었으므로 나중에 투입
                // 에지에서 철거하면 **새 주인의 데이터를 부순다**. tag 비교
                // 가드만으로는 같은 tag 재전송을 걸러낼 수 없어서 여기서
                // 인덱스로 끊는다.
                //
                // 보류분 자체는 무해하다 — wide payload 는 이미
                // `skid_payload_wide` 에 **복제**돼 있으므로 슬롯을 잃어도
                // 투입되는 값은 bit-identical 그대로다 (§22.14b-3 이 재독출
                // 대신 복제를 택한 이유가 여기서 값을 한다).
                skid_frag_hdr <= 8'h00;
            end

            if (skid_overflow_now) begin
                input_skid_overflow_error_r <= 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Per-unit `pe_active` — pipelined to align with EHDecode's stage-1
    // latency. `pe_active_p` is what the corresponding PE_Core sees on the
    // cycle when its dec_* operand-bus carries the matching instruction.
    // -------------------------------------------------------------------------
    // 6-stage pipe to align with EHDecode's pipelined chain walk:
    //   accept edge (1) → SLOT 0 (2) → SLOT 1 (3) → SLOT 2 (4) → SLOT 3 (5)
    //   → dec_* latch (6). pe_active is what PE_Core sees on the cycle when
    //   dec_valid=1 (Edge 6→7), so the registered value must be held in
    //   stage s6 during that interval.
    //
    // v1.9.2 §22.14b-3 항 4 — 1단(s1)의 기준 에지가 "ext_valid 에지" 에서
    // **accept 에지**로 바뀌었다 (`ext_to_*` 가 `wave_accept` 를 읽는다).
    // 두 에지는 EHDecode 가 비어 있을 때만 일치하고, 보류가 걸리면 최대
    // `MAX_EH` 에지만큼 벌어진다. 파이프의 정렬 기준은 EHDecode 의 **실제
    // 래치 에지**이므로 이쪽이 정의상 옳다.
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
    // v1.8.0e 3a-C4 §35.3 — FDOT32_CR sticky 2종을 **모든** PE_Core 에서
    // 거둔다. 오늘의 형상에서 L-PE 16개는 MUL_OPS_SUPPORTED=0 이라
    // g_v180c_fp_off 가 두 신호를 1'b0 로 zero-tie 하고, 그 상수는
    // elaboration 에서 접혀 면적이 0 이다. 그럼에도 결선을 남기는 이유는
    // 승격 로직이 "MU 만 결함을 낼 수 있다" 를 **하드코딩하지 않게** 하기
    // 위해서다 — 어느 인스턴스가 FP_StepSeq 를 호스팅하는지는 파라미터의
    // 함수이지 이 블록이 알아야 할 사실이 아니다.
    wire                   pe_fdotcr_spec [0:NUM_PES-1];
    wire                   pe_fdotcr_flt  [0:NUM_PES-1];

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
                    .lower_required            (pe_lower[IDX]),
                    // v1.8.0e 3a-C4 §35.3 — L-PE 는 MUL_OPS_SUPPORTED=0
                    // 이라 이 두 신호가 구조적으로 상수 0 이다 (면적 0).
                    // 그래도 결선한다 — 위 선언부의 사유 참조.
                    .fp_special_sticky         (pe_fdotcr_spec[IDX]),
                    .fp_unit_fault             (pe_fdotcr_flt[IDX])
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
    // v1.8.0e 3a-C4 §27.7a.3/§35.3 — FDOT32_CR sticky 2종의 MU 원천.
    // 둘 다 유닛 안에서는 **per-op latch** 다 (매 fd_launch 가 덮어쓴다).
    wire                  mu_fdotcr_special;  // 정상 데이터 이벤트 — 폴딩 금지
    wire                  mu_fdotcr_fault;    // RTL 결함 — 아래에서 §26.5 승격

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
        .lower_required            (mu_lower),
        // v1.8.0e 3a-C4 §35.3 — FDOT32_CR 는 MU 전용이다 (FP_StepSeq 를
        // 가진 유일한 인스턴스). 두 sticky 의 실제 소스는 여기뿐이다.
        .fp_special_sticky         (mu_fdotcr_special),
        .fp_unit_fault             (mu_fdotcr_fault)
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
    wire                  du_fdotcr_special;  // v1.8.0e 3a-C4 — 구조적 0
    wire                  du_fdotcr_fault;    // v1.8.0e 3a-C4 — 구조적 0

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
        .lower_required            (du_lower),
        // v1.8.0e 3a-C4 §35.3 — DIV-UNIT 도 MUL_OPS_SUPPORTED=0 이라
        // 구조적 상수 0 (L-PE 와 같은 사유로 그래도 결선한다).
        .fp_special_sticky         (du_fdotcr_special),
        .fp_unit_fault             (du_fdotcr_fault)
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

    // v1.8.0e 3a-C4 §27.7a.3/§35.3 항 2 — FDOT32_CR unit fault 의 §26.5
    // 등급 승격. `FP_StepSeq` 는 reset-free 블록이라 (rst 포트 자체가 없다)
    // 유닛 안에서는 launch 마다 지워지는 per-op latch 밖에 만들 수 없다.
    // 그 pulse/level 을 여기서 받아 **reset-clearable only** sticky 로
    // 세운다 — `bank_tag_collision_error_r` 와 정확히 같은 등급이다.
    // 승격하지 않고 그냥 포트로 통과시키면 "sticky 라고 이름만 붙은
    // pulse" 가 되어 다음 launch 에 조용히 지워진다 (loud-fault-never-
    // silent 위반의 전형).
    reg fdotcr_unit_fault_r;
    // 인스턴스 횡단 수집 결과 (아래 출력 머지 블록이 구동한다). 여기서
    // 선언하는 이유는 Verilog 가 선언 선행을 요구하고, 바로 아래 bank-table
    // 순차 블록이 `m_fd_fault` 를 set 조건으로 읽기 때문이다.
    // **m_fd_spec 는 관측 전용** — `m_err` 폴딩에 절대 들어가지 않는다.
    reg m_fd_spec, m_fd_fault;

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
            fdotcr_unit_fault_r        <= 1'b0;   // v1.8.0e 3a-C4 §35.3
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

            // v1.8.0e 3a-C4 §35.3 — FDOT32_CR unit fault 승격. MU 의
            // per-op latch 가 서면 여기서 리셋까지 붙잡는다. `fd_spec`
            // (정상 데이터 이벤트) 는 **여기 들어오지 않는다** — 그것을
            // 섞으면 §27.7a.3 검사 (i) 이 성립 불가가 된다.
            if (m_fd_fault) begin
                fdotcr_unit_fault_r <= 1'b1;
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
        // v1.8.0e 3a-C4 §35.3 — FDOT32_CR sticky 2종의 인스턴스 횡단 수집.
        // **분리 유지**: m_fd_spec 는 아래 `m_err` 폴딩에 들어가지 않는다.
        m_fd_spec  = mu_fdotcr_special | du_fdotcr_special;
        m_fd_fault = mu_fdotcr_fault   | du_fdotcr_fault;
        for (i = 0; i < NUM_PES; i = i + 1) begin
            m_err = m_err | pe_error[i];
            m_lwr = m_lwr | pe_lower[i];
            m_fd_spec  = m_fd_spec  | pe_fdotcr_spec[i];
            m_fd_fault = m_fd_fault | pe_fdotcr_flt[i];
        end
        // v1.9 §26.5 — fold the bank tag-collision fault into the error
        // flag too, mirroring the any_output_collision precedent
        // immediately below, so existing any_error_flag consumers see it
        // without needing to know about the dedicated port.
        m_err = m_err | bank_tag_collision_error_r;
        // v1.9.2 §22.14b-3 — 같은 이유로 입력단 skid overflow 도 폴딩한다.
        // 전용 포트를 모르는 기존 소비자도 "무언가 버려졌다" 를 본다.
        m_err = m_err | input_skid_overflow_error_r;
        // v1.8.0e 3a-C4 §35.3 pin 1 — FDOT32_CR **unit fault 만** 폴딩한다.
        // `fdotcr_special_status` (정상 데이터 이벤트) 는 여기 **절대**
        // 들어오지 않는다: 이 블록은 순수 OR-reduce 라 한 번 섞이면
        // 되돌릴 수 없고, SDK audit 이 §27.7a.3 검사 (i) 에서 special
        // operand 를 의도적으로 투입하는 것 자체가 매번 cluster 전역
        // error 를 올리게 된다.
        m_err = m_err | fdotcr_unit_fault_r;
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
    assign input_skid_overflow_error = input_skid_overflow_error_r; // v1.9.2 §22.14b-3
    // v1.8.0e 3a-C4 §27.7a.3/§35.3 — FDOT32_CR 상태 2종.
    // `fdotcr_special_status` 는 MU 유닛의 per-op latch 를 **조합적으로
    // 그대로** 낸다 (승격 금지 — op 단위 귀속이 §27.7a.3 의 요구이고,
    // reset-clearable 로 만들면 audit 이 어느 op 의 sticky 인지 잃는다).
    // 위 `m_err` 블록에 이 신호가 없다는 것이 pin 이다 — 음성 회귀
    // 테스트가 그 부재를 감시한다.
    assign fdotcr_special_status   = m_fd_spec;
    assign fdotcr_unit_fault_error = fdotcr_unit_fault_r;
    // v1.6.6 §22.14 / v1.9.2 §22.14b-3 — Cluster back-pressure.
    //   출력단 3항 = AND-reduce over MU/DU/L-PE ready ("결과를 낼 자리가
    //   있는가"). v1.6.6 은 여기서 끝났고, 그래서 이 신호는 "지금 명령을
    //   받을 수 있는가" 를 **뜻한 적이 없었다** (§22.14b-1).
    //   입력단 1항 = `!skid_valid` ("보류 자리가 비어 있는가"). 이 항이
    //   붙어야 비로소 "지금 명령을 받아도 **소실되지 않는다**" 가 된다.
    //
    // 계약은 여전히 observe-only 다 (§22.14b-2: 강제할 소비자가 0건이므로
    // enforced stall 로 바꿔도 손실을 1건도 줄이지 못한다). 다만 이제
    // 0 을 무시하고 주입하면 `input_skid_overflow_error` 가 **소리를 낸다**
    // — 관측 가능한 계약이 됐다.
    generate
        if (NUM_PES > 0) begin : g_ready_agg
            integer pr_i;
            reg     pe_ready_and;
            always @(*) begin
                pe_ready_and = 1'b1;
                for (pr_i = 0; pr_i < NUM_PES; pr_i = pr_i + 1)
                    pe_ready_and = pe_ready_and & pe_ready_lpe[pr_i];
            end
            assign cluster_ready = mu_pe_ready & du_pe_ready & pe_ready_and
                                 & ~skid_valid;
        end
    endgenerate

endmodule
