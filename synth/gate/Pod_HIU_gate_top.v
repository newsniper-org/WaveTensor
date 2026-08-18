// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// Pod_HIU_gate_top.v — U30 SoC 묶음 실측용 gate 래퍼.
//
// 목적
// ----
// 사용자 질문 "Alveo U30 카드의 SoC 하나당 (2x2)x(2x2)+HIU 묶음을 각각
// 합성하는 건 어떨지"에 실측으로 답하기 위한 top. Pod(2x2 cluster x 2x2 PE
// = 16 PE) 하나와 HIU 하나를 같은 top 에 병치하고, 같은 clk/rst 를 공유해
// 하나의 패브릭 위에서 경쟁하게 만든다.
//
// gate_top 관례 (FP_StepSeq_gate_top.v / FP_Mul36_gate_top.v 선례)
// ----------------------------------------------------------------
//   * 모든 입출력을 정확히 1회 등록한다. 따라서 측정되는 모든 타이밍
//     경로는 두 블록 내부의 실제 FF-to-FF 경로다 (I/O 지연이 WNS 를
//     오염시키지 않는다).
//   * 래퍼는 flop 만 추가한다 (LUT ~0).
//
// 블록 간 결선
// ------------
// 두 블록 사이에는 RTL 주석이 명시한 결선이 2개 있다. 억지 프로토콜을
// 발명하지 않고, 그 2개만 잇는다. 둘 다 래퍼에서 1회 등록하므로
// cross-block 경로 역시 FF-to-FF 이며, 각 블록 단독 실측치와 그대로
// 비교 가능하다.
//
//   1) HIU.rng_word / rng_word_valid  ->  Pod.rng_word / rng_word_valid
//      근거: Pod.v "TRNG broadcast (Pod-wide; sourced from HIU one level
//      up)" — OPREF.src_kind=2 (RNG bank) 공급원.
//   2) Pod.mem_addr                   ->  HIU.virt_addr
//      근거: Pod.v "Memory side-channel (forwarded from any Cluster to a
//      Pod-level HIU)". 주소만 전달한다. mem_req 를 HIU 의 어느 요청
//      입력에 물릴지는 spec 이 규정하지 않았으므로 발명하지 않고, HIU 의
//      요청 입력(dma_req/ats_req/pri_req)은 top 경계 입력으로 남기고
//      mem_req 는 등록된 top 출력으로 관측만 한다.
//
// RTL 무수정
// ----------
// Pod.v / Cluster.v / PE_Core.v / FP_* / HIU.v 전부 무수정 인스턴스화.
// (합성 하네스가 쓰는 HIU.v 사본에는 정찰 결함 D1 — `output reg
// dma_data_out` 이 서브모듈 출력에 연결된 Verilog-2001 위반 — 만
// wire 로 되돌려 놓았다. 본체가 구동하지 않는 포트이므로 의미 보존.)

module Pod_HIU_gate_top #(
    parameter ADDR_WIDTH   = 64,
    parameter TAG_WIDTH    = 80,
    parameter MAX_EH       = 4,
    parameter INSTR_WIDTH  = 32 + MAX_EH*96,   // = 416
    parameter PE_ROWS      = 2,
    parameter PE_COLS      = 2,
    parameter CLUSTER_ROWS = 2,
    parameter CLUSTER_COLS = 2,
    parameter DATA_WIDTH   = 32
) (
    input                          clk,
    input                          rst,

    // ---- Pod 측 경계 입력 ----
    input                          ext_valid_i,
    input  [INSTR_WIDTH-1:0]       ext_instruction_i,
    input  [TAG_WIDTH-1:0]         ext_tag_i,
    input  [ADDR_WIDTH-1:0]        ext_payload_i,
    input  [ADDR_WIDTH-1:0]        ext_payload_b_i,
    input                          ext_payload_b_valid_i,
    input  [7:0]                   ext_frag_hdr_i,

    // ---- HIU 측 경계 입력 ----
    input                          dma_req_i,
    input  [DATA_WIDTH-1:0]        dma_data_in_i,
    input  [1:0]                   interface_type_i,
    input                          ats_req_i,
    input                          pri_req_i,
    input  [ADDR_WIDTH-1:0]        shadow_write_start_i,
    input  [ADDR_WIDTH-1:0]        shadow_write_end_i,
    input                          shadow_write_en_i,
    input  [3:0]                   shadow_index_i,
    input                          context_switch_i,
    input  [1:0]                   partition_id_i,
    input  [191:0]                 chacha_nonce_i,
    input  [255:0]                 chacha_key_i,

    // ---- HIU partitioned-TLB fill 입력 (spec §29.4 — D4 실물화) ----
    // 래퍼 관례대로 rst 를 제외한 신규 I/O 를 정확히 1회 등록한다.
    input                          tlb_write_en_i,
    input  [1:0]                   tlb_write_partition_i,
    input  [3:0]                   tlb_write_index_i,
    input  [ADDR_WIDTH-1:0]        tlb_write_virt_i,
    input  [ADDR_WIDTH-1:0]        tlb_write_phys_i,

    // ---- Pod 측 경계 출력 ----
    output reg [TAG_WIDTH-1:0]     ext_out_tag_o,
    output reg [ADDR_WIDTH-1:0]    ext_out_payload_o,
    output reg [7:0]               ext_out_opcode_o,
    output reg [7:0]               ext_out_frag_hdr_o,
    output reg                     ext_out_valid_o,
    output reg                     mem_req_o,
    output reg [ADDR_WIDTH-1:0]    mem_addr_o,
    output reg                     any_error_flag_o,
    output reg                     any_lower_required_o,
    output reg                     pod_ready_o,

    // ---- HIU 측 경계 출력 ----
    output reg [ADDR_WIDTH-1:0]    phys_addr_o,
    output reg [DATA_WIDTH-1:0]    dma_data_out_o,
    output reg                     dma_ack_o,
    output reg                     access_granted_o,
    output reg                     ats_resp_o,
    output reg                     pri_resp_o,
    output reg                     tlb_fault_o,
    output reg [2:0]               tlb_fault_code_o,
    output reg [7:0]               rng_raw_o,
    output reg                     rng_raw_valid_o,
    output reg [63:0]              rng_word_o,
    output reg                     rng_word_valid_o,
    output reg                     trng_unhealthy_o
);

    // =========================================================================
    // 입력 등록단 (1회)
    // =========================================================================
    reg                     ext_valid_q;
    reg [INSTR_WIDTH-1:0]   ext_instruction_q;
    reg [TAG_WIDTH-1:0]     ext_tag_q;
    reg [ADDR_WIDTH-1:0]    ext_payload_q;
    reg [ADDR_WIDTH-1:0]    ext_payload_b_q;
    reg                     ext_payload_b_valid_q;
    reg [7:0]               ext_frag_hdr_q;

    reg                     dma_req_q;
    reg [DATA_WIDTH-1:0]    dma_data_in_q;
    reg [1:0]               interface_type_q;
    reg                     ats_req_q;
    reg                     pri_req_q;
    reg [ADDR_WIDTH-1:0]    shadow_write_start_q;
    reg [ADDR_WIDTH-1:0]    shadow_write_end_q;
    reg                     shadow_write_en_q;
    reg [3:0]               shadow_index_q;
    reg                     context_switch_q;
    reg [1:0]               partition_id_q;
    reg [191:0]             chacha_nonce_q;
    reg [255:0]             chacha_key_q;
    reg                     tlb_write_en_q;
    reg [1:0]               tlb_write_partition_q;
    reg [3:0]               tlb_write_index_q;
    reg [ADDR_WIDTH-1:0]    tlb_write_virt_q;
    reg [ADDR_WIDTH-1:0]    tlb_write_phys_q;

    // =========================================================================
    // 블록 출력 wire
    // =========================================================================
    wire [TAG_WIDTH-1:0]    pod_out_tag_w;
    wire [ADDR_WIDTH-1:0]   pod_out_payload_w;
    wire [7:0]              pod_out_opcode_w;
    wire [7:0]              pod_out_frag_hdr_w;
    wire                    pod_out_valid_w;
    wire                    pod_mem_req_w;
    wire [ADDR_WIDTH-1:0]   pod_mem_addr_w;
    wire                    pod_any_error_w;
    wire                    pod_any_lower_w;
    wire                    pod_ready_w;

    wire [ADDR_WIDTH-1:0]   hiu_phys_addr_w;
    wire [DATA_WIDTH-1:0]   hiu_dma_data_out_w;
    wire                    hiu_dma_ack_w;
    wire                    hiu_access_granted_w;
    wire                    hiu_ats_resp_w;
    wire                    hiu_pri_resp_w;
    wire                    hiu_tlb_fault_w;
    wire [2:0]              hiu_tlb_fault_code_w;
    wire [7:0]              hiu_rng_raw_w;
    wire                    hiu_rng_raw_valid_w;
    wire [63:0]             hiu_rng_word_w;
    wire                    hiu_rng_word_valid_w;
    wire                    hiu_trng_unhealthy_w;

    // =========================================================================
    // 블록 간 결선 파이프 레지스터 (1회 — cross-block 도 FF-to-FF 로 유지)
    // =========================================================================
    reg [63:0]              link_rng_word_q;        // HIU -> Pod
    reg                     link_rng_word_valid_q;  // HIU -> Pod
    reg [ADDR_WIDTH-1:0]    link_virt_addr_q;       // Pod -> HIU

    always @(posedge clk) begin
        // ---- 입력 등록 ----
        ext_valid_q           <= ext_valid_i;
        ext_instruction_q     <= ext_instruction_i;
        ext_tag_q             <= ext_tag_i;
        ext_payload_q         <= ext_payload_i;
        ext_payload_b_q       <= ext_payload_b_i;
        ext_payload_b_valid_q <= ext_payload_b_valid_i;
        ext_frag_hdr_q        <= ext_frag_hdr_i;

        dma_req_q             <= dma_req_i;
        dma_data_in_q         <= dma_data_in_i;
        interface_type_q      <= interface_type_i;
        ats_req_q             <= ats_req_i;
        pri_req_q             <= pri_req_i;
        shadow_write_start_q  <= shadow_write_start_i;
        shadow_write_end_q    <= shadow_write_end_i;
        shadow_write_en_q     <= shadow_write_en_i;
        shadow_index_q        <= shadow_index_i;
        context_switch_q      <= context_switch_i;
        partition_id_q        <= partition_id_i;
        chacha_nonce_q        <= chacha_nonce_i;
        chacha_key_q          <= chacha_key_i;
        tlb_write_en_q        <= tlb_write_en_i;
        tlb_write_partition_q <= tlb_write_partition_i;
        tlb_write_index_q     <= tlb_write_index_i;
        tlb_write_virt_q      <= tlb_write_virt_i;
        tlb_write_phys_q      <= tlb_write_phys_i;

        // ---- 블록 간 링크 등록 ----
        link_rng_word_q       <= hiu_rng_word_w;
        link_rng_word_valid_q <= hiu_rng_word_valid_w;
        link_virt_addr_q      <= pod_mem_addr_w;

        // ---- 출력 등록 ----
        ext_out_tag_o         <= pod_out_tag_w;
        ext_out_payload_o     <= pod_out_payload_w;
        ext_out_opcode_o      <= pod_out_opcode_w;
        ext_out_frag_hdr_o    <= pod_out_frag_hdr_w;
        ext_out_valid_o       <= pod_out_valid_w;
        mem_req_o             <= pod_mem_req_w;
        mem_addr_o            <= pod_mem_addr_w;
        any_error_flag_o      <= pod_any_error_w;
        any_lower_required_o  <= pod_any_lower_w;
        pod_ready_o           <= pod_ready_w;

        phys_addr_o           <= hiu_phys_addr_w;
        dma_data_out_o        <= hiu_dma_data_out_w;
        dma_ack_o             <= hiu_dma_ack_w;
        access_granted_o      <= hiu_access_granted_w;
        ats_resp_o            <= hiu_ats_resp_w;
        pri_resp_o            <= hiu_pri_resp_w;
        tlb_fault_o           <= hiu_tlb_fault_w;
        tlb_fault_code_o      <= hiu_tlb_fault_code_w;
        rng_raw_o             <= hiu_rng_raw_w;
        rng_raw_valid_o       <= hiu_rng_raw_valid_w;
        rng_word_o            <= hiu_rng_word_w;
        rng_word_valid_o      <= hiu_rng_word_valid_w;
        trng_unhealthy_o      <= hiu_trng_unhealthy_w;
    end

    // =========================================================================
    // Pod — (2x2 cluster) x (2x2 PE) = 16 PE
    // =========================================================================
    Pod #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .TAG_WIDTH    (TAG_WIDTH),
        .MAX_EH       (MAX_EH),
        .INSTR_WIDTH  (INSTR_WIDTH),
        .PE_ROWS      (PE_ROWS),
        .PE_COLS      (PE_COLS),
        .CLUSTER_ROWS (CLUSTER_ROWS),
        .CLUSTER_COLS (CLUSTER_COLS)
    ) u_pod (
        .clk                 (clk),
        .rst                 (rst),
        .ext_valid           (ext_valid_q),
        .ext_instruction     (ext_instruction_q),
        .ext_tag             (ext_tag_q),
        .ext_payload         (ext_payload_q),
        .ext_payload_b       (ext_payload_b_q),
        .ext_payload_b_valid (ext_payload_b_valid_q),
        .ext_frag_hdr        (ext_frag_hdr_q),
        .rng_word            (link_rng_word_q),
        .rng_word_valid      (link_rng_word_valid_q),
        .ext_out_tag         (pod_out_tag_w),
        .ext_out_payload     (pod_out_payload_w),
        .ext_out_opcode      (pod_out_opcode_w),
        .ext_out_frag_hdr    (pod_out_frag_hdr_w),
        .ext_out_valid       (pod_out_valid_w),
        .mem_req             (pod_mem_req_w),
        .mem_addr            (pod_mem_addr_w),
        .any_error_flag      (pod_any_error_w),
        .any_lower_required  (pod_any_lower_w),
        .pod_ready           (pod_ready_w)
    );

    // =========================================================================
    // HIU — Pod-level host interface unit
    // =========================================================================
    HIU #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_hiu (
        .clk                (clk),
        .rst                (rst),
        .virt_addr          (link_virt_addr_q),
        .dma_req            (dma_req_q),
        .dma_data_in        (dma_data_in_q),
        .interface_type     (interface_type_q),
        .ats_req            (ats_req_q),
        .pri_req            (pri_req_q),
        .shadow_write_start (shadow_write_start_q),
        .shadow_write_end   (shadow_write_end_q),
        .shadow_write_en    (shadow_write_en_q),
        .shadow_index       (shadow_index_q),
        .context_switch     (context_switch_q),
        .partition_id       (partition_id_q),
        .chacha_nonce       (chacha_nonce_q),
        .chacha_key         (chacha_key_q),
        .tlb_write_en       (tlb_write_en_q),
        .tlb_write_partition(tlb_write_partition_q),
        .tlb_write_index    (tlb_write_index_q),
        .tlb_write_virt     (tlb_write_virt_q),
        .tlb_write_phys     (tlb_write_phys_q),
        .phys_addr          (hiu_phys_addr_w),
        .dma_data_out       (hiu_dma_data_out_w),
        .dma_ack            (hiu_dma_ack_w),
        .access_granted     (hiu_access_granted_w),
        .ats_resp           (hiu_ats_resp_w),
        .pri_resp           (hiu_pri_resp_w),
        .tlb_fault          (hiu_tlb_fault_w),
        .tlb_fault_code     (hiu_tlb_fault_code_w),
        .rng_raw            (hiu_rng_raw_w),
        .rng_raw_valid      (hiu_rng_raw_valid_w),
        .rng_word           (hiu_rng_word_w),
        .rng_word_valid     (hiu_rng_word_valid_w),
        .trng_unhealthy     (hiu_trng_unhealthy_w)
    );

endmodule
