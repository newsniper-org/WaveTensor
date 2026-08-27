// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// OwnershipTable 후-formal 하네스 (§6.3) — 축: 전이는 명시 기입 사이클에만
// (암묵 전이·축출 부재 — E.7 이 금지한 형태) · 커밋 원자성 (유효 비트와
// 태그가 한 에지에 함께 — 혼합 관측 사이클 부재) · 방향은 *오프셋*이 정한다.
//
// Platform 가드의 정식 GUARD-MAP 줄은 HiuPipeline.scala 에 있다 (가드당
// 저장소 전체 한 줄 규율). 이 표는 그 판정의 데이터 원천이므로, 여기서 재는
// 것은 상태 기계 실물의 전이 규율이다 — 각 assert 옆에 가드명 주석.
//
// 대상 SV 는 rtl/generated/OwnershipTable.sv 커밋본 그대로.
//
// ══ 부착 방식 — bind 를 버리고 expose + 래퍼로 (2026-08-25) ═══════════════
//
// 앞판은 `bind OwnershipTable OwnershipTable_props ...` 로 붙였다. yosys 0.66
// 자유 프론트엔드는 bind 를 **조용히 버린다** — 이 저장소의 다른 하네스
// (SharedUnit · ResultBank · MmioConfig …)는 이미 그 실측 때문에 expose 로
// 옮겨 갔는데 이 파일은 남아 있었다 (`XlateStore_props.sv` 도 같은 상태다 —
// 이 파도의 배정 밖이라 rtl/README.md 에 사실만 등재했다). 결과는 공허
// PASS 였다: 앞 파도의
// ownershiptable.sby 두 태스크는 **assert 셀 0 개**로 통과했다 (실측:
// design_smt2.smt2 의 assert 셀 수 0 · props 인스턴스 0). 즉 이 모듈에
// 대한 후-formal 은 지금까지 아무것도 재지 않았다.
//
// ⇒ 아래 OwnershipTable_formal 래퍼가 결선을 맡고, sby [script] 의 expose 가
//    내부 레지스터(validBits · tagVec_*)를 포트로 승격한다. 공허가 아님은
//    smt2 의 assert 셀 수와 cover 태스크의 증인 도달로 함께 검산한다.
//
// ══ 독립 재구성 원칙 — RTL 의 자기 판정을 믿지 않는다 ═════════════════════
//
// 이 하네스는 전이의 *방향*·*대상*·*충돌* 을 전부 1차 입력(io_addr ·
// io_wdata · io_wstrobe · io_ready)과 노출된 상태 레지스터에서 **다시
// 계산한다.** RTL 의 setWr/clrWr/collide/wIdx/wTag 를 가져다 쓰지 않는다.
//
// 앞판은 방향을 `$past(io_wdata[31])` — 1차 입력의 비트 하나 — 에서 읽었다.
// 전이 명령이 오프셋으로 옮겨 간 지금 그 자리를 RTL 내부 신호 setWr/clrWr 로
// 대체하면, 「주소 디코드가 두 방향을 맞바꾼다」는 결함을 하네스가 스스로
// 눈감는다. 그래서 오프셋 디코드까지 검사자 쪽에서 재구성한다 — 앞판이
// slotBusy/slotMine 을 원 레지스터에서 다시 계산한 것과 같은 취지이며,
// 커버리지는 *늘어난다* (주소 디코드가 검사 대상에 새로 들어온다).

`default_nettype none

module OwnershipTable_props (
  input wire          clk,
  input wire          reset,
  // ── 1차 입력/관측 (DUT 포트) ──────────────────────────────────────────
  input wire [11:0]   io_addr,
  input wire          io_wstrobe,
  input wire [31:0]   io_wdata,
  input wire          io_rstrobe,
  input wire          io_ready,
  input wire [31:0]   io_query_frame,
  input wire          io_query_devOwned,
  input wire          io_faultCollide,
  input wire          io_faultClearCollide,
  input wire          io_faultBadWrite,
  input wire          io_faultClearBadWrite,
  // ── expose 로 승격된 상태 (래퍼가 anyconst 슬롯으로 사영해 넘긴다) ────
  input wire [63:0]   f_valid,         // validBits — 전 슬롯 (비트 선택은 값싸다)
  input wire [5:0]    f_slot,          // anyconst 슬롯 (래퍼 소유 — 아래 주석)
  input wire [25:0]   f_sTag           // tagVec[f_slot] — 래퍼의 64:1 case 먹스
);
  // 형상 상수 — OwnershipTable(ownEntries = 64) · FRAME_W = 32 ⇒ idxW 6 · tagW 26.
  localparam integer TAGW    = 26;
  localparam [3:0]   REGION  = 4'h2;
  // 워드 선택은 addr[3:2] 전수 디코드다 (E.1.2: addr[3] = 조회 쌍/전이 쌍 ·
  // addr[2] = 쌍 안의 방향). addr[7:4] 는 0 이어야 한다 — 그 밖은 예약 오프셋.
  localparam [5:0]   W_IDX    = 6'd0;  // 0x200 OWN_IDX    RW
  localparam [5:0]   W_STATUS = 6'd1;  // 0x204 OWN_STATUS RO
  localparam [5:0]   W_SET    = 6'd2;  // 0x208 OWN_SET    WO — 이양
  localparam [5:0]   W_CLR    = 6'd3;  // 0x20C OWN_CLR    WO — 회수

  // ── ENV assume: 단발 reset 프로토콜 (근거: HiuMask_props.sv 동일 —
  // async-reset 레지스터의 형식 검사 초기화 규약. 그 외 assume 없음) ──
  reg f_init = 1'b1;
  always @(posedge clk) f_init <= 1'b0;
  always @(*) begin
    if (f_init) assume (reset);
    else        assume (!reset);
  end

  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;
  // reset 의 한 사이클 지연을 *레지스터*로 든다. 앞판은 여기를
  // `!$past(reset)` 로 적었는데 그것은 연속 대입 안이라 yosys 가 거부한다
  // (「$past is only allowed in clocked blocks」). 앞판에서 그 오류가 드러나지
  // 않은 이유는 bind 묵살로 이 모듈이 아예 elaborate 되지 않았기 때문이다 —
  // 공허 PASS 가 문법 오류까지 가려 주고 있었다. 의미는 동일하다.
  reg f_reset_d = 1'b1;
  always @(posedge clk) f_reset_d <= reset;
  wire f_ok = f_past_valid && !reset && !f_reset_d;

  // ── 조회 공간의 분해 — 색인 + 태그가 프레임 *전폭*이다 ────────────────
  wire [5:0]      f_qIdx = io_query_frame[5:0];
  wire [TAGW-1:0] f_qTag = io_query_frame[31:6];
  wire            f_qHit = (f_qIdx == f_slot);   // 조회가 anyconst 슬롯에 앉는가

  // ── MMIO 디코드의 독립 재구성 (머리말 「독립 재구성 원칙」) ────────────
  wire f_aligned = (io_addr[1:0] == 2'b00);
  wire f_region  = (io_addr[11:8] == REGION);
  wire f_selW    = io_ready && io_wstrobe && f_aligned && f_region;
  wire f_idxWr    = f_selW && (io_addr[7:2] == W_IDX);
  wire f_statusWr = f_selW && (io_addr[7:2] == W_STATUS);
  wire f_setWr    = f_selW && (io_addr[7:2] == W_SET);
  wire f_clrWr    = f_selW && (io_addr[7:2] == W_CLR);

  // 전이 워드 — 워드 전체가 프레임이다 (예약 비트도 방향 비트도 없다).
  wire [5:0]      f_wIdx = io_wdata[5:0];
  wire [TAGW-1:0] f_wTag = io_wdata[31:6];
  wire f_hit  = (f_wIdx == f_slot);              // 기입이 anyconst 슬롯을 겨냥하는가
  wire f_sVal = f_valid[f_slot];
  wire f_mine = (f_sTag == f_wTag);
  // 직접 사상 충돌 — 이양 대상 슬롯이 *남의* 페이지로 점유돼 있다.
  wire f_collide = f_setWr && f_hit && f_sVal && !f_mine;

  // ── 조합 축 — 조회 정의 (Platform.owner_check 의 데이터 원천) ───────────
  // devOwned = 유효 ∧ 태그 일치. 정의역은 32b 전부다 — 앞판의 `!frame[31]`
  // 항이 사라졌지만 그것은 커버리지 손실이 아니다: 앞판에서 태그 비교가
  // 덮던 것은 [30:6] 이고 [31] 은 별항이 따로 덮었다. 지금은 태그 비교가
  // [31:6] 을 덮는다 — 두 경우 모두 등식이 프레임 32b *전부*에 대해 서고,
  // 구속되는 조회 공간의 크기(2^32)가 같다. 항이 준 것은 「이 구간에서는
  // 항상 거짓」이라는 *약한* 사실이었고, 지금은 그 구간이 다른 구간과
  // 똑같이 「표가 정한다」는 *강한* 사실 아래 들어와 있다.
  // anyconst 슬롯으로 사영해도 보편성은 그대로다 — f_slot 이 자유 상수이므로
  // 「조회가 f_slot 에 앉는 모든 실행」에 대한 증명은 64 색인 전부를 덮는다.
  // 태그 26b 는 여전히 자유라 각 색인에서 태그 공간 전체가 구속된다.
  always @(*) begin
    if (f_past_valid && !reset && f_qHit) begin
      assert (io_query_devOwned == (f_sVal && (f_sTag == f_qTag)));
    end
  end

  // ── 방향의 배타성 — 한 쓰기가 두 방향일 수 없다 (E.7 「한 번의 쓰기」) ──
  // 명령이 데이터 비트에 있던 앞판에서는 이것이 비트 하나의 항진명제라
  // 적을 자리가 없었다. 오프셋으로 옮긴 지금은 *디코드의 성질*이므로 잰다 —
  // 두 워드 비교가 겹치면(디코드 결함) 한 워드 쓰기가 이양이자 회수가 된다.
  always @(*) begin
    if (f_past_valid && !reset) begin
      assert (!(f_setWr && f_clrWr));
      assert (!(f_setWr && f_statusWr));
      assert (!(f_clrWr && f_statusWr));
      assert (!(f_setWr && f_idxWr));
      assert (!(f_clrWr && f_idxWr));
    end
  end

  // ── 시제 축 — 슬롯 전이 규율 (anyconst 슬롯 보편 검사) ──────────────────
  //
  // anyconst 슬롯 f_slot (래퍼 소유): *임의 고정* 슬롯에 대한 증명 = 전 슬롯
  // 보편 증명. 슬롯을 값으로 고정하지 않으므로 솔버가 반증하기 가장 쉬운
  // 슬롯을 스스로 고르고, 그 슬롯에서 성질이 서면 64개 전부에서 선다.
  // ResultBank_props.sv 가 store 축에 쓴 것과 같은 형태이며 같은 이유다.
  //
  // 실측 (2026-08-25): 64슬롯 generate 전수형은 $past 상태가 1664b 가 되어
  // BMC 가 10분+ 에도 미종료였다. anyconst 사영 + 래퍼 case 먹스로 상태가
  // 슬롯 하나분(27b)으로 줄고, 증명하는 명제는 같다.
  //
  // 이양/회수 조건은 검사자 쪽에서 f_valid/f_sTag + 재구성 디코드로 독립
  // 재구성한다 (RTL 의 slotBusy/slotMine/setWr/clrWr 을 믿지 않는다).
  always @(posedge clk) begin
    if (f_ok) begin
      if ($past(f_setWr) && $past(f_hit) && !$past(f_sVal)) begin
        // Platform.state_machine_kept / E.7 — 이양 커밋 원자성: 유효 비트와
        // 태그가 같은 에지에 함께 선다 — 부분 상태 관측 사이클 부재.
        // 대상 프레임에 제약이 없다 — 32b 전 구간이 이양 가능하다
        // (앞판은 프레임 ≥ 2^31 을 표현조차 못 했다. c_owned_high 가 증인).
        assert (f_sVal);
        assert (f_sTag == $past(f_wTag));
      end else if ($past(f_clrWr) && $past(f_hit) && $past(f_sVal)
                   && ($past(f_sTag) == $past(f_wTag))) begin
        // 회수 — 유효만 내리고 태그는 불변 (한 에지 완결)
        assert (!f_sVal);
        assert ($stable(f_sTag));
      end else begin
        // Platform.state_machine_kept / E.7 — 암묵 전이 부재: 위 두 명시
        // 기입 경우 밖에서는 validBits 도 태그도 움직이지 않는다 — 축출
        // 배선 부재의 관측형. 이 else 가 덮는 경우는 앞판보다 *늘었다*:
        // 기입 없는 사이클 · 타 슬롯 기입 · 충돌 기입 · 무연산 항등 ·
        // 읽기 strobe · OWN_IDX 기입 · **OWN_STATUS(RO) 기입** ·
        // **예약 오프셋 기입** · 비정렬 기입 · 구역 밖 기입.
        // 굵은 둘은 앞판에 없던 경우다 — 0x204 는 앞판에서 전이 관문
        // 자체였고, 예약/비정렬은 앞판이 dataWr 안에 접어 두어 검사자가
        // 따로 볼 수 없었다.
        assert ($stable(f_sVal));
        assert ($stable(f_sTag));
      end
    end
  end

  // ── 충돌은 loud — 기입 무효는 위 else 가지가 재고, fault 는 여기 ────────
  always @(posedge clk) begin
    if (f_ok) begin
      // 충돌 기입(이양 대상 슬롯이 남의 것) → sticky fault 세움 (같은
      // 사이클 clear 와 겹쳐도 세움이 이긴다 — StickyFault 규율)
      if ($past(f_collide))
        assert (io_faultCollide);
      // sticky — 명시적 해제 외엔 내려가지 않는다.
      if ($past(io_faultCollide && !io_faultClearCollide))
        assert (io_faultCollide);
    end
  end

  // ── RO 오프셋의 쓰기는 loud — 조용한 무시 금지 (E.1.1) ─────────────────
  // 신설 축이다. 앞판에서 0x204 는 전이 관문이었고 지금은 RO 상태 창
  // (OWN_STATUS)이다. 앞판 드라이버가 그 오프셋에 이양 워드를 계속 쓰면 *아무 일도 일어나지
  // 않는다* — 조용히 무시하면 드라이버는 자기 이양이 먹혔다고 믿고 장치가
  // 소유하지 않은 페이지를 장치에 넘겼다고 회계한다. §5.5 가 조용한 실패를
  // 보안 문제로 승격한 자리이며, 여기서는 마이그레이션 안전망을 겸한다.
  always @(posedge clk) begin
    if (f_ok) begin
      if ($past(f_statusWr))
        assert (io_faultBadWrite);
      if ($past(io_faultBadWrite && !io_faultClearBadWrite))
        assert (io_faultBadWrite);
    end
  end

  // ── WO 오프셋의 읽기는 조용하다 — fault 를 내지 않는다 (E.1.1) ─────────
  // 방향 축의 반대편이다. 읽기는 장치가 *돌려주는* 쪽이라 관대함이 하위
  // 호환을 만든다. 「읽기 0」 자체는 rdata 관측이라 여기서 재지 않고,
  // *fault 를 내지 않는다*는 것만 잰다 (fault 두 축 모두 정지).
  wire f_woRead = io_ready && !io_wstrobe && io_rstrobe && f_aligned && f_region
                  && ((io_addr[7:2] == W_SET) || (io_addr[7:2] == W_CLR));
  always @(posedge clk) begin
    if (f_ok && $past(f_woRead)) begin
      assert (io_faultBadWrite == $past(io_faultBadWrite && !io_faultClearBadWrite));
      assert (io_faultCollide  == $past(io_faultCollide  && !io_faultClearCollide));
    end
  end

  // ── 도달성 증인 (cover 태스크 전용 — 공허 PASS 방지) ───────────────────
  // 이 파일의 단언은 「A 이면 B」 꼴이 대부분이라 A 가 충족 불가능하면 전부
  // 공허하게 통과한다. bind 묵살로 실제 공허 PASS 를 겪은 모듈이므로
  // (머리말) 증인을 명시적으로 둔다.
  //
  // 각 줄의 `←` 오른쪽이 **그 증인이 살리는 대상**이다 — 여기서는 전부 이
  // 태스크의 `# PROVES:` 앵커다 (이 하네스의 단언에는 라벨이 없다).
  // 줄번호로 매지 않는다. scripts/lint_witness_map.py 가 참조 실재성만 재고
  // 「그 궤적이 정말 그 전건을 세우는가」는 재지 못한다.
  //
  // W1  ← Platform.state_machine_kept — 이양 커밋 도달 (원자성 단언의 전건).
  // W2  ← Platform.state_machine_kept — 회수 도달.
  // W3  ← Platform.owner_check — 장치 소유 상태가 실제로 관측된다. 이것이
  //       도달 불가능하면 조회 정의(유효 ∧ 태그 일치)는 늘 거짓인 우변으로
  //       자명하게 성립한다.
  // W4  ← Platform.owner_check — 결정의 목적 그 자체: 프레임 ≥ 2^31 인
  //       페이지도 장치 소유가 된다. 앞판 인코딩에서 이 증인은 **원리적으로
  //       도달 불가**였다 (전이 워드가 그 프레임을 표현하지 못한다).
  //       도달이 곧 「제3 상태 소멸」의 실측이다.
  // W5  ← Platform.state_machine_kept — 상위 비트를 든 이양 기입 도달
  //       (프레임 전폭이 전이 경로를 통과한다).
  // W6  ← Platform.state_machine_kept — 충돌 기입 형상 도달 (기입 무효화
  //       가지의 전건).
  // W7  ← Platform.state_machine_kept — 충돌 sticky fault 가 실제로 선다.
  // W8  ← Platform.state_machine_kept — RO 오프셋 기입 도달.
  // W9  ← Platform.state_machine_kept — RO 기입 sticky fault 가 실제로 선다.
  // W10 ← Platform.state_machine_kept — 무연산 항등(이미 소유한 슬롯에 SET):
  //       「명시 기입 사이클인데 전이가 없다」는 갈래가 실재한다.
  // W11 ← Platform.state_machine_kept — 무연산 항등의 CLR 면.
  // W12 ← Platform.state_machine_kept — WO 오프셋 읽기 도달 (조용함 단언의
  //       전건 $past(f_woRead)).
  always @(posedge clk) begin
    if (f_ok) begin
      w1_handoff:    cover (f_setWr && f_hit && !f_sVal);
      w2_reclaim:    cover (f_clrWr && f_hit && f_sVal && f_mine);
      w3_owned:      cover (io_query_devOwned);
      w4_owned_high: cover (io_query_devOwned && io_query_frame[31]);
      w5_set_high:   cover (f_setWr && f_hit && io_wdata[31] && !f_sVal);
      w6_collide:    cover (f_collide);
      w7_flt_col:    cover (io_faultCollide);
      w8_ro_write:   cover (f_statusWr);
      w9_flt_bad:    cover (io_faultBadWrite);
      w10_noop_set:  cover (f_setWr && f_hit && f_sVal && f_mine);
      w11_noop_clr:  cover (f_clrWr && f_hit && !f_sVal);
      w12_wo_read:   cover (f_woRead);
    end
  end
endmodule

// 형식 검증 톱 — 대상 + props 결선 (내부 포트는 sby [script] 의 expose 가 만든다).
module OwnershipTable_formal (
  input wire        clk,
  input wire        reset,
  input wire [11:0] io_addr,
  input wire        io_wstrobe,
  input wire [31:0] io_wdata,
  input wire        io_rstrobe,
  input wire [31:0] io_query_frame,
  input wire        io_faultClearCollide,
  input wire        io_faultClearBadWrite
);
  wire [31:0] io_rdata;
  wire        io_rvalid;
  wire        io_ready;
  wire        io_query_devOwned;
  wire        io_faultCollide;
  wire        io_faultBadWrite;
  wire [63:0] validBits;
  wire [25:0] tagVec_0,  tagVec_1,  tagVec_2,  tagVec_3,  tagVec_4,  tagVec_5,
              tagVec_6,  tagVec_7,  tagVec_8,  tagVec_9,  tagVec_10, tagVec_11,
              tagVec_12, tagVec_13, tagVec_14, tagVec_15, tagVec_16, tagVec_17,
              tagVec_18, tagVec_19, tagVec_20, tagVec_21, tagVec_22, tagVec_23,
              tagVec_24, tagVec_25, tagVec_26, tagVec_27, tagVec_28, tagVec_29,
              tagVec_30, tagVec_31, tagVec_32, tagVec_33, tagVec_34, tagVec_35,
              tagVec_36, tagVec_37, tagVec_38, tagVec_39, tagVec_40, tagVec_41,
              tagVec_42, tagVec_43, tagVec_44, tagVec_45, tagVec_46, tagVec_47,
              tagVec_48, tagVec_49, tagVec_50, tagVec_51, tagVec_52, tagVec_53,
              tagVec_54, tagVec_55, tagVec_56, tagVec_57, tagVec_58, tagVec_59,
              tagVec_60, tagVec_61, tagVec_62, tagVec_63;

  OwnershipTable dut (
    .io_addr(io_addr), .io_wstrobe(io_wstrobe), .io_wdata(io_wdata),
    .io_rstrobe(io_rstrobe), .io_rdata(io_rdata), .io_rvalid(io_rvalid),
    .io_ready(io_ready),
    .io_query_frame(io_query_frame), .io_query_devOwned(io_query_devOwned),
    .io_faultCollide(io_faultCollide), .io_faultClearCollide(io_faultClearCollide),
    .io_faultBadWrite(io_faultBadWrite), .io_faultClearBadWrite(io_faultClearBadWrite),
    .clk(clk), .reset(reset),
    // ── expose 로 올린 내부 상태 포트 ──
    .validBits(validBits),
    .tagVec_0(tagVec_0),   .tagVec_1(tagVec_1),   .tagVec_2(tagVec_2),   .tagVec_3(tagVec_3),
    .tagVec_4(tagVec_4),   .tagVec_5(tagVec_5),   .tagVec_6(tagVec_6),   .tagVec_7(tagVec_7),
    .tagVec_8(tagVec_8),   .tagVec_9(tagVec_9),   .tagVec_10(tagVec_10), .tagVec_11(tagVec_11),
    .tagVec_12(tagVec_12), .tagVec_13(tagVec_13), .tagVec_14(tagVec_14), .tagVec_15(tagVec_15),
    .tagVec_16(tagVec_16), .tagVec_17(tagVec_17), .tagVec_18(tagVec_18), .tagVec_19(tagVec_19),
    .tagVec_20(tagVec_20), .tagVec_21(tagVec_21), .tagVec_22(tagVec_22), .tagVec_23(tagVec_23),
    .tagVec_24(tagVec_24), .tagVec_25(tagVec_25), .tagVec_26(tagVec_26), .tagVec_27(tagVec_27),
    .tagVec_28(tagVec_28), .tagVec_29(tagVec_29), .tagVec_30(tagVec_30), .tagVec_31(tagVec_31),
    .tagVec_32(tagVec_32), .tagVec_33(tagVec_33), .tagVec_34(tagVec_34), .tagVec_35(tagVec_35),
    .tagVec_36(tagVec_36), .tagVec_37(tagVec_37), .tagVec_38(tagVec_38), .tagVec_39(tagVec_39),
    .tagVec_40(tagVec_40), .tagVec_41(tagVec_41), .tagVec_42(tagVec_42), .tagVec_43(tagVec_43),
    .tagVec_44(tagVec_44), .tagVec_45(tagVec_45), .tagVec_46(tagVec_46), .tagVec_47(tagVec_47),
    .tagVec_48(tagVec_48), .tagVec_49(tagVec_49), .tagVec_50(tagVec_50), .tagVec_51(tagVec_51),
    .tagVec_52(tagVec_52), .tagVec_53(tagVec_53), .tagVec_54(tagVec_54), .tagVec_55(tagVec_55),
    .tagVec_56(tagVec_56), .tagVec_57(tagVec_57), .tagVec_58(tagVec_58), .tagVec_59(tagVec_59),
    .tagVec_60(tagVec_60), .tagVec_61(tagVec_61), .tagVec_62(tagVec_62), .tagVec_63(tagVec_63)
  );

  // ── anyconst 슬롯과 그 슬롯의 태그 — 여기서 만든다 ────────────────────
  //
  // 슬롯 사영을 *래퍼*에서 하는 이유는 비용이다. props 안에서
  // `f_tags[26*f_slot +: 26]` 로 뽑으면 26 이 2의 거듭제곱이 아니라 상수
  // 곱셈기 + 1664b 배럴 시프터가 서고, 그것을 BMC 가 매 스텝 펼친다 —
  // 실측으로 basecase/bmc 가 스텝 5 에서 분 단위로 멎었다 (induction 과
  // cover 는 통과). 아래 64:1 case 먹스는 26 × 63 먹스로 끝난다.
  //
  // 사영은 증명을 약화시키지 않는다 — f_slot 이 anyconst(자유 상수)이므로
  // 「f_slot 을 겨냥한 모든 실행」에 대한 증명이 곧 64 슬롯 전칭 증명이다.
  // ResultBank_props.sv 의 store 축과 같은 형태·같은 논거다.
  (* anyconst *) wire [5:0] f_slot;
  reg [25:0] f_sTag;
  always @(*) begin
    case (f_slot)
      6'd0: f_sTag=tagVec_0;   6'd1: f_sTag=tagVec_1;   6'd2: f_sTag=tagVec_2;
      6'd3: f_sTag=tagVec_3;   6'd4: f_sTag=tagVec_4;   6'd5: f_sTag=tagVec_5;
      6'd6: f_sTag=tagVec_6;   6'd7: f_sTag=tagVec_7;   6'd8: f_sTag=tagVec_8;
      6'd9: f_sTag=tagVec_9;   6'd10:f_sTag=tagVec_10;  6'd11:f_sTag=tagVec_11;
      6'd12:f_sTag=tagVec_12;  6'd13:f_sTag=tagVec_13;  6'd14:f_sTag=tagVec_14;
      6'd15:f_sTag=tagVec_15;  6'd16:f_sTag=tagVec_16;  6'd17:f_sTag=tagVec_17;
      6'd18:f_sTag=tagVec_18;  6'd19:f_sTag=tagVec_19;  6'd20:f_sTag=tagVec_20;
      6'd21:f_sTag=tagVec_21;  6'd22:f_sTag=tagVec_22;  6'd23:f_sTag=tagVec_23;
      6'd24:f_sTag=tagVec_24;  6'd25:f_sTag=tagVec_25;  6'd26:f_sTag=tagVec_26;
      6'd27:f_sTag=tagVec_27;  6'd28:f_sTag=tagVec_28;  6'd29:f_sTag=tagVec_29;
      6'd30:f_sTag=tagVec_30;  6'd31:f_sTag=tagVec_31;  6'd32:f_sTag=tagVec_32;
      6'd33:f_sTag=tagVec_33;  6'd34:f_sTag=tagVec_34;  6'd35:f_sTag=tagVec_35;
      6'd36:f_sTag=tagVec_36;  6'd37:f_sTag=tagVec_37;  6'd38:f_sTag=tagVec_38;
      6'd39:f_sTag=tagVec_39;  6'd40:f_sTag=tagVec_40;  6'd41:f_sTag=tagVec_41;
      6'd42:f_sTag=tagVec_42;  6'd43:f_sTag=tagVec_43;  6'd44:f_sTag=tagVec_44;
      6'd45:f_sTag=tagVec_45;  6'd46:f_sTag=tagVec_46;  6'd47:f_sTag=tagVec_47;
      6'd48:f_sTag=tagVec_48;  6'd49:f_sTag=tagVec_49;  6'd50:f_sTag=tagVec_50;
      6'd51:f_sTag=tagVec_51;  6'd52:f_sTag=tagVec_52;  6'd53:f_sTag=tagVec_53;
      6'd54:f_sTag=tagVec_54;  6'd55:f_sTag=tagVec_55;  6'd56:f_sTag=tagVec_56;
      6'd57:f_sTag=tagVec_57;  6'd58:f_sTag=tagVec_58;  6'd59:f_sTag=tagVec_59;
      6'd60:f_sTag=tagVec_60;  6'd61:f_sTag=tagVec_61;  6'd62:f_sTag=tagVec_62;
      6'd63:f_sTag=tagVec_63;
    endcase
  end

  OwnershipTable_props u_own_props (
    .clk                   (clk),
    .reset                 (reset),
    .io_addr               (io_addr),
    .io_wstrobe            (io_wstrobe),
    .io_wdata              (io_wdata),
    .io_rstrobe            (io_rstrobe),
    .io_ready              (io_ready),
    .io_query_frame        (io_query_frame),
    .io_query_devOwned     (io_query_devOwned),
    .io_faultCollide       (io_faultCollide),
    .io_faultClearCollide  (io_faultClearCollide),
    .io_faultBadWrite      (io_faultBadWrite),
    .io_faultClearBadWrite (io_faultClearBadWrite),
    .f_valid               (validBits),
    .f_slot                (f_slot),
    .f_sTag                (f_sTag)
  );
endmodule

`default_nettype wire
