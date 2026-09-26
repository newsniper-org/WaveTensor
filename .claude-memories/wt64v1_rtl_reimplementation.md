---
name: wt64v1-rtl-reimplementation
description: WT64v1 RTL 전면 재구현 착수 (2026-08-20) — 정본은 아키텍처 가이드 PDF 하나, SpinalHDL 주 + SV 검증층, clean-room, 선-formal 우선
metadata: 
  node_type: memory
  type: project
  originSessionId: 4e29961e-988b-4f27-9ede-dfb9c81925bc
  modified: 2026-09-26T06:08:38.208Z
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
- **파도 C — Mask cocotb 골든 회귀: 해소**, commit `1666c7a`
  (2026-09-22). 하네스 결함(io_keyWr_part 미구동)이었고 RTL 은 옳았다 —
  [[mask-golden-sim-regression]]. 하네스가 파도 A 의 계약을 값 수준에서
  재는 지향 시험 둘을 얻었고 `boot()` 가 입력 포트 정의역을 기계로 대조한다.
- **파도 D — 재키잉 FINAL 엣지 동시 기입 모서리: 착지 완료**, commit
  `086fb27` (2026-09-22). 관측 결손(유효 하강만 있고 fault 침묵)을 정본
  §6.3 순서로 닫았다: `MaskEngine.tla`(엔진 창의 시간 축, Mask.tla 과
  분업) → `dirtyNow = compDirty || wrActNow` → `MaskUnit/engine.sby`(단독
  래퍼, 비트 수준 엔진 1 s, 변이 6종) + cocotb 오프셋 스윕. 세션 한도로
  워크플로가 한 번 끊겼고 `resumeFromRunId` 로 재개했다(끊긴 에이전트의
  산출물은 트리에 남아 있었다 — 재작성이 아니라 검증 모드로 프롬프트를
  고쳐 재개). HiuMask 합성 태스크의 cover 가 z3 로 step 45 에서 5시간
  웨지 → cover 엔진만 btormc 로(2 s) — [[solver-blindness-trap]].
- **파도 1 — 이월 묶음: 착지**, commit `db72dae` (2026-09-25). 증인 없는
  앵커 0(Reassembly W19~W21, 변이로 비공허 확인) · 부록 D 모델 수를
  lint_guide_derived_tables (8) 로 기계화 · GUARD-MAP 절 순서 · 낡은 좌표.
  사용자 지정 순서 1 → **2(Wt64Top 조립층 후-formal 태스크)** → 3(정본
  3.9 「내부만」 둘: 변환 항목 배열 0xC00 · flush 발화 0xE00). 세션 한도로
  에이전트가 자주 끊긴다 — 끊긴 에이전트의 산출물이 디스크에 남으니
  재작성 말고 상태부터 확인할 것.
- **파도 2 — Wt64Top 조립층 후-formal: 착지**, commit `e90d3f1` (2026-09-26).
  `rtl/formal/sby/Wt64Top/assembly.sby` — 하위 유닛 14개 절단(블랙박스 =
  과대근사), 83 단언·증인 25, 무결성 핀 여섯이 절단 정의역·assume 수 등을
  [script] 에서 고정. 한계는 .sby 머리 「보증하지 않는 것」 닫힌 목록(절단
  입력 핀 252 중 80 만 결박 — 데이터 경로 172 핀 미측정). 측정이 드러낸
  미결: **결함 D1**(0xF00–0xF07 ready=0 인데 rvalid) · **D2**(TAG1 [27:16]
  거절 미전파) · **정본 판정 요청 T1**(미배선 구역 쓰기 조용한 흡수 —
  0xE00 XLATE_FLUSH) · T2(비정렬 쓰기) · T3(0x000–0x11F). 다음 = 파도 3.
- **파도 3 — 변환 저장소 MMIO 문: 착지**, commit `bec0505` (2026-09-26).
  0xC00 항목 배열(LO 스테이징 · HI 단일 에지 커밋 · V=0 무효화) · 0xE00
  flush 발화 · 0xE10 해제 · RO 쓰기 거절. 선-formal `XlateSurface.tla`(가드
  17 · 42 run, 전량 429) 가 하류 거부 처분을 **기계로 판정** — reject/drop
  은 속성을 깨고 버스 정지만 통과. 새 컴포넌트 `XlateStaging.scala`, 최상위
  io.install/io.flush 은퇴. 렌즈가 잡은 것: xlatestore V 운반 오라클이 DUT
  자신의 commitLine_v 를 봐 공허(XS1 변이가 bmc/prove/cover 전부 통과) ·
  RTL 이 모델 없이 0xE10/RO 를 착지(§6.3 역순 — 모델로 되먹임). **판정
  요청 T5**: 스테이징 소진 미정 → flush 건넌 옛 LO 가 HI 한 워드로 재커밋,
  방어는 LO-먼저 호스트 규율뿐. 이월: wdata→ready 기능상 죽은 구조 경로 ·
  조립 그림자 하네스 독립 리뷰 · T1 잔여 · D1/D2 · run_wt64.py mkdtemp
  누수([[tmpfs-scratch-exhaustion]]).
- **파도 4 — 남은 과제 전수** (사용자 2026-09-26 「남은 것들도 전부 수행하도록.」
  — 정본 판정 포함으로 읽었다). 착지: `d65b1c2` 러너 mkdtemp 정리 · `cd61057`
  D2(TAG1 [27:16] 거절) + **AbortSurface.tla**(소거 스테이징의 §6.3 1단 결손 해소,
  가드 13 · 30 run) · `f229c8b` **spec 판정** — T1-i β(소비 없는 RW 워드 쓰기
  거절, CQ_BASE 포함) · T1-ii iv(판 0 = 물려받은 구간에 약속 없음) · T2 a(비정렬
  쓰기 = sub-word → [6]) · T3 d(0x000–0x11F 합의 전 처분: 쓰기 [6] · 읽기 0,
  3.10 새 규범) · T4 ii · T5 a(수락된 flush 가 래치 파티션 스테이징 유효를 내림)
  · E04 A(정지 게이트 스냅샷) · E.12.1 3항 명료화. 판정 갈래는 조사 3 + 판결
  검토 1 의 권고 채택(커밋 본문에 명시). `9ec42ee` RTL 착지 — MmioPage.tla ·
  XlateObs.tla 신설, XlateSurface 50 run, 배터리 518, PROVES 167, Shape 21; 조립
  하네스 독립 리뷰 완료(obs_read_pure 핀 미결박 적발). 단위 축은 /var/tmp 워크
  트리 수직 슬라이스 → 통합자 git apply --3way 가 통했다. ⚠ 재개된 워크플로
  에이전트가 대화의 사용자 질문(「현재 상황은?」)을 자기 과제로 오인해 보고만
  하고 멈춘 일이 있다 — 재개 프롬프트에 「상태 질의가 아니다 — 수행하라」를
  명시할 것. 남은 것: 태그 코덱 전파 파도(D2b · D2c).
  ⚠ 「Common.scala 편집 금지」는 **사용자 지시가 아니었다** — 병렬 파도의 파일
  소유권 규칙과 `when_Common_l259` 이름 핀(하네스 매크로 WT_STICKY_SET_FAULT)이
  섞여 굳은 것. 판결 검토자가 그것을 「막힘」으로 올렸다 — 제약의 출처를 먼저
  확인하라.
- **완료 게이트(파도 C 부터 확정)**: `make lint` · `make rtl-lint` ·
  rtl-gen 결정성 · `rtl/formal/tla/run.sh`(컨테이너) · 후-formal 관련
  태스크 재스윕 + `lint_postformal --require-fresh` stale 0 · **`make
  rtl-sim` 전 스위트** · 고아 컨테이너 0. 이월: `MaskUnit.scala` 머리의
  MaskEngine GUARD-MAP 블록 위치(Mask 절 꼬리 불릿 둘 사이에 끼어 있다 —
  줄 이동은 인용 27건 재조준 + HiuMask bmc 50분 재스윕이라 미룸) · cocotb
  의 수락 사이클(N=0) 같은-파티션 기입 점(후-formal W8 이 잰다) ·
  `lint_guide_derived_tables` 에 `.tla` 편수 ↔ 부록 D 「모델 수」 대조
  한 줄(지금은 기계 밖 — 문면에 분모를 적어 두었다).
