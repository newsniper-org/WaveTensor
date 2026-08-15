// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

// =============================================================================
// tb_fp_acclattice.v — FP_AccLattice 전-벡터 bit-exact TB (iverilog)
//
// golden: scripts/golden_lattice.py 가 생성한
//   include/generated/lattice_wave_vectors.hex   (4001 벡터, 700 hex/line)
// 레이아웃 계약: include/generated/lattice_vec_contract.md §1/§6.
//
// 판정 (계약 §6 — 표본률 논증 금지):
//   4층 전부 bit-exact — resolve(EXP_RESOLVED) / RTO-48 추출(EXP_WIDE) /
//   bank 인코딩(EXP_BANK) / PACK_FINAL drain(EXP_FP32). 추가로 DUT fault==0
//   (벡터 전제조건 §4 — 전 벡터가 fault-free 입력).
//
// 구동: 1 cycle 1 벡터 스트리밍 (파이프라인 동시 점유 검증 겸함). 벡터 t 를
// negedge t 에 인가, LATENCY(4) posedge 후의 negedge t+4 에 판정.
//
// DISCRIMINATOR 자기시험 (항상 실행 — tautology 방지, 본 프로젝트 기적발
// 결함 유형):
//   TB 내부에 의도적 오답 참조 f_trunc48_ref (RTO-48 의 sticky-jam 을 뺀
//   순수 truncation — "sticky 미반영 참조") 를 두고, wide 층 비교를 같은
//   FAIL 경로로 1회 시연한다 (표찰 [DISC-EXPECTED-FAIL]). 최종 판정:
//     PASS ⇔ (전 벡터 4층 + fault 일치) AND (오답 참조가 1개 이상의
//             벡터에서 실제 FAIL 을 유발)
//   오답 참조가 한 번도 FAIL 하지 않으면 판정기가 tautology 라는 뜻이므로
//   TB 전체를 FAIL 로 강등한다. (golden 사전 계산상 1556/4001 벡터에서
//   갈라진다 — jam/tie family 가 주 표적.)
//
// 실행 (repo root 에서):
//   iverilog -g2012 -o /tmp/tb_fp_acclattice.vvp FP_AccLattice.v \
//            tb_fp_acclattice.v && vvp /tmp/tb_fp_acclattice.vvp
// =============================================================================

`timescale 1ns / 1ps

module tb_fp_acclattice;

    localparam integer N_VEC   = 4001;
    localparam integer LATENCY = 4;

    localparam [63:0] CANON_ZERO_FIELD = 64'h0400_0000_0000_0000;

    // ---- 벡터 메모리 (계약 §1: 1 line = 2800 bit) ----
    reg [2799:0] vec [0:N_VEC-1];

    // ---- clock ----
    reg clk = 1'b0;
    always #5 clk = ~clk;

    // ---- DUT 구동 ----
    reg  [2799:0] cur;
    wire [33*64-1:0] flat;

    // addend k = VEC[2799-64k -: 64], k=0..32 (k=32 가 carry-in [751:688]) —
    // 계약 §6 의 static unroll (genvar 상수 — dynamic part-select 아님)
    genvar gk;
    generate
        for (gk = 0; gk < 33; gk = gk + 1) begin : g_fld
            assign flat[64*gk+63 : 64*gk] = cur[2799-64*gk -: 64];
        end
    endgenerate

    wire [527:0] dut_resolved;
    wire [63:0]  dut_wide, dut_bank;
    wire [31:0]  dut_fp32;
    wire         dut_fault;

    FP_AccLattice dut (
        .clk          (clk),
        .addends_flat (flat),
        .resolved_q   (dut_resolved),
        .wide_q       (dut_wide),
        .bank_q       (dut_bank),
        .fp32_q       (dut_fp32),
        .fault_q      (dut_fault)
    );

    // =========================================================================
    // 의도적 오답 참조 — sticky-jam 미반영 truncation (TB 행위 모델; RTL 이
    // 아니므로 behavioral loop/variable shift 사용)
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
    // 판정 루프
    // =========================================================================
    integer t, chk;
    integer errors, first_err;
    integer disc_hits;                  // 오답 참조가 FAIL 을 유발한 횟수
    reg     disc_shown;
    reg [2799:0] cv;
    reg [527:0]  exp_resolved;
    reg [63:0]   exp_wide, exp_bank, bad_wide;
    reg [31:0]   exp_fp32;

    // 공용 FAIL 경로 — discriminator 자기시험도 같은 경로를 통과시킨다
    task fail_report;
        input [127:0] layer;            // 층 이름 (ASCII)
        input integer idx;
        input [527:0] got;
        input [527:0] expd;
        input         is_disc;          // 1 = 의도적 오답 참조 비교
        begin
            if (is_disc) begin
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

    initial begin
        $readmemh("include/generated/lattice_wave_vectors.hex", vec);
        errors     = 0;
        first_err  = -1;
        disc_hits  = 0;
        disc_shown = 1'b0;
        cur        = vec[0];

        for (t = 0; t < N_VEC + LATENCY; t = t + 1) begin
            @(negedge clk);

            // ---- 판정: 벡터 t-LATENCY 의 출력이 방금 posedge 로 확정됨 ----
            if (t >= LATENCY) begin
                chk = t - LATENCY;
                cv  = vec[chk];
                exp_resolved = cv[687:160];
                exp_wide     = cv[159:96];
                exp_bank     = cv[95:32];
                exp_fp32     = cv[31:0];

                if (dut_resolved !== exp_resolved)
                    fail_report("RESOLVED", chk,
                                {dut_resolved}, {exp_resolved}, 1'b0);
                if (dut_wide !== exp_wide)
                    fail_report("WIDE", chk,
                                {464'b0, dut_wide}, {464'b0, exp_wide}, 1'b0);
                if (dut_bank !== exp_bank)
                    fail_report("BANK", chk,
                                {464'b0, dut_bank}, {464'b0, exp_bank}, 1'b0);
                if (dut_fp32 !== exp_fp32)
                    fail_report("FP32", chk,
                                {496'b0, dut_fp32}, {496'b0, exp_fp32}, 1'b0);
                if (dut_fault !== 1'b0)
                    fail_report("FAULT", chk,
                                {527'b0, dut_fault}, 528'b0, 1'b0);

                // ---- discriminator 자기시험: 오답 참조를 같은 FAIL 경로로 ----
                bad_wide = f_trunc48_ref(exp_resolved);
                if (dut_wide !== bad_wide)
                    fail_report("WIDE-vs-BADREF", chk,
                                {464'b0, dut_wide}, {464'b0, bad_wide}, 1'b1);
            end

            // ---- 인가: negedge t 에 vec[t] (posedge t+1 에서 S1 진입 —
            // 그 출력은 negedge t+LATENCY 에 판정된다) ----
            if (t < N_VEC)
                cur = vec[t];
        end

        // ---- 최종 판정 ----
        $display("");
        $display("vectors: %0d  errors: %0d  disc_hits: %0d",
                 N_VEC, errors, disc_hits);
        if (errors == 0 && disc_hits > 0) begin
            $display("TB_RESULT PASS pass=%0d total=%0d disc_selftest=PASS",
                     N_VEC, N_VEC);
            $finish;
        end
        else begin
            if (errors != 0)
                $display("TB_RESULT FAIL pass=%0d total=%0d first_fail=%0d",
                         N_VEC - errors, N_VEC, first_err);
            if (disc_hits == 0)
                $display("TB_RESULT FAIL disc_selftest=FAIL (오답 참조가 한 번도 FAIL 하지 않음 — 판정기 tautology 의심)");
            $fatal(1);
        end
    end

endmodule
