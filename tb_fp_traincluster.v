// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

// =============================================================================
// tb_fp_traincluster.v — FP_TrainCluster (④ GATE V20-3 통합체) 전 경로 TB
// (spec §27.6 "④ GATE V20-3 기준 선공표" 블록의 검증 의무 1(i)/(iii) + 2 + 3
//  의 실행체. golden: scripts/golden_lattice.py 산출
//  include/generated/cluster_wave_vectors.hex (1234 wave, 964 hex/line) —
//  레이아웃/판정 계약: include/generated/cluster_vec_contract.md.)
//
// PHASE E — cluster 벡터 전량 (1234 wave, ④ 검증 의무 2 "전 경로"):
//   operand 인가 (ld surface) -> lane 곱 전단 tap (widen/DAZ/f16-subnormal
//   정책 포함) -> 8-operand x 4-beat dispatch -> lattice -> bank RTO-48
//   store -> drain RNE-24 반출까지, 다음 층 전부 bit-exact 판정:
//     * tap 층   : beat b 의 lane j raw 곱 == EXP_ADDEND[8b+j] (계약 §7 —
//                  변이 (b) lane 전치 / (c) beat mux off-by-one 은 exact 합
//                  이 순서-무관이라 이 층에서만 갈라진다; 관측은 DUT 내부
//                  lat_ops 의 계층 참조 — 별도 미러 tap 인스턴스 없음
//                  (tautology 방지: 참조값은 전부 golden hex))
//     * resolve  : u_dut.u_lattice.resolved_q == EXP_RESOLVED (계층 참조 —
//                  cluster top 은 resolved_q 를 미노출하나 판정 4층 완전성
//                  을 위해 lattice 인스턴스 port 를 직접 관측)
//     * 추출     : lat_wide_o == EXP_WIDE
//     * bank     : dbg word (writeback 후) == EXP_BANK
//     * drain    : lat_fp32_o (즉시-drain 지점) == EXP_FP32, 그리고 비-체인
//                  라인은 bank DRAIN 반출 == EXP_FP32 (경로 2곳 모두)
//   전 구간 fault_o == 0 / clu_reject_q == 0 / done 궤적 cycle-정밀 (매
//   cycle 양방향). carry 는 언제나 bank 가 공급 (IF-1) — 비-체인 라인은
//   ADDEND[32] 의 fp64 재인코딩을 FILL 로 주입하고, c_chain_* 라인
//   (META[1]) 은 FILL 없이 직전 wave 의 bank writeback 을 그대로 소비한다
//   (gap-후 같은 slot 재시작의 대량 재판정 — 체인 총 248 라인 non-vacuity
//   assert). META[1] 라인은 ADDEND[32] == 직전 라인 EXP_WIDE 를 TB 가
//   사전 검사한다 (golden 자체 불일치는 $fatal).
//
// PHASE D — II/체이닝 directed (④ 검증 의무 2 "통합 문맥 재판정"; 기대값은
//   손계산 고정점 — tb_fp_accbank PHASE A payload binding 관례):
//   1.0 단일 곱 payload 로 (i) 타 slot II=4 완전 중첩 (bank-start 간격
//   정확히 4, done 간격 4, 양쪽 bit-exact), (ii) 같은 slot 체이닝 delta
//   정확히 7 (writeback-cycle forward carry: 1.0 -> 2.0 -> 3.0), (iii)
//   delta 6 위반 = bank WAVE_WINDOW 거부 + sticky (거부 wave 는 done 없음),
//   (iv) in-flight wave 중 타 slot DRAIN 인터리브 합법.
//
// PHASE O — ** 창 offset 0 same-cycle 중재 (③ 이월 커버리지 경계 (i) 의
//   폐쇄 — bank_scenarios_contract.md §2/§10 이 "시나리오 형식상 표현 불가,
//   ④ 통합 TB 직접 구동 몫" 으로 이월한 그 경계) **: 외부 cmd 를 내부
//   WAVE issue cycle (wave_v+2) 에 정확히 겹쳐 인가한다.
//     O1..O4: 같은 slot DRAIN/ZERO/FILL/SPILL -> ARB_OFFSET0 sticky (거부,
//             상태 불변, wave 무지연 — done cycle/값 bit-exact 재확인)
//     O5: 타 slot DRAIN -> ARB_PORT (원인 귀속 분리)
//     O6: REQ -> ARB_PORT (bank 미도달 — acq_v 무발행)
//   전부 cycle-정밀: sticky 발화 cycle 전 0 / 후 mask (양방향), reject
//   pulse 는 충돌 다음 cycle 정확히 1회, bank sticky 는 전 구간 0 (거부
//   cmd 의 bank 미도달 증명).
//
// PHASE X — cmd surface 나머지 guard: 외부 raw OP_WAVE 차단 (CMD_WAVE),
//   II<4 wave 거부 (WAVE_BUSY — in-flight wave 는 무손상), 스트리밍 중
//   operand load 거부 (LD_CONFLICT — 후속 wave 로 store 불변 증명),
//   미정의 opcode 6 pass-through (bank PROTO_GUARD — cluster sticky 0).
//
// PHASE W — 창 offset >= 1 위반의 통합 재판정: in-flight wave 창 offset 2
//   의 ZERO 가 cluster 중재를 통과해 bank ZERO_WINDOW 로 거부됨 — offset 0
//   (cluster ARB_OFFSET0) 과 offset 1..7 (bank window guard) 의 경계 분담
//   을 통합 문맥에서 확인.
//
// PHASE S — special operand pin: 소비창 내 NaN(bf16)/Inf(f16) operand ->
//   기여 canonical zero + LANE_SPECIAL sticky + 그 wave writeback 억제
//   (bank CARRY_VFAULT 동반, LAT_FAULT 는 비발화 — 원인 귀속 분리).
//
// PHASE L — carry-lane fault (d) 통합 재판정: FILL-valid 2^300 -> carry
//   소비 (beat 0) fault -> done cycle LAT_FAULT sticky 화 + writeback 억제
//   + 잔존 word drain == +Inf (bank carry_fault_range family 의 통합 형).
//
// PHASE G — TLC ghost 2건 처분의 구현 검증 (④ 검증 의무 1(iii) — golden
//   반쪽 명세 bank_scenarios_contract.md §10 항 3 그대로):
//   G1 (DT-04 (h) K 완결 캐리어 — 계약 재배정 "hw 강제 불가"): K=2 계획
//      중 1 wave 만 issue 하고 drain — hw 는 fault 를 내지 않아야 한다
//      (fault_o==0 전 구간; issued==K 보장은 TB 스케줄 몫 — scoreboard
//      ghost 대조는 TB 가 수행하고 RTL 이 잡는다고 주장하지 않는다).
//   G2 (DT-05 (l) spill image owner-tag 캐리어 — 계약 재배정, fill_owner
//      SDK 강등): (a) TB scoreboard 가 spill image 출처를 추적한 상태에서
//      외래 stream 이 tag 없이 (tag_v=0 — SDK 가 캐리어를 공급하지 않은
//      형) FILL -> hw 는 수용하고 fault 없음 — scoreboard 만 출처 불일치
//      를 안다 (hw 미검사 사실 자체가 §10 판정); (b) 대조: 같은 FILL 에
//      tag 캐리어를 공급하면 (tag_v=1) bank hw 비교 (FILL_FOREIGN) 가
//      거부한다 — 캐리어 공급 시 hw 대조가 실재함의 재확인 (③ DT-05 형).
//   ghost 2건은 hw-실재 guard 가 아니므로 변이 반증 대상에서 제외한다
//   (§10 항 3 (b) — 변이 반증은 hw-실재 guard 한정).
//
// DISCRIMINATOR 자기시험 (tautology 방지 — ③ PHASE C 형식): "중재 절단
//   오답 모델" — 외부 cmd 를 issue cycle 에도 bank 로 전달하고 bank
//   guard 만으로 판정하는 RTL 변이의 행위 모델. offset 0 에서는 창 카운터
//   가 아직 미장전 (wq 는 start posedge 에 장전) 이라 bank window guard
//   가 통과시키므로, 오답 모델은 O1..O6 전부를 "수용" 으로 예측한다 —
//   golden 기대 (거부) 와의 divergence 를 판정 경로에서 계수 (disc_hits).
//   0회면 판정기 tautology 로 TB 전체 FAIL. (offset-0 중재가 bank guard
//   로 환원 불가함 — 신설 사유 — 의 상시 증명이기도 하다.)
//
// 변이 반증 (④ 검증 의무 3 — TB 밖 일회성 실측, 결과는 gate 기록 전사):
//   (a) tap 곱 significand 하위 절단 (b) lane->lattice 전치 (c) beat mux
//   off-by-one (d) carry 비-beat0 수용 (e) DRAIN 경로 silent 절단 — 전부
//   hw-실재 guard/datapath 변이. (b)/(c) 는 exact 합이 순서-무관이라 합
//   층은 불변 — tap 층 판정 (PHASE E) 만이 사멸시킨다 (판별력의 근거).
//
// 판정: 모든 비교 bit-exact, 표본률 논증 금지 (계약 §7). 실행 (repo root;
// -Iinclude 는 FP_TrainCluster.v 의 `include "attributes.vh" 때문):
//   $ verilator --binary --timing -j 0 -Wno-TIMESCALEMOD -Iinclude \
//       FP_TrainCluster.v FP_AccLattice.v FP_AccBank.v tb_fp_traincluster.v \
//       --top-module tb_fp_traincluster -o tb_traincluster \
//       --Mdir /tmp/wt_traincluster_obj
//   $ /tmp/wt_traincluster_obj/tb_traincluster
//   iverilog: iverilog -g2012 -Iinclude -o /tmp/tb_traincluster.vvp \
//       FP_TrainCluster.v FP_AccLattice.v FP_AccBank.v tb_fp_traincluster.v \
//       && vvp /tmp/tb_traincluster.vvp
// TB 행위 모델은 dynamic part-select / 계층 참조를 쓴다 — RTL 은 clean,
// TB 는 면책 (tb_fp_acclattice.v 헤더의 일탈 기록과 동형). srst 는 operand
// store 를 지우지 않으므로 (dispatch 스테이징 — RTL 헤더 계약) phase 간
// operand 잔존은 각 phase 가 명시 재적재로 관리한다.
// =============================================================================

`timescale 1ns / 1ps

/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off WIDTHEXPAND */
// (TB 행위 모델의 integer/비트폭 혼용 — RTL 이 아님; RTL 3종은 -Wall clean.)

module tb_fp_traincluster;

    localparam integer N_VEC   = 1234;   // cluster_wave_vectors.hex 라인 수
    localparam integer N_CHAIN = 248;    // 체인 라인 수 (c_chain_* — 계약 §6:
                                         // (32-1)x4 + (32-1)x2 + (32-1)x2)
    localparam integer N_DIR   = 18;     // directed 하위 시나리오 수

    localparam integer LATENCY = 7;

    // FP_AccBank / FP_TrainCluster op 인코딩 (계약 전사)
    localparam [2:0] OP_REQ = 3'd0, OP_WAVE = 3'd1, OP_FILL = 3'd2,
                     OP_DRAIN = 3'd3, OP_ZERO = 3'd4, OP_SPILL = 3'd5;

    // cluster sticky 원인 색인 (FP_TrainCluster.v 헤더 표)
    localparam integer CF_ARB_OFFSET0 = 0, CF_ARB_PORT = 1,
                       CF_WAVE_BUSY = 2, CF_CMD_WAVE = 3,
                       CF_LD_CONFLICT = 4, CF_LANE_SPECIAL = 5,
                       CF_LAT_FAULT = 6;
    // bank sticky 원인 색인 (FP_AccBank.v 헤더 표)
    localparam integer FC_WAVE_WINDOW = 1, FC_FILL_FOREIGN = 4,
                       FC_ZERO_WINDOW = 9, FC_CARRY_VFAULT = 11,
                       FC_PROTO_GUARD = 12;

    // 손계산 고정점 (directed payload — 1.0 단일 곱)
    localparam [63:0] F64_1  = 64'h3FF0_0000_0000_0000;
    localparam [63:0] F64_2  = 64'h4000_0000_0000_0000;
    localparam [63:0] F64_3  = 64'h4008_0000_0000_0000;
    localparam [63:0] W300   = 64'h52B0_0000_0000_0000;  // 2^300 (FILL-valid)
    localparam [63:0] WIDE_1 = 64'h0000_8000_0000_0000;  // 1.0 (normalized)
    localparam [63:0] WIDE_2 = 64'h0001_8000_0000_0000;  // 2.0
    localparam [63:0] WIDE_3 = 64'h0001_C000_0000_0000;  // 3.0
    localparam [31:0] F32_1  = 32'h3F80_0000;
    localparam [31:0] F32_2  = 32'h4000_0000;
    localparam [31:0] F32_3  = 32'h4040_0000;

    // stream / slot 배정 (slot 은 bank bit [5] 양쪽을 실사용)
    localparam [3:0] ST   = 4'd5;
    localparam [3:0] ST_B = 4'd7;
    localparam [5:0] SL_A = 6'h15;
    localparam [5:0] SL_B = 6'h2A;
    localparam [5:0] SL_C = 6'h33;
    localparam [5:0] SL_E = 6'h1A;       // PHASE E 전용

    // ---- 벡터 메모리 (계약 §1: 1 line = 3856 bit) ----
    reg [3855:0] cvec [0:N_VEC-1];

    // ---- clock ----
    reg clk = 1'b0;
    always #5 clk = ~clk;

    // ---- DUT 결선 ----
    reg         srst;
    reg         ld_v;
    reg  [4:0]  ld_idx;
    reg  [15:0] ld_a, ld_b;
    reg         wave_v, wave_bf16;
    reg  [3:0]  wave_st;
    reg  [5:0]  wave_sl;
    reg         cmd_v;
    reg  [2:0]  cmd_op;
    reg  [3:0]  cmd_st;
    reg  [5:0]  cmd_sl;
    reg  [63:0] cmd_word;
    reg         cmd_tag_v;
    reg  [3:0]  cmd_tag;
    reg  [5:0]  dbg_sl;

    wire        resp_v, resp_ref, resp_vf, acq_v, acq_rej;
    wire        drain_v, spill_v, clu_rej, lat_done, fault_w;
    wire [31:0] drain_w32, lat_fp32;
    wire [63:0] spill_w, dbg_word, lat_wide;
    wire [6:0]  clu_causes;
    wire [13:0] bank_causes;
    wire        dbg_ov;
    wire [3:0]  dbg_own;

    FP_TrainCluster u_dut (
        .clk               (clk),
        .srst_i            (srst),
        .ld_v_i            (ld_v),
        .ld_idx_i          (ld_idx),
        .ld_a_i            (ld_a),
        .ld_b_i            (ld_b),
        .wave_v_i          (wave_v),
        .wave_dtype_bf16_i (wave_bf16),
        .wave_stream_i     (wave_st),
        .wave_slot_i       (wave_sl),
        .cmd_v_i           (cmd_v),
        .cmd_op_i          (cmd_op),
        .cmd_stream_i      (cmd_st),
        .cmd_slot_i        (cmd_sl),
        .cmd_word_i        (cmd_word),
        .cmd_tag_v_i       (cmd_tag_v),
        .cmd_tag_i         (cmd_tag),
        .resp_v_o          (resp_v),
        .resp_refused_o    (resp_ref),
        .resp_vfault_o     (resp_vf),
        .acq_v_o           (acq_v),
        .acq_reject_o      (acq_rej),
        .drain_v_o         (drain_v),
        .drain_o           (drain_w32),
        .spill_v_o         (spill_v),
        .spill_o           (spill_w),
        .clu_reject_q      (clu_rej),
        .lat_done_o        (lat_done),
        .lat_wide_o        (lat_wide),
        .lat_fp32_o        (lat_fp32),
        .clu_fault_causes_o(clu_causes),
        .bank_fault_causes_o(bank_causes),
        .fault_o           (fault_w),
        .dbg_slot_i        (dbg_sl),
        .dbg_word_o        (dbg_word),
        .dbg_owner_v_o     (dbg_ov),
        .dbg_owner_o       (dbg_own)
    );

    // ---- wide field -> fp64 재인코딩 (bank FILL 주입용 — FP_AccBank 변환
    //      기의 역함수; 벡터 carry 는 lattice-표현 범위라 fp64 normal 만
    //      발생, subnormal corner 도달 시 golden 위반으로 $fatal) ----
    function [63:0] wide2f64;
        input [63:0] wf;
        reg               s;
        reg signed [11:0] e;
        reg [47:0]        sig;
        reg [11:0]        eb;
        begin
            s   = wf[59];
            e   = {wf[58], wf[58:48]};
            sig = wf[47:0];
            if (sig == 48'd0)
                wide2f64 = 64'd0;                    // canonical zero -> +0
            else begin
                if (!sig[47]) begin
                    $display("FATAL: carry 비-normalized (golden 위반) %h", wf);
                    $fatal(1);
                end
                eb = e + 12'sd1023;
                if (eb == 12'd0 || eb >= 12'd2047 || eb[11]) begin
                    $display("FATAL: carry fp64 normal 범위 밖 %h", wf);
                    $fatal(1);
                end
                wide2f64 = {s, eb[10:0], sig[46:0], 5'b0};
            end
        end
    endfunction

    // =========================================================================
    // 오류 계정 + discriminator
    // =========================================================================
    integer errors;
    integer disc_hits;
    reg     disc_shown;
    integer e2e_pass, dir_pass, n_chain_run;

    task fail_v;
        input [175:0] tag;              // 층 이름 (ASCII)
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

    // 중재 절단 오답 모델의 divergence 계수 (헤더 DISCRIMINATOR 항):
    // offset 0 에서 bank 창 카운터는 미장전 (wq 장전은 start posedge) —
    // "issue cycle 에도 전달" 변이의 bank-guard-only 예측은 '수용' 이고
    // golden 기대는 '거부' 다. TB 창 모델 (armed_from = issue+1) 로 예측을
    // 실계산해 divergence 를 계수한다.
    task disc_hit;
        input integer scen;
        input integer c;
        begin
            disc_hits = disc_hits + 1;
            if (!disc_shown) begin
                disc_shown = 1'b1;
                $display("[DISC-EXPECTED-FAIL] scen %0d cyc %0d:", scen, c);
                $display("  중재 절단 오답 모델 (외부 cmd 를 issue cycle 에도");
                $display("  bank 전달, bank guard 만 판정) 은 offset 0 에서 창");
                $display("  카운터 미장전으로 이 cmd 를 수용했을 것 — golden");
                $display("  기대는 거부다. 오답 모델이 판정 경로에서 실제 FAIL");
                $display("  을 유발함의 시연 (비-tautology 증명).");
            end
        end
    endtask

    // =========================================================================
    // fault_o 집약 불변식 (매 cycle) — FP_TrainCluster.v:554 집약 계약의 반증
    //   assign fault_o = (|clu_sticky) | bank_fault_w;
    // 를 관측 원인 벡터 (clu_fault_causes_o) 와 bank fault 라인
    // (u_dut.bank_fault_w — 계층 관측, u_dut.u_lattice.resolved_q 관용구와
    // 동형) 으로 재구성해 === 등가 판정한다. phase 별 fault_w !== 0 검사
    // (0-기대) 와 달리 sticky 발화 구간 (X1-4/W/S/L) 에서 양성 1 을 실제로
    // 요구한다 — 'fault_o = 1'b0' 절단 변이와 bank 항 탈락 변이
    // ('fault_o = |clu_sticky') 를 사멸시키는 loud-fault-never-silent 표면.
    // 양쪽 sticky 는 power-on 0 초기화 (PROCASSINIT 계약) 라 t=0 부터 X-free
    // — negedge 마다 무조건 판정한다 (srst 구간 포함).
    // =========================================================================
    always @(negedge clk) begin
        if (fault_w !== ((|clu_causes) | u_dut.bank_fault_w))
            fail_v("FAULT-AGG", 99, $time,
                   {63'd0, fault_w},
                   {62'd0, (|clu_causes), u_dut.bank_fault_w});
    end

    // =========================================================================
    // 공용 driver
    // =========================================================================
    task drive_idle;
        begin
            ld_v = 1'b0; ld_idx = 5'd0; ld_a = 16'd0; ld_b = 16'd0;
            wave_v = 1'b0; wave_bf16 = 1'b1;
            wave_st = 4'd0; wave_sl = 6'd0;
            cmd_v = 1'b0; cmd_op = 3'd0; cmd_st = 4'd0; cmd_sl = 6'd0;
            cmd_word = 64'd0; cmd_tag_v = 1'b0; cmd_tag = 4'd0;
        end
    endtask

    task scen_reset;                    // 제어 상태 격리 (operand store 잔존)
        begin
            drive_idle;
            srst = 1'b1;
            @(negedge clk);
            srst = 1'b0;
            @(negedge clk);
        end
    endtask

    task do_fill;                       // (drive 국면 전용 조립기)
        input [3:0]  st;
        input [5:0]  sl;
        input [63:0] w;
        input        tv;
        input [3:0]  tg;
        begin
            cmd_v = 1'b1; cmd_op = OP_FILL; cmd_st = st; cmd_sl = sl;
            cmd_word = w; cmd_tag_v = tv; cmd_tag = tg;
        end
    endtask

    task do_ld;
        input [4:0]  idx;
        input [15:0] a;
        input [15:0] b;
        begin
            ld_v = 1'b1; ld_idx = idx; ld_a = a; ld_b = b;
        end
    endtask

    task do_wave;
        input        bf16;
        input [3:0]  st;
        input [5:0]  sl;
        begin
            wave_v = 1'b1; wave_bf16 = bf16; wave_st = st; wave_sl = sl;
        end
    endtask

    // =========================================================================
    // PHASE D — II=4 / delta-7 체이닝 / delta-6 위반 / 인터리브 (헤더 참조)
    // 스케줄 (cycle): FILL A/B(+0),C(1.0) @0/1/2; ld 32쌍 @3..34 (pair0 만
    // 1.0x1.0); w1 A@36 (issue 38, done 45) / w2 B@40 (issue 42 — II=4,
    // done 49) / DRAIN C@39 (in-flight 인터리브) / w3 A@47 (issue 49, carry
    // 1.0 -> 2.0, done 56) / w4 A@54 (issue 56 = w3 writeback cycle —
    // delta 정확히 7, forward carry 2.0 -> 3.0, done 63) / w5 B@62 (issue
    // 64, 1.0 -> 2.0, done 71) / w6 B@68 (issue 70, delta 6 -> WAVE_WINDOW
    // 거부) / DRAIN A@75 (3.0) / DRAIN B@77 (2.0).
    // =========================================================================
    reg [13:0] exp_bf;
    reg [6:0]  exp_cf;
    reg        expd, expdv;
    reg [63:0] expw;
    reg [31:0] expf;

    task run_d;
        integer c, e0;
        begin
            e0 = errors;
            for (c = 0; c <= 80; c = c + 1) begin
                @(negedge clk);
                drive_idle;
                dbg_sl = SL_A;
                case (c)
                    0:  do_fill(ST, SL_A, 64'h0, 1'b1, ST);
                    1:  do_fill(ST, SL_B, 64'h0, 1'b1, ST);
                    2:  do_fill(ST, SL_C, F64_1, 1'b1, ST);
                    39: begin cmd_v = 1'b1; cmd_op = OP_DRAIN;
                              cmd_st = ST; cmd_sl = SL_C; end
                    75: begin cmd_v = 1'b1; cmd_op = OP_DRAIN;
                              cmd_st = ST; cmd_sl = SL_A; end
                    77: begin cmd_v = 1'b1; cmd_op = OP_DRAIN;
                              cmd_st = ST; cmd_sl = SL_B; end
                    default: ;
                endcase
                if (c >= 3 && c <= 34)
                    do_ld(c - 3, (c == 3) ? 16'h3F80 : 16'h0,
                                 (c == 3) ? 16'h3F80 : 16'h0);
                if (c == 36 || c == 47 || c == 54)
                    do_wave(1'b1, ST, SL_A);
                if (c == 40 || c == 62 || c == 68)
                    do_wave(1'b1, ST, SL_B);
                if (c == 41)            dbg_sl = SL_C;
                if (c == 50 || c == 72) dbg_sl = SL_B;
                #1;
                // sticky 궤적 — bank WAVE_WINDOW 만, 가시 71 부터 (양방향)
                exp_bf = (c >= 71) ? (14'd1 << FC_WAVE_WINDOW) : 14'd0;
                if (bank_causes !== exp_bf)
                    fail_v("D-BSTICKY", 0, c, {50'd0, bank_causes},
                           {50'd0, exp_bf});
                if (clu_causes !== 7'd0)
                    fail_v("D-CSTICKY", 0, c, {57'd0, clu_causes}, 64'd0);
                if (clu_rej !== 1'b0)
                    fail_v("D-REJ", 0, c, {63'd0, clu_rej}, 64'd0);
                // done 궤적 + 값 (II=4 중첩: 45/49 간격 4; delta-7: 56/63)
                expd = (c == 45) || (c == 49) || (c == 56) || (c == 63)
                     || (c == 71);
                if (lat_done !== expd)
                    fail_v("D-DONE", 0, c, {63'd0, lat_done}, {63'd0, expd});
                if (expd) begin
                    expw = (c == 45 || c == 49) ? WIDE_1
                         : (c == 63)            ? WIDE_3 : WIDE_2;
                    expf = (c == 45 || c == 49) ? F32_1
                         : (c == 63)            ? F32_3 : F32_2;
                    if (lat_wide !== expw)
                        fail_v("D-WIDE", 0, c, lat_wide, expw);
                    if (lat_fp32 !== expf)
                        fail_v("D-FP32", 0, c, {32'd0, lat_fp32},
                               {32'd0, expf});
                end
                // drain 반출
                expdv = (c == 40) || (c == 76) || (c == 78);
                if (drain_v !== expdv)
                    fail_v("D-DRAINV", 0, c, {63'd0, drain_v},
                           {63'd0, expdv});
                if (c == 40 && drain_w32 !== F32_1)
                    fail_v("D-DRAIN-C", 0, c, {32'd0, drain_w32},
                           {32'd0, F32_1});
                if (c == 76 && drain_w32 !== F32_3)
                    fail_v("D-DRAIN-A", 0, c, {32'd0, drain_w32},
                           {32'd0, F32_3});
                if (c == 78 && drain_w32 !== F32_2)
                    fail_v("D-DRAIN-B", 0, c, {32'd0, drain_w32},
                           {32'd0, F32_2});
                // bank word 궤적 (writeback 가시 cycle)
                if (c == 41 && (dbg_word !== F64_1 || dbg_ov !== 1'b0))
                    fail_v("D-CREL", 0, c, {dbg_ov, dbg_word[62:0]}, F64_1);
                if (c == 46 && dbg_word !== F64_1)
                    fail_v("D-WB1", 0, c, dbg_word, F64_1);
                if (c == 50 && dbg_word !== F64_1)
                    fail_v("D-WB2", 0, c, dbg_word, F64_1);
                if (c == 57 && dbg_word !== F64_2)
                    fail_v("D-WB3", 0, c, dbg_word, F64_2);
                if (c == 64 && dbg_word !== F64_3)
                    fail_v("D-WB4", 0, c, dbg_word, F64_3);
                if (c == 72 && dbg_word !== F64_2)
                    fail_v("D-WB5", 0, c, dbg_word, F64_2);
                // w5 수용 / w6 거부 응답
                if (c == 65 && (resp_v !== 1'b1 || resp_ref !== 1'b0))
                    fail_v("D-RESP-W5", 0, c, {62'd0, resp_v, resp_ref},
                           {62'd0, 2'b10});
                if (c == 71 && (resp_v !== 1'b1 || resp_ref !== 1'b1))
                    fail_v("D-RESP-W6", 0, c, {62'd0, resp_v, resp_ref},
                           {62'd0, 2'b11});
            end
            if (errors == e0) dir_pass = dir_pass + 1;
            else $display("== PHASE D FAIL (누적 %0d) ==", errors - e0);
            scen_reset;
        end
    endtask

    // =========================================================================
    // PHASE O — 창 offset 0 same-cycle 중재 directed (mode 1..6, 헤더 참조)
    // FILL A/B @0/1; wave A @3 (issue 5); 외부 cmd @5 (issue cycle 정확히).
    // =========================================================================
    task run_off0;
        input integer mode;
        integer c, e0;
        begin
            e0 = errors;
            for (c = 0; c <= 16; c = c + 1) begin
                @(negedge clk);
                drive_idle;
                dbg_sl = (mode == 5) ? SL_B : (mode == 6) ? SL_C : SL_A;
                case (c)
                    0: do_fill(ST, SL_A, F64_1, 1'b1, ST);
                    1: do_fill(ST, SL_B, F64_1, 1'b1, ST);
                    3: do_wave(1'b1, ST, SL_A);
                    5: begin
                        case (mode)
                            1: begin cmd_v = 1'b1; cmd_op = OP_DRAIN;
                                     cmd_st = ST; cmd_sl = SL_A; end
                            2: begin cmd_v = 1'b1; cmd_op = OP_ZERO;
                                     cmd_st = ST; cmd_sl = SL_A; end
                            3: do_fill(ST, SL_A, F64_3, 1'b1, ST);
                            4: begin cmd_v = 1'b1; cmd_op = OP_SPILL;
                                     cmd_st = ST; cmd_sl = SL_A; end
                            5: begin cmd_v = 1'b1; cmd_op = OP_DRAIN;
                                     cmd_st = ST; cmd_sl = SL_B; end
                            default: begin cmd_v = 1'b1; cmd_op = OP_REQ;
                                     cmd_st = 4'd6; cmd_sl = SL_C; end
                        endcase
                        // 오답 모델 (bank-guard-only) 창 판정: armed_from =
                        // issue+1 = 6 > 5 -> 미장전 -> '수용' 예측 — golden
                        // 기대 '거부' 와 divergence
                        disc_hit(100 + mode, c);
                    end
                    default: ;
                endcase
                #1;
                // cluster sticky: ARB_OFFSET0 (1..4) / ARB_PORT (5..6),
                // 가시 6 부터 — cycle 정밀 양방향
                exp_cf = (c >= 6) ? ((mode <= 4)
                                     ? (7'd1 << CF_ARB_OFFSET0)
                                     : (7'd1 << CF_ARB_PORT)) : 7'd0;
                if (clu_causes !== exp_cf)
                    fail_v("O-CSTICKY", mode, c, {57'd0, clu_causes},
                           {57'd0, exp_cf});
                // bank sticky 전 구간 0 — 거부 cmd 의 bank 미도달 증명
                if (bank_causes !== 14'd0)
                    fail_v("O-BSTICKY", mode, c, {50'd0, bank_causes},
                           64'd0);
                // reject pulse 정확히 충돌 다음 cycle 1회
                if (clu_rej !== ((c == 6) ? 1'b1 : 1'b0))
                    fail_v("O-REJ", mode, c, {63'd0, clu_rej},
                           {63'd0, (c == 6)});
                // wave 무지연 — done 정확히 12, 값 2.0 (carry 1.0 + 1.0)
                if (lat_done !== ((c == 12) ? 1'b1 : 1'b0))
                    fail_v("O-DONE", mode, c, {63'd0, lat_done},
                           {63'd0, (c == 12)});
                if (c == 12 && lat_wide !== WIDE_2)
                    fail_v("O-WIDE", mode, c, lat_wide, WIDE_2);
                // 거부 cmd 의 무효과 (mode 별 상태 불변)
                if (c == 6) begin
                    case (mode)
                        1: if (dbg_ov !== 1'b1 || dbg_word !== F64_1)
                               fail_v("O-DRAIN0", mode, c,
                                      {dbg_ov, dbg_word[62:0]}, F64_1);
                        2: if (dbg_word !== F64_1)
                               fail_v("O-ZERO0", mode, c, dbg_word, F64_1);
                        3: if (dbg_word !== F64_1)
                               fail_v("O-FILL0", mode, c, dbg_word, F64_1);
                        4: if (dbg_ov !== 1'b1)
                               fail_v("O-SPILL0", mode, c,
                                      {63'd0, dbg_ov}, 64'd1);
                        5: if (dbg_ov !== 1'b1 || dbg_word !== F64_1)
                               fail_v("O-DRAINB0", mode, c,
                                      {dbg_ov, dbg_word[62:0]}, F64_1);
                        default:
                           if (dbg_ov !== 1'b0)
                               fail_v("O-REQ0", mode, c,
                                      {63'd0, dbg_ov}, 64'd0);
                    endcase
                end
                // drain/spill/acq 무발행 (REQ 미도달 -> acq_v 도 전 구간 0)
                if (drain_v !== 1'b0)
                    fail_v("O-DRAINV", mode, c, {63'd0, drain_v}, 64'd0);
                if (spill_v !== 1'b0)
                    fail_v("O-SPILLV", mode, c, {63'd0, spill_v}, 64'd0);
                if (acq_v !== 1'b0)
                    fail_v("O-ACQV", mode, c, {63'd0, acq_v}, 64'd0);
                // WAVE 자체의 bank 응답 (수용) 은 6 에 그대로 — 그 외 무응답
                if (c == 6 && (resp_v !== 1'b1 || resp_ref !== 1'b0))
                    fail_v("O-RESPW", mode, c, {62'd0, resp_v, resp_ref},
                           {62'd0, 2'b10});
                if (c == 7 && resp_v !== 1'b0)
                    fail_v("O-RESP0", mode, c, {63'd0, resp_v}, 64'd0);
                // writeback 착지 (wave 결과 보존 — mode 3 의 F64_3 미기록
                // 포함: 착지값은 언제나 2.0)
                if (c == 13 && mode <= 4 && dbg_word !== F64_2)
                    fail_v("O-WB", mode, c, dbg_word, F64_2);
            end
            if (errors == e0) dir_pass = dir_pass + 1;
            else $display("== PHASE O mode %0d FAIL (누적 %0d) ==",
                          mode, errors - e0);
            scen_reset;
        end
    endtask

    // =========================================================================
    // PHASE X — cmd surface guard 4종 (헤더 참조)
    // =========================================================================
    task run_x1;                        // 외부 raw OP_WAVE 차단 (CMD_WAVE)
        integer c, e0;
        begin
            e0 = errors;
            for (c = 0; c <= 14; c = c + 1) begin
                @(negedge clk);
                drive_idle;
                dbg_sl = SL_A;
                if (c == 0) do_fill(ST, SL_A, F64_1, 1'b1, ST);
                if (c == 2) begin
                    cmd_v = 1'b1; cmd_op = OP_WAVE;
                    cmd_st = ST; cmd_sl = SL_A;
                end
                #1;
                exp_cf = (c >= 3) ? (7'd1 << CF_CMD_WAVE) : 7'd0;
                if (clu_causes !== exp_cf)
                    fail_v("X1-CSTICKY", 1, c, {57'd0, clu_causes},
                           {57'd0, exp_cf});
                if (bank_causes !== 14'd0)
                    fail_v("X1-BSTICKY", 1, c, {50'd0, bank_causes}, 64'd0);
                if (clu_rej !== ((c == 3) ? 1'b1 : 1'b0))
                    fail_v("X1-REJ", 1, c, {63'd0, clu_rej},
                           {63'd0, (c == 3)});
                if (lat_done !== 1'b0)          // wave 미발화 — 우회 차단
                    fail_v("X1-DONE", 1, c, {63'd0, lat_done}, 64'd0);
                if (resp_v !== ((c == 1) ? 1'b1 : 1'b0))
                    fail_v("X1-RESP", 1, c, {63'd0, resp_v},
                           {63'd0, (c == 1)});
            end
            if (errors == e0) dir_pass = dir_pass + 1;
            else $display("== PHASE X1 FAIL ==");
            scen_reset;
        end
    endtask

    task run_x2;                        // II<4 wave 거부 (WAVE_BUSY)
        integer c, e0;
        begin
            e0 = errors;
            for (c = 0; c <= 20; c = c + 1) begin
                @(negedge clk);
                drive_idle;
                dbg_sl = SL_B;
                if (c == 0) do_fill(ST, SL_A, F64_1, 1'b1, ST);
                if (c == 1) do_fill(ST, SL_B, F64_1, 1'b1, ST);
                if (c == 3) do_wave(1'b1, ST, SL_A);
                if (c == 5) do_wave(1'b1, ST, SL_B);   // 스트리밍 중 — 거부
                #1;
                exp_cf = (c >= 6) ? (7'd1 << CF_WAVE_BUSY) : 7'd0;
                if (clu_causes !== exp_cf)
                    fail_v("X2-CSTICKY", 2, c, {57'd0, clu_causes},
                           {57'd0, exp_cf});
                if (bank_causes !== 14'd0)
                    fail_v("X2-BSTICKY", 2, c, {50'd0, bank_causes}, 64'd0);
                if (clu_rej !== ((c == 6) ? 1'b1 : 1'b0))
                    fail_v("X2-REJ", 2, c, {63'd0, clu_rej},
                           {63'd0, (c == 6)});
                // w1 무손상 (done 12, 2.0) + 거부 wave 는 done 없음
                if (lat_done !== ((c == 12) ? 1'b1 : 1'b0))
                    fail_v("X2-DONE", 2, c, {63'd0, lat_done},
                           {63'd0, (c == 12)});
                if (c == 12 && lat_wide !== WIDE_2)
                    fail_v("X2-WIDE", 2, c, lat_wide, WIDE_2);
                if (c == 20 && (dbg_ov !== 1'b1 || dbg_word !== F64_1))
                    fail_v("X2-BWORD", 2, c, {dbg_ov, dbg_word[62:0]},
                           F64_1);
            end
            if (errors == e0) dir_pass = dir_pass + 1;
            else $display("== PHASE X2 FAIL ==");
            scen_reset;
        end
    endtask

    task run_x3;                        // 스트리밍 중 load 거부 (LD_CONFLICT)
        integer c, e0;
        begin
            e0 = errors;
            for (c = 0; c <= 29; c = c + 1) begin
                @(negedge clk);
                drive_idle;
                dbg_sl = SL_A;
                if (c == 0)  do_fill(ST, SL_A, F64_1, 1'b1, ST);
                if (c == 2)  do_wave(1'b1, ST, SL_A);
                if (c == 3)  do_ld(5'd0, 16'h4000, 16'h4000); // 거부돼야 함
                if (c == 13) do_wave(1'b1, ST, SL_A);
                if (c == 26) begin
                    cmd_v = 1'b1; cmd_op = OP_DRAIN;
                    cmd_st = ST; cmd_sl = SL_A;
                end
                #1;
                exp_cf = (c >= 4) ? (7'd1 << CF_LD_CONFLICT) : 7'd0;
                if (clu_causes !== exp_cf)
                    fail_v("X3-CSTICKY", 3, c, {57'd0, clu_causes},
                           {57'd0, exp_cf});
                if (bank_causes !== 14'd0)
                    fail_v("X3-BSTICKY", 3, c, {50'd0, bank_causes}, 64'd0);
                if (clu_rej !== ((c == 4) ? 1'b1 : 1'b0))
                    fail_v("X3-REJ", 3, c, {63'd0, clu_rej},
                           {63'd0, (c == 4)});
                // w1 done 11: 2.0 (pair0 가 1.0 그대로 — 거부 증명 전반);
                // w2 done 22: 3.0 (store 불변 증명 후반 — 2.0x2.0 이
                // 실렸다면 4.0+2.0=6.0 으로 갈라진다)
                if (lat_done !== (((c == 11) || (c == 22)) ? 1'b1 : 1'b0))
                    fail_v("X3-DONE", 3, c, {63'd0, lat_done},
                           {63'd0, ((c == 11) || (c == 22))});
                if (c == 11 && lat_wide !== WIDE_2)
                    fail_v("X3-WIDE1", 3, c, lat_wide, WIDE_2);
                if (c == 22 && lat_wide !== WIDE_3)
                    fail_v("X3-WIDE2", 3, c, lat_wide, WIDE_3);
                if (drain_v !== ((c == 27) ? 1'b1 : 1'b0))
                    fail_v("X3-DRAINV", 3, c, {63'd0, drain_v},
                           {63'd0, (c == 27)});
                if (c == 27 && drain_w32 !== F32_3)
                    fail_v("X3-DRAIN", 3, c, {32'd0, drain_w32},
                           {32'd0, F32_3});
            end
            if (errors == e0) dir_pass = dir_pass + 1;
            else $display("== PHASE X3 FAIL ==");
            scen_reset;
        end
    endtask

    task run_x4;                        // 미정의 opcode 6 — bank PROTO_GUARD
        integer c, e0;
        begin
            e0 = errors;
            for (c = 0; c <= 6; c = c + 1) begin
                @(negedge clk);
                drive_idle;
                dbg_sl = SL_A;
                if (c == 0) begin
                    cmd_v = 1'b1; cmd_op = 3'd6;
                    cmd_st = ST; cmd_sl = SL_A;
                end
                #1;
                exp_bf = (c >= 1) ? (14'd1 << FC_PROTO_GUARD) : 14'd0;
                if (bank_causes !== exp_bf)
                    fail_v("X4-BSTICKY", 4, c, {50'd0, bank_causes},
                           {50'd0, exp_bf});
                if (clu_causes !== 7'd0)
                    fail_v("X4-CSTICKY", 4, c, {57'd0, clu_causes}, 64'd0);
                if (clu_rej !== 1'b0)   // cluster 는 pass-through — 거부 아님
                    fail_v("X4-REJ", 4, c, {63'd0, clu_rej}, 64'd0);
                if (resp_v !== 1'b0)    // UNK 응답 무발행 (bank 계약)
                    fail_v("X4-RESP", 4, c, {63'd0, resp_v}, 64'd0);
                if (c == 2 && dbg_ov !== 1'b0)
                    fail_v("X4-STATE", 4, c, {63'd0, dbg_ov}, 64'd0);
            end
            if (errors == e0) dir_pass = dir_pass + 1;
            else $display("== PHASE X4 FAIL ==");
            scen_reset;
        end
    endtask

    // =========================================================================
    // PHASE W — 창 offset 2 위반의 통합 재판정 (bank ZERO_WINDOW 경유)
    // =========================================================================
    task run_w;
        integer c, e0;
        begin
            e0 = errors;
            for (c = 0; c <= 14; c = c + 1) begin
                @(negedge clk);
                drive_idle;
                dbg_sl = SL_A;
                if (c == 0) do_fill(ST, SL_A, F64_1, 1'b1, ST);
                if (c == 2) do_wave(1'b1, ST, SL_A);
                if (c == 6) begin       // issue 4, 창 [4,11] — offset 2
                    cmd_v = 1'b1; cmd_op = OP_ZERO;
                    cmd_st = ST; cmd_sl = SL_A;
                end
                #1;
                exp_bf = (c >= 7) ? (14'd1 << FC_ZERO_WINDOW) : 14'd0;
                if (bank_causes !== exp_bf)
                    fail_v("W-BSTICKY", 0, c, {50'd0, bank_causes},
                           {50'd0, exp_bf});
                if (clu_causes !== 7'd0)   // offset != 0 — cluster 중재 통과
                    fail_v("W-CSTICKY", 0, c, {57'd0, clu_causes}, 64'd0);
                if (clu_rej !== 1'b0)
                    fail_v("W-REJ", 0, c, {63'd0, clu_rej}, 64'd0);
                if (c == 7 && (resp_v !== 1'b1 || resp_ref !== 1'b1))
                    fail_v("W-RESP", 0, c, {62'd0, resp_v, resp_ref},
                           {62'd0, 2'b11});
                if (lat_done !== ((c == 11) ? 1'b1 : 1'b0))
                    fail_v("W-DONE", 0, c, {63'd0, lat_done},
                           {63'd0, (c == 11)});
                if (c == 11 && lat_wide !== WIDE_2)
                    fail_v("W-WIDE", 0, c, lat_wide, WIDE_2);
                if (c == 12 && dbg_word !== F64_2)  // ZERO 미반영 + wb 정상
                    fail_v("W-WB", 0, c, dbg_word, F64_2);
            end
            if (errors == e0) dir_pass = dir_pass + 1;
            else $display("== PHASE W FAIL ==");
            scen_reset;
        end
    endtask

    // =========================================================================
    // PHASE S — special operand pin (sel 0: bf16 NaN / sel 1: f16 -Inf)
    // =========================================================================
    task run_s;
        input integer sel;
        integer c, e0;
        begin
            e0 = errors;
            for (c = 0; c <= 20; c = c + 1) begin
                @(negedge clk);
                drive_idle;
                dbg_sl = SL_A;
                if (c == 0)
                    do_ld(5'd0, sel ? 16'h3C00 : 16'h3F80,
                                 sel ? 16'h3C00 : 16'h3F80);
                if (c == 1)
                    do_ld(5'd1, sel ? 16'hFC00 : 16'h7FC0,
                                 sel ? 16'h3C00 : 16'h3F80);
                if (c == 2)  do_fill(ST, SL_A, 64'h0, 1'b1, ST);
                if (c == 4)  do_wave(sel ? 1'b0 : 1'b1, ST, SL_A);
                if (c == 16) begin
                    cmd_v = 1'b1; cmd_op = OP_DRAIN;
                    cmd_st = ST; cmd_sl = SL_A;
                end
                if (c == 18) do_ld(5'd1, 16'h0, 16'h0);   // cleanup
                #1;
                // LANE_SPECIAL 은 소비 beat0 (issue 6) 채집 -> 가시 7;
                // LAT_FAULT 는 lattice fault_q 가 0 이므로 절대 비발화
                // (원인 귀속 분리 — silent zero 대체 금지 pin 의 loud 반쪽)
                exp_cf = (c >= 7) ? (7'd1 << CF_LANE_SPECIAL) : 7'd0;
                if (clu_causes !== exp_cf)
                    fail_v("S-CSTICKY", sel, c, {57'd0, clu_causes},
                           {57'd0, exp_cf});
                // writeback 억제 동반 sticky (carry-vfault 동형) — 가시 14
                exp_bf = (c >= 14) ? (14'd1 << FC_CARRY_VFAULT) : 14'd0;
                if (bank_causes !== exp_bf)
                    fail_v("S-BSTICKY", sel, c, {50'd0, bank_causes},
                           {50'd0, exp_bf});
                if (clu_rej !== 1'b0)
                    fail_v("S-REJ", sel, c, {63'd0, clu_rej}, 64'd0);
                // done 13: 기여 zero 강제로 합 == 1.0 (X 방출 없음)
                if (lat_done !== ((c == 13) ? 1'b1 : 1'b0))
                    fail_v("S-DONE", sel, c, {63'd0, lat_done},
                           {63'd0, (c == 13)});
                if (c == 13 && lat_wide !== WIDE_1)
                    fail_v("S-WIDE", sel, c, lat_wide, WIDE_1);
                // writeback 억제 — word 는 +0 보존
                if (c == 14 && dbg_word !== 64'h0)
                    fail_v("S-SUPPRESS", sel, c, dbg_word, 64'h0);
                if (drain_v !== ((c == 17) ? 1'b1 : 1'b0))
                    fail_v("S-DRAINV", sel, c, {63'd0, drain_v},
                           {63'd0, (c == 17)});
                if (c == 17 && drain_w32 !== 32'h0000_0000)
                    fail_v("S-DRAIN", sel, c, {32'd0, drain_w32}, 64'd0);
            end
            if (errors == e0) dir_pass = dir_pass + 1;
            else $display("== PHASE S%0d FAIL ==", sel);
            scen_reset;
        end
    endtask

    // =========================================================================
    // PHASE L — carry-lane fault (d) 통합 재판정 (FILL-valid 2^300)
    // =========================================================================
    task run_l;
        integer c, e0;
        begin
            e0 = errors;
            for (c = 0; c <= 19; c = c + 1) begin
                @(negedge clk);
                drive_idle;
                dbg_sl = SL_A;
                if (c == 0)  do_ld(5'd0, 16'h0, 16'h0);   // store 정리
                if (c == 1)  do_ld(5'd1, 16'h0, 16'h0);
                if (c == 2)  do_fill(ST, SL_A, W300, 1'b1, ST);
                if (c == 4)  do_wave(1'b1, ST, SL_A);
                if (c == 16) begin
                    cmd_v = 1'b1; cmd_op = OP_DRAIN;
                    cmd_st = ST; cmd_sl = SL_A;
                end
                #1;
                // done cycle 13 채집 -> LAT_FAULT 가시 14 (LANE_SPECIAL 0)
                exp_cf = (c >= 14) ? (7'd1 << CF_LAT_FAULT) : 7'd0;
                if (clu_causes !== exp_cf)
                    fail_v("L-CSTICKY", 0, c, {57'd0, clu_causes},
                           {57'd0, exp_cf});
                exp_bf = (c >= 14) ? (14'd1 << FC_CARRY_VFAULT) : 14'd0;
                if (bank_causes !== exp_bf)
                    fail_v("L-BSTICKY", 0, c, {50'd0, bank_causes},
                           {50'd0, exp_bf});
                if (lat_done !== ((c == 13) ? 1'b1 : 1'b0))
                    fail_v("L-DONE", 0, c, {63'd0, lat_done},
                           {63'd0, (c == 13)});
                // writeback 억제 — word 2^300 보존, drain == +Inf
                if (c == 14 && dbg_word !== W300)
                    fail_v("L-SUPPRESS", 0, c, dbg_word, W300);
                if (drain_v !== ((c == 17) ? 1'b1 : 1'b0))
                    fail_v("L-DRAINV", 0, c, {63'd0, drain_v},
                           {63'd0, (c == 17)});
                if (c == 17 && drain_w32 !== 32'h7F80_0000)
                    fail_v("L-DRAIN", 0, c, {32'd0, drain_w32},
                           {32'd0, 32'h7F80_0000});
            end
            if (errors == e0) dir_pass = dir_pass + 1;
            else $display("== PHASE L FAIL ==");
            scen_reset;
        end
    endtask

    // =========================================================================
    // PHASE G — ghost 처분 검증 (헤더 참조; §10 항 3 명세 이행)
    // =========================================================================
    integer    ghost_K, ghost_issued;
    reg [63:0] img_w;
    reg [3:0]  img_own;
    reg        img_v;

    task run_g1;                        // (h) issued<K drain — hw 무검사
        integer c, e0;
        begin
            e0 = errors;
            ghost_K = 2; ghost_issued = 0;
            for (c = 0; c <= 18; c = c + 1) begin
                @(negedge clk);
                drive_idle;
                dbg_sl = SL_A;
                if (c == 0) begin
                    cmd_v = 1'b1; cmd_op = OP_REQ;
                    cmd_st = ST; cmd_sl = SL_A;
                    do_ld(5'd0, 16'h3F80, 16'h3F80);
                end
                if (c == 3) begin
                    do_wave(1'b1, ST, SL_A);
                    ghost_issued = ghost_issued + 1;
                end
                if (c == 15) begin      // K=2 계획 중 1 만 issue — 조기 drain
                    cmd_v = 1'b1; cmd_op = OP_DRAIN;
                    cmd_st = ST; cmd_sl = SL_A;
                end
                #1;
                // hw 는 issued==K 를 강제할 수 없다 (계약 재배정) — fault 0
                // 전 구간이 판정이다. 조기 drain 에 fault 를 기대하지 말 것.
                if (fault_w !== 1'b0)
                    fail_v("G1-FAULT", 0, c,
                           {43'd0, clu_causes, bank_causes}, 64'd0);
                if (acq_v !== ((c == 2) ? 1'b1 : 1'b0))
                    fail_v("G1-ACQ", 0, c, {63'd0, acq_v},
                           {63'd0, (c == 2)});
                if (c == 2 && acq_rej !== 1'b0)
                    fail_v("G1-ACQREJ", 0, c, {63'd0, acq_rej}, 64'd0);
                if (lat_done !== ((c == 12) ? 1'b1 : 1'b0))
                    fail_v("G1-DONE", 0, c, {63'd0, lat_done},
                           {63'd0, (c == 12)});
                if (c == 12 && lat_wide !== WIDE_1)
                    fail_v("G1-WIDE", 0, c, lat_wide, WIDE_1);
                if (drain_v !== ((c == 16) ? 1'b1 : 1'b0))
                    fail_v("G1-DRAINV", 0, c, {63'd0, drain_v},
                           {63'd0, (c == 16)});
                if (c == 16 && drain_w32 !== F32_1)
                    fail_v("G1-DRAIN", 0, c, {32'd0, drain_w32},
                           {32'd0, F32_1});
            end
            $display("[GHOST h] issued=%0d != K=%0d 의 조기 drain 을 hw 가",
                     ghost_issued, ghost_K);
            $display("  fault 없이 수용 — 'hw 강제 불가' 재배정 판정 그대로.");
            $display("  issued==K 보장은 TB/SDK 스케줄 몫 (scoreboard 대조).");
            if (errors == e0) dir_pass = dir_pass + 1;
            else $display("== PHASE G1 FAIL ==");
            scen_reset;
        end
    endtask

    task run_g2a;                       // (l) tag 미공급 FILL — hw 미검사
        integer c, e0;
        begin
            e0 = errors;
            img_v = 1'b0; img_w = 64'd0; img_own = 4'd0;
            for (c = 0; c <= 8; c = c + 1) begin
                @(negedge clk);
                drive_idle;
                dbg_sl = SL_A;
                if (c == 0) do_fill(ST, SL_A, F64_3, 1'b1, ST);
                if (c == 2) begin
                    cmd_v = 1'b1; cmd_op = OP_SPILL;
                    cmd_st = ST; cmd_sl = SL_A;
                end
                if (c == 5)             // 외래 stream, tag 캐리어 미공급
                    do_fill(ST_B, SL_A, img_w, 1'b0, 4'd0);
                #1;
                if (c == 3) begin       // spill 방출 + scoreboard 기록
                    if (spill_v !== 1'b1 || spill_w !== F64_3)
                        fail_v("G2A-SPILL", 0, c, spill_w, F64_3);
                    img_v = 1'b1; img_w = spill_w; img_own = ST;
                end
                else if (spill_v !== 1'b0)
                    fail_v("G2A-SPILLV", 0, c, {63'd0, spill_v}, 64'd0);
                // hw 는 출처를 검사하지 않는다 — fault 0 전 구간이 판정
                if (fault_w !== 1'b0)
                    fail_v("G2A-FAULT", 0, c,
                           {43'd0, clu_causes, bank_causes}, 64'd0);
                if (c == 6) begin       // 수용 (acquire-by-fill 외래 stream)
                    if (resp_v !== 1'b1 || resp_ref !== 1'b0)
                        fail_v("G2A-RESP", 0, c,
                               {62'd0, resp_v, resp_ref}, {62'd0, 2'b10});
                    if (dbg_ov !== 1'b1 || dbg_own !== ST_B
                        || dbg_word !== F64_3)
                        fail_v("G2A-STATE", 0, c,
                               {dbg_ov, 55'd0, dbg_own, 4'd0}, 64'd0);
                end
            end
            // scoreboard ghost 대조 — TB 만이 출처 불일치를 안다
            if (img_v && img_own != ST_B) begin
                $display("[GHOST l] 외래 image (origin stream %0d) 를 stream %0d",
                         img_own, ST_B);
                $display("  이 tag 캐리어 없이 (tag_v=0) FILL — hw 는 수용, fault");
                $display("  없음. spill image 포맷에 owner-토큰이 없어 hw 대조");
                $display("  불가 — fill_owner SDK 계약 강등 판정 그대로 (0x7D");
                $display("  포맷 규범화 시점 재심사 의무 이월).");
            end
            else
                fail_v("G2A-GHOST", 0, 0, {60'd0, img_own}, {60'd0, ST_B});
            if (errors == e0) dir_pass = dir_pass + 1;
            else $display("== PHASE G2a FAIL ==");
            scen_reset;
        end
    endtask

    task run_g2b;                       // (l) 대조 — tag 공급 시 hw 가 거부
        integer c, e0;
        begin
            e0 = errors;
            for (c = 0; c <= 8; c = c + 1) begin
                @(negedge clk);
                drive_idle;
                dbg_sl = SL_A;
                if (c == 0) do_fill(ST, SL_A, F64_3, 1'b1, ST);
                if (c == 2) begin
                    cmd_v = 1'b1; cmd_op = OP_SPILL;
                    cmd_st = ST; cmd_sl = SL_A;
                end
                if (c == 5)             // tag 캐리어 공급 (SDK 가 공급한 형)
                    do_fill(ST_B, SL_A, img_w, 1'b1, img_own);
                #1;
                exp_bf = (c >= 6) ? (14'd1 << FC_FILL_FOREIGN) : 14'd0;
                if (bank_causes !== exp_bf)
                    fail_v("G2B-BSTICKY", 0, c, {50'd0, bank_causes},
                           {50'd0, exp_bf});
                if (clu_causes !== 7'd0)
                    fail_v("G2B-CSTICKY", 0, c, {57'd0, clu_causes}, 64'd0);
                if (c == 6) begin
                    if (resp_v !== 1'b1 || resp_ref !== 1'b1)
                        fail_v("G2B-RESP", 0, c,
                               {62'd0, resp_v, resp_ref}, {62'd0, 2'b11});
                    if (dbg_ov !== 1'b0 || dbg_word !== F64_3)
                        fail_v("G2B-STATE", 0, c,
                               {dbg_ov, dbg_word[62:0]}, F64_3);
                end
            end
            if (errors == e0) dir_pass = dir_pass + 1;
            else $display("== PHASE G2b FAIL ==");
            scen_reset;
        end
    endtask

    // =========================================================================
    // PHASE E — cluster 벡터 전량 (헤더 참조). 라인 스케줄 (cycle):
    //   0: (비-체인) FILL carry / ld pair 0;  1..31: ld pair 1..31;
    //   33: wave (issue 35, lattice beat 35..38, done 42, wb 가시 43);
    //   45: (다음 라인 비-체인) DRAIN — 반출 46 == EXP_FP32.
    // =========================================================================
    reg [511:0] lops;
    reg [527:0] lres;

    task run_vec;
        input integer l;
        input         fill_now;
        input         drain_now;
        integer c, j, b, e0;
        reg [3855:0] v;
        reg          dt_bf16;
        reg [63:0]   expa;
        reg          expresp;
        begin
            v       = cvec[l];
            dt_bf16 = ~v[3824];
            e0      = errors;
            for (c = 0; c <= 47; c = c + 1) begin
                @(negedge clk);
                drive_idle;
                dbg_sl = SL_E;
                if (c == 0 && fill_now)
                    do_fill(ST, SL_E, wide2f64(v[751:688]), 1'b1, ST);
                if (c <= 31)
                    do_ld(c[4:0], v[3823-32*c -: 16], v[3807-32*c -: 16]);
                if (c == 33)
                    do_wave(dt_bf16, ST, SL_E);
                if (c == 45 && drain_now) begin
                    cmd_v = 1'b1; cmd_op = OP_DRAIN;
                    cmd_st = ST; cmd_sl = SL_E;
                end
                #1;
                // 전 구간 무-fault / 무-거부 (loud 불변식)
                if (fault_w !== 1'b0)
                    fail_v("E-FAULT", l, c,
                           {43'd0, clu_causes, bank_causes}, 64'd0);
                if (clu_rej !== 1'b0)
                    fail_v("E-REJ", l, c, {63'd0, clu_rej}, 64'd0);
                // done 궤적 (cycle 정밀 양방향)
                if (lat_done !== ((c == 42) ? 1'b1 : 1'b0))
                    fail_v("E-DONE", l, c, {63'd0, lat_done},
                           {63'd0, (c == 42)});
                // tap 층 — beat b lane j raw 곱 == EXP_ADDEND[8b+j]
                if (c >= 35 && c <= 38) begin
                    b = c - 35;
                    lops = u_dut.lat_ops;
                    for (j = 0; j < 8; j = j + 1) begin
                        expa = v[2799 - 64*(8*b+j) -: 64];
                        if (lops[64*j +: 64] !== expa)
                            fail_v("E-TAP", l, 8*b + j,
                                   lops[64*j +: 64], expa);
                    end
                end
                if (c == 42) begin
                    // resolve 층 (lattice 인스턴스 계층 관측)
                    lres = u_dut.u_lattice.resolved_q;
                    if (lres !== v[687:160]) begin
                        errors = errors + 1;
                        if (errors <= 25)
                            $display("FAIL[E-RESOLVED] line=%0d", l);
                    end
                    if (lat_wide !== v[159:96])
                        fail_v("E-WIDE", l, c, lat_wide, v[159:96]);
                    if (lat_fp32 !== v[31:0])
                        fail_v("E-FP32", l, c, {32'd0, lat_fp32},
                               {32'd0, v[31:0]});
                end
                if (c == 43 && dbg_word !== v[95:32])
                    fail_v("E-BANK", l, c, dbg_word, v[95:32]);
                // 응답/반출 궤적
                expresp = ((c == 1) && fill_now) || (c == 36)
                        || ((c == 46) && drain_now);
                if (resp_v !== expresp
                    || (expresp && (resp_ref !== 1'b0 || resp_vf !== 1'b0)))
                    fail_v("E-RESP", l, c,
                           {61'd0, resp_v, resp_ref, resp_vf},
                           {63'd0, expresp});
                if (drain_v !== (((c == 46) && drain_now) ? 1'b1 : 1'b0))
                    fail_v("E-DRAINV", l, c, {63'd0, drain_v},
                           {63'd0, ((c == 46) && drain_now)});
                if ((c == 46) && drain_now && (drain_w32 !== v[31:0]))
                    fail_v("E-DRAIN", l, c, {32'd0, drain_w32},
                           {32'd0, v[31:0]});
                if (spill_v !== 1'b0)
                    fail_v("E-SPILLV", l, c, {63'd0, spill_v}, 64'd0);
                if (acq_v !== 1'b0)
                    fail_v("E-ACQV", l, c, {63'd0, acq_v}, 64'd0);
            end
            if (errors == e0) e2e_pass = e2e_pass + 1;
            else $display("== E2E 라인 %0d FAIL (누적 %0d) ==",
                          l, errors - e0);
        end
    endtask

    // =========================================================================
    // main
    // =========================================================================
    integer m, l;
    reg ch, dr;

    initial begin
        $readmemh("include/generated/cluster_wave_vectors.hex", cvec);
        errors = 0; disc_hits = 0; disc_shown = 1'b0;
        e2e_pass = 0; dir_pass = 0; n_chain_run = 0;
        drive_idle;
        dbg_sl = 6'd0;
        srst = 1'b1;
        repeat (3) @(negedge clk);
        srst = 1'b0;
        @(negedge clk);

        // ---- directed phases ----
        run_d;
        for (m = 1; m <= 6; m = m + 1)
            run_off0(m);
        run_x1; run_x2; run_x3; run_x4;
        run_w;
        run_s(0); run_s(1);
        run_l;
        run_g1; run_g2a; run_g2b;

        // ---- PHASE E: 벡터 전량 ----
        scen_reset;
        for (l = 0; l < N_VEC; l = l + 1) begin
            ch = cvec[l][3825];
            if (ch) begin
                if (l == 0) begin
                    $display("FATAL: 라인 0 이 체인 표시 — golden 위반");
                    $fatal(1);
                end
                // golden 자체 정합 — META[1] 라인의 carry == 직전 EXP_WIDE
                if (cvec[l][751:688] !== cvec[l-1][159:96]) begin
                    $display("FATAL: 체인 carry 불일치 line %0d", l);
                    $fatal(1);
                end
                n_chain_run = n_chain_run + 1;
            end
            dr = (l == N_VEC - 1) ? 1'b1 : ~cvec[l+1][3825];
            run_vec(l, ~ch, dr);
        end

        // 체인 non-vacuity (계약 §6 family 배치의 산술 고정값)
        if (n_chain_run !== N_CHAIN) begin
            errors = errors + 1;
            $display("FAIL: 체인 라인 수 %0d != %0d (family 소실/드리프트)",
                     n_chain_run, N_CHAIN);
        end

        // ---- 최종 판정 ----
        $display("");
        $display("config: N=8 II=4 LATENCY=%0d slot(E)=%0d", LATENCY, SL_E);
        $display("directed       : %0d/%0d (D/O1-6/X1-4/W/S0-1/L/G1-G2ab)",
                 dir_pass, N_DIR);
        $display("offset-0 중재  : ARB_OFFSET0 4건 + ARB_PORT 2건 (PHASE O)");
        $display("e2e 벡터       : %0d/%0d (체인 %0d — bank carry 재소비)",
                 e2e_pass, N_VEC, n_chain_run);
        $display("disc_hits (중재 절단 오답 모델 적발): %0d", disc_hits);
        if (errors == 0 && disc_hits >= 2
            && dir_pass == N_DIR && e2e_pass == N_VEC
            && n_chain_run == N_CHAIN) begin
            $display("TB_RESULT PASS e2e=%0d/%0d directed=%0d/%0d off0=6 ghost=2 disc_selftest=PASS",
                     e2e_pass, N_VEC, dir_pass, N_DIR);
            $finish;
        end
        else begin
            if (disc_hits < 2)
                $display("TB_RESULT FAIL disc_selftest=FAIL (오답 모델 divergence %0d < 2 — 판정기 tautology 의심)",
                         disc_hits);
            $display("TB_RESULT FAIL errors=%0d", errors);
            $fatal(1);
        end
    end

endmodule
