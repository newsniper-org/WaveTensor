#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""툴체인 핀 대조 — SpinalHDL 재구현 (정본 §6.6 「도구는 증거의 일부다」).

정본은 이렇게 적는다:

    어떤 도구의 어느 버전으로 쟀는지 답할 수 없는 검증은 검증이 아니다.
    도구 집합은 고정된 환경 정의로 관리하며, 버전 변경은 게이트 재측정과
    같은 급의 기록을 남긴다.

같은 버전이 **세 곳**에 적혀 있다. 세 곳이 필요한 이유는 서로 다른 소비자가
읽기 때문이다 —

  · `.devcontainer/Dockerfile`        ARG 기본값 (직접 `podman build` 할 때)
  · `.devcontainer/devcontainer.json` build.args (VS Code / devcontainer CLI)
  · `rtl/spinal/`                     실제 빌드 (`project/build.properties`, `build.sbt`)

⚠️ **넷째 자리가 있었다** (2026-08-30 적발). `.github/workflows/gates.yml` 이
같은 핀 여덟을 `--build-arg` 로 넘기고 있었고, `--build-arg` 는 ARG 기본값을
덮으므로 그것은 사본이 아니라 **가장 센 선언**이었다. 그런데 이 검사의
정의역에 그 파일이 없어 아무도 재지 않았고, 그 사이 `TLA_BLAKE2B512` 가 죽은
값으로 남아 있었다 — 재핀 커밋(`cdc769d`)이 세 곳 중 둘만 갱신했다.
⇒ 처분은 「대조 추가」가 아니라 **금지**다. CI 는 이 저장소의 Dockerfile 을
그대로 빌드하므로 핀 사본이 정보를 더하지 않는다. 아래 `CI_BUILD_ARGS_ALLOWED`
가 허용하는 호스트 적응 값 둘 말고는, 워크플로가 build-arg 를 넘기면 실패한다.
「세 곳」은 그러므로 관찰이 아니라 **집행되는 규범**이다.

## 보관본 ↔ 핀 (2026-09-11 등재)

선언처는 위 셋으로 닫혀 있지만, 핀 가운데 하나(`TLA_BLAKE2B512`)는 이제
**저장소 안의 내용**을 가리킨다 — `.devcontainer/vendor/tla2tools.jar`
(보관본, 사용자 판정 「landing → commit → 대기」·원장 §3 ⒜). 보관본은
*내용*이고 핀은 *그 내용의 해시*다. **둘째 선언처가 아니다** — 그런데 둘이
어긋나면 이 저장소가 `gates.yml` 에서 겪은 그 사고와 같은 모양이 된다(한쪽은
갱신되고 한쪽은 남는다). ⇒ 이 검사가 보관 jar 의 BLAKE2b-512 를 **직접 재서**
Dockerfile ARG 와 대조한다. Dockerfile 의 `b2sum -c` 도 남아 있다 — 두 그물이
같은 값을 문다(lint 는 커밋 전에, 빌드는 이미지에서).

그리고 보관본 옆의 산문(`.devcontainer/vendor/README.md`)은 **핀 값을 담지
못한다.** 착지 당일 그 문서가 128-hex 해시 전문 · TLC build/rev 를 표로 옮겨
적고 있었고(확증 결함), 그것은 lint 정의역 밖의 셋째 사본 — CI build-arg 가
그랬던 것과 같은 모양 — 이라 재핀 즉시 조용히 낡는다. 처분은 CI 축과 같은
**금지**다: 그 파일에 128-hex 나 `YYYY.MM.DD.HHMMSS` 꼴이 나오면 값이 맞아도
실패한다(V4·V5). 산문이 핀을 말하려면 선언처를 **가리켜야** 한다.

셋이 어긋나면 조용히 나쁜 일이 일어난다. 컨테이너는 어떤 버전의 의존을
이미지 층에 구워 두는데, 빌드가 다른 버전을 원하면 (a) 네트워크가 없을 때
죽거나 (b) 네트워크가 있을 때 **조용히 다른 버전을 받아 온다**. (b) 가 더
나쁘다 — 통과하는데 무엇으로 쟀는지가 달라진다.

⇒ 이 검사는 그 어긋남을 **크게** 실패시킨다. 사람 기억으로 유지되는 일치는
   일치가 아니다 (정본 부록 B.3).

## 음성 시험 — `--self-test`

이 검사의 핵심 주장은 **완전성 주장**이다("Dockerfile 의 모든 ARG 는 세 표 중
하나에 반드시 들어야 한다"). 그런 주장은 파서가 이름 하나를 못 읽는 순간
조용히 무너진다 — 못 읽은 이름은 「미등재」로 울 대상조차 되지 못하고 애초에
검사 정의역 밖이다. 2026-08-30 에 실제로 그랬다: 합법 표기 다섯이 옛 정규식을
우회했고, **그것을 잡은 것은 상주 시험이 아니라 사람의 전수 검증이었다.**
음성 시험 15종을 손으로 돌려 넷이 rc=0 인 것을 보고 고쳤는데 **그 시험은
저장소에 하나도 남지 않았다.** `--self-test` 가 그것을 상주시킨다 — 그때의
대조군 1 + 음성 9 + CI 금지 5 에, 그때 재지 않은 판정 분기 둘(읽지 못한
토큰 N6 · CI 허공 build-arg C6), 그리고 **도입 당일 전수 검증이 찾은 미덮임
일곱**(N11–N17), 그리고 보관본 착지(2026-09-11)의 다섯 — 보관본 1바이트 훼손 ·
핀만 갱신 · 보관본 부재(V1–V3) · 보관본 README 의 핀 사본 둘(V4·V5) — 을
더해 **대조군 1 + 변이 28** 이다.

    python3 scripts/lint_toolchain_pins.py --self-test

형태는 `scripts/lint_witness_map.py --self-test` 를 따른다 — 격리 사본(`/tmp`)
→ 문자열 치환 → **하위프로세스 재실행** → rc **와 문면**으로 판정. 실파일은
건드리지 않는다 (실파일을 고쳤다 되돌리는 방식은 중단되면 저장소를 더럽힌다).

규율 넷을 명시한다. 넷 다 이 저장소가 이미 데인 자리다.

  · **대조군이 먼저다** (N0). 기준 사본이 이미 실패하면 모든 변이가 엉뚱한
    이유로 울고 자기시험이 「전부 잡았다」로 초록이 된다.
  · **판정 축이 둘이다** — rc=1 **과** 기대 문면. rc 만 보면 「울긴 울었는데
    다른 이유로」가 통과로 세어지고, 그 변이가 겨냥한 분기는 조용히 정의역
    밖에 남는다 (`lint_section_refs` 가 래칫 집행 코드에서 겪은 형태).
  · **변이 지점은 손으로 박지 않는다.** 기준 파일을 파싱해 **실제 자리**에서
    고른다. 손으로 박으면 문면이 옮겨간 날 「아무것도 치환 못 함 = 변화 없음
    = 잡지 못함」으로 조용히 무효가 된다. 치환 실패는 실패다 (skip 이 아니다).
  · **0 건은 통과가 아니다.** 「안 돌면서 OK 를 인쇄」가 이 부류의 전형이다
    (`lint_guide_derived_tables` 가 도입 이래 정확히 그 상태였다). 그래서
    ⓪ 정의역 폐쇄 여섯이 변이보다 **먼저** 돈다 — 정의역 경로 하한 · CI 파서
    양성 대조 · 변이 건수 하한 · **ARG 파서 양성 대조** · **JSONC 파서 양성
    대조** · **해시 함수 양성 대조**(알려진 벡터). ⓪ 가 막는 길은 「픽스처가
    비었다 / 파서가 잴 것을 못 찾았다 / 해시가 다른 계열이다」다.

## 이 검사가 재지 **못하는** 것 — 반드시 함께 읽어라

⚠️ 도입 당시 이 절이 **없었다.** 그래서 무엇이 안 덮였는지 읽는 사람이 알
길이 없었고, docstring 은 「이 자기시험이 조용해질 수 있는 **유일한** 길」이
공허화라고 적었다. 그 문장은 좁게(공허화 갈래) 읽으면 참이지만 넓게(「검사가
퇴화해도 초록」) 읽으면 거짓이었다 — 전수 검증이 **판정 분기 일곱과 파서
보조 다섯**을 격리 사본에서 들어내도 자기시험이 초록인 것을 실측했다
(2026-08-30). 그 열둘은 지금 N11–N17 · D4 · D5 가 문다. 남는 것은 아래다.

  · **핀이 옳은지**는 재지 못한다. 이 검사는 세 선언이 **서로 같은지**만
    잰다. 셋이 나란히 틀린 값을 말하면 초록이다 — 그 축은 `--no-cache` 실
    빌드와 Dockerfile 안의 자기보고 grep 대조만 잰다 (§3).
    ⚠️ 보관본 축(2026-09-11)이 그 문장을 **한 핀에 대해서만** 좁힌다:
    `TLA_BLAKE2B512` 는 이제 저장소 안의 바이트와 대조되므로 「선언 둘과
    보관본이 나란히 틀린다」가 되려면 누군가 jar 를 바꾸고 그 해시를 두 곳에
    옮겨 적어야 한다 — 그것은 사고가 아니라 재핀이다. 그 jar 가 *돌아가는지*
    (build/rev 자기보고 · 모델 검사 스모크)는 여전히 빌드만 잰다.
  · **CI 축의 실 트리 계수에 하한이 없다.** 「CI 가 build-arg 를 하나도 안
    넘긴다」가 이 검사가 바라는 정상 상태라 계수 하한을 걸면 규범을 지킨
    저장소가 실패한다. 대신 파서를 합성으로 검증하고(D2) 실 트리 계수는
    **게이트가 아니라 대비로** 인쇄한다.
  · **`--build-arg` 말고 다른 덮어쓰기 경로**는 정의역 밖이다 — 환경 변수
    치환 · `devcontainer.json` 의 `features` · 러너 이미지에 미리 깔린 도구.
  · **중단되면 `/tmp` 에 격리 사본이 남는다.** 실측 21회(2026-08-30):
    SIGINT 는 잔여 0(파이썬이 `KeyboardInterrupt` 로 정리한다), **SIGTERM ·
    SIGKILL 은 매회 잔여 1**(`/tmp/wt-pins-neg-*`). `tempfile.
    TemporaryDirectory` 의 내재적 한계다. 저장소는 21회 전부 깨끗했다 —
    위에서 「실파일을 고쳤다 되돌리는 방식은 중단되면 저장소를 더럽힌다」고
    적은 그 대비가 여기서도 유지된다. 남는 것은 `/tmp` 뿐이고 재부팅이
    치운다.

stdlib 전용. 직접 실행 가능:  python3 scripts/lint_toolchain_pins.py
"""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

DOCKERFILE = REPO / ".devcontainer" / "Dockerfile"
DEVJSON = REPO / ".devcontainer" / "devcontainer.json"
BUILD_PROPS = REPO / "rtl" / "spinal" / "project" / "build.properties"
BUILD_SBT = REPO / "rtl" / "spinal" / "build.sbt"

# 보관본 (2026-09-11 착지). 핀 `TLA_BLAKE2B512` 가 가리키는 **내용**이다 —
# 선언이 아니다. Dockerfile 이 `COPY vendor/tla2tools.jar` 뒤에 `b2sum -c` 로
# 같은 대조를 한 번 더 한다(빌드 컨텍스트 = `.devcontainer`).
VENDOR_JAR = REPO / ".devcontainer" / "vendor" / "tla2tools.jar"
VENDOR_PIN = "TLA_BLAKE2B512"
# 보관본 옆의 산문. 핀 값 사본이 **금지**되는 파일이다 (아래 `_VENDOR_README_BAN`).
VENDOR_README = REPO / ".devcontainer" / "vendor" / "README.md"
# 금지 문양 — (이름, 정규식). 128-hex 는 BLAKE2b-512 전문, 점 넷의 숫자열은
# TLC 의 `TLA_TLC_BUILD` 꼴(`2026.09.10.191157`)이다. 짧은 rev(7-hex)는 금지하지
# 않는다 — 그 문서의 번들표가 라이선스 본문의 **출처 좌표**(`@<rev>`)로 정당하게
# 쓰고, 7-hex 는 일반 낱말과 겹쳐 오탐이 된다. 값이 아니라 *꼴*을 금지하는
# 이유는 재핀 뒤에도 옛 값이 남는 것을 잡기 위해서다 — 현행 값만 금지하면
# 낡은 사본이 바로 정의역 밖으로 빠진다.
_VENDOR_README_BAN = (
    ("128-hex 해시 전문", re.compile(r"(?<![0-9a-fA-F])[0-9a-fA-F]{128}(?![0-9a-fA-F])")),
    ("TLC build 시각 `YYYY.MM.DD.HHMMSS`", re.compile(r"(?<!\d)\d{4}\.\d{2}\.\d{2}\.\d{6}(?!\d)")),
)

# 대조할 축: (표시명, Dockerfile ARG 이름, devcontainer.json build.args 키)
PINS = [
    ("sbt", "SBT_VERSION", "SBT_VERSION"),
    ("scala", "SCALA_VERSION", "SCALA_VERSION"),
    ("SpinalHDL", "SPINAL_VERSION", "SPINAL_VERSION"),
]

# 대조할 축 2 — rtl/spinal 대응물이 **없는** 도구 핀 (두 곳만 대조).
#
# btormc 층(2026-08-29, 사용자 승인)의 핀 넷. 기준은 Dockerfile ARG 다 —
# 이미지가 실제로 굽는 값이고, devcontainer.json 이 다른 값을 넘기면 VS Code
# 재빌드가 조용히 다른 도구를 굽는다 (위 (b)와 같은 모양 — 통과하는데
# 무엇으로 쟀는지가 달라진다). 셋째 축(상류 3.2.4 가 선언한 커밋과의 일치)은
# 여기가 아니라 Dockerfile 의 grep 대조가 빌드마다 잰다 — 네트워크 없이 잴 수
# 없는 대조를 lint 에 두면 lint 가 네트워크를 잡게 된다.
PINS_TWOWAY = [
    # TLA+ / TLC (2026-08-29 등재). 이 넷은 **이전까지 대조 밖에 있었다** —
    # devcontainer.json 에 값이 적혀 있는데 아무도 Dockerfile 과 맞춰 보지
    # 않았다.
    #
    # ⚠️ 정직 기록 — 이 구멍으로 **실제 사고가 났다는 증거는 없다.** 2026-08-29
    # 에 이 호스트의 세션 이전 이미지를 전수로 재 봤더니 전부 그때 커밋돼 있던
    # 핀(`4b2313f3…`)과 일치했다. 그때의 결함은 이미지↔선언의 어긋남이 아니라
    # **핀↔상류**의 어긋남(핀이 가리키는 바이트를 더는 받을 수 없음)이었고,
    # 그것은 lint 가 아니라 `--no-cache` 빌드만 잡는다. 여기 등재하는 이유는
    # 사고가 났기 때문이 아니라 **두 선언이 어긋날 수 있는데 아무도 대조하지
    # 않고 있었기** 때문이다 — VS Code 재빌드가 조용히 다른 도구를 굽는 경로가
    # 그것이고, 그 어긋남은 여기서만 잡힌다.
    #
    # 해시와 build/rev 를 **둘 다** 든 이유: 재핀을 기계적 복붙으로 만들지
    # 않기 위해서다. 해시만 갈아 끼우면 Dockerfile 의 자기보고 대조가 빌드에서
    # 죽는다 (§3 의 `grep -qF "TLC2 Version ${TLA_TLC_BUILD} (rev: ${TLA_TLC_REV})"`).
    ("TLA+ 태그", "TLA_VERSION"),
    ("tla2tools blake2b", "TLA_BLAKE2B512"),
    ("TLC 빌드", "TLA_TLC_BUILD"),
    ("TLC rev", "TLA_TLC_REV"),
    ("btormc(Boolector)", "BOOLECTOR_VERSION"),
    ("boolector 커밋", "BOOLECTOR_COMMIT"),
    ("btor2tools 커밋", "BTOR2TOOLS_COMMIT"),
    ("lingeling 커밋", "LINGELING_COMMIT"),
    # ── 2026-08-30 등재 ────────────────────────────────────────────────────
    # 앞선 등재(2026-08-29)는 TLA+ 넷만 채웠고, **양쪽에 적혀 있는데 아무도
    # 대조하지 않는 핀이 그밖에도 넷 더 있었다.** 실측으로 세어 확인했다.
    #
    # `ALA_SNAPSHOT` 이 그중 가장 무겁다 — 이 한 줄이 verilator·yosys·z3·
    # iverilog·jdk·sbt·python 의 버전을 **전부** 정한다. 두 선언이 어긋나면
    # VS Code 재빌드가 다른 날짜의 도구 일체를 굽고, 그때 게이트는 통과하는데
    # 무엇으로 쟀는지가 달라진다 — 이 파일의 docstring 이 (b) 라 부른 바로 그
    # 실패다. 가장 무거운 핀이 가장 오래 대조 밖에 있었다.
    ("ALA 스냅샷", "ALA_SNAPSHOT"),
    ("cocotb", "COCOTB_VERSION"),
    # `COCOTB_PYTHON` · `SBY_COMMIT` 은 이때까지 **Dockerfile 에만** 있었다.
    # 등재하면서 devcontainer.json 쪽 선언을 함께 신설했다 (값을 바꾼 것이
    # 아니라 없던 선언을 만든 것이다 — 두 파일의 값은 등재 시점에 같았다).
    ("cocotb python", "COCOTB_PYTHON"),
    ("sby 커밋", "SBY_COMMIT"),
    # 층 토글. 버전은 아니지만 **무엇이 이미지에 들어 있는가**를 정하므로
    # 「어느 도구로 쟀는가」의 일부다 — `WITH_BTORMC=0` 으로 구운 이미지는
    # btor 엔진을 아예 못 돌린다. 어긋나면 크게 실패하는 축이라 (b) 부류는
    # 아니나, 두 선언이 갈라질 수 있다는 사실은 위 넷과 같다.
    ("sby 층", "WITH_SBY"),
    ("btormc 층", "WITH_BTORMC"),
]

# 대조하지 **않는** ARG 와 그 이유 — 빈칸이 아니라 판정이다.
#
# 아래 완전성 검사가 이 표를 강제한다: Dockerfile 의 ARG 는 위 세 표 중
# 하나에 반드시 들어야 하고, 새 ARG 를 추가하면 **여기 판정을 적기 전까지
# lint 가 실패한다.** 2026-08-30 이전에는 이 강제가 없었고, 그래서 핀 넷이
# 조용히 대조 밖에 머물렀다 — 사람이 등재를 기억해야 하는 구조였다는 뜻이다.
# 다음 표류를 견디는 것은 등재된 목록이 아니라 **등재를 강제하는 이 검사**다.
ARGS_NOT_COMPARED = {
    "UID": (
        "호스트 적응 값. devcontainer.json 은 `${localEnv:UID:1000}` 라는 "
        "devcontainer-CLI 변수를 넘기고 Dockerfile 기본값은 리터럴 1000 이라 "
        "**문자열 대조가 성립하지 않는다.** 둘이 다른 것이 의도다 — 호스트 "
        "UID 에 맞추는 것이 이 인자의 목적이고, .devcontainer/README.md 의 "
        "수동 실행 예도 `--build-arg UID=$(id -u)` 로 넘긴다. 재현성 축이 "
        "아니다: UID 가 달라도 잰 값은 같다."
    ),
    "GID": "위 UID 와 같다.",
    "USERNAME": (
        "도구 핀이 아니라 **신원 값**이다 — 「어느 버전으로 쟀는가」에 아무것도 "
        "기여하지 않는다. 빌드 인자로 노출할 이유가 없어 devcontainer.json 에 "
        "두지 않았고, 그 판단은 유지한다.\n"
        "        ⚠️ 다만 결합이 하나 있다는 것은 적어 둔다(실측 2026-08-30): "
        "devcontainer.json 의 `remoteUser` 가 `\"wt\"` 로 **하드코딩**돼 있어 "
        "ARG USERNAME 을 바꾸면 어긋난다. 대조를 넣지 않는 이유는 그 어긋남이 "
        "조용하지 않기 때문이다 — 없는 사용자로는 컨테이너가 서지 못하고 "
        "즉시 죽는다. 이 lint 가 막는 것은 **조용한** 어긋남이다."
    ),
}


def strip_jsonc(text: str) -> str:
    """`//` 줄 주석을 제거한다 — 문자열 안의 `//` 는 건드리지 않는다.

    devcontainer.json 은 JSONC 이고 이 저장소의 것은 주석이 많다(의도적으로 —
    그 주석들이 왜 그렇게 고정했는지의 기록이다). 순진하게 지우면
    `"https://..."` 같은 값을 깨뜨리므로 문자열 상태를 따라간다.
    """
    out = []
    in_str = False
    escaped = False
    i = 0
    while i < len(text):
        c = text[i]
        if in_str:
            out.append(c)
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
            continue
        if c == "/" and i + 1 < len(text) and text[i + 1] == "/":
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


# ── Dockerfile ARG 파서 ─────────────────────────────────────────────────────
#
# ⚠️ 이 파서는 **정규식 한 줄이었다가 실패한 자리**다. 2026-08-30 이전 판은
#
#     re.match(r"^\s*ARG\s+([A-Z_][A-Z0-9_]*)", line)
#
# 이었고, 그것은 podman/BuildKit 이 정상 처리하는 표기 넷을 **조용히 놓쳤다.**
# 실측(2026-08-30, `podman build --no-cache`, archlinux:base-devel 위)으로
# 네 표기가 전부 유효함을 확인했다 —
#
#     ARG AAA=1 BBB=2      → AAA=1 BBB=2      (한 줄 다중 ARG)
#     arg CCC=3            → CCC=3            (소문자 **명령**)
#     ARG ddd=4            → ddd=4            (소문자 **이름**)
#     ARG EEE=5 \          → EEE=5 FFF=6      (줄 이음)
#         FFF=6
#
# 그리고 옛 검사에 그 넷 중 셋(다중의 둘째 이름 · 소문자 명령 · 소문자 이름)과
# 줄 이음의 둘째 이름을 미등재로 넣어 보니 **rc=0 으로 통과했다.** 즉 「미등재
# ARG 는 실패한다」는 이 파일의 핵심 주장이 그 표기들에 대해 성립하지 않았다.
#
# 그래서 파서를 이렇게 짓는다:
#   · 줄 이음(`\`)을 먼저 접합해 **논리 줄**로 만든다.
#   · `ARG` 를 대소문자 무시로 잡는다 (Dockerfile 명령은 대소문자 무구분).
#   · 나머지를 공백으로 쪼개 `이름[=값]` 토큰을 **전부** 센다.
#   · 읽을 수 없는 토큰은 **버리지 않고 크게 실패시킨다** — 파서가 못 읽는
#     것을 조용히 지나가는 것이 애초의 결함이었다.

_ARG_INSTR = re.compile(r"^\s*ARG\s+(.*)$", re.IGNORECASE)
_ARG_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def _logical_lines(text: str) -> list[str]:
    """줄 이음(`\\`)을 접합한다. 주석 줄은 버린다.

    RUN 블록도 함께 접합되지만 상관없다 — 우리는 `ARG` 로 시작하는 논리 줄만
    본다. 이음 중간의 주석 줄은 Dockerfile 파서와 같이 건너뛴다.
    """
    out: list[str] = []
    buf = ""
    for raw in text.splitlines():
        if raw.lstrip().startswith("#"):
            continue
        stripped = raw.rstrip()
        if stripped.endswith("\\"):
            buf += stripped[:-1] + " "
            continue
        buf += stripped
        out.append(buf)
        buf = ""
    if buf:
        out.append(buf)
    return out


def _strip_trailing_comment(rest: str) -> str:
    """공백 뒤의 `#` 부터를 버린다.

    실측(2026-08-30): `ARG XX=1 # note` 를 podman 이 받아들이고 `XX=1` 을
    선언한다. 값 안의 `#`(예: `ARG X=a#b`)은 앞에 공백이 없으므로 남는다.
    """
    m = re.search(r"(?:^|\s)#", rest)
    return rest[: m.start()] if m else rest


def parse_dockerfile_args(path: Path) -> tuple[list[tuple[str, str | None]], list[str]]:
    """`[(이름, 값 또는 None)]` 과 **읽지 못한 토큰** 목록을 돌려준다.

    값이 없는 `ARG FOO` 형은 값 `None` 으로 센다 — 이름은 등재 대상이고,
    「기본값이 없다」는 사실 자체가 대조에서 뜻을 갖기 때문이다.
    """
    pairs: list[tuple[str, str | None]] = []
    unparsed: list[str] = []
    for logical in _logical_lines(path.read_text(encoding="utf-8")):
        m = _ARG_INSTR.match(logical)
        if not m:
            continue
        for tok in _strip_trailing_comment(m.group(1)).split():
            name, sep, value = tok.partition("=")
            if not _ARG_NAME.match(name):
                unparsed.append(tok)
                continue
            if sep and len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            pairs.append((name, value if sep else None))
    return pairs, unparsed


# ⚠️ 옛 판에는 `read_dockerfile_args`(값)와 `read_dockerfile_arg_names`(이름)
# **둘**이 있었고 각각 자기 정규식을 들고 있었다. 그래서 사각이 두 곳에 생겼고,
# 둘이 갈라질 수도 있었다 (실제로 옛 판은 「이름은 있는데 기본값이 없다」와
# 「이름이 아예 없다」를 구분하지 못하고 한 말로 뭉갰다).
# ⇒ 경로는 위 `parse_dockerfile_args` **하나**다. 파생 뷰가 필요하면 호출부에서
#   만든다 — 파서를 하나 더 두지 마라.


# ── CI 워크플로의 build-arg ─────────────────────────────────────────────────
#
# ⚠️ 이 축은 **실제 사고로 열렸다** (2026-08-30 적발).
#
# `--build-arg` 는 ARG 기본값을 **덮는다.** 그러므로 워크플로의 build-args
# 블록은 「참고용 사본」이 아니라 Dockerfile 보다 **센 셋째 선언처**다.
# 그런데 이 lint 의 정의역은 `.devcontainer/*` 와 `rtl/spinal/*` 넷뿐이었고
# — 이 파일의 docstring 은 지금도 「세 곳」이라 적었다 — 그 정의역 밖의
# `.github/workflows/gates.yml` 이 `TLA_BLAKE2B512` 로 **죽은 값**
# (`4b2313f3…`, 2026-08-11 자)을 넘기고 있었다. 2026-08-29 의 재핀
# (`cdc769d`)이 두 선언처는 갱신했으나 이 셋째는 몰랐다.
# ⇒ 손으로 유지되는 정의역이 뒤처진 것이다. 그래서 아래는 목록이 아니라
#   **`.github/workflows/` 순회**로 잰다 (새 워크플로도 자동으로 든다).
#
# 판정은 「대조」가 아니라 「금지」다. 대조로 두면 사람이 세 곳을 맞춰야 하고,
# 뒤처지는 것이 바로 그 구조다. 워크플로는 이 저장소의 Dockerfile 을 그대로
# 빌드하므로 핀 사본이 **정보를 하나도 더하지 않는다** — 없애면 어긋날 자리가
# 사라진다. (devcontainer.json 은 다르다: VS Code 가 Dockerfile 을 읽기 전에
# 인자를 정하는 별개 소비자라 사본이 필요하고, 그래서 저쪽은 대조한다.)
CI_WORKFLOW_DIR = REPO / ".github" / "workflows"

# CI 가 넘겨도 되는 build-arg 와 그 이유 — 빈칸이 아니라 판정이다.
CI_BUILD_ARGS_ALLOWED = {
    "UID": (
        "호스트 적응 값. GitHub 러너의 작업 사용자가 1001 이고, 컨테이너가 "
        "bind mount 로 만든 파일의 소유자가 어긋나면 뒤 step 의 "
        "`git diff --exit-code` 가 권한으로 깨진다. 재현성 축이 아니다 — "
        "UID 가 달라도 잰 값은 같다 (ARGS_NOT_COMPARED 와 같은 이유)."
    ),
    "GID": "위 UID 와 같다.",
}

_CI_BUILD_ARGS_BLOCK = re.compile(r"^(\s*)build-args:\s*(\|-?|>-?)?\s*$")
_CI_BUILD_ARG_FLAG = re.compile(r"--build-arg[=\s]+[\"']?([A-Za-z_][A-Za-z0-9_]*)")


def read_ci_build_args(path: Path) -> list[tuple[int, str]]:
    """워크플로 한 편이 빌드에 넘기는 build-arg **키**를 `(줄번호, 키)` 로.

    두 경로를 본다: `docker/build-push-action` 의 `build-args:` 블록과,
    `run:` 안에서 직접 부르는 `--build-arg`. 둘 다 ARG 기본값을 덮는다.
    YAML 파서를 쓰지 않는 이유는 이 스크립트가 **stdlib 전용**이기 때문이다
    (PyYAML 은 이 저장소의 게이트 의존이 아니다).
    """
    lines = path.read_text(encoding="utf-8").splitlines()
    found: list[tuple[int, str]] = []
    i = 0
    while i < len(lines):
        m = _CI_BUILD_ARGS_BLOCK.match(lines[i])
        if m:
            indent = len(m.group(1))
            j = i + 1
            while j < len(lines):
                cur = lines[j]
                if not cur.strip():
                    j += 1
                    continue
                if len(cur) - len(cur.lstrip()) <= indent:
                    break
                item = cur.strip()
                if item.startswith("- "):
                    item = item[2:].strip()
                key = item.split("=", 1)[0].strip().strip("\"'")
                if key:
                    found.append((j + 1, key))
                j += 1
            i = j
            continue
        for mm in _CI_BUILD_ARG_FLAG.finditer(lines[i]):
            found.append((i + 1, mm.group(1)))
        i += 1
    return found


def read_devcontainer_args(path: Path) -> dict[str, str]:
    data = json.loads(strip_jsonc(path.read_text(encoding="utf-8")))
    return dict(data.get("build", {}).get("args", {}))


def read_sbt_version(path: Path) -> str | None:
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\s*sbt\.version\s*=\s*(\S+)\s*$", line)
        if m:
            return m.group(1)
    return None


def read_build_sbt(path: Path) -> dict[str, str | None]:
    text = path.read_text(encoding="utf-8")
    scala = re.search(r'scalaVersion\s*:=\s*"([^"]+)"', text)
    spinal = re.search(r'val\s+spinalVersion\s*=\s*"([^"]+)"', text)
    return {
        "scala": scala.group(1) if scala else None,
        "spinal": spinal.group(1) if spinal else None,
    }


def main() -> int:
    problems: list[str] = []

    for p in (DOCKERFILE, DEVJSON, BUILD_PROPS, BUILD_SBT):
        if not p.exists():
            problems.append(f"파일 부재: {p.relative_to(REPO)}")
    if problems:
        for p in problems:
            print(f"lint_toolchain_pins: FAIL — {p}", file=sys.stderr)
        return 1

    df_pairs, df_unparsed = parse_dockerfile_args(DOCKERFILE)
    # 파서가 못 읽은 토큰은 **버리지 않는다.** 조용히 버리는 것이 이 검사가
    # 2026-08-30 까지 앓던 결함 그 자체다 — 못 읽으면 등재 여부를 잴 수 없고,
    # 잴 수 없는 것을 통과로 인쇄하면 안 된다.
    for tok in df_unparsed:
        problems.append(
            f"읽지 못한 ARG 토큰: Dockerfile 의 `{tok}` — 이 검사가 그 이름을 "
            f"셀 수 없으므로 등재 여부를 판정할 수 없다. 표기를 고치거나 "
            f"파서를 고쳐라 (통과시키지 마라)"
        )
    df = dict(df_pairs)
    df_names = [n for n, _ in df_pairs]
    df_names_set = set(df_names)
    dj = read_devcontainer_args(DEVJSON)
    sbt_actual = read_sbt_version(BUILD_PROPS)
    sbt_build = read_build_sbt(BUILD_SBT)

    # 실제 빌드가 말하는 값 — 이것이 기준이다. 컨테이너는 여기에 맞춰 굽는다.
    actual = {
        "SBT_VERSION": sbt_actual,
        "SCALA_VERSION": sbt_build["scala"],
        "SPINAL_VERSION": sbt_build["spinal"],
    }

    rows = []
    for label, df_key, dj_key in PINS:
        a = actual[df_key]
        d = df.get(df_key)
        j = dj.get(dj_key)
        if a is None:
            problems.append(f"{label}: rtl/spinal 쪽에서 버전을 읽지 못했다")
            continue
        if d is None:
            problems.append(f"{label}: Dockerfile 에 ARG {df_key} 가 없다")
        elif d != a:
            problems.append(
                f"{label}: Dockerfile ARG {df_key}={d} ≠ rtl/spinal 의 {a}"
            )
        if j is None:
            problems.append(f"{label}: devcontainer.json build.args 에 {dj_key} 가 없다")
        elif j != a:
            problems.append(
                f"{label}: devcontainer.json {dj_key}={j} ≠ rtl/spinal 의 {a}"
            )
        rows.append((label, a))

    for label, key in PINS_TWOWAY:
        d = df.get(key)
        j = dj.get(key)
        if key not in df_names_set:
            problems.append(f"{label}: Dockerfile 에 ARG {key} 가 없다")
        elif d is None:
            # 이름은 있는데 `=값` 이 없다. 옛 파서는 이 둘을 구분하지 못했고
            # 「없다」로 뭉뚱그렸다 — 다른 결함이므로 다른 말로 적는다.
            problems.append(
                f"{label}: Dockerfile 의 ARG {key} 에 기본값이 없다 — "
                f"직접 `podman build` 하면 빈 값으로 굽는다"
            )
        if j is None:
            problems.append(f"{label}: devcontainer.json build.args 에 {key} 가 없다")
        elif d is not None and j != d:
            problems.append(
                f"{label}: devcontainer.json {key}={j} ≠ Dockerfile ARG 의 {d}"
            )
        if d is not None:
            # 커밋 해시는 OK 줄을 읽을 수 없게 만든다 — 표시만 줄인다 (대조는 전폭).
            rows.append((label, d if len(d) <= 12 else d[:12] + "…"))

    # ── 보관본 ↔ 핀 ───────────────────────────────────────────────────────
    # 핀은 해시이고 보관본은 그 해시가 가리키는 바이트다. 여기서 바이트를
    # **직접 재서** Dockerfile ARG 와 대조한다. 어느 쪽이 참인지는 이 검사가
    # 정하지 못한다 — 어긋났다는 사실만 크게 인쇄한다. devcontainer.json 쪽은
    # 위 PINS_TWOWAY 가 Dockerfile 과 맞추므로 여기서 다시 재지 않는다.
    vendor_rel = VENDOR_JAR.relative_to(REPO)
    pin_df = df.get(VENDOR_PIN)
    if not VENDOR_JAR.is_file():
        problems.append(
            f"보관본 부재: {vendor_rel} 가 없다 — 핀 {VENDOR_PIN} 이 가리키는 "
            f"내용을 이쪽이 보관하지 않으면 환경 정의는 처음부터 다시 지을 수 "
            f"없다 (정본 §6.6.2: 내용 고정은 필요조건, 보관이 충분조건). "
            f"Dockerfile 의 COPY 도 이 파일이 없으면 죽는다"
        )
    else:
        h = hashlib.blake2b(digest_size=64)
        with VENDOR_JAR.open("rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
        vendor_b2 = h.hexdigest()
        vendor_size = VENDOR_JAR.stat().st_size
        if pin_df is not None and vendor_b2 != pin_df:
            problems.append(
                f"보관본 ≠ 핀: {vendor_rel} 의 blake2b {vendor_b2[:12]}… "
                f"({vendor_size:,} B) ≠ Dockerfile ARG {VENDOR_PIN} "
                f"{pin_df[:12]}… — 보관본은 내용이고 핀은 그 내용의 해시다. "
                f"둘 중 어느 쪽이 참인지 이 검사는 정하지 못한다. 재핀이면 "
                f"보관본 교체 + 핀 넷(Dockerfile · devcontainer.json)을 "
                f"**함께** 갱신하라; 아니면 어느 쪽이 조용히 바뀐 것이다"
            )
        elif pin_df is not None:
            rows.append(("보관본", f"{vendor_size:,} B b2 {vendor_b2[:12]}…"))

    # ── 보관본 README 의 핀 사본 금지 ──────────────────────────────────────
    # 정의역 파일이 없으면 「잴 것이 없었다」이지 통과가 아니다 — 보관본이
    # 있는데 그 옆의 산문(라이선스 실측·재핀 절차)이 없으면 그것도 결손이다.
    readme_rel = VENDOR_README.relative_to(REPO)
    if not VENDOR_README.is_file():
        problems.append(
            f"보관본 README 부재: {readme_rel} 가 없다 — 보관본의 번들 구성·"
            f"라이선스 실측과 재핀 절차가 사는 자리다"
        )
    else:
        for lineno, line in enumerate(
                VENDOR_README.read_text(encoding="utf-8").splitlines(), 1):
            for what, rx in _VENDOR_README_BAN:
                m = rx.search(line)
                if m:
                    problems.append(
                        f"보관본 README 가 핀을 재선언한다: {readme_rel}:{lineno} 에 "
                        f"{what} `{m.group(0)[:12]}…` — 이 파일은 lint 가 대조하지 "
                        f"않는 셋째 사본이라 재핀 즉시 조용히 낡는다. 값을 맞춰 "
                        f"적어도 실패한다. 지우고 선언처(Dockerfile ARG · "
                        f"devcontainer.json)를 **가리켜라**"
                    )

    # ── 완전성 ────────────────────────────────────────────────────────────
    # 위의 표들은 **손으로 유지되는 목록**이고, 손으로 유지되는 목록은 반드시
    # 뒤처진다 (실측: 2026-08-30 에 세어 보니 양쪽에 적혀 있으면서 대조 밖인
    # 핀이 넷, 한쪽에만 있는 것이 둘 있었다). 아래 두 검사가 그 뒤처짐을
    # 구조로 막는다 — 목록을 늘리는 것이 아니라 **누락이 실패가 되게** 한다.
    covered = (
        {k for _, k, _ in PINS}
        | {k for _, k in PINS_TWOWAY}
        | set(ARGS_NOT_COMPARED)
    )

    # (1) Dockerfile 의 모든 ARG 는 대조되거나, 대조하지 않는 이유가 적혀야 한다.
    seen: set[str] = set()
    for name in df_names:
        if name in seen:
            continue
        seen.add(name)
        if name not in covered:
            problems.append(
                f"미등재 ARG: Dockerfile 의 `{name}` 이 어느 표에도 없다 — "
                f"대조 대상이면 PINS/PINS_TWOWAY 에, 아니면 그 **이유와 함께** "
                f"ARGS_NOT_COMPARED 에 넣어라"
            )

    # (2) 거꾸로 — devcontainer.json 이 Dockerfile 에 없는 인자를 넘기면
    #     빌드는 그것을 **조용히 무시한다** (podman/BuildKit 둘 다). 오타 하나로
    #     핀이 통째로 무력해지는데 아무 신호가 없다. 여기서 크게 실패시킨다.
    for key in dj:
        if key not in df_names_set:
            problems.append(
                f"허공 build.arg: devcontainer.json 의 `{key}` 에 대응하는 "
                f"ARG 가 Dockerfile 에 없다 — 빌드가 조용히 무시한다"
            )

    # (3) CI 워크플로 — **셋째 선언처를 금지한다.** 정의역은 손 목록이 아니라
    #     `.github/workflows/` 순회다 (새 워크플로가 조용히 새는 것을 막는다).
    if CI_WORKFLOW_DIR.is_dir():
        wf_paths = sorted(
            p
            for p in CI_WORKFLOW_DIR.rglob("*")
            if p.suffix in (".yml", ".yaml") and p.is_file()
        )
        if not wf_paths:
            # 워크플로가 하나도 없으면 이 검사는 아무것도 재지 않는다. 그
            # 사실을 통과로 인쇄하지 않는다 — 「덮었다」와 「잴 것이 없었다」는
            # 다르다. (디렉터리 자체가 없으면 CI 가 없는 것이라 조용히 넘긴다.)
            problems.append(
                f"{CI_WORKFLOW_DIR.relative_to(REPO)} 에 워크플로가 없다 — "
                f"CI build-arg 검사가 잰 것이 0 이다. 정의역을 확인하라"
            )
        for wf in wf_paths:
            rel = wf.relative_to(REPO)
            for lineno, key in read_ci_build_args(wf):
                if key not in CI_BUILD_ARGS_ALLOWED:
                    problems.append(
                        f"CI 가 핀을 재선언한다: {rel}:{lineno} 의 build-arg "
                        f"`{key}` — `--build-arg` 는 Dockerfile ARG 기본값을 "
                        f"**덮는다**. CI 는 이 저장소의 Dockerfile 을 그대로 "
                        f"빌드하므로 사본이 정보를 더하지 않고, 어긋날 자리만 "
                        f"만든다 (2026-08-30: 그 자리에서 죽은 TLA 해시가 "
                        f"나왔다). 지워라 — 값을 갱신하는 것이 아니다. "
                        f"호스트 적응 값이면 CI_BUILD_ARGS_ALLOWED 에 **이유와 "
                        f"함께** 넣어라"
                    )
                elif key not in df_names_set:
                    problems.append(
                        f"허공 build-arg: {rel}:{lineno} 의 `{key}` 에 대응하는 "
                        f"ARG 가 Dockerfile 에 없다 — 빌드가 조용히 무시한다"
                    )

    if problems:
        print("lint_toolchain_pins: FAIL — 툴체인 핀이 어긋났다", file=sys.stderr)
        for p in problems:
            print(f"  · {p}", file=sys.stderr)
        print(
            "\n  세 곳이 같은 값을 말해야 한다:\n"
            "    .devcontainer/Dockerfile          (ARG 기본값)\n"
            "    .devcontainer/devcontainer.json   (build.args)\n"
            "    rtl/spinal/{project/build.properties, build.sbt}   ← 기준\n"
            "\n  그리고 **넷째는 없다**: .github/workflows/ 는 핀을 build-arg 로\n"
            "  넘기지 않는다 (UID/GID 만 예외). --build-arg 는 ARG 기본값을 덮으므로\n"
            "  그 사본이 가장 센 선언이 되고, 2026-08-30 에 그 자리에서 죽은 TLA\n"
            "  해시가 나왔다. 값을 맞춰 적어도 실패한다 — 사본을 지워라.\n"
            "\n  보관본은 선언이 아니라 **내용**이다:\n"
            "    .devcontainer/vendor/tla2tools.jar   blake2b == TLA_BLAKE2B512\n"
            "  어긋나면 재핀은 보관본 교체 + 핀 둘 갱신을 **함께** 한다.\n"
            "  그 옆의 vendor/README.md 는 핀 값을 담지 않는다 — 셋째 사본 금지.\n"
            "\n  어긋난 채로 두면 컨테이너가 구운 캐시와 빌드가 원하는 버전이\n"
            "  달라진다. 네트워크가 있으면 조용히 다른 버전을 받아 온다 —\n"
            "  통과하는데 무엇으로 쟀는지가 달라지는 것이 가장 나쁘다.",
            file=sys.stderr,
        )
        return 1

    print("lint_toolchain_pins: OK — " + " / ".join(f"{k} {v}" for k, v in rows))
    return 0


# ═══════════════════════════════════════════════════════════════════════════
# 음성 시험 — 격리 사본에서 변이 28종이 실제로 잡히는지 (도입 시 16, 이후 확장)
#
# 왜 검사 파일 **안**인가: 이 저장소의 선례 다섯이 전부 안이고 lint 를 겨냥한
# 별도 시험 파일은 0건이다. 안에 두면 (a) 표기를 넓힐 때 변이도 같은 커밋에서
# 함께 움직이고 — 2026-08-30 사건이 정확히 「검사만 고치고 시험은 남지 않은」
# 형태였다 — (b) 배포 단위가 하나로 남는다(stdlib 전용). 밖에 두면 시험 파일이
# 「호출되지 않는 파일」이 되기 쉽고, 그것이 이 저장소의 실패형 그 자체다.
# ═══════════════════════════════════════════════════════════════════════════

# 손-유지 **하한**이다. 손-유지 *정의역*(목록)은 금지지만 하한은 허용된다 —
# 방향이 반대이기 때문이다: 목록에서 빠뜨리면 침묵이고, 하한에서 빠뜨리면
# 곧 실패다 (`lint_section_refs` ⑭ 가 적은 그대로).
_MIN_DOMAIN_PATHS = 6
_MIN_MUTATIONS = 28
_MIN_ARG_PROBE = 10

_SELF_TEST_TAG = "WT_SELFTEST"

# ── 파서 양성 대조의 정답표 ─────────────────────────────────────────────────
#
# ⚠️ 왜 변이가 아니라 **양성 대조**인가. 파서 보조 함수의 퇴화는 대개
# 「판정이 뒤집힌다」가 아니라 「같은 문면을 **다른 경로로** 얻는다」로
# 나타나서 rc·문면 축에 안 걸린다. 실측(2026-08-30): `_strip_trailing_comment`
# 를 `return rest` 로 무력화해도 N5 가 초록이었다 — 꼬리 주석의 `#` 가 「읽지
# 못한 토큰」 경로로 흘러 기대 문면이 여전히 나왔기 때문이다. 반대로 값 안의
# `#` 까지 자르는 **과잉** 변경도 초록이었다(핀 값이 조용히 절단되는데 이름은
# 그대로라 아무도 울지 않는다). 그런 부류는 함수의 **출력 전체**를 정답표와
# 대조해야 잡힌다.
#
# 정답표는 추측이 아니라 실측이다 — podman 5.8.2 / archlinux:base-devel 위에서
# 아래 표기를 전부 빌드해 `RUN printf` 로 확인했다 (2026-08-30):
#
#   A=[1] B=[2] H=[a#b] QT=[vw] NOVAL=[] LOWCMD=[5] lowname=[6] TAILC=[7]
#
# 즉 한 줄 다중 · 소문자 명령 · 소문자 이름 · **이음 중간의 주석 줄** ·
# 꼬리 주석 · 값 안의 `#` · 따옴표 벗기기 · 값 없는 ARG 가 전부 확인된 표기다.
_ARG_PROBE_DF = (
    "FROM scratch\n"
    "# 주석 줄의 ARG COMMENTED=0 은 선언이 아니다\n"
    "ARG A=1 B=2\n"
    "arg LOWCMD=5\n"
    "ARG lowname=6\n"
    "ARG CONT=8 \\\n"
    "# 이음 중간의 주석 줄 — Dockerfile 파서는 건너뛴다\n"
    "    CONT2=9\n"
    "ARG TAILC=7  # 꼬리 주석\n"
    "ARG HASHVAL=a#b\n"
    "ARG QUOTED=\"vw\"\n"
    "ARG NOVAL\n"
    "RUN echo hi\n"
)
_ARG_PROBE_WANT = [
    ("A", "1"), ("B", "2"), ("LOWCMD", "5"), ("lowname", "6"),
    ("CONT", "8"), ("CONT2", "9"), ("TAILC", "7"),
    ("HASHVAL", "a#b"), ("QUOTED", "vw"), ("NOVAL", None),
]

# `strip_jsonc` 는 문자열 상태를 따라가야 한다. 추적을 지우면 `"https://…"` 의
# `//` 가 주석으로 잘려 JSON 이 깨지는데, 실측으로는 **초록이었다** — 변이가
# 없었기 때문이다.
_JSONC_PROBE = (
    "{\n"
    "  // 줄 주석\n"
    '  "url": "https://example.invalid/a//b",\n'
    '  "esc": "he said \\"//\\" here",  // 꼬리 주석\n'
    '  "n": 1\n'
    "}\n"
)
_JSONC_WANT = {
    "url": "https://example.invalid/a//b",
    "esc": 'he said "//" here',
    "n": 1,
}


# BLAKE2b-512 의 빈 입력 벡터(RFC 7693 부록 A 계열; `b2sum </dev/null` 과 같다).
# 해시 계열이 조용히 바뀌면(digest_size · 알고리즘) 변이 V1–V3 이 「다른
# 이유로」 울기 전에 여기서 이름을 갖고 죽는다.
_B2_EMPTY = (
    "786a02f742015903c6c6fd852552d272912f4740e15847618a86e217f71f5419"
    "d25e1031afee585313896444934eb04b903a685b1448b755d56f701afe9be2ce"
)


class _MutationMiss(RuntimeError):
    """변이 지점을 찾지 못했다 — **skip 이 아니라 실패다.**

    치환할 문면이 사라지면 그 변이는 「파일을 바꾸지 않고 재실행」이 되고,
    통과하는 검사는 당연히 통과한다. 조용히 무효가 되는 시험이 없는 시험보다
    나쁘다 (그것이 초록을 인쇄하기 때문).
    """


def _domain_paths() -> list[Path]:
    """이 검사가 읽는 **정의역 경로 전부**를 모듈 상수에서 뽑는다.

    픽스처를 이 결과로 지으면 정의역이 늘 때 픽스처가 자동으로 따라온다 —
    손으로 유지되는 픽스처 목록은 반드시 뒤처지고, 뒤처진 픽스처에서는
    새 축이 「파일 부재」로 엉뚱하게 울거나(운이 좋을 때) 아예 안 돈다.
    """
    out: list[Path] = []
    for name, val in sorted(globals().items()):
        if name == "REPO" or name.startswith("_") or not isinstance(val, Path):
            continue
        try:
            val.relative_to(REPO)
        except ValueError:
            continue
        out.append(val)
    return out


def _build_fixture(root: Path) -> Path:
    """정의역 경로만 담은 격리 사본을 짓는다. 실파일은 건드리지 않는다."""
    me = Path(__file__).resolve()
    base = root / "repo"
    (base / "scripts").mkdir(parents=True, exist_ok=True)
    shutil.copy2(me, base / "scripts" / me.name)
    for p in _domain_paths():
        tgt = base / p.relative_to(REPO)
        tgt.parent.mkdir(parents=True, exist_ok=True)
        if p.is_dir():
            shutil.copytree(
                p, tgt, symlinks=True,
                ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
            )
        elif p.is_file():
            shutil.copy2(p, tgt)
        else:
            raise _MutationMiss(f"정의역 경로가 실재하지 않는다: {p}")
    return base


def _run_fixture(base: Path) -> tuple[int, str]:
    me = Path(__file__).resolve().name
    r = subprocess.run(
        [sys.executable, str(base / "scripts" / me)],
        capture_output=True, text=True,
    )
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def _sub(path: Path, before: str, after: str) -> None:
    text = path.read_text(encoding="utf-8")
    if before not in text:
        raise _MutationMiss(f"{path.name}: 변이 지점 부재 — /{before[:64]}/")
    path.write_text(text.replace(before, after, 1), encoding="utf-8")


def _append(path: Path, extra: str) -> None:
    path.write_text(path.read_text(encoding="utf-8") + extra, encoding="utf-8")


_SIMPLE_ARG_LINE = re.compile(r"^ARG\s+([A-Za-z_][A-Za-z0-9_]*)=(\S+)\s*$")


def _arg_line(text: str, name: str | None = None) -> str:
    """`ARG NAME=VALUE` 꼴 **실제 줄**을 돌려준다 (name 이 None 이면 첫 줄).

    변이의 닻을 여기서 얻는다 — 리터럴을 이 파일에 박아 두지 않기 위해서다.
    """
    for raw in text.splitlines():
        m = _SIMPLE_ARG_LINE.match(raw)
        if m and (name is None or m.group(1) == name):
            return raw
    raise _MutationMiss(f"`ARG {name or '<첫>'}=…` 꼴 줄을 찾지 못했다")


_SYNTH_WORKFLOW = (
    "name: wt-selftest\n"
    "on: workflow_dispatch\n"
    "jobs:\n"
    "  x:\n"
    "    runs-on: ubuntu-latest\n"
    "    steps:\n"
    "      - uses: docker/build-push-action@v6\n"
    "        with:\n"
    "          build-args: |\n"
    "            {block_key}={block_val}\n"
    "      - run: docker build --build-arg {flag_key}={flag_val} .\n"
    "      - run: docker build --build-arg={eq_key}={eq_val} .\n"
)


def _mutations() -> list[tuple]:
    """`(번호, 설명, 적용함수, 기대 문면들[, 금지 문면들])`.

    다섯째 칸은 **선택**이고 「이 문면이 나오면 겨냥한 분기가 아니라 다른
    분기가 운 것」을 뜻한다 (N5 참조).

    닻과 기댓값은 **기준 파일을 파싱해서** 만든다. 리터럴을 박으면 값이 바뀐
    날 조용히 무효가 된다.
    """
    df_text = DOCKERFILE.read_text(encoding="utf-8")
    dj_text = DEVJSON.read_text(encoding="utf-8")
    df = dict(parse_dockerfile_args(DOCKERFILE)[0])
    dj = read_devcontainer_args(DEVJSON)
    anchor = _arg_line(df_text)

    # ── 닻 넷을 기준 파일에서 고른다 ────────────────────────────────────────
    # 값 대조 축(PINS): rtl/spinal 이 기준인 핀 하나.
    pin_key = PINS[0][1]
    pin_val = df.get(pin_key)
    if pin_val is None:
        raise _MutationMiss(f"Dockerfile 에 ARG {pin_key} 기본값이 없다")

    # 두-선언 대조 축(PINS_TWOWAY): 양쪽에 리터럴로 적힌 첫 핀.
    two_key = two_val = two_label = None
    for _lbl, k in PINS_TWOWAY:
        if k in df and dj.get(k) == df[k] and f'"{k}": "{df[k]}"' in dj_text:
            two_key, two_val, two_label = k, df[k], _lbl
            break
    if two_key is None:
        raise _MutationMiss("PINS_TWOWAY 중 양쪽에 리터럴로 적힌 핀이 없다")

    # 기본값 제거 축: `ARG K=V` 단순 줄을 가진 첫 두-선언 핀.
    nodef_key = nodef_label = None
    for _lbl, k in PINS_TWOWAY:
        if k in df and f"ARG {k}={df[k]}" in df_text:
            nodef_key, nodef_label = k, _lbl
            break
    if nodef_key is None:
        raise _MutationMiss("`ARG K=V` 단순 줄을 가진 두-선언 핀이 없다")
    nodef_line = _arg_line(df_text, nodef_key)

    # ── N11–N17 의 닻 ───────────────────────────────────────────────────────
    # 아래 일곱은 **판정 분기 일곱**을 각각 격리한다. 도입 당일 전수 검증이
    # 이 일곱을 격리 사본에서 통째로 들어내도 본 검사 rc=0 · 자기시험 rc=0 인
    # 것을 실측했다 (2026-08-30). 가장 무거웠던 것은 `elif j != a` —
    # devcontainer.json 이 rtl/spinal 과 어긋나도 아무도 울지 않게 검사를
    # 퇴화시켜도 초록이었고, 바로 옆의 `elif d != a` 는 N7 이 물고 있었다.
    # **나란한 두 분기 중 하나만 덮여 있었다**는 것이 이 부류의 얼굴이다.
    pin_label = PINS[0][0]
    pin_dj_key = PINS[0][2]
    pin_dj_decl = f'"{pin_dj_key}": "{dj.get(pin_dj_key)}"'
    if pin_dj_decl + "," not in dj_text:
        raise _MutationMiss(f"devcontainer.json 에 `{pin_dj_decl},` 가 없다")
    pin_arg_line = _arg_line(df_text, pin_key)

    two_decl = f'"{two_key}": "{two_val}"'
    if two_decl + "," not in dj_text:
        raise _MutationMiss(f"devcontainer.json 에 `{two_decl},` 가 없다")

    # rtl/spinal 기준값을 읽는 줄 — 주석이 아니라 **실 선언 줄**이어야 한다.
    props_line = next(
        (ln for ln in BUILD_PROPS.read_text(encoding="utf-8").splitlines()
         if re.match(r"^\s*sbt\.version\s*=\s*(\S+)\s*$", ln)), None)
    if props_line is None:
        raise _MutationMiss("build.properties 에 `sbt.version=` 줄이 없다")

    # CI 허용 축: CI 가 넘겨도 되는 인자 중 Dockerfile 에 ARG 로 있는 첫 것.
    ci_key = None
    for k in sorted(CI_BUILD_ARGS_ALLOWED):
        if k in df and f"ARG {k}={df[k]}" in df_text:
            ci_key = k
            break
    if ci_key is None:
        raise _MutationMiss("CI_BUILD_ARGS_ALLOWED 중 Dockerfile ARG 인 것이 없다")
    ci_line = _arg_line(df_text, ci_key)

    real_wf = sorted(
        p.relative_to(REPO)
        for p in CI_WORKFLOW_DIR.rglob("*")
        if p.suffix in (".yml", ".yaml") and p.is_file()
    )
    if not real_wf:
        raise _MutationMiss(".github/workflows 에 워크플로가 없다 — C1 이 잴 것이 없다")
    wf0 = real_wf[0]

    def df_of(base: Path) -> Path:
        return base / DOCKERFILE.relative_to(REPO)

    def dj_of(base: Path) -> Path:
        return base / DEVJSON.relative_to(REPO)

    def wf_dir(base: Path) -> Path:
        return base / CI_WORKFLOW_DIR.relative_to(REPO)

    def bp_of(base: Path) -> Path:
        return base / BUILD_PROPS.relative_to(REPO)

    def jar_of(base: Path) -> Path:
        return base / VENDOR_JAR.relative_to(REPO)

    def readme_of(base: Path) -> Path:
        return base / VENDOR_README.relative_to(REPO)

    # ── V1–V3 의 닻 — 보관본 핀은 양쪽에 **리터럴**로 적혀 있어야 한다. ─────
    vpin = df.get(VENDOR_PIN)
    if vpin is None or len(vpin) != 128:
        raise _MutationMiss(f"Dockerfile 의 ARG {VENDOR_PIN} 이 128-hex 가 아니다")
    vpin_df_line = f"ARG {VENDOR_PIN}={vpin}"
    vpin_dj_decl = f'"{VENDOR_PIN}": "{vpin}"'
    if vpin_df_line not in df_text or vpin_dj_decl not in dj_text:
        raise _MutationMiss(f"{VENDOR_PIN} 이 양쪽에 리터럴로 적혀 있지 않다")
    vpin_other = ("1" if vpin[0] != "1" else "2") + vpin[1:]

    def _corrupt_jar(b: Path) -> None:
        # 마지막 1바이트를 뒤집는다 — 크기는 같고 내용만 다르다. 「크기가
        # 같으면 같은 파일」로 퇴화한 검사는 여기서 초록이 된다.
        f = jar_of(b)
        data = bytearray(f.read_bytes())
        if not data:
            raise _MutationMiss(f"{f.name} 이 비어 있다 — 훼손할 바이트가 없다")
        data[-1] ^= 0xFF
        f.write_bytes(bytes(data))

    def _repin_only(b: Path) -> None:
        # 핀 둘을 **일관되게** 다른 값으로 — 두-선언 대조(N8)는 조용하고
        # 보관본 대조만 울어야 한다. 이것이 「셋째 선언처」 형태의 사고다:
        # 선언은 갱신됐는데 내용이 안 따라왔다.
        _sub(df_of(b), vpin_df_line, f"ARG {VENDOR_PIN}={vpin_other}")
        _sub(dj_of(b), vpin_dj_decl, f'"{VENDOR_PIN}": "{vpin_other}"')

    def _drop_jar(b: Path) -> None:
        jar_of(b).unlink()

    # V4·V5 — 산문에 **현행 값 그대로** 붙인다. 값이 맞아도 실패해야 한다
    # (CI 축의 C1 과 같은 판정: 대조가 아니라 금지). 닻은 기준 파일에서 읽은
    # 핀이다 — 리터럴을 박지 않는다.
    build_val = df.get("TLA_TLC_BUILD")
    if build_val is None or not re.fullmatch(r"\d{4}\.\d{2}\.\d{2}\.\d{6}", build_val):
        raise _MutationMiss("Dockerfile 의 ARG TLA_TLC_BUILD 가 `YYYY.MM.DD.HHMMSS` 꼴이 아니다")

    def _readme_hash_copy(b: Path) -> None:
        _append(readme_of(b), f"\n| BLAKE2b-512 | `{vpin}` |\n")

    def _readme_build_copy(b: Path) -> None:
        _append(readme_of(b), f"\n| 자기보고 | `TLC2 Version {build_val}` |\n")

    def _insert_arg(text_after: str):
        return lambda b: _sub(df_of(b), anchor, anchor + text_after)

    def _new_workflow(rel: str, keys: dict[str, str]):
        def apply(b: Path) -> None:
            f = wf_dir(b) / rel
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_text(_SYNTH_WORKFLOW.format(**keys), encoding="utf-8")
        return apply

    def _drop_workflows(b: Path) -> None:
        for p in sorted(wf_dir(b).rglob("*")):
            if p.suffix in (".yml", ".yaml") and p.is_file():
                p.unlink()

    def _ci_block(b: Path) -> None:
        # 실 워크플로 파일이 정의역 안에 있는가 — 그리고 **값이 정확해도**
        # 실패하는가. (이 축의 판정은 「대조」가 아니라 「금지」다.)
        _append(
            b / wf0,
            "\n# wt-selftest\nzz:\n  build-args: |\n"
            f"    {two_key}={two_val}\n",
        )

    unreadable = f"9{_SELF_TEST_TAG}_N6=1"

    return [
        # ── N1–N5 : 표기 다섯. 2026-08-30 에 이 다섯이 옛 파서를 우회했고
        #            podman 실 빌드로 다섯이 전부 유효 표기임이 확인됐다.
        #            각각 **미등재 ARG 를 그 표기로 심고** 검사가 그 이름을
        #            읽어 내는지를 잰다.
        ("N1", "한 줄 다중 `ARG A=1 B=2` 의 둘째 이름",
         _insert_arg(f" {_SELF_TEST_TAG}_N1=1"),
         (f"미등재 ARG: Dockerfile 의 `{_SELF_TEST_TAG}_N1`",)),
        ("N2", "소문자 **명령** `arg`",
         _insert_arg(f"\narg {_SELF_TEST_TAG}_N2=1"),
         (f"미등재 ARG: Dockerfile 의 `{_SELF_TEST_TAG}_N2`",)),
        ("N3", "소문자 **이름**",
         _insert_arg(f"\nARG {_SELF_TEST_TAG.lower()}_n3=1"),
         (f"미등재 ARG: Dockerfile 의 `{_SELF_TEST_TAG.lower()}_n3`",)),
        ("N4", "줄 이음(`\\`) 뒤의 둘째 이름",
         _insert_arg(f" \\\n    {_SELF_TEST_TAG}_N4=1"),
         (f"미등재 ARG: Dockerfile 의 `{_SELF_TEST_TAG}_N4`",)),
        # N5 의 **금지 문면**에 주의. 꼬리 주석을 못 자르면 `#`·주석 낱말이
        # 「읽지 못한 토큰」으로 흘러 기대 문면이 여전히 나오고, rc·기대 문면
        # 두 축만으로는 초록이 된다 (실측 2026-08-30). 겨냥한 분기가 아니라
        # 다른 분기가 울었다는 것을 가르려면 금지 축이 필요하다.
        ("N5", "꼬리 주석",
         _insert_arg(f"\nARG {_SELF_TEST_TAG}_N5=1  # 꼬리 주석"),
         (f"미등재 ARG: Dockerfile 의 `{_SELF_TEST_TAG}_N5`",),
         ("읽지 못한 ARG 토큰",)),
        # ── N6 : 읽지 못한 토큰을 **버리지 않는다**. 조용히 버리는 것이
        #         애초의 결함이었다 — 못 읽으면 등재 여부를 잴 수 없고,
        #         잴 수 없는 것을 통과로 인쇄하면 안 된다.
        ("N6", "읽을 수 없는 토큰을 통과시키지 않는다",
         _insert_arg(f"\nARG {unreadable}"),
         (f"읽지 못한 ARG 토큰: Dockerfile 의 `{unreadable}`",)),
        # ── N7–N9 : 표기 축만 시험하면 **값 대조 코드가 정의역 밖에** 남는다.
        ("N7", f"PINS 값 어긋남 (Dockerfile {pin_key} ≠ rtl/spinal)",
         lambda b: _sub(df_of(b), f"ARG {pin_key}={pin_val}",
                        f"ARG {pin_key}={pin_val}-wt-selftest"),
         (f"Dockerfile ARG {pin_key}={pin_val}-wt-selftest ≠ rtl/spinal 의",)),
        ("N8", f"PINS_TWOWAY 두 선언 어긋남 (devcontainer.json {two_key})",
         lambda b: _sub(dj_of(b), f'"{two_key}": "{two_val}"',
                        f'"{two_key}": "{two_val}-wt-selftest"'),
         (f"devcontainer.json {two_key}={two_val}-wt-selftest ≠ "
          f"Dockerfile ARG 의 {two_val}",)),
        ("N9", f"기본값 제거 (`ARG {nodef_key}` — 이름은 있고 값이 없다)",
         lambda b: _sub(df_of(b), nodef_line, f"ARG {nodef_key}"),
         (f"Dockerfile 의 ARG {nodef_key} 에 기본값이 없다",)),
        # ── N10 : 역방향. devcontainer.json 의 오타 하나로 핀이 무력해지는데
        #          빌드는 **조용히 무시한다**.
        ("N10", "허공 build.arg (devcontainer.json → 없는 ARG)",
         lambda b: _sub(dj_of(b), f'"{two_key}": "{two_val}"',
                        f'"{two_key}": "{two_val}",\n'
                        f'      "{_SELF_TEST_TAG}_N10": "x"'),
         (f"허공 build.arg: devcontainer.json 의 `{_SELF_TEST_TAG}_N10`",)),
        # ── C1–C6 : CI 금지 축. 이 축은 **실제 사고로 열렸다** —
        #            죽은 TLA 해시가 워크플로의 build-arg 사본에 있었다.
        ("C1", f"실 워크플로({wf0}) 의 build-args 블록 — **값이 맞아도** 실패",
         _ci_block,
         ("CI 가 핀을 재선언한다", str(wf0), f"`{two_key}`")),
        ("C2", "**새** 워크플로 (하위 디렉터리 + `.yaml`) — 정의역이 rglob 인가",
         _new_workflow(f"sub/{_SELF_TEST_TAG.lower()}_c2.yaml",
                       {"block_key": two_key, "block_val": two_val,
                        "flag_key": two_key, "flag_val": two_val,
                        "eq_key": two_key, "eq_val": two_val}),
         ("CI 가 핀을 재선언한다",
          f"sub/{_SELF_TEST_TAG.lower()}_c2.yaml")),
        ("C3", "`run:` 안의 `--build-arg K=V` (공백 표기)",
         _new_workflow(f"{_SELF_TEST_TAG.lower()}_c3.yml",
                       {"block_key": ci_key, "block_val": "1",
                        "flag_key": two_key, "flag_val": two_val,
                        "eq_key": ci_key, "eq_val": "1"}),
         ("CI 가 핀을 재선언한다", f"{_SELF_TEST_TAG.lower()}_c3.yml",
          f"`{two_key}`")),
        ("C4", "`--build-arg=K=V` (등호 표기)",
         _new_workflow(f"{_SELF_TEST_TAG.lower()}_c4.yml",
                       {"block_key": ci_key, "block_val": "1",
                        "flag_key": ci_key, "flag_val": "1",
                        "eq_key": two_key, "eq_val": two_val}),
         ("CI 가 핀을 재선언한다", f"{_SELF_TEST_TAG.lower()}_c4.yml",
          f"`{two_key}`")),
        # 「덮었다」와 「잴 것이 없었다」를 가른다. 이 자기시험이 조용해질 수
        # 있는 길 하나가 여기이므로 변이로도 잡아 둔다.
        ("C5", "워크플로 0건 — 잴 것이 없으면 통과가 아니다",
         _drop_workflows,
         ("워크플로가 없다",)),
        ("C6", f"허공 build-arg (CI 의 `{ci_key}` ↔ Dockerfile ARG 부재)",
         lambda b: _sub(df_of(b), ci_line + "\n", ""),
         ("허공 build-arg:", f"`{ci_key}`")),
        # ── N11–N17 : 판정 분기 일곱의 격리. 전부 「들어내도 초록」이었다. ───
        #
        # N11 이 이 뭉치의 머릿돌이다 — `elif j != a`. 이 분기는 이 파일이
        # 스스로 최악이라 부른 (b)「조용히 다른 버전을 받아 온다」를 SBT ·
        # SCALA · SPINAL 에 대해 막는 **유일한 자리**이고, 실장 보고서는
        # 「N7–N9 값 대조 축」이라 적어 닫힌 것처럼 읽히게 했다. 실제로는
        # devcontainer.json 이 rtl/spinal 과 어긋나도 조용한 상태로 검사를
        # 퇴화시켜도 변이 16 이 전부 초록이었다.
        ("N11", f"PINS devcontainer 값 어긋남 ({pin_dj_key} ≠ rtl/spinal)",
         lambda b: _sub(dj_of(b), pin_dj_decl,
                        f'"{pin_dj_key}": "{dj.get(pin_dj_key)}-wt-selftest"'),
         (f"devcontainer.json {pin_dj_key}={dj.get(pin_dj_key)}-wt-selftest ≠ "
          f"rtl/spinal 의",)),
        ("N12", f"PINS Dockerfile ARG 부재 ({pin_key} 줄 제거)",
         lambda b: _sub(df_of(b), pin_arg_line + "\n", ""),
         (f"{pin_label}: Dockerfile 에 ARG {pin_key} 가 없다",)),
        ("N13", f"PINS devcontainer 선언 부재 ({pin_dj_key})",
         lambda b: _sub(dj_of(b), pin_dj_decl + ",\n", ""),
         (f"{pin_label}: devcontainer.json build.args 에 {pin_dj_key} 가 없다",)),
        ("N14", "rtl/spinal 기준값을 읽지 못함 (build.properties 무력화)",
         lambda b: _sub(bp_of(b), props_line + "\n", "# " + props_line + "\n"),
         (f"{pin_label}: rtl/spinal 쪽에서 버전을 읽지 못했다",)),
        ("N15", f"PINS_TWOWAY Dockerfile ARG 부재 ({nodef_key} 줄 제거)",
         lambda b: _sub(df_of(b), nodef_line + "\n", ""),
         (f"{nodef_label}: Dockerfile 에 ARG {nodef_key} 가 없다",)),
        ("N16", f"PINS_TWOWAY devcontainer 선언 부재 ({two_key})",
         lambda b: _sub(dj_of(b), two_decl + ",\n", ""),
         (f"{two_label}: devcontainer.json build.args 에 {two_key} 가 없다",)),
        # 진입부 존재 검사. 들어내면 파일이 없을 때 조용히 통과하는 것이
        # 아니라 **역추적으로 죽는데**, 그것은 「검사가 판정했다」가 아니다 —
        # 그래서 rc 가 아니라 문면으로 가른다.
        ("N17", f"정의역 파일 부재 ({BUILD_SBT.relative_to(REPO)})",
         lambda b: (b / BUILD_SBT.relative_to(REPO)).unlink(),
         ("파일 부재:", str(BUILD_SBT.relative_to(REPO)))),
        # ── V1–V3 : 보관본 ↔ 핀 (2026-09-11). 보관본은 내용, 핀은 해시 — ────
        #            어긋남의 세 얼굴을 각각 격리한다. V1·V2 의 **금지 문면**은
        #            두-선언 대조(N8 의 분기)가 대신 운 것을 걸러 낸다: 겨냥은
        #            보관본 대조다.
        ("V1", "보관본 1바이트 훼손 (크기 같음 · 내용 다름)",
         _corrupt_jar,
         ("보관본 ≠ 핀:", str(VENDOR_JAR.relative_to(REPO))),
         ("≠ Dockerfile ARG 의",)),
        ("V2", "핀만 갱신 (Dockerfile · devcontainer.json 둘 다, 보관본은 그대로)",
         _repin_only,
         ("보관본 ≠ 핀:", vpin_other[:12]),
         ("≠ Dockerfile ARG 의",)),
        ("V3", "보관본 부재",
         _drop_jar,
         ("보관본 부재:", str(VENDOR_JAR.relative_to(REPO)))),
        # ── V4–V5 : 보관본 README 의 핀 사본 — **값이 맞아도** 실패. ─────────
        #            착지 당일 실제로 그렇게 적혀 있었다(확증 결함). 금지 문면은
        #            보관본 대조가 대신 운 것을 걸러 낸다.
        ("V4", "vendor/README.md 에 128-hex 해시 전문 사본 (현행 값 그대로)",
         _readme_hash_copy,
         ("보관본 README 가 핀을 재선언한다:",
          str(VENDOR_README.relative_to(REPO)), "128-hex 해시 전문"),
         ("보관본 ≠ 핀:",)),
        ("V5", "vendor/README.md 에 TLC build 시각 사본 (현행 값 그대로)",
         _readme_build_copy,
         ("보관본 README 가 핀을 재선언한다:",
          str(VENDOR_README.relative_to(REPO)), "TLC build 시각"),
         ("보관본 ≠ 핀:",)),
    ]


def self_test() -> int:
    print("lint_toolchain_pins: 음성 시험 — 격리 사본(/tmp)에서 변이 주입")
    rows: list[tuple[bool, str, str]] = []
    ok = True

    try:
        muts = _mutations()
    except _MutationMiss as e:
        print(f"  ✗ 변이표를 짓지 못했다 — {e}", file=sys.stderr)
        print("음성 시험 불통과 (변이 0건은 통과가 아니다)", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory(prefix="wt-pins-neg-") as td:
        root = Path(td)

        # ── ⓪ 정의역 폐쇄 — 변이보다 **먼저**. ─────────────────────────────
        # 「0 건을 돌고 OK 를 인쇄」가 이 부류의 전형적 실패다. 그 길을 셋으로
        # 막는다: 픽스처가 검사의 정의역 전부를 담았는가 · CI 파서가 실제로
        # 무언가를 읽는가 · 변이가 하한만큼 있는가.
        try:
            base0 = _build_fixture(root / "d0")
        except _MutationMiss as e:
            print(f"  ✗ D1 {e}", file=sys.stderr)
            return 1
        dom = _domain_paths()
        missing = [
            str(p.relative_to(REPO)) for p in dom
            if not (base0 / p.relative_to(REPO)).exists()
        ]
        d1 = len(dom) >= _MIN_DOMAIN_PATHS and not missing
        rows.append((d1, "D1",
                     f"정의역 경로 {len(dom)}개(하한 {_MIN_DOMAIN_PATHS}) 전부 "
                     f"픽스처에 실재" + (f" — 결손 {missing}" if missing else "")))

        # CI build-arg 파서 **양성 대조**: 세 표기를 다 읽는가. 실 트리 계수에
        # 하한을 걸지 않는 이유는 「CI 가 build-arg 를 하나도 안 넘긴다」가
        # 이 검사가 바라는 정상 상태이기 때문이다 — 그것을 실패로 만들면
        # 규범을 지킨 저장소가 실패한다. 대신 파서 자체를 합성으로 검증한다.
        probe = root / "probe.yml"
        probe.write_text(_SYNTH_WORKFLOW.format(
            block_key="WT_PROBE_BLOCK", block_val="1",
            flag_key="WT_PROBE_FLAG", flag_val="2",
            eq_key="WT_PROBE_EQ", eq_val="3"), encoding="utf-8")
        got = {k for _, k in read_ci_build_args(probe)}
        want = {"WT_PROBE_BLOCK", "WT_PROBE_FLAG", "WT_PROBE_EQ"}
        d2 = got >= want
        rows.append((d2, "D2",
                     f"CI build-arg 파서 양성 대조 — 표기 3종 {sorted(want & got)}"
                     + (f" / **못 읽음** {sorted(want - got)}" if want - got else "")))

        d3 = len(muts) >= _MIN_MUTATIONS
        rows.append((d3, "D3",
                     f"변이 {len(muts)}건 ≥ 하한 {_MIN_MUTATIONS} "
                     f"(0건은 통과가 아니다)"))

        # ── D4 : Dockerfile ARG 파서 **양성 대조.** ─────────────────────────
        # 변이가 아니라 양성 대조인 이유는 `_ARG_PROBE_DF` 머리주석에 적었다 —
        # 파서 보조의 퇴화는 「같은 문면을 다른 경로로」 나타나 rc·문면 축을
        # 빠져나간다. 여기서는 **출력 전체**를 실측 정답표와 대조한다.
        probe_df = root / "probe.Dockerfile"
        probe_df.write_text(_ARG_PROBE_DF, encoding="utf-8")
        got_pairs, got_unparsed = parse_dockerfile_args(probe_df)
        # 정답표에 **하한**을 함께 건다. 표와 픽스처를 같이 비우면
        # `[] == []` 로 조용히 초록이 되는데, 그것이 이 파일이 이름한 「0건을
        # 돌고 OK 를 인쇄」 그 자체다 — 양성 대조도 예외가 아니다.
        d4 = (len(_ARG_PROBE_WANT) >= _MIN_ARG_PROBE
              and got_pairs == _ARG_PROBE_WANT and not got_unparsed)
        rows.append((d4, "D4",
                     f"ARG 파서 양성 대조 — 표기 {len(_ARG_PROBE_WANT)}종"
                     f"(하한 {_MIN_ARG_PROBE})"
                     + ("" if d4 else
                        f" / **어긋남** 얻음={got_pairs} 읽지못함={got_unparsed}")))

        # ── D5 : JSONC 파서 양성 대조. ──────────────────────────────────────
        # 문자열 추적을 지우면 `"https://…"` 의 `//` 가 주석으로 잘려 JSON 이
        # 깨진다. 그 갈래에 변이가 없어 들어내도 초록이었다 (실측 2026-08-30).
        try:
            got_json = json.loads(strip_jsonc(_JSONC_PROBE))
        except Exception as e:  # noqa: BLE001 — 무엇이 터졌는지 인쇄해야 한다
            got_json = f"<예외: {type(e).__name__}: {e}>"
        d5 = got_json == _JSONC_WANT
        rows.append((d5, "D5",
                     "JSONC 파서 양성 대조 — 문자열 안의 `//` · 이스케이프 "
                     "따옴표 · 꼬리 주석"
                     + ("" if d5 else f" / **어긋남** {got_json}")))

        # ── D6 : 해시 함수 양성 대조. ───────────────────────────────────────
        # 보관본 대조는 `hashlib.blake2b(digest_size=64)` 위에 선다. 계열이
        # 조용히 바뀌면(예: digest_size 기본값 32 로 회귀) V1–V3 이 「다른
        # 이유로」 울고 N0 가 죽는데, 그때 문면은 「보관본 ≠ 핀」이라 사람이
        # 보관본을 의심한다. 알려진 벡터로 함수 자체를 먼저 잰다.
        d6 = hashlib.blake2b(b"", digest_size=64).hexdigest() == _B2_EMPTY
        rows.append((d6, "D6",
                     "해시 함수 양성 대조 — blake2b(digest_size=64) 의 빈 입력 "
                     "벡터가 `b2sum </dev/null` 과 같다"
                     + ("" if d6 else " / **어긋남**")))

        # 게이트가 아니라 **대비의 인쇄** — 실 트리에서 이 축이 무엇을 봤는지.
        real_wf = [p for p in CI_WORKFLOW_DIR.rglob("*")
                   if p.suffix in (".yml", ".yaml") and p.is_file()]
        real_keys = [k for p in real_wf for _, k in read_ci_build_args(p)]
        note = (f"실 트리 대비: 워크플로 {len(real_wf)}편 / build-arg 키 "
                f"{len(real_keys)}개 {sorted(set(real_keys))} — 게이트가 아니라 "
                f"대비의 인쇄다")

        if not (d1 and d2 and d3 and d4 and d5 and d6):
            for good, tag, text in rows:
                print(f"  {'✓' if good else '✗'} {tag} {text}")
            print(f"  · {note}")
            print("음성 시험 불통과 — 정의역 폐쇄가 깨졌다 (변이는 걸지 않았다)",
                  file=sys.stderr)
            return 1

        # ── N0 대조군 — 변이 없는 사본이 통과하는가. **먼저.** ──────────────
        rc, out = _run_fixture(base0)
        if rc != 0:
            for good, tag, text in rows:
                print(f"  {'✓' if good else '✗'} {tag} {text}")
            print("  ✗ N0 대조군 — **변이 없는 사본이 이미 실패한다**")
            print(out)
            print("음성 시험 불통과 — 기준이 깨진 상태에서는 모든 변이가 "
                  "엉뚱한 이유로 운다", file=sys.stderr)
            return 1
        rows.append((True, "N0", "대조군 — 변이 없는 사본은 통과한다 (rc=0)"))

        # ── 변이 ────────────────────────────────────────────────────────────
        for i, mut in enumerate(muts):
            tag, desc, apply, expect = mut[:4]
            forbid = mut[4] if len(mut) > 4 else ()
            base = _build_fixture(root / f"m{i}")
            try:
                apply(base)  # type: ignore[operator]
            except _MutationMiss as e:
                rows.append((False, tag, f"{desc} — 변이 지점을 찾지 못했다: {e}"))
                ok = False
                continue
            rc, out = _run_fixture(base)
            if rc == 0:
                rows.append((False, tag,
                             f"{desc} — **검사가 잡지 못했다** (공허한 검사다)"))
                ok = False
                continue
            miss = [s for s in expect if s not in out]
            if miss:
                # rc 만 보면 여기가 통과로 세어지고, 이 변이가 겨냥한 분기는
                # 조용히 정의역 밖에 남는다.
                rows.append((False, tag,
                             f"{desc} — 실패는 했으나 **다른 이유로** 울었다: "
                             f"기대 문면 부재 {miss}"))
                ok = False
                continue
            spur = [s for s in forbid if s in out]
            if spur:
                # 기대 문면이 **다른 경로로** 나온 경우. 이것을 통과로 세면
                # 겨냥한 분기가 조용히 정의역 밖에 남는다 (N5 가 그랬다).
                rows.append((False, tag,
                             f"{desc} — 기대 문면은 나왔으나 **겨냥한 분기가 "
                             f"아니라 다른 분기가** 울었다: 금지 문면 {spur}"))
                ok = False
                continue
            rows.append((True, tag, f"{desc} — FAIL 확인"))

    for good, tag, text in rows:
        print(f"  {'✓' if good else '✗'} {tag} {text}")
    print(f"  · {note}")
    if not ok:
        print(f"음성 시험 불통과 — 변이 {sum(1 for g, _, _ in rows if not g)}건이 "
              f"기대대로 실패하지 않았다", file=sys.stderr)
        return 1
    print(f"음성 시험 통과 — 대조군 1 + 정의역 폐쇄 6 + 변이 {len(muts)} 전부 "
          f"기대대로 판정된다")
    print("  이것은 **검사가 무는지**를 재는 것이지 핀이 옳은지를 재는 것이 "
          "아니다 — 후자는 위의 본 검사가, 그리고 `--no-cache` 실 빌드만이 "
          "잰다.")
    return 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(self_test())
    sys.exit(main())
