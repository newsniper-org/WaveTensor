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
EXTENDS Naturals, FiniteSets

CONSTANTS
    Names,           \* LNID 이름 공간. 평면·불투명 (§1.1)
    Banks,           \* LBID 이름 공간. 평면·불투명
    Points,          \* 한 배달 범위 안의 배달 지점들 (형제 노드)
    Depth,           \* 배달 범위의 겹 수. 계층 파라미터
    NoName,
    DisabledGuards

AllGuards == {"global_judge", "fault_once", "loud_fault"}
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
    judged,      \* [Scopes -> BOOLEAN]  이 범위에서 판정이 끝났는가
    faultsIn     \* [Scopes -> 0..2]  이 범위에서 밟은 fault 수

vars == <<owns, bankMap, lnid, lbid, srcKind, judged, faultsIn>>

ScopeUnion(s) == UNION { owns[<<s, p>>] : p \in Points }

\* 이 토큰을 소유하지 않는 지점들 — **지역 비소유**. 정상 동작이다.
NonOwners(s, n) == { p \in Points : n \notin owns[<<s, p>>] }

(***************************************************************************)
(* 두 발화 조건. 둘 다 **그 범위의 지역 상태**만 본다 — 그 사실이           *)
(* Inv_ScopeLocal 의 내용이고, 깊이 귀납의 근거다.                         *)
(***************************************************************************)
MissLnid(s) == lnid \notin ScopeUnion(s)
MissLbid    == srcKind = 1 /\ lbid \notin bankMap
AnyMiss(s)  == MissLnid(s) \/ MissLbid

TypeOK ==
    /\ owns \in [Scopes \X Points -> SUBSET Names]
    /\ bankMap \subseteq Banks
    /\ lnid \in Names \cup {NoName}
    /\ lbid \in Banks
    /\ srcKind \in SrcKinds
    /\ judged \in [Scopes -> BOOLEAN]
    /\ faultsIn \in [Scopes -> 0..MaxF]

Init ==
    /\ owns = [e \in Scopes \X Points |-> {}]
    /\ bankMap = {}
    /\ lnid = NoName
    /\ lbid = CHOOSE b \in Banks : TRUE
    /\ srcKind = 0
    /\ judged = [s \in Scopes |-> FALSE]
    /\ faultsIn = [s \in Scopes |-> 0]

(***************************************************************************)
(* 구성 — reset 직후 소유 집합과 사상표는 전부 비어 있다 (§1.5).           *)
(***************************************************************************)
ConfigOwn(s, p, n) ==
    /\ lnid = NoName
    /\ n \notin ScopeUnion(s)          \* 한 범위 안에서 한 이름은 한 지점만 소유
    /\ owns' = [owns EXCEPT ![<<s, p>>] = @ \cup {n}]
    /\ UNCHANGED <<bankMap, lnid, lbid, srcKind, judged, faultsIn>>

ConfigBank(b) ==
    /\ lnid = NoName
    /\ bankMap' = bankMap \cup {b}
    /\ UNCHANGED <<owns, lnid, lbid, srcKind, judged, faultsIn>>

Arrive(n, b, k) ==
    /\ lnid = NoName
    /\ lnid' = n
    /\ lbid' = b
    /\ srcKind' = k
    /\ judged' = [s \in Scopes |-> FALSE]
    /\ faultsIn' = [s \in Scopes |-> 0]
    /\ UNCHANGED <<owns, bankMap>>

(***************************************************************************)
(* 판정 — 범위마다 한 번.                                                  *)
(*                                                                         *)
(*   global_judge  살아 있으면 진입점이 **합집합**으로 판정한다.           *)
(*                 지우면 각 지점이 **지역**으로 판정해 자기 것이 아닌      *)
(*                 지점마다 fault 를 낸다 — 정상 토큰이 형제 수만큼 밟는다. *)
(*   fault_once    두 발화 조건을 **하나의 fault 로 접는다.** 지우면 두     *)
(*                 조건을 다 밟은 토큰이 두 번 발화한다.                   *)
(***************************************************************************)
FaultCount(s) ==
    IF ~On("loud_fault") /\ AnyMiss(s)
      THEN 0                       \* 무언 드롭 — INV-T3 정면 위반
      ELSE IF On("global_judge")
             THEN IF ~AnyMiss(s) THEN 0
                  ELSE IF On("fault_once")
                         THEN 1
                         ELSE (IF MissLnid(s) THEN 1 ELSE 0)
                              + (IF MissLbid THEN 1 ELSE 0)
             ELSE \* 지역 판정 — 형제마다 발화한다. LBID 축은 표가 하나이므로
                  \* 지역 판정이어도 그대로 남는다.
                  Cardinality(NonOwners(s, lnid)) + (IF MissLbid THEN 1 ELSE 0)

Judge(s) ==
    /\ lnid # NoName
    /\ ~judged[s]
    /\ judged' = [judged EXCEPT ![s] = TRUE]
    /\ faultsIn' = [faultsIn EXCEPT ![s] = FaultCount(s)]
    /\ UNCHANGED <<owns, bankMap, lnid, lbid, srcKind>>

Retire ==
    /\ lnid # NoName
    /\ \A s \in Scopes : judged[s]
    /\ lnid' = NoName
    /\ UNCHANGED <<owns, bankMap, lbid, srcKind, judged, faultsIn>>

Next ==
    \/ \E s \in Scopes, p \in Points, n \in Names : ConfigOwn(s, p, n)
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
        (lnid # NoName /\ judged[s] /\ ~AnyMiss(s)) => faultsIn[s] = 0

\* ISA-3 후반 — 걸리면 반드시 밟는다. 무언 드롭 금지 (INV-T3).
Inv_MissAlwaysFaults ==
    \A s \in Scopes :
        (lnid # NoName /\ judged[s] /\ AnyMiss(s)) => faultsIn[s] >= 1

\* ISA-4 — 배달 범위마다 최대 1회. **두 조건을 다 밟아도 하나다.**
Inv_FaultAtMostOncePerScope == \A s \in Scopes : faultsIn[s] =< 1

(***************************************************************************)
(* 귀납 단계 — 범위 간 비간섭.                                             *)
(*                                                                         *)
(* 한 범위의 fault 수가 *그 범위의 지역 술어만*으로 완전히 결정된다면,     *)
(* 범위를 하나 더 쌓아도 새로운 상호작용이 생기지 않는다. 그 사실이 깊이   *)
(* 에 대한 귀납의 단계다 — 기저(Depth=1,2,3)에서 임의 깊이로 올린다.       *)
(***************************************************************************)
Inv_ScopeLocal ==
    \A s \in Scopes :
        (lnid # NoName /\ judged[s])
            => faultsIn[s] = (IF AnyMiss(s) THEN 1 ELSE 0)

(***************************************************************************)
(* 위험 도달성 증인                                                        *)
(*                                                                         *)
(* 증인은 **구성이 끝난 기계**에서 도달해야 뜻이 있다. 구성 전에는 모든     *)
(* 소유 집합과 사상표가 비어 있어 전부 fault 이므로(§1.5), 그 상태로        *)
(* 반증된 증인은 정본이 이미 자명하다고 선언한 것을 다시 말할 뿐이다.       *)
(* 적대 검증이 실측으로 잡은 지적이다.                                     *)
(***************************************************************************)
Configured(s) == ScopeUnion(s) # {} /\ bankMap # {}

Witness_NoClean == \A s \in Scopes : ~(judged[s] /\ lnid # NoName /\ ~AnyMiss(s))
\* **구성된** 기계에서 fault 가 나는가. 구성 전에는 전부 fault 이므로
\* (정본 §1.5) 그 상태로 반증하면 아무것도 뜻하지 않는다 — 적대 검증 지적.
Witness_NoFault ==
    \A s \in Scopes : ~(Configured(s) /\ faultsIn[s] > 0)

\* 지역 비소유가 실재하는가 — 없으면 global_judge 가드가 공허하다.
Witness_NoLocalNonOwnership ==
    \A s \in Scopes :
        (judged[s] /\ lnid # NoName /\ ~MissLnid(s)) => NonOwners(s, lnid) = {}

(***************************************************************************)
(* **두 조건을 동시에 밟는 토큰이 실재하는가.**                            *)
(*                                                                         *)
(* 이 증인이 반증되지 않으면 ISA-4 「최대 1회」는 검사할 것이 없다 —       *)
(* 두 번 발화할 상황 자체가 도달 불가능하다는 뜻이기 때문이다.             *)
(* 처음 판이 조건 하나만 모델링했을 때가 정확히 그 상태였다.               *)
(***************************************************************************)
Witness_NoDoubleMiss ==
    \A s \in Scopes :
        ~(judged[s] /\ lnid # NoName /\ Configured(s) /\ MissLnid(s) /\ MissLbid)

\* 무언 드롭이 **표현 가능한가.** loud_fault 가드를 지운 모델에서만 도달해야
\* 하며, 좋은 모델에서 도달 불가인 것이 곧 INV-T3 가 지켜진다는 뜻이다.
\* 이 증인이 없어서 Inv_MissAlwaysFaults 가 *어떤 형상에서도 반증 불가*
\* 였다 — README 교훈 ①(방어적 구성이 가드를 무력화)의 재발이었다.
Witness_NoSilentDrop ==
    \A s \in Scopes : ~(judged[s] /\ lnid # NoName /\ AnyMiss(s) /\ faultsIn[s] = 0)

=============================================================================
