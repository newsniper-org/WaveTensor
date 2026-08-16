// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

// =============================================================================
// tb_fp_acclattice.v — FP_AccLattice (beat-serial 출하형) 전-벡터 bit-exact TB
//
// golden: scripts/golden_lattice.py 가 생성한
//   include/generated/lattice_wave_vectors.hex   (4081 벡터, 700 hex/line)
// 레이아웃 계약: include/generated/lattice_vec_contract.md §1/§6. exact
// lattice 는 순서-무관 (§27.2.1) 이므로 같은 33-addend 집합의 beat-serial
// 재생은 full-parallel 과 4층 전부 bit-exact 여야 한다 — 그것이 판정이다.
//
// beat 스케줄 (FP_AccLattice.v 헤더 계약 — 본 TB 가 carry-in 선택을 봉인):
//   beat b (= 0..NUM_BEATS-1, 연속 cycle): ops_i[64j+:64] = addend N*b+j.
//   carry_i = addend 32 — beat 0 (start_i 와 같은 cycle) 에만 유효값 인가.
//   ** 비-beat0 cycle 의 carry_i 에는 고의 오염값 (예약 비트 위반 필드) 을
//   인가한다 ** — DUT 가 beat 0 밖에서 carry_i 를 샘플하면 fault (a) 또는
//   값 오염으로 반드시 FAIL 한다 (carry-in "beat 0 병합" 선택의 봉인).
//
// 인가는 전 벡터 back-to-back (wave-step 사이 idle cycle 0) — II =
// NUM_BEATS 파이프라인 중첩 (resolve/추출 vs 다음 wave-step 의 beat 열)
// 을 함께 검증한다. done_q 간격이 정확히 NUM_BEATS 임을 매 벡터 확인.
// ** 첫 done_q 의 절대 latency == LATENCY (= NUM_BEATS+3) 도 assert 한다 **
// — bank 함의 '같은 slot 체이닝 >= LATENCY' (하류 ③ dispatch 스케줄 입력
// 제약) 가 이 상수에 걸려 있으므로 간격 (II) 만으로는 불충분하다.
//
// 판정 (계약 §6 — 표본률 논증 금지):
//   4층 전부 bit-exact — resolve(EXP_RESOLVED) / RTO-48 추출(EXP_WIDE) /
//   bank 인코딩(EXP_BANK) / PACK_FINAL drain(EXP_FP32). 추가로 DUT fault==0
//   (벡터 전제조건 §4 — 전 벡터가 fault-free 입력).
//
// FAULT-주입 directed phase (벡터 완주 직후 back-to-back 연속 인가):
//   벡터 계약 §4 가 fault-free 입력만 공급하므로, fault (a)~(f) 검출 배선
//   과 per-beat sticky 누적·beat0 리셋 (loud-fault-never-silent 법칙의
//   구현) 은 벡터만으로는 반증 불가다 (반증 폐쇄 2026-08-16, MUT-D).
//   본 TB 는 벡터 phase 후 16개의 directed wave 를 인가한다:
//     - fault 클래스 (a) 예약비트 / (b) 비-canonical zero / (c) leading
//       zero>1 / (d) 배치 범위 밖 (고·저 양측) / (e) 표현성 위반 /
//       (f) 추출 지수 범위 밖 — 각각 서로 다른 beat·lane 위치 (addend
//       index 1..31 분산; N=8/N=2 양쪽에서 beat 0·중간·마지막 beat 를
//       커버) 에 1건씩 주입, done 시 fault_q===1 확인 (sticky 누적 +
//       검출기 생존 증명).
//     - carry lane fault @ beat 0 — 비-beat0 POISON (과잉 샘플 봉인) 의
//       반대 방향인 '검출기 사망 (과소)' 을 봉인.
//     - 각 fault wave 직후 all-zero clean wave — fault_q===0 + canonical
//       zero 4층 확인 (fault_acc 의 beat0 리셋; 오염이 해당 wave 에만
//       국한됨을 증명).
//
// DISCRIMINATOR 자기시험 (항상 실행 — tautology 방지, 본 프로젝트 기적발
// 결함 유형; 벡터 phase 에만 적용):
//   (1) f_trunc48_ref — RTO-48 의 sticky-jam 을 뺀 순수 truncation ("전면
//       sticky 미반영"). golden 사전 계산상 1556(구 벡터)+80(신규 밴드
//       family) 벡터에서 갈라진다.
//   (2) f_pt48_ref — sticky 를 leading bit 아래 48..79 위치와 window 밖
//       (>=128) 에서만 취하고 80..127 밴드를 고의로 절단한 부분-절단 오답
//       참조 (MUT-A 계열의 행위 모델). sticky_window_band family
//       (d=80..127, 48개 벡터) 가 이를 적발한다 (golden 사전 계산상 총
//       49 벡터 — 신규 48 + 기존 cancellation 1) — 부분-절단 계열이 벡터
//       셋으로 판별됨을 자기시험으로 상시 증명 (반증 폐쇄 2026-08-16).
//   최종 판정: PASS ⇔ (전 벡터 4층 + fault 일치) AND (directed fault
//   phase 전건 일치) AND (두 오답 참조가 각각 1개 이상의 벡터에서 실제
//   FAIL 을 유발). 오답 참조가 한 번도 FAIL 하지 않으면 판정기 tautology
//   로 보고 TB 전체를 FAIL 로 강등한다.
//
// 계약 §6 스케치로부터의 명시적 일탈 (사유 기록): §6 은 TB 슬라이싱도
// static unroll 로 스케치했으나, 본 TB 의 driver/checker 는 행위 모델로서
// dynamic part-select (`ops[64*j +: 64]`) / variable shift (`cv >> ...`)
// 를 사용한다 — dynamic part-select 금지 (project law) 는 RTL 을 구속하며
// (FP_AccLattice.v 는 clean), TB 행위 모델은 면책 (§6 완화 문구와 동기;
// 양 시뮬레이터 정상 동작 실증).
//
// 실행 (repo root 에서 — 기본 N=8 전 4081 벡터; -Wno-TIMESCALEMOD 는 repo
// RTL 이 timescale 을 갖지 않는 관례 때문 — TB 에만 timescale 존재):
//   $ verilator --binary --timing -j 0 -Wno-TIMESCALEMOD \
//       FP_AccLattice.v tb_fp_acclattice.v \
//       --top-module tb_fp_acclattice -o tb_acclat --Mdir /tmp/wt_acclat_obj
//   $ /tmp/wt_acclat_obj/tb_acclat
// N=2 파라미터화 회귀 (Beat2 역할 승계 구성): 위에 -GTB_N=2 추가.
// iverilog 도 가능:
//   $ iverilog -g2012 -o /tmp/tb_acclat.vvp FP_AccLattice.v \
//       tb_fp_acclattice.v && vvp /tmp/tb_acclat.vvp
// =============================================================================

`timescale 1ns / 1ps

/* verilator lint_off WIDTHTRUNC */
// (TB 행위 모델의 의도적 절단 — addend 슬라이싱 / 오답 참조의 e = p-266.
//  RTL 이 아님; FP_AccLattice.v 는 -Wall clean.)

module tb_fp_acclattice;

    parameter integer TB_N   = 8;      // PRODUCTS_PER_BEAT (-G/-P 재정의 가능)
    parameter integer TB_VEC = 4081;   // 검사 벡터 수 (앞에서부터)

    localparam integer N_VEC_MEM = 4081;
    localparam integer NB        = 32 / TB_N;
    localparam integer LATENCY   = NB + 3;

    // directed fault-주입 phase: fault/clean 교대 16 wave (헤더 참조)
    localparam integer NF        = 16;
    localparam integer TOTAL     = TB_VEC + NF;

    localparam [63:0] CANON_ZERO_FIELD = 64'h0400_0000_0000_0000;
    // 비-beat0 cycle 의 carry_i 오염 감시값 — 예약 비트 [63:60] 위반 필드.
    // DUT 가 beat 0 밖에서 carry 를 샘플하면 fault/값 층에서 반드시 적발된다.
    localparam [63:0] POISON_FIELD     = 64'hFFFF_FFFF_FFFF_FFFF;

    // ---- 벡터 메모리 (계약 §1: 1 line = 2800 bit) ----
    reg [2799:0] vec [0:N_VEC_MEM-1];

    // ---- clock ----
    reg clk = 1'b0;
    always #5 clk = ~clk;

    // ---- DUT 구동 (negedge blocking — DUT 는 posedge 샘플) ----
    reg                 start;
    reg [TB_N*64-1:0]   ops;
    reg [63:0]          carry;

    wire [527:0] dut_resolved;
    wire [63:0]  dut_wide, dut_bank;
    wire [31:0]  dut_fp32;
    wire         dut_fault, dut_done;

    FP_AccLattice #(.PRODUCTS_PER_BEAT(TB_N)) dut (
        .clk        (clk),
        .start_i    (start),
        .ops_i      (ops),
        .carry_i    (carry),
        .resolved_q (dut_resolved),
        .wide_q     (dut_wide),
        .bank_q     (dut_bank),
        .fp32_q     (dut_fp32),
        .fault_q    (dut_fault),
        .done_q     (dut_done)
    );

    // =========================================================================
    // 의도적 오답 참조 1 — sticky-jam 전면 미반영 truncation (TB 행위 모델;
    // RTL 이 아니므로 behavioral loop/variable shift 사용)
    // =========================================================================
    function [63:0] f_trunc48_ref;
        input [527:0] lat;              // EXP_RESOLVED (two's complement)
        reg           s;
        reg [527:0]   mag, tmp;
        integer       p, i;
        reg signed [11:0] e;
        begin
            if (lat == 528'd0)
                f_trunc48_ref = CANON_ZERO_FIELD;
            else begin
                s   = lat[527];
                mag = s ? (~lat + 528'd1) : lat;
                p = 0;
                for (i = 0; i <= 527; i = i + 1)
                    if (mag[i]) p = i;
                tmp = (p >= 47) ? (mag >> (p - 47)) : (mag << (47 - p));
                e = p - 266;
                // 오답 지점: RTO 라면 (|잘린 비트| != 0) 을 LSB 에 OR-jam
                // 해야 하나, 여기서는 고의로 생략한다 (truncate 그대로).
                f_trunc48_ref = {4'b0000, s, e[10:0], tmp[47:0]};
            end
        end
    endfunction

    // =========================================================================
    // 의도적 오답 참조 2 — sticky 부분 절단 (leading bit 아래 80..127 밴드
    // 를 고의 누락 — RTL 추출기의 `|n6[79:0]` 를 `|n6[79:48]` 류로 절단한
    // 변이의 행위 모델). sticky_window_band family (d=80..127) 가 적발한다.
    // =========================================================================
    function [63:0] f_pt48_ref;
        input [527:0] lat;
        reg           s;
        reg [527:0]   mag, tmp;
        integer       p, i;
        reg signed [11:0] e;
        reg           j2;
        begin
            if (lat == 528'd0)
                f_pt48_ref = CANON_ZERO_FIELD;
            else begin
                s   = lat[527];
                mag = s ? (~lat + 528'd1) : lat;
                p = 0;
                for (i = 0; i <= 527; i = i + 1)
                    if (mag[i]) p = i;
                tmp = (p >= 47) ? (mag >> (p - 47)) : (mag << (47 - p));
                e = p - 266;
                // 오답 지점: sticky 를 top-48 아래 전체가 아니라 offset
                // 48..79 와 >=128 에서만 취한다 (80..127 밴드 절단).
                j2 = 1'b0;
                for (i = 0; i <= 527; i = i + 1)
                    if (mag[i] && (i <= p - 48)
                        && !(((p - i) >= 80) && ((p - i) <= 127)))
                        j2 = 1'b1;
                f_pt48_ref = {4'b0000, s, e[10:0],
                              tmp[47:1], tmp[0] | j2};
            end
        end
    endfunction

    // =========================================================================
    // 공용 FAIL 경로 — discriminator 자기시험도 같은 경로를 통과시킨다
    // kind: 0 = 실판정, 1 = 오답 참조 1 (전면 절단), 2 = 오답 참조 2 (부분)
    // =========================================================================
    integer errors, first_err;
    integer disc_hits, disc2_hits;      // 오답 참조가 FAIL 을 유발한 횟수
    reg     disc_shown, disc2_shown;

    task fail_report;
        input [127:0] layer;            // 층 이름 (ASCII)
        input integer idx;
        input [527:0] got;
        input [527:0] expd;
        input [1:0]   kind;
        begin
            if (kind == 2'd1) begin
                disc_hits = disc_hits + 1;
                if (!disc_shown) begin
                    disc_shown = 1'b1;
                    $display("[DISC-EXPECTED-FAIL] vec %0d layer %0s:", idx,
                             layer);
                    $display("  dut     = %h", got);
                    $display("  bad_ref = %h", expd);
                    $display("  -> sticky-jam 미반영 오답 참조가 실제 FAIL 을");
                    $display("     유발함 — 판정기 비-tautology 시연 (1회).");
                end
            end
            else if (kind == 2'd2) begin
                disc2_hits = disc2_hits + 1;
                if (!disc2_shown) begin
                    disc2_shown = 1'b1;
                    $display("[DISC2-EXPECTED-FAIL] vec %0d layer %0s:", idx,
                             layer);
                    $display("  dut     = %h", got);
                    $display("  bad_ref = %h", expd);
                    $display("  -> sticky 부분-절단 (80..127 밴드 누락) 오답");
                    $display("     참조도 실제 FAIL 을 유발함 (1회 시연).");
                end
            end
            else begin
                errors = errors + 1;
                if (first_err < 0) first_err = idx;
                if (errors <= 10) begin
                    $display("FAIL vec %0d layer %0s:", idx, layer);
                    $display("  got = %h", got);
                    $display("  exp = %h", expd);
                end
            end
        end
    endtask

    // =========================================================================
    // directed fault-주입 wave 정의 (시간 0 에 구성; 헤더 참조)
    // fault 위치는 addend index 로 지정 — beat = idx/TB_N 이므로 N=8/N=2
    // 양쪽에서 beat 0·중간·마지막 beat 가 모두 커버된다.
    // =========================================================================
    reg [63:0]   faddend [0:NF*33-1];   // wave w 의 addend k = faddend[33w+k]
    reg [NF-1:0] fexp;                  // 1 = fault_q==1 기대
    integer      fi, fj;

    // =========================================================================
    // 절대 latency 감시 (posedge 프레임 — 결정적 관측):
    //   * start 는 driver 가 negedge 에 blocking 으로 세우므로 posedge 읽기
    //     는 race-free — 첫 1 관측 posedge = DUT 의 beat0 샘플 edge.
    //   * done_q 는 DUT 가 posedge NBA 로 세우므로 같은 edge 의 active
    //     읽기는 이전 값 — 첫 1 관측 posedge = (done 등록 edge)+1
    //     = beat0 edge + (NB+3) = beat0 edge + LATENCY.
    //   따라서 p_done - p_start == LATENCY 가 정확한 절대 latency 판정이다
    //   (최종 판정 블록에서 assert; drain 창이 넉넉해 done 이 +8 cycle
    //   늦어도 벡터 비교만으로는 안 잡히는 격차를 이것이 폐쇄한다).
    // =========================================================================
    integer pcyc    = 0;
    integer p_start = -1;
    integer p_done  = -1;

    always @(posedge clk) begin
        pcyc = pcyc + 1;
        if ((p_start < 0) && (start === 1'b1))    p_start = pcyc;
        if ((p_done  < 0) && (dut_done === 1'b1)) p_done  = pcyc;
    end

    // =========================================================================
    // 판정 프로세스 — done_q 순서 = wave 순서 (고정-latency 파이프라인).
    // back-to-back 인가에서 done 간격은 정확히 NUM_BEATS (II 검증).
    // =========================================================================
    integer chk = 0;
    integer cyc = 0;
    integer last_done_cyc = -1;
    reg [2799:0] ccv;
    reg [527:0]  exp_resolved;
    reg [63:0]   exp_wide, exp_bank, bad_wide, bad_wide2;
    reg [31:0]   exp_fp32;

    always @(negedge clk) begin
        cyc = cyc + 1;
        if (dut_done) begin
            if (chk >= TOTAL) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("FAIL: 예기치 않은 done_q (chk=%0d, cyc=%0d)",
                             chk, cyc);
            end
            else begin
                if (chk < TB_VEC) begin
                    // ================= 벡터 phase =================
                    ccv          = vec[chk];
                    exp_resolved = ccv[687:160];
                    exp_wide     = ccv[159:96];
                    exp_bank     = ccv[95:32];
                    exp_fp32     = ccv[31:0];

                    if (dut_resolved !== exp_resolved)
                        fail_report("RESOLVED", chk,
                                    {dut_resolved}, {exp_resolved}, 2'd0);
                    if (dut_wide !== exp_wide)
                        fail_report("WIDE", chk, {464'b0, dut_wide},
                                    {464'b0, exp_wide}, 2'd0);
                    if (dut_bank !== exp_bank)
                        fail_report("BANK", chk, {464'b0, dut_bank},
                                    {464'b0, exp_bank}, 2'd0);
                    if (dut_fp32 !== exp_fp32)
                        fail_report("FP32", chk, {496'b0, dut_fp32},
                                    {496'b0, exp_fp32}, 2'd0);
                    if (dut_fault !== 1'b0)
                        fail_report("FAULT", chk,
                                    {527'b0, dut_fault}, 528'b0, 2'd0);

                    // ---- discriminator 자기시험 (오답 참조 2종) ----
                    bad_wide = f_trunc48_ref(exp_resolved);
                    if (dut_wide !== bad_wide)
                        fail_report("WIDE-vs-BADREF", chk,
                                    {464'b0, dut_wide},
                                    {464'b0, bad_wide}, 2'd1);
                    bad_wide2 = f_pt48_ref(exp_resolved);
                    if (dut_wide !== bad_wide2)
                        fail_report("WIDE-vs-BADREF2", chk,
                                    {464'b0, dut_wide},
                                    {464'b0, bad_wide2}, 2'd2);
                end
                else begin
                    // ============ directed fault-주입 phase ============
                    if (fexp[chk-TB_VEC]) begin
                        // fault wave: loud-fault 필수 (값 층은 fault 계약상
                        // 무의미 — fault_q 만 판정)
                        if (dut_fault !== 1'b1)
                            fail_report("FAULT-INJ", chk,
                                        {527'b0, dut_fault},
                                        {527'b0, 1'b1}, 2'd0);
                    end
                    else begin
                        // 직전 fault wave 직후의 all-zero clean wave:
                        // fault_acc beat0 리셋 + 오염 국한성 + 4층 canonical
                        if (dut_fault !== 1'b0)
                            fail_report("CLEAN-AFTER-INJ", chk,
                                        {527'b0, dut_fault}, 528'b0, 2'd0);
                        if (dut_resolved !== 528'd0)
                            fail_report("CLEAN-RESOLVED", chk,
                                        {dut_resolved}, 528'd0, 2'd0);
                        if (dut_wide !== CANON_ZERO_FIELD)
                            fail_report("CLEAN-WIDE", chk,
                                        {464'b0, dut_wide},
                                        {464'b0, CANON_ZERO_FIELD}, 2'd0);
                        if (dut_bank !== 64'd0)
                            fail_report("CLEAN-BANK", chk,
                                        {464'b0, dut_bank}, 528'd0, 2'd0);
                        if (dut_fp32 !== 32'd0)
                            fail_report("CLEAN-FP32", chk,
                                        {496'b0, dut_fp32}, 528'd0, 2'd0);
                    end
                end

                // ---- II 간격: back-to-back 인가에서 done 간격 == NB ----
                // (directed phase 는 벡터 phase 직후 idle 없이 이어지므로
                //  경계 포함 전 wave 에 동일하게 적용)
                if ((chk > 0) && ((cyc - last_done_cyc) != NB)) begin
                    errors = errors + 1;
                    if (errors <= 10)
                        $display("FAIL vec %0d: done 간격 %0d != II(%0d)",
                                 chk, cyc - last_done_cyc, NB);
                end
                last_done_cyc = cyc;

                chk = chk + 1;
            end
        end
    end

    // =========================================================================
    // 구동 프로세스 — 전 벡터 + directed fault wave, 전부 back-to-back
    // =========================================================================
    integer t, b, j, w;
    reg [2799:0] cv;
    reg [63:0]   addend [0:32];

    initial begin
        $readmemh("include/generated/lattice_wave_vectors.hex", vec);
        errors      = 0;
        first_err   = -1;
        disc_hits   = 0;
        disc2_hits  = 0;
        disc_shown  = 1'b0;
        disc2_shown = 1'b0;
        start = 1'b0;
        ops   = {TB_N{CANON_ZERO_FIELD}};
        carry = POISON_FIELD;

        // ---- directed fault-주입 wave 구성 (시간 0; 짝수 idx = fault,
        //      홀수 idx = all-zero clean — fault/clean 교대) ----
        for (fi = 0; fi < NF; fi = fi + 1)
            for (fj = 0; fj < 33; fj = fj + 1)
                faddend[33*fi+fj] = CANON_ZERO_FIELD;
        fexp = {NF{1'b0}};
        // (a) 예약 비트 [63:60]!=0 — addend 31 (마지막 beat 마지막 lane)
        faddend[33*0  + 31] = 64'h8400_0000_0000_0000;  fexp[0]  = 1'b1;
        // (b) sig==0 이나 비-canonical zero (전부 0 필드) — addend 17
        faddend[33*2  + 17] = 64'h0000_0000_0000_0000;  fexp[2]  = 1'b1;
        // (c) nonzero sig 의 leading zero>1 (sig=1) — addend 1 (beat 0)
        faddend[33*4  +  1] = 64'h0000_0000_0000_0001;  fexp[4]  = 1'b1;
        // (d-고) q>528: e=+300, normalized — addend 9
        faddend[33*6  +  9] = 64'h012C_8000_0000_0000;  fexp[6]  = 1'b1;
        // (d-저) q<1: e=-300, normalized — addend 13
        faddend[33*8  + 13] = 64'h06D4_8000_0000_0000;  fexp[8]  = 1'b1;
        // (e) 표현성 위반: e=-260, sig 홀수 -> PHYS[47:0] 침범 — addend 25
        faddend[33*10 + 25] = 64'h06FC_8000_0000_0001;  fexp[10] = 1'b1;
        // (f) 추출 지수 범위 밖: 2^260 + 2^260 = 2^261 (lane 은 전부 유효,
        //     resolve 합만 범위 밖 -> e==261 검출) — addend 0,1
        faddend[33*12 +  0] = 64'h0104_8000_0000_0000;
        faddend[33*12 +  1] = 64'h0104_8000_0000_0000;  fexp[12] = 1'b1;
        // carry lane fault @ beat 0 — 검출기 사망 (과소) 방향의 봉인
        //     (비-beat0 POISON 은 과잉 샘플 방향만 봉인한다)
        faddend[33*14 + 32] = 64'hFFFF_FFFF_FFFF_FFFF;  fexp[14] = 1'b1;

        @(negedge clk);

        // ---- 벡터 phase ----
        for (t = 0; t < TB_VEC; t = t + 1) begin
            cv = vec[t];
            // addend k = cv[2799-64k -: 64] (계약 §6 — TB 행위 모델 면책,
            // 헤더의 일탈 주석 참조)
            for (j = 0; j < 33; j = j + 1)
                addend[j] = cv >> (2800 - 64*(j+1));

            for (b = 0; b < NB; b = b + 1) begin
                start = (b == 0);
                carry = (b == 0) ? addend[32] : POISON_FIELD;
                for (j = 0; j < TB_N; j = j + 1)
                    ops[64*j +: 64] = addend[TB_N*b + j];
                @(negedge clk);
            end
        end

        // ---- directed fault-주입 phase (idle 없이 연속) ----
        for (t = 0; t < NF; t = t + 1) begin
            for (b = 0; b < NB; b = b + 1) begin
                start = (b == 0);
                carry = (b == 0) ? faddend[33*t + 32] : POISON_FIELD;
                for (j = 0; j < TB_N; j = j + 1)
                    ops[64*j +: 64] = faddend[33*t + TB_N*b + j];
                @(negedge clk);
            end
        end

        start = 1'b0;
        carry = POISON_FIELD;
        ops   = {TB_N{CANON_ZERO_FIELD}};

        // ---- 파이프라인 drain (LATENCY + 여유) ----
        for (w = 0; (w < LATENCY + 8) && (chk < TOTAL); w = w + 1)
            @(negedge clk);

        // ---- 최종 판정 ----
        $display("");
        $display("config: PRODUCTS_PER_BEAT=%0d NUM_BEATS(II)=%0d LATENCY=%0d",
                 TB_N, NB, LATENCY);
        $display("vectors: %0d  fault_directed: %0d  checked: %0d  errors: %0d",
                 TB_VEC, NF, chk, errors);
        $display("disc_hits: %0d (전면 절단)  disc2_hits: %0d (부분 절단)",
                 disc_hits, disc2_hits);
        if (chk < TOTAL) begin
            errors = errors + 1;
            $display("FAIL: done_q 미도착 — %0d/%0d wave 만 완료", chk, TOTAL);
        end
        // ---- 첫 done 절대 latency == LATENCY (= NB+3) — posedge 감시 ----
        if ((p_start < 0) || (p_done < 0)
            || ((p_done - p_start) != LATENCY)) begin
            errors = errors + 1;
            $display("FAIL: 첫 done 절대 latency %0d != LATENCY(%0d)",
                     (p_done < 0 || p_start < 0) ? -1 : (p_done - p_start),
                     LATENCY);
        end
        else
            $display("latency: 첫 done = beat0 + %0d cycle == LATENCY (OK)",
                     p_done - p_start);
        if (errors == 0 && disc_hits > 0 && disc2_hits > 0) begin
            $display("TB_RESULT PASS pass=%0d total=%0d disc_selftest=PASS disc2_selftest=PASS",
                     TOTAL, TOTAL);
            $finish;
        end
        else begin
            if (errors != 0)
                $display("TB_RESULT FAIL pass=%0d total=%0d first_fail=%0d",
                         TOTAL - errors, TOTAL, first_err);
            if (disc_hits == 0)
                $display("TB_RESULT FAIL disc_selftest=FAIL (전면-절단 오답 참조가 한 번도 FAIL 하지 않음 — 판정기 tautology 의심)");
            if (disc2_hits == 0)
                $display("TB_RESULT FAIL disc2_selftest=FAIL (부분-절단 오답 참조가 한 번도 FAIL 하지 않음 — sticky 밴드 커버리지 소실)");
            $fatal(1);
        end
    end

endmodule
