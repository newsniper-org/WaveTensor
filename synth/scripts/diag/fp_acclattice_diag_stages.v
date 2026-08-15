// DIAGNOSTIC ONLY — GATE V20-2 xcu55c LUT FAIL 귀속 실험 (출하 RTL 아님).
// FP_AccLattice.v 의 스테이지 로직을 문자 그대로 복사하되, 스테이지 경계를
// keep_hierarchy 모듈로 감싸 Vivado report_utilization -hierarchical 이
// 컴포넌트별 LUT 를 분리 보고하게 한다.
//
// 경계 규약 (fusion 왜곡 방지):
//   * placement (diag_place_one) = decode + fault + 112-bit barrel + 2-of-9
//     demux. 조건부 반전 (do_neg ? ~field : field) 은 여기 두지 않는다 —
//     출하 flat netlist 에서 그 XOR 는 tree level-1 LUT 에 흡수되므로,
//     반전은 tree 모듈 내부에서 수행해 같은 fusion 을 재현한다.
//   * diag_tree34 = 반전 + ncnt row + 34-row 3:2 compressor (8 level).
//   * diag_resolve = 576-bit CPA + 정렬검사.
//   * diag_extract = S3 (negate/chunk/priority/window/CLZ/sticky).
//   * diag_encode  = S4 (normalize barrel + RTO48 + wide/bank/fp32).
//   * diag_ternary576 = L4 실험 — 같은 34 row 를 Vivado 추론 ternary adder
//     tree (CARRY8) 로 합산했을 때의 면적 (2-level 파이프라인).
//
// 파이프라인 레지스터 경계는 출하 RTL 과 동일 (S1/S2/S3/S4).

module diag_barrel112 (
    input  [47:0]  sig,
    input  [5:0]   o,
    output [111:0] b6
);
    wire [111:0] b0 = {64'b0, sig};
    wire [111:0] b1 = o[0] ? {b0[110:0],  1'b0} : b0;
    wire [111:0] b2 = o[1] ? {b1[109:0],  2'b0} : b1;
    wire [111:0] b3 = o[2] ? {b2[107:0],  4'b0} : b2;
    wire [111:0] b4 = o[3] ? {b3[103:0],  8'b0} : b3;
    wire [111:0] b5 = o[4] ? {b4[ 95:0], 16'b0} : b4;
    assign       b6 = o[5] ? {b5[ 79:0], 32'b0} : b5;
endmodule

module diag_demux576 (
    input  [111:0] b6,
    input  [3:0]   seg,
    output [575:0] field
);
    wire [63:0] segv [0:8];
    genvar gj;
    generate
        for (gj = 0; gj < 9; gj = gj + 1) begin : g_demux
            assign segv[gj] =
                (seg == gj[3:0])          ? b6[63:0]
              : ((seg + 4'd1) == gj[3:0]) ? {16'b0, b6[111:64]}
              :                             64'b0;
        end
    endgenerate
    assign field = {segv[8], segv[7], segv[6], segv[5],
                    segv[4], segv[3], segv[2], segv[1],
                    segv[0]};
endmodule

module diag_place_one (
    input  [63:0]  f,
    output [575:0] field,
    output         neg,
    output         fault
);
    wire               s   = f[59];
    wire signed [10:0] e   = f[58:48];
    wire [47:0]        sig = f[47:0];
    wire               nz  = |sig;

    wire bad_resv = |f[63:60];
    wire bad_zero = ~nz & (f[59:0] != {1'b0, 11'h400, 48'b0});
    wire bad_lead = nz & ~sig[47] & ~sig[46];

    wire signed [12:0] q_s = {{2{e[10]}}, e} + 13'sd267;
    wire bad_q = nz & ((q_s < 13'sd1) | (q_s > 13'sd528)
                       | ((q_s == 13'sd528) & sig[47]));
    wire [9:0] q = q_s[9:0];

    wire [111:0] b6;
    (* keep_hierarchy = "yes" *) diag_barrel112 u_barrel (
        .sig(sig), .o(q[5:0]), .b6(b6));

    wire [3:0] seg = q[9:6];
    wire bad_low = nz & (seg == 4'd0) & (|b6[47:0]);

    (* keep_hierarchy = "yes" *) diag_demux576 u_demux (
        .b6(b6), .seg(seg), .field(field));

    assign neg   = s & nz;
    assign fault = bad_resv | bad_zero | bad_lead | bad_q | bad_low;
endmodule

module diag_ncnt (
    input  [32:0] neg_bit,
    output [5:0]  ncnt
);
    wire [1:0] pc3 [0:10];
    genvar gi;
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
    assign ncnt = {1'b0, pcC0} + {2'b0, pcB2};
endmodule

module diag_tree34 (
    input  [33*576-1:0] fields_flat,
    input  [32:0]       neg,
    input  [5:0]        ncnt,
    output [575:0]      row_sum,
    output [575:0]      row_carry
);
    wire [575:0] r0 [0:33];
    genvar gk, gi;
    generate
        for (gk = 0; gk < 33; gk = gk + 1) begin : g_r0
            wire [575:0] fld = fields_flat[576*gk +: 576];
            assign r0[gk] = neg[gk] ? ~fld : fld;   // 출하 RTL 의 contrib
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

    generate
        if (1) begin : g_l8
            wire [575:0] a = r7[0], b = r7[1], c = r7[2];
            wire [575:0] mj = (a & b) | (a & c) | (b & c);
            assign row_sum   = a ^ b ^ c;
            assign row_carry = {mj[574:0], 1'b0};
        end
    endgenerate
endmodule

module diag_resolve (
    input  [575:0] a,
    input  [575:0] b,
    output [527:0] lat,
    output         low_nz
);
    wire [575:0] phys_sum = a + b;      // mod 2^576
    assign lat    = phys_sum[575:48];
    assign low_nz = |phys_sum[47:0];
endmodule

module diag_extract (
    input  [527:0] lat,
    output [127:0] win_o,
    output [5:0]   lz_o,
    output [3:0]   cs_o,
    output         stlow_o,
    output         sign_o,
    output         magz_o
);
    wire         lat_sign = lat[527];
    wire [527:0] mag      = lat_sign ? (~lat + 528'd1) : lat;
    wire [575:0] mag_ext  = {48'b0, mag};

    wire [63:0] chunk [0:8];
    wire [8:0]  ch_any;
    genvar gj;
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

    assign win_o   = win;
    assign lz_o    = {z5, z4, z3, z2, z1, z0};
    assign cs_o    = cs;
    assign stlow_o = st_low;
    assign sign_o  = lat_sign;
    assign magz_o  = ~|ch_any;
endmodule

module diag_encode (
    input  [127:0] win_p3,
    input  [5:0]   lz_p3,
    input  [3:0]   cs_p3,
    input          stlow_p3,
    input          sign_p3,
    input          magz_p3,
    output [63:0]  wide_w,
    output [63:0]  bank_w,
    output [31:0]  fp32_w,
    output         fault_range
);
    localparam [63:0] CANON_ZERO_FIELD = 64'h0400_0000_0000_0000;

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

    assign fault_range = ~magz_p3 & (e_w == 12'sd261);

    assign wide_w = magz_p3 ? CANON_ZERO_FIELD
                            : {4'b0000, sign_p3, e_w[10:0], sig_rto};

    wire [10:0] e_biased = e_w[10:0] + 11'd1023;
    assign bank_w = magz_p3 ? 64'b0
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

    assign fp32_w = magz_p3 ? 32'h0000_0000
                  : ovf     ? {sign_p3, 8'hFF, 23'd0}
                  : udf     ? {sign_p3, 31'd0}
                  :           {sign_p3, biased, m25[22:0]};
endmodule

// L4 실험 — 같은 34 row 를 Vivado 추론 ternary adder tree 로 (CARRY8 매핑).
// 2단 파이프라인 (levelA 후 + levelB 후) — 면적 측정 목적.
module diag_ternary576 (
    input               clk,
    input  [33*576-1:0] fields_flat,
    input  [32:0]       neg,
    input  [5:0]        ncnt,
    output reg [575:0]  total_q
);
    wire [575:0] r0 [0:33];
    genvar gk, gi;
    generate
        for (gk = 0; gk < 33; gk = gk + 1) begin : g_r0
            wire [575:0] fld = fields_flat[576*gk +: 576];
            assign r0[gk] = neg[gk] ? ~fld : fld;
        end
    endgenerate
    assign r0[33] = {570'b0, ncnt};

    // level A: 34 → 12  (11x ternary + 1 passthrough), mod 2^576
    reg [575:0] tA [0:11];
    generate
        for (gi = 0; gi < 11; gi = gi + 1) begin : g_tA
            always @(posedge clk)
                tA[gi] <= r0[3*gi] + r0[3*gi+1] + r0[3*gi+2];
        end
    endgenerate
    always @(posedge clk) tA[11] <= r0[33];

    // level B: 12 → 4
    reg [575:0] tB [0:3];
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_tB
            always @(posedge clk)
                tB[gi] <= tA[3*gi] + tA[3*gi+1] + tA[3*gi+2];
        end
    endgenerate

    // level C: 4 → 2 → 1 (ternary + binary, 한 cycle)
    wire [575:0] tC = tB[0] + tB[1] + tB[2];
    always @(posedge clk) total_q <= tC + tB[3];
endmodule

module fp_acclattice_diag_stages_top (
    input                clk,
    input  [33*64-1:0]   addends_flat,
    output reg [527:0]   resolved_q,
    output reg [63:0]    wide_q,
    output reg [63:0]    bank_q,
    output reg [31:0]    fp32_q,
    output reg           fault_q,
    output     [575:0]   ternary_o
);
    // 입력 1회 등록 (gate_top 관례)
    reg [33*64-1:0] add_q;
    always @(posedge clk) add_q <= addends_flat;

    // ---- S1: placement x33 + ncnt + tree ----
    wire [33*576-1:0] fields_flat;
    wire [32:0]       negb, pfault;
    genvar gk;
    generate
        for (gk = 0; gk < 33; gk = gk + 1) begin : g_place
            (* keep_hierarchy = "yes" *) diag_place_one u_place (
                .f     (add_q[64*gk +: 64]),
                .field (fields_flat[576*gk +: 576]),
                .neg   (negb[gk]),
                .fault (pfault[gk]));
        end
    endgenerate

    wire [5:0] ncnt;
    (* keep_hierarchy = "yes" *) diag_ncnt u_ncnt (
        .neg_bit(negb), .ncnt(ncnt));

    wire [575:0] row_sum_w, row_carry_w;
    (* keep_hierarchy = "yes" *) diag_tree34 u_tree (
        .fields_flat(fields_flat), .neg(negb), .ncnt(ncnt),
        .row_sum(row_sum_w), .row_carry(row_carry_w));

    reg [575:0] row_a_p1, row_b_p1;
    reg         fault_p1;
    always @(posedge clk) begin
        row_a_p1 <= row_sum_w;
        row_b_p1 <= row_carry_w;
        fault_p1 <= |pfault;
    end

    // ---- S2: resolve ----
    wire [527:0] lat_w;
    wire         lownz_w;
    (* keep_hierarchy = "yes" *) diag_resolve u_resolve (
        .a(row_a_p1), .b(row_b_p1), .lat(lat_w), .low_nz(lownz_w));

    reg [527:0] lat_p2;
    reg         fault_p2;
    always @(posedge clk) begin
        lat_p2   <= lat_w;
        fault_p2 <= fault_p1 | lownz_w;
    end

    // ---- S3: extract ----
    wire [127:0] win_w;
    wire [5:0]   lz_w;
    wire [3:0]   cs_w;
    wire         stlow_w, sign_w, magz_w;
    (* keep_hierarchy = "yes" *) diag_extract u_extract (
        .lat(lat_p2), .win_o(win_w), .lz_o(lz_w), .cs_o(cs_w),
        .stlow_o(stlow_w), .sign_o(sign_w), .magz_o(magz_w));

    reg [127:0] win_p3;
    reg [5:0]   lz_p3;
    reg [3:0]   cs_p3;
    reg         stlow_p3, sign_p3, magz_p3, fault_p3;
    reg [527:0] lat_p3;
    always @(posedge clk) begin
        win_p3   <= win_w;
        lz_p3    <= lz_w;
        cs_p3    <= cs_w;
        stlow_p3 <= stlow_w;
        sign_p3  <= sign_w;
        magz_p3  <= magz_w;
        fault_p3 <= fault_p2;
        lat_p3   <= lat_p2;
    end

    // ---- S4: encode ----
    wire [63:0] wide_w, bank_w;
    wire [31:0] fp32_w;
    wire        frange_w;
    (* keep_hierarchy = "yes" *) diag_encode u_encode (
        .win_p3(win_p3), .lz_p3(lz_p3), .cs_p3(cs_p3),
        .stlow_p3(stlow_p3), .sign_p3(sign_p3), .magz_p3(magz_p3),
        .wide_w(wide_w), .bank_w(bank_w), .fp32_w(fp32_w),
        .fault_range(frange_w));

    always @(posedge clk) begin
        resolved_q <= lat_p3;
        wide_q     <= wide_w;
        bank_q     <= bank_w;
        fp32_q     <= fp32_w;
        fault_q    <= fault_p3 | frange_w;
    end

    // ---- L4 실험 (본 파이프라인과 분리 집계) ----
    (* keep_hierarchy = "yes" *) diag_ternary576 u_x_ternary (
        .clk(clk), .fields_flat(fields_flat), .neg(negb), .ncnt(ncnt),
        .total_q(ternary_o));

endmodule
