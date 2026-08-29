#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""생성 case-body 를 소비하는 `case` 선택자의 **폭 일치** 검사 (W2 파도).

## 왜 이 검사가 있는가

Verilog `case` 는 선택자와 arm 라벨의 폭이 다르면 **좁은 쪽을
zero-extend** 해서 조용히 비교한다. 인코딩 개정 파도 W1 이 opcode 를
12비트로 올리면서 생성 case body 의 arm 은 전부 `12'h###` 가 됐는데,
소비자가 종전대로 8비트 선택자(`case (cb_opcode)`)를 쓰면 `0x47B` 가
`{4'h0, 8'h7B}` 로 확장돼 **`12'h07B` arm 에 적중한다.** 확장 니블이
접히고, 디코더는 확장 영역 명령을 기본 영역 명령으로 판정한다 —
컴파일도 시뮬도 조용하다 (verilator 는 WIDTHEXPAND 경고 하나뿐이고
그 경고는 waive 가능하다).

`scripts/gen_isa_tables.py` 가 이미 **컴파일 강제 가드**를 심어 두었다:
case body 첫 arm `(~{cb_opcode_ext, cb_opcode}): ;` 는 어떤 선택자 값과도
매치되지 않지만 확장 니블 식별자를 *참조*하므로, 그것을 결선하지 않은
소비자는 컴파일이 깨진다. 그러나 그 가드가 강제하는 것은
**「식별자가 선언돼 있는가」뿐**이다:

  - 니블을 선언만 하고 선택자는 8비트로 두면 → 가드 arm 은 컴파일되고
    나머지 arm 은 그대로 접힌다.
  - 니블을 선언하고 선택자에 `{4'h0, cb_opcode}` 처럼 **상수로 묶어**
    넣으면 폭은 12비트인데 확장 니블은 여전히 죽어 있다.
  - 선택자 문면은 맞는데 니블의 **선언 폭**이 좁으면(예 `[1:0]`)
    연접 총폭이 12에 못 미쳐 다시 zero-extend 가 일어난다.

가드는 **필요조건이지 충분조건이 아니다.** 이 lint 가 남은 셋을 닫는다.

## 무엇을 대조하는가

원천은 전부 *생성 산출물*(clean)이다 — 이 파일은 폭 12 도, 선택자 문면도
하드코딩하지 않는다. 파도가 폭을 다시 올리면 생성기 한 곳만 고치면 된다.

  (1) arm 폭 N        ← case body 의 sized-literal arm 라벨 (전부 동일해야)
  (2) 규정 선택자 S   ← W2 가드 arm `(~S): ;` 의 피연산자
  (3) 소비자 전수     ← case body 를 `` `include `` 하는 Verilog 파일
  (4) 소비자마다: include 가 `case`…`endcase` **안**에 있는가
  (5) 소비자마다: 그 `case` 의 선택자 문면 == S (공백 무시)
  (6) 소비자마다: 그 선택자의 **선언 해석 폭** == N

(5) 와 (6) 은 서로를 덮지 못한다. (5) 는 `{4'h0, cb_opcode}` 를 잡지만
선언 폭 협소화를 못 잡고, (6) 은 그 반대다. 둘 다 있어야 닫힌다.

## 재지 못하는 것 (명기한다)

  - **case-body 밖의 접힘.** 상위 계층이 명령 워드에서 opcode 하위
    8비트만 뽑아 비교하는 부류는 이 검사의 정의역이 아니다 — 그 축은
    시뮬 층의 상주 시험이 진다.
  - **선택자가 뜻이 있는가.** 폭과 문면이 맞아도 그 신호가 진짜 명령
    워드에서 왔는지는 재지 않는다.
  - 이 검사는 **텍스트 스캐너**다 (`scripts/lint_frag_total_m1_held.py` ·
    `scripts/lint_output_payload_hold.py` 의 선례). 전체 Verilog 파서가
    아니라 이 저장소의 일관된 문법에 충분한 만큼만 판다.

## 진단 출력 규약 (clean-room)

실패 진단은 **경로 · 줄번호 · 폭(수치) · 생성 산출물에서 온 이름**만
인쇄한다. 소비자 소스의 본문을 절대 인용하지 않는다 — 이 lint 는
에어락 밖에서 작성·유지되고, 진단이 소스를 옮기면 그 자체가 오염
경로가 되기 때문이다.

## 음성 시험 (이 검사를 결선하기 전에 통과시킨 것)

`--self-test` 가 두 층을 돈다 — 저장소를 더럽히지 않는다.

  A. 합성 픽스처 7종 (/tmp) — 검출기 논리 자체의 반증력
     ① 8b 선택자                     → 폭 불일치로 FAIL
     ② `{4'h0, cb_opcode}` 상수 묶기 → 문면 불일치로 FAIL (폭은 12)
     ③ 확장 니블 선언 `[3:0]`→`[1:0]` → 폭 불일치로 FAIL (문면은 일치)
     ④ arm 을 `8'h##` 로 되돌림       → arm/선택자 폭 불일치로 FAIL
     ⑤ include 를 case 밖으로          → 전제 소실로 FAIL
     ⑥ W2 가드 arm 삭제                → 규정 선택자 부재로 FAIL
     ⑦ 소비자 0건                      → 공허로 FAIL
  B. 실 트리 사본 2종 — 검출기가 *이 저장소*에 실제로 물려 있는가
     ⑧ 실 소비자의 선택자를 8b 로      → FAIL
     ⑨ 실 확장 니블 선언을 1비트로     → FAIL

    scripts/lint_case_selector_width.py             검사
    scripts/lint_case_selector_width.py --self-test 음성 시험
"""
import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

DEFAULT_ROOT = Path(__file__).resolve().parent.parent
ARTIFACT_REL = "include/generated/isa_ehshape_case_body.vh"

SCAN_SUFFIXES = (".v", ".sv", ".svh", ".vh")
SKIP_DIR_NAMES = {".git", "sim_build", "obj_dir", "__pycache__", "node_modules",
                  ".venv", "venv", "build"}

TAG = "lint_case_selector_width"


class Fail(Exception):
    pass


# ---------------------------------------------------------------------------
# 어휘 층 — 길이 보존 마스킹 (오프셋이 곧 줄번호가 되도록)
# ---------------------------------------------------------------------------

def mask(src: str, strings: bool) -> str:
    """주석(항상)과 문자열 리터럴(strings=True)을 공백으로 덮되 **길이와
    줄바꿈을 보존**한다. 오프셋이 원본과 1:1 이라 줄번호 환산이 정확하다."""
    out = list(src)
    i, n, state = 0, len(src), None
    while i < n:
        c = src[i]
        if state is None:
            if c == "/" and i + 1 < n and src[i + 1] == "/":
                out[i] = out[i + 1] = " "
                state, i = "line", i + 2
                continue
            if c == "/" and i + 1 < n and src[i + 1] == "*":
                out[i] = out[i + 1] = " "
                state, i = "block", i + 2
                continue
            if c == '"' and strings:
                out[i] = " "
                state, i = "str", i + 1
                continue
            i += 1
        elif state == "line":
            if c == "\n":
                state = None
            else:
                out[i] = " "
            i += 1
        elif state == "block":
            if c == "*" and i + 1 < n and src[i + 1] == "/":
                out[i] = out[i + 1] = " "
                state, i = None, i + 2
                continue
            if c != "\n":
                out[i] = " "
            i += 1
        else:  # str
            if c == "\\" and i + 1 < n:
                out[i] = " "
                out[i + 1] = "\n" if src[i + 1] == "\n" else " "
                i += 2
                continue
            if c == '"':
                out[i] = " "
                state = None
            elif c != "\n":
                out[i] = " "
            i += 1
    return "".join(out)


def lineno(text: str, off: int) -> int:
    return text.count("\n", 0, off) + 1


# ---------------------------------------------------------------------------
# 생성 산출물에서 규범을 읽는다 (폭도 문면도 하드코딩하지 않는다)
# ---------------------------------------------------------------------------

_ARM = re.compile(r"^\s*(\d+)'[sS]?[hHbBdDoO][0-9a-fA-FxXzZ_?]+\s*:", re.M)
_GUARD = re.compile(r"\(\s*~\s*(\{[^{}]*\})\s*\)\s*:")


def read_norm(artifact: Path):
    """(arm 폭 N, 규정 선택자 S, arm 개수) — 전부 생성 산출물에서."""
    if not artifact.is_file():
        raise Fail(f"생성 case body 부재: {artifact} — 커밋된 산출물이다 "
                   f"(scripts/gen_isa_tables.py generate)")
    body = mask(artifact.read_text(encoding="utf-8"), strings=True)

    widths = {int(m.group(1)) for m in _ARM.finditer(body)}
    arms = len(_ARM.findall(body))
    if not widths:
        raise Fail("case body 에 sized-literal arm 이 0건 — 산출물 형상이 "
                   "바뀌었거나 파싱이 깨졌다 (공허 방지 앵커)")
    if len(widths) != 1:
        raise Fail(f"case body 의 arm 폭이 섞였다: {sorted(widths)} — "
                   f"zero-extension 이 어느 폭 기준인지 정의되지 않는다")
    if arms < 2:
        raise Fail(f"case body arm 이 {arms}건뿐 — 파싱 붕괴 의심 (공허 방지)")

    g = _GUARD.search(body)
    if not g:
        raise Fail("W2 컴파일 강제 가드 `(~{...}): ;` 가 case body 에 없다 — "
                   "규정 선택자의 authority 가 사라졌다 "
                   "(scripts/gen_isa_tables.py emit_case_body)")
    return widths.pop(), g.group(1), arms


# ---------------------------------------------------------------------------
# 소비자 전수 — case body 를 include 하는 Verilog 파일
# ---------------------------------------------------------------------------

def verilog_files(root: Path):
    for p in sorted(root.rglob("*")):
        if p.suffix not in SCAN_SUFFIXES or not p.is_file():
            continue
        if SKIP_DIR_NAMES & set(p.relative_to(root).parts[:-1]):
            continue
        yield p


def find_consumers(root: Path, artifact: Path):
    base = artifact.name
    inc = re.compile(r"`include\s+\"([^\"]*" + re.escape(base) + r")\"")
    hits = []
    for p in verilog_files(root):
        if p.resolve() == artifact.resolve():
            continue
        raw = p.read_text(encoding="utf-8", errors="replace")
        code = mask(raw, strings=False)   # 문자열은 남긴다 — include 경로가 문자열이다
        for m in inc.finditer(code):
            hits.append((p, m.start(), raw))
    return hits


# ---------------------------------------------------------------------------
# case 블록 지도 · 선택자 추출
# ---------------------------------------------------------------------------

_CASE_TOK = re.compile(r"\b(endcase|casex|casez|case)\b")


def case_blocks(code: str):
    """(case 키워드 오프셋, endcase 오프셋) 목록 — 토큰 스택."""
    stack, blocks = [], []
    for m in _CASE_TOK.finditer(code):
        if m.group(1) == "endcase":
            if stack:
                blocks.append((stack.pop(), m.start()))
        else:
            stack.append(m.start())
    while stack:                      # 불균형 잔여는 EOF 에서 닫는다 (방어)
        blocks.append((stack.pop(), len(code)))
    return blocks


def selector_span(code: str, case_off: int):
    """`case` 키워드 뒤 괄호쌍 안쪽의 (start, end). 못 찾으면 None."""
    i = code.find("(", case_off)
    if i < 0:
        return None
    depth, j = 0, i
    while j < len(code):
        if code[j] == "(":
            depth += 1
        elif code[j] == ")":
            depth -= 1
            if depth == 0:
                return i + 1, j
        j += 1
    return None


def norm_expr(e: str) -> str:
    return re.sub(r"\s+", "", e)


# ---------------------------------------------------------------------------
# 선언 폭 해석
# ---------------------------------------------------------------------------

_DECL_KW = re.compile(r"\b(?:input|output|inout|wire|reg|logic|bit)\b")
_RANGE = re.compile(r"\[([^\[\]:]+):([^\[\]:]+)\]")
_PARAM = re.compile(r"\b(?:parameter|localparam)\b[^;]*?\b([A-Za-z_]\w*)\s*=\s*"
                    r"([0-9][0-9_]*)\b")
_SIZED = re.compile(r"^(\d+)'[sS]?[hHbBdDoO][0-9a-fA-FxXzZ_?]+$")
_BITSEL = re.compile(r"^([A-Za-z_]\w*)\s*\[([^\[\]:]+)\]$")
_PARTSEL = re.compile(r"^([A-Za-z_]\w*)\s*\[([^\[\]:]+):([^\[\]:]+)\]$")
_IDENT = re.compile(r"^[A-Za-z_]\w*$")


def const_env(code: str):
    env = {}
    for m in _PARAM.finditer(code):
        env.setdefault(m.group(1), int(m.group(2).replace("_", "")))
    return env


def const_eval(expr: str, env):
    """숫자 · 표에 있는 파라미터 이름 · + - * / ( ) 만 허용."""
    e = expr.strip()
    if not re.fullmatch(r"[0-9A-Za-z_+\-*/() \t]*", e) or not e:
        return None
    toks = set(re.findall(r"[A-Za-z_]\w*", e))
    if not toks <= set(env):
        return None
    try:
        return int(eval(e, {"__builtins__": {}}, dict(env)))  # noqa: S307
    except Exception:
        return None


def decl_width(name: str, code: str, env):
    """(폭, 선언 줄번호) 또는 (None, 사유). 선언 줄을 인용하지 않는다."""
    found = []
    for idx, line in enumerate(code.splitlines(), 1):
        if not re.search(r"\b" + re.escape(name) + r"\b", line):
            continue
        if not _DECL_KW.search(line):
            continue
        # 대입/비교문에 우연히 키워드가 섞이는 경우를 배제
        if re.search(r"[<>=!]=|<=|\bassign\b", line) and "," not in line:
            if not re.search(r"\b(?:input|output|inout|wire|reg|logic|bit)\b\s*"
                             r"(?:\[[^\]]*\]\s*)?" + re.escape(name) + r"\b", line):
                continue
        r = _RANGE.search(line)
        if r is None:
            found.append((1, idx))
            continue
        hi, lo = const_eval(r.group(1), env), const_eval(r.group(2), env)
        if hi is None or lo is None:
            return None, f"선언 범위를 상수로 풀 수 없다 (줄 {idx})"
        found.append((abs(hi - lo) + 1, idx))
    if not found:
        return None, "선언을 찾지 못했다"
    widths = {w for w, _ in found}
    if len(widths) != 1:
        return None, (f"선언이 여러 폭으로 보인다: {sorted(widths)} "
                      f"(줄 {sorted(l for _, l in found)})")
    return found[0][0], found[0][1]


def expr_width(expr: str, code: str, env):
    """(폭, None) 또는 (None, 사유). 인용하는 이름은 전부 규정 선택자
    (생성 산출물 출처)에서 온 것이므로 진단에 실어도 오염이 아니다."""
    e = expr.strip()
    if e.startswith("{") and e.endswith("}"):
        inner, parts, depth, cur = e[1:-1], [], 0, ""
        for ch in inner:
            if ch in "{([":
                depth += 1
            elif ch in "})]":
                depth -= 1
            if ch == "," and depth == 0:
                parts.append(cur)
                cur = ""
            else:
                cur += ch
        parts.append(cur)
        total = 0
        for p in parts:
            w, why = expr_width(p, code, env)
            if w is None:
                return None, why
            total += w
        return total, None

    e = norm_expr(e)
    if not e:
        return None, "빈 피연산자"
    m = _SIZED.match(e)
    if m:
        return int(m.group(1)), None
    m = _PARTSEL.match(e)
    if m:
        hi, lo = const_eval(m.group(2), env), const_eval(m.group(3), env)
        if hi is None or lo is None:
            return None, f"부분선택 범위를 상수로 풀 수 없다: {m.group(1)}[…]"
        return abs(hi - lo) + 1, None
    m = _BITSEL.match(e)
    if m:
        return 1, None
    if _IDENT.match(e):
        w, info = decl_width(e, code, env)
        if w is None:
            return None, f"`{e}` — {info}"
        return w, None
    return None, "해석할 수 없는 피연산자 형태"


# ---------------------------------------------------------------------------
# 본 검사
# ---------------------------------------------------------------------------

def analyze(root: Path):
    """진단 목록과 관측 사실을 돌려준다. 예외 Fail = 전제 붕괴."""
    artifact = root / ARTIFACT_REL
    arm_w, sel_norm_src, arms = read_norm(artifact)
    want = norm_expr(sel_norm_src)

    consumers = find_consumers(root, artifact)
    if not consumers:
        raise Fail(f"{ARTIFACT_REL} 를 include 하는 Verilog 소비자가 0건 — "
                   f"이 검사가 공허해졌다 (경로 표기가 바뀌었거나 소비자가 "
                   f"사라졌다)")

    problems, observed = [], []
    for path, inc_off, raw in consumers:
        rel = path.relative_to(root).as_posix()
        code = mask(raw, strings=True)
        env = const_env(code)
        blocks = [(b, e) for b, e in case_blocks(code) if b <= inc_off <= e]
        if not blocks:
            problems.append(
                f"{rel}:{lineno(raw, inc_off)} — include 가 case…endcase "
                f"안에 있지 않다: 폭 강제의 전제가 사라졌다")
            continue
        b, _e = max(blocks, key=lambda t: t[0])       # 최내곽
        span = selector_span(code, b)
        if span is None:
            problems.append(f"{rel}:{lineno(raw, b)} — case 선택자 괄호를 "
                            f"찾지 못했다")
            continue
        s, t = span
        got = norm_expr(code[s:t])
        ln = lineno(raw, b)
        if got != want:
            w, why = expr_width(code[s:t], code, env)
            wtxt = f"폭 {w}" if w is not None else f"폭 미해석({why})"
            problems.append(
                f"{rel}:{ln} — case 선택자가 규정 형태와 다르다 "
                f"(규정 `{sel_norm_src}` = {arm_w}b, 실물 {wtxt}). "
                f"arm 은 {arm_w}b 이므로 좁은 선택자는 zero-extend 로 "
                f"조용히 매치되고 상위 니블이 접힌다")
            continue
        w, why = expr_width(code[s:t], code, env)
        if w is None:
            problems.append(f"{rel}:{ln} — 선택자 폭을 해석하지 못했다: {why} "
                            f"(해석 불가는 통과가 아니다 — 공허 금지)")
            continue
        if w != arm_w:
            why_dir = ("문면은 규정과 같으나 **선언 폭**이 좁다 — 좁은 쪽이 "
                       "zero-extend 되어 상위 니블이 접힌다"
                       if w < arm_w else
                       "문면은 규정과 같으나 **arm 이 좁다** — 생성기가 "
                       "폭을 되돌렸다면 arm 라벨이 zero-extend 되어 "
                       "상위 니블이 무시된다")
            problems.append(
                f"{rel}:{ln} — 선택자 폭 {w}b != case arm 폭 {arm_w}b. "
                f"{why_dir}")
            continue
        observed.append((rel, ln, w))
    return arm_w, arms, sel_norm_src, observed, problems


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--root", default=str(DEFAULT_ROOT))
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args(argv)

    if args.self_test:
        return self_test()

    root = Path(args.root).resolve()
    try:
        arm_w, arms, sel, observed, problems = analyze(root)
    except Fail as e:
        print(f"{TAG}: FAIL — {e}", file=sys.stderr)
        return 1

    if problems:
        print(f"{TAG}: FAIL — case 선택자 폭 위반:", file=sys.stderr)
        for p in problems:
            print(f"  {p}", file=sys.stderr)
        print(f"{TAG}: 규정 선택자 `{sel}` (생성 case body 의 W2 가드 arm "
              f"에서 읽었다) · arm 폭 {arm_w}b", file=sys.stderr)
        return 1

    print(f"{TAG}: OK — case body arm {arms}건 전부 {arm_w}b · 소비자 "
          f"{len(observed)}건 전부 규정 선택자 `{sel}` 를 {arm_w}b 로 편다")
    for rel, ln, w in observed:
        print(f"  {rel}:{ln} — 선택자 {w}b ✓")
    return 0


# ---------------------------------------------------------------------------
# 음성 시험
# ---------------------------------------------------------------------------

_FIX_ARTIFACT = """\
// GENERATED by scripts/gen_isa_tables.py from isa/wt64v1_isa.json
// One case arm per opcode.
            // W2 GATE (compile-forcing)
            (~{cb_opcode_ext, cb_opcode}): ;  // never matches
            12'h000: begin  // NOP
                ;
            end
            12'h001: begin  // WADV
                ;
            end
            default: begin
                ;
            end
"""

_FIX_CONSUMER = """\
// fixture consumer
module Fixture (
    input  wire [3:0] cb_opcode_ext,
    input  wire [7:0] cb_opcode,
    output reg        legal
);
    always @* begin
        legal = 1'b0;
        case ({cb_opcode_ext, cb_opcode})
`include "generated/isa_ehshape_case_body.vh"
        endcase
    end
endmodule
"""

# (이름, 산출물 치환 또는 None, 소비자 치환 또는 None)
_FIXTURE_MUTATIONS = [
    ("① 8b 선택자", None,
     ("case ({cb_opcode_ext, cb_opcode})", "case (cb_opcode)")),
    ("② 상수 묶기 {4'h0, cb_opcode}", None,
     ("case ({cb_opcode_ext, cb_opcode})", "case ({4'h0, cb_opcode})")),
    ("③ 확장 니블 선언 [3:0]→[1:0]", None,
     ("input  wire [3:0] cb_opcode_ext", "input  wire [1:0] cb_opcode_ext")),
    ("④ arm 을 8'h## 로 되돌림",
     [("12'h000:", "8'h00:"), ("12'h001:", "8'h01:")], None),
    ("⑤ include 를 case 밖으로", None,
     ("        case ({cb_opcode_ext, cb_opcode})\n"
      "`include \"generated/isa_ehshape_case_body.vh\"\n"
      "        endcase\n",
      "        case ({cb_opcode_ext, cb_opcode})\n"
      "            default: ;\n"
      "        endcase\n"
      "`include \"generated/isa_ehshape_case_body.vh\"\n")),
    ("⑥ W2 가드 arm 삭제",
     [("            (~{cb_opcode_ext, cb_opcode}): ;  // never matches\n", "")],
     None),
    ("⑦ 소비자 0건", None,
     ("`include \"generated/isa_ehshape_case_body.vh\"", "            ;")),
]


def _run(root: Path):
    return subprocess.run(
        [sys.executable, str(Path(__file__).resolve()), "--root", str(root)],
        capture_output=True, text=True)


def _plant(base: Path, artifact: str, consumer: str):
    (base / "include" / "generated").mkdir(parents=True, exist_ok=True)
    (base / ARTIFACT_REL).write_text(artifact, encoding="utf-8")
    (base / "Fixture.v").write_text(consumer, encoding="utf-8")


def _fixture_layer() -> bool:
    ok = True
    with tempfile.TemporaryDirectory(prefix="wt-casesel-fix-") as td:
        base = Path(td) / "repo"
        _plant(base, _FIX_ARTIFACT, _FIX_CONSUMER)
        r = _run(base)
        if r.returncode != 0:
            print("  양성 대조 불통과 — 변이 없는 픽스처가 이미 실패한다:")
            print(r.stdout + r.stderr)
            return False
        print("  양성 대조: 변이 없는 픽스처는 통과한다 ✓")
        for name, art_muts, con_mut in _FIXTURE_MUTATIONS:
            art, con = _FIX_ARTIFACT, _FIX_CONSUMER
            miss = False
            for a, b in (art_muts or []):
                if a not in art:
                    miss = True
                art = art.replace(a, b, 1)
            if con_mut:
                a, b = con_mut
                if a not in con:
                    miss = True
                con = con.replace(a, b, 1)
            if miss:
                print(f"  {name}: 변이 지점을 찾지 못했다")
                ok = False
                continue
            _plant(base, art, con)
            r = _run(base)
            if r.returncode == 0:
                print(f"  {name}: **검사가 잡지 못했다** (공허한 검사다)")
                ok = False
            else:
                lines = (r.stderr or "").splitlines()
                detail = next((l.strip() for l in lines
                               if l.startswith("  ") and TAG not in l), "")
                if not detail:
                    detail = next((l.split("FAIL — ", 1)[-1] for l in lines
                                   if f"{TAG}: FAIL" in l), "")
                print(f"  {name}: FAIL 확인 ✓ — {detail[:110]}")
    return ok


def _real_tree_layer() -> bool:
    """실 트리의 소비자를 격리 사본으로 옮겨 두 변이를 건다. 소비자
    본문은 **오프셋으로만** 다루고 인쇄하지 않는다 (clean-room)."""
    root = DEFAULT_ROOT
    artifact = root / ARTIFACT_REL
    try:
        arm_w, _sel_src, _ = read_norm(artifact)
    except Fail as e:
        print(f"  실 트리 층 생략 — {e}")
        return True
    consumers = find_consumers(root, artifact)
    if not consumers:
        print("  실 트리 층: 소비자 0건 — 본 검사가 이미 FAIL 이다")
        return False

    ok = True
    with tempfile.TemporaryDirectory(prefix="wt-casesel-real-") as td:
        base = Path(td) / "repo"
        (base / "include" / "generated").mkdir(parents=True, exist_ok=True)
        shutil.copy2(artifact, base / ARTIFACT_REL)
        rels = []
        for path, _off, _raw in consumers:
            rel = path.relative_to(root)
            (base / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, base / rel)
            rels.append(rel)
        r = _run(base)
        if r.returncode != 0:
            print("  실 트리 양성 대조 불통과 — 사본이 이미 실패한다 "
                  "(본 검사가 FAIL 이라는 뜻)")
            return False
        print(f"  실 트리 양성 대조: 소비자 {len(rels)}건 사본 통과 ✓")

        # ⑧ 선택자를 하위 8비트만으로 좁힌다 (연접의 마지막 항만 남긴다).
        pristine = {rel: (base / rel).read_text(encoding="utf-8") for rel in rels}
        target = rels[0]
        raw = pristine[target]
        code = mask(raw, strings=True)
        inc_off = next(o for p, o, _ in consumers
                       if p.relative_to(root) == target)
        blocks = [(b, e) for b, e in case_blocks(code) if b <= inc_off <= e]
        b = max(blocks, key=lambda t: t[0])[0]
        s, t = selector_span(code, b)
        sel_txt = code[s:t]
        parts = norm_expr(sel_txt).strip("{}").split(",")
        (base / target).write_text(raw[:s] + parts[-1] + raw[t:],
                                   encoding="utf-8")
        r = _run(base)
        if r.returncode == 0:
            print("  ⑧ 실 선택자를 8b 로: **검사가 잡지 못했다**")
            ok = False
        else:
            print(f"  ⑧ 실 선택자를 하위 항 하나로 좁힘: FAIL 확인 ✓ "
                  f"(arm {arm_w}b)")
        (base / target).write_text(raw, encoding="utf-8")

        # ⑨ 연접 첫 항의 **선언 폭**을 1비트로 줄인다 (문면은 그대로).
        env = const_env(code)
        first = parts[0]
        w, info = decl_width(first, code, env)
        if w is None:
            print(f"  ⑨ 생략 — 선언 폭 해석 불가 ({info})")
        else:
            dline = info
            lines = raw.splitlines(keepends=True)
            lines[dline - 1] = _RANGE.sub("[0:0]", lines[dline - 1], count=1)
            (base / target).write_text("".join(lines), encoding="utf-8")
            r = _run(base)
            if r.returncode == 0:
                print("  ⑨ 확장 니블 선언 1비트화: **검사가 잡지 못했다**")
                ok = False
            else:
                print(f"  ⑨ 연접 첫 항 선언을 1비트로: FAIL 확인 ✓ "
                      f"(원 폭 {w}b)")
            (base / target).write_text(raw, encoding="utf-8")
    return ok


def self_test() -> int:
    print(f"{TAG} --self-test")
    print(" A. 합성 픽스처 층")
    a = _fixture_layer()
    print(" B. 실 트리 층")
    b = _real_tree_layer()
    ok = a and b
    print("음성 시험 " + ("통과 — 아홉 변이 전부 잡힌다" if ok else "불통과"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
