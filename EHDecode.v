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
// bus width (INSTR_WIDTH = 32 + 32 + MAX_EH*96) is the only hard cap. See
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
//               instr_latched / payload_latched. `input_tag` 은 래치하지
//               않고 같은 에지에 cb_* 로 직접 분해한다 (§B-2 정리).
//               Pipeline kicks on next edge with stg_index=0.
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

module EHDecode #(
    parameter ADDR_WIDTH  = 64,
    parameter TAG_WIDTH   = 80,
    parameter MAX_EH      = 4,
    parameter INSTR_WIDTH = 32 + 32 + MAX_EH*96,   // W8: +CH = 448
    // v1.5.2 §19 — wide-input path capacity. 16 slot × 64 bit = 1024 bit
    // matches Cluster's fragment buffer (FRAG_MAX = 16). Legacy consumers
    // ignore this signal; wide-consumer primitives (v1.5.3+) read it.
    parameter FRAG_MAX    = 16,
    parameter WIDE_W      = FRAG_MAX * ADDR_WIDTH
) (
    input                       clk,
    input                       rst,
    input                       in_valid,
    input  [INSTR_WIDTH-1:0]    instruction,
    input  [TAG_WIDTH-1:0]      input_tag,
    input  [ADDR_WIDTH-1:0]     input_payload,
    input  [ADDR_WIDTH-1:0]     input_payload_b,
    input                       input_payload_b_valid,
    // v1.5.2 §19 — wide payload path. Cluster's fragment buffer drives
    // this with the reassembled wave-token payload when a multi-fragment
    // wave completes; otherwise legacy `input_payload` is authoritative.
    // `input_payload_wide_valid` distinguishes: 1 = wide is meaningful
    // (multi-fragment), 0 = legacy single-fragment (wide is unused).
    input  [WIDE_W-1:0]         input_payload_wide,
    input                       input_payload_wide_valid,

    // ---- Stage-1 registered dec_* bus (consumed by PE_Core) ----
    output reg                   dec_valid,
    // W1 잔여 (기록) — 이 버스는 12b opcode 의 **하위 8b** 만 나른다.
    // 오늘 이것이 접힘 경로가 **아닌** 이유는 하나뿐이다: 생성 whitelist
    // 가 12b 연접 등호-OR 라 확장 니블 ≠ 0 인 코드점은 전부 decode_error
    // 이고, PE_Core 는 `!dec_decode_error` 로 게이트되어 있다. 즉 여기에
    // 실려 내려가는 값의 확장 니블은 항상 0 이다.
    // 배정 코드점이 0x1##–0xF## 로 처음 들어오는 날 이 전제가 깨진다 —
    // 그날을 잡는 상주 그물은 asm 측의 「배정 코드점 확장 니블 0」
    // 트립와이어이고, 그것이 울리면 **먼저 이 버스를 12b 로 넓혀야
    // 한다** (PE_Core 의 디스패치 case 선택자까지 함께).
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
    // v1.8.0d §23.10.10(c) — encoding {presence, src_kind[2:0]}: bit 3 =
    // "an OPREF EH was present" (acc_any_opref), bits [2:0] = src_kind
    // (0 direct payload_b / 1 NoC bank / 2 TRNG; 3+ is decode_error via
    // opref_kind_unsupported, so the 3-bit truncation is lossless).
    // Rationale: without the presence bit, an OPREF EH with src_kind 0
    // (the COMMON direct-payload_b form) is indistinguishable from the
    // no-OPREF/imm form at the execute stage — both would read 4'h0.
    // The 0x73 ACC_ELEMWISE OPREF-only launch rung keys on bit 3.
    // (Cluster's NoC/TRNG B-side routing uses the SEPARATE combinational
    // opref_src_kind_out tap below, which keeps the raw kind encoding.)
    output reg [3:0]             dec_eff_opref_kind,
    output reg [31:0]            dec_eff_mem_offset,
    output reg [47:0]            dec_eff_subscript,
    // v1.3: second SUBSCRIPT EH body (axes 4-7 for {A,B,O}). Zero when
    // only one SUBSCRIPT EH was emitted (backward compatible w/ v1.2 sigs).
    output reg [47:0]            dec_eff_subscript_hi,
    // v1.4: second IMM64 EH body — 128-bit wide immediate via multi-IMM64
    // chain. Zero when only one IMM64 EH was emitted. Enables input-side
    // wide-tensor payload without changing the NoC packet format. See
    // wt64v1_spec.md §17.
    output reg [63:0]            dec_eff_imm64_hi,
    // v1.5.2 §19 — reassembled wide payload latched into the decoder's
    // dec_* bus. Zero when the wave was single-fragment (legacy). Wide-
    // consumer primitives (v1.5.3+) read this alongside dec_input_payload.
    output reg [WIDE_W-1:0]      dec_input_payload_wide,
    output reg                   dec_input_payload_wide_valid,
    output reg [7:0]             dec_eff_output_port_id,
    output reg [7:0]             dec_eff_precision,
    output reg [31:0]            dec_wave_number,
    output reg [15:0]            dec_thread_id,
    output reg [15:0]            dec_port_context_id,

    // ---- Combinational OPREF reflection (same-cycle as `instruction`) ----
    output [3:0]                 opref_src_kind_out,
    output [3:0]                 opref_port_id_out,
    output [7:0]                 opref_noc_route_out,

    // ---- 입력단 accept 가능 여부 (v1.9.2 §22.14b-3, normative) ----
    // `in_ready = !stg_active`. 체인 워크가 진행 중이면 :195 의 입력 래치와
    // :350 의 워크 kick 이 **둘 다** `in_valid && !stg_active` 로 가드되므로
    // 그 사이클의 `in_valid` 는 소비되지도 큐잉되지도 에러로 기록되지도
    // 않는다 — 즉 이 신호가 0 인 동안 들어온 명령은 **소실**된다.
    // 그 사실을 처음으로 모듈 경계에 노출하는 포트다. 기존 내부 reg 의
    // 반전일 뿐 **신규 상태가 아니다** (신규 FF 0).
    //
    // 이 포트를 읽는 부모는 소실 대신 **보류**를 선택할 수 있다 —
    // Cluster.v 의 skid buffer 1단이 그것이다 (§22.14b-3).
    output                       in_ready
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
    // v1.8.0a §23.9 — EH type codes come from the single machine-readable
    // ISA source (isa/wt64v1_isa.json) via scripts/gen_isa_tables.py.
    // This was the THIRD hand copy (after asm.py and the spec table) —
    // exactly the drift surface the single-source migration kills.
    `include "generated/isa_eh_codes.vh"

    // -------------------------------------------------------------------------
    // Chain-walk pipeline state — one slot per cycle.
    // v1.3: widths parametric on MAX_EH (was hardcoded 4-bit/3-bit for
    // MAX_EH=4). Termination is sentinel-driven; stg_index is only used
    // as a safety cap against malformed instructions without EH_END.
    //
    // D3 수리: 이 블록은 원래 iw_c generate 뒤(구 라인 204-209)에 있었고,
    // 바로 아래 입력 래치 always 블록이 `stg_active` 를 선언보다 먼저
    // 읽고 있었다. Vivado 는 관용적으로 통과시키지만 Verilog-2001 은
    // 선언 선행을 요구하므로 다른 합성기에서 hard error 가 될 수 있다.
    // 선언을 사용 지점 앞으로 올린 것 외에 변경 없음 (동일 모듈 스코프
    // 이므로 test_cluster.py:528 의 `dut.u_ehdec.stg_active` 계층 경로도
    // 그대로 유효하다).
    // -------------------------------------------------------------------------
    reg [OFF_W-1:0]  stg_off;
    reg [3:0]        stg_expect;
    reg [IDX_W-1:0]  stg_index;
    reg              stg_active;
    reg              stg_chain_err;
    reg              stg_unknown;

    // -------------------------------------------------------------------------
    // Latch the inputs once in_valid pulses so the chain walk reads stable
    // data even after the upstream changes its drive. Pipeline init happens
    // on the SAME cycle (no separate walk_kick stage) — `cb_*` and SLOT 0's
    // `stg_expect` are sourced directly from the live `instruction` wire,
    // while subsequent slots read from the registered `instr_latched`.
    // -------------------------------------------------------------------------
    reg [INSTR_WIDTH-1:0] instr_latched;
    // 태그 래치본은 두지 않는다. 태그 필드는 같은 에지에 `input_tag` 에서
    // cb_wave_number / cb_thread_id / cb_port_context_id / cb_precision_mode
    // / cb_dimension_sizes 로 **직접** 들어가고, 출력 태그는
    // `forwarded_tag_c` / `wave_advanced_tag_c` 가 조합으로 만든다. 즉
    // 읽는 곳이 한 군데도 없는 write-only 레지스터였다 — "입력 래치 집합의
    // 대칭" 이라는 명목상 사유만 있었고 RTL 의미에는 기여하지 않아 제거했다.
    reg [ADDR_WIDTH-1:0]  payload_latched, payload_b_latched;
    reg                   payload_b_valid_latched;
    // v1.5.2 §19 — wide payload latched on the same edge as legacy inputs.
    reg [WIDE_W-1:0]      payload_wide_latched;
    reg                   payload_wide_valid_latched;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            instr_latched              <= {INSTR_WIDTH{1'b0}};
            payload_latched            <= {ADDR_WIDTH{1'b0}};
            payload_b_latched          <= {ADDR_WIDTH{1'b0}};
            payload_b_valid_latched    <= 1'b0;
            payload_wide_latched       <= {WIDE_W{1'b0}};
            payload_wide_valid_latched <= 1'b0;
        end else if (in_valid && !stg_active) begin
            instr_latched              <= instruction;
            payload_latched            <= input_payload;
            payload_b_latched          <= input_payload_b;
            payload_b_valid_latched    <= input_payload_b_valid;
            payload_wide_latched       <= input_payload_wide;
            payload_wide_valid_latched <= input_payload_wide_valid;
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

    // D3 수리 흔적: 여기 있던 chain-walk 파이프라인 상태 선언 블록
    // (stg_off / stg_expect / stg_index / stg_active / stg_chain_err /
    // stg_unknown) 은 위 입력 래치 always 블록 앞으로 이동했다. 그 always
    // 블록이 `stg_active` 를 읽는데 선언이 뒤에 있어서, Vivado 의 관용에
    // 의존하는 use-before-declare 상태였다 (다른 합성기에서는 hard error).
    // 선언 위치만 옮겼을 뿐 폭·개수·초기화·구동 논리는 전부 그대로다.

    // Accumulated body fields
    reg [15:0] acc_port_body;
    reg [15:0] acc_imm16;
    reg [31:0] acc_imm32;
    // v1.4: IMM64 bank — 2 slots for 128-bit total immediate via
    // multi-IMM64 EH chain. First IMM64 EH lands in bank[0], second in
    // bank[1]; third raises stg_chain_err.
    reg [63:0] acc_imm64;
    reg [63:0] acc_imm64_hi;
    reg [1:0]  acc_imm64_slot;
    // MEM EH 의 addr_mode / stride 는 **legality 판정에서 실제로 읽힌다**
    // (C-1 실물화, 2026-08-18 — spec §2 `MEM.addr_mode`/`MEM.stride` 절 + §32).
    // 합법값은 **둘 다 0 뿐**이고 nonzero 는 `decode_error` 다
    // (`mem_addr_mode_illegal` / `mem_stride_illegal` — 둘 다 `acc_any_mem` 로
    //  게이트되나 그 게이트는 **예비 방어**다 — `mem_addr_mode_illegal` 정의
    //  바로 앞의 변이 실측 기록 + spec §32.11 참조).
    // 본 개정은 두 필드에 **어떤 주소 산술 의미도 배정하지 않는다** — 주소는
    // 여전히 `acc_mem_offset` 하나로만 결정된다 (`dec_eff_mem_offset`). 하드웨어가
    // 두 필드를 읽는 목적은 오직 **0 인지 확인**하는 것이다. 의미 배정은
    // 0x7D/0x7E sub-op 인코딩 규범화의 몫이며, 지금 선점하면 0x7D 가 sub-op 을
    // 실을 마지막 자유 공간이 사라진다 (§32.3).
    reg [ 3:0] acc_mem_addr_mode;
    reg [11:0] acc_mem_stride;
    reg [31:0] acc_mem_offset;
    // v1.3: widened to hold up to 2 SUBSCRIPT EH bodies (low + hi).
    // Lower 48 bits = first SUBSCRIPT (axes 0-3 for {A,B,O}).
    // Upper 48 bits = second SUBSCRIPT (axes 4-7 for {A,B,O}).
    reg [95:0] acc_subscript;
    reg [1:0]  acc_subscript_slot;  // 0=none seen, 1=one seen, 2=two seen
    reg [ 3:0] acc_opref_src_kind;
    // OPREF 의 port_id / noc_route 에는 누적 레지스터를 두지 않는다.
    // 실경로는 **조합 경로** (`opref_port_c` / `opref_route_c` →
    // opref_port_id_out / opref_noc_route_out) 하나뿐이다 — 부모(Cluster)의
    // bank 라우팅이 같은 에지에 값을 필요로 해서 1-사이클 늦은 누적본을 쓸
    // 수 없기 때문이다. 과거의 `acc_opref_port_id` / `acc_opref_noc_route`
    // 는 "EH 필드 집합의 대칭" 명목으로만 존재한 write-only 사본이었고,
    // 읽는 곳이 없어 제거했다. src_kind 는 누적본이 실제로 읽히므로 유지.
    reg [ 7:0] acc_prec_mode;
    reg [ 7:0] acc_prec_dim;

    // Per-class presence accumulators
    reg acc_any_port, acc_any_imm16, acc_any_imm32, acc_any_imm64;
    reg acc_any_mem,  acc_any_subscript, acc_any_opref, acc_any_precision;

    // Carried base header
    // 인코딩 개정 파도 W1 — opcode 는 12b 다: 기본 8b `[31:24]` + 확장
    // 니블 `[11:8]`. `[15:12]` 는 예약 4b (항상 0). 확장 니블은 생성
    // include 의 12b case arm / whitelist 와 결선되는 상위 니블이므로
    // 반드시 별도 캐리로 살아 있어야 한다 (8b 선택자로 접히면 0x4## 가
    // 0x0## arm 에 조용히 매치한다 — W2 가 경고한 공허 PASS).
    reg [7:0]  cb_opcode;
    reg [3:0]  cb_opcode_ext;
    reg [3:0]  cb_flags;
    reg [3:0]  cb_reserved;
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
            acc_imm64_hi       <= 64'h0;
            acc_imm64_slot     <= 2'd0;
            acc_opref_src_kind <= 4'h0;
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
            cb_opcode_ext      <= 4'h0;
            cb_flags           <= 4'h0;
            cb_reserved        <= 4'h0;
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
                // W8 — CH(Castagnoli Header): next_hdr ≠ END 이면 word 1 은
                // CH 이고 EH 사슬이 아니다. 보행은 word 2 에서 시작한다.
                // EH-0 (next_hdr == END) 은 CH 가 없으므로 종전과 동일하게
                // word 1 에서 시작한다 (즉시 종료). `bh_len` 은 CH 를 포함한
                // 물리 워드 총수이므로 bh_len 대조는 이 시작 오프셋에서
                // 자연히 유도된다 — 별도 보정이 없다.
                stg_off            <= (instruction[23:20] != 4'h0)
                                      ? {{(OFF_W-2){1'b0}}, 2'd2}
                                      : {{(OFF_W-1){1'b0}}, 1'b1};
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
                acc_imm64_hi       <= 64'h0;
                acc_imm64_slot     <= 2'd0;
                acc_opref_src_kind <= 4'h0;
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
                cb_opcode_ext      <= instruction[11:8];    // W1
                cb_flags           <= instruction[19:16];
                cb_reserved        <= instruction[15:12];   // W1: 8b → 4b
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
                        // v1.4: 2-slot IMM64 bank. First IMM64 → acc_imm64
                        // (backward compat), second → acc_imm64_hi. Third
                        // raises chain_err (encoding overflow).
                        if (acc_imm64_slot == 2'd0) begin
                            acc_imm64      <= {cur_w2, cur_w1};
                            acc_any_imm64  <= 1'b1;
                            acc_imm64_slot <= 2'd1;
                        end else if (acc_imm64_slot == 2'd1) begin
                            acc_imm64_hi   <= {cur_w2, cur_w1};
                            acc_imm64_slot <= 2'd2;
                        end else begin
                            stg_chain_err  <= 1'b1;
                        end
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
    // F_MEM (bit1) 은 **적법성 판정에서 실제로 읽힌다** (C-1 실물화, 2026-08-18
    // — spec §2 + §32.5): **F_MEM 이 서 있는데 MEM EH 가 없으면 `decode_error`**
    // (`mem_flag_without_eh` — `prec_flag_without_eh` 와 동형의 한쪽 함의).
    // **역방향은 강제하지 않는다** — MEM EH 가 있는데 F_MEM 이 서 있지 않은
    // 명령은 합법이다. 어셈블러에 F_MEM 을 자동 세팅하는 경로가 0건이라 역방향을
    // 강제하면 현존 전 LD/ST 가 즉시 `decode_error` 가 되고, ISA 자신도 이 비트를
    // `mem_hint` 로 명명한다 (§32.5 의 기각 근거 3건).
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
        // W1 — 선택자는 12b 다. `cb_opcode` 단독(8b)으로 선택하면 생성
        // include 의 `12'h###` arm 이 zero-extend 로 조용히 매치하여 확장
        // 니블이 접힌다. 연접은 그 접힘을 구조적으로 불가능하게 한다.
        case ({cb_opcode_ext, cb_opcode})
            // v1.8.0a §23.9 — legality case body is GENERATED from
            // isa/wt64v1_isa.json (scripts/gen_isa_tables.py). Historical
            // per-group commentary (v1.6.5c 0x63/64/65 bugfix rationale,
            // CACHE_LOAD_WIDE precision-EH note, ...) now lives in the
            // JSON desc/notes fields and is emitted into the include.
            `include "generated/isa_ehshape_case_body.vh"
        endcase
    end

    wire any_imm = acc_any_imm16 | acc_any_imm32 | acc_any_imm64;

    // v1.8.0a §23.9 — is_alu_binary + opcode_supported are GENERATED
    // (single-source). See isa/wt64v1_isa.json.
    `include "generated/isa_opcode_wires.vh"

    wire alu_binary_xor_err = is_alu_binary && (any_imm == acc_any_opref);

    // v1.8.0a COMMIT 2 §23.6a — FP-block mode-byte legality. The precision
    // byte (eff_precision: tag[15:8], or PRECISION-EH byte0 under
    // F_PRECISION_OVR — the pre-existing mux at line ~461, no new pipeline
    // state, no new ports) acquires format-selector SEMANTICS only inside
    // opcode block 0x70-0x7F (in_fp_block self-gate from the generated
    // wires include). For every supported sub-0x70 opcode (0x00-0x6A era
    // post opcode-cleanup) the byte stays inert metadata — bit-identical
    // legacy behavior regardless of its value, proven by the frozen
    // truth-table differential (domain_version 2 recapture).
    // An illegal mode byte is DECODE_ERROR (malformation), never
    // lower_required (capability absence) — decode/execute boundary.
    wire [3:0] mode_dtype = eff_precision[3:0];
    wire [1:0] mode_acc   = eff_precision[5:4];
    wire [1:0] mode_rnd   = eff_precision[7:6];
    wire fp_block_illegal = in_fp_block
        && !FP_LEGAL_ROM[{cb_opcode[3:0], mode_dtype, mode_acc, mode_rnd}];

    wire missing_eh   = (req_port      && !acc_any_port)
                      | (req_mem       && !acc_any_mem)
                      | (req_subscript && !acc_any_subscript)
                      | (req_opref     && !acc_any_opref)
                      | (req_imm16     && !acc_any_imm16);
    wire forbidden_eh = (forbid_subscript && acc_any_subscript)
                      | (forbid_mem       && acc_any_mem)
                      | (forbid_imm_any   && any_imm)
                      | (forbid_opref     && acc_any_opref);

    wire bh_len_mismatch = (cb_bh_len != {{(8-OFF_W){1'b0}}, stg_off});
    wire reserved_nonzero = (cb_reserved != 4'h0);
    wire prec_flag_without_eh = (f_precision_ovr || f_dim_ovr) && !acc_any_precision;
    wire opb_required_invalid   = f_has_opb && !payload_b_valid_latched;
    // OPREF.src_kind: 0=direct payload_b, 1=NoC bank, 2=TRNG. 3+ rejected.
    wire opref_kind_unsupported = acc_any_opref && (acc_opref_src_kind > 4'h2);
    // C-1 실물화 (2026-08-18) — spec §2 `MEM.addr_mode`/`MEM.stride` 절 + §32.2.
    // 두 필드는 **0 만 합법**이다. 의미는 배정하지 않는다 (§32.3).
    //
    // `acc_any_mem` 게이트에 대한 정직한 기록 (**개별 중복 · 합동 필수**,
    // spec §32.11 의 변이 표 — 2026-08-18 실측):
    //   * 잔재값 오발을 막는 방어는 **둘**이다 — (i) 명령 래치가 `acc_mem_addr_mode`
    //     /`acc_mem_stride` 를 0 으로 지우는 것, (ii) 이 `acc_any_mem` 게이트.
    //   * MUT-D (게이트만 제거) → **200 PASS, 생존**. 오늘의 RTL 에서 게이트는
    //     행위적으로 **중복**이며, 이를 죽이는 테스트는 존재할 수 없다 (클리어가
    //     `acc_mem_* != 0 ⟹ acc_any_mem` 을 무조건 참으로 만들어 **등가 변이**).
    //   * MUT-E (클리어만 제거) → **200 PASS, 생존**. 대칭적으로 게이트가 단독으로
    //     막는다.
    //   * MUT-F (둘 다 제거) → `test_mem_field_state_does_not_leak_across_instructions`
    //     **FAIL**. 즉 이 쌍은 dead code 가 아니라 **합동으로 필수**다.
    // 따라서 게이트는 "필수 조건" 이 아니라 **예비 방어(redundant-by-design)** 다 —
    // 클리어에 대한 의존을 끊고 전제("MEM EH 가 존재할 때만 판정")를 식 자체에
    // 명시한다. 이 문장을 "게이트가 없으면 오발한다" 로 되돌리지 말 것: 실측이
    // 반증한다.
    wire mem_addr_mode_illegal = acc_any_mem && (acc_mem_addr_mode != 4'h0);
    wire mem_stride_illegal    = acc_any_mem && (acc_mem_stride    != 12'h0);
    // F_MEM 방향1만: 플래그가 서 있는데 MEM EH 가 없음 → error.
    // 역방향(EH 있고 flag 없음)은 **합법**이다 — §32.5.
    wire mem_flag_without_eh   = f_mem && !acc_any_mem;

    wire decode_error = stg_chain_err | bh_len_mismatch | reserved_nonzero
                      | stg_unknown   | (!opcode_supported)
                      | missing_eh    | forbidden_eh
                      | alu_binary_xor_err
                      | opb_required_invalid | opref_kind_unsupported
                      | prec_flag_without_eh
                      // v1.8.0a COMMIT 2 — 12th term, self-gated to 0x70-0x7F.
                      // (원 주석은 "11th" 였으나 `dee6c94` 작성 시점부터
                      //  off-by-one — 그때도 피연산자는 12개였다. §32.7 말미.)
                      | fp_block_illegal
                      // C-1 실물화 (2026-08-18) — 13~15번째 항. spec §2 + §32.2.
                      | mem_addr_mode_illegal | mem_stride_illegal
                      | mem_flag_without_eh;

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
            dec_eff_mem_offset           <= 32'h0;
            dec_eff_subscript            <= 48'h0;
            dec_eff_subscript_hi         <= 48'h0;
            dec_eff_imm64_hi             <= 64'h0;
            dec_input_payload_wide       <= {WIDE_W{1'b0}};
            dec_input_payload_wide_valid <= 1'b0;
            dec_eff_output_port_id       <= 8'h00;
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
                // v1.8.0d §23.10.10(c) — presence bit 3 (see port comment)
                dec_eff_opref_kind        <= {acc_any_opref,
                                              acc_opref_src_kind[2:0]};
                dec_eff_mem_offset           <= acc_mem_offset;
                dec_eff_subscript            <= acc_subscript[47:0];
                dec_eff_subscript_hi         <= acc_subscript[95:48];
                dec_eff_imm64_hi             <= acc_imm64_hi;
                dec_input_payload_wide       <= payload_wide_latched;
                dec_input_payload_wide_valid <= payload_wide_valid_latched;
                dec_eff_output_port_id       <= eff_output_port_id;
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
    // extlen_c 는 EH 헤더의 8-bit ext-length 필드를 통째로 받지만, 오프셋
    // 전진에 쓰이는 것은 하위 니블 `extlen_c[3:0]` 뿐이다 (EH 길이는 최대
    // 15 워드). 상위 니블은 예약 필드라 읽지 않는다 — 폭을 4로 줄이면
    // 대입부에서 묵시적 절단이 생기므로 필드 폭은 spec 대로 두고 경고만
    // 국소 억제한다.
    /* verilator lint_off UNUSEDSIGNAL */
    reg [7:0] extlen_c;
    /* verilator lint_on UNUSEDSIGNAL */
    reg [3:0] opref_kind_c;
    reg [3:0] opref_port_c;
    reg [7:0] opref_route_c;
    reg       opref_found_c;

    always @(*) begin
        // W8 — 이 조합 보행도 CH 를 건너뛴다. `stg_off` 의 kick 과 **문자
        // 그대로 같은 항**이어야 한다: 두 보행이 서로 다른 워드에서
        // 시작하면 조합 반사(Cluster bank 라우팅)와 레지스터 경로가
        // 어긋난다.
        off_c[0]      = (instruction[23:20] != 4'h0)
                        ? {{(OFF_W-2){1'b0}}, 2'd2}
                        : {{(OFF_W-1){1'b0}}, 1'b1};
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
    // ⚠ W5 잔여 — `[23:20]` 은 더 이상 port_id 가 아니라 본문 12b(LBID ∥
    // src_kind)의 CRC-4 다. 이 출력이 반사하는 값은 그 CRC 니블이고,
    // 포트 이름만 폐지된 필드의 것으로 남아 있다. 개명은 Top_Core·합성
    // 래퍼 포트까지 번지므로 별도 커밋으로 분리했다. 소비자는 0건이다
    // (Cluster 는 명시적 미접속, Top_Core 는 상위로 통과만 시킨다).
    // 이 자리의 CRC **검산**(불일치 = malformation) 역시 아직 없다 — 파도
    // 이후 legacy 는 니블을 반사만 하고 판정하지 않는다.
    assign opref_port_id_out   = opref_port_c;
    assign opref_noc_route_out = opref_route_c;

    // v1.9.2 §22.14b-3 — 입력단 accept 가능 여부. `:195` / `:350` 의 가드
    // 조건과 **문자 그대로 같은 항**이므로 두 지점이 어긋날 수 없다.
    assign in_ready = !stg_active;

endmodule
