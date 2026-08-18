#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""v1.9.1 §31.14 CI lint — `expect_fail` **양방향 래칫의 기계 집행**.

무엇이 새어 나갔는가 (이 파일이 생긴 이유)
------------------------------------------
§28.4 항 8(e) 는 *"수리하지 않기로 결정된 결함은 golden 을 assert 하는
테스트 + `@cocotb.test(expect_fail=True)` 로 기록한다"* 를 규범화했고,
§31.13.6 은 그것이 **양방향 래칫**이라고 적었다 — 결함이 고쳐져도 FAIL,
assert 를 약화시켜도 (약화된 테스트는 통과해 버리므로 unexpected-pass 로)
FAIL.

**뒤쪽 방향이 실제로는 열려 있었다.** assert 를 약화시키면서 `expect_fail`
표식을 **같이** 지우면 그 테스트는 그냥 PASS 하고 CI 는 녹색이 된다
(적대 검증 실증: 2줄 편집으로 축퇴 은폐가 완전 복원됨). 래칫은 편집자가
표식을 남겨 두기로 선택했을 때에만 작동했다 — 즉 **선의에 의존하는
래칫**이었고, 그것은 래칫이 아니다.

이 lint 은 그 의존을 없앤다. 아래 표에 선언된 known-defect 테스트는
다음 3건을 **동시에** 만족해야 한다:

  1. 존재하고 `async def` 이며 `@cocotb.test(expect_fail=True)` 로
     표기돼 있다. (표식을 지우면 여기서 FAIL)
  2. 함수 본문의 `assert` 중 하나가 선언된 **golden 토큰 전건**을 포함한다.
     (assert 를 자격 비트만 보게 약화시키면 여기서 FAIL)
  3. docstring 에 spec 절 번호가 있다 (§28.4 항 8(e) 문면 요건).

역방향 래칫 (같은 표가 반대쪽도 막는다)
---------------------------------------
repo 의 **모든** `test_*.py` 를 훑어 `expect_fail` 표식을 전수 수집하고,
표에 선언되지 않은 것이 하나라도 있으면 FAIL 한다. 이것이 없으면 회귀한
테스트에 `expect_fail=True` 를 붙여 조용히 녹색으로 만드는 경로가 열린다
— 항 8(e) 가 금지하는 두 실패 양식 중 하나다.

Exit 0 = 선언된 known-defect 테스트가 3건 요건을 전부 만족하고, 미선언
`expect_fail` 이 0건. Exit 1 = 위반.
"""

import ast
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# ---------------------------------------------------------------------------
# known-defect 선언표.
#
#   spec_ref      — docstring 에 반드시 등장해야 하는 spec 절 번호
#   assert_tokens — 그 테스트의 `assert` 중 **하나**가 전부 포함해야 하는
#                   문자열. golden 비교식을 지목한다. assert 를 자격 비트만
#                   보게 약화시키면 어느 assert 도 이 토큰을 갖지 않으므로
#                   여기서 걸린다.
#   body_tokens   — 함수 본문 어디든 있어야 하는 문자열. 결과 신호를 실제로
#                   **읽는** 코드를 지목한다 (읽지도 않고 비교만 흉내내는
#                   형태를 막는다).
#   why           — 왜 수리하지 않고 loud 기록으로 남기는가 (사람용)
# ---------------------------------------------------------------------------
KNOWN_DEFECT_TESTS = {
    ("test_tensor_alu.py", "test_matmul_golden_known_broken"): {
        "spec_ref": "§31.7",
        "assert_tokens": ["ref_matmul(A, B)"],
        "body_tokens": ["resolved(dut.result_matrix)"],
        "why": "MATMUL(0x30) 무동작 — inner k-loop 의 비차단 대입 축퇴. "
               "수리는 D²=16 mul → D³=64 mul (premap $mul 31→76, DSP48 "
               "310→~760) 로 프로젝트가 이미 기각한 자원 폭증을 복원하므로 "
               "spec §31.7 이 normative 로 기각했다. 정본은 PE_Core "
               "(test_isa_decoder.py::test_matmul_2x2 값 검증 PASS).",
    },
    ("test_tensor_alu.py", "test_alu_valid_is_not_result_valid"): {
        "spec_ref": "§31.7",
        "assert_tokens": ["ref_add(A, B)"],
        "body_tokens": ["resolved(dut.result_matrix)"],
        "why": "O1b — `alu_valid` 는 result-valid 가 아니라 '리셋 중 아님' "
               "자유주행 플래그다. 이 비트를 result-valid 로 쓰는 테스트가 "
               "O1 을 은폐한 직접 기전이므로, 의미론을 실증하는 케이스를 "
               "loud 하게 남긴다 (§28.4 항 8(b)).",
    },
}


def _decorator_expect_fail(dec) -> bool:
    """`@cocotb.test(expect_fail=True)` 인가 (`@cocotb.test()` 는 False)."""
    if not isinstance(dec, ast.Call):
        return False
    for kw in dec.keywords:
        if kw.arg == "expect_fail":
            return isinstance(kw.value, ast.Constant) and kw.value.value is True
    return False


def _is_cocotb_test(dec) -> bool:
    func = dec.func if isinstance(dec, ast.Call) else dec
    if isinstance(func, ast.Attribute):
        return func.attr == "test"
    if isinstance(func, ast.Name):
        return func.id == "test"
    return False


def _collect(path: Path):
    """(func_name -> node) 와 expect_fail 표식이 붙은 함수 이름 집합."""
    src = path.read_text()
    tree = ast.parse(src)
    funcs, marked = {}, set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            funcs[node.name] = node
            for dec in node.decorator_list:
                if _is_cocotb_test(dec) and _decorator_expect_fail(dec):
                    marked.add(node.name)
    return src, funcs, marked


def main() -> int:
    fail = []
    checked = 0

    # ---- 정방향: 선언된 known-defect 테스트가 3건 요건을 만족하는가 ----
    by_file = {}
    for (fname, tname), spec in KNOWN_DEFECT_TESTS.items():
        by_file.setdefault(fname, {})[tname] = spec

    cache = {}
    for fname, entries in by_file.items():
        path = REPO_ROOT / fname
        if not path.exists():
            fail.append(f"{fname}: 선언된 known-defect 테스트 파일이 없다")
            continue
        src, funcs, marked = _collect(path)
        cache[fname] = (src, funcs, marked)

        for tname, spec in entries.items():
            checked += 1
            node = funcs.get(tname)
            if node is None:
                fail.append(
                    f"{fname}::{tname} — 선언된 known-defect 테스트가 "
                    "사라졌다. 결함이 수리됐다면 spec 절을 갱신하고 이 표에서 "
                    "빼라 (조용히 지우는 것은 §28.4 항 8(e) 위반).")
                continue
            if not isinstance(node, ast.AsyncFunctionDef):
                fail.append(f"{fname}::{tname} — cocotb 테스트는 "
                            "`async def` 여야 한다")
            if tname not in marked:
                fail.append(
                    f"{fname}::{tname} — `@cocotb.test(expect_fail=True)` "
                    "표식이 없다. **이것이 은폐 복원 경로다**: assert 를 "
                    "약화시키면서 표식을 같이 지우면 테스트가 PASS 해 "
                    "버리고 CI 가 녹색이 된다 (§31.14.3). 결함이 수리됐다면 "
                    f"spec {spec['spec_ref']} 를 갱신하고 이 표에서 빼라.")
            # docstring 에 spec 절 번호 (§28.4 항 8(e))
            doc = ast.get_docstring(node) or ""
            if spec["spec_ref"] not in doc:
                fail.append(
                    f"{fname}::{tname} — docstring 에 spec 절 번호 "
                    f"{spec['spec_ref']} 가 없다 (§28.4 항 8(e) 문면 요건).")
            # golden 토큰을 전부 포함하는 assert 가 하나라도 있는가
            asserts = [n for n in ast.walk(node) if isinstance(n, ast.Assert)]
            ok = False
            for a in asserts:
                seg = ast.get_source_segment(src, a) or ""
                if all(tok in seg for tok in spec["assert_tokens"]):
                    ok = True
                    break
            if not ok:
                fail.append(
                    f"{fname}::{tname} — golden 값 assert 가 없다 "
                    f"(요구 토큰 전건 포함: {spec['assert_tokens']}). "
                    "자격 비트만 보는 assert 로 되돌리는 것은 축퇴 동작을 "
                    "정답으로 못박는 행위이며 §28.4 항 8(a)/8(e) 가 "
                    "금지한다.")
            # 결과 신호를 실제로 읽는가
            body_seg = ast.get_source_segment(src, node) or ""
            missing = [t for t in spec["body_tokens"] if t not in body_seg]
            if missing:
                fail.append(
                    f"{fname}::{tname} — 결과 신호를 읽는 코드가 없다 "
                    f"(누락 토큰: {missing}). 값을 읽지 않는 테스트는 "
                    "무엇을 assert 하든 §28.4 항 8(a) 위반이다.")

    # ---- 역방향: 미선언 expect_fail 이 하나라도 있으면 FAIL ----
    declared = set(KNOWN_DEFECT_TESTS)
    found = set()
    for path in sorted(REPO_ROOT.glob("test_*.py")):
        fname = path.name
        if fname in cache:
            _, _, marked = cache[fname]
        else:
            try:
                _, _, marked = _collect(path)
            except SyntaxError as exc:
                fail.append(f"{fname}: 파싱 실패 — {exc}")
                continue
        for tname in marked:
            found.add((fname, tname))

    undeclared = sorted(found - declared)
    if undeclared:
        fail.append(
            "미선언 `expect_fail` 테스트 "
            f"{['::'.join(x) for x in undeclared]} — 회귀한 테스트에 "
            "`expect_fail=True` 를 붙여 조용히 녹색으로 만드는 경로다. "
            "known-defect 로 남길 것이면 이 표에 spec 절 번호와 golden "
            "토큰을 함께 선언하라 (§28.4 항 8(e)).")

    print("lint_known_defect_tests — §28.4 항 8(e) expect_fail 양방향 래칫")
    for (fname, tname), spec in sorted(KNOWN_DEFECT_TESTS.items()):
        print(f"  [known-defect] {fname}::{tname}  (spec {spec['spec_ref']})")
        print(f"      golden assert: {spec['assert_tokens']} / body: {spec['body_tokens']}")
        print(f"      사유: {spec['why']}")
    print(f"  스캔한 test_*.py: {len(list(REPO_ROOT.glob('test_*.py')))}개 / "
          f"발견된 expect_fail 표식 {len(found)}건 / 선언 {len(declared)}건")
    print()

    if fail:
        for f in fail:
            print(f"VIOLATION: {f}")
        return 1

    print(f"lint_known_defect_tests OK — known-defect {checked}건 전부 "
          "(expect_fail 표식 + golden 값 assert + spec 절 번호) 3건 요건 "
          "충족, 미선언 expect_fail 0건")
    return 0


if __name__ == "__main__":
    sys.exit(main())
