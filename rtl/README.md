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
