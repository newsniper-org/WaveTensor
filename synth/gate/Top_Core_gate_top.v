// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// Top_Core_gate_top.v — GATE S1-US 래퍼 (spec §28 — "시뮬레이터 통과 ≠
// 합성 가능" 을 상시 검사로 전환하는 system-integration 합성 gate).
//
// 발견 경위 (이 파일이 존재하는 이유)
// ----------------------------------
// 사용자의 HIU 면적 질문에 답하려 했을 때 답할 수가 없었다 — `HIU.v` 와
// `Top_Core.v` 는 repo 의 어떤 합성 스크립트에도 등장하지 않았고 (grep
// 실측: `synth/` 전체에서 두 파일명 등장 0건), 처음 합성을 시도하자
// Vivado 가 `ERROR [Synth 8-685]` 로 거부했다 (결함 D1 — `output reg
// dma_data_out` 을 서브모듈 출력에 연결한 Verilog-2001 위반). 즉 두
// 모듈은 cocotb 에서 계속 PASS 하면서 **한 번도 합성된 적이 없었다**.
// 이 gate 는 그 공백을 계보에 편입해 상시 검사로 만든다.
//
// gate_top 관례 (`synth/lattice/fp_ops/FP_TrainCluster_gate_top.v` 선례)
// ---------------------------------------------------------------------
//   * `rst` 를 제외한 모든 입출력을 정확히 1회 등록한다. 따라서 측정되는
//     모든 타이밍 경로는 `u_core` 내부의 실제 FF-to-FF 경로이며, OOC
//     I/O 지연이 WNS 를 오염시키지 않는다.
//   * 래퍼는 flop 만 추가한다 (LUT 기여 ~0) — 리포트의 LUT 수는 정직한
//     (보수적) core 수치다.
//   * `rst` 는 등록하지 않고 그대로 통과시킨다. Top_Core/HIU/ISA_Decoder
//     는 async-reset 설계이므로 reset 을 한 단 늦추면 reset 릴리즈 시점의
//     의미가 바뀐다. 대신 XDC 가 `set_false_path -from [get_ports rst]`
//     로 reset 배포 경로를 타이밍에서 제외한다 (fp-ops gate 관례가
//     "코어가 reset-free 라서 reset false path 가 없다" 였던 것과 정확히
//     반대의 이유 — 여기 코어는 reset 을 쓴다).
//
// wrapper I/O flop = 1,601: 입력 1,246 (token_valid 1 + instruction 416 +
// input_tag 80 + payload 64 + payload_b 64 + payload_b_valid 1 +
// mem_data_in 32 + chacha_nonce 192 + chacha_key 256 + context_switch 1 +
// partition_id 2 + interface_type 2 + ats_req 1 + pri_req 1 +
// shadow_write_start 64 + shadow_write_end 64 + shadow_write_en 1 +
// shadow_index 4) + 출력 355 (payload 64 + tag 80 + valid 1 + opcode 8 +
// frag_hdr 8 + pe_ready 1 + error_flag 1 + lower_required 1 + opref 16 +
// mem_data_out 32 + mem_phys_addr 64 + granted 1 + dma_ack 1 + ats_resp 1
// + pri_resp 1 + rng_raw 8 + rng_raw_valid 1 + rng_word 64 +
// rng_word_valid 1 + trng_unhealthy 1). FF 는 GATE S1 에서 추적만 한다
// (V9-4 관례) — binding 은 LUT ceiling / DSP·BRAM / premap $mul /
// DRC·CRITICAL WARNING 뿐이다.
//
// RTL 무수정
// ----------
// `Top_Core.v` / `ISA_Decoder.v` / `EHDecode.v` / `PE_Core.v` /
// `FP_StepSeq.v` / `FP_Mul36.v` / `FP_AddWide.v` / `HIU.v` 전부 무수정
// 인스턴스화한다. 이 래퍼는 어떤 신호도 발명하지 않고 Top_Core 의 포트를
// 그대로 등록해 노출한다 — 측정 대상이 실물 통합 top 이어야 하기 때문이다.
//
// TRNG 링 오실레이터 (결함 D2)
// ----------------------------
// `u_core/u_hiu/g_ro[*]` 는 의도된 조합 피드백(엔트로피 원천)이다. 이
// 래퍼는 그것에 아무 조치도 하지 않는다 — 인정은 XDC 의 몫이며
// `synth/constraints/hiu_trng_ro.xdc` 가 synth_design 직후 적용된다.
// gate 는 RO 8개에서 정확히 8건의 `[Synth 8-295] found timing loop`
// CRITICAL WARNING 만 화이트리스트하고, 그 외 CRITICAL WARNING 은 0 을
// 요구한다 (loud-fault-never-silent — 전역 강등 금지).

module Top_Core_gate_top #(
    parameter ADDR_WIDTH     = 64,
    parameter TAG_WIDTH      = 80,
    parameter MAX_EH         = 4,
    parameter INSTR_WIDTH    = 32 + MAX_EH*96,   // = 416
    parameter DMA_DATA_WIDTH = 32
) (
    input                          clk,
    input                          rst,     // 등록하지 않음 (위 주석)

    // ---- 토큰 측 경계 입력 ----
    input                          token_valid_i,
    input  [INSTR_WIDTH-1:0]       instruction_i,
    input  [TAG_WIDTH-1:0]         input_tag_i,
    input  [ADDR_WIDTH-1:0]        input_payload_i,
    input  [ADDR_WIDTH-1:0]        input_payload_b_i,
    input                          input_payload_b_valid_i,

    // ---- HIU 메모리 측 경계 입력 ----
    input  [DMA_DATA_WIDTH-1:0]    mem_data_in_i,

    // ---- HIU 구성 입력 ----
    input  [191:0]                 chacha_nonce_i,
    input  [255:0]                 chacha_key_i,
    input                          context_switch_i,
    input  [1:0]                   partition_id_i,
    input  [1:0]                   interface_type_i,
    input                          ats_req_i,
    input                          pri_req_i,
    input  [ADDR_WIDTH-1:0]        shadow_write_start_i,
    input  [ADDR_WIDTH-1:0]        shadow_write_end_i,
    input                          shadow_write_en_i,
    input  [3:0]                   shadow_index_i,

    // ---- 토큰 측 경계 출력 ----
    output reg [ADDR_WIDTH-1:0]    output_payload_o,
    output reg [TAG_WIDTH-1:0]     output_tag_o,
    output reg                     output_valid_o,
    output reg [7:0]               opcode_out_o,
    output reg [7:0]               output_frag_hdr_o,
    output reg                     pe_ready_o,
    output reg                     error_flag_o,
    output reg                     lower_required_o,
    output reg [3:0]               opref_src_kind_o,
    output reg [3:0]               opref_port_id_o,
    output reg [7:0]               opref_noc_route_o,

    // ---- HIU 메모리 측 경계 출력 ----
    output reg [DMA_DATA_WIDTH-1:0] mem_data_out_o,
    output reg [ADDR_WIDTH-1:0]    mem_phys_addr_o,
    output reg                     mem_access_granted_o,
    output reg                     mem_dma_ack_o,
    output reg                     ats_resp_o,
    output reg                     pri_resp_o,

    // ---- TRNG 경계 출력 ----
    output reg [7:0]               rng_raw_o,
    output reg                     rng_raw_valid_o,
    output reg [63:0]              rng_word_o,
    output reg                     rng_word_valid_o,
    output reg                     trng_unhealthy_o
);

    // ---- 입력 등록 (1,246 flops) ----
    reg                        token_valid_q;
    reg [INSTR_WIDTH-1:0]      instruction_q;
    reg [TAG_WIDTH-1:0]        input_tag_q;
    reg [ADDR_WIDTH-1:0]       input_payload_q;
    reg [ADDR_WIDTH-1:0]       input_payload_b_q;
    reg                        input_payload_b_valid_q;
    reg [DMA_DATA_WIDTH-1:0]   mem_data_in_q;
    reg [191:0]                chacha_nonce_q;
    reg [255:0]                chacha_key_q;
    reg                        context_switch_q;
    reg [1:0]                  partition_id_q;
    reg [1:0]                  interface_type_q;
    reg                        ats_req_q;
    reg                        pri_req_q;
    reg [ADDR_WIDTH-1:0]       shadow_write_start_q;
    reg [ADDR_WIDTH-1:0]       shadow_write_end_q;
    reg                        shadow_write_en_q;
    reg [3:0]                  shadow_index_q;

    // ---- core 출력 조합 넷 ----
    wire [ADDR_WIDTH-1:0]      output_payload_w;
    wire [TAG_WIDTH-1:0]       output_tag_w;
    wire                       output_valid_w;
    wire [7:0]                 opcode_out_w;
    wire [7:0]                 output_frag_hdr_w;
    wire                       pe_ready_w;
    wire                       error_flag_w;
    wire                       lower_required_w;
    wire [3:0]                 opref_src_kind_w;
    wire [3:0]                 opref_port_id_w;
    wire [7:0]                 opref_noc_route_w;
    wire [DMA_DATA_WIDTH-1:0]  mem_data_out_w;
    wire [ADDR_WIDTH-1:0]      mem_phys_addr_w;
    wire                       mem_access_granted_w;
    wire                       mem_dma_ack_w;
    wire                       ats_resp_w;
    wire                       pri_resp_w;
    wire [7:0]                 rng_raw_w;
    wire                       rng_raw_valid_w;
    wire [63:0]                rng_word_w;
    wire                       rng_word_valid_w;
    wire                       trng_unhealthy_w;

    always @(posedge clk) begin
        token_valid_q           <= token_valid_i;
        instruction_q           <= instruction_i;
        input_tag_q             <= input_tag_i;
        input_payload_q         <= input_payload_i;
        input_payload_b_q       <= input_payload_b_i;
        input_payload_b_valid_q <= input_payload_b_valid_i;
        mem_data_in_q           <= mem_data_in_i;
        chacha_nonce_q          <= chacha_nonce_i;
        chacha_key_q            <= chacha_key_i;
        context_switch_q        <= context_switch_i;
        partition_id_q          <= partition_id_i;
        interface_type_q        <= interface_type_i;
        ats_req_q               <= ats_req_i;
        pri_req_q               <= pri_req_i;
        shadow_write_start_q    <= shadow_write_start_i;
        shadow_write_end_q      <= shadow_write_end_i;
        shadow_write_en_q       <= shadow_write_en_i;
        shadow_index_q          <= shadow_index_i;

        // ---- 출력 등록 (355 flops) ----
        output_payload_o        <= output_payload_w;
        output_tag_o            <= output_tag_w;
        output_valid_o          <= output_valid_w;
        opcode_out_o            <= opcode_out_w;
        output_frag_hdr_o       <= output_frag_hdr_w;
        pe_ready_o              <= pe_ready_w;
        error_flag_o            <= error_flag_w;
        lower_required_o        <= lower_required_w;
        opref_src_kind_o        <= opref_src_kind_w;
        opref_port_id_o         <= opref_port_id_w;
        opref_noc_route_o       <= opref_noc_route_w;
        mem_data_out_o          <= mem_data_out_w;
        mem_phys_addr_o         <= mem_phys_addr_w;
        mem_access_granted_o    <= mem_access_granted_w;
        mem_dma_ack_o           <= mem_dma_ack_w;
        ats_resp_o              <= ats_resp_w;
        pri_resp_o              <= pri_resp_w;
        rng_raw_o               <= rng_raw_w;
        rng_raw_valid_o         <= rng_raw_valid_w;
        rng_word_o              <= rng_word_w;
        rng_word_valid_o        <= rng_word_valid_w;
        trng_unhealthy_o        <= trng_unhealthy_w;
    end

    Top_Core #(
        .ADDR_WIDTH    (ADDR_WIDTH),
        .TAG_WIDTH     (TAG_WIDTH),
        .MAX_EH        (MAX_EH),
        .INSTR_WIDTH   (INSTR_WIDTH),
        .DMA_DATA_WIDTH(DMA_DATA_WIDTH)
    ) u_core (
        .clk                  (clk),
        .rst                  (rst),
        .token_valid          (token_valid_q),
        .instruction          (instruction_q),
        .input_tag            (input_tag_q),
        .input_payload        (input_payload_q),
        .input_payload_b      (input_payload_b_q),
        .input_payload_b_valid(input_payload_b_valid_q),
        .output_payload       (output_payload_w),
        .output_tag           (output_tag_w),
        .output_valid         (output_valid_w),
        .opcode_out           (opcode_out_w),
        .output_frag_hdr      (output_frag_hdr_w),
        .pe_ready             (pe_ready_w),
        .error_flag           (error_flag_w),
        .lower_required       (lower_required_w),
        .opref_src_kind       (opref_src_kind_w),
        .opref_port_id        (opref_port_id_w),
        .opref_noc_route      (opref_noc_route_w),
        .mem_data_in          (mem_data_in_q),
        .mem_data_out         (mem_data_out_w),
        .mem_phys_addr        (mem_phys_addr_w),
        .mem_access_granted   (mem_access_granted_w),
        .mem_dma_ack          (mem_dma_ack_w),
        .chacha_nonce         (chacha_nonce_q),
        .chacha_key           (chacha_key_q),
        .context_switch       (context_switch_q),
        .partition_id         (partition_id_q),
        .interface_type       (interface_type_q),
        .ats_req              (ats_req_q),
        .pri_req              (pri_req_q),
        .shadow_write_start   (shadow_write_start_q),
        .shadow_write_end     (shadow_write_end_q),
        .shadow_write_en      (shadow_write_en_q),
        .shadow_index         (shadow_index_q),
        .ats_resp             (ats_resp_w),
        .pri_resp             (pri_resp_w),
        .rng_raw              (rng_raw_w),
        .rng_raw_valid        (rng_raw_valid_w),
        .rng_word             (rng_word_w),
        .rng_word_valid       (rng_word_valid_w),
        .trng_unhealthy       (trng_unhealthy_w)
    );

endmodule
