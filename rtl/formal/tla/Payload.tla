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
(* 순번·총개수·마지막 표시를 나르는 채널은 *사이드밴드 CTRL* 이다 — DATA 와 *)
(* 나란히 가는 CTRL 등급 신호 (부록 E 열 번째 표면). 폭은 고정 상수         *)
(* (INV-T1/T2 — 형상의 함수 금지), 태그 레이아웃과 페이로드는 불변. 이       *)
(* 모델에서 순번 s · 총개수 total[r] · 마지막 비트 l 이 조각과 함께 도착하는 *)
(* 것은 그 채널의 추상이다 — 더는 모델이 조용히 메운 공백이 아니다.         *)
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
(* 이 독법은 규범이다: 재조립의 *키*는 태그이고(§4.3 규범 1), LBID(구간)는  *)
(* 결속의 원천도 규범이다 — 값은 개시 wave 의 ACCTGT(§1.4.7)가 명명한       *)
(* 목적 LBID 다 (§4.3). 모델의 ctxBase 확정은 그 디코드 시점의 추상이다.    *)
(* 재조립 문맥 *생성 시점*에 태그에 결속돼 조각열 종료까지 불변인 *문맥의    *)
(* 속성*이다(§2.4.1 — 착지). §4.3(태그=키)과 §2.4.1(LBID=착지)은 같은       *)
(* 결속의 두 얼굴이며, 같은 태그의 동시 재조립 최대 하나(EXT-4)는 그        *)
(* 결속의 유일성으로 성립한다. 모델에서 그 결속은 Send 의 「문맥을 새로     *)
(* 열 때 한 번」 ctxBase 확정 + 이후 bb = ctxBase[c] 재사용으로 나타난다.   *)
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
(* ## 조각열 종료 = 마지막 조각 표시 — 누락이 loud fault 가 되는 자리       *)
(*                                                                         *)
(* §4.3 규범 3의 셋 중 상한 초과·순번 중복은 조각 *도착 시점*에 판정         *)
(* 가능하지만 누락은 「조각열이 끝났다」는 시점을 요구한다. 그 시점은        *)
(* *마지막 조각 표시*다 — 사이드밴드의 「마지막」 1비트. 표시가 authority,   *)
(* 선언 총개수는 검산, 구현 슬롯 상한은 안전장치 — §4.2.2 EH 종료의 삼중    *)
(* 구조(END authority · 길이 검산 · 상한 안전장치)와 동형이다.              *)
(*                                                                         *)
(*   - Deliver 는 표시를 요구한다 (ctxLast). 개수 도달(ctxFill >= total)은   *)
(*     검산이지 종료 선언이 아니다 — 표시 없이 개수만 차는 것은 종료가       *)
(*     아니다.                                                             *)
(*   - 표시가 도착한 시점에 last_judges 가드가 완전성을 판정한다: 수신       *)
(*     순번 집합 # {1..총개수} 이면 누락/중복이며 loud fault. 지우면 누락이   *)
(*     무언으로 남는다 — 1차 판이 「덮지 않는 것」으로 자백했던 바로 그       *)
(*     공백이다. Inv_EndIncompleteLoud 가 그 판정의 짝이다.                 *)
(*   - *표시 유실* 갈래: 표시가 끝내 오지 않으면 문맥은 미완으로 남는다.     *)
(*     그것은 fault 가 *아니다* — 타임아웃으로 fault 를 지어내는 것은        *)
(*     「조용한 실패의 다른 이름」이다 (부록 E.3 이 HIU 채움에서 기각한       *)
(*     것과 같은 이유가 여기서는 규범이다). 모델은 미완 문맥 상태의 *관측    *)
(*     가능성*(IncompleteCtx — 진단 표면)만 두고, 처분은 호스트 몫이다.      *)
(*     Witness_NoMarkerLoss 가 그 갈래의 도달 가능성을 검사한다.            *)
(*   - 거절된 조각의 표시는 접수되지 않는다 — 거절 자체가 이미 loud 이고     *)
(*     (loud_reject), 거절된 조각은 어떤 흔적도 문맥에 남기지 않는다는       *)
(*     기존 처분과 한 몸이다.                                              *)
(*                                                                         *)
(* ## 오류 3분류를 접지 않는다 (§1.6.2 · §2.4.1 규범 4 · §4.5 규범)        *)
(*                                                                         *)
(* SlotCap 은 *구현 파라미터*(한 구간의 물리 칸 수)이고 total[r] 은 조각열이*)
(* *선언한* 총개수다. 정본이 두 「상한」을 서로 다른 낱말로 확정했다 —      *)
(* §4.3 의 상한은 *선언 총개수*이고 §2.4.1 의 상한은 *구현 슬롯 상한*이다.  *)
(* 둘을 한 상수로 겸하게 하면 §4.3 규범 2·3 이 지목한 "총개수 자체가        *)
(* 상한을 넘는 조각열" 이 표현 자체가 불가능해진다. 갈라 두면 처분도 갈린다:*)
(*   - 순번 s > total[r]   → 선언과의 자기모순 = malformation·loud fault    *)
(*                            (§4.3 규범 3)                                *)
(*   - total[r] > SlotCap  → *능력 부재* — 오류가 아니다 (§2.4.1 규범 4 ·   *)
(*                            §4.5 · §1.6.2 오류 3분류 배타성)              *)
(* 능력 부재를 loud fault 로 접는 구현은 Inv_CapabilityNotMalformed 를      *)
(* 위반한다.                                                               *)
(*                                                                         *)
(* ## 태그 지정 문맥 소거 (부록 E.12) — 호스트의 처분이 기계에 들어오는 자리 *)
(*                                                                         *)
(* 1차 판은 「미완 문맥의 처분은 모델 밖 — 회수를 모델에 넣으면 타임아웃을   *)
(* 뒷문으로 들이는 것」이라 적었다. E.12 가 그 처분의 실물을 확정했다:      *)
(* *태그 지정 문맥 소거* MMIO 기입 — 타임아웃(기계가 지어내는 종료)이        *)
(* 아니라 호스트의 *명시적* 기입이므로 뒷문이 아니다 (§3.7 드레인 완주       *)
(* 가능성 — 표시 유실 문맥 하나가 드레인을 영원히 막지 않게 하는 수단).      *)
(* ContextAbort(t) 가 그 추상이다. E.12 규범 세 항이 그대로 갈래가 된다:    *)
(*                                                                         *)
(*   - 소거 대상은 그 태그의 활성 문맥 전체다 — 결속(태그 해방)·수신 순번    *)
(*     집합·회계. 구간 slots 도 비운다 — Consume 과 같은 소거 규율이다.      *)
(*     abort_erases 가 그 가드다. 태그 해방은 가드 밖에 둔다 — 대표          *)
(*     결함형이 「태그는 해방됐는데 회계·구간이 남았다」(소거 write-enable    *)
(*     일부 누락)이기 때문이다. 지우면 잔재 위 재사용이 조용한 덮어쓰기      *)
(*     (Prop_NoSilentOverwrite) 또는 섞인 인도(Inv_ReassemblyExclusive)로    *)
(*     나타난다.                                                           *)
(*   - 소거는 fault 가 아니다 — 호스트의 *의도된* 처분이다. abort_not_fault  *)
(*     가 그 가드다 (capability_not_fault 와 같은 문체 — 지우면 소거가       *)
(*     faultBit 를 세우고 Inv_AbortNotFault 가 반증한다).                    *)
(*   - 소거는 회계 흔적을 남긴다 — *소거 카운트.* 조용한 소거는 없다.        *)
(*     abort_leaves_trace 가 그 가드다: abortsG(실제 소거의 유령 기록 —      *)
(*     지상 진리)와 abortCount(기계가 세는 관측면)를 가르고, 지우면 소거는   *)
(*     일어나되 카운트가 서지 않는다 — Inv_AbortLoud 가 그 어긋남이다.       *)
(*   - 지정 태그에 열린 문맥이 없으면 쓰기 무시 — 오류가 아니다 (드레인      *)
(*     경합에서 이미 인도·소비된 문맥의 소거 시도는 정상 경로다). 모델에서   *)
(*     그 갈래는 상태 무변경 = [Next]_vars 의 스터터와 동일하므로 따로       *)
(*     열거하지 않는다 — 전제 TagHeld(t) 가 그 「무시」의 문면이다.          *)
(*                                                                         *)
(* 소거 규율이 Consume(reset_on_deliver)과 *같은데 가드를 따로 두는* 근거:  *)
(* 두 소거는 서로 다른 전이(인도 완결 vs 호스트 기입)이고 RTL 에서 서로     *)
(* 다른 write-enable 경로다. 한 가드로 묶으면 삭제 실험이 두 경로를 동시에  *)
(* 지워, 한쪽 경로만 깨진 구현(인도 소거는 맞고 abort 소거만 누락)이 모델   *)
(* 대응에서 구별 불가가 된다 — GUARD-MAP 의 가드당 1검사 규약과도 어긋난다. *)
(* 「같은 규율」이라는 사실은 가드 공유가 아니라 이 해설이 나른다.          *)
(*                                                                         *)
(* ## 이 모델이 덮지 않는 것                                               *)
(*                                                                         *)
(*   ⚠️ 배압·무손실(§2.6)은 이 모델 밖이다 — SEC-3(NoLoss.tla)의 몫이다.     *)
(*      여기서 거절된 조각은 회계에 남지만 재전송되지 않는다. 문맥 풀이      *)
(*      고갈되면 Send 가 발화하지 않고 조용히 멈춘다 — 그 무처분도 SEC-3 의  *)
(*      몫이다. (ASSUME Cardinality(Ctxs) >= NumTags 가 key_is_tag 아래에서  *)
(*      그 고갈을 배제한다.)                                                *)
(*   ⚠️ *미완 문맥의 회수 정책*은 여전히 모델 밖이다 — E.12 로 들어온 것은    *)
(*      소거라는 *수단*의 계약(회계 흔적·fault 불참·없는 태그 무시)이지,     *)
(*      호스트가 언제 소거하는가라는 *정책*이 아니다. ContextAbort 는 아무   *)
(*      때나 발화 가능한 환경 액션이다 — 그 임의성이 정책 비규정의 표현이다. *)
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
              "key_is_tag", "reset_on_deliver", "write_atomic", "last_judges",
              "abort_erases", "abort_leaves_trace", "abort_not_fault"}
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
    ctxLast,    \* [Ctxs -> BOOLEAN]  마지막 조각 표시가 접수됐는가 — 종료 authority
    outValid,   \* [Tags -> BOOLEAN]  재조립 완료 선언
    out,        \* [Tags -> [1..SlotCap -> Runs \cup {NoR}]]  완료 시점의 구간 스냅숏
    sends,      \* 0..MaxSend  전송 횟수. 유한화용
    rejCap,     \* 유령 변수 — 순번 상한 초과로 거절된 수
    rejRestart, \* 유령 변수 — 재시작 충돌로 거절된 수
    rejDup,     \* 유령 변수 — 순번 중복으로 거절된 수
    rejCapa,    \* 유령 변수 — *능력 부재*로 거절된 수 (§2.4.1 규범 4)
    endBad,     \* 유령 변수 — 표시 접수 시점에 순번 집합이 불완전했던 횟수
    accSince,   \* 유령 변수 — [Tags -> BOOLEAN] 태그가 해방된 뒤 접수가 있었는가
    dlvT,       \* 유령 변수 — [Tags -> 0..MaxSend] 그 태그가 몇 번 완료됐는가
    abortsG,    \* 유령 변수 — 실제로 일어난 문맥 소거 수 (지상 진리, E.12)
    abortCount, \* 기계가 세는 소거 카운트 — E.12 의 회계 관측면 (fault 아님)
    faultBit,   \* 기계가 세우는 sticky loud fault 비트 (§4.3 「loud fault」)
    capAbsent   \* 기계가 세우는 sticky *능력 부재* 신호 (§1.6.2 — fault 가 아니다)

vars == <<runTag, total, sent, slots, pend, ctxTag, ctxBase, ctxSeen, ctxFill,
          ctxOwner, ctxLast, outValid, out, sends, rejCap, rejRestart, rejDup,
          rejCapa, endBad, accSince, dlvT, abortsG, abortCount, faultBit,
          capAbsent>>

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
    /\ ctxLast \in [Ctxs -> BOOLEAN]
    /\ outValid \in [Tags -> BOOLEAN]
    /\ out \in [Tags -> [1..SlotCap -> Runs \cup {NoR}]]
    /\ sends \in 0..MaxSend
    /\ rejCap \in 0..MaxSend
    /\ rejRestart \in 0..MaxSend
    /\ rejDup \in 0..MaxSend
    /\ rejCapa \in 0..MaxSend
    /\ endBad \in 0..MaxSend
    /\ accSince \in [Tags -> BOOLEAN]
    /\ dlvT \in [Tags -> 0..MaxSend]
    \* 0..1 포화 — accSince(BOOLEAN)와 같은 유한화다. 이 모델의 어떤 검사도
    \* 소거 *횟수*를 쓰지 않는다 (Inv_AbortLoud·Witness 전부 > 0 비교) —
    \* dlvT 가 값 2 를 요구하는 Witness_NoTagReuse 때문에 MaxSend 캡인 것과
    \* 다른 자리다. 전폭 카운터로 두면 소거 뒤의 상태가 카운터 값만 다른
    \* 채로 전부 새 상태가 되어 형상 sweep 이 실측으로 폭발했다 (shapeA
    \* 10분+). 횟수의 회계 자체는 RTL 관측면(abortCount 레지스터)의 몫이다.
    /\ abortsG \in 0..1
    /\ abortCount \in 0..1
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
    /\ ctxLast = [c \in Ctxs |-> FALSE]
    /\ outValid = [t \in Tags |-> FALSE]
    /\ out = [t \in Tags |-> [i \in 1..SlotCap |-> NoR]]
    /\ sends = 0
    /\ rejCap = 0
    /\ rejRestart = 0
    /\ rejDup = 0
    /\ rejCapa = 0
    /\ endBad = 0
    /\ accSince = [t \in Tags |-> FALSE]
    /\ dlvT = [t \in Tags |-> 0]
    /\ abortsG = 0
    /\ abortCount = 0
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
(*   last_judges         지우면 표시 시점의 누락이 무언으로 남는다          *)
(*                                                                         *)
(* b 는 *문맥을 새로 열 때* 잡는 구간 시작이다. base_from_tag 가 켜져 있으면*)
(* 태그가 지목한 자리 하나만 통과한다.                                     *)
(*                                                                         *)
(* l 은 사이드밴드의 「마지막」 1비트다. 생산자가 적대적이므로 아무 조각에나 *)
(* 실릴 수 있고, 영영 안 실릴 수도 있다 (표시 유실 갈래). 표시가 *접수되는*  *)
(* 시점에 last_judges 가 완전성을 판정한다 — 접수 후 순번 집합이            *)
(* {1..선언 총개수} 와 다르면 누락/중복이며 loud fault (§4.3 규범 3의 누락   *)
(* 축이 사는 자리). endBad 는 그 사건의 유령 기록이고, 가드는 faultBit 발화  *)
(* 만 쥔다 — rej*/loud_reject 짝과 같은 분업이다.                           *)
(***************************************************************************)
Send(r, s, c, b, l) ==
    /\ SendPre(r, c)
    /\ LET t  == runTag[r]
           bb == IF Free(c) THEN b ELSE ctxBase[c]
           k  == bb + s
           ra == CapaRej(r)
           rc == CapRej(r, s)
           rr == RestartRej(r, c)
           rd == DupRej(r, c, s)
           ns == ctxSeen[c] \cup {s}          \* 접수 후의 수신 순번 집합
           eb == l /\ ns # (1..total[r])      \* 표시 시점 불완전 — 지상 진리
       IN /\ (~Free(c)) \/ (~On("base_from_tag")) \/ (b = (t - 1) * SlotCap)
          \* 문맥을 새로 열지 않는 경우 b 는 쓰이지 않으므로 하나로 고정한다
          \* — 그러지 않으면 같은 전이가 |BaseRange| 번 중복 열거된다.
          /\ (Free(c)) \/ (b = 0)
          /\ IF ra \/ rc \/ rr \/ rd
               THEN \* 거절. 처분이 갈린다 — 능력 부재는 fault 가 아니다.
                    \* 거절된 조각의 표시는 접수되지 않는다 (ctxLast·endBad
                    \* 불변) — 거절 자체가 이미 loud 이다.
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
                                   ctxFill, ctxOwner, ctxLast, endBad, accSince>>
               ELSE \* 접수. 자리에 *조각열의 정체성*을 남긴다.
                    /\ ctxTag' = [ctxTag EXCEPT ![c] = t]
                    /\ ctxBase' = [ctxBase EXCEPT ![c] = bb]
                    /\ ctxSeen' = [ctxSeen EXCEPT ![c] = @ \cup {s}]
                    /\ ctxFill' = [ctxFill EXCEPT ![c] = IF @ < MaxSend THEN @ + 1 ELSE @]
                    /\ ctxOwner' = [ctxOwner EXCEPT ![c] = r]
                    /\ ctxLast' = [ctxLast EXCEPT ![c] = @ \/ l]
                    /\ accSince' = [accSince EXCEPT ![t] = TRUE]
                    \* 표시 도착 = 조각열 종료 선언. 그 시점의 완전성 판정.
                    /\ endBad' = (IF eb THEN endBad + 1 ELSE endBad)
                    /\ faultBit' = (IF eb /\ On("last_judges") THEN TRUE ELSE faultBit)
                    \* 회계와 데이터 기입이 갈리는 자리.
                    /\ IF On("write_atomic")
                         THEN /\ slots' = [slots EXCEPT ![k] = r]
                              /\ UNCHANGED pend
                         ELSE /\ pend' = [pend EXCEPT ![k] = r]
                              /\ UNCHANGED slots
                    /\ UNCHANGED <<rejCap, rejRestart, rejDup, rejCapa,
                                   capAbsent>>
    /\ sends' = sends + 1
    /\ sent' = [sent EXCEPT ![r] = @ \cup {s}]
    /\ UNCHANGED <<runTag, total, outValid, out, dlvT, abortsG, abortCount>>

\* 늦게 착지하는 데이터 기입. write_atomic 이 켜져 있으면 pend 가 늘 비어
\* 있으므로 이 액션은 발화하지 않는다 — 좋은 모델은 1차 판과 같은 기계다.
WriteBack(k) ==
    /\ pend[k] # NoR
    /\ slots' = [slots EXCEPT ![k] = pend[k]]
    /\ pend' = [pend EXCEPT ![k] = NoR]
    /\ UNCHANGED <<runTag, total, sent, ctxTag, ctxBase, ctxSeen, ctxFill,
                   ctxOwner, ctxLast, outValid, out, sends, rejCap, rejRestart,
                   rejDup, rejCapa, endBad, accSince, dlvT, abortsG, abortCount,
                   faultBit, capAbsent>>

(***************************************************************************)
(* 재조립 완료 — 기계가 「다 모였다」고 판단하는 유일한 지점.              *)
(*                                                                         *)
(* 판단 근거는 *문맥이 센 개수*(ctxFill)다. 슬롯을 훑어 세지 않는다 — 훑어  *)
(* 세면 구멍 있는 구간이 완성으로 판정되는 일이 구조적으로 불가능해지고,    *)
(* 그러면 no_dup_seq · write_atomic 삭제 실험이 조용히 통과한다.           *)
(*                                                                         *)
(* 그리고 종료의 *authority* 는 마지막 조각 표시(ctxLast)다 — 개수 도달은   *)
(* 검산일 뿐 종료 선언이 아니다. 표시 없이 개수만 찬 문맥은 인도되지 않고   *)
(* 미완으로 남는다 (표시 유실 갈래 — 처분은 호스트 몫).                     *)
(***************************************************************************)
DeliverPre(c) ==
    /\ ctxTag[c] # NoT
    /\ ctxOwner[c] # NoR
    /\ ctxLast[c]
    /\ ~outValid[ctxTag[c]]
    /\ ctxFill[c] >= total[ctxOwner[c]]

Deliver(c) ==
    /\ DeliverPre(c)
    /\ LET t == ctxTag[c]
       IN /\ outValid' = [outValid EXCEPT ![t] = TRUE]
          /\ out' = [out EXCEPT ![t] = [i \in 1..SlotCap |-> slots[ctxBase[c] + i]]]
          /\ dlvT' = [dlvT EXCEPT ![t] = IF @ < MaxSend THEN @ + 1 ELSE @]
    /\ UNCHANGED <<runTag, total, sent, slots, pend, ctxTag, ctxBase, ctxSeen,
                   ctxFill, ctxOwner, ctxLast, sends, rejCap, rejRestart,
                   rejDup, rejCapa, endBad, accSince, abortsG, abortCount,
                   faultBit, capAbsent>>

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
              /\ ctxLast' = [c \in Ctxs |-> IF ctxTag[c] = t THEN FALSE ELSE ctxLast[c]]
              /\ slots' = [k \in SlotIx |->
                             IF \E c \in Ctxs : ctxTag[c] = t /\ InWindow(c, k)
                               THEN NoR ELSE slots[k]]
         ELSE UNCHANGED <<ctxTag, ctxSeen, ctxFill, ctxOwner, ctxLast, slots>>
    /\ UNCHANGED <<runTag, total, sent, pend, ctxBase, out, sends, rejCap,
                   rejRestart, rejDup, rejCapa, endBad, dlvT, abortsG,
                   abortCount, faultBit, capAbsent>>

(***************************************************************************)
(* 태그 지정 문맥 소거 (부록 E.12 · §3.7 드레인 완주 가능성).              *)
(*                                                                         *)
(* 호스트의 MMIO 기입의 추상 — 환경 액션이라 아무 때나 발화할 수 있다      *)
(* (언제 소거하는가는 호스트 정책이며 이 모델의 계약이 아니다 — 머리       *)
(* 「덮지 않는 것」). 전제 TagHeld(t) 가 E.12 3항의 문면이다: 열린 문맥이   *)
(* 없는 태그로의 기입은 무연산 = [Next]_vars 의 스터터와 동일해 따로        *)
(* 열거하지 않는다.                                                        *)
(*                                                                         *)
(*   abort_erases       지우면 태그는 해방되는데 회계·구간이 남는다 —       *)
(*                      잔재 위 재사용이 조용한 덮어쓰기·섞인 인도로 나타남 *)
(*   abort_leaves_trace 지우면 소거가 카운트 없이 지나간다 — 조용한 소거    *)
(*   abort_not_fault    지우면 호스트의 의도된 처분이 fault 로 접힌다       *)
(*                                                                         *)
(* 태그 해방(ctxTag := NoT)이 abort_erases *밖*에 있는 이유: 대표 결함형이  *)
(* 「해방은 했는데 소거 write-enable 일부가 빠졌다」이기 때문이다. 해방까지 *)
(* 가드 안에 넣으면 삭제 실험이 「소거가 아예 안 일어나는 기계」를 만드는데,*)
(* 그것은 조용한 결함이 아니라 드레인이 멈추는 시끄러운 결함이라 이 배터리 *)
(* 의 관심사(조용한 어긋남)가 아니다.                                      *)
(*                                                                         *)
(* slots 도 비운다 — Consume 과 같은 소거 규율(같은 InWindow 술어)이다.     *)
(* 규율이 같은데 가드가 따로인 근거는 머리 해설에 있다 (서로 다른 전이 ·    *)
(* 서로 다른 RTL write-enable — 한 가드로 묶으면 한쪽 경로만 깨진 구현이    *)
(* 구별 불가). pend 는 건드리지 않는다 — Consume 과 같다 (write_atomic 이   *)
(* 켜진 기계에서 pend 는 늘 비어 있다).                                    *)
(*                                                                         *)
(* 인도됐으나 아직 소비되지 않은 문맥(outValid[t] = TRUE)의 소거도 허용     *)
(* 한다 — out 은 완료 시점의 스냅숏이라 소거의 영향을 받지 않고, accSince   *)
(* 는 outValid 의 수명과 짝이므로 소거가 건드리지 않는다 (드레인 경합       *)
(* 갈래 — E.12 3항 해설).                                                  *)
(***************************************************************************)
ContextAbort(t) ==
    /\ TagHeld(t)
    /\ LET cs == {c \in Ctxs : ctxTag[c] = t}
       IN /\ ctxTag' = [c \in Ctxs |-> IF c \in cs THEN NoT ELSE ctxTag[c]]
          /\ IF On("abort_erases")
               THEN /\ ctxSeen'  = [c \in Ctxs |-> IF c \in cs THEN {} ELSE ctxSeen[c]]
                    /\ ctxFill'  = [c \in Ctxs |-> IF c \in cs THEN 0 ELSE ctxFill[c]]
                    /\ ctxOwner' = [c \in Ctxs |-> IF c \in cs THEN NoR ELSE ctxOwner[c]]
                    /\ ctxLast'  = [c \in Ctxs |-> IF c \in cs THEN FALSE ELSE ctxLast[c]]
                    /\ slots'    = [k \in SlotIx |->
                                      IF \E c \in cs : InWindow(c, k)
                                        THEN NoR ELSE slots[k]]
               ELSE UNCHANGED <<ctxSeen, ctxFill, ctxOwner, ctxLast, slots>>
    \* 유령(지상 진리)과 기계 관측면을 가른다 — rej*/faultBit 짝과 같은 분업.
    \* 0..1 포화 — 근거는 TypeOK 의 해당 주석 (검사는 전부 > 0 비교).
    /\ abortsG' = 1
    /\ abortCount' = (IF On("abort_leaves_trace") THEN 1 ELSE abortCount)
    \* 소거는 fault 가 아니다 (E.12 2항) — capability_not_fault 와 같은 문체.
    /\ faultBit' = (IF On("abort_not_fault") THEN faultBit ELSE TRUE)
    /\ UNCHANGED <<runTag, total, sent, pend, ctxBase, outValid, out, sends,
                   rejCap, rejRestart, rejDup, rejCapa, endBad, accSince, dlvT,
                   capAbsent>>

(***************************************************************************)
(* 종료를 모델에 명시한다 — CHECK_DEADLOCK 을 끄지 않기 위해서다.          *)
(* 세 Can* 는 각 액션의 전제를 *그대로* 쓴다. 따로 적으면 어긋나고, 어긋나면*)
(* TLC 가 정당한 종료를 교착으로 보고해 판정이 흐려진다.                   *)
(*                                                                         *)
(* ContextAbort 는 Idle 의 부정에 넣지 *않는다* — 호스트는 소거하지 않을    *)
(* 수 있고(정책 비규정), 소거 가능한 상태는 ContextAbort 자신이 enabled     *)
(* 라 애초에 교착으로 보고되지 않는다. Idle 과 ContextAbort 가 같은 상태에  *)
(* 서 함께 열려 있는 것은 그 임의성의 표현이다.                            *)
(***************************************************************************)
CanSend    == \E r \in Runs, c \in Ctxs : SendPre(r, c)
CanWrite   == \E k \in SlotIx : pend[k] # NoR
CanDeliver == \E c \in Ctxs : DeliverPre(c)
CanConsume == \E t \in Tags : outValid[t]

Idle == ~CanSend /\ ~CanWrite /\ ~CanDeliver /\ ~CanConsume /\ UNCHANGED vars

Next ==
    \/ \E r \in Runs, s \in Seqs, c \in Ctxs, b \in BaseRange, l \in BOOLEAN :
          Send(r, s, c, b, l)
    \/ \E k \in SlotIx : WriteBack(k)
    \/ \E c \in Ctxs : Deliver(c)
    \/ \E t \in Tags : Consume(t)
    \/ \E t \in Tags : ContextAbort(t)
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
(* §4.3 규범 3의 *누락* 축 — 표시 시점의 불완전은 무언으로 남지 않는다.    *)
(*                                                                         *)
(* endBad 는 「마지막 조각 표시가 접수됐는데 그 시점의 수신 순번 집합이     *)
(* {1..선언 총개수} 가 아니었다」는 사건의 유령 기록(지상 진리)이고,        *)
(* faultBit 는 기계가 세우는 신호다. last_judges 를 지우면 사건은 그대로    *)
(* 일어나되 신호가 서지 않는다 — 1차 판에서 누락이 「조용히 멈추는 것」으로 *)
(* 만 나타나던 비-커버리지가 정확히 이 어긋남이다.                         *)
(*                                                                         *)
(* 전건에 들어가는 것은 *판정 사건*이지 미완 상태가 아니라는 데 주의 —      *)
(* 표시가 오지 않아 미완에 머무는 문맥(표시 유실)은 endBad 를 올리지        *)
(* 않으며, 따라서 이 불변식은 그 갈래에 fault 를 요구하지 않는다.          *)
(***************************************************************************)
Inv_EndIncompleteLoud == (endBad > 0) => faultBit

(***************************************************************************)
(* 표시 유실 갈래의 관측 표면 — 미완 문맥 상태.                            *)
(*                                                                         *)
(* 표시가 끝내 오지 않은 문맥은 인도되지 않고(DeliverPre 가 ctxLast 를      *)
(* 요구한다) fault 도 아니다. 타임아웃으로 종료를 지어내는 것은 금지다 —    *)
(* 그것은 조용한 실패의 다른 이름이다 (부록 E.3 선례). 기계가 지는 의무는   *)
(* 이 상태가 진단 표면으로 *관측 가능*하다는 것까지이고, 회수·처분은        *)
(* 호스트 몫이다. 모델에서 관측 가능성은 이 술어가 기계 상태(ctxTag ·       *)
(* ctxLast)만으로 정의된다는 사실 그 자체다.                               *)
(***************************************************************************)
IncompleteCtx(c) == ctxTag[c] # NoT /\ ~ctxLast[c]

(***************************************************************************)
(* §1.6.2 오류 3분류 · §2.4.1 규범 4 · §4.5 규범 — 능력 부재는 malformation *)
(* 이 아니다.                                                              *)
(*                                                                         *)
(* 전건은 *지상 진리*로 적는다: 실제로 일어난 거절이 능력 부재뿐이었는가.  *)
(* 후건은 *기계의 신호*다: 그런데도 fault 를 세웠는가. 두 어휘가 갈려 있으  *)
(* 므로 자기지시가 아니다. 이것을 접는 구현은 관측자에게 *어디를 고쳐야     *)
(* 하는지*를 거짓으로 알린다 — §1.6.2 가 "셋을 한 신호로 접으면" 이라 적은  *)
(* 것 그대로다.                                                            *)
(*                                                                         *)
(* endBad = 0 이 전건에 있는 이유: 표시 시점 불완전은 malformation 이고     *)
(* fault 가 *정당*하므로, 그 사건이 함께 일어난 이력에서는 이 불변식이      *)
(* fault 부재를 요구하면 안 된다. 전건은 「fault 감인 사건이 하나도 없었다」 *)
(* 를 전부 지상 진리 어휘로 나열한 것이다.                                 *)
(***************************************************************************)
Inv_CapabilityNotMalformed ==
    (rejCapa > 0 /\ rejCap + rejRestart + rejDup = 0 /\ endBad = 0) => ~faultBit

(***************************************************************************)
(* 완료 후 태그 재사용 — 내놓은 결과는 *해방 이후 접수된 조각들*로 만들어져 *)
(* 야 한다. 낡은 회계로 같은 구간을 다시 내보내는 것이 이 갈래의 대표      *)
(* 결함형이며, Inv_ReassemblyExclusive 는 그것에 눈이 멀다.               *)
(*                                                                         *)
(* accSince 는 「접수가 있었다」는 지상 진리이고 outValid 는 기계의 선언이다.*)
(***************************************************************************)
Inv_NoStaleRedeliver == \A t \in Tags : outValid[t] => accSince[t]

(***************************************************************************)
(* E.12 「조용한 소거는 없다」 — 소거는 회계 흔적(소거 카운트)을 남긴다.    *)
(*                                                                         *)
(* abortsG 는 실제로 일어난 소거의 유령 기록(지상 진리)이고 abortCount 는   *)
(* 기계가 세는 관측면이다. 둘이 어긋나면 그것이 곧 조용한 소거다 —          *)
(* rej*/faultBit 짝(Inv_RejectLoud)과 같은 형태. abort_leaves_trace 를      *)
(* 지우면 소거는 일어나되 카운트가 서지 않아 이 불변식이 반증된다.         *)
(* 두 기록 다 0..1 포화(유한화 — TypeOK 주석)라 > 0 비교가 검사의 전부이고, *)
(* 같은 전이에서만 오르므로 포화가 거짓 반증을 만들지 않는다. 소거 *횟수*   *)
(* 의 회계는 RTL 관측면(abortCount 레지스터, 포화 카운터)의 몫이다.        *)
(***************************************************************************)
Inv_AbortLoud == (abortsG > 0) => (abortCount > 0)

(***************************************************************************)
(* E.12 「소거는 fault 가 아니다」 — 호스트의 의도된 처분이 loud fault 로   *)
(* 접히면 관측자에게 「기계 어딘가가 잘못됐다」를 거짓으로 알린다.          *)
(* Inv_CapabilityNotMalformed 와 같은 구조: 전건은 「fault 감인 사건이       *)
(* 하나도 없었는데 소거는 있었다」를 전부 지상 진리 어휘로 나열한 것이고,   *)
(* 후건이 기계의 신호다. rejCapa 는 전건에서 배제하지 않는다 — 능력 부재    *)
(* 역시 fault 가 아니기 때문이다 (§1.6.2).                                 *)
(***************************************************************************)
Inv_AbortNotFault ==
    (abortsG > 0 /\ rejCap + rejRestart + rejDup = 0 /\ endBad = 0) => ~faultBit

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
    ~(rejCapa > 0 /\ rejCap + rejRestart + rejDup = 0 /\ endBad = 0)

\* *문맥 풀이 실제로 둘 이상 동시에 살아 있는가.* 반증되지 않으면 |Ctxs| >= 2
\* 가 축퇴와 다를 바 없고, key_is_tag 삭제 실험이 아무것도 뜻하지 않는다.
Witness_NoTwoActiveCtx ==
    ~(\E c1 \in Ctxs, c2 \in Ctxs :
         c1 # c2 /\ ctxTag[c1] # NoT /\ ctxTag[c2] # NoT)

\* *한 태그가 실제로 두 번 완료되는가* — 즉 완료 후 재사용 갈래가 도달
\* 가능한가. 반증되지 않으면 reset_on_deliver 삭제 실험이 공허하다.
Witness_NoTagReuse == \A t \in Tags : dlvT[t] <= 1

\* *표시 시점 불완전(누락)이 구성된 기계에서 실제로 도달하는가.* 반증되지
\* 않으면 last_judges 는 한 번도 일하지 않은 것이고 Inv_EndIncompleteLoud
\* 는 전건이 비어 자명하게 참일 뿐이다.
Witness_NoMissAtEnd == endBad = 0

\* *표시 유실 갈래가 실제로 도달하는가* — 생산이 끝났는데(sends = MaxSend)
\* 표시 없는 미완 문맥이 남았고 기계는 fault 를 세우지 않았다. 반증되지
\* 않으면 「미완은 fault 가 아니다」 라는 처분이 시험된 적 없는 장식이다.
Witness_NoMarkerLoss ==
    ~( /\ sends = MaxSend
       /\ ~faultBit
       /\ \E c \in Ctxs : IncompleteCtx(c) /\ ctxFill[c] > 0 )

\* *문맥 소거가 구성된 기계에서 실제로 일어나는가.* 반증되지 않으면 E.12 의
\* 세 가드 전부와 Inv_AbortLoud 가 한 번도 일하지 않은 장식이다.
Witness_NoAbort == abortsG = 0

\* *소거만 있고 fault 감인 사건이 없는 이력*이 도달 가능한가 —
\* Inv_AbortNotFault 의 전건 그 자체다. Witness_NoAbort 는 abortsG > 0 만
\* 보이므로 이것을 대신하지 못한다 (NoCapabilityOnlyRejection 과 같은 이유).
Witness_NoAbortOnlyHistory ==
    ~(abortsG > 0 /\ rejCap + rejRestart + rejDup = 0 /\ endBad = 0)

=============================================================================
