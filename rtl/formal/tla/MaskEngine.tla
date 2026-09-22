\* SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
\* SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
--------------------------- MODULE MaskEngine ---------------------------
(***************************************************************************)
(* MaskUnit 재키잉 엔진 창의 **시간 축** — FINAL 엣지 동시 기입 모서리의     *)
(* 선-formal 모델. 파도 D (2026-09-22).                                      *)
(*                                                                         *)
(* ## Mask.tla 과의 분업 — E.9 4항의 두 면                                  *)
(*                                                                         *)
(* Mask.tla 은 저장의 파티션 범위(창·키·논스·REKEY authority)를 재고,       *)
(* 재키잉을 「수락 시점에 maskValid 를 세운다」로 추상한다 — 그 Complete 는  *)
(* phase 만 되돌리고 오염·fault·완료 시점 유효화라는 개념이 없다. 이미     *)
(* 증명된 그 가드 넷은 여기서 건드리지 않는다. 이 모델은 엔진 창의 시간   *)
(* 축만 다룬다:                                                            *)
(*   Mask.tla       = 「어느 파티션」                                        *)
(*                    e-defined.typ:1526 「다른 파티션이 그 변경의 사정권 밖」 *)
(*   MaskEngine.tla = 「언제」                                              *)
(*                    e-defined.typ:1525 「옛 키로 만든 주소와 새 키로 만든 주소가 섞이면 안 된다」 *)
(*                                                                         *)
(* 정본 (좌표 뒤 「」 는 그 줄의 축자 — lint_section_refs 축 1 이 대조한다): *)
(*   e-defined.typ:518 「재키잉 중 입력 기입」 — FAULT_STATUS [13]. 시점     *)
(*     예외가 없다: 재키잉 *중*이면 어느 사이클의 기입이든 이 비트다.       *)
(*   e-defined.typ:347 「`[8]` 엔진 busy · `[9]` 재키잉 수락 가능」 —        *)
(*     MASK_STATUS. 「재키잉 중」의 정의는 장치 자신의 관측 busy=1 이다.     *)
(*   e-defined.typ:345 「엔진이 유휴가 아니면 수락되지 않고」 — busy 창의    *)
(*     경계는 수락 엣지와 완료 엣지 둘뿐이다.                               *)
(*   05-security.typ:384 「소실도 loud 여야 한다」 — 함정 「실제로 있었던    *)
(*     조용한 소실」. 오염이 아니어도 관측이 없으면 결손이다.               *)
(*   05-security.typ:371 「조용한 실패는 편의 문제가 아니라」 보안 문제다.   *)
(*   e-defined.typ:1543-1544 「그 파티션 비트가 설 때까지 기다린다」 —       *)
(*     호스트의 완료 관측. 파도 D 이전 RTL 에서는 FINAL 엣지 기입 뒤 이     *)
(*     기다림이 어떤 비트도 서지 않은 채 무한이었다 (정본 5장 「실제로       *)
(*     있었던 조용한 소실」 함정과 동형).                                    *)
(*   e-defined.typ:1549 「재계산 중(`0xEC0` `[8]`)」 — 정본 자신이 「재키잉    *)
(*     중」의 정의역을 [8] 로 준다 (「끝점이 정본에 없다」 반론의 반증).     *)
(*   rtl/spinal/src/main/scala/wt64/mask/MaskUnit.scala:148 「계산 중 입력이 바뀐 재키잉은 결과를 유효화하지 않는다」 *)
(*     — 그 파일 자신의 E.9 4항 계약 (compDirty → faultWrDuringRekey);      *)
(*     파도 D 가 그 문면에 「FINAL 사이클 포함」을 한 문장으로 더했다.       *)
(*   rtl/spinal/src/main/scala/wt64/Common.scala:256 「해제와 발화가 같은 사이클이면 발화가 이긴다」 *)
(*     — StickyFault 규약. 이 모델의 ClearFault 는 완료와 겹치지 않는다     *)
(*     (아래 「안 잰다」).                                                  *)
(*                                                                         *)
(* ## 이 모델이 잡는 정확한 결함                                            *)
(*                                                                         *)
(* 파도 D 이전 판(1666c7a)의 RTL (파도 C 검토 실측 2026-09-22): 활성 파티션 *)
(* (actPart)으로 향한 키·논스 기입이 정확히 FINAL 사이클 — 이 사이클은     *)
(* io.busy=1 · io.rekey.ready=0 으로 장치 자신이 「재키잉 중」이라 말한다 — *)
(* 에 실리면, 기입 표면의 compDirty := True 는 레지스터라 **다음** 사이클에 *)
(* 야 1 이 되고, FINAL 가지는 dirtyAtFinal 에 compDirty 레지스터만 실어    *)
(* 엣지 전 값 0 을 읽으므로 sticky 가 서지 않았다. 유효는 기입 표면을 FSM *)
(* 뒤에 둔 텍스트 순서(유효화와 겹치면 무효화가 이긴다)로 떨어진다. 실측:  *)
(* 수락+42 엣지 기입 → maskReady[p]=0 · faultWrDuringRekey=0. 수락+40·+41  *)
(* → fault=1. 파도 D 의 RTL 은 FINAL 가지가 같은 사이클 항 wrActNow 를     *)
(* 직접 본다 —                                                             *)
(*   rtl/spinal/src/main/scala/wt64/mask/MaskUnit.scala:473 「val dirtyNow = compDirty || wrActNow」 *)
(*   (좌표는 파도 D 의 RTL 편집·rtl-gen 뒤에 재조준했다 — 이 파일의 RTL     *)
(*   좌표 확정은 D2 뒤다.)                                                 *)
(* 안전 결손은 아니다 — 마스크는 유효화되지 않는다. **관측 결손**이다:      *)
(* 같은 호스트 행위가 1사이클 타이밍에 따라 두 판정을 받고(판정이 시간을   *)
(* 가른다), 호스트는 「아직 안 끝남」과 「내 기입이 결과를 버렸다」를 가를  *)
(* 수 없다 — 조용한 소실의 정확한 형태다. 아래 dirty_loud 가드를 지운       *)
(* 모델이 파도 D 이전 RTL 과 동형이고, Prop_MixLoud 가 그 반례를 낸다.      *)
(*                                                                         *)
(* 가드 넷은 각각 정본의 한 문장이다:                                       *)
(*   dirty_scoped         busy 중 기입은 **target 파티션으로 향한 것만**    *)
(*                        dirty 를 세운다. 지우면 어느 파티션 기입이든     *)
(*                        dirty — 파도 A 이전 RTL 과 동형 (E.9 4항 「다른   *)
(*                        파티션이 그 변경의 사정권 밖」).                  *)
(*   dirty_no_validate    dirty 한 완료는 target 을 유효화하지 않는다.      *)
(*                        지우면 유효화 — 옛/새 입력 혼합 창 (E.9 4항).     *)
(*   dirty_loud           유효화하지 않은 완료는 fault 를 세운다 — **완료와 *)
(*                        같은 스텝의 target 기입도 포함**. 지우면 fault' = *)
(*                        fault ∨ dirty (직전 스텝까지의 오염만) — 파도 D   *)
(*                        이전 RTL dirtyAtFinal := compDirty 와 동형        *)
(*                        (FAULT_STATUS [13] · loud-fault-never-silent).    *)
(*   invalidate_beats_validate                                              *)
(*                        완료와 같은 스텝의 target 기입은 유효화를 이긴다  *)
(*                        (무효). 지우면 유효화가 이긴다 — MaskUnit.scala   *)
(*                        기입 표면 「FSM 뒤에 두어 …」 텍스트 순서 결정의  *)
(*                        형식화.                                          *)
(*                                                                         *)
(* ## 이 모델이 다루지 않는 것 (「안 잰다」)                                *)
(*                                                                         *)
(* · 42사이클 길이 · HROUND/CROUND 라운드 수 · 라운드망 — busy 는 추상 한   *)
(*   상태다. 「FINAL 사이클」은 이 모델에서 「완료 스텝」 하나다. 완료까지의 *)
(*   정확한 엣지 수는 후-formal(engine.sby, bmc 깊이 ≥ 48)과 cocotb        *)
(*   (수락+40·41·42·43·44 오프셋 지향 시험)의 몫이다.                      *)
(* · 키·논스 값과 마스크 값 — 불투명. XChaCha20 정확성은 golden 대조 몫.    *)
(* · 키 워드 인덱스·논스 워드 인덱스(idx<6) — 기입은 「그 파티션으로 향한   *)
(*   기입」 하나로 접는다. 키 기입과 논스 기입은 이 모델에서 같은 액션이다  *)
(*   (RTL 은 동형 두 when 이고 D2 의 wrActNow 가 둘을 OR 한다).            *)
(* · 어느 파티션의 저장이 바뀌는가(창·MASK_PART·REKEY authority) —          *)
(*   Mask.tla 의 정의역이다. 여기서 기입은 파티션 q 를 직접 지목한다.       *)
(* · 수락 엣지와 같은 스텝의 기입 — RTL 의 rekeyFire ∧ part = rekey.part    *)
(*   가지. 이 모델의 Accept 는 기입과 겹치지 않는다. 그 모서리의 *값 면*   *)
(*   (유도 초기 상태가 엣지 전 값을 래치)은 HiuMask 의 key_scoped_storage  *)
(*   섀도우 대조가, *오염 면*(같은-파티션 수락 사이클 기입 ⇒ 완료가 loud· *)
(*   무효)은 engine.sby 의 f_dirty 갈래 (i) 와 증인 W8 이 잰다.            *)
(* · ClearFault 와 완료가 같은 스텝 — StickyFault 「발화가 이긴다」 규약은  *)
(*   CapWord.set_beats_clear 가 같은 규약을 이미 재고, 이 모델의 fault 는   *)
(*   그 규약의 소비자다. 여기서 해제는 단독 스텝이다.                      *)
(* · busy 중 REKEY 시도의 미수락(MASK_STATUS [9]) — Mask.rekey_idle_only.   *)
(* · sticky 의 1사이클 지연(RegInit) — 모델의 스텝은 원자적이다.            *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS
    Parts,           \* 임대(파티션). 불투명 토큰 2~3
    NoPart,          \* 「기입 없음 / 지목 없음」 표식 (모델 값)
    DisabledGuards

AllGuards == {"dirty_scoped", "dirty_no_validate", "dirty_loud",
              "invalidate_beats_validate"}
On(g) == g \notin DisabledGuards

VARIABLES
    phase,           \* {"idle", "busy"} — busy 는 수락 엣지부터 완료 엣지까지를 접은 한 상태
    target,          \* 엔진이 물고 있는 파티션 (RTL actPart). NoPart = 아직 수락 없음
    valid,           \* [Parts -> BOOLEAN] — MASK_STATUS 파티션별 마스크 준비 (RTL maskValid)
    dirty,           \* 이번 busy 창에서 **직전 스텝까지** target 으로 향한 기입이
                     \* 있었는가 — RTL compDirty *레지스터* (이번 스텝의 기입은 아직 아니다)
    fault,           \* FAULT_STATUS [13] sticky (RTL faultWrDuringRekey)
    done,            \* 보조 — 직전 스텝이 완료(busy→idle)였는가
    wr,              \* 보조 — 직전 스텝에 기입된 파티션. NoPart = 기입 없음
    overlapSeen,     \* 증인용 sticky — 완료와 target 기입이 한 스텝에 겹친 적 있는가
    dirtyDoneSeen,   \* 증인용 sticky — dirty 한 완료가 실재했는가
    cleanDoneSeen,   \* 증인용 sticky — 깨끗한 완료가 target 을 유효화한 적 있는가
    otherBusySeen    \* 증인용 sticky — busy 중 target 아닌 파티션 기입이 실재했는가

vars == <<phase, target, valid, dirty, fault, done, wr,
          overlapSeen, dirtyDoneSeen, cleanDoneSeen, otherBusySeen>>

TypeOK ==
    /\ phase \in {"idle", "busy"}
    /\ target \in Parts \cup {NoPart}
    /\ valid \in [Parts -> BOOLEAN]
    /\ dirty \in BOOLEAN
    /\ fault \in BOOLEAN
    /\ done \in BOOLEAN
    /\ wr \in Parts \cup {NoPart}
    /\ overlapSeen \in BOOLEAN
    /\ dirtyDoneSeen \in BOOLEAN
    /\ cleanDoneSeen \in BOOLEAN
    /\ otherBusySeen \in BOOLEAN

Init ==
    /\ phase = "idle"
    /\ target = NoPart
    /\ valid = [p \in Parts |-> FALSE]
    /\ dirty = FALSE
    /\ fault = FALSE
    /\ done = FALSE
    /\ wr = NoPart
    /\ overlapSeen = FALSE
    /\ dirtyDoneSeen = FALSE
    /\ cleanDoneSeen = FALSE
    /\ otherBusySeen = FALSE

(***************************************************************************)
(* MASK_REKEY 수락 엣지 — idle→busy. 옛 마스크는 이 순간부터 무효고         *)
(* 오염 누적은 여기서 지워진다 (RTL IDLE 가지: compDirty := False ·         *)
(* maskValid(part) := False). busy 중 시도의 미수락은 Mask.rekey_idle_only. *)
(***************************************************************************)
Accept(p) ==
    /\ phase = "idle"
    /\ phase' = "busy"
    /\ target' = p
    /\ dirty' = FALSE
    /\ valid' = [valid EXCEPT ![p] = FALSE]
    /\ done' = FALSE
    /\ wr' = NoPart
    /\ UNCHANGED <<fault, overlapSeen, dirtyDoneSeen, cleanDoneSeen, otherBusySeen>>

(***************************************************************************)
(* 한 스텝의 공통 갱신 — 기입 파티션 w (NoPart = 기입 없음) · 완료 여부 c.  *)
(* 네 액션(WriteIdle · WriteBusy · Complete · CompleteWithWrite)이 전부 이  *)
(* 하나로 환원된다 — 완료와 기입이 같은 스텝에 오는 모서리를 별도 사본으로 *)
(* 적으면 두 사본이 드리프트한다 (CapWord.tla Step 선례).                   *)
(*                                                                         *)
(*   dirty     직전 스텝까지의 오염 — RTL compDirty 레지스터가 이 사이클에  *)
(*             보이는 값. 이번 스텝의 기입은 dirtySet 으로 따로 든다.       *)
(*   wrTgt     모서리 — 완료 스텝에 target 기입이 겹친다 (RTL FINAL 사이클  *)
(*             의 actPart 기입). dirty_scoped 와 무관하게 target 기입만이다 *)
(*             — RTL 의 같은 사이클 항(D2 wrActNow)은 언제나 actPart 한정.  *)
(*   mixed     완료가 유효화하면 옛/새 입력 혼합이 되는 조건 = dirty ∨ wrTgt *)
(*                                                                         *)
(*   dirty_scoped               끄면 busy 중 어느 파티션 기입이든 dirtySet. *)
(*   dirty_no_validate          끄면 dirty 여도 유효화한다.                 *)
(*   invalidate_beats_validate  끄면 wrTgt 여도 유효화가 이긴다.            *)
(*   dirty_loud                 끄면 fault 는 dirty (직전 스텝까지) 만 본다 *)
(*                              — 파도 D 이전 RTL dirtyAtFinal := compDirty. *)
(*                                                                         *)
(* dirty' 는 완료 스텝에도 누적된다(리셋은 Accept 에서) — RTL compDirty 가  *)
(* rekeyFire 에서만 지워지는 것과 같다. idle 의 stale dirty 는 어디서도    *)
(* 읽히지 않는다 (Accept 가 먼저 지운다).                                  *)
(***************************************************************************)
Step(w, c) ==
    LET busy     == phase = "busy"
        dirtySet == busy /\ (w # NoPart) /\ ((w = target) \/ ~On("dirty_scoped"))
        wrTgt    == c /\ (w = target)
        mixed    == dirty \/ wrTgt
        baseOK   == ~dirty \/ ~On("dirty_no_validate")
        tgtValid == IF wrTgt /\ On("invalidate_beats_validate") THEN FALSE ELSE baseOK
        loud     == IF On("dirty_loud") THEN mixed ELSE dirty
    IN  /\ c => busy
        /\ (w # NoPart) \/ c
        /\ phase' = IF c THEN "idle" ELSE phase
        /\ valid' = [q \in Parts |->
                       IF c /\ (q = target) THEN tgtValid
                       ELSE IF q = w THEN FALSE
                       ELSE valid[q]]
        /\ dirty' = (dirty \/ dirtySet)
        /\ fault' = (fault \/ (c /\ loud))
        /\ done' = c
        /\ wr' = w
        /\ overlapSeen'   = (overlapSeen \/ wrTgt)
        /\ dirtyDoneSeen' = (dirtyDoneSeen \/ (c /\ dirty))
        /\ cleanDoneSeen' = (cleanDoneSeen \/ (c /\ ~dirty /\ ~wrTgt /\ tgtValid))
        /\ otherBusySeen' = (otherBusySeen \/ (busy /\ (w # NoPart) /\ (w # target)))
        /\ UNCHANGED target

\* 유휴 중 파티션 q 의 키/논스 기입 — 그 파티션의 유효만 떨어진다. 오염 없음.
WriteIdle(q) == (phase = "idle") /\ Step(q, FALSE)

\* busy 중 파티션 q 의 기입 — 유효는 떨어지고, dirty' 는 가드대로.
WriteBusy(q) == (phase = "busy") /\ Step(q, FALSE)

\* 완료 엣지 — busy→idle. valid[target]' = ¬dirty · fault' = fault ∨ dirty.
Complete == Step(NoPart, TRUE)

\* **모서리** — 완료와 q 기입이 한 스텝. q = target 이면 유효·fault 는 가드대로.
CompleteWithWrite(q) == Step(q, TRUE)

\* FAULT_CLEAR — 단독 스텝 (완료와 겹치지 않는다 — 머리 「안 잰다」).
ClearFault ==
    /\ fault
    /\ fault' = FALSE
    /\ done' = FALSE
    /\ wr' = NoPart
    /\ UNCHANGED <<phase, target, valid, dirty,
                   overlapSeen, dirtyDoneSeen, cleanDoneSeen, otherBusySeen>>

Next ==
    \/ \E p \in Parts : Accept(p)
    \/ \E q \in Parts : WriteIdle(q)
    \/ \E q \in Parts : WriteBusy(q)
    \/ Complete
    \/ \E q \in Parts : CompleteWithWrite(q)
    \/ ClearFault

Spec == Init /\ [][Next]_vars

(***************************************************************************)
(* 속성 — 전부 행위 속성([][...]_vars). 「이 완료가 무엇을 유효화·발화했는가」 *)
(* 는 한 스텝의 전후를 함께 봐야 말할 수 있다 (CapWord.tla · Mask.tla 과   *)
(* 같은 자리). 보조 변수 done' · wr' 가 그 스텝의 원인을 나른다.           *)
(***************************************************************************)

\* E.9 4항 「다른 파티션이 그 변경의 사정권 밖」 — 엔진 창에서도 성립한다.
\* busy 중 target 아닌 파티션의 기입은 오염을 바꾸지 않는다.
Prop_DirtyScoped ==
    [][ ((phase = "busy") /\ (wr' # NoPart) /\ (wr' # target)) => (dirty' = dirty) ]_vars

\* E.9 4항 「옛 키로 … 새 키로 … 섞이면 안 된다」 — dirty 한 완료는 target 을
\* 유효화하지 않는다.
Prop_DirtyNoValidate ==
    [][ (done' /\ dirty) => ~valid'[target] ]_vars

\* FAULT_STATUS [13] · loud-fault-never-silent — 유효화하지 않은 완료는
\* 반드시 fault 를 세운다. 완료와 같은 스텝의 target 기입이 유효화를 막은
\* 경우도 예외가 아니다 — 그 스텝은 busy 였다 (재키잉 중).
Prop_MixLoud ==
    [][ (done' /\ ~valid'[target]) => fault' ]_vars

\* 기입 표면의 텍스트 순서 결정 — 완료와 같은 스텝의 target 기입은
\* 유효화를 이긴다 (무효). 안전한 쪽 우선.
Prop_InvalidateBeatsValidate ==
    [][ (done' /\ (wr' = target)) => ~valid'[target] ]_vars

\* 가드 아님 — 고정 의미의 상태 불변식 (AllGuards 넷은 불변). 수락은 옛
\* 마스크를 즉시 무효화하고 (RTL IDLE 가지 maskValid(io.rekey.part) := False)
\* busy 중 어느 스텝도 target 을 유효화하지 않는다 — 「재계산 중」인 파티션이
\* 유효로 보이는 창은 없다. Mask.tla 은 이 축을 반대로 추상한다(수락 시
\* TRUE — 저장 범위만 재므로 무방)라 어느 모델도 재지 않던 축을 여기서
\* 든다; 후-formal 은 engine.sby 의 a_accept_invalidates (앵커 없음).
Inv_BusyTargetInvalid == (phase = "busy") => ~valid[target]

(***************************************************************************)
(* 위험 도달성 증인 — 좋은 모델에서 반드시 반증돼야 한다.                  *)
(***************************************************************************)

\* 완료와 target 기입의 겹침이 실재하는가 — 없으면 dirty_loud 와
\* invalidate_beats_validate 의 삭제 실험이 그 가드를 한 번도 건드리지 못한다.
Witness_NoOverlap == ~overlapSeen

\* dirty 한 완료가 실재하는가 — 없으면 dirty_no_validate 가 공허하다.
Witness_NoDirtyComplete == ~dirtyDoneSeen

\* 깨끗한 완료가 target 을 유효화한 적 있는가 — 없으면 「유효화하지
\* 않는다」 류 속성 전부가 「아무것도 유효화하지 않는」 기계에서 공허하다.
Witness_NoCleanComplete == ~cleanDoneSeen

\* busy 중 target 아닌 파티션 기입이 실재하는가 — 없으면 dirty_scoped 가
\* 한 번도 시험되지 않는다.
Witness_NoOtherWriteBusy == ~otherBusySeen

=============================================================================
