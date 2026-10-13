// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// XlateDoor 후-formal 하네스 — 변환 저장소의 문 → 표 끝-끝 (3.10 v1.0 묶음 RTL 파도 W3, 2026-10-13 ·
// 설계 결정 DP-13 (C)). 태스크: rtl/formal/sby/XlateDoor/door.sby (머리가 앵커 · 엔진 · 깊이를 소유한다).
// 선-formal 계약: rtl/formal/tla/XlateSurface.tla — Inv_AtMostOneValidPerVpn · Prop_V0Misses ·
// Prop_V1Hits · Prop_StallEnds 와 가드 commit_replaces_vpn · stall_independent.
//
// ## 왜 이 하네스가 따로 있는가
//
// 문(XlateStaging)은 props.sby 가, 저장(XlateStore)은 xlatestore.sby 가 각자의 포트에서 잰다.
// 그 둘을 잇는 조립 결선(Wt64Top xlateArea — VPN 분할 · ready 덮어쓰기)과 「문이 커밋한 것이
// 표에서 어떻게 보이는가」는 어느 단독 태스크도 재지 않는다. 조립 태스크(assembly.sby)는 hiu
// (XlateStore 내장)를 절단하므로 installSlotFree 가 자유 핀이 되어 정지 유계를 원리적으로 잴 수
// 없다 (「보증하지 않는 것」 (m)). 이 하네스가 그 틈을 메운다:
//   · 정지 유계 — 주소 · 상태 적법 COMMIT 의 ready 하강은 F_N(= 형상 파티션 수 — DP-21) 사이클 안에
//     풀린다 (d_stall_bounded). 조회 입력은 자유다 — 「다른 정지와 독립」(stall_independent):
//     조회 · 미적중 쪽이 무엇을 하든 성립해야 한다.
//   · (a) V=1 커밋 뒤 그 (파티션, VPN) 의 조회는 적중하고 값이 그 커밋의 것이다 (d_hit_live ·
//     d_hit_sound) — 사이에 그 파티션의 다른 커밋 · flush 가 없는 한.
//   · (b) V=0 커밋 뒤 그 (파티션, VPN) 의 조회는 미적중이다 (d_hit_sound — 그림자가 무효).
//   · 같은 VPN 재커밋 뒤 이중 유효 없음 — 관측형: 재커밋 뒤 적중 값은 언제나 마지막 커밋의 것이고
//     (d_hit_sound) 그 뒤 V=0 커밋이면 미적중이다 (같은 단언). 두 칸이 같은 키로 유효하면 둘 중
//     하나가 옛 값으로 적중하거나 V=0 뒤에 남은 칸이 적중한다 — 모델의 RTL 삭제 유비가 이중 유효
//     불변식이 아니라 (a)/(b) 위반으로 나타난다는 XlateSurface.tla 머리 「commit_replaces_vpn」 주의.
//
// ## 부착 — 래퍼 인스턴스 (bind 없음)
//
// 이 검사자가 XlateStaging(문)과 XlateStore(저장)를 **직접 인스턴스**하고 그 사이를 Wt64Top
// xlateArea 의 결선 *복제*로 잇는다 — 영역 선택 · 정렬 · 워드 오프셋 · COMMIT 워드 판정 · 설치
// 번들(idx = VPN[3:0] · tag = VPN[31:4] — XlateStore.idxOf/tagOf 의 기본 형상 값) · installReady =
// installSlotFree · ready 덮어쓰기. 복제가 실물과 같다는 것은 Wt64Top/assembly.sby 의
// VERIFIES Wt64Top.composite_wiring 이 핀 등식으로 잰다 (HiuMask_comp · RouteMmio 선례 — a_door_*).
// 두 모듈은 Wt64Top.sv 안에 있다 — `prep -top XlateDoor_check` 가 나머지를 지운다.
//
// ## 오라클 — 정본 · 모델 · 포트로만 짓는다
//
// 스테이징 그림자(f_vv · f_fv · f_lp · f_vpn · f_fr)는 XlateStaging_props.sv 와 같은 규칙으로 버스
// 이력에서 짓고(수락 = 스트로브 ∧ ready — ready 는 포트다), 추적 키 하나((f_kp, f_kvpn) — $anyconst)
// 의 정본 상태(f_kv · f_kfr · f_kperm · f_klive)를 커밋 · flush 의 버스 사건으로 갱신한다. DUT 의
// 내부 레지스터(stgVpnValid · fillPend · validBits …)는 한 번도 읽지 않는다.
//   f_kv    정본상 그 키가 유효일 *수 있다* — V=1 커밋이 세우고 V=0 커밋 · flush 가 내린다. 같은
//           파티션의 다른 VPN 커밋은 그 키를 축출할 *수* 있으나(직접 사상의 같은 칸 · 정본 (h)
//           「같은 파티션 COMMIT 의 결과」) 값을 바꾸지 않는다 — 적중하면 값은 f_kfr 이어야 한다.
//   f_klive 정본상 그 키가 *반드시* 유효하다 — V=1 커밋이 세우고 같은 파티션의 다른 커밋 ·
//           flush · V=0 이 내린다.
//
// 정본 (좌표 뒤 「」 는 그 줄의 축자):
//   e-defined.typ:310 「같은 (파티션, VPN) 에 두 항목이 동시에 적중하지 않는다 — 뒤 커밋이 앞 항목을 대체한다」
//   e-defined.typ:310 「V=0 COMMIT 뒤 같은 (파티션, VPN) 조회는 반드시 미적중이다.」
//   e-defined.typ:310 「축출은 같은 파티션 안에서만 일어난다」
//   e-defined.typ:308 「정지 중에는 효과가 없고, 수락되면 커밋되며, 드롭하지 않는다」
//   e-defined.typ:308 「호스트 조치에 기대지 않고 다른 정지(미적중 정지 · 초기화 소거 구간)와 독립이다」
//
// 문체: yosys 개방판은 SVA 시퀀스를 받지 않으므로 즉시 단언(always + $past).
module XlateDoor_check (
  input logic        clk,
  input logic        reset,
  // MMIO 쓰기 — 자유 (읽기는 이 하네스 밖: 문 구역 읽기는 ready 를 낮추지 않는다 — assembly)
  input logic        io_mmio_wstrobe,
  input logic [11:0] io_mmio_addr,
  input logic [31:0] io_mmio_wdata,
  // 조회 — 자유 (HiuPipeline 의 조회 · 미적중 정지 쪽이 무엇을 하든)
  input logic        io_lookup_valid,
  input logic [1:0]  io_lookup_part,
  input logic [31:0] io_lookup_vpn,
  input logic        io_hostRsp_valid,
  input logic [31:0] io_hostRsp_frame,
  input logic        io_hostRsp_perm_r,
  input logic        io_hostRsp_perm_w,
  input logic        io_hostRsp_perm_x
);
  localparam PARTS = 4;   // 기본 형상 파티션 수 (xlateParts)
  localparam F_N   = 4;   // DP-21 — 「설치가 오지 않는 동안 ≤ xlateParts 사이클」
  // ENV: 기계는 reset 에서 시작한다. bmc · cover · 정지 축 prove 의 유일한 assume 이다 (추적 키는 $anyconst 둘 —
  // 정의역 전부가 실재). 표 축 prove 만 조회 주소 = 추적 키 assume 하나를 더한다 (아래 XLATEDOOR_HIT).
  initial assume (reset);

  logic f_past_valid = 1'b0;
  logic f_past_reset = 1'b1;
  always @(posedge clk) begin
    f_past_valid <= 1'b1;
    f_past_reset <= reset;
  end
  wire f_step = f_past_valid && !reset && !f_past_reset;

  // ── Wt64Top xlateArea 결선 복제 (composite_wiring 이 실물과 대조) ───────────
  wire        aligned = (io_mmio_addr[1:0] == 2'd0);
  wire        selXent = (io_mmio_addr[11:9] == 3'b110);     // 0xC00–0xDFF
  wire        selXctl = (io_mmio_addr[11:7] == 5'b11100);   // 0xE00–0xE7F
  wire        wrEnt   = io_mmio_wstrobe && selXent && aligned;
  wire        wrCtl   = io_mmio_wstrobe && selXctl && aligned;
  wire        isCommit = (io_mmio_addr[6:2] == 5'd2);       // 기저 안 워드 COMMIT

  wire        xs_needReady, xs_commit_valid, xs_commit_perm_r, xs_commit_perm_w, xs_commit_perm_x;
  wire        xs_commit_v, xs_flush_valid, xs_missClr, xs_badWrite, xs_badData;
  wire [1:0]  xs_commit_part, xs_flush_part;
  wire [31:0] xs_commit_vpn, xs_commit_frame;
  wire        st_installSlotFree, st_install_ready;
  wire        st_rsp_hit, st_rsp_fromFill, st_rsp_perm_r, st_rsp_perm_w, st_rsp_perm_x;
  wire [31:0] st_rsp_frame;
  wire        st_rsp_hostPresent, st_rsp_hostPerm_r, st_rsp_hostPerm_w, st_rsp_hostPerm_x;
  wire [31:0] st_rsp_hostFrame;

  XlateStaging xstg (
    .io_wrEnt(wrEnt), .io_wrCtl(wrCtl), .io_woff(io_mmio_addr[8:2]), .io_wdata(io_mmio_wdata),
    .io_installReady(st_installSlotFree), .io_needReady(xs_needReady),
    .io_commit_valid(xs_commit_valid), .io_commit_part(xs_commit_part),
    .io_commit_vpn(xs_commit_vpn), .io_commit_frame(xs_commit_frame),
    .io_commit_perm_r(xs_commit_perm_r), .io_commit_perm_w(xs_commit_perm_w),
    .io_commit_perm_x(xs_commit_perm_x), .io_commit_v(xs_commit_v),
    .io_flush_valid(xs_flush_valid), .io_flush_part(xs_flush_part),
    .io_missClr(xs_missClr), .io_badWrite(xs_badWrite), .io_badData(xs_badData),
    .clk(clk), .reset(reset)
  );

  XlateStore store (
    .io_lookup_valid(io_lookup_valid), .io_lookup_part(io_lookup_part), .io_lookup_vpn(io_lookup_vpn),
    .io_rsp_hit(st_rsp_hit), .io_rsp_fromFill(st_rsp_fromFill), .io_rsp_frame(st_rsp_frame),
    .io_rsp_perm_r(st_rsp_perm_r), .io_rsp_perm_w(st_rsp_perm_w), .io_rsp_perm_x(st_rsp_perm_x),
    .io_rsp_hostPresent(st_rsp_hostPresent), .io_rsp_hostFrame(st_rsp_hostFrame),
    .io_rsp_hostPerm_r(st_rsp_hostPerm_r), .io_rsp_hostPerm_w(st_rsp_hostPerm_w),
    .io_rsp_hostPerm_x(st_rsp_hostPerm_x),
    .io_hostRsp_valid(io_hostRsp_valid), .io_hostRsp_frame(io_hostRsp_frame),
    .io_hostRsp_perm_r(io_hostRsp_perm_r), .io_hostRsp_perm_w(io_hostRsp_perm_w),
    .io_hostRsp_perm_x(io_hostRsp_perm_x),
    .io_install_valid(xs_commit_valid), .io_install_ready(st_install_ready),
    .io_install_part(xs_commit_part),
    .io_install_idx(xs_commit_vpn[3:0]),          // XlateStore.idxOf(vpn, idxW = 4)
    .io_install_tag(xs_commit_vpn[31:4]),         // XlateStore.tagOf(vpn, idxW = 4)
    .io_install_frame(xs_commit_frame),
    .io_install_perm_r(xs_commit_perm_r), .io_install_perm_w(xs_commit_perm_w),
    .io_install_perm_x(xs_commit_perm_x), .io_install_v(xs_commit_v),
    .io_flush_valid(xs_flush_valid), .io_flush_part(xs_flush_part),
    .installSlotFree(st_installSlotFree),
    .clk(clk), .reset(reset)
  );

  // ready 덮어쓰기 복제 — when(wrEnt ∧ isCommit ∧ needReady) io.mmio.ready := installSlotFree.
  // 이 문 구역 밖의 ready 는 이 하네스의 관심 밖이라 1 로 둔다.
  wire ready = (wrEnt && isCommit && xs_needReady) ? st_installSlotFree : 1'b1;
  wire acc   = io_mmio_wstrobe && ready;      // 버스 수락

  // ── 버스 사건 — 정본 배치에서 다시 짓는다 ───────────────────────────────
  wire [1:0] p   = io_mmio_addr[8:7];
  wire [4:0] w   = io_mmio_addr[6:2];
  wire vpnW  = wrEnt && (w == 5'd0);
  wire frW   = wrEnt && (w == 5'd1);
  wire cmW   = wrEnt && (w == 5'd2);
  wire vhW   = wrEnt && (w == 5'd3);
  wire flW   = wrCtl && (w == 5'd0);
  wire flOk  = (io_mmio_wdata[31:8] == 24'd0) && (io_mmio_wdata[7:0] < PARTS);

  // ── 그림자 스테이징 (XlateStaging_props.sv 와 같은 규칙 — 기본 형상이라 기저는 전부 실재) ──
  logic        f_vv  = 1'b0;
  logic        f_fv  = 1'b0;
  logic [1:0]  f_lp  = 2'd0;
  logic [31:0] f_vpn = 32'd0;
  logic [31:0] f_fr  = 32'd0;
  wire pairOk  = f_vv && (f_lp == p);
  wire cmLegal = cmW && pairOk;                                  // 주소 · 상태 적법 (정지 대상)
  wire cmBad   = (io_mmio_wdata[27:0] != 28'd0) || (io_mmio_wdata[31] && !f_fv);
  wire cmOk    = cmLegal && acc && !cmBad;                       // 정본상 커밋되는 COMMIT
  wire vpnAcc  = vpnW && acc;
  wire frAcc   = frW && acc && pairOk;
  wire vhAcc   = vhW && acc && pairOk && (io_mmio_wdata == 32'd0);
  wire flAcc   = flW && acc && flOk;
  always @(posedge clk) begin
    if (reset) begin
      f_vv <= 1'b0;
      f_fv <= 1'b0;
    end else begin
      if (vpnAcc) begin
        f_vv <= 1'b1; f_fv <= 1'b0; f_lp <= p; f_vpn <= io_mmio_wdata;
      end
      if (frAcc) begin
        f_fv <= 1'b1; f_fr <= io_mmio_wdata;
      end
      if (vhAcc) f_fv <= 1'b0;
      if (flAcc && (io_mmio_wdata[1:0] == f_lp)) begin
        f_vv <= 1'b0; f_fv <= 1'b0;
      end
    end
  end

  // ── 추적 키 — 어느 (파티션, VPN) 이든 (솔버가 고른다) ────────────────────
  (* anyconst *) logic [1:0]  f_kp;
  (* anyconst *) logic [31:0] f_kvpn;
  logic        f_kv    = 1'b0;
  logic        f_klive = 1'b0;
  logic [31:0] f_kfr   = 32'd0;
  logic [2:0]  f_kperm = 3'd0;
  wire cmKey   = cmOk && (f_lp == f_kp) && (f_vpn == f_kvpn);
  wire cmOther = cmOk && (f_lp == f_kp) && (f_vpn != f_kvpn);
  always @(posedge clk) begin
    if (reset) begin
      f_kv <= 1'b0;
      f_klive <= 1'b0;
    end else if (cmKey) begin
      f_kv    <= io_mmio_wdata[31];
      f_klive <= io_mmio_wdata[31];
      f_kfr   <= f_fr;
      f_kperm <= io_mmio_wdata[30:28];
    end else if (cmOther) begin
      f_klive <= 1'b0;                           // 같은 파티션의 다른 커밋은 축출할 수 있다 (h)
    end else if (flAcc && (io_mmio_wdata[1:0] == f_kp)) begin
      f_kv    <= 1'b0;
      f_klive <= 1'b0;
    end
  end
  wire lookKey = io_lookup_valid && (io_lookup_part == f_kp) && (io_lookup_vpn == f_kvpn);
`ifdef XLATEDOOR_HIT
  // ENV (표 축 prove 태스크만): 조회 주소를 추적 키로 묶는다. 표 축 단언은 키 조회에서만 무엇을 말하므로
  // 이 제약은 그 단언을 약하게 하지 않는다 — 조회가 상태를 바꾸지 않는다는 전제(XlateStore 의 조회는
  // readAsync 조합 경로 · xlatestore.sby flush_keeps_data 의 $stable 가지가 자유 조회 위에서 잰다) 아래서다.
  // 조회 *유효*는 자유로 둔다. 정지 축(XLATEDOOR_STALL)과 bmc 는 조회 주소까지 자유다.
  always @(*) assume (io_lookup_part == f_kp && io_lookup_vpn == f_kvpn);
`endif

  // ── 정지 유계 — 주소 · 상태 적법 COMMIT 이 ready 0 을 보는 연속 사이클 수 ─────────
  logic [2:0] f_held = 3'd0;
  wire stalled = cmLegal && !ready;
  always @(posedge clk) begin
    if (reset || !stalled) f_held <= 3'd0;
    else if (f_held != 3'd7) f_held <= f_held + 3'd1;
  end

  // 매크로가 단언을 가른다 (door.sby 「엔진」): XLATEDOOR_STALL(prove_stall 태스크)은 정지 축 둘만,
  // XLATEDOOR_HIT 는 표 축 둘만 컴파일한다. bmc 는 넷 다. 한 pdr 가 둘을 함께 들면 표 축의 귀납 불변식(저장
  // Mem 64 줄 × 추적 키)이 정지 축의 쉬운 증명까지 붙잡는다 — 실측. 표 축의 무계 증명은 미수렴이라
  // XLATEDOOR_HIT 를 쓰는 태스크는 지금 없다 (door.sby 머리 — 착지 결정 대기).
`ifndef XLATEDOOR_COVER
`ifndef XLATEDOOR_STALL
  always @(*) if (f_step) begin
    // (a)(b) · 대체 — 키 조회가 적중하면 정본상 유효이고 값은 마지막 커밋의 것이다.
    d_hit_sound: assert (!(lookKey && st_rsp_hit) ||
                         (f_kv && st_rsp_frame == f_kfr &&
                          {st_rsp_perm_r, st_rsp_perm_w, st_rsp_perm_x} == f_kperm));
    // (a) — V=1 커밋 뒤 (그 파티션의 다른 커밋 · flush 없이) 키 조회는 적중한다.
    d_hit_live:  assert (!(lookKey && f_klive) || st_rsp_hit);
  end
`endif
`ifndef XLATEDOOR_HIT
  always @(*) if (f_step) begin
    // 정지 유계 (DP-21) — 연속 정지는 F_N 사이클을 넘지 않는다 (지금 사이클 포함 f_held + 1).
    d_stall_bounded: assert (!stalled || (f_held < F_N));
    // ready 를 내리는 것은 주소 · 상태 적법 COMMIT 뿐 — VPN · FRAME · VPN_HI · 거절 · 제어 구역은 기다리지 않는다.
    d_ready_only_commit: assert (ready || cmLegal);
  end
`endif
`endif

  // ── cover 증인 (전부 reset 기점) ─────────────────────────────────────────
`ifdef XLATEDOOR_COVER
  // W1 ← XlateSurface.commit_replaces_vpn · d_hit_live · d_hit_sound — V=1 커밋 다음 사이클 키 조회가 그 프레임으로 적중한다 (채움 바이패스)
  always @(posedge clk) if (f_step) w1_hit_fill: cover (lookKey && st_rsp_hit && st_rsp_fromFill && $past(cmKey) && f_kfr != 32'd0);
  // W2 ← XlateSurface.commit_replaces_vpn · d_hit_live — 커밋이 저장으로 이관된 뒤에도 적중한다 (저장 적중)
  always @(posedge clk) if (f_step) w2_hit_store: cover (lookKey && f_klive && st_rsp_hit && !st_rsp_fromFill);
  // W3 ← XlateSurface.commit_replaces_vpn · d_hit_sound — 저장에 살아 있던 키의 재커밋(다른 프레임) 뒤에도 저장 적중이다 (대체 — 같은 칸을 덮는다. 재커밋 사이클에 키가 저장에서 실제로 적중하고 있어야 축출 · 소거 뒤 재설치 경로가 증인을 채우지 못한다 — 역-변이 RECOMMIT_KILLS)
  always @(posedge clk) if (f_step) w3_replace: cover (lookKey && st_rsp_hit && !st_rsp_fromFill && $past(f_klive && lookKey && st_rsp_hit && !st_rsp_fromFill && cmKey && io_mmio_wdata[31] && f_fr != f_kfr, 2));
  // W4 ← XlateSurface.commit_replaces_vpn · d_hit_sound — 살아 있던 키에 V=0 커밋 뒤 키 조회가 미적중이다 ((b) — 단일 항목 무효화)
  always @(posedge clk) if (f_step) w4_v0_miss: cover (lookKey && !st_rsp_hit && $past(cmKey && !io_mmio_wdata[31] && f_klive));
  // W5 ← XlateSurface.stall_independent · XlateDoor.stall_bounded · d_stall_bounded — 적법 COMMIT 이 정지했다가 다음 사이클 같은 COMMIT 이 수락된다 (조회가 줄곧 서 있는 채)
  always @(posedge clk) if (f_step) w5_stall_release: cover (cmLegal && ready && $past(stalled) && $past(io_mmio_addr) == io_mmio_addr && $past(io_mmio_wdata) == io_mmio_wdata && io_lookup_valid && $past(io_lookup_valid));
  // W6 ← XlateSurface.stall_independent · XlateDoor.stall_bounded · d_stall_bounded · d_ready_only_commit — 데이터 사유 COMMIT 도 정지하고 풀린 수락 사이클에 거절된다 (badData)
  always @(posedge clk) if (f_step) w6_bad_after_stall: cover (xs_badData && $past(stalled) && $past(io_mmio_wdata) == io_mmio_wdata);
  // W7 ← XlateSurface.commit_replaces_vpn · d_hit_sound — 살아 있던 키의 칸(같은 파티션 · VPN[3:0])에 다른 VPN 이 V=1 로 커밋된 뒤 키가 축출돼 미적중이다 (정본 (h) — 키 값이 새지 않는다. V=1 이고 축출 사이클에 키가 실제로 적중하고 있어야 V=0 무효화 · 미설치 경로가 증인을 채우지 못한다 — 역-변이 NO_EVICT · NO_TAG)
  always @(posedge clk) if (f_step) w7_evicted: cover (lookKey && f_kv && !f_klive && !st_rsp_hit && $past(cmOther && io_mmio_wdata[31] && f_klive && lookKey && st_rsp_hit && f_vpn[3:0] == f_kvpn[3:0], 2));
`endif
endmodule
