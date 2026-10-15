\* SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
\* SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
---------------------------- MODULE ActivePart ----------------------------
\* `0xE14` XLATE_ACTIVE_PART — 결속 파티션 워드와 그 수락 판정 (A, D) 의 선-formal 모델.
\* 3.10 v1.0 묶음 RTL 파도 W4 (2026-10-15) 신설 (DP-6 — XlateSurface 대형을 부풀리지 않고
\* 잴 수 있는 경계 하나: AbortSurface · CapWord 선례).
\*
\* ## 분업
\*
\*   XlateSurface.tla  `0xC00` 문 · `0xE00` flush · `0xE10` 해제 — 결속은 거기 상태가 아니다.
\*   MmioPage.tla      페이지 처분의 *부류* — `0xE14` 는 부류 rw 이고, 그 기입의 의미(값 검사 ·
\*                     드레인 판정 · `[9:8]` 쓰기 무시)와 판정 사이클의 정지는 이 모델이다.
\*   Isolation.tla     조회 · 채움의 비간섭 — 요청이 *어느* 파티션으로 오는가는 거기 입력이다.
\*   ActivePart.tla    그 입력의 원천 — 요청의 파티션 = 접수 시점의 결속, 결속은 드레인 경계에서만
\*                     바뀌고, 모든 버스 수락 기입이 (A, D) 를 정본 술어대로 남긴다.
\*
\* ## 정본 (좌표 뒤 「」 는 그 줄의 축자 — lint_section_refs 축 1 이 대조한다)
\*
\*   워드 — E.1.2 `0xE14` 행
\*   e-defined.typ:329 「`[8]` APPLIED (A — 마지막 기입이 적용됐는가)」
\*   e-defined.typ:329 「`[9]` DRAINED (D — 마지막 기입 수락 에지의 드레인 판정)」
\*   e-defined.typ:329 「`[9:8]` *쓰기 무시* (RW 워드 안의 RO 필드」
\*   e-defined.typ:329 「`[31:10]` 예약 = 0 (엄격)」
\*   e-defined.typ:329 「reset 값은 `[7:0]` = 0 · `[9:8]` = 0 이고」
\*   e-defined.typ:329 「A · D 는 reset 뒤 *첫 기입부터* 뜻을 갖는다」
\*   수락 판정 — E.1.2 「결속 파티션의 수락 판정」
\*   e-defined.typ:332 「*값 검사가 먼저다.*」
\*   e-defined.typ:332 「`[31:10]` 비0 은 거절 + `[6]` · 결속 불변이다」
\*   e-defined.typ:332 「D 는 값 검사와 무관하게 늘 *그 기입 수락 에지 직후의 상태*(같은 사이클의 요청 접수 포함)에 대해 표집한다」
\*   e-defined.typ:332 「v1.0 의 D 는 `0x37C` DRAIN_ALLZERO 다」
\*   e-defined.typ:332 「버스 수락된 `0xE14` 기입은 어느 것이든 A · D 를 갱신한다」
\*   e-defined.typ:332 「어떤 사유든(값 검사 · 드레인 판정) 거절이면 A = 0 이다」
\*   e-defined.typ:332 「그래서 A = 0 ∧ D = 1 은 값 거절과 같은 뜻이다」
\*   e-defined.typ:332 「이 아니므로 A · D 도 결속도 움직이지 않는다」 — 비정렬 `0xE15`–`0xE17` (명확화 2026-10-11).
\*   e-defined.typ:332 「A = 0 · 거절 + `[6]` · 결속 불변」 — 다른 값 ∧ D = 0.
\*   e-defined.typ:332 「A = 1 · 무동작 · *fault 없음* — D = 0 이 보고된다」 — 같은 값 ∧ D = 0.
\*   e-defined.typ:332 「v1.0 의 이 워드는 내부 포트 결속을 MMIO 로 바꾸는 표면이고」
\*   일반 규범 · reset · 없는 값 · `[6]` 폴딩
\*   e-defined.typ:208 「*일반 규범 — RW 워드 안의 RO 필드는 쓰기 무시다.*」
\*   e-defined.typ:208 「RO 필드를 엄격 예약으로 두면 규범을 지킨 드라이버가 거절을 받는다」
\*   e-defined.typ:208 「`0xE14` 의 드레인 판정 거절은 내용이 아니라 시점의 거절이라 여기 들지 않는다」
\*   e-defined.typ:216 「`0xE14` XLATE_ACTIVE_PART = 0.」
\*   e-defined.typ:414 「실재하지 않는 파티션 값의 기입은 *수락되지 않고 거절 + loud fault* 다」
\*   e-defined.typ:557 「*시점 위반*이라 고칠 동작이 다르다」
\*   3.7.2 「결속 전환」
\*   03-hiu.typ:1198 「(`0xE14`)의 드레인 위반은 장치가 그 기입을 거절하고 크게 알린다」
\*   03-hiu.typ:1271 「값 검사가 먼저이고, 현재와 다른 값은 D = 1 일」
\*   03-hiu.typ:1272 「같은 값은 fault 없이 무동작이다」
\*   03-hiu.typ:1275 「시점은 그 기입의 수락 에지 직후 상태이고 *같은 사이클의 요청 접수를」
\*   03-hiu.typ:1276 「접수와 결속 교체가 겹치는 경합을 닫는다」
\*   03-hiu.typ:1292 「*드레인 경계에서만 바뀌는 구성 상태*이고」
\*   03-hiu.typ:1297 「같은 값 기입은 결속을 바꾸지 않는다. 드레인되지 않은 상태에서 그것을」
\*   03-hiu.typ:1316 「결속을 MMIO 로 바꾸는 표면이고, *결속 전환이 격리를 준다는 주장은 명령 링」
\*
\* ## 모델
\*
\*   한 스텝 = 한 클록 에지. 입력 셋이 같은 에지에 겹칠 수 있다 — MMIO 접근 하나(버스는 한 번에
\*   하나) · 요청 하나의 접수 · 진행 중인 일 하나의 빠져나감. 이 겹침이 정본 술어 「수락 에지
\*   *직후*의 상태(같은 사이클의 요청 접수 포함)」의 정의역이다.
\*   · jobs[p] — 꼬리표 p(접수 시점의 결속)로 받아들인 진행 중인 일. 꼬리표는 유령이고 장치는
\*     Busy(= ¬DRAIN_ALLZERO) 하나만 본다 — v1.0 의 D 는 장치 전역 `0x37C` 다.
\*   · bound · regA · regD — 장치 레지스터 `[7:0]` · `[8]` · `[9]`. reset 0.
\*   · pend — α 의 actPend: t 에 수락된 기입이 t+1 판정을 기다린다(v · 값 검사 결과 · 유령 셋).
\*   · gB · gA · gD · gRej — 정본 유령: 정렬 `0xE14` 기입을 *수락 에지에 원자적으로* 판정한
\*     레지스터. 가드는 이것을 읽지 않고 속성만 읽는다(XlateSurface 의 cs 와 같은 자리).
\*   · 보조(한 스텝): wacc · uacc · rd · vrej · res · lV · lR · lU · rq · rqP · stR · stM · hold.
\*
\* ## 설계 결정 — D 표집 꼴 (DP-4 · W4-2) — 이 모델이 그 근거 문서다
\*
\*   DSample = "alpha"  (좋은 모델) t 에 수락된 기입을 pend 로 잡고 t+1 에 D := DRAIN_ALLZERO 를
\*                      읽어 판정해 t+1 에지에 적용한다. t+1 의 DRAIN_ALLZERO 가 곧 「t 에지 직후의
\*                      상태」다 — t 에 접수된 요청은 파이프 단 하나를 차지하고(같은 사이클 접수
\*                      포함), t 에지에 빠져나간 일은 이미 없다. t+1 동안 요청 접수와 MMIO 를
\*                      막는다(pend_stalls_req · pend_stalls_mmio) — 판정 뒤 · 적용 전에 옛 결속으로
\*                      받는 일과 판정 전의 되읽기를 닫는다. 값 검사 거절의 `[6]` 은 t 에 바로 낸다.
\*   DSample = "beta"   (대안) D = ALLZERO(t) ∧ ¬접수(t) 를 t 에 판정해 t 에지에 적용 — 합의 메모의
\*                      구현 예시 꼴이다. 같은 사이클 접수는 센다. 어긋나는 궤적은 하나다 — **마지막
\*                      일이 그 기입과 같은 에지에 빠져나가는 모서리**: 요청 접수(일 1) → 다음 사이클에
\*                      다른 값 기입 ∧ 그 일이 같은 에지에 퇴장. 정본 D = 1(에지 직후 일 0) 인데 β 는
\*                      D = 0 → 적법한 결속 전환이 거절 + `[6]`(거짓 loud). 실측 반례는 run.sh 이 절
\*                      머리 — _alt_beta(Prop_DIsPostEdge) · _alt_beta_loud(Prop_LoudOnlySpec), 둘 다
\*                      상태 3 개. 그런데 β 는 격리 몸(Inv_WorkUnderBound · Prop_NoStaleWorkAfterSwitch ·
\*                      Prop_SwitchOnlyDrained · Prop_NoAcceptAcrossSwitch · Prop_ReqPartIsBound)을
\*                      지킨다(_alt_beta_iso 통과) — 결함은 「보수적 격리」가 아니라 *정본과 다른 관측*
\*                      이다. 그리고 그 모서리의 전환을 β 는 영영 하지 못한다(_alt_beta_edge 통과 ·
\*                      α 에서는 증인 NoEdgeLeaveSwitch 가 반증된다). 그래서 α 다 — 대가는 `0xE14`
\*                      기입마다 1 사이클 정지이고 정본은 응답 시간을 규범으로 걸지 않는다.
\*                      RTL 에서 이 모서리에 닿는 길: 모델의 퇴장 L 은 제약이 없지만, RTL 에서 기입과
\*                      같은 에지에 마지막 일이 정의역을 떠나는 길은 MMIO 를 거치지 않는 퇴장뿐이다 —
\*                      **HIU s6 → io.hiuRsp.fire**(응답 퇴장). CQ_OCC 쪽 퇴장은 CQ_HEAD MMIO 기입이라
\*                      `0xE14` 기입과 같은 에지에 올 수 없다(버스는 한 번에 하나). DP-4 의 「어긋나는
\*                      궤적은 하나」 는 그 응답 퇴장 경로의 모서리다 (W5 의 Y4 통지가 인용할 문장).
\*   DSample = "lag"    (대안) α 인데 D 의 원천이 t 에 접수된 요청을 t+1 에 아직 세지 않는다(점유
\*                      카운트 지연). α 의 정확성은 「t 접수 ⇒ t+1 DRAIN_ALLZERO 에 든다」 라는 RTL
\*                      사실에 기댄다 — 이 대안이 그 의존을 기록한다: 옛 결속으로 받은 일이 교체를
\*                      건넌다(_alt_lag → Inv_WorkUnderBound, 상태 3 개 — 격리 결함). 몫: 닫힌 목록 3.
\*   StallAlt = "hold"  (대안) 정지를 한 사이클 더 늘인 꼴(t+1 · t+2). 정본 위반은 아니지만(응답 시간
\*                      무규범) 위 「1 사이클」 과 RTL 의 `stall := actPend` 를 앵커한다
\*                      (_alt_stall_hold → Prop_StallOnlyPend).
\*
\* ## 가드 — 각각 정본 한 문장. 삭제 run 은 자기 속성이 첫 위반으로 난다.
\*
\*   지도의 여덟(W4-1)에 넷을 더했다 — 근거: reject_loud 는 :1198 · E:557 의 「크게 알린다」
\*   (XlateSurface · MmioPage 의 같은 이름 선례 — 거절의 판정과 그 발화를 따로 잰다),
\*   pend_stalls_req · pend_stalls_mmio 는 α 의 두 정지 포트(W4-5 stallReq · stallMmio)가 각각
\*   다른 결함을 막아서(접수 경합 · 판정 전 되읽기), unaligned_outside 는 E:332 명확화(2026-10-11)
\*   · W4-4 — 「`0xE14` 기입」의 정의역 경계가 RTL 의 항 하나(정렬 게이트)라서다.
\*
\*   value_first        :332 1항 · :414 — 없는 파티션 값은 D · 같은 값 여부와 무관하게 거절. 지우면
\*                      값 검사가 같은 값 비교 *뒤*로 가고 절단된 필드가 현재 결속과 같아 무동작
\*                      수락(A = 1)된다. → Prop_ValueFirst
\*                      (주의: 이 가드의 앵커는 *절단 사례*다 — 검사의 *순서* 그 자체가 아니다. 검증
\*                      변이 V7 「드레인 검사 먼저」 는 Prop_RejectLoud 하나로만 잡힌다 — A · D · 결속은
\*                      정본대로 남고 `[6]` 의 사이클 · 귀속 사유만 다르다(`[6]` 이 sticky 라 호스트
\*                      관측은 같다). RTL · cocotb 는 순서가 아니라 절단 사례를 재라.)
\*   rsv_strict         :329 · :332 1항 — `[31:10]` 비0 은 거절. 지우면 예약을 무시하고 `[7:0]` 로
\*                      판정한다. → Prop_RsvRejected
\*   ro_field_ignored   :329 · :208 일반 규범 — `[9:8]` 쓰기는 무시. 지우면 `[9:8]` 이 예약-엄격으로
\*                      읽혀 RMW 하는 적합 드라이버의 기입이 거절된다(:208 이 이름한 첫 사례).
\*                      → Prop_RoFieldIgnored
\*   drain_gates_switch :332 표 · :1271 — 다른 값은 D = 1 일 때만 결속을 바꾼다. 지우면 D = 0 에서
\*                      결속이 바뀐다. → Prop_SwitchOnlyDrained
\*   same_value_noop    :332 표 · :1272 · :1297 — 같은 값은 D 와 무관하게 A = 1 · fault 없음.
\*                      지우면 같은 값 ∧ D = 0 이 거절 + `[6]`. → Prop_SameValueNoFault
\*                      (짝 _pair_same_reject 와 동형 기계 — 짝은 정본 해설이 기각한 *설계 대안*의
\*                      이름이고 삭제는 RTL 의 같은 값 항이다. 둘 다 남긴다.)
\*   ad_every_accept    :332 3항 — A 는 기입마다 귀속된다: 어떤 거절이든 A = 0. 지우면 A 의 쓰기
\*                      허가가 「적용」 뿐이라 거절 뒤에 앞 기입의 A = 1 이 남는다. → Prop_AdEveryAccept
\*                      (같은 문장의 D 절반 — 값 거절도 D 를 표집한다 — 은 Prop_DIsPostEdge 가 모든
\*                      기입에 대해 잰다: 비상주 변이 M2 「값 거절에 D 미표집」 → Prop_DIsPostEdge.)
\*   d_includes_same_cycle :332 2항 · :1275 — D 는 수락 에지 *직후* 상태. 지우면 기입 사이클(t)의
\*                      에지 *전* DRAIN_ALLZERO 를 잡아 같은 사이클에 접수된 일을 놓친다.
\*                      → Prop_DIsPostEdge
\*   pend_stalls_req    :1276 경합 닫힘 (α 의 정지 하나) — 판정 사이클 t+1 에 요청을 받지 않는다.
\*                      지우면 t+1 에 옛 결속으로 받은 일이 t+1 에지의 결속 교체를 건넌다.
\*                      → Prop_NoAcceptAcrossSwitch
\*   pend_stalls_mmio   :329 「마지막 기입」 (α 의 정지 둘) — 판정 사이클 t+1 에 MMIO 를 받지 않는다.
\*                      지우면 되읽기가 판정 전 레지스터를 본다. → Prop_ReadIsSpec
\*   req_part_from_bound :1292 · :332 머리 — 요청의 파티션은 접수 시점 결속에서 온다(포트가 아니다).
\*                      지우면 요청이 임의 파티션 꼬리표를 단다. → Prop_ReqPartIsBound
\*   unaligned_outside  :332 명확화 — `0xE15`–`0xE17` 쓰기는 이 정의역 밖(페이지 sub-word 거절 +
\*                      `[6]` · A · D · 결속 불변). 지우면 하위 두 비트를 버린 `0xE14` 기입으로
\*                      처리된다. → Prop_UnalignedInert
\*   reject_loud        :1198 · :332 · E:557 — 거절(값 · 드레인)은 전부 `[6]`. 지우면 조용한 거절.
\*                      → Prop_RejectLoud
\*
\* ## 고정 속성 (가드 아님 — 좋은 모델 cfg 가 건다 · 반증력은 짝 · 대안 · 비상주 변이)
\*
\*   Inv_ObsIsSpec            판정이 끝난 상태(pend 없음)의 장치 레지스터 = 정본 유령.
\*                            ← _pair_today_absorb · 대안 β
\*   Inv_WorkUnderBound       진행 중인 일은 전부 지금 결속의 꼬리표다 (격리 몸 — v1.0 은 이 판정에
\*                            기댄 격리를 *주장하지 않는다* :1316 — 그래도 판정 자체는 이것을 낸다).
\*                            ← _alt_lag · _del_pend_stalls_req_iso
\*   Prop_NoStaleWorkAfterSwitch 결속이 바뀌는 에지 뒤에 옛 결속의 일이 남지 않는다.
\*                            ← _del_pend_stalls_req_stale
\*   Prop_LoudOnlySpec        `[6]` 은 정본이 거절하는 기입(과 비정렬)에서만. ← _alt_beta_loud
\*                            드레인 판정의 발화는 *그 기입 자신*의 정본 판정(res.grej)과 대조한다 —
\*                            pend_stalls_mmio 에 기대지 않는다(검증 반례 W27: t+1 둘째 기입 허용 꼴).
\*   Prop_A0D1IsValueReject   A = 0 ∧ D = 1 ⇒ 값 거절 · 드레인된 값 거절 ⇒ A = 0 ∧ D = 1 (:332 3항).
\*                            ← _del_ad_every_accept_a0d1 · 비상주 변이 M1 「D 게이트 반전」
\*   Prop_StallOnlyPend       정지(요청 · MMIO)는 판정 사이클에만 — 정확히 1 사이클이고 풀린다.
\*                            ← _alt_stall_hold (검증 변이 H15b/d/e/f 「사건 뒤 영영 선 · 늘인 정지」)
\*
\* ## 짝 · 대안
\*
\*   _pair_today_absorb  W4 전 RTL(HEAD f67e3d6) — `0xE14` 는 `uResv` 구역의 예약 오프셋이라 쓰기
\*                       흡수 · 읽기 0. → Inv_ObsIsSpec (같은 값 기입 하나 뒤 A 가 0 이다).
\*   _pair_today_port    같은 RTL — 요청 파티션은 최상위 포트 io.hiuReq.part. → Prop_ReqPartIsBound
\*   _pair_same_reject   SameAlt = "reject" — 같은 값 ∧ D = 0 → 거절 + `[6]`. → Prop_SameValueNoFault
\*   _alt_beta · _alt_beta_loud · _alt_beta_iso(통과) · _alt_beta_edge(통과) — 위 「설계 결정」.
\*   _alt_lag (→ Inv_WorkUnderBound) · _alt_stall_hold (→ Prop_StallOnlyPend) — 위 「설계 결정」.
\*
\* ## RTL GUARD-MAP 예정 문면 (W4 RTL 단계 — 가드 하나에 줄 하나)
\*
\*   ActivePart.scala (새 컴포넌트 — 포트 wr · wdata · drainNow · activePart · actWord · badWrite ·
\*   stallMmio · stallReq; 상태 bound · aReg · dReg · actPend · pendV · pendOk):
\*   · value_first -> valOk = !XlateStaging.partBad(wdata[7:0], cfg.xlateParts) ∧ (wdata[31:10] === 0)
\*     — 없는 값 판정은 한 정의(Wt64Top partBad 주석 「파티션을 받는 표면 셋」 → 넷: 이 표면이 넷째).
\*     pendV 를 8b 보다 좁게 저장하면 절단 별칭(모델의 Alias)이 생기고 그것을 막는 것이 pendOk 다
\*     (¬valOk 이면 t 에 badWrite · 적용 가지 없음 — pendSame 은 valOk 인 기입에서만 뜻을 갖는다).
\*   · rsv_strict -> valOk 의 wdata[31:10] === 0 항.
\*   · ro_field_ignored -> valOk · pendSame · pendV · aReg · dReg 어느 식에도 wdata[9:8] 이 없다.
\*   · drain_gates_switch -> applyNow = actPend ∧ pendOk ∧ (pendSame ∨ io.drainNow); bound := pendV 는
\*     applyNow 일 때만.
\*   · same_value_noop -> applyNow 의 pendSame(= pendV === bound) 항 — 같은 값은 D 를 묻지 않는다.
\*   · ad_every_accept -> when(actPend) { aReg := applyNow; dReg := io.drainNow } — 쓰기 허가가
\*     actPend 하나다(적용 여부와 무관). actPend 는 값 검사와 무관하게 수락된 정렬 기입마다 선다.
\*   · d_includes_same_cycle -> dReg 는 actPend 사이클(t+1)의 io.drainNow 를 잡는다 — 기입 사이클의
\*     drainNow 를 래치하지 않는다. io.drainNow 의 원천은 CompletionUnit.drainAllZero(아래).
\*   · pend_stalls_req -> io.stallReq := actPend; Wt64Top 에서 *valid 와 ready 둘 다*:
\*     hiu.io.req.valid := io.hiuReq.valid && !actp.io.stallReq · io.hiuReq.ready := hiu.io.req.ready &&
\*     !actp.io.stallReq. ready 만 내리면 안 된다 — HiuPipeline 은 ready = advance 가 valid 와 무관하고
\*     advance 에 s1.valid := io.req.valid 라 정지 사이클에 요청이 s1 에 실리고 재전송된다(이중 접수).
\*     assembly a_hiu_pass 를 이 꼴로 다시 쓴다.
\*   · pend_stalls_mmio -> io.stallMmio := actPend; 정지는 **R_XCTL 구역(또는 isAct) 범위**로 —
\*     `0xC00` COMMIT 의 ready 덮어쓰기(xlateArea `io.mmio.ready := hiu.installSlotFree`)와 같은 꼴.
\*     페이지 전역으로 io.mmio.ready 를 내리지 마라: mask · fp · abort · fault 구역의 wr 은
\*     io.mmio.wstrobe && sel && aligned 로 ready 항이 없고 own · cq · cfgBlk 는 날 wstrobe 를 받으므로,
\*     전역 정지는 효과를 내면서 버스에는 「미수락」 을 보여 재시도 = 이중 효과다(MmioPage.effect_on_accept
\*     위반). 모델의 MMIO 접근은 전부 `0xE14` 부류(정렬 `0xE14` · 비정렬 `0xE15`–`0xE17`)라 구역 범위
\*     정지로 Prop_ReadIsSpec 이 같게 선다. 상태의 함수라 lint_ready_cone 의 wdata 콘 금지와 맞는다.
\*   · (두 정지 공통) stall := actPend 그 자체 — 늘이거나 래치하지 않는다 (Prop_StallOnlyPend ·
\*     _alt_stall_hold). 후-formal a_ready_* 에 「ready 하강 ⇒ actPend」 를 넘긴다.
\*   · reject_loud -> io.badWrite = (wr ∧ ¬valOk) ∨ (actPend ∧ pendOk ∧ ¬applyNow) → 원천별
\*     sticky io_fault_actCfgBadWrite(Wt64Top 클래스 끝 · W4 D1) → FAULT_STATUS `[6]`.
\*   Wt64Top.scala:
\*   · req_part_from_bound -> hiu.io.req.part := actp.io.activePart — io.hiuReq.part 입력은 은퇴(같은
\*     줄 주석).
\*   · unaligned_outside -> actp.io.wr := (xlateArea 쓰기 스트로브) ∧ isAct ∧ mmioAligned — 비정렬은
\*     pageArea.unalWr(MmioPage.unaligned_rejected)만 받는다.
\*   CompletionUnit.scala (클래스 끝 — 가드 줄 없음, 위 d_includes_same_cycle 의 원천):
\*   · io.drainAllZero := allZero (여섯 카운트 ∧ CQ_OCC = 0 — `0x37C` 읽기와 같은 식). 「핀 = `0x37C`
\*     읽기 = 여섯 입력 전부 0」 은 descriptor.sby 몫.
\*   Wt64Top.scala MmioPage GUARD-MAP (이 변경이 거짓으로 만드는 줄):
\*   · MmioPage.rsp_on_accept · effect_on_accept — ready 하강 원천에 actp.io.stallMmio 를, 조립 구역
\*     목록에 actArea 를 더한다.
\*   · MmioPage.resv_lenient — 「구역 안 미정의 워드」 에서 `0xE14` 를 뺀다(uResv = `0xE18`–`0xE7C`).
\*   · MmioPage.reject_loud — 거절선 목록에 원천별 sticky io_fault_actCfgBadWrite 를 더한다(surfBadWr 합류 아님).
\*
\* ## 닫힌 목록 — 이 모델이 재지 않는 것과 그 몫
\*
\*   1. 주소 디코드 — `0xE14` 의 구역 · 워드 선택 · 정렬 판정 비트. 모델의 접근은 종류를 직접
\*      지목한다. 몫: assembly 구역 분류(uResv 에서 `0xE14` 제외 · isAct 디코드).
\*   2. 값 인코딩 — `[7:0]` 8b · 「실재 파티션 수 이상」 의 비교 폭 · `[31:10]` 의 자리. 모델은
\*      Phantom · rsv · ro 플래그로 사유만 싣는다. 몫: ActivePart 단독 하네스(새 .sby) · assembly
\*      a_bind_upd.
\*   3. D 의 원천 — DRAIN_ALLZERO 가 「옛 결속 아래 받아들인 일이 하나도 없음」 과 같다는 것. 모델은
\*      jobs 하나로 접었다. 두 갈래로 몫이 다르다:
\*      (a) 합의 완전성(여섯 카운트 + CQ_OCC = `0x37C` 읽기 = 핀) — descriptor.sby.
\*      (b) **시점** — t 에 접수된 요청이 t+1 의 occupancy 에 이미 든다(req.fire(t) ⇒ occupancy(t+1) ≥ 1)
\*          · 파이프 → 하류 카운트 인계에 0 틈이 없다. α 가 기대는 사실이고 어기면 격리가 깨진다
\*          (_alt_lag). descriptor.sby 는 CompletionUnit 단독이라 HIU 를 못 보고, assembly 는
\*          hiu = HiuPipeline 을 절단해 occupancy · drainAllZero 가 자유 핀이라 f_D 는 결선만 잰다 —
\*          그래서 몫은 **HiuPipeline 태스크**(hiumask.sby 확장 또는 새 태스크)다. HEAD 의 RTL 은 참이다
\*          (advance 에 s1.valid := io.req.valid · occupancy = s1..s6 popcount)이지만 재는 것이 없다.
\*   4. D 의 v1.0 공허 항 — ⑥ 순서 토큰 축 · 명령 링 미소비 항. 정본이 공허라 정했고 링 소비 회로
\*      착지 판의 일이다(:1278 이후). 모델에 항이 없다.
\*   5. 격리 *주장* — 투입 정지 수단이 없어 v1.0 은 결속 전환에 기댄 격리를 주장하지 않는다
\*      (:1316). 모델의 Inv_WorkUnderBound 는 장치 판정의 성질이지 호스트 절차의 보증이 아니다.
\*      호스트 절차(투입 정지 → 드레인 → 기입 → 되읽기 → 재개)는 모델 밖.
\*   6. 사이클 수 — α 의 정지는 정확히 1 사이클(Prop_StallOnlyPend 가 잰다)이지만 「다른 정지와
\*      겹친 ready 하강의 합」 과 정지의 *구역 범위*(정렬 0xE14 하나 — 다른 구역 기입은 정지
\*      사이클에도 수락되고 효과는 1회, 이중 효과 없음)는 조립의 일이다. 몫: assembly a_ready_* 정지 원천 목록 · MmioPage.effect_on_accept.
\*      RTL 의 정지 구역은 정렬 `0xE14` 하나(isAct = 정렬 ∧ 워드 5)라 비정렬 `0xE15`–`0xE17` 은 판정
\*      사이클에도 정지하지 않는다 — 모델(모든 접근을 `0xE14` 부류로 지목)보다 덜 막지만 그 접근은
\*      무효과다(Prop_UnalignedInert)라 무해하다. 몫: cocotb(판정 사이클 0xE15 ready 1) · assembly.
\*   7. `[6]` 의 sticky · W1C — lV · lR · lU 는 발화 펄스다. 몫: assembly(원천별 sticky 결선 — DP-15, xlateCfgBadWrite 선례) · faultArea.
\*   8. reset 형식 단언 — W4-9 대로 하지 않는다. Init 이 reset 값의 모델이다. 몫: cocotb N15
\*      reset_values_norm.
\*   9. 바이트 인에이블 절반 — 장치 포트에 없다. 비정렬은 하위 두 비트의 처분만 잰다.
\*      **몫 없음 — 정본 경계 밖**(어댑터 이행).
\*  10. 읽기 인코딩 — `[31:10]` 읽기 0 · 비트 자리. 모델의 rd 는 (b, a, d) 셋. 몫: assembly a_bind_rd.
\*  11. io.hiuRsp.part 메아리(DP-10) — 모델에 응답이 없다. 몫: cocotb N11 active_part_binds_lookup.
\*  12. 조회의 파티션 사용 — 꼬리표를 받은 요청이 어느 표를 찾는가. 몫: Isolation.tla · XlateObs.tla ·
\*      hiumask.sby(HiuPipeline req.part 포트는 유지).
\*  13. 접수 용량 — MaxJobs 는 환경 배압 추상(HiuPipeline ready). 정본 술어와 무관하다.
\*      **몫 없음 — 술어 밖**.
\*  14. 드레인 의무의 범위(flush · 키 · 전역 구성의 드레인) — 호스트 의무이고 장치 회로가 없다
\*      (장치가 강제하는 것은 `0xE14` 판정 하나뿐). **몫 없음 — 장치 경계 밖**.
\*  15. 비정렬 *읽기* `0xE15`–`0xE17` — 0 · fault 없음(03-hiu 비정렬 읽기 규범). 모델의 읽기는 정렬만.
\*      몫: MmioPage(ReadVal — 부류 무관 비정렬 읽기 0) · assembly 페이지 처분.
\*
\* ## 규모와 분리 검사 (실측은 run.sh 이 절 머리)
\*
\*   작은 cfg(파티션 2 · 상한 1) · 큰 cfg(파티션 4 = 인코딩 상한 · 상한 2). VIEW 없음 — 상태가 작다.
\*   분리 검사(비상주): 가드마다 지운 판에 가드 속성 전부 + 고정 속성을 걸고 위반을 하나씩 벗긴다.
\*   고정 속성 여섯은 전부 상주 음성 run 을 갖는다(위 「고정 속성」 의 ←).
\*
EXTENDS Naturals, FiniteSets

CONSTANTS
    Parts,           \* 실재 파티션 (불투명 토큰)
    P0,              \* reset 값 [7:0] = 0 의 파티션
    Phantom,         \* 없는 파티션 값 (≥ 실재 파티션 수 — E.1.2 「없는 파티션 값의 처분」)
    MaxJobs,         \* 꼬리표 하나당 진행 중인 일의 상한 (상태 유한화 — 환경 배압)
    DSample,         \* D 표집 꼴 — "alpha"(좋은 모델 · DP-4) | "beta"(대안: ALLZERO(t) ∧ ¬접수(t))
                     \*   | "lag"(대안: α 인데 t 접수가 t+1 점유에 아직 안 든다 — 닫힌 목록 3 의 RTL 사실)
    StallAlt,        \* α 정지의 길이 — "pulse"(좋은 모델: actPend 그 자체) | "hold"(대안: 한 사이클 더)
    SameAlt,         \* 같은 값 기입 — "noop"(정본) | "reject"(짝: 같은 값 ∧ D = 0 → 거절)
    Today,           \* TRUE = W4 전 RTL(HEAD f67e3d6) — 0xE14 쓰기 흡수 · 요청 파티션은 포트
    DisabledGuards

AllGuards == {"value_first", "rsv_strict", "ro_field_ignored", "drain_gates_switch",
              "same_value_noop", "ad_every_accept", "d_includes_same_cycle",
              "pend_stalls_req", "pend_stalls_mmio", "req_part_from_bound",
              "unaligned_outside", "reject_loud"}

ASSUME P0 \in Parts /\ Phantom \notin Parts /\ MaxJobs \in Nat \ {0}
ASSUME DSample \in {"alpha", "beta", "lag"} /\ StallAlt \in {"pulse", "hold"} /\ SameAlt \in {"noop", "reject"} /\ Today \in BOOLEAN
ASSUME DisabledGuards \subseteq AllGuards

On(g) == g \notin DisabledGuards

\* α 꼴(판정을 t+1 로 미루고 그 사이클을 정지) — 좋은 모델과 대안 lag 가 공유한다.
Alphaish == DSample \in {"alpha", "lag"}

Vals == Parts \cup {Phantom}
\* value_first 를 지운 판의 필드 절단 — 없는 값이 실재 파티션(reset 파티션)으로 접힌다.
Alias(v) == IF v = Phantom THEN P0 ELSE v

Busy(j) == \E p \in Parts : j[p] > 0

VARIABLES
    jobs,            \* [Parts -> 0..MaxJobs] 진행 중인 일 — 꼬리표(접수 시점 파티션)는 유령, 장치는 Busy 만 본다
    bound,           \* 장치 0xE14 [7:0] — 결속 파티션
    regA,            \* 장치 [8] APPLIED
    regD,            \* 장치 [9] DRAINED
    pend,            \* α 의 actPend — t 에 수락된 기입이 t+1 판정을 기다린다
    gB, gA, gD,      \* 유령 — 정본 레지스터 (수락 에지에 원자적으로 판정)
    gRej,            \* 유령 — 마지막 수락 기입의 정본 판정이 거절인가
    wacc,            \* 보조 — 이 스텝에 0xE14 기입으로 처리된 정렬 기입
    uacc,            \* 보조 — 이 스텝에 버스가 수락한 비정렬 쓰기(0xE15–0xE17)
    rd,              \* 보조 — 이 스텝의 0xE14 읽기와 그 값
    vrej,            \* 보조 — 이 스텝의 값 검사 거절
    res,             \* 보조 — 이 스텝에 판정이 *적용된* 기입 (α: t+1 · β: t)
    lV, lR, lU,      \* 보조 — 이 스텝의 [6] 발화: 값 검사 · 드레인 판정 · 비정렬
    rq, rqP,         \* 보조 — 이 스텝에 접수된 요청과 그 파티션
    stR, stM,        \* 보조 — 이 스텝에 α 정지로 막힌 요청 · MMIO 접근
    hold             \* 대안 "hold" 의 늘인 정지 — 앞 스텝의 pend.on (좋은 모델에서는 늘 FALSE)

vars == <<jobs, bound, regA, regD, pend, gB, gA, gD, gRej,
          wacc, uacc, rd, vrej, res, lV, lR, lU, rq, rqP, stR, stM, hold>>

\* grej — 그 기입 *자신*의 정본 판정(수락 에지의 ~gApply)을 판정 사이클까지 싣는다. 「마지막 기입」의
\* 유령 gRej 로 대조하면 t+1 에 둘째 기입이 들어오는 꼴에서 앞 기입의 적법한 [6] 이 둘째 기입 몫으로
\* 읽힌다(검증 반례 W27) — 속성이 pend_stalls_mmio 에 기대지 않도록 기입별로 나른다.
\* dl — 대안 lag 의 D: t 에지의 퇴장은 반영하고 같은 사이클 접수는 아직 세지 않은 점유.
PendT == [on: BOOLEAN, v: Parts, ok: BOOLEAN, ro: BOOLEAN, d0: BOOLEAN, dl: BOOLEAN,
          gd: BOOLEAN, pre: BOOLEAN, rqs: BOOLEAN, grej: BOOLEAN]
ResT  == [on: BOOLEAN, v: Parts, ok: BOOLEAN, same: BOOLEAN, apply: BOOLEAN,
          ro: BOOLEAN, gd: BOOLEAN, pre: BOOLEAN, rqs: BOOLEAN, ab: BOOLEAN, grej: BOOLEAN]
NoPend == [on |-> FALSE, v |-> P0, ok |-> TRUE, ro |-> FALSE, d0 |-> FALSE, dl |-> FALSE,
           gd |-> FALSE, pre |-> FALSE, rqs |-> FALSE, grej |-> FALSE]
NoRes  == [on |-> FALSE, v |-> P0, ok |-> TRUE, same |-> FALSE, apply |-> FALSE,
           ro |-> FALSE, gd |-> FALSE, pre |-> FALSE, rqs |-> FALSE, ab |-> FALSE, grej |-> FALSE]
NoWacc == [on |-> FALSE, v |-> P0, rsv |-> FALSE, ro |-> FALSE]
NoRd   == [on |-> FALSE, b |-> P0, a |-> FALSE, d |-> FALSE]

TypeOK ==
    /\ jobs \in [Parts -> 0..MaxJobs]
    /\ bound \in Parts /\ regA \in BOOLEAN /\ regD \in BOOLEAN
    /\ pend \in PendT
    /\ gB \in Parts /\ gA \in BOOLEAN /\ gD \in BOOLEAN /\ gRej \in BOOLEAN
    /\ wacc \in [on: BOOLEAN, v: Vals, rsv: BOOLEAN, ro: BOOLEAN]
    /\ uacc \in BOOLEAN
    /\ rd \in [on: BOOLEAN, b: Parts, a: BOOLEAN, d: BOOLEAN]
    /\ vrej \in BOOLEAN /\ res \in ResT
    /\ lV \in BOOLEAN /\ lR \in BOOLEAN /\ lU \in BOOLEAN
    /\ rq \in BOOLEAN /\ rqP \in Parts /\ stR \in BOOLEAN /\ stM \in BOOLEAN /\ hold \in BOOLEAN

Init ==
    /\ jobs = [p \in Parts |-> 0]
    /\ bound = P0 /\ regA = FALSE /\ regD = FALSE      \* reset [9:0] = 0
    /\ pend = NoPend
    /\ gB = P0 /\ gA = FALSE /\ gD = FALSE /\ gRej = FALSE
    /\ wacc = NoWacc /\ uacc = FALSE /\ rd = NoRd /\ vrej = FALSE /\ res = NoRes
    /\ lV = FALSE /\ lR = FALSE /\ lU = FALSE
    /\ rq = FALSE /\ rqP = P0 /\ stR = FALSE /\ stM = FALSE /\ hold = FALSE

\* 한 사이클의 MMIO 입력 — 버스는 한 번에 하나 (k = "none" | "rd" | "wr").
Ops == {o \in [k: {"none", "rd", "wr"}, v: Vals, rsv: BOOLEAN, ro: BOOLEAN, al: BOOLEAN] :
            o.k # "wr" => (o.v = P0 /\ ~o.rsv /\ ~o.ro /\ o.al)}
NoOp == [k |-> "none", v |-> P0, rsv |-> FALSE, ro |-> FALSE, al |-> TRUE]

(***************************************************************************)
(* 한 스텝 = 한 클록 에지. 입력: MMIO 접근 op · 요청 제시 rqW(파티션 꼬리표   *)
(* tag 는 포트 결속일 때만 뜻이 있다) · 이 에지에 빠져나가는 일 L.           *)
(***************************************************************************)
\* 가드 자리: value_first(phBad) · rsv_strict · ro_field_ignored(vbad) · drain_gates_switch ·
\* same_value_noop(rapply) · ad_every_accept(regA') · d_includes_same_cycle(dA) · pend_stalls_req ·
\* pend_stalls_mmio(reqOK · mmioOK) · req_part_from_bound(sp) · unaligned_outside(unal) · reject_loud(lV · lR).
\* 정본 유령(sWr · gOk · gSame · gApply)은 가드를 읽지 않는다.
Step(op, rqW, tag, L) ==
  LET stall    == Alphaish /\ (pend.on \/ (StallAlt = "hold" /\ hold))   \* α 의 t+1 (hold: t+2 까지)
      mmioOK   == ~(stall /\ On("pend_stalls_mmio"))
      reqOK    == ~(stall /\ On("pend_stalls_req"))
      o        == IF mmioOK THEN op ELSE NoOp
      sp       == IF On("req_part_from_bound") /\ ~Today THEN bound ELSE tag
      acceptR  == rqW /\ reqOK /\ jobs[sp] < MaxJobs
      jobs1    == [p \in Parts |-> jobs[p] + (IF acceptR /\ p = sp THEN 1 ELSE 0)
                                           - (IF p \in L THEN 1 ELSE 0)]
      preBusy  == Busy(jobs)
      postZero == ~Busy(jobs1)
      lagZero  == ~Busy([p \in Parts |-> jobs[p] - (IF p \in L THEN 1 ELSE 0)])  \* lag: 접수 미반영
      \* --- 쓰기 디코드 (장치)
      isU      == o.k = "wr" /\ ~o.al
      unal     == isU /\ On("unaligned_outside")
      awr      == o.k = "wr" /\ ~unal /\ ~Today
      phBad    == o.v = Phantom /\ (On("value_first") \/ Alias(o.v) # bound)
      vbad     == awr /\ (phBad \/ (o.rsv /\ On("rsv_strict"))
                              \/ (o.ro /\ ~On("ro_field_ignored")))
      wv       == Alias(o.v)
      \* --- 정본 (유령 — 가드 없음): 정렬 0xE14 기입을 수락 에지에 원자적으로 판정
      sWr      == o.k = "wr" /\ o.al
      gOk      == o.v \in Parts /\ ~o.rsv
      gSame    == o.v = gB
      gApply   == gOk /\ (gSame \/ postZero)
      \* --- 장치 판정 (α: pend 의 t+1 · β: 기입 사이클 t)
      sGrej    == IF sWr THEN ~gApply ELSE FALSE               \* 이 기입 자신의 정본 판정
      resolveA == Alphaish /\ pend.on
      dA       == IF DSample = "lag" THEN pend.dl
                  ELSE IF On("d_includes_same_cycle") THEN ~preBusy ELSE pend.d0
      dB       == ~preBusy /\ ~acceptR                         \* β = ALLZERO(t) ∧ ¬접수(t)
      resolveB == DSample = "beta" /\ awr
      rv       == IF resolveA THEN pend.v ELSE wv
      rok      == IF resolveA THEN pend.ok ELSE ~vbad
      rD       == IF resolveA THEN dA ELSE dB
      rsame    == rv = bound
      sameNoop == rsame /\ On("same_value_noop") /\ SameAlt = "noop"
      rapply   == rok /\ (sameNoop \/ rD \/ ~On("drain_gates_switch"))
      resolve  == resolveA \/ resolveB
  IN
  /\ L \subseteq {p \in Parts : jobs[p] > 0}
  /\ jobs' = jobs1
  /\ bound' = IF resolve /\ rapply THEN rv ELSE bound
  /\ regA'  = IF resolve /\ (On("ad_every_accept") \/ rapply) THEN rapply ELSE regA
  /\ regD'  = IF resolve THEN rD ELSE regD
  /\ pend'  = IF Alphaish /\ awr
                 THEN [on |-> TRUE, v |-> wv, ok |-> ~vbad, ro |-> o.ro, d0 |-> ~preBusy,
                       dl |-> lagZero, gd |-> postZero, pre |-> preBusy, rqs |-> acceptR,
                       grej |-> sGrej]
                 ELSE NoPend
  /\ res'   = IF resolve
                 THEN [on |-> TRUE, v |-> rv, ok |-> rok, same |-> rsame, apply |-> rapply,
                       ro |-> IF resolveA THEN pend.ro ELSE o.ro,
                       gd |-> IF resolveA THEN pend.gd ELSE postZero,
                       pre |-> IF resolveA THEN pend.pre ELSE preBusy,
                       rqs |-> IF resolveA THEN pend.rqs ELSE acceptR,
                       ab |-> regA,
                       grej |-> IF resolveA THEN pend.grej ELSE sGrej]
                 ELSE NoRes
  /\ wacc'  = IF awr THEN [on |-> TRUE, v |-> o.v, rsv |-> o.rsv, ro |-> o.ro] ELSE NoWacc
  /\ uacc'  = isU
  /\ vrej'  = vbad
  /\ lV'    = (vbad /\ On("reject_loud"))
  /\ lR'    = (resolve /\ rok /\ ~rapply /\ On("reject_loud"))
  /\ lU'    = unal
  /\ rd'    = IF o.k = "rd" THEN [on |-> TRUE, b |-> bound, a |-> regA, d |-> regD] ELSE NoRd
  /\ gB'    = IF sWr /\ gApply THEN o.v ELSE gB
  /\ gA'    = IF sWr THEN gApply ELSE gA
  /\ gD'    = IF sWr THEN postZero ELSE gD
  /\ gRej'  = IF sWr THEN ~gApply ELSE gRej
  /\ rq'    = acceptR
  /\ rqP'   = IF acceptR THEN sp ELSE P0
  /\ stR'   = (rqW /\ ~reqOK)
  /\ stM'   = (op.k # "none" /\ ~mmioOK)
  /\ hold'  = (StallAlt = "hold" /\ pend.on)

Leaves == {{}} \cup {{p} : p \in Parts}
Tags   == IF On("req_part_from_bound") /\ ~Today THEN {P0} ELSE Parts

Next == \E op \in Ops, rqW \in BOOLEAN, tag \in Tags, L \in Leaves : Step(op, rqW, tag, L)

Spec == Init /\ [][Next]_vars

(***************************************************************************)
(* 가드 속성 — 각 가드를 지운 run 의 첫 위반                                 *)
(***************************************************************************)
Prop_ValueFirst        == [][ (wacc'.on /\ wacc'.v = Phantom) => vrej' ]_vars
Prop_RsvRejected       == [][ (wacc'.on /\ wacc'.rsv) => vrej' ]_vars
Prop_RoFieldIgnored    == [][ (wacc'.on /\ wacc'.ro /\ ~wacc'.rsv /\ wacc'.v \in Parts) => ~vrej' ]_vars
Prop_SwitchOnlyDrained == [][ bound' # bound => (res'.on /\ res'.apply /\ regD') ]_vars
Prop_SameValueNoFault  == [][ (res'.on /\ res'.ok /\ res'.same) => (regA' /\ ~lR' /\ bound' = bound) ]_vars
Prop_AdEveryAccept     == [][ res'.on => regA' = res'.apply ]_vars
Prop_DIsPostEdge       == [][ res'.on => regD' = res'.gd ]_vars
Prop_NoAcceptAcrossSwitch == [][ rq' => bound' = bound ]_vars
Prop_ReadIsSpec        == [][ rd'.on => (rd'.b = gB /\ rd'.a = gA /\ rd'.d = gD) ]_vars
Prop_ReqPartIsBound    == [][ rq' => rqP' = bound ]_vars
Prop_UnalignedInert    == [][ uacc' => (lU' /\ ~wacc'.on) ]_vars
Prop_RejectLoud        == [][ /\ (vrej' => lV')
                              /\ ((res'.on /\ res'.ok /\ ~res'.apply) => lR') ]_vars

(***************************************************************************)
(* 고정 속성                                                                  *)
(***************************************************************************)
Inv_ObsIsSpec == ~pend.on => (bound = gB /\ regA = gA /\ regD = gD)
Inv_WorkUnderBound == \A p \in Parts : p # bound => jobs[p] = 0
Prop_NoStaleWorkAfterSwitch == [][ bound' # bound => jobs'[bound] = 0 ]_vars
Prop_LoudOnlySpec == [][ /\ (lV' => (wacc'.on /\ gRej'))
                         /\ (lR' => (res'.on /\ res'.grej))
                         /\ (lU' => uacc') ]_vars
Prop_A0D1IsValueReject == [][ /\ ((res'.on /\ ~regA' /\ regD') => ~res'.ok)
                              /\ ((res'.on /\ ~res'.ok /\ res'.gd) => (~regA' /\ regD')) ]_vars
\* 정지는 판정 사이클(pend 가 선 스텝)에만 — pend 는 늘 한 스텝짜리라 정지의 길이 = 정확히 1 사이클이고
\* 풀린다. 이것이 없으면 「특정 사건 뒤 영영 선 정지」가 안전 속성 전부를 통과한다(검증 변이 H15b/d/e/f).
Prop_StallOnlyPend == [][ (stM' \/ stR') => pend.on ]_vars

(***************************************************************************)
(* 증인 — 좋은 모델에서 반드시 반증된다                                       *)
(***************************************************************************)
Witness_NoSwitch          == ~(res.on /\ res.apply /\ ~res.same)
Witness_NoDrainReject     == ~(res.on /\ res.ok /\ ~res.apply)
Witness_NoSameUndrained   == ~(res.on /\ res.ok /\ res.same /\ ~res.gd)
Witness_NoA0D1            == ~(res.on /\ ~regA /\ regD)
Witness_NoPhantomWr       == ~(wacc.on /\ wacc.v = Phantom)
Witness_NoRsvWr           == ~(wacc.on /\ wacc.rsv /\ wacc.v \in Parts)
Witness_NoRoApplied       == ~(res.on /\ res.ro /\ res.apply)
Witness_NoSameCycleReject == ~(res.on /\ res.ok /\ ~res.same /\ ~res.apply /\ res.rqs /\ ~res.pre)
Witness_NoEdgeLeaveSwitch == ~(res.on /\ res.apply /\ ~res.same /\ res.pre)
Witness_NoReqStall        == ~stR
Witness_NoMmioStall       == ~stM
Witness_NoReqAfterSwitch  == ~(rq /\ rqP # P0)
Witness_NoUnaligned       == ~uacc
Witness_NoSettledRead     == ~(rd.on /\ rd.a)
Witness_NoALowered        == ~(res.on /\ res.ab /\ ~res.apply)
Witness_NoValRejUndrained == ~(res.on /\ ~res.ok /\ ~res.gd)              \* (0,0) 의 값 거절 절반 (E:557)
Witness_NoSameDrained     == ~(res.on /\ res.ok /\ res.same /\ res.gd)    \* (1,1) 의 같은 값 절반
Witness_NoValRejSameCycle == ~(vrej /\ rq)                                \* 값 거절과 같은 사이클의 요청 접수

=============================================================================
