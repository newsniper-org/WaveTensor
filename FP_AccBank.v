// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

// =============================================================================
// FP_AccBank.v — v2.0 wide ACC bank: 2 banks x 32 lanes x 64b/cluster
// (spec §27.2.2 + [하류 ③ COMMIT 2026-08-16] 블록이 normative.
//  golden: scripts/golden_lattice.py `bank_execute` — golden-before-RTL law;
//  formal: proofs/tla/AccBank.tla ownership guard 군 — formal-first §23.7-3;
//  통합 TB: tb_fp_accbank.v — TLC 유도 directed + golden 시나리오 전량.)
//
// -----------------------------------------------------------------------------
// 계약 요약 (§27.2.2 승계 — 본 헤더가 hw 관측 계약의 요약본이다)
// -----------------------------------------------------------------------------
// * word 포맷: slot 당 64b = PACK_WIDE 값의 IEEE binary64 무손실 재인코딩.
//   canonical zero 는 fp64 +0 (64'h0) 하나뿐 — §27.2.2 canonical zero 항.
//   상태 = N_SLOTS x 64b (기본 64 slot = 2 bank x 32 lane = 4,096 bit —
//   §27.2.2 의 그 수치). 저장 구조는 FF array (BRAM 강제 아님 — slot 별
//   독립 write enable; 합성기가 LUTRAM/FF 로 자유 매핑).
// * slot 주소: {bank, lane} 평탄화 SLOT_AW-bit. 상위 사상 (pcid[1:0] 등
//   80-bit tag 정체성 -> stream id) 은 상류 몫 — 본 unit 은 STREAM_W-bit
//   stream id 의 등가 비교만 한다 (AccBank.tla 의 Streams 대역).
//
// * IF-1 read-before-dispatch: 수용된 WAVE 의 carry word read 는 start
//   (dispatch) cycle 에 완료된다 — lat_carry_o 는 그 cycle 에 유효한
//   조합 read (FF array 이므로 SRAM read latency 없음) 이고, lat_start_o
//   와 같은 cycle 에 lattice 의 beat 0 로 공급된다. 같은 cycle 에
//   writeback (아래 IF-3) 이 같은 slot 에 착지하면 carry 는 그 writeback
//   값이다 (golden §3 처리 순서 (1) writeback -> (3) 명령 의 hw 형 =
//   lat_bank_i forward mux). ** 비-수용 cycle 의 lat_carry_o 는 고의
//   POISON (예약 비트 위반 필드) ** — lattice 의 비-beat0 carry 무시
//   계약 (IF-1 후반) 을 시스템 결선 상태에서도 능동 검증한다.
// * IF-2 ownership window: 수용된 WAVE (start t) 부터 writeback
//   (t+LATENCY) 까지 그 slot 은 lattice 소유 — 창 [t, t+LATENCY] (양끝
//   포함) 내 같은 slot 의 FILL/DRAIN/ZERO(/SPILL) 접촉은 거부 + sticky
//   (loud, silent 수용 금지). 창 직후 cycle (t+LATENCY+1) 접촉은 합법.
//   구현: slot 별 4-bit 창 카운터 wq (수용 posedge 에 8, 매 cycle -1;
//   명령 cycle t+k 에서 wq == 9-k) — FDZ fault 조건 wq >= 2 (k <= 7),
//   같은 slot 재-WAVE 금지 조건 wq >= 3 (k <= 6; k == 7 은 합법 체이닝).
// * IF-3 같은 slot 체이닝: 다음 start 는 이전 start + LATENCY 부터 합법
//   (그 cycle 의 carry 는 직전 writeback 값 — forward mux). delta 4..6
//   은 거부 + sticky. 거부된 WAVE 는 창을 열지도, lattice 를 start 하지도
//   않는다. 타 slot 은 II=NUM_BEATS 로 완전 중첩 (lattice 1개 — start
//   간격 관리는 상위 dispatch 책임, golden §2 형식 규율).
// * IF-4 zero 기록: ZERO (raw 0x7E) 는 canonical zero (fp64 +0) 기록,
//   owner 불변, ownership-checked (창/owner 검사 후) — TLA+ zero_owner.
//   acquire 융합 zero 는 REQ commit 의 scrub (아래) 이 담당.
//
// * 명령 (cycle 당 1개 — cmd_v_i): REQ / WAVE / FILL / DRAIN / ZERO /
//   SPILL. 검사 우선순위 (golden §4): window -> ownership -> 값 검증.
//   같은 cycle 의 처리 순서 (golden §3): (1) writeback -> (2) acquire
//   commit -> (3) 명령 — hw 로는 (1)(2) 의 효과를 (3) 의 조합 판정이
//   forward mux (eff_word / eff_owner) 로 보는 것으로 구현된다.
//   - REQ: 2-phase acquire — t 에 pend 등록, t+1 에 commit/reject.
//     commit (slot 무소유): owner := stream + ** canonical zero scrub **
//     (commit_zero — SRAM 잔존값이 새 소유자에게 새지 않는 유일한 방벽,
//     TLA+ CommitOwn/NoSilentAliasing). reject (소유 중): 거부 + sticky
//     (RejectOwn), incumbent 완전 불변. 응답: acq_v_q/acq_reject_q @ t+2.
//   - WAVE: window(IF-3) -> owner 검사 통과 시 lat_start_o + carry 공급,
//     wb 파이프에 slot 등록; t+LATENCY 에 lat_bank_i 를 slot 에 기록.
//     ** carry-lane fault (d)/(e) (pin 3 — FILL-valid 이나 lattice-비표현)
//     는 lattice 가 carry 소비 (beat 0) 에서 검출 ** 하고 그 wave 의
//     lat_fault_i (done cycle) 로 도착한다 — bank 는 writeback 을 억제
//     (word 보존 — silent 오염 금지) 하고 sticky (CARRY_VFAULT) 를 세운다.
//     창은 그대로 점유된다 (golden §5 항 1).
//   - FILL: window -> 외래 image tag (fill_owner — cmd_tag_*_i 대조;
//     ghost (l): tag 캐리어는 image 측/TB 몫, 대조는 hw) -> busy
//     (fill_bankfree — 소유 중 slot 은 자기/외래 불문 거부) -> FILL
//     validation (§27.2.2 (i) NaN/Inf (ii) PACK_WIDE-비표현 -> sticky +
//     acquire 도 하지 않음 (iii) ±0 수용 + canonical +0 화). 수용 =
//     acquire-by-fill (owner := stream) + word 기록.
//   - DRAIN: window -> owner 통과 시 PACK_FINAL — 정확히 1회 RNE-24 +
//     flush-after-round FTZ (§27.2.3; overflow ±Inf / exact zero +0 —
//     FP_AccLattice.v S4 drain 과 동형 관용구) 를 drain_q 로, ownership
//     release. ** word 는 지우지 않는다 ** (SRAM 잔존 — golden §5 항 2;
//     잔존값의 유일한 방벽은 acquire 시 scrub).
//   - SPILL: window -> owner 통과 시 word 를 spill_q 로 (image 8
//     fragments 확폭은 상위 frag FSM 몫 — §27.2.2 SPILL), release, word
//     잔존. 위반 시 거부 + sticky (PROTO_GUARD — AccBank.tla 의 fault
//     6종 밖이나 loud-fault-never-silent 법칙상 silent 불가).
//
// * sticky fault: 합성 가능한 status 레지스터 (v1.9
//   bank_tag_collision_error 등급 — §26.5 선례; sim-only assertion 금지).
//   원인별 bit + OR (fault_o). 해제는 srst_i 뿐 (시나리오/런 스코프 내
//   해제 없음 — golden §1 sticky 계약). 원인 bit 배치:
//     [0]  ACQ_REJECT   — RejectOwn (TLA+ commit_free 반쪽)
//     [1]  WAVE_WINDOW  — 같은 slot 재start delta < LATENCY (IF-3)
//     [2]  WAVE_OWNER   — 비-owner wave (acc_owner / AccumulateFault)
//     [3]  FILL_WINDOW  — 창 내 FILL (IF-2)
//     [4]  FILL_FOREIGN — 외래 image 주소 (fill_owner / FillFaultForeign)
//     [5]  FILL_BUSY    — live bank 위 FILL (fill_bankfree / FillFaultBusy)
//     [6]  FILL_VALID   — FILL validation (i)/(ii)
//     [7]  DRAIN_WINDOW — 창 내 DRAIN (IF-2)
//     [8]  DRAIN_OWNER  — 비-owner drain (drain_owner / DrainFault)
//     [9]  ZERO_WINDOW  — 창 내 ZERO (IF-2)
//     [10] ZERO_OWNER   — 비-owner raw 0x7E (zero_owner / ZeroFault)
//     [11] CARRY_VFAULT — carry-lane (d)/(e) (pin 3; writeback 억제 동반)
//     [12] PROTO_GUARD  — SPILL guard 위반 / 미정의 opcode (방어적)
//     [13] LAT_DESYNC   — lat_done_i 와 내부 wb 파이프 불일치 (결선 무결
//                         성 자기검사 — 정상 경로 도달 불가)
//
// * 시간 규약: 명령/응답 전부 posedge 동기. 명령 cycle t 의 판정은 조합,
//   효과는 posedge(t) 등록 — 관측층: resp_v_q/resp_refused_q/resp_vfault_q
//   (비-REQ 명령, t+1), acq_*_q (REQ, t+2), drain_*/spill_* (t+1), 상태
//   (word/owner) 는 t+1 부터, WAVE writeback 은 t+LATENCY+1 부터 관측.
//   LATENCY 파라미터는 짝 lattice 의 NUM_BEATS+3 과 일치해야 한다 (N=8
//   출하 = 7 — §27.2.2 IF-2).
// * srst_i: 동기 초기화 — power-on 정의 상태 (전 slot canonical +0, 전
//   slot 무소유, sticky 0 — golden §1) 복원 + status clear (CSR 급).
//   TB 의 시나리오 격리용이기도 하다.
// * dbg_*: 관측 전용 read port (CSR readback 급) — 판정 로직에 미관여.
// * 곱셈기 사용 0. dynamic part-select 없음 (array word 색인만 사용).
// =============================================================================

/* verilator lint_off UNUSEDSIGNAL */
// (d_m25[23] 등 관용구 잉여 bit — FP_AccLattice.v S4 와 동일 사유.)
/* verilator lint_off PROCASSINIT */
// (reg 초기값 = FPGA bitstream 초기화 관례 — FP_AccLattice.v 와 동일.
//  srst_i 가 별도로 존재하나 power-on 확정값도 함께 제공한다.)

module FP_AccBank #(
    parameter integer SLOT_AW  = 6,          // 2^6 = 64 slot = 2 bank x 32 lane
    parameter integer N_SLOTS  = 64,
    parameter integer STREAM_W = 4,
    parameter integer LATENCY  = 7           // 짝 lattice 의 NUM_BEATS+3
) (
    input                       clk,
    input                       srst_i,

    // ---- 명령 port (cycle 당 최대 1 명령 — golden §2 형식 규율) ----
    input                       cmd_v_i,
    input  [2:0]                cmd_op_i,    // 아래 OP_* 인코딩
    input  [STREAM_W-1:0]       cmd_stream_i,
    input  [SLOT_AW-1:0]        cmd_slot_i,
    input  [63:0]               cmd_word_i,  // FILL: fp64 image word
    input                       cmd_tag_v_i, // FILL: image owner-tag 유효
    input  [STREAM_W-1:0]       cmd_tag_i,   // FILL: image owner-tag

    // ---- lattice 결선 (FP_AccLattice.v 실제 인터페이스 — IF-1) ----
    output                      lat_start_o, // -> start_i (수용 WAVE 의 beat 0)
    output [63:0]               lat_carry_o, // -> carry_i (wide field)
    input                       lat_done_i,  // <- done_q
    input  [63:0]               lat_bank_i,  // <- bank_q (fp64 writeback word)
    input                       lat_fault_i, // <- fault_q (carry (d)/(e) 포함)

    // ---- 응답/관측 (registered — 시간 규약은 헤더) ----
    output reg                  resp_v_q,
    output reg                  resp_refused_q,
    output reg                  resp_vfault_q,
    output reg                  acq_v_q,
    output reg                  acq_reject_q,
    output reg                  drain_v_q,
    output reg [31:0]           drain_q,
    output reg                  spill_v_q,
    output reg [63:0]           spill_q,

    // ---- sticky fault status (합성 status — §26.5 선례) ----
    output [13:0]               fault_causes_o,
    output                      fault_o,

    // ---- 관측 전용 read port ----
    input  [SLOT_AW-1:0]        dbg_slot_i,
    output [63:0]               dbg_word_o,
    output                      dbg_owner_v_o,
    output [STREAM_W-1:0]       dbg_owner_o
);

    // ---- op 인코딩 (통합 TB / 상위 decode 와 공유하는 계약) ----
    localparam [2:0] OP_REQ   = 3'd0;
    localparam [2:0] OP_WAVE  = 3'd1;
    localparam [2:0] OP_FILL  = 3'd2;
    localparam [2:0] OP_DRAIN = 3'd3;
    localparam [2:0] OP_ZERO  = 3'd4;
    localparam [2:0] OP_SPILL = 3'd5;

    // sticky cause 색인 (헤더 표와 1:1)
    localparam integer FC_ACQ_REJECT   = 0;
    localparam integer FC_WAVE_WINDOW  = 1;
    localparam integer FC_WAVE_OWNER   = 2;
    localparam integer FC_FILL_WINDOW  = 3;
    localparam integer FC_FILL_FOREIGN = 4;
    localparam integer FC_FILL_BUSY    = 5;
    localparam integer FC_FILL_VALID   = 6;
    localparam integer FC_DRAIN_WINDOW = 7;
    localparam integer FC_DRAIN_OWNER  = 8;
    localparam integer FC_ZERO_WINDOW  = 9;
    localparam integer FC_ZERO_OWNER   = 10;
    localparam integer FC_CARRY_VFAULT = 11;
    localparam integer FC_PROTO_GUARD  = 12;
    localparam integer FC_LAT_DESYNC   = 13;

    // 비-수용 cycle 의 carry POISON — 예약 비트 위반 필드 (lattice 의
    // 비-beat0 carry 무시 계약을 결선 상태에서 능동 검증 — 헤더 IF-1).
    // canonical zero field (64'h0400_0000_0000_0000) 는 별도 상수 없이
    // 변환기 e_zero 경로가 구조적으로 산출한다.
    localparam [63:0] POISON_FIELD = 64'hFFFF_FFFF_FFFF_FFFF;

    // =========================================================================
    // 상태 — slot word (fp64) / ownership / 창 카운터 / pend / wb 파이프
    // =========================================================================
    reg [63:0]         words  [0:N_SLOTS-1];
    reg                own_v  [0:N_SLOTS-1];
    reg [STREAM_W-1:0] own_id [0:N_SLOTS-1];
    reg [3:0]          wq     [0:N_SLOTS-1];

    reg                pend_v  = 1'b0;      // REQ 2-phase staging (단일 —
    reg [STREAM_W-1:0] pend_st = {STREAM_W{1'b0}};  // v1.9 mu_pending_other
    reg [SLOT_AW-1:0]  pend_sl = {SLOT_AW{1'b0}};   // 선례의 pend 규율)

    reg [LATENCY-1:0]  wb_v_sh = {LATENCY{1'b0}};   // wave 수용 -> LATENCY 뒤
    reg [SLOT_AW-1:0]  wb_sl_sh [0:LATENCY-1];      // writeback slot 파이프

    reg [13:0]         sticky_q = 14'b0;

    assign fault_causes_o = sticky_q;
    assign fault_o        = |sticky_q;

    // =========================================================================
    // 명령 decode + 같은-cycle 처리 순서의 forward mux (golden §3)
    // =========================================================================
    wire cmd_req   = cmd_v_i & (cmd_op_i == OP_REQ);
    wire cmd_wave  = cmd_v_i & (cmd_op_i == OP_WAVE);
    wire cmd_fill  = cmd_v_i & (cmd_op_i == OP_FILL);
    wire cmd_drain = cmd_v_i & (cmd_op_i == OP_DRAIN);
    wire cmd_zero  = cmd_v_i & (cmd_op_i == OP_ZERO);
    wire cmd_spill = cmd_v_i & (cmd_op_i == OP_SPILL);
    wire cmd_unk   = cmd_v_i & (cmd_op_i > OP_SPILL);

    // 창 카운터 관측 (명령 cycle t+k 에서 wq == 9-k — 헤더 IF-2 산술)
    wire [3:0] wq_c     = wq[cmd_slot_i];
    wire       win_wave = (wq_c >= 4'd3);   // 같은 slot 재-WAVE 금지 (k<=6)
    wire       win_fdz  = (wq_c >= 4'd2);   // FILL/DRAIN/ZERO/SPILL fault 창

    // (2) acquire commit — REQ 다음 cycle 의 판정 (owner 는 raw: writeback
    // 은 owner 를 만지지 않고, 명령은 처리 순서상 commit 뒤이므로 안전)
    wire commit_ok  = pend_v & ~own_v[pend_sl];
    wire commit_hit = commit_ok & (pend_sl == cmd_slot_i);

    // (3) 명령이 보는 유효 owner — 같은 cycle commit 의 forward
    wire                eff_ov   = commit_hit | own_v[cmd_slot_i];
    wire [STREAM_W-1:0] eff_own  = commit_hit ? pend_st : own_id[cmd_slot_i];
    wire                own_match = eff_ov & (eff_own == cmd_stream_i);

    // (1) writeback head — 같은 cycle 의 lattice done 과 정렬 (LATENCY 검증
    // 은 LAT_DESYNC 자기검사). fault 는 writeback 억제 (forward 도 억제).
    wire               wb_head_v = wb_v_sh[LATENCY-1];
    wire [SLOT_AW-1:0] wb_head_s = wb_sl_sh[LATENCY-1];
    wire               wb_ok     = wb_head_v & ~lat_fault_i;
    wire               wb_hit    = wb_ok & (wb_head_s == cmd_slot_i);

    // (3) 명령이 보는 유효 word — commit scrub > writeback > 저장값
    // (golden §3 의 (1)->(2)->(3) 순서; commit 과 writeback 의 같은 slot
    //  동시 발생은 ownership 구조상 도달 불가 — 순서는 방어적 명문화)
    wire [63:0] eff_word = commit_hit ? 64'h0
                         : wb_hit     ? lat_bank_i
                         :              words[cmd_slot_i];

    // =========================================================================
    // fp64 -> PACK_WIDE field 변환 (carry 공급 + drain 공용). 전제: 저장
    // word 는 항상 표현 가능 (FILL validation 통과값 또는 lattice writeback
    // — 구조적 보장, §27.2.1 amendment pin 2 의 보장 경로). 전제 위반은
    // 정상 경로 도달 불가이며, 만에 하나 도달해도 lattice 의 carry-lane
    // 강화형 fault (c) 가 loud 하게 잡는다 (silent 경로 없음).
    // =========================================================================
    wire        e_sgn  = eff_word[63];
    wire [10:0] e_E    = eff_word[62:52];
    wire [51:0] e_m    = eff_word[51:0];
    wire        e_zero = (e_E == 11'd0) & (e_m == 52'd0);

    // 11-bit two's-complement exponent (mod-2048 가산이 곧 인코딩)
    wire [10:0] w_e   = e_zero          ? 11'h400
                      : (e_E != 11'd0)  ? (e_E - 11'd1023)
                      : e_m[51]         ? 11'h401       // subnormal corner 1
                      :                   11'h400;      // subnormal corner 2
    wire [47:0] w_sig = e_zero          ? 48'd0
                      : (e_E != 11'd0)  ? {1'b1, e_m[51:5]}
                      : e_m[51]         ? e_m[51:4]
                      :                   e_m[50:3];

    wire [63:0] carry_field = {4'b0000, (e_zero ? 1'b0 : e_sgn), w_e, w_sig};

    // =========================================================================
    // DRAIN — PACK_FINAL: 정확히 1회 RNE-24 + flush-after-round FTZ
    // (§27.2.3; FP_AccLattice.v S4 관용구 동형 — rcarry 시 d_m25[22:0]
    //  verbatim: 2^24 로 오른 mantissa 의 하위 23 bit 는 이미 0)
    // =========================================================================
    wire [23:0]        d_m24  = w_sig[47:24];
    wire               d_grd  = w_sig[23];
    wire               d_stk  = |w_sig[22:0];
    wire               d_up   = d_grd & (d_stk | w_sig[24]);
    wire [24:0]        d_m25  = {1'b0, d_m24} + {24'b0, d_up};
    wire               d_rc   = d_m25[24];
    wire signed [11:0] d_e    = $signed({w_e[10], w_e});
    wire signed [12:0] d_ef   = {d_e[11], d_e} + {12'b0, d_rc};
    wire               d_ovf  = (d_ef >  13'sd127);
    wire               d_udf  = (d_ef < -13'sd126);
    wire [7:0]         d_bias = d_ef[7:0] + 8'd127;

    wire [31:0] drain_w = e_zero ? 32'h0000_0000
                        : d_ovf  ? {e_sgn, 8'hFF, 23'd0}
                        : d_udf  ? {e_sgn, 31'd0}
                        :          {e_sgn, d_bias, d_m25[22:0]};

    // =========================================================================
    // FILL validation (§27.2.2 (i)-(iii) — golden fp64_to_wide 동형)
    // =========================================================================
    wire [10:0] f_E = cmd_word_i[62:52];
    wire [51:0] f_m = cmd_word_i[51:0];
    wire f_naninf = (f_E == 11'h7FF);                       // (i)
    wire f_zero   = (f_E == 11'd0) & (f_m == 52'd0);        // (iii) ±0
    wire f_sub    = (f_E == 11'd0) & (f_m != 52'd0);
    wire f_sub_ok = f_m[51] ? (f_m[3:0] == 4'h0)            // binade -1023
                  : (f_m[50] & (f_m[2:0] == 3'h0));         // binade -1024
    wire fill_bad = f_naninf                                        // (i)
                  | (~f_naninf & (f_E != 11'd0) & (|f_m[4:0]))      // (ii)
                  | (f_sub & ~f_sub_ok);                            // (ii)
    wire [63:0] fill_store = f_zero ? 64'h0 : cmd_word_i;   // -0 -> +0

    // =========================================================================
    // 명령 판정 — 검사 우선순위: window -> ownership -> 값 검증 (golden §4)
    // =========================================================================
    wire wave_ref_win = cmd_wave & win_wave;
    wire wave_ref_own = cmd_wave & ~win_wave & ~own_match;
    wire wave_acc     = cmd_wave & ~win_wave &  own_match;

    wire fill_foreign  = cmd_tag_v_i & (cmd_tag_i != cmd_stream_i);
    wire fill_ref_win  = cmd_fill & win_fdz;
    wire fill_ref_for  = cmd_fill & ~win_fdz &  fill_foreign;
    wire fill_ref_busy = cmd_fill & ~win_fdz & ~fill_foreign & eff_ov;
    wire fill_ref      = fill_ref_win | fill_ref_for | fill_ref_busy;
    wire fill_vf       = cmd_fill & ~fill_ref &  fill_bad;
    wire fill_acc      = cmd_fill & ~fill_ref & ~fill_bad;

    wire drain_ref_win = cmd_drain & win_fdz;
    wire drain_ref_own = cmd_drain & ~win_fdz & ~own_match;
    wire drain_acc     = cmd_drain & ~win_fdz &  own_match;

    wire zero_ref_win  = cmd_zero & win_fdz;
    wire zero_ref_own  = cmd_zero & ~win_fdz & ~own_match;
    wire zero_acc      = cmd_zero & ~win_fdz &  own_match;

    wire spill_ref     = cmd_spill & (win_fdz | ~own_match);
    wire spill_acc     = cmd_spill & ~win_fdz & own_match;

    wire any_ref = wave_ref_win | wave_ref_own | fill_ref
                 | drain_ref_win | drain_ref_own
                 | zero_ref_win | zero_ref_own | spill_ref;
    wire cmd_nonreq = cmd_wave | cmd_fill | cmd_drain | cmd_zero | cmd_spill;

    // ---- lattice 결선 출력 (IF-1) — srst 중 start 억제 (방어적) ----
    assign lat_start_o = wave_acc & ~srst_i;
    assign lat_carry_o = (wave_acc & ~srst_i) ? carry_field : POISON_FIELD;

    // ---- 관측 read port ----
    assign dbg_word_o    = words[dbg_slot_i];
    assign dbg_owner_v_o = own_v[dbg_slot_i];
    assign dbg_owner_o   = own_id[dbg_slot_i];

    // =========================================================================
    // 상태 갱신 — 단일 always. words 의 NBA 순서 = golden §3 처리 순서
    // ((1) writeback -> (2) commit scrub -> (3) 명령; 같은 index 중복 시
    //  뒤가 이긴다 — 분석상 도달 불가/값 동일 케이스뿐이나 순서로 명문화)
    // =========================================================================
    integer i;
    always @(posedge clk) begin
        if (srst_i) begin
            for (i = 0; i < N_SLOTS; i = i + 1) begin
                words[i]  <= 64'h0;                 // power-on: canonical +0
                own_v[i]  <= 1'b0;                  // 전 slot 무소유
                own_id[i] <= {STREAM_W{1'b0}};
                wq[i]     <= 4'd0;
            end
            pend_v   <= 1'b0;
            wb_v_sh  <= {LATENCY{1'b0}};
            sticky_q <= 14'b0;
            resp_v_q <= 1'b0; resp_refused_q <= 1'b0; resp_vfault_q <= 1'b0;
            acq_v_q  <= 1'b0; acq_reject_q   <= 1'b0;
            drain_v_q <= 1'b0;
            spill_v_q <= 1'b0;
        end
        else begin
            // ---- 창 카운터 (수용 WAVE 는 8 로 재장전, 그 외 0 까지 -1) ----
            for (i = 0; i < N_SLOTS; i = i + 1) begin
                if (wave_acc && (cmd_slot_i == i[SLOT_AW-1:0]))
                    wq[i] <= 4'd8;
                else if (wq[i] != 4'd0)
                    wq[i] <= wq[i] - 4'd1;
            end

            // ---- (1) writeback (carry-vfault 는 억제 + sticky — §5 항 1) ----
            if (wb_ok)
                words[wb_head_s] <= lat_bank_i;
            if (wb_head_v & lat_fault_i)
                sticky_q[FC_CARRY_VFAULT] <= 1'b1;
            if (wb_head_v ^ lat_done_i)             // 결선 무결성 자기검사
                sticky_q[FC_LAT_DESYNC] <= 1'b1;

            // wb 파이프 shift + 수용 WAVE 삽입
            wb_v_sh <= {wb_v_sh[LATENCY-2:0], wave_acc};
            for (i = LATENCY - 1; i > 0; i = i - 1)
                wb_sl_sh[i] <= wb_sl_sh[i-1];
            if (wave_acc)
                wb_sl_sh[0] <= cmd_slot_i;

            // ---- (2) acquire commit / reject (REQ 의 t+1) ----
            acq_v_q      <= pend_v;
            acq_reject_q <= pend_v & own_v[pend_sl];
            if (commit_ok) begin
                own_v[pend_sl]  <= 1'b1;
                own_id[pend_sl] <= pend_st;
                words[pend_sl]  <= 64'h0;           // commit_zero scrub
            end
            if (pend_v & own_v[pend_sl])
                sticky_q[FC_ACQ_REJECT] <= 1'b1;    // RejectOwn — 불변 거부
            if (pend_v)
                pend_v <= 1'b0;

            // ---- (3) 명령 효과 ----
            if (cmd_req) begin                      // pend 는 정확히 1 cycle
                pend_v  <= 1'b1;                    // 점유 — commit cycle 의
                pend_st <= cmd_stream_i;            // 재-REQ 도 안전 (clear
                pend_sl <= cmd_slot_i;              // 뒤 set — NBA 순서)
            end
            if (fill_acc) begin
                words[cmd_slot_i]  <= fill_store;
                own_v[cmd_slot_i]  <= 1'b1;         // acquire-by-fill
                own_id[cmd_slot_i] <= cmd_stream_i;
            end
            if (zero_acc)
                words[cmd_slot_i] <= 64'h0;         // IF-4 (owner 불변)
            if (drain_acc) begin
                own_v[cmd_slot_i] <= 1'b0;          // release — word 잔존
                drain_q <= drain_w;
            end
            if (spill_acc) begin
                own_v[cmd_slot_i] <= 1'b0;          // release — word 잔존
                spill_q <= eff_word;
            end
            drain_v_q <= drain_acc;
            spill_v_q <= spill_acc;

            resp_v_q       <= cmd_nonreq;
            resp_refused_q <= any_ref;
            resp_vfault_q  <= fill_vf;

            // ---- sticky 원인 bit (전부 set-only — 해제는 srst_i 뿐) ----
            if (wave_ref_win)  sticky_q[FC_WAVE_WINDOW]  <= 1'b1;
            if (wave_ref_own)  sticky_q[FC_WAVE_OWNER]   <= 1'b1;
            if (fill_ref_win)  sticky_q[FC_FILL_WINDOW]  <= 1'b1;
            if (fill_ref_for)  sticky_q[FC_FILL_FOREIGN] <= 1'b1;
            if (fill_ref_busy) sticky_q[FC_FILL_BUSY]    <= 1'b1;
            if (fill_vf)       sticky_q[FC_FILL_VALID]   <= 1'b1;
            if (drain_ref_win) sticky_q[FC_DRAIN_WINDOW] <= 1'b1;
            if (drain_ref_own) sticky_q[FC_DRAIN_OWNER]  <= 1'b1;
            if (zero_ref_win)  sticky_q[FC_ZERO_WINDOW]  <= 1'b1;
            if (zero_ref_own)  sticky_q[FC_ZERO_OWNER]   <= 1'b1;
            if (spill_ref | cmd_unk)
                sticky_q[FC_PROTO_GUARD] <= 1'b1;
        end
    end

endmodule

/* verilator lint_on PROCASSINIT */
/* verilator lint_on UNUSEDSIGNAL */
