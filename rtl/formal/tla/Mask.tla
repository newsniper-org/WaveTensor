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
EXTENDS Naturals, FiniteSets

CONSTANTS
    Parts,           \* 임대(파티션). 불투명 토큰
    KeyVals,         \* 키 값 도메인. 불투명 토큰 — 값 자체의 정확성은 SEC-1(golden) 몫
    NonceVals,       \* 논스 값 도메인. 불투명 토큰
    NoPart,          \* 「지목 없음」 표식 (모델 값)
    DisabledGuards

AllGuards == {"key_scoped_storage", "key_write_own_only",
              "rekey_idle_only", "rekey_explicit_target"}
On(g) == g \notin DisabledGuards

SomeKey   == CHOOSE k \in KeyVals   : TRUE
SomeNonce == CHOOSE n \in NonceVals : TRUE
SomePart  == CHOOSE p \in Parts     : TRUE

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
    lastWinWrite     \* 이번 전이가 *창을 거친 기입*(키 또는 논스)이었다면 그
                     \* 창 값, 아니면 NoPart. Rekey 의 maskValid 기입은 창과
                     \* 무관한 별개 authority 이므로 이 표식에 잡히지 않는다
                     \* — Prop_MaskValidScoped 가 REKEY 의 정당한 변경과
                     \* 창 기입의 스코프 위반을 가르는 데 쓴다 (아래 해설)

vars == <<key, nonce, maskValid, winPart, phase, reqPart, engTarget, engKey,
          rekeyAccepted, keyEverWritten, driftSeen, busyAttemptSeen, lastWinWrite>>

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

(***************************************************************************)
(* MASK_PART(0xEA0) 기입 — 다음 키·논스 기입의 창을 바꾼다.                *)
(* e-defined.typ:351 7항: authority 는 MASK_REKEY 하나이지 이 창이 아니다  *)
(* — 그래서 SetPart 자체는 REKEY 상태(phase/engTarget)에 아무 영향이 없다. *)
(***************************************************************************)
SetPart(p) ==
    /\ winPart' = p
    /\ lastWinWrite' = NoPart
    /\ UNCHANGED <<key, nonce, maskValid, phase, reqPart, engTarget, engKey,
                   rekeyAccepted, keyEverWritten, driftSeen, busyAttemptSeen>>

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
    /\ UNCHANGED <<nonce, winPart, phase, reqPart, engTarget, engKey,
                   rekeyAccepted, driftSeen, busyAttemptSeen>>

(***************************************************************************)
(* MASK_NONCE[0..5] 기입 — 이미 파티션별로 옳게 구현돼 있다(변경 대상       *)
(* 아님). 논스 기입도 창(winPart)이 가리키는 파티션의 유효만 떨어뜨린다 —   *)
(* 그 처분이 WriteKey 의 key_write_own_only 가 *복구해야 할* 목표 동작이다. *)
(***************************************************************************)
WriteNonce(nv) ==
    /\ nonce' = [nonce EXCEPT ![winPart] = nv]
    /\ maskValid' = [maskValid EXCEPT ![winPart] = FALSE]
    /\ lastWinWrite' = winPart
    /\ UNCHANGED <<key, winPart, phase, reqPart, engTarget, engKey,
                   rekeyAccepted, keyEverWritten, driftSeen, busyAttemptSeen>>

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
(***************************************************************************)
Rekey(p) ==
    LET idleOK == (phase = "idle") \/ ~On("rekey_idle_only")
        target == IF On("rekey_explicit_target") THEN p ELSE winPart
    IN  /\ reqPart' = p
        /\ driftSeen' = (driftSeen \/ (p # winPart))
        /\ busyAttemptSeen' = (busyAttemptSeen \/ (phase = "busy"))
        /\ IF idleOK
             THEN /\ phase' = "busy"
                  /\ engTarget' = target
                  /\ engKey' = key[target]
                  /\ rekeyAccepted' = TRUE
                  /\ maskValid' = [maskValid EXCEPT ![target] = TRUE]
             ELSE /\ rekeyAccepted' = FALSE
                  /\ UNCHANGED <<phase, engTarget, engKey, maskValid>>
        /\ lastWinWrite' = NoPart
        /\ UNCHANGED <<key, nonce, winPart, keyEverWritten>>

(***************************************************************************)
(* 엔진이 HROUND 스트림을 마치고 유휴로 돌아간다 — busy 구간의 종료.        *)
(***************************************************************************)
Complete ==
    /\ phase = "busy"
    /\ phase' = "idle"
    /\ lastWinWrite' = NoPart
    /\ UNCHANGED <<key, nonce, maskValid, winPart, reqPart, engTarget, engKey,
                   rekeyAccepted, keyEverWritten, driftSeen, busyAttemptSeen>>

Next ==
    \/ \E p \in Parts : SetPart(p)
    \/ \E kv \in KeyVals : WriteKey(kv)
    \/ \E nv \in NonceVals : WriteNonce(nv)
    \/ \E p \in Parts : Rekey(p)
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

\* e-defined.typ:333 "기입은 그 파티션의 마스크 유효를 즉시 떨어뜨린다" —
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

=============================================================================
