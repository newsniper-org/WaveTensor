\* SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
\* SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
----------------------------- MODULE XlateObs -------------------------------
(***************************************************************************)
(* 변환 미적중의 관측면 — `0xE04` XLATE_STATUS · `0xE08`/`0xE0C`            *)
(* XLATE_MISS_VPN 세 RO 워드가 *무엇을* 내는가의 선-formal 모델.           *)
(* 파도 4 (2026-09-26 — 판정 E04 (A) 「정지 게이트 스냅샷」).              *)
(* 3.10 v1.0 묶음 RTL 파도 W2 (2026-10-12) 가 조회 지점의 *판정 시점*과   *)
(* 판정 래치를 더했다 — 아래 「판정 래치」 절.                             *)
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
(*                     그리고 (W2) 조회 지점의 판정 시점 — 판정이 언제 서고 *)
(*                     언제까지 사는가, 그것이 없으면 채움이 수렴하는가.   *)
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
(*   tbl     장치의 *조회 시야* — (파티션, VPN) 마다 판정 값(Frames 의 한   *)
(*           값) 또는 NoFr(미적중). 항목 기입(COMMIT)과 flush 만 바꾼다.   *)
(*           시야는 채움 바이패스 > 저장 블록의 접힌 값이고 HI 커밋 에지   *)
(*           하나에 바뀐다 (XlateStore 의 채움 가림 · 바이패스→저장 이관   *)
(*           무공백). Frames 의 한 값은 판정 데이터 전부(프레임 · 권한 ·    *)
(*           fromFill)의 추상이다 — 필드별로 갈리지 않는다(같은 래치).     *)
(*   s3      조회 지점의 요청 하나 — E.4 3항: 정지는 조회 지점 한 곳이고    *)
(*           파이프 전체가 함께 서므로 동시에 정지한 요청은 하나다.         *)
(*   sticky  미적중 sticky — set 이 정지 레벨이고 해제(0xE10)를 이긴다      *)
(*           (XlateSurface.tla 발견 4 · E.1.2 `0xE10` 행의 정지 중 해제 유실). *)
(*   cap     첫 미적중 포착 레지스터 — 좋은 모델은 관측에 쓰지 않는다.      *)
(*           가드 삭제·대안(갈래 (B) 「첫 미적중 포착」)만 쓴다.           *)
(*   rd      직전 읽기의 결과 (종류 · [0] · [1] · 파티션 · VPN).            *)
(*   snap    `[0]` = 1 을 본 STATUS 읽기의 스냅샷 — 항목 기입까지 유지.   *)
(*   ev      증인 사건 꼬리표 (한 스텝짜리).                                *)
(*   lat     (W2) 장치의 판정 래치 — [on, fr]. 가드 셋이 이것을 짓는다.     *)
(*   jd      (W2) 판정 *유령* — 정본의 판정(첫 적중 사이클의 조회값)을      *)
(*           장치와 독립으로 적는다. 어느 가드도 이것을 읽지 않고, 속성의  *)
(*           참 쪽만 이것을 읽는다 (검사 어휘로 지상 진리를 적지 않는다). *)
(*   lv      (W2) 직전 Leave 가 하류로 나른 값 (한 스텝짜리) — 마스킹 입력  *)
(*           프레임 mfr 과 승인 단 소유권 조회 주소 ofr.                    *)
(*   z       (W2) 유령 — 마지막 커밋이 V=0 인 (파티션, VPN) 의 집합.        *)
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
(*                     상수(파티션 값 0)를 낸다 — 파도 3 까지의 RTL 모양.    *)
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
(*   (W2 가드 셋은 아래 「판정 래치」 절.)                                 *)
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
(*                     정지한 *그* 요청(W2 — 요청 꼬리표 tok)을 결국 풀어   *)
(*                     조회 지점에서 떠나보낸다 —                           *)
(*                     :881 채널의 *충분성*과 결과 (h) 의 수렴. 짝 셋이    *)
(*                     채널 불충분을 반례로 보인다 (첫 미적중 포착 VPN ·    *)
(*                     상수 파티션 · 파도 3 까지의 RTL 「세 워드 읽기 0」). *)
(*                     넷째 짝(W2)이 래치 없는 판의 라이브락을 보인다.      *)
(*   (W2 의 고정 속성 둘은 아래 「판정 래치」 절.)                         *)
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
(* ## 판정 래치 — 3.10 v1.0 묶음 RTL 파도 W2 (2026-10-12)                  *)
(*                                                                         *)
(* 정본 (같은 줄 축자 결속):                                               *)
(*   03-hiu.typ:734 「처음 적중한 사이클이다」 — 판정 시점.                 *)
(*   03-hiu.typ:735 「요청이 조회 지점을 떠날 때까지 유지되고, 그 뒤의 커밋 · flush 는 그 요청의」 *)
(*   03-hiu.typ:737 「같은 값으로 쓰인다」 — 소유권 조회 주소와 마스킹 입력 프레임. *)
(*   03-hiu.typ:738 「판정 래치는 경로를 가르지 않는다」                     *)
(*   03-hiu.typ:741 「수락되면 풀리고, 그 커밋 항목으로 판정된다」           *)
(*   03-hiu.typ:742 「전에 다른 커밋이 그 항목을 밀어내도 다시 미적중하지 않는다」 *)
(*   03-hiu.typ:746 「래치를 어떤 회로로 두는지 — 정지 조건과」 — 회로는 재구현의 일이다. *)
(*   03-hiu.typ:754 「조회 지점 뒤의 단이 배압으로 서 있으면 풀린 요청이 조회 지점에 머물고」 *)
(*   03-hiu.typ:755 「사이에 같은 파티션의 다른 커밋이 그 칸을 덮으면 요청은」 — 반례의 몸. *)
(*   03-hiu.typ:756 「정지와 커밋이 엇갈리는 동안 드라이버의 채움이 수렴한다는」 *)
(*   03-hiu.typ:763 「한 단이라도 저장 블록을 다시 읽으면 한 요청이 두」     *)
(*   03-hiu.typ:1323 「조회에만 효력이 있다」 — 철회(V=0 · flush)의 효력 범위. *)
(*   03-hiu.typ:1324 「스냅샷을 들고 끝까지 간다」                          *)
(*   03-hiu.typ:1329 「완전한 철회 = V=0 · flush + 그 에지 뒤의 드레인 관측.」 — 드레인 절반은 닫힌 목록 14. *)
(*   03-hiu.typ:2075 「flush 또는 V=0 COMMIT 의 에지 뒤에 판정되는 조회에서」 — HIU-2. *)
(*   03-hiu.typ:2078 「에지 이전에 판정된 요청은 이 속성의 범위 밖이다」      *)
(*   e-defined.typ:310 「효력은 그 커밋 에지 뒤에 판정되는 조회에만 미친다 — 그 전에 판정이 래치된 요청은 래치된 판정으로 끝까지 간다」 — 결과 (a). *)
(*   e-defined.typ:310 「V=0 COMMIT 뒤 같은 (파티션, VPN) 조회는 반드시 미적중이다.」 — 결과 (b). 여기서 재는 것은 그 *판정 시점 범위*뿐이다 — 저장 측은 닫힌 목록 15. *)
(*   e-defined.typ:310 「축출은 같은 파티션 안에서만 일어난다」 — 결과 (c).   *)
(*   e-defined.typ:310 「풀린 그 요청은 그 커밋 항목으로 판정되고」 — 결과 (d). *)
(*   e-defined.typ:312 「자발 축출은 없다」 — 결과 (h). 이 모델에서는 구조다 — 닫힌 목록 13. *)
(*   e-defined.typ:312 「장치는 축출을 같은 파티션에 대한 호스트 COMMIT 과 flush 의 결과로만 한다」 — HostSpec 경쟁자. *)
(*   e-defined.typ:312 「그러므로 (d) 와 함께 드라이버는 미적중 채움으로 언제나 수렴한다」 *)
(*   e-defined.typ:873 「풀린 요청은 그 커밋 항목으로 판정된다」 — E.3 2항의 좁힘. *)
(*   e-defined.typ:914 「판정의 래치는 상태를 가르지 않으므로 2항은 그대로 선다」 *)
(*                                                                         *)
(* ### 모델 변경                                                           *)
(*                                                                         *)
(*   · tbl 이 판정 값을 든다 (불리언 → Frames ∪ {NoFr}). 대체 커밋(같은    *)
(*     (파티션, VPN) 의 V=1 재커밋)이 값을 바꿀 수 있어야 판정 *유지*를     *)
(*     잴 수 있다.                                                         *)
(*   · Install(p, v, f, E) — f = NoFr 이 V=0 COMMIT 이다. E 는 같은 파티션의 *)
(*     다른 VPN 집합에서 비결정으로 고른 축출 집합이다(결과 (c) · (h): 축출은 *)
(*     같은 파티션 COMMIT 의 결과로만, 다른 파티션 불가). 용량 · 연관도 ·  *)
(*     교체 정책은 형상이므로 *임의 부분집합*으로 과근사한다 — 속성은 어느  *)
(*     형상에서도 서야 한다(정합성은 용량에 기대지 않는다).                *)
(*   · Stalled == s3.on ∧ ¬lat.on ∧ 조회 미적중. Leave 의 전건은 ¬Stalled  *)
(*     — 곧 lat.on ∨ 조회 적중이다. 관측(DevSt · missStall)도 이 Stalled 를 *)
(*     읽는다 — 래치된 요청은 정지가 아니다.                               *)
(*   · Leave 가 하류로 나르는 값 lv = [mfr, ofr]. 승인 · 마스킹 단은 이    *)
(*     모델에 없으므로(머리 「닫힌 목록」 3) 두 값을 Leave 하나로 접었다.  *)
(*   · LeaveArrive(p, v) — 연속 전진: 조회 지점의 요청이 떠나고 다음 요청이 *)
(*     같은 에지에 들어온다(RTL 에서 s3 는 advance 에 s2 에서 적재된다 — 정상 *)
(*     흐름). 래치 비움의 시각 · 우선순위가 다음 요청에 닿는 유일한 에지다. *)
(*     Arrive 는 조회 지점이 빈 때의 도착(거품 뒤)으로 남는다.             *)
(*   · tok — 도착마다 뒤집히는 요청 꼬리표(유령). 요청별 진행 속성만 읽는다. *)
(*   · HostSpec 에 경쟁자(HostCompete — 정지 중인 요청의 (파티션, VPN) 밖의 *)
(*     COMMIT, V=1 · V=0, 같은 파티션 축출 포함 — 풀린 · 래치된 요청 자신의  *)
(*     항목의 철회 · 대체도 포함 · HostFlush — flush)와 하류                *)
(*     배압(Depart = Leave ∨ LeaveArrive 의 *약한* 공정성)을 더했다. 경쟁자 *)
(*     둘은 결과 (h) 가 이름한 축출 원인 그대로다. 하류 hold 는 조회 지점의 *)
(*     상태와 독립이라 「떠날 수 있음」이 끊길 때마다 배압이 그 틈에 걸리는 *)
(*     정렬을 배제할 근거가 없다 — 약한 공정성이 정확히 그것을 허용한다.   *)
(*   · Alts — 대안 넷(아래 「대안 넷」). 가드가 아니다: 가드 삭제는 그 가드의 *)
(*     RTL 항을 *지운* 판이고, 대안은 그 항을 그럴듯하게 *잘못 지은* 판이다. *)
(*   · 큰 cfg 는 VIEW StateView 로 돈다 — 한 스텝짜리 출력(rd · ev · lv)과   *)
(*     요청 꼬리표 tok 를 접는다. 건전성 근거는 StateView 정의 위 주석이다. *)
(*     작은 cfg 와 삭제 · 대안 · 짝 · 증인 cfg 는 VIEW 없이 돈다.            *)
(*                                                                         *)
(* ### 래치 포착의 원자성 — 왜 「스텝 이전 조회값」을 잡아도 되는가        *)
(*                                                                         *)
(* 모델의 한 스텝은 클럭 에지 하나다. 래치(와 유령 jd)는 *모든* 스텝에서    *)
(* 그 스텝이 떠나는 상태의 조회값을 잡는다 — RTL 레지스터가 에지에서 그     *)
(* 사이클의 조합 조회값을 잡는 것과 같다. 근거 셋:                        *)
(*   1. 판정과 포착은 같은 조합값이다. RTL 의 s3→s4 캡처(lookFrame →       *)
(*      io.mask.req.frame · s4.frame)와 래치 포착은 같은 사이클의 같은     *)
(*      조회 출력을 먹는다 — 판정한 값과 래치된 값 사이에 끼는 사이클이     *)
(*      없다.                                                              *)
(*   2. 커밋 에지와 래치 에지 사이에 끼어들 에지가 없다. 채움 적중은 HI    *)
(*      커밋 에지 다음 사이클에 바이패스로 보이고 그 사이클 끝 에지가      *)
(*      포착한다. 그 사이클에 같은 파티션의 다음 기입은 채움 슬롯 점유      *)
(*      (install.ready = 슬롯 비어 있음)로 수락되지 않는다 — 수락되더라도   *)
(*      그 효과는 포착 에지 *뒤*다. 모델은 더 관대하다: 적중이 보이고       *)
(*      래치가 아직 빈 중간 상태를 명시적으로 두고, 거기서 어떤 동작(같은   *)
(*      파티션 축출 · V=0 · flush 포함)이든 같은 스텝에 오게 한다. 그       *)
(*      스텝의 포착은 여전히 중간 상태의 조회값이다 — 판정이 그 에지 *앞*에 *)
(*      났으므로 e-defined.typ:310 「효력은 그 커밋 에지 뒤에 판정되는 조회에만 미친다」 *)
(*      이 정확히 이것이다. 그 관대함의 값: BFS 최단 반례(래치 삭제판 · 짝  *)
(*      「오늘의 RTL」)는 축출 · 철회를 *첫 적중 사이클 끝 에지*에 둔다 — RTL *)
(*      에서는 그 에지가 같은 파티션 커밋을 받지 않으므로(채움 슬롯 점유)   *)
(*      그 꼴 그대로는 재현되지 않는다. RTL 에서 가능한 꼴은 hold ≥ 2 사이클 *)
(*      뒤의 경쟁 커밋이고(수락 C → C+1 바이패스 적중 · 슬롯 해제 → C+2 경쟁 *)
(*      수락 → C+3 가림으로 재미적중), 모델은 그 꼴도 허용한다(사이에 다른  *)
(*      스텝). 끝-끝 시험은 RTL 꼴을 쓴다.                                  *)
(*   3. tbl 은 조회 *시야*다 — 채움 가림이 대기 중인 줄을 그 항목의 가장  *)
(*      새 판으로 보이게 하고 바이패스→저장 이관에 관측 공백이 없으므로     *)
(*      (XlateStore 의 가림 주석), 커밋 하나는 시야를 한 에지에 한 번만    *)
(*      바꾼다. 그래서 Install 한 스텝이 HI 커밋 에지 하나다.              *)
(* 이 판은 map 이 제안한 원자 포착(「tbl 이 참이 되는 스텝의 다음 상태에서 *)
(* lat 이 선다」 — 중간 상태를 접는다)보다 인터리빙을 *더* 허용한다 —     *)
(* 접힌 판의 행동은 전부 이 판의 행동이므로 이 판의 PASS 가 접힌 판의      *)
(* PASS 를 함의한다.                                                       *)
(*                                                                         *)
(* ### 가드 셋 (W2)                                                        *)
(*                                                                         *)
(*   verdict_latch       :734 · :735 첫 적중 사이클에 판정을 래치하고 떠날  *)
(*                       때까지 유지한다 — 래치가 정지를 막고(Stalled 의    *)
(*                       ¬lat.on 항) 하류 값을 댄다(EffFr). 지우면 W2 전   *)
(*                       RTL(HEAD 9b6eee6 — 래치 없음, 매 사이클 다시 판정): *)
(*                       판정된 요청이 hold 로 머무는 동안 그 항목이 철회되 *)
(*                       거나 같은 파티션의 다른 VPN 커밋에 밀려나면 다시   *)
(*                       정지한다. → Prop_NoReMiss (깊이 3 — BFS 최단은 V=0 *)
(*                       철회 꼴; 축출 꼴은 짝 「오늘의 RTL(W2 전 — HEAD     *)
(*                       9b6eee6)」이 HostSpec 에서 보인다). 이 가드는 RTL  *)
(*                       항 둘(정지 쪽 lookAny · 값 쪽 lookFrame/lookPerm 의 *)
(*                       마지막 대입)을 묶는다 — 값 절반만 빠진 판은 대안   *)
(*                       value_no_latch 이고 그 반증은 고정 속성             *)
(*                       Prop_LatchedSurvivesRetract 가 든다.               *)
(*   latch_clears_on_leave  :735 판정은 *그 요청의* 것이다 — 요청이 조회   *)
(*                       지점을 떠나는 *그* 에지(advance)에 래치를 비우고,  *)
(*                       그 에지의 포착보다 앞선다. 지우면 다음 요청이 앞   *)
(*                       요청의 판정을 물려받아 미적중인데도 정지하지       *)
(*                       않는다. → Prop_NoInheritedVerdict (깊이 3 — 연속   *)
(*                       전진). 「같은 에지」와 「포착보다 앞」은 대안 둘    *)
(*                       (clear_late · capture_beats_clear)이 따로 반증한다. *)
(*   latch_one_value     :737 · :763 래치된 판정은 승인 단의 소유권 조회    *)
(*                       주소와 마스킹 입력 프레임에 같은 값으로 쓰인다.    *)
(*                       지우면 소유권 조회가 떠나는 시점의 저장 시야를     *)
(*                       다시 읽는다 — 래치 뒤 대체 · 축출 · 철회가 있으면  *)
(*                       한 요청이 두 판정을 갖는다. → Prop_OneValue (깊이 4) *)
(*   깊이는 BFS 최단 반례의 스텝 수다 (run.sh 머리에 실측).                *)
(*                                                                         *)
(* ### 속성 (W2) — 참 쪽은 전부 유령(jd · z)과 정본 술어다                  *)
(*                                                                         *)
(*   Prop_NoReMiss              판정된 요청(jd.on)은 정지하지 않는다 —     *)
(*                              결과 (d) 의 「다시 미적중하지 않는다」.    *)
(*                              관측면(`[0]`)이 매 사이클 보는 축이라      *)
(*                              상태 속성이다.                             *)
(*   Prop_NoInheritedVerdict    자기 조회로 판정되지 않은 요청(CanonV 꺼짐) *)
(*                              은 정지한다 — 장치가 그 요청을 판정된 것으로 *)
(*                              다루지 않는다. NoReMiss 와 합쳐 「Stalled  *)
(*                              ⇔ 조회 지점의 요청에 정본 판정이 없음」.  *)
(*   Prop_OneValue              Leave 가 나르는 두 값(마스킹 · 소유권)이   *)
(*                              같다.                                      *)
(*   고정 의미 둘 (가드 아님 — 반증력은 상주 run 이 든다):                  *)
(*   Prop_LatchedSurvivesRetract  Leave 가 나르는 마스킹 값은 그 요청의     *)
(*                              정본 판정(첫 적중 조회값)이다 — 판정 뒤의  *)
(*                              철회(V=0 · flush)도 대체 커밋도 바꾸지      *)
(*                              못한다 (:1324 스냅샷 · 결과 (a)). 철회가    *)
(*                              정본의 대표 사례라 이름이 그렇다. 값이     *)
(*                              *소비되는* 자리가 떠나는 에지(s3→s4 캡처)  *)
(*                              이므로 Leave 에서 잰다. 반증: verdict_latch *)
(*                              삭제판 단독 cfg(깊이 4 — 같은 VPN 대체 커밋 *)
(*                              뒤 떠남).                                  *)
(*   Prop_V0AfterEdgeMisses     마지막 커밋이 V=0 인 (파티션, VPN) 의 요청이 *)
(*                              그 에지 전에 판정되지 않았으면 정지한다 —  *)
(*                              HIU-2 V=0 축의 *판정 시점 범위*(V=0 → 미적중 *)
(*                              자체는 이 모델에서 구조다 — 닫힌 목록 15).  *)
(*                              불변식 Key∈z ⇒ tbl[Key]=NoFr 아래 이것은     *)
(*                              NoInheritedVerdict 의 V=0 사례다(그 함의를  *)
(*                              숨기지 않는다 — 따로 둔 이유는 HIU-2 문면과 *)
(*                              의 일대일 결속이고, 반증은 latch_clears_on_ *)
(*                              leave 삭제판 단독 cfg 가 든다).             *)
(*   Prop_StickyRiseOnStall     미적중 sticky `[1]` 은 정본 판정이 없는     *)
(*                              요청이 조회 지점에 있는 스텝에만 선다 —     *)
(*                              :742 「다시 미적중하지 않는다」의 관측면 꼴. *)
(*                              참 쪽은 유령 CanonV 만 읽는다. 다른 속성은   *)
(*                              sticky 를 모델 자신의 StickyNext 와 대조해   *)
(*                              set 원천을 재지 못했다. 반증: 대안           *)
(*                              sticky_raw_miss.                            *)
(*   진행: Prop_StallResolves 는 「정지한 *그* 요청은 결국 떠난다」다 —    *)
(*   (Stalled ∧ tok = b) ~> (¬s3.on ∨ tok ≠ b). 아래 「발견 (W2)」 · 「발견 *)
(*   (W2 독립 반증)」. 옛 꼴 둘은 대비 run 전용으로 남는다 — Prop_StallLifts *)
(*   (정지가 순간 걷힘) · Prop_StallEmpties (조회 지점이 빈다).             *)
(*                                                                         *)
(* ### 대안 넷 (W2) — 그럴듯한 RTL 결함, 각각 상주 MUST FAIL run           *)
(*                                                                         *)
(*   clear_late          래치 비움이 떠난 *다음* 에지(RegNext(s3.valid ∧     *)
(*                       advance)) → Prop_NoInheritedVerdict (깊이 3)        *)
(*   capture_beats_clear when(포착).elsewhen(advance) 비움 — 첫 적중 에지에  *)
(*                       떠나는 요청의 포착이 비움을 이긴다                  *)
(*                       → Prop_NoInheritedVerdict (깊이 3)                  *)
(*   sticky_raw_miss     [1] 의 set 이 원시 미적중(s3.valid ∧ ¬조회 적중)    *)
(*                       → Prop_StickyRiseOnStall (깊이 4)                   *)
(*   value_no_latch      값 쪽 마지막 대입 없음(정지 쪽 래치만) — 유효 값이 *)
(*                       늘 조회값 → Prop_LatchedSurvivesRetract (깊이 4)   *)
(*   앞 둘은 연속 전진(LeaveArrive)이 있어야 운다 — 거품 하나를 강제하던    *)
(*   판에서는 둘 다 배터리 전체를 통과했다(아래 「발견 (W2 독립 반증)」).   *)
(*                                                                         *)
(* ### 발견 (W2) — 옛 진행 속성은 라이브락에 눈멀었다                       *)
(*                                                                         *)
(* 옛 Prop_StallResolves 는 Stalled ~> ¬Stalled 였다. 래치를 지운 판에 경쟁 *)
(* 커밋자와 하류 배압을 주면 「정지 → 호스트 채움으로 풀림 → hold 로 머묾 → *)
(* 경쟁 커밋이 축출 → 다시 정지」가 영원히 돈다(03-hiu.typ:756 「정지와 커밋이 엇갈리는 동안 드라이버의 채움이 수렴한다는」 *)
(* 보장이 흔들리는 바로 그 꼴). 그런데 그 행동에서 *매* 정지는 순간이나마  *)
(* 풀린다 — 옛 꼴은 이 라이브락을 통과시킨다(대비 run 실측 PASS). 결과 (h) *)
(* 의 「수렴」은 요청이 결국 *떠나는* 것이므로 진행 속성을 「떠남」으로     *)
(* 강화했다. 새 꼴은 옛 꼴을 함의한다(떠난 요청은 정지가 아니다).          *)
(* 옛 진행 짝 셋의 판정은 바뀌지 않는다 — 그 셋은 래치가 살아 있어 풀린   *)
(* 요청의 떠남이 계속 켜져 있고(약한 공정성이 떠나게 한다), 그러므로 그    *)
(* 셋의 반례는 여전히 「풀리지 않음」뿐이다.                               *)
(*                                                                         *)
(* ### 발견 (W2 독립 반증) — 거품 하나가 비움의 시각을 가렸다 (수리함)     *)
(*                                                                         *)
(* 첫 판의 Arrive 는 조회 지점이 비어야 받았다 — 떠남과 다음 도착 사이에   *)
(* 언제나 거품 스텝이 있었다. RTL 에서 s3 는 advance 에 s2 에서 적재되므로  *)
(* 연속 요청이 정상이다. 거품 아래에서는 「떠나는 그 에지에 비움」과 「한    *)
(* 에지 늦은 비움」 · 「포착이 비움을 이김」이 가려지지 않는다 — 거품 에지가 *)
(* 늦은 비움을 대신 해 준다. 독립 반증의 변이 둘(M2b · M18)이 작은 · 진행 · *)
(* 큰 run 을 전부 통과했고, 연속 전진을 들이자 둘 다 3 스텝에             *)
(* Prop_NoInheritedVerdict 로 운다 — 다음 요청이 앞 요청의 판정(다른       *)
(* 파티션 것일 수 있다)을 물려받는 HIU-1 꼴이다(반례: Arrive(p1,v1) ·      *)
(* Install(p1,v1,f1) · LeaveArrive(p2,v1) — p2 의 미적중 요청이 p1 의 판정을 *)
(* 든다). 수리: LeaveArrive 를 Next · HostNext 에 넣고 두 결함을 상주 대안 *)
(* 으로 둔다. 역대조(2026-10-12 비상주 실측): Next 에서 LeaveArrive 만 뺀  *)
(* 사본에서는 두 대안 모두 작은 좋은 cfg(속성 전부)를 통과한다 — 연속 전진 *)
(* 이 그 반증력의 몸이다. 그 값으로 「떠남」을 Stalled ~> ¬s3.on 으로 적던 *)
(* 진행 속성이 좋은 모델에서도 깨졌다 — 요청이 끊임없이 이어지면 조회      *)
(* 지점이 영영 비지 않는다(대비 run 실측). 그 꼴은 거품이 강제될 때만      *)
(* 「그 요청이 떠난다」였다. 그래서 진행을 요청 꼬리표 tok 로 다시 적었다.   *)
(*                                                                         *)
(* ### RTL GUARD-MAP 예정 문면 (HiuPipeline.scala 클래스 끝 — 줄 중립)      *)
(*                                                                         *)
(*   XlateObs.verdict_latch -> missWait = s3.valid ∧ ¬lookAny, lookAny =   *)
(*     래치 적중 ∨ 조회 적중(xlate.io.rsp.hit). 래치 레지스터(이름 고정 —  *)
(*     익명 when 안 Reg 금지)는 s3.valid ∧ ¬래치 ∧ 조회 적중인 사이클 끝에  *)
(*     조회값(hit · frame · perm · fromFill)을 잡고, 유효 값은 래치 ? 래치값 *)
(*     : 조회값 이다(lookFrame · lookPerm 의 마지막 대입 · lookFill). 이 줄은 *)
(*     항 둘(정지 쪽 lookAny · 값 쪽 마지막 대입)을 묶는다 — 값 절반의      *)
(*     반증은 고정 속성 Prop_LatchedSurvivesRetract 가 든다(대안            *)
(*     value_no_latch). RTL 측정은 hiumask l_hold.                          *)
(*   XlateObs.latch_clears_on_leave -> when(advance) 가 래치를 비운다 —     *)
(*     요청이 떠나는 *그* 에지이고(지연 비움 아님 — 대안 clear_late 가 반증) *)
(*     포착(.elsewhen)보다 앞이며(대안 capture_beats_clear 가 반증) reset   *)
(*     값도 빈 래치다(reset 형식 단언은 W1-8 이월 — 닫힌 목록 8). advance 는 *)
(*     s3 의 요청이 s4 로 넘어가는 바로 그 enable 이고, 같은 에지에 s2 의   *)
(*     요청이 s3 로 들어온다(연속 전진). RTL 측정은 hiumask l_clear — 연속  *)
(*     전진의 에지를 덮어야 한다.                                           *)
(*   XlateObs.latch_one_value -> io.mask.req.frame 과 s4.frame(승인 단      *)
(*     io.owner.frame 의 원천)이 같은 lookFrame 한 신호에서 온다 — 어느 단도 *)
(*     저장 블록을 다시 읽지 않는다(s5 · s6 은 s4.frame 을 나른다).         *)
(*   함께 고칠 문면:                                                       *)
(*   · obs_part_stalled · obs_vpn_stalled · obs_no_residue · Wt64Top 의     *)
(*     obs_stall_live 줄의 「missWait = s3.valid ∧ ¬적중」 → 「¬(래치 ∨     *)
(*     적중)」. Wt64Top 의 obs_sticky 줄 「StickyFault(set = missWait …)」 *)
(*     은 글자로는 참으로 남지만 missWait 가 판정 래치를 아는 정지라는 말을 *)
(*     더한다 (닫힌 목록 16).                                              *)
(*   · 머리 GUARD-MAP 의 Isolation.query_no_serve 「lookAny = hit」 → 래치  *)
(*     ∨ hit(래치는 로컬 조회값만 잡는다 — 호스트 leg 가지 없음).            *)
(*   · Decode.stall_uniform 「나머지 단 · 필드 전부가 when(advance)」 →     *)
(*     래치는 단계 레지스터가 아니다(데이터만 들고 advance 에 비워지며      *)
(*     enable 이 아니다).                                                  *)
(*   · Decode.lookup_unbranched 「s4 캡처 데이터로만 · 유일한 제어는        *)
(*     advance」 → 조회 결과는 s4 캡처와 판정 래치의 *데이터*로만 흐른다.   *)
(*     래치 포착 enable 은 데이터 레지스터의 enable 이지 단계 제어가 아니다 *)
(*     (상태열 불변 — 닫힌 목록 9 의 몫이 이 줄이다). 래치가 들어오면 옛    *)
(*     문면은 글자 그대로 거짓이 된다 (Y4 r2 회신 §2 항 2 가 요청 · r2-ack  *)
(*     §2 #2 가 수용).                                                     *)
(*   · 같은 식(「missWait = s3.valid ∧ ¬조회 적중」)을 축자로 옮겨 적은 곳 — *)
(*     XlateStaging 의 XlateSurface.mclr_keeps_stall GUARD-MAP 줄(W3 소유 —  *)
(*     W2 에서 줄 중립으로 고칠지 W3 이월로 적을지는 착지 판정) ·           *)
(*     HiuMask_props.sv 의 호스트 leg 증인 주석(「`missWait = s3_valid &&   *)
(*     !x_hit` 이므로」 — W2-4 하네스) · xlatestore.sby 의 정지 인용(W2-5). *)
(*                                                                         *)
(* ## 닫힌 목록 — 이 모델이 재지 않는 것과 그 몫                          *)
(*                                                                         *)
(*   1. 비트 배치 — [0]·[1]·[15:8] 의 자리, [15:8] 의 0 확장, VPN 의 하위 32b · *)
(*      상위 워드 분할은 RTL 조립층(Wt64Top_props.sv a_rd_xstatus ·        *)
(*      a_rd_xvpnlo · a_rd_xvpnhi)이 잰다. 이 모델의 값은 추상 기호다.     *)
(*   2. 읽기 응답의 시각(수락 다음 사이클)과 스냅샷의 포착 시점 — RTL 은    *)
(*      수락 사이클에 포착한다. 모델의 한 스텝이 그 둘을 합친다. 몫은 RTL  *)
(*      조립층 a_rd_xstatus · a_rd_xvpnlo · a_rd_xvpnhi 다 — 수락 다음      *)
(*      사이클의 rvalid 와 rdata = 수락 사이클 핀 값($past)을 등식으로 잰다. *)
(*   3. 파이프라인의 나머지 — 적중 요청의 여섯 단 · 승인 · 마스킹은 떠남   *)
(*      하나로 접었다. 도착은 조회 지점이 비었을 때(Arrive)와 앞 요청이     *)
(*      떠나는 같은 에지(LeaveArrive — 연속 전진)뿐이다. 두 소비 값(마스킹  *)
(*      입력 · 소유권 조회 주소)이 실제로 s4 · s6 에서 같은 값인지는        *)
(*      hiumask l_one_value 몫이다.                                        *)
(*   4. 해제(0xE10)의 문 쪽 적법성 · 예약 — XlateSurface.tla 의 mclr_* .   *)
(*      여기의 Clear 는 수락된 해제 하나다.                                *)
(*   5. (W2) 판정 데이터의 필드별 분리 — 프레임 · 권한 · fromFill 은 한 값  *)
(*      으로 접었다. 필드마다 같은 래치 · 같은 비움을 타는지는 hiumask      *)
(*      l_hold 몫이다.                                                     *)
(*   6. (W2) 포착 게이트 — 모델의 포착 조건은 「조회 적중(유효 게이트된 값)」 *)
(*      하나이고 가드가 아니다(지울 RTL 줄이 이 모델의 축이 아니다). 래치가 *)
(*      저장 값의 새 보유 경로이므로 「포착은 유효 게이트된 적중에서만」은  *)
(*      하네스 l_capture_gated 몫이고, HIU-3 정적 검사는 아직 없다.         *)
(*   7. (W2) 축출의 형상 — 용량 · 연관도 · 교체 정책은 임의 부분집합 축출로 *)
(*      과근사했다. 「다른 파티션 축출 불가」는 이 모델에서 구조이고 측정은 *)
(*      Isolation.capacity_partitioned · XlateSurface 몫이다.              *)
(*   8. (W2) reset 비움 — reset 형식 단언은 이 파도에서 하지 않는다(W1-8    *)
(*      이월). Init 의 빈 래치가 reset 값의 모델이다.                      *)
(*   9. (W2) 상태열 불변 — 래치가 단계 수를 바꾸지 않음(:738 · E.4 2항)은   *)
(*      Decode.stall_uniform · lookup_unbranched 몫이다. Leave 는 단계 수를 *)
(*      갖지 않는다.                                                       *)
(*  10. (W2) 다중 조회 지점 형상 — 결과 (h) 끝 문장의 「판정 래치는 조회    *)
(*      지점마다」는 v1.0 밖이다(단일 조회 지점 전제).                     *)
(*  11. (W2) 하류 배압의 유한성 — 외부 io.hold 가 영원히 서지 않는다는 것  *)
(*      (Depart 의 약한 공정성)은 *환경 가정*이다. HIU 정본 의무가 아니고  *)
(*      소비자 쪽 몫이며, 이 RTL 파도의 어느 하위 파도의 몫도 아니다. W3 의 *)
(*      「하류 정지 유계」는 다른 축이다 — 그것은 COMMIT 버스 정지다:       *)
(*      e-defined.typ:308 「하류 채움 슬롯이 찬 동안의 *적법한* COMMIT 은 버스를 배압으로 정지시킨다」. *)
(*      이 가정 없이는 Prop_StallResolves 의 「떠남」을 주장하지 않는다 —  *)
(*      그때 남는 것은 공정성 없이 Spec 아래 서는 안전 속성 Prop_NoReMiss *)
(*      (판정된 요청은 다시 정지하지 않는다)다.                            *)
(*  12. (W2) 커밋 문 — 어떤 기입이 수락되는 COMMIT 인가(스테이징 · 거절 ·   *)
(*      하류 정지)는 XlateSurface.tla 몫이다. 여기의 Install 은 수락된     *)
(*      COMMIT 하나다.                                                     *)
(*  13. (W2) 결과 (h) 「자발 축출은 없다」 — 이 모델에서 축출은 Install(같은 *)
(*      파티션 COMMIT) · Flush 밖에 없으므로 구조다. 진행 PASS 가 여기      *)
(*      기댄다. RTL 측정 몫은 XlateSurface.evict_on_commit_only(W3 —       *)
(*      Prop_TableByDoor, 앵커 xlatestore). 7 은 「다른 파티션            *)
(*      축출 불가」만 다룬다.                                               *)
(*  14. (W2) 3.7.2 완전한 철회의 드레인 관측 절반 — 판정된 요청(s3 래치     *)
(*      포함)이 드레인 정의역(3.7.2 「드레인의 정의역」 첫 항 — 요청        *)
(*      파이프라인 안의 요청)에 드는가는 이 모델 밖이다. 이 모델은 판정     *)
(*      유지(:1324 스냅샷)만 잰다. RTL 에서 래치된 요청은 s3.valid 로 HIU   *)
(*      점유(io.occupancy — 여섯 단 valid 의 수)에 들고, 조립층            *)
(*      a_drain_order 가 그 핀의 DRAIN 결선을 잰다. 점유 = 단 valid 의 수   *)
(*      자체를 재는 단언은 없다 — 미측정이다. 승인 뒤 소비분은 메모리      *)
(*      파이프 착지의 선행 조건(B.5)이다.                                  *)
(*  15. (W2) 결과 (b) 의 저장 측 — V=0 커밋이 그 (파티션, VPN) 를 조회      *)
(*      시야에서 미적중으로 만든다(대기 줄 가림 · 유효 비트 운반) — 는 이   *)
(*      모델에서 Install 의 구조(f = NoFr 대입)다. 측정 몫은                *)
(*      XlateSurface.commit_v_carried(저장 절반 xlatestore · 문 절반     *)
(*      조립층)와 W3 의 Prop_V0Misses(새 문 위 V=0 → 미적중 — HIU-2 의    *)
(*      V=0 축)다. 여기서 재는 것은 판정 시점 범위                        *)
(*      (Prop_V0AfterEdgeMisses)뿐이다.                                    *)
(*  16. (W2) `[1]` set 원천의 RTL 결선 — 모델은 결과를 Prop_StickyRiseOnStall *)
(*      로 재고 대안 sticky_raw_miss 가 반증한다. RTL 에서 그 원천은        *)
(*      StickyFault(set = missWait) 이고 missWait 가 판정 래치를 아는       *)
(*      정지이므로 따라 선다 — 결선 몫은 XlateObs.obs_sticky 의 GUARD-MAP   *)
(*      줄(Wt64Top)과 hiumask m_sticky(지상 진리 f_stall ∧ ¬f_lat 상속)다.  *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS
  Parts,          \* 파티션 (모델 값)
  Vpns,           \* 가상 페이지 번호 (모델 값)
  Frames,         \* (W2) 판정 값 — 프레임 · 권한 · fromFill 의 추상 (모델 값)
  NoPart, NoVpn,  \* 관측의 「0」 — 정지 없음
  NoFr,           \* (W2) 미적중 — 판정 값 없음
  ObsNoStall,     \* obs_no_residue 를 지웠을 때 정지 없는 관측의 잔재: "latched" | "live"
  Pipe,           \* 조회 지점의 정지 — "uniform"(E.4 3항) | "leaky"(짝 — 정지한 요청이 밀려난다)
  Wired,          \* 관측 값 배선 — TRUE | FALSE(짝 — 파도 3 까지의 RTL: 세 워드 읽기 0)
  Alts,           \* (W2) 대안 구현 — 좋은 모델은 {}. 머리 「대안 넷」 (가드가 아니다)
  DisabledGuards

AllGuards == {"obs_stall_live", "obs_sticky", "obs_part_stalled",
              "obs_vpn_stalled", "obs_no_residue", "obs_read_pure",
              "verdict_latch", "latch_clears_on_leave", "latch_one_value"}

\* (W2) 그럴듯한 RTL 결함의 모델 — 각각 상주 MUST FAIL run 하나가 반증력을 든다.
AllAlts == {"clear_late", "capture_beats_clear", "sticky_raw_miss", "value_no_latch"}

ASSUME ObsNoStall \in {"latched", "live"}
ASSUME Pipe \in {"uniform", "leaky"}
ASSUME Wired \in BOOLEAN
ASSUME NoPart \notin Parts /\ NoVpn \notin Vpns /\ NoFr \notin Frames
ASSUME DisabledGuards \subseteq AllGuards
ASSUME Alts \subseteq AllAlts

On(g) == g \notin DisabledGuards
Alt(a) == a \in Alts

\* 가드 삭제 obs_part_stalled 의 상수 — 파티션 값 0 (파도 3 까지의 RTL 이 [15:8] 에 내던 것).
P0 == CHOOSE p \in Parts : TRUE
V0 == CHOOSE v \in Vpns : TRUE

FrV == Frames \cup {NoFr}

NoS3   == [on |-> FALSE, part |-> P0, vpn |-> V0]
NoCap  == [part |-> NoPart, vpn |-> NoVpn]
NoRd   == [kind |-> "none", st |-> FALSE, sk |-> FALSE, part |-> NoPart, vpn |-> NoVpn]
NoSnap == [on |-> FALSE, st |-> FALSE, part |-> NoPart, vpn |-> NoVpn]
NoLat  == [on |-> FALSE, fr |-> NoFr]          \* 빈 래치 · 판정 없음 (lat 과 jd 가 같은 꼴)
NoLv   == [on |-> FALSE, mfr |-> NoFr, ofr |-> NoFr]

VARIABLES tbl, s3, sticky, cap, rd, snap, ev, lat, jd, lv, z, tok
vars == <<tbl, s3, sticky, cap, rd, snap, ev, lat, jd, lv, z, tok>>
\* 큰 cfg 의 VIEW (규모 run 전용). 한 스텝짜리 출력 rd · ev · lv 와 요청 꼬리표 tok 는 좋은
\* 모델(Alts = {})에서 어느 동작의 가드도 갱신도 읽지 않는다 — tok 는 자기 반전만 한다 — 그
\* 넷만 다른 두 상태의 후속은 같다. 큰 cfg 가 거는 속성은 rd · lv 를 프라임(전이)으로만 읽고
\* tok 는 읽지 않으며, TLC 는 이미 본 VIEW 로 가는 전이에도 행동 속성을 검사한다
\* (2026-10-12 탐침 실측). ev 를 상태로 읽는 증인과 tok 를 읽는 진행 속성은 큰 cfg 에 걸지
\* 않는다. 대안 clear_late 는 lv.on 을 읽으므로 VIEW 아래 돌리지 않는다.
StateView == <<tbl, s3, sticky, cap, snap, lat, jd, z>>

(* ---- 조회 지점 ---- *)
Key  == <<s3.part, s3.vpn>>
Look == tbl[Key]                       \* 조회 지점의 조합 조회값 (NoFr = 미적중)
Hit  == s3.on /\ Look # NoFr

\* 장치의 정지 — 래치된 요청은 정지가 아니다 (missWait = s3.valid ∧ ¬(래치 ∨ 적중)).
Stalled == s3.on /\ ~lat.on /\ Look = NoFr

\* 정본 판정 — 이미 판정됐으면 그 판정(유령 jd), 아니면 지금 조회가 적중하면 그 값.
\* 장치와 독립이다(가드를 읽지 않는다). 매 스텝 jd' 가 이것이다 — 첫 적중 사이클의 값.
CanonV == IF jd.on THEN jd
          ELSE IF Hit THEN [on |-> TRUE, fr |-> Look] ELSE NoLat

\* 장치 래치의 차기 값 — 스텝 이전의 조회값을 잡는다(머리 「원자성」). 가드 verdict_latch.
\* 대안 clear_late: 비움이 떠난 *다음* 에지에 선다 — 그 지연 비움 대기 RegNext(s3.valid ∧
\* advance) 는 「직전 스텝이 떠남」이고 그것이 lv.on 그 자체다. 대기가 포착을 이긴다.
LatNext == IF ~On("verdict_latch") THEN NoLat
           ELSE IF Alt("clear_late") /\ lv.on THEN NoLat
           ELSE IF lat.on THEN lat
           ELSE IF Hit THEN [on |-> TRUE, fr |-> Look] ELSE NoLat
\* 떠나는(또는 밀려나는) 요청 뒤의 래치 — 가드 latch_clears_on_leave: 떠나는 *그* 에지에
\* 비우고, 그 에지의 포착보다 앞선다. 대안 clear_late 는 이 에지에 비우지 않고, 대안
\* capture_beats_clear 는 첫 적중 에지에 떠나는 요청의 포착이 비움을 이긴다.
LatAfterLeave == IF On("latch_clears_on_leave") /\ ~Alt("clear_late")
                    /\ ~(Alt("capture_beats_clear") /\ ~lat.on)
                 THEN NoLat ELSE LatNext

\* 장치의 유효 판정 값 — 래치 ? 래치값 : 조회값 (마스킹 입력 프레임). 대안 value_no_latch 는
\* 값 쪽 마지막 대입이 없다(정지 쪽 래치만 있다 — 유효 값이 늘 조회값).
EffFr == IF lat.on /\ ~Alt("value_no_latch") THEN lat.fr ELSE Look
\* 승인 단 소유권 조회 주소 — 가드 latch_one_value. 지우면 떠나는 시점의 저장 시야를 다시 읽는다.
OwnFr == IF On("latch_one_value") THEN EffFr ELSE Look

TypeOK ==
  /\ tbl \in [Parts \X Vpns -> FrV]
  /\ s3 \in [on : BOOLEAN, part : Parts, vpn : Vpns]
  /\ sticky \in BOOLEAN
  /\ cap \in [part : Parts \cup {NoPart}, vpn : Vpns \cup {NoVpn}]
  /\ rd \in [kind : {"none", "status", "vpn"}, st : BOOLEAN, sk : BOOLEAN,
             part : Parts \cup {NoPart}, vpn : Vpns \cup {NoVpn}]
  /\ snap \in [on : BOOLEAN, st : BOOLEAN, part : Parts \cup {NoPart},
               vpn : Vpns \cup {NoVpn}]
  /\ ev \subseteq {"rdStall", "rdAfter", "rdLive", "rdStallOther", "rdNewStall",
                   "rdSnap", "leaseAfterStall",
                   "evictJudged", "retractJudged", "replaceJudged", "arriveV0"}
  /\ lat \in [on : BOOLEAN, fr : FrV]
  /\ jd \in [on : BOOLEAN, fr : FrV]
  /\ lv \in [on : BOOLEAN, mfr : FrV, ofr : FrV]
  /\ z \subseteq Parts \X Vpns
  /\ tok \in BOOLEAN

Init == /\ tbl = [x \in Parts \X Vpns |-> NoFr]
        /\ s3 = NoS3
        /\ sticky = FALSE
        /\ cap = NoCap
        /\ rd = NoRd
        /\ snap = NoSnap
        /\ ev = {}
        /\ lat = NoLat
        /\ jd = NoLat
        /\ lv = NoLv
        /\ z = {}
        /\ tok = FALSE

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
\* 대안 sticky_raw_miss: set 이 판정 래치를 모르는 원시 미적중(s3.valid ∧ ¬조회 적중)이다.
StickySet == IF Alt("sticky_raw_miss") THEN s3.on /\ Look = NoFr ELSE Stalled
StickyNext(clr) == StickySet \/ (sticky /\ ~clr)
\* 첫 미적중 포착 — sticky 가 서는 스텝에 정지한 요청을 잡고, 정지 없는 해제에서 비운다.
CapNext(clr) == IF Stalled /\ ~sticky THEN [part |-> s3.part, vpn |-> s3.vpn]
                ELSE IF clr /\ ~Stalled THEN NoCap ELSE cap

\* 조회 지점에 요청이 도착한다. 좋은 파이프(E.4 3항)는 조회 지점이 비어야 받는다 —
\* 정지한 요청은 항목 기입이 풀 때까지 그 자리에 있다. "leaky" 는 정지한 요청을
\* 밀어낸다 (정지가 조회 지점을 얼리지 않는 파이프 — 짝 run 전용). 새 요청은 아직
\* 판정되지 않았다(jd' 빔) — 첫 조회는 도착 *다음* 상태의 조합값이다. 요청 꼬리표 tok 가
\* 도착마다 뒤집힌다 — 요청별 진행 속성이 「그 요청」을 가리키는 유일한 손잡이다.
Arrive(p, v) ==
  /\ ~s3.on \/ Pipe = "leaky"
  /\ s3' = [on |-> TRUE, part |-> p, vpn |-> v]
  /\ sticky' = StickyNext(FALSE) /\ cap' = CapNext(FALSE)
  /\ lat' = LatAfterLeave /\ jd' = NoLat /\ lv' = NoLv /\ tok' = ~tok
  /\ UNCHANGED <<tbl, snap, z>> /\ rd' = NoRd
  /\ ev' = IF <<p, v>> \in z THEN {"arriveV0"} ELSE {}

\* 판정된(또는 이 에지에 판정이 서는) 요청이 조회 지점을 떠난다 — s3→s4 캡처(advance).
\* 하류로 나르는 값: 마스킹 입력 mfr = 유효 판정 값, 소유권 조회 주소 ofr (가드 latch_one_value).
Leave ==
  /\ s3.on /\ ~Stalled
  /\ s3' = NoS3
  /\ lv' = [on |-> TRUE, mfr |-> EffFr, ofr |-> OwnFr]
  /\ lat' = LatAfterLeave /\ jd' = NoLat /\ tok' = tok
  /\ sticky' = StickyNext(FALSE) /\ cap' = CapNext(FALSE)
  /\ UNCHANGED <<tbl, snap, z>> /\ rd' = NoRd /\ ev' = {}

\* 연속 전진 — 조회 지점의 요청이 떠나고 다음 요청이 *같은 에지*에 들어온다 (RTL 에서 s3 는
\* advance 에 s2 에서 적재되므로 이것이 정상 흐름이다). 래치 비움의 시각 · 우선순위가 여기서만
\* 다음 요청에 닿는다 — 머리 「발견 (W2 독립 반증)」.
LeaveArrive(p, v) ==
  /\ s3.on /\ ~Stalled
  /\ s3' = [on |-> TRUE, part |-> p, vpn |-> v]
  /\ lv' = [on |-> TRUE, mfr |-> EffFr, ofr |-> OwnFr]
  /\ lat' = LatAfterLeave /\ jd' = NoLat /\ tok' = ~tok
  /\ sticky' = StickyNext(FALSE) /\ cap' = CapNext(FALSE)
  /\ UNCHANGED <<tbl, snap, z>> /\ rd' = NoRd
  /\ ev' = IF <<p, v>> \in z THEN {"arriveV0"} ELSE {}

\* 조회 지점의 요청이 떠나는 전진 — 하류 배압의 약한 공정성이 거는 동작 (머리 「모델 변경」).
Depart == Leave \/ \E p \in Parts, v \in Vpns : LeaveArrive(p, v)

\* 판정된 요청의 항목에 닿는 커밋의 증인 꼬리표 — 위험 전건의 도달성. 전건 jd.on(스텝 이전)
\* 은 「앞 스텝에 이미 판정이 래치된 요청」이다 — 첫 적중 사이클(래치가 아직 빈) 에지의 커밋은
\* 꼬리표를 받지 않는다 (RTL 에서 그 에지는 채움 슬롯 점유로 같은 파티션 커밋을 받지 않는다 —
\* 머리 「원자성」 2).
JudgedEv(p, v, f, E) ==
  LET own == s3.on /\ p = s3.part /\ v = s3.vpn
  IN  (IF jd.on /\ ~own /\ p = s3.part /\ s3.vpn \in E /\ Look # NoFr
          THEN {"evictJudged"} ELSE {})
      \cup (IF jd.on /\ own /\ f = NoFr /\ Look # NoFr
               THEN {"retractJudged"} ELSE {})
      \cup (IF jd.on /\ own /\ f # NoFr /\ f # jd.fr
               THEN {"replaceJudged"} ELSE {})

\* 수락된 COMMIT (HI) — 값 f 를 (p, v) 에 커밋한다. f = NoFr 이 V=0 COMMIT 이다.
\* E 는 같은 파티션의 다른 VPN 중 이 커밋이 축출하는 것 (결과 (c) · (h) — 형상 중립 과근사).
\* 정지를 푸는 유일한 것 (E.3 2항). 스냅샷은 여기서 끝난다.
Install(p, v, f, E) ==
  /\ tbl' = [x \in Parts \X Vpns |->
               IF x = <<p, v>> THEN f
               ELSE IF x[1] = p /\ x[2] \in E THEN NoFr
               ELSE tbl[x]]
  /\ z' = IF f = NoFr THEN z \cup {<<p, v>>} ELSE z \ {<<p, v>>}
  /\ sticky' = StickyNext(FALSE) /\ cap' = CapNext(FALSE)
  /\ lat' = LatNext /\ jd' = CanonV /\ lv' = NoLv
  /\ UNCHANGED <<s3, tok>> /\ rd' = NoRd /\ snap' = NoSnap
  /\ ev' = JudgedEv(p, v, f, E)

\* 파티션 flush — 유효만 지운다. 정지한 요청을 바꾸지 않는다 (스냅샷 유지).
Flush(p) ==
  /\ tbl' = [x \in Parts \X Vpns |-> IF x[1] = p THEN NoFr ELSE tbl[x]]
  /\ sticky' = StickyNext(FALSE) /\ cap' = CapNext(FALSE)
  /\ lat' = LatNext /\ jd' = CanonV /\ lv' = NoLv
  /\ UNCHANGED <<s3, snap, z, tok>> /\ rd' = NoRd
  /\ ev' = (IF ~Stalled /\ cap.part = p THEN {"leaseAfterStall"} ELSE {})
           \cup (IF jd.on /\ p = s3.part /\ Look # NoFr
                    THEN {"retractJudged"} ELSE {})

\* 수락된 0xE10 해제 — 정지는 풀지 않고, 정지 중이면 set 이 이긴다.
Clear ==
  /\ sticky' = StickyNext(TRUE) /\ cap' = CapNext(TRUE)
  /\ lat' = LatNext /\ jd' = CanonV /\ lv' = NoLv
  /\ UNCHANGED <<tbl, s3, snap, z, tok>> /\ rd' = NoRd /\ ev' = {}

\* 세 RO 워드의 읽기 — 한 스텝에 [0] · [1] · 파티션 · VPN 을 함께 본다 (워드 배치는
\* 이 모델 밖 — 머리 「닫힌 목록」 1). kind 는 증인·스냅샷이 가른다.
Read(k) ==
  /\ rd' = [kind |-> k, st |-> DevSt, sk |-> DevSk, part |-> DevPart, vpn |-> DevVpn]
  /\ sticky' = IF On("obs_read_pure") \/ k # "status" THEN StickyNext(FALSE)
               ELSE Stalled                      \* 읽기-해제 변이 (read-to-clear)
  /\ cap' = CapNext(FALSE)
  /\ snap' = IF k = "status" /\ DevSt /\ ~snap.on
               THEN [on |-> TRUE, st |-> DevSt, part |-> DevPart, vpn |-> DevVpn]
               ELSE snap
  /\ lat' = LatNext /\ jd' = CanonV /\ lv' = NoLv
  /\ UNCHANGED <<tbl, s3, z, tok>>
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
  /\ \E f \in Frames, E \in SUBSET (Vpns \ {DevVpn}) : Install(DevPart, DevVpn, f, E)

Next == \/ \E p \in Parts, v \in Vpns : Arrive(p, v)
        \/ Leave
        \/ \E p \in Parts, v \in Vpns : LeaveArrive(p, v)
        \/ \E p \in Parts, v \in Vpns : \E f \in FrV, E \in SUBSET (Vpns \ {v}) :
              Install(p, v, f, E)
        \/ \E p \in Parts : Flush(p)
        \/ Clear
        \/ \E k \in {"status", "vpn"} : Read(k)

Spec == Init /\ [][Next]_vars

\* 호스트는 관측면만으로 채운다 (채널의 충분성 검사). (W2) 경쟁자가 함께 돈다 — 정지한
\* 요청의 (파티션, VPN) 밖의 COMMIT(V=1 · V=0, 같은 파티션 축출 포함)과 flush 이고 공정성이
\* 없다 (결과 (h) 가 이름한 축출 원인 둘 — 같은 파티션 호스트 COMMIT 과 flush).
\* 정지한 요청 자신의 항목은 *정지 중에는* HostFill 만 쓴다 — 그래서 정지를 푸는 것은 여전히
\* 관측면이다. 정지가 아닌 동안(풀린 · 래치된 요청)에는 그 요청 자신의 항목도 경쟁자의 철회
\* (V=0) · 대체(다른 값의 V=1) 대상이다 — 결과 (a) 「그 전에 판정이 래치된 요청은」 의 꼴.
\* 공정성 셋: 채움(켜져 있으면 결국 채운다) · 읽기(폴링 — 머리 「발견」: 읽기 공정성이
\* 없으면 「안 읽는 호스트」의 말더듬이 진행 짝의 반례를 대신한다) · (W2) 떠남(하류 배압 —
\* 약한 공정성: 요청이 *계속* 떠날 수 있으면 결국 떠난다 — 홀로 떠나든 연속 전진이든.
\* 이것은 환경 가정이다 — 머리 「닫힌 목록」 11).
HostRead == \E k \in {"status", "vpn"} : Read(k)
HostCompete ==
  \E p \in Parts, v \in Vpns : \E f \in FrV, E \in SUBSET (Vpns \ {v}) :
     /\ ~(Stalled /\ p = s3.part /\ v = s3.vpn)
     /\ Install(p, v, f, E)
HostFlush == \E p \in Parts : Flush(p)
HostNext == \/ \E p \in Parts, v \in Vpns : Arrive(p, v)
            \/ Depart
            \/ HostFill
            \/ HostRead
            \/ HostCompete
            \/ HostFlush
HostSpec == Init /\ [][HostNext]_vars
            /\ WF_vars(HostFill) /\ WF_vars(HostRead) /\ WF_vars(Depart)

(* ---- 가드 속성 ---- *)
Prop_StatusStall   == [][ rd'.kind = "status" => rd'.st = Stalled ]_vars           \* obs_stall_live
Prop_StatusSticky  == [][ rd'.kind = "status" => rd'.sk = sticky ]_vars            \* obs_sticky
Prop_PartStalled   == [][ (rd'.kind # "none" /\ Stalled) => rd'.part = s3.part ]_vars \* obs_part_stalled
Prop_VpnStalled    == [][ (rd'.kind # "none" /\ Stalled) => rd'.vpn = s3.vpn ]_vars   \* obs_vpn_stalled
Prop_NoStallNoData == [][ (rd'.kind # "none" /\ ~Stalled)
                           => (rd'.part = NoPart /\ rd'.vpn = NoVpn) ]_vars         \* obs_no_residue
Prop_ReadPure      == [][ rd'.kind # "none"
                           => (sticky' = StickyNext(FALSE) /\ tbl' = tbl /\ s3' = s3) ]_vars \* obs_read_pure
\* (W2) 판정된 요청은 다시 정지하지 않는다 — 결과 (d).                      \* verdict_latch
Prop_NoReMiss           == [](jd.on => ~Stalled)
\* (W2) 자기 조회로 판정되지 않은 요청은 정지한다 — 판정은 그 요청의 것이다. \* latch_clears_on_leave
Prop_NoInheritedVerdict == []((s3.on /\ ~CanonV.on) => Stalled)
\* (W2) 떠나는 요청의 마스킹 입력과 소유권 조회 주소는 같은 값이다.          \* latch_one_value
Prop_OneValue           == [][ lv'.on => lv'.ofr = lv'.mfr ]_vars

(* ---- 고정 의미의 속성 ---- *)
\* 여러 워드 읽기가 찢기지 않는다 — [0] = 1 을 본 뒤 항목 기입 전까지의 읽기는 스냅샷 그대로.
Prop_NoTear == [][ (snap.on /\ rd'.kind # "none")
                    => (rd'.st = snap.st /\ rd'.part = snap.part /\ rd'.vpn = snap.vpn) ]_vars
\* (W2) 떠나는 요청의 값은 그 요청의 정본 판정이다 — 판정 뒤의 철회 · 대체가 바꾸지 못한다.
Prop_LatchedSurvivesRetract == [][ lv'.on => lv'.mfr = CanonV.fr ]_vars
\* (W2) 마지막 커밋이 V=0 인 항목의 요청은, 그 에지 전에 판정되지 않았으면 정지한다.
Prop_V0AfterEdgeMisses == []((s3.on /\ ~jd.on /\ Key \in z) => Stalled)
\* (W2) 미적중 sticky `[1]` 은 정본 판정이 없는 요청이 조회 지점에 있는 스텝에만 선다 —
\* 판정된 요청의 항목이 밀려나도 「미적중이 있었다」를 남기지 않는다 —
\* 03-hiu.typ:742 「전에 다른 커밋이 그 항목을 밀어내도 다시 미적중하지 않는다」 의 관측면 꼴.
Prop_StickyRiseOnStall == [][ (~sticky /\ sticky') => (s3.on /\ ~CanonV.on) ]_vars
\* 채널의 충분성 + 수렴 — 관측면만 보는 호스트 아래 정지한 *그* 요청은 결국 떠난다 (HostSpec
\* 아래). 「그 요청」은 도착마다 뒤집히는 꼬리표 tok 로 가리킨다 — 조회 지점이 비거나 다음
\* 요청이 들어왔으면(연속 전진) 그 요청은 떠난 것이다.
Prop_StallResolves == \A b \in BOOLEAN : (Stalled /\ tok = b) ~> (~s3.on \/ tok # b)
\* 대비 전용 — 조회 지점이 언젠가 빈다. 연속 전진 아래 좋은 모델도 깬다(정상 흐름이 s3 를
\* 영영 채운다) — 진행을 요청 꼬리표로 적은 근거 (머리 「발견 (W2 독립 반증)」).
Prop_StallEmpties == Stalled ~> ~s3.on
\* 옛 꼴 — 정지가 (순간이라도) 걷힌다. 라이브락을 통과시킨다 (대비 run 전용 — 머리 「발견 (W2)」).
Prop_StallLifts == Stalled ~> ~Stalled

(* ---- 증인 — 위험 전건의 도달성 ---- *)
Witness_NoRdStall      == "rdStall"      \notin ev   \* 정지 중의 읽기
Witness_NoRdAfter      == "rdAfter"      \notin ev   \* 정지가 풀린 뒤 sticky 가 선 채의 읽기
Witness_NoRdLive       == "rdLive"       \notin ev   \* 조회 지점에 적중 요청이 산 채의 읽기
Witness_NoRdStallOther == "rdStallOther" \notin ev   \* 파티션 값 0 이 아닌 정지의 읽기
Witness_NoRdNewStall   == "rdNewStall"   \notin ev   \* 해제 없이 온 둘째 정지의 읽기
Witness_NoSnapRead     == "rdSnap"       \notin ev   \* 스냅샷 뒤 · 항목 기입 전의 읽기
Witness_NoLease        == "leaseAfterStall" \notin ev \* 끝난 정지의 파티션을 flush (임대 회전)
\* (W2)
Witness_NoHoldAfterHit        == ~jd.on                       \* 판정된 요청이 떠나지 않고 머문다 (하류 배압)
\* 아래 셋의 전건은 「앞 스텝에 판정이 래치된 요청」(jd.on — JudgedEv 주석)이다.
Witness_NoEvictWhileLatched   == "evictJudged"   \notin ev   \* 래치된 요청의 항목을 같은 파티션 다른 VPN 커밋이 축출
Witness_NoRetractWhileLatched == "retractJudged" \notin ev   \* 래치된 요청의 항목을 V=0 · flush 가 무효로
Witness_NoReplaceWhileLatched == "replaceJudged" \notin ev   \* 래치된 요청의 항목을 다른 값의 V=1 재커밋이 대체
Witness_NoArriveAfterV0       == "arriveV0"      \notin ev   \* 마지막 커밋이 V=0 인 (파티션, VPN) 에 요청이 도착
=============================================================================
