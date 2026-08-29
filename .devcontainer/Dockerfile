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
#
# ⚠️ 알려진 예외 — **§3 의 TLA+/TLC 는 불변 좌표에 묶여 있지 않다.**
#    상류가 롤링 pre-release 하나로만 배포하기 때문이고, 불변 대안으로의
#    전환은 2026-08-29 에 실측으로 기각됐다. 전문은 §3.
#    작은 둘째 예외: §4 의 `COCOTB_PYTHON=3.13` 은 **마이너 좌표**라 uv 가
#    빌드 시점의 최신 패치로 해석한다 (실측 2026-08-29: `3.13.15` 가 깔린다).
#    나머지(ALA 날짜 · 커밋 sha · Maven/PyPI 릴리스 버전)는 불변이다.
#    이 절을 여기 두는 이유는 "재현 가능하다" 는 통짜 주장이 사실이 아니기
#    때문이다 — 어디가 아닌지 이름을 대지 못하면 그 주장은 검사할 수 없다.

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
#    ⚠️ 이 층의 핀은 **불변 아티팩트가 아니다.** 그것이 알려진 결손이고,
#    아래가 왜 그런지와 무엇을 재 봤는지의 전문이다. 재지 않은 것은 재지
#    않았다고 적는다.
#
#    ## (1) `v1.8.0` 은 버전 태그가 아니라 **롤링 pre-release** 다
#
#    GitHub API 실측 (2026-08-29): `v1.8.0` 은 `prerelease=true` 이고
#    published 2026-08-21T16:05:58Z, 자산 `tla2tools.jar` 의 updated 는
#    2026-08-21T16:04:53Z 다. 상류 README 축자 —
#
#        Currently, every commit to the master branch is built & uploaded
#        to the 1.8.0 Clarke pre-release
#
#    ⇒ **master 커밋마다 같은 태그·같은 URL 에 새 빌드가 덮인다.** 표류는
#    이상 동작이 아니라 상류가 설계한 동작이고 앞으로도 계속된다. 이 저장소가
#    두 번 겪은 핀 표류의 원인은 이것 하나다:
#
#        호스트 pacman 2.19 / 2024-08-08   2,274,532 B  (참고 — 다른 계보)
#        구 핀 `4b2313f3…` / 2026-08-11    4,486,193 B  ← 더는 받을 수 없다
#        현행  `644f4331…` / 2026-08-21    4,487,757 B  ← 지금 이 핀
#
#    ## (2) 정식 릴리스로의 다운그레이드는 **불가** (실측 2026-08-29)
#
#    최신 정식 릴리스는 `v1.7.4` (2024-08-05, prerelease=false, 2,274,532 B)
#    = **TLC 2.19** 인데, 실행하면 `-noGenerateSpecTE` 를 인식하지 못한다:
#    `Error: unrecognized option: -noGenerateSpecTE`. `rtl/formal/tla/run.sh`
#    가 358 run 전부에 그 플래그를 쓴다 (290 개가 의도된 MUST FAIL 이라 끄면
#    run 마다 TTrace 스펙 파일이 둘씩 쌓인다). ⇒ 이 경로는 닫혀 있다.
#
#    ## (3) 불변 아티팩트 전환을 시도했고 **실측으로 기각했다** (2026-08-29)
#
#    상류 README 가 가리키는 곳은 릴리스가 아니라 Maven 스냅샷 저장소
#    (`org.lamport:tla2tools:1.8.0-SNAPSHOT`) 이고, 스냅샷 자체는 가변이지만
#    **개별 빌드 파일은 타임스탬프·빌드번호가 박힌 유일 경로**다 — 실측한
#    좌표는 `1.8.0-20260821.161407-53`, 3,729,383 B,
#    b2 `1827aa31…` / sha256 `ac212fb5…`. TLC 자기보고도 GH 자산과 **같다**
#    (`TLC2 Version 2026.08.21.155922 (rev: 9787e65)`). 두 jar 의 공통 엔트리
#    1,600 개는 **CRC32 가 전부 일치**하고 Maven 쪽에만 있는 엔트리는 0 이다
#    ⇒ 같은 빌드의 다른 패키징이 맞다.
#
#    그런데 **얇은 쪽으로는 우리 워크로드가 돌지 않는다.** 두 번 잰 결과:
#
#      · 그대로: `make rtl-formal` 358 + `proofs/tla/run.sh` 16 = **374 run
#        전량 실패**, 374/374 가 같은 원인이다 —
#        `java.lang.NoClassDefFoundError: javax/mail/SendFailedException`
#        at `tlc2.TLC.main(TLC.java:333)`. 인수 파싱을 지난 모든 실행이 죽는다.
#      · POM 이 선언한 유일한 런타임 의존(`com.sun.mail:mailapi:1.6.8`)을
#        classpath 에 얹은 뒤: 모델 검사 **시작 직후** 다시 죽는다. 206 run
#        확인 후 중단했고 206/206 이 NoClassDefFoundError, 클래스명이 인쇄된
#        36 건(MUST PASS run)은 전부 `com/google/gson/JsonElement` 다.
#        **gson 은 POM 에 없다** — 즉 POM 이 실제 런타임 의존을 과소 선언한다.
#      · 대조군 — 같은 배터리를 현행 GH 지방 jar 로: **374 run 전량 정상**
#        (OK 374 / FAIL 0). ⇒ 위 실패는 패키징 때문이지 다른 무엇 때문이 아니다.
#
#    GH 지방(fat) jar 가 더 담고 있는 520 엔트리의 정체: gson(230) ·
#    com.sun.mail+javax.mail+javax.activation(233) · prettier4j(53) ·
#    javamail 리소스 2. ⇒ Maven 아티팩트는 **자립 실행 배포본이 아니다**
#    (Maven 소비자가 의존 해석으로 채우는 것을 전제한 얇은 jar 다).
#
#    ⇒ 전환하지 않는다. 이 결론은 「돌려 보니 안 되더라」가 아니라
#      **358 run 배터리 두 번**의 출력이다.
#
#    ## (4) 그래서 이 층이 사는 것 / 못 사는 것
#
#    산다 — 조용한 바꿔치기는 없다. 같은 URL 이 다른 바이트를 주면 `b2sum -c`
#    가 빌드를 **크게** 죽인다 (loud-fault-never-silent).
#    못 산다 — **재현성**. 핀이 가리키는 바이트는 다음 master 푸시와 함께
#    받을 수 없게 되고, 그때부터 정본 Dockerfile 은 **from-scratch 로 빌드
#    불가**가 된다. 구 핀 `4b2313f3…` 가 이미 그 상태였는데 오래 보이지
#    않았다 — 파생 빌드가 캐시 층을 재사용했기 때문이다. ⚠️ 캐시가 한 일을
#    정확히 적어 둔다: 캐시는 **이미지와 핀의 일치를 유지하면서**
#    from-scratch 실패만 가렸다. 어긋난 것은 이미지↔핀이 아니라 핀↔상류다.
#    (실측 2026-08-29 — 이 호스트에 남아 있는 세션 이전 이미지 넷, 08-19
#     15:43 · 08-19 15:52(`wavetensor-dev:test`) · 08-20 06:25 · 08-28 16:34
#     UTC 는 **전부** b2 `4b2313f3…` / 4,486,193 B / `TLC2 Version
#     2026.08.11.125311 (rev: 0894c34)` 를 담고 있고, 이는 그때 커밋돼 있던
#     핀과 같다. 644f4331 을 담은 이미지는 이 세션 이전에 하나도 없다.)
#    ⇒ 이 부류의 부패는 이미지를 열어 봐서는 드러나지 않는다. `--no-cache`
#      재빌드가 유일한 관측 수단이다.
#
#    ## (5) 재지 **않은** 것 (정직 기록)
#
#      · Maven 스냅샷 저장소의 보존(purge) 정책 — 재지 않았다.
#      · 얇은 jar + Maven Central 불변 릴리스(mailapi·gson·prettier4j)로
#        지방 jar 를 **재조립**했을 때 358 run 이 도는지 — 재지 않았다.
#        재조립을 하려면 gson·prettier4j 의 **버전**을 알아야 하는데, 지방
#        jar 는 shading 으로 `META-INF/maven/**` 기술자를 지운다(실측:
#        GH 전용 엔트리의 META-INF 는 javamail 리소스 둘뿐). ⇒ 아티팩트만
#        보고는 버전이 정해지지 않는다. 상류 빌드 정의를 읽어야 하고, 그것은
#        **우리가 배포본을 조립한다**는 뜻이라 별개의 정책 결정이다.
#
#    해시 계열은 저장소 전체가 **BLAKE2b-512** 로 통일돼 있다 (`b2sum` 기본값).
#    stdlib `hashlib.blake2b(digest_size=64)` 와 같은 값이며, 판정기 핀·생성물
#    출처·게이트 증거가 전부 같은 계열을 쓴다 — 계열이 섞이면 "무엇으로 쟀는가"
#    앞에 "어느 해시로?" 라는 질문이 하나 더 붙는다.
#
#    핀 넷은 **서로 다른 것을 잰다.** 해시는 바이트를, build·rev 는 그 바이트가
#    스스로 무엇이라 말하는지를 잰다. 둘을 함께 두는 이유는 재핀이 기계적
#    복붙으로 흘러가지 않게 하기 위해서다 — 해시만 갈아 끼우면 build/rev 대조가
#    죽는다. `scripts/lint_toolchain_pins.py` 가 여기 ↔ devcontainer.json 을 대조한다.
ARG TLA_VERSION=1.8.0
ARG TLA_BLAKE2B512=644f4331776049d41097c6f4540014c46acdf3c5d951f3d9778de8b1263bac9a0b2b00fa57329bc04d207d63b4b4df84fd5846493153d9149600aefef92beaa4
ARG TLA_TLC_BUILD=2026.08.21.155922
ARG TLA_TLC_REV=9787e65
RUN mkdir -p /usr/share/java \
 && curl -fsSL -o /usr/share/java/tla2tools.jar \
      "https://github.com/tlaplus/tlaplus/releases/download/v${TLA_VERSION}/tla2tools.jar" \
 && echo "${TLA_BLAKE2B512}  /usr/share/java/tla2tools.jar" | b2sum -c - \
 && printf '#!/bin/sh\nexec java -XX:+UseParallelGC -cp /usr/share/java/tla2tools.jar tlc2.TLC "$@"\n' \
      > /usr/local/bin/tlc \
 && printf '#!/bin/sh\nexec java -cp /usr/share/java/tla2tools.jar tla2sany.SANY "$@"\n' \
      > /usr/local/bin/sany \
 && chmod +x /usr/local/bin/tlc /usr/local/bin/sany \
 #  자기보고 대조 — 받은 바이트가 스스로 말하는 build/rev 가 핀과 같은가.
 && tlc 2>&1 | head -1 \
      | grep -qF "TLC2 Version ${TLA_TLC_BUILD} (rev: ${TLA_TLC_REV})" \
 #  ⚠️ **실행 스모크** — `tlc -h` 가 도는 것은 아무것도 뜻하지 않는다.
 #  2026-08-29 의 Maven 얇은 jar 실측이 정확히 그 함정이었다: 인수 없는 호출은
 #  버전을 인쇄하고 깨끗이 끝났고 `sany` 도 모든 모듈을 파싱했는데(파라미터
 #  오류 경로와 파서 경로가 MailSender 앞에서 반환한다),
 #  **실제 모델 검사는 374 run 전량이 NoClassDefFoundError 로 죽었다.**
 #  ⇒ 이 층은 진짜 모델을 하나 검사시킨다. 파싱·SANY·검사 시작·완주까지
 #  밟으므로 그 결손을 빌드 시점에 잡는다. 조용히 통과하는 툴체인은 검증되지
 #  않은 툴체인이다 (§4b SpinalHDL 스모크와 같은 규율).
 #  `-noGenerateSpecTE` 도 함께 태운다 — 러너가 358 run 전부에 쓰는 플래그이고,
 #  이것이 v1.7.4(TLC 2.19)로의 다운그레이드를 막는 바로 그 벽이다.
 && mkdir -p /tmp/tlasmoke \
 && printf '%s\n' \
      '---- MODULE Smoke ----' \
      'EXTENDS Naturals' \
      'VARIABLE x' \
      'Init == x = 0' \
      'Next == x'"'"' = (x + 1) % 3' \
      'Inv == x \in 0..2' \
      '======================' \
      > /tmp/tlasmoke/Smoke.tla \
 && printf '%s\n' 'INIT Init' 'NEXT Next' 'INVARIANT Inv' > /tmp/tlasmoke/Smoke.cfg \
 && cd /tmp/tlasmoke \
 && tlc -nowarning -workers 1 -cleanup -noGenerateSpecTE -config Smoke.cfg Smoke \
      > /tmp/tlasmoke/out.txt 2>&1 \
 && grep -q "Model checking completed. No error has been found." /tmp/tlasmoke/out.txt \
 && sany Smoke.tla > /dev/null \
 && cd / && rm -rf /tmp/tlasmoke /tmp/hsperfdata_root \
 && echo "[wt] TLC 스모크 OK — ${TLA_TLC_BUILD} (rev: ${TLA_TLC_REV}) / b2 ${TLA_BLAKE2B512}"

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
# 5b) btormc + btorsim — cover 모드를 받는 **비트 수준** 모델 체커 (sby `btor` 엔진).
#
#    왜 들어가는가 (2026-08-28 전수 실측 → 2026-08-29 사용자 승인 「권고대로 해.」):
#    DecodeWalk cover 태스크가 이 층 없이는 완주 불가였다 — cover 가용 엔진이
#    smtbmc(z3)뿐이고 z3 는 아홉 구성 전부 step 3 미완주(1800초 TIMEOUT), 같은
#    step-3 질의를 비트 수준(MiniSAT)은 5.76초에 푼다. abc 는 sby 에서 cover
#    모드를 받지 않는다(bmc3·sim3 = bmc 전용, pdr = prove 전용). 즉 결손은
#    「cover 모드를 받는 비트 수준 엔진의 부재」이고 이 층이 그 처분이다.
#    스냅샷에 boolector/btormc/bitwuzla/pono 는 없다 (pacman 실측 — §5 의
#    boolector target not found 기록과 같은 사실). Boolector 는 MIT.
#
#    구성 요소 셋을 **각각 커밋 해시로 고정해 명시로 받는다.** boolector 의
#    contrib/setup-*.sh 를 그대로 돌리면 그 스크립트가 빌드 시점에 네트워크를
#    잡는다 — 핀이 스크립트 속에 숨고, 이 파일만 읽어서는 「무엇을 받는가」에
#    답할 수 없다. 대신 그 스크립트가 *선언한* 커밋(= 상류 3.2.4 가 실제로
#    빌드한 값 — §4b 가 SpinalHDL 의 2.13.12 를 고른 것과 같은 이유)을 ARG 로
#    들어 직접 받고, 아래 grep 대조가 「ARG ↔ 상류 선언」의 일치를 빌드마다
#    다시 잰다 — boolector 만 올리면 대조가 크게 실패해 세 핀을 함께 움직이게
#    만든다. 태그가 아니라 커밋을 적는 이유는 §5 와 같다: 태그는 옮길 수 있다.
#
#    SAT 백엔드는 **lingeling 하나만** 켠다 — boolector CMake 의 기본이자 상류
#    핀이 있는 조합이다. cadical·cms·minisat·picosat 는 명시로 끈다 (§2 가
#    yices 에 세운 규율 그대로: 백엔드가 늘면 「무엇으로 쟀는가」가 흐려진다).
#
#    실측 주의 (2026-08-29 프로토타입 빌드로 확인):
#      · cmake 4.4.2 는 cmake_minimum_required < 3.5 를 거부한다 — 두 프로젝트
#        (boolector 3.3 · btor2tools 3.3) 모두 해당. CMAKE_POLICY_VERSION_MINIMUM
#        으로 하한만 선언한다 (소스 개정이 아니다).
#      · lingeling 은 `make` 전체가 아니라 **liblgl.a 만** 짓는다 — gcc 16 이
#        treengeling(병렬 프론트엔드, 소비하지 않는다)의 낡은 포인터 캐스트를
#        오류로 승격시켜 전체 빌드가 죽는다 (실측). 소비하는 것만 짓는다.
#      · btorsim 은 boolector 가 아니라 btor2tools 의 산출물이다 — sby 의 btor
#        엔진은 cover 증인 궤적 재생을 btorsim 으로 돌린다 (sby_engine_btor.py:
#        `btorsim -c --vcd … --hierarchical-symbols --info …`). 핀 커밋의
#        btorsim 이 그 플래그를 전부 받는 것을 소스에서 확인했다.
#    boolector 본체(SMT 솔버 실행 파일)는 넣지 않는다 — 승인된 결손은 cover
#    모델 체커이고, smtbmc 백엔드 솔버를 늘리는 것은 별도 처분이다.
# ---------------------------------------------------------------------------
ARG WITH_BTORMC=1
ARG BOOLECTOR_VERSION=3.2.4
ARG BOOLECTOR_COMMIT=393cdfba3735d334bb4e6525500b8a0280dd41e6
ARG BTOR2TOOLS_COMMIT=037f1fa88fb439dca6f648ad48a3463256d69d8b
ARG LINGELING_COMMIT=7d5db72420b95ab356c98ca7f7a4681ed2c59c70
RUN if [ "${WITH_BTORMC}" = "1" ]; then \
      export CMAKE_POLICY_VERSION_MINIMUM=3.5 && \
      git clone https://github.com/Boolector/boolector /tmp/boolector && \
      git -C /tmp/boolector checkout --detach "${BOOLECTOR_COMMIT}" && \
      test "$(git -C /tmp/boolector rev-parse HEAD)" = "${BOOLECTOR_COMMIT}" && \
      grep -q "^COMMIT_ID=\"${BTOR2TOOLS_COMMIT}\"\$" /tmp/boolector/contrib/setup-btor2tools.sh && \
      grep -q "^COMMIT_ID=\"${LINGELING_COMMIT}\"\$" /tmp/boolector/contrib/setup-lingeling.sh && \
      git clone https://github.com/arminbiere/lingeling /tmp/lingeling && \
      git -C /tmp/lingeling checkout --detach "${LINGELING_COMMIT}" && \
      test "$(git -C /tmp/lingeling rev-parse HEAD)" = "${LINGELING_COMMIT}" && \
      git clone https://github.com/Boolector/btor2tools /tmp/btor2tools && \
      git -C /tmp/btor2tools checkout --detach "${BTOR2TOOLS_COMMIT}" && \
      test "$(git -C /tmp/btor2tools rev-parse HEAD)" = "${BTOR2TOOLS_COMMIT}" && \
      cd /tmp/lingeling && ./configure.sh -fPIC && make -j"$(nproc)" liblgl.a && \
      cd /tmp/btor2tools && CFLAGS="-fPIC" ./configure.sh --static && make -C build -j"$(nproc)" && \
      mkdir -p /tmp/boolector/deps/install/lib /tmp/boolector/deps/install/include && \
      cp /tmp/lingeling/liblgl.a /tmp/btor2tools/build/lib/libbtor2parser.a \
         /tmp/boolector/deps/install/lib/ && \
      cp /tmp/lingeling/lglib.h /tmp/btor2tools/src/btor2parser/btor2parser.h \
         /tmp/boolector/deps/install/include/ && \
      cd /tmp/boolector && ./configure.sh --no-cadical --no-cms --no-minisat --no-picosat && \
      make -C build -j"$(nproc)" && \
      install -m 755 /tmp/boolector/build/bin/btormc /usr/local/bin/btormc && \
      install -m 755 /tmp/btor2tools/build/bin/btorsim /usr/local/bin/btorsim && \
      cd / && rm -rf /tmp/boolector /tmp/btor2tools /tmp/lingeling && \
      test "$(btormc --version)" = "${BOOLECTOR_VERSION}" && \
      btorsim -h > /dev/null && \
      echo "[wt] btormc ${BOOLECTOR_VERSION} OK @ boolector ${BOOLECTOR_COMMIT} (btor2tools ${BTOR2TOOLS_COMMIT} / lingeling ${LINGELING_COMMIT})" ; \
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
  '# TLC 의 자기보고에는 **어느 자산을 받았는지**가 없다 — `v1.8.0` 은 롤링' \
  '# pre-release 라 같은 태그가 여러 바이트를 서빙하기 때문이다. 그래서 빌드가' \
  '# 고정한 해시를 함께 적는다: 위 한 줄은 "무엇이라 말하는가", 아래 한 줄은' \
  '# "무슨 바이트였는가". 앞의 것만으로는 재현할 수 없다.' \
  "printf \"  tla2tools  v${TLA_VERSION} 자산 · b2 %s… (빌드 시 고정 · 롤링 태그)\\\\n\" \"\$(echo ${TLA_BLAKE2B512} | cut -c1-16)\"" \
  'printf "  sby        %s\\n" "$(command -v sby >/dev/null 2>&1 && sby --version 2>&1 | head -1 || echo "(미설치 — WITH_SBY=0)")"' \
  'printf "  btormc     %s\\n" "$(command -v btormc >/dev/null 2>&1 && btormc --version 2>&1 || echo "(미설치 — WITH_BTORMC=0)")"' \
  '# btorsim 에는 --version 이 없다 (핀 커밋 소스 실측) — 스스로 답하지 못하는' \
  '# 도구는 빌드가 고정한 커밋을 대신 적는다. §4b 의 「빌드 시 고정된 값」과 같은 층위다.' \
  "printf \"  btorsim    %s\\\\n\" \"\$(command -v btorsim >/dev/null 2>&1 && echo 'btor2tools @ ${BTOR2TOOLS_COMMIT} (빌드 시 고정)' || echo '(미설치 — WITH_BTORMC=0)')\"" \
  'echo "  --- SpinalHDL 툴체인 (빌드 시 고정된 값) ---"' \
  'printf "  java       %s\\n" "$(java -version 2>&1 | head -1)"' \
  "printf \"  sbt        %s (런처 %s)\\\\n\" \"${SBT_VERSION}\" \"\$(sbt --script-version 2>/dev/null || echo '?')\"" \
  "echo \"  scala      ${SCALA_VERSION}\"" \
  "echo \"  SpinalHDL  ${SPINAL_VERSION}\"" \
  'echo "  Vivado     (의도적 부재 — 합성 gate 는 호스트에서 잰다)"' \
  > /home/${USERNAME}/wt-toolversions.sh \
 && chmod +x /home/${USERNAME}/wt-toolversions.sh

CMD ["/bin/bash"]
