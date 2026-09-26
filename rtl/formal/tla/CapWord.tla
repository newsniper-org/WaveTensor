\* SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
\* SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
---------------------------- MODULE CapWord ----------------------------
(***************************************************************************)
(* CAP_STATUS(0xF8C) · CAP_CLEAR(0xF90) — 능력 부재 관측 워드의 선-formal    *)
(* 모델. 파도 B (정본 1126a38, 2026-08-31: CAP_STATUS 축 둘→넷).           *)
(*                                                                         *)
(* 정본 (좌표 뒤 「」 는 그 줄의 축자 — lint_section_refs 축 1 이 대조한다): *)
(*   e-defined.typ:500-503 「능력 부재도 관측이 sticky 여야 재시도 주체가 놓치지 않는다」 *)
(*     — 0xF8C RO 축 넷 + [31:4] RO 예약 = 0, 0xF90 WO 는 같은 비트 배치의  *)
(*     W1C 이고 [31:4] 예약 = 0 (엄격).                                     *)
(*   e-defined.typ:566-616 「넷은 서로 접지 않는다」 — 규범 「CAP_STATUS    *)
(*     비트 배정 — 축은 「고칠 동작」으로 가른다」. 고칠 동작이 넷 다        *)
(*     다르므로 접으면 상위 계층이 어느 동작을 해야 하는지를 관측에서 잃는다.*)
(*   01-isa-asm.typ:1540-1563 「관측은 sticky 다」 — 규범 「능력 부재의     *)
(*     조회는 상위 계층의 의무다」(조회·수리·해제·재시도). 능력 부재는      *)
(*     fault 가 아니다 — FAULT_STATUS·FAULT_SUMMARY 어느 쪽에도 들지 않는다. *)
(*   rtl/spinal/src/main/scala/wt64/Common.scala:334 「해제와 발화가 같은 사이클이면 발화가 이긴다」 *)
(*     — StickyFault 규약. 이 워드는 fault 가 아니지만 그 순서만 승계한다   *)
(*     (해제로 관측을 삼키는 창을 만들지 않는다).                           *)
(*   E.1.2 FAULT_CLEAR 행 · Wt64Top faultArea 주석: 거절된 기입은 한 비트도 *)
(*     내리지 않는다 — 반쯤 수락이 없다.                                    *)
(*                                                                         *)
(* ## 이 모델이 잡는 정확한 결함                                            *)
(*                                                                         *)
(* 재구현 착수 시점(파도 B 이전)의 Wt64Top 은 CAP_STATUS 를 두 축으로 들고  *)
(* CAP_CLEAR 의 예약 마스크를 N_CAP_BITS=2 에서 유도해 [31:2] 로 두었다.    *)
(* 정본은 [31:4] 다. 따라서 오늘의 RTL 에서는 [2]·[3] 에 대한 *적법한*      *)
(* W1C 기입이 예약 위반으로 읽혀 거절 + loud(FAULT_STATUS[6]) 된다 —        *)
(* clear_atomic 가드의 *정의역*이 정본과 다르다. 이 모델의 Axes 는 토큰    *)
(* 넷이고 Witness_NoClear 는 넷 *전부*가 수락된 W1C 로 내려간 상태를 요구  *)
(* 한다 — 축 둘만 해제 가능한 기계에서는 그 증인이 반증되지 않는다.        *)
(* 그리고 [2] 는 이 워드에 닿지 않는다: 판정 회로(DecodeWalk judge.capAbsent)*)
(* 는 실재하나 그것을 이 워드로 잇는 배선과 sticky 가 없다 (E.1.3 표       *)
(* 「내부만」). [3] 은 원천이 0건이라 상수 0 이다 (E.1.3 표 「미구현」).    *)
(*                                                                         *)
(* 가드 넷은 각각 정본의 한 문장이다:                                       *)
(*   axis_isolated       축 k 의 사건은 cap[k] 만 세운다. 지우면 사건이     *)
(*                       다른 축도 세운다 — 「접기」 결함.                  *)
(*   sticky_until_clear  선 비트는 그 축의 수락된 W1C 로만 내려간다. 지우면 *)
(*                       읽기·시간 경과로 저절로 내려가는 Decay 가 열린다. *)
(*   clear_atomic        예약 구간에 1 이 있는 기입은 한 비트도 내리지 않고 *)
(*                       badWrite 만 세운다. 지우면 부분 수락 — 예약 위반   *)
(*                       인데 축 비트는 내려간다.                           *)
(*   set_beats_clear     같은 스텝에 사건과 그 축의 해제가 겹치면 비트는    *)
(*                       선 채다. 지우면 해제가 이긴다 — StickyFault 규약   *)
(*                       위반.                                             *)
(*                                                                         *)
(* ## 이 모델이 다루지 않는 것                                              *)
(*                                                                         *)
(* · 능력 부재가 fault 워드에 들지 않는 것 — 원천 모듈 가드                 *)
(*   (Payload.capability_not_fault · Decode.fault_not_folded)가 이미 잰다.  *)
(* · 어느 사건이 어느 축인가(정본 표의 배정) — 이 모델은 축을 불투명 토큰   *)
(*   으로 본다. 축 번호·비트 폭은 모델의 질문이 아니다: 예약 구간은 rsv     *)
(*   플래그 하나로 추상화했고, 마스크 값 [31:4] 자체는 후-formal            *)
(*   (a_rsvbad_def)의 몫이다.                                               *)
(* · [0] 의 sticky 가 상류(Reassembly capBit)에 살고 워드 컴포넌트는 레벨을 *)
(*   통과시킨다는 배치 — 관측 워드의 행위는 같으므로 이 모델은 워드만 본다. *)
(*   이중 sticky 레이스는 그 배치의 문제이고 후-formal a_passthru_0 이 잰다. *)
(* · [2] 의 set 펄스가 walk.oValid 로 유효 한정돼야 한다는 것 — 원천 쪽     *)
(*   조건이다. 이 모델의 Event(a) 는 정의상 유효한 사건이다.                *)
(* · [3] 이 상수 0 인 것 — 모델은 넷을 대칭으로 본다. 원천 부재는 RTL 의    *)
(*   사실이며 rtl/README.md 「자리는 있고 회로는 없다」 표가 든다.           *)
(* · CAP_CLEAR 읽기 0 · [31:4] 읽기 0 — 워드 인코딩이라 후-formal 몫이다.   *)
(* · 축 [0] 에 남아 있는 두 번째 해제 경로(최상위 io.faultClear 포트) —      *)
(*   이 모델의 해제 authority 는 CAP_CLEAR 하나다.                          *)
(* · sticky 의 1사이클 지연(RegInit) — 모델의 스텝은 원자적이다.            *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS
    Axes,            \* CAP_STATUS 의 축. 불투명 토큰 넷 — 어느 사건이 어느 축인가는 정본 표의 몫
    DisabledGuards

AllGuards == {"axis_isolated", "sticky_until_clear", "clear_atomic", "set_beats_clear"}
On(g) == g \notin DisabledGuards

\* axis_isolated 를 지웠을 때 사건이 *함께* 세우는 접힌 축 — 결정적으로 하나 고른다.
Fold(a) == CHOOSE b \in Axes \ {a} : TRUE

VARIABLES
    cap,             \* [Axes -> BOOLEAN] — CAP_STATUS 읽기 값의 축별 비트
    badWrite,        \* 예약 위반 기입이 거절된 사실. sticky (RTL: surfBadWr → FAULT_STATUS[6])
    evt,             \* 보조 — 직전 스텝의 사건 축 집합 ({} 또는 단일)
    clr,             \* 보조 — 직전 스텝에 *수락된* W1C 축 집합
    rsv,             \* 보조 — 직전 스텝이 예약 구간 위반 기입이었는가
    clearedAxes      \* 증인용 sticky — 선 비트가 수락된 W1C 로 내려간 적 있는 축의 합집합

vars == <<cap, badWrite, evt, clr, rsv, clearedAxes>>

TypeOK ==
    /\ cap \in [Axes -> BOOLEAN]
    /\ badWrite \in BOOLEAN
    /\ evt \in SUBSET Axes
    /\ clr \in SUBSET Axes
    /\ rsv \in BOOLEAN
    /\ clearedAxes \in SUBSET Axes

Init ==
    /\ cap = [x \in Axes |-> FALSE]
    /\ badWrite = FALSE
    /\ evt = {}
    /\ clr = {}
    /\ rsv = FALSE
    /\ clearedAxes = {}

(***************************************************************************)
(* 한 스텝의 공통 갱신 — 사건 축 집합 E · CAP_CLEAR 기입 여부 wr · W1C 요청 *)
(* 축 집합 m · 예약 위반 r. 세 액션(Event · Clear · EventAndClear)이 전부  *)
(* 이 하나로 환원된다 — 사건과 기입이 같은 스텝에 오는 경우를 별도 사본으로 *)
(* 적으면 두 사본이 드리프트한다.                                          *)
(*                                                                         *)
(*   axis_isolated    끄면 E 의 각 축 a 가 Fold(a) 도 세운다.               *)
(*   clear_atomic     끄면 r 인 기입도 m 을 수락한다 (부분 수락).            *)
(*   set_beats_clear  끄면 같은 축의 해제가 사건을 이긴다.                  *)
(*                                                                         *)
(* 수락된 해제 집합 clr' 은 「예약 위반이면 빈 집합」이다 — 거절된 기입은   *)
(* 한 비트도 내리지 않는다 (E.1.2 FAULT_CLEAR 행과 같은 처분).             *)
(***************************************************************************)
Step(E, wr, m, r) ==
    LET setAx == IF On("axis_isolated") THEN E ELSE E \cup {Fold(a) : a \in E}
        acc   == wr /\ (~r \/ ~On("clear_atomic"))
        clrAx == IF acc THEN m ELSE {}
        newBit(x) == IF On("set_beats_clear")
                       THEN (x \in setAx) \/ (cap[x] /\ x \notin clrAx)
                       ELSE (x \notin clrAx) /\ ((x \in setAx) \/ cap[x])
    IN  /\ cap' = [x \in Axes |-> newBit(x)]
        /\ badWrite' = (badWrite \/ (wr /\ r))
        /\ evt' = E
        /\ clr' = clrAx
        /\ rsv' = (wr /\ r)
        /\ clearedAxes' = (clearedAxes \cup {x \in clrAx : cap[x] /\ ~newBit(x)})

\* 축 a 의 능력 부재 사건 — 원천(재조립 · step sequencer · DecodeWalk 판정)이
\* 그 축의 set 을 올린다. 이 모델에서 사건은 정의상 유효하다 (머리 해설).
Event(a) == Step({a}, FALSE, {}, FALSE)

\* CAP_CLEAR 기입 — [3:0] 에 해당하는 W1C 요청 m, 예약 [31:4] 위반 여부 r.
\* m = {} 도 적법하다 (0 을 쓰는 무동작 W1C).
Clear(m, r) == Step({}, TRUE, m, r)

\* 같은 스텝에 사건과 기입이 겹친다 — set_beats_clear 가 실제로 시험되는 자리.
EventAndClear(a, m, r) == Step({a}, TRUE, m, r)

\* sticky_until_clear 를 지웠을 때만 열리는 액션 — 읽기·시간 경과로 비트가
\* 저절로 내려간다. 수락된 해제가 아니므로 clr' = {} 이다.
Decay(a) ==
    /\ ~On("sticky_until_clear")
    /\ cap[a]
    /\ cap' = [cap EXCEPT ![a] = FALSE]
    /\ evt' = {}
    /\ clr' = {}
    /\ rsv' = FALSE
    /\ UNCHANGED <<badWrite, clearedAxes>>

Next ==
    \/ \E a \in Axes : Event(a)
    \/ \E m \in SUBSET Axes, r \in BOOLEAN : Clear(m, r)
    \/ \E a \in Axes, m \in SUBSET Axes, r \in BOOLEAN : EventAndClear(a, m, r)
    \/ \E a \in Axes : Decay(a)

Spec == Init /\ [][Next]_vars

(***************************************************************************)
(* 속성 — 전부 행위 속성([][...]_vars). 「무엇이 이 비트를 세웠/내렸는가」  *)
(* 는 한 스텝의 전후를 함께 봐야 말할 수 있다 (Mask.tla · ResultBank.tla   *)
(* 과 같은 자리). 보조 변수 evt' · clr' · rsv' 가 그 스텝의 원인을 나른다.  *)
(***************************************************************************)

\* 규범 「넷은 서로 접지 않는다」 — 비트가 서는 것은 그 축의 사건뿐이다.
Prop_AxisIsolation ==
    [][ \A x \in Axes : (~cap[x] /\ cap'[x]) => (x \in evt') ]_vars

\* E.1.2 CAP_CLEAR 행 「sticky 여야」 — 비트가 내려가는 것은 그 축의 *수락된*
\* W1C 뿐이다. 읽기도, 시간도, 다른 축의 해제도 아니다.
Prop_StickyUntilClear ==
    [][ \A x \in Axes : (cap[x] /\ ~cap'[x]) => (x \in clr') ]_vars

\* 예약 구간 엄격 + 「반쯤 수락이 없다」 — 예약 위반 기입은 아무 축도
\* 수락하지 않고, 아무 비트도 내리지 않으며, badWrite 를 세운다.
Prop_ClearAtomic ==
    [][ rsv' => (/\ clr' = {}
                 /\ badWrite'
                 /\ \A x \in Axes : cap[x] => cap'[x]) ]_vars

\* StickyFault 규약 — 사건이 있었던 축은 그 스텝 뒤에 서 있다, 같은 스텝에
\* 그 축의 해제가 수락됐더라도.
Prop_SetBeatsClear ==
    [][ \A x \in evt' : cap'[x] ]_vars

(***************************************************************************)
(* 위험 도달성 증인 — 좋은 모델에서 반드시 반증돼야 한다.                  *)
(***************************************************************************)

\* 사건이 실재하는가 — 어떤 cap 도 서지 않으면 위 속성 전부가 공허하다.
Witness_NoEvent == \A x \in Axes : ~cap[x]

\* 선 비트가 해제로 내려가는 일이 넷 *전부*에서 실재하는가 — 넷 전부의
\* 해제 도달성을 요구한다. RTL 마스크 폭([31:4] 대 [31:2])의 대조는 이
\* 모델의 정의역이 아니다(예약은 rsv 플래그 하나로 추상화) — 그것은
\* 후-formal capword.sby 의 a_rsvbad_def 가 잰다.
Witness_NoClear == clearedAxes # Axes

\* 예약 위반 기입의 거절이 실재하는가 — 없으면 clear_atomic 이 한 번도
\* 시험되지 않는다.
Witness_NoRejectedWrite == ~badWrite

\* 같은 축의 사건과 수락된 해제가 같은 스텝에 겹치는 일이 실재하는가 —
\* 없으면 set_beats_clear 가드 삭제 실험이 그 가드를 한 번도 건드리지 못한다.
Witness_NoSimultaneous == evt \cap clr = {}

=============================================================================
