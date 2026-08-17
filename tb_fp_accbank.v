// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

// =============================================================================
// tb_fp_accbank.v — FP_AccLattice + FP_AccBank 통합 TB (하류 ③ 검증 계획
// (a)/(b) 의 실행체 — spec §27.6 "하류 ③ 검증 계획 선공표" 3계열 중 TB 몫)
//
// 결선: FP_AccBank 가 lattice 의 실제 인터페이스 (start_i/carry_i <-
// lat_start_o/lat_carry_o, done_q/bank_q/fault_q -> lat_*_i) 로 직결된다.
// TB 는 dispatcher (WAVE 명령 + 8-operand x 4 beat ops 인가 — §27.2.1
// amendment 의 dispatch 스케줄) 겸 판정기다. carry 는 항상 bank 가 공급
// (IF-1) — TB 는 carry 를 만지지 않는다.
//
// PHASE A — TLC 유도 directed 14건 (proofs/tla/derived/
//   tla_directed_scenarios.json 의 DT-01..08 + WT-01..06; §27.6 (a)):
//   guard-별 삭제 실험의 TLC 반례 trace 를 bank 자극 열로 사상하고, 전
//   가드 armed RTL 이 같은 자극 열을 거부 + sticky 로 종결함을 cycle
//   정밀 판정한다 — sticky 원인 vector 를 매 cycle 비교 (발화 cycle
//   이전 0 / 이후 해당 원인 one-hot; 조기·지연 발화 양방향 loud).
//   witness 6건은 fault 없는 도달성 (전 구간 sticky==0 + 상태 궤적).
//   * payload binding (JSON payload_binding): 토큰 = 단일 nonzero 곱
//     (2^0/2^1/2^2) + 31 canonical zero — pairwise 구별, 체이닝 기대값
//     은 exact 합 (1.0 -> 1+2=3.0 / 4.0) 의 fp64 인코딩.
//   * ghost (l) — spill image owner-tag 캐리어: TB 의 mem ghost 배열이
//     캐리어를 실물화하고 (JSON ghost_prerequisites 기록 그대로), 대조
//     자체는 FP_AccBank 의 cmd_tag_* hw 비교다 (FILL_FOREIGN 판정).
//   * ghost (h) — DRAIN_STRAY 의 issued==K 전제는 TB 스케줄이 보장.
//   * 기록 (JSON 대비 정정 1건): DT-05 invariant 문언 "bank0 word ==
//     W(sA#1) 잔존" 은 자기 자신의 DT-02 semantics (GRANT 의 commit_zero
//     scrub) 와 모순 — cycle 12 GRANT(sB) 가 scrub 하므로 물리 word 는
//     canonical zero 다. 본 TB 는 golden bank_execute semantics (scrub)
//     를 판정 기준으로 삼는다. sticky 원인/발화 cycle/mem 불변/owner
//     무주 판정은 JSON 그대로다.
//
// PHASE B — golden 시나리오 전량 (include/generated/bank_scenarios.hex,
//   349 시나리오 = directed 49 + rand_interleave 300; §27.6 (b)/(c) + ④
//   GATE V20-3 교차곱 append 6건 — bank_scenarios_contract.md §10 (ii):
//   window_fill offset 6 / window_zero offset 4 / window_spill offset
//   {2,4,5,6} 이 기존 343 스트림 뒤에 붙어 창-거부 4 클래스 x offset 1..7
//   전수가 성립한다; 아래 family 계수 가드가 append 소실을 loud 하게 잡는다):
//   record 계약 (bank_scenarios_contract.md §6) 대로 파싱해 재생하고
//   전 관측층을 bit-exact 판정한다:
//     * 명령별 refused/vfault (resp_*_q @ t+1, REQ 는 acq_*_q @ t+2;
//       UNK (미정의 opcode 6/7) 는 응답 무발행 — resp_v==0 판정)
//     * WAVE 스냅샷 (cycle t+7 말 slot word — dbg port @ t+8)
//     * FILL 스냅샷 (cycle t 말 — @ t+1) / DRAIN fp32 (@ t+1)
//     * SPILL — 수용: spill_v/spill_q (@ t+1) + word 잔존 스냅샷; 거부
//       (창 내/비-owner): PROTO_GUARD sticky + word 불변 스냅샷 + spill
//       무발행. UNK — sticky + 상태 무변경 스냅샷 (2026-08-16 적대
//       재실측 폐쇄: spill_ref/cmd_unk 절단 변이의 escape 봉인)
//     * sticky 궤적 — 기대 최초 발화 가시 cycle 전 0 / 후 1 (매 cycle)
//     * lattice done/fault 궤적 (수용 WAVE 당 done 정확히 t+7, carry
//       vfault 의 fault_q 동반 — 매 cycle 양방향)
//     * 시나리오 말 sticky / owner map / slot word 4개
//   체이닝 경계 7/8, 위반 4/5/6, gap 1/3/17 (같은/타 slot — §27.6 (b)(2)
//   "gap-후 재시작" 커버리지 경계의 명시 폐쇄), 창 경계 offset 1/3/7/8,
//   FILL validation, carry-lane fault (d)/(e), ownership 계열, 랜덤
//   인터리브 300 이 전부 이 스트림 안이다 (계약 §7 family 표).
//   시나리오 간 srst_i 로 power-on 상태 복원 (계약 §1 power-on pin).
//
// PHASE P2 — pin 2 강화형 fault (c) 봉인 (§27.2.1 amendment pin 2 의 ③
//   구현 의무 — FP_AccLattice.v carry-lane 배선의 직접 판정):
//   bank 경유로는 이 fault 가 구조적으로 도달 불가다 (bank 저장 word 는
//   FILL validation/writeback 산출 — 항상 normalized 또는 canonical zero;
//   pin 2 의 "구조적 보장 경로" 그 자체). 따라서 별도 lattice 인스턴스
//   (u_lat2) 를 TB 가 직접 구동해 판정한다:
//   (1) carry = 1-bit un-normalized raw (sig=2^46, e=0) — 약형 (c) 는
//       통과시키고 강화형만 잡는 판별 벡터 -> fault_q==1 필수 (약형
//       배선이 남아 있으면 여기서 FAIL — 배선 증명).
//   (2) 같은 필드를 곱 lane (addend 0) 에 인가한 대조 wave -> fault 0
//       + wide bit-exact (0.5) — 곱 lane 약형 판정 불변의 증명.
//
// PHASE C — discriminator 자기시험 (tautology 방지 — 프로젝트 기적발
//   결함 유형; tb_fp_acclattice.v 의 오답 참조 관용구):
//   ownership 검사 절단 오답 모델 — "owner 를 무시하고 window 만 검사"
//   하는 RTL 변이의 행위 모델 — 의 예측 (수용) 이, owner-거부 WAVE
//   명령에서 golden 기대 (거부) 와 실제로 갈라짐을 판정 경로 그대로
//   1회 이상 시연한다 (분류는 TB 자체의 창 모델로 window-거부/owner-
//   거부를 구별). 0회면 판정기 tautology 로 보고 TB 전체 FAIL.
//
// 판정: 모든 비교 bit-exact, 표본률 논증 금지 (계약 §6). 실행:
//   $ verilator --binary --timing -j 0 -Wno-TIMESCALEMOD \
//       FP_AccLattice.v FP_AccBank.v tb_fp_accbank.v \
//       --top-module tb_fp_accbank -o tb_accbank --Mdir /tmp/wt_accbank_obj
//   $ /tmp/wt_accbank_obj/tb_accbank        (repo root 에서)
//   iverilog: iverilog -g2012 -o /tmp/tb_accbank.vvp FP_AccLattice.v \
//       FP_AccBank.v tb_fp_accbank.v && vvp /tmp/tb_accbank.vvp
// TB 행위 모델은 dynamic part-select / 변수 shift 를 쓴다 — RTL 은 clean,
// TB 는 면책 (tb_fp_acclattice.v 헤더의 일탈 기록과 동형).
// =============================================================================

`timescale 1ns / 1ps

/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off WIDTHEXPAND */
// (TB 행위 모델의 integer/비트폭 혼용 — RTL 이 아님; 양 RTL 은 -Wall clean.)

module tb_fp_accbank;

    localparam integer TB_N    = 8;          // lattice PRODUCTS_PER_BEAT
    localparam integer NB      = 32 / TB_N;  // = II = 4
    localparam integer LATENCY = NB + 3;     // = 7

    localparam integer N_SCEN_GOLD = 349;    // bank_scenarios.hex 시나리오 수
    localparam integer N_REC_GOLD  = 39878;  // 총 record 수 (계약 §7)
    localparam integer N_SCEN_TLC  = 14;     // DT-01..08 + WT-01..06

    localparam [63:0] CANON  = 64'h0400_0000_0000_0000;  // wide canonical zero
    localparam [63:0] F64_1  = 64'h3FF0_0000_0000_0000;  // 1.0
    localparam [63:0] F64_3  = 64'h4008_0000_0000_0000;  // 3.0
    localparam [63:0] F64_4  = 64'h4010_0000_0000_0000;  // 4.0
    localparam [31:0] F32_3  = 32'h4040_0000;            // RNE24(3.0)

    // FP_AccBank op 인코딩 (FP_AccBank.v localparam 과 1:1)
    localparam [2:0] OP_REQ = 3'd0, OP_WAVE = 3'd1, OP_FILL = 3'd2,
                     OP_DRAIN = 3'd3, OP_ZERO = 3'd4, OP_SPILL = 3'd5;

    // sticky cause 색인 (FP_AccBank.v 헤더 표)
    localparam integer FC_ACQ_REJECT = 0, FC_WAVE_OWNER = 2,
                       FC_FILL_FOREIGN = 4, FC_FILL_BUSY = 5,
                       FC_DRAIN_OWNER = 8, FC_ZERO_OWNER = 10;

    // TLA+ stream id (tla_directed_scenarios.json constants.streams)
    localparam [3:0] S_A = 4'd0;             // sA — pcid 0
    localparam [3:0] S_B = 4'd2;             // sB — pcid 2 (ALIAS)

    // ---- clock ----
    reg clk = 1'b0;
    always #5 clk = ~clk;

    // ---- DUT 결선 ----
    reg               srst;
    reg               cmd_v;
    reg  [2:0]        cmd_op;
    reg  [3:0]        cmd_st;
    reg  [5:0]        cmd_sl;
    reg  [63:0]       cmd_word;
    reg               cmd_tag_v;
    reg  [3:0]        cmd_tag;
    reg  [5:0]        dbg_sl;
    reg  [TB_N*64-1:0] ops;

    wire        lat_start;
    wire [63:0] lat_carry;
    wire [527:0] l_res;
    wire [63:0] l_wide, l_bank;
    wire [31:0] l_fp32;
    wire        l_fault, l_done;

    wire        resp_v, resp_ref, resp_vf, acq_v, acq_rej;
    wire        drain_v, spill_v, bank_fault;
    wire [31:0] drain_w32;
    wire [63:0] spill_w, dbg_word;
    wire [13:0] causes;
    wire        dbg_ov;
    wire [3:0]  dbg_own;

    FP_AccLattice #(.PRODUCTS_PER_BEAT(TB_N)) u_lat (
        .clk        (clk),
        .start_i    (lat_start),
        .ops_i      (ops),
        .carry_i    (lat_carry),
        .resolved_q (l_res),
        .wide_q     (l_wide),
        .bank_q     (l_bank),
        .fp32_q     (l_fp32),
        .fault_q    (l_fault),
        .done_q     (l_done)
    );

    // ---- PHASE P2 전용 lattice 인스턴스 — TB 직접 구동 (헤더 참조) ----
    reg               p2_start;
    reg  [TB_N*64-1:0] p2_ops;
    reg  [63:0]       p2_carry;
    wire [527:0] p2_res;
    wire [63:0]  p2_wide, p2_bank;
    wire [31:0]  p2_fp32;
    wire         p2_fault, p2_done;

    FP_AccLattice #(.PRODUCTS_PER_BEAT(TB_N)) u_lat2 (
        .clk        (clk),
        .start_i    (p2_start),
        .ops_i      (p2_ops),
        .carry_i    (p2_carry),
        .resolved_q (p2_res),
        .wide_q     (p2_wide),
        .bank_q     (p2_bank),
        .fp32_q     (p2_fp32),
        .fault_q    (p2_fault),
        .done_q     (p2_done)
    );

    FP_AccBank #(.SLOT_AW(6), .N_SLOTS(64), .STREAM_W(4),
                 .LATENCY(LATENCY)) u_bank (
        .clk           (clk),
        .srst_i        (srst),
        .cmd_v_i       (cmd_v),
        .cmd_op_i      (cmd_op),
        .cmd_stream_i  (cmd_st),
        .cmd_slot_i    (cmd_sl),
        .cmd_word_i    (cmd_word),
        .cmd_tag_v_i   (cmd_tag_v),
        .cmd_tag_i     (cmd_tag),
        .lat_start_o   (lat_start),
        .lat_carry_o   (lat_carry),
        .lat_done_i    (l_done),
        .lat_bank_i    (l_bank),
        .lat_fault_i   (l_fault),
        .resp_v_q      (resp_v),
        .resp_refused_q(resp_ref),
        .resp_vfault_q (resp_vf),
        .acq_v_q       (acq_v),
        .acq_reject_q  (acq_rej),
        .drain_v_q     (drain_v),
        .drain_q       (drain_w32),
        .spill_v_q     (spill_v),
        .spill_q       (spill_w),
        .fault_causes_o(causes),
        .fault_o       (bank_fault),
        .dbg_slot_i    (dbg_sl),
        .dbg_word_o    (dbg_word),
        .dbg_owner_v_o (dbg_ov),
        .dbg_owner_o   (dbg_own)
    );

    // ---- 시나리오 slot (0..3) -> 물리 slot 사상 (TB 자유 — 계약 §1;
    //      bank bit = addr[5]: slot 0/1 -> bank0, 2/3 -> bank1 로 분산해
    //      주소 decode 양쪽 bank 를 실사용) ----
    function [5:0] f_slot;
        input [1:0] s;
        f_slot = {s, 4'b1010};
    endfunction

    // ---- fp64 -> wide field (FP_AccBank 변환기의 행위 모델 —
    //      phase A 의 IF-1 carry 관측 기대값) ----
    function [63:0] f64f;
        input [63:0] w;
        reg [10:0] E;
        reg [51:0] m;
        begin
            E = w[62:52];
            m = w[51:0];
            if (E == 0 && m == 0)
                f64f = CANON;
            else if (E != 0)
                f64f = {4'b0, w[63], E - 11'd1023, 1'b1, m[51:5]};
            else if (m[51])
                f64f = {4'b0, w[63], 11'h401, m[51:4]};
            else
                f64f = {4'b0, w[63], 11'h400, m[50:3]};
        end
    endfunction

    // ---- 2^k 단일 곱 payload 의 wide field (phase A 토큰) ----
    function [63:0] fpk;
        input integer k;
        fpk = {4'b0, 1'b0, k[10:0], 1'b1, 47'b0};
    endfunction

    // =========================================================================
    // 오류 계정 + discriminator
    // =========================================================================
    integer errors;
    integer disc_hits;
    reg     disc_shown;
    integer tlc_pass, gdir_pass, rand_pass, gdir_total, rand_total;
    integer fam_cnt [0:22];

    task fail_v;
        input [175:0] tag;              // 층 이름 (ASCII, 좌측 0-패딩)
        input integer scen;
        input integer c;
        input [63:0]  got;
        input [63:0]  expd;
        begin
            errors = errors + 1;
            if (errors <= 25) begin
                $display("FAIL[%0s] scen=%0d cyc=%0d", tag, scen, c);
                $display("  got = %h  exp = %h", got, expd);
            end
        end
    endtask

    // discriminator: owner-거부 WAVE 에서 오답 모델 (owner 무시) 예측이
    // golden 기대와 갈라짐 — 1회 시연 + 계수
    task disc_hit;
        input integer scen;
        input integer c;
        begin
            disc_hits = disc_hits + 1;
            if (!disc_shown) begin
                disc_shown = 1'b1;
                $display("[DISC-EXPECTED-FAIL] scen %0d cyc %0d:", scen, c);
                $display("  ownership 절단 오답 모델 (owner 무시, window 만");
                $display("  검사) 은 이 WAVE 를 수용했을 것 — golden 기대는");
                $display("  거부다. 오답 모델이 판정 경로에서 실제 FAIL 을");
                $display("  유발함의 1회 시연 (비-tautology 증명).");
            end
        end
    endtask

    // =========================================================================
    // 공용 driver 상태 (한 시점에 한 runner 만 사용)
    // =========================================================================
    integer wv_on, wv_t, wv_p;          // golden phase: bmem 기반 beat 인가
    integer aw_on, aw_t;                // TLC phase: 단일 곱 beat 인가
    reg [63:0] aw_field;

    task drive_idle;
        begin
            cmd_v = 1'b0; cmd_op = 3'd0; cmd_st = 4'd0; cmd_sl = 6'd0;
            cmd_word = 64'd0; cmd_tag_v = 1'b0; cmd_tag = 4'd0;
        end
    endtask

    task scen_reset;                    // 시나리오 격리 (power-on 복원)
        begin
            drive_idle;
            ops = {TB_N{CANON}};
            srst = 1'b1;
            @(negedge clk);
            srst = 1'b0;
            @(negedge clk);
        end
    endtask

    // =========================================================================
    // PHASE A — TLC 유도 directed 시나리오 러너
    // =========================================================================
    integer dn;                          // op 수
    integer d_t   [0:15];
    reg [2:0]  d_op [0:15];
    reg [3:0]  d_st [0:15];
    integer d_mem [0:15];                // FILL/SPILL 의 image slot
    reg        d_ref [0:15];             // 기대 거부
    integer d_pk  [0:15];                // WAVE payload 지수 (2^k)
    reg [63:0] d_wb [0:15];              // 수용 WAVE 의 기대 writeback word
    reg [31:0] d_f32 [0:15];             // 수용 DRAIN 의 기대 fp32
    integer d_cause, d_fcyc, dH;         // 기대 sticky 원인/발화 cycle/horizon

    // slot0 기대 궤적 (cycle c 에 관측되는 값 — 레지스터 가시성 기준)
    reg [63:0] tw   [0:63];
    reg        tov  [0:63];
    reg [3:0]  town [0:63];

    // spill image ghost (JSON ghost (l) 캐리어 — TB 실물화)
    reg        mem_v   [0:1];
    reg [3:0]  mem_own [0:1];
    reg [63:0] mem_w   [0:1];

    task d_clr;
        integer i;
        begin
            dn = 0; d_cause = -1; d_fcyc = -1; dH = 0;
            for (i = 0; i < 16; i = i + 1) begin
                d_t[i] = 0; d_op[i] = 3'd0; d_st[i] = 4'd0; d_mem[i] = 0;
                d_ref[i] = 1'b0; d_pk[i] = 0; d_wb[i] = 64'd0;
                d_f32[i] = 32'd0;
            end
        end
    endtask

    task d_add;
        input integer t;
        input [2:0]  op;
        input [3:0]  st;
        input integer m;
        input        rf;
        input integer pk;
        input [63:0] wb;
        input [31:0] f32;
        begin
            d_t[dn] = t; d_op[dn] = op; d_st[dn] = st; d_mem[dn] = m;
            d_ref[dn] = rf; d_pk[dn] = pk; d_wb[dn] = wb; d_f32[dn] = f32;
            dn = dn + 1;
        end
    endtask

    // 시나리오 정의 — tla_directed_scenarios.json 의 ops 열 1:1
    task d_build;
        input integer id;
        begin
            d_clr;
            case (id)
            1: begin // DT-01 — commit_free: RejectOwn + sticky, 탈취 없음
                d_add(0, OP_REQ, S_A, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(2, OP_REQ, S_B, 0, 1'b1, 0, 64'd0, 32'd0);
                d_cause = FC_ACQ_REJECT; d_fcyc = 3; dH = 11;
            end
            2: begin // DT-02 — commit_zero: stale SRAM scrub (fault 없음)
                d_add(0,  OP_REQ,   S_A, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(2,  OP_WAVE,  S_A, 0, 1'b0, 0, F64_1, 32'd0);
                d_add(10, OP_SPILL, S_A, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(11, OP_REQ,   S_B, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(13, OP_WAVE,  S_B, 0, 1'b0, 2, F64_4, 32'd0);
                dH = 22;
            end
            3: begin // DT-03 — acc_owner: stray WSTEP 거부 + sticky
                d_add(0,  OP_REQ,   S_A, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(2,  OP_SPILL, S_A, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(3,  OP_REQ,   S_B, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(5,  OP_WAVE,  S_A, 0, 1'b1, 0, 64'd0, 32'd0);
                d_add(12, OP_WAVE,  S_B, 0, 1'b0, 2, F64_4, 32'd0);
                d_cause = FC_WAVE_OWNER; d_fcyc = 5; dH = 21;
            end
            4: begin // DT-04 — drain_owner: stray drain (issued==K) 거부
                d_add(0,  OP_REQ,   S_A, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(2,  OP_WAVE,  S_A, 0, 1'b0, 0, F64_1, 32'd0);
                d_add(9,  OP_WAVE,  S_A, 0, 1'b0, 1, F64_3, 32'd0); // delta 7
                d_add(17, OP_SPILL, S_A, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(18, OP_REQ,   S_B, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(20, OP_WAVE,  S_B, 0, 1'b0, 2, F64_4, 32'd0);
                d_add(28, OP_DRAIN, S_A, 0, 1'b1, 0, 64'd0, 32'd0);
                d_cause = FC_DRAIN_OWNER; d_fcyc = 28; dH = 37;
            end
            5: begin // DT-05 — fill_owner: 외래 image FILL 거부 (leak 차단)
                d_add(0,  OP_REQ,   S_A, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(2,  OP_WAVE,  S_A, 0, 1'b0, 0, F64_1, 32'd0);
                d_add(10, OP_SPILL, S_A, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(11, OP_REQ,   S_B, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(13, OP_SPILL, S_B, 1, 1'b0, 0, 64'd0, 32'd0);
                d_add(14, OP_FILL,  S_B, 0, 1'b1, 0, 64'd0, 32'd0);
                d_cause = FC_FILL_FOREIGN; d_fcyc = 14; dH = 23;
            end
            6: begin // DT-06 — fill_bankfree: 자기 image, live 외래 bank
                d_add(0, OP_REQ,   S_A, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(2, OP_SPILL, S_A, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(3, OP_REQ,   S_B, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(5, OP_FILL,  S_A, 0, 1'b1, 0, 64'd0, 32'd0);
                d_cause = FC_FILL_BUSY; d_fcyc = 5; dH = 14;
            end
            7, 8: begin // DT-07 (zero_owner) / DT-08 (requesterid — 동일 자극)
                d_add(0,  OP_REQ,   S_A, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(2,  OP_WAVE,  S_A, 0, 1'b0, 0, F64_1, 32'd0);
                d_add(9,  OP_WAVE,  S_A, 0, 1'b0, 1, F64_3, 32'd0); // delta 7
                d_add(17, OP_ZERO,  S_B, 0, 1'b1, 0, 64'd0, 32'd0);
                d_add(18, OP_DRAIN, S_A, 0, 1'b0, 0, 64'd0, F32_3);
                d_cause = FC_ZERO_OWNER; d_fcyc = 17; dH = 27;
            end
            9: begin // WT-01 — 도달성: acquire 경합 상태 (reject 직전 절단)
                d_add(0, OP_REQ, S_A, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(2, OP_REQ, S_B, 0, 1'b0, 0, 64'd0, 32'd0);
                dH = 2;                 // cycle 3 의 자동 해소는 DT-01 몫
            end
            10: begin // WT-02 — 도달성: spilled + issued<K
                d_add(0, OP_REQ,   S_A, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(2, OP_SPILL, S_A, 0, 1'b0, 0, 64'd0, 32'd0);
                dH = 11;
            end
            11: begin // WT-03 — 도달성: spilled + issued==K
                d_add(0,  OP_REQ,   S_A, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(2,  OP_WAVE,  S_A, 0, 1'b0, 0, F64_1, 32'd0);
                d_add(9,  OP_WAVE,  S_A, 0, 1'b0, 1, F64_3, 32'd0);
                d_add(17, OP_SPILL, S_A, 0, 1'b0, 0, 64'd0, 32'd0);
                dH = 26;
            end
            12: begin // WT-04 — 도달성: 두 context image 공존
                d_add(0, OP_REQ,   S_A, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(2, OP_SPILL, S_A, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(3, OP_REQ,   S_B, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(5, OP_SPILL, S_B, 1, 1'b0, 0, 64'd0, 32'd0);
                dH = 14;
            end
            13: begin // WT-05 — 도달성: 자기 image ready + live 외래 owner
                d_add(0, OP_REQ,   S_A, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(2, OP_SPILL, S_A, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(3, OP_REQ,   S_B, 0, 1'b0, 0, 64'd0, 32'd0);
                dH = 12;
            end
            default: begin // 14: WT-06 — 도달성: zero-race 창 개방
                d_add(0, OP_REQ,  S_A, 0, 1'b0, 0, 64'd0, 32'd0);
                d_add(2, OP_WAVE, S_A, 0, 1'b0, 0, F64_1, 32'd0);
                dH = 11;
            end
            endcase
        end
    endtask

    // slot0 기대 궤적 산출 — 수용 op 의 효과 가시 cycle 에 반영
    // (REQ: t+2 commit / WAVE: t+8 writeback / DRAIN·SPILL: t+1 release /
    //  ZERO: t+1; 수용 FILL 은 본 directed 집합에 없음 — loud 차단)
    task d_traj;
        integer c, i;
        reg [63:0] cw;
        reg cov;
        reg [3:0] cown;
        begin
            cw = 64'd0; cov = 1'b0; cown = 4'd0;
            for (c = 0; c <= dH + 2; c = c + 1) begin
                for (i = 0; i < dn; i = i + 1) begin
                    if (!d_ref[i]) begin
                        if (d_op[i] == OP_REQ && c == d_t[i] + 2) begin
                            cov = 1'b1; cown = d_st[i]; cw = 64'd0;
                        end
                        if (d_op[i] == OP_WAVE && c == d_t[i] + 8)
                            cw = d_wb[i];
                        if (d_op[i] == OP_DRAIN && c == d_t[i] + 1)
                            cov = 1'b0;
                        if (d_op[i] == OP_SPILL && c == d_t[i] + 1)
                            cov = 1'b0;
                        if (d_op[i] == OP_ZERO && c == d_t[i] + 1)
                            cw = 64'd0;
                        if (d_op[i] == OP_FILL) begin
                            $display("FATAL: 수용 FILL 은 directed 궤적 미지원");
                            $fatal(1);
                        end
                    end
                end
                tw[c] = cw; tov[c] = cov; town[c] = cown;
            end
        end
    endtask

    integer da_last_acc;                 // discriminator 용 창 모델 (slot0)

    task run_directed;
        input integer id;
        integer c, i, k, e0;
        reg exp1, expd, expr, expq, expdr, expsp;
        reg [13:0] expc;
        begin
            d_build(id);
            d_traj;
            mem_v[0] = 1'b0; mem_v[1] = 1'b0;
            mem_own[0] = 4'd0; mem_own[1] = 4'd0;
            mem_w[0] = 64'd0; mem_w[1] = 64'd0;
            aw_on = 0; aw_t = 0; aw_field = CANON;
            da_last_acc = -100;
            e0 = errors;

            for (c = 0; c <= dH + 1; c = c + 1) begin
                @(negedge clk);
                drive_idle;
                // ---- WAVE beat 인가 (단일 곱 @ beat0 lane0, 나머지 canonical) ----
                if (aw_on && (c - aw_t) <= NB - 1) begin
                    ops = {TB_N{CANON}};
                    if (c == aw_t)
                        ops[63:0] = aw_field;
                end
                else begin
                    aw_on = 0;
                    ops = {TB_N{CANON}};
                end
                // ---- 명령 인가 ----
                k = -1;
                for (i = 0; i < dn; i = i + 1)
                    if (d_t[i] == c) k = i;
                if (k >= 0) begin
                    cmd_v = 1'b1;
                    cmd_op = d_op[k];
                    cmd_st = d_st[k];
                    cmd_sl = f_slot(2'd0);          // TLA bank 0 -> slot 0
                    if (d_op[k] == OP_WAVE) begin
                        aw_on = 1; aw_t = c; aw_field = fpk(d_pk[k]);
                        ops = {TB_N{CANON}};
                        ops[63:0] = aw_field;
                    end
                    if (d_op[k] == OP_FILL) begin   // ghost image 로부터
                        cmd_word  = mem_w[d_mem[k]];
                        cmd_tag_v = mem_v[d_mem[k]];
                        cmd_tag   = mem_own[d_mem[k]];
                    end
                end
                #1;
                // ---- (1) lattice start / IF-1 carry 관측 ----
                exp1 = (k >= 0) && (d_op[k] == OP_WAVE) && !d_ref[k];
                if (lat_start !== exp1)
                    fail_v("TLC-START", id, c, {63'd0, lat_start},
                           {63'd0, exp1});
                if (exp1 && (lat_carry !== f64f(tw[c+1])))
                    fail_v("TLC-CARRY-IF1", id, c, lat_carry, f64f(tw[c+1]));
                // ---- discriminator (owner-거부 WAVE) ----
                if (k >= 0 && d_op[k] == OP_WAVE && d_ref[k]) begin
                    if (!(c - da_last_acc < LATENCY))
                        disc_hit(id, c);            // 오답 모델은 수용했을 것
                end
                if (exp1)
                    da_last_acc = c;
                // ---- (2) sticky 원인 vector — cycle 정밀 (양방향) ----
                expc = (d_cause >= 0 && c >= d_fcyc + 1)
                     ? (14'd1 << d_cause) : 14'd0;
                if (causes !== expc)
                    fail_v("TLC-STICKY", id, c, {50'd0, causes},
                           {50'd0, expc});
                // ---- (3) lattice done 궤적 ----
                expd = 1'b0;
                for (i = 0; i < dn; i = i + 1)
                    if (d_op[i] == OP_WAVE && !d_ref[i]
                        && d_t[i] == c - LATENCY) expd = 1'b1;
                if (l_done !== expd)
                    fail_v("TLC-DONE", id, c, {63'd0, l_done}, {63'd0, expd});
                if (expd && (l_fault !== 1'b0))
                    fail_v("TLC-LFAULT", id, c, {63'd0, l_fault}, 64'd0);
                // ---- (4) resp/acq/drain/spill 응답 ----
                expr = 1'b0;
                for (i = 0; i < dn; i = i + 1)
                    if (d_t[i] == c - 1 && d_op[i] != OP_REQ) begin
                        expr = 1'b1;
                        if (resp_v !== 1'b1 || resp_ref !== d_ref[i]
                            || resp_vf !== 1'b0)
                            fail_v("TLC-RESP", id, c,
                                   {61'd0, resp_v, resp_ref, resp_vf},
                                   {61'd0, 1'b1, d_ref[i], 1'b0});
                    end
                if (!expr && resp_v !== 1'b0)
                    fail_v("TLC-RESP0", id, c, {63'd0, resp_v}, 64'd0);
                expq = 1'b0;
                for (i = 0; i < dn; i = i + 1)
                    if (d_t[i] == c - 2 && d_op[i] == OP_REQ) begin
                        expq = 1'b1;
                        if (acq_v !== 1'b1 || acq_rej !== d_ref[i])
                            fail_v("TLC-ACQ", id, c,
                                   {62'd0, acq_v, acq_rej},
                                   {62'd0, 1'b1, d_ref[i]});
                    end
                if (!expq && acq_v !== 1'b0)
                    fail_v("TLC-ACQ0", id, c, {63'd0, acq_v}, 64'd0);
                expdr = 1'b0;
                for (i = 0; i < dn; i = i + 1)
                    if (d_t[i] == c - 1 && d_op[i] == OP_DRAIN
                        && !d_ref[i]) begin
                        expdr = 1'b1;
                        if (drain_v !== 1'b1 || drain_w32 !== d_f32[i])
                            fail_v("TLC-DRAIN", id, c, {32'd0, drain_w32},
                                   {32'd0, d_f32[i]});
                    end
                if (!expdr && drain_v !== 1'b0)
                    fail_v("TLC-DRAIN0", id, c, {63'd0, drain_v}, 64'd0);
                expsp = 1'b0;
                for (i = 0; i < dn; i = i + 1)
                    if (d_t[i] == c - 1 && d_op[i] == OP_SPILL
                        && !d_ref[i]) begin
                        expsp = 1'b1;
                        if (spill_v !== 1'b1 || spill_w !== tw[c-1])
                            fail_v("TLC-SPILL", id, c, spill_w, tw[c-1]);
                        // ghost image 기록 (owner-tag 캐리어 — JSON (l))
                        mem_v[d_mem[i]]   = 1'b1;
                        mem_own[d_mem[i]] = d_st[i];
                        mem_w[d_mem[i]]   = tw[c-1];
                    end
                if (!expsp && spill_v !== 1'b0)
                    fail_v("TLC-SPILL0", id, c, {63'd0, spill_v}, 64'd0);
                // ---- (5) slot0 word/owner 궤적 — 매 cycle 불변식 ----
                dbg_sl = f_slot(2'd0);
                #0.2;
                if (dbg_word !== tw[c])
                    fail_v("TLC-WORD", id, c, dbg_word, tw[c]);
                if (dbg_ov !== tov[c]
                    || (tov[c] && dbg_own !== town[c]))
                    fail_v("TLC-OWNER", id, c, {59'd0, dbg_ov, dbg_own},
                           {59'd0, tov[c], town[c]});
            end
            if (errors == e0)
                tlc_pass = tlc_pass + 1;
            else
                $display("== TLC 시나리오 %0d FAIL (누적 오류 %0d) ==",
                         id, errors - e0);
            scen_reset;
        end
    endtask

    // =========================================================================
    // PHASE B — golden 시나리오 스트림 러너 (bank_scenarios.hex)
    // =========================================================================
    reg [63:0] bmem [0:39999];
    integer bp;                          // record 포인터

    integer g_ncmd, g_fam, g_idx;
    integer gt   [0:63];
    reg [2:0]  gop [0:63];
    reg [3:0]  gst [0:63];
    reg [1:0]  gsl [0:63];
    reg        gref [0:63];
    reg        gvf  [0:63];
    reg [63:0] gword [0:63];
    reg [63:0] gexpw [0:63];
    reg [63:0] gdrain [0:63];
    reg [63:0] gspill [0:63];            // SPILL 수용 시 기대 spill_q
    integer gprod [0:63];
    reg        g_stk_end;
    reg [31:0] g_omap;
    reg [63:0] g_fw [0:3];
    integer gH, g_vis;

    integer twin   [0:3];                // discriminator 창 모델 (시나리오 slot)
    integer twin_v [0:3];

    task parse_golden;                   // bmem[bp] 에서 1 시나리오 파싱
        integer p, k, nrec;
        reg [63:0] h;
        begin
            h = bmem[bp];
            if (h[63:56] !== 8'h01) begin
                $display("FATAL: BEGIN tag 아님 @ record %0d (%h)", bp, h);
                $fatal(1);
            end
            g_idx  = h[55:40];
            g_fam  = h[39:32];
            nrec   = h[31:16];
            g_ncmd = h[7:0];
            if (h[15:8] !== 8'd4 || g_ncmd > 63) begin
                $display("FATAL: BEGIN 필드 위반 @ scen %0d", g_idx);
                $fatal(1);
            end
            p = bp + 1;
            for (k = 0; k < g_ncmd; k = k + 1) begin
                h = bmem[p]; p = p + 1;
                case (h[63:56])         // 계약 §6 record 태그 -> bank op
                    8'h10: gop[k] = OP_REQ;
                    8'h11: gop[k] = OP_WAVE;
                    8'h12: gop[k] = OP_FILL;
                    8'h13: gop[k] = OP_DRAIN;
                    8'h14: gop[k] = OP_ZERO;
                    8'h15: gop[k] = OP_SPILL;
                    8'h16: begin        // UNK — [42:40] = 원 opcode (6/7)
                        gop[k] = h[42:40];
                        if (gop[k] <= OP_SPILL || h[47] !== 1'b1) begin
                            $display("FATAL: UNK record 위반 @ scen %0d (%h)",
                                     g_idx, h);
                            $fatal(1);
                        end
                    end
                    default: begin
                        $display("FATAL: 명령 태그 %h @ scen %0d", h[63:56],
                                 g_idx);
                        $fatal(1);
                    end
                endcase
                gst[k]  = h[55:52];
                gsl[k]  = h[49:48];
                gref[k] = h[47];
                gvf[k]  = h[46];
                gt[k]   = h[31:0];
                if (gop[k] == OP_WAVE) begin
                    gprod[k] = p; p = p + 32;
                    gexpw[k] = bmem[p]; p = p + 1;
                end
                else if (gop[k] == OP_FILL) begin
                    gword[k] = bmem[p];
                    gexpw[k] = bmem[p+1];
                    p = p + 2;
                end
                else if (gop[k] == OP_DRAIN) begin
                    gdrain[k] = bmem[p]; p = p + 1;
                    if (gdrain[k][32] !== ~gref[k])
                        fail_v("G-DRAINREC", g_idx, gt[k], gdrain[k],
                               {31'd0, ~gref[k], 32'd0});
                end
                else if (gop[k] == OP_SPILL) begin
                    gspill[k] = bmem[p];        // 수용 시 기대 spill_q
                    gexpw[k]  = bmem[p+1];      // cycle t 말 word 스냅샷
                    p = p + 2;
                    if (gref[k] && gspill[k] !== 64'd0)
                        fail_v("G-SPILLREC", g_idx, gt[k], gspill[k], 64'd0);
                end
                else if (gop[k] > OP_SPILL) begin   // UNK
                    gexpw[k] = bmem[p];         // 상태 무변경 스냅샷
                    p = p + 1;
                end
            end
            h = bmem[p];
            if (h[63:56] !== 8'h0F) begin
                $display("FATAL: END tag 아님 @ scen %0d", g_idx);
                $fatal(1);
            end
            g_stk_end = h[48];
            g_omap    = h[47:16];
            g_fw[0] = bmem[p+1]; g_fw[1] = bmem[p+2];
            g_fw[2] = bmem[p+3]; g_fw[3] = bmem[p+4];
            if (p + 5 - bp !== nrec) begin
                $display("FATAL: record 수 불일치 @ scen %0d (%0d != %0d)",
                         g_idx, p + 5 - bp, nrec);
                $fatal(1);
            end
            bp = bp + nrec;
            // horizon (계약 §6: 마지막 명령 + 7 + 2) / sticky 최초 가시 cycle
            gH = 0; g_vis = -1;
            for (k = 0; k < g_ncmd; k = k + 1) begin
                if (gt[k] > gH) gH = gt[k];
                if (gref[k]) begin
                    if (g_vis < 0
                        || gt[k] + ((gop[k] == OP_REQ) ? 2 : 1) < g_vis)
                        g_vis = gt[k] + ((gop[k] == OP_REQ) ? 2 : 1);
                end
                if (gvf[k]) begin
                    if (g_vis < 0
                        || gt[k] + ((gop[k] == OP_FILL) ? 1 : 8) < g_vis)
                        g_vis = gt[k] + ((gop[k] == OP_FILL) ? 1 : 8);
                end
            end
            gH = gH + LATENCY + 2;
            if ((g_vis >= 0) !== g_stk_end)
                fail_v("G-STKCONSIST", g_idx, 0, {63'd0, g_stk_end},
                       {63'd0, (g_vis >= 0)});
        end
    endtask

    task run_golden;
        integer c, i, k, e0, s, b, j;
        reg exp1, expd, expdv, expr, expq, expsp, vfd;
        reg [7:0] ob;
        begin
            parse_golden;
            fam_cnt[g_fam] = fam_cnt[g_fam] + 1;
            e0 = errors;
            wv_on = 0; wv_t = 0; wv_p = 0;
            twin_v[0] = 0; twin_v[1] = 0; twin_v[2] = 0; twin_v[3] = 0;
            twin[0] = 0; twin[1] = 0; twin[2] = 0; twin[3] = 0;

            for (c = 0; c <= gH + 1; c = c + 1) begin
                @(negedge clk);
                drive_idle;
                // ---- WAVE beat 인가 (bmem 의 32 addend record) ----
                if (wv_on) begin
                    b = c - wv_t;
                    if (b <= NB - 1)
                        for (j = 0; j < TB_N; j = j + 1)
                            ops[64*j +: 64] = bmem[wv_p + TB_N*b + j];
                    else begin
                        wv_on = 0;
                        ops = {TB_N{CANON}};
                    end
                end
                else
                    ops = {TB_N{CANON}};
                // ---- 명령 인가 ----
                k = -1;
                for (i = 0; i < g_ncmd; i = i + 1)
                    if (gt[i] == c) k = i;
                if (k >= 0) begin
                    cmd_v  = 1'b1;
                    cmd_op = gop[k];
                    cmd_st = gst[k];
                    cmd_sl = f_slot(gsl[k]);
                    if (gop[k] == OP_FILL) begin
                        cmd_word  = gword[k];
                        cmd_tag_v = 1'b1;       // 시나리오 레벨: 자기 image
                        cmd_tag   = gst[k];     // (fill_owner 는 phase A 몫)
                    end
                    if (gop[k] == OP_WAVE) begin
                        wv_on = 1; wv_t = c; wv_p = gprod[k];
                        for (j = 0; j < TB_N; j = j + 1)
                            ops[64*j +: 64] = bmem[wv_p + j];
                    end
                end
                #1;
                // ---- lattice start (수용 WAVE 만; 거부 = start 없음) ----
                exp1 = (k >= 0) && (gop[k] == OP_WAVE) && !gref[k];
                if (lat_start !== exp1)
                    fail_v("G-START", g_idx, c, {63'd0, lat_start},
                           {63'd0, exp1});
                // ---- discriminator: owner-거부 WAVE 분류 ----
                if (k >= 0 && gop[k] == OP_WAVE && gref[k]) begin
                    if (!(twin_v[gsl[k]]
                          && (c - twin[gsl[k]] < LATENCY)))
                        disc_hit(g_idx, c);
                end
                if (exp1) begin
                    twin_v[gsl[k]] = 1;
                    twin[gsl[k]] = c;
                end
                // ---- sticky 궤적 (기대 최초 가시 cycle 전 0 / 후 1) ----
                if (bank_fault !== ((g_vis >= 0) && (c >= g_vis)))
                    fail_v("G-STICKY", g_idx, c, {63'd0, bank_fault},
                           {63'd0, ((g_vis >= 0) && (c >= g_vis))});
                // ---- lattice done/fault 궤적 ----
                expd = 1'b0; vfd = 1'b0;
                for (i = 0; i < g_ncmd; i = i + 1)
                    if (gop[i] == OP_WAVE && !gref[i]
                        && gt[i] == c - LATENCY) begin
                        expd = 1'b1;
                        vfd = gvf[i];
                    end
                if (l_done !== expd)
                    fail_v("G-DONE", g_idx, c, {63'd0, l_done},
                           {63'd0, expd});
                if (expd && (l_fault !== vfd))
                    fail_v("G-LFAULT", g_idx, c, {63'd0, l_fault},
                           {63'd0, vfd});
                // ---- resp @ t+1 (비-REQ 정의 op; UNK 는 응답 무발행 —
                //      아래 !expr 가지가 resp_v==0 을 판정) ----
                expr = 1'b0;
                for (i = 0; i < g_ncmd; i = i + 1)
                    if (gt[i] == c - 1 && gop[i] != OP_REQ
                        && gop[i] <= OP_SPILL) begin
                        expr = 1'b1;
                        if (resp_v !== 1'b1 || resp_ref !== gref[i]
                            || resp_vf !==
                               ((gop[i] == OP_FILL) ? gvf[i] : 1'b0))
                            fail_v("G-RESP", g_idx, c,
                                   {61'd0, resp_v, resp_ref, resp_vf},
                                   {61'd0, 1'b1, gref[i],
                                    ((gop[i] == OP_FILL) ? gvf[i] : 1'b0)});
                    end
                if (!expr && resp_v !== 1'b0)
                    fail_v("G-RESP0", g_idx, c, {63'd0, resp_v}, 64'd0);
                // ---- acq @ t+2 (REQ) ----
                expq = 1'b0;
                for (i = 0; i < g_ncmd; i = i + 1)
                    if (gt[i] == c - 2 && gop[i] == OP_REQ) begin
                        expq = 1'b1;
                        if (acq_v !== 1'b1 || acq_rej !== gref[i])
                            fail_v("G-ACQ", g_idx, c,
                                   {62'd0, acq_v, acq_rej},
                                   {62'd0, 1'b1, gref[i]});
                    end
                if (!expq && acq_v !== 1'b0)
                    fail_v("G-ACQ0", g_idx, c, {63'd0, acq_v}, 64'd0);
                // ---- drain @ t+1 ----
                expdv = 1'b0;
                for (i = 0; i < g_ncmd; i = i + 1)
                    if (gt[i] == c - 1 && gop[i] == OP_DRAIN
                        && !gref[i]) begin
                        expdv = 1'b1;
                        if (drain_v !== 1'b1
                            || drain_w32 !== gdrain[i][31:0])
                            fail_v("G-DRAIN", g_idx, c, {32'd0, drain_w32},
                                   {32'd0, gdrain[i][31:0]});
                    end
                if (!expdv && drain_v !== 1'b0)
                    fail_v("G-DRAIN0", g_idx, c, {63'd0, drain_v}, 64'd0);
                // ---- spill @ t+1 (수용 SPILL 만; 거부 = 무발행) ----
                expsp = 1'b0;
                for (i = 0; i < g_ncmd; i = i + 1)
                    if (gt[i] == c - 1 && gop[i] == OP_SPILL
                        && !gref[i]) begin
                        expsp = 1'b1;
                        if (spill_v !== 1'b1 || spill_w !== gspill[i])
                            fail_v("G-SPILLQ", g_idx, c, spill_w,
                                   gspill[i]);
                    end
                if (!expsp && spill_v !== 1'b0)
                    fail_v("G-SPILL0", g_idx, c, {63'd0, spill_v}, 64'd0);
                // ---- FILL 스냅샷 (cycle t 말 == 관측 t+1) ----
                for (i = 0; i < g_ncmd; i = i + 1)
                    if (gt[i] == c - 1 && gop[i] == OP_FILL) begin
                        dbg_sl = f_slot(gsl[i]);
                        #0.2;
                        if (dbg_word !== gexpw[i])
                            fail_v("G-FILLSNAP", g_idx, c, dbg_word,
                                   gexpw[i]);
                    end
                // ---- SPILL/UNK 스냅샷 (cycle t 말 == 관측 t+1) —
                //      거부 = word 불변 / 수용 SPILL = release 후 잔존 ----
                for (i = 0; i < g_ncmd; i = i + 1)
                    if (gt[i] == c - 1 && gop[i] == OP_SPILL) begin
                        dbg_sl = f_slot(gsl[i]);
                        #0.2;
                        if (dbg_word !== gexpw[i])
                            fail_v("G-SPILLSNAP", g_idx, c, dbg_word,
                                   gexpw[i]);
                    end
                for (i = 0; i < g_ncmd; i = i + 1)
                    if (gt[i] == c - 1 && gop[i] > OP_SPILL) begin
                        dbg_sl = f_slot(gsl[i]);
                        #0.2;
                        if (dbg_word !== gexpw[i])
                            fail_v("G-UNKSNAP", g_idx, c, dbg_word,
                                   gexpw[i]);
                    end
                // ---- WAVE 스냅샷 (cycle t+7 말 == 관측 t+8) ----
                for (i = 0; i < g_ncmd; i = i + 1)
                    if (gt[i] == c - 8 && gop[i] == OP_WAVE) begin
                        dbg_sl = f_slot(gsl[i]);
                        #0.2;
                        if (dbg_word !== gexpw[i])
                            fail_v("G-WAVESNAP", g_idx, c, dbg_word,
                                   gexpw[i]);
                    end
                // ---- 시나리오 말 판정 (horizon 말 상태 — 계약 §6) ----
                if (c == gH + 1) begin
                    if (bank_fault !== g_stk_end)
                        fail_v("G-ENDSTICKY", g_idx, c, {63'd0, bank_fault},
                               {63'd0, g_stk_end});
                    for (s = 0; s < 4; s = s + 1) begin
                        dbg_sl = f_slot(s[1:0]);
                        #0.2;
                        ob = g_omap >> (8 * (3 - s));
                        if (dbg_word !== g_fw[s])
                            fail_v("G-ENDWORD", g_idx, c, dbg_word,
                                   g_fw[s]);
                        if (ob == 8'hFF) begin
                            if (dbg_ov !== 1'b0)
                                fail_v("G-ENDOWNER", g_idx, c,
                                       {63'd0, dbg_ov}, 64'd0);
                        end
                        else begin
                            if (dbg_ov !== 1'b1 || dbg_own !== ob[3:0])
                                fail_v("G-ENDOWNER", g_idx, c,
                                       {59'd0, dbg_ov, dbg_own},
                                       {59'd0, 1'b1, ob[3:0]});
                        end
                    end
                end
            end
            if (errors == e0) begin
                if (g_fam == 18) rand_pass = rand_pass + 1;
                else             gdir_pass = gdir_pass + 1;
            end
            else
                $display("== golden 시나리오 %0d (family %0d) FAIL ==",
                         g_idx, g_fam);
            if (g_fam == 18) rand_total = rand_total + 1;
            else             gdir_total = gdir_total + 1;
            scen_reset;
        end
    endtask

    // =========================================================================
    // PHASE P2 — pin 2 강화형 fault (c) 직접 판정 (헤더 PHASE P2 참조)
    // =========================================================================
    // 판별 벡터: 1-bit un-normalized raw (s=0, e=0, sig=2^46) — 약형 (c)
    // (leading zero > 1) 는 통과시키고 강화형 (sig[47]==0) 만 잡는다.
    localparam [63:0] UNNORM_RAW = 64'h0000_4000_0000_0000;
    // 대조 wave 기대값: 2^46 * 2^(0-47) = 0.5 -> wide (0, -1, 2^47)
    localparam [63:0] WIDE_HALF  = 64'h07FF_8000_0000_0000;

    integer p2_ok;

    task run_p2;
        integer b, w, e0;
        begin
            e0 = errors;
            // ---- wave 1: carry lane 강화형 — fault_q==1 필수 ----
            @(negedge clk);
            for (b = 0; b < NB; b = b + 1) begin
                p2_start = (b == 0);
                p2_carry = (b == 0) ? UNNORM_RAW : 64'hFFFF_FFFF_FFFF_FFFF;
                p2_ops   = {TB_N{CANON}};
                @(negedge clk);
            end
            p2_start = 1'b0;
            p2_carry = 64'hFFFF_FFFF_FFFF_FFFF;
            w = 0;
            while (!p2_done && w < LATENCY + 4) begin
                @(negedge clk);
                w = w + 1;
            end
            if (!p2_done)
                fail_v("P2-NODONE", 0, w, 64'd0, 64'd1);
            else if (p2_fault !== 1'b1)
                fail_v("P2-CARRY-STRONG", 0, w, {63'd0, p2_fault}, 64'd1);
            // ---- wave 2 (대조): 같은 필드를 곱 lane 0 에 — fault 0 +
            //      wide bit-exact (곱 lane 약형 불변 증명) ----
            @(negedge clk);
            for (b = 0; b < NB; b = b + 1) begin
                p2_start = (b == 0);
                p2_carry = (b == 0) ? CANON : 64'hFFFF_FFFF_FFFF_FFFF;
                p2_ops   = {TB_N{CANON}};
                if (b == 0)
                    p2_ops[63:0] = UNNORM_RAW;      // addend 0 (곱 lane)
                @(negedge clk);
            end
            p2_start = 1'b0;
            p2_carry = 64'hFFFF_FFFF_FFFF_FFFF;
            p2_ops   = {TB_N{CANON}};
            w = 0;
            while (!p2_done && w < LATENCY + 4) begin
                @(negedge clk);
                w = w + 1;
            end
            if (!p2_done)
                fail_v("P2-NODONE2", 0, w, 64'd0, 64'd1);
            else begin
                if (p2_fault !== 1'b0)
                    fail_v("P2-PRODLANE-RAW", 0, w, {63'd0, p2_fault},
                           64'd0);
                if (p2_wide !== WIDE_HALF)
                    fail_v("P2-PRODLANE-WIDE", 0, w, p2_wide, WIDE_HALF);
            end
            @(negedge clk);
            p2_ok = (errors == e0);
        end
    endtask

    // =========================================================================
    // main
    // =========================================================================
    integer did, scen, i0;
    reg gap_ok, spillfam_ok, xprod_ok;

    initial begin
        $readmemh("include/generated/bank_scenarios.hex", bmem);
        errors = 0; disc_hits = 0; disc_shown = 1'b0;
        tlc_pass = 0; gdir_pass = 0; rand_pass = 0;
        gdir_total = 0; rand_total = 0;
        for (i0 = 0; i0 <= 22; i0 = i0 + 1) fam_cnt[i0] = 0;
        drive_idle;
        ops = {TB_N{CANON}};
        dbg_sl = 6'd0;
        p2_start = 1'b0;
        p2_ops = {TB_N{CANON}};
        p2_carry = 64'hFFFF_FFFF_FFFF_FFFF;
        p2_ok = 0;
        srst = 1'b1;
        repeat (3) @(negedge clk);
        srst = 1'b0;
        @(negedge clk);

        // ---- PHASE P2: pin 2 강화형 fault (c) 봉인 ----
        run_p2;

        // ---- PHASE A: TLC 유도 directed 14 ----
        for (did = 1; did <= N_SCEN_TLC; did = did + 1)
            run_directed(did);

        // ---- PHASE B: golden 시나리오 349 (④ 교차곱 append 포함) ----
        bp = 0;
        for (scen = 0; scen < N_SCEN_GOLD; scen = scen + 1)
            run_golden;
        if (bp !== N_REC_GOLD) begin
            errors = errors + 1;
            $display("FAIL: record 총수 %0d != %0d (hex/계약 불일치)",
                     bp, N_REC_GOLD);
        end

        // ---- gap-후 재시작 커버리지 (§27.6 (b)(2) 폐쇄의 non-vacuity) ----
        gap_ok = (fam_cnt[3] == 3) && (fam_cnt[4] == 3);
        if (!gap_ok) begin
            errors = errors + 1;
            $display("FAIL: gap 재시작 family 소실 (same=%0d cross=%0d)",
                     fam_cnt[3], fam_cnt[4]);
        end

        // ---- SPILL/UNK guard family (적대 재실측 폐쇄의 non-vacuity —
        //      이 family 들이 소실되면 spill_ref/cmd_unk 절단 변이가 다시
        //      escape 한다). spill_window 는 ④ 교차곱 append 후 7 (offset
        //      1..7 전수 — 계약 §10 (ii)) ----
        spillfam_ok = (fam_cnt[19] == 7) && (fam_cnt[20] == 2)
                   && (fam_cnt[21] == 1) && (fam_cnt[22] == 2);
        if (!spillfam_ok) begin
            errors = errors + 1;
            $display("FAIL: SPILL/UNK guard family 소실 (win=%0d own=%0d acc=%0d unk=%0d)",
                     fam_cnt[19], fam_cnt[20], fam_cnt[21], fam_cnt[22]);
        end

        // ---- ④ 교차곱 append non-vacuity (계약 §10 (ii): window_fill
        //      offset 6 / window_zero offset 4 append 후 family 계수 5/5 —
        //      seed 이동·append 소실로 교차곱 전수가 조용히 좁아지는 것을
        //      TB 레벨에서도 잡는다 (생성기 assert 의 재생 측 반쪽) ----
        xprod_ok = (fam_cnt[6] == 5) && (fam_cnt[7] == 5);
        if (!xprod_ok) begin
            errors = errors + 1;
            $display("FAIL: 교차곱 append family 소실 (zero=%0d fill=%0d, 기대 5/5)",
                     fam_cnt[6], fam_cnt[7]);
        end

        // ---- 최종 판정 ----
        $display("");
        $display("config: N=%0d II=%0d LATENCY=%0d", TB_N, NB, LATENCY);
        $display("pin2 강화형 (c): %0s", p2_ok ? "PASS" : "FAIL");
        $display("TLC directed   : %0d/%0d", tlc_pass, N_SCEN_TLC);
        $display("golden directed: %0d/%0d", gdir_pass, gdir_total);
        $display("golden random  : %0d/%0d", rand_pass, rand_total);
        $display("gap 재시작 family: same-slot %0d / cross-slot %0d (기대 3/3)",
                 fam_cnt[3], fam_cnt[4]);
        $display("SPILL/UNK guard family: window %0d / owner %0d / accept %0d / unk %0d (기대 7/2/1/2)",
                 fam_cnt[19], fam_cnt[20], fam_cnt[21], fam_cnt[22]);
        $display("교차곱 append family: zero %0d / fill %0d (기대 5/5)",
                 fam_cnt[6], fam_cnt[7]);
        $display("disc_hits (ownership-절단 오답 모델 적발): %0d", disc_hits);
        if (errors == 0 && disc_hits > 0 && p2_ok != 0
            && tlc_pass == N_SCEN_TLC
            && gdir_pass == gdir_total && rand_pass == rand_total
            && gdir_total + rand_total == N_SCEN_GOLD) begin
            $display("TB_RESULT PASS pin2=PASS tlc=%0d/%0d dir=%0d/%0d rand=%0d/%0d disc_selftest=PASS",
                     tlc_pass, N_SCEN_TLC, gdir_pass, gdir_total,
                     rand_pass, rand_total);
            $finish;
        end
        else begin
            if (disc_hits == 0)
                $display("TB_RESULT FAIL disc_selftest=FAIL (오답 모델이 한 번도 갈라지지 않음 — 판정기 tautology 의심)");
            $display("TB_RESULT FAIL errors=%0d", errors);
            $fatal(1);
        end
    end

endmodule
