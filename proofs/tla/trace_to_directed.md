<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# TLC 반례 trace → RTL directed test 시나리오 변환 (하류 ③ 검증 계획 (a))

**지위**: spec `§27.6 하류 ③ 검증 계획 선공표` 의 **(a) TLA+ 유도 directed
test** 항, 그리고 `§27.2.2 IF-2` 의 "guard-별 삭제 실험의 TLC 반례 trace 가
③ directed test 시나리오의 원천" 명문의 이행 산출물이다. 본 문서가 변환
**규칙**과 trace↔시나리오 **대응표**를, `derived/tla_directed_scenarios.json`
이 cycle-태그 명령 시퀀스 + 기대 fault 를, `derived/traces/*.trace.txt` 가
TLC 반례 원문 (결정적 extract) 을 각각 담는다. 세 산출물은 1:1:1 이다.

골든 반쪽 (§27.6 (c) — `scripts/golden_lattice.py` 확장) 과는 **별도 파일**
로 병존한다: 본 시나리오군은 순서·간격·fault 계약만 고정하고, payload 토큰
(`sA#1` 등) 에 구체 64-bit addend 벡터와 기대 word 를 바인딩하는 것은 골든
반쪽의 몫이다 (JSON `payload_binding` 항이 바인딩 인터페이스).

---

## 1. 실행 기록 (2026-08-16 재실행 — 결정성 확인 포함)

- `./run.sh` 전건: **16/16 declared 대로 — gate GREEN** (exit 0).
  MUST-PASS 2 (GOOD 완전 탐색 + large safety-only), MUST-FAIL 14
  (guard 삭제 7 + requesterid 1 + witness 6) 전부 선언된 불변식으로 실패.
- trace 확보: 14개 MUST-FAIL run 을 개별 재실행 (동일 커맨드라인,
  `-difftrace` 만 제거해 **full-state trace** 로 출력 — difftrace 는 출력
  형식만 바꾸며 BFS 탐색·반례는 동일).
- **결정성**: `-workers 1` pin 하에 각 run **2회 재실행 → trace extract
  14/14 byte-identical**. states generated 수치도 README §4 표
  (75/858/1,250/2,586/2,788/487/361/363/26/24/162/489/205/23) 와 전부 일치.
- 정리: TLC metadir (`states/`) 은 `-cleanup` 으로 소거 확인, 대용량 로그
  없음 (trace extract 총 ~100 KB 만 저장).

## 2. action → bank/lattice 인터페이스 op 사상

모델의 stream 3개 중 반례에 등장하는 것은 sA/sB (bank 0 영구 충돌쌍) 뿐
이다 — sC (bank 1) 는 전 trace 무행동이므로 시나리오에도 없다. TLC 의
action 라벨은 발화 stream 을 표기하지 않으므로 stream 귀속은 상태 delta
(`st`/`pend`/`issued` 변화) 로 복원했다.

| TLA+ action | op (JSON `op_vocabulary`) | RTL 인터페이스 의미 | fault |
|---|---|---|---|
| `RequestOwn(s)` | `ACQ_REQ` | acquire 2-phase 의 요청 반쪽 — pend staging 등록만, bank 무접촉 (`Inv_NoPhantom`; v1.9 `mu_pending_other` 동형) | — |
| `CommitOwn(s)` | `ACQ_GRANT` | T+1 accept: live bank-free 재검사 + `owner[b]:=s` + **canonical zero 기록** (IF-4 원자 acquire+zero) | — |
| `RejectOwn(s)` | `ACQ_REJECT` | T+1 refuse: 거부 + sticky, incumbent 불변 | `acq_reject` |
| `Accumulate(s)` | `WSTEP` | wave-step dispatch 1회: carry read 는 start 이전 완료 (IF-1), beat 0 carry 공급, writeback @ start+LATENCY | — |
| `AccumulateFault(s)` | `WSTEP_STRAY` | 비-owner dispatch 도착 (spill 후 in-flight) — carry 공급·writeback 거부 + sticky | `stray_acc` |
| `Drain(s)` | `DRAIN` | drain 계열 op (opcode 미지정 — README §8(i)): word read → PACK_FINAL RNE-24, release 동일 원자 사건. SRAM word 잔존 | — |
| `DrainFault(s)` | `DRAIN_STRAY` | 비-owner drain 도착 — 거부 + sticky, 값 미발행 | `stray_drain` |
| `Spill(s,m)` | `SPILL` | 0x7D: word → fp64 image (8 frags) slot m, release. word 잔존 | — |
| `Fill(s,m)` | `FILL` | 0x7D: image ingest (FILL validation (i)-(iii)) → word, 재획득, image 소비 | — |
| `FillFaultForeign(s,m)` | `FILL_FOREIGN` | 외래 image 주소 — 거부 + sticky, **image 미소비** | `fill_foreign` |
| `FillFaultBusy(s,m)` | `FILL_BUSY` | 자기 image + bank 외래 live — 거부 + sticky, **image 미소비** | `fill_busy` |
| `Zero(s)` / `ZeroFault(s)` | `ZERO_RAW` | raw 0x7E (비융합) — ownership-checked: GOOD 계약에서 핸드셰이크 밖 발행자는 owner 일 수 없어 **항상 거부** + sticky | `zero_race` |

## 3. cycle 태깅 규칙 (N=8 출하 형상: II=4, LATENCY=7)

JSON `constants.timing_rules` 와 동일 — 규범 근거를 병기한다.

- **R-T1** — `ACQ_REQ @ C` 의 짝 `ACQ_GRANT`/`ACQ_REJECT` 는 `@ C+1`
  (2-phase deferred commit; pend 단일 staging). cursor → C+2.
- **R-T2** — `WSTEP @ C`: ownership window = **[C, C+7]** (IF-2),
  writeback/done @ C+7. 같은 slot 의 다음 **chaining WSTEP 은 정확히
  C+7** 에 배치한다 — IF-3 최소 간격을 시나리오가 고의로 실증한다. 같은
  slot 의 다음 **비-WSTEP 접촉은 ≥ C+8** (창 회피). cursor → C+7/C+8.
  거부되는 `WSTEP_STRAY` 도 파이프라인 점유를 보수적으로 동일 취급.
- **R-T3** — `DRAIN`/`SPILL`/`FILL`/`ZERO_RAW` 및 모든 거부 시도는
  bank-port 추상 **1 cycle**. 실 op 의 frag FSM 다주기 확폭은 ③ RTL TB
  구현 몫이며 순서·상대 간격 계약은 불변. cursor → C+1.

**표면 스코프 (명시)**: 본 (a) 시나리오군은 TLA+ 모델의 표면 그대로 —
**stream-레벨 ownership-register 표면** — 을 cycle-태그로 고정한 것이다.
fault op 들은 전부 **창 밖 + register 소유 중** 시점에 배치했다 (거부
근거가 순수하게 ownership register 이도록). wave-step **창 내부** 접촉
(owner 자신의 접촉 포함) 의 cycle-정밀 판정 — 창 직전/직후 합법, 창 내
fault — 은 검증 계획 **(b)(3)** 의 몫이며 본 문서의 범위 밖이다.

## 4. fault 재해석 규칙 (guard 삭제 trace → armed RTL 판정)

TLC 반례는 **guard 를 지운** 모델의 오염 경로이고, 실 RTL 은 전 guard
armed 다. 변환은 §27.6 (a) 의 판정문 그대로:

- **R-F1** — trace 에서 삭제된 guard 덕에 착지한 **guilty action** (대응표
  §5 에 명기) 은 armed RTL 에서 그 guard 의 fault-경로 op 로 사상된다.
  판정: 그 cycle 에 **거부 + sticky 상승**, 그리고 guilty op 가 건드렸을
  모든 상태 (bank word / owner / mem image) 의 **불변 확인**.
- **R-F2** — guilty action **이후의 trace 꼬리** (오염 전파·오염 drain) 는
  armed RTL 에서 도달 불가하므로 자극으로 재생하지 않고, "오염이 없어야
  할 관측점" 으로 재해석한다 (예: DT-07 의 Drain 은 참값 drain 으로 —
  TLC 의 '정상적으로 생긴 0.0' 반증 관측).
- **R-F3** — **`commit_zero` 특례**: 삭제 대상이 guard 술어가 아니라
  acquire 의 **zero 효과**이므로 fault-경로가 없다. DT-02 는 sticky 전
  구간 0 인 **값 판정** 시나리오다 — 판정점은 재acquire 직후 wave-step 의
  beat-0 carry == canonical zero (stale SRAM word 차단).
- **R-F4** — fault 시나리오당 fault op 은 **정확히 1개**다 (per-guard
  1-run-1-guard 귀속의 보존). 따라서 sticky 가 원인별 bit 가 아니라 v1.9
  `bank_tag_collision_error` 등급의 **단일 sticky bit** 로 구현되어도
  시나리오군의 원인 귀속은 유지된다 (입도는 ③ 구현 몫 — README §9.9).
- **R-F5** — 각 fault 시나리오는 **mutation check** 를 동반한다: RTL 의
  대응 guard 를 제거한 변이에서 같은 자극이 TLC 반례의 오염을 재현하며
  test FAIL 해야 한다 (TLA+ 삭제 실험 ↔ RTL 변이 실험의 대칭 — §5.1
  하중-가드 규율의 RTL 이식).
- **R-W1** — **witness 6건**은 fault 없는 **도달성** 시나리오다: 전 구간
  sticky == 0 + 도달 상태 관측이 판정이며, 각 witness 가 무장(arm)하는
  fault 시나리오를 `arms` 필드로 지목한다 (도달한 상태에서 해당 fault op
  를 인가하면 대응 DT 시나리오의 fault 판정으로 이어진다).

## 5. trace ↔ 시나리오 대응표

| run | cfg (`AccBank_*.cfg`) | TLC 위반 불변식 | trace (states) | 시나리오 | guilty action (trace state) | 기대 sticky @ cycle | 판정 요지 |
|---|---|---|---|---|---|---|---|
| 03 | `del_commit_free` | `Inv_OwnerAgreement` | 5 | **DT-01** | `CommitOwn(sB)` (5) | `acq_reject` @ 3 | 탈취 거부, owner[0]==sA 불변 |
| 04 | `del_commit_zero` | `NoSilentAliasing` | 8 | **DT-02** | `CommitOwn(sB)` zero 효과 부재 (7) | **없음** (R-F3) | sB 첫 carry == canonical zero (stale 차단) |
| 05 | `del_acc_owner` | `NoSilentAliasing` | 8 | **DT-03** | `Accumulate(sA)` stray (7) | `stray_acc` @ 5 | stray 거부, sB word 무오염 |
| 06 | `del_drain_owner` | `Inv_NoCrossContextLeak` | 10 | **DT-04** | `Drain(sA)` stray (10) | `stray_drain` @ 28 | leak 차단, sB partial 불변 |
| 07 | `del_fill_owner` | `Inv_NoCrossContextLeak` | 10 | **DT-05** | `Fill(sB←m0)` foreign (9) | `fill_foreign` @ 14 | 외래 image 거부·미소비 |
| 08 | `del_fill_bankfree` | `Inv_OwnerAgreement` | 7 | **DT-06** | `Fill(sA←m0)` busy (7) | `fill_busy` @ 5 | incumbent (sB) 불변, image 미소비 |
| 09 | `del_zero_owner` | `Inv_Value` | 7 | **DT-07** | `Zero(sB)` raw 0x7E (6) | `zero_race` @ 17 | zero 거부, drain == 참값 (0.0 아님) |
| 10 | `requesterid` | `Inv_Value` | 7 | **DT-08** | `Zero(sB)` (6) | `zero_race` @ 17 | 자극 = DT-07 과 동일 (아래 주석) |
| 11 | `witness_reject` | `Witness_NoAcquireContention` | 4 | **WT-01** | — (도달) | 없음 (sticky==0) | 경합 상태 도달 — arms DT-01 |
| 12 | `witness_stray_acc` | `Witness_NoStrayAccumulate` | 4 | **WT-02** | — | 없음 | stray-acc 도착면 도달 — arms DT-03 |
| 13 | `witness_stray_drain` | `Witness_NoStrayDrain` | 6 | **WT-03** | — | 없음 | stray-drain 도착면 도달 — arms DT-04 |
| 14 | `witness_fill_foreign` | `Witness_NoForeignFillTarget` | 7 | **WT-04** | — | 없음 | 두 image 공존 도달 — arms DT-05 |
| 15 | `witness_fill_busy` | `Witness_NoBusyFill` | 6 | **WT-05** | — | 없음 | busy-fill 상태 도달 — arms DT-06 |
| 16 | `witness_zero_window` | `Witness_NoZeroRaceWindow` | 4 | **WT-06** | — | 없음 | zero-race 창 개방 도달 — arms DT-07 |

**run 10 주석**: `requesterid` (전 가드 삭제) 의 BFS 최단 반례는
`del_zero_owner` 의 반례와 **action-열 단위로 동일**함을 실측 확인했다
(state 열 diff 공집합; states generated 만 361 vs 363). 따라서 DT-08 은
별도 자극이 아니라 DT-07 자극의 재사용 + 서사 기록이다 — 개별 귀속은
DT-01..07 (1 guard : 1 시나리오) 의 몫이라는 §5.3 규율 그대로.

**커버리지 확인**: §27.6 (a) 가 요구한 ownership loud-fault 경로 6종 —
RejectOwn / AccumulateFault / DrainFault / FillFaultForeign /
FillFaultBusy / ZeroFault — 는 각각 DT-01/03/04/05/06/07 이 fault 판정으로
커버한다 (IF-2 명기의 "창 내 FILL 외래-image 변형 = FillFaultForeign 포함"
충족). guard 7종 중 fault-경로가 없는 `commit_zero` 는 R-F3 값-판정
(DT-02) 으로 커버 — 7/7 + requesterid + witness 6/6 = **14/14 변환 완료**.

## 6. trace 파일 결정성 (sha256)

`derived/traces/*.trace.txt` 는 TLC 출력에서 wall-clock 줄만 제거한
결정적 extract 다 (헤더 3줄 주석 + `Error:` 이후 전문). 2회 재실행
byte-identical 확인 후의 sha256:

| trace | sha256 |
|---|---|
| `del_commit_free` | `fa5c28cd628765f45b2f4a77c09f1d30a1a847ced5cc11273a37214fe261a7c5` |
| `del_commit_zero` | `c1c19681518116aeaae6131190e8e043571fdd502c4bd609aaf8e870bf29f48c` |
| `del_acc_owner` | `4f911102803c2a8856de42620d02f50ff891e9cd50b30a12d448597ae9d96e3c` |
| `del_drain_owner` | `73a2cc8cc9b5820942fed8f1e69d06e1c440921e63cb1a676f02803ef9bf7142` |
| `del_fill_owner` | `951e1eb4b5b3e1a87e99b59ab359321fc15c7972f493ce63c7c046607891f820` |
| `del_fill_bankfree` | `a2f01cf619277e1da73cb40decab574021c179bf3b47eead75f94c547879b9c6` |
| `del_zero_owner` | `01a4353f7c26263a81c936857f35cadfa1dd265d8c47fada0fee18dcdc6624be` |
| `requesterid` | `506267a5178213b2e01db17c23e072f49306a7fe04435efa310d4b232e488149` |
| `witness_reject` | `a45c4a87294362815a8d2367a7a8cbdf740556d8fb510b00d01c8787fe448389` |
| `witness_stray_acc` | `1dba1325c8f85b2bb1db11e7f02709c7c70a29127354fd5d68c58bad3e820234` |
| `witness_stray_drain` | `60494d1b3e9acb7d4677ee5d40c5f26042391f7b4ed916981c4169b67f5f0c9a` |
| `witness_fill_foreign` | `4af0cef8b0ad18576c24ebc132a0d5312cfd260676fd5513eba0a49fa10f75ca` |
| `witness_fill_busy` | `8ee62a4c9517843e74bf11c0a0053d0777b9bed2f7cf81cb243322c3caad890d` |
| `witness_zero_window` | `57e48ffb93a4ba48faf1697cd2ba94afa7f82311e2f690b7bd1c0a09b6c45676` |

모델/cfg 가 변하면 trace 와 본 표·JSON 을 **같은 commit 에서** 재생성해야
한다 (원천은 언제나 `run.sh` 의 TLC 실행 — 시나리오는 유도물이다).

## 7. 전제·경계 (정직 기록)

1. **ghost 상속 (README §8 (h)/(l))**: DT-05 의 `fill_foreign` 판정은
   spill image 의 owner-tag 캐리어를, DT-04 의 issued==K 전제는 K 완결
   캐리어를 전제한다. ③ RTL 이 캐리어를 실물화하지 않는 한 해당 검사는
   TB scoreboard (ghost) 대조로 수행하고 그렇다고 기록해야 한다.
2. **sticky 입도**: 원인 후보 6종의 원인별 bit 분리는 ③ 구현 선택 —
   최소 계약은 합성 가능한 단일 sticky (§26.5 선례, sim-only 금지).
   R-F4 에 의해 어느 입도든 본 시나리오군의 귀속은 유지된다.
3. **cycle 수치의 조건부**: 모든 cycle 태그는 N=8 출하 형상 (II=4,
   LATENCY=7) 조건부다. `PRODUCTS_PER_BEAT` 변경 시 R-T2 의 7/8 이
   `LATENCY`/`LATENCY+1` 로 치환된다 (JSON 은 상수와 규칙을 분리 보관).
4. **드레인 opcode 미지정** (README §8 (i)) 은 본 변환에서도 추상 op
   (`DRAIN`) 로 유지 — opcode 배정은 spec 몫이며 시나리오 의미 불변.
5. **본 시나리오군이 증명하지 않는 것**: 수치 정확성 (골든 반쪽 몫),
   창 내부 cycle-정밀 판정 ((b)(3) 몫), gap-후 재시작 ((b)(2) 몫),
   liveness/공정 arbiter (README §7 — RTL 의 ASSUMED 의무).

## 8. 파일

| 파일 | 역할 |
|---|---|
| `trace_to_directed.md` | 본 문서 — 변환 규칙 + 대응표 (문서 1개 규율) |
| `derived/tla_directed_scenarios.json` | 시나리오 14건 — cycle-태그 op 열 + 기대 sticky/상태 (기계가독) |
| `derived/traces/*.trace.txt` | TLC 반례/도달 trace 결정적 extract 14건 (provenance) |
