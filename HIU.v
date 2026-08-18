// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

`include "attributes.vh"

module HIU #(
    parameter ADDR_WIDTH = 64,
    parameter MAX_REGIONS = 16,
    parameter DATA_WIDTH = 32,
    parameter TLB_ENTRIES = 16,
    parameter NUM_PARTITIONS = 4,  // Partitioned TLB size (for cache attack resistance)
    // XChaCha20 라운드 수 (표준 = 20). **의미가 §30.7 에서 확정됐다**:
    // `round_counter` 는 이 값까지 세고 **1 cycle = 1 라운드 (quarter-round
    // 4개)** 다. 즉 20 cycle = 20 라운드 = double round 10회 — RFC 8439 의
    // ChaCha20 그대로다. 폐기 형태는 `< CHACHA_ROUNDS/2` = 10 cycle 을 돌면서
    // 그 10 cycle 이 double round 10회라고 **선언만** 했고 실물은 diagonal
    // round 10회였다 (§30.2 파급 1). 이 파라미터를 바꾸면 표준을 벗어난다.
    parameter CHACHA_ROUNDS = 20,
    parameter DUMMY_CYCLES = 8     // Constant-time dummy delay cycles
) (
    input clk,
    input rst,
    input [ADDR_WIDTH-1:0] virt_addr,
    input dma_req,
    input [DATA_WIDTH-1:0] dma_data_in,
    // ---- D7 처분 (spec §29.10) — 선언된 예약 포트 -------------------------
    // 지위: **RESERVED**. 호스트는 `2'b00` 으로 구동해야 하며 non-zero 는
    // 미정의다. 현 RTL 은 이 포트를 **읽지 않으므로 어떤 값도 동작을
    // 바꾸지 않는다** — 그 사실 자체가 계약이다 ("무시된다" 를 명시적으로
    // 약속한다). 합성기는 이것을 `WARNING: [Synth 8-7129] Port
    // interface_type[1]/[0] ... unconnected or has no load` 로 상시
    // 관측하며, 넷리스트 기여는 실측 0 이다 (§29.2 C6 — 래퍼의
    // `interface_type_q` 조차 셀 0개).
    //
    // 의도 복원 (§29.10): 호스트 **transport 종류 선택자**다. 인코딩
    // 화석 0=PCIe, 1=USB 가 `test_hiu.py` 주석에 남아 있었고, 2비트 =
    // 4종 (PCIe / USB / CXL / 예약) 이 `.claude-memos/sdk_architecture.md`
    // 의 `Transport` trait 서술 및 `remote_accelerator_access.md` 와
    // 정합한다.
    //
    // **승격 조건 (결선 금지의 해제 시점):** transport 별 ATS/PRI 자격
    // 계약이 spec 에 normative 로 기록되는 시점. 그 전에 결선하는 것은
    // 없는 행동을 발명하는 일이다 — HIU 에 transport 종속 행동이 하나도
    // 없고 ATS/PRI 는 이미 전용 포트로 처리된다.
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

    // ---- D4 실물화 (spec §29.4) — TLB fill control plane ------------------
    // 이 5개 입력이 D4 수리의 본체다. repo 존재 기간 전체에 걸쳐
    // partitioned TLB 를 채우는 유일한 메커니즘은 `test_hiu.py:24-26` 의
    // **계층 강제 기입**이었다 — 즉 RTL 에는 fill 경로가 아예 없었고
    // (최초 private commit 4d80c76 에도 없다), 저장소는 넷리스트에서
    // 전부 소멸했다 (`Synth 8-3848` × 128, 셀 0개). 호스트 기입 포트가
    // 그 공백을 계약으로 메운다.
    //
    // 프로토콜 (§29.4):
    //   1. 호스트가 아래 4개 payload 를 안정시킨 뒤 `tlb_write_en` 을
    //      1 cycle 어서트한다.
    //   2. HIU 가 IDLE 이면 다음 cycle 에 `TLB_UPDATE` 로 진입해 엔트리를
    //      설치하고 IDLE 로 복귀한다 (설치는 정확히 1 cycle).
    //   3. IDLE 이 아니면 **기입하지 않고** `tlb_fault` (code=BUSY) 를
    //      올린다. 조용한 드롭도 조용한 큐잉도 없다. 재시도는 호스트 책임.
    //   4. `shadow_write_en` 과 동시 어서트되면 **TLB 기입이 이긴다**
    //      (fault 아님 — 우선순위 규정). 조회 우선순위 (TLB > shadow) 와
    //      같은 방향인 것 자체가 규범이다 (§29.5).
    input tlb_write_en,
    input [$clog2(NUM_PARTITIONS)-1:0] tlb_write_partition,  // = tenant lease id
    input [$clog2(TLB_ENTRIES)-1:0]    tlb_write_index,      // direct-mapped 슬롯
    input [ADDR_WIDTH-1:0] tlb_write_virt,
    input [ADDR_WIDTH-1:0] tlb_write_phys,

    output reg [ADDR_WIDTH-1:0] phys_addr,

    // ---- loud-fault 관측면 (spec §29.6) -----------------------------------
    // **호스트 프로그래밍 오류 전용**이다. 변환 miss 는 여기 올리지
    // 않는다 — 관대함이 아니라 타이밍 채널 방지다 (§29.6 항 6):
    // miss 를 조기 스트로브로 알리면 hit/miss 가 시간으로 구별되어 HIU 의
    // 존재 이유가 무너진다. data plane 은 조용히 상수시간, control plane
    // 은 즉시 시끄럽게 — 이것이 규범 내용이다.
    output reg tlb_fault,            // 1-cycle 펄스
    output reg [2:0] tlb_fault_code, // 마지막 fault 사유, 다음 fault 까지 유지
    // D1 수리: `output reg` → `output` (암묵 wire).
    // 이 포트는 HIU 본체의 어떤 always 블록도 구동하지 않고, 오직
    // 서브모듈 dma_inst 의 출력에 직결된다 (아래 dma_engine 인스턴스).
    // Verilog-2001 은 reg 를 모듈 인스턴스 출력에 연결하는 것을 금지하며
    // Vivado 는 이것을 hard error 로 거부한다 — 계통 전체를 막던 유일한
    // 합성 차단 결함. wire 로 바꾸는 것은 의미 보존이다 (구동원 불변).
    output     [DATA_WIDTH-1:0] dma_data_out,
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

// =============================================================================
// Partitioned TLB — D4 실물화 (spec §29.3 / §29.5, 형태 (i′):
// 호스트 기입형 · direct-mapped · reset-free 저장)
//
// 폐기된 형태 (참고): `partitioned_tlb_{virt,phys,valid}
// [0:NUM_PARTITIONS-1][0:TLB_ENTRIES-1]` 2D 배열 3개. 8,256 bit 전부가
// undriven 이라 합성에서 소멸했고, 그 배열의 **행 주소 곱셈
// (p*TLB_ENTRIES + j) 48개가 gate anchor 의 premap `$mul` 429 안에
// phantom multiplier 로 들어앉아 있었다** (§29.11 별항 1). 아래 형태는
// 엔트리 주소를 연접으로 만들어 곱셈을 구조적으로 없앤다.
//
// 주소 분해 (PAGE_SHIFT = 12, 4 KiB 페이지):
//     tag         = virt_addr[63:16]   (48 bit)
//     index       = virt_addr[15:12]   ( 4 bit = $clog2(TLB_ENTRIES))
//     page offset = virt_addr[11:0]    (12 bit = PAGE_SHIFT)
// 엔트리 주소 = {partition, index} **연접** 6 bit — 곱셈 없음.
// =============================================================================
localparam PAGE_SHIFT = 12;
localparam TLB_IDX_W  = $clog2(TLB_ENTRIES);              // 4
localparam TLB_PART_W = $clog2(NUM_PARTITIONS);           // 2
localparam TLB_ADDR_W = TLB_PART_W + TLB_IDX_W;           // 6
localparam TLB_DEPTH  = NUM_PARTITIONS * TLB_ENTRIES;     // 64 (상수 접힘)
localparam TLB_PPN_W  = ADDR_WIDTH - PAGE_SHIFT;          // 52
localparam TLB_TAG_W  = ADDR_WIDTH - PAGE_SHIFT - TLB_IDX_W; // 48
localparam TLB_ENT_W  = TLB_TAG_W + TLB_PPN_W;            // 100

// `tlb_valid` — reset 이 반드시 필요한 **유일한** TLB 상태. async-reset
// 블록에 유지한다 (§29.5). AND 의 첫 항이자 유일한 자격 부여자다.
reg [TLB_DEPTH-1:0] tlb_valid;

// `tlb_mem` — {tag, ppn} = 100 bit × 64 word. async-reset **없는** 전용
// 동기 블록에 두고 `distributed` 로 못박는다 (§29.5 / §29.3 채택 이유 3·4):
//   * async-reset 블록 안이면 Vivado 가 RAM 추론을 거부하고
//     (`Synth 8-4767`) 레지스터로 펼친다 — 실측 LUT +2,492 / FF +7,940.
//   * `block` 을 쓰면 RAMB36 2개가 붙어 GATE S1 의 BRAM exact 축이
//     2 → 4 로 깨져 **즉시 FAIL** 이다. 힌트 하나가 gate 를 가른다.
(* ram_style = "distributed" *)
reg [TLB_ENT_W-1:0] tlb_mem [0:TLB_DEPTH-1];
reg [TLB_ENT_W-1:0] tlb_rd_q;   // 등록된 읽기 데이터 (TRANSLATE → TLB_READ)

// 호스트 기입 payload 샘플 (§29.4 프로토콜 1-2). IDLE 에서 1 cycle 만
// 안정하면 되도록 샘플해 둔다. reset-free — 유일한 소비 상태
// (`TLB_UPDATE`) 가 이 샘플을 쓰는 cycle 로만 도달하므로 read-before-write
// 가 구조적으로 불가능하다 (§29.7 (a) 판정).
reg [TLB_PART_W-1:0] tlb_wr_part_q;
reg [TLB_IDX_W-1:0]  tlb_wr_index_q;
reg [ADDR_WIDTH-1:0] tlb_wr_virt_q;
reg [ADDR_WIDTH-1:0] tlb_wr_phys_q;

// 변환 시퀀스 샘플 (§29.5) — TRANSLATE 에서 라이브 입력을 한 번만 읽고
// 이후 전 시퀀스는 샘플본만 쓴다.
reg [ADDR_WIDTH-1:0] xlat_virt;
reg                  xlat_tlb_valid;   // async-reset (자격 부여자)
reg                  xlat_shadow_hit;  // async-reset (자격 부여자)

// fault code 인코딩 (§29.6 표)
localparam [2:0] TLB_FAULT_NONE            = 3'd0,
                 TLB_FAULT_INDEX_MISMATCH  = 3'd1,
                 TLB_FAULT_PHYS_MISALIGNED = 3'd2,
                 TLB_FAULT_BUSY            = 3'd3,
                 TLB_FAULT_PARTITION_RANGE = 3'd4;
                 // 3'd5-3'd7 reserved

reg [ADDR_WIDTH-1:0] shadow_regions_start [0:MAX_REGIONS-1];
reg [ADDR_WIDTH-1:0] shadow_regions_end [0:MAX_REGIONS-1];
reg shadow_valid [0:MAX_REGIONS-1];

// XChaCha20 state
reg [31:0] chacha_state [0:15];  // Current working state
reg [31:0] initial_state [0:15]; // Initial state for final add
// D5 수리: `chacha_stream[0:15]` 삭제. 채워지기만 하고 어디서도 읽히지
// 않는 write-only 배열이었다 (grep 결과 선언 + CHACHA_FINAL 의 대입,
// 두 곳뿐). 주소 마스킹은 chacha_stream 을 경유하지 않고 CHACHA_FINAL
// 에서 chacha_state/initial_state 를 직접 더해 만든다. 합성 옵티마이저는
// 이미 이 16개 레지스터를 제거했으므로 넷리스트도 불변.
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
           CHACHA_FINAL = 4'b1101,
           // D4 실물화 신규 2상태 (§29.4 프로토콜 5). 기존 14 상태에
           // 이 둘을 배정하면 4-bit 공간이 정확히 소진되므로 **상태 폭은
           // 늘지 않는다**.
           TLB_UPDATE = 4'b1110,   // 호스트 기입 설치 (정확히 1 cycle)
           TLB_READ   = 4'b1111;   // 태그 비교 1회 + 우선순위 해소

reg [3:0] state;
reg [4:0] dummy_counter;
reg [4:0] round_counter;

integer i, m, ksh;

reg dma_ack_staged;

always @(*) begin
    dma_ack_staged = internal_dma_ack;
end

// =============================================================================
// TLB 조합 경로 (spec §29.5 / §29.6)
// =============================================================================

// 조회 주소 — 라이브 입력에서 만든다. `tlb_rd_q` 는 매 cycle 무조건
// 적재되고, TRANSLATE → TLB_READ 전이 edge 에 적재된 값만 소비된다.
// 같은 edge 에 `xlat_virt` / `xlat_tlb_valid` 도 같은 라이브 입력에서
// 샘플되므로 셋은 항상 정합한다.
wire [TLB_ADDR_W-1:0] tlb_raddr =
     {partition_id, virt_addr[PAGE_SHIFT+TLB_IDX_W-1:PAGE_SHIFT]};

wire [TLB_TAG_W-1:0] tlb_rd_tag = tlb_rd_q[TLB_ENT_W-1:TLB_PPN_W];
wire [TLB_PPN_W-1:0] tlb_rd_ppn = tlb_rd_q[TLB_PPN_W-1:0];

// **`valid` 가 AND 의 첫 항이자 유일한 자격 부여자다** (§29.6 항 1).
// `tlb_mem` 은 reset-free 이므로 power-up 값이 미정의이고, `FLUSH_TLB`
// 도 tag/ppn 을 지우지 않는다 — flush 후에도 RAM 에는 이전 tenant 의
// 데이터가 남아 있다. 따라서 이 게이팅은 power-up 1회의 규율이 아니라
// **영구 규율**이다. 구현자는 "flush 했으니 깨끗하다" 를 가정할 수 없다.
wire tlb_hit_w = xlat_tlb_valid &&
     (tlb_rd_tag == xlat_virt[ADDR_WIDTH-1:PAGE_SHIFT+TLB_IDX_W]);

// 호스트 기입 검증 (§29.6 항 5) — 샘플본에 대해 판정한다.
wire [TLB_IDX_W-1:0] tlb_wr_virt_index =
     tlb_wr_virt_q[PAGE_SHIFT+TLB_IDX_W-1:PAGE_SHIFT];
wire tlb_wr_index_err = (tlb_wr_index_q != tlb_wr_virt_index);
wire tlb_wr_phys_err  = (tlb_wr_phys_q[PAGE_SHIFT-1:0] != {PAGE_SHIFT{1'b0}});
// 폭이 아니라 **값**으로 비교한다 — `tlb_wr_part_q >= NUM_PARTITIONS` 로
// 쓰면 NUM_PARTITIONS 가 포트 폭으로 잘려 항상 참이 된다. NUM_PARTITIONS
// = 4 인 현 형상에서는 이 항이 상수 0 으로 접혀 셀을 만들지 않는다.
wire [31:0] tlb_wr_part_ext = {{(32-TLB_PART_W){1'b0}}, tlb_wr_part_q};
wire tlb_wr_part_err = (tlb_wr_part_ext >= NUM_PARTITIONS);
wire tlb_wr_ok = !(tlb_wr_index_err || tlb_wr_phys_err || tlb_wr_part_err);
wire [TLB_ADDR_W-1:0] tlb_waddr = {tlb_wr_part_q, tlb_wr_index_q};
wire tlb_install_w = (state == TLB_UPDATE) && tlb_wr_ok;

// shadow 16-way 비교 — TRANSLATE 에서 1회 확정해 레지스터에 담는다.
reg shadow_hit_c;
always @(*) begin
    shadow_hit_c = 1'b0;
    for (ksh = 0; ksh < MAX_REGIONS; ksh = ksh + 1) begin
        if (shadow_valid[ksh] && (virt_addr >= shadow_regions_start[ksh])
                              && (virt_addr <= shadow_regions_end[ksh])) begin
            shadow_hit_c = 1'b1;
        end
    end
end

// =============================================================================
// 주 FSM — async-reset 블록.
//
// D6 (spec §29.7) 처분: 이 블록이 **쓰는 모든 레지스터는 rst 분기에서
// 대입된다**. 대입되지 않던 66개 (shadow_regions_start/end 32 +
// chacha_state 16 + initial_state 16 + masked_phys_addr 1 + phys_addr 1)
// 중 `phys_addr` 은 **형식2** (rst 대입 추가) 로 여기 남고, 나머지 65개는
// **형식3** (아래 reset-free 전용 블록으로 분리) 이다.
//
// 왜 형식1 (`if (!rst)` 가드 블록 분리) 이 아닌가 — §29.7 명시 기각:
// `if (!rst)` 는 그대로 CE 로 접혀 `rst → LUT → FF.CE` 동기 경로가
// 남는다. 그런데 그 경로는 XDC 가 false_path 로 빼 놓아 **타이밍이
// 검증되지 않은 채 실리콘에서 데이터 캡처를 게이팅한다.** 형식1 은
// 메시지만 없애고 위험을 남긴다. 결정적 근거: 현재 넷리스트가 이미
// 형식1 이다 (Vivado 가 그 변환을 이미 수행했고, 그래도 위험이 남았다).
// =============================================================================
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
        phys_addr <= {ADDR_WIDTH{1'b0}};   // D6 형식2 (§29.7) + §29.6 부수 규범
        tlb_valid <= {TLB_DEPTH{1'b0}};
        tlb_fault <= 1'b0;
        tlb_fault_code <= TLB_FAULT_NONE;
        xlat_tlb_valid <= 1'b0;
        xlat_shadow_hit <= 1'b0;
        for (i = 0; i < MAX_REGIONS; i = i + 1) begin
            shadow_valid[i] <= 0;
        end
    end else begin
        if (dma_req && (state == IDLE)) dma_req_pending <= 1;  // dma_req 캡처 강화 (IDLE에서만, 하지만 dma_req 입력 즉시)
        if (context_switch) state <= FLUSH_TLB;
        case (state)
            IDLE: begin
                // §29.4 프로토콜 4 — TLB 기입이 shadow 기입을 이긴다.
                // 조회 우선순위 (TLB > shadow) 와 **같은 방향**인 것
                // 자체가 규범이다 (§29.5).
                if (tlb_write_en) state <= TLB_UPDATE;
                else if (shadow_write_en) state <= SHADOW_UPDATE;
                else if (dma_req_pending) state <= TRANSLATE;
                else if (ats_req) state <= ATS_QUERY;
                else if (pri_req) state <= PRI_REQUEST;
            end
            TLB_UPDATE: begin
                // 설치는 정확히 1 cycle. 관측 가능한 부작용은 해당
                // 엔트리의 valid/tag/ppn 뿐이다 (§29.4 프로토콜 2).
                // 검증 실패 4종은 **기입을 수행하지 않고** 아래 fault
                // 단일 지점에서 소리를 낸다 (§29.6 항 5).
                if (tlb_wr_ok) tlb_valid[tlb_waddr] <= 1'b1;
                state <= IDLE;
            end
            SHADOW_UPDATE: begin
                if ({1'b0, shadow_index} < 5'd16) begin
                    shadow_valid[shadow_index] <= 1;
                end
                state <= IDLE;
            end
            TRANSLATE: begin
                // cycle 1 — 라이브 입력을 **한 번만** 읽는다. 이후 전
                // 시퀀스 (조회·마스킹·DMA) 는 샘플본만 쓴다.
                access_granted <= 0;
                dummy_counter <= 0;
                xlat_tlb_valid  <= tlb_valid[tlb_raddr];
                xlat_shadow_hit <= shadow_hit_c;
                state <= TLB_READ;
            end
            TLB_READ: begin
                // cycle 2 — 태그 비교 1회로 우선순위를 해소한다.
                //
                // **우선순위 규범 (§29.5): TLB 히트가 이기고 shadow 는
                // fallback 전용이다.** 폐기된 형태의 `if (!access_granted)`
                // 가드는 죽은 코드였다 — `access_granted` 는 TRANSLATE
                // 진입 시점에 **항상 0** 이므로 shadow 루프가 항상 돌고,
                // 같은 always 블록의 **나중 대입인 shadow 가 TLB 를
                // 덮었다.** 즉 TLB 를 실체화하는 순간 shadow region 과
                // 겹치는 TLB 엔트리가 조용히 identity-map 으로 강등되는
                // **tenant 격리 구멍**이 열린다 (verilator 실증:
                // 중첩 shadow → SHADOW_OVERRIDES).
                //
                // 그래서 조건을 고치는 것이 아니라 **단일 if/else if/else
                // 사슬로 대체**한다 — 조건만 고치면 나중-대입 규칙이
                // 다시 함정이 된다.
                if (tlb_hit_w) begin
                    phys_addr <= {tlb_rd_ppn, xlat_virt[PAGE_SHIFT-1:0]};
                    access_granted <= 1'b1;
                end else if (xlat_shadow_hit) begin
                    phys_addr <= xlat_virt;
                    access_granted <= 1'b1;
                end else begin
                    // §29.6 부수 규범 — miss 시 0 으로 **구동**한다.
                    // 폐기된 형태는 miss 에 phys_addr 를 대입하지 않아
                    // 직전 변환 결과가 모듈 출력에 남았고 `Top_Core.v`
                    // 가 그것을 `mem_phys_addr` 로 외부에 노출했다.
                    // "소비자가 access_granted 로 거른다" 는 계약은 spec
                    // 어디에도 쓰인 적이 없다.
                    phys_addr <= {ADDR_WIDTH{1'b0}};
                    access_granted <= 1'b0;
                end
                state <= DUMMY_DELAY;  // Constant-time dummy always
            end
            DUMMY_DELAY: begin
                if (dummy_counter == DUMMY_CYCLES - 1) begin
                    state <= CHACHA_H_INIT;
                end
                dummy_counter <= dummy_counter + 1;
            end
            // ---- XChaCha20 4상태 --------------------------------------------
            // `chacha_state` / `initial_state` / `masked_phys_addr` 의 대입은
            // D6 형식3 으로 아래 reset-free 블록으로 옮겼다. 여기 남는 것은
            // reset 되는 제어 상태 (`round_counter` / `subkey` / `state`)
            // 뿐이며, 두 블록은 같은 `state` 디코드를 본다.
            CHACHA_H_INIT: begin  // HChaCha20 initialization (subkey derivation)
                round_counter <= 0;
                state <= CHACHA_H_MASK;
            end
            CHACHA_H_MASK: begin  // HChaCha20 rounds
                // §30.7 부분 편집 함정 1: `< CHACHA_ROUNDS / 2` 를 그대로
                // 두면 20 라운드가 아니라 double round 5회가 된다.
                if (round_counter < CHACHA_ROUNDS) begin
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
                round_counter <= 0;
                state <= CHACHA_MASK;
            end
            CHACHA_MASK: begin  // ChaCha20 rounds
                if (round_counter < CHACHA_ROUNDS) begin   // §30.7 함정 1
                    round_counter <= round_counter + 1;
                end else begin
                    state <= CHACHA_FINAL;
                end
            end
            CHACHA_FINAL: begin
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
                // §29.5 flush 규범 — `tlb_valid` 64비트 전체와
                // `shadow_valid` 16비트를 지운다. **`tlb_mem` 의 tag/ppn
                // 데이터는 지우지 않는다** (reset-free RAM 이라 지울 수단이
                // 없고, 지울 필요도 없다). 이것이 §29.6 의 존재 이유다:
                // flush 후에도 RAM 에는 이전 tenant 의 데이터가 남아 있고
                // `valid` 가 유일한 방벽이다.
                //
                // 이월 D9 (§29.9): `context_switch` 하나가 **전 파티션**을
                // 지운다 = tenant A 의 context switch 가 tenant B 의 변환을
                // 무효화한다 (가용성 측면 cross-tenant 영향). 수리는
                // Y4 `hiu_abi.md` 의 lease-rotation 계약 변경을 요구하므로
                // 본 commit 범위 밖이며, 현행 의미 (전역 flush) 를 규범으로
                // 명시해 둔다 — 조용히 두지 않는다.
                tlb_valid <= {TLB_DEPTH{1'b0}};
                for (i = 0; i < MAX_REGIONS; i = i + 1) begin
                    shadow_valid[i] <= 0;
                end
                state <= IDLE;
            end
            default: state <= IDLE;
        endcase

        // ---- control-plane loud fault (§29.6 항 5) ------------------------
        // **단일 지점**에 두어 우선순위를 한 곳에 고정한다 (case 뒤에
        // 있으므로 case 안의 어떤 대입보다 나중이다). `tlb_fault` 는
        // 기본 0 = 1-cycle 펄스이고, `tlb_fault_code` 는 fault 가 났을
        // 때만 갱신되어 다음 fault 까지 유지된다.
        //
        // 우선순위 BUSY > INDEX_MISMATCH > PHYS_MISALIGNED >
        // PARTITION_RANGE. 두 사유가 같은 cycle 에 성립해도 `tlb_fault`
        // 는 반드시 올라가므로 **조용히 드롭되는 거절은 없다** — 코드가
        // 하나로 좁혀질 뿐이다.
        tlb_fault <= 1'b0;
        if (tlb_write_en && (state != IDLE)) begin
            tlb_fault      <= 1'b1;
            tlb_fault_code <= TLB_FAULT_BUSY;
        end else if ((state == TLB_UPDATE) && tlb_wr_index_err) begin
            // direct-mapped 에서 index 가 tag 와 어긋난 엔트리는 **어떤
            // 주소로도 조회될 수 없다.** 조용히 설치하면 호스트는
            // 매핑했다고 믿고 하드웨어는 영원히 miss 한다 — D4 와 같은
            // 종류의 "선언과 실물의 괴리" 다.
            tlb_fault      <= 1'b1;
            tlb_fault_code <= TLB_FAULT_INDEX_MISMATCH;
        end else if ((state == TLB_UPDATE) && tlb_wr_phys_err) begin
            tlb_fault      <= 1'b1;
            tlb_fault_code <= TLB_FAULT_PHYS_MISALIGNED;
        end else if ((state == TLB_UPDATE) && tlb_wr_part_err) begin
            // NUM_PARTITIONS = 4 인 현 형상에서는 2-bit 포트라 **구조적으로
            // 발생 불가**이나, 파라미터가 4 미만으로 재형상되면 발생한다.
            // 조건을 지금 적어 두는 것이 재형상 시의 조용한 실패를 막는다.
            tlb_fault      <= 1'b1;
            tlb_fault_code <= TLB_FAULT_PARTITION_RANGE;
        end
    end
end

// =============================================================================
// D6 형식3 — async-reset **없는** 전용 동기 블록 (spec §29.7)
//
// 여기 있는 레지스터는 전부 (a) 판정이다: 기입 enable 이 FSM state 디코드
// 종속이고 `state` 는 async-reset (rst 중 IDLE 고정) 이므로 **rst 중에
// enable 이 1 이 될 수 없음이 구조적으로 증명**된다. 읽기는 전부 reset
// 되는 자격 비트로 가드된다 (shadow_valid / tlb_valid / state 도달성).
// 파형·값 불변이면서 `rst → LUT → FF.CE` 조합 경로를 없애는 유일한 형식.
//
// `tlb_mem` 이 이 블록에 있는 것은 선택이 아니라 **필수**다 —
// async-reset 블록 안이면 Vivado 가 RAM 추론을 원천 거부한다
// (`Synth 8-4767`). 즉 D4 실물화가 D6 수리를 강제한다 (§29.3 채택 이유 4).
// =============================================================================

// HChaCha20 / ChaCha20 초기 상태 — 조합으로 확정되는 값이므로
// `initial_state` 를 **경유하지 않고** 같은 cycle 에 두 배열에 병렬
// 대입한다. 이것이 D8 수리다 (§29.8): 폐기된 형태는 같은 블록·같은
// cycle 에 `initial_state[*] <= 상수/키/nonce` 와 `chacha_state[m] <=
// initial_state[m]` 을 함께 수행했고, 비차단 대입이라 RHS 가 **직전
// 값**이었다. 결과는 첫 사이클만의 문제가 아니라 **영구적 1단계
// 어긋남**이었다 — subkey 가 HChaCha20 사양대로 유도되지 않고 ChaCha20
// 라운드가 subkey 상태 위에서 돌지 않는다. 즉 마스크가 XChaCha20
// 키스트림이 아니었다. golden: `scripts/golden_xchacha.py`.
//
// **§30 정정 — D8 은 결함 1건이 아니라 3건의 묶음이었다.** 위 문단이 고친
// 것은 그중 D8-0 뿐이고, 그것을 고쳐도 결론 (*"마스크는 XChaCha20
// 키스트림이 아니다"*) 은 그대로 참으로 남았다. 나머지 둘은 이 commit 이
// 처분한다:
//   * **D8-A** — 2단 ChaCha20 의 nonce 워드 배치가 draft §2.3 위반
//     (`c_init_w[13..15]`, 아래).
//   * **D8-B** — 8 quarter-round 병렬 계산으로 column round 전량 소실
//     (`CHACHA_H_MASK` / `CHACHA_MASK` 의 라운드 datapath, 아래).
// 셋을 함께 고쳐야 값이 표준이 된다 — D8-A 만 고치면 nonce tail 64비트 중
// 32비트가 여전히 죽는다 (§30.3 통제 실험). 값 계약은 §30.6, 실측 근거는
// §30.4, 벡터는 `include/generated/xchacha_vectors.hex` 다.
wire [31:0] h_init_w [0:15];
wire [31:0] c_init_w [0:15];

assign h_init_w[0]  = 32'h61707865;
assign h_init_w[1]  = 32'h3320646e;
assign h_init_w[2]  = 32'h79622d32;
assign h_init_w[3]  = 32'h6b206574;
assign h_init_w[4]  = chacha_key[31:0];
assign h_init_w[5]  = chacha_key[63:32];
assign h_init_w[6]  = chacha_key[95:64];
assign h_init_w[7]  = chacha_key[127:96];
assign h_init_w[8]  = chacha_key[159:128];
assign h_init_w[9]  = chacha_key[191:160];
assign h_init_w[10] = chacha_key[223:192];
assign h_init_w[11] = chacha_key[255:224];
assign h_init_w[12] = chacha_nonce[31:0];    // nonce[0:3] bytes
assign h_init_w[13] = chacha_nonce[63:32];   // nonce[4:7]
assign h_init_w[14] = chacha_nonce[95:64];   // nonce[8:11]
assign h_init_w[15] = chacha_nonce[127:96];  // nonce[12:15]

assign c_init_w[0]  = 32'h61707865;
assign c_init_w[1]  = 32'h3320646e;
assign c_init_w[2]  = 32'h79622d32;
assign c_init_w[3]  = 32'h6b206574;
assign c_init_w[4]  = subkey[31:0];
assign c_init_w[5]  = subkey[63:32];
assign c_init_w[6]  = subkey[95:64];
assign c_init_w[7]  = subkey[127:96];
assign c_init_w[8]  = subkey[159:128];
assign c_init_w[9]  = subkey[191:160];
assign c_init_w[10] = subkey[223:192];
assign c_init_w[11] = subkey[255:224];
// ---- D8-A 수리 (spec §30.6 항 2) --------------------------------------
// draft-irtf-cfrg-xchacha-03 §2.3: 2단 ChaCha20 의 12바이트 nonce 는
// `4 NUL || nonce[16:24]` 다. 따라서 `[13]` 은 **0** 이고 nonce 바이트
// 16-23 은 `[14]`/`[15]` 로 간다.
//
// 폐기 배치 (`[13]=nonce[16:20], [14]=nonce[20:24], [15]=0`) 는 표준
// 위반이었다. libsodium 계열의 64-bit counter 표기로 봐도 counter 상위
// 32비트 = `[13]` = 0 이므로 값이 같다 (§30.4 anchor 조사).
assign c_init_w[12] = 32'h00000000;          // counter = 0 (하위 32b)
assign c_init_w[13] = 32'h00000000;          // counter 상위 32b = 4 NUL
assign c_init_w[14] = chacha_nonce[159:128]; // nonce 바이트 16-19
assign c_init_w[15] = chacha_nonce[191:160]; // nonce 바이트 20-23

always @(posedge clk) begin
    // ---- shadow region 데이터 (교과서적 data/valid 쌍; valid 는 reset) --
    if ((state == SHADOW_UPDATE) && ({1'b0, shadow_index} < 5'd16)) begin
        shadow_regions_start[shadow_index] <= shadow_write_start;
        shadow_regions_end[shadow_index]   <= shadow_write_end;
    end

    // ---- TLB 기입 payload 샘플 (§29.4 프로토콜 1-2) --------------------
    if ((state == IDLE) && tlb_write_en) begin
        tlb_wr_part_q  <= tlb_write_partition;
        tlb_wr_index_q <= tlb_write_index;
        tlb_wr_virt_q  <= tlb_write_virt;
        tlb_wr_phys_q  <= tlb_write_phys;
    end

    // ---- TLB 저장소 — 1 write / 1 registered read ----------------------
    // 기입은 검증을 통과한 설치에서만 일어난다 (`tlb_install_w`).
    // 읽기는 매 cycle 무조건 수행되고, TRANSLATE → TLB_READ 전이 edge 에
    // 적재된 값만 `tlb_hit_w` 가 소비한다.
    if (tlb_install_w) begin
        tlb_mem[tlb_waddr] <= {tlb_wr_virt_q[ADDR_WIDTH-1:PAGE_SHIFT+TLB_IDX_W],
                               tlb_wr_phys_q[ADDR_WIDTH-1:PAGE_SHIFT]};
    end
    tlb_rd_q <= tlb_mem[tlb_raddr];

    // ---- 변환 시퀀스 샘플 ----------------------------------------------
    if (state == TRANSLATE) begin
        xlat_virt <= virt_addr;
    end

    // ---- XChaCha20 상태 (D8 수리 포함) ---------------------------------
    case (state)
        CHACHA_H_INIT: begin
            for (m = 0; m < 16; m = m + 1) begin
                chacha_state[m]  <= h_init_w[m];
                initial_state[m] <= h_init_w[m];
            end
        end
        CHACHA_INIT: begin
            for (m = 0; m < 16; m = m + 1) begin
                chacha_state[m]  <= c_init_w[m];
                initial_state[m] <= c_init_w[m];
            end
        end
        // ---- D8-B 수리 (spec §30.6 항 3 / §30.7 형태 (A)) ----------------
        //
        // 폐기 형태는 **같은 arm 안에서 8개 quarter-round 를 전부 기술**했다.
        // `chacha_qr_func` 는 레지스터 `chacha_state` 를 직접 읽고 대입은
        // 비차단이므로 8개 전부가 **직전 상태**에서 계산됐고, diagonal 4쌍의
        // 목적지 인덱스 합집합이 정확히 {0..15} 라 **column round 결과가
        // 전량 덮였다.** 결과: 1 cycle = diagonal round 1회, 상태가 영구히
        // 4그룹 {0,5,10,15}/{1,6,11,12}/{2,7,8,13}/{3,4,9,14} 로 분해되고
        // 10 라운드 내내 그룹 간 혼합이 0 이었다 (§30.4 실측).
        //
        // 형태 (A) — **cycle 당 라운드 1개** (quarter-round 4개), 위상은
        // `round_counter[0]` 이 고른다. column 이 먼저다 (`CHACHA_*_INIT`
        // 직후 `round_counter <= 0`). 20 cycle = 20 라운드 = double round
        // 10회 = RFC 8439 ChaCha20.
        //
        // 왜 (A) 인가 (§30.7): 한 cycle 안에 column→diagonal 을 직렬로 잇는
        // 형태 (B) 는 quarter-round 의 의존 덧셈 사슬을 4단 → 8단으로 늘려
        // **setup(WNS/Fmax) 축을 직접 때린다.** (A) 는 조합 깊이가 불변이고
        // (출력 되쓰기 2:1 mux 1단만 추가), 비용은 단 당 +10 cycle 뿐이다.
        //
        // **정확성 근거 (비차단 대입이 이제 안전한 이유):** 한 arm 안의
        // 4개 quarter-round 는 목적지 인덱스가 서로소이고 (column 은 열,
        // diagonal 은 대각), 표준 정의상 **한 라운드의 4개 quarter-round 는
        // 서로 독립**이다. 즉 전부 직전 상태에서 읽는 것이 규범 그대로다.
        // 폐기 형태의 결함은 비차단 대입 자체가 아니라 **서로 의존하는 두
        // 라운드를 같은 cycle 에 병렬로 놓은 것**이었다.
        //
        // 두 단(HChaCha20 / ChaCha20)이 **같은 case arm 을 공유**한다.
        // 둘은 같은 `chacha_state` 위의 같은 연산이므로 폐기 형태에서도
        // 값은 같았고 공유 여부는 합성기 재량이었다 — §30.9 cut ladder (b)
        // 를 선제 적용해 공유를 **텍스트로 고정**한다 (값 계약 불변).
        CHACHA_H_MASK, CHACHA_MASK: begin
            if (round_counter < CHACHA_ROUNDS) begin
                if (round_counter[0] == 1'b0) begin
                    // column round — 4개 열
                    {chacha_state[0], chacha_state[4], chacha_state[8],  chacha_state[12]} <= chacha_qr_func(0, 4, 8,  12);
                    {chacha_state[1], chacha_state[5], chacha_state[9],  chacha_state[13]} <= chacha_qr_func(1, 5, 9,  13);
                    {chacha_state[2], chacha_state[6], chacha_state[10], chacha_state[14]} <= chacha_qr_func(2, 6, 10, 14);
                    {chacha_state[3], chacha_state[7], chacha_state[11], chacha_state[15]} <= chacha_qr_func(3, 7, 11, 15);
                end else begin
                    // diagonal round — 4개 대각
                    {chacha_state[0], chacha_state[5], chacha_state[10], chacha_state[15]} <= chacha_qr_func(0, 5, 10, 15);
                    {chacha_state[1], chacha_state[6], chacha_state[11], chacha_state[12]} <= chacha_qr_func(1, 6, 11, 12);
                    {chacha_state[2], chacha_state[7], chacha_state[8],  chacha_state[13]} <= chacha_qr_func(2, 7, 8,  13);
                    {chacha_state[3], chacha_state[4], chacha_state[9],  chacha_state[14]} <= chacha_qr_func(3, 4, 9,  14);
                end
            end
        end
        CHACHA_FINAL: begin
            // D5 수리: 여기 있던 `chacha_stream[m] <= ...` 16-way 루프를
            // 삭제했다. 키스트림 워드는 이 마스크 계산이 직접 재현하므로
            // (word0/word1 = state+initial) 관측 가능한 동작은 동일하다.
            masked_phys_addr <= phys_addr ^ {
                chacha_state[1] + initial_state[1],
                chacha_state[0] + initial_state[0]
            };  // 64-bit mask
        end
        default: ;  // 그 외 상태에서는 이 블록이 아무것도 하지 않는다
    endcase
end

// =============================================================================
// 4-state X 규율 (spec §29.6 항 4) — 시뮬 측 loud-fault.
//
// X 를 지원하는 시뮬레이터에서 미기입 `tlb_mem` 은 X 다. `tlb_hit_w` 가
// X 가 되어 `access_granted` 로 전파되면 안 된다 — 방어는 `xlat_tlb_valid`
// 게이팅이고, 이 assert 는 그 방어가 깨졌을 때 조용히 넘어가지 않게 한다.
// `SIM ?= verilator` (Makefile:13) 는 2-state 이므로 여기서는 발화하지
// 않는다 — 이 검사가 겨냥하는 것은 4-state 흐름 (`make SIM=icarus`) 이다.
// =============================================================================
`ifdef WT_SIM_ASSERT
always @(posedge clk) begin
    if (!rst && (state == TLB_READ) && (tlb_hit_w === 1'bx)) begin
        $display("HIU FATAL: tlb_hit_w is X in TLB_READ — valid gating broke (spec 29.6 item 4)");
        $fatal;
    end
end
`endif

// ChaCha20 quarter-round (RFC 8439 §2.1). 반환 = {xa, xb, xc, xd}.
//
// **이 function 은 레지스터 `chacha_state` 를 직접 읽는다.** 즉 같은 cycle
// 의 다른 호출이 만든 값을 볼 수 없고, 전부 **직전 상태**에서 계산된다.
// 그 성질이 D8-B 의 원인이었으므로 호출 규율을 여기 못박는다:
//
//   **한 cycle 에는 같은 라운드에 속하는 4개만 호출할 것.** column 4개
//   (열) 또는 diagonal 4개 (대각) 중 하나다. 이 4개는 표준 정의상 서로
//   독립이고 목적지 인덱스가 서로소이므로 직전 상태 읽기가 규범 그대로다.
//   서로 **의존하는** 두 라운드를 같은 cycle 에 놓으면 (폐기 형태) 뒤에
//   적힌 라운드가 앞을 전량 덮는다 — 조용히, 시뮬레이션 경고 없이.
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