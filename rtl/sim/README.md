<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# `rtl/sim/` — 재구현 트리의 런타임 하네스

자립형 cocotb 러너 하나(`run_wt64.py`)와 하네스 둘. `make rtl-sim` 이
진입점이다.

**이 문서의 목적은 무엇을 쟀는지가 아니라 무엇을 재지 *못했는지*를 남기는
것이다.** 이 저장소가 반복해 밟은 형태가 「하네스가 있다」를 「그 축을
잰다」로 읽는 것이고, 미측정 축을 이름으로 열거하지 않으면 그 오독이
기본값이 된다 (정본 §6.7 원칙 5 — 미측정은 통과가 아니다).

---

## 실행

```
make rtl-sim                              # 전 스위트
make rtl-sim SIM_SUITES="Mask"            # 좁혀 돌기
make rtl-sim WT_SIM_BUILD=/tmp/wtsim      # 빌드 자리 고정 (기본은 mkdtemp)
WT_SIM_KEEP=1 make rtl-sim                # 통과해도 mkdtemp 루트를 남긴다
```

`python3 rtl/sim/run_wt64.py` 로 **직접 부르지 마라.** 이 저장소의 cocotb 는
시스템 python 이 아니라 전용 venv 에 있다. Makefile 이
`cocotb-config --python-bin` 에게 인터프리터를 묻는 이유가 그것이고,
러너의 `main()` 도 그 오독을 선제 차단한다 (「도구를 못 찾음」이
「측정했는데 실패」로 읽히는 것을 막는다).

빌드 산출물은 **저장소 안에 만들지 않는다.** `WT_SIM_BUILD` 를 주지 않으면
`tempfile.mkdtemp()` 다. 저장소 안에 `sim_build/` 를 만들면
`scripts/lint_forbidden_terms.py` 의 SKIP_DIRS 가 그것을 건너뛰므로,
검사받지 않는 구역을 새로 만드는 셈이 된다.

mkdtemp 루트는 **통과한 실행이 스스로 지운다** — 실패한 실행은 조사하라고
남기고 그 자리를 인쇄한다. 남기던 시절 `/tmp`(tmpfs)에 루트가 개당 ~230M 씩
쌓여 게이트를 돌리던 검토자가 ENOSPC 로 죽었다 (2026-09-26). `WT_SIM_BUILD`
로 준 자리는 호출자의 것이라 러너가 지우지 않는다.

### 도구 (실측)

| 축 | 값 |
|---|---|
| cocotb | 2.0.1 (`cocotb-config --version`) |
| python | 3.13 (pipx venv) — 시스템 python 은 3.14 이고 `cocotb_tools` 가 없다 |
| Verilator | 5.048 |

`iverilog` 는 호스트에 없다 (컨테이너에만). 지금 하네스는 Verilator 전용이다.

---

## 실행 결과 (2026-09-26, 호스트)

```
Mask:  11 tests passed (skip 0, 하한 11)
Shape: 21 tests passed (skip 0, 하한 21)
run_wt64: 요청 스위트 2건 / cocotb 테스트 32건 전부 통과
```

(2026-09-26 파도 4 — Shape 15 → 16 `abort_tag1_word_legality` · 통합 착지 16 → 21: 페이지 통합 `page_disposition` · `fp_clear_window` ·
3B `xlate_miss_observed` · `xlate_miss_obs_second_stall` · 3A `xlate_other_flush_keeps_staging` (`xlate_hi_releases_stall` 은 제자리에서 `xlate_flush_ends_staging`).
2026-09-26 파도 3 — 변환 저장소의 MMIO 문: Shape 6 → 13, 지향 시험 일곱
`xlate_*`, 같은 날 반증 검토 뒤 수리로 13 → 15 — 인접 HI 의 D-2 버스 정지 값 시험 둘.
직전 기준선 2026-09-22: Mask 11 · Shape 6 · 총 17.
그 앞 기준선 2026-08-28: Mask 8 · Shape 6 · 총 14. 2026-09-22 에 Mask 가
8 → 10 — 임대별 키 파도의 값 수준 지향 시험 둘 — 그리고 같은 날 파도 D 에서
10 → 11 — FINAL 엣지 같은-파티션 동시 기입 지향 시험
`wr_same_partition_at_final_edge_is_loud`. 그 사이 2026-09-20 RTL
`ca3c496` 이 Mask 스위트를 **2/8 FAIL** 로 깨뜨린 채 커밋됐다 — 아래
「함정 ⑥」.)

핵심 수치:

| 측정 | 값 | 어디서 |
|---|---|---|
| SEC-1 golden 정확 비교 | **80/80 라인** (pinned 8 · rand 32 · edge 8 · nonce_tail 16 · key_word 16) | `sec1_golden_exact` |
| 사영 뒤 서로 다른 `maskFrame` | **73/80** | 같음 |
| 사영 뒤 서로 다른 자극점 | **79/80** | 같음 |
| 재키잉 지연 | 수락 엣지 **포함** 43사이클 / **제외** 42엣지 / `io_busy` 상승 41사이클 | `fixed_latency_path_invariant` |
| `faultNonceDup` 등가 대조 (golden 루프 안) | **80/80 라인** — 기대 1 이 17라인 (pinned 1–7 · edge 42–43 · key_word 쌍 뒤 줄 65…79), 나머지 63은 기대 0 | `sec1_golden_exact` |
| 임대별 키 범위 — 값 수준 | part 1/2 각자 golden → part 1 키만 갈아 `maskReady` 정확히 `0b0100` · part 2 값 불변 → 재키잉 뒤 `0b0110` · 값 셋 golden | `key_scope_cross_partition_value` |
| 계산 중 **다른** 파티션 기입 | `maskReady == 0b0001` · `faultWrDuringRekey == 0` · part 0 값 golden | `wr_other_partition_during_rekey_is_clean` |
| 변이 실측 (사본 worktree, 생성 SV 한 자리씩 — M2 만 case 블록 24줄) | **4/4 잡힘** — 아래 표 | Mask 스위트 전체 |
| 구성 표면 소거 구간 | **65535 엣지** | `cfg_surface_integrity` |
| ISA-1 대조면 | **119/121** 출력 (제외: `io_push_1_stall`·`io_push_2_stall`) | `compare_face_is_pinned` |
| IO fault 해제선 | 19 (fault 출력 23 − MMIO 전용 4) | 같음 |

---

## 스위트

### `Mask` — `test_mask_golden.py` (DUT `MaskUnit.sv`)

SEC-1 주소 마스킹의 golden 정확 대조. 대조식은 한 줄로 닫힌다:

```
io_rsp_frame  ==  io_req_frame ^ (mask64 >> 12) & 0xFFFFFFFF
```

`mask64[43:12]` 는 E.9 3항의 적용 슬라이스이고 (`PA_W=44` · `PAGE_W=12` ·
`FRAME_W=32`, `XlateStore.scala:60-70`), RTL 은 64비트 마스크를 레지스터에
두지 않고 그 32비트만 상수 분해로 만든다 (`MaskUnit.scala:443-483` 「is(PH_FINAL) {」
이하, 생성물 `MaskUnit.sv:304-307` 「st_1[11 : 0] + 12'h46e」 에서 상수 셋 대조 확인).

**`!=`·popcount·통계형 확산 검사가 한 곳도 없다.** 정본 §5.2.4 가 이름한
「확산은 세어서 확인할 수 없다 — **틀린 값도 다르다**」의 수신인이 이
파일이고 (`MaskUnit.scala:125-130` 「확산 검사는 구현하지 않는다」 가 명시한다), 있는 것은 golden 값과의
등가 비교 하나뿐이다. `nonce_tail`·`key_word` 가족의 「검출기」 성격은
*그 벡터가 폐기 알고리즘을 골라내도록 golden 이 구성됐다*는 뜻이지
하네스가 통계를 잰다는 뜻이 아니다.

fault 는 `io_fault*` **실포트로만** 관측한다 — 시뮬 전용 단언으로 fault 를
구현하면 합성 결과물에 그 검사가 없다.

**키·논스 저장은 임대(파티션)마다 다르다** (정본 「키의 범위 — 임대마다
다르다」, RTL `ca3c496`). 하네스의 전제는 넷 — 키 기입 포트에 `io_keyWr_part`
가 있고 워드는 그 파티션에 앉는다 · 키 기입은 **그 파티션의** `maskValid`
만 떨어뜨린다 · REKEY 는 그 파티션의 키를 읽는다 · `compDirty` 는 기입
파티션이 계산 중 파티션(또는 이번 REKEY 대상)일 때만 선다. 제어면은 후-formal
`HiuMask` 가 증명했고, 여기서는 그 결과가 **golden 값**으로 나타나는지를
지향 시험 둘로 잰다 (`key_scope_cross_partition_value` ·
`wr_other_partition_during_rekey_is_clean`). golden 루프는 `i % 4` 로 파티션을
골고루 돌며 매 라인 `faultNonceDup` 도 하네스 쪽 모델(유효 파티션 → 논스)과
**등가**로 대조한다 — 기대 1 이면 해제하고 다음 라인으로 간다. 옛 계약(키
전역 1벌)에서는 이 축이 루프에서 공허하게 거짓이었고, 지금은 17라인에서
실제로 선다.

변이 실측 (2026-09-22 — `git worktree` 사본의 `rtl/generated/MaskUnit.sv`
에 한 자리씩 넣고(M2 만 case 블록 24줄) `make rtl-sim SIM_SUITES=Mask`; 저장소 생성물은 손대지 않았다):

| 변이 | 무엇을 깨는가 | 죽는 시험 |
|---|---|---|
| M1 | 키 기입이 part 를 무시하고 항상 파티션 0 에 쓴다 | `sec1_golden_exact` (라인 1, part=1) · `en_is_the_single_stall_source` · `key_scope_cross_partition_value` |
| M2 | REKEY 가 항상 파티션 0 의 키를 읽는다 | `sec1_golden_exact` (라인 9, rand part=1 — pinned 8줄은 키가 같아 part 0 의 키로도 golden 이 맞는다; 그것이 원장 5번의 자극 축소다) · `en_is_the_single_stall_source` · `key_scope_cross_partition_value` |
| M3 | 키 기입이 **전** 파티션의 `maskValid` 를 내린다 | `sec1_golden_exact` (라인 1 — `faultNonceDup` 기대 1 인데 0: 전건이던 part 0 이 무효화됐다) · `key_scope_cross_partition_value` (part 2 install 뒤 `maskReady` 0b0100 ≠ 0b0110 — part 2 의 키 기입이 part 1 을 무효화했다) |
| M4 | 키 기입이 파티션과 무관하게 가동 중이면 `compDirty` 를 세운다 | `wr_other_partition_during_rekey_is_clean` (`maskReady` 0b0000 ≠ 0b0001) — **이 시험만** 문다; 나머지 아홉은 M4 에 침묵한다 |

M4 가 말하는 것: 기존 아홉은 「다른 파티션 기입은 사정권 밖」을 한 번도 재지
않았다. 지향 시험 하나가 그 축의 유일한 그물이다.

**FINAL 엣지의 같은-파티션 동시 기입** (파도 D, 2026-09-22) — 수락 엣지 기준
오프셋 40·41·42·43·44 의 활성 파티션 키 기입(+ 논스 idx 5 · 예약 idx 6 음성
대조)을 케이스마다 새 재키잉으로 재고 `io_faultWrDuringRekey == busy_seen`
(기입 **직전** `io_busy` 표본)을 등가로 단언한다 —
`wr_same_partition_at_final_edge_is_loud`. 「재키잉 중」의 정의역은 장치
자신의 관측 busy=1 이고 FAULT_STATUS `[13]` 에 시점 예외가 없다(정본 E.1.2
표 · E.9). 파도 D 이전 판(1666c7a)은 N=42(FINAL 사이클)에서 유효만
떨어뜨리고 fault 가 침묵했다 — 음성 실측 (2026-09-22, `git worktree` 사본
`1666c7a` 의 생성물 `rtl/generated/MaskUnit.sv` 에 이 하네스를 그대로 돌림):
`wr_same_partition_at_final_edge_is_loud` **만** 죽고(`[key N=42]
io_faultWrDuringRekey=0 ≠ busy_seen=1` — N=40·41 은 통과한 뒤) 나머지 열은
통과, 10/11. 파도 D 의 생성물에서는 11/11 이고 표는
`[(40,1),(41,1),(42,1),(43,0),(44,0)]`. RTL 의 수리는 FINAL 가지가
같은 사이클 항 `wrActNow` 를 직접 보는 것 하나다
(`MaskUnit.scala:473` 「val dirtyNow = compDirty || wrActNow」); 같은 모서리의
후-formal 은 `rtl/formal/sby/MaskUnit/engine.sby` (D3) 다. 같은 시험이 N=42 에
**타 파티션** 키 기입도 재서 같은-사이클 항이 활성 파티션 한정임을 등가로
단언한다 — `(busy_seen, fault, maskReady[p], maskReady[q]) == (1, 0, 1, 0)` +
p 의 값 golden. 변이 실측 mutScope(사본 생성물에서 `wrActNow` 의 파티션 비교를
뗌): 이 케이스 하나만 죽고 나머지 전부 통과 — 그 케이스가 없던 동안 그 축은
오라클에 점이 없었다(RTL 반증 검토가 찾아 파도 안에서 닫았다).

### `Shape` — `test_shape_equiv.py` (DUT `Wt64Top.sv`)

ISA-2 사상 경유(존재 축) · ISA-1 자리 무관성 · 구성 표면 무결성 ·
변환 저장소의 MMIO 문(파도 3 — `xlate_*` 아홉: 설치 → 적중 · flush → 같은 VPN
미적중 · HI 한 워드가 정지를 푼다 · V=0 무효화 · HI 거절 둘의 `[6]` · flush 거절과
절단 별칭 부재 · `0xE10` 은 정지를 풀지 않는다 · 그리고 반증 검토 뒤 더한 인접 HI 둘 —
쉬는 사이클 없는 원시 구동 `mmio_burst` 로 D-2 버스 정지가 정확히 한 사이클이고 `[6]` 이
서지 않으며 풀린 기입이 커밋됨(tagB 적중 · V=0 무효화 생존)을 값으로 잰다. 착지판 일곱은
기입마다 쉬는 엣지를 남겨 정지를 한 번도 만들지 않았고, ready 덮어쓰기를 끊은 생성물
변이를 7/7 로 통과시켰다). 미적중 판정(`assert_miss`)은 ready 표본열 등식이다 — 착지판의
`stalled >= 8` 하한은 정지가 새는 변이를 통과시켰다. 기입은 호스트 ABI 오프셋이고 조회는
내부 포트 `io.hiuReq` 다 — 정지 *중*의 `0xE10` 해제가 미적중 sticky 를 내리지 못한다는
것(set 이 정지 레벨이고 발화가 해제를 이긴다)은 이 스위트가 처음 드러낸 사실이다.
파도 4 페이지 통합 — `page_disposition`(물려받은 구간 · 명령 링 표 워드 · CQ_BASE · `0xFFC` 쓰기의 `[6]` 과
되읽기 0 · 비정렬 쓰기 `[6]` · 예약 정렬 오프셋 무-fault) · `fp_clear_window`(선택자 표 소거 창 *안*에서 읽기는
기다리지 않고 응답 정확히 1회 · FP_BIND 예약 거절은 수락 뒤에만 `fpCfgBadWrite` · 비정렬 쓰기는 정지 없이 `[6]`).

판정은 언제나 **예측 벡터와의 바이트 동일성**이다. ISA-2 를
`F(σ(S)) != F(S)` 로 쓰지 않는다 — 그것이 정본이 이름한 「틀린 값도
다르다」 그 자체다. `F(σ(S)) == predict(σ(S))` 정확 비교가 판정이고,
`!=` 는 「σ 가 관측 가능한가」의 부수 확인으로만 쓰이며 그 사실이 코드에
적혀 있다.

---

## ⛔ 이 하네스의 층위 — 호스트 ABI 가 아니다

**투입 방향(호스트 명령 큐 / E.5 명령 링)은 RTL 에 미착지다.**

| 근거 | 파일:라인 |
|---|---|
| 일의 유일한 원천이 `io.instr` 외부 제시 | `Wt64Top.scala:913` 「walk.io.iValid      := io.instr.valid」 |
| `io_instr_valid` 는 있고 **`io_instr_ready` 가 없다** | `rtl/generated/Wt64Top.sv:13-31` |
| `R_SQ`(0x380–0x3FF) = 「명령 방향 실물 0건」 | `Wt64Top.scala:1180` 「private val selSq    = sel(R_SQ)」 |
| `CompletionUnit` 은 스스로 **완료 방향** 표면 셋이라 적는다 | `host/CompletionUnit.scala:1-27` |

⇒ **이 하네스에서 호스트는 하네스 자신이고, 설계 내부 포트 `io.instr` 를
직접 때린다.** 그러므로 여기서 확인된 ISA-1/ISA-2 는

> 호스트 ABI 층위의 등가가 아니라 **디코드 진입 층위의 등가**다.

이 문장을 지우지 마라.

---

## 미측정 원장 — 11축

`make rtl-sim` 이 통과 계수와 **같은 자리에** 이 원장을 인쇄한다. 착지하면
그 항이 사라진다.

| # | 재지 못하는 것 | 근거 |
|---|---|---|
| 1 | 투입 방향 일체 — 링 head/tail · 가득 참 · E.5 3항 loud fault · 배압 정지 · 크레딧 | 회로 0건 (위 표) |
| 2 | **ISA-1 두-형상 대조 (nPoints 4 ↔ 2)** | 형상 B 생성기 부재 — 아래 별항 |
| 3 | ISA-2 **자리 축** (LNID 소유 지점 `[23:16]` · LBID 슬롯 구간 `[15:0]` 순열) | 관측면 부재 — `RouteJudge.scala:145` 는 `!viewHit` 뿐이고 지점별 소유를 구조적으로 모른다. 구간값 소비자 `Reassembly.wr → ResultBank.write` 는 미배선 — `Wt64Top.scala:83` 「Reassembly.wr → ResultBank.write 는 **미배선**이다」 |
| 4 | fp32 산술 정확성 (`golden_fp32` 비트 일치) | `StepSequencer.scala:425-426` 이 `UInt` 정수곱·정수합 — 산술은 축 (b) 후속 |
| 5 | `mask64` 의 32비트 (`[63:44]`·`[11:0]`) | `MaskUnit.scala:289-296` 「저장은 적용 비트만」 — 레지스터도 배선도 없다. **비교 불가가 아니라 비교 대상 부재** |
| 6 | `SUBKEY`(256b)·`BLOCK`(512b) 를 통한 부분 수리 검출 | 내는 포트가 없다. `st_0..st_15` 의 계층 peek 은 포트 계약이 아니라 SpinalHDL 명명의 우연이라 통과 기준으로 쓰지 않는다 |
| 7 | `FAULT_STATUS[17]`·`[18]` | `Wt64Top.sv:1641` 「faultWords_status[17] = 1'b0;」 과 다음 줄 `[18]` 상수 0 — 원천 부재. **0 을 「정상」으로 읽으면 안 된다** |
| 8 | `SharedUnit`·`MemOrderGate` 독립 `.sv` 의 top 대표성 | 형상 불일치 — 독립본 16비트 vs top 인스턴스 161/128비트 |
| 9 | OPREF **B** 참조의 LBID 축 | 제시 자체가 없다 — `Wt64Top.scala:86` 「OPREF B 토큰의 RouteJudge 제시는 미배선」 (TODO 2항), `tokIn` 은 사이클당 하나. ISA-2 α 는 **OPREF A 축만** 덮는다 |
| 10 | 변환 저장소 관측 세 워드의 값 (`0xE04` · `0xE08`/`0xE0C`) | 회로 0건 — 정지 상태·정지한 요청의 VPN 을 내는 배선이 없다. 읽기는 응답 + 0, 쓰기는 거절 + `[6]` (파도 3 은 `0xE00` · `0xE10` 과 쓰기 방향만 닫았다) |
| 11 | 변환 조회의 호스트 ABI 층위 | 요청 원천(메모리 파이프) 미착지 — 조회는 내부 포트 `io.hiuReq` 제시다. `xlate_*` 시험의 기입 쪽만 호스트 ABI 오프셋이다 |

### 2번 별항 — ISA-1 형상 축이 미측정인 이유와 남은 20줄

`Wt64Config(nPoints=2)` 로 두 번째 SV 를 내는 생성기가 없다
(`rtl/spinal/src/main/scala/wt64/gen/` 에 `GenWt64TopShape.scala` 부재).
선례는 있다 — `GenSharedUnit.scala:23-26` 이 정확히 그 패턴으로
`SharedUnitDepth0.sv` 를 낸다. `rtl/spinal/` 은 이 파도의 편집 배정 밖이라
착지시키지 않았다.

**그동안 이 파일이 하는 일**: 궤적 비교기를 세우고, 그것이 살아 있음을
`isa1_comparator_selfcheck` 가 양·음성 대조로 **매 실행 증명한다.** 그리고
`isa1_place_independence` 가 한 형상 안에서 확인 가능한 ISA-1 의 몫(물리
자리 무관성)을 실제로 잰다. 형상 축을 잰 척하지 않는다.

형상 B 가 착지하면 대조면 정의(`SHAPE_DEPENDENT` 둘 제외 = 115)와
`snapshot()` 이 그대로 쓰인다.

### 부록 D 지위에 대한 주의

**ISA-2 를 「증명됨」으로 올리면 안 된다.** 존재 축만 닫혔고 자리 축은
열린 채다 (원장 3번). 정직한 지위는 **「부분 — 존재 축만」**이다.
**ISA-1 도 「증명됨」이 아니다** — 자리 무관성만 닫혔고 형상 축은 미측정이다.

---

## 정본 결정 대기 — 하네스가 임의로 정할 수 없는 것

**ISA-1 의 「관측 가능한 결과」의 외연이 정본에 없다.**
ⓐ결과값만 / ⓑ관측 가능한 출력 전부 / ⓒⓑ+사이클 타이밍 — 셋 다 §1.8 문면과
양립하고, 부록 D.3.1 색인은 「같은 결과」로 더 줄여 적어 오히려 모호함을 키운다.

이 하네스는 **ⓒ(사이클 정확)로 잰다.** 근거는 ⓒ ⊃ ⓑ ⊃ ⓐ 이므로 나중에 더
약한 정의로 완화하는 것은 언제나 무해하고 그 역은 편도라는 것이다
(§3.7.1 「되돌림이 비대칭이다」와 같은 논거). ⓒ가 깨지는데 값은 맞는
경우가 나오면 그 실패 자체가 정본이 답해야 할 질문의 반례이므로, 삼키지
않고 크게 실패시킨다.

**이것은 하네스의 재량이 아니라 결정 대기 항목이다.** `Common.scala:29` 가
태그 팩킹에 대해 이름한 형태 — 「정본이 정한 적 없는 값이 하네스 한 줄로
조용히 굳는다」 — 를 피하기 위해 선택과 근거를 여기 적어 둔다.

---

## 하네스를 짜다 실제로 밟은 함정 여섯

전부 **조용히 초록이 되는** 부류다. 다섯은 코드 안에 재발 방지 주석이,
⑥ 은 주석이 아니라 `boot()` 의 포트 정의역 **검사**가 박혀 있다. ⑤ 는 하네스가 초록이 된 **뒤** 적대적 재검증이 찾은 것이라
따로 표시해 둔다 — 초록은 검증의 끝이 아니다. ⑥ 은 RTL 계약이 바뀐 뒤
하네스가 **옛 계약을 잰 채** 여섯이 초록으로 남은 것이다.

### ① 관측 엣지가 한 박 늦으면 궤적 비교가 **공허하게 통과한다**

디코드 사슬은 레지스터 한 단이고 표본 엣지 = 방출 엣지다. 한 박 늦게
뜨면 관측면이 전부 0 이고 — **그래도 두 궤적 비교는 통과한다. 0 == 0
이기 때문이다.** `isa1_place_independence` 가 실제로 공허한 초록이었다.

⇒ `present()` 가 **매 제시마다** 전건(`io_route_tokOut_valid == 1`,
`malformed == 0`, `capAbsent == 0`)을 확인한다. 전건 없는 비교는 비교가
아니다.

### ② sticky fault 의 역사가 형상 차이로 오독된다

sticky 는 *역사의 누적*이다. 두 궤적을 따로 돌려 사이클 정확 비교를 하면
앞 궤적이 세운 sticky 가 다음 궤적의 시작 상태를 바꾼다.
`isa1_place_independence` 가 `io_fault_route` 한 자리에서 갈렸는데, 그것은
배치 A 의 뷰 미적중이 남긴 잔재였지 자리 결속이 아니었다.

⇒ **sticky 를 대조면에서 빼는 것으로 풀지 않는다** — 그것은 관측면을 줄이는
것이고 줄인 만큼이 미측정이 된다. 궤적 앞에서 `clear_all_faults()` 로
역사를 맞춘다. IO 해제선이 없는 다섯(`ownBadWrite`·`cqOverflow`·`cqBadWrite`
·`fpCapAbsent`·`ehCapAbsent` — MMIO `0xF84`/`0xF90` 로만 내려간다)은 이름으로
적어 두고, 서 있으면 크게 실패한다.

### ③ `io_mmio_ready` 를 아무 주소에서나 폴링하면 소거 구간이 **0 사이클**로 보인다

`io.mmio.ready` 의 기본값은 `True` 이고 — `Wt64Top.scala:1593` 「io.mmio.ready := True」 —
몇 구역에서만 덮인다(구성 구역은 `cfgBlk.io.ready` · 적법한 XLATE_ENTRY_HI 쓰기는 하류 `install.ready`). 예약 오프셋(예: `addr=0`)에서 폴링하면
reset 해제 직후 1 이 읽힌다. 그것을 「소거 끝」으로 읽으면 **이후 구성 기입이
통째로 무시된 채 본시험이 돈다.**

⇒ 폴링은 반드시 구성 구역 주소로. 그리고 `boot()` 가 소거 구간이 실제로
≈65536 엣지였는지 확인한다 — 짧으면 FAIL 이다.

### ④ 음성 대조가 변수를 하나만 흔들지 않으면 「잡았다」가 우연일 수 있다

태그(`lnid`)를 바꿔 뷰 미적중을 만들면 관측면 **여섯 자리**가 함께 움직인다
(`io_route_tokOut_payload_tag_lnid` · `io_mem_down_0..3_payload` ·
`io_route_faultFire`) — 태그가 그대로 전파되기 때문이다.

⇒ 음성 대조는 **자극을 바이트 동일하게 두고 사상만 제거한다.** 그러면
움직여야 하는 자리가 정확히 하나(`io_route_faultFire`)로 특정되고, 그
하나인지를 exact 로 판정할 수 있다.

### ⑤ (재검증이 찾음) 항진 단언을 「술어가 살아 있다」로 읽었다

`negative_control_comparison_is_live` 가 `got == exp` 를 단언한 **뒤**
`wrong = exp ^ 0x80000000` 을 만들어 `assert got != wrong` 을 두고 그것을
「대조 술어 생존 확인」이라 적었다. 파이썬 정수는 언제나 그 xor 와 다르므로
**이 단언은 결코 실패할 수 없다.** 실패할 수 없는 단언을 생존 증거로 읽는
것이 정확히 이 하네스가 잡겠다고 나선 그 형태다 — 재검증에서 발각했다.

⇒ 항진을 지우고 **구성 축 음성 대조**로 갈았다: 요청 프레임을 바이트
고정한 채 키·논스만 다른 벡터의 것으로 갈면 응답이 **그 벡터의 golden
마스크와 정확히 같아져야** 한다. 등가 비교이고, 「DUT 가 구성을 무시한다」를
실제로 끊는다.

부수: 그 대조의 짝을 `recs[1]` 로 집었다가 **자기 비공허 단언에 걸렸다** —
`pinned` 8줄은 키·논스가 같아 사영 마스크가 같다(그래서 서로 다른
`maskFrame` 이 73/80 이다). 색인으로 집지 않고 **사영 뒤 실제로 다른 첫
벡터를 찾아** 쓴다. 원장 5번(사영이 판별력을 32비트로 줄인다)이 하네스
자신의 자극 선택에도 걸린다는 실례다.

그리고 미측정 원장이 **성공 실행에서만** 인쇄되고 있었다 (`run_one` 이
실패 시 `sys.exit` 로 빠져나가 `print_unmeasured()` 를 건너뛴다). 원장을
가장 읽어야 할 사람은 실패를 보는 사람이다 — `try/finally` 로 옮겨
실패 실행에서도 찍는다.

부수로 밟은 것 하나 더: cocotb 2.0 은 테스트가 끝날 때 그 테스트가
`start_soon` 한 태스크를 전부 취소한다. 클럭을 「한 번만 띄우고 재사용」하면
두 번째 테스트에서 클럭이 죽은 채로 돌고, 그 실패는 **예외 없이** 온다
(시뮬이 `$finish` 하고 남은 테스트가 message 빈 FAIL 로 무너진다).
⇒ 클럭은 테스트마다 새로 띄운다.

### ⑥ (2026-09-22) 포트가 늘었는데 `INPUTS` 에 없으면 0 이 **뜻을 가진 채** 시험이 돈다

RTL `ca3c496` 이 `io_keyWr_part` 를 신설했다. 하네스의 `INPUTS` 목록에 그
이름이 없으니 `boot()` 가 초기화하지 않고 `write_key()` 도 구동하지 않았다 —
Verilator 미구동 입력은 0 이고, 그 0 은 「파티션 0」이라는 **뜻**을 갖는다.
모든 키가 파티션 0 에 앉았고 part≠0 파티션은 리셋 값(전부 0) 키로 재키잉해
golden 과 어긋났다. part≠0 으로 값을 재는 시험 **둘만** 죽었고
(`sec1_golden_exact` 라인 1 · `en_is_the_single_stall_source`), 나머지
여섯은 전부 part 0 에서 값을 재서 초록이었다 — 그 여섯의 초록은 계약을
확인한 것이 아니라 그 축을 재지 않은 것이다.

⇒ `INPUTS` 는 `boot()` 가 생성물 머리의 입력 포트 집합과 **기계로** 대조한다
— 누락·잉여면 FAIL 이다 (주석은 호출이 아니다; 옛 목록에 그 검사를 대면
`io_keyWr_part` 누락을 즉시 지목한다). 그리고
파도 A 의 **로컬** 완료 게이트에 `make rtl-sim` 이 없어 이 회귀가 커밋에
실렸다 (CI 의 step 은 2026-08-28 부터 있었다 — 아래 「미처리」 정정) —
RTL 계약을 바꾸는 파도는 후-formal 만이 아니라 **cocotb 골든도** 게이트에
넣어야 한다. 형식은 제어면을, 골든은 값을 잰다 — 둘은 서로를 대신하지
않는다.

부수로 찾은 것: 이 하네스의 `MaskUnit.scala:NNN` 좌표 인용 14건이 **전부
따옴표 없이** 있었고, 파도 A 가 그 파일을 고쳐 14건 중 13건이 다른 줄을
가리키게 됐는데(제자리는 XlateStore 의 폭 상수 인용 하나) 아무도 몰랐다 (`lint_section_refs` 의 R5 는 상한만 걸고 대상 대조는
따옴표 있는 인용에만 한다). 재조준하며 전부 같은 줄 축자 「…」 결속으로
바꿨다 — 다음 RTL 편집이 줄을 밀면 STALE 로 지목된다. 래칫 항목은 14 → 0.

---

## 러너가 선례에서 갈라지는 세 곳

선례는 `synth/lattice/fp_ops/run_fp_ops_tests.py` 다. API 형태(`get_runner` /
`build(sources=…)` / `test()`)는 그대로 서지만 **판정 로직 셋은 고쳤다.**

| # | 선례의 결함 | 이 러너의 처분 |
|---|---|---|
| a | `if num_failed:` 만 봐서 **테스트 0건이 exit 0** | 표에 `expect_min` 칸 — 하한 미달은 FAIL |
| b | `get_results` 가 `<skipped>` 를 안 센다 (`check_results.py:33-39`) ⇒ **자기 skip 이 「돌았고 실패 0」으로 읽힌다** | XML 을 직접 세고 **skip 을 실패로** 집계 |
| c | docstring 의 `python3 …` 가 이 호스트에서 `ModuleNotFoundError` | Makefile 이 `cocotb-config --python-bin` 에게 묻고, `main()` 이 오독을 선제 차단 |

(b) 는 이 저장소가 이미 밟은 형태다 — `scripts/lint_frag_slots_dual_run.py`
가 존재하는 이유가 정확히 「FRAG_SLOTS>1 전용 6건이 기본 빌드에서 값 검사
0건 하고 PASS 로 집계됐다」다.

그리고 **`runner.test()` 는 pytest 밖에서 실패를 판정하지 않는다**
(`cocotb_tools/runner.py:561-577` 의 `if pytest_current_test:` 가 통째로
건너뛰어진다). 시뮬이 exit 0 으로 끝나면서 테스트가 전부 FAIL 이어도
그 호출은 조용히 `Path` 를 돌려준다 — 러너의 `tally()` 가 **유일한 판정
지점**이다.

## 모듈 표(`MOD=`)를 쓰지 않는 이유 — 시기가 아니라 구조

`rtl/generated/` 18편은 평면이 아니라 **중복 정의 그래프**다.
`Wt64Top.sv` 가 module 정의 18개를 자기 안에 갖고, `HiuPipeline.sv` 가
`XlateStore` 를, `SharedUnit.sv` 와 `SharedUnitDepth0.sv` 가
`SharedUnitOccupyStub` 를 각각 정의한다. 두 편을 한 소스 목록에 넣으면
Verilator 가 `%Warning-MODDUP` 으로 거부한다(기본 fatal — 실측 5.048).

⇒ 형상마다 **별도 `build_dir` 로 따로 도는 수밖에 없고**, 그것은 Makefile
조건 분기 표가 아니라 파이썬 루프다. 그래서 러너의 `src` 는 **언제나 한
편**이고(파일 단위로 폐포가 이미 잡혀 있다 — SpinalHDL 이 하위를 인라인해
낸다) 그 사실을 규칙으로 못박아 나중에 손이 두 편을 합칠 자리를 없앤다.

`rtl-sim` 은 기존 모듈 표에 항목을 추가하지 않고 조건 분기도 0건이므로,
`scripts/lint_synth_coverage.py` 의 파서 앵커 둘과 래칫 넷을 건드리지 않는다
(`make lint` 전수 통과로 확인).

---

## 미처리 — 보고만 하고 고치지 않은 것

~~**`.github/workflows/gates.yml` 에 `rtl-sim` step 이 0건이다.**~~ — 착지했다.
`9fd6b52`(2026-08-28, 이 하네스와 같은 커밋의 「CI 결선」)가 「재구현 런타임
하네스 (rtl-sim)」 step 을 넣었다 (컨테이너 `wavetensor-dev:ci` 안에서
`make rtl-sim`). 이 문단은 그 커밋 안에서 이미 낡아 있었다 — 2026-09-22 정정.

그런데 CI 에 step 이 있어도 **파도의 로컬 완료 게이트에 `make rtl-sim` 이
없으면** 회귀는 커밋에 실린다 — 2026-09-20 `ca3c496` 이 그 실례다 (커밋
문면의 게이트 목록: rtl-postformal · lint · rtl-lint · tla run · 레거시
cocotb — 이 하네스는 없다). RTL 계약을 바꾸는 파도의 게이트에 이 하네스를
넣는 것은 CI 가 아니라 **파도 절차**의 몫이다 (함정 ⑥).

`synth/lattice/fp_ops/run_fp_ops_tests.py` 자신의 결함 셋(위 표)도 그대로
남아 있다 — 그 파일도 편집 배정 밖이다.
