// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

// =============================================================================
// tb_fp_acclattice_beat2.v — FP_AccLatticeBeat2 (ECP5 feasibility measurement
// 전용 beat-serial 변형) 전-벡터 bit-exact 스모크 TB.
//
// golden 벡터는 full-parallel TB (tb_fp_acclattice.v) 와 동일:
//   include/generated/lattice_wave_vectors.hex (4001 벡터, 계약:
//   include/generated/lattice_vec_contract.md). exact lattice 는 순서-무관
// 이므로 (§27.2.1) 같은 33-addend 집합의 beat-serial 재생은 4층 전부
// (RESOLVED/WIDE/BANK/FP32) bit-exact 여야 한다 — 그것이 판정이다.
//
// beat 스케줄 (FP_AccLatticeBeat2.v 헤더 계약):
//   beat b (0..15): op_a = addend 2b, op_b = addend 2b+1
//   beat 16       : op_a = addend 32 (carry-in), op_b = canonical zero
//
// DISCRIMINATOR 자기시험 (tb_fp_acclattice.v 와 동일 규율 — tautology 방지):
//   sticky-jam 을 뺀 truncation 오답 참조가 1개 이상의 벡터에서 실제 FAIL
//   경로를 타야 PASS (golden 사전 계산상 1556/4001 벡터에서 갈라진다).
//
// 실행 (repo root 에서):
//   $ verilator --binary --timing -j 0 -Wno-fatal \
//       synth/lattice/fp_ops/FP_AccLatticeBeat2.v \
//       synth/lattice/fp_ops/tb_fp_acclattice_beat2.v \
//       --top-module tb_fp_acclattice_beat2 -o tb_beat2 \
//       --Mdir /tmp/wt_beat2_obj
//   $ /tmp/wt_beat2_obj/tb_beat2
// =============================================================================

`timescale 1ns / 1ps

module tb_fp_acclattice_beat2;

    localparam integer N_VEC = 4001;

    localparam [63:0] CANON_ZERO_FIELD = 64'h0400_0000_0000_0000;

    reg [2799:0] vec [0:N_VEC-1];

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg         start;
    reg  [63:0] op_a, op_b;

    wire [527:0] dut_resolved;
    wire [63:0]  dut_wide, dut_bank;
    wire [31:0]  dut_fp32;
    wire         dut_fault, dut_done;

    FP_AccLatticeBeat2 dut (
        .clk        (clk),
        .start_i    (start),
        .op_a_i     (op_a),
        .op_b_i     (op_b),
        .resolved_q (dut_resolved),
        .wide_q     (dut_wide),
        .bank_q     (dut_bank),
        .fp32_q     (dut_fp32),
        .fault_q    (dut_fault),
        .done_q     (dut_done)
    );

    // ---- 의도적 오답 참조 (sticky-jam 미반영 truncation) — TB 행위 모델 ----
    function [63:0] f_trunc48_ref;
        input [527:0] lat;
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
                f_trunc48_ref = {4'b0000, s, e[10:0], tmp[47:0]};
            end
        end
    endfunction

    integer t, b, w, errors, disc_hits, first_err;
    reg [2799:0] cv;
    reg [527:0]  exp_resolved;
    reg [63:0]   exp_wide, exp_bank, bad_wide;
    reg [31:0]   exp_fp32;
    reg [63:0]   addend [0:32];
    reg          disc_shown;

    initial begin
        $readmemh("include/generated/lattice_wave_vectors.hex", vec);
        errors     = 0;
        disc_hits  = 0;
        first_err  = -1;
        disc_shown = 1'b0;
        start = 1'b0;
        op_a  = CANON_ZERO_FIELD;
        op_b  = CANON_ZERO_FIELD;

        @(negedge clk);

        for (t = 0; t < N_VEC; t = t + 1) begin
            cv = vec[t];
            // addend k = cv[2799-64k -: 64] (계약 §6 정적 배열 — TB 행위 모델)
            for (b = 0; b < 33; b = b + 1)
                addend[b] = cv >> (2800 - 64*(b+1));
            exp_resolved = cv[687:160];
            exp_wide     = cv[159:96];
            exp_bank     = cv[95:32];
            exp_fp32     = cv[31:0];

            // ---- 17 acc beats ----
            for (b = 0; b < 17; b = b + 1) begin
                start = (b == 0);
                op_a  = (b < 16) ? addend[2*b]   : addend[32];
                op_b  = (b < 16) ? addend[2*b+1] : CANON_ZERO_FIELD;
                @(negedge clk);
            end
            start = 1'b0;
            op_a  = CANON_ZERO_FIELD;
            op_b  = CANON_ZERO_FIELD;

            // ---- resolve 9 + extract 2 → done ----
            w = 0;
            while (!dut_done && w < 20) begin
                @(negedge clk);
                w = w + 1;
            end
            if (!dut_done) begin
                errors = errors + 1;
                if (first_err < 0) first_err = t;
                if (errors <= 10)
                    $display("FAIL vec %0d: done_q not seen within 20 cycles",
                             t);
            end
            else begin
                if (dut_resolved !== exp_resolved) begin
                    errors = errors + 1;
                    if (first_err < 0) first_err = t;
                    if (errors <= 10) begin
                        $display("FAIL vec %0d layer RESOLVED:", t);
                        $display("  got = %h", dut_resolved);
                        $display("  exp = %h", exp_resolved);
                    end
                end
                if (dut_wide !== exp_wide) begin
                    errors = errors + 1;
                    if (first_err < 0) first_err = t;
                    if (errors <= 10)
                        $display("FAIL vec %0d layer WIDE: got %h exp %h",
                                 t, dut_wide, exp_wide);
                end
                if (dut_bank !== exp_bank) begin
                    errors = errors + 1;
                    if (first_err < 0) first_err = t;
                    if (errors <= 10)
                        $display("FAIL vec %0d layer BANK: got %h exp %h",
                                 t, dut_bank, exp_bank);
                end
                if (dut_fp32 !== exp_fp32) begin
                    errors = errors + 1;
                    if (first_err < 0) first_err = t;
                    if (errors <= 10)
                        $display("FAIL vec %0d layer FP32: got %h exp %h",
                                 t, dut_fp32, exp_fp32);
                end
                if (dut_fault !== 1'b0) begin
                    errors = errors + 1;
                    if (first_err < 0) first_err = t;
                    if (errors <= 10)
                        $display("FAIL vec %0d layer FAULT: got %b exp 0",
                                 t, dut_fault);
                end

                // ---- discriminator 자기시험 ----
                bad_wide = f_trunc48_ref(exp_resolved);
                if (dut_wide !== bad_wide) begin
                    disc_hits = disc_hits + 1;
                    if (!disc_shown) begin
                        disc_shown = 1'b1;
                        $display("[DISC-EXPECTED-FAIL] vec %0d: dut %h vs bad_ref %h",
                                 t, dut_wide, bad_wide);
                        $display("  -> sticky-jam 미반영 오답 참조가 실제 FAIL 을 유발함 (1회 시연).");
                    end
                end

                @(negedge clk);   // done 소거 후 다음 벡터
            end
        end

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
                $display("TB_RESULT FAIL disc_selftest=FAIL (판정기 tautology 의심)");
            $fatal(1);
        end
    end

endmodule
