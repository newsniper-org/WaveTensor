// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// Wt64Top 조립층 후-formal 검사자 — MMIO 구성 표면(4 KiB 페이지)의 조립 결선.
// 대상: rtl/generated/Wt64Top.sv 의 Wt64Top 모듈 *본문*. 태스크:
// rtl/formal/sby/Wt64Top/assembly.sby (머리가 절단 목록 · 보증 범위 · 엔진 표 ·
// 역-변이 표 · 축별 발화 우선 표를 소유한다 — 여기 되풀이하지 않는다).
//
// ## 부착 — 이 모듈은 래퍼가 아니라 Wt64Top *안*의 검사자다
//
// 파일 끝 bind 문은 .sby [script] 가 이름-고정 텍스트 전개로 Wt64Top 본문의
// endmodule 앞에 넣는다 (yosys 0.66 은 bind 를 묵살한다 — SharedUnit_props.sv
// 머리). 포트는 .* 로 같은 이름의 Wt64Top 넷에 묶인다: 이름이 사라지면
// hierarchy 가 ERROR 로 운다. 무거운 하위 인스턴스 열넷은 expose -evert 로
// 제거되고, 그 출력 핀은 Wt64Top 의 새 *입력* 포트 <인스턴스>__<포트>(매 스텝
// 자유 — 과대근사), 입력 핀은 새 *출력* 포트 <인스턴스>__<포트>(그 핀에 실제로
// 물린 신호)가 된다. 이중 밑줄 이름을 보는 것은 **핀**을 보는 것이다 — 같은
// 이름의 wire 가 아니다 (핀만 재배선한 변이를 wire 관측은 놓친다: 스파이크 실측).
// 구체로 남는 하위 유닛은 CapStatusWord(capWord) · AbortStaging(stg) · XlateStaging(xstg) 셋이다.
//
// ## 피연산자 규율
//
//   기대측(오라클)은 top 포트 · 절단 핀 · 구체 유닛 출력 · 이 파일의 그림자
//   레지스터(f_win · 변환 문의 f_xvv/f_xfv/f_xlp/f_xvpn/f_xfr)와 주소 리터럴로만 짓는다. DUT 어휘
//   (sel*, *Area_*, fltClrAccept, surfBadWr)를 재인용하지 않는다. DUT 측은 top 출력
//   포트 · 절단 핀 · 구체 유닛 출력뿐이다 — Wt64Top 내부 wire 와 순번 이름(_zz_*)·
//   줄번호 매인 이름은 참조하지 않는다. 변환 문(xstg)의 판정 출력(needReady ·
//   commit.* · badWrite · badData)은 오라클에 쓰지 않는다 — 문의 적법성은 MMIO 이력에서 다시
//   지은 그림자 스테이징으로 판정하고, xstg 는 DUT 측으로만 본다 (a_xhold_quiet 의
//   badWrite · badData 와 XlateDoor 결선 복제 등식 a_door_* — 복제의 같음은 DUT ↔ DUT 핀 등식이다).
//   그래서 워드 디코드 → 스테이징 의미 → 설치 핀이 한 오라클 아래 끝-끝으로 잰다.
//   생성물에서 상수에 묶인 넷(축 3 set · FAULT_STATUS [17]/[18] · CAP_STATUS
//   [31:4])은 MMIO 읽기 표면으로만 잰다 — 계층 모델에서는 lint_tautology 의 상수
//   접힘 검사가 모듈 경계를 못 넘으므로, 반증력은 .sby 머리의 역-변이 표가 든다.
//
// ## 정본 (좌표 뒤 「」 는 그 줄의 축자)
//
//   e-defined.typ:137 「구역 경계가 곧 소유 경계라는 사실이 무너진다」
//   e-defined.typ:198 「0 을 반환하고 fault 를 내지 않는다」
//   e-defined.typ:202 「거절 + loud fault 다」
//   e-defined.typ:205 「이 규범의 대상이 아니다」
//   03-hiu.typ:839 「쓰기 무시·읽기 0」
//   e-defined.typ:188 「비0 기입은 거절 + loud fault」
//   e-defined.typ:414 「실재하지 않는 파티션 값의 기입은」
//   e-defined.typ:497 「해제와 발화가 같은 사이클이면 발화가 이긴다」
//   e-defined.typ:527 「이 워드에 들지 않는다」
//   e-defined.typ:499 「FAULT_STATUS 의 논리합」
//   e-defined.typ:503 「CAP_STATUS 와 같은 비트 배치의 W1C」
//   e-defined.typ:485 「태그 값은 내지 않는다」
//   e-defined.typ:1800 「거절된 기입은 무장을 세우지 않는다」
//   e-defined.typ:341 「이 창은 어느 슬롯에 쓰는가만 정한다」
//   e-defined.typ:399 「창을 재키잉의 authority 로 겸하게」
//   e-defined.typ:461 「`[30:24]` 예약 = 0 (엄격)」
//   e-defined.typ:463 「적재 수락 가능」
//   e-defined.typ:267 「정의역 나열 순서 그대로」
//   e-defined.typ:44 「이 문서가 새로 정의하지 않는다」
//   b-gaps.typ:811 「물려받은 `0x000`–`0x11F` 의 방향 처분」
//   e-defined.typ:212 「예약 오프셋 정책을 따르고」
//   03-hiu.typ:858 「드라이버가 ABI 판을 물었을 때 0 을 받는다」
//   e-defined.typ:473 「소거 대상 태그의 wave 필드」
//   e-defined.typ:475 「`[15:0]` LNID」
//   e-defined.typ:477 「`[15:8]` precision · `[7:0]` dim」
//   ── W3 (3.10 v1.0 묶음 — 형상 비노출 0xC00 문, 2026-10-13) — 앞판의 3.9 LO/HI 인용 둘을 대체 ──
//   e-defined.typ:305 「수락된 기입이 그 주소의 파티션을 래치한다」
//   e-defined.typ:306 「래치 파티션의 기저에서만 수락한다」
//   e-defined.typ:308 「유효 비트를 담은 워드가 마지막이므로 부분 기입 상태가 유효해질 수 없다」
//   e-defined.typ:308 「기다리지 않고 곧장 거절 + `[6]` 이다」
//   e-defined.typ:308 「수락 사이클에 거절된다 — 그 수락은 위 유계 정지 뒤일 수 있다」
//   e-defined.typ:308 「*표의 워드로 등재한다* — 쓰기는 거절 + `[6]`, 읽기는 0」
//   e-defined.typ:311 「VPN 기입은 기입 주소의 파티션을 래치하고 FRAME 스테이징 유효를 내린다」
//   e-defined.typ:321 「`[7:0]` 파티션 — *기입이 곧 발화*다 · `[31:8]` 예약 = 0 (엄격)」
//   e-defined.typ:329 「*정지 자체는 이것으로 풀리지 않는다*」
//   e-defined.typ:323 「`[0]` 미적중으로 정지 중 · `[1]` 미적중 sticky · `[15:8]` 정지한 요청의 파티션」
//   e-defined.typ:325 「정지한 요청의 가상 페이지 번호 하위 32b」
//   e-defined.typ:327 「v1.0 표면(VPN 32b — VA 44b 는 유도, E.2 해설)에서는 항상 0 이다」
//   03-hiu.typ:1133 「수락 중에는 ready 가 내려가 있으므로 중간 상태는 관측되지」
//   03-hiu.typ:1134 「읽기도 같다 — 수락(ready ∧ 스트로브)되지 않은 접근은 효과도 응답도 없다」
//   03-hiu.typ:874 「하위 두 비트가 0 이 아닌 *쓰기*는 어댑터가 새게 한 sub-word 쓰기의 잔재이고」
//   03-hiu.typ:874 「비정렬 *읽기*는 0 · fault 없음이다」
//   03-hiu.typ:1623 「이 장치는 거기 워드를 두지 않는다. 쓰기는」
//   03-hiu.typ:1624 「거절 + loud fault (FAULT_STATUS `[6]`), 읽기는 0 · fault 없음이다」
//   e-defined.typ:743 「*소비 회로가 없는 RW 워드 — 쓰기는 거절, 읽기는 0.*」
//   e-defined.typ:505 「합의 전 값은 0 이고 *판 0 은 물려받은 `0x000`–`0x11F` 에 어떤 레이아웃도 약속하지 않는다*」
//   e-defined.typ:505 「쓰기는 E.1.1 RO 규범대로 거절 + loud fault 다」
//   ── W1 (3.10 v1.0 묶음 RTL 파도 — 표면 비트·워드, 2026-10-11) 이 더한 근거 ──
//   e-defined.typ:495 「`[31:20]` RO 예약 = 0」 — FAULT_STATUS 는 [19:0] (비트 스물).
//   e-defined.typ:497 「`[31:20]` 예약 = 0 (엄격)」 — FAULT_CLEAR 의 예약 비트 경계.
//   e-defined.typ:497 「호스트 대면 fault 해제 표면은 이 워드 하나다」 — [19] 에는 IO 해제선이 없다.
//   e-defined.typ:523 「비소유 프레임 접근 — 자격(권한 비트)은 허용했으나」 — [19] 의 원천.
//   e-defined.typ:503 「`[7:0]` 실재 파티션 수 · `[23:8]` 파티션당 항목 용량」 — 0xFF8 HIU_SHAPE.
//   e-defined.typ:503 「두 필드 다 *개수*로 인코딩한다」 — log2 가 아니다.
//   e-defined.typ:765 「참조 구현의 형상은 *파티션 4 × 항목 16 = 64 항목 · 직접 사상 · 항목 8 B* 이며」
//     — 하네스 상수 F_PARTS · F_SLOTS 의 출처 (직접 사상이라 파티션당 저장 칸 수 = 파티션당 항목 16).
//     RTL 상수를 베끼지 않는다 (차등 정의역 함정).
//   e-defined.typ:347 「읽기는 아무것도 해제하지 않는다」 — 0xEC4 (a_rd_pure 의 근거).
//   e-defined.typ:347 「`[31:17]` RO 예약 = 0」 — 0xEC4 의 배치 (값의 뜻은 MaskUnit/engine.sby).
//
// ## 구역 분류 — 정의 정책과 예약 정책을 섞지 않는다 (워드 단위)
//
//   rLeg  0x000–0x11F  물려받은 기존 배정 — 3.10 「합의 전의 처분」(판정 T3 (d)): 이
//                      장치는 거기 워드를 두지 않는다. 쓰기는 정렬 여부 무관 거절 +
//                      [6](surfMust) · 읽기는 0(resvA). 합의가 워드를 배정하면 물러난다.
//                      (b-gaps.typ:811 「물려받은 `0x000`–`0x11F` 의 방향 처분」 — 그 미결 행을 판정이 닫았다.)
//   rResv 0x120–0x1FF  예약 — 정렬 쓰기 무-fault · 읽기 0.
//   미배선 두 구역(0x380 · 0xFC0)과 변환 저장소 제어(0xE00)의 표에 없는 워드.
//     uResv  표에 없는 워드 (0x394–0x3FC · 0xE14–0xE7C · 0xFC0–0xFF4) — 예약 정책:
//            정렬 쓰기 무-fault(surfMust 밖 → a_surf_rise) · 읽기 0.
//     sqTbl  명령 링 표 워드 다섯 (0x380–0x390) — RW 넷은 소비 회로가 없는 워드(E.1.3 규범
//            끝 — 판정 T1-i β), SQ_HEAD(0x38C)는 RO. 정렬 쓰기 거절 + [6](surfMust) · 읽기
//            0(resvA). 0xFFC 는 RO 판 워드(판정 T1-ii): 정렬 쓰기 거절 + [6](surfMust) ·
//            읽기는 합의 전 값 0 (a_rd_abi — 이제 규범 값이라 결함의 동결이 아니다).
//     shapeW 0xFF8 HIU_SHAPE (W1) — RO 워드: 정렬 쓰기 거절 + [6](surfMust) · 정렬 읽기는
//            응답 + 정본 표에서 유도한 형상 값(a_rd_shape) · 비정렬 읽기 0(resvA).
//   0xEC4 MASK_DUP_CAPTURE (W1) — 조립 구역 RO 워드: 정렬 쓰기 거절 + [6](surfMust) · 정렬
//     읽기는 응답 + 수락 사이클의 mask.dupCapture 핀(a_rd_dupcap) · undefA 는 0xEC8 부터다.
//   변환 저장소 두 구역 (파도 3 — XlateStaging 이 배선했다):
//     xWo    항목 표면 (0xC00–0xDFC) · 0xE00 · 0xE10 — 읽기는 resvA(응답 + 읽기 0 — 네 WO 워드와
//            예약-엄격 28 워드가 같다). 항목 표면은 기저 0xC00 + (p≪7) 안 오프셋 A[6:2] 로 가른다
//            (W3): VPN(0) · FRAME(1) · COMMIT(2) · VPN_HI(3) · 예약-엄격(4..31). 쓰기의 처분은 문의
//            판정이다 — 주소 · 상태 사유 거절(짝 불일치 FRAME/VPN_HI/COMMIT · 비0 VPN_HI · 예약-엄격
//            워드 · 0xE00/0xE10 예약 · 없는 파티션)은 surfMust(조립 sticky), 데이터 사유(FRAME 없는
//            V=1 · [27:0] 비0 COMMIT)는 *수락 사이클*에만 원천별 sticky io_fault_xlateCfgBadWrite
//            (xBadAcc — a_xbad_*), VPN · 적법 FRAME/VPN_HI · 커밋 · 정지된 COMMIT 은 무-fault.
//     xRo    RO 워드 (0xE04–0xE0C) — 정렬 쓰기는 거절 + [6](surfMust). 정렬 읽기는
//            응답 + 값 — 파도 4 가 관측 값을 배선했다 (a_rd_xstatus · a_rd_xvpnlo ·
//            a_rd_xvpnhi — 값은 절단 핀 hiu__missStall · hiu__missPart · hiu__missVpn ·
//            hiu__io_missNotice 의 포장이다. 정지 게이트 스냅샷의 뜻은 hiumask.sby).
//   비정렬 쓰기(own · cq · cfg 밖 전부 — 예약 · 물려받은 구역 포함)는 sub-word 쓰기의 장치
//   포트 표현이라(판정 T2 (a)) 거절 + [6](surfMust). 세 유닛 구역의 비정렬 쓰기는 유닛
//   sticky 몫이다 (각 유닛 태스크). 비정렬 읽기는 0(resvA — 유닛 구역 밖).
//   surfOpen 은 파도 4 페이지 통합으로 0 이 되어 지웠다 — must/open 분해가 정확 등식이 됐다.
//
// ## assume (전수)
//
//   initial assume (reset) 하나 — t0 의 reset. 절단 핀에는 assume 이 0 건이다
//   (.sby [script] 의 select -assert-count 가 $check(FLAVOR=assume) 수 1 을 핀한다).
//
// WITNESS-RESIDUAL: 실물 도달성 — 절단 출력 의존 증인 — 콘에 절단 핀(<인스턴스>__*)
//   이 든 증인은 과대근사 위의 도달이다. 목록과 실물 근거는 각 W 태그 산문이 적고,
//   절단 무관 증인은 cover 태스크 [script] 의 콘 판별이 기계로 강제한다.
module Wt64Top_props (
  input logic        clk,
  input logic        reset,
  // ── top ports ──
  input logic [11:0] io_mmio_addr,
  input logic        io_mmio_wstrobe,
  input logic [31:0] io_mmio_wdata,
  input logic        io_mmio_rstrobe,
  input logic [31:0] io_mmio_rdata,
  input logic        io_mmio_rvalid,
  input logic        io_mmio_ready,
  input logic        io_fault_cfgSurfBadWrite,
  input logic        io_fault_fpCfgBadWrite,
  input logic        io_fault_xlateCfgBadWrite,  // W3 — COMMIT 데이터 사유 거절의 원천별 sticky (DP-15)
  input logic        io_fault_hiuOwn,      // W1 — FAULT_STATUS [19] 원천별 수출 (a_fsrc_b19)
  // hiu 의 최상위 직결 입력 (파도 4 W6 — a_hiu_pass: 읽기가 요청 · hold · hostRsp 에 닿지 않는다)
  input logic        io_hiuReq_valid, io_hiuReq_write, input logic [1:0] io_hiuReq_part,
  input logic [31:0] io_hiuReq_vpn,
  input logic        io_hiuHold,
  input logic        io_hostRsp_valid, input logic [31:0] io_hostRsp_frame,
  input logic        io_hostRsp_perm_r, io_hostRsp_perm_w, io_hostRsp_perm_x,
  input logic        io_faultClear_decodeWalk,
  input logic        io_faultClear_operandDecode,
  input logic        io_faultClear_route,
  input logic        io_faultClear_reasm,
  input logic        io_faultClear_reasmCap,
  input logic        io_faultClear_hiuPerm,
  input logic        io_faultClear_hiuMiss,
  input logic        io_faultClear_cfgDupOwner,
  input logic        io_faultClear_cfgBadWrite,
  input logic        io_faultClear_cfgSurfBadWrite,
  input logic        io_faultClear_ownCollide,
  input logic        io_faultClear_fabricBp,
  input logic        io_faultClear_sharedBp,
  input logic        io_faultClear_bankWrite,
  input logic        io_faultClear_maskNoMask,
  input logic        io_faultClear_maskNonceDup,
  input logic        io_faultClear_maskWrRekey,
  input logic        io_faultClear_fpBp,
  input logic        io_faultClear_fpBadProg,
  // ── kept (concrete) units: output wires ──
  input logic [31:0] capWord_io_word,
  input logic [2:0]  stg_io_armed,
  input logic        stg_io_fire,
  input logic [31:0] stg_io_tag_wave,
  input logic [3:0]  stg_io_tag_epoch,
  input logic        stg_io_tag_poison,
  input logic        stg_io_tag_trace,
  input logic [15:0] stg_io_tag_lnid,
  input logic [7:0]  stg_io_tag_precision,
  input logic [7:0]  stg_io_tag_dim,
  input logic        xstg_io_badWrite,
  // W3 — 문의 출력 · 입력 넷 (DUT 측 — 오라클이 아니다: a_xhold_quiet 과 XlateDoor 결선 복제 등식 a_door_*)
  input logic        xstg_io_badData, xstg_io_needReady,
  input logic [6:0]  xstg_io_woff,
  input logic        xstg_io_commit_valid, input logic [1:0] xstg_io_commit_part,
  input logic [31:0] xstg_io_commit_vpn, input logic [31:0] xstg_io_commit_frame,
  input logic        xstg_io_commit_perm_r, xstg_io_commit_perm_w, xstg_io_commit_perm_x, xstg_io_commit_v,
  input logic        xstg_io_flush_valid, input logic [1:0] xstg_io_flush_part,
  // ── evert pins ──
  input logic        walk__io_oValid, walk__io_oCapAbsent, walk__io_oFault, walk__io_iFaultClear,
  input logic        od__io_oFault, od__io_iFaultClear,
  input logic        rj__io_fault, rj__io_faultClear,
  input logic        rj__io_viewWr_valid, input logic [3:0] rj__io_viewWr_idx, input logic rj__io_viewWr_en,
  input logic [15:0] rj__io_viewWr_lnid,
  input logic        rj__io_bankWr_valid, input logic [7:0] rj__io_bankWr_lbid, input logic rj__io_bankWr_mapped,
  input logic        reasm__io_fault, reasm__io_faultClear, reasm__io_capAbsent, reasm__io_capAbsentClear,
  input logic [7:0]  reasm__io_abortCount,
  input logic [2:0]  reasm__io_incomplete,
  input logic [2:0]  reasm__io_occupancy,
  input logic        reasm__io_abort_valid,
  input logic [31:0] reasm__io_abort_tag_wave,
  input logic [3:0]  reasm__io_abort_tag_epoch,
  input logic        reasm__io_abort_tag_poison,
  input logic        reasm__io_abort_tag_trace,
  input logic [15:0] reasm__io_abort_tag_lnid,
  input logic [7:0]  reasm__io_abort_tag_precision,
  input logic [7:0]  reasm__io_abort_tag_dim,
  input logic        reasm__io_deliver_valid, reasm__io_deliver_ready,
  input logic [2:0]  mog__io_occupancy,
  input logic        hiu__io_req_ready,
  input logic [31:0] hiu__io_owner_frame,
  input logic        hiu__io_owner_devOwned,
  input logic        hiu__io_mask_req_valid, input logic [1:0] hiu__io_mask_req_part,
  input logic [31:0] hiu__io_mask_req_frame,
  input logic        hiu__io_mask_rsp_valid, input logic [31:0] hiu__io_mask_rsp_frame,
  input logic        hiu__io_faultPerm, hiu__io_faultClear, hiu__io_missClear,
  input logic [2:0]  hiu__io_occupancy,
  input logic        hiu__io_install_valid, hiu__installSlotFree, input logic [1:0] hiu__io_install_part,
  input logic [3:0]  hiu__io_install_idx, input logic [27:0] hiu__io_install_tag,
  input logic [31:0] hiu__io_install_frame,
  input logic        hiu__io_install_perm_r, hiu__io_install_perm_w, hiu__io_install_perm_x, hiu__io_install_v,
  input logic        hiu__io_flush_valid, input logic [1:0] hiu__io_flush_part,
  input logic        hiu__io_req_valid, hiu__io_req_write, input logic [1:0] hiu__io_req_part,
  input logic [31:0] hiu__io_req_vpn,
  input logic        hiu__io_hold,
  input logic        hiu__io_hostRsp_valid, input logic [31:0] hiu__io_hostRsp_frame,
  input logic        hiu__io_hostRsp_perm_r, hiu__io_hostRsp_perm_w, hiu__io_hostRsp_perm_x,
  // 파도 4 — hiu 의 io 번들 밖 출력 (절단 핀): 슬롯 여유 · 미적중 관측 값 · 미적중 sticky
  input logic        hiu__missStall, hiu__io_missNotice, input logic [1:0] hiu__missPart,
  input logic [31:0] hiu__missVpn,
  // W1 — hiu 의 io 번들 밖 [19] 원천 (절단 출력 핀) · 그 해제 (절단 입력 핀 — IO 해제선 없음)
  input logic        hiu__faultOwn, hiu__faultOwnClear,
  input logic [11:0] own__io_addr, input logic own__io_wstrobe, input logic [31:0] own__io_wdata,
  input logic        own__io_rstrobe, own__io_rvalid, own__io_ready,
  input logic [31:0] own__io_query_frame, input logic own__io_query_devOwned,
  input logic        own__io_faultCollide, own__io_faultClearCollide, own__io_faultBadWrite, own__io_faultClearBadWrite,
  input logic [11:0] cfgBlk__io_addr, input logic cfgBlk__io_wstrobe, input logic [31:0] cfgBlk__io_wdata,
  input logic        cfgBlk__io_rstrobe, cfgBlk__io_rvalid, cfgBlk__io_ready,
  input logic        cfgBlk__io_viewWr_valid, input logic [3:0] cfgBlk__io_viewWr_idx, input logic cfgBlk__io_viewWr_en,
  input logic [15:0] cfgBlk__io_viewWr_lnid,
  input logic        cfgBlk__io_bankWr_valid, input logic [7:0] cfgBlk__io_bankWr_lbid, input logic cfgBlk__io_bankWr_mapped,
  input logic        cfgBlk__io_faultDupOwner, cfgBlk__io_faultBadWrite, cfgBlk__io_faultClearDup, cfgBlk__io_faultClearBad,
  input logic        merge__io_fault, merge__io_faultClear, input logic [2:0] merge__io_occupancy,
  input logic        shared_1__io_faultBpViolation, shared_1__io_faultClear, input logic [2:0] shared_1__io_occupancy,
  input logic        bank__io_fault, bank__io_faultClear, input logic [4:0] bank__io_occupancy,
  input logic        mask__io_keyWr_valid, input logic [1:0] mask__io_keyWr_part, input logic [2:0] mask__io_keyWr_idx,
  input logic [31:0] mask__io_keyWr_data,
  input logic        mask__io_nonceWr_valid, input logic [1:0] mask__io_nonceWr_part, input logic [2:0] mask__io_nonceWr_idx,
  input logic [31:0] mask__io_nonceWr_data,
  input logic        mask__io_rekey_valid, mask__io_rekey_ready, input logic [1:0] mask__io_rekey_part,
  input logic [3:0]  mask__io_maskReady, input logic mask__io_busy, mask__io_en,
  input logic        mask__io_req_valid, input logic [1:0] mask__io_req_part, input logic [31:0] mask__io_req_frame,
  input logic        mask__io_rsp_valid, input logic [31:0] mask__io_rsp_frame,
  input logic        mask__io_faultNoMask, mask__io_faultNonceDup, mask__io_faultWrDuringRekey,
  input logic        mask__io_faultClearNoMask, mask__io_faultClearNonceDup, mask__io_faultClearWrRekey,
  input logic [31:0] mask__dupCapture,     // W1 — 0xEC4 캡처 워드 (절단 출력 핀 — 뜻은 MaskUnit/engine.sby)
  input logic        fps__io_oCapAbsent, fps__io_oBusy,
  input logic        fps__io_progWr_valid, input logic [7:0] fps__io_progWr_slot, input logic [7:0] fps__io_progWr_idx,
  input logic [15:0] fps__io_progWr_step,
  input logic        fps__io_bindWr_valid, input logic [15:0] fps__io_bindWr_key, input logic fps__io_bindWr_en,
  input logic [7:0]  fps__io_bindWr_slot,
  input logic        fps__io_loadReady, fps__io_faultBpViolation, fps__io_faultBadProg, fps__io_faultClearBp, fps__io_faultClearBadProg,
  input logic [7:0]  cq__io_addr, input logic cq__io_wstrobe, input logic [31:0] cq__io_wdata,
  input logic        cq__io_rstrobe, cq__io_rvalid, cq__io_ready,
  input logic        cq__io_comp_valid, cq__io_comp_ready,
  input logic [15:0] cq__io_drain_pipe, cq__io_drain_pending, cq__io_drain_output,
  input logic [15:0] cq__io_drain_ownSlots, cq__io_drain_contexts, cq__io_drain_tokens,
  input logic        cq__io_faultOverflow, cq__io_faultClearOverflow, cq__io_faultBadWrite, cq__io_faultClearBadWrite
);
  initial assume (reset);

  logic f_past_valid = 1'b0;
  logic f_past_reset = 1'b1;
  always @(posedge clk) begin
    f_past_valid <= 1'b1;
    f_past_reset <= reset;
  end
  wire f_step = f_past_valid && !reset && !f_past_reset;

  wire [11:0] A = io_mmio_addr;
  wire [31:0] D = io_mmio_wdata;
  wire W  = io_mmio_wstrobe;
  wire R  = io_mmio_rstrobe && !io_mmio_wstrobe;
  wire al = (A[1:0] == 2'b00);

  wire rLeg   = (A <  12'h120);
  wire rResv  = (A >= 12'h120) && (A < 12'h200);
  wire rOwn   = (A >= 12'h200) && (A < 12'h300);
  wire rCq    = (A >= 12'h300) && (A < 12'h380);
  wire rCfg   = (A >= 12'h400) && (A < 12'hC00);
  wire rXent  = (A >= 12'hC00) && (A < 12'hE00);
  wire rMask  = (A >= 12'hE80) && (A < 12'hF00);
  wire rFp    = (A >= 12'hF00) && (A < 12'hF40);
  wire rAbort = (A >= 12'hF40) && (A < 12'hF80);
  wire rFault = (A >= 12'hF80) && (A < 12'hFC0);
  wire rAsm   = rMask || rFp || rAbort || rFault;
  wire rXctl  = (A >= 12'hE00) && (A < 12'hE80);
  wire uResv  = ((A >= 12'h394) && (A < 12'h400)) || ((A >= 12'hE14) && (A < 12'hE80)) ||
                ((A >= 12'hFC0) && (A < 12'hFF8));                // W1 — 0xFF8 은 HIU_SHAPE 다
  wire shapeW = (A >= 12'hFF8) && (A < 12'hFFC);   // HIU_SHAPE 0xFF8 (비정렬 바이트 0xFF9–0xFFB 포함)
  wire xWo    = rXent || ((A >= 12'hE00) && (A < 12'hE04)) || ((A >= 12'hE10) && (A < 12'hE14));
  wire xRo    = (A >= 12'hE04) && (A < 12'hE10);
  wire sqTbl  = (A >= 12'h380) && (A < 12'h394);  // 명령 링 표 워드 다섯 (0x380–0x390)
  wire abiW   = (A >= 12'hFFC);                    // 판 워드 0xFFC (비정렬 바이트 0xFFD–0xFFF 포함)
  // 변환 항목 표면 (W3) — 기저 0xC00 + (p≪7): A[8:7] = 파티션 · A[6:2] = 기저 안 워드 색인.
  wire [1:0] xp = A[8:7];
  wire [4:0] xw = A[6:2];
  wire xEnt   = W && al && rXent;               // 항목 표면의 정렬된 쓰기
  wire xVpnW  = xEnt && (xw == 5'd0);           // XLATE_ENTRY_VPN    (정지되지 않는다 — a_ready_only_slot)
  wire xFrW   = xEnt && (xw == 5'd1);           // XLATE_ENTRY_FRAME
  wire xCmW   = xEnt && (xw == 5'd2);           // XLATE_ENTRY_COMMIT (정지 후보)
  wire xVhW   = xEnt && (xw == 5'd3);           // XLATE_ENTRY_VPN_HI
  wire xRsW   = xEnt && (xw >= 5'd4);           // 예약-엄격 28 워드

  // ── 변환 문의 그림자 스테이징 — 모델 XlateSurface.tla 의 stg = [vv, fv, p, vpn, fr] 를 MMIO 이력에서 ──
  // 다시 짓는다 (XlateStaging_props.sv 와 같은 규칙). 갱신 원천 넷: VPN(래치 · FRAME 유효 하강) ·
  // 래치 기저의 FRAME(VPN 유효 필요) · 래치 기저의 0 VPN_HI(FRAME 유효 하강) · 래치 파티션의 적법
  // XLATE_FLUSH(두 유효 하강). COMMIT(커밋 · 거절 · 정지) · 거절 · 다른 파티션 flush · MISS_CLEAR ·
  // RO 쓰기는 건드리지 않는다 (e-defined.typ:306 「커밋은 스테이징을 소진하지 않는다」). 원천들은
  // 주소가 달라 한 사이클에 겹치지 않고, 항목 표면의 비COMMIT 쓰기는 ready = 1 이라 수락 = 스트로브다
  // (a_ready_only_slot). 기본 형상(파티션 4)이라 형상 밖 기저 가지는 없다 ((g)). DUT 의 스테이징과
  // 이 그림자의 일치는 prove(abc pdr)가 귀납 불변식으로 스스로 찾는다 — xstg 내부 레지스터를 참조하지 않는다.
  logic        f_xvv  = 1'b0;
  logic        f_xfv  = 1'b0;
  logic [1:0]  f_xlp  = 2'd0;
  logic [31:0] f_xvpn = 32'd0;
  logic [31:0] f_xfr  = 32'd0;
  wire xPair  = f_xvv && (f_xlp == xp);         // 래치 기저 ∧ VPN 유효
  always @(posedge clk) begin
    if (reset) begin
      f_xvv  <= 1'b0;
      f_xfv  <= 1'b0;
      f_xlp  <= 2'd0;
      f_xvpn <= 32'd0;
      f_xfr  <= 32'd0;
    end else if (xVpnW) begin
      f_xvv  <= 1'b1;
      f_xfv  <= 1'b0;
      f_xlp  <= xp;
      f_xvpn <= D;
    end else if (xFrW && xPair) begin
      f_xfv  <= 1'b1;
      f_xfr  <= D;
    end else if (xVhW && xPair && (D == 32'd0)) begin
      f_xfv  <= 1'b0;
    end else if (W && al && (A == 12'hE00) && partOk && (D[1:0] == f_xlp)) begin
      f_xvv  <= 1'b0;
      f_xfv  <= 1'b0;
    end
  end
  // 정본 판정 — 주소 · 상태로 적법한 COMMIT(정지 후보 · 모델 Refused 의 정의역)과 데이터 사유.
  wire xHold  = xCmW && xPair;                  // 주소 · 상태 적법 COMMIT — 하류 거부로 버스 정지 가능
  wire xDBad  = (D[27:0] != 28'd0) || (D[31] && !f_xfv);   // 데이터 사유 (V=0 의 [30:28] 은 항이 아니다 — DP-20)
  wire xBadAcc = xHold && hiu__installSlotFree && xDBad;    // 수락 사이클의 데이터 사유 거절 (원천별 sticky)
  // 주소 · 상태 사유 — 하류 상태와 무관하게 곧장 거절 (조립 sticky).
  wire xRej   = (xFrW && !xPair) || (xCmW && !xPair) || (xVhW && !(xPair && (D == 32'd0))) || xRsW;

  wire aKey   = (A >= 12'hE80) && (A <= 12'hE9C);
  wire aNonce = (A >= 12'hEA4) && (A <= 12'hEB8);
  wire aTag   = (A >= 12'hF40) && (A <= 12'hF4C);
  wire woA    = aKey || aNonce || (A == 12'hEBC) || (A == 12'hF00) || (A == 12'hF04) ||
                aTag || (A == 12'hF84) || (A == 12'hF90);
  wire undefA = ((A >= 12'hEC8) && (A <= 12'hEFC)) || ((A >= 12'hF0C) && (A <= 12'hF3C)) ||  // W1 — 0xEC4 는 MASK_DUP_CAPTURE 다
                ((A >= 12'hF5C) && (A <= 12'hF7C)) || ((A >= 12'hF94) && (A <= 12'hFBC));
  // xWo 는 woA 가 아니라 여기다 — 그 읽기의 rvalid·rdata 는 resvRv 경로(mux 기본 0)라
  // 절단된 유닛 rvalid 가 자유인 이 모델에서는 a_rd_resv0 의 유닛 rvalid 예외가 필요하다
  // (조립 네 구역의 WO 는 mapRv 가 mux 최우선이라 a_rd_wo 로 정확 등식을 잰다).
  wire resvA  = rLeg || rResv || uResv || sqTbl || xWo || (abiW && !al) || (shapeW && !al) || ((rAsm || rXctl) && !al);
  wire [11:0] f_kOff = A - 12'hE80;
  wire [11:0] f_nOff = A - 12'hEA4;

  // 형상 상수 — 정본 표에서 독립 유도한다 (머리 「정본」 절의 참조 구현 형상 인용 —
  // 「파티션 4 × 항목 16」 · 직접 사상). partOk 의 파티션 수와 HIU_SHAPE [7:0] 이 *같은 상수*다:
  // 둘이 갈리면 하나가 틀렸다. RTL 의 cfg 를 베끼지 않는다 (차등 정의역 함정).
  localparam integer F_PARTS = 4;    // 실재 파티션 수
  localparam integer F_SLOTS = 16;   // 파티션당 저장 칸 수 (직접 사상 — 파티션당 항목 수)
  // 0xFF8 의 기대 읽기 값 — [31:24] 0 · [23:8] 칸 수 · [7:0] 파티션 수 (둘 다 개수)
  localparam [31:0] F_HIU_SHAPE = (F_SLOTS << 8) | F_PARTS;
  wire partOk = (D[31:8] == 24'd0) && ({24'd0, D[7:0]} < F_PARTS);
  wire acF84  = W && (A == 12'hF84) && (D[31:20] == 12'd0);   // W1 — 예약 [31:20] (비트 스물)
  wire acF90  = W && (A == 12'hF90) && (D[31:4]  == 28'd0);

  wire surfMust = xRej || (W && al && (
      ((A == 12'hE00) && !partOk) || (A == 12'hE04) || (A == 12'hE08) || (A == 12'hE0C) ||
      ((A == 12'hE10) && (D[31:1] != 31'd0)) ||
      ((A == 12'hEA0) && !partOk) || ((A == 12'hEBC) && !partOk) || (A == 12'hEC0) ||
      (A == 12'hEC4) || (A == 12'hFF8) ||              // W1 — MASK_DUP_CAPTURE · HIU_SHAPE (RO)
      (A == 12'hF08) ||
      ((A == 12'hF44) && (D[27:16] != 12'd0)) ||
      ((A == 12'hF48) && (D[31:16] != 16'd0)) || ((A == 12'hF4C) && (D[31:1] != 31'd0)) ||
      (A == 12'hF50) || (A == 12'hF54) || (A == 12'hF58) ||
      (A == 12'hF80) || ((A == 12'hF84) && (D[31:20] != 12'd0)) || (A == 12'hF88) || (A == 12'hF8C) ||
      ((A == 12'hF90) && (D[31:4] != 28'd0)))) ||
      (W && rLeg) ||                                   // T3 (d) — 물려받은 구간 쓰기 (정렬 무관)
      (W && al && (sqTbl || (A == 12'hFFC))) ||        // T1-i β 소비 없는 RW 넷 · SQ_HEAD RO · T1-ii 판 워드 RO
      (W && !al && !(rOwn || rCq || rCfg));            // T2 (a) — 비정렬 쓰기 (세 유닛 구역 밖 전부)
  // FP_BIND(0xF04) [30:24] 예약 거절 — D1 (b): 조립 sticky 가 아니라 수락(loadReady) 게이트된 별도
  // sticky(io_fault_fpCfgBadWrite)다. 해제선은 0xF84[6] 하나다 (IO 해제선 없음).
  wire fpBad = W && al && (A == 12'hF04) && (D[30:24] != 7'd0) && fps__io_loadReady;
  wire clrF  = acF84 && D[6];
  wire clrS = io_faultClear_cfgSurfBadWrite || (acF84 && D[6]);

  logic [1:0] f_win = 2'b00;
  always @(posedge clk) begin
    if (reset) f_win <= 2'b00;
    else if (W && al && (A == 12'hEA0) && partOk) f_win <= D[1:0];
  end

  wire [19:0] f_expSt = {hiu__faultOwn, 2'b00, cq__io_faultOverflow, fps__io_faultBadProg, fps__io_faultBpViolation,
      mask__io_faultWrDuringRekey, mask__io_faultNonceDup, mask__io_faultNoMask, bank__io_fault,
      shared_1__io_faultBpViolation, merge__io_fault, own__io_faultCollide,
      (cfgBlk__io_faultBadWrite || io_fault_cfgSurfBadWrite || cq__io_faultBadWrite || own__io_faultBadWrite ||
       io_fault_fpCfgBadWrite || io_fault_xlateCfgBadWrite),
      cfgBlk__io_faultDupOwner, hiu__io_faultPerm, reasm__io_fault, rj__io_fault, od__io_oFault, walk__io_oFault};

  wire src1 = fps__io_oCapAbsent;
  wire src2 = walk__io_oValid && walk__io_oCapAbsent;

`ifndef WT64TOP_COVER
  always @(*) if (!reset) begin
    // region routing
    a_own_strb: assert (own__io_wstrobe == (W && rOwn) && own__io_rstrobe == (io_mmio_rstrobe && rOwn));
    a_cq_strb:  assert (cq__io_wstrobe  == (W && rCq)  && cq__io_rstrobe  == (io_mmio_rstrobe && rCq));
    a_cfg_strb: assert (cfgBlk__io_wstrobe == (W && rCfg) && cfgBlk__io_rstrobe == (io_mmio_rstrobe && rCfg));
    a_blk_bus:  assert (own__io_addr == A && cfgBlk__io_addr == A && cq__io_addr == A[7:0] &&
                        own__io_wdata == D && cfgBlk__io_wdata == D && cq__io_wdata == D &&
                        mask__io_keyWr_data == D && mask__io_nonceWr_data == D);
    a_ready_unit: assert ((!rOwn || io_mmio_ready == own__io_ready) && (!rCq || io_mmio_ready == cq__io_ready) &&
                          (!rCfg || io_mmio_ready == cfgBlk__io_ready));
    // D1 (b) — 선택자 표 소거를 기다리는 것은 정렬 FP_PROG/FP_BIND *쓰기*뿐 (읽기·비정렬은 기다리지 않는다)
    a_ready_fpw: assert (!(W && al && ((A == 12'hF00) || (A == 12'hF04))) || io_mmio_ready == fps__io_loadReady);
    a_ready_one: assert ((rOwn || rCq || rCfg || (W && al && ((A == 12'hF00) || (A == 12'hF04))) || xHold) || io_mmio_ready);
    // W3 (A) 조립 절반 — 항목 표면 쓰기의 ready 는 주소 · 상태 적법 COMMIT 이면 *정확히* 하류 슬롯 여유
    // (hiu.installSlotFree)이고 그 밖(VPN · FRAME · VPN_HI · 예약-엄격 · 주소 · 상태 사유 거절 COMMIT)이면
    // 1 이다. 등식이라 그 ready 가 다른 정지 원천(미적중 정지 hiu__missStall · cfgBlk ready · FP 소거
    // loadReady)을 보지 않는다 — 「다른 정지와 독립」의 ready 쪽 (모델 stall_independent 의 ready 측 ·
    // Prop_AddrRejectNoWait 의 조립 쪽 「기다리지 않고 곧장」). wdata 는 xHold 에 없다 (구조 콘 검사
    // scripts/lint_ready_cone.py). 둘의 차이(같은 파티션 flush)는 a_xonehot 이 조립에서 만들지 않는다.
    a_ready_only_slot: assert (!xEnt || io_mmio_ready == (xHold ? hiu__installSlotFree : 1'b1));
    // mask
    a_key_valid:   assert (mask__io_keyWr_valid == (W && al && aKey));
    a_key_idx:     assert (!mask__io_keyWr_valid || mask__io_keyWr_idx == f_kOff[4:2]);
    a_nonce_valid: assert (mask__io_nonceWr_valid == (W && al && aNonce));
    a_nonce_idx:   assert (!mask__io_nonceWr_valid || mask__io_nonceWr_idx == f_nOff[4:2]);
    a_win_pins:    assert (mask__io_keyWr_part == f_win && mask__io_nonceWr_part == f_win);
    a_mask_env:    assert ($onehot0({mask__io_keyWr_valid, mask__io_nonceWr_valid, mask__io_rekey_valid}));
    a_rekey_iff:   assert (mask__io_rekey_valid == (W && al && (A == 12'hEBC) && partOk));
    a_rekey_part:  assert (!mask__io_rekey_valid || mask__io_rekey_part == D[1:0]);
    // fp
    a_prog_src:    assert (!fps__io_progWr_valid || (W && al && (A == 12'hF00)));
    a_prog_acc:    assert (!(W && al && (A == 12'hF00) && io_mmio_ready) || fps__io_progWr_valid);
    a_prog_fields: assert (!fps__io_progWr_valid || (fps__io_progWr_slot == D[31:24] &&
                           fps__io_progWr_idx == D[23:16] && fps__io_progWr_step == D[15:0]));
    a_bind_src:    assert (!fps__io_bindWr_valid || (W && al && (A == 12'hF04) && (D[30:24] == 7'd0)));
    a_bind_acc:    assert (!(W && al && (A == 12'hF04) && (D[30:24] == 7'd0) && io_mmio_ready) || fps__io_bindWr_valid);
    a_bind_fields: assert (!fps__io_bindWr_valid || (fps__io_bindWr_en == D[31] &&
                           fps__io_bindWr_slot == D[23:16] && fps__io_bindWr_key == D[15:0]));
    // abort
    a_fire_src:   assert (!reasm__io_abort_valid || (W && al && (A == 12'hF4C) && (D[31:1] == 31'd0) && D[0]));
    a_fire_route: assert (reasm__io_abort_valid == stg_io_fire && reasm__io_abort_tag_wave == stg_io_tag_wave &&
                          reasm__io_abort_tag_epoch == stg_io_tag_epoch && reasm__io_abort_tag_poison == stg_io_tag_poison &&
                          reasm__io_abort_tag_trace == stg_io_tag_trace && reasm__io_abort_tag_lnid == stg_io_tag_lnid &&
                          reasm__io_abort_tag_precision == stg_io_tag_precision && reasm__io_abort_tag_dim == stg_io_tag_dim);
    // fault clear routing
    a_fclr_b0:  assert (walk__io_iFaultClear == (io_faultClear_decodeWalk || (acF84 && D[0])));
    a_fclr_b1:  assert (od__io_iFaultClear   == (io_faultClear_operandDecode || (acF84 && D[1])));
    a_fclr_b2:  assert (rj__io_faultClear    == (io_faultClear_route || (acF84 && D[2])));
    a_fclr_b3:  assert (reasm__io_faultClear == (io_faultClear_reasm || (acF84 && D[3])));
    a_fclr_b4:  assert (hiu__io_faultClear   == (io_faultClear_hiuPerm || (acF84 && D[4])));
    a_fclr_b5:  assert (cfgBlk__io_faultClearDup == (io_faultClear_cfgDupOwner || (acF84 && D[5])));
    a_fclr_b6:  assert (cfgBlk__io_faultClearBad == (io_faultClear_cfgBadWrite || (acF84 && D[6])) &&
                        own__io_faultClearBadWrite == (acF84 && D[6]) && cq__io_faultClearBadWrite == (acF84 && D[6]));
    a_fclr_b7:  assert (own__io_faultClearCollide == (io_faultClear_ownCollide || (acF84 && D[7])));
    a_fclr_b8:  assert (merge__io_faultClear == (io_faultClear_fabricBp || (acF84 && D[8])));
    a_fclr_b9:  assert (shared_1__io_faultClear == (io_faultClear_sharedBp || (acF84 && D[9])));
    a_fclr_b10: assert (bank__io_faultClear == (io_faultClear_bankWrite || (acF84 && D[10])));
    a_fclr_b11: assert (mask__io_faultClearNoMask == (io_faultClear_maskNoMask || (acF84 && D[11])));
    a_fclr_b12: assert (mask__io_faultClearNonceDup == (io_faultClear_maskNonceDup || (acF84 && D[12])));
    a_fclr_b13: assert (mask__io_faultClearWrRekey == (io_faultClear_maskWrRekey || (acF84 && D[13])));
    a_fclr_b14: assert (fps__io_faultClearBp == (io_faultClear_fpBp || (acF84 && D[14])));
    a_fclr_b15: assert (fps__io_faultClearBadProg == (io_faultClear_fpBadProg || (acF84 && D[15])));
    a_fclr_b16: assert (cq__io_faultClearOverflow == (acF84 && D[16]));
    // W1 — [19] 의 해제는 0xF84 [19] 하나다: IO 해제선이 없다 (정본 「호스트 대면 fault 해제 표면은
    // 이 워드 하나다」 · 표면 이후 축의 규율). 예약 경계는 acF84 의 [31:20] 이다.
    a_fclr_b19: assert (hiu__faultOwnClear == (acF84 && D[19]));
    a_miss_clr: assert (hiu__io_missClear == (io_faultClear_hiuMiss ||
                        (W && al && (A == 12'hE10) && (D[31:1] == 31'd0) && D[0])));
    // 변환 저장소의 문 (파도 3 · W3 재작성) — 오라클은 그림자 스테이징(f_xvv · f_xfv · f_xlp · f_xvpn · f_xfr)이다.
    // commit_fires · commit_base_match · commit_needs_vpn · commit_needs_frame · commit_rsv_strict ·
    // frame_stages_only — 설치 핀의 전건 전수: 하류가 받을 수 있는 주소 · 상태 적법 COMMIT 중 데이터
    // 적법한 것 ⇔ install.valid. 흡수 · VPN/FRAME/VPN_HI 발 커밋 · 다른 기저/VPN 없음/FRAME 없는 V=1 ·
    // [27:0] 비0 의 커밋 · 거부된 사이클의 valid(= 조용한 드롭)를 이 한 등식이 막는다.
    a_xcm_iff:    assert (hiu__io_install_valid == (xHold && hiu__installSlotFree && !xDBad));
    a_xcm_part:   assert (!xHold || hiu__io_install_part == f_xlp);  // valid 무관 — ready 가 그 COMMIT 의 파티션 슬롯을 본다
    // commit_whole · commit_v_carried (문 절반) — 커밋 사이클의 핀 = 래치 VPN(칸 분할 idx = VPN[3:0] ·
    // tag = VPN[31:4] — DP-1 직접 사상 · 조회와 같은 함수 XlateStore.idxOf/tagOf, 그 같음은 door.sby) ‖
    // FRAME(V=1) ‖ COMMIT 권한 · V ‖ 래치 파티션. 권한 비트 배정 [30]=R · [29]=W · [28]=X 는 호스트 ABI.
    a_xcm_fields: assert (!hiu__io_install_valid ||
                          (hiu__io_install_part == f_xlp && hiu__io_install_idx == f_xvpn[3:0] &&
                           hiu__io_install_tag == f_xvpn[31:4] && (!D[31] || hiu__io_install_frame == f_xfr) &&
                           hiu__io_install_v == D[31] &&
                           hiu__io_install_perm_r == D[30] && hiu__io_install_perm_w == D[29] &&
                           hiu__io_install_perm_x == D[28]));
    // W3 (A) 조립 절반 — 정지 중(주소 · 상태 적법 COMMIT ∧ 슬롯 점유)에는 설치 · flush 핀이 서지 않고
    // 문의 두 거절선도 서지 않는다 (:308 「정지 중에는 효과가 없고」). 버스가 하나뿐이라 정지 중 새
    // 설치가 없다 — xlatestore.sby s_pend_bounded 의 전건 「설치가 오지 않는 동안」의 조립 쪽 이행.
    a_xhold_quiet: assert (!(xHold && !hiu__installSlotFree) ||
                           (!hiu__io_install_valid && !xstg_io_badWrite && !xstg_io_badData && !hiu__io_flush_valid));
    // flush_fires · flush_part_exists · flush_rsv_strict — 적법 XLATE_FLUSH ⇔ flush 핀 (같은 사이클,
    // ready 무관) · flush_scoped (문 절반) — 파티션 하나, 그 기입의 [7:0] 그 자체 (절단 별칭 없음).
    a_xflush_iff:  assert (hiu__io_flush_valid == (W && al && (A == 12'hE00) && partOk));
    a_xflush_part: assert (!hiu__io_flush_valid || hiu__io_flush_part == D[1:0]);
    // 설치 ∧ flush 배타 — 파도 4 SLOTFREE 뒤 이 단언이 *안전 전제*다: 문의 installReady 가 flush 와
    // 무관한 슬롯 여유라, 같은 사이클 · 같은 파티션 flush 가 설치와 겹치면 문은 커밋을 내고
    // XlateStore 는 flush 우선으로 그 설치를 조용히 버린다 (XlateStore_props.sv a_ready_split).
    a_xonehot:     assert ($onehot0({hiu__io_install_valid, hiu__io_flush_valid}));
    // cap axis 0
    a_cap0_lvl: assert (capWord_io_word[0] == reasm__io_capAbsent);
    a_cap0_clr: assert (reasm__io_capAbsentClear == (io_faultClear_reasmCap || (acF90 && D[0])));
    // drain + composite wiring
    a_drain_order: assert (cq__io_drain_pipe == {13'd0, hiu__io_occupancy} && cq__io_drain_pending == {13'd0, shared_1__io_occupancy} &&
                           cq__io_drain_output == {13'd0, merge__io_occupancy} && cq__io_drain_ownSlots == {11'd0, bank__io_occupancy} &&
                           cq__io_drain_contexts == {13'd0, reasm__io_occupancy} && cq__io_drain_tokens == {13'd0, mog__io_occupancy});
    a_hm_en:     assert (mask__io_en == hiu__io_req_ready);
    a_hm_req:    assert (mask__io_req_valid == hiu__io_mask_req_valid && mask__io_req_part == hiu__io_mask_req_part &&
                         mask__io_req_frame == hiu__io_mask_req_frame);
    a_hm_rsp:    assert (hiu__io_mask_rsp_valid == mask__io_rsp_valid && hiu__io_mask_rsp_frame == mask__io_rsp_frame);
    a_own_query: assert (hiu__io_owner_devOwned == own__io_query_devOwned && own__io_query_frame == hiu__io_owner_frame);
    a_route_wr:  assert (rj__io_viewWr_valid == cfgBlk__io_viewWr_valid && rj__io_viewWr_idx == cfgBlk__io_viewWr_idx &&
                         rj__io_viewWr_en == cfgBlk__io_viewWr_en && rj__io_viewWr_lnid == cfgBlk__io_viewWr_lnid &&
                         rj__io_bankWr_valid == cfgBlk__io_bankWr_valid && rj__io_bankWr_lbid == cfgBlk__io_bankWr_lbid &&
                         rj__io_bankWr_mapped == cfgBlk__io_bankWr_mapped);
    a_bp_relief: assert (reasm__io_deliver_ready == cq__io_comp_ready && cq__io_comp_valid == reasm__io_deliver_valid);
    // W3 — XlateDoor 결선 복제의 같음 (composite_wiring · DP-13 (C)): rtl/formal/sby/XlateDoor/door.sby 의
    // XlateDoor_check 가 문 · 저장 사이에 복제한 결선이 실물 xlateArea 와 같다 — 설치 번들(idx = VPN[3:0] ·
    // tag = VPN[31:4]) · flush · 워드 오프셋 · ready 덮어쓰기. 복제가 실물과 갈리면 door.sby 의 끝-끝
    // 측정(정지 유계 · (a)(b))이 다른 기계를 잰 것이 된다 — 이 넷이 그 다리다(출력 쪽만 직접 — 입력 wrEnt · wrCtl · wdata · installReady 는 xlateArea_* 넷이라 간접: a_xcm_iff · a_xcm_fields · a_xhold_quiet · a_xflush_iff · a_ready_only_slot).
    a_door_install: assert (hiu__io_install_valid == xstg_io_commit_valid && hiu__io_install_part == xstg_io_commit_part &&
                            hiu__io_install_idx == xstg_io_commit_vpn[3:0] && hiu__io_install_tag == xstg_io_commit_vpn[31:4] &&
                            hiu__io_install_frame == xstg_io_commit_frame && hiu__io_install_v == xstg_io_commit_v &&
                            hiu__io_install_perm_r == xstg_io_commit_perm_r && hiu__io_install_perm_w == xstg_io_commit_perm_w &&
                            hiu__io_install_perm_x == xstg_io_commit_perm_x);
    a_door_flush:   assert (hiu__io_flush_valid == xstg_io_flush_valid && hiu__io_flush_part == xstg_io_flush_part);
    a_door_woff:    assert (xstg_io_woff == A[8:2]);
    a_door_ready:   assert (!(W && al && (rXent || rXctl)) ||
                            io_mmio_ready == ((rXent && (xw == 5'd2) && xstg_io_needReady) ? hiu__installSlotFree : 1'b1));
    // hiu 의 요청 · hold · hostRsp 입력 핀 = 최상위 IO 그대로 (파도 4 W6 검토 — XlateObs.obs_read_pure 의 「조립 몫
    // 전부」가 이 열 핀을 요구한다: 읽기가 파이프라인을 잡거나 요청을 누르거나 응답을 먹는 변이 N15 · N16 · N22 가
    // 이 단언 전에는 세 태스크를 다 통과했다). 절단 입력 핀 열을 묶어 「재지 않는 핀」 hiu 10 → 0.
    // W1 — [19] 원천별 수출: 최상위 io.fault.hiuOwn 은 hiu 의 faultOwn 핀 그대로다 ([4] 와 다른 넷).
    a_fsrc_b19:  assert (io_fault_hiuOwn == hiu__faultOwn);
    // W1 — 읽기 무부작용 (조립 절반 · 정본 0xEC4 「읽기는 아무것도 해제하지 않는다」): 읽기 사이클에
    // [12] 와 캡처 워드 · [19] 원천의 상태를 움직일 수 있는 절단 입력 핀(해제 둘 · 재키잉 · 키 ·
    // 논스 기입)이 읽기 때문에 서지 않는다 — 해제 핀은 IO 해제선 그대로다. 유닛 절반(그 핀이
    // 서지 않으면 [12] · 캡처 · [19] 가 그대로다)은 MaskUnit/engine.sby 의 n_dup_hold · n_dup_rise_src ·
    // c_first · c_clr_zero 와 hiumask.sby 의 o_own_hold · o_own_rise 다 — 합성은 서술이다.
    // a_fclr_b12 · a_fclr_b19 · a_rekey_iff · a_key_valid · a_nonce_valid 에서 유도된다 (a_mask_env 와
    // 같은 처분 — 읽기 무부작용을 이름으로 드는 서명).
    a_rd_pure:   assert (!R || (mask__io_faultClearNonceDup == io_faultClear_maskNonceDup && !hiu__faultOwnClear &&
                                !mask__io_rekey_valid && !mask__io_keyWr_valid && !mask__io_nonceWr_valid));
    a_hiu_pass:  assert (hiu__io_req_valid == io_hiuReq_valid && hiu__io_req_write == io_hiuReq_write &&
                         hiu__io_req_part == io_hiuReq_part && hiu__io_req_vpn == io_hiuReq_vpn &&
                         hiu__io_hold == io_hiuHold &&
                         hiu__io_hostRsp_valid == io_hostRsp_valid && hiu__io_hostRsp_frame == io_hostRsp_frame &&
                         hiu__io_hostRsp_perm_r == io_hostRsp_perm_r && hiu__io_hostRsp_perm_w == io_hostRsp_perm_w &&
                         hiu__io_hostRsp_perm_x == io_hostRsp_perm_x);
  end

  always @(posedge clk) if (f_step) begin
    // reads
    if ($past(R && resvA)) begin
      a_rd_resv_rv: assert (io_mmio_rvalid);
      a_rd_resv0:   assert ((own__io_rvalid || cq__io_rvalid || cfgBlk__io_rvalid) || io_mmio_rdata == 32'd0);
    end
    if ($past(R && al && undefA))                  a_rd_undef: assert (io_mmio_rvalid && io_mmio_rdata == 32'd0);
    // 미적중 관측 값 (파도 4 — XlateObs 포장 절반) — 수락 사이클의 절단 핀을 워드로 포장한 값이
    // 다음 사이클 rdata 다: STATUS [0] 정지 · [1] sticky · [15:8] 파티션(0 확장) · 나머지 0 ·
    // VPN_LO = VPN · VPN_HI = 0 (VA 44b — VPN 32b). 유닛 rvalid 가 자유인 이 모델에서도 정확
    // 등식이다 (관측 덮어쓰기가 rdata mux 의 마지막 대입이다).
    if ($past(R && al && (A == 12'hE04)))          a_rd_xstatus: assert (io_mmio_rvalid && io_mmio_rdata ==
        {16'd0, 6'd0, $past(hiu__missPart), 6'd0, $past(hiu__io_missNotice), $past(hiu__missStall)});
    if ($past(R && al && (A == 12'hE08)))          a_rd_xvpnlo:  assert (io_mmio_rvalid && io_mmio_rdata == $past(hiu__missVpn));
    if ($past(R && al && (A == 12'hE0C)))          a_rd_xvpnhi:  assert (io_mmio_rvalid && io_mmio_rdata == 32'd0);
    if ($past(R && al && woA))                     a_rd_wo:    assert (io_mmio_rvalid && io_mmio_rdata == 32'd0);
    // T1-ii — 0xFFC 읽기는 합의 전 값 0 — e-defined.typ:505 「합의 전 값은 0 이고」. resvRv 경로라 유닛 rvalid 예외는 a_rd_resv0 와 같다.
    if ($past(R && al && (A == 12'hFFC)))          a_rd_abi:   assert (io_mmio_rvalid &&
        ((own__io_rvalid || cq__io_rvalid || cfgBlk__io_rvalid) || io_mmio_rdata == 32'd0));
    // D1 · 「보증하지 않는 것」 (c) 의 조립 절반 — 조립이 낸 rvalid 는 직전 사이클에 *수락된* 조립 구역 읽기의 응답이다
    if (io_mmio_rvalid && !own__io_rvalid && !cq__io_rvalid && !cfgBlk__io_rvalid)
                                                   a_rv_acc:   assert ($past(R && io_mmio_ready && !(rOwn || rCq || rCfg)));
    if ($past(R && al && (A == 12'hEA0)))          a_rd_mpart: assert (io_mmio_rvalid && io_mmio_rdata == {30'd0, $past(f_win)});
    if ($past(R && al && (A == 12'hEC0)))          a_rd_mstat: assert (io_mmio_rvalid && io_mmio_rdata ==
        {22'd0, $past(mask__io_rekey_ready), $past(mask__io_busy), 4'd0, $past(mask__io_maskReady)});
    if ($past(R && al && (A == 12'hF08)))          a_rd_fstat: assert (io_mmio_rvalid && io_mmio_rdata ==
        {30'd0, $past(fps__io_oBusy), $past(fps__io_loadReady)});
    if ($past(R && al && (A == 12'hF50)))          a_rd_acnt:  assert (io_mmio_rvalid && io_mmio_rdata == {24'd0, $past(reasm__io_abortCount)});
    if ($past(R && al && (A == 12'hF54)))          a_rd_ainc:  assert (io_mmio_rvalid && io_mmio_rdata == {29'd0, $past(reasm__io_incomplete)});
    if ($past(R && al && (A == 12'hF58)))          a_rd_arm:   assert (io_mmio_rvalid && io_mmio_rdata == {29'd0, $past(stg_io_armed)});
    if ($past(R && al && (A == 12'hF80)))          a_rd_fst:   assert (io_mmio_rvalid && io_mmio_rdata == {12'd0, $past(f_expSt)});
    if ($past(R && al && (A == 12'hF88)))          a_rd_fsum:  assert (io_mmio_rvalid && io_mmio_rdata == {31'd0, |$past(f_expSt)});
    // W1 — 0xFF8 HIU_SHAPE: 정렬 읽기의 다음 사이클 응답 + 정본 표에서 유도한 형상 값 (RTL 상수를
    // 베끼지 않는다). resvRv 경로가 아니라 덮어쓰기라 유닛 rvalid 예외가 없는 정확 등식이다.
    if ($past(R && al && (A == 12'hFF8)))          a_rd_shape:  assert (io_mmio_rvalid && io_mmio_rdata == F_HIU_SHAPE);
    // W1 — 0xEC4 MASK_DUP_CAPTURE: 정렬 읽기의 다음 사이클 rdata = 수락 사이클의 mask.dupCapture 핀
    // (조립에 캡처를 드는 상태가 없다 — 값의 뜻은 MaskUnit/engine.sby 의 c_* 가 든다).
    if ($past(R && al && (A == 12'hEC4)))          a_rd_dupcap: assert (io_mmio_rvalid && io_mmio_rdata == $past(mask__dupCapture));
    if ($past(R && al && (A == 12'hF8C))) begin
      a_rd_capst: assert (io_mmio_rvalid && io_mmio_rdata == {28'd0, $past(capWord_io_word[3:1]), $past(reasm__io_capAbsent)});
      a_rd_capb3: assert (!io_mmio_rdata[3]);
    end
    // surf sticky
    a_surf_fire:  assert (!$past(surfMust) || io_fault_cfgSurfBadWrite);
    a_surf_rise:  assert (!(io_fault_cfgSurfBadWrite && !$past(io_fault_cfgSurfBadWrite)) || $past(surfMust));
    a_surf_hold:  assert (!($past(io_fault_cfgSurfBadWrite) && !$past(clrS)) || io_fault_cfgSurfBadWrite);
    a_surf_clear: assert (!$past(io_fault_cfgSurfBadWrite && clrS && !surfMust) || !io_fault_cfgSurfBadWrite);
    // FP_BIND 예약 거절 sticky (D1 (b)) — 수락된 기입에서만 선다 · 발화 우선 · 비하강 · 0xF84[6] 해제
    a_fpbad_fire:  assert (!$past(fpBad) || io_fault_fpCfgBadWrite);
    a_fpbad_rise:  assert (!(io_fault_fpCfgBadWrite && !$past(io_fault_fpCfgBadWrite)) || $past(fpBad));
    a_fpbad_hold:  assert (!($past(io_fault_fpCfgBadWrite) && !$past(clrF)) || io_fault_fpCfgBadWrite);
    a_fpbad_clear: assert (!$past(io_fault_fpCfgBadWrite && clrF && !fpBad) || !io_fault_fpCfgBadWrite);
    // W3 — COMMIT 데이터 사유 거절의 원천별 sticky (DP-15 · fpBindArea 선례): 수락 사이클(슬롯 여유)의
    // 데이터 사유 COMMIT 에서만 선다 · 발화 우선 · 비하강 · 0xF84[6] 해제 (IO 해제선 없음). 정지 중
    // (슬롯 점유)의 데이터 사유 COMMIT 은 세우지 않는다 — 「수락 사이클에 거절된다」.
    a_xbad_fire:   assert (!$past(xBadAcc) || io_fault_xlateCfgBadWrite);
    a_xbad_rise:   assert (!(io_fault_xlateCfgBadWrite && !$past(io_fault_xlateCfgBadWrite)) || $past(xBadAcc));
    a_xbad_hold:   assert (!($past(io_fault_xlateCfgBadWrite) && !$past(clrF)) || io_fault_xlateCfgBadWrite);
    a_xbad_clear:  assert (!$past(io_fault_xlateCfgBadWrite && clrF && !xBadAcc) || !io_fault_xlateCfgBadWrite);
    // abort arm
    a_arm_src:  assert (stg_io_armed == $past(stg_io_armed) || $past(W && al && aTag));
    a_arm_set0: assert (!$past(W && al && (A == 12'hF40)) || stg_io_armed[0]);
    a_arm_set1: assert (!$past(W && al && (A == 12'hF44) && (D[27:16] == 12'd0)) || stg_io_armed[1]);
    a_arm_set2: assert (!$past(W && al && (A == 12'hF48) && (D[31:16] == 16'd0)) || stg_io_armed[2]);
    // 거절된 TAG1 기입(poison·trace·예약 비0)은 무장 [1] 을 움직이지 않는다 — E.12.1 1항 후단의 조립 몫
    a_arm_rej1: assert (!$past(W && al && (A == 12'hF44) && (D[27:16] != 12'd0)) || (stg_io_armed[1] == $past(stg_io_armed[1])));
    // 비정렬 소거 구역 쓰기(TAG0/1/2 · FIRE 의 sub-word 표현)는 무장을 움직이지 않고 [6] 을 세운다 — E.12.1 1항 · 판정 T2 (a)
    a_arm_unal: assert (!$past(W && !al && rAbort) || ((stg_io_armed == $past(stg_io_armed)) && io_fault_cfgSurfBadWrite));
    // abort staging value — wdata pin to stg; TAG1 is the whole-word round trip (no field named — the codec layout
    // is not locked; the epoch [31:28] path is measured). Wave-4 landing checked LNID only (was a_tag1_lnid).
    a_tag0_val:  assert (!$past(W && al && (A == 12'hF40)) || stg_io_tag_wave == $past(D));
    a_tag1_val:  assert (!$past(W && al && (A == 12'hF44) && (D[27:16] == 12'd0)) || {stg_io_tag_epoch, stg_io_tag_poison, stg_io_tag_trace, 10'd0, stg_io_tag_lnid} == $past(D));
    a_tag2_val:  assert (!$past(W && al && (A == 12'hF48) && (D[31:16] == 16'd0)) || {stg_io_tag_precision, stg_io_tag_dim} == $past(D[15:0]));
    // cap axes 1/2
    a_cap1_set:  assert (!$past(src1) || capWord_io_word[1]);
    a_cap1_rise: assert (!(capWord_io_word[1] && !$past(capWord_io_word[1])) || $past(src1));
    a_cap1_fall: assert (!($past(capWord_io_word[1]) && !capWord_io_word[1]) || $past(acF90 && D[1]));
    a_cap1_clr:  assert (!$past(capWord_io_word[1] && acF90 && D[1] && !src1) || !capWord_io_word[1]);
    a_cap2_set:  assert (!$past(src2) || capWord_io_word[2]);
    a_cap2_rise: assert (!(capWord_io_word[2] && !$past(capWord_io_word[2])) || $past(src2));
    a_cap2_fall: assert (!($past(capWord_io_word[2]) && !capWord_io_word[2]) || $past(acF90 && D[2]));
    a_cap2_clr:  assert (!$past(capWord_io_word[2] && acF90 && D[2] && !src2) || !capWord_io_word[2]);
  end
`endif

`ifdef WT64TOP_COVER
  // 부류: [무관] = 콘에 절단 핀 없음 (cover [script] 가 강제) · [의존] = 콘에 절단 핀 있음.
  // W1 ← Wt64Top.region_routing · a_cq_strb · a_own_strb — [무관] 완료 구역 마지막 워드와 명령 링 첫 워드의 경계
  always @(posedge clk) if (f_step) w1_cq_last:  cover (cq__io_wstrobe && A == 12'h37C);
  always @(posedge clk) if (f_step) w1_sq_first: cover (W && A == 12'h380 && !own__io_wstrobe && !cq__io_wstrobe && !cfgBlk__io_wstrobe);
  // W2 ← MmioPage.resv_lenient · a_rd_resv_rv · a_rd_undef — [의존: rvalid OR·rdata mux 콘에 유닛 rvalid 핀] 값은 resvRv/mapRv 만으로 선다 — 실물 도달은 MMIO 궤적뿐
  always @(posedge clk) if (f_step) w2_resv_rd:  cover ($past(R && A == 12'h1FC) && io_mmio_rvalid);
  always @(posedge clk) if (f_step) w2_undef_rd: cover ($past(R && A == 12'hEFC) && io_mmio_rvalid && io_mmio_rdata == 32'd0);
  // W3 ← MmioPage.wo_read_zero · a_rd_wo — [의존: rdata mux] 키 기입 직후의 되읽기가 0 (mapRv 가 mux 최우선이라 값은 유닛 핀과 무관)
  always @(posedge clk) if (f_step) w3_key_rd_after_wr: cover ($past(R && A == 12'hE80) && $past(W && A == 12'hE80 && D != 32'd0, 2) && io_mmio_rvalid && io_mmio_rdata == 32'd0);
  // W4 ← MmioPage.ro_rejected · AbortSurface.ro_rejected · AbortSurface.reject_loud · a_surf_fire — [무관] RO 오프셋(0xF58) 쓰기로 조립 sticky 첫 상승
  always @(posedge clk) if (f_step) w4_ro_wr: cover ($past(W && al && A == 12'hF58 && !io_fault_cfgSurfBadWrite) && io_fault_cfgSurfBadWrite);
  // W5 ← Wt64Top.word_reserved_strict · a_rekey_iff · a_fclr_b0 — [무관] 예약 비0 기입은 거절+loud 이고 효과가 없다
  always @(posedge clk) if (f_step) w5_rekey_rsv: cover ($past(W && al && A == 12'hEBC && D[31:8] != 24'd0 && !io_fault_cfgSurfBadWrite) && io_fault_cfgSurfBadWrite && !$past(mask__io_rekey_valid));
  always @(posedge clk) if (f_step) w5_fclr_rsv:  cover (W && al && A == 12'hF84 && D[20] && D[0] && !io_faultClear_decodeWalk && !walk__io_iFaultClear);
  // W6 ← Wt64Top.partition_reject · a_win_pins — [무관] MASK_PART [7:0]=4 (형상 파티션 수 밖) 거절
  always @(posedge clk) if (f_step) w6_part_rej: cover ($past(W && al && A == 12'hEA0 && D == 32'd4 && !io_fault_cfgSurfBadWrite) && io_fault_cfgSurfBadWrite);
  // W7 ← Wt64Top.surf_fire_beats_clear · a_surf_fire · a_surf_clear — [무관] 해제선과 거절 사건의 겹침 · MMIO W1C 해제
  always @(posedge clk) if (f_step) w7_surf_overlap: cover ($past(W && al && A == 12'hEC0 && io_faultClear_cfgSurfBadWrite && io_fault_cfgSurfBadWrite) && io_fault_cfgSurfBadWrite);
  always @(posedge clk) if (f_step) w7_surf_clear:   cover ($past(io_fault_cfgSurfBadWrite && W && A == 12'hF84 && D == 32'h40) && !io_fault_cfgSurfBadWrite);
  // W8 ← Wt64Top.fault_status_map · a_rd_fst · a_rd_fsum — [의존: rdata mux] [6] 은 조립 sticky 로도 선다 — 실물 도달은 W4 궤적 + 읽기
  always @(posedge clk) if (f_step) w8_fst_rd6: cover ($past(R && A == 12'hF80) && io_mmio_rdata[6]);
  always @(posedge clk) if (f_step) w8_fsum_rd: cover ($past(R && A == 12'hF88) && io_mmio_rdata[0]);
  // W9 ← Wt64Top.fault_clear_routing · a_fclr_b16 · a_fclr_b19 — [무관] 20비트 전부 1 인 수락 W1C 가 첫·끝 축에 닿는다 (W1 — 끝 축은 [19])
  always @(posedge clk) if (f_step) w9_fclr_all: cover (W && A == 12'hF84 && D[31:20] == 12'd0 && D[19:0] == 20'hFFFFF && walk__io_iFaultClear && cq__io_faultClearOverflow && hiu__faultOwnClear);
  // W10 ← Wt64Top.cap_status_wiring · a_cap0_clr · a_cap2_rise · a_rd_capst — w10_cap0_clr [무관] ·
  //       w10_cap2_gate [의존: walk 핀 — 실물 근거 없음(DecodeWalk 의 등급이 iValid 와 무관하게 계산된다는 설계 서술뿐)] ·
  //       w10_capst_rd2 [의존: walk 핀 — 실물 근거 DecodeWalk_props.sv w3_capabsent]
  always @(posedge clk) if (f_step) w10_cap0_clr:  cover (reasm__io_capAbsentClear && !io_faultClear_reasmCap);
  always @(posedge clk) if (f_step) w10_cap2_gate: cover ($past(walk__io_oCapAbsent && !walk__io_oValid) && !capWord_io_word[2]);
  always @(posedge clk) if (f_step) w10_capst_rd2: cover ($past(R && A == 12'hF8C) && io_mmio_rdata[2]);
  // W11 ← Wt64Top.abort_surface · a_rd_arm · a_fire_route — w11_fire [무관] · w11_arm_rd_full [의존: rdata mux — 무장·태그는 구체 stg]
  always @(posedge clk) if (f_step) w11_fire:        cover (reasm__io_abort_valid);
  always @(posedge clk) if (f_step) w11_arm_rd_full: cover ($past(R && A == 12'hF58) && io_mmio_rdata[2:0] == 3'b111 && $past(stg_io_tag_wave) != 32'd0);
  // W12 ← Wt64Top.mask_surface · a_win_pins · a_key_valid — [무관] 창 3 으로 옮긴 뒤의 키 기입
  always @(posedge clk) if (f_step) w12_key_win3: cover (mask__io_keyWr_valid && mask__io_keyWr_part == 2'd3);
  // W13 ← Mask.rekey_explicit_target · a_rekey_part · a_rekey_iff — [무관] 창과 다른 파티션의 재키잉 (Mask.tla Witness_NoWindowTargetDrift 의 RTL 판)
  always @(posedge clk) if (f_step) w13_rekey_drift: cover (mask__io_rekey_valid && mask__io_rekey_part != mask__io_keyWr_part);
  // W14 ← Wt64Top.fp_surface · a_bind_src — [무관] 결속(en=1) 기입의 발행
  always @(posedge clk) if (f_step) w14_bind_en: cover (fps__io_bindWr_valid && fps__io_bindWr_en);
  // W15 ← Wt64Top.drain_wiring · a_drain_order — [의존: 점유 핀 — 실물 근거 없음]
  always @(posedge clk) if (f_step) w15_drain_nz: cover (cq__io_drain_pipe != 16'd0 && cq__io_drain_tokens != 16'd0);
  // W16 ← Wt64Top.composite_wiring · a_hm_en · a_hm_req — [의존: hiu 핀 — 실물 근거 HiuMask_props.sv w4_misswait_stall · w8_mask_frozen_loaded]
  always @(posedge clk) if (f_step) w16_hm_stall: cover (!mask__io_en && mask__io_req_valid);
  // W17 ← MmioPage.resv_lenient · a_surf_rise — [무관] 미배선 구역의 표에 없는 워드(0xFC0) 정렬 쓰기 뒤 조립 sticky 가 서지 않는다
  always @(posedge clk) if (f_step) w17_resv_wr: cover ($past(W && al && A == 12'hFC0 && !io_fault_cfgSurfBadWrite) && !io_fault_cfgSurfBadWrite);
  // W18 ← XlateSurface.flush_fires · XlateSurface.flush_scoped · Wt64Top.xlate_surface · a_xflush_iff · a_xflush_part · a_xonehot — [무관] 0xE00 기입이 파티션 3 flush 핀을 세운다
  always @(posedge clk) if (f_step) w18_xflush3: cover (hiu__io_flush_valid && hiu__io_flush_part == 2'd3);
  // W19 ← XlateSurface.commit_fires · XlateSurface.commit_whole · XlateSurface.commit_v_carried · Wt64Top.xlate_surface · a_xcm_iff · a_xcm_fields — [의존: hiu__installSlotFree 핀 — 실물 근거 XlateStore_props.sv w8_slot_written (채움 슬롯이 비어 슬롯 여유가 선다)] V=0 COMMIT 이 래치된 VPN 과 함께 설치 핀에 닿는다 (FRAME 없이도 — V=0 은 VPN 유효만 요구한다)
  always @(posedge clk) if (f_step) w19_xcm_v0: cover (hiu__io_install_valid && !hiu__io_install_v && {hiu__io_install_tag, hiu__io_install_idx} != 32'd0 && !f_xfv);
  // W20 ← Wt64Top.xlate_surface · a_ready_only_slot · a_xhold_quiet — [의존: hiu__installSlotFree 핀 — 실물 근거 XlateStore_props.sv w13_slot_busy (점유 중 슬롯 여유 하강)] 주소 · 상태 적법 COMMIT 쓰기가 하류 거부로 버스를 정지시킨다
  always @(posedge clk) if (f_step) w20_xstall: cover (xHold && !io_mmio_ready);
  // W21 ← XlateSurface.commit_needs_vpn · XlateSurface.reject_loud · Wt64Top.xlate_surface · a_surf_fire — [무관] reset 뒤 VPN 없이(빈 스테이징) 온 COMMIT(0xC08 — 래치 파티션 reset 값 0 과 같은 기저)은 하류 상태와 무관하게 곧장 거절되고 조립 sticky 를 세운다
  always @(posedge clk) if (f_step) w21_xcm_rej: cover ($past(W && al && A == 12'hC08 && !f_xvv && !io_fault_cfgSurfBadWrite) && io_fault_cfgSurfBadWrite);
  // W22 ← Wt64Top.xlate_surface · a_miss_clr — [무관] 0xE10 [0]=1 이 IO 해제선 없이 미적중 해제 핀을 세운다
  always @(posedge clk) if (f_step) w22_missclr: cover (hiu__io_missClear && !io_faultClear_hiuMiss);
  // W23 ← XlateSurface.flush_part_exists · XlateSurface.reject_loud · Wt64Top.xlate_surface · a_xflush_iff · a_surf_fire — [무관] 없는 파티션(4)의 XLATE_FLUSH 는 flush 핀 없이 조립 sticky 를 세운다
  always @(posedge clk) if (f_step) w23_xflush_rej: cover ($past(W && al && A == 12'hE00 && D == 32'd4 && !io_fault_cfgSurfBadWrite) && io_fault_cfgSurfBadWrite && !$past(hiu__io_flush_valid));
  // W24 ← XlateSurface.frame_stages_only · a_xcm_iff · a_surf_rise — [무관] FRAME 까지 찬 스테이징을 다른 파티션 · VPN 의 VPN 기입이 덮고 조용하다 (flush 핀도 조립 sticky 도 서지 않는다)
  always @(posedge clk) if (f_step) w24_xvpn_over: cover ($past(xVpnW && f_xvv && f_xfv && xp != f_xlp && D != f_xvpn && !io_fault_cfgSurfBadWrite) && !io_fault_cfgSurfBadWrite && !$past(hiu__io_flush_valid));
  // W25 ← XlateSurface.commit_fires · a_xcm_iff · a_xcm_fields — [의존: hiu__installSlotFree 핀 — 실물 근거 XlateStaging_props.sv w9_recommit (같은 스테이징으로 온 COMMIT 둘이 둘 다 커밋 — 문 단독)] VPN 없이 같은 항목의 COMMIT 이 다시 커밋된다 (e-defined.typ:306 「커밋은 스테이징을 소진하지 않는다」. flush 를 건넌 재커밋은 W40 이 끊는다)
  always @(posedge clk) if (f_step) w25_xrecommit: cover (hiu__io_install_valid && $past(hiu__io_install_valid, 2) && !$past(xVpnW) && {hiu__io_install_part, hiu__io_install_tag, hiu__io_install_idx} == $past({hiu__io_install_part, hiu__io_install_tag, hiu__io_install_idx}, 2));
  // W26 ← XlateSurface.commit_base_match · XlateSurface.reject_loud · a_xcm_iff · a_surf_fire — [무관] 래치 파티션과 다른 기저의 COMMIT 이 곧장 거절되고 조립 sticky 를 세운다
  always @(posedge clk) if (f_step) w26_xcm_mismatch: cover ($past(xCmW && f_xvv && xp != f_xlp && !io_fault_cfgSurfBadWrite) && io_fault_cfgSurfBadWrite);
  // W27 ← XlateSurface.flush_rsv_strict · XlateSurface.reject_loud · a_xflush_iff · a_surf_fire — [무관] 실재 파티션이지만 [31:8] 비0 인 XLATE_FLUSH 는 flush 핀 없이 조립 sticky 를 세운다
  always @(posedge clk) if (f_step) w27_xflush_rsv: cover ($past(W && al && A == 12'hE00 && D[31:8] != 24'd0 && D[7:0] < 8'd4 && !io_fault_cfgSurfBadWrite) && io_fault_cfgSurfBadWrite && !$past(hiu__io_flush_valid));
  // W28 ← Wt64Top.word_reserved_strict · Wt64Top.abort_surface · AbortSurface.reject_loud · AbortSurface.legal_first · a_surf_fire · a_arm_rej1 — [무관] ABORT_TAG1 [26] trace 비0 정렬 쓰기는 조립 sticky 를 세우고 무장 [1] 을 세우지 않는다
  always @(posedge clk) if (f_step) w28_tag1_trace_rej: cover ($past(W && al && A == 12'hF44 && D[27:16] == 12'h400 && !io_fault_cfgSurfBadWrite && !stg_io_armed[1]) && io_fault_cfgSurfBadWrite && !stg_io_armed[1]);
  // W29 ← MmioPage.leg_write_rejected · MmioPage.reject_loud · a_surf_fire — [무관] 물려받은 구간(0x040) 쓰기가 조립 sticky 를 처음 세운다 (판정 T3 (d) — 옛 역-변이 L1 의 반전)
  always @(posedge clk) if (f_step) w29_leg_wr: cover ($past(W && al && A == 12'h040 && !io_fault_cfgSurfBadWrite) && io_fault_cfgSurfBadWrite);
  // W30 ← MmioPage.nocons_rejected · a_surf_fire — [무관] SQ_SIZE(0x388) 정렬 쓰기가 조립 sticky 를 처음 세운다 (판정 T1-i β)
  always @(posedge clk) if (f_step) w30_sq_wr: cover ($past(W && al && A == 12'h388 && !io_fault_cfgSurfBadWrite) && io_fault_cfgSurfBadWrite);
  // W31 ← MmioPage.ro_rejected · a_surf_fire — [무관] HIU_ABI_VERSION(0xFFC) 정렬 쓰기가 조립 sticky 를 처음 세운다 (판정 T1-ii — E.1.1 RO)
  always @(posedge clk) if (f_step) w31_ffc_wr: cover ($past(W && al && A == 12'hFFC && !io_fault_cfgSurfBadWrite) && io_fault_cfgSurfBadWrite);
  // W32 ← MmioPage.unaligned_rejected · MmioPage.reject_loud · a_surf_fire · a_arm_unal — [무관] 비정렬 ABORT_TAG0(0xF41) 쓰기는 무장을 세우지 않고 조립 sticky 를 처음 세운다 (판정 T2 (a) · E.12.1 1항)
  always @(posedge clk) if (f_step) w32_unal_tag0: cover ($past(W && A == 12'hF41 && !io_fault_cfgSurfBadWrite && stg_io_armed == 3'd0) && io_fault_cfgSurfBadWrite && stg_io_armed == 3'd0);
  // W33 ← MmioPage.rsp_on_accept · a_rv_acc · a_ready_fpw — [의존: fps__io_loadReady 핀 — 실물 근거 없음(StepSequencer 의 sby 태스크 0 건 — 소거 구간은 cocotb fp_clear_window ① 이 값 수준으로 잰다)] 소거 중(loadReady 0) 0xF00 읽기는 기다리지 않고 다음 사이클 응답 + 0 이다 (D1 (b))
  always @(posedge clk) if (f_step) w33_fp_rd_clear: cover ($past(R && A == 12'hF00 && !fps__io_loadReady && io_mmio_ready) && io_mmio_rvalid && io_mmio_rdata == 32'd0);
  // W34 ← MmioPage.effect_on_accept · MmioPage.reject_loud · a_fpbad_fire · a_fpbad_rise — [의존: fps__io_loadReady 핀 — 실물 근거 없음(위와 같다 — cocotb fp_clear_window ②)] 수락된 FP_BIND 예약 비0 기입이 별도 sticky 를 처음 세운다
  always @(posedge clk) if (f_step) w34_fpbad: cover ($past(fpBad && !io_fault_fpCfgBadWrite) && io_fault_fpCfgBadWrite);
  // W35 ← MmioPage.effect_on_accept · a_ready_fpw · a_fpbad_rise — [의존: fps__io_loadReady 핀 — 실물 근거 없음(위와 같다)] 소거 중 잡힌(ready 0) FP_BIND 예약 비0 기입은 어느 sticky 도 세우지 않는다 (D1 — 수락 전 loud 없음)
  always @(posedge clk) if (f_step) w35_fpbad_held: cover ($past(W && al && A == 12'hF04 && D[30:24] != 7'd0 && !io_mmio_ready &&
      !io_fault_fpCfgBadWrite && !io_fault_cfgSurfBadWrite) && !io_fault_fpCfgBadWrite && !io_fault_cfgSurfBadWrite);
  // ── 파도 4 증인 — 미적중 관측 값 (XlateObs 포장 절반 · 3B) ──
  // W36 ← XlateObs.obs_stall_live · XlateObs.obs_part_stalled · XlateObs.obs_sticky · a_rd_xstatus — [의존: hiu__missStall · hiu__missPart · hiu__io_missNotice 핀 — 실물 근거 HiuMask_props.sv w19_obs_stall · w21_sticky_holds] 정지 중 STATUS 읽기가 [0] · [1] · 비0 파티션을 낸다
  always @(posedge clk) if (f_step) w36_xstatus_stall: cover ($past(R && al && A == 12'hE04) && io_mmio_rvalid && io_mmio_rdata[0] && io_mmio_rdata[1] && io_mmio_rdata[9:8] != 2'd0);
  // W37 ← XlateObs.obs_vpn_stalled · a_rd_xvpnlo · a_rd_xvpnhi — [의존: hiu__missStall · hiu__missVpn 핀 — 실물 근거 HiuMask_props.sv w19_obs_stall] 정지 중 VPN 두 워드 읽기 — 하위는 비0 · 상위는 0 (VA 44b)
  always @(posedge clk) if (f_step) w37_xvpn_lo: cover ($past(R && al && A == 12'hE08 && hiu__missStall) && io_mmio_rvalid && io_mmio_rdata != 32'd0);
  always @(posedge clk) if (f_step) w37_xvpn_hi: cover ($past(R && al && A == 12'hE0C && hiu__missStall && hiu__missVpn != 32'd0) && io_mmio_rvalid && io_mmio_rdata == 32'd0);
  // W38 ← XlateObs.obs_no_residue · XlateObs.obs_sticky · a_rd_xstatus — [의존: hiu__missStall · hiu__io_missNotice 핀 — 실물 근거 HiuMask_props.sv w20_after_zero · w21_sticky_holds] 정지가 없는데 sticky 가 선 채의 STATUS 읽기 — [0] 0 · [1] 1 · 파티션 0 (두 비트가 갈린다)
  always @(posedge clk) if (f_step) w38_xstatus_after: cover ($past(R && al && A == 12'hE04) && io_mmio_rvalid && !io_mmio_rdata[0] && io_mmio_rdata[1] && io_mmio_rdata[15:8] == 8'd0);
  // W39 ← XlateObs.obs_read_pure · a_miss_clr · a_hiu_pass — [무관] STATUS 읽기 사이클에 IO 해제선 없이 미적중 해제 핀도 flush 핀도 서지 않는다 (읽기는 해제 명령을 내지 않는다 — 설치 핀은 콘에 절단 핀 hiu__installSlotFree 가 들어 여기 넣지 않는다: a_xcm_iff 가 W 를 전건에 든다)
  always @(posedge clk) if (f_step) w39_xread_pure: cover (R && al && A == 12'hE04 && !io_faultClear_hiuMiss && !hiu__io_missClear && !hiu__io_flush_valid);
  // W40 ← XlateSurface.flush_drops_staging · XlateSurface.commit_needs_vpn · XlateSurface.reject_loud · a_xcm_iff · a_surf_fire — [무관] 래치 파티션의 적법 XLATE_FLUSH 가 스테이징을 비운 뒤(그림자: VPN 유효 0 · VPN ≠ reset 값 0 — VPN 값은 VPN 기입으로만 바뀌고 그 기입은 유효를 세우므로 그 조합은 flush 하강뿐이다) 같은 기저의 COMMIT 이 거절되고 조립 sticky 를 세운다 — 판정 전 RTL 이 옛 스테이징을 커밋하던 입력 (판정 T5 (a) · (f) 7항)
  always @(posedge clk) if (f_step) w40_xflush_ends: cover ($past(xCmW && !f_xvv && (f_xvpn != 32'd0) && (xp == f_xlp) && !io_fault_cfgSurfBadWrite) && io_fault_cfgSurfBadWrite);
  // ── W1 증인 (3.10 v1.0 묶음 — FAULT_STATUS [19] · 0xFF8 HIU_SHAPE · 0xEC4 MASK_DUP_CAPTURE) ──
  // W41 ← MmioPage.ro_rejected · Wt64Top.hiu_shape · a_surf_fire — [무관] HIU_SHAPE(0xFF8) 정렬 쓰기가 조립 sticky 를 처음 세운다 (예약 관대였던 HEAD 의 반전 — uResv 축소의 절단 무관 증인)
  always @(posedge clk) if (f_step) w41_shape_wr: cover ($past(W && al && A == 12'hFF8 && !io_fault_cfgSurfBadWrite) && io_fault_cfgSurfBadWrite);
  // W42 ← MmioPage.ro_rejected · Wt64Top.mask_surface · a_surf_fire — [무관] MASK_DUP_CAPTURE(0xEC4) 정렬 쓰기가 조립 sticky 를 처음 세운다 (미정의 워드였던 HEAD 의 반전)
  always @(posedge clk) if (f_step) w42_dupcap_wr: cover ($past(W && al && A == 12'hEC4 && !io_fault_cfgSurfBadWrite) && io_fault_cfgSurfBadWrite);
  // W43 ← MmioPage.resv_lenient · a_surf_rise — [무관] 줄어든 uResv 의 끝 워드(0xFF4) 정렬 쓰기 뒤 조립 sticky 가 서지 않는다 (예약 관대가 0xFF8 앞에서 끝난다)
  always @(posedge clk) if (f_step) w43_resv_ff4: cover ($past(W && al && A == 12'hFF4 && !io_fault_cfgSurfBadWrite) && !io_fault_cfgSurfBadWrite);
  // W44 ← Wt64Top.hiu_shape · a_rd_shape — [의존: rdata mux 콘에 유닛 rdata 핀 — 값은 덮어쓰기라 핀과 무관(실물 근거 = 이 등식)] 0xFF8 읽기가 형상 값을 낸다
  always @(posedge clk) if (f_step) w44_shape_rd: cover ($past(R && al && A == 12'hFF8) && io_mmio_rvalid && io_mmio_rdata == F_HIU_SHAPE);
  // W45 ← Wt64Top.mask_surface · a_rd_dupcap — [의존: mask__dupCapture 핀 — 실물 근거 MaskEngine_props.sv w11_dup_latch] 0xEC4 읽기가 [16] = 1 · 비트맵 비0 인 캡처를 낸다
  always @(posedge clk) if (f_step) w45_dupcap_rd: cover ($past(R && al && A == 12'hEC4) && io_mmio_rvalid && io_mmio_rdata[16] && io_mmio_rdata[15:8] != 8'd0);
  // W46 ← Wt64Top.fault_status_map · a_rd_fst · a_fsrc_b19 — [의존: hiu__faultOwn 핀 — 실물 근거 HiuMask_props.sv w13_unowned_loud] 0xF80 읽기가 [19] 를 내고 원천별 수출도 선다
  always @(posedge clk) if (f_step) w46_fst_rd19: cover ($past(R && al && A == 12'hF80 && io_fault_hiuOwn) && io_mmio_rdata[19] && !io_mmio_rdata[4]);
  // W47 ← Wt64Top.fault_clear_routing · a_fclr_b19 · a_rd_pure — [무관] 0xF84 [19] 수락 기입이 IO 해제선 없이 [19] 해제 핀을 세우고, 0xEC4 읽기 사이클에는 해제 핀이 서지 않는다
  always @(posedge clk) if (f_step) w47_fclr_b19: cover (W && al && A == 12'hF84 && D == 32'h0008_0000 && hiu__faultOwnClear);
  always @(posedge clk) if (f_step) w47_read_pure: cover (R && al && A == 12'hEC4 && !io_faultClear_maskNonceDup && !mask__io_faultClearNonceDup && !hiu__faultOwnClear);
  // ── W3 증인 (3.10 v1.0 묶음 — 형상 비노출 0xC00 문) ──
  // W48 ← XlateSurface.commit_needs_frame · XlateSurface.reject_loud · a_xbad_fire · a_xbad_rise — [의존: hiu__installSlotFree 핀 — 실물 근거 XlateStaging_props.sv w18_no_frame (수락 사이클의 데이터 사유 거절)] FRAME 없는 V=1 COMMIT 이 수락되어 원천별 sticky 를 처음 세우고 조립 sticky 는 서지 않는다
  always @(posedge clk) if (f_step) w48_xbad_noframe: cover ($past(xBadAcc && !f_xfv && D[31] && D[27:0] == 28'd0 && !io_fault_xlateCfgBadWrite && !io_fault_cfgSurfBadWrite) && io_fault_xlateCfgBadWrite && !io_fault_cfgSurfBadWrite);
  // W49 ← XlateSurface.rsvw_rejected · XlateSurface.reject_loud · a_surf_fire — [무관] 래치 기저의 예약-엄격 워드(+0x7C) 정렬 쓰기가 조립 sticky 를 처음 세운다 (W3 전 RTL 은 그 자리를 LO/HI 로 수락했다)
  always @(posedge clk) if (f_step) w49_xrsvw: cover ($past(xRsW && (xw == 5'd31) && xPair && !io_fault_cfgSurfBadWrite) && io_fault_cfgSurfBadWrite);
  // W50 ← XlateSurface.vpnhi_strict · XlateSurface.reject_loud · a_surf_fire — [무관] 래치 기저의 비0 VPN_HI 정렬 쓰기가 조립 sticky 를 처음 세운다
  always @(posedge clk) if (f_step) w50_xvpnhi: cover ($past(xVhW && xPair && D != 32'd0 && !io_fault_cfgSurfBadWrite) && io_fault_cfgSurfBadWrite);
  // W51 ← XlateSurface.frame_pair_check · XlateSurface.reject_loud · a_surf_fire — [무관] VPN 이 래치된 기저와 다른 기저의 FRAME 정렬 쓰기가 조립 sticky 를 처음 세운다
  always @(posedge clk) if (f_step) w51_xframe_pair: cover ($past(xFrW && f_xvv && xp != f_xlp && !io_fault_cfgSurfBadWrite) && io_fault_cfgSurfBadWrite);
  // W52 ← XlateSurface.vpn_drops_frame · XlateSurface.commit_rsv_strict · a_xbad_fire · a_xcm_iff — [의존: hiu__installSlotFree 핀 — 실물 근거 XlateStaging_props.sv w17_vpn_drops · w23_cm_rsv] FRAME 까지 찬 스테이징에 VPN 을 다시 쓴 뒤의 V=1 COMMIT · 또는 [27:0] 비0 COMMIT 이 수락되어 설치 핀 없이 원천별 sticky 를 세운다
  always @(posedge clk) if (f_step) w52_xbad_vpn_drops: cover ($past(xBadAcc && D[31] && !f_xfv && D[27:0] == 28'd0 && !io_fault_xlateCfgBadWrite) && $past(xVpnW && f_xfv, 2) && io_fault_xlateCfgBadWrite);
  always @(posedge clk) if (f_step) w52_xbad_rsv: cover ($past(xBadAcc && f_xfv && D[27:0] != 28'd0 && !hiu__io_install_valid && !io_fault_xlateCfgBadWrite) && io_fault_xlateCfgBadWrite);
`endif
endmodule

bind Wt64Top Wt64Top_props chk (.*);
