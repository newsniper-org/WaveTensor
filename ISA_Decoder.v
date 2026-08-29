// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

// =============================================================================
// ISA_Decoder.v — thin wrapper around EHDecode + PE_Core.
//
// Preserves the original module interface so all stand-alone tests
// (test_isa_decoder.py, test_top_core.py via Top_Core).  The PE.v wrapper
// was another such consumer until C-2 retired it (spec §33.3 verdict 4).
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
    parameter INSTR_WIDTH           = 32 + 32 + MAX_EH*96,  // W8: +CH = 448
    parameter MUL_OPS_SUPPORTED     = 1,
    parameter DIV_OPS_SUPPORTED     = 1,
    parameter NON_MUL_OPS_SUPPORTED = 1,
    parameter FRAG_MAX              = 16,
    parameter WIDE_W                = FRAG_MAX * ADDR_WIDTH
) (
    input                       clk,
    input                       rst,
    input                       token_valid,
    input  [INSTR_WIDTH-1:0]    instruction,
    input  [TAG_WIDTH-1:0]      input_tag,
    input  [ADDR_WIDTH-1:0]     input_payload,
    input  [ADDR_WIDTH-1:0]     input_payload_b,
    input                       input_payload_b_valid,
    // v1.5.2 §19 — wide payload input (from Cluster fragment buffer).
    // For standalone tests without fragmentation, tie both to 0.
    input  [WIDE_W-1:0]         input_payload_wide,
    input                       input_payload_wide_valid,
    output [ADDR_WIDTH-1:0]     output_payload,
    output [TAG_WIDTH-1:0]      output_tag,
    output                      output_valid,
    output [7:0]                opcode_out,
    // v1.5 §17 — NoC wave-token fragment header. Default 8'h00 (single-
    // fragment) for all v1.0..1.4 primitives.
    output [7:0]                output_frag_hdr,
    // v1.6.6 §22.14 — pe_ready back-pressure signal (combinational).
    // Exposed for upstream fabric observation. High when PE_Core can
    // accept a new dispatch; low during FSM emit or MUL/DIV in-flight.
    output                      pe_ready,
    // v1.5.2 §19 — reassembled wide payload latched into the dec_* stage.
    // Exposed at the ISA_Decoder boundary for hierarchical test access
    // and downstream (Cluster.v / Top_Core.v) legacy tie-off.  (PE.v also
    // tied this off until C-2 retired it — spec §33.3.)
    output [WIDE_W-1:0]         dec_input_payload_wide_out,
    output                      dec_input_payload_wide_valid_out,
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
    /* verilator lint_off UNUSEDSIGNAL */
    // v1.3: second SUBSCRIPT EH body. Exposed for hierarchical test access
    // and future 5+ axes signature dispatch. Unused by current PE_Core (see
    // wt64v1_spec.md §16).
    wire [47:0]                dec_eff_subscript_hi;
    // v1.4: second IMM64 EH body — 128-bit wide immediate. Exposed for
    // hierarchical test access; PE_Core doesn't yet consume this (see
    // wt64v1_spec.md §17).
    wire [63:0]                dec_eff_imm64_hi;
    /* verilator lint_on UNUSEDSIGNAL */
    // v1.5.2b §19 — internal wide-payload wire. EHDecode drives; PE_Core
    // reads (via new wide-input port) AND top-level output_wide port
    // exposes it for hierarchical test / future upstream observability.
    wire [WIDE_W-1:0]          dec_input_payload_wide;
    wire                       dec_input_payload_wide_valid;
    wire [7:0]                 dec_eff_output_port_id;
    wire [7:0]                 dec_eff_precision;
    wire [31:0]                dec_wave_number;
    wire [15:0]                dec_thread_id;
    /* verilator lint_off UNUSEDSIGNAL */
    // `dec_port_context_id` 는 EHDecode 가 내보내지만 **어떤 부모도 읽지
    // 않는다** — Cluster 는 dec_* 버스가 한 사이클 늦어서 쓸 수 없고,
    // `ext_tag[31:16]` 에서 직접 뽑은 조합 `in_pcid` 를 쓴다 (Cluster.v:498).
    // 여기 wire 는 이 얇은 래퍼가 EHDecode 의 dec_* 버스를 **전부** 받아
    // 형태를 증언하기 위한 것이며, 래퍼 안에서는 읽히지 않는다.
    wire [15:0]                dec_port_context_id;
    /* verilator lint_on UNUSEDSIGNAL */

    EHDecode #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .TAG_WIDTH  (TAG_WIDTH),
        .MAX_EH     (MAX_EH),
        .INSTR_WIDTH(INSTR_WIDTH),
        .FRAG_MAX   (FRAG_MAX),
        .WIDE_W     (WIDE_W)
    ) u_ehdec (
        .clk                       (clk),
        .rst                       (rst),
        .in_valid                  (token_valid),
        .instruction               (instruction),
        .input_tag                 (input_tag),
        .input_payload             (input_payload),
        .input_payload_b           (input_payload_b),
        .input_payload_b_valid     (input_payload_b_valid),
        .input_payload_wide        (input_payload_wide),
        .input_payload_wide_valid  (input_payload_wide_valid),
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
        .opref_src_kind_out        (opref_src_kind_out),
        .opref_port_id_out         (opref_port_id_out),
        .opref_noc_route_out       (opref_noc_route_out),
        // v1.9.2 §22.14b-3/-5 — EHDecode 신규 출력 `in_ready` 는 여기서
        // **의도적으로 미접속**이다 (§22.14b-5 표의 갈래 A). 근거 2건:
        //   (1) 보류 경로(skid buffer)는 Cluster 계층의 구조물이고
        //       (`Cluster.v` §22.14b-3), 이 얇은 래퍼에는 보류할 저장소도
        //       배압을 걸 상대도 없다. 포트만 올리면 "관찰은 되는데 아무도
        //       쓰지 않는 신호" 가 하나 더 생길 뿐이다 — §22.14b-2 가
        //       `cluster_ready` 에 대해 정확히 그 형태를 문제 삼았다.
        //   (2) `EHDecode.v` 는 GATE S1(`sys_top_core`) 소스 목록 안이다.
        //       미접속이면 `Top_Core` 트리에서 프루닝되어 **전 축 델타 0**
        //       이고, 노출하면 premap ports 49→50 · port bits 1,742→1,743
        //       으로 gate 상수를 같은 commit 에서 옮겨야 한다 (갈래 B).
        //       본 세션의 작업 범위는 gate 기준 수치를 건드리지 않는다.
        // **정직 명기**: 따라서 `ISA_Decoder` 를 단독으로 구동하는 경로
        // (test_isa_decoder.py / Top_Core.v)에는 §22.14b-1 의 무언
        // drop 이 **그대로 남아 있다** — 체인 워크 중(`MAX_EH` 에지)
        // `token_valid` 를 다시 올리면 그 명령은 소실된다. 이 계층에서
        // 그것을 닫으려면 여기에도 보류 경로가 필요하며, 본 amendment 의
        // 범위가 아니다 (Cluster 가 유일한 실사용 주입 경로다).
        .in_ready                  ()
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
        .dec_eff_subscript_hi      (dec_eff_subscript_hi),
        .dec_eff_imm64_hi          (dec_eff_imm64_hi),
        .dec_input_payload_wide    (dec_input_payload_wide),
        .dec_input_payload_wide_valid (dec_input_payload_wide_valid),
        .dec_eff_output_port_id    (dec_eff_output_port_id),
        .dec_eff_precision         (dec_eff_precision),
        .dec_wave_number           (dec_wave_number),
        .dec_thread_id             (dec_thread_id),
        .output_payload            (output_payload),
        .output_tag                (output_tag),
        .output_valid              (output_valid),
        .opcode_out                (opcode_out),
        .output_frag_hdr           (output_frag_hdr),
        .pe_ready                  (pe_ready),
        .memory_req                (memory_req),
        .mem_addr                  (mem_addr),
        .error_flag                (error_flag),
        .lower_required            (lower_required),
        // v1.8.0e 3a-C4 §35.3 항 5 — 갈래 A (미노출), `.in_ready ()` 바로
        // 위 관용구의 복제다. FDOT32_CR 의 두 sticky 는 여기서 **의도적으로
        // 미접속**이다.
        //   (1) `ISA_Decoder` 는 single-decoder demo 다. 이 계층에는 §26.5
        //       등급의 reset-clearable 승격을 보관할 저장소도, 그것을 읽을
        //       소비자도 없다 — 포트만 올리면 §22.14b-2 가 `cluster_ready`
        //       에 대해 문제 삼은 "관찰은 되는데 아무도 쓰지 않는 신호" 를
        //       하나 더 만든다. 승격은 `rst` 를 가지고 `any_error_flag` 를
        //       실제로 소유한 `Cluster` 에서 한다.
        //   (2) 귀결 (측정 전 공표, §35.6): `sys_top_core` 형상에서
        //       `fd_fault` 는 **여전히 프루닝**되므로 `Synth 8-6014` 는
        //       **15 를 유지한다.** 15 는 실패 신호가 아니다 — 14 가 나오면
        //       누군가 갈래 B 를 택했다는 뜻이고, 그때는 갈래 변경과
        //       `synth/gate/Top_Core_gate_top.v` 의 wrapper I/O flop 회계를
        //       같은 COMMIT 에 기록해야 한다.
        // **정직 명기**: 따라서 `fd_fault` 가 실리콘에 실재한다는 증거는
        // 이 경로가 아니라 **Cluster 축**에서 얻는다 (cocotb directed poke
        // + Cluster 합성 census).
        .fp_special_sticky         (),
        .fp_unit_fault             ()
    );

    // v1.5.2b §19 — mirror the internal wide bus to the top-level output
    // ports (kept for hierarchical test access and future upstream taps).
    assign dec_input_payload_wide_out       = dec_input_payload_wide;
    assign dec_input_payload_wide_valid_out = dec_input_payload_wide_valid;

endmodule
