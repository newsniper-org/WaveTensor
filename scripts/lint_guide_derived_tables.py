#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""정본의 *파생 표*가 원천과 어긋나지 않는지 검사한다.

## 왜 이 검사가 있는가

정본에는 다른 곳의 사실을 *요약해 적은* 표와 문장이 여럿이다 — 속성 총수,
축별 분류, 단계별 분류, 진행 현황의 run 수. 이것들은 원천이 아니라 파생이고,
파생은 원천이 움직이면 조용히 낡는다.

이 저장소에서 그 드리프트가 **다섯 번** 일어났다.

  1. 부록 D 축별 분류가 27 인데 실물이 39 였다 (HIU-8~11 추가 시 갱신 누락)
  2. §3.9 요약 표가 본문과 어긋났다
  3. README 의 쪽수가 낡았다
  4. 부록 D 진행 현황이 낡았다
  5. 부록 B.5 해설의 산술이 표 행 수와 맞지 않았다 (아홉 vs 열둘)

다섯 번 모두 *컴파일은 통과했고 아무 테스트도 실패하지 않았다.* 파생 표는
틀려도 조용하다 — 그것이 이 검사가 필요한 이유 전부다.

정본 README §검증 6항은 이 대조를 *셸 스니펫으로* 적어 두었다. 사람이 손으로
돌리는 검사이며, 부록 B.3 이 「집행되지 않는 규율」이라 부른 것과 같은 형태다.
그래서 기계로 옮겼다.

## 무엇을 대조하는가

  (1) 각 장 `#속성(...)` 선언 수  ==  부록 D 색인 행 수
  (2) 부록 D 축별 분류 합         ==  위 수
  (3) 부록 D 단계별 분류 합       ==  위 수
  (4) 부록 D 진행 현황의 run 수   ==  rtl/formal/tla/run.sh 의 expect_* 수
  (5) 명령어 최대 길이 주장       ==  어셈블러 상수 (그리고 서로)

## (5) 는 왜 뒤늦게 생겼는가 — 여섯 번째 드리프트

인코딩 개정 파도(W8)가 CH 한 워드를 넣어 최대 길이를 416b/13워드 →
448b/14워드로 옮겼다. 정본은 그 값을 **세 곳**에 적는다 — §1.3.1 규범
「최대 길이」의 산술 · §4.6 「인코딩 용량」의 현행 문장 · 부록 B 원장의
*현재* 칸. 파도는 앞의 둘만 고쳤고 **원장 칸은 416비트로 남았다.** 같은
정본이 자기 안에서 32비트 어긋났고, 재구현의 유일한 기준이 그것이다
(부록 B 만 읽은 재구현자는 13워드 버스를 판다). `make guide` 도 이 검사도
그 수치를 재지 않았다 — 둘 다 rc=0 이었다.

같은 값이 **확장 명세**에도 파생된다 (`docs/extensions/*.md` 는 base 상한을
인용해 자기 EH 사슬이 그 안임을 논증한다). 실제로 `wt64v1-c.md` 가 상한을
13워드로 적어 형제 문서 둘과 어긋났다. 그래서 스윕은 확장 문서까지 본다.

원천은 **어셈블러 상수**다 (`asm/wavetensor_asm.py` 의 `INSTR_WORDS_REAL` ·
`INSTR_WIDTH_BITS`) — 바이너리를 실제로 내는 쪽이고, 문서 셋은 전부 그것의
파생이다. 낡은 값(CH 개정 *이전* = 한 워드 적은 값)은 금지가 아니라
**표지 강제**다: 역사로 적으려면 그 자리에서 역사라고 말해야 한다.

이 검사는 매 실행마다 자기 **반증력**을 증명한다 — 인메모리 변이 여섯 개를
먹여 넷이 전부 우는지 확인하고, 하나라도 조용하면 그 자리에서 실패한다.
(공허한 게이트를 막는 그물이 스스로 공허해질 수 있다는 것이 이 저장소가
반복해 배운 교훈이다.)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GUIDE = ROOT / "docs" / "wt64v1-architecture-guide"
EXTDOCS = ROOT / "docs" / "extensions"
ASM = ROOT / "asm" / "wavetensor_asm.py"
RUNSH = ROOT / "rtl" / "formal" / "tla" / "run.sh"

PREFIXES = ("ISA", "FAB", "HIU", "EXT", "SEC")

# 낡은 값을 *역사로* 적을 때 붙어 있어야 하는 표지. 이 목록에 없는 문면으로
# 낡은 값을 적으면 현재 시제 주장으로 간주한다 — 부록 B 원장 칸이 정확히
# 그렇게 틀렸다 (「최대 416비트로 전면 대체됨」은 현재 시제다).
_HISTORICAL = ("이전", "종전", "과거", "이었다", "였다", "개정 전", "옛")


class Drift(Exception):
    """(5) 계열 불일치. 자기 시험이 이것을 잡아 반증력을 확인한다."""


def fail(msg: str) -> None:
    print(f"lint_guide_derived_tables: FAIL — {msg}", file=sys.stderr)
    sys.exit(1)


def _asm_length_constants(asm_text: str):
    """원천 — 어셈블러가 실제로 집행하는 워드 수와 비트 폭."""
    m = re.search(r"^INSTR_WORDS_REAL\s*=\s*(\d+)\s*$", asm_text, re.M)
    if m is None:
        raise Drift(
            "L0: asm/wavetensor_asm.py 에서 INSTR_WORDS_REAL 을 읽지 못했다 — "
            "명령어 길이의 원천이 사라졌으면 아래 대조는 전부 공허하다")
    words = int(m.group(1))
    if re.search(r"^INSTR_WIDTH_BITS\s*=\s*INSTR_WORDS_REAL\s*\*\s*32\b",
                 asm_text, re.M) is None:
        raise Drift(
            "L0: INSTR_WIDTH_BITS 가 INSTR_WORDS_REAL * 32 로 유도되지 않는다 "
            "— 유도가 끊기면 이 검사가 잘못된 비트 수를 원천으로 삼는다")
    return words, words * 32


def check_length_claims(isa_text, ext_text, bgaps_text, sweep, words, bits):
    """(5) 명령어 최대 길이 — 원천 하나, 파생 셋, 그리고 낡은 값 스윕.

    `sweep` 은 [(표시 이름, 본문), ...]. 불일치는 Drift 로 던진다.
    """
    # --- L1: §1.3.1 규범 「최대 길이」의 산술 -----------------------------
    blk = re.search(r'#규범\(라벨: "최대 길이"\)\[(.*?)^\]', isa_text,
                    re.S | re.M)
    if blk is None:
        raise Drift(
            'L1: §1.3.1 규범 「최대 길이」 블록을 찾지 못했다 — 최대 길이의 '
            '규범 자리가 사라졌거나 라벨이 바뀌었다. 이 앵커가 조용히 '
            '빠지면 나머지 대조가 반쪽이 된다')
    arith = re.search(
        r"\$\s*(\d+)\s*\+\s*(\d+)\s*\+\s*(\d+)\s*times\s*(\d+)\s*=\s*(\d+)\s*\$",
        blk.group(1))
    if arith is None:
        raise Drift("L1: 규범 「최대 길이」에서 비트 산술을 읽지 못했다")
    a, b, c, d, rhs = (int(x) for x in arith.groups())
    if a + b + c * d != rhs:
        raise Drift(
            f"L1: 규범의 산술이 스스로 틀렸다 — {a} + {b} + {c}×{d} = "
            f"{a + b + c * d} 인데 {rhs} 라 적었다")
    if rhs != bits:
        raise Drift(
            f"L1: 규범 「최대 길이」는 {rhs}비트, 어셈블러는 {bits}비트"
            f"(INSTR_WORDS_REAL={words}) — 정본과 실물이 갈렸다")

    # --- L2: §4.6 「인코딩 용량」의 현행 문장 ------------------------------
    sect = re.search(r"^== 인코딩 용량(.*?)(?=^== )", ext_text, re.S | re.M)
    if sect is None:
        raise Drift("L2: §4.6 「인코딩 용량」 절을 찾지 못했다")
    body = sect.group(1)
    if f"{bits}비트" not in body:
        raise Drift(
            f"L2: §4.6 이 현행 최대 길이 {bits}비트를 적지 않는다 — 여기가 "
            f"「이전 값 → 현행 값」을 나란히 적는 유일한 자리다")
    if f"*{words}워드*" not in body:
        raise Drift(
            f"L2: §4.6 이 도달 가능 최대 *{words}워드*를 적지 않는다 — "
            f"비트 수만 맞고 워드 수가 어긋나면 버스 폭이 어긋난다")

    # --- L3: 부록 B 원장의 *현재* 칸 -------------------------------------
    row = re.search(r"\[명령어 길이\],\s*\[[^\]]*\],\s*\[(.*?)\],\s*?\n\n",
                    bgaps_text, re.S)
    if row is None:
        raise Drift(
            "L3: 부록 B 원장의 「명령어 길이」 행을 찾지 못했다 — 이 행이 "
            "여섯 번째 드리프트가 난 자리다")
    cell = row.group(1)
    if f"{bits}비트" not in cell and f"{bits}b" not in cell:
        raise Drift(
            f"L3: 부록 B 원장의 *현재* 칸이 {bits}비트를 적지 않는다: "
            f"{' '.join(cell.split())[:120]}")

    # --- L4: 낡은 값은 역사 표지 없이 적을 수 없다 ------------------------
    # CH 개정이 더한 것은 정확히 한 워드다 — 그래서 개정 *이전* 값은
    # 유도된다. 하드코딩이 아니다.
    old_bits, old_words = bits - 32, words - 1
    stale = ((rf"(?<!\d){old_bits}\s*비트", f"{old_bits}비트"),
             (rf"(?<!\d){old_bits}\s*b\b", f"{old_bits}b"),
             (rf"(?<!\d){old_words}\s*워드", f"{old_words}워드"))
    for name, text in sweep:
        flat = re.sub(r"\s+", " ", text)
        for pat, label in stale:
            for m in re.finditer(pat, flat):
                win = flat[max(0, m.start() - 90):m.end() + 90]
                if not any(h in win for h in _HISTORICAL):
                    raise Drift(
                        f"L4: {name} 이 낡은 값 {label} 를 현재 시제로 적는다 "
                        f"(현행은 {bits}비트/{words}워드). 역사로 적으려면 그 "
                        f"자리에서 역사라고 말해야 한다 — 표지 {list(_HISTORICAL)[:3]} "
                        f"중 하나가 근처에 없다: …{win.strip()[:140]}…")

    return f"명령어 최대 길이 {bits}b/{words}워드 정합 (규범·§4.6·부록 B · 스윕 {len(sweep)}건)"


def _self_test(isa_text, ext_text, bgaps_text, sweep, words, bits):
    """이 검사가 무엇을 배제하는지 매 실행마다 증명한다.

    변이 여섯을 먹여 전부 Drift 가 나야 한다. 하나라도 조용하면 그 결은
    검사되지 않는 것이고, 검사되지 않는 결은 다음 파도에서 다시 낡는다.
    """
    old_bits, old_words = bits - 32, words - 1
    cases = [
        ("규범 산술의 우변을 개정 전 값으로",
         (isa_text.replace(f"= {bits}$", f"= {old_bits}$"), ext_text,
          bgaps_text, sweep)),
        ("규범 산술의 좌변을 깨뜨림",
         (isa_text.replace("4 times 96", "3 times 96"), ext_text,
          bgaps_text, sweep)),
        ("규범 앵커 삭제",
         (isa_text.replace('#규범(라벨: "최대 길이")', '#트랙("최대 길이")'),
          ext_text, bgaps_text, sweep)),
        ("§4.6 현행 문장을 개정 전 값으로",
         (isa_text, ext_text.replace(f"{bits}비트", f"{old_bits}비트"),
          bgaps_text, sweep)),
        ("부록 B 원장 칸에서 현행 값 삭제",
         (isa_text, ext_text,
          bgaps_text.replace(f"최대 {bits}비트", "최대 여러 비트"), sweep)),
        ("표지 없는 낡은 값 삽입",
         (isa_text, ext_text, bgaps_text,
          sweep + [("(변이 문서)",
                    f"상한은 {old_words}워드 · 최대 {old_bits}비트다.")])),
    ]
    for label, (i, e, b, s) in cases:
        try:
            check_length_claims(i, e, b, s, words, bits)
        except Drift:
            continue
        fail(
            f"자기 시험 실패 — 변이 「{label}」 를 이 검사가 잡지 못한다. "
            f"(5) 는 그만큼 공허하다")


def main() -> None:
    if not GUIDE.is_dir():
        fail(f"정본 디렉터리가 없다: {GUIDE}")

    # --- 원천 (1): 각 장의 #속성 선언 -------------------------------------
    declared = []
    for f in sorted((GUIDE / "chapters").glob("*.typ")):
        declared += re.findall(r'#속성\("([A-Z]+-\d+)"', f.read_text(encoding="utf-8"))
    n_declared = len(declared)
    if n_declared == 0:
        fail("각 장에서 #속성 선언을 하나도 찾지 못했다 — 조판 환경 이름이 바뀌었나")

    dupes = {p for p in declared if declared.count(p) > 1}
    if dupes:
        fail(f"속성 ID 중복 선언: {sorted(dupes)}")

    # --- 파생 (1): 부록 D 색인 행 ----------------------------------------
    dpath = GUIDE / "appendix" / "d-properties.typ"
    dtext = dpath.read_text(encoding="utf-8")
    index_rows = re.findall(r"^  \[((?:%s)-\d+)\]," % "|".join(PREFIXES), dtext, re.M)
    n_index = len(index_rows)
    if n_index != n_declared:
        fail(
            f"속성 수 불일치 — 각 장 선언 {n_declared} vs 부록 D 색인 {n_index}\n"
            f"  색인에만: {sorted(set(index_rows) - set(declared))}\n"
            f"  선언에만: {sorted(set(declared) - set(index_rows))}"
        )

    # --- 파생 (2): 축별 분류 표 ------------------------------------------
    # 표 행은 `[(a) …], […], [38],` 형태다. *합계* 행도 함께 대조한다.
    # 이 셋(세 축 · 합계 · 실물)이 전부 같아야 한다 — 드리프트 1번이 정확히
    # 여기서 났다 (축 (a) 를 25 로 두어 합계 27, 실물은 39).
    axes = dict(
        (k, int(v))
        for k, v in re.findall(r"^  \[\(([abc])\)[^\]]*\], \[[^\]]*\], \[(\d+)\],", dtext, re.M)
    )
    if set(axes) != {"a", "b", "c"}:
        fail(
            "부록 D 축별 분류 표를 읽지 못했다 — 표가 사라졌거나 형식이 바뀌었다. "
            "이 검사가 조용히 건너뛰면 드리프트 1번이 그대로 재발한다"
        )
    axis_sum = axes["a"] + axes["b"] + axes["c"]
    if axis_sum != n_declared:
        fail(
            f"축별 분류 합 {axis_sum} != 속성 수 {n_declared} "
            f"((a) {axes['a']} / (b) {axes['b']} / (c) {axes['c']})"
        )
    total = re.search(r"^  \[\*합계\*\], \[\], \[\*(\d+)\*\],", dtext, re.M)
    if total is None:
        fail("부록 D 축별 분류 표에 *합계* 행이 없다")
    if int(total.group(1)) != n_declared:
        fail(f"축별 분류 표의 합계 {total.group(1)} != 속성 수 {n_declared}")

    # --- 파생 (3): 단계별 분류 합 ----------------------------------------
    n_pre = sum(1 for m in re.finditer(r'#속성\("[A-Z]+-\d+", 단계: "선"', "".join(
        f.read_text(encoding="utf-8") for f in sorted((GUIDE / "chapters").glob("*.typ")))))
    n_post = n_declared - n_pre
    stage = re.search(r"선\s*\*?(\d+)\*?\s*/\s*후\s*\*?(\d+)", dtext)
    if stage:
        s_pre, s_post = int(stage.group(1)), int(stage.group(2))
        if (s_pre, s_post) != (n_pre, n_post):
            fail(
                f"단계별 분류 불일치 — 부록 D 는 선 {s_pre}/후 {s_post}, "
                f"실물은 선 {n_pre}/후 {n_post}"
            )

    # --- 파생 (4): 진행 현황의 run 수 vs run.sh --------------------------
    if not RUNSH.is_file():
        fail(f"형식 배터리가 없다: {RUNSH}")
    # 호출만 센다. `expect_pass() {` 같은 *정의* 줄은 제외해야 한다 —
    # 처음 판은 `\b` 로 끝내서 정의 둘을 함께 세었고, 이 검사 자신이
    # 2 만큼 어긋난 수를 보고했다. 파생 표를 지키는 검사도 파생이다.
    runs = len(re.findall(r"^expect_(?:pass|fail)[ \t]", RUNSH.read_text(encoding="utf-8"), re.M))
    if runs == 0:
        fail("run.sh 에서 expect_pass/expect_fail 를 하나도 찾지 못했다")

    claimed = re.search(r"\*(\d+)\s*run\*", dtext)
    if claimed is None:
        fail("부록 D 진행 현황에 run 수가 적혀 있지 않다 — 파생 표가 사라졌다")
    n_claimed = int(claimed.group(1))
    if n_claimed != runs:
        fail(
            f"run 수 불일치 — 부록 D 는 {n_claimed} run, "
            f"rtl/formal/tla/run.sh 는 {runs} run"
        )

    # --- 파생 (5): 명령어 최대 길이 주장 ---------------------------------
    if not ASM.is_file():
        fail(f"어셈블러가 없다: {ASM} — 명령어 길이의 원천이다")
    isa_p = GUIDE / "chapters" / "01-isa-asm.typ"
    ext_p = GUIDE / "chapters" / "04-ext-payload.typ"
    for p in (isa_p, ext_p):
        if not p.is_file():
            fail(f"정본 장이 없다: {p}")
    read = lambda p: p.read_text(encoding="utf-8")
    sweep = [(str(p.relative_to(ROOT)), read(p))
             for p in sorted(GUIDE.glob("chapters/*.typ"))
             + sorted(GUIDE.glob("appendix/*.typ"))
             + sorted(EXTDOCS.glob("*.md"))]
    isa_text, ext_text = read(isa_p), read(ext_p)
    bgaps_text = read(GUIDE / "appendix" / "b-gaps.typ")
    try:
        words, bits = _asm_length_constants(read(ASM))
        # 매 실행마다 반증력을 먼저 증명하고, 그 다음에 실물을 잰다.
        _self_test(isa_text, ext_text, bgaps_text, sweep, words, bits)
        length_note = check_length_claims(isa_text, ext_text, bgaps_text,
                                          sweep, words, bits)
    except Drift as exc:
        fail(str(exc))

    print(
        f"lint_guide_derived_tables: OK — 속성 {n_declared}건 "
        f"(선 {n_pre} / 후 {n_post}) · 부록 D 색인 {n_index}건 정합"
        + f" · 축별 (a){axes['a']}/(b){axes['b']}/(c){axes['c']} 합계 정합"
        + f" · 형식 배터리 {runs} run 정합"
        + f" · {length_note}"
    )


if __name__ == "__main__":
    main()
