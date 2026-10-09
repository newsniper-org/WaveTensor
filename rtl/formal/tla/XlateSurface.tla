\* SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
\* SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
--------------------------- MODULE XlateSurface -----------------------------
(***************************************************************************)
(* 변환 저장소의 MMIO 문 — `0xC00` 항목 배열(XLATE_ENTRY_LO/HI)과          *)
(* `0xE00` XLATE_FLUSH 의 선-formal 모델. 파도 3 (2026-09-26). 파도 4 개정 *)
(* (같은 날): 판정 T5 (a) · T4 (ii) 를 가드 둘로 실었다 — 아래 「판정」.     *)
(* 같은 날 수리: `0xE10` XLATE_MISS_CLEAR 와 RO 세 워드(`0xE04`–`0xE0C`)의 *)
(* 쓰기 처분을 더했다 — RTL 이 모델보다 먼저 배선한 결정(검토자 D-7)을    *)
(* 6.3 규율대로 모델로 돌려보낸 것이다 (아래 「가드」 다섯 · 판정 4).      *)
(*                                                                         *)
(* ## 분업 — 이 모델은 「문」만 잰다                                       *)
(*                                                                         *)
(*   XlateStore.tla    저장 블록 — 유효 게이팅 · 파티션 격리 · flush 가    *)
(*                     데이터를 남긴다 (조회의 정확성).                    *)
(*   Isolation.tla     조회·채움의 비간섭 — 설치 범위 · 채움 슬롯.         *)
(*   XlateSurface.tla  호스트가 두드리는 *문* — 두 워드로 쪼개진 항목 기입의 *)
(*                     스테이징·커밋 원자성, flush 발화의 범위, 거절의 처분, *)
(*                     하류 거부의 처분, `0xE10` 해제와 미적중 정지의 관계, *)
(*                     RO 쓰기의 처분. 어느 모델에도 없던 제어면이다.      *)
(*                                                                         *)
(* 두 모델이 「설치」와 「flush」를 원자 동작 하나로 두는 자리를 이 모델이 *)
(* 연다: 호스트는 32b 버스로 한 번에 한 워드만 쓰므로 항목 하나(64b)는 두  *)
(* 번의 기입이고, 그 사이의 상태가 관측면에 실재한다.                      *)
(*                                                                         *)
(* 정본 (좌표 뒤 「」 는 그 줄의 축자 — lint_section_refs 축 1 이 대조한다): *)
(*   e-defined.typ:306 「기입은 스테이징이며 표에 커밋되지 않는다」        *)
(*     — XLATE_ENTRY_LO(+0x0, WO).                                         *)
(*   03-hiu.typ:1552 「HI 가 항목 전체(V 포함)를 단일 에지에 커밋한다」 *)
(*   03-hiu.typ:1552 「LO 는 스테이징(항목 번호 래치 · reset 은 빈 스테이징)이고」 *)
(*   03-hiu.typ:1552 「번호 불일치 · 빈 스테이징의 HI 는 거절 + `[6]` 이고 아무것도 움직이지 않는다」 *)
(*   e-defined.typ:308 「`[31]` V — 유효」 — XLATE_ENTRY_HI(+0x4, WO). V 는 호스트가 *)
(*     쓰는 필드다: HI `[31]`=0 은 단일 항목 무효화다.                     *)
(*   03-hiu.typ:1552 「HI 가 항목 전체(V 포함)를 단일 에지에 커밋한다」 *)
(*   e-defined.typ:308 「유효 비트를 담은 워드가 마지막이므로 부분 기입 상태가 유효해질 수 없다」 *)
(*   e-defined.typ:321 「기입이 곧 발화」 — XLATE_FLUSH(`0xE00`, WO).      *)
(*   e-defined.typ:321 「`[31:8]` 예약 = 0 (엄격)」                        *)
(*   e-defined.typ:321 「지우는 것은 그 파티션의 유효 비트뿐이고 태그·변환 데이터는 남는다」 *)
(*   e-defined.typ:321 「없는 파티션 값의 기입은 거절 + loud fault 다」    *)
(*   e-defined.typ:414 「실재하지 않는 파티션 값의 기입은 수락되지 않고 거절 + loud fault 다」 *)
(*   e-defined.typ:415 「이므로 FAULT_STATUS `[6]` 에 접는다」             *)
(*   e-defined.typ:419 「조용한 무시는 금지다」                            *)
(*   e-defined.typ:188 「워드 안의 예약 비트는 엄격이다」                  *)
(*   e-defined.typ:1541 「XLATE_FLUSH 로 그 파티션의 변환 유효 비트를 지운다」 *)
(*     — E.9 6항 임대 회전 ⑵.                                              *)
(*   e-defined.typ:1547 「한꺼번에 비우는 전역 발화는 이 표면에 없고, 있어서도 안 된다」 *)
(*   e-defined.typ:873 「호스트가 항목을 기입하면 정지가 풀린다」 — E.3 2항. *)
(*     항목 기입이 버스에서 조용히 사라지면 이 문장이 이행 불가능해진다.   *)
(*   03-hiu.typ:778 「유효 비트가 유일한 방벽이다」                        *)
(*   e-defined.typ:329 「`[0]` 에 1 기입 = 미적중 sticky 해제 · `[31:1]` 예약 = 0 (엄격)」 *)
(*     — XLATE_MISS_CLEAR(`0xE10`, WO).                                    *)
(*   e-defined.typ:329 「*정지 자체는 이것으로 풀리지 않는다* — 정지를 푸는 것은 항목 기입뿐이다」 *)
(*   e-defined.typ:202 「*RO 오프셋의 쓰기* — 거절 + loud fault 다」 — `0xE04` *)
(*     XLATE_STATUS · `0xE08`/`0xE0C` XLATE_MISS_VPN_LO/HI.                *)
(*                                                                         *)
(* ## 이 모델이 잡는 정확한 결함                                           *)
(*                                                                         *)
(* 오늘(HEAD e90d3f1)의 Wt64Top 은 `0xC00`–`0xDFF` 와 `0xE00`–`0xE7F` 를 구역 *)
(* 으로 *열거*만 하고(`selXent` · `selXctl` → `selUnwired`) 소비자가 없다. 그 *)
(* 구역의 쓰기는 예약 오프셋 정책(쓰기 무시)으로 **조용히 흡수**되고, 항목 *)
(* 설치와 flush 는 최상위 IO(`io.install` · `io.flush`)로만 닿는다. 임대 회전 *)
(* ⑵ 를 따르는 드라이버의 `0xE00` flush 는 사라지고 호스트는 지우지 않은   *)
(* 파티션을 지웠다고 믿는다 —                                              *)
(*   e-defined.typ:419 「flush 를 조용히 삼키면 호스트는 지우지 않은」     *)
(* (파도 2 가 정본 판정 요청 T1 로 기록한 자리). 짝 run 「오늘의 RTL」 둘이 *)
(* 그 기계와 동형이다:                                                     *)
(*   flush 쪽  flush_fires · reject_loud 삭제 → Prop_FlushClears 반례.     *)
(*             항목은 HI 문으로 세운다 — 오늘의 RTL 에서 항목이 서는 유일한 *)
(*             길인 최상위 `io.install` 의 대역이다.                       *)
(*   항목 쪽   hi_fires · flush_fires · reject_loud 삭제 → Prop_HiCommits 반례. *)
(* 실측 하나: 문 셋을 다 지운 판에 Prop_FlushClears 를 걸면 *통과한다* — 설치 *)
(* 경로가 문 하나뿐인 모델에서 HI 문까지 닫으면 표에 산 항목이 없어 flush  *)
(* 결함이 공허하게 숨는다. 그래서 flush 쪽 짝은 HI 문을 남긴다.            *)
(*                                                                         *)
(* 그리고 문을 *순진하게* 붙이면 생기는 결함 둘을 미리 잡는다:             *)
(*   (a) XlateStore 의 `install` 포트에는 V 필드가 없다 — 설치는 언제나 유효를 *)
(*       세운다. HI `[31]`=0 기입을 그 포트에 그대로 물리면 무효화하려던   *)
(*       항목이 *유효해진다.* hi_v_carried 삭제가 그 배선과 동형이고       *)
(*       Prop_ValidFromV 가 반례를 낸다 (Witness_NoKill 이 그 입력의 도달성). *)
(*   (b) 스테이징에 유효 비트 없이 번호만 래치하면 reset 직후 래치 번호(E0)와 *)
(*       같은 항목의 HI 한 워드가 한 번도 쓰이지 않은 프레임(Junk)으로     *)
(*       커밋된다 — HI 만 쓴 부분 기입이 유효해진다. hi_needs_staging 삭제. *)
(*                                                                         *)
(* ## 설계 결정 — 하류 거부(`install.ready` = 0)의 처분                    *)
(*                                                                         *)
(* XlateStore 의 `install.ready` 는 그 파티션의 채움 슬롯이 차 있거나 같은 *)
(* 파티션 flush 와 겹치면 내려간다 — *적법한* HI 가 하류에서 거부될 수 있다. *)
(* 조용한 드롭은 금지다(:419). 모델은 상수 Refusal 로 세 갈래를 다 표현하고 *)
(* 기계가 판정한다:                                                        *)
(*   "stall"   버스 정지 — mmio ready 를 내려 그 기입을 수락하지 않고 잡아 *)
(*             둔다. 슬롯이 비면 *같은 기입*이 단일 에지에 커밋된다.  ← 좋은 모델 *)
(*   "reject"  거절 + loud (FAULT_STATUS `[6]`).  → Prop_RejectOnlyMalformed 위반 *)
(*   "drop"    조용한 흡수.                        → Prop_HiCommits 위반   *)
(* reject 가 틀린 이유: `[6]` 은 「거절된 구성 기입」이고 정본이 HI 에 준 거절 *)
(* 사유는 번호 불일치 하나다. 옳은 LO→HI 순서를 지킨 드라이버가 사이클     *)
(* 타이밍 하나로 fault 를 받는다 — 같은 행위가 타이밍에 따라 두 판정을     *)
(* 받는다(MaskEngine 머리말이 이름한 관측 결손의 형태). 두 워드는 WO 이고  *)
(* 읽기 0 이라 드라이버는 *어느* 기입이 떨어졌는지 되읽을 수도 없다.       *)
(* stall 이 맞는 이유: 정본의 일반 처분이 배압이다 —                       *)
(*   e-defined.typ:871 「요청은 배압으로 정지하고」                        *)
(*   e-defined.typ:1337 「장치는 배압으로 정지한다」                       *)
(* 그리고 이 정지는 호스트 조치 없이 풀린다 — 채움 슬롯의 저장 커밋은 버스와 *)
(* 독립이다. LiveSpec 아래 Prop_StallEnds 가 통과하고, 그 공정성(Drain)을 뺀 *)
(* 짝이 실패한다 — 풀림이 정확히 그 의무에 걸려 있다는 뜻이다.             *)
(*                                                                         *)
(* ## 가드 — 각각 정본 한 문장. 지우면 자기 속성만 깨진다                  *)
(*                                                                         *)
(*   lo_stages_only     :306 스테이징 — LO 는 표에 닿지 않는다.            *)
(*                      지우면 LO 가 표의 프레임을 곧장 덮는다(쓰기 관통) — *)
(*                      살아 있는 항목이 옛 태그·새 프레임으로 찢긴다.     *)
(*                      → Prop_LoStagesOnly                                *)
(*   hi_fires           :306 HI 기입이 커밋 발화다. 지우면 적법한 HI 가    *)
(*                      흡수된다(오늘의 RTL). → Prop_HiCommits             *)
(*   hi_entry_match     :306 번호 불일치 HI 는 거절. 지우면 다른 항목에    *)
(*                      스테이징된 프레임이 이 항목으로 커밋된다.          *)
(*                      → Prop_MismatchRejected                            *)
(*   hi_needs_staging   :308 부분 기입 상태는 유효해질 수 없다 — 스테이징이 *)
(*                      빈 HI 는 거절. 지우면 위 (b). → Prop_UnstagedRejected *)
(*   hi_commit_whole    :308 단일 에지 커밋. 지우면 V 가 먼저 서고 프레임이 *)
(*                      다음 에지에 앉는다 — 유효한데 옛 프레임인 상태가 한 *)
(*                      스텝 관측된다. → Prop_HiCommitWhole                *)
(*   hi_v_carried       :308 V 는 쓴 값이다. 지우면 위 (a). → Prop_ValidFromV *)
(*   flush_fires        :321 기입이 곧 발화. 지우면 적법한 flush 가 흡수된다 *)
(*                      (오늘의 RTL · T1). → Prop_FlushClears              *)
(*   flush_scoped       :1547 전역 발화 금지. 지우면 flush(p) 가 전 파티션을 *)
(*                      비운다. → Prop_FlushScoped                         *)
(*   flush_valid_only   :321 유효 비트뿐. 지우면 데이터까지 지운다.        *)
(*                      → Prop_FlushKeepsData (저장 쪽 구조 보장은         *)
(*                      XlateStore.flush_keeps_data 가 잰다 — 여기는 문이  *)
(*                      발화하는 효과의 범위다)                            *)
(*   flush_part_exists  :321 · :414 없는 파티션 값은 거절. 지우면 필드가 폭에 *)
(*                      맞춰 잘려 *다른 실재 파티션*이 flush 된다.         *)
(*                      → Prop_PhantomRejected                             *)
(*   flush_rsv_strict   :321 · :188 예약 엄격. 지우면 예약 위반 flush 가   *)
(*                      실행된다. → Prop_RsvRejected                       *)
(*   reject_loud        :419 조용한 무시 금지 — 거절은 전부 `[6]` 을 세운다. *)
(*                      지우면 거절이 조용하다. → Prop_RejectLoud          *)
(*                                                                         *)
(*   아래 다섯 — `0xE10` · RO 세 워드 (같은 날 수리, 아래 판정 4 와 함께)   *)
(*   mclr_fires         :329 `[0]`=1 · 예약 0 의 기입이 미적중 sticky 를     *)
(*                      내린다 (정지가 없을 때). 지우면 해제가 흡수된다 —  *)
(*                      착지 전 RTL 의 `0xE10`. → Prop_MclrClears           *)
(*   mclr_needs_one     :329 해제는 `[0]`=1 기입뿐이다. 지우면 `[0]`=0 기입도 *)
(*                      sticky 를 내린다 — 호스트가 모르는 새 미적중 기록이 *)
(*                      사라진다. → Prop_MclrZeroKeeps                     *)
(*   mclr_rsv_strict    :329 · :188 예약 `[31:1]` 엄격. 지우면 예약 위반    *)
(*                      해제가 실행된다. → Prop_MclrRsvRejected            *)
(*   mclr_keeps_stall   :329 해제는 정지를 풀지 않는다 — 정지를 푸는 것은   *)
(*                      항목 기입뿐. 지우면 `0xE10` 한 워드가 정지한 요청을 *)
(*                      항목 없이 풀어 준다. → Prop_MclrKeepsStall         *)
(*   ro_rejected        :202 RO 오프셋의 쓰기는 거절이다. 지우면 흡수된다 — *)
(*                      착지 전 RTL 의 `0xE04`–`0xE0C` (파도 2 의 T1).     *)
(*                      → Prop_RoRejected (loud 는 reject_loud 가 잰다)    *)
(*                                                                         *)
(*   아래 둘 — 파도 4 판정 T5 · T4 (f229c8b) 의 착지                        *)
(*   flush_drops_staging 0xC00 · 0xE00 행 — *수락된* flush 가 래치 번호의 파티션인 *)
(*                      스테이징의 유효를 내린다 (프레임·번호는 남는다).   *)
(*                      지우면 flush(임대 회전 ⑵)를 건넌 옛 LO 가 같은 번호 *)
(*                      HI 한 워드로 새 임대의 태그·V 와 함께 커밋된다 —   *)
(*                      판정 전 RTL. → Prop_FlushEndsStaging               *)
(*   ent_part_exists    「없는 파티션 값의 처분」 말미 — 상한 아래 형상에서 *)
(*                      항목 배열의 형상 밖 주소                           *)
(*                      (없는 파티션)의 LO · HI 는 거절이고 스테이징을      *)
(*                      움직이지 않는다. 지우면 주소가 partW 로 잘려 실재  *)
(*                      파티션의 항목이 설치된다(별칭 — 격리 위반).        *)
(*                      → Prop_EntPhantomRejected (격리 귀결은 고정 속성   *)
(*                      Prop_EntNoAlias). 상수 BelowCap = TRUE 인 전용 cfg *)
(*                      에서만 입력이 실재한다 — 기본 형상(상한)에서는     *)
(*                      주소가 전부 실재 파티션이다.                       *)
(*                                                                         *)
(* ## 이 모델이 다루지 않는 것 (「안 잰다」)                               *)
(*                                                                         *)
(* · 조회·채움·값의 정확성 — 적중 판정, 유효 게이팅, 파티션 격리, 채움     *)
(*   바이패스는 XlateStore.tla · Isolation.tla 의 정의역이다. 이 모델의 표는 *)
(*   「항목마다 V 와 프레임 토큰」 하나이고, 채움 슬롯(fill slot)과 저장   *)
(*   블록의 이관은 가시성 면에서 하나로 접는다 — HI 커밋 에지에 항목이     *)
(*   서고, 슬롯 점유는 하류 거부(busy)로만 보인다.                         *)
(* · HI 의 태그·권한 필드 — 불투명. 원자성은 V 와 프레임(LO)의 짝으로 잰다. *)
(* · 주소 디코드 — 어느 비트가 파티션·색인·워드인가(`addr[8:7]` · `addr[6:3]` *)
(*   · `addr[2]`)는 후-formal 의 몫이다. 여기서 기입은 항목을 직접 지목한다. *)
(* · 읽기 방향 — WO 워드(LO · HI · XLATE_FLUSH · XLATE_MISS_CLEAR)의 읽기 0 *)
(*   과 RO 세 워드의 읽기 *값*은 워드 인코딩·관측면의 몫이다. RO 세 워드의 *)
(*   값은 오늘 미배선(읽기 0)이다 — 정본 E.1.3 의 「미적중 관측」 행이       *)
(*   *부분*인 이유이고, 파도 2 의 T1 중 남은 것(`0x380`–`0x390` · `0xFFC` 의 *)
(*   쓰기 흡수와 `0xE04`–`0xE0C` 의 읽기 값)이다. 이 모델은 그 셋의 *쓰기* *)
(*   처분과 `0xE10` 만 싣는다.                                             *)
(* · 미적중 정지의 원천 — 조회 파이프라인. 이 모델의 Lookup 은 「표에 유효  *)
(*   항목이 없는 항목으로 조회가 와서 정지한다」 하나로 접고(태그 불투명), *)
(*   정지는 그 항목의 V=1 커밋이 푼다(E.3 2항). 적중 판정·채움 바이패스는  *)
(*   XlateStore.tla · Isolation.tla 의 정의역이다.                         *)
(* · sub-word 쓰기 거절 — 03-hiu.typ:867 「sub-word 쓰기는 수락하지 않는다」 의 *)
(*   이행 지점은 버스 어댑터다(정본 3.9 미측정 행).                        *)
(* · FAULT_STATUS `[6]` 의 sticky·해제 — 이 모델의 loud 는 그 스텝의 발화  *)
(*   펄스다. sticky·W1C·발화 우선은 fault 표면(CapWord 와 같은 부류)의 몫. *)
(*   (미적중 sticky 는 다르다 — 그 해제 문이 이 모델의 `0xE10` 이라 set·해제 *)
(*   순서를 여기서 싣는다: 판정 4.)                                        *)
(* · 시간 — 사이클 수. 모델은 스텝이 원자적이고 비시간적이라 하류 거부의   *)
(*   도달성을 *과대* 근사한다 (RTL 에서는 LO 한 사이클이 슬롯 커밋을 기다려 *)
(*   주므로 LO→HI 교대 기입은 거부를 만나지 않고, 같은 항목 HI 연속만      *)
(*   만난다). 과대 근사는 처분 판정을 약하게 만들지 않는다.                *)
(* · 설치·flush 원천은 이 문 *하나*다 — 최상위 IO `io.install`·`io.flush` 가 *)
(*   남으면 authority 가 둘이 되고, 하류 거부가 외부 행위자에 매이며, 같은 *)
(*   파티션 flush 와 설치가 한 사이클에 겹칠 수 있다. 그 갈래는 모델 밖이다 *)
(*   (RTL 파도의 은퇴·중재 의무).                                          *)
(* · 색인 축의 형상 밖 주소 — `addr[6:3]` 은 이 구현에서 색인 16 고정이라  *)
(*   (XlateStore 의 8 B 폭 require) 실재하지 않는 색인을 표현하지 않는다.  *)
(*   파티션 축의 형상 밖 주소는 이제 잰다 — 가드 ent_part_exists (판정 T4). *)
(*                                                                         *)
(* ## 판정 — 이 모델이 정본 판정 요청으로 올렸던 넷 (전부 닫혔다)       *)
(*                                                                         *)
(*   1. 스테이징의 수명 (판정 T5 (a), f229c8b) — 커밋은 소진하지 않고       *)
(*      *수락된* flush 가 래치 파티션의 스테이징 유효를 내린다:            *)
(*        e-defined.typ:306 「커밋은 스테이징을 소진하지 않는다」          *)
(*        e-defined.typ:321 「다른 파티션을 래치한 스테이징은 건드리지 않는다」 *)
(*      가드 flush_drops_staging. 판정 전에는 Witness_NoStaleRecommit 가   *)
(*      반증되는(= 옛 LO 재커밋이 도달하는) 증인이었다 — 이제 좋은 모델의 *)
(*      고정 속성 Inv_NoStaleRecommit 이고, 가드 삭제 판이 그 반례를 낸다. *)
(*      기각한 두 갈래를 대안 상수 StgAlt 로 싣는다 — "consume"(커밋 소진)은 *)
(*      Prop_FlushEndsStaging 반례, "global"(전역 비움)은                 *)
(*      Prop_FlushStagingScoped 반례. consume 의 반례가 정본 해설의 세 스텝 *)
(*      그대로다 — e-defined.typ:1884 「바로 위 세 스텝이 곧 반례다」      *)
(*      (LO{p,i} → flush(p) → HI{p,i}: 커밋된 적 없는 옛 LO 는 소진이 못   *)
(*      막는다).                                                           *)
(*   2. reset 직후의 래치 번호 — 스테이징의 유효가 정본 문면이 됐다:        *)
(*        e-defined.typ:306 「reset 은 빈 스테이징이고」                   *)
(*      hi_needs_staging 은 그 문장과 빈 스테이징 HI 의 거절을 싣는다.      *)
(*   3. 상한 아래 형상 (판정 T4 (ii)) — 항목 배열의 형상 밖 주소는 거절:   *)
(*        e-defined.typ:424 「상한 아래 형상에서는 그 주소가 없는 파티션을 가리키고」 *)
(*      가드 ent_part_exists · 상수 BelowCap.                              *)
(*   4. 정지 중의 `0xE10` 해제 — 유실이 정본 문면이 됐다:                 *)
(*        e-defined.typ:329 「정지 *중에* 쓴 해제는 유실된다」             *)
(*      Prop_ClearAlwaysLowers 는 여전히 반증된다(run.sh MUST FAIL) —      *)
(*      이제 그 반례가 정본의 귀결이다. 드라이버의 순서는 항목 기입 → 해제. *)
(*                                                                         *)
(* ## 분리 검사 (비상주 실측 — 머리의 기록이 전부다)                       *)
(*                                                                         *)
(*   새 가드 둘을 각각 지운 판에 *나머지* 속성 전부(가드 속성 · 고정 속성)를 *)
(*   건 run 은 그 가드의 자기 속성과 그 귀결(flush_drops_staging →         *)
(*   Inv_NoStaleRecommit · ent_part_exists → Prop_EntNoAlias)만 빼면 통과한다 *)
(*   — 새 가드가 기존 계약을 깨지 않고, 기존 가드가 새 속성을 대신 지지  *)
(*   않는다. 실측값은 run.sh 의 이 모델 절 머리에 적는다.                  *)
(*                                                                         *)
(* ## 규모 — 새 입력이 large 를 부풀리지 않게 (배터리 소요)               *)
(*                                                                         *)
(*   XlateSurface_large.cfg 는 배터리 안이고 HEAD f229c8b 판이 단일 워커   *)
(*   약 36분이다(62,060,261 generated · 2,400,988 distinct). 그래서 새 증인 *)
(*   셋은 ev 사건을 늘리지 않고 스텝 뒤 상태(acc · why · stale · stg)의    *)
(*   술어로 적었고(아래 증인 절), T4 의 형상 밖 파티션 주소는 상수 BelowCap *)
(*   = FALSE 로 끄고 전용 cfg 에서만 켠다. 대안 StgAlt 는 large 에서 "flush" *)
(*   하나다. 개정판 large 의 실측 소요는 run.sh 이 모델 절 머리에 적는다.  *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS
    Parts,           \* 실재하는 파티션. 불투명 토큰 (≥ 2 — flush_scoped 가 잴 타 파티션)
    Indices,         \* 파티션당 색인. 불투명 토큰
    Frames,          \* LO 가 나르는 물리 프레임 값. 불투명 토큰 (≥ 2 — 찢김이 보이려면)
    Junk,            \* reset 뒤 한 번도 쓰이지 않은 내용 (모델 값) — 호스트가 쓴 적 없는 프레임
    Phantom,         \* XLATE_FLUSH `[7:0]` 이 표현하지만 실재하지 않는 파티션 값 (모델 값)
    Refusal,         \* 하류 거부(install.ready = 0)의 처분 — "stall" | "reject" | "drop"
    StgAlt,          \* 스테이징 수명의 갈래 — "flush"(판정 T5 (a)) | "consume"(커밋 소진) |
                     \* "global"(flush 가 파티션과 무관하게 스테이징을 비움). 뒤 둘은 기각한 대안
    BelowCap,        \* 형상 < 인코딩 상한 — TRUE 면 항목 배열 창이 없는 파티션(Phantom)의 항목
                     \* 주소를 표현한다 (판정 T4). 전용 cfg 에서만 TRUE — large 를 부풀리지 않는다
    DisabledGuards

ASSUME Refusal \in {"stall", "reject", "drop"}
ASSUME StgAlt \in {"flush", "consume", "global"}
ASSUME BelowCap \in BOOLEAN
ASSUME Cardinality(Parts) >= 2 /\ Cardinality(Frames) >= 2
ASSUME Junk \notin Frames /\ Phantom \notin Parts

AllGuards == {"lo_stages_only", "hi_fires", "hi_entry_match", "hi_needs_staging",
              "hi_commit_whole", "hi_v_carried",
              "flush_fires", "flush_scoped", "flush_valid_only",
              "flush_part_exists", "flush_rsv_strict", "reject_loud",
              "mclr_fires", "mclr_needs_one", "mclr_rsv_strict", "mclr_keeps_stall",
              "ro_rejected", "flush_drops_staging", "ent_part_exists"}
On(g) == g \notin DisabledGuards

Entries == Parts \X Indices
PartOf(e) == e[1]
\* 항목 배열 창(`0xC00` 구역)이 표현하는 항목 번호 전수. 파티션은 주소 비트 `addr[8:7]`
\* 로 오므로 형상이 상한이면 창의 번호가 전부 실재하고(Entries), 상한 아래이면 없는
\* 파티션의 번호가 창에 남는다 (판정 T4 — Phantom 을 그 파티션 값으로 재사용한다).
\* IF 를 창 파티션 집합(WinParts)으로 좁혀 둔다 — 「IF BelowCap THEN 곱집합 ELSE Entries」
\* 꼴로 적으면 TLC 1 워커 실측(작은 cfg · 한 CPU 고정)에서 상태당 비용이 약 1.3배였다
\* (31.5 s → 23.0 s, 도달 상태 같음). 뜻은 같다.
WinParts == IF BelowCap THEN {Phantom} ELSE {}
WinEnts == (Parts \cup WinParts) \X Indices
EntReal(e) == PartOf(e) \in Parts
FrVals == Frames \cup {Junk}
E0 == CHOOSE e \in Entries : TRUE     \* 스테이징 번호 레지스터의 reset 값
P0 == CHOOSE p \in Parts : TRUE
\* flush_part_exists 를 지웠을 때 없는 값이 잘려 닿는 실재 파티션 — 8b 필드를
\* partW 비트로 자르는 배선이면 없는 값은 어떤 실재 값과 겹친다.
Alias == P0
\* ent_part_exists 를 지웠을 때 형상 밖 번호가 닿는 실재 항목 — 번호의 파티션 필드를
\* partW 로 자르는 배선(commit.part := numPart.resized)이면 없는 파티션이 Alias 로 간다.
AliasEnt(e) == IF EntReal(e) THEN e ELSE <<Alias, e[2]>>

(***************************************************************************)
(* 버스 기입 — 필드가 고른 레코드. 쓰지 않는 필드는 채움 값이며 속성은     *)
(* 언제나 kind 를 먼저 본다.                                               *)
(*   lo     XLATE_ENTRY_LO — 항목 e, 프레임 fr                             *)
(*   hi     XLATE_ENTRY_HI — 항목 e, V 비트 v (태그·권한은 불투명)         *)
(*   flush  XLATE_FLUSH    — 파티션 값 part(없는 값 Phantom 포함), 예약 rsv *)
(*   mclr   XLATE_MISS_CLEAR — `[0]` 을 v 에, 예약 `[31:1]` 비0 을 rsv 에     *)
(*   ro     RO 세 워드(`0xE04`–`0xE0C`) 중 하나의 쓰기 — 셋의 처분은 같다   *)
(*          (어느 오프셋인가는 주소 디코드라 후-formal 의 몫이다)          *)
(***************************************************************************)
Wr(k, e, f, b, q, r) == [kind |-> k, ent |-> e, fr |-> f, v |-> b, part |-> q, rsv |-> r]
NoWrite == Wr("none", E0, Junk, FALSE, P0, FALSE)
LoWrites == {Wr("lo", e, f, FALSE, P0, FALSE) : e \in WinEnts, f \in Frames}
HiWrites == {Wr("hi", e, Junk, b, P0, FALSE) : e \in WinEnts, b \in BOOLEAN}
FlushWrites == {Wr("flush", E0, Junk, FALSE, q, r) : q \in Parts \cup {Phantom}, r \in BOOLEAN}
MclrWrites == {Wr("mclr", E0, Junk, b, P0, r) : b \in BOOLEAN, r \in BOOLEAN}
RoWrites == {Wr("ro", E0, Junk, FALSE, P0, FALSE)}
Writes == LoWrites \cup HiWrites \cup FlushWrites \cup MclrWrites \cup RoWrites

\* 처분 — 그 스텝에 버스가 수락한 기입이 무엇이 됐는가.
\*   none    수락 없음 (Drain · LateFr · Lookup)  hold   버스 정지 — 수락하지 않고 잡아 둠
\*   stage   LO 스테이징                        commit HI 커밋
\*   flush   flush 실행                         absorb 수락됐는데 아무 일도 없음 (조용한 흡수)
\*   clear   미적중 sticky 해제 발화             noop   `0xE10` `[0]`=0 — W1C 의 0 쓰기
\*   (noop 은 흡수가 아니다: 정본 :329 가 해제로 정한 것은 `[0]` 에 1 을 쓰는
\*    기입이고, `[0]` 의 0 은 예약 비트가 아니라 「해제하지 않는다」는 적법한 값이다.)
\*   거절 여덟 — unstaged · mismatch · phantom · rsv · refused(하류 거부를 거절로
\*   처분) · mrsv(`0xE10` 예약 비0) · ro(RO 오프셋 쓰기) · ephantom(항목 배열의 형상
\*   밖 주소 — 판정 T4)
Reasons == {"none", "hold", "stage", "commit", "flush", "absorb", "clear", "noop",
            "unstaged", "mismatch", "phantom", "rsv", "refused", "mrsv", "ro", "ephantom"}
RejectReasons == {"unstaged", "mismatch", "phantom", "rsv", "refused", "mrsv", "ro", "ephantom"}

\* 증인용 스텝 사건 — 전건 도달성의 표식. 매 스텝 새로 계산된다 (sticky 아님).
Events == {"loLive", "newFr", "kill", "stale", "flushLive", "flushOther",
           "clrLive", "zeroLive", "clrStall"}

NoLate == [on |-> FALSE, ent |-> E0, fr |-> Junk]
NoStall == [on |-> FALSE, ent |-> E0]

VARIABLES
    tbl,     \* [Entries -> [v, fr]] — 항목의 유효 비트와 프레임 (가시성: 채움 슬롯 + 저장 블록)
    stg,     \* [sv, ent, fr] — LO 스테이징 레지스터: 유효 · 래치된 항목 번호 · 프레임
             \* (ent 는 기입된 번호 그대로 — ent_part_exists 를 지우면 형상 밖 번호도 래치된다)
    busy,    \* [Parts -> BOOLEAN] — 그 파티션 채움 슬롯 점유 = XlateStore install.ready 하강
    held,    \* 버스가 잡아 둔 기입 (mmio ready = 0). NoWrite = 버스 한가
    late,    \* hi_commit_whole 을 지웠을 때만 쓰인다 — 다음 에지에 앉을 프레임
    stale,   \* 고스트 — 스테이징된 LO 가 그 파티션의 마지막 flush 보다 먼저인가 (판정 1 ·
             \* T5). 가드 무관: flush 가 *실행된* 파티션으로 선다(스테이징 유효 하강과 별개)
    mstall,  \* 미적중 정지 — [on, ent]: 조회 요청이 유효 항목 없는 항목에서 정지했는가
    msticky, \* 미적중 sticky (XLATE_STATUS [1]) — set 은 정지 레벨, 해제는 `0xE10`
    acc,     \* 보조 — 이 스텝에 버스가 수락한 기입. NoWrite = 수락 없음
    why,     \* 보조 — 그 기입의 처분 (Reasons)
    loud,    \* 보조 — 이 스텝이 FAULT_STATUS [6] 을 발화했는가 (펄스)
    ev       \* 보조 — 이 스텝의 증인 사건 (Events 의 부분집합)

vars == <<tbl, stg, busy, held, late, stale, mstall, msticky, acc, why, loud, ev>>

TypeOK ==
    /\ tbl \in [Entries -> [v : BOOLEAN, fr : FrVals]]
    /\ stg \in [sv : BOOLEAN, ent : WinEnts, fr : FrVals]
    /\ busy \in [Parts -> BOOLEAN]
    /\ held \in Writes \cup {NoWrite}
    /\ late \in [on : BOOLEAN, ent : Entries, fr : FrVals]
    /\ stale \in BOOLEAN
    /\ mstall \in [on : BOOLEAN, ent : Entries]
    /\ msticky \in BOOLEAN
    /\ acc \in Writes \cup {NoWrite}
    /\ why \in Reasons
    /\ loud \in BOOLEAN
    /\ ev \in SUBSET Events

Init ==
    /\ tbl = [e \in Entries |-> [v |-> FALSE, fr |-> Junk]]
    /\ stg = [sv |-> FALSE, ent |-> E0, fr |-> Junk]
    /\ busy = [p \in Parts |-> FALSE]
    /\ held = NoWrite
    /\ late = NoLate
    /\ stale = FALSE
    /\ mstall = NoStall
    /\ msticky = FALSE
    /\ acc = NoWrite
    /\ why = "none"
    /\ loud = FALSE
    /\ ev = {}

(***************************************************************************)
(* 정본의 적법성 — 가드와 무관하다. 속성이 이것을 쓴다 (장치가 무엇을      *)
(* 적법하다고 *보는가*는 아래 Dev 계열이고 가드에 따라 달라진다).          *)
(***************************************************************************)
\* 정본이 보는 스테이징 유효 — 장치의 유효 비트에서 flush 를 건넌 것(stale)을 뺀다.
\* 가드 flush_drops_staging 이 살아 있으면 stale ⇒ ~stg.sv 라 stg.sv 와 같고, 지운
\* 판에서도 정본의 판정(flush 뒤 스테이징은 빈다)을 그대로 든다 — 장치가 스스로
\* 적법하다고 보는 것을 속성이 믿지 않게 한다.
SpecStaged == stg.sv /\ ~stale
SpecHiOK(w) == SpecStaged /\ stg.ent = w.ent /\ EntReal(w.ent)
SpecFlOK(w) == w.part \in Parts /\ ~w.rsv
SpecMcOK(w) == ~w.rsv
SpecMalformed(w) ==
    \/ (~EntReal(w.ent) /\ w.kind \in {"lo", "hi"})
    \/ (w.kind = "hi" /\ ~SpecHiOK(w))
    \/ (w.kind = "flush" /\ ~SpecFlOK(w))
    \/ (w.kind = "mclr" /\ ~SpecMcOK(w))
    \/ w.kind = "ro"

(***************************************************************************)
(* 장치의 판정 — 가드 의존. HI 는 스테이징 유무를 먼저 본다.               *)
(***************************************************************************)
\* 항목 배열의 형상 밖 주소 (판정 T4) — LO · HI 둘 다. 가장 먼저 본다. 첫 연언 BelowCap 은
\* 뜻을 바꾸지 않는다(상한 형상에서는 번호가 전부 실재한다) — 모든 기입의 처분이 이 항을
\* 먼저 보므로 상한 형상에서 곧장 거짓으로 끊게 둔 것이다 (1 워커 실측: 이 항이 상태당 비용의
\* 약 2할이었다 — 작은 cfg · 한 CPU 고정 23.2 s → 18.2 s).
DevEntPhantom(w) == BelowCap /\ w.kind \in {"lo", "hi"} /\ ~EntReal(w.ent) /\ On("ent_part_exists")
DevUnstaged(w) == ~stg.sv /\ On("hi_needs_staging")
DevMismatch(w) == stg.ent # w.ent /\ On("hi_entry_match")
DevHiBad(w) == DevUnstaged(w) \/ DevMismatch(w)
DevPhantom(w) == w.part \notin Parts /\ On("flush_part_exists")
DevRsvBad(w) == w.rsv /\ On("flush_rsv_strict")
DevMcRsvBad(w) == w.rsv /\ On("mclr_rsv_strict")
\* 장치가 해제로 보는 기입 — `[0]`=1 (mclr_needs_one 을 지우면 값과 무관).
DevMcFires(w) == w.v \/ ~On("mclr_needs_one")

\* 하류 거부 — 장치가 적법하다고 본 HI 가 채움 슬롯이 찬 파티션으로 간다.
Refused(w) == w.kind = "hi" /\ ~DevEntPhantom(w) /\ ~DevHiBad(w) /\ busy[PartOf(AliasEnt(w.ent))]

(***************************************************************************)
(* 수락된 기입 하나의 처분 — 모든 수락 경로(Present · Retry)가 이 하나로   *)
(* 환원된다 (CapWord.tla Step 선례: 사본 둘은 드리프트한다).               *)
(*                                                                         *)
(* 처분 d 를 먼저 정하고, 표·스테이징·하류의 갱신은 d 의 함수다 —          *)
(* 「commit」 표식과 실제 커밋 기입이 갈라질 자리가 없다.                  *)
(*                                                                         *)
(* 거절된 기입은 한 비트도 움직이지 않는다 — 표도 스테이징도 하류도        *)
(* (Wt64Top maskArea 의 「거절된 기입은 레지스터를 움직이지 않는다」 규율). *)
(***************************************************************************)
Dispose(w) ==
    LET e    == AliasEnt(w.ent)   \* 장치가 닿는 항목 (가드가 살아 있으면 형상 밖 번호는 여기 오지 않는다)
        p    == PartOf(e)
        rej  == CASE DevEntPhantom(w)                   -> "ephantom"
                  [] w.kind = "hi"    /\ DevUnstaged(w) -> "unstaged"
                  [] w.kind = "hi"    /\ DevMismatch(w) -> "mismatch"
                  [] w.kind = "flush" /\ DevPhantom(w)  -> "phantom"
                  [] w.kind = "flush" /\ DevRsvBad(w)   -> "rsv"
                  [] w.kind = "mclr"  /\ DevMcRsvBad(w) -> "mrsv"
                  [] w.kind = "ro"    /\ On("ro_rejected") -> "ro"
                  [] OTHER                               -> "none"
        d    == IF rej # "none" THEN rej
                ELSE CASE w.kind = "lo" -> "stage"
                       [] w.kind = "hi" /\ busy[p] ->
                            \* stall 은 Present 가 잡아 두므로 여기 오지 않는다
                            (IF Refusal = "reject" THEN "refused" ELSE "absorb")
                       [] w.kind = "hi"    -> (IF On("hi_fires")    THEN "commit" ELSE "absorb")
                       [] w.kind = "flush" -> (IF On("flush_fires") THEN "flush"  ELSE "absorb")
                       [] w.kind = "mclr"  ->
                            (IF DevMcFires(w)
                               THEN (IF On("mclr_fires") THEN "clear" ELSE "absorb")
                               ELSE "noop")
                       \* ro 가 여기 오는 것은 ro_rejected 를 지운 모델뿐이다
                       [] OTHER            -> "absorb"
        newV == IF On("hi_v_carried") THEN w.v ELSE TRUE
        \* 미적중 정지를 푸는 것은 그 항목의 유효 커밋이다 (E.3 2항 — 태그는 불투명이라
        \* 「그 항목에 V=1 이 커밋되면 정지한 요청이 적중한다」로 접는다).
        rel  == d = "commit" /\ newV /\ mstall.on /\ mstall.ent = e
        tgt  == IF w.part \in Parts THEN w.part ELSE Alias
        F    == IF On("flush_scoped") THEN {tgt} ELSE Parts
        flushEntry(x) == [v |-> FALSE,
                          fr |-> IF On("flush_valid_only") THEN tbl[x].fr ELSE Junk]
        \* 수락된 flush 가 스테이징의 유효를 내리는가 (판정 T5). 번호·프레임은 남는다.
        \*   flush   래치 번호의 파티션이 그 flush 의 범위 F 안일 때 (좋은 모델)
        \*   global  파티션과 무관하게 (기각 — E.9 6항 「하나」 · :321 「다른 파티션을
        \*           래치한 스테이징은 건드리지 않는다」 위반)
        \*   consume flush 는 스테이징에 닿지 않고 커밋이 소진한다 (기각 — 아래 stg')
        dropStg == /\ d = "flush" /\ stg.sv /\ On("flush_drops_staging")
                   /\ CASE StgAlt = "flush"   -> PartOf(stg.ent) \in F
                        [] StgAlt = "global"  -> TRUE
                        [] StgAlt = "consume" -> FALSE
    IN  /\ tbl' = CASE d = "stage"  ->
                         (IF On("lo_stages_only") THEN tbl
                          ELSE [tbl EXCEPT ![e].fr = w.fr])
                    [] d = "commit" ->
                         (IF On("hi_commit_whole")
                            THEN [tbl EXCEPT ![e] = [v |-> newV, fr |-> stg.fr]]
                            ELSE [tbl EXCEPT ![e].v = newV])
                    [] d = "flush"  ->
                         [x \in Entries |-> IF PartOf(x) \in F THEN flushEntry(x) ELSE tbl[x]]
                    [] OTHER        -> tbl
        /\ late' = IF d = "commit" /\ ~On("hi_commit_whole")
                     THEN [on |-> TRUE, ent |-> e, fr |-> stg.fr]
                     ELSE late
        /\ stg' = CASE d = "stage" -> [sv |-> TRUE, ent |-> w.ent, fr |-> w.fr]
                    [] dropStg     -> [stg EXCEPT !.sv = FALSE]
                    [] d = "commit" /\ StgAlt = "consume" -> [stg EXCEPT !.sv = FALSE]
                    [] OTHER       -> stg
        /\ busy' = CASE d = "commit" -> [busy EXCEPT ![p] = TRUE]
                     \* flush 는 그 파티션의 진행 중 채움도 취한다 (XlateStore flush 가지)
                     [] d = "flush"  -> [q \in Parts |-> IF q \in F THEN FALSE ELSE busy[q]]
                     [] OTHER        -> busy
        /\ stale' = CASE d = "stage" -> FALSE
                      [] d = "flush" -> stale \/ (stg.sv /\ PartOf(stg.ent) \in F)
                      [] OTHER       -> stale
        \* 해제는 정지에 닿지 않는다 — mclr_keeps_stall 을 지운 모델에서만 푼다.
        /\ mstall' = IF rel \/ (d = "clear" /\ ~On("mclr_keeps_stall"))
                       THEN NoStall ELSE mstall
        \* set 은 정지 *레벨*이고 발화가 해제를 이긴다 (StickyFault 규약 — 판정 4).
        \* 정지가 살아 있던 스텝의 해제는 유실된다.
        /\ msticky' = (mstall.on \/ (msticky /\ d # "clear"))
        /\ acc' = w
        /\ why' = d
        /\ loud' = (d \in RejectReasons /\ On("reject_loud"))
        /\ ev' = (IF d = "stage" /\ tbl[e].v /\ tbl[e].fr # w.fr THEN {"loLive"} ELSE {})
               \cup (IF d = "commit" /\ tbl[e].fr # stg.fr THEN {"newFr"} ELSE {})
               \cup (IF d = "commit" /\ tbl[e].v /\ ~w.v THEN {"kill"} ELSE {})
               \cup (IF d = "commit" /\ stale THEN {"stale"} ELSE {})
               \cup (IF d = "flush" /\ w.part \in Parts
                        /\ \E x \in Entries : PartOf(x) = w.part /\ tbl[x].v
                       THEN {"flushLive"} ELSE {})
               \cup (IF d = "flush" /\ w.part \in Parts
                        /\ \E x \in Entries : PartOf(x) # w.part /\ tbl[x].v
                       THEN {"flushOther"} ELSE {})
               \* 아래 셋은 입력(정본 적법성)으로 적는다 — 장치 처분과 무관하게 전건이
               \* 실재함을 보이는 표식이다.
               \cup (IF w.kind = "mclr" /\ w.v /\ ~w.rsv /\ msticky /\ ~mstall.on
                       THEN {"clrLive"} ELSE {})
               \cup (IF w.kind = "mclr" /\ ~w.v /\ ~w.rsv /\ msticky /\ ~mstall.on
                       THEN {"zeroLive"} ELSE {})
               \cup (IF w.kind = "mclr" /\ w.v /\ ~w.rsv /\ mstall.on
                       THEN {"clrStall"} ELSE {})

(***************************************************************************)
(* 호스트가 버스에 기입 하나를 제시한다. 버스는 한 번에 하나다 — 잡혀 있는 *)
(* 기입이 있으면 다음 기입은 제시되지 않는다(held = NoWrite 전제).         *)
(* Refusal = "stall" 이고 하류가 거부하면 수락하지 않고 잡아 둔다.         *)
(***************************************************************************)
Present(w) ==
    /\ held = NoWrite
    /\ ~late.on
    /\ IF Refusal = "stall" /\ Refused(w)
         THEN /\ held' = w
              /\ acc' = NoWrite
              /\ why' = "hold"
              /\ loud' = FALSE
              /\ ev' = {}
              /\ UNCHANGED <<tbl, stg, busy, late, stale, mstall, msticky>>
         ELSE /\ UNCHANGED held
              /\ Dispose(w)

\* 잡혀 있던 기입이 하류가 비는 순간 수락된다 — 같은 기입, 단일 에지.
Retry ==
    /\ held # NoWrite
    /\ ~late.on
    /\ ~busy[PartOf(AliasEnt(held.ent))]
    /\ held' = NoWrite
    /\ Dispose(held)

\* 채움 슬롯의 저장 커밋 — 호스트 조치 없이, 버스와 독립으로 일어난다
\* (XlateStore commitFire 는 점유가 있으면 매 사이클 발화한다).
Drain(p) ==
    /\ busy[p]
    /\ ~late.on
    /\ busy' = [busy EXCEPT ![p] = FALSE]
    /\ acc' = NoWrite
    /\ why' = "none"
    /\ loud' = FALSE
    /\ ev' = {}
    /\ UNCHANGED <<tbl, stg, held, late, stale, mstall, msticky>>

\* hi_commit_whole 을 지운 모델에서만 열린다 — 커밋의 둘째 에지. 그 사이에
\* 다른 동작은 끼지 않는다 (찢긴 상태는 정확히 한 스텝 관측된다).
LateFr ==
    /\ late.on
    /\ tbl' = [tbl EXCEPT ![late.ent].fr = late.fr]
    /\ late' = NoLate
    /\ acc' = NoWrite
    /\ why' = "none"
    /\ loud' = FALSE
    /\ ev' = {}
    /\ UNCHANGED <<stg, busy, held, stale, mstall, msticky>>

\* 조회 요청 하나가 유효 항목 없는 항목에 닿아 정지한다 — 버스와 독립인 다른
\* 포트다. 정지 중에는 파이프 전체가 서므로 새 조회는 오지 않는다. 미적중
\* sticky 는 정지 레벨로 선다 (RTL: StickyFault(set = missWait, …)).
\* 적중 조회는 이 모델의 어떤 상태도 움직이지 않으므로 적지 않는다.
Lookup(e) ==
    /\ ~mstall.on
    /\ ~late.on
    /\ ~tbl[e].v
    /\ mstall' = [on |-> TRUE, ent |-> e]
    /\ msticky' = TRUE
    /\ acc' = NoWrite
    /\ why' = "none"
    /\ loud' = FALSE
    /\ ev' = {}
    /\ UNCHANGED <<tbl, stg, busy, held, late, stale>>

Next ==
    \/ \E w \in Writes : Present(w)
    \/ Retry
    \/ \E p \in Parts : Drain(p)
    \/ LateFr
    \/ \E e \in Entries : Lookup(e)

Spec == Init /\ [][Next]_vars

\* 정지가 호스트 조치 없이 풀린다는 의무 — 채움 슬롯의 저장 커밋은 결국
\* 일어나고(Drain), 하류가 빈 동안 잡힌 기입은 결국 수락된다(Retry).
LiveSpec ==
    /\ Spec
    /\ WF_vars(Retry)
    /\ \A p \in Parts : WF_vars(Drain(p))

\* 대조군 — Drain 의 공정성을 뺀다. Prop_StallEnds 가 반증돼야 한다: 풀림이
\* 정확히 「슬롯은 버스와 독립으로 비워진다」에 걸려 있다는 증명이다.
LiveSpecNoDrain ==
    /\ Spec
    /\ WF_vars(Retry)

(***************************************************************************)
(* 가드 속성 — 전부 행위 속성([][...]_vars). 「이 기입이 무엇을 움직였는가」 *)
(* 는 한 스텝의 전후를 함께 봐야 말할 수 있다. acc' 가 그 스텝의 원인,     *)
(* why' · loud' 가 처분이다. 전건의 적법성은 정본 판정(Spec 계열)이지 장치 *)
(* 판정(Dev 계열)이 아니다 — 장치가 스스로 적법하다고 보는 것을 속성이 믿으면 *)
(* 가드 삭제가 속성까지 함께 지운다.                                       *)
(***************************************************************************)

\* lo_stages_only — LO 는 표에 닿지 않는다.
Prop_LoStagesOnly ==
    [][ acc'.kind = "lo" => tbl' = tbl ]_vars

\* hi_fires — 적법한 HI 는 커밋된다 (수락된 이상 흡수·거절이 없다).
Prop_HiCommits ==
    [][ (acc'.kind = "hi" /\ SpecHiOK(acc')) => why' = "commit" ]_vars

\* hi_entry_match — 스테이징된 번호와 다른 항목의 HI 는 거절되고 표는 불변.
Prop_MismatchRejected ==
    [][ (acc'.kind = "hi" /\ stg.sv /\ stg.ent # acc'.ent)
          => (why' \in RejectReasons /\ tbl' = tbl) ]_vars

\* hi_needs_staging — 스테이징이 빈 HI(HI 만 쓴 부분 기입)는 거절되고 표는 불변.
Prop_UnstagedRejected ==
    [][ (acc'.kind = "hi" /\ ~stg.sv)
          => (why' \in RejectReasons /\ tbl' = tbl) ]_vars

\* hi_commit_whole — 커밋 스텝이 스테이징 프레임까지 그 항목에 앉히고,
\* 다른 항목은 건드리지 않는다. (형상 밖 번호의 커밋은 이 속성이 아니라
\* Prop_EntPhantomRejected · Prop_EntNoAlias 의 몫이다 — 그 번호는 표에 없다.)
Prop_HiCommitWhole ==
    [][ (acc'.kind = "hi" /\ why' = "commit" /\ EntReal(acc'.ent))
          => (/\ tbl'[acc'.ent].fr = stg.fr
              /\ \A x \in Entries \ {acc'.ent} : tbl'[x] = tbl[x]) ]_vars

\* hi_v_carried — 커밋된 항목의 유효는 HI `[31]` 그 값이다.
Prop_ValidFromV ==
    [][ (acc'.kind = "hi" /\ why' = "commit" /\ EntReal(acc'.ent)) => tbl'[acc'.ent].v = acc'.v ]_vars

\* flush_fires — 적법한 flush 뒤 그 파티션의 항목은 전부 무효다.
Prop_FlushClears ==
    [][ (acc'.kind = "flush" /\ SpecFlOK(acc'))
          => \A x \in Entries : PartOf(x) = acc'.part => ~tbl'[x].v ]_vars

\* flush_scoped — 실재 파티션 p 의 flush 는 다른 파티션을 건드리지 않는다.
Prop_FlushScoped ==
    [][ (acc'.kind = "flush" /\ acc'.part \in Parts)
          => \A x \in Entries : PartOf(x) # acc'.part => tbl'[x] = tbl[x] ]_vars

\* flush_valid_only — flush 는 프레임(데이터)을 지우지 않는다.
Prop_FlushKeepsData ==
    [][ acc'.kind = "flush" => \A x \in Entries : tbl'[x].fr = tbl[x].fr ]_vars

\* flush_part_exists — 없는 파티션 값의 flush 는 거절되고 표는 불변.
Prop_PhantomRejected ==
    [][ (acc'.kind = "flush" /\ acc'.part \notin Parts)
          => (why' \in RejectReasons /\ tbl' = tbl) ]_vars

\* flush_rsv_strict — 예약 `[31:8]` 비0 flush 는 거절되고 표는 불변.
Prop_RsvRejected ==
    [][ (acc'.kind = "flush" /\ acc'.rsv)
          => (why' \in RejectReasons /\ tbl' = tbl) ]_vars

\* reject_loud — 거절은 전부 FAULT_STATUS [6] 을 발화한다.
Prop_RejectLoud ==
    [][ why' \in RejectReasons => loud' ]_vars

\* mclr_fires — 적법한 `[0]`=1 해제는 (정지가 없으면) 미적중 sticky 를 내린다.
\* 정지 중의 해제는 이 속성의 전건 밖이다 — 판정 4 (Prop_ClearAlwaysLowers).
Prop_MclrClears ==
    [][ (acc'.kind = "mclr" /\ acc'.v /\ SpecMcOK(acc') /\ ~mstall.on) => ~msticky' ]_vars

\* mclr_needs_one — `[0]`=0 기입은 sticky 를 움직이지 않는다.
Prop_MclrZeroKeeps ==
    [][ (acc'.kind = "mclr" /\ ~acc'.v) => msticky' = msticky ]_vars

\* mclr_rsv_strict — 예약 `[31:1]` 비0 해제는 거절되고 sticky 는 불변.
Prop_MclrRsvRejected ==
    [][ (acc'.kind = "mclr" /\ acc'.rsv)
          => (why' \in RejectReasons /\ msticky' = msticky) ]_vars

\* mclr_keeps_stall — 해제는 미적중 정지에 닿지 않는다. (버스 정지 held 는 구조로
\* 닿지 않는다 — 버스는 한 번에 한 기입이라 해제가 제시될 때 held = NoWrite 다.)
Prop_MclrKeepsStall ==
    [][ acc'.kind = "mclr" => mstall' = mstall ]_vars

\* ro_rejected — RO 오프셋 쓰기는 거절되고 아무것도 움직이지 않는다.
Prop_RoRejected ==
    [][ acc'.kind = "ro"
          => (/\ why' \in RejectReasons
              /\ tbl' = tbl /\ stg' = stg /\ mstall' = mstall /\ msticky' = msticky) ]_vars

\* flush_drops_staging — flush(임대 회전 ⑵)를 건넌 스테이징 위의 HI 는 번호와 무관하게
\* 거절되고 표는 불변이다 (판정 T5 — E.1.2 `0xC00` · `0xE00` 행 · E.9 6항 ⑵). 전건 stale 은
\* 가드 무관 고스트다: 가드를 지운 장치는 스테이징을 유효로 들고 있고, 그때 같은
\* 번호의 HI 한 워드가 옛 임대의 프레임을 새 임대의 태그·V 로 커밋한다.
Prop_FlushEndsStaging ==
    [][ (acc'.kind = "hi" /\ stale) => (why' \in RejectReasons /\ tbl' = tbl) ]_vars

\* ent_part_exists — 항목 배열의 형상 밖 주소(없는 파티션)의 LO · HI 는 거절되고 표도
\* 스테이징도 움직이지 않는다 (판정 T4 — 「없는 파티션 값의 처분」 말미).
Prop_EntPhantomRejected ==
    [][ (~EntReal(acc'.ent) /\ acc'.kind \in {"lo", "hi"})
          => (why' \in RejectReasons /\ tbl' = tbl /\ stg' = stg) ]_vars

(***************************************************************************)
(* 가드 아님 — 고정 의미의 속성. 좋은 모델 cfg 와 처분 대안 짝이 쓴다.     *)
(***************************************************************************)

\* 거절은 정본이 열거한 사유로만 — 적법한 기입이 fault 를 받는 일은 없다.
\* Refusal = "reject" 가 이것을 깬다 (머리 「설계 결정」).
Prop_RejectOnlyMalformed ==
    [][ why' \in RejectReasons => SpecMalformed(acc') ]_vars

\* [6] 은 거절에서만 발화한다 — 허위 fault 없음.
Prop_LoudOnlyOnReject ==
    [][ loud' => why' \in RejectReasons ]_vars

\* 표를 움직이는 것은 커밋과 flush 둘뿐이다 — 문 밖의 경로가 없다.
Prop_TableByDoor ==
    [][ tbl' # tbl => why' \in {"commit", "flush"} ]_vars

\* :308 「부분 기입 상태가 유효해질 수 없다」의 상태형 — 유효한 항목의
\* 프레임은 호스트가 쓴 값이다.
Inv_ValidFrameWritten ==
    \A x \in Entries : tbl[x].v => tbl[x].fr # Junk

\* 판정 T5 의 격리 귀결 — flush 를 건넌 옛 LO 는 V 와 무관하게 다시 커밋되지 않는다.
\* 판정 전에는 이것의 부정이 증인(Witness_NoStaleRecommit, MUST FAIL)이었다 — 옛 LO
\* 재커밋이 도달했다. 가드 flush_drops_staging 을 지운 판이 그 반례를 그대로 낸다.
Inv_NoStaleRecommit == "stale" \notin ev

\* 판정 T5 의 범위 — 실재 파티션의 수락된 flush 는 다른 파티션을 래치한 스테이징을
\* 건드리지 않는다 (E.1.2 `0xE00` 행). 대안 StgAlt = "global" 이 이것을 깬다.
Prop_FlushStagingScoped ==
    [][ (acc'.kind = "flush" /\ why' = "flush" /\ acc'.part \in Parts
         /\ PartOf(stg.ent) # acc'.part) => stg' = stg ]_vars

\* 판정 T5 — flush 가 내리는 것은 스테이징의 *유효*뿐이고 번호·프레임은 남는다
\* (E.1.2 `0xC00` 행). 관측면에는 보이지 않는 사실이다 — 빈 스테이징의 HI 는
\* 번호와 무관하게 거절이라 남은 번호·프레임이 쓰일 길이 없다 (후-formal 이 재지
\* 않는 이유). 모델은 정본의 문면을 그대로 싣는다.
Prop_FlushStagingKeepsData ==
    [][ acc'.kind = "flush" => (stg'.ent = stg.ent /\ stg'.fr = stg.fr) ]_vars

\* 판정 T4 의 격리 귀결 — 형상 밖 번호의 HI 가 실재 파티션의 항목을 움직이지 않는다
\* (「없는 파티션 값의 처분」 말미의 별칭 금지). 가드 ent_part_exists 를 지운 판이 반례를 낸다.
Prop_EntNoAlias ==
    [][ (~EntReal(acc'.ent) /\ acc'.kind = "hi") => tbl' = tbl ]_vars

\* 버스 정지는 영구가 아니다 (LiveSpec 아래).
Prop_StallEnds ==
    (held # NoWrite) ~> (held = NoWrite)

\* 미적중이 살아 있는 동안 sticky 는 서 있다 — 「미적중이 있었다」를 미적중이
\* 살아 있는 동안 지울 수 없다 (set 이 정지 레벨).
Inv_StallSticky ==
    mstall.on => msticky

\* 미적중 정지를 푸는 것은 항목 커밋뿐이다 —
\*   e-defined.typ:329 「정지를 푸는 것은 항목 기입뿐이다 (E.3 2항)」
Prop_StallOnlyByEntry ==
    [][ (mstall.on /\ ~mstall'.on) => why' = "commit" ]_vars

\* 판정 4 — 「적법한 해제는 언제나 sticky 를 내린다」. 좋은 모델에서 반드시
\* 반증된다(run.sh MUST FAIL): 정지 중에 수락된 해제는 set(정지 레벨) 에 져서
\* fault 도 효과도 없이 사라진다. 정본이 그 유실을 문면으로 정했다 —
\* e-defined.typ:329 「정지 *중에* 쓴 해제는 유실된다」.
Prop_ClearAlwaysLowers ==
    [][ (acc'.kind = "mclr" /\ acc'.v /\ SpecMcOK(acc')) => ~msticky' ]_vars

(***************************************************************************)
(* 위험 도달성 증인 — 좋은 모델에서 반드시 반증돼야 한다. 가드마다 그      *)
(* 가드가 막는 입력이 실재함을 보인다 (없으면 그 가드의 삭제 실험이 가드를 *)
(* 한 번도 건드리지 못한다).                                               *)
(***************************************************************************)

\* lo_stages_only — 살아 있는 항목에 다른 프레임의 LO 가 온다.
Witness_NoLoOverLive == "loLive" \notin ev

\* hi_entry_match · reject_loud — 스테이징된 번호와 다른 항목의 HI 가 온다.
Witness_NoMismatch == why # "mismatch"

\* hi_needs_staging · reject_loud — 스테이징이 빈 HI 가 온다.
Witness_NoUnstaged == why # "unstaged"

\* hi_fires · hi_commit_whole — 프레임을 바꾸는 커밋이 일어난다.
Witness_NoFrameChange == "newFr" \notin ev

\* hi_v_carried — V=0 HI 가 살아 있는 항목을 무효화한다 (단일 항목 무효화).
Witness_NoKill == "kill" \notin ev

\* flush_fires · flush_valid_only — 살아 있는 파티션이 flush 된다.
Witness_NoFlushLive == "flushLive" \notin ev

\* flush_scoped — 다른 파티션이 살아 있는 동안 flush 가 일어난다.
Witness_NoFlushOther == "flushOther" \notin ev

\* flush_part_exists · reject_loud — 없는 파티션 값의 flush 가 온다.
Witness_NoPhantom == why # "phantom"

\* flush_rsv_strict · reject_loud — 실재 파티션에 예약 위반 flush 가 온다.
Witness_NoRsv == why # "rsv"

\* Refusal = "stall" — 하류 거부로 버스가 실제로 정지한다.
Witness_NoStall == held = NoWrite

\* mclr_fires — 정지가 풀린 뒤 선 채로 남은 sticky 위에 적법한 해제가 온다.
Witness_NoClearLive == "clrLive" \notin ev

\* mclr_needs_one — 선 sticky 위에(정지 없음) `[0]`=0 의 적법한 기입이 온다.
Witness_NoZeroLive == "zeroLive" \notin ev

\* mclr_rsv_strict · reject_loud — 예약 위반 해제가 온다.
Witness_NoMclrRsv == why # "mrsv"

\* mclr_keeps_stall — 미적중 정지 중에 적법한 해제가 온다 (판정 4 의 전건).
Witness_NoClearInStall == "clrStall" \notin ev

\* ro_rejected · reject_loud — RO 오프셋 쓰기가 온다.
Witness_NoRo == why # "ro"

\* 아래 셋은 ev 사건을 늘리지 않고 스텝 뒤 상태의 술어로 적는다 — ev 가 상태의 일부라
\* 사건 하나가 large 의 도달 상태를 늘린다 (머리 「규모」).

\* flush_drops_staging — 스테이징이 찬 파티션의 flush 가 실행된다 (가드의 전건).
\* stale 은 그런 flush 로만 서므로(스테이징 유효 · 래치 파티션 ∈ 실행 범위) 이 술어의
\* 첫 도달이 곧 그 flush 의 스텝이다. 뒤따르는 같은 파티션 flush 도 술어를 만족하지만
\* 증인이 보이는 것은 도달이므로 최단 반례가 첫 건넘이다.
Witness_NoFlushStaged == ~(why = "flush" /\ stale /\ PartOf(stg.ent) = acc.part)

\* flush_drops_staging — flush 를 건넌 스테이징 위에 *같은 번호*의 HI 가 온다 (속성의
\* 전건 — 판정 전 RTL 이 옛 프레임을 커밋하던 입력). HI 는 stale · stg 를 움직이지
\* 않으므로 스텝 뒤 상태가 곧 스텝 앞 상태다.
Witness_NoStaleHi == ~(acc.kind = "hi" /\ stale /\ acc.ent = stg.ent)

\* ent_part_exists · reject_loud — 항목 배열의 형상 밖 주소 기입이 온다 (BelowCap).
Witness_NoEntPhantom == why # "ephantom"

=============================================================================
