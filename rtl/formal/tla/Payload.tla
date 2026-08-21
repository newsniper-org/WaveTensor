\* SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
\* SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
--------------------------- MODULE Payload ---------------------------
(***************************************************************************)
(* EXT-4 선-formal 모델 — 조각 재조립의 배타성.                             *)
(*                                                                         *)
(* 정본 §4.6:                                                              *)
(*   EXT-4 재조립 배타성 — 하나의 태그에 대해 동시에 진행 중인 재조립은     *)
(*   최대 하나다. 두 번째 시작 시도는 fault 를 낸다.                       *)
(*                                                                         *)
(* 계약의 본문은 §4.3 규범 네 항이다:                                      *)
(*   1. 조각은 같은 태그를 공유한다 — 태그가 재조립의 키다.                *)
(*   2. 조각의 최대 개수에는 상한이 있다.                                  *)
(*   3. 상한 초과 · 순번 중복 · 순번 누락은 loud fault.                    *)
(*   4. 재조립 미완 상태에서 같은 태그로 새 조각열이 시작하면 loud fault —  *)
(*      *조용히 덮어쓰지 않는다.*                                          *)
(*                                                                         *)
(* 슬롯 의미론은 §2.4.1 규범이 정한 「조각별 슬롯」이다 — 조각열 하나가     *)
(* *연속한 슬롯 구간*을 차지하고, 순번이 그 구간 안의 자리를 정한다.       *)
(* 그리고 §2.4.1 규범 4항이 처분 하나를 더 못박는다: 조각 총 개수가        *)
(* *구현의 슬롯 상한*을 넘으면 malformation 이 아니라 *능력 부재*다        *)
(* (§1.6.2 오류 3분류). 이 모델은 그 둘을 갈라 적는다 — 아래 참조.         *)
(*                                                                         *)
(* ## 왜 「슬롯 점유 <= 1」 이 아니라 *재조립 결과*를 보는가                *)
(*                                                                         *)
(* 배타성을 "한 슬롯에 한 조각" 으로 적으면 그것은 가드를 다른 낱말로       *)
(* 되풀이한 것에 지나지 않는다 — Route.tla 의 M2 에서 실측한 자기지시       *)
(* 실패형이다. 배타성이 깨졌을 때 *관측되는 것*은 점유 수가 아니라         *)
(* 재조립된 내용이다: 두 조각열이 한 태그를 나눠 쓰면 완성된 구간이         *)
(* *어느 원본 조각열과도 다르다.* 그래서 이 모델은 결과를 본다.            *)
(*                                                                         *)
(* ## NoLoss.tla 가 덮지 못한 축이 여기다                                  *)
(*                                                                         *)
(* NoLoss.tla 머리가 명시적으로 남긴 공백: "요청에 정체성이 없다 — 개수만   *)
(* 센다. 'A 가 사라지고 B 가 두 번 완료됐다' 는 보존 등식을 만족하므로 그   *)
(* 모델은 보지 못한다." 이 모델은 조각에 *정체성*을 준다. 슬롯에 들어간     *)
(* 것은 값이 아니라 *어느 조각열의 조각인가*이며, 회계가 아니라 귀속을      *)
(* 검사한다.                                                               *)
(*                                                                         *)
(* ## 지상 진리와 기계 상태를 가른다                                       *)
(*                                                                         *)
(*   지상 진리 (생산자 측): runTag — 어느 조각열이 어느 태그를 겨냥하는가   *)
(*                          total  — 그 조각열이 선언한 조각 총 개수        *)
(*                          sent   — 그 조각열이 실제로 무엇을 내보냈는가   *)
(*   기계 상태 (재조립 측): slots · pend · ctx* · out · faultBit · capAbsent*)
(*                                                                         *)
(* 불변식은 두 어휘를 *잇는다* — 기계가 내놓은 구간(out)이 생산자가 실제로  *)
(* 완주한 조각열 하나와 일치하는가. 가드는 기계 어휘로만 적혀 있으므로      *)
(* 불변식이 가드를 되풀이하지 않는다.                                      *)
(*                                                                         *)
(* ## 재조립 문맥은 태그로 *색인되지 않는다* — 그것이 검사 대상이다         *)
(*                                                                         *)
(* 1차 판은 base/fill/owner 를 태그마다 하나씩 두었다. 그러면 EXT-4 의      *)
(* *문면*("한 태그에 진행 중인 재조립은 최대 하나")이 구조적으로 참이 되어  *)
(* 한 번도 시험되지 않는다 — 어떤 가드를 지워도 한 태그에 문맥이 둘 생길    *)
(* 수 없기 때문이다. §4.3 규범 1(「태그가 재조립의 키다」)을 어기는 구현 —  *)
(* 문맥을 소스 포트나 자유 풀로 색인하고 두 문맥이 같은 태그를 서비스하는   *)
(* 구현 — 이 그 모델에는 보이지 않았다.                                    *)
(*                                                                         *)
(* 그래서 문맥을 유한 풀 Ctxs 로 올리고 ctxTag 를 변수로 두었다. key_is_tag *)
(* 가드가 §4.3 규범 1 그 자체이며, 지우면 한 태그를 두 문맥이 서비스하고    *)
(* *조용한 덮어쓰기*가 일어난다 — §4.3 함정이 참조 구현에서 실측한          *)
(* 「같은 태그의 새 조각이 도착하면 조용히 마지막 것이 이긴다」 바로 그것.  *)
(* Route.tla 의 M3(뷰가 변수가 아니라 정의)와 같은 처분이다.               *)
(*                                                                         *)
(* ## 구간 시작(base)은 정의가 아니라 *변수*다                             *)
(*                                                                         *)
(* 같은 이유로 구간 시작도 정의가 아니라 문맥의 상태다. Base(t) 를 정의로   *)
(* 두면 §2.4.1 이 "구간의 시작은 LBID 가 지목한다" 로 정한 사상이 어긋나는  *)
(* 일이 *정의상 불가능*해진다. base_from_tag 가 그 사상이고, 지우면 문맥이  *)
(* 엉뚱한 자리를 구간 시작으로 잡는다.                                     *)
(*                                                                         *)
(* ## 회계와 데이터 기입을 쪼갠다                                          *)
(*                                                                         *)
(* 실제 RTL 에서 slots(데이터) · ctxFill(개수) · ctxSeen(수신 기록) 은 서로 *)
(* 다른 레지스터이고 서로 다른 write enable 을 갖는다. 한 동작으로 적으면   *)
(* "회계는 진행했는데 칸은 아직 비었다" 가 표현 불가능해지고, 지울 가드가   *)
(* 없으므로 삭제 실험이 그 축을 영원히 못 본다 — NoLoss.tla 의             *)
(* advance_atomic 이 처분한 것과 같은 형태다. write_atomic 이 그 가드다.   *)
(*                                                                         *)
(* ## 태그 재사용 축은 정본이 *열어 둔* 갈래다                             *)
(*                                                                         *)
(* §4.3 규범 4의 전건이 "재조립이 완료되지 않은 채" 이므로, 완료된 뒤       *)
(* 같은 태그로 새 조각열이 오는 것은 fault 대상에서 제외된 — 즉 적법하게    *)
(* 남겨 둔 — 갈래다. 그 갈래를 닫아 두면(Send 에 ~outValid 를 걸고 outValid *)
(* 를 절대 내리지 않으면) 그 갈래의 대표 결함형인 *재조립 회계 미초기화*    *)
(* (낡은 구간을 새 결과로 다시 내보냄)가 도달 불가가 된다. Consume 이 태그를*)
(* 해방하고 reset_on_deliver 가 회계를 비운다.                             *)
(*                                                                         *)
(* 그리고 그 결함형은 Inv_ReassemblyExclusive 가 *잡지 못한다* — Faithful 의*)
(* \E r 이 "어떤 조각열 하나와 일치하면 참" 이므로 같은 구간이 두 번        *)
(* 내보내져도 매번 그 조각열이 증인이 된다. Inv_NoStaleRedeliver 가 그      *)
(* 공백을 메운다.                                                          *)
(*                                                                         *)
(* ## 오류 3분류를 접지 않는다 (§1.6.2 · §2.4.1 규범 4 · §4.5 규범)        *)
(*                                                                         *)
(* SlotCap 은 *구현 파라미터*(한 구간의 물리 칸 수)이고 total[r] 은 조각열이*)
(* *선언한* 총개수다. 둘을 한 상수로 겸하게 하면 §4.3 규범 2·3 이 지목한    *)
(* "총개수 자체가 상한을 넘는 조각열" 이 표현 자체가 불가능해진다.         *)
(* 갈라 두면 처분도 갈린다:                                                *)
(*   - 순번 s > total[r]           → loud fault (§4.3 규범 3)              *)
(*   - total[r] > SlotCap          → *능력 부재* (§2.4.1 규범 4 · §4.5)     *)
(* 능력 부재를 loud fault 로 접는 구현은 Inv_CapabilityNotMalformed 를      *)
(* 위반한다. 정본 두 절이 같은 사건에 다른 처분을 적고 있다는 사실 자체는   *)
(* 정본 환류 대상이며 아래 「덮지 않는 것」에 다시 적는다.                  *)
(*                                                                         *)
(* ## 이 모델이 덮지 않는 것                                               *)
(*                                                                         *)
(*   ⚠️ *조각 순번·총개수를 나르는 채널이 정본에 없다.* §4.3 정의와 §2.6     *)
(*      규범은 "각 조각은 순번과 총 개수를 나른다" 고 적지만, §1.5 태그      *)
(*      레이아웃(80b = wave 32 / 스레드 ID 16 / LNID 16 / 정밀도 8 /        *)
(*      차원 8)에 그런 필드가 없고 부록 E 아홉 항(E.1~E.9)도 그 채널을      *)
(*      정의하지 않는다. 이 모델은 순번 s 와 총개수 total[r] 이 조각과       *)
(*      함께 도착한다고 *가정*한다 — 모델이 조용히 메운 공백이며 정본 환류   *)
(*      대상이다.                                                          *)
(*   ⚠️ *「순번 누락」이 loud fault 로 표현되지 않는다.* §4.3 규범 3은 셋을   *)
(*      나란히 적지만 — 상한 초과 · 순번 중복 · 순번 누락 — 앞의 둘은        *)
(*      조각 *도착 시점*에 판정 가능한 반면 누락은 그렇지 않다. 누락을        *)
(*      선언하려면 「조각열이 끝났다」는 시점이 있어야 하는데 *정본에 그      *)
(*      시점이 정의돼 있지 않다.* (부록 E.3 이 타임아웃을 "조용한 실패의     *)
(*      다른 이름" 이라 기각한 것은 *HIU 변환표 미적중 채움*에 대한 규범이지 *)
(*      조각 재조립에 대한 규범이 아니다 — 다른 표면의 규범을 이식하면 안   *)
(*      된다.) 이 모델에서 누락은 ctxFill 이 total 에 못 미쳐 *조용히        *)
(*      멈추는* 것으로만 나타난다 — 정본 환류 대상이다.                     *)
(*      (중복이 개수를 부풀려 구멍을 채운 것처럼 보이게 하는 경우는          *)
(*       no_dup_seq 가 덮는다. 덮이는 것은 그 합성뿐이다.)                   *)
(*   ⚠️ 배압·무손실(§2.6)은 이 모델 밖이다 — SEC-3(NoLoss.tla)의 몫이다.     *)
(*      여기서 거절된 조각은 회계에 남지만 재전송되지 않는다. 문맥 풀이      *)
(*      고갈되면 Send 가 발화하지 않고 조용히 멈춘다 — 그 무처분도 SEC-3 의  *)
(*      몫이다. (ASSUME Cardinality(Ctxs) >= NumTags 가 key_is_tag 아래에서  *)
(*      그 고갈을 배제한다.)                                                *)
(*   ⚠️ *능력 부재의 처분에 대해 정본 두 절이 충돌한다.* §4.3 규범 3은        *)
(*      "상한을 넘는 조각열 … loud fault" 이고 §2.4.1 규범 4는 "구현의       *)
(*      슬롯 상한을 넘으면 능력 부재 — malformation 이 아니다" 이다. 이      *)
(*      모델은 두 「상한」을 서로 다른 것(total[r] 과 SlotCap)으로 *읽어*     *)
(*      충돌을 회피했다. 그 독법이 정본의 뜻인지는 확인되지 않았다 —        *)
(*      정본 환류 대상이다.                                                 *)
(*   ⚠️ 조각의 *날조*(생산자가 보내지 않은 조각이 슬롯에 나타남)는 표현      *)
(*      가능하지만 그것을 막는 가드가 없다 — 삭제 실험이 이 축을 시험하지    *)
(*      않는다. sent 를 불변식에 넣은 것은 표현 가능성을 위해서이지          *)
(*      가드 검증을 위해서가 아니다.                                        *)
(*   ⚠️ 조각열이 *선언한* 총개수와 *실제로 보낸* 개수의 불일치를 기계가      *)
(*      판정하지 않는다. total[r] 은 지상 진리이자 기계가 믿는 값이며,       *)
(*      둘을 가르는 축(선언 위조)은 여기 없다.                              *)
(*   ⚠️ out 은 완료 시점의 *스냅숏*이다. 인도 후에 구간이 변하는 것          *)
(*      (늦은 WriteBack 은 제외 — 그것은 write_atomic 이 덮는다)을 관측하지  *)
(*      않는다. 정본에 「인도 후 구간의 지위」가 없어 무엇을 관측해야 할지가  *)
(*      정해져 있지 않기 때문이다.                                          *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS
    NumTags,        \* 태그 수. 슬롯 구간이 이웃하려면 2 이상이어야 한다
    Runs,           \* 조각열 — 불투명 토큰(모델 값). 내부 구조가 없다
    Ctxs,           \* 재조립 문맥 풀 — 불투명 토큰. *태그로 색인하지 않는다*
    SlotCap,        \* 구현의 슬롯 상한 = 한 구간의 물리 칸 수 (§2.4.1·§4.5)
    MaxSend,        \* 유한화를 위한 총 전송 상한. 모델 유한성의 유일한 목적
    NoR,            \* 「조각 없음」 / 「소유자 없음」 표식 (모델 값)
    NoT,            \* 「이 문맥은 비어 있다」 표식 (모델 값)
    DisabledGuards

AllGuards == {"cap_check", "capability_check", "capability_not_fault",
              "no_restart", "no_dup_seq", "loud_reject", "base_from_tag",
              "key_is_tag", "reset_on_deliver", "write_atomic"}
On(g) == g \notin DisabledGuards

Tags   == 1..NumTags
\* 선언 총개수. SlotCap + 1 은 *구현 상한을 넘는 조각열*이며 §2.4.1 규범 4가
\* 「능력 부재」로 처분하라고 못박은 값이다. 2 부터인 이유는 총개수 1 이면
\* 재조립의 「미완 상태」가 존재하지 않아 §4.3 규범 4가 공허해지기 때문이다.
Totals == 2..(SlotCap + 1)
\* 순번은 상한을 *넘을 수 있다.* 넘는 순번이 도착하는 것이 §4.3 규범 3의
\* 전건이므로, 순번 공간을 1..SlotCap 로 좁히면 cap_check 가 막을 것 자체가
\* 표현 불가능해진다 (ResultBank 의 방어적 캡 실패형).
Seqs   == 1..(SlotCap + 1)
\* 마지막 슬롯 하나는 *구간 밖으로 넘친 기입*이 착지할 자리다. 이 자리가
\* 없으면 마지막 태그의 상한 초과 기입이 표현 불가능해진다.
SlotIx == 1..(NumTags * SlotCap + 1)

\* 슬롯 색인이 *어느 구간에 속하는가* — 순수 산술이며 기계 상태를 안 본다.
WindowOf(k) == ((k - 1) \div SlotCap) + 1

\* 구간이 슬롯 배열 밖으로 나가지 않게 하는 범위. 넘침 슬롯 한 칸까지 허용한다.
BaseRange == 0..((NumTags - 1) * SlotCap)

(***************************************************************************)
(* 축퇴 배제 (§6.7 형상 sweep).                                            *)
(*                                                                         *)
(* *주석만 있고 ASSUME 이 없는 축퇴 배제는 배제가 아니다.* 1차 판은 세      *)
(* 축퇴를 주석에 나란히 적고 ASSUME 은 둘만 두었고, 강제되지 않은 축퇴      *)
(* (|Runs| = 1) 에서 no_restart 삭제가 *조용히 통과했다* — Route.tla 가     *)
(* B2 로 기록한 것과 문자 그대로 같은 실패형이다. 여기 적는 축퇴는 전부     *)
(* ASSUME 으로 강제한다.                                                   *)
(***************************************************************************)
\* NumTags = 1 이면 구간 밖 기입이 이웃을 침범할 수 없어 cap_check 가 공허.
ASSUME NumTags >= 2
\* |Runs| = 1 이면 같은 태그에 두 조각열이 겹칠 수 없어 no_restart 가 공허.
ASSUME Cardinality(Runs) >= 2
\* |Ctxs| = 1 이면 한 태그를 두 문맥이 서비스할 수 없어 key_is_tag 가 공허.
ASSUME Cardinality(Ctxs) >= 2
\* key_is_tag 아래에서 태그마다 문맥이 최대 하나이므로, 문맥 수가 태그 수
\* 이상이면 문맥 고갈이 일어나지 않는다. 고갈은 이 모델의 계약이 아니다.
ASSUME Cardinality(Ctxs) >= NumTags
\* SlotCap = 1 이면 재조립이 한 조각으로 끝나 「미완 상태」가 존재하지 않고,
\* Totals = 2..2 가 되어 능력 부재 축과 정상 축이 겹친다.
ASSUME SlotCap >= 2
\* 한 태그에서 재조립이 두 번 일어날 수 있어야 태그 재사용 축이 도달 가능하다.
ASSUME MaxSend >= 2 * SlotCap

VARIABLES
    runTag,     \* [Runs -> Tags]      지상 진리. 초기 상태에서 정해지고 안 바뀐다
    total,      \* [Runs -> Totals]    지상 진리. 조각열이 선언한 조각 총 개수
    sent,       \* [Runs -> SUBSET Seqs]  지상 진리. 생산자가 실제로 내보낸 것
    slots,      \* [SlotIx -> Runs \cup {NoR}]  기계. 각 자리에 *누구의* 조각이
    pend,       \* [SlotIx -> Runs \cup {NoR}]  기계. 접수됐으나 아직 안 착지한 기입
    ctxTag,     \* [Ctxs -> Tags \cup {NoT}]  문맥이 서비스하는 태그. *변수다*
    ctxBase,    \* [Ctxs -> BaseRange]  문맥이 잡은 구간 시작. *정의가 아니라 변수다*
    ctxSeen,    \* [Ctxs -> SUBSET Seqs]  문맥이 이미 받은 순번 (중복 판정 근거)
    ctxFill,    \* [Ctxs -> 0..MaxSend]  문맥이 세는 접수 개수 (완료 판정 근거)
    ctxOwner,   \* [Ctxs -> Runs \cup {NoR}]  문맥이 기억하는 진행 중 조각열
    outValid,   \* [Tags -> BOOLEAN]  재조립 완료 선언
    out,        \* [Tags -> [1..SlotCap -> Runs \cup {NoR}]]  완료 시점의 구간 스냅숏
    sends,      \* 0..MaxSend  전송 횟수. 유한화용
    rejCap,     \* 유령 변수 — 순번 상한 초과로 거절된 수
    rejRestart, \* 유령 변수 — 재시작 충돌로 거절된 수
    rejDup,     \* 유령 변수 — 순번 중복으로 거절된 수
    rejCapa,    \* 유령 변수 — *능력 부재*로 거절된 수 (§2.4.1 규범 4)
    accSince,   \* 유령 변수 — [Tags -> BOOLEAN] 태그가 해방된 뒤 접수가 있었는가
    dlvT,       \* 유령 변수 — [Tags -> 0..MaxSend] 그 태그가 몇 번 완료됐는가
    faultBit,   \* 기계가 세우는 sticky loud fault 비트 (§4.3 「loud fault」)
    capAbsent   \* 기계가 세우는 sticky *능력 부재* 신호 (§1.6.2 — fault 가 아니다)

vars == <<runTag, total, sent, slots, pend, ctxTag, ctxBase, ctxSeen, ctxFill,
          ctxOwner, outValid, out, sends, rejCap, rejRestart, rejDup, rejCapa,
          accSince, dlvT, faultBit, capAbsent>>

TypeOK ==
    /\ runTag \in [Runs -> Tags]
    /\ total \in [Runs -> Totals]
    /\ sent \in [Runs -> SUBSET Seqs]
    /\ slots \in [SlotIx -> Runs \cup {NoR}]
    /\ pend \in [SlotIx -> Runs \cup {NoR}]
    /\ ctxTag \in [Ctxs -> Tags \cup {NoT}]
    /\ ctxBase \in [Ctxs -> BaseRange]
    /\ ctxSeen \in [Ctxs -> SUBSET Seqs]
    \* ctxFill 을 total 로 캡하지 *않는다.* 캡하면 no_dup_seq 를 지웠을 때
    \* 생기는 과잉 계수가 표현 불가능해지고, 삭제 실험이 조용히 통과한다.
    \* 그리고 ctxFill 을 Cardinality(ctxSeen) 으로 *정의*해도 같은 일이
    \* 일어난다 — 집합은 두 번 셀 수 없기 때문이다. 그래서 둘을 따로 둔다.
    /\ ctxFill \in [Ctxs -> 0..MaxSend]
    /\ ctxOwner \in [Ctxs -> Runs \cup {NoR}]
    /\ outValid \in [Tags -> BOOLEAN]
    /\ out \in [Tags -> [1..SlotCap -> Runs \cup {NoR}]]
    /\ sends \in 0..MaxSend
    /\ rejCap \in 0..MaxSend
    /\ rejRestart \in 0..MaxSend
    /\ rejDup \in 0..MaxSend
    /\ rejCapa \in 0..MaxSend
    /\ accSince \in [Tags -> BOOLEAN]
    /\ dlvT \in [Tags -> 0..MaxSend]
    /\ faultBit \in BOOLEAN
    /\ capAbsent \in BOOLEAN

Init ==
    /\ runTag \in [Runs -> Tags]
    /\ total \in [Runs -> Totals]
    /\ sent = [r \in Runs |-> {}]
    /\ slots = [k \in SlotIx |-> NoR]
    /\ pend = [k \in SlotIx |-> NoR]
    /\ ctxTag = [c \in Ctxs |-> NoT]
    /\ ctxBase = [c \in Ctxs |-> 0]
    /\ ctxSeen = [c \in Ctxs |-> {}]
    /\ ctxFill = [c \in Ctxs |-> 0]
    /\ ctxOwner = [c \in Ctxs |-> NoR]
    /\ outValid = [t \in Tags |-> FALSE]
    /\ out = [t \in Tags |-> [i \in 1..SlotCap |-> NoR]]
    /\ sends = 0
    /\ rejCap = 0
    /\ rejRestart = 0
    /\ rejDup = 0
    /\ rejCapa = 0
    /\ accSince = [t \in Tags |-> FALSE]
    /\ dlvT = [t \in Tags |-> 0]
    /\ faultBit = FALSE
    /\ capAbsent = FALSE

(***************************************************************************)
(* 문맥 선택 — §4.3 규범 1 「태그가 재조립의 키다」 가 사는 자리.           *)
(*                                                                         *)
(* key_is_tag 를 켜 두면 새 문맥을 여는 것은 *그 태그를 서비스하는 문맥이   *)
(* 하나도 없을 때뿐*이다. 지우면 기계가 태그가 아닌 다른 것(소스 포트,     *)
(* 자유 문맥 풀)으로 문맥을 색인하게 되고, 한 태그를 두 문맥이 서비스한다. *)
(***************************************************************************)
Serves(c, t) == ctxTag[c] = t
Free(c)      == ctxTag[c] = NoT
TagHeld(t)   == \E d \in Ctxs : ctxTag[d] = t

CtxUsable(r, c) ==
    \/ Serves(c, runTag[r])
    \/ /\ Free(c)
       /\ (~On("key_is_tag")) \/ (~TagHeld(runTag[r]))

(***************************************************************************)
(* 접수 검사 — §4.3 규범 2·3·4 와 §2.4.1 규범 4를 기계 어휘로 적은 것.      *)
(*                                                                         *)
(* 순서가 있다: 능력 → 상한 → 재시작 → 중복.                               *)
(*                                                                         *)
(* *능력 부재가 맨 앞*인 이유는 §1.6.2 가 세 신호를 서로 다른 것으로 못박고 *)
(* ISA-5 가 「동시에 서지 않는다」를 요구하기 때문이다. 능력이 없는 조각열은*)
(* 애초에 이 기계에서 재조립되지 않으므로 나머지 판정의 대상이 아니다.     *)
(*                                                                         *)
(* cap_check 를 켜 두면 구간 밖 색인이 중복 검사에 들어가지 않는다. 지우면  *)
(* 들어가고, 그때 *이웃 구간의* 자리를 보게 된다 — 그 어긋남이 구간 침범의  *)
(* 실제 형태다.                                                            *)
(***************************************************************************)
NoCapacity(r)      == total[r] > SlotCap
OverLimit(r, s)    == s > total[r]
RestartClash(r, c) == ctxOwner[c] # NoR /\ ctxOwner[c] # r
DupSeq(c, s)       == s \in ctxSeen[c]

CapaRej(r)         == On("capability_check") /\ NoCapacity(r)
CapRej(r, s)       == (~CapaRej(r)) /\ On("cap_check") /\ OverLimit(r, s)
RestartRej(r, c)   == (~CapaRej(r)) /\ On("no_restart") /\ RestartClash(r, c)
DupRej(r, c, s)    == /\ ~CapaRej(r)
                      /\ ~CapRej(r, s)
                      /\ On("no_dup_seq")
                      /\ DupSeq(c, s)

\* Send 의 전제 — Idle 이 이것의 부정을 쓰므로 두 곳이 어긋나지 않게 한 곳에 둔다.
SendPre(r, c) ==
    /\ sends < MaxSend
    /\ ~outValid[runTag[r]]
    /\ CtxUsable(r, c)

(***************************************************************************)
(* 조각 도착.                                                              *)
(*                                                                         *)
(* 생산자는 *적대적*이다 — 아무 순번이나 몇 번이든 보낸다. 검사받는 것은    *)
(* 생산자가 아니라 재조립 기계다.                                          *)
(*                                                                         *)
(*   cap_check           지우면 구간 밖에 기입한다 → 이웃 재조립을 침범     *)
(*   capability_check    지우면 능력 밖 조각열을 받아 구간을 넘친다         *)
(*   capability_not_fault 지우면 능력 부재를 malformation 으로 접는다       *)
(*   base_from_tag       지우면 구간 시작이 태그와 어긋난다                 *)
(*   key_is_tag          지우면 한 태그를 두 문맥이 서비스한다 → 조용한 덮어씀*)
(*   no_restart          지우면 두 조각열이 한 문맥을 나눠 쓴다 → 섞인 결과 *)
(*   no_dup_seq          지우면 같은 자리를 두 번 세고 구간에 구멍이 남는다 *)
(*   loud_reject         지우면 거절이 흔적을 안 남긴다 → 조용한 드롭       *)
(*   write_atomic        지우면 회계만 진행하고 데이터가 늦게 착지한다      *)
(*                                                                         *)
(* b 는 *문맥을 새로 열 때* 잡는 구간 시작이다. base_from_tag 가 켜져 있으면*)
(* 태그가 지목한 자리 하나만 통과한다.                                     *)
(***************************************************************************)
Send(r, s, c, b) ==
    /\ SendPre(r, c)
    /\ LET t  == runTag[r]
           bb == IF Free(c) THEN b ELSE ctxBase[c]
           k  == bb + s
           ra == CapaRej(r)
           rc == CapRej(r, s)
           rr == RestartRej(r, c)
           rd == DupRej(r, c, s)
       IN /\ (~Free(c)) \/ (~On("base_from_tag")) \/ (b = (t - 1) * SlotCap)
          \* 문맥을 새로 열지 않는 경우 b 는 쓰이지 않으므로 하나로 고정한다
          \* — 그러지 않으면 같은 전이가 |BaseRange| 번 중복 열거된다.
          /\ (Free(c)) \/ (b = 0)
          /\ IF ra \/ rc \/ rr \/ rd
               THEN \* 거절. 처분이 갈린다 — 능력 부재는 fault 가 아니다.
                    /\ rejCapa' = (IF ra THEN rejCapa + 1 ELSE rejCapa)
                    /\ rejCap' = (IF rc THEN rejCap + 1 ELSE rejCap)
                    /\ rejRestart' = (IF rr /\ ~rc THEN rejRestart + 1 ELSE rejRestart)
                    /\ rejDup' = (IF rd /\ ~rr THEN rejDup + 1 ELSE rejDup)
                    /\ capAbsent' = (IF ra /\ On("loud_reject") THEN TRUE ELSE capAbsent)
                    /\ faultBit' =
                         CASE (rc \/ rr \/ rd) /\ On("loud_reject") -> TRUE
                           [] ra /\ ~On("capability_not_fault")     -> TRUE
                           [] OTHER                                  -> faultBit
                    /\ UNCHANGED <<slots, pend, ctxTag, ctxBase, ctxSeen,
                                   ctxFill, ctxOwner, accSince>>
               ELSE \* 접수. 자리에 *조각열의 정체성*을 남긴다.
                    /\ ctxTag' = [ctxTag EXCEPT ![c] = t]
                    /\ ctxBase' = [ctxBase EXCEPT ![c] = bb]
                    /\ ctxSeen' = [ctxSeen EXCEPT ![c] = @ \cup {s}]
                    /\ ctxFill' = [ctxFill EXCEPT ![c] = IF @ < MaxSend THEN @ + 1 ELSE @]
                    /\ ctxOwner' = [ctxOwner EXCEPT ![c] = r]
                    /\ accSince' = [accSince EXCEPT ![t] = TRUE]
                    \* 회계와 데이터 기입이 갈리는 자리.
                    /\ IF On("write_atomic")
                         THEN /\ slots' = [slots EXCEPT ![k] = r]
                              /\ UNCHANGED pend
                         ELSE /\ pend' = [pend EXCEPT ![k] = r]
                              /\ UNCHANGED slots
                    /\ UNCHANGED <<rejCap, rejRestart, rejDup, rejCapa,
                                   faultBit, capAbsent>>
    /\ sends' = sends + 1
    /\ sent' = [sent EXCEPT ![r] = @ \cup {s}]
    /\ UNCHANGED <<runTag, total, outValid, out, dlvT>>

\* 늦게 착지하는 데이터 기입. write_atomic 이 켜져 있으면 pend 가 늘 비어
\* 있으므로 이 액션은 발화하지 않는다 — 좋은 모델은 1차 판과 같은 기계다.
WriteBack(k) ==
    /\ pend[k] # NoR
    /\ slots' = [slots EXCEPT ![k] = pend[k]]
    /\ pend' = [pend EXCEPT ![k] = NoR]
    /\ UNCHANGED <<runTag, total, sent, ctxTag, ctxBase, ctxSeen, ctxFill,
                   ctxOwner, outValid, out, sends, rejCap, rejRestart, rejDup,
                   rejCapa, accSince, dlvT, faultBit, capAbsent>>

(***************************************************************************)
(* 재조립 완료 — 기계가 「다 모였다」고 판단하는 유일한 지점.              *)
(*                                                                         *)
(* 판단 근거는 *문맥이 센 개수*(ctxFill)다. 슬롯을 훑어 세지 않는다 — 훑어  *)
(* 세면 구멍 있는 구간이 완성으로 판정되는 일이 구조적으로 불가능해지고,    *)
(* 그러면 no_dup_seq · write_atomic 삭제 실험이 조용히 통과한다.           *)
(***************************************************************************)
DeliverPre(c) ==
    /\ ctxTag[c] # NoT
    /\ ctxOwner[c] # NoR
    /\ ~outValid[ctxTag[c]]
    /\ ctxFill[c] >= total[ctxOwner[c]]

Deliver(c) ==
    /\ DeliverPre(c)
    /\ LET t == ctxTag[c]
       IN /\ outValid' = [outValid EXCEPT ![t] = TRUE]
          /\ out' = [out EXCEPT ![t] = [i \in 1..SlotCap |-> slots[ctxBase[c] + i]]]
          /\ dlvT' = [dlvT EXCEPT ![t] = IF @ < MaxSend THEN @ + 1 ELSE @]
    /\ UNCHANGED <<runTag, total, sent, slots, pend, ctxTag, ctxBase, ctxSeen,
                   ctxFill, ctxOwner, sends, rejCap, rejRestart, rejDup,
                   rejCapa, accSince, faultBit, capAbsent>>

(***************************************************************************)
(* 소비 — 소비자가 결과를 가져가면 그 태그가 다시 쓸 수 있게 된다.         *)
(*                                                                         *)
(* §4.3 규범 4의 전건이 「재조립이 완료되지 않은 채」이므로 완료 후 같은     *)
(* 태그의 재사용은 정본이 *fault 대상에서 제외한* 갈래다. 그 갈래를 열지    *)
(* 않으면 그 갈래의 대표 결함형(재조립 회계 미초기화)이 도달 불가가 된다.  *)
(*                                                                         *)
(* reset_on_deliver 를 지우면 문맥의 회계(순번 기록·개수·소유자)와 구간이   *)
(* 그대로 남아, 새 조각이 하나도 오지 않았는데 같은 구간이 다시 결과로      *)
(* 나간다. Inv_ReassemblyExclusive 는 그것에 눈이 멀다 — Faithful 의 \E r 이 *)
(* 매번 같은 조각열을 증인으로 삼기 때문이다. Inv_NoStaleRedeliver 의 몫.  *)
(***************************************************************************)
InWindow(c, k) == k > ctxBase[c] /\ k <= ctxBase[c] + SlotCap

Consume(t) ==
    /\ outValid[t]
    /\ outValid' = [outValid EXCEPT ![t] = FALSE]
    /\ accSince' = [accSince EXCEPT ![t] = FALSE]
    /\ IF On("reset_on_deliver")
         THEN /\ ctxTag' = [c \in Ctxs |-> IF ctxTag[c] = t THEN NoT ELSE ctxTag[c]]
              /\ ctxSeen' = [c \in Ctxs |-> IF ctxTag[c] = t THEN {} ELSE ctxSeen[c]]
              /\ ctxFill' = [c \in Ctxs |-> IF ctxTag[c] = t THEN 0 ELSE ctxFill[c]]
              /\ ctxOwner' = [c \in Ctxs |-> IF ctxTag[c] = t THEN NoR ELSE ctxOwner[c]]
              /\ slots' = [k \in SlotIx |->
                             IF \E c \in Ctxs : ctxTag[c] = t /\ InWindow(c, k)
                               THEN NoR ELSE slots[k]]
         ELSE UNCHANGED <<ctxTag, ctxSeen, ctxFill, ctxOwner, slots>>
    /\ UNCHANGED <<runTag, total, sent, pend, ctxBase, out, sends, rejCap,
                   rejRestart, rejDup, rejCapa, dlvT, faultBit, capAbsent>>

(***************************************************************************)
(* 종료를 모델에 명시한다 — CHECK_DEADLOCK 을 끄지 않기 위해서다.          *)
(* 세 Can* 는 각 액션의 전제를 *그대로* 쓴다. 따로 적으면 어긋나고, 어긋나면*)
(* TLC 가 정당한 종료를 교착으로 보고해 판정이 흐려진다.                   *)
(***************************************************************************)
CanSend    == \E r \in Runs, c \in Ctxs : SendPre(r, c)
CanWrite   == \E k \in SlotIx : pend[k] # NoR
CanDeliver == \E c \in Ctxs : DeliverPre(c)
CanConsume == \E t \in Tags : outValid[t]

Idle == ~CanSend /\ ~CanWrite /\ ~CanDeliver /\ ~CanConsume /\ UNCHANGED vars

Next ==
    \/ \E r \in Runs, s \in Seqs, c \in Ctxs, b \in BaseRange : Send(r, s, c, b)
    \/ \E k \in SlotIx : WriteBack(k)
    \/ \E c \in Ctxs : Deliver(c)
    \/ \E t \in Tags : Consume(t)
    \/ Idle

Spec == Init /\ [][Next]_vars

(***************************************************************************)
(* 불변식                                                                  *)
(***************************************************************************)

(***************************************************************************)
(* EXT-4 그 자체 — 재조립된 구간은 *하나의* 조각열과 일치한다.             *)
(*                                                                         *)
(* 「일치」의 내용 넷:                                                     *)
(*   - 그 조각열이 이 태그를 겨냥했다        (runTag — 지상 진리)          *)
(*   - 그 조각열이 이 기계의 능력 안에 있다   (total  — 지상 진리)          *)
(*   - 그 조각열이 실제로 전부 내보냈다      (sent   — 지상 진리)          *)
(*   - 구간의 앞 total 칸이 전부 그 조각열 것이고 나머지는 비어 있다        *)
(*                                          (out    — 기계가 내놓은 것)    *)
(*                                                                         *)
(* 섞이면 넷째가, 구멍이 나면 넷째가(NoR 는 어느 조각열도 아니다), 데이터가 *)
(* 늦으면 넷째가, 날조되면 셋째가 깨진다. 어느 경우든 "결과가 어느 원본과도 *)
(* 다르다".                                                                *)
(*                                                                         *)
(* 꼬리 칸(total[r]+1 .. SlotCap)이 NoR 이어야 한다는 조건은 *구간 길이가   *)
(* 조각 총 개수*라는 §2.4.1 규범 2항의 형식이다 — 남의 조각이 꼬리에 남아   *)
(* 있으면 그 구간은 이 조각열의 것이 아니다.                               *)
(***************************************************************************)
Faithful(t) ==
    \E r \in Runs :
        /\ runTag[r] = t
        /\ total[r] <= SlotCap
        /\ (1..total[r]) \subseteq sent[r]
        /\ \A i \in 1..SlotCap :
              out[t][i] = (IF i <= total[r] THEN r ELSE NoR)

Inv_ReassemblyExclusive == \A t \in Tags : outValid[t] => Faithful(t)

(***************************************************************************)
(* §2.4.1 「연속한 슬롯 구간」 — 조각은 자기 조각열의 구간을 벗어나지       *)
(* 않는다. WindowOf 는 색인의 순수 산술이고 runTag 는 지상 진리이므로,     *)
(* 이 불변식은 기계의 검사 어휘를 전혀 쓰지 않는다.                        *)
(*                                                                         *)
(* 넘침 슬롯(NumTags*SlotCap+1)의 WindowOf 는 NumTags+1 이고 그것은 어떤   *)
(* runTag 값도 될 수 없다 — 마지막 태그의 구간 이탈도 여기서 잡힌다.       *)
(***************************************************************************)
Inv_NoCrossWindow ==
    \A k \in SlotIx : slots[k] # NoR => runTag[slots[k]] = WindowOf(k)

(***************************************************************************)
(* §4.3 규범 3·4 의 「loud fault」 — 거절이 관측 가능한 흔적을 남긴다.     *)
(*                                                                         *)
(* rej* 는 유령 변수(실제로 거절이 일어났다는 지상 진리)이고 faultBit ·     *)
(* capAbsent 는 기계가 세우는 신호다. 둘이 어긋나면 그것이 곧 「조용한      *)
(* 드롭」이다 — NoLoss.tla 의 faulted/faultBit 짝과 같은 형태다.           *)
(***************************************************************************)
Inv_RejectLoud ==
    /\ (rejCap + rejRestart + rejDup > 0) => faultBit
    /\ (rejCapa > 0) => capAbsent

(***************************************************************************)
(* §1.6.2 오류 3분류 · §2.4.1 규범 4 · §4.5 규범 — 능력 부재는 malformation *)
(* 이 아니다.                                                              *)
(*                                                                         *)
(* 전건은 *지상 진리*로 적는다: 실제로 일어난 거절이 능력 부재뿐이었는가.  *)
(* 후건은 *기계의 신호*다: 그런데도 fault 를 세웠는가. 두 어휘가 갈려 있으  *)
(* 므로 자기지시가 아니다. 이것을 접는 구현은 관측자에게 *어디를 고쳐야     *)
(* 하는지*를 거짓으로 알린다 — §1.6.2 가 "셋을 한 신호로 접으면" 이라 적은  *)
(* 것 그대로다.                                                            *)
(***************************************************************************)
Inv_CapabilityNotMalformed ==
    (rejCapa > 0 /\ rejCap + rejRestart + rejDup = 0) => ~faultBit

(***************************************************************************)
(* 완료 후 태그 재사용 — 내놓은 결과는 *해방 이후 접수된 조각들*로 만들어져 *)
(* 야 한다. 낡은 회계로 같은 구간을 다시 내보내는 것이 이 갈래의 대표      *)
(* 결함형이며, Inv_ReassemblyExclusive 는 그것에 눈이 멀다.               *)
(*                                                                         *)
(* accSince 는 「접수가 있었다」는 지상 진리이고 outValid 는 기계의 선언이다.*)
(***************************************************************************)
Inv_NoStaleRedeliver == \A t \in Tags : outValid[t] => accSince[t]

(***************************************************************************)
(* §4.3 함정 「참조 구현에 남아 있던 조용한 덮어쓰기」 의 직접 형태.       *)
(*                                                                         *)
(* 정본이 실측으로 기록한 결함형은 *같은 태그의 새 조각이 도착하면 조용히   *)
(* 마지막 것이 이긴다* 이다. 그것은 상태 하나로 말할 수 없다 — "값이        *)
(* 바뀐다" 는 전이의 성질이므로 행위 속성으로 적는다 (ResultBank 의         *)
(* Prop_WriteQualified 와 같은 문체).                                      *)
(*                                                                         *)
(* 좋은 모델에서 참인 이유: key_is_tag 가 한 태그에 문맥 하나를, no_restart *)
(* 가 한 문맥에 조각열 하나를, no_dup_seq 가 한 순번에 기입 하나를 남긴다.  *)
(* 셋 중 무엇이 빠져도 이 성질이 깨질 수 있다.                             *)
(***************************************************************************)
Prop_NoSilentOverwrite ==
    [][ \A k \in SlotIx : ~( /\ slots[k] # NoR
                             /\ slots'[k] # NoR
                             /\ slots'[k] # slots[k] ) ]_vars

(***************************************************************************)
(* 위험 도달성 증인 — 좋은 모델에서 반드시 반증돼야 한다.                  *)
(*                                                                         *)
(* 하나라도 반증되지 않으면, 좋은 모델의 통과는 "계약이 위험을 담아서" 가   *)
(* 아니라 "설정이 그 위험을 한 번도 만들지 않아서" 이고 아무것도 뜻하지     *)
(* 않는다 (§6.7).                                                          *)
(***************************************************************************)

\* 재조립이 실제로 완료되는가 — 안 되면 Inv_ReassemblyExclusive 가 공허하다.
Witness_NoDelivery == \A t \in Tags : ~outValid[t]

\* *미완 재조립 상태가 실제로 존재하는가.* 없으면 §4.3 규범 4의 전건
\* ("재조립이 완료되지 않은 채") 이 도달 불가이고 no_restart 는 아무것도
\* 막지 않는다. 이 증인이 세 거절 증인의 전제다.
Witness_NoPartialReassembly ==
    \A c \in Ctxs :
        ctxFill[c] = 0 \/ (ctxOwner[c] # NoR /\ ctxFill[c] >= total[ctxOwner[c]])

\* 네 거절 사유가 각각 실제로 발생하는가. 원인별로 세지 않으면 이 넷을
\* 세울 수 없다 — 거절된 조각은 슬롯에 흔적을 남기지 않기 때문이다.
Witness_NoRestartClash    == rejRestart = 0
Witness_NoDupSeq          == rejDup = 0
Witness_NoOverLimit       == rejCap = 0
\* 능력 부재가 실제로 도달 가능한가. 반증되지 않으면 SlotCap 을 total 과
\* 가른 것이 장식이고, Inv_CapabilityNotMalformed 가 공허하다.
Witness_NoCapabilityAbsence == rejCapa = 0

\* *능력 부재만 일어난 상태*가 도달 가능한가 — Inv_CapabilityNotMalformed 의
\* 전건 그 자체다. 앞 증인은 rejCapa > 0 만 보이므로 이것을 대신하지 못한다.
\* 반증되지 않으면 그 불변식은 전건이 비어 자명하게 참일 뿐이다.
Witness_NoCapabilityOnlyRejection ==
    ~(rejCapa > 0 /\ rejCap + rejRestart + rejDup = 0)

\* *문맥 풀이 실제로 둘 이상 동시에 살아 있는가.* 반증되지 않으면 |Ctxs| >= 2
\* 가 축퇴와 다를 바 없고, key_is_tag 삭제 실험이 아무것도 뜻하지 않는다.
Witness_NoTwoActiveCtx ==
    ~(\E c1 \in Ctxs, c2 \in Ctxs :
         c1 # c2 /\ ctxTag[c1] # NoT /\ ctxTag[c2] # NoT)

\* *한 태그가 실제로 두 번 완료되는가* — 즉 완료 후 재사용 갈래가 도달
\* 가능한가. 반증되지 않으면 reset_on_deliver 삭제 실험이 공허하다.
Witness_NoTagReuse == \A t \in Tags : dlvT[t] <= 1

=============================================================================
