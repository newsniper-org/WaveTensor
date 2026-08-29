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

셋이 어긋나면 조용히 나쁜 일이 일어난다. 컨테이너는 어떤 버전의 의존을
이미지 층에 구워 두는데, 빌드가 다른 버전을 원하면 (a) 네트워크가 없을 때
죽거나 (b) 네트워크가 있을 때 **조용히 다른 버전을 받아 온다**. (b) 가 더
나쁘다 — 통과하는데 무엇으로 쟀는지가 달라진다.

⇒ 이 검사는 그 어긋남을 **크게** 실패시킨다. 사람 기억으로 유지되는 일치는
   일치가 아니다 (정본 부록 B.3).

stdlib 전용. 직접 실행 가능:  python3 scripts/lint_toolchain_pins.py
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

DOCKERFILE = REPO / ".devcontainer" / "Dockerfile"
DEVJSON = REPO / ".devcontainer" / "devcontainer.json"
BUILD_PROPS = REPO / "rtl" / "spinal" / "project" / "build.properties"
BUILD_SBT = REPO / "rtl" / "spinal" / "build.sbt"

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
]


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


def read_dockerfile_args(path: Path) -> dict[str, str]:
    args: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\s*ARG\s+([A-Z_][A-Z0-9_]*)=(\S+)\s*$", line)
        if m:
            args[m.group(1)] = m.group(2)
    return args


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

    df = read_dockerfile_args(DOCKERFILE)
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
        if d is None:
            problems.append(f"{label}: Dockerfile 에 ARG {key} 가 없다")
        if j is None:
            problems.append(f"{label}: devcontainer.json build.args 에 {key} 가 없다")
        elif d is not None and j != d:
            problems.append(
                f"{label}: devcontainer.json {key}={j} ≠ Dockerfile ARG 의 {d}"
            )
        if d is not None:
            # 커밋 해시는 OK 줄을 읽을 수 없게 만든다 — 표시만 줄인다 (대조는 전폭).
            rows.append((label, d if len(d) <= 12 else d[:12] + "…"))

    if problems:
        print("lint_toolchain_pins: FAIL — 툴체인 핀이 어긋났다", file=sys.stderr)
        for p in problems:
            print(f"  · {p}", file=sys.stderr)
        print(
            "\n  세 곳이 같은 값을 말해야 한다:\n"
            "    .devcontainer/Dockerfile          (ARG 기본값)\n"
            "    .devcontainer/devcontainer.json   (build.args)\n"
            "    rtl/spinal/{project/build.properties, build.sbt}   ← 기준\n"
            "\n  어긋난 채로 두면 컨테이너가 구운 캐시와 빌드가 원하는 버전이\n"
            "  달라진다. 네트워크가 있으면 조용히 다른 버전을 받아 온다 —\n"
            "  통과하는데 무엇으로 쟀는지가 달라지는 것이 가장 나쁘다.",
            file=sys.stderr,
        )
        return 1

    print("lint_toolchain_pins: OK — " + " / ".join(f"{k} {v}" for k, v in rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
