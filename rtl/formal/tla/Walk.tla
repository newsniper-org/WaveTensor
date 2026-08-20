\* SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
\* SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
--------------------------- MODULE Walk ---------------------------
(***************************************************************************)
(* EXT-1 · EXT-2 · EXT-3 선-formal 모델 — 확장 헤더 사슬의 순회와 검산.    *)
(*                                                                         *)
(*   EXT-1 순회 종료성 — 순회는 반드시 끝난다.                             *)
(*   EXT-2 종료 이후 무효과 — 종료 표식 뒤의 슬롯은 효과를 내지 않는다.    *)
(*   EXT-3 검산의 독립성 — 검산 셋은 서로 독립이다. 어느 하나를 무력화하면 *)
(*         나머지가 그 사실을 검출한다.                                    *)
(*                                                                         *)
(* ## EXT-3 은 검사들 *자신에 대한* 메타 속성이다                          *)
(*                                                                         *)
(* 앞의 모델들은 "기계가 계약을 지키는가" 를 물었다. EXT-3 은 다르다 —      *)
(* *검사가 서로를 대신하고 있지 않은가* 를 묻는다. 셋이 겹쳐 있어도 하나가  *)
(* 나머지에 함축되면 실제로는 둘뿐이고, 그 사실은 아무 테스트도 드러내지    *)
(* 않는다. 모든 테스트가 여전히 통과하기 때문이다.                         *)
(*                                                                         *)
(* 형식은 이렇게 잡는다: 각 검사를 하나씩 지웠을 때 *malformed 인 사슬이    *)
(* 통과하는가.* 지워도 아무것도 통과하지 않는다면 그 검사는 나머지에        *)
(* 함축된 것이고 — 독립이 아니다.                                          *)
(*                                                                         *)
(* 그래서 이 모델에서 네 가드가 한 불변식(Inv_SoundVerdict)을 공유하는 것은 *)
(* 결함이 아니라 *증명하려는 것 그 자체*다.                                *)
(*                                                                         *)
(* ## 종료 판정은 검사가 아니라 authority 다                               *)
(*                                                                         *)
(* §4.2.2 규범이 못박는 것: "종료는 종료 표식(END)이 정한다. 길이 필드는    *)
(* *검산*이다. 슬롯 상한은 *안전장치*다."                                  *)
(*                                                                         *)
(* 즉 END 는 나머지 둘이 *무엇에 대해* 검사하는지를 정하는 기준점이지,      *)
(* 그 자신이 거절자가 아니다. 그리고 그것이 §4.2.2 함정 —                   *)
(* "셋 중 어느 하나를 종료 판정에 쓰면 나머지 둘이 검사 기능을 잃는다" —   *)
(* 의 내용 전부다. 길이를 authority 로 쓰면 길이 검산이 자기 자신을         *)
(* 검사하게 되어 항진명제가 된다.                                          *)
(*                                                                         *)
(* ## 이 모델이 덮지 않는 것                                               *)
(*                                                                         *)
(*   ⚠️ 사슬은 초기 상태에서 통째로 정해진다 — 사슬이 순회 중에 바뀌는       *)
(*      경우(자기수정)는 없다. 명령 사슬은 읽기 전용이므로 손실이 없다.     *)
(*   ⚠️ 효과의 *내용*이 아니라 개수만 센다 — EXT-2 는 "효과가 없다" 이므로   *)
(*      개수로 족하다. 효과가 *틀린* 경우는 다른 축이다.                    *)
(*   ⚠️ EH 종류별 결합 규칙(§4.2.3)은 이 모델 밖이다.                       *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS
    Cap,            \* 슬롯 상한. 고정 순회의 횟수이기도 하다 (§4.3)
    DisabledGuards

AllGuards == {"end_authority", "len_check", "cap_check",
              "junk_check", "post_end_gated"}
On(g) == g \notin DisabledGuards

Slots == 1..Cap
\* eh   — 정의된 EH 종류
\* end  — 종료 표식
\* junk — 정의되지 않은 EH 종류 (§4.2.2 규범 3항: malformation)
Kinds == {"eh", "end", "junk"}

ASSUME Cap >= 2

VARIABLES
    chain,      \* [Slots -> Kinds]  읽기 전용. 초기 상태에서 정해진다
    declLen,    \* 0..Cap  길이 필드 선언값
    pc,         \* 0..Cap  순회 위치. 고정 순회이므로 언제나 Cap 까지 간다
    ended,      \* BOOLEAN  「이미 끝났다」 표시. 효과 게이팅의 유일한 근거
    effects,    \* 0..Cap   실제로 발생한 부수 효과 수
    verdict     \* {"none", "ok", "malformed"}

vars == <<chain, declLen, pc, ended, effects, verdict>>

TypeOK ==
    /\ chain \in [Slots -> Kinds]
    /\ declLen \in 0..Cap
    /\ pc \in 0..Cap
    /\ ended \in BOOLEAN
    /\ effects \in 0..Cap
    /\ verdict \in {"none", "ok", "malformed"}

(***************************************************************************)
(* 지상 진리 — 검사와 *무관하게* 정의된다.                                 *)
(*                                                                         *)
(* 이것이 이 모델에서 가장 중요한 한 줄이다. 적합성을 검사의 어휘로 적으면  *)
(* "검사를 통과한 것이 적합하다" 가 되어 아무것도 증명하지 못한다           *)
(* (Route.tla 의 M2 에서 실측한 자기지시 실패형).                          *)
(***************************************************************************)
EndPos ==
    IF \E i \in Slots : chain[i] = "end"
      THEN CHOOSE i \in Slots :
             chain[i] = "end" /\ \A j \in 1..(i - 1) : chain[j] # "end"
      ELSE 0

WellFormed ==
    /\ EndPos # 0                                     \* 끝이 있다
    /\ declLen = EndPos                               \* 선언과 실제가 맞는다
    /\ \A i \in 1..(EndPos - 1) : chain[i] = "eh"     \* 앞은 전부 정의된 종류

(***************************************************************************)
(* authority — 순회가 「끝났다」고 보는 자리.                              *)
(*                                                                         *)
(* end_authority 를 지우면 *길이 필드*가 그 자리를 정한다. 그 순간 길이     *)
(* 검산은 declLen = declLen 이 되어 항진명제가 된다 — §4.2.2 함정이 적은    *)
(* "나머지 둘이 검사 기능을 잃는다" 가 정확히 이 형태다.                   *)
(***************************************************************************)
Authority == IF On("end_authority") THEN EndPos ELSE declLen

(***************************************************************************)
(* 세 검산 (§4.2.2 규범).                                                  *)
(***************************************************************************)
RejLen  == On("len_check")  /\ Authority # 0 /\ declLen # Authority
RejCap  == On("cap_check")  /\ Authority = 0
RejJunk == On("junk_check") /\ \E i \in 1..(Authority - 1) : chain[i] = "junk"

Rejected == RejLen \/ RejCap \/ RejJunk

Init ==
    /\ chain \in [Slots -> Kinds]
    /\ declLen \in 0..Cap
    /\ pc = 0
    /\ ended = FALSE
    /\ effects = 0
    /\ verdict = "none"

(***************************************************************************)
(* 고정 순회 (§4.3).                                                       *)
(*                                                                         *)
(* 조기 탈출이 없다 — 종료 표식을 만나도 *계속 돈다.* 멈추는 것은 순회가    *)
(* 아니라 *효과*다. 그것이 §4.3 함정의 요건이며, 상수 시간 계약의 근거다.  *)
(*                                                                         *)
(* post_end_gated 를 지우면 종료 뒤의 슬롯도 효과를 낸다 — 명령의 의미가    *)
(* 사슬 뒤의 쓰레기에 의존하게 된다.                                       *)
(***************************************************************************)
Step ==
    /\ pc < Cap
    /\ pc' = pc + 1
    /\ ended' = (ended \/ chain[pc + 1] = "end")
    /\ effects' = IF (~ended \/ ~On("post_end_gated")) /\ chain[pc + 1] = "eh"
                    THEN effects + 1
                    ELSE effects
    /\ UNCHANGED <<chain, declLen, verdict>>

\* 순회가 끝난 뒤 한 번 판정한다.
Finish ==
    /\ pc = Cap
    /\ verdict = "none"
    /\ verdict' = IF Rejected THEN "malformed" ELSE "ok"
    /\ UNCHANGED <<chain, declLen, pc, ended, effects>>

\* 판정 이후 상태는 고정이다. 종료를 모델에 명시한다.
Done == /\ pc = Cap /\ verdict # "none"
        /\ UNCHANGED vars

Next == Step \/ Finish \/ Done

Spec == Init /\ [][Next]_vars

(***************************************************************************)
(* 불변식                                                                  *)
(***************************************************************************)

\* EXT-3 그 자체 — 통과했다면 적합했다.
\* 네 가드(authority + 검산 셋)가 이 하나를 공유하고, 어느 하나를 지워도
\* 깨진다는 사실이 곧 *넷 모두가 독립적으로 필요하다*는 증명이다.
Inv_SoundVerdict == verdict = "ok" => WellFormed

\* EXT-2 — 효과 수는 종료 표식 앞의 정의된 슬롯 수와 정확히 같다.
\* 순회는 Cap 까지 갔지만 효과는 거기서 멈춰 있어야 한다.
EffectiveSlots ==
    Cardinality({ i \in Slots : i =< pc /\ chain[i] = "eh"
                                /\ (EndPos = 0 \/ i < EndPos) })
Inv_NoPostEndEffect == effects = EffectiveSlots

\* EXT-1 — 순회는 상한을 넘지 않는다. 고정 횟수이므로 종료가 구조적이다.
Inv_WalkBounded == pc =< Cap

(***************************************************************************)
(* 위험 도달성 증인 — 좋은 모델에서 반드시 반증돼야 한다.                  *)
(***************************************************************************)

\* 통과와 거절이 둘 다 실재하는가 — 한쪽이 없으면 판정이 공허하다.
Witness_NoOk        == verdict # "ok"
Witness_NoMalformed == verdict # "malformed"

(***************************************************************************)
(* 독립성 증인 — EXT-3 의 직접 형태.                                       *)
(*                                                                         *)
(* 「이 검사 *하나만* 잡아내는 사슬이 존재하는가」. 존재하지 않으면 그       *)
(* 검사는 나머지에 함축된 것이고 독립이 아니다. 셋 다 반증돼야 한다.        *)
(***************************************************************************)
Witness_NoLenOnly  == ~(RejLen  /\ ~RejCap /\ ~RejJunk)
Witness_NoCapOnly  == ~(RejCap  /\ ~RejLen /\ ~RejJunk)
Witness_NoJunkOnly == ~(RejJunk /\ ~RejLen /\ ~RejCap)

\* 종료 표식 *뒤에* 슬롯이 실제로 있는가 — 없으면 post_end_gated 가 공허하다.
Witness_NoPostEndSlot ==
    \A i \in Slots : EndPos = 0 \/ i =< EndPos \/ pc < i

=============================================================================
