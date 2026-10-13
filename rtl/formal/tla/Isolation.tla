\* SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
\* SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
--------------------------- MODULE Isolation ---------------------------
(***************************************************************************)
(* SEC-4 · HIU-11 선-formal 모델 — 격리와 선택적 경로의 무해성.            *)
(*                                                                         *)
(*   SEC-4  격리 (§5.8) — 파티션 p 의 *관측 가능한 출력*은 파티션 q != p 가 *)
(*          설치한 상태에 의존하지 않는다. (HIU-1/HIU-2 의 상위 형태.)      *)
(*   HIU-11 선택적 경로의 무해성 (§3.12) — 호스트 서비스 경로(변환 질의 ·   *)
(*          하드웨어 일관성)를 켜고 끄는 것이 상수 시간 계약을 바꾸지 않는다.*)
(*                                                                         *)
(* ## 둘 다 관계 속성이다 — §3.4.2 를 그대로 적용한다                      *)
(*                                                                         *)
(* §3.4.2 규범: "한 구성만 검사하는 것은 검사가 아니다." SEC-4 의 "의존하지 *)
(* 않는다" 는 한 실행 안에서 말할 수 없다 — 비간섭(non-interference)이고    *)
(* *두 실행의 비교*다. HIU-11 도 같은 형태다 — 선택적 경로가 *있는* 구성과  *)
(* *없는* 구성의 비교다.                                                    *)
(*                                                                         *)
(* 그래서 이 모델은 네 세계를 격자로 들고 간다. 축이 둘이기 때문이다:      *)
(*                                                                         *)
(*        |  off (선택적 경로 없음)  |  on (선택적 경로 있음)               *)
(*   -----+--------------------------+------------------------             *)
(*   qA   |  <<"qA","off">>          |  <<"qA","on">>                       *)
(*   qB   |  <<"qB","off">>          |  <<"qB","on">>                       *)
(*                                                                         *)
(*   QSides 축 — 타 파티션(q != Subject)이 설치한 상태만 다르다. SEC-4.     *)
(*   Opts   축 — 선택적 호스트 서비스 경로의 유무만 다르다. HIU-11.         *)
(*                                                                         *)
(* Subject(=p)에 관한 것은 네 세계에서 전부 같다. p 의 동작열은 *같은       *)
(* 인자로 네 세계에 동시에* 걸린다 (lockstep). §3.4.2 함정이 못박듯         *)
(* 입력이 같지 않으면 통과도 반증도 증거가 아니므로, 이 대칭이 모델의       *)
(* 전제 전부다.                                                            *)
(*                                                                         *)
(* ## 두 축이 무엇으로 갈라지는가 — 「관측이 읽는 상태」 규율               *)
(*                                                                         *)
(* Platform.tla 가 실측으로 세운 규율이 있다: 두 세계를 가르는 변수는       *)
(* *관측 경로 위에 있어야 한다.* Witness_NoMemSkew 가 성립한 이유는 mem 이  *)
(* Read 가 실제로 읽는 변수였기 때문이다. 관측이 읽지 않는 탐침만 어긋나면  *)
(* 동치는 계약이 만든 참이 아니라 *구성이 만든 참*이고, §3.4.2 해설이 적은  *)
(* "어긋남이 아예 없다면 두 구성의 구분은 이름뿐" 그 자리다.                *)
(*                                                                         *)
(* 이 모델의 초판은 Opts 축에서 그 규율을 어겼다 — 두 구성이 쓰기 전용      *)
(* 탐침(optUsed) 하나에서만 달랐고, valid·data·fill 은 전 상태공간에서      *)
(* 비트 동일했다. 적대 검증이 그것을 blocking 으로 지목했고, 이 판은        *)
(* 호스트 응답 항목(hostEnt)을 두어 고쳤다:                                *)
(*                                                                         *)
(*   - hostEnt 는 on 구성에만 생긴다 (off 는 언제나 NoEnt).                 *)
(*   - hostEnt 는 Approved · SelectedDatum 이 *가드 없이* 읽는다. 즉        *)
(*     관측 경로 위에 있다.                                                *)
(*   - 그런데도 관측이 같은 이유는 query_no_serve 가드다 (§3.3.1 규범 1     *)
(*     "변환은 장치 안에서 완결돼야 한다") — 호스트 응답은 *장치가 이미     *)
(*     가진 항목*만 담을 수 있고, 스스로 항목을 만들어 내지 못한다.         *)
(*   - 그 가드를 지우면 on 구성만 적중하고 값이 갈린다.                     *)
(*                                                                         *)
(* 정직하게 적어 둘 것 하나: *좋은 모델에서 hostEnt 는 결코 판정을 혼자     *)
(* 정하지 않는다.* 그것은 결함이 아니라 중립성의 뜻 그 자체다 — 선택적      *)
(* 경로가 결과를 바꾼다면 그것이 곧 HIU-11 위반이다. 그러므로 이 축에서     *)
(* 요구할 수 있는 최대는 셋이고, 셋 다 여기서 성립한다:                    *)
(* (1) 상태가 실제로 어긋난다 (Witness_NoOptStateSkew 가 반증된다),         *)
(* (2) 그 상태가 관측 경로 위에 있다 (Approved 가 On(...) 없이 읽는다),     *)
(* (3) 중립성이 *가드가 만든 참*이다 (del_query_no_serve 가 깨뜨린다).      *)
(*                                                                         *)
(* ## SEC-4 가 HIU-1/HIU-2 의 「상위 형태」인 지점                          *)
(*                                                                         *)
(* XlateStore.tla 가 이미 HIU-1(적중 판정이 남의 항목을 고르지 않는다)과    *)
(* HIU-2(flush 후 미적중)를 증명했다. SEC-4 가 그 둘의 재탕이면 새 모델을   *)
(* 만들 이유가 없다. 세 지점에서 다르다:                                    *)
(*                                                                         *)
(*   1. *읽기 경로가 셋이다.* XlateStore 는 스스로 적었다 — "모델에는 읽기  *)
(*      경로가 하나뿐이기 때문에" HIU-3 의 전수성을 답할 수 없다고. 여기는  *)
(*      저장 블록 조회 · 공유 채움 버퍼 바이패스 · 호스트 응답 항목, 셋이다.*)
(*      판정이 옳아도 둘째·셋째가 게이트되지 않으면 격리가 깨진다           *)
(*      (§3.6.3 함정 "모든 읽기 경로 ... 하나라도 빠지면 이전 테넌트의       *)
(*      변환이 새어 나간다").                                              *)
(*   2. *관측 가능한 출력 전부*를 본다 — 적중 여부(obsKind)뿐 아니라        *)
(*      값(obsVal), *상태열*(trace), 그리고 *승인 이전에 소비자에게 실린    *)
(*      값*(fwd)까지. §3.2 규범이 세 축을 함께 못박는다: "값이 새면 격리    *)
(*      위반이고, 타이밍이 다르면 부채널이다."                             *)
(*   3. *미적중이라는 사실 자체*가 관측이다. 남의 항목이 있고 없고에 따라   *)
(*      p 의 미적중 시점이 달라지면 그것이 채널이다 — 그것을 잡는 것이      *)
(*      Inv_TraceNonInterference 다.                                       *)
(*                                                                         *)
(* 1번을 지탱하는 것이 무엇인지 정확히 적어 둔다. 적대 검증이 "install_     *)
(* scoped 는 XlateStore 의 partition_check 와 같은 규범을 시험한다" 고      *)
(* 지적했고 그것이 옳다 — 그러므로 *둘째·셋째 읽기 경로를 지탱하는 것은     *)
(* fill_tagged · fill_offpath · fill_slot_per_partition · query_no_serve    *)
(* 넷이지 install_scoped 가 아니다.* install_scoped 는 저장 블록 축이       *)
(* 가정이 아니라 하중을 받고 있음을 보이는 가드이며, 그 축 자체는           *)
(* XlateStore 와 겹친다.                                                   *)
(*                                                                         *)
(* ## 채널은 태그만이 아니라 용량이다                                      *)
(*                                                                         *)
(* 이 모델의 초판은 채움을 한 걸음으로 적었다 — valid·data·fill 을 동시에   *)
(* 썼다. 그러면 *p 의 줄이 공유 버퍼에만 있고 저장 블록에는 아직 없는 창*   *)
(* 이 존재하지 않고, 그 결과 바이패스가 판정을 혼자 정하는 일이 원리적으로  *)
(* 불가능해진다 (BypassHit => StoreHit 이 자동으로 참이 된다). 지울 가드가  *)
(* 없어서 통과한 형태이며 NoLoss.tla 의 advance_atomic 과 같은 자리다.      *)
(*                                                                         *)
(* 그래서 채움을 SubjectFillStart(버퍼 점유) / SubjectFillCommit(저장       *)
(* 커밋) 둘로 쪼갰다. 그 창이 생기자 새 채널이 드러났다 — q 의 설치가 p 의  *)
(* in-flight 줄을 *축출*하면 p 가 미적중한다. 태그는 정상이고 주소 구조도   *)
(* 정상인데 깨진다. 채널은 태그가 아니라 *용량*이다.                        *)
(*                                                                         *)
(* 같은 채널이 저장 블록 축에도 있다. §3.6.1 규범이 재구현에 요구하는       *)
(* 결과는 둘뿐이고(곱셈 없음 · 메모리 자원 추론), 그 둘은 격리에 관해       *)
(* 아무 말도 하지 않는다. 즉 파티션이 한 집합의 way 를 나눠 쓰는 구조는     *)
(* 정본이 허용한다 — 그리고 그 갈래의 대표 결함형이 축출 채널이다           *)
(* (§5.1 위협 모델 3항이 인용하는 캐시 타이밍 채널 그 자체). 그래서         *)
(* capacity_partitioned 가드를 두어 그 갈래를 *표현 가능하게* 만들었다.     *)
(* 근거는 #속성 SEC-4 자신이다 — "q 가 설치한 상태에 의존하지 않는다" 는    *)
(* 적중을 남에게서 받는 것뿐 아니라 남 때문에 잃는 것도 금지한다.           *)
(*                                                                         *)
(* ## 승인은 이름이 아니라 상태다                                          *)
(*                                                                         *)
(* §3.2 규범 1 은 시간적 문장이다 — "읽기 결과는 승인 이전에 소비자에게     *)
(* 도달하지 않는다." 초판은 요청을 한 걸음으로 적어 이것을 *최종 값의       *)
(* 함수적 게이팅*으로 축약했고, 그것은 영구 누출형만 잡았다. 일시 누출형    *)
(* (실행에서 앞당겨 전달하고 승인에서 회수)은 표현 불가였고 지울 가드가     *)
(* 애초에 없었다.                                                          *)
(*                                                                         *)
(* 그래서 요청을 RequestExec / RequestApprove 둘로 쪼개고 *소비자에게       *)
(* 실린 값*(fwd)을 관측 목록에 넣었다. no_early_forward 가 §3.2 규범 1 의   *)
(* 시간축을 지탱하고, approve_gates_value 가 값축을 지탱한다. 둘은 같은     *)
(* 규범의 서로 다른 두 항이며 서로를 대신하지 못한다 —                     *)
(* del_no_early_forward 는 Inv_ForwardNonInterference 만 깨뜨리고           *)
(* Inv_ValueNonInterference 는 통과시킨다.                                 *)
(*                                                                         *)
(* ## 상수 시간을 「사이클 수가 같다」로 적지 않는다                        *)
(*                                                                         *)
(* §5.3 규범: 상수 시간성은 "항상 N 사이클" 이 아니라 *어느 경로를 타든     *)
(* 같은 상태열*이다. 사이클 수는 결과이지 계약이 아니다. 그래서 이 모델은   *)
(* 요청이 지나는 *상태열 자체*(§3.2 순서 계약의 6단계)를 기록하고 비교한다. *)
(*                                                                         *)
(* 그 구분이 이름뿐이 아님을 배터리가 실제로 보인다 — del_coh_no_shortcut   *)
(* 은 길이가 *같으면서* 상태열이 다른 반례를 낸다. 사이클 수만 보는         *)
(* Inv_OptionalPathSameCycles 는 그 반례를 통과시키고, 상태열을 보는        *)
(* Inv_OptionalPathNeutral 만 잡는다. 그 짝이 §5.3 의 형식적 형태다.        *)
(*                                                                         *)
(* ## 지상 진리는 무엇인가                                                 *)
(*                                                                         *)
(* 이 모델의 지상 진리는 *네 세계의 관측 변수가 같은가*이며, 어떤 가드나    *)
(* 검사의 술어로도 적혀 있지 않다. obsKind · obsVal · trace · fwd 는 요청   *)
(* 동작이 계산해 남기는 값이고, 불변식은 그 값들을 세계 사이에서 *비교*할   *)
(* 뿐이다. 「승인됐는가」(Approved)를 불변식에 쓰면 "검사를 통과한 것이     *)
(* 옳다" 가 되어 자기지시적으로 만족된다 — Route.tla M2 에서 실측한         *)
(* 실패형이며 여기서는 처음부터 피했다.                                    *)
(*                                                                         *)
(* ## 이 모델이 덮지 않는 것                                               *)
(*                                                                         *)
(*   ⚠️ 저장 블록에 태그 비교가 없다 — 적중 조건을 유효 비트로만 적었다.     *)
(*      적중 판정의 정확성(HIU-1 · HIU-2 · HIU-4)은 XlateStore.tla 의 몫이고,*)
(*      이 모델이 묻는 것은 *판정이 옳을 때에도 남는 채널*이다. 두 모델을   *)
(*      함께 읽어야 격리가 덮인다.                                         *)
(*   ⚠️ flush 가 없다 — 컨텍스트 전환 축(HIU-2)은 XlateStore.tla 가 덮는다.  *)
(*      여기서 저장 블록의 초기 쓰레기(data 의 초기값)가 "flush 가 남긴     *)
(*      데이터" 와 같은 자리를 차지한다.                                    *)
(*   ⚠️ 저장 블록은 파티션·색인당 항목이 하나다 (직접 사상 1-way). §3.6.2    *)
(*      규범 2 가 예상하는 *여러 후보의 동시 적중*은 채움 버퍼 축에서만     *)
(*      표현된다 (BypassCands 가 여럿일 수 있고 BypassPick 이 우선순위를    *)
(*      명시한다). 저장 블록 안의 다중 way 우선순위는 표현 불가다.          *)
(*      다만 그 갈래의 *격리 결함형*(교차 파티션 축출)은                    *)
(*      capacity_partitioned 로 표현된다.                                  *)
(*   ⚠️ SEC-2 그 자체를 검사하지 않는다 — 적중·대체·미적중 *사이*의 상태열   *)
(*      동일성은 별도 모델(Decode)의 몫이다. HIU-11 은 *선택적 경로의       *)
(*      유무*가 그 계약을 바꾸는가에 한정된다. 이 모델이 비교하는 두 상태열 *)
(*      은 언제나 같은 요청의 것이다.                                       *)
(*   ⚠️ 소유권 확인의 *위치*는 §3.2 규범으로 확정됐다 — *접근 승인(6) 안*,   *)
(*      사후 게이팅 (환류 완료). 이 모델이 먼저 그 자리에 두었고            *)
(*      (coh_no_shortcut 가 승인 단계의 두 변종 "approve_own" /             *)
(*      "approve_coh" 를 가른다), 정본이 그 독법을 규범으로 못박았다 —      *)
(*      SEC-2 상태열 동일성이 전단 확인을 배제한다는 것이 그 근거다.        *)
(*      단계를 하나 *더* 만들지 않은 것도 이제 회피(Route.tla M4)가 아니라  *)
(*      규범 준수다. 남는 모델화 선택은 변종의 구체 표현(이름 · 길이        *)
(*      같음)뿐이며, 그것은 §5.3 「상태열 *자체*의 동일성」과 같은 방향이다. *)
(*      ⇒ 따라서 "HIU-11 이 SEC-2 로 환원되지 않는다" 는 판정도 이제 해석   *)
(*      이 아니라 규범 위에 선다. coh_no_shortcut 삭제는 *한 세계 안에서*   *)
(*      요청마다 상태열을 바꾸지 않으므로(SEC-2 는 그대로다) Opts 축        *)
(*      비교만이 그것을 잡는다 — HIU-11 이 SEC-2 의 되풀이가 아닌 이유다.   *)
(*      등급을 「부분 증명」에 묶었던 해석 의존은 해소됐다.                  *)
(*   ⚠️ 읽기 경로 *사이*의 우선순위는 §3.6.2 규범 2 로 확정됐다 (환류 완료)  *)
(*      — 진행 중 채움 바이패스 > 저장 블록 > 호스트 응답, 채움 후보가      *)
(*      복수면 자기 파티션 우선. 근거는 신선도(채움이 가장 새 항목)와       *)
(*      로컬 우선(선택적 경로는 가속이지 authority 가 아니다 — HIU-8)이다.  *)
(*      이 모델의 약정(SelectedDatum 의 경로 순서 · BypassPick 의 Subject   *)
(*      우선)이 그 규범과 일치한다. 좋은 모델의 비간섭 결과는 이 순서에     *)
(*      의존하지 않지만(네 세계가 같은 순서를 쓰므로 lockstep 이 유지된다)  *)
(*      값 축 관측의 *뜻*은 이 순서가 고정한다.                             *)
(*   ⚠️ 요청이 한 번에 하나다 (pend 가 단일 값이다). 실행·승인 사이에 다른  *)
(*      동작이 끼어드는 것은 표현되지만, *두 요청의 파이프라인 겹침*과      *)
(*      요청 사이의 자원 경합(FAB-2 축)은 표현 불가다.                     *)
(*   ⚠️ 사이클을 세지 않는다 — 단계는 이름이고, 한 단계의 실제 지연은 없다. *)
(*      단계 이름의 열이 같으면 소요 시간이 같다고 *약정*한다. §5.3 이       *)
(*      상수 시간을 상태열 동일성으로 규정하므로 이 약정이 계약과 같은      *)
(*      방향이다.                                                          *)
(*   ⚠️ p 의 요청열이 q 에 의존하는 경우는 표현 불가다 — lockstep 대칭이     *)
(*      그것을 배제한다. 그것은 모델의 결함이 아니라 비간섭 정의의 전제다.  *)
(*      (p 가 자기가 본 것을 근거로 다음 요청을 고르는 적응적 공격자는      *)
(*      이 형태로 잡히지 않는다.)                                          *)
(*   ⚠️ 마스킹의 내용(SEC-1)은 없다 — 단계 이름 "mask" 만 있다.             *)
(*   ⚠️ 전력·전자기 등 상태열 밖의 부채널 축은 위협 모델(§5.1) 밖이다.       *)
(*   ⚠️ rawObs 는 *관측 가능한 출력이 아니라* 모델 내부 탐침이다. 증인에만   *)
(*      쓰이며 어떤 불변식도 그것을 세계 사이에서 비교하지 않는다. fwd 는   *)
(*      다르다 — 그것은 소비자가 실제로 드는 값이므로 관측이다.             *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets, Sequences

CONSTANTS
    Partitions,      \* 격리 단위 (§3.6 정의). 불투명 토큰
    Subject,         \* 관심 파티션 p. 나머지가 전부 q 다
    Indices,         \* 변환표 색인. 불투명 토큰
    Datums,          \* 변환 데이터. 불투명 토큰
    NoDatum,         \* 「관측값 없음」 표식 (모델 값)
    NoFill,          \* 「채움 버퍼 자리가 비어 있음」 표식 (모델 값)
    NoEnt,           \* 「호스트 응답 항목 없음」 표식 (모델 값)
    NoReq,           \* 「진행 중인 요청 없음」 표식 (모델 값)
    DisabledGuards

AllGuards == {"install_scoped", "capacity_partitioned",
              "fill_tagged", "fill_slot_per_partition", "fill_offpath",
              "approve_gates_value", "no_early_forward",
              "query_offpath", "query_no_serve", "coh_no_shortcut"}
On(g) == g \notin DisabledGuards

QSides == {"qA", "qB"}        \* 타 파티션이 설치한 상태의 두 갈래 — SEC-4 축
Opts   == {"off", "on"}       \* 선택적 호스트 서비스 경로의 유무 — HIU-11 축
Worlds == QSides \X Opts

IsOn(w) == w[2] = "on"

Slots  == Partitions \X Indices
Others == Partitions \ {Subject}

\* §3.2 순서 계약의 6단계 — 다만 승인(6)이 두 변종을 갖는다 (아래 Trace 주석).
\* 그리고 이 모델이 표현하는 이탈 단계 셋.
StageNames == {"accept", "delay", "lookup", "mask", "exec",
               "approve_own", "approve_coh",
               "fwait", "query", "qwait"}

(***************************************************************************)
(* 축퇴 배제 — 형상 sweep 이 잡아야 할 것을 형상이 숨기지 못하게 한다.     *)
(*                                                                         *)
(*   타자가 없으면 SEC-4 는 말할 것이 없다.                                *)
(*   데이터가 하나뿐이면 *값 채널을 표현할 수 없다* (ResultBank 의 방어적   *)
(*   캡과 같은 형태 — 검출하려는 것을 표현 불가능하게 만드는 방어).        *)
(*                                                                         *)
(* 색인은 1개를 *의도적으로* 허용한다. 이 모델의 모든 채널(태그 · 주소      *)
(* 구조 · 용량 축출 · 바이패스 · 호스트 응답)은 *같은 색인*에서 발화하므로  *)
(* 색인 1개가 축퇴가 아니다 — 오히려 최소 형상이 반례를 가장 빨리 낸다.    *)
(* 색인 축이 무언가를 숨기는지는 ASSUME 이 아니라 형상 sweep 이 답한다:    *)
(* 좋은 모델과 *열 개 가드 삭제 전부*를 색인 2 형상(shapeA)과 파티션 3     *)
(* 형상(shapeB)에서도 돌린다. 그것이 배터리에 실려 있다.                   *)
(***************************************************************************)
ASSUME Subject \in Partitions
ASSUME Cardinality(Partitions) >= 2
ASSUME Cardinality(Indices) >= 1
ASSUME Cardinality(Datums) >= 2

VARIABLES
    valid,     \* [Worlds -> [Slots -> BOOLEAN]]   저장 블록의 유효 비트
    data,      \* [Worlds -> [Slots -> Datums]]    저장 블록의 변환 데이터
    fill,      \* [Worlds -> [Partitions -> (Slots \X Datums) \cup {NoFill}]]
               \*   채움 버퍼. 자리가 파티션당 하나인가 아니면 하나를
               \*   나눠 쓰는가를 fill_slot_per_partition 가 정한다.
    hostEnt,   \* [Worlds -> (Indices \X Datums) \cup {NoEnt}]
               \*   선택적 호스트 서비스의 응답 항목. on 구성에만 생긴다.
    pend,      \* Indices \cup {NoReq}   실행됐으나 아직 승인되지 않은 요청
    fwd,       \* [Worlds -> Datums \cup {NoDatum}]
               \*   관측 ④: *승인 이전에 소비자에게 실린 값* (§3.2 규범 1)
    obsKind,   \* [Worlds -> {"none","value","fault"}]  관측 ①: 적중/미적중이라는 사실
    obsVal,    \* [Worlds -> Datums \cup {NoDatum}]     관측 ②: 돌려받은 값
    trace,     \* [Worlds -> Seq(StageNames)]           관측 ③: 지나간 상태열
    rawObs     \* [Worlds -> Datums \cup {NoDatum}]  내부 탐침 — 파이프에 실린 원시 값

vars == <<valid, data, fill, hostEnt, pend, fwd,
          obsKind, obsVal, trace, rawObs>>

TypeOK ==
    /\ valid \in [Worlds -> [Slots -> BOOLEAN]]
    /\ data \in [Worlds -> [Slots -> Datums]]
    /\ fill \in [Worlds -> [Partitions -> (Slots \X Datums) \cup {NoFill}]]
    /\ hostEnt \in [Worlds -> (Indices \X Datums) \cup {NoEnt}]
    /\ pend \in Indices \cup {NoReq}
    /\ fwd \in [Worlds -> Datums \cup {NoDatum}]
    /\ obsKind \in [Worlds -> {"none", "value", "fault"}]
    /\ obsVal \in [Worlds -> Datums \cup {NoDatum}]
    /\ rawObs \in [Worlds -> Datums \cup {NoDatum}]
    /\ \A w \in Worlds : \A k \in 1..Len(trace[w]) : trace[w][k] \in StageNames

SomeDatum == CHOOSE d \in Datums : TRUE

Init ==
    \* 유효 비트는 전부 내려 있으나 *데이터는 이미 무언가를 담고 있다* —
    \* §3.6.3 이 "flush 는 데이터를 남긴다" 로 못박은 것과 같은 자리다.
    /\ valid = [w \in Worlds |-> [s \in Slots |-> FALSE]]
    /\ data = [w \in Worlds |-> [s \in Slots |-> SomeDatum]]
    /\ fill = [w \in Worlds |-> [p \in Partitions |-> NoFill]]
    /\ hostEnt = [w \in Worlds |-> NoEnt]
    /\ pend = NoReq
    /\ fwd = [w \in Worlds |-> NoDatum]
    /\ obsKind = [w \in Worlds |-> "none"]
    /\ obsVal = [w \in Worlds |-> NoDatum]
    /\ trace = [w \in Worlds |-> << >>]
    /\ rawObs = [w \in Worlds |-> NoDatum]

(***************************************************************************)
(* 구조 선택 둘 — 가드가 켜져 있으면 정본이 요구하는 결과를 낸다.          *)
(*                                                                         *)
(* install_scoped — 저장 블록의 *항목 주소*가 파티션을 구분하는가.          *)
(*   근거는 §3.6.2 규범 1("적중은 *파티션과 가상 페이지 번호(VPN)가 모두 일치*하고 유효 *)
(*   비트가 서 있을 때만 성립한다")과 #속성 HIU-1 이다. §3.6.1 의          *)
(*   `{파티션, 색인}` 연접은 #해설이지 #규범이 아니다 — 바로 뒤의 #규범     *)
(*   「재구현에 대한 요건 — 결과지 방법이 아니다」가 요구하는 결과는        *)
(*   곱셈 없음과 메모리 자원 추론 둘뿐이고, *파티션 필드를 주소에 넣으라고  *)
(*   구속하지 않는다.* 그래서 이 가드의 근거를 규범 쪽으로 옮겨 적었다.    *)
(*   (초판은 §3.6.1 해설을 규범처럼 인용했고, 적대 검증이 그것을 지적했다.)*)
(*                                                                         *)
(* capacity_partitioned — 저장 *용량*이 파티션 사이에서 나뉘는가.           *)
(*   지우면 q 의 설치가 같은 색인의 p 항목을 밀어낸다. 주소 구조도 태그도   *)
(*   정상인데 p 가 미적중한다 — §5.1 3항이 위협 모델에 넣은 캐시 타이밍     *)
(*   채널의 형태 그대로다. 근거는 #속성 SEC-4 자신이다.                    *)
(***************************************************************************)
TargetSlot(q, i) == IF On("install_scoped") THEN <<q, i>> ELSE <<Subject, i>>

FillSlotOf(p) == IF On("fill_slot_per_partition") THEN p ELSE Subject

(***************************************************************************)
(* 세 개의 읽기 경로.                                                      *)
(*                                                                         *)
(* ① 저장 블록 조회 — 항목 주소가 파티션을 구분하면 p 의 조회는            *)
(*    <<Subject, i>> 만 본다. install_scoped 가 그것을 시험한다.           *)
(*                                                                         *)
(* ② 공유 채움 버퍼 바이패스 — 미적중을 상위 계층이 채우는 경로(§3.6.2     *)
(*    규범 3)의 in-flight 줄을 조회에 곧바로 돌려주는 흔한 구현이다.        *)
(*    이것이 두 번째 읽기 경로이며, 채움을 두 걸음으로 쪼갠 덕분에         *)
(*    *실제로 판정을 혼자 정할 수 있다* (Witness_NoInflightBypass 가        *)
(*    반증되는 것이 그 증명이다). 초판에서는 이 가지가 죽은 코드였다.      *)
(*                                                                         *)
(*    fill_tagged 를 지우면 이 경로가 색인만 보고 파티션을 보지 않는다.     *)
(*    그러면 q 의 채움이 p 의 요청에 적중하고 — 저장 블록의 판정은 여전히   *)
(*    옳은데도 격리가 깨진다. §3.6.3 함정이 "하나라도 빠지면" 이라고 적은   *)
(*    그 하나가 이것이다.                                                  *)
(*                                                                         *)
(* ③ 호스트 응답 항목 — 선택적 경로(§3.3.1)가 남기는 상태. 가드 없이       *)
(*    읽힌다. 중립성은 *읽기*가 아니라 *채움*을 제한해서 얻는다             *)
(*    (query_no_serve).                                                    *)
(*                                                                         *)
(* 우선순위는 §3.6.2 규범 2 가 확정한 순서 그대로다 — in-flight 채움(최신)  *)
(* > 저장 블록 > 호스트 응답, 후보 복수면 자기 파티션 우선. 최신이 이기는   *)
(* 것이 바이패스의 뜻(신선도)이고, 호스트 응답이 마지막인 것은 선택적       *)
(* 경로가 가속이지 authority 가 아니기 때문이다 (HIU-8).                    *)
(***************************************************************************)
StoreHit(w, i) == valid[w][<<Subject, i>>]

BypassCands(w, i) ==
    {p \in Partitions :
        /\ fill[w][p] # NoFill
        /\ fill[w][p][1][2] = i
        /\ ((~On("fill_tagged")) \/ fill[w][p][1][1] = Subject)}

BypassHit(w, i) == BypassCands(w, i) # {}

\* §3.6.2 규범 2 (확정) — 경로 사이 전순서에 더해, 후보 복수면 자기 파티션 우선.
BypassPick(w, i) ==
    IF Subject \in BypassCands(w, i)
      THEN Subject
      ELSE CHOOSE p \in BypassCands(w, i) : TRUE

HostHit(w, i) == hostEnt[w] # NoEnt /\ hostEnt[w][1] = i

Approved(w, i) == BypassHit(w, i) \/ StoreHit(w, i) \/ HostHit(w, i)

SelectedDatum(w, i) ==
    IF BypassHit(w, i) THEN fill[w][BypassPick(w, i)][2]
    ELSE IF StoreHit(w, i) THEN data[w][<<Subject, i>>]
    ELSE hostEnt[w][2]

(***************************************************************************)
(* 승인 이전에 파이프에 실리는 원시 값.                                    *)
(*                                                                         *)
(* §3.2 규범이 승인(6)을 실행(5)보다 뒤에 둔 이유가 여기 있다 — 판정이      *)
(* 경로를 가르면 소요 사이클이 판정에 의존한다. 그 대가로 실행 단계는       *)
(* *미적중이어도 무언가를 싣는다.* 이 값에는 게이팅이 없다. 그것이 요점이다.*)
(* 채움 버퍼를 태그 없이 훑는 것이 그 「게이팅 없음」 의 형식이다.          *)
(***************************************************************************)
RawCands(w, i) ==
    {p \in Partitions : fill[w][p] # NoFill /\ fill[w][p][1][2] = i}

RawPick(w, i) ==
    IF Subject \in RawCands(w, i)
      THEN Subject
      ELSE CHOOSE p \in RawCands(w, i) : TRUE

RawDatum(w, i) ==
    IF RawCands(w, i) # {}
      THEN fill[w][RawPick(w, i)][2]
      ELSE data[w][<<Subject, i>>]

(***************************************************************************)
(* 요청이 지나는 상태열 — §3.2 순서 계약의 6단계.                          *)
(*                                                                         *)
(*   accept  요청 접수 · delay 고정 지연 · lookup 변환표 조회               *)
(*   mask    물리 주소 마스킹 · exec 요청 실행 · 그리고 접근 승인           *)
(*                                                                         *)
(* 접근 승인(6)이 두 변종을 갖는다. §3.4.1 규범 「일관성이 있어도 규약은    *)
(* 남는다」는 하드웨어 일관성이 있을 때 *비우기 의무만* 생략할 수 있고      *)
(* 소유권 상태 기계는 그대로 유지한다고 못박는다. 그 상태 기계를 지나는    *)
(* 승인이 "approve_own" 이고, 일관성을 이유로 그것을 건너뛴 승인이         *)
(* "approve_coh" 다. 길이는 같고 열이 다르다 — 그것이 이 모델이 §5.3 의    *)
(* "절대 사이클 수가 아니라 경로 간 동일성" 을 형식화하는 지점이다.        *)
(*                                                                         *)
(* 단계를 하나 *더* 만들지 않았다. §3.2 규범이 소유권·자격 확인의 자리를   *)
(* *접근 승인(6) 안*으로 확정했다 — 일곱째 단계도 전단 확인도 없다 (근거:  *)
(* SEC-2 상태열 동일성이 전단 확인을 배제한다). 승인 안의 변종이라는 이    *)
(* 모델의 배치는 그 규범이 확정한 자리다 (비덮개 목록 참조).               *)
(*                                                                         *)
(* 고정 지연은 *가드가 아니다.* 이 모델에서 그것을 빼면 네 세계의 상태열이  *)
(* 똑같이 짧아질 뿐이므로 어떤 불변식도 깨지지 않는다 — 지워도 통과하는     *)
(* 가드는 두지 않는다는 §6.3.2 규율에 따라 무조건 단계로 적었다.           *)
(*                                                                         *)
(* 이탈 단계 셋이 각각 하나의 채널을 표현한다:                             *)
(*                                                                         *)
(*   fwait      공유 채움 경로를 기다린다 → p 의 타이밍이 q 에 의존한다     *)
(*   query,qwait 호스트 변환 질의 왕복이 요청 경로 위에 올라온다 (§3.3.1     *)
(*              "질의 왕복은 가변 지연이다") → 구성에 따라 상태열이 달라진다*)
(***************************************************************************)
Trace(w, i) ==
       <<"accept", "delay", "lookup">>
    \o (IF (~On("fill_offpath")) /\ (\E p \in Partitions : fill[w][p] # NoFill)
          THEN <<"fwait">> ELSE << >>)
    \o (IF (~On("query_offpath")) /\ IsOn(w) /\ (~StoreHit(w, i))
          THEN <<"query", "qwait">> ELSE << >>)
    \o <<"mask", "exec">>
    \o <<IF On("coh_no_shortcut") \/ (~IsOn(w))
           THEN "approve_own" ELSE "approve_coh">>

(***************************************************************************)
(* 관측을 소비한다 — 남겨 두면 후속 단계에서 낡은 관측이 속성을 다시 걸어  *)
(* 거짓 반례를 만든다 (XlateStore 모델에서 실측한 실패형).                  *)
(* fwd 는 여기서 지우지 않는다 — 그것을 회수하는 것은 승인의 몫이며,       *)
(* 회수 시점이 곧 §3.2 규범 1 이 말하는 시간축이기 때문이다.               *)
(***************************************************************************)
ClearObs ==
    /\ obsKind' = [w \in Worlds |-> "none"]
    /\ obsVal' = [w \in Worlds |-> NoDatum]
    /\ trace' = [w \in Worlds |-> << >>]
    /\ rawObs' = [w \in Worlds |-> NoDatum]

(***************************************************************************)
(* Subject 의 채움 — 상위 계층이 p 의 미적중을 채운다 (§3.6.2 규범 3).      *)
(* **네 세계 전부에 같은 인자로** 들어간다 (§3.4.2 함정).                   *)
(*                                                                         *)
(* 두 걸음이다. 첫 걸음은 채움 버퍼 자리를 점유할 뿐 저장 블록을 건드리지  *)
(* 않는다 — 그 사이가 바이패스가 유일한 적중원인 창이고, 동시에 남의       *)
(* 설치가 그 줄을 축출할 수 있는 창이다.                                   *)
(***************************************************************************)
SubjectFillStart(i, d) ==
    /\ fill' = [w \in Worlds |-> [fill[w] EXCEPT ![Subject] = <<<<Subject, i>>, d>>]]
    /\ ClearObs
    /\ UNCHANGED <<valid, data, hostEnt, pend, fwd>>

(***************************************************************************)
(* 커밋 — 버퍼에 실린 줄이 저장 블록으로 들어간다.                         *)
(*                                                                         *)
(* 동작은 네 세계에 같은 인자로 걸리지만 *효과*는 세계마다 다를 수 있다 —  *)
(* 버퍼 자리를 남이 덮어썼다면 그 세계는 다른 줄을 커밋하거나 커밋할 것이  *)
(* 없다. 그 비대칭이 곧 fill_slot_per_partition 이 막는 채널이며, 좋은     *)
(* 모델에서는 네 세계의 버퍼가 같으므로 효과도 같다.                       *)
(***************************************************************************)
SubjectFillCommit ==
    /\ \E w \in Worlds : fill[w][Subject] # NoFill
    /\ valid' = [w \in Worlds |->
                   IF fill[w][Subject] # NoFill
                     THEN [valid[w] EXCEPT ![fill[w][Subject][1]] = TRUE]
                     ELSE valid[w]]
    /\ data' = [w \in Worlds |->
                  IF fill[w][Subject] # NoFill
                    THEN [data[w] EXCEPT ![fill[w][Subject][1]] = fill[w][Subject][2]]
                    ELSE data[w]]
    /\ fill' = [w \in Worlds |-> [fill[w] EXCEPT ![Subject] = NoFill]]
    /\ ClearObs
    /\ UNCHANGED <<hostEnt, pend, fwd>>

(***************************************************************************)
(* 타 파티션의 채움 — **한쪽 QSide 의 두 세계에만** 건다.                   *)
(*                                                                         *)
(* 이것이 네 세계를 QSides 축으로 갈라놓는 유일한 것이다. 즉 두 갈래는      *)
(* "q 가 설치한 상태" 에서만 다르다 — SEC-4 가 요구하는 비교의 형태 그대로. *)
(*                                                                         *)
(* q 의 설치가 남기는 것이 셋이다:                                         *)
(*   - 저장 블록의 자기 항목 (install_scoped 가 켜져 있으면 p 가 닿지 못한다)*)
(*   - 채움 버퍼의 잔여물 (fill_tagged · fill_offpath 가 지킨다)           *)
(*   - 그리고 *용량* — 자기가 자리를 차지하면서 남의 것을 밀어낼 수 있다    *)
(*     (capacity_partitioned · fill_slot_per_partition 가 지킨다)          *)
(*                                                                         *)
(* 셋째가 초판에 없던 것이고, 적대 검증이 blocking 으로 지목한 것이다.     *)
(***************************************************************************)
OtherFill(q, i, d, qs) ==
    LET s == TargetSlot(q, i)
        k == FillSlotOf(q)
        Evict(vv) == IF On("capacity_partitioned") \/ s = <<Subject, i>>
                       THEN vv
                       ELSE [vv EXCEPT ![<<Subject, i>>] = FALSE]
    IN
    /\ valid' = [w \in Worlds |->
                   IF w[1] = qs
                     THEN Evict([valid[w] EXCEPT ![s] = TRUE])
                     ELSE valid[w]]
    /\ data' = [w \in Worlds |-> IF w[1] = qs
                                   THEN [data[w] EXCEPT ![s] = d]
                                   ELSE data[w]]
    /\ fill' = [w \in Worlds |-> IF w[1] = qs
                                   THEN [fill[w] EXCEPT ![k] = <<s, d>>]
                                   ELSE fill[w]]
    /\ ClearObs
    /\ UNCHANGED <<hostEnt, pend, fwd>>

(***************************************************************************)
(* 선택적 호스트 서비스 경로가 동작한다 — "on" 세계에서만.                 *)
(*                                                                         *)
(* §3.3.1 이 기각한 대안이 정확히 이 형태다 — 변환 항목을 *호스트의 주소   *)
(* 변환 서비스에 질의해서* 채우는 것. 기각했으므로 재구현이 이 경로를      *)
(* 넣더라도 §3.3.1 규범 1 이 남는다: "변환은 *장치 안*에서 완결돼야 한다.  *)
(* 호스트 변환 서비스의 존재를 정상 경로의 전제로 두지 않는다."            *)
(*                                                                         *)
(* query_no_serve 가 그 규범이다 — 호스트 응답 항목은 *장치가 이미 가진    *)
(* 것*만 담을 수 있다. 지우면 호스트가 장치에 없는 항목을 만들어 내고,     *)
(* 그 순간 on 구성만 적중한다. 그것이 §3.3 규범 2 가 금지하는 것의 거울상  *)
(* 이다 — 없는 호스트에서 기능이 줄면 안 된다는 말은 있는 호스트에서       *)
(* 기능이 늘면 안 된다는 말과 같은 종속이며, 정본 §3.4.1 이 그 대칭을      *)
(* 이미 못박았다 ("반대 방향도 같은 종속이다").                            *)
(*                                                                         *)
(* 가드는 *읽기*가 아니라 *채움*을 제한한다. 읽기(Approved · SelectedDatum)*)
(* 에는 On(...) 이 없다 — 그래야 hostEnt 가 관측 경로 위에 있다고 말할 수  *)
(* 있고, 중립성이 구성이 아니라 계약에서 온다.                             *)
(***************************************************************************)
HostQuery(i, d) ==
    /\ hostEnt' = [w \in Worlds |->
                     IF /\ IsOn(w)
                        /\ \/ ~On("query_no_serve")
                           \/ /\ valid[w][<<Subject, i>>]
                              /\ data[w][<<Subject, i>>] = d
                       THEN <<i, d>>
                       ELSE hostEnt[w]]
    /\ ClearObs
    /\ UNCHANGED <<valid, data, fill, pend, fwd>>

(***************************************************************************)
(* 요청 — 유일한 관측점. **네 세계에 같은 인자로 동시에.**                 *)
(*                                                                         *)
(* 실행(5)과 승인(6) 사이에 상태가 있다. §3.2 규범 1 은 시간적 문장이므로  *)
(* ("읽기 결과는 승인 이전에 소비자에게 도달하지 않는다") 그 사이가 없으면 *)
(* 일시 누출형을 표현할 수 없다.                                           *)
(*                                                                         *)
(* no_early_forward 는 그 규범을 그대로 옮긴 가드다. 지우면 실행 단계가    *)
(* 원시 값을 소비자에게 앞당겨 싣고, 승인에서 회수하더라도 *그 사이에      *)
(* 이미 관측된다.* approve_gates_value(값축)는 그것을 잡지 못한다 —        *)
(* 최종 obsVal 은 승인 시점에만 표본되기 때문이다. 둘은 같은 규범의 서로   *)
(* 다른 두 항이며 배터리가 그 짝을 실측한다.                               *)
(***************************************************************************)
RequestExec(i) ==
    /\ pend = NoReq
    /\ pend' = i
    /\ rawObs' = [w \in Worlds |-> RawDatum(w, i)]
    /\ fwd' = [w \in Worlds |->
                 IF On("no_early_forward") THEN NoDatum ELSE RawDatum(w, i)]
    /\ obsKind' = [w \in Worlds |-> "none"]
    /\ obsVal' = [w \in Worlds |-> NoDatum]
    /\ trace' = [w \in Worlds |-> << >>]
    /\ UNCHANGED <<valid, data, fill, hostEnt>>

(***************************************************************************)
(* 승인 — 판정이 경로를 가르지 않고 *결과를 게이트*한다 (§3.2 규범).       *)
(*                                                                         *)
(* approve_gates_value 는 §3.2 규범 1·2 를 그대로 옮긴 가드다:             *)
(*   "실행 단계는 승인 이전에 외부에 관측 가능한 부수 효과를 내지 않는다."  *)
(*   "미승인 요청의 관측 결과는 fault 와 ... 타이밍뿐이다. 값이 새면        *)
(*    격리 위반이고, 타이밍이 다르면 부채널이다."                          *)
(* 지우면 미적중 요청이 *fault 를 내면서도* 원시 값을 흘린다 — 그 값은      *)
(* 공유 채움 버퍼에서 왔으므로 q 에 의존한다.                              *)
(***************************************************************************)
RequestApprove ==
    /\ pend # NoReq
    /\ obsKind' = [w \in Worlds |->
                     IF Approved(w, pend) THEN "value" ELSE "fault"]
    /\ obsVal' = [w \in Worlds |->
                    IF Approved(w, pend) THEN SelectedDatum(w, pend)
                    ELSE IF On("approve_gates_value") THEN NoDatum
                    ELSE RawDatum(w, pend)]
    /\ trace' = [w \in Worlds |-> Trace(w, pend)]
    /\ rawObs' = [w \in Worlds |-> NoDatum]
    /\ fwd' = [w \in Worlds |-> NoDatum]
    /\ pend' = NoReq
    /\ UNCHANGED <<valid, data, fill, hostEnt>>

Next ==
    \/ \E i \in Indices, d \in Datums : SubjectFillStart(i, d)
    \/ SubjectFillCommit
    \/ \E q \in Others, i \in Indices, d \in Datums, qs \in QSides :
           OtherFill(q, i, d, qs)
    \/ \E i \in Indices, d \in Datums : HostQuery(i, d)
    \/ \E i \in Indices : RequestExec(i)
    \/ RequestApprove

Spec == Init /\ [][Next]_vars

(***************************************************************************)
(* 불변식 — 여덟 다 **두 세계의 비교**다. 한 세계 안에서는 아무것도 말하지 *)
(* 않는다. 그것이 비간섭 속성의 형태이며 §3.4.2 규범이 요구하는 것이다.    *)
(*                                                                         *)
(* 앞 넷은 QSides 축(SEC-4), 뒤 넷은 Opts 축(HIU-11)이다. 두 축이 *같은    *)
(* 관측 목록*을 본다 — 초판은 Opts 축에서 상태열 하나만 봤고, §3.3 규범 2  *)
(* ("지원하지 않는 호스트에서 기능이 줄면 안 된다")가 겨누는 판정·값 축이  *)
(* 검사 대상이 아니었다. 적대 검증이 그것을 지적했다.                      *)
(***************************************************************************)

\* SEC-4 (판정 축) — *미적중이라는 사실 자체*가 q 에 의존하지 않는다.
\* 남의 항목이 있고 없고에 따라 p 가 적중하거나 미적중하면 그것이 채널이다.
\*
\* 네 가드가 이 하나를 공유한다 — fill_tagged(버퍼 태그),
\* fill_slot_per_partition(버퍼 용량), capacity_partitioned(저장 용량),
\* 그리고 install_scoped 도 형상에 따라 여기서 먼저 깨진다. 약점이 아니다:
\* *각각* 지웠을 때 *각각* 깨지므로 전부 독립적으로 필요하다는 것이
\* 증명된다 (NoLoss.tla 의 Inv_Conservation 과 같은 형태).
Inv_VerdictNonInterference ==
    \A o \in Opts : obsKind[<<"qA", o>>] = obsKind[<<"qB", o>>]

\* SEC-4 (값 축) — 돌려받은 값이 q 에 의존하지 않는다.
\* 승인되지 않은 요청이 흘린 값도 여기에 걸린다 (§3.2: "값이 새면 격리 위반").
Inv_ValueNonInterference ==
    \A o \in Opts : obsVal[<<"qA", o>>] = obsVal[<<"qB", o>>]

\* SEC-4 (타이밍 축) — 지나간 *상태열*이 q 에 의존하지 않는다 (§3.2: "타이밍이
\* 다르면 부채널"). 공유 자원을 기다리는 순간이 상태열에 나타나면 위반이다.
Inv_TraceNonInterference ==
    \A o \in Opts : trace[<<"qA", o>>] = trace[<<"qB", o>>]

\* SEC-4 (시간축) — *승인 이전에* 소비자에게 실린 값이 q 에 의존하지 않는다.
\* §3.2 규범 1 의 시간적 문장을 그대로 옮긴 것이다. 값 축(obsVal)은 승인
\* 시점에만 표본되므로 일시 누출을 보지 못한다 — 이것이 그 틈을 덮는다.
\*
\* 좋은 모델에서 이것은 *공허하게 참*이다 — no_early_forward 가 fwd 를
\* 언제나 NoDatum 으로 묶기 때문이다. NoLoss.tla 의 Inv_NoSilentTruncation
\* 과 같은 자리이며, 내용을 주는 것은 두 run 의 짝이다:
\*   Witness_NoRawSkew 반증  — 앞당겨 실을 값이 *실제로* q 에 의존한다
\*   del_no_early_forward    — 가드가 없으면 그 값이 실제로 실린다
\* 둘 중 하나라도 없으면 이 불변식은 장식이다.
Inv_ForwardNonInterference ==
    \A o \in Opts : fwd[<<"qA", o>>] = fwd[<<"qB", o>>]

\* HIU-11 (타이밍 축) — 선택적 경로의 유무가 상수 시간 계약을 바꾸지 않는다.
\* §5.3 대로 *상태열*을 비교한다. 사이클 수가 아니다.
Inv_OptionalPathNeutral ==
    \A qs \in QSides : trace[<<qs, "off">>] = trace[<<qs, "on">>]

\* 일부러 약하게 적은 형태 — 사이클 수만 본다.
\* del_coh_no_shortcut 에서 이것은 **통과하고** Inv_OptionalPathNeutral 은
\* 깨진다. 그 짝이 §5.3 규범 "절대 사이클 수가 아니라 경로 간 동일성" 의
\* 형식적 형태다. 계약을 숫자로 적으면 이 결함형에 눈이 먼다.
\*
\* 장식이 아니라는 것은 비대칭이 말한다 — 이 불변식은 del_query_offpath 는
\* 잡고(질의 왕복이 열을 *늘린다*) del_coh_no_shortcut 은 놓친다(승인의
\* 변종은 길이를 바꾸지 않는다). 즉 숫자 검사가 잡는 것이 있고 놓치는 것이
\* 있으며, 놓치는 쪽이 정확히 정본이 경계하라고 적은 축이다.
Inv_OptionalPathSameCycles ==
    \A qs \in QSides : Len(trace[<<qs, "off">>]) = Len(trace[<<qs, "on">>])

\* HIU-11 (판정 축) — §3.3 규범 2 의 직접 형식화. "지원하지 않는 호스트에서
\* 기능이 줄면 안 된다" 는 타이밍이 아니라 *판정*의 문장이다.
Inv_OptSameVerdict ==
    \A qs \in QSides : obsKind[<<qs, "off">>] = obsKind[<<qs, "on">>]

\* HIU-11 (값 축) — 같은 규범의 값 쪽. 두 구성이 같은 값을 돌려준다.
Inv_OptSameValue ==
    \A qs \in QSides : obsVal[<<qs, "off">>] = obsVal[<<qs, "on">>]

(***************************************************************************)
(* 위험 도달성 증인 — 좋은 모델에서 반드시 반증돼야 한다.                  *)
(*                                                                         *)
(* 비간섭 불변식은 좋은 모델에서 *구조적으로* 참이다 — p 의 출력이 lockstep *)
(* 상태만 보기 때문이다. 그래서 그 통과에 내용을 주는 것은 증인이다.       *)
(* NoLoss.tla 의 Inv_NoSilentTruncation 과 같은 자리이며, 증인이 하나라도   *)
(* 반증되지 않으면 그 축의 불변식은 장식이다.                              *)
(*                                                                         *)
(* 일곱이 서로 다른 명제여야 한다. 초판은 optUsed 위에 두 증인을 세웠는데  *)
(* off 쪽이 구조적으로 언제나 FALSE 라 둘이 같은 명제였고, 적대 검증이     *)
(* 그것을 지적했다. 이 판에서 그 자리는 hostEnt 어긋남 하나와 바이패스     *)
(* 도달성 하나로 갈라졌다.                                                 *)
(***************************************************************************)

\* p 가 실제로 값을 받는가. 안 받으면 값 축 전부가 공허하다.
Witness_NoSubjectValue == \A w \in Worlds : obsKind[w] # "value"

\* p 가 실제로 미적중하는가. 미적중이 도달 불가면 approve_gates_value 와
\* query_offpath 가 아무것도 막지 않는다.
Witness_NoSubjectMiss == \A w \in Worlds : obsKind[w] # "fault"

\* 공유 채움 경로가 실제로 *남의 것*으로 점유되는가.
\* 반증되지 않으면 fill_tagged 도 fill_offpath 도 공허하다.
Witness_NoForeignFill ==
    \A w \in Worlds, p \in Partitions :
        fill[w][p] = NoFill \/ fill[w][p][1][1] = Subject

\* 두 QSide 의 내부 상태가 **실제로 어긋나는가.**
\* 이것이 반증되지 않으면 SEC-4 의 통과는 "두 갈래가 사실 같아서" 이고
\* 아무것도 뜻하지 않는다. Platform.tla 의 Witness_NoMemSkew 와 같은 자리다.
Witness_NoQSkew ==
    \A o \in Opts :
        /\ \A s \in Slots :
              /\ valid[<<"qA", o>>][s] = valid[<<"qB", o>>][s]
              /\ data[<<"qA", o>>][s] = data[<<"qB", o>>][s]
        /\ \A p \in Partitions : fill[<<"qA", o>>][p] = fill[<<"qB", o>>][p]

\* 승인 이전에 파이프에 실린 원시 값이 **실제로 q 에 의존하는가.**
\* 반증되지 않으면 approve_gates_value 와 no_early_forward 가 막는 것이
\* 실재하지 않는다.
Witness_NoRawSkew ==
    \A o \in Opts : rawObs[<<"qA", o>>] = rawObs[<<"qB", o>>]

\* **바이패스가 실제로 판정을 혼자 정하는가.**
\* 이것이 반증되지 않으면 두 번째 읽기 경로는 죽은 코드이고, "읽기 경로가
\* 여럿" 이라는 이 모델의 존재 이유 절반이 이름뿐이다. 초판이 정확히 그
\* 상태였다 — 채움이 한 걸음이라 BypassHit => StoreHit 가 자동으로 참이었다.
Witness_NoInflightBypass ==
    \A w \in Worlds, i \in Indices : BypassHit(w, i) => StoreHit(w, i)

\* 두 구성의 **관측이 읽는 상태**가 실제로 어긋나는가.
\* hostEnt 는 Approved · SelectedDatum 이 가드 없이 읽는 변수다. 이것이
\* 반증되지 않으면 HIU-11 의 통과는 "선택적 경로가 아무것도 하지 않아서"
\* 이고, §3.4.2 해설이 적은 "어긋남이 아예 없다면 두 구성의 구분은 이름뿐"
\* 그 자리가 된다. Platform.tla 의 Witness_NoMemSkew 와 같은 자리다.
Witness_NoOptStateSkew ==
    \A qs \in QSides : hostEnt[<<qs, "off">>] = hostEnt[<<qs, "on">>]

=============================================================================
