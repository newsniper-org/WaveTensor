\* SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
\* SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
--------------------------- MODULE SharedUnit ---------------------------
(***************************************************************************)
(* FAB-2 선-formal 모델 — 공유 자원 배타성과 「무처분 없음」.               *)
(*                                                                         *)
(* 정본 `docs/wt64v1-architecture-guide` §2.7:                             *)
(*                                                                         *)
(*   FAB-2 공유 자원 배타성 — 공유 유닛은 어느 시점에도 최대 하나의 요청을 *)
(*   처리한다. 점유 중 도착한 요청은 규정된 처분(대기/거절/오류) 중 하나를 *)
(*   *반드시* 받는다 — **무처분이 없다.**                                  *)
(*                                                                         *)
(* 이 속성이 부록 D.5 우선순위 1번인 이유는 이 프로젝트가 실제로 여기서    *)
(* 무너졌기 때문이다 (§2.2 함정): 공유 디코더가 점유 중일 때 도착한 명령이 *)
(* **어떤 오류 비트도 세우지 않고 사라졌다.** 명세에 그 경우가 없었기       *)
(* 때문이다. 그것이 §6.2 가 "명세의 공백은 구현으로 메워진다" 로 부르는    *)
(* 실패형의 원형이다.                                                      *)
(*                                                                         *)
(* 처분은 **대기**로 확정됐다 (§2.2 「처분 확정」). 따라서 이 모델은        *)
(* 보류 자원 + 배압 + 배압 위반 시 loud fault 를 표현한다.                 *)
(*                                                                         *)
(* 모델링 규약 (§6.7 해설): 상수를 유한·소형으로 유지한다. 요청자는        *)
(* **불투명 토큰**이며 내부 구조가 없다 — 그 제약이 좋은 인코딩을 강제하고,*)
(* ISA 를 형상 독립으로 만든 근거와 같은 방향이다.                         *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets, Sequences

CONSTANTS
    Requesters,      \* 불투명 토큰 집합. 내부 구조 없음
    QueueDepth,      \* 보류 자원 깊이 — 구현 파라미터 (깊이 0 도 적법)
    DisabledGuards   \* 가드 삭제 실험용. 좋은 모델에서는 {}

(***************************************************************************)
(* 가드 — §6.3.2 「속성의 유효성 증명」의 대상.                            *)
(*                                                                         *)
(* 각 보호 조건을 지운 모델이 속성을 위반하는지 확인한다. 지워도 통과하는  *)
(* 가드는 *불필요하거나 속성이 부실하거나* 둘 중 하나이며, 어느 쪽인지     *)
(* 판정하기 전에는 그 가드를 검증됐다고 하지 않는다.                       *)
(***************************************************************************)
AllGuards == {"busy_check", "queue_room", "backpressure"}
On(g) == g \notin DisabledGuards

Dispositions == {"idle", "queued", "serving", "done", "backpressured"}

VARIABLES
    serving,   \* 지금 처리 중인 요청자 **집합**. 배타성은 불변식이지 구조가 아니다
    queue,     \* 보류 열
    disp,      \* [Requesters -> Dispositions] — 각 요청이 받은 처분
    arrived    \* 도착한 적이 있는 요청자

vars == <<serving, queue, disp, arrived>>

Range(s) == { s[i] : i \in 1..Len(s) }

\* `queue \in Seq(Requesters)` 로 적으면 TLC 가 검사할 수 없다 — Seq 는 무한
\* 집합이다. 유계 형태로 적는 것이 모델을 작게 유지하는 규율의 일부다 (§6.7).
TypeOK ==
    /\ serving \subseteq Requesters
    /\ Range(queue) \subseteq Requesters
    /\ Len(queue) =< QueueDepth
    /\ disp \in [Requesters -> Dispositions]
    /\ arrived \subseteq Requesters

Init ==
    /\ serving = {}
    /\ queue = <<>>
    /\ disp = [r \in Requesters |-> "idle"]
    /\ arrived = {}

(***************************************************************************)
(* 요청 도착.                                                              *)
(*                                                                         *)
(* `arrived` 는 **모든 분기에서** 갱신된다 — 그것이 이 모델의 핵심이다.    *)
(* 도착 사실은 처분과 무관하게 기록되므로, 처분을 빠뜨린 경로는 반드시     *)
(* Inv_NoUndisposed 로 드러난다.                                           *)
(***************************************************************************)
Arrive(r) ==
    /\ disp[r] \in {"idle", "backpressured"}   \* 배압 뒤 재시도는 정상 경로
    /\ arrived' = arrived \cup {r}
    /\ \/ \* 유닛이 비어 있으면 곧바로 처리한다.
          \* 가드 busy_check 를 지우면 점유 중에도 이 분기가 열린다.
          /\ (serving = {} \/ ~On("busy_check"))
          /\ serving' = serving \cup {r}
          /\ disp'    = [disp EXCEPT ![r] = "serving"]
          /\ queue'   = queue
       \/ \* 점유 중 — 보류 자원에 자리가 있으면 대기시킨다.
          \* 가드 queue_room 을 지우면 자리가 없어도 밀어 넣고, 가장 오래된
          \* 항목이 조용히 덮어써진다 (고정 깊이 버퍼의 실제 동작).
          /\ serving # {}
          /\ (Len(queue) < QueueDepth \/ ~On("queue_room"))
          /\ queue'   = IF Len(queue) < QueueDepth
                          THEN Append(queue, r)
                          ELSE Append(Tail(queue), r)
          /\ disp'    = [disp EXCEPT ![r] = "queued"]
          /\ serving' = serving
       \/ \* 점유 중이고 보류 자원도 가득 — **배압**이다. 오류가 아니다.
          \* 가드 backpressure 를 지우면 요청이 아무 표시 없이 사라진다:
          \* 이것이 참조 구현에서 실제로 일어난 그 경로다.
          /\ serving # {}
          /\ Len(queue) >= QueueDepth
          /\ On("queue_room")
          /\ queue'   = queue
          /\ serving' = serving
          /\ disp'    = IF On("backpressure")
                          THEN [disp EXCEPT ![r] = "backpressured"]
                          ELSE disp

\* 유닛이 비면 보류 열에서 하나를 꺼내 처리한다.
Dequeue ==
    /\ serving = {}
    /\ Len(queue) > 0
    /\ serving' = {Head(queue)}
    /\ disp'    = [disp EXCEPT ![Head(queue)] = "serving"]
    /\ queue'   = Tail(queue)
    /\ UNCHANGED arrived

Complete(r) ==
    /\ r \in serving
    /\ serving' = serving \ {r}
    /\ disp'    = [disp EXCEPT ![r] = "done"]
    /\ UNCHANGED <<queue, arrived>>

(***************************************************************************)
(* 종료를 **모델에 명시**한다.                                             *)
(*                                                                         *)
(* 모든 요청이 처리를 마치면 어떤 동작도 열리지 않는다. 그것은 정당한      *)
(* 종료지만 TLC 에게는 deadlock 으로 보인다. 여기서 `CHECK_DEADLOCK FALSE` *)
(* 로 검사를 꺼 버리면 *의도치 않은* 교착까지 함께 못 잡게 된다 — 검사를   *)
(* 약화시켜 통과시키는 것은 이 프로젝트가 경계하는 습관 그대로다.          *)
(* 대신 종료 조건을 명시적 stuttering 으로 적어, deadlock 검사가 나머지    *)
(* 전부에 대해 살아 있게 한다.                                             *)
(***************************************************************************)
AllSettled == \A r \in Requesters : disp[r] = "done"
Terminated == AllSettled /\ UNCHANGED vars

Next ==
    \/ \E r \in Requesters : Arrive(r)
    \/ \E r \in Requesters : Complete(r)
    \/ Dequeue
    \/ Terminated

Spec ==
    /\ Init
    /\ [][Next]_vars
    /\ WF_vars(Dequeue)
    /\ \A r \in Requesters : WF_vars(Complete(r))

(***************************************************************************)
(* 불변식 — 정본 §6.5 문체: 관측 가능한 대상과 조건만으로 쓰고, **위반을   *)
(* 정의한다**.                                                             *)
(***************************************************************************)

\* FAB-2 전반부: 공유 유닛은 어느 시점에도 최대 하나를 처리한다.
Inv_Exclusive == Cardinality(serving) =< 1

\* FAB-2 후반부 — **이 모델의 존재 이유**.
\* 도착한 요청은 반드시 어떤 처분을 받는다. "idle" 로 남아 있다는 것은
\* 도착했는데 아무 일도 일어나지 않았다는 뜻이고, 그것이 무처분이다.
Inv_NoUndisposed == \A r \in arrived : disp[r] # "idle"

\* 대기 처분을 받은 요청은 실제로 보류 열에 있어야 한다. 처분만 기록하고
\* 자원에 넣지 않으면 그 요청은 영원히 오지 않는다 — 조용한 소실이다.
Inv_NoLoss == \A r \in Requesters : (disp[r] = "queued") => (r \in Range(queue))

\* 처리 중이라고 표시된 것과 실제로 처리 중인 것이 일치해야 한다.
Inv_ServingAgrees == \A r \in Requesters : (disp[r] = "serving") <=> (r \in serving)

(***************************************************************************)
(* 진행성 (FAB-6 의 이 지점에서의 형태).                                   *)
(* 배압이 영구히 유지되지 않는 한, 대기 중인 요청은 결국 처리된다.         *)
(***************************************************************************)
Prop_Progress == \A r \in Requesters : (disp[r] = "queued") ~> (disp[r] = "done")

(***************************************************************************)
(* 위험 도달성 증인 — 좋은 모델에서 **반드시 반증돼야 한다**.              *)
(*                                                                         *)
(* 좋은 모델이 통과하는 이유가 "계약이 위험을 담고 있어서" 인지 "설정이    *)
(* 그 위험을 한 번도 만들지 않아서" 인지를 가른다. 후자면 그 통과는        *)
(* 아무것도 뜻하지 않는다 — §6.7 이 지목한 "조건이 안 맞으면 스스로        *)
(* 건너뛰고 통과로 보고하는" 검사와 같은 형태다.                           *)
(***************************************************************************)

\* 경합이 실제로 일어나는가 — 점유 중 도착해 대기한 요청이 있는가.
Witness_NoQueueing == \A r \in Requesters : disp[r] # "queued"

\* 보류 자원이 실제로 가득 차는가 — 배압 경로가 도달 가능한가.
\* 이것이 반증되지 않으면 backpressure 가드는 공허하다.
Witness_NoBackpressure == \A r \in Requesters : disp[r] # "backpressured"

\* 처리가 실제로 끝나는가 — 진행 경로가 도달 가능한가.
Witness_NoCompletion == \A r \in Requesters : disp[r] # "done"

=============================================================================
