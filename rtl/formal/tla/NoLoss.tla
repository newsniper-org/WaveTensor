\* SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
\* SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
--------------------------- MODULE NoLoss ---------------------------
(***************************************************************************)
(* SEC-3 선-formal 모델 — 무소실 (loud-fault-never-silent 의 형식화).      *)
(*                                                                         *)
(* 정본 §5.7:                                                              *)
(*   SEC-3 무소실 — 어떤 요청도 상태 비트를 세우지 않고 사라지지 않는다.   *)
(*                                                                         *)
(* ## ISA-9 회계 축도 이 모델의 몫이다 (§1.4.2 · §1.8) — 사상 명시          *)
(*                                                                         *)
(* ISA-9 토큰 비증식(발화당 후속 논리 결과 최대 1)의 *회계 축* — 「파이프    *)
(* 안에서 늘지 않는다」 — 는 새 모델이 아니라 이 모델의 기존 속성 둘의       *)
(* 합성이다:                                                               *)
(*                                                                         *)
(*   Inv_NoPhantom     completed + faulted <= entered — 처분 총량이 도착    *)
(*                     총량을 넘지 않는다. complete_once 삭제(한 완료의     *)
(*                     과잉 계수 = 증식의 회계 형태)가 이것을 반증한다.     *)
(*   Inv_Conservation  등식이 위 상한과 만나면 파이프 안(InPipe)도 도착분   *)
(*                     을 넘지 못한다 — 단 사이 이동(AdvanceN·W)은 옮길 뿐  *)
(*                     만들지 않는다.                                      *)
(*                                                                         *)
(* §1.8 이 적은 쌍대 그대로다: SEC-3 은 「줄지 않는다」, ISA-9 회계 축은     *)
(* 「늘지 않는다」 — 같은 보존 등식의 두 방향이다.                          *)
(*                                                                         *)
(* 이 모델이 지는 것은 *총량* 형태까지다 — 요청에 정체성이 없으므로 발화    *)
(* 개별의 「최대 1」은 여기 없다. 수락 축(토큰 1 → 수락 <= 1)은 Route        *)
(* (Inv_UniqueOwnerPerScope + 진입점 범위당 1회 원자 판정)가, 「조각열은     *)
(* 하나로 센다」(§1.4.2)는 Payload(Deliver 의 ~outValid 게이트 +            *)
(* Inv_ReassemblyExclusive + Inv_NoStaleRedeliver)가 맡는다. 모듈 경계를    *)
(* 가로지르는 합성 축은 후-formal 몫이다 (부록 D 사상 등재는 통합자).       *)
(*                                                                         *)
(* ## FAB-2 와 무엇이 다른가                                               *)
(*                                                                         *)
(* FAB-2 는 *한 공유 유닛*에서 무처분이 없음을 말한다. SEC-3 은 그 상위     *)
(* 형태로 *기계 전체의 회계*를 말한다 — 들어온 것이 끝난 것 · fault 난 것 · *)
(* 아직 안에 있는 것의 합과 같아야 한다. 유닛마다 처분이 있어도 유닛        *)
(* *사이*에서 새면 SEC-3 은 깨진다.                                        *)
(*                                                                         *)
(* 그래서 이 모델은 개수를 센다. 계약이 "사라지지 않는다" 이므로 형식은     *)
(* 보존 등식이어야 한다 (@sec:formal 6.5 「불변식」 문체).                  *)
(*                                                                         *)
(* ## 서문 §0.8 이 적은 네 실패형이 전부 여기에 있다                       *)
(*                                                                         *)
(*   조용한 드롭      — 자리가 없을 때 요청이 처분 없이 사라진다            *)
(*   조용한 덮어쓰기  — 자리 검사 없이 받아 이미 있던 것을 지운다           *)
(*   조용한 절단      — 넓은 값이 좁은 통로를 *통과해 버린다*               *)
(*   조용한 완료 조작 — 없던 완료를 만들어 손실을 가린다                    *)
(*                                                                         *)
(* 앞의 둘은 개수를 줄이고 마지막은 개수를 늘린다. 둘 다 회계 위반이며,     *)
(* *늘리는 쪽이 더 위험하다* — 손실을 덮기 때문이다.                        *)
(*                                                                         *)
(* ## 이 모델이 덮지 않는 것                                               *)
(*                                                                         *)
(*   ⚠️ 요청에 정체성이 없다 — 개수만 센다. "A 가 사라지고 B 가 두 번        *)
(*      완료됐다" 는 보존 등식을 만족하므로 이 모델은 보지 못한다.          *)
(*      그 축은 태그 유일성(EXT-4 재조립 배타성)이 맡는다.                  *)
(*   ⚠️ 진행성이 없다 — 요청이 영원히 파이프 안에 머물러도 보존은 성립한다.  *)
(*      "사라지지 않는다" 와 "언젠가 끝난다" 는 다른 명제다. 후자는          *)
(*      진행성 속성이며 이 모델의 대상이 아니다.                            *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS
    Depth,        \* 단 수. 요청은 1단에서 들어와 Depth 단에서 나간다
    Cap,          \* 단별 수용량
    MaxReq,       \* 유한화를 위한 총 도착 상한. 모델 유한성의 유일한 목적
    NoW,          \* 「관측 없음」 표식 (모델 값)
    DisabledGuards

AllGuards == {"queue_room", "busy_loud", "fault_sticky",
              "width_checked", "complete_once", "advance_atomic"}
On(g) == g \notin DisabledGuards

Stages == 1..Depth
Widths == {"narrow", "wide"}

\* 통로는 좁다. 넓은 값이 여기 들어오면 그 자체가 절단이다.
ASSUME Depth >= 1 /\ Cap >= 1 /\ MaxReq >= Depth

VARIABLES
    entered,    \* 지금까지 *도착한* 요청 수. 회계의 좌변
    stageN,     \* [Stages -> 0..Cap]  각 단이 든 좁은 요청 수
    stageW,     \* [Stages -> 0..Cap]  각 단이 든 넓은 요청 수 — 절단의 증거
    completed,  \* 정상 완료 수
    faulted,    \* fault 처분을 받은 수
    wideFaulted,\* 그중 *넓은 폭*을 이유로 거절된 수 — fault 원인 기록에 해당
    faultBit,   \* sticky fault 비트 (§1.6.3 · ISA-6 · §5.5)
    obsIn,      \* 직전 완료된 요청이 *들어올 때* 가졌던 폭
    obsOut      \* 그 요청이 *나갈 때* 가진 폭. 통로가 좁으므로 언제나 narrow

vars == <<entered, stageN, stageW, completed, faulted, wideFaulted,
          faultBit, obsIn, obsOut>>

TypeOK ==
    /\ entered \in 0..MaxReq
    /\ stageN \in [Stages -> 0..Cap]
    /\ stageW \in [Stages -> 0..Cap]
    \* completed 의 상한을 MaxReq 로 조이지 *않는다.* complete_once 를 지웠을
    \* 때 생기는 과잉 계수가 표현 가능해야 Inv_NoPhantom 이 그것을 잡는다.
    \* 검출하려는 것을 표현할 수 없게 만드는 방어는 방어가 아니다 (ResultBank 실측).
    /\ completed \in 0..(2 * MaxReq)
    /\ faulted \in 0..MaxReq
    /\ wideFaulted \in 0..MaxReq
    /\ faultBit \in BOOLEAN
    /\ obsIn \in Widths \cup {NoW}
    /\ obsOut \in Widths \cup {NoW}

\* 파이프 안에 남아 있는 수. 보존 등식의 우변 셋째 항.
InPipe ==
    LET f[i \in 0..Depth] ==
        IF i = 0 THEN 0 ELSE f[i - 1] + stageN[i] + stageW[i]
    IN f[Depth]

Room(i) == stageN[i] + stageW[i] < Cap

Init ==
    /\ entered = 0
    /\ stageN = [i \in Stages |-> 0]
    /\ stageW = [i \in Stages |-> 0]
    /\ completed = 0
    /\ faulted = 0
    /\ wideFaulted = 0
    /\ faultBit = FALSE
    /\ obsIn = NoW
    /\ obsOut = NoW

\* fault 처분. sticky 가 이 처분의 *관측 가능성* 전부다 —
\* 비트가 남지 않으면 fault 는 일어난 적 없는 것과 구별되지 않는다.
RaiseFault(wide) ==
    /\ faulted' = faulted + 1
    /\ wideFaulted' = IF wide THEN wideFaulted + 1 ELSE wideFaulted
    /\ faultBit' = IF On("fault_sticky") THEN TRUE ELSE FALSE

(***************************************************************************)
(* 도착.                                                                   *)
(*                                                                         *)
(* 세 갈래다: 자리가 있으면 받고, 없으면 처분하고, 넓으면 거절한다.        *)
(* 세 갈래 전부가 회계에 기록돼야 한다는 것이 SEC-3 의 내용이다.           *)
(*                                                                         *)
(*   width_checked  지우면 넓은 값이 좁은 통로에 들어간다 → 조용한 절단     *)
(*   queue_room     지우면 가득 찬 단에 덮어쓴다 → 조용한 덮어쓰기          *)
(*   busy_loud      지우면 자리 없는 요청이 처분 없이 사라진다 → 조용한 드롭 *)
(***************************************************************************)
Arrive(w) ==
    /\ entered < MaxReq
    /\ entered' = entered + 1
    /\ IF w = "wide" /\ On("width_checked")
         THEN \* 넓은 값은 통로 앞에서 loud 하게 거절된다.
              /\ RaiseFault(TRUE)
              /\ UNCHANGED <<stageN, stageW, completed>>
         ELSE IF Room(1) \/ ~On("queue_room")
                THEN \* 받는다. 자리 검사를 지웠다면 가득 찬 단에 *덮어쓴다* —
                     \* 수용량이 상한이므로 개수가 늘지 않고, 그 순간 안에
                     \* 있던 요청 하나가 회계에서 사라진다.
                     /\ IF w = "wide"
                          THEN /\ stageW' = [stageW EXCEPT ![1] =
                                               IF @ < Cap THEN @ + 1 ELSE @]
                               /\ UNCHANGED stageN
                          ELSE /\ stageN' = [stageN EXCEPT ![1] =
                                               IF @ < Cap THEN @ + 1 ELSE @]
                               /\ UNCHANGED stageW
                     /\ UNCHANGED <<completed, faulted, wideFaulted, faultBit>>
                ELSE IF On("busy_loud")
                       THEN \* 자리가 없으면 *처분한다.* 무처분이 아니다.
                            /\ RaiseFault(FALSE)
                            /\ UNCHANGED <<stageN, stageW, completed>>
                       ELSE \* 처분 없이 사라진다 — 공유 디코더 실패형 그 자체.
                            UNCHANGED <<stageN, stageW, completed,
                                        faulted, wideFaulted, faultBit>>
    /\ UNCHANGED <<obsIn, obsOut>>

(***************************************************************************)
(* 단 사이 이동. 여기서 새면 유닛마다 처분이 있어도 SEC-3 은 깨진다.       *)
(*                                                                         *)
(* advance_atomic 가드는 *2차 적대 검증의 산물*이다. 처음 판은 이동을        *)
(* `@ - 1, ![i+1] = @ + 1` 한 동작으로 적었고, 그러면 단 사이 소실이         *)
(* *구조적으로 표현 불가능*해진다 — 지울 가드가 없으므로 가드 삭제 실험이   *)
(* 그 결함형을 영원히 못 본다. Route.tla 의 M3(뷰가 변수가 아니라 정의)와    *)
(* 같은 형태이며, README 교훈 ② 그 자체다.                                  *)
(***************************************************************************)
AdvanceN(i) ==
    /\ i < Depth
    /\ stageN[i] > 0
    /\ Room(i + 1)
    /\ stageN' = IF On("advance_atomic")
                   THEN [stageN EXCEPT ![i] = @ - 1, ![i + 1] = @ + 1]
                   ELSE [stageN EXCEPT ![i] = @ - 1]   \* 떠났는데 도착 안 함
    /\ UNCHANGED <<entered, stageW, completed, faulted, wideFaulted, faultBit, obsIn, obsOut>>

AdvanceW(i) ==
    /\ i < Depth
    /\ stageW[i] > 0
    /\ Room(i + 1)
    /\ stageW' = IF On("advance_atomic")
                   THEN [stageW EXCEPT ![i] = @ - 1, ![i + 1] = @ + 1]
                   ELSE [stageW EXCEPT ![i] = @ - 1]
    /\ UNCHANGED <<entered, stageN, completed, faulted, wideFaulted, faultBit, obsIn, obsOut>>

(***************************************************************************)
(* 완료 — 유일한 출구.                                                     *)
(*                                                                         *)
(* complete_once 를 지우면 완료가 두 번 세어진다. 개수가 *늘어나는* 위반    *)
(* 이며, 손실을 덮는다 — 하나 잃고 하나 두 번 세면 보존 등식이 다시         *)
(* 맞는다. 그래서 이 가드는 다른 넷과 방향이 반대이지만 같은 계약을 지킨다. *)
(*                                                                         *)
(* 통로는 좁다. 나가는 폭은 언제나 narrow 이므로, 넓은 값이 안에 있었다면   *)
(* 그 사실이 여기서 obsIn # obsOut 로 드러난다.                            *)
(***************************************************************************)
CompleteN ==
    /\ stageN[Depth] > 0
    /\ stageN' = [stageN EXCEPT ![Depth] = @ - 1]
    /\ completed' = IF On("complete_once") THEN completed + 1 ELSE completed + 2
    /\ obsIn' = "narrow"
    /\ obsOut' = "narrow"
    /\ UNCHANGED <<entered, stageW, faulted, wideFaulted, faultBit>>

CompleteW ==
    /\ stageW[Depth] > 0
    /\ stageW' = [stageW EXCEPT ![Depth] = @ - 1]
    /\ completed' = completed + 1
    /\ obsIn' = "wide"
    /\ obsOut' = "narrow"        \* 통로가 좁다 — 이 어긋남이 곧 절단이다
    /\ UNCHANGED <<entered, stageN, faulted, wideFaulted, faultBit>>

\* 모든 요청이 도착했고 파이프가 비면 어떤 동작도 열리지 않는다.
\* 종료를 모델에 명시한다 — deadlock 검사를 끄지 않기 위해서다.
Idle == /\ entered = MaxReq /\ InPipe = 0
        /\ UNCHANGED vars

Next ==
    \/ \E w \in Widths : Arrive(w)
    \/ \E i \in Stages : AdvanceN(i)
    \/ \E i \in Stages : AdvanceW(i)
    \/ CompleteN
    \/ CompleteW
    \/ Idle

Spec == Init /\ [][Next]_vars

(***************************************************************************)
(* 불변식                                                                  *)
(***************************************************************************)

\* SEC-3 그 자체 — 회계가 맞는다.
\* 좌변은 도착 수, 우변은 처분된 것과 아직 안에 있는 것.
Inv_Conservation == entered = completed + faulted + InPipe

\* fault 가 *관측 가능한 흔적*을 남긴다. sticky 가 아니면 fault 는
\* 일어난 적 없는 것과 구별되지 않고, 그 구별 불가가 곧 「조용함」이다.
Inv_FaultVisible == faulted > 0 => faultBit

\* 조용한 절단 금지 — 나간 폭이 들어온 폭과 같다.
Inv_NoSilentTruncation == obsIn = NoW \/ obsIn = obsOut

\* 없던 완료를 만들지 않는다. 회계의 상한.
Inv_NoPhantom == completed + faulted =< entered

(***************************************************************************)
(* 위험 도달성 증인 — 좋은 모델에서 반드시 반증돼야 한다.                  *)
(***************************************************************************)

\* 완료가 실제로 일어나는가 — 안 일어나면 회계가 공허하다.
Witness_NoCompletion == completed = 0

\* fault 가 실제로 일어나는가.
Witness_NoFault == faulted = 0

\* **단이 실제로 가득 차는가.** 안 차면 queue_room·busy_loud 가드가
\* 막아야 할 상황 자체가 도달 불가이고, 두 가드는 아무것도 막지 않는다.
Witness_NoFullStage == \A i \in Stages : Room(i)

\* **넓은 요청이 실제로 폭 검사에 걸리는가.** 안 걸리면 width_checked 가
\* 공허하고, Inv_NoSilentTruncation 은 아무것도 뜻하지 않는다.
\* 좋은 모델에서 넓은 요청은 거절되어 파이프에 흔적을 남기지 않으므로,
\* 거절 자체를 원인별로 세지 않으면 이 증인을 세울 수 없다.
Witness_NoWideRejection == wideFaulted = 0

=============================================================================
