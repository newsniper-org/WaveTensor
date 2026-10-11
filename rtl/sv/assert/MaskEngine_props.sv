// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
//
// MaskEngine 후-formal 하네스 — MaskUnit 재키잉 엔진 창의 **시간 축**.
// FINAL 엣지 동시 기입 모서리 (파도 D, 2026-09-22). 선-formal
// rtl/formal/tla/MaskEngine.tla 의 가드 넷을 생성물 rtl/generated/MaskUnit.sv
// 위에서 다시 잰다. Mask.tla / HiuMask 합성(hiumask.sby)이 「어느 파티션」을,
// 이 하네스가 「언제」를 든다 — E.9 4항의 두 면.
//
// **W1 (3.10 v1.0 묶음 RTL 파도 — 표면 비트·워드, 2026-10-11)** 이 이 하네스에
// 둘째 축을 더했다: FAULT_STATUS `[11]`/`[12]` 의 발화와 `0xEC4` MASK_DUP_CAPTURE
// 의 래치·해제 (아래 「W1 — 논스 재사용 판정 · 캡처」 절). 선-formal 은
// rtl/formal/tla/Mask.tla 의 새 가드 여덟이다 (dup_on_started_rekey · cap_first_event ·
// cap_clear_whole · cap_set_beats_clear · cap_bitmap_exact · cap_bitmap_domain ·
// start_ignores_dup · complete_ignores_dup).
//
// 정본 (좌표 뒤 「」 는 그 줄의 축자 — lint_section_refs 축 1 이 대조한다):
//   e-defined.typ:518 「재키잉 중 입력 기입」 — FAULT_STATUS [13]. 시점 예외가
//     없다: 재키잉 *중*이면 어느 사이클의 기입이든 이 비트다.
//   e-defined.typ:347 「`[8]` 엔진 busy · `[9]` 재키잉 수락 가능」 — MASK_STATUS.
//     「재키잉 중」의 정의는 장치 자신의 관측 busy=1 이고, 이 하네스의 busy 창은
//     그 포트(io_busy) 그대로다.
//   e-defined.typ:1549 「재계산 중(`0xEC0` `[8]`)」 — 정본 자신이 「재키잉 중」의
//     정의역을 [8] 로 준다.
//   e-defined.typ:1525 「옛 키로 만든 주소와 새 키로 만든 주소가 섞이면 안 된다」
//     — 오염 완료는 유효화하지 않는다.
//   e-defined.typ:1526 「다른 파티션이 그 변경의 사정권 밖」 — 타 파티션 기입은
//     오염이 아니다 (dirty_scoped).
//   05-security.typ:384 「소실도 loud 여야 한다」 — 유효화하지 않은 완료는
//     반드시 sticky 를 세운다. 오염이 아니어도 관측이 없으면 결손이다.
//   MaskUnit.scala:148 「계산 중 입력이 바뀐 재키잉은 결과를 유효화하지 않는다」
//     — 그 파일 자신의 계약. 파도 D 가 「FINAL 사이클 포함」을 더했다.
//   MaskUnit.scala:473 「val dirtyNow = compDirty || wrActNow」 — 파도 D 의 RTL:
//     FINAL 가지가 레지스터에 더해 **같은 사이클 항**을 직접 본다.
//   MaskUnit.scala:481 「maskValid(actPart) := !dirtyNow」 — 유효화의 식.
//   MaskUnit.scala:238 「워드 0..5. 6·7 기입은 무시한다」 — 논스 예약 오프셋
//     정책. 이 하네스는 그 경계를 리터럴(idx < 6)로 다시 적는다.
//   Common.scala:334 「해제와 발화가 같은 사이클이면 발화가 이긴다」 — StickyFault
//     규약. a_dirty_final_loud 의 전건은 해제를 배제하지 않으므로 그 겹침도
//     이 유닛에서 잰다 (도달은 증인 W6).
//   ── W1 이 더한 정본 근거 (같은 규율 — 좌표 뒤 같은 줄 축자) ──
//   e-defined.typ:516 「미준비 마스크 통과」 — FAULT_STATUS [11].
//   e-defined.typ:517 「논스 재사용 재키잉」 — FAULT_STATUS [12].
//   e-defined.typ:345 「p 자신은 비교에 들지 않는다」 — [12] 판정의 정의역: 재키잉이
//     *시작된* 발화(엔진 유휴 수락)가 지목한 p 에 대해, 마스크가 유효한 다른 q ≠ p 중
//     논스가 p 의 새 논스와 같은 것이 있을 때.
//   e-defined.typ:345 「거절 + `[6]` 인 발화는 `[12]` 도 `0xEC4` 도 움직이지 않는다」 —
//     값 검사 거절은 Wt64Top 이 rekey.valid 를 세우지 않는 것으로 이 유닛에 닿지
//     않는다 (assembly.sby a_rekey_iff). 이 유닛에서 「시작된」은 valid ∧ ready 다.
//   e-defined.typ:347 「`[31:17]` RO 예약 = 0」 · 「p 번 비트는 늘 0」 — 캡처 워드 배치.
//   e-defined.typ:347 「`[16]` = 1 동안의 새 발화는 캡처를 덮지 않는다」 — 첫 사건 보존.
//   e-defined.typ:347 「해제와 새 발화가 같은 사이클이면 새 사건을 래치한다」 — 세움 우선.
//   e-defined.typ:347 「`[12]` 와 함께 이 워드를 지운다」 — 해제는 워드 전체 (내부
//     해제선 포함 — 이 유닛에서 해제는 io_faultClearNonceDup 하나다).
//   e-defined.typ:347 「완료 전까지 `[8]` = 1 을 본다」 — 시작된 재키잉은 busy 로 간다.
//   e-defined.typ:527 「재키잉의 완료(`0xEC0` `[8]` 하강)는 `[12]` 와 무관하게 온다」.
//   e-defined.typ:216 「모든 파티션의 마스크 유효 = 0 · 키 · 논스 = 0」 — 논스 섀도우의
//     reset 값의 근거 (reset 형식 단언은 W1 범위 밖 — 아래 「재지 않는 것」).
//
// ## 이 하네스가 잡는 정확한 결함
//
// 파도 D 이전 판(1666c7a)의 RTL: 활성 파티션으로 향한 키·논스 기입이 정확히
// FINAL 사이클(io_busy=1 · io_rekey_ready=0 — 장치 자신이 「재키잉 중」이라
// 말한다)에 실리면, 기입 표면의 compDirty := True 는 레지스터라 다음 사이클에야
// 1 이 되고 FINAL 가지는 레지스터의 엣지 전 값 0 만 실어 sticky 가 서지
// 않았다. 유효는 기입 표면의 텍스트 순서로 떨어진다. 실측: 수락+42 엣지 기입
// → maskReady[p]=0 · faultWrDuringRekey=0, 수락+40·+41 → fault=1. 안전 결손이
// 아니라 **관측 결손**이다 — 같은 호스트 행위가 1사이클 타이밍에 두 판정을
// 받고, 호스트는 「아직 안 끝남」과 「내 기입이 결과를 버렸다」를 가를 수 없다.
// a_final_overlap_loud 가 그 판에 bmc 반례를 낸다 (engine.sby §역-변이 mutA).
//
// ## 부착 방식
//
// 래퍼 모듈 MaskUnit_formal 이 DUT 를 인스턴스하고 **포트에만** 검사자를
// 붙인다. bind 는 yosys 0.66 이 조용히 무시한다 (SharedUnit_props.sv 파일
// 머리의 실측). 필요한 신호가 전부 포트라 expose 도 없다 — 내부 이름(phase ·
// compDirty · actPart · 줄번호 매인 when 이름)을 하나도 참조하지 않으므로 Scala
// 줄 밀림에 이 하네스가 무력화될 자리가 없다. W1 의 캡처 워드도 클래스 끝 포트
// dupCapture 다 (io_ 접두 없는 생성 이름 — installSlotFree 관례).
//
// ## 지상 진리는 포트에서 다시 적는다 (DUT 어휘를 재인용하지 않는다)
//
//   f_fire   = io_rekey_valid && io_rekey_ready — 수락 엣지.
//   f_act    — 수락 엣지에서 io_rekey_part 를 래치 (RTL actPart 의 독립 사본).
//   f_dirty  — busy 창 안에서 활성 파티션으로 향한 기입이 **직전 사이클까지**
//              있었는가. 두 갈래: (i) 수락 사이클 자체의 io_rekey_part 기입
//              (RTL 기입 표면의 rekeyFire ∧ part = rekey.part 가지 — 유도 초기
//              상태가 그 사이클의 옛 값을 래치한다) · (ii) io_busy 중 f_act 기입.
//              수락에서 (i) 로 다시 시작한다. 이 레지스터가 RTL compDirty 와
//              같은 시점 의미다 — 이번 사이클의 기입은 아직 아니다.
//   wrAct    — **이 사이클**의 활성 파티션 기입 (io_busy 중). FINAL 사이클의
//              wrAct 가 모서리다: 레지스터 f_dirty 는 그것을 보지 못한다.
//   완료 엣지 = $past(io_busy) && !io_busy — 직전 사이클이 FINAL 이었다.
//   기입 = 키 워드 기입(어느 idx 든) 또는 논스 워드 기입 idx < 6 (리터럴 —
//          예약 오프셋 6·7 은 기입이 아니다; 그 경계를 넓힌 변이는
//          a_clean_final_validates 에서 반례가 난다. 도달은 증인 W10).
//   f_act 는 완료 엣지 사이클에 $past(f_act) 와 같다 — busy 중에는 수락이 없어
//   f_act 가 바뀌지 않고, 완료 사이클의 새 수락은 다음 엣지에야 래치된다.
//   그래서 완료 사이클의 관측은 io_maskReady[f_act] 로 적는다.
//   ── W1 이 더한 지상 진리 ──
//   논스 탐침 (W1 — $anyconst 축약, 아래 「논스 탐침」 절이 근거와 실측을 든다):
//     f_rm  — 래퍼의 anyconst 1b. 0 이면 환경은 종전 그대로 자유다(기존 단언 · 논스 무관
//             W1 단언이 그 위에서 선다). 1 이면 「탐침 환경」: 논스 기입은 탐침 자리 (워드
//             f_pw, 비트 f_pb) 의 워드 또는 예약 오프셋(6·7)으로만 가고 데이터는 탐침 비트 밖이
//             0 이다 (as_probe_env). 탐침 자리는 고정 여섯 — 워드마다 하나, 비트 0 · 7 · 13 ·
//             19 · 26 · 31 — 중 래퍼의 anyconst f_ps 가 고른다.
//     f_pbit[q] — 파티션 q 의 탐침 자리 섀도우 — io_nonceWr_* 미러, reset 0. 탐침 환경에서 그
//             밖의 논스 비트는 reset 값 0 에 머문다(정본 reset 규범) — 그래서 「논스(q) ==
//             논스(p)」 ⇔ f_pbit[q] == f_pbit[p] 다. DUT 의 nonce 레지스터 · nonceDupQ ·
//             nonceDup 은 하나도 참조하지 않는다.
//   f_vOther = io_maskReady ∧ ¬(bit io_rekey_part) — 마스크가 유효한 *다른* 파티션 (MASK_STATUS
//              [7:0] 의 포트 관측 · 수락 사이클의 엣지 전 값).
//   f_dupQ[q] = f_vOther[q] ∧ (f_pbit[q] == f_pbit[io_rekey_part]) — [12] 판정과 [15:8] 비트맵의
//              *한* 정의역 (정본이 둘을 같은 정의역으로 묶었다). **탐침 환경(f_rm)에서만 정확**하다.
//   f_mayDup = f_fire ∧ f_vOther ≠ 0 ∧ (¬f_rm ∨ f_dupQ ≠ 0) — [12] 세움이 *가능한* 사이클.
//              탐침 환경에서는 세움 사건 그 자체이고, 자유 환경에서는 그 상계(논스 항을 모른다).
//   해제     = io_faultClearNonceDup — 이 유닛에서 [12] 와 캡처의 해제는 이 입력
//              하나다 (조립이 IO 해제선 ∨ 0xF84 [12] 를 합류시킨다 — assembly
//              a_fclr_b12). **자유 입력이다** — 거절 · busy 발화 사이클에도 해제가
//              올 수 있다 (선-formal Mask.tla 의 RekeyBad · busy 분기가 c ∈ {none, io}
//              를 연 것과 같은 자리). 막는 가정을 두지 않는다.
//   f_nmEv   = io_en ∧ io_req_valid ∧ ¬io_maskReady[io_req_part] — [11] 세움 사건
//              (미준비 마스크를 요청이 *통과*하는 사이클 = 공통 enable 이 선 사이클).
//
// 가드 ↔ 단언 대응:
//   MaskEngine.dirty_loud
//     : a_final_overlap_loud (완료 직전 사이클 = FINAL 에 활성 파티션 기입이
//       있었으면 sticky 가 섰다 — **모서리 자체**) · a_dirty_final_loud
//       (직전 사이클까지의 오염이 있었으면 sticky 가 섰다 — 레지스터 경로) ·
//       a_fault_rise_at_final_only (sticky 상승 원천은 완료 엣지뿐)
//   MaskEngine.invalidate_beats_validate
//     : a_final_overlap_no_validate (FINAL 사이클의 활성 파티션 기입은 유효화를
//       이긴다 — 완료 뒤 그 비트는 0)
//   MaskEngine.dirty_no_validate
//     : a_dirty_final_no_validate (오염 완료는 유효화하지 않는다)
//   MaskEngine.dirty_scoped
//     : a_clean_final_validates (오염도 겹침도 없는 완료는 유효화한다 — 타
//       파티션 기입만 있었던 창도 「깨끗」이다: f_dirty 는 f_act 한정) ·
//       a_clean_final_quiet (그 완료는 sticky 를 세우지 않는다) ·
//       a_dirty_scoped (위 둘의 특수형 — 전건을 「busy 중 타 파티션 기입이
//       실재했던 창」으로 못박아 가드의 정의역 자체를 이름으로 든다. 위 둘에서
//       따라오지만, 이 가드가 그 전건에서 시험됐다는 것을 라벨로 남긴다;
//       전건 도달은 증인 W3). 파티션 무관 오염 변이(mutB)는 셋 다 깨뜨린다.
//   (앵커 없음 — 모델의 고정 불변식·규약 승계)
//     : a_fault_sticky (해제 없이 안 내려감) · a_accept_invalidates (수락은 옛
//       마스크를 즉시 무효화 — MaskEngine.tla Inv_BusyTargetInvalid 의 수락
//       엣지 면) · a_busy_target_invalid (busy 중 활성 파티션은 유효로 보이지
//       않는다 — 같은 불변식의 상태 면)
//   ── W1 (Mask.tla 의 새 가드 여덟) ──
//   Mask.dup_on_started_rekey
//     : n_dup_fire (세움 사건이면 다음 엣지에 [12] — 해제와 겹쳐도 · 탐침 환경) ·
//       n_dup_rise_src ([12] 의 상승 원천은 세움이 가능한 사이클뿐 — busy 미수락 발화 ·
//       유효한 다른 파티션이 없는 수락 · 탐침 환경에서 같은 논스가 없는 수락은 세우지 않는다) ·
//       n_dup_hold (해제 없이 내려가지 않는다) · n_dup_clear (세움이 불가능한 사이클의 해제는 내린다)
//   Mask.cap_first_event
//     : c_first ([16] = 1 ∧ ¬해제인 사이클을 건너 필드 [15:0] 불변 — 새 발화가 와도)
//   Mask.cap_clear_whole
//     : c_clr_zero ([12] = 0 이면 워드 전체 0 — 해제가 p · 비트맵까지 지운다)
//   Mask.cap_set_beats_clear
//     : c_set_wins ([16] = 1 ∧ 해제 ∧ 시작된 재키잉의 사이클 → 다음 엣지 워드 = 해제(0) 또는 그
//       *새* 사건 — p 와 비트맵 전부 (탐침 환경에서 비트맵 정확 등식). [16] · p 만 보면 같은 p 의
//       낡은 비트맵 변이를 놓친다)
//   Mask.cap_bitmap_exact
//     : c_latch (래치 사건 — [16] = 0 에서 시작된 재키잉이 [12] 를 세운 사건 — 의 다음 엣지
//       워드 = {[16]=1 · p · 비0 비트맵 ⊆ 유효한 다른 파티션} — bit p 는 늘 0 · [31:17] = 0.
//       전건은 **래치 사건**이지 「캡처가 바뀌었다」가 아니다. 논스 무관 — 자유 환경에서 선다)
//   Mask.cap_bitmap_domain
//     : c_latch_dom (같은 래치 사건의 비트맵 = 판정 정의역 f_dupQ — 탐침 환경의 정확 등식)
//   Mask.start_ignores_dup
//     : e_start_busy (시작된 재키잉은 다음 엣지에 busy — [12] 를 세운 것이어도) ·
//       e_idle_ready (유휴면 수락 가능 — 수락 판정에 논스 재사용 항이 없다)
//   Mask.complete_ignores_dup
//     : e_busy_bounded (busy 창은 F_BUSY_BOUND 사이클 안에 끝난다 — [12] 가 선 채로도) ·
//       e_busy_len_same (완료된 창의 길이는 첫 창의 길이와 같다 — 첫 창은 구조상 [12] = 0 인
//       창이라, [12] 에 기댄 유계 지연이 상계 안에 숨지 못한다. 아래 f_len0 해설)
//   (앵커 없음 — 구조 sanity · [11] 축)
//     : c_iff ([16] == [12] — W1-4 결정으로 [16] 은 [12] 레지스터 그 자체라 RTL 에서
//       구조다. 가드 앵커가 될 수 없다) · c_rsv ([31:17] = 0 상시) ·
//       n_nomask_fire · n_nomask_rise_src · n_nomask_hold ([11] — 선-formal 가드 없음.
//       조립층 assembly.sby 의 축별 발화 우선 표가 이 라벨을 출처로 든다)
//
// assume 목록 (전수):
//   as_reset_shape — reset 은 시각 0 에만 활성. 근거: 정본 1장의 ENV 계약
//   (모델 Init 대응이 reset 직후 상태) — CapStatusWord_props.sv 와 동일.
//   as_probe_word · as_probe_env (W1) — 탐침 워드는 0..5 다 · *f_rm = 1 일 때만* 논스 기입이
//   탐침 (워드, 비트) 밖을 건드리지 않는다. f_rm = 0 의 궤적은 종전 그대로 전부 남는다 —
//   이 둘이 지우는 것은 「탐침 환경 궤적 중 여러 비트 자리가 동시에 다른 논스」뿐이다
//   (아래 「논스 탐침」 절의 「재지 않는 것」).
//   기능 입력(io_keyWr_* · io_nonceWr_* · io_rekey_valid/part · io_en ·
//   io_req_* · io_faultClear*)은 전부 자유다 — busy 중 기입도, 수락과 같은
//   사이클의 기입도, 완료와 같은 사이클의 해제도 제약하지 않는다 (그것을
//   가정하면 이 하네스가 재러 온 모서리가 반례 공간에서 사라진다). W1 이 더한
//   assume 은 0 건이다 — io_faultClearNonceDup 은 세움 · busy 발화 · 래치 어느
//   사이클에도 자유다.
//
// 이 태스크가 재지 **않는** 것 (각각 어디가 재는가):
//   · busy 창의 정확한 길이(수락 뒤 42 엣지) · 라운드 수 · 마스크 값 — 여기서
//     busy 는 포트 io_busy 의 관측 그대로다. 증인이 깊이 안에서 도달한다는
//     것은 「창이 유한하고 깊이 안에 닫힌다」까지만 말한다. 정확한 오프셋
//     40·41·42·43·44 의 판정은 rtl/sim/test_mask_golden.py 의 지향 시험
//     wr_same_partition_at_final_edge_is_loud 이, 마스크 값은 golden 대조가 잰다.
//     (W1 의 e_busy_bounded 는 *상계*만, e_busy_len_same 은 「창마다 길이가 같다」는 *관계*만
//     건다 — 길이 값(42) 자체를 잰 것이 아니다.)
//   · 저장의 파티션 범위(key_scoped_storage · key_write_own_only) · REKEY 유휴
//     수락(rekey_idle_only) — HiuMask/hiumask.sby. MASK_PART 창 라우팅
//     (rekey_explicit_target) — Wt64Top/assembly.sby (CHECK — 파도 2 승격).
//   · 요청 경로의 고정 1사이클 — hiumask.sby. (논스 재사용 [12] · 미준비 통과 [11]
//     의 발화는 W1 부터 여기서 잰다.)
//   · 수락과 같은 사이클의 기입이 유도 초기 상태에 **값**으로 어떻게 실리는가 —
//     hiumask.sby 의 key_scoped_storage (섀도우 대조). 여기서는 그 기입이
//     오염(f_dirty 갈래 (i))으로 계수된다는 것까지다 (도달은 증인 W8).
//   · W1 — 값 검사 거절(예약 비0 · 없는 파티션)의 MASK_REKEY 가 [12] · 0xEC4 를
//     움직이지 않는다는 것: 그 발화는 이 유닛에 닿지 않는다 (rekey.valid 0 —
//     assembly a_rekey_iff). 0xEC4 읽기 결선 · 읽기 무부작용 · 쓰기 거절 + [6] ·
//     IO 해제선 ∨ 0xF84 [12] 의 합류 — assembly.sby (a_rd_dupcap · a_rd_pure ·
//     surfMust · a_fclr_b12). 캡처 워드의 reset 값 0 의 *형식* 단언 — W1 범위 밖
//     (W1-8 이월: 오늘은 c_clr_zero 가 reset 직후 [12] = 0 에서 워드 0 을 함께 잰다).
//   · W1 — 논스 비트맵 · [12] 판정의 *논스 항*은 탐침 환경(f_rm = 1)에서만 정확하게 잰다:
//     두 비트 자리 이상이 동시에 다른 논스 쌍에만, 또는 고정 탐침 여섯 밖의 한 비트 자리에만
//     나타나는 비교기 결함은 이 태스크를 통과한다 (아래 「논스 탐침」 절). 논스 무관 절반(시작된 재키잉 · 유효한 다른 파티션 · p · bit p ·
//     첫 사건 보존 · 해제 · 세움 우선의 구조)은 자유 환경에서도 잰다. 그 두 부류는 cocotb 가 지향
//     표본으로 잰다 — rtl/sim/test_mask_golden.py 의 nonce_dup_compare_every_bit 가 (나) 는 비교기 넷 ×
//     192 자리 전부, (가) 는 이웃 두 비트 차이 191 자리만(패리티 접기 변이를 잡는다), 그리고
//     sec1_golden_exact 가 80 라인 무작위 논스 쌍을 본다. 형식 증명이 아니다 — (가) 의 나머지(세 비트
//     이상 · 이웃하지 않은 두 비트 차이에만 나타나는 결함)는 어디서도 전수로 재지 않는다.
//   · W1 — 「같은 p 로 재래치하며 비트맵이 바뀌는」 궤적의 *도달*: RTL 에서는 재키잉
//     세 번 이상(엔진 창 43 사이클 × 3)이 필요해 bmc · cover 깊이 밖이다. 그 변이는
//     c_latch · c_set_wins 가 비트맵 전량 비교로 잡지만 bmc 반례는 깊이 밖이라 prove
//     (abc pdr — 무계)만 낸다. 선-formal 증인 Witness_NoStaleRelatch 가 추상 수준의
//     도달을 든다.
//
// 이 파일의 cover 는 태스크 구분 없이 컴파일된다 — bmc·prove 모델에서는 sby 가
// chformal 로 제거한다 (CapStatusWord_props.sv 와 같은 배치).

`default_nettype none

module MaskEngine_props (
    input wire        clk,
    input wire        reset,
    input wire        io_keyWr_valid,
    input wire [1:0]  io_keyWr_part,
    input wire        io_nonceWr_valid,
    input wire [1:0]  io_nonceWr_part,
    input wire [2:0]  io_nonceWr_idx,
    input wire        io_rekey_valid,
    input wire        io_rekey_ready,
    input wire [1:0]  io_rekey_part,
    input wire [3:0]  io_maskReady,
    input wire        io_busy,
    input wire        io_faultWrDuringRekey,
    input wire        io_faultClearWrRekey,
    // ── W1 — [11]/[12] · 0xEC4 (포트만) ──
    input wire [31:0] io_nonceWr_data,
    input wire        io_en,
    input wire        io_req_valid,
    input wire [1:0]  io_req_part,
    input wire        io_faultNoMask,
    input wire        io_faultClearNoMask,
    input wire        io_faultNonceDup,
    input wire        io_faultClearNonceDup,
    input wire [31:0] dupCapture,
    // W1 — 논스 탐침 (래퍼의 anyconst)
    input wire        f_rm,
    input wire [2:0]  f_ps
);

  reg f_past_valid = 1'b0;
  reg f_past_reset = 1'b1;
  always @(posedge clk) begin
    f_past_valid <= 1'b1;
    f_past_reset <= reset;
  end
  wire f_ok = f_past_valid && !reset && !f_past_reset;

  // as_reset_shape (근거는 파일 머리 참조)
  always @(*) as_reset_shape: assume (reset == !f_past_valid);

  // ═══ 지상 진리 — 포트에서 다시 적는다 ═══════════════════════════════
  wire f_fire     = io_rekey_valid && io_rekey_ready;
  // 논스 기입 적중 — 워드 0..5 만. 6 은 이 파일의 리터럴이다.
  wire f_nonceHit = io_nonceWr_valid && (io_nonceWr_idx < 3'd6);

  reg [1:0] f_act;        // 수락 엣지에 래치한 파티션
  reg       f_dirty;      // 직전 사이클까지의 활성 파티션 기입 (두 갈래 — 머리)
  reg       f_otherSeen;  // 이번 busy 창에 활성 아닌 파티션 기입이 있었는가
  reg       f_acceptWr;   // 이번 창의 오염이 수락 사이클 자체의 기입에서 시작했는가

  wire f_wrAct   = (io_keyWr_valid && (io_keyWr_part == f_act)) ||
                   (f_nonceHit     && (io_nonceWr_part == f_act));
  wire f_wrNew   = (io_keyWr_valid && (io_keyWr_part == io_rekey_part)) ||
                   (f_nonceHit     && (io_nonceWr_part == io_rekey_part));
  wire f_wrOther = (io_keyWr_valid && (io_keyWr_part != f_act)) ||
                   (f_nonceHit     && (io_nonceWr_part != f_act));
  // 이 사이클의 활성 파티션 기입 — busy 중 (FINAL 사이클 포함).
  wire wrAct = io_busy && f_wrAct;

  always @(posedge clk) begin
    if (reset) begin
      f_act       <= 2'd0;
      f_dirty     <= 1'b0;
      f_otherSeen <= 1'b0;
      f_acceptWr  <= 1'b0;
    end else if (f_fire) begin
      // 갈래 (i) — 수락 사이클 자체의 같은-파티션 기입은 오염이다.
      f_act       <= io_rekey_part;
      f_dirty     <= f_wrNew;
      f_acceptWr  <= f_wrNew;
      f_otherSeen <= 1'b0;
    end else if (io_busy) begin
      // 갈래 (ii) — busy 중 활성 파티션 기입. 타 파티션 기입은 오염이 아니다.
      if (f_wrAct)   f_dirty     <= 1'b1;
      if (f_wrOther) f_otherSeen <= 1'b1;
    end
  end

  // ═══ W1 — 논스 탐침 · [12] 판정의 정의역 · 세움 사건 ════════════════
  //
  // ## 논스 탐침 — 왜 전폭 섀도우가 아닌가 (실측, 2026-10-11 — 진행 중 W1 생성물 스냅숏)
  //
  // 첫 판은 4 × 192b 전폭 섀도우(io_nonceWr_* 미러)였다. 그 판은 세 엔진이 전부 **스텝 46**
  // — 첫 세움 사건이 가능해지는 스텝 — 에서 웨지했다: abc bmc3 프레임 46 에서 8 분+ 무진전 ·
  // abc pdr F[44] 에서 4 분+ 무진전 · btormc k=46 무진전 (논스 무관 단언만 둔 판은 bmc3 50
  // 프레임이 2 초). 원인은 섀도우와 DUT 논스 저장의 **등치 miter** 다 — 두 레지스터 파일이
  // 같은 기입을 받는다는 것을 SAT 가 프레임마다 비트마다 다시 배워야 한다. ABC scorr(신호
  // 대응)는 reset 제약을 써야만 둘을 합치는데 sby 가 제약을 먼저 접어(fold) 다중 속성
  // 모델에서 되살리지 못했다 (unfold 실패 · -m 판은 거짓 반례) — 엔진 전처리로 덮을 수 없다.
  // 그래서 지시서의 축약(「$anyconst 로 (q, 워드) 하나만 추적」)을 (워드, 비트) 로 좁혀 썼다:
  // 탐침 환경에서는 탐침 밖 논스 비트가 reset 값 0 에 머물러 등치가 탐침 비트 등치로 *정확히*
  // 환원되고, DUT 쪽 비교기의 나머지 비트는 단위 전파로 상수가 된다 — miter 가 1 비트 사슬로
  // 줄어든다. 자리를 anyconst 워드(6) × anyconst 비트(32) 로 연 판도 실측했다: 비트를 anyconst 로
  // 열면 다시 웨지한다 (워드 고정 · 비트 anyconst — bmc3 50 프레임 중 48 에서 200 초 시한 초과 ·
  // 워드 anyconst · 비트 고정 — 21 초 PASS · 둘 다 고정 — 5 초 PASS). 그래서 자리는 고정 여섯
  // (워드마다 하나 · 비트를 흩음) 중 anyconst 선택이다.
  //
  // 재지 않는 것 (축약의 대가 — 기계 밖 자백이 되지 않게 engine.sby 머리와 「재지 않는 것」에 같이
  // 적는다): (가) 탐침 환경에서 *두 비트 자리 이상이 동시에 다른* 논스 쌍 — 그것에만 나타나는
  // 비교기 결함(예: 비트 XOR 접기 비교)은 이 태스크를 통과한다. (나) 고정 여섯 밖의 비트 자리 —
  // 그 자리 *하나만* 무시하는 비교기 결함(예: 워드 2 의 비트 5 만 빼먹음)도 통과한다. 워드 하나를
  // 통째로 빼먹는 결함 · 위 · 아래 끝 비트를 무시하는 결함 · 다른 파티션의 논스를 기준으로 쓰는
  // 결함 · 유효 항 결함 · 폭을 줄인 비교(예: 하위 160b 만)는 여섯 자리 중 하나로 드러난다.
  // (가) · (나) 는 cocotb 가 지향 표본으로 잰다 — 위 「재지 않는 것」 절의 nonce_dup_compare_every_bit ·
  // sec1_golden_exact ((나) 는 192 자리 전부, (가) 는 이웃 두 비트 차이와 무작위 쌍만). W1 검증이 (나) 의
  // 실례(워드 0 비트 1 만 무시)를 이 태스크 · 기존 cocotb 열한 시험이 전부 통과시키는 것을 실측했고
  // (변이 X14), 그 스윕이 그 자리에서 잡는다.
  //
  // 탐침 자리 — 고정 여섯(워드마다 하나 · 비트 0 · 7 · 13 · 19 · 26 · 31) 중 래퍼의 anyconst f_ps.
  // 고정 자리라야 탐침 밖 비트가 *무조건* 상수가 된다 (위 실측).
  reg [2:0] f_pw;
  reg [4:0] f_pb;
  always @(*) begin
    case (f_ps)
      3'd0: begin f_pw = 3'd0; f_pb = 5'd0;  end
      3'd1: begin f_pw = 3'd1; f_pb = 5'd7;  end
      3'd2: begin f_pw = 3'd2; f_pb = 5'd13; end
      3'd3: begin f_pw = 3'd3; f_pb = 5'd19; end
      3'd4: begin f_pw = 3'd4; f_pb = 5'd26; end
      default: begin f_pw = 3'd5; f_pb = 5'd31; end
    endcase
  end
  always @(*) as_probe_word: assume (f_ps < 3'd6);
  always @(*) if (f_rm && io_nonceWr_valid)
    as_probe_env: assume (((io_nonceWr_idx == f_pw) || (io_nonceWr_idx >= 3'd6)) &&
                          ((io_nonceWr_data & ~(32'd1 << f_pb)) == 32'd0));

  reg [3:0] f_pbit;   // 파티션별 탐침 비트 — (워드 f_pw, 비트 f_pb)
  always @(posedge clk) begin
    if (reset)
      f_pbit <= 4'd0;
    else if (io_nonceWr_valid && (io_nonceWr_idx == f_pw))
      f_pbit[io_nonceWr_part] <= io_nonceWr_data[f_pb];
  end

  wire [3:0] f_vOther = io_maskReady & ~(4'd1 << io_rekey_part);
  wire       f_pP     = f_pbit[io_rekey_part];
  wire [3:0] f_eqv    = ~(f_pbit ^ {4{f_pP}});          // 탐침 등치 (탐침 환경에서 = 논스 등치)
  wire [3:0] f_dupQ   = f_vOther & f_eqv;
  wire       f_mayDup = f_fire && (f_vOther != 4'd0) && (!f_rm || (f_dupQ != 4'd0));
  // 세움 사건이 래치해야 할 비트맵의 *구조* — [15:12] 0 · 유효한 다른 파티션의 부분집합 ·
  // 비0 (bit p 는 f_vOther 에 없으므로 늘 0). 탐침 환경에서는 그 값이 정확히 f_dupQ 다.
  // [11]
  wire f_nmEv = io_en && io_req_valid && !io_maskReady[io_req_part];

  // complete_ignores_dup — busy 연속 사이클 계수 (포화). 상계 F_BUSY_BOUND 는 정본이
  // 거는 상수가 아니다 — 「완료가 [12] 와 무관하게 온다」를 안전 속성으로 적기 위한 유계
  // 근사이고, 오늘 생성물의 창(수락 뒤 42 엣지 — engine.sby 「깊이 근거」)보다 넉넉히 크다.
  // [12] 를 기다리는 완료는 스텝 ~93 에서야 상계를 넘으므로 bmc(깊이 50)가 아니라 prove
  // (abc pdr — 무계)가 그 반례를 낸다. 창을 늘리는 정당한 RTL 변경이면 이 상수를 함께 옮긴다.
  localparam [6:0] F_BUSY_BOUND = 7'd48;
  reg [6:0] f_bcnt;
  always @(posedge clk) begin
    if (reset)                        f_bcnt <= 7'd0;
    else if (!io_busy)                f_bcnt <= 7'd0;
    else if (f_bcnt != 7'd127)        f_bcnt <= f_bcnt + 7'd1;
  end

  // complete_ignores_dup — 창 길이의 *관계* (W1 검증 결함 수리). 상계 하나로는 「[12] 가 설 때만
  // 완료를 몇 사이클 늦추는」 결함(정본 「완료는 [12] 와 무관하게 온다」 위반이자 타이밍 부채널)이
  // 상계 48 안에 숨는다 — 검증 단계 독립 변이 RV4(CROUND 를 [12] = 1 일 때 한 사이클 붙듦)가
  // 단언 28 을 전부 통과했다. 그래서 첫 완료 창의 길이 f_len0 를 잡아 두고 뒤의 완료 창마다 같은
  // 길이를 요구한다. **첫 창은 구조상 [12] = 0 인 창이다** — reset 뒤 마스크가 유효한 파티션이
  // 없어 첫 수락은 세움 사건일 수 없고, 창 안에서는 busy 라 다른 수락이 없다. 그러니 f_len0 은
  // 늘 「[12] = 0 창」의 길이이고, [12] 가 선 채 끝나는 창(증인 W21)이 그것과 같아야 한다 — 두
  // 궤적의 비교(2-안전성)를 한 궤적 안의 두 창으로 접은 것이다. 이 관계는 「창 길이가 상수」라는
  // 오늘 RTL 사실(엔진 단계 수가 고정 — 입력에 따른 정지가 없다)보다 넓지 않다: 정당한 RTL 이
  // 창 길이를 다른 것(예: 파티션 번호)에 기대게 바꾸면 여기서 크게 운다 — 그때 이 관계를
  // 「[12] 만 다른 두 창」으로 좁혀 다시 적는다. 길이 값 자체(42)는 재지 않는다 (cocotb
  // REKEY_TO_READY 등식 몫). 반례는 둘째 완료(스텝 ~88)부터라 bmc(깊이 50)가 아니라 prove
  // (abc pdr — 무계)가 낸다.
  reg [6:0] f_len0;
  reg       f_len0_v;
  always @(posedge clk) begin
    if (reset) begin
      f_len0   <= 7'd0;
      f_len0_v <= 1'b0;
    end else if (!io_busy && (f_bcnt != 7'd0) && !f_len0_v) begin
      f_len0   <= f_bcnt;
      f_len0_v <= 1'b1;
    end
  end

  // ═══ 단언 ═════════════════════════════════════════════════════════════
  always @(posedge clk) if (f_ok) begin
    // ── 완료 엣지 — 직전 사이클이 FINAL 이었다 ──
    if ($past(io_busy) && !io_busy) begin
      // dirty_loud — **모서리**: FINAL 사이클 자체의 활성 파티션 기입도
      // sticky 를 세운다. 파도 D 이전 판(레지스터만 실음)은 여기서 반례.
      if ($past(wrAct))
        a_final_overlap_loud: assert (io_faultWrDuringRekey);
      // invalidate_beats_validate — 그 기입은 유효화를 이긴다.
      if ($past(wrAct))
        a_final_overlap_no_validate: assert (!io_maskReady[f_act]);
      // dirty_loud — 레지스터 경로: 직전 사이클까지의 오염도 loud.
      if ($past(f_dirty))
        a_dirty_final_loud: assert (io_faultWrDuringRekey);
      // dirty_no_validate — 오염 완료는 유효화하지 않는다.
      if ($past(f_dirty))
        a_dirty_final_no_validate: assert (!io_maskReady[f_act]);
      // 깨끗한 완료는 유효화한다 — 「아무것도 유효화하지 않는」 기계와 파티션
      // 무관 오염(dirty_scoped 삭제)을 함께 막는 양성면.
      if (!$past(f_dirty) && !$past(wrAct))
        a_clean_final_validates: assert (io_maskReady[f_act]);
      // 깨끗한 완료는 sticky 를 세우지 않는다 — 등식: 그 엣지의 sticky 는
      // 해제 규약(선 채 ∧ ¬해제)만으로 결정된다.
      if (!$past(f_dirty) && !$past(wrAct))
        a_clean_final_quiet: assert (io_faultWrDuringRekey ==
                                     ($past(io_faultWrDuringRekey) && !$past(io_faultClearWrRekey)));
      // dirty_scoped 직접형 — busy 중 타 파티션 기입이 실재했던 창의 완료는
      // 유효화하고 sticky 를 세우지 않는다 (E.9 4항 「사정권 밖」).
      if ($past(f_otherSeen) && !$past(f_dirty) && !$past(wrAct))
        a_dirty_scoped: assert (io_maskReady[f_act] &&
                                !(io_faultWrDuringRekey && !$past(io_faultWrDuringRekey)));
    end
    // ── sticky 규약 ──
    // 해제 없이 내려가지 않는다.
    if ($past(io_faultWrDuringRekey) && !$past(io_faultClearWrRekey))
      a_fault_sticky: assert (io_faultWrDuringRekey);
    // 상승 원천은 완료 엣지뿐 — busy 중 기입 자체가 sticky 를 세우지 않는다.
    if (io_faultWrDuringRekey && !$past(io_faultWrDuringRekey))
      a_fault_rise_at_final_only: assert ($past(io_busy) && !io_busy);
    // ── 수락·busy 중 유효 (모델 Inv_BusyTargetInvalid — 앵커 없음) ──
    // 수락은 옛 마스크를 즉시 무효화한다. f_act 는 이 엣지에 막 래치됐다.
    if ($past(f_fire))
      a_accept_invalidates: assert (!io_maskReady[f_act]);
    // busy 중 활성 파티션은 유효로 보이지 않는다 — 「재계산 중」인 파티션이
    // 유효로 보이는 창은 없다.
    if (io_busy)
      a_busy_target_invalid: assert (!io_maskReady[f_act]);

    // ── W1 · [12] 발화 — Mask.dup_on_started_rekey ──
    // 세움 사건이면 다음 엣지에 [12] — 같은 사이클 해제가 있어도 (세움이 이긴다). 탐침
    // 환경에서만 판정이 정확하다.
    if ($past(f_rm && f_mayDup))
      n_dup_fire: assert (io_faultNonceDup);
    // 상승 원천은 세움 사건뿐 — busy 미수락 발화(ready 0)도, 유효한 다른 파티션이 없는 수락도,
    // (탐침 환경에서) 같은 논스의 유효한 다른 파티션이 없는 수락도 [12] 를 세우지 않는다.
    if (io_faultNonceDup && !$past(io_faultNonceDup))
      n_dup_rise_src: assert ($past(f_mayDup));
    // 해제 없이 내려가지 않는다.
    if ($past(io_faultNonceDup) && !$past(io_faultClearNonceDup))
      n_dup_hold: assert (io_faultNonceDup);
    // 세움이 불가능한 사이클의 해제는 내린다 (W1C — 해제가 실제로 일한다).
    if ($past(io_faultNonceDup && io_faultClearNonceDup && !f_mayDup))
      n_dup_clear: assert (!io_faultNonceDup);

    // ── W1 · 캡처 워드 0xEC4 ──
    // Mask.cap_first_event — [16] = 1 ∧ ¬해제인 사이클을 건너 필드 불변 (새 발화가 와도
    // 덮지 않는다). [16] 의 불변은 n_dup_hold 가 든다.
    if ($past(io_faultNonceDup) && !$past(io_faultClearNonceDup))
      c_first: assert (dupCapture[15:0] == $past(dupCapture[15:0]));
    // Mask.cap_bitmap_exact — [16] = 0 에서 시작된 재키잉이 [12] 를 세운 사건(래치 사건)의 다음
    // 엣지 워드: [31:16] = {0, 1} · [7:0] = p · [15:12] = 0 · [11:8] 은 *유효한 다른* 파티션의
    // 부분집합(bit p 는 늘 0)이고 비0. 논스 항과 무관한 절반이라 자유 환경에서도 선다.
    if ($past(f_fire && !io_faultNonceDup) && io_faultNonceDup)
      c_latch: assert ((dupCapture[31:16] == 16'h0001) && (dupCapture[7:0] == {6'd0, $past(io_rekey_part)}) &&
                       (dupCapture[15:12] == 4'd0) && ((dupCapture[11:8] & ~$past(f_vOther)) == 4'd0) &&
                       (dupCapture[11:8] != 4'd0));
    // Mask.cap_bitmap_domain — 같은 래치 사건의 비트맵 = [12] 판정의 정의역 그 자체 (유효 ∧
    // 논스 등치의 q 별 항). 탐침 환경에서 정확 등식이다.
    if ($past(f_rm && f_fire && !io_faultNonceDup) && io_faultNonceDup)
      c_latch_dom: assert (dupCapture[11:8] == $past(f_dupQ));
    // Mask.cap_set_beats_clear — [16] = 1 인 채 해제와 시작된 재키잉이 같은 사이클이면 다음
    // 엣지는 둘 중 하나다: 세움 사건이 아니었으면 해제(워드 0), 세움 사건이었으면 *새* 사건의
    // 워드 — p 와 비트맵 전부 (탐침 환경에서는 비트맵 = f_dupQ 의 정확 등식). [16] · p 만 보면
    // 같은 p 의 낡은 비트맵 변이를 놓친다.
    if ($past(f_fire && io_faultNonceDup && io_faultClearNonceDup))
      c_set_wins: assert ((!io_faultNonceDup && (dupCapture == 32'd0)) ||
                          (io_faultNonceDup && (dupCapture[31:16] == 16'h0001) &&
                           (dupCapture[7:0] == {6'd0, $past(io_rekey_part)}) && (dupCapture[15:12] == 4'd0) &&
                           ((dupCapture[11:8] & ~$past(f_vOther)) == 4'd0) && (dupCapture[11:8] != 4'd0) &&
                           (!f_rm || (dupCapture[11:8] == $past(f_dupQ)))));
    // ── W1 · 진행 — Mask.start_ignores_dup · Mask.complete_ignores_dup ──
    // 시작된 재키잉은 다음 엣지에 busy — [12] 를 세운 사건이어도.
    if ($past(f_fire))
      e_start_busy: assert (io_busy);
    // busy 창은 상계 안에 끝난다 — [12] 가 선 채로도 (완료가 [12] 를 기다리지 않는다).
    e_busy_bounded: assert (!(io_busy && (f_bcnt >= F_BUSY_BOUND)));
    // 완료된 창의 길이는 첫 창([12] = 0 인 창)의 길이와 같다 — [12] 에 기댄 유계 지연이 없다.
    // 완료 사이클의 f_bcnt 가 그 창의 busy 사이클 수다 (아직 0 으로 돌아가기 전).
    if (f_len0_v && $past(io_busy) && !io_busy)
      e_busy_len_same: assert (f_bcnt == f_len0);

    // ── W1 · [11] 발화 (앵커 없음) ──
    if ($past(f_nmEv))
      n_nomask_fire: assert (io_faultNoMask);
    if (io_faultNoMask && !$past(io_faultNoMask))
      n_nomask_rise_src: assert ($past(f_nmEv));
    if ($past(io_faultNoMask) && !$past(io_faultClearNoMask))
      n_nomask_hold: assert (io_faultNoMask);
  end

  // ── W1 · 조합 단언 (reset 밖 상시) ──
  always @(*) if (f_ok) begin
    // Mask.cap_clear_whole — [12] = 0 이면 워드 전체 0 (해제가 p · 비트맵까지 지운다 ·
    // 거절 · busy 발화는 필드를 세우지 않는다).
    c_clr_zero: assert (io_faultNonceDup || (dupCapture == 32'd0));
    // 구조 sanity (앵커 없음) — [16] 은 [12] 레지스터 그 자체 (W1-4).
    c_iff: assert (dupCapture[16] == io_faultNonceDup);
    // [31:17] RO 예약 = 0 상시.
    c_rsv: assert (dupCapture[31:17] == 15'd0);
    // Mask.start_ignores_dup (ready 절반) — 유휴면 수락 가능: 수락 판정에 논스 재사용
    // 항이 없다. busy ⇒ ¬ready 쪽은 hiumask.sby 의 rekey_idle_only 가 든다.
    e_idle_ready: assert (io_busy || io_rekey_ready);
  end

  // ── 도달성 증인 (cover 태스크 전용 — 단언의 공허 방지) ──────────────
  //
  // 각 줄의 `←` 오른쪽이 **그 증인이 살리는 대상**이다: `<Model>.<guard>` 는
  // 이 태스크의 `# PROVES:` 앵커, 소문자 식별자는 이 하네스의 단언 라벨.
  // 줄번호로 매지 않는다. scripts/lint_witness_map.py 가 이 선언의 **참조
  // 실재성**을 재고, 뜻은 재지 못한다. 완료 엣지에 닿으려면 수락 뒤 43 엣지가
  // 필요하다 — cover 깊이 근거는 engine.sby 머리.

  // W1 ← MaskEngine.dirty_loud · MaskEngine.invalidate_beats_validate
  //      완료 직전 사이클(FINAL)에 활성 파티션 기입이 실렸다 — 겹침이 실재한다.
  //      없으면 a_final_overlap_loud · a_final_overlap_no_validate 의 전건이
  //      한 번도 서지 않은 채 통과한다 (선-formal Witness_NoOverlap 과 같은 자리).
  // W2 ← MaskEngine.dirty_no_validate
  //      직전 사이클까지의 오염이 있는 완료 — FINAL 사이클 자체에는 기입이
  //      없다 (W1 과 갈라 둔다: 같은 사이클 항이 아니라 누적 항이 결과를 버린
  //      궤적). a_dirty_final_* 의 전건 도달.
  // W3 ← MaskEngine.dirty_scoped
  //      busy 중 활성 아닌 파티션 기입만 있었던 창의 완료가 유효화한다 —
  //      a_dirty_scoped 의 전건 도달 (선-formal Witness_NoOtherWriteBusy).
  // W4 ← a_clean_final_validates
  //      깨끗한 완료가 활성 파티션 비트를 실제로 0→1 로 올린다 — 「아무것도
  //      유효화하지 않는」 기계에서 무효화 류 단언 전부가 공허해지는 것을 막는다
  //      (선-formal Witness_NoCleanComplete).
  // W5 ← a_fault_sticky
  //      선 sticky 가 해제로 실제로 내려간다 — a_fault_sticky 만으로는 「영영
  //      안 내려가는」 구현이 통과한다.
  // W6 ← a_dirty_final_loud
  //      오염 완료와 해제가 같은 사이클 — 발화가 이긴다 (StickyFault 규약 승계,
  //      CapWord.set_beats_clear 와 같은 결). a_dirty_final_loud 의 전건이
  //      해제를 배제하지 않았음이 이 궤적에서 실제로 시험된다.
  // W7 ← a_accept_invalidates
  //      유효했던 파티션의 재키잉 수락이 그 비트를 1→0 으로 실제로 떨어뜨린다
  //      — 두 번째 재키잉이 깊이 안에 있다는 것도 함께 든다.
  // W8 ← a_dirty_final_loud · MaskEngine.dirty_no_validate
  //      수락 사이클 자체의 같은-파티션 기입(f_dirty 갈래 (i))이 오염을 세워
  //      완료가 loud 이고 무효다 — 그 갈래를 뺀 하네스는 a_clean_final_validates
  //      에서 반례가 나므로, 이 증인은 갈래가 실물로 도달함을 든다.
  // W9 ← MaskEngine.dirty_loud
  //      FINAL 사이클의 겹침이 **논스** 워드 기입(idx < 6)이다 — 키 기입 없이.
  //      키·논스 두 when 이 동형이라는 것이 한쪽만으로 시험되지 않게 한다.
  // W10 ← a_clean_final_validates
  //      FINAL 사이클에 활성 파티션의 논스 **예약 오프셋**(idx 6·7) 기입이
  //      있었는데 완료가 깨끗하게 유효화한다 — 하네스 리터럴 idx < 6 의 경계가
  //      DUT 의 무시 정책과 같은 자리에 있음을 도달로 든다.
  always @(posedge clk) if (f_ok) begin
    w1_final_overlap_write: cover ($past(io_busy) && !io_busy && $past(wrAct));
    w2_dirty_final: cover ($past(io_busy) && !io_busy && $past(f_dirty) && !$past(wrAct));
    w3_other_write_busy_then_clean_final: cover ($past(io_busy) && !io_busy && $past(f_otherSeen)
                                                 && !$past(f_dirty) && !$past(wrAct) && io_maskReady[f_act]);
    w4_clean_final: cover ($past(io_busy) && !io_busy && !$past(f_dirty) && !$past(wrAct)
                           && io_maskReady[f_act] && !$past(io_maskReady[f_act]));
    w5_fault_clear: cover ($past(io_faultWrDuringRekey) && $past(io_faultClearWrRekey) && !io_faultWrDuringRekey);
    w6_dirty_final_with_clear: cover ($past(io_busy) && !io_busy && $past(f_dirty)
                                      && $past(io_faultClearWrRekey) && io_faultWrDuringRekey);
    w7_accept_drops_ready: cover ($past(f_fire) && $past(io_maskReady[io_rekey_part]) && !io_maskReady[f_act]);
    w8_accept_write_dirty_final: cover ($past(io_busy) && !io_busy && $past(f_acceptWr) && !$past(wrAct)
                                        && !io_maskReady[f_act] && io_faultWrDuringRekey);
    w9_final_overlap_nonce_only: cover ($past(io_busy) && !io_busy && $past(wrAct)
                                        && !$past(io_keyWr_valid) && $past(f_nonceHit));
    w10_final_reserved_nonce_is_clean: cover ($past(io_busy) && !io_busy
                                              && $past(io_nonceWr_valid && (io_nonceWr_idx >= 3'd6)
                                                       && (io_nonceWr_part == f_act))
                                              && !$past(f_dirty) && !$past(wrAct) && io_maskReady[f_act]);
  end

  // ── W1 증인 — [11]/[12] 발화 · 0xEC4 캡처 · 진행 ─────────────────────
  //
  // 깊이: 첫 세움 사건은 q 의 재키잉 완료(수락 스텝 1 → maskReady[q] 스텝 44) 뒤 p 의
  // 수락(스텝 44 — 섀도우와 DUT 논스가 reset 값 0 으로 같다)에서 서고 [12] 는 스텝 45
  // 에 보인다. *둘째* 사건 · 해제와 겹친 사건 · 자기 유효 · 다중 비트 · [12] 가 선 채의
  // 완료는 엔진이 다시 유휴가 되는 스텝 87 의 수락이 필요해 스텝 88 안팎이다 —
  // engine.sby 의 bmc · cover 깊이 96 근거 (W1).
  //
  // W25 ← n_dup_fire
  //       탐침 환경의 세움 사건이 [12] 를 세운다 — n_dup_fire 의 전건이 탐침 환경에서 도달한다.
  // W11 ← Mask.dup_on_started_rekey · Mask.cap_bitmap_exact · n_dup_rise_src · c_latch
  //       [16] = 0 에서의 세움 사건이 [12] 를 0→1 로 세우고 워드가 그 사건을 담는다 —
  //       비트맵 비0 (c_latch 전건 도달 · 비트맵이 0 인 「아무것도 래치하지 않는」 구현이
  //       등식을 통과하지 않게 한다).
  // W12 ← Mask.dup_on_started_rekey · n_dup_rise_src
  //       busy 중 재키잉 시도(ready 0)의 시점에 판정 정의역이 비0 인데 [12] 가 서지 않는다
  //       — 「재키잉이 *시작된* 발화에서만」의 미수락 갈래가 실재한다 (선-formal
  //       Witness_NoBusyDupAttempt).
  // W13 ← Mask.cap_first_event · c_first
  //       [16] = 1 · 해제 없음 · 둘째 세움 사건 — 캡처가 첫 사건 그대로다 (선-formal
  //       Witness_NoSecondEvent).
  // W14 ← Mask.cap_set_beats_clear · c_set_wins
  //       [16] = 1 인 채 해제와 세움 사건이 같은 사이클이고 *새 사건의 p 가 옛 p 와 다르다*
  //       — 옛 워드를 남기는 구현이 c_set_wins 에서 반례가 나는 궤적 (Witness_NoClearFireOverlap).
  // W15 ← Mask.cap_clear_whole · c_clr_zero · n_dup_clear
  //       세움 사건 없는 해제가 [12] 를 내리고 그 직전 워드의 필드가 비0 이었다 —
  //       해제가 실제로 p · 비트맵을 지운다 (Witness_NoIoClearHeld).
  // W16 ← Mask.dup_on_started_rekey · c_clr_zero
  //       [12] = 1 인 채 busy 미수락 발화와 해제가 같은 사이클 — 해제만 일어나 워드가 0 이다
  //       (Witness_NoRejectedClearOverlap — 해제선은 그 사이클에도 자유다).
  // W17 ← Mask.cap_bitmap_exact · c_latch
  //       재키잉 대상 p 자신이 유효인 채 세움 사건이 래치된다 — bit p 를 비트맵에 넣는
  //       변이(q ≠ p 항 탈락)가 c_latch 에서 반례가 나는 궤적 (Witness_NoSelfValidDup).
  // W18 ← Mask.cap_bitmap_domain · c_latch · c_latch_dom
  //       비트맵에 비트가 둘 이상 선 래치 (Witness_NoMultiBitmap).
  // W19 ← Mask.cap_bitmap_domain · c_latch · c_latch_dom
  //       (탐침 환경) 래치 사건에서 논스가 같은데 마스크가 유효하지 않은 다른 파티션이 실재하고 비트맵에
  //       들지 않는다 — 비트맵이 유효 항을 무시하는 변이가 깊이 46 안에서 반례가 나는 궤적.
  // W20 ← Mask.cap_bitmap_domain · c_latch_dom
  //       (탐침 환경) 래치 사건에서 마스크가 유효한데 논스가 다른 다른 파티션이 실재하고 비트맵에 들지
  //       않는다 — 비트맵이 논스 항을 무시하는 변이의 궤적.
  // W21 ← Mask.complete_ignores_dup · e_busy_bounded · e_busy_len_same
  //       [12] = 1 인 채 busy 가 끝난다 — 완료가 [12] 를 기다리지 않는 궤적이 실재한다. 그 창은
  //       첫 창일 수 없으므로(첫 창은 구조상 [12] = 0) e_busy_len_same 의 비교가 [12] 가 선 창에서
  //       실제로 일어나는 궤적이기도 하다.
  // W22 ← Mask.start_ignores_dup · e_start_busy · e_idle_ready
  //       [12] 를 세운 시작된 재키잉이 다음 엣지에 busy 다.
  // W23 ← n_nomask_fire · n_nomask_rise_src
  //       미준비 마스크를 요청이 통과해 [11] 이 0→1 로 선다.
  // W24 ← n_nomask_hold · n_dup_hold
  //       선 [11] 과 [12] 가 각자의 해제로 실제로 내려간다 — 「영영 안 내려가는」 구현이
  //       hold 단언을 통과하는 것을 막는 반대면.
  always @(posedge clk) if (f_ok) begin
    w11_dup_latch: cover ($past(f_fire && !io_faultNonceDup) && io_faultNonceDup && (dupCapture[11:8] != 4'd0));
    w12_busy_dup_attempt: cover ($past(f_rm && io_rekey_valid && !io_rekey_ready && (f_dupQ != 4'd0) && !io_faultNonceDup)
                                 && !io_faultNonceDup);
    w13_second_event: cover ($past(f_rm && f_fire && (f_dupQ != 4'd0) && io_faultNonceDup && !io_faultClearNonceDup)
                             && (dupCapture[15:0] == $past(dupCapture[15:0])));
    w14_clear_fire_overlap: cover ($past(f_rm && f_fire && (f_dupQ != 4'd0) && io_faultNonceDup && io_faultClearNonceDup
                                         && (dupCapture[1:0] != io_rekey_part))
                                   && io_faultNonceDup);
    w15_clear_zero: cover ($past(io_faultNonceDup && io_faultClearNonceDup && !f_fire && (dupCapture[15:0] != 16'd0))
                           && !io_faultNonceDup && (dupCapture == 32'd0));
    w16_busy_attempt_clear: cover ($past(io_faultNonceDup && io_rekey_valid && !io_rekey_ready && io_faultClearNonceDup)
                                   && !io_faultNonceDup && (dupCapture == 32'd0));
    w17_self_valid_latch: cover ($past(f_fire && !io_faultNonceDup && io_maskReady[io_rekey_part]) && io_faultNonceDup);
    w18_multi_bitmap: cover ($past(f_fire && !io_faultNonceDup) && io_faultNonceDup && !$onehot0(dupCapture[11:8]));
    w19_invalid_same_nonce: cover ($past(f_rm && f_fire && !io_faultNonceDup &&
                                         ((~io_maskReady & ~(4'd1 << io_rekey_part) & f_eqv) != 4'd0))
                                   && io_faultNonceDup);
    w20_valid_diff_nonce: cover ($past(f_rm && f_fire && !io_faultNonceDup && ((f_vOther & ~f_eqv) != 4'd0))
                                 && io_faultNonceDup);
    w25_probe_dup_fire: cover ($past(f_rm && f_mayDup && !io_faultNonceDup) && io_faultNonceDup);
    w21_complete_with_dup: cover ($past(io_busy && io_faultNonceDup) && !io_busy);
    w22_dup_start_busy: cover ($past(f_fire && !io_faultNonceDup) && io_faultNonceDup && io_busy);
    w23_nomask_rise: cover ($past(f_nmEv && !io_faultNoMask) && io_faultNoMask);
    w24_nomask_clear: cover ($past(io_faultNoMask && io_faultClearNoMask && !f_nmEv) && !io_faultNoMask);
    w24_dup_clear: cover ($past(io_faultNonceDup && io_faultClearNonceDup && !f_mayDup) && !io_faultNonceDup);
  end

endmodule

// 형식 검증 톱 — 대상 + props 결선. 내부 포트 없음 (expose 불필요). 키 기입
// 데이터 · 요청 프레임은 자유 입력으로 두되 검사자에는 잇지 않는다 (이 하네스의
// 정의역 밖 — 파일 머리 「재지 않는 것」). W1 부터 요청 valid/part · enable ·
// 논스 기입 데이터 · [11]/[12] 와 그 해제 · 캡처 워드는 검사자에 잇는다.
module MaskUnit_formal (
    input wire        clk,
    input wire        reset,
    input wire        io_keyWr_valid,
    input wire [1:0]  io_keyWr_part,
    input wire [2:0]  io_keyWr_idx,
    input wire [31:0] io_keyWr_data,
    input wire        io_nonceWr_valid,
    input wire [1:0]  io_nonceWr_part,
    input wire [2:0]  io_nonceWr_idx,
    input wire [31:0] io_nonceWr_data,
    input wire        io_rekey_valid,
    input wire [1:0]  io_rekey_part,
    input wire        io_en,
    input wire        io_req_valid,
    input wire [1:0]  io_req_part,
    input wire [31:0] io_req_frame,
    input wire        io_faultClearNoMask,
    input wire        io_faultClearNonceDup,
    input wire        io_faultClearWrRekey
);
  wire        io_rekey_ready;
  wire [3:0]  io_maskReady;
  wire        io_busy;
  wire        io_rsp_valid;
  wire [31:0] io_rsp_frame;
  wire        io_faultNoMask;
  wire        io_faultNonceDup;
  wire        io_faultWrDuringRekey;
  wire [31:0] dupCapture;
  // W1 — 논스 탐침 칸 (anyconst — 래퍼 소유, CompletionUnit_props.sv 의 f_slot 관례)
  (* anyconst *) wire       f_rm;
  (* anyconst *) wire [2:0] f_ps;

  MaskUnit dut (
    .io_keyWr_valid(io_keyWr_valid), .io_keyWr_part(io_keyWr_part),
    .io_keyWr_idx(io_keyWr_idx), .io_keyWr_data(io_keyWr_data),
    .io_nonceWr_valid(io_nonceWr_valid), .io_nonceWr_part(io_nonceWr_part),
    .io_nonceWr_idx(io_nonceWr_idx), .io_nonceWr_data(io_nonceWr_data),
    .io_rekey_valid(io_rekey_valid), .io_rekey_ready(io_rekey_ready),
    .io_rekey_part(io_rekey_part),
    .io_maskReady(io_maskReady), .io_busy(io_busy),
    .io_en(io_en), .io_req_valid(io_req_valid), .io_req_part(io_req_part),
    .io_req_frame(io_req_frame),
    .io_rsp_valid(io_rsp_valid), .io_rsp_frame(io_rsp_frame),
    .io_faultNoMask(io_faultNoMask), .io_faultNonceDup(io_faultNonceDup),
    .io_faultWrDuringRekey(io_faultWrDuringRekey),
    .io_faultClearNoMask(io_faultClearNoMask),
    .io_faultClearNonceDup(io_faultClearNonceDup),
    .io_faultClearWrRekey(io_faultClearWrRekey),
    .dupCapture(dupCapture),
    .clk(clk), .reset(reset)
  );

  MaskEngine_props u_MaskEngine_props (
    .clk(clk), .reset(reset),
    .io_keyWr_valid(io_keyWr_valid), .io_keyWr_part(io_keyWr_part),
    .io_nonceWr_valid(io_nonceWr_valid), .io_nonceWr_part(io_nonceWr_part),
    .io_nonceWr_idx(io_nonceWr_idx),
    .io_rekey_valid(io_rekey_valid), .io_rekey_ready(io_rekey_ready),
    .io_rekey_part(io_rekey_part),
    .io_maskReady(io_maskReady), .io_busy(io_busy),
    .io_faultWrDuringRekey(io_faultWrDuringRekey),
    .io_faultClearWrRekey(io_faultClearWrRekey),
    .io_nonceWr_data(io_nonceWr_data),
    .io_en(io_en), .io_req_valid(io_req_valid), .io_req_part(io_req_part),
    .io_faultNoMask(io_faultNoMask), .io_faultClearNoMask(io_faultClearNoMask),
    .io_faultNonceDup(io_faultNonceDup), .io_faultClearNonceDup(io_faultClearNonceDup),
    .dupCapture(dupCapture),
    .f_rm(f_rm), .f_ps(f_ps)
  );
endmodule

`default_nettype wire
