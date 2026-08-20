<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# WaveTensor post-stable 장기 계획 — 문서화 · 구현 이원화 · 양산

작성일: 2026-08-17
상태: **§3(단계 B) 대체됨 (2026-08-20)** — 아래 §3 배너 참조.
      §2(문서화)·§4(양산)는 유효하며 여전히 plan-only 다.
지시 근거: 사용자 지시 2026-08-17 · 대체 근거: 사용자 지시 2026-08-20

본 메모는 **stable spec 과 stable reference implementation 이 전부 완성된
이후**의 3단 장기 계획을 규정한다. 현행 개발 (v2.0 TRAIN / 3a FDOT32_CR /
v2.1 SCALE) 의 어느 것도 대체하지 않으며, 본 계획의 어떤 항목도 §1 의
진입 게이트가 열리기 전에 착수하지 않는다.

## 1. 진입 게이트 (전건 — 하나라도 미충족이면 본 계획 전체가 잠김)

1. **stable spec 확정**: `.claude-memos/wt64v1_spec.md` 가 stable release
   판정을 받는다. 이 시점부터 §12a 의 pre-stable 완화가 종료되고 frozen
   first-class 보증이 발효한다 (§12a — pre-stable compat 정책의 종료 조건).
   dead-opcode 제거·recapture·계약 변경이 더 이상 정규 이벤트가 아니게 되는
   그 전환이 곧 본 게이트다.
2. **stable reference implementation 확정**: 현행 순수 Verilog RTL 이
   spec 전건에 대해 gate PASS + golden bit-exact 상태로 동결된다.

두 조건이 **동시에** 충족된 시점을 `T_stable` 이라 하고, 아래 단계는
`T_stable` 이후에만 순서대로 승격한다.

## 2. 단계 A — 본격적인 문서화

`T_stable` 이후 첫 작업. 현재까지의 문서는 **개발 중 기록** (spec + memo +
gate log) 이며, 외부 소비자를 위한 문서화는 의도적으로 미착수 상태다.

- **대상 독자 분리**: (i) ISA 소비자 (컴파일러·SDK 작성자), (ii) RTL
  통합자 (SoC/FPGA 인티그레이터), (iii) 검증자 (golden/formal 재현),
  (iv) 최종 사용자 (SDK API).
- **원천 단일화**: spec 이 normative 원천으로 남고, 문서는 spec 에서
  파생·링크한다 (중복 서술 금지 — 이 저장소의 §12a 기록 규율 연장).
  기존 생성기 관례 (`make lint` 의 gen_isa_tables fresh 검사) 를 문서
  생성물에도 확장할지 여부를 그 시점에 판정한다.
- **재현성 문서**: golden 재생성·gate 재실행 절차를 외부인이 그대로
  수행할 수 있는 형태로 (현행 `synth/scripts/diag/` 보존 관례의 일반화).
- **범위 밖**: 마케팅 자료·벤치마크 주장. 실측 근거 없는 성능 서술은
  이 저장소의 measured-anchor 규율 위반이다.

## 3. 단계 B — reference implementation 이원화

> ### ⛔ 이 절은 대체됐다 (2026-08-20, 사용자 지시)
>
> **RTL 전면 재구현이 `T_stable` 이전에 착수됐고, 신규 구현이 normative 를
> 승계한다.** 이 절의 "복합 판 = 보조 구현 / binding gate 판정은 순수 Verilog
> 판에만" 구도는 더 이상 적용되지 않는다.
>
> | 이 절의 전제 | 실제 |
> |---|---|
> | 착수 게이트 `T_stable` | **미충족 상태로 착수** — 게이트 미충족 사실을 §5 규율대로 먼저 보고했고, 사용자가 진행을 선택했다 |
> | 동기: 생산성·파라미터화 실험 | **동기가 다르다** — 참조 구현 검증에서 같은 부류의 결함이 반복 발견된 결과다 (정본 서문 §0.8) |
> | 신규 = 보조 구현 (normative 지위 없음) | **신규가 normative 승계 목표.** 루트 `*.v` 는 오라클·회귀 참조·비교 대조군으로 존치 |
> | Chisel | **SpinalHDL** (정본 서문이 HDL 선택을 재구현팀 자유로 열어 둠) |
>
> **정본은 이제 `docs/wt64v1-architecture-guide/main.pdf` 하나다.** 이 메모를
> 포함해 저장소의 다른 문서는 전부 비정본이며, 어긋나는 지점은 정본 부록 B 가
> 정정본이다. 재구현 규약은 `rtl/README.md`.
>
> 다만 §3.2 의 pin 중 셋은 **살아남아 재구현에 그대로 적용된다** —
> 혼재 경계를 파일 단위로 선언할 것, 생성물은 생성기와 함께 커밋하고 손편집을
> 금지할 것, 툴체인 버전을 고정 기록할 것. 셋 다 `rtl/README.md` 와
> `scripts/lint_toolchain_pins.py` 로 이행됐다.
>
> (아래 원문은 기록의 연속성을 위해 보존한다 — 폐기·개정 서술을 삭제하지 않는
> 저장소 규율.)

문서화 착지 후. **기존 구현을 대체하지 않고 병존시킨다.**

### 3.1 판 (edition) 정의

| 판 | 구성 | 지위 |
|---|---|---|
| **순수 Verilog 판** (기존) | 현행 RTL 전체 | **normative reference** — bit-exactness 의 최종 심판, 기존 gate 계보 (V9-4 / V20-x) 승계 |
| **Chisel+Verilog 복합 판** (신규) | Chisel 로 생성 + 기존 Verilog 모듈 혼재 | **보조 구현** — 생산성·파라미터화 실험, normative 지위 없음 |

### 3.2 이원화의 구속 조건 (설계 이전에 미리 못박는 pin)

- **동치 의무**: 복합 판은 순수 Verilog 판과 **golden 벡터 전건 bit-exact**
  여야 한다. 두 판의 불일치는 그 자체로 결함 신호다 (3a FDOT32_CR 의
  dual-datapath invariant 와 같은 구조 — §27.7a.3 의 사고방식 연장).
- **혼재 경계 명시**: 어느 모듈이 Chisel 생성물이고 어느 것이 기존
  Verilog 인지 파일 단위로 선언한다. 생성물은 커밋하되 생성기와 함께
  커밋하고, 생성물 손편집을 금지한다 (`include/generated/` 관례 승계).
- **gate 이중 실행**: 복합 판도 동일 gate 하네스로 측정하되, **binding
  판정은 순수 Verilog 판에만 있다**. 복합 판 결과는 MEASUREMENT 지위
  (ECP5 반쪽 정책과 동형).
- **툴체인 종속 기록**: Chisel/FIRRTL 버전을 고정 기록한다 (Vivado
  2025.2.1 절대 업그레이드 금지 교훈의 일반화 — `cross_vendor_fabric_evidence.md`).
- **철회 조건 사전 선언**: 복합 판이 동치 의무를 반복적으로 깨거나 툴체인
  유지비가 이득을 넘으면 폐기한다. 폐기는 실패가 아니라 예정된 분기다
  (ECP5 off-ramp 형식).

## 4. 단계 C — 양산 플랜 (이원화)

이원화된 구현이 안정된 후. **두 플랜을 병렬로 수립하되 서로의 전제가
되지 않게 격리한다.**

### 4.1 플랜 1 — 기존 파운드리 공정용

- 대상: 현재 상용 가능한 공정 노드. 구체 노드·파운드리는 그 시점의
  실측 견적으로 결정하며 **본 메모는 노드를 선점하지 않는다**.
- 산출물: 면적·전력·클럭 예산의 measured-anchor 화 (FPGA 실측을 ASIC
  추정으로 옮기는 환산 근거를 반드시 문서화 — 환산 계수를 근거 없이
  쓰지 않는다), 테이프아웃 전 검증 체크리스트, MPW/셔틀 옵션 조사.
- 제약: 이 저장소의 gate 규율 (기준 선공표 → 측정 → 정직 기록) 을
  ASIC 흐름에도 그대로 적용한다.

### 4.2 플랜 2 — 새로운 공정까지 포함하는 장기 플랜

- 대상: 차세대·비주류 공정 (선단 노드, 3D 적층, 신소자 등) 을 포함하는
  더 긴 시야의 플랜. 후보군은 착수 시점의 산업 현황으로 갱신한다.
- 성격: **탐색적** — 플랜 1 의 성공을 전제하지 않으며, 반대로 플랜 1 이
  플랜 2 를 기다리지도 않는다.
- 판정 축: WaveTensor 아키텍처의 어떤 성질이 새 공정에서 비대칭적
  이득을 갖는지 (dataflow·wave/tag 모델·int4 native 경로) 를 근거로
  후보를 좁힌다.

## 5. 이 메모의 지위

- **plan-only**: 본 메모의 어떤 항목도 현행 개발의 우선순위를 바꾸지
  않는다. `T_stable` 이전에 본 계획을 착수하라는 요청이 오면, 게이트
  미충족 사실을 먼저 보고한다.
- **선점 금지**: 노드·툴체인 버전·파운드리 등 시점 의존 선택은 본 메모가
  결정하지 않는다 (착수 시점 실측으로 결정).
- 관련: `future_applications.md` (PLL-DSP, WT64v1CLf GPGPU — 별도 트리거),
  `board_hw_plan.md`, `cross_vendor_fabric_evidence.md` (툴체인 고정 교훈),
  `sdk_architecture.md` (SDK 는 별도 저장소 — 문서화 단계에서 연동).
