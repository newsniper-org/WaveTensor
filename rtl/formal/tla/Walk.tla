\* SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
\* SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
--------------------------- MODULE Walk ---------------------------
(***************************************************************************)
(* EXT-1 · EXT-2 · EXT-3 선-formal 모델 — 확장 헤더 사슬의 순회와 검산.    *)
(*                                                                         *)
(*   EXT-1 순회 종료성 — 순회는 반드시 끝난다.                             *)
(*   EXT-2 종료 이후 무효과 — 종료 표식 뒤의 슬롯은 효과를 내지 않는다.    *)
(*   EXT-3 검산의 독립성 — 검산 셋은 서로 독립이다. 어느 하나를 무력화하면 *)
(*         나머지가 그 사실을 검출한다.                                    *)
(*   ISA-5 분류 배타성 — 능력 부재는 malformation 으로 접히지 않는다       *)
(*         (§1.6.2 오류 3분류 · §4.2.2 검산 규범 2항).                     *)
(*                                                                         *)
(* ## EXT-3 은 검사들 *자신에 대한* 메타 속성이다                          *)
(*                                                                         *)
(* 앞의 모델들은 "기계가 계약을 지키는가" 를 물었다. EXT-3 은 다르다 —      *)
(* *검사가 서로를 대신하고 있지 않은가* 를 묻는다. 셋이 겹쳐 있어도 하나가  *)
(* 나머지에 함축되면 실제로는 둘뿐이고, 그 사실은 아무 테스트도 드러내지    *)
(* 않는다. 모든 테스트가 여전히 통과하기 때문이다.                         *)
(*                                                                         *)
(* 형식은 이렇게 잡는다: 각 검사를 하나씩 지웠을 때 *malformed 인 사슬이    *)
(* 통과하는가.* 지워도 아무것도 통과하지 않는다면 그 검사는 나머지에        *)
(* 함축된 것이고 — 독립이 아니다.                                          *)
(*                                                                         *)
(* 그래서 이 모델에서 네 가드(authority + 검산 셋)가 한 불변식              *)
(* (Inv_SoundVerdict)을 공유하는 것은 결함이 아니라 *증명하려는 것 그       *)
(* 자체*다. 다섯째 가드 cap_declared 는 이 게임 밖이다 — 능력 부재는        *)
(* 거절이 아니라 *별도 종결*이므로, 그 가드가 지는 불변식은                 *)
(* Inv_CapabilityNotMalformed 하나다 (아래).                               *)
(*                                                                         *)
(* ## 종료 판정은 검사가 아니라 authority 다                               *)
(*                                                                         *)
(* §4.2.2 규범이 못박는 것: "종료는 종료 표식(END)이 정한다. 길이 필드는    *)
(* *검산*이다. 슬롯 상한은 *안전장치*다."                                  *)
(*                                                                         *)
(* 즉 END 는 나머지 둘이 *무엇에 대해* 검사하는지를 정하는 기준점이지,      *)
(* 그 자신이 거절자가 아니다. 그리고 그것이 §4.2.2 함정 —                   *)
(* "셋 중 어느 하나를 종료 판정에 쓰면 나머지 둘이 검사 기능을 잃는다" —   *)
(* 의 내용 전부다. 길이를 authority 로 쓰면 길이 검산이 자기 자신을         *)
(* 검사하게 되어 항진명제가 된다.                                          *)
(*                                                                         *)
(* ## END 미출현은 순회로 구별할 수 없다 — 선언이 가른다 (§4.2.2 함정)      *)
(*                                                                         *)
(* 순회기는 자기 지평(Cap) 밖을 볼 수 없다. 상한 완주 후 END 미출현은       *)
(* 「손상(END 실종)」일 수도 「능력 밖(END 가 더 멀리 실재)」일 수도 있고,  *)
(* 순회는 둘을 구별하지 못한다. 구별 수단은 순회가 아니라 *선언*이다:       *)
(*                                                                         *)
(*   · declLen > Cap  → *능력 부재.* 판정은 순회 전에 선언만으로 선다.      *)
(*     바이너리는 옳고 이 기계가 못 받는 것이다 — 오류가 아니다 (§1.6.2 ·   *)
(*     §1.3 「최대 길이」). Payload.tla 의 capAbsent /                      *)
(*     Inv_CapabilityNotMalformed 와 같은 처분 — §4.2.2 「선언 총개수 /     *)
(*     구현 슬롯 상한」 이분의 재적용이다.                                  *)
(*   · declLen <= Cap 인데 그 안에 END 미출현 → *malformation* —            *)
(*     「들어간다」고 선언하고 실물이 아닌 자기모순 (§4.2.2 검산 규범 3항). *)
(*                                                                         *)
(* 두 조건은 서로소다 — ISA-5 가 우선순위 규정 없이 *구조로* 성립한다.      *)
(*                                                                         *)
(* ## 이 모델이 덮지 않는 것                                               *)
(*                                                                         *)
(*   ⚠️ 사슬은 초기 상태에서 통째로 정해진다 — 사슬이 순회 중에 바뀌는       *)
(*      경우(자기수정)는 없다. 명령 사슬은 읽기 전용이므로 손실이 없다.     *)
(*   ⚠️ 효과의 *내용*이 아니라 개수만 센다 — EXT-2 는 "효과가 없다" 이므로   *)
(*      개수로 족하다. 효과가 *틀린* 경우는 다른 축이다.                    *)
(*   ⚠️ EH 종류별 결합 규칙(§4.2.3)은 이 모델 밖이다.                       *)
(*   ⚠️ Cap 밖의 슬롯은 표현 불가다 — 「END 가 실재하나 지평 밖」 갈래는     *)
(*      declLen > Cap 이 대표한다. declLen > Cap 인 사슬은 잘 형성 여부와   *)
(*      *무관하게* capability 다: WellFormed 는 지평 안(EndPos \in Slots)   *)
(*      에서만 정의되므로 그런 사슬은 모델 안에서 결코 WellFormed 가 아니고,*)
(*      실세계에서 잘 형성됐을 그 사슬의 「옳음」은 verdict "capability" 가  *)
(*      malformed 로 접히지 않는다는 처분으로만 담는다.                     *)
(*   ⚠️ 상한 초과 선언의 *크기*는 판정에 안 들어간다 — 대소만 본다. 전폭     *)
(*      8비트 선언 공간의 Cap 초과 값 전부를 Cap + 1 하나가 대표한다.       *)
(*   ⚠️ 워드 축이 없다 — 슬롯·워드 축약 1:1 (DecodeWalk 의 EH 는 1~3워드     *)
(*      인데 여기서는 슬롯 하나가 워드 하나다). 인코딩 개정 파도 W8 의 CH   *)
(*      (둘째 헤더, §1.3.4)는 슬롯이 아니라 *워드*라 이 모델의 표현 밖이다: *)
(*      EH-조건부 존재(next_hdr ≠ END ⇔ word1 = CH)도, 순회 시작 오프셋의   *)
(*      1/2 갈래도, CRC-32C 재계산 대조도, bh_len 의 CH 포함 회계도 여기     *)
(*      없다 — declLen 은 이 모델에서 이미 추상 선언값이라 무개정이다.      *)
(*      CH *판정* 축의 선-formal 은 Decode.tla 의 ch 축(ch_judged 가드 —    *)
(*      같은 파도 신설)이 지고, 재계산 대조의 참·오프셋 이동의 회계 편입은  *)
(*      후-formal(walk_decode.sby 참조 모델 등가)이 잰다.                   *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS
    Cap,            \* 슬롯 상한. 고정 순회의 횟수이기도 하다 (§4.3)
    DisabledGuards

AllGuards == {"end_authority", "len_check", "cap_declared", "cap_check",
              "junk_check", "post_end_gated"}
On(g) == g \notin DisabledGuards

Slots == 1..Cap
\* eh   — 정의된 EH 종류
\* end  — 종료 표식
\* junk — 정의되지 않은 EH 종류 (§4.2.2 규범 4항: malformation)
Kinds == {"eh", "end", "junk"}

\* 선언 길이의 값 공간. Cap + 1 은 「구현 상한을 넘는 선언 전부」의 대표다 —
\* 전폭 8비트 비교(§1.3 함정)에서 판정에 쓰이는 것은 대소뿐이므로 하나로
\* 접어도 판정 공간을 잃지 않는다.
Decls == 0..(Cap + 1)

ASSUME Cap >= 2

VARIABLES
    chain,      \* [Slots -> Kinds]  읽기 전용. 초기 상태에서 정해진다
    declLen,    \* Decls  길이 필드 선언값
    pc,         \* 0..Cap  순회 위치. 고정 순회이므로 언제나 Cap 까지 간다
    ended,      \* BOOLEAN  「이미 끝났다」 표시. 효과 게이팅의 유일한 근거
    effects,    \* 0..Cap   실제로 발생한 부수 효과 수
    verdict     \* {"none", "ok", "malformed", "capability"}

vars == <<chain, declLen, pc, ended, effects, verdict>>

TypeOK ==
    /\ chain \in [Slots -> Kinds]
    /\ declLen \in Decls
    /\ pc \in 0..Cap
    /\ ended \in BOOLEAN
    /\ effects \in 0..Cap
    /\ verdict \in {"none", "ok", "malformed", "capability"}

(***************************************************************************)
(* 지상 진리 — 검사와 *무관하게* 정의된다.                                 *)
(*                                                                         *)
(* 이것이 이 모델에서 가장 중요한 한 줄이다. 적합성을 검사의 어휘로 적으면  *)
(* "검사를 통과한 것이 적합하다" 가 되어 아무것도 증명하지 못한다           *)
(* (Route.tla 의 M2 에서 실측한 자기지시 실패형).                          *)
(***************************************************************************)
EndPos ==
    IF \E i \in Slots : chain[i] = "end"
      THEN CHOOSE i \in Slots :
             chain[i] = "end" /\ \A j \in 1..(i - 1) : chain[j] # "end"
      ELSE 0

WellFormed ==
    /\ EndPos # 0                                     \* 끝이 있다
    /\ declLen = EndPos                               \* 선언과 실제가 맞는다
    /\ \A i \in 1..(EndPos - 1) : chain[i] = "eh"     \* 앞은 전부 정의된 종류

\* 능력 부재 — 지상 진리. 선언이 구현 상한을 넘는다 (§1.3 「최대 길이」 ·
\* §4.2.2 검산 규범 2항). 순회를 보지 않는다 — 선언만 본다.
CapaAbsent == declLen > Cap

(***************************************************************************)
(* authority — 순회가 「끝났다」고 보는 자리.                              *)
(*                                                                         *)
(* end_authority 를 지우면 *길이 필드*가 그 자리를 정한다. 그 순간 길이     *)
(* 검산은 declLen = declLen 이 되어 항진명제가 된다 — §4.2.2 함정이 적은    *)
(* "나머지 둘이 검사 기능을 잃는다" 가 정확히 이 형태다.                   *)
(***************************************************************************)
Authority == IF On("end_authority") THEN EndPos ELSE declLen

(***************************************************************************)
(* 능력 종결 — 거절이 아니다 (§1.6.2).                                     *)
(*                                                                         *)
(* cap_declared 는 순회 *전*의 선언 비교다. 켜져 있으면 declLen > Cap 인    *)
(* 사슬은 capability 로 종결되고 나머지 판정의 대상이 아니다 (Payload.tla   *)
(* 의 「능력 부재가 맨 앞」 과 같은 순서 — ISA-5 는 세 신호가 동시에 서지   *)
(* 않기를 요구한다). 지우면 기계에 능력이라는 개념 자체가 없어지고, 그      *)
(* 사슬은 아래 일반 거절로 흘러 malformed 로 접힌다 —                       *)
(* Inv_CapabilityNotMalformed 가 그 접힘을 잡는다.                          *)
(***************************************************************************)
CapaTerm == On("cap_declared") /\ CapaAbsent

(***************************************************************************)
(* 세 검산 (§4.2.2 검산 규범).                                             *)
(*                                                                         *)
(* ~CapaTerm 이 세 검산 전부의 전건에 있는 것이 분류 배타성의 기계 형태다 — *)
(* 좋은 기계에서 ~CapaTerm = (declLen <= Cap) 이므로 RejNoEnd 는 규범 3항의 *)
(* 서로소 형태 「declLen <= Cap /\ END 미출현」 그대로가 되고, cap_declared *)
(* 를 지우면 전건이 사라져 RejNoEnd 가 옛 「END 부재 전부 malformation」    *)
(* 으로 되접힌다 — 그 되접힘이 곧 삭제 실험의 반례다.                       *)
(***************************************************************************)
RejLen   == On("len_check")  /\ ~CapaTerm /\ Authority # 0 /\ declLen # Authority
RejNoEnd == On("cap_check")  /\ ~CapaTerm /\ EndPos = 0
RejJunk  == On("junk_check") /\ ~CapaTerm
                             /\ \E i \in 1..(Authority - 1) : chain[i] = "junk"

Rejected == RejLen \/ RejNoEnd \/ RejJunk

Init ==
    /\ chain \in [Slots -> Kinds]
    /\ declLen \in Decls
    /\ pc = 0
    /\ ended = FALSE
    /\ effects = 0
    /\ verdict = "none"

(***************************************************************************)
(* 고정 순회 (§4.3).                                                       *)
(*                                                                         *)
(* 조기 탈출이 없다 — 종료 표식을 만나도 *계속 돈다.* 멈추는 것은 순회가    *)
(* 아니라 *효과*다. 그것이 §4.3 함정의 요건이며, 상수 시간 계약의 근거다.  *)
(*                                                                         *)
(* capability 로 조기에 판정이 서도 마찬가지다 — 순회는 상한까지 완주하고   *)
(* (상태열 균일, §1.6.1 D14), 갈리는 것은 Finish 의 verdict 뿐이다.         *)
(*                                                                         *)
(* post_end_gated 를 지우면 종료 뒤의 슬롯도 효과를 낸다 — 명령의 의미가    *)
(* 사슬 뒤의 쓰레기에 의존하게 된다.                                       *)
(***************************************************************************)
Step ==
    /\ pc < Cap
    /\ pc' = pc + 1
    /\ ended' = (ended \/ chain[pc + 1] = "end")
    /\ effects' = IF (~ended \/ ~On("post_end_gated")) /\ chain[pc + 1] = "eh"
                    THEN effects + 1
                    ELSE effects
    /\ UNCHANGED <<chain, declLen, verdict>>

\* 순회가 끝난 뒤 한 번 판정한다. capability 가 맨 앞이다 — 능력이 없는
\* 사슬은 나머지 판정의 대상이 아니다 (§1.6.2 · Payload.tla 접수 순서).
Finish ==
    /\ pc = Cap
    /\ verdict = "none"
    /\ verdict' = IF CapaTerm THEN "capability"
                  ELSE IF Rejected THEN "malformed"
                  ELSE "ok"
    /\ UNCHANGED <<chain, declLen, pc, ended, effects>>

\* 판정 이후 상태는 고정이다. 종료를 모델에 명시한다.
Done == /\ pc = Cap /\ verdict # "none"
        /\ UNCHANGED vars

Next == Step \/ Finish \/ Done

Spec == Init /\ [][Next]_vars

(***************************************************************************)
(* 불변식                                                                  *)
(***************************************************************************)

\* EXT-3 그 자체 — 통과했다면 적합했고, capability 라 했다면 정말 능력 밖이다.
\* 네 가드(authority + 검산 셋)가 첫 연언지를 공유하고, 어느 하나를 지워도
\* 깨진다는 사실이 곧 *넷 모두가 독립적으로 필요하다*는 증명이다.
\* 둘째 연언지는 capability 방향의 건전성이다 — 기계가 능력 부재를 선언했다면
\* 지상 진리도 능력 부재다 (WellFormed 인 사슬은 declLen = EndPos <= Cap
\* 이므로 첫 연언지가 이미 「ok 이면 능력 안」 을 함의한다).
Inv_SoundVerdict ==
    /\ verdict = "ok" => WellFormed
    /\ verdict = "capability" => CapaAbsent

\* ISA-5 · §1.6.2 — 능력 부재는 loud 오류로 접히지 않는다.
\* 전건은 지상 진리(선언이 상한을 넘었다), 후건은 기계의 판정이다 — 두
\* 어휘가 갈려 있으므로 자기지시가 아니다 (Payload.tla
\* Inv_CapabilityNotMalformed 와 같은 문체). cap_declared 를 지우면 그런
\* 사슬이 일반 거절로 흘러 malformed 가 되고 이 불변식이 깨진다 — 접는
\* 구현은 관측자에게 *바이너리를 고치라*는 거짓 지시를 보내는 것이다.
Inv_CapabilityNotMalformed == CapaAbsent => verdict # "malformed"

\* EXT-2 — 효과 수는 종료 표식 앞의 정의된 슬롯 수와 정확히 같다.
\* 순회는 Cap 까지 갔지만 효과는 거기서 멈춰 있어야 한다.
EffectiveSlots ==
    Cardinality({ i \in Slots : i =< pc /\ chain[i] = "eh"
                                /\ (EndPos = 0 \/ i < EndPos) })
Inv_NoPostEndEffect == effects = EffectiveSlots

\* EXT-1 — 순회는 상한을 넘지 않는다. 고정 횟수이므로 종료가 구조적이다.
Inv_WalkBounded == pc =< Cap

(***************************************************************************)
(* 위험 도달성 증인 — 좋은 모델에서 반드시 반증돼야 한다.                  *)
(***************************************************************************)

\* 세 종결이 전부 실재하는가 — 어느 하나가 없으면 그 판정이 공허하다.
Witness_NoOk         == verdict # "ok"
Witness_NoMalformed  == verdict # "malformed"
\* capability 종결이 구성된 기계에서 실제로 도달하는가. 반증되지 않으면
\* Decls 를 Cap 너머로 넓힌 것이 장식이고 Inv_CapabilityNotMalformed 는
\* 전건이 비어 자명하게 참일 뿐이다.
Witness_NoCapability == verdict # "capability"

(***************************************************************************)
(* 독립성 증인 — EXT-3 의 직접 형태.                                       *)
(*                                                                         *)
(* 「이 검사 *하나만* 잡아내는 사슬이 존재하는가」. 존재하지 않으면 그       *)
(* 검사는 나머지에 함축된 것이고 독립이 아니다. 셋 다 반증돼야 한다.        *)
(* Rej* 의 전건 ~CapaTerm 때문에 capability 사슬은 이 증인들에 안 걸린다 —  *)
(* 능력 축은 거절이 아니므로 독립성 게임의 참가자가 아니다.                 *)
(***************************************************************************)
Witness_NoLenOnly  == ~(RejLen  /\ ~RejNoEnd /\ ~RejJunk)
Witness_NoCapOnly  == ~(RejNoEnd /\ ~RejLen  /\ ~RejJunk)
Witness_NoJunkOnly == ~(RejJunk /\ ~RejLen   /\ ~RejNoEnd)

\* 종료 표식 *뒤에* 슬롯이 실제로 있는가 — 없으면 post_end_gated 가 공허하다.
Witness_NoPostEndSlot ==
    \A i \in Slots : EndPos = 0 \/ i =< EndPos \/ pc < i

=============================================================================
