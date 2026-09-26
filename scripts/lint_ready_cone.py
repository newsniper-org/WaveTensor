#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""MMIO ready 의 **조합 입력 콘**에 쓰기 데이터(`io_mmio_wdata`)가 없는가 — 구조 검사.

## 왜 이 검사가 있는가

`Wt64Top.scala` `xlateArea` 의 D-2(하류 거부 = 버스 정지) 조건 ② 는 「ready 는 주소 ·
스트로브 · 상태만의 함수 — wdata 비의존」이다. 파도 3 착지판은 그것이 **기능적으로만**
참이었다: ready 덮어쓰기가 XlateStore `install.ready` 를 먹었고, install.ready 는 같은
사이클 · 같은 파티션 flush 를 조합으로 보며(`flushSamePart`), flush.valid 는 0xE00 기입의
wdata 판정(예약 · 없는 파티션 · `[7:0]` 파티션)이었다 — 넷리스트에 조합 경로
`io_mmio_wdata → flush.valid → install.ready → io_mmio_ready` 가 있었다 (rtl/README.md
파도 3 「구조 경로」). 경로는 죽어 있었지만(문의 항목 기입과 flush 발화가 주소 디코드로
배타 — yosys SAT 실측) STA 의 입력→출력 조합 경로 · 콘 기반 형식 검사는 wdata 를 본다.
파도 4 SLOTFREE 가 ready 를 flush 와 무관한 슬롯 여유(`hiu.installSlotFree`)로 바꿔 경로를
**구조로** 끊었다. 이 검사는 그것이 다시 생기지 않게 한다 — 「기능적으로 죽었다」는
논증은 다음 편집이 주소 디코드를 바꾸는 순간 조용히 거짓이 되고, 그때 남는 것은 주석이다.

## 무엇을 재는가

`rtl/generated/Wt64Top.sv` 를 yosys 로 읽어(`proc` · `flatten`) `io_mmio_ready` 의 입력
콘을 **플립플롭 · 메모리에서 끊어** 모은다(`%ci*:-$dff,…`). 그 콘의 최상위 입력 포트가

  (1) `io_mmio_wdata` 를 **포함하지 않는다** — 이것이 검사다.
  (2) `io_mmio_addr` · `io_mmio_wstrobe` 를 **포함한다** — 양성 대조. 이것이 없으면
      「wdata 가 없다」와 「콘을 못 쟀다(포트 이름이 바뀌었다 · 파싱이 깨졌다)」가 같은
      결과를 낸다 — 이 저장소가 세 번 밟은 「측정하지 못했다를 0 이었다로 보고」의 형태.

설계 성질을 조립 하네스 `[script]` 의 `select -assert-*` 에 넣지 않은 이유: 그 핀들은
하네스 무결성 전용이다 — 설계 결함이 ERROR 16 으로 오표기된다 (assembly.sby 머리).

## yosys 가 없으면 — 미측정이지 통과가 아니다

`make lint` 는 CI 에서 도구 없는 러너로도 돈다. yosys 가 PATH 에 없으면 **「미측정」을
인쇄하고** 0 으로 끝난다(`lint_tautology --audit` 의 모델 없음 처분과 같은 형태) —
`--require-yosys` 를 주면 실패한다. 자기시험도 같다.

## 자기시험 `--self-test`

생성물 사본에 변이를 셋 먹여 **정해진 문면으로** 실패하는지 본다 (다른 이유의 실패는
통과로 치지 않는다):
  M1 SLOTFREE 이전 구조 — ready 덮어쓰기를 `hiu_io_install_ready` 로 되돌린다 (파도 3 착지판의
     모양 그대로 — 2026-09-26 실측: f229c8b 생성물에서 이 검사는 실패한다).
  M2 ready 기본값에 wdata 비트 — 경로를 직접 심는다.
  M3 양성 대조 — 출력 포트 이름을 바꿔 콘을 못 재게 한다 (「없다」가 아니라 「못 쟀다」로 울어야 한다).
"""
import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GEN = ROOT / "rtl" / "generated" / "Wt64Top.sv"

_FF = ("$dff,$adff,$sdff,$dffe,$adffe,$sdffe,$sdffce,$dffsr,$dffsre,$aldff,$aldffe,"
       "$dlatch,$adlatch,$dlatchsr,$mem,$mem_v2")
_WANT_POS = ("io_mmio_addr", "io_mmio_wstrobe")   # 양성 대조 — 콘에 있어야 한다
_FORBID = "io_mmio_wdata"                          # 콘에 없어야 한다

MSG_PATH = "io_mmio_wdata 가 io_mmio_ready 의 조합 입력 콘에 있다"
MSG_POS = "양성 대조 실패 — 콘을 못 쟀다"


def _cone_inputs(sv: Path, work: Path) -> tuple[int, list[str], str]:
    """(rc, 콘의 최상위 입력 포트 이름들, yosys 로그 꼬리)."""
    out = work / "inputs.txt"
    if out.exists():
        out.unlink()
    ys = work / "cone.ys"
    ys.write_text(
        f"read_verilog -sv {sv}\n"
        "hierarchy -top Wt64Top\n"
        "proc\n"
        "flatten\n"
        "opt_clean\n"
        f"select -set rc o:io_mmio_ready %ci*:-{_FF}\n"
        f"tee -q -o {out} select -list @rc i:* %i\n",
        encoding="utf-8")
    p = subprocess.run(["yosys", "-q", "-s", str(ys)], capture_output=True, text=True)
    names = []
    if out.exists():
        for ln in out.read_text(encoding="utf-8").splitlines():
            ln = ln.strip()
            if "/" in ln:
                names.append(ln.split("/", 1)[1])
    tail = "\n".join((p.stdout + p.stderr).strip().splitlines()[-4:])
    return p.returncode, names, tail


def check(sv: Path) -> tuple[bool, str]:
    """(통과?, 한 줄 판정)."""
    with tempfile.TemporaryDirectory(prefix="wt-ready-cone-") as td:
        rc, names, tail = _cone_inputs(sv, Path(td))
    if rc != 0:
        return False, f"{MSG_POS}: yosys rc={rc} — {tail}"
    missing = [n for n in _WANT_POS if n not in names]
    if missing:
        return False, (f"{MSG_POS}: io_mmio_ready 콘에 {', '.join(missing)} 가 없다 "
                       f"(콘 입력 {names or '∅'}) — 포트 이름 · 파싱을 확인할 것")
    if _FORBID in names:
        return False, (f"{MSG_PATH} (콘 입력 {names}). ready 는 주소 · 스트로브 · 상태만의 함수여야 "
                       "한다 — Wt64Top.scala xlateArea 조건 ② (수락 전 wdata 로 ready 를 정하면 "
                       "같은 기입의 재제시가 다른 판정을 받을 수 있다)")
    return True, f"콘 입력 {sorted(names)} — wdata 없음 · 양성 대조 {list(_WANT_POS)} 있음"


_MUTATIONS = (
    ("M1 SLOTFREE 이전 구조 (ready ← install.ready)",
     "      io_mmio_ready = hiu_installSlotFree;",
     "      io_mmio_ready = hiu_io_install_ready;", MSG_PATH),
    ("M2 ready 기본값에 wdata 비트",
     "    io_mmio_ready = 1'b1;",
     "    io_mmio_ready = io_mmio_wdata[0];", MSG_PATH),
    ("M3 양성 대조 — 출력 포트 개명",
     "io_mmio_ready", "io_mmio_rdy", MSG_POS),
)


def self_test() -> int:
    ok, why = check(GEN)
    if not ok:
        print(f"lint_ready_cone --self-test: FAIL — 무변이 생성물이 이미 실패한다: {why}", file=sys.stderr)
        return 1
    src = GEN.read_text(encoding="utf-8")
    bad = 0
    with tempfile.TemporaryDirectory(prefix="wt-ready-cone-st-") as td:
        for name, old, new, want in _MUTATIONS:
            n = src.count(old)
            if n == 0 or (name.startswith(("M1", "M2")) and n != 1):
                print(f"  {name}: 변이 대상이 {n} 곳 — 자기시험을 생성물에 맞춰 고칠 것", file=sys.stderr)
                bad += 1
                continue
            m = Path(td) / "Wt64Top.sv"
            m.write_text(src.replace(old, new), encoding="utf-8")
            ok, why = check(m)
            if ok:
                print(f"  {name}: 통과했다 — 검사가 물지 않는다", file=sys.stderr)
                bad += 1
            elif want not in why:
                print(f"  {name}: 실패했으나 다른 이유다 (기대 「{want}」): {why}", file=sys.stderr)
                bad += 1
            else:
                print(f"  {name}: 선언대로 실패 — {want}")
    if bad:
        print(f"lint_ready_cone --self-test: FAIL — 변이 {bad}/{len(_MUTATIONS)} 가 선언과 다르게 행동했다",
              file=sys.stderr)
        return 1
    print(f"lint_ready_cone --self-test: OK — 변이 {len(_MUTATIONS)}/{len(_MUTATIONS)} 가 정해진 문면으로 실패")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--require-yosys", action="store_true",
                    help="yosys 가 없으면 실패한다 (기본은 「미측정」 인쇄 후 0)")
    a = ap.parse_args()
    if shutil.which("yosys") is None:
        msg = "lint_ready_cone: 미측정 — yosys 가 PATH 에 없다 (통과가 아니다)"
        if a.require_yosys:
            print(msg, file=sys.stderr)
            return 1
        print(msg)
        return 0
    if not GEN.is_file():
        print(f"lint_ready_cone: FAIL — {GEN} 가 없다", file=sys.stderr)
        return 1
    if a.self_test:
        return self_test()
    ok, why = check(GEN)
    if not ok:
        print(f"lint_ready_cone: FAIL — {why}", file=sys.stderr)
        return 1
    print(f"lint_ready_cone: OK — {why}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
