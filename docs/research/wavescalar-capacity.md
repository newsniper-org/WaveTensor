<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# 패브릭보다 큰 프로그램 — WaveScalar 와 파생 아키텍처들의 용량 초과 처리

> **비정본 — 조사 자료.** 정본은 `docs/wt64v1-architecture-guide/` 다.
> 이 문서는 문헌 조사의 종합이며 설계 결정이 아니라 **설계 입력**이다.
> WT64v1 현행에 대한 서술은 전부 정본 문면에서 확인한 것이고, 원전 문헌에
> 대한 서술은 각 절 말미·본문의 출처 표기가 근거다. 조사가 확보하지 못한
> 것은 §7 에 정직하게 남겼다.

**조사 질문**: 프로세서 내 PE 들에 다 담을 수 없을 만큼 거대한 프로그램을
WaveScalar 와 그 파생 아키텍처들은 어떻게 처리하는가.

**조사 시점**: 2026-08. 네 각도(WaveScalar 원전 / wave-ordered memory /
EDGE·TRIPS 계열 / CGRA·시공간 다중화 계열)의 병렬 문헌 조사를 종합했다.

---

## 1. 조사 질문과 배경

WaveTensor 의 기원 질문은 "WaveScalar ISA 를 CPU 가 아니라 가속기에
활용할 수 있도록 개량하면 어떨까"였다. WT64v1 은 그 개량의 현행 형태이고,
다음 사실들이 이번 조사의 좌표계다 (정본 문면 확인, 2026-08 기준).

- **태그 80b 에 wave 32b 필드가 있다** (정본 §1.4.4 태그 레이아웃 표:
  wave 번호 32b · 스레드 ID 16b · LNID 16b · 정밀도 8b · 차원 8b).
  단 RTL 실측으로 **wave 번호는 어떤 비교·조건·게이팅에도 쓰이지 않는다** —
  입력 태그에서 읽혀 출력 태그로 복사될 뿐이다 (정본 §4 WOM 절 「현황 —
  정직한 기재」).
- **Wave-Ordered Memory 는 현행에 없다.** 정본 §4 에 「사용자가 명시적으로
  지목한 개념 — 현행에 없다」로 개념 소개만 서 있고, 메모리 순서는 §4.4.4
  에서 **명시적 순서 의존(메모리 연산 간 토큰 전달)** 으로 확정됐다.
  wave 번호는 순서 기전이 아니라고 같은 절이 못박는다.
- **능력 부재(capability 부재) 분류** — 바이너리는 옳은데 이 유닛이 직접
  못 하는 경우, 오류가 아니며 *상위 계층(호스트)이 분해하거나 대체한다*
  (정본 §1.6.2). 즉 용량 초과에 대한 WT64v1 의 현행 답은 **호스트 측 정적
  분해**다.
- **상호연결에 라우터·중재기·패킷·flit 이 없다** — 브로드캐스트 + valid
  디먹스 + OR 병합 셋뿐이다 (정본 §2.3, 실측 등급). NoC 를 전제한 기법의
  직수입은 정본이 명시적으로 금지한 함정이다 ("분리할 경합이 없는 곳에
  라우터를 짓게 된다").
- **형상 독립 ISA (INV-T1/T2)** — 명령·태그 인코딩에 하드웨어 인스턴스
  개수가 새지 않는다. 다중 조각 wave 의 재조립 문맥은 개시 wave 디코드
  시점에 열리고 태그→목적 LBID 결속이 종료까지 불변이다 (정본 §1.4.7
  ACCTGT · §4.3).

이 좌표계에서 원전과 파생들의 답을 읽는다.

---

## 2. WaveScalar 의 답 — 패브릭 자체가 명령어 캐시다 (WaveCache)

WaveScalar 의 답은 이름 그대로다. ISA 는 "바이너리의 모든 정적 명령이
각자 전용 PE 를 갖는" 무한 가상 기계를 정의하고, 물리 PE 격자는 그
가상 공간의 **캐시**다 — 그래서 WaveCache 다 (Swanson et al., *WaveScalar*,
MICRO-36 2003, §1; Swanson PhD thesis 2006, §1: "PE 들이 애플리케이션
워킹셋을 캐시한다"). 용량 초과 처리는 세 겹의 캐시화로 구성된다:
**명령**(패브릭 = I-cache), **토큰**(매칭 테이블 = 인메모리 테이블의 캐시),
**병렬성**(k-loop bounding).

### 2.1 명령 적재 — 수요 기반 미스 구동

실행 개시는 OS 측이 프로그램 첫 명령의 '주소'로 메시지를 보내는 것이다.
그 명령이 패브릭에 없으면 미스가 나고 WaveCache 가 메모리에서 명령을 PE 로
적재한다. 적재 시 출력 타깃 필드를 메모리 주소에서 WaveCache 내 위치로
재작성하고, 미적재 목적지는 'not-loaded' 센티널로 둔다. not-loaded 로
메시지가 가면 미스가 연쇄해 필요한 부분 그래프가 끌려 들어온다. 워킹셋이
안정되면 명령은 제자리에서 수백만 번 실행된다 (MICRO-36 §5.3 "Loading,
finding, and replacing instructions").

비용: 미스는 heavyweight 이벤트다 — 명령 비트만이 아니라 입력 큐 등 명령의
'상태' 전체를 온칩으로 가져와야 하고, 타깃 재작성 하드웨어가 필요하다.
MICRO-36 §6.6 의 실험 가정은 메모리에서 명령 상태 읽기 32사이클 + 캐시
횡단 전송 1–24사이클이다.

### 2.2 축출·교체

빈 자리가 없으면 기존 명령을 제거한다 — 상태 전부를 메모리로 스왑아웃하고,
그 명령에게 값을 보내는 생산자들의 목적지 필드를 'not-loaded' 로 되돌리는
분산 무효화다. 절감책으로 큐가 비고 한동안 실행되지 않은 명령은 스스로
'idle' 마킹 — idle 명령은 되쓸 상태가 없어 값싸게 교체된다 (MICRO-36 §5.3).
MICRO-36 실험 구성은 클러스터 단위 LRU 였다 (§6.6). 주목할 실측: mcf ·
equake · fft · mpeg 는 워킹셋 초과 크기의 패브릭에서 오히려 성능이
하락했다 — **"명령을 큰 패브릭에 펼치는 것보다 교체 정책이 워킹셋을 좁은
공간에 모으는 편이 낫다"** (MICRO-36 §6.6, Fig.7).

### 2.3 PE 가상화 (시분할) — 용량의 실체

PE 하나가 정적 명령 여러 개를 담아 시분할 실행한다. MICRO-36 설계는 PE 당
8명령 × ~2K PE = 16K 명령 (64KB RISC I-cache 상당, §4). 학위논문 RTL
기준선은 PE 당 128명령(가상화 도수 V), 2-PE pod → 8-PE domain → 4-domain
cluster 계층, 클러스터당 4K 정적 명령이다 (thesis Table 7.2). 파레토
탐색에서 **V 가 성능 최중요 파라미터**로 판명됐다 — 64→128명령/PE 확대가
면적 +12%로 성능 +43% (thesis §7.2). 대가는 SRAM 지배 — 클러스터 면적의
71%가 PE 이고 전체의 ~83%가 SRAM 이며, 256엔트리에서 사이클 타임이 명령
저장소 +7% · 매칭 캐시 +21% 든다 (thesis §7.1).

### 2.4 배치 — 컴파일러 선형화 + 런타임 세그먼트 적재

컴파일 시 각 함수의 데이터플로 그래프를 pre-order DFS 로 선형화해 의존
사슬이 연속되게 하고 짧은 세그먼트로 자른다(길이는 앱별 튜닝). 런타임에
미적재 명령이 필요해지면 그 세그먼트 전체를 PE 하나에 통째로 적재한다 —
세그먼트 내 명령들은 서로 의존적이라 자원을 다투지 않는다. 채움 순서는
도메인→클러스터→격자 뱀 순회다 (thesis §4.6; Mercaldi et al., ASPLOS 2006
의 계층 스케줄링). 배치 품질의 지렛대는 크다: 알고리즘 간 성능 차 10배
이상, 나쁜 배치는 최대 5배 저하 (Mercaldi et al., ASPLOS 2006; SPAA 2006).
배치 알고리즘 덕에 메시지 트래픽의 30–40%가 단일 pod 안에서 해결된다
(thesis §9.3).

### 2.5 토큰 저장 — 매칭 테이블의 캐시화 + k-loop bounding

동적 데이터플로라서 정적 명령 하나의 대기 토큰 수에 상한이 없다. 해법은
고전 데이터플로 기법 — 매칭 테이블을 더 큰 **인메모리 매칭 테이블의
캐시**로 구현한다. 입력 큐 오버플로 값은 전용 가상 주소 공간(주소 =
명령주소‖큐번호‖wave 번호)에 저장하고, 자리가 나면 프리페치한다 (thesis
§4.2; MICRO-36 §6.7). '병렬성 폭발'(루프 인덱스 계산이 앞질러 달려 토큰을
대량 생성, 매칭 테이블을 스필시키는 문제)에는 **k-loop bounding** — 동시
실행 가능한 루프 반복 수를 앱별 튜닝 값 k 로 제한한다 (thesis §4.7, Culler
1990 MIT PhD [15] 경유 채용; MICRO-36 시점에는 없었고 adpcm 이 32엔트리
큐에서 -20% 를 보이며 문제만 관찰됨, §6.7).

### 2.6 wave 번호의 자리 — 용량 문제의 원인이자 전제

wave 번호는 **명령 용량과 무관하다.** Wave-Advance 가 wave(비순환 그래프
조각) 진입 시 번호를 올려 같은 정적 명령의 서로 다른 동적 인스턴스(반복)
토큰들이 공존·동시 실행하게 하는 태그다 (thesis §2.2.3; MICRO-36 §3).
wave 번호가 만드는 것은 **토큰 저장 압력**이고, 그것을 §2.5 의 두 기전이
받아낸다. wave 번호의 비트 폭은 원전 본문에서 확인하지 못했다 (§7 참조).

---

## 3. 파생들의 답 — 창 순환과 시분할의 스펙트럼

### 3.1 EDGE/TRIPS — 패브릭에는 프로그램이 아니라 '창'만 산다

TRIPS 는 문제를 애초에 '패브릭에 프로그램을 담는' 문제로 만들지 않는다.
프로그램 전체는 I-캐시/메모리에 있고, 실행 배열에는 항상 최대 8개 블록
(비추측 1 + 추측 7 = 1,024명령 윈도)만 상주한다. 실행 타일당 예약 스테이션
64개 = 8명령 × 8블록이 블록 프레임의 실체다 (Sankaralingam et al.,
MICRO-39 2006, §3, §3.4). 블록 교체는 "다음-블록 예측기(8사이클당 1회,
3사이클) → 13사이클 페치 파이프라인으로 빈 슬롯 사상 → 최오래 블록 커밋
ACK 시 슬롯 해제"의 **하드웨어 자동 순환**이고, 그 이상의 상주 관리 기전
(소프트웨어 오버레이, 블록 우선순위)은 **존재하지 않는다** — 조사에서
그런 문헌을 발견하지 못한 것이 아니라, 설계 자체가 그것을 두지 않았다
(MICRO-39 2006 §4.1, §4.4; Burger et al., IEEE Computer 2004, p.48).

이 순환을 값싸게 만드는 것이 **블록 원자성**이다. 모든 술어 경로에서 출력
개수가 동일하다는 ISA 제약(≤32 레지스터 쓰기, ≤32 store, 정확히 1 분기;
부족분은 null write/store 로 패딩) 덕에 분산 기판에서 도착 출력 수만 세면
완료를 검출하고, 페치·커밋·오예측 복구·자원 해제가 전부 '블록 통째'라
명령별 ROB·리네임 부기가 사라진다 (MICRO-39 2006 §2.1, §4.3–4.4).
분업 경계는 SPDI — **where 는 컴파일러(좌표까지 정적 배치), when 은
하드웨어(데이터플로 발화)** (IEEE Computer 2004, pp.45, 49–51).

실리콘 회고(Gebhart et al., ASPLOS 2009)의 실측: 컴파일러가 블록을 못
채웠고(평균 70/128), move 명령이 전체의 ~20%, 동적 코드 크기 Alpha 의
11배, 컴파일 SPEC2000 은 Core 2 의 60%. 실효 IPC 는 블록크기/8 로 상한
(8사이클당 1블록 페치 한계, §5.3). 후속 **TFlex** (Kim et al., MICRO-40
2007)는 블록 주소 해시로 소유자 코어를 정하는 완전 분산 프로토콜로 같은
바이너리를 2-wide 코어 1~32개에 재컴파일 없이 신축 사상했다 — 9-bit
target 필드의 비트 해석(하위=코어 선택, 상위=슬롯 선택)만 바꾼다. 윈도
용량·페치 대역폭·LSQ 가 코어 수에 선형 비례한다.

### 3.2 CGRA·시공간 다중화 계열 — 네 부류의 답

'구성 > 패브릭' 문제에 대한 이 계보의 답은 네 부류로 정리된다.

1. **호스트/컴파일러 정적 분할 (주류)** — SGMF 는 큰 CUDA 커널을 서브커널로
   쪼개 전 스레드 드레인 → 중간값 메모리 스필 → 재구성 → 재실행한다
   (Voitsechov & Etsion, ISCA 2014, §4.6; 논문 시점 분할은 수동). RipTide
   는 6×6 패브릭에 안 들어가는 fft 를 컴파일러가 두 함수로 분할한다
   (Gobieski et al., MICRO 2022, §VII-A). Plasticine 은 물리 자원(64 PCU +
   64 PMU) 안에 실현 불가하면 **컴파일 실패**로 선언하고 초과 처리를 상위
   런타임에 넘겼다 (Prabhakar et al., ISCA 2017, §5; 상용 후속 SambaNova
   의 런타임 가상화 특허 US 11,809,908 은 제목만 확인 — §7).
2. **구성 페이징 (하드웨어 자체가 페이징)** — PipeRench 가 유일하다. 단일
   구성을 파이프라인 스테이지 단위 조각(virtual stripe)으로 쪼개 실행과
   동시에 매 사이클 한 스트라이프씩 로드한다 — "전체 구성이 패브릭에 한
   번에 존재하지 않는다". v-스테이지 앱을 p 물리 스트라이프에 돌리면
   처리량 ∝ (p−1)/v. 대가는 강한 구조 제약 — 순방향 전용, 순환 의존은 한
   스테이지 내부로 한정 (Goldstein et al., ISCA 1999, §3–4).
3. **PE 당 다중 컨텍스트 시분할** — DPGA 가 원형이다. 어레이 요소마다
   4-컨텍스트 명령 저장소를 두고, **전역 브로드캐스트되는 컨텍스트
   식별자(CID)** 를 주소로 로컬 저장소를 조회한다 — "CID 를 바꾸면 어레이
   전체가 즉시 재구성". 명령 저장소는 '컨텍스트 캐시'이고 초과분은 외부
   메모리에서 컨트롤러가 순차 교체한다 (Bolotski, DeHon, Knight, FPGA
   1994). **라우터가 전혀 없는 브로드캐스트 상호연결에서 이뤄진 용량
   가상화**라는 점에서 WT64v1 §2.3 제약과 가장 동형인 선례다. 대가는 PE 당
   구성 메모리 면적 × 컨텍스트 수. 다중 컨텍스트는 CGRA 분야의 표준 답이기도
   하다 (Podobas et al., IEEE Access 2020).
4. **용량 상한 + 호스트 폴백** — SEED 는 오프로드 수용량을 ISA 계약으로
   상한한다: fully-inlined 중첩 루프, 최대 1024 비복합 명령(~20KB 저장소).
   넘치는 코드는 그냥 OOO 코어가 실행한다. 정적 명령 수 제한이 태그 폭을
   제한하고 태그 매칭 CAM 을 제거한다 (Nowatzki et al., ISCA 2015, §3).
   1024-명령 지역 기준 중첩 루프 커버리지는 동적 명령의 88%다 (§7 Q1).

규모의 기준점: Tartan 은 전 프로그램 공간 매핑의 면적을 정량화하고
"가까운 미래에 대부분의 큰 프로그램은 가상화 없이 재구성 패브릭에 완전히
구현될 수 없다"고 결론지었다 — mesa 는 정적 25,000 페이지가 필요한데
400mm²@90nm 다이는 ~800 페이지이고, 동적 워킹셋은 ~2,700 페이지다
(Mishra et al., ASPLOS 2006, §5.6). **정적 요구가 동적 워킹셋의 ~10배** —
워킹셋 캐시화(WaveScalar)든 창 순환(TRIPS)이든, 어떤 형태로든 가상화가
불가피하다는 것이 이 계보의 합의다.

### 3.3 보편 규율 하나 — 아무도 in-flight 토큰을 살려둔 채 갈아끼우지 않는다

태그 매칭 데이터플로와 구성 교체의 상호작용에 대해 조사된 전 사례가 같은
규율을 따랐다: **패브릭을 비우고 교체한다.** (a) 전면 드레인 + 메모리 스필
(SGMF), (b) 정지(quiesce) 후 라이브 상태의 아키텍처화 — 최악 ~2KB (SEED),
(c) 레지스터 상태 저장/복원 전용 버스 (PipeRench), (d) 태그 제거로 문제
자체를 소거 (SEED, RipTide). in-flight 태그 토큰을 패브릭에 둔 채 구성을
교체하는 기전은 어떤 문헌에서도 발견하지 못했다. 유일한 예외적 구도는
WaveScalar 자신인데, 거기서도 명령 단위 축출은 "큐가 비고 idle 인" 명령을
우선하며(§2.2), 상태가 있는 명령의 축출은 상태 전체의 스왑아웃이다 —
토큰을 패브릭에 남기는 것이 아니라 토큰까지 함께 옮긴다.

---

## 4. 메모리 순서와 용량의 상호작용 — wave-ordered vs 명시적 토큰

### 4.1 원전의 wave-ordered memory (WOM)

WOM 은 두 층이다. **wave 내**: 컴파일러가 CFG 너비우선 순회로 각 메모리
명령에 `<pred, seq, succ>` 링크를 주석하고(유일 결정 불가 지점은 와일드카드
'?', 어떤 경로에도 '?–?' 쌍이 없도록 MEMORY-NOP 삽입 — 정적 명령의 3%
미만), 메모리 시스템이 도착 순서와 무관하게 갭 부재를 판정하며 체인을
재조립한다 (MICRO-36 §3.2; thesis §3.2.2–3.2.3, 발행 규칙 W1–W3 과
wavefront F). **wave 간**: WAVE-ADVANCE 가 올리는 wave 번호가 상위 자릿수가
되어 (wave#, seq#) 쌍이 프로그램 전체 메모리 연산의 전순서를 이룬다
(thesis §3.2 p.19).

하드웨어 실체는 클러스터당 store buffer(ORDERING/NEXT 테이블, ISSUED
레지스터, partial store queue)다. 동적 wave 하나당 store buffer 하나가
배정되고, 바인딩은 **메인 메모리 상의 wave번호→store buffer 맵 + 캐시
일관성**으로, wave 완료 시 다음 wave 담당자에게 '선행 완료' 메시지를
핸드오프한다 (thesis §4.4–4.4.1). 동시 ordered 순서열 수는 물리 store
buffer 수가 상한이다 (thesis Ch.8 p.95).

### 4.2 용량(축출)과 순서의 분리

핵심 관찰: 순서 상태는 PE 에 있지 않다 — (a) 요청에 실려 다니는 주석과
(b) 동적 wave 단위의 store buffer 에 있다. 따라서 명령이 어디 배치되든,
축출·재적재되든 순서 보장은 구조적으로 불변이다. 논문의 간접 근거:
"단일 클러스터 + L2 + 메인 메모리로 어떤 WaveScalar 프로그램도 실행
가능하되, 명령이 소수 PE 를 드나들며 스왑되므로 성능만 나쁠 수 있다"
(thesis §4.1 p.39). **이것이 'PE 용량보다 큰 프로그램'에 대한 이 계열의
1차 답이다.** 단, "축출이 순서를 깨지 않는다"는 명시 문장은 두 원전 어디에도
없다 — 설계 구조로부터의 귀결이다 (§7).

### 4.3 명시적 토큰과의 비교 — WT64v1 확정과의 관계

원전 자신의 정량 비교: 순차 C 바이너리 자동 변환(별칭 분석 없음) 조건에서
WOM 은 token-passing 대비 메모리 병렬성 2배, 전체 IPC +46% (thesis §3.4.3).
원인은 토큰이 제어 흐름을 따라 STEER 명령으로 유도돼야 해(연속 메모리 연산
쌍 사이 평균 2.5개) 지연이 끼는 것이다. 그러나 저자들 스스로 **별칭 정보가
좋으면 token-passing 이 유리**하다고 인정하고, unordered 인터페이스
(LOAD-UNORDERED / STORE-UNORDERED-ACK + MEMORY-NOP-ACK 펜스)를 제2
인터페이스로 제공했다 — 스토어가 완료 시 ack 값을 내 후속 연산의 트리거로
삼는 방식으로, **WT64v1 §4.4.4 의 명시적 순서 의존과 동일한 발상**이다
(thesis §5.2.1, §8.1–8.2.1). 처방도 명시돼 있다: "분석 어려운 포인터 추적
코드는 wave-ordered 로" — 즉 WOM 의 우위 조건은 정적으로 의존을 알 수 없는
코드이며, 컴파일러/호스트가 의존을 정적으로 아는 가속기 워크로드라는
WT64v1 의 전제에서는 그 우위 조건이 성립하지 않는다.

정본의 확정과 원전의 병존 구도는 정합적이다. 정본 §4.4.4 는 순번 재정렬
버퍼 안을 가변 지연(상수 시간 계약 충돌)과 순번 고갈을 이유로 기각하고
명시적 순서 의존을 택했으며, 영역 분할을 "토큰을 걸지 않는 결정"이라는
기전 위 최적화로 흡수했다. 원전의 unordered 경로가 정확히 같은 노선이고,
WOM 하드웨어(클러스터 계층 · store buffer 라우팅 · 일관성 맵)는 정본이
금지한 'NoC 전제 기법 직수입' 범주에 해당한다.

한 가지 원전측 교훈은 이식 가능하다: 정본 §4.4.4 해설의 선-formal 실측
(MemOrder.tla — wave 게이트가 토큰 순서와 어긋나면 교착)과 원전의
"wavefront 는 비메모리 명령을 통과하지 않는다"(thesis §3.4.3)는 같은
문제의식이다 — 순서 기전이 계약을 넘어 게이트하면 대가는 병렬성 손실이
아니라 진행성 상실이다.

---

## 5. WT64v1 제약으로의 사상

### 5.1 현행 답의 좌표 — 스펙트럼의 어디인가

§3.2 의 네 부류에 대면 WT64v1 의 현행 답(능력 부재 → 호스트 분해,
정본 §1.6.2)은 **부류 1(호스트/컴파일러 정적 분할)** 이고, 오프로드
수용량이 계약으로 상한되고 초과분이 상위 계층으로 간다는 점에서는
**부류 4(SEED 형 용량 상한 + 폴백)** 의 구도이기도 하다. 이것은 주변부가
아니라 주류 노선이다 — SGMF(2014) · Plasticine(2017) · RipTide(2022)가
전부 같은 자리에 서 있다. 조각열의 선언 총개수가 구현 슬롯 상한을 넘으면
malformation 이 아니라 능력 부재라는 정본 §4.3 의 처분도 같은 노선의
문면이다.

다른 점 하나는 명확하다: SGMF 계열의 분할은 논문 시점 수동이고 자동화
서술을 후속에서도 찾지 못했다(§7). Plasticine 은 컴파일 실패 선언 후
상위 런타임으로 넘겼고 그 런타임의 기전은 특허 제목만 확인됐다. 즉
**호스트 분해 노선의 '분해기' 자체는 조사된 문헌에서 미해결 숙제로 남아
있다** — WT64v1 이 이 노선을 유지한다면 분해기의 규약(무엇을 경계로
자르는가, 중간값은 어디로 가는가)이 문헌이 답을 주지 않는 자리다.

### 5.2 NoC 없는 브로드캐스트 패브릭(§2.3)에서 성립하는 것과 안 되는 것

**직수입 불가 (라우팅 망 전제)**:

- WaveCache 의 미스 연쇄·not-loaded 센티널·생산자 목적지 재작성 — 명령
  단위 점대점 메시지와 계층 인터커넥트(pod 1 / domain 5 / cluster 9 /
  cluster 간 9+거리 사이클)를 전제한다 (thesis Table 7.2).
- WOM store buffer 라우팅·메인 메모리 일관성 맵·wave 완료 핸드오프
  (thesis §4.4.1).
- TRIPS 의 GDN/GCN/GSN/GRN 마이크로넷 4종과 GT 중앙 제어, OPN 오퍼랜드
  망 (MICRO-39 2006 §3–4) — TFlex 의 해시 분산도 1-hop 1사이클 2D 메시를
  전제한다 (MICRO-40 2007 §4).
- RipTide 의 부분 중첩 재구성 — 버퍼리스 2D-토러스 NoC 에 제어 흐름을
  싣는 설계가 전제다 (MICRO 2022 §VI).

**브로드캐스트 구조에서 성립하는 선례·아이디어 (토폴로지 중립 또는 동형)**:

- **DPGA 의 로컬 명령 저장소 + 전역 브로드캐스트 CID** (FPGA 1994) —
  라우터 0 인 브로드캐스트 상호연결에서의 용량 가상화 선례로, WT64v1 §2.3
  (브로드캐스트 + valid 디먹스 + OR 병합)과 구조적으로 가장 가깝다.
  "전역 브로드캐스트 하나가 어레이 전체의 국소 선택을 바꾼다"는 형태는
  WT64v1 의 명령 번들 브로드캐스트·valid 디먹스와 같은 결이다.
- **TRIPS 의 '고정 출력 개수로 완료 검출'** — 카운팅만으로 분산 기판에서
  블록 완료를 아는 기법은 라우팅과 무관한 ISA 계약이다 (MICRO-39 2006
  §2.1). WT64v1 이 이미 가진 조각열 규범(선언 총개수 + 마지막 조각 표시
  + 수신 순번 집합 검사, 정본 §4.3)과 같은 부류의 발상이다.
- **'창 순환과 프로그램 상주의 분리'** (TRIPS) · **'블록(구성) = 축출
  단위'** — 개념 자체는 토폴로지 중립이다.
- **'워킹셋이 작을수록 좁게 모으는 편이 낫다'** (MICRO-36 §6.6) 와
  **컴파일 시 DFS 선형화·세그먼트 분할** (thesis §4.6 의 정적 절반) —
  호스트 측 정적 분해에도 이식 가능한 관찰이다.
- **드레인-후-교체 규율** (§3.3) — 상호연결과 무관한 보편 규율이며,
  WT64v1 이 어떤 형태의 재구성을 택하든 전제로 삼을 수 있는 유일하게
  문헌 합의가 있는 규율이다.

### 5.3 형상 독립 ISA(INV-T1/T2)·재조립 문맥·소유와의 충돌 지점

- **TFlex 형 비트 해시는 INV-T1/T2 정면 위반이다.** target 필드의 하위
  비트 = 코어 선택, 상위 비트 = 슬롯 선택이라는 해석은 "상수 비트
  슬라이스가 인스턴스 선택자로 쓰이는" 바로 그 형태다 (정본 §1.2 INV-T2
  정적 검사 문구). TFlex 의 목적(재컴파일 없는 신축 사상)은 WT64v1 에서
  논리 ID + MMIO 사상표(정본 §1.5)가 이미 담당한다 — 수단이 다르다.
- **SEED 형 '정적 명령 수 상한의 ISA 계약화'는 긴장 관계다.** SEED 는
  1024 명령이라는 수치를 ISA 에 박아 태그 폭·CAM 을 줄였다 (ISCA 2015 §3).
  WT64v1 에서 구현 상한은 능력 부재 판정의 기준이지 인코딩의 함수가 아니다
  (정본 §1.6.2 — 길이 필드 '선언'이 구현 상한을 넘으면 능력 부재). 상한을
  인코딩 폭으로 승격하는 순간 INV-T1 위반이다.
- **재조립 문맥은 구성 교체의 추가 제약이다.** 다중 조각 wave 의 태그→
  목적 LBID 결속은 개시 wave 디코드 시점에 열려 조각열 종료까지 불변이고,
  미완 조각열 위 같은 태그의 새 조각열은 loud fault 다 (정본 §4.3). 즉
  §3.3 의 드레인 규율을 WT64v1 로 옮기면 드레인 대상은 in-flight 토큰만이
  아니라 **열린 재조립 문맥**을 포함한다 — 문맥이 열린 채 구성(사상표 포함)
  이 바뀌면 결속 불변 규범과 충돌한다. 문헌에는 이 층위(재조립 상태와
  재구성의 상호작용)에 대응하는 선례가 없다 — WT64v1 고유의 결정 지점이다.
- **LNID 소유의 서로소성과 사상표의 거처** (정본 §1.5 — MMIO 구성
  레지스터) 는 DPGA 형 컨텍스트 전환과는 오히려 정합적이다: 사상표가
  머신 구성이므로 "구성 전환 = 사상표 전환" 이라는 확장은 인코딩을 건드리지
  않는다. 단 이것은 가용성 관찰이지 설계 결정이 아니다.

### 5.4 wave 32b 필드가 이미 주는 것과 안 주는 것

**주는 것**: 원전 계보에서 wave 번호가 하는 일 중 WT64v1 에 이미 있는 것은
"동적 인스턴스의 식별자" 자리뿐이다 — 필드 폭 32b 는 원전 확인이 불가능한
수치이나(§7), 식별 공간으로서는 충분히 크다. 정본 §4.4.4 해설이 적었듯
스레드 ID 16b 와 함께 "순번을 실을 자리를 새로 만들 필요가 없을 가능성"
이라는 가용성도 준다.

**안 주는 것**: 원전에서 wave 번호가 실제로 일하는 자리 전부다 —
(a) wave 간 메모리 전순서의 상위 자릿수 (thesis §3.2), (b) 매칭 테이블
스필 주소의 구성 성분 (MICRO-36 §6.7), (c) k-loop bounding 의 반복 구별
전제 (thesis §4.7), (d) store buffer 바인딩 키 (thesis §4.4.1). WT64v1
에서 wave 번호는 아무것도 게이트하지 않으며(정본 §4 실측), §4.4.4 가
"wave 번호는 순서 기전이 아니다"라고 못박았으므로 (a)·(d) 는 확정적으로
닫혔다. (b)·(c) 는 토큰 저장 가상화·병렬성 제한이라는 **아직 WT64v1 이
답하지 않은 문제**의 자리다 — wave 필드가 그 답의 재료가 될 수 있다는
것과 그 답이 필요하다는 것은 별개 명제이고, 현행 워크로드 구도(호스트
정적 분해, 태그 매칭 압력의 상한이 구성으로 정해짐)에서 그 문제가
발생하는지 자체가 미확정이다.

---

## 6. 열리는 설계 질문들 (B.5 후보 형태)

조사 결과가 결정을 내려주지 않되, 결정이 필요해질 자리를 후보로 남긴다.
전부 "정본이 답을 갖고 있지 않고, 문헌이 대가 구조를 보여준 자리"다.

1. **호스트 분해기의 규약** — 현행 답(§1.6.2)의 실체는 호스트 측 분해인데,
   분해의 경계 규약(무엇 단위로 자르는가 — SGMF 의 커널 경계 / RipTide 의
   함수 경계 / WaveScalar 컴파일러의 DFS 세그먼트)과 중간값의 거처(SGMF:
   전량 메모리 왕복)가 미규정이다. 문헌 합의는 "드레인 후 교체"까지이고
   분해 자동화는 전 계보에서 미해결이다.
2. **드레인의 정의역** — 구성 교체 전 비워야 할 것의 목록. 문헌의 목록은
   in-flight 토큰·라이브 레지스터 상태였으나, WT64v1 은 **열린 재조립
   문맥**(태그→LBID 결속, 수신 순번 집합)이 추가된다 (§5.3). "문맥이 열린
   채 사상표가 바뀌면 무엇이 서는가"는 문헌에 선례가 없는 WT64v1 고유
   질문이다.
3. **DPGA 형 다중 컨텍스트의 채택 여부** — 브로드캐스트 상호연결과 동형인
   유일한 용량 가상화 선례다. 대가는 PE 당 구성 저장 면적 × 컨텍스트 수
   (WaveScalar 실측이 경고하는 SRAM 지배 — 전체의 ~83%, thesis §7.1)와
   컨텍스트 간 상태 규율의 컴파일러 이관. 채택한다면 "컨텍스트 전환 =
   사상표 전환" 인가, 사상표는 MMIO 구성이므로 호스트 주도인가가 뒤따른다.
4. **가상화 도수의 자리** — WaveScalar 의 최중요 파라미터(V = PE 당 명령
   수)에 대응하는 WT64v1 의 양은 무엇인가. 형상 독립 ISA 아래에서 V 는
   인코딩에 나타나면 안 되므로(INV-T1), 순수 구성 파라미터로만 존재할 수
   있다 — 그렇다면 능력 부재 판정 기준(구현 상한)과 어떻게 연동되는가.
5. **토큰 저장 압력의 상한 근거** — 원전은 매칭 테이블 스필 + k-loop
   bounding 으로 무한 동적 인스턴스를 받아냈다. WT64v1 의 현행 구도에서
   같은 압력(병렬성 폭발)이 구조적으로 발생 가능한지, 불가능하다면 그
   불가능성이 어느 규범에서 나오는지(재조립 문맥 유일성? 조각열 규범?
   호스트 분해의 입도?)를 명시할 자리. 발생 가능하다면 k-bound 에 대응하는
   제한 기전의 자리가 필요하다.
6. **'창 순환' 개념의 이식 가능성** — TRIPS 의 "패브릭에는 창만 산다"를
   라우팅 망 없이 번역하면 "브로드캐스트 단위 = 창, 순환은 호스트 주도"가
   된다. 이것이 현행 명령 번들 브로드캐스트 dispatch 와 실질적으로 같은
   것인지(이미 있음), 아니면 상주 구성의 세대 교체라는 새 층인지의 판별.
7. **wave 32b 필드의 장래 의미 부여** — §5.4 의 (b)·(c) 자리. 정본 §4.4.4
   가 순서 기전으로의 사용을 닫았으므로, 남는 후보는 동적 인스턴스 식별
   (재조립·스필 키)이다. "보존만 되는 필드는 은닉 채널" 이라는 정본 §5
   계열 경고(예약 필드는 덫)와의 정합 검토가 선행돼야 한다.

---

## 7. 조사가 확보하지 못한 것 (gaps)

각 각도가 정직하게 남긴 공백을 통합한다. 아래 항목에 대한 본문 서술은
없거나, 있다면 간접 근거임을 명시했다.

**원문 미확보**:
- ACM TOCS 25(2) 2007 판 "The WaveScalar Architecture" 본문 — 페이월.
  상세 주장은 전부 MICRO-36 원문과 Swanson 학위논문에서 직접 검증했고
  TOCS 는 초록·서지로만 확인.
- Culler 1990 (k-loop bounding 원출처) — Swanson 학위논문 [15] 경유 인용.
- CACM 회고 "The TRIPS Project" — 접근 차단(403). ASPLOS 2009 §7–8 로 충당.
- SambaNova 특허 US 11,809,908 의 실제 기전 — 제목·존재만 확인.
- Coons et al. ASPLOS 2006 (TRIPS 스케줄러 상세), ASPLOS 2009 확장
  기술보고서 TR-08-31 — 미열람.
- thesis 가 token-passing 으로 인용한 [12,13] 의 서지 미확정.

**찾지 못한 수치·명문**:
- wave 번호의 비트 폭 — MICRO-36·학위논문 추출 텍스트에 수치 없음.
  WT64v1 의 32b 에 대응하는 원전 수치는 미확인.
- wave 당 sequence number 비트 폭 — thesis §3.2.3 은 "제한이 있다"고만 언급.
- "명령 축출·재적재가 메모리 순서 보장과 충돌하지 않는다"는 명시 문장 —
  두 원전 어디에도 없다. thesis §4.1 p.39 와 설계 구조로부터의 귀결로만
  답했다 (§4.2).
- 학위논문 세대의 축출 '정책' 명세(LRU 여부·트리거) — 클러스터별 LRU 는
  MICRO-36 실험 구성에서만 명시.
- 명령 미스율·축출 빈도의 벤치마크별 실측 표 — MICRO-36 Fig.7 은 곡선
  서술뿐.

**존재하지 않음이 확인된 것 (부재의 확인)**:
- in-flight 태그 토큰을 패브릭에 둔 채 구성을 교체하는 기전 — 전 조사
  범위에서 발견 못 함. 전 사례가 드레인·정지·상태 스왑·태그 제거였다.
- TRIPS 의 8-슬롯 윈도를 넘는 블록 상주 관리 기전 — 설계에 없다.
- Tartan 의 가상화 '구현' — 없다. 불가피성 결론의 한계 연구로 종결.
- SGMF/dMT-CGRA 계보의 자동 커널 분할 툴체인 — SGMF 시점 수동, 후속에서도
  자동화 서술 미발견.

**미조사 영역**:
- WT64v1 §2.3 과 완전 동형(브로드캐스트 + valid 디먹스 + OR 병합)인
  상호연결에서의 용량 가상화 선례 — 정확 일치는 없음. 최근접이 DPGA.
- 용량 초과 시 세그먼트 적재와 축출이 상호작용하는 동적 시나리오의 배치
  연구 — Mercaldi 계열은 전부 워킹셋이 패브릭에 다 들어가는 조건.
- wave-ordered memory 에 대한 제3자 후속 비판 문헌(TRIPS/ASH 진영의 직접
  반론), ripple 과 실제 별칭 분석의 결합 정량, Microsoft E2, NEC DRP 의
  1차 문헌.

---

## 8. 서지

### WaveScalar 원전

1. Steven Swanson, Ken Michelson, Andrew Schwerin, Mark Oskin.
   *WaveScalar.* MICRO-36, 2003.
   <https://homes.cs.washington.edu/~oskin/wavescalar.pdf>
2. Steven Swanson. *The WaveScalar Architecture.* PhD dissertation,
   University of Washington, 2006.
   <https://cseweb.ucsd.edu/~swanson/papers/SwansonPhDThesis.pdf>
3. Steven Swanson, Andrew Schwerin, Martha Mercaldi, Andrew Petersen,
   Andrew Putnam, Ken Michelson, Mark Oskin, Susan J. Eggers.
   *The WaveScalar Architecture.* ACM TOCS 25(2), 2007. (원문 미확보 —
   초록·서지만 확인)
   <https://dl.acm.org/doi/10.1145/1233307.1233308>
4. Martha Mercaldi, Steven Swanson, Andrew Petersen, Andrew Putnam,
   Andrew Schwerin, Mark Oskin, Susan J. Eggers. *Instruction Scheduling
   for a Tiled Dataflow Architecture.* ASPLOS-XII, 2006.
   <https://cseweb.ucsd.edu/~swanson/papers/ASPLOS2006WaveScalar.pdf>
5. Martha Mercaldi et al. *Modeling Instruction Placement on a Spatial
   Architecture.* SPAA '06, 2006.
   <https://arcade.cs.columbia.edu/ws-spaa06.pdf>
6. David E. Culler. *Managing Parallelism and Resources in Scientific
   Dataflow Programs.* MIT PhD thesis, 1990. (직접 미열람 — [2]의 [15]
   경유 인용)
   <https://dspace.mit.edu/handle/1721.1/14425>

### EDGE / TRIPS 계열

7. Doug Burger, Stephen W. Keckler, Kathryn S. McKinley, et al.
   *Scaling to the End of Silicon with EDGE Architectures.* IEEE Computer
   37(7), 2004.
   <https://www.cs.utexas.edu/~mckinley/papers/trips-computer-2004.pdf>
8. Karthikeyan Sankaralingam, Ramadass Nagarajan, et al. *Distributed
   Microarchitectural Protocols in the TRIPS Prototype Processor.*
   MICRO-39, 2006.
   <http://www.cs.columbia.edu/~simha/cal/pubs/pdfs/trips_microarchitecture.pdf>
9. Mark Gebhart, Bertrand A. Maher, Katherine E. Coons, et al.
   *An Evaluation of the TRIPS Computer System.* ASPLOS XIV, 2009.
   <https://www.cs.utexas.edu/~mckinley/papers/trips-eval-asplos-2009.pdf>
10. Changkyu Kim, Simha Sethumadhavan, M.S. Govindan, Nitya Ranganathan,
    Divya Gulati, Doug Burger, Stephen W. Keckler. *Composable Lightweight
    Processors (TFlex).* MICRO-40, 2007.
    <https://www.cs.columbia.edu/~simha/cal/pubs/pdfs/clp.pdf>

### CGRA · 시공간 다중화 계열

11. Dani Voitsechov, Yoav Etsion. *Single-Graph Multiple Flows: Energy
    Efficient Design Alternative for GPGPUs (SGMF).* ISCA 2014.
    <http://class.ece.iastate.edu/tyagi/cpre581/papers/ISCA14SGMF.pdf>
12. Mahim Mishra, Timothy J. Callahan, Tiberiu Chelcea, Girish
    Venkataramani, Seth C. Goldstein, Mihai Budiu. *Tartan: Evaluating
    Spatial Computation for Whole Program Execution.* ASPLOS 2006.
    <https://www.cs.cmu.edu/~mahim/research/ASPLOS06.pdf>
13. Tony Nowatzki, Vinay Gangadhar, Karthikeyan Sankaralingam. *Exploring
    the Potential of Heterogeneous Von Neumann/Dataflow Execution Models
    (SEED).* ISCA 2015.
    <https://users.cs.duke.edu/~lkw34/papers/dataflow-isca2015.pdf>
14. Graham Gobieski, Souradip Ghosh, Marijn Heule, Todd Mowry, Tony
    Nowatzki, Nathan Beckmann, Brandon Lucia. *RipTide: A Programmable,
    Energy-Minimal Dataflow Compiler and Architecture.* MICRO 2022.
    <https://www.cs.cmu.edu/~beckmann/publications/papers/2022.micro.riptide.pdf>
15. Dani Voitsechov, Oron Port, Yoav Etsion. *Inter-thread Communication
    in Multithreaded, Reconfigurable Coarse-grain Arrays (dMT-CGRA).*
    MICRO 2018.
    <https://yoav.net.technion.ac.il/files/2019/06/dMT-CGRA-MICRO2018.pdf>
16. Raghu Prabhakar, Yaqi Zhang, David Koeplinger, et al. *Plasticine:
    A Reconfigurable Architecture for Parallel Patterns.* ISCA 2017.
    <https://csl.stanford.edu/~christos/publications/2017.plasticine.isca.pdf>
17. Seth C. Goldstein, Herman Schmit, Matthew Moe, Mihai Budiu, Srihari
    Cadambi, R. Reed Taylor, Ronald Laufer. *PipeRench: A Coprocessor for
    Streaming Multimedia Acceleration.* ISCA 1999.
    <https://www.cs.cmu.edu/~mihaib/research/isca99.pdf>
18. Michael Bolotski, André DeHon, Thomas F. Knight Jr. *Unifying FPGAs
    and SIMD Arrays (DPGA).* FPGA 1994.
    <https://www.engineering.upenn.edu/~andre/pdf/dpga_fpga1994.pdf>
19. Artur Podobas, Kentaro Sano, Satoshi Matsuoka. *A Survey on
    Coarse-Grained Reconfigurable Architectures from a Performance
    Perspective.* IEEE Access, vol. 8, 2020.
    <https://arxiv.org/pdf/2004.04509>
20. SambaNova Systems. *Runtime virtualization of reconfigurable data
    flow resources.* US Patent 11,809,908, 2023. (제목만 확인, 본문 미독)
    <https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/11809908>

### WT64v1 정본 (본 문서의 좌표계)

21. `docs/wt64v1-architecture-guide/` — §1.4.4 (태그 레이아웃),
    §1.4.7 (ACCTGT · 재조립 결속), §1.5 (논리 ID 사상표), §1.6.2
    (capability 부재), §2.3 (상호연결 3원소), §4.3 (조각·재조립 문맥),
    §4 WOM 절 · §4.4.4 (명시적 순서 의존 확정).
