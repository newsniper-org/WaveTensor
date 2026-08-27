// SPDX-License-Identifier: CC-BY-4.0
// SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors

#import "../lib/template.typ": *

#pagebreak()
= 용어집 <sec:glossary>

국문 정본 · 영문 대응 · 정의 위치.

== 기계

#table(
  columns: (auto, auto, auto, 1fr),
  align: (left, left, left, left),
  table.header([*국문*], [*영문*], [*절*], [*뜻*]),
  [WT64v1], [WaveTensor 64-bit Dataflow ISA v1], [@sec:preface], [이 문서의 대상 — 데이터플로 텐서 가속기 규약],
  [데이터플로], [dataflow], [@sec:preface], [실행 시점을 *피연산자 도착*이 정하는 모델],
  [토큰], [token], [@sec:preface], [64비트 페이로드 + 80비트 태그],
  [호스트 인터페이스 · HIU], [Host Interface Unit], [@sec:hiu], [*호스트가 장치에 닿는 유일한 경계*],
  [DVMA], [Direct Virtual Memory Access], [@sec:hiu], [장치가 *가상 주소*로 메모리 접근. 호스트 MMU 유무와 무관해야 한다],
  [zero-copy], [zero-copy], [@sec:hiu], [호스트와 장치가 *같은 페이지*를 직접 봄 — 복사 없음. *일관성과 다르다*],
  [캐시 일관성], [coherency], [@sec:hiu], [하드웨어가 같은 값을 보장. zero-copy 보다 *강한* 성질이며 요건이 아니다],
)

== 구조

#table(
  columns: (auto, auto, auto, 1fr),
  align: (left, left, left, left),
  table.header([*국문*], [*영문*], [*절*], [*뜻*]),
  [PE], [Processing Element], [@sec:fabric], [연산을 수행하는 단위. 이종],
  [클러스터], [Cluster], [@sec:fabric], [PE 그리드 + 공유 디코더 + 결과 뱅크],
  [Pod], [Pod], [@sec:fabric], [클러스터 그리드. 현행 최상위],
  [Global Grid], [Global Grid], [@sec:fabric], [Pod 상위 결합. *설계 의도만 존재*],
  [결과 뱅크], [result bank], [@sec:fabric], [생산자의 직전 출력을 담는 슬롯 집합],
)

== 명령어

#table(
  columns: (auto, auto, auto, 1fr),
  align: (left, left, left, left),
  table.header([*국문*], [*영문*], [*절*], [*뜻*]),
  [기본 헤더], [base header], [@sec:isa], [32비트. 항상 존재],
  [확장 헤더 · EH], [extension header], [@sec:isa], [사슬로 붙는 가변 길이 단위],
  [종료 표식], [sentinel / END], [@sec:extpayload], [사슬의 끝. *종료의 authority*],
  [태그], [tag], [@sec:isa], [토큰과 함께 흐르는 80비트 식별 정보],
  [조각열], [fragment sequence], [@sec:extpayload], [4.3 의 다섯 조건을 만족하는 전송 묶음. *하나로 센다*],
  [조각], [fragment], [@sec:extpayload], [조각열의 원소인 부분 전송 단위],
  [고정 순회], [fixed walk], [@sec:extpayload], [슬롯 상한만큼 고정 횟수 순회],
  [lowering], [lowering], [@sec:isa], [고수준 표현을 실행 가능한 명령열로 낮추기],
)

== 논리 이름

#table(
  columns: (auto, auto, auto, 1fr),
  align: (left, left, left, left),
  table.header([*국문*], [*영문*], [*절*], [*뜻*]),
  [논리 노드 ID · LNID], [Logical Node ID], [@sec:isa], [16비트. *토큰의 수신자*],
  [논리 뱅크 ID · LBID], [Logical Bank ID], [@sec:isa], [8비트. *읽을 결과 슬롯*],
  [사상표], [mapping table], [@sec:isa], [논리 이름 → 물리 자원. *머신 구성*],
  [형상 독립성], [topology-agnosticism], [@sec:isa], [같은 바이너리가 다른 형상에서 같은 의미],
  [미사상], [unmapped], [@sec:isa], [사상표에 없음. *불법 인코딩이 아니다*],
)

== 오류

#table(
  columns: (auto, auto, auto, 1fr),
  align: (left, left, left, left),
  table.header([*국문*], [*영문*], [*절*], [*뜻*]),
  [malformation], [malformation], [@sec:isa], [*바이너리가 틀렸다* — 컴파일러가 고친다],
  [능력 부재], [capability absence], [@sec:isa], [*이 유닛에 그 능력이 없다* — 상위가 분해],
  [route fault], [route fault], [@sec:isa], [*머신 구성이 틀렸다* — 부트 코드가 고친다],
  [sticky fault], [sticky fault], [@sec:hiu], [한 번 서면 명시적 해제까지 유지],
  [폴딩], [folding], [@sec:security], [여러 fault 를 종합 신호로 모으기],
  [주소 마스킹], [address masking], [@sec:security], [물리 주소를 키스트림으로 가리기],
  [확산], [diffusion], [@sec:security], [입력 1비트가 출력 전반에 퍼지는 성질. *의존 ≠ 확산*],
  [loud fault], [loud fault], [@sec:security], [*조용히 실패하지 않는다* — 이 프로젝트의 제1규율],
)

== 연산

#table(
  columns: (auto, auto, auto, 1fr),
  align: (left, left, left, left),
  table.header([*국문*], [*영문*], [*절*], [*뜻*]),
  [step sequencer], [step sequencer], [@sec:fabric], [스칼라 부동소수점 유닛의 순차 제어기],
  [step], [step], [@sec:fabric], [그 제어기의 한 단계],
  [단일 공유 곱셈기], [single shared multiplier], [@sec:fabric], [모든 step 프로그램이 재사용하는 유일한 곱셈기],
  [배압], [back-pressure], [@sec:fabric], [소비자가 받을 수 없음을 알리는 신호],
)

#규범(라벨: "금지 용어 — 다시 한 번")[
  *"마이크로코드" / "microcode"* 는 이 문서와 이 프로젝트 전체에서
  *사용하지 않는다.* 정본은 *step sequencer / step* 이다.
]

== 검증

#table(
  columns: (auto, auto, auto, 1fr),
  align: (left, left, left, left),
  table.header([*국문*], [*영문*], [*절*], [*뜻*]),
  [형식 검증], [formal verification], [@sec:formal], [*모든 도달 가능 상태*에 대한 논증. 테스트와 다르다],
  [속성], [property], [@sec:formal], [검사 대상 명제 하나. 번호·단계·상태를 갖는다],
  [선-formal], [pre-formal], [@sec:formal], [RTL 이전에 모델 위에서 속성 검사],
  [후-formal], [post-formal], [@sec:formal], [구현된 RTL 에 대해 같은 속성 검사],
  [가드 삭제 실험], [guard-deletion experiment], [@sec:formal], [보호 조건을 지워 속성의 검출력 확인],
  [지향 테스트], [directed test], [@sec:formal], [반례에서 유래한 특정 시나리오 테스트],
  [golden 모델], [golden model], [@sec:formal], [산술 의미론의 authority. 비트 단위 기대값],
  [게이트], [gate], [@sec:capacity], [기계가 판정하는 측정 기준],
  [사전 공표], [pre-declaration], [@sec:formal], [*측정 이전에* 기준을 공표하는 것],
  [상수 시간성], [constant-time], [@sec:security], [절대치가 아니라 *경로 간 동일성*],
)

== 출처 등급

#table(
  columns: (auto, 1fr),
  align: (left, left),
  [#등급("실측")], [도구를 실제로 돌려 얻은 값. *실리콘 관측이 아니다*],
  [#등급("유도")], [실측값에서 산술로 유도. 근거를 함께 적는다],
  [#등급("목표")], [측정 *이전에* 공표된 기준],
  [#등급("미측정")], [아직 재지 않음. 추측으로 채우지 않는다],
)
