\* SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
\* SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
--------------------------- MODULE AbortSurface -----------------------------
(***************************************************************************)
(* 재조립 문맥 소거의 호스트 쪽 문 — `0xF40` 구역(ABORT_TAG0/1/2 스테이징 · *)
(* ABORT_FIRE 발화 · RO 세 워드)과 무장 규율(E.12.1)의 선-formal 모델.      *)
(* 파도 4 (2026-09-26).                                                    *)
(*                                                                         *)
(* ## 왜 이제 있는가 — 1단을 건너뛴 모듈이었다                            *)
(*                                                                         *)
(* AbortStaging(2026-08-25 결정 A)은 선-formal 없이 RTL 과 후-formal 로     *)
(* 착지했다 — 그 .sby 머리가 「PROVES 가 아니라 VERIFIES 인 이유」로 자백한 *)
(* 그대로다: Payload.tla 는 소거를 「태그 하나를 지정한 소거 기입」이라는   *)
(* *의미론*으로 추상하고, 그 태그를 32b 버스 세 워드에 싣는 문은 어느 모델의 *)
(* 상태도 아니었다. 정본 6.3 은 「1단을 건너뛴 모듈은 완료로 간주하지      *)
(* 않는다」고 적는다. 이 모델이 그 1단이다 — XlateSurface.tla 가 변환 저장소 *)
(* 에 대해 한 것을 소거 표면에 한다.                                        *)
(*                                                                         *)
(* ## 분업                                                                 *)
(*                                                                         *)
(*   Payload.tla       재조립 문맥 — 소거가 무엇을 지우는가(창·회계), 없는  *)
(*                     태그의 소거는 무시, 소거는 fault 가 아니다.          *)
(*   AbortSurface.tla  호스트가 두드리는 *문* — 세 워드 스테이징, 워드별    *)
(*                     무장, 발화의 성립, 잔류 소진, 워드 적법성의 거절과   *)
(*                     그 처분. 발화가 *어느 태그*를 싣는가까지가 이 모델이고 *)
(*                     그 태그가 어느 문맥에 닿는가는 Payload 다.           *)
(*                                                                         *)
(* 정본 (좌표 뒤 「」 는 그 줄의 축자 — lint_section_refs 축 1 이 대조한다): *)
(*   e-defined.typ:473 「수락된 기입이 무장 비트 `[0]` 을 세운다」 — ABORT_TAG0. *)
(*   e-defined.typ:475 「`[27]` poison = 0 · `[26]` trace = 0 · `[25:16]` 예약 = 0 (엄격)」 *)
(*   e-defined.typ:475 「처분은 셋 다 같다: 거절 + loud fault」 — ABORT_TAG1. *)
(*   e-defined.typ:477 「`[31:16]` 예약 = 0 (엄격). 스테이징 · 무장 비트 `[2]`」 *)
(*   e-defined.typ:479 「`[0]` 에 1 기입 = 소거 발화 · `[31:1]` 예약 = 0 (엄격)」 *)
(*   e-defined.typ:479 「발화 기입은 성립 여부와 무관하게 무장 셋을 전부 내린다」 *)
(*   e-defined.typ:481 「*성립한 소거만* 센다」 — ABORT_COUNT.              *)
(*   e-defined.typ:485 「`[2:0]` 무장 마스크」 — ABORT_ARM (RO).            *)
(*   e-defined.typ:202 「*RO 오프셋의 쓰기* — 거절 + loud fault 다」        *)
(*   e-defined.typ:1727 「*소거 대상 매칭의 키에서 poison 과 trace 는 빠진다.*」 *)
(*   e-defined.typ:1728 「그 두 비트는 반드시 0 이며」 — E.12 6항.         *)
(*   e-defined.typ:1799 「*수락된* 기입은 각각 자기 무장 비트를 세운다」     *)
(*   e-defined.typ:1800 「값을 덮되 비트는 선 채다」 — 재기입의 처분.      *)
(*   e-defined.typ:1800 「*거절된 기입은 무장을 세우지 않는다*」            *)
(*   e-defined.typ:1801 「예약 비0 · sub-word · RO 방향 위반은 이미 거절 + loud fault 이고」 *)
(*   e-defined.typ:1802 「효과 없는 기입이 승인만 남기면 그것이 곧 부분 기입의」 *)
(*   e-defined.typ:1804 「`0xF4C` ABORT_FIRE 기입은 무장 비트 셋이 *모두 선*」 — 2항. *)
(*   e-defined.typ:1805 「무장 미완 발화는 *무시*이며 오류가 아니다」        *)
(*   e-defined.typ:1808 「ABORT_FIRE 기입은 소거의 성립 여부와 무관하게 세 무장」 — 3항. *)
(*   e-defined.typ:1811 「*구조적으로 존재하지 않는다.*」 — stale staging.  *)
(*   e-defined.typ:1816 「*무장은 태그 값을 검사하지 않는다*」 — 5항.       *)
(*   e-defined.typ:1818 「*워드의 적법성 검사는 무장보다 앞선다*」          *)
(*   e-defined.typ:1819 「poison·trace 비0 · sub-word · RO 방향 위반은 기입 자체가 거절되고」 *)
(*   03-hiu.typ:747 「*sub-word 쓰기는 수락하지 않는다* — *거절 + loud」     *)
(*   03-hiu.typ:753 「발화 전에 부분 기입이 무효과여야 하는 *스테이징 세 워드*를」 *)
(*   05-security.typ:371 「조용한 실패는 편의 문제가 아니라 *보안 문제*다.」 *)
(*                                                                         *)
(* ## 이 모델이 잡는 정확한 결함 — D2 (rtl/README.md)                      *)
(*                                                                         *)
(* 파도 4 착지 이전의 AbortStaging 은 ABORT_TAG1 에 검사가 없었다(okTag1 =  *)
(* wr ∧ selTag1). 정본 TAG1 재배분(fa18169)이 `[27:16]` 을 poison · trace · *)
(* 예약 엄격으로 갈랐는데 RTL 로 전파되지 않았다 — trace 가 선 TAG1 이      *)
(* 조용히 스테이징되고 무장했고, 발화가 trace 를 든 태그를 실었다. 짝 run   *)
(* 둘이 그 기계와 동형이다 (poison_trace_zero · epoch_word_rsv_strict 삭제):        *)
(*   Prop_PoisonTraceRejected 반례  — 거절 사유인 기입이 수락된다.             *)
(*   Prop_FiredKeyClean 반례    — 소거가 trace 를 든 키를 싣는다 (E.12 6항 *)
(*                                의 호스트 가시 귀결).                    *)
(* 그리고 후-formal 에 있던 구멍 하나(검토자 V13): 「수락된 기입이 자기 무장 *)
(* 을 세운다」의 *양의 방향*을 단언이 아니라 증인만 쟀다 — TAG1 이 무장을    *)
(* 안 세우는 변이가 bmc·prove 를 통과했다. arm_on_accept 가 그 문장이고     *)
(* 삭제 run 이 Prop_ArmOnAccept 로 운다.                                   *)
(*                                                                         *)
(* ## 가드 — 각각 정본 한 문장. 삭제 run(run.sh)은 자기 속성이 첫 위반으로 *)
(*    난다. 「자기 속성*만*」 은 분리 검사가 잰다 — 비상주, 2026-09-26 실측  *)
(*    13/13 (가드마다 지운 판에 나머지 가드 속성 열둘 · rtl/formal/tla/README) *)
(*                                                                         *)
(*   이름: TAG1 = 에포크 워드(epoch_word — `[31:28]` 에포크 ‖ `[15:0]` LNID), *)
(*   TAG2 = 형상 워드(shape_word — precision ‖ dim). 가드 이름에 숫자를 쓰지 *)
(*   않는다 — lint_guard_map · lint_postformal 의 가드 정규식이 `[A-Za-z_]+` *)
(*   라 `tag1_…` 은 AllGuards · GUARD-MAP · PROVES 어디서도 *조용히* 읽히지   *)
(*   않는다(착지 중 실측 — 셋이 전수 계수에서 빠진 채 OK 가 인쇄됐다).        *)
(*                                                                         *)
(*   워드 적법성 (감지) — 「거절 사유인가」를 장치가 알아보는가              *)
(*   poison_trace_zero     :475 · :1727 TAG1 `[27]` poison · `[26]` trace 비0 은 *)
(*                      거절. 지우면 그 기입이 수락된다 — 소거 키에 trace 가 *)
(*                      든다(D2 이전 RTL). → Prop_PoisonTraceRejected          *)
(*   epoch_word_rsv_strict    :475 TAG1 `[25:16]` 예약 비0 은 거절. → Prop_EpochWordRsvRejected *)
(*   shape_word_rsv_strict    :477 TAG2 `[31:16]` 예약 비0 은 거절. → Prop_ShapeWordRsvRejected *)
(*   fire_rsv_strict    :479 FIRE `[31:1]` 예약 비0 은 거절. → Prop_FireRsvRejected *)
(*   ro_rejected        :202 · :1801 RO 세 워드(`0xF50` · `0xF54` · `0xF58`)의 *)
(*                      쓰기는 거절. 지우면 흡수된다. → Prop_RoRejected     *)
(*   거절의 처분                                                          *)
(*   legal_first        :1818 · :1800 적법성 검사는 무장보다 앞선다 — 거절된 *)
(*                      기입은 스테이징도 무장도 소진도 발화도 움직이지     *)
(*                      않는다. 지우면 loud 이지만 효과가 있는 기입(「거절 *)
(*                      했다면서 무장했다」 — 후-formal V7 과 동형).        *)
(*                      → Prop_RejectedNoEffect                            *)
(*   reject_loud        :475 · 5.6 거절은 전부 FAULT_STATUS `[6]`. 지우면   *)
(*                      조용한 거절. → Prop_RejectLoud                     *)
(*   무장                                                                 *)
(*   arm_on_accept      :1799 수락된 스테이징 기입은 자기 무장 비트를 세운다. *)
(*                      지우면 적법한 호스트 시퀀스가 영영 발화하지 못한다 *)
(*                      (V13). → Prop_ArmOnAccept                          *)
(*   arm_own_word       :1799 「각각 자기」 — 무장 비트의 상승 원천은 자기   *)
(*                      워드의 기입뿐. 지우면 한 워드의 기입이 이웃 워드의 *)
(*                      무장을 세운다 — 쓰지 않은 워드가 발화에 실린다.    *)
(*                      → Prop_ArmOwnWord                                  *)
(*   stage_writes_value :1800 재기입은 값을 덮는다. 지우면 무장이 선 워드의  *)
(*                      재기입이 옛 값을 남긴다 — 호스트가 고친 태그가 아니라 *)
(*                      처음 쓴 태그가 실린다. → Prop_StageLatest          *)
(*   발화                                                                 *)
(*   fire_needs_armed   :1804 무장 셋이 모두 선 상태에서만 소거. 지우면 부분 *)
(*                      기입의 발화. → Prop_FireNeedsArmed                 *)
(*   fire_needs_one     :479 `[0]` 에 1 기입만 발화다. 지우면 `[0]`=0 의 적법 *)
(*                      기입이 소거를 일으킨다. → Prop_FireNeedsOne        *)
(*   fire_drains_arm    :479 · :1808 수락된 발화 기입은 성립 여부와 무관하게 *)
(*                      무장 셋을 전부 내린다. 지우면 「성립한 소거만 무장을 *)
(*                      내린다」가 된다 — 무시된 발화가 무장을 남기고, 빠진 *)
(*                      워드 하나만 다시 쓴 발화가 직전 시도의 잔재를 싣는다 *)
(*                      (stale staging). → Prop_FireDrains                 *)
(*                                                                         *)
(* 고정 의미의 속성(가드 아님 — 좋은 모델 cfg 가 건다):                    *)
(*   Prop_NoPartialFire    소거에 실리는 세 워드는 전부 직전 발화 기입 *뒤*에 *)
(*                         수락된 기입이다 — 부분 기입(2항)도 stale staging *)
(*                         (3항 「구조적으로 존재하지 않는다」)도 아니다.   *)
(*   Prop_FireTagLatest    실리는 값은 워드마다 마지막 수락 기입의 값이다.  *)
(*   Prop_FiredKeyClean    실리는 태그에 poison · trace · 예약이 없다(E.12 6항). *)
(*   Prop_MalformedRejected 거절 사유인 기입은 전부 거절된다 — sub-word 포함. *)
(*   Prop_RejectOnlyMalformed 적법한 기입은 거절되지 않는다 — 무장 미완    *)
(*                         발화는 거절이 아니라 무시다 (2항).              *)
(*   Prop_LoudOnlyOnReject  [6] 은 거절에서만.                             *)
(*   Prop_UnderarmedIgnored 무장 미완의 적법 발화는 fault 도 소거도 없다.   *)
(*   Prop_StagingNoFire    스테이징 워드 기입만으로는 소거가 없다 (03-hiu 3.7 *)
(*                         「발화 전에 부분 기입이 무효과」).               *)
(*   Prop_ArmFallsOnlyOnFire 무장의 하강 원천은 수락된 발화 기입뿐이다 — 스테이징 *)
(*                         기입(자기 · 이웃 워드)도 거절된 기입도 무장을 내리지 *)
(*                         않는다 (아래 「닫지 않은 자리」 4). 가드 속성 어느 것도 *)
(*                         이것을 말하지 않았다: 재기입이 이웃 워드의 무장을 *)
(*                         내리는 장치가 속성 스물하나를 전부 통과했다(검토 탐침 *)
(*                         2026-09-26 — 발화는 여전히 도달, 공허 아님). 후-formal *)
(*                         짝은 t_arm_fall 이다.                            *)
(* 앞의 셋은 명세측 그림자(fresh · last — 장치 판정과 무관하게 「정본이     *)
(* 적법하다고 보는 기입」의 이력)로 적는다. 장치가 스스로 수락했다고 보는  *)
(* 것을 속성이 믿으면 가드 삭제가 속성까지 함께 지운다.                    *)
(*                                                                         *)
(* ## 설계 결정 — sub-word 쓰기의 처분 (상수 Subword)                      *)
(*                                                                         *)
(* E.12.1 1·5항과 03-hiu.typ:747 「*sub-word 쓰기는 수락하지 않는다*」 가  *)
(* sub-word 를 거절 + loud 로 적는다. 장치 포트에는 바이트 인에이블이 없고 *)
(* 주소 하위 두 비트가 남는다 — 그 비트가                                 *)
(* 0 이 아닌 쓰기가 sub-word 의 장치 포트 표현인가는 정본 판정 요청 T2 였고 *)
(* 파도 4 가 (a) 「그렇다 — 페이지 전역에서 거절 + [6]」 로 판정했다. 그     *)
(* RTL 은 파도 4 페이지 통합이 착지했다 (pageArea.unalWr — 페이지 전역 한 식). *)
(* 이 축은 가드가 아니라 상수로 남는다 (아래 끝 두 줄이 그 이유다):      *)
(*   "reject"  거절 + loud. 좋은 모델 — 판정 T2 (a).                        *)
(*   "ignore"  조용한 흡수. **T2 앞의 RTL** — abortArea.wr 이 mmioAligned 를 *)
(*             요구해 비정렬 쓰기는 AbortStaging 에 닿지 않고 fault 도 없다. *)
(*             → Prop_MalformedRejected 반례 (짝 run). 가드 속성 열셋은    *)
(*             이 상수에 매이지 않는다 — 감지 다섯은 전건에서 sub-word 를 *)
(*             빼고, 나머지는 장치의 거절 판정이나 정본 적법성을 전건으로 *)
(*             쓴다. 대비 run 「D2 뒤 · T2 앞의 RTL」이 그 판에서 가드 속성 *)
(*             전부를 통과한다.                                           *)
(* 그 거절의 가드는 MmioPage.unaligned_rejected 한 줄이 진다 — 같은 RTL 식 *)
(* 에 GUARD-MAP 두 줄을 세우지 않는다. 좋은 모델 "reject" 가 오늘의 RTL 이다. *)
(*                                                                         *)
(* ## 정본 문면이 닫지 않던 자리 — RTL 이 먼저 정한 읽기를 모델로 돌려보냈고, 1 · 2 · 4 는 파도 4 spec 커밋이 E.12.1 3항 끝줄(e-defined.typ:1811 「*무장 비트를 내리는 것은 수락된 발화 기입과 reset 뿐이다*」)로 정본에 올렸다 — 3 은 여전히 읽기다 *)
(*                                                                         *)
(*   1. *거절된* 발화 기입(예약 비0)은 무장을 내리지 않는다. :1808 은       *)
(*      「ABORT_FIRE 기입은 … 전부 내린다」만 적고 수락/거절을 가르지 않는다. *)
(*      AbortStaging 스칼라독 「「성립·불성립 무관」의 경계」가 그것을 1항의 *)
(*      거절 축을 대칭으로 옮긴 읽기로 정했다(:1802 「효과 없는 기입이 승인만 *)
(*      남기면」 의 반대 방향 — 거절이 소진만 남기면 호스트는 자기 오타 하나로 *)
(*      세 워드를 다시 싣는다). 이 모델은 legal_first 로 그 읽기를 싣는다.  *)
(*   2. `[0]`=0 의 *수락된* 발화 기입도 발화 워드 기입이다 — 소거는 없고 무장 *)
(*      은 내린다. :479 「`[0]` 에 1 기입 = 소거 발화」와 3항 「ABORT_FIRE   *)
(*      기입은」 을 함께 읽은 결과이고 RTL(okFire 가 wdata(0) 과 무관하게     *)
(*      소진)과 같다. Witness_NoZeroFire 가 그 입력의 도달성이다.          *)
(*   3. 발화는 스테이징 *값*을 소비하지 않는다 — 값은 남고 무장만 내린다.   *)
(*      정본은 값의 수명을 말하지 않는다. 남은 값은 무장이 0 이라 다시 실리지 *)
(*      않으므로(Prop_NoPartialFire) 관측 차이가 없다 — 이 모델은 값을 남긴다. *)
(*   4. 무장은 수락된 발화 기입에서만 내려간다. :1800 「값을 덮되 비트는 선  *)
(*      채다」 는 *같은* 워드의 재기입만 말하고, 이웃 워드 기입 · 거절된 기입이 *)
(*      무장을 내리지 않는다는 것은 1항(수락 기입이 올린다) · 3항(발화 기입이  *)
(*      내린다)을 닫힌 세계로 읽은 결과다 — 다른 하강 원천을 두면 올바른 호스트 *)
(*      시퀀스(세 워드 → 한 워드 재기입 → 발화)가 무장 미완으로 조용히 무시된다. *)
(*      고정 속성 Prop_ArmFallsOnlyOnFire 가 그 읽기다 (1 의 발화 쪽 절반과 겹친다). *)
(*                                                                         *)
(* ## 이 모델이 다루지 않는 것 (「안 잰다」 — 닫힌 목록)                   *)
(*                                                                         *)
(* · 소거의 *효과* — 어느 문맥이 지워지는가, 없는 태그의 무시(E.12 3항),   *)
(*   에포크가 다른 태그, 창·회계의 소거, ABORT_COUNT 의 증가 자체.        *)
(*   Payload.tla(abort_* 가드)와 Reassembly 후-formal 의 정의역이다. 여기서 *)
(*   소거는 「발화가 태그 하나를 싣는다」(fired · ftag)까지다.             *)
(* · 소거 매칭의 *키*가 poison · trace 를 빼는가(E.12 6항의 매칭 절반) —  *)
(*   이 모델은 스테이징에 그 두 비트가 0 이라는 입구 절반만 잰다. 매칭    *)
(*   절반은 재구현 결함 D2b(Reassembly 번들 통비교 — 태그 코덱 전파 파도가 *)
(*   Payload.tla Tags 정제로 먼저 모델에 싣는다)다.                         *)
(* · 워드 *안*의 필드 배치 — 어느 비트가 에포크·LNID·precision·dim 인가, *)
(*   마스크 값(`0x0FFF0000` 등). 모델의 값은 불투명 토큰이고 거절 사유는    *)
(*   플래그 셋(poison · trace · rsv)이다. 마스크 자체는 후-formal          *)
(*   (AbortStaging_props.sv p_arm_miss_not_bad)의 몫이다.                  *)
(* · 주소 디코드 — 어느 오프셋이 어느 워드인가. 기입은 워드를 직접 지목한다 *)
(*   (조립 후-formal Wt64Top/assembly.sby 의 몫).                          *)
(* · 읽기 방향 — WO 네 워드의 읽기 0, RO 세 워드의 읽기 *값*(ABORT_ARM 은 *)
(*   무장 마스크 그 자체다 — 4항 관측은 이 모델의 armed 가 곧 그 값이다).  *)
(* · 5항 후단 — 스테이징된 태그를 관측면에 내지 않는다. 관측면은 이 모델에 *)
(*   없다(조립 후-formal 의 몫).                                           *)
(* · FAULT_STATUS `[6]` 의 sticky · W1C · 발화 우선 — loud 는 그 스텝의 발화 *)
(*   펄스다 (CapWord 와 같은 부류 — 조립 후-formal a_surf_fire 등).              *)
(* · 시간 — 모델의 스텝은 원자적이다. 「발화 기입과 같은 사이클의 스테이징 *)
(*   기입」은 표현되지 않는다(한 접근은 한 워드 — 배타 디코드).            *)
(* · 한 스텝에 기입 여럿 — 버스는 한 번에 한 워드다. 선택 신호 배타가      *)
(*   깨진 세계는 후-formal 하네스가 자유 입력으로 따로 잰다.               *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS
    Vals,            \* 스테이징 워드가 나르는 값. 불투명 토큰 (≥ 2 — 재기입이 보이려면)
    Zero,            \* reset 뒤 한 번도 쓰이지 않은 스테이징 내용 (모델 값)
    Subword,         \* sub-word(하위 두 비트 ≠ 0) 쓰기의 처분 — "reject" | "ignore"
    DisabledGuards

ASSUME Subword \in {"reject", "ignore"}
ASSUME Cardinality(Vals) >= 2 /\ Zero \notin Vals

AllGuards == {"poison_trace_zero", "epoch_word_rsv_strict", "shape_word_rsv_strict",
              "fire_rsv_strict", "ro_rejected",
              "legal_first", "reject_loud",
              "arm_on_accept", "arm_own_word", "stage_writes_value",
              "fire_needs_armed", "fire_needs_one", "fire_drains_arm"}
On(g) == g \notin DisabledGuards

\* 세 스테이징 워드 — 0 = ABORT_TAG0(0xF40) · 1 = ABORT_TAG1(0xF44) · 2 = ABORT_TAG2(0xF48).
Words == {0, 1, 2}
\* arm_own_word 를 지웠을 때 기입이 함께 세우는 이웃 워드 — 결정적으로 하나.
Nb(w) == (w + 1) % 3

\* 워드 안 거절 사유 플래그 — 값의 비트 배치는 모델 밖(머리 「안 잰다」).
BadF == {"poison", "trace", "rsv"}
KeyBad == {"poison", "trace"}
\* 워드마다 표현 가능한 거절 사유 — TAG0 `[31:0]` 은 wave 전폭이라 예약이 없다.
BadOf(w) == IF w = 0 THEN {{}}
            ELSE IF w = 1 THEN SUBSET BadF
            ELSE {{}, {"rsv"}}

(***************************************************************************)
(* 버스 기입 — 필드가 고른 레코드. 쓰지 않는 필드는 채움 값이며 속성은     *)
(* 언제나 kind 를 먼저 본다.                                               *)
(*   tag   ABORT_TAGw — 워드 w, 값 val, 거절 사유 bad                      *)
(*   fire  ABORT_FIRE — `[0]` 을 one 에, 예약 `[31:1]` 비0 을 bad 에        *)
(*   ro    RO 세 워드 중 하나의 쓰기 — 셋의 처분은 같다                   *)
(* 모든 종류에 sub(하위 두 비트 ≠ 0 — sub-word 의 장치 포트 표현)가 있다.  *)
(***************************************************************************)
Wr(k, w, v, b, o, s) == [kind |-> k, w |-> w, val |-> v, bad |-> b, one |-> o, sub |-> s]
NoWrite == Wr("none", 0, Zero, {}, FALSE, FALSE)
TagWrites == UNION {{Wr("tag", w, v, b, FALSE, s) : v \in Vals, b \in BadOf(w), s \in BOOLEAN}
                    : w \in Words}
FireWrites == {Wr("fire", 0, Zero, b, o, s) : b \in {{}, {"rsv"}}, o \in BOOLEAN, s \in BOOLEAN}
RoWrites == {Wr("ro", 0, Zero, {}, FALSE, s) : s \in BOOLEAN}
Writes == TagWrites \cup FireWrites \cup RoWrites

\* 처분 — 그 스텝의 기입이 무엇이 됐는가.
\*   ok      수락 (스테이징 · 발화 워드 기입)
\*   absorb  조용한 흡수 — 아무것도 움직이지 않고 fault 도 없다
\*   거절 여섯 — sub · ro · t1key · t1rsv · t2rsv · frsv
Reasons == {"none", "ok", "absorb", "sub", "ro", "t1key", "t1rsv", "t2rsv", "frsv"}
RejectReasons == {"sub", "ro", "t1key", "t1rsv", "t2rsv", "frsv"}

Events == {"underarmed", "zeroFull", "rewrite", "rejDrain"}

StgVals == Vals \cup {Zero}
NoTag == [x \in Words |-> [v |-> Zero, bad |-> {}]]

VARIABLES
    stg,     \* [Words -> [v, bad]] — 스테이징 세 워드 (bad 는 거절 사유가 스테이징된 흔적 — 좋은 모델에서 언제나 {})
    armed,   \* SUBSET Words — 무장 마스크 (= ABORT_ARM `[2:0]` 읽기 값)
    fresh,   \* 명세 그림자 — 직전 적법 발화 기입 뒤에 적법한 기입이 온 워드
    last,    \* 명세 그림자 — 워드마다 마지막 적법 기입의 값
    acc,     \* 보조 — 이 스텝의 기입
    why,     \* 보조 — 그 기입의 처분 (Reasons)
    loud,    \* 보조 — 이 스텝이 FAULT_STATUS [6] 을 발화했는가 (펄스)
    fired,   \* 보조 — 이 스텝에 소거가 발화했는가 (= ABORT_COUNT 증가 후보)
    ftag,    \* 보조 — 그 소거가 실은 태그 (발화 순간의 스테이징). 발화 없으면 NoTag
    ev       \* 보조 — 이 스텝의 증인 사건 (Events 의 부분집합)

vars == <<stg, armed, fresh, last, acc, why, loud, fired, ftag, ev>>

TypeOK ==
    /\ stg \in [Words -> [v : StgVals, bad : SUBSET BadF]]
    /\ armed \in SUBSET Words
    /\ fresh \in SUBSET Words
    /\ last \in [Words -> StgVals]
    /\ acc \in Writes \cup {NoWrite}
    /\ why \in Reasons
    /\ loud \in BOOLEAN
    /\ fired \in BOOLEAN
    /\ ftag \in [Words -> [v : StgVals, bad : SUBSET BadF]]
    /\ ev \in SUBSET Events

Init ==
    /\ stg = NoTag
    /\ armed = {}
    /\ fresh = {}
    /\ last = [x \in Words |-> Zero]
    /\ acc = NoWrite
    /\ why = "none"
    /\ loud = FALSE
    /\ fired = FALSE
    /\ ftag = NoTag
    /\ ev = {}

(***************************************************************************)
(* 정본의 적법성 — 가드와 무관하다. 속성의 전건이 이것을 쓴다.            *)
(***************************************************************************)
SpecBad(wr) == wr.sub \/ wr.kind = "ro" \/ wr.bad # {}

(***************************************************************************)
(* 장치의 판정 — 가드 의존. 사유가 여럿이면 앞의 것이 이름이 된다 (어느    *)
(* 이름이든 거절이다 — 속성은 이름이 아니라 RejectReasons 소속을 본다).    *)
(***************************************************************************)
Reason(wr) ==
    IF wr.sub THEN (IF Subword = "reject" THEN "sub" ELSE "absorb")
    ELSE IF wr.kind = "ro" THEN (IF On("ro_rejected") THEN "ro" ELSE "absorb")
    ELSE IF wr.kind = "tag" /\ wr.w = 1 /\ wr.bad \cap KeyBad # {} /\ On("poison_trace_zero")
         THEN "t1key"
    ELSE IF wr.kind = "tag" /\ wr.w = 1 /\ "rsv" \in wr.bad /\ On("epoch_word_rsv_strict")
         THEN "t1rsv"
    ELSE IF wr.kind = "tag" /\ wr.w = 2 /\ "rsv" \in wr.bad /\ On("shape_word_rsv_strict")
         THEN "t2rsv"
    ELSE IF wr.kind = "fire" /\ "rsv" \in wr.bad /\ On("fire_rsv_strict")
         THEN "frsv"
    ELSE "ok"

(***************************************************************************)
(* 기입 하나의 처분 — 유일한 동작. 처분 d 를 먼저 정하고, 스테이징·무장·  *)
(* 발화는 「효과가 있는가(eff)」의 함수다 — 「거절」 표식과 실제 효과가     *)
(* 갈라질 자리가 legal_first 하나뿐이다.                                  *)
(***************************************************************************)
Present(wr) ==
    LET d      == Reason(wr)
        eff    == d = "ok" \/ (d \in RejectReasons /\ ~On("legal_first"))
        isTag  == wr.kind = "tag"
        isFire == wr.kind = "fire"
        w      == wr.w
        fire   == /\ eff /\ isFire
                  /\ (wr.one \/ ~On("fire_needs_one"))
                  /\ (armed = Words \/ ~On("fire_needs_armed"))
        armTag == (IF On("arm_on_accept") THEN {w} ELSE {})
                  \cup (IF On("arm_own_word") THEN {} ELSE {Nb(w)})
        spOK   == ~SpecBad(wr)
    IN  /\ stg' = IF eff /\ isTag /\ (On("stage_writes_value") \/ w \notin armed)
                    THEN [stg EXCEPT ![w] = [v |-> wr.val, bad |-> wr.bad]]
                    ELSE stg
        \* 수락된 발화 기입은 성립 여부와 무관하게 셋을 전부 내린다 (3항) —
        \* fire_drains_arm 을 지우면 「성립한 소거만 내린다」.
        /\ armed' = IF eff /\ isTag THEN armed \cup armTag
                    ELSE IF eff /\ isFire
                         THEN (IF On("fire_drains_arm") \/ fire THEN {} ELSE armed)
                    ELSE armed
        /\ fresh' = IF spOK /\ isTag THEN fresh \cup {w}
                    ELSE IF spOK /\ isFire THEN {}
                    ELSE fresh
        /\ last' = IF spOK /\ isTag THEN [last EXCEPT ![w] = wr.val] ELSE last
        /\ acc' = wr
        /\ why' = d
        /\ loud' = (d \in RejectReasons /\ On("reject_loud"))
        /\ fired' = fire
        /\ ftag' = IF fire THEN stg ELSE NoTag
        \* 증인 사건은 입력(정본 적법성)으로 적는다 — 장치 처분과 무관하게
        \* 전건이 실재함을 보이는 표식이다.
        /\ ev' = (IF spOK /\ isFire /\ wr.one /\ armed # Words THEN {"underarmed"} ELSE {})
               \cup (IF spOK /\ isFire /\ ~wr.one /\ armed = Words THEN {"zeroFull"} ELSE {})
               \cup (IF spOK /\ isTag /\ w \in armed /\ stg[w].v # wr.val THEN {"rewrite"} ELSE {})
               \cup (IF SpecBad(wr) /\ isFire /\ armed # {} THEN {"rejDrain"} ELSE {})

Next == \E wr \in Writes : Present(wr)

Spec == Init /\ [][Next]_vars

(***************************************************************************)
(* 가드 속성 — 전부 행위 속성. acc' 가 그 스텝의 원인, why' · loud' ·      *)
(* fired' 가 처분이다. 감지 가드 다섯의 전건은 정본 적법성이고 sub-word 를 *)
(* 뺀다 — sub-word 의 처분은 상수 Subword 의 몫이라 가드 속성과 섞지 않는다. *)
(***************************************************************************)

\* poison_trace_zero — TAG1 `[27]` poison · `[26]` trace 비0 은 거절된다.
Prop_PoisonTraceRejected ==
    [][ (acc'.kind = "tag" /\ acc'.w = 1 /\ ~acc'.sub /\ acc'.bad \cap KeyBad # {})
          => why' \in RejectReasons ]_vars

\* epoch_word_rsv_strict — TAG1 `[25:16]` 예약 비0 은 거절된다.
Prop_EpochWordRsvRejected ==
    [][ (acc'.kind = "tag" /\ acc'.w = 1 /\ ~acc'.sub /\ "rsv" \in acc'.bad)
          => why' \in RejectReasons ]_vars

\* shape_word_rsv_strict — TAG2 `[31:16]` 예약 비0 은 거절된다.
Prop_ShapeWordRsvRejected ==
    [][ (acc'.kind = "tag" /\ acc'.w = 2 /\ ~acc'.sub /\ "rsv" \in acc'.bad)
          => why' \in RejectReasons ]_vars

\* fire_rsv_strict — FIRE `[31:1]` 예약 비0 은 거절된다.
Prop_FireRsvRejected ==
    [][ (acc'.kind = "fire" /\ ~acc'.sub /\ "rsv" \in acc'.bad)
          => why' \in RejectReasons ]_vars

\* ro_rejected — RO 세 워드의 쓰기는 거절된다.
Prop_RoRejected ==
    [][ (acc'.kind = "ro" /\ ~acc'.sub) => why' \in RejectReasons ]_vars

\* legal_first — 거절된 기입은 스테이징 · 무장 · 발화 어느 것도 움직이지 않는다.
Prop_RejectedNoEffect ==
    [][ why' \in RejectReasons => (stg' = stg /\ armed' = armed /\ ~fired') ]_vars

\* reject_loud — 거절은 전부 FAULT_STATUS [6] 을 발화한다.
Prop_RejectLoud ==
    [][ why' \in RejectReasons => loud' ]_vars

\* arm_on_accept — 적법한 스테이징 기입 뒤 그 워드의 무장이 서 있다.
Prop_ArmOnAccept ==
    [][ (acc'.kind = "tag" /\ ~SpecBad(acc')) => acc'.w \in armed' ]_vars

\* arm_own_word — 무장 비트 x 의 상승은 워드 x 의 기입에서만.
Prop_ArmOwnWord ==
    [][ \A x \in Words : (x \notin armed /\ x \in armed')
                           => (acc'.kind = "tag" /\ acc'.w = x) ]_vars

\* stage_writes_value — 적법한 스테이징 기입 뒤 그 워드의 값은 쓴 값이다 (재기입 포함).
Prop_StageLatest ==
    [][ (acc'.kind = "tag" /\ ~SpecBad(acc')) => stg'[acc'.w].v = acc'.val ]_vars

\* fire_needs_armed — 소거는 무장 셋이 모두 선 상태에서만.
Prop_FireNeedsArmed ==
    [][ fired' => armed = Words ]_vars

\* fire_needs_one — 소거는 `[0]`=1 인 발화 워드 기입에서만.
Prop_FireNeedsOne ==
    [][ fired' => (acc'.kind = "fire" /\ acc'.one) ]_vars

\* fire_drains_arm — 적법한 발화 기입 뒤 무장은 전부 내려가 있다 (성립 무관).
Prop_FireDrains ==
    [][ (acc'.kind = "fire" /\ ~SpecBad(acc')) => armed' = {} ]_vars

(***************************************************************************)
(* 고정 의미의 속성 — 좋은 모델 cfg 와 짝 · 대비 run 이 쓴다.              *)
(***************************************************************************)

\* 2항 · 3항 — 소거에 실리는 세 워드는 전부 직전 발화 기입 뒤에 적법하게 쓰였다.
\* 부분 기입(한 번도 안 쓴 워드)도 stale staging(직전 시도의 잔재)도 아니다.
Prop_NoPartialFire ==
    [][ fired' => fresh = Words ]_vars

\* 1항 「값을 덮되」 — 실리는 값은 워드마다 마지막 적법 기입의 값이다.
Prop_FireTagLatest ==
    [][ fired' => \A x \in Words : ftag'[x].v = last[x] ]_vars

\* E.12 6항 — 소거가 싣는 태그에 poison · trace · 예약이 없다 (키에서 빠지는 두 비트가 0).
Prop_FiredKeyClean ==
    [][ fired' => \A x \in Words : ftag'[x].bad = {} ]_vars

\* 거절 사유인 기입은 전부 거절된다 — sub-word 포함 (E.12.1 1·5항 · 03-hiu 3.7).
Prop_MalformedRejected ==
    [][ SpecBad(acc') => why' \in RejectReasons ]_vars

\* 적법한 기입은 거절되지 않는다 — 무장 미완 발화도 거절이 아니다 (2항).
Prop_RejectOnlyMalformed ==
    [][ why' \in RejectReasons => SpecBad(acc') ]_vars

\* [6] 은 거절에서만 발화한다 — 허위 fault 없음.
Prop_LoudOnlyOnReject ==
    [][ loud' => why' \in RejectReasons ]_vars

\* 2항 — 무장 미완의 적법 발화는 무시다: 소거도 fault 도 없다 (소진은 Prop_FireDrains).
Prop_UnderarmedIgnored ==
    [][ (acc'.kind = "fire" /\ ~SpecBad(acc') /\ armed # Words)
          => (~fired' /\ ~loud' /\ why' = "ok") ]_vars

\* 스테이징 워드 기입만으로는 소거가 없다 — 발화는 발화 워드에서만.
Prop_StagingNoFire ==
    [][ acc'.kind # "fire" => ~fired' ]_vars

\* 무장의 하강 원천은 수락된 발화 기입뿐 — 스테이징 기입(이웃 워드 포함) · 거절된
\* 기입 · 흡수는 무장을 내리지 않는다 (머리 「닫지 않은 자리」 4 · 후-formal t_arm_fall).
Prop_ArmFallsOnlyOnFire ==
    [][ ~(acc'.kind = "fire" /\ why' = "ok") => armed \subseteq armed' ]_vars

(***************************************************************************)
(* 위험 도달성 증인 — 좋은 모델에서 반드시 반증돼야 한다. 가드마다 그      *)
(* 가드가 막는 입력이 실재함을 보인다.                                     *)
(***************************************************************************)

\* arm_on_accept · arm_own_word · stage_writes_value · fire_needs_armed · fire_drains_arm —
\* 소거가 실제로 발화한다 (세 워드 적재 → 무장 완비 → 발화).
Witness_NoFire == ~fired

\* fire_needs_armed · fire_drains_arm — 무장 미완의 적법 발화([0]=1)가 온다.
Witness_NoUnderarmedFire == "underarmed" \notin ev

\* fire_needs_one — 무장 완비 상태에 `[0]`=0 의 적법 발화 워드 기입이 온다.
Witness_NoZeroFire == "zeroFull" \notin ev

\* stage_writes_value — 무장이 선 워드에 다른 값의 적법 재기입이 온다.
Witness_NoRewrite == "rewrite" \notin ev

\* legal_first — 무장이 선 동안 거절 사유인 발화 기입이 온다 (소진 여부가 갈린다).
Witness_NoRejectedDrain == "rejDrain" \notin ev

\* poison_trace_zero · legal_first · reject_loud — poison/trace 가 선 TAG1 이 거절된다.
Witness_NoPoisonTraceReject == why # "t1key"

\* epoch_word_rsv_strict — 예약 `[25:16]` 비0 TAG1 이 거절된다.
Witness_NoEpochWordRsvReject == why # "t1rsv"

\* shape_word_rsv_strict — 예약 `[31:16]` 비0 TAG2 가 거절된다.
Witness_NoShapeWordRsvReject == why # "t2rsv"

\* fire_rsv_strict — 예약 `[31:1]` 비0 발화 기입이 거절된다.
Witness_NoFireRsvReject == why # "frsv"

\* ro_rejected — RO 세 워드의 쓰기가 거절된다.
Witness_NoRoReject == why # "ro"

\* Subword = "reject" — sub-word 쓰기가 거절된다.
Witness_NoSubReject == why # "sub"

=============================================================================
