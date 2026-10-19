\* SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
\* SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
--------------------------- MODULE Platform ---------------------------
(***************************************************************************)
(* HIU-8 · HIU-9 · HIU-10 선-formal 모델 — 플랫폼 독립.                    *)
(*                                                                         *)
(*   HIU-8  DVMA 독립 — 같은 가상 주소의 변환 결과는 호스트 변환 서비스의   *)
(*          가용 여부에 의존하지 않는다.                                    *)
(*   HIU-9  zero-copy 독립 — 캐시 일관 상호연결이 없는 구성에서도, 소유권   *)
(*          규약을 지킨 접근열의 관측 결과는 있는 구성과 같다.              *)
(*   HIU-10 소유권 배타성 — 소유하지 않은 쪽의 접근은 반드시 fault 다.      *)
(*                                                                         *)
(* ## 왜 두 세계를 한 모델에 두는가 — 이 속성은 관계 속성이다              *)
(*                                                                         *)
(* 앞의 네 모델(SharedUnit·ResultBank·XlateStore·Route)의 속성은 전부       *)
(* *한 기계 안의* 성질이었다. HIU-8·9 는 다르다 — "A 구성과 B 구성의 결과가 *)
(* 같다" 는 **두 실행의 비교**이고, 기계 하나를 모델링해 "잘 돈다" 를        *)
(* 보이는 것으로는 아무것도 증명되지 않는다. 플랫폼 종속은 기계가 고장나는  *)
(* 것이 아니라 *플랫폼에 따라 다르게 도는 것*이기 때문이다.                 *)
(*                                                                         *)
(* 그래서 이 모델은 두 세계를 함께 들고 간다:                               *)
(*                                                                         *)
(*   plain — 호스트에 변환 서비스도 캐시 일관 상호연결도 *없다*             *)
(*   rich  — 둘 다 *있다*                                                   *)
(*                                                                         *)
(* 그리고 모든 동작을 **같은 인자로 두 세계에 동시에** 건다 (lockstep).     *)
(* 입력이 같지 않으면 출력 비교는 무의미하므로, 이 lockstep 이 모델의        *)
(* 전제 전부다. 두 세계는 *플랫폼 능력에서만* 다르다.                       *)
(*                                                                         *)
(* ## 이 모델이 덮지 않는 것                                               *)
(*                                                                         *)
(*   ⚠️ 일관성을 「즉시 전파」로 추상했다 — 실제 상호연결의 전파 지연·재정렬 *)
(*      은 없다. 그 축은 §4.4.4 의 명시적 순서 의존과 함께 후-formal 이 맡  *)
(*      는다. 여기서 묻는 것은 *지연이 있는가*가 아니라 *규약이 일관성을     *)
(*      대신할 수 있는가*다.                                               *)
(*   ⚠️ 페이지 안의 오프셋이 없다 — 페이지가 값 하나를 갖는다. 소유권 단위가 *)
(*      페이지이므로(§3.4.1 1번) 이 추상은 소유권 축에서 손실이 없다.        *)
(*   ⚠️ 부분 소유·중간 상태가 없다 — §3.4.1 이 "중간 상태는 없다" 고 규정한  *)
(*      것을 타입으로 반영했다. 그 규정 자체를 시험하지는 않는다.           *)
(***************************************************************************)
\*
\* ## 승인 거부의 보고 비트 — FAULT_STATUS [4] 와 [19] (3.10 v1.0 묶음 · W1, 2026-10-11)
\*
\* 정본 (좌표 뒤 「」 는 그 줄의 축자 — lint_section_refs 축 1 이 대조한다)
\*   e-defined.typ:518 「변환 권한 위반 — 자격(권한 비트) 거부」
\*   e-defined.typ:523 「비소유 프레임 접근 — 자격(권한 비트)은 허용했으나 승인 단의 소유권 판정이 장치 소유가 아니라서 거부된 접근」
\*   e-defined.typ:527 「권한 비트가 그 접근을 허용하지 않으면 소유와 무관하게 `[4]` 만 서고」
\*   e-defined.typ:527 「자격이 허용된 접근이 장치 소유가 아닌 프레임에 닿을 때만 `[19]` 가 선다 — 한 접근에 둘이 함께 서지 않는다」
\*   e-defined.typ:527 「거부 채움(V=1 · R = W = X = 0 — E.3 2항)은 프레임이 무엇이든 `[4]` 로만 선다」
\*   e-defined.typ:527 「값 차단 · 승인 거부 · 상태열」 — 둘이 같고 갈리는 것은 보고 비트뿐이다.
\*   e-defined.typ:529 「우선순위를 자격 먼저로 둔 것은 호스트가 회수 · 부팅에서 쓰는 거부 채움의 `[4]` 를 예상한 사건으로 따로 분류할 수 있게 하고」
\*   e-defined.typ:1418 「자격이 먼저이므로 권한 비트가 허용한 접근만 `[19]` 로 가고」
\*   03-hiu.typ:362 「소유하지 않은 쪽의 접근은 *loud fault* 이며 sticky 다」 — HIU-10 의 몸.
\*   03-hiu.typ:363 「권한 비트가 그 접근을 허용하지 않으면 소유와 무관하게 `[4]` 가 대신 선다 — 자격이 먼저다」
\*   03-hiu.typ:363 「장치 쪽 접근의 보고 비트는 FAULT_STATUS `[19]`」 — 보고 축은 장치 접근 한정이다.
\*   e-defined.typ:873 「승인 거부(`[4]` — 거부 채움은 프레임이 무엇이든 자격 거부다」 — 드레인 근거가 기대는 승인 거부.
\*
\* 앞판의 이 모델은 판정 결과가 obsKind ∈ {none, value, fault} 하나뿐이라 자격(권한
\* 비트)이라는 개념이 없었고, 그래서 [4] 와 [19] 의 가름을 표현할 수 없었다. 이 판은
\* 사상에 권한 비트(perm ⊆ {r, w} — 거부 채움 = {})를 싣고, 접근마다 접근한 쪽(obsWho),
\* 그 접근이 세운 보고 비트 집합 obsBits ⊆ {4, 19}, 승인 판정 obsDec ∈ {miss, grant, deny}
\* (grant = 읽기는 값을 돌려받고 쓰기는 반영된다 · deny = 값 차단 + 승인 거부), 원인 사실
\* 둘(obsEnt — 권한 비트가 그 접근을 허용했는가 · obsOwned — 접근한 쪽이 소유자인가)을
\* 기록한다. 쓰기도 승인을 지나므로 Write 도 관측을 남긴다(값은 남기지 않는다 — obsKind 는
\* 읽기의 축 그대로다).
\*
\* 자격(권한 비트) · 보고 비트는 **장치 접근만**의 축이다 — 권한 비트는 HIU 변환 항목의 것이고
\* FAULT_STATUS 는 장치 요청 파이프의 승인 단(3.2)이 세운다. 호스트 접근의 값 차단은 앞판
\* 그대로 미사상 ∨ 비소유이고, 호스트 접근은 보고 비트를 세우지 않는다(Inv_ReportBitByCause
\* 가 {} 를 요구한다). 그래서 [19] 의 원인 「접근한 쪽 ≠ 소유자」 는 장치 접근에서 정확히
\* ¬devOwned 다. 미사상은 보고 비트가 없다(미적중 통지는 FAULT_STATUS 에 들지 않는다 —
\* e-defined.typ:526 「미적중 통지(`0xE04[1]`)와 능력 부재」).
\*
\* 값 차단 · 승인 거부는 두 원인이 같다 — 자격 거부의 값 차단은 가드 entitle_gates_value,
\* 비소유의 값 차단은 기존 owner_check 가 진다. 속성은 Inv_EntDeniedBlocked(자격 쪽) ·
\* Inv_UnownedFaults(소유 쪽, 앞판 문면) · Inv_DenyIffReported(「갈리는 것은 보고 비트뿐」 —
\* 사상된 장치 접근은 승인 거부일 때 정확히 보고 비트가 선다)다.
\*
\* 가드 넷 — 각각 RTL 의 한 자리와 일대일 (GUARD-MAP 대응 예정 이름, RTL 착지 전)
\*
\*   entitle_gates_value 자격 거부는 값 차단 + 승인 거부다 — 비소유와 같은 처분.
\*                      RTL: HiuPipeline.granted = s6.valid ∧ s6.anyHit ∧ devOwned ∧ entitle
\*                      의 `entitle` 항 (오늘 그대로 — W1 이 바꾸지 않는 줄, GUARD-MAP 만 단다).
\*                      지우면 자격 거부 장치 접근(거부 채움이 전형)이 값을 돌려받고 쓰기가
\*                      반영된다 → Inv_EntDeniedBlocked.
\*
\*   perm_entitle_only  [4] 는 자격 거부에서만 선다 — 소유는 [4] 의 항이 아니다.
\*                      RTL: HiuPipeline.permViol = s6.valid ∧ s6.anyHit ∧ ¬entitle
\*                      (W1 전 RTL(HEAD 3b80087)의 ¬(devOwned ∧ entitle) 를 제자리에서 좁힌다).
\*                      지우면 자격 허용 ∧ 비소유 접근이 [4] 를 세운다 → Inv_Bit4EntOnly.
\*   entitle_first      [19] 는 자격이 허용된 접근에서만 — 자격 거부가 비소유를 가린다.
\*                      RTL: HiuPipeline.ownViol = s6.valid ∧ s6.anyHit ∧ entitle ∧ ¬devOwned
\*                      의 `entitle` 항. 지우면 자격 거부 ∧ 비소유 접근(거부 채움된 회수
\*                      페이지가 전형)이 [4] 와 [19] 를 함께 세운다 → Inv_OneBitPerAccess ·
\*                      거부 채움 변형 → Inv_DenyFillIs4.
\*   own_reported       자격 허용 ∧ 비소유 접근은 [19] 를 세운다 — 원천이 실재한다.
\*                      RTL: HiuPipeline.faultOwn = StickyFault(ownViol, …) → 원천별 수출
\*                      (io.fault.hiuOwn 류) → Wt64Top FAULT_STATUS [19] (B_OWN_FRAME = 19).
\*                      지우면 [4] 를 좁힌 판에서 그 접근이 어느 비트도 세우지 않는다(값만
\*                      막힌 조용한 거부) → Inv_UnownedLoud.
\*
\* 고정 의미의 속성 (좋은 모델 cfg 가 전부 건다)
\*   Inv_ReportBitByCause  보고 비트 = 원인의 정확 등식: 자격 거부 → {4} · 자격 허용 ∧ 비소유
\*                         → {19} · 그 밖(승인 · 미사상) → {}. 「오늘의 RTL」(W1 전 RTL — HEAD 3b80087) 짝의 목표 속성.
\*   Inv_OneBitPerAccess   한 접근에 둘이 함께 서지 않는다.
\*   Inv_Bit4EntOnly       [4] 가 섰으면 그 접근은 자격 거부였다.
\*   Inv_UnownedLoud       기존 Inv_UnownedFaults(값 차단)의 보고 짝 — 비소유 접근이면 [4] 와
\*                         [19] 중 하나는 선다. 앞판 HIU-10 의 「loud」 를 원인별 둘로 가른 뒤에도
\*                         「둘 중 하나는 선다」 로 보존한다.
\*   Inv_DenyFillIs4       거부 채움(perm = {})을 지난 장치 접근은 프레임 소유와 무관하게 {4}.
\*   Inv_EntDeniedBlocked  자격 거부 장치 접근은 승인 거부(값 차단 · 쓰기 미반영)다.
\*   Inv_DenyIffReported   사상된 장치 접근은 승인 거부 ⇔ 보고 비트가 선다 — 값 차단 · 승인
\*                         거부는 두 원인이 같고 갈리는 것은 보고 비트뿐이다.
\* (불변식 셋 — 원인 사실 · 보고 · 판정 — 은 접근한 쪽이 장치일 때만 건다. Inv_UnownedFaults 는
\* 앞판 그대로 두 접근자 모두에 건다.)
\*
\* 짝 「오늘의 RTL」 = 가드 둘(perm_entitle_only · own_reported)을 지운 판 — W1 전 RTL(HEAD 3b80087)은
\* permViol = ¬(devOwned ∧ entitle) 하나로 두 원인을 [4] 에 접고 [19] 원천이 없다.
\* Inv_ReportBitByCause 를 깬다(자격 허용 ∧ 비소유 → {4}). 대비 MUST PASS — 같은 판이
\* Inv_OneBitPerAccess · Inv_UnownedLoud · Inv_DenyFillIs4 · Inv_UnownedFaults ·
\* Inv_EntDeniedBlocked · Inv_DenyIffReported 와 HIU-8/9 불변식은 전부 통과한다: W1 전 RTL 의
\* 간극이 원인 귀속 하나뿐임을 기계로 붙잡는다 (그 판의 granted 도 entitle 항을 이미 가졌다 — W1 은 그 줄을 바꾸지 않았다).
\*
\* 이 판이 재지 않는 것 (「안 잰다」 — 닫힌 목록)
\*   · sticky · W1C(0xF84 [19] 해제) · 발화 우선 — obsBits 는 그 접근의 발화 펄스다.
\*   · 승인 상태열의 동일성 — 단계 축은 Isolation(coh_no_shortcut) · Decode(stall_uniform).
\*   · 표현 불가 프레임(e-defined.typ:1418 「표현 불가 프레임은 유효하게 사상된 페이지이므로」) —
\*     소유권 표에 없는 프레임은 이 모델에서 「장치 소유 아님」 과 같은 페이지로 접힌다.
\*   · 실행 권한(x) — 요청 종류에 실행이 없다. perm 은 읽기 · 쓰기 둘만 싣는다.
\*   · [19] 캡처 — 정본이 v1.0 에 두지 않는다.
\*   · 호스트 쪽 접근의 자격 · 보고 — 호스트 접근은 HIU 권한 비트의 판정 대상이 아니고(값 차단은
\*     미사상 ∨ 비소유) FAULT_STATUS 를 세우지 않는다. 호스트 쪽 비소유 처분의 보고 경로는
\*     정본의 장치 레지스터 축 밖이다 (03-hiu.typ:363 「장치 쪽 접근의 보고 비트는 FAULT_STATUS `[19]`」).
\*   · 거부된 쓰기의 미반영은 판정(obsDec)과 같은 AccFault 로 구조적이다 — 쓰기 경로만 따로
\*     승인을 무시하는 변이는 RTL 쪽(hiumask granted ⇒ 값 · 쓰기)의 몫이다.
\*
\* ## OWN_SET 의 거절 — FAULT_STATUS [7] (3.10 v1.0 묶음 · W6, 2026-10-18)
\*
\* 정본 (좌표 뒤 「」 는 그 줄의 축자 — lint_section_refs 축 1 이 대조한다)
\*   e-defined.typ:1387 「장치는 OWN_SET 을 *거절할 수 있다*」
\*   e-defined.typ:1387 「어느 프레임이 거절되는가는 구현의 형상이 정하고 호스트 계약이 아니다」
\*   e-defined.typ:1387 「거절은 *무효과*다」 · 「아무것도 축출하지 않는다」 · 「축출은 암묵 전이다」
\*   e-defined.typ:1387 「거절은 loud sticky fault FAULT_STATUS `[7]` 을 세운다」
\*   e-defined.typ:1387 「장치 소유 페이지가 하나도 없을 때의 OWN_SET 에는 형상 · 점유에 따른 거절이 없다」
\*   e-defined.typ:1387 「*이미 장치 소유인 페이지*의 OWN_SET 은 무연산이다」
\*   e-defined.typ:1387 「*OWN_CLR 은 형상 · 점유로 거절되지 않는다*」
\*   e-defined.typ:527 「`[7]` 은 E.7 6항의 OWN_SET 거절 *하나*」 — [7] 의 유일한 원천.
\*
\* 앞판의 Handoff 는 용량이 없어 이양을 *늘* 커밋했다 — 정본이 허락한 거절이 모델에 없었고,
\* 그래서 「거절은 무효과」「[7] 은 거절에서만」 을 걸 자리도 없었다. 이 판은 거절을 형상
\* 중립의 *비결정 분기* OwnSetReject 로 들인다: 정본이 거절을 형상에 맡기므로(「호스트 계약이
\* 아니다」) 모델은 「언제 거절하는가」 를 정하지 않고 *거절이 허락되는 울타리*(하한 · 이미 소유
\* 무연산)와 *거절의 처분*(무효과 · 축출 없음 · [7])만 건다. 어떤 형상이든 이 울타리 안의
\* 거절은 전부 탐색된다. 상수 SetShape = "direct" 는 HEAD RTL 의 형상(직접 사상 — 같은 색인 ·
\* 다른 태그면 거절, 아니면 커밋)을 결정적으로 고정한 대비 — 울타리가 RTL 을 배제하지 않음을
\* 보인다 (페이지 셋 · 둘이 한 칸 · 하나가 혼자 — 충돌 커밋 불가 · 비충돌 공존 둘 다 도달).
\*
\* 가드 여섯 — RTL 자리는 OwnershipTable.scala (GUARD-MAP 은 그 파일 끝)
\*   set_reject_inert   거절은 무효과 — 소유 · 배후 저장 · 사본이 그대로다. 지우면 거절이
\*                      대상을 앉히고 다른 장치 소유 페이지를 축출한다(직접 사상 덮어쓰기)
\*                      → Prop_SetRejectInert.
\*   set_reject_loud    거절은 [7] 을 세운다. 지우면 조용한 거절 → Prop_SetRejectLoud.
\*   set_reject_floor   하한 — 다른 장치 소유 페이지가 없으면 거절이 허락되지 않는다. 지우면
\*                      빈 표의 OWN_SET 이 거절된다 → Prop_SetRejectFloor.
\*   set_owned_noop     이미 장치 소유인 페이지의 OWN_SET 은 무연산(거절 아님). 지우면 그 기입이
\*                      거절 + [7] 이 된다 → Prop_OwnedSetNoop.
\*   clr_no_reject      OWN_CLR 에는 거절 분기가 없다. 지우면 OWN_CLR 이 거절 + [7] 이 된다
\*                      → Prop_ClrNoReject.
\*   seven_reject_only  [7] 은 거절에서만 선다 — 커밋 · 무연산은 [7] 을 세우지 않는다(상승 건전성).
\*                      지우면 커밋된 OWN_SET 이 [7] 을 세운다 → Prop_SevenRejectOnly.
\* 고정 속성 Prop_NoImplicitTransition — 소유가 바뀌는 페이지는 그 스텝의 *커밋된* 전이 기입의
\*   대상 하나뿐이다(축출 · 암묵 전이 없음). 상주 음성 = set_reject_inert 삭제의 둘째 run.
\* 대비 SetShape = "direct" 의 Inv_SlotExclusive — 한 칸에 장치 소유 페이지는 하나.
\* 측정 범위 (공허 칸 — 결함 아님): 거절은 하한 울타리 때문에 페이지 1 판(Platform_base)에서
\*   한 번도 열리지 않는다 — 그 판의 Prop_SetRejectInert · Prop_SetRejectLoud · Prop_SetRejectFloor 는
\*   전건 공허다. 거절 축은 페이지 ≥ 2 판(shapeA · shapeB · direct)이 재고, 증인 Witness_NoSetReject
\*   (페이지 2)가 그 도달을 상주로 보인다. Prop_SevenRejectOnly 의 전건(거절 밖의 [7])은 좋은
\*   모델 어디서도 도달하지 않는다 — 상승 건전성이므로 당연하고, 반증력은 seven_reject_only 삭제
\*   run 이 진다. Prop_OwnedSetNoop · Prop_ClrNoReject 의 전건은 base 에서도 도달한다(Handoff 무연산 ·
\*   회수). HEAD 의미론(「늘 커밋」 — OwnSetReject 를 Next 에서 뺀 판) 음성은 모델 변이로 쟀다:
\*   증인 NoSetReject 두 판과 거절 분기에 기대는 삭제 다섯이 그 판에서 전부 반례 없이 통과한다.
\*
\* 이 판이 재지 않는 것 (닫힌 목록 — 위 목록에 더한다)
\*   · E.7 7항 읽기 순서 — 모델의 스텝은 원자적이라 전이 기입 *뒤의* 어느 관측도 그 결과를
\*     본다. 이것은 모델의 구조이지 측정이 아니다. 알맹이(읽기는 수락 사이클의 표 스냅숏 ·
\*     전이는 수락 다음 에지부터 보인다)는 사이클 축이라 ownershiptable.sby 의 몫이다.
\*   · 어느 형상이 *언제* 거절하는가 · 거절의 완전성(거절해야 할 때 거절하는가) — 정본이
\*     호스트 계약 밖으로 둔다. 직접 사상 64 칸의 완전성은 ownershiptable.sby 가 잰다.
\*     거절의 정의 자체 —
\*       e-defined.typ:1387 「그 프레임이 장치 소유로 앉을 수 있는 저장 칸이 전부 *다른* 장치 소유 페이지로 차 있는 경우다」
\*     — 는 저장 칸을 가진 형상의 문장이라 "any" 는 그 형상 중립 그림자(하한 울타리 「다른 장치
\*     소유 페이지 ∃」 — set_owned_noop 울타리와 합치면 정본 하한 「하나도 없을 때」 와 동치)만
\*     싣는다. 저장 칸 조건 자체는 대비 "direct" 의 Collide 에만 있다.
\*   · [7] 의 sticky · W1C · 발화 우선 — own7 은 그 스텝의 발화 펄스다.
\*   · sub-word OWN_SET/OWN_CLR 의 거절 + [6] — MmioPage.unaligned_rejected 의 몫이다.
\*
EXTENDS Naturals, FiniteSets

CONSTANTS
    Pages,        \* 소유권 단위 (§3.4.1 1번). 불투명 토큰
    Vaddrs,       \* 가상 주소. 불투명 토큰
    NoMap,        \* 「사상 없음」 표식 (모델 값)
    NoCache,      \* 「지역 사본 없음」 표식 (모델 값)
    NoVal,        \* 「관측값 없음」 표식 (모델 값)
    DisabledGuards,
    SetShape      \* OWN_SET 거절의 형상 — "any"(울타리 안 비결정 · 좋은 모델) | "direct"(HEAD RTL 직접 사상 대비)

AllGuards == {"xlate_local", "flush_on_handoff", "state_machine_kept", "owner_check",
              "entitle_gates_value", "perm_entitle_only", "entitle_first", "own_reported",
              "set_reject_inert", "set_reject_loud", "set_reject_floor", "set_owned_noop",
              "clr_no_reject", "seven_reject_only"}
On(g) == g \notin DisabledGuards

Worlds == {"plain", "rich"}
Agents == {"host", "dev"}
Values == 0..1
Acc == {"r", "w"}             \* 접근 종류 — 권한 비트의 정의역 (x 는 머리 「안 잰다」)
Perms == SUBSET Acc           \* {} = 거부 채움 (V=1 · R = W = X = 0)
FaultBits == {4, 19}          \* FAULT_STATUS 의 승인 거부 보고 비트

\* 이 모델의 전제. 두 세계가 *같지 않아야* 비교가 뜻을 갖는다.
ASSUME Cardinality(Pages) >= 1 /\ Cardinality(Vaddrs) >= 1
ASSUME SetShape \in {"any", "direct"}

VARIABLES
    xlate,     \* [Worlds -> [Vaddrs -> Pages \cup {NoMap}]]  장치 내부 변환표
    perm,      \* [Worlds -> [Vaddrs -> Perms]]               사상의 권한 비트
    owner,     \* [Worlds -> [Pages -> Agents]]               중간 상태 없음
    mem,       \* [Worlds -> [Pages -> Values]]               공유 배후 저장
    cache,     \* [Worlds -> [Agents -> [Pages -> Values \cup {NoCache}]]]
    obsKind,   \* [Worlds -> {"none", "value", "fault"}]      직전 읽기의 성격
    obsVal,    \* [Worlds -> Values \cup {NoVal}]             직전 읽기의 값
    obsOwned,  \* [Worlds -> BOOLEAN]  직전 접근에서 접근한 쪽이 소유자였는가
    obsWho,    \* Agents \cup {"none"} 직전 접근의 접근자 (두 세계 공통 — lockstep)
    obsDec,    \* [Worlds -> {"none", "miss", "grant", "deny"}]  직전 접근의 승인 판정
    obsAcc,    \* Acc \cup {"none"}    직전 접근의 종류 (두 세계 공통 — lockstep)
    obsEnt,    \* [Worlds -> BOOLEAN]  직전 접근을 권한 비트가 허용했는가
    obsFill,   \* [Worlds -> BOOLEAN]  직전 접근이 거부 채움(perm = {}) 사상을 지났는가
    obsBits,   \* [Worlds -> SUBSET FaultBits]  직전 접근이 세운 보고 비트 (발화 펄스)
    ownOp,     \* {"none", "set", "clr"}  직전 스텝의 소유권 전이 기입 (W6 — 두 세계 공통)
    ownRes,    \* {"none", "commit", "noop", "reject"}  그 기입의 처분
    ownPg,     \* Pages \cup {NoMap}  그 기입의 대상 (NoMap = 전이 기입 없음)
    own7       \* [Worlds -> BOOLEAN]  그 스텝의 FAULT_STATUS [7] 발화 펄스

vars == <<xlate, perm, owner, mem, cache, obsKind, obsVal, obsOwned,
          obsWho, obsDec, obsAcc, obsEnt, obsFill, obsBits, ownOp, ownRes, ownPg, own7>>

TypeOK ==
    /\ xlate \in [Worlds -> [Vaddrs -> Pages \cup {NoMap}]]
    /\ perm \in [Worlds -> [Vaddrs -> Perms]]
    /\ owner \in [Worlds -> [Pages -> Agents]]
    /\ mem \in [Worlds -> [Pages -> Values]]
    /\ cache \in [Worlds -> [Agents -> [Pages -> Values \cup {NoCache}]]]
    /\ obsKind \in [Worlds -> {"none", "value", "fault"}]
    /\ obsVal \in [Worlds -> Values \cup {NoVal}]
    /\ obsOwned \in [Worlds -> BOOLEAN]
    /\ obsWho \in Agents \cup {"none"}
    /\ obsDec \in [Worlds -> {"none", "miss", "grant", "deny"}]
    /\ obsAcc \in Acc \cup {"none"}
    /\ obsEnt \in [Worlds -> BOOLEAN]
    /\ obsFill \in [Worlds -> BOOLEAN]
    /\ obsBits \in [Worlds -> SUBSET FaultBits]
    /\ ownOp \in {"none", "set", "clr"}
    /\ ownRes \in {"none", "commit", "noop", "reject"}
    /\ ownPg \in Pages \cup {NoMap}
    /\ own7 \in [Worlds -> BOOLEAN]

(***************************************************************************)
(* 소유권 강제.                                                            *)
(*                                                                         *)
(* state_machine_kept 는 §3.4.1 규범 「일관성이 있어도 규약은 남는다」 를   *)
(* 그대로 옮긴 가드다. 지우면 rich 세계가 상태 기계를 통째로 생략한다 —     *)
(* 즉 *일관성이 있을 때만 성립하는 상태 기계*가 된다. 정본이 금지하는       *)
(* 바로 그 형태이며, 결과는 "없는 플랫폼에서 기능이 줄어드는" 것이 아니라   *)
(* 그 반대다: *있는 플랫폼에서 기능이 늘어난다.* 둘은 같은 종속이다.        *)
(***************************************************************************)
Enforce(w) == /\ On("owner_check")
              /\ (w = "plain" \/ On("state_machine_kept"))

CanAccess(w, a, pg) == owner[w][pg] = a \/ ~Enforce(w)

Mapped(w, va) == xlate[w][va] # NoMap

\* 자격 — 권한 비트가 그 접근 종류를 허용하는가 (사실. 판정 대상은 장치 접근뿐 — 머리).
Entitled(w, va, t) == t \in perm[w][va]

\* 승인 거부의 두 원인 — 사상된 *장치* 접근에서만 뜻이 있다 (호스트는 머리 「안 잰다」).
\* 장치 접근에서 ~CanAccess 는 정확히 ¬devOwned 다 (Enforce 가 켜진 세계).
EntDeny(w, a, va, t) == a = "dev" /\ Mapped(w, va) /\ ~Entitled(w, va, t)
OwnDeny(w, a, va)    == a = "dev" /\ Mapped(w, va) /\ ~CanAccess(w, a, xlate[w][va])

\* 접근이 막히는가 — 세 발화 조건: 미사상 · 자격 거부(장치) · 비소유.
\* 자격 항은 entitle_gates_value (RTL granted 의 entitle 항), 비소유 항은 owner_check.
AccFault(w, a, va, t) ==
    \/ ~Mapped(w, va)
    \/ (On("entitle_gates_value") /\ EntDeny(w, a, va, t))
    \/ ~CanAccess(w, a, xlate[w][va])

\* 장치의 보고 — 가드 의존. W1 전 RTL(HEAD 3b80087) = perm_entitle_only · own_reported 를 지운 판.
Bit4(w, a, va, t) ==
    IF On("perm_entitle_only") THEN EntDeny(w, a, va, t)
    ELSE EntDeny(w, a, va, t) \/ OwnDeny(w, a, va)
Bit19(w, a, va, t) ==
    /\ On("own_reported")
    /\ OwnDeny(w, a, va)
    /\ (On("entitle_first") => ~EntDeny(w, a, va, t))
Bits(w, a, va, t) ==
    (IF Bit4(w, a, va, t) THEN {4} ELSE {}) \cup (IF Bit19(w, a, va, t) THEN {19} ELSE {})

\* 접근 하나의 보고 관측 — 접근자 · 승인 판정 · 원인 사실(자격 · 소유 · 거부 채움) · 장치가
\* 세운 비트. 원인 사실은 접근자와 무관한 사실로 적고, 속성이 obsWho = "dev" 로 한정한다.
\* 미사상은 원인 축과 무관하다 (obsEnt · obsOwned = TRUE, obsFill = FALSE, obsDec = miss).
Observe(a, va, t) ==
    /\ obsWho'   = a
    /\ obsDec'   = [w \in Worlds |-> IF ~Mapped(w, va) THEN "miss"
                                     ELSE IF AccFault(w, a, va, t) THEN "deny"
                                     ELSE "grant"]
    /\ obsAcc'   = t
    /\ obsEnt'   = [w \in Worlds |-> ~Mapped(w, va) \/ Entitled(w, va, t)]
    /\ obsOwned' = [w \in Worlds |-> ~Mapped(w, va) \/ owner[w][xlate[w][va]] = a]
    /\ obsFill'  = [w \in Worlds |-> Mapped(w, va) /\ perm[w][va] = {}]
    /\ obsBits'  = [w \in Worlds |-> Bits(w, a, va, t)]

\* 관측을 소비한다 — 남겨 두면 후속 단계에서 낡은 관측이 속성을 다시 걸어
\* 거짓 반례를 만든다 (XlateStore 모델에서 실측한 실패형).
ClearObs ==
    /\ obsKind'  = [w \in Worlds |-> "none"]
    /\ obsVal'   = [w \in Worlds |-> NoVal]
    /\ obsOwned' = [w \in Worlds |-> TRUE]
    /\ obsWho'   = "none"
    /\ obsDec'   = [w \in Worlds |-> "none"]
    /\ obsAcc'   = "none"
    /\ obsEnt'   = [w \in Worlds |-> TRUE]
    /\ obsFill'  = [w \in Worlds |-> FALSE]
    /\ obsBits'  = [w \in Worlds |-> {}]

\* 소유권 전이 기입이 없는 스텝 — 전이 관측 펄스를 내린다 (W6).
OwnIdle ==
    /\ ownOp' = "none" /\ ownRes' = "none" /\ ownPg' = NoMap
    /\ own7' = [w \in Worlds |-> FALSE]

Init ==
    /\ xlate = [w \in Worlds |-> [va \in Vaddrs |-> NoMap]]
    /\ perm = [w \in Worlds |-> [va \in Vaddrs |-> {}]]
    /\ owner = [w \in Worlds |-> [pg \in Pages |-> "host"]]
    /\ mem = [w \in Worlds |-> [pg \in Pages |-> 0]]
    /\ cache = [w \in Worlds |-> [a \in Agents |-> [pg \in Pages |-> NoCache]]]
    /\ obsKind = [w \in Worlds |-> "none"]
    /\ obsVal = [w \in Worlds |-> NoVal]
    /\ obsOwned = [w \in Worlds |-> TRUE]
    /\ obsWho = "none"
    /\ obsDec = [w \in Worlds |-> "none"]
    /\ obsAcc = "none"
    /\ obsEnt = [w \in Worlds |-> TRUE]
    /\ obsFill = [w \in Worlds |-> FALSE]
    /\ obsBits = [w \in Worlds |-> {}]
    /\ ownOp = "none" /\ ownRes = "none" /\ ownPg = NoMap
    /\ own7 = [w \in Worlds |-> FALSE]

(***************************************************************************)
(* 변환 항목 기입 — 호스트가 구성 표면으로 기입한다 (§3.3).                *)
(* 두 세계에 **같이** 들어간다. 이것이 정상 경로다.                        *)
(* 권한 비트 ps 가 {} 이면 거부 채움이다 (회수 · 부팅에서 호스트가 쓴다).  *)
(***************************************************************************)
MapVa(va, pg, ps) ==
    /\ xlate' = [w \in Worlds |-> [xlate[w] EXCEPT ![va] = pg]]
    /\ perm' = [w \in Worlds |-> [perm[w] EXCEPT ![va] = ps]]
    /\ ClearObs /\ OwnIdle
    /\ UNCHANGED <<owner, mem, cache>>

(***************************************************************************)
(* 호스트 변환 서비스로 미사상을 채운다 — **rich 세계에서만 가능하다.**    *)
(*                                                                         *)
(* §3.3.1 이 기각한 대안이 정확히 이것이다. 가드 xlate_local 이 켜져 있으면 *)
(* 이 동작은 아예 열리지 않는다. 지우면 rich 세계의 변환표가 plain 보다     *)
(* 커지고 — 그 순간 "PE 가 보는 주소 공간" 이 호스트에 따라 달라진다.      *)
(***************************************************************************)
HostFill(va, pg, ps) ==
    /\ ~On("xlate_local")
    /\ xlate["rich"][va] = NoMap
    /\ xlate' = [xlate EXCEPT !["rich"] = [@ EXCEPT ![va] = pg]]
    /\ perm' = [perm EXCEPT !["rich"] = [@ EXCEPT ![va] = ps]]
    /\ ClearObs /\ OwnIdle
    /\ UNCHANGED <<owner, mem, cache>>

(***************************************************************************)
(* 기입.                                                                   *)
(*                                                                         *)
(* rich 세계의 일관 상호연결을 **write-through** 로 추상한다 — 기입이       *)
(* 즉시 배후 저장에 보인다. plain 세계는 지역 사본에만 남는다.             *)
(* 이 비대칭이 이 모델에서 "일관성" 이 뜻하는 것의 전부다.                 *)
(* 기입도 승인을 지나므로 보고 비트를 세운다 — 값 관측(obsKind)은 없다.   *)
(***************************************************************************)
Write(a, va, v) ==
    /\ cache' = [w \in Worlds |->
                   IF AccFault(w, a, va, "w") THEN cache[w]
                   ELSE [cache[w] EXCEPT ![a] =
                           [@ EXCEPT ![xlate[w][va]] = v]]]
    /\ mem' = [w \in Worlds |->
                 IF w = "rich" /\ ~AccFault(w, a, va, "w")
                   THEN [mem[w] EXCEPT ![xlate[w][va]] = v]
                   ELSE mem[w]]
    /\ obsKind' = [w \in Worlds |-> "none"]
    /\ obsVal'  = [w \in Worlds |-> NoVal]
    /\ Observe(a, va, "w")
    /\ OwnIdle
    /\ UNCHANGED <<xlate, perm, owner>>

(***************************************************************************)
(* 읽기 — 유일한 값 관측점.                                                *)
(***************************************************************************)
Read(a, va) ==
    /\ obsKind' = [w \in Worlds |->
                     IF AccFault(w, a, va, "r") THEN "fault" ELSE "value"]
    /\ obsVal' = [w \in Worlds |->
                    IF AccFault(w, a, va, "r") THEN NoVal
                    ELSE IF cache[w][a][xlate[w][va]] # NoCache
                           THEN cache[w][a][xlate[w][va]]
                           ELSE mem[w][xlate[w][va]]]
    /\ Observe(a, va, "r")
    /\ OwnIdle
    /\ UNCHANGED <<xlate, perm, owner, mem, cache>>

\* 대비 SetShape = "direct" 의 칸 — 페이지 하나만 혼자, 나머지는 한 칸을 나눈다 (같은 색인 · 다른 태그).
SoloPg == CHOOSE p \in Pages : TRUE
Slot(pg) == IF pg = SoloPg THEN 1 ELSE 0
Collide(pg) == \E q \in Pages \ {pg} : owner["plain"][q] = "dev" /\ Slot(q) = Slot(pg)

(***************************************************************************)
(* 소유권 이양 — 구성 표면의 명시적 쓰기로만 (§3.4.1 2번). 암묵 전이 없음. *)
(*                                                                         *)
(* §3.4.1 3번: *넘기는 쪽이 비운다.* plain 세계에서 그 비우기가 지역 사본을 *)
(* 배후 저장으로 밀어낸다. rich 세계는 write-through 라 이미 밀려 있으므로  *)
(* 비우기가 *생략된다* — 정본이 "비우기 의무(3번)만 생략할 수 있다" 고      *)
(* 적은 그대로다. 두 세계의 결과가 같아지는 것은 이 대칭 덕분이다.         *)
(*                                                                         *)
(* flush_on_handoff 를 지우면 plain 세계만 낡은 값을 들고 남는다.          *)
(***************************************************************************)
Handoff(frm, to, pg) ==
    /\ frm # to
    /\ ~(to = "dev" /\ SetShape = "direct" /\ Collide(pg))   \* 직접 사상 대비: 충돌 이양은 커밋할 수 없다
    /\ owner' = [w \in Worlds |->
                   IF owner[w][pg] = frm THEN [owner[w] EXCEPT ![pg] = to]
                   ELSE owner[w]]
    /\ mem' = [w \in Worlds |->
                 IF /\ owner[w][pg] = frm
                    /\ w = "plain"
                    /\ On("flush_on_handoff")
                    /\ cache[w][frm][pg] # NoCache
                   THEN [mem[w] EXCEPT ![pg] = cache[w][frm][pg]]
                   ELSE mem[w]]
    /\ cache' = [w \in Worlds |->
                   IF owner[w][pg] = frm
                     THEN [cache[w] EXCEPT ![frm] = [@ EXCEPT ![pg] = NoCache]]
                     ELSE cache[w]]
    /\ ClearObs
    /\ ownOp' = (IF to = "dev" THEN "set" ELSE "clr")
    /\ ownRes' = (IF owner["plain"][pg] = frm THEN "commit" ELSE "noop")
    /\ ownPg' = pg
    \* seven_reject_only — [7] 은 거절에서만. 지운 판: 커밋된 OWN_SET 이 [7] 을 세운다.
    /\ own7' = [w \in Worlds |-> ~On("seven_reject_only") /\ to = "dev" /\ owner[w][pg] = frm]
    /\ UNCHANGED <<xlate, perm>>

(***************************************************************************)
(* OWN_SET 의 거절 (W6 — 머리 「OWN_SET 의 거절」). 형상 중립 비결정 분기.  *)
(* 두 세계에 같이 든다 (lockstep — 거절은 장치의 성질이지 플랫폼의 성질이  *)
(* 아니다).                                                                *)
(***************************************************************************)

\* 거절이 허락되는 울타리 — 가드 의존. "direct" 는 정확히 충돌일 때만.
SetRejectable(pg) ==
    /\ (SetShape = "direct" => Collide(pg))
    /\ (On("set_owned_noop") => owner["plain"][pg] # "dev")
    /\ (On("set_reject_floor") => \E q \in Pages \ {pg} : owner["plain"][q] = "dev")

\* set_reject_inert 를 지운 판 — 직접 사상 덮어쓰기: 대상을 앉히고 다른 장치 소유 페이지를 축출한다.
Overwrite(w, pg) == [p \in Pages |-> IF p = pg THEN "dev" ELSE "host"]

OwnSetReject(pg) ==
    /\ SetRejectable(pg)
    /\ owner' = IF On("set_reject_inert") THEN owner
                ELSE [w \in Worlds |-> Overwrite(w, pg)]
    /\ ownOp' = "set" /\ ownRes' = "reject" /\ ownPg' = pg
    /\ own7' = [w \in Worlds |-> On("set_reject_loud")]
    /\ ClearObs
    /\ UNCHANGED <<xlate, perm, mem, cache>>

\* clr_no_reject 를 지운 판에만 열린다 — OWN_CLR 이 거절 + [7].
OwnClrReject(pg) ==
    /\ ~On("clr_no_reject")
    /\ ownOp' = "clr" /\ ownRes' = "reject" /\ ownPg' = pg
    /\ own7' = [w \in Worlds |-> TRUE]
    /\ ClearObs
    /\ UNCHANGED <<xlate, perm, owner, mem, cache>>

Next ==
    \/ \E va \in Vaddrs, pg \in Pages, ps \in Perms : MapVa(va, pg, ps)
    \/ \E va \in Vaddrs, pg \in Pages, ps \in Perms : HostFill(va, pg, ps)
    \/ \E a \in Agents, va \in Vaddrs, v \in Values : Write(a, va, v)
    \/ \E a \in Agents, va \in Vaddrs : Read(a, va)
    \/ \E frm, to \in Agents, pg \in Pages : Handoff(frm, to, pg)
    \/ \E pg \in Pages : OwnSetReject(pg)
    \/ \E pg \in Pages : OwnClrReject(pg)

Spec == Init /\ [][Next]_vars

(***************************************************************************)
(* 불변식 — 처음 넷은 **두 세계의 비교**다.                                *)
(***************************************************************************)

\* HIU-8 — 변환 결과(프레임 · 권한 비트)가 호스트 변환 서비스의 가용 여부에 의존하지 않는다.
Inv_SameTranslation ==
    \A va \in Vaddrs : /\ xlate["plain"][va] = xlate["rich"][va]
                       /\ perm["plain"][va] = perm["rich"][va]

\* HIU-9 (값 축) — 소유권 규약을 지킨 접근열의 관측값이 같다.
Inv_SameObservation ==
    (obsKind["plain"] = "value" /\ obsKind["rich"] = "value")
        => obsVal["plain"] = obsVal["rich"]

\* HIU-9 (정책 축) — 두 세계가 *같은 접근에서 fault 한다.*
\* §3.4.1 규범: 선택적 경로가 정상 경로의 전제가 되면 안 된다. 뒤집어 말하면
\* 선택적 경로가 있다고 해서 *허용 범위가 넓어져서도 안 된다.*
Inv_SameFaultPolicy == obsKind["plain"] = obsKind["rich"]

\* HIU-10 — 값을 돌려받았다면 읽은 쪽이 소유자였다. 조용한 낡은 값 금지.
Inv_UnownedFaults ==
    \A w \in Worlds : obsKind[w] = "value" => obsOwned[w]

(***************************************************************************)
(* 승인 거부의 보고 비트 — 원인별 보고 (머리 「승인 거부의 보고 비트」).   *)
(***************************************************************************)

\* 원인 → 기대 비트. 자격이 먼저다. 보고 축은 장치 접근 한정 — 호스트 접근은 {}.
ExpectedBits(w) ==
    IF obsWho # "dev" THEN {}
    ELSE IF ~obsEnt[w] THEN {4}
    ELSE IF ~obsOwned[w] THEN {19}
    ELSE {}

\* 원인별 보고 — 보고 비트는 원인의 정확 등식이다. 「오늘의 RTL」(W1 전 RTL — HEAD 3b80087) 짝이 깬다.
Inv_ReportBitByCause == \A w \in Worlds : obsBits[w] = ExpectedBits(w)

\* 한 접근에 둘이 함께 서지 않는다 (entitle_first).
Inv_OneBitPerAccess == \A w \in Worlds : obsBits[w] # FaultBits

\* [4] 는 자격 거부에서만 선다 (perm_entitle_only).
Inv_Bit4EntOnly == \A w \in Worlds : 4 \in obsBits[w] => ~obsEnt[w]

\* HIU-10 의 보고 짝 — 비소유 장치 접근이면 [4] 와 [19] 중 하나는 선다 (own_reported).
Inv_UnownedLoud ==
    \A w \in Worlds : (obsWho = "dev" /\ ~obsOwned[w]) => obsBits[w] # {}

\* 거부 채움을 지난 장치 접근은 프레임 소유와 무관하게 [4] 만 (entitle_first 의 거부 채움 축).
Inv_DenyFillIs4 == \A w \in Worlds : (obsWho = "dev" /\ obsFill[w]) => obsBits[w] = {4}

\* 자격 거부 장치 접근은 승인 거부다 — 값 차단 · 쓰기 미반영 (entitle_gates_value).
\* Inv_UnownedFaults 의 자격 쪽 짝 (e-defined.typ:527 「값 차단 · 승인 거부 · 상태열」).
Inv_EntDeniedBlocked ==
    \A w \in Worlds : (obsWho = "dev" /\ ~obsEnt[w]) => obsDec[w] = "deny"

\* 「갈리는 것은 보고 비트뿐이다」 — 사상된 장치 접근은 승인 거부일 때 정확히 보고 비트가 선다.
Inv_DenyIffReported ==
    \A w \in Worlds : (obsWho = "dev" /\ obsDec[w] # "miss" /\ obsDec[w] # "none")
                        => (obsDec[w] = "deny" <=> obsBits[w] # {})

(***************************************************************************)
(* OWN_SET 의 거절 — 가드 속성 여섯 + 고정 속성 (W6 — 머리).              *)
(***************************************************************************)

\* set_reject_inert — 거절은 무효과 (소유 · 배후 저장 · 사본 그대로 — 축출 없음).
Prop_SetRejectInert ==
    [][ ownRes' = "reject" => (owner' = owner /\ mem' = mem /\ cache' = cache) ]_vars
\* set_reject_loud — 거절은 [7] 을 세운다.
Prop_SetRejectLoud == [][ ownRes' = "reject" => \A w \in Worlds : own7'[w] ]_vars
\* set_reject_floor — 하한: 다른 장치 소유 페이지가 없으면 거절이 없다.
Prop_SetRejectFloor ==
    [][ (ownOp' = "set" /\ ownRes' = "reject")
          => \E q \in Pages \ {ownPg'} : owner["plain"][q] = "dev" ]_vars
\* set_owned_noop — 이미 장치 소유인 페이지의 OWN_SET 은 무연산이다 (거절이 아니다).
Prop_OwnedSetNoop ==
    [][ (ownOp' = "set" /\ owner["plain"][ownPg'] = "dev") => ownRes' = "noop" ]_vars
\* clr_no_reject — OWN_CLR 은 거절되지 않는다.
Prop_ClrNoReject == [][ ownOp' = "clr" => ownRes' # "reject" ]_vars
\* seven_reject_only — [7] 은 거절에서만 선다 (상승 건전성).
Prop_SevenRejectOnly == [][ (\E w \in Worlds : own7'[w]) => ownRes' = "reject" ]_vars

\* 고정 — 소유가 바뀌는 페이지는 그 스텝의 커밋된 전이 기입의 대상 하나뿐 (축출 · 암묵 전이 없음).
Prop_NoImplicitTransition ==
    [][ \A w \in Worlds, p \in Pages :
          owner'[w][p] # owner[w][p] => (ownRes' = "commit" /\ p = ownPg') ]_vars

\* 대비 "direct" — 한 칸에 장치 소유 페이지는 하나 (직접 사상의 저장 실물).
Inv_SlotExclusive ==
    \A p, q \in Pages : (p # q /\ owner["plain"][p] = "dev" /\ owner["plain"][q] = "dev")
                          => Slot(p) # Slot(q)

(***************************************************************************)
(* 위험 도달성 증인 — 좋은 모델에서 반드시 반증돼야 한다.                  *)
(***************************************************************************)

\* 값 읽기가 실제로 일어나는가 — 안 일어나면 위 전부가 공허하다.
Witness_NoValueRead == obsKind["plain"] # "value"

\* fault 가 실제로 일어나는가.
Witness_NoFault == obsKind["plain"] # "fault"

\* 소유권이 실제로 이양되는가 — 안 되면 flush 가드가 공허하다.
Witness_NoHandoff == \A pg \in Pages : owner["plain"][pg] = "host"

\* **지역 사본이 배후 저장과 실제로 어긋나는가.**
\* 이것이 반증되지 않으면 plain 세계에 「낡은 값」 이라는 위험 자체가 없고,
\* flush_on_handoff 가드는 아무것도 막지 않는다. XlateStore 의
\* Witness_DataSurvivesFlush 와 같은 자리의 증인이다.
Witness_NoDivergentCache ==
    \A a \in Agents, pg \in Pages :
        cache["plain"][a][pg] = NoCache \/ cache["plain"][a][pg] = mem["plain"][pg]

\* 두 세계의 배후 저장이 실제로 어긋나는 순간이 있는가.
\* 없으면 rich/plain 구분이 이름뿐이고 비교가 자명해진다.
Witness_NoMemSkew ==
    \A pg \in Pages : mem["plain"][pg] = mem["rich"][pg]

\* [4] 가 실제로 서는가 — 안 서면 perm_entitle_only · entitle_gates_value 가 공허하다.
\* (보고 비트는 장치 접근만 세우므로 반례는 장치 접근이다.)
Witness_NoEntDeny == 4 \notin obsBits["plain"]

\* [19] 가 실제로 서는가 — 안 서면 own_reported 가 공허하다.
Witness_NoOwnDeny == 19 \notin obsBits["plain"]

\* 두 원인이 한 접근에 겹치는가 (자격 거부 ∧ 비소유) — 안 겹치면 entitle_first 의
\* 우선순위가 가를 입력이 없어 공허하다.
Witness_NoBothCauses == ~(obsWho = "dev" /\ ~obsEnt["plain"] /\ ~obsOwned["plain"])

\* 거부 채움이 *장치 소유* 프레임 위의 장치 접근에서 일어나는가 — 「프레임이 무엇이든 [4]」
\* 의 소유 쪽 절반 (이양을 지나야 도달한다). 비소유 쪽 절반은 entitle_first 거부 채움 삭제
\* run 의 반례가 보인다.
Witness_NoDenyFillOwned == ~(obsWho = "dev" /\ obsFill["plain"] /\ obsOwned["plain"])

\* W6 — OWN_SET 거절이 실재하는가 (안 일어나면 거절 가드 넷이 공허하다).
Witness_NoSetReject == ownRes # "reject"
\* 이미 장치 소유인 페이지의 OWN_SET(무연산)이 실재하는가 — set_owned_noop 의 입력.
Witness_NoOwnedSetNoop == ~(ownOp = "set" /\ ownRes = "noop")
\* OWN_CLR 의 회수 커밋이 실재하는가 — clr_no_reject 의 입력이 무연산뿐이 아님.
Witness_NoClrCommit == ~(ownOp = "clr" /\ ownRes = "commit")
\* 장치 소유 페이지 둘이 공존하는가 — 대비 "direct" 에서 비충돌 커밋이 점유 중에도 일어남.
Witness_NoCoOwned == Cardinality({p \in Pages : owner["plain"][p] = "dev"}) <= 1

=============================================================================
