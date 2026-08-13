<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# Cross-vendor fabric 실측 — ECP5 vs UltraScale+ (2026-08-13)

작성일: 2026-08-13
상태: **실측 완료 (재현 가능)** — 하드웨어 0대, 비용 $0
대상 RTL: v1.9 `618def9` 시점 (case_result_s2 2단 분할 + tag-latch bank fix 포함)

> **연관 메모**: [`board_hw_plan.md`](./board_hw_plan.md) — 본 실측이 Stage-2 계획을 무효화한다 (§5).
> [`wt64v1_spec.md`](./wt64v1_spec.md) §26.6 (GATE V9-4 FAIL 판정) / §26.9 (congestion 진단) — 본 실측이 그 미해결 질문을 닫는다. spec 은 ISA 규범이므로 본 근거 문서는 분리 보관한다.

---

## 1. 배경 — 무엇이 미해결이었나

v1.9 는 dispatch 파이프라이닝(`case_result_s2`)을 도입하고 자신이 사전 공표한 Fmax gate 를 **충족하지 못했다**: 실측 11.34 MHz vs floor 14.2 MHz (spec §26.6, FAIL 로 정직 기록). 후속 3-lens 진단(§26.9)은 병목이 `u_matmul_unit` 내부 `case(dec_opcode)` 조합 cloud 이고 라우팅이 지연의 68% 라고 특정했으나, **결정적 질문을 열어둔 채 끝났다**:

> **11.34 MHz 는 ECP5 fabric 의 한계인가, 아니면 설계 자체의 구조적 문제인가?**

이 질문이 열려 있는 한 하드웨어 투자 판단(Avant G70 $6,476 / EC2 F2 / Alveo)이 전부 추측 위에 놓인다. 본 문서는 **돈을 쓰기 전에** 그 질문을 실측으로 닫은 기록이다.

---

## 2. 핵심 실측 — 동일 RTL, 3개 fabric

전부 **P&R 후(post-place-and-route)** 수치이며, 동일 geometry (Pod 2×2 클러스터 × 2×2 PE), 동일 commit, 동일 100 MHz 제약이다.

| | **ECP5 LFE5U-85F** | **XCAU25P** | **`xcu55c` (= EC2 F2 실리콘)** |
|---|---|---|---|
| **Fmax** | **11.34 MHz** | 합성만 (용량 초과로 P&R 불가) | **~98 MHz** |
| WNS @ 100 MHz 제약 | — | -1.835 ns (합성 후) | **-0.205 ns** |
| Data Path Delay | 88.1 ns | 11.816 ns (합성 후) | **10.187 ns** |
| **Logic Levels** | **117** | 48 (합성 후) | **48** |
| 라우팅 지연 비중 | 68% | 77.3% (합성 후) | **62.6%** |
| LUT | — | **173,453 / 141,000 = 123% (초과)** | 170,850 / 1,303,680 = **13.1%** |
| DSP | (DSP48 없음) | 156 / 1,200 | 156 / 9,024 |
| 점유율 | 39.56% (TRELLIS_COMB) | 초과 | **13.1%** |

**동일한 RTL 이 fabric 만 바꿔서 8.7배 빨라진다.**

임계경로 양단은 **양쪽 fabric 에서 구조적으로 동일**하다:
`u_ehdec/dec_input_payload_wide_reg[*]` → `u_matmul_unit/cr_payload_reg[*]`
(즉 wide 브로드캐스트 버스 → case dispatch → v1.9 의 `case_result_s2`)

---

## 3. 결론 — ECP5 fabric 이 지배적 원인

**증거 세 겹:**

1. **Logic Levels 117 → 48 (2.4× 얕아짐).** ECP5 에는 DSP48 이 없어 MATMUL/MAC 이 LUT 로 흩어진다. UltraScale+ 는 9,024 DSP 로 이를 흡수한다.
2. **라우팅 비중이 P&R 후 오히려 개선(77.3% → 62.6%).** 13% 점유율에서는 배치기가 혼잡 없이 일한다. ECP5 는 39.56% 점유에서 이미 라우팅이 막혀 있었다 — 이것이 §26.9 가 "5세대 내내 고정된 천장"으로 관측한 현상의 정체다.
3. **용량 자체가 다른 체급.** 173K LUT 는 XCAU25P(141K)를 **123% 초과**하지만 `xcu55c`(1.3M)에서는 **13.1%** 다.

### 3.1 v1.9 판정의 재해석 (중요)

**v1.9 의 "Fmax FAIL" 은 설계 실패가 아니었다 — 측정 대상 fabric 이 잘못됐던 것이다.** 동일 설계가 UltraScale+ 에서 100 MHz 를 **0.205 ns 차이**로 놓친다. 게다가 이 측정은 `-2L`(저속) 등급이고 **실제 F2 는 `-2`(고속)** 이므로, 진짜 F2 실리콘에서는 100 MHz 충족이 유력하다.

단, **설계가 커진 것 자체는 사실이다**: 2026-05 베이스라인 대비 Logic Levels 18 → 48 (2.7×), LUT 61.9K → 173K (2.8×). v1.6~v1.9 의 fp32 step sequencer / vector fp / CVT·DEQUANT / VFMA 가 모두 들어간 결과다. **적정 부품에서는 여전히 100 MHz 급**이지만, 2026-05 의 그 보드(XCAU25P 141K)에는 더 이상 들어가지 않는다.

### 3.2 ECP5 의 재포지셔닝 (normative intent)

**ECP5 는 FOSS 검증 vehicle 이지 성능 타겟이 아니다.** 향후 ECP5 Fmax 수치를 아키텍처 성능 지표로 인용해서는 안 된다 — 그 숫자는 fabric 특성(DSP48 부재 + 라우팅 자원 빈약)에 지배된다. ECP5 가 여전히 유일하게 제공하는 것은 §5 참조.

---

## 4. 도구·라이선스 발견 (재현에 필수)

### 4.1 `xcu55c` ≡ `xcvu47p` — 무료로 F2 실리콘을 다룰 수 있다

AMD 는 동일 다이를 Alveo 이름(`xcu*`)으로도 출하하는데, **무료 device 목록에는 `xcu*` 만 있고 `xcvu*` 는 없다.** 라이선스 검사가 **device 문자열 기준**이라 생긴 틈이다. 로컬 실측 확인:

```
Got license for feature 'Synthesis' and/or device 'xcu55c'   → OK
Got license for feature 'Synthesis' and/or device 'xcu50'    → OK
ERROR [Common 17-345] ... device 'xcvu47p'                   → 차단
```

Vivado part DB 대조 결과 **fabric 이 완전 동일**:

| Part | LUT | FF | DSP | SLR | Family | Speed |
|---|---|---|---|---|---|---|
| `xcu55c-fsvh2892-2L-e` | 1,303,680 | 2,607,360 | 9,024 | 3 | virtexuplusHBM | **-2L** |
| `xcvu47p-fsvh2892-2-e` (F2) | 1,303,680 | 2,607,360 | 9,024 | 3 | virtexuplusHBM | **-2** |

패키지(`fsvh2892`)까지 동일하고 **차이는 speed grade 뿐**이다 → `xcu55c` 결과는 **보수적 하한**. speed grade 를 맞춘 데이터가 필요하면 `xcu50`(-2/-3 제공)을 쓴다. (부차 차이: `xcu55c` 는 GTY 40개 vs `xcvu47p` 96개 — 본 설계는 transceiver 미사용이라 무관.)

### 4.2 ⚠️ Vivado 2025.2 를 절대 업그레이드하지 말 것

- **2025.2 가 마지막 라이선스-프리 릴리스**다 (AMD 명시).
- 2026.1 부터 BASIC 조차 FLEX 파일을 **툴 실행 시점에** 요구하고, **Alveo 계열이 BASIC 에서 제외**된다.
- 즉 업그레이드하면 §4.1 경로가 **소멸**한다. 현 `/opt/Xilinx/2025.2.1` 설치본(81 GB)은 **만료되지 않는 자산**이며 디스크 정리 시에도 보존 대상이다.

### 4.3 AMD 이탈 전제의 현재 상태

`board_hw_plan.md` §1 이 이탈 사유로 기록한 "Vivado 무료 Linux 지원 만료"는 **AMD 가 2026-05-29 경 번복**했다(BASIC 포함 전 티어 Linux 지원). 다만 새 제약이 대체했다: **부품군별 티어 게이팅** — Virtex UltraScale+ 는 BASIC 미포함(CORE $1,200/yr 부터), Artix UltraScale+ 및 Alveo 계열은 접근 가능. 본 문서 §4.1 의 실측이 이 게이팅의 실제 경계를 보여준다.

---

## 5. 하드웨어 계획에 대한 결론

`board_hw_plan.md` 의 2-stage 계획을 다음과 같이 갱신한다.

| | 판정 | 근거 |
|---|---|---|
| **Stage-1 ULX3S ECP5 (~$250)** | **유지** | **링 오실레이터 TRNG 를 실측할 유일한 경로** (§5.1) + `UsbCdcTransport` + FOSS bitstream. 단 **성능 타겟 아님**(§3.2), full Pod 미탑재(MULT18X18D 412 필요 vs 156) |
| **Stage-2 Avant G70** | **폐기** | 리드타임 **52주**, 1년차 $6,476 + 이후 $3,142/yr(유료 Radiant), PCIe **Gen3**(계획의 Gen4 아님), F2 부품 대비 3-5배 작음 |
| **EC2 F2 + Activate** | **유효하나 비긴급** | timing 질문은 §2 로 무료 해결됨. 남는 가치는 **대규모 실제 실행**뿐이며 TRNG 는 불가(§5.1). Seoul 리전 GA(2025-11-12), f2.6xlarge $2.376/hr(us-east-1 대비 +20%), **Seoul spot 미제공** |
| **Alveo 구매** | **불필요** | 국내 중고 물량 사실상 없음, 신품 U50 $3,464(Digi-Key) — 패시브 방열로 데스크톱 부적합. §4.1 로 구매 없이 동일 fabric 접근 가능 |

### 5.1 ⚠️ AWS F2 는 TRNG 를 원천적으로 못 올린다

AWS 는 **조합 루프를 범주적으로 금지**한다 — 에러 `UNSUPPORTED_DESIGN_LOGIC`: *"Combinatorial loops are not allowed in CL designs and AFIs are not generated in such cases."* `aws-fpga` 저장소 전체에 우회 옵션 0회 등장, 제약 수준 완화 불가(SEU 근거), AWS 직원이 포럼에서 *"Correct. We prohibit combinatorial loops"* 로 확답.

**본 설계에 직접 해당한다**: `HIU.v:347` `localparam TRNG_NRO = 8` — 3단 인버터 루프 8개가 `WT_KEEP`/`WT_DONT_TOUCH` 로 보호되어 있다(합성 시 제거 경로 없음, `ifdef VERILATOR` LFSR 대체는 시뮬 전용).

> **역설**: F2 는 **시뮬레이션으로 검증 가능한 모든 것**을 검증할 수 있으나, **실리콘이 아니면 검증 못 하는 유일한 항목(TRNG 엔트로피)**만 못 한다. 따라서 F2 는 TRNG 를 stub 처리한 **후기 단계 대규모 점검용**이지 Stage-2 플랫폼이 아니다.

또한 F2 산출물은 **암호화·서명된 AFI ID** 이지 bitstream 이 아니다 — RTL 이 `SHL-2.1 OR CERN-OHL-W-2.0` 인 프로젝트에는 실질적 후퇴다. 그 밖에: shell 클럭이 **250 MHz 고정**이라 CDC 계층이 신규 필수 작업으로 발생한다.

### 5.2 자금 조달 관련 (참고)

- **AWS Activate Founders ~$1,000**, 유효기간 2년. **사업자등록증이 "registration" 요건을 충족**(법인 불요). Portfolio($200K)는 Activate Provider Org ID 필요 — 자력 경로 없음.
- ⚠️ **2026 예비창업패키지는 사업자등록증이 없어야 신청 가능하다.** 개인사업자 등록 시 해당 트랙이 영구 소멸하고, 대신 초기창업패키지(개인사업자 허용, 3년 이내, 최대 ₩1억, 2027-01~02 창구)가 열린다. **본 실측으로 Activate 가 critical path 에서 빠졌으므로 등록을 서두를 이유가 없다** — 두 트랙을 비교할 시간이 확보됐다.

---

## 6. 재현 방법

```bash
# 전제: /opt/Xilinx/2025.2.1 (라이선스 파일 불요 — §4.1)
cd /home/ybi/WaveTensor

# F2 실리콘 등가 (보수적 -2L)
make synth-pod PART=xcu55c-fsvh2892-2L-e
make impl-pod  PART=xcu55c-fsvh2892-2L-e

# speed grade 정합 데이터가 필요하면
make synth-pod PART=xcu50-fsvh2104-2-e     # 또는 -3

grep -E "Worst Slack|Data Path Delay|Logic Levels" \
     synth/reports/pod_2x2_2x2_impl_timing.rpt
```

**주의**: `PART` 를 명시하지 않으면 `Makefile:91` 의 기본값 `xczu3eg-sfvc784-1-i`(~71K LUT)로 떨어져 현 설계(173K LUT)가 들어가지 않는다. `make -C` 대신 저장소 루트에서 실행할 것(`Makefile:84` 가 `$(PWD)` 사용 — Lattice 쪽 `:140` 은 올바르게 `$(CURDIR)`).

**보고서 파일 주의**: 본 실행이 `synth/reports/pod_2x2_2x2_impl_*.rpt` 를 덮어썼다. 2026-05 XCAU25P 베이스라인(WNS +2.058 ns, LUT 61.9K/141K, DSP 140, 0.62 W)은 `board_hw_plan.md` 와 `wt64v1_spec.md` 에 수치로 보존돼 있다.

---

## 7. 미해결 / 후속

- **`xcu50`(-2, -3) 실행** — speed grade 정합 상한값 확보. 현 `-2L` 수치는 하한이다.
- **full Pod(4×4 클러스터) geometry** — 본 실측은 2×2 다. flagship 규모에서의 혼잡 거동은 미측정.
- **ECP5 seed 1-5 sweep** — §26.9 가 지적한 대로 전 5세대 ECP5 수치가 `seed=1` 단발이다. 11.34 MHz 자체의 잡음 폭이 미확정(본 결론에는 영향 없음 — 8.7배 격차는 잡음 범위를 압도).
- **Alveo 무료 라이선스** — `xcu55c` 를 커버하나 `xcvu47p` 는 아님(별도 family row). 개인사업자 등록 후 신청 시도 가치 있음(무비용, 최악은 거절).
- 미검증: Seoul F2 spot 구매 가능성, AMD Alveo 라이선스의 구매 이력 요구 여부, 개인사업자의 AMD company-info 심사 통과 여부.
