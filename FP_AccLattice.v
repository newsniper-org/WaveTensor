// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

// =============================================================================
// FP_AccLattice.v — v2.0 wave-step-atomic accumulation: 528-bit exact-integer
// lattice unit (spec §27.2 normative; §27.6 하류 gate 순서 ② = GATE V20-2 의
// 대상 RTL. golden: scripts/golden_lattice.py — golden-before-RTL law).
//
// 한 wave-step (= 1 dispatch) 의 33 addend — 32 곱 + ACC bank carry-in — 를
// 정확(exact) 정수로 누산하고, 그 wave-step 의 유일한 반올림인 RTO-48 추출
// 1회를 수행한다 (§27.2.1 "wave-step-atomic"). dot 내부 반올림 0회, 따라서
// 결합 순서 개입 불가 — serial-equivalence 증명 의무의 구조적 소거 (§27.4).
//
// -----------------------------------------------------------------------------
// 인터페이스 계약 (pinned)
// -----------------------------------------------------------------------------
// 입력 addends_flat: 33 x 64-bit wide field, addend k = [64k+63 : 64k].
//   field 인코딩 (include/generated/lattice_vec_contract.md §2 와 동일):
//     [63:60] = 4'b0000 (예약 — 반드시 0)
//     [59]    = sign
//     [58:48] = exp — 11-bit two's complement, -1024..+1023
//     [47:0]  = sig — unsigned, unit at bit 47;  값 = (-1)^s * sig * 2^(e-47)
//   canonical zero = 64'h0400_0000_0000_0000 (sign=0, exp=-1024, sig=0) 이
//   zero 의 유일한 인코딩 (§23.10.1 / FP_AddWide.v c21092a 폐쇄와 동일 규범).
//   nonzero 는 leading zero <= 1 (sig >= 2^46 — 곱 lane raw 형식은 1-bit
//   un-normalized 허용, FP_AddWide PRECONDITIONS 동형). addend 32 (carry-in)
//   는 normalized (sig[47]==1) 또는 canonical zero.
//
// 출력 (전부 LATENCY(4) cycle 후 유효 — 아래 스테이지 표):
//   resolved_q [527:0] : §27.2.1 resolve 결과 — exact 33-항 합의 528-bit
//                        two's complement (bit i 의 weight 2^(i-266),
//                        i=0..526; bit 527 = sign).
//   wide_q     [63:0]  : RTO-48 추출 결과, 위 wide field 인코딩. exact zero
//                        합이면 canonical zero. 이것이 그 wave-step 의
//                        유일한 반올림 (top-48 + sticky-jam = RTO_48).
//   bank_q     [63:0]  : wide_q 값의 IEEE binary64 무손실 재인코딩
//                        (§27.2.2 bank/spill word). 추출 결과의 e 는 구조상
//                        -266..260 이므로 fp64 normal 구간만 발생한다 —
//                        subnormal corner (e=-1023/-1024) 는 bank FILL
//                        ingest 경로 (하류 gate ③) 전용이며 본 unit 에는
//                        도달 불가라 구현하지 않는다 (dead logic 회피).
//   fp32_q     [31:0]  : 즉시-drain 결과 — PACK_FINAL 정확히 1회 RNE-24 +
//                        flush-after-round FTZ (§27.2.3). 정리
//                        RNE24(RTO48(exact)) == RNE24(exact) 에 의해 single-
//                        wave 즉시 drain 은 RNE24(exact 33-항 합) 과 bit-
//                        exact (§27.7 FDOT32_CR 불변식의 기반).
//   fault_q            : loud-fault, never-silent (project law) — 아래
//                        FAULT 클래스 참조. 합성 가능한 status (sticky 화는
//                        상위 계층 몫; §26.5 선례의 sim-only assertion 금지).
//
// 항상-흐르는 고정-latency 파이프라인: handshake/stall/reset 없음 — 상위가
// cycle 을 센다 (FP_AddWide.v / PE_Core 64-bit MUL 파이프라인 계약과 동형).
//
// -----------------------------------------------------------------------------
// 마이크로아키텍처 (§27.2.1 pin 준수) — 스테이지 의미
// -----------------------------------------------------------------------------
// 물리 lattice = 576 bit = 9 segment x 64 bit (golden SEGMENT GEOMETRY pin).
// 값 비트는 PHYS[575:48] (PHYS[48] = weight 2^-266); PHYS[47:0] 은 표현성
// 전제로 항상 0 인 정렬 여유. addend 의 48-bit sig 는 LSB 를 q = e+267 에
// 두고 PHYS[q+47:q] 점유; o = q[5:0] 은 static 6-stage barrel, k = q[9:6]
// 은 segment demux — 48 <= 64 이므로 인접 <= 2 segment ("2-of-9").
// dynamic part-select 없음 — FP_AddWide.v:179-194 barrel idiom 그대로.
//
//   S1 (comb → reg): field decode + 인코딩 fault 검사; static barrel +
//        2-of-9 demux 로 576-bit 기여 생성; 음수는 ones' complement + 부호
//        count 로 처리 (33개 +1 보정을 34번째 row 하나로 합산 — exact,
//        mod 2^576); 34-row 3:2 compressor tree (8 level, linear chain
//        없음) 로 2 row 까지 압축. 등록: row_a/row_b (2x576b), fault.
//   S2 (comb → reg): resolve — 576-bit carry-propagate 가산 정확히 1회
//        (§27.2.1 "resolve 1회"). PHYS[47:0]==0 정렬 검사 (loud fault).
//        등록: 528-bit two's-complement resolve 값, fault.
//   S3 (comb → reg): 추출 전반부 — sign/magnitude (528-bit negate; resolve
//        가산과 별개인 추출 단계), 64-bit chunk 분해, coarse 우선순위
//        (최상위 nonzero chunk), 128-bit window 선택 (static 9:1 mux),
//        chunk 내 CLZ (6-stage 이진탐색 tree), window 아래 sticky 의
//        prefix-OR. 등록: window(128b)/clz/chunk index/sticky/부호 등.
//   S4 (comb → reg): 추출 후반부 + 인코딩 — window 를 static 6-stage
//        barrel 로 normalize, top-48 + sticky-jam = RTO_48; exact zero 면
//        canonical zero; bank(fp64)/drain(fp32) 인코딩. 출력 등록.
//
// resolved_q 는 S3/S4 를 528-bit 그대로 관통해 출력과 정렬된다 (FF 비용은
// V9-4 관례대로 추적만 — LUT 만이 GATE V20-2 의 hard ceiling).
//
// 곱셈기 사용 0 — 본 블록은 add/shift/compare 전용이다. premap `$mul`
// operator delta 0 이 GATE V20-2 의 pin (§27.6); 곱은 상류 lane 담당.
//
// FAULT 클래스 (전 벡터에서 0 이어야 함 — 벡터 전제조건 §4):
//   (a) field 예약 비트 [63:60] != 0
//   (b) sig==0 인데 canonical zero 인코딩이 아님
//   (c) nonzero sig 의 leading zero > 1 (sig < 2^46)
//   (d) 배치 범위 밖 — q < 1 또는 q > 528, 또는 q==528 에서 sig[47]==1
//       (units >= 2^527: |v| >= 2^261, golden addend_units 의 lattice
//       range fault 와 동치 지점)
//   (e) 표현성 위반 — 배치 후 PHYS[47:0] != 0 (per-addend + resolve 후
//       정렬 잔여 검사; golden 의 "precision below 2^-266" fault)
//   (f) 추출 지수 범위 밖 — e == 261 (resolve 합이 lattice 계약 범위 밖
//       이었다는 증거; golden lattice_accumulate overflow fault 대응)
//
// beat-serial 변형 (ECP5 feasibility, 2-products/beat x 16 beats + 9-cycle
// serial resolve) 은 §27.6 에 예고된 별도 구성이다 — 본 파일은 xcu55c 대상
// full-parallel 기본형이며, beat-serial 은 후속 wrapper 로 붙인다 (본
// 모듈의 계약 층 — 값/반올림/fault — 은 그 변형과 공유된다).
// =============================================================================

/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNUSEDPARAM */
// (PHYS_W/LAT_W/LATENCY 는 계약 문서화 상수 — 폭 리터럴은 가독성을 위해
//  본문에 직접 쓴다. FP_AddWide.v 의 lint_off 관례와 동일.)

module FP_AccLattice (
    input                clk,

    // 33 x 64-bit wide field — addend k 는 [64*k+63 : 64*k], k=0..31 이 곱,
    // k=32 가 bank carry-in (33번째 EXACT addend, §27.2.1)
    input  [33*64-1:0]   addends_flat,

    // ---- 전 출력 LATENCY(4) cycle 후 유효 ----
    output reg [527:0]   resolved_q,
    output reg [63:0]    wide_q,
    output reg [63:0]    bank_q,
    output reg [31:0]    fp32_q,
    output reg           fault_q
);

    localparam integer N_ADD  = 33;   // 32 곱 + carry-in
    localparam integer PHYS_W = 576;  // 9 segment x 64 bit
    localparam integer LAT_W  = 528;
    localparam integer LATENCY = 4;   // 상위 계층이 세는 고정 latency

    localparam [63:0] CANON_ZERO_FIELD = 64'h0400_0000_0000_0000;

    // =========================================================================
    // S1a — addend 별 decode / fault / 배치 (static barrel + 2-of-9 demux)
    // =========================================================================
    wire [575:0] contrib [0:N_ADD-1];   // 576-bit 물리 기여 (음수는 ~field)
    wire [N_ADD-1:0] neg_bit;           // 음수 addend — +1 보정은 ncnt 로 합산
    wire [N_ADD-1:0] add_fault;         // per-addend 인코딩/배치 fault

    genvar gk, gj, gi;
    generate
        for (gk = 0; gk < N_ADD; gk = gk + 1) begin : g_addend
            wire [63:0]        f   = addends_flat[64*gk+63 : 64*gk];
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
            // fault (d): q 범위 + q==528 에서 normalized sig (|v| >= 2^261)
            wire bad_q = nz & ((q_s < 13'sd1) | (q_s > 13'sd528)
                               | ((q_s == 13'sd528) & sig[47]));
            wire [9:0] q = q_s[9:0];

            // static 6-stage barrel: sig << o (o = q[5:0]) — 112-bit 필드.
            // FP_AddWide.v:179-194 idiom (좌측 shift 형) — dynamic
            // part-select 없음.
            wire [111:0] b0 = {64'b0, sig};
            wire [111:0] b1 = q[0] ? {b0[110:0],  1'b0} : b0;
            wire [111:0] b2 = q[1] ? {b1[109:0],  2'b0} : b1;
            wire [111:0] b3 = q[2] ? {b2[107:0],  4'b0} : b2;
            wire [111:0] b4 = q[3] ? {b3[103:0],  8'b0} : b3;
            wire [111:0] b5 = q[4] ? {b4[ 95:0], 16'b0} : b4;
            wire [111:0] b6 = q[5] ? {b5[ 79:0], 32'b0} : b5;

            // fault (e) per-addend 형: seg 0 에 배치될 때 PHYS[47:0] 침범
            wire [3:0] seg = q[9:6];
            wire bad_low = nz & (seg == 4'd0) & (|b6[47:0]);

            // 2-of-9 segment demux — 정적 비교 mux (하위 64 = segment k,
            // 상위 48 = segment k+1; q<=528 이므로 k+1 <= 8 또는 상위 0)
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

            // 음수 = ones' complement; +1 은 ncnt row 로 (exact, mod 2^576)
            wire do_neg = s & nz;
            assign contrib[gk]   = do_neg ? ~field : field;
            assign neg_bit[gk]   = do_neg;
            assign add_fault[gk] = bad_resv | bad_zero | bad_lead
                                 | bad_q | bad_low;
        end
    endgenerate

    // 음수 +1 보정 count — 33 x 1-bit 의 tree popcount (linear chain 금지)
    wire [1:0] pc3 [0:10];
    generate
        for (gi = 0; gi < 11; gi = gi + 1) begin : g_pc3
            assign pc3[gi] = {1'b0, neg_bit[3*gi]}
                           + {1'b0, neg_bit[3*gi+1]}
                           + {1'b0, neg_bit[3*gi+2]};
        end
    endgenerate
    wire [2:0] pcA0 = {1'b0, pc3[0]} + {1'b0, pc3[1]};
    wire [2:0] pcA1 = {1'b0, pc3[2]} + {1'b0, pc3[3]};
    wire [2:0] pcA2 = {1'b0, pc3[4]} + {1'b0, pc3[5]};
    wire [2:0] pcA3 = {1'b0, pc3[6]} + {1'b0, pc3[7]};
    wire [2:0] pcA4 = {1'b0, pc3[8]} + {1'b0, pc3[9]};
    wire [3:0] pcB0 = {1'b0, pcA0} + {1'b0, pcA1};
    wire [3:0] pcB1 = {1'b0, pcA2} + {1'b0, pcA3};
    wire [3:0] pcB2 = {1'b0, pcA4} + {2'b0, pc3[10]};
    wire [4:0] pcC0 = {1'b0, pcB0} + {1'b0, pcB1};
    wire [5:0] ncnt = {1'b0, pcC0} + {2'b0, pcB2};

    // =========================================================================
    // S1b — 34-row 3:2 compressor tree (34→23→16→11→8→6→4→3→2, 8 level).
    // carry row 는 <<1 (mod 2^576 — 최상위 탈락은 two's-complement 모듈러
    // 산술의 정의 그대로). linear adder chain 없음 — project law.
    // =========================================================================
    wire [575:0] r0 [0:33];
    generate
        for (gk = 0; gk < N_ADD; gk = gk + 1) begin : g_r0
            assign r0[gk] = contrib[gk];
        end
    endgenerate
    assign r0[33] = {570'b0, ncnt};

    wire [575:0] r1 [0:22];
    generate
        for (gi = 0; gi < 11; gi = gi + 1) begin : g_l1
            wire [575:0] a = r0[3*gi], b = r0[3*gi+1], c = r0[3*gi+2];
            wire [575:0] mj = (a & b) | (a & c) | (b & c);
            assign r1[2*gi]   = a ^ b ^ c;
            assign r1[2*gi+1] = {mj[574:0], 1'b0};
        end
    endgenerate
    assign r1[22] = r0[33];

    wire [575:0] r2 [0:15];
    generate
        for (gi = 0; gi < 7; gi = gi + 1) begin : g_l2
            wire [575:0] a = r1[3*gi], b = r1[3*gi+1], c = r1[3*gi+2];
            wire [575:0] mj = (a & b) | (a & c) | (b & c);
            assign r2[2*gi]   = a ^ b ^ c;
            assign r2[2*gi+1] = {mj[574:0], 1'b0};
        end
    endgenerate
    assign r2[14] = r1[21];
    assign r2[15] = r1[22];

    wire [575:0] r3 [0:10];
    generate
        for (gi = 0; gi < 5; gi = gi + 1) begin : g_l3
            wire [575:0] a = r2[3*gi], b = r2[3*gi+1], c = r2[3*gi+2];
            wire [575:0] mj = (a & b) | (a & c) | (b & c);
            assign r3[2*gi]   = a ^ b ^ c;
            assign r3[2*gi+1] = {mj[574:0], 1'b0};
        end
    endgenerate
    assign r3[10] = r2[15];

    wire [575:0] r4 [0:7];
    generate
        for (gi = 0; gi < 3; gi = gi + 1) begin : g_l4
            wire [575:0] a = r3[3*gi], b = r3[3*gi+1], c = r3[3*gi+2];
            wire [575:0] mj = (a & b) | (a & c) | (b & c);
            assign r4[2*gi]   = a ^ b ^ c;
            assign r4[2*gi+1] = {mj[574:0], 1'b0};
        end
    endgenerate
    assign r4[6] = r3[9];
    assign r4[7] = r3[10];

    wire [575:0] r5 [0:5];
    generate
        for (gi = 0; gi < 2; gi = gi + 1) begin : g_l5
            wire [575:0] a = r4[3*gi], b = r4[3*gi+1], c = r4[3*gi+2];
            wire [575:0] mj = (a & b) | (a & c) | (b & c);
            assign r5[2*gi]   = a ^ b ^ c;
            assign r5[2*gi+1] = {mj[574:0], 1'b0};
        end
    endgenerate
    assign r5[4] = r4[6];
    assign r5[5] = r4[7];

    wire [575:0] r6 [0:3];
    generate
        for (gi = 0; gi < 2; gi = gi + 1) begin : g_l6
            wire [575:0] a = r5[3*gi], b = r5[3*gi+1], c = r5[3*gi+2];
            wire [575:0] mj = (a & b) | (a & c) | (b & c);
            assign r6[2*gi]   = a ^ b ^ c;
            assign r6[2*gi+1] = {mj[574:0], 1'b0};
        end
    endgenerate

    wire [575:0] r7 [0:2];
    generate
        if (1) begin : g_l7
            wire [575:0] a = r6[0], b = r6[1], c = r6[2];
            wire [575:0] mj = (a & b) | (a & c) | (b & c);
            assign r7[0] = a ^ b ^ c;
            assign r7[1] = {mj[574:0], 1'b0};
        end
    endgenerate
    assign r7[2] = r6[3];

    wire [575:0] row_sum_w, row_carry_w;
    generate
        if (1) begin : g_l8
            wire [575:0] a = r7[0], b = r7[1], c = r7[2];
            wire [575:0] mj = (a & b) | (a & c) | (b & c);
            assign row_sum_w   = a ^ b ^ c;
            assign row_carry_w = {mj[574:0], 1'b0};
        end
    endgenerate

    // ---- S1 파이프라인 레지스터 ----
    reg [575:0] row_a_p1, row_b_p1;
    reg         fault_p1;

    always @(posedge clk) begin
        row_a_p1 <= row_sum_w;
        row_b_p1 <= row_carry_w;
        fault_p1 <= |add_fault;
    end

    // =========================================================================
    // S2 — resolve: 576-bit carry-propagate 가산 정확히 1회 (§27.2.1).
    // 정렬 검사 PHYS[47:0]==0 (fault (e) 의 resolve-후 형). resolve 값 =
    // (S mod 2^576) >> 48 의 하위 528 bit (two's complement).
    // =========================================================================
    wire [575:0] phys_sum = row_a_p1 + row_b_p1;    // mod 2^576

    reg [527:0] lat_p2;
    reg         fault_p2;

    always @(posedge clk) begin
        lat_p2   <= phys_sum[575:48];
        fault_p2 <= fault_p1 | (|phys_sum[47:0]);
    end

    // =========================================================================
    // S3 — 추출 전반부: sign/magnitude → chunk 분해 → coarse 우선순위 →
    // 128-bit window 선택 + chunk-내 CLZ (이진탐색 tree) + prefix-OR sticky
    // =========================================================================
    wire        lat_sign = lat_p2[527];
    wire [527:0] mag     = lat_sign ? (~lat_p2 + 528'd1) : lat_p2;
    wire [575:0] mag_ext = {48'b0, mag};

    // 64-bit chunk (정적 슬라이스) + chunk 별 nonzero
    wire [63:0] chunk [0:8];
    wire [8:0]  ch_any;
    generate
        for (gj = 0; gj < 9; gj = gj + 1) begin : g_chunk
            assign chunk[gj]  = mag_ext[64*gj+63 : 64*gj];
            assign ch_any[gj] = |chunk[gj];
        end
    endgenerate

    // coarse: 최상위 nonzero chunk index (9-way 우선순위 — FP_AddWide 의
    // 소형 priority 관용구 급; mag==0 이면 cs=0 + mag_zero)
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

    // 128-bit window = {chunk[cs], chunk[cs-1]} — 정적 9:1 mux.
    // leading bit 이 chunk[cs] 안에 있으므로 top-48 은 window 로 충분
    // (48 + 63 = 111 <= 128); window 아래는 전부 prefix-OR sticky.
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

    // window 아래 (chunk cs-2 이하) sticky — prefix-OR 를 정적 mux 로 선택
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

    // chunk[cs] 의 CLZ — 6-stage 이진탐색 (tree; linear scan 아님)
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

    // ---- S3 파이프라인 레지스터 ----
    reg [127:0] win_p3;
    reg [5:0]   lz_p3;
    reg [3:0]   cs_p3;
    reg         stlow_p3, sign_p3, magz_p3, fault_p3;
    reg [527:0] lat_p3;                 // resolved_q 정렬 관통 (FF 추적만)

    always @(posedge clk) begin
        win_p3   <= win;
        lz_p3    <= lz;
        cs_p3    <= cs;
        stlow_p3 <= st_low;
        sign_p3  <= lat_sign;
        magz_p3  <= mag_zero;
        fault_p3 <= fault_p2;
        lat_p3   <= lat_p2;
    end

    // =========================================================================
    // S4 — 추출 후반부 + 인코딩: window normalize (static 6-stage barrel) →
    // top-48 + sticky-jam = RTO_48 → wide/bank/fp32 인코딩
    // =========================================================================
    wire [127:0] n0 = win_p3;
    wire [127:0] n1 = lz_p3[5] ? {n0[ 95:0], 32'b0} : n0;
    wire [127:0] n2 = lz_p3[4] ? {n1[111:0], 16'b0} : n1;
    wire [127:0] n3 = lz_p3[3] ? {n2[119:0],  8'b0} : n2;
    wire [127:0] n4 = lz_p3[2] ? {n3[123:0],  4'b0} : n3;
    wire [127:0] n5 = lz_p3[1] ? {n4[125:0],  2'b0} : n4;
    wire [127:0] n6 = lz_p3[0] ? {n5[126:0],  1'b0} : n5;

    // RTO_48: top-48 truncate + sticky OR-jam into LSB (§27.2.1 —
    // wave-step 유일의 반올림. RNE-48 store 가 아닌 이유는 §27.2.1 의
    // directed double-rounding 반례 — b_rne48_discriminator 벡터가 적발)
    wire [47:0] top48  = n6[127:80];
    wire        sticky = (|n6[79:0]) | stlow_p3;
    wire [47:0] sig_rto = {top48[47:1], top48[0] | sticky};

    // leading-bit 위치 p = 64*cs + 63 - lz;  e = p - 266 (weight 규약)
    wire [9:0]         p_pos = {cs_p3, 6'b111111} - {4'b0, lz_p3};
    wire signed [11:0] e_w   = $signed({2'b00, p_pos}) - 12'sd266;

    // fault (f): e==261 은 |합| >= 2^261 — lattice 계약 범위 밖의 증거
    wire fault_range = ~magz_p3 & (e_w == 12'sd261);

    // ---- wide field (canonical zero 포함) ----
    wire [63:0] wide_w = magz_p3 ? CANON_ZERO_FIELD
                                 : {4'b0000, sign_p3, e_w[10:0], sig_rto};

    // ---- bank word: IEEE binary64 무손실 재인코딩 (§27.2.2) ----
    // 추출 결과의 e 는 -266..260 — fp64 normal 전용 (헤더 참조):
    //   {sign, e+1023 (11-bit biased), sig[46:0], 5'b0};  zero -> +0
    wire [10:0] e_biased = e_w[10:0] + 11'd1023;
    wire [63:0] bank_w = magz_p3 ? 64'b0
                                 : {sign_p3, e_biased, sig_rto[46:0], 5'b0};

    // ---- drain: PACK_FINAL — 정확히 1회 RNE-24, 그 후 flush-after-round
    // FTZ; overflow -> ±Inf; exact zero -> +0 (§27.2.3, A4/F4 pin).
    // FP_AddWide.v PACK_FINAL 관용구와 동형 (rcarry 시 m25[22:0] verbatim —
    // 2^24 로 오른 mantissa 의 하위 23 bit 는 이미 0).
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

    // ---- S4 출력 레지스터 ----
    always @(posedge clk) begin
        resolved_q <= lat_p3;
        wide_q     <= wide_w;
        bank_q     <= bank_w;
        fp32_q     <= fp32_w;
        fault_q    <= fault_p3 | fault_range;
    end

endmodule

/* verilator lint_on UNUSEDPARAM */
/* verilator lint_on UNUSEDSIGNAL */
