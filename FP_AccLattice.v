// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

// =============================================================================
// FP_AccLattice.v — v2.0 wave-step-atomic accumulation: 528-bit exact-integer
// lattice unit, 출하 microarchitecture = beat-serial (spec §27.2 normative +
// §27.2.1 말미 [amendment 2026-08-16] 블록이 출하 형상 normative; golden:
// scripts/golden_lattice.py — golden-before-RTL law).
//
// 한 wave-step (= 1 dispatch) 의 33 addend — 32 곱 + ACC bank carry-in — 를
// beat 당 PRODUCTS_PER_BEAT(=N) 개씩 NUM_BEATS(=32/N) 개 beat 에 나눠
// 인가받아 exact 정수로 누산하고, 그 wave-step 의 유일한 반올림인 RTO-48
// 추출 1회를 수행한다 (§27.2.1 "wave-step-atomic"). beat 분할은 exact 정수
// 부분합의 시간 분할일 뿐이므로 wave-step 결과는 full-parallel 시간 구조와
// bit-identical — dot 내부 반올림 0회, 순서-무관 (association-free), 반올림
// 이벤트의 수 (wave-step 당 1) 도 위치 (bank store) 도 불변 (amendment
// "수학 계약 불변" 항 — golden·4001 벡터·추출 정리 무변경 재사용).
//
// -----------------------------------------------------------------------------
// 파라미터 / 시간 계약
// -----------------------------------------------------------------------------
// PRODUCTS_PER_BEAT (기본 8): beat 당 곱 operand 수. 32 의 약수만 유효
//   (1/2/4/8/16/32 — 위반 시 sim time-0 loud $fatal; N=0/음수는 그 전에
//   part-select elaboration error 로 사망 — 어느 쪽이든 loud, silent 경로
//   없음). N=2 구성이 기존 측정
//   전용 변형 FP_AccLatticeBeat2 의 역할을 승계한다 (amendment 파라미터화 항;
//   Beat2 파일·리포트는 provenance 로 유지).
//
// NUM_BEATS = 32/N.
//   ** II = NUM_BEATS cycle ** — 연속 wave-step 은 마지막 beat 의 바로 다음
//   cycle 에 다음 start_i 를 인가할 수 있다 (resolve/추출은 다음 wave-step
//   의 beat 열과 완전 중첩되는 파이프라인 스테이지 — 아래 스테이지 표).
//   ** LATENCY = NUM_BEATS + 3 cycle ** (beat 0 인가 cycle → done_q==1 cycle).
//     N=8 (기본/출하): II = 4 @ 100 MHz 문맥 — amendment 의 계약 "II <= 8"
//                      을 2 배 여유로 충족. LATENCY = 7.
//     N=2 :            II = 16, LATENCY = 19.
//     N=32:            II = 1,  LATENCY = 4.
//
// -----------------------------------------------------------------------------
// carry-in 인가 방식 — 본 RTL 의 선택 (amendment: "RTL 이 선택하고 TB 로
// 고정"; tb_fp_acclattice.v 가 이 선택을 봉인한다)
// -----------------------------------------------------------------------------
// ** beat 0 병합 ** (별도 carry beat 없음 — II 1 beat 절약, 총 NUM_BEATS beat).
//   carry_i 는 start_i 와 같은 cycle (beat 0) 에만 샘플되며, 그 외 cycle 의
//   carry_i 값은 완전히 무시된다 (TB 는 비-beat0 cycle 에 고의 오염값을
//   인가해 이 격리를 검증한다). 구현: beat 0 에는 carry-save 상태 row 가
//   아직 0 이므로 carry-in 의 576-bit 배치 기여를 s-row 초기값 자리에, 0 을
//   c-row 자리에 주입한다 — compressor 에 인가되는 row 수는 모든 beat 에서
//   동일한 (N field + carry-save 2 + ncnt 1) = N+3 (amendment "N+2+1 rows"
//   구조) 이고, carry-in 병합의 compressor 추가 비용은 0 이다 (배치 lane
//   1개 추가가 유일한 비용).
//
// bank 인터페이스 함의 (하류 ③ bank COMMIT 이 승계·명문화할 계약):
//   * read-before-dispatch: bank 는 carry-in word 를 wave-step 의 beat 0
//     cycle 에 공급해야 한다 — bank read 는 dispatch 시점에 완료.
//   * ownership window: carry-in 은 beat 0 에서 소비 완료되므로, 같은 slot
//     에 대한 본 wave-step 의 결과 write-back (LATENCY 후) 과 read 가
//     겹치지 않는 창이 구조적으로 보장된다.
//   * 같은 slot 체이닝 (이 wave-step 의 wide 결과 = 다음 wave-step 의
//     carry-in): bank forwarding 없는 기본 계약에서 다음 start_i 는 이전
//     start_i 로부터 >= LATENCY cycle 뒤여야 한다. 서로 다른 slot 의
//     wave-step 은 II = NUM_BEATS 로 완전 중첩 가능. (이 두 간격이 상위
//     dispatch 스케줄의 입력 제약으로 등재된다 — amendment "II 계약" 항.)
//
// -----------------------------------------------------------------------------
// 인터페이스 계약 (pinned)
// -----------------------------------------------------------------------------
// beat 스케줄: beat b (= 0..NUM_BEATS-1, 연속 cycle — 중간 stall 없음) 에
//   ops_i[64j+63:64j] = addend N*b+j (j = 0..N-1, 오름차순 pin). start_i 는
//   beat 0 과 같은 cycle 에 1 (beat 1..NUM_BEATS-1 중의 start_i 는 무시 —
//   스케줄 준수는 상위 dispatch 책임). carry_i = addend 32 (bank carry-in).
//
// field 인코딩 (include/generated/lattice_vec_contract.md §2 와 동일):
//     [63:60] = 4'b0000 (예약 — 반드시 0)
//     [59]    = sign
//     [58:48] = exp — 11-bit two's complement, -1024..+1023
//     [47:0]  = sig — unsigned, unit at bit 47;  값 = (-1)^s * sig * 2^(e-47)
//   canonical zero = 64'h0400_0000_0000_0000 (sign=0, exp=-1024, sig=0) 이
//   zero 의 유일한 인코딩 (§23.10.1 / FP_AddWide.v c21092a 폐쇄와 동일 규범).
//   nonzero 는 leading zero <= 1 (sig >= 2^46 — 곱 lane raw 형식은 1-bit
//   un-normalized 허용, FP_AddWide PRECONDITIONS 동형). carry_i 는
//   normalized (sig[47]==1) 또는 canonical zero — 위반은 fault (c) 의
//   carry-lane 강화형으로 hw 검사된다 (§27.2.1 amendment pin 2, 아래
//   FAULT 클래스 (c) 항; ③ 구현 의무 이행 2026-08-16).
//
// 출력 (done_q 가 1 인 cycle 에 유효 — 다음 wave-step 의 S4 까지 유지):
//   resolved_q [527:0] : §27.2.1 resolve 결과 — exact 33-항 합의 528-bit
//                        two's complement (bit i 의 weight 2^(i-266),
//                        i=0..526; bit 527 = sign).
//   wide_q     [63:0]  : RTO-48 추출 결과 (위 field 인코딩; exact zero 합
//                        이면 canonical zero) — 그 wave-step 의 유일한
//                        반올림 (top-48 + sticky-jam = RTO_48).
//   bank_q     [63:0]  : wide_q 값의 IEEE binary64 무손실 재인코딩 (§27.2.2
//                        bank/spill word). 추출 결과의 e 는 구조상 -266..260
//                        이므로 fp64 normal 구간만 발생한다 — subnormal
//                        corner 는 bank FILL ingest 경로 (하류 ③) 전용이며
//                        본 unit 에는 도달 불가라 구현하지 않는다.
//   fp32_q     [31:0]  : 즉시-drain — PACK_FINAL 정확히 1회 RNE-24 +
//                        flush-after-round FTZ (§27.2.3). 정리
//                        RNE24(RTO48(exact)) == RNE24(exact) 에 의해 single-
//                        wave 즉시 drain 은 RNE24(exact 33-항 합) 과 bit-
//                        exact (§27.7 FDOT32_CR 불변식의 기반).
//   fault_q            : loud-fault, never-silent (project law) — 아래
//                        FAULT 클래스의 wave-step sticky OR. 합성 가능한
//                        status (sim-only assertion 금지 — §26.5 선례).
//   done_q             : 1-cycle pulse — 출력 유효 표지. 항상-흐르는 고정-
//                        latency 파이프라인 — handshake/stall/reset 없음,
//                        상위가 cycle 을 센다 (FP_AddWide.v 계약과 동형).
//
// -----------------------------------------------------------------------------
// 마이크로아키텍처 — 스테이지 의미 (§27.2.1 pin 준수)
// -----------------------------------------------------------------------------
// 물리 lattice = 576 bit = 9 segment x 64 bit (golden SEGMENT GEOMETRY pin).
// 값 비트는 PHYS[575:48] (PHYS[48] = weight 2^-266); PHYS[47:0] 은 표현성
// 전제로 항상 0 인 정렬 여유. addend 의 48-bit sig 는 LSB 를 q = e+267 에
// 두고 PHYS[q+47:q] 점유; o = q[5:0] 은 static 6-stage barrel, k = q[9:6]
// 은 segment demux — 48 <= 64 이므로 인접 <= 2 segment ("2-of-9").
// dynamic part-select 없음 — FP_AddWide.v barrel idiom 그대로.
//
//   B  (beat 스테이지 — wave-step 당 NUM_BEATS cycle):
//        per-lane field decode + 인코딩/배치 fault 검사 (per-beat — 매 beat
//        그 beat 의 lane 들을 검사, wave-step sticky 로 누적); static
//        barrel + 2-of-9 demux 로 N 개의 576-bit 기여 생성 (음수는 ones'
//        complement, +1 보정은 이 beat 의 ncnt row 로 — exact, mod 2^576);
//        (N field + carry-save 2 row + ncnt row) = N+3 row 를 3:2
//        compressor tree 로 2 row 에 되접어 s_row/c_row 갱신. beat 0 는
//        carry-save 자리에 {carry-in 기여, 0} 주입 (위 carry-in 선택).
//   R  (1 cycle): resolve — ** 병렬 1-cycle 576-bit carry-propagate 가산
//        정확히 1회 ** (§27.2.1 "resolve 1회"; GATE V20-2 에서 WNS +1.807 ns
//        로 실측 졸업한 그 구조 — amendment 가 pin). serial 9-cycle resolve
//        는 재실측에서 LUT ceiling 위협 시의 명시 fallback 이며 본 RTL 은
//        채택하지 않는다 (채택 시 II 계약의 §12a 재개정 동반 — amendment).
//        PHYS[47:0]==0 정렬 검사 (fault (e) 의 resolve-후 형). 528-bit
//        two's-complement resolve 값 등록.
//   S3 (1 cycle): 추출 전반부 — sign/magnitude (528-bit negate; resolve
//        가산과 별개인 추출 단계), 64-bit chunk 분해, coarse 우선순위
//        (최상위 nonzero chunk), 128-bit window 선택 (static 9:1 mux),
//        chunk 내 CLZ (6-stage 이진탐색 tree), window 아래 sticky 의
//        prefix-OR.
//   S4 (1 cycle): 추출 후반부 + 인코딩 — window 를 static 6-stage barrel 로
//        normalize, top-48 + sticky-jam = RTO_48; exact zero 면 canonical
//        zero; bank(fp64)/drain(fp32) 인코딩. 출력 + done_q 등록.
//
// R/S3/S4 는 각 1-cycle 점유의 파이프라인 스테이지 — 마지막 beat 직후
// cycle 에 시작하는 다음 wave-step 의 beat 열과 완전 중첩된다 (beat 0 는
// s_row/c_row 를 읽지 않으므로 — carry 주입 mux — R 이 최종 row 를 소비하는
// cycle 과 다음 wave-step 의 beat 0 이 같은 cycle 이어도 안전하다). II =
// NUM_BEATS 는 이 중첩으로 성립하며 N=32 (II=1) 에서도 구조적 hazard 가
// 없다. resolved_q 는 S3/S4 를 528-bit 그대로 관통해 출력과 정렬된다 (FF
// 비용은 V9-4 관례대로 추적만 — LUT 만이 GATE V20-2 의 hard ceiling).
//
// 곱셈기 사용 0 — 본 블록은 add/shift/compare 전용이다. premap `$mul`
// operator delta 0 이 GATE V20-2 의 pin (§27.6); 곱은 상류 lane 담당.
//
// FAULT 클래스 (전 벡터에서 0 이어야 함 — 벡터 전제조건 계약 §4; per-beat
// 검사 + wave-step sticky):
//   (a) field 예약 비트 [63:60] != 0
//   (b) sig==0 인데 canonical zero 인코딩이 아님
//   (c) nonzero sig 의 leading zero > 1 (sig < 2^46). ** carry lane
//       (lane N, beat 0 전용) 은 강화형 **: nonzero sig 의 sig[47]==0
//       이 곧 fault — carry-in 은 normalized 또는 canonical zero 만
//       (§27.2.1 amendment pin 2 의 normative 승격; 곱 lane 의 1-bit
//       un-normalized raw 허용은 불변)
//   (d) 배치 범위 밖 — q < 1 또는 q > 528, 또는 q==528 에서 sig[47]==1
//       (units >= 2^527: |v| >= 2^261, golden addend_units 의 lattice
//       range fault 와 동치 지점)
//   (e) 표현성 위반 — 배치 후 PHYS[47:0] != 0 (per-lane 형 + resolve 후
//       정렬 잔여 검사; golden 의 "precision below 2^-266" fault)
//   (f) 추출 지수 범위 밖 — e == 261 (resolve 합이 lattice 계약 범위 밖
//       이었다는 증거; golden lattice_accumulate overflow fault 대응)
// =============================================================================

/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNUSEDPARAM */
// (PHYS_W/LAT_W/II_CYC/LATENCY 는 계약 문서화 상수 — 폭 리터럴은 가독성을
//  위해 본문에 직접 쓴다. FP_AddWide.v 의 lint_off 관례와 동일.)
/* verilator lint_off PROCASSINIT */
// (reg 선언 초기값 = FPGA bitstream 초기화 관례 — 본 unit 은 계약상 reset
//  포트가 없다 (헤더 "handshake/stall/reset 없음"; FP_AccLatticeBeat2 의
//  phase 초기값과 동일 패턴). xcu55c/ECP5 두 대상 fabric 모두 지원.)

module FP_AccLattice #(
    // beat 당 곱 operand 수 — 32 의 약수 (1/2/4/8/16/32), 기본 8 (출하 형상)
    parameter integer PRODUCTS_PER_BEAT = 8
) (
    input                clk,

    input                start_i,   // beat 0 marker (같은 cycle 에 ops/carry)
    input  [PRODUCTS_PER_BEAT*64-1:0] ops_i,
                                    // beat b: addend N*b+j = ops_i[64j+63:64j]
    input  [63:0]        carry_i,   // bank carry-in — beat 0 에서만 샘플

    // ---- done_q 가 1 인 cycle 에 유효 (다음 wave-step 의 S4 까지 유지) ----
    output reg [527:0]   resolved_q,
    output reg [63:0]    wide_q,
    output reg [63:0]    bank_q,
    output reg [31:0]    fp32_q,
    output reg           fault_q,
    output reg           done_q
);

    initial done_q = 1'b0;   // power-on 확정값 (FPGA init 관례 — 위 pragma 주석)

    localparam integer N_PB    = PRODUCTS_PER_BEAT;
    localparam integer NBEATS  = 32 / N_PB;
    localparam integer ROWS0   = N_PB + 3;   // N field + carry-save 2 + ncnt 1
    localparam integer PHYS_W  = 576;        // 9 segment x 64 bit
    localparam integer LAT_W   = 528;
    localparam integer II_CYC  = NBEATS;     // 계약 문서화 (헤더 참조)
    localparam integer LATENCY = NBEATS + 3; // 계약 문서화 (헤더 참조)

    localparam [63:0] CANON_ZERO_FIELD = 64'h0400_0000_0000_0000;

    /* verilator lint_off WIDTHTRUNC */
    localparam [5:0] LAST_BCNT = NBEATS - 1;   // NBEATS-1 <= 31 — 6 bit 수납
    /* verilator lint_on WIDTHTRUNC */
    localparam       NB_IS_1   = (NBEATS == 1) ? 1'b1 : 1'b0;

    // ---- 파라미터 유효성 — loud fatal (silent 금지). initial+$fatal 이므로
    //      정확히는 sim time-0 발화다 (N=5 등 '약수 아님' 위반은 이 메시지로
    //      깨끗하게 죽는다 — iverilog·verilator 실측). N=0/음수는 이 가드
    //      이전에 lane_flat 등의 part-select elaboration error 가 먼저
    //      발화한다 — 메시지는 지저분하나 역시 loud (법칙 위반 아님). ----
    generate
        if ((PRODUCTS_PER_BEAT < 1) || (PRODUCTS_PER_BEAT > 32)
            || ((32 % PRODUCTS_PER_BEAT) != 0)) begin : g_bad_param
            initial begin
                $display("FATAL FP_AccLattice: PRODUCTS_PER_BEAT=%0d — 32 의 약수가 아님",
                         PRODUCTS_PER_BEAT);
                $fatal(1);
            end
        end
    endgenerate

    // =========================================================================
    // beat 제어 — start_i = beat 0; 이후 NUM_BEATS-1 개 beat 연속 진행.
    // 마지막 beat 직후 cycle 에 다음 start_i 허용 → II = NUM_BEATS.
    // =========================================================================
    reg       acc_active = 1'b0;    // beat 1..NUM_BEATS-1 동안 1
    reg [5:0] bcnt       = 6'd0;

    wire beat0     = start_i & ~acc_active;
    wire acc_en    = beat0 | acc_active;
    wire last_beat = beat0 ? NB_IS_1 : (bcnt == LAST_BCNT);

    always @(posedge clk) begin
        if (acc_en) begin
            if (last_beat) begin
                acc_active <= 1'b0;
                bcnt       <= 6'd0;
            end
            else begin
                acc_active <= 1'b1;
                bcnt       <= beat0 ? 6'd1 : (bcnt + 6'd1);
            end
        end
    end

    // =========================================================================
    // B-a — lane 별 decode / fault / 배치 (static barrel + 2-of-9 demux).
    // lane 0..N-1 = 이 beat 의 곱 addend, lane N = carry-in (beat 0 전용 —
    // 기여는 beat 0 의 carry-save 주입 mux 로만, fault 도 beat 0 만 계수).
    // =========================================================================
    wire [64*(N_PB+1)-1:0] lane_flat;
    assign lane_flat[64*N_PB-1:0]        = ops_i;
    assign lane_flat[64*N_PB+63:64*N_PB] = carry_i;

    wire [575:0]  contrib [0:N_PB];     // 576-bit 물리 기여 (음수는 ~field)
    wire [N_PB:0] neg_bit;              // 음수 lane — +1 보정은 ncnt row 로
    wire [N_PB:0] lane_fault;           // per-lane 인코딩/배치 fault

    genvar gk, gj, gi;
    generate
        for (gk = 0; gk <= N_PB; gk = gk + 1) begin : g_lane
            wire [63:0]        f   = lane_flat[64*gk+63 : 64*gk];
            wire               s   = f[59];
            wire signed [10:0] e   = f[58:48];
            wire [47:0]        sig = f[47:0];
            wire               nz  = |sig;

            // fault (a)(b)(c) — (c) 는 lane 별 정적 특수화: 곱 lane
            // (gk < N_PB) 은 leading zero > 1 검사 그대로 (raw 1-bit
            // un-normalized 허용), carry lane (gk == N_PB) 은 강화형 —
            // nonzero 인데 sig[47]==0 이면 곧 fault (§27.2.1 amendment
            // pin 2 이행; 발화 게이트는 기존 fault_acc 의 beat0 전용
            // carry-lane 항 그대로 — 배선 최소 변경).
            wire bad_resv = |f[63:60];
            wire bad_zero = ~nz & (f[59:0] != {1'b0, 11'h400, 48'b0});
            wire bad_lead = nz & ~sig[47]
                          & ((gk == N_PB) ? 1'b1 : ~sig[46]);

            // 배치 위치 q = e + 267 (PHYS LSB), k = q[9:6], o = q[5:0]
            wire signed [12:0] q_s = {{2{e[10]}}, e} + 13'sd267;
            // fault (d): q 범위 + q==528 에서 normalized sig (|v| >= 2^261)
            wire bad_q = nz & ((q_s < 13'sd1) | (q_s > 13'sd528)
                               | ((q_s == 13'sd528) & sig[47]));
            wire [9:0] q = q_s[9:0];

            // static 6-stage barrel: sig << o (o = q[5:0]) — 112-bit 필드.
            // FP_AddWide.v barrel idiom — dynamic part-select 없음.
            wire [111:0] b0 = {64'b0, sig};
            wire [111:0] b1 = q[0] ? {b0[110:0],  1'b0} : b0;
            wire [111:0] b2 = q[1] ? {b1[109:0],  2'b0} : b1;
            wire [111:0] b3 = q[2] ? {b2[107:0],  4'b0} : b2;
            wire [111:0] b4 = q[3] ? {b3[103:0],  8'b0} : b3;
            wire [111:0] b5 = q[4] ? {b4[ 95:0], 16'b0} : b4;
            wire [111:0] b6 = q[5] ? {b5[ 79:0], 32'b0} : b5;

            // fault (e) per-lane 형: seg 0 배치 시 PHYS[47:0] 침범
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
            assign contrib[gk]    = do_neg ? ~field : field;
            assign neg_bit[gk]    = do_neg;
            assign lane_fault[gk] = bad_resv | bad_zero | bad_lead
                                  | bad_q | bad_low;
        end
    endgenerate

    // 이 beat 의 음수 +1 보정 count — 33-slot tree popcount (미사용 slot 은
    // 상수 0 으로 소거; linear chain 금지 — 기존 tree 형태 재사용).
    // slot 32 = carry lane (beat 0 에서만 계수).
    wire [32:0] negv;
    generate
        for (gk = 0; gk < N_PB; gk = gk + 1) begin : g_negv
            assign negv[gk] = neg_bit[gk];
        end
        if (N_PB < 32) begin : g_negz
            for (gk = N_PB; gk < 32; gk = gk + 1) begin : g_z
                assign negv[gk] = 1'b0;
            end
        end
    endgenerate
    assign negv[32] = beat0 & neg_bit[N_PB];

    wire [1:0] pc3 [0:10];
    generate
        for (gi = 0; gi < 11; gi = gi + 1) begin : g_pc3
            assign pc3[gi] = {1'b0, negv[3*gi]}
                           + {1'b0, negv[3*gi+1]}
                           + {1'b0, negv[3*gi+2]};
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
    // B-b — (N+3)-row 3:2 compressor tree → 2 row (carry-save 갱신).
    // level 별 row 수는 상수 함수 f_rows_after 로 파라미터 유도; level 은
    // 각각 독립 배열 (tr0..tr8 — 기존 r0..r7 관례) 로 전개해 linear adder
    // chain 없이 tree 로 되접는다 (project law). carry row 는 <<1 (mod
    // 2^576 — 최상위 탈락은 two's-complement 모듈러 산술의 정의 그대로).
    // 수렴 (row 2) 이후의 level 은 pass-through 별칭 — 로직 비용 0.
    // beat 0: carry-save 자리에 {carry-in 기여, 0} 주입 (헤더 carry-in 선택).
    // =========================================================================
    function integer f_rows_after;
        input integer lvl;
        integer r, i;
        begin
            r = ROWS0;
            for (i = 0; i < lvl; i = i + 1)
                r = (r > 2) ? (2 * (r / 3) + (r % 3)) : r;
            f_rows_after = r;
        end
    endfunction

    localparam integer RL0 = ROWS0;
    localparam integer RL1 = f_rows_after(1);
    localparam integer RL2 = f_rows_after(2);
    localparam integer RL3 = f_rows_after(3);
    localparam integer RL4 = f_rows_after(4);
    localparam integer RL5 = f_rows_after(5);
    localparam integer RL6 = f_rows_after(6);
    localparam integer RL7 = f_rows_after(7);
    localparam integer RL8 = f_rows_after(8);   // == 2 (모든 유효 N)

    reg [575:0] s_row = 576'b0;
    reg [575:0] c_row = 576'b0;

    wire [575:0] s_in = beat0 ? contrib[N_PB] : s_row;
    wire [575:0] c_in = beat0 ? 576'b0        : c_row;
    wire [575:0] nrow = {570'b0, ncnt};

    wire [575:0] tr0 [0:RL0-1];
    wire [575:0] tr1 [0:RL1-1];
    wire [575:0] tr2 [0:RL2-1];
    wire [575:0] tr3 [0:RL3-1];
    wire [575:0] tr4 [0:RL4-1];
    wire [575:0] tr5 [0:RL5-1];
    wire [575:0] tr6 [0:RL6-1];
    wire [575:0] tr7 [0:RL7-1];
    wire [575:0] tr8 [0:RL8-1];

    generate
        for (gk = 0; gk < N_PB; gk = gk + 1) begin : g_row0
            assign tr0[gk] = contrib[gk];
        end
    endgenerate
    assign tr0[N_PB]   = nrow;
    assign tr0[N_PB+1] = s_in;
    assign tr0[N_PB+2] = c_in;

    // 3:2 reduce 1 level — 입력 RIN row 를 2*(RIN/3) + RIN%3 row 로.
    // RIN <= 2 인 level 은 pass-through (수렴 후 별칭).
    generate
        if (RL0 > 2) begin : g_t1
            for (gi = 0; gi < RL0/3; gi = gi + 1) begin : g_csa
                wire [575:0] mj = (tr0[3*gi] & tr0[3*gi+1])
                                | (tr0[3*gi] & tr0[3*gi+2])
                                | (tr0[3*gi+1] & tr0[3*gi+2]);
                assign tr1[2*gi]   = tr0[3*gi] ^ tr0[3*gi+1] ^ tr0[3*gi+2];
                assign tr1[2*gi+1] = {mj[574:0], 1'b0};
            end
            for (gi = 0; gi < RL0%3; gi = gi + 1) begin : g_pass
                assign tr1[2*(RL0/3)+gi] = tr0[3*(RL0/3)+gi];
            end
        end
        else begin : g_p1
            for (gi = 0; gi < RL0; gi = gi + 1) begin : g_k
                assign tr1[gi] = tr0[gi];
            end
        end

        if (RL1 > 2) begin : g_t2
            for (gi = 0; gi < RL1/3; gi = gi + 1) begin : g_csa
                wire [575:0] mj = (tr1[3*gi] & tr1[3*gi+1])
                                | (tr1[3*gi] & tr1[3*gi+2])
                                | (tr1[3*gi+1] & tr1[3*gi+2]);
                assign tr2[2*gi]   = tr1[3*gi] ^ tr1[3*gi+1] ^ tr1[3*gi+2];
                assign tr2[2*gi+1] = {mj[574:0], 1'b0};
            end
            for (gi = 0; gi < RL1%3; gi = gi + 1) begin : g_pass
                assign tr2[2*(RL1/3)+gi] = tr1[3*(RL1/3)+gi];
            end
        end
        else begin : g_p2
            for (gi = 0; gi < RL1; gi = gi + 1) begin : g_k
                assign tr2[gi] = tr1[gi];
            end
        end

        if (RL2 > 2) begin : g_t3
            for (gi = 0; gi < RL2/3; gi = gi + 1) begin : g_csa
                wire [575:0] mj = (tr2[3*gi] & tr2[3*gi+1])
                                | (tr2[3*gi] & tr2[3*gi+2])
                                | (tr2[3*gi+1] & tr2[3*gi+2]);
                assign tr3[2*gi]   = tr2[3*gi] ^ tr2[3*gi+1] ^ tr2[3*gi+2];
                assign tr3[2*gi+1] = {mj[574:0], 1'b0};
            end
            for (gi = 0; gi < RL2%3; gi = gi + 1) begin : g_pass
                assign tr3[2*(RL2/3)+gi] = tr2[3*(RL2/3)+gi];
            end
        end
        else begin : g_p3
            for (gi = 0; gi < RL2; gi = gi + 1) begin : g_k
                assign tr3[gi] = tr2[gi];
            end
        end

        if (RL3 > 2) begin : g_t4
            for (gi = 0; gi < RL3/3; gi = gi + 1) begin : g_csa
                wire [575:0] mj = (tr3[3*gi] & tr3[3*gi+1])
                                | (tr3[3*gi] & tr3[3*gi+2])
                                | (tr3[3*gi+1] & tr3[3*gi+2]);
                assign tr4[2*gi]   = tr3[3*gi] ^ tr3[3*gi+1] ^ tr3[3*gi+2];
                assign tr4[2*gi+1] = {mj[574:0], 1'b0};
            end
            for (gi = 0; gi < RL3%3; gi = gi + 1) begin : g_pass
                assign tr4[2*(RL3/3)+gi] = tr3[3*(RL3/3)+gi];
            end
        end
        else begin : g_p4
            for (gi = 0; gi < RL3; gi = gi + 1) begin : g_k
                assign tr4[gi] = tr3[gi];
            end
        end

        if (RL4 > 2) begin : g_t5
            for (gi = 0; gi < RL4/3; gi = gi + 1) begin : g_csa
                wire [575:0] mj = (tr4[3*gi] & tr4[3*gi+1])
                                | (tr4[3*gi] & tr4[3*gi+2])
                                | (tr4[3*gi+1] & tr4[3*gi+2]);
                assign tr5[2*gi]   = tr4[3*gi] ^ tr4[3*gi+1] ^ tr4[3*gi+2];
                assign tr5[2*gi+1] = {mj[574:0], 1'b0};
            end
            for (gi = 0; gi < RL4%3; gi = gi + 1) begin : g_pass
                assign tr5[2*(RL4/3)+gi] = tr4[3*(RL4/3)+gi];
            end
        end
        else begin : g_p5
            for (gi = 0; gi < RL4; gi = gi + 1) begin : g_k
                assign tr5[gi] = tr4[gi];
            end
        end

        if (RL5 > 2) begin : g_t6
            for (gi = 0; gi < RL5/3; gi = gi + 1) begin : g_csa
                wire [575:0] mj = (tr5[3*gi] & tr5[3*gi+1])
                                | (tr5[3*gi] & tr5[3*gi+2])
                                | (tr5[3*gi+1] & tr5[3*gi+2]);
                assign tr6[2*gi]   = tr5[3*gi] ^ tr5[3*gi+1] ^ tr5[3*gi+2];
                assign tr6[2*gi+1] = {mj[574:0], 1'b0};
            end
            for (gi = 0; gi < RL5%3; gi = gi + 1) begin : g_pass
                assign tr6[2*(RL5/3)+gi] = tr5[3*(RL5/3)+gi];
            end
        end
        else begin : g_p6
            for (gi = 0; gi < RL5; gi = gi + 1) begin : g_k
                assign tr6[gi] = tr5[gi];
            end
        end

        if (RL6 > 2) begin : g_t7
            for (gi = 0; gi < RL6/3; gi = gi + 1) begin : g_csa
                wire [575:0] mj = (tr6[3*gi] & tr6[3*gi+1])
                                | (tr6[3*gi] & tr6[3*gi+2])
                                | (tr6[3*gi+1] & tr6[3*gi+2]);
                assign tr7[2*gi]   = tr6[3*gi] ^ tr6[3*gi+1] ^ tr6[3*gi+2];
                assign tr7[2*gi+1] = {mj[574:0], 1'b0};
            end
            for (gi = 0; gi < RL6%3; gi = gi + 1) begin : g_pass
                assign tr7[2*(RL6/3)+gi] = tr6[3*(RL6/3)+gi];
            end
        end
        else begin : g_p7
            for (gi = 0; gi < RL6; gi = gi + 1) begin : g_k
                assign tr7[gi] = tr6[gi];
            end
        end

        if (RL7 > 2) begin : g_t8
            for (gi = 0; gi < RL7/3; gi = gi + 1) begin : g_csa
                wire [575:0] mj = (tr7[3*gi] & tr7[3*gi+1])
                                | (tr7[3*gi] & tr7[3*gi+2])
                                | (tr7[3*gi+1] & tr7[3*gi+2]);
                assign tr8[2*gi]   = tr7[3*gi] ^ tr7[3*gi+1] ^ tr7[3*gi+2];
                assign tr8[2*gi+1] = {mj[574:0], 1'b0};
            end
            for (gi = 0; gi < RL7%3; gi = gi + 1) begin : g_pass
                assign tr8[2*(RL7/3)+gi] = tr7[3*(RL7/3)+gi];
            end
        end
        else begin : g_p8
            for (gi = 0; gi < RL7; gi = gi + 1) begin : g_k
                assign tr8[gi] = tr7[gi];
            end
        end
    endgenerate

    // ---- beat 레지스터: carry-save 상태 + wave-step sticky fault ----
    reg fault_acc = 1'b0;

    always @(posedge clk) begin
        if (acc_en) begin
            s_row <= tr8[0];
            c_row <= tr8[1];
            // per-beat fault — 곱 lane 은 매 beat, carry lane 은 beat 0 만
            fault_acc <= (beat0 ? 1'b0 : fault_acc)
                       | (|lane_fault[N_PB-1:0])
                       | (beat0 & lane_fault[N_PB]);
        end
    end

    // =========================================================================
    // R — resolve: 병렬 1-cycle 576-bit carry-propagate 가산 정확히 1회
    // (§27.2.1; amendment 가 pin 한 실측 졸업 구조 — serial fallback 미채택).
    // 마지막 beat 직후 cycle 에 s_row/c_row 최종값을 소비한다 — 같은 cycle
    // 의 다음 wave-step beat 0 은 s/c 를 읽지 않으므로 (carry 주입 mux)
    // 중첩 안전. 정렬 검사 PHYS[47:0]==0 (fault (e) resolve-후 형).
    // resolve 값 = (S mod 2^576) >> 48 의 하위 528 bit (two's complement).
    // =========================================================================
    reg v_res = 1'b0;
    reg v_s3  = 1'b0;
    reg v_s4  = 1'b0;

    wire [575:0] phys_sum = s_row + c_row;      // mod 2^576

    reg [527:0] lat_p2;
    reg         fault_p2;

    always @(posedge clk) begin
        v_res    <= acc_en & last_beat;
        v_s3     <= v_res;
        v_s4     <= v_s3;
        lat_p2   <= phys_sum[575:48];
        fault_p2 <= fault_acc | (|phys_sum[47:0]);
    end

    // =========================================================================
    // S3 — 추출 전반부: sign/magnitude → chunk 분해 → coarse 우선순위 →
    // 128-bit window 선택 + chunk-내 CLZ (이진탐색 tree) + prefix-OR sticky
    // =========================================================================
    wire         lat_sign = lat_p2[527];
    wire [527:0] mag      = lat_sign ? (~lat_p2 + 528'd1) : lat_p2;
    wire [575:0] mag_ext  = {48'b0, mag};

    // 64-bit chunk (정적 슬라이스) + chunk 별 nonzero
    wire [63:0] chunk [0:8];
    wire [8:0]  ch_any;
    generate
        for (gj = 0; gj < 9; gj = gj + 1) begin : g_chunk
            assign chunk[gj]  = mag_ext[64*gj+63 : 64*gj];
            assign ch_any[gj] = |chunk[gj];
        end
    endgenerate

    // coarse: 최상위 nonzero chunk index (9-way 우선순위; mag==0 이면
    // cs=0 + mag_zero)
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

    // window 아래 (chunk cs-2 이하) sticky — prefix-OR 를 정적 mux 로 선택.
    // (기록: 아래 pre[] 는 9-element 선형 OR 체인 — 'linear loop 대신 tree'
    //  법칙의 자구와 표면 충돌하나, 903351c 원본 (line 404) 을 문자 그대로
    //  승계한 GATE V20-2 졸업 구조이고, 9-bit OR 는 스테이지 지배 경로
    //  (S3 의 528-bit negate) 대비 무시 가능 + 합성기가 자동 평탄화한다 —
    //  승계 선례로 기록만 남긴다.)
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
    wire [47:0] top48   = n6[127:80];
    wire        sticky  = (|n6[79:0]) | stlow_p3;
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

    // ---- S4 출력 레지스터 (v_s4 cycle 에만 갱신 — done 사이 유지) ----
    always @(posedge clk) begin
        done_q <= v_s4;
        if (v_s4) begin
            resolved_q <= lat_p3;
            wide_q     <= wide_w;
            bank_q     <= bank_w;
            fp32_q     <= fp32_w;
            fault_q    <= fault_p3 | fault_range;
        end
    end

endmodule

/* verilator lint_on UNUSEDPARAM */
/* verilator lint_on UNUSEDSIGNAL */
