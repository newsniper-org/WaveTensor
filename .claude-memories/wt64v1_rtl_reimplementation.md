---
name: wt64v1-rtl-reimplementation
description: WT64v1 RTL 전면 재구현 착수 (2026-08-20) — 정본은 아키텍처 가이드 PDF 하나, SpinalHDL 주 + SV 검증층, clean-room, 선-formal 우선
metadata: 
  node_type: memory
  type: project
  originSessionId: 4e29961e-988b-4f27-9ede-dfb9c81925bc
  modified: 2026-08-20T06:48:30.843Z
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
   간접 오염 경로이기 때문. `isa/truth_table_premigration.json` 은 블랙박스
   오라클로만 (명세로 읽으면 오염).
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
- 툴체인 고정 (`scripts/lint_toolchain_pins.py` 가 3곳 대조):
  JDK 21.0.12 · sbt 1.12.15 · Scala 2.13.12 · SpinalHDL 1.14.2 · sby `f57802a1`.
  ⚠️ 스냅샷의 `sbt` 는 **2.0.6 (런처)** 이고 `build.properties` 가 실제 버전을
  정한다. `scala`/`mill`/`coursier` 패키지는 스냅샷에 **없다**.
  SpinalHDL 은 **Scala 3 빌드가 없다**.
- `make rtl-gen / rtl-lint / rtl-formal / rtl-sim`. **Makefile 의 MOD 표는
  건드리지 말 것** — `lint_synth_coverage.py` 와 이중 잠금이라 즉시 FAIL 한다.
- 확정된 설계 결정 4건 (정본에 환류됨): 사상표 MMIO = 4 KiB 페이지 직접 배열
  (0x400/0x800, 256×4 B, 단일 워드라 원자성 자명) / 다중 조각 wave = **조각별
  슬롯** / 공유 유닛 점유 중 도착 = **대기** / 접근 승인 = **사후 게이팅**.

관련: [[prestable-compat-policy]], [[fp32-step-sequencer-terminology]],
[[wt64v1-precision-recovery-roadmap]] (참조 구현 현황).
