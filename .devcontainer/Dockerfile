# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
#
# WaveTensor 검증 환경 — 형식(formal) + 시뮬레이션 도구 일체.
#
# ⛔ 이 이미지에 들어가지 않는 것: Vivado / Cadence 등 벤더 P&R·에뮬레이션 도구.
#    이유는 편의가 아니라 계약이다 —
#      · Vivado 2025.2.1 은 81 GB 이고 라이선스가 걸려 있으며, 프로젝트 규율상
#        **2025.2 위로 절대 올리지 않는다**(마지막 라이선스-프리 릴리스).
#      · 합성 gate(LUT/DSP/BRAM/Fmax/WHS)는 그 도구의 출력이 곧 증거이므로
#        호스트의 고정 설치본에서만 잰다.
#    ⇒ 컨테이너 = 검증 축 (a) 프로토콜·상태기계 + (b) 산술 bit-exactness
#       호스트     = 검증 축 (c) 타이밍·면적
#
# 재현성: Arch Linux Archive 스냅샷으로 **날짜 고정**한다. 형식-우선 전략에서
# 도구 버전은 증거의 일부다 — "어느 버전으로 쟀는가" 를 답할 수 없는 gate 는
# gate 가 아니다 (§22.14b-10 provenance 규율의 도구 층 적용).

FROM archlinux:base-devel

# ---------------------------------------------------------------------------
# 1) 스냅샷 고정 — 이 날짜를 바꾸는 것은 도구 버전을 바꾸는 것이다.
#    바꿀 때는 gate 재측정과 같은 급의 기록을 남길 것.
# ---------------------------------------------------------------------------
ARG ALA_SNAPSHOT=2026/08/12
# `-Syyuu` 이어야 한다: base 이미지의 pacman DB 가 스냅샷보다 **최신**이므로
# 다운그레이드를 허용하지 않으면 해소 불가 충돌로 빌드가 죽는다.
RUN printf 'Server=https://archive.archlinux.org/repos/%s/$repo/os/$arch\n' "${ALA_SNAPSHOT}" \
      > /etc/pacman.d/mirrorlist \
 && sed -i 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf \
 && pacman -Syyuu --noconfirm

# ---------------------------------------------------------------------------
# 2) 시뮬레이션 + 합성-프론트엔드 + SMT
#    - verilator  : 주 시뮬레이터 (cocotb 기본). assertion 기본 ON
#    - iverilog   : 4-state 흐름 — `WT_SIM_ASSERT` X-검사와 miter 재실행에 필수.
#                   호스트에 없어서 §31.13.3 miter 가 재실행 불가였던 그 구멍.
#    - yosys      : premap $mul 증거 · ECP5 경로 · write_smt2(형식 BMC 백엔드)
#    - z3         : yosys-smtbmc 백엔드. smtbmc 의 기본값은 yices 인데 넣지
#                   않는다 — 미설치로 두어 `-s z3` 를 **명시하게** 만든다
#                   (기본값에 의존하면 어느 solver 로 쟀는지 증거에 안 남는다).
#                   cvc5 는 Arch 공식 저장소에 없다(실측: ALA 스냅샷 target
#                   not found). 필요하면 별도 층에서 명시적으로 넣을 것.
# ---------------------------------------------------------------------------
# `curl` 은 아래 TLA+ 단계가 쓴다 — base-devel 에 없으므로 여기서 넣는다.
# `nextpnr` 는 넣지 않는다: ECP5 P&R 은 검증 축 (c)(배치·배선) 이고
# 그 축은 이 컨테이너의 대상이 아니다. ECP5 는 gate 가 아니라 MEASUREMENT 이기도 하다.
#    ⚠️ JDK 는 **버전을 명시**한다. `jdk-openjdk` 는 무버전 메타 이름이라 스냅샷이
#    주는 것이 곧 버전이 되는데, 이 스냅샷에서 그것은 **26.0.2** 다 (실측).
#    비-LTS JDK 를 TLC 와 Scala 툴체인의 바닥으로 깔면 "어느 JDK 로 쟀는가" 의
#    답이 스냅샷 날짜에 종속된다. `jdk21-openjdk` (21.0.12.u8-1, 실측 존재) 로
#    고정한다 — LTS 이고, sbt 1.12.x · Scala 2.13.x 가 모두 지원하는 범위다.
RUN pacman -S --noconfirm --needed \
      git make cmake pkgconf which diffutils curl \
      python python-pip \
      verilator iverilog gtkwave \
      yosys \
      z3 \
      jdk21-openjdk \
 && pacman -Scc --noconfirm

# ---------------------------------------------------------------------------
# 3) TLA+ / TLC — proofs/tla/run.sh 가 merge gate 로 쓰는 도구.
#    Apalache 는 넣지 않는다: 모델을 **TLC-checkable(유한·소형 상수)** 로
#    유지하는 제약이 인코딩 결정(불투명 토큰)을 강제해 왔고, 그 제약을 푸는
#    것은 모델링 결정이지 환경 결정이 아니다. 필요해지면 그때 별도 층으로.
# ---------------------------------------------------------------------------
#    ⚠️ 실측 주의 — **`v1.8.0` 태그는 롤링 자산을 서빙한다.** 그 URL 로 받으면
#    빌드 시점에 따라 TLC 버전이 달라진다 (실측: 호스트 2.19/2024-08-08 =
#    2,274,532 B vs 컨테이너 2026.08.11 = 4,486,193 B). 태그가 버전을
#    고정하지 못하므로 **BLAKE2b-512 로 고정**한다 — 이 저장소가 gate 증거에
#    적용하는 provenance 규율(§22.14b-10)을 도구에 그대로 적용한 것이다.
#    해시를 바꾸는 것은 검증 도구를 바꾸는 것이다.
#
#    (참고: 두 버전 모두 `proofs/tla/run.sh` 16 run 을 통과한다 — 실측 확인.
#     그래도 고정하는 이유는 "돌더라" 가 아니라 "무엇으로 쟀는지 답할 수
#     있어야 한다" 이다.)
#    해시 계열은 저장소 전체가 **BLAKE2b-512** 로 통일돼 있다 (`b2sum` 기본값).
#    stdlib `hashlib.blake2b(digest_size=64)` 와 같은 값이며, 판정기 핀·생성물
#    출처·게이트 증거가 전부 같은 계열을 쓴다 — 계열이 섞이면 "무엇으로 쟀는가"
#    앞에 "어느 해시로?" 라는 질문이 하나 더 붙는다.
ARG TLA_VERSION=1.8.0
ARG TLA_BLAKE2B512=4b2313f35e5f2965120c161dbb982c8541fff20b9a556543bccbc5163f7fcdc40a7dafa43b5b99c628502409dcda7274936df8509bba8fded6d3b51d8f5ffe45
RUN mkdir -p /usr/share/java \
 && curl -fsSL -o /usr/share/java/tla2tools.jar \
      "https://github.com/tlaplus/tlaplus/releases/download/v${TLA_VERSION}/tla2tools.jar" \
 && echo "${TLA_BLAKE2B512}  /usr/share/java/tla2tools.jar" | b2sum -c - \
 && printf '#!/bin/sh\nexec java -XX:+UseParallelGC -cp /usr/share/java/tla2tools.jar tlc2.TLC "$@"\n' \
      > /usr/local/bin/tlc \
 && printf '#!/bin/sh\nexec java -cp /usr/share/java/tla2tools.jar tla2sany.SANY "$@"\n' \
      > /usr/local/bin/sany \
 && chmod +x /usr/local/bin/tlc /usr/local/bin/sany

# ---------------------------------------------------------------------------
# 4) cocotb — **python 버전이 실제 제약이다** (실측으로 두 번 확인):
#      · cocotb 2.0.1 은 Python **≤ 3.13** 만 지원한다 (빌드가 그렇게 죽는다)
#      · Arch 스냅샷의 시스템 python 은 **3.14.7**
#    호스트가 cocotb 를 pipx venv(3.13)에 둔 것도 같은 벽을 피한 결과였다.
#
#    그래서 시스템 python 에 넣지 않고 `uv` 로 **python 3.13 을 고정 설치**해
#    그 위에 올린다. 시스템 python 업그레이드가 cocotb 를 깨지 못하게 분리하는
#    것이 목적이고, 부수적으로 python 버전 자체가 고정 증거가 된다.
#
#    ⚠️ 정직 기록: 이것은 "호출 함정을 없앴다" 가 아니라 **"함정을 하나로
#    묶고 문서화했다"** 이다. `python3 -c "import cocotb"` 는 여기서도 실패한다.
#    Makefile 이 쓰는 것은 `cocotb-config --makefiles` 이고 그것이 PATH 에 있으면
#    된다 — 회귀는 그 경로로 돈다.
# ---------------------------------------------------------------------------
#    설치 위치는 **시스템 경로**로 강제한다 — root 홈에 깔면 아래에서 만드는
#    비-root 개발 사용자가 접근하지 못한다.
ARG COCOTB_VERSION=2.0.1
ARG COCOTB_PYTHON=3.13
ENV UV_PYTHON_INSTALL_DIR=/opt/uv-python \
    UV_TOOL_DIR=/opt/uv-tools \
    UV_TOOL_BIN_DIR=/usr/local/bin
RUN pacman -S --noconfirm --needed uv && pacman -Scc --noconfirm \
 && uv python install "${COCOTB_PYTHON}" \
 && uv tool install --python "${COCOTB_PYTHON}" "cocotb==${COCOTB_VERSION}" \
 && chmod -R a+rX /opt/uv-python /opt/uv-tools \
 && cocotb-config --version

# ---------------------------------------------------------------------------
# 4b) Scala / SpinalHDL — RTL 전면 재구현의 설계 언어 층.
#
# 네 개의 버전이 **각각 독립적으로** 고정돼야 한다. 하나라도 흐르면 "어느
# 툴체인으로 생성한 RTL 인가" 에 답할 수 없다 (§6.6 「도구는 증거의 일부다」).
#
#   · sbt 런처   — 스냅샷의 `sbt` 패키지. 이 스냅샷에서는 **2.0.6** 이다.
#   · sbt 실제   — 런처가 아니라 `project/build.properties` 가 정한다.
#   · Scala      — SpinalHDL 이 빌드된 그 버전으로 맞춘다.
#   · SpinalHDL  — 라이브러리 2종 + **컴파일러 플러그인** 1종.
#
# ⚠️ 실측 주의 1 — **스냅샷의 sbt 는 1.x 가 아니라 2.0.6 이다.** 그래도 쓸 수
#    있는 이유는 그 패키지가 *런처*이기 때문이다. 셸 스크립트에
#    `build_props_sbt_version` 해석이 있고, launcher jar 의 boot properties 가
#    `version: ${sbt.version-read(sbt.version)[2.0.6]}` 로 선언한다 —
#    즉 **2.0.6 은 기본값일 뿐이고 실제 버전은 build.properties 가 정한다.**
#    (패키지를 풀어 확인한 사실이지, "돌더라" 가 아니다. 다만 *부트스트랩이
#    실제로 성공하는지*는 아래 스모크가 증명한다 — 읽은 것과 돈 것은 다르다.)
#
# ⚠️ 실측 주의 2 — **Arch 에 `scala` 패키지는 없다.** 정상이다. Scala 컴파일러는
#    sbt 가 coursier 로 받으며, 그래서 버전이 pacman 이 아니라 build.sbt 에
#    고정된다. `mill`·`coursier` 도 스냅샷에 없으므로 mill 경로는 닫혀 있다.
#
# ⚠️ 실측 주의 3 — SpinalHDL 은 **Scala 3 빌드가 없다** (`spinalhdl-core_3` 부재).
#    2.13 계열만 있고, 1.14.2 의 POM 이 의존하는 것은 정확히 **2.13.12** 다.
#    binary cross (`_2.13`) 로 배포되므로 다른 patch 도 될 가능성이 높으나,
#    상류가 실제로 빌드한 값을 쓰는 것이 재현성에서 가장 싸다.
#
# 재현성: 의존을 이미지 층에 **구워 둔다**. 컨테이너를 다시 만들 때 네트워크가
# 결과를 바꾸면 그것은 고정이 아니다 — TLA+ 를 해시로 묶은 것과 같은 이유다.
# ---------------------------------------------------------------------------
ARG SBT_VERSION=1.12.15
ARG SCALA_VERSION=2.13.12
ARG SPINAL_VERSION=1.14.2

#    캐시는 시스템 경로에 두고 **누구나 쓸 수 있게** 연다. 아래에서 만드는
#    비-root 사용자의 UID 가 ARG 로 정해지므로 chown 으로는 묶을 수 없고,
#    묶으면 UID 를 바꾼 사용자가 런타임에 새 의존을 못 받는다.
ENV COURSIER_CACHE=/opt/scala/coursier \
    SBT_OPTS="-Dsbt.boot.directory=/opt/scala/sbt-boot -Dsbt.ivy.home=/opt/scala/ivy -Dsbt.global.base=/opt/scala/sbt-global"

#    프라이밍 프로젝트는 의존을 캐시에 굽는 동시에 **툴체인 스모크**다 —
#    sbt 2.0.6 런처가 실제로 sbt ${SBT_VERSION} 을 부트스트랩하는지, Scala
#    컴파일러와 idsl 컴파일러 플러그인이 함께 서는지, SpinalVerilog 가 실제로
#    파일을 뱉는지까지 한 번에 판정한다. 실패하면 이미지 빌드가 죽는다 —
#    그것이 의도다. 조용히 통과하는 툴체인은 검증되지 않은 툴체인이다.
RUN pacman -S --noconfirm --needed sbt && pacman -Scc --noconfirm \
 && mkdir -p /opt/scala/coursier /opt/scala/sbt-boot /opt/scala/ivy /opt/scala/sbt-global \
 && mkdir -p /tmp/prime/project /tmp/prime/src/main/scala \
 && printf '%s\n' "sbt.version=${SBT_VERSION}" > /tmp/prime/project/build.properties \
 && printf '%s\n' \
      "ThisBuild / scalaVersion := \"${SCALA_VERSION}\"" \
      'lazy val prime = (project in file("."))' \
      '  .settings(' \
      '    libraryDependencies ++= Seq(' \
      "      \"com.github.spinalhdl\" %% \"spinalhdl-core\" % \"${SPINAL_VERSION}\"," \
      "      \"com.github.spinalhdl\" %% \"spinalhdl-lib\"  % \"${SPINAL_VERSION}\"" \
      '    ),' \
      "    addCompilerPlugin(\"com.github.spinalhdl\" %% \"spinalhdl-idsl-plugin\" % \"${SPINAL_VERSION}\")" \
      '  )' \
      > /tmp/prime/build.sbt \
 && printf '%s\n' \
      'import spinal.core._' \
      'class Prime extends Component {' \
      '  val io = new Bundle { val a = in Bool(); val b = out Bool() }' \
      '  io.b := !io.a' \
      '}' \
      'object PrimeGen extends App { SpinalVerilog(new Prime) }' \
      > /tmp/prime/src/main/scala/Prime.scala \
 && cd /tmp/prime \
 && sbt -batch "runMain PrimeGen" \
 && test -s /tmp/prime/Prime.v \
 && grep -q 'module Prime' /tmp/prime/Prime.v \
 && echo "[wt] SpinalHDL 스모크 OK — sbt ${SBT_VERSION} / scala ${SCALA_VERSION} / spinal ${SPINAL_VERSION}" \
 && cd / && rm -rf /tmp/prime \
 #  ⚠️ sbt 는 부트 서버 소켓을 `$TMPDIR/.sbt/` 에 만든다. 이 층은 root 로 도므로
 #  그대로 두면 **root 소유 디렉터리가 남아** 비-root 개발 사용자의 sbt 가
 #  AccessDeniedException 으로 죽는다 (실측). /tmp 는 1777 이라 지워 두면
 #  각 사용자가 자기 것을 만든다. TLC 가 `--userns=keep-id` 없이 states/ 를
 #  못 만들던 것과 같은 부류의 함정이다.
 && rm -rf /tmp/.sbt /tmp/hsperfdata_root \
 && chmod -R a+rwX /opt/scala

# ---------------------------------------------------------------------------
# 5) 형식 도구 보조층 (선택) — 무겁거나 별도 배포 체계라 기본에서 뺀다.
#    · SymbiYosys(sby) : yosys 기반 BMC/k-induction 프론트엔드.
#                        저장소 선례 0건이라 신규 인프라 — 도입 시 활성화.
#    · Frama-C         : opam switch 격리가 필요 (호출 규약 메모 존재)
#    · CBMC / Kani / Verus / Rocq / Isabelle
#      → Isabelle 은 **사용자 custom 설치본**이라 pacman 경로가 없다.
#        공식 번들을 받으려면 별도 층에서 명시적으로 할 것.
#    필요해지면 ARG 로 켠다. 켜지 않으면 이미지가 작게 유지된다.
# ---------------------------------------------------------------------------
#    SBY 는 이제 기본 ON 이다 — 재구현이 후-formal 단계를 실제로 밟기 때문이다.
#    (문서는 제품명을 지목하지 않는다. 2026-08-27 개정 이후로는 *방법*도
#    지목하지 않고 **요건**만 적는다 — 합성 경로 위에서 돌 것 · 반례 궤적을
#    낼 것 · 도달성 증인을 낼 것 · 판정을 세 갈래로 가를 것 · 엔진을 증거에
#    남길 것 · 덜 덮은 것을 증명됨으로 세지 말 것. sby+z3 는 그 요건을
#    만족하는 이 저장소의 선택이고, IC3/PDR 계열도 같은 요건 아래 있다.)
#
#    ⚠️ 이전 판은 `git clone --depth 1` 로 **기본 브랜치 끝**을 받았다. 그것은
#    TLA+ 층이 스스로 경고한 바로 그 패턴 — *빌드 시점이 버전을 정하는* 롤링
#    자산이다. **커밋 sha 로 고정한다.** `v0.66` 을 고른 이유는 이 스냅샷의
#    yosys 가 0.66 이기 때문이다 (sby 는 yosys 와 함께 버전이 움직인다).
#    태그가 아니라 커밋을 적는 이유: 태그는 옮길 수 있고 커밋은 옮길 수 없다.
#    ⚠️ 실측 (2026-08-20) — 이전 판은 `boolector` 를 함께 깔았는데
#    **그 패키지는 이 스냅샷에 없다** (`target not found`). `WITH_SBY=0` 이
#    기본이었으므로 이 경로는 *한 번도 실행된 적이 없었고*, 그래서 못 쓰는
#    상태로 남아 있었다. 켜자마자 드러났다 — cvc5 때와 같은 부류다.
#
#    솔버는 **z3 하나만** 둔다. 스냅샷에 yices·cvc4·cryptominisat·minisat 도
#    있지만 넣지 않는다 — 위 §2 가 yices 에 대해 세운 규율("기본값에 의존하면
#    어느 solver 로 쟀는지 증거에 안 남는다")을 sby 에도 그대로 적용한다.
#    ⇒ .sby 파일이 솔버를 **명시하지 않으면 크게 실패한다.** 그것이 의도다.
ARG WITH_SBY=1
ARG SBY_COMMIT=f57802a16613f013e84e024df50fc3f0ea74f88b
RUN if [ "${WITH_SBY}" = "1" ]; then \
      pacman -S --noconfirm --needed python-click && pacman -Scc --noconfirm && \
      git clone https://github.com/YosysHQ/sby /tmp/sby && \
      git -C /tmp/sby checkout --detach "${SBY_COMMIT}" && \
      test "$(git -C /tmp/sby rev-parse HEAD)" = "${SBY_COMMIT}" && \
      make -C /tmp/sby install && rm -rf /tmp/sby && \
      sby --help > /dev/null && echo "[wt] sby OK @ ${SBY_COMMIT}" ; \
    fi

# ---------------------------------------------------------------------------
# 6) 비-root 개발 사용자 — 호스트 UID 와 맞춰 bind mount 권한 문제를 없앤다.
# ---------------------------------------------------------------------------
ARG USERNAME=wt
ARG UID=1000
ARG GID=1000
RUN groupadd -g "${GID}" "${USERNAME}" 2>/dev/null || true \
 && useradd -m -u "${UID}" -g "${GID}" -s /bin/bash "${USERNAME}" \
 && echo "${USERNAME} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/"${USERNAME}"

USER ${USERNAME}
WORKDIR /workspace

# 도구 자기보고 — 컨테이너가 무엇을 담고 있는지 한 줄로 답하게 한다.
# 이 출력이 곧 "어느 버전으로 쟀는가" 의 답이다.
RUN printf '%s\n' \
  '#!/bin/sh' \
  'echo "=== WaveTensor 검증 환경 ==="' \
  'printf "  verilator  %s\\n" "$(verilator --version 2>&1 | head -1)"' \
  'printf "  iverilog   %s\\n" "$(iverilog -V 2>&1 | head -1)"' \
  'printf "  yosys      %s\\n" "$(yosys -V 2>&1 | head -1)"' \
  'printf "  cocotb     %s\\n" "$(cocotb-config --version 2>&1)"' \
  'printf "  z3         %s\\n" "$(z3 --version 2>&1)"' \
  '# `tlc -h` 의 첫 줄은 빈 줄이라 head -1 이 아무것도 못 잡는다 — 이 행은' \
  '# 오랫동안 공백을 보고하고 있었다. 인수 없이 부르면 첫 줄이 곧 버전이다.' \
  '# "어느 버전으로 쟀는가" 에 답하지 못하는 자기보고는 자기보고가 아니다.' \
  'printf "  TLC        %s\\n" "$(tlc 2>&1 | head -1)"' \
  'printf "  sby        %s\\n" "$(command -v sby >/dev/null 2>&1 && sby --version 2>&1 | head -1 || echo "(미설치 — WITH_SBY=0)")"' \
  'echo "  --- SpinalHDL 툴체인 (빌드 시 고정된 값) ---"' \
  'printf "  java       %s\\n" "$(java -version 2>&1 | head -1)"' \
  "printf \"  sbt        %s (런처 %s)\\\\n\" \"${SBT_VERSION}\" \"\$(sbt --script-version 2>/dev/null || echo '?')\"" \
  "echo \"  scala      ${SCALA_VERSION}\"" \
  "echo \"  SpinalHDL  ${SPINAL_VERSION}\"" \
  'echo "  Vivado     (의도적 부재 — 합성 gate 는 호스트에서 잰다)"' \
  > /home/${USERNAME}/wt-toolversions.sh \
 && chmod +x /home/${USERNAME}/wt-toolversions.sh

CMD ["/bin/bash"]
