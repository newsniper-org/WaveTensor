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
EXTENDS Naturals, FiniteSets

CONSTANTS
    Pages,        \* 소유권 단위 (§3.4.1 1번). 불투명 토큰
    Vaddrs,       \* 가상 주소. 불투명 토큰
    NoMap,        \* 「사상 없음」 표식 (모델 값)
    NoCache,      \* 「지역 사본 없음」 표식 (모델 값)
    NoVal,        \* 「관측값 없음」 표식 (모델 값)
    DisabledGuards

AllGuards == {"xlate_local", "flush_on_handoff", "state_machine_kept", "owner_check"}
On(g) == g \notin DisabledGuards

Worlds == {"plain", "rich"}
Agents == {"host", "dev"}
Values == 0..1

\* 이 모델의 전제. 두 세계가 *같지 않아야* 비교가 뜻을 갖는다.
ASSUME Cardinality(Pages) >= 1 /\ Cardinality(Vaddrs) >= 1

VARIABLES
    xlate,     \* [Worlds -> [Vaddrs -> Pages \cup {NoMap}]]  장치 내부 변환표
    owner,     \* [Worlds -> [Pages -> Agents]]               중간 상태 없음
    mem,       \* [Worlds -> [Pages -> Values]]               공유 배후 저장
    cache,     \* [Worlds -> [Agents -> [Pages -> Values \cup {NoCache}]]]
    obsKind,   \* [Worlds -> {"none", "value", "fault"}]      직전 읽기의 성격
    obsVal,    \* [Worlds -> Values \cup {NoVal}]             직전 읽기의 값
    obsOwned   \* [Worlds -> BOOLEAN]  직전 읽기에서 읽은 쪽이 소유자였는가

vars == <<xlate, owner, mem, cache, obsKind, obsVal, obsOwned>>

TypeOK ==
    /\ xlate \in [Worlds -> [Vaddrs -> Pages \cup {NoMap}]]
    /\ owner \in [Worlds -> [Pages -> Agents]]
    /\ mem \in [Worlds -> [Pages -> Values]]
    /\ cache \in [Worlds -> [Agents -> [Pages -> Values \cup {NoCache}]]]
    /\ obsKind \in [Worlds -> {"none", "value", "fault"}]
    /\ obsVal \in [Worlds -> Values \cup {NoVal}]
    /\ obsOwned \in [Worlds -> BOOLEAN]

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

\* 읽기가 fault 인가 — 두 발화 조건: 미사상 · 비소유
AccFault(w, a, va) ==
    \/ xlate[w][va] = NoMap
    \/ ~CanAccess(w, a, xlate[w][va])

\* 관측을 소비한다 — 남겨 두면 후속 단계에서 낡은 관측이 속성을 다시 걸어
\* 거짓 반례를 만든다 (XlateStore 모델에서 실측한 실패형).
ClearObs ==
    /\ obsKind'  = [w \in Worlds |-> "none"]
    /\ obsVal'   = [w \in Worlds |-> NoVal]
    /\ obsOwned' = [w \in Worlds |-> TRUE]

Init ==
    /\ xlate = [w \in Worlds |-> [va \in Vaddrs |-> NoMap]]
    /\ owner = [w \in Worlds |-> [pg \in Pages |-> "host"]]
    /\ mem = [w \in Worlds |-> [pg \in Pages |-> 0]]
    /\ cache = [w \in Worlds |-> [a \in Agents |-> [pg \in Pages |-> NoCache]]]
    /\ obsKind = [w \in Worlds |-> "none"]
    /\ obsVal = [w \in Worlds |-> NoVal]
    /\ obsOwned = [w \in Worlds |-> TRUE]

(***************************************************************************)
(* 변환 항목 기입 — 호스트가 구성 표면으로 기입한다 (§3.3).                *)
(* 두 세계에 **같이** 들어간다. 이것이 정상 경로다.                        *)
(***************************************************************************)
MapVa(va, pg) ==
    /\ xlate' = [w \in Worlds |-> [xlate[w] EXCEPT ![va] = pg]]
    /\ ClearObs
    /\ UNCHANGED <<owner, mem, cache>>

(***************************************************************************)
(* 호스트 변환 서비스로 미사상을 채운다 — **rich 세계에서만 가능하다.**    *)
(*                                                                         *)
(* §3.3.1 이 기각한 대안이 정확히 이것이다. 가드 xlate_local 이 켜져 있으면 *)
(* 이 동작은 아예 열리지 않는다. 지우면 rich 세계의 변환표가 plain 보다     *)
(* 커지고 — 그 순간 "PE 가 보는 주소 공간" 이 호스트에 따라 달라진다.      *)
(***************************************************************************)
HostFill(va, pg) ==
    /\ ~On("xlate_local")
    /\ xlate["rich"][va] = NoMap
    /\ xlate' = [xlate EXCEPT !["rich"] = [@ EXCEPT ![va] = pg]]
    /\ ClearObs
    /\ UNCHANGED <<owner, mem, cache>>

(***************************************************************************)
(* 기입.                                                                   *)
(*                                                                         *)
(* rich 세계의 일관 상호연결을 **write-through** 로 추상한다 — 기입이       *)
(* 즉시 배후 저장에 보인다. plain 세계는 지역 사본에만 남는다.             *)
(* 이 비대칭이 이 모델에서 "일관성" 이 뜻하는 것의 전부다.                 *)
(***************************************************************************)
Write(a, va, v) ==
    /\ cache' = [w \in Worlds |->
                   IF AccFault(w, a, va) THEN cache[w]
                   ELSE [cache[w] EXCEPT ![a] =
                           [@ EXCEPT ![xlate[w][va]] = v]]]
    /\ mem' = [w \in Worlds |->
                 IF w = "rich" /\ ~AccFault(w, a, va)
                   THEN [mem[w] EXCEPT ![xlate[w][va]] = v]
                   ELSE mem[w]]
    /\ ClearObs
    /\ UNCHANGED <<xlate, owner>>

(***************************************************************************)
(* 읽기 — 유일한 관측점.                                                   *)
(***************************************************************************)
Read(a, va) ==
    /\ obsKind' = [w \in Worlds |->
                     IF AccFault(w, a, va) THEN "fault" ELSE "value"]
    /\ obsVal' = [w \in Worlds |->
                    IF AccFault(w, a, va) THEN NoVal
                    ELSE IF cache[w][a][xlate[w][va]] # NoCache
                           THEN cache[w][a][xlate[w][va]]
                           ELSE mem[w][xlate[w][va]]]
    /\ obsOwned' = [w \in Worlds |->
                      \/ xlate[w][va] = NoMap          \* 미사상은 이 축과 무관
                      \/ owner[w][xlate[w][va]] = a]
    /\ UNCHANGED <<xlate, owner, mem, cache>>

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
    /\ UNCHANGED xlate

Next ==
    \/ \E va \in Vaddrs, pg \in Pages : MapVa(va, pg)
    \/ \E va \in Vaddrs, pg \in Pages : HostFill(va, pg)
    \/ \E a \in Agents, va \in Vaddrs, v \in Values : Write(a, va, v)
    \/ \E a \in Agents, va \in Vaddrs : Read(a, va)
    \/ \E frm, to \in Agents, pg \in Pages : Handoff(frm, to, pg)

Spec == Init /\ [][Next]_vars

(***************************************************************************)
(* 불변식 — 셋 다 **두 세계의 비교**다.                                    *)
(***************************************************************************)

\* HIU-8 — 변환 결과가 호스트 변환 서비스의 가용 여부에 의존하지 않는다.
Inv_SameTranslation ==
    \A va \in Vaddrs : xlate["plain"][va] = xlate["rich"][va]

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

=============================================================================
