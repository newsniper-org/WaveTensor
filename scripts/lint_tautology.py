#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""공허 3형 — **상수 접힘 검사**. (항진 판정기가 아니다. 아래를 읽어라.)

## 이름이 「항진 게이트」가 아닌 이유

이 검사가 재는 것은 **yosys 가 접을 수 있는 부류**뿐이고, 그 부류는 **구조적
항등**(`assert (1'b1)` · `assert (q == q)` · `assert (b || !b)`)이다 — 그것만
`connect \\A 1'1` 로 접힌다.

**폭이 함의하는 항진은 접히지 않는다** (2026-08-27 실측, 이 파일의 음성 시험
근거): `assert ({3'b0, q} <= 4'hF)` 는 `$le` 셀(`A_WIDTH 1` · `B 4'hF`)이 그대로
남는다 — yosys 0.66 은 `$le` 에 범위 추론을 하지 않는다. 심은 항진 5건 중 4건만
잡혔다. **4차 설계 브리핑이 이 예를 「접힌다」의 표준 예로 들었고 그것이 틀렸다**
(notes-vacuity-detection.md §4차 ①의 표). 게이트의 실제 덮임은 설계가 가정한
것보다 좁다.

구조가 다른 두 식의 의미적 동치(`assert (f(x) == g(x))`, f≡g)도 접히지 않는다.
하네스 자신의 assume 아래에서만 항진인 것도 절대 접히지 않는다 — assume 은
`chformal -assume -early` 로 별도 셀로 살아남는다.

⇒ **항진의 필요조건 검출기이지 항진 판정기가 아니다.** 「상수 접힘 0」을 「항진
없음」으로 읽으면 3형은 닫혔다는 기록만 남고 진짜 검사(가드 삭제 실험의 후-formal
판 — RTL 에서 가드를 지우고 증명이 실제로 깨지는지)는 영영 오지 않는다. 3형은
**열린 채로 유지된다.** 이 게이트는 바닥을 조금 올릴 뿐이다.

## 무엇을 세는가

합성 모델(`design_prep.il`)의 `cell $assert` 마다 두 피연산자를 본다:

  · `\\A`  가 상수  → 단언이 설계와 무관하다. A=1 이면 항진(어떤 설계에서도 통과),
                     A=0 이면 무조건 거짓. 둘 다 공허의 3형이다.
  · `\\EN` 이 상수 0 → 단언이 영영 비활성이다. 셀은 세어지지만 아무것도 재지 않는다.

**`EN` 이 상수 1 인 것은 정상이다** — 무조건 단언이고 3차 실측에서 18건이었다.
그것을 잡으면 오탐이고, 그래서 `en1` 은 세되 판정하지 않는다(보고만).

**상수 A 에는 두 부류가 있다** (2026-08-28 신설 — `_CONST_BY_MERGE` 머리
주석이 정본): 저작-항진(단언 문면이 설계 무관 — 하드 실패)과 병합-상수
(flatten 후 opt_merge 가 동형 콘을 물리 공유해 등가 miter 가 접힘 — 구조적
등가의 증명이므로 세되 근거와 함께 기록). 가르는 기계는 선-flatten 감사
모델(`design_preflatten.il`)이다 — 병합 전 모델에서 접힌 것만 저작이다.

## 간접 결속 — 직접 상수만 보면 놓친다

3차 전수 감사가 잡은 것은 「모듈 수준 `connect` 로 상수에 결속된 경우」다.
실측(2026-08-27, /tmp/wt-sby-out 모델 51개): 모듈 수준 `connect` 3197건 중
**우변이 상수인 것 434건**이고 그중 통짜 결속이 345건이다. 즉 이 저장소의 모델에서
간접 결속은 흔하다 — `connect \\A 1'1` 이라는 *직접* 형태만 grep 하면 그 434건 뒤에
숨은 항진을 통째로 놓친다.

그래서 이 스크립트는 **비트 단위로 상수를 전파한다**:

  1. 모듈 수준 `connect <lhs> <rhs>` 에서 비트별 상수 지도와 별칭 지도를 만든다.
     (`connect \\w 3'010` · `connect \\w [1] 1'0` · `connect \\w { 16'0 \\tag }` 전부)
  2. 별칭을 **고정점까지** 따라간다 — 1단이 아니라 N단이다. 3차가 잡은 것은
     1단이지만 `connect \\a \\b` · `connect \\b 1'1` 의 2단 사슬을 막을 것이 없다.
     실제 도달 깊이를 보고에 인쇄한다(`depth`) — 「1단만 있었다」와 「N단을 봤는데
     1단뿐이었다」를 가르기 위해서다.
  3. 그 뒤에 `$assert` 의 A/EN 을 해소한다.

## 갓 clone 한 사람 — 「없다」와 「없는 곳을 봤다」

모델은 `/tmp` 에 있고 커밋되지 않는다. 그러므로 모델을 못 찾은 것은 **계수 0 이
아니라 미계수(UNCOUNTED)** 다. 이 구분이 이 파일의 알맹이고, 2026-08-25 에 두 번
밟은 「측정하지 못했다를 0이었다로 보고」의 재발을 막는 유일한 장치다.

  · `--audit`                 모델 없는 태스크를 **미계수로 인쇄**하고 통과 (make lint)
  · `--audit --require-models` 모델이 없으면 **하드 실패** (스윕 직후 — 게이트 결함)

`--require-fresh` 가 `make rtl-postformal` 에만 걸린 비대칭과 같은 자리다.
RTL 을 편집하는 중에 모델이 없는 것은 정상이고, 스윕 직후에 없는 것은 결함이다.

## 양성 대조 — `--self-test`

「검사가 살아 있는가」를 검사가 스스로 인쇄한다. 상수 접힘을 **일부러 심은** 합성
모델 조각을 만들어 넷을 확인한다: 직접 A · 간접 A(1단) · 간접 A(2단) · EN=0.
그리고 **무조건 단언(EN=1)이 잡히지 않는 것**을 함께 확인한다 — 오탐 쪽 대조가
없으면 「전부 잡는 검사」가 통과해 버린다.

모델이 없어도 돌므로 **갓 clone 한 사람에게도 뜻이 있는 유일한 부분**이다.
계수가 0 일 때 그 0 이 「셈이 살아 있는데 0」임을 이것이 받쳐 준다.

## 왜 셈이 여기 한 곳에만 사는가

`sby_sweep.sh` 머리 주석의 규율 그대로 — 「셈은 여기서, 서식과 해시와 판정은
lint 에서」. 스윕이 이 파일을 `--count` 로 부르고, 증거층이 그 수를 증거에 적고,
`lint_postformal` 이 판정한다. **정규식 사본이 두 층에 생기는 것**이 2026-08-25
두 오탐의 뿌리이므로 파서는 여기 한 벌뿐이다. `--audit` 도 같은 함수를 부른다.
"""

import argparse
import json
import os
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SBY_DIR = ROOT / "rtl" / "formal" / "sby"

# ── 면제 표 ──────────────────────────────────────────────────────────────
#
# `_NO_WITNESS` 와 정확히 같은 형태다. 표가 비어 있으므로 **오늘의 동작은 순수
# 하드 실패와 동치**다. 그런데도 표를 두는 이유는 3차 파도의 판단 그대로다:
# 탈출구가 없으면 다음 사람은 규율을 고치는 대신 **「접히지 않게 식을 비트는」**
# 길로 간다. 그것은 3형을 없애는 것이 아니라 검출 불가 형태로 옮기는 것이고,
# 이 게이트를 스스로 무력화하는 가장 빠른 길이다.
#
# 키: "<Dir>/<name>.sby:<task>". 값: (근거, 그래도 재는 다른 수단).
_TAUTOLOGY = {
    # 비어 있다 — 2026-08-27 실측으로 모델 51개 · $assert 1314셀 중 상수 A 0건,
    # 상수 EN0 0건. 항목을 넣으려면 _MAX_TAUTOLOGY 를 함께 올려야 한다
    # (그것이 서명이다).
}
_MAX_TAUTOLOGY = 0   # 상수 접힘이 허용된 태스크 수. 늘지 않는다.

# ── 병합-상수(const-by-merge) 표 — 저작-항진과 가른다 ────────────────────
#
# 2026-08-28 (walk_decode 엔진 처분 파도) 신설. `_STRUCTURAL`/`_PARTIAL` 의
# 계보다: **범주가 없으면 통합자는 둘 중 하나를 강요받는다** — 게이트를
# 완화하거나(항진 검출이 통째로 죽는다), 모델 준비를 비틀어 접히지 않게
# 만들거나(증명이 완주하지 못하게 되돌아간다). 범주를 만들고 표+래칫으로
# 서명을 요구하는 것이 세 번 검증된 세 번째 길이다.
#
# ## 두 접힘은 다른 것이다
#
#   저작-항진   단언 *문면*이 설계와 무관하게 참이다 (`assert (q == q)`).
#               어떤 설계에서도 통과하므로 아무것도 재지 않는다. **하드 실패.**
#   병합-상수   단언 문면은 두 독립 전개의 등가인데, flatten 후 opt_merge 가
#               셀형·연결이 동일한 두 콘을 물리 공유해 $eq(r,r)→1 로 접었다.
#               이 접힘은 **구조적 등가의 증명 그 자체**다 — RTL 상수가
#               하나라도 틀리면 병합이 안 되어 SAT 반례 탐색으로 되돌아간다
#               (walk_decode.sby [script] 의 flatten 주석 · 실측). 세되
#               근거와 함께 기록하고, 하드 실패시키지 않는다.
#
# ## 기계가 둘을 가르는 방법 — 선-flatten 감사 모델
#
# 해당 .sby 의 [script] 가 flatten *직전에* `design_preflatten.il` 을 남기고
# (sby_sweep.sh 가 그것을 세어 const_a_authored 로 증거에 싣는다), 병합 전
# 모델에서 접힌 것만 저작-항진으로 판정한다. 병합 전 모델에서 0 이고 병합 후
# 모델에서 N 이면 그 N 은 전부 병합-상수다. **감사 모델이 없는 태스크는 종전
# 그대로 접힘 전부가 저작 혐의다** — 이 표에 올리는 것만으로는 아무것도
# 면제되지 않는다 (표 등재 + 감사 모델 + authored 0, 셋이 모두 서야 한다).
#
# 키: `_TAUTOLOGY` 와 같은 "<sby 상대경로>:<태스크>". 값: (근거, 그래도 재는
# 다른 수단). 항목을 넣으려면 _MAX_CONST_BY_MERGE 를 함께 올려야 한다.
_CONST_BY_MERGE = {
    "rtl/formal/sby/DecodeWalk/walk_decode.sby:bmc": (
        "CH CRC-32C 등가 단언 콘 — 참조(스펙-유도 워드 행렬 상수)와 RTL 의 "
        "CRC 콘이 동형이라 flatten 후 opt_merge 가 물리 공유, oInstr 등가 "
        "14 · slot 등가 3 · 그 외 2 의 $eq 가 상수 1 로 접힘 (실측 19/41)",
        "선-flatten 감사 모델에서 저작-항진 0 을 매 스윕 실측 + 변이 실측 "
        "(RTL·참조 상수 1비트 훼손 시 병합이 풀려 반례가 실제로 난다 — "
        "walk_decode.sby 엔진 처분 기록의 변이 4/4)",
    ),
    "rtl/formal/sby/DecodeWalk/walk_decode.sby:prove": (
        "bmc 와 같은 모델·같은 병합 (태스크는 엔진만 다르다 — abc pdr)",
        "bmc 항목과 동일 — 감사 모델은 태스크마다 따로 생성·계수된다",
    ),
}
_MAX_CONST_BY_MERGE = 2   # 병합-상수가 허용된 태스크 수. 늘리려면 근거와 함께.

_CONST_RE = re.compile(r"^(\d+)'([01xzm-]+)$")
_INT_RE = re.compile(r"^-?\d+$")
_SLICE_RE = re.compile(r"^\[(\d+)(?::(\d+))?\]$")
# 실물: `  wire width 4 input 21 \vld` · `  wire input 31 \shoveAny` · `  wire \x`
_WIRE_RE = re.compile(r"^\s*wire\s+(.*?)(\S+)\s*$")
_WIDTH_RE = re.compile(r"\bwidth\s+(\d+)\b")

_MAX_DEPTH = 64      # 별칭 사슬 고정점 상한. 넘으면 순환이므로 보고한다.


def _fail(msg: str) -> None:
    print(f"lint_tautology: FAIL — {msg}", file=sys.stderr)
    sys.exit(1)


# ─────────────────────────────────────────────────────────────────────────
# RTLIL sigspec 파서
# ─────────────────────────────────────────────────────────────────────────
def _tokens(s: str):
    """`{ 16'0000 \\tag [3:0] }` 를 토큰으로. 중괄호는 따로 떨어진다."""
    return s.replace("{", " { ").replace("}", " } ").split()


def _const_bits(tok: str):
    """상수 리터럴 → LSB-first 비트 문자열 리스트. 아니면 None."""
    m = _CONST_RE.match(tok)
    if m:
        width, bits = int(m.group(1)), m.group(2)
        # RTLIL 리터럴은 MSB-first. 폭에 맞춰 좌측을 잘라내거나 확장한다.
        bits = bits[-width:].rjust(width, bits[0] if bits else "0")
        return list(reversed(bits))
    if _INT_RE.match(tok):
        v = int(tok)
        return [str((v >> i) & 1) for i in range(32)]
    return None


def parse_sigspec(spec: str, widths: dict):
    """sigspec → LSB-first 비트 목록. 각 비트는 ('c', '0'|'1'|…) 또는
    ('w', 이름, 인덱스). 해석 불가면 None (해석 못 한 것을 상수로 읽지 않는다)."""
    toks = _tokens(spec)
    if not toks:
        return None
    if toks[0] == "{":
        if toks[-1] != "}":
            return None
        inner, groups = toks[1:-1], []
        if "{" in inner or "}" in inner:
            return None          # 중첩 연접 — 이 저장소 모델에 실물이 없다
        # 연접 원소는 MSB-first. 원소 경계는 「이름 [슬라이스]」 붙임을 고려한다.
        i = 0
        while i < len(inner):
            if i + 1 < len(inner) and _SLICE_RE.match(inner[i + 1]):
                groups.append(" ".join(inner[i:i + 2]))
                i += 2
            else:
                groups.append(inner[i])
                i += 1
        out = []
        for g in reversed(groups):          # MSB-first → LSB-first 로 뒤집는다
            b = parse_sigspec(g, widths)
            if b is None:
                return None
            out.extend(b)
        return out

    if len(toks) == 1:
        c = _const_bits(toks[0])
        if c is not None:
            return [("c", ch) for ch in c]
        name = toks[0]
        w = widths.get(name)
        if w is None:
            return None
        return [("w", name, i) for i in range(w)]

    if len(toks) == 2:
        name, m = toks[0], _SLICE_RE.match(toks[1])
        if not m:
            return None
        hi = int(m.group(1))
        lo = int(m.group(2)) if m.group(2) is not None else hi
        if lo > hi:
            hi, lo = lo, hi
        return [("w", name, i) for i in range(lo, hi + 1)]

    return None


# ─────────────────────────────────────────────────────────────────────────
# 모델 스캔
# ─────────────────────────────────────────────────────────────────────────
def scan_model(path: Path) -> dict:
    """design_prep.il 하나 → 계수 dict.

    모듈마다 따로 해소한다 — 이름 공간이 모듈별이므로 한 통에 섞으면 다른
    모듈의 동명 wire 로 상수가 새어 **오탐**이 난다.
    """
    text = path.read_text(encoding="utf-8", errors="replace")

    mod = None
    mods = {}          # 모듈명 -> {"widths":…, "conn":[…], "asserts":[…]}
    in_cell = None     # (셀타입, {포트: sigspec}, 셀이름)
    last_src = ""      # 직전 `attribute \src` — 실패 보고의 길잡이로만 쓴다.
    #
    # 증거에 저장하지 않는다. 줄번호 매인 참조를 *보관*하면 무관한 편집마다
    # 밀려서 공허 2형(줄번호 밀림)의 증거층 판이 된다. 실패 순간에만 인쇄하는
    # 길잡이는 그 위험이 없고, 사람이 단언을 찾는 비용을 크게 줄인다.

    def cur():
        return mods.setdefault(
            mod, {"widths": {}, "conn": [], "asserts": []})

    for raw in text.splitlines():
        line = raw.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        stripped = line.strip()

        if stripped.startswith("module "):
            mod = stripped.split(None, 1)[1].strip()
            cur()
            continue
        if mod is None:
            continue

        if stripped.startswith("attribute \\src "):
            last_src = stripped[len("attribute \\src "):].strip('"')
            continue

        if stripped == "end":
            if in_cell is not None:
                ctype, ports, cname, csrc = in_cell
                # $check(FLAVOR=assert)는 $assert 와 같은 자로 센다 (2026-08-28):
                # yosys 0.66 의 read_verilog -formal 은 단언을 $check 로 들이고
                # $assert 로의 하강은 async2sync 가 한다. 선-flatten 감사 모델
                # (walk_decode.sby 의 design_preflatten.il)은 하강 전 덤프라
                # $check 뿐이고, 이것을 못 세면 「세는 쪽이 아무것도 보지
                # 못했다」가 계수 0 으로 둔갑한다 — 이 파일이 막으러 온 그
                # 형태다. 조건·활성 피연산자는 양쪽 다 \A·\EN 이다.
                if ctype == "$assert" or (
                        ctype == "$check"
                        and ports.get("#FLAVOR") == '"assert"'):
                    ports["#name"] = cname
                    ports["#src"] = csrc
                    cur()["asserts"].append(ports)
                in_cell = None
            else:
                mod = None          # 모듈 끝
            continue

        if stripped.startswith("cell "):
            parts = stripped.split(None, 2)
            in_cell = (parts[1] if len(parts) >= 2 else "?", {},
                       parts[2].lstrip("\\") if len(parts) >= 3 else "?",
                       last_src)
            continue

        if stripped.startswith("parameter ") and in_cell is not None:
            # $check 의 FLAVOR 판별에만 쓴다. `parameter \FLAVOR "assert"`.
            p = stripped.split(None, 2)
            if len(p) == 3 and p[1] == "\\FLAVOR":
                in_cell[1]["#FLAVOR"] = p[2].strip()
            continue

        if stripped.startswith("wire "):
            if in_cell is None:
                m = _WIRE_RE.match(line)
                if m:
                    wm = _WIDTH_RE.search(m.group(1))
                    cur()["widths"][m.group(2)] = int(wm.group(1)) if wm else 1
            continue

        if stripped.startswith("connect "):
            body = stripped[len("connect "):].strip()
            if in_cell is not None:
                # 셀 포트 결선 — 포트명은 첫 토큰.
                p = body.split(None, 1)
                if len(p) == 2:
                    in_cell[1][p[0]] = p[1].strip()
            else:
                # 모듈 수준 결선 — 좌변은 이름[+슬라이스] 또는 연접.
                if body.startswith("{"):
                    depth, i = 0, 0
                    for i, ch in enumerate(body):
                        depth += (ch == "{") - (ch == "}")
                        if depth == 0:
                            break
                    lhs, rhs = body[:i + 1], body[i + 1:].strip()
                else:
                    t = body.split()
                    if len(t) >= 2 and _SLICE_RE.match(t[1]):
                        lhs, rhs = " ".join(t[:2]), " ".join(t[2:])
                    else:
                        lhs, rhs = t[0], " ".join(t[1:])
                if rhs:
                    cur()["conn"].append((lhs, rhs))
            continue

    # ── 모듈마다 상수/별칭을 고정점까지 전파 ──────────────────────────────
    # `unparsed` 는 **이 검사 자신의 사각지대**다. 파서가 포기한 connect 뒤에
    # 상수 결속이 숨어 있으면 계수는 당당하게 0 을 인쇄한다 — 이 저장소가 두 번
    # 밟은 「측정하지 못했다를 0이었다로 보고」가 *검사기 안에서* 재현되는 자리다.
    # 그래서 세어서 인쇄한다. 2026-08-27 실측으로 3199/3199 을 해석하므로 0 이고,
    # yosys 가 새 구문을 내면 여기가 먼저 운다.
    tot = {"assert_cells": 0, "const_a": 0, "const_en0": 0, "en1": 0,
           "depth": 0, "cyclic": 0, "unparsed": 0}
    detail = []

    for name, m in mods.items():
        widths = m["widths"]
        const = {}       # (wire, idx) -> '0'|'1'|'x'|…
        alias = {}       # (wire, idx) -> (wire, idx)
        for lhs, rhs in m["conn"]:
            lb = parse_sigspec(lhs, widths)
            rb = parse_sigspec(rhs, widths)
            if lb is None or rb is None:
                tot["unparsed"] += 1
                continue
            for lbit, rbit in zip(lb, rb):
                if lbit[0] != "w":
                    continue
                key = (lbit[1], lbit[2])
                if rbit[0] == "c":
                    const.setdefault(key, rbit[1])
                else:
                    alias.setdefault(key, (rbit[1], rbit[2]))

        # 별칭 사슬을 따라 상수를 끌어온다. 1단이 아니라 고정점까지.
        depth = 0
        for _ in range(_MAX_DEPTH):
            grew = 0
            for k, v in alias.items():
                if k not in const and v in const:
                    const[k] = const[v]
                    grew += 1
            if not grew:
                break
            depth += 1
        else:
            tot["cyclic"] += 1
        tot["depth"] = max(tot["depth"], depth)

        def resolve(spec):
            """sigspec 이 전부 상수면 비트 문자열(LSB-first), 아니면 None."""
            bits = parse_sigspec(spec, widths)
            if bits is None:
                return None
            out = []
            for b in bits:
                if b[0] == "c":
                    out.append(b[1])
                elif (b[1], b[2]) in const:
                    out.append(const[(b[1], b[2])])
                else:
                    return None
            return out

        for ports in m["asserts"]:
            tot["assert_cells"] += 1
            # 피연산자를 아예 해석하지 못한 것은 「상수가 아니다」가 아니라
            # 「보지 못했다」다. resolve 는 둘 다 None 을 내므로 여기서 가른다.
            for port in ("\\A", "\\EN"):
                if parse_sigspec(ports.get(port, ""), widths) is None:
                    tot["unparsed"] += 1
            a = resolve(ports.get("\\A", ""))
            en = resolve(ports.get("\\EN", ""))
            who = {"cell": ports.get("#name", "?"),
                   "src": ports.get("#src", "")}
            if a is not None:
                tot["const_a"] += 1
                detail.append({**who, "port": "A",
                               "value": "".join(reversed(a))})
            if en is not None:
                if set(en) <= {"0"}:
                    tot["const_en0"] += 1
                    detail.append({**who, "port": "EN", "value": "0"})
                elif "1" in en:
                    # 무조건 단언 — **정상이다.** 세되 판정하지 않는다.
                    tot["en1"] += 1
    tot["detail"] = detail[:20]
    return tot


def scan_models(paths) -> dict:
    """모델 여럿 → 합산. 태스크마다 model/ 이 따로 생기므로 셀 수는 최댓값이
    옳지만(sby_sweep.sh 의 2차 파도 판단), **상수 계수는 합이다** — 어느 한
    태스크의 모델에서라도 접혔으면 그것은 실재하는 접힘이다."""
    agg = {"models": 0, "assert_cells": 0, "const_a": 0, "const_en0": 0,
           "en1": 0, "depth": 0, "cyclic": 0, "unparsed": 0, "detail": []}
    for p in paths:
        r = scan_model(p)
        agg["models"] += 1
        agg["assert_cells"] = max(agg["assert_cells"], r["assert_cells"])
        for k in ("const_a", "const_en0", "en1", "cyclic", "unparsed"):
            agg[k] += r[k]
        agg["depth"] = max(agg["depth"], r["depth"])
        for d in r["detail"]:
            d = dict(d, model=p.parent.parent.name)
            agg["detail"].append(d)
    agg["detail"] = agg["detail"][:20]
    return agg


# ─────────────────────────────────────────────────────────────────────────
# 양성 대조 — 검사가 살아 있는가
# ─────────────────────────────────────────────────────────────────────────
_FIXTURE = r"""
module \selftest
  wire \direct_a
  wire \hop1
  wire \hop2
  wire \live
  wire \en_zero
  wire \en_one
  connect \hop1 1'1
  connect \hop2 \hop1
  connect \en_zero 1'0
  connect \en_one 1'1
  attribute \keep 1
  cell $assert \t_direct
    connect \A 1'1
    connect \EN \en_one
  end
  attribute \keep 1
  cell $assert \t_indirect1
    connect \A \hop1
    connect \EN \en_one
  end
  attribute \keep 1
  cell $assert \t_indirect2
    connect \A \hop2
    connect \EN \en_one
  end
  attribute \keep 1
  cell $assert \t_en_zero
    connect \A \live
    connect \EN \en_zero
  end
  attribute \keep 1
  cell $assert \t_unconditional
    connect \A \live
    connect \EN \en_one
  end
  attribute \keep 1
  cell $assert \t_normal
    connect \A \live
    connect \EN \live
  end
  attribute \keep 1
  cell $check \t_check_assert_const
    parameter \FLAVOR "assert"
    connect \A 1'1
    connect \EN \en_one
  end
  attribute \keep 1
  cell $check \t_check_cover_const
    parameter \FLAVOR "cover"
    connect \A 1'1
    connect \EN \en_one
  end
end
"""

# 다른 모듈의 동명 wire 로 상수가 새면 오탐이다 — 그 음성 대조.
_FIXTURE_LEAK = r"""
module \other
  wire \hop1
  connect \hop1 1'1
end
module \victim
  wire \hop1
  attribute \keep 1
  cell $assert \t_must_not_fold
    connect \A \hop1
    connect \EN 1'1
  end
end
"""


def self_test(verbose: bool = True) -> bool:
    """상수 접힘을 일부러 심은 모델에서 실제로 잡히는지. 오탐 쪽도 함께."""
    ok = True
    with tempfile.TemporaryDirectory() as td:
        f = Path(td) / "design_prep.il"
        f.write_text(_FIXTURE, encoding="utf-8")
        r = scan_model(f)
        checks = [
            ("assert 셀 7개를 센다 ($check FLAVOR=assert 포함 · FLAVOR=cover 제외)",
             r["assert_cells"] == 7, r["assert_cells"]),
            ("상수 A 4건 (직접·간접1단·간접2단·$check-assert)",
             r["const_a"] == 4, r["const_a"]),
            ("상수 EN0 1건", r["const_en0"] == 1, r["const_en0"]),
            ("무조건 단언(EN=1) 5건을 항진으로 잡지 않는다",
             r["en1"] == 5, r["en1"]),
            ("별칭 사슬 깊이 ≥ 1 (간접이 실제로 전파됐다)",
             r["depth"] >= 1, r["depth"]),
        ]
        g = Path(td) / "leak.il"
        g.write_text(_FIXTURE_LEAK, encoding="utf-8")
        rl = scan_model(g)
        checks.append(("모듈 경계를 넘어 상수가 새지 않는다",
                       rl["const_a"] == 0, rl["const_a"]))
        for label, good, got in checks:
            if not good:
                ok = False
            if verbose:
                print(f"  {'ok' if good else 'FAIL'}  {label} (관측 {got})")
    return ok


# ─────────────────────────────────────────────────────────────────────────
# 감사 — 저장소의 .sby 전수에 대해
# ─────────────────────────────────────────────────────────────────────────
def sby_models(out: Path):
    """.sby -> {태스크: 모델경로}. sby_sweep.sh 의 prefix 규약과 같은 규칙."""
    found = {}
    for f in sorted(SBY_DIR.glob("*/*.sby")):
        prefix = f"{f.parent.name}-{f.stem}"
        tasks = {}
        for m in sorted(out.glob(f"{prefix}*/model/design_prep.il")):
            d = m.parent.parent.name
            if d != prefix and not d.startswith(prefix + "_"):
                continue        # 접두가 겹치는 다른 .sby 를 삼키지 않는다
            tasks[d[len(prefix):].lstrip("_") or "(base)"] = m
        found[f.relative_to(ROOT).as_posix()] = tasks
    return found


def audit(out: Path, require_models: bool, as_json: bool) -> int:
    found = sby_models(out)
    counted, uncounted, offenders, agg = [], [], [], {
        "assert_cells": 0, "const_a": 0, "const_en0": 0, "en1": 0, "depth": 0,
        "unparsed": 0, "const_by_merge": 0}
    merged, gate_defects = [], []
    for rel, tasks in sorted(found.items()):
        if not tasks:
            uncounted.append(rel)
            continue
        for task, model in sorted(tasks.items()):
            r = scan_model(model)
            agg["assert_cells"] += r["assert_cells"]
            for k in ("const_en0", "en1", "unparsed"):
                agg[k] += r[k]
            agg["depth"] = max(agg["depth"], r["depth"])
            key = f"{rel}:{task}"
            counted.append(key)

            # 선-flatten 감사 모델 — 있으면 저작-항진과 병합-상수를 가른다
            # (`_CONST_BY_MERGE` 머리 주석). 없으면 종전 그대로: 접힘 전부가
            # 저작 혐의다. `const_a` 집계는 **저작 혐의분**이다 — 병합-상수를
            # 같은 칸에 합치면 머리줄의 「상수 A 0」이 두 뜻을 갖게 된다.
            pre = model.parent / "design_preflatten.il"
            if pre.is_file():
                rp = scan_model(pre)
                authored = rp["const_a"]
                by_merge = r["const_a"] - authored
                agg["const_a"] += authored
                if (authored or r["const_en0"]) and key not in _TAUTOLOGY:
                    # 저작-항진 — 병합 전 모델에서 이미 접혀 있었다.
                    offenders.append((key, dict(rp, const_en0=r["const_en0"])))
                elif by_merge < 0 and rp["assert_cells"] == r["assert_cells"]:
                    # 같은 단언 집합인데 병합 *후*가 더 적게 접혔다 — 산술이
                    # 서지 않는다. 게이트(감사 모델 배선)의 결함이지 대상의
                    # 결함이 아니다. (단언 수가 다른 것은 정상 — cover 모델은
                    # chformal 이 단언을 제거한다.)
                    gate_defects.append(
                        f"{key} — 선-flatten 접힘 {authored} > 후-flatten "
                        f"{r['const_a']} (단언 수 동일 {r['assert_cells']})")
                elif by_merge > 0:
                    agg["const_by_merge"] += by_merge
                    if key in _CONST_BY_MERGE:
                        merged.append((key, by_merge))
                    else:
                        offenders.append((key, dict(
                            r, _by_merge=by_merge, const_a=0)))
            else:
                agg["const_a"] += r["const_a"]
                if (r["const_a"] or r["const_en0"]) and key not in _TAUTOLOGY:
                    offenders.append((key, r))

    if as_json:
        print(json.dumps({"counted": len(counted), "uncounted": uncounted,
                          "offenders": [o[0] for o in offenders], **agg},
                         ensure_ascii=False, sort_keys=True))

    # 표 부패 — 사라진 태스크의 면제가 남으면 아무도 다시 읽지 않는다.
    for key in _TAUTOLOGY:
        if key.split(":")[0] not in found:
            _fail(f"_TAUTOLOGY 표가 부패했다 — {key} 의 .sby 가 없다. "
                  f"면제를 지워라")
    if len(_TAUTOLOGY) > _MAX_TAUTOLOGY:
        _fail(f"상수 접힘 래칫 위반 — {len(_TAUTOLOGY)} > {_MAX_TAUTOLOGY}. "
              f"면제를 늘리려면 근거와 함께 _MAX_TAUTOLOGY 를 올려라 (그것이 서명이다)")
    for key, val in _CONST_BY_MERGE.items():
        if key.split(":")[0] not in found:
            _fail(f"_CONST_BY_MERGE 표가 부패했다 — {key} 의 .sby 가 없다. "
                  f"항목을 지워라")
        if not isinstance(val, (tuple, list)) or len(val) != 2 or not all(
                isinstance(s, str) and s.strip() for s in val):
            _fail(f"_CONST_BY_MERGE 표의 {key} 에 (근거, 다른 수단) 두 문면이 "
                  f"없다 — 근거 없는 병합-상수는 저작-항진과 구별되지 않는다")
    if len(_CONST_BY_MERGE) > _MAX_CONST_BY_MERGE:
        _fail(f"병합-상수 래칫 위반 — {len(_CONST_BY_MERGE)} > "
              f"{_MAX_CONST_BY_MERGE}. 항목을 늘리려면 근거와 함께 "
              f"_MAX_CONST_BY_MERGE 를 올려라 (그것이 서명이다)")
    if gate_defects:
        _fail("선-flatten 감사 모델의 산술이 서지 않는 태스크가 있다 — "
              "**게이트의 결함**이지 대상의 결함이 아니다: "
              + " · ".join(gate_defects))

    if not as_json:
        # 미계수를 **머리줄 안에** 넣는다. 꼬리말로 붙이면 훑는 사람은 「상수 A
        # 0」만 읽고 「항진이 없다」로 가져간다 — 측정하지 않은 것을 측정해서
        # 0 이었던 것으로 읽는 그 형태다. 잰 것이 없으면 수를 앞세우지 않는다.
        scope = (f"{len(counted)}태스크" if not uncounted else
                 f"{len(counted)}태스크 (**미계수 {len(uncounted)}** — 아래)")
        print(f"상수 접힘 검사: {scope}에서 $assert "
              f"{agg['assert_cells']}셀 — 상수 A(저작) {agg['const_a']} · "
              f"상수 EN0 {agg['const_en0']} (무조건 단언 {agg['en1']}건은 정상) "
              f"· 병합-상수 {agg['const_by_merge']} (≤표 {_MAX_CONST_BY_MERGE}) "
              f"· 별칭 추적 깊이 {agg['depth']}단 (래칫 면제≤{_MAX_TAUTOLOGY})")
        print("  ※ yosys 가 접을 수 있는 부류만이다 — 의미적 동치와 assume 아래의 "
              "항진은 접히지 않는다. 3형은 열린 채다")
        if agg["unparsed"]:
            print(f"  ⚠ 해석하지 못한 결선/피연산자 {agg['unparsed']}건 — 그 뒤의 "
                  f"상수 결속은 **보지 못했다**. 위 계수 0 은 그만큼 약하다. "
                  f"parse_sigspec 를 넓혀라", file=sys.stderr)
        # 병합-상수 — 하드 실패가 아니라 **근거 있는 기록**이다. 계수와 근거를
        # 매번 인쇄한다 (`_STRUCTURAL` 의 「안 잰다」 칸과 같은 성격 — 숫자를
        # 침묵시키면 다음 사람이 이 접힘을 저작-항진으로 오독하거나, 반대로
        # 저작-항진을 병합으로 오독한다).
        for key, n in merged:
            why, other = _CONST_BY_MERGE[key]
            print(f"  병합-상수 {key} — {n}건 (선-flatten 감사 모델에서 저작 0 "
                  f"실측)")
            print(f"      근거: {why}")
            print(f"      그래도 재는 수단: {other}")

    for key, r in offenders:
        if "_by_merge" in r:
            print(f"  FAIL {key} — 병합-상수 {r['_by_merge']}건이 "
                  f"_CONST_BY_MERGE 표에 없다", file=sys.stderr)
            continue
        print(f"  FAIL {key} — 상수 A {r['const_a']} · 상수 EN0 "
              f"{r['const_en0']}", file=sys.stderr)
        for x in r["detail"][:8]:
            why = ("설계와 무관하게 늘 참" if x["port"] == "A" and
                   x["value"].endswith("1") else
                   "늘 거짓" if x["port"] == "A" else "영영 비활성")
            print(f"      {x['cell']}  {x['port']}={x['value']} ({why})"
                  f"  @ {x['src']}", file=sys.stderr)
    if offenders:
        _fail(f"상수로 접힌 단언이 {len(offenders)}태스크에 있다 — 저작-항진"
              f"(설계와 무관하게 참이거나 영영 비활성)이거나 미등재 병합-상수다. "
              f"단언을 고치거나, 저작-항진은 _TAUTOLOGY 에(_MAX_TAUTOLOGY 서명), "
              f"병합-상수는 선-flatten 감사 모델과 함께 _CONST_BY_MERGE 에"
              f"(_MAX_CONST_BY_MERGE 서명) 근거를 들어 등재하라")

    if uncounted:
        # 「없다」와 「없는 곳을 봤다」를 가른다 — 이 파일의 알맹이.
        head = ", ".join(uncounted[:3]) + (" …" if len(uncounted) > 3 else "")
        if require_models:
            _fail(f"미계수 {len(uncounted)}건 — {out} 에 모델이 없다 ({head}). "
                  f"**게이트의 결함**이지 대상의 결함이 아니다. 상수 0 이 아니라 "
                  f"세지 못한 것이다. 스윕을 고쳐라")
        print(f"  ⚠ 미계수 {len(uncounted)}건 — 모델이 없다 ({head}). "
              f"상수 0 이 아니라 **세지 못했다**. 재려면: make rtl-postformal")
    return 0


def main() -> None:
    ap = argparse.ArgumentParser(add_help=True, description=__doc__)
    ap.add_argument("--count", nargs="+", metavar="IL",
                    help="모델을 세어 JSON 으로 (sby_sweep.sh 전용)")
    ap.add_argument("--audit", action="store_true",
                    help="저장소의 .sby 전수에 대해 감사 (기본)")
    ap.add_argument("--require-models", action="store_true",
                    help="모델이 없으면 하드 실패 — 스윕 직후 자기검사용")
    ap.add_argument("--self-test", action="store_true",
                    help="양성 대조 — 일부러 심은 상수 접힘이 실제로 잡히는지")
    ap.add_argument("--out", default=os.environ.get("SBY_OUT", "/tmp/wt-sby-out"),
                    help="sby 산출물 디렉터리 (기본 $SBY_OUT 또는 /tmp/wt-sby-out)")
    ap.add_argument("--json", action="store_true", help="기계용 출력")
    a = ap.parse_args()

    if a.count:
        print(json.dumps(scan_models([Path(p) for p in a.count]),
                         ensure_ascii=False, sort_keys=True))
        return

    # 양성 대조는 **언제나, 감사보다 먼저** 돈다. 조건부로 두지 않는 것이
    # 요점이다 — 검사가 죽어 있으면 계수 0 은 「접힘이 없다」가 아니라
    # 「보지 못했다」이고, 그 둘을 가르는 것이 이 순서다. 3차가 「cover == 0」을
    # 항등 검사보다 앞에 세운 것과 같은 함정이다.
    print("상수 접힘 검사 — 양성 대조:")
    if not self_test():
        _fail("양성 대조 실패 — 일부러 심은 상수 접힘을 잡지 못했다. "
              "계수 0 은 「접힘이 없다」가 아니라 「검사가 죽었다」다")
    if a.self_test and not a.audit:
        print("  양성 대조 통과 (모델 없이도 뜻이 있는 유일한 부분)")
        return

    sys.exit(audit(Path(a.out), a.require_models, a.json))


if __name__ == "__main__":
    main()
