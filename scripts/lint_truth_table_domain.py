#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""오라클 신선도 — **정의역** 축. 그리고 동결 표의 바이트 불변.

## 왜 이 검사가 있는가

`isa/truth_table_encwave.json` 은 **clean-room 오라클**이다 (재구현 메모
`.claude-memories/wt64v1_rtl_reimplementation.md`: 「현행 오라클은
`isa/truth_table_encwave.json`」). RTL 전면 재구현이 이 표를 블랙박스
오라클로 쓴다. 낡은 오라클은 틀린 인코딩을 승인하고, 그것은 실패가 아니라
**침묵**으로 나타난다.

먼저 **틀린 걱정 하나를 치운다** (실측 2026-08-30). 「Python 어셈블러가
동결되지 않았으므로 그 산출물인 오라클이 낡는다」는 구조적으로 성립하지
않는다 —

  · 이 표가 담는 것은 판정 **3비트뿐**(err/lwr/out)이고 **인코딩은 한
    비트도 담기지 않는다.** 저장소 자신의 실측이 그렇게 적었다
    (`test_isa_decoder.py` 머리주석 · `c682acd`): 인코딩 파도가 5,796 점의
    바이너리를 전부 바꿨는데 outcome 은 5,934/5,934 **동일**했다.
  · 그러므로 인코딩 지문을 이 표에 대해 재는 것은 0 비트짜리 검사다.

낡을 수 있는 것은 판정이 아니라 **정의역**이다. 그리고 그 축에는
2026-08-30 까지 게이트가 하나도 없었다:

  · 캡처 도메인 `_TT_SUPPORTED_OPCODES` · `_TT_UNSUPPORTED_PROBES` 는
    **손으로 박은 리터럴**이고, 머리주석이 「generator-independent — never
    derived from the JSON source」라고 **일부러** 그렇게 못박았다 (§23.9
    순환성 차단기). 그 차단기는 옳다 — 그러나 그 대가로 두 선언이 갈라져도
    아무도 울지 않는다.
  · `isa/wt64v1_isa.json` 에 새 opcode 가 0x07 로 태어나면
    `gen_isa_tables --check` 는 통과하고(그것의 정의역은 생성 ISA 표다),
    캡처 도메인은 상수라 자라지 않고, 차등 시험의
    `extra = set(got) - set(frozen)` 은 `got` 이 못 자라므로 **영원히
    공집합**이다. ⇒ 그 opcode 는 **오라클에 한 점도 없이 태어난다.**
  · 반대 방향도 조용하다. 오늘 `_TT_UNSUPPORTED_PROBES` 에 든 코드점에
    ISA 가 명령을 배정하면(0x6B 이 실제로 그랬다 — `GAMMA_MUL_W`), 점은
    있는데 그 점의 **outcome 계급이 낡는다.** 그때 필요한 것은 도메인
    확장이 아니라 **재캡처**이고, 그 필요를 오늘은 사람이 기억해야 한다.

⇒ 이 검사는 그 셋을 기계로 잰다. RTL 을 태우지 않는다 — cocotb 불요,
   stdlib 전용, 실측 0.05 초 미만이라 `make lint` 안에 산다.

## ⚠️ 두 표는 **다른 종류**다 — 이 구분이 이 파일의 자료구조에 있다

    CURRENT = ORACLE                 재생성 대상 (심의된 재캡처로 정당하게 움직인다)
    FROZEN  = {경로: (알고리즘, 해시, dv)}    **불변 대상** (정의상 안 움직인다)

`isa/truth_table_premigration.json` 은 「이관 전 계보 전용」으로 좁아진
**동결 산출물**이다. 현행 인코딩 바이너리를 이 표에 걸면 전량 불일치한다.
순진한 게이트가 두 표를 다 「갱신」하려 들면 **계보 증거를 파괴한다.**
그래서 구분을 산문이 아니라 **자료구조**가 나른다:

  · `FROZEN` 은 dict(경로→해시)이고 `ORACLE` 은 Path 다. 형이 다르다.
  · 아래 ⓪ 이 `ORACLE in FROZEN` 을 **실패**로 만든다 — 핀을 재생성 대상에
    겨누는 것은 오조준이지 갱신이 아니다.
  · 아래 ⓪ 이 **이 스크립트 자신의 AST** 를 훑어 `FROZEN` 을 참조하는
    쓰기 호출이 없음을 강제한다. 「읽기만 한다」가 주석이 아니라 집행이다.

그리고 **encwave 에는 해시 핀을 걸지 않는다.** 그 파일은 심의된 재캡처로
정당하게 움직이고, 핀은 **둘째 선언처**가 되어 반드시 낡는다 — 이 저장소가
`gates.yml` build-arg 로 이미 한 번 데인 형태다 (`lint_toolchain_pins`).

## 이 검사가 재지 **못하는** 것 — 반드시 함께 읽어라

  · **outcome 이 옳은지**는 재지 못한다. 그 축은 `test_isa_decoder.py`
    `test_encwave_rtl_truth_table_differential` 이 6,141 점 전량으로 재고,
    `.github/workflows/gates.yml` 이 매 push·PR 마다 돌린다. 그것을
    `make lint` 로 끌어오지 **않는다**: 실측 +4.1~7.9 s(예산 +24~46%) ·
    verilator + pipx cocotb python + 206 MB `sim_build` 를 정적 검사 경로에
    얹고, 얻는 것은 CI 가 이미 하고 있는 대조다. 끄고 싶어지는 게이트는
    곧 없는 게이트다.
  · **인코딩이 옳은지**도 재지 못한다 — 위에 적은 대로 이 표에 인코딩이
    없다. 그 축은 `asm/test_wavetensor_asm.py` 의 `ref` 핀과
    `test_reference_encoders_byte_for_byte` 가 잰다.
    ⚠️ 그 사슬의 **첫 마디가 12/68 opcode (18%)** 다 (실측 2026-08-30):
    어셈블러↔`ref` 핀이 표본인데 `ref`↔캡처 인코더는 1,144 점 전수다.
    가장 약한 마디가 맨 앞이라는 사실은 여기 등재만 하고 처분은 사람이
    정한다.
  · **키 문자열 표기의 옳음**은 재지 못한다. 아래 재유도는 캡처 쪽 `_tt_key`
    와 **독립 재구현**이다 — 표기가 갈라지면 전량 불일치로 **크게** 운다.
    그 시끄러움이 의도다 (표기 변경은 domain_version 의 일부라고 캡처
    머리주석이 못박는다).
  · **ISA 의 21% 는 이 오라클 밖이다** (실측 2026-08-30). `isa/wt64v1_isa.json`
    의 opcode 68 개 중 14 개(0x70 `VFMA_ACC` … 0x7E `FP_ACC_CTRL`)가
    `DOMAIN_CEILING = 0x6F` 위에 있고, 그 14 개의 오라클 점은 **0** 이다.
    배제 자체는 ISA 소스 자신의 선언(「0x070-0x07F is outside the truth-table
    domain」)을 승계한 것이라 정당하다 — 그러나 그 대가로 위 (a) 축
    (「오라클에 한 점도 없이 태어난다」)이 그 블록에 대해 **구조적으로 영구
    침묵**한다. 그래서 아래 OK 문면은 「54 개 전부」로 끝내지 않고 배제분을
    **세어서 인쇄**한다. 완전 덮임처럼 읽히는 초록이 이 파일이 막으려는
    바로 그 침묵이기 때문이다. 그 블록은 `test_fp_block_unassigned_opcodes_
    still_error` 와 CI 의 차등 시험이 따로 잰다.

stdlib 전용. 직접 실행 가능:

    python3 scripts/lint_truth_table_domain.py
    python3 scripts/lint_truth_table_domain.py --self-test
"""

from __future__ import annotations

import ast
import concurrent.futures as cf
import hashlib
import itertools
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

TAG = "lint_truth_table_domain"

# ── 정의역 경로 ─────────────────────────────────────────────────────────────
#
# ⚠️ 형이 곧 지위다. 아래 셋은 **읽고 대조하는** 소스이고, `FROZEN` 만
#    「바이트가 못 움직이는」 대상이다.
ISA_SOURCE = REPO / "isa" / "wt64v1_isa.json"
DOMAIN_DECL = REPO / "test_isa_decoder.py"

#: **재생성 대상.** 심의된 재캡처(`WT_CAPTURE_TRUTH_TABLE=1`)로 정당하게
#: 움직인다. 그러므로 해시 핀을 걸지 않는다 — 걸면 둘째 선언처가 된다.
ORACLE = REPO / "isa" / "truth_table_encwave.json"

#: **불변 대상.** 「이관 전 계보 전용」으로 좁아진 동결 산출물이다. 재캡처
#: 대상이 아니라 **재캡처하면 안 되는** 대상이고, 그 사실을 여기서 바이트로
#: 집행한다.
#:
#: 오늘까지 이 파일의 「바이트 동결」은 docstring 에만 있었다
#: (`asm/test_wavetensor_asm.py::test_frozen_truth_table_untouched` 의
#: 「이 파일이 한 바이트라도 움직이면 여기서 울려야 한다」). 실제 단언은
#: 셋뿐이었다 — `domain_version == 3` · opcode 수 > 50 · fp-block 키 0건.
#: ⇒ **outcome 벡터를 하나 뒤집어도 셋 다 통과한다.** 저장소 전체에 이 두
#: 표에 대한 해시 핀이 0건이었다 (실측 2026-08-30). 선언된 보증과 집행된
#: 보증이 어긋나 있었고, 이 상수가 그 간극이다.
#:
#: 해시 상수의 자리는 **한 곳**이어야 한다. 두 곳에 적으면 그것이 다음
#: 사고다 — 그래서 이 값은 저장소에서 여기에만 있다.
FROZEN: dict[Path, tuple[str, str, int]] = {
    REPO / "isa" / "truth_table_premigration.json": (
        "blake2b-512",
        "d94186b0e85500f012804d98b8a7655c1eee7189317154cb9f01471af90eaebf4"
        "1ef63a677119e2aa6efc58c4e520f1adc83a5a0bd887a357a3e1af4f6207d33",
        3,  # domain_version — 이 표의 지위를 이름한다 (현행은 4)
    ),
}

# ── 판정 상수 ───────────────────────────────────────────────────────────────

#: 캡처 도메인의 천장. `0x70`–`0x7F` 는 **일부러** 제외돼 있다 — 캡처
#: 머리주석: 「that block is scheduled to change in v1.8.0a COMMIT 2 …
#: freezing it here would make the intended change look like a regression」.
#: 그 블록은 `test_fp_block_unassigned_opcodes_still_error` 가 따로 못박는다.
#: 빈칸이 아니라 판정이므로 상수로 든다 — 천장을 옮기려면 이 줄을 고쳐야 하고,
#: 그러면 왜 옮기는지 적게 된다.
DOMAIN_CEILING = 0x6F

#: 캡처 도메인이 **미지원 탐침**으로 세는데 ISA 는 명령을 배정한 코드점.
#: 빈칸이 아니라 판정이다 — 여기 적히지 않은 교집합은 실패한다.
#:
#: 이 표가 재는 것이 이 파일의 두 번째 축이다: 점은 있는데 **outcome 계급이
#: 낡는** 경로. 도메인은 자라지 않으므로 차등 시험이 영원히 침묵한다.
PROBE_YET_ASSIGNED: dict[int, str] = {
    0x6B: (
        "v1.8.0e 에서 `GAMMA_MUL_W` 로 **재배정**됐다. 점 집합을 고정으로 "
        "두는 것이 캡처의 규약이라 이 코드점은 열거 목록(`_TT_UNSUPPORTED_"
        "PROBES`)에 그대로 남고, 캡처된 outcome 계급만 supported-executes 로 "
        "바뀌었다 (domain_version 3 에서 재캡처됨). 즉 **재캡처가 이미 "
        "일어난** 자리이고, 그래서 여기 등재가 「낡음」이 아니라 「처리됨」을 "
        "뜻한다. 새 코드점이 여기 나타나면 그것은 처리되지 않은 것이다."
    ),
}

# 손-유지 **하한**이다. 손-유지 *정의역*(목록)은 금지지만 하한은 허용된다 —
# 방향이 반대이기 때문이다: 목록에서 빠뜨리면 침묵이고, 하한에서 빠뜨리면 곧
# 실패다 (`lint_section_refs` ⑭ 가 적은 그대로). 실측으로만 올려라.
_MIN_FROZEN = 1  # 동결 핀이 0 건이면 이 축이 아무것도 재지 않는다
_MIN_DOMAIN_OPCODES = 60  # 실측 2026-08-30: 69
_MIN_ISA_OPCODES = 50  # 실측 2026-08-30: ≤0x6F 가 54
_MIN_POINTS = 5000  # 실측 2026-08-30: 5,934
_MIN_EXT_PROBES = 150  # 실측 2026-08-30: 207

#: 캡처 키의 opcode 토큰. 3자리 고정은 domain_version 4 의 정의에 **포함**
#: 된다 (W7 표기 이관 — opcode 는 12b 이고 기존 코드점은 확장 니블 0).
#: 읽지 못한 키는 **버리지 않고 크게 실패시킨다** — 조용히 버리면 양쪽이
#: 함께 줄어 대조가 공허해진다 (`lint_toolchain_pins` 의 ARG 토큰과 같은 형태).
_KEY_RE = re.compile(r"^0x([0-9A-Fa-f]{3})\|([^|]*)\|0x([0-9A-Fa-f]+)\|([P-])$")


class _ParseError(RuntimeError):
    """선언을 읽지 못했다 — **skip 이 아니라 실패다.**"""


# ═══════════════════════════════════════════════════════════════════════════
# 캡처 도메인 선언 읽기 — `test_isa_decoder.py` 를 **import 하지 않고**
#
# import 하면 cocotb 가 필요하고, `make lint` 의 `python3` 에는 cocotb 가
# 없다 (실측: ModuleNotFoundError; cocotb 는 pipx venv 안이고
# `cocotb-config --python-bin` 으로만 닿는다 — `Makefile` 의 `rtl-sim` 이 그
# 선례다). 그 의존을 정적 검사 경로에 끌어들이지 않는다.
# ⇒ AST 로 **모듈 최상위 대입만** 읽는다. 부작용 0, 의존 0.
# ═══════════════════════════════════════════════════════════════════════════


def _eval_literal(node: ast.AST) -> object:
    """리터럴 · `range(...)` · `list(...)` · `+` · `*` 펼침만 평가한다.

    `eval` 을 쓰지 않는 이유는 명백하다 — 이 함수는 시험 파일을 읽는다.
    읽지 못하는 표기는 **조용히 건너뛰지 않고** 예외를 던진다.

    ⚠️ 그 「크게 실패한다」에는 대가가 있다: **의미 무변 리팩터에 거짓
    실패한다.** 실측 2026-08-30 — `_TT_DATA_EH_KINDS = [..., *[...]]` 로
    펼침을 쓰기만 해도 「읽지 못한 표기: Starred」로 죽었고, `_fail()` 이
    붙인 처방은 **재캡처 7 단계**였다 (원인과 무관하게 자산을 움직이는
    처방 — F-52 부류). 표기 폭은 그래서 「엄격할수록 좋다」가 아니라
    **캡처 쪽이 실제로 쓸 만한 파이썬만큼** 넓어야 한다. 아래 `*` 펼침이
    그 실측에서 온 넓힘이고, 파서 실패의 처방은 이제 재캡처가 아니라
    `_PARSE_HOWTO` 다.
    """
    if isinstance(node, ast.Constant):
        return node.value
    if isinstance(node, (ast.List, ast.Tuple)):
        out: list[object] = []
        for x in node.elts:
            if isinstance(x, ast.Starred):
                inner = _eval_literal(x.value)
                if not isinstance(inner, list):
                    raise _ParseError(
                        f"`*` 펼침의 피연산자가 리스트가 아니다: {inner!r}")
                out.extend(inner)
            else:
                out.append(_eval_literal(x))
        return out
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left = _eval_literal(node.left)
        right = _eval_literal(node.right)
        if isinstance(left, list) and isinstance(right, list):
            return left + right
        raise _ParseError(f"`+` 의 피연산자가 리스트가 아니다: {left!r} {right!r}")
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
        args = [_eval_literal(a) for a in node.args]
        if node.func.id == "range":
            return list(range(*args))  # type: ignore[arg-type]
        if node.func.id == "list" and len(args) == 1:
            return list(args[0])  # type: ignore[arg-type]
    raise _ParseError(f"읽지 못한 표기: {ast.dump(node)[:120]}")


def _module_bindings(tree: ast.Module) -> list[tuple[str, ast.AST]]:
    """모듈 최상위의 `이름 = 값` 을 (이름, 값노드) 로 돌려준다.

    ⚠️ `ast.AnnAssign` 을 **함께** 센다. `ast.Assign` 만 세던 판이 실측에서
    거짓 실패했다 (2026-08-30): `_TT_FLAGS: list[int] = [0x0, 0x8]` 로 타입
    주석만 붙여도 「선언을 찾지 못했다」로 죽고, 그 실패가 재캡처를 지시했다.
    주석 추가는 의미 무변 리팩터이지 도메인 변경이 아니다.
    """
    out: list[tuple[str, ast.AST]] = []
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for tgt in node.targets:
                if isinstance(tgt, ast.Name):
                    out.append((tgt.id, node.value))
        elif isinstance(node, ast.AnnAssign) and node.value is not None:
            if isinstance(node.target, ast.Name):
                out.append((node.target.id, node.value))
    return out


#: 캡처 쪽이 **실제로 쓰는 경로 상수**. 값이 아니라 **지위**를 대조한다:
#: `_TT_PATH` 는 재생성 대상(ORACLE)이어야 하고, `_TT_FROZEN_…` 은 FROZEN 이어야
#: 한다. 이 둘이 갈리면 캡처가 동결 표를 덮어쓴다 — 아래 ⓪b 가 그것을 **쓰기가
#: 일어나기 전에** 정적으로 잡는다.
_TARGET_DECLS = ("_TT_PATH", "_TT_FROZEN_PREMIGRATION_PATH")


def _eval_repo_path(node: ast.AST, repo: Path) -> Path:
    """`os.path.join(_REPO, 'a', 'b')` 만 평가한다. 다른 표기는 **실패**다."""
    if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
            and node.func.attr == "join" and node.args):
        raise _ParseError(
            f"경로 상수가 `os.path.join(_REPO, …)` 표기가 아니다: "
            f"{ast.dump(node)[:120]}")
    head = node.args[0]
    if not (isinstance(head, ast.Name) and head.id == "_REPO"):
        raise _ParseError("경로 상수의 첫 인자가 `_REPO` 가 아니다 — 저장소 "
                          "바깥을 가리킬 수 있는 표기는 읽지 않는다")
    parts: list[str] = []
    for a in node.args[1:]:
        v = _eval_literal(a)
        if not isinstance(v, str):
            raise _ParseError(f"경로 조각이 문자열이 아니다: {v!r}")
        parts.append(v)
    if not parts:
        raise _ParseError("경로 조각이 없다")
    return repo.joinpath(*parts)


def parse_capture_domain(path: Path) -> dict[str, object]:
    """캡처 도메인 선언을 뽑는다. 하나라도 못 읽으면 **실패**다."""
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    want = {
        "_TT_SUPPORTED_OPCODES",
        "_TT_UNSUPPORTED_PROBES",
        "_TT_DATA_EH_KINDS",
        "_TT_FLAGS",
        "_TT_EXT_NIBBLES",
        "_TT_DOMAIN_VERSION",
    }
    out: dict[str, object] = {}
    targets: dict[str, Path] = {}
    for name, value in _module_bindings(tree):
        if name in want:
            out[name] = _eval_literal(value)
        elif name in _TARGET_DECLS:
            targets[name] = _eval_repo_path(value, REPO)
    missing = sorted(want - set(out))
    if missing:
        raise _ParseError(
            f"{path.name} 에서 캡처 도메인 선언을 찾지 못했다: {missing}"
        )
    missing_t = sorted(set(_TARGET_DECLS) - set(targets))
    if missing_t:
        raise _ParseError(
            f"{path.name} 에서 캡처 **대상 경로** 선언을 찾지 못했다: "
            f"{missing_t} — 이 게이트는 캡처가 어느 파일에 쓰는지를 알아야 한다"
        )
    out["_TARGETS"] = targets
    # 형상 축의 상한 — `_tt_domain()` 의 정수 리터럴 순회에서 뽑는다.
    # 리터럴로 박으면 상한이 바뀐 날 조용히 무효가 된다.
    out["_SUBSET_SIZES"] = _subset_sizes(tree, path)
    return out


def _subset_sizes(tree: ast.Module, path: Path) -> list[int]:
    """`_tt_domain()` 의 **부분집합 크기 순회**를 이름에 의존하지 않고 찾는다.

    ⚠️ 예전 판은 `sub.target.id == "k"` 로 **지역 루프 변수 이름을 하드코드**
    했다. 실측 2026-08-30: `for k in (1,2,3)` → `for ksize in (1,2,3)` 라는
    순수 개명(의미 무변)에 게이트가 거짓 실패했고, 그 실패가 재캡처를
    지시했다. 지역 변수 이름은 캡처의 계약이 아니다 — **정수 리터럴을 도는
    루프라는 형태**가 계약이다.

    형태로 고르므로 후보가 둘 이상이면 기계가 고를 수 없다 — 그때는 조용히
    첫 것을 집지 않고 **모호하다고 실패**한다 (조용한 오선택은 형상 축을
    통째로 무효로 만든다).
    """
    for node in ast.walk(tree):
        if not (isinstance(node, ast.FunctionDef) and node.name == "_tt_domain"):
            continue
        found: list[list[int]] = []
        for sub in ast.walk(node):
            if not isinstance(sub, (ast.For, ast.AsyncFor)):
                continue
            try:
                sizes = _eval_literal(sub.iter)
            except _ParseError:
                continue  # 이름·호출을 도는 루프 — 형상 축이 아니다
            if (isinstance(sizes, list) and sizes
                    and all(isinstance(x, int) and not isinstance(x, bool)
                            for x in sizes)):
                found.append([int(x) for x in sizes])
        if not found:
            raise _ParseError(
                f"{path.name}: `_tt_domain()` 에서 부분집합 크기 순회"
                f"(정수 리터럴을 도는 `for`)를 찾지 못했다")
        if len(found) > 1:
            raise _ParseError(
                f"{path.name}: `_tt_domain()` 에 정수 리터럴 순회가 "
                f"{len(found)}개다 {found} — 어느 것이 형상 축인지 기계가 고를 "
                f"수 없다. 조용히 첫 것을 집으면 형상 대조가 무효가 된다")
        return found[0]
    raise _ParseError(f"{path.name}: `_tt_domain()` 정의를 찾지 못했다")


# ═══════════════════════════════════════════════════════════════════════════
# 기대 키 집합의 **독립 재유도**
#
# 캡처 쪽 `_tt_key` 와 같은 문자열을 여기서 다시 만든다. 사본이 아니라
# **독립 재구현**이고, 갈라지면 전량 불일치로 크게 운다 — 그 시끄러움이
# 의도다. (표기 변경은 domain_version 의 일부라고 캡처 머리주석이 못박는다.
# 조용히 표기가 바뀌는 길이 있으면 안 된다.)
# ═══════════════════════════════════════════════════════════════════════════


def _key(op: int, subset: tuple[str, ...], flags: int, port: bool) -> str:
    return f"0x{op:03X}|{','.join(subset)}|0x{flags:X}|{'P' if port else '-'}"


def expected_points(dom: dict[str, object]) -> set[str]:
    kinds = list(dom["_TT_DATA_EH_KINDS"])  # type: ignore[arg-type]
    subsets: list[tuple[str, ...]] = [()]
    for k in dom["_SUBSET_SIZES"]:  # type: ignore[union-attr]
        subsets.extend(itertools.combinations(kinds, k))
    ops = sorted(set(dom["_TT_SUPPORTED_OPCODES"])  # type: ignore[arg-type]
                 | set(dom["_TT_UNSUPPORTED_PROBES"]))  # type: ignore[arg-type]
    out: set[str] = set()
    for op in ops:
        for fl in dom["_TT_FLAGS"]:  # type: ignore[union-attr]
            for sub in subsets:
                out.add(_key(op, sub, fl, True))
            # 「bare no-port point」— 포트 EH 없는 한 점. 부분집합 축과 별개다.
            out.add(_key(op, (), fl, False))
    return out


def expected_ext_probes(dom: dict[str, object]) -> set[str]:
    ops = sorted(set(dom["_TT_SUPPORTED_OPCODES"])  # type: ignore[arg-type]
                 | set(dom["_TT_UNSUPPORTED_PROBES"]))  # type: ignore[arg-type]
    return {
        _key((ext << 8) | op, (), 0x0, True)
        for op in ops
        for ext in dom["_TT_EXT_NIBBLES"]  # type: ignore[union-attr]
    }


def key_opcodes(keys: object, where: str) -> tuple[set[int], list[str]]:
    """키에서 12b opcode 를 뽑는다. 읽지 못한 키는 목록으로 돌려준다."""
    ops: set[int] = set()
    bad: list[str] = []
    for k in keys:  # type: ignore[union-attr]
        m = _KEY_RE.match(k)
        if not m:
            bad.append(f"{where}: {k!r}")
            continue
        ops.add(int(m.group(1), 16))
    return ops, bad


# ═══════════════════════════════════════════════════════════════════════════
# ⓪ 동결/재생성 분리의 **집행**
# ═══════════════════════════════════════════════════════════════════════════

_WRITE_ATTRS = {
    "write_text", "write_bytes", "touch", "unlink", "rename", "replace",
    "mkdir", "rmdir", "chmod", "symlink_to", "hardlink_to",
}


def _names_in(node: ast.AST) -> set[str]:
    return {n.id for n in ast.walk(node) if isinstance(n, ast.Name)}


def _is_write_call(node: ast.Call) -> bool:
    if isinstance(node.func, ast.Name) and node.func.id == "open":
        mode = ""
        if len(node.args) > 1 and isinstance(node.args[1], ast.Constant):
            mode = str(node.args[1].value)
        for kw in node.keywords:
            if kw.arg == "mode" and isinstance(kw.value, ast.Constant):
                mode = str(kw.value.value)
        return any(c in mode for c in "wax+")
    if isinstance(node.func, ast.Attribute):
        if node.func.attr in _WRITE_ATTRS:
            return True
        if node.func.attr == "open":
            mode = ""
            if node.args and isinstance(node.args[0], ast.Constant):
                mode = str(node.args[0].value)
            for kw in node.keywords:
                if kw.arg == "mode" and isinstance(kw.value, ast.Constant):
                    mode = str(kw.value.value)
            return any(c in mode for c in "wax+")
    return False


def _reachable_from(tree: ast.Module, root: str) -> list[ast.FunctionDef]:
    """`root()` 에서 **호출 그래프로 닿는** 함수 정의만 돌려준다.

    왜 모듈 전체가 아닌가: 아래 음성 시험은 격리 사본(`/tmp`)의 **픽스처
    파일**에 일부러 쓴다 — 동결 표의 사본을 1 바이트 뒤집는 변이가 그것이다.
    모듈 전체를 훑으면 그 정당한 쓰기가 위양성으로 잡혀 대조군이 깨지고,
    깨진 대조군 아래서는 모든 변이가 엉뚱한 이유로 운다.
    ⇒ 정의역은 **본 검사가 실제로 실행하는 코드**다.

    ⚠️ 그 대가로 남는 사각: `run()` 에서 닿지 않는 곳에 숨긴 쓰기는 이 검사가
    보지 못한다. 그러나 닿지 않는 코드는 **본 검사가 실행하지 않으므로**
    동결 표를 건드릴 수 없다. 위험은 「나중에 배선되는」 경우이고, 배선되는
    순간 정의역에 들어와 잡힌다.
    """
    defs = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
    seen: set[str] = set()
    order: list[ast.FunctionDef] = []
    stack = [root]
    while stack:
        name = stack.pop()
        if name in seen or name not in defs:
            continue
        seen.add(name)
        fn = defs[name]
        order.append(fn)
        for call in ast.walk(fn):
            if isinstance(call, ast.Call) and isinstance(call.func, ast.Name):
                stack.append(call.func.id)
    return order


def _formals(fn: ast.FunctionDef) -> list[str]:
    a = fn.args
    return [x.arg for x in (*a.posonlyargs, *a.args)]


def _spread_call(call: ast.Call, callee: ast.FunctionDef,
                 tainted_here: set[str], into: set[str]) -> bool:
    """오염된 **실인자** → 피호출자의 **형식인자**. 늘었으면 True."""
    grew = False
    formals = _formals(callee)
    kwonly = [x.arg for x in callee.args.kwonlyargs]
    vararg = callee.args.vararg.arg if callee.args.vararg else None
    kwarg = callee.args.kwarg.arg if callee.args.kwarg else None

    def add(names) -> None:
        nonlocal grew
        for nm in names:
            if nm and nm not in into:
                into.add(nm)
                grew = True

    for i, a in enumerate(call.args):
        if not (_names_in(a) & tainted_here):
            continue
        if isinstance(a, ast.Starred) or i >= len(formals):
            # 어느 자리에 앉을지 정적으로 모른다 ⇒ **전부** 오염으로 본다.
            # 위양성 쪽으로 틀리는 것이 이 검사의 규약이다.
            add([*formals, *kwonly, vararg])
        else:
            add([formals[i]])
    for kw in call.keywords:
        if not (_names_in(kw.value) & tainted_here):
            continue
        add([kw.arg] if kw.arg else [*formals, *kwonly, kwarg])
    return grew


def frozen_write_sites(path: Path) -> list[str]:
    """본 검사의 코드 경로가 `FROZEN` 유래 경로에 **쓰기**를 여는가.

    「읽기만 한다」를 주석이 아니라 집행으로 만든다. 순진한 게이트가 두 표를
    다 「갱신」하려 드는 것이 이 파일이 막는 자산 파괴 경로이고, 그 코드는
    반드시 `run()` 에서 닿는 자리에 생긴다.

    오염 전파는 **함수 사이를 건넌다**(inter-procedural, 전역 고정점):

      (1) 함수 안 — `FROZEN` 을 참조하는 대입·순회·with 의 대상이 오염된다.
      (2) 함수 사이 — 오염된 실인자로 호출하면 피호출자의 그 자리 형식인자가
          오염된다. `*args` 나 자리 초과처럼 **정적으로 자리를 모르는** 경우는
          전부 오염으로 본다.

    ⚠️ (2) 는 실측이 강제한 것이다 (2026-08-30). 예전 판은 함수 안만 따라가서
    `def _refresh(p): p.write_bytes(...)` 를 만들고 `run()` 에서
    `for _p in FROZEN: _refresh(_p)` 로 부르면 **호출 한 마디만에 뚫렸다** —
    `frozen_write_sites` 는 아무 자리도 보고하지 않았고, 격리 사본의 동결 표가
    실제로 `{}` 로 파괴됐으며(md5 `a09063df…`→`99914b93…`), rc=1 은 났으나
    이유는 「동결 표가 움직였다」라는 **사후** 해시 검출이었다. 정적 집행의
    값어치는 쓰기가 일어나기 **전에** 막는 데 있으므로, 한 마디 깊이에서
    끝나는 집행은 집행이 아니다.

    실패 방향이 위양성(쓰지 않는데 쓴다고 운다)이라 견디는 쪽이고, 위음성은
    정의상 자산 파괴다.

    ⚠️ **한계를 정직하게 적는다.** 이것은 정적 검사이지 샌드박스가 아니다.
    쓰기가 `run()` 안에서 **이 검사보다 먼저** 실행되도록 심어지면 파일은
    그 자리에서 움직인다 — 실측으로 확인했다(`_refresh` 호출을 `run()` 머리에
    넣은 구성: 자리는 정확히 보고되지만 파일은 이미 `{}` 였다). 어떤 검사도
    자기보다 앞서 실행되는 코드를 되돌릴 수는 없다. 이 함수가 보증하는 것은
    「그런 코드 경로가 **보고된다**」이지 「일어나지 않는다」가 아니고, 실무상
    값어치는 리뷰·CI 가 그 자리를 읽는 데 있다. 실행 순서까지 막는 유일한
    형태는 이 스크립트를 읽기 전용 프로세스로 격리하는 것인데, 그것은
    `make lint` 의 예산 밖이다. 처분은 사람이 정한다.
    """
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    fns = _reachable_from(tree, "run")
    by_name = {fn.name: fn for fn in fns}
    tainted: dict[str, set[str]] = {fn.name: {"FROZEN"} for fn in fns}

    # 전역 고정점 — 호출 순서·정의 순서에 의존하지 않는다.
    for _ in range(64):
        grew = False
        for fn in fns:
            here = tainted[fn.name]
            for node in ast.walk(fn):
                src = tgts = None
                if isinstance(node, ast.Assign):
                    src, tgts = node.value, node.targets
                elif isinstance(node, (ast.For, ast.AsyncFor)):
                    src, tgts = node.iter, [node.target]
                elif isinstance(node, ast.withitem):
                    src, tgts = node.context_expr, (
                        [node.optional_vars] if node.optional_vars else [])
                if src is None or not tgts:
                    continue
                if not (_names_in(src) & here):
                    continue
                for t in tgts:
                    for n in ast.walk(t):
                        if isinstance(n, ast.Name) and n.id not in here:
                            here.add(n.id)
                            grew = True
            for call in ast.walk(fn):
                if not (isinstance(call, ast.Call)
                        and isinstance(call.func, ast.Name)):
                    continue
                callee = by_name.get(call.func.id)
                if callee is None:
                    continue
                if _spread_call(call, callee, here, tainted[callee.name]):
                    grew = True
        if not grew:
            break

    sites: list[str] = []
    for fn in fns:
        for node in ast.walk(fn):
            if (isinstance(node, ast.Call) and _is_write_call(node)
                    and (_names_in(node) & tainted[fn.name])):
                sites.append(f"{path.name}:{node.lineno} (in {fn.name}())")
    return sorted(set(sites))


# ═══════════════════════════════════════════════════════════════════════════
# 본 검사
# ═══════════════════════════════════════════════════════════════════════════

_RECAPTURE_HOWTO = """
  ── 오라클을 정말 재캡처해야 한다면 (도메인이 **정당하게** 자란 경우) ──
    0. 이것은 검토된 의도적 행위다. 「lint 가 울어서」는 이유가 아니다.
    1. `git status --porcelain isa/` 가 비어 있는지 확인한다.
    2. WT_CAPTURE_TRUTH_TABLE=1 make MOD=ISA_Decoder \\
           TESTCASE=test_encwave_rtl_truth_table_differential
       (약 8 초. 재캡처 비용 == 대조 비용이다 — 같은 스윕이고 분기만 다르다.)
    3. `git diff --stat -- isa/` 로 무엇이 움직였는지 읽는다.
    4. `test_isa_decoder.py` 의 `_TT_DOMAIN_VERSION` 을 범프하고,
       소비자 핀(`asm/test_wavetensor_asm.py` 의 encwave 핀 5건)을 재동기한다.
    5. 3 회 캡처해 **바이트 동일**함을 확인한다 (`c682acd` 의 절차).
    6. 차등 재캡처 · dv 범프 · 소비자 핀 재동기를 **한 커밋에** 담는다.
    7. 아래 FROZEN 해시는 **건드리지 않는다** (그 표는 재캡처 대상이 아니다).

  ── ⚠️ isa/truth_table_premigration.json 은 재캡처 대상이 **아니다** ──
    「이관 전 계보 전용」으로 좁아진 동결 산출물이다. 현행 인코딩 바이너리를
    이 표에 걸면 전량 불일치한다. 이 파일이 움직였다면 그것은 갱신이 아니라
    **계보 증거의 파괴**다 — 되돌려라 (`git checkout -- isa/truth_table_premigration.json`).
"""

#: 파서 실패의 처방. **재캡처가 아니다.**
#:
#: 실측 2026-08-30 이 이 상수를 강제했다: 의미 무변 리팩터 셋(타입 주석 추가 ·
#: `*` 펼침 · 지역 루프 변수 개명)에 게이트가 거짓 실패했고, 그때마다 위
#: `_RECAPTURE_HOWTO` 전문이 인쇄돼 「WT_CAPTURE_TRUTH_TABLE=1 … dv 범프 …
#: 한 커밋」을 지시했다. 원인은 파서인데 처방은 **자산을 움직이는 7 단계**였다
#: — 문면이 오진하면 사람이 그 오진을 실행한다 (F-52 부류). 파서 실패에는
#: 파서 처방을 붙인다.
_PARSE_HOWTO = """
  ── 선언을 **읽지 못했을 때** — 재캡처가 아니다 ──
    이 실패는 「도메인이 갈라졌다」가 아니라 「이 게이트의 파서가
    test_isa_decoder.py 의 **표기**를 읽지 못했다」다. 처방은 둘 중 하나다:
      1. 방금 바꾼 표기를 되돌린다 (대개 **한 줄 되돌리기**다), 또는
      2. scripts/lint_truth_table_domain.py 의 파서를 그 표기까지 넓힌다 —
         `_eval_literal` (값 표기) · `_module_bindings` (대입 형태) ·
         `_subset_sizes` (형상 축 순회) · `_eval_repo_path` (경로 상수).
         넓혔으면 `--self-test` 의 D2/D6 양성 대조에 그 표기를 등재하라.
    ⚠️ 오라클도 동결 표도 **건드리지 마라** — 원인이 그쪽에 없다.
       특히 재캡처하지 마라: 파서가 못 읽는 것과 도메인이 낡은 것은 다르다.
"""

#: 캡처 **대상**이 갈라졌을 때의 처방. 여기서 `_RECAPTURE_HOWTO` 를 인쇄하면
#: 처방 자체가 자산 파괴를 실행한다 — 그 2 단계가
#: `WT_CAPTURE_TRUTH_TABLE=1 … TESTCASE=test_encwave_rtl_truth_table_
#: differential` 이고, 그 시험은 `open(_TT_PATH, 'w')` 로 쓴다. `_TT_PATH` 가
#: 동결 표를 겨눈 상태에서 그 줄을 따르면 **계보 증거가 그 자리에서 사라진다.**
#: 처방과 사고가 같은 명령인 유일한 자리라 별도로 가른다.
_TARGET_HOWTO = """
  ── 캡처 **대상**이 어긋났다 — ⚠️ **재캡처를 실행하지 마라** ──
    이 상태에서 `WT_CAPTURE_TRUTH_TABLE=1` 을 돌리면 그 명령이 곧 사고다:
    차등 시험은 `open(_TT_PATH, 'w')` 로 쓰므로, `_TT_PATH` 가 겨눈 파일이
    그대로 덮인다. 먼저 **겨냥을 고쳐라.**
      1. test_isa_decoder.py 의 `_TT_PATH` 를 재생성 대상으로 되돌린다:
           _TT_PATH = os.path.join(_REPO, 'isa', 'truth_table_encwave.json')
      2. `_TT_FROZEN_PREMIGRATION_PATH` 는 계보 전용 읽기 경로다 — 캡처가
         그것을 겨누는 일은 어떤 경우에도 없다.
      3. 동결 표가 이미 움직였다면 되돌려라:
           git checkout -- isa/truth_table_premigration.json
      4. 겨냥이 바로잡히고 이 게이트가 초록이 된 **뒤에야** 재캡처를 논한다.
"""


def run(quiet: bool = False) -> int:
    problems: list[str] = []
    notes: list[str] = []

    # ── ⓪ 동결/재생성 분리 ────────────────────────────────────────────────
    #
    # **가장 먼저** 돈다. 이 구분이 무너진 상태에서 도메인을 대조하면
    # 「고쳐라」가 자산 파괴를 뜻하게 된다.
    if len(FROZEN) < _MIN_FROZEN:
        problems.append(
            f"동결 핀 {len(FROZEN)}건 < 하한 {_MIN_FROZEN} — 이 축이 잰 것이 "
            f"0 이다. 「대조했더니 같았다」가 아니라 「대조할 것이 없었다」다"
        )
    if ORACLE in FROZEN:
        problems.append(
            f"**오조준** — 재생성 대상 `{ORACLE.relative_to(REPO)}` 에 동결 "
            f"핀이 걸려 있다. 그 표는 심의된 재캡처로 **정당하게 움직인다**; "
            f"핀을 걸면 둘째 선언처가 되어 반드시 낡는다 (gates.yml build-arg "
            f"사고와 같은 형태). 동결 핀은 `truth_table_premigration.json` "
            f"에만 건다"
        )
    sites = frozen_write_sites(Path(__file__).resolve())
    if sites:
        problems.append(
            f"**동결 경로에 쓰기를 연다**: {sites} — 이 스크립트는 FROZEN 을 "
            f"읽기만 해야 한다. 동결 표를 재생성 대상으로 다루는 코드 경로가 "
            f"생기면 계보 증거가 파괴된다"
        )

    for p in (ISA_SOURCE, DOMAIN_DECL, ORACLE, *FROZEN):
        if not p.is_file():
            problems.append(f"파일 부재: {p.relative_to(REPO)}")
    if problems:
        return _fail(problems)

    # ── ① 동결 표의 바이트 불변 ────────────────────────────────────────────
    for path, (algo, want, want_dv) in FROZEN.items():
        rel = path.relative_to(REPO)
        raw = path.read_bytes()  # 읽기 전용 — 위 AST 검사가 그것을 집행한다
        if algo != "blake2b-512":
            problems.append(f"{rel}: 알 수 없는 해시 알고리즘 `{algo}`")
            continue
        got = hashlib.blake2b(raw).hexdigest()
        if got != want:
            problems.append(
                f"**동결 표가 움직였다**: {rel}\n"
                f"      기대 {algo} {want}\n"
                f"      실제 {algo} {got}   ({len(raw):,} B)\n"
                f"      이 파일은 「이관 전 계보 전용」 동결 산출물이다 — "
                f"재생성 대상이 아니라 **불변 대상**이다. 되돌려라: "
                f"git checkout -- {rel}"
            )
            continue
        try:
            dv = json.loads(raw)["domain_version"]
        except Exception as e:  # noqa: BLE001 — 무엇이 터졌는지 인쇄해야 한다
            problems.append(f"{rel}: domain_version 을 읽지 못했다 — {e}")
            continue
        if dv != want_dv:
            problems.append(
                f"{rel}: domain_version {dv} ≠ 핀 {want_dv} — 해시는 맞는데 "
                f"지위 선언이 어긋난다 (핀 표가 낡았다)"
            )
        notes.append(f"동결 {rel} {algo[:8]}…{got[:12]} dv{dv} ({len(raw):,} B)")

    # ── ② 캡처 도메인 선언 ────────────────────────────────────────────────
    try:
        dom = parse_capture_domain(DOMAIN_DECL)
    except _ParseError as e:
        return _fail([f"캡처 도메인 선언을 읽지 못했다: {e}"], howto="parse")

    # ── ⓪b 캡처가 **어느 파일에 쓰는가** ──────────────────────────────────
    #
    # ⚠️ 이 축이 없던 판(2026-08-30 실측)의 구멍이 그대로 자산 파괴다:
    # `test_isa_decoder.py` 의 `_TT_PATH` 를 동결 표로 돌려놔도 게이트는 rc=0
    # 이었고, **하필 그 파일을 「불변 대상(재캡처 대상이 아니다)」이라 인쇄**
    # 했다. 게이트가 재생성 대상(ORACLE)만 읽고 **실제 캡처 대상**을 한 번도
    # 읽지 않았기 때문이다 (`grep -c _TT_PATH` → 0).
    #
    # 이 축의 유일한 그물이던 cocotb 단언
    # (`test_encwave_capture_shape_invariants` 의
    #  `assert _TT_FROZEN_PREMIGRATION_PATH != _TT_PATH`)은 **사후 검출**이다 —
    # 파괴적 쓰기를 하는 `test_encwave_rtl_truth_table_differential` 보다
    # 나중에 돌고, `make lint`/훅에는 아예 없다. 여기서는 **쓰기가 일어나기
    # 전에**, RTL 없이, 정적으로 막는다.
    targets: dict[str, Path] = dom["_TARGETS"]  # type: ignore[assignment]
    tgt_problems: list[str] = []
    cap = targets["_TT_PATH"]
    cap_rel = cap.relative_to(REPO) if cap.is_relative_to(REPO) else cap
    if cap in FROZEN:
        tgt_problems.append(
            f"**캡처가 동결 표를 겨눈다**: {DOMAIN_DECL.name} 의 `_TT_PATH` 가 "
            f"`{cap_rel}` 다 — 그 파일은 동결 핀이 걸린 **불변 대상**인데 "
            f"`WT_CAPTURE_TRUTH_TABLE=1` 이 그 자리에 `open(_TT_PATH, 'w')` 로 "
            f"덮어쓴다. 이것이 **계보 증거 파괴** 그 자체다. `_TT_PATH` 를 "
            f"재생성 대상(`{ORACLE.relative_to(REPO)}`)으로 되돌려라"
        )
    elif cap != ORACLE:
        tgt_problems.append(
            f"**캡처 대상이 갈라졌다**: {DOMAIN_DECL.name} 의 `_TT_PATH` 가 "
            f"`{cap_rel}` 인데 이 게이트가 신선도를 재는 오라클은 "
            f"`{ORACLE.relative_to(REPO)}` 다 — 캡처가 쓰는 파일과 게이트가 "
            f"읽는 파일이 다르면 **이 게이트 전체가 공허**하다 (엉뚱한 파일이 "
            f"신선하다고 인쇄한다). 둘 중 하나를 맞춰라"
        )
    fz = targets["_TT_FROZEN_PREMIGRATION_PATH"]
    if fz not in FROZEN:
        fz_rel = fz.relative_to(REPO) if fz.is_relative_to(REPO) else fz
        tgt_problems.append(
            f"동결 상수가 핀 표와 갈라졌다: {DOMAIN_DECL.name} 의 "
            f"`_TT_FROZEN_PREMIGRATION_PATH` 는 `{fz_rel}` 인데 이 파일의 "
            f"`FROZEN` 에 그 경로가 없다 — 「동결」이라 이름 붙은 파일이 "
            f"바이트 핀 밖에 있다"
        )
    if tgt_problems:
        # **여기서 즉시 돌아간다.** 처방이 갈리기 때문이다 — 이 실패에
        # `_RECAPTURE_HOWTO` 를 붙이면 처방 2 단계가 곧 자산 파괴다.
        return _fail(problems + tgt_problems, howto="target")

    supported = sorted(set(dom["_TT_SUPPORTED_OPCODES"]))  # type: ignore[arg-type]
    probes = sorted(set(dom["_TT_UNSUPPORTED_PROBES"]))  # type: ignore[arg-type]
    domain = set(supported) | set(probes)
    if len(domain) < _MIN_DOMAIN_OPCODES:
        problems.append(
            f"캡처 도메인 {len(domain)} opcode < 하한 {_MIN_DOMAIN_OPCODES} — "
            f"이 검사가 잰 것이 0 에 가깝다. **0 건은 통과가 아니다**"
        )

    # ── ③ 오라클 자기 키 집합 ─────────────────────────────────────────────
    oracle = json.loads(ORACLE.read_text(encoding="utf-8"))
    for sec, floor in (("points", _MIN_POINTS), ("ext_probes", _MIN_EXT_PROBES)):
        if sec not in oracle:
            problems.append(f"오라클에 `{sec}` 절이 없다")
        elif len(oracle[sec]) < floor:
            problems.append(
                f"오라클 `{sec}` {len(oracle[sec])}점 < 하한 {floor} — "
                f"대조가 공허해진다. **0 건은 통과가 아니다**"
            )
    if problems:
        return _fail(problems)

    if oracle["domain_version"] != dom["_TT_DOMAIN_VERSION"]:
        problems.append(
            f"domain_version 이 갈라졌다: 오라클 {oracle['domain_version']} ≠ "
            f"선언 {dom['_TT_DOMAIN_VERSION']} "
            f"({DOMAIN_DECL.name} 의 `_TT_DOMAIN_VERSION`) — 재캡처와 dv 범프가 "
            f"**한 커밋에** 담기지 않았다"
        )

    bad_keys: list[str] = []
    got_pts, bk = key_opcodes(oracle["points"], "points")
    bad_keys += bk
    got_ext, bk = key_opcodes(oracle["ext_probes"], "ext_probes")
    bad_keys += bk
    if bad_keys:
        problems.append(
            f"읽지 못한 오라클 키 {len(bad_keys)}건 — 예: {bad_keys[:3]} — "
            f"조용히 버리면 양쪽이 함께 줄어 대조가 공허해진다. 표기를 "
            f"고치거나 파서를 고쳐라 (통과시키지 마라)"
        )

    # 선언 도메인 ↔ 오라클 키 집합 — **전량 재유도 후 집합 대조**
    for sec, want_keys in (("points", expected_points(dom)),
                           ("ext_probes", expected_ext_probes(dom))):
        have = set(oracle[sec])
        only_decl = sorted(want_keys - have)
        only_oracle = sorted(have - want_keys)
        if only_decl:
            problems.append(
                f"`{sec}`: 선언 도메인에는 있는데 **오라클에 없는** 점 "
                f"{len(only_decl)}건 — 예: {only_decl[:3]}. 도메인이 자랐는데 "
                f"재캡처가 없었다는 뜻이다"
            )
        if only_oracle:
            problems.append(
                f"`{sec}`: 오라클에는 있는데 **선언 도메인에 없는** 점 "
                f"{len(only_oracle)}건 — 예: {only_oracle[:3]}. 캡처 도메인이 "
                f"줄었거나 키 표기가 갈라졌다"
            )

    # ── ④ ISA 소스 ↔ 캡처 도메인 ──────────────────────────────────────────
    isa = json.loads(ISA_SOURCE.read_text(encoding="utf-8"))
    isa_codes = {int(o["code"]) for o in isa["opcodes"]}
    isa_in_range = {c for c in isa_codes if c <= DOMAIN_CEILING}
    isa_above = sorted(isa_codes - isa_in_range)

    # ── 천장이 낡았는가 — **나란한 두 방향을 다 건다** ─────────────────────
    #
    # `DOMAIN_CEILING` 은 빈칸이 아니라 판정이고, 그 판정이 낡는 길은 둘이다.
    # 한쪽만 걸면 나머지가 조용히 정의역 밖에 남는다 — 이 저장소의 상습
    # 실패형이 정확히 그것이다.
    #
    #   (선언 쪽) 캡처 도메인 리터럴이 천장 위로 자랐다.
    #   (오라클 쪽) 오라클 키가 천장 위의 기저 opcode 를 담는다.
    #
    # 둘은 보통 함께 움직이지만 **함께 움직인다는 보장이 없다** (도메인은
    # 손-유지 리터럴이고 오라클은 캡처 산출물이라 커밋이 갈릴 수 있다).
    domain_above = sorted(domain & set(isa_above))
    if domain_above:
        problems.append(
            f"**천장이 낡았다 (선언 쪽)**: 캡처 도메인이 "
            + ", ".join(f"0x{c:02X}" for c in domain_above)
            + f" 를 담는데 DOMAIN_CEILING = 0x{DOMAIN_CEILING:02X} 가 그것을 "
            f"정의역 밖이라 선언한다. ISA 는 그 코드점에 명령을 배정했으므로 "
            f"「ISA 에 없다」가 아니라 **천장 선언이 낡은** 것이다 — "
            f"`DOMAIN_CEILING` 을 올리고 캡처 머리주석의 배제 문구를 함께 "
            f"고쳐라 (그 둘은 같은 판정의 두 사본이다)"
        )

    # (오라클 쪽) 키의 12b opcode 는 확장 니블을 포함하므로 **하위 바이트**로
    # 되돌려 기저 opcode 를 본다. `got_pts`/`got_ext` 가 여기서 하중을 진다.
    base_ops = {op & 0xFF for op in (got_pts | got_ext)}
    covered_above = sorted((base_ops & set(isa_above)) - set(domain_above))
    if covered_above:
        problems.append(
            f"**천장이 낡았다 (오라클 쪽)**: DOMAIN_CEILING = "
            f"0x{DOMAIN_CEILING:02X} 가 배제한다고 선언한 opcode 인데 오라클에 "
            f"점이 있다 — "
            + ", ".join(f"0x{c:02X}" for c in covered_above)
            + ". 게다가 캡처 **선언**에는 없다 — 배제 선언 · 선언 도메인 · "
            "오라클 셋이 서로 갈라졌다. 어느 것이 옳은지는 캡처 머리주석이 "
            "정한다"
        )

    if len(isa_in_range) < _MIN_ISA_OPCODES:
        problems.append(
            f"ISA 소스의 ≤0x{DOMAIN_CEILING:02X} opcode {len(isa_in_range)}개 "
            f"< 하한 {_MIN_ISA_OPCODES} — 잰 것이 0 에 가깝다. **0 건은 통과가 "
            f"아니다**"
        )

    # (a) ISA 가 배정한 코드점이 오라클 정의역 밖이면 그 opcode 는
    #     **오라클에 한 점도 없이 태어난다.** 차등 시험은 `got` 이 상수라
    #     영원히 침묵한다 — 그 침묵이 이 파일이 사는 이유다.
    orphan = sorted(isa_in_range - domain)
    if orphan:
        problems.append(
            "**오라클에 한 점도 없는 opcode**: "
            + ", ".join(f"0x{c:02X}" for c in orphan)
            + f" — ISA 소스가 배정했는데 캡처 도메인"
            f"(`_TT_SUPPORTED_OPCODES`/`_TT_UNSUPPORTED_PROBES`)에 없다. "
            f"차등 시험의 `extra = set(got) - set(frozen)` 은 `got` 이 자라지 "
            f"못하므로 **영원히 공집합**이고, 그래서 이것은 실패가 아니라 "
            f"침묵으로 나타난다. 도메인 리터럴을 넓히고 재캡처하라"
        )

    # (b) 거꾸로 — 도메인이 「지원」이라 말하는데 ISA 에 그 명령이 없다.
    #     오라클이 실재하지 않는 명령의 실행 outcome 을 승인하고 있다는 뜻이다.
    #     ⚠️ 정의역은 `isa_in_range` 가 아니라 `isa_codes` 다. 천장 **위**에
    #     배정된 코드점을 「지원」이라 캡처했다면 그것은 「ISA 에 없다」가
    #     아니라 「천장이 낡았다」이고, 바로 위 축이 그 문면으로 운다. 여기서
    #     `isa_in_range` 를 쓰면 같은 사건에 **틀린 진단**이 붙는다.
    ghost = sorted(set(supported) - isa_codes)
    if ghost:
        problems.append(
            "**ISA 에 없는데 「지원」으로 캡처된 opcode**: "
            + ", ".join(f"0x{c:02X}" for c in ghost)
            + " — `_TT_SUPPORTED_OPCODES` 가 배정을 주장하는데 "
            f"`{ISA_SOURCE.relative_to(REPO)}` 에 그 코드점이 없다. opcode 가 "
            f"제거·재배치됐는데 오라클이 옛 계급을 승인하고 있다. 리터럴을 "
            f"미지원 탐침으로 옮기고 재캡처하라"
        )

    # (c) 「미지원 탐침」인데 ISA 가 명령을 배정했다 — 점은 있으나 그 점의
    #     **outcome 계급이 낡는다.** 도메인은 안 자라므로 (a) 로는 안 잡힌다.
    for c in sorted(set(probes) & isa_in_range):
        if c not in PROBE_YET_ASSIGNED:
            problems.append(
                f"**낡은 outcome 계급**: 0x{c:02X} 가 `_TT_UNSUPPORTED_PROBES` "
                f"에 있는데 ISA 는 명령을 배정했다 — 점은 있으나 캡처된 "
                f"outcome 이 「미지원」계급이다. 도메인은 자라지 않으므로 차등 "
                f"시험이 침묵한다. 재캡처한 뒤 **이유와 함께** "
                f"PROBE_YET_ASSIGNED 에 등재하라 (0x6B 이 그 선례다)"
            )
    for c in sorted(PROBE_YET_ASSIGNED):
        if c not in set(probes) & isa_in_range:
            problems.append(
                f"표가 낡았다: 0x{c:02X} 가 PROBE_YET_ASSIGNED 에 등재됐는데 "
                f"「미지원 탐침 ∩ ISA 배정」이 아니다 — 등재를 지워라"
            )

    if problems:
        return _fail(problems)

    if not quiet:
        print(
            f"{TAG}: OK — 캡처 도메인 {len(domain)} opcode "
            f"(지원 {len(supported)} + 탐침 {len(probes)}) / 오라클 dv"
            f"{oracle['domain_version']} points {len(oracle['points']):,} + "
            f"ext_probes {len(oracle['ext_probes'])} 전량 키 집합 일치"
        )
        print(
            f"  · ISA 소스 opcode {len(isa_codes)}개 = 정의역 안 "
            f"{len(isa_in_range)}개(≤0x{DOMAIN_CEILING:02X}) **전부 덮임** + "
            f"정의역 **밖** {len(isa_above)}개 — 재배정 등재 "
            f"{len(PROBE_YET_ASSIGNED)}건 "
            f"({', '.join(f'0x{c:02X}' for c in sorted(PROBE_YET_ASSIGNED))})"
        )
        # ⚠️ 배제분을 **세어서 인쇄**한다. 「54개 전부 정의역 안」만 인쇄하던
        #    판은 배정 opcode 14개(전체의 21%)를 조용히 빼고도 완전 덮임처럼
        #    읽혔다 (실측 2026-08-30). RTL 전면 재구현이 이 표를 블랙박스
        #    오라클로 쓰는 이상, ISA 의 21% 가 오라클에 없다는 사실은 초록
        #    문면이 감출 것이 아니라 **인쇄할** 것이다.
        if isa_above:
            print(
                f"  · ⚠ 정의역 **밖** {len(isa_above)}개 "
                f"({len(isa_above) / max(len(isa_codes), 1) * 100:.0f}%) — "
                + ", ".join(f"0x{c:02X}" for c in isa_above)
                + f" : 오라클 점 **0**. ISA 소스 자신의 선언"
                f"(「0x0{DOMAIN_CEILING + 1:02X}-0x07F is outside the "
                f"truth-table domain」)을 승계한 정당한 배제이나, 그 대가로 "
                f"「오라클에 한 점도 없이 태어난다」탐지기가 이 블록에 대해 "
                f"**구조적으로 영구 침묵**한다 — 이 블록의 그물은 "
                f"`test_fp_block_unassigned_opcodes_still_error` 와 CI 차등 "
                f"시험뿐이다"
            )
        print(
            f"  · 캡처 대상 {cap_rel} — 재생성 대상이고 이 게이트가 재는 "
            f"오라클과 **같은 파일**이다 (`_TT_PATH` 정적 대조)"
        )
        for n in notes:
            print(f"  · {n} — **불변 대상** (재캡처 대상이 아니다)")
        print(
            "  · ⚠ 이 검사는 **정의역**만 잰다 — outcome 이 옳은지는 "
            "`test_encwave_rtl_truth_table_differential`(6,141점)이 CI 에서 "
            "재고, 인코딩은 이 표에 한 비트도 담기지 않는다."
        )
    return 0


def _fail(problems: list[str], howto: str = "recapture") -> int:
    """처방을 **원인에 맞춰** 고른다.

    `howto="parse"` 는 「파서가 표기를 못 읽었다」 — 재캡처 처방을 붙이면
    사람이 원인과 무관하게 자산을 움직인다. `howto="target"` 은 「캡처 대상이
    어긋났다」 — 재캡처 처방의 2 단계가 **그 상태에서 곧 자산 파괴**다.
    """
    print(f"{TAG}: FAIL — 오라클 정의역 / 동결 표가 어긋났다", file=sys.stderr)
    for p in problems:
        print(f"  · {p}", file=sys.stderr)
    print({"parse": _PARSE_HOWTO,
           "target": _TARGET_HOWTO}.get(howto, _RECAPTURE_HOWTO),
          file=sys.stderr)
    return 1


# ═══════════════════════════════════════════════════════════════════════════
# 음성 시험 — 격리 사본에서 변이가 실제로 잡히는지
#
# 형태는 `scripts/lint_toolchain_pins.py --self-test` 를 따른다: 트리 사본
# (`/tmp`) → 문자열 치환 → **하위프로세스 재실행** → rc **와 문면**으로 판정.
# 실파일은 건드리지 않는다 (실파일을 고쳤다 되돌리는 방식은 중단되면 저장소를
# 더럽힌다 — 특히 이 파일의 정의역에는 **동결 산출물**이 있다).
#
# 규율 넷은 선례와 같다:
#   · **대조군이 먼저다** (N0).
#   · **판정 축이 둘이다** — rc=1 **과** 기대 문면. rc 만 보면 「울긴 울었는데
#     다른 이유로」가 통과로 세어진다.
#   · **변이 지점은 손으로 박지 않는다** — 기준 파일을 파싱해 실제 자리에서
#     고른다. 치환 실패는 skip 이 아니라 실패다.
#   · **0 건은 통과가 아니다** — ⓪ 정의역 폐쇄가 변이보다 먼저 돈다.
# ═══════════════════════════════════════════════════════════════════════════

_MIN_DOMAIN_PATHS = 4
_MIN_MUTATIONS = 30  # 실측 2026-08-30. 내리려면 무엇이 왜 빠졌는지 함께 적어라
_MIN_KEY_PROBE = 6
#: 양성 대조(의미 무변 리팩터) 하한. **0 건은 통과가 아니다** — 이 축이 비면
#: 게이트는 조여지는 방향으로만 자라고, 거짓 실패가 쌓인 게이트는 꺼진다.
_MIN_REFACTORS = 4

#: 픽스처의 **동결 표를 움직여도 되는** 변이. 이 둘 말고는 어떤 변이도 동결
#: 표를 못 움직인다 — 아래 N8 이 매 변이마다 그것을 잰다.
#:
#: ⚠️ 왜 전역 불변으로 세우는가 (실측 2026-08-30). 예전 판의 `frozen_write_sites`
#: 는 함수 안만 따라가서, 호출 **한 마디**를 건너뛰는 쓰기(`_refresh(p)`)를
#: 놓쳤다. 그때 rc 는 1 이었으므로 「변이를 잡았다」로 세어졌지만 — 이유는
#: 사후 해시였고 **픽스처의 동결 표는 이미 파괴된 뒤**였다. rc 만 세는 판정은
#: 「정적으로 막았다」와 「부수고 나서 알아챘다」를 구분하지 못한다. 그 구분을
#: 기계가 하게 만드는 것이 N8 이다.
_FROZEN_MAY_MOVE = {"m3", "m13"}

#: 병렬 폭. 각 시행은 독립 격리 사본 + 독립 하위프로세스라 공유 상태가 없다.
#: 상한을 두는 이유는 이것이 `make lint` 안에서 돌기 때문이다 — 훅을 돌리는
#: 기계를 통째로 먹지 않는다.
_WORKERS = max(1, min(8, (os.cpu_count() or 1)))


class _MutationMiss(RuntimeError):
    """변이 지점을 찾지 못했다 — **skip 이 아니라 실패다.**"""


# ── AST 평가기 양성 대조의 정답표 ───────────────────────────────────────────
#
# ⚠️ 왜 변이가 아니라 **양성 대조**인가. 파서 보조의 퇴화는 「판정이 뒤집힌다」
# 가 아니라 「덜 읽는다」로 나타나고, 덜 읽으면 기대 키 집합이 **함께** 줄어
# 대조가 조용히 공허해진다 (`lint_toolchain_pins` D4 가 같은 이유로 있다).
_LIT_PROBE = (
    "A = list(range(0x00, 0x03)) + [0x10, 0x11] + list(range(0x20, 0x22))\n"
    "B = [0x0, 0x8]\n"
    "C = ['imm16', 'mem']\n"
    "D = 4\n"
    "E = ['a', *['b', 'c'], 'd']\n"      # `*` 펼침 — 실측이 강제한 넓힘
)
_LIT_WANT = {
    "A": [0x00, 0x01, 0x02, 0x10, 0x11, 0x20, 0x21],
    "B": [0x0, 0x8],
    "C": ["imm16", "mem"],
    "D": 4,
    "E": ["a", "b", "c", "d"],
}

# ── 선언 파서 양성 대조 (D6) ────────────────────────────────────────────────
#
# ⚠️ 이 대조는 실측 셋에서 왔다 (2026-08-30). 아래 **의미 무변 리팩터** 셋에
# 예전 판이 전부 거짓 실패했고, 그 실패 문면이 **재캡처 7 단계**를 지시했다:
#
#   · 타입 주석 추가        `_TT_FLAGS: list[int] = [...]`  → AnnAssign 미지원
#   · `*` 펼침              `[..., *[...]]`                 → Starred 미지원
#   · 지역 루프 변수 개명   `for k` → `for ksize`           → 이름 하드코드
#
# 세 리팩터를 **한 픽스처에 모아** 양성 대조로 세운다. 변이가 아니라 양성
# 대조인 이유는 `_LIT_PROBE` 와 같다 — 파서 퇴화는 「판정이 뒤집힌다」가 아니라
# 「덜 읽는다/못 읽는다」로 나타나고, 그 방향은 변이가 아니라 정답표가 잡는다.
_DECL_PROBE = '''\
import os

_REPO = "/wt-selftest"

_TT_SUPPORTED_OPCODES = list(range(0x00, 0x03)) + [0x10]
_TT_UNSUPPORTED_PROBES: list[int] = [0x20, *[0x21, 0x22]]
_TT_DATA_EH_KINDS = ['imm16', *['imm32', 'mem']]
_TT_FLAGS: list[int] = [0x0, 0x8]
_TT_EXT_NIBBLES = [0x1, 0xF]
_TT_DOMAIN_VERSION: int = 9
_TT_PATH = os.path.join(_REPO, 'isa', 'truth_table_encwave.json')
_TT_FROZEN_PREMIGRATION_PATH = os.path.join(
    _REPO, 'isa', 'truth_table_premigration.json')


def _tt_domain():
    from itertools import combinations
    subsets = [()]
    for ksize in (1, 2):
        subsets.extend(combinations(_TT_DATA_EH_KINDS, ksize))
    for op in sorted(_TT_SUPPORTED_OPCODES + _TT_UNSUPPORTED_PROBES):
        for fl in _TT_FLAGS:
            for sub in subsets:
                yield (op, sub, fl, True)
            yield (op, (), fl, False)
'''
_DECL_WANT = {
    "_TT_SUPPORTED_OPCODES": [0x00, 0x01, 0x02, 0x10],
    "_TT_UNSUPPORTED_PROBES": [0x20, 0x21, 0x22],
    "_TT_DATA_EH_KINDS": ["imm16", "imm32", "mem"],
    "_TT_FLAGS": [0x0, 0x8],
    "_TT_EXT_NIBBLES": [0x1, 0xF],
    "_TT_DOMAIN_VERSION": 9,
    "_SUBSET_SIZES": [1, 2],
}

#: 형상 축 순회가 **모호할 때** 조용히 첫 것을 집지 않는지 — 음성 방향.
_DECL_PROBE_AMBIGUOUS = _DECL_PROBE.replace(
    "    subsets = [()]\n",
    "    subsets = [()]\n    for extra in (7, 8, 9):\n        subsets.append(extra)\n",
)

# ── 키 파서 양성 대조 ───────────────────────────────────────────────────────
# 좁히면(정규식이 한 표기를 못 읽으면) 그 키가 「읽지 못함」으로 크게 울어야
# 하고, 넓히면(아무거나 매치하면) 오조준이 통과한다. 양방향을 다 건다.
_KEY_PROBE_OK = [
    ("0x000||0x0|P", 0x000),
    ("0x06B|imm16|0x8|P", 0x06B),
    ("0x0FF|imm16,imm32,imm64|0x0|-", 0x0FF),
    ("0xF6a|mem|0xF|P", 0xF6A),
]
_KEY_PROBE_BAD = ["0x00||0x0|P", "0x0000||0x0|P", "0x00G||0x0|P", "0x000|imm16|0x0|X"]


def _domain_paths() -> list[Path]:
    """이 검사가 읽는 **정의역 경로 전부**를 모듈 상수에서 뽑는다.

    손으로 유지되는 픽스처 목록은 반드시 뒤처지고, 뒤처진 픽스처에서는 새 축이
    「파일 부재」로 엉뚱하게 울거나(운이 좋을 때) 아예 안 돈다.
    """
    out: list[Path] = []
    for name, val in sorted(globals().items()):
        if name == "REPO" or name.startswith("_"):
            continue
        if isinstance(val, Path):
            out.append(val)
        elif isinstance(val, dict):
            out.extend(k for k in val if isinstance(k, Path))
    return sorted(set(out))


def _build_fixture(root: Path) -> Path:
    base = root / "repo"
    me = Path(__file__).resolve()
    (base / "scripts").mkdir(parents=True, exist_ok=True)
    shutil.copy2(me, base / "scripts" / me.name)
    for p in _domain_paths():
        if not p.is_file():
            raise _MutationMiss(f"정의역 경로가 실재하지 않는다: {p}")
        tgt = base / p.relative_to(REPO)
        tgt.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(p, tgt)
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


def _mutations() -> list[tuple]:
    """`(번호, 설명, 적용함수, 기대 문면들[, 금지 문면들])`.

    닻과 기댓값은 **기준 파일을 파싱해서** 만든다. 리터럴을 박으면 값이 바뀐
    날 조용히 무효가 된다.
    """
    dom = parse_capture_domain(DOMAIN_DECL)
    isa = json.loads(ISA_SOURCE.read_text(encoding="utf-8"))
    supported = sorted(set(dom["_TT_SUPPORTED_OPCODES"]))  # type: ignore[arg-type]
    probes = sorted(set(dom["_TT_UNSUPPORTED_PROBES"]))  # type: ignore[arg-type]
    domain = set(supported) | set(probes)
    isa_codes = {int(o["code"]) for o in isa["opcodes"]}

    # ISA 에 실재하면서 「지원」으로 캡처된 코드점 하나 — m1 의 닻.
    victim = next((c for c in supported if c in isa_codes), None)
    if victim is None:
        raise _MutationMiss("ISA 에 실재하는 지원 opcode 가 없다")
    victim_entry = next(o for o in isa["opcodes"] if int(o["code"]) == victim)

    # 도메인 **밖**의 빈 코드점 하나 — m2 의 닻 (오늘은 0x07 부근).
    free = next((c for c in range(0, DOMAIN_CEILING + 1)
                 if c not in domain and c not in isa_codes), None)
    if free is None:
        raise _MutationMiss("도메인 밖의 빈 코드점이 없다")

    # ISA 가 배정했으면서 천장 **위**인 코드점 하나 — m17/m18 의 닻.
    above_op = next((c for c in sorted(isa_codes) if c > DOMAIN_CEILING), None)
    if above_op is None:
        raise _MutationMiss(
            f"ISA 에 0x{DOMAIN_CEILING:02X} 초과 배정이 없다 — 천장 축의 변이를 "
            f"지을 수 없다. 천장이 정말 ISA 최대치를 넘었다면 이 변이가 아니라 "
            f"`DOMAIN_CEILING` 의 존재 이유를 다시 물어야 한다")

    # 미지원 탐침이면서 ISA 에 **없는** 코드점 하나 — m8 의 닻.
    probe_free = next((c for c in probes
                       if c not in isa_codes and c not in PROBE_YET_ASSIGNED), None)
    if probe_free is None:
        raise _MutationMiss("ISA 에 없는 미지원 탐침이 없다")

    frozen_path = next(iter(FROZEN))
    frozen_rel = frozen_path.relative_to(REPO)
    frozen_dv = FROZEN[frozen_path][2]
    me_name = Path(__file__).resolve().name

    oracle_live = json.loads(ORACLE.read_text(encoding="utf-8"))
    ext_victim = sorted(oracle_live["ext_probes"])[0]
    # 도메인 **밖**이면서 표기가 정상인 키 하나 — `only_oracle` 축의 닻.
    stray_key = _key(free, (), 0x0, True)
    if stray_key in oracle_live["points"]:
        raise _MutationMiss(f"닻으로 쓸 키가 이미 오라클에 있다: {stray_key}")

    sup_src = _decl_source(DOMAIN_DECL, "_TT_SUPPORTED_OPCODES")
    probe_src = _decl_source(DOMAIN_DECL, "_TT_UNSUPPORTED_PROBES")
    kinds_src = _decl_source(DOMAIN_DECL, "_TT_DATA_EH_KINDS")
    dv_src = _decl_source(DOMAIN_DECL, "_TT_DOMAIN_VERSION")
    flags_src = _decl_source(DOMAIN_DECL, "_TT_FLAGS")
    ttpath_src = _decl_source(DOMAIN_DECL, "_TT_PATH")
    ttfrozen_src = _decl_source(DOMAIN_DECL, "_TT_FROZEN_PREMIGRATION_PATH")

    def isa_of(b: Path) -> Path:
        return b / ISA_SOURCE.relative_to(REPO)

    def decl_of(b: Path) -> Path:
        return b / DOMAIN_DECL.relative_to(REPO)

    def oracle_of(b: Path) -> Path:
        return b / ORACLE.relative_to(REPO)

    def me_of(b: Path) -> Path:
        return b / "scripts" / me_name

    # ── m1 : ISA 에서 opcode 하나 제거 ─────────────────────────────────────
    # 도메인은 그대로라 「고아」축(m2)으로는 안 잡힌다. 「지원인데 ISA 에
    # 없다」축이 물어야 한다 — 나란한 두 방향 중 하나만 덮이는 것이 이
    # 저장소의 상습 실패형이다.
    def m1(b: Path) -> None:
        d = json.loads(isa_of(b).read_text(encoding="utf-8"))
        n = len(d["opcodes"])
        d["opcodes"] = [o for o in d["opcodes"] if int(o["code"]) != victim]
        if len(d["opcodes"]) != n - 1:
            raise _MutationMiss(f"ISA 에서 0x{victim:02X} 를 지우지 못했다")
        isa_of(b).write_text(json.dumps(d), encoding="utf-8")

    # ── m2 : ISA 에 합성 opcode 추가 ───────────────────────────────────────
    # 「오라클에 한 점도 없이 태어난다」— 이 파일이 사는 가장 큰 이유.
    def m2(b: Path) -> None:
        d = json.loads(isa_of(b).read_text(encoding="utf-8"))
        clone = dict(victim_entry)
        clone["code"] = free
        clone["mnemonic"] = "WT_SELFTEST_PROBE"
        d["opcodes"].append(clone)
        isa_of(b).write_text(json.dumps(d), encoding="utf-8")

    # ── m3 : 동결 표 1 바이트 반전 ─────────────────────────────────────────
    def m3(b: Path) -> None:
        f = b / frozen_rel
        raw = bytearray(f.read_bytes())
        # outcome 벡터가 사는 자리. `indent=0` 캡처라 원소가 줄마다 놓인다 —
        # 닻을 손으로 박지 않고 **실제 바이트열**에서 찾는다.
        #
        # ⚠️ 오늘의 상주 단언 셋(`domain_version == 3` · opcode 수 > 50 ·
        # fp-block 키 0건)은 이 뒤집기를 **전부 통과한다.** 그것이 이 핀이
        # 있는 이유다 — docstring 은 「한 바이트라도 움직이면 울린다」고
        # 적었는데 집행은 그 주장을 뒷받침하지 않았다 (실측 2026-08-30).
        old, new = b"[\n1,\n0,\n0\n]", b"[\n0,\n0,\n1\n]"
        i = raw.rfind(old)
        if i < 0:
            raise _MutationMiss("동결 표에서 outcome 벡터를 찾지 못했다")
        raw[i:i + len(old)] = new
        f.write_bytes(bytes(raw))

    # ── m4 : 핀을 premigration 대신 encwave 로 겨눔 (오조준) ────────────────
    # 「두 표를 다 갱신하려 드는」 순진한 게이트가 만드는 자리다. 자료구조가
    # 구분을 나르는지를 여기서 잰다.
    def m4(b: Path) -> None:
        _sub(me_of(b),
             'REPO / "isa" / "truth_table_premigration.json": (',
             'REPO / "isa" / "truth_table_encwave.json": (')

    # ── m4b : 동결 경로에 **쓰기**를 여는 코드 경로 ─────────────────────────
    # 자산 파괴 경로 그 자체 — 「두 표를 다 갱신」하려는 순진한 게이트가 만드는
    # 자리다. 「읽기만 한다」가 집행인지 주석인지를 여기서 가른다. 변이는
    # `run()` **안**에 넣는다: 오염 전파를 한 마디 건너(`FROZEN.items()` 의
    # 순회 대상 `path`) 따라가는지까지 재기 위해서다.
    read_anchor = "        raw = path.read_bytes()"

    def m4b(b: Path) -> None:
        _sub(me_of(b), read_anchor,
             read_anchor + "\n        path.write_bytes(raw)  # wt-selftest")

    # ── m5 : 도메인 공집합 → 하한이 물어야 한다 ────────────────────────────
    def m5(b: Path) -> None:
        _sub(decl_of(b), sup_src, "_TT_SUPPORTED_OPCODES = []")
        _sub(decl_of(b), probe_src, "_TT_UNSUPPORTED_PROBES = []")

    # ── m5b : 하한 상수를 올려 **하한 분기만** 격리한다 ────────────────────
    # (m5 는 여러 분기를 동시에 울린다. 하한이 실제로 서 있는지는 이렇게만
    #  격리된다 — `lint_selftest_coverage` S3 가 같은 이유로 이 형태다.)
    def m5b(b: Path) -> None:
        _sub(me_of(b), f"_MIN_DOMAIN_OPCODES = {_MIN_DOMAIN_OPCODES}",
             f"_MIN_DOMAIN_OPCODES = {len(domain) + 5}")

    # ── m6 : 오라클에서 한 opcode 의 점을 통째로 제거 ──────────────────────
    def m6(b: Path) -> None:
        f = oracle_of(b)
        d = json.loads(f.read_text(encoding="utf-8"))
        pre = f"0x{victim:03X}|"
        gone = [k for k in d["points"] if k.startswith(pre)]
        if not gone:
            raise _MutationMiss(f"오라클에 0x{victim:03X} 점이 없다")
        for k in gone:
            del d["points"][k]
        f.write_text(json.dumps(d), encoding="utf-8")

    # ── m7 : domain_version 이 갈라짐 (재캡처와 dv 범프가 따로 놀았다) ──────
    def m7(b: Path) -> None:
        _sub(decl_of(b), dv_src,
             f"_TT_DOMAIN_VERSION = {int(dom['_TT_DOMAIN_VERSION']) + 1}")

    # ── m8 : 미지원 탐침에 ISA 가 명령을 배정 (outcome 계급이 낡는다) ──────
    # 도메인은 **자라지 않는다** — 점도 그대로다. m2 로는 절대 안 잡힌다.
    def m8(b: Path) -> None:
        d = json.loads(isa_of(b).read_text(encoding="utf-8"))
        clone = dict(victim_entry)
        clone["code"] = probe_free
        clone["mnemonic"] = "WT_SELFTEST_REALLOC"
        d["opcodes"].append(clone)
        isa_of(b).write_text(json.dumps(d), encoding="utf-8")

    # ── m9 : 재배정 등재가 낡음 (표가 실물보다 넓어지는 방향) ──────────────
    def m9(b: Path) -> None:
        _sub(me_of(b), "PROBE_YET_ASSIGNED: dict[int, str] = {",
             "PROBE_YET_ASSIGNED: dict[int, str] = {\n"
             f"    0x{probe_free:02X}: 'wt-selftest probe',")

    # ── m10 : 형상 축이 갈라짐 (EH 종류가 하나 늘었다) ─────────────────────
    # 키 집합 재유도가 **형상까지** 재는지를 잰다. opcode 집합만 대조하는
    # 얕은 검사였다면 여기서 초록이다.
    def m10(b: Path) -> None:
        kinds = list(dom["_TT_DATA_EH_KINDS"])  # type: ignore[arg-type]
        _sub(decl_of(b), kinds_src,
             "_TT_DATA_EH_KINDS = " + repr(kinds + ["wt_selftest_kind"]))

    # ── m11 : 키 표기가 조용히 갈라짐 (3자리 → 2자리) ──────────────────────
    def m11(b: Path) -> None:
        f = oracle_of(b)
        d = json.loads(f.read_text(encoding="utf-8"))
        k = sorted(d["points"])[0]
        d["points"]["0x" + k[3:]] = d["points"].pop(k)
        f.write_text(json.dumps(d), encoding="utf-8")

    # ── m5c · m5d : **나란한 하한 분기**를 각각 격리한다. ──────────────────
    # 「나란한 두 분기 중 하나만 덮여 있었다」가 이 저장소의 상습 얼굴이다
    # (`lint_toolchain_pins` N11–N17 이 그 실측 기록이다). 하한이 셋이면
    # 변이도 셋이어야 한다 — 하나만 걸고 「하한이 선다」고 말하지 않는다.
    def m5c(b: Path) -> None:
        _sub(me_of(b), f"_MIN_POINTS = {_MIN_POINTS}",
             f"_MIN_POINTS = {len(json.loads(ORACLE.read_text())['points']) + 5}")

    def m5d(b: Path) -> None:
        n = len({c for c in isa_codes if c <= DOMAIN_CEILING})
        _sub(me_of(b), f"_MIN_ISA_OPCODES = {_MIN_ISA_OPCODES}",
             f"_MIN_ISA_OPCODES = {n + 5}")

    # ── m13 : 동결 표가 사라짐 ─────────────────────────────────────────────
    # 「없으면 대조할 것이 없다」를 통과로 세지 않는지. 파일 부재를 조용히
    # 넘기는 검사는 자산이 지워진 날 초록을 인쇄한다.
    def m13(b: Path) -> None:
        (b / frozen_rel).unlink()

    # ── m3b : 동결 핀의 **dv 칸**만 어긋남 (해시는 맞다) ───────────────────
    # 나란한 쌍의 반대편이다: m3 은 해시 축, 이것은 **지위 선언** 축. 예전
    # 판에서 `if dv != want_dv:` 를 죽여도 자기시험이 초록이었다 (실측).
    def m3b(b: Path) -> None:
        _sub(me_of(b), f"\n        {frozen_dv},  # domain_version",
             f"\n        {frozen_dv + 1},  # domain_version")

    # ── m4c : 쓰기를 **호출 한 마디 건너** 숨긴다 ──────────────────────────
    # m4b 는 같은 함수 안 변이만 재므로 이 갈래를 증명하지 못했다. 예전 판은
    # 여기서 뚫렸고 — AST 는 아무 자리도 보고하지 않았고, 픽스처의 동결 표가
    # 실제로 파괴된 뒤 사후 해시가 울었다. 그래서 금지 문면이 「동결 표가
    # 움직였다」다: 사후 검출로 우는 것은 **잡은 것이 아니다.**
    def m4c(b: Path) -> None:
        _sub(me_of(b), "def run(quiet: bool = False) -> int:",
             "def _wt_selftest_refresh(p):\n"
             "    p.write_bytes(b'{}')\n\n\n"
             "def run(quiet: bool = False) -> int:")
        _sub(me_of(b), read_anchor,
             read_anchor + "\n        _wt_selftest_refresh(path)  # wt-selftest")

    # ── m5e : ext_probes 하한 분기 격리 (_MIN_EXT_PROBES) ──────────────────
    # m5c 의 나란한 쌍. 예전 판은 `("points", …), ("ext_probes", …)` 에서 ext
    # 항을 **삭제해도** 자기시험이 초록이었다 (실측).
    def m5e(b: Path) -> None:
        _sub(me_of(b), f"_MIN_EXT_PROBES = {_MIN_EXT_PROBES}",
             f"_MIN_EXT_PROBES = {len(oracle_live['ext_probes']) + 5}")

    # ── m6b : ext_probes 에서 키 하나 제거 (only_decl 축, 확장 니블) ───────
    # 207 점짜리 확장 니블 축 **전량**이 예전 판에서 무검이었다: 집합 대조
    # 루프에서 ext 항을 지워도 초록. m6 의 나란한 쌍이다.
    def m6b(b: Path) -> None:
        f = oracle_of(b)
        d = json.loads(f.read_text(encoding="utf-8"))
        if ext_victim not in d["ext_probes"]:
            raise _MutationMiss(f"오라클 ext_probes 에 {ext_victim} 이 없다")
        del d["ext_probes"][ext_victim]
        f.write_text(json.dumps(d), encoding="utf-8")

    # ── m6c : 오라클에 **표기가 정상인** 도메인 밖 점을 심는다 ─────────────
    # `only_oracle` 축(「캡처 도메인이 줄었다」방향) 전체가 예전 판에서
    # 무검이었다 — `if only_oracle:` 를 죽여도 초록. m11 은 **표기 불량**
    # 축으로 울기 때문에 이 갈래를 대신하지 못한다. 그래서 여기 키는
    # `_KEY_RE` 를 통과하는 정상 표기다.
    def m6c(b: Path) -> None:
        f = oracle_of(b)
        d = json.loads(f.read_text(encoding="utf-8"))
        d["points"][stray_key] = d["points"][sorted(d["points"])[0]]
        f.write_text(json.dumps(d), encoding="utf-8")

    # ── m6d : 오라클에서 `ext_probes` 절이 통째로 사라짐 ───────────────────
    # `if sec not in oracle:` 를 죽여도 초록이었다 (실측). 절이 없으면 그 축은
    # 「대조했더니 같았다」가 아니라 「대조할 것이 없었다」다.
    def m6d(b: Path) -> None:
        f = oracle_of(b)
        d = json.loads(f.read_text(encoding="utf-8"))
        del d["ext_probes"]
        f.write_text(json.dumps(d), encoding="utf-8")

    # ── m14 : 캡처 대상을 **동결 표로** 돌려놓는다 ─────────────────────────
    # 자산 파괴의 실제 입구다. 예전 판은 `_TT_PATH` 를 한 번도 읽지 않아
    # (`grep -c _TT_PATH` → 0) 이 변이 아래서 rc=0 이었고, 하필 그 파일을
    # 「불변 대상(재캡처 대상이 아니다)」이라 인쇄했다.
    def m14(b: Path) -> None:
        _sub(decl_of(b), ttpath_src,
             "_TT_PATH = os.path.join(_REPO, 'isa', "
             "'truth_table_premigration.json')")

    # ── m14b : 캡처 대상이 제3 의 파일로 갈라진다 ──────────────────────────
    # 「게이트가 읽는 파일 ≠ 캡처가 쓰는 파일」 = 게이트 전체가 공허.
    def m14b(b: Path) -> None:
        _sub(decl_of(b), ttpath_src,
             "_TT_PATH = os.path.join(_REPO, 'isa', 'wt_selftest_elsewhere.json')")

    # ── m14c : 동결 상수가 핀 표 밖을 가리킨다 (나란한 반대 방향) ──────────
    def m14c(b: Path) -> None:
        _sub(decl_of(b), ttfrozen_src,
             "_TT_FROZEN_PREMIGRATION_PATH = os.path.join(\n"
             "    _REPO, 'isa', 'wt_selftest_unpinned.json')")

    # ── m15 : 정의역 천장을 올린다 (DOMAIN_CEILING) ────────────────────────
    # 천장은 판정인데 예전 판에는 그것을 겨눈 변이가 **0 건**이었다 — 내리는
    # 방향만 `_MIN_ISA_OPCODES` 하한에 우연히 걸렸다. 올리면 0x70 블록이
    # 정의역 안으로 들어오고, 그 블록의 오라클 점은 0 이므로 (a) 축이 물어야
    # 한다. 무는지가 곧 「천장이 하중을 진다」의 증명이다.
    #
    # ⚠️ 닻은 **줄 전체**다. `DOMAIN_CEILING = 0x6F` 만 쓰면 머리주석의 같은
    #    문자열이 먼저 걸려 상수는 그대로 남고 변이가 조용히 무효가 된다
    #    (실측 — 이 변이의 첫 판이 정확히 그렇게 rc=0 이었다).
    def m15(b: Path) -> None:
        _sub(me_of(b), f"\nDOMAIN_CEILING = 0x{DOMAIN_CEILING:02X}\n",
             f"\nDOMAIN_CEILING = 0x{max(isa_codes):02X}\n")

    # ── m17 : 캡처 **선언**이 천장 위로 자란다 (천장 낡음 · 선언 쪽) ───────
    # 「지원인데 ISA 에 없다」축으로 우는 것은 **틀린 진단**이다 — 0x70 은
    # ISA 에 실재한다. 금지 문면이 그 오진을 못박는다.
    def m17(b: Path) -> None:
        _sub(decl_of(b), sup_src,
             f"_TT_SUPPORTED_OPCODES = list({supported!r}) + [0x{above_op:02X}]")

    # ── m18 : **오라클**만 천장 위로 자란다 (천장 낡음 · 오라클 쪽) ────────
    # m17 의 나란한 쌍. 선언은 그대로이므로 m17 축은 침묵해야 한다.
    def m18(b: Path) -> None:
        f = oracle_of(b)
        d = json.loads(f.read_text(encoding="utf-8"))
        ext0 = sorted(set(dom["_TT_EXT_NIBBLES"]))[0]  # type: ignore[arg-type]
        d["ext_probes"][_key((ext0 << 8) | above_op, (), 0x0, True)] = \
            d["ext_probes"][ext_victim]
        f.write_text(json.dumps(d), encoding="utf-8")

    # ── m16 : 파서가 정말 못 읽는 표기 → **처방이 갈리는지** ───────────────
    # 잡는지만이 아니라 **무엇을 하라고 인쇄하는지**를 잰다. 예전 판은 이
    # 실패에 재캡처 7 단계를 붙였다 — 원인은 파서인데 처방은 자산을 움직인다.
    # 금지 문면이 그 오진을 못박는다.
    def m16(b: Path) -> None:
        _sub(decl_of(b), flags_src, "_TT_FLAGS = [x for x in (0x0, 0x8)]")

    # ── m12 : 동결 핀 표를 비움 (이 축이 아무것도 안 재게 된다) ────────────
    def m12(b: Path) -> None:
        f = me_of(b)
        text = f.read_text(encoding="utf-8")
        i = text.index("FROZEN: dict[Path, tuple[str, str, int]] = {")
        j = text.index("\n}\n", i) + len("\n}\n")
        f.write_text(text[:i] + "FROZEN: dict[Path, tuple[str, str, int]] = {}\n"
                     + text[j:], encoding="utf-8")

    return [
        ("m1", f"ISA 에서 지원 opcode 0x{victim:02X} 제거", m1,
         ("ISA 에 없는데 「지원」으로 캡처된 opcode", f"0x{victim:02X}")),
        ("m2", f"ISA 에 합성 opcode 0x{free:02X} 추가 (도메인 밖)", m2,
         ("오라클에 한 점도 없는 opcode", f"0x{free:02X}", "영원히 공집합")),
        ("m3", f"{frozen_rel} 의 outcome 벡터 1 개 반전", m3,
         ("동결 표가 움직였다", str(frozen_rel), "blake2b-512")),
        ("m4", "동결 핀을 재생성 대상(encwave)으로 오조준", m4,
         ("**오조준**", "truth_table_encwave.json", "둘째 선언처")),
        ("m4b", "동결 경로에 쓰기를 여는 코드 경로 삽입", m4b,
         ("동결 경로에 쓰기를 연다", "읽기만 해야 한다"),
         # 정적으로 막혔다면 쓰기는 **실행되지 않는다** — 사후 해시가 울면
         # 그것은 「부수고 나서 알아챘다」이지 잡은 것이 아니다.
         ("동결 표가 움직였다",)),
        ("m4c", "쓰기를 **호출 한 마디 건너** 숨김 (inter-procedural)", m4c,
         ("동결 경로에 쓰기를 연다", "읽기만 해야 한다",
          "_wt_selftest_refresh"),
         ("동결 표가 움직였다",)),
        ("m3b", f"동결 핀의 dv 칸만 어긋남 ({frozen_dv}→{frozen_dv + 1})", m3b,
         (f"domain_version {frozen_dv} ≠ 핀 {frozen_dv + 1}", "핀 표가 낡았다"),
         ("동결 표가 움직였다",)),
        # 금지 문면 `3 회 캡처해` 는 `_RECAPTURE_HOWTO` 에만 있다 — 이 셋에
        # 그것이 인쇄되면 **처방이 곧 사고**다 (재캡처가 동결 표를 덮는다).
        ("m14", "캡처 대상(`_TT_PATH`)을 **동결 표로** 돌려놓음", m14,
         ("캡처가 동결 표를 겨눈다", str(frozen_rel), "계보 증거 파괴",
          "재캡처를 실행하지 마라"),
         ("3 회 캡처해",)),
        ("m14b", "캡처 대상이 제3 의 파일로 갈라짐", m14b,
         ("캡처 대상이 갈라졌다", "이 게이트 전체가 공허",
          "재캡처를 실행하지 마라"),
         ("3 회 캡처해",)),
        ("m14c", "동결 상수(`_TT_FROZEN_…`)가 핀 표 밖을 가리킴", m14c,
         ("동결 상수가 핀 표와 갈라졌다", "바이트 핀 밖에 있다"),
         ("3 회 캡처해",)),
        ("m16", "파서가 못 읽는 표기 → **파서 처방**이 인쇄되는가", m16,
         ("캡처 도메인 선언을 읽지 못했다", "읽지 못한 표기",
          "재캡처가 아니다", "한 줄 되돌리기"),
         ("3 회 캡처해",)),
        ("m15", f"정의역 천장을 0x{DOMAIN_CEILING:02X}→0x{max(isa_codes):02X} "
                f"로 올림", m15,
         ("오라클에 한 점도 없는 opcode", f"0x{above_op:02X}", "영원히 공집합")),
        ("m17", f"캡처 **선언**이 천장 위로 자람 (0x{above_op:02X})", m17,
         ("천장이 낡았다 (선언 쪽)", f"0x{above_op:02X}", "천장 선언이 낡은"),
         # 0x70 은 ISA 에 실재한다 — 「지원인데 ISA 에 없다」는 오진이다.
         ("ISA 에 없는데 「지원」으로 캡처된 opcode",
          "천장이 낡았다 (오라클 쪽)")),
        ("m18", f"**오라클**만 천장 위로 자람 (0x{above_op:02X})", m18,
         ("천장이 낡았다 (오라클 쪽)", f"0x{above_op:02X}", "셋이 서로 갈라졌다"),
         ("천장이 낡았다 (선언 쪽)",)),
        ("m5", "캡처 도메인 공집합 — 하한이 물어야 한다", m5,
         ("< 하한", "0 건은 통과가 아니다")),
        ("m5b", "도메인 하한 분기 격리 (_MIN_DOMAIN_OPCODES)", m5b,
         ("캡처 도메인", "< 하한", "0 건은 통과가 아니다")),
        ("m5c", "오라클 점수 하한 분기 격리 (_MIN_POINTS)", m5c,
         ("오라클 `points`", "< 하한", "대조가 공허해진다")),
        ("m5d", "ISA 계수 하한 분기 격리 (_MIN_ISA_OPCODES)", m5d,
         ("ISA 소스의 ≤0x6F opcode", "< 하한", "0 건은 통과가 아니다")),
        ("m5e", "ext_probes 하한 분기 격리 (_MIN_EXT_PROBES)", m5e,
         ("오라클 `ext_probes`", "< 하한", "대조가 공허해진다")),
        ("m13", f"동결 표가 사라짐 ({frozen_rel})", m13,
         ("파일 부재", str(frozen_rel))),
        ("m6", f"오라클에서 0x{victim:03X} 의 점을 통째로 제거", m6,
         ("오라클에 없는** 점", f"0x{victim:03X}", "재캡처가 없었다")),
        ("m6b", f"ext_probes 에서 키 하나 제거 ({ext_victim})", m6b,
         ("`ext_probes`: 선언 도메인에는 있는데", "오라클에 없는** 점",
          ext_victim),
         ("읽지 못한 오라클 키",)),
        ("m6c", f"도메인 밖 점을 오라클에 심음 ({stray_key})", m6c,
         ("`points`: 오라클에는 있는데", "선언 도메인에 없는** 점",
          stray_key, "캡처 도메인이 줄었거나"),
         # 표기는 정상이므로 「읽지 못한 키」축으로 우는 것은 다른 분기다.
         ("읽지 못한 오라클 키", "선언 도메인에는 있는데")),
        ("m6d", "오라클에서 `ext_probes` 절이 통째로 사라짐", m6d,
         ("오라클에 `ext_probes` 절이 없다",)),
        ("m7", "domain_version 이 선언과 갈라짐", m7,
         ("domain_version 이 갈라졌다", "한 커밋에")),
        ("m8", f"미지원 탐침 0x{probe_free:02X} 에 ISA 가 명령 배정", m8,
         ("낡은 outcome 계급", f"0x{probe_free:02X}", "PROBE_YET_ASSIGNED"),
         # 도메인은 자라지 않았으므로 (a) 축이 울면 그것은 다른 분기다.
         ("오라클에 한 점도 없는 opcode",)),
        ("m9", f"재배정 등재가 낡음 (0x{probe_free:02X})", m9,
         ("표가 낡았다", f"0x{probe_free:02X}", "등재를 지워라")),
        ("m10", "형상 축이 갈라짐 (data-EH 종류 +1)", m10,
         ("오라클에 없는** 점",)),
        ("m11", "오라클 키 표기가 3자리에서 갈라짐", m11,
         ("읽지 못한 오라클 키", "통과시키지 마라")),
        ("m12", "동결 핀 표를 비움 (이 축이 잰 것이 0 이 된다)", m12,
         ("동결 핀 0건 < 하한", "대조할 것이 없었다")),
    ]


def _refactors() -> list[tuple[str, str, object]]:
    """**의미 무변 리팩터** — 이것들은 rc=0 이어야 한다 (P 계열 양성 대조).

    ⚠️ 변이표의 **반대편**이다. 변이는 「물어야 할 때 무는가」를 재고, 이것은
    「물면 안 될 때 안 무는가」를 잰다. 한쪽만 세우면 게이트는 조여지는
    방향으로만 자라고, 거짓 실패가 쌓인 게이트는 결국 꺼진다 — 꺼진 게이트는
    없는 게이트다.

    셋 다 실측에서 온 것이다 (2026-08-30). 예전 판은 셋 다 rc=1 이었고,
    그 실패 문면이 **재캡처 7 단계**를 인쇄했다 — 실제 처방은 한 줄 되돌리기
    였는데. 원인과 무관하게 자산을 움직이는 처방이 이 저장소의 F-52 부류다.

    닻도 기댓값도 **기준 파일에서 뽑는다.** 리터럴을 박으면 표기가 바뀐 날
    「지점 부재」로 조용히 무효가 된다.
    """
    dom = parse_capture_domain(DOMAIN_DECL)
    flags_src = _decl_source(DOMAIN_DECL, "_TT_FLAGS")
    kinds_src = _decl_source(DOMAIN_DECL, "_TT_DATA_EH_KINDS")
    kinds = [str(x) for x in dom["_TT_DATA_EH_KINDS"]]  # type: ignore[union-attr]
    if len(kinds) < 2:
        raise _MutationMiss("data-EH 종류가 2 개 미만이라 펼침 리팩터를 못 짓는다")
    half = len(kinds) // 2

    def decl_of(b: Path) -> Path:
        return b / DOMAIN_DECL.relative_to(REPO)

    # ── r1 : 타입 주석 추가 (Assign → AnnAssign) ───────────────────────────
    def r1(b: Path) -> None:
        head, _, tail = flags_src.partition("=")
        _sub(decl_of(b), flags_src, f"{head.rstrip()}: list[int] ={tail}")

    # ── r2 : `*` 펼침으로 같은 목록을 다시 쓴다 ────────────────────────────
    def r2(b: Path) -> None:
        _sub(decl_of(b), kinds_src,
             "_TT_DATA_EH_KINDS = ["
             + ", ".join(repr(x) for x in kinds[:half])
             + ", *" + repr(kinds[half:]) + "]")

    # ── r3 : `_tt_domain()` 의 **지역** 루프 변수를 순수 개명 ──────────────
    #        (지역 변수 이름은 캡처의 계약이 아니다.)
    def r3(b: Path) -> None:
        p = decl_of(b)
        text = p.read_text(encoding="utf-8")
        tree = ast.parse(text, filename=str(p))
        lines = text.splitlines(keepends=True)
        for node in ast.walk(tree):
            if not (isinstance(node, ast.FunctionDef)
                    and node.name == "_tt_domain"):
                continue
            for sub in ast.walk(node):
                if not (isinstance(sub, ast.For)
                        and isinstance(sub.target, ast.Name)):
                    continue
                try:
                    sizes = _eval_literal(sub.iter)
                except _ParseError:
                    continue
                if not (isinstance(sizes, list) and sizes
                        and all(isinstance(x, int) for x in sizes)):
                    continue
                old = sub.target.id
                new = f"{old}_renamed_by_selftest"
                span = "".join(lines[node.lineno - 1:node.end_lineno])
                if not re.search(rf"\b{re.escape(old)}\b", span):
                    raise _MutationMiss(f"루프 변수 `{old}` 를 본문에서 못 찾았다")
                fixed = re.sub(rf"\b{re.escape(old)}\b", new, span)
                p.write_text(
                    "".join(lines[:node.lineno - 1]) + fixed
                    + "".join(lines[node.end_lineno:]), encoding="utf-8")
                return
        raise _MutationMiss("`_tt_domain()` 의 형상 축 루프를 찾지 못했다")

    def r_all(b: Path) -> None:
        r1(b)
        r2(b)
        r3(b)

    return [
        ("P1", "타입 주석 추가 (`_TT_FLAGS: list[int] = …`)", r1),
        ("P2", "`*` 펼침으로 같은 목록 재작성 (`_TT_DATA_EH_KINDS`)", r2),
        ("P3", "`_tt_domain()` 지역 루프 변수 순수 개명", r3),
        ("P4", "셋 **동시** 적용 (실측 재현: 예전 판은 셋 다 재캡처를 지시했다)",
         r_all),
    ]


def _decl_source(path: Path, name: str) -> str:
    """모듈 최상위 대입의 **원문**을 돌려준다 (변이의 닻).

    리터럴을 이 파일에 박지 않기 위해서다 — 값이 바뀐 날 「치환 못 함 = 변화
    없음 = 잡지 못함」으로 조용히 무효가 되는 것을 막는다.
    """
    text = path.read_text(encoding="utf-8")
    tree = ast.parse(text, filename=str(path))
    lines = text.splitlines(keepends=True)
    for node in tree.body:
        hit = False
        if isinstance(node, ast.Assign):
            hit = any(isinstance(t, ast.Name) and t.id == name
                      for t in node.targets)
        elif isinstance(node, ast.AnnAssign) and node.value is not None:
            # 파서가 AnnAssign 을 읽게 됐으므로 닻도 같이 읽어야 한다 —
            # 안 그러면 주석이 붙는 날 변이가 「지점 부재」로 조용히 죽는다.
            hit = isinstance(node.target, ast.Name) and node.target.id == name
        if hit:
            return "".join(lines[node.lineno - 1:node.end_lineno]).rstrip("\n")
    raise _MutationMiss(f"{path.name}: `{name}` 대입을 찾지 못했다")


def self_test() -> int:
    print(f"{TAG}: 음성 시험 — 격리 사본(/tmp)에서 변이 주입")
    rows: list[tuple[bool, str, str]] = []
    ok = True

    try:
        muts = _mutations()
        refs = _refactors()
    except (_MutationMiss, _ParseError) as e:
        print(f"  ✗ 변이표를 짓지 못했다 — {e}", file=sys.stderr)
        print("음성 시험 불통과 (변이 0건은 통과가 아니다)", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory(prefix="wt-ttdom-neg-") as td:
        root = Path(td)

        # ── ⓪ 정의역 폐쇄 — 변이보다 **먼저**. ─────────────────────────────
        # 「안 돌면서 OK 를 인쇄」가 이 부류의 전형이다.
        try:
            base0 = _build_fixture(root / "d0")
        except _MutationMiss as e:
            print(f"  ✗ D1 {e}", file=sys.stderr)
            return 1

        dom_paths = _domain_paths()
        missing = [str(p.relative_to(REPO)) for p in dom_paths
                   if not (base0 / p.relative_to(REPO)).exists()]
        d1 = len(dom_paths) >= _MIN_DOMAIN_PATHS and not missing
        rows.append((d1, "D1", f"정의역 경로 {len(dom_paths)}개"
                               f"(하한 {_MIN_DOMAIN_PATHS}) 전부 픽스처에 실재"
                               + (f" — 결손 {missing}" if missing else "")))

        # D2 : AST 평가기 양성 대조 — **출력 전체**를 정답표와 대조한다.
        probe = root / "probe_literals.py"
        probe.write_text(_LIT_PROBE, encoding="utf-8")
        got_lit: dict[str, object] = {}
        try:
            for node in ast.parse(_LIT_PROBE).body:
                if isinstance(node, ast.Assign):
                    got_lit[node.targets[0].id] = _eval_literal(node.value)  # type: ignore[union-attr]
        except _ParseError as e:
            got_lit = {"<예외>": str(e)}
        d2 = got_lit == _LIT_WANT
        rows.append((d2, "D2", "AST 평가기 양성 대조 — `list(range())` · `+` 접합 "
                               "· 문자열/정수 리터럴"
                               + ("" if d2 else f" / **어긋남** {got_lit}")))

        # D3 : 키 파서 양성 대조 — 양방향(읽어야 할 것 · 읽으면 안 될 것).
        ok_ops, ok_bad = key_opcodes([k for k, _ in _KEY_PROBE_OK], "probe")
        bad_ops, bad_bad = key_opcodes(_KEY_PROBE_BAD, "probe")
        d3 = (len(_KEY_PROBE_OK) + len(_KEY_PROBE_BAD) >= _MIN_KEY_PROBE
              and not ok_bad
              and ok_ops == {v for _, v in _KEY_PROBE_OK}
              and not bad_ops
              and len(bad_bad) == len(_KEY_PROBE_BAD))
        rows.append((d3, "D3", f"키 파서 양성 대조 — 유효 {len(_KEY_PROBE_OK)} "
                               f"전부 읽고 무효 {len(_KEY_PROBE_BAD)} 전부 "
                               f"「읽지 못함」으로 크게 실패"
                               + ("" if d3 else
                                  f" / **어긋남** ok={sorted(ok_ops)} "
                                  f"ok_bad={ok_bad} bad={sorted(bad_ops)}")))

        # D4 : 변이 건수 하한.
        d4 = len(muts) >= _MIN_MUTATIONS and len(refs) >= _MIN_REFACTORS
        rows.append((d4, "D4", f"변이 {len(muts)}건 ≥ 하한 {_MIN_MUTATIONS} · "
                               f"양성 대조 {len(refs)}건 ≥ 하한 "
                               f"{_MIN_REFACTORS} (0건은 통과가 아니다)"))

        # D5 : **실 트리 계수** — 대조가 실제로 무언가를 재는가.
        try:
            dom = parse_capture_domain(DOMAIN_DECL)
            oracle = json.loads(ORACLE.read_text(encoding="utf-8"))
            n_dom = len(set(dom["_TT_SUPPORTED_OPCODES"])  # type: ignore[arg-type]
                        | set(dom["_TT_UNSUPPORTED_PROBES"]))  # type: ignore[arg-type]
            n_pts = len(expected_points(dom))
            d5 = (n_dom >= _MIN_DOMAIN_OPCODES
                  and n_pts >= _MIN_POINTS
                  and n_pts == len(oracle["points"]))
            rows.append((d5, "D5", f"실 트리 대조 계수 — 도메인 {n_dom} opcode · "
                                   f"재유도 {n_pts:,}점 = 오라클 "
                                   f"{len(oracle['points']):,}점 · ext "
                                   f"{len(expected_ext_probes(dom))}"))
        except (_ParseError, KeyError) as e:
            d5 = False
            rows.append((False, "D5", f"실 트리 계수를 재지 못했다 — {e}"))

        # D6 : **선언 파서** 양성 대조 — 의미 무변 리팩터 셋을 읽는가.
        #      (타입 주석 · `*` 펼침 · 지역 루프 변수 개명. 셋 다 예전 판에서
        #       거짓 실패했고 그 문면이 재캡처를 지시했다.)
        d6_probe = root / "probe_decl.py"
        d6_probe.write_text(_DECL_PROBE, encoding="utf-8")
        d6_note = ""
        try:
            got_decl = parse_capture_domain(d6_probe)
            tg = got_decl.pop("_TARGETS")
            d6 = (got_decl == _DECL_WANT
                  and tg["_TT_PATH"] == ORACLE
                  and tg["_TT_FROZEN_PREMIGRATION_PATH"] in FROZEN)
            if not d6:
                d6_note = f" / **어긋남** {got_decl} {tg}"
        except (_ParseError, KeyError) as e:
            d6, d6_note = False, f" / **예외** {e}"
        # 음성 방향 — 형상 축이 모호하면 조용히 첫 것을 집지 않는다.
        d6b_probe = root / "probe_decl_ambiguous.py"
        d6b_probe.write_text(_DECL_PROBE_AMBIGUOUS, encoding="utf-8")
        try:
            parse_capture_domain(d6b_probe)
            d6 = False
            d6_note += (" / **모호한 형상 축을 조용히 집었다** — 정수 리터럴 "
                        "순회가 둘인데 실패하지 않았다")
        except _ParseError as e:
            if "기계가 고를 수 없다" not in str(e):
                d6 = False
                d6_note += f" / 모호성 실패의 이유가 다르다: {e}"
        rows.append((d6, "D6", "선언 파서 양성 대조 — 타입 주석(AnnAssign) · "
                               "`*` 펼침 · 지역 루프 변수 개명 · 경로 상수 "
                               "지위; 그리고 모호한 형상 축은 **실패**"
                               + d6_note))

        if not (d1 and d2 and d3 and d4 and d5 and d6):
            for good, tag, text in rows:
                print(f"  {'✓' if good else '✗'} {tag} {text}")
            print("음성 시험 불통과 — 정의역 폐쇄가 깨졌다 (변이는 걸지 않았다)",
                  file=sys.stderr)
            return 1

        # ── N0 대조군 — 변이 없는 사본이 통과하는가. **먼저.** ─────────────
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

        # ── P 계열 + 변이 — **병렬로** 돈다 ─────────────────────────────────
        #
        # ⚠️ 비용이 판정에 든다. 이 자기시험은 `make lint` 안에 살고, 훅은 이미
        #    직렬 십수 초다 — 「끄고 싶어지는 게이트는 곧 없는 게이트다」가 이
        #    파일 머리주석의 규율이다. 축을 P 계열 4 + 변이 11 만큼 늘리면서
        #    직렬로 두면 실측 2.3 s → 6.3 s (+170%) 였다. 각 시행은 **독립
        #    격리 사본 + 독립 하위프로세스**라 공유 상태가 없으므로 병렬화가
        #    안전하고, 판정은 순서에 의존하지 않는다(아래에서 원래 순서로
        #    되돌려 인쇄한다 — 사람이 읽는 순서는 결정적이어야 한다).
        #    stdlib 전용 규약은 유지된다 (`concurrent.futures` 는 stdlib).
        pinned_hash = next(iter(FROZEN.values()))[1]
        frozen_fx_rel = next(iter(FROZEN)).relative_to(REPO)

        def _judge_refactor(tag, desc, apply, slot) -> tuple[bool, str, str]:
            base = _build_fixture(root / slot)
            try:
                apply(base)
            except (_MutationMiss, _ParseError) as e:
                return (False, tag, f"{desc} — 리팩터를 적용하지 못했다: {e}")
            rc, out = _run_fixture(base)
            if rc != 0:
                why = [ln.strip() for ln in out.splitlines()
                       if ln.strip().startswith("·")]
                msg = f"{desc} — **의미 무변 리팩터에 거짓 실패한다**"
                if "3 회 캡처해" in out:
                    msg += (" (그리고 **재캡처를 지시했다** — 원인과 무관하게 "
                            "자산을 움직이는 처방이다)")
                if why:
                    msg += f"\n        {why[0][:180]}"
                return (False, tag, msg)
            return (True, tag, f"{desc} — 통과 확인 (거짓 실패 없음)")

        def _judge_mutation(tag, desc, apply, expect, forbid,
                            slot) -> tuple[bool, str, str]:
            base = _build_fixture(root / slot)
            try:
                apply(base)
            except _MutationMiss as e:
                return (False, tag, f"{desc} — 변이 지점을 찾지 못했다: {e}")
            rc, out = _run_fixture(base)

            # ── N8 : **픽스처의 동결 표가 움직였는가.** ────────────────────
            # rc 만 세는 판정은 「정적으로 막았다」와 「부수고 나서 알아챘다」를
            # 구분하지 못한다 — 예전 판이 정확히 그렇게 초록이었다. 이 축을
            # 모든 변이에 건다: m3/m13 말고는 어떤 변이도 동결 표를 못 움직인다.
            #
            # ⚠️ **이 축만을 격리하는 변이는 없다 — 등재하고 넘어간다.**
            # 실측(2026-08-30): 이 축을 통째로 죽여도 자기시험이 초록이었다.
            # 이유는 공허가 아니라 **지배**다 — 파괴가 일어나는 모든 구성이
            # 이미 앞선 축에 걸린다. 정적 검사를 죽이고 쓰기를 심으면 (a) 쓰기가
            # 조기 반환 뒤라 실행되지 않아 rc=0 → 「잡지 못했다」로 붉고,
            # (b) 읽기 앞이면 해시가 어긋나 rc=1 이되 기대 문면이 없어 「다른
            # 이유로 울었다」로 붉다. 그래서 N8 은 **오늘의 그물이 아니라 미래의
            # 그물**이다: `expect` 를 느슨하게 쓴 변이가 나중에 추가될 때
            # 쓰기를 통과시키지 않게 한다. 비용이 0 에 가깝고 위험 방향이
            # 자산 파괴라 남긴다. 처분은 사람이 정한다.
            if tag not in _FROZEN_MAY_MOVE:
                fx = base / frozen_fx_rel
                moved = (not fx.is_file()) or (
                    hashlib.blake2b(fx.read_bytes()).hexdigest() != pinned_hash)
                if moved:
                    return (False, tag,
                            f"{desc} — rc={rc} 이지만 **픽스처의 동결 표가 "
                            f"파괴됐다**. 이 검사가 쓰기를 정적으로 막지 못하고 "
                            f"사후에 알아챘다는 뜻이다 (자산 파괴는 이미 "
                            f"일어났다)")
            if rc == 0:
                return (False, tag,
                        f"{desc} — **검사가 잡지 못했다** (공허한 검사다)")
            miss = [s for s in expect if s not in out]
            if miss:
                # rc 만 보면 여기가 통과로 세어지고, 이 변이가 겨냥한 분기는
                # 조용히 정의역 밖에 남는다.
                return (False, tag,
                        f"{desc} — 실패는 했으나 **다른 이유로** 울었다: "
                        f"기대 문면 부재 {miss}")
            spur = [s for s in forbid if s in out]
            if spur:
                return (False, tag,
                        f"{desc} — 기대 문면은 나왔으나 **겨냥한 분기가 아니라 "
                        f"다른 분기도** 울었다: 금지 문면 {spur}")
            return (True, tag, f"{desc} — FAIL 확인")

        jobs: list[tuple] = []
        for tag, desc, apply in refs:
            jobs.append((_judge_refactor, (tag, desc, apply, f"p_{tag}")))
        for i, mut in enumerate(muts):
            tag, desc, apply, expect = mut[:4]
            forbid = mut[4] if len(mut) > 4 else ()
            jobs.append((_judge_mutation,
                         (tag, desc, apply, expect, forbid, f"m{i}")))

        with cf.ThreadPoolExecutor(max_workers=_WORKERS) as pool:
            futs = [pool.submit(fn, *args) for fn, args in jobs]
            for f in futs:  # 제출 순서대로 거둔다 — 인쇄 순서는 결정적이다
                good, tag, text = f.result()
                rows.append((good, tag, text))
                if not good:
                    ok = False

        # ── N7 : **시행 계수 폐쇄** — 루프가 조용히 비지 않았는가. ─────────
        # D4 는 「표에 몇 건이 들었는가」를 재고, 이것은 「그 중 몇 건이 실제로
        # 돌았는가」를 잰다. 둘은 다르다: 제출 루프를 비우면 D4 는 그대로
        # 초록이고 「전부 기대대로 판정된다」가 인쇄된다 — 실측으로 확인한
        # 구멍이다 (`for … in refs:` → `in []:` 가 rc=0 이었다).
        p_tags = {t for t, _, _ in refs}
        m_tags = {m[0] for m in muts}
        ran_p = {t for _, t, _ in rows if t in p_tags}
        ran_m = {t for _, t, _ in rows if t in m_tags}
        if len(ran_p) != len(refs) or len(ran_m) != len(muts):
            rows.append((False, "N7",
                         f"**시행 계수가 어긋났다** — 양성 대조 {len(ran_p)}/"
                         f"{len(refs)} · 변이 {len(ran_m)}/{len(muts)} 만 실제로 "
                         f"돌았다. 「전부 기대대로」가 「아무것도 안 돌았다」를 "
                         f"뜻하게 되는 자리다"))
            ok = False
        else:
            rows.append((True, "N7",
                         f"시행 계수 폐쇄 — 양성 대조 {len(ran_p)}/{len(refs)} · "
                         f"변이 {len(ran_m)}/{len(muts)} 전부 실제로 돌았다"))

        # 실파일 불변의 실증 — 픽스처 변이가 저장소를 건드리지 않았는가.
        live = hashlib.blake2b(next(iter(FROZEN)).read_bytes()).hexdigest()
        pinned = next(iter(FROZEN.values()))[1]
        if live != pinned:
            rows.append((False, "N9", "**실파일이 움직였다** — 자기시험이 "
                                      "저장소를 더럽혔다"))
            ok = False
        else:
            rows.append((True, "N9", "실파일 불변 — 자기시험 후에도 동결 표의 "
                                     "해시가 그대로다"))

    for good, tag, text in rows:
        print(f"  {'✓' if good else '✗'} {tag} {text}")
    if not ok:
        print(f"음성 시험 불통과 — {sum(1 for g, _, _ in rows if not g)}건이 "
              f"기대대로 판정되지 않았다", file=sys.stderr)
        return 1
    # 계수는 **세어서** 인쇄한다 — 손으로 박은 숫자는 축이 늘어난 날 낡는다
    # (실측: D6 을 더한 뒤에도 문면은 「정의역 폐쇄 5」였다).
    n_dclose = sum(1 for _, t, _ in rows if re.fullmatch(r"D\d+", t))
    print(f"음성 시험 통과 — 대조군 1 + 정의역 폐쇄 {n_dclose} + **양성 "
          f"대조(의미 무변 리팩터) {len(refs)}** + 변이 {len(muts)} + 실파일 "
          f"불변 1 전부 기대대로 판정된다 (병렬 폭 {_WORKERS})")
    print("  ⚠ 이것은 **이 검사가 무는지**를 재는 것이지 오라클의 outcome 이 "
          "옳은지를 재는 것이 아니다 — 후자는 CI 의 6,141점 차등 시험만 잰다.")
    return 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(self_test())
    sys.exit(run())
