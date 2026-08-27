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
# 1) lint 14종
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
