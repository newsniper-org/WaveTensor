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
