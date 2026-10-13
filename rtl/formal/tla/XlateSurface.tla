\* SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
\* SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
--------------------------- MODULE XlateSurface -----------------------------
\* 변환 저장소의 MMIO 문 — `0xC00` 형상 비노출 항목 표면(파티션 기저마다 VPN · FRAME ·
\* COMMIT · VPN_HI · 예약-엄격 28 워드)과 `0xE00` XLATE_FLUSH · `0xE10` XLATE_MISS_CLEAR ·
\* RO 세 워드(`0xE04`–`0xE0C`) 쓰기의 선-formal 모델.
\* 3.10 v1.0 묶음 RTL 파도 W3 (2026-10-13) 재작성 — 앞판(파도 3 · 4, 2026-09-26)은 호스트가
\* 색인을 고르는 LO/HI 직접 배열의 문이었다. 그 표면은 정본에서 사라졌다.
\*
\* ## 분업 — 이 모델은 「문」과 「칸 선택의 결과」를 잰다
\*
\*   XlateStore.tla    저장 블록 — 유효 게이팅 · 파티션 격리 · flush 가 데이터를 남긴다.
\*   Isolation.tla     조회 · 채움의 비간섭 — 설치 범위 · 채움 슬롯.
\*   XlateObs.tla      관측면 값 · 판정 시점(판정 래치) · 진행(HostSpec).
\*   XlateSurface.tla  호스트가 두드리는 *문* — VPN → FRAME → COMMIT 스테이징 (f), 칸을
\*                     장치가 고르는 커밋의 결과 (a)(b)(c)(g)(h), HIU-4 의 진짜 증명
\*                     (Inv_AtMostOneValidPerVpn), HIU-2 의 V=0 축 (Prop_V0Misses), 하류 정지의
\*                     처분과 그 풀림 (Prop_StallEnds · Prop_StallDataBlind), flush · 해제 · RO 처분.
\*
\* ## 정본 (좌표 뒤 「」 는 그 줄의 축자 — lint_section_refs 축 1 이 대조한다)
\*
\*   표면 — E.1.2 `0xC00` 행
\*   e-defined.typ:297 「호스트는 (VPN, 프레임, 권한)만 기입하고 장치 안 어느 칸에 둘지는 *장치가 정한다*」
\*   e-defined.typ:298 「`addr[8:7]` = 파티션 · 상한 4 다」
\*   e-defined.typ:299 「어느 항목이 상주하는지를 돌려주는 표면은 없다」
\*   e-defined.typ:305 「수락된 기입이 그 주소의 파티션을 래치한다」 — VPN.
\*   e-defined.typ:306 「기입은 *스테이징*이며 표에 커밋되지 않는다」 — FRAME.
\*   e-defined.typ:306 「래치 파티션의 기저에서만 수락한다」
\*   e-defined.typ:306 「커밋은 스테이징을 소진하지 않는다」
\*   e-defined.typ:308 「`[27:0]` 예약 = 0 (엄격)」 — COMMIT.
\*   e-defined.typ:308 「유효 비트를 담은 워드가 마지막이므로 부분 기입 상태가 유효해질 수 없다」
\*   e-defined.typ:308 「정지 중에는 효과가 없고, 수락되면 커밋되며, 드롭하지 않는다」
\*   e-defined.typ:308 「호스트 조치에 기대지 않고 다른 정지(미적중 정지 · 초기화 소거 구간)와 독립이다」
\*   e-defined.typ:308 「기다리지 않고 곧장 거절 + `[6]` 이다」 — 주소 · 스테이징 상태 사유.
\*   e-defined.typ:308 「수락 사이클에 거절된다 — 그 수락은 위 유계 정지 뒤일 수 있다」 — 데이터 사유.
\*   e-defined.typ:308 「비0 기입은 거절 + `[6]` · 스테이징 불변이며」 — VPN_HI.
\*   e-defined.typ:308 「수락된 VPN_HI 기입은 FRAME 스테이징 유효를 내린다.」
\*   e-defined.typ:308 「*표의 워드로 등재한다* — 쓰기는 거절 + `[6]`, 읽기는 0」 — 예약-엄격 28 워드.
\*   결과 규범 (a)–(h)
\*   e-defined.typ:310 「같은 (파티션, VPN) 에 두 항목이 동시에 적중하지 않는다 — 뒤 커밋이 앞 항목을 대체한다」 — (a) · HIU-4.
\*   e-defined.typ:310 「V=0 COMMIT 뒤 같은 (파티션, VPN) 조회는 반드시 미적중이다.」 — (b) · HIU-2 V=0 축.
\*   e-defined.typ:310 「축출은 같은 파티션 안에서만 일어난다」 — (c).
\*   e-defined.typ:310 「미적중 정지는 정지한 요청의 (파티션, VPN) 에 대한 V=1 커밋(거부 채움 포함)이 수락되면 풀린다」 — (d).
\*   e-defined.typ:310 「`0xE00` flush 는 그 파티션의 항목을 전부 무효로 한다」 — (e).
\*   e-defined.typ:311 「VPN 기입은 기입 주소의 파티션을 래치하고 FRAME 스테이징 유효를 내린다」 — (f) 1항.
\*   e-defined.typ:311 「묵은 프레임이 새 VPN 에 묶이지 않게 하는 장치이고」
\*   e-defined.typ:311 「FRAME 기입은 래치 파티션과 같은 기저에서만 수락한다」 — (f) 2항.
\*   e-defined.typ:311 「V=1 COMMIT 은 *FRAME 유효*를 요구한다」 — (f) 3항.
\*   e-defined.typ:311 「V=0 COMMIT 은 VPN 유효만 요구한다」
\*   e-defined.typ:311 「래치와 다른 파티션 기저의 COMMIT · VPN 없는 COMMIT · FRAME 유효 없는 V=1 COMMIT」 — (f) 4항.
\*   e-defined.typ:311 「없는 파티션 기저로의 기입은 어느 워드든 거절 + `[6]` 이」 — (f) 6항.
\*   e-defined.typ:311 「래치 파티션에 대한 *수락된* flush 가 두 스테이징 유효를 모두 내린다」 — (f) 7항.
\*   e-defined.typ:312 「교체 결정과 교체 상태 갱신은 커밋 경로에서만 일어나고」 — (g).
\*   e-defined.typ:312 「장치는 축출을 같은 파티션에 대한 호스트 COMMIT 과 flush 의 결과로만 한다」 — (h).
\*   제어 구역 · 일반 처분
\*   e-defined.typ:321 「기입이 곧 발화」 — XLATE_FLUSH.
\*   e-defined.typ:321 「`[31:8]` 예약 = 0 (엄격)」
\*   e-defined.typ:321 「지우는 것은 그 파티션의 *유효 비트뿐*이고 태그·변환 데이터는 남는다」
\*   e-defined.typ:321 「다른 파티션을 래치한 스테이징은 건드리지 않는다」
\*   e-defined.typ:321 「없는 파티션 값의 기입은 거절 + loud fault 다」
\*   e-defined.typ:329 「`[0]` 에 1 기입 = 미적중 sticky 해제 · `[31:1]` 예약 = 0 (엄격)」 — XLATE_MISS_CLEAR.
\*   e-defined.typ:329 「*정지 자체는 이것으로 풀리지 않는다* — 정지를 푸는 것은 항목 기입뿐이다」
\*   e-defined.typ:329 「정지 *중에* 쓴 해제는 유실된다」
\*   e-defined.typ:202 「*RO 오프셋의 쓰기* — 거절 + loud fault 다」 — `0xE04`–`0xE0C`.
\*   e-defined.typ:188 「워드 안의 예약 비트는 *엄격*이다」
\*   e-defined.typ:414 「실재하지 않는 파티션 값의 기입은 *수락되지 않고 거절 + loud fault* 다」
\*   e-defined.typ:415 「이므로 FAULT_STATUS `[6]` 에 접는다」
\*   e-defined.typ:419 「*조용한 무시는 금지다.*」
\*   e-defined.typ:424 「상한 아래 형상에서는 그 주소가 없는 파티션을 가리키고」
\*   e-defined.typ:1547 「한꺼번에 비우는 전역 발화는 이 표면에 없고, 있어서도 안 된다」
\*   e-defined.typ:873 「VPN · FRAME 스테이징 기입과 V=0 COMMIT 은 정지를 풀지 않는다」 — E.3 2항.
\*   03-hiu.typ:778 「유효 비트가 유일한 방벽이다」
\*   03-hiu.typ:828 「*명시 예외 — `0xC00` 구역의 예약-엄격 워드.*」 — 예약 오프셋 정책의 명시 예외.
\*   03-hiu.typ:2075 「flush 또는 V=0 COMMIT 의 에지 *뒤에 판정되는* 조회에서」 — HIU-2.
\*   03-hiu.typ:2092 「*적중 유일성* — 하나의 요청에 대해 적중하는 항목은 최대 하나다」 — HIU-4.
\*
\* ## 모델 변경 (앞판 → W3)
\*
\*   · 표 tbl : [Parts -> [Slots -> [vpn, fr, v]]]. 앞판은 [Parts × Indices -> [v, fr]] 이고 호스트가
\*     항목 번호를 지목했다. 이제 호스트는 (VPN, 프레임) 만 쓰고 COMMIT 이 칸을 고르는 것은 장치의
\*     비결정 선택이다 — 같은 파티션에 같은 VPN 의 유효 칸이 있으면 그 칸을 덮고(태그 탐색 —
\*     commit_replaces_vpn), 없으면 그 파티션의 아무 칸(희생 칸)을 덮는다. 교체 정책 · 연관도는
\*     형상이므로 비결정으로 과근사한다 — 속성은 어느 형상에서도 서야 한다. Slots 1 은 직접 사상과
\*     동형이다(같은 VPN 은 늘 같은 칸 — W3-3 DP-1 의 참조 형상 4 × 16 의 한 색인 열). Slots 2 는
\*     축출 · 대체 탐색이 실재하는 형상이고 전용 cfg 로만 돈다.
\*   · 기입 종류 vpn · frame · commit · vpnhi · rsvw · flush · mclr · ro. 앞판의 lo · hi 는 사라졌다.
\*   · 스테이징 stg = [vv, fv, p, vpn, fr] — VPN 유효 · FRAME 유효 · 래치 파티션 · 값 둘. 앞판은
\*     [sv, ent, fr] (항목 번호 래치) 였다.
\*   · 정본 유령 cs (스테이징) · stale (flush 를 건넌 빈 스테이징) · fstale (VPN · VPN_HI 가 내린
\*     묵은 프레임). 가드는 이것을 읽지 않고 속성의 참 쪽만 읽는다 — 장치가 스스로 적법하다고 보는
\*     것을 속성이 믿지 않게 한다. 좋은 모델에서 cs = stg (Inv_StgIsSpec) 라 상태를 늘리지 않는다.
\*   · 하류 정지 판정 Refused 는 주소 · 스테이징 상태만 본다(RefuseDomain = "addrstate"). 데이터
\*     사유(FRAME 유효 없는 V=1 · `[27:0]` 비0)는 정지를 받고, 풀린 수락 사이클(Retry)에 거절된다.
\*   · 미적중 정지는 (파티션, VPN) 키이고 그 키가 표에서 유효해지는 커밋 에지에 풀린다 — 앞판은
\*     「그 항목 번호에 V=1」 이었다.
\*   · 대형 · 칸 2 · 상한 아래 cfg 와 가드 삭제 · 짝 cfg 는 VIEW StateView 로 돈다 — 한 스텝짜리 보조
\*     넷(acc · why · loud · ev)을 접는다. 건전성 근거는 StateView 정의 위 주석. 작은 cfg 는 VIEW 없이
\*     같은 속성을 걸어 그 대조가 된다. 증인은 보조를 상태로 읽으므로 VIEW 없이 돈다.
\*
\* ## 설계 결정 — 하류 정지의 처분 (이제 정본 규범이다)
\*
\* 하류 채움 슬롯이 찬 동안의 적법한 COMMIT 은 버스 정지다 (Refusal = "stall" — 좋은 모델). 기각한
\* 두 처분은 대안으로 남는다: "reject" 는 옳은 드라이버에 fault (Prop_RejectOnlyMalformed),
\* "drop" 은 조용한 흡수 (Prop_CommitCommits). 정지의 *정의역*도 대안으로 가른다:
\*   RefuseDomain = "addrstate"  needReady 가 주소 · 스테이징 상태만 본다 (좋은 모델 · RTL 지도의 XlateStaging 식).
\*   RefuseDomain = "full"       데이터 필드도 본다 — 데이터 사유 COMMIT 이 하류가 찬 사이클에 곧장
\*                               거절된다. 같은 기입이 사이클 타이밍에 따라 두 시점의 판정을 받는
\*                               것이고 RTL 에서는 wdata → ready 조합 경로다 (lint_ready_cone M2).
\*                               → Prop_StallDataBlind 반례.
\*   RefuseDomain = "kind"       종류만 본다 — 하류가 찬 동안 COMMIT 이면 주소 · 상태 사유까지 정지
\*                               뒤 거절한다. :308 「기다리지 않고 곧장 거절 + `[6]` 이다」 를 어긴다.
\*                               → Prop_AddrRejectNoWait 반례. 둘(StallDataBlind · AddrRejectNoWait)이
\*                               정지의 정의역을 「주소 · 상태 적법 ∧ 하류 점유」 로 양쪽에서 조인다.
\* 정지는 호스트 조치 없이 풀린다 — LiveSpec 의 공정성은 *장치* 동작(Retry · Drain)에만 걸린다.
\* 미적중 정지와 독립이다 — 가드 stall_independent. 사이클 수 상한(DP-21: 「설치가 오지 않는 동안
\* ≤ xlateParts 사이클」)은 이 모델에 없다 — 닫힌 목록 3.
\*
\* ## 가드 — 각각 정본 한 문장. 삭제 run 은 자기 속성이 첫 위반으로 난다.
\*
\*   앞판 이름 유지 — 의미가 이어진다 (DP-14)
\*   flush_fires        :321 기입이 곧 발화. 지우면 적법한 flush 가 흡수된다. → Prop_FlushClears
\*   flush_scoped       :1547 전역 발화 금지. 지우면 flush(p) 가 전 파티션을 비운다. → Prop_FlushScoped
\*   flush_valid_only   :321 유효 비트뿐. 지우면 VPN · 프레임까지 지운다. → Prop_FlushKeepsData
\*   flush_part_exists  :321 · :414 없는 파티션 값은 거절. 지우면 필드가 잘려 다른 실재 파티션이
\*                      flush 된다. → Prop_PhantomRejected
\*   flush_rsv_strict   :321 · :188 예약 엄격. → Prop_RsvRejected
\*   reject_loud        :419 조용한 무시 금지 — 거절은 전부 `[6]`. → Prop_RejectLoud
\*   mclr_fires         :329 `[0]`=1 해제가 sticky 를 내린다(정지 없을 때). → Prop_MclrClears
\*   mclr_needs_one     :329 해제는 `[0]`=1 뿐. → Prop_MclrZeroKeeps
\*   mclr_rsv_strict    :329 `[31:1]` 엄격. → Prop_MclrRsvRejected
\*   mclr_keeps_stall   :329 해제는 정지를 풀지 않는다. → Prop_MclrKeepsStall
\*   ro_rejected        :202 RO 오프셋 쓰기는 거절. → Prop_RoRejected
\*   flush_drops_staging :321 · :311 (f) 7항 — 래치 파티션의 수락된 flush 가 *두* 유효를 내린다
\*                      (앞판은 유효 하나). 지우면 flush(임대 회전 ⑵)를 건넌 VPN · FRAME 이 새
\*                      임대의 COMMIT 한 워드로 커밋된다 — FRAME · VPN_HI 도 그 스테이징 위에
\*                      수락된다. → Prop_FlushEndsStaging
\*   ent_part_exists    :311 (f) 6항 · :424 — 없는 파티션 기저의 *어느 워드든* 거절(앞판은 LO · HI).
\*                      지우면 기저가 partW 로 잘려 실재 파티션이 래치 · 커밋된다.
\*                      → Prop_EntPhantomRejected (격리 귀결은 고정 속성 Prop_EntNoAlias). BelowCap.
\*   개명 — LO/HI 전용 여섯 (DP-14)
\*   frame_stages_only  ← lo_stages_only. :306 VPN · FRAME · VPN_HI 기입은 표에 닿지 않는다. 지우면
\*                      FRAME 이 래치 (파티션, VPN) 의 산 칸을 곧장 덮는다(쓰기 관통). → Prop_StagesOnly
\*   commit_fires       ← hi_fires. :308 COMMIT 이 커밋 발화다. 지우면 적법한 COMMIT 이 흡수된다.
\*                      → Prop_CommitCommits
\*   commit_base_match  ← hi_entry_match. :311 (f) 4항 — 래치와 다른 기저의 COMMIT 은 거절. 지우면
\*                      래치한 VPN · 프레임이 *다른 파티션*에 커밋된다. → Prop_BaseMismatchRejected
\*   commit_needs_vpn   ← hi_needs_staging. :311 (f) 4항 — VPN 없는 COMMIT 은 거절. 지우면 reset
\*                      뒤 한 번도 쓰이지 않은 VPN 이 커밋된다. → Prop_NoVpnRejected
\*   commit_whole       ← hi_commit_whole. :308 단일 에지 커밋. 지우면 V 가 먼저 서고 VPN · 프레임이
\*                      다음 에지에 앉는다 — 유효한데 옛 키 · 옛 프레임인 칸이 한 스텝 관측된다.
\*                      → Prop_CommitWhole
\*   commit_v_carried   ← hi_v_carried. :308 · :310 (b) — V 는 쓴 값이다. 지우면 V=0 COMMIT 이 그
\*                      (파티션, VPN) 을 *유효하게* 커밋한다. → Prop_V0Misses (HIU-2 V=0 축)
\*   신설
\*   vpn_drops_frame    :311 (f) 1항 · :308 VPN_HI — VPN · VPN_HI 의 수락된 기입이 FRAME 유효를
\*                      내린다. 지우면 묵은 프레임이 새 VPN 에 묶여 커밋된다. → Prop_VpnDropsFrame
\*   commit_needs_frame :311 (f) 3항 — V=1 은 FRAME 유효를 요구한다(V=0 은 VPN 만). 지우면 한 번도
\*                      쓰이지 않은 프레임이 유효로 커밋된다. → Prop_CommitNeedsFrame
\*   frame_pair_check   :306 · :311 (f) 2항 — FRAME · VPN_HI 는 래치 파티션 기저 ∧ VPN 유효에서만
\*                      수락. 지우면 다른 파티션 기저에 쓴 프레임이 래치 파티션의 항목에 묶인다.
\*                      → Prop_FramePairRejected
\*   vpnhi_strict       :308 VPN_HI 비0 은 거절 · 스테이징 불변. → Prop_VpnHiStrict
\*   rsvw_rejected      :308 · 03:828 예약-엄격 28 워드 쓰기는 거절 + `[6]`. 지우면 흡수된다(3.7 의
\*                      관대). 삭제 run 은 흡수로 *과근사*한다 — W3 전 RTL(aa91e86)은 그 자리를
\*                      앞판 색인 2–15 의 LO/HI 로 수락해 스테이징 · 커밋까지 한다(흡수보다 나쁜
\*                      넷째 처분 — 모델의 처분 집합 밖이라 흡수로 접었다).
\*                      → Prop_RsvwRejected
\*   commit_rsv_strict  :308 `[27:0]` 엄격 — 수락 사이클에 거절. → Prop_CommitRsvRejected
\*   commit_replaces_vpn :310 (a) · HIU-4 — 같은 파티션에 같은 VPN 의 유효 칸이 있으면 그 칸을 덮는다.
\*                      지우면 같은 (파티션, VPN) 이 두 칸에 유효하다. → Inv_AtMostOneValidPerVpn
\*                      (칸 2 cfg). V=0 축의 귀결(Prop_V0Misses)은 짝 _pair_v0_replace 가 따로 잰다.
\*   evict_in_partition :310 (c) — 희생 칸은 COMMIT 의 파티션 안에서만. 지우면 다른 파티션의 칸을
\*                      덮는다(격리 위반). → Prop_CommitScoped
\*   evict_on_commit_only :312 (h) — 자발 축출 없음. 지우면 산 칸이 시간 · 배경으로 무효가 된다
\*                      (동작 Decay). → Prop_TableByDoor
\*   stall_independent  :308 「다른 정지와 독립」 — 채움 슬롯의 저장 커밋(Drain)은 미적중 정지와
\*                      무관하게 일어난다. 지우면 미적중 정지 중 하류 정지가 영원히 남는다 — 그
\*                      정지를 풀 COMMIT 이 버스에 잡혀 있기 때문이다. → Prop_StallEnds (LiveSpec ·
\*                      CHECK_DEADLOCK FALSE — 판정은 데드락이 아니라 진행 속성의 반례다)
\*
\* ## 고정 속성 (가드 아님 — 좋은 모델 cfg 가 건다 · 반증력은 대안 · 짝 run 이 든다)
\*
\*   Prop_RejectOnlyMalformed  거절은 정본 사유로만.            ← Refusal = "reject"
\*   Prop_LoudOnlyOnReject     `[6]` 은 거절에서만.
\*   Prop_StallDataBlind       주소 · 상태 적법 COMMIT 은 하류가 빈 사이클에만 수락된다.
\*                                                               ← RefuseDomain = "full"
\*   Prop_AddrRejectNoWait     버스가 잡아 두는 COMMIT 은 주소 · 상태로 적법한 것뿐이다 (:308
\*                             「기다리지 않고 곧장 거절」 — 정지 정의역의 주소 절반).
\*                                                               ← RefuseDomain = "kind"
\*   Prop_HoldInert            잡아 두는 스텝은 아무것도 움직이지 않는다 (:308 「정지 중에는 효과가
\*                             없고」 — 표 · 스테이징 · 하류 · 미적중 정지 · sticky · `[6]`).
\*   Prop_RejectInert          거절은 아무것도 움직이지 않는다 (:311 (f) 4항 — 표 · 스테이징 ·
\*                             하류 · 미적중 정지 · sticky). 각 가드 속성은 자기 축(표 · 스테이징)만
\*                             보므로 이 일반형이 나머지 축을 든다.
\*   Prop_V1Hits               (a) 적법한 V=1 뒤 그 파티션에 (VPN, 프레임) 이 유효로 선다.
\*   Inv_ValidFrameWritten     유효 칸의 VPN · 프레임은 호스트가 쓴 값이다 (:308 부분 기입).
\*   Inv_StgIsSpec             장치 스테이징 = 정본 스테이징 (유령이 상태를 늘리지 않는 근거).
\*   Prop_FlushStagingScoped   flush 는 다른 파티션 래치 스테이징을 건드리지 않는다. ← StgAlt "global"
\*   Prop_FlushStagingKeepsData flush 가 내리는 것은 유효 둘뿐.
\*   Prop_EntNoAlias           없는 기저의 COMMIT 은 실재 칸을 움직이지 않는다. ← 짝 ent_alias
\*   Inv_StallSticky · Prop_StallOnlyByEntry · Prop_StallReleasedByFill — E.3 2항 (그 키를 상주하게
\*                             만드는 V=1 커밋만 푼다 — 다른 (파티션, VPN) 의 커밋은 풀지 않는다 ·
\*                             정지한 키의 적법한 V=1 은 반드시 푼다).
\*   Prop_ClearAlwaysLowers    발견 4 — 좋은 모델에서 반드시 반증된다 (:329 정지 중 해제 유실).
\*
\* ## 짝 · 대안
\*
\*   _pair_host_index   HostIndex = TRUE — 형상 노출 대안: 호스트가 COMMIT 에 칸을 지목하고 장치는
\*                      대체 탐색을 하지 않는다 → Inv_AtMostOneValidPerVpn 반례(칸 2). *주의*: W3 전
\*                      RTL(HEAD aa91e86)은 이 기계가 *아니다* — 그 RTL 의 저장 키는 태그(28b) ‖
\*                      색인(4b) = VPN 이라 호스트가 색인을 고르는 것이 곧 VPN 하위 비트를 고르는
\*                      것이고, 같은 VPN 이 두 색인에 앉을 수 없다. 이 짝이 보이는 것은 「색인을
\*                      키와 독립으로 고르게 하는 형상 노출 표면」이 HIU-4 를 구조로 잃는다는 것 —
\*                      새 표면이 칸 선택을 장치에 두고 대체 탐색을 의무로 건 이유다.
\*   _pair_v0_replace   commit_replaces_vpn 삭제의 V=0 축 → Prop_V0Misses.
\*   _pair_refuse_full  RefuseDomain = "full" → Prop_StallDataBlind.
\*   _pair_refuse_kind  RefuseDomain = "kind" → Prop_AddrRejectNoWait (주소 · 상태 사유도 기다린다).
\*   _pair_refusal_*    하류 거부의 기각 처분 둘.
\*   _pair_stg_*        스테이징 수명의 기각 갈래 둘 (판정 T5). consume 은 두 문장을 함께 깬다 —
\*                      _pair_stg_consume(flush 가 스테이징을 끝내지 않는다 → Prop_FlushEndsStaging) ·
\*                      _pair_stg_consume_commit(:306 「커밋은 스테이징을 소진하지 않는다」 — 커밋
\*                      뒤 재커밋이 VPN 없음으로 거절된다 → Prop_CommitCommits).
\*   _pair_ent_alias    없는 기저를 잘라 커밋 → Prop_EntNoAlias.
\*   _pair_today_*      파도 3 이전 RTL (문 없음 — 쓰기 흡수). 역사 짝.
\*   _pair_live_nodrain Drain 공정성 없음 → Prop_StallEnds.
\*   _pair_clear_in_stall 발견 4.
\*
\* ## RTL GUARD-MAP 예정 문면 (W3 RTL 단계 — 줄 중립 · 가드 하나에 줄 하나)
\*
\*   XlateStaging.scala (문 — 전면 재작성, 상태 stgVpnValid · stgFrameValid · stgPart · stgVpn ·
\*   stgFrame, RTL 지도의 XlateStaging 식):
\*   · frame_stages_only -> vpnOk · frOk · vhOk 는 스테이징 레지스터만 움직이고 commit.valid ·
\*     flush.valid · missClr 어느 것도 세우지 않는다 — 표를 움직이는 원천은 그 두 포트뿐이다.
\*   · commit_fires -> needReady(= wrEnt ∧ w==2 ∧ pairOk) ∧ installReady ∧ ¬cmDataBad 이면
\*     commit.valid — 흡수 가지가 없다.
\*   · commit_base_match -> needReady 의 pairOk 중 stgPart === p 항 — 다른 기저의 COMMIT 은
\*     commit.valid 없이 badWrite(곧장 — 정지 없음). 「곧장」(주소 · 상태 사유는 needReady 가
\*     0 이라 ready 를 내리지 않는다)의 모델 쪽은 고정 속성 Prop_AddrRejectNoWait 이고 RTL 쪽은
\*     XlateStaging/props.sby 의 p_need_iff(주소 · 상태 절반) · assembly a_ready_only_slot 이다.
\*   · commit_needs_vpn -> needReady 의 pairOk 중 stgVpnValid(reset 0) 항.
\*   · commit_whole -> commit 번들 하나(part · vpn = stgVpn · frame = stgFrame · perm · v = wdata)가
\*     한 사이클에 나가고 XlateStore 는 install.fire 한 에지에 채움 줄 전체를 싣는다(fillShadow 가림).
\*   · vpn_drops_frame -> vpnOk 와 vhOk 가 stgFrameValid := False.
\*   · commit_needs_frame -> cmDataBad 의 (wdata(31) ∧ ¬stgFrameValid) 항.
\*   · frame_pair_check -> frOk · vhOk 의 pairOk 항 — 짝 불일치 FRAME · VPN_HI 는 badWrite · 부동.
\*   · vpnhi_strict -> vhOk 의 wdata === 0 항.
\*   · rsvw_rejected -> w ≥ 4 의 항목 구역 쓰기는 badWrite — 어느 스테이징 · 발화도 없다.
\*   · commit_rsv_strict -> cmDataBad 의 (wdata & COMMIT_RSV) ≠ 0 항.
\*   · flush_fires · flush_scoped · flush_part_exists · flush_rsv_strict · mclr_* · ro_rejected ->
\*     앞판 문면 그대로(0xE00 구역 처분 불변). flush_valid_only -> DELEGATED(XlateStore) 그대로.
\*   · flush_drops_staging -> flushDrop(flush.valid ∧ ¬vpnOk ∧ partField[1:0] === stgPart)이
\*     stgVpnValid · stgFrameValid 둘을 내린다 (값 레지스터는 부동).
\*   · ent_part_exists -> phantom = partBad(p) 이면 어느 워드든 badWrite · 스테이징 부동 (기본 형상
\*     elaborate 상수 False — p2.sby 가 잰다).
\*   · reject_loud -> 주소 · 상태 사유는 badWrite → surfBadWr → `[6]`; 데이터 사유(cmAcc ∧ cmDataBad)는
\*     Wt64Top xlateArea 의 원천별 sticky → `[6]` 합류(DP-15 · fpBindArea 선례).
\*   XlateStore.scala (저장 — 로직 불변 · `:200` 부동):
\*   · commit_v_carried -> 옛 :329 hi_v_carried 줄을 같은 줄에서 개명 — install.v(= COMMIT [31])가
\*     채움 줄의 v 로 들어가 validBits := commitLine.v.
\*   · evict_in_partition -> 커밋 주소 = commitSel @@ idx, commitSel = 채움 슬롯 번호 = 파티션.
\*   · evict_on_commit_only -> validBits · store 의 쓰기 원천은 커밋(commitFire) · flush 둘뿐 —
\*     시간 · 조회 · 배경 경로가 없다(조회는 readAsync 만).
\*   · stall_independent -> commitFire = fillPend.orR 의 콘에 hold · missStall · 버스 입력이 없다 —
\*     측정은 xlatestore s_pend_bounded(전건 f_quiet ≥ PARTS) · door.sby.
\*   Wt64Top.scala xlateArea (파일 끝):
\*   · commit_replaces_vpn -> install.idx = XlateStore.idxOf(commit.vpn) · install.tag =
\*     XlateStore.tagOf(commit.vpn) — 조회의 reqIdx · reqTag 와 *같은 함수*라 같은 VPN 은 같은 칸으로
\*     가서 덮이고 대기 중에는 fillShadow 가 옛 판을 가린다(A″ · DP-1 직접 사상).
\*     *주의*: RTL 의 삭제 유비(설치와 조회가 다른 분할 함수)는 모델의 「두 칸 동시 유효」 반례를
\*     내지 않는다 — 조회 후보가 한 칸뿐이라서다. 그 결함은 (a)(b) 위반(V=1 미적중 · V=0 뒤 적중)
\*     으로 나타나므로 RTL 측정은 이중 유효 불변식이 아니라 door.sby 의 (a)/(b) 단언이다.
\*   · evict_in_partition 의 RTL 항은 기존 Isolation.install_scoped 사상(XlateStore.scala)과 같은
\*     항이다 — 같은 줄을 두 가드가 가리킨다(중복이지 누락이 아니다).
\*   · stall_independent 는 Drain 쪽(채움 슬롯 commitFire 가 미적중 정지를 보지 않는다)만 가드다.
\*     ready 쪽(정지된 COMMIT 의 ready 가 missStall 에 기대지 않는다)은 모델의 Retry 에 미적중 정지
\*     항이 구조로 없고(그런 항을 넣은 변이는 Prop_StallEnds 가 잡는다 — 비상주 실측), RTL 쪽은
\*     assembly a_ready_only_slot · door.sby 다.
\*   Wt64Top.scala MmioPage GUARD-MAP (W3 RTL 단계 — 이 변경이 거짓으로 만드는 줄 넷):
\*   · MmioPage.nocons_rejected 줄에 「XlateStaging w ≥ 4(예약-엄격 28 워드) → badWrite」 항을 더한다.
\*   · MmioPage.rsp_on_accept 줄의 「적법 XLATE_ENTRY_HI *쓰기*」 → 「적법 COMMIT *쓰기*(needReady)」.
\*   · MmioPage.wo_read_zero 줄에 예약-엄격 워드의 읽기 0(resvRd)을 적는다.
\*   · MmioPage.resv_lenient 줄의 「구역 안 미정의 워드」 에서 0xC00 의 예약-엄격 워드를 뺀다.
\*   (정지 처분 자체 — when(wrEnt ∧ isCommit ∧ xstg.io.needReady) io.mmio.ready := installSlotFree —
\*   는 가드가 아니라 설계 결정이고 VERIFIES Wt64Top.xlate_surface 몫이다. RefuseDomain 의 RTL 쪽은
\*   needReady 콘에 wdata 가 없다는 lint_ready_cone.)
\*
\* ## 닫힌 목록 — 이 모델이 재지 않는 것과 그 몫
\*
\*   1. 주소 디코드 — 어느 비트가 파티션 · 워드인가(addr[8:7] · addr[6:2])와 워드 색인 ≥ 4 의
\*      예약-엄격 판정은 후-formal(XlateStaging/props.sby · assembly 구역 분류) 몫. 기입은 종류를
\*      직접 지목한다.
\*   2. 권한 필드 `[30:28]` — 프레임 토큰에 접혔다. V=0 COMMIT 의 `[30:28]` 수락(DP-20)은 관측
\*      불가라 재지 않는다 — 몫: XlateStaging/props.sby 의 「V=0 은 cmDataBad 에 권한 항이 없다」.
\*   3. 시간 — 하류 정지의 사이클 수 상한(DP-21 「설치가 오지 않는 동안 ≤ xlateParts 사이클」).
\*      모델은 진행만 잰다. 몫: xlatestore.sby s_pend_bounded + w_pend_drains · XlateDoor/door.sby
\*      (적법 COMMIT 의 ready 하강은 N 사이클 안에 풀린다) · assembly (A) a_xhold_quiet ·
\*      a_ready_only_slot. 「설치가 오지 않는 동안」 전건의 근거가 이 모델의 버스 단일성이다 —
\*      held 가 서 있는 동안 Present 가 꺼진다(정지 중 새 COMMIT 없음).
\*   4. 채움 슬롯 · 저장 블록 이관 — 가시성 면에서 하나로 접었다(커밋 에지에 칸이 선다). 대기 줄
\*      가림 · 바이패스는 XlateStore · Isolation · xlatestore.sby 몫.
\*   5. VPN 색인/태그 분할(A″) — 칸 선택의 *함수*는 모델 밖이다. 같은 VPN → 같은 칸의 구조는
\*      Wt64Top xlateArea 의 idxOf/tagOf 공용과 door.sby 결선 등식 몫.
\*   6. 판정 시점 — 커밋 효력이 「에지 뒤에 판정되는 조회」에만 미친다는 범위는 XlateObs.tla 몫.
\*      여기의 Lookup 은 래치 없는 조회 하나로 접었다.
\*   7. 교체 상태 — 연관도 1 · 교체 상태 없음(DP-2)이라 (g) 의 「교체 상태 갱신은 커밋 경로에서만」
\*      은 공허하게 참이다. 희생 칸 선택은 비결정이다.
\*   8. sub-word 쓰기 — 버스 어댑터 몫(MmioPage.unaligned_rejected).
\*   9. `[6]` 의 sticky · W1C · 원천별 sticky 합류 — loud 는 그 스텝의 발화 펄스다. 데이터 사유
\*      sticky(DP-15)의 결선은 assembly 몫.
\*  10. 읽기 방향 — 항목 구역 · WO 워드의 읽기 0 은 MmioPage.wo_read_zero · assembly 몫.
\*  11. 최상위 IO 설치 · flush 입력 — 은퇴했다(문이 유일한 원천). 모델 밖.
\*  12. reset 형식 단언 — W3-9 대로 하지 않는다. Init 이 reset 값의 모델이다.
\*  13. 형상 ≠ 참조 형상(색인 ≠ 16 · DP-23) — 선택 항목, 모델은 Slots 를 토큰으로 둔다.
\*  14. 초기화 소거 구간과의 독립 — :308 「다른 정지(미적중 정지 · 초기화 소거 구간)와 독립」 중
\*      미적중 정지만 모델에 있다. 소거 구간은 모델 밖이다 — 몫: 채움 슬롯 commitFire 의 콘에
\*      소거 입력이 구조로 없다는 것(xlatestore.sby s_pend_bounded · door.sby).
\*  15. 결과 (g) 의 조회 경로 — 커밋 처리가 조회 경로에 정지 · ready 를 만들지 않는다는 것은 여기서
\*      구조(Lookup 이 busy · held 를 읽지 않는다)뿐이다. 몫: Isolation.fill_offpath.
\*  16. 단일 조회 지점 — (h) 와 E.4 3항의 조회 지점이 하나라는 전제는 미적중 정지 하나(mstall)로
\*      가정했다. 몫: v1.0 형상의 HiuPipeline 구조(E.4 3항).
\*
\* ## 규모와 분리 검사 (실측은 run.sh 이 모델 절 머리)
\*
\*   작은 cfg(칸 1 · VPN 1)는 VIEW 없이 · 대형(칸 1 · VPN 2) · 칸 2 둘 · 상한 아래는 VIEW StateView.
\*   칸 2 cfg 는 둘이다 — 파티션 1 · VPN 3(축출 깊이) 과 파티션 2 · VPN 1(태그 탐색이 다른 파티션을
\*   읽는 결함 — 파티션 1 에서는 P0 = ep 라 보이지 않는다). Inv_AtMostOneValidPerVpn 은 칸 1 cfg
\*   에서 공허하다(한 원소 집합의 부분집합) — 반증력은 칸 2 cfg 둘 · commit_replaces_vpn 삭제 ·
\*   _pair_host_index 가 든다.
\*   대안 상수(RefuseDomain · StgAlt · Refusal · HostIndex · BelowCap)는 대형에서 끈다.
\*   분리 검사(비상주 — 결과 요약은 run.sh 이 절 머리): 가드마다 지운 판에 자기 속성을 뺀 가드 속성 · 고정 속성
\*   전부를 걸고 위반을 하나씩 빼며 PASS 까지 — 행이 그 삭제가 깨는 속성 집합이다.
EXTENDS Naturals, FiniteSets

CONSTANTS
    Parts,           \* 실재하는 파티션 — 불투명 토큰 (칸 2 전용 cfg 만 1 — 아래 ASSUME 주석)
    Slots,           \* 파티션당 저장 칸 — 불투명 토큰. 1 = 직접 사상 동형(같은 VPN 은 늘 같은 칸),
                     \* 2 = 축출 · 대체 탐색이 실재하는 형상 (전용 cfg)
    Vpns,            \* 가상 페이지 번호 — 불투명 토큰
    Frames,          \* 물리 프레임(+ 권한)의 추상 — 불투명 토큰 (≥ 2 — 찢김 · 대체가 보이려면)
    Junk,            \* reset 뒤 한 번도 쓰이지 않은 프레임 내용 (모델 값)
    NoVpn,           \* reset 뒤 한 번도 쓰이지 않은 VPN 내용 (모델 값)
    Phantom,         \* 없는 파티션 값 — XLATE_FLUSH `[7:0]` · 상한 아래 형상의 기저 (모델 값)
    Refusal,         \* 하류 거부(채움 슬롯 점유)의 처분 — "stall" | "reject" | "drop"
    RefuseDomain,    \* 정지 판정의 정의역 — "addrstate"(주소 · 스테이징 상태만 — 좋은 모델) |
                     \* "full"(데이터 필드도 본다 — 기각한 대안: wdata → ready 경로) |
                     \* "kind"(종류만 — 기각한 대안: 주소 · 상태 사유 COMMIT 도 기다린다)
    StgAlt,          \* 스테이징 수명의 갈래 — "flush" | "consume" | "global" (뒤 둘은 기각한 대안)
    BelowCap,        \* 형상 < 인코딩 상한 — TRUE 면 창이 없는 파티션(Phantom)의 기저를 표현한다
    HostIndex,       \* TRUE = 형상 노출 대안 — 호스트가 COMMIT 에 칸을 지목한다(장치의 대체 탐색 없음)
    DisabledGuards

ASSUME Refusal \in {"stall", "reject", "drop"}
ASSUME RefuseDomain \in {"addrstate", "full", "kind"}
ASSUME StgAlt \in {"flush", "consume", "global"}
ASSUME BelowCap \in BOOLEAN /\ HostIndex \in BOOLEAN
\* 파티션 1 은 칸 2 전용 cfg 뿐이다 — 기저 불일치 · flush 범위 · 축출 범위의 입력이 없는 형상이라
\* 그 속성들은 거기서 공허하고, 파티션 2 cfg(작은 · 대형 · 삭제 · 증인)가 입력을 든다.
ASSUME Cardinality(Parts) >= 1 /\ Cardinality(Frames) >= 2 /\ Slots # {} /\ Vpns # {}
ASSUME Junk \notin Frames /\ NoVpn \notin Vpns /\ Phantom \notin Parts

AllGuards == {"frame_stages_only", "commit_fires", "commit_base_match", "commit_needs_vpn",
              "commit_whole", "commit_v_carried",
              "vpn_drops_frame", "commit_needs_frame", "frame_pair_check", "vpnhi_strict",
              "rsvw_rejected", "commit_rsv_strict", "commit_replaces_vpn",
              "evict_in_partition", "evict_on_commit_only", "stall_independent",
              "flush_fires", "flush_scoped", "flush_valid_only",
              "flush_part_exists", "flush_rsv_strict", "reject_loud",
              "mclr_fires", "mclr_needs_one", "mclr_rsv_strict", "mclr_keeps_stall",
              "ro_rejected", "flush_drops_staging", "ent_part_exists"}
ASSUME DisabledGuards \subseteq AllGuards
On(g) == g \notin DisabledGuards

\* 창이 표현하는 기저의 파티션 — 상한 형상에서는 전부 실재한다. 상한 아래 형상(BelowCap)만
\* 없는 파티션의 기저(Phantom)가 창에 남는다 (판정 T4 · 「없는 파티션 값의 처분」 말미).
WinParts == IF BelowCap THEN {Phantom} ELSE {}
BaseParts == Parts \cup WinParts
FrVals  == Frames \cup {Junk}
VpnVals == Vpns \cup {NoVpn}
P0 == CHOOSE p \in Parts : TRUE
S0 == CHOOSE s \in Slots : TRUE
X0 == CHOOSE x \in Vpns : TRUE
\* 없는 파티션 값이 가드를 잃었을 때 닿는 실재 파티션 — 필드를 partW 비트로 자르는 배선.
Alias == P0
Eff(p) == IF p \in Parts THEN p ELSE Alias

(***************************************************************************)
(* 버스 기입 — 필드가 고른 레코드. 쓰지 않는 필드는 채움 값이고 속성은     *)
(* 언제나 kind 를 먼저 본다.                                               *)
(*   vpn    기저 p 의 XLATE_ENTRY_VPN — 값 x                               *)
(*   frame  기저 p 의 XLATE_ENTRY_FRAME — 값 f (권한은 프레임 토큰에 접힌다) *)
(*   commit 기저 p 의 XLATE_ENTRY_COMMIT — V 비트 v · `[27:0]` 비0 r        *)
(*          (HostIndex 대안에서만 호스트가 지목한 칸 i)                     *)
(*   vpnhi  기저 p 의 XLATE_ENTRY_VPN_HI — 비0 r                            *)
(*   rsvw   기저 p 의 예약-엄격 28 워드 중 하나 (+0x10..+0x7C — 처분이 같다) *)
(*   flush  XLATE_FLUSH — 파티션 값 p(없는 값 Phantom 포함) · 예약 `[31:8]` 비0 r *)
(*   mclr   XLATE_MISS_CLEAR — `[0]` 을 v 에 · 예약 `[31:1]` 비0 을 r 에    *)
(*   ro     RO 세 워드(`0xE04`–`0xE0C`) 중 하나의 쓰기                      *)
(***************************************************************************)
Wr(k, p, x, f, i, b, r) == [kind |-> k, p |-> p, x |-> x, f |-> f, i |-> i, v |-> b, r |-> r]
NoWrite == Wr("none", P0, X0, Junk, S0, FALSE, FALSE)
HostSlots == IF HostIndex THEN Slots ELSE {S0}
BaseKinds == {"vpn", "frame", "commit", "vpnhi", "rsvw"}
VpnWrites    == {Wr("vpn", p, x, Junk, S0, FALSE, FALSE) : p \in BaseParts, x \in Vpns}
FrameWrites  == {Wr("frame", p, X0, f, S0, FALSE, FALSE) : p \in BaseParts, f \in Frames}
CommitWrites == {Wr("commit", p, X0, Junk, i, b, r) :
                    p \in BaseParts, i \in HostSlots, b \in BOOLEAN, r \in BOOLEAN}
VpnHiWrites  == {Wr("vpnhi", p, X0, Junk, S0, FALSE, r) : p \in BaseParts, r \in BOOLEAN}
RsvwWrites   == {Wr("rsvw", p, X0, Junk, S0, FALSE, FALSE) : p \in BaseParts}
FlushWrites  == {Wr("flush", q, X0, Junk, S0, FALSE, r) : q \in Parts \cup {Phantom}, r \in BOOLEAN}
MclrWrites   == {Wr("mclr", P0, X0, Junk, S0, b, r) : b \in BOOLEAN, r \in BOOLEAN}
RoWrites     == {Wr("ro", P0, X0, Junk, S0, FALSE, FALSE)}
Writes == VpnWrites \cup FrameWrites \cup CommitWrites \cup VpnHiWrites \cup RsvwWrites
          \cup FlushWrites \cup MclrWrites \cup RoWrites

\* 처분 — 그 스텝에 버스가 수락한 기입이 무엇이 됐는가.
\*   none 수락 없음 · hold 버스 정지(수락하지 않고 잡아 둠) · stage 스테이징 · commit 커밋 ·
\*   flush flush 실행 · absorb 수락됐는데 아무 일도 없음(조용한 흡수) · clear 미적중 sticky
\*   해제 · noop `0xE10` `[0]`=0 (W1C 의 0 — 흡수가 아니다).
\*   거절 — ephantom(없는 파티션 기저 · 어느 워드든) · rsvw(예약-엄격 워드) · pair(FRAME ·
\*   VPN_HI 의 짝 불일치) · vhrsv(VPN_HI 비0) · novpn(VPN 없는 COMMIT) · base(래치와 다른
\*   기저의 COMMIT) · crsv(COMMIT `[27:0]` 비0) · nofr(FRAME 유효 없는 V=1) · phantom(없는
\*   파티션 값 flush) · rsv(flush 예약) · refused(하류 거부를 거절로 처분) · mrsv(`0xE10`
\*   예약) · ro(RO 쓰기).
Rejects == {"ephantom", "rsvw", "pair", "vhrsv", "novpn", "base", "crsv", "nofr",
            "phantom", "rsv", "refused", "mrsv", "ro"}
Reasons == {"none", "hold", "stage", "commit", "flush", "absorb", "clear", "noop"} \cup Rejects

\* 증인용 스텝 사건 — 전건 도달성의 표식 (sticky 아님). 상태 술어로 적을 수 없는 것만.
Events == {"newFr", "kill", "evict", "flushLive", "flushOther",
           "clrLive", "zeroLive", "clrStall", "dataHeld"}

Ent  == [vpn : VpnVals, fr : FrVals, v : BOOLEAN]
Stg  == [vv : BOOLEAN, fv : BOOLEAN, p : Parts, vpn : VpnVals, fr : FrVals]
Blank   == [vpn |-> NoVpn, fr |-> Junk, v |-> FALSE]
EmptyStg == [vv |-> FALSE, fv |-> FALSE, p |-> P0, vpn |-> NoVpn, fr |-> Junk]
NoLate  == [on |-> FALSE, q |-> P0, s |-> S0, vpn |-> NoVpn, fr |-> Junk]
NoStall == [on |-> FALSE, p |-> P0, vpn |-> X0]

VARIABLES
    tbl,     \* [Parts -> [Slots -> Ent]] — 장치 안 칸 (가시성: 채움 슬롯 + 저장 블록을 접은 것)
    stg,     \* 장치의 스테이징 — VPN 유효 · FRAME 유효 · 래치 파티션 · VPN · 프레임
    busy,    \* [Parts -> BOOLEAN] — 그 파티션 채움 슬롯 점유 (= XlateStore install.ready 하강)
    held,    \* 버스가 잡아 둔 COMMIT (mmio ready = 0). NoWrite = 버스 한가
    late,    \* commit_whole 을 지웠을 때만 — 다음 에지에 앉을 VPN · 프레임
    mstall,  \* 미적중 정지 — [on, p, vpn]
    msticky, \* 미적중 sticky (XLATE_STATUS [1])
    cs,      \* 유령 — *정본*의 스테이징. 수락된 기입 열에 정본 (f) 를 그대로 적용한 것이다.
             \* 어느 가드도 읽지 않고 속성의 참 쪽만 읽는다 (검사 어휘로 지상 진리를 적지 않는다)
    stale,   \* 유령 — 정본 VPN 유효가 *flush 로* 내려간 뒤 VPN 이 다시 오지 않았다 (판정 T5)
    fstale,  \* 유령 — 마지막 정본 FRAME 뒤 VPN · VPN_HI 가 유효 프레임을 내렸다 (묵은 프레임 존재)
    acc,     \* 보조 — 이 스텝에 버스가 수락한 기입. NoWrite = 수락 없음
    why,     \* 보조 — 그 기입의 처분 (Reasons)
    loud,    \* 보조 — 이 스텝이 FAULT_STATUS [6] 을 발화했는가 (펄스)
    ev       \* 보조 — 이 스텝의 증인 사건

vars == <<tbl, stg, busy, held, late, mstall, msticky, cs, stale, fstale, acc, why, loud, ev>>
\* 대형 cfg 의 VIEW — 한 스텝짜리 보조 넷(acc · why · loud · ev)을 접는다. 어느 동작의 가드도
\* 갱신도 그 넷을 프라임 없이 읽지 않으므로 넷만 다른 두 상태의 후속은 같다. 대형 cfg 가 거는
\* 행동 속성은 넷을 프라임(전이)으로만 읽고, TLC 는 이미 본 VIEW 로 가는 전이에도 행동 속성을
\* 검사한다 (W2 XlateObs 탐침 실측 2026-10-12). 넷을 상태로 읽는 증인은 VIEW 아래 돌리지 않는다.
StateView == <<tbl, stg, busy, held, late, mstall, msticky, cs, stale, fstale>>

TypeOK ==
    /\ tbl \in [Parts -> [Slots -> Ent]]
    /\ stg \in Stg
    /\ busy \in [Parts -> BOOLEAN]
    /\ held \in Writes \cup {NoWrite}
    /\ late \in [on : BOOLEAN, q : Parts, s : Slots, vpn : VpnVals, fr : FrVals]
    /\ mstall \in [on : BOOLEAN, p : Parts, vpn : Vpns]
    /\ msticky \in BOOLEAN
    /\ cs \in Stg
    /\ stale \in BOOLEAN /\ fstale \in BOOLEAN
    /\ acc \in Writes \cup {NoWrite}
    /\ why \in Reasons
    /\ loud \in BOOLEAN
    /\ ev \in SUBSET Events

Init ==
    /\ tbl = [q \in Parts |-> [s \in Slots |-> Blank]]
    /\ stg = EmptyStg
    /\ busy = [q \in Parts |-> FALSE]
    /\ held = NoWrite
    /\ late = NoLate
    /\ mstall = NoStall
    /\ msticky = FALSE
    /\ cs = EmptyStg
    /\ stale = FALSE /\ fstale = FALSE
    /\ acc = NoWrite /\ why = "none" /\ loud = FALSE /\ ev = {}

Resident(t, p, x) == \E s \in Slots : t[p][s].v /\ t[p][s].vpn = x

(***************************************************************************)
(* 정본의 적법성 — 가드와 무관하다. 유령 cs · stale 만 읽는다.             *)
(***************************************************************************)
SpecAddrOK(w)   == w.p \in Parts /\ cs.vv /\ cs.p = w.p          \* 주소 · 스테이징 상태
SpecCommitOK(w) == SpecAddrOK(w) /\ ~w.r /\ (w.v => cs.fv)       \* + 데이터 필드
SpecFlOK(w)     == w.p \in Parts /\ ~w.r
SpecMcOK(w)     == ~w.r
SpecMalformed(w) ==
    \/ (w.kind \in BaseKinds /\ w.p \notin Parts)
    \/ w.kind = "rsvw"
    \/ (w.kind = "frame" /\ ~SpecAddrOK(w))
    \/ (w.kind = "vpnhi" /\ (~SpecAddrOK(w) \/ w.r))
    \/ (w.kind = "commit" /\ ~SpecCommitOK(w))
    \/ (w.kind = "flush" /\ ~SpecFlOK(w))
    \/ (w.kind = "mclr" /\ ~SpecMcOK(w))
    \/ w.kind = "ro"

(***************************************************************************)
(* 장치의 판정 — 가드 의존. RTL 식(RTL 지도의 XlateStaging 식)의 항과 일대일이다. *)
(***************************************************************************)
\* 없는 파티션 기저 — 어느 워드든 가장 먼저 본다 (첫 연언 BelowCap 은 상한 형상에서 곧장 끊는다).
DevEntPhantom(w) == BelowCap /\ w.kind \in BaseKinds /\ w.p \notin Parts /\ On("ent_part_exists")
DevPair(w)   == (stg.vv /\ stg.p = Eff(w.p)) \/ ~On("frame_pair_check")
DevNoVpn     == ~stg.vv /\ On("commit_needs_vpn")
DevBase(w)   == stg.p # Eff(w.p) /\ On("commit_base_match")
DevCmRsv(w)  == w.r /\ On("commit_rsv_strict")
DevNoFr(w)   == w.v /\ ~stg.fv /\ On("commit_needs_frame")
DevDataBad(w) == DevCmRsv(w) \/ DevNoFr(w)
DevPhantom(w) == w.p \notin Parts /\ On("flush_part_exists")
DevRsvBad(w)  == w.r /\ On("flush_rsv_strict")
DevMcRsvBad(w) == w.r /\ On("mclr_rsv_strict")
DevMcFires(w) == w.v \/ ~On("mclr_needs_one")
\* 정지 판정 needReady — 주소 · 스테이징 상태로 적법한 COMMIT. RefuseDomain = "full" 은
\* 데이터 사유까지 보는 기각 대안이다 (그 판은 데이터 사유 COMMIT 을 정지 없이 곧장 거절한다).
\* RefuseDomain = "kind" 는 주소 · 상태 항을 빼는 기각 대안이다 (그 판은 주소 · 상태 사유 COMMIT 을
\* 정지 뒤 Retry 에서 거절한다).
DevAddrOK(w) == w.kind = "commit" /\ ~DevEntPhantom(w) /\ ~DevNoVpn /\ ~DevBase(w)
Refused(w)   == /\ busy[Eff(w.p)]
                /\ CASE RefuseDomain = "addrstate" -> DevAddrOK(w)
                     [] RefuseDomain = "full"      -> DevAddrOK(w) /\ ~DevDataBad(w)
                     [] RefuseDomain = "kind"      -> w.kind = "commit"

\* COMMIT 이 앉을 칸 — 장치가 고른다. 같은 파티션에 같은 VPN 의 유효 칸이 있으면 그 칸이다
\* (commit_replaces_vpn — 태그 탐색). 아니면 그 파티션의 아무 칸(희생 칸 — 교체 정책은 형상이라
\* 비결정으로 과근사한다). HostIndex 대안은 호스트가 지목한 칸이다.
Targets(w) ==
    LET ep   == Eff(w.p)
        same == {s \in Slots : tbl[ep][s].v /\ tbl[ep][s].vpn = stg.vpn}
    IN  IF HostIndex THEN {<<ep, w.i>>}
        ELSE IF On("commit_replaces_vpn") /\ same # {} THEN {<<ep, s>> : s \in same}
        ELSE IF On("evict_in_partition") THEN {<<ep, s>> : s \in Slots}
        ELSE Parts \X Slots

(***************************************************************************)
(* 수락된 기입 하나의 처분 — 수락 경로 둘(Present · Retry)이 이 하나로     *)
(* 환원된다. 처분 d 를 먼저 정하고 갱신은 d 의 함수다. 거절된 기입은 한   *)
(* 비트도 움직이지 않는다 (표 · 스테이징 · 하류). rt = Retry 의 수락인가.  *)
(***************************************************************************)
Dispose(w, rt) ==
    LET ep  == Eff(w.p)
        rej == CASE DevEntPhantom(w)                                   -> "ephantom"
                 [] w.kind = "rsvw"   /\ On("rsvw_rejected")           -> "rsvw"
                 [] w.kind = "frame"  /\ ~DevPair(w)                   -> "pair"
                 [] w.kind = "vpnhi"  /\ w.r /\ On("vpnhi_strict")     -> "vhrsv"
                 [] w.kind = "vpnhi"  /\ ~DevPair(w)                   -> "pair"
                 [] w.kind = "commit" /\ DevNoVpn                      -> "novpn"
                 [] w.kind = "commit" /\ DevBase(w)                    -> "base"
                 [] w.kind = "flush"  /\ DevPhantom(w)                 -> "phantom"
                 [] w.kind = "flush"  /\ DevRsvBad(w)                  -> "rsv"
                 [] w.kind = "mclr"   /\ DevMcRsvBad(w)                -> "mrsv"
                 [] w.kind = "ro"     /\ On("ro_rejected")             -> "ro"
                 [] OTHER                                              -> "none"
        d   == IF rej # "none" THEN rej
               ELSE CASE w.kind = "commit" /\ busy[ep] /\ ~DevDataBad(w) ->
                            \* stall 은 Present 가 잡아 두므로 여기 오지 않는다
                            (IF Refusal = "reject" THEN "refused" ELSE "absorb")
                      [] w.kind = "commit" /\ DevCmRsv(w) -> "crsv"
                      [] w.kind = "commit" /\ DevNoFr(w)  -> "nofr"
                      [] w.kind = "commit" -> (IF On("commit_fires") THEN "commit" ELSE "absorb")
                      [] w.kind \in {"vpn", "frame", "vpnhi"} -> "stage"
                      [] w.kind = "flush"  -> (IF On("flush_fires") THEN "flush" ELSE "absorb")
                      [] w.kind = "mclr"   ->
                            (IF DevMcFires(w)
                               THEN (IF On("mclr_fires") THEN "clear" ELSE "absorb")
                               ELSE "noop")
                      [] OTHER -> "absorb"     \* rsvw · ro 가 여기 오는 것은 가드를 지운 판뿐
        newV == IF On("commit_v_carried") THEN w.v ELSE TRUE
        tgt  == IF w.p \in Parts THEN w.p ELSE Alias
        F    == IF On("flush_scoped") THEN {tgt} ELSE Parts
        flushEnt(e) == [v |-> FALSE,
                        vpn |-> IF On("flush_valid_only") THEN e.vpn ELSE NoVpn,
                        fr  |-> IF On("flush_valid_only") THEN e.fr  ELSE Junk]
        dropStg == /\ d = "flush" /\ On("flush_drops_staging")
                   \* 래치 비교는 flush 워드의 필드 그 자체다 (RTL flushDrop 의 partField == stgPart) —
                   \* 표를 지우는 범위 F(flush_scoped)와는 다른 항이다.
                   /\ CASE StgAlt = "flush"   -> stg.p = tgt
                        [] StgAlt = "global"  -> TRUE
                        [] StgAlt = "consume" -> FALSE
        \* frame_stages_only 를 지운 판 — FRAME 이 래치 (파티션, VPN) 의 산 칸을 곧장 덮는다.
        wthru == [q \in Parts |-> [s \in Slots |->
                    IF q = ep /\ tbl[q][s].v /\ tbl[q][s].vpn = stg.vpn
                      THEN [tbl[q][s] EXCEPT !.fr = w.f] ELSE tbl[q][s]]]
        \* 정본 스테이징의 다음 값 — 수락된 기입 열에 정본 (f) 를 적용한다.
        csFl == d = "flush" /\ SpecFlOK(w) /\ cs.p = w.p
        csN  == CASE w.kind = "vpn" /\ w.p \in Parts ->
                        [vv |-> TRUE, fv |-> FALSE, p |-> w.p, vpn |-> w.x, fr |-> cs.fr]
                  [] w.kind = "frame" /\ SpecAddrOK(w) -> [cs EXCEPT !.fv = TRUE, !.fr = w.f]
                  [] w.kind = "vpnhi" /\ SpecAddrOK(w) /\ ~w.r -> [cs EXCEPT !.fv = FALSE]
                  [] csFl -> [cs EXCEPT !.vv = FALSE, !.fv = FALSE]
                  [] OTHER -> cs
        dropsFr == (w.kind = "vpn" /\ w.p \in Parts) \/ (w.kind = "vpnhi" /\ SpecAddrOK(w) /\ ~w.r)
    IN  \E t \in (IF d = "commit" THEN Targets(w) ELSE {<<P0, S0>>}) :
        LET old  == tbl[t[1]][t[2]]
            nt   == CASE d = "stage" /\ w.kind = "frame" /\ ~On("frame_stages_only") -> wthru
                      [] d = "commit" ->
                            (IF On("commit_whole")
                               THEN [tbl EXCEPT ![t[1]][t[2]] = [vpn |-> stg.vpn, fr |-> stg.fr, v |-> newV]]
                               ELSE [tbl EXCEPT ![t[1]][t[2]].v = newV])
                      [] d = "flush" ->
                            [q \in Parts |-> IF q \in F THEN [s \in Slots |-> flushEnt(tbl[q][s])]
                                             ELSE tbl[q]]
                      [] OTHER -> tbl
        IN
        /\ tbl' = nt
        /\ late' = IF d = "commit" /\ ~On("commit_whole")
                     THEN [on |-> TRUE, q |-> t[1], s |-> t[2], vpn |-> stg.vpn, fr |-> stg.fr]
                     ELSE late
        /\ stg' = CASE d = "stage" /\ w.kind = "vpn" ->
                         [vv |-> TRUE, fv |-> (IF On("vpn_drops_frame") THEN FALSE ELSE stg.fv),
                          p |-> ep, vpn |-> w.x, fr |-> stg.fr]
                    [] d = "stage" /\ w.kind = "frame" -> [stg EXCEPT !.fv = TRUE, !.fr = w.f]
                    [] d = "stage" /\ w.kind = "vpnhi" ->
                         (IF On("vpn_drops_frame") THEN [stg EXCEPT !.fv = FALSE] ELSE stg)
                    [] dropStg -> [stg EXCEPT !.vv = FALSE, !.fv = FALSE]
                    [] d = "commit" /\ StgAlt = "consume" -> [stg EXCEPT !.vv = FALSE, !.fv = FALSE]
                    [] OTHER -> stg
        /\ busy' = CASE d = "commit" -> [busy EXCEPT ![ep] = TRUE]
                     [] d = "flush"  -> [q \in Parts |-> IF q \in F THEN FALSE ELSE busy[q]]
                     [] OTHER        -> busy
        \* 미적중 정지는 정지한 (파티션, VPN) 이 표에서 적중하게 되는 커밋 에지에 풀린다
        \* (E.3 2항 · 결과 (d)). 해제(0xE10)는 정지에 닿지 않는다 — mclr_keeps_stall 을 지운 판만.
        /\ mstall' = IF \/ (mstall.on /\ d = "commit" /\ Resident(nt, mstall.p, mstall.vpn))
                        \/ (d = "clear" /\ ~On("mclr_keeps_stall"))
                       THEN NoStall ELSE mstall
        \* set 은 정지 레벨이고 발화가 해제를 이긴다 (StickyFault 규약 — 정지 중 해제 유실).
        /\ msticky' = (mstall.on \/ (msticky /\ d # "clear"))
        /\ cs' = csN
        /\ stale' = CASE w.kind = "vpn" /\ w.p \in Parts -> FALSE
                      [] csFl /\ cs.vv -> TRUE
                      [] OTHER -> stale
        /\ fstale' = CASE w.kind = "frame" /\ SpecAddrOK(w) -> FALSE
                       [] dropsFr -> fstale \/ cs.fv
                       [] OTHER -> fstale
        /\ acc' = w
        /\ why' = d
        /\ loud' = (d \in Rejects /\ On("reject_loud"))
        /\ ev' = (IF d = "commit" /\ w.v /\ Resident(tbl, ep, stg.vpn)
                     /\ \E s \in Slots : tbl[ep][s].v /\ tbl[ep][s].vpn = stg.vpn /\ tbl[ep][s].fr # stg.fr
                    THEN {"newFr"} ELSE {})
               \cup (IF d = "commit" /\ ~w.v /\ Resident(tbl, ep, stg.vpn) THEN {"kill"} ELSE {})
               \cup (IF d = "commit" /\ old.v /\ old.vpn # stg.vpn THEN {"evict"} ELSE {})
               \cup (IF d = "flush" /\ w.p \in Parts /\ \E s \in Slots : tbl[w.p][s].v
                       THEN {"flushLive"} ELSE {})
               \cup (IF d = "flush" /\ w.p \in Parts
                        /\ \E q \in Parts \ {w.p}, s \in Slots : tbl[q][s].v
                       THEN {"flushOther"} ELSE {})
               \* 아래 넷은 입력(정본 적법성)으로 적는다 — 장치 처분과 무관한 전건 표식.
               \cup (IF w.kind = "mclr" /\ w.v /\ ~w.r /\ msticky /\ ~mstall.on THEN {"clrLive"} ELSE {})
               \cup (IF w.kind = "mclr" /\ ~w.v /\ ~w.r /\ msticky /\ ~mstall.on THEN {"zeroLive"} ELSE {})
               \cup (IF w.kind = "mclr" /\ w.v /\ ~w.r /\ mstall.on THEN {"clrStall"} ELSE {})
               \cup (IF rt /\ d \in {"crsv", "nofr"} THEN {"dataHeld"} ELSE {})

(***************************************************************************)
(* 호스트가 버스에 기입 하나를 제시한다. 버스는 한 번에 하나다 — 잡혀 있는 *)
(* 기입이 있으면 다음 기입은 제시되지 않는다. Refusal = "stall" 이고 하류가 *)
(* 거부하면 수락하지 않고 잡아 둔다 (정지 중 무효과).                      *)
(***************************************************************************)
Present(w) ==
    /\ held = NoWrite
    /\ ~late.on
    /\ IF Refusal = "stall" /\ Refused(w)
         THEN /\ held' = w
              /\ acc' = NoWrite /\ why' = "hold" /\ loud' = FALSE /\ ev' = {}
              /\ UNCHANGED <<tbl, stg, busy, late, mstall, msticky, cs, stale, fstale>>
         ELSE /\ UNCHANGED held
              /\ Dispose(w, FALSE)

\* 잡혀 있던 COMMIT 이 하류가 비는 순간 수락된다 — 같은 기입, 단일 에지. 데이터 사유는
\* 여기서(수락 사이클) 거절된다.
Retry ==
    /\ held # NoWrite
    /\ ~late.on
    /\ ~busy[Eff(held.p)]
    /\ held' = NoWrite
    /\ Dispose(held, TRUE)

\* 채움 슬롯의 저장 커밋 — 호스트 조치 없이, 버스와 독립으로 일어난다. 다른 정지(미적중
\* 정지)와도 독립이다 — stall_independent 를 지운 판만 미적중 정지 동안 막힌다.
Drain(p) ==
    /\ busy[p]
    /\ ~late.on
    /\ (~mstall.on \/ On("stall_independent"))
    /\ busy' = [busy EXCEPT ![p] = FALSE]
    /\ acc' = NoWrite /\ why' = "none" /\ loud' = FALSE /\ ev' = {}
    /\ UNCHANGED <<tbl, stg, held, late, mstall, msticky, cs, stale, fstale>>

\* commit_whole 을 지운 판에서만 열린다 — 커밋의 둘째 에지 (VPN · 프레임이 V 뒤에 앉는다).
LateFr ==
    /\ late.on
    /\ tbl' = [tbl EXCEPT ![late.q][late.s] = [@ EXCEPT !.vpn = late.vpn, !.fr = late.fr]]
    /\ late' = NoLate
    /\ mstall' = IF mstall.on /\ Resident(tbl', mstall.p, mstall.vpn) THEN NoStall ELSE mstall
    /\ acc' = NoWrite /\ why' = "none" /\ loud' = FALSE /\ ev' = {}
    /\ UNCHANGED <<stg, busy, held, msticky, cs, stale, fstale>>

\* evict_on_commit_only 를 지운 판에서만 열린다 — 자발 축출 (시간 · 배경 작업).
Decay(q, s) ==
    /\ ~On("evict_on_commit_only")
    /\ ~late.on
    /\ tbl[q][s].v
    /\ tbl' = [tbl EXCEPT ![q][s].v = FALSE]
    /\ acc' = NoWrite /\ why' = "none" /\ loud' = FALSE /\ ev' = {}
    /\ UNCHANGED <<stg, busy, held, late, mstall, msticky, cs, stale, fstale>>

\* 조회 요청 하나가 (p, x) 에서 미적중해 정지한다 — 버스와 독립인 다른 포트다. 정지 중에는
\* 파이프 전체가 서므로 새 조회는 오지 않는다. 적중 조회는 이 모델의 어떤 상태도 움직이지
\* 않으므로 적지 않는다 (조회는 칸도 교체 상태도 쓰지 않는다 — 결과 (g)).
Lookup(p, x) ==
    /\ ~mstall.on
    /\ ~late.on
    /\ ~Resident(tbl, p, x)
    /\ mstall' = [on |-> TRUE, p |-> p, vpn |-> x]
    /\ msticky' = TRUE
    /\ acc' = NoWrite /\ why' = "none" /\ loud' = FALSE /\ ev' = {}
    /\ UNCHANGED <<tbl, stg, busy, held, late, cs, stale, fstale>>

Next ==
    \/ \E w \in Writes : Present(w)
    \/ Retry
    \/ \E p \in Parts : Drain(p)
    \/ LateFr
    \/ \E q \in Parts, s \in Slots : Decay(q, s)
    \/ \E p \in Parts, x \in Vpns : Lookup(p, x)

Spec == Init /\ [][Next]_vars

\* 정지가 호스트 조치 없이 풀린다는 의무 — 공정성은 *장치* 동작 둘에만 건다.
LiveSpec ==
    /\ Spec
    /\ WF_vars(Retry)
    /\ \A p \in Parts : WF_vars(Drain(p))

\* 대조군 — Drain 의 공정성을 뺀다.
LiveSpecNoDrain ==
    /\ Spec
    /\ WF_vars(Retry)

(***************************************************************************)
(* 가드 속성 — 행위 속성. acc' 가 그 스텝의 원인, why' · loud' 가 처분.     *)
(* 전건의 적법성은 정본(유령 cs · stale · fstale)이지 장치 판정이 아니다.  *)
(***************************************************************************)

\* frame_stages_only — VPN · FRAME · VPN_HI 기입은 표에 닿지 않는다.
Prop_StagesOnly ==
    [][ acc'.kind \in {"vpn", "frame", "vpnhi"} => tbl' = tbl ]_vars

\* commit_fires — 정본이 적법하다고 보는 COMMIT 이 수락되면 커밋된다 (흡수 · 거절 없음).
Prop_CommitCommits ==
    [][ (acc'.kind = "commit" /\ SpecCommitOK(acc')) => why' = "commit" ]_vars

\* commit_base_match — 래치 파티션과 다른 기저의 COMMIT 은 거절, 표 불변.
Prop_BaseMismatchRejected ==
    [][ (acc'.kind = "commit" /\ acc'.p \in Parts /\ cs.vv /\ cs.p # acc'.p)
          => (why' \in Rejects /\ tbl' = tbl) ]_vars

\* commit_needs_vpn — reset 뒤 VPN 이 한 번도 오지 않은 스테이징의 COMMIT 은 거절, 표 불변.
\* (flush 를 건넌 빈 스테이징은 flush_drops_staging 의 몫 — 전건 ~stale.)
Prop_NoVpnRejected ==
    [][ (acc'.kind = "commit" /\ ~cs.vv /\ ~stale) => (why' \in Rejects /\ tbl' = tbl) ]_vars

\* commit_whole — 적법한 V=1 커밋 스텝 뒤 (VPN, 프레임, 유효) 가 한 칸에 함께 서 있다.
Prop_CommitWhole ==
    [][ (acc'.kind = "commit" /\ SpecCommitOK(acc') /\ acc'.v /\ why' = "commit")
          => \E q \in Parts, s \in Slots : tbl'[q][s] = [vpn |-> cs.vpn, fr |-> cs.fr, v |-> TRUE] ]_vars

\* commit_v_carried — 결과 (b) · HIU-2 의 V=0 축: 적법한 V=0 커밋 뒤 그 (파티션, VPN) 은
\* 어느 칸에서도 유효하지 않다.
Prop_V0Misses ==
    [][ (acc'.kind = "commit" /\ SpecCommitOK(acc') /\ ~acc'.v /\ why' = "commit")
          => ~Resident(tbl', acc'.p, cs.vpn) ]_vars

\* commit_needs_frame — FRAME 이 한 번도 서지 않은 VPN 위의 V=1 COMMIT 은 거절, 표 불변.
Prop_CommitNeedsFrame ==
    [][ (acc'.kind = "commit" /\ acc'.v /\ ~cs.fv /\ ~fstale) => (why' \in Rejects /\ tbl' = tbl) ]_vars

\* vpn_drops_frame — VPN · VPN_HI 재기입이 내린 *묵은* 프레임 위의 V=1 COMMIT 은 거절, 표 불변.
Prop_VpnDropsFrame ==
    [][ (acc'.kind = "commit" /\ acc'.v /\ ~cs.fv /\ fstale) => (why' \in Rejects /\ tbl' = tbl) ]_vars

\* frame_pair_check — 래치 파티션 기저가 아니거나 VPN 유효가 없는(reset 뒤) FRAME · VPN_HI 는
\* 거절이고 스테이징 · 표 불변.
Prop_FramePairRejected ==
    [][ (acc'.kind \in {"frame", "vpnhi"} /\ ~stale /\ ~SpecAddrOK(acc'))
          => (why' \in Rejects /\ stg' = stg /\ tbl' = tbl) ]_vars

\* vpnhi_strict — 비0 VPN_HI 는 거절이고 스테이징 불변.
Prop_VpnHiStrict ==
    [][ (acc'.kind = "vpnhi" /\ acc'.r) => (why' \in Rejects /\ stg' = stg) ]_vars

\* rsvw_rejected — 예약-엄격 워드 쓰기는 거절이고 아무것도 움직이지 않는다.
Prop_RsvwRejected ==
    [][ acc'.kind = "rsvw" => (why' \in Rejects /\ tbl' = tbl /\ stg' = stg) ]_vars

\* commit_rsv_strict — COMMIT `[27:0]` 비0 은 거절, 표 불변.
Prop_CommitRsvRejected ==
    [][ (acc'.kind = "commit" /\ acc'.r) => (why' \in Rejects /\ tbl' = tbl) ]_vars

\* commit_replaces_vpn — HIU-4 · 결과 (a): 같은 (파티션, VPN) 에 유효한 칸은 많아야 하나다.
Inv_AtMostOneValidPerVpn ==
    \A p \in Parts, x \in Vpns :
        Cardinality({s \in Slots : tbl[p][s].v /\ tbl[p][s].vpn = x}) =< 1

\* evict_in_partition — 결과 (c): COMMIT 은 자기 파티션 밖의 칸을 건드리지 않는다.
Prop_CommitScoped ==
    [][ (acc'.kind = "commit" /\ acc'.p \in Parts) => \A q \in Parts \ {acc'.p} : tbl'[q] = tbl[q] ]_vars

\* evict_on_commit_only — 결과 (h): 표를 움직이는 것은 커밋과 flush 둘뿐이다 (자발 축출 없음).
Prop_TableByDoor ==
    [][ tbl' # tbl => why' \in {"commit", "flush"} ]_vars

\* stall_independent — 하류 정지는 호스트 조치 없이 풀린다 (LiveSpec 아래 · 미적중 정지와 독립).
Prop_StallEnds ==
    (held # NoWrite) ~> (held = NoWrite)

\* flush_fires — 적법한 flush 뒤 그 파티션의 칸은 전부 무효다.
Prop_FlushClears ==
    [][ (acc'.kind = "flush" /\ SpecFlOK(acc')) => \A s \in Slots : ~tbl'[acc'.p][s].v ]_vars

\* flush_scoped — 실재 파티션 p 의 flush 는 다른 파티션을 건드리지 않는다.
Prop_FlushScoped ==
    [][ (acc'.kind = "flush" /\ acc'.p \in Parts) => \A q \in Parts \ {acc'.p} : tbl'[q] = tbl[q] ]_vars

\* flush_valid_only — flush 는 데이터(VPN · 프레임)를 지우지 않는다.
Prop_FlushKeepsData ==
    [][ acc'.kind = "flush" =>
          \A q \in Parts, s \in Slots : tbl'[q][s].fr = tbl[q][s].fr /\ tbl'[q][s].vpn = tbl[q][s].vpn ]_vars

\* flush_part_exists — 없는 파티션 값의 flush 는 거절되고 표는 불변.
Prop_PhantomRejected ==
    [][ (acc'.kind = "flush" /\ acc'.p \notin Parts) => (why' \in Rejects /\ tbl' = tbl) ]_vars

\* flush_rsv_strict — 예약 `[31:8]` 비0 flush 는 거절되고 표는 불변.
Prop_RsvRejected ==
    [][ (acc'.kind = "flush" /\ acc'.r) => (why' \in Rejects /\ tbl' = tbl) ]_vars

\* reject_loud — 거절은 전부 FAULT_STATUS [6] 을 발화한다.
Prop_RejectLoud ==
    [][ why' \in Rejects => loud' ]_vars

\* mclr_fires — 적법한 `[0]`=1 해제는 (정지가 없으면) 미적중 sticky 를 내린다.
Prop_MclrClears ==
    [][ (acc'.kind = "mclr" /\ acc'.v /\ SpecMcOK(acc') /\ ~mstall.on) => ~msticky' ]_vars

\* mclr_needs_one — `[0]`=0 기입은 sticky 를 움직이지 않는다.
Prop_MclrZeroKeeps ==
    [][ (acc'.kind = "mclr" /\ ~acc'.v) => msticky' = msticky ]_vars

\* mclr_rsv_strict — 예약 `[31:1]` 비0 해제는 거절되고 sticky 는 불변.
Prop_MclrRsvRejected ==
    [][ (acc'.kind = "mclr" /\ acc'.r) => (why' \in Rejects /\ msticky' = msticky) ]_vars

\* mclr_keeps_stall — 해제는 미적중 정지에 닿지 않는다.
Prop_MclrKeepsStall ==
    [][ acc'.kind = "mclr" => mstall' = mstall ]_vars

\* ro_rejected — RO 오프셋 쓰기는 거절되고 아무것도 움직이지 않는다.
Prop_RoRejected ==
    [][ acc'.kind = "ro"
          => (/\ why' \in Rejects
              /\ tbl' = tbl /\ stg' = stg /\ mstall' = mstall /\ msticky' = msticky) ]_vars

\* flush_drops_staging — flush(임대 회전 ⑵)를 건넌 스테이징 위의 FRAME · VPN_HI · COMMIT 은
\* 거절되고 표 · 스테이징 불변이다 (판정 T5 · (f) 일곱째 항 · `0xE00` 행).
Prop_FlushEndsStaging ==
    [][ (acc'.kind \in {"frame", "vpnhi", "commit"} /\ stale)
          => (why' \in Rejects /\ tbl' = tbl /\ stg' = stg) ]_vars

\* ent_part_exists — 없는 파티션 기저의 어느 워드든 거절이고 표 · 스테이징 불변.
Prop_EntPhantomRejected ==
    [][ (acc'.kind \in BaseKinds /\ acc'.p \notin Parts)
          => (why' \in Rejects /\ tbl' = tbl /\ stg' = stg) ]_vars

(***************************************************************************)
(* 가드 아님 — 고정 의미의 속성. 좋은 모델 cfg 와 대안 · 짝이 쓴다.        *)
(***************************************************************************)

\* 거절은 정본이 열거한 사유로만 — 적법한 기입이 fault 를 받는 일은 없다 (Refusal = "reject" 가 깬다).
Prop_RejectOnlyMalformed ==
    [][ why' \in Rejects => SpecMalformed(acc') ]_vars

\* [6] 은 거절에서만 발화한다 — 허위 fault 없음.
Prop_LoudOnlyOnReject ==
    [][ loud' => why' \in Rejects ]_vars

\* 정지 판정은 데이터 필드를 보지 않는다 — 주소 · 스테이징 상태로 적법한 COMMIT 은 하류 슬롯이
\* 빈 사이클에만 수락된다 (데이터 사유 거절도 그 수락 사이클이다). RefuseDomain = "full" 이 깬다.
Prop_StallDataBlind ==
    [][ (acc'.kind = "commit" /\ SpecAddrOK(acc')) => ~busy[acc'.p] ]_vars

\* 주소 · 스테이징 상태 사유는 기다리지 않는다 — 버스가 잡아 두는 COMMIT 은 정본이 주소 · 상태로
\* 적법하다고 보는 것뿐이다 (래치와 다른 기저 · VPN 없음 · 없는 기저는 정지 없이 곧장 거절).
\* 정지 중에는 버스가 기입 하나를 들고 있어 cs 가 움직이지 않으므로 잡는 스텝에서 재면 족하다.
\* RefuseDomain = "kind" 가 깬다.
Prop_AddrRejectNoWait ==
    [][ (held = NoWrite /\ held' # NoWrite) => SpecAddrOK(held') ]_vars

\* 정지 중에는 효과가 없다 — 잡는 스텝은 표 · 스테이징 · 하류 · 미적중 정지 · sticky 를 움직이지
\* 않고 `[6]` 도 세우지 않는다.
Prop_HoldInert ==
    [][ (held = NoWrite /\ held' # NoWrite)
          => (/\ tbl' = tbl /\ stg' = stg /\ busy' = busy
              /\ mstall' = mstall /\ msticky' = msticky /\ ~loud') ]_vars

\* 거절은 아무것도 움직이지 않는다 — 가드 속성은 각자 자기 축(표 · 스테이징)만 보므로, 하류 점유 ·
\* 미적중 정지 · sticky 까지 든 일반형이다.
Prop_RejectInert ==
    [][ why' \in Rejects
          => (/\ tbl' = tbl /\ stg' = stg /\ busy' = busy
              /\ mstall' = mstall /\ msticky' = msticky) ]_vars

\* 결과 (a) — 적법한 V=1 커밋 뒤 그 파티션에 (VPN, 프레임) 이 유효로 선다.
Prop_V1Hits ==
    [][ (acc'.kind = "commit" /\ SpecCommitOK(acc') /\ acc'.v)
          => \E s \in Slots : tbl'[acc'.p][s] = [vpn |-> cs.vpn, fr |-> cs.fr, v |-> TRUE] ]_vars

\* 부분 기입 상태가 유효해질 수 없다 — 유효한 칸의 VPN · 프레임은 호스트가 쓴 값이다.
Inv_ValidFrameWritten ==
    \A q \in Parts, s \in Slots : tbl[q][s].v => (tbl[q][s].fr # Junk /\ tbl[q][s].vpn # NoVpn)

\* 장치 스테이징이 정본 스테이징과 같다 — 좋은 모델에서 유령이 상태를 늘리지 않는 근거.
Inv_StgIsSpec == stg = cs

\* 판정 T5 의 범위 — 실재 파티션의 수락된 flush 는 다른 파티션을 래치한 스테이징을 건드리지
\* 않는다. 대안 StgAlt = "global" 이 깬다.
Prop_FlushStagingScoped ==
    [][ (acc'.kind = "flush" /\ why' = "flush" /\ acc'.p \in Parts /\ stg.p # acc'.p) => stg' = stg ]_vars

\* flush 가 내리는 것은 스테이징의 *유효* 둘뿐이고 래치 · VPN · 프레임 값은 남는다.
Prop_FlushStagingKeepsData ==
    [][ acc'.kind = "flush" => (stg'.p = stg.p /\ stg'.vpn = stg.vpn /\ stg'.fr = stg.fr) ]_vars

\* 판정 T4 의 격리 귀결 — 없는 파티션 기저의 COMMIT 은 실재 파티션의 칸을 움직이지 않는다.
Prop_EntNoAlias ==
    [][ (acc'.kind = "commit" /\ acc'.p \notin Parts) => tbl' = tbl ]_vars

\* 미적중이 살아 있는 동안 sticky 는 서 있다.
Inv_StallSticky ==
    mstall.on => msticky

\* 미적중 정지를 푸는 것은 정지한 (파티션, VPN) 을 상주하게 만드는 V=1 커밋뿐이다 — VPN · FRAME
\* 스테이징 · V=0 COMMIT · 다른 (파티션, VPN) 의 커밋은 풀지 않는다 (E.3 2항의 좁힘 · 결과 (d)).
Prop_StallOnlyByEntry ==
    [][ (mstall.on /\ ~mstall'.on)
          => (why' = "commit" /\ acc'.v /\ Resident(tbl', mstall.p, mstall.vpn)) ]_vars

\* E.3 2항 · 결과 (d) — 정지한 (파티션, VPN) 에 대한 적법한 V=1 커밋이 수락되면 정지가 풀린다.
Prop_StallReleasedByFill ==
    [][ (mstall.on /\ acc'.kind = "commit" /\ SpecCommitOK(acc') /\ acc'.v
         /\ acc'.p = mstall.p /\ cs.vpn = mstall.vpn) => ~mstall'.on ]_vars

\* 판정 4 — 「적법한 해제는 언제나 sticky 를 내린다」. 좋은 모델에서 반드시 반증된다.
Prop_ClearAlwaysLowers ==
    [][ (acc'.kind = "mclr" /\ acc'.v /\ SpecMcOK(acc')) => ~msticky' ]_vars

(***************************************************************************)
(* 위험 도달성 증인 — 좋은 모델에서 반드시 반증돼야 한다.                  *)
(***************************************************************************)

\* frame_stages_only — 래치 (파티션, VPN) 이 다른 프레임으로 산 동안 FRAME 이 수락된다.
Witness_NoFrameOverLive ==
    ~(acc.kind = "frame" /\ why = "stage"
      /\ \E s \in Slots : tbl[stg.p][s].v /\ tbl[stg.p][s].vpn = stg.vpn /\ tbl[stg.p][s].fr # acc.f)

\* commit_fires · commit_whole — 산 (파티션, VPN) 의 프레임을 바꾸는 커밋(대체)이 일어난다.
Witness_NoFrameChange == "newFr" \notin ev

\* commit_base_match — 래치와 다른 기저의 COMMIT 이 온다.
Witness_NoBaseMismatch == why # "base"

\* commit_needs_vpn — VPN 없는 COMMIT 이 온다.
Witness_NoVpnless == why # "novpn"

\* commit_v_carried — V=0 커밋이 산 항목을 무효화한다 (결과 (b) 의 전건).
Witness_NoKill == "kill" \notin ev

\* commit_needs_frame — FRAME 유효 없는 V=1 COMMIT 이 온다.
Witness_NoFramelessV1 == why # "nofr"

\* vpn_drops_frame — 묵은 프레임 위에 V=1 COMMIT 이 온다 (VPN · VPN_HI 가 유효 프레임을 내린 뒤).
Witness_NoStaleFrameCommit == ~(acc.kind = "commit" /\ acc.v /\ ~cs.fv /\ fstale)

\* frame_pair_check — 짝 불일치 FRAME · VPN_HI 가 온다.
Witness_NoPairMismatch == why # "pair"

\* vpnhi_strict — 비0 VPN_HI 가 온다.
Witness_NoVpnHiRsv == why # "vhrsv"

\* rsvw_rejected — 예약-엄격 워드 쓰기가 온다.
Witness_NoRsvw == why # "rsvw"

\* commit_rsv_strict — `[27:0]` 비0 COMMIT 이 온다.
Witness_NoCommitRsv == why # "crsv"

\* commit_replaces_vpn · evict_in_partition — 다른 VPN 의 산 칸을 덮는 커밋(축출)이 일어난다.
Witness_NoEvict == "evict" \notin ev

\* evict_on_commit_only — 산 항목이 있는 상태가 실재한다 (자발 축출의 전건).
Witness_NoResident == ~(\E q \in Parts, s \in Slots : tbl[q][s].v)

\* stall_independent — 하류 정지와 미적중 정지가 동시에 선다.
Witness_NoStallInMiss == ~(held # NoWrite /\ mstall.on)

\* Refusal = "stall" — 하류 거부로 버스가 실제로 정지한다.
Witness_NoStall == held = NoWrite

\* RefuseDomain — 데이터 사유 COMMIT 이 정지 뒤 수락 사이클에 거절된다 (Prop_StallDataBlind 의 전건).
Witness_NoDataHeld == "dataHeld" \notin ev

\* flush_fires · flush_valid_only — 살아 있는 파티션이 flush 된다.
Witness_NoFlushLive == "flushLive" \notin ev

\* flush_scoped — 다른 파티션이 살아 있는 동안 flush 가 일어난다.
Witness_NoFlushOther == "flushOther" \notin ev

\* flush_part_exists — 없는 파티션 값의 flush 가 온다.
Witness_NoPhantom == why # "phantom"

\* flush_rsv_strict — 예약 위반 flush 가 온다.
Witness_NoRsv == why # "rsv"

\* mclr_fires — 정지가 풀린 뒤 선 채로 남은 sticky 위에 적법한 해제가 온다.
Witness_NoClearLive == "clrLive" \notin ev

\* mclr_needs_one — 선 sticky 위에(정지 없음) `[0]`=0 의 적법한 기입이 온다.
Witness_NoZeroLive == "zeroLive" \notin ev

\* mclr_rsv_strict — 예약 위반 해제가 온다.
Witness_NoMclrRsv == why # "mrsv"

\* mclr_keeps_stall — 미적중 정지 중에 적법한 해제가 온다.
Witness_NoClearInStall == "clrStall" \notin ev

\* ro_rejected — RO 오프셋 쓰기가 온다.
Witness_NoRo == why # "ro"

\* flush_drops_staging — 스테이징이 그 파티션을 래치한 채 flush 가 실행된다 (가드의 전건).
Witness_NoFlushStaged == ~(why = "flush" /\ stale /\ cs.p = acc.p)

\* flush_drops_staging — flush 를 건넌 스테이징 위에 FRAME · VPN_HI · COMMIT 이 온다.
Witness_NoStaleUse == ~(acc.kind \in {"frame", "vpnhi", "commit"} /\ stale)

\* ent_part_exists — 없는 파티션 기저의 기입이 온다 (BelowCap).
Witness_NoEntPhantom == why # "ephantom"

=============================================================================
