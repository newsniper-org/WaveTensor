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

## 실행 결과 (2026-10-26, 호스트 — W8 생성물 · 판 값 커밋 `0xFFC` = `0x0001_0000` · FP_SHAPE 판 게이트)

```
Mask:      12 tests passed (skip 0, 하한 12)
Shape:     47 tests passed (skip 0, 하한 47)
ShapeAbi0:  3 tests passed (skip 0, 하한 3)
run_wt64: 요청 스위트 3건 / cocotb 테스트 62건 전부 통과
```

(2026-10-26 W8(판 값 커밋) — Shape 46 → 47: `abi_version_pair` 신설 · `page_disposition` 의 `0xFFC` 읽기 기대와 `fp_shape_expect` 를
판 리터럴로 · 새 스위트 `ShapeAbi0`(판 0 변형 — 아래 「W8」 절). 2026-10-18 W6(`0xF0C` FP_SHAPE · `[7]`) — Shape 44 → 46: `fp_shape_word` · `own_set_collide` 신설, `fp_clear_window` 를 제자리에서 넓힘(④–⑥ — 아래 「W6」 절). 2026-10-15 W4(결속 파티션) — Shape 37 → 44: 조회 헬퍼가 파티션을 `0xE14` 결속으로 만들고(`bind_part`) 새 일곱(`active_part_*` 여섯 · `reset_values_norm` — 아래 「W4」 절). 2026-10-13 W3 수정 — Shape 36 → 37 `xlate_high_vpn_bits_distinguish` · `xlate_other_flush_keeps_staging` 에 파티션 1 vs 3 행(아래 「W3 수정」 절). 2026-10-13 W3(형상 비노출 `0xC00` 문) — Shape 26 → 36: 옛 문의 `xlate_*` 를 제자리에서 VPN → FRAME → COMMIT 문으로 다시 쓰고 새 열(N1–N7 · 선-formal 인계 셋 — 아래 「W3」 절). 2026-10-12 W2(판정 래치) — Shape 24 → 26 `xlate_released_judgment_survives_eviction` · `xlate_latched_hit_survives_retire`(아래 「W2」 절). 2026-10-12 W1 검증 수리 — Mask 11 → 12 `nonce_dup_compare_every_bit`(논스 비교 전폭 — 아래 「W1」 절의 「검증 수리」) · N14 에 reset · `[4]` 단독 해제 · `0xF88` 요약 행. 2026-10-11 W1(3.10 RTL 파도 — 표면 비트·워드) — Shape 21 → 24 `hiu_shape_word` · `mask_dup_capture` · `fault19_nonowned_access`, Mask 11 그대로(두 시험을 넓힘 — 아래 「W1」 절). 2026-09-26 파도 4 — Shape 15 → 16 `abort_tag1_word_legality` · 통합 착지 16 → 21: 페이지 통합 `page_disposition` · `fp_clear_window` ·
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
| `faultNonceDup` 등가 대조 (golden 루프 안) | **80/80 라인** — 기대 1 이 17라인 (pinned 1–7 · edge 42–43 · key_word 쌍 뒤 줄 65…79), 나머지 63은 기대 0. `dupCapture`(0xEC4 유닛 쪽) 등가 **80/80** + 해제 뒤 0 **17/17** · 다중 비트 비트맵 **7라인** (2–7 · 43) | `sec1_golden_exact` |
| 임대별 키 범위 — 값 수준 | part 1/2 각자 golden → part 1 키만 갈아 `maskReady` 정확히 `0b0100` · part 2 값 불변 → 재키잉 뒤 `0b0110` · 값 셋 golden | `key_scope_cross_partition_value` |
| 계산 중 **다른** 파티션 기입 | `maskReady == 0b0001` · `faultWrDuringRekey == 0` · part 0 값 golden | `wr_other_partition_during_rekey_is_clean` |
| 변이 실측 (사본 worktree, 생성 SV 한 자리씩 — M2 만 case 블록 24줄) | **4/4 잡힘** — 아래 표 | Mask 스위트 전체 |
| 구성 표면 소거 구간 | **65535 엣지** | `cfg_surface_integrity` |
| ISA-1 대조면 | **122/124** 출력 (제외: `io_push_1_stall`·`io_push_2_stall`) | `compare_face_is_pinned` |
| IO fault 해제선 | 19 (fault 출력 28 − MMIO 전용 9 — `NO_IO_CLEAR` 는 이름까지 생성물과 등식. W3 의 `io_fault_xlateCfgBadWrite` 와 W4 의 `io_fault_actCfgBadWrite` 는 `0xF84[6]` 로만 내려간다) | 같음 |

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
이하, 생성물 `MaskUnit.sv:312-315` 「st_1[11 : 0] + 12'h46e」 에서 상수 셋 대조 확인).

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
변환 저장소의 MMIO 문(파도 3 — `xlate_*` 아홉 · W3 에서 형상 비노출 문으로 제자리 재작성(아래 「W3」 절):
설치 → 적중 · flush → 같은 VPN 미적중 · 정지를 푸는 COMMIT · V=0 무효화 · 짝 검사 거절의 `[6]` · flush
거절과 절단 별칭 부재 · `0xE10` 은 정지를 풀지 않는다 · 그리고 반증 검토 뒤 더한 인접 기입 둘(파도 3 의 HI · W3 의 COMMIT) —
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

### W1 — 표면 비트 · 워드 (3.10 v1.0 묶음의 RTL 파도 첫 하위 파도)

새 표면 셋을 호스트가 보는 값으로 잰다. 기대값은 **정본 표에서 독립 유도**한다 —
RTL companion 의 상수(비트 자리 · 오프셋 · 형상)를 import 하지 않는다 (차등 정의역
함정 — 기대측이 RTL 에서 오면 RTL 과 함께 틀리고 시험은 *부재*로 침묵한다).

| 시험 | 스위트 | 재는 것 |
|---|---|---|
| `hiu_shape_word` (N12) | Shape | `0xFF8` 읽기 == 참조 형상(정본 E.2 「파티션 4 × 항목 16 · 직접 사상」)에서 유도한 `0x0000_1004` (개수 인코딩) · 재읽기 불변 · 쓰기 셋(전폭 1 · 읽은 값 · 0)이 값과 무관하게 거절 + `[6]` · 값 불변 · `[7:0]` 이 XLATE_FLUSH 수락 정의역과 맞물림 |
| `mask_dup_capture` (N13) | Shape | `0xEC4` 23 행 표 — reset 0 · 래치(p · 비트맵 · `[16]`) · 읽기 무부작용 · RO 쓰기 거절 · 첫 사건 보존 · `0xF84` `[12]` 와 내부 해제선이 워드 전체를 지움 · 비트맵 정의역 셋(유효한 p 자신 · 유효 하강 · 다른 논스) · 거절 + `[6]` 발화 둘과 엔진 바쁨 미수락 발화의 불변 · 같은 사이클 해제 + 발화의 새 사건 래치(p · 비트맵 둘 다 앞 사건과 다르게) · 바쁨/거절 발화 + 해제선은 해제만 |
| `fault19_nonowned_access` (N14) | Shape | reset 직후(해제 전) `[4]` · `[19]` · `[6]` 과 원천별 수출 둘이 0 + 원인별 보고 12 접근 행(적중 · 「정지 → 채움」 두 경로) — 자격 거부 → `[4]` 만 · 자격 허용 ∧ 비소유 → `[19]` 만 · 자격이 먼저 · 거부 채움은 프레임 무관 `[4]`, 행마다 승인 0 · 값 0 · 사이클 수가 양성 대조와 같음(상태열 균일) + sticky/`0xF84`/`0xF88` 10 행 — `[31:20]` 예약 비0 은 거절 + `[6]` · 한 비트도 안 내림 · `[19]` = 1 인 채 `1 << 4` 는 `[4]` 만 내림 · `[19]` 하나만 선 FAULT_STATUS = `1 << 19` · FAULT_SUMMARY = 1 · `1 << 19` 는 `[19]` 만 내림 + 원천별 수출 `io_fault_hiuOwn`/`io_fault_hiuPerm` |
| `sec1_golden_exact` (넓힘) | Mask | 80 라인마다 `dupCapture` 등가 + 겹친 라인의 해제 뒤 0 + 다중 비트 비트맵 라인 비공허 |
| `fault_nonce_dup` (넓힘) | Mask | `[12]` · `dupCapture` 10 행 표 — 래치 · 첫 사건 보존 · 해제 · 유효한 p 자신 제외 · 같은 엣지 해제 + 발화(p · 비트맵 둘 다 새 사건) · 바쁨 미수락 + 해제선 · 유효 하강 제외 |
| `nonce_dup_compare_every_bit` (검증 수리) | Mask | 논스 비교 전폭 1540 행 — 비교기 넷(q) × (기저 논스 유효화 1 + p = q+1 에 한 비트 차이 192 + 이웃 두 비트 차이 191 + 같은 논스 양성 대조 1). 차이 행은 `[12]` = 0 · 캡처 0, 양성 대조는 `[12]` = 1 · 캡처 = (p, {q}). 행마다 전건(q 유효 · 모형 겹침 없음)을 그 자리에서 단언 |

`zero_inputs` 는 이제 생성물 머리의 입력 포트 집합과 `SHAPE_INPUTS`(+ `io_faultClear_*`)를
매 부팅 기계로 대조한다 — 아래 함정 ⑥ 의 Shape 판.

**통합 실측 (2026-10-11, W1 생성물 — `Wt64Top.sv` sha256 `03d89ffe…d0cd7` · `MaskUnit.sv`
`d9c9f968…6a4f`)** — `make rtl-sim` 필터 없이 35/35(Mask 11 · Shape 24). 생성물 포트 목록에서
다시 센 계수: 출력 121 → **122** · 대조면 119 → **120** · 입력 120 그대로 · IO 해제선 **19**
그대로 · fault 출력 25 → **26** · `NO_IO_CLEAR` 6 → **7**(`io_fault_hiuOwn`). `compare_face_is_pinned`
는 이제 `NO_IO_CLEAR` 의 *이름*도 「같은 이름 해제선이 없는 fault 출력」 집합과 등식으로 본다
(수의 등식은 이름이 바뀐 축을 못 본다 — 아래 변이 MS12).

**HEAD 음성 대조 (2026-10-11, HEAD `3b80087` 생성물 · 이 파일들 그대로)** — 의도한 이유로 죽는 것:
N12 `0xFF8` 읽기 0(예약 오프셋), N13 `0xEC4` 열이 래치 행마다 0 · `0xEC4` 쓰기 행의 `[6]` 0(10/23 행,
`[12]` 열은 23 행 전부 모형과 같다 — 지향 23 행의 읽기 관측일 뿐 HEAD `[12]` 판정의 동치를 말하지 않는다), N14 비소유 · 자격 허용 세 행(적중 읽기 · 쓰기 · 채움)이 `[19]`
대신 `[4]` · sticky/`0xF84` 7 행 전부(`[19]` 원천 없음 · `[31:19]` 예약으로 `1 << 19` 거절 + `[6]`).
함께 죽지만 값 음성 대조가 *아닌* 것: `compare_face_is_pinned`(출력 121 ≠ 122) 와 `clear_all_faults` 를
부르는 궤적 시험 넷(`io_fault_hiuOwn` 핸들 부재) — 못박은 표가 W1 생성물을 적기 때문이다. 계수 두 줄과
`NO_IO_CLEAR` 만 HEAD 값으로 되돌린 사본으로 다시 돌리면 기존 21 은 통과하고 N12 · N13 · N14 셋만 같은
이유로 죽는다. Mask 9/11: 넓힌 두 시험은 **포트 부재**(`dupCapture` 없음)로 죽는다 — 값 음성 대조가
아니다(`fault_nonce_dup` 의 `[12]` 열은 10 행 전부 모형과 같다 — 지향 10 행의 읽기 관측이다). 캡처 *값*의 음성 대조는 아래 변이가 맡는다.

**변이 실측 (2026-10-11, W1 생성물의 rsync 사본에 생성 SV 한 자리씩 · 스위트 전체)** — 23 변이 전부
잡힘, 새 시험 · 검사마다 그것만 죽이는 변이가 있다:

| 변이 (생성 SV 자리) | 죽은 시험 |
|---|---|
| MaskUnit 래치 조건에서 보유 항 삭제(첫 사건 보존 제거) · 해제 우선(세움 승리 제거) · 비트맵에서 유효 항 삭제 · 비트맵에서 `q ≠ p` 항 삭제 | `fault_nonce_dup` 만 |
| MaskUnit 비트맵에서 논스 항 삭제 | `sec1_golden_exact` 만 (`fault_nonce_dup` 의 유효 파티션은 논스가 전부 같다 — 이 축은 `sec1` 몫) |
| MaskUnit 해제가 필드를 안 지움 · `dupCapture[16]` 을 0 으로 | 둘 다 |
| Wt64Top `0xFF8` 값을 log2 인코딩 `0x0402` 로 · `0xFF8` 쓰기를 거절식에서 뺌 | `hiu_shape_word` 만 |
| Wt64Top `0xEC4` 쓰기 거절 삭제 · `0xEC4` 읽기에서 `[16]` 결손 · 최상위 안 MaskUnit 의 첫 사건 보존 제거 | `mask_dup_capture` 만 |
| Wt64Top `permViol` 을 HEAD 꼴로 · `ownViol` 에서 자격 항 삭제 · `[19]` 해제 미결선 · `0xF84` 예약을 `[31:19]` 로 · `granted` 에서 자격 항 삭제(값 누출) | `fault19_nonowned_access` 만 |
| 최상위 출력 하나 추가 · 해제선 하나를 `io_faultClear_hiuOwn` 으로 개명(수는 그대로) · `[19]` 에 IO 해제선을 붙임 | `compare_face_is_pinned` 만 |
| 최상위 입력 하나 추가 · 하나 제거(내부 상수로) · `input` 줄 하나 들여쓰기 변경(파서가 흘림) | 부팅하는 23 시험 전부 — 아래 함정 ⑥ Shape 판 |

**검증 수리 (2026-10-12 — 독립 변이 반증이 찾은 탈출 셋)** — W1 생성물은 그대로이고 시험만 넓혔다
(생성물 sha 는 위 통합 실측과 같다). 무변이 `make rtl-sim` 필터 없이 36/36(Mask 12 · Shape 24).

| 탈출 변이 (생성 SV) | 수리 전 | 수리 뒤 |
|---|---|---|
| X14 — 논스 비교기 넷이 워드 0 비트 1 을 무시 (`engine.sby` 탐침 여섯 밖 한 자리) | engine prove · bmc PASS · Mask 11/11 · Shape 24/24 — **어디서도 안 잡힘** | `nonce_dup_compare_every_bit` **만** 죽음 — 「한 비트 차이 4 행: (q, p, 비트) = (0,1,1) (1,2,1) (2,3,1) (3,0,1)」 |
| 비교기 하나만 · 한 자리만 무시 — q=2 비트 150 · q=0 비트 191 · q=3 비트 64 (이 단계의 손 변이 — 비교기 넷이 다 훑이는지) | — | 셋 다 `nonce_dup_compare_every_bit` **만** · 각자 정확히 그 (q, 비트) 한 행 |
| X23 · X24 — 패리티 접기 비교(192 비트 전체 · 워드별) | `sec1_golden_exact`(+ X23 은 `key_scope_cross_partition_value`) | 그대로 + `nonce_dup_compare_every_bit`(이웃 두 비트 차이 X23 764 행 · X24 744 행 — 워드 경계를 건너는 쌍 20 개는 워드별 패리티를 바꾼다 — 와 기저 논스 유효화 3 행) — 두 층 |
| X21 — `faultOwn` reset 값 1 | N14 통과 — `clear_all_faults` 를 부르는 궤적 시험 넷이 시작 상태 가드로 *우연히* 잡음 | 그대로 + `fault19_nonowned_access` 의 reset 행 「관측 (0, 1, 0, 0, 1) · 기대 0」 |
| X04 — `[4]` 해제(`io_faultClear`)가 `faultOwn` 도 내림 | hiumask `o_own_hold` 만 · Shape 24/24 | + `fault19_nonowned_access` 의 「`[19]` = 1 인 채 `0xF84` ← `[4]`」 행 (0,0,0) ≠ (0,1,0) |
| X02 — FAULT_SUMMARY 가 `[19]` 를 뺌 | assembly `a_rd_fsum` 만 · Shape 24/24 | + `fault19_nonowned_access` 의 요약 행 (0x00080000, 0) ≠ (0x00080000, 1) |

`nonce_dup_compare_every_bit` 의 HEAD `3b80087` 생성물 대조는 포트 부재(`dupCapture` 없음)로 죽는다 — 값
음성 대조가 아니다. 이 시험의 값 대조는 위 X14 계열이다 (HEAD 의 비교기는 W1 과 같은 식이라 그 생성물에서
값 대조가 성립할 자리가 없다).

### W2 — 판정 래치 (3.10 v1.0 묶음의 RTL 파도 둘째 하위 파도)

정본 3.6.2 「판정 시점과 판정 래치」 · 3.7.2 「철회의 효력 범위」 · E.1.2 `0xC00` 결과 (a)(b)(d) 를 HIU 요청
경로의 응답 값과 `0xE04` 관측으로 잰다. 기대값은 정본 문장과 시험이 쓴 값(프레임 · 소유)에서 유도한다 —
RTL 의 래치 신호(`lat_*`)를 보지 않는다(포트 계약만: `io_hiuHold` · `io_hiuReq` · `io_hiuRsp` · `io_phys` ·
`0xE04` · FAULT_STATUS). 두 시험의 헬퍼는 W3 에서 형상 비노출 문의 `commit_entry` · `commit_ops`(VPN →
FRAME → COMMIT)로 바뀌었다 — 로직 · 기대값은 그대로이고, 세 워드 열이 경쟁 커밋의 가장 이른 꼴을 한 에지
미룬다(C+3 수락 · C+4 채움 가림 · 버스트 정지 계수 `[0, 0, 0, 0, 0, 0]`).

| 시험 | 재는 것 |
|---|---|
| `xlate_released_judgment_survives_eviction` (N8) | 결과 (d) 의 반례 그대로 — 미적중 정지 → hold → A 의 커밋이 풀고 요청은 hold 로 조회 지점에 머묾 → 같은 파티션 축출 → 놓음. 축출 원인 둘(정본이 이름한 COMMIT · flush): **경쟁 커밋** — COMMIT(A) 수락 C → C+1 채움 바이패스 적중 · VPN(B) → C+2 FRAME(B) → C+3 같은 칸의 다른 VPN COMMIT(B) 수락 → C+4 채움 가림(W2 판은 LO · HI 두 워드라 C+2 · C+3 이었다). RTL 에서 가장 이른 꼴이고 인접 버스트의 정지 계수 `[0, 0, 0, 0, 0, 0]` 이 C · C+3 을 못박는다. **flush(p)** — 채움 슬롯을 기다리지 않으므로 C+1(풀린 첫 적중 사이클)에 수락되고 그 끝 에지 = 래치 포착 에지에 A 의 진행 중 채움 줄과 유효 비트를 지운다. 사례마다 hold 를 올린 뒤부터 응답까지 호스트 응답 leg(`io_hostRsp` — 장치 소유 비0 프레임 · RWX 전부)을 세워 둔다 — 래치를 호스트 leg 에서 포착하는 구현은 첫 관측 행(정지가 사라진다)과 응답 행(그 프레임)에서 운다. hold 중 `0xE04` `[0]` = 0 · `0xE10` 뒤 `[1]` = 0 · 래치가 선 hold 중 `0xF84` W1C(`[4]` · `[19]`)를 한 번 쓰고 16 사이클 더 — 관측면 0 · `io_fault_hiuMiss` 0(해제 펄스로 래치를 비우는 구현은 이 행에서 재미적중으로 운다) · 놓은 뒤 3 사이클(대조 — 저장 적중을 hold 로 잡았다 놓은 것과 같은 상태열)에 A 의 프레임 · fromFill 1 로 승인 · `[4]` · `[19]` · `[6]` 0 — 15 행. 끝에 축출 전건(B 적중 · A 미적중 · flush 된 A 미적중). 같은 칸 고르기는 화이트박스(직접 사상 — 색인 = VPN 하위 4b) |
| `xlate_latched_hit_survives_retire` (N9) | 같은 (p, VPN) 요청 둘 R1 · R2 를 인접 제시하고 R1 의 첫 적중 사이클에 hold — R2 는 R1 이 떠나는 그 에지에 조회 지점에 들어 철회 · 대체 에지 *뒤에* 판정된다. 대조(철회 없음) · V=0 COMMIT 과 flush(p) 각각 포착 뒤 · 포착 에지와 같은 에지(R1 의 첫 적중 사이클에 기입을 실어 그 끝 에지에 수락) · 같은 VPN 대체(새 프레임은 호스트 소유) · 권한만 바뀌는 대체(같은 프레임 FA · 권한 -WX → R-- · 요청 둘 다 쓰기 — R1 은 래치된 권한으로 승인되고 응답 권한 칸이 `-WX`, R2 는 자격 거부 `---` · 끝에 `[4]` = 1) · hold 없는 대조(적중 R1 이 첫 적중 에지에 떠나고 미적중 R2 가 그 에지에 든다). R1 은 언제나 래치된 FA(fromFill 0)로 승인되고, R2 는 철회면 미적중 정지 → 채움 FC 로, 대체면 FB(호스트 소유 → 값 차단 + `[19]`)로 판정된다. hold 없는 대조의 R2 는 자기 조회로 정지한다(판정을 물려받지 않는다). 응답 사이클 칸은 기준 경로 둘(래치 없는 적중의 조회 지점 → 응답 3 · 정지 하나를 채움이 푸는 경로 2)과 같은 셈 · 응답 행마다 권한 칸 — 33 행 |

**`LOOKUP_WINDOW` · `MISS_LEAD` 실측** — 래치는 단 수를 바꾸지 않는다. 두 시험이 매 실행 로그에 남기는 실측:
적중 조회 접수 → 응답 5 사이클 · 조회 지점 도달 2(= `MISS_LEAD`) · 조회 지점 → 응답 3 · 채움 기입 → 응답 2 —
W2 생성물과 HEAD 생성물이 같다. `assert_miss` 의 표본열 등식(창 20 · 앞 2)을 쓰는 기존 시험이 W2 생성물에서
전부 통과한다 — 두 상수는 그대로다.

**통합 실측 (2026-10-12, W2 생성물 — `Wt64Top.sv` sha256 `ff28cb10…3bc0c` · `HiuPipeline.sv` `442c2711…db45d`)**
— `make rtl-sim` 필터 없이 38/38(Mask 12 · Shape 26). 대조면 계수(출력 122 · 대조면 120 · 입력 120 · 해제선 19 ·
`NO_IO_CLEAR` 7)는 그대로다 — 래치는 내부 상태이고 최상위 포트가 늘지 않았다.

**HEAD 음성 대조 (2026-10-12, HEAD `a8cda09` = RTL `9b6eee6` 생성물 · 이 파일들 그대로)** — 기존 24 는 통과하고
새 둘만 의도한 이유로 죽는다. N8: 두 사례 모두 축출 뒤 hold 중 관측면이 요청을 다시 말하고(재미적중 — 경쟁
커밋 `0x00000103` · flush `0x00000203` 과 그 VPN) `0xE10` 해제 뒤에도 `[1]` 이 남으며, hold 를 놓아도 응답이
없다(영구 정지). 대조 · 정지 전건 · 버스트 정지 계수 · `[6]` 행은 같다. N9: V=0 · flush 네 행에서 R1 이 hold 중
다시 미적중하고(관측면 `[0]` = 1) 채움 커밋의 FC(fromFill 1)로 판정된다 — 래치된 FA 가 아니다. 대체 행에서
R1 이 떠나는 시점의 저장 시야 FB(호스트 소유)로 판정돼 승인이 무너진다. 대조 · hold 없는 행은 같다.

**변이 실측 (2026-10-12, W2 생성물의 rsync 사본 — 생성 `Wt64Top.sv` 의 `module HiuPipeline` 구간 한 자리씩 ·
Shape 스위트 전체)** — 12 변이 전부 잡힘. 기존 24 시험은 어느 변이에도 죽지 않는다(판정 래치는 지금까지 어느
cocotb 시험의 정의역에도 없었다):

| 변이 (생성 SV 자리) | 죽은 시험 |
|---|---|
| 래치 정지 절반 삭제(`lookAny` = 조회 적중뿐) · 값 절반 삭제(`lookFrame`/`lookPerm` 마지막 대입 · `lookFill` — 모델 대안 value_no_latch) · 미적중 sticky set 이 원시 미적중(sticky_raw_miss) · `s4.frame` 이 저장 시야를 다시 읽음(소유권 조회와 마스킹 입력이 두 값) · 같은 파티션 커밋이 래치를 비움 · flush 가 래치를 비움 | 둘 다 |
| `lookFill` 만 래치를 안 탐 | N8 만 (fromFill 진단 칸 — 판정 값은 같다) |
| 포착이 저장 적중에서만(채움 바이패스 사이클의 판정을 놓침) | N8 만 — flush 사례의 재미적중(값) + 경쟁 커밋 사례의 fromFill |
| 래치 비움이 한 에지 늦음(clear_late) | N9 만 — 철회 · 대체 행의 R2 가 R1 의 판정(FA)을 물려받음 |
| 같은 에지의 포착이 비움을 이김(capture_beats_clear) | N9 만 — hold 없는 행의 미적중 R2 가 R1 의 판정으로 정지 없이 승인 |
| 포착이 채움 바이패스 적중에서만(저장 적중의 판정을 놓침) | N9 만 |
| 늦은 포착(조회 지점에서 한 사이클 머문 뒤의 적중만) | N9 만 — 포착 에지와 같은 에지의 V=0 · flush 두 행 |

**검증 수리 (2026-10-12 — 독립 변이 반증이 찾은 탈출 다섯)** — 생성물은 그대로이고 시험만 넓혔다. 권한 필드의 래치를 가르지 못하던 셋(값 쪽 래치에서 권한만 빠짐 등)은 N9 의 권한 행에서, 호스트 leg 포착은 N8 의 호스트 leg 상주 행에서, `faultClear` 가 래치를 비우는 구현은 N8 의 `0xF84` W1C 행에서 이제 죽는다. 같은 방법의 46 변이 재실측(Shape 스위트)에서 42 잡힘 · 생존 넷은 처분이 있다 — 둘은 `latCapture` 의 `s3.valid` 항 변이로 miter 로 동치가 증명됐고(`hiumask.sby` 「동치 변이」 절), 하나는 거품 데이터라 `hiumask` 가 잡으며, 하나는 reset 의 래치 비움(Verilator 0 초기화 — reset 형식 단언 이월). 전 스위트 38/38 그대로.


### W3 — 형상 비노출 `0xC00` 문 (3.10 v1.0 묶음의 RTL 파도 셋째 하위 파도)

호스트는 파티션 기저 `0xC00` + (p ≪ 7) 에 VPN(`+0x00`) · FRAME(`+0x04`) · COMMIT(`+0x08`) · VPN_HI(`+0x0C`)
만 쓰고 칸은 장치가 고른다. 기대값은 정본 E.1.2 `0xC00` 행 · 결과 (a)–(d) · 스테이징 (f) · E.3 2항의 문장에서
독립 유도한다(`test_shape_equiv.py` 의 절 머리에 축자 인용 목록). 헬퍼는 `xbase` · `commit_word` · `commit_ops` ·
`commit_entry` 로 바뀌었고(앞판 `xent` · `hi_word` · `install_entry` 은퇴), 옛 문의 `xlate_*` 열둘(W2 의 N8 · N9
헬퍼 포함)은 제자리에서 다시 썼다 — `xlate_hi_rejects_are_loud` → `xlate_commit_rejects_are_loud` (행 표 16 행),
인접 HI 둘 → `xlate_adjacent_commit_stalls_then_commits` · `xlate_adjacent_v0_stalls_then_invalidates`.
`[6]` 의 정지 중 사이클 표본은 생성물 출력 중 `io_fault_*BadWrite` 전량의 논리합(`f6_now`)이고, 쓰는 시험마다
끝에 그 값이 `0xF80[6]` 과 같은지 대조한다. 행 표의 조회 칸은 앞 조회가 정지해 접수가 막히면 `("blocked",)` 로
적는다(음성 대조 기록이 첫 정지에서 끊기지 않게).

| 시험 | 재는 것 |
|---|---|
| `xlate_reserved_words_strict` (N1) | 네 기저 × `+0x10`~`+0x7C` 28 워드: 쓰기마다 `[6]` · 되읽기 0 (데이터는 앞판 LO · HI 의 적법한 기입처럼) · 표의 네 워드 읽기 0 · 읽기는 `[6]` 무발화 · 112 기입 뒤 COMMIT{1} 수락 · (1, va) 적중 · (0, va) 미적중 — 120 행 |
| `xlate_vpn_hi_rules` (N2) | VPN 없는 VPN_HI · 비0 둘 · 다른 기저 → `[6]` · 스테이징 불변(뒤 V=1 COMMIT 이 앞 FRAME 으로 커밋) / VPN_HI(0) 수락 → FRAME 유효 하강 → V=1 COMMIT `[6]` · 무커밋(표의 판 그대로) · FRAME 재기입 뒤 V=1 수락 · VPN_HI(0) 뒤 V=0 수락 → 미적중 |
| `xlate_vpn_rewrite_drops_frame` (N3) | VPN(va) · FRAME(fx) · VPN(vb) · V=1 → `[6]` · fx 가 어느 VPN 에도 묶이지 않음 · VPN{q} 가 래치를 옮김 → COMMIT{p} · COMMIT{q}(V=1) `[6]` · V=0 COMMIT{q} 수락 · VPN{p}(vb) · V=0 → 미적중 |
| `xlate_commit_data_reject_after_stall` (N4) | 하류가 찬 사이클의 데이터 사유 COMMIT 둘(`[27:0]` 비0 · FRAME 유효 없는 V=1): 정지 계수 `[…, 1]` · 사이클 표본 (ready, `[6]`) = 정지 (0, 0) · 수락 사이클 (1, 0) · 수락 에지 뒤 1 · 무커밋 |
| `xlate_commit_addr_reject_no_wait` (인계 「kind」) | 적법한 COMMIT{p} 바로 다음 사이클의 기저 불일치 COMMIT{q}: 정지 0 · 수락 에지에 `[6]` · 무커밋. 이 RTL 의 채움 슬롯은 파티션별이라 q 의 슬롯은 비어 있다 — 잡는 것은 「정지가 주소를 안 보고 슬롯도 파티션을 안 가리는」 문. **「주소 · 상태 사유가 정지를 기다린다」 축 자체는 합성 RTL 에서 도달 불가**(아래 「W3 수정」 절) — 수락 근거는 props `p_need_iff` · assembly `a_ready_only_slot` |
| `xlate_staging_survives_commit` (인계 「consume」) | 한 스테이징의 COMMIT 넷(V=1 → V=0 → 정지를 푸는 V=1 → V=1 R=0) 전부 수락 · 매번 커밋(적중 · 미적중 · 승인 · 자격 거부 + `[4]`) |
| `xlate_other_key_keeps_stall` (인계 「다른 키」) | R(p, va) 정지 중 같은 칸(화이트박스 — 하위 4b)의 다른 VPN · 다른 칸 · 다른 파티션 같은 VPN 의 V=1 커밋 · (p, va) 스테이징 기입만 — 매번 응답 없음 · ready 0 · 관측면 불변 · `[6]` 0. COMMIT(V=1) 한 워드가 푼다. 전건: 다른 칸 · 다른 파티션 커밋은 적중 |
| `xlate_same_vpn_replaces` (N5) | 같은 (p, VPN) 재커밋 셋(새 열 · 산 FRAME 위 FRAME 재기입 · 새 열) → 매번 마지막 프레임만 적중 · 다른 파티션 같은 VPN 불변 · V=0 뒤 미적중(앞 판이 드러나지 않음) |
| `xlate_v0_nonresident` (N6) | R(p, vb) 정지 중 VPN · FRAME · V=0 COMMIT(p, vb) — 정지 유지 · 관측면 불변 · 같은 스테이징 V=1 이 푼다 · 커밋한 적 없는 (p, vd) 의 V=0 뒤 미적중. 같은 파티션 다른 항목의 축출은 단언하지 않는다(허용) |
| `xlate_evict_scoped` (N7) | q 에 항목 넷 · p 에 커밋 33(하위 4b 0~F 전부 · q 와 같은 VPN 값 포함) · q 의 VPN 넷을 p 에서 V=0 → q 의 넷 전부 처음 프레임으로 적중 · p 의 마지막 커밋 적중 |

**HEAD 음성 대조 (2026-10-13, HEAD `aa91e86` 생성물 · 이 파일들 그대로 — rsync 사본)** — 새 열 전부 FAIL. 정본이
새로 거는 축 넷은 의도한 이유로 운다: N1 은 112 예약 워드 쓰기가 전부 `[6]` 0(앞판 LO · HI 로 수락), N2 는
VPN_HI(= 앞판 색인 1 의 HI 자리) 비0 기입이 `[6]` 0, N4 는 `[27:0]` 비0 COMMIT(= 앞판 태그)이 정지도 `[6]` 도 없이
수락, 「kind」 는 기저 불일치 COMMIT(= 앞판 다른 색인의 LO)이 `[6]` 0, N3 은 VPN 재기입 · 래치 이동 뒤의 V=1 이
`[6]` 0. 나머지 다섯(N5 · N6 · N7 · consume · 다른 키)은 앞판 문이 세 워드 열을 커밋으로 읽지 않아 첫 적중 · 정지
해제 행에서 운다(문 배치 자체가 다르다).

**변이 실측 (2026-10-13, W3 생성물의 rsync 사본 — 생성 `Wt64Top.sv` 한 자리씩 · Shape 36 전체)** — 새 시험마다
그것을 죽이는 변이가 있고, 아래 「그것만」 열이 그 시험 하나만 죽인 변이다:

| 변이 (생성 SV 자리) | 죽은 시험 |
|---|---|
| K1 `isRsvw` = 0 (예약 워드 흡수) | N1 만 |
| K2 수락된 VPN_HI 가 FRAME 유효를 안 내림 | N2 만 |
| K2b VPN_HI 관대(`vhLegal` = `pairOk`) | N2 · `xlate_commit_rejects_are_loud` |
| K3 VPN 재기입이 FRAME 유효를 안 내림 | N3 · N4 |
| K3b 파티션이 바뀐 VPN 재기입만 FRAME 유효를 안 내림 | N3 만 |
| K4a RefuseDomain=full (`needReady` 에 ¬`cmDataBad` · 데이터 사유를 곧장 거절) | N4 만 |
| K4b 데이터 사유 거절이 수락 전(정지 중)에 섬 (`badData` = `needReady` ∧ `cmDataBad`) | N4 만 |
| K5 정지가 주소 사유도 붙잡고 슬롯 여유가 전역(`fillPend` 논리합) | 「kind」 만 |
| K6 V=0 커밋이 VPN 유효를 소진 | 「consume」 · N4 · N6 (셋 다 같은 스테이징의 V=0 → V=1 을 쓴다 — 「consume」 만 죽이는 변이는 못 찾았다) |
| K7 채움 적중이 태그를 안 봄 | 「다른 키」 만 |
| K8 산 FRAME 위 재기입 무시 | N5 만 |
| K9 채움 적중이 V 를 안 봄 | N6 만 |
| K10 파티션 1 커밋이 파티션 3 같은 칸을 지움 | N7 · 「다른 키」(전건 행) |
| K10b V=0 커밋이 모든 파티션의 같은 칸을 지움 | N7 만 |

---

### W4 — `0xE14` XLATE_ACTIVE_PART · 결속 파티션 (3.10 v1.0 묶음의 RTL 파도 넷째 하위 파도)

요청 파티션은 이제 최상위 입력 `io_hiuReq_part`(은퇴)가 아니라 `0xE14` 결속이다. 그래서 조회 헬퍼
(`hiu_lookup` · `present_seq`)는 파티션 인자를 **결속으로 만든다** — `bind_part(p)` 가 `0xE14 ← p` 를 쓰고
되읽어 `[7:0]` = p ∧ `[8]` A = 1 을 단언한다(단언하지 않으면 거절된 전환 뒤 조회가 옛 파티션에서 조용히
돈다 — 함정 ⑥ 의 결속 판). 확인한 결속은 부팅마다 잊고 다시 확인한다(`_BOUND`). 옛 37 시험은 몸체 변경 없이
이 헬퍼로 옮겨 37/37 PASS 였다. `xlate_miss_obs_second_stall` 은 p1 → p2 전환을 명시적 `bind_part` 와 D = 1
단언으로 바꿨다. 기대값은 정본 E.1.2 `0xE14` 행 · 「결속 파티션의 수락 판정」 · reset 값 규범에서 유도했다
(시험 파일 W4 절 머리의 축자 인용) — RTL 상수를 import 하지 않는다.

| 시험 | 재는 것 |
|---|---|
| N10 `active_part_ad_table` | (A, D) 네 칸 × 사유 — 드레인됨: 다른 값 교체 · 같은 값 무동작 · 값 거절 A0 D1 + `[6]`. 미드레인(미적중으로 붙든 요청): 다른 값 A0 D0 + `[6]` · 같은 값 A1 D0 fault 없음 · 값 거절 A0 D0. 절단 별칭 5 · 6 · `[31:10]` 비0(같은 값 포함) · 없는 값 4–255 전량. 거절된 전환이 붙든 요청을 옮기지 않는다(관측 `[15:8]`) |
| N10 `active_part_d_sample_edges` | 같은 사이클 접수(요청 접수와 다른 값 기입이 같은 에지 → D0 거절 · 그 요청은 옛 결속으로 응답; 같은 값이면 A1 D0 무fault) · β 모서리(응답이 떠나는 그 에지의 기입 → D1 교체) · 한 사이클 이른 대조(→ D0 거절) |
| `active_part_rmw_ro_ignored` | `[9:8]` 네 값 모두 무시 — 되읽은 워드 되쓰기 수락 · `[9]` = 1 기입이 D 를 만들지 않는다 |
| `active_part_unaligned_outside` | `0xE15`–`0xE17` 쓰기 → `[6]` · 결속 · A · D 각각이 바뀔 수밖에 없는 상태에서 불변 |
| `active_part_judgment_stall` | t+1 한 사이클: HIU 접수 ready (1,0,1,1) · MMIO ready `0xE14` (0,1) · `0xF80` · `0xE04` · `0xE15` · `0x208` (1,1) · 직후 읽기 rvalid 한 번 · 판정 뒤 값 · 정지 사이클 요청 응답 한 번 · 인접 둘 정지 계수 [0, 1]. 시간 모양은 설계 선택(α) 확인이다 — 정본은 응답 시간을 걸지 않는다 |
| N11 `active_part_binds_lookup` | 같은 VPN 을 1 · 3 에 다른 프레임 — 결속만 바꾸면 승인 프레임이 바뀐다 · `io.hiuRsp.part` 메아리 · 빈 파티션 2 결속 → 미적중 · 관측 `[15:8]` = 2 |
| N15 `reset_values_norm` | 전원 reset 과 실행 중 reset 각각 뒤: `0xF80` · `0xE04` · `0xF8C` · `0x320` · `0xE14` · `0xEC4` · `0xEA0` · `0xEC0[7:0]` = 0 · `0x324` = 1 · 파이프 빔 · 스테이징 무효 · 소유권 전 페이지 호스트 · 소거 sweep ≤ 2^16 이고 처음부터. 실행 중 reset 앞에 각 워드가 비0 이었음을 전건으로 단언한다 — `0x320` 만 비0 으로 만들지 못했다(완료 큐 push 원천을 구동하지 않는다 — 한 점 관측) |

**HEAD(f67e3d6) 음성 대조** — 생성물 사본에서 입력 정의역만 HEAD 에 맞추고(`io_hiuReq_part` 를 0 으로 구동)
돌렸다. 새 일곱 + `xlate_miss_obs_second_stall` 이 8/8 FAIL — `bind_part` 단언(되읽기 0 — 쓰기 흡수)에서 운다.
단언을 끈 판에서도 8/8 FAIL 이고 이유가 의도대로다: `0xE14` 쓰기가 흡수돼 되읽기 0 · `[6]` 없음, 붙든 요청의
관측 `[15:8]` = 0(포트 파티션), 포트 파티션 0 이라 결속 1 · 3 의 항목이 미적중(N11 · D 표집 · N15 가 조회
정지에서 막힌다), 판정 정지 없음. N15 의 reset 워드 행은 HEAD 에서도 0 이다(`0xE14` 미구현 — 읽기 0) —
HEAD 에서 N15 가 우는 자리는 결속 축이다.

**변이** (W4 생성물 사본 · 한 자리씩 · Shape 44 전체):

| 변이 | 죽은 시험 |
|---|---|
| K1 값 검사가 `[6:0]` 만 봄 (128–131 … 별칭) | N10 ad_table 만 |
| K2b HIU 점유가 s1 을 세지 않음 (같은 사이클 접수 누락) | N10 d_sample 만 |
| K2c HIU 점유가 s6 을 세지 않음 (떠나기 전 일 누락) | N10 d_sample 만 |
| K2 D 를 기입 사이클 t 에 표집 (β 꼴) | d_sample · binds_lookup + 옛 `xlate_*` 아홉 — `bind_part` 가 앞 응답이 떠나는 바로 그 에지에 수락되는 일이 흔해(β 모서리) 옛 시험이 거짓 거절로 운다 |
| K3 `[9:8]` 엄격 | rmw 만 |
| K4 쓰기 스트로브가 정렬을 보지 않음 | unaligned 만 |
| K5 MMIO 정지 없음 | judgment_stall 만 |
| K5b 정지 중 HIU valid 게이트 없음 | judgment_stall 만 |
| K6 `rsp.part` 메아리가 3 을 1 로 | binds_lookup 만 |
| K7 결속 reset 값 1 | reset_values_norm 만 |
| K8 같은 값도 D 를 요구 | ad_table · d_sample · rmw · unaligned |
| K6b 요청 파티션 0 고정 (HEAD 꼴) | 29 시험 |

### W6 — `0xF0C` FP_SHAPE · OWN_SET 거절과 `[7]` (3.10 v1.0 묶음의 RTL 파도 여섯째 하위 파도)

기대값은 정본 E.1.2 FP_SHAPE 행 · reset 값 규범 6항 · E.1.3 · E.7 6 · 7항에서 유도했다(시험 파일 W6 절 머리의
축자 인용). FP_SHAPE 의 기대는 `0xFFC` 를 *읽어서* 만든다 — 0 이면 워드 전체 0, 아니면 `(1 << 24) | (stepMax << 9) | P`
(P = 10 · stepMax = 32 는 E.1.3 의 RTL 사실 문장). 그래서 판 값 커밋 날 시험은 고칠 것이 없고, 판 0 인 채 비0 을 내는
생성물은 운다. 판 0 동안 rdata 의 *원천*(배선 상수 0 대 예약 읽기 0)은 포트로 가를 수 없다 — assembly 의 몫이다.

| 시험 | 재는 것 |
|---|---|
| `fp_shape_word` (신설) | 소거가 끝난 정상 상태: 읽기 = 판 값 유도 기대 · rvalid 1회 · 재읽기 불변 · fault 없음 · RO 쓰기 셋(전폭 1 · `0x0100_400A` · 0) → 거절 + `[6]` · `[15]` 아님 · 값 · FP_STATUS 불변 · 비정렬 `0xF0D`–`0xF0F` 쓰기 `[6]` · 비정렬 읽기 0 · 표 밖 이웃 `0xF10`–`0xF3C` 정렬 워드 열둘 전부 관대(쓰기 무시 · 읽기 0 — 넷 표본 판은 `0xF14` 별칭 변이를 놓쳤다, W6 검증 OBS-1) |
| `fp_clear_window` ④–⑥ (보강) | 선택자 표 소거 중: `0xF0C` 읽기는 기다리지 않고 rvalid 1회 · 기대 값 · `0xF0C` · `0xF08` 쓰기는 제시 사이클 ready = 1(정지 없음) · 거절 + `[6]` · `[15]` 아님 · fpCfgBadWrite 무관 · 값 불변. 끝에서 loadReady = 0 을 다시 본다(창 안 전건) |
| `own_set_collide` (신설) | 같은 칸 · 다른 태그 프레임 둘(칸 = 프레임 하위 6b — 자극을 거절 쪽으로 보내는 화이트박스, 기대값에는 들지 않는다)과 다른 칸 하나. 하한(빈 표의 첫 OWN_SET 커밋 — 표를 비운 뒤 한 번 더) · 거절 → 무효과(대상 호스트 소유 · 점유자 유지) · `[7]` · `io_fault_ownCollide` · `[6]` 없음 · `[7]` sticky · `[7]` = 1 인 채 다른 칸 커밋 · `0xF84` W1C · 같은 태그 무연산 · OWN_CLR 무거절(점유자 다른 태그 · 회수 · 이미 호스트) · 칸이 빈 뒤 커밋 · 역방향 거절. 전이 대상의 OWN_STATUS 는 전이 수락 바로 다음 사이클의 읽기다(E.7 7항 장치 포트 순서). 끝에 승인 경로 — 거절된 프레임의 자격 허용 읽기는 `[19]` · 커밋된 프레임은 승인 |

**HEAD(b0a4c47) 음성 대조** — `fp_shape_word` · `fp_clear_window` FAIL(`0xF0C` 쓰기가 `[6]` 없이 흡수 — 표 밖 정렬 워드).
`own_set_collide` 는 HEAD 에서도 PASS 다 — OwnershipTable 논리는 W6 이전과 같고 W6 RTL 은 GUARD-MAP 만 더했다. 그 시험의
수락 기준은 아래 변이다.

**변이** (W6 생성물 사본 · 한 자리씩 · Shape 46 전체):

| 변이 | 죽은 시험 |
|---|---|
| F1 `0xF0C` 쓰기의 `surfBadWr` 제거 | fp_shape_word · fp_clear_window |
| F2 판 0 인 채 rdata `0x0100_400A` | fp_shape_word · fp_clear_window |
| F4 디코드 별칭 `wordOff[1:0] == 3` (`0xF1C` · `0xF2C` · `0xF3C` 도 RO) | fp_shape_word 만 |
| F5 소거 중 `0xF0C` 쓰기 정지 | fp_clear_window 만 |
| F6 `0xF0C` 쓰기 거절을 loadReady 로 게이트(소거 중 흡수) | fp_clear_window 만 |
| F7 소거 중 `0xF0C` 읽기 정지 | fp_clear_window 만 |
| F8 소거 중 `0xF08` 쓰기 정지 | fp_clear_window 만 |
| O1 OWN_CLR 이 collide | own_set_collide 만 |
| O2 커밋(빈 칸)이 collide | own_set_collide 만 |
| O3 같은 태그 무연산이 collide | own_set_collide 만 |
| O4 거절 갈래가 점유자를 덮음(축출) | own_set_collide 만 |
| O5 `[7]` 상수 0 | own_set_collide 만 |
| O6 `[7]` 비sticky(매 사이클 해제) | own_set_collide 만 |
| O7 `0xF84[7]` W1C 끊김 | own_set_collide 만 |
| O8 OWN_CLR 이 태그를 안 봄(남의 페이지 회수) | own_set_collide 만 |
| O9 빈 표에서 collide(하한 위반) | own_set_collide 만 |

### W8 — 판 값 커밋 `0xFFC` = `0x0001_0000` · FP_SHAPE 판 게이트 (3.10 v1.0 동결 뒤 첫 장치 변화)

기대값은 정본 문면과 Y4 합의(판 = `(major << 16) | minor`)에서 하네스가 따로 짓는다 — `HIU_ABI_EXPECT = (HIU_ABI_MAJOR 1 << 16) |
HIU_ABI_MINOR 0`(시험 파일 W6 절 머리의 `03-hiu.typ` 1651 행 인용) · `fp_shape_ref(abi)` = 판 0 이면 0, 아니면 `(1 << 24) | (32 << 9) | 10`.
W6 판은 FP_SHAPE 기대를 `0xFFC` 를 *읽어서* 지었다 — 그 꼴은 두 워드가 함께 판 0 으로 되돌아간 생성물(아래 ABI0)을 통과시킨다. 이제
`fp_shape_expect` 는 읽은 판 값을 리터럴과 대조하고 기대는 리터럴에서 낸다.

| 시험 | 재는 것 |
|---|---|
| `abi_version_pair` (신설) | 선택자 표 소거 중과 뒤 각각: `0xFFC` → `0xF0C` · `0xF0C` → `0xFFC` 두 순서로 읽어 붙듦 0 · rvalid 1회 · 값 = 리터럴 기대 · 쌍조건(`0xF0C[31:24]` ≠ 0 ⇔ `0xFFC` ≠ 0 — MMIO 응답만으로) · `0xFFC` RO 쓰기 넷(전폭 1 · 0 · 판 값 그 자체 · major+1) 거절 + `[6]` · 값 불변 · 비정렬 `0xFFD`–`0xFFF` 읽기 0 · fault 없음 |
| `page_disposition` (보강) | `0xFFC` 읽기 = `HIU_ABI_EXPECT`(W6 까지는 「합의 전 0」) · 읽기 fault 없음 |
| `fp_shape_word` · `fp_clear_window` (보강) | 기대를 판 리터럴에서 — 읽은 `0xFFC` 가 리터럴과 다르면 그 자리에서 운다 |

**`ShapeAbi0` 스위트 (신설).** 생성물 `Wt64Top.sv` 의 `assign abiArea_ver = 32'h00010000;` 한 줄만 `32'h0` 으로 바꾼 사본을 빌드 자리에 짓고
(저장소에 쓰지 않는다 · 치환 수 정확히 1 을 요구 — 0 이면 「미측정이지 통과가 아니다」로 실패) `abi_version_pair` · `fp_shape_word` ·
`page_disposition` 셋을 `WT_ABI_MAJOR` = `WT_ABI_MINOR` = 0 으로 돌린다. 그 사본은 `Ident.VERSION` 만 0 으로 바꾼 Spinal elaboration 의
생성물과 바이트 동일하다(rtl/README.md W8 절). 러너는 `testcase` 표로 고른 시험만 세고, 고르지 않은 시험이 skip 이 아니면 실패로 센다.

**변이** (W8 생성물 사본 · 한 식씩 · Shape 는 판 의존 넷(`abi_version_pair` · `fp_shape_word` · `page_disposition` · `fp_clear_window`) ·
ShapeAbi0 셋):

| 변이 | Shape | ShapeAbi0 |
|---|---|---|
| BASE 무변이 | 4/4 PASS | 3/3 PASS |
| GATE_LIT1 — FP_SHAPE 게이트를 판 넷 대신 별도 리터럴 1 에 | PASS (v1.0 에서 포트로 안 갈린다) | fp_shape_word · abi_version_pair |
| ABI_RD_LIT — `0xFFC` 읽기를 판 넷 대신 별도 리터럴 `0x0001_0000` 에 | PASS (같은 까닭) | page_disposition · fp_shape_word · abi_version_pair |
| GATE_LIT0 — 게이트를 리터럴 0 에 | fp_clear_window · fp_shape_word · abi_version_pair | PASS |
| ENC2 · P11 · SM33 — FP_SHAPE 번호 2 · P 11 · stepMax 33 | fp_clear_window · fp_shape_word · abi_version_pair (셋 다 같다) | PASS |
| MAJ2 · MIN1 — 판 `0x0002_0000` · `0x0001_0001` | page_disposition · fp_clear_window · fp_shape_word · abi_version_pair | 치환 0 번 — 스위트 실패(미측정) |
| ABI0 — 판 상수를 0 으로 되돌림(두 워드가 함께 0) | page_disposition · fp_clear_window · fp_shape_word · abi_version_pair | 치환 0 번 — 스위트 실패 |
| ABI_NORD — `0xFFC` 덮어쓰기 탈락 | page_disposition · fp_clear_window · fp_shape_word · abi_version_pair | PASS |
| SH_NORD — `0xF0C` 덮어쓰기 탈락 | fp_clear_window · fp_shape_word · abi_version_pair | PASS |

**HEAD(`1500438`) 음성 대조** — Shape 의 판 의존 넷이 전부 FAIL(`0xFFC` 가 0 · FP_SHAPE 가 0) · ShapeAbi0 은 HEAD 생성물에 판 상수 줄이 없어 치환 0 번으로 실패한다(통과로 세지 않는다). 판 0 변형이 잡는 것은 v1.0 에서 포트로 갈리지 않는 *결합* 결함(GATE_LIT1 · ABI_RD_LIT) — 본선이 잡는 값 결함은 판 0 에서 통과하는 것이 정답이다.

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

## 미측정 원장 — 10축

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
| 7 | `FAULT_STATUS[17]`·`[18]` | `Wt64Top.sv:1717` 「faultWords_status[17] = 1'b0;」 과 다음 줄 `[18]` 상수 0 — 원천 부재. **0 을 「정상」으로 읽으면 안 된다** |
| 8 | `SharedUnit`·`MemOrderGate` 독립 `.sv` 의 top 대표성 | 형상 불일치 — 독립본 16비트 vs top 인스턴스 161/128비트 |
| 9 | OPREF **B** 참조의 LBID 축 | 제시 자체가 없다 — `Wt64Top.scala:86` 「OPREF B 토큰의 RouteJudge 제시는 미배선」 (TODO 2항), `tokIn` 은 사이클당 하나. ISA-2 α 는 **OPREF A 축만** 덮는다 |
| 10 | 변환 조회의 호스트 ABI 층위 | 요청 원천(메모리 파이프) 미착지 — 조회의 VPN · valid 는 내부 포트 `io.hiuReq` 제시이고, 파티션은 `0xE14` XLATE_ACTIVE_PART MMIO 결속이다(W4 — `io_hiuReq_part` 은퇴). `xlate_*` · `active_part_*` 시험의 기입 쪽만 호스트 ABI 오프셋이다 |

(옛 10번 「변환 저장소 관측 세 워드의 값 — 회로 0건」은 파도 4(`9ec42ee`)부터 거짓이었다 — `xlate_miss_observed` 가 잰다. W4 에서 지웠다.)

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
몇 구역에서만 덮인다(구성 구역은 `cfgBlk.io.ready` · 주소 · 상태 적법 XLATE_ENTRY_COMMIT 쓰기는 하류 `installSlotFree`). 예약 오프셋(예: `addr=0`)에서 폴링하면
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

**Shape 판 (W1, 2026-10-11)** — `test_shape_equiv.py` 에는 같은 검사가 없었다
(`zero_inputs` 가 손으로 고른 이름만 0 으로 두고, 그 밖의 새 입력은 조용히 0 으로 남았다).
3.10 RTL 파도는 최상위 입력을 빼고(`io_hiuReq_part` — W4 에서 은퇴) 더하므로, 이제 `zero_inputs`
가 생성물 머리의 `input` 이름 전량을 `SHAPE_INPUTS`(+ 접두로 거두는 `io_faultClear_*`)와
**등식으로** 대조한다 — 누락 · 잉여면 전 시험이 죽고, 파서가 `input` 줄을 흘렸는지(줄 수 등식)도
먼저 본다. 변이 실측(2026-10-11, W1 생성물 사본 · Shape 스위트 전체): 쓰이지 않는 입력 하나
(`io_mutIn`) 추가 · 입력 하나(`io_mem_slotSel`)를 포트 목록에서 빼 내부 상수로 · `input` 줄 하나의
들여쓰기 변경 — 셋 다 부팅하는 23 시험 전부가 각각 「누락 ['io_mutIn']」 · 「잉여 ['io_mem_slotSel']」 ·
「input 줄 120 중 119 만 읽었다」 로 죽고, 부팅하지 않는 `compare_face_is_pinned` 하나만 통과했다 —
검사의 자리는 `zero_inputs` 하나이고 `boot` · `boot_hiu` 가 둘 다 부른다.

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

---

## W3 수정 (2026-10-13) — 독립 검증 결함 처분

W3 독립 검증(생성 SV 변이 54)에서 **formal 만 잡고 Shape 스위트를 통과한 변이 셋**을 시험이 잡게 했다.
기대값은 형상과 무관하다(커밋한 VPN 은 적중 · 커밋하지 않은 VPN 은 미적중 · 다른 파티션의 flush 는
스테이징에 닿지 않는다). 자극만 참조 형상에서 같은 칸에 떨어지도록 하위 4b 를 맞췄다.

| 변이 (생성 SV 자리) | 그 전 | 지금 죽는 시험 |
|---|---|---|
| M26 저장 적중 태그 비교가 `[15:0]` 만 | Shape 통과 (door · xlatestore 만) | `xlate_high_vpn_bits_distinguish` 만 |
| M43 설치 태그 `[27]`(= VPN[31]) 0 고정 | Shape 통과 (assembly `a_door_install` 만) | `xlate_high_vpn_bits_distinguish` 만 |
| M13b `stgFlushDrop` 의 파티션 비교가 bit0 만 | Shape 통과 (props · door · assembly 만) | `xlate_other_flush_keeps_staging`(새 행 — 래치 1 · flush 3) 만 |

실측: rsync 사본(생성물 = 저장소 W3 생성물)에 변이 하나씩 · Shape 37 전체 — 셋 다 36/37(위 열 하나만 FAIL).
무변이 저장소 `make rtl-sim` 49/49 (Mask 12 · Shape 37).

**측정 불가로 판정된 축 — 「주소 · 상태 사유 COMMIT 이 정지를 기다린다」.** 채움 대기는 설치 다음 사이클에
무조건 비워지므로 찬 슬롯을 만나는 COMMIT 은 직전 사이클에 수락된 같은 파티션 COMMIT 의 스테이징을 그대로
갖는다 — 늘 주소 · 상태 적법이다. 그 축을 어기는 변이(M04 · M04b · M28)는 Shape 와 door.sby(prove_stall
무계 증명 포함)를 통과한다 — 합성 RTL 에서 관측되지 않는다. 수락 근거는 하류 슬롯을 절단한 하네스
(`XlateStaging/props.sby` `p_need_iff` · `Wt64Top/assembly.sby` `a_ready_only_slot` · `a_door_ready`)이고,
`xlate_commit_addr_reject_no_wait` 는 그 처분의 값 수준 회귀 기록이다.
