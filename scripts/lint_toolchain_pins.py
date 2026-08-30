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
