// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// MmioConfig 후-formal 하네스 — 서로소 기입 거절(D2, §1.4.5)과
// 「기입 1회 = 뷰 구동 1회」 원자성(§3.7.1)의 RTL 재검사 (§6.3).
//
// 대상: rtl/generated/MmioConfig.sv (커밋본 그대로)
// 실행: rtl/formal/sby/MmioConfig/{mmio_config,mmio_deep}.sby (smtbmc z3)
//
// ## 부착 방식 — bind 대신 expose+인스턴스
//
// yosys 0.66 자유 프론트엔드는 SV `bind` 를 조용히 버린다 (2026-08-24
// 컨테이너 실측 — RouteJudge_props.sv 머리 주석 참조). sby [script] 의
// `expose` 로 내부 신호를 포트로 승격해 직접 인스턴스한다.
//
// ## 가드 대응
//
// Route.unique_owner 는 GUARD-MAP 에서 DELEGATED(MmioConfig) 다 —
// lint_postformal 규칙상 PROVES 앵커는 CHECK 가드 전용이므로 .sby 에는
// 앵커 없이, 여기와 .sby 주석으로 위임 증명임을 밝힌다. 이행 지점
// chkDupOwn 의 「쓰기 무효 + loud sticky fault」가 핵심 속성이다.
// Route.view_sync 의 *구동 절반* (표 기입과 뷰 구동의 동일 사이클·동일
// 조건·동일 내용)도 이 모듈의 계약이라 여기서 잰다.
//
// ## 초기화 소거(sweep) 65536 사이클과 BMC 도달성 (정직 표기)
//
// reset 후 revMem 소거가 2^16 사이클이라 reset 기점 BMC 는 initDone 이후
// 상태에 닿지 못한다. 그래서 기능 속성의 실측은 k-귀납(prove)이 맡고,
// BMC 태스크는 소거 구간의 속성(무구동·무fault·ready 저지)만 실효적으로
// 잰다. k-귀납은 도달성과 무관하게 모든 상태 위에서 닫힘을 재므로 소거
// 이후 구간도 덮는다.
//
// ## MMIO_DEEP (mmio_deep.sby 전용) — 표 내용 수준 서로소 불변식
//
// yosys 자유 프론트엔드로는 Mem 내용에 하네스가 닿을 수 없다 (bind 부재,
// 계층 참조 부재, 배열 포트 부재 — 전부 실측). 그래서 표 내용은 기입
// 신호(단일 쓰기 포트 — 커밋본 RTL 에서 Mem 당 write 호출 하나)를 거울로
// 뜬 그림자 레지스터로 재구성하고, Mem *판독* 신호(revChkPresent·fwdRd)
// 와 그림자의 일치는 assume 다리로 잇는다. 다리의 근거는 각 assume 주석
// 에 적었다 — 판독=최후기입이라는 Mem 의미론과, 기입 경로가 아래에서
// assert 로 짝지어짐(assume-guarantee: t 이전의 보증이 t 의 가정을
// 정당화)이다. 이 다리 위에서 「한 LNID 의 소유 슬롯 <= 1」(서로소의
// 실물)이 k-귀납으로 선다.

`timescale 1ns/1ps

module MmioConfig_props (
  input wire        clk,
  input wire        reset,
  // ── 자유 입력 (환경 assume 은 reset 프로토콜 하나) ──────────────────
  input wire [11:0] addr,
  input wire        wstrobe,
  input wire [31:0] wdata,
  input wire        rstrobe,
  input wire        clr_dup,
  input wire        clr_bad
);

  // ── 대상 출력 + expose 승격 내부 ────────────────────────────────────
  wire [31:0] rdata;
  wire        rvalid, ready;
  wire        vw_valid, vw_en;
  wire [3:0]  vw_idx;
  wire [15:0] vw_lnid;
  wire        bw_valid, bw_mapped;
  wire [7:0]  bw_lbid;
  wire        f_dup, f_bad;
  // 내부 (expose)
  wire        w_initDone, w_busy;
  wire [7:0]  w_pSlot;
  wire [31:0] w_pWord;
  wire        w_revChkPresent;
  wire [31:0] w_fwdRd;
  wire        w_chkDupOwn, w_chkBadWr;
  wire        w_fwdWrEn, w_revWrEn, w_lbWrEn;
  wire [7:0]  w_fwdWrAddr, w_lbWrAddr;
  wire [31:0] w_fwdWrData, w_lbWrData;
  wire [15:0] w_revWrAddr;
  wire [0:0]  w_revWrData;

  MmioConfig dut (
    .io_addr(addr),
    .io_wstrobe(wstrobe),
    .io_wdata(wdata),
    .io_rstrobe(rstrobe),
    .io_rdata(rdata),
    .io_rvalid(rvalid),
    .io_ready(ready),
    .io_viewWr_valid(vw_valid),
    .io_viewWr_idx(vw_idx),
    .io_viewWr_en(vw_en),
    .io_viewWr_lnid(vw_lnid),
    .io_bankWr_valid(bw_valid),
    .io_bankWr_lbid(bw_lbid),
    .io_bankWr_mapped(bw_mapped),
    .io_faultDupOwner(f_dup),
    .io_faultBadWrite(f_bad),
    .io_faultClearDup(clr_dup),
    .io_faultClearBad(clr_bad),
    .clk(clk),
    .reset(reset),
    // expose 승격 포트
    .initDone(w_initDone),
    .busy(w_busy),
    .pSlot(w_pSlot),
    .pWord(w_pWord),
    .revChkPresent(w_revChkPresent),
    .fwdRd(w_fwdRd),
    .chkDupOwn(w_chkDupOwn),
    .chkBadWr(w_chkBadWr),
    .fwdWrEn(w_fwdWrEn),
    .fwdWrAddr(w_fwdWrAddr),
    .fwdWrData(w_fwdWrData),
    .revWrEn(w_revWrEn),
    .revWrAddr(w_revWrAddr),
    .revWrData(w_revWrData),
    .lbWrEn(w_lbWrEn),
    .lbWrAddr(w_lbWrAddr),
    .lbWrData(w_lbWrData)
  );

  // ── 하네스 독립 재계산 — 수락·판정 함수 (§3.7 디코드 + §1.4.5 CHECK) ─
  wire        h_aligned = (addr[1:0] == 2'b00);
  wire [1:0]  h_region  = addr[11:10];
  wire [7:0]  h_wordIdx = addr[9:2];
  wire        h_acceptW = ready && wstrobe;
  wire        h_acceptR = ready && !wstrobe && rstrobe; // 동시 제시면 쓰기 우선
  wire        h_lnidWrite = h_acceptW && h_aligned && (h_region == 2'd1);
  wire        h_lbidWrite = h_acceptW && h_aligned && (h_region == 2'd2);
  wire        h_rsvAccess = !(h_aligned && (h_region == 2'd1 || h_region == 2'd2));

  wire        h_pV     = w_pWord[31];
  wire [7:0]  h_pPoint = w_pWord[23:16];
  wire [15:0] h_pLnid  = w_pWord[15:0];
  wire        h_oldV   = w_fwdRd[31];
  wire [15:0] h_oldLnid = w_fwdRd[15:0];
  // 거절 3원인 폴딩 (faultBadWrite 소관): 용량 밖(capSlots=16)·점유 슬롯·
  // 없는 지점(nPoints=4). 상수는 생성본 (Wt64Config) 실측치와 일치해야 한다.
  wire        h_bad311 = (w_pSlot >= 8'h10) || h_oldV || (h_pPoint >= 8'h04);
  wire        h_commit  = w_busy && h_pV && !h_bad311 && !w_revChkPresent;
  wire        h_dup     = w_busy && h_pV && !h_bad311 && w_revChkPresent;
  wire        h_badwr   = w_busy && h_pV && h_bad311;
  wire        h_release = w_busy && !h_pV && h_oldV;
  wire        h_noop    = w_busy && !h_pV && !h_oldV;

  // ── reset 프로토콜 (유일한 환경 assume) ─────────────────────────────
  // assume 근거: RouteJudge_props 와 동일 — 부트 시 reset 1회 인가 후
  // 해제라는 형식 검증 관례. §1.5 는 "reset 직후" 상태만 규정한다.
  reg f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;
  always @* begin
    if (!f_past_valid) assume (reset);
    else               assume (!reset);
  end
  reg past_reset = 1'b1;
  always @(posedge clk) past_reset <= reset;

  always @(posedge clk) begin
    if (!reset) begin
      // ── 수락 규약: ready = initDone && !busy 의 관측 등가 —
      //    소거 중·CHECK 중 접근 저지 (상위 어댑터 대기 규약의 전제)
      p_ready_def: assert (ready == (w_initDone && !w_busy));

      // ── CHECK 판정 함수의 문면 일치 (§1.4.5 + 폴딩 규정 §5.6):
      //    D2(서로소 위반)는 별도 비트, 그 밖 3원인은 badWrite 폴딩.
      p_chk_dup_def: assert (w_chkDupOwn == h_dup);
      p_chk_bad_def: assert (w_chkBadWr == h_badwr);

      // ── Route.unique_owner (DELEGATED 이행 지점) — D2 거절 = 쓰기 무효.
      //    중복 소유 기입은 표·역방향 표·뷰 어느 것도 움직이지 못한다.
      if (h_dup || h_badwr || h_noop) begin
        p_reject_no_write: assert (!w_fwdWrEn && !w_revWrEn && !vw_valid);
      end

      // ── 「기입 1회 = 뷰 구동 1회」 원자성 (§3.7.1, view_sync 구동 절반).
      //    뷰 구동은 커밋·해제와 *동일 사이클, 동일 조건* — 그 외 경로 없음.
      p_view_drive_iff: assert (vw_valid == (h_commit || h_release));
      p_view_en_iff:    assert (vw_en == h_commit);
      if (w_initDone) begin
        // 소거 밖에서 표 기입은 커밋·해제뿐이고, 뷰 구동과 1:1 이다.
        p_atomic_lnid: assert (w_fwdWrEn == vw_valid);
        p_atomic_rev:  assert (w_revWrEn == vw_valid);
        p_atomic_lbid: assert (w_lbWrEn == h_lbidWrite);
      end
      if (h_commit) begin
        // 커밋: 표 워드·역방향 표·뷰가 같은 내용으로 함께 간다.
        // pSlot<16 은 !h_bad311 에서 따라 나온다 — vw_idx 절단이 무손실.
        p_commit_fields: assert (w_fwdWrAddr == w_pSlot && w_pSlot < 8'h10
                                 && w_fwdWrData == w_pWord
                                 && w_revWrAddr == h_pLnid && w_revWrData == 1'b1
                                 && vw_idx == w_pSlot[3:0] && vw_lnid == h_pLnid);
      end
      if (h_release) begin
        // 해제: 표 워드 소거·역방향 표 해제·뷰 해제 — 역시 한 몸.
        p_release_fields: assert (w_fwdWrAddr == w_pSlot && w_fwdWrData == 32'h0
                                  && w_revWrAddr == h_oldLnid && w_revWrData == 1'b0
                                  && vw_idx == w_pSlot[3:0] && vw_lnid == h_oldLnid);
      end

      // ── LBID 축 원자성: 표 기입과 존재 비트 뷰 구동이 같은 사이클,
      //    같은 조건, 같은 내용 (HIU-7 이 자명해지는 단일 워드 커밋).
      p_bank_drive_iff: assert (bw_valid == h_lbidWrite);
      if (h_lbidWrite) begin
        p_bank_fields: assert (w_lbWrAddr == h_wordIdx
                               && w_lbWrData == (wdata & 32'h8000FFFF)
                               && bw_lbid == h_wordIdx
                               && bw_mapped == wdata[31]
                               && bw_mapped == w_lbWrData[31]);
      end

      // ── 수락 사이클 무기입 — CHECK 의 판독(fwdRd·revChk)과 기입이 같은
      //    사이클에 겹치지 않는다 (MMIO_DEEP 의 assume 다리 건전성 근거).
      if (h_acceptW || h_acceptR) begin
        p_no_write_on_accept: assert (!w_fwdWrEn && !w_revWrEn);
      end

      // ── 소거 중 침묵 (§1.5): 구성 전 기계는 뷰를 구동하지 않고 fault 도
      //    내지 않는다. busy 는 initDone 을 함의한다.
      p_busy_implies_done: assert (!w_busy || w_initDone);
      if (!w_initDone) begin
        p_sweep_quiet: assert (!vw_valid && !bw_valid
                               && !w_chkDupOwn && !w_chkBadWr && !ready);
      end
    end

    if (f_past_valid && !past_reset && !reset) begin
      // ── initDone 단조 상승 — 소거는 한 번 끝나면 끝이다.
      p_done_monotone: assert (!$past(w_initDone) || w_initDone);

      // ── busy 프로토콜: CHECK 는 정확히 1사이클, LNID 수락에서만 진입.
      p_busy_next: assert (w_busy == $past(h_lnidWrite));

      // ── rvalid 프로토콜: 수락 다음 사이클 1펄스.
      p_rvalid_next: assert (rvalid == $past(h_acceptR));

      // ── 예약 오프셋 읽기 0 (§3.7 — 쓰기 무시·읽기 0 정책의 읽기 절반.
      //    쓰기 절반은 p_busy_next·p_bank_drive_iff 가 함께 강제한다:
      //    표 밖 쓰기는 busy 도 lbWr 도 만들지 못한다).
      if (rvalid && $past(h_acceptR && h_rsvAccess)) begin
        p_rsv_read_zero: assert (rdata == 32'h0);
      end

      // ── loud sticky (§3.7·§5.5) — 정확한 다음 상태 함수. 원인별로 접지
      //    않은 두 비트가 각자 sticky: 발화는 반드시 남고, 명시 해제 외
      //    하강 없음, 동시 해제+발화면 발화 우선.
      p_dup_sticky: assert (f_dup == ($past(w_chkDupOwn)
                                      || ($past(f_dup) && !$past(clr_dup))));
      p_bad_sticky: assert (f_bad == ($past(w_chkBadWr)
                                      || ($past(f_bad) && !$past(clr_bad))));
    end

    // ── reset 직후: fault 없음, busy 없음 (§1.5).
    if (f_past_valid && past_reset) begin
      p_reset_state: assert (!f_dup && !f_bad && !w_busy && !w_initDone);
    end
  end

`ifdef MMIO_DEEP
  // ═══ 표 내용 수준 서로소 — unique_owner 의 실물 (mmio_deep.sby 전용) ═══
  //
  // 그림자: fwdMem 의 유효 슬롯 0..15 (capSlots=16 — 커밋은 p_commit_fields
  // 가 pSlot<16 을 강제하므로 소유 엔트리는 이 범위 밖에 존재할 수 없다).
  // 갱신은 대상의 단일 쓰기 포트 신호(fwdWr*)를 그대로 거울 뜬다 — 소거
  // 기입(데이터 0)도 거울에 실리므로 소거 완료 상태(전부 공집합)와 일치.
  reg [15:0] shV;
  reg [255:0] shL; // 16 슬롯 × 16b LNID
  always @(posedge clk) begin
    if (reset) begin
      shV <= 16'b0;
      shL <= 256'b0;
    end else if (w_fwdWrEn && w_fwdWrAddr < 8'h10) begin
      shV[w_fwdWrAddr[3:0]] <= w_fwdWrData[31];
      shL[w_fwdWrAddr[3:0]*16 +: 16] <= w_fwdWrData[15:0];
    end
  end

  // 그림자 기준 「이 LNID 를 소유한 슬롯이 존재하는가」
  integer s;
  reg h_ownedP; // pLnid 소유 존재
  always @* begin
    h_ownedP = 1'b0;
    for (s = 0; s < 16; s = s + 1)
      if (shV[s] && shL[s*16 +: 16] == h_pLnid) h_ownedP = 1'b1;
  end

  always @* begin
    if (!reset && w_busy) begin
      // assume 다리 ① — CHECK 의 역방향 표 판독 = 그림자 소유 존재.
      // 근거: (a) revMem 기입 경로는 단일 쓰기 포트뿐이고 그 기입은
      // p_commit_fields·p_release_fields·p_atomic_rev 가 fwd 기입과
      // 짝지어 강제한다 (t 이전 사이클의 보증); (b) 판독은 수락 사이클의
      // readSync 이고 그 사이클에 기입이 없음은 p_no_write_on_accept 가
      // 강제한다; (c) reset 후 소거가 rev 전 엔트리를 0 으로 쓸어 그림자
      // 초기값(공집합)과 일치한다 (§1.5). 즉 판독=최후기입이라는 Mem
      // 의미론만이 기계 밖 가정이다 (assume-guarantee 분해).
      assume (w_revChkPresent == h_ownedP);
      // assume 다리 ② — CHECK 의 정방향 표 판독 = 그림자 슬롯 내용.
      // 근거는 ①과 같다 (fwd 기입 거울 + 수락 사이클 무기입 + 소거).
      // 슬롯>=16 에는 V=1 이 커밋된 적 없으므로 (p_commit_fields 의
      // pSlot<16) 판독 V 비트는 0 이다.
      if (w_pSlot < 8'h10) begin
        assume (h_oldV == shV[w_pSlot[3:0]]);
        if (shV[w_pSlot[3:0]])
          assume (h_oldLnid == shL[w_pSlot[3:0]*16 +: 16]);
      end else begin
        assume (!h_oldV);
      end
    end
  end

  genvar gs, gt;
  generate
    for (gs = 0; gs < 16; gs = gs + 1) begin : g_uniq_s
      for (gt = 0; gt < 16; gt = gt + 1) begin : g_uniq_t
        if (gs < gt) begin : g_pair
          always @(posedge clk) begin
            if (!reset) begin
              // ── 서로소의 실물: 한 LNID 를 소유한 슬롯은 최대 하나 —
              //    역방향 표가 *함수*라는 사실의 정방향 표 판 (§1.4.5 D2).
              //    커밋 가드(revChkPresent=0 ⟺ 그림자 무소유 — 다리 ①)가
              //    이 불변식을 귀납으로 보존한다.
              assert (!(shV[gs] && shV[gt]
                        && shL[gs*16 +: 16] == shL[gt*16 +: 16]));
            end
          end
        end
      end
    end
  endgenerate
`endif

endmodule
