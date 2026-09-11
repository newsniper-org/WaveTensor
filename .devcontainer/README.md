<!-- SPDX-License-Identifier: CC-BY-4.0 -->
<!-- SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors -->

# WaveTensor 검증 환경 (devcontainer)

## 왜 만들었는가

**형식-우선(formal-first) 전략에서는 도구가 곧 게이트다.** 도구가 흩어져 있으면
게이트가 "내 머신에서만 돈다" 가 되고, 그것은 게이트가 아니다.

실제로 흩어져 있던 증상 (2026-08-20 실측):

| 증상 | 결과 |
|---|---|
| `cocotb` 가 pipx venv(python 3.13)에 설치 | 시스템 `python3 -c "import cocotb"` 가 **실패**. 조사 에이전트가 "테스트 실행 불가" 로 **오판**했다 |
| `iverilog` 부재 | §31.13.3 의 miter 재실행 **불가**, `WT_SIM_ASSERT` X-검사가 **영영 발화 불가**(verilator 는 2-state) |
| `frama-c` 가 opam switch 안에만 | 호출 규약을 따로 외워야 함 (메모까지 존재) |
| SymbiYosys / Apalache / Kani 부재 | 형식 인프라 확장 경로가 막혀 있음 |

devcontainer 는 이 넷을 **환경 정의 하나로** 없앤다.

---

## 경계 — 무엇이 들어가고 무엇이 빠지는가

이 경계는 편의가 아니라 **검증 축의 분할**과 같다.

| 검증 축 | 대상 | 도구 | 위치 |
|---|---|---|---|
| **(a)** 프로토콜 · 상태기계 · 소유권 | 형식화 적합 | TLC (선-formal) · SBY (후-formal) | **컨테이너** |
| **(b)** 산술 bit-exactness | golden 대조가 현실적 | cocotb · verilator · iverilog · golden(python) | **컨테이너** |
| **(c)** 타이밍 · 면적 · Fmax | 형식 대상 아님 — **측정** 대상 | **Vivado** | **호스트 전용** |

### 네 번째 축 — 설계 (2026-08-20 신설)

WT64v1 **RTL 전면 재구현**이 착수되면서 축이 하나 늘었다. 재구현의 정본은
`docs/wt64v1-architecture-guide/main.pdf` 이고, 설계 언어는 SpinalHDL 이다.

| 도구 | 고정값 | 어디서 고정하는가 |
|---|---|---|
| JDK | `jdk21-openjdk` **21.0.12** | Dockerfile (버전 **명시** — 무버전은 26.0.2 를 준다) |
| sbt 런처 | 스냅샷 `sbt` **2.0.6** | ALA 스냅샷 |
| sbt 실제 | **1.12.15** | `rtl/spinal/project/build.properties` |
| Scala | **2.13.12** | `rtl/spinal/build.sbt` |
| SpinalHDL | **1.14.2** | 〃 |

`scripts/lint_toolchain_pins.py` 가 세 곳(Dockerfile ARG · devcontainer.json
build.args · rtl/spinal 빌드 파일)이 같은 값을 말하는지 **기계로** 대조한다.

> **⚠️ 넷째 자리는 금지다** (2026-08-30 적발·처분). `.github/workflows/gates.yml`
> 이 같은 핀 여덟을 `--build-arg` 로 넘기고 있었다. `--build-arg` 는 ARG
> 기본값을 **덮으므로** 그것은 사본이 아니라 가장 센 선언이었는데, 핀 lint 의
> 정의역 밖이라 아무도 재지 않았다 — 그 사이 `TLA_BLAKE2B512` 가 죽은 값
> (`4b2313f3…`)으로 남아 있었다. 2026-08-29 의 재핀(`cdc769d`)이 세 곳 중
> 둘만 갱신했고, GHA 층 캐시가 그 RUN 을 건너뛰는 동안만 가려져 있었다.
>
> 처분은 「대조 추가」가 아니라 **금지**다. CI 는 이 저장소의 Dockerfile 을
> 그대로 빌드하므로 핀 사본이 정보를 하나도 더하지 않는다 — 지운 여덟 중
> 일곱은 기본값과 글자 그대로 같았고, 중복의 유일한 효과가 이 사고였다.
> 지금 gates.yml 이 넘기는 것은 호스트 적응 값 `UID`/`GID` 둘뿐이고,
> lint 가 `.github/workflows/` 를 **순회**하며(손 목록이 아니다) 그 밖의
> build-arg 를 발견하면 죽는다.

> **⚠️ 실측이 뒤집은 가정 셋** (2026-08-20, ALA 스냅샷 `2026/08/12` 기준)
>
> 1. **스냅샷의 `sbt` 는 1.x 가 아니라 2.0.6 이다.** 그래도 쓸 수 있는 이유는
>    그것이 *런처*이기 때문 — launcher jar 의 boot properties 가
>    `version: ${sbt.version-read(sbt.version)[2.0.6]}` 이므로 2.0.6 은
>    **기본값**이고 `project/build.properties` 가 이긴다. 아티팩트를 열어
>    확인했고, 이미지 빌드의 스모크가 실제 부트스트랩까지 증명한다.
> 2. **`scala` · `mill` · `coursier` 패키지는 스냅샷에 없다.** Scala 컴파일러는
>    sbt 가 coursier 로 받으므로 정상이다. **mill 경로는 닫혀 있다.**
> 3. **SpinalHDL 은 Scala 3 빌드가 없다** (`spinalhdl-core_3` 부재).
>
> 의존은 이미지 층에 **구워 둔다**. 컨테이너를 다시 만들 때 네트워크가 결과를
> 바꾸면 그것은 고정이 아니다 — TLA+ 를 해시로 묶은 것과 같은 이유다.
> (다만 TLA+ 는 **모범이 아니라 예외**다 — 해시로 묶여 있을 뿐 좌표가 불변이
> 아니고, 그래서 아래 「TLA+ / TLC」 절이 따로 있다. Maven 릴리스 좌표로
> 묶이는 이 Scala 층 쪽이 정상형이다.)
> 그 층은 동시에 **툴체인 스모크**다: 부트스트랩·컴파일러 플러그인·
> `SpinalSystemVerilog` 출력까지 한 번에 판정하고, 실패하면 이미지 빌드가 죽는다.

### ⛔ Vivado 가 들어가지 않는 이유 (계약이지 편의가 아니다)

1. **81 GB** 이고 라이선스가 걸려 있다.
2. 프로젝트 규율상 **2025.2 위로 절대 올리지 않는다** — 2025.2 가 마지막
   라이선스-프리 릴리스이고, 2026.1 은 BASIC 에서 Alveo 를 제외한다.
   컨테이너에 넣으면 "이미지를 다시 만들면 버전이 올라가는" 경로가 생긴다.
3. 합성 gate 의 증거는 **그 도구의 출력 그 자체**다. 고정된 호스트 설치본에서
   재는 것이 provenance 를 유지하는 유일한 방법이다.

∴ **컨테이너에서 도는 것**: `make lint` · cocotb 회귀 · `proofs/tla/run.sh` · golden 재생성
   **호스트에서 도는 것**: `make synth-sys-gate` · `make synth-fp-op` · `fp_op_gate_check.py`

### 그 밖에 의도적으로 뺀 것

| 도구 | 뺀 이유 |
|---|---|
| **Apalache** | 모델을 **TLC-checkable(유한·소형 상수)** 로 유지하는 제약이 인코딩 결정(불투명 토큰)을 강제해 왔다. 그 제약을 푸는 것은 **모델링 결정**이지 환경 결정이 아니다 |
| **nextpnr / ECP5 P&R** | 검증 축 (c). ECP5 는 gate 가 아니라 MEASUREMENT 이기도 하다 |
| **Isabelle** | 호스트가 **custom 설치본**이라 pacman 경로가 없다. 공식 번들을 쓰려면 별도 층에서 명시적으로 |
| ~~**SymbiYosys**~~ | ~~저장소 선례 0건~~ → **2026-08-20 기본 ON.** 재구현이 후-formal 단계를 실제로 밟는다. (정본은 2026-08-27 개정으로 방법이 아니라 **요건**을 규정한다 — sby+z3 는 그 요건을 만족하는 선택이고 IC3/PDR 계열도 같은 요건 아래 있다.) 커밋 `f57802a1…`(v0.66) 로 고정 — 이전 판은 `--depth 1` 로 브랜치 끝을 받는 **롤링 자산**이었다 |
| **boolector / bitwuzla / cvc5** | 스냅샷에 **없다**(실측: `target not found`). 그리고 없어도 된다 — 솔버는 **z3 하나만** 둔다. yices·cvc4 도 스냅샷에 있지만 넣지 않는다: 기본값에 의존하면 *어느 solver 로 쟀는지 증거에 안 남는다.* `.sby` 가 솔버를 명시하지 않으면 크게 실패해야 한다 |
| Frama-C / CBMC / Verus / Kani / Rocq | drivers·Y4 층 도구. WaveTensor RTL 대상이 아니다 |

---

## 재현성 — 스냅샷 고정

Arch 는 롤링이라 그냥 쓰면 **빌드할 때마다 도구 버전이 달라진다.** 그래서
[Arch Linux Archive](https://archive.archlinux.org/) 스냅샷으로 날짜를 고정한다.

```
ARG ALA_SNAPSHOT=2026/08/12
```

> **이 날짜를 바꾸는 것은 도구 버전을 바꾸는 것이다.** 형식-우선 전략에서 도구
> 버전은 증거의 일부이므로, 변경 시 gate 재측정과 같은 급의 기록을 남길 것
> (§22.14b-10 provenance 규율의 도구 층 적용).

`pacman -Syyuu` 를 쓰는 이유: base 이미지의 DB 가 스냅샷보다 **최신**이라
다운그레이드를 허용하지 않으면 해소 불가 충돌로 빌드가 죽는다.

### ⚠️ TLA+ / TLC — 이 이미지에서 유일하게 **불변이 아닌** 핀

다른 층은 거의 전부 불변 좌표에 묶여 있다 (ALA 스냅샷 날짜 · 커밋 sha ·
Maven/PyPI 릴리스 버전). **TLC 가 그렇지 않다.** 알려진 결손이고, 감추지
않는다. (작은 둘째 예외 하나 — `COCOTB_PYTHON=3.13` 은 마이너 좌표라 uv 가
빌드 시점의 최신 패치로 해석한다. 실측 2026-08-29: `3.13.15`. TLC 와 달리
해시로도 묶여 있지 않으므로 여기 함께 적어 둔다.)

| | |
|---|---|
| 받는 곳 | **보관본 `vendor/tla2tools.jar`** (2026-09-11 착지, `COPY`). 출처는 `github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar` — 재핀할 때만 다시 받는다 |
| 그 태그의 정체 | **롤링 pre-release** (`prerelease=true`). 상류 README: 「every commit to the master branch is built & uploaded to the 1.8.0 Clarke pre-release」 ⇒ **같은 URL 에 새 빌드가 덮인다** |
| 고정 수단 | BLAKE2b-512 + TLC 자기보고 build/rev **셋을 함께** |
| 사는 것 | 조용한 바꿔치기 없음 — 바이트가 바뀌면 `b2sum -c` 가 빌드를 죽인다 |
| **못 샀던 것 (2026-09-11 이전)** | **재현성.** 다음 master 푸시와 함께 이 바이트는 받을 수 없게 되고, 그때부터 정본 Dockerfile 은 from-scratch 빌드 불가가 됐다 — **보관본 착지로 닫혔다.** 상류 표류는 이제 수리 사건이 아니라 선택적 업그레이드다 (`vendor/README.md` 의 재핀 절차) |

표류 이력 (실측):

| 시점 | blake2b (앞 8) | 크기 | 상태 |
|---|---|---|---|
| 2024-08-08 (호스트 pacman, 다른 계보) | — | 2,274,532 B | TLC 2.19 |
| 2026-08-11 | `4b2313f3…` | 4,486,193 B | **더는 받을 수 없다** |
| 2026-08-21 | `644f4331…` | 4,487,757 B | **더는 받을 수 없다** |
| 2026-09-10 | `a2ccfb8c…` | 4,490,846 B | 현행 핀 |

관측 이력 (표가 *무엇인지*를 적는다면 이쪽은 *언제 재 봤고 무엇이 나왔는지*를
적는다 — 둘은 다른 것이고, 관측을 안 적어 두면 다음 사람이 「롤링이라니 또
죽었겠지」로 넘겨짚거나 재지도 않고 살아 있다고 가정한다):

| 관측일 | 한 일 | 결과 |
|---|---|---|
| 2026-08-29 | 재핀 (커밋 `cdc769d`) | 구 핀이 죽어 있었다 |
| 2026-08-30 | 상류 자산을 다시 받아 대조 | `644f4331…` / 4,487,757 B — **현행 핀과 일치. 표류 없음** |
| 2026-09-11 | 상류 자산을 다시 받아 대조 | `a2ccfb8c…` / 4,490,846 B / `TLC2 Version 2026.09.10.191157 (rev: c3af5e2)` — 직전 핀(2026-08-21 빌드)과 **불일치. 표류 발생**(상류 푸시 2026-09-10T19:16Z). 재핀 |
| 2026-09-11 | **보관본 착지** — 같은 바이트를 `vendor/tla2tools.jar` 로 커밋 | 이후 상류 표류는 수리 사건이 아니다. 번들 구성·라이선스 실측은 `vendor/README.md` |

> ⚠️ **「안정적이다」로 읽지 말 것.** 위 표의 성질은 하나도 변하지 않았다 —
> `v1.8.0` 은 여전히 롤링 pre-release 이고 master 커밋마다 같은 URL 이 덮인다.
> 각 관측이 말하는 것은 오직 **그날까지의 상태**뿐이다 — 8/30 의 「표류 없음」은
> 그로부터 11일 뒤 무효가 됐다. 다음 푸시가 언제인지는 재지 않았고 잴 수도 없다.
> 관측된 표류 간격은 8/11 → 8/21 (열흘) · 8/21 → 9/10 (스무날), **표본 2** —
> 주기라 부르기엔 아직 적다.

> **2026-08-11 핀이 죽어 있는 동안 아무도 몰랐다.** 파생 빌드가 캐시 층을
> 재사용했기 때문이다. 캐시가 한 일을 정확히 적어 둔다 — 캐시는 **이미지와
> 핀의 일치를 유지하면서** from-scratch 실패만 가렸다. 어긋난 것은
> 이미지↔핀이 아니라 **핀↔상류**다.
>
> 실측 (2026-08-29): 이 호스트에 남아 있는 세션 이전 이미지 넷(08-19 15:43 ·
> 08-19 15:52 = `wavetensor-dev:test` · 08-20 06:25 · 08-28 16:34 UTC)은
> **전부** b2 `4b2313f3…` / 4,486,193 B / `TLC2 Version 2026.08.11.125311
> (rev: 0894c34)` 를 담고 있고 그것은 그때 커밋돼 있던 핀과 같다.
> `644f4331…` 을 담은 이미지는 이 세션 이전에 하나도 없다.
>
> ⇒ 그러므로 **이미지를 열어 `b2sum` 을 재는 것으로는 이 부패가 드러나지
> 않는다.** 드러나는 곳은 오직 `--no-cache` 재빌드다 —
> **정본 Dockerfile 의 from-scratch 빌드가 도는지는 따로 재야 한다.**
>
> 2026-08-29 에 `--no-cache` 로 정본을 전량 재빌드해 우회를 해소했다
> (35 스텝 전부 재실행 · `[wt] TLC 스모크 OK` · `[wt] SpinalHDL 스모크 OK` ·
> `[wt] sby OK` · `[wt] btormc 3.2.4 OK`). 그 이미지로 게이트를 다시 쟀다:
> `make rtl-formal` **358/358** · `proofs/tla/run.sh` **16/16** · 자기보고
> (`~/wt-toolversions.sh`)의 TLC 줄과 새 `tla2tools` 줄이 핀과 일치.

#### 불변 좌표로의 전환 — 시도했고 **실측으로 기각**했다 (2026-08-29)

상류 README 가 실제로 가리키는 배포처는 릴리스가 아니라 Maven **스냅샷**
저장소다. 스냅샷 자체는 가변이지만 개별 빌드 파일은 타임스탬프·빌드번호가
박힌 유일 경로이므로 불변이다 — `1.8.0-20260821.161407-53`, 3,729,383 B.
그 아티팩트가 GH 자산과 **같은 빌드**인 것도 확인했다: TLC 자기보고 동일
(`2026.08.21.155922 rev 9787e65`), 공통 엔트리 1,600 개의 **CRC32 전부 일치**,
Maven 쪽에만 있는 엔트리 0.

**그런데 그 jar 로는 우리 워크로드가 돌지 않는다.**

배터리는 `make rtl-formal` 358 run + `proofs/tla/run.sh` 16 run = **374 run**.

| 시도 | 결과 (실측) |
|---|---|
| 얇은 jar 그대로 | **374/374 실패.** 전부 같은 원인 — `NoClassDefFoundError: javax/mail/SendFailedException` at `tlc2.TLC.main(TLC.java:333)` |
| \+ POM 이 선언한 유일 런타임 의존 `com.sun.mail:mailapi:1.6.8` | 모델 검사 **시작 직후** 다시 죽는다. 206 run 확인 후 중단, 206/206 NoClassDefFoundError, 클래스명이 인쇄된 36 건은 전부 `com/google/gson/JsonElement`. **gson 은 POM 에 없다** |
| 대조군 — 현행 GH 지방 jar | **374/374 정상** (OK 374 / FAIL 0) |

대조군이 있으므로 위 실패는 **패키징에 귀속된다** — 환경·모델·러너가 아니다.

⇒ Maven 아티팩트는 자립 실행 배포본이 아니다(Maven 소비자가 의존 해석으로
채우는 것을 전제한 얇은 jar). GH 지방 jar 가 더 담은 520 엔트리는
gson(230) · com.sun.mail+javax.mail+javax.activation(233) · prettier4j(53) ·
javamail 리소스 2 다.

정식 릴리스로의 **다운그레이드도 불가**: 최신 정식은 `v1.7.4`(2024-08-05) =
TLC 2.19 인데 `-noGenerateSpecTE` 를 인식하지 못한다(실측:
`unrecognized option`). 러너가 358 run 전부에 쓰는 플래그다.

#### 재지 **않은** 것

- Maven 스냅샷 저장소의 보존(purge) 정책.
- 얇은 jar 에 Maven Central 불변 릴리스(mailapi·gson·prettier4j)를 더해
  지방 jar 를 **재조립**하면 도는지. 재조립하려면 gson·prettier4j 의 버전을
  알아야 하는데 지방 jar 는 shading 으로 `META-INF/maven/**` 를 지운다
  (실측) — 아티팩트만 보고는 정해지지 않는다. 상류 빌드 정의를 읽어야 하고,
  그것은 **우리가 배포본을 조립한다**는 뜻이라 별개의 정책 결정이다.

#### 그래서 층에 무엇을 넣었나 — **실행 스모크**

이번에 배운 것은 「`tlc -h` 가 도는 것은 아무것도 뜻하지 않는다」다. 얇은 jar
는 인수 없는 호출에 버전을 인쇄하고 깨끗이 끝났다(파라미터 오류 경로가 먼저
반환한다). **깨진 것은 실제 모델 검사였다.** 그래서 TLA 층이 이제 진짜 모델을
하나 검사한다 — 파싱 · SANY · 검사 시작 · 완주 · `-noGenerateSpecTE` 수용까지.
같은 스모크를 얇은 jar 에 물려 **실제로 잡히는 것**도 확인했다(양방향 실측).

---

## 사용

### VS Code / Cursor
`.devcontainer/` 를 인식하는 편집기에서 "Reopen in Container".

### 수동 (podman / docker)

```sh
# 빌드
podman build --build-arg UID=$(id -u) --build-arg GID=$(id -g) \
    -t wavetensor-dev -f .devcontainer/Dockerfile .devcontainer

# 실행 — `--userns=keep-id` 를 빠뜨리지 말 것 (아래 참조)
podman run --rm -it --userns=keep-id \
    -v "$PWD":/workspace:z -w /workspace wavetensor-dev

# 도구 버전 자기보고 — "어느 버전으로 쟀는가" 의 답
~/wt-toolversions.sh
```

> ### ⚠️ rootless podman: `--userns=keep-id` 는 선택이 아니다
>
> 빠뜨리면 저장소가 컨테이너 안에서 **uid 0 소유**로 보이고, 비-root 사용자가
> 쓰기를 못 한다. 증상은 조용하지 않지만 **엉뚱한 곳을 가리킨다** —
>
> ```
> util.Assert$TLCRuntimeException: TLC could not make a directory
>   states/26-08-19-15-47-12.652 for the disk files it needs to write.
> ```
>
> 이걸 처음 봤을 때 TLC 버전 문제로 오진했다 (컨테이너가 받은 jar 가 호스트와
> 달랐기 때문). 호스트 jar 를 주입해도 같은 실패가 났고, 그제서야 권한으로
> 좁혀졌다. **`make lint` 는 이 조건에서도 통과한다** — 쓰기를 안 하기 때문에.
> 즉 lint 만 보고 "환경 OK" 라고 판단하면 안 된다.

### 선택 층 켜기

```sh
podman build --build-arg WITH_SBY=1 ... # SymbiYosys 포함
```

---

## 검증 — 컨테이너가 실제로 게이트를 돌리는가

이미지를 만들었다고 끝이 아니다. **아래가 전부 통과해야 이 환경이 쓸모 있다.**

```sh
# 1) lint 16종
make lint                                   # → exit 0

# 2) cocotb 회귀 — 6 MOD
for m in HIU ISA_Decoder ALU_Extended Top_Core Cluster Pod; do
    rm -rf sim_build; make MOD=$m
done                                        # → 합계 329 PASS, FAIL 0

# 3) 양 빌드
make test-cluster-both                      # → rc 0

# 4) 어셈블러 단위
python3 -m unittest asm.test_wavetensor_asm # → rc 0

# 5) 형식 게이트 (16 run: GOOD 2 + guard 삭제 7 + requesterid 1 + witness 6)
cd proofs/tla && ./run.sh                   # → exit 0

# 6) 컨테이너에서 **돌면 안 되는 것** — 부재 확인
command -v vivado || echo "OK: Vivado 부재(의도)"
```

> ✅ **5번은 2026-08-20 에 결선됐다.** `scripts/hooks/pre-commit` 이 커밋을 막고
> (`make hooks-install`), `.github/workflows/gates.yml` 이 CI 에서 돌린다.
> 재구현 선-formal 은 `make rtl-formal` 로 분리돼 있으며, **모델이 없으면
> 통과가 아니라 실패한다** — 미측정은 통과가 아니다.

---

## 알려진 한계

- **호스트 UID 를 빌드 인자로 받는다.** 다른 UID 의 사용자가 같은 이미지를 쓰면
  bind mount 권한이 어긋난다. 그때는 재빌드가 정답이다.
- **`podman` 은 `:z` 라벨이 필요할 수 있다** (SELinux 환경).
- 이미지 크기는 선택 층을 켜는 만큼 커진다. 기본 층만으로 일상 게이트는 전부 돈다.
