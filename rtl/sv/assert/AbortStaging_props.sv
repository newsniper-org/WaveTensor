// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// AbortStaging 후-formal 하네스 — 정본 E.12.1 「무장 비트 다섯 항」의 측정.
//
// ## 왜 이 하네스가 존재하는가
//
// 2026-08-25 결정 A 의 요점은 「발화 전 부분 기입 무효과」와 「stale staging
// 부재」를 *ABI 의무에서 기계가 강제하는 속성으로* 옮기는 것이다. 옮겼다는
// 주장은 재기 전까지 주장일 뿐이므로, 이 파일이 그 주장을 기계 검증한다.
// 재지 않으면 결정의 절반만 이행한 것이다.
//
// ## 부착 방식 — bind 가 아니라 *래퍼*다 (이 하네스만 다르다)
//
// 다른 하네스는 bind 를 쓰고 sby 스크립트가 그것을 텍스트 전개한다 (yosys
// 개방판이 bind 를 조용히 무시하기 때문 — 공허 PASS 의 원천). 여기서는 그
// 전개가 필요 없다: 대상이 담긴 Wt64Top.sv 는 모듈 스물을 담은 파일이라
// 「첫 endmodule 앞에 주입」 관용구가 *어느* 모듈에 주입될지를 파일 순서에
// 맡기게 되고, 그 순서는 SpinalHDL 생성기가 정한다 — 계약이 아닌 것에 하네스
// 부착을 매다는 형태다.
//
// 대신 이 검사자가 대상을 **직접 인스턴스**한다. 그러려면 단언이 보는 것이
// 전부 포트여야 하고, 실제로 그렇다 — 무장 마스크는 정본이 요구하는 RO
// 관측면(`0xF58` ABORT_ARM)이고 스테이징 값은 io_tag 로 나간다. 즉 이 하네스는
// *호스트가 볼 수 있는 것만* 본다. 내부 신호를 안 보는 것이 제약이 아니라
// 이 계약의 성질이다: E.12.1 은 호스트 대면 계약이다.
//
// 그래서 sby 는 `prep -top AbortStaging_check` 하나로 끝난다 (bind 없음 ·
// 텍스트 전개 없음 · 공허 위장 없음 — 단언이 top 모듈 본문에 산다).
//
// 문체: yosys 개방판은 SVA 시퀀스를 받지 않으므로 즉시 단언(always+$past).
module AbortStaging_check (
  input logic        clk,
  input logic        reset,
  input logic        io_wr,
  input logic        io_selTag0,
  input logic        io_selTag1,
  input logic        io_selTag2,
  input logic        io_selFire,
  input logic [31:0] io_wdata
);

  // ── 리셋 규율 ────────────────────────────────────────────────────────
  // ENV: 기계는 리셋에서 시작한다 (무장 0 · 스테이징 0). 이 하네스의 유일한
  // assume 이다 — 상위 디코더가 보장하는 「한 접근은 한 워드」조차 assume 으로
  // 넣지 않는다 (아래 참조).
  initial assume (reset);

  logic f_past_valid = 1'b0;
  logic f_past_reset = 1'b1;
  always @(posedge clk) begin
    f_past_valid <= 1'b1;
    f_past_reset <= reset;
  end
  wire f_step = f_past_valid && !reset && !f_past_reset;

  wire        io_badWrite;
  wire [2:0]  io_armed;
  wire        io_fire;
  wire [31:0] io_tag_wave;
  wire [3:0]  io_tag_epoch;
  wire        io_tag_poison;
  wire        io_tag_trace;
  wire [15:0] io_tag_lnid;
  wire [7:0]  io_tag_precision;
  wire [7:0]  io_tag_dim;

  AbortStaging dut (
    .io_wr(io_wr), .io_selTag0(io_selTag0), .io_selTag1(io_selTag1),
    .io_selTag2(io_selTag2), .io_selFire(io_selFire), .io_wdata(io_wdata),
    .io_badWrite(io_badWrite), .io_armed(io_armed), .io_fire(io_fire),
    .io_tag_wave(io_tag_wave), .io_tag_epoch(io_tag_epoch),
    .io_tag_poison(io_tag_poison), .io_tag_trace(io_tag_trace),
    .io_tag_lnid(io_tag_lnid), .io_tag_precision(io_tag_precision),
    .io_tag_dim(io_tag_dim),
    .clk(clk), .reset(reset)
  );

  // 워드 선택은 *자유*로 둔다 — 상위 디코더가 배타를 보장하지만 그것을 여기서
  // assume 으로 깔면 「배타가 깨진 세계에서 이 계약이 무너지는가」를 묻지
  // 못한다. 아래 단언은 전부 배타를 *가정하지 않고* 성립한다 (여러 sel 이
  // 동시에 서도 무장은 각자 서고, 발화 sel 이 함께 서면 잔류 소진이 이긴다).
  //
  // 수락/거절의 문면 — 상위와 같은 마스크. 값을 다시 적지 않고 관측 가능한
  // io_badWrite 와 함께 쓴다.
  // TAG1 의 거절 = [27:16] poison·trace·예약 — 처분은 셋 다 같다 (E.1.2 0xF44 · E.12 6항).
  // 적재 필드는 [31:28] 에포크 ‖ [15:0] LNID. 스레드‖LNID 코덱을 여기 적지 않는다.
  wire tag1_rsv_bad = ((io_wdata & 32'h0fff0000) != 32'h0);
  wire tag2_rsv_bad = ((io_wdata & 32'hffff0000) != 32'h0);
  wire fire_rsv_bad = ((io_wdata & 32'hfffffffe) != 32'h0);
  wire ok_tag0 = io_wr && io_selTag0;
  wire ok_tag1 = io_wr && io_selTag1 && !tag1_rsv_bad;
  wire ok_tag2 = io_wr && io_selTag2 && !tag2_rsv_bad;
  wire ok_fire = io_wr && io_selFire && !fire_rsv_bad;

  // ═══ 조합 단언 ═══════════════════════════════════════════════════════
  always @(*) if (!reset) begin
    // ── E.12.1 2항 — 발화의 성립 조건 ────────────────────────────────
    //
    // 「무장 셋이 모두 선 상태에서만」. 이것이 결정 A 의 심장이며, 이 한 줄이
    // 「발화 전의 부분 기입은 효과가 없다」를 *기계가 강제하는* 형태로 만든다.
    p_fire_needs_armed: assert (!io_fire || (io_armed == 3'b111));

    // 발화의 나머지 전건 전수 — 발화 워드의 수락된 기입에 [0]=1 이어야 한다.
    // 등식이 아니라 함의 넷으로 적는 이유: 「이것들이 없으면 발화하지 않는다」
    // 가 계약이고, 역은 계약이 아니다 (stagedRsvBad 이중 방어가 하나 더 있다).
    p_fire_needs_word:  assert (!io_fire || (io_wr && io_selFire));
    p_fire_needs_bit0:  assert (!io_fire || io_wdata[0]);
    p_fire_needs_ok:    assert (!io_fire || !fire_rsv_bad);

    // ── 「부분 기입 무효과」의 문면 ──────────────────────────────────
    //
    // 태그 워드 기입만으로는 아무것도 발화하지 않는다. 위 셋의 귀결이지만
    // 계약의 *문장 그대로*를 따로 세운다 — 다음 사람이 이 파일에서 찾는 것은
    // 「부분 기입은 효과가 없다」이지 그 분해가 아니다.
    p_partial_no_effect: assert (!(io_wr && (io_selTag0 || io_selTag1 || io_selTag2)
                                          && !io_selFire) || !io_fire);

    // ── E.12.1 2항 후단 — 무장 미완 발화는 *무시*이지 거절이 아니다 ──
    //
    // badWrite(거절된 구성 기입 = loud fault [6])는 예약 비트 축에서만 선다.
    // 무장 상태는 그 판정에 들어가지 않는다 — 들어가면 「무시」가 「거절」로
    // 접히고 E.12 3항과 같은 처분이라는 문장이 거짓이 된다.
    p_arm_miss_not_bad: assert (io_badWrite ==
                                ((io_wr && io_selTag1 && tag1_rsv_bad) ||
                                 (io_wr && io_selTag2 && tag2_rsv_bad) ||
                                 (io_wr && io_selFire && fire_rsv_bad)));

    // ── E.12.1 5항에 대해: 여기에 단언을 두지 않는다 ───────────────────
    //
    // 한동안 `p_arm_width: assert ((io_armed & ~3'b111) == 3'b000)` 가
    // 있었다. io_armed 이 3비트 포트이므로 이것은 **상수 참**이고 yosys 가
    // 접는다 — 실측: design_prep.il 에 `cell $assert \p_arm_width /
    // connect \A 1'1`. 단언 셀은 세어지므로 공허 게이트를 통과하고 증명도
    // 통과하는데 아무것도 재지 않는다. *셀 수로는 잡히지 않는 공허의 셋째
    // 결*이며, 전수 검증이 셀의 A 입력을 훑어 잡았다.
    //
    // 5항 전단(무장은 태그 *값*을 검사하지 않는다)은 아래 t_arm_set_* 가
    // 잰다 — 수락된 기입이면 값과 무관하게 자기 무장이 선다 (증인 W8 — 에포크
    // 비0 의 TAG1 이 수락되어 무장한다). t_arm_src_* 는 상승의 *원천*만 잰다:
    // 값에 따라 무장을 *안* 세우는 장치(검토 N6 — 에포크 비0 이면 무장 없음)는
    // t_arm_src 를 통과하고 t_arm_set_1 에만 걸린다. 후단(스테이징된 태그를 관측면에 내지 않는다)은 이
    // 모듈 밖 Wt64Top 조립의 성질이고 그 *조립 국소 경로*는 Wt64Top/assembly.sby
    // 가 잰다 — Reassembly 경유 잔여는 rtl/README 「미측정」 절에 남는다.
  end

  // ═══ 전이 단언 ═══════════════════════════════════════════════════════
  always @(posedge clk) if (f_step) begin
    // ── E.12.1 3항 — 잔류 소진 ────────────────────────────────────────
    //
    // 발화 워드의 수락된 기입은 *성립 여부와 무관하게* 무장 셋을 전부 내린다.
    // $past(io_fire) 를 전건에 넣지 않는 것이 요점이다 — 넣으면 「성공한
    // 소거만 무장을 내린다」가 되고 stale staging 이 되살아난다.
    t_arm_cleared_on_fire: assert (!$past(ok_fire) || (io_armed == 3'b000));

    // 그 귀결: 소거 하나마다 세 워드를 다시 기입해야 한다. 발화 직후 사이클에
    // 무장이 완비일 수 없다 — 「어제 반쯤 실어 둔 태그가 오늘의 발화에
    // 실린다」가 구조적으로 표현 불가라는 문장의 관측형.
    t_no_stale_staging: assert (!$past(ok_fire) || !io_fire);

    // ── E.12.1 1항 — 무장 비트 상승의 원천은 자기 워드의 수락된 기입뿐 ──
    //
    // 등식이 아니라 「상승 → 원천」 함의로 적는다 (하강 원천은 위 잔류 소진이
    // 따로 잰다). 셋을 따로 적는 이유는 「한 워드의 기입이 다른 워드의 무장을
    // 세운다」가 이 축의 대표 결함형이기 때문이다 — 그 결함형은 등식 하나로
    // 뭉뚱그리면 어느 비트가 샜는지를 말해 주지 않는다.
    t_arm_src_0: assert (!(io_armed[0] && !$past(io_armed[0])) || $past(ok_tag0));
    t_arm_src_1: assert (!(io_armed[1] && !$past(io_armed[1])) || $past(ok_tag1));
    t_arm_src_2: assert (!(io_armed[2] && !$past(io_armed[2])) || $past(ok_tag2));

    // ── E.12.1 1항 전단의 *양의 방향* — 수락된 기입은 자기 무장을 세운다 ──
    //
    // 위 t_arm_src_* 는 「상승 → 원천」뿐이라 「무장이 서야 할 때 서는가」를
    // 재지 않았다. 그 방향은 증인 W1 만 쟀고, 실측으로 「TAG1 이 무장을 안
    // 세우는」 변이가 bmc·prove 를 통과하고 cover 만 떨어졌다 (검토자 V13 —
    // 선-formal AbortSurface.arm_on_accept 의 삭제 run 이 그 결함형이다).
    // 같은 사이클의 수락된 발화 기입이 이기는 것은 잔류 소진 규약이다
    // (선택 신호가 자유라 배타를 가정하지 않는다).
    t_arm_set_0: assert (!$past(ok_tag0 && !ok_fire) || io_armed[0]);
    t_arm_set_1: assert (!$past(ok_tag1 && !ok_fire) || io_armed[1]);
    t_arm_set_2: assert (!$past(ok_tag2 && !ok_fire) || io_armed[2]);

    // 무장 비트의 *하강* 원천은 수락된 발화 기입뿐이다 — 거절된 발화 기입
    // (예약 [31:1] 비0)은 무장을 내리지 않는다 (AbortSurface.legal_first 의
    // 발화 쪽 절반 · 모델 머리 「정본 문면이 닫지 않은 자리」 1). 스테이징
    // 기입·거절된 스테이징 기입도 무장을 내리지 않는다 — 모델 고정 속성
    // Prop_ArmFallsOnlyOnFire (「닫지 않은 자리」 4) 의 RTL 판이다.
    t_arm_fall: assert (!(|($past(io_armed) & ~io_armed)) || $past(ok_fire));

    // 거절된 스테이징 기입은 무장을 세우지 않는다 (E.12.1 1항 후단) — 실물은 두 축이다:
    // TAG1 [27:16] poison·trace·예약 (E.12 6항) · TAG2 [31:16] 예약.
    t_arm1_not_on_reject: assert (!$past(io_wr && io_selTag1 && tag1_rsv_bad && !io_selFire)
                                  || (io_armed[1] == $past(io_armed[1])));
    t_arm2_not_on_reject: assert (!$past(io_wr && io_selTag2 && tag2_rsv_bad && !io_selFire)
                                  || (io_armed[2] == $past(io_armed[2])));

    // ── 「부분 기입 무효과」의 상태 축 — 스테이징 값의 안정 ────────────
    //
    // 태그 워드는 *자기* 워드의 수락된 기입에서만 움직인다. 이 셋이 없으면
    // 「발화 전의 부분 기입은 효과가 없다」의 절반(효과가 *다른* 워드에
    // 새는 것)이 재어지지 않는다. 관측은 호스트 대면 io_tag 로 한다 —
    // 스테이징 레지스터가 아니라 그것이 나가는 값이 계약이다.
    t_tag0_hold: assert ($past(ok_tag0) || (io_tag_wave == $past(io_tag_wave)));
    t_tag1_hold: assert ($past(ok_tag1) ||
                         ((io_tag_epoch  == $past(io_tag_epoch))  &&
                          (io_tag_poison == $past(io_tag_poison)) &&
                          (io_tag_trace  == $past(io_tag_trace))  &&
                          (io_tag_lnid   == $past(io_tag_lnid))));
    t_tag2_hold: assert ($past(ok_tag2) ||
                         ((io_tag_precision == $past(io_tag_precision)) &&
                          (io_tag_dim       == $past(io_tag_dim))));

    // 「같은 워드의 재기입은 값을 덮되」(E.12.1 1항) — 수락된 기입 뒤 그 워드의
    // 스테이징 값은 쓴 값이다. 무장이 이미 선 워드의 재기입도 같다 (증인 W10).
    // TAG1 은 *워드 전량*의 왕복이다 — 호스트 대면 두 포트를 이어 붙인 32b 가 쓴
    // 워드와 같다 — 코덱이 E.5.1 재배분을 실은 뒤(태그 코덱 전파 파도)의 포트는
    // 에포크 · poison · trace · LNID 이고 예약 [25:16] 은 번들에 없어 0 으로 잇는다.
    // 파도 4 착지판은 LNID [15:0] 만 재서 「에포크를 떨군다」 · 「재기입이 옛 에포크를
    // 남긴다」 두 변이가 bmc · prove 를 통과했다 (검토 N1 · N2 — props.sby 역-변이 표).
    // 수락된 TAG1 은 [27:16] = 0 이라 그 자리도 0 으로 잰다. 그리고 코덱이 필드를 갖게 된
    // 지금 필드별 단언을 더한다 (t_tag1_epoch · a_tag_pt_zero — 아래).
    t_tag0_val: assert (!$past(ok_tag0) || (io_tag_wave == $past(io_wdata)));
    t_tag1_val: assert (!$past(ok_tag1) || ({io_tag_epoch, io_tag_poison, io_tag_trace, 10'd0, io_tag_lnid} == $past(io_wdata)));
    // 필드별 — 에포크는 [31:28] 에서 온다 (코덱의 필드 자리가 E.5.1 과 어긋나면 반례).
    t_tag1_epoch: assert (!$past(ok_tag1) || (io_tag_epoch == $past(io_wdata[31:28])));
    t_tag2_val: assert (!$past(ok_tag2) || ({io_tag_precision, io_tag_dim} == $past(io_wdata[15:0])));

    // 소거가 싣는 태그의 poison · trace 는 *언제나* 0 이다 (E.1.2 0xF44 · E.12 6항) —
    // 스테이징은 [27:26] 비0 을 거절하고 reset 값이 0 이라, 이것은 수락 기입만이 TAG1 을
    // 움직인다는 사실의 불변식 형태다. Reassembly 의 소거 매칭이 두 비트를 키에서 빼야 하는
    // 이유가 이 등식이다 (Payload.key_drops_side — 소거는 0 을 싣고 문맥은 1 일 수 있다).
    a_tag_pt_zero: assert (!io_tag_poison && !io_tag_trace);

    // 발화는 스테이징을 *소비하지 않는다* — 값은 그대로 남고 무장만 내려간다.
    // (남는 것이 문제가 아니다: 무장이 0 이라 다시 실리지 않는다. 이 단언이
    //  그 두 사실을 함께 못박는다 — t_arm_cleared_on_fire 와 짝이다.)
    t_fire_keeps_value: assert (!$past(ok_fire && !io_selTag0 && !io_selTag1 && !io_selTag2)
                                || (io_tag_wave == $past(io_tag_wave)));
  end

  // ── cover 증인 — 공허 아님의 증거 ──────────────────────────────────────
  //
  // 위 단언은 전부 함의라 「발화가 한 번도 안 일어나는 세계」에서 자명하게
  // 선다 — p_fire_needs_armed 가 특히 그렇다. 아래 증인이 reset 으로부터
  // 실제로 세 워드가 실리고, 무장이 차고, 발화가 나고, 잔류가 소진되는
  // 궤적을 보인다.
  //   ※ sby 의 cover 모드는 chformal -assert -remove 로 단언을 스스로
  //     떼어낸다. 증인이 적법 궤적 위에 있다는 것은 bmc 태스크가 보증한다.
`ifdef ABORTSTG_COVER
  // W1 ← AbortSurface.arm_on_accept · AbortSurface.arm_own_word · p_fire_needs_armed ·
  //      t_arm_src_0 · t_arm_src_1 · t_arm_src_2 · t_arm_set_0 · t_arm_set_1 · t_arm_set_2
  //      무장이 실제로 완비된다 (세 워드가 다 실린다). 이것 없이는
  //      p_fire_needs_armed 가 전건 거짓으로 공허하다.
  always @(posedge clk) if (f_step) w1_armed_full: cover (io_armed == 3'b111);

  // W2 ← AbortSurface.fire_needs_one · p_fire_needs_ok · p_fire_needs_bit0 · p_fire_needs_word ·
  //      t_arm_cleared_on_fire · t_fire_keeps_value
  //      발화가 실제로 난다 (결정 A 가 「엄격한 축소」라는 주장의 활성면:
  //      올바른 호스트 시퀀스는 무장 규율 아래에서도 그대로 동작한다).
  always @(posedge clk) if (f_step) w2_fire: cover (io_fire);

  // W3 ← AbortSurface.fire_needs_armed · p_fire_needs_armed · p_partial_no_effect
  //      *무장 미완 발화*가 실제로 도달한다 — 즉 이 규율이 실제로 막는
  //      일이 있다. 없으면 무장 게이트는 한 번도 일하지 않은 장식이다.
  always @(posedge clk)
    if (f_step) w3_fire_underarmed: cover (io_wr && io_selFire && !fire_rsv_bad && io_wdata[0]
                       && (io_armed != 3'b111));

  // W4 ← p_arm_miss_not_bad · p_partial_no_effect
  //      그 미완 발화가 *fault 를 세우지 않는다* (무시이지 거절이 아니다 —
  //      E.12 3항과 같은 처분이라는 문장의 활성면).
  always @(posedge clk)
    if (f_step) w4_fire_underarmed_quiet: cover (io_wr && io_selFire && !fire_rsv_bad && io_wdata[0]
                       && (io_armed != 3'b111) && !io_badWrite);

  // W5 ← AbortSurface.fire_drains_arm · t_arm_cleared_on_fire · t_no_stale_staging · t_fire_keeps_value
  //      잔류 소진이 실제로 관측된다: 무장 완비 상태에서 발화 워드를 쓰고
  //      다음 사이클에 무장이 0 이다.
  always @(posedge clk)
    if (f_step) w5_arm_drained: cover ($past(ok_fire) && $past(io_armed) == 3'b111 && io_armed == 3'b000);

  // W6 ← AbortSurface.shape_word_rsv_strict · AbortSurface.legal_first · AbortSurface.reject_loud ·
  //      t_arm2_not_on_reject · t_tag2_hold
  //      거절된 스테이징 기입(TAG2 예약 비0)이 실제로 도달한다 —
  //      t_arm2_not_on_reject 의 전건.
  always @(posedge clk) if (f_step) w6_tag2_reject: cover (io_wr && io_selTag2 && tag2_rsv_bad);

  // W7 ← AbortSurface.poison_trace_zero · AbortSurface.epoch_word_rsv_strict · AbortSurface.legal_first ·
  //      AbortSurface.reject_loud · t_arm1_not_on_reject · t_tag1_hold · p_arm_miss_not_bad
  //      거절된 TAG1 기입이 사유마다 실제로 도달한다 — [27] poison 단독 · [26] trace 단독 ·
  //      [25:16] 예약 단독. 셋이 따로 서야 한 사유만 빠뜨린 마스크가 증인 쪽에서도 드러난다.
  always @(posedge clk) if (f_step) w7_tag1_rej_poison: cover (io_wr && io_selTag1 && io_wdata[27:16] == 12'h800);
  always @(posedge clk) if (f_step) w7_tag1_rej_trace:  cover (io_wr && io_selTag1 && io_wdata[27:16] == 12'h400);
  always @(posedge clk) if (f_step) w7_tag1_rej_rsv:    cover (io_wr && io_selTag1 && io_wdata[27:26] == 2'b00 && io_wdata[25:16] != 10'd0);

  // W8 ← AbortSurface.arm_on_accept · t_arm_src_1 · t_arm_set_1 · t_tag1_val · p_arm_miss_not_bad
  //      에포크 [31:28] 비0 의 TAG1 기입은 수락되어 무장을 세운다 — 거절 마스크가 에포크를 삼키지 않는다.
  always @(posedge clk) if (f_step) w8_tag1_epoch_arms: cover ($past(ok_tag1 && io_wdata[31:28] != 4'd0 && !io_selFire) && io_armed[1]);
  // W9 ← AbortSurface.fire_rsv_strict · AbortSurface.legal_first · t_arm_fall · p_fire_needs_ok
  //      무장이 선 동안 예약 [31:1] 비0 의 발화 기입이 온다 — 거절이라 무장을 내리지 않는다
  //      (t_arm_fall 의 전건 · 모델 Witness_NoRejectedDrain 의 RTL 판).
  always @(posedge clk) if (f_step) w9_fire_rsv_armed: cover (io_wr && io_selFire && fire_rsv_bad && io_armed != 3'b000);

  // W10 ← AbortSurface.stage_writes_value · t_tag0_val
  //       무장이 이미 선 워드에 다른 값의 수락된 재기입이 온다 (「값을 덮되 비트는 선 채다」 —
  //       모델 Witness_NoRewrite 의 RTL 판).
  always @(posedge clk) if (f_step) w10_tag0_rewrite: cover (ok_tag0 && io_armed[0] && io_wdata != io_tag_wave);

  // W11 ← AbortSurface.fire_needs_one · p_fire_needs_bit0
  //       무장 완비 상태에 [0]=0 의 수락된 발화 기입이 온다 — 발화 없이 무장만 내린다
  //       (모델 Witness_NoZeroFire 의 RTL 판).
  always @(posedge clk) if (f_step) w11_fire_zero_full: cover (ok_fire && !io_wdata[0] && io_armed == 3'b111);

  // W12 ← AbortSurface.fire_drains_arm · t_arm_cleared_on_fire
  //       무장 미완(0 아님)의 발화가 무시되면서도 무장을 전부 내린다 — 「성립 여부와 무관하게」의
  //       활성면. 「성립한 소거만 내린다」 결함은 이 궤적에서만 드러난다.
  always @(posedge clk)
    if (f_step) w12_ignored_fire_drains: cover ($past(ok_fire && io_wdata[0] && io_armed != 3'b111 && io_armed != 3'b000)
                                                && io_armed == 3'b000);
`endif // ABORTSTG_COVER

endmodule
