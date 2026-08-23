\* SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
\* SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
------------------------------ MODULE Route ------------------------------
(***************************************************************************)
(* ISA-3 · ISA-4 선-formal 모델 — route fault 의 판정 주체와 범위.         *)
(*                                                                         *)
(*   ISA-3 전역 미스만 fault — 배달 범위의 합집합에 속하는 LNID 를 가진    *)
(*         토큰은 route fault 를 밟지 않는다. 합집합에 없는 LNID 는        *)
(*         반드시 밟는다.                                                  *)
(*   ISA-4 계층당 1회성 — 하나의 토큰이 하나의 배달 범위에서 발생시키는    *)
(*         route fault 는 최대 1회다.                                      *)
(*                                                                         *)
(* ## 발화 조건은 **둘**이다 — 하나만 다루면 ISA-4 가 공허해진다           *)
(*                                                                         *)
(* 정본 §1.6.3 「발화 조건」:                                              *)
(*   (1) 토큰의 LNID 가 그 토큰이 진입한 배달 범위 전체에서 어느 소유자    *)
(*       에게도 속하지 않는다.                                             *)
(*   (2) `src_kind=1` 인 명령의 LBID 가 사상표에 없다.                     *)
(*                                                                         *)
(* (2)의 판정 자리도 정본이 정한다 — §1.6.3 「판정 주체와 범위」 2항:      *)
(* 진입점, 조건 1항과 같은 자리. Judge(s) 가 두 조건을 진입점의 한 원자    *)
(* 판정으로 접는 것은 그 규범 그대로다.                                    *)
(*                                                                         *)
(* 처음 판은 (1)만 모델링했다. 그러면 ISA-4 「최대 1회」가 검사할 것이      *)
(* 없다 — 조건이 하나뿐이면 두 번 발화할 방법 자체가 없기 때문이다.        *)
(* *두 조건을 동시에 밟은 토큰에도 fault 는 하나여야 한다*는 것이 그        *)
(* 규범의 실질이고, 그 상황은 조건이 둘일 때만 만들어진다.                 *)
(*                                                                         *)
(* ## 계층 — 기저는 TLC, 깊이는 귀납                                       *)
(*                                                                         *)
(* 「계층당 1회」는 계층이 하나뿐인 모델에서 거의 자명하게 성립한다. TLC 는 *)
(* 유한 검사기라 깊이를 고정해야 하므로, 임의 깊이는 검사로 닿을 수 없다.  *)
(*                                                                         *)
(* 대신 이 모델은 귀납의 두 조각을 각각 확인 가능한 형태로 만든다:         *)
(*                                                                         *)
(*   기저      Depth = 1, 2, 3 을 TLC 로 전수 검사한다.                    *)
(*   귀납 단계 `Inv_ScopeLocal` — 한 범위의 fault 판정이 *(토큰, 그 범위의  *)
(*             합집합, 사상표)* 만의 함수임을 확인한다. 즉 **범위 사이에    *)
(*             결합이 없다.** 결합이 없으면 깊이 k 에서 k+1 로 가는 단계가  *)
(*             새로운 상호작용을 만들지 않으므로, 기저에서 임의 깊이로      *)
(*             올라가는 귀납이 성립한다.                                   *)
(*                                                                         *)
(* ⚠️ 정직 표기: 이것은 *TLAPS 로 기계 증명한 것이 아니다.* TLC 가 확인한   *)
(* 것은 기저와 비간섭이고, 깊이에 대한 귀납은 그 둘 위에 선 **논증**이다.  *)
(* 부록 D 에도 그렇게 적는다.                                              *)
(***************************************************************************)
(***************************************************************************)
(* ## 이 모델이 덮지 않는 것 — 적대 검증이 남긴 목록                       *)
(*                                                                         *)
(* 덮지 않는 것을 적지 않으면 「전수」라는 낱말이 거짓이 된다. 아래는 이    *)
(* 모델이 *의도적으로* 또는 *아직* 표현하지 않는 것들이다.                 *)
(*                                                                         *)
(*   ⚠️ 시간축 없음 — Judge(s) 는 ~judged[s] 로 범위당 1회 원자 대입이다.   *)
(*      같은 범위가 다시 발화하는 상황(재진입·파이프라인 중첩)은 상태로     *)
(*      존재하지 않는다. ISA-4 「계층당 최대 1회」의 *계층* 축은 덮이지만   *)
(*      *시간* 축은 덮이지 않는다. 후-formal(sby) 이 그 축을 맡는다.        *)
(*                                                                         *)
(*   ⚠️ sticky 가 범위 밖 — Arrive 가 faultsIn 을 0 으로 되돌린다. 정본     *)
(*      §1.6.3 과 ISA-6 은 fault 비트가 *sticky* 라고 규정하므로, 이 모델의 *)
(*      faultsIn 은 「fault 상태」가 아니라 「이 토큰이 밟은 발화 횟수」다.  *)
(*      두 낱말을 섞으면 안 된다.                                          *)
(*                                                                         *)
(*   ⚠️ 토큰 제시가 스트로브다 — Arrive 는 「새 토큰 하나의 도착」이고,      *)
(*      같은 토큰이 여러 사이클 제시되는 상황은 이 모델에 상태로 없다.      *)
(*      RTL(RouteJudge)의 tokIn 이 「토큰 하나 = valid 한 사이클」 이라는    *)
(*      전제 — 같은 토큰을 여러 사이클 들고 있으면 발화가 사이클마다        *)
(*      선다 — 는 위 시간축 부재에서 따라 나온 *구현의 새 결정*이며, 이     *)
(*      모델이 검사하지 않는다. ISA-4 의 시간 축과 함께 후-formal(sby)      *)
(*      몫이다 (1차 파도 환류 처분, 2026-08-23).                            *)
(*                                                                         *)
(*   ⚠️ 해제와 in-flight 의 겹침 없음 — 구성 액션(ConfigOwn·ConfigRelease)  *)
(*      은 lnid = NoName (토큰 없음) 에서만 열린다. 소유 해제가 비행 중     *)
(*      토큰과 겹치는 시간축은 이 모델에 표현이 없다 — 후-formal 몫이다.    *)
(*                                                                         *)
(*   ✅ (해소) 소유 서로소성 — 초판에서 unique_owner 는 정본 근거 없는      *)
(*      모델러의 가정이었다. 지금은 §1.4.5 규범이다: 한 배달 범위 안에서   *)
(*      한 LNID 의 소유자는 최대 하나, 강제는 사상표 기입 시점의 거절.     *)
(*      가드는 그 규범의 형식화다 — ConfigOwn 주석 참조.                   *)
(*                                                                         *)
(*   ✅ (해소) fault 후 전파 — 이 모델은 fault 를 밟은 토큰도 모든 범위     *)
(*      에서 판정받게 돌린다. 초판에서 이것은 근거 없는 선택이었다         *)
(*      (§1.8 ISA-4 함정이 지적했다). 지금은 §1.6.3 토큰 전파 규범         *)
(*      (무효과 통과)이 이 독법을 확정한다 — 차단 게이트 금지는            *)
(*      scope_independent 가드가 형식화한다.                               *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS
    Names,           \* LNID 이름 공간. 평면·불투명 (§1.1)
    Banks,           \* LBID 이름 공간. 평면·불투명
    Points,          \* 한 배달 범위 안의 배달 지점들 (형제 노드)
    Depth,           \* 배달 범위의 겹 수. 계층 파라미터
    NoName,
    DisabledGuards

AllGuards == {"global_judge", "fault_once", "loud_fault",
              "view_sync", "scope_independent", "unique_owner"}
On(g) == g \notin DisabledGuards

Scopes == 1..Depth

(***************************************************************************)
(* 형제가 둘 이상이어야 「지역 판정」과 「전역 판정」이 다른 것이 된다.     *)
(* 지점이 하나면 지역 판정이 곧 전역 판정이므로 global_judge 가드 삭제     *)
(* 실험이 *정당하게* 통과한다 — 적대 검증이 실측으로 잡았다. 배터리가 그   *)
(* 축퇴 형상을 돌지 않는다는 사실에 기대지 않고 여기서 못박는다.           *)
(***************************************************************************)
ASSUME Cardinality(Points) >= 2

\* fault 상한. 지역 판정은 형제 수만큼 낼 수 있고 LBID 축이 하나 더 얹힌다.
\* **주입 최대값과 같은 값으로 두지 않는다** — 상한이 곧 주입값이면 타입
\* 불변식이 판별력을 잃고, 무엇보다 「형제마다 fault」의 규모가 표현되지 않는다.
MaxF == Cardinality(Points) + 1

\* `src_kind` 는 §1.4.3 그대로다. 1 = 결과 뱅크 조회(첨자는 LBID).
\* 이 모델이 구분해야 하는 것은 「LBID 를 보는가」뿐이므로 둘로 족하다.
SrcKinds == {0, 1}

VARIABLES
    owns,        \* [Scopes \X Points -> SUBSET Names]  구성이 정한다
    bankMap,     \* SUBSET Banks — LBID 사상표. 구성 표면에 하나 있다 (§1.5)
    lnid,        \* 흐르는 토큰의 LNID. NoName = 토큰 없음
    lbid,        \* 그 명령의 LBID
    srcKind,     \* 그 명령의 src_kind
    view,        \* [Scopes -> SUBSET Names]  **진입점이 들고 있는 합집합 뷰.**
                 \* 정본 §1.6.3 1항: "진입점은 자기 하위 소유 집합들의 합집합을
                 \* 알아야 한다. 합집합 표를 갖든 하위의 적중 신호를 OR 로 모으든
                 \* 구현은 자유" — 즉 뷰는 **표와 별개의 상태**이고, 둘이 어긋날
                 \* 수 있다. 뷰를 정의로 두면 그 어긋남이 표현 불가능해진다.
    judged,      \* [Scopes -> BOOLEAN]  이 범위에서 판정이 끝났는가
    faultsIn     \* [Scopes -> 0..2]  이 범위에서 밟은 fault 수

vars == <<owns, bankMap, lnid, lbid, srcKind, view, judged, faultsIn>>

ScopeUnion(s) == UNION { owns[<<s, p>>] : p \in Points }

\* 이 토큰을 소유하지 않는 지점들 — **지역 비소유**. 정상 동작이다.
NonOwners(s, n) == { p \in Points : n \notin owns[<<s, p>>] }

(***************************************************************************)
(* 두 어휘를 **의도적으로 가른다.**                                        *)
(*                                                                         *)
(*   Real*  — 실재. 지점별 소유 표가 말하는 것. **불변식이 쓴다.**         *)
(*   View*  — 진입점이 보는 것. **액션이 쓴다.**                           *)
(*                                                                         *)
(* 처음 판은 불변식과 액션이 같은 술어를 썼다. 그러면 불변식이 액션을      *)
(* 되풀이할 뿐이라 *자기지시적으로 만족*된다 — 적대 검증이 잡은 지적이다.  *)
(* 어휘를 가르면 뷰가 실재와 어긋나는 순간 불변식이 그것을 잡는다.         *)
(***************************************************************************)
RealMissLnid(s) == lnid \notin ScopeUnion(s)
ViewMissLnid(s) == lnid \notin view[s]
MissLbid        == srcKind = 1 /\ lbid \notin bankMap

RealAnyMiss(s) == RealMissLnid(s) \/ MissLbid
ViewAnyMiss(s) == ViewMissLnid(s) \/ MissLbid

TypeOK ==
    /\ owns \in [Scopes \X Points -> SUBSET Names]
    /\ bankMap \subseteq Banks
    /\ lnid \in Names \cup {NoName}
    /\ lbid \in Banks
    /\ srcKind \in SrcKinds
    /\ view \in [Scopes -> SUBSET Names]
    /\ judged \in [Scopes -> BOOLEAN]
    /\ faultsIn \in [Scopes -> 0..MaxF]

Init ==
    /\ owns = [e \in Scopes \X Points |-> {}]
    /\ bankMap = {}
    /\ lnid = NoName
    /\ lbid = CHOOSE b \in Banks : TRUE
    /\ srcKind = 0
    /\ view = [s \in Scopes |-> {}]
    /\ judged = [s \in Scopes |-> FALSE]
    /\ faultsIn = [s \in Scopes |-> 0]

(***************************************************************************)
(* 구성 — reset 직후 소유 집합과 사상표는 전부 비어 있다 (§1.5).           *)
(***************************************************************************)
ConfigOwn(s, p, n) ==
    \* 서로소 가드 — §1.4.5 규범: 한 배달 범위 안에서 한 LNID 의 소유자는
    \* 최대 하나이고, 강제는 사상표 **기입 시점의 거절**이다. 이 가드가 그
    \* 거절이다 — 중복 소유를 만드는 쓰기는 액션 자체가 막힌다 (거절의
    \* loud fault 방출은 모델 밖). 지우면 두 지점이 같은 이름을 소유해
    \* 배달이 모호해진다 — Inv_UniqueOwnerPerScope 가 잡는다.
    /\ (n \notin ScopeUnion(s) \/ ~On("unique_owner"))
    /\ lnid = NoName
    /\ owns' = [owns EXCEPT ![<<s, p>>] = @ \cup {n}]
    \* 뷰 동기화. 지우면 진입점의 뷰가 표보다 뒤처진다 — §1.6.3 이 허용한
    \* 「하위 적중 신호 OR」 갈래의 대표 결함형(스큐)이 정확히 이것이다.
    \* 이 원자 대입이 곧 「기입 1회 = 뷰 구동 1회」 라는 *모듈 간* 계약의
    \* 모델 문면이다 — RTL 에서 표 반영(MmioConfig)과 뷰 구동(RouteJudge 의
    \* viewWr 포트)이 서로 다른 모듈로 갈라졌으므로, 모델 안의 한 액션이던
    \* 것이 두 모듈 사이의 계약이 됐다. 정본 §3.7.1 「기입의 원자성 계약」
    \* 이 그 등재 자리다 (1차 파도 환류 처분, 2026-08-23).
    /\ view' = IF On("view_sync")
                 THEN [view EXCEPT ![s] = @ \cup {n}]
                 ELSE view
    /\ UNCHANGED <<bankMap, lnid, lbid, srcKind, judged, faultsIn>>

(***************************************************************************)
(* 소유 해제 — 구현 환류 (2026-08-23).                                     *)
(*                                                                         *)
(* 초판 모델은 추가(ConfigOwn)만 두었고 §1.5 공집합으로 되돌아갈 길이      *)
(* 없었다. RTL(MmioConfig)이 해제 기입(V=0)을 열었다 — 표와 진입점 뷰를    *)
(* *같은 조작*으로 소거한다. §6.3 5단계에 따라 그 결정을 모델로 돌려받는다.*)
(*                                                                         *)
(* view_sync 가드를 *공유*한다 — 「기입 1회 = 뷰 구동 1회」(§3.7.1)는       *)
(* 방향(추가/해제)과 무관한 한 계약이기 때문이다. 가드를 지운 실험         *)
(* (Route_del_view_sync)의 반례는 두 방향 어느 쪽에서든 나올 수 있다 —     *)
(* TLC 는 통상 추가 쪽 최단 반례를 먼저 낸다. RTL 에서 두 방향이 서로      *)
(* 다른 기입 경로라는 사실의 검사는 후-formal 몫이다.                      *)
(*                                                                         *)
(* 새 가드는 없다: 점유 엔트리의 유효 재기입 거절(해제 후 재기입 2단계)은  *)
(* ConfigOwn 의 unique_owner 거절이 이미 형식화하고 있고, 해제 자체가      *)
(* 만들 수 있는 유일한 스큐(뷰 잔존)는 view_sync 축이다. 해제 × 비행 중    *)
(* 토큰의 시간축은 머리 비-커버리지 목록 참조.                             *)
(***************************************************************************)
ConfigRelease(s, p, n) ==
    /\ n \in owns[<<s, p>>]
    /\ lnid = NoName
    /\ owns' = [owns EXCEPT ![<<s, p>>] = @ \ {n}]
    \* @ \ {n} 이 정확한 것은 unique_owner 아래에서다 — 서로소성이 살아
    \* 있으면 형제 지점이 같은 이름을 들 수 없어, 지점 하나의 해제가 곧
    \* 범위 합집합에서의 소거다. unique_owner 를 지운 실험 형상에서는 이
    \* 대입이 스큐를 만들 수 있으나, 그 형상이 검사하는 것은
    \* Inv_UniqueOwnerPerScope 하나다 (cfg 참조).
    /\ view' = IF On("view_sync")
                 THEN [view EXCEPT ![s] = @ \ {n}]
                 ELSE view
    /\ UNCHANGED <<bankMap, lnid, lbid, srcKind, judged, faultsIn>>

ConfigBank(b) ==
    /\ lnid = NoName
    /\ bankMap' = bankMap \cup {b}
    /\ UNCHANGED <<owns, lnid, lbid, srcKind, view, judged, faultsIn>>

Arrive(n, b, k) ==
    /\ lnid = NoName
    /\ lnid' = n
    /\ lbid' = b
    /\ srcKind' = k
    /\ judged' = [s \in Scopes |-> FALSE]
    /\ faultsIn' = [s \in Scopes |-> 0]
    /\ UNCHANGED <<owns, bankMap, view>>

(***************************************************************************)
(* 판정 — 범위마다 한 번.                                                  *)
(*                                                                         *)
(*   global_judge  살아 있으면 진입점이 **합집합**으로 판정한다.           *)
(*                 지우면 각 지점이 **지역**으로 판정해 자기 것이 아닌      *)
(*                 지점마다 fault 를 낸다 — 정상 토큰이 형제 수만큼 밟는다. *)
(*   fault_once    두 발화 조건을 **하나의 fault 로 접는다.** 지우면 두     *)
(*                 조건을 다 밟은 토큰이 두 번 발화한다.                   *)
(***************************************************************************)
BaseFault(s) ==
    IF ~On("loud_fault") /\ ViewAnyMiss(s)
      THEN 0                       \* 무언 드롭 — INV-T3 정면 위반
      ELSE IF On("global_judge")
             THEN IF ~ViewAnyMiss(s) THEN 0
                  ELSE IF On("fault_once")
                         THEN 1
                         ELSE (IF ViewMissLnid(s) THEN 1 ELSE 0)
                              + (IF MissLbid THEN 1 ELSE 0)
             ELSE \* 지역 판정 — 형제마다 발화한다.
                  Cardinality(NonOwners(s, lnid)) + (IF MissLbid THEN 1 ELSE 0)

\* scope_independent 를 지우면 앞 범위의 결과가 이 범위의 판정에 샌다 —
\* §1.6.3 토큰 전파 규범(무효과 통과)이 금지한 차단 게이트가 정확히 이
\* 결합이다. 그 결합이 있으면 깊이에 대한 귀납도 성립하지 않는다.
FaultCount(s) ==
    IF On("scope_independent") \/ s = 1
      THEN BaseFault(s)
      ELSE IF faultsIn[s - 1] > 0 THEN 0 ELSE BaseFault(s)

Judge(s) ==
    /\ lnid # NoName
    /\ ~judged[s]
    /\ judged' = [judged EXCEPT ![s] = TRUE]
    /\ faultsIn' = [faultsIn EXCEPT ![s] = FaultCount(s)]
    /\ UNCHANGED <<owns, bankMap, lnid, lbid, srcKind, view>>

Retire ==
    /\ lnid # NoName
    /\ \A s \in Scopes : judged[s]
    /\ lnid' = NoName
    /\ UNCHANGED <<owns, bankMap, lbid, srcKind, view, judged, faultsIn>>

Next ==
    \/ \E s \in Scopes, p \in Points, n \in Names : ConfigOwn(s, p, n)
    \/ \E s \in Scopes, p \in Points, n \in Names : ConfigRelease(s, p, n)
    \/ \E b \in Banks : ConfigBank(b)
    \/ \E n \in Names, b \in Banks, k \in SrcKinds : Arrive(n, b, k)
    \/ \E s \in Scopes : Judge(s)
    \/ Retire

Spec == Init /\ [][Next]_vars

(***************************************************************************)
(* 불변식                                                                  *)
(***************************************************************************)

\* ISA-3 전반 — 어느 조건도 걸리지 않으면 fault 를 밟지 않는다.
\* 이것이 깨지면 *정상 워크로드가 죽는다.*
Inv_CleanNeverFaults ==
    \A s \in Scopes :
        (lnid # NoName /\ judged[s] /\ ~RealAnyMiss(s)) => faultsIn[s] = 0

\* ISA-3 후반 — 걸리면 반드시 밟는다. 무언 드롭 금지 (INV-T3).
Inv_MissAlwaysFaults ==
    \A s \in Scopes :
        (lnid # NoName /\ judged[s] /\ RealAnyMiss(s)) => faultsIn[s] >= 1

\* ISA-4 — 배달 범위마다 최대 1회. **두 조건을 다 밟아도 하나다.**
Inv_FaultAtMostOncePerScope == \A s \in Scopes : faultsIn[s] =< 1

(***************************************************************************)
(* 귀납 단계 — 범위 간 비간섭.                                             *)
(*                                                                         *)
(* 한 범위의 fault 수가 *그 범위의 지역 술어만*으로 완전히 결정된다면,     *)
(* 범위를 하나 더 쌓아도 새로운 상호작용이 생기지 않는다. 그 사실이 깊이   *)
(* 에 대한 귀납의 단계다 — 기저(Depth=1,2,3)에서 임의 깊이로 올린다.       *)
(***************************************************************************)
\* **쌍대 형태**로 적는다. 지역 상태가 같은 두 범위는 같은 결과를 내야 한다 —
\* 이 진술은 액션의 어휘를 되풀이하지 않으므로 자기지시적이지 않다.
Inv_ScopeLocal ==
    \A s, u \in Scopes :
        (lnid # NoName /\ judged[s] /\ judged[u] /\ view[s] = view[u])
            => faultsIn[s] = faultsIn[u]

\* 진입점의 뷰가 실재와 일치해야 한다 (§1.6.3 1항).
Inv_ViewAgrees == \A s \in Scopes : view[s] = ScopeUnion(s)

\* 한 범위 안에서 한 이름의 소유자는 최대 하나 — §1.4.5 규범.
\* 가드(unique_owner)는 기입 어휘, 이 불변식은 소유 표 어휘다 (자기지시 금지).
Inv_UniqueOwnerPerScope ==
    \A s \in Scopes, n \in Names :
        Cardinality({ p \in Points : n \in owns[<<s, p>>] }) =< 1

(***************************************************************************)
(* 위험 도달성 증인                                                        *)
(*                                                                         *)
(* 증인은 **구성이 끝난 기계**에서 도달해야 뜻이 있다. 구성 전에는 모든     *)
(* 소유 집합과 사상표가 비어 있어 전부 fault 이므로(§1.5), 그 상태로        *)
(* 반증된 증인은 정본이 이미 자명하다고 선언한 것을 다시 말할 뿐이다.       *)
(* 적대 검증이 실측으로 잡은 지적이다.                                     *)
(***************************************************************************)
Configured(s) == ScopeUnion(s) # {} /\ bankMap # {}

Witness_NoClean == \A s \in Scopes : ~(judged[s] /\ lnid # NoName /\ ~RealAnyMiss(s))
\* **구성된** 기계에서 fault 가 나는가. 구성 전에는 전부 fault 이므로
\* (정본 §1.5) 그 상태로 반증하면 아무것도 뜻하지 않는다 — 적대 검증 지적.
Witness_NoFault ==
    \A s \in Scopes : ~(Configured(s) /\ faultsIn[s] > 0)

\* 지역 비소유가 실재하는가 — 없으면 global_judge 가드가 공허하다.
Witness_NoLocalNonOwnership ==
    \A s \in Scopes :
        (judged[s] /\ lnid # NoName /\ ~RealMissLnid(s)) => NonOwners(s, lnid) = {}

(***************************************************************************)
(* **두 조건을 동시에 밟는 토큰이 실재하는가.**                            *)
(*                                                                         *)
(* 이 증인이 반증되지 않으면 ISA-4 「최대 1회」는 검사할 것이 없다 —       *)
(* 두 번 발화할 상황 자체가 도달 불가능하다는 뜻이기 때문이다.             *)
(* 처음 판이 조건 하나만 모델링했을 때가 정확히 그 상태였다.               *)
(***************************************************************************)
Witness_NoDoubleMiss ==
    \A s \in Scopes :
        ~(judged[s] /\ lnid # NoName /\ Configured(s) /\ RealMissLnid(s) /\ MissLbid)

\* 무언 드롭이 **표현 가능한가.** loud_fault 가드를 지운 모델에서만 도달해야
\* 하며, 좋은 모델에서 도달 불가인 것이 곧 INV-T3 가 지켜진다는 뜻이다.
\* 이 증인이 없어서 Inv_MissAlwaysFaults 가 *어떤 형상에서도 반증 불가*
\* 였다 — README 교훈 ①(방어적 구성이 가드를 무력화)의 재발이었다.
Witness_NoSilentDrop ==
    \A s \in Scopes : ~(judged[s] /\ lnid # NoName /\ RealAnyMiss(s) /\ faultsIn[s] = 0)

=============================================================================
