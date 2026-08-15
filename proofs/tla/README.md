<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# `proofs/tla/` — WaveTensor formal models (TLA+)

WaveTensor 의 **첫 formal artifact**. 디렉터리 관례는 자매 repo
[`/home/ybi/Y4`](../../../Y4) 의 `proofs/{coq,isabelle,verus}` 를 따른다
(Y4 는 Rust/seL4 대면이라 Verus/Rocq/Isabelle, WaveTensor 는 동시성
아키텍처 상태라 TLA+ — 도구는 다르되 `proofs/<tool>/` 배치는 동일).

현재 모델 1종: **`AccBank`** — v2.0 "TRAIN" 의 fp32 ACC bank
ownership/drain 계약.

---

## 1. 왜 이것이 gate 인가

spec `§23.7` residual risk 3 (`.claude-memos/wt64v1_spec.md:2122`):

> ACC bank 는 순수 tagged-wave 모델 밖의 신규 architectural state —
> tag-keyed bank aliasing 은 silent-gradient-corruption 클래스.
> **RTL 전에 TLA+/formal 선행** (wavetensor-drivers formal-first 관례).

그리고 `§23.8` 진입 조건 (4): "**ACC bank TLA+ — v2.0 전** (v1.8 스코프
아님)". 즉 본 모델이 green 이 되기 전에는 v2.0 ACC bank RTL 을 쓰지
않는다. 본 디렉터리가 그 gate 의 실체다.

### 무엇이 위험한가 (정확한 진술)

spec `§23.1` (`wt64v1_spec.md:2012`) 의 ACC bank 규범 텍스트는 **한 줄이
전부**다:

> **fp32 ACC bank** (2 × 32 lanes × 32b/cluster, tag `pcid[1:0]` 로 bank
> 선택 + 명시적 ownership/drain 계약 + ACC_SPILL/FILL) — "requester ID"
> 식 암묵 계약은 반증되어 폐기.

여기에 **구조적 산술 모순**이 들어 있다: `pcid[1:0]` 은 값이 4개인 2-bit
선택자인데 bank 는 2개뿐이다. 게다가

* `pcid` 는 spec 에 정의가 없고, RTL 에서는 `port_context_id =
  tag[31:16]` 이며 (`EHDecode.v:363-367`), 그 비트는 이미 라우팅이
  전부 점유한다 — `Pod.v:132` 가 `pcid[7:4]` 를 cluster index 로,
  `Cluster.v:500` 이 `pcid[3:0]` 를 PE index 로 쓴다.
* forwarded tag 에서 `pcid` 는 `{8'h00, eff_output_port_id}` 로 **재구성**
  된다 (`EHDecode.v:561`) — 즉 bank 키의 실체는 프로그램이 고르는
  `output_port_id[1:0]` 이지 하드웨어 고유 context id 가 아니다.
* 반면 누산의 **논리적 정체성**은 80-bit tag 전체에 걸쳐 있다
  (`wave_number[79:48]` / `thread_id[47:32]` / `pcid[31:16]` / ...).

따라서 bank 키는 stream 정체성에 대해 **설계상 심하게 non-injective**
하다. `pcid[1:0]` 만 같고 나머지 어디가 달라도 같은 bank 로 간다.
막는 것이 없으면 drain 결과는 **정상적으로 생긴 유한 fp32 인데 값만
틀린** 것이 된다 — `error_flag` 없음, `lower_required` 없음, status bit
없음. 증상은 수천 step 뒤의 잘못된 gradient 하나뿐이다. 이것이
silent-gradient-corruption 클래스다.

본 모델은 그 non-injective 키를 **일부러 그대로 넣고**
(`ASSUME AliasingIsExercised` — 두 stream 이 충돌하지 않는 config 는 TLC
가 아예 거부한다), 그럼에도 명시적 ownership/drain 계약이 corruption 을
**도달 불가능**하게 만든다는 것을 증명한다.

---

## 2. 실행 방법

```sh
cd proofs/tla
./run.sh              # 16개 run 전부 — 2개는 PASS, 14개는 FAIL 해야 함
```

개별 실행 (`tlc` = tla2tools 2.19, `/usr/bin/tlc`):

```sh
tlc AccBank.tla                                         # GOOD -> 통과해야 함
tlc -config AccBank_large.cfg          AccBank.tla      # GOOD, 4 stream 스케일 체크
tlc -config AccBank_del_<guard>.cfg    AccBank.tla      # 가드 1개 삭제 실험 (7종) -> 각자 실패해야 함
tlc -config AccBank_requesterid.cfg    AccBank.tla      # 전 가드 삭제 = 반증된 설계 -> 실패해야 함
tlc -config AccBank_witness_<name>.cfg AccBank.tla      # hazard 도달성 witness (6종) -> 실패해야 함
```

`run.sh` 는 각 run 이 **선언된 대로** 동작했는지 grep 으로 확인하고
아니면 non-zero exit 한다 — 그대로 merge gate 로 쓸 수 있다.

`run.sh` 는 **`-workers 1` 로 고정**되어 있다. MUST-PASS run 의 상태
수는 완전 탐색이므로 스케줄링과 무관하지만, MUST-FAIL run 이 반례를
만나기까지 생성하는 상태 수는 BFS 방문 순서 = worker 스레드 스케줄링에
의존한다. 실측: `del_fill_owner` 를 1 worker 로 두 번 돌리면 두 번 다
2,788 states generated (비트 단위 동일), 4 workers 로 두 번 돌리면
2,471 / 2,437 로 흔들린다. §4 의 모든 수치는 그래서 재현 가능하다.
(반례의 **길이와 위반 불변식**은 worker 수와 무관하게 동일하다.)

> Apalache 는 이 머신에 없다. 모델은 **TLC-checkable** 하도록,
> 즉 유한하고 작은 상수로 작성했다 (symbolic 도구 불필요).

---

## 3. 무엇을 증명하는가

값은 **불투명 토큰**이다. contribution 하나는 `[str |-> s, idx |-> i]`
이고 bank cell 은 그 토큰의 **순서 있는 시퀀스** — 해석되지 않은 ⊕-항을
적용 순서대로 기록한 것이다. fp32 산술은 전혀 모델링하지 않는다.
이 인코딩에서 두 가지가 공짜로 따라온다: 정체성 오염은 "한 시퀀스에 두
stream 의 토큰이 섞임", 순서 오염은 "`idx` 가 오름차순 canonical prefix
가 아님".

모델의 두 가지 구조적 선택이 §5 의 측정 결과를 만든다:

* **SRAM 의미론 (stale retention).** `Drain` 과 `Spill` 은 bank 를
  release 하되 cell 을 **지우지 않는다** — 하드웨어 store 는 SRAM 을
  scrub 하지 않는다. 따라서 acquire 시점의 zero (`CommitOwn` 의
  `commit_zero` 효과 = 0x7E 의 원자 형태)가 이전 owner 의 stale partial
  과 새 owner 사이에 있는 **유일한** 방어다.
* **attempt surface.** 하드웨어는 "소프트웨어가 자기가 주장하는 상태에
  있다"를 신뢰할 수 없다. v1.9 파이프라인드 dispatch 에서는 0x7D SPILL
  이 retire 한 뒤에도 VFMA_ACC/drain 이 in flight 일 수 있고, acquire
  핸드셰이크 밖에서 raw 0x7E 가 날아올 수 있다. 모델은 그 **시도 자체를
  허용**하고, 하드웨어 가드가 거절 + sticky fault 로 **응답**한다 —
  v1.9 bank table 이 충돌 launch 시도를 허용하고
  `bank_tag_collision_error_r` (Cluster.v:1036) 로 응답하는 것과 같은
  규율이다. 가드가 하중을 받는 것은 정확히 이 표면 때문이다 (§5.2).

| 이름 | 진술 | 종류 |
|---|---|---|
| **`NoSilentAliasing`** | **중심 불변식.** 기계 안의 어떤 누산 ⊕-항(bank cell 또는 spill slot)도 둘 이상의 stream 의 contribution 을 담지 않는다. release 된 bank 의 stale 단일-owner 데이터는 허용 (SRAM), **혼합은 절대 불가** | safety |
| `Inv_Exclusive` | **owned** bank 안의 모든 토큰은 owner 의 것. (release 된 bank 는 이전 owner 의 stale 을 가질 수 있다 — 읽으려면 acquire 가 필요하고 acquire 는 zero 하므로 죽은 데이터다) | safety |
| `Inv_OwnerAgreement` | 하드웨어 ownership 레지스터와 stream 측 시각이 절대 어긋나지 않음 (모든 corruption trace 의 선행 상태) | safety |
| `Inv_NoPhantom` | 요청됐지만 아직 commit 되지 않은 claim 은 ownership 레지스터에 나타나지 않음 (v1.9 residual risk 11 의 phantom row) | safety |
| `Inv_Canonical` | owned bank 내용은 owner 자신의 contribution 을 **ascending wave-order K** 로, 빠짐 없이 순서 그대로 담고 있음 | safety |
| `Inv_Complete` | drain 은 짧은 누산을 내보내지 않음 (`Len = K`) | safety |
| `Inv_NoCrossContextLeak` | 어떤 spill slot 도 drain 결과도 타 context 데이터를 나르지 않음 (corruption 과 구별되는 **leak**). NSlots ≥ 2 에서 비로소 비공허 — §5.2 (iii) | safety |
| **`Inv_Value`** | **payoff.** stream 이 기계에서 꺼낸 값 = ghost reference accumulator, 즉 자기 자신의 K 개 contribution 을 정확히 canonical 순서로 접은 항. 더도 덜도 아님 | safety |
| `Liveness` | 모든 stream 이 결국 drain 한다 — sA·sB 가 bank 0 에서 **영구히 충돌**함에도. **조건부 결과 — §6 의 ASSUMED 공정성 의무 참조** | temporal |
| `NoOwnershipLeak` | 끝난 stream 이 bank 를 영원히 붙들지 않음 (동일 조건부) | temporal |

`Inv_Value` 가 최상위 정리인 이유: 실패 양상이 deadlock 도 error 도
아니고 **깔끔하게 생긴 틀린 수**이기 때문이다. ghost accumulator 없이는
"silent" 자체를 표현할 수 없다.

### 모델링된 corruption 경로

spec risk 3 이 가리키는 경로 전부에 대해, **가드 삭제 run (§5.1) 이
정확히 그 경로의 반례를 산출**한다:

1. **write-write alias** — 두 stream 이 같은 bank 에 번갈아 누적
   (`acc_owner` 삭제 → `NoSilentAliasing` 반례)
2. **zero race** — 남의 누산 도중 raw `0x7E FP_ACC_ZERO` 착지
   (`zero_owner` 삭제 → `Inv_Value` 반례; §6 전체가 이것)
3. **stale-SRAM alias** — acquire 가 zero 하지 않으면 이전 owner 의
   stale partial 이 새 누산에 접힘 (`commit_zero` 삭제 →
   `NoSilentAliasing` 반례)
4. **spill/fill alias + leak** — FILL 이 남의 image 를 복원하거나
   (`fill_owner` 삭제 → `Inv_NoCrossContextLeak` 반례), 살아 있는
   bank 을 덮음 (`fill_bankfree` 삭제 → `Inv_OwnerAgreement` 반례)
5. **stray drain leak** — spill 후 in-flight drain 이 남의 live partial
   을 읽어감 (`drain_owner` 삭제 → `Inv_NoCrossContextLeak` 반례)
6. **short drain** — K 개 중 j < K 만 착지한 상태에서 drain.
   `Drain` 의 `issued[s] = K` 는 **ghost 가드**라 삭제 실험 대상이
   아니다 — 오늘의 하드웨어에는 검사할 캐리어 자체가 없다. §8 (h).

---

## 4. 실측 결과 (재현 가능)

TLC 2.19 (`/usr/share/java/tla2tools.jar`), Linux/JDK, **`-workers 1`**
(§2 의 결정성 규율 — `run.sh` 가 그대로 고정한다). 표의 모든 수치는
`./run.sh` 한 번의 출력이다.

| # | run | 결과 | states generated | distinct | depth |
|---|---|---|---|---|---|
| 01 | `AccBank` (GOOD, 불변식 9 + temporal 2) | **No error** (완전 탐색) | 14,021 | **2,524** | 17 |
| 02 | `AccBank_large` (GOOD, 4 stream / K=3 / 양 bank 경합, safety only) | **No error** (완전 탐색) | 296,321 | **42,330** | 26 |
| 03 | `del_commit_free` | `Inv_OwnerAgreement` **violated** | 75 | 42 | 반례 **5 states** |
| 04 | `del_commit_zero` | `NoSilentAliasing` **violated** | 858 | 282 | 반례 **8 states** |
| 05 | `del_acc_owner` | `NoSilentAliasing` **violated** | 1,250 | 489 | 반례 **8 states** |
| 06 | `del_drain_owner` | `Inv_NoCrossContextLeak` **violated** | 2,586 | 777 | 반례 **10 states** |
| 07 | `del_fill_owner` | `Inv_NoCrossContextLeak` **violated** | 2,788 | 862 | 반례 **10 states** |
| 08 | `del_fill_bankfree` | `Inv_OwnerAgreement` **violated** | 487 | 175 | 반례 **7 states** |
| 09 | `del_zero_owner` | `Inv_Value` **violated** | 361 | 160 | 반례 **7 states** |
| 10 | `requesterid` (전 가드 삭제) | `Inv_Value` **violated** | 363 | 170 | 반례 **7 states** |
| 11 | `witness_reject` | `Witness_NoAcquireContention` **violated** | 26 | 15 | 반례 4 states |
| 12 | `witness_stray_acc` | `Witness_NoStrayAccumulate` **violated** | 24 | 13 | 반례 4 states |
| 13 | `witness_stray_drain` | `Witness_NoStrayDrain` **violated** | 162 | 75 | 반례 6 states |
| 14 | `witness_fill_foreign` | `Witness_NoForeignFillTarget` **violated** | 489 | 176 | 반례 7 states |
| 15 | `witness_fill_busy` | `Witness_NoBusyFill` **violated** | 205 | 91 | 반례 6 states |
| 16 | `witness_zero_window` | `Witness_NoZeroRaceWindow` **violated** | 23 | 12 | 반례 4 states |

두 GOOD run 모두 **완전 탐색**이다 — `states left on queue` = 0,
`-simulate` 아님, state constraint 없음. 상태공간이 폭발하지 않은 이유는
상수를 작게 잡았기 때문이고, 그 선택의 정당성은 §7 에 적었다.

run 01 의 temporal 검사는 tableau 4 branches / 총 10,096 distinct
states 이며 약 1분 49초 걸린다 (safety 부분은 1초 미만; run 02 는
safety only 라 296k states 를 1초에 끝낸다). 즉 **비용은 전부 liveness
쪽**이고, 이것이 `AccBank_large` 를 safety only 로 돌린 이유다 (§7).

**deadlock 검사에 대한 정직한 각주**: `-deadlock` 플래그를 주지 않았
으므로 TLC 기본 deadlock 검사는 켜져 있고 두 GOOD run 모두 통과했다.
다만 이전 draft 와 달리 이것을 증거로 세지 **않는다** — 현 모델의
fault 액션들(`AccumulateFault` 등)은 sticky bit 이 이미 올라간 상태에서
self-loop successor 를 제공하므로, deadlock 부재는 이제 대부분 자명하게
성립한다. 유의미한 진행성 주장은 전적으로 `Liveness`(§6 조건부)가
담당한다.

기본 config: `Streams = {sA, sB, sC}`, `Pcid = [sA↦0, sB↦2, sC↦1]`,
`NBanks = 2`, `K = 2`, `NSlots = 2`. `BankOf(p) = p % 2` 이므로 **sA 와
sB 는 bank 0 에서 영구 충돌**한다 (0 % 2 = 2 % 2 = 0). sC 는 bank 1.

`AccBank_large` 는 stream 4개(`sD` 추가, `Pcid = 3`), `K = 3`, **양쪽
bank 모두 충돌쌍**을 갖는다. safety only — 이유는 §7 마지막 항목.

---

## 5. 모델이 이빨을 갖는다는 증거 — 측정이지 주장이 아니다

통과하지만 실패할 수 없는 formal model 은 가치가 0 이다. 나아가 **"이
가드가 하중을 받는다"는 문장 자체도 측정 대상**이다: 가드를 지웠는데
TLC 출력이 그대로면 그 가드는 죽은 코드다. 본 디렉터리의 규율은 RTL
gate 와 동일하다 — **주장하려면 그 주장을 깨는 실험을 함께 싣는다.**

### 5.1 하중 가드 표 (per-guard 삭제 실험으로 측정됨)

`DisabledGuards` 상수가 가드 집합을 받는다. `{}` 가 GOOD 모델이고,
가드 삭제는 **소스 편집이 아니라 `.cfg` 한 줄**이다. 아래 표의 각 행은
`run.sh` 의 MUST-FAIL run 하나와 1:1 대응하며, **이 표에 실리는 유일한
자격 요건은 "그 가드 하나만 지운 run 이 아래 불변식의 반례를 산출했다"
이다** (§4 run 03–09 의 수치가 그 실측이다).

| 가드 | 위치 | 지키는 것 | 삭제 시 위반 (측정) | 반례 |
|---|---|---|---|---|
| `commit_free` | `CommitOwn` / fault 경로 `RejectOwn` | 살아 있는 bank 탈취 금지 — 거절 + sticky fault 로 응답 | `Inv_OwnerAgreement` | 5 states |
| `commit_zero` | `CommitOwn` (효과) | acquire 가 stale SRAM 을 scrub — 이전 owner 의 partial 이 새 누산에 접히는 것을 금지 | `NoSilentAliasing` | 8 states |
| `acc_owner` | `Accumulate` / `AccumulateFault` | spill 후 in-flight VFMA_ACC 가 남의 bank 에 착지하는 것을 금지 | `NoSilentAliasing` | 8 states |
| `drain_owner` | `Drain` / `DrainFault` | in-flight drain 이 남의 live partial 을 읽어가는 것을 금지 | `Inv_NoCrossContextLeak` | 10 states |
| `fill_owner` | `Fill` / `FillFaultForeign` | FILL 이 **남의** spill image 를 복원하는 것을 금지 (leak) | `Inv_NoCrossContextLeak` | 10 states |
| `fill_bankfree` | `Fill` / `FillFaultBusy` | FILL 이 살아 있는 남의 bank 위에 착지하는 것을 금지 | `Inv_OwnerAgreement` | 7 states |
| `zero_owner` | `Zero` / `ZeroFault` | raw 0x7E 가 남의 누산을 zero 하는 것을 금지 (**zero race**, §6) | `Inv_Value` | 7 states |

`Spill` 과 `RequestOwn` 은 하드웨어 가드를 **주장하지 않으므로** 표에
없다 (spill 의 owner 일치는 `Inv_OwnerAgreement` 가 이미 보장하는
표면에서만 발화하고, slot 선택은 소프트웨어 주소 선택이다).
`Drain` 의 `issued[s] = K` 는 **ghost** 라 측정 불가능하다 — §8 (h).

### 5.2 이전 draft 의 부검 — 죽은 가드 4개

이 표가 지금의 모양이 된 이유를 기록한다. 이전 draft 는 "하중 가드
5개"를 **주장**했지만, per-guard 삭제 실험은 그중 **4개가 죽어 있음**을
보였다 — `Accumulate` 의 owner 검사, `Drain` 의 owner 검사, `Fill` 의
`mem.own = s`, `CommitOwn` 의 bank zero 를 각각 지워도 TLC 출력이
**바이트 단위로 동일**했다 (2,186 / 843 / depth 18, no error).
각각의 사인(死因)과 처방:

| 죽은 가드 | 사인 | 처방 (현 모델) |
|---|---|---|
| `Accumulate` owner 검사 | `st[s]="own" ⇒ owner[BankKey(s)]=s` 가 그 자체로 GOOD 모델의 불변식 (= `Inv_OwnerAgreement`) — FSM 이 비-owner 의 시도 자체를 배제해서 가드가 볼 것이 없었다 | attempt surface 확장: spill 후 in-flight op 이 "spilled" 상태에서 도착한다. 가드가 그것을 멈추고 (`AccumulateFault` sticky), 지우면 착지한다 (run 05) |
| `Drain` owner 검사 | 동일 (검증자가 보고한 3건 외에 삭제 실험이 추가로 찾아낸 **4번째** 죽은 가드) | 동일 처방 (run 06) |
| `Fill` `mem.own = s` | spill slot 이 1개면 `st[s]="spilled" ⇒ mem.own = s` — 외래 image 가 존재할 수 없어 가드가 공허했다. `Inv_NoCrossContextLeak` 의 mem 절도 같이 공허했다 | `NSlots ≥ 2` (ASSUME 로 고정). 두 context 의 image 가 공존하고 (run 14 witness), FILL 이 남의 slot 을 주소할 수 있으며, 가드를 지우면 leak 이 관통한다 (run 07) |
| `CommitOwn` bank zero | `Drain`/`Spill` 이 release 때 bank 를 지웠으므로 `BankFree(b) ⇒ bank[b] = <<>>` — zero 가 빈 cell 에 <<>> 를 덮어썼다 | SRAM 의미론: release 는 cell 을 남긴다. acquire-zero 가 stale 방어의 전부가 되고, 지우면 stale 이 새 누산에 접힌다 (run 04) |

교훈을 규율로 고정한 것이 §5.1 의 자격 요건과 `run.sh` 의 run 03–09 다.
가드가 죽으면 **gate 가 빨갛게 변한다** — README 가 아니라 스크립트가
그것을 감시한다.

### 5.3 반증된 설계 — `AccBank_requesterid.cfg`

`DisabledGuards = AllGuardsDeleted` 는 spec §23.1 이 반증했다고 기록한
설계 그 자체다: bank 는 `pcid[1:0]` 슬라이스로 고르고, 누산기의 주인은
**선언되는 게 아니라 지금 dispatch 하는 자로부터 추론**된다. run 10 이
그것을 종단 silent corruption (`Inv_Value` 반례, fault 없음) 으로
보인다. **이 run 은 원인을 특정 가드에 귀속시킬 수 없다** — 귀속은
run 03–09 (가드 하나씩) 의 몫이고, 이 run 은 서사적 반증으로만 존재한다.

### 5.4 hazard 도달성 witness 6종 — GOOD 모델이 **왜** 통과하는가

GOOD 모델이 통과한다는 사실만으로는 아무것도 증명되지 않는다. 가드가
막을 상황이 애초에 도달 불가능한 모델도 똑같이 통과하기 때문이다 —
바로 그 방식으로 이전 draft 의 가드 4개가 죽어 있었다 (§5.2). 그래서
**가드마다 그 가드의 발화 조건이 GOOD 모델에서 실제로 도달됨**을
고의로-거짓인 불변식의 반례로 증명한다 (run 11–16):

| witness | 도달함을 증명하는 상황 | 대응 가드 |
|---|---|---|
| `Witness_NoAcquireContention` | 살아 있는 외래 owner 와 실제로 경합하는 claim | `commit_free` |
| `Witness_NoStrayAccumulate` | 비-owner 상태에서 하드웨어에 도착하는 accumulate 시도 | `acc_owner` |
| `Witness_NoStrayDrain` | 비-owner 상태에서 도착하는 drain 시도 (issued = K) | `drain_owner` |
| `Witness_NoForeignFillTarget` | 서로 다른 두 context 의 spill image 공존 + fill 가능 상태 | `fill_owner` |
| `Witness_NoBusyFill` | 자기 image 준비 완료 + bank 는 외래 owner 가 live 점유 | `fill_bankfree` |
| `Witness_NoZeroRaceWindow` | 외래 owner 가 비어 있지 않은 누산을 들고 있는 bank 에 raw 0x7E 발행 가능 | `zero_owner` |

즉 safety 가 성립하는 이유는 계약이 위험을 **가두기** 때문이지, 위험이
없어서가 아니다. (witness 는 모두 상태 술어다 — fault 사건의 선행
상태가 도달되면 해당 fault 액션은 `Next` 에 의해 발화 가능하다.)

### 5.5 config 자체의 비공허성 — ASSUME 2종

```tla
ASSUME AliasingIsExercised ==
    \E a, b \in Streams : a # b /\ BankKey(a) = BankKey(b)

ASSUME AssumeSlots == NSlots \in Nat /\ NSlots >= 2
```

충돌쌍이 없는 config 는 aliasing 에 대해, slot 1개짜리 config 는
spill/fill leak 에 대해 아무것도 증명하지 못하므로 TLC 가 실행을
거부한다. 실측 (`NBanks` 를 4로 바꿔 충돌 제거 / `NSlots = 1`):

```
Error: Assumption line 216, col 5 to line 216, col 58 of module AccBank is false.
Error: Assumption line 224, col 23 to line 224, col 51 of module AccBank is false.
```

미래에 누가 상수를 만지다가 gate 를 조용히 무력화하는 것을 막는다.
(`NSlots ≥ 2` 가 필요한 이유의 실측 근거는 §5.2 의 `fill_owner` 행이다.)

---

## 6. 0x7E FP_ACC_ZERO — zero race, 이제 모델 안에 있다

`0x7E FP_ACC_ZERO` 는 ISA 행 그대로 읽으면 "bank 에 대고 발행할 수 있는
zeroing op" 이다. 모델은 그것을 **독립 액션 `Zero`** 로 문자 그대로
넣었고, 두 개의 run 이 권고의 양면을 **측정**한다:

**(a) 무가드 raw 0x7E → race 가 실제로 잡힌다** (run 09,
`AccBank_del_zero_owner.cfg`, `Inv_Value` 반례 7 states):

```
State 3: <CommitOwn>    owner = (0 :> "sA" ...)          sA 가 bank 0 획득
State 4-5: <Accumulate> bank = (0 :> <<sA:1, sA:2>> ...) 정상 누적 (issued = K)
State 6: <Zero>         bank = (0 :> <<>> ...)           sB 의 raw 0x7E 가 착지 — 가드가 없다
State 7: <Drain>        drained[sA] = [has |-> TRUE, val |-> <<>>]
                        conflict = FALSE
```

sA 는 K 개를 정상 누적했고, 외래 raw 0x7E 가 그 사이에 착지해 bank 를
비웠으며, sA 는 `<<sA:1, sA:2>>` 대신 `<<>>` 를 drain 했다. `conflict =
FALSE`. fp32 로 옮기면 "**정상적으로 생긴 0.0**" — gradient 가 통째로
증발했는데 어떤 status bit 도 올라가지 않는다.

**(b) 소유권 검사 + acquire-zero 원자화 → race 배제** (run 01: GOOD
모델 완전 탐색 통과; run 16: race 의 창이 GOOD 모델에서 **실제로
열림**을 witness 로 증명 — 배제가 공허하지 않다).

여기서 나오는, **측정으로 뒷받침되는** 권고:

> v2.0 spec 은 0x7E 를 다음 중 하나로 규범화해야 한다 — (i) acquire 와
> zero 를 **한 원자 사건**으로 융합 (모델의 `CommitOwn`; 2-phase
> request/commit, T+1 에 live 재검사), 그리고/또는 (ii) 독립 0x7E 를
> 허용하되 **하드웨어가 owner 일치 검사** 후 불일치는 거절 + sticky
> fault. 무가드 0x7E 는 곧바로 silent-gradient-corruption 이다 (run 09).

---

## 7. 상수 선택의 정당성 (상태공간 폭발 없음)

`K = 2` 는 **write-write alias 를 낼 수 있는 최소값**이다: 외래 사건
하나가 두 contribution 사이에 끼어들려면 contribution 이 최소 2개여야
한다. stream 3개는 "충돌쌍 + 무관한 제3자"의 최소 구성이고,
`NBanks = 2` 는 spec 의 실제 bank 수, `NSlots = 2` 는 spill/fill leak
hazard 가 도달 가능해지는 최소값이다 (§5.2 — 1개면 공허, ASSUME 가
거부).

작은 config 가 걱정되어 **4 stream / K=3 / 양쪽 bank 모두 충돌쌍**인
`AccBank_large.cfg` 도 돌렸다 — 42,330 distinct states, depth 26, 역시
완전 탐색으로 통과 (run 02). 상수를 키워도 결론이 바뀌지 않음을 확인한
것이다.

`AccBank_large` 는 **safety only** 다. 강한 공정성(SF) 5종 × stream 4개
에 대한 temporal 검사가 이 규모에서 현실적 시간 안에 끝나지 않아
`PROPERTY` 를 뺐다. **liveness 는 작은 config 에서만 검증됐다** — 정직
하게 그렇게 기록한다.

### Liveness 는 조건부다 — ASSUMED 공정성 의무 (전건 주의)

**본 모델의 liveness 결과 (`Liveness`, `NoOwnershipLeak`) 는 무조건
성질이 아니다.** `Fairness` 는 모든 진행 액션에 **강한 공정성(SF)** 을
건다 — 이것은 "**공정한 claim/issue arbiter**" 의 모델링이며, **spec
§23.1 에도 v1.9 RTL 에도 그런 arbiter 는 존재하지 않는다**. 즉 SF 는
증명된 전제가 아니라 **v2.0 RTL 이 앞으로 이행해야 할 ASSUMED 의무**다
(예: pending claim 들 간 round-robin grant). RTL 이 이 의무를 이행하지
않으면 liveness 결과는 하드웨어로 이전되지 않는다. **모든 safety 결과는
이 가정과 무관하다.** 같은 경고가 `AccBank.tla` 의 `Fairness` 와
`Liveness` 정의 옆에 박혀 있다 — 인용할 때는 반드시 "공정한 arbiter 가
주어지면 liveness" 로 인용할 것.

왜 WF 가 아니라 SF 인가 (TLC 가 잡아준 것): 처음에는 약한 공정성(WF)을
걸었는데 TLC 가 **실제 반례**를 내놓았다 — stream 이 `issued < K` 상태
에서 spill 과 fill 을 무한히 반복하면 `Accumulate` 가 **연속적으로**
enable 되지 않으므로 WF 가 아무것도 강제하지 못하고, 그 stream 은
영원히 drain 하지 않는다. SF (무한히 자주 enable 되면 발화) 가 이것을
닫는다. `Spill` 과 fault 액션들에는 공정성을 **의도적으로 걸지 않았다**
— spill 은 선택적 소프트웨어 정책이고, "거절"이 진행을 위해 반드시
일어나야 하는 사건이면 계약이 잘못된 것이기 때문이다.

---

## 8. spec 이 정하지 않아 **내가 정한** 것 — 전건 리뷰 요망

spec §23.1 의 ACC bank 규범 텍스트는 앞서 인용한 **한 줄이 전부**이고,
repo 전체에서 그 줄을 부연하는 곳은 없다 (`grep -r requester` → spec:2012
1건). 아래는 모델링을 위해 **부득이 결정한** 사항이다. 전부
**v2.0 spec COMMIT 0 에서 규범화 여부를 판정**해야 한다. 어느 하나도
기존 spec 문장의 재진술이 아니다.

| # | 미정 지점 | 채택한 해석 | 근거 / 위험 |
|---|---|---|---|
| **(a)** | 누산의 **정체성**이 무엇인가 (full 80-bit tag? `(wave_number, thread_id)`? `(thread_id, output_port_id)`?) | **명시적 owner 토큰** — launch 시점에 재구성된 tag 전체. 모델의 `Streams` 원소가 곧 그것. `pcid` 슬라이스는 **정체성이 아니라 bank 인덱스**로만 쓴다 | wave-advance 경로가 `wave_number` 를 +1 하므로 (`EHDecode.v:564`) 순진한 full-tag 키는 누산 도중 정체성이 바뀐다. launch 시점 tag 재구성 선례가 이미 있다 (fp step sequencer 의 `fp_tag_held`, spec:2160) — 그 패턴을 그대로 쓴 것 |
| **(b)** | "명시적 ownership/drain 계약"의 **규범 본문** (acquire op? release op? fault 의미? **하드웨어 강제인가 SDK 규율인가?**) | **하드웨어 강제.** acquire = `0x7E` (획득과 zero 가 **한 원자 사건**), release = drain 과 동시, 거절·stray op·raw 0x7E 는 **loud + sticky** | §26.8 item 10 이 마지막 SDK spacing 규칙을 하드웨어 제거로 **폐기**한 선례, §23.6a contract 1 의 "SDK-only 계약은 하드웨어가 감지 못 함"(spec:2113). **이제 측정 근거가 있다**: 하드웨어 검사 7종 각각에 대해 "지우면 어떤 불변식이 깨지는가"가 §5.1 에 실측으로 있다 |
| **(c)** | **bank 선택자 arity**: `pcid[1:0]` 은 4값, bank 는 2개. 의도가 bank 4개인가, `bank = pcid[0]` 인가, 2:1 매핑 + 충돌 fault 인가 | **2:1 매핑 + loud 충돌 처리**를 모델링했다 (`BankOf(p) = p % NBanks`) — 그리고 그것이 **안전함을 증명**했다 | 셋 중 무엇이든 계약이 있으면 안전하다는 것이 본 모델의 결론이므로, arity 는 성능/점유 문제로 강등된다. 다만 **spec 은 셋 중 하나를 반드시 명시해야 한다** — 현재 문장은 그 자체로 산술이 맞지 않는다 |
| **(d)** | **어느 `pcid`** 인가 (도착한 `ext_tag` 의 것인가, 재구성된 forwarded tag 의 `{8'h00, output_port_id}` 인가), 그리고 **어느 사이클**에 sampling 하는가 | 재구성된 launch-time tag, **commit(T+1) 시점** sampling | v1.9 residual risk 11: T 시점 무조건 할당이 busy-reject 된 dispatch 에 phantom row 를 남겼다 (spec:2885). 모델의 `RequestOwn` 은 bank 상태를 **일절 건드리지 않는다**; `Inv_NoPhantom` 이 그것을 고정한다 |
| **(e)** | **bank 거주지 vs 라우팅** — 한 누산의 contribution 이 서로 다른 cluster 로 라우팅되면? | **미해결. 모델링하지 않음** (단일 cluster) | bank 키가 라우팅 키의 부분 슬라이스라는 사실(`Pod.v:132` / `Cluster.v:500`)은 이것이 실재 위험임을 시사한다. **v2.0 spec 이 반드시 답해야 할 열린 질문** |
| **(f)** | **초기 상태** — reset 시 bank 는 0 인가 정의되지 않는가, 한 번도 zero 되지 않은 bank 를 읽으면 fault 인가 | 명시적 acquire(= zero) 없이는 bank 를 **읽을 수조차 없다**. 모델에서 `Drain` 의 accept 경로는 owner 일치를 요구하고, 그 상태는 `CommitOwn`/`Fill` 을 통해서만 도달한다. SRAM 의미론(release 후 stale 잔존)이라 이 규칙이 더욱 실질적이다 — stale 은 acquire-zero 가 scrub 하기 전까지 죽은 데이터다 | 계약이 있으면 "초기값" 질문 자체가 소멸한다는 것이 이 해석의 이점. reset 값 규범은 여전히 spec 이 적어야 한다 |
| **(g)** | **oversubscription** — cluster 당 bank 가 2개뿐인데 세 번째 live 누산이 오면? | **거절 + loud sticky bit**, 그리고 소프트웨어가 `0x7D` spill 로 관리. 둘 다 모델링됨 (`RejectOwn`, `Spill`/`Fill`) | v1.9 §26.5 의 `bank_tag_collision_error_r` 선례 (`Cluster.v:1036`) — "합성 가능한 sticky status bit, sim-only `$error` 여서는 안 된다"(spec:2809). `Liveness` 가 "전부 거절"이라는 자명한 해를 배제한다 (단, §7 의 조건부 경고) |
| **(h)** | **K (완결) 이 아키텍처적으로 보이지 않는다** — tag 에도 0x70-block 인코딩에도 "K 중 i번째" / last 마커가 없다 | **ghost 변수로 모델링했다.** `Drain` 의 `issued[s] = K` 가드는 **오늘의 하드웨어로는 검사 불가능**하다 | **가장 큰 미해결 격차.** `dec_*` bus 에 fragment 수가 없어 PE 가 감지 못 하는 §23.6a contract 1 과 **동일한 노출면**(spec:2113). 따라서 `Inv_Complete` 는 증명된 성질이 아니라 **가정 모양**이다 — 정직하게 그렇게 읽어야 한다. v2.0 은 (i) K 캐리어를 신설하든지 (ii) short drain 을 SDK 계약으로 남기고 그렇다고 **명시**하든지 택해야 한다 |
| **(i)** | **drain opcode 가 지정되지 않았다** — 후보 3개(`0x72 ACC_REDUCE`, `0x7C STORE_QUANT`, `0x7D SPILL`) 중 무엇도 designate 되지 않음 | 추상 액션 `Drain` 하나로 뭉갰다 | 어느 opcode 든 계약 모양은 같으므로 증명은 유효하다. 다만 spec 이 하나를 골라야 한다 |
| **(j)** | `0x7D`/`0x7E` 의 **sub-op 인코딩 캐리어 부재** | 스코프 밖 (§9.6) | 기존 선례는 `imm16[7:4]` + monotonic loosening (0x72/0x74/0x77/0x79). **주의**: "absent = 기본값" 관례가 여기서는 위험하다 — `absent = SPILL` 과 `absent = FILL` 은 **방향이 반대인 데이터 이동**이다 (0x72 의 `absent = SUM` 과 성격이 다르다) |
| **(k)** | **SR / ownership 결합** — ACC bank 를 `rnd=1` STORE_QUANT 로 drain 하면 counter-RNG 키가 **owner** 의 `(wave_number, thread_id)` 인가 **drain 하는 dispatch** 의 것인가 | 모델링하지 않음(산술). **다만 (a) 의 결정이 이것을 답할 수 있게 만든다** | spec 은 말이 없다. drainer 의 키를 쓰면 "누가 drain 했느냐"에 따라 같은 프로그램이 다른 비트를 내므로 §23.4 item 5 bit-reproducibility 가 **조용히** 깨진다. owner 토큰을 파생 슬라이스가 아니라 **명시적 아키텍처 객체**로 두어야 할 독립적인 이유 |
| **(l)** | **spill image 의 owner 태그 캐리어 부재** — `fill_owner` 가드는 "image 에 owner 토큰이 기록되어 있고 FILL 시 하드웨어가 대조한다"를 전제하는데, 오늘의 0x7D 행에는 그런 image 포맷 규범이 없다 | **ghost 로 모델링했다** (`mem[m].own`). `issued[s] = K` 와 같은 지위다 — 계약이 이 검사를 **필요로 함**은 증명됐지만 (run 07: 지우면 leak 관통), 검사할 캐리어는 아직 없다 | v2.0 은 spill image 포맷에 owner 토큰 필드를 규범화하든지, `fill_owner` 를 SDK 계약으로 강등하고 그렇다고 **명시**해야 한다. 후자라면 §23.6a contract 1 급의 노출면이 하나 더 생기는 것이다 |

> **(b), (c), (h), (l) 이 리뷰 우선순위다.** (b) 는 계약의 존재 자체,
> (c) 는 spec 문장의 산술 모순, (h)/(l) 은 증명이 ghost 에 기대는 두
> 지점이다.

---

## 9. 스코프 밖 — 모델링하지 **않은** 것

정직하게 경계를 긋는다. 아래는 본 모델이 **증명하지 않는다**.

1. **IEEE-754 / fp32 산술.** 값은 불투명 토큰이다. TLC 에 float 이론이
   없고, real 산술은 상태공간을 폭발시키며, 비결합성은 애초에 동시성
   정리가 아니라 수치 정리다. 수치 쪽은 이미 있는 채널이 담당한다 —
   `scripts/golden_fp32.py` (bit-exact golden) + `scripts/fp_release_sweep.py`
   의 independent-oracle 규칙 (spec §23.10.10(f) pin 13 — `ml_dtypes` 대조).
   **두 반쪽이 합쳐져야** §23.4 item 5 (bit-reproducibility) 가 닫힌다:
   TLA+ 가 "연산 **순서**가 프로그램이 정한 불변식"임을, golden 이 "그
   고정된 순서가 요구되는 비트를 낳음"을 증명한다. 어느 한쪽만으로는
   성립하지 않는다 — 이 합성 논증 자체를 v2.0 kickoff 메모에 명시할 것.
2. **canonical accumulation order 의 tree 모양.** 본 모델은 누산 항을
   **시퀀스**(= 좌측 fold)로 본다. 따라서 "owner 의 contribution 이
   ascending K 로 빠짐없이"(`Inv_Canonical`)는 증명하지만, spec §23.1 의
   **32-lane balanced 5-level tree** 와 임의 `FP_LANES` fold 의
   serial-equivalence 는 증명하지 않는다. 그것은 별도 모델
   (`CanonOrder.tla`, 해석되지 않은 ⊕ 위의 **항 트리**를 상태로 갖는)
   의 일이며 v2.0 의 남은 formal 작업이다. Phase-1 조사가 지적했듯이
   이 refinement 야말로 model checker 가 잘하는 문제다.
3. **lane 차원.** bank 는 32 lane 이지만 모델은 lane 을 갖지 않는다.
   근거: aliasing 속성은 lane-wise 이고 32 lane 은 구조적으로 동일·독립
   하므로 한 lane 에 대한 증명이 대칭성으로 전부를 덮는다. **이 대칭
   논증이 깨지는 경우**(lane 간 공유 자원, lane-dependent 주소 계산,
   `FP_LANES` fold 가 lane 을 교차 매핑)에는 무효다 — 2번 항목의
   `CanonOrder.tla` 가 정확히 그 지점을 다뤄야 한다.
4. **멀티 cluster / 라우팅.** bank 는 per-cluster 인데 `pcid[7:4]` 가
   cluster index, `pcid[3:0]` 가 PE index다 (`Pod.v:132`,
   `Cluster.v:500`) — bank 키가 **라우팅 키의 부분 슬라이스**다. 한
   누산의 contribution 들이 서로 다른 cluster 로 라우팅되면 어떻게
   되는지는 spec 에 아무 말이 없고 (§8 (e)), 본 모델도 단일 cluster 만
   본다.
5. **사이클 정확도.** `RequestOwn` → `CommitOwn`/`RejectOwn` 2단계가
   v1.9 의 T / T+1 deferred-commit 을 반영하고, attempt surface 가
   "spill 후 in-flight op" 라는 파이프라인 현상을 추상적으로 담지만,
   그 외에는 사이클 정확 모델이 아니다. 파이프라인 깊이,
   `output_regs_free` 상호배제, frag FSM 은 없다.
6. **0x7D / 0x7E 의 sub-op 인코딩.** SPILL 과 FILL, ZERO 와 STATUS 를
   구별할 **인코딩 캐리어가 아직 없다** (양쪽 행 모두 imm16/32/64 ·
   opref · subscript 를 전부 forbid, `isa/wt64v1_isa.json:2216-2242`,
   `:2252-2282`). 모델은 액션을 추상적으로 다루며 인코딩은 v2.0
   kickoff 메모의 계약 초안 몫이다.
7. **stochastic rounding.** SR 은 산술이므로 여기 없다. 다만 §8 (k) 의
   지적은 본 모델의 설계 결정과 직결된다.
8. **spill slot 수의 규범.** 모델은 `NSlots = 2` 로 돌린다 — leak
   hazard 가 도달 가능해지는 **최소값**이라서다 (§5.2; 1개는 공허해서
   ASSUME 가 거부한다). 실제 spill 대상이 메모리인 이상 slot 수는
   사실상 무한이며, "몇 개면 충분한가"는 증명 대상이 아니라 소프트웨어
   정책이다.
9. **fault 의 입도.** `conflict` 는 단일 sticky bit 다 (v1.9
   `bank_tag_collision_error_r` 선례). RTL 이 원인별 status bit 를 나눌
   지는 (acquire 거절 / stray acc / stray drain / foreign fill / busy
   fill / raw zero — 모델의 fault 액션 6종이 곧 그 후보 목록이다) v2.0
   spec 의 몫이다.

---

## 10. 파일

| 파일 | 역할 |
|---|---|
| `AccBank.tla` | 모델. `DisabledGuards` 상수로 가드를 개별 삭제할 수 있다 (`{}` = GOOD) |
| `AccBank.cfg` | GOOD — 불변식 9 + temporal 2. **통과해야 함** |
| `AccBank_large.cfg` | GOOD, 4 stream / K=3, safety only. **통과해야 함** |
| `AccBank_del_commit_free.cfg` | 가드 삭제 실험 ×7 — §5.1 표의 실측. **각자 실패해야 함** |
| `AccBank_del_commit_zero.cfg` | 〃 |
| `AccBank_del_acc_owner.cfg` | 〃 |
| `AccBank_del_drain_owner.cfg` | 〃 |
| `AccBank_del_fill_owner.cfg` | 〃 |
| `AccBank_del_fill_bankfree.cfg` | 〃 |
| `AccBank_del_zero_owner.cfg` | 〃 (zero race, §6) |
| `AccBank_requesterid.cfg` | 전 가드 삭제 = 반증된 "requester ID" 설계. **실패해야 함** (귀속 불가, 서사용 — §5.3) |
| `AccBank_witness_reject.cfg` | hazard 도달성 witness ×6 — §5.4 표. **각자 실패해야 함** |
| `AccBank_witness_stray_acc.cfg` | 〃 |
| `AccBank_witness_stray_drain.cfg` | 〃 |
| `AccBank_witness_fill_foreign.cfg` | 〃 |
| `AccBank_witness_fill_busy.cfg` | 〃 |
| `AccBank_witness_zero_window.cfg` | 〃 (zero-race 창, §6) |
| `run.sh` | 16개 run 전부 + 선언 대비 검증, `-workers 1` 고정, merge gate 용 non-zero exit |

라이선스: `.tla`/`.cfg`/`.sh` 는 소프트웨어 클래스
(`LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0`), 본 README 는 문서
클래스(`CC-BY-4.0`). `LICENSE.md` §2 / §3 참조.
