#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""run_wt64.py — WT64v1 재구현 트리의 자립형 cocotb 러너.

선례는 `synth/lattice/fp_ops/run_fp_ops_tests.py` 다. 그쪽은 Makefile 의
`MOD` 표를 쓰지 않고 파이썬이 직접 빌드·실행·집계한다. 이 러너도 같은 형태
이지만, **MOD 표를 쓰지 않는 이유가 다르다** — 저쪽은 시기(합성 게이트가
배선보다 앞섰다)였고, 이쪽은 구조다:

`rtl/generated/` 18편은 평면이 아니라 **중복 정의 그래프**다. 실측
(Verilator 5.048) — `Wt64Top.sv` 가 module 정의 18개를 자기 안에 갖고,
`HiuPipeline.sv` 가 `XlateStore` 를, `SharedUnit.sv` 와
`SharedUnitDepth0.sv` 가 `SharedUnitOccupyStub` 를 각각 정의한다. 두 편을
한 소스 목록에 넣으면 `%Warning-MODDUP` 이 뜨고 그것은 기본 fatal 이다.
⇒ 형상마다 **별도 build_dir 로 따로 도는 수밖에 없고**, 그것은 Makefile
`ifeq` 표가 아니라 파이썬 루프다. 그래서 `SOURCES` 는 언제나 길이 1 이다
(파일 단위로 폐포가 이미 잡혀 있다 — SpinalHDL 이 컴포넌트마다 하위를
인라인해 낸다). 규칙으로 못박아 나중에 손이 두 편을 합칠 자리를 없앤다.

═══════════════════════════════════════════════════════════════════════════
## 이 러너가 재지 못하는 것 — 먼저 적는다
═══════════════════════════════════════════════════════════════════════════

**투입 방향(호스트 명령 큐 / E.5 명령 링)은 RTL 에 미착지다.**

근거 (직접 열어 확인한 것):
  · `rtl/spinal/src/main/scala/wt64/top/Wt64Top.scala:876-877` — 일의 유일한
    원천은 `io.instr.valid` / `io.instr.words` 외부 제시다.
  · 생성물 `rtl/generated/Wt64Top.sv:13-31` 에 `io_instr_valid` 는 있고
    **`io_instr_ready` 가 없다.** 명령 제시는 배압 없는 단방향 스트로브다.
  · `Wt64Top.scala:1139-1143` 의 `selUnwired` 가 `R_SQ`(0x380–0x3FF)를
    「명령 방향 실물 0건」이라 열거한다.
  · `host/CompletionUnit.scala:1-27` 은 스스로 **완료 방향** 표면 셋
    (완료 큐 E.5 · 완료 통지 E.6 · 드레인 관측면 E.11)만 담는다고 적는다.

⇒ 이 하네스에서 **호스트는 하네스 자신**이고, 다음 다섯은 잴 대상이 아예
   없다 (여기 없는 것은 미측정이지 통과가 아니다):
     ① 명령 링 head/tail 전진 · ② 링 가득 참 / 한 칸 비움 인코딩
     ③ 가득 링 밀어넣기의 loud fault (E.5 3항)
     ④ 호스트 쪽 배압 정지 · ⑤ 크레딧 반환
⇒ 그러므로 이 하네스의 ISA-1/ISA-2 는 **호스트 ABI 층위의 등가가 아니라
   디코드 진입 층위의 등가**다. 그 문장을 증거에 그대로 박는다.

재는 것: 명령 *제시*(valid 1사이클) 이후의 경로 — 디코드 관측면, 라우팅
판정, 구성 표면 처분, 그리고 마스킹 유닛의 SEC-1 golden 정확 대조.
각 스위트가 무엇을 재고 무엇을 재지 못하는지는 `rtl/sim/README.md` 와
각 하네스 파일 머리 주석이 갈라 적는다.

═══════════════════════════════════════════════════════════════════════════
## 선례에서 갈라지는 세 곳 (베끼면 안 되는 결함)
═══════════════════════════════════════════════════════════════════════════

**(a) 0건 통과.** 선례는 `if num_failed:` 만 본다 — 테스트 0건이면
「0 tests passed」를 찍고 exit 0 이다. 기대 건수 없는 계수는 계수가 아니다.
⇒ 표에 `expect_min` 칸을 두고 하한 미달을 FAIL 로 만든다.

**(b) skip 무계수.** `cocotb_tools.check_results.get_results` 는
`<testcase>` 와 `<failure>` 만 센다 (check_results.py:33-39). cocotb 는
skip 을 `<skipped>` 로 적는다 (`cocotb/_xunit_reporter.py:99`). ⇒ **자기
skip 한 테스트가 「돌았고 실패 0」으로 읽힌다.** 이 저장소가 이미 밟은
형태다 — `scripts/lint_frag_slots_dual_run.py` 가 존재하는 이유가 정확히
「FRAG_SLOTS>1 전용 6건이 기본 빌드에서 값 검사 0건 하고 PASS 로 집계됐다」
다. ⇒ `get_results` 를 쓰지 않고 XML 을 직접 세되 `<skipped>` 를 **실패로**
집계한다. skip 이 정당하면 표를 고치는 편집으로 하고, 그 편집이 리뷰
대상이 된다.

**(c) 인터프리터.** 선례 docstring 은 `python3 …` 라 적지만 이 호스트의
`/usr/bin/python3` 는 `cocotb_tools` 를 갖지 않는다 (cocotb 는 전용 venv 에
있다 — `.devcontainer/Dockerfile:105` 가 그 벽을 이미 문면으로 적는다).
⇒ Makefile `rtl-sim` 이 `cocotb-config --python-bin` 에게 인터프리터를
묻는다. 이 파일을 `python3` 으로 직접 부르면 `ModuleNotFoundError` 로
죽고, 그것은 「측정했는데 실패」가 아니라 「도구를 못 찾음」이라 원인이
오독된다. 그래서 아래 `main()` 이 그 오독을 선제 차단한다.

호출:
    $(cocotb-config --python-bin) rtl/sim/run_wt64.py [스위트…]
    make rtl-sim [SIM_SUITES="Mask Shape"]
"""

import os
import sys
import tempfile
from pathlib import Path
from xml.etree import ElementTree

REPO = Path(__file__).resolve().parents[2]
GEN = REPO / "rtl" / "generated"
SIM = Path(__file__).resolve().parent

# ---------------------------------------------------------------------------
# 스위트 표.
#
# `src` 는 **언제나 한 편**이다 (위 MODDUP 규칙). `expect_min` 은 그 하네스가
# 반드시 돌려야 하는 cocotb 테스트 건수의 하한이다 — 선례가 갖지 못한 칸이고,
# 없으면 「0건 통과」가 성립한다.
# ---------------------------------------------------------------------------
SUITES = {
    "Mask": {
        "top": "MaskUnit",
        "src": "MaskUnit.sv",
        "test_module": "test_mask_golden",
        # 2026-09-22 8 → 10: 임대별 키(정본 7fa5f2e · RTL ca3c496)의 값 수준
        # 지향 시험 둘(key_scope_cross_partition_value ·
        # wr_other_partition_during_rekey_is_clean) 신설. 하한이지 계수가 아니다.
        # 2026-09-22 10 → 11: 파도 D — FINAL 엣지 같은-파티션 동시 기입 지향
        # 시험(wr_same_partition_at_final_edge_is_loud) 신설.
        "expect_min": 11,
        "what": "SEC-1 golden 정확 대조 (mask64[43:12] 사영) + fault 3축 + 고정 지연 "
                "+ 임대별 키 범위(값)",
    },
    "Shape": {
        "top": "Wt64Top",
        "src": "Wt64Top.sv",
        "test_module": "test_shape_equiv",
        "expect_min": 6,
        "what": "ISA-2 순열 (LBID·LNID 존재 축) + ISA-1 자리 무관성 + 비교기 자기대조",
    },
}


def tally(results_xml):
    """결과 XML 을 **직접** 센다.

    `cocotb_tools.check_results.get_results` 를 쓰지 않는 이유는 그것이
    `<skipped>` 를 세지 않기 때문이다 (check_results.py:33-39 는 testcase 와
    failure 만 본다). 그러면 자기 skip 한 테스트가 「돌았고 실패 0」으로
    읽힌다.

    파일이 없으면 예외를 낸다 — 미완료 로그는 통과가 아니다.
    """
    p = Path(results_xml)
    if not p.is_file():
        raise RuntimeError(f"결과 XML 이 없다: {p} — 시뮬레이션 미완료다")
    tree = ElementTree.parse(p)
    n = fail = skip = 0
    names = []
    for ts in tree.iter("testsuite"):
        for tc in ts.iter("testcase"):
            n += 1
            names.append(tc.get("name", "?"))
            if next(tc.iter("failure"), None) is not None:
                fail += 1
            if next(tc.iter("skipped"), None) is not None:
                skip += 1
    return n, fail, skip, names


def run_one(name, build_root):
    from cocotb_tools.runner import get_runner

    cfg = SUITES[name]
    src = GEN / cfg["src"]
    if not src.is_file():
        sys.exit(f"{name}: 생성물이 없다: {src} — `make rtl-gen` 이 선행이다")

    runner = get_runner("verilator")
    build_dir = Path(build_root) / name  # 스위트마다 격리 — MODDUP 회피의 절반
    runner.build(
        sources=[str(src)],  # 길이 1 — 위 규칙
        includes=[str(REPO / "include")],
        hdl_toplevel=cfg["top"],
        build_dir=str(build_dir),
        waves=False,
    )
    # ⚠ `runner.test()` 는 pytest 밖에서 **실패를 판정하지 않는다.**
    #    `cocotb_tools/runner.py:561-577` 의 `if pytest_current_test:` 블록이
    #    통째로 건너뛰어지므로, 시뮬이 exit 0 으로 끝나면서 테스트가 전부
    #    FAIL 이어도 이 호출은 조용히 Path 를 돌려준다. 판정은 아래 tally 다.
    results_xml = runner.test(
        hdl_toplevel=cfg["top"],
        test_module=cfg["test_module"],
        build_dir=str(build_dir),
        test_dir=str(build_dir),
    )
    n, fail, skip, names = tally(results_xml)

    bad = []
    if fail:
        bad.append(f"{fail}/{n} 실패")
    if skip:
        # 조용한 self-skip 금지. 조건이 안 맞으면 스스로 건너뛰고 통과로
        # 보고하는 검사는 정본 §6.7 이 지목한 실패형이다.
        bad.append(f"skip {skip}건 — 값을 보지 않은 테스트가 통과로 집계됐다")
    if n < cfg["expect_min"]:
        bad.append(f"계수 {n} < 하한 {cfg['expect_min']} — 미측정이지 통과가 아니다")
    if bad:
        sys.exit(
            f"{name}: " + " / ".join(bad)
            + f"\n  실행된 테스트: {', '.join(names) or '(없음)'}"
            + f"\n  results: {results_xml}"
        )
    print(f"{name}: {n} tests passed (skip 0, 하한 {cfg['expect_min']}) — {cfg['what']}")
    return n


# ---------------------------------------------------------------------------
# 미측정 원장 — 통과 계수와 **같은 자리에** 인쇄한다.
#
# 다음 사람이 「끝-끝 하네스가 있다」를 「투입도 잰다」로 읽는 것을 막는
# 유일한 장치다. 열거하지 않으면 그 오독이 기본값이 된다.
# 각 항의 근거는 이 저장소 파일:라인이고, 착지하면 그 줄이 사라진다.
# ---------------------------------------------------------------------------
UNMEASURED = [
    ("투입 방향 일체 (명령 링 head/tail · 가득 참 · E.5 3항 loud fault · "
     "배압 정지 · 크레딧)",
     "회로 0건 — Wt64Top.sv 에 io_instr_ready 부재, Wt64Top.scala:1139 selSq UNWIRED"),
    ("ISA-1 두-형상 대조 (nPoints 4 ↔ 2)",
     "형상 B 생성기 부재 — rtl/spinal/.../gen/GenWt64TopShape.scala 미착지. "
     "비교기 자체는 isa1_comparator_selfcheck 가 양·음성 대조로 살아 있음을 확인한다"),
    ("ISA-2 자리 축 (LNID 소유 지점 [23:16] · LBID 슬롯 구간 [15:0] 순열)",
     "관측면 부재 — RouteJudge 는 지점별 소유를 모르고(RouteJudge.scala:145), "
     "구간값 소비자 Reassembly.wr→ResultBank.write 가 미배선(Wt64Top.scala:81-83)"),
    ("fp32 산술 정확성 (golden_fp32 비트 일치)",
     "StepSequencer.scala:425-426 이 UInt 정수곱·정수합 — 산술은 축 (b) 후속"),
    ("mask64 의 32비트 ([63:44]·[11:0])",
     "MaskUnit.scala:289-296 「저장은 적용 비트만」 — 적용 슬라이스만 물질화, 레지스터도 배선도 없다. "
     "비교 불가가 아니라 비교 대상 부재"),
    ("SUBKEY(256b)·BLOCK(512b) 필드를 통한 부분 수리 검출",
     "재구현 MaskUnit 에 부표준키·블록 워드를 내는 포트가 없다 — 계층 peek 은 "
     "포트 계약이 아니라 SpinalHDL 명명의 우연이므로 통과 기준으로 쓰지 않는다"),
    ("FAULT_STATUS[17]·[18]",
     "Wt64Top.sv:1491-1492 상수 0 — 엔트로피원·명령 디스크립터 원천 부재. "
     "0 을 「정상」으로 읽으면 안 된다"),
    ("SharedUnit·MemOrderGate 독립 .sv 의 top 대표성",
     "형상 불일치 — 독립본 reqWidth=16/reqW=16 vs top 인스턴스 161/128비트"),
    ("OPREF B 참조의 LBID 축",
     "제시 자체가 없다 — Wt64Top.scala:84 (TODO 2항) · :925-927, tokIn 은 사이클당 하나"),
]


def print_unmeasured():
    print()
    print("── 미측정 원장 (이 하네스가 재지 '못하는' 것) " + "─" * 28)
    for i, (what, why) in enumerate(UNMEASURED, 1):
        print(f"  {i}. {what}")
        print(f"     근거: {why}")
    print(f"  총 {len(UNMEASURED)}축 미측정 — 미측정은 통과가 아니다 (정본 §6.7 원칙 5).")
    print("─" * 74)


def main():
    try:
        import cocotb_tools.runner  # noqa: F401
    except ImportError:
        sys.exit(
            "run_wt64: `cocotb_tools` 를 import 할 수 없다 — 이것은 「측정했는데 "
            "실패」가 아니라 「도구를 못 찾음」이다.\n"
            f"  현재 인터프리터: {sys.executable}\n"
            "  이 저장소의 cocotb 는 시스템 python 이 아니라 전용 venv 에 있다.\n"
            "  올바른 호출: $(cocotb-config --python-bin) rtl/sim/run_wt64.py\n"
            "  또는:        make rtl-sim"
        )

    wanted = sys.argv[1:] or list(SUITES)
    for name in wanted:
        if name not in SUITES:
            sys.exit(f"알 수 없는 스위트 '{name}' (유효: {', '.join(SUITES)})")

    build_root = os.environ.get("WT_SIM_BUILD") or tempfile.mkdtemp(prefix="wt_sim_")
    # 저장소 안에 빌드 산출물을 만들지 않는다 — `scripts/lint_forbidden_terms.py`
    # 의 SKIP_DIRS 에 `sim_build` 가 있어 저장소 안 빌드는 lint 를 조용히
    # 건너뛰게 만든다. 선례 94-95행과 같은 처분.
    #
    # tb 모듈이 오라클을 import 할 수 있게 두 곳이 필요하다:
    #   asm/     — generated_isa_tables (wavetensor_asm 이 상대 import 한다)
    #   scripts/ — acc_format_study · golden_fp32 · golden_lattice 상호 import
    paths = [str(SIM), str(REPO / "asm"), str(REPO / "scripts")]
    for p in reversed(paths):
        if p not in sys.path:
            sys.path.insert(0, p)
    existing = os.environ.get("PYTHONPATH", "")
    os.environ["PYTHONPATH"] = os.pathsep.join(paths + ([existing] if existing else []))
    os.environ["WT_REPO"] = str(REPO)

    total = 0
    # ⚠ 원장은 **실패 실행에서도** 인쇄한다. `run_one` 은 실패 시 `sys.exit` 로
    #   빠져나가므로 이 자리가 `try` 밖에 있으면 「매 실행 인쇄한다」가 성립하지
    #   않는다 — 원장을 가장 읽어야 할 사람이 실패를 보고 있는 사람이다
    #   (「어디까지 잰 하네스가 깨진 것인가」가 원장 없이는 안 잡힌다).
    #   finally 가 먼저 돌고 SystemExit 문면이 그 뒤에 찍혀 실패가 마지막에 남는다.
    try:
        for name in wanted:
            print(f"=== {name}: build + test (build root: {build_root}) ===")
            total += run_one(name, build_root)
        print(f"\nrun_wt64: 요청 스위트 {len(wanted)}건 / cocotb 테스트 {total}건 전부 통과")
    finally:
        print_unmeasured()


if __name__ == "__main__":
    main()
