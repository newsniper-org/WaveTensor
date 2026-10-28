---
name: wt64v1-rtl-reimplementation
description: WT64v1 RTL 전면 재구현 착수 (2026-08-20) — 정본은 아키텍처 가이드 PDF 하나, SpinalHDL 주 + SV 검증층, clean-room, 선-formal 우선
metadata: 
  node_type: memory
  type: project
  originSessionId: 4e29961e-988b-4f27-9ede-dfb9c81925bc
  modified: 2026-10-11T10:31:02.976Z
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
  명시할 것.
- **파도 5 — 태그 코덱 전파: 착지**, commit `87b34cf` (2026-09-27). Types.Tag 를
  E.5.1 배치(70b, 예약 구조 제외)로 · 매칭 키는 poison/trace 제외(D2b) · CD_TAG1
  poison 장치 저작 0 · 예약 0(D2c). Payload.tla 정제, 배터리 524. Reassembly bmc
  는 abc bmc3 (z3 는 ctx≠0 변이를 못 잡았다). 이월: poison 전파 원천 · 사이드밴드
  엄격 거절(E.5.4 소비처 미배선) · ISA json 에 ACCTGT 없음(소거 E2E 시험 불가).
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

**§3.10 v1.0 묶음 (Y4 협상, 2026-10-09)** — 양측 사용자 결정으로 입장 확정 (WT 답
`.local-replies-to/Y4/2026-10-09-reply-s310.md` · Y4 r2 · WT r2-ack). 정본 spec 커밋
`6a25359` (형상 비노출 `0xC00` · `0xE14` (A, D)=APPLIED/DRAINED · `0xFF8` · `0xEC4` ·
판정 래치 신설 · E.1.1 호스트 해석 규범 · reset 값 규범 · 판의 뜻). Y4 대조 답이 정정을
요청해 정정 커밋 `8af46df` (FAULT_STATUS `[19]` 비소유 프레임 접근 신설 — `[4]` 는 자격 거부로
좁힘, 자격이 먼저 · 배정 `[0]`–`[19]` · 예약 `[31:20]` · 겹치는 슬롯 구간은 v1.0 판정 안 함(수락,
호스트 의무) · (a) 래치 한정 · minor (e) VA 조건 · `[12]` 「재키잉이 시작된」). 줄 수를 보존해
인용 재조준 0. Y4 는 `8af46df` 를 이견 없이 수용(Y4 `754c610`). 착수 정찰이 찾은 명확화 둘(S-3 `[12]`·`0xEC4`
비트맵 정의역 = 마스크 유효한 *다른* 파티션 · S-2 `0xE14` sub-word 쓰기는 A·D 불변)과 사실 정정 F-1(HIU-4
「증명됨」 → 미착수 — 인용 불변식 `Inv_AtMostOneCandidate` 가 항진)을 spec 커밋 `b81df18` 로 냈다(Y4 대조 대기,
`2026-10-11-spec-b81df18.md`). **RTL 파도 착수 2026-10-11**: W0(낡은 증거 7 재스윕) `3b80087` → W1([19] · 0xFF8 ·
0xEC4 · [11]/[12]) → W2(판정 래치) → W3(형상 비노출 문 · HIU-4 진짜 증명) → W4(0xE14 · DP-4 α) → W5 Y4 착지 통지.
작업 지시서 · 보고서는 `/var/tmp/wt-s310/`. **W1 착지 `9b6eee6` (2026-10-12)** — 선-formal 554 run · hiumask/engine/assembly 재스윕 · cocotb 36 · 전수 postformal 23 PASS; DP-17 로 B.5 「비소유 loud」 해소(3.9 *부분* · HIU-5/6 *부분 증명*); 덮임 판정 기준 = 가드의 GUARD-MAP RTL 범위를 앵커 태스크가 전부 재는가(범위가 절단 조립에 걸치면 `_PARTIAL`). 파도에 더함:
permViol 가르기 · N_BITS 20 · FLT_CLEAR_RSV · Wt64Top_props/HiuMask_props/assembly.sby 의 `[4]`·`[31:19]`
자리. **W2 착지 `aa91e86` (2026-10-13)** — 판정 래치(HiuPipeline 끝 `lat` Area) · XlateObs 22→41 run(배터리 573) · hiumask assert 57/cover 37 · cocotb 38 · postformal 23 PASS; 3.9 판정 래치 *구현*(미측정 둘: (h) RTL → W3 `evict_on_commit_only` · 점유 단언 없음). 이월: HIU-3 정적 검사 본체 · reset 형식 단언. 교훈: 서브에이전트가 주간 한도로 편집 도중 죽으면 작업 트리에 부분 편집이 남는다 — 재개 프롬프트에 「처음부터 말고 git diff 를 결정과 대조해 이어라」를 넣어야 한다. **W3 착지 `f67e3d6` (2026-10-13)** — 새 0xC00 문(XlateStaging 재작성 · needReady 주소/상태만 · 데이터 사유 sticky xlateCfgBadWrite) · XlateSurface 50→77(배터리 600) · XlateStore 항진 삭제(DP-12 사용자 확정) · door.sby 신설(정지 유계 무계 · 표 축 bmc16 유계) · cocotb 49 · postformal 24 PASS. **W4 착지 `e88f6f4` (2026-10-15, 사용자 「W4 시작해」)** — ActivePart(0xE14 결속 · α 판정 · 거절은 원천별 sticky actCfgBadWrite) · hiuReq.part 은퇴 · ActivePart.tla(20편 · 배터리 644) · activepart/occ.sby 신설 · cocotb 56 · postformal 26 PASS. β 는 거짓 [6] 모서리 반례 → S-1 · S-2 불필요. **W5 통지 2026-10-16** `.local-replies-to/Y4/2026-10-16-rtl-wave-landed.md` — 동결 sha `e88f6f4` 제안 · Y4 대조 · S-2 귀결 확인 · r2 §4-5 모양 수용 · v1.0 frozen · 양측 sign-off 를 청함; Y4 답 대기 → 그 뒤 `0xFFC` = `0x0001_0000` 별도 커밋. **동결 전 대조 (2026-10-16)** — Y4 rc1 `e8b5844` 대조에서 major 1(창 기준선 `[6]` 만으로는 `[5]` · `[15]` 거절을 놓침) → Y4 rc2 `47668e8`(W = [5][6][7][15]) + 물음 D1(`[7]` OWN_SET 거절 원천) · D2(`[15]` 원천 — RTL `[15:14]` 거절이 정본 「예약 비트 없음」과 충돌)를 sign-off 차단으로 걸었다. 둘 다 정본 공백이었다. 사용자 결정 → **spec `f6bc4df`**: E.7 6·7항(형상 중립 OWN_SET 거절 · 장치 포트 읽기 순서) · E.1.1 5항(되읽기 전 장치 소유로 셈하지 않음) · 3.5 척추에 이름 붙인 예외(소유권 표 용량 비용) · `[15]` 원천 닫힌 넷 · step 워드/열쇠 배치 3.10 동결 · `0xF0C` FP_SHAPE(판 워드와 함께만 비0) · 비0 판 커밋은 FP_SHAPE 배선과 함께이거나 그 뒤. 통지 `.local-replies-to/Y4/2026-10-16-reply-rc2-d1d2-spec-f6bc4df.md` — Y4 rc3 대기. 남은 순서: rc3 대조 → WT sign-off(history 보존 서면 확인은 사용자 확인 필요) → FP_SHAPE 배선 + `[7]` 상승 건전성 단언 RTL 파도 → 판 값 커밋. 교훈: 수정자의 수정은 늘 새 결함을 낳았다(검토 다섯 바퀴 18→11→5→4→2) — 수정 뒤 재검토 없이 커밋하지 마라. **W6 착지 `efafb14` (2026-10-19, 사용자 「지금 착수해」)** — 0xF0C FP_SHAPE 배선(판 0 동안 읽기 0 · 쓰기 [6] · 판 근원 Ident.PRE_AGREEMENT 하나 · 판 게이트만 1 로 바꾼 변형에서 0x0100_400A 한 번 측정) · Platform.tla OWN_SET 거절 확장(가드 8→14 · 배터리 657) · ownershiptable [7] 세움 건전성 s_col_src/slot/floor + s_rd_snap(prove smtbmc z3 k-귀납 · bmc 는 abc bmc3 + aigsmt z3) · cocotb 58 · _PARTIAL 47. **판 값 커밋의 배선 전제는 풀렸다** — 남은 것은 Y4 rc3 대조 → 양측 sign-off → 0x0001_0000 커밋(바꿀 곳: PRE_AGREEMENT 근원 · 하네스 판 토큰 · pageArea require/읽기 경로). 주간 한도로 워크플로가 세 번 끊겼고 resumeFromRunId + 역할별 progress.md 로 매번 이어졌다. 세움 건전성 교훈은 [[sticky_set_soundness]]. **동결 후보 spec `b16fc07` (2026-10-20, 정본 트리 2dd78f80)** — Y4 rc3 `ff72bb0`(C1·C2 sign-off 차단) 답: C2 `0xF08[1]` 읽기 순서(Y4 문안의 강화판 + 유계 정지 허락) · C3 3.6.2 · C4 플랫폼 지정 이미지 · C5 걷기 순서 동결(→ (4) 는 기계적 내용 검사로 막힘) · C6 거절 배타성·후보 칸 고정 · C7 · C11 v1.x. 사용자가 C1 서면 확인 허락 — **`b16fc07` 까지 history 를 다시 쓰지 않는다**(rebase·amend·force push 금지), 동결 뒤 판 값 커밋까지는 정본 사실 행만 · 바꿀 때마다 Y4 에 diff 통지. 통지 `.local-replies-to/Y4/2026-10-20-reply-rc3-freeze-b16fc07.md` — Y4 rc4 대기 → WT sign-off → Y4 v1.0 frozen → 측정 파도(C2 최상위 단언 · [7] 최상위 합성 · 판 값 날 0x0100_400A 상주) → 0x0001_0000 커밋. 이월 사실 커밋: C10 B.5 v1.x 등재 · C13 낡은 RTL 주석. → 둘 다 착지(2026-10-20): `395e5b1` B.5 v1.x 등재(b-gaps 1410·2105·2118·2126, 줄·계수 불변) · `22c76bb` RTL 주석(생성물 불변); Y4 통지 `.local-replies-to/Y4/2026-10-20-notice-post-freeze-facts-395e5b1-22c76bb.md`. 남은 주석: StepSequencer 머리 주석의 「잠정 결정」 문면(3.10 이 배치 동결 — W8 판 값 커밋 파도 몫). **WT sign-off 송부 (2026-10-22)** `.local-replies-to/Y4/2026-10-22-signoff-v1.0-b16fc07-783b119.md` — Y4 rc4 `783b119`(조건부 Y4 sign-off 문안 · hiu_abi §5.4) 대조 major 0, minor 7 은 수정 요구 아닌 알림. 사용자 결정: history 는 `b16fc07`→판 값 커밋까지 main fast-forward 만 · 통지 sha 전부 도달 가능 / **push 는 판 값 커밋 전에 하되 시점은 그때 다시 지시받는다** / C9 는 v1.x 로 받되 v1.0 격리 결함이면 재서명 경로. 판 값 커밋 이행 방식: 장치 변화는 0xFFC·FP_SHAPE 값 둘 · 한 상수에서 데이터 경로로 · 상주 단언은 MMIO 응답 + 하네스 독립 리터럴 + 판 0 변형. 그때 함께 고칠 것: Wt64Top.scala:435·1911-1912·1999 주석과 3.9 :1556 「같은 근원」 과장, StepSequencer.scala:105-107 주석. 다음: Y4 v1.0 frozen 표지 sha 대기 → 측정 파도(C2 최상위 · [7] 0xF80 합성 · OWN_STATUS 조립 통과) → push(지시) → 0x0001_0000 커밋. **양측 sign-off 발효 (2026-10-22)** — Y4 sign-off 발효 · `hiu_abi.md` v1.0 frozen 표지 `3ba1e58`(규범 = `783b119`) · Y4 동결 뒤 사실 정정 1 `5d092cc`(a1–a6). §3.10 v1.0 은 **동결**: WaveTensor 정본 `b16fc07`(트리 2dd78f80) + Y4 `783b119`. 남은 것: 측정 파도 → push(지시) → 판 값 커밋(통지에 Wt64Top.scala:435·1911-1912·1999 와 3.9 :1556 정정 줄 포함). **W7 측정 파도 착지 `ea62f89` (2026-10-26, 사용자 「시작해.」 2026-10-23)** — 하네스 · 사실만(RTL 불변 · 생성물 2d93ad7b · 0xFFC 0): `Wt64Top/fporder.sby`(fps 비절단 — C2 첫 절 a_ord_done k-귀납 무계 · 둘째 절 a_ord_sel/a_ord_cap 「소거 완료 직후」 가정 bmc d16 유계, 무계는 막힘) · `Wt64Top/ownasm.sby`(own 비절단 — t7_rst/src/slot/cmp/hold/rd + o_rd, abc pdr 무계 → set_reject_loud · seven_reject_only 완전 덮임, _MAX_PARTIAL 47→45) · walk_decode prove 한도 1800→3600. 정본 3.9 `03-hiu.typ:1537` · `:1556` 두 셀만(사실), 정본 트리 `443cbfeb2da230b9c728dec7244c7d9f2337e0c5`. 검증 8회 · 착지 검토 3회. 이월(핀된 문면 — W8 판 값 커밋 파도 몫): Wt64TopOwn_props.sv · ownasm.sby 머리의 「t7_src 가 함의」→ t7_src·t7_slot, ownershiptable.sby · assembly.sby PROVES 의 「합성은 서술」 낡음. 교훈: ① 수정 에이전트가 자기가 띄운 전수 게이트(~3h)를 기다리지 않고 「Waiting」으로 돌아와 검증 두 회가 헛돌았다 — 지시서에 「MAKE_RC 까지 Monitor 로 기다려 보고」를 넣을 것. ② nvme btrfs 메타데이터 포화로 게이트가 SIGBUS·21 FAIL 로 위장([[btrfs-metadata-enospc]]). ③ 검증자는 매 회 새 증인 결함을 찾았다(r+1 틈 → 유지 단언 → reset 탈출 → 증인 칸 → 증인 예외 항 경유) — 증인은 「닿는다」가 아니라 「검사 항으로 닿는다」여야 한다. Y4 통지 `.local-replies-to/Y4/2026-10-26-notice-post-freeze-facts-W7-ea62f89.md` → Y4 대조 답 `2026-10-26-notice-ea62f89-crosscheck-fact-correction-2.md`(이견 0 · Y4 `041cdb4` 사실 정정 2 · `b16fc07` 주석 태그 권고). **push 완료 2026-10-26** (사용자 「push해.」) — 원격 main `09a33ce..1500438`, 통지 `.local-replies-to/Y4/2026-10-26-notice-push-1500438.md`; 주석 태그 `wt64v1-s3.10-v1.0-frozen`(객체 abb0f767 → b16fc07, 사용자 지시) 원격에 올림. **W8 판 값 커밋 파도 착수 2026-10-26** — 지시서 `/var/tmp/wt-s310/W8-brief.md` · 워크플로 wf_badf7fcf-8c5(스크립트 사본 `/var/tmp/wt-s310/w8-resume. **W8 판 값 커밋 착지 `40de875` (2026-10-26)** — `Ident.VERSION = 0x0001_0000` 한 상수 → `abiArea.ver` 넷에서 `0xFFC` 읽기와 FP_SHAPE 판 게이트(`0x0100_400A`)가 데이터 경로로 나온다(옛 require 묶음 제거); 생성물 `Wt64Top.sv` +15/−1 · 포트 불변 · 다른 생성물 19 동일. 상주: assembly `a_rd_abi` · 쌍조건 `a_pair_sh`/`a_pair_abi` + 판 0 변형 `Wt64Top/abi0.sby`(sed 한 줄 치환 · 핀) + cocotb `ShapeAbi0`; 별도 리터럴 변이는 판 0 변형에서만 잡힌다. 정본 사실 6 hunk(3.9 `:1556` · `:1566` · `:1581`, E.1.3 `:723` · `:737-738`, B.5 `:1410`) — `0xFFC` 행 *부분*→*구현*/E.1.3 물러남, 정본 트리 `1e2803a51c25ea73e19fea4ee85bbafc794ccb97`. 게이트 W8F2 한 번 29/0/0/0 · sim 62/62. 메모리 거울은 별도 커밋 `a9e4d94`(pre-commit 훅이 거울을 자동으로 넣으므로 거울 커밋을 먼저). 검증 5회 수렴. 교훈: 수정 에이전트는 지시서에 적어도 여전히 게이트를 안 기다리고 돌아온다(F2) — 오케스트레이터가 게이트 로그를 직접 감시하고 다음 검증을 늦춰 띄운다. Y4 판 값 통지 `.local-replies-to/Y4/2026-10-26-notice-version-commit-40de875.md`(사실 검증 4회 수렴) · 메모리 거울 `81d670a` · **push 2026-10-27** 원격 main `1500438..81d670a`(통지에 덧붙임). Y4 판 값 대조 답 `2026-10-27-reply-version-commit-40de875.md`(수용 · 조건 4 충족 · Y4 `619ff73`) → 체제 연장 수락(사실 체제 · 통지 꼴 · fast-forward 를 v1.0 정본 변경 동안 유지) → **W9 사실 정정 `5116e1e` (2026-10-28)**(Y4 §3 · §4 — 정본 4 치환 · 트리 `3491d68f…` · 생성물 동일 · 메모리 거울 `8e994f6` 별도) · 통지 `2026-10-28-notice-post-freeze-facts-5116e1e.md` · 사용자가 직접 push(원격 main `5116e1e`). 통지 규칙(Y4 요청): 정본 변경마다 추가/치환을 가르고 줄별 규범 경계를 적는다 · 행 이동은 「상태 칸 변경 · 근거 규범 줄」. **열린 물음:** `.local-requests-to/Y4/2026-10-28-stale-pending-texts-boundary.md` — 동결 뒤 남은 「sign-off 대기 · 합의 대기」 11 줄(사실 칸 5 · 근거 2 · 규범 블록 4)의 경계, Y4 답 전엔 손대지 않는다(사용자 결정). 다음 사실 커밋 후보: run_wt64.py:185 · assembly.sby:256 판 0 동일성 한정. 남은 것: Y4 의 RTL diff · 장치 값 대조 → 실장치 결속(Y4 몫) · C9 SEC-4 분석 · 3.9 step 적재 행(선택).js`). 다음: 0x0001_0000 판 값 커밋(통지에 Wt64Top.scala:435·1911-1912·1999 · StepSequencer.scala:105-107 · 3.9 :1556 「같은 근원」 · 「판 0 한정」 포함) · 이월: rtl/README.md:2357 의 원문과 다른 인용. 교훈: 배터리 뒤 .tla 주석을 고치면 그 절만 재실행해 sha 와 함께 기록. 워크플로 스크립트 템플릿 문자열 안의 백틱은 스크립트를 깨뜨린다(검토 에이전트가 통째로 빠짐). W5 통지 메모 `/var/tmp/wt-s310/W5-notes-from-W3.md`. 다음: 이견 없으면 RTL 파도(형상 비노출 문 · ACTIVE_PART ·
HIU_SHAPE · 0xEC4 · d-i 래치 + HiuMask_props/GUARD-MAP · XlateObs 확장(같은 파티션 축출) ·
정지 유계 단언 xlatestore+assembly · `[11]`/`[12]` 발화 단언 engine.sby · 3.9 상태 낱말 ·
부록 D 수), `0xFFC` 는 0 유지 → Y4 v1.0 frozen + sign-off → `0x0001_0000` 별도 커밋.
교훈: 합의 문면을 원장으로 접을 때 「구성 교체」 목록에 `0xC00` 항목 기입을 잘못 넣었다 —
645bed0 목록(사상표·flush·소유권)과 대조하지 않은 탓, 규범 충돌 검증자가 잡았다.
