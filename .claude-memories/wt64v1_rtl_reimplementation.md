---
name: wt64v1-rtl-reimplementation
description: WT64v1 RTL 전면 재구현 착수 (2026-08-20) — 정본은 아키텍처 가이드 PDF 하나, SpinalHDL 주 + SV 검증층, clean-room, 선-formal 우선
metadata: 
  node_type: memory
  type: project
  originSessionId: 4e29961e-988b-4f27-9ede-dfb9c81925bc
  modified: 2026-09-21T13:05:38.362Z
---

2026-08-20 사용자 지시로 **WT64v1 RTL 전면 재구현**이 착수됐다. 사용자 확정
4건:

1. **정본은 `docs/wt64v1-architecture-guide/main.pdf` 하나다.** 사용자 원문:
   *"다른 문서들이 정본이 아니고, 내가 가리킨 PDF 파일이 정본이야"*.
   `.claude-memos/wt64v1_spec.md`(1.1 MB)·`claude.md`·메모 전부 **비정본**이며,
   어긋나는 지점은 정본 **부록 B** 가 정정본이다.
2. **신규 구현이 normative 승계** — 루트 `*.v` 는 오라클·회귀 참조로 존치.
   [[post-stable-roadmap]] §3 이 이 결정으로 대체됐다.
3. **clean-room** — 정본 + 서문 §0.3.1 이 허용한 오라클만 읽는다
   (`asm/wavetensor_asm.py`, `scripts/golden_*.py`, `isa/wt64v1_isa.json`,
   `include/generated/*.hex`). 루트 `*.v`·`tb_*.v`·`test_*.py` 는 **읽지 않는다**
   — 루트 `test_*.py` 를 뺀 이유는 원본 포트명·내부 계층 경로에 결합돼 있어
   간접 오염 경로이기 때문. truth table 은 블랙박스 오라클로만 (명세로 읽으면 오염).
   ⚠️ **2026-08-29 갱신**: 현행 오라클은 `isa/truth_table_encwave.json`
   (domain_version 4 · 키 `0x0##` 3자리)이고, `truth_table_premigration.json` 은
   **「이관 전 계보 전용」으로 좁아진 동결 산출물**이다 — 현행 인코딩 바이너리를
   프로즌 표에 걸면 전량 불일치한다. legacy 를 만져야 할 때는 [[cleanroom-airlock]].
4. **SpinalHDL 주 + SV 검증층** — 설계는 전부 SpinalHDL(→ SystemVerilog 생성),
   수기 SV 는 SVA+bind 하네스와 벤더 프리미티브 래퍼로 한정.

**Why:** 재구현은 실패가 아니라 **발견**의 결과다 (정본 서문 §0.8) — 참조 구현
검증에서 같은 부류의 결함이 반복 드러났고, 공통점은 결함이 아니라 *그것을
가능하게 한 검사*였다. 재구현의 가치는 회로를 다시 쓰는 데 있지 않고 그 검사
실패형을 구조적으로 불가능하게 만드는 데 있다.

**How to apply:**
- 규약 전문은 `rtl/README.md`. 계획 파일은 `~/.claude/plans/ancient-questing-snail.md`.
- **정본 §6.3 이 구속력 있는 순서를 못박는다: 선-formal → RTL → 후-formal.
  "1단을 건너뛴 모듈은 완료로 간주하지 않는다."** RTL 을 먼저 쓰지 말 것.
- 형식화 순서는 정본 부록 D.5: FAB-2 → FAB-3 → HIU-3 → ISA-3 → HIU-8/9 →
  SEC-3 → EXT-3. 각 모델에 **가드 삭제 실험** 필수, 반례는 지향 테스트로 변환.
- 툴체인 고정 (`scripts/lint_toolchain_pins.py` 가 3곳 대조 + PINS_TWOWAY 축):
  JDK 21.0.12 · sbt 1.12.15 · Scala 2.13.12 · SpinalHDL 1.14.2 · sby `f57802a1`
  · btormc 3.2.4(2026-08-29 추가 — sby cover 엔진) · TLA 는 [[rolling-asset-pin-trap]].
  ⚠️ 스냅샷의 `sbt` 는 **2.0.6 (런처)** 이고 `build.properties` 가 실제 버전을
  정한다. `scala`/`mill`/`coursier` 패키지는 스냅샷에 **없다**.
  SpinalHDL 은 **Scala 3 빌드가 없다**.
- `make rtl-gen / rtl-lint / rtl-formal / rtl-sim`. **Makefile 의 MOD 표는
  건드리지 말 것** — `lint_synth_coverage.py` 와 이중 잠금이라 즉시 FAIL 한다.
- 확정된 설계 결정 4건 (정본에 환류됨): 사상표 MMIO = 4 KiB 페이지 직접 배열
  (0x400/0x800, 256×4 B, 단일 워드라 원자성 자명) / 다중 조각 wave = **조각별
  슬롯** / 공유 유닛 점유 중 도착 = **대기** / 접근 승인 = **사후 게이팅**.

관련: [[prestable-compat-policy]], [[fp32-step-sequencer-terminology]],
[[wt64v1-precision-recovery-roadmap]] (참조 구현 현황),
[[cleanroom-airlock]] (legacy 를 만져야 할 때), [[solver-blindness-trap]] ·
[[yosys-bind-trap]] · [[sby-composite-regression]] (공허 PASS 세 형태).

## RTL 이 정본을 뒤쫓는 파도 — 진행 (2026-09-20/21 갱신)

정본이 RTL 을 앞선 지점을 §6.3 순서(선-formal → RTL → 후-formal)로
따라잡는 작업이 진행 중이다.

- **파도 A — 임대별 마스크 키(정본 `7fa5f2e`): 착지 완료**, commit
  `ca3c496`. `MaskUnit.scala` 의 key 저장을 파티션별 `Vec` 로, `keyWr`
  에 `part` 필드 신설, `Wt64Top` 의 `M_NONCE_PART`→`M_MASK_PART`(키·논스
  공용 창). 선-formal `rtl/formal/tla/Mask.tla` 신설(368 run, 기존
  358+10). 후-formal `HiuMask_props.sv` 수리 셋 — 상호배타 `assume`
  누락 · 섀도우-DUT 귀납 보조 불변식 부재 · REKEY 완료/keyWr 겹침
  오판 (전부 검증 하네스 결손, RTL 결함 아님). 실측 함정은
  [[lint-section-refs-gotchas]] · [[host-tlc-shadow-package]] ·
  [[background-task-oom-kill]] 로 별도 기록.
- **파도 B — `CAP_STATUS` 축 둘→넷(정본 `1126a38`): 착지 완료**, commit
  `ac63902` (2026-09-21). 워드 행위를 `host/CapStatusWord` 컴포넌트로 추출
  (Wt64Top 에 후-formal 하네스가 없어 그것이 형식으로 잴 유일한 자리 —
  DELEGATED(Wt64Top) 선례와 같은 논리). 선-formal `CapWord.tla`(377 run),
  후-formal `capword.sby`(변이 7종 전부 FAIL 실측). 축 [0] 은 상류 sticky
  라 레벨 통과(이중 sticky 레이스), [2] 는 `oValid` 한정, [3] 상수 0.
  워크플로는 동시 ≤3 에이전트로 9개, 74분 — [[agent-concurrency-cap]].
- **정본이 RTL 을 앞선 두 파도(A·B)가 모두 닫혔다.** 다음 후보:
  [[mask-golden-sim-regression]] (`make rtl-sim` Mask 2/8 선재 실패 —
  파도 A 의 게이트에 rtl-sim 이 없어 실린 회귀; RTL 결함인지 하네스
  결함인지 미판정). 파도 게이트에 `make rtl-sim` 전 스위트를 넣을 것.
