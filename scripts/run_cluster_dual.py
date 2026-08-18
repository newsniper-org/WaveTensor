#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""P0-2 — Cluster 이중 빌드(FRAG_SLOTS=1 / FRAG_SLOTS>1) **단일 진입점**.

무엇이 새어 나갔는가 (이 파일이 생긴 이유)
------------------------------------------
`test_cluster.py` 의 6건은 FRAG_SLOTS>1 에서만 의미가 있고, 기본 빌드
(FRAG_SLOTS=1)에서는 값 검사를 **0건** 수행하고도 PASS 로 집계된다.
그런데 두 빌드를 모두 돌리도록 강제하는 장치가 CI·hook·lint 어디에도
없었다. 즉 `make MOD=Cluster` 만 돌린 녹색은 "다중 슬롯 경로가 검증됐다"
를 **전혀** 의미하지 않는데, 로그만 봐서는 구분이 되지 않았다.

이 스크립트가 하는 일
---------------------
두 빌드를 순서대로 돌리고, 각 빌드에서 다음을 **대조**한다:

  * FRAG_SLOTS=1  — self-skip 표식이 정확히 EXPECTED_SKIPS 건. 0건이면
    (게이트가 조용해졌거나 테스트가 사라졌다는 뜻) FAIL.
  * FRAG_SLOTS=4  — self-skip 표식이 정확히 0건. 하나라도 있으면 다중
    슬롯 빌드인데도 건너뛴 것이므로 FAIL.
  * 두 빌드 모두 FAIL=0 이고 테스트 수가 서로 같아야 한다.

따라서 "돌리지 않으면 티가 나는" 형태다 — 한쪽만 돌리면 이 스크립트를
통과할 수 없고, self-skip 을 조용하게 되돌리면 계수가 어긋나 FAIL 한다.

사용:  make test-cluster-both     (또는 python3 scripts/run_cluster_dual.py)
"""

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# test_cluster.py 의 `_MULTISLOT_SKIP_MARK` 와 반드시 일치해야 한다.
# (scripts/lint_frag_slots_dual_run.py 가 불일치를 기계적으로 잡는다.)
SKIP_MARK = "FRAG_SLOTS-SELF-SKIP"

# FRAG_SLOTS>1 전용 테스트 건수 = FRAG_SLOTS=1 빌드에서 나와야 할 표식 수.
# 6 → 7 (v1.9.2 §22.14b-4b): `test_skid_deferred_commit_survives_concurrent_
# cache_load` 가 추가됐다. FRAG_SLOTS=1 에는 `frag_ready` 가 서지 않아
# `cache_hit` 자체가 없고, 따라서 그 테스트가 겨냥하는 기아 경로도 없다.
EXPECTED_SKIPS = 7

# 다중 슬롯 빌드에서 쓸 슬롯 수.
MULTI_SLOTS = 4

_SUMMARY = re.compile(r"TESTS=(\d+)\s+PASS=(\d+)\s+FAIL=(\d+)\s+SKIP=(\d+)")


def _run(frag_slots):
    """한 빌드를 돌리고 (rc, log, (tests, passes, fails, skips)) 를 돌려준다."""
    env = dict(os.environ)
    env["PATH"] = os.path.expanduser("~/.local/bin") + os.pathsep + env.get("PATH", "")
    # tracked results.xml 을 건드리지 않는다.
    tmp_xml = tempfile.NamedTemporaryFile(suffix=".xml", delete=False)
    tmp_xml.close()
    env["COCOTB_RESULTS_FILE"] = tmp_xml.name

    sim_build = REPO_ROOT / "sim_build"
    subprocess.run(["rm", "-rf", str(sim_build)], check=True)

    cmd = ["make", "-C", str(REPO_ROOT), "MOD=Cluster"]
    if frag_slots != 1:
        cmd.append(f"FRAG_SLOTS={frag_slots}")
    label = f"FRAG_SLOTS={frag_slots}"
    print(f"=== {label}: {' '.join(cmd)}", flush=True)
    proc = subprocess.run(cmd, env=env, capture_output=True, text=True)
    log = proc.stdout + proc.stderr
    os.unlink(tmp_xml.name)

    m = None
    for m in _SUMMARY.finditer(log):
        pass
    counts = tuple(int(g) for g in m.groups()) if m else None
    return proc.returncode, log, counts


def main():
    failures = []
    results = {}

    for slots in (1, MULTI_SLOTS):
        rc, log, counts = _run(slots)
        label = f"FRAG_SLOTS={slots}"
        n_skip = log.count(SKIP_MARK)
        results[slots] = (rc, counts, n_skip)

        if counts is None:
            failures.append(f"{label}: cocotb 요약줄(TESTS=…)을 찾지 못했다 "
                            f"(rc={rc}). 빌드가 실패했을 가능성이 높다.")
            print(log[-4000:], file=sys.stderr)
            continue

        tests, passes, fails, skips = counts
        print(f"    {label}: TESTS={tests} PASS={passes} FAIL={fails} "
              f"SKIP={skips} self-skip={n_skip}", flush=True)

        if rc != 0 or fails != 0:
            failures.append(f"{label}: FAIL={fails} (rc={rc})")

        if slots == 1:
            if n_skip != EXPECTED_SKIPS:
                failures.append(
                    f"{label}: self-skip 표식이 {n_skip}건 — {EXPECTED_SKIPS}건이어야 "
                    f"한다. 0건이면 게이트가 조용해졌거나(loud 화 회귀) 해당 "
                    f"테스트가 사라진 것이고, 초과면 새 self-skip 이 "
                    f"EXPECTED_SKIPS 갱신 없이 들어온 것이다.")
        else:
            if n_skip != 0:
                failures.append(
                    f"{label}: self-skip 표식이 {n_skip}건 — 다중 슬롯 빌드에서는 "
                    f"0건이어야 한다. 이 빌드에서조차 건너뛰었다면 그 테스트는 "
                    f"어느 빌드에서도 검증되지 않는다.")

    if all(results.get(s, (None, None, None))[1] for s in (1, MULTI_SLOTS)):
        t1 = results[1][1][0]
        t2 = results[MULTI_SLOTS][1][0]
        if t1 != t2:
            failures.append(
                f"두 빌드의 테스트 수가 다르다: FRAG_SLOTS=1 → {t1}, "
                f"FRAG_SLOTS={MULTI_SLOTS} → {t2}")

    if failures:
        print("\nrun_cluster_dual: FAIL", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print("\nrun_cluster_dual: OK — 두 FRAG_SLOTS 빌드 모두 통과, "
          f"self-skip 계수 정합 ({EXPECTED_SKIPS} / 0)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
