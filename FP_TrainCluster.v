// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

`include "attributes.vh"

// =============================================================================
// FP_TrainCluster.v — v2.0 TRAIN 누산 datapath 구조 합성체 (GATE V20-3 대상 top)
//
// spec §27.6 "④ GATE V20-3 기준 선공표" 블록 (2026-08-17) 이 본 구현의
// normative 계약이다. scope = FMA lane 곱 원천 x8 + FP_AccLattice x1 (N=8)
// + FP_AccBank x1 + beat dispatch 스켈레톤 + FILL/DRAIN/ZERO 명령 경로.
// 제외 (④ 명시): FDOT32_CR(0x7A), TRAIN ISA 결선 (0x7D/0x7E decode →
// dispatch), SR/Adam. "스켈레톤" 의 의미 그대로 — ISA decode 로부터의
// 결선이 아니라 TB-구동 가능한 dispatch 인터페이스까지가 본 top 의 범위.
// 통합 TB 는 다음 phase 몫 (본 COMMIT 은 컴파일·elaboration 확인까지).
//
// binding (전사 — 기준 수치는 §27.6 ④ 블록의 무수정 전사여야 한다):
//   LUT hard ceiling 35,377 / DSP48E2 정확히 8 / premap `$mul` 정확히 8 /
//   BRAM 0 / DRC errors 0; Fmax/WNS 는 기록 축.
//
// -----------------------------------------------------------------------------
// 곱 원천 — 전단 tap 채택 (선택과 근거; §27.6 ④ scope "lane 형상 주기" 항)
// -----------------------------------------------------------------------------
// ** FP_FmaLaneBf16 전체 인스턴스가 아니라 wide-product 전단 tap 을 채택한다
// (FP_TrainLaneTap — 본 파일 하단, FP_FmaLaneBf16.v S1/S2/static-align 의
// 문자 그대로 승계). ** 근거 2건:
//   (1) 형식 정합 — tap 산출이 §27.2 raw product 형식 그 자체다: bf16
//       8x8→16-bit significand 곱 <<32 / f16 11x11→22-bit <<26 은 양쪽 다
//       [2^46, 2^48) 에 정적 착지 (1-bit un-normalized 허용 — lattice fault
//       (c) 곱-lane 약형의 그 허용), p_exp = ea_eff + eb_eff + 1 은 signed
//       11-bit 수납 (bf16 [-251,255] / f16 [-47,31]), zero 곱은 canonical
//       zero field (64'h0400_0000_0000_0000) — lattice field 인코딩
//       ([63:60]=0 / [59]=s / [58:48]=e / [47:0]=sig) 과 bit-정합이며
//       lattice fault (a)/(b)/(c)/(d)/(e) 어느 것도 정상 경로에서 발화하지
//       않는다 (bf16 최저 q=16 의 PHYS[47:0] 침범은 곱 하위 32 bit 구조적
//       0 으로 소거 — §27.2.1 "bf16 곱 LSB weight 2^-266" 그 산술).
//   (2) 구조 — 전체 lane 의 출력은 RN(a*b + c) 의 fp32 (PACK_FINAL 후단
//       포함) 라 lattice addend 원천이 될 수 없다. 옵션 3 의 in-dot 경로에
//       per-lane 후단 누산은 존재하지 않는다 (§27.2.1 — in-dot 반올림 0회).
//       per-lane FP_AddWide 후단 (776 중 617 LUT) 은 본 top 에 미인스턴스.
//   anchor 기록 의무 (§27.6 ④): LUT anchor 는 측정 실물인 전체 lane 776 을
//   쓴다 — ceiling 은 상한이며, 전단 tap 채택으로 실측이 anchor 를 하회할
//   것이고 그 사실은 gate 기록에 남긴다. premap `$mul` = tap 당 정확히 1
//   (the ONE 11x11 significand multiplier — FP_FmaLaneBf16.v C1 명문 승계)
//   x 8 lanes = 8; lattice 0 / bank 0 실측 — 합 정확히 8, 형상 불문 불변.
//
// -----------------------------------------------------------------------------
// 시간 구조 (IF-1 정렬 — tap 전단 latency 2 를 issue 파이프가 흡수한다)
// -----------------------------------------------------------------------------
//   cycle t      : wave_v_i 수용 (스트리머 idle 시) — beat 0 operand (pair
//                  0..7) 를 tap 에 인가; slot/stream 은 issue 파이프에 등록.
//   t+1 .. t+3   : beat 1..3 operand (pair 8..15 / 16..23 / 24..31) 인가.
//   t+2          : tap S2 → beat 0 raw product; 같은 cycle 에 내부 OP_WAVE
//                  가 bank cmd port 에 인가된다. ** 이 cycle 이 bank 판정
//                  cycle 이자 (수용 시) lat_start_o = lattice beat 0 = IF-2
//                  ownership window 의 start (offset 0) 다. ** bank 는 carry
//                  word read 를 이 cycle 에 완료해 lat_carry_o 로 공급한다
//                  (IF-1 read-before-dispatch — FF array 조합 read).
//   t+2 .. t+5   : lattice beat 0..3 소비 (곱 8개/beat — lane idle 0).
//   t+9          : lattice done_q (= bank-start t+2 + LATENCY 7) — wide/fp32
//                  관측 + bank writeback (lat_fault 시 억제 + sticky).
//   t+10         : bank word 상태 (dbg_*) 에서 writeback 관측 가능.
// 상류 (TB) 스케줄 입력 제약 (§27.2.2 IF-3 의 승계 — bank-start 간격이
// 계약 기준이고 issue 지연이 상수 2 이므로 wave_v_i 간격도 동일 산술):
//   * 서로 다른 slot: wave_v_i 간격 >= 4 (II=4 — 스트리머가 미만을 거부).
//   * 같은 slot 체이닝: wave_v_i 간격 >= 7 (bank IF-3 이 bank-start 간격
//     >= LATENCY=7 로 강제 — 미만은 WAVE_WINDOW 거부+sticky).
//
// -----------------------------------------------------------------------------
// ** offset-0 중재 pin (③ 이월 커버리지 경계 (i) 의 RTL 폐쇄 — §27.6 ④
// 검증 의무 1(i) 의 그 중재) **
// -----------------------------------------------------------------------------
// bank cmd port 는 cycle 당 1 명령이다 (golden §2 형식 규율). 본 top 은 그
// port 앞에 2-원천 중재기를 둔다: 내부 WAVE issue (wave_v_i + 2) vs 외부
// cmd surface (cmd_*_i). 채택 규칙 (pin):
//   * WAVE 는 어떤 경우에도 지연·거부되지 않는다 (dispatch 스케줄 결정성 —
//     beat/product 정렬이 issue cycle 에 고정돼 있으므로 WAVE 를 미루는
//     중재는 IF-1 정렬 자체를 깬다).
//   * 같은 cycle 에 같은 slot 을 주소하는 FILL/DRAIN/ZERO/SPILL 접촉:
//     ** IF-2 ownership window 는 start cycle 을 포함하므로 (창 [t, t+7]
//     양끝 포함 — §27.2.2 IF-2) 이것은 offset 0 의 창 위반이다 → 거부 +
//     cluster sticky ARB_OFFSET0 (loud, silent 수용 금지). ** window 위반
//     클래스의 cycle-정밀 확장이지 신규 계약이 아니다 — bank 단독 TB 가
//     시나리오 형식상 표현할 수 없던 같은-(cycle,slot) 2명령 경계의 hw 형.
//   * 같은 cycle 의 그 외 충돌 (다른 slot 의 FDZ/SPILL, 또는 REQ): 계약
//     위반이 아니라 단일 cmd port 의 구조 충돌이다 → 같은 거부 + 별도
//     sticky ARB_PORT (원인 귀속 분리 — offset-0 창 위반과 혼동 금지).
//   * 거부된 외부 cmd 는 bank 에 도달하지 않는다 (bank sticky 불변) —
//     관측은 clu_reject_q 1-cycle pulse (충돌 다음 cycle) + cluster sticky.
//   * 상류는 cmd_v_i 를 wave issue cycle (wave_v_i + 2) 과 겹치지 않게
//     스케줄할 책임이 있다 — 위반은 위 규칙대로 loud (거부+sticky) 하며
//     silent 소실 경로는 없다.
//
// -----------------------------------------------------------------------------
// 외부 cmd surface (FILL/DRAIN/ZERO 명령 경로의 bank cmd 인터페이스 결선)
// -----------------------------------------------------------------------------
// cmd_op_i 인코딩은 FP_AccBank.v 의 OP_* 계약 그대로 (아래 localparam 전사).
// REQ/FILL/DRAIN/ZERO/SPILL + 미정의 opcode (6/7) 는 bank 로 pass-through
// — 미정의 opcode 는 bank 의 PROTO_GUARD sticky 가 잡는다 (③ cmd_unk 변이
// 사멸 표면 보존). ** OP_WAVE (1) 만 예외 — 외부 surface 의 raw WAVE 는
// 전용 wave 경로 (operand 스트리밍 + issue 정렬) 를 우회해 lattice 를
// 비정렬 start 시키므로 차단한다: 거부 + sticky CMD_WAVE_DIRECT (전달 안
// 함). ** wave 는 wave_v_i surface 하나로만 발화한다.
//
// -----------------------------------------------------------------------------
// special operand pin (skeleton 레벨 — TRAIN ISA 의 special 의미론은 ④
// 제외 범위, 후속 ISA COMMIT 몫)
// -----------------------------------------------------------------------------
// lattice 는 NaN/Inf 를 표현하지 못한다 (§27.2 field 계약). narrow operand
// 의 NaN/Inf 가 소비 중인 wave 의 lane 에 도달하면:
//   * 기여는 canonical zero field 로 강제 (lattice 전제조건이 매 cycle
//     성립 — X 방출 없음; FP_FmaLaneBf16.v "operand preconditions hold on
//     EVERY cycle" 관례의 승계),
//   * 같은 cycle 에 cluster sticky LANE_SPECIAL 발화 (loud — silent zero
//     대체 금지, project law),
//   * 그 wave 의 writeback 은 억제된다 (lat_fault_i OR — carry-vfault 처리
//     (golden §5 항 1) 와 동형: word 보존 + 창 점유 유지 + bank sticky
//     CARRY_VFAULT 동반).
// bf16 exp field 0 (true zero + 254 subnormals) 은 special 이 아니라 DAZ
// zero — 정상 경로다 (§23.10.5 operand-load 계약; tap 이 canonical zero
// field 로 exact 하게 기여 0 을 인가한다).
//
// -----------------------------------------------------------------------------
// fault 집약 (부품 fault → cluster 레벨 sticky; 원인 귀속 유지)
// -----------------------------------------------------------------------------
// fault_o = |clu_fault_causes_o | bank fault_o. 원인은 병렬 노출:
//   * clu_fault_causes_o[6:0] — 본 top 고유 원인 (아래 표), set-only,
//     해제는 srst_i 뿐 (bank sticky 계약과 동형).
//       [0] ARB_OFFSET0  — offset-0 창 위반 (위 중재 pin)
//       [1] ARB_PORT     — cmd port 구조 충돌 (다른 slot / REQ)
//       [2] WAVE_BUSY    — beat 스트리밍 중 wave_v_i (II<4 위반; 거부)
//       [3] CMD_WAVE     — 외부 surface 의 raw OP_WAVE (거부)
//       [4] LD_CONFLICT  — beat 스트리밍 cycle 의 operand load (거부 —
//                          in-flight wave 의 golden 대비 결정성 보존)
//       [5] LANE_SPECIAL — 소비 중 lane 의 NaN/Inf (위 pin)
//       [6] LAT_FAULT    — lattice fault_q (done cycle 채집 — lattice
//                          (a)..(f) 클래스, carry-lane (c강화)/(d)/(e) 포함)
//   * bank_fault_causes_o[13:0] — FP_AccBank sticky 원인 14 bit 그대로
//     (귀속 불변 pass-through; CARRY_VFAULT 는 LANE_SPECIAL/LAT_FAULT 와
//     조합돼 "lattice-측 fault 로 writeback 억제됨" 을 표시한다).
//   * lattice 자체의 fault_q 는 per-wave 값 (sticky 아님) — cluster 가
//     done cycle 에 LAT_FAULT 로 sticky 화한다.
//
// -----------------------------------------------------------------------------
// 기타 계약 (승계 명문)
// -----------------------------------------------------------------------------
// * srst_i: bank·cluster 제어 상태의 동기 초기화 (CSR 급). operand store
//   는 dispatch 스테이징이라 srst 범위 밖 (power-on +0 init — 결정적).
//   srst 는 idle (in-flight wave 없음) 에서 인가하는 것이 TB 규율 —
//   mid-flight srst 는 lattice (reset 없는 항상-흐름 파이프) 의 이후 done
//   이 bank LAT_DESYNC 로 loud 하게 남는다 (정직한 자기검사; silent 아님).
// * srst_i cycle 의 wave_v_i / cmd_v_i / ld_v_i 는 무시된다 (bank 의 srst
//   cycle 명령 무시와 동일 계약 — ③ TB 가 봉인한 그 표면).
// * 곱셈 연산자는 FP_TrainLaneTap 의 그 1개뿐 (본 top glue 는 add/mux
//   전용) — premap `$mul` 정확히 8 의 구조적 보장.
// * dynamic part-select 없음 (array word 색인 + 상수 index 만 — project
//   law). 스트리머/소비창 카운터는 FP_AccLattice.v beat 제어 idiom 승계.
// * 파라미터: 본 top 은 N=8 출하 형상 고정 (NBEATS=4, LATENCY=7 hard pin
//   — §27.6 ④ scope). lattice 의 PRODUCTS_PER_BEAT 파라미터화는 lattice
//   에 존치 (측정 계보) — cluster 레벨 파라미터화는 ④ 범위 밖.
// =============================================================================

/* verilator lint_off UNUSEDPARAM */
// (OP_REQ 등 op 인코딩 표 전사는 계약 문서화 상수 — FP_AccLattice.v 의
//  lint_off 관례와 동일.)
/* verilator lint_off PROCASSINIT */
// (reg 선언 초기값 = FPGA bitstream 초기화 관례 — FP_AccLattice.v /
//  FP_AccBank.v 와 동일. srst_i 가 별도로 존재하나 power-on 확정값도 함께
//  제공한다.)

module FP_TrainCluster #(
    parameter integer SLOT_AW  = 6,          // 2^6 = 64 slot = 2 bank x 32 lane
    parameter integer N_SLOTS  = 64,
    parameter integer STREAM_W = 4
) (
    input                       clk,
    input                       srst_i,

    // ---- wave-step operand store load port (TB-구동 스테이징 surface) ----
    input                       ld_v_i,
    input  [4:0]                ld_idx_i,    // pair index 0..31 (addend 번호)
    input  [15:0]               ld_a_i,      // narrow multiplicand a
    input  [15:0]               ld_b_i,      // narrow multiplicand b

    // ---- wave dispatch surface (beat dispatch 스켈레톤 입구) ----
    input                       wave_v_i,
    input                       wave_dtype_bf16_i, // 1=bf16, 0=f16 (wave 단위)
    input  [STREAM_W-1:0]       wave_stream_i,
    input  [SLOT_AW-1:0]        wave_slot_i,

    // ---- bank cmd surface (REQ/FILL/DRAIN/ZERO/SPILL — OP_WAVE 는 차단) ----
    input                       cmd_v_i,
    input  [2:0]                cmd_op_i,    // FP_AccBank.v OP_* 인코딩
    input  [STREAM_W-1:0]       cmd_stream_i,
    input  [SLOT_AW-1:0]        cmd_slot_i,
    input  [63:0]               cmd_word_i,  // FILL: fp64 image word
    input                       cmd_tag_v_i, // FILL: image owner-tag 유효
    input  [STREAM_W-1:0]       cmd_tag_i,   // FILL: image owner-tag

    // ---- bank 응답/관측 pass-through (시간 규약은 FP_AccBank.v 헤더) ----
    output                      resp_v_o,
    output                      resp_refused_o,
    output                      resp_vfault_o,
    output                      acq_v_o,
    output                      acq_reject_o,
    output                      drain_v_o,
    output [31:0]               drain_o,
    output                      spill_v_o,
    output [63:0]               spill_o,

    // ---- cluster 레벨 거부 pulse (중재/우회/스트리머 거부 — 다음 cycle) ----
    output reg                  clu_reject_q,

    // ---- lattice 관측 (done cycle 유효 — FP_AccLattice.v 출력 계약) ----
    output                      lat_done_o,
    output [63:0]               lat_wide_o,  // RTO-48 wide field
    output [31:0]               lat_fp32_o,  // 즉시-drain RNE-24 (§27.2.3)

    // ---- fault 집약 (원인 귀속 병렬 노출 — 헤더 표) ----
    output [6:0]                clu_fault_causes_o,
    output [13:0]               bank_fault_causes_o,
    output                      fault_o,

    // ---- bank 관측 전용 read port pass-through ----
    input  [SLOT_AW-1:0]        dbg_slot_i,
    output [63:0]               dbg_word_o,
    output                      dbg_owner_v_o,
    output [STREAM_W-1:0]       dbg_owner_o
);

    // ---- op 인코딩 (FP_AccBank.v 와 공유하는 계약 — 전사) ----
    localparam [2:0] OP_REQ   = 3'd0;
    localparam [2:0] OP_WAVE  = 3'd1;
    localparam [2:0] OP_FILL  = 3'd2;
    localparam [2:0] OP_DRAIN = 3'd3;
    localparam [2:0] OP_ZERO  = 3'd4;
    localparam [2:0] OP_SPILL = 3'd5;

    // N=8 출하 형상 hard pin (헤더 "파라미터" 항)
    localparam integer LATENCY = 7;          // = NBEATS(4) + 3 — bank 와 일치

    // cluster sticky 원인 색인 (헤더 표와 1:1)
    localparam integer CF_ARB_OFFSET0  = 0;
    localparam integer CF_ARB_PORT     = 1;
    localparam integer CF_WAVE_BUSY    = 2;
    localparam integer CF_CMD_WAVE     = 3;
    localparam integer CF_LD_CONFLICT  = 4;
    localparam integer CF_LANE_SPECIAL = 5;
    localparam integer CF_LAT_FAULT    = 6;

    // =========================================================================
    // wave-step operand store — 32 pair x (16b + 16b) FF (glue 산정의 그
    // "32 pair x 32b"). power-on 전량 +0 (bf16/f16 양쪽에서 K_ZERO — 결정적).
    // =========================================================================
    reg [15:0] opa [0:31];
    reg [15:0] opb [0:31];

    integer ii;
    initial begin
        for (ii = 0; ii < 32; ii = ii + 1) begin
            opa[ii] = 16'h0000;
            opb[ii] = 16'h0000;
        end
    end

    // =========================================================================
    // beat 스트리머 — wave_v_i 수용 cycle 이 beat 0, 이후 3 cycle 연속
    // (FP_AccLattice.v beat 제어 idiom 승계 — NBEATS=4 고정형).
    // =========================================================================
    reg       s_active = 1'b0;               // beat 1..3 동안 1
    reg [1:0] s_bcnt   = 2'd0;

    wire wave_go = wave_v_i & ~s_active & ~srst_i;
    wire s_en    = wave_go | s_active;
    wire [1:0] beat_sel = s_active ? s_bcnt : 2'd0;

    always @(posedge clk) begin
        if (srst_i) begin
            s_active <= 1'b0;
            s_bcnt   <= 2'd0;
        end
        else if (s_en) begin
            if (s_active & (s_bcnt == 2'd3)) begin
                s_active <= 1'b0;
                s_bcnt   <= 2'd0;
            end
            else begin
                s_active <= 1'b1;
                s_bcnt   <= wave_go ? 2'd1 : (s_bcnt + 2'd1);
            end
        end
    end

    // dtype 는 wave 단위 — beat 0 는 조합 (당 cycle 인가), beat 1..3 은 등록값
    reg dtype_r = 1'b0;
    always @(posedge clk) begin
        if (wave_go) dtype_r <= wave_dtype_bf16_i;
    end
    wire tap_dtype = wave_go ? wave_dtype_bf16_i : dtype_r;

    // operand load — 스트리밍 cycle (beat 0..3) 과의 충돌은 거부 + sticky
    // (in-flight wave 의 golden 대비 결정성 보존 — 헤더 LD_CONFLICT 항)
    wire ld_ok   = ld_v_i & ~s_en & ~srst_i;
    wire ld_conf = ld_v_i &  s_en & ~srst_i;

    always @(posedge clk) begin
        if (ld_ok) begin
            opa[ld_idx_i] <= ld_a_i;
            opb[ld_idx_i] <= ld_b_i;
        end
    end

    // =========================================================================
    // WAVE issue 파이프 — wave_go 로부터 2 cycle (tap S1+S2 latency) 지연해
    // bank cmd port 에 OP_WAVE 인가: beat 0 raw product 와 같은 cycle (IF-1
    // 정렬 — 헤더 시간 구조). wave_go 간격 >= 4 (스트리머 거부) 이므로 issue
    // 파이프 내 충돌은 구조적으로 없다.
    // =========================================================================
    reg                iss_v1 = 1'b0, iss_v2 = 1'b0;
    reg [SLOT_AW-1:0]  iss_sl1 = {SLOT_AW{1'b0}},  iss_sl2 = {SLOT_AW{1'b0}};
    reg [STREAM_W-1:0] iss_st1 = {STREAM_W{1'b0}}, iss_st2 = {STREAM_W{1'b0}};

    always @(posedge clk) begin
        if (srst_i) begin
            iss_v1 <= 1'b0;
            iss_v2 <= 1'b0;
        end
        else begin
            iss_v1 <= wave_go;
            iss_v2 <= iss_v1;
        end
        iss_sl1 <= wave_slot_i;
        iss_sl2 <= iss_sl1;
        iss_st1 <= wave_stream_i;
        iss_st2 <= iss_st1;
    end

    // =========================================================================
    // bank cmd port 중재 — 헤더 "offset-0 중재 pin" 의 구현.
    // WAVE (iss_v2) 우선·무지연; 외부 cmd 는 빈 cycle 에만 pass-through.
    // =========================================================================
    wire cmd_ext     = cmd_v_i & ~srst_i;
    wire ext_is_wave = cmd_ext & (cmd_op_i == OP_WAVE);      // 우회 차단
    wire ext_fdzs    = cmd_ext & ((cmd_op_i == OP_FILL)
                                | (cmd_op_i == OP_DRAIN)
                                | (cmd_op_i == OP_ZERO)
                                | (cmd_op_i == OP_SPILL));

    wire arb_hit  = iss_v2 & cmd_ext & ~ext_is_wave;         // 같은-cycle 충돌
    wire arb_off0 = arb_hit & ext_fdzs & (cmd_slot_i == iss_sl2);
    wire arb_port = arb_hit & ~arb_off0;
    wire ext_fwd  = cmd_ext & ~ext_is_wave & ~iss_v2;        // bank 로 전달

    wire               bk_v      = iss_v2 | ext_fwd;
    wire [2:0]         bk_op     = iss_v2 ? OP_WAVE : cmd_op_i;
    wire [STREAM_W-1:0] bk_stream = iss_v2 ? iss_st2 : cmd_stream_i;
    wire [SLOT_AW-1:0]  bk_slot   = iss_v2 ? iss_sl2 : cmd_slot_i;
    wire               bk_tag_v  = ext_fwd & cmd_tag_v_i;

    // =========================================================================
    // FMA lane 전단 tap x 8 — beat_sel 에 따른 8-of-32 pair 선택 (per-lane
    // 4:1 mux — 상수 index 만) → FP_TrainLaneTap (S1+S2+static align) →
    // lattice ops. lane j 의 beat b addend = pair 8b+j (오름차순 pin —
    // FP_AccLattice.v 인터페이스 계약).
    // =========================================================================
    wire [511:0] lat_ops;
    wire [7:0]   lane_spc;

    genvar gl;
    generate
        for (gl = 0; gl < 8; gl = gl + 1) begin : g_lane
            wire [15:0] a_w = (beat_sel == 2'd0) ? opa[gl]
                            : (beat_sel == 2'd1) ? opa[gl + 8]
                            : (beat_sel == 2'd2) ? opa[gl + 16]
                            :                      opa[gl + 24];
            wire [15:0] b_w = (beat_sel == 2'd0) ? opb[gl]
                            : (beat_sel == 2'd1) ? opb[gl + 8]
                            : (beat_sel == 2'd2) ? opb[gl + 16]
                            :                      opb[gl + 24];

            FP_TrainLaneTap u_tap (
                .clk          (clk),
                .a_narrow     (a_w),
                .b_narrow     (b_w),
                .dtype_bf16   (tap_dtype),
                .prod_field   (lat_ops[64*gl+63 : 64*gl]),
                .prod_special (lane_spc[gl])
            );
        end
    endgenerate

    // =========================================================================
    // lattice + bank 인스턴스 — IF-1 직결 (start/carry 같은 cycle, done/
    // bank word/fault 가 LATENCY=7 에 되돌아온다).
    // =========================================================================
    wire        lat_start_w;
    wire [63:0] lat_carry_w;
    wire        lat_done_w;
    wire [63:0] lat_bankword_w;
    wire        lat_fault_lat;

    // special-operand wave 의 writeback 억제 (헤더 special pin) — sp_p4 는
    // 그 wave 의 done cycle 에 정렬된 특례 플래그 (아래 소비창 파이프).
    reg sp_p2 = 1'b0, sp_p3 = 1'b0, sp_p4 = 1'b0;
    wire lat_fault_w = lat_fault_lat | sp_p4;

    // resolved_q (528b) 는 본 top 에서 미노출 — 통합 TB 판정은 wide/fp32/
    // bank word 로 충분하며 관측 port 는 glue 산정 범위 밖 (헤더).
    /* verilator lint_off PINCONNECTEMPTY */
    FP_AccLattice #(
        .PRODUCTS_PER_BEAT (8)
    ) u_lattice (
        .clk        (clk),
        .start_i    (lat_start_w),
        .ops_i      (lat_ops),
        .carry_i    (lat_carry_w),
        .resolved_q (),
        .wide_q     (lat_wide_o),
        .bank_q     (lat_bankword_w),
        .fp32_q     (lat_fp32_o),
        .fault_q    (lat_fault_lat),
        .done_q     (lat_done_w)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    wire bank_fault_w;

    FP_AccBank #(
        .SLOT_AW  (SLOT_AW),
        .N_SLOTS  (N_SLOTS),
        .STREAM_W (STREAM_W),
        .LATENCY  (LATENCY)
    ) u_bank (
        .clk            (clk),
        .srst_i         (srst_i),
        .cmd_v_i        (bk_v),
        .cmd_op_i       (bk_op),
        .cmd_stream_i   (bk_stream),
        .cmd_slot_i     (bk_slot),
        .cmd_word_i     (cmd_word_i),
        .cmd_tag_v_i    (bk_tag_v),
        .cmd_tag_i      (cmd_tag_i),
        .lat_start_o    (lat_start_w),
        .lat_carry_o    (lat_carry_w),
        .lat_done_i     (lat_done_w),
        .lat_bank_i     (lat_bankword_w),
        .lat_fault_i    (lat_fault_w),
        .resp_v_q       (resp_v_o),
        .resp_refused_q (resp_refused_o),
        .resp_vfault_q  (resp_vfault_o),
        .acq_v_q        (acq_v_o),
        .acq_reject_q   (acq_reject_o),
        .drain_v_q      (drain_v_o),
        .drain_q        (drain_o),
        .spill_v_q      (spill_v_o),
        .spill_q        (spill_o),
        .fault_causes_o (bank_fault_causes_o),
        .fault_o        (bank_fault_w),
        .dbg_slot_i     (dbg_slot_i),
        .dbg_word_o     (dbg_word_o),
        .dbg_owner_v_o  (dbg_owner_v_o),
        .dbg_owner_o    (dbg_owner_o)
    );

    assign lat_done_o = lat_done_w;

    // =========================================================================
    // 소비창 — bank 가 수용한 WAVE 의 lattice beat 0..3 cycle 표지 (수용
    // 여부는 lat_start_w 로만 알 수 있으므로 스트리머와 별도 미러). 소비
    // 중 lane 의 special 만 fault 다 — 비소비 cycle 의 tap 산출은 lattice
    // 가 구조적으로 무시하므로 기여가 없다 (스트리머 idle 값 포함).
    // lat_start_w 간격 >= 4 는 스트리머가 보장 (헤더) — c_active 중의
    // beat 0 재진입은 구조적으로 없다.
    // =========================================================================
    reg       c_active = 1'b0;
    reg [1:0] c_bcnt   = 2'd0;

    wire c_en = lat_start_w | c_active;

    always @(posedge clk) begin
        if (srst_i) begin
            c_active <= 1'b0;
            c_bcnt   <= 2'd0;
        end
        else if (c_en) begin
            if (c_active & (c_bcnt == 2'd3)) begin
                c_active <= 1'b0;
                c_bcnt   <= 2'd0;
            end
            else begin
                c_active <= 1'b1;
                c_bcnt   <= lat_start_w ? 2'd1 : (c_bcnt + 2'd1);
            end
        end
    end

    wire spc_any = |lane_spc;

    // wave 단위 special 누적 → done cycle 정렬 파이프 (FP_AccLattice.v 의
    // fault_acc → fault_p2/p3 → fault_q 정렬과 동일 산술: 마지막 beat 의
    // 다음 cycle 에 최종값, 그로부터 3 cycle 뒤가 done cycle).
    reg spc_acc = 1'b0;
    always @(posedge clk) begin
        if (srst_i)
            spc_acc <= 1'b0;
        else if (c_en)
            spc_acc <= (lat_start_w ? 1'b0 : spc_acc) | spc_any;
    end

    always @(posedge clk) begin
        if (srst_i) begin
            sp_p2 <= 1'b0;
            sp_p3 <= 1'b0;
            sp_p4 <= 1'b0;
        end
        else begin
            sp_p2 <= spc_acc;
            sp_p3 <= sp_p2;
            sp_p4 <= sp_p3;
        end
    end

    // =========================================================================
    // cluster sticky + 거부 pulse — set-only, 해제는 srst_i 뿐 (bank 동형)
    // =========================================================================
    wire wave_busy = wave_v_i & s_active & ~srst_i;   // II<4 위반 — 거부

    reg [6:0] clu_sticky = 7'b0;

    initial clu_reject_q = 1'b0;

    always @(posedge clk) begin
        if (srst_i) begin
            clu_sticky   <= 7'b0;
            clu_reject_q <= 1'b0;
        end
        else begin
            clu_reject_q <= arb_off0 | arb_port | wave_busy
                          | ext_is_wave | ld_conf;

            if (arb_off0)    clu_sticky[CF_ARB_OFFSET0]  <= 1'b1;
            if (arb_port)    clu_sticky[CF_ARB_PORT]     <= 1'b1;
            if (wave_busy)   clu_sticky[CF_WAVE_BUSY]    <= 1'b1;
            if (ext_is_wave) clu_sticky[CF_CMD_WAVE]     <= 1'b1;
            if (ld_conf)     clu_sticky[CF_LD_CONFLICT]  <= 1'b1;
            if (c_en & spc_any)
                clu_sticky[CF_LANE_SPECIAL] <= 1'b1;
            if (lat_done_w & lat_fault_lat)
                clu_sticky[CF_LAT_FAULT] <= 1'b1;
        end
    end

    assign clu_fault_causes_o = clu_sticky;
    assign fault_o            = (|clu_sticky) | bank_fault_w;

endmodule

/* verilator lint_on PROCASSINIT */
/* verilator lint_on UNUSEDPARAM */

// =============================================================================
// FP_TrainLaneTap — FP_FmaLaneBf16 의 wide-product 전단 tap (본 파일 상단
// "곱 원천 — 전단 tap 채택" 항이 채택 근거의 normative 기록이다).
//
// FP_FmaLaneBf16.v 의 S1 (nunpack/classify/p_exp — nunpack verbatim) + S2
// (the ONE 11x11 significand multiplier — C1 명문 승계, `WT_USE_DSP) +
// static align (C2 — 2:1 wire mux, 반올림 0) 을 문자 그대로 승계하고,
// per-lane FP_AddWide 후단 (PACK_FINAL) 과 fp32 특례 mux 는 승계하지
// 않는다 — in-dot 경로에 per-lane 후단 누산은 없다 (§27.2.1).
//
// 산출 (operand 인가로부터 정확히 2 cycle 뒤 — S1/S2 reg, align 은 조합):
//   prod_field[63:0]  : lattice addend field (lattice_vec_contract.md §2 —
//                       [63:60]=0 / [59]=sign / [58:48]=exp / [47:0]=sig).
//                       nonzero 곱 = §27.2 raw product 형식 (sig 는
//                       [2^46,2^48) — 1-bit un-normalized 허용형; p_exp =
//                       ea_eff+eb_eff+1). zero 곱 (진짜 zero / DAZ / 특례
//                       operand) = canonical zero field — 부호는 계약상
//                       버려진다 (zero 기여는 합에 부호 효과가 없고,
//                       canonical zero 는 +0 하나 — §23.10.1).
//   prod_special      : a/b 어느 쪽이든 NaN/Inf (widen-후 분류 K_NAN/K_INF)
//                       — 상위 (FP_TrainCluster) 가 소비창 내에서만 loud
//                       fault 로 채집한다. field 는 canonical zero 로 이미
//                       강제돼 있어 lattice 전제조건은 매 cycle 성립한다.
//
// operand-load 정책 (FP_FmaLaneBf16.v 헤더의 그 계약 — 곱측 반쪽):
//   * bf16 exp field 0 → SIGNED ZERO (DAZ — 254 subnormal 포함): K_ZERO.
//   * f16 subnormal → EXACT 주입 (leading-one scan + shift — §23.10.5 의
//     의도된 비대칭).
//   * NaN (sNaN 포함)/Inf → K_NAN/K_INF: sig 0 강제 + prod_special.
// 항상-흐르는 고정-latency 파이프 — handshake/stall/reset 없음 (FP_Mul36 /
// FP_AddWide / FP_FmaLaneBf16 계약 동형). 곱셈기 사용 정확히 1.
// =============================================================================

/* verilator lint_off UNUSEDSIGNAL */
// (nunpack 반환 벡터의 분기별 미사용 bit — FP_FmaLaneBf16.v 와 동일 사유.)
/* verilator lint_off DECLFILENAME */
// (tap 은 cluster 전용 종속 모듈 — 채택 근거·계약이 같은 파일 상단 헤더에
//  묶여 있어 한 파일 동거가 계보 추적에 유리하다. 별도 top 아님.)

module FP_TrainLaneTap (
    input             clk,

    input      [15:0] a_narrow,
    input      [15:0] b_narrow,
    input             dtype_bf16,   // 1 = bf16, 0 = f16

    output     [63:0] prod_field,
    output            prod_special
);

    // operand 분류 (FP_FmaLaneBf16.v 와 동일 인코딩)
    localparam [1:0] K_NUM  = 2'd0;
    localparam [1:0] K_ZERO = 2'd1;
    localparam [1:0] K_INF  = 2'd2;
    localparam [1:0] K_NAN  = 2'd3;

    localparam [63:0] CANON_ZERO_FIELD = 64'h0400_0000_0000_0000;

    // -------------------------------------------------------------------------
    // S1 조합 — narrow operand unpack / widen / classify.
    // FP_FmaLaneBf16.v nunpack VERBATIM (주석 포함 원문은 그 파일 참조).
    // -------------------------------------------------------------------------
    function [22:0] nunpack;
        input [15:0]     x;
        input            is_bf16;
        reg              s;
        reg  [7:0]       e8;
        reg  [6:0]       m7;
        reg  [4:0]       e5;
        reg  [9:0]       m10;
        reg  [3:0]       bl;
        reg  [10:0]      sig;
        reg signed [8:0] eef;
        reg  [1:0]       knd;
        integer          j;
        begin
            s   = x[15];
            e8  = x[14:7];
            m7  = x[6:0];
            e5  = x[14:10];
            m10 = x[9:0];

            bl = 4'd0;
            for (j = 0; j <= 9; j = j + 1)
                if (m10[j]) bl = j[3:0] + 4'd1;

            if (is_bf16) begin
                if (e8 == 8'hFF)      knd = (|m7) ? K_NAN : K_INF;
                else if (e8 == 8'h00) knd = K_ZERO;   // + all 254 subnormals
                else                  knd = K_NUM;
                sig = {3'b000, 1'b1, m7};             // 8b, zero-extended to 11
                eef = $signed({1'b0, e8}) - 9'sd127;
            end else begin
                if (e5 == 5'h1F)      knd = (|m10) ? K_NAN : K_INF;
                else if (e5 == 5'h00) knd = (|m10) ? K_NUM : K_ZERO;
                else                  knd = K_NUM;
                if (e5 == 5'h00) begin
                    sig = {1'b0, m10} << (4'd11 - bl);       // f16 subnormal
                    eef = $signed({5'b0, bl}) - 9'sd25;
                end else begin
                    sig = {1'b1, m10};
                    eef = $signed({4'b0, e5}) - 9'sd15;
                end
            end

            if (knd != K_NUM) sig = 11'd0;
            nunpack = {sig, eef, s, knd};
        end
    endfunction

    wire [22:0]       au = nunpack(a_narrow, dtype_bf16);
    wire [22:0]       bu = nunpack(b_narrow, dtype_bf16);

    wire [10:0]       a_sig = au[22:12];
    wire signed [8:0] a_eef = au[11:3];
    wire              a_sgn = au[2];
    wire [1:0]        a_knd = au[1:0];

    wire [10:0]       b_sig = bu[22:12];
    wire signed [8:0] b_eef = bu[11:3];
    wire              b_sgn = bu[2];
    wire [1:0]        b_knd = bu[1:0];

    // p_exp = ea_eff + eb_eff + 1 (dtype-agnostic — FP_FmaLaneBf16.v ALIGN
    // ALGEBRA). 비-K_NUM operand 는 -1024 zero sentinel 로 강제.
    wire signed [10:0] p_exp_num = {{2{a_eef[8]}}, a_eef}
                                 + {{2{b_eef[8]}}, b_eef}
                                 + 11'sd1;
    wire               p_is_zero = (a_knd != K_NUM) | (b_knd != K_NUM);
    wire signed [10:0] p_exp_w   = p_is_zero ? -11'sd1024 : p_exp_num;

    wire sp    = a_sgn ^ b_sgn;
    wire spc_w = (a_knd == K_NAN) | (a_knd == K_INF)
               | (b_knd == K_NAN) | (b_knd == K_INF);

    // ---- S1 레지스터 ----
    reg        [10:0]  a_sig_s1, b_sig_s1;
    reg signed [10:0]  p_exp_s1;
    reg                p_sgn_s1, bf16_s1, pz_s1, spc_s1;

    always @(posedge clk) begin
        a_sig_s1 <= a_sig;
        b_sig_s1 <= b_sig;
        p_exp_s1 <= p_exp_w;
        p_sgn_s1 <= sp;
        bf16_s1  <= dtype_bf16;
        pz_s1    <= p_is_zero;
        spc_s1   <= spc_w;
    end

    // -------------------------------------------------------------------------
    // S2 — the ONE 11x11 -> 22 significand multiplier (C1 승계; 본 tap 의
    // 유일한 곱셈기 — premap `$mul` = 1 pin). vendor-neutral DSP 힌트는
    // FP_Mul36 / FP_FmaLaneBf16 관례 그대로.
    // -------------------------------------------------------------------------
    `WT_USE_DSP reg [21:0] prod_s2;

    reg signed [10:0]  p_exp_s2;
    reg                p_sgn_s2, bf16_s2, pz_s2, spc_s2;

    always @(posedge clk) begin
        prod_s2  <= a_sig_s1 * b_sig_s1;
        p_exp_s2 <= p_exp_s1;
        p_sgn_s2 <= p_sgn_s1;
        bf16_s2  <= bf16_s1;
        pz_s2    <= pz_s1;
        spc_s2   <= spc_s1;
    end

    // -------------------------------------------------------------------------
    // static align — [2^46,2^48) 로의 2:1 wire mux (C2 — 반올림 0, barrel 0):
    //   bf16: prod in [2^14,2^16) -> << 32   (prod[21:16] 은 구조적 0)
    //   f16 : prod in [2^20,2^22) -> << 26
    // -------------------------------------------------------------------------
    wire [47:0] p_sig_w = bf16_s2 ? {prod_s2[15:0], 32'd0}
                                  : {prod_s2[21:0], 26'd0};

    // lattice addend field — zero 곱 (특례 operand 포함) 은 canonical zero
    assign prod_field   = pz_s2 ? CANON_ZERO_FIELD
                                : {4'b0000, p_sgn_s2, p_exp_s2, p_sig_w};
    assign prod_special = spc_s2;

endmodule

/* verilator lint_on DECLFILENAME */
/* verilator lint_on UNUSEDSIGNAL */
