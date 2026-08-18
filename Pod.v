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
    // v1.5.1 §18 — Pod-level fragment header input; broadcast to selected
    // Cluster (only one Cluster active per cycle in this routing model).
    input  [7:0]                ext_frag_hdr,

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
    output                      any_lower_required,
    // v1.6.6 §22.14 / v1.9.2 §22.14b-3 — pod_ready = AND across all
    // clusters' ready. `cluster_ready` 의 의미가 §22.14b-3 에서 "출력단만"
    // 에서 "**출력단 + 입력단 skid 자리**" 로 바뀌었고, AND-reduce 는 그
    // 의미를 **자동 상속**한다 (여기 코드 변경 0줄).
    output                      pod_ready,
    // v1.9.2 §22.14b-3 — 입력단 skid overflow sticky fault, Pod 전 클러스터
    // OR-reduce. ready 체인과 달리 **fault 노출은 자동 상속이 아니다** —
    // Cluster 는 이것을 자기 `any_error_flag` 에 폴딩하지만, 그 경로만
    // 두면 "무언가 잘못됐다" 까지만 올라오고 **무엇이** 잘못됐는지는
    // Pod 경계에서 사라진다. 전용 포트를 손으로 배선하는 이유다.
    //
    // 대비 (정직 기록): `bank_tag_collision_error`(§26.5)는 오늘도
    // `cl_bank_collision` 으로 **흡수만** 하고 Pod 포트로 올리지 않는다.
    // 그 결정을 여기서 바꾸지는 않되(범위 밖), 두 fault 의 노출 수준이
    // 서로 다르다는 사실은 남겨 둔다.
    output                      any_input_skid_overflow,
    // v1.8.0e 3a-C4 §27.7a.3/§35.3 항 4 — FDOT32_CR unit fault, Pod 전
    // 클러스터 OR-reduce. `input_skid_overflow_error` 형을 복제한다
    // (`bank_tag_collision_error` 형의 **흡수**는 부족하다): Cluster 가
    // 이것을 자기 `any_error_flag` 에 폴딩하므로 그 경로만 두면
    // "무언가 잘못됐다" 까지만 올라오고 **무엇이** 잘못됐는지는 Pod
    // 경계에서 사라진다. reset-clearable sticky 라 OR-reduce 의 의미가
    // 명확하다 ("이 Pod 에서 리셋 이후 FDOT32_CR 유닛 결함이 있었다").
    //
    // **정직 명기 — 짝이 되는 `fdotcr_special_status` 는 여기 올리지
    // 않는다.** 그것은 sticky 가 아니라 **per-op** latch 이고 (§27.7a.3
    // 이 (결과, sticky) 쌍을 op 단위로 회수한다), 클러스터 4개를
    // OR-reduce 하면 어느 op 의 sticky 인지 귀속이 사라져 검사 (i) 이
    // 오히려 못 쓰게 된다. SDK audit 은 그것을 **Cluster 포트**에서
    // 읽는다. 흡수(absorb)조차 하지 않는 이유는 흡수할 대상이 없기
    // 때문이다 — 이 신호는 Pod 안에서 소비되지 않는다.
    output                      any_fdotcr_unit_fault
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
    /* verilator lint_off UNUSEDSIGNAL */
    // v1.5.3 §20 — Cluster's dedicated output-collision pulse. Currently
    // absorbed here (also folded into cl_error[]); v1.6+ may bubble it to
    // Pod's external interface for explicit fabric-collision reporting.
    wire                   cl_collision     [0:NUM_CLUSTERS-1];
    // v1.9 §26.5 — Cluster's bank tag-collision sticky fault. Already
    // folded into cl_error[] (Cluster.v's own any_error_flag), same
    // absorption pattern as cl_collision above; kept as its own wire for
    // the same future-bubble-to-Pod's-external-interface reason.
    wire                   cl_bank_collision [0:NUM_CLUSTERS-1];
    /* verilator lint_on UNUSEDSIGNAL */
    // v1.9.2 §22.14b-3 — Cluster 의 입력단 skid overflow sticky fault.
    // cl_collision / cl_bank_collision 과 달리 **흡수하지 않고** 아래
    // OR-reduce 로 Pod 포트까지 올린다 (fault 노출은 수동 배선).
    wire                   cl_skid_overflow [0:NUM_CLUSTERS-1];
    // v1.8.0e 3a-C4 §35.3 — Cluster 의 FDOT32_CR unit fault sticky.
    // cl_skid_overflow 와 같이 **흡수하지 않고** Pod 포트까지 올린다.
    wire                   cl_fdotcr_fault  [0:NUM_CLUSTERS-1];
    // v1.8.0e 3a-C4 §35.3 — 짝이 되는 per-op 관측 신호. Pod 안에 소비자가
    // 없고 OR-reduce 는 op 귀속을 파괴하므로 (포트 주석 참조) 여기서
    // 끊는다. 그래도 **결선은 남긴다** — 미접속으로 두면 Cluster 포트가
    // Pod 계층에서 존재 자체를 잃고, 계층 테스트가 짚을 좌표가 없어진다.
    //
    // **verilator UNUSEDSIGNAL 억제 프래그마를 일부러 걸지 않는다**
    // (v1.8.0e 3a-C4 적대 검수 2026-08-18). 이 주석이 그 프래그마의 철자를
    // 그대로 적지 않는 이유도 측정이다: 감사 한 줄짜리
    // `grep -c` census 가 주석까지 세어 있지도 않은 억제를 +1 로 보고한다.
    // 착지 당시에는 위 두 블록(:138-148 / cl_collision·
    // cl_bank_collision)의 파일-내 선례를 따라 프래그마 쌍으로 감쌌고, 그
    // 상태로 "새 프래그마는 1건도 추가하지 않았다" 고 보고했다 — **그 보고가
    // 틀렸다**. PE_Core 에서 한 쌍을 걷어내고 여기에 한 쌍을 넣어 트리
    // 순증감이 0 이었던 것을 "추가 0" 으로 잘못 요약한 것이다.
    //
    // 프래그마를 도로 넣는 대신 **경고를 세워 둔다**. 실측: 프래그마를 빼면
    // Pod 계층 `verilator -Wall` 의 UNUSEDSIGNAL 이 33 → 34 로 정확히 1건
    // 늘고(`cl_fdotcr_special`), 다른 경고 클래스는 전부 불변이다. 억제는
    // 이 신호가 소비되지 않는다는 사실을 **감추는** 쪽이고, 세워 두는 쪽은
    // 그것을 계속 보이게 한다 — 같은 착지에서 `PE_Core.v:1430`
    // (`fd_ing_q`) 의 신규 UNUSEDSIGNAL 도 억제하지 않고 보고했으므로
    // 그쪽과 취급도 일치한다. 파일-내 선례(:138-148)와 어긋나는 것은
    // 알면서 택한 것이다: spec §22.14b 는 "읽히는 순간 억제가 거짓이 된다"
    // 며 프래그마 **쌍 제거**의 선례를 이미 세웠다.
    //
    // 경고가 서 있으므로 "경고를 없애려고 이 wire 를 지운다" 가 다음 수순의
    // 유혹이 된다. 그것을 막는 것이 `test_pod.py` 의
    // `test_pod_fdotcr_special_status_stops_at_cluster` 다 — 결선 존재와
    // 비폴딩을 둘 다 assert 한다. 지우려면 그 테스트를 먼저 마주해야 한다.
    wire                   cl_fdotcr_special[0:NUM_CLUSTERS-1];
    wire                   cl_mem_req     [0:NUM_CLUSTERS-1];
    wire [ADDR_WIDTH-1:0]  cl_mem_addr    [0:NUM_CLUSTERS-1];
    wire                   cl_error       [0:NUM_CLUSTERS-1];
    wire                   cl_lower       [0:NUM_CLUSTERS-1];
    wire                   cl_ready       [0:NUM_CLUSTERS-1];   // v1.6.6

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
                    .ext_frag_hdr        (ext_frag_hdr),
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
                    .any_lower_required  (cl_lower[CIDX]),
                    .any_output_collision (cl_collision[CIDX]),
                    .cluster_ready       (cl_ready[CIDX]),
                    .bank_tag_collision_error (cl_bank_collision[CIDX]),
                    .input_skid_overflow_error (cl_skid_overflow[CIDX]),
                    .fdotcr_special_status     (cl_fdotcr_special[CIDX]),
                    .fdotcr_unit_fault_error   (cl_fdotcr_fault[CIDX])
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
    reg                  m_skid_overflow;   // v1.9.2 §22.14b-3
    reg                  m_fdotcr_fault;    // v1.8.0e 3a-C4 §35.3

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
        m_skid_overflow = 1'b0;
        m_fdotcr_fault  = 1'b0;
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
            m_skid_overflow = m_skid_overflow | cl_skid_overflow[i];
            m_fdotcr_fault  = m_fdotcr_fault  | cl_fdotcr_fault[i];
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
    assign any_input_skid_overflow = m_skid_overflow;   // v1.9.2 §22.14b-3
    assign any_fdotcr_unit_fault   = m_fdotcr_fault;    // v1.8.0e 3a-C4 §35.3
    // v1.6.6 §22.14 — pod_ready = AND across all clusters' ready.
    generate
        if (NUM_CLUSTERS > 0) begin : g_pod_ready
            integer pri;
            reg     pod_ready_r;
            always @(*) begin
                pod_ready_r = 1'b1;
                for (pri = 0; pri < NUM_CLUSTERS; pri = pri + 1)
                    pod_ready_r = pod_ready_r & cl_ready[pri];
            end
            assign pod_ready = pod_ready_r;
        end
    endgenerate

endmodule
