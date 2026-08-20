\* SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
\* SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
--------------------------- MODULE ResultBank ---------------------------
(***************************************************************************)
(* FAB-3 · FAB-4 선-formal 모델 — 기입 자격과 소유 구간.                   *)
(*                                                                         *)
(* 정본 §2.7:                                                              *)
(*   FAB-3 기입 자격 — 결과 슬롯의 값은 그것을 바꿀 자격자가 존재하는       *)
(*         사이클에만 변한다.                                              *)
(*   FAB-4 소유 구간 — 생산자가 슬롯을 소유하는 구간 [t, t+L] (양끝 포함)  *)
(*         동안 다른 생산자는 그 슬롯에 기입하지 않는다.                   *)
(*                                                                         *)
(* 부록 D.5 우선순위 2번. 1번(FAB-2)과 마찬가지로 이 프로젝트가 실제로      *)
(* 여기서 무너졌다 — §2.4 함정: 기입 자격을 강제하던 실행 시점 검사가       *)
(* 어느 모듈 삭제와 함께 사라졌고 *정적 검사도 회귀도 전부 통과했다.*       *)
(* 남은 것은 다른 파일의 주석이 그 계약의 이름을 인용하고 있다는 사실뿐    *)
(* 이었다.                                                                 *)
(*                                                                         *)
(* §6.5.1 이 이 속성을 「좋은 속성의 본보기」로 든다 — 관측 가능한 대상과   *)
(* 조건만으로 쓰였고, *위반을 정의하며*, 구현을 규정하지 않는다.           *)
(*                                                                         *)
(* ## L 은 상수가 아니라 파라미터다 (§2.4)                                 *)
(*                                                                         *)
(* 구간의 양끝 포함은 정해졌으나 길이는 RTL 단계에서 측정과 함께 정한다.   *)
(* 모델은 임의의 L >= 0 에 대해 성립해야 한다 — 값을 미리 박으면 그 값이   *)
(* 모델의 결론에 섞여 들어간다. cfg 가 서로 다른 L 로 두 번 돌린다.        *)
(*                                                                         *)
(* 여기서 L 은 소유가 지속되는 *추가* 사이클 수다: 소유는 나이 0 에서       *)
(* 시작해 나이 L 까지 유효하므로 구간의 길이는 L+1 사이클이고, 그것이       *)
(* [t, t+L] 이 *양끝 포함*이라는 말의 내용이다.                            *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS
    Slots,           \* 결과 슬롯. 불투명 토큰 — 내부 구조 없음
    Producers,       \* 생산자. 불투명 토큰
    L,               \* 소유 구간 파라미터 (§2.4). 상수로 박지 않는다
    NoOwner,         \* 「소유자 없음」 표식. 모델 값으로 둔다 — `CHOOSE` 는
                     \* TLC 가 무계로 보고 평가하지 못한다 (실측)
    DisabledGuards

AllGuards == {"owner_check", "acquire_free", "interval_end"}
On(g) == g \notin DisabledGuards

\* 값은 추상이다. 바뀌었다는 *사실*만 관측하면 되므로 작은 순환 집합으로 둔다.
Values == 0..2

VARIABLES
    owner,       \* [Slots -> Producers \cup {NoOwner}]
    age,         \* [Slots -> 0..(L+1)]  소유 시작으로부터 지난 사이클.
                 \* L+1 까지 표현 가능해야 한다 — 그 값이 곧 「구간을 넘겼다」 이며,
                 \* 표현할 수 없으면 그 위반을 검출할 수도 없다 (아래 해설)
    val,         \* [Slots -> Values]
    lastWriter   \* [Slots -> Producers \cup {NoOwner}]  마지막으로 값을 바꾼 주체

vars == <<owner, age, val, lastWriter>>

TypeOK ==
    /\ owner \in [Slots -> Producers \cup {NoOwner}]
    /\ age \in [Slots -> 0..(L + 1)]
    /\ val \in [Slots -> Values]
    /\ lastWriter \in [Slots -> Producers \cup {NoOwner}]

Init ==
    /\ owner = [s \in Slots |-> NoOwner]
    /\ age = [s \in Slots |-> 0]
    /\ val = [s \in Slots |-> 0]
    /\ lastWriter = [s \in Slots |-> NoOwner]

(***************************************************************************)
(* 소유 획득.                                                              *)
(* 가드 acquire_free 를 지우면 이미 소유된 슬롯도 빼앗을 수 있다 —         *)
(* 구간 안에서 소유자가 바뀌므로 FAB-4 가 무너진다.                        *)
(***************************************************************************)
Acquire(p, s) ==
    /\ (owner[s] = NoOwner \/ ~On("acquire_free"))
    /\ owner' = [owner EXCEPT ![s] = p]
    /\ age'   = [age   EXCEPT ![s] = 0]
    \* 새 구간이 시작하면 기입자 기록도 새로 시작한다. `lastWriter` 는
    \* *현재 구간의* 기입자를 뜻하며, 구간을 넘어선 값은 의미가 없다 —
    \* 이것을 빠뜨렸더니 좋은 모델이 반증됐다 (아래 해설).
    /\ lastWriter' = [lastWriter EXCEPT ![s] = NoOwner]
    /\ UNCHANGED val

(***************************************************************************)
(* 기입.                                                                   *)
(* 가드 owner_check 가 FAB-3 그 자체다 — 지우면 자격자가 아닌 주체가       *)
(* (소유자가 아예 없는 슬롯에도) 값을 바꾼다.                              *)
(***************************************************************************)
Write(p, s, v) ==
    /\ (owner[s] = p \/ ~On("owner_check"))
    /\ v # val[s]                       \* 값이 실제로 바뀌는 기입만 본다
    /\ val'        = [val        EXCEPT ![s] = v]
    /\ lastWriter' = [lastWriter EXCEPT ![s] = p]
    /\ UNCHANGED <<owner, age>>

(***************************************************************************)
(* 사이클 경과.                                                            *)
(* 나이가 L 에 이르면 소유가 끝난다 — 양끝 포함이므로 나이 L 인 사이클     *)
(* 까지는 아직 소유 중이고, 그 다음에 놓는다.                              *)
(* 가드 interval_end 를 지우면 소유가 구간을 넘겨 지속된다.                *)
(***************************************************************************)
Tick(s) ==
    /\ owner[s] # NoOwner
    /\ IF age[s] >= L /\ On("interval_end")
         THEN /\ owner' = [owner EXCEPT ![s] = NoOwner]
              /\ age'   = [age   EXCEPT ![s] = 0]
         ELSE /\ owner' = owner
              \* 나이를 L 로 **캡하지 않는다.** 처음에는 방어적으로 캡했는데,
              \* 그 캡이 interval_end 가드가 막아야 할 상태 자체를 표현
              \* 불가능하게 만들어 가드 삭제 실험이 조용히 통과했다 (실측).
              \* 검출하려는 것을 표현할 수 없게 만드는 방어는 방어가 아니다.
              /\ age'   = [age EXCEPT ![s] = IF age[s] < L + 1 THEN age[s] + 1 ELSE age[s]]
    /\ UNCHANGED <<val, lastWriter>>

\* 소유가 하나도 없으면 어떤 동작도 열리지 않는 상태가 생길 수 있다.
\* FAB-2 모델과 같은 이유로 종료를 명시한다 — deadlock 검사를 살려 두기 위해서다.
Idle == /\ \A s \in Slots : owner[s] = NoOwner
        /\ UNCHANGED vars

Next ==
    \/ \E p \in Producers, s \in Slots : Acquire(p, s)
    \/ \E p \in Producers, s \in Slots, v \in Values : Write(p, s, v)
    \/ \E s \in Slots : Tick(s)
    \/ Idle

Spec == Init /\ [][Next]_vars /\ \A s \in Slots : WF_vars(Tick(s))

(***************************************************************************)
(* 불변식                                                                  *)
(***************************************************************************)

\* 소유 중인 슬롯의 나이는 구간을 넘지 않는다. [t, t+L] 양끝 포함의 상태 형태.
Inv_IntervalBounded == \A s \in Slots : age[s] =< L

\* 현재 구간에서 값을 바꾼 주체가 있다면 그 주체는 소유자여야 한다.
Inv_WriterWasOwner ==
    \A s \in Slots :
        (owner[s] # NoOwner /\ lastWriter[s] # NoOwner)
            => lastWriter[s] = owner[s]

(***************************************************************************)
(* FAB-3 그 자체 — **행위 속성**이다.                                      *)
(*                                                                         *)
(* "값이 바뀐다" 는 상태 하나로는 말할 수 없다. 두 상태를 비교해야 하므로  *)
(* 불변식이 아니라 [][...]_vars 형태로 적는다. §6.5 의 「전이 조건」 문체   *)
(* 이며, *허용되지 않는 변화를 함께 적는* 형태다.                          *)
(***************************************************************************)
Prop_WriteQualified ==
    [][ \A s \in Slots :
          (val'[s] # val[s]) => (owner[s] # NoOwner) ]_vars

\* FAB-4 — 소유 구간 동안 소유자가 바뀌지 않는다.
\* 구간이 끝나기 전에 owner 가 다른 생산자로 넘어가면 위반이다.
Prop_IntervalStable ==
    [][ \A s \in Slots :
          (owner[s] # NoOwner /\ age[s] < L /\ owner'[s] # owner[s])
              => owner'[s] = NoOwner ]_vars

(***************************************************************************)
(* 위험 도달성 증인 — 좋은 모델에서 반드시 반증돼야 한다.                  *)
(***************************************************************************)

\* 소유가 실제로 일어나는가.
Witness_NoOwnership == \A s \in Slots : owner[s] = NoOwner

\* 값이 실제로 바뀌는가 — 안 바뀌면 FAB-3 이 공허하다.
Witness_NoWrite == \A s \in Slots : lastWriter[s] = NoOwner

\* 구간이 실제로 끝까지 가는가 — 안 가면 interval_end 가드가 공허하다.
Witness_NoFullInterval == \A s \in Slots : age[s] < L

=============================================================================
