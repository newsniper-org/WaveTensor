\* SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
\* SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
----------------------------- MODULE Mask -----------------------------
(***************************************************************************)
(* SEC-1 곁가지 / HIU-* 임대별 마스크 키 — MaskUnit 제어면 선-formal 모델. *)
(*                                                                         *)
(* 정본 `7fa5f2e`(임대별 마스크 키): 05-security.typ:112 규범 "키의 범위 —  *)
(* 임대마다 다르다" · e-defined.typ:333 "마스킹 — 0xE80 구역" · :351       *)
(* "임대별 키의 인코딩 — 창이지 평면 배열이 아니다" · E.9 4항·6항.         *)
(*                                                                         *)
(* 이 모델이 다루지 않는 것: ChaCha 라운드망의 암호 정확성(SEC-1)은        *)
(* golden 대조(cocotb, `rtl/sim/test_mask_golden.py`)의 몫이다 — 이 모델은 *)
(* *어느 파티션의* 키가 저장·기입·재키잉으로 읽히는가라는 제어면만 본다.   *)
(* 값 자체가 옳은 XChaCha20 출력인지는 이 모델의 질문이 아니다.            *)
(*                                                                         *)
(* ## 신설인 이유                                                          *)
(*                                                                         *)
(* `Isolation.tla` 는 파이프라인 단계 이름 "mask" 를 세 번 쓸 뿐(문자열     *)
(* 리터럴), key/rekey/nonce/lease 라는 낱말을 하나도 모델하지 않는다 —      *)
(* 실측(`grep -n -i "key\|rekey\|nonce\|lease"` 이 저장소 tla 전체)로       *)
(* Mask 관련 제어면 선-formal 은 이 파일 이전에 저장소 어디에도 없었다.     *)
(*                                                                         *)
(* ## 이 모델이 잡는 정확한 결함                                            *)
(*                                                                         *)
(* 재구현 착수 시점의 `MaskUnit.scala` 는 `key` 를 파티션마다 두지 않고     *)
(* 한 벌(`Vec.fill(KEY_WORDS)`)로 두었고, 키 기입 시 `for (p <- 0 until     *)
(* parts) maskValid(p) := False` 로 **전 파티션을 무효화**했다 — E.9 4항    *)
(* "다른 파티션이 그 변경의 사정권 밖" 이 명시적으로 금지하는 형태다.       *)
(* 아래 `key_scoped_storage` · `key_write_own_only` 가드를 지우면 각각      *)
(* 그 결함과 동형인 모델이 되고, 반례가 나와야 그 대응이 맞다는 증거다      *)
(* (§6.3.2 가드 삭제 실험).                                                *)
(*                                                                         *)
(* `rekey_explicit_target` 가드는 e-defined.typ:351 7항이 명시적으로       *)
(* 기각한 갈래 — "MASK_PART 창이 재키잉의 authority 를 겸하는" 설계 — 를    *)
(* 모델에 넣어 반례를 낸다. MASK_REKEY(0xEBC) 는 `[7:0]` 에 재키잉할        *)
(* 파티션을 **직접** 나른다: 창(MASK_PART)과는 별개의 authority 다.         *)
(***************************************************************************)
\* ## 확장 — FAULT_STATUS [12] 논스 재사용 판정 · 0xEC4 MASK_DUP_CAPTURE
\*    (v1.0 묶음 RTL 파도 W1, 2026-10-11 — 선-formal 1단)
\*
\* 오늘(HEAD b81df18)까지 [12] 판정도 0xEC4 캡처도 어느 모델에도 없었다
\* (전수 grep 0건). 이 절이 둘을 이 모델에 싣는다 — 「재키잉이 시작된」
\* 발화의 정의(rekey_idle_only · rekey_explicit_target)가 이미 여기 살기
\* 때문이다. 변수 dup = FAULT_STATUS [12] sticky, cap = 0xEC4 의 두 필드
\* ([7:0] p · [15:8] 비트맵 — 레지스터 capPart · capMap), ev = 이 전이의 버스 사건
\* 기록(속성·증인이 「어느 사건이었나」를 가르는 데만 쓴다 — lastWinWrite 와 같은 자리).
\* [16] 캡처 유효는 따로 두지 않는다 — 결정 W1-4 대로 [16] 은 [12] sticky 레지스터
\* *그 자체*다. 호스트가 읽는 워드는 Word(아래)이고 Word.on = dup 이 구조로 선다.
\* 그래서 「[16] ⇔ [12]」(Inv_CapIffDup)는 목표 모델에서 가드가 아니라 구조이고,
\* 그것을 깨는 것은 짝 「오늘의 RTL」(W1 전 RTL — HEAD 3b80087 · 워드 미디코드) 하나다. 이 결정에서 RTL 이 실제로
\* 빠뜨릴 수 있는 해제 몫은 [16] 이 아니라 capPart · capMap 의 해제다 — 가드
\* cap_clear_whole 이 그것을 잰다(목표 Inv_CapClearedZero).
\*
\* 정본 근거 (같은 줄 축자 결속 — 줄이 밀리면 lint_section_refs R3 가 운다):
\*   판정 시점      e-defined.typ:345 「엔진 유휴에서 수락되고 값 검사를 통과해 거절 + `[6]` 이 아닌」
\*   판정 정의역    e-defined.typ:345 「p 자신은 비교에 들지 않는다」
\*   거절 발화      e-defined.typ:345 「거절 + `[6]` 인 발화는 `[12]` 도 `0xEC4` 도 움직이지 않는다」
\*   비트맵         e-defined.typ:347 「p 번 비트는 늘 0」
\*   첫 사건 보존   e-defined.typ:347 「`[16]` = 1 동안의 새 발화는 캡처를 덮지 않는다」
\*   세움이 이김    e-defined.typ:347 「해제와 새 발화가 같은 사이클이면 새 사건을 래치한다」
\*   같은 해제 신호 e-defined.typ:347 「구현의 내부 해제선(호스트 계약 밖 · `0xF84` 행)도 `[12]` 와 함께 이 워드를 지운다」
\*   불변식         e-defined.typ:347 「`[12]` = 1 ∧ `[16]` = 0 은 도달 불가다」
\*   reset 값       e-defined.typ:216 「`0xEC4` MASK_DUP_CAPTURE = 0」
\*   준비 비트      e-defined.typ:527 「호스트는 `[12]` = 1 이면 그 HIU 의 모든 파티션의 준비 비트를 신뢰하지 않는다」
\*                  — 그래서 이 모델은 [12] 를 동반한 재키잉 뒤의 maskValid 를
\*                    바꾸지 않는다(구현 정의 — 기존 Rekey 처분 그대로).
\*   엔진 무관      e-defined.typ:527 「재키잉의 완료(`0xEC0` `[8]` 하강)는 `[12]` 와 무관하게 온다」
\*   busy 진입      e-defined.typ:347 「완료 전까지 `[8]` = 1 을 본다」
\*                  — 시작된 발화는 [12] 가 서도 엔진을 busy 로 보내고(start_ignores_dup),
\*                    완료는 [12] 를 읽지 않는다(complete_ignores_dup).
\*
\* 새 가드 여덟과 RTL 대응 예정 이름 (GUARD-MAP 용 — 정식 줄은 RTL 저자가
\* MaskUnit.scala 클래스 끝 주석에 단다; 한 가드 = 한 줄, lint_guard_map):
\*   dup_on_started_rekey  지우면 [12] 판정이 *모든* MASK_REKEY 기입(busy 미수락 ·
\*                         값 검사 거절 포함)에서 돈다.
\*     → GUARD-MAP: Mask.dup_on_started_rekey -> nonceDupFire = rekeyFire && nonceDup
\*       (rekeyFire = rekey.valid ∧ rekey.ready(=!engineBusy); rekey.valid 는
\*        Wt64Top 이 예약 · partBad 를 통과한 기입에만 세운다 — 캡처도 같은 fire 만 본다)
\*   cap_first_event       지우면 [16] = 1 동안의 새 발화가 캡처를 덮는다.
\*     → GUARD-MAP: Mask.cap_first_event -> 캡처 래치 조건의 !io.faultNonceDup 항
\*       (when(nonceDupFire && (!io.faultNonceDup || io.faultClearNonceDup)))
\*   cap_clear_whole       지우면 해제가 [12](= [16])만 내리고 capPart · capMap 을 남긴다
\*                         — 워드가 [16] = 0 인데 [7:0] · [15:8] 이 낡은 값을 낸다.
\*                         정본은 해제가 *이 워드*를 지운다고 한다(아래 :347 결속).
\*     → GUARD-MAP: Mask.cap_clear_whole -> capPart · capMap 을 io.faultClearNonceDup
\*       (= IO 해제선 ∨ fclr(12))로 지운다 — [16] 은 io.faultNonceDup 레지스터 그 자체라
\*       저절로 내려가므로 이 줄이 해제의 유일한 몫이다
\*   cap_set_beats_clear   지우면 해제와 같은 사이클의 발화가 래치되지 않는다
\*                         (해제가 이겨 [12] = 1 인데 필드 0 — 새 사건 상실).
\*     → GUARD-MAP: Mask.cap_set_beats_clear -> 래치 조건의 || io.faultClearNonceDup 항
\*       + 래치 대입이 해제 대입 *뒤*(마지막 대입이 이긴다)
\*   cap_bitmap_exact      지우면 비트맵 정의역에서 q ≠ p 가 빠진다(p 자신이 비트맵에
\*                         든다 — 정본 명확화 2026-10-11 이 닫은 갈래).
\*     → GUARD-MAP: Mask.cap_bitmap_exact -> capMap 의 bit p 는 0 — nonceDupQ 의 q ≠ p 항
\*   cap_bitmap_domain     지우면 비트맵이 겹침 항(maskValid(q) ∧ nonce(q) = nonce(p))을
\*                         잃고 「다른 파티션 전부」를 낸다. 파티션 2 에서는 발화 조건이
\*                         두 항을 함의해 보이지 않는다 — 삭제 run 은 파티션 3 + VIEW 다.
\*     → GUARD-MAP: Mask.cap_bitmap_domain -> capMap := nonceDupQ.asBits — [12] 의 OR 가
\*       접는 바로 그 q 별 항(maskValid(q) ∧ nonce(q) == reqNonce)
\*   start_ignores_dup     지우면 [12] 를 세운 시작된 발화가 엔진을 busy 로 보내지 않는다
\*                         (재키잉 중단 설계).
\*     → GUARD-MAP: Mask.start_ignores_dup -> busy 진입은 rekeyFire 하나 — nonceDup 이
\*       rekey.ready · engineBusy 세움 식에 들지 않는다
\*   complete_ignores_dup  지우면 [12] 가 서 있는 동안 완료가 막힌다(완료 정체 설계).
\*     → GUARD-MAP: Mask.complete_ignores_dup -> 엔진 완료(engineBusy 하강) 조건에
\*       io.faultNonceDup 항이 없다
\*
\* 짝 「오늘의 RTL」(W1 전 RTL — HEAD 3b80087) = CapWired = FALSE: [12] 판정은 있으나 0xEC4 가 디코드되지 않아
\* 읽기 0 이다(R_MASK 워드 17 미디코드). Inv_CapIffDup 이 깨진다. W1 전 RTL 의 [12]
\* 판정 식이 이 모델의 판정과 같다는 것은 측정이 아니라 *읽기 대조*다
\* (MaskUnit 의 nonceDup 식 · Wt64Top 의 [12] 결선) — CapWired 는 Word 만 바꾸므로 어떤 run 도
\* RTL 의 [12] 쪽을 재지 않는다(W1 RTL 의 [12] 는 후-formal engine.sby 가 탐침 축약 아래에서 잰다). 그래서 대비 MUST PASS run 을 두지 않는다.
\*
\* 이 절이 재지 않는 것 (닫힌 목록 — 여기 없는 정본 규칙은 위 속성이 잰다):
\*   · 0xEC4 쓰기 거절 + [6] — RO 부류, MmioPage.ro_rejected 의 몫.
\*   · 0xEC4 읽기 결선 — assembly 의 몫(a_rd_dupcap — W1 에서 섰다).
\*   · 논스 *값*의 폭 — 불투명 토큰. 192b 전폭 비교의 정확성은 후-formal engine.sby 의 몫.
\*   · e-defined.typ:347 「읽기는 아무것도 해제하지 않는다」 — 이 모델에는 읽기 동작이 없다.
\*     W1 전에는 이것을 재는 단언이 **없었다**. 몫: assembly(0xEC4 · 0xF80 읽기 사이클에 [12] 와
\*     dupCapture 가 그대로라는 단언 — W1 에서 a_rd_pure 로 섰다 · 형제 단언에서 유도되는 단언).
\*   · e-defined.typ:497 「예약 비트가 0 이 아니면 기입 전체를 거절(+ `[6]`)하고 한 비트도 내리지 않는다」
\*     — 이 모델의 Clear("host") 는 늘 수락된 W1C 다. 거절된 0xF84 기입이 [12] 와
\*     0xEC4 를 건드리지 않음은 assembly(acF84 · w5_fclr_rsv)의 몫이다(MmioPage 「안 잰다」).
\*   · reset *형식* 단언 — 결정 W1-8 로 이번에 하지 않는다. 모델의 Init 이 reset 0 이다.
EXTENDS Naturals, FiniteSets

CONSTANTS
    Parts,           \* 임대(파티션). 불투명 토큰
    KeyVals,         \* 키 값 도메인. 불투명 토큰 — 값 자체의 정확성은 SEC-1(golden) 몫
    NonceVals,       \* 논스 값 도메인. 불투명 토큰
    NoPart,          \* 「지목 없음」 표식 (모델 값)
    CapWired,        \* TRUE = 0xEC4 결선(목표). FALSE = 짝 「오늘의 RTL」(W1 전 RTL — HEAD 3b80087) — 워드 없음(읽기 0)
    DisabledGuards

AllGuards == {"key_scoped_storage", "key_write_own_only",
              "rekey_idle_only", "rekey_explicit_target",
              "dup_on_started_rekey", "cap_first_event", "cap_clear_whole",
              "cap_set_beats_clear", "cap_bitmap_exact", "cap_bitmap_domain",
              "start_ignores_dup", "complete_ignores_dup"}
On(g) == g \notin DisabledGuards

SomeKey   == CHOOSE k \in KeyVals   : TRUE
SomeNonce == CHOOSE n \in NonceVals : TRUE
SomePart  == CHOOSE p \in Parts     : TRUE

\* [12] 해제 신호의 원천 — 호스트 대면 0xF84 [12] W1C ("host") 와 구현 내부
\* 해제선 io.faultClear.maskNonceDup ("io"). 정본은 둘을 *같은 신호*로 묶는다.
\* MMIO 버스는 하나라 host 해제는 MASK_REKEY 기입과 같은 사이클에 올 수 없다
\* — 같은 사이클 겹침은 내부 해제선으로만 생긴다.
ClrSrc  == {"host", "io"}
EvKinds == {"other", "start", "busy", "bad", "clear"}
Cap0    == [on |-> FALSE, p |-> NoPart, bm |-> {}]   \* 워드 전체 0
Fld0    == [p |-> NoPart, bm |-> {}]                 \* capPart · capMap 의 0

VARIABLES
    key,             \* [Parts -> KeyVals]     — MASK_KEY[0..7], WO 레지스터 뒤의 저장
    nonce,           \* [Parts -> NonceVals]   — MASK_NONCE[0..5], 이미 파티션별(변경 대상 아님)
    maskValid,       \* [Parts -> BOOLEAN]     — MASK_STATUS 의 파티션별 준비 비트
    winPart,         \* MASK_PART(0xEA0) 창 레지스터 — 다음 키·논스 기입의 대상
    phase,           \* {"idle", "busy"} — REKEY 진행 (HROUND 스트림 중)
    reqPart,         \* 가장 최근 MASK_REKEY 기입이 지목한 파티션 (수락 여부 무관)
    engTarget,       \* 엔진이 실제로 라운드 유도에 쓴 파티션. None = 아직 REKEY 없음
    engKey,          \* engTarget 확정 시 엔진이 읽은 키 값
    rekeyAccepted,   \* 가장 최근 REKEY 시도의 수락 여부 (MASK_STATUS[9] 미수락의 반대)
    keyEverWritten,  \* 증인용 sticky 비트 — 키 기입이 실제로 일어났는가
    driftSeen,       \* 증인용 sticky 비트 — reqPart # winPart 인 REKEY 시도가 실재했는가
    busyAttemptSeen, \* 증인용 sticky 비트 — phase="busy" 중 REKEY 시도가 실재했는가
    lastWinWrite,    \* 이번 전이가 *창을 거친 기입*(키 또는 논스)이었다면 그
                     \* 창 값, 아니면 NoPart. Rekey 의 maskValid 기입은 창과
                     \* 무관한 별개 authority 이므로 이 표식에 잡히지 않는다
                     \* — Prop_MaskValidScoped 가 REKEY 의 정당한 변경과
                     \* 창 기입의 스코프 위반을 가르는 데 쓴다 (아래 해설)
    dup,             \* FAULT_STATUS [12] sticky — 논스 재사용 판정
    cap,             \* 0xEC4 의 필드 레지스터 — [p: [7:0] capPart, bm: [15:8] capMap].
                     \* [16] 은 dup 그 자체(W1-4) — 호스트 시야는 Word
    ev               \* 이 전이의 버스 사건 — [kind, p, clr, hit, held, self, stale]
                     \*   kind  "start"(재키잉이 시작된 REKEY) · "busy"(엔진 busy 미수락)
                     \*         · "bad"(값 검사 거절 + [6]) · "clear"(해제만) · "other"
                     \*   p     지목 파티션 (start 는 엔진이 실제로 문 파티션)
                     \*   clr   이 사이클의 [12] 해제 원천 — "none" · "host" · "io"
                     \*   hit · held · self · stale — 증인 전용 기록 (전이 *앞* 상태):
                     \*         p 에 겹침 있음 · 캡처 유효였음 · p 자신이 마스크 유효였음
                     \*         · 캡처가 같은 p 로 유효한데 그 비트맵이 지금의 DupSet(p) 와 다름

vars == <<key, nonce, maskValid, winPart, phase, reqPart, engTarget, engKey,
          rekeyAccepted, keyEverWritten, driftSeen, busyAttemptSeen, lastWinWrite,
          dup, cap, ev>>

\* ## 규모 — 대형 cfg 의 VIEW (2026-10-11 실측)
\*
\* 확장 뒤 Mask_large(파티션 3)를 VIEW 없이 돌리면 133,529,425 generated /
\* 7,881,960 distinct · 11분 34초(-workers 1)다 — 확장 전 232,752 distinct · 4초의
\* 34배. 폭발의 몸은 dup · cap 이 아니라 *쓰기 전용* 변수들이다: ev(사건 기록),
\* lastWinWrite, 증인 sticky 셋, reqPart · engKey · rekeyAccepted. 이것들은
\* Next 의 어느 동작도 (자기 자신의 갱신 밖에서는) 읽지 않고, 대형 cfg 가 거는
\* 속성은 그것들을 *다음* 상태(priming)로만 읽는다. 그래서 지문에서 빼도 대형
\* cfg 의 판정은 같다 — 지문이 같은 두 상태는 같은 후속(빠진 변수 제외)을 갖고,
\* TLC 는 대표 상태에서 나가는 *모든* 전이에 행위 속성을 평가한다.
\* VIEW 를 쓴 대형 = 1,990,081 generated / 92,352 distinct · 수십 초(거절 · busy 발화에
\* 내부 해제선 겹침을 연 판 — 위 VIEW 없는 실측은 그 전 판의 것이다).
\* 비트맵의 겹침 항은 파티션 3 에서만 보이므로 이 대형 설정이 그 항의 유일한 측정
\* 설정이다 — 같은 설정의 MUST-FAIL 대조(cap_bitmap_domain 삭제)가 상주한다.
\* TypeOK 의 빠진 변수 몫과 ev 를 읽는 증인은 VIEW 없는 cfg(작은 설정 ·
\* 증인 cfg 전부)가 잰다 — 대형에만 VIEW 를 건다. 새 변수를 더할 때 이 목록을
\* 다시 대조하라: 동작이 *읽는* 변수를 여기서 빼면 판정이 공허해진다.
StateView == <<key, nonce, maskValid, winPart, phase, engTarget, dup, cap>>

\* 호스트가 0xEC4 에서 읽는 워드. 목표(CapWired)에서 [16] = dup 은 구조다 —
\* W1-4 「[16] 은 [12] sticky 레지스터 그 자체」. W1 전 RTL(HEAD 3b80087)은 워드 미디코드(읽기 0).
Word == IF CapWired THEN [on |-> dup, p |-> cap.p, bm |-> cap.bm] ELSE Cap0

\* 정본 판정 정의역 — 마스크가 유효한 *다른* 파티션 q ≠ p 가운데 논스가 p 의
\* 새 논스와 같은 것. p 의 논스 레지스터는 재키잉 전에 이미 새 논스를 담는다
\* (MASK_NONCE 기입이 앞선다) — 그래서 「p 의 새 논스」 = nonce[p] (전이 앞 상태).
\* 속성은 이 정의를 *독립으로* 쓴다 — 모델의 갱신식(BmSet)이 아니라.
DupSet(p) == {q \in Parts : maskValid[q] /\ q # p /\ nonce[q] = nonce[p]}

\* 모델의 캡처 비트맵 갱신식 — cap_bitmap_exact 를 끄면 q ≠ p 가 빠지고,
\* cap_bitmap_domain 을 끄면 겹침 항(maskValid ∧ 논스 동치)이 빠진다.
BmSet(p) == {q \in Parts :
               /\ (q # p \/ ~On("cap_bitmap_exact"))
               /\ ((maskValid[q] /\ nonce[q] = nonce[p]) \/ ~On("cap_bitmap_domain"))}

Ev(k, p, c) ==
    LET att == k \in {"start", "busy", "bad"}
    IN  [kind |-> k, p |-> p, clr |-> c,
         hit  |-> (att /\ DupSet(p) # {}),
         held |-> dup,
         self |-> (att /\ maskValid[p]),
         stale |-> (att /\ dup /\ cap.p = p /\ cap.bm # DupSet(p))]
EvOther == [kind |-> "other", p |-> NoPart, clr |-> "none",
            hit |-> FALSE, held |-> FALSE, self |-> FALSE, stale |-> FALSE]

TypeOK ==
    /\ key \in [Parts -> KeyVals]
    /\ nonce \in [Parts -> NonceVals]
    /\ maskValid \in [Parts -> BOOLEAN]
    /\ winPart \in Parts
    /\ phase \in {"idle", "busy"}
    /\ reqPart \in Parts \cup {NoPart}
    /\ engTarget \in Parts \cup {NoPart}
    /\ engKey \in KeyVals
    /\ rekeyAccepted \in BOOLEAN
    /\ keyEverWritten \in BOOLEAN
    /\ driftSeen \in BOOLEAN
    /\ busyAttemptSeen \in BOOLEAN
    /\ lastWinWrite \in Parts \cup {NoPart}
    /\ dup \in BOOLEAN
    /\ cap \in [p : Parts \cup {NoPart}, bm : SUBSET Parts]
    /\ ev \in [kind : EvKinds, p : Parts \cup {NoPart}, clr : {"none"} \cup ClrSrc,
               hit : BOOLEAN, held : BOOLEAN, self : BOOLEAN, stale : BOOLEAN]

Init ==
    /\ key = [p \in Parts |-> SomeKey]
    /\ nonce = [p \in Parts |-> SomeNonce]
    /\ maskValid = [p \in Parts |-> FALSE]
    /\ winPart = SomePart
    /\ phase = "idle"
    /\ reqPart = NoPart
    /\ engTarget = NoPart
    /\ engKey = SomeKey
    /\ rekeyAccepted = FALSE
    /\ keyEverWritten = FALSE
    /\ driftSeen = FALSE
    /\ busyAttemptSeen = FALSE
    /\ lastWinWrite = NoPart
    /\ dup = FALSE                 \* reset 값 0 (FAULT_STATUS sticky 전부)
    /\ cap = Fld0                  \* reset 값 0
    /\ ev = EvOther

(***************************************************************************)
(* [12] · 0xEC4 의 한 사이클 갱신 — 모든 REKEY 기입과 해제가 이것을 지난다. *)
(*                                                                         *)
(*   att      이 사이클에 MASK_REKEY 기입이 있었는가                       *)
(*   started  그 기입이 「재키잉이 시작된」 발화인가 (유휴 수락 ∧ 값 통과)   *)
(*   p        판정이 볼 파티션                                             *)
(*   c        이 사이클의 해제 원천 ("none" · "host" · "io")               *)
(*                                                                         *)
(* [12] 자신은 StickyFault 규약(세움이 이긴다)을 따른다 — 이 절의 가드가    *)
(* 아니라 FAULT_STATUS 공통 규약이다.                                      *)
(***************************************************************************)
DupCap(att, started, p, c) ==
    LET judged == IF On("dup_on_started_rekey") THEN started ELSE TRUE
        fire   == att /\ judged /\ (DupSet(p) # {})
        clrNow == c # "none"
        clrFld == clrNow /\ On("cap_clear_whole")
        free   == IF On("cap_set_beats_clear") THEN (~dup \/ clrNow) ELSE ~dup
        latch  == fire /\ (free \/ ~On("cap_first_event"))
    IN  /\ dup' = (fire \/ (dup /\ ~clrNow))
        /\ cap' = IF latch THEN [p |-> p, bm |-> BmSet(p)]
                  ELSE IF clrFld THEN Fld0
                  ELSE cap

(***************************************************************************)
(* MASK_PART(0xEA0) 기입 — 다음 키·논스 기입의 창을 바꾼다.                *)
(* e-defined.typ:351 7항: authority 는 MASK_REKEY 하나이지 이 창이 아니다  *)
(* — 그래서 SetPart 자체는 REKEY 상태(phase/engTarget)에 아무 영향이 없다. *)
(***************************************************************************)
SetPart(p) ==
    /\ winPart' = p
    /\ lastWinWrite' = NoPart
    /\ ev' = EvOther
    /\ UNCHANGED <<key, nonce, maskValid, phase, reqPart, engTarget, engKey,
                   rekeyAccepted, keyEverWritten, driftSeen, busyAttemptSeen,
                   dup, cap>>

(***************************************************************************)
(* MASK_KEY[0..7] 기입 — 창(winPart)이 가리키는 파티션 슬롯에 앉는다.       *)
(*                                                                         *)
(*   key_scoped_storage   지우면 키 저장이 파티션별이 아니라 전역 1벌이     *)
(*                        된다 — 재구현 착수 시점 RTL 과 동형.             *)
(*   key_write_own_only   지우면 키 기입이 **전 파티션의** maskValid 를     *)
(*                        떨어뜨린다 — 같은 RTL 의 두 번째 결함면.         *)
(***************************************************************************)
WriteKey(kv) ==
    /\ key' = IF On("key_scoped_storage")
                THEN [key EXCEPT ![winPart] = kv]
                ELSE [p \in Parts |-> kv]
    /\ maskValid' = IF On("key_write_own_only")
                      THEN [maskValid EXCEPT ![winPart] = FALSE]
                      ELSE [p \in Parts |-> FALSE]
    /\ keyEverWritten' = TRUE
    /\ lastWinWrite' = winPart
    /\ ev' = EvOther
    /\ UNCHANGED <<nonce, winPart, phase, reqPart, engTarget, engKey,
                   rekeyAccepted, driftSeen, busyAttemptSeen, dup, cap>>

(***************************************************************************)
(* MASK_NONCE[0..5] 기입 — 이미 파티션별로 옳게 구현돼 있다(변경 대상       *)
(* 아님). 논스 기입도 창(winPart)이 가리키는 파티션의 유효만 떨어뜨린다 —   *)
(* 그 처분이 WriteKey 의 key_write_own_only 가 *복구해야 할* 목표 동작이다. *)
(* 캡처는 래치 순간의 스냅숏이라 뒤의 논스 · 유효 변경에 따라 움직이지     *)
(* 않는다 (UNCHANGED cap).                                                  *)
(***************************************************************************)
WriteNonce(nv) ==
    /\ nonce' = [nonce EXCEPT ![winPart] = nv]
    /\ maskValid' = [maskValid EXCEPT ![winPart] = FALSE]
    /\ lastWinWrite' = winPart
    /\ ev' = EvOther
    /\ UNCHANGED <<key, winPart, phase, reqPart, engTarget, engKey,
                   rekeyAccepted, keyEverWritten, driftSeen, busyAttemptSeen,
                   dup, cap>>

(***************************************************************************)
(* MASK_REKEY(0xEBC) 기입 — `[7:0]` 이 재키잉할 파티션 p 를 직접 나른다.    *)
(*                                                                         *)
(*   rekey_idle_only       지우면 phase="busy" 에도 수락한다 — MASK_STATUS *)
(*                         [9] 미수락 관측(정본 e-defined.typ:344)이 깨진다.*)
(*   rekey_explicit_target 지우면 REKEY 가 지목한 파티션이 아니라 *창*이    *)
(*                         가리키는 파티션을 읽는다 — e-defined.typ:351    *)
(*                         7항이 명시적으로 기각한 "창이 authority 를 겸함" *)
(*                         갈래와 동형이다.                                *)
(*                                                                         *)
(* 수락되면 그 파티션의 maskValid 를 세운다 — MASK_STATUS 가 파티션별로     *)
(* 준비를 보고하는 관측 가능한 형태이며, key_write_own_only 가드 실험이     *)
(* "다른 파티션의 준비가 꺼진다" 를 관측할 수 있으려면 준비가 *서는* 경로가 *)
(* 먼저 있어야 한다.                                                       *)
(*                                                                         *)
(* c = 같은 사이클의 [12] 해제 원천("none" · "io"). 내부 해제선은 MMIO 와   *)
(* 독립된 입력이라 수락된 발화에도, busy 미수락 발화에도 겹칠 수 있다 —     *)
(* 둘 다 연다 (host W1C 는 버스가 하나라 REKEY 기입과 같은 사이클이 없다).  *)
(*                                                                         *)
(*   start_ignores_dup     지우면 [12] 를 세운 시작된 발화가 엔진을 busy 로   *)
(*                         보내지 않는다(재키잉 중단 설계).                *)
(***************************************************************************)
Rekey(p, c) ==
    LET idleOK == (phase = "idle") \/ ~On("rekey_idle_only")
        target == IF On("rekey_explicit_target") THEN p ELSE winPart
    IN  /\ reqPart' = p
        /\ driftSeen' = (driftSeen \/ (p # winPart))
        /\ busyAttemptSeen' = (busyAttemptSeen \/ (phase = "busy"))
        /\ IF idleOK
             THEN /\ phase' = IF On("start_ignores_dup") \/ DupSet(target) = {}
                                THEN "busy" ELSE "idle"
                  /\ engTarget' = target
                  /\ engKey' = key[target]
                  /\ rekeyAccepted' = TRUE
                  /\ maskValid' = [maskValid EXCEPT ![target] = TRUE]
                  /\ DupCap(TRUE, TRUE, target, c)
                  /\ ev' = Ev("start", target, c)
             ELSE /\ rekeyAccepted' = FALSE
                  /\ UNCHANGED <<phase, engTarget, engKey, maskValid>>
                  /\ DupCap(TRUE, FALSE, p, c)
                  /\ ev' = Ev("busy", p, c)
        /\ lastWinWrite' = NoPart
        /\ UNCHANGED <<key, nonce, winPart, keyEverWritten>>

(***************************************************************************)
(* MASK_REKEY 값 검사 거절 — `[31:8]` 예약 비0 또는 없는 파티션 지목.       *)
(* 거절 + [6] 이고 엔진 · 준비 · 지목 상태는 하나도 바뀌지 않는다.          *)
(* (`[6]` 자체는 이 모델 밖 — MmioPage 의 reject_loud 몫.) p 는 기입의      *)
(* `[7:0]` 이 실재 파티션을 가리키는 경우(예약 비0 갈래)다 — 그래야         *)
(* dup_on_started_rekey 삭제 실험이 판정할 대상을 갖는다. c 는 Rekey 와 같다 *)
(* — 내부 해제선은 거절 사이클에도 올 수 있다.                             *)
(***************************************************************************)
RekeyBad(p, c) ==
    /\ DupCap(TRUE, FALSE, p, c)
    /\ ev' = Ev("bad", p, c)
    /\ lastWinWrite' = NoPart
    /\ UNCHANGED <<key, nonce, maskValid, winPart, phase, reqPart, engTarget,
                   engKey, rekeyAccepted, keyEverWritten, driftSeen,
                   busyAttemptSeen>>

(***************************************************************************)
(* [12] 해제만 있는 사이클 — host W1C 또는 내부 해제선.                     *)
(***************************************************************************)
Clear(src) ==
    /\ DupCap(FALSE, FALSE, NoPart, src)
    /\ ev' = Ev("clear", NoPart, src)
    /\ lastWinWrite' = NoPart
    /\ UNCHANGED <<key, nonce, maskValid, winPart, phase, reqPart, engTarget,
                   engKey, rekeyAccepted, keyEverWritten, driftSeen,
                   busyAttemptSeen>>

(***************************************************************************)
(* 엔진이 HROUND 스트림을 마치고 유휴로 돌아간다 — busy 구간의 종료.        *)
(* 완료는 [12] 와 무관하다 — 판정은 수락 사이클에서 이미 끝났다.           *)
(*                                                                         *)
(*   complete_ignores_dup  지우면 [12] 가 서 있는 동안 완료가 막힌다.        *)
(***************************************************************************)
Complete ==
    /\ phase = "busy"
    /\ (On("complete_ignores_dup") \/ ~dup)
    /\ phase' = "idle"
    /\ lastWinWrite' = NoPart
    /\ ev' = EvOther
    /\ UNCHANGED <<key, nonce, maskValid, winPart, reqPart, engTarget, engKey,
                   rekeyAccepted, keyEverWritten, driftSeen, busyAttemptSeen,
                   dup, cap>>

Next ==
    \/ \E p \in Parts : SetPart(p)
    \/ \E kv \in KeyVals : WriteKey(kv)
    \/ \E nv \in NonceVals : WriteNonce(nv)
    \/ \E p \in Parts, c \in {"none", "io"} : Rekey(p, c)
    \/ \E p \in Parts, c \in {"none", "io"} : RekeyBad(p, c)
    \/ \E src \in ClrSrc : Clear(src)
    \/ Complete

Spec == Init /\ [][Next]_vars

(***************************************************************************)
(* 속성 — 전부 행위 속성([][...]_vars). 저장이 한 사이클 안에서 파티션      *)
(* 경계를 지키는가를 묻는 것이라 상태 하나로는 말할 수 없다 (ResultBank.tla *)
(* Prop_WriteQualified 와 같은 자리).                                       *)
(***************************************************************************)

\* E.9 4항 "다른 파티션이 사정권 밖" — 저장측. 창이 가리키지 않는 파티션의
\* 키는 어떤 전이에서도 바뀌지 않는다.
Prop_KeyScoped ==
    [][ \A q \in Parts : (q # winPart) => (key'[q] = key[q]) ]_vars

\* e-defined.typ:339 「기입은 그 파티션의 마스크 유효를 즉시 떨어뜨린다」 —
\* 그 파티션에 한정된다. *창을 거친 기입*(lastWinWrite' # NoPart 인 전이 —
\* WriteKey 또는 WriteNonce) 이 아닌 파티션의 준비는 꺼지지 않는다.
\*
\* REKEY 의 maskValid 기입은 이 속성의 대상이 **아니다** — REKEY 의
\* authority 는 창이 아니라 REKEY 기입 자신이므로(e-defined.typ:351 7항),
\* REKEY(p) 의 target 이 winPart 와 달라도 그것은 스코프 위반이 아니라
\* 설계대로다. lastWinWrite 가 정확히 그 구별을 잡는다 (Rekey/SetPart/
\* Complete 는 lastWinWrite' = NoPart 로 이 속성에서 스스로를 뺀다).
Prop_MaskValidScoped ==
    [][ (lastWinWrite' # NoPart) =>
          (\A q \in Parts : (q # lastWinWrite') => (maskValid'[q] = maskValid[q])) ]_vars

\* e-defined.typ:344 "유휴가 아니면 미수락" — 엔진이 실제로 파티션을
\* 바꿔 무는(engTarget 이 바뀌는) 모든 전이는 유휴에서 시작했어야 한다.
Prop_RekeyIdleOnly ==
    [][ (engTarget' # engTarget) => (phase = "idle") ]_vars

\* e-defined.typ:351 7항 "authority 는 MASK_REKEY 하나" — 엔진이 실제로
\* 무는 파티션은 REKEY 기입이 지목한 파티션이다, 창의 현재값과 무관하게.
Prop_RekeyTargetIsRequested ==
    [][ (engTarget' # engTarget) => (engTarget' = reqPart') ]_vars

(***************************************************************************)
(* 확장 속성 — [12] 판정 · 0xEC4 캡처 · 엔진과의 무관.                      *)
(*                                                                         *)
(* 각 가드의 목표 속성(삭제 cfg 가 반례를 내야 하는 것):                   *)
(*   dup_on_started_rekey → Prop_RejectedFireInert                         *)
(*   cap_first_event      → Prop_CapFirstEvent                             *)
(*   cap_clear_whole      → Inv_CapClearedZero                             *)
(*   cap_set_beats_clear  → Prop_CapSetBeatsClear                          *)
(*   cap_bitmap_exact     → Prop_CapBitmapExact                            *)
(*   cap_bitmap_domain    → Prop_CapBitmapExact (파티션 3 + VIEW)           *)
(*   start_ignores_dup    → Prop_StartGoesBusy                             *)
(*   complete_ignores_dup → Inv_BusyCanComplete                            *)
(* Prop_DupExact 는 [12] 한 비트의 전체 의미(판정 시점 · 정의역 · sticky ·  *)
(* 세움이 이김) — 특정 가드의 목표가 아니라 좋은 모델의 계약이다.           *)
(* Inv_CapIffDup 은 목표 모델에서 *구조*다(Word.on = dup — W1-4). 깨는 것은  *)
(* 짝 「오늘의 RTL」(W1 전 RTL — HEAD 3b80087) 하나이고, 가드 삭제로는          *)
(* 깨지지 않는다(측정 아님 — 구조 확인).                                  *)
(***************************************************************************)

\* [16] ⇔ [12] — 같은 세움 사건 · 같은 해제 신호 · 둘 다 세움이 이긴다.
Inv_CapIffDup == Word.on = dup

\* 캡처가 유효하지 않으면 워드 전체가 0 — reset 값 0 · 해제가 이 워드
\* ([7:0] · [15:8] 포함)를 지운다. 목표 모델에서 Word.on = dup 이므로 이것은
\* 「~dup ⇒ capPart = 0 ∧ capMap = 0」 이다 — cap_clear_whole 의 목표.
Inv_CapClearedZero == (~Word.on) => (Word = Cap0)

\* [12] 의 정확한 의미 — 「재키잉이 시작된」 발화의 수락 사이클에서 정의역
\* DupSet 이 비지 않을 때만 서고, 해제 사이클이 아니면 유지되며, 해제와 세움이
\* 겹치면 세움이 이긴다.
Prop_DupExact ==
    [][ dup' = ((ev'.kind = "start" /\ DupSet(ev'.p) # {}) \/ (dup /\ ev'.clr = "none")) ]_vars

\* 거절 + [6] 인 발화와 busy 미수락 발화는 [12] 도 0xEC4 도 *보태지* 않는다 —
\* 같은 사이클에 내부 해제선이 오면 그 해제만 일어난다(해제는 발화와 독립인
\* 입력이다). 곧 발화가 없었던 것과 같은 결과다.
Prop_RejectedFireInert ==
    [][ (ev'.kind \in {"busy", "bad"}) =>
          /\ dup' = (dup /\ ev'.clr = "none")
          /\ Word' = IF ev'.clr = "none" THEN Word ELSE Cap0 ]_vars

\* 첫 사건 보존 — 캡처가 유효하고 해제가 없는 사이클에는 워드가 그대로다.
Prop_CapFirstEvent ==
    [][ (Word.on /\ ev'.clr = "none") => (Word' = Word) ]_vars

\* 세움이 이긴다 — 해제와 같은 사이클의 「[12] 를 세우는」 시작된 발화는 그
\* 새 사건을 래치한다. 래치 *내용*의 정확성(비트맵)은 Prop_CapBitmapExact 의
\* 몫이라 여기서는 「새 사건이 래치됐다」(유효 ∧ 그 사건의 p)만 본다 — 두 가드의
\* 삭제 실험이 서로의 속성으로 새지 않게 축을 가른다.
Prop_CapSetBeatsClear ==
    [][ (ev'.kind = "start" /\ DupSet(ev'.p) # {} /\ ev'.clr # "none") =>
          (Word'.on /\ Word'.p = ev'.p) ]_vars

\* 래치 사건 — 「[12] 를 세우는」 시작된 발화가 캡처 무효 중이거나 해제와 같은
\* 사이클에 온 것. 모델의 갱신식(DupCap)과 독립으로 정본 문면에서 쓴다.
LatchEv == ev'.kind = "start" /\ DupSet(ev'.p) # {} /\ (~Word.on \/ ev'.clr # "none")

\* 래치된 내용은 그 사건의 p 와 정본 정의역의 비트맵 그대로다 (p 번 비트 0).
\* 전건 둘:
\*   (1) 필드가 바뀌어 비0 p 를 담는 모든 전이 — 래치 사건 밖의 덮어쓰기도 잡는다.
\*   (2) 래치 사건이고 래치된 p 가 그 사건의 p 인 전이 — 같은 p 로 다시 래치하며
\*       필드가 *바뀌지 않은* 경우(해제 + 발화 겹침에서 낡은 비트맵을 남기는
\*       구현)를 잡는다. (1) 만으로는 cap' = cap 이라 서지 않는다.
\* p 가 사건의 p 와 다른 래치 실패는 Prop_CapSetBeatsClear 의 몫이라 (2) 에서
\* 뺀다 — cap_set_beats_clear 삭제가 이 속성으로 새지 않게.
Prop_CapBitmapExact ==
    [][ ( (Word'.p # NoPart /\ <<Word'.p, Word'.bm>> # <<Word.p, Word.bm>>)
          \/ (LatchEv /\ Word'.p = ev'.p) )
        => (Word'.p = ev'.p /\ Word'.bm = DupSet(ev'.p)) ]_vars

\* 시작된 발화는 [12] 와 무관하게 엔진을 busy 로 보낸다 — 「완료 전까지 [8] = 1」.
Prop_StartGoesBusy ==
    [][ (ev'.kind = "start") => (phase' = "busy") ]_vars

\* busy 인 엔진은 언제나 완료할 수 있다 — 완료는 [12] 와 무관하게 온다.
Inv_BusyCanComplete == (phase = "busy") => ENABLED Complete

(***************************************************************************)
(* 위험 도달성 증인 — 좋은 모델에서 반드시 반증돼야 한다.                  *)
(***************************************************************************)

\* 키 기입이 실제로 일어나는가 — 안 일어나면 위 속성 전부가 공허하다.
Witness_NoKeyWrite == ~keyEverWritten

\* REKEY 가 실제로 수락되는가.
Witness_NoRekeyAccept == engTarget = NoPart

\* 창과 REKEY 지목 파티션이 실제로 어긋나는 시나리오가 도달 가능한가 —
\* 안 되면 rekey_explicit_target 가드 삭제 실험이 아무것도 보이지 못한다.
Witness_NoWindowTargetDrift == ~driftSeen

\* phase="busy" 중 REKEY 시도가 실제로 일어나는가 — 안 일어나면
\* rekey_idle_only 가드 삭제 실험이 그 가드를 한 번도 건드리지 못한다.
Witness_NoBusyRekeyAttempt == ~busyAttemptSeen

\* [12] 가 실제로 서는가 — 안 서면 확장 속성 전부가 공허하다.
Witness_NoDupEvent == ~dup

\* 둘째 사건 — 캡처 유효 · 해제 없음 상태에서 [12] 를 세울 시작된 발화가
\* 실재하는가. 없으면 cap_first_event 삭제 실험이 덮을 대상을 갖지 못한다.
Witness_NoSecondEvent ==
    ~(ev.kind = "start" /\ ev.hit /\ ev.held /\ ev.clr = "none")

\* 해제와 발화의 겹침 — 캡처 유효 중 내부 해제선과 같은 사이클에 [12] 를
\* 세울 시작된 발화가 실재하는가. 없으면 cap_set_beats_clear 가 공허하다.
Witness_NoClearFireOverlap ==
    ~(ev.kind = "start" /\ ev.hit /\ ev.held /\ ev.clr # "none")

\* 바쁜 발화 — 엔진 busy 중 미수락 REKEY 의 지목 파티션에 겹침이 실재하는가.
\* 없으면 dup_on_started_rekey 삭제 실험의 busy 갈래가 공허하다.
Witness_NoBusyDupAttempt == ~(ev.kind = "busy" /\ ev.hit)

\* 값 검사 거절 발화의 지목 파티션에 겹침이 실재하는가 — 거절 갈래의 같은 몫.
Witness_NoRejectedDupAttempt == ~(ev.kind = "bad" /\ ev.hit)

\* 내부 해제선이 유효한 캡처를 지우는 사이클이 실재하는가 — 없으면
\* cap_clear_whole 삭제 실험(해제가 필드를 남김)의 내부 해제선 갈래가 공허하다.
Witness_NoIoClearHeld == ~(ev.kind = "clear" /\ ev.clr = "io" /\ ev.held)

\* p 자신이 마스크 유효인 채 [12] 를 세우는 시작된 발화가 실재하는가 — 없으면
\* cap_bitmap_exact 삭제 실험(q ≠ p 누락)이 p 번 비트를 한 번도 세우지 못한다.
Witness_NoSelfValidDup == ~(ev.kind = "start" /\ ev.hit /\ ev.self)

\* 비트맵 다중 비트 — 한 사건에 겹친 파티션이 둘 이상인 캡처가 실재하는가
\* (파티션 3 이상에서만 가능 — 비트맵이 OR 하나로 접히지 않았음의 증인).
Witness_NoMultiBitmap == ~(Word.on /\ Cardinality(Word.bm) >= 2)

\* 거절 · busy 발화와 내부 해제선의 겹침 — 캡처 유효 중 실재하는가. 없으면
\* Prop_RejectedFireInert 의 해제 갈래(「해제만 일어난다」)가 공허하다.
Witness_NoRejectedClearOverlap ==
    ~(ev.kind \in {"busy", "bad"} /\ ev.clr # "none" /\ ev.held)

\* 같은 p 로의 재래치 — 캡처가 p 로 유효하고 그 비트맵이 지금의 DupSet(p) 와
\* 다를 때, 해제와 같은 사이클에 p 의 [12] 를 세우는 시작된 발화가 실재하는가.
\* 없으면 Prop_CapBitmapExact 의 전건 (2) 가 공허하다 (파티션 3 이상에서만 가능).
Witness_NoStaleRelatch ==
    ~(ev.kind = "start" /\ ev.hit /\ ev.clr # "none" /\ ev.stale)

=============================================================================
