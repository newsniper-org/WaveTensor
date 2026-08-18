#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""P0-2 CI lint — FRAG_SLOTS self-skip 의 **조용한 재도입 봉쇄**.

무엇이 새어 나갔는가
--------------------
`test_cluster.py` 의 FRAG_SLOTS>1 전용 테스트 6건은 기본 빌드
(FRAG_SLOTS=1)에서 `if _slots(dut) == 1: return` 로 **조용히** 빠져나가며
값 검사를 0건 수행하고도 PASS 로 집계됐다. 두 빌드를 모두 돌리도록
강제하는 장치도 없었다. 결과적으로 다중 슬롯 경로(persistence / LRU /
cold-fill / FRAG_INVAL)는 "녹색 CI" 아래에서 **미검증**일 수 있었다.

이 lint 이 강제하는 것
----------------------
  1. `test_cluster.py` 안에서 `_slots()` 결과로 곧장 `return` 하는
     **조용한** self-skip 이 0건이어야 한다. 유일하게 허용되는 형태는
     `if _skip_unless_multislot(dut): return` 이며, 그 헬퍼는 WARNING 을
     남긴다. (bare `return` 을 다시 넣으면 여기서 FAIL)
  2. `_skip_unless_multislot` 을 쓰는 테스트 집합이 아래 선언표와
     **정확히** 일치해야 한다. 테스트를 지우거나 새로 조용히 추가하면
     불일치로 FAIL 한다.
  3. 선언표 크기 == `run_cluster_dual.EXPECTED_SKIPS`. 한쪽만 고치면 FAIL.
  4. `_MULTISLOT_SKIP_MARK` (테스트) == `SKIP_MARK` (dual 러너) ==
     이 파일의 상수. 표식이 어긋나면 러너가 0건을 세고 조용히 통과할 수
     있으므로 세 곳을 묶는다.
  5. Makefile 에 `test-cluster-both` 타깃이 있고 `run_cluster_dual.py` 를
     부른다. 진입점이 사라지면 FAIL.

Exit 0 = 전부 만족. Exit 1 = 위반.
"""

import ast
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
TEST_FILE = REPO_ROOT / "test_cluster.py"
RUNNER = REPO_ROOT / "scripts" / "run_cluster_dual.py"
MAKEFILE = REPO_ROOT / "Makefile"

SKIP_MARK = "FRAG_SLOTS-SELF-SKIP"
GATE_NAME = "_skip_unless_multislot"
SLOTS_NAME = "_slots"

# FRAG_SLOTS>1 전용으로 self-skip 하는 테스트 — 선언표.
MULTISLOT_ONLY_TESTS = {
    "test_frag_slots_persistent_no_clear",
    "test_frag_slots_coldfill_monotonic_age_and_lru_eviction",
    "test_frag_slots_tag_reuse_collision_safe_realloc",
    "test_frag_inval_hit_frees_slot_immediately",
    "test_frag_inval_freed_slot_reclaimed_by_free_priority_not_evict",
    "test_frag_inval_midassembly_slot_reports_miss_not_cancel",
    # v1.9.2 §22.14b-4b — deferred CAM commit 의 기아 봉쇄. FRAG_SLOTS=1 에는
    # `frag_ready` 가 구조적으로 서지 않아 `cache_hit` 자체가 존재하지 않고,
    # 따라서 기아 경로도 존재하지 않는다 (다중 슬롯 빌드 전용).
    "test_skid_deferred_commit_survives_concurrent_cache_load",
}


def _calls(node, name):
    """`node` 하위에 `name(...)` 호출이 있는가."""
    for sub in ast.walk(node):
        if (isinstance(sub, ast.Call) and isinstance(sub.func, ast.Name)
                and sub.func.id == name):
            return True
    return False


def _is_cocotb_test(dec):
    f = dec.func if isinstance(dec, ast.Call) else dec
    return isinstance(f, ast.Attribute) and f.attr == "test"


def main():
    errors = []

    src = TEST_FILE.read_text(encoding="utf-8")
    tree = ast.parse(src, filename=str(TEST_FILE))

    gated = set()
    for node in ast.walk(tree):
        if not isinstance(node, (ast.AsyncFunctionDef, ast.FunctionDef)):
            continue
        if not any(_is_cocotb_test(d) for d in node.decorator_list):
            continue

        # ---- 요건 1: 조용한 self-skip 금지 ----
        for sub in ast.walk(node):
            if not isinstance(sub, ast.If):
                continue
            body = [s for s in sub.body if not isinstance(s, ast.Pass)]
            if len(body) != 1 or not isinstance(body[0], ast.Return):
                continue
            if body[0].value is not None:
                continue
            # 조건이 `_slots(...)` 를 직접 보거나, `_slots()` 로 대입된
            # 지역 변수를 보는가?
            if _calls(sub.test, SLOTS_NAME):
                errors.append(
                    f"{TEST_FILE.name}::{node.name} — `{SLOTS_NAME}()` 결과로 "
                    f"곧장 bare `return` 하는 조용한 self-skip. "
                    f"`if {GATE_NAME}(dut): return` 을 써라 (WARNING 을 남긴다).")
                continue
            names = {n.id for n in ast.walk(sub.test) if isinstance(n, ast.Name)}
            for stmt in ast.walk(node):
                if (isinstance(stmt, ast.Assign)
                        and _calls(stmt.value, SLOTS_NAME)
                        and any(isinstance(t, ast.Name) and t.id in names
                                for t in stmt.targets)):
                    errors.append(
                        f"{TEST_FILE.name}::{node.name} — `{SLOTS_NAME}()` 로 "
                        f"대입한 변수로 bare `return` 하는 조용한 self-skip. "
                        f"`if {GATE_NAME}(dut): return` 을 써라.")
                    break

        if _calls(node, GATE_NAME):
            gated.add(node.name)

    # ---- 요건 2: 선언표와 정확히 일치 ----
    missing = MULTISLOT_ONLY_TESTS - gated
    extra = gated - MULTISLOT_ONLY_TESTS
    for name in sorted(missing):
        errors.append(
            f"선언표의 `{name}` 이 `{GATE_NAME}` 을 쓰지 않는다 "
            f"(사라졌거나 게이트가 제거됐다).")
    for name in sorted(extra):
        errors.append(
            f"`{name}` 이 `{GATE_NAME}` 을 쓰는데 MULTISLOT_ONLY_TESTS 에 "
            f"선언돼 있지 않다 — 새 self-skip 은 선언 없이 들어올 수 없다.")

    # ---- 요건 3/4: 러너 상수와의 정합 ----
    runner_src = RUNNER.read_text(encoding="utf-8") if RUNNER.exists() else ""
    if not runner_src:
        errors.append(f"{RUNNER} 가 없다 — 이중 빌드 진입점이 사라졌다.")
    else:
        m = re.search(r"^EXPECTED_SKIPS\s*=\s*(\d+)", runner_src, re.M)
        if not m:
            errors.append(f"{RUNNER.name}: EXPECTED_SKIPS 상수를 찾지 못했다.")
        elif int(m.group(1)) != len(MULTISLOT_ONLY_TESTS):
            errors.append(
                f"{RUNNER.name}: EXPECTED_SKIPS={m.group(1)} 인데 선언표는 "
                f"{len(MULTISLOT_ONLY_TESTS)}건이다 — 두 곳을 함께 갱신하라.")
        m = re.search(r'^SKIP_MARK\s*=\s*"([^"]+)"', runner_src, re.M)
        if not m:
            errors.append(f"{RUNNER.name}: SKIP_MARK 상수를 찾지 못했다.")
        elif m.group(1) != SKIP_MARK:
            errors.append(
                f"{RUNNER.name}: SKIP_MARK={m.group(1)!r} != {SKIP_MARK!r}")

    m = re.search(r'^_MULTISLOT_SKIP_MARK\s*=\s*"([^"]+)"', src, re.M)
    if not m:
        errors.append(f"{TEST_FILE.name}: _MULTISLOT_SKIP_MARK 상수를 찾지 못했다.")
    elif m.group(1) != SKIP_MARK:
        errors.append(
            f"{TEST_FILE.name}: _MULTISLOT_SKIP_MARK={m.group(1)!r} != "
            f"{SKIP_MARK!r} — 러너가 표식을 0건 세고 조용히 통과하게 된다.")

    # ---- 요건 5: Makefile 진입점 ----
    mk = MAKEFILE.read_text(encoding="utf-8")
    if not re.search(r"^test-cluster-both:", mk, re.M):
        errors.append("Makefile 에 `test-cluster-both` 타깃이 없다.")
    elif "run_cluster_dual.py" not in mk:
        errors.append("Makefile 의 `test-cluster-both` 가 run_cluster_dual.py 를 "
                      "부르지 않는다.")

    if errors:
        print("lint_frag_slots_dual_run: FAIL", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1

    print(f"lint_frag_slots_dual_run: OK — self-skip {len(gated)}건 전부 loud "
          f"게이트 경유, 러너/Makefile 진입점 정합")
    return 0


if __name__ == "__main__":
    sys.exit(main())
