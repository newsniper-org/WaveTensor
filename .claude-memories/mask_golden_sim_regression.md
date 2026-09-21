---
name: mask-golden-sim-regression
description: make rtl-sim 의 Mask 스위트 2/8 이 HEAD(ca3c496 임대별 마스크 키 착지)에서 이미 실패한다 — sec1_golden_exact 골든 불일치 · en_is_the_single_stall_source. 별도 파도로 처분 필요.
metadata:
  type: project
  originSessionId: e7f99d7a-a6eb-46be-b7eb-fd78237e02a7
  modified: 2026-09-21T12:33:32.025Z
---

**`make rtl-sim` 이 HEAD 에서 빨갛다** — 2026-09-21 CAP_STATUS 파도(파도 B)의
전수 반증 세 렌즈가 각각 독립으로 실측했다. `rtl/sim/test_mask_golden.py` 의
두 시험이 순정 HEAD `ca3c496`(임대별 마스크 키 착지) worktree 에서도 같은
메시지로 실패한다:

- `sec1_golden_exact` — 「라인 1 (pinned, part=1): io_rsp_frame 0x8DC44C4A ≠
  golden MASKED[43:12] 0x59C63B88」
- `en_is_the_single_stall_source` — `rtl/sim/test_mask_golden.py:468`
  `assert got == exp` AssertionError

`run_wt64.py` 는 Mask 스위트를 먼저 돌리고 첫 스위트 실패에서 `sys.exit`
하므로 **Shape 스위트는 `make rtl-sim` 으로는 도달되지 않는다** —
`make rtl-sim SIM_SUITES=Shape` 로 따로 돌려야 한다(파도 B 는 그렇게 6/6 을
실측했다). `rtl/sim/README.md` 의 「Mask 8 passed (2026-08-28)」 기록은 지금
사실이 아니다.

**Why (추정, 미확인):** 2026-09-20 파도 A 가 `MaskUnit.scala` 의 키 저장을
파티션별로 가르고 `keyWr` 에 `part` 필드를 신설했으며 Wt64Top 의
`M_NONCE_PART`(0x20)를 `M_MASK_PART` 로 넓혀 **키 기입도 그 창을 거치게**
했다. cocotb golden 하네스가 옛 결선(키는 전역 1벌, 창은 논스 전용)을
전제하면 pinned part=1 의 키가 다른 파티션 슬롯에 앉아 골든과 어긋난다.
파도 A 의 게이트 목록에 `rtl-sim` 이 없었다 — 후-formal(18 모듈)·lint·TLA·
레거시 HIU cocotb 는 돌렸지만 `rtl/sim` 은 돌리지 않았고, 그래서 이 회귀가
커밋에 실렸다. **골든 값 불일치라 하네스 결함인지 RTL 실결함인지 아직
가르지 않았다** — 하네스만 고치는 것으로 시작하지 말 것.

**How to apply:**
- 다음 파도(또는 별도 수리 파도)의 첫 작업: `rtl/sim/test_mask_golden.py` 를
  읽어 키 기입 경로(`M_MASK_PART` 창 + `keyWr.part`)를 따라가고 골든
  생성(`scripts/golden_*.py`)의 파티션 전제와 대조한다. RTL 결함이면 `MaskUnit`
  의 후-formal(hiumask.sby)이 왜 못 잡았는지도 함께 묻는다(값 축은 golden
  대조 몫 — SEC-1 은 형식이 아니라 대조).
- 파도 완료 게이트에 `make rtl-sim`(전 스위트)을 **반드시** 넣는다 — 파도 A
  가 그것을 빠뜨렸다.
- 해소 전까지 착지 보고에 「rtl-sim 전부 PASS」라 적지 말고 스위트별로 적는다.

관련: [[wt64v1-rtl-reimplementation]] · [[differential-domain-trap]] (골든
정의역이 손-리터럴이면 새 경로는 오라클에 한 점도 없이 태어난다).
