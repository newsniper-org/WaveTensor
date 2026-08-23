<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# WT64v1 RTL 전면 재구현

## 정본은 하나다

**`docs/wt64v1-architecture-guide/main.pdf` 가 유일한 정본이다.**

이 저장소의 다른 문서 — `.claude-memos/wt64v1_spec.md`, `claude.md`,
`.claude-memos/` 전반 — 은 **비정본**이다. 그 문서들과 정본이 어긋나는 지점은
정본의 **부록 B 가 정정본**이며, 재구현은 부록 B 를 먼저 읽는다.

## clean-room 경계 — 무엇을 읽고 무엇을 읽지 않는가

재구현이 clean-room 으로 성립하려면 재구현 쪽이 원본 구현 표현에 노출되지
않아야 한다. 이것은 형식적 예방이 아니다 — 구현 표현이 섞이면 "무엇을
만들어야 하는가" 대신 "원본은 어떻게 했는가"를 읽게 되고, 그 순간 독립 구현
이라는 주장이 무너진다.

| | 대상 | 근거 |
|---|---|---|
| ✅ **읽는다** | `docs/wt64v1-architecture-guide/**` | 정본 |
| ✅ | `asm/wavetensor_asm.py` | 어셈블러 오라클. 서문이 *"clean-room 오염이 아니다 — 어셈블러는 RTL 이 아니다"* 라고 명시 |
| ✅ | `scripts/golden_*.py` | golden 모델 — 산술 의미론의 authority |
| ✅ | `isa/wt64v1_isa.json` | 정본 §1.7.3 이 요구하는 "기계가 읽는 단일 정의"의 실물 |
| ✅ | `include/generated/*.hex` | golden 이 낸 기대값 벡터 |
| ⚠️ | `isa/truth_table_premigration.json` | **오라클로만.** 통과/실패를 받는 것은 안전하나 **명세로 읽으면 오염** |
| ⛔ | 저장소 루트 `*.v`, `tb_*.v` | 원본 RTL |
| ⛔ | 루트 `test_*.py` | 오라클 목록에 없다. 원본의 top-level 포트명·내부 계층 경로에 결합돼 있어 **간접 오염 경로**다 |

⛔ 항목을 피하는 대가로 하네스를 새로 쓴다. 입력 벡터는 어셈블러에서, 기대값은
golden 에서 직접 받는다.

## 혼재 경계 — 어느 파일이 생성물이고 어느 것이 수기인가

경계를 파일 단위로 선언하지 않으면 아무도 "이 줄을 고쳐도 되는가"에 답할 수
없다.

| 경로 | 성격 | 손편집 |
|---|---|---|
| `rtl/spinal/` | SpinalHDL 설계 (Scala) — **생성기** | ✅ 여기를 고친다 |
| `rtl/generated/` | SpinalHDL 산출 SystemVerilog | ⛔ **금지.** 생성기를 고치고 다시 낸다 |
| `rtl/sv/assert/` | SVA + `bind` 후-formal 하네스 (수기) | ✅ |
| `rtl/sv/prim/` | 벤더 프리미티브 BlackBox 래퍼 (수기) | ✅ |
| `rtl/formal/tla/` | 선-formal 모델 · cfg · 러너 | ✅ |
| `rtl/formal/sby/` | 후-formal BMC / k-귀납 | ✅ |
| `rtl/sim/` | 자립형 cocotb 러너 + 하네스 | ✅ |

생성물은 **커밋한다.** 단 생성기와 **함께** 커밋한다 — 둘이 따로 움직이면
저장소 안의 SystemVerilog 가 무엇으로부터 나왔는지 답할 수 없게 된다.
생성물에는 헤더로 그 사실이 박힌다 (`rtl/spinal/.../Wt64.scala` 의 `rtlHeader`).

## 툴체인 고정

**어떤 도구의 어느 버전으로 쟀는지 답할 수 없는 검증은 검증이 아니다**
(정본 §6.6). 도구는 증거의 일부다.

| 축 | 고정값 | 어디에 |
|---|---|---|
| Arch 스냅샷 | `2026/08/12` | `.devcontainer/devcontainer.json` |
| JDK | `jdk21-openjdk` (LTS) | 〃 (Dockerfile 이 버전을 명시한다) |
| sbt | **1.12.15** | `rtl/spinal/project/build.properties` |
| Scala | **2.13.12** | `rtl/spinal/build.sbt` |
| SpinalHDL | **1.14.2** | 〃 |
| SymbiYosys | 커밋 `f57802a1…` (v0.66) | Dockerfile `SBY_COMMIT` |

`scripts/lint_toolchain_pins.py` 가 이 값들이 서로 일치하는지 **기계로** 대조한다.
사람 기억으로 유지되는 일치는 일치가 아니다.

### 실측 기록 — 이 고정에 이른 근거

가정이 아니라 실제로 재서 정한 값들이다.

- ALA 스냅샷 `2026/08/12` 에 **`sbt` 는 1.x 가 아니라 `1:2.0.6-1`** 이다. 그래도
  쓸 수 있는 이유는 그것이 *런처*이기 때문 — launcher jar 의 boot properties 가
  `version: ${sbt.version-read(sbt.version)[2.0.6]}` 이므로 2.0.6 은 **기본값**이고
  `project/build.properties` 가 이긴다.
- 같은 스냅샷에 **`scala`·`mill`·`coursier` 패키지는 없다.** Scala 컴파일러는
  sbt 가 coursier 로 받으므로 정상이며, **mill 경로는 닫혀 있다.**
- 무버전 `jdk-openjdk` 는 이 스냅샷에서 **26.0.2** 를 준다 (비-LTS).
  `jdk21-openjdk` (21.0.12.u8-1) 로 명시 고정했다.
- **SpinalHDL 은 Scala 3 빌드가 없다** (`spinalhdl-core_3` 부재). 2.13 계열뿐이고
  1.14.2 의 POM 이 의존하는 값이 정확히 `2.13.12` 다.

## 왜 SpinalHDL 인가 — 그리고 무엇이 규범이 아닌가

정본 서문은 *"사용할 HDL(Verilog / Chisel / 혼합)은 재구현팀의 자유다"* 라고
적는다. 즉 **SpinalHDL 은 정본이 지시한 것이 아니라 이 저장소의 선택**이다.
같은 이유로 TLC·cocotb·SymbiYosys 도 정본이 지목한 제품이 아니다 — 정본 6장은
어떤 형식 도구도 제품명으로 지목하지 않고 *성격*(유한 상태 모델 검사기 /
합성 프론트엔드 기반 유계 모델 검사 + k-귀납 / golden 대조)만 규정한다.

정본이 실제로 구속하는 것은 도구가 아니라 **순서**다 (§6.3, 구속력 있음):

> 선-formal → RTL → 후-formal. **1단을 건너뛴 모듈은 완료로 간주하지 않는다.**

## 현재 상태

**단계 0 (환경·규율·미결 결정) 진행 중.** RTL 설계는 아직 없다.

`rtl/spinal/src/main/scala/wt64/gen/ToolchainCheck.scala` 는 **설계가 아니다** —
`make rtl-gen` 이 실제로 무언가를 하는지 판정할 대상일 뿐이며, 재구현 설계가
착지하면 삭제된다. 생성할 것이 없을 때 조용히 성공하는 게이트는 정본 §6.7 이
지목한 실패형 그 자체다.

## 1차 파도 — 착지한 모듈과 가드 대응 (2026-08-22)

§6.3 완료 판정 「모델과의 대응 관계가 서술 가능함」은 기계 검사다 —
각 모듈 파일 머리의 `GUARD-MAP` 블록을 `scripts/lint_guard_map.py` 가
모델의 `AllGuards` 와 대조한다 (전수성 · 유일성 · 참조 실재성, `make lint`
결선). 현재 **ENFORCED 8모델 · 52가드 전수** (CHECK 42 / DELEGATED 9 / ENV 1).

| 모듈 | 모델 | 정본 |
|---|---|---|
| `route/RouteJudge` | Route.tla | §1.6.3 진입점 판정 · 전파 · sticky |
| `hiu/MmioConfig` | Route.unique_owner 강제 지점 | §3.7.1 사상표 · §1.4.5 기입 거절 |
| `fabric/SharedUnit` | SharedUnit.tla | §2.2 대기 처분 · 무처분 없음 |
| `fabric/ResultBank` | ResultBank.tla | §2.4 소유 구간 [t, t+L] |
| `fabric/FabricMerge` | Fabric.tla (11가드) | §2.3 선택 규칙 · §2.6 배압 · FAB-9/10 |
| `hiu/XlateStore` | XlateStore.tla + Isolation 저장·채움 축 | §3.6 직접 사상 · flush 데이터 잔존 · D12 |
| `decode/DecodeWalk` | Walk.tla + Decode.tla | §4.2 END authority · §1.6.1 판정 위치 · SEC-7 |

2차 파도 대기: HiuPipeline(승인 축 — Isolation 위임 가드 5), Payload 재조립,
MemOrder 토큰, NoLoss 회계 횡단 검사, 피연산자 해석(EH 본문).

## 모델 환류 대기 — 구현이 새로 한 결정 (§6.3 5단계)

RTL 이 모델에 없는 결정을 했다. §6.3: 「그 결정을 모델로 돌려보낸다.」
아래는 1차 파도가 남긴 환류 대기 목록이다 — 처리 전까지 이 목록이 부채다.

**RouteJudge**

- 뷰 기입 인터페이스를 엔트리 직접 지정(idx-addressed) 방식으로 정했다 — 모델 ConfigOwn 은 집합 합집합 갱신만 말하고 표의 물리 조직은 정하지 않는다. 이 선택으로 할당·거절 로직이 전부 MmioConfig 로 가고 RouteJudge 는 순수 미러가 된다. view_sync 의 원자성(표 반영과 뷰 구동이 같은 조작)이 모듈 간 계약이 됐다 — 모델은 ConfigOwn 한 액션 안의 원자 대입이었으므로,…
- 소유 해제(en=False 기입)를 인터페이스에 열어 두었다 — 모델 ConfigOwn 은 추가만 있고 제거 액션이 없다. reset(§1.5 전부 공집합)으로 되돌리는 길이 필요해 열었으나, 해제가 in-flight 토큰과 겹치는 시간축은 모델에 표현이 없다. 후-formal 또는 모델 개정 대상.
- tokIn 을 valid 스트로브(토큰 하나 = valid 한 사이클)로 전제했다 — Route.tla 는 시간축이 없다고 스스로 적었고(머리 주석), 같은 토큰이 여러 사이클 제시되면 faultFire 가 사이클마다 선다. ISA-4 의 시간축은 후-formal(sby) 몫이라는 모델의 위임을 따랐으나 스트로브 전제 자체는 구현의 새 결정이다.
- src_kind ≥3 (예약) 의 거절은 이 판정기에 두지 않았다 — malformation 판정(디코드 경계, Decode 소관)이지 route 축이 아니다. ISA-5 분류 배타성의 우선순위 규정과 맞물리는 결정이므로 Decode 쪽과 정합 확인 필요.

**MmioConfig**

- GUARD-MAP 배치 이탈 (통합자 확인 요망): 과제는 본 파일에 Route 6줄을 요구했으나 선행 착지한 route/RouteJudge.scala 가 이미 6줄 전부를 보유 (unique_owner 는 DELEGATED(MmioConfig)). lint_guard_map 의 가드당-정확히-1줄(전수성) 요구 때문에 본 파일은 파싱되지 않는 서술 블록으로 unique_owner·view_sync 이행 지점만 기록 — 중복 …
- 엔트리 내부 비트 배치 잠정 결정 (§3.7.1 이 호스트 합의로 미룬 자리): LNID 엔트리 [31]V·[30:24]예약·[23:16]소유 지점·[15:0]LNID / LBID 엔트리 [31]V·[30:16]예약·[15:8]슬롯 구간 시작·[7:0]길이. 예약 비트는 쓰기 무시(마스크 정규화 저장)·읽기 0 — 호스트 ABI 합의(§3.10) 입력으로 회부할 것
- 등록 수락 용량 capSlots = min(4*nPoints, 256): RouteJudge 의 뷰 표 용량(viewEntries = 4*nPoints)과 맞물리는 슬롯만 기입을 수락하고 용량 밖 슬롯은 거절+loud fault — 표에는 있고 뷰에는 없는 이름(view_sync 스큐)을 만들지 않기 위함. Route.tla 에는 유한 뷰 용량 개념이 없다 — 모델로 돌려보낼 결정
- V=0 기입 = 슬롯 해제 (표·역방향 표·뷰 동시 소거), 점유 슬롯 V=1 재기입은 거절 (해제 후 재기입 2단계): Route.tla ConfigOwn 에는 제거 액션이 없다 — remove 액션 추가 검토 요청
- 없는 지점 등록 거절: 소유 지점 필드는 고정 8b(형상 무관)이므로 p >= nPoints 값이 표현 가능 — 수락하면 뷰에는 있고 배달자는 없는 이름이 되므로 기입 시점 거절+loud fault. 모델은 p ∈ Points 만 존재해 이 결함형이 표현 불가
- faultBadWrite 폴딩 규정 (§5.6 「신호마다 명시」의 이 표면 몫): 용량 밖 슬롯·없는 지점·점유 재기입 3원인을 1비트로 접고, D2 서로소 위반(faultDupOwner)과는 접지 않음
- MMIO 타이밍 계약: LNID 기입은 역방향 표 동기 읽기 1사이클 때문에 2사이클(수락→CHECK 커밋/거절)이며 그동안 ready 강하. 커밋 자체는 Mem 단일 워드 쓰기 1회라 §3.7.1 원자성 유지. reset 후 2^16 사이클 초기화 소거 동안에도 ready=0 (§1.5 공집합의 관측 가능한 구현) — 호스트 부팅 순서 문서에 반영 필요
- 동시 wstrobe/rstrobe 제시 시 쓰기 우선 — 소박한 인터페이스의 잠정 규약 (버스 어댑터 착지 시 재확인)

**SharedUnit**

- 추월 금지(FIFO 보존)를 구현이 새로 결정했다: 모델 Arrive 의 직행 분기는 serving = {} 만 요구해 보류 열이 비어 있지 않아도 새 도착이 대기자를 추월해 즉시 점유할 수 있다. RTL 은 acceptDirect 에 queueEmpty 를 추가로 걸어 추월을 금지했다 (FAB-6 도착 순서 공정성의 이 지점 형태). 모델에 no_overtake 가드로 돌려보내 검증할 것을 제안
- 배압 무시 → loud fault 경로가 모델에 동작으로 없다: 모델은 backpressure 가드 삭제 실험(조용한 소실)으로만 그 자리를 덮는다. RTL 은 §2.2/§2.6 대로 위반을 sticky fault 로 구현했고, 위반 갈래가 어떤 상태(슬롯·본체·카운터)에도 쓰지 않음(FAB-10 소비자 무결성)도 함께 구현했다 — 모델에 violating-push 동작 + fault_raised/fault_sticky/bp_…
- 동시성 결정: 모델은 Arrive/Dequeue/Complete 가 원자적 인터리빙이라 같은 순간의 도착+dequeue 가 없지만, RTL 은 한 사이클에 둘이 겹친다. 가득 찬 열에서 pop 하는 사이클의 도착은 보수적으로 배압 처리했다 (room 판정은 현재 cnt 기준, pop 이 비운 자리는 다음 사이클부터 보인다) — 배압은 오류가 아니므로 적법하나 모델이 모르는 결정
- 본체 인터페이스 계약을 구현이 정의했다: start 는 busy 낮은 사이클에만 서고(처분 구조가 보장), busy 는 start 다음 사이클부터, done 은 완료 사이클 1사이클 + rsp 동시 유효. 모델의 Complete 에 대응하는 RTL 문면이며 본체 교체(자리 표시자 → 실제 나눗셈·행렬 유닛)의 고정 경계

**ResultBank**

- 나이 카운터는 0..L 만 표현한다 (모델은 0..L+1). 근거: 해제가 age === L 판정과 같은 블록에 융합돼 있어 age > L 이 구조적으로 생성 불가능 — 위반 상태를 저장할 별도 검사기가 감시할 전이가 없다. 이 융합을 깨는 개정은 L+1 표현과 검사기를 함께 들여와야 한다고 파일 머리에 못박았다 (모델 해설의 「판단하라」 지점에 대한 답).
- 획득 거절의 관측 형태: 모델은 acquire_free 가드가 동작 자체를 막지만, RTL 의 요청은 배선으로 도착하므로 「막힘」을 granted === False 의 명시적 같은-사이클 응답으로 만들었다 — FAB-2 의 「무처분 없음」 어휘를 획득 경로에 적용한 결정. 모델에 거절 관측 변수는 없다.
- 소유는 허가 다음 사이클부터 관측된다 (레지스터 갱신) — 구간 시작 t 는 허가+1 사이클이고, 허가와 같은 사이클의 기입은 자격 없음으로 fault 다. 모델에선 Acquire 와 Write 가 별개 원자 단계라는 사실의 RTL 시간축 해석이며, 모델이 명시하지 않은 결정이다.
- 범위 밖 물리 슬롯 색인 (slotCap 이 2^k 가 아닐 때 존재): 기입은 자격 없음으로 접어 같은 sticky fault, 획득은 거절, 읽기는 owned=False. 모델의 Slots 는 불투명 토큰이라 색인 공간이 없다 — 이 처분은 전부 RTL 의 신규 결정이다.
- 소유 해제는 store 를 지우지 않는다 — 값은 구간 종료 후에도 남아 후속 참조(§2.4 정의)에 쓰인다. 모델의 Tick 이 val 을 UNCHANGED 로 두는 것과 정합하지만, 읽기 포트 의미론 자체가 모델 밖이다.
- lastWriter 상태를 RTL 에 두지 않았다 — FAB-4 아래 구간당 기입자 최대 1 (정본 해설: 3항은 공허) 이라 모델의 lastWriter 는 관측 변수로 판단. 기입자 기록을 들여오는 개정은 모델 Acquire 의 lastWriter 초기화(구간 시작 시 기록 재시작)를 함께 들여와야 한다고 주석에 남겼다.

**FabricMerge**

- 선택 기전을 확정했다 — 모델은 선택 기전을 짓지 않고 공정성만 SF 가정으로 걸었는데(Fabric.tla 「공정성」절), RTL 은 one-hot 포인터 라운드로빈(fire 마다 ptrOh := selOh.rotateLeft(1))으로 기전을 세웠다. 모델 자신이 적었듯 「어떤 RTL 이 그 공정성을 갖는지는 후-formal 의 몫」 — 이 라운드로빈이 SF_vars(Grant(p)) 를 실현하는지가 후-formal 검사 대…
- 제공 잠금(lock)을 추가했다 — valid && !ready 동안 selOh 를 lockedOh 로 동결한다. 모델에는 없는 결정이다(모델은 시도 사이에 선택이 바뀌어도 된다). Stream 페이로드 안정성(소비자 관측 안정)을 위해 필요했고, single_producer 를 강화할 뿐 진행성은 해치지 않는다(포인터는 fire 에만 돈다). 모델에 반영하려면 「잠금 중 선택 불변」을 선택 규칙의 속성으로 되돌려 보낼 수 있…
- 배압 위반 표면을 옮겨 읽었다 — 모델의 Shove(~ready 에서 병합 지점 구동)는 이 RTL 에서 구조적으로 불가능하다(pop 이 fire 연언). 물리적으로 남는 위반 표면은 생산 경계(가득 찬 출력 자원에 strb)이고, sticky fault 계기는 거기 있다. §2.6 진행 전파 규범이 「기계 안의 각 소비자」에 배압 규약을 지우므로 이 경계도 §2.6 4항의 적용 지점이라고 읽었다 — 이 독법이 맞는지 모델/정…
- 위반 데이터의 처분을 「소거 + loud fault」로 확정했다 — 모델의 Shove 는 규약 위반 pop(값이 넘어간다)인데, RTL 의 shove 는 값이 자원에도 소비자에도 닿지 않고 버려지며 sticky fault 만 남는다. FAB-5 의 「재시도되거나 fault 를 낸다」 중 fault 갈래의 실현이다.
- 출력 자원을 시프트 큐로 구현 — pop 시 내용을 지우지 않아 마지막 항목을 넘긴 face 에 낡은 값이 남는다(모델의 dat 잔존과 동형). 그 값의 격리는 자원이 아니라 병합 게이팅이 맡는다 — 두 축의 분리를 그대로 유지.
- D 의 값은 여전히 미확정 — Wt64Config.outDepth(기본 1) 파라미터로 유지했고 N=3·D=2 형상 elaborate + lint 로 파라미터화만 검증했다. 값 확정은 정본 §2.6 대로 측정과 함께.

**XlateStore**

- VA/PA 전체 폭을 VA_W = PA_W = 44 로 확정했다 — 정본은 E.2 에서 항목 8 B·페이지 4 KiB·필드 목록만 주고 주소 폭을 주지 않는다. 44/44 는 기본 형상(파티션 4 × 색인 16)에서 항목이 정확히 8 B 를 채우는 값이다 (유효 1 + 권한 3 + 태그 28 + 프레임 32 = 64b, 예약 비트 없음). 정본 E.2 에 폭 확정이 필요하다.
- 항목 본체의 비트 배치(하위부터 tag → frame → perm r/w/x, 유효 비트는 Mem 밖 레지스터)를 구현이 정했다 — E.2 는 필드 목록만 준다. 호스트가 8 B 를 직접 기입하는 MMIO 창이 생기면 이 배치가 ABI 가 되므로 정본/모델로 되돌려 확정할 것.
- flush(p) 가 파티션 p 의 진행 중 채움 버퍼 줄도 함께 취한다 — XlateStore.tla 에는 채움이, Isolation.tla 에는 flush 가 없어 flush × 채움 상호작용이 어느 모델에도 없다. 이 결정이 없으면 flush 뒤 이전 컨텍스트의 줄이 커밋돼 HIU-2 가 창 하나만큼 깨진다. 모델에 Flush 가 fill 버퍼를 소거하는 동작으로 추가돼야 한다.
- 채움 커밋 직렬화: Mem 쓰기 포트가 하나라 점유 슬롯 중 고정 우선순위(낮은 파티션 번호 우선)로 사이클당 하나씩 커밋한다. Isolation.tla 의 SubjectFillCommit 은 단일 주체라 중재가 없다 — 다중 파티션 동시 점유 시의 커밋 순서는 모델에 없는 결정이다 (기입 원천이 호스트 구성 표면 하나라 유입도 사이클당 1이라 밀림은 유한).
- install.ready 는 자기 슬롯 점유 외에 같은 파티션 flush 와의 같은 사이클 충돌도 거부한다 (기입 유실 대신 배압) — 모델에 없는 결정.
- 조회 입력을 VA 가 아니라 VPN(32b) 으로 받는다 — 페이지 오프셋은 변환에 관여하지 않으므로 받지 않는 인터페이스 선택.
- flush 효과는 다음 사이클부터 관측된다 (레지스터 경계 1개) — §3.6.3 검증 시퀀스(flush 후 조회)에는 영향 없음.

**DecodeWalk**

- 자기 종류 필드 검산 신설 — 사슬 포인터(authority)가 지목한 종류와 EH 워드 [11:8] 자기 선언의 불일치를 malformation 으로 판정한다. 정본 §1.6.1 목록·Walk.tla 에 없는 검사 (선언–실물 자기모순이라는 §4.2 검산 논리의 연장; 어셈블러는 항상 일치 방출이라 적법 바이너리 무거절). 모델·정본 환류 필요
- 워드 수 필드의 지위 확정 — 보폭 authority 는 카탈로그 표이고 워드 내 [7:0] 워드 수 필드는 검산이다 (END/길이 관계와 동형). 불일치 = malformation, 8비트 전폭 비교. 정본은 이 필드의 검사 여부를 규정하지 않았다 — 환류 필요
- §4.2.3 반복 규약을 전수 구현했다 (과제 명시는 ACCTGT 중복뿐) — PORT/IMM16/IMM32/IMM64/MEM/PRECISION/ACCTGT ≤1, OPREF ≤2, SUBSCRIPT·NOP_PAD 무제한. Walk.tla 는 §4.2.3 을 명시적으로 밖에 두었으므로 이 축의 모델 부재가 확인됨 — 순수 종류 계수 검사라 순회 모듈이 품는 것이 자연스럽다고 판단. 통합자 조정 대상
- END 미출현 = 전부 malformation 으로 판정 (Walk.tla RejCap · 과제 지시대로) — 그러나 정본 §1.3 은 「지원하지 않는 길이는 능력 부재」라 적는다. END 가 구현 상한 밖에 실재하는 잘 형성된 사슬과 END 가 아예 없는 사슬을 상한 안 순회로는 구별할 수 없다 — §1.6.1 항4 (malformation) 와 §1.3 (capability 부재) 의 경계 확정이 정본에 필요
- 방출면 예약 마스킹 — oInstr 워드0 [15:8] 을 0 으로 지워 방출한다. SEC-7 (ii) (판정 이후 구별 불가능) 를 게이트가 아닌 구조로 강제하는 결정이며 모델 관측면에 없는 형태 — 환류 후보
- sticky 발화 시점 — oFault 는 판정 방출 다음 에지에 선다 (set 이 래치된 판정 rMal 만 소비 — mal_carried 의 단일 원천 유지의 귀결). 판정 방출과 sticky 가 같은 tick 이어야 한다는 요구가 어디에도 없음을 확인, 필요 시 규정 요망
- 미지 EH 의 순회 보폭 = 1 워드로 고정 (정본 미규정; 판정은 어차피 malformation 이므로 유일 목적은 순회 유계·결정성) — 환류 후보
- 이 모듈이 남긴 것: 플래그–EH 대응 검사 (§1.6.1 항2) 와 EH 본문 내 예약 필드 (OPREF [23:20]·ACCTGT [23:16]) 판정은 본문 해석과 함께 2차 파도 몫 — 단 D14 의 「판정은 순회 종료 직후 한 번」과 정합하려면 2차 파도의 malformation 항이 같은 판정점(oExecValid 이전)에 합류해야 한다

~~가장 무거운 것 하나 — DecodeWalk 가 찾은 정본 긴장~~ **해소 (2026-08-23)**:
END 미출현의 분류가 *선언 기준 분기*로 확정됐다 (§4.2.2 개정) — 선언
`bh_len` > 구현 상한 = 능력 부재 (순회 전 판정, 오류 아님), 선언 이내 END
부재 = malformation (자기모순). 두 조건이 서로소라 ISA-5 가 구조로 성립.
Walk.tla 에 `capability` 종결 + `cap_declared` 가드, DecodeWalk 에
`oCapAbsent`(StickyFault 불참) 착지. D10 「두 상한」 이분의 재적용이다.
