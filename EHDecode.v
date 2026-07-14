// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

// =============================================================================
// EHDecode.v — Cluster-shared instruction-decode front-end.
//
// Pipelined chain walk: ONE EH per cycle, up to MAX_EH slots. Termination
// is **sentinel-driven** — the walk exits the moment an EH whose `next_hdr`
// is EH_END (0x0) is processed, or the moment `stg_expect` itself is
// EH_END on entry (empty chain). The `stg_index == MAX_EH-1` check is a
// **safety cap** against malformed instructions with no sentinel: not the
// primary termination condition.
//
// WT64v1 v1.3 (2026-07-14) amendment moves EH count from a spec constraint
// to a hardware-sizing hint. Software emits any number of EHs it needs; the
// bus width (INSTR_WIDTH = 32 + MAX_EH*96) is the only hard cap. See
// `wt64v1_spec.md` §16 for details.
//
// Resource win: instead of MAX_EH cascaded sets of 16:1 muxes (one per
// slot, each reading 3 words from an INSTR_WORDS-word array, all in series
// in one cycle), we instantiate ONE set of muxes and reuse it across
// cycles. The per-slot offset is held in a register, advances on each
// clock edge, and drives the same physical mux.
//
// Pipeline (with `instruction` and `input_*` held stable from in_valid until
// done; the parent (Cluster/ISA_Decoder) is responsible for not changing
// inputs mid-walk):
//
//   cycle T   : in_valid=1, instruction valid. Inputs latched into
//               instr_latched / tag_latched / payload_latched. Pipeline
//               kicks on next edge with stg_index=0.
//   cycle T+1 : SLOT 0 decoded from iw_c[stg_off]; accumulators update.
//               stg_off / stg_expect advance. If cur_next == EH_END:
//               done_d1 latches immediately (early sentinel exit).
//   cycle T+k : SLOT k-1 decoded; done_d1 latches when sentinel reached
//               or safety cap (k == MAX_EH) hits.
//   cycle T+k+1 : dec_* registers update from accumulator + legality check.
//
// v1.3 also adds multi-SUBSCRIPT accumulation (§16): up to 2 SUBSCRIPT
// EHs concatenate low → hi in `acc_subscript[95:0]`, exposing 8 axes for
// 5+ axes EINSUM signatures. Third SUBSCRIPT raises chain_err.
//
// External interface: ISA_Decoder.v stays as a thin wrapper. Tests use
// `RisingEdge(dec_valid)` polling, not fixed cycle waits — so early
// sentinel exit is transparent.
// =============================================================================

/* verilator lint_off UNUSEDSIGNAL */

module EHDecode #(
    parameter ADDR_WIDTH  = 64,
    parameter TAG_WIDTH   = 80,
    parameter MAX_EH      = 4,
    parameter INSTR_WIDTH = 32 + MAX_EH*96
) (
    input                       clk,
    input                       rst,
    input                       in_valid,
    input  [INSTR_WIDTH-1:0]    instruction,
    input  [TAG_WIDTH-1:0]      input_tag,
    input  [ADDR_WIDTH-1:0]     input_payload,
    input  [ADDR_WIDTH-1:0]     input_payload_b,
    input                       input_payload_b_valid,

    // ---- Stage-1 registered dec_* bus (consumed by PE_Core) ----
    output reg                   dec_valid,
    output reg [7:0]             dec_opcode,
    output reg                   dec_decode_error,
    output reg                   dec_tag_match,
    output reg [TAG_WIDTH-1:0]   dec_forwarded_tag,
    output reg [TAG_WIDTH-1:0]   dec_wave_advanced_tag,
    output reg [ADDR_WIDTH-1:0]  dec_input_payload,
    output reg [ADDR_WIDTH-1:0]  dec_input_payload_b,
    output reg                   dec_input_payload_b_valid,
    output reg [ADDR_WIDTH-1:0]  dec_eff_b_value,
    output reg [15:0]            dec_eff_imm16,
    output reg [7:0]             dec_eff_dim_sizes,
    output reg [3:0]             dec_eff_opref_kind,
    output reg [31:0]            dec_eff_mem_offset,
    output reg [47:0]            dec_eff_subscript,
    // v1.3: second SUBSCRIPT EH body (axes 4-7 for {A,B,O}). Zero when
    // only one SUBSCRIPT EH was emitted (backward compatible w/ v1.2 sigs).
    output reg [47:0]            dec_eff_subscript_hi,
    output reg [7:0]             dec_eff_output_port_id,
    output reg [7:0]             dec_eff_precision,
    output reg [31:0]            dec_wave_number,
    output reg [15:0]            dec_thread_id,
    output reg [15:0]            dec_port_context_id,

    // ---- Combinational OPREF reflection (same-cycle as `instruction`) ----
    output [3:0]                 opref_src_kind_out,
    output [3:0]                 opref_port_id_out,
    output [7:0]                 opref_noc_route_out
);

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------
    localparam INSTR_WORDS_REAL = INSTR_WIDTH/32;
    // INSTR_WORDS pads iw_c[] to at least the safe upper bound so the mux
    // never goes out of range regardless of MAX_EH. Kept at 32 to cover
    // MAX_EH up to ~10 (32 = 1 + 10*3 + 1 slack).
    localparam INSTR_WORDS      = (INSTR_WORDS_REAL > 32) ? INSTR_WORDS_REAL : 32;
    // v1.3: parametric chain-walk state widths. stg_off addresses iw_c[];
    // stg_index counts slots up to the MAX_EH safety cap. Minimum widths
    // preserve backward compat when MAX_EH=4 ($clog2(32)=5, $clog2(5)=3).
    localparam OFF_W  = $clog2(INSTR_WORDS);
    localparam IDX_W  = $clog2(MAX_EH + 1);
    localparam [3:0] EH_END        = 4'h0;
    localparam [3:0] EH_PORT       = 4'h1;
    localparam [3:0] EH_IMM16      = 4'h2;
    localparam [3:0] EH_IMM32      = 4'h3;
    localparam [3:0] EH_IMM64      = 4'h4;
    localparam [3:0] EH_MEM        = 4'h5;
    localparam [3:0] EH_SUBSCRIPT  = 4'h6;
    localparam [3:0] EH_OPREF      = 4'h7;
    localparam [3:0] EH_PRECISION  = 4'h8;
    localparam [3:0] EH_NOP_PAD    = 4'hF;

    // -------------------------------------------------------------------------
    // Latch the inputs once in_valid pulses so the chain walk reads stable
    // data even after the upstream changes its drive. Pipeline init happens
    // on the SAME cycle (no separate walk_kick stage) — `cb_*` and SLOT 0's
    // `stg_expect` are sourced directly from the live `instruction` wire,
    // while subsequent slots read from the registered `instr_latched`.
    // -------------------------------------------------------------------------
    reg [INSTR_WIDTH-1:0] instr_latched;
    reg [TAG_WIDTH-1:0]   tag_latched;
    reg [ADDR_WIDTH-1:0]  payload_latched, payload_b_latched;
    reg                   payload_b_valid_latched;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            instr_latched           <= {INSTR_WIDTH{1'b0}};
            tag_latched             <= {TAG_WIDTH{1'b0}};
            payload_latched         <= {ADDR_WIDTH{1'b0}};
            payload_b_latched       <= {ADDR_WIDTH{1'b0}};
            payload_b_valid_latched <= 1'b0;
        end else if (in_valid && !stg_active) begin
            instr_latched           <= instruction;
            tag_latched             <= input_tag;
            payload_latched         <= input_payload;
            payload_b_latched       <= input_payload_b;
            payload_b_valid_latched <= input_payload_b_valid;
        end
    end

    // 16x32 view of the latched instruction. Stays as wires (not LUTRAM) —
    // LUTRAM single-write-port inference would force a 13-cycle serial load
    // that dominates the latency budget. The chain walk's mux-sharing
    // already happens via pipelining (only ONE iw_c[stg_off] read per
    // cycle), regardless of whether iw_c is a wire or a LUTRAM.
    wire [31:0] iw_c [0:INSTR_WORDS-1];
    genvar gci;
    generate
        for (gci = 0; gci < INSTR_WORDS; gci = gci + 1) begin : gen_iw_c
            if (gci < INSTR_WORDS_REAL)
                assign iw_c[gci] = instr_latched[gci*32 +: 32];
            else
                assign iw_c[gci] = 32'h00000000;
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Chain-walk pipeline state — one slot per cycle.
    // v1.3: widths parametric on MAX_EH (was hardcoded 4-bit/3-bit for
    // MAX_EH=4). Termination is sentinel-driven; stg_index is only used
    // as a safety cap against malformed instructions without EH_END.
    // -------------------------------------------------------------------------
    reg [OFF_W-1:0]  stg_off;
    reg [3:0]        stg_expect;
    reg [IDX_W-1:0]  stg_index;
    reg              stg_active;
    reg              stg_chain_err;
    reg              stg_unknown;

    // Accumulated body fields
    reg [15:0] acc_port_body;
    reg [15:0] acc_imm16;
    reg [31:0] acc_imm32;
    reg [63:0] acc_imm64;
    reg [ 3:0] acc_mem_addr_mode;
    reg [11:0] acc_mem_stride;
    reg [31:0] acc_mem_offset;
    // v1.3: widened to hold up to 2 SUBSCRIPT EH bodies (low + hi).
    // Lower 48 bits = first SUBSCRIPT (axes 0-3 for {A,B,O}).
    // Upper 48 bits = second SUBSCRIPT (axes 4-7 for {A,B,O}).
    reg [95:0] acc_subscript;
    reg [1:0]  acc_subscript_slot;  // 0=none seen, 1=one seen, 2=two seen
    reg [ 3:0] acc_opref_src_kind;
    reg [ 3:0] acc_opref_port_id;
    reg [ 7:0] acc_opref_noc_route;
    reg [ 7:0] acc_prec_mode;
    reg [ 7:0] acc_prec_dim;

    // Per-class presence accumulators
    reg acc_any_port, acc_any_imm16, acc_any_imm32, acc_any_imm64;
    reg acc_any_mem,  acc_any_subscript, acc_any_opref, acc_any_precision;

    // Carried base header
    reg [7:0]  cb_opcode;
    reg [3:0]  cb_flags;
    reg [7:0]  cb_reserved;
    reg [7:0]  cb_bh_len;

    // Carried tag fields
    reg [31:0] cb_wave_number;
    reg [15:0] cb_thread_id;
    reg [15:0] cb_port_context_id;
    reg [ 7:0] cb_precision_mode;
    reg [ 7:0] cb_dimension_sizes;

    // Single-stage decoded slot wires (one set, reused every cycle).
    wire [31:0] cur_w0 = iw_c[stg_off];
    wire [31:0] cur_w1 = iw_c[stg_off + {{(OFF_W-1){1'b0}}, 1'b1}];
    wire [31:0] cur_w2 = iw_c[stg_off + {{(OFF_W-2){1'b0}}, 2'd2}];
    wire [3:0]  cur_next   = cur_w0[15:12];
    wire [3:0]  cur_type   = cur_w0[11: 8];
    wire [7:0]  cur_extlen = cur_w0[ 7: 0];

    wire cur_present = stg_active && (stg_expect != EH_END);
    wire cur_chain_err = cur_present
                       && ((cur_type != stg_expect) || (cur_extlen == 8'h00));

    wire is_port_c      = cur_present && !cur_chain_err && (cur_type == EH_PORT);
    wire is_imm16_c     = cur_present && !cur_chain_err && (cur_type == EH_IMM16);
    wire is_imm32_c     = cur_present && !cur_chain_err && (cur_type == EH_IMM32);
    wire is_imm64_c     = cur_present && !cur_chain_err && (cur_type == EH_IMM64);
    wire is_mem_c       = cur_present && !cur_chain_err && (cur_type == EH_MEM);
    wire is_subscript_c = cur_present && !cur_chain_err && (cur_type == EH_SUBSCRIPT);
    wire is_opref_c     = cur_present && !cur_chain_err && (cur_type == EH_OPREF);
    wire is_precision_c = cur_present && !cur_chain_err && (cur_type == EH_PRECISION);
    wire is_nop_c       = cur_present && !cur_chain_err && (cur_type == EH_NOP_PAD);
    wire is_unknown_c   = cur_present && !cur_chain_err
                       && !(is_port_c | is_imm16_c | is_imm32_c | is_imm64_c
                          | is_mem_c  | is_subscript_c | is_opref_c
                          | is_precision_c | is_nop_c);

    reg done_d1;     // signals "dec_* should latch this cycle"

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            stg_off            <= {{(OFF_W-1){1'b0}}, 1'b1};
            stg_expect         <= EH_END;
            stg_index          <= {IDX_W{1'b0}};
            stg_active         <= 1'b0;
            stg_chain_err      <= 1'b0;
            stg_unknown        <= 1'b0;
            acc_port_body      <= 16'h0;
            acc_imm16          <= 16'h0;
            acc_imm32          <= 32'h0;
            acc_imm64          <= 64'h0;
            acc_mem_addr_mode  <= 4'h0;
            acc_mem_stride     <= 12'h0;
            acc_mem_offset     <= 32'h0;
            acc_subscript      <= 96'h0;
            acc_subscript_slot <= 2'd0;
            acc_opref_src_kind <= 4'h0;
            acc_opref_port_id  <= 4'h0;
            acc_opref_noc_route<= 8'h0;
            acc_prec_mode      <= 8'h0;
            acc_prec_dim       <= 8'h0;
            acc_any_port       <= 1'b0;
            acc_any_imm16      <= 1'b0;
            acc_any_imm32      <= 1'b0;
            acc_any_imm64      <= 1'b0;
            acc_any_mem        <= 1'b0;
            acc_any_subscript  <= 1'b0;
            acc_any_opref      <= 1'b0;
            acc_any_precision  <= 1'b0;
            cb_opcode          <= 8'h0;
            cb_flags           <= 4'h0;
            cb_reserved        <= 8'h0;
            cb_bh_len          <= 8'h0;
            cb_wave_number     <= 32'h0;
            cb_thread_id       <= 16'h0;
            cb_port_context_id <= 16'h0;
            cb_precision_mode  <= 8'h0;
            cb_dimension_sizes <= 8'h0;
            done_d1            <= 1'b0;
        end else begin
            done_d1 <= 1'b0;
            if (in_valid && !stg_active) begin
                // Initialize the pipeline DIRECTLY from the live `instruction`
                // wire — saves a cycle of latency vs. requiring a separate
                // walk_kick stage. Subsequent slot reads use the registered
                // instr_latched (this same edge writes it).
                stg_off            <= {{(OFF_W-1){1'b0}}, 1'b1};
                stg_expect         <= instruction[23:20];
                stg_index          <= {IDX_W{1'b0}};
                stg_active         <= 1'b1;
                stg_chain_err      <= 1'b0;
                stg_unknown        <= 1'b0;
                acc_port_body      <= 16'h0;
                acc_imm16          <= 16'h0;
                acc_imm32          <= 32'h0;
                acc_imm64          <= 64'h0;
                acc_mem_addr_mode  <= 4'h0;
                acc_mem_stride     <= 12'h0;
                acc_mem_offset     <= 32'h0;
                acc_subscript      <= 96'h0;
                acc_subscript_slot <= 2'd0;
                acc_opref_src_kind <= 4'h0;
                acc_opref_port_id  <= 4'h0;
                acc_opref_noc_route<= 8'h0;
                acc_prec_mode      <= 8'h0;
                acc_prec_dim       <= 8'h0;
                acc_any_port       <= 1'b0;
                acc_any_imm16      <= 1'b0;
                acc_any_imm32      <= 1'b0;
                acc_any_imm64      <= 1'b0;
                acc_any_mem        <= 1'b0;
                acc_any_subscript  <= 1'b0;
                acc_any_opref      <= 1'b0;
                acc_any_precision  <= 1'b0;
                cb_opcode          <= instruction[31:24];
                cb_flags           <= instruction[19:16];
                cb_reserved        <= instruction[15:8];
                cb_bh_len          <= instruction[7:0];
                cb_wave_number     <= input_tag[79:48];
                cb_thread_id       <= input_tag[47:32];
                cb_port_context_id <= input_tag[31:16];
                cb_precision_mode  <= input_tag[15:8];
                cb_dimension_sizes <= input_tag[7:0];
            end else if (stg_active) begin
                // Process the current slot, then advance.
                if (cur_present) begin
                    if (cur_chain_err) stg_chain_err <= 1'b1;
                    if (is_unknown_c)  stg_unknown   <= 1'b1;
                    if (is_port_c) begin
                        acc_port_body <= cur_w0[31:16];
                        acc_any_port  <= 1'b1;
                    end
                    if (is_imm16_c) begin
                        acc_imm16     <= cur_w0[31:16];
                        acc_any_imm16 <= 1'b1;
                    end
                    if (is_imm32_c) begin
                        acc_imm32     <= cur_w1;
                        acc_any_imm32 <= 1'b1;
                    end
                    if (is_imm64_c) begin
                        acc_imm64     <= {cur_w2, cur_w1};
                        acc_any_imm64 <= 1'b1;
                    end
                    if (is_mem_c) begin
                        acc_mem_addr_mode <= cur_w0[19:16];
                        acc_mem_stride    <= cur_w0[31:20];
                        acc_mem_offset    <= cur_w1;
                        acc_any_mem       <= 1'b1;
                    end
                    if (is_subscript_c) begin
                        // v1.3: multi-SUBSCRIPT accumulation. Up to 2 SUBSCRIPT
                        // EHs concatenate low → hi. Third raises chain_err.
                        if (acc_subscript_slot == 2'd0) begin
                            acc_subscript[47:0]  <= {cur_w1, cur_w0[31:16]};
                            acc_any_subscript    <= 1'b1;
                            acc_subscript_slot   <= 2'd1;
                        end else if (acc_subscript_slot == 2'd1) begin
                            acc_subscript[95:48] <= {cur_w1, cur_w0[31:16]};
                            acc_subscript_slot   <= 2'd2;
                        end else begin
                            stg_chain_err        <= 1'b1;
                        end
                    end
                    if (is_opref_c) begin
                        acc_opref_src_kind  <= cur_w0[19:16];
                        acc_opref_port_id   <= cur_w0[23:20];
                        acc_opref_noc_route <= cur_w0[31:24];
                        acc_any_opref       <= 1'b1;
                    end
                    if (is_precision_c) begin
                        acc_prec_mode     <= cur_w0[23:16];
                        acc_prec_dim      <= cur_w0[31:24];
                        acc_any_precision <= 1'b1;
                    end
                    stg_off    <= stg_off + {{(OFF_W-4){1'b0}}, cur_extlen[3:0]};
                    stg_expect <= cur_next;
                end
                // Termination (v1.3): fixed MAX_EH-cycle walk. The sentinel
                // (EH_END = 0x0) is dynamically enforced by `cur_present`
                // gating — cycles after the sentinel do no work but the
                // pipeline still runs to MAX_EH slots so the downstream
                // pe_active alignment stays deterministic (see Cluster.v's
                // 6-stage pe_active shift register).
                //
                // The user's C-string-style "chain walks until '\0'" analogy
                // is realized as: bus width (MAX_EH*96) is a HARDWARE sizing
                // hint; software emits any count of EHs it needs up to that
                // bus width, and the sentinel logically terminates the chain.
                // Extra pipeline cycles beyond the sentinel are pure no-ops.
                //
                // Bumping MAX_EH also requires bumping the Cluster.v
                // pe_active pipeline depth in lockstep.
                if (stg_index == (MAX_EH[IDX_W-1:0] -
                                  {{(IDX_W-1){1'b0}}, 1'b1})) begin
                    stg_active <= 1'b0;
                    done_d1    <= 1'b1;
                end else begin
                    stg_index <= stg_index + {{(IDX_W-1){1'b0}}, 1'b1};
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Final field derivation + legality (combinational, clocked once via
    // dec_* register update on done_d1).
    // -------------------------------------------------------------------------
    wire f_has_opb       = cb_flags[3];
    wire f_precision_ovr = cb_flags[2];
    wire f_mem           = cb_flags[1];
    wire f_dim_ovr       = cb_flags[0];

    wire [7:0] eff_output_port_id  = acc_port_body[15:8];
    wire [7:0] eff_input_port_mask = acc_port_body[ 7:0];
    wire [7:0] eff_precision       = f_precision_ovr ? acc_prec_mode
                                                     : cb_precision_mode;
    wire [7:0] eff_dim_sizes       = f_dim_ovr ? acc_prec_dim
                                              : cb_dimension_sizes;

    wire [63:0] eff_b_value =
          (acc_any_opref) ? payload_b_latched
        : (acc_any_imm64) ? acc_imm64
        : (acc_any_imm32) ? {32'h0, acc_imm32}
        :                   {48'h0, acc_imm16};

    reg req_port, req_mem, req_subscript, req_opref, req_imm16;
    reg forbid_subscript, forbid_mem, forbid_imm_any, forbid_opref;

    always @(*) begin
        req_port         = 1'b0;
        req_mem          = 1'b0;
        req_subscript    = 1'b0;
        req_opref        = 1'b0;
        req_imm16        = 1'b0;
        forbid_subscript = 1'b0;
        forbid_mem       = 1'b0;
        forbid_imm_any   = 1'b0;
        forbid_opref     = 1'b0;
        case (cb_opcode)
            8'h00: begin
                forbid_subscript = 1'b1; forbid_mem = 1'b1;
                forbid_imm_any   = 1'b1; forbid_opref = 1'b1;
            end
            8'h01, 8'h02, 8'h03: begin
                req_port         = 1'b1;
                forbid_subscript = 1'b1; forbid_mem = 1'b1;
                forbid_imm_any   = 1'b1; forbid_opref = 1'b1;
            end
            8'h04, 8'h05: begin
                req_port      = 1'b1; req_mem = 1'b1;
                forbid_subscript = 1'b1;
                forbid_imm_any   = 1'b1; forbid_opref = 1'b1;
            end
            // ALU binary (IMM XOR OPREF): ADD/SUB/MUL/DIV/MOD/DIVMOD +
            // bitwise binary (AND/OR/XOR/NAND/NOR/XNOR).
            8'h10, 8'h11, 8'h12, 8'h13, 8'h14, 8'h15, 8'h16,
            8'h1C, 8'h1D,
            8'h51, 8'h52, 8'h53: begin
                req_port         = 1'b1;
                forbid_subscript = 1'b1; forbid_mem = 1'b1;
            end
            // Shift / rotate (require IMM16 for the shift amount).
            8'h17, 8'h18, 8'h19, 8'h1A, 8'h1E: begin
                req_port = 1'b1; req_imm16 = 1'b1;
                forbid_subscript = 1'b1; forbid_mem = 1'b1;
                forbid_opref     = 1'b1;
            end
            // Pure unary (no immediate, no operand-ref): NEG / BITREV /
            // NOT / POPCOUNT / CLZ / CTZ.
            8'h1B, 8'h1F,
            8'h50, 8'h54, 8'h55, 8'h56: begin
                req_port         = 1'b1;
                forbid_subscript = 1'b1; forbid_mem = 1'b1;
                forbid_imm_any   = 1'b1; forbid_opref = 1'b1;
            end
            8'h20, 8'h21, 8'h22, 8'h23, 8'h24, 8'h25, 8'h26: begin
                // 0x26 = SPLAT (v1.1 amendment). Same legality shape as
                // other shape ops: PORT required, IMM16 required (holds
                // the scalar in [7:0]), no subscript / mem / opref.
                req_port = 1'b1; req_imm16 = 1'b1;
                forbid_subscript = 1'b1; forbid_mem = 1'b1;
                forbid_opref     = 1'b1;
            end
            8'h30, 8'h31: begin
                req_port = 1'b1; req_opref = 1'b1;
                forbid_subscript = 1'b1; forbid_mem = 1'b1;
                forbid_imm_any   = 1'b1;
            end
            8'h32: begin
                req_port = 1'b1; req_subscript = 1'b1; req_opref = 1'b1;
                forbid_mem = 1'b1; forbid_imm_any = 1'b1;
            end
            8'h40, 8'h41, 8'h42, 8'h43, 8'h44: begin
                req_port         = 1'b1;
                forbid_subscript = 1'b1; forbid_mem = 1'b1;
                forbid_imm_any   = 1'b1; forbid_opref = 1'b1;
            end
            default: begin
                forbid_subscript = 1'b1; forbid_mem = 1'b1;
                forbid_imm_any   = 1'b1; forbid_opref = 1'b1;
            end
        endcase
    end

    wire any_imm = acc_any_imm16 | acc_any_imm32 | acc_any_imm64;

    wire is_alu_binary = (cb_opcode == 8'h10) || (cb_opcode == 8'h11) ||
                         (cb_opcode == 8'h12) || (cb_opcode == 8'h13) ||
                         (cb_opcode == 8'h14) || (cb_opcode == 8'h15) ||
                         (cb_opcode == 8'h16) ||
                         (cb_opcode == 8'h1C) || (cb_opcode == 8'h1D) ||
                         (cb_opcode == 8'h51) || (cb_opcode == 8'h52) ||
                         (cb_opcode == 8'h53);
    wire alu_binary_xor_err = is_alu_binary && (any_imm == acc_any_opref);

    wire missing_eh   = (req_port      && !acc_any_port)
                      | (req_mem       && !acc_any_mem)
                      | (req_subscript && !acc_any_subscript)
                      | (req_opref     && !acc_any_opref)
                      | (req_imm16     && !acc_any_imm16);
    wire forbidden_eh = (forbid_subscript && acc_any_subscript)
                      | (forbid_mem       && acc_any_mem)
                      | (forbid_imm_any   && any_imm)
                      | (forbid_opref     && acc_any_opref);

    wire opcode_supported =
         (cb_opcode == 8'h00) || (cb_opcode == 8'h01) || (cb_opcode == 8'h02) ||
         (cb_opcode == 8'h03) || (cb_opcode == 8'h04) || (cb_opcode == 8'h05) ||
         (cb_opcode == 8'h10) || (cb_opcode == 8'h11) || (cb_opcode == 8'h12) ||
         (cb_opcode == 8'h13) || (cb_opcode == 8'h14) || (cb_opcode == 8'h15) ||
         (cb_opcode == 8'h16) || (cb_opcode == 8'h17) || (cb_opcode == 8'h18) ||
         (cb_opcode == 8'h19) || (cb_opcode == 8'h1A) || (cb_opcode == 8'h1B) ||
         (cb_opcode == 8'h1C) || (cb_opcode == 8'h1D) || (cb_opcode == 8'h1E) ||
         (cb_opcode == 8'h1F) || (cb_opcode == 8'h20) || (cb_opcode == 8'h21) ||
         (cb_opcode == 8'h22) || (cb_opcode == 8'h23) || (cb_opcode == 8'h24) ||
         (cb_opcode == 8'h25) || (cb_opcode == 8'h26) || (cb_opcode == 8'h30) || (cb_opcode == 8'h31) ||
         (cb_opcode == 8'h32) || (cb_opcode == 8'h40) || (cb_opcode == 8'h41) ||
         (cb_opcode == 8'h42) || (cb_opcode == 8'h43) || (cb_opcode == 8'h44) ||
         (cb_opcode == 8'h50) || (cb_opcode == 8'h51) || (cb_opcode == 8'h52) ||
         (cb_opcode == 8'h53) || (cb_opcode == 8'h54) || (cb_opcode == 8'h55) ||
         (cb_opcode == 8'h56);

    wire bh_len_mismatch = (cb_bh_len != {{(8-OFF_W){1'b0}}, stg_off});
    wire reserved_nonzero = (cb_reserved != 8'h00);
    wire prec_flag_without_eh = (f_precision_ovr || f_dim_ovr) && !acc_any_precision;
    wire opb_required_invalid   = f_has_opb && !payload_b_valid_latched;
    // OPREF.src_kind: 0=direct payload_b, 1=NoC bank, 2=TRNG. 3+ rejected.
    wire opref_kind_unsupported = acc_any_opref && (acc_opref_src_kind > 4'h2);

    wire decode_error = stg_chain_err | bh_len_mismatch | reserved_nonzero
                      | stg_unknown   | (!opcode_supported)
                      | missing_eh    | forbidden_eh
                      | alu_binary_xor_err
                      | opb_required_invalid | opref_kind_unsupported
                      | prec_flag_without_eh;

    wire [7:0] pcid_one_hot = 8'h01 << cb_port_context_id[2:0];
    wire tag_match = (cb_opcode != 8'h00)
                  && ((eff_input_port_mask & pcid_one_hot) != 8'h00);

    wire [TAG_WIDTH-1:0] forwarded_tag_c =
        {cb_wave_number, cb_thread_id, 8'h00, eff_output_port_id,
         eff_precision, eff_dim_sizes};
    wire [TAG_WIDTH-1:0] wave_advanced_tag_c =
        {cb_wave_number + 32'd1, cb_thread_id, 8'h00, eff_output_port_id,
         eff_precision, eff_dim_sizes};

    // -------------------------------------------------------------------------
    // dec_* register stage — fires the cycle after SLOT 3 finishes.
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dec_valid                 <= 1'b0;
            dec_decode_error          <= 1'b0;
            dec_tag_match             <= 1'b0;
            dec_opcode                <= 8'h00;
            dec_forwarded_tag         <= {TAG_WIDTH{1'b0}};
            dec_wave_advanced_tag     <= {TAG_WIDTH{1'b0}};
            dec_input_payload         <= {ADDR_WIDTH{1'b0}};
            dec_input_payload_b       <= {ADDR_WIDTH{1'b0}};
            dec_input_payload_b_valid <= 1'b0;
            dec_eff_b_value           <= {ADDR_WIDTH{1'b0}};
            dec_eff_imm16             <= 16'h0;
            dec_eff_dim_sizes         <= 8'h00;
            dec_eff_opref_kind        <= 4'h0;
            dec_eff_mem_offset        <= 32'h0;
            dec_eff_subscript         <= 48'h0;
            dec_eff_subscript_hi      <= 48'h0;
            dec_eff_output_port_id    <= 8'h00;
            dec_eff_precision         <= 8'h00;
            dec_wave_number           <= 32'h0;
            dec_thread_id             <= 16'h0;
            dec_port_context_id       <= 16'h0;
        end else begin
            dec_valid <= done_d1;
            if (done_d1) begin
                dec_decode_error          <= decode_error;
                dec_tag_match             <= tag_match;
                dec_opcode                <= cb_opcode;
                dec_forwarded_tag         <= forwarded_tag_c;
                dec_wave_advanced_tag     <= wave_advanced_tag_c;
                dec_input_payload         <= payload_latched;
                dec_input_payload_b       <= payload_b_latched;
                dec_input_payload_b_valid <= payload_b_valid_latched;
                dec_eff_b_value           <= eff_b_value;
                dec_eff_imm16             <= acc_imm16;
                dec_eff_dim_sizes         <= eff_dim_sizes;
                dec_eff_opref_kind        <= acc_opref_src_kind;
                dec_eff_mem_offset        <= acc_mem_offset;
                dec_eff_subscript         <= acc_subscript[47:0];
                dec_eff_subscript_hi      <= acc_subscript[95:48];
                dec_eff_output_port_id    <= eff_output_port_id;
                dec_eff_precision         <= eff_precision;
                dec_wave_number           <= cb_wave_number;
                dec_thread_id             <= cb_thread_id;
                dec_port_context_id       <= cb_port_context_id;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Combinational OPREF reflection — Cluster bank routing reads this in the
    // SAME cycle as `instruction`. Walks the raw `instruction` wire (not
    // instr_latched) so it's valid even before the input is latched.
    // -------------------------------------------------------------------------
    wire [31:0] iw_raw [0:INSTR_WORDS-1];
    genvar gri;
    generate
        for (gri = 0; gri < INSTR_WORDS; gri = gri + 1) begin : gen_iw_raw
            if (gri < INSTR_WORDS_REAL)
                assign iw_raw[gri] = instruction[gri*32 +: 32];
            else
                assign iw_raw[gri] = 32'h00000000;
        end
    endgenerate

    integer sc;
    reg [OFF_W-1:0] off_c     [0:MAX_EH];
    reg [3:0]       expect_c  [0:MAX_EH];
    reg [3:0] type_c, next_c;
    reg [7:0] extlen_c;
    reg [3:0] opref_kind_c;
    reg [3:0] opref_port_c;
    reg [7:0] opref_route_c;
    reg       opref_found_c;

    always @(*) begin
        off_c[0]      = {{(OFF_W-1){1'b0}}, 1'b1};
        expect_c[0]   = instruction[23:20];
        opref_kind_c  = 4'h0;
        opref_port_c  = 4'h0;
        opref_route_c = 8'h00;
        opref_found_c = 1'b0;
        type_c        = 4'h0;
        next_c        = 4'h0;
        extlen_c      = 8'h00;
        for (sc = 0; sc < MAX_EH; sc = sc + 1) begin
            if (expect_c[sc] != 4'h0 && !opref_found_c) begin
                type_c   = iw_raw[off_c[sc]][11:8];
                extlen_c = iw_raw[off_c[sc]][7:0];
                next_c   = iw_raw[off_c[sc]][15:12];
                if (type_c == 4'h7) begin
                    opref_kind_c  = iw_raw[off_c[sc]][19:16];
                    opref_port_c  = iw_raw[off_c[sc]][23:20];
                    opref_route_c = iw_raw[off_c[sc]][31:24];
                    opref_found_c = 1'b1;
                end
                off_c[sc+1]    = off_c[sc] + {{(OFF_W-4){1'b0}}, extlen_c[3:0]};
                expect_c[sc+1] = next_c;
            end else begin
                off_c[sc+1]    = off_c[sc];
                expect_c[sc+1] = 4'h0;
            end
        end
    end

    assign opref_src_kind_out  = opref_kind_c;
    assign opref_port_id_out   = opref_port_c;
    assign opref_noc_route_out = opref_route_c;

endmodule

/* verilator lint_on UNUSEDSIGNAL */
