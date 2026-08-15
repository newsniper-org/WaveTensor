// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

// =============================================================================
// FP_AccLatticeBeat2.v — GATE V20-2 ECP5 반쪽 feasibility MEASUREMENT 전용
// beat-serial 변형 (spec §27.6 이 선공표한 ECP5 대상 형상: "beat-serialized
// 2-products/beat x 16 beats + 9-cycle serial resolve").
//
// 지위 (명시 — 오독 금지):
//   * 이것은 측정용 변형이지 출하 datapath 가 아니다. full-parallel 기본형
//     (repo root FP_AccLattice.v, golden: scripts/golden_lattice.py) 이
//     계약의 규범 RTL 이며, 본 변형은 §27.6 ECP5 실현성 측정의 대상 형상을
//     LUT/FF/Fmax 로 가격 매기기 위해 존재한다. 그래서 repo root 가 아니라
//     synth/lattice/fp_ops/ 에 산다.
//   * 산술 계약 층 (placement / 3:2 compress / RTO-48 추출 / 인코딩 / fault)
//     은 FP_AccLattice.v 의 해당 코드를 그대로 복사해 공유한다 — 측정이
//     정직하려면 기능적으로 올바른 로직을 재야 하기 때문이다. 스모크 검증:
//     tb_fp_acclattice_beat2.v 가 full-parallel 과 동일한 golden 벡터
//     (include/generated/lattice_wave_vectors.hex) 전 4001개를 beat-serial
//     스케줄로 재생해 4층 bit-exact 를 판정한다.
//
// 시퀀싱 (wave-step 1회 = 28 cycle):
//   acc beat 0..16 (17 cycle) : beat b 에 operand 쌍 (addend 2b, 2b+1);
//                               beat 16 = (bank carry-in, canonical zero).
//                               2 x placement + 5-row(3:2 x3) compress 로
//                               576-bit carry-save 상태 (s_row/c_row) 갱신.
//                               전부 exact (mod 2^576) — 순서 무관.
//   resolve 0..8    (9 cycle) : 64 bit/cycle serial carry-propagate —
//                               §27.2.1 "resolve 1회" 의 시간 전개형. 상태
//                               행은 64b 우측 shift, 몫은 res_sh 로 수집.
//   extract         (2 cycle) : S3(우선순위/CLZ/window) → S4(normalize +
//                               RTO-48 + wide/bank/fp32 인코딩) — 병렬형
//                               S3/S4 코드 그대로. done_q 1-cycle pulse.
//
// start_i 는 acc beat 0 과 같은 cycle 에 1 (operand 쌍 동시 인가). 상위가
// cycle 을 센다 — handshake 없음 (측정 top 계약).
//
// FAULT 클래스는 FP_AccLattice.v 헤더의 (a)-(f) 그대로 — wave-step 동안
// sticky 누적, done 시 fault_q 로 보고.
// =============================================================================

/* verilator lint_off UNUSEDSIGNAL */

module FP_AccLatticeBeat2 (
    input                clk,

    input                start_i,     // acc beat 0 marker (동일 cycle 인가)
    input  [63:0]        op_a_i,      // beat b: addend 2b   (beat 16: carry-in)
    input  [63:0]        op_b_i,      // beat b: addend 2b+1 (beat 16: canonical zero)

    // ---- done_q 가 1 인 cycle 에 유효 ----
    output reg [527:0]   resolved_q,
    output reg [63:0]    wide_q,
    output reg [63:0]    bank_q,
    output reg [31:0]    fp32_q,
    output reg           fault_q,
    output reg           done_q
);

    localparam [63:0] CANON_ZERO_FIELD = 64'h0400_0000_0000_0000;

    localparam [1:0] PH_IDLE = 2'd0, PH_ACC = 2'd1,
                     PH_RES  = 2'd2, PH_EXT = 2'd3;

    reg [1:0] phase = PH_IDLE;
    reg [4:0] cnt   = 5'd0;

    // =========================================================================
    // per-operand decode / fault / 배치 — FP_AccLattice.v S1a 그대로 (2 lane)
    // =========================================================================
    wire [63:0] ops [0:1];
    assign ops[0] = op_a_i;
    assign ops[1] = op_b_i;

    wire [575:0] contrib [0:1];
    wire [1:0]   neg_bit;
    wire [1:0]   op_fault;

    genvar gk, gj;
    generate
        for (gk = 0; gk < 2; gk = gk + 1) begin : g_place
            wire [63:0]        f   = ops[gk];
            wire               s   = f[59];
            wire signed [10:0] e   = f[58:48];
            wire [47:0]        sig = f[47:0];
            wire               nz  = |sig;

            // fault (a)(b)(c)
            wire bad_resv = |f[63:60];
            wire bad_zero = ~nz & (f[59:0] != {1'b0, 11'h400, 48'b0});
            wire bad_lead = nz & ~sig[47] & ~sig[46];

            // 배치 위치 q = e + 267 (PHYS LSB), k = q[9:6], o = q[5:0]
            wire signed [12:0] q_s = {{2{e[10]}}, e} + 13'sd267;
            wire bad_q = nz & ((q_s < 13'sd1) | (q_s > 13'sd528)
                               | ((q_s == 13'sd528) & sig[47]));
            wire [9:0] q = q_s[9:0];

            // static 6-stage barrel — dynamic part-select 없음
            wire [111:0] b0 = {64'b0, sig};
            wire [111:0] b1 = q[0] ? {b0[110:0],  1'b0} : b0;
            wire [111:0] b2 = q[1] ? {b1[109:0],  2'b0} : b1;
            wire [111:0] b3 = q[2] ? {b2[107:0],  4'b0} : b2;
            wire [111:0] b4 = q[3] ? {b3[103:0],  8'b0} : b3;
            wire [111:0] b5 = q[4] ? {b4[ 95:0], 16'b0} : b4;
            wire [111:0] b6 = q[5] ? {b5[ 79:0], 32'b0} : b5;

            wire [3:0] seg = q[9:6];
            wire bad_low = nz & (seg == 4'd0) & (|b6[47:0]);

            // 2-of-9 segment demux — 정적 비교 mux
            wire [63:0] segv [0:8];
            for (gj = 0; gj < 9; gj = gj + 1) begin : g_demux
                assign segv[gj] =
                    (seg == gj[3:0])          ? b6[63:0]
                  : ((seg + 4'd1) == gj[3:0]) ? {16'b0, b6[111:64]}
                  :                             64'b0;
            end

            wire [575:0] field = {segv[8], segv[7], segv[6], segv[5],
                                  segv[4], segv[3], segv[2], segv[1],
                                  segv[0]};

            wire do_neg = s & nz;
            assign contrib[gk]  = do_neg ? ~field : field;
            assign neg_bit[gk]  = do_neg;
            assign op_fault[gk] = bad_resv | bad_zero | bad_lead
                                | bad_q | bad_low;
        end
    endgenerate

    // =========================================================================
    // beat compress — 5 row {s_row, c_row, contrib0, contrib1, nrow} 를
    // 3:2 세 단으로 2 row 에 되접음 (exact, mod 2^576). nrow = 이 beat 의
    // 음수 +1 보정 (0..2) — full-parallel 의 ncnt row 를 시간 전개한 것.
    // =========================================================================
    reg  [575:0] s_row, c_row;

    wire beat0  = (phase == PH_IDLE) & start_i;
    wire acc_en = beat0 | (phase == PH_ACC);

    wire [575:0] s_in = beat0 ? 576'b0 : s_row;
    wire [575:0] c_in = beat0 ? 576'b0 : c_row;

    wire [1:0]   nsum = {1'b0, neg_bit[0]} + {1'b0, neg_bit[1]};
    wire [575:0] nrow = {574'b0, nsum};

    // c1: 3:2(contrib0, contrib1, nrow)
    wire [575:0] c1m = (contrib[0] & contrib[1]) | (contrib[0] & nrow)
                     | (contrib[1] & nrow);
    wire [575:0] c1s = contrib[0] ^ contrib[1] ^ nrow;
    wire [575:0] c1c = {c1m[574:0], 1'b0};

    // c2: 3:2(s_in, c_in, c1s)
    wire [575:0] c2m = (s_in & c_in) | (s_in & c1s) | (c_in & c1s);
    wire [575:0] c2s = s_in ^ c_in ^ c1s;
    wire [575:0] c2c = {c2m[574:0], 1'b0};

    // c3: 3:2(c2s, c2c, c1c) → 차기 carry-save 상태
    wire [575:0] c3m = (c2s & c2c) | (c2s & c1c) | (c2c & c1c);
    wire [575:0] c3s = c2s ^ c2c ^ c1c;
    wire [575:0] c3c = {c3m[574:0], 1'b0};

    // =========================================================================
    // serial resolve — 64 bit/cycle, 9 cycle (§27.6 "9-cycle serial resolve")
    // =========================================================================
    reg  [575:0] res_sh;
    reg          res_carry;

    wire [64:0] res_add = {1'b0, s_row[63:0]} + {1'b0, c_row[63:0]}
                        + {64'b0, res_carry};

    // =========================================================================
    // 제어 + sticky fault
    // =========================================================================
    reg fault_acc;

    always @(posedge clk) begin
        done_q <= 1'b0;

        if (acc_en) begin
            s_row     <= c3s;
            c_row     <= c3c;
            fault_acc <= (beat0 ? 1'b0 : fault_acc) | (|op_fault);
            if (beat0) begin
                phase <= PH_ACC;
                cnt   <= 5'd1;
            end
            else if (cnt == 5'd16) begin
                phase     <= PH_RES;
                cnt       <= 5'd0;
                res_carry <= 1'b0;
            end
            else
                cnt <= cnt + 5'd1;
        end
        else if (phase == PH_RES) begin
            res_sh    <= {res_add[63:0], res_sh[575:64]};
            s_row     <= {64'b0, s_row[575:64]};
            c_row     <= {64'b0, c_row[575:64]};
            res_carry <= res_add[64];
            if (cnt == 5'd8) begin
                phase <= PH_EXT;
                cnt   <= 5'd0;
            end
            else
                cnt <= cnt + 5'd1;
        end
        else if (phase == PH_EXT) begin
            if (cnt == 5'd0)
                cnt <= 5'd1;            // S3 capture cycle (아래 always)
            else begin
                phase  <= PH_IDLE;      // S4 capture + done (아래 always)
                cnt    <= 5'd0;
                done_q <= 1'b1;
            end
        end
    end

    // =========================================================================
    // 추출 S3 — FP_AccLattice.v S3 그대로 (lat_p2 → res_sh[575:48])
    // =========================================================================
    wire [527:0] lat_r    = res_sh[575:48];
    wire         align_ng = |res_sh[47:0];      // fault (e) resolve-후 형

    wire         lat_sign = lat_r[527];
    wire [527:0] mag      = lat_sign ? (~lat_r + 528'd1) : lat_r;
    wire [575:0] mag_ext  = {48'b0, mag};

    wire [63:0] chunk [0:8];
    wire [8:0]  ch_any;
    generate
        for (gj = 0; gj < 9; gj = gj + 1) begin : g_chunk
            assign chunk[gj]  = mag_ext[64*gj+63 : 64*gj];
            assign ch_any[gj] = |chunk[gj];
        end
    endgenerate

    reg [3:0] cs;
    always @* begin
        casez (ch_any)
            9'b1????????: cs = 4'd8;
            9'b01???????: cs = 4'd7;
            9'b001??????: cs = 4'd6;
            9'b0001?????: cs = 4'd5;
            9'b00001????: cs = 4'd4;
            9'b000001???: cs = 4'd3;
            9'b0000001??: cs = 4'd2;
            9'b00000001?: cs = 4'd1;
            default:      cs = 4'd0;
        endcase
    end
    wire mag_zero = ~|ch_any;

    reg [127:0] win;
    always @* begin
        case (cs)
            4'd0:    win = {chunk[0], 64'b0};
            4'd1:    win = {chunk[1], chunk[0]};
            4'd2:    win = {chunk[2], chunk[1]};
            4'd3:    win = {chunk[3], chunk[2]};
            4'd4:    win = {chunk[4], chunk[3]};
            4'd5:    win = {chunk[5], chunk[4]};
            4'd6:    win = {chunk[6], chunk[5]};
            4'd7:    win = {chunk[7], chunk[6]};
            default: win = {chunk[8], chunk[7]};
        endcase
    end

    wire [8:0] pre;
    assign pre[0] = ch_any[0];
    generate
        for (gj = 1; gj < 9; gj = gj + 1) begin : g_pre
            assign pre[gj] = pre[gj-1] | ch_any[gj];
        end
    endgenerate
    reg st_low;
    always @* begin
        case (cs)
            4'd0, 4'd1: st_low = 1'b0;
            4'd2:       st_low = pre[0];
            4'd3:       st_low = pre[1];
            4'd4:       st_low = pre[2];
            4'd5:       st_low = pre[3];
            4'd6:       st_low = pre[4];
            4'd7:       st_low = pre[5];
            default:    st_low = pre[6];
        endcase
    end

    wire [63:0] v0 = win[127:64];
    wire        z5 = ~|v0[63:32];
    wire [63:0] v1 = z5 ? {v0[31:0], 32'b0} : v0;
    wire        z4 = ~|v1[63:48];
    wire [63:0] v2 = z4 ? {v1[47:0], 16'b0} : v1;
    wire        z3 = ~|v2[63:56];
    wire [63:0] v3 = z3 ? {v2[55:0],  8'b0} : v2;
    wire        z2 = ~|v3[63:60];
    wire [63:0] v4 = z2 ? {v3[59:0],  4'b0} : v3;
    wire        z1 = ~|v4[63:62];
    wire [63:0] v5 = z1 ? {v4[61:0],  2'b0} : v4;
    wire        z0 = ~v5[63];
    wire [5:0]  lz = {z5, z4, z3, z2, z1, z0};

    // ---- S3 capture (PH_EXT cnt==0) ----
    reg [127:0] win_p3;
    reg [5:0]   lz_p3;
    reg [3:0]   cs_p3;
    reg         stlow_p3, sign_p3, magz_p3, fault_p3;
    reg [527:0] lat_p3;

    always @(posedge clk) begin
        if ((phase == PH_EXT) && (cnt == 5'd0)) begin
            win_p3   <= win;
            lz_p3    <= lz;
            cs_p3    <= cs;
            stlow_p3 <= st_low;
            sign_p3  <= lat_sign;
            magz_p3  <= mag_zero;
            fault_p3 <= fault_acc | align_ng;
            lat_p3   <= lat_r;
        end
    end

    // =========================================================================
    // 추출 S4 + 인코딩 — FP_AccLattice.v S4 그대로
    // =========================================================================
    wire [127:0] n0 = win_p3;
    wire [127:0] n1 = lz_p3[5] ? {n0[ 95:0], 32'b0} : n0;
    wire [127:0] n2 = lz_p3[4] ? {n1[111:0], 16'b0} : n1;
    wire [127:0] n3 = lz_p3[3] ? {n2[119:0],  8'b0} : n2;
    wire [127:0] n4 = lz_p3[2] ? {n3[123:0],  4'b0} : n3;
    wire [127:0] n5 = lz_p3[1] ? {n4[125:0],  2'b0} : n4;
    wire [127:0] n6 = lz_p3[0] ? {n5[126:0],  1'b0} : n5;

    wire [47:0] top48   = n6[127:80];
    wire        sticky  = (|n6[79:0]) | stlow_p3;
    wire [47:0] sig_rto = {top48[47:1], top48[0] | sticky};

    wire [9:0]         p_pos = {cs_p3, 6'b111111} - {4'b0, lz_p3};
    wire signed [11:0] e_w   = $signed({2'b00, p_pos}) - 12'sd266;

    wire fault_range = ~magz_p3 & (e_w == 12'sd261);

    wire [63:0] wide_w = magz_p3 ? CANON_ZERO_FIELD
                                 : {4'b0000, sign_p3, e_w[10:0], sig_rto};

    wire [10:0] e_biased = e_w[10:0] + 11'd1023;
    wire [63:0] bank_w = magz_p3 ? 64'b0
                                 : {sign_p3, e_biased, sig_rto[46:0], 5'b0};

    wire [23:0]        m24    = sig_rto[47:24];
    wire               guard  = sig_rto[23];
    wire               stk24  = |sig_rto[22:0];
    wire               rne_up = guard & (stk24 | sig_rto[24]);
    wire [24:0]        m25    = {1'b0, m24} + {24'b0, rne_up};
    wire               rcarry = m25[24];
    wire signed [12:0] e_fin  = {e_w[11], e_w} + {12'b0, rcarry};
    wire               ovf    = (e_fin >  13'sd127);
    wire               udf    = (e_fin < -13'sd126);
    wire [7:0]         biased = e_fin[7:0] + 8'd127;

    wire [31:0] fp32_w = magz_p3 ? 32'h0000_0000
                       : ovf     ? {sign_p3, 8'hFF, 23'd0}
                       : udf     ? {sign_p3, 31'd0}
                       :           {sign_p3, biased, m25[22:0]};

    // ---- S4 출력 capture (PH_EXT cnt==1 — done_q 와 같은 edge) ----
    always @(posedge clk) begin
        if ((phase == PH_EXT) && (cnt == 5'd1)) begin
            resolved_q <= lat_p3;
            wide_q     <= wide_w;
            bank_q     <= bank_w;
            fp32_q     <= fp32_w;
            fault_q    <= fault_p3 | fault_range;
        end
    end

endmodule

/* verilator lint_on UNUSEDSIGNAL */
