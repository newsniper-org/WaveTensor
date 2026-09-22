---
name: mask-golden-sim-regression
description: (해소 2026-09-22) make rtl-sim Mask 2/8 실패는 하네스가 io_keyWr_part 를 구동하지 않은 것 — RTL 결함 아님(독립 반증). 남은 이월 둘 — FINAL 엣지 동시 기입 모서리 · MaskUnit.scala 의 낡은 정본 좌표.
metadata:
  type: project
  originSessionId: e7f99d7a-a6eb-46be-b7eb-fd78237e02a7
  modified: 2026-09-22T11:39:57.118Z
---

**해소됨 (파도 C, 2026-09-22).** `make rtl-sim` 의 Mask 스위트 2/8 실패
(`sec1_golden_exact` · `en_is_the_single_stall_source`)는 **하네스 결함**이었다:
파도 A(ca3c496)가 `MaskUnit` 에 `io_keyWr_part` 입력을 신설했는데
`rtl/sim/test_mask_golden.py` 의 `INPUTS` 손 목록과 `write_key()` 가 그 포트를
구동하지 않아 모든 키가 파티션 0 에 앉았고, part≠0 으로 값을 재는 두 시험만
리셋 값(0) 키의 마스크와 비교해 죽었다(관측값 0x8DC44C4A 가 정확히 key=0 의
골든 — 독립 검토자가 `scripts/golden_xchacha.py` 로 확인).

**RTL 결함은 없다** — 「RTL 이 틀렸다」 가설을 세운 독립 검토자가 사본에서
탐침 9종(4파티션 순서 교차 · 롤링 모델 · 재키잉 authority · 가동 중 타/동
파티션 기입 · 동시 엣지 · 벡터 밖 난수 48벌)으로 등가 비교 2천여 건을 전부
골든과 맞추고 기각했다.

**착지한 것:** 하네스가 `io_keyWr_part` 를 구동 · 낡은 문면(전 파티션
무효화, dup 검사 공허) 전부 새 계약으로 · 골든 루프가 `faultNonceDup` 을
하네스 모델과 **등가** 대조(80 라인 중 기대 1 이 17) · 지향 시험 둘 신설
(`key_scope_cross_partition_value` · `wr_other_partition_during_rekey_is_clean`)
· 변이 6종 전부 잡힘 · `boot()` 가 생성물 입력 포트 집합과 `INPUTS` 를
**기계로 대조**(손 목록 구멍을 닫음 — 옛 목록에 대면 `io_keyWr_part` 누락을
즉시 지목) · 하네스의 `MaskUnit.scala:NNN` 좌표 14건(13건이 낡아 있었다)을
같은 줄 축자 「…」 결속으로 바꿔 lint 가 STALE 을 잡게 함 · Mask 10/10 ·
Shape 6/6.

**Why 회귀가 실렸는가:** 파도 A 의 로컬 완료 게이트에 `make rtl-sim` 이
없었다(후-formal·lint·TLA·레거시 HIU 만). 형식은 제어면을, 골든은 값을
잰다 — 둘은 서로를 대신하지 않는다.

**How to apply:**
- RTL 계약을 바꾸는 파도의 완료 게이트에 `make rtl-sim`(전 스위트)을
  **반드시** 넣는다. 러너는 첫 스위트 실패에서 멈추므로 스위트별 결과를
  따로 적는다.
- cocotb 하네스의 입력 목록은 손으로 유지하지 말고 생성물 포트 집합과 기계로
  대조하라 — `test_mask_golden.py` 의 `generated_input_ports()` 가 선례다.
  (`test_shape_equiv.py` 는 `EXPECT_OUTPUTS` 핀으로 같은 구멍을 다른 방식으로
  막는다.)

**이월 처분:**
1. **FINAL 엣지 동시 기입 모서리 — 파도 D 로 해소** (commit `086fb27`,
   2026-09-22): `MaskEngine.tla` → `dirtyNow = compDirty || wrActNow` →
   `MaskUnit/engine.sby` + cocotb 오프셋 스윕. 이제 수락 뒤 busy 사이클
   전부(FINAL 포함)의 같은-파티션 기입이 loud 다.
2. **낡은 정본 좌표 `e-defined.typ:333`(실물 :339)** — `MaskUnit.scala`
   와 `Mask.tla` 의 둘은 같은 줄 축자 결속으로 재조준했다(2026-09-22 후속
   커밋). **`HiuMask_props.sv:890` 하나가 남았다** — 그 파일은
   `hiumask.sby` 의 [files] 라 주석 한 글자에도 재스윕(bmc z3 약 50분)이
   따라와서 다음 HiuMask 편집 때 함께 고친다. 따옴표가 다음 줄에 있어 lint
   는 침묵한다(정의역 밖) — 잊지 말 것.

관련: [[wt64v1-rtl-reimplementation]] · [[selftest-residency]] (주석은 호출이
아니다 — 정의역은 기계가 닫는다) · [[differential-domain-trap]].
