<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# WT64v1 재구현 — 선-formal 모델

정본 `docs/wt64v1-architecture-guide` §6.3 이 구속력 있는 순서를 못박는다:

> 선-formal → RTL → 후-formal. **1단을 건너뛴 모듈은 완료로 간주하지 않는다.**

여기가 그 1단이다. **RTL 보다 먼저 있다.**

```sh
make rtl-formal        # 또는  sh rtl/formal/tla/run.sh
```

기존 `proofs/tla/` (ACC bank) 와 **분리**돼 있다 — 규약은 승계하되 게이트
계보는 건드리지 않는다.

## 속성 현황

| 속성 | 모델 | 상태 |
|---|---|---|
| **FAB-2** 공유 자원 배타성 + 무처분 없음 | `SharedUnit.tla` | **증명됨** |
| **FAB-3** 기입 자격 · **FAB-4** 소유 구간 | `ResultBank.tla` | **증명됨** |
| **HIU-1 · 2** 격리 · flush 후 미적중 (HIU-4 는 W3 에서 `XlateSurface.tla` 로 옮겼다) | `XlateStore.tla` | HIU-1 · 2 **증명됨** — HIU-4 로 인용되던 `Inv_AtMostOneCandidate` 는 항진이라(정본 부록 D 사실 정정 2026-10-11) 3.10 v1.0 묶음 RTL 파도 W3 (2026-10-13, DP-12 사용자 확정)이 정의와 cfg 의 `INVARIANT` 줄을 지웠다(run 수 7 불변 · 줄 수 176 보존 — 지운 자리는 주석). HIU-4 의 증명 거처는 `XlateSurface.Inv_AtMostOneValidPerVpn` (아래 행) |
| **HIU-3** 유효 게이팅 전수 | `XlateStore.tla` | **부분 증명** — 전수성은 정적 검사 몫 |
| **ISA-3 · ISA-4 · ISA-8** 전역 미스만 fault · 계층당 1회 · 사상 축 | `Route.tla` | **부분 증명** (시간축·귀납 기계증명 비었음) |
| **HIU-8 · HIU-9 · HIU-10** 플랫폼 독립 · 소유권 배타성 | `Platform.tla` | **증명됨** — 3.10 v1.0 묶음 RTL 파도 W1 의 선-formal(2026-10-11 — 파도 착지 2026-10-12): HIU-10 의 「loud」 를 원인별 보고(자격 거부 `[4]` · 자격 허용 ∧ 비소유 `[19]`)로 가른 가드 넷 · 불변식 일곱을 더했다 — 가드 여덟 · 23 run (아래 절) |
| **SEC-3** 무소실 | `NoLoss.tla` | **증명됨** |
| **EXT-1 · EXT-2 · EXT-3** 순회 종료성 · 종료 후 무효과 · 검산 독립 | `Walk.tla` | **증명됨** |
| **FAB-1 · FAB-9 · FAB-10 · FAB-5 · FAB-6** 단일 생산자 · 병합 게이팅 · 소비자 무결성 · 무손실 · 진행성 | `Fabric.tla` | **증명됨** — FAB-6 의 공정성 가정은 §2.6 진행 전파 규범이 계약으로 승격 |
| **SEC-4 · HIU-11** 격리(비간섭) · 선택적 경로 중립 | `Isolation.tla` | **증명됨** |
| **EXT-4** 재조립 배타성 | `Payload.tla` | **증명됨** |
| **EXT-6** 메모리 순서 (명시적 순서 의존) | `MemOrder.tla` | **증명됨** — 과잉 게이팅 금지가 §4.4.4 규범으로 승격 |
| **SEC-2 · SEC-7** 경로 간 동일성 · 예약 필드 불투과 | `Decode.tla` | **증명됨** |
| **E.1.2 임대별 마스크 키 · MASK_REKEY · FAULT_STATUS `[12]` 논스 재사용 판정 · `0xEC4` MASK_DUP_CAPTURE** | `Mask.tla` | **증명됨** — 가드 열둘(키 · 재키잉 넷 + W1 여덟) + 증인 열넷 + 짝 1, 29 run. 축 모델. 대형 cfg 는 `VIEW StateView`. 짝 「오늘의 RTL」(W1 전 RTL — HEAD 3b80087)이 `Inv_CapIffDup` 을 깬다 (아래 절) |
| **E.1.2 CAP_STATUS/CAP_CLEAR** 축 격리 · sticky · 예약 위반 원자 거절 · 발화 우선 | `CapWord.tla` | **증명됨** — 가드 넷(axis_isolated · sticky_until_clear · clear_atomic · set_beats_clear) + 증인 넷, 9 run. 축은 불투명 토큰 넷 — 사건→축 배정은 정본 표의 몫 |
| **E.1.2 · E.3 변환 저장소의 MMIO 문** `0xC00` 형상 비노출 항목 표면(VPN · FRAME · COMMIT · VPN_HI · 예약-엄격 28 워드) · 스테이징 (f) · 커밋 결과 (a)(b)(c)(g)(h) · **HIU-4** 적중 유일성 · **HIU-2** V=0 축 · 하류 정지 처분 · `0xE00` flush 발화·범위 · `0xE10` 해제 · RO 쓰기 거절 · 거절 loud | `XlateSurface.tla` | **증명됨** (모델 위) — 3.10 v1.0 묶음 RTL 파도 W3 (2026-10-13) 재작성(앞판은 파도 3 · 4 의 LO/HI 직접 배열 문 — 아래 절은 그 기록). 가드 스물아홉(개명 여섯 · 신설 열 · 유지 열셋 — commit_fires · commit_base_match · commit_needs_vpn · commit_whole · commit_v_carried · frame_stages_only · commit_replaces_vpn · vpn_drops_frame · commit_needs_frame · frame_pair_check · vpnhi_strict · rsvw_rejected · commit_rsv_strict · evict_in_partition · evict_on_commit_only · stall_independent · flush_fires · flush_scoped · flush_valid_only · flush_part_exists · flush_rsv_strict · flush_drops_staging · ent_part_exists · reject_loud · mclr_fires · mclr_needs_one · mclr_rsv_strict · mclr_keeps_stall · ro_rejected) + 증인 스물여덟 + 짝 여섯 · 대안 일곱 · 발견 1 + 진행 1, 77 run (좋은 cfg 다섯 — 작은 · 대형 · 칸 2 · 칸 2 × 파티션 2 · 형상 밖 기저). 새 고정 속성 일곱 `Inv_AtMostOneValidPerVpn`(HIU-4 — 칸 1 cfg 에서는 공허, 반증력은 칸 2 cfg 둘 · `del_commit_replaces_vpn` · `pair_host_index`) · `Prop_V0Misses`(HIU-2 V=0 축) · `Prop_StallDataBlind` · `Prop_AddrRejectNoWait` · `Prop_HoldInert` · `Prop_RejectInert` · `Prop_CommitScoped` · 유지 `Prop_StallEnds`(하류 정지 유계 · 진행) · `Prop_TableByDoor`(W3 부터 칸 2 cfg 에도 걸리고 `del_evict_on_commit_only` 가 반증). 대안 상수 `RefuseDomain` = full · kind 가 정지 판정의 데이터 무관을 반증으로 받친다. 라벨이 HIU-1/2/3 · HIU-4 를 인용해 색인 모델로 센다 (부록 D 「모델 13개」). 실측: XlateSurface 절 77/77 선언대로 · 전량 배터리 600/600 선언대로 — 컨테이너 · 2026-10-13 18:37–19:58 KST · 게이트 GREEN(`run.sh` 종료 코드 0 경로) · 이탈 0 · 입력 sha 620건 불변 (부록 D 문장과 같은 판) |
| **E.1.2 · E.12 · E.12.1 재조립 문맥 소거의 문** `0xF40` 스테이징 세 워드 · 워드 적법성(TAG1 poison·trace·예약 · TAG2/FIRE 예약 · RO 쓰기) · 거절의 무효과·loud · 워드별 무장 · 재기입 덮음 · 발화 성립(무장 완비 · `[0]`=1) · 잔류 소진 | `AbortSurface.tla` | **증명됨** — 가드 열셋(poison_trace_zero · epoch_word_rsv_strict · shape_word_rsv_strict · fire_rsv_strict · ro_rejected · legal_first · reject_loud · arm_on_accept · arm_own_word · stage_writes_value · fire_needs_armed · fire_needs_one · fire_drains_arm) + 증인 열하나 + 짝 셋 · 대비 1, 30 run. 축 모델. sub-word 처분은 상수 `Subword`(판정 T2 — RTL 은 W4). 짝 둘이 D2 이전 RTL(TAG1 무검사)과 동형 |
| **3.7 · 3.10 · E.1.1 · E.1.3 구성 페이지의 처분** 포트 수락·응답 · RO 쓰기 · WO 읽기 · 예약 오프셋(정렬 워드) · 비정렬 쓰기 · 물려받은 `0x000`–`0x11F` · rw 부류(W4 부터 `0xE14` XLATE_ACTIVE_PART 도 — 그 기입의 의미는 `ActivePart.tla`, 값 거절은 `bad` 에 접힌다) · 소비 회로 없는 RW 워드(W3 부터 `0xC00` 예약-엄격 28 워드 — XlateSurface 의 rsvw — 도 이 부류: 쓰기 거절 + `[6]` · 읽기 0) · 거절 loud | `MmioPage.tla` | **증명됨** — 가드 아홉(rsp_on_accept · effect_on_accept · ro_rejected · wo_read_zero · resv_lenient · unaligned_rejected · leg_write_rejected · nocons_rejected · reject_loud) + 증인 열 + 짝·대안 여덟 · 대비 1, 29 run. 축 모델. 고정 속성의 예외 집합(SpecReject · SpecQuiet)이 곧 판정 내용이라 판정을 유도하지 못한다. 짝 둘이 D1 이전 조립과 동형. W4 (2026-10-15)는 주석 셋만 — run 29 불변 |
| **E.1.2 · E.3 변환 미적중의 관측면** `0xE04` XLATE_STATUS · `0xE08`/`0xE0C` XLATE_MISS_VPN 의 *값* — 정지 게이트 스냅샷(정지 중에만 그 요청 · 정지가 없으면 0) · 찢김 없음 · 읽기 무해제 · 채널의 충분성 · **3.6.2 판정 시점과 판정 래치**(W2) | `XlateObs.tla` | **증명됨** (모델 위) — 가드 아홉(obs_stall_live · obs_sticky · obs_part_stalled · obs_vpn_stalled · obs_no_residue · obs_read_pure + W2 verdict_latch · latch_clears_on_leave · latch_one_value) + 고정 속성 Prop_NoTear · Prop_LatchedSurvivesRetract · Prop_V0AfterEdgeMisses · 진행 Prop_StallResolves(「정지한 *그* 요청은 결국 떠난다」 — 요청 꼬리표 tok · 폴링 호스트 HostSpec · 경쟁자 · 하류 배압) + 증인 열셋 + 대안 다섯 · 고정 속성 반증 둘 · 진행 짝 셋 · 짝 셋 · 대비 셋, 41 run (W2 전 22). 축 모델. 짝 「파도 3 까지의 RTL」(세 워드 읽기 0)이 정지 영구로, 짝 「오늘의 RTL」(W2 전 RTL — HEAD 9b6eee6, 래치 없음)이 재미적중으로 운다 |
| **E.1.2 · 3.7.2 결속 파티션** `0xE14` XLATE_ACTIVE_PART — 요청 파티션 = 접수 시점의 결속 · 값 검사 먼저 · 다른 값은 D = 1 일 때만 교체 · 같은 값은 fault 없는 무동작 · 수락마다 (A, D) · D 는 수락 에지 직후 상태(같은 사이클 접수 포함) · 판정 사이클의 요청 · MMIO 정지 · 비정렬 무효과 · 거절 loud | `ActivePart.tla` | **증명됨** (모델 위) — 3.10 v1.0 묶음 RTL 파도 W4 (2026-10-15) 신설. 가드 열둘(value_first · rsv_strict · ro_field_ignored · drain_gates_switch · same_value_noop · ad_every_accept · d_includes_same_cycle · pend_stalls_req · pend_stalls_mmio · req_part_from_bound · unaligned_outside · reject_loud) + 고정 속성 여섯(Inv_ObsIsSpec · Inv_WorkUnderBound · Prop_NoStaleWorkAfterSwitch · Prop_LoudOnlySpec · Prop_A0D1IsValueReject · Prop_StallOnlyPend — 전부 상주 음성 run) + 증인 열여덟 + 짝 셋(W4 전 RTL 두 꼴 — 쓰기 흡수 · 포트 결속 · 기각한 「같은 값 ∧ D = 0 → 거절」) + 대안 여섯(D 표집 β 넷 — 정본 어긋남 · 거짓 loud · 격리 몸 PASS · 같은 에지 퇴장 전환 불가 PASS · lag · 정지 hold), 44 run. 축 모델. DP-4 α 의 근거가 β 반례다 (아래 절) |

순서는 부록 D.5 규범 그대로다 — **근거는 "실제로 무너진 곳"** 이다.

## FAB-2 — `SharedUnit.tla`

정본 §2.7 의 진술:

> 공유 유닛은 어느 시점에도 최대 하나의 요청을 처리한다. 점유 중 도착한
> 요청은 규정된 처분(대기/거절/오류) 중 하나를 **반드시** 받는다 —
> **무처분이 없다.**

처분은 §2.2 에서 **대기**로 확정됐다. 모델은 보류 자원 + 배압을 표현한다.

### 8 run 의 구성

| # | run | 판정 | 무엇을 말하는가 |
|---:|---|---|---|
| 1–2 | 좋은 모델 (깊이 1·요청자 3 / 깊이 2·요청자 4) | MUST PASS | 계약이 일관적이다 |
| 3 | 가드 삭제 `busy_check` | MUST FAIL → `Inv_Exclusive` | 점유 검사가 배타성을 지탱한다 |
| 4 | 가드 삭제 `queue_room` | MUST FAIL → `Inv_NoLoss` | 자리 검사가 조용한 덮어쓰기를 막는다 |
| 5 | 가드 삭제 `backpressure` | MUST FAIL → `Inv_NoUndisposed` | **배압이 무처분을 막는 유일한 것** |
| 6 | 증인 `NoQueueing` | MUST FAIL | 경합이 실제로 일어난다 |
| 7 | 증인 `NoBackpressure` | MUST FAIL | 보류 자원이 실제로 가득 찬다 |
| 8 | 증인 `NoCompletion` | MUST FAIL | 처리가 실제로 끝난다 |

실측: 좋은 모델 62 / 308 distinct states.

## FAB-3 · FAB-4 — `ResultBank.tla`

기입 자격과 소유 구간. `L` 은 **상수가 아니라 파라미터**다 (정본 §2.4) —
`L=1` 과 `L=2` 로 각각 돌려 결론이 값에 의존하지 않음을 확인한다.

| # | run | 판정 | 무엇을 말하는가 |
|---:|---|---|---|
| 9–10 | 좋은 모델 (L=1 / L=2) | MUST PASS | 1089 / 4356 distinct states |
| 11 | 가드 삭제 `owner_check` | MUST FAIL → `Prop_WriteQualified` | **FAB-3 그 자체** |
| 12 | 가드 삭제 `acquire_free` | MUST FAIL → `Prop_IntervalStable` | 구간 안에서 소유자가 바뀐다 |
| 13 | 가드 삭제 `interval_end` | MUST FAIL → `Inv_IntervalBounded` | 구간이 끝나지 않는다 |
| 14–16 | 증인 (소유 · 기입 · 구간 만료) | MUST FAIL | 셋 다 도달 가능 |

FAB-3 은 **행위 속성**이다 — "값이 바뀐다" 는 상태 하나로 말할 수 없으므로
불변식이 아니라 `[][...]_vars` 로 적었다. 정본 §6.5 의 「전이 조건」 문체이며
*허용되지 않는 변화를 함께 적는* 형태다.

### 이 모델이 가르친 것 두 가지

**① 방어적 캡이 가드를 무력화했다.** 처음에 `Tick` 에서 나이를 `L` 로 캡했더니
`interval_end` 가드 삭제 실험이 **조용히 통과했다** — 캡이 그 가드가 막아야 할
상태(나이가 구간을 넘음)를 *표현 불가능하게* 만들었기 때문이다.
검출하려는 것을 표현할 수 없게 만드는 방어는 방어가 아니다.
§6.3.2 의 "지워도 통과하는 가드는 불필요하거나 속성이 부실하거나" 에서
**후자**였고, 가드 삭제 실험이 아니었으면 몰랐을 것이다.

**② 「마지막 기입자」는 구간 단위 개념이다.** 정본 §2.4 계약 3항이 요구하는
"누가 이기는가" 는 FAB-4 아래에서 겨룰 일이 없어 공허하다. 좋은 모델이
반증된 반례가 그것을 말했고, 정본에 환류했다.

### 왜 가드 삭제가 필요한가

모델이 속성을 통과했다는 사실만으로는 **그 속성이 무언가를 실제로 잡는지**
알 수 없다. 항상 참인 속성은 항상 통과한다 (§6.3.2).

각 가드를 지웠을 때 **그 가드 자신의 불변식**이 무너지는 것이 핵심이다.
셋이 서로 다른 불변식을 깨뜨린다는 사실이, 셋이 서로 다른 것을 지탱하고
있다는 증거다.

### 왜 증인이 필요한가

좋은 모델이 통과하는 이유가 *"계약이 위험을 담고 있어서"* 인지
*"설정이 그 위험을 한 번도 만들지 않아서"* 인지를 가른다. 후자면 그 통과는
아무것도 뜻하지 않는다 — §6.7 이 지목한 **"조건이 안 맞으면 스스로 건너뛰고
통과로 보고하는"** 검사와 같은 형태다.

증인은 위험이 **결코 일어나지 않는다**는 불변식이고, TLC 가 그것을 반증하는
것이 곧 도달성 증명이다.

## 반례는 버리지 않는다 (§6.3)

증인 3건이 낸 반례는 RTL 단계의 **지향 테스트 씨앗**이다. 각각이 하네스가
반드시 만들어야 할 시나리오를 말한다:

1. **경합** — 유닛이 점유 중일 때 두 번째 요청이 도착해 대기에 든다.
2. **배압** — 점유 + 보류 자원 만석 상태에서 세 번째 요청이 도착한다.
   이 상태에서 요청이 사라지면 안 되고, 배압 표시를 받아야 한다.
3. **진행** — 대기에 들었던 요청이 유닛이 비면 실제로 처리된다 (기아 없음).

RTL 이 아직 없으므로 지향 테스트로 **변환**하는 것은 단계 2 의 일이다.
시나리오 자체를 여기 적어 두는 이유는 정본 §6.3 이 적듯 *"반례를 보고
설계를 고친 뒤 반례를 폐기하면 같은 결함이 재발했을 때 아무도 모르기"*
때문이다.

## 모델링 규약

- **속성은 모델과 같은 파일에** 둔다 (§6.3.1). 떨어져 있으면 계약이 바뀔 때
  속성이 따라오지 않는다.
- 상수는 **유한·소형**으로 유지한다. 요청자는 **불투명 토큰**이며 내부 구조가
  없다 — 그 제약이 좋은 인코딩을 강제하고, ISA 를 형상 독립으로 만든 근거와
  같은 방향이다 (§6.7 해설).
- 종료는 **모델에 명시**한다. `CHECK_DEADLOCK FALSE` 로 검사를 끄면 정당한
  종료와 함께 *의도치 않은 교착*까지 못 잡게 된다 — 검사를 약화시켜 통과시키는
  것은 이 프로젝트가 경계하는 습관 그대로다.
- `-workers 1` **PIN**. 여러 워커에서는 BFS 방문 순서가 스레드 스케줄에 의존해
  MUST-FAIL run 의 상태 수가 재현되지 않는다.

## HIU-1 · 2 · 3 · 4 — `XlateStore.tla` (HIU-4 는 2026-10-13 W3 에서 `XlateSurface.Inv_AtMostOneValidPerVpn` 로 옮겼다 — 위 표)

넷을 한 모델에 둔 이유는 넷이 **같은 구조 위의 성질**이기 때문이다. 따로 쓰면
저장 블록을 네 벌 모델링하게 되고 그 네 벌이 드리프트한다.

핵심은 정본 §3.6.3 — 이 장에서 가장 중요한 규범이라고 적힌 것:

> flush 는 **유효 비트만** 지운다. 저장 블록의 태그·변환 데이터는 지워지지
> 않는다. ⇒ **유효 비트가 유일한 방벽이다.**

그래서 모델은 flush 가 데이터를 **남기도록** 만든다. 데이터를 함께 지우는
모델은 HIU-2 를 자명하게 통과시키고, 그 통과는 아무것도 뜻하지 않는다.

| # | run | 판정 | 무엇을 말하는가 |
|---:|---|---|---|
| 17–18 | 좋은 모델 (파티션 2 / 3) | MUST PASS | |
| 19 | 가드 삭제 `valid_check` | MUST FAIL → `Inv_ValidGated` | **HIU-3 그 자체** |
| 20 | 가드 삭제 `partition_check` | MUST FAIL → `Inv_PartitionIsolated` | HIU-1 |
| 21 | 증인 `NoHit` | MUST FAIL | 적중이 실제로 일어난다 |
| 22 | 증인 `DataSurvivesFlush` | MUST FAIL | **flush 후 데이터가 실제로 남는다** |
| 23 | 증인 유효성 (`flush_keeps_data` 삭제) | **MUST PASS** | 아래 |

### 23번이 왜 MUST PASS 인가

22번이 반증됐다는 사실만으로는 *증인이 옳은 것을 재는지* 알 수 없다.
데이터를 지우는 모델에서 그 증인이 **성립하는지**를 짝으로 확인한다 —
성립한다면 22번의 반증은 **데이터가 실제로 남기 때문**이지 증인이 부실해서가
아니다. 두 run 을 짝으로 읽어야 HIU-2 의 통과가 자명하지 않음이 확정된다.

### HIU-3 은 여기서 끝나지 않는다

정본 §3.12 함정: *"모든 읽기 경로" 는 유한하고 열거 가능하므로 이 속성은
정적 검사로 완전히 확인할 수 있다.*

이 모델이 보이는 것은 게이팅이 **있을 때** 격리가 성립한다는 것이다. 구현에
그 게이팅이 **빠짐없이** 있는지는 모델이 답할 수 없다 — 모델에는 읽기 경로가
하나뿐이기 때문이다. 그 전수성은 설계가 착지한 뒤 정적 검사가 답한다.
그래서 부록 D 에서 HIU-3 만 **「부분 증명」**으로 적었다. 증명됨으로 적으면
없는 확신을 적는 것이 된다.

## ISA-3 · ISA-4 — `Route.tla`

route fault 의 판정 주체와 범위. 표적은 §1.6.3 함정이 *"이 규범의 전부"* 라고
적은 두 낱말의 구분 — **지역 비소유(정상) vs 전역 미스(fault)**.

### 이 모델이 정본의 모순을 찾았다

ISA-3 은 *"합집합에 속하는 LNID 를 가진 토큰은 route fault 를 밟지 않는다"* 로
적혀 있었다. 그런데 §1.6.3 의 발화 조건은 **둘**이다 — LNID 합집합 미스와
LBID 미사상. 따라서 LNID 는 합집합에 있는데 LBID 가 미사상인 토큰은
*fault 를 밟으면서 ISA-3 을 위반한다.*

ISA-3 을 그대로 옮긴 불변식이 LBID 축을 넣자마자 반증됐고, **반례가 가리킨
것은 모델의 결함이 아니라 문서의 결함이었다.** 원인은 두 독립 축을 하나의
속성에 욱여넣은 것이다. 정본에서 ISA-3 을 LNID 축으로 좁히고 사상 축을
**ISA-8** 로 분리해 환류했다 (속성 39 → 40).

16 run: 기저 3(깊이 1·2·3) + 형상 sweep 2 + 가드 삭제 **6** + 증인 4 + 짝 1.

### 이 모델은 적대적 검증을 거쳤다

세 렌즈(정본 충실성 · 공허성 · 형상 독립성)로 독립 반증을 시도했고
**blocking 3건**이 나왔다. 셋 다 "통과하고 있었지만 아무것도 뜻하지 않던" 것이다.

| 지적 | 내용 | 처분 |
|---|---|---|
| B1 | 모든 cfg 가 이름·뱅크·지점 2/2/2 고정 — 형상 sweep 이 깊이 축에만 | 이름 4·지점 2 / 이름 3·지점 3 추가 |
| B2 | `Points={d1}` 축퇴에서 `del_global_judge` 가 조용히 통과 | `ASSUME Cardinality(Points) >= 2` |
| B3 | **`Inv_MissAlwaysFaults`(INV-T3)가 배터리의 어떤 형상에서도 반증 불가** | `loud_fault` 가드 신설 |

B3 이 가장 아프다. INV-T3 무언 드롭 금지는 정본이 *"이 프로젝트가 반복해서
진 실패형"* 이라 부르는 축인데, 그 속성을 지탱하는 가드가 없어 **속성이
언제나 참이었다.** 이 README 가 스스로 적은 교훈 ①(방어적 구성이 가드를
무력화)의 재발이다 — 같은 실패를 다른 옷을 입고 두 번 했다.

M5 도 실질적이었다: `|Names| = |Points|` 인 형상에서는 구성이 끝나면 합집합이
이름 공간 전체가 되어 **LNID 미스가 원리적으로 도달 불가**가 된다.
정본 §1.2 가 형상 sweep 을 "유일한 직접 검사" 라 부르는 이유가 이것이다.

### 2차 적대 검증 — 「무엇을 표현할 수 없는가」

1차가 *속성이 공허한가* 를 물었다면, 2차는 **모델이 결함형을 표현할 수 있는가**
를 물었다. material 3건이 나왔고, 셋 다 **가드가 아니라 모델링 선택**이었다 —
지울 가드가 애초에 없었으므로 가드 삭제 실험으로는 영원히 잡히지 않는다.

| 지적 | 표현 불가였던 것 | 처분 |
|---|---|---|
| M2 | `Inv_ScopeLocal` 이 액션과 **같은 술어**(`AnyMiss`)로 적혀 액션을 되풀이할 뿐이었다 | 어휘 분리 + **쌍대 형태**로 재진술 |
| M3 | 진입점의 합집합 뷰가 **변수가 아니라 정의**라, 뷰와 표가 어긋나는 일이 정의상 불가능 | `view` 변수 승격 + `view_sync` 가드 |
| M4 | `ConfigOwn` 의 서로소 조건이 **미판정 가드** — 정본에 근거가 없는데 모델이 가정 | `unique_owner` 가드 + 정본 B.5 미결 등재 |

**M2 와 M3 은 한 수정으로 함께 풀렸다.** 뷰를 변수로 만들자 불변식은 *실재*
(`ScopeUnion`)를, 액션은 *뷰*(`view[s]`)를 보게 되어 어휘가 자연히 갈라졌고
자기지시성이 사라졌다. 그리고 그 분리가 없었다면 `view_sync` 삭제 실험도
무의미했을 것이다 — 불변식이 액션과 같은 뷰를 봤다면 스큐가 *양쪽에 동시에*
반영돼 아무것도 깨지지 않는다.

M3 이 겨눈 것은 정본 §1.6.3 이 "합집합 표를 갖든 하위의 적중 신호를 OR 로
모으든 구현은 자유" 라고 열어 둔 갈래다. 후자를 고르면 뷰는 **조합 신호**가 되고
그 극성·스큐가 새 결함형이 된다. 정의로 둔 모델은 그 갈래를 **볼 수 없었다.**

### 교훈 ② — 표현 불가능한 결함은 검출 불가능하다

가드 삭제 실험은 강력하지만 **모델이 이미 표현할 수 있는 것만** 시험한다.
FAB-3 의 방어적 캡(교훈 ①)도, 여기의 정의-대-변수도, `loud_fault` 부재(B3)도
전부 같은 형태다 — *지울 가드가 없어서 통과했다.* 그래서 가드 삭제 실험 다음에
반드시 물어야 하는 질문이 하나 더 있다: **"이 모델에서 표현할 수 *없는* 결함은
무엇인가?"** 이 질문에 답하지 않은 모델은 전수 검사를 했다고 말할 수 없다.

### 증인은 「구성된 기계」에서 도달해야 한다

`Configured(s) == ScopeUnion(s) # {} /\ bankMap # {}` 를 증인에 합취했다.
구성 전에는 모든 소유 집합과 사상표가 비어 있어 전부 fault 이므로(§1.5),
그 상태로 반증된 증인은 정본이 이미 자명하다고 선언한 것을 다시 말할 뿐이다.

### 왜 「부분 증명」인가

두 가지가 열려 있다.

1. **진입점의 합집합 뷰가 상태가 아니다.** `ScopeUnion(s)` 는 변수가 아니라
   정의라서 owns 로부터 매번 재계산된다. 그래서 §1.6.3 1항이 요구하는
   *"진입점의 뷰"* 와 지점별 표가 **어긋나는 일이 정의상 불가능**하다.
   정본이 명시적으로 허용한 두 구현 중 「하위 적중 신호 OR」 갈래의 대표
   결함형(극성·스큐)이 정확히 그 어긋남인데, 이 모델은 그것에 눈이 멀다.
2. **깊이 귀납은 논증이다.** 기저(TLC)와 비간섭(`Inv_ScopeLocal`)은 검사됐으나
   임의 깊이는 그 둘 위에 선 논증이며 TLAPS 기계 증명이 아니다.
   그리고 `Inv_ScopeLocal` 은 액션과 같은 어휘로 적혀 있어 *정의 층위* 결합에는
   눈이 멀다 — 액션 층위 결합만 잡는다.

⇒ 「증명됨」으로 적으면 없는 확신을 적는 것이다. HIU-3 과 같은 등급이되
이유는 다르다: HIU-3 은 *전수성*이 비었고, 여기는 *진입점 뷰*와 *귀납의 기계
증명*이 비었다.


## HIU-8 · HIU-9 · HIU-10 — `Platform.tla`

정본 §3.12 의 진술:

> **HIU-8** 같은 가상 주소에 대한 변환 결과는 호스트 변환 서비스의 가용
> 여부에 **의존하지 않는다.**
> **HIU-9** 캐시 일관 상호연결이 없는 구성에서도, 소유권 규약을 지킨
> 접근열의 관측 결과는 일관 상호연결이 있는 구성과 **같다.**
> **HIU-10** 어느 시점에도 한 페이지의 소유자는 최대 하나다.

### 이것은 관계 속성이다 — 앞의 넷과 성격이 다르다

`SharedUnit` · `ResultBank` · `XlateStore` · `Route` 의 속성은 전부 *한 기계
안의* 성질이었다. HIU-8·9 는 **두 실행의 비교**다. 그래서 기계 하나를
모델링해 "잘 돈다" 를 보이는 것으로는 **아무것도 증명되지 않는다** —
플랫폼 종속은 기계가 고장나는 것이 아니라 *플랫폼에 따라 다르게 도는 것*
이기 때문이다.

모델은 두 세계를 함께 들고 간다:

| 세계 | 호스트 변환 서비스 | 캐시 일관 상호연결 |
|---|---|---|
| `plain` | 없음 | 없음 |
| `rich` | 있음 | 있음 (write-through 로 추상) |

그리고 모든 동작을 **같은 인자로 두 세계에 동시에** 건다. 입력이 같지
않으면 출력 비교가 무의미하므로 이 lockstep 이 모델의 전제 전부다.
두 세계는 *플랫폼 능력에서만* 다르다.

23 run: 기저 1 + 형상 sweep 2 + 가드 삭제 9 + 증인 9 + 짝 「오늘의 RTL」 1 + 대비 1 (3.10 v1.0 묶음 RTL 파도 W1 전에는 12 run: 기저 1 + 형상 sweep 2 + 가드 삭제 4 + 증인 5 — 아래 「W1」 절이 더한 것이 가드 넷 · 삭제 run 다섯 · 증인 넷 · 짝 · 대비다).

| 가드 | 지우면 | 정본 근거 |
|---|---|---|
| `xlate_local` | rich 의 변환표가 plain 보다 커진다 → `Inv_SameTranslation` | §3.3.1 이 기각한 대안 그 자체 |
| `flush_on_handoff` | plain 만 낡은 값을 들고 남는다 → `Inv_SameObservation` | §3.4.1 3번 「넘기는 쪽이 비운다」 |
| `state_machine_kept` | rich 가 상태 기계를 생략한다 → `Inv_SameFaultPolicy` | §3.4.1 규범 「일관성이 있어도 규약은 남는다」 |
| `owner_check` | 비소유 접근이 조용히 값을 돌려준다 → `Inv_UnownedFaults` | HIU-10 · §5.5 loud-fault-never-silent |
| `entitle_gates_value` (W1) | 자격 거부 장치 접근(거부 채움이 전형)이 값을 돌려받고 쓰기가 반영된다 → `Inv_EntDeniedBlocked` | E.1.2 「FAULT_STATUS 비트 배정」 — 값 차단 · 승인 거부는 두 원인이 같다 |
| `perm_entitle_only` (W1) | 자격 허용 ∧ 비소유 접근이 `[4]` 를 세운다 → `Inv_Bit4EntOnly` | 같은 규범 — `[4]` 는 자격 거부만 |
| `entitle_first` (W1) | 자격 거부 ∧ 비소유 접근이 `[4]` · `[19]` 를 함께 세운다 → `Inv_OneBitPerAccess` · 거부 채움 축 → `Inv_DenyFillIs4` | 같은 규범 — 자격이 먼저, 한 접근에 둘이 함께 서지 않는다 |
| `own_reported` (W1) | 자격 허용 ∧ 비소유 접근이 어느 비트도 세우지 않는다(조용한 거부) → `Inv_UnownedLoud` | 정본 3.4.1 4항 — 소유하지 않은 쪽의 접근은 loud fault |

### 이 모델이 실제로 말하는 것

핵심은 **`Witness_NoMemSkew` 가 반증되는데 `Inv_SameObservation` 은 통과**
한다는 짝이다. 두 세계의 배후 저장은 *실제로 어긋난다* — rich 는
write-through 라 즉시 반영되고 plain 은 지역 사본에 머문다. 그런데도 관측은
같다. **소유권 규약이 일관성을 정확히 대신한다**는 것이 이 짝의 내용이며,
그것이 §3.4 가 "손해가 아니라 거래" 라고 부른 것의 형식적 형태다.

어긋남이 도달 불가였다면 관측 동치는 자명했을 것이고, 아무것도 뜻하지
않았을 것이다.

### 가드 삭제가 그 자체로 도달성 증인이다

「기입 → 이양 → 읽기」라는 위험 인터리빙이 실제로 도달 가능한가는 별도
증인으로 적지 않았다. `del_flush_on_handoff` 가 `Inv_SameObservation` 을
깨뜨린다는 사실이 곧 그 답이기 때문이다 — 도달 불가능한 인터리빙이라면
가드를 지워도 아무것도 깨지지 않는다.

### 정본이 "기능이 준다" 고 적은 것의 반대 방향

§3.4.1 규범은 일관성 의존 상태 기계를 두면 *"없는 플랫폼에서 기능이 줄고
그것이 곧 플랫폼 종속"* 이라고 적는다. 모델이 실제로 낸 반례는 방향이
반대였다 — `state_machine_kept` 를 지우자 **있는 플랫폼에서 기능이 늘었다.**
plain 이 fault 하는 접근을 rich 가 통과시킨다.

둘은 같은 종속이다. 어느 쪽이든 *PE 가 보는 세계가 호스트에 따라 달라진다.*
정본 문장은 한 방향만 적고 있어 좁다 — §3.4.1 에 대칭 형태를 환류했다.


### W1 — 승인 거부의 보고 비트 `[4]` · `[19]` (3.10 v1.0 묶음, 2026-10-11)

3.10 v1.0 묶음이 `[4]` 에서 `[19]` 「비소유 프레임 접근」을 갈라 신설했다 — 자격이 먼저: 권한 비트가 그
접근을 허용하지 않으면 소유와 무관하게 `[4]` 만, 자격 허용 ∧ 비소유일 때만 `[19]`, 한 접근에 둘이 함께
서지 않는다. 거부 채움(R=W=X=0)은 프레임이 무엇이든 `[4]` 다. 사상에 권한 비트를 싣고 장치 접근마다 접근자 ·
승인 판정 · 원인 사실 · 보고 비트를 기록한다 (보고 축은 **장치 접근 한정** — 호스트 접근은 보고 비트를
세우지 않고, `Inv_ReportBitByCause` 가 그것을 상주로 잰다). 정본 좌표 · RTL 대응 이름은 모델 머리가 소유한다.

- 새 불변식 일곱(좋은 모델 cfg 셋이 전부 건다): `Inv_ReportBitByCause`(보고 비트 = 원인의 정확 등식) ·
  `Inv_OneBitPerAccess` · `Inv_Bit4EntOnly` · `Inv_UnownedLoud`(앞판 「loud」 의 보존 — 둘 중 하나는 선다) ·
  `Inv_DenyFillIs4` · `Inv_EntDeniedBlocked` · `Inv_DenyIffReported`(「갈리는 것은 보고 비트뿐」).
- 새 증인 넷(전부 장치 접근으로 도달): `NoEntDeny` · `NoOwnDeny` · `NoBothCauses` · `NoDenyFillOwned`.
- 짝 「오늘의 RTL」(W1 전 RTL — HEAD 3b80087: `permViol = ¬(devOwned ∧ entitle)` 하나로 두 원인을 `[4]` 에
  접고 `[19]` 원천이 없다) = 가드 둘(`perm_entitle_only` · `own_reported`)을 지운 판이 `Inv_ReportBitByCause` 를
  깨고, 같은 판의 대비 MUST PASS 가 나머지 불변식 · HIU-8/9 를 전부 통과한다 — 그 RTL 의 간극은 원인 귀속
  하나뿐이었다. 이름은 착지 뒤에도 유지한다(XlateSurface 짝 선례).
- 재지 않는 것(모델 머리 「안 잰다」 가 닫힌 목록): sticky · W1C · 발화 우선 · 표현 불가 프레임 · 실행 권한 ·
  `[19]` 캡처 · 호스트 쪽 자격 · 보고 · 쓰기 경로 단독의 승인 무시. RTL 쪽 몫은 후-formal `hiumask.sby`(원인별
  상승 원천 · sticky · 값 차단) · `assembly.sby`(배치 · 해제 라우팅)이고 둘의 합성은 서술이다
  (`lint_postformal` `_PARTIAL` 의 `Platform.own_reported` · `Platform.entitle_gates_value`).
- 실측: Platform 절 23/23 선언대로 (전량 배터리 554/554 — 컨테이너 · 2026-10-11 21:15 KST 완료 · 부록 D 문장과
  같은 판). 형상 sweep 페이지 2 · 주소 2 는 89,388 distinct.

## SEC-3 — `NoLoss.tla`

정본 §5.7 의 진술:

> **SEC-3** 무소실 — 어떤 요청도 상태 비트를 세우지 않고 사라지지 않는다.
> (loud-fault-never-silent 의 형식화.)

### FAB-2 와 무엇이 다른가

FAB-2 는 *한 공유 유닛*의 무처분 없음이다. SEC-3 은 그 상위 형태로
**기계 전체의 회계**를 말한다 — 유닛마다 처분이 있어도 유닛 *사이*에서
새면 깨진다. 계약이 "사라지지 않는다" 이므로 형식은 보존 등식이다.

```
entered = completed + faulted + InPipe
```

서문 §0.8 이 적은 네 실패형이 전부 이 등식 위에 있다. 앞의 셋은 개수를
줄이고 마지막은 **늘린다** — 그리고 늘리는 쪽이 더 위험하다. 하나 잃고
하나를 두 번 세면 등식이 다시 맞기 때문이다.

16 run: 기저 1 + 형상 sweep 2 + 가드 삭제 6 + 증인 4 (+ 짝 3은 없음).

| 가드 | 지우면 | §0.8 실패형 |
|---|---|---|
| `queue_room` | 가득 찬 단에 덮어쓴다 → `Inv_Conservation` | 조용한 덮어쓰기 |
| `busy_loud` | 자리 없는 요청이 처분 없이 사라진다 → `Inv_Conservation` | 조용한 드롭 (공유 디코더) |
| `advance_atomic` | 단을 떠났는데 다음 단에 도착하지 않는다 → `Inv_Conservation` | 유닛 *사이*의 소실 |
| `fault_sticky` | fault 가 흔적을 안 남긴다 → `Inv_FaultVisible` | 시뮬 전용 단언으로 구현한 fault |
| `width_checked` | 넓은 값이 좁은 통로를 통과한다 → `Inv_NoSilentTruncation` | 조용한 절단 |
| `complete_once` | 없던 완료를 만든다 → `Inv_NoPhantom` | 손실을 덮는 회계 |

### 세 가드가 한 불변식을 공유한다 — 약점이 아니다

`queue_room` · `busy_loud` · `advance_atomic` 은 전부 `Inv_Conservation` 을
깨뜨린다. 「가드 하나에 불변식 하나」 를 어긴 것처럼 보이지만 사실은 그
반대다 — 셋을 *각각* 지웠을 때 셋 다 깨지므로, 셋 모두가 **독립적으로
필요하다**는 것이 증명됐다. 하나를 위해 억지로 다른 불변식을 만들었다면
그 불변식은 계약이 아니라 모델의 장식이었을 것이다.

### `advance_atomic` 은 2차 적대 검증의 산물이다

처음 판은 단 사이 이동을 `![i] = @-1, ![i+1] = @+1` 한 동작으로 적었다.
그러면 **유닛 사이의 소실이 구조적으로 표현 불가능**해진다 — 지울 가드가
없으므로 가드 삭제 실험이 그 결함형을 영원히 못 본다.

`Route.tla` 의 M3(뷰가 변수가 아니라 정의)와 같은 형태이고, 바로 위
교훈 ② 그 자체다. 이번에는 모델을 쓰는 중에 그 질문을 던져서 잡았다.

### `Inv_NoSilentTruncation` 은 좋은 모델에서 공허하게 참이다

`width_checked` 가 넓은 요청을 통로 앞에서 거절하므로, 좋은 모델의
파이프에는 넓은 값이 *들어오지 않는다* — 따라서 `obsIn` 이 `"wide"` 가 되는
일이 없고 불변식은 자명하게 성립한다.

그것이 이 불변식에 내용을 주는 것은 두 실행의 **짝**이다:
`Witness_NoWideRejection` 이 반증돼 넓은 요청이 *실제로 도착한다*는 것을
보이고, `del_width_checked` 가 불변식을 깨뜨려 *가드가 없으면 통과한다*는
것을 보인다. 둘 중 하나라도 없으면 이 불변식은 장식이다.

거절을 원인별로 세지 않았다면(`wideFaulted`) 앞의 증인을 세울 수 없었다 —
거절된 요청은 파이프에 흔적을 남기지 않기 때문이다.


## EXT-1 · EXT-2 · EXT-3 — `Walk.tla`

정본 §4.5 의 진술:

> **EXT-3** 검산의 독립성 — 종료 판정, 길이 검산, 상한 검사 셋은 서로
> 독립이다. 어느 하나를 무력화하면 나머지 둘 중 적어도 하나가 그 사실을
> 검출한다.

### EXT-3 은 검사들 *자신에 대한* 메타 속성이다

앞의 모델들은 "기계가 계약을 지키는가" 를 물었다. EXT-3 은 다르다 —
**검사가 서로를 대신하고 있지 않은가** 를 묻는다.

셋이 겹쳐 있어도 하나가 나머지에 함축되면 실제로는 둘뿐이다. 그리고
그 사실은 **아무 테스트도 드러내지 않는다** — 모든 테스트가 여전히
통과하기 때문이다. 이것이 서문 §0.8 이 "결함이 아니라 그것을 가능하게 한
검사" 라고 부른 것의 가장 순수한 형태다.

14 run: 기저 1 + 형상 sweep 2 + 가드 삭제 5 + 증인 6.

### 종료 판정은 검사가 아니라 authority 다 — 정본 문장이 좁다

§4.2.2 규범은 못박는다: *"종료는 종료 표식(END)이 정한다. 길이 필드는
검산이다. 슬롯 상한은 안전장치다."* 즉 END 는 나머지가 *무엇에 대해*
검사하는지를 정하는 기준점이지, 그 자신이 거절자가 아니다.

그런데 EXT-3 의 문장은 "종료 판정, 길이 검산, 상한 검사 셋" 이라고 적어
END 를 검사 중 하나로 센다. 모델을 세우면서 이 어긋남이 드러났다 —
실제 거절자는 **길이 검산 · 상한 검사 · 미지 종류**(§4.2.2 규범 3항)
셋이고, 종료 판정은 그 위에 있는 authority 다. 정본에 환류했다.

### 「하나만 잡는 사슬」이 독립성의 직접 형태다

| 증인 | 반증하는 사슬 |
|---|---|
| `Witness_NoLenOnly` | END 는 있고 미지 종류도 없는데 선언 길이만 어긋난 사슬 |
| `Witness_NoCapOnly` | END 가 아예 없는 사슬 |
| `Witness_NoJunkOnly` | END 도 길이도 맞는데 앞에 미지 종류가 섞인 사슬 |

셋 다 반증됐다. 어느 하나라도 반증되지 않으면 그 검사는 나머지에
함축된 것이고, 「3중」은 이름뿐이다.

### 지상 진리를 검사의 어휘로 적지 않았다

`WellFormed` 는 `RejLen` · `RejCap` · `RejJunk` 를 **쓰지 않는다.** 사슬의
구조만으로 정의된다. 검사의 어휘로 적었다면 "검사를 통과한 것이 적합하다"
가 되어 `Inv_SoundVerdict` 가 항진명제가 됐을 것이다 — `Route.tla` 의 M2
에서 실측한 자기지시 실패형이며, 이번에는 처음부터 피했다.

### 다섯 가드가 두 불변식을 공유한다

`Inv_SoundVerdict` 를 넷이 공유하는 것은 `NoLoss.tla` 와 같은 이유로
약점이 아니다 — 넷을 *각각* 지웠을 때 넷 다 깨지므로 **넷 모두가
독립적으로 필요하다**는 것이 증명됐다. EXT-3 이 요구하는 것이 정확히
그 진술이다.


## FAB-1 · FAB-9 · FAB-5 · FAB-6 — `Fabric.tla`

병합 지점 하나의 계약. 이 모델의 반례가 **정본을 고쳤다** — FAB-1(유효
생산자 최대 하나)이 문자 그대로 성립하는데 소비자가 어느 생산자도 보내지
않은 값을 받는 상태(`drove = <<{b1}, NoVal>>`, `merged = {b1,b2}`)가
`del_valid_gated` 에서 도달했고, 게이팅 축이 **FAB-9** 로 분리 등재됐다
(§2.7 함정). ISA-3 → ISA-8 과 같은 발견 경로다.

63 run (D=2 형상 4 포함). 가드 11 — 병합 축 4(single_producer · valid_gated ·
valid_tracks_data · capture_atomic), 배압 축 5(stall_on_pending · bp_loud ·
fault_raised · fault_sticky · bp_no_consumer_write), 진행성 축 2(fair_grant ·
bp_relief). FAB-6 은 이 배터리의 첫 **진행성** 속성이다 — `~>` 형태,
공정성을 생산자마다 건다 (`WF_vars(\E p : ...)` 는 이접에 대한 공정성이라
기아를 못 막는다).

값 = 비트 집합, OR 병합 = 합집합. 「유효 생산자 ≤ 1」로만 적으면 가드와
같은 어휘라 자기지시적이 된다 — 그래서 *병합된 값 자체*를 관측하고,
`Witness_NoOrHazard`(합집합이 어느 쪽과도 다른 값들이 동시에 실릴 수
있는가)가 이 배터리에서 가장 중요한 run 이다.

## SEC-4 · HIU-11 — `Isolation.tla`

둘 다 관계 속성 — `Platform.tla` 의 lockstep 구조를 승계한다 (§3.4.2).
SEC-4 는 두 세계가 **q 가 설치한 상태에서만** 다르고 p 의 관측(판정 · 값 ·
상태열 · 승인 이전 방출)이 같아야 한다. `XlateStore.tla`(HIU-1/2)의
재탕이 아닌 이유: 그쪽은 *적중 판정*이 남의 항목을 고르지 않음을 말하고,
이쪽은 **미적중이라는 사실 자체의 타이밍**까지 채널로 본다 — q 의 설치
*행위*가 공유 채움 경로에 남긴 잔여물이 실측된 둘째 채널이다.

HIU-11 은 선택적 경로가 *있는* 구성과 *없는* 구성의 비교이며, §3.4.2 의
짝 문장이 여기에도 성립한다 — 두 구성의 내부 상태는 실제로 어긋나는데
(`Witness_NoOptStateSkew` 반증) 관측은 같다.

43 run. 가드 10, 증인 7 (전부 구성된 기계에서 반증).

## EXT-4 — `Payload.tla`

`NoLoss.tla` 가 덮지 못한 축 — 그 모델은 개수만 세므로 「A 를 잃고 B 를
두 번 완료」를 보지 못하고, 자기 머리가 그 공백을 EXT-4 의 몫으로 남겼다.
이 모델은 조각에 **정체성**을 준다.

재조립 문맥을 태그 색인이 아니라 유한 풀(`Ctxs`)로 들어 EXT-4 문면(「하나의
태그에 동시 재조립 최대 하나」)을 시험 가능하게 만들었고, `NFrag` 하나가
겸하던 총개수·구간 길이·상한을 `total[r]`(조각열 선언)과 `SlotCap`(구현
파라미터)으로 갈라 §1.6.2 오류 3분류를 표현한다. §4.3 함정이 참조 구현에서
실측한 「같은 태그의 새 조각이 오면 조용히 마지막 것이 이긴다」가 배터리에서
두 번 재현된다 — 문맥 축(`del_key_is_tag`)과 조각열 축(`del_no_restart`).

26 run. 가드 11, 증인 11. 조각 순번·총개수의 채널은 **부록 E.10 (조각 머리
채널, 사이드밴드 CTRL)** 로 확정됐다 — 모델의 「함께 도착한다」 가정이
계약이 됐다. 마지막 조각 표시(B.5 결정)도 착지했다: `ctxLast` 가 종료
authority, `last_judges` 가드가 표시 접수 시점의 완전성 판정 —
지우면 누락이 무언으로 남아 `Inv_EndIncompleteLoud` 가 깨진다. 표시 유실
갈래(`Witness_NoMarkerLoss`)는 fault 가 아니라 미완 문맥의 관측 가능성이다
— 처분은 호스트 몫.

**태그 코덱 전파 파도 (2026-09-26 · D2b).** `Tags` 를 (Key × Trace × Poison) 으로 정제했다 — 정본이
「키는 태그 전량이 아니다 — poison 과 trace 는 빠진다」(04-ext-payload 4.3 · E.12 6항)로 태그 = 키 등식을
끊었는데, 태그가 정수 하나인 모델에서는 키를 태그 전량으로 잡는 구현(재구현의 번들 통비교)이 정본 구현과
구별되지 않았다. 새 가드 `key_drops_side`(세 매칭 — 개시 · 조각 조회 · 소거 — 이 키 투영만 비교) · 새 불변식
`Inv_AbortReachesKey`(소거 뒤 그 *키*의 문맥이 남지 않는다 — 소거는 스테이징이 0 으로 못박은 두 비트를 싣는다).
run 여섯: 좋은 모델 둘(trace 축 · poison 축 — 두 축을 함께 켜면 전이 분기 4배로 기저가 폭발해 한 축씩 켠다,
각 39.8만 distinct · 1분 30초) · 삭제 → `Inv_AbortReachesKey` · 증인 둘(`NoSideFragHit` · `NoSideAbortHit`) ·
오늘의 RTL 짝 둘(trace 만 · poison 만 → `Prop_NoSilentOverwrite` — 조각 조회 절반의 귀결: 두 비트만 다른
도착이 같은 키의 둘째 문맥을 열어 같은 구간을 덮는다). 다른 가드의 run 은 접힌 판(Traces = Poisons = {0}
— 1차 판과 같은 기계)으로 돈다. Payload 구간 38 run · 가드 16.

## EXT-6 — `MemOrder.tla`

§4.4.4 가 확정한 기전(명시적 순서 의존)의 형식화. **이 모델은 한 번
죽었다** — 1차 판의 `Inv_OnlyTokenBlocks` 는 좋은 모델 세 형상 전부에서
*측정된 항진명제*였다. 좋은 모델의 가드가 `FireEnabled` 와 불변식의 전건을
같은 술어로 만들어 `P => P` 로 붕괴했다. `Route.tla` M2 실패형의 재발이며,
README 가 그 실패형을 적어 둔 뒤에도 되풀이됐다는 것 자체가 기록할 값이다.

수리의 축은 **두 얼굴의 분리**다. §4.4.4 규범 1(발화 계약: 이어진 쌍은
선행 완료 뒤에만 발화)과 EXT-6 문면(관측 계약: 프로그램 순서와 관측 순서
일치)은 같은 계약의 두 얼굴이지만, 한 이름에 담으면 BFS 가 언제나 얕은
얼굴에서 멈춰 깊은 얼굴이 영원히 무판정으로 남는다. `Inv_DepRespected` 와
`Inv_ObservedOrder` 로 갈라 각각 판정 주체를 주었다.

61 run. 가드 7 — 발화측 게이트 2(token_gate · token_on_complete), 배선
일치 1(gate_matches_dep, **3방향**: 과소·과대·역방향 순환 교착), 과잉
게이팅 3(wave · addr · inflight — 정본이 「구현은 자유」로 열어 둔 갈래마다
그 자유를 반납하는 결함형), 완료측 결박 1(complete_not_ordered — 응답
FIFO 기계는 종전 배터리 전부를 좋은 기계와 판별 불가로 통과했다. 지울
가드가 없는 결함형은 검출되지 않는다).

**부분 증명인 이유**: 과잉 게이팅 금지(`Inv_OnlyTokenBlocks`)의 정본
근거가 전부 §4.4.4 *해설*에 있다 — 해설은 계약이 아니다. 규범 승격이
미결이다 (B.5).

## SEC-2 · SEC-7 — `Decode.tla`

SEC-7 의 함정은 「판정 이전」이다 — "예약이 0 이 아니면 거절" 만 적으면
속성이 자명해진다. 이 모델은 판정 이전 단계를 두고, 그 단계의 관측(상태열 ·
sticky 미적중 · 진단 워드 · 승인 경계 방출)이 예약 비트에 의존할 수 있는
구조를 만들어 그 의존을 가드 6개로 막는다. 예약 필드에서만 다른 두 명령의
lockstep 비교다.

SEC-2 는 「사이클 수」가 아니라 **상태열**이다 — `Strong_SamePathSeq`(상태열
동일)와 `Weak_SamePathLen`(길이만 동일)을 짝으로 두어, 같은 반례에 대해
강한 쪽은 깨지고 약한 쪽은 통과함을 보였다. 사이클 수만 재는 검사는
상태열이 다른데 길이만 같은 구현을 통과시키고, 그 차이가 곧 부채널이다.
정본 §5.3 이 테스트에 대해 적은 「절대 사이클 수가 아니라 경로 간 동일성」
의 형식 속성 짝이 이것이다.

72 run — 이 배터리에서 가장 큰 모델. 가드 11, 증인 9, 짝 19.
세 경로(적중·대체·미적중) 각각의 도달성 증인이 있다 — 하나라도 도달
불가면 SEC-2 는 남은 둘만 비교하는 명제가 된다.

## E.1.2 · E.3 변환 저장소의 MMIO 문 — `XlateSurface.tla` (파도 3, 2026-09-26 — 앞판 LO/HI 문의 기록. 2026-10-13 W3 재작성판은 위 표 행 · 모델 머리)

`XlateStore.tla`(저장 블록) · `Isolation.tla`(조회·채움의 비간섭)가 설치와 flush 를 원자 동작
하나로 두는 자리를 연다 — 호스트는 32b 버스로 한 워드씩 쓰므로 항목 하나(64b)는 LO · HI 두
기입이고, 그 사이의 상태가 관측면에 실재한다. 정본 좌표와 각 가드의 문장은 모델 머리가 소유한다.

50 run (파도 4 개정 뒤 — 아래 「판정 T5 · T4」): 좋은 모델 3(파티션 2 · 색인 1 / 색인 2 규모 / 상한 아래
형상 — `BelowCap`) + 가드 삭제 19 + 증인 18 + 짝 「오늘의 RTL」
2(XLATE_FLUSH · 항목 기입이 조용히 흡수되던 착지 전 기계 — 파도 2 의 T1) + 하류 거부 처분 대안 2
(거절 + loud → `Prop_RejectOnlyMalformed` 위반 · 조용한 흡수 → `Prop_HiCommits` 위반) + 스테이징 수명
대안 2(`StgAlt` — 커밋 소진 → `Prop_FlushEndsStaging` 위반 · 전역 비움 → `Prop_FlushStagingScoped` 위반) +
형상 밖 주소 별칭 짝 1(`Prop_EntNoAlias` 위반) + 진행 1
(`LiveSpec` 아래 `Prop_StallEnds` 통과) + 그 대조군 1(채움 슬롯 Drain 공정성을 빼면 정지가 영구) +
발견 1(정지 중 `0xE10` 해제의 유실 — `Prop_ClearAlwaysLowers` 가 좋은 모델에서 반증된다).

착지판은 31 run 이었다. `0xE10` XLATE_MISS_CLEAR 와 RO 세 워드(`0xE04`–`0xE0C`)의 쓰기 처분은
RTL 이 모델보다 먼저 배선했고(검토자 D-7) 반증 검토가 그것을 6.3 위반으로 지적했다 — 같은 날
모델로 돌려보내 가드 다섯(`mclr_fires` · `mclr_needs_one` · `mclr_rsv_strict` · `mclr_keeps_stall` ·
`ro_rejected`) · 증인 다섯 · 발견 run 하나를 더했다. 모델은 조회 요청 하나의 미적중 정지(`mstall`)와
미적중 sticky(`msticky` — set 은 정지 레벨, 발화가 해제를 이긴다)를 싣고, 정지는 그 항목의 V=1
커밋만 푼다(E.3 2항).

하류 거부(`install.ready` = 0)의 처분은 설계 결정이라 상수 `Refusal` 로 세 갈래를 다 표현하고
기계가 판정한다 — 버스 정지만 모든 속성을 통과한다.

**판정 T5 · T4 (파도 4 개정, 2026-09-26 — 정본 f229c8b).** 착지판의 증인 `Witness_NoStaleRecommit`
(MUST FAIL)는 정본 문면의 귀결 — 스테이징이 flush 로 끝나지 않으면 임대 회전 ⑵ 를 건넌 옛 LO 가
HI 한 워드로 다시 커밋된다 — 을 붙잡고 「정본이 정하면 그때 모델을 고친다」고 적혀 있었다. 판정
(a)(수락된 flush 가 래치 파티션의 스테이징 유효를 내린다 · 커밋은 소진하지 않는다)으로 그 증인은
반례를 잃었고, 뒤집어 좋은 모델의 고정 속성 `Inv_NoStaleRecommit` 으로 올렸다 (run 은 지웠다). 가드
`flush_drops_staging` · `ent_part_exists`(판정 T4 (ii) — 상한 아래 형상의 형상 밖 항목 주소는 거절) 둘,
기각한 두 갈래는 상수 `StgAlt` 의 대안으로 각자 반례를 낸다 — 커밋 소진의 반례가 정본 해설의 세
스텝(LO → flush → HI) 그대로다. 형상 밖 주소는 상수 `BelowCap` 으로 끄고 전용 cfg 넷에서만 켠다 —
`XlateSurface_large.cfg` 는 배터리 안이다. 새 증인 셋은 ev 사건을 늘리지 않는 스텝 뒤 상태 술어라
large 의 도달 상태를 부풀리지 않는다. 분리 검사와 규모 실측은 run.sh 그 절 머리.

**재지 않는 것** (모델 머리 「안 잰다」가 닫힌 목록): 조회·채움·값의 정확성 · HI 의 태그·권한
필드 · 주소 디코드 · 읽기 방향(`0xE04`–`0xE0C` 관측 워드의 읽기 *값* 포함 — 쓰기 처분만 싣는다) ·
적중 판정(미적중 정지는 「유효 항목 없는 항목의 조회」 하나로 접는다) · sub-word 쓰기 · FAULT `[6]` 의
sticky·해제 · 사이클 수(모델은 하류 거부의 도달성을 *과대* 근사한다 — RTL 에서는 같은 항목 HI
연속만 거부를 만난다) · 설치·flush 원천이 둘인 갈래(최상위 IO 잔존 — RTL 파도가 은퇴시켰다) ·
색인 축의 형상 밖 주소(이 구현은 색인 16 고정 — 파티션 축은 판정 T4 로 잰다).

## E.1.2 · E.12 · E.12.1 재조립 문맥 소거의 문 — `AbortSurface.tla` (파도 4, 2026-09-26)

`AbortStaging`(결정 A)은 2026-08-25 에 선-formal 없이 RTL · 후-formal 로 착지했다 — 6.3 의 1단 결손이었다.
`Payload.tla` 는 소거를 「태그 하나를 지정한 소거 기입」이라는 의미론으로 추상하고, 그 태그를 32b 버스 세
워드에 싣는 문은 어느 모델의 상태도 아니었다. 이 모델이 그 문이다 — 정본 좌표와 각 가드의 문장은 모델
머리가 소유한다.

30 run: 좋은 모델 2(값 2 / 값 3 규모) + 가드 삭제 13 + 증인 11 + 짝 3 + 대비 1.
- 짝 「D2 이전의 RTL」 둘 — TAG1 `[27:16]` 무검사(`poison_trace_zero` · `epoch_word_rsv_strict` 삭제 · `Subword` =
  "ignore"). 하나는 가드 자신의 속성(`Prop_PoisonTraceRejected`)으로, 하나는 그 호스트 가시 귀결
  (`Prop_FiredKeyClean` — 소거가 trace 를 든 태그를 싣는다, E.12 6항)으로 운다.
- 짝 「D2 뒤 · T2 앞의 RTL」 — sub-word 쓰기의 조용한 흡수(`Subword` = "ignore") → `Prop_MalformedRejected`.
  sub-word 처분은 가드가 아니라 상수다: 판정 T2 (a) 의 RTL 은 페이지 통합 파도(W4)가 착지하므로, 오늘
  GUARD-MAP 이 거짓 주장을 하지 않게 한다. 그 착지 커밋이 이 상수를 가드로 올린다.
- 대비 MUST PASS — 같은 판에서 가드 속성 열셋과 나머지 고정 속성 여덟이 전부 통과한다. 남은 간극이 sub-word
  하나라는 기계 기록이다.

분리 검사(비상주, 2026-09-26 실측): 가드마다 지운 판에 나머지 가드 속성 열둘을 걸어 13/13 통과 — 가드
삭제는 자기 속성만 깨뜨린다(삭제 run 자체는 첫 위반 하나만 보고하므로 이 「만」은 분리 검사가 잰다). 열둘은
6천–5만7천 distinct(5,955 – 56,509 · 검토 재실측 `-workers 2`)이고, `legal_first` 삭제 판만 거절 사유가
스테이징에 실려 상태가 커진다(905,561 distinct · `-workers 8` 로 1분 41초 — MUST PASS 판정은 워커 수와
무관하다; 단일 워커 판은 10분을 넘겨 끊었다). 그리고 D2 이전 판(`poison_trace_zero` · `epoch_word_rsv_strict` 삭제 · `Subword` =
"ignore")에 속성을 하나씩 걸면(21 run) 여섯이 운다: 가드 속성 둘(`Prop_PoisonTraceRejected` ·
`Prop_EpochWordRsvRejected`)과 고정 속성 넷(`Prop_NoPartialFire` · `Prop_FireTagLatest` ·
`Prop_FiredKeyClean` · `Prop_MalformedRejected`). `Prop_NoPartialFire` 가 우는 것은 수락된 거절 사유
TAG1 이 정본 적법 기입이 아니어서 명세 그림자가 그 워드를 「쓰이지 않은」 것으로 보는데 장치는 무장해
발화하기 때문이다 — D2 이전 기계의 발화는 정본의 눈으로는 부분 기입의 발화다.

RTL 이 먼저 정한 읽기 둘을 모델로 돌려보냈다 (모델 머리 「정본 문면이 닫지 않은 자리」): 거절된 발화
기입은 무장을 내리지 않는다(정본 3항은 수락/거절을 가르지 않는다 — `legal_first` 가 그 읽기다) ·
`[0]`=0 의 수락된 발화 기입도 발화 워드 기입이라 무장을 내린다. 셋째 읽기는 검토가 모델로 올렸다 — 무장은
수락된 발화 기입에서만 내려간다(정본 1항 「값을 덮되 비트는 선 채다」는 *같은* 워드의 재기입만 말한다). 이것은 가드가 아니라 고정
속성 `Prop_ArmFallsOnlyOnFire` 다 (파도 4 검토 뒤, 2026-09-26): 착지판의 속성 스물하나 어느 것도 무장의
*지속*을 말하지 않아 「재기입이 이웃 워드의 무장을 내린다」 장치가 전부를 통과했다. 탐침(비상주 — 모델
사본에 상수 `Probe` 로 그 누수를 넣음) 실측: 누수 판에 옛 속성 스물하나 → 통과(10,117 distinct — 공허가
아니다: 같은 판의 `Witness_NoFire` 는 반증된다) · 새 속성 → 위반 · `legal_first` 삭제 판(거절된 발화가
무장을 내림)에 새 속성 → 위반 · 좋은 모델에 스물둘 → 통과(6,121 distinct). 좋은 모델 cfg 둘과 대비 cfg
가 이 속성을 건다 — run 수는 그대로 30 이다. 후-formal 짝은 `AbortStaging_props.sv` 의 `t_arm_fall`.

**재지 않는 것** (모델 머리 「안 잰다」가 닫힌 목록): 소거의 효과(어느 문맥이 지워지는가 · 없는 태그의
무시 · ABORT_COUNT 증가 자체 — `Payload.tla`) · 매칭 키가 poison · trace 를 빼는가의 매칭 절반(재구현
결함 D2b — 태그 코덱 전파 파도가 `Payload.tla` Tags 정제 · 가드 `key_drops_side` 로 실었다) · 워드 안의 필드 배치와 마스크
값 · 주소 디코드 · 읽기 방향 · 5항 후단 · FAULT `[6]` 의 sticky · 시간.

## 3.7 · 3.10 · E.1.1 · E.1.3 구성 페이지의 처분 — `MmioPage.tla` (파도 4 페이지 통합, 2026-09-26)

MMIO 워드 표면의 *처분*은 어느 모델의 상태도 아니었다 — 조립 후-formal 이 VERIFIES 로만 잰 자리이고,
파도 4 의 판정 다섯(D1 · T1-i · T1-ii 쓰기 · T2 · T3)이 여기에 새 가드를 만든다. 이 모델이 그 1단이다.
`XlateSurface.tla` · `AbortSurface.tla` 는 자기 구역 문의 의미를, 이 모델은 페이지 전역의 처분 규칙
— 어느 접근이 수락되고 수락된 접근이 효과 · 거절 + loud · 조용한 무시 · 응답 중 무엇이 되는가 — 를
본다. 정본 좌표와 각 가드의 문장은 모델 머리가 소유한다.

29 run: 좋은 모델 1 + 대비 1(주소 기준 ready — D1 이전 모양 — 에서도 가드 둘이 살면 안전) + 가드 삭제 9 +
증인 10 + 짝·대안 8.
- 짝 「D1 이전의 조립」 둘 — 주소 기준 ready(`FpWaitByAddr`) 아래 잡힌 읽기의 응답(`Prop_RespAnswersAccepted`)과
  수락 전 FP_BIND 예약 거절(`Prop_LoudOnlySpec`).
- 짝 「판정 전의 표면」 — 비정렬 · 물려받은 구간 · RO 쓰기 흡수 + 소비 없는 워드 흡수 → `Prop_NoSilentDrop`.
- 대안 넷 — 레지스터만 실물화(`NoConsPolicy` = store: `Prop_NoSilentDrop` · `Prop_NoStaleRead`) · 물려받은
  구간 관대 · 비정렬 관대 (셋 다 `Prop_NoSilentDrop`) — 판정이 기각한 갈래의 기계 기록이다.
- 짝 「ready 만 고친 판」 — 응답 가드를 지우면 여전히 운다: 사상표(gateR)는 읽기도 소거를 기다린다.

CQ_SIZE 의 같은 값 수락(무동작)은 고정 속성 `Prop_NoSilentDrop` 이 *효과*로 센다 — 세지 않으면 모델의
고정 속성이 기존 정본 규범과 모순이다. 탐침(비상주): 그 계수를 빼면 좋은 모델이 `Prop_NoSilentDrop` 으로
운다 · 증인 `Witness_NoSameValueWr` 가 예외의 도달이다.

분리 검사(비상주, 2026-09-26 실측): 가드마다 지운 판에 나머지 가드 속성 여덟 — 9/9 통과(각 247 distinct).
삭제 run 자체는 첫 위반 하나만 보고하므로 「자기 속성*만*」은 이 검사가 잰다.

**한계** (모델 머리): 고정 속성의 예외 집합이 판정의 내용 그 자체다 — 판정이 달랐다면 두 집합을 바꿔 적었을
것이고 모델은 똑같이 통과했을 것이다. 기계로 보이는 것은 가드 ↔ 속성 대응 · 증인 도달 · 짝의 반례 · 규범
사이의 공존(예약 관대 ∧ 비정렬 엄격 · CQ_SIZE 같은 값 수락 ∧ 소비 없는 워드 거절)뿐이다.

**재지 않는 것** (모델 머리가 닫힌 목록): 어느 오프셋이 어느 부류인가(주소 디코드 — 조립 후-formal) ·
수락된 기입의 의미(각 구역 모델) · 읽기 값의 뜻(0xE04–0xE0C · 0xFFC 판 값) · 바이트 인에이블 · `[6]` 의
sticky · 시간 · 한 스텝의 접근 여럿.

## E.1.2 · E.3 변환 미적중의 관측면 — `XlateObs.tla` (파도 4 3B, 2026-09-26 · 판정 래치 W2, 2026-10-12)

`XlateSurface.tla` 는 호스트 쪽 *문*이고 세 RO 워드(`0xE04`–`0xE0C`)의 *읽기*는 그 모델의 상태가 아니다.
파도 3 까지 RTL 은 세 워드 읽기를 0 으로 두었고(미배선) 정본은 필드만 정한 채 셋 — 정지가 없을 때의 값 ·
여러 워드 읽기의 찢김 · 읽기가 해제하는가 — 에 침묵했다. 판정 E04 (A) 「정지 게이트 스냅샷」(f229c8b)이
셋을 정했고, 6.3 의 요구대로 그 결정을 이 모델로 돌려보냈다. 정본 좌표와 각 가드의 문장은 모델 머리가
소유한다.

파도 4 판 22 run (W2 가 41 로 늘렸다 — 아래 「W2」): 좋은 모델 2(파티션 2 · VPN 2 / 파티션 3 규모) + 가드 삭제 6 + 대안 1(비게이트 — 갈래 (C)) + 진행 1
(HostSpec) + 진행 짝 2(첫 미적중 포착 VPN · 상수 파티션) + 짝 「오늘의 RTL」 1 + 대비 1 + 짝 「새는 파이프」 1
+ 증인 7. RTL 편집 전에 블록 22/22 GREEN(컨테이너 · 2026-09-26 15:21 KST)을 남겼다.
- 가드 삭제 셋이 기각 갈래와 동형이다: `obs_vpn_stalled` 삭제 = 첫 미적중 포착(갈래 (B)) ·
  `obs_no_residue` 삭제(`ObsNoStall` = "latched") = 그 포착값의 잔재 · 대안(`ObsNoStall` = "live") = 비게이트
  (갈래 (C) — 조회 지점의 살아 있는 요청이 샌다).
- 진행 `Prop_StallResolves` 는 관측면만 보고 채우는 호스트(HostSpec)가 모든 정지를 푸는가 (W2 에서 「정지한 그 요청은 결국 떠난다」로 강화 — 아래 「W2」) —
  e-defined.typ:881 「채널이 없으면 2항은 이행 불가능한」의 *충분성* 쪽이다. 짝 「오늘의 RTL」(`Wired` = FALSE)이 그 문장의 기계 판이다.
- `Prop_NoTear`(찢김 없음)는 가드가 아니다 — 몸이 관측 회로가 아니라 E.4 3항 일제 정지(RTL 주장은
  `Decode.stall_uniform`)라서다. 짝 「새는 파이프」(`Pipe` = "leaky")가 반증력을 든다.

**발견 — 원형의 진행 짝은 말더듬 인공물에 열려 있었다 (수리함).** 원형(스크래치 시안)은 HostSpec 의 공정성을
채움(HostFill)에만 걸었다. 그 판에서 「`obs_stall_live` 를 지운 기계도 호스트가 푼다」(PASS 기대)가 FAIL 이었다 —
[0] 이 sticky 를 내면 정지가 선 그 스텝의 sticky 가 아직 0 이라 HostFill 이 꺼지고, 공정성 없는 Read 만 켜져 있어
영영 읽지 않는 호스트의 말더듬 행동이 진행을 깼다. 원형은 그 run 을 뺐다. 그러나 같은 인공물이 나머지 진행 짝에도
열려 있었다(첫 미적중 포착 판은 첫 정지 스텝에 포착 레지스터가 비어 HostFill 이 꺼진다) — TLC 는 반례 하나만
보고하므로 그 FAIL 이 「채널이 틀린 것을 말한다」로 났는지 「안 읽었다」로 났는지 선언이 가르지 못했다.
그래서 빼지 않고 HostSpec 에 읽기 공정성(폴링)을 걸었다 — 근거는
e-defined.typ:874 「정지가 영구가 되지 않을 책임은 호스트에 있다」 다. 그 판에서 진행 짝 반례는 「채널이 틀린 것을 말한다」뿐이고 원형이 뺀 run 은 대비 MUST PASS 다.

분리 검사(비상주, 2026-09-26 실측): 가드마다 지운 판에 나머지 가드 속성 다섯을 걸어 6/6 통과 — 가드 삭제는
자기 속성만 깨뜨린다. `Prop_NoTear` 는 분리 검사에서 뺐다 — 스냅샷의 전건이 「[0] = 1 을 읽었다」라
`obs_stall_live` 를 지운 판([0] = sticky)에서는 정지가 끝난 뒤에도 스냅샷이 서서 뜻이 바뀐다.

**재지 않는 것** (모델 머리 「닫지 않은 자리」가 닫힌 목록): 비트 배치(RTL 조립층 `a_rd_xstatus` ·
`a_rd_xvpnlo` · `a_rd_xvpnhi`) · 읽기 응답의 시각 · 적중 요청의 나머지 단 · 0xE10 의 문 쪽 적법성(`XlateSurface.tla`).

### W2 — 판정 래치 (3.10 v1.0 묶음의 RTL 파도 W2 선-formal, 2026-10-12)

정본 3.6.2 「판정 시점과 판정 래치」 · 3.7.2 철회의 효력 범위 · E.1.2 `0xC00` 결과 (d) · (h) · E.3 2항의 좁힘을
같은 모델에 실었다 — 판정 래치가 미적중 정지(`Stalled`)의 정의를 바꾸고 관측면이 그 정지를 읽기 때문이다. 모델
변경(판정 값을 드는 `tbl` · 같은 파티션 축출 집합을 비결정으로 고르는 `Install` · 연속 전진 `LeaveArrive` · 요청
꼬리표 `tok` · HostSpec 의 경쟁자와 하류 배압) · 정본 좌표 · RTL GUARD-MAP 예정 문면은 모델 머리가 소유한다.
여기서 「증명됨」은 *모델 위의* 사실이다 — RTL 측정은 `hiumask.sby` 와 형상 시험 N8 · N9 다 (`rtl/README.md` W2 절).

41 run (`run.sh` XlateObs 절을 세어 확인): 좋은 모델 2 + 가드 삭제 9(옛 여섯 + 아래 셋) + 대안 5(비게이트 ·
`clear_late` · `capture_beats_clear` · `sticky_raw_miss` · `value_no_latch`) + 고정 속성 반증 2 + 진행 1 + 진행 짝 3
(첫 미적중 포착 VPN · 상수 파티션 · 래치 없음 라이브락) + 짝 3(「파도 3 까지의 RTL」 · 「새는 파이프」 · 「오늘의
RTL」 W2 전) + 대비 3(`[0]` sticky · 옛 진행 꼴 `Prop_StallLifts` · 기각한 꼴 `Prop_StallEmpties`) + 증인 13.

| 가드 (W2) | 지우면 → 목표 속성 |
|---|---|
| `verdict_latch` | 판정된 요청이 hold 로 머무는 동안 항목이 철회 · 축출되면 다시 정지 → `Prop_NoReMiss` |
| `latch_clears_on_leave` | 다음 요청이 앞 요청의 판정을 물려받음 → `Prop_NoInheritedVerdict` |
| `latch_one_value` | 소유권 조회가 떠나는 시점의 저장 시야를 다시 읽어 한 요청이 두 값 → `Prop_OneValue` |

- 고정 속성 둘(가드 아님): `Prop_LatchedSurvivesRetract`(떠나는 값은 그 요청의 첫 적중 조회값 — 판정 뒤 철회 ·
  대체가 바꾸지 못한다) · `Prop_V0AfterEdgeMisses`(마지막 커밋이 V=0 인 (파티션, VPN) 의 요청은 그 에지 전에
  판정되지 않았으면 정지 — HIU-2 V=0 축의 *판정 시점 범위*). 반증은 가드 삭제판 단독 cfg 둘이 든다.
  `Prop_StickyRiseOnStall` 은 대안 `sticky_raw_miss` 가 반증한다.
- 진행을 강화했다 — `Prop_StallResolves` = 「정지한 *그* 요청은 결국 떠난다」: (Stalled ∧ tok = b) ~> (¬s3.on ∨
  tok ≠ b). 옛 꼴 Stalled ~> ¬Stalled(`Prop_StallLifts`)는 래치 없는 판의 라이브락(정지 → 채움으로 풀림 → hold
  로 머묾 → 경쟁 커밋 축출 → 다시 정지)을 통과시킨다 — 대비 run 실측 PASS. 「조회 지점이 언젠가 빈다」
  (`Prop_StallEmpties`)는 연속 전진 아래 좋은 모델도 깬다 — 대비 run 실측 FAIL. 그래서 요청 꼬리표로 적었다. 진행 짝
  「래치 없음 + 경쟁 커밋자 + 하류 배압」이 새 꼴을 깨 「결과 (d) 없이 (h) 의 수렴이 없다」가 기계로 선다. 하류
  배압의 유한성(Depart = Leave ∨ LeaveArrive 의 약한 공정성)은 *환경 가정*이다(닫힌 목록 11).
- 연속 전진 `LeaveArrive` — 첫 판은 떠남과 다음 도착 사이에 거품 스텝을 강제했고, 그 아래에서 「한 에지 늦은
  비움」 · 「포착이 비움을 이김」이 배터리를 통과했다(독립 반증이 찾음). LeaveArrive 를 들이자 둘 다 3 스텝에
  `Prop_NoInheritedVerdict` 로 울고, 지금은 상주 대안이다. 역대조(비상주): LeaveArrive 만 뺀 사본에서 두 대안이
  작은 좋은 cfg 를 통과한다 (모델 머리 「발견 (W2 독립 반증)」).
- 큰 cfg(`XlateObs_large.cfg`)는 `VIEW StateView` 로 돈다 — 한 스텝짜리 출력(rd · ev · lv)과 요청 꼬리표 tok 를
  접는다(건전성 근거는 모델의 StateView 주석). 대안 `clear_late` 는 lv.on 을 읽으므로 VIEW 아래 돌리지 않는다. 다른
  cfg 는 VIEW 없이 돈다.
- 모델은 RTL 보다 관대하다(모델 머리 「래치 포착의 원자성」) — BFS 최단 반례는 축출 · 철회를 첫 적중 사이클 끝
  에지에 둔다. RTL 에서 같은 파티션 *커밋*은 그 에지에 수락되지 않으므로(채움 슬롯 점유) 커밋 축출의 RTL 꼴은
  hold ≥ 2 사이클 뒤의 경쟁 커밋이다. flush 는 채움 슬롯을 기다리지 않아 그 에지에 수락된다 — 형상 시험 N8 의 flush
  사례가 그 꼴이다 (`rtl/sim/README.md` W2 절).
- 닫힌 목록 16 항(모델 머리). RTL 로 넘긴 것: 두 소비 값의 동일성(3 — hiumask `l_one_value`) · 필드별 분리(5 —
  `l_hold`) · 포착 게이트(6 — `l_capture_gated`, 유도 단언; HIU-3 정적 검사 본체는 없다) · reset 비움(8 — 형식 단언
  이월). **미측정으로 남은 것**: 결과 (h) 「자발 축출은 없다」(13 — 이 모델에서 구조이고 진행 PASS 가 거기 기댄다;
  W3 후보 가드 `evict_on_commit_only`) · 래치된 요청이 드레인 정의역 ①(HIU 점유 = 단 valid 의 수)에 드는가(14 — W2 당시 그
  점유를 재는 단언이 없었다 · W4 (2026-10-15)부터 `HiuMask/occ.sby` `h_occ_conserve` 가 잰다, reset 점유 0 은 구조) · HIU-2 V=0 축의 저장 측(15 — W3 까지 착지 대기; 여기서 재는 것은 판정 시점 범위뿐).
- 실측: XlateObs 절 41/41 선언대로 · 전량 배터리 573/573 선언대로 — 컨테이너 · 2026-10-12 11:54–13:25 KST · 게이트
  GREEN (부록 D 문장과 같은 판). 작은 좋은 모델 150,784 distinct · 큰 좋은 모델(VIEW) 618,496 distinct · 진행 MUST
  PASS 149,248 distinct (`run.sh` 절 머리 주석).

## E.1.2 임대별 마스크 키 · `[12]` 논스 재사용 판정 · `0xEC4` MASK_DUP_CAPTURE — `Mask.tla`

축 모델이다 (라벨이 색인 속성 ID 를 인용하지 않는다). 임대별 키 · 논스 · 마스크 유효 · MASK_PART 창 ·
MASK_REKEY 의 명시적 지목을 싣고, 3.10 v1.0 묶음 RTL 파도 W1 의 선-formal (2026-10-11 — 파도 착지 2026-10-12)이 FAULT_STATUS `[12]` 판정과
`0xEC4` 캡처를 같은 모델에 실었다 — 「재키잉이 시작된」 발화의 정의(`rekey_idle_only` ·
`rekey_explicit_target`)가 이미 여기 살기 때문이다. 정본 좌표(같은 줄 축자 결속)와 RTL 대응 이름은 모델
머리가 소유한다.

29 run: 좋은 모델 2(파티션 2 / 파티션 3 · `VIEW StateView`) + 가드 삭제 12 + 증인 14 + 짝 「오늘의 RTL」 1
(W1 전에는 10 run — 가드 넷 · 증인 넷 · 좋은 모델 둘).

| 가드 (W1) | 지우면 → 목표 속성 |
|---|---|
| `dup_on_started_rekey` | busy · 거절 발화도 `[12]` 를 세운다 → `Prop_RejectedFireInert` |
| `cap_first_event` | 둘째 사건이 캡처를 덮는다 → `Prop_CapFirstEvent` |
| `cap_clear_whole` | 해제가 `[7:0]` · `[15:8]` 을 남긴다 → `Inv_CapClearedZero` |
| `cap_set_beats_clear` | 같은 사이클 해제가 이긴다 → `Prop_CapSetBeatsClear` |
| `cap_bitmap_exact` | 비트맵에 p 자신이 든다 → `Prop_CapBitmapExact` |
| `cap_bitmap_domain` | 비트맵 = 다른 파티션 전부 → `Prop_CapBitmapExact` (파티션 3 · VIEW — 비트맵의 겹침 항은 파티션 3 에서만 보인다) |
| `start_ignores_dup` | `[12]` 를 세운 시작된 발화가 엔진을 busy 로 보내지 않는다 → `Prop_StartGoesBusy` |
| `complete_ignores_dup` | `[12]` 가 서 있는 동안 완료가 막힌다 → `Inv_BusyCanComplete` |

- `[16]` 은 결정대로 `[12]` sticky 그 자체(`Word.on = dup`)라 `Inv_CapIffDup` 은 가드가 아니라 **구조**다 —
  그것을 깨는 것은 짝 「오늘의 RTL」(W1 전 RTL — HEAD 3b80087: `CapWired = FALSE`, `0xEC4` 미디코드 · 읽기 0) 하나다.
  그 짝은 워드만 바꾸므로 RTL 의 `[12]` 판정 쪽은 이 배터리가 재지 않는다 — W1 RTL 의 `[12]` 는 후-formal
  `engine.sby` 가 **탐침 축약 아래에서** 잰다 (고정 탐침 여섯 자리 중 하나의 1비트 논스 등치 환경). 그래서 대비
  MUST PASS 를 두지 않았다.
- 계약 둘(가드 목표 아님): `Prop_DupExact`(`[12]` 한 비트의 전체 의미) · `Inv_CapIffDup`(구조).
- 대형 cfg 의 `VIEW StateView` 는 동작이 *읽는* 변수 전부다 — 동작이 읽지 않는 기록 · 증인용 변수(`ev` · `lastWinWrite` ·
  `reqPart` · `engKey` · 증인 sticky 들)를 지문에서 뺀다. 그 cfg 를 바꾸는 편집이 `cap_bitmap_domain` 측정을 조용히 끄지 못하도록 그 삭제 run 도 같은 설정으로 돈다.
- 재지 않는 것(모델 머리의 닫힌 목록): `0xEC4` 쓰기 거절 + `[6]`(MmioPage `ro_rejected`) · `0xEC4` 읽기 결선
  (assembly `a_rd_dupcap`) · 논스 192b 전폭 비교(engine.sby — 탐침 축약, 탐침 밖은 cocotb 지향 표본) · 읽기 무부작용
  (assembly `a_rd_pure` — 유도 단언) · `0xF84` 예약 비트 거절(assembly) · reset 형식 단언(W1 에서 하지 않았다).
- 실측: Mask 절 29/29 선언대로 (전량 배터리 554/554 — 2026-10-11). 파티션 2 좋은 모델 159,024 distinct · 파티션 3 ·
  VIEW 92,352 distinct.

## E.1.2 · 3.7.2 결속 파티션 — `ActivePart.tla` (3.10 v1.0 묶음의 RTL 파도 W4 선-formal, 2026-10-15)

축 모델이다 (라벨이 색인 속성 ID 를 인용하지 않는다). 정본 E.1.2 `0xE14` XLATE_ACTIVE_PART 행 · 「결속 파티션의 수락
판정 — 0xE14 의 (A, D) 쌍」 · 3.7.2 「결속 전환」을 싣는다 — 요청의 파티션은 접수 시점의 결속이고, 결속은 드레인
경계에서만 바뀐다. 정본 좌표 · RTL GUARD-MAP 예정 문면 · 닫힌 「안 잰다」 목록은 모델 머리가 소유한다. 여기서
「증명됨」은 *모델 위의* 사실이다 — RTL 측정은 `ActivePart/activepart.sby` · `Wt64Top/assembly.sby` ·
`CompletionUnit/descriptor.sby` `prove_daz` · `HiuMask/occ.sby` 와 형상 시험 N10 · N11 · N15 다 (`rtl/README.md` W4 절).

44 run (`run.sh` ActivePart 절을 세어 확인): 좋은 모델 2(파티션 2 · 일 상한 1 / 파티션 4 · 일 상한 2) + 가드 삭제 12 +
고정 속성 음성 3(`_del_ad_every_accept_a0d1` · `_del_pend_stalls_req_iso` · `_del_pend_stalls_req_stale`) + 증인 18 + 짝 3
(W4 전 RTL — `0xE14` 쓰기 흡수 · 요청 파티션이 포트 · 기각한 「같은 값 ∧ D = 0 → 거절」) + 대안 6(β 넷 · lag · hold).

| 가드 | 지우면 → 목표 속성 |
|---|---|
| `value_first` | 없는 값이 같은 값으로 접혀 수락 → `Prop_ValueFirst` |
| `rsv_strict` | `[31:10]` 비0 수락 → `Prop_RsvRejected` |
| `ro_field_ignored` | `[9:8]` 을 예약-엄격으로(RMW 드라이버 거절) → `Prop_RoFieldIgnored` |
| `drain_gates_switch` | D = 0 에서 결속 교체 → `Prop_SwitchOnlyDrained` |
| `same_value_noop` | 같은 값 ∧ D = 0 → 거절 + `[6]` → `Prop_SameValueNoFault` |
| `ad_every_accept` | 거절 뒤 앞 기입의 A = 1 이 남음 → `Prop_AdEveryAccept` |
| `d_includes_same_cycle` | 기입 사이클 에지 전 표집 — 같은 사이클 접수 누락 → `Prop_DIsPostEdge` |
| `pend_stalls_req` | 판정 사이클에 옛 결속으로 접수 → `Prop_NoAcceptAcrossSwitch` |
| `pend_stalls_mmio` | 판정 전 되읽기 → `Prop_ReadIsSpec` |
| `req_part_from_bound` | 요청 파티션이 포트에서 옴 → `Prop_ReqPartIsBound` |
| `unaligned_outside` | `0xE15`–`0xE17` 이 `0xE14` 기입으로 처리 → `Prop_UnalignedInert` |
| `reject_loud` | 조용한 거절 → `Prop_RejectLoud` |

- 고정 속성 여섯(가드 아님 — 전부 상주 음성 run): `Inv_ObsIsSpec` · `Inv_WorkUnderBound`(격리 몸) ·
  `Prop_NoStaleWorkAfterSwitch` · `Prop_LoudOnlySpec` · `Prop_A0D1IsValueReject` · `Prop_StallOnlyPend`(정지 = 판정 사이클
  그 자체 — 대안 hold 가 반증).
- D 표집 꼴(DP-4)의 근거: 좋은 모델은 α(t 수락 → t+1 표집 · t+1 동안 접수 · MMIO 정지). 대안 β(ALLZERO(t) ∧ ¬접수(t))는
  「마지막 일이 기입과 같은 에지에 빠져나가는」 모서리에서 D = 0 을 내 적법한 전환을 거절 + `[6]` 한다(`_alt_beta` ·
  `_alt_beta_loud`) — 격리 몸은 지키고(`_alt_beta_iso` MUST PASS) 그 모서리의 전환을 영영 못 한다(`_alt_beta_edge` MUST
  PASS). 정본과 다른 관측이라 S-1 은 불필요했다. 대안 lag(α 인데 t 접수가 t+1 점유에 아직 안 듦)는 격리를 깬다
  (`Inv_WorkUnderBound`) — α 가 기대는 RTL 사실의 기록이고 그 측정은 `HiuMask/occ.sby` `h_occ_accept` · `h_occ_conserve`.
- 비정렬 `0xE15`–`0xE17` 의 처분(A · D · 결속 불변)은 정본 E.1.2 「결속 파티션의 수락 판정」 명확화가 이미 닫았다 —
  S-2 는 불필요했다.
- 실측(`run.sh` 절 머리 주석): 작은 cfg 1,233 distinct · 큰 cfg(파티션 4 · 상한 2) 7,359 distinct.
- 실측: ActivePart 절 44/44 선언대로(run [251]–[294]) · 전량 배터리 644/644 선언대로 — 컨테이너 `w4g-gate-tlc` · 2026-10-15 13:15–15:06 KST · 게이트 GREEN(「전체 644 run 이 선언대로 행동했다」 줄 — `run.sh` 종료 코드 0 경로) · 이탈 0 · 입력 sha 665건 중 663건 불변 — 두 건(`ActivePart.tla` · `MmioPage.tla`)은 배터리 끝(15:06:32) 뒤 15:06–15:07 에 바뀌었다(오케스트레이터의 배터리 뒤 주석 정정 — W4R2 결함 2 · MmioPage 는 HEAD 대비 주석 줄만 · ActivePart 는 배터리 입력 사본 대비 주석 줄 셋) — 바뀐 두 편은 15:07–15:08 절 재실행(MmioPage 29 + ActivePart 44 = 73/73 선언대로 · 게이트 GREEN · `gate-w4g/post`)으로 재확인, 그 입력 sha 665/665 = 현재 판 (부록 D 문장과 같은 판) · 이어서 `XlateObs.tla` 닫힌 목록 14 주석(점유 미측정 → W4 `h_occ_conserve`)을 고치고 XlateObs 절 41/41 선언대로 · GREEN (15:43–15:59 · `gate-w4g/post2`, XlateObs.tla sha 2611c0bf).
