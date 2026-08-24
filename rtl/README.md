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
| `hiu/HiuPipeline` | Isolation 승인 축 + Decode 경로 축 + Platform | §3.2 여섯 단계 · D11 승인 게이팅 · SEC-2 상태열 |
| `payload/Reassembly` | Payload.tla (11가드) | §4.3 문맥 결속 · D8/D9/D10 · E.10 |
| `memorder/MemOrderGate` | MemOrder.tla (7가드) | §4.4.4 토큰 게이트 · D13 콘 앵커 |
| `decode/OperandDecode` | (모델 없음 — 관측 기반) | §1.4 본문 해석 · ACCTGT 결속 배선 · SEC-7 |
| `hiu/OwnershipTable` | Platform 판정의 데이터 원천 | E.7 두 상태·명시 전이만 · 경계 계약 확정 |
| `mask/MaskUnit` | (golden 관측 동형) | §5.2 라운드 3단 · E.9 · 고정 사이클 |
| `host/CompletionUnit` | FAB-6 앵커의 장치 실물 | E.5 링 · E.6 통지 · **E.11 드레인 집계** |
| `payload/Reassembly`+ | Payload +3 가드 (E.12) | 문맥 소거 — fault 아님·회계 흔적 |
| `fp/StepSequencer` | (골격 — 산술은 축 (b) 후속) | §2.5 깊이 P · 미상주=능력 부재 · 곱셈기 1 앵커 |
| `top/Wt64Top` | — | 15유닛 배선 · MMIO 디코드 · E.11 여섯 카운트 |

2차 파도 착지 완료 (2026-08-23) — ENFORCED 11모델 · 76가드 전수.
NoLoss 는 모듈이 아니라 합성 속성 — 후-formal 이 조합 위에서 검사한다
(lint_guard_map ENFORCED 주석의 판단 근거 참조).

3차 파도 착지 완료 (2026-08-23) — 16모듈 · ENFORCED 11모델 · 79가드 전수.

4차 파도 착지 완료 (2026-08-23):
- 마스킹 단이 §3.2 실자리(s4)로 — HiuPipeline io.mask 왕복이 s4 의 몸,
  MaskUnit 이 반대편 (결선 계약: io.en = advance). 비마스킹 프레임은 승인
  소유권 조회 전용 병행 운반, io.rsp.frame 은 마스킹된 값으로 의미 변경.
- E.11 여섯 카운트 중 다섯 실물 (pipe·pending·output·ownSlots·contexts) —
  tokens 만 발행 관측 상류 미착지로 부분 (정직한 TODO 유지).
- Payload 시간 폭발 처분 — 지배 자유도는 「임의 시점 소거→재개방」의 시간
  배치 (E.12 정책 비규정의 표현이라 좁히기 금지). 형상 축소 + 이름 대칭
  (SYMMETRY — MUST-FAIL run 은 구체 공간 유지, -workers 1 재현성 PIN 보존):
  shapeA 15s (127×), shapeB 9m40s. 배터리 전체 23m24s — 병합 게이트 실용.
- ISA-9 = 기존 증명의 합성 (사상: NoLoss.tla 머리). 잔여 끝-끝 축은 후-formal.

## 후-formal 1차 파도 (2026-08-24) — 주장이 증명이 되다

§6.3 셋째 단. GUARD-MAP CHECK 76 중 **66 이 sby(yosys 0.66 + smtbmc z3
단독)로 증명**됐다 — 대부분 k-귀납(prove), 일부 bmc. **진짜 RTL 결함 0건.**
선-formal 모델을 의사-명세로 쓴 구축 방식의 수확이다.

구성: `rtl/sv/assert/*_props.sv` (SVA 하네스) + `rtl/formal/sby/<모듈>/*.sby`
(머리의 `# PROVES: <모델>.<가드>` 가 lint_postformal 의 대조 앵커).
게이트: `lint_postformal.py`(선언 실재성·CHECK 전용성·커버리지 래칫 66,
make lint 11종) + `make rtl-postformal`(전 태스크 실행 — 미측정은 통과가
아니다).

첫 합성 증명 둘 — HiuPipeline×MaskUnit(상태열 균일·stall_uniform, 어느
모델도 소유하지 않던 축)과 RouteJudge×MmioConfig(view_sync 원자성 —
M3 스큐 부정. 모듈별 두 절반은 PASS, 합성 귀납은 2^16 Mem 부담).

도구 함정 (재현·해소·메모리 등재): **yosys 0.66 은 bind 를 조용히
무시한다** — 하네스가 제거돼 전 태스크 공허 PASS. 세 팀이 독립 적발.
expose+래퍼로 대체, 공허 검출 = smt2 assert 셀 수 + cover reached 증인.
generate 라벨 유일화 실패·proc_rom 귀납 비구속(memory_map)도 함께.

미덮임 CHECK 10 (2차 파도 대상): 구조 skip 2 (out_no_reason —
원인 채널 부재는 트레이스 속성 불가·포트 전수 검토로 갈음 / 완전 콘) +
Isolation 승인 축 4 + Payload 2 + 기타.

후속: cocotb 하네스 (SEC-1 golden 대조 — MaskUnit 합성 형상, mask64[43:12]
사영 계약), ISA-1/2 두-형상 대조, ISA-9 끝-끝 합성, 합성 실측 (Q3 전제).
주의: 호스트 tlc 2.19 는 -noGenerateSpecTE 미지원, 호스트 sby 사용 금지 —
전부 컨테이너로.

## 구성 표면 sub-word ABI 조항 (2026-08-24, 결정 B)

**구성 페이지(4 KiB) 전체에 대해 sub-word(바이트 인에이블) 쓰기는 거절 +
loud fault 다.** 적용 범위는 사상표(0x400~0xBFF)만이 아니라 구성 표면
전체다 — E.7 전이 워드·E.12 발화 워드가 같은 원자성 논증 위에 서 있다.

근거는 정본 §3.7.1 의 원자성 규범이 *전제*를 하나 빌려 쓰고 있었다는
발견이다. 「엔트리 폭 4 B = 단일 워드이므로 부분 갱신이라는 상태가
구조적으로 존재하지 않는다」는 논증은 **한 워드 쓰기가 쪼개지지 않는다**를
전제하는데, 정본은 그 전제를 어디에서도 보증한 적이 없다. RTL 은 포트에
바이트 스트로브를 두지 않아 구조로만 봉해 두고 있었고 — 그것은 곧
*문서화되지 않은 ABI 전제*였다. 호스트 버스(PCIe/AXI)는 sub-word 쓰기를
허용하므로, 명문화하지 않으면 상위 어댑터에서 read-modify-write 가 조용히
생기고 위 논증이 무너진다.

**이 저장소가 이행하는 몫**: `hiu/MmioConfig.scala` 의 MMIO 포트는 쓰기
낱알이 워드 하나이고 바이트 인에이블 입력이 아예 없다. 「sub-word 기입」
이라는 사건은 이 경계에 *도달할 수 없다* — 표현 불가능이 곧 이행이다.

**이 저장소 밖에서 지켜야 할 몫 (정직하게 적는다)**: 그러므로 거절의
이행 지점은 이 모듈이 아니라 **상위 어댑터(호스트 버스 → 이 포트 브리지)**
다. 어댑터는 구성 페이지에 대한 sub-word 쓰기 요청을 수락하지 말고 거절 +
loud fault 로 처리해야 한다. 여기에는 그 어댑터가 없으므로 이 요건은
**검사되지 않는다** — 미측정이지 통과가 아니다 (정본 §6.7 원칙 5). 어댑터가
착지하면 이 조항이 그 모듈의 후-formal 속성이 된다.

관련 결정 A (같은 회의): 엔트리 *내부* 예약 비트는 엄격(비0 = 거절 + loud
fault)이다. 아래 「모델 환류 대기」의 MmioConfig 둘째 항목(「예약 비트는
쓰기 무시(마스크 정규화 저장)·읽기 0」)은 이 결정으로 처분됐다 — 그 항목의
문면은 이제 낡았고, 현행 규범은 `hiu/MmioConfig.scala` 머리의 「엔트리
내부 예약 비트」 절이다. 통합자가 환류 목록을 갱신할 때 함께 처리할 것.

## 구성 페이지 구역 지도 — 호스트 ABI 결정 2 (2026-08-25)

E.1 이 `0xC00`–`0xFFF` 를 통째로 「예약」이라 선언한 탓에 정본이 규범으로
세운 표면 넷이 오프셋을 갖지 못하고 있었고 (E.9 마스킹 · E.12 문맥 소거 ·
§2.5 프로그램 적재 · §3.8 fault), RTL 은 그중 셋을 `0xC00` 에 **잠정** 배치
하고 「되돌린다」고 적어 두었다. 결정 2 가 4 KiB 페이지 전체를 다시 배정했고
이 파도가 그 이동을 이행했다.

배정 원칙 넷과 구역·워드 상수는 `top/Wt64Top.scala` 의 companion
`object Wt64Top` 스칼라독이 **유일한 출처**다 — 표를 두 곳에 적으면 그 자체가
드리프트 표면이므로 여기 옮겨 적지 않는다. 이 절이 소유하는 것은 *무엇이
배선됐고 무엇이 안 됐는가*뿐이다.

### 이 파도가 옮긴 것

| 옛 오프셋 | 새 오프셋 | 표면 |
|---|---|---|
| `0xC00`–`0xC1C` | `0xE80`–`0xE9C` | MASK_KEY[0..7] (E.9 1항) |
| `0xC20` | `0xEA0` | MASK_NONCE_PART |
| `0xC24`–`0xC38` | `0xEA4`–`0xEB8` | MASK_NONCE[0..5] (E.9 2항) |
| `0xC3C` | `0xEBC` | MASK_REKEY (E.9 4항) |
| `0xC40` | `0xEC0` | MASK_STATUS |
| `0xC44`–`0xC4C` | `0xF00`–`0xF08` | FP_PROG · FP_BIND · FP_STATUS (§2.5) |
| `0xC50`–`0xC5C` | `0xF40`–`0xF4C` | ABORT_TAG0..2 · ABORT_FIRE (E.12) |
| `0xC60`–`0xC64` | `0xF50`–`0xF54` | ABORT_COUNT · REASM_INCOMPLETE |

상위 디코더도 함께 좁혔다: `selCq` 는 `addr[11:8]==0x3` (256 B) 에서
`addr[11:7]==0b00110` (128 B) 로, `selLoc` (`addr[11:8]==0xC`) 은 사라지고
구역 열하나가 대신 선다. **전부 상수 접두 비교이며 범위 비교는 한 곳도
생기지 않았다** — 생성물에서 확인 가능하다 (`rtl/generated/Wt64Top.sv` 의
`assign sel*` 열한 줄 + `selUnwired` 한 줄). 둘째 파도가 `selFault` 를 미배선
목록에서 배선 목록으로 옮겼을 뿐 줄 수는 그대로다 — 구역 판정의 모양은 배선
여부와 무관하다는 사실이 여기서 보인다.

### 둘째 파도 — 완료 구역 *안쪽* + 장치 전역 fault 표면 (2026-08-25)

첫 파도는 구역 *경계*만 옮기고 `host/CompletionUnit.scala` 안쪽을 옛 배치로
남겼다 (파일 배정 밖이었고 아래 표로 정직하게 등재했다). 전수 검증이 그
어긋남을 RED 로 냈고, 이 파도가 닫았다.

| 워드 | 옛 (구역 안 오프셋) | 새 (정본 E.1.2) |
|---|---|---|
| CQ_BASE_LO / CQ_BASE_HI | 없음 | `+0x00` / `+0x04` (**미배선** — 아래) |
| CQ_SIZE | `+0x00` (RO, 엔트리 수) | `+0x08` (RW, `log2`(엔트리 수)) |
| CQ_HEAD | `+0x04` | `+0x0C` |
| CQ_TAIL | `+0x08` | `+0x10` |
| IRQ_STATUS · IRQ_MASK · IRQ_CLEAR | `+0x10` / `+0x14` / `+0x18` | `+0x20` / `+0x24` / `+0x28` |
| FAULT · FAULT_CLEAR | `+0x1C` / `+0x20` | **삭제** — `0xF80[16]` / `0xF84[16]` 로 |
| 엔트리 창 · 드레인 여섯 · CQ_OCC · ALLZERO | `+0x40`–`+0x7C` | 같음 (움직이지 않았다) |

**가장 위험했던 자리는 `+0x04` 다.** 정본은 CQ_BASE_HI(RW)이고 옛 RTL 도 RW
였는데 실물이 CQ_HEAD 였다 — 정본을 따라 만든 드라이버가 링 기저 상위 워드를
쓰면 완료 링의 *소비 색인이 조용히 덮인다.* 예약(쓰기 무시·읽기 0)이면
무해했을 자리가 유효한 RW 기입으로 상태를 망가뜨리는 형태이며, 그래서
**옛 오프셋을 비우는 것**이 이 수리의 본체다. 옛 FAULT_CLEAR(`+0x20`, WO)도
같은 부류였다 — 새 맵에서 그 자리는 IRQ_STATUS(RO)다.

`0x300`–`0x37F` 의 새 읽기 뮤스는 생성물에서 직접 확인된다
(`rtl/generated/CompletionUnit.sv` 의 `case(io_addr)`): 정의 오프셋은
`8'h08`·`0c`·`10`·`20`·`24`·`60`–`74`·`78`·`7c` 뿐이고 옛 자리
`8'h00`·`04`·`1c` 는 어느 분기에도 없다 — 읽기 0 이다.

**CQ_SIZE 재인코딩.** `+0x08` 읽기가 엔트리 수가 아니라 `log2`(엔트리 수)를
낸다 (깊이 8 → `32'h00000003`, 생성물에서 확인). 같은 워드가 다른 뜻을 갖게
되는 *의미 변경*이므로 옛 자리를 비우는 것이 특히 중요하다 — 드라이버가 옛
값 8 을 새 인코딩으로 읽으면 2^8 엔트리 링이라 오해한다.

**장치 전역 fault 표면 `0xF80`–`0xF90` 배선.** 열여덟 축은 전부 이미 합성
가능한 sticky 비트로 존재했고 (§3.8 만족), 없던 것은 호스트 대면 표면 —
HIU-6 의 「명시적 해제」가 top IO 입력뿐이었다. 다섯 워드가 섰다:

| 오프셋 | 워드 | 실물 |
|---|---|---|
| `0xF80` | FAULT_STATUS (RO) | 열일곱 축의 sticky 배치 + `[6]` 폴딩. `[17]` 엔트로피만 상수 0 |
| `0xF84` | FAULT_CLEAR (WO, W1C) | 각 하위 유닛의 `faultClear` 에 **논리합**으로 들어간다 — 기존 IO 해제선을 무효화하지 않는다 |
| `0xF88` | FAULT_SUMMARY (RO) | `[0]` = STATUS 논리합. 개별 노출을 대체하지 않고 덧붙인다 (§5.6 1항) |
| `0xF8C` | CAP_STATUS (RO) | `[0]` 재조립 슬롯 · `[1]` step 프로그램 미상주. **fault 아님** — STATUS·SUMMARY 어느 쪽에도 들지 않는다 (§1.6.2) |
| `0xF90` | CAP_CLEAR (WO, W1C) | 같은 비트 배치 |

`[6]`「거절된 구성 기입」이 세 원천을 접는다 — `MmioConfig.faultBadWrite` ·
top 의 `cfgSurfBadWrite` · **완료 유닛의 새 `faultBadWrite`**. 상류
관측면(`io.fault.*`)에서는 접지 않고 이 워드에서만 합류하며, 폴딩 지점을
명시하라는 §5.6 3항의 이행이다. `[16]` 링 오버플로의 해제도 이제 여기다 —
완료 유닛은 `io.faultClearOverflow` 입력으로 그 펄스를 받는다.

새 sticky 는 **하나**다 (`io.fault.fpCapAbsent`): StepSequencer 의
`oCapAbsent` 는 종결 사이클 1펄스라 관측면이 놓칠 수 있는데, 정본 E.1.2 가
「능력 부재도 관측이 sticky 여야 재시도 주체가 놓치지 않는다」고 정했다.
원천 모듈이 sticky 를 갖지 않는 유일한 축이라 top 이 *대신 드는* 것이 아니라
*새로 만드는* 것이다. 나머지 열일곱은 배치일 뿐 새 상태가 아니다.

### 자리는 있고 회로는 없다 (§3.9 등재 대상)

새 맵이 **자리와 필드를 정했으나 이 RTL 이 소비 회로를 내지 않는** 표면이다.
자리를 정한 것과 회로를 낸 것은 다른 사실이고, 섞어 보고하지 않는다 —
미측정은 통과가 아니다 (정본 §6.7 원칙 5).

「예약」과 「미배선」은 전기적으로 같다 (쓰기 무시 · 읽기 0). **다른 것은
사실이다**: 예약은 *표에 없는* 오프셋이고, 아래는 표에 *있는데* 소비자가 없는
오프셋이다. 그 구별이 코드에 보이도록 미배선 구역도 이름 있는 상수를 갖고
(`object Wt64Top` 의 `Sq`·`Xent`·`Xctl`·`Fault`·`Ident`) 디코더가 그 구역을
**열거한다** (`selSq`·`selXent`·`selXctl`·`selFault`·`selIdent` → `selUnwired`).

| 표면 | 오프셋 | 상태 | 부재의 실체 |
|---|---|---|---|
| 명령 링 전량 | `0x380`–`0x390` | 미구현 | 명령 방향 실물 0건 — 일의 원천이 top 의 `io.instr` 외부 제시이고, 링에서 디스크립터를 꺼내는 경로가 없다 |
| 두 링의 base | `0x300`/`0x304` · `0x380`/`0x384` | 미구현 | 현행 완료 링은 *장치 상주*(내부 `Mem`)라 기저 주소를 소비하지 않는다. 완료 쪽 두 워드는 `object CompletionUnit` 의 `OFF_CQ_BASE_LO/HI` 가 이름을 들고 **어느 회로도 참조하지 않는다** — 그 사실 자체가 미배선의 뜻이다 |
| CQ_SIZE 의 *기입* 반쪽 | `0x308` | 부분 | 읽기는 실물(`log2` 재인코딩). 기입은 링이 장치 상주라 이행할 수단이 없다 — 현재 크기와 *같은* 값만 수락(무동작)이고 다른 값은 **거절 + loud** (`0xF80[6]`). 조용한 무시를 고르지 않은 이유는 호스트가 자기가 정한 크기의 링이 있다고 믿게 되기 때문이다. 링의 거처 합의(§3.10)가 서면 진짜 RW 가 될 자리 |
| 변환 항목 배열 128워드 | `0xC00`–`0xDFC` | 내부만 | XlateStore 의 `install` 포트는 실재하나 top 이 외부 IO 로 수출한다 — E.3 「호스트가 기입한다」의 *호스트 쪽 문*이 없다 |
| XLATE_FLUSH | `0xE00` | 내부만 | §3.6.3 flush 논리는 XlateStore 에 있고 **발화 표면만** 없다 (top IO 입력) |
| 미적중 관측 3워드 + 해제 | `0xE04`–`0xE10` | 미구현 | 미적중 sticky 는 HiuPipeline 에 있으나 top IO 로만 나가고, 정지한 요청의 VPN 배선은 0건 |
| FAULT_STATUS `[17]` 엔트로피 | `0xF80[17]` | 미구현 | 비트 *자리*는 ABI 로 확정됐고 **세울 원천이** 없다 — 엔트로피원 유닛 자체가 재구현에 미착지다. 생성물에서 상수 0 (`faultWords_status[17] = 1'b0`). 해제 경로도 참조되지 않아 회로가 서지 않는다 |
| HIU_ABI_VERSION | `0xFFC` | 미구현 | 자리는 되살렸으나 **판 번호가 §3.10 합의 대상**이다 — 틀린 값을 내는 것이 값을 안 내는 것보다 나쁘다 |

### 워드 안의 예약 비트 — 엄격 (결정 A 와 같은 형태)

새로 배선된 워드 중 예약 비트를 가진 넷에 거절 경로를 냈다. 비0 기입은
**거절 + loud sticky fault** 이며 마스크는 적재 마스크의 여집합으로 유도한다
(`MmioConfig.LNID_RSV_MASK` 선례 — 두 상수가 따로 표류할 자리를 없앤다):

| 워드 | 예약 | 마스크 |
|---|---|---|
| MASK_NONCE_PART `0xEA0` | `[31:8]` | `0xFFFFFF00` |
| MASK_REKEY `0xEBC` | `[31:8]` | `0xFFFFFF00` |
| FP_BIND `0xF04` | `[30:24]` | `0x7F000000` |
| ABORT_TAG2 `0xF48` | `[31:16]` | `0xFFFF0000` |
| ABORT_FIRE `0xF4C` | `[31:1]` | `0xFFFFFFFE` |
| CQ_SIZE `0x308` | `[31:5]` | `0xFFFFFFE0` |
| IRQ_MASK `0x324` | `[31:1]` | `0xFFFFFFFE` |
| IRQ_CLEAR `0x328` | `[31:1]` | `0xFFFFFFFE` |
| FAULT_CLEAR `0xF84` | `[31:18]` | `0xFFFC0000` |
| CAP_CLEAR `0xF90` | `[31:2]` | `0xFFFFFFFC` |

앞 넷은 `top/Wt64Top.scala` 가, IRQ_MASK 는 **정규화에서 거절로 바뀌었다** —
옛 착지는 `wdata & 1` 로 정규화해 저장했는데 정본 E.1.2 가 이 워드의
`[31:1]` 을 *엄격*으로 못박았다. CQ_SIZE·IRQ_MASK·IRQ_CLEAR 의 거절은 완료
유닛이 자기 sticky (`io.faultBadWrite`)로 들고 `0xF80[6]` 에서 합류한다.
같은 구역의 **RO 오프셋 쓰기**(CQ_TAIL · IRQ_STATUS · 엔트리 창 · 드레인
여섯 · CQ_OCC · ALLZERO)도 같은 sticky 로 거절된다 — 마스킹·step·소거 구역이
이미 하던 처분과 같은 형태이며, 완료 구역만 관대하게 두면 같은 페이지 안에서
처분이 갈린다.

거절은 하나의 새 sticky (`io.fault.cfgSurfBadWrite`, 해제 `io.faultClear.
cfgSurfBadWrite`) 로 접힌다. `MmioConfig` 의 `faultBadWrite` 와 **접지 않은**
이유는 원천 모듈이 다르기 때문이다 — 하위 유닛의 sticky 를 top 이 대신 들 수
없다. 호스트 대면 표면(`0xF80[6]` 「구성 — 거절된 구성 기입」)에서 한 비트로
합류하며, **그 표면은 둘째 파도에서 착지했다** — 폴딩은 이제 실물이다.

FP_PROG 의 용량 밖 슬롯·색인과 step 워드 예약 비트는 **StepSequencer 가 이미**
자기 계약으로 거절하고 `faultBadProg`(새 맵 `0xF80[15]`)로 크게 알린다 —
top 에서 두 번 검사하지 않는다. 검사가 두 곳에 있으면 둘이 갈리고, 그때 어느
쪽이 정본인지 답할 수 없다.

## 모델 환류 대기 — 구현이 새로 한 결정 (§6.3 5단계)

> **처리 현황 (2026-08-23, 2차 파도)**: 아래 1차 파도 목록의 대부분이
> 처분됐다 — 모델 개정(Route ConfigRelease · SharedUnit no_overtake ·
> Fabric 비-커버리지), 정본 등재(§2.2 보류 순서 · §2.3 제공 잠금 · §2.4
> 자격 관측면 · §3.7.1 원자성 계약·거절 3원인 · §4.2.2 검산 확장), B.5
> 회부(엔트리 배치). 2차 파도가 새로 남긴 환류는 각 모듈 보고 기준으로
> 이 절 말미에 추가된다. 미처분 잔여: E.2 주소 폭 44/44 · 항목 배치 ABI ·
> flush×채움 모델 추가 · 채움 커밋 직렬화 (부록 E·Isolation 모델 확장 대기),
> 고정 지연 길이(1사이클 잠정) 정본 확정, 자격/비소유 fault 폴딩 구분.

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

**Wt64Top — 구역 지도 파도 (2026-08-25)**

- **형상 밖 파티션 값의 거절은 새 맵의 문면을 넘어선 결정이다.** 결정 2 는
  MASK_NONCE_PART·MASK_REKEY 의 필드를 「`[7:0]` 파티션 · `[31:8]` 예약(엄격)」
  으로만 정하고, `[7:0]` 안의 *없는 파티션* 값(`>= cfg.xlateParts`)의 처분을
  비웠다. 이 RTL 은 **거절 + loud fault** 로 정했다 — 조용히 자르면 파티션 4 를
  재키잉하려던 호스트가 파티션 0 의 키를 갈아 버리고, 그것이 정본이 반복해서
  지목한 「조용히 소멸」이다. 근거는 `MmioConfig` 의 「없는 지점 등록 거절」
  (pointBad) 선례와 결정 A 의 되돌림 비대칭(엄격→관대는 무해, 관대→엄격은
  편도)이다. XLATE_FLUSH(`0xE00`)도 같은 8b 파티션 필드를 쓰므로 배선될 때
  같은 처분이어야 한다. ⇒ §3.10 합의 입력.
- **RO 오프셋 쓰기의 거절을 이 구역들에 실제로 걸었다.** MASK_STATUS ·
  FP_STATUS · ABORT_COUNT · REASM_INCOMPLETE 에 대한 쓰기는 거절 + loud
  fault 다 (조용히 무시하면 드라이버는 자기 쓰기가 먹혔다고 믿는다).
  대칭항인 **WO 오프셋의 읽기는 0 반환·fault 없음** 이며, 이행 방식은 읽기
  경로가 그 워드를 *덮지 않는 것*이다. 두 처분이 반대인 근거는 §3.7.1 함정이
  남긴 방향 축이다 — 「돌려주는 쪽」은 관대, 「받아들이는 쪽」은 엄격.
  정본 §3.7 예약 정책은 이 축의 결론을 아직 적지 않았다. ⇒ 규범 승격 대상.
- **새 sticky 하나가 늘었다** (`io.fault.cfgSurfBadWrite`). top 이 직접
  디코드하는 구성 표면의 거절을 든다. `MmioConfig.faultBadWrite` 와 접지
  않은 이유는 원천 모듈이 다르기 때문이며(하위 유닛의 sticky 를 top 이 대신
  들 수 없다), 호스트 대면 표면 `0xF80[6]` 에서 한 비트로 합류한다 (둘째
  파도에서 착지 — 아래 항목). §5.6 이 요구하는 「폴딩 여부는 신호마다
  명시」의 이 표면 몫이다.
- ~~**완료 구역은 경계만 새 맵이고 안쪽은 옛 맵이다**~~ **해소 (둘째 파도)** —
  위 「둘째 파도」 표. 남은 미결은 *링의 거처*뿐이다 (호스트 메모리 링이면
  base 를 소비하고 엔트리 창이 불필요, 장치 상주 링이면 그 반대). 그 합의가
  서기 전까지 CQ_SIZE 기입은 「같은 값만 수락, 다른 값은 거절 + loud」다.
  ⇒ §3.10 합의 입력.
- **CQ_SIZE 기입의 처분을 RTL 이 정했다.** 정본은 이 워드를 RW 로 정했는데
  장치 상주 링에서는 크기가 elaborate 상수라 이행할 수단이 없다. 갈래는 셋
  이었다 — (a) 조용히 무시 (b) 거절 + loud (c) 항상 거절. (a)는 호스트가 자기가
  정한 크기의 링이 있다고 믿게 만드는 「조용한 실패」이고, (c)는 크기를 확인만
  하려는 정본 준수 드라이버까지 벌한다. 그래서 (b)의 세분 — *현재 값과 같으면
  수락(무동작), 다르면 거절* — 을 골랐다. ⇒ §3.10 합의 입력.
- **IRQ_MASK `[31:1]` 이 정규화에서 거절로 바뀌었다.** 정본 E.1.2 가 엄격으로
  못박은 것을 옛 착지가 관대하게 들고 있었다. 결정 A 의 되돌림 비대칭
  (엄격→관대는 무해, 관대→엄격은 편도)이 이 방향의 이동을 지금 해야 하는
  근거다.
- **장치 전역 fault 표면이 섰고 `[6]` 의 폴딩 지점이 확정됐다** — 세 원천
  (`MmioConfig.faultBadWrite` · top `cfgSurfBadWrite` · 완료 유닛
  `faultBadWrite`)이 `0xF80[6]` *에서만* 합류한다. 상류 관측면에서는 여전히
  접지 않으므로 진단은 원천별로 남는다. §5.6 3항의 「폴딩 여부는 신호마다
  명시」의 이 표면 몫이다.
- **능력 부재 sticky 를 top 이 새로 하나 만든다** (`io.fault.fpCapAbsent`).
  StepSequencer 의 `oCapAbsent` 만 종결 1펄스라 sticky 원천이 없었다. 정본
  E.1.2 CAP_CLEAR 항의 「능력 부재도 관측이 sticky 여야 재시도 주체가 놓치지
  않는다」가 근거다. ⇒ StepSequencer 가 자기 sticky 를 드는 편이 옳은지는
  모델 환류 대상 (다른 열일곱 축은 전부 원천 모듈이 든다).
- **HIU_ABI_VERSION 은 자리만 되살렸다.** 판 번호의 내부 필드 분할
  (major/minor 등)이 §3.10 합의 대상이라 값을 정하지 않았고, 정하지 않은 값을
  회로로 내면 드라이버가 그것을 진짜로 읽는다. 자리(`0xFFC`)와 「페이지
  마지막 워드여야 한다」는 제약만 `object Wt64Top.Ident` 가 든다 (elaborate
  시점 `require` 로 강제).

**후-formal 영향 — 둘째 파도 (2026-08-25 실측)**: `[files]` 역색인 전수 결과
**영향 태스크 0건**이다. 근거는 둘이다 — (1) 열여섯 `.sby` 어느 것의 `[files]`
절도 `CompletionUnit.sv`·`Wt64Top.sv` 를 읽지 않는다 (두 파일을 top 으로 삼는
태스크도, 그것을 `bind` 하는 props 파일도 없다). (2) `make rtl-gen` 뒤
`git status rtl/generated/` 가 그 둘만 modified 로 내고, 열여섯 태스크가 읽는
파일 전수를 HEAD 와 대조하면 `RouteMmio_props.sv` 하나만 다르다 — 그것은 다른
곳에서 진행 중인 RouteMmio 수리이지 이 파도의 산출이 아니다. 확인 삼아
`MmioConfig/mmio_config` 와 `Reassembly/props` 를 실제로 돌려 둘 다 PASS.

⚠ **완료 구역과 fault 표면에는 후-formal 태스크가 없다.** 이 파도가 옮긴
오프셋도, 새로 낸 fault 표면도 단언이 한 줄도 걸려 있지 않다 — `rtl/sv/assert/`
와 `rtl/formal/sby/` 가 이 파도의 파일 배정 밖이라 여기서 만들 수 없었다.
미측정은 통과가 아니다 (§6.7 원칙 5). ⇒ 후속 파도 대상: `CompletionUnit` 의
오프셋 배타성(정의 워드 밖 기입이 어떤 레지스터도 움직이지 않음)과
`0xF84` W1C 의 「해제가 발화를 삼키지 않음」이 첫 두 속성이다.

**후-formal 상태 주의 (2026-08-25 실측)** — `RouteMmio/route_mmio` 의 `prove`
태스크가 **HEAD 에서 이미 실패한다**: `p_bank_iff`(props.sv:233) ·
`p_pair_bank`(props.sv:253) 두 단언이 k-귀납에서 반례를 낸다 (`bmc` 는 PASS).
구역 지도 파도와 무관함이 실측으로 확정됐다 — 그 태스크가 읽는 세 파일
(`MmioConfig.sv` · `RouteJudge.sv` · `RouteMmio_props.sv`)이 HEAD 와 바이트
동일하고, HEAD 를 `git archive` 로 푼 청정 트리에서 같은 두 단언이 같은 줄에서
같이 실패한다. `make rtl-postformal` 은 지금 red 다 — 미측정이 아니라
**측정된 실패**이므로 조용히 두지 않는다. ⇒ 별도 수리 대상.

~~가장 무거운 것 하나 — DecodeWalk 가 찾은 정본 긴장~~ **해소 (2026-08-23)**:
END 미출현의 분류가 *선언 기준 분기*로 확정됐다 (§4.2.2 개정) — 선언
`bh_len` > 구현 상한 = 능력 부재 (순회 전 판정, 오류 아님), 선언 이내 END
부재 = malformation (자기모순). 두 조건이 서로소라 ISA-5 가 구조로 성립.
Walk.tla 에 `capability` 종결 + `cap_declared` 가드, DecodeWalk 에
`oCapAbsent`(StickyFault 불참) 착지. D10 「두 상한」 이분의 재적용이다.
