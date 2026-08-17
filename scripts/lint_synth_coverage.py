#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""lint_synth_coverage.py — spec §28 CI lint: "시뮬레이터 통과 ≠ 합성 가능"
을 상시 검사로 전환한다.

왜 이 lint 이 존재하는가
------------------------
사용자가 HIU 면적을 물었을 때 답할 수 없었다. `HIU.v` 와 `Top_Core.v` 는
repo 의 어떤 합성 스크립트에도 등장하지 않았고 (`grep -rn 'HIU.v'
synth/` → 0건), 첫 합성 시도는 Vivado 가 거부했다 (`ERROR [Synth 8-685]`
— 결함 D1, Verilog-2001 위반). 두 모듈은 cocotb 에서 **계속 PASS 하면서
한 번도 합성된 적이 없었다.** 시뮬레이터 PASS 가 "합성 가능" 의 대역으로
쓰이고 있었던 것이다.

그래서 이 lint 의 검사 대상은 RTL 이 아니라 **repo 자신의 구조**다:
cocotb 로 검증되는 모든 모듈이 합성 경로 상에서 어떤 지위에 있는지가
선언되어 있는가. 새 모듈을 cocotb Makefile 에 추가하면서 합성 경로를
선언하지 않으면 이 lint 가 깨진다 — 그것이 이 파일의 유일한 목적이다.

검사 규칙 (전부 기계적 — 파일시스템 상태에 의존하지 않으므로 clean
checkout 에서도 동일한 판정이 나온다)
--------------------------------------------------------------------
  1. **미분류 금지**: `Makefile` 의 cocotb `MOD` 목록에 있는 모듈이 아래
     COVERAGE 표에 없으면 FAIL. (= 합성 지위를 선언하지 않은 신규 모듈)
  2. **stale 금지**: COVERAGE 표에 있으나 Makefile 에 없는 모듈이 있으면
     FAIL. (= 사라진 모듈의 유령 선언)
  3. **래칫**: `uncovered` / `measured-pending` 지위의 개수가 아래 선언된
     상한을 넘으면 FAIL. 지위 강등(gate → uncovered)은 상한을 올리는
     편집을 강제하므로 조용히 일어날 수 없다.
  4. **소리내기**: `gate` 가 아닌 모든 항목을 매 실행 stdout 에 열거한다.
     통과해도 침묵하지 않는다 (loud-fault-never-silent).

`gate` 지위만이 "위반 시 비영 종료하는 검사가 존재한다" 를 뜻한다.
`harness` 는 재현 가능한 합성 경로는 있으나 merge-blocker binding 이
없다는 뜻이고, `measured-pending` / `uncovered` 는 각각 그 이유를 문자열로
들고 있어야 한다.

Exit 0 = 전 모듈의 합성 지위가 선언되어 있고 래칫 위반 없음.
Exit 1 = 위반 (미분류 / stale / 래칫 초과).
"""

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MAKEFILE = REPO_ROOT / "Makefile"

# 래칫 상한 — 낮추는 편집만 정당하다. 올리려면 그 자체가 리뷰 대상이다.
UNCOVERED_MAX = 2
MEASURED_PENDING_MAX = 3

# ---------------------------------------------------------------------------
# 합성 지위 선언표 (spec §28.4)
#
#   status "gate"             — merge-blocker binding 이 있는 gate 에 편입됨.
#                               위반 시 `make fp-op-report` 가 비영 종료한다.
#   status "harness"          — repo 안에 재현 가능한 합성 경로가 있으나
#                               binding gate 는 없다.
#   status "measured-pending" — 실측은 있으나 편입 보류. 보류 사유가
#                               `why` 에 있어야 한다.
#   status "uncovered"        — 합성 경로 없음. 사유가 `why` 에 있어야 한다.
# ---------------------------------------------------------------------------
COVERAGE = {
    "Top_Core": {
        "status": "gate",
        "how": "make synth-sys-gate SYS_GATE=sys_top_core "
               "PART=xcu55c-fsvh2892-2L-e   (GATE S1-US, spec §28)",
    },
    "HIU": {
        "status": "gate",
        "how": "GATE S1-US 안에서 `u_core/u_hiu` 계층으로 측정됨 "
               "(hierarchical util 행 + hiu_trng_ro.xdc 의 g_ro 인정). "
               "이 모듈이 GATE S1 신설의 발단이다 — 결함 D1 이 계통 전체를 "
               "막고 있었고, D4 (partitioned TLB undriven) 는 아직 열려 있다. "
               "구속 범위 정밀화 (적대 감사 2026-08-18): HIU 를 구속하는 축은 "
               "(i) 합성 가능성 자체 — HIU 가 elaborate/synth 에 실패하면 "
               "Top_Core gate 가 함께 죽는다 (D1 이 실증), (ii) `Synth 8-295` "
               "화이트리스트 정확히 8 = TRNG ring oscillator 8개 (9번째나 "
               "소실 모두 FAIL), (iii) DSP 0 · BRAM 0 기여분이 Top_Core 의 "
               "exact-value 축 (39 / 2) 에 합산돼 고정된다. **HIU 자체 면적을 "
               "직접 구속하는 축은 없다** — 계층 행 2,570 LUT 는 기록이고, "
               "면적 상한은 Top_Core 총계 (ceiling 24,799) 로만 걸린다. HIU "
               "단독 ceiling 은 선공표된 바 없으므로 여기서 만들지 않는다 "
               "(V9-4: 기준은 측정 전 공표).",
    },
    "Pod": {
        "status": "harness",
        "how": "make synth-pod / make impl-pod (Vivado) + "
               "make impl-pod-ecp5 (yosys+nextpnr) — 실측 아카이브 "
               "synth/reports/pod_2x2_2x2_impl_*.rpt",
    },
    "Cluster": {
        "status": "harness",
        "how": "synth/lattice/scripts/synth_cluster.ys (ECP5) + Pod 경유 "
               "Vivado — 실측 아카이브 synth/lattice/reports/cluster_v19b_*",
    },
    "Tensor_ALU": {
        "status": "measured-pending",
        "how": "정찰 실측 (xcu55c OOC gate_top, post-route): LUT 4,486 / "
               "FF 7,178 / DSP48 310 / Fmax 155.79 MHz — spec §28.8",
        "why": "고아 지위(폐기 vs 통합) 미확정. 편입은 gate 를 통해 설계를 "
               "merge-blocker 로 약속하는 행위인데, MATMUL(0x30) 이 실측상 "
               "무동작(무한 램프 — spec §28.8 결함 O1)이므로 지금 면적을 "
               "gate 로 고정하면 죽은 설계를 규범화하게 된다. 지위 판정이 "
               "선행해야 한다.",
    },
    "SIMD_ALU": {
        "status": "measured-pending",
        "how": "정찰 실측 (xcu55c OOC gate_top, 45 ns closure): LUT 10,001 / "
               "CARRY8 1,608 / Fmax 22.47 MHz — spec §28.8",
        "why": "고아 지위 미확정. 22.47 MHz 는 프로젝트 100 MHz 문맥의 "
               "4.45x 미달이고 병목은 조합 divider 체인(CARRY8 159단)이다 — "
               "수리는 PE_Core 의 bit-serial 상태기계 채택 = 인터페이스·"
               "latency 변경이라 '의미 보존' 이 아니다. 지위 판정 선행.",
    },
    "ALU_Extended": {
        "status": "measured-pending",
        "how": "정찰 실측 (xcu55c OOC gate_top, post-route): LUT 606 / "
               "FF 274 / DSP48 20 / Fmax 167.31 MHz — spec §28.8",
        "why": "고아 지위 미확정. 3개 중 유일하게 Synth 경고 0건이고 "
               "2026-07-14 까지 능동 유지보수됐다 (벤더 attribute 이행) — "
               "즉 폐기 후보가 아니라 통합 후보로 보이지만, 통합 지점 "
               "(claude.md §6 'PE.v = ISA_Decoder + ALU wrapper') 자체가 "
               "Cluster→PE_Core 직결로 대체된 상태다. 지위 판정 선행.",
    },
    "PE": {
        "status": "uncovered",
        "how": None,
        "why": "합성 경로 없음. synth_pod.ys / synth_cluster.ys 가 PE.v 를 "
               "read_verilog 하지만 Pod/Cluster 가 인스턴스화하지 않으므로 "
               "hierarchy -top 에서 프루닝된다 (pod_2x2_2x2_impl_util.rpt "
               "계층에 bare PE 행 0건). 구조적 사유: Cluster.v 가 EHDecode "
               "를 cluster 레벨로 끌어올려 공유하고 PE_Core 를 직접 "
               "인스턴스화하므로 per-PE 래퍼 계층이 supersede 됐다.",
    },
    "ISA_Decoder": {
        "status": "uncovered",
        "how": None,
        "why": "합성 경로 없음 (PE 와 같은 구조적 사유 — Cluster→PE_Core "
               "직결이 per-PE decode 래퍼를 대체했다). 단 GATE S1-US 의 "
               "Top_Core 안에서는 `u_core/u_decoder` 로 실제 합성되므로 "
               "'전혀 합성되지 않는 RTL' 은 아니다 — standalone top 으로서 "
               "의 합성 경로가 없다는 뜻이며, 이 구분은 D1 류의 top-level "
               "포트 결함이 standalone 에서만 드러나는 경우를 놓칠 수 있다.",
    },
}

VALID_STATUS = ("gate", "harness", "measured-pending", "uncovered")


def parse_makefile_mods():
    """cocotb MOD 목록을 Makefile 에서 기계적으로 추출한다.

    두 곳을 각각 파싱해 교차검증한다:
      (a) `ifeq ($(MOD),X)` / `else ifeq ($(MOD),X)` 분기
      (b) `$(error Unknown MOD '$(MOD)'. Valid: ...)` 의 목록
    둘이 어긋나면 Makefile 자체가 자기모순이므로 FAIL 이다 — 이 lint 의
    입력이 신뢰할 수 없다는 뜻이고, 조용히 한쪽을 고르는 것은 답이 아니다.
    """
    text = MAKEFILE.read_text()
    branch = re.findall(r"^\s*(?:else\s+)?ifeq\s*\(\$\(MOD\),([A-Za-z_0-9]+)\)",
                        text, re.M)
    m = re.search(r"Unknown MOD .*?Valid:\s*([^)]+)\)", text)
    if not m:
        sys.exit("lint_synth_coverage: Makefile 의 `$(error Unknown MOD ... "
                 "Valid: ...)` 행을 찾지 못했다 — 파서 앵커가 사라졌다.")
    declared = [w.strip() for w in m.group(1).split(",") if w.strip()]
    if sorted(branch) != sorted(declared):
        sys.exit("lint_synth_coverage: Makefile 자기모순 — MOD 분기 "
                 f"{sorted(branch)} != Valid 목록 {sorted(declared)}")
    return branch


def main():
    mods = parse_makefile_mods()

    for name, e in COVERAGE.items():
        if e["status"] not in VALID_STATUS:
            sys.exit(f"lint_synth_coverage: {name}: 알 수 없는 status "
                     f"{e['status']!r} (허용: {VALID_STATUS})")
        if e["status"] in ("measured-pending", "uncovered") and not e.get("why"):
            sys.exit(f"lint_synth_coverage: {name}: status "
                     f"{e['status']!r} 는 `why` 사유 문자열이 필수다.")
        if e["status"] in ("gate", "harness", "measured-pending") \
                and not e.get("how"):
            sys.exit(f"lint_synth_coverage: {name}: status "
                     f"{e['status']!r} 는 `how` 재현 경로가 필수다.")

    unclassified = [m for m in mods if m not in COVERAGE]
    stale = [k for k in COVERAGE if k not in mods]

    by_status = {s: [k for k, v in COVERAGE.items() if v["status"] == s]
                 for s in VALID_STATUS}

    print("lint_synth_coverage — 합성 지위 (spec §28.4; cocotb MOD "
          f"{len(mods)}개)")
    for s in VALID_STATUS:
        names = sorted(by_status[s])
        print(f"  {s:<17s} {len(names)}: {', '.join(names) or '-'}")
    print()
    for s in ("harness", "measured-pending", "uncovered"):
        for name in sorted(by_status[s]):
            e = COVERAGE[name]
            print(f"  [{s}] {name}")
            if e.get("how"):
                print(f"      경로: {e['how']}")
            if e.get("why"):
                print(f"      사유: {e['why']}")
    print()

    fail = []
    if unclassified:
        fail.append(
            f"미분류 모듈 {unclassified} — cocotb MOD 에는 있으나 COVERAGE "
            "표에 합성 지위 선언이 없다. 이것이 바로 HIU/Top_Core 가 "
            "repo 존재 기간 3.5개월 내내 미합성으로 남은 경로다 "
            "(spec §28). gate/harness/"
            "measured-pending/uncovered 중 하나로 분류하고, 후자 둘은 "
            "사유를 적어라.")
    if stale:
        fail.append(f"stale 선언 {stale} — COVERAGE 표에 있으나 Makefile "
                    "cocotb MOD 목록에 없다.")
    n_unc = len(by_status["uncovered"])
    n_pend = len(by_status["measured-pending"])
    if n_unc > UNCOVERED_MAX:
        fail.append(f"래칫 위반: uncovered {n_unc} > 상한 {UNCOVERED_MAX}")
    if n_pend > MEASURED_PENDING_MAX:
        fail.append(f"래칫 위반: measured-pending {n_pend} > 상한 "
                    f"{MEASURED_PENDING_MAX}")

    if fail:
        for f in fail:
            print(f"VIOLATION: {f}")
        sys.exit(1)

    print(f"lint_synth_coverage OK — 미분류 0 / stale 0 / uncovered {n_unc} "
          f"<= {UNCOVERED_MAX} / measured-pending {n_pend} <= "
          f"{MEASURED_PENDING_MAX}")


if __name__ == "__main__":
    main()
