// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// CompletionUnit 후-formal 하네스 (§6.3) — 완료 디스크립터 축.
//
// ══ 이 하네스가 왜 이번에 서는가 ═══════════════════════════════════════════
//
// 완료 디스크립터·명령 링에 후-formal 태스크가 **0건**이었다 (직전 파도 인계
// 사항). 호스트 ABI 결정 5(2026-08-25)가 그 공백 위에서 디스크립터 배치를
// 바꾼다 — 워드 정렬 + 선두 kind 바이트 + 「장치가 32 B 전량을 기입한다」.
// 배치를 바꾸면서 재는 것을 만들지 않으면, 바뀐 것이 무엇을 보증하는지 아무도
// 모르는 상태가 그대로 이어진다 (§6.7 원칙 5: 미측정은 통과가 아니다).
//
// ══ 축 — 「전량 기입」과 「워드 배치」는 *한 등식*으로 닫힌다 ═══════════════
//
// 위험의 이름은 잔류다: 32 B 칸에 12 B 만 갱신하면 그 칸의 *이전 항목 태그가
// 남고*, 호스트는 그것을 새 완료로 읽는다 (§3.6.3 해설이 flush 에 대해 경계한
// 것과 같은 형태). 잔류의 *일반형*은 「그 칸에 원래 있던 임의의 내용」이고,
// 이 링 저장소에는 reset 이 없으므로 **형식 검사의 초기 상태가 바로 그 임의
// 잔류다.** 그래서 한 번의 push 만으로 잔류 검사가 성립한다 — 여덟 워드를
// 되읽어 전부가 *이번* 입력의 함수인지 보면 된다.
//
// 그 등식이 동시에 워드 배치 검사다. 되읽은 워드 i 를 검사자가 정본 배치로
// 독립 재구성한 값과 대조하므로:
//   · CD_KIND 가 선두이고 값이 `0x01` 인가 (그리고 나머지 24b 가 0 인가)
//   · 태그 세 워드(E.5.1 직렬화)가 CD_TAG0..2 에 서는가 — TAG1 = 스레드 ‖ LNID,
//     TAG2 = 예약 0 ‖ 정밀도 ‖ 차원
//   · CD_BASE·CD_TOTAL 이 각자 *워드 하나씩* 을 쓰는가 (총개수의 그릇이 32b)
//   · CD_RSV0·CD_RSV1 이 0 으로 *기입되는가*
// 가 한 assert 로 함께 잰다. 두 축을 따로 재면 「배치는 맞는데 일부 워드가
// 미기입」인 상태를 어느 쪽도 잡지 못한다 — 그 교집합이 정확히 위험 지점이다.
//
// 부분 기입은 초기 내용의 모델링 방식과 무관하게 잡힌다: 미기입 워드는 초기
// 내용을 내는데, 검사자가 기대하는 값은 입력 필드의 함수이고 그 입력은 자유다
// (예: lnid != 0 을 고르면 CD_TAG1 미기입이 즉시 반증된다). 초기 내용이 자유
// 변수든 0 이든 반례가 존재한다 — 예약 두 워드만이 「초기가 0 이면 구별 불가」
// 이며, 그 둘의 무해함은 값이 0 이라는 사실 자체가 준다.
//
// ══ 이 태스크가 재지 *않는* 것 — 정직 표기 ═════════════════════════════════
//
//  1. **명령 방향은 재지 않는다.** 명령 디스크립터를 조립하는 회로가 이
//     저장소에 없다 (E.1.3 UNWIRED 등재). 「태그 필드가 양방향에서 같은 상대
//     오프셋」의 *두 방향 대조*는 elaborate 시점 검사가 든다 (HostDesc 의
//     require) — 회로가 없는 쪽은 형식 검사가 잴 대상이 아니다. 여기서 재는
//     것은 그 프레임의 완료 방향 절반이다.
//  2. **k-귀납(prove)을 두지 않았다.** 되읽기 등식의 귀납 불변은
//     `ring[f_slot] == 그림자` 인데 링 저장소가 포트로 노출되지 않아 그것을
//     적을 수 없다. BMC 는 reset 부터 깊이 14 까지의 *모든* 실행을 전수로
//     재고, 위에 적었듯 잔류의 일반형이 그 초기 상태에 들어 있다. 「덮인 깊이
//     안에서 전수」와 「무한 깊이」의 차이를 여기 적어 둔다.
//  3. 창 밖 표면(드레인 집계 · IRQ 마스크 · 거절된 구성 기입)은 이 태스크의
//     축이 아니다. 후속 파도 몫이다.
//
// ══ 독립 재구성 원칙 — RTL 의 자기 판정을 믿지 않는다 ═══════════════════════
//
// 링 인코딩(빈/가득), 창 오프셋 디코드, 디스크립터 배치를 전부 1차 입력과
// 노출된 포인터(head·tail)에서 **다시 계산한다.** RTL 의 full/empty/isWindow/
// descWords 를 가져다 쓰지 않는다 — 가져다 쓰면 「디코드가 두 자리를 맞바꾼다」
// 부류의 결함을 하네스가 스스로 눈감는다 (OwnershipTable_props.sv 의 같은 절).
//
// ══ 부착 방식 — expose + 래퍼 (bind 미사용) ════════════════════════════════
//
// yosys 0.66 자유 프론트엔드는 `bind` 를 오류 없이 파싱하고 *조용히 버린다* —
// 이 저장소의 다른 하네스가 전부 그 실측 때문에 expose 로 옮겨 갔다. 공허가
// 아님은 design_prep.il 의 assert/cover 셀 수와 cover 증인 도달로 검산한다.

`default_nettype none

module CompletionUnit_props (
  input wire          clk,
  input wire          reset,
  // ── 1차 입력/관측 (DUT 포트) ──────────────────────────────────────────
  input wire [7:0]    io_addr,
  input wire          io_wstrobe,
  input wire [31:0]   io_wdata,
  input wire          io_rstrobe,
  input wire [31:0]   io_rdata,
  input wire          io_rvalid,
  input wire          io_ready,
  input wire          io_comp_valid,
  input wire [31:0]   io_comp_tag_wave,
  input wire [3:0]    io_comp_tag_epoch,
  input wire          io_comp_tag_poison,
  input wire          io_comp_tag_trace,
  input wire [15:0]   io_comp_tag_lnid,
  input wire [7:0]    io_comp_tag_precision,
  input wire [7:0]    io_comp_tag_dim,
  input wire [7:0]    io_comp_base,
  input wire [7:0]    io_comp_total,
  input wire          io_comp_ready,
  input wire          io_faultOverflow,
  input wire          io_faultClearOverflow,
  input wire          io_faultBadWrite,
  input wire          io_faultClearBadWrite,
  // ── expose 로 승격된 링 포인터 ────────────────────────────────────────
  input wire [2:0]    f_head,
  input wire [2:0]    f_tail,
  // ── anyconst 칸 (래퍼 소유) ───────────────────────────────────────────
  input wire [2:0]    f_slot
);
  // 형상 상수 — CompletionUnit(cqDepth = 8) ⇒ 포인터 3b. INV-T1 무관 (형식
  // 검사는 *이 형상*을 재는 자리다 — 형상 독립성은 lint_isa7 의 축).
  localparam [7:0] KIND_COMPLETION = 8'h01; // HostDesc.Kind.COMPLETION
  localparam [7:0] OFF_WINDOW      = 8'h40; // 완료 구역 안 창 시작 (E.1.2)

  // ── ENV assume: 단발 reset 프로토콜 (선례 HiuMask/OwnershipTable 동일 —
  // async-reset 레지스터의 형식 검사 초기화 규약. 그 외 assume 없음) ──
  reg f_init = 1'b1;
  always @(posedge clk) f_init <= 1'b0;
  always @(*) begin
    if (f_init) assume (reset);
    else        assume (!reset);
  end

  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;
  reg f_reset_d = 1'b1;
  always @(posedge clk) f_reset_d <= reset;
  wire f_ok = f_past_valid && !reset && !f_reset_d;

  // ── 링 인코딩의 독립 재구성 (E.5 1·2항) ───────────────────────────────
  // head == tail 이 빈 링, (tail+1) mod size == head 가 가득. 크기가 2^k 라
  // 나머지 연산이 포인터 폭의 wrap 그 자체다 — 아래 덧셈에 마스크가 없는
  // 것이 그 사실의 형태다 (E.5 1항이 2의 거듭제곱을 고른 이유).
  wire [2:0] f_tail_p1 = f_tail + 3'd1;
  wire       f_full    = (f_tail_p1 == f_head);
  wire       f_empty   = (f_tail    == f_head);
  wire       f_push    = io_comp_valid && !f_full;
  wire       f_shove   = io_comp_valid &&  f_full; // 가득인 링에 밀어 넣기

  // ── 창 읽기의 독립 재구성 — 오프셋 디코드까지 검사 대상에 넣는다 ──────
  wire       f_acceptR = (!io_wstrobe) && io_rstrobe; // 동시 제시면 쓰기 우선
  wire       f_aligned = (io_addr[1:0] == 2'b00);
  wire       f_isWin   = (io_addr[7:5] == OFF_WINDOW[7:5]);
  wire [2:0] f_winWord = io_addr[4:2];
  wire       f_winRead = f_acceptR && f_aligned && f_isWin && !f_empty;

  // ── 그림자 — anyconst 칸에 대한 *마지막* 기입의 입력 필드 ──────────────
  //
  // 디스크립터가 아니라 *입력 필드*를 붙든다. 그래야 기대값이 검사자 쪽 재구성
  // 이 되고, RTL 의 조립을 RTL 의 조립으로 대조하는 항진명제가 되지 않는다.
  //
  // 「마지막 기입」으로 족한 근거: head == f_slot 이고 링이 비어 있지 않으면
  // 그 칸은 살아 있는 항목이고, 살아 있는 칸은 head 가 지나가기 전까지 다시
  // 기입되지 않는다 (가득 검사가 tail 의 head 추월을 막는다). 즉 그때 칸의
  // 내용은 f_slot 에 대한 마지막 기입과 같다.
  reg        f_written = 1'b0;
  reg [31:0] s_wave;
  reg [15:0] s_lnid;
  reg [3:0]  s_epoch;
  reg        s_trace;
  reg        s_poison_in; // 입력 poison — 기대값에 *쓰지 않는다* (증인 W9 의 전건 전용)
  reg [7:0]  s_prec, s_dim, s_base, s_total;
  always @(posedge clk) begin
    if (reset) begin
      f_written <= 1'b0;
    end else if (f_push && (f_tail == f_slot)) begin
      f_written <= 1'b1;
      s_wave    <= io_comp_tag_wave;
      s_epoch   <= io_comp_tag_epoch;
      s_trace   <= io_comp_tag_trace;
      s_poison_in <= io_comp_tag_poison;
      s_lnid    <= io_comp_tag_lnid;
      s_prec    <= io_comp_tag_precision;
      s_dim     <= io_comp_tag_dim;
      s_base    <= io_comp_base;
      s_total   <= io_comp_total;
    end
  end

  // ── 정본 배치의 독립 재구성 (부록 E.5.1 직렬화 + E.5.2 kind + E.5.3 배치) ──
  // +0x00 CD_KIND   [7:0] kind = 0x01 · [31:8] 예약 = 0
  // +0x04 CD_TAG0   [31:0] wave 번호
  // +0x08 CD_TAG1   [31:28] 에포크 · [27] poison(장치 저작 — 원천 0건이라 0) · [26] trace ·
  //                 [25:16] 예약 = 0 · [15:0] LNID   (태그 코덱 전파 파도 — D2c 수리)
  // +0x0C CD_TAG2   [31:16] 예약 = 0 · [15:8] 정밀도 · [7:0] 차원
  // +0x10 CD_BASE   [7:0] 결속 LBID · [31:8] 예약 = 0
  // +0x14 CD_TOTAL  [31:0] 조각 선언 총개수 (폭 미확정 값의 그릇 — 상위 0 확장)
  // +0x18 CD_RSV0   예약 = 0
  // +0x1C CD_RSV1   예약 = 0
  function automatic [31:0] f_exp(input [2:0] i);
    case (i)
      3'd0:    f_exp = {24'd0, KIND_COMPLETION};
      3'd1:    f_exp = s_wave;
      3'd2:    f_exp = {s_epoch, 1'b0, s_trace, 10'd0, s_lnid}; // 입력 poison 을 반향하지 않는다
      3'd3:    f_exp = {16'd0, s_prec, s_dim};
      3'd4:    f_exp = {24'd0, s_base};
      3'd5:    f_exp = {24'd0, s_total};
      default: f_exp = 32'd0; // CD_RSV0 · CD_RSV1 — 0 을 *기입한다*
    endcase
  endfunction

  // ══ 축 1 — 배압은 링 인코딩 그 자체다 (E.5 2항 · §2.6) ═════════════════
  // ready 가 재구성된 「가득」의 부정과 정확히 같다. 어긋나면 상류가 잘못된
  // 시점에 정지하거나(진행성 손실) 가득인 링에 밀어 넣는다(오버플로).
  always @(*) begin
    if (f_past_valid && !reset) begin
      assert (io_comp_ready == !f_full);
    end
  end

  // ══ 축 2 — 링 칸 전량 기입 · 잔류 부재 · 워드 배치 (한 등식) ═══════════
  //
  // 이 하네스의 머리 속성이다. 창이 낸 워드가 *이번* 입력으로 재구성한 값과
  // 같다 ⇒ 그 워드는 이번 기입의 함수다 ⇒ 여덟 워드 전부에 대해 성립하면
  // 이전 항목의 어느 워드도 남지 않았다.
  always @(posedge clk) begin
    if (f_ok) begin
      if ($past(f_winRead) && ($past(f_head) == f_slot) && $past(f_written)) begin
        assert (io_rvalid);
        assert (io_rdata == f_exp($past(f_winWord)));
      end
    end
  end

  // ══ 축 2b — CD_TAG1 의 장치 저작 · 예약 자리 (E.5.3 · 1.4.4 poison 6항 · D2c) ═══
  // 축 2 의 등식이 이미 워드 전량을 재지만, D2c 의 두 비트 부류를 이름으로 남긴다 —
  // [27] poison 은 장치 저작이고 원천이 0건이라 0 (입력 사이드밴드의 poison 을 반향하면
  // 반례), [25:16] 은 예약 = 0 (옛 코덱은 스레드 ID 상위 비트를 여기 냈다). 그리고 [26]
  // trace 와 [31:28] 에포크는 호스트 저작이라 *보존*된다 (1.4.4 「trace 는 보존된다」).
  always @(posedge clk) begin
    if (f_ok) begin
      if ($past(f_winRead) && ($past(f_head) == f_slot) && $past(f_written) && ($past(f_winWord) == 3'd2)) begin
        a_cd_tag1_poison0: assert (io_rdata[27] == 1'b0);
        a_cd_tag1_rsv0:    assert (io_rdata[25:16] == 10'd0);
        a_cd_tag1_trace:   assert (io_rdata[26] == s_trace);
        a_cd_tag1_epoch:   assert (io_rdata[31:28] == s_epoch);
      end
    end
  end

  // ══ 축 3 — 빈 링은 저장소를 관측면에 내지 않는다 (E.1.2 창 행) ═════════
  // 미기입 저장소(= 임의 내용)가 창으로 새는 경로의 부재. 축 2 와 짝이다:
  // 살아 있는 칸은 *이번 기입*을 내고, 살아 있지 않으면 아무것도 내지 않는다.
  always @(posedge clk) begin
    if (f_ok) begin
      if ($past(f_acceptR) && $past(f_aligned) && $past(f_isWin) && $past(f_empty)) begin
        assert (io_rdata == 32'd0);
      end
    end
  end

  // ══ 축 3b — 비정렬 읽기는 0 (파도 4 W6) ═══════════════════════════════
  // 03-hiu.typ:874 「비정렬 *읽기*는 0 · fault 없음이다」 — 창을 포함한 구역 어디서든 주소 하위 두
  // 비트가 0 이 아닌 수락 읽기의 응답은 rvalid + 0 이다. RTL 은 readValue 의 aligned 게이트와 winSel 의
  // aligned 항이 든다. 이 단언 전에는 그 규범을 재는 태스크가 없어 winSel 의 aligned 탈락(비어 있지 않은
  // 링의 0x341 읽기가 링 항목을 샌다 — 검토 변이 M12)이 이 태스크를 통과했다. fault 없음은 축 6 등식이 잰다.
  always @(posedge clk) begin
    if (f_ok) begin
      if ($past(f_acceptR) && !$past(f_aligned)) begin
        assert (io_rvalid);
        assert (io_rdata == 32'd0);
      end
    end
  end

  // ══ 축 4 — 생산 색인은 장치가, 그것도 수락 사이클에만 움직인다 (E.5 표) ══
  always @(posedge clk) begin
    if (f_ok) begin
      if ($past(f_push)) assert (f_tail == ($past(f_tail) + 3'd1));
      else               assert (f_tail == $past(f_tail));
    end
  end

  // ══ 축 5 — 오버플로: loud sticky · 링 상태 불변 (E.5 · §3.8 · FAB-10 동형) ══
  // 밀어 넣어진 항목은 저장에 닿지 않는다 — 그 관측 가능한 절반이 「tail 이
  // 움직이지 않는다」이고, 축 4 가 그것을 이미 전칭으로 든다 (shove ⇒ !push).
  // 여기서는 sticky 의 두 요건을 잰다: 발화에 선다 / 명시적 해제 외엔 안 내린다.
  always @(posedge clk) begin
    if (f_ok) begin
      if ($past(f_shove)) assert (io_faultOverflow); // 해제와 겹쳐도 발화가 이긴다
      if ($past(io_faultOverflow) && !$past(io_faultClearOverflow))
        assert (io_faultOverflow);
    end
  end

  // ══ 축 6 — 거절된 구성 기입: 정확한 차기 상태 등식 (E.1.1 · 파도 4 판정 T1-i · T2) ══
  // 거절 사유를 정본 표로 *독립 재구성*한다 — RTL 의 isRoOff · badWrite 를 참조하지 않는다.
  //   비정렬 쓰기 (판정 T2 (a) — sub-word 쓰기의 장치 포트 표현, 구역 안 어디서든)
  //   RO 오프셋 쓰기 — CQ_TAIL · IRQ_STATUS · 엔트리 창 · 드레인 여섯 · CQ_OCC · DRAIN_ALLZERO
  //   소비 회로 없는 RW 워드 — CQ_BASE_LO/HI (판정 T1-i β · 정본 E.1.3 규범 끝)
  //   예약 비트 비0 · 이행 불가 CQ_SIZE 값 (log2 8 = 3 이 아닌 값)
  // 등식이 양방향이라 「표에 없는 정렬 오프셋 쓰기 · 적법한 기입은 sticky 를 세우지 않는다」
  // (예약 오프셋 관대)와 「발화가 해제를 이긴다」가 함께 선다.
  wire f_wAl    = io_wstrobe && f_aligned;
  wire f_roOff  = (io_addr == 8'h10) || (io_addr == 8'h20) || (io_addr[7:5] == 3'd2) ||
                  ((io_addr >= 8'h60) && (io_addr <= 8'h74)) || (io_addr == 8'h78) || (io_addr == 8'h7C);
  wire f_base   = (io_addr == 8'h00) || (io_addr == 8'h04);
  wire f_sizeBd = (io_addr == 8'h08) && ((io_wdata[31:5] != 27'd0) || (io_wdata[4:0] != 5'd3));
  wire f_rsvBd  = ((io_addr == 8'h24) || (io_addr == 8'h28)) && (io_wdata[31:1] != 31'd0);
  wire f_unalW  = io_wstrobe && !f_aligned;
  wire f_badWr  = f_unalW || (f_wAl && (f_roOff || f_base || f_sizeBd || f_rsvBd));
  always @(posedge clk) begin
    if (f_ok) begin
      assert (io_faultBadWrite == ($past(f_badWr) || ($past(io_faultBadWrite) && !$past(io_faultClearBadWrite))));
    end
  end

  // ══ 비공허 증인 — 축 2 가 여덟 워드 *전부*에서 도달 가능한가 ════════════
  //
  // 셀 수가 0 이 아니라는 것만으로는 「그 assert 가 실제로 걸리는 실행이
  // 있는가」에 답하지 못한다. 아래 여덟 cover 가 그 답이다 — 하나라도 미도달
  // 이면 축 2 는 그 워드에서 공허하다.
  //
  // 각 줄의 `←` 오른쪽이 **그 증인이 살리는 대상**이다: `<Module>.<name>` 은
  // 이 태스크의 `# VERIFIES:` 앵커다 (이 하네스의 단언에는 라벨이 없다).
  // 줄번호로 매지 않는다. scripts/lint_witness_map.py 가 참조 실재성만 재고
  // 「그 궤적이 정말 그 전건을 세우는가」는 재지 못한다.
  //
  // W1 ← CompletionUnit.desc_full_write · CompletionUnit.desc_word_layout
  //      워드 0..7 각각의 되읽기가 도달한다 (한 태그 아래 라벨 여덟 —
  //      워드마다 따로 세지 않으면 미도달 워드가 도달 워드에 가린다).
  //      워드 하나가 미도달이면 그 워드의 배치 등식은 한 번도 걸리지 않은 채
  //      통과한다.
  always @(posedge clk) begin
    if (f_ok && $past(f_winRead) && ($past(f_head) == f_slot) && $past(f_written)) begin
      w1_word0: cover ($past(f_winWord) == 3'd0);
      w1_word1: cover ($past(f_winWord) == 3'd1);
      w1_word2: cover ($past(f_winWord) == 3'd2);
      w1_word3: cover ($past(f_winWord) == 3'd3);
      w1_word4: cover ($past(f_winWord) == 3'd4);
      w1_word5: cover ($past(f_winWord) == 3'd5);
      w1_word6: cover ($past(f_winWord) == 3'd6);
      w1_word7: cover ($past(f_winWord) == 3'd7);
    end
  end

  // 나머지 증인 — 가득/오버플로/빈 창이 실제로 도달하는가.
  // W2 ← CompletionUnit.ring_encoding — 「가득」 상태에 실제로 닿는다.
  //      닿지 못하면 배압 등가와 가득 재구성은 늘 거짓인 우변으로 자명하다.
  // W3 ← CompletionUnit.overflow_sticky — 오버플로 sticky 가 실제로 선다
  //      (두 sticky 단언의 전건).
  // W4 ← CompletionUnit.window_no_leak · CompletionUnit.ring_encoding —
  //      빈 링의 창 읽기가 도달한다. 이것이 없으면 「빈 창은 0」은 창 읽기
  //      자체가 없는 세계에서 자명하다.
  // W5 ← CompletionUnit.desc_full_write · CompletionUnit.desc_word_layout —
  //      태그 워드가 *전부 비영*인 항목의 되읽기: 「0 을 0 으로 맞히는」
  //      항진 증인이 아니라는 것을 이 하나가 보인다.
  // W6 ← MmioPage.unaligned_rejected — 판정 T2 (a): 비정렬 쓰기가 거절 sticky 를 처음 세운다.
  // W7 ← MmioPage.nocons_rejected — 판정 T1-i β: CQ_BASE_HI(+0x04) 정렬 쓰기가 거절 sticky 를
  //      처음 세운다 (소비 회로 없는 RW 워드 — 옛 처분은 조용한 흡수였다).
  // W9 ← CompletionUnit.cd_tag1_device_authored · CompletionUnit.desc_word_layout — 입력 사이드밴드의
  //      poison 이 1 인 항목의 CD_TAG1 을 되읽는다. 이것 없이는 a_cd_tag1_poison0 이 「입력 poison 이
  //      늘 0 인 세계」에서 자명하다 (D2c 이전 기계를 가를 전건).
  // W10 ← CompletionUnit.cd_tag1_device_authored — trace 가 1 인 항목의 CD_TAG1 되읽기 (보존 방향 전건).
  // W8 ← CompletionUnit.unaligned_read_zero — 비어 있지 않은 링의 창을 비정렬로 읽는다 (정렬이면 링 항목
  //      워드가 나올 자리 — 「0 을 내는 읽기」가 빈 창 · 창 밖에서만 서는 공허를 막는다).
  always @(posedge clk) begin
    if (f_ok) begin
      w2_full:         cover (f_full);
      w3_overflow:     cover (io_faultOverflow);
      w4_empty_window: cover ($past(f_acceptR) && $past(f_isWin) && $past(f_empty));
      w5_nonzero_tags: cover ($past(f_winRead) && ($past(f_head) == f_slot) && $past(f_written)
             && (s_wave != 32'd0) && (s_lnid != 16'd0) && (s_total != 8'd0));
      w6_unal_wr:      cover (io_faultBadWrite && !$past(io_faultBadWrite) && $past(f_unalW));
      w7_base_wr:      cover (io_faultBadWrite && !$past(io_faultBadWrite) && $past(f_wAl && (io_addr == 8'h04)));
      w8_unal_rd:      cover ($past(f_acceptR && !f_aligned && f_isWin && !f_empty) && io_rvalid);
      w9_poison_in:    cover ($past(f_winRead) && ($past(f_head) == f_slot) && $past(f_written) && ($past(f_winWord) == 3'd2) && s_poison_in);
      w10_trace_in:    cover ($past(f_winRead) && ($past(f_head) == f_slot) && $past(f_written) && ($past(f_winWord) == 3'd2) && s_trace && (s_epoch != 4'd0));
    end
  end
endmodule

// 형식 검증 톱 — 대상 + props 결선 (내부 포트는 sby [script] 의 expose 가 만든다).
module CompletionUnit_formal (
  input wire        clk,
  input wire        reset,
  input wire [7:0]  io_addr,
  input wire        io_wstrobe,
  input wire [31:0] io_wdata,
  input wire        io_rstrobe,
  input wire        io_comp_valid,
  input wire [31:0] io_comp_tag_wave,
  input wire [3:0]  io_comp_tag_epoch,
  input wire        io_comp_tag_poison,
  input wire        io_comp_tag_trace,
  input wire [15:0] io_comp_tag_lnid,
  input wire [7:0]  io_comp_tag_precision,
  input wire [7:0]  io_comp_tag_dim,
  input wire [7:0]  io_comp_base,
  input wire [7:0]  io_comp_total,
  input wire [15:0] io_drain_pipe,
  input wire [15:0] io_drain_pending,
  input wire [15:0] io_drain_output,
  input wire [15:0] io_drain_ownSlots,
  input wire [15:0] io_drain_contexts,
  input wire [15:0] io_drain_tokens,
  input wire        io_faultClearOverflow,
  input wire        io_faultClearBadWrite
);
  wire [31:0] io_rdata;
  wire        io_rvalid;
  wire        io_ready;
  wire        io_comp_ready;
  wire        io_irq;
  wire        io_faultOverflow;
  wire        io_faultBadWrite;
  // expose 가 올린 링 포인터
  wire [2:0]  head;
  wire [2:0]  tail;

  CompletionUnit dut (
    .io_addr(io_addr), .io_wstrobe(io_wstrobe), .io_wdata(io_wdata),
    .io_rstrobe(io_rstrobe), .io_rdata(io_rdata), .io_rvalid(io_rvalid),
    .io_ready(io_ready),
    .io_comp_valid(io_comp_valid),
    .io_comp_tag_wave(io_comp_tag_wave),
    .io_comp_tag_epoch(io_comp_tag_epoch),
    .io_comp_tag_poison(io_comp_tag_poison),
    .io_comp_tag_trace(io_comp_tag_trace),
    .io_comp_tag_lnid(io_comp_tag_lnid),
    .io_comp_tag_precision(io_comp_tag_precision),
    .io_comp_tag_dim(io_comp_tag_dim),
    .io_comp_base(io_comp_base),
    .io_comp_total(io_comp_total),
    .io_comp_ready(io_comp_ready),
    .io_irq(io_irq),
    .io_drain_pipe(io_drain_pipe), .io_drain_pending(io_drain_pending),
    .io_drain_output(io_drain_output), .io_drain_ownSlots(io_drain_ownSlots),
    .io_drain_contexts(io_drain_contexts), .io_drain_tokens(io_drain_tokens),
    .io_faultOverflow(io_faultOverflow),
    .io_faultClearOverflow(io_faultClearOverflow),
    .io_faultBadWrite(io_faultBadWrite),
    .io_faultClearBadWrite(io_faultClearBadWrite),
    .clk(clk), .reset(reset),
    // ── expose 로 올린 내부 상태 포트 ──
    .head(head), .tail(tail)
  );

  // anyconst 칸 — *임의 고정* 칸에 대한 증명 = 여덟 칸 보편 증명.
  // (ResultBank_props.sv 의 store 축 · OwnershipTable_props.sv 의 슬롯 축과
  //  같은 형태·같은 논거. 사영이 증명을 약화시키지 않는다.)
  (* anyconst *) wire [2:0] f_slot;

  CompletionUnit_props props (
    .clk(clk), .reset(reset),
    .io_addr(io_addr), .io_wstrobe(io_wstrobe), .io_wdata(io_wdata),
    .io_rstrobe(io_rstrobe), .io_rdata(io_rdata), .io_rvalid(io_rvalid),
    .io_ready(io_ready),
    .io_comp_valid(io_comp_valid),
    .io_comp_tag_wave(io_comp_tag_wave),
    .io_comp_tag_epoch(io_comp_tag_epoch),
    .io_comp_tag_poison(io_comp_tag_poison),
    .io_comp_tag_trace(io_comp_tag_trace),
    .io_comp_tag_lnid(io_comp_tag_lnid),
    .io_comp_tag_precision(io_comp_tag_precision),
    .io_comp_tag_dim(io_comp_tag_dim),
    .io_comp_base(io_comp_base),
    .io_comp_total(io_comp_total),
    .io_comp_ready(io_comp_ready),
    .io_faultOverflow(io_faultOverflow),
    .io_faultClearOverflow(io_faultClearOverflow),
    .io_faultBadWrite(io_faultBadWrite),
    .io_faultClearBadWrite(io_faultClearBadWrite),
    .f_head(head), .f_tail(tail), .f_slot(f_slot)
  );
endmodule

`default_nettype wire
