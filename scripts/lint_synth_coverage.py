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
  3. **래칫**: `uncovered` / `measured-pending` / `superseded` /
     `reference` 지위의 개수가 아래 선언된
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

import ast
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MAKEFILE = REPO_ROOT / "Makefile"

# 래칫 상한 — 낮추는 편집만 정당하다. 올리려면 그 자체가 리뷰 대상이다.
UNCOVERED_MAX = 2
# v1.9.1 §31.6 — 3건 전부 `superseded` 2 + `reference` 1 로 이동했으므로
# 이 상한은 **완화가 아니라 0 으로 인하**된다. 새 `measured-pending` 은
# 이제 상한 자체가 막는다.
MEASURED_PENDING_MAX = 0
# `superseded` 래칫 — §31.6 이 규정한 ≤ 3.
SUPERSEDED_MAX = 3
# `reference` 래칫 — 현재 ALU_Extended 1건. 늘리려면 그 편집이 리뷰 대상이다.
REFERENCE_MAX = 1

# ---------------------------------------------------------------------------
# 합성 지위 선언표 (spec §28.4)
#
#   status "gate"             — merge-blocker binding 이 있는 gate 에 편입됨.
#                               위반 시 `make fp-op-report` 가 비영 종료한다.
#   status "harness"          — repo 안에 재현 가능한 합성 경로가 있으나
#                               binding gate 는 없다.
#   status "measured-pending" — 실측은 있으나 편입 보류. 보류 사유가
#                               `why` 에 있어야 한다.
#   status "superseded"       — (v1.9.1 §31.6 신설, §28.4 5번째 지위) 기능이
#                               다른 모듈로 **이관 완료**됐음이 확정되어 합성
#                               대상이 아닌 RTL. 등재 요건 4건 — `canonical`
#                               (정본 모듈), `canonical_test` (그 정본의 값
#                               검증 테스트 산문 설명), `canonical_test_refs`
#                               (그 테스트의 **기계 판독 가능한** 참조 목록),
#                               `deadline` (폐기 판정 기한 조건).
#                               하나라도 비면 비영 종료한다.
#
#                               v1.9.1 §31.14 강화: `canonical_test` 는 원래
#                               **문자열의 존재만** 검사됐다 — 즉 정본 테스트가
#                               삭제되거나 이름이 바뀌어도 lint 는 조용했다.
#                               "정본이 있고 그것이 검증됐다" 가 근거인데
#                               그 근거를 검증하지 않는 lint 는 근거의 시늉일
#                               뿐이다. 이제 `canonical_test_refs` 의 각 항목이
#                               (a) 실제 파일의 실제 async 테스트 함수로
#                               해소되고, (b) 그 함수가 DUT 신호를 읽는 값
#                               assert 를 최소 1개 가진다는 것까지 AST 로
#                               확인한다.
#   status "reference"        — (v1.9.1 §31.6 신설) 통합 지점이 소멸했으나
#                               값 검증 테스트가 건전하고 능동 유지보수된
#                               참조 구현. **비합성 대상**임을 명시한다.
#                               `why` + `how` 필수.
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
        "status": "superseded",
        "how": "정찰 실측 (xcu55c OOC gate_top, post-route): LUT 4,486 / "
               "FF 7,178 / DSP48 310 / Fmax 155.79 MHz — spec §28.8. "
               "합성 편입 경로는 신설하지 않는다 (GATE S1 전 축 0 기여).",
        "canonical": "PE_Core (0x30 matmul_func / 0x31 인라인 lane add / "
                     "0x32 EINSUM 2단 SUBSCRIPT dispatch)",
        "canonical_test": "test_isa_decoder.py::test_matmul_2x2 "
                          "(A=[[1,2],[3,4]] B=[[5,6],[7,8]] -> [[19,22],"
                          "[43,50]] 값 assert PASS) + test_tensor_add",
        "canonical_test_refs": [
            ("test_isa_decoder.py", "test_matmul_2x2"),
            ("test_isa_decoder.py", "test_tensor_add"),
        ],
        "deadline": "파일 폐기 실행은 사용자 결정 1건 (spec §31.6 — §12a "
                    "규칙 6 절차의 (a) 소비자 audit 과 (b) 정본 지정은 이미 "
                    "충족돼 있다). 그때까지 test_tensor_alu.py 가 §28.4 "
                    "항 8 형식으로 결함을 loud 하게 유지한다.",
        "why": "superseded duplicate — 소비자 0 (.v 인스턴스 0 / synth "
               "read_verilog 목록 0 / 외부 sibling 리포 4곳 grep 0). "
               "0x32 는 **현행 ISA 에 없는 의미론**(EINSUM 이 아니라 "
               "retired TENSOR_MUL)이고 0x30 은 프로젝트가 기각한 4x4 "
               "unrolled pre-mitigation shape 다. MATMUL(0x30) 무동작은 "
               "수리 기각 상태로 남는다 (spec §31.7 — 정답 구현은 premap "
               "$mul 31->76 / DSP48 310->~760 으로 이미 기각된 자원 폭증을 "
               "복원한다). O2 (Synth 8-7137 x49) 수리는 소멸 (spec §31.8).",
    },
    "SIMD_ALU": {
        "status": "superseded",
        "how": "정찰 실측 (xcu55c OOC gate_top, 45 ns closure): LUT 10,001 / "
               "CARRY8 1,608 / Fmax 22.47 MHz — spec §28.8.",
        "canonical": "PE_Core (0x10/0x11/0x12/0x13/0x1C/0x1F 전부 구현; "
                     "0x13/0x1C/0x1D 는 bit-serial FSM)",
        "canonical_test": "test_isa_decoder.py 스칼라 ALU/DIV/MOD/DIVMOD "
                          "값 검증군 (192 케이스 전건 PASS)",
        "canonical_test_refs": [
            ("test_isa_decoder.py", "test_add_with_imm"),
            ("test_isa_decoder.py", "test_add_with_opref_uses_payload_b"),
            ("test_isa_decoder.py", "test_divrem"),
            ("test_isa_decoder.py", "test_bitwise_and"),
            ("test_isa_decoder.py", "test_bitwise_or"),
            ("test_isa_decoder.py", "test_bitwise_xor"),
        ],
        "deadline": "`board_hw_plan.md:173` 의 contingency 등재("
                    "ECP5 84K LUT 부족 시 대체) 무효화가 선행한다. "
                    "무효화 근거는 확보돼 있다 — §28.8 O3 실측 22.47 MHz "
                    "는 100 MHz 문맥의 4.45x 미달이라 대체제로서 실효성이 "
                    "없다. 그 다음이 사용자 결정 1건.",
        "why": "superseded duplicate — 디코드하는 opcode 6종이 전부 "
               "PE_Core 에 구현돼 있고, 정작 SIMD 계열 ISA opcode "
               "0x60-0x65/0x69 는 하나도 디코드하지 않는다 (lane-parallel "
               "형태의 ISA 진입점 0건). 값 테스트 9/9 는 건전하다 — "
               "폐기 사유는 결함이 아니라 중복이다.",
    },
    "ALU_Extended": {
        "status": "reference",
        "how": "정찰 실측 (xcu55c OOC gate_top, post-route): LUT 606 / "
               "FF 274 / DSP48 20 / Fmax 167.31 MHz — spec §28.8. "
               "**비합성 대상** — 합성 편입 경로를 신설하지 않는다.",
        "why": "reference implementation 재분류 (spec §31.6). 3개 중 "
               "유일하게 Synth 경고 0건이고 2026-07-14(7105e3c)까지 능동 "
               "유지보수됐으며 값 테스트 16/16 이 전부 result 값을 "
               "assert 한다 — 즉 폐기 후보가 아니다. 다만 통합 지점 "
               "(claude.md §6 'PE.v = ISA_Decoder + ALU wrapper') 자체가 "
               "Cluster->PE_Core 직결로 소멸했으므로 `measured-pending` "
               "(= 편입 판정 대기) 은 이미 거짓이 된 사유다. 비합성 참조 "
               "구현을 repo 에 유지하는 것의 정당성 검토는 stable release "
               "선언 라운드로 이월한다.",
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

VALID_STATUS = ("gate", "harness", "measured-pending", "superseded",
                "reference", "uncovered")


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


_TEST_AST_CACHE = {}


def _test_funcs(fname):
    """test 파일의 (함수명 -> node) 와 원본 소스. AST 로 1회만 파싱한다."""
    if fname not in _TEST_AST_CACHE:
        path = REPO_ROOT / fname
        if not path.exists():
            _TEST_AST_CACHE[fname] = (None, None)
        else:
            src = path.read_text()
            funcs = {n.name: n for n in ast.walk(ast.parse(src))
                     if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}
            _TEST_AST_CACHE[fname] = (src, funcs)
    return _TEST_AST_CACHE[fname]


def _resolve_canonical_test(module, ref):
    """v1.9.1 §31.14 — `canonical_test_refs` 항목 1건을 기계 검증한다.

    반환: 위반 사유 문자열 리스트 (빈 리스트 = OK).

    검사 2단:
      (a) 그 파일의 그 이름이 실제 `async def` 테스트 함수로 해소되는가.
          (정본 테스트가 삭제/개명되면 `superseded` 등재 근거가 사라진다)
      (b) 그 함수가 **DUT 신호를 읽는 값 assert** 를 최소 1개 갖는가.
          (`dut.` 를 참조하는 `assert ... == ...`). 이것이 없으면 그 테스트는
          §28.4 항 8(a) 의 "값 검사" 요건을 만족하지 못하므로 정본의 근거가
          될 수 없다 — 바로 구 `test_tensor_alu.py` 가 그랬다.
    """
    fname, tname = ref
    problems = []
    src, funcs = _test_funcs(fname)
    if src is None:
        return [f"{module}: canonical_test_refs 의 파일 {fname} 이 없다"]
    node = funcs.get(tname)
    if node is None:
        return [f"{module}: canonical_test_refs {fname}::{tname} 가 해소되지 "
                "않는다 — 정본의 값 검증 테스트가 삭제/개명됐다. "
                "`superseded` 등재 근거는 '안 쓰인다' 가 아니라 '정본이 있고 "
                "그것이 검증됐다' 이므로 (§12a 규칙 6), 이 참조가 끊기면 "
                "등재 자체가 무효다."]
    if not isinstance(node, ast.AsyncFunctionDef):
        problems.append(f"{module}: {fname}::{tname} 은 `async def` 가 "
                        "아니다 — cocotb 테스트가 아니다")
    has_value_assert = False
    for a in ast.walk(node):
        if not isinstance(a, ast.Assert):
            continue
        seg = ast.get_source_segment(src, a) or ""
        if "dut." in seg and ("==" in seg or "!=" in seg):
            has_value_assert = True
            break
    if not has_value_assert:
        problems.append(
            f"{module}: {fname}::{tname} 에 DUT 신호를 읽는 값 assert 가 "
            "없다 (§28.4 항 8(a)). 값을 보지 않는 테스트는 정본의 검증 "
            "근거가 될 수 없다 — 구 test_tensor_alu.py 의 "
            "`alu_valid == 1` 단독 assert 가 정확히 이 형태였다.")
    return problems


def main():
    mods = parse_makefile_mods()

    for name, e in COVERAGE.items():
        if e["status"] not in VALID_STATUS:
            sys.exit(f"lint_synth_coverage: {name}: 알 수 없는 status "
                     f"{e['status']!r} (허용: {VALID_STATUS})")
        if e["status"] in ("measured-pending", "superseded", "reference",
                           "uncovered") and not e.get("why"):
            sys.exit(f"lint_synth_coverage: {name}: status "
                     f"{e['status']!r} 는 `why` 사유 문자열이 필수다.")
        if e["status"] in ("gate", "harness", "measured-pending",
                           "superseded", "reference") and not e.get("how"):
            sys.exit(f"lint_synth_coverage: {name}: status "
                     f"{e['status']!r} 는 `how` 재현 경로가 필수다.")
        # v1.9.1 §31.6 — `superseded` 등재 요건 3건. 하나라도 비면 FAIL.
        # "안 쓰인다" 가 아니라 "정본이 있고 그것이 검증됐다" 가 근거여야
        # 한다는 §12a 규칙 6 의 기계 집행이다.
        if e["status"] == "superseded":
            for key in ("canonical", "canonical_test", "canonical_test_refs",
                        "deadline"):
                if not e.get(key):
                    sys.exit(
                        f"lint_synth_coverage: {name}: status 'superseded' "
                        f"는 `{key}` 가 필수다 (§31.6 등재 요건 + §31.14 "
                        "기계 해소 요건: 정본 모듈 / 정본의 값 검증 테스트 / "
                        "그 테스트의 기계 판독 참조 / 폐기 판정 기한 조건).")

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
    for s in ("harness", "measured-pending", "superseded", "reference",
              "uncovered"):
        for name in sorted(by_status[s]):
            e = COVERAGE[name]
            print(f"  [{s}] {name}")
            if e.get("how"):
                print(f"      경로: {e['how']}")
            if e.get("canonical"):
                print(f"      정본: {e['canonical']}")
            if e.get("canonical_test"):
                print(f"      정본검증: {e['canonical_test']}")
            if e.get("canonical_test_refs"):
                refs = ", ".join(f"{f}::{t}"
                                 for f, t in e["canonical_test_refs"])
                print(f"      정본검증(해소됨): {refs}")
            if e.get("deadline"):
                print(f"      기한: {e['deadline']}")
            if e.get("why"):
                print(f"      사유: {e['why']}")
    print()

    fail = []
    # v1.9.1 §31.14 — `canonical_test` 를 문자열이 아니라 **실체**로 검증한다.
    for name, e in sorted(COVERAGE.items()):
        for ref in e.get("canonical_test_refs", ()):
            fail.extend(_resolve_canonical_test(name, ref))
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
    n_sup = len(by_status["superseded"])
    n_ref = len(by_status["reference"])
    if n_sup > SUPERSEDED_MAX:
        fail.append(f"래칫 위반: superseded {n_sup} > 상한 {SUPERSEDED_MAX}")
    if n_ref > REFERENCE_MAX:
        fail.append(f"래칫 위반: reference {n_ref} > 상한 {REFERENCE_MAX}")

    if fail:
        for f in fail:
            print(f"VIOLATION: {f}")
        sys.exit(1)

    print(f"lint_synth_coverage OK — 미분류 0 / stale 0 / uncovered {n_unc} "
          f"<= {UNCOVERED_MAX} / measured-pending {n_pend} <= "
          f"{MEASURED_PENDING_MAX} / superseded {n_sup} <= {SUPERSEDED_MAX}"
          f" / reference {n_ref} <= {REFERENCE_MAX}")


if __name__ == "__main__":
    main()
