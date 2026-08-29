\* SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
\* SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
--------------------------- MODULE XlateStore ---------------------------
(***************************************************************************)
(* HIU-1 · HIU-2 · HIU-3 · HIU-4 선-formal 모델 — 변환 저장 블록.          *)
(*                                                                         *)
(* 넷을 한 모델에 두는 이유는 넷이 *같은 구조 위의 성질*이기 때문이다.     *)
(* 따로 쓰면 저장 블록을 네 번 모델링하게 되고, 그 네 벌이 드리프트한다.   *)
(*                                                                         *)
(*   HIU-1 파티션 격리 — 파티션 p 의 요청이 q != p 가 설치한 항목으로      *)
(*         적중하는 일은 없다.                                             *)
(*   HIU-2 flush 후 미적중 — 컨텍스트 전환 이후 이전 컨텍스트가 설치한     *)
(*         어떤 항목도 적중하지 않는다. *저장 블록에 데이터가 남아 있음에도.* *)
(*   HIU-3 유효 게이팅 전수 — 저장 블록에서 값을 읽는 모든 경로가 유효     *)
(*         비트로 게이트된다. 게이트되지 않은 경로가 하나라도 있으면 위반. *)
(*   HIU-4 적중 유일성 — 하나의 요청에 대해 적중하는 항목은 최대 하나.     *)
(*                                                                         *)
(* ## 이 모델의 핵심 — 데이터는 남는다                                     *)
(*                                                                         *)
(* 정본 §3.6.3 이 이 장에서 가장 중요한 규범이라고 적는 것:                *)
(*                                                                         *)
(*   컨텍스트 전환 시 flush 는 *유효 비트만* 지운다. 저장 블록의 태그·변환 *)
(*   데이터는 지워지지 않는다 — reset 이 없는 저장이므로 지울 수단이 없고, *)
(*   지울 필요도 없다. ⇒ *유효 비트가 유일한 방벽이다.*                    *)
(*                                                                         *)
(* 그래서 이 모델은 flush 가 데이터를 *남기도록* 만든다. 데이터를 함께     *)
(* 지우는 모델은 HIU-2 를 자명하게 통과시키고, 그 통과는 아무것도 뜻하지   *)
(* 않는다. 증인 하나가 "데이터가 실제로 남는가" 를 따로 확인한다.          *)
(*                                                                         *)
(* ## HIU-3 은 여기서 끝나지 않는다                                        *)
(*                                                                         *)
(* §3.12 함정: "모든 읽기 경로" 는 유한하고 열거 가능하므로 이 속성은      *)
(* *정적 검사로 완전히 확인할 수 있다.* 이 모델은 게이팅이 **있을 때**     *)
(* 격리가 성립함을 보이고, 구현에 그 게이팅이 **빠짐없이** 있는지는        *)
(* `scripts/lint_hiu3_valid_gating.py` 가 센다. 둘이 함께여야 완결된다.    *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS
    Partitions,      \* 격리 단위. 불투명 토큰
    Indices,         \* 직접 사상 색인. 항목 주소는 {파티션, 색인} 연접이다 (§3.6.1)
    Tags,            \* 가상 주소 상위. 불투명 토큰
    NoPart,          \* 「설치자 없음」 표식 (모델 값)
    DisabledGuards

AllGuards == {"valid_check", "partition_check", "flush_keeps_data"}
On(g) == g \notin DisabledGuards

Entries == Partitions \X Indices

VARIABLES
    valid,      \* [Entries -> BOOLEAN]   유일한 방벽
    tag,        \* [Entries -> Tags]      flush 가 지우지 않는다
    installer,  \* [Entries -> Partitions \cup {NoPart}]  누가 설치했나. flush 가 지우지 않는다
    hitEntry,   \* 직전 조회가 **값을 읽어 돌려준 항목**. None = 미적중
    reqPart     \* 그 조회를 낸 파티션. None = 조회가 없었음
                \* 둘 다 조회가 아닌 동작에서 **소비된다** — 남겨 두면 후속
                \* 단계에서 낡은 관측이 속성을 다시 걸어 거짓 반례를 만든다 (실측)

vars == <<valid, tag, installer, hitEntry, reqPart>>

TypeOK ==
    /\ valid \in [Entries -> BOOLEAN]
    /\ tag \in [Entries -> Tags]
    /\ installer \in [Entries -> Partitions \cup {NoPart}]
    /\ hitEntry \in Entries \cup {NoPart}
    /\ reqPart \in Partitions \cup {NoPart}

SomeTag == CHOOSE t \in Tags : TRUE

Init ==
    /\ valid = [e \in Entries |-> FALSE]
    /\ tag = [e \in Entries |-> SomeTag]
    /\ installer = [e \in Entries |-> NoPart]
    /\ hitEntry = NoPart
    /\ reqPart = NoPart

(***************************************************************************)
(* 항목 설치 — 호스트가 기입한다 (부록 E.3: 채움 주체는 호스트).           *)
(***************************************************************************)
Install(p, i, t) ==
    /\ valid'     = [valid     EXCEPT ![<<p, i>>] = TRUE]
    /\ tag'       = [tag       EXCEPT ![<<p, i>>] = t]
    /\ installer' = [installer EXCEPT ![<<p, i>>] = p]
    /\ hitEntry' = NoPart
    /\ reqPart'  = NoPart

(***************************************************************************)
(* 컨텍스트 전환 flush — **유효 비트만** 지운다 (§3.6.3).                  *)
(*                                                                         *)
(* 가드 flush_keeps_data 를 지우면 데이터까지 지우는 모델이 된다. 그러면   *)
(* HIU-2 는 여전히 통과하지만 *자명하게* 통과한다 — 그 통과는 유효 비트가  *)
(* 방벽이라는 사실을 아무것도 증명하지 않는다. 그래서 이 가드의 삭제는     *)
(* 불변식이 아니라 **증인**으로 잡는다 (아래 Witness_DataSurvivesFlush).   *)
(***************************************************************************)
Flush(p) ==
    /\ valid' = [e \in Entries |-> IF e[1] = p THEN FALSE ELSE valid[e]]
    /\ IF On("flush_keeps_data")
         THEN UNCHANGED <<tag, installer>>
         ELSE /\ tag'       = [e \in Entries |-> IF e[1] = p THEN SomeTag ELSE tag[e]]
              /\ installer' = [e \in Entries |-> IF e[1] = p THEN NoPart ELSE installer[e]]
    /\ hitEntry' = NoPart
    /\ reqPart'  = NoPart

(***************************************************************************)
(* 조회.                                                                   *)
(*                                                                         *)
(* 적중 조건은 셋의 논리곱이다 (§3.6.2): 파티션 일치 · 태그 일치 ·         *)
(* 유효 비트. 직접 사상이므로 후보는 `{p, i}` 하나뿐이고 — 그것이 HIU-4    *)
(* 를 *구조로* 만족시키는 방식이다.                                        *)
(*                                                                         *)
(*   valid_check     지우면 유효하지 않은 항목도 돌려준다 → HIU-3          *)
(*   partition_check 지우면 남의 파티션 항목도 돌려준다 → HIU-1            *)
(***************************************************************************)
Lookup(p, i, t) ==
    LET e == <<p, i>>
        vOK == valid[e] \/ ~On("valid_check")
        \* 파티션 검사를 지우면 다른 파티션의 같은 색인 항목을 볼 수 있다.
        pOK == ~On("partition_check")
        hitSelf  == vOK /\ tag[e] = t
        foreign  == { q \in Partitions :
                        q # p /\ valid[<<q, i>>] /\ tag[<<q, i>>] = t }
    IN  /\ hitEntry' = IF hitSelf
                         THEN e
                         ELSE IF pOK /\ foreign # {}
                                THEN <<CHOOSE q \in foreign : TRUE, i>>
                                ELSE NoPart
        /\ reqPart' = p
        /\ UNCHANGED <<valid, tag, installer>>

Next ==
    \/ \E p \in Partitions, i \in Indices, t \in Tags : Install(p, i, t)
    \/ \E p \in Partitions : Flush(p)
    \/ \E p \in Partitions, i \in Indices, t \in Tags : Lookup(p, i, t)

Spec == Init /\ [][Next]_vars

(***************************************************************************)
(* 불변식                                                                  *)
(***************************************************************************)

\* HIU-3 — 값을 돌려준 항목은 유효했어야 한다.
\* "모든 읽기 경로가 유효 비트로 게이트된다" 의 관측 가능한 형태이며,
\* 조회가 아닌 동작에서 hitEntry 가 소비되므로 *상태 불변식*으로 족하다.
Inv_ValidGated ==
    (hitEntry # NoPart) => valid[hitEntry]

\* HIU-1 — 적중한 항목은 요청한 파티션의 것이어야 한다.
Inv_PartitionIsolated ==
    (hitEntry # NoPart /\ reqPart # NoPart) => hitEntry[1] = reqPart

\* HIU-2 — 유효하지 않은 항목은 적중하지 않는다. 데이터가 남아 있어도.
\* flush 는 유효 비트만 지우므로, 이 불변식이 곧 "유효 비트가 유일한 방벽" 이다.
Inv_InvalidNeverHits ==
    (hitEntry # NoPart) => (installer[hitEntry] # NoPart /\ valid[hitEntry])

\* HIU-4 — 직접 사상이므로 하나의 (파티션, 색인) 에 후보는 하나뿐이다.
\* 구조로 만족되지만, 구조가 실제로 그런지 확인하는 것이 이 불변식이다.
Inv_AtMostOneCandidate ==
    \A p \in Partitions, i \in Indices :
        Cardinality({ e \in Entries : e = <<p, i>> }) =< 1

(***************************************************************************)
(* 위험 도달성 증인                                                        *)
(***************************************************************************)

\* 적중이 실제로 일어나는가 — 안 일어나면 위 전부가 공허하다.
Witness_NoHit == hitEntry = NoPart

\* flush 이후에도 **데이터가 남는가.**
\* 이것이 반증되지 않으면 HIU-2 는 "데이터를 지워서" 통과한 것이고,
\* 유효 비트가 방벽이라는 사실을 아무것도 증명하지 않는다.
Witness_DataSurvivesFlush ==
    \A e \in Entries : (~valid[e]) => (installer[e] = NoPart)

=============================================================================
