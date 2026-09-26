// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// FabricMerge 후-formal 하네스 (§6.3) — bind 로 rtl/generated/FabricMerge.sv 에 부착.
//
// 선-formal 모델 rtl/formal/tla/Fabric.tla 가 검사한 계약을, 구현된 회로에
// 대해 같은 속성으로 다시 잰다. 도구: yosys + sby (BMC + k-귀납), 솔버 z3
// 단독. 각 속성 위에 FabricMerge.scala 의 GUARD-MAP 과 같은 가드명을 적는다.
//
// 형상 (rtl/generated/FabricMerge.sv 기준): N = 4 lane, D = 1 (cnt 1비트),
// 페이로드 폭 W = 151 = body 64 + last 1 + total 8 + seq 8 + dim 8 +
// precision 8 + lnid 16 + trace 1 + poison 1 + epoch 4 + wave 32 (태그 코덱 전파
// 파도 — 옛 스레드 ID 16 이 에포크 · poison · trace 로 갈렸고 예약 10 은 번들에
// 없다). 아래 모든 151비트 연접은 merge_contribs_* 와 같은 순서 {body, last,
// total, seq, dim, precision, lnid, epoch, poison, trace, wave} 로 통일한다 — 순서 자체는 임의고, face·push·payload
// 세 연접이 같은 순서라는 것만이 비교의 전제다.
//
// 주의 1: yosys(비-Verific)의 SVA 부분집합에 맞춰 시퀀스 연산자 없이
// 즉시 단언 + $past 로만 쓴다. 공정성 카운터는 하네스의 모델링 상태다.
//
// 주의 2 (부착 방식 — 실측): OSS yosys(0.64·0.66, Verific 없음)는 bind 를
// **파싱만 하고 조용히 적용하지 않는다** (SBY 문서도 bind 를 Verific 기능
// 으로 분류한다. 상류 tests/bind/ 는 .ys 종료 코드만 보므로 이 무시를 잡지
// 못한다 — 본 저장소에서 module-scope·top-scope·.* 전 형태 실측 확인).
// 그래서 이 파일은 두 갈래다:
//   - 기본 (bind 지원 도구): 파일 끝의 bind 문이 규약대로 부착한다.
//   - FABRICMERGE_EXPOSE_FLOW (sby/yosys 흐름): sby 스크립트가 yosys
//     `expose` 로 내부 신호를 포트로 승격한 뒤, 아래 FabricMerge_formal
//     래퍼가 같은 결선을 손으로 잇는다. 결선 내용은 bind 문과 1:1 동일.

module FabricMerge_props (
  input wire         clk,
  input wire         reset,
  // 외부 인터페이스
  input wire         fault,
  input wire         faultClear,
  input wire         consumer_valid,
  input wire         consumer_ready,
  input wire         fire,             // io_consumer_fire = valid && ready
  input wire [150:0] consumer_pay,     // io_consumer_payload 연접
  input wire [3:0]   strb,             // io_push_i_strb
  input wire [3:0]   stall,            // io_push_i_stall
  input wire [150:0] push_pay_0,       // io_push_i_result 연접
  input wire [150:0] push_pay_1,
  input wire [150:0] push_pay_2,
  input wire [150:0] push_pay_3,
  // lane 내부 상태 (버스면 face = slots(0), 점유 cnt — D = 1 이라 1비트)
  input wire [150:0] face_0,
  input wire [150:0] face_1,
  input wire [150:0] face_2,
  input wire [150:0] face_3,
  input wire [3:0]   cnt,              // lanes_i_cnt (D=1: 비트 = 값)
  input wire [3:0]   full,
  input wire [3:0]   vld,
  input wire [3:0]   doPush,
  input wire [3:0]   doPop,
  input wire [3:0]   shove,
  // 선택 규칙 내부 상태
  input wire [3:0]   req,
  input wire [3:0]   ptrOh,
  input wire [3:0]   lockedOh,
  input wire         locked,
  input wire [3:0]   selOh,
  input wire [3:0]   drive,
  input wire         shoveAny
);

  // 배열화 — generate 루프에서 인덱스로 접근하기 위한 내부 결선.
  wire [150:0] push_pay [0:3];
  wire [150:0] face     [0:3];
  assign push_pay[0] = push_pay_0;  assign push_pay[1] = push_pay_1;
  assign push_pay[2] = push_pay_2;  assign push_pay[3] = push_pay_3;
  assign face[0] = face_0;  assign face[1] = face_1;
  assign face[2] = face_2;  assign face[3] = face_3;

`ifdef FABRICMERGE_COVER_CONTRACTS
  // ── 증인용 관측 결선 (cover 태스크에서만 컴파일) ─────────────────────────
  //
  // f_rival(i) — lane i 가 「요청을 든 채로 구동은 못 하고, 자기 face 에
  // 버스와 *다른* 비0 값을 들고 있는」 상태. FAB-9 의 반례 형상이 정확히
  // 이것이다: 게이팅이 빠지면 이 비트들이 OR 병합에 실려 소비자가 어느
  // 생산자도 보내지 않은 값을 받는다. 이 상태가 도달 가능해야
  // `if (drive[gi]) assert (consumer_pay == face[gi])` 가 「경쟁자가 없는
  // 세계」의 자명한 등식이 아니게 된다.
  wire [3:0] f_rival;
  assign f_rival[0] = req[0] && !drive[0] && (|face_0) && (face_0 != consumer_pay);
  assign f_rival[1] = req[1] && !drive[1] && (|face_1) && (face_1 != consumer_pay);
  assign f_rival[2] = req[2] && !drive[2] && (|face_2) && (face_2 != consumer_pay);
  assign f_rival[3] = req[3] && !drive[3] && (|face_3) && (face_3 != consumer_pay);
`endif

`ifndef FABRICMERGE_NO_FAIR
`ifdef FABRICMERGE_COVER_FAIR
  // lane 지역 공정성 카운터의 모듈 축 사영 (증인 전용 — 위 사유 참조).
  wire [2:0] f_wait [0:3];
`endif
`endif

  // ── 리셋 규약 (하네스 기반 시설 — 유일한 전역 assume) ────────────────
  //
  // 근거: 선-formal 모델의 Init 은 리셋 직후 상태다. 생성 SV 의 레지스터는
  // initial 값이 없고 비동기 리셋으로만 초기화되므로, 시각 0 에 리셋을 한
  // 사이클 인가하고 이후 내리는 표준 리셋 프로토콜을 가정한다. 리셋이
  // 임의 시점에 재인가되는 경우는 검사 범위 밖(모델에도 없음)이다.
  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;
  always @(*) begin
    if (!f_past_valid) assume (reset);
    else               assume (!reset);
  end

  always @(posedge clk) begin
    if (f_past_valid && !reset) begin

      // ── Fabric.single_producer (FAB-1) ────────────────────────────────
      // 사이클당 버스를 구동하는 생산자 ≤ 1. drive = selOh & req ⊆ selOh
      // 이므로 selOh 의 one-hot 성이 전제 축이다. 아래 네 불변식은
      // k-귀납을 닫기 위한 보조 불변식이면서 그 자체가 설계의 참 속성이다.
      assert ($onehot(ptrOh));                 // 우선순위 포인터는 항상 one-hot
      assert ($onehot0(lockedOh));             // 포획 레지스터는 one-hot 또는 0
      assert (!locked || $onehot(lockedOh));   // 잠금 중이면 정확히 one-hot
      assert ($onehot0(selOh));                // 선택 = 라운드로빈 산출 or 포획
      assert ($onehot0(drive));                // 구동 집합 ≤ 1 — 가드 본문

      // ── Fabric.valid_gated (FAB-9 — 이 파도의 심장) ───────────────────
      // 병합 결과가 구동자 face 와 비트 단위로 정확히 일치한다. 비구동
      // lane 의 face 에 남은 낡은 값이 한 비트라도 실렸다면 등식이 깨진다
      // — "drove 하나인데 merged 에 남의 비트" 반례가 회로에 없음의 증명.
      // 소비자 valid 는 구동 집합 비공백과 동치다 (§2.3 규범 2항).
      assert (consumer_valid == (drive != 4'b0000));

      // ── Fabric.fault_raised ───────────────────────────────────────────
      // shove 사이클의 클록 에지에 상태 비트가 선다 — faultClear 가 같은
      // 사이클에 와도 set 이 이긴다 (§2.6 함정 요구 1).
      if ($past(shoveAny)) assert (fault);

      // ── Fabric.fault_sticky ───────────────────────────────────────────
      // 세운 비트는 io.faultClear 외의 어떤 동작으로도 내려가지 않는다 —
      // 특히 배압 해제(ready 상승)는 여기 결선돼 있지 않다 (§2.6 함정
      // 요구 2). ready·strb 전 조합에 대해 성립해야 통과한다.
      if ($past(fault && !faultClear)) assert (fault);

      // ── Fabric.bp_no_consumer_write (FAB-10) ──────────────────────────
      // 배압(valid ∧ ¬ready) 동안 소비자 관측면은 얼어 있다 — valid 는
      // 유지되고 페이로드는 비트 단위로 불변이다 (§2.6 규범 5항). shove
      // 가 그동안 일어나도 쓰이는 것은 fault 비트 하나뿐이다.
      if ($past(consumer_valid && !consumer_ready)) begin
        assert (consumer_valid);
        assert (consumer_pay == $past(consumer_pay));
      end

    end
  end

  // ── lane 단위 속성 ──────────────────────────────────────────────────────
  genvar gi;
  generate for (gi = 0; gi < 4; gi = gi + 1) begin : g_lane

    always @(posedge clk) begin
      if (f_past_valid && !reset) begin

        // ── Fabric.valid_gated (FAB-9) — lane 축 ────────────────────────
        // lane gi 가 구동 중이면 소비자 페이로드 == 그 lane 의 face. 등식
        // (⊇ 아님)이므로 다른 lane 의 기여가 0 임까지 함께 담는다.
        if (drive[gi]) assert (consumer_pay == face[gi]);

        // ── Fabric.valid_tracks_data ────────────────────────────────────
        // (1) vld 상승의 유일한 원인은 doPush 다 — 데이터 없이 valid 만
        //     서는 경로가 없다 (§2.3 결과 방향 규율 1).
        if (vld[gi] && !$past(vld[gi])) assert ($past(doPush[gi]));
        // (2) 그 doPush 사이클에 face 가 밀어넣은 값으로 쓰인다 — valid
        //     는 데이터와 함께 선다. (D=1 이라 쓰기 자리는 항상 slots(0).)
        if ($past(doPush[gi])) assert (face[gi] == $past(push_pay[gi]));

        // ── Fabric.capture_atomic (FAB-5) ───────────────────────────────
        // pop 과 소비자 수락(ready/valid 완결)은 같은 사건이다 — 「떠났는데
        // 도착 안 함」 상태가 상태 공간에 없다 (§2.6 규범 3항).
        // (1) pop ⊆ 그 사이클의 수락 ∧ 그 lane 의 구동.
        assert (!doPop[gi] || (consumer_valid && consumer_ready && drive[gi]));
        // (2) 점유 감소의 유일한 원인은 수락된 핸드오프다.
        if (!cnt[gi] && $past(cnt[gi])) assert ($past(drive[gi] && fire));
        // (3) 수락된 핸드오프는 실제로 점유를 내린다 (D=1: doPush 는 full
        //     이 아닐 때만이라 drive[gi]∧fire 와 같은 사이클에 doPush 불가).
        if ($past(drive[gi] && fire)) assert (!cnt[gi]);

        // ── Fabric.stall_on_pending ─────────────────────────────────────
        // (1) full 이 io.push(i).stall 로 그대로 수출된다 (§2.6 규범 2항).
        assert (stall[gi] == full[gi]);
        // (2) full 사이클에는 어떤 쓰기도 face 에 닿지 않는다 — 가득 찬
        //     출력 자원 덮어쓰기 경로 부재 (pop 동반 여부와 무관: doPush
        //     는 사이클 시작의 full 로 게이트된다).
        if ($past(full[gi])) assert (face[gi] == $past(face[gi]));
        // (3) pop 없이는 점유도 그대로다 — 조용한 소실 없음.
        if ($past(full[gi] && !doPop[gi])) assert (full[gi]);

        // ── Fabric.bp_loud ──────────────────────────────────────────────
        // 배압(stall) 무시 밀어넣기(strb ∧ stall = shove)는 조용한 소실이
        // 아니라 loud fault 처분을 받는다 (§2.6 규범 4항). 데이터가 자원에
        // 닿지 않음은 stall_on_pending (2) 가 이미 덮는다.
        if ($past(strb[gi] && stall[gi])) assert (fault);

      end
    end


`ifndef FABRICMERGE_NO_FAIR
    // ── Fabric.fair_grant (FAB-6) — 유계 공정성, BMC 전용 ────────────────
    // 라운드로빈: fire 마다 ptrOh 가 방금 서비스된 lane 의 다음으로 돈다.
    // 요청을 지속하는 lane 은 최대 N(=4) grant 안에 반드시 선택된다 —
    // 즉 요청 유지 중 「grant 를 받지 못한 채 지나보낸 fire」는 N-1(=3) 회
    // 를 넘지 못한다. 카운터는 하네스의 모델링 상태다 (설계 상태 아님).
    // k-귀납은 카운터-포인터 거리 결합 불변식 없이는 닫히지 않으므로
    // 계획대로 BMC 로만 잰다 (fairness.sby, 깊이 ≥ 2N).
    reg [2:0] wait_fires = 3'd0;
    always @(posedge clk) begin
      if (reset || !req[gi])   wait_fires <= 3'd0;   // 요청 끊김 → 관측 리셋
      else if (fire) begin
        if (drive[gi])         wait_fires <= 3'd0;   // grant 받음
        else                   wait_fires <= wait_fires + 3'd1;
      end
    end
    always @(posedge clk)
      if (f_past_valid && !reset) assert (wait_fires <= 3'd3);

`ifdef FABRICMERGE_COVER_FAIR
    // 증인은 모듈 축으로 내보낸다 (아래 `endgenerate` 뒤). yosys 는 generate
    // 블록 이름으로 단언 라벨을 한정하지 않아 같은 라벨이 lane 마다 생성되면
    // 충돌한다 (실측: `Cannot add procedural assertion … already created`).
    // 그래서 lane 지역 상태인 이 카운터만 모듈 축 배열로 사영한다.
    assign f_wait[gi] = wait_fires;
`endif // FABRICMERGE_COVER_FAIR
`endif

  end endgenerate

`ifdef FABRICMERGE_COVER_CONTRACTS
  // ── lane 축 cover 증인 (계약 축 — 「병합 충돌이 실제로 일어나는가」) ──────
  //
  // 위 lane 단언 열 개 중 **아홉이 전건을 가진 함의**다. 전건이 도달
  // 불가능하면 그 단언은 공허하게 참이고, 셀 수 게이트도 상수 접힘 검사도
  // 그것을 잡지 못한다 (`!전건 || 후건` 의 \A 는 전건이 죽어 있어도 상수로
  // 접히지 않는다). 아래 증인이 그 결을 닫는다 — 각 줄의 `←` 오른쪽이 그
  // 증인이 살리는 대상이고(`<Model>.<guard>` 는 이 태스크의 `# PROVES:`
  // 앵커), 인용은 하네스 문면 그대로다. **줄번호로 매지 않는다** — 줄번호
  // 매인 참조가 밀려 상수가 되는 것이 이 저장소가 이미 밟은 공허의 둘째
  // 결이다. scripts/lint_witness_map.py 가 참조 실재성만 재고 「그 궤적이
  // 정말 그 전건을 세우는가」는 재지 못한다.
  //
  // 증인은 lane 마다 따로 선다. 「어느 한 lane 이 구동한다」로 뭉치면
  // 라운드로빈이 특정 lane 에 영영 닿지 못하는 세계를 배제하지 못하고,
  // 그 lane 의 전건 붙은 단언 아홉은 그대로 공허하다.
  //
  // **왜 generate 밖에서 손으로 네 번 펴는가 (실측 사유)**: yosys 0.66 은
  // generate 블록 이름으로 단언 라벨을 한정하지 않는다 — 같은 라벨이 lane
  // 마다 생성되면 `Cannot add procedural assertion … already created` 로
  // 죽는다. 라벨이 없으면 yosys 가 `check_cover_<파일>_<줄>_<id>` 로 이름을
  // 짓고(실측), 그 **줄번호 매인 이름**이 증거에 남으면 무관한 편집마다
  // 증인 이름이 통째로 갈린다 — 공허 둘째 결의 증거층 판이다. 셀 수는
  // 종전과 같다 (lane 8 × 4 = 32).
  wire f_ok_c = f_past_valid && !reset;

  // WL1 ← Fabric.valid_gated
  //       `if (drive[i]) assert (consumer_pay == face[i])` (FAB-9 lane 축)
  //       lane i 가 실제로 버스를 구동하고 그 face 가 비0 이다. face 가
  //       늘 0 이면 등식은 0 == 0 으로 아무것도 재지 않는다.
  // WL2 ← Fabric.valid_gated
  //       같은 단언의 **충돌면**. lane i 가 구동 중인데 다른 lane 이 버스와
  //       다른 비0 face 를 들고 나란히 요청 중이다 — 게이팅이 빠졌다면 바로
  //       반례가 되는 그 형상이 도달 가능하다는 증거.
  // WL3 ← Fabric.valid_tracks_data
  //       `if (vld[i] && !$past(vld[i])) assert ($past(doPush[i]))` ① —
  //       vld 상승이 실제로 일어난다.
  // WL4 ← Fabric.valid_tracks_data
  //       `if ($past(doPush[i])) assert (face[i] == $past(push_pay[i]))` ② —
  //       비0 페이로드로 밀어넣는다. 0 만 흐르는 세계에서는 이 등식도 0 == 0.
  // WL5 ← Fabric.capture_atomic
  //       `assert (!doPop[i] || (consumer_valid && consumer_ready && drive[i]))`
  //       ① 의 전건 doPop[i].
  // WL6 ← Fabric.capture_atomic
  //       ② `if (!cnt[i] && $past(cnt[i])) …` 와 ③ `if ($past(drive[i] && fire))
  //       …` 의 전건. 둘은 같은 사건의 앞뒤 면이라 증인 하나로 묶는다.
  // WL7 ← Fabric.stall_on_pending · Fabric.bp_loud
  //       ① `assert (stall[i] == full[i])` · ② `if ($past(full[i])) assert
  //       (face[i] == $past(face[i]))` · bp_loud `if ($past(strb[i] &&
  //       stall[i])) assert (fault)` 셋의 공통 활성면: 자원이 가득 찬 채로
  //       **실제 쓰기 시도**를 받는다. full 이 도달 불가능하면 ① 은 0 == 0,
  //       ② 는 「아무도 안 쓰는데 안 변한다」, bp_loud 는 통째로 공허하다.
  // WL8 ← Fabric.stall_on_pending
  //       ③ `if ($past(full[i] && !doPop[i])) assert (full[i])` 의 전건 —
  //       pop 없는 full 구간이 실제로 존재한다.
  always @(posedge clk) if (f_ok_c) wl1_l0: cover (drive[0] && (|face[0]));
  always @(posedge clk) if (f_ok_c) wl2_l0: cover (drive[0] && (f_rival != 4'b0000));
  always @(posedge clk) if (f_ok_c) wl3_l0: cover (vld[0] && !$past(vld[0]));
  always @(posedge clk) if (f_ok_c) wl4_l0: cover ($past(doPush[0] && (|push_pay[0])));
  always @(posedge clk) if (f_ok_c) wl5_l0: cover (doPop[0]);
  always @(posedge clk) if (f_ok_c)
    wl6_l0: cover (!cnt[0] && $past(cnt[0]) && $past(drive[0] && fire));
  always @(posedge clk) if (f_ok_c) wl7_l0: cover ($past(full[0] && strb[0]));
  always @(posedge clk) if (f_ok_c) wl8_l0: cover ($past(full[0] && !doPop[0]));
  always @(posedge clk) if (f_ok_c) wl1_l1: cover (drive[1] && (|face[1]));
  always @(posedge clk) if (f_ok_c) wl2_l1: cover (drive[1] && (f_rival != 4'b0000));
  always @(posedge clk) if (f_ok_c) wl3_l1: cover (vld[1] && !$past(vld[1]));
  always @(posedge clk) if (f_ok_c) wl4_l1: cover ($past(doPush[1] && (|push_pay[1])));
  always @(posedge clk) if (f_ok_c) wl5_l1: cover (doPop[1]);
  always @(posedge clk) if (f_ok_c)
    wl6_l1: cover (!cnt[1] && $past(cnt[1]) && $past(drive[1] && fire));
  always @(posedge clk) if (f_ok_c) wl7_l1: cover ($past(full[1] && strb[1]));
  always @(posedge clk) if (f_ok_c) wl8_l1: cover ($past(full[1] && !doPop[1]));
  always @(posedge clk) if (f_ok_c) wl1_l2: cover (drive[2] && (|face[2]));
  always @(posedge clk) if (f_ok_c) wl2_l2: cover (drive[2] && (f_rival != 4'b0000));
  always @(posedge clk) if (f_ok_c) wl3_l2: cover (vld[2] && !$past(vld[2]));
  always @(posedge clk) if (f_ok_c) wl4_l2: cover ($past(doPush[2] && (|push_pay[2])));
  always @(posedge clk) if (f_ok_c) wl5_l2: cover (doPop[2]);
  always @(posedge clk) if (f_ok_c)
    wl6_l2: cover (!cnt[2] && $past(cnt[2]) && $past(drive[2] && fire));
  always @(posedge clk) if (f_ok_c) wl7_l2: cover ($past(full[2] && strb[2]));
  always @(posedge clk) if (f_ok_c) wl8_l2: cover ($past(full[2] && !doPop[2]));
  always @(posedge clk) if (f_ok_c) wl1_l3: cover (drive[3] && (|face[3]));
  always @(posedge clk) if (f_ok_c) wl2_l3: cover (drive[3] && (f_rival != 4'b0000));
  always @(posedge clk) if (f_ok_c) wl3_l3: cover (vld[3] && !$past(vld[3]));
  always @(posedge clk) if (f_ok_c) wl4_l3: cover ($past(doPush[3] && (|push_pay[3])));
  always @(posedge clk) if (f_ok_c) wl5_l3: cover (doPop[3]);
  always @(posedge clk) if (f_ok_c)
    wl6_l3: cover (!cnt[3] && $past(cnt[3]) && $past(drive[3] && fire));
  always @(posedge clk) if (f_ok_c) wl7_l3: cover ($past(full[3] && strb[3]));
  always @(posedge clk) if (f_ok_c) wl8_l3: cover ($past(full[3] && !doPop[3]));
`endif // FABRICMERGE_COVER_CONTRACTS

`ifndef FABRICMERGE_NO_FAIR
`ifdef FABRICMERGE_COVER_FAIR
  // ── 공정성 축 cover 증인 (「기아 직전 상태에 도달하는가」) ────────────────
  //
  // 위 단언(`wait_fires <= 3`)은 전건이 없다 — 그래서 계약 축과 도달성 질문이
  // 다르다. 여기서 공허를 만드는 것은 죽은 전건이 아니라 **죽은 카운터**다:
  // wait_fires 가 0 을 벗어나지 못하면 `<= 3` 은 폭(3비트)이 이미 허용하는
  // 값 위의 느슨한 상한일 뿐이고, N=4 라운드로빈에 대해 아무것도 재지 않는다.
  // 게다가 카운터는 `!req[i]` 로도 0 으로 되돌아가므로, lane i 가 **영영
  // grant 를 못 받고 요청만 끊기는** 세계에서도 상계는 성립한다. 그 두
  // 세계를 배제하는 것이 아래 넷이다. (lane 별로 손수 편 사유는 위 계약 축
  // 블록의 「왜 generate 밖에서」 절과 같다.)
  //
  // WF1 ← Fabric.fair_grant — 증가 경로의 활성면: lane i 가 요청을 든 채로
  //       *남의* grant 를 지나본다. 이것이 도달 불가능하면 카운터는 영영 0 이다.
  // WF2 ← Fabric.fair_grant — **상계가 빡빡하다**: 허용 최댓값 3 에 실제로
  //       닿는다. 1 까지밖에 못 가면 `<= 3` 은 N-1 이라는 문면을 재지 못한 것이다.
  // WF3 ← Fabric.fair_grant — **기아 배제의 알맹이**: 0 이 아닌 대기에서
  //       *grant 로* 카운터가 내려간다. 요청 철회(!req)에 의한 리셋과 구별되지
  //       않으면, 이 lane 이 한 번도 선택되지 않는 궤적 위에서도 상계는 참이다.
  // WF4 ← Fabric.fair_grant — 상계 바로 그 지점에서의 해방: wait_fires = 3 인
  //       사이클의 fire 가 lane i 를 고른다. WF2(도달)와 WF3(grant 로 해제)를
  //       한 궤적에 겹쳐 「N-1 을 넘기지 않고 반드시 선택된다」를 보인다.
  always @(posedge clk) if (f_past_valid && !reset)
    wf1_l0: cover (req[0] && fire && !drive[0]);
  always @(posedge clk) if (f_past_valid && !reset)
    wf2_l0: cover (f_wait[0] == 3'd3);
  always @(posedge clk) if (f_past_valid && !reset)
    wf3_l0: cover (req[0] && fire && drive[0] && (f_wait[0] != 3'd0));
  always @(posedge clk) if (f_past_valid && !reset)
    wf4_l0: cover ((f_wait[0] == 3'd3) && req[0] && fire && drive[0]);
  always @(posedge clk) if (f_past_valid && !reset)
    wf1_l1: cover (req[1] && fire && !drive[1]);
  always @(posedge clk) if (f_past_valid && !reset)
    wf2_l1: cover (f_wait[1] == 3'd3);
  always @(posedge clk) if (f_past_valid && !reset)
    wf3_l1: cover (req[1] && fire && drive[1] && (f_wait[1] != 3'd0));
  always @(posedge clk) if (f_past_valid && !reset)
    wf4_l1: cover ((f_wait[1] == 3'd3) && req[1] && fire && drive[1]);
  always @(posedge clk) if (f_past_valid && !reset)
    wf1_l2: cover (req[2] && fire && !drive[2]);
  always @(posedge clk) if (f_past_valid && !reset)
    wf2_l2: cover (f_wait[2] == 3'd3);
  always @(posedge clk) if (f_past_valid && !reset)
    wf3_l2: cover (req[2] && fire && drive[2] && (f_wait[2] != 3'd0));
  always @(posedge clk) if (f_past_valid && !reset)
    wf4_l2: cover ((f_wait[2] == 3'd3) && req[2] && fire && drive[2]);
  always @(posedge clk) if (f_past_valid && !reset)
    wf1_l3: cover (req[3] && fire && !drive[3]);
  always @(posedge clk) if (f_past_valid && !reset)
    wf2_l3: cover (f_wait[3] == 3'd3);
  always @(posedge clk) if (f_past_valid && !reset)
    wf3_l3: cover (req[3] && fire && drive[3] && (f_wait[3] != 3'd0));
  always @(posedge clk) if (f_past_valid && !reset)
    wf4_l3: cover ((f_wait[3] == 3'd3) && req[3] && fire && drive[3]);
`endif // FABRICMERGE_COVER_FAIR
`endif // !FABRICMERGE_NO_FAIR

`ifdef FABRICMERGE_COVER_CONTRACTS
  // ── 모듈 축 cover 증인 (계약 축) ────────────────────────────────────────
  //
  // 증인이 보증하는 것과 보증하지 않는 것 (과대 주장 금지 — DecodeWalk 선례):
  // sby 의 cover 모드는 `chformal -assume -early` 로 assume 은 남기고
  // `chformal -live -fair -assert -remove` 로 **단언을 제거한다**. 그러므로
  // 아래 궤적은 「단언을 만족하도록 제약된 궤적」이 아니라 리셋 규약만 지킨
  // 도달 가능 궤적이다. 그럼에도 결론이 서는 것은 같은 하네스의 bmc/prove
  // 태스크가 *모든* 도달 가능 상태에서 단언이 서는 것을 따로 보이기 때문이다.
  // 순서가 중요하다 — bmc/prove 가 깨지면 증인의 해석도 함께 무너진다.
  wire f_ok_m = f_past_valid && !reset;

  // WC1 ← Fabric.single_producer
  //       `assert (!locked || $onehot(lockedOh))` 의 전건 `locked`.
  //       잠금이 영영 서지 않으면 이 단언은 공허하고, 포획 경로(lockedOh)
  //       전체가 검사에서 빠진다.
  always @(posedge clk) if (f_ok_m) wc1_locked: cover (locked);

  // WC2 ← Fabric.single_producer · Fabric.valid_gated
  //       `assert ($onehot0(drive))` · `assert (consumer_valid == (drive != 4'b0))`
  //       구동 집합이 실제로 비고 버스에 비0 이 실린다. drive 가 늘 0 이면
  //       $onehot0 은 자명하고 등식은 0 == 0 이다.
  always @(posedge clk) if (f_ok_m) wc2_bus_nonzero: cover (consumer_valid && (|consumer_pay));

  // WC3 ← Fabric.single_producer
  //       같은 두 단언의 **최대 경합면**: 넷 전부 요청 중인데 구동은 하나다.
  //       $onehot0(drive) 가 「경합이 없어서」가 아니라 선택 규칙 때문에
  //       서는 것임을 이 증인이 가른다.
  always @(posedge clk) if (f_ok_m) wc3_max_contention: cover ((req == 4'b1111) && (drive != 4'b0000));

  // WC4 ← Fabric.fault_raised · Fabric.bp_loud
  //       `if ($past(shoveAny)) assert (fault)` 의 전건.
  always @(posedge clk) if (f_ok_m) wc4_shove: cover (shoveAny);

  // WC5 ← Fabric.fault_raised
  //       같은 단언의 상승 순간 — fault 가 *처음* 서는 에지. 이미 서 있는
  //       상태를 지나가는 것과 구별되지 않으면 loud 단언이 자명해진다.
  always @(posedge clk) if (f_ok_m) wc5_fault_rise: cover (fault && !$past(fault));

  // WC6 ← Fabric.fault_sticky
  //       `if ($past(fault && !faultClear)) assert (fault)` 의 전건.
  always @(posedge clk) if (f_ok_m) wc6_fault_hold: cover ($past(fault && !faultClear));

  // WC7 ← Fabric.fault_sticky · Fabric.fault_raised · Fabric.bp_loud
  //       그 **반대면**: fault 가 영구 1 이 아니다 (해제가 실제로 내린다).
  //       이것이 없으면 fault_raised · bp_loud 의 `assert (fault)` 는 「리셋
  //       이후 늘 1 인 비트」 위에서 자명하게 통과한다 — 전건 도달성과는
  //       다른 결의 공허이고, 같은 단언 묶음에 함께 걸린다.
  always @(posedge clk) if (f_ok_m) wc7_fault_clear: cover (!fault && $past(fault));

  // WC8 ← Fabric.bp_no_consumer_write
  //       전건 `$past(consumer_valid && !consumer_ready)`.
  //       페이로드 비0 을 함께 요구해 「불변」이 0 의 불변이 아니게 한다.
  always @(posedge clk) if (f_ok_m)
    wc8_bp_nonzero: cover ($past(consumer_valid && !consumer_ready) && (|consumer_pay));

  // WC9 ← Fabric.bp_no_consumer_write · Fabric.bp_loud
  //       같은 전건 ∧ 그 구간의 shove. 하네스 주석이 주장하는 「shove 가
  //       그동안 일어나도 쓰이는 것은 fault 비트 하나뿐」이 실제로 재어지는
  //       궤적 — 배압과 위반이 겹치지 않는 세계라면 그 문장은 미측정이다.
  always @(posedge clk) if (f_ok_m)
    wc9_bp_shove: cover ($past(consumer_valid && !consumer_ready) && shoveAny);

  // WC10 ← Fabric.bp_no_consumer_write
  //        같은 전건의 종결면: 배압이 실제로 풀린다(fire). 영영 얼어 있는
  //        기계에서는 「얼어 있다」가 자명하고, 잠금 해제 경로가 미측정이다.
  always @(posedge clk) if (f_ok_m)
    wc10_bp_release: cover ($past(consumer_valid && !consumer_ready) && fire);
`endif // FABRICMERGE_COVER_CONTRACTS

endmodule

`ifdef FABRICMERGE_EXPOSE_FLOW

// ── sby/yosys 경로 — expose 로 승격된 내부 포트를 손 결선하는 래퍼 ────────
//
// sby 스크립트가 `expose` 로 FabricMerge 내부 신호(lane 상태·face·선택
// 상태·shoveAny·fire)를 출력 포트로 승격한 *뒤* 이 파일을 읽는다. 따라서
// 아래 인스턴스의 내부 신호 포트들은 그 시점에 실재한다. 결선은 아래
// `else` 가지의 bind 문과 정확히 같은 내용이다 — 두 갈래가 어긋나면
// 검증 대상이 달라지므로, 고칠 때는 반드시 양쪽을 함께 고칠 것.
module FabricMerge_formal (
  input wire         clk,
  input wire         reset,
  input wire         io_faultClear,
  input wire         io_consumer_ready,
  input wire         io_push_0_strb,
  input wire [31:0]  io_push_0_result_head_tag_wave,
  input wire [3:0]    io_push_0_result_head_tag_epoch,
  input wire          io_push_0_result_head_tag_poison,
  input wire          io_push_0_result_head_tag_trace,
  input wire [15:0]  io_push_0_result_head_tag_lnid,
  input wire [7:0]   io_push_0_result_head_tag_precision,
  input wire [7:0]   io_push_0_result_head_tag_dim,
  input wire [7:0]   io_push_0_result_head_seq,
  input wire [7:0]   io_push_0_result_head_total,
  input wire         io_push_0_result_head_last,
  input wire [63:0]  io_push_0_result_body,
  input wire         io_push_1_strb,
  input wire [31:0]  io_push_1_result_head_tag_wave,
  input wire [3:0]    io_push_1_result_head_tag_epoch,
  input wire          io_push_1_result_head_tag_poison,
  input wire          io_push_1_result_head_tag_trace,
  input wire [15:0]  io_push_1_result_head_tag_lnid,
  input wire [7:0]   io_push_1_result_head_tag_precision,
  input wire [7:0]   io_push_1_result_head_tag_dim,
  input wire [7:0]   io_push_1_result_head_seq,
  input wire [7:0]   io_push_1_result_head_total,
  input wire         io_push_1_result_head_last,
  input wire [63:0]  io_push_1_result_body,
  input wire         io_push_2_strb,
  input wire [31:0]  io_push_2_result_head_tag_wave,
  input wire [3:0]    io_push_2_result_head_tag_epoch,
  input wire          io_push_2_result_head_tag_poison,
  input wire          io_push_2_result_head_tag_trace,
  input wire [15:0]  io_push_2_result_head_tag_lnid,
  input wire [7:0]   io_push_2_result_head_tag_precision,
  input wire [7:0]   io_push_2_result_head_tag_dim,
  input wire [7:0]   io_push_2_result_head_seq,
  input wire [7:0]   io_push_2_result_head_total,
  input wire         io_push_2_result_head_last,
  input wire [63:0]  io_push_2_result_body,
  input wire         io_push_3_strb,
  input wire [31:0]  io_push_3_result_head_tag_wave,
  input wire [3:0]    io_push_3_result_head_tag_epoch,
  input wire          io_push_3_result_head_tag_poison,
  input wire          io_push_3_result_head_tag_trace,
  input wire [15:0]  io_push_3_result_head_tag_lnid,
  input wire [7:0]   io_push_3_result_head_tag_precision,
  input wire [7:0]   io_push_3_result_head_tag_dim,
  input wire [7:0]   io_push_3_result_head_seq,
  input wire [7:0]   io_push_3_result_head_total,
  input wire         io_push_3_result_head_last,
  input wire [63:0]  io_push_3_result_body
);

  // 원래 출력들
  wire         io_fault;
  wire         io_consumer_valid;
  wire [31:0]  io_consumer_payload_head_tag_wave;
  wire [3:0]    io_consumer_payload_head_tag_epoch;
  wire          io_consumer_payload_head_tag_poison;
  wire          io_consumer_payload_head_tag_trace;
  wire [15:0]  io_consumer_payload_head_tag_lnid;
  wire [7:0]   io_consumer_payload_head_tag_precision;
  wire [7:0]   io_consumer_payload_head_tag_dim;
  wire [7:0]   io_consumer_payload_head_seq;
  wire [7:0]   io_consumer_payload_head_total;
  wire         io_consumer_payload_head_last;
  wire [63:0]  io_consumer_payload_body;
  wire [2:0]   io_occupancy;
  wire         io_push_0_stall, io_push_1_stall, io_push_2_stall, io_push_3_stall;

  // expose 로 승격된 내부 신호들
  wire [31:0]  lanes_0_slots_0_head_tag_wave, lanes_1_slots_0_head_tag_wave,
               lanes_2_slots_0_head_tag_wave, lanes_3_slots_0_head_tag_wave;
  wire [3:0]    lanes_0_slots_0_head_tag_epoch, lanes_1_slots_0_head_tag_epoch,
               lanes_2_slots_0_head_tag_epoch, lanes_3_slots_0_head_tag_epoch;
  wire          lanes_0_slots_0_head_tag_poison, lanes_1_slots_0_head_tag_poison,
               lanes_2_slots_0_head_tag_poison, lanes_3_slots_0_head_tag_poison;
  wire          lanes_0_slots_0_head_tag_trace, lanes_1_slots_0_head_tag_trace,
               lanes_2_slots_0_head_tag_trace, lanes_3_slots_0_head_tag_trace;
  wire [15:0]  lanes_0_slots_0_head_tag_lnid, lanes_1_slots_0_head_tag_lnid,
               lanes_2_slots_0_head_tag_lnid, lanes_3_slots_0_head_tag_lnid;
  wire [7:0]   lanes_0_slots_0_head_tag_precision, lanes_1_slots_0_head_tag_precision,
               lanes_2_slots_0_head_tag_precision, lanes_3_slots_0_head_tag_precision;
  wire [7:0]   lanes_0_slots_0_head_tag_dim, lanes_1_slots_0_head_tag_dim,
               lanes_2_slots_0_head_tag_dim, lanes_3_slots_0_head_tag_dim;
  wire [7:0]   lanes_0_slots_0_head_seq, lanes_1_slots_0_head_seq,
               lanes_2_slots_0_head_seq, lanes_3_slots_0_head_seq;
  wire [7:0]   lanes_0_slots_0_head_total, lanes_1_slots_0_head_total,
               lanes_2_slots_0_head_total, lanes_3_slots_0_head_total;
  wire         lanes_0_slots_0_head_last, lanes_1_slots_0_head_last,
               lanes_2_slots_0_head_last, lanes_3_slots_0_head_last;
  wire [63:0]  lanes_0_slots_0_body, lanes_1_slots_0_body,
               lanes_2_slots_0_body, lanes_3_slots_0_body;
  wire [0:0]   lanes_0_cnt, lanes_1_cnt, lanes_2_cnt, lanes_3_cnt;
  wire         lanes_0_full, lanes_1_full, lanes_2_full, lanes_3_full;
  wire         lanes_0_vld,  lanes_1_vld,  lanes_2_vld,  lanes_3_vld;
  wire         lanes_0_doPush, lanes_1_doPush, lanes_2_doPush, lanes_3_doPush;
  wire         lanes_0_doPop,  lanes_1_doPop,  lanes_2_doPop,  lanes_3_doPop;
  wire         lanes_0_shove,  lanes_1_shove,  lanes_2_shove,  lanes_3_shove;
  wire [3:0]   select_req, select_ptrOh, select_lockedOh, select_selOh, select_drive;
  wire         select_locked;
  wire         io_consumer_fire;
  wire         shoveAny;

  FabricMerge u_dut (
    .clk(clk), .reset(reset),
    .io_fault(io_fault), .io_faultClear(io_faultClear),
    .io_push_0_strb(io_push_0_strb),
    .io_push_0_result_head_tag_wave(io_push_0_result_head_tag_wave),
    .io_push_0_result_head_tag_epoch(io_push_0_result_head_tag_epoch),
    .io_push_0_result_head_tag_poison(io_push_0_result_head_tag_poison),
    .io_push_0_result_head_tag_trace(io_push_0_result_head_tag_trace),
    .io_push_0_result_head_tag_lnid(io_push_0_result_head_tag_lnid),
    .io_push_0_result_head_tag_precision(io_push_0_result_head_tag_precision),
    .io_push_0_result_head_tag_dim(io_push_0_result_head_tag_dim),
    .io_push_0_result_head_seq(io_push_0_result_head_seq),
    .io_push_0_result_head_total(io_push_0_result_head_total),
    .io_push_0_result_head_last(io_push_0_result_head_last),
    .io_push_0_result_body(io_push_0_result_body),
    .io_push_0_stall(io_push_0_stall),
    .io_push_1_strb(io_push_1_strb),
    .io_push_1_result_head_tag_wave(io_push_1_result_head_tag_wave),
    .io_push_1_result_head_tag_epoch(io_push_1_result_head_tag_epoch),
    .io_push_1_result_head_tag_poison(io_push_1_result_head_tag_poison),
    .io_push_1_result_head_tag_trace(io_push_1_result_head_tag_trace),
    .io_push_1_result_head_tag_lnid(io_push_1_result_head_tag_lnid),
    .io_push_1_result_head_tag_precision(io_push_1_result_head_tag_precision),
    .io_push_1_result_head_tag_dim(io_push_1_result_head_tag_dim),
    .io_push_1_result_head_seq(io_push_1_result_head_seq),
    .io_push_1_result_head_total(io_push_1_result_head_total),
    .io_push_1_result_head_last(io_push_1_result_head_last),
    .io_push_1_result_body(io_push_1_result_body),
    .io_push_1_stall(io_push_1_stall),
    .io_push_2_strb(io_push_2_strb),
    .io_push_2_result_head_tag_wave(io_push_2_result_head_tag_wave),
    .io_push_2_result_head_tag_epoch(io_push_2_result_head_tag_epoch),
    .io_push_2_result_head_tag_poison(io_push_2_result_head_tag_poison),
    .io_push_2_result_head_tag_trace(io_push_2_result_head_tag_trace),
    .io_push_2_result_head_tag_lnid(io_push_2_result_head_tag_lnid),
    .io_push_2_result_head_tag_precision(io_push_2_result_head_tag_precision),
    .io_push_2_result_head_tag_dim(io_push_2_result_head_tag_dim),
    .io_push_2_result_head_seq(io_push_2_result_head_seq),
    .io_push_2_result_head_total(io_push_2_result_head_total),
    .io_push_2_result_head_last(io_push_2_result_head_last),
    .io_push_2_result_body(io_push_2_result_body),
    .io_push_2_stall(io_push_2_stall),
    .io_push_3_strb(io_push_3_strb),
    .io_push_3_result_head_tag_wave(io_push_3_result_head_tag_wave),
    .io_push_3_result_head_tag_epoch(io_push_3_result_head_tag_epoch),
    .io_push_3_result_head_tag_poison(io_push_3_result_head_tag_poison),
    .io_push_3_result_head_tag_trace(io_push_3_result_head_tag_trace),
    .io_push_3_result_head_tag_lnid(io_push_3_result_head_tag_lnid),
    .io_push_3_result_head_tag_precision(io_push_3_result_head_tag_precision),
    .io_push_3_result_head_tag_dim(io_push_3_result_head_tag_dim),
    .io_push_3_result_head_seq(io_push_3_result_head_seq),
    .io_push_3_result_head_total(io_push_3_result_head_total),
    .io_push_3_result_head_last(io_push_3_result_head_last),
    .io_push_3_result_body(io_push_3_result_body),
    .io_push_3_stall(io_push_3_stall),
    .io_consumer_valid(io_consumer_valid),
    .io_consumer_ready(io_consumer_ready),
    .io_consumer_payload_head_tag_wave(io_consumer_payload_head_tag_wave),
    .io_consumer_payload_head_tag_epoch(io_consumer_payload_head_tag_epoch),
    .io_consumer_payload_head_tag_poison(io_consumer_payload_head_tag_poison),
    .io_consumer_payload_head_tag_trace(io_consumer_payload_head_tag_trace),
    .io_consumer_payload_head_tag_lnid(io_consumer_payload_head_tag_lnid),
    .io_consumer_payload_head_tag_precision(io_consumer_payload_head_tag_precision),
    .io_consumer_payload_head_tag_dim(io_consumer_payload_head_tag_dim),
    .io_consumer_payload_head_seq(io_consumer_payload_head_seq),
    .io_consumer_payload_head_total(io_consumer_payload_head_total),
    .io_consumer_payload_head_last(io_consumer_payload_head_last),
    .io_consumer_payload_body(io_consumer_payload_body),
    .io_occupancy(io_occupancy),
    // ── expose 승격 포트 ──
    .lanes_0_slots_0_head_tag_wave(lanes_0_slots_0_head_tag_wave),
    .lanes_0_slots_0_head_tag_epoch(lanes_0_slots_0_head_tag_epoch),
    .lanes_0_slots_0_head_tag_poison(lanes_0_slots_0_head_tag_poison),
    .lanes_0_slots_0_head_tag_trace(lanes_0_slots_0_head_tag_trace),
    .lanes_0_slots_0_head_tag_lnid(lanes_0_slots_0_head_tag_lnid),
    .lanes_0_slots_0_head_tag_precision(lanes_0_slots_0_head_tag_precision),
    .lanes_0_slots_0_head_tag_dim(lanes_0_slots_0_head_tag_dim),
    .lanes_0_slots_0_head_seq(lanes_0_slots_0_head_seq),
    .lanes_0_slots_0_head_total(lanes_0_slots_0_head_total),
    .lanes_0_slots_0_head_last(lanes_0_slots_0_head_last),
    .lanes_0_slots_0_body(lanes_0_slots_0_body),
    .lanes_1_slots_0_head_tag_wave(lanes_1_slots_0_head_tag_wave),
    .lanes_1_slots_0_head_tag_epoch(lanes_1_slots_0_head_tag_epoch),
    .lanes_1_slots_0_head_tag_poison(lanes_1_slots_0_head_tag_poison),
    .lanes_1_slots_0_head_tag_trace(lanes_1_slots_0_head_tag_trace),
    .lanes_1_slots_0_head_tag_lnid(lanes_1_slots_0_head_tag_lnid),
    .lanes_1_slots_0_head_tag_precision(lanes_1_slots_0_head_tag_precision),
    .lanes_1_slots_0_head_tag_dim(lanes_1_slots_0_head_tag_dim),
    .lanes_1_slots_0_head_seq(lanes_1_slots_0_head_seq),
    .lanes_1_slots_0_head_total(lanes_1_slots_0_head_total),
    .lanes_1_slots_0_head_last(lanes_1_slots_0_head_last),
    .lanes_1_slots_0_body(lanes_1_slots_0_body),
    .lanes_2_slots_0_head_tag_wave(lanes_2_slots_0_head_tag_wave),
    .lanes_2_slots_0_head_tag_epoch(lanes_2_slots_0_head_tag_epoch),
    .lanes_2_slots_0_head_tag_poison(lanes_2_slots_0_head_tag_poison),
    .lanes_2_slots_0_head_tag_trace(lanes_2_slots_0_head_tag_trace),
    .lanes_2_slots_0_head_tag_lnid(lanes_2_slots_0_head_tag_lnid),
    .lanes_2_slots_0_head_tag_precision(lanes_2_slots_0_head_tag_precision),
    .lanes_2_slots_0_head_tag_dim(lanes_2_slots_0_head_tag_dim),
    .lanes_2_slots_0_head_seq(lanes_2_slots_0_head_seq),
    .lanes_2_slots_0_head_total(lanes_2_slots_0_head_total),
    .lanes_2_slots_0_head_last(lanes_2_slots_0_head_last),
    .lanes_2_slots_0_body(lanes_2_slots_0_body),
    .lanes_3_slots_0_head_tag_wave(lanes_3_slots_0_head_tag_wave),
    .lanes_3_slots_0_head_tag_epoch(lanes_3_slots_0_head_tag_epoch),
    .lanes_3_slots_0_head_tag_poison(lanes_3_slots_0_head_tag_poison),
    .lanes_3_slots_0_head_tag_trace(lanes_3_slots_0_head_tag_trace),
    .lanes_3_slots_0_head_tag_lnid(lanes_3_slots_0_head_tag_lnid),
    .lanes_3_slots_0_head_tag_precision(lanes_3_slots_0_head_tag_precision),
    .lanes_3_slots_0_head_tag_dim(lanes_3_slots_0_head_tag_dim),
    .lanes_3_slots_0_head_seq(lanes_3_slots_0_head_seq),
    .lanes_3_slots_0_head_total(lanes_3_slots_0_head_total),
    .lanes_3_slots_0_head_last(lanes_3_slots_0_head_last),
    .lanes_3_slots_0_body(lanes_3_slots_0_body),
    .lanes_0_cnt(lanes_0_cnt), .lanes_1_cnt(lanes_1_cnt),
    .lanes_2_cnt(lanes_2_cnt), .lanes_3_cnt(lanes_3_cnt),
    .lanes_0_full(lanes_0_full), .lanes_1_full(lanes_1_full),
    .lanes_2_full(lanes_2_full), .lanes_3_full(lanes_3_full),
    .lanes_0_vld(lanes_0_vld), .lanes_1_vld(lanes_1_vld),
    .lanes_2_vld(lanes_2_vld), .lanes_3_vld(lanes_3_vld),
    .lanes_0_doPush(lanes_0_doPush), .lanes_1_doPush(lanes_1_doPush),
    .lanes_2_doPush(lanes_2_doPush), .lanes_3_doPush(lanes_3_doPush),
    .lanes_0_doPop(lanes_0_doPop), .lanes_1_doPop(lanes_1_doPop),
    .lanes_2_doPop(lanes_2_doPop), .lanes_3_doPop(lanes_3_doPop),
    .lanes_0_shove(lanes_0_shove), .lanes_1_shove(lanes_1_shove),
    .lanes_2_shove(lanes_2_shove), .lanes_3_shove(lanes_3_shove),
    .select_req(select_req), .select_ptrOh(select_ptrOh),
    .select_lockedOh(select_lockedOh), .select_locked(select_locked),
    .select_selOh(select_selOh), .select_drive(select_drive),
    .io_consumer_fire(io_consumer_fire),
    .shoveAny(shoveAny)
  );

  FabricMerge_props u_props (
    .clk            (clk),
    .reset          (reset),
    .fault          (io_fault),
    .faultClear     (io_faultClear),
    .consumer_valid (io_consumer_valid),
    .consumer_ready (io_consumer_ready),
    .fire           (io_consumer_fire),
    .consumer_pay   ({io_consumer_payload_body,
                      io_consumer_payload_head_last,
                      io_consumer_payload_head_total,
                      io_consumer_payload_head_seq,
                      io_consumer_payload_head_tag_dim,
                      io_consumer_payload_head_tag_precision,
                      io_consumer_payload_head_tag_lnid,
                      io_consumer_payload_head_tag_epoch,
                      io_consumer_payload_head_tag_poison,
                      io_consumer_payload_head_tag_trace,
                      io_consumer_payload_head_tag_wave}),
    .strb           ({io_push_3_strb, io_push_2_strb, io_push_1_strb, io_push_0_strb}),
    .stall          ({io_push_3_stall, io_push_2_stall, io_push_1_stall, io_push_0_stall}),
    .push_pay_0     ({io_push_0_result_body,
                      io_push_0_result_head_last,
                      io_push_0_result_head_total,
                      io_push_0_result_head_seq,
                      io_push_0_result_head_tag_dim,
                      io_push_0_result_head_tag_precision,
                      io_push_0_result_head_tag_lnid,
                      io_push_0_result_head_tag_epoch,
                      io_push_0_result_head_tag_poison,
                      io_push_0_result_head_tag_trace,
                      io_push_0_result_head_tag_wave}),
    .push_pay_1     ({io_push_1_result_body,
                      io_push_1_result_head_last,
                      io_push_1_result_head_total,
                      io_push_1_result_head_seq,
                      io_push_1_result_head_tag_dim,
                      io_push_1_result_head_tag_precision,
                      io_push_1_result_head_tag_lnid,
                      io_push_1_result_head_tag_epoch,
                      io_push_1_result_head_tag_poison,
                      io_push_1_result_head_tag_trace,
                      io_push_1_result_head_tag_wave}),
    .push_pay_2     ({io_push_2_result_body,
                      io_push_2_result_head_last,
                      io_push_2_result_head_total,
                      io_push_2_result_head_seq,
                      io_push_2_result_head_tag_dim,
                      io_push_2_result_head_tag_precision,
                      io_push_2_result_head_tag_lnid,
                      io_push_2_result_head_tag_epoch,
                      io_push_2_result_head_tag_poison,
                      io_push_2_result_head_tag_trace,
                      io_push_2_result_head_tag_wave}),
    .push_pay_3     ({io_push_3_result_body,
                      io_push_3_result_head_last,
                      io_push_3_result_head_total,
                      io_push_3_result_head_seq,
                      io_push_3_result_head_tag_dim,
                      io_push_3_result_head_tag_precision,
                      io_push_3_result_head_tag_lnid,
                      io_push_3_result_head_tag_epoch,
                      io_push_3_result_head_tag_poison,
                      io_push_3_result_head_tag_trace,
                      io_push_3_result_head_tag_wave}),
    .face_0         ({lanes_0_slots_0_body,
                      lanes_0_slots_0_head_last,
                      lanes_0_slots_0_head_total,
                      lanes_0_slots_0_head_seq,
                      lanes_0_slots_0_head_tag_dim,
                      lanes_0_slots_0_head_tag_precision,
                      lanes_0_slots_0_head_tag_lnid,
                      lanes_0_slots_0_head_tag_epoch,
                      lanes_0_slots_0_head_tag_poison,
                      lanes_0_slots_0_head_tag_trace,
                      lanes_0_slots_0_head_tag_wave}),
    .face_1         ({lanes_1_slots_0_body,
                      lanes_1_slots_0_head_last,
                      lanes_1_slots_0_head_total,
                      lanes_1_slots_0_head_seq,
                      lanes_1_slots_0_head_tag_dim,
                      lanes_1_slots_0_head_tag_precision,
                      lanes_1_slots_0_head_tag_lnid,
                      lanes_1_slots_0_head_tag_epoch,
                      lanes_1_slots_0_head_tag_poison,
                      lanes_1_slots_0_head_tag_trace,
                      lanes_1_slots_0_head_tag_wave}),
    .face_2         ({lanes_2_slots_0_body,
                      lanes_2_slots_0_head_last,
                      lanes_2_slots_0_head_total,
                      lanes_2_slots_0_head_seq,
                      lanes_2_slots_0_head_tag_dim,
                      lanes_2_slots_0_head_tag_precision,
                      lanes_2_slots_0_head_tag_lnid,
                      lanes_2_slots_0_head_tag_epoch,
                      lanes_2_slots_0_head_tag_poison,
                      lanes_2_slots_0_head_tag_trace,
                      lanes_2_slots_0_head_tag_wave}),
    .face_3         ({lanes_3_slots_0_body,
                      lanes_3_slots_0_head_last,
                      lanes_3_slots_0_head_total,
                      lanes_3_slots_0_head_seq,
                      lanes_3_slots_0_head_tag_dim,
                      lanes_3_slots_0_head_tag_precision,
                      lanes_3_slots_0_head_tag_lnid,
                      lanes_3_slots_0_head_tag_epoch,
                      lanes_3_slots_0_head_tag_poison,
                      lanes_3_slots_0_head_tag_trace,
                      lanes_3_slots_0_head_tag_wave}),
    .cnt            ({lanes_3_cnt, lanes_2_cnt, lanes_1_cnt, lanes_0_cnt}),
    .full           ({lanes_3_full, lanes_2_full, lanes_1_full, lanes_0_full}),
    .vld            ({lanes_3_vld, lanes_2_vld, lanes_1_vld, lanes_0_vld}),
    .doPush         ({lanes_3_doPush, lanes_2_doPush, lanes_1_doPush, lanes_0_doPush}),
    .doPop          ({lanes_3_doPop, lanes_2_doPop, lanes_1_doPop, lanes_0_doPop}),
    .shove          ({lanes_3_shove, lanes_2_shove, lanes_1_shove, lanes_0_shove}),
    .req            (select_req),
    .ptrOh          (select_ptrOh),
    .lockedOh       (select_lockedOh),
    .locked         (select_locked),
    .selOh          (select_selOh),
    .drive          (select_drive),
    .shoveAny       (shoveAny)
  );

endmodule

`else  // bind 를 실제 적용하는 도구용 — 결선은 위 래퍼와 1:1 동일

// ── bind — 대상 내부 스코프에 부착. 연접 순서는 merge_contribs_* 와 동일:
//    {body, last, total, seq, dim, precision, lnid, epoch, poison, trace, wave} ──
bind FabricMerge FabricMerge_props u_props (
  .clk            (clk),
  .reset          (reset),
  .fault          (io_fault),
  .faultClear     (io_faultClear),
  .consumer_valid (io_consumer_valid),
  .consumer_ready (io_consumer_ready),
  .fire           (io_consumer_fire),
  .consumer_pay   ({io_consumer_payload_body,
                    io_consumer_payload_head_last,
                    io_consumer_payload_head_total,
                    io_consumer_payload_head_seq,
                    io_consumer_payload_head_tag_dim,
                    io_consumer_payload_head_tag_precision,
                    io_consumer_payload_head_tag_lnid,
                    io_consumer_payload_head_tag_epoch,
                    io_consumer_payload_head_tag_poison,
                    io_consumer_payload_head_tag_trace,
                    io_consumer_payload_head_tag_wave}),
  .strb           ({io_push_3_strb, io_push_2_strb, io_push_1_strb, io_push_0_strb}),
  .stall          ({io_push_3_stall, io_push_2_stall, io_push_1_stall, io_push_0_stall}),
  .push_pay_0     ({io_push_0_result_body,
                    io_push_0_result_head_last,
                    io_push_0_result_head_total,
                    io_push_0_result_head_seq,
                    io_push_0_result_head_tag_dim,
                    io_push_0_result_head_tag_precision,
                    io_push_0_result_head_tag_lnid,
                    io_push_0_result_head_tag_epoch,
                    io_push_0_result_head_tag_poison,
                    io_push_0_result_head_tag_trace,
                    io_push_0_result_head_tag_wave}),
  .push_pay_1     ({io_push_1_result_body,
                    io_push_1_result_head_last,
                    io_push_1_result_head_total,
                    io_push_1_result_head_seq,
                    io_push_1_result_head_tag_dim,
                    io_push_1_result_head_tag_precision,
                    io_push_1_result_head_tag_lnid,
                    io_push_1_result_head_tag_epoch,
                    io_push_1_result_head_tag_poison,
                    io_push_1_result_head_tag_trace,
                    io_push_1_result_head_tag_wave}),
  .push_pay_2     ({io_push_2_result_body,
                    io_push_2_result_head_last,
                    io_push_2_result_head_total,
                    io_push_2_result_head_seq,
                    io_push_2_result_head_tag_dim,
                    io_push_2_result_head_tag_precision,
                    io_push_2_result_head_tag_lnid,
                    io_push_2_result_head_tag_epoch,
                    io_push_2_result_head_tag_poison,
                    io_push_2_result_head_tag_trace,
                    io_push_2_result_head_tag_wave}),
  .push_pay_3     ({io_push_3_result_body,
                    io_push_3_result_head_last,
                    io_push_3_result_head_total,
                    io_push_3_result_head_seq,
                    io_push_3_result_head_tag_dim,
                    io_push_3_result_head_tag_precision,
                    io_push_3_result_head_tag_lnid,
                    io_push_3_result_head_tag_epoch,
                    io_push_3_result_head_tag_poison,
                    io_push_3_result_head_tag_trace,
                    io_push_3_result_head_tag_wave}),
  .face_0         ({lanes_0_slots_0_body,
                    lanes_0_slots_0_head_last,
                    lanes_0_slots_0_head_total,
                    lanes_0_slots_0_head_seq,
                    lanes_0_slots_0_head_tag_dim,
                    lanes_0_slots_0_head_tag_precision,
                    lanes_0_slots_0_head_tag_lnid,
                    lanes_0_slots_0_head_tag_epoch,
                    lanes_0_slots_0_head_tag_poison,
                    lanes_0_slots_0_head_tag_trace,
                    lanes_0_slots_0_head_tag_wave}),
  .face_1         ({lanes_1_slots_0_body,
                    lanes_1_slots_0_head_last,
                    lanes_1_slots_0_head_total,
                    lanes_1_slots_0_head_seq,
                    lanes_1_slots_0_head_tag_dim,
                    lanes_1_slots_0_head_tag_precision,
                    lanes_1_slots_0_head_tag_lnid,
                    lanes_1_slots_0_head_tag_epoch,
                    lanes_1_slots_0_head_tag_poison,
                    lanes_1_slots_0_head_tag_trace,
                    lanes_1_slots_0_head_tag_wave}),
  .face_2         ({lanes_2_slots_0_body,
                    lanes_2_slots_0_head_last,
                    lanes_2_slots_0_head_total,
                    lanes_2_slots_0_head_seq,
                    lanes_2_slots_0_head_tag_dim,
                    lanes_2_slots_0_head_tag_precision,
                    lanes_2_slots_0_head_tag_lnid,
                    lanes_2_slots_0_head_tag_epoch,
                    lanes_2_slots_0_head_tag_poison,
                    lanes_2_slots_0_head_tag_trace,
                    lanes_2_slots_0_head_tag_wave}),
  .face_3         ({lanes_3_slots_0_body,
                    lanes_3_slots_0_head_last,
                    lanes_3_slots_0_head_total,
                    lanes_3_slots_0_head_seq,
                    lanes_3_slots_0_head_tag_dim,
                    lanes_3_slots_0_head_tag_precision,
                    lanes_3_slots_0_head_tag_lnid,
                    lanes_3_slots_0_head_tag_epoch,
                    lanes_3_slots_0_head_tag_poison,
                    lanes_3_slots_0_head_tag_trace,
                    lanes_3_slots_0_head_tag_wave}),
  .cnt            ({lanes_3_cnt, lanes_2_cnt, lanes_1_cnt, lanes_0_cnt}),
  .full           ({lanes_3_full, lanes_2_full, lanes_1_full, lanes_0_full}),
  .vld            ({lanes_3_vld, lanes_2_vld, lanes_1_vld, lanes_0_vld}),
  .doPush         ({lanes_3_doPush, lanes_2_doPush, lanes_1_doPush, lanes_0_doPush}),
  .doPop          ({lanes_3_doPop, lanes_2_doPop, lanes_1_doPop, lanes_0_doPop}),
  .shove          ({lanes_3_shove, lanes_2_shove, lanes_1_shove, lanes_0_shove}),
  .req            (select_req),
  .ptrOh          (select_ptrOh),
  .lockedOh       (select_lockedOh),
  .locked         (select_locked),
  .selOh          (select_selOh),
  .drive          (select_drive),
  .shoveAny       (shoveAny)
);

`endif
