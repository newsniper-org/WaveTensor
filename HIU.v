// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

`include "attributes.vh"

module HIU #(
    parameter ADDR_WIDTH = 64,
    parameter MAX_REGIONS = 16,
    parameter DATA_WIDTH = 32,
    parameter TLB_ENTRIES = 16,
    parameter NUM_PARTITIONS = 4,  // Partitioned TLB size (for cache attack resistance)
    parameter CHACHA_ROUNDS = 20,  // XChaCha20 rounds for masking
    parameter DUMMY_CYCLES = 8     // Constant-time dummy delay cycles
) (
    input clk,
    input rst,
    input [ADDR_WIDTH-1:0] virt_addr,
    input dma_req,
    input [DATA_WIDTH-1:0] dma_data_in,
    input [1:0] interface_type,
    input ats_req,
    input pri_req,
    input [ADDR_WIDTH-1:0] shadow_write_start,
    input [ADDR_WIDTH-1:0] shadow_write_end,
    input shadow_write_en,
    input [3:0] shadow_index,
    input context_switch,  // Signal for flush-on-context-switch
    input [1:0] partition_id,  // [1:0] for NUM_PARTITIONS=4
    input [191:0] chacha_nonce,  // 192-bit nonce for XChaCha20
    input [255:0] chacha_key,    // 256-bit key for XChaCha20
    output reg [ADDR_WIDTH-1:0] phys_addr,
    output reg [DATA_WIDTH-1:0] dma_data_out,
    output reg dma_ack,
    output reg access_granted,
    output reg ats_resp,
    output reg pri_resp,

    // ---- TRNG outputs -----------------------------------------------------
    // Phase 1: 8-bit raw debiased entropy stream + valid strobe.
    // Phase 3: 64-bit conditioned word + valid strobe + health flag.
    // The 64-bit `rng_word` is the canonical OPREF.src_kind=2 source consumed
    // by Pod/Cluster bank routing.
    output [7:0]  rng_raw,
    output        rng_raw_valid,
    output [63:0] rng_word,
    output        rng_word_valid,
    output        trng_unhealthy
);

// Partitioned TLB and Shadow regions (unchanged)
reg [ADDR_WIDTH-1:0] partitioned_tlb_virt [0:NUM_PARTITIONS-1][0:TLB_ENTRIES-1];
reg [ADDR_WIDTH-1:0] partitioned_tlb_phys [0:NUM_PARTITIONS-1][0:TLB_ENTRIES-1];
reg partitioned_tlb_valid [0:NUM_PARTITIONS-1][0:TLB_ENTRIES-1];

reg [ADDR_WIDTH-1:0] shadow_regions_start [0:MAX_REGIONS-1];
reg [ADDR_WIDTH-1:0] shadow_regions_end [0:MAX_REGIONS-1];
reg shadow_valid [0:MAX_REGIONS-1];

// XChaCha20 state
reg [31:0] chacha_state [0:15];  // Current working state
reg [31:0] initial_state [0:15]; // Initial state for final add
reg [31:0] chacha_stream [0:15]; // Keystream
reg [ADDR_WIDTH-1:0] masked_phys_addr;
reg [255:0] subkey;  // HChaCha20-derived subkey (256 bits)

// Internal signals
wire internal_dma_ack;

// dma_req 저장 reg (dma_req 펄스 지속)
reg dma_req_pending;

// DMA Engine 수정: .dma_req(dma_req_pending)
dma_engine #(
    .DATA_WIDTH(DATA_WIDTH)
) dma_inst (
    .clk(clk),
    .rst(rst),
    .dma_req(dma_req_pending),  // 수정: pending 사용
    .dma_data_in(dma_data_in),
    .phys_addr(masked_phys_addr),
    .access_granted(access_granted),
    .dma_ack(internal_dma_ack),
    .dma_data_out(dma_data_out)
);

// FSM states (added HChaCha20 states)
localparam IDLE = 4'b0000,
           TRANSLATE = 4'b0001,
           DMA_EXEC = 4'b0010,
           ATS_QUERY = 4'b0011,
           PRI_REQUEST = 4'b0100,
           GRANT_ACCESS = 4'b0101,
           SHADOW_UPDATE = 4'b0110,
           DUMMY_DELAY = 4'b0111,
           FLUSH_TLB = 4'b1000,
           CHACHA_H_INIT = 4'b1001,  // HChaCha20 initialization
           CHACHA_H_MASK = 4'b1010,  // HChaCha20 rounds
           CHACHA_INIT = 4'b1011,    // ChaCha20 initialization with subkey
           CHACHA_MASK = 4'b1100,  // ChaCha20 rounds
           CHACHA_FINAL = 4'b1101;    

reg [3:0] state;
reg [4:0] dummy_counter;
reg [4:0] round_counter;

integer p, i, j, k, m;

reg dma_ack_staged;

always @(*) begin
    dma_ack_staged = internal_dma_ack;
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= IDLE;
        access_granted <= 0;
        ats_resp <= 0;
        pri_resp <= 0;
        dummy_counter <= 0;
        round_counter <= 0;
        dma_ack <= 0;
        subkey <= 0;
        dma_req_pending <= 0;
        for (p = 0; p < NUM_PARTITIONS; p = p + 1) begin
            for (i = 0; i < TLB_ENTRIES; i = i + 1) begin
                partitioned_tlb_valid[p][i] <= 0;
            end
        end
        for (i = 0; i < MAX_REGIONS; i = i + 1) begin
            shadow_valid[i] <= 0;
        end
    end else begin
        if (dma_req && (state == IDLE)) dma_req_pending <= 1;  // dma_req 캡처 강화 (IDLE에서만, 하지만 dma_req 입력 즉시)
        if (context_switch) state <= FLUSH_TLB;
        case (state)
            IDLE: begin
                if (shadow_write_en) state <= SHADOW_UPDATE;
                else if (dma_req_pending) state <= TRANSLATE;
                else if (ats_req) state <= ATS_QUERY;
                else if (pri_req) state <= PRI_REQUEST;
            end
            SHADOW_UPDATE: begin
                if ({1'b0, shadow_index} < 5'd16) begin
                    shadow_regions_start[shadow_index] <= shadow_write_start;
                    shadow_regions_end[shadow_index] <= shadow_write_end;
                    shadow_valid[shadow_index] <= 1;
                end
                state <= IDLE;
            end
            TRANSLATE: begin
                access_granted <= 0;
                for (j = 0; j < TLB_ENTRIES; j = j + 1) begin
                    if (partitioned_tlb_valid[partition_id][j] && (virt_addr == partitioned_tlb_virt[partition_id][j])) begin
                        phys_addr <= partitioned_tlb_phys[partition_id][j];
                        access_granted <= 1;
                    end
                end
                dummy_counter <= 0;
                if (!access_granted) begin
                    for (k = 0; k < MAX_REGIONS; k = k + 1) begin
                        if (shadow_valid[k] && (virt_addr >= shadow_regions_start[k]) && (virt_addr <= shadow_regions_end[k])) begin
                            phys_addr <= virt_addr;
                            access_granted <= 1;
                        end
                    end
                end
                state <= DUMMY_DELAY;  // Constant-time dummy always
            end
            DUMMY_DELAY: begin
                if (dummy_counter == DUMMY_CYCLES - 1) begin
                    state <= CHACHA_H_INIT;
                end
                dummy_counter <= dummy_counter + 1;
            end
            CHACHA_H_INIT: begin  // HChaCha20 initialization (subkey derivation)
                // Initial state for HChaCha20: constants + key + nonce[127:0] (first 16 bytes, 128 bits)
                initial_state[0] <= 32'h61707865;
                initial_state[1] <= 32'h3320646e;
                initial_state[2] <= 32'h79622d32;
                initial_state[3] <= 32'h6b206574;
                initial_state[4] <= chacha_key[31:0];
                initial_state[5] <= chacha_key[63:32];
                initial_state[6] <= chacha_key[95:64];
                initial_state[7] <= chacha_key[127:96];
                initial_state[8] <= chacha_key[159:128];
                initial_state[9] <= chacha_key[191:160];
                initial_state[10] <= chacha_key[223:192];
                initial_state[11] <= chacha_key[255:224];
                initial_state[12] <= chacha_nonce[31:0];   // nonce[0:3] bytes
                initial_state[13] <= chacha_nonce[63:32];  // nonce[4:7]
                initial_state[14] <= chacha_nonce[95:64];  // nonce[8:11]
                initial_state[15] <= chacha_nonce[127:96]; // nonce[12:15]
                // Copy to working state
                for (m = 0; m < 16; m = m + 1) begin
                    chacha_state[m] <= initial_state[m];
                end
                round_counter <= 0;
                state <= CHACHA_H_MASK;
            end
            CHACHA_H_MASK: begin  // HChaCha20 rounds
                if (round_counter < CHACHA_ROUNDS / 2) begin
                    {chacha_state[0], chacha_state[4], chacha_state[8], chacha_state[12]} <= chacha_qr_func(0, 4, 8, 12);
                    {chacha_state[1], chacha_state[5], chacha_state[9], chacha_state[13]} <= chacha_qr_func(1, 5, 9, 13);
                    {chacha_state[2], chacha_state[6], chacha_state[10], chacha_state[14]} <= chacha_qr_func(2, 6, 10, 14);
                    {chacha_state[3], chacha_state[7], chacha_state[11], chacha_state[15]} <= chacha_qr_func(3, 7, 11, 15);
                    {chacha_state[0], chacha_state[5], chacha_state[10], chacha_state[15]} <= chacha_qr_func(0, 5, 10, 15);
                    {chacha_state[1], chacha_state[6], chacha_state[11], chacha_state[12]} <= chacha_qr_func(1, 6, 11, 12);
                    {chacha_state[2], chacha_state[7], chacha_state[8], chacha_state[13]} <= chacha_qr_func(2, 7, 8, 13);
                    {chacha_state[3], chacha_state[4], chacha_state[9], chacha_state[14]} <= chacha_qr_func(3, 4, 9, 14);
                    round_counter <= round_counter + 1;
                end else begin
                    // Extract subkey: state[0-3] + state[12-15]
                    subkey[31:0] <= chacha_state[0];
                    subkey[63:32] <= chacha_state[1];
                    subkey[95:64] <= chacha_state[2];
                    subkey[127:96] <= chacha_state[3];
                    subkey[159:128] <= chacha_state[12];
                    subkey[191:160] <= chacha_state[13];
                    subkey[223:192] <= chacha_state[14];
                    subkey[255:224] <= chacha_state[15];
                    state <= CHACHA_INIT;  // Proceed to ChaCha20 with subkey
                end
            end
            CHACHA_INIT: begin  // ChaCha20 initialization with subkey
                // Initial state: constants + subkey + counter=0 + nonce[16:23] (last 8 bytes) with 0 prefix
                initial_state[0] <= 32'h61707865;
                initial_state[1] <= 32'h3320646e;
                initial_state[2] <= 32'h79622d32;
                initial_state[3] <= 32'h6b206574;
                initial_state[4] <= subkey[31:0];
                initial_state[5] <= subkey[63:32];
                initial_state[6] <= subkey[95:64];
                initial_state[7] <= subkey[127:96];
                initial_state[8] <= subkey[159:128];
                initial_state[9] <= subkey[191:160];
                initial_state[10] <= subkey[223:192];
                initial_state[11] <= subkey[255:224];
                initial_state[12] <= 32'h00000000;  // Counter 0
                initial_state[13] <= chacha_nonce[159:128];  // nonce[16:19]
                initial_state[14] <= chacha_nonce[191:160];  // nonce[20:23]
                initial_state[15] <= 32'h00000000;  // Padding for 96-bit nonce
                // Copy to working state
                for (m = 0; m < 16; m = m + 1) begin
                    chacha_state[m] <= initial_state[m];
                end
                round_counter <= 0;
                state <= CHACHA_MASK;
            end
            CHACHA_MASK: begin  // ChaCha20 rounds
                if (round_counter < CHACHA_ROUNDS / 2) begin
                    {chacha_state[0], chacha_state[4], chacha_state[8], chacha_state[12]} <= chacha_qr_func(0, 4, 8, 12);
                    {chacha_state[1], chacha_state[5], chacha_state[9], chacha_state[13]} <= chacha_qr_func(1, 5, 9, 13);
                    {chacha_state[2], chacha_state[6], chacha_state[10], chacha_state[14]} <= chacha_qr_func(2, 6, 10, 14);
                    {chacha_state[3], chacha_state[7], chacha_state[11], chacha_state[15]} <= chacha_qr_func(3, 7, 11, 15);
                    {chacha_state[0], chacha_state[5], chacha_state[10], chacha_state[15]} <= chacha_qr_func(0, 5, 10, 15);
                    {chacha_state[1], chacha_state[6], chacha_state[11], chacha_state[12]} <= chacha_qr_func(1, 6, 11, 12);
                    {chacha_state[2], chacha_state[7], chacha_state[8], chacha_state[13]} <= chacha_qr_func(2, 7, 8, 13);
                    {chacha_state[3], chacha_state[4], chacha_state[9], chacha_state[14]} <= chacha_qr_func(3, 4, 9, 14);
                    round_counter <= round_counter + 1;
                end else begin
                    state <= CHACHA_FINAL;
                end
            end
            CHACHA_FINAL: begin
                // Generate keystream: chacha_state + initial_state
                for (m = 0; m < 16; m = m + 1) begin
                    chacha_stream[m] <= chacha_state[m] + initial_state[m];
                end
                masked_phys_addr <= phys_addr ^ {
                    chacha_state[1] + initial_state[1],
                    chacha_state[0] + initial_state[0]
                };  // 64-bit mask example
                state <= DMA_EXEC;
            end
            DMA_EXEC: begin
                dma_ack <= dma_ack_staged;
                state <= GRANT_ACCESS;
            end
            ATS_QUERY: begin
                ats_resp <= 1;
                state <= IDLE;
            end
            PRI_REQUEST: begin
                pri_resp <= 1;
                state <= IDLE;
            end
            GRANT_ACCESS: begin
                dma_ack <= 0;
                dma_req_pending <= 0; // 요청 처리가 끝났으므로 pending 비트 클리어
                access_granted <= 0; // 다음 요청을 위해 접근 권한 플래그 초기화 필수
                state <= IDLE;
            end
            FLUSH_TLB: begin
                for (p = 0; p < NUM_PARTITIONS; p = p + 1) begin
                    for (i = 0; i < TLB_ENTRIES; i = i + 1) begin
                        partitioned_tlb_valid[p][i] <= 0;
                    end
                end
                for (i = 0; i < MAX_REGIONS; i = i + 1) begin
                    shadow_valid[i] <= 0;
                end
                state <= IDLE;
            end
            default: state <= IDLE;
        endcase
    end
end

// chacha_qr task (quarter round)
// CHACHA_MASK 상태 내 최적화 (function 사용)
function [127:0] chacha_qr_func;  // 반환: xa, xb, xc, xd (32-bit x 4)
    input [3:0] a, b, c, d;
    reg [31:0] xa, xb, xc, xd;
    begin
        xa = chacha_state[a] + chacha_state[b];
        xd = (chacha_state[d] ^ xa) << 16 | (chacha_state[d] ^ xa) >> 16;
        xc = chacha_state[c] + xd;
        xb = (chacha_state[b] ^ xc) << 12 | (chacha_state[b] ^ xc) >> 20;
        xa = xa + xb;
        xd = (xd ^ xa) << 8 | (xd ^ xa) >> 24;
        xc = xc + xd;
        xb = (xb ^ xc) << 7 | (xb ^ xc) >> 25;
        chacha_qr_func = {xa, xb, xc, xd};  // 패킹 반환
    end
endfunction

// =============================================================================
// TRNG Phase 1 — 8 free-running ring oscillators, sampled by clk, with
// von-Neumann debiasing per RO.
//
// `dont_touch` + `keep` attributes prevent Vivado from collapsing the
// inverter chains away. In simulation the ROs are modeled by the system
// clock + a per-RO LFSR-style perturbation so cocotb can exercise the
// debias and downstream paths deterministically (see ifdef VERILATOR).
// In synthesis (FPGA) the inverter chains are placed; the XDC must add:
//     set_property DONT_TOUCH true [get_cells -hier u_trng/ro*_chain]
//     set_false_path -through [get_pins -hier u_trng/ro*_inv*]
//
// Phase 1 emits a debiased bit per RO whenever a (01) or (10) sample pair
// arrives; (00)/(11) pairs are discarded (von Neumann). 8 ROs run in
// parallel — average 4 bits/cycle of debiased entropy, but pulses are
// bursty per RO. We accumulate into an 8-bit shift register and assert
// `rng_raw_valid` whenever the register has been refreshed since last read.
// =============================================================================

localparam TRNG_NRO = 8;

// ---- RO models ------------------------------------------------------------
//
// Synthesis path: 3-stage inverter loop per RO. The first inverter takes
// the loop output (XOR'd with rst so the loop kicks off after rst de-asserts)
// and the third drives `ro_out`. Vivado must keep all of these.
//
// Simulation path: ifdef VERILATOR uses an alternative LFSR-derived sample
// because Verilator cannot model combinational feedback safely.

`WT_KEEP `WT_DONT_TOUCH wire [TRNG_NRO-1:0] ro_out_w;
`WT_KEEP `WT_DONT_TOUCH reg  [TRNG_NRO-1:0] ro_lfsr_q;

`ifdef VERILATOR
// Simulation-only entropy proxy: per-RO LFSR. NOT cryptographic.
always @(posedge clk or posedge rst) begin
    if (rst) begin
        ro_lfsr_q <= 8'h5A;  // arbitrary nonzero seed
    end else begin
        // Galois LFSR with polynomial x^8 + x^6 + x^5 + x^4 + 1 (0xB8).
        ro_lfsr_q <= {ro_lfsr_q[6:0], ro_lfsr_q[7]} ^
                     ({8{ro_lfsr_q[7]}} & 8'h2D);
    end
end
assign ro_out_w = ro_lfsr_q;
`else
// Synthesis path: per-RO 3-stage inverter chain. Each chain has its own
// `keep` so Vivado does not merge them. The first inverter is `~(stage3 ^ rst)`
// to prevent the loop from latching to a stable Z-state on power-up.
genvar gri;
generate
    for (gri = 0; gri < TRNG_NRO; gri = gri + 1) begin : g_ro
        `WT_KEEP `WT_DONT_TOUCH wire ro_s1, ro_s2, ro_s3;
        assign ro_s1 = ~(ro_s3 ^ rst);
        assign ro_s2 = ~ro_s1;
        assign ro_s3 = ~ro_s2;
        assign ro_out_w[gri] = ro_s3;
    end
endgenerate
always @(posedge clk or posedge rst) begin
    if (rst) ro_lfsr_q <= 8'h0;
    // ro_lfsr_q is unused in synthesis path; keep declared so the same
    // always block exists in both compile flows.
end
`endif

// ---- Per-RO double-flop sampler (CDC) -------------------------------------
reg [TRNG_NRO-1:0] ro_meta_q, ro_sync_q, ro_prev_q;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        ro_meta_q <= {TRNG_NRO{1'b0}};
        ro_sync_q <= {TRNG_NRO{1'b0}};
        ro_prev_q <= {TRNG_NRO{1'b0}};
    end else begin
        ro_meta_q <= ro_out_w;
        ro_sync_q <= ro_meta_q;
        ro_prev_q <= ro_sync_q;
    end
end

// ---- Von Neumann debias per RO --------------------------------------------
// Pair = (ro_prev_q[i], ro_sync_q[i])
//   01 -> emit 1
//   10 -> emit 0
//   00/11 -> discard (no emit)
reg [TRNG_NRO-1:0] vn_emit_w, vn_bit_w;
integer kvn;
always @(*) begin
    vn_emit_w = {TRNG_NRO{1'b0}};
    vn_bit_w  = {TRNG_NRO{1'b0}};
    for (kvn = 0; kvn < TRNG_NRO; kvn = kvn + 1) begin
        case ({ro_prev_q[kvn], ro_sync_q[kvn]})
            2'b01: begin vn_emit_w[kvn] = 1'b1; vn_bit_w[kvn] = 1'b1; end
            2'b10: begin vn_emit_w[kvn] = 1'b1; vn_bit_w[kvn] = 1'b0; end
            default: begin vn_emit_w[kvn] = 1'b0; vn_bit_w[kvn] = 1'b0; end
        endcase
    end
end

// ---- 8-bit accumulation shift register ------------------------------------
reg [7:0] rng_acc_q;
reg [3:0] rng_acc_count_q;  // 0..8
reg       rng_raw_valid_q;
reg [7:0] rng_raw_q;

integer kac;
reg [7:0] acc_next;
reg [3:0] cnt_next;

always @(*) begin
    acc_next = rng_acc_q;
    cnt_next = rng_acc_count_q;
    for (kac = 0; kac < TRNG_NRO; kac = kac + 1) begin
        if (vn_emit_w[kac] && cnt_next < 4'd8) begin
            acc_next = {acc_next[6:0], vn_bit_w[kac]};
            cnt_next = cnt_next + 4'd1;
        end
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rng_acc_q       <= 8'h0;
        rng_acc_count_q <= 4'd0;
        rng_raw_q       <= 8'h0;
        rng_raw_valid_q <= 1'b0;
    end else begin
        rng_raw_valid_q <= 1'b0;
        if (cnt_next >= 4'd8) begin
            // Byte ready — present and reset the accumulator.
            rng_raw_q       <= acc_next;
            rng_raw_valid_q <= 1'b1;
            rng_acc_q       <= 8'h0;
            rng_acc_count_q <= 4'd0;
        end else begin
            rng_acc_q       <= acc_next;
            rng_acc_count_q <= cnt_next;
        end
    end
end

assign rng_raw       = rng_raw_q;
assign rng_raw_valid = rng_raw_valid_q;

// =============================================================================
// TRNG Phase 3 — SP800-90B health check + 64-bit `rng_word` conditioning.
//
// Health check (continuous): RCT (Repetition Count) + APT (Adaptive
// Proportion). On failure `trng_unhealthy` latches high until reset; downstream
// consumers MUST treat outputs as suspect once raised.
//
// Conditioning (this phase): pack 8 successive debiased bytes into a 64-bit
// word and present via `rng_word` + 1-cycle `rng_word_valid` pulse. This is
// NOT a SP800-90A approved conditioner — it preserves the per-bit min-entropy
// of the von Neumann output (~0.5 H/bit) but provides no PRF expansion.
// Future Phase 3.5 will replace the byte-pack stage with a ChaCha20-keyed
// conditioner that consumes the raw bytes as a periodic key reseed.
// =============================================================================

// ---- Health check: Repetition Count Test (NIST SP800-90B 4.4.1) ----------
// Threshold: any single byte value repeating > 41 times in a row trips RCT.
// (C = 1 + ceil(20 / 0.5) = 41 for H_min ≈ 0.5 bit/bit raw entropy.)
localparam [5:0] RCT_THRESHOLD = 6'd41;

reg [7:0]  rct_last_q;
reg [5:0]  rct_count_q;
reg        rct_fail_q;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rct_last_q  <= 8'h0;
        rct_count_q <= 6'd0;
        rct_fail_q  <= 1'b0;
    end else if (rng_raw_valid_q) begin
        if (rng_raw_q == rct_last_q) begin
            if (rct_count_q < RCT_THRESHOLD) begin
                rct_count_q <= rct_count_q + 6'd1;
            end else begin
                rct_fail_q <= 1'b1;
            end
        end else begin
            rct_last_q  <= rng_raw_q;
            rct_count_q <= 6'd1;
        end
    end
end

// ---- Adaptive Proportion Test (NIST SP800-90B 4.4.2) ----------------------
// Window W = 64 samples; threshold A = 51 occurrences of the same value
// within the window (corresponds to alpha = 2^-20 for H_min = 0.5).
// Implemented as a sliding count: track first-byte-of-window + occurrences.
localparam [6:0] APT_WINDOW    = 7'd64;
localparam [6:0] APT_THRESHOLD = 7'd51;

reg [7:0]  apt_target_q;
reg [6:0]  apt_count_q;
reg [6:0]  apt_pos_q;
reg        apt_fail_q;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        apt_target_q <= 8'h0;
        apt_count_q  <= 7'd0;
        apt_pos_q    <= 7'd0;
        apt_fail_q   <= 1'b0;
    end else if (rng_raw_valid_q) begin
        if (apt_pos_q == 7'd0) begin
            // First byte of new window — adopt as target.
            apt_target_q <= rng_raw_q;
            apt_count_q  <= 7'd1;
            apt_pos_q    <= 7'd1;
        end else begin
            if (rng_raw_q == apt_target_q) begin
                if (apt_count_q < APT_THRESHOLD) begin
                    apt_count_q <= apt_count_q + 7'd1;
                end else begin
                    apt_fail_q <= 1'b1;
                end
            end
            if (apt_pos_q + 7'd1 >= APT_WINDOW) begin
                apt_pos_q <= 7'd0;        // window rollover
            end else begin
                apt_pos_q <= apt_pos_q + 7'd1;
            end
        end
    end
end

assign trng_unhealthy = rct_fail_q | apt_fail_q;

// ---- 64-bit conditioning: pack 8 bytes into one rng_word -----------------
reg [63:0] rng_word_q;
reg [3:0]  rng_word_byte_count_q;   // 0..8
reg        rng_word_valid_q;
reg [63:0] rng_word_acc_q;          // shift register

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rng_word_q            <= 64'h0;
        rng_word_acc_q        <= 64'h0;
        rng_word_byte_count_q <= 4'd0;
        rng_word_valid_q      <= 1'b0;
    end else begin
        rng_word_valid_q <= 1'b0;
        if (rng_raw_valid_q && !trng_unhealthy) begin
            if (rng_word_byte_count_q == 4'd7) begin
                rng_word_q            <= {rng_word_acc_q[55:0], rng_raw_q};
                rng_word_valid_q      <= 1'b1;
                rng_word_acc_q        <= 64'h0;
                rng_word_byte_count_q <= 4'd0;
            end else begin
                rng_word_acc_q        <= {rng_word_acc_q[55:0], rng_raw_q};
                rng_word_byte_count_q <= rng_word_byte_count_q + 4'd1;
            end
        end
    end
end

assign rng_word       = rng_word_q;
assign rng_word_valid = rng_word_valid_q;

endmodule

// dma_engine (unchanged)
module dma_engine #(
    parameter DATA_WIDTH = 32
) (
    input clk,
    input rst,
    input dma_req,
    input [DATA_WIDTH-1:0] dma_data_in,
    input [63:0] phys_addr,
    input access_granted,
    output reg dma_ack,
    output reg [DATA_WIDTH-1:0] dma_data_out
);

    reg [DATA_WIDTH-1:0] dma_buffer;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dma_ack <= 0;
            dma_data_out <= 0;
            dma_buffer <= 0;
        end else if (dma_req && access_granted) begin
            dma_buffer <= dma_data_in;
            dma_data_out <= dma_buffer ^ phys_addr[DATA_WIDTH-1:0];
            dma_ack <= 1;
        end else begin
            dma_ack <= 0;
        end
    end

endmodule