<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# 개발환경·ABI·Rust 기준 축 — 사용자 방침(2026-08-30)의 이 저장소 착지

*세운 날: 2026-08-30. 이 문서는 **결정하지 않는다.** 방침이 답하지 않은 것은
아래 §6 에 미결로 세우고 사람에게 남긴다. 여기 있는 것은 방침 원문과, 이
저장소 실물의 실측과, 둘이 만나는 자리의 충돌표다.*

관련 실물:
- `asm/wavetensor_asm.py` · `asm/test_wavetensor_asm.py` — 방침의 「포팅 예정」이
  가리키는 실물. 이 저장소에서 **역할 일곱**을 진다 (§4)
- `scripts/lint_guide_derived_tables.py` — 정본 일관성 게이트. 진실 원천이
  위 파일의 **Python 문법**에 결합돼 있다 (§4.3)
- `scripts/lint_section_refs.py` — 인용 좌표 래칫. `asm/` 이 **hard 구역**이다 (§4.4)
- `scripts/lint_toolchain_pins.py` — 핀 대조 축. **Rust 계통이 없다** (§3)
- `.claude-memos/toolchain_pin_axis.md` — 같은 「하한 vs 핀」 물음의 선례 (§3.1)
- `.claude-memos/sdk_encoding_delta_notice.md` — 비트 델타의 **통지 authority**.
  이 문서는 그것을 **가리키기만 한다** (§4.5)
- 정본 `docs/wt64v1-architecture-guide/chapters/00-preface.typ` §0.3.1 「오염 없는
  오라클」 · `chapters/01-isa-asm.typ` §1.9 「어셈블러 — 오라클로서의 지위」

---

## 0. 방침 원문 — 축자 (현재까지 명시된 것)

**아래는 2026-08-30 사용자 방침의 축자 사본이다. 해석은 §1 이후에만 있고,
해석이 이 절을 대체하지 않는다.** 목록은 원문에서 `...` 로 **열려 있고**,
이 문서는 그것을 닫지 않는다.

> * 드라이버 및 SDK 개발을 위한 권장 개발환경들
>     - Linux
>         -- Alpine Linux with kernel version 7.x + musl libc + LLVM: for musl ABI build
>         -- LineageOS 23.2 (based on AOSP 16): for Android(Bionic ABI) build
>         -- openSUSE Slowroll with kernel version 7.x + LLVM: for glibc ABI build
>     - NetBSD version 11.0
>     - DragonFlyBSD version 6.4.2
>     ...
> * 현재 Python(3.x)으로 작성되어있는 어셈블러는 pure Rust로 port할 예정. 단, 착수 시기는 아직 미정.
> * 모든 Rust 코드들은 2024 Edition, stable toolchain version >= 1.97을 기준으로 함.
> * Y4(로컬 저장소 위치: `~/Y4/`)용 드라이버 및 SDK 개발을 위해서는 구체적인 Y4 ABI부터 먼저 확정해야 함!!

**문면이 말한 것 다섯** — 해석을 얹지 않고 옮긴다:

1. `...` 는 목록이 **열려 있다**는 선언이다. 위 다섯은 「전부」가 아니라
   「현재까지 명시된 것」이다. 항목 추가는 정규 이벤트다.
2. 「**권장** 개발환경」이다. 「지원 대상」이라 적히지 않았다.
3. asm 포팅은 「**예정**」이고 「착수 시기는 아직 **미정**」이다. 시기가
   미정이라는 것 자체가 방침의 일부다 — 「진행 중」이나 「다음 단계」로
   승격하지 마라.
4. `>= 1.97` 은 **하한**이지 핀이 아니다. 「1.97 로 고정」이라 적히지 않았다.
5. `!!` 는 강조다. Y4 ABI 확정은 **선행 조건**이고, 그 전에 Y4 용 드라이버/SDK
   를 짓는 것은 방침 위반이다. 이 문서는 그것을 **블로커**로 적는다 (§5).

### 0.1 방침 이후 내려진 판정 — **닫힌 것과 유보된 것** (같은 날)

⚠️ **아래는 미결이 아니다.** 사용자가 이미 판정했으므로 §6 미결표에 넣으면
내려진 결정을 지우는 것이 된다. 축자로 보존한다.

| | 판정 | 축자 | 이 문서에서의 자리 |
|---|---|---|---|
| **유보** (작업 큐 #37) | Y4 Rust 하한 정합 — **지금 맞추지 않는다** | 「일단 verus-fork 쪽 개발 작업들(custom backends, 최신 Verus upstream으로부터 rebase 등...) 부터 먼저 해놓고 나서 추후 결정.」 | §5.2. 「미정」이 아니라 **선행 조건이 명명된 유보**다 |
| **결정 A** (#38) | Bionic 축의 **소비자는 드라이버와 NDK**다 | 「Bionic은 드라이버 및 NDK에서 필요로 하잖나?」 | §1 — Q2 를 좁힌다 (아래) |
| **결정 B** (#38) | Python 어셈블러를 **동결하지 않는다** | 「Python 어셈블러는 내가 명시적으로 지시하기 전까지는 동결하지 말도록.」 | §4.7. 옛 Q10 을 **닫는다** |

**결정 A 의 사정거리 — 넓게 읽지 마라.** 이것이 정한 것은 *Bionic 축을 누가
소비하는가*(드라이버 유저스페이스 + NDK 의 C/C++ 표면)이지, 다섯 권장 환경
전체가 지원 타깃인가가 아니다. Q2 는 **좁아졌을 뿐 닫히지 않았다** —
NetBSD/DragonFly 의 축과, 방침 목록에 없는 macOS/Windows 의 처분은 그대로 열려
있다. (부수: 이 결정은 JVM 이 Bionic 축의 소비자가 **아니라는** 것도 함의한다 —
빈 칸이 아니라 **애초에 그 축의 칸이 아니다.** 그 실물 수정은 형제 저장소 몫이다.)

## 1. 「권장 개발환경」과 「지원 타깃」은 문면상 다른 축이다

방침은 「권장 개발환경들」이라 적었다. 그것은 *어디서 개발하는가*이고,
*무엇 위에서 도는가*(지원 타깃)와 같은 축이라고 문면이 말하지 않는다.

다만 문면이 **관측 가능한 사실** 하나를 준다: `musl` · `Bionic` · `glibc` 를
**ABI 이름으로 명시해 셋으로 갈랐고**, 각 줄이 「for … ABI build」로 끝난다.
「build」라 적힌 이상 빌드 타깃 축이 셋으로 갈렸다고 읽는 쪽이 자연스럽다.

**그 읽기가 맞는지는 이 문서가 정하지 않는다** — 미결 Q2 로 세운다. 두 축을
섞어 적으면 나중에 어느 쪽이 방침이었는지 되돌릴 수 없기 때문이다.

부수로 문면이 답하지 않는 비대칭 둘:

- NetBSD 11.0 · DragonFlyBSD 6.4.2 는 위 **ABI 3분할 밖**이다 (그 둘의 libc 는
  musl 도 Bionic 도 glibc 도 아니다). 별도 타깃인지 개발 호스트일 뿐인지 미결.
- Y4 자신은 권장 목록에 **없다**. 그런데 마지막 줄이 「Y4용 드라이버 및 SDK」를
  전제한다. Y4 가 타깃인지, 장차 개발환경인지, 아직 어느 쪽도 아닌지 미결 (§5).

## 2. ABI 3분할 — 이 저장소 반영 실측

전수 grep (`.git` 제외, 2026-08-30):

| 방침의 낱말 | 이 저장소 히트 | 뜻이 같은가 |
|---|---|---|
| `musl` | **0 파일** | — |
| `Bionic` / `bionic` | **0 파일** | — |
| `glibc` | **0 파일** | — |
| `openSUSE` | **0 파일** | — |
| `LineageOS` · `AOSP` | **0 파일** | — |
| `Alpine` | 1 파일 — `.claude-memos/remote_accelerator_access.md:107` | **아니다** |
| `NetBSD` | 1 파일 — `.claude-memos/host_a_custom_hypervisor.md` | **아니다** |
| `DragonFly` | 2 파일 — `host_a_custom_hypervisor.md` · `.claude-memories/y4_separate_repo.md:9` | **아니다** |

「뜻이 같은가」 열이 요지다 — **히트 셋은 전부 다른 뜻이다**:

- `Alpine` — 「A가 "단순 가속기 호스트" 면 가벼운 OS (Alpine, NixOS minimal) 로
  daemon 만 가동」. **원격 가속기 호스트의 OS 후보**이지 개발환경이 아니다.
- `NetBSD` · `DragonFly` — `.claude-memos/host_a_custom_hypervisor.md:295` 의 「**3-tier driver
  전략** — DragonFlyBSD (BSD) 1순위 → NetBSD via rump kernel 2순위 → Linux port
  (해당 driver 한정 GPLv2) 최후수단」. **Y4 가 드라이버 소스를 어디서 가져오는가**
  라는 계보 논의다. 같은 OS 이름이 방침에서는 *개발환경*, 여기서는 *소스 공여자*다.
- `.claude-memories/y4_separate_repo.md:9` 의 DragonFlyBSD 도 같은 결 — Y4 의 reuse manifest
  (`seL4/Tock/DragonFlyBSD/Redox`).

⇒ **판정: 방침의 OS/ABI 축은 이 저장소에 선례가 없는 신설 축이다.** 이름이
겹치는 셋은 전부 다른 축이므로, 그것을 근거로 「이미 반영돼 있다」고 읽으면
오독이다.

⚠️ 이것이 「충돌」인지 「미반영」인지는 **Q2·Q3 이 닫혀야 정해진다.** 권장
개발환경이 저장소 인프라(devcontainer)를 대체하는 축인지 별개 축인지가
미정이므로 어긋남으로 단정하지 않는다. 실물만 적는다:

- `.devcontainer/Dockerfile` 은 **Arch 단일**(`ALA_SNAPSHOT=2026/08/12`, 295 패키지)
  이고, Arch 는 **방침 목록에 없는 배포판**이다.
- `.github/workflows/gates.yml` 은 그 이미지 하나로 전 게이트를 돈다. 다섯 권장
  환경 중 CI 에 결선된 것은 **0개**다.

## 3. Rust 기준의 실효 — 이 저장소에 Rust 가 0 이다

실측 (2026-08-30, `.git` 제외):

| 재는 것 | 값 |
|---|---|
| `*.rs` | **0** |
| `Cargo.toml` | **0** |
| `rust-toolchain*` | **0** |
| `.devcontainer/` · `.github/` 의 `rust`\|`cargo` grep | **0건** |

그리고 `scripts/lint_toolchain_pins.py` 가 대조하는 핀 계통 — `PINS` 셋
(`SBT_VERSION` · `SCALA_VERSION` · `SPINAL_VERSION`) + `PINS_TWOWAY` 열넷
(TLA+ 넷 · btormc 계열 넷 · `ALA_SNAPSHOT` · `COCOTB_VERSION` · `COCOTB_PYTHON` ·
`SBY_COMMIT` · `WITH_SBY` · `WITH_BTORMC`) — 에 **Rust 축이 없다.**

⇒ **오늘 이 저장소에서 `2024 Edition` · `stable >= 1.97` 이 집행할 대상은 0 이다.**

**그러므로 지금 `lint_toolchain_pins.py` 에 Rust 축을 세우지 않는다.** 핀할
실물이 0 인 선언은 이 저장소가 이미 한 번 겪은 실패의 정확한 형태다 —
「안 돌면서 OK 를 인쇄」. 그 교훈은 `lint_section_refs.py` 세 번째 파도가
`asm` 뿌리에서 겪은 것(「정의역에는 들어왔는데 집행 실효가 0 이었다」)과 같다.

실효는 **셋뿐이고 전부 전방 구속**이다:

- **(i) 포팅 착수 조건.** asm 이 Rust 로 가면 그 코드는 SDK 저장소에 앉으므로
  기준은 거기서 집행된다. *이* 저장소가 정해야 할 것은 Rust 기준이 아니라
  **남는 Python 파일과 그 기계 소비자들의 처분**이다 (§4).
- **(ii) 통지 authority 로서의 하중.** `sdk_encoding_delta_notice.md` 가 스스로
  「사실이 어긋나면 이 문서가 이긴다」로 서 있다. Rust 기준이 그 통지에 들어가면
  이 저장소가 형제 저장소의 툴체인 기준을 발신하는 자리가 된다.
- **(iii) Y4 축** — §5.

### 3.1 하한인가 핀인가 — 이 저장소 규율과 정면으로 만난다

정본 `docs/wt64v1-architecture-guide/chapters/06-formal.typ:589-594` 축자:

> - *내용 고정(해시·커밋)은 필요조건이다.* 없으면 「무엇으로 쟀는가」에 답할 수
>   없고, 바꿔치기가 조용히 지나간다.
> - *재현의 충분조건은 그 내용을 이쪽이 보관하는 것이다.* 상류가 계속 준다는
>   보장은 어느 핀도 사지 못한다.

**하한만으로는 실행 시점 버전이 기록되지 않는다.** `>= 1.97` 은 「1.97 이상
아무거나」를 허용하므로 「무엇으로 쟀는가」에 답하지 못한다 — 정본이 *필요조건*
이라 부른 것을 만족하지 않는다.

그리고 이 축에는 **집행하는 기계가 없다**. `rust-toolchain.toml` 은 하한을
표현할 수 없고(채널은 롤링이거나 정확한 핀, 둘 중 하나다), 하한 의미를 갖는
것은 Cargo 의 `rust-version` 뿐인데 그것은 툴체인 선택을 하지 않는다.

`toolchain_pin_axis.md` §2 가 `ALA_SNAPSHOT` 에 대해 「**날짜는 좌표이지 내용이
아니다**」라 적은 것보다 **한 단계 더 약한 자리**다 — 하한에는 좌표조차 없다.

**실물 예시가 이미 있다** (Y4, 아래 §5.2): `channel = "stable"` 이라 적힌 핀이
이 호스트에서 **1.96.0** 으로 풀린다. 하한 `1.97` 아래인데 아무것도 울지 않는다.

⇒ 선택지 셋과 대가 (**이 문서는 고르지 않는다** — Q1):

| | 형태 | 대가 |
|---|---|---|
| ⒜ | `channel = "stable"` 유지 + 하한은 `rust-version` 으로만 | 「최신 stable 추종」을 산다. 재현성은 **별도 lock 으로 캡처하지 않으면 성립하지 않는다** — 그 lock 장치가 rustc 에는 없다 |
| ⒝ | `channel = "1.97.1"` 로 핀 | 필요조건을 만족한다. 대신 문면(`>=`)과 실물(정확 핀)이 어긋나고, 재핀이 반복 이벤트가 된다 |
| ⒞ | 둘 다 (핀 + `rust-version` 하한) | 두 값이 서로 다른 것을 뜻하게 된다 — `rust-version` 은 *크레이트 소비자용 MSRV*, `rust-toolchain` 은 *개발 툴체인*. 그 이원화가 의도인지가 별개 결정이다 |

## 4. asm 포팅 — 오라클 지위의 승계 문제

### 4.1 실측 — 브리프보다 크다

| | 값 (2026-08-30 실측) |
|---|---|
| `asm/wavetensor_asm.py` | **2,574행 / 117,443 B** |
| `asm/test_wavetensor_asm.py` | **3,322행 / 169,517 B** |
| `INSTR_WORDS_REAL` | `= 14` (`asm/wavetensor_asm.py:88`) |
| `INSTR_WIDTH_BITS` | `= INSTR_WORDS_REAL * 32` (같은 파일 :89, = 448) |
| CI 게이트 실행 | `python3 -m unittest -q asm.test_wavetensor_asm` → **Ran 177 tests … OK** (0.154s, rc=0) |
| `asm/README.md` | **없다** (디렉토리에 `.py` 3개 + 캐시뿐) |

### 4.2 같은 파일이 **일곱 자리**에서 하중을 진다

포팅이 건드리는 것은 오라클 지위 하나가 아니다.

| # | 역할 | 실물 좌표 | 포팅 시 |
|---|---|---|---|
| 1 | **정본 오라클 (규범)** | `docs/wt64v1-architecture-guide/chapters/00-preface.typ:140` 「오염 없는 오라클」 · 규범 블록 :145 | 언어 중립 (§4.3) |
| 2 | **정본 규범 — 재구현 대상 제외** | `docs/wt64v1-architecture-guide/chapters/01-isa-asm.typ:1610` · 규범 :1612–1616 | 언어 중립 |
| 3 | **에어락 열람 허가표** | `rtl/README.md` ✅ 행 | **경로 결합** |
| 4 | **lint 원천 — 정본 게이트의 진실 원천** | `scripts/lint_guide_derived_tables.py:126, 488, 494, 1016` | **Python 문법 결합 → hard-fail** |
| 5 | **CI 게이트** | `.github/workflows/gates.yml:195` 「어셈블러 단위 테스트」 → `:198` | 경로 결합 |
| 6 | **인용 좌표 래칫 (hard 구역)** | `scripts/lint_section_refs.py:654-655` | **경로 키 래칫 — 하강도 실패** |
| 7 | **재구현 쪽 관측 기록의 출처** | `rtl/spinal/src/main/scala/wt64/decode/OperandDecode.scala:33` 「인코딩 관측 기록 (허용 오라클: asm/wavetensor_asm.py encode_pass)」 · 같은 디렉토리 `DecodeWalk.scala` | 경로 결합 |

부수로 **생성기 사슬의 소비처**이기도 하다 — `scripts/gen_isa_tables.py:63` 이
`"pytables": REPO / "asm" / "generated_isa_tables.py"` 를 내고
`scripts/lint_isa_tables_fresh.py` 가 신선도를 건다.

### 4.3 정본의 허가 근거는 **언어가 아니다**

`docs/wt64v1-architecture-guide/chapters/01-isa-asm.typ:1612-1616` 축자:

> 어셈블러는 유지·개량된다. 따라서 재구현팀은 어셈블러를 *자유롭게 읽고 실행할
> 수 있으며*, 그것이 내는 비트열이 곧 입력 벡터다. 이것은 clean-room 오염이
> 아니다 — 어셈블러는 RTL 이 아니다.

⇒ **Rust 어셈블러도 RTL 이 아니므로 문면상 오라클 지위는 언어를 타지 않는다.**
그러나 그 문면이 답하지 않는 것이 다섯이고, 다섯 다 실물이 이미 걸려 있다.

**(a) 오라클의 거처가 저장소 밖으로 나간다.** 위 표의 3·4·5·6·7 은 전부
**저장소 상대 경로**다. 포팅 목적지는 SDK `/home/ybi/wavetensor-sdk/docs/architecture.md:131`
`crates/wavetensor-asm/` 이다. 에어락은 *이* 저장소 트리 위에 그어져 있고,
형제 저장소를 가리킬 문법이 `rtl/README.md` 열람표에 없다.

**(b) 병존 기간에 오라클이 둘이 된다.** SDK `/home/ybi/wavetensor-sdk/docs/architecture.md:167` 축자 —
Phase C = 「이행 중 (두 어셈블러 모두 살아있음)」. 정본 §0.3.1 규범표는 오라클을
**단수**로 적는다. 둘이 비트에서 갈리면 어느 쪽이 오라클인지 정본에 문면이 없다.
(정본 §1.7.3 「단일 진실 원천」은 *opcode 표*에 걸리지 *인코더 자체*에 걸리지 않는다.)

**(c) 「3계통째 독립 구현」 요구가 정본이 아니라 메모에 산다.**
`sdk_encoding_delta_notice.md` 가 「Rust 포트는 3계통째 독립 구현이어야 같은
버그를 세 벌 복사하는 경로가 막힌다」·「Rust 포트가 인코딩 규범을 truth table
에서 역추출하면 안 된다」를 적는다. 그런데 **포팅은 정의상 Python 을 읽고 하는
일**이라 「독립」의 뜻이 오라클 축과 CRC 축에서 서로 다르다. 이 규율은 §0.3.1
「에어락은 양방향이다」와 같은 결인데 **정본에 없다.**

**(d) 부록 E 는 어셈블러를 pass/fail 오라클보다 강한 것으로 쓴다.**
`docs/wt64v1-architecture-guide/appendix/e-defined.typ:899` 축자: 「미룬 자리로 어셈블러(허용 오라클)를 고른 것
자체는 이 저장소의 관행 그대로이고, 다른 인코딩 공백들이 실제로 그렇게 닫혔다」.
즉 어셈블러는 **정본이 정하지 않은 것을 정하는 관측원**이다. 그 권위가 둘로
갈리면 `sdk_encoding_delta_notice.md` 머리의 현행 순위 「정본 > 어셈블러 실물 >
이 문서」가 성립하지 않는다 — 그리고 **갈리는 자리가 하필 정본이 침묵하는
자리일 수 있다.**

**(e) Phase E 는 정본의 오라클 하나를 지운다.** SDK `/home/ybi/wavetensor-sdk/docs/phase_plan.md:115` —
「Python 어셈블러 deprecation … 최소 6개월 grace period」. 정본 §0.3.1 은 오라클을
**넷**으로 세고, 그중 하나가 사라지는 사태를 예상하지 않는다.

### 4.4 가장 급한 것은 (a)~(e) 가 아니라 **4번**이다

`scripts/lint_guide_derived_tables.py` 는 **정본 §1.3.1 · §4.5 · 부록 B 의 상호
일관성 게이트**이고, 그 진실 원천이 Python 소스 안의 두 줄이다. 파서가 Python
문법에 박혀 있다 (축자):

```
 95: ASM = ROOT / "asm" / "wavetensor_asm.py"
453:    m = re.search(r"^INSTR_WORDS_REAL\s*=\s*(\d+)\s*$", asm_text, re.M)
459:    if re.search(r"^INSTR_WIDTH_BITS\s*=\s*INSTR_WORDS_REAL\s*\*\s*32\b", …)
801:        fail(f"어셈블러가 없다: {ASM} — 명령어 길이의 원천이다")
```

Rust 포트는 `pub const INSTR_WORDS_REAL: usize = 14;` 로 쓴다 — **두 정규식 모두
불일치**하고, 파일이 떠나면 `fail()` → `sys.exit(1)`. **경고가 아니라 hard-fail
이다.**

그리고 이 게이트가 세워진 이유가 하필 「같은 값이 정본 세 곳에 있는데 파도가 둘만
고쳤다」(그 파일 머리 §(5), 여섯 번째 드리프트)이므로, **게이트가 죽으면 정확히
그 부류가 되돌아온다.**

⇒ **이 결정은 포팅 착수 *전에* 나야 한다** (Q6). 착수 후면 정본 일관성 게이트가
깨진 채로 일하게 된다.

### 4.5 래칫 — `asm/` 은 hard 구역이다

`scripts/lint_section_refs.py:654-655` 에 경로 키 두 줄이 서 있다:

```
    "asm/test_wavetensor_asm.py": 2,
    "asm/wavetensor_asm.py": 10,
```

`:650` 주석이 「`asm/` 12건 — `sender_zone()` 이 hard 로 올림」이라 적고, 같은
파일이 **하강도 실패시키는** 것을 규율로 못박는다(래칫은 올릴 때 리뷰 대상이다).
⇒ asm 이 저장소를 떠나면 두 줄이 조용히 슬랙이 되는 게 아니라 **검사가 운다.**
래칫 항목을 형제 저장소로 옮길 문법이 없다 (Q7).

### 4.6 부수 실측 — SDK 계획이 없는 파일을 전제한다

SDK `/home/ybi/wavetensor-sdk/docs/phase_plan.md:77` (C6) 은 「WaveTensor 저장소의 `asm/wavetensor_asm.py`
README 에 "SDK 로 이주 중" 명기」를 계획하고, `:115` (E5) 도 「README 에 "SDK 로
이주 완료" 명기」를 적는다. **실측: `asm/README.md` 는 없다** (`asm/` 에 `.py` 3개 + 캐시 디렉토리뿐).
신설할지, 계획 문면을 고칠지는 이 문서가 정하지 않는다 — 사실로만 적는다.

부수: 형제 저장소가 **같은 날 이 충돌을 스스로 등재했다** — `/home/ybi/wavetensor-sdk/docs/phase_plan.md:77`
의 C6 행이 「⚠️ **좌표 결손 (실측 2026-08-30)** … 이 마일스톤은 존재하지 않는
파일을 편집하도록 적혀 있다 … **조용히 고치지 않고 충돌로 남긴다**」를 달고
있다. 즉 이것은 이 문서가 처음 찾은 것이 아니라 **양쪽에 같은 모양으로 서 있는
충돌**이다.

**⚠️ 인코딩 비트 델타는 이 문서에 복제하지 않는다.**
`sdk_encoding_delta_notice.md` 가 스스로 통지 authority 로 서 있으므로 복제하면
authority 가 둘이 된다. 포팅 금지 목록(§5, `wave_fragments_vdot()` ·
`wave_fragments_fdot32_cr()`)을 포함해 **좌표만 가리킨다.**

### 4.7 착수까지 Python 어셈블러는 **동결하지 않는다** (결정 B, 2026-08-30)

사용자 판정 축자: 「Python 어셈블러는 내가 명시적으로 지시하기 전까지는 동결하지
말도록.」

⇒ **계속 개량한다.** 포팅 델타가 커지는 것(인코딩 개정 파도가 이미 한 번 만든
것이고, 그 전량이 `sdk_encoding_delta_notice.md` 다)은 **수용된 대가**다. 동결은
사용자 명시 지시가 있을 때만.

함의 둘:

- **정본 환류가 어셈블러에서 막히지 않는다.** 위 §4.2 표의 역할 1·2·4·7 은
  포팅 전까지 살아 있는 채로 계속 움직인다.
- **SDK Phase C 비트-동등 기준선은 움직이는 표적이다.** 그러므로 델타 통지가
  일회성이 아니라 **반복 이벤트**다 — `sdk_encoding_delta_notice.md` 형태의
  통지를 「한 번 보냈다」로 닫으면 안 된다.

이것이 「착수 시기 미정」(방침 §0)과 만나는 자리를 적어 둔다: 미정 기간이 길수록
델타가 단조 증가하고, **그 증가를 재는 기계는 없다.**

### 4.8 포팅이 **라이선스를 좁힌다** — LGPL 갈래가 Rust 쪽에서 사라진다

**이것은 방침이 실제로 건드리는 결과인데, 최초 착지 당시 네 저장소 원장
어디에도 등재되지 않았다** (전수 `LGPL` grep: 본 문서 0건 ·
`.claude-memories/dev_platform_policy.md` 0건 · drivers `docs/platforms.md` 0건 ·
SDK `docs/architecture.md` 는 §5 의 기존 서술 1건뿐). 「기록되지 않은 미결은
미결이 아니라 분실이다」가 그대로 적용된다 — 뒤늦게 세운다 (2026-08-30 수리).

실측 양쪽:

| 쪽 | 좌표 | 문면 |
|---|---|---|
| 이 저장소 | `LICENSE.md:53` + `:57` | `SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0` 이 「The assembler (`asm/wavetensor_asm.py`) and its tests」에 걸린다 |
| SDK | `/home/ybi/wavetensor-sdk/docs/licensing.md:41-46` | 포팅 시 「**Elect the Apache-2.0 option**」 (SDK `.claude-memories/wavetensor_sdk_asm_migration.md` 「License handling during port」에도 축자로 반복) |

⇒ **삼중 라이선스가 포팅에서 단일로 좁아지고, 없어지는 것은 LGPL 갈래다.**
그것이 부수 효과가 아니라는 근거가 같은 파일에 있다 — `LICENSE.md:64` 는 삼중을
제안한 이유를 「**Linux-kernel-adjacent codebases naturally accept LGPL**」이라
명시한다. LGPL 갈래는 *커널 인접 소비자*를 위해 일부러 둔 것이고, 드라이버
저장소의 Linux 서브모듈이 GPL-2.0+ 인 지금 그 소비자는 가설이 아니다.

**미결 (§6 Q12 로 등재)** — 방침은 「pure Rust 로 port」라고만 적었고 라이선스에
**침묵한다.** 값을 채우지 마라.

**부수 (방침과 무관하게 이미 실물과 어긋남):** `LICENSE.md:61-62` 는 「Future
driver, hypervisor, and host-side daemon code that ships in this repository」에도
같은 삼중을 걸어 둔다. 그러나 **드라이버는 이미 별도 저장소로 나갔고**
(`/home/ybi/wavetensor-drivers`, Linux 서브모듈은 GPL-2.0+) **하이퍼바이저도
마찬가지다** (`/home/ybi/Y4`, Apache-2.0 단독). 이 문장이 가리키는 코드는 이
저장소에 실릴 계획이 없다. **고치지 않고 보고한다** — 문장을 지울지 범위를
좁힐지는 사람이 정할 일이고, 방침이 연 질문도 아니다.

## 5. Y4 — 블로커 하나와 유보 하나. 둘은 다른 것이다

### 5.1 Y4 ABI 확정은 **블로커**다 (`!!`)

방침의 마지막 줄이 `!!` 로 강조한 선행 조건이다. Y4 용 드라이버/SDK 개발은
**구체적 Y4 ABI 확정 전에는 착수할 수 없다.**

실측 — 그 선행 조건은 **오늘 충족되지 않았다**:

| 문서 | 실측 상태 |
|---|---|
| `/home/ybi/Y4/docs/hiu_abi.md` | v0 — draft, **not frozen** (양측 sign-off 전) |
| `/home/ybi/Y4/docs/lease_capability.md` | 스키마 v0 (draft, **not frozen**) |

그리고 **Y4 자신이 이미 같은 판단을 하고 있다** — `/home/ybi/Y4/Cargo.toml:18-19`
축자:

> `# HIU-touching crates (hiu/, hiu/mock/, hiu/lease) defer until docs/hiu_abi.md`
> `# is v1.0 frozen.`

⇒ 방침의 `!!` 는 Y4 가 HIU 축에서 이미 세운 유보를 **재확인**하는 면이 있다.
다만 **블로커의 범위가 미결**이다 (Q8·Q9) — 「구체적 Y4 ABI」가 가리키는 것이
⒜ 게스트↔하이퍼바이저 hypercall ABI 인지 ⒝ lease capability 취득 경로인지
⒞ 그 밖인지를 방침이 말하지 않고, 세 후보의 문서 상태가 서로 다르다.

### 5.2 Rust 하한 정합은 **미결이 아니라 유보다** — 사용자 판정 2026-08-30

⚠️ **이 자리를 미결로 적으면 왜곡이다.** 사용자가 이미 판정했다 (작업 큐 #37).
판정 축자:

> 일단 verus-fork 쪽 개발 작업들(custom backends, 최신 Verus upstream으로부터
> rebase 등...) 부터 먼저 해놓고 나서 추후 결정.

⇒ 아래 충돌 셋은 **지금 맞추지 않는다.** 「미정」이 아니라 **선행 조건이 명명된
유보**이고, 해제 시점은 「verus-fork 작업 후 재판정」이다. (선행 작업 목록도
`...` 로 열려 있다.)

**실측 충돌 셋** (2026-08-30, `/home/ybi/Y4` 직접 측정 — **고치지 않았다**):

| # | 실물 | 방침 대비 |
|---|---|---|
| ① | `/home/ybi/Y4/Cargo.toml:37` `rust-version = "1.94"` · `/home/ybi/Y4/kernel/Cargo.toml:9` 동일 (kernel 은 workspace `exclude` 라 상속 불가 — **편집 지점이 둘**) | 하한 `1.97` 보다 3 마이너 아래. `edition = "2024"` 는 **일치** |
| ② | `/home/ybi/Y4/verus-fork/rust-toolchain.toml` `channel = "1.95.0"` + `components = [… "rustc-dev", "llvm-tools"]` | 하드 핀이나 1.97 미만. rustc 내부 API 결합 fork 라 **상류가 올리기 전엔 못 따라간다** |
| ③ | `/home/ybi/Y4/rust-toolchain.toml` `channel = "stable"` — 이 호스트에서 `rustc 1.96.0 (ac68faa20 2026-05-25)` 로 풀린다. `1.97.1` 툴체인이 rustup 에 **설치돼 있는데도** 선택되지 않는다 | 「stable」은 핀이 아니라 롤링 참조. 하한도 핀이 아니라 **집행하는 기계가 없다** — `rust-version = "1.94"` 는 cargo 가 집행하지만 하한을 낮게 잡아 1.96 을 통과시킨다 |

#37 이 명시로 남긴 것: **집행 기계 부재(충돌 ③)는 유보 해제 시점에 같이
처분한다.** 그리고 **방침의 「모든 Rust 코드」에 벤더링된 증명기 포크가 드는지는
여전히 열려 있다** — #37 이 그것을 「방침의 열린 지점」이라 적었다 (Q4).

## 6. 미결 등재표

**⚠️ 이 표의 항목에 값을 채워 넣지 마라.** 그럴듯한 값을 채우는 것이 이
프로젝트가 반복해 밟은 함정이다. 「기록되지 않은 미결은 미결이 아니라
분실이다」 — 실제로 소멸한 요구가 최소 셋 있었다.

| # | 미결 | 누가 정하는가 | 정해지지 않으면 무엇이 막히는가 |
|---|---|---|---|
| Q1 | **하한인가 핀인가** — `>= 1.97` 을 무엇으로 실재화하나 (§3.1 ⒜⒝⒞) | 저장소 정책 (프로그램 전체) | Rust 축의 provenance 가 필요조건조차 못 만족한 채로 남는다. Y4 충돌 ③ 이 그 실물 |
| Q2 | **「권장 개발환경」 ↔ 「지원 타깃」의 관계** — ABI 3분할이 빌드 타깃 3분할인가 | 사용자 | 드라이버·SDK 의 타깃 매트릭스를 세울 수 없다. NetBSD/DragonFly 의 축도 이것에 딸린다 |
| Q3 | **CI 결선** — 다섯 중 무엇을 기계가 재는가 (전부 / ABI 3종 / 0). 그리고 이 저장소의 devcontainer(Arch, 목록 밖)는 대체되는가 별개 축인가 | 사용자 | §2 의 「미반영」이 「충돌」인지 정해지지 않는다. 이 저장소는 CI 이미지가 하나뿐이다 |
| Q4 | **하한의 적용 범위** — ⒜ 신규 코드만 ⒝ 기존 저장소 전부 ⒞ 벤더링된 검증기 포크까지 | 사용자 (#37 유보 해제 시) | 유보 ②의 처분이 정해지지 않는다 |
| Q5 | **정본 §0.3.1 「오라클 넷」의 개정 시점과 형태** — 병존 기간(§4.3(b))에 어느 쪽이 오라클인가. Phase E 가 넷을 셋으로 줄이는가, Rust 가 자리를 승계하는가 | 저장소 정책 | 포팅 착지 시 정본이 실물과 어긋난다. 비트-동등이 깨졌을 때 누가 이기는지도 이것에 딸린다 |
| Q6 | **`lint_guide_derived_tables` 의 원천을 어디로 옮기는가** — ⓐ Python 존치 ⓑ `isa/wt64v1_isa.json` 이관(그 JSON 에 현재 `INSTR_WORDS_REAL` 이 **없다** — 스키마 확장 필요) ⓒ 언어 중립 파일 신설 | 저장소 정책 | **포팅 착수 *전에* 나야 한다.** 착수 후면 정본 일관성 게이트가 깨진 채로 일한다 (§4.4) |
| Q7 | **`lint_section_refs` hard 구역 래칫을 어떻게 넘기는가** — 삭제(하강 허용의 예외를 만든다)인가, hard 구역의 정의를 저장소 경계에서 **프로그램 경계**로 넓히는가 | 저장소 정책 | asm 이 떠나는 순간 `make lint` 가 운다 (§4.5) |
| Q8 | **「구체적 Y4 ABI」가 가리키는 것** — hypercall ABI / lease capability 취득 경로 / 그 밖 중 어느 것인가, 몇 개인가 | 사용자 | 블로커의 **크기**가 정해지지 않는다 (§5.1) |
| Q9 | **Y4 ABI 블로커의 사정거리** — HIU 접촉 crate 만인가(그것은 Y4 가 이미 스스로 미뤄 두었다), 「Y4용 드라이버/SDK」 전부인가 | 사용자 | 형제 저장소의 Phase 계획이 착수 가능한지 정해지지 않는다 |
| Q11 | **`...` 의 표기 규약** — 목록이 열려 있음을 문서에 어떤 형태로 남기고, 항목 추가 시 갱신 책임은 어느 파일이 지는가 | 저장소 정책 | 항목이 추가될 때 어디를 고쳐야 하는지 모른다. 사본이 갈라진다 |
| Q12 | **포팅 산출물의 라이선스** — ⒜ SDK 지시대로 Apache-2.0 단독으로 좁히는가 ⒝ Rust 쪽에서도 삼중을 유지하는가 ⒞ LGPL 대신 다른 갈래로 커널 인접 소비자를 덮는가 (§4.8) | 사용자 (라이선스는 저작권자 결정) | 포팅 착지 시 **LGPL 갈래가 조용히 사라진다.** `LICENSE.md:64` 가 그 갈래를 둔 이유로 명시한 「Linux-kernel-adjacent 소비자」는 드라이버 저장소의 GPL-2.0+ 서브모듈로 이미 실재한다 |

**번호가 Q10 에서 건너뛴 이유** — 그 자리는 「포팅 착수까지 Python 어셈블러의
개정 정책」이었고 **닫혔다** (§0.1 결정 B → §4.7). 번호를 당기지 않는 것은
이 문서를 인용하는 형제 저장소의 좌표를 깨지 않기 위해서다.

**Q2 는 §0.1 결정 A 로 좁아졌다** — Bionic 축의 소비자는 정해졌고, 남은 것은
다섯 환경 전체의 타깃 여부와 NetBSD/DragonFly 의 축이다.

## 7. ⚠️ 재지 않은 것

- **방침 5종 OS 각각의 커널/libc/LLVM 실제 버전** — 재지 않았다. Alpine 의
  kernel 7.x · openSUSE Slowroll 의 7.x 가 언제 무엇인지 확인하지 않았다.
- **Rust 1.97 의 실재·릴리스 일자** — 상류 대조를 하지 않았다. 방침이 선언한
  하한을 그대로 옮겼을 뿐이다. (이 호스트에 `1.97.1` 툴체인이 설치돼 있다는
  것은 `rustup toolchain list` 로 쟀다 — 그것과 상류 릴리스 사실은 별개다.)
- **LineageOS 23.2 / AOSP 16 의 NDK ABI 수준** — 재지 않았다.
- **NetBSD 11.0 · DragonFlyBSD 6.4.2 의 Rust 타깃 tier** — 재지 않았다.
- **SDK·drivers 저장소의 Rust 실물** — **없음을 실측했다** (`/home/ybi/wavetensor-sdk`
  에서 `.rs` · `Cargo.toml` · `rust-toolchain*` 합계 **0**, HEAD `934963c`).
  따라서 「거기서 기준이 집행된다」(§3 (i))는 **계획이지 실측이 아니다.**
- **포팅 후 `lint_guide_derived_tables` 원천 이관의 대가 비교** — 재지 않았다.
  Q6 의 세 선택지에 값을 매기지 않았다.
- **Q6 ⓑ 의 스키마 확장 비용** — `isa/wt64v1_isa.json` 에 `INSTR_WORDS_REAL` 이
  없다는 것은 쟀으나, 넣는 데 무엇이 딸려 오는지는 재지 않았다.
- **이 문서 자신의 좌표를 기계가 아직 재지 않았다.** `lint_section_refs.py` 의
  축 1 정의역은 `git ls-files`(인덱스)이고 이 파일은 **미추적**이라, 실행이
  「축 1 정의역 밖 — 미추적 파일 1개 / 좌표 26건」으로 인쇄한다. 즉 **여기 적힌
  `파일:줄` 26건은 이 세션에서 사람이 손으로 대조했을 뿐 게이트가 물지 않았다.**
  커밋되면 정의역에 들어오고 그때 기계가 잰다. (손 대조에서 실제로 **일곱 건이
  어긋나 있었다** — 형제 저장소 문서와 `gates.yml` 이 이 세션 도중 움직였다.
  §8 의 교훈이 이 문서 자신에게도 걸린 것이다.)
- **`asm/` 파일이 실제로 떠났을 때 `make lint` 가 어떻게 죽는지** — 재지 않았다.
  §4.4 의 hard-fail 과 §4.5 의 래칫은 **코드를 읽어 판정한 것**이고 변이를
  주입해 확인하지 않았다. (이 저장소의 규율은 「검사가 무는지를 기계가 재야
  한다」이므로, 이 판정은 그 규율을 아직 만족하지 않는다.)

## 8. 브리프와 실물이 어긋난 자리 (고치지 않고 보고한다)

이 문서를 세우며 「현행」 주장을 개별로 실물 대조했다. 어긋난 것 **여섯**:

1. **`Alpine` 이 「전수 grep 0건」이 아니다** — `.claude-memos/remote_accelerator_access.md:107`
   에 1건 있다. 뜻은 다르다(원격 가속기 호스트의 경량 OS 후보). 결론(§2 의
   「선례 없는 신설 축」)은 바뀌지 않으나 **0건이라는 수치는 틀렸다.**
2. **`DragonFly` 가 1 파일이 아니라 2 파일이다** — `host_a_custom_hypervisor.md`
   외에 `.claude-memories/y4_separate_repo.md:9` (Y4 reuse manifest).
3. **asm 두 파일의 행 수는 낡지 않았다** — 조사 보고가 「2,574행·3,322행은
   낡았다」고 적었으나 실측이 정확히 **2,574 / 3,322행**이다. 바이트(117,443 /
   169,517 B)와 비교해 낡았다고 판정한 **범주 오류**다.
4. ~~**SDK 의 하한 결손이 4곳이 아니라 3곳이다**~~ — **이 항 자체가 착지
   시점에 이미 낡아 있었다 (2026-08-30 재실측으로 정정).**

   당시 이렇게 적었다 (좌표는 전부 **SDK 저장소** 것인데 원문이 저장소를
   안 밝혀 이 저장소의 없는 파일을 가리켰다 — 뿌리를 편집자가 전개했고,
   그 전개 외에는 축자다):
   「`/home/ybi/wavetensor-sdk/docs/architecture.md:32` 만 갱신됐고 남은
   결손은 `/home/ybi/wavetensor-sdk/README.md:32` ·
   `/home/ybi/wavetensor-sdk/CLAUDE.md:48` ·
   `/home/ybi/wavetensor-sdk/docs/phase_plan.md:29` 셋이다.」

   ※ 이 전개는 편의가 아니다. 형제 저장소 좌표를 저장소-상대로 적으면
   `lint_section_refs` R1 이 **이 저장소의 없는 파일**로 읽고 운다 —
   실제로 이 문서가 그 축에서 12건으로 실패했다. 절대 경로가 규약이다.

   **재실측 결과 그 셋도 전부 이미 갱신돼 있다** — 즉 결손은 3곳이 아니라
   **0곳**이다:

   | 좌표 | 실측 문면 |
   |---|---|
   | `/home/ybi/wavetensor-sdk/README.md:32` | Rust — **2024 Edition, stable toolchain ≥ 1.97** (user policy 2026-08-30 …) |
   | `/home/ybi/wavetensor-sdk/CLAUDE.md:48` | Core: Rust — **2024 Edition, stable toolchain ≥ 1.97** |
   | `/home/ybi/wavetensor-sdk/docs/phase_plan.md:29` | Rust stable toolchain — **2024 Edition · stable `>= 1.97`** |

   ⚠️ **이것이 이 세션이 여섯 번 밟은 함정의 여섯 번째다** — 병행 세션이
   움직이는 동안 조사 산출물을 그대로 옮겨 적었고, 그 낡은 전제가 「고치지
   않았다」는 문장과 함께 착지물 안에 굳었다. 그대로 두면 다음 세션이 **이미
   고쳐진 파일을 다시 고치러** 간다. 교훈은 §7 과 같다: **형제 저장소의
   「현행」 주장은 적는 순간 다시 재라.**
5. **Y4 Rust 하한은 미결이 아니라 유보다** — 브리프가 그 뭉치를 미결로 세웠으나
   작업 큐 #37 에 **사용자 판정(2026-08-30)** 이 있다. §5.2 에 유보로 적었다.
   미결로 적었으면 이미 내려진 결정을 지우는 것이 된다.

6. **이 저장소의 메모리 시드에 낡은 「현행」 진술이 있다** —
   `.claude-memories/wavetensor_sdk_separate_repo.md:22` 「WaveTensor SDK repo is
   not yet committed (initial scaffold only); first commit is deferred until the
   user explicitly asks.」 **실측: 커밋 3개, HEAD `934963c`, 워킹트리 clean.**
   첫 커밋은 이미 났다. **고치지 않고 보고한다** — 그 문장은 사실 진술이자
   *결정 진술*(「사용자가 명시로 요청할 때까지 미룬다」)이라, 사실만 갱신하면
   결정이 어떻게 닫혔는지가 지워진다. 갱신 형태는 사람이 정할 일이다.

부수 — 이 세션 중 저장소가 움직였다: 과제 스냅샷의 HEAD 는 `c7b92ee` 였으나
실제 HEAD 는 `727532a` 이고, 워킹트리에 다른 파도의 미커밋 변경이 있다
(`Makefile` · `.github/workflows/gates.yml` · `scripts/lint_toolchain_pins.py` ·
`scripts/hooks/pre-commit` + 미추적 `scripts/lint_selftest_coverage.py`).
**이 문서는 그것들을 건드리지 않았다.**
