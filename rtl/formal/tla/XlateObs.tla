\* SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
\* SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
----------------------------- MODULE XlateObs -------------------------------
(***************************************************************************)
(* 변환 미적중의 관측면 — `0xE04` XLATE_STATUS · `0xE08`/`0xE0C`            *)
(* XLATE_MISS_VPN 세 RO 워드가 *무엇을* 내는가의 선-formal 모델.           *)
(* 파도 4 (2026-09-26 — 판정 E04 (A) 「정지 게이트 스냅샷」).              *)
(*                                                                         *)
(* ## 왜 이제 있는가 — 값이 어느 모델의 상태도 아니었다                    *)
(*                                                                         *)
(* XlateSurface.tla 는 호스트 쪽 *문*(스테이징 · 커밋 · flush · 0xE10 해제 · *)
(* RO 세 워드 쓰기 거절)이고, 그 모델에서 세 RO 워드의 *읽기*는 상태가      *)
(* 아니다. 파도 3 까지 RTL 은 세 워드 읽기를 전부 0 으로 두었고(미배선),    *)
(* 정본은 필드만 정한 채 셋에 침묵했다 — 정지가 없을 때의 값 · 여러 워드   *)
(* 읽기의 찢김 · 읽기가 해제하는가. 판정 E04 (A) 가 그 셋을 정했고          *)
(* (f229c8b), 6.3 은 「그 결정을 모델로 돌려보낸다」를 요구한다. 이 모델이 *)
(* 그 1단이다.                                                             *)
(*                                                                         *)
(* ## 분업                                                                 *)
(*                                                                         *)
(*   XlateSurface.tla  문 — 무엇이 표를 바꾸고 무엇이 sticky 를 내리는가.   *)
(*   XlateObs.tla      관측 — 세 워드가 무엇을 내고, 그것만 보는 호스트가   *)
(*                     정지를 풀 수 있는가— E.3 파생 요건의 *충분성*.       *)
(*   Isolation.tla     조회·채움의 비간섭 (관측면의 파티션 간 누출은 여기  *)
(*                     아래 obs_no_residue 가 이 워드들에 대해 잰다).      *)
(*                                                                         *)
(* 정본 (좌표 뒤 「」 는 그 줄의 축자 — lint_section_refs 축 1 이 대조한다): *)
(*   e-defined.typ:323 「`[0]` 미적중으로 정지 중 · `[1]` 미적중 sticky · `[15:8]` 정지한 요청의 파티션」 *)
(*   e-defined.typ:323 「정지 중(`[0]` = 1)에만 정지한 요청의 값을 내고 정지가 없으면 0 이다」 *)
(*   e-defined.typ:323 「끝난 정지의 잔재를 관측면에 남기지 않는다」      *)
(*   e-defined.typ:323 「여러 워드 읽기가 찢기지 않는다」                  *)
(*   e-defined.typ:323 「이 워드와 두 VPN 워드의 읽기는 아무것도 해제하지 않는다」 *)
(*   e-defined.typ:325 「정지한 요청의 가상 페이지 번호 하위 32b」        *)
(*   e-defined.typ:327 「넓은 판에서도 정지가 없으면 0 이다」               *)
(*   e-defined.typ:329 「*정지 자체는 이것으로 풀리지 않는다*」            *)
(*   e-defined.typ:873 「호스트가 항목을 기입하면 정지가 풀린다.」 — E.3 2항. *)
(*   e-defined.typ:881 「채널이 없으면 2항은 이행 불가능한」               *)
(*   e-defined.typ:884 「정지 사실과 sticky 는 `0xE04` XLATE_STATUS 로 읽는다」 *)
(*   e-defined.typ:886 「기입해야 할 항목의 가상 페이지 번호는 `0xE08`/`0xE0C`」 *)
(*   e-defined.typ:913 「미적중에 의한 정지(E.3)는 #emph[조회] 에서 일어나며」 — E.4 3항. *)
(*   05-security.typ:464 「*상태 표면* — sticky 표시(@sec:defined E.3), 진단 상태(@sec:hiu 3.8),」 *)
(*   05-security.typ:501 「의 *활동이 남긴 상태*에 의존하지 않는다」       *)
(*                                                                         *)
(* ## 추상                                                                 *)
(*                                                                         *)
(*   tbl     표 — (파티션, VPN) 의 적중 여부. 항목 기입(V)과 flush 만 바꾼다. *)
(*   s3      조회 지점의 요청 하나 — E.4 3항: 정지는 조회 지점 한 곳이고    *)
(*           파이프 전체가 함께 서므로 동시에 정지한 요청은 하나다.         *)
(*   sticky  미적중 sticky — set 이 정지 레벨이고 해제(0xE10)를 이긴다      *)
(*           (XlateSurface.tla 발견 4 · E.1.2 `0xE10` 행의 정지 중 해제 유실). *)
(*   cap     첫 미적중 포착 레지스터 — 좋은 모델은 관측에 쓰지 않는다.      *)
(*           가드 삭제·대안(갈래 (B) 「첫 미적중 포착」)만 쓴다.           *)
(*   rd      직전 읽기의 결과 (종류 · [0] · [1] · 파티션 · VPN).            *)
(*   snap    `[0]` = 1 을 본 STATUS 읽기의 스냅샷 — 항목 기입까지 유지.   *)
(*   ev      증인 사건 꼬리표 (한 스텝짜리).                                *)
(*   관측의 「0」 은 NoPart · NoVpn 이다 — 파티션 값 0 · VPN 0 과 구별해야  *)
(*   「정지 없음」 과 「파티션 0 의 정지」 가 가려진다 (RTL 에서는 [0] 이   *)
(*   그 둘을 가른다).                                                      *)
(*                                                                         *)
(* ## 가드 — 각각 정본 한 문장. 삭제 run 은 자기 속성이 첫 위반으로 난다.  *)
(*                                                                         *)
(*   obs_stall_live    :323 `[0]` 은 *지금* 정지 중인가다. 지우면 [0] 이   *)
(*                     sticky 를 낸다 — 정지가 풀린 뒤에도 1.              *)
(*                     → Prop_StatusStall                                  *)
(*   obs_sticky        :323 `[1]` 은 sticky 다. 지우면 [1] 이 살아 있는 정지를 *)
(*                     낸다 — 풀린 미적중의 흔적이 사라진다.               *)
(*                     → Prop_StatusSticky                                 *)
(*   obs_part_stalled  :323 정지 중의 `[15:8]` 은 정지한 요청의 파티션. 지우면 *)
(*                     상수(파티션 값 0)를 낸다 — 오늘의 RTL 모양.          *)
(*                     → Prop_PartStalled                                  *)
(*   obs_vpn_stalled   :325 정지 중의 VPN 은 정지한 요청의 VPN. 지우면 첫 미적중 *)
(*                     포착(갈래 (B))을 낸다 — 해제 없이 둘째 정지가 오면   *)
(*                     첫 요청의 VPN 이 읽힌다. → Prop_VpnStalled          *)
(*   obs_no_residue    :323 · :327 정지가 없으면 `[15:8]` 과 VPN 은 0. 지우면 *)
(*                     대안 상수 ObsNoStall 이 정하는 잔재를 낸다 —         *)
(*                     "latched" 는 끝난 정지의 포착값(갈래 (B)), "live" 는 *)
(*                     조회 지점의 살아 있는 요청(갈래 (C) 비게이트).       *)
(*                     → Prop_NoStallNoData                                *)
(*   obs_read_pure     :323 읽기는 아무것도 해제하지 않는다. 지우면 STATUS  *)
(*                     읽기가 sticky 를 내린다 (read-to-clear).            *)
(*                     → Prop_ReadPure                                     *)
(*                                                                         *)
(* 고정 의미의 속성 (가드 아님 — 좋은 모델 cfg 가 건다):                   *)
(*   Prop_NoTear       `[0]` = 1 을 본 STATUS 읽기 뒤 항목 기입 전까지의 읽기는 *)
(*                     그 스냅샷과 같다 — :323 「여러 워드 읽기가 찢기지    *)
(*                     않는다」. 가드가 아니다: 성립의 몸이 관측 회로가     *)
(*                     아니라 E.4 3항(조회 지점의 일제 정지 — 정지한 요청은 *)
(*                     항목 기입이 풀기 전까지 움직이지 않는다)이고 그 RTL  *)
(*                     주장은 Decode.stall_uniform 이다. 반증력은 짝 run   *)
(*                     「새는 파이프」(상수 Pipe = "leaky")가 든다.        *)
(*   Prop_StallResolves (HostSpec 아래) 관측면만 보고 항목을 기입하는 호스트가 *)
(*                     모든 정지를 푼다 — :881 채널의 *충분성*. 짝 셋이    *)
(*                     채널 불충분을 반례로 보인다 (첫 미적중 포착 VPN ·    *)
(*                     상수 파티션 · 오늘의 RTL 「세 워드 읽기 0」).        *)
(*                                                                         *)
(* ## 발견 — 원형의 진행 짝은 말더듬 인공물에 열려 있었다 (수리함)       *)
(*                                                                         *)
(* 원형(스크래치 시안)의 HostSpec 은 공정성을 HostFill 하나에만 걸었다. 그 *)
(* 판에서 「obs_stall_live 를 지운 기계도 호스트가 결국 푼다」(PASS 기대)가 *)
(* FAIL 이었다 — 결함이 아니라 인공물이다: [0] 이 sticky 를 내면 정지가 선 *)
(* *그 스텝*의 sticky 는 아직 0 이고(set 은 다음 스텝에 반영된다), 그 상태  *)
(* 에서 켜진 동작은 Read 뿐인데 공정성이 없으니 호스트가 영영 읽지 않는     *)
(* 말더듬 행동이 Prop_StallResolves 를 깬다. 원형은 그 run 을 배터리에서    *)
(* 뺐다. 그러나 같은 인공물이 **나머지 진행 짝에도 열려 있었다** — 첫 미적중 *)
(* 포착 판(live_del_vpn)은 첫 정지 스텝에 포착 레지스터가 아직 비어 HostFill *)
(* 이 꺼진다. 그 짝의 FAIL 이 「엉뚱한 VPN 을 채운다」로 났는지 「안 읽었다」 *)
(* 로 났는지를 선언이 가르지 못한다 (TLC 는 반례 하나만 보고한다).        *)
(* 수리: HostSpec 에 읽기 공정성을 건다 — 폴링하는 호스트. 근거는 E.3 3항  *)
(*   e-defined.typ:874 「정지가 영구가 되지 않을 책임은 호스트에 있다」    *)
(* — 책임을 지는 호스트는 관측한다. 그 아래서 진행 짝의 반례는 전부 「채널이 *)
(* 틀린 것을 말한다」 뿐이고, 원형이 뺀 run 은 선언대로 PASS 다 (run.sh 의  *)
(* 대비 run — obs_stall_live 는 충분성의 가드가 아니라 Prop_StatusStall(정지  *)
(* *사실*의 정확성)의 가드다).                                              *)
(*                                                                         *)
(* ## 닫지 않은 자리 — 이 모델이 재지 않는 것                              *)
(*                                                                         *)
(*   1. 비트 배치 — [0]·[1]·[15:8] 의 자리, [15:8] 의 0 확장, VPN 의 하위 32b · *)
(*      상위 워드 분할은 RTL 조립층(Wt64Top_props.sv a_rd_xstatus ·        *)
(*      a_rd_xvpnlo · a_rd_xvpnhi)이 잰다. 이 모델의 값은 추상 기호다.     *)
(*   2. 읽기 응답의 시각(수락 다음 사이클)과 스냅샷의 포착 시점 — RTL 은    *)
(*      수락 사이클에 포착한다. 모델의 한 스텝이 그 둘을 합친다.           *)
(*   3. 파이프라인의 나머지 — 적중 요청의 여섯 단 · 승인 · 마스킹은 Leave  *)
(*      하나로 접었다. HostSpec 의 도착은 조회 지점이 비었을 때만이다.     *)
(*   4. 해제(0xE10)의 문 쪽 적법성 · 예약 — XlateSurface.tla 의 mclr_* .   *)
(*      여기의 Clear 는 수락된 해제 하나다.                                *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS
  Parts,          \* 파티션 (모델 값)
  Vpns,           \* 가상 페이지 번호 (모델 값)
  NoPart, NoVpn,  \* 관측의 「0」 — 정지 없음
  ObsNoStall,     \* obs_no_residue 를 지웠을 때 정지 없는 관측의 잔재: "latched" | "live"
  Pipe,           \* 조회 지점의 정지 — "uniform"(E.4 3항) | "leaky"(짝 — 정지한 요청이 밀려난다)
  Wired,          \* 관측 값 배선 — TRUE | FALSE(짝 — 파도 3 까지의 RTL: 세 워드 읽기 0)
  DisabledGuards

AllGuards == {"obs_stall_live", "obs_sticky", "obs_part_stalled",
              "obs_vpn_stalled", "obs_no_residue", "obs_read_pure"}

ASSUME ObsNoStall \in {"latched", "live"}
ASSUME Pipe \in {"uniform", "leaky"}
ASSUME Wired \in BOOLEAN
ASSUME NoPart \notin Parts /\ NoVpn \notin Vpns
ASSUME DisabledGuards \subseteq AllGuards

On(g) == g \notin DisabledGuards

\* 가드 삭제 obs_part_stalled 의 상수 — 파티션 값 0 (오늘의 RTL 이 [15:8] 에 내는 것).
P0 == CHOOSE p \in Parts : TRUE
V0 == CHOOSE v \in Vpns : TRUE

NoS3   == [on |-> FALSE, part |-> P0, vpn |-> V0]
NoCap  == [part |-> NoPart, vpn |-> NoVpn]
NoRd   == [kind |-> "none", st |-> FALSE, sk |-> FALSE, part |-> NoPart, vpn |-> NoVpn]
NoSnap == [on |-> FALSE, st |-> FALSE, part |-> NoPart, vpn |-> NoVpn]

VARIABLES tbl, s3, sticky, cap, rd, snap, ev
vars == <<tbl, s3, sticky, cap, rd, snap, ev>>

Stalled == s3.on /\ ~tbl[<<s3.part, s3.vpn>>]

TypeOK ==
  /\ tbl \in [Parts \X Vpns -> BOOLEAN]
  /\ s3 \in [on : BOOLEAN, part : Parts, vpn : Vpns]
  /\ sticky \in BOOLEAN
  /\ cap \in [part : Parts \cup {NoPart}, vpn : Vpns \cup {NoVpn}]
  /\ rd \in [kind : {"none", "status", "vpn"}, st : BOOLEAN, sk : BOOLEAN,
             part : Parts \cup {NoPart}, vpn : Vpns \cup {NoVpn}]
  /\ snap \in [on : BOOLEAN, st : BOOLEAN, part : Parts \cup {NoPart},
               vpn : Vpns \cup {NoVpn}]
  /\ ev \subseteq {"rdStall", "rdAfter", "rdLive", "rdStallOther", "rdNewStall",
                   "rdSnap", "leaseAfterStall"}

Init == /\ tbl = [x \in Parts \X Vpns |-> FALSE]
        /\ s3 = NoS3
        /\ sticky = FALSE
        /\ cap = NoCap
        /\ rd = NoRd
        /\ snap = NoSnap
        /\ ev = {}

(* ---- 장치가 내는 관측 — 가드 의존 ---- *)
NoStallPart == CASE On("obs_no_residue")  -> NoPart
                 [] ObsNoStall = "latched" -> cap.part
                 [] OTHER -> (IF s3.on THEN s3.part ELSE NoPart)
NoStallVpn  == CASE On("obs_no_residue")  -> NoVpn
                 [] ObsNoStall = "latched" -> cap.vpn
                 [] OTHER -> (IF s3.on THEN s3.vpn ELSE NoVpn)
DevPart == IF ~Wired THEN NoPart
           ELSE IF Stalled THEN (IF On("obs_part_stalled") THEN s3.part ELSE P0)
           ELSE NoStallPart
DevVpn  == IF ~Wired THEN NoVpn
           ELSE IF Stalled THEN (IF On("obs_vpn_stalled") THEN s3.vpn ELSE cap.vpn)
           ELSE NoStallVpn
DevSt   == IF ~Wired THEN FALSE
           ELSE IF On("obs_stall_live") THEN Stalled ELSE sticky
DevSk   == IF ~Wired THEN FALSE
           ELSE IF On("obs_sticky") THEN sticky ELSE Stalled

\* sticky — set 이 정지 레벨이고 해제를 이긴다 (StickyFault 규약 · 매 스텝 공통).
StickyNext(clr) == Stalled \/ (sticky /\ ~clr)
\* 첫 미적중 포착 — sticky 가 서는 스텝에 정지한 요청을 잡고, 정지 없는 해제에서 비운다.
CapNext(clr) == IF Stalled /\ ~sticky THEN [part |-> s3.part, vpn |-> s3.vpn]
                ELSE IF clr /\ ~Stalled THEN NoCap ELSE cap

\* 조회 지점에 요청이 도착한다. 좋은 파이프(E.4 3항)는 조회 지점이 비어야 받는다 —
\* 정지한 요청은 항목 기입이 풀 때까지 그 자리에 있다. "leaky" 는 정지한 요청을
\* 밀어낸다 (정지가 조회 지점을 얼리지 않는 파이프 — 짝 run 전용).
Arrive(p, v) ==
  /\ ~s3.on \/ Pipe = "leaky"
  /\ s3' = [on |-> TRUE, part |-> p, vpn |-> v]
  /\ sticky' = StickyNext(FALSE) /\ cap' = CapNext(FALSE)
  /\ UNCHANGED <<tbl, snap>> /\ rd' = NoRd /\ ev' = {}

\* 적중한 요청이 조회 지점을 떠난다 (적중 요청의 나머지 단은 접었다).
Leave ==
  /\ s3.on /\ ~Stalled
  /\ s3' = NoS3
  /\ sticky' = StickyNext(FALSE) /\ cap' = CapNext(FALSE)
  /\ UNCHANGED <<tbl, snap>> /\ rd' = NoRd /\ ev' = {}

\* 항목 기입(HI 커밋, V = b) — 정지를 푸는 유일한 것 (E.3 2항). 스냅샷은 여기서 끝난다.
Install(p, v, b) ==
  /\ tbl' = [tbl EXCEPT ![<<p, v>>] = b]
  /\ sticky' = StickyNext(FALSE) /\ cap' = CapNext(FALSE)
  /\ UNCHANGED s3 /\ rd' = NoRd /\ snap' = NoSnap /\ ev' = {}

\* 파티션 flush — 유효만 지운다. 정지한 요청을 바꾸지 않는다 (스냅샷 유지).
Flush(p) ==
  /\ tbl' = [x \in Parts \X Vpns |-> IF x[1] = p THEN FALSE ELSE tbl[x]]
  /\ sticky' = StickyNext(FALSE) /\ cap' = CapNext(FALSE)
  /\ UNCHANGED <<s3, snap>> /\ rd' = NoRd
  /\ ev' = IF ~Stalled /\ cap.part = p THEN {"leaseAfterStall"} ELSE {}

\* 수락된 0xE10 해제 — 정지는 풀지 않고, 정지 중이면 set 이 이긴다.
Clear ==
  /\ sticky' = StickyNext(TRUE) /\ cap' = CapNext(TRUE)
  /\ UNCHANGED <<tbl, s3, snap>> /\ rd' = NoRd /\ ev' = {}

\* 세 RO 워드의 읽기 — 한 스텝에 [0] · [1] · 파티션 · VPN 을 함께 본다 (워드 배치는
\* 이 모델 밖 — 머리 「닫지 않은 자리」 1). kind 는 증인·스냅샷이 가른다.
Read(k) ==
  /\ rd' = [kind |-> k, st |-> DevSt, sk |-> DevSk, part |-> DevPart, vpn |-> DevVpn]
  /\ sticky' = IF On("obs_read_pure") \/ k # "status" THEN StickyNext(FALSE)
               ELSE Stalled                      \* 읽기-해제 변이 (read-to-clear)
  /\ cap' = CapNext(FALSE)
  /\ snap' = IF k = "status" /\ DevSt /\ ~snap.on
               THEN [on |-> TRUE, st |-> DevSt, part |-> DevPart, vpn |-> DevVpn]
               ELSE snap
  /\ UNCHANGED <<tbl, s3>>
  /\ ev' = (IF Stalled THEN {"rdStall"} ELSE {})
           \cup (IF ~Stalled /\ sticky THEN {"rdAfter"} ELSE {})
           \cup (IF ~Stalled /\ s3.on THEN {"rdLive"} ELSE {})
           \cup (IF Stalled /\ s3.part # P0 THEN {"rdStallOther"} ELSE {})
           \cup (IF Stalled /\ cap.part # NoPart /\ cap # [part |-> s3.part, vpn |-> s3.vpn]
                   THEN {"rdNewStall"} ELSE {})
           \cup (IF snap.on THEN {"rdSnap"} ELSE {})

\* 호스트의 채움 절차 — 관측면만 보고 그 항목을 V=1 로 기입한다 (E.3 2항 · :881).
HostFill ==
  /\ DevSt /\ DevPart \in Parts /\ DevVpn \in Vpns
  /\ Install(DevPart, DevVpn, TRUE)

Next == \/ \E p \in Parts, v \in Vpns : Arrive(p, v)
        \/ Leave
        \/ \E p \in Parts, v \in Vpns, b \in BOOLEAN : Install(p, v, b)
        \/ \E p \in Parts : Flush(p)
        \/ Clear
        \/ \E k \in {"status", "vpn"} : Read(k)

Spec == Init /\ [][Next]_vars

\* 호스트는 관측면만으로 채운다 — 다른 설치는 없다 (채널의 충분성 검사).
\* 공정성 둘: 채움(켜져 있으면 결국 채운다)과 읽기(폴링 — 머리 「발견」: 읽기 공정성이
\* 없으면 「안 읽는 호스트」의 말더듬이 진행 짝의 반례를 대신한다).
HostRead == \E k \in {"status", "vpn"} : Read(k)
HostNext == \/ \E p \in Parts, v \in Vpns : Arrive(p, v)
            \/ Leave
            \/ HostFill
            \/ HostRead
HostSpec == Init /\ [][HostNext]_vars /\ WF_vars(HostFill) /\ WF_vars(HostRead)

(* ---- 가드 속성 ---- *)
Prop_StatusStall   == [][ rd'.kind = "status" => rd'.st = Stalled ]_vars           \* obs_stall_live
Prop_StatusSticky  == [][ rd'.kind = "status" => rd'.sk = sticky ]_vars            \* obs_sticky
Prop_PartStalled   == [][ (rd'.kind # "none" /\ Stalled) => rd'.part = s3.part ]_vars \* obs_part_stalled
Prop_VpnStalled    == [][ (rd'.kind # "none" /\ Stalled) => rd'.vpn = s3.vpn ]_vars   \* obs_vpn_stalled
Prop_NoStallNoData == [][ (rd'.kind # "none" /\ ~Stalled)
                           => (rd'.part = NoPart /\ rd'.vpn = NoVpn) ]_vars         \* obs_no_residue
Prop_ReadPure      == [][ rd'.kind # "none"
                           => (sticky' = StickyNext(FALSE) /\ tbl' = tbl /\ s3' = s3) ]_vars \* obs_read_pure

(* ---- 고정 의미의 속성 ---- *)
\* 여러 워드 읽기가 찢기지 않는다 — [0] = 1 을 본 뒤 항목 기입 전까지의 읽기는 스냅샷 그대로.
Prop_NoTear == [][ (snap.on /\ rd'.kind # "none")
                    => (rd'.st = snap.st /\ rd'.part = snap.part /\ rd'.vpn = snap.vpn) ]_vars
\* 채널의 충분성 — 관측면만 보는 호스트가 모든 정지를 푼다 (HostSpec 아래).
Prop_StallResolves == Stalled ~> ~Stalled

(* ---- 증인 — 위험 전건의 도달성 ---- *)
Witness_NoRdStall      == "rdStall"      \notin ev   \* 정지 중의 읽기
Witness_NoRdAfter      == "rdAfter"      \notin ev   \* 정지가 풀린 뒤 sticky 가 선 채의 읽기
Witness_NoRdLive       == "rdLive"       \notin ev   \* 조회 지점에 적중 요청이 산 채의 읽기
Witness_NoRdStallOther == "rdStallOther" \notin ev   \* 파티션 값 0 이 아닌 정지의 읽기
Witness_NoRdNewStall   == "rdNewStall"   \notin ev   \* 해제 없이 온 둘째 정지의 읽기
Witness_NoSnapRead     == "rdSnap"       \notin ev   \* 스냅샷 뒤 · 항목 기입 전의 읽기
Witness_NoLease        == "leaseAfterStall" \notin ev \* 끝난 정지의 파티션을 flush (임대 회전)
=============================================================================
