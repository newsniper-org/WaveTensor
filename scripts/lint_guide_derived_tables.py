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
  (3) 부록 D 단계별 분류 합       ==  위 수 (D.2 의 *모든* 사본 — 분류 문장과
      진행 현황의 분모 둘 다)
  (4) 부록 D 진행 현황의 run 수   ==  rtl/formal/tla/run.sh 의 expect_* 수
  (5) 명령어 최대 길이 주장       ==  어셈블러 상수 (그리고 서로), 그리고 그
      주장이 가리키는 *절 번호* == 4장에서 「인코딩 용량」의 실제 차례
  (6) 부록 B.5 요약 계수          ==  B.5 표를 파싱해 센 값 (행 수 · 네 부류 ·
      미결 분해 넷 · 해설 산술의 좌변과 우변 · 그리고 요약 문장 *밖*의
      산문에 남은 행 수 사본 전부)
  (7) README 가 인용하는 수        ==  위에서 센 값 · `refs.yml` 실물 항 수
      (앵커는 현재 시제 주장에만 둔다 — 날짜 박힌 기록 안이면 실패)
  (8) 부록 D 진행 현황의 모델 수   ==  rtl/formal/tla 실물 (`.tla` 편수 ·
      run.sh 의 `M=` 집합 · 색인 속성을 덮는 모델 수 · 축 모델의 이름과 수 —
      아래 「(8) 은 무엇을 재고 무엇을 안 재는가」)

## (3) 은 도입 이래 한 번도 돌지 않았다 — 일곱 번째 드리프트

이 검사가 실패한 방식이 이 파일이 경고하는 바로 그 형태다. (3) 의 정규식은
「선 31 / 후 12」를 찾는데 정본 문면은 「*선-formal 31 · 후-formal 12*」라
적는다. 매치가 `None` 이었고, 코드는 `if stage:` 로 *조용히 건너뛰었다.*
그러면서 OK 줄은 자기가 센 값으로 「(선 31 / 후 12)」를 인쇄해 **정본 주장을
대조한 것처럼** 읽히게 했다 — 검사받지 않은 수가 검사받은 얼굴로 나왔다.

⇒ 앵커를 못 찾으면 건너뛰지 않고 *크게 실패한다.* 그리고 이 축을 자기
시험에 급여한다 — 자기 시험이 먹이지 않는 축은 수리해도 다시 죽는다.
(6)·(7) 도 같은 규율로 짓는다: 앵커 부재는 통과가 아니라 실패다.

## (6) 은 왜 필요한가

부록 B.5 는 78행 표 하나와 그 표를 *산문으로 요약한* 해설을 함께 싣는다 —
행 수 · 네 부류(해소·파라미터화·조건부·미결) · 미결의 네 갈래 분해 ·
그리고 「다섯에서 여덟이 됐다 — 둘을 닫았는데 …가 새로 열렸다」 부류의
산술. 전부 *파생*이고, 전부 한글 수사로 적혀 있어 눈으로는 더 안 걸린다.
드리프트 목록 5번(「B.5 해설의 산술이 표와 맞지 않았다」)이 정확히 여기서
났는데 검사가 확장되지 않아 *같은 형태가 두 번째로 났다* — 이번엔 위 산술
자신이 `5 - 2 + 4 = 8` 로 틀려 있었다.

## (5) 는 왜 뒤늦게 생겼는가 — 여섯 번째 드리프트

인코딩 개정 파도(W8)가 CH 한 워드를 넣어 최대 길이를 416b/13워드 →
448b/14워드로 옮겼다. 정본은 그 값을 **세 곳**에 적는다 — §1.3.1 규범
「최대 길이」의 산술 · §4.5 「인코딩 용량」의 현행 문장 · 부록 B 원장의
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

## (8) 은 왜 뒤늦게 생겼는가 — 그리고 무엇을 재고 무엇을 안 재는가

부록 D 진행 현황은 run 수 옆에 *모델 수*를 적는다 — 「모델 12개 (색인 속성을
덮는 것; 그 밖에 … 축 모델 셋 Mask · CapWord · MaskEngine 이 있어 `.tla` 는
15편이다)」. (4) 는 run 수만 대조했다. 그래서 파도 셋(Decode `ch_judged` ·
Mask · CapWord · MaskEngine)이 모델을 더하는 동안 run 수는 게이트가 밀었고
모델 수는 아무도 밀지 않아 **세 번 안 움직였다** — 세 렌즈가 같은 자리를
지적했다. 같은 문장 안의 두 수 중 하나만 재면 안 재는 쪽이 낡는다.

원천은 `rtl/formal/tla/` 실물 둘이고, 세 수를 거기서 유도한다:

  · `.tla` 편수 — `rtl/formal/tla/*.tla` 의 glob. (T1)
  · 「색인 속성을 덮는 모델」의 수 — 부록 D D.3 색인에는 「모델」 열이 없어
    색인 쪽에서는 못 센다. 대신 `run.sh` 가 모델마다 `M=<이름>.tla` 절을 열고
    그 절의 `expect_*` 라벨에 덮는 속성 ID 를 적으므로(`"FAB-2 좋은 모델 …"` ·
    `"HIU-1/2/3/4 …"`), **라벨이 색인 속성 ID 를 하나라도 인용하는 절**을
    「색인을 덮는 모델」로 센다. (T3)
  · 축 모델의 이름과 수 — 위의 여집합. 앵커가 이름으로 적는 셋과 *집합*으로
    대조하고, 수사 「셋」도 이름 수와 대조한다. (T4)
  · 그리고 `M=` 집합 == `.tla` 집합을 **양방향**으로 요구한다 — 파일만 있고
    배터리가 안 도는 모델, 배터리만 있고 파일 없는 절, 둘 다 실패다. (T2)

안 재는 것을 적어 둔다. 라벨이 인용한 속성 ID 가 *그 모델이 실제로 증명하는*
속성인지는 재지 않는다 — 라벨은 배터리의 선언이지 증명이 아니고, 증명은
run 자신(가드 삭제 · 증인)이 한다. 색인의 어느 속성이 어느 모델에 덮이는지의
대응표도 재지 않는다 — D.3 에 「모델」 열이 생기면 그때 (1) 과 같은 형태로
잰다. 12 라는 수는 그 대응표의 *행 수*가 아니라 라벨 선언의 *절 수*다.

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
TLADIR = RUNSH.parent
REFS = GUIDE / "refs.yml"
README = GUIDE / "README.md"

PREFIXES = ("ISA", "FAB", "HIU", "EXT", "SEC")
# 색인 속성 ID — run.sh 라벨 안에서 「이 run 이 덮는 속성」을 가리키는 표기.
# `HIU-1/2/3/4` 같은 묶음 표기도 첫 ID 로 잡힌다 (하나면 충분하다).
_PROP_ID = re.compile(r"\b(?:%s)-\d+" % "|".join(PREFIXES))

# 낡은 값을 *역사로* 적을 때 붙어 있어야 하는 표지. 이 목록에 없는 문면으로
# 낡은 값을 적으면 현재 시제 주장으로 간주한다 — 부록 B 원장 칸이 정확히
# 그렇게 틀렸다 (「최대 416비트로 전면 대체됨」은 현재 시제다).
_HISTORICAL = ("이전", "종전", "과거", "이었다", "였다", "개정 전", "옛")


class Drift(Exception):
    """(5) 계열 불일치. 자기 시험이 이것을 잡아 반증력을 확인한다."""


def fail(msg: str) -> None:
    print(f"lint_guide_derived_tables: FAIL — {msg}", file=sys.stderr)
    sys.exit(1)


# --------------------------------------------------------------------------
# 한글 수사 — B.5 요약은 아라비아 숫자를 쓰지 않는다
# --------------------------------------------------------------------------
_KO_TENS = {"아흔": 90, "여든": 80, "일흔": 70, "예순": 60, "쉰": 50,
            "마흔": 40, "서른": 30, "스물": 20, "열": 10}
_KO_ONES = {"하나": 1, "한": 1, "둘": 2, "두": 2, "셋": 3, "세": 3,
            "넷": 4, "네": 4, "다섯": 5, "여섯": 6, "일곱": 7,
            "여덟": 8, "아홉": 9}


def ko_num(word: str) -> int:
    """「일흔여덟」 → 78. 못 읽으면 Drift — 조용히 0 을 돌려주지 않는다."""
    s = word.strip()
    n, matched = 0, False
    if s.startswith("백"):  # 100–199: 「백다섯」 = 105. B.5 표가 백 행을 넘었다.
        n, s, matched = 100, s[1:], True
    for k in sorted(_KO_TENS, key=len, reverse=True):
        if s.startswith(k):
            n, s, matched = n + _KO_TENS[k], s[len(k):], True
            break
    if s:
        for k in sorted(_KO_ONES, key=len, reverse=True):
            if s == k:
                n, matched = n + _KO_ONES[k], True
                s = ""
                break
    if not matched or s:
        raise Drift(f"한글 수사를 읽지 못했다: 「{word}」")
    return n


_KO_ONES_W = {1: "하나", 2: "둘", 3: "셋", 4: "넷", 5: "다섯", 6: "여섯",
              7: "일곱", 8: "여덟", 9: "아홉"}
_KO_TENS_W = {v: k for k, v in _KO_TENS.items()}


def _ko(n: int) -> str:
    """78 → 「일흔여덟」. 자기 시험이 변이를 *문면으로* 만들 때 쓴다."""
    if not 1 <= n <= 199:
        raise Drift(f"한글 수사로 적을 범위 밖: {n}")
    head, n = ("백", n - 100) if n >= 100 else ("", n)
    return head + _KO_TENS_W.get(n // 10 * 10, "") + _KO_ONES_W.get(n % 10, "")


def _break_arith(bgaps_text: str) -> str:
    """B.5 해설 산술의 *우변*만 한 칸 옮긴 변이를 만든다."""
    def sub(m):
        return f"부류는 {m.group(1)}에서 {_ko(ko_num(m.group(2)) + 1)}이 됐다"
    out, n = re.subn(r"부류는 (\S+?)에서 (\S+?)이 됐다", sub, bgaps_text, count=1)
    if n != 1:
        fail("자기 시험이 B.5 산술 문장을 변이시키지 못했다 — 문면이 움직였다")
    return out


def _bracket_cells(body: str):
    """`[...]` 최상위 셀을 순서대로 뽑는다 (중첩 대괄호 허용)."""
    cells, depth, cur = [], 0, []
    for ch in body:
        if ch == "[":
            depth += 1
            if depth == 1:
                cur = []
                continue
        elif ch == "]":
            depth -= 1
            if depth == 0:
                cells.append("".join(cur))
                continue
            if depth < 0:
                raise Drift("B.5 표의 대괄호 짝이 맞지 않는다")
        if depth > 0:
            cur.append(ch)
    if depth != 0:
        raise Drift("B.5 표의 대괄호가 닫히지 않았다")
    return cells


_B5_CATS = ("해소", "파라미터화", "조건부", "미결")


def parse_b5_table(bgaps_text: str):
    """부록 B.5 표를 파싱해 (행 수, 부류별 개수) 를 *세어서* 돌려준다.

    손으로 옮겨 적은 요약을 이 값과 대조한다 — 요약은 파생이고 표가 원천이다.
    """
    sec = bgaps_text.find("== 미결 결정")
    if sec < 0:
        raise Drift("B.5 「미결 결정」 절을 찾지 못했다")
    t = bgaps_text.find("#table(", sec)
    if t < 0:
        raise Drift("B.5 표를 찾지 못했다")
    # 괄호 깊이로 표의 끝을 찾는다.
    depth, end = 0, None
    for i in range(t + len("#table"), len(bgaps_text)):
        c = bgaps_text[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                end = i
                break
    if end is None:
        raise Drift("B.5 표의 괄호가 닫히지 않았다")
    body = bgaps_text[t:end]
    h = body.find("table.header")
    if h < 0:
        raise Drift("B.5 표에 table.header 가 없다 — 열 구조를 확인할 수 없다")
    hdr_end = body.find(")", h)
    cells = _bracket_cells(body[hdr_end:])
    if not cells or len(cells) % 3:
        raise Drift(
            f"B.5 표의 셀 수 {len(cells)} 가 3의 배수가 아니다 — 열이 밀렸다 "
            f"(이 표가 실제로 그렇게 무너진 적이 있다)")
    counts = {c: 0 for c in _B5_CATS}
    for k in range(2, len(cells), 3):
        s = cells[k].strip().lstrip("*")
        for c in _B5_CATS:
            if s.startswith(c):
                counts[c] += 1
                break
        else:
            raise Drift(
                f"B.5 상태 칸이 네 부류 어디에도 들지 않는다: "
                f"{' '.join(cells[k].split())[:80]}")
    return len(cells) // 3, counts


def check_b5_counts(bgaps_text: str):
    """(6) B.5 요약 산문 세 겹을 표 실물과 대조한다."""
    rows, counts = parse_b5_table(bgaps_text)
    flat = re.sub(r"\s+", " ", bgaps_text)

    # --- B1: 「지금 N 이다 — 해소 …, 파라미터화 …, 조건부 …, 미결 …」 ------
    m = re.search(
        r"이 표는 처음 \S+? 항이었고 지금 (\S+?)이다 — "
        r"해소 (\S+?), 파라미터화 (\S+?), 조건부 (\S+?), 미결 (\S+?)\.", flat)
    if m is None:
        raise Drift(
            "B1: B.5 요약 해설의 계수 문장을 찾지 못했다 — 표 행 수와 네 부류를 "
            "적는 유일한 자리다. 문면이 바뀌었으면 이 검사도 함께 옮겨야 한다")
    said_rows = ko_num(m.group(1))
    said = {c: ko_num(m.group(i)) for i, c in enumerate(_B5_CATS, start=2)}
    if said_rows != rows:
        raise Drift(f"B1: B.5 해설은 {said_rows}행, 표 실물은 {rows}행")
    for c in _B5_CATS:
        if said[c] != counts[c]:
            raise Drift(
                f"B1: B.5 해설의 「{c}」 는 {said[c]}, 표 실물은 {counts[c]} "
                f"(실물 전량: {counts})")
    if sum(said.values()) != said_rows:
        raise Drift(
            f"B1: 네 부류 합 {sum(said.values())} != 표 행 수 {said_rows} — "
            f"부류 어디에도 들지 않는 행이 있다는 뜻이다")

    # --- B2: 미결의 넷 갈래 분해 -----------------------------------------
    # 다섯 → 넷 (2026-10-12, 3.10 v1.0 묶음의 RTL 파도 W1 착지): 「재는 일이 남은 것」
    # 부류의 유일한 행(비소유 접근 loud fault 의 후-formal 미증명)이 해소로 옮겨 그
    # 부류가 비었다. 수사는 0 을 적지 못하므로 갈래 자체가 문면에서 빠졌다 — 이 수가
    # 그 구조를 잠근다 (부류가 다시 생기면 함께 올린다).
    # 조사는 앞 수사의 받침이 정한다 — 「서른여덟은」 · 「마흔하나는」. 수가
    # 움직일 때마다 게이트가 *비문을 쓰라고* 요구하지 않도록 둘 다 받는다.
    dec = re.search(r"남은 (\S+?)[은는] 한 부류가 아니다:(.*?)Q5 분석", flat)
    if dec is None:
        raise Drift(
            "B2: 미결 분해 문장(「남은 … 은/는 한 부류가 아니다」)을 찾지 못했다")
    if ko_num(dec.group(1)) != counts["미결"]:
        raise Drift(
            f"B2: 분해 머리는 {ko_num(dec.group(1))}, 표의 미결은 "
            f"{counts['미결']}")
    parts = [ko_num(x) for x in re.findall(r"\*([가-힣]{1,4})\*[은는]", dec.group(2))
             if _is_ko_num(x)]
    if len(parts) != 4:
        raise Drift(
            f"B2: 미결 분해의 갈래가 넷이 아니라 {len(parts)}개로 읽혔다 "
            f"({parts}) — 갈래를 늘리거나 줄였으면 이 수도 함께 움직여야 한다")
    if sum(parts) != counts["미결"]:
        raise Drift(
            f"B2: 미결 분해 합 {'+'.join(map(str, parts))}={sum(parts)} != "
            f"표의 미결 {counts['미결']}")

    # --- B3: 「A 에서 B 가 됐다 — C 를 닫았는데 D 가 새로 열렸다」 ----------
    ar = re.search(
        r"부류는 (\S+?)에서 (\S+?)이 됐다 — (\S+?)을 닫았는데 (\S+?)이 "
        r"새로 열렸다", flat)
    if ar is None:
        raise Drift(
            "B3: 「정본이 스스로 답한다」 부류의 산술 문장을 찾지 못했다 — "
            "드리프트 5번이 난 형태이고, 그래서 문장이 사라지는 것도 실패다")
    a, b, c, d = (ko_num(x) for x in ar.groups())
    if a - c + d != b:
        raise Drift(
            f"B3: B.5 해설의 산술이 스스로 틀렸다 — {a} - {c} + {d} = "
            f"{a - c + d} 인데 {b} 라 적었다")

    # --- B4: 산문 어디에도 표 행 수의 대조되지 않는 사본을 두지 않는다 ------
    # B1 은 요약 해설 *한 문장*만 앵커로 잡는다. 그 문장 밖에 「78행 계수에
    # 서는 …」 같은 사본이 서면 검사가 닿지 않고, 실제로 행을 79 로 만든
    # 커밋이 그 사본을 78 로 남겼다. ⇒ B.5 절 안의 모든 「N행」을 센 값과
    # 대조한다. 예외는 *소스 줄 번호*뿐이고, 그것은 파일 경로나 「파일」이
    # 앞에 붙어 있어야 한다 — 예외의 자격을 문면이 스스로 증명하게 한다.
    sec = bgaps_text.find("== 미결 결정")
    b5_body = bgaps_text[sec:]
    src_ref = re.compile(r"(?:`[^`]*\.(?:scala|py|sv|v|tla|typ|md)`|파일)[^`]{0,40}$",
                         re.S)
    for m in re.finditer(r"(?<![\d–~-])(\d+)행", b5_body):
        if src_ref.search(b5_body[max(0, m.start() - 60):m.start()]):
            continue  # 소스 줄 번호 — 이 표의 계수가 아니다
        if int(m.group(1)) != rows:
            ctx = " ".join(
                b5_body[max(0, m.start() - 60):m.end() + 40].split())
            raise Drift(
                f"B4: B.5 산문이 「{m.group(0)}」 이라 적는데 표 실물은 "
                f"{rows}행이다 — 계수를 옮길 때는 기계로 다시 센다: …{ctx}…")

    return (f"B.5 {rows}행 = " +
            " · ".join(f"{c} {counts[c]}" for c in _B5_CATS) +
            f" · 미결 분해 {'+'.join(map(str, parts))}" +
            f" · 해설 산술 {a}-{c}+{d}={b}"), rows, counts


def _is_ko_num(word: str) -> bool:
    try:
        ko_num(word)
    except Drift:
        return False
    return True


def check_stage_split(dtext: str, n_pre: int, n_post: int) -> None:
    """(3) 부록 D 단계별 분류 — 그리고 그 수의 *모든* 사본.

    이 축은 도입 이래 매치가 `None` 이어서 한 번도 돌지 않았다. 그래서
    *못 찾는 것 자체가 실패*다 — 조용히 건너뛰면 인쇄되는 「선 n/후 m」이
    자기가 센 값이 되어 대조한 척한다.

    그리고 자리를 *하나만* 잡으면 안 된다. 이 축을 살린 바로 그 수리가
    같은 파일에 선-formal 수의 대조되지 않는 사본을 둘 더 낳았다 — 살아난
    검사가 D.2 한 문장만 보고 있었기 때문이다. 사본이 생길 수 있는 문면
    형태를 표로 들고, 형태마다 *적어도 하나*를 요구한다 (문면이 사라지는
    것도 실패다).
    """
    # (정규식, 사람이 읽는 이름, 이 문면이 적는 수 — "pre" 또는 "pre_post")
    forms = (
        (r"선-formal\s+\*?(\d+)\*?\s*·\s*후-formal\s+\*?(\d+)\*?",
         "D.2 단계별 분류 「선-formal N · 후-formal M」", "pre_post"),
        (r"선-formal 대상\s+\*?(\d+)\*?\s*건",
         "D.2 진행 현황의 분모 「선-formal 대상 N건」", "pre"),
    )
    for pat, label, kind in forms:
        found = list(re.finditer(pat, dtext))
        if not found:
            raise Drift(
                f"S1: 부록 D 에서 {label} 문면을 찾지 못했다. 이 축은 정규식이 "
                f"문면과 안 맞아 도입 이래 조용히 건너뛴 전력이 있다 — 못 찾으면 "
                f"통과가 아니라 실패다")
        for m in found:
            s_pre = int(m.group(1))
            if s_pre != n_pre:
                raise Drift(
                    f"S1: {label} 가 선 {s_pre} 라 적는데 실물은 선 {n_pre} 다")
            if kind == "pre_post" and int(m.group(2)) != n_post:
                raise Drift(
                    f"S1: {label} 가 후 {int(m.group(2))} 라 적는데 실물은 "
                    f"후 {n_post} 다")


# 날짜가 박힌 *실측 기록* 문단의 머리. 이 문단들은 「그날 무엇을 쟀는가」의
# 로그이지 현재 상태의 요약이 아니다 — 아래 R2 가 게이트 앵커를 이 안에
# 두는 것을 금한다.
_DATED_RECORD_HEAD = re.compile(r"^재?실측[^\n(]*\(\d{4}-\d{2}-\d{2}\)", re.M)


def _dated_record_spans(readme_text: str):
    """날짜 박힌 실측 기록 문단의 (시작, 끝) 목록. 문단은 빈 줄로 끝난다."""
    spans = []
    for m in _DATED_RECORD_HEAD.finditer(readme_text):
        end = readme_text.find("\n\n", m.end())
        spans.append((m.start(), len(readme_text) if end < 0 else end))
    return spans


def check_readme_copies(readme_text, n_declared, n_pre, n_post, n_refs) -> str:
    """(7) README 가 인용하는 수 — 그것이 *사본*이면 게이트 안에 넣는다.

    README 는 「남은 수(속성 · 서지)는 **기계가 대조한다**」 고 적었는데
    서지 수는 실제로 아무도 세지 않았고 이미 46 vs 45 로 어긋나 있었다.
    쪽수는 「세는 것이 기계에 없으면 적지 않는 편이 낫다」로 지웠지만, 이 둘은
    지우는 대신 *주장을 참으로 만드는* 쪽을 골랐다 — 재구현자가 README 만
    읽고 규모를 가늠하는 자리이고, 세는 일이 파일 하나 파싱이면 지울 이유가
    없다. 대신 그 주장을 문면 그대로 집행한다.

    ## R2 — 앵커를 날짜 박힌 기록 안에 두지 않는다

    이 축의 첫 판이 그 규율 없이 서서 곧바로 사고를 냈다. 앵커 둘이
    「재실측 (2026-08-27)」 문단 안에 있었고, 그날 실물은 서지 *45* 였다.
    수가 46 이 되자 게이트를 통과시키는 유일한 방법이 **그날의 기록을 46 으로
    고치는 것**이었고 그렇게 됐다 — 게이트가 「그날 재지 않은 값을 그날 잰
    것으로 적어라」를 강제한 것이다. 그리고 서지가 늘 때마다 같은 위조를
    다시 요구한다.

    ⇒ 현재 시제 주장(문서 지도의 괄호 · 「남은 수」)만 앵커로 삼고, 날짜
    박힌 문단 안에 앵커가 들어오면 *실패한다.* 로그는 고치는 것이 아니라
    새 줄을 더하는 것이다.
    """
    checks = (
        (rf"\({n_declared}개 색인 — 선 {n_pre} / 후 {n_post}\)",
         f"부록 D 인용 「({n_declared}개 색인 — 선 {n_pre} / 후 {n_post})」"),
        (rf"\({n_refs}항, 전부 본문 인용\)", f"refs.yml 인용 「({n_refs}항…)」"),
        (rf"남은 수\(속성 {n_declared} · 서지 {n_refs}\)",
         f"「남은 수(속성 {n_declared} · 서지 {n_refs})」"),
    )
    spans = _dated_record_spans(readme_text)
    for pat, label in checks:
        m = re.search(pat, readme_text)
        if m is None:
            raise Drift(
                f"R1: README 의 {label} 가 실물과 어긋난다 (실물: 속성 "
                f"{n_declared} = 선 {n_pre} + 후 {n_post} · 서지 {n_refs}항). "
                f"README 는 이 수들을 「기계가 대조한다」고 적으므로, 대조에서 "
                f"빠지는 순간 그 문장 자신이 거짓이 된다")
        for lo, hi in spans:
            if lo <= m.start() < hi:
                raise Drift(
                    f"R2: 게이트 앵커 {label} 가 날짜 박힌 실측 기록 안에 있다. "
                    f"그러면 수가 움직일 때마다 게이트가 *그날 재지 않은 값을 "
                    f"그날 잰 것으로* 고치라고 요구한다 — 실제로 그렇게 서지 "
                    f"45 가 46 으로 사후 수정됐다. 앵커는 현재 시제 주장에만 "
                    f"두고, 기록은 고치지 말고 줄을 더하라")
    return (f"README 인용 정합 (속성 {n_declared} · 선 {n_pre}/후 {n_post} · "
            f"서지 {n_refs} · 앵커가 날짜 기록 {len(spans)}건 밖)")


def count_refs(refs_text: str) -> int:
    """`refs.yml` 최상위 키 = 서지 항 수."""
    n = len(re.findall(r"^[A-Za-z0-9_.:+-]+:\s*$", refs_text, re.M))
    if n == 0:
        raise Drift("refs.yml 에서 서지 항을 하나도 찾지 못했다")
    return n


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

    # --- L2: §4.5 「인코딩 용량」의 현행 문장 ------------------------------
    sect = re.search(r"^== 인코딩 용량(.*?)(?=^== )", ext_text, re.S | re.M)
    if sect is None:
        raise Drift("L2: §4.5 「인코딩 용량」 절을 찾지 못했다")
    body = sect.group(1)
    if f"{bits}비트" not in body:
        raise Drift(
            f"L2: §4.5 이 현행 최대 길이 {bits}비트를 적지 않는다 — 여기가 "
            f"「이전 값 → 현행 값」을 나란히 적는 유일한 자리다")
    if f"*{words}워드*" not in body:
        raise Drift(
            f"L2: §4.5 이 도달 가능 최대 *{words}워드*를 적지 않는다 — "
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

    # --- L5: 이 축을 가리키는 *절 번호* 자신이 맞는가 ----------------------
    # 위 L2 는 「인코딩 용량」 절을 제목으로 연다 — 번호는 쓰지 않는다. 그래서
    # 산문이 그 절을 §4.6 으로 잘못 가리켜도 L2 는 조용했고, `lint_section_refs`
    # 도 조용했다 (4.6 은 실재하는 좌표 — 「형식 속성」 — 이라 좌표 실재성
    # 검사를 통과한다). 그 오기가 이 스크립트의 메시지에서 원장으로, 원장에서
    # README 로 세 자리를 번졌다. ⇒ 번호를 *센다*.
    enc = _enc_section_number(ext_text)
    for name, text in sweep:
        flat = re.sub(r"\s+", " ", text)
        for m in re.finditer(r"(?<![\d.])4\.(\d+)(?![\d.])", flat):
            win = flat[max(0, m.start() - 120):m.end() + 120]
            if "최대 길이" not in win and "인코딩 용량" not in win:
                continue
            if int(m.group(1)) == enc:
                continue
            # 낡은/틀린 번호를 *역사로* 적는 것은 이 부록의 일이다 (B.5 는
            # 자기 오기의 기록을 싣는다). L4 와 같은 규율을 쓴다 — 금지가
            # 아니라 *표지 강제*: 그 자리에서 역사라고 말해야 한다.
            if any(h in win for h in _HISTORICAL):
                continue
            raise Drift(
                f"L5: {name} 이 명령어 최대 길이의 근거 절을 「4.{m.group(1)}」 "
                f"로 가리키는데 「인코딩 용량」은 4장의 {enc}번째 절 = "
                f"§4.{enc} 다. 좌표가 실재하기만 하면 통과하는 참조 검사는 "
                f"이 부류를 잡지 못한다 — 번호를 세는 것이 유일한 그물이다. "
                f"종전 오기를 역사로 적는 것이면 그 자리에서 역사라고 말하라 "
                f"(표지 {list(_HISTORICAL)[:3]} 중 하나): …{win.strip()[:140]}…")

    return (f"명령어 최대 길이 {bits}b/{words}워드 정합 "
            f"(규범·§4.{enc}·부록 B · 스윕 {len(sweep)}건)")


def _enc_section_number(ext_text: str) -> int:
    """4장에서 「인코딩 용량」이 몇 번째 `==` 절인가 — 곧 §4.N 의 N."""
    heads = re.findall(r"^== (.+)$", ext_text, re.M)
    idx = [i for i, h in enumerate(heads, start=1) if h.startswith("인코딩 용량")]
    if len(idx) != 1:
        raise Drift(
            f"L5: 4장에서 「인코딩 용량」 절을 정확히 하나 찾지 못했다 "
            f"({len(idx)}개) — 절 번호를 셀 수 없으면 아래 대조가 공허하다")
    return idx[0]


# (8) 의 앵커 — 부록 D 진행 현황 한 문장. 세 수(색인을 덮는 모델 수 · 축 모델
# 수사 · `.tla` 편수)와 축 모델 이름들이 한 괄호 안에 산다. 괄호 안의 서술
# (「저장·워드·엔진 창의」)은 축 모델이 늘 때마다 바뀌므로 결속하지 않는다.
_TLA_ANCHOR = re.compile(
    r"모델 (\d+)개 \(색인 속성을 덮는 것;[^()]{0,200}?축 모델 (\d+|[가-힣]+) "
    r"((?:[A-Za-z_]\w* · )*[A-Za-z_]\w*) 이 있어 `\.tla` 는 (\d+)편이다\)")


def runsh_models(runsh_text: str) -> dict:
    """run.sh 의 모델 절 → 「그 절의 expect_* 라벨이 색인 속성 ID 를 인용하는가」.

    `M=<이름>.tla` 가 절을 열고, 그 아래 `expect_*` 호출의 첫 인자(라벨)가 그
    절의 run 들이다. 라벨에 색인 속성 ID 가 하나라도 있으면 *색인 속성을 덮는*
    모델, 하나도 없으면 축 모델이다 — 라벨은 배터리가 스스로 적은 선언이고
    이 함수는 그 선언을 센다. 어느 절에도 속하지 않는 run · 못 읽는 라벨 ·
    절의 중복은 전부 Drift 다: 조용히 빠지면 모델 하나가 계수에서 사라진다.
    """
    covers: dict = {}
    cur = None
    for ln, line in enumerate(runsh_text.splitlines(), start=1):
        m = re.match(r"^M=([A-Za-z_]\w*)\.tla\s*$", line)
        if m:
            cur = m.group(1)
            if cur in covers:
                raise Drift(
                    f"T2: run.sh:{ln} 이 M={cur}.tla 절을 두 번 연다 — 모델 "
                    f"하나를 두 번 세거나 절 경계를 잘못 읽는다")
            covers[cur] = False
            continue
        if not re.match(r"^expect_(?:pass|fail)[ \t]", line):
            continue  # 정의 줄(`expect_pass() {`)과 무관한 줄
        e = re.match(r'^expect_(?:pass|fail)[ \t]+"([^"]*)"', line)
        if e is None:
            raise Drift(
                f"T2: run.sh:{ln} 의 expect_* 라벨을 읽지 못했다 — 라벨은 같은 "
                f"줄의 첫 따옴표 인자여야 (8) 이 셀 수 있다")
        if cur is None:
            raise Drift(
                f"T2: run.sh:{ln} 의 run 이 어느 M= 절에도 속하지 않는다 — 그 "
                f"run 의 모델은 (8) 이 세지 못한다")
        if _PROP_ID.search(e.group(1)):
            covers[cur] = True
    if not covers:
        raise Drift(
            "T2: run.sh 에서 M=<이름>.tla 절을 하나도 찾지 못했다 — 모델 집합의 "
            "원천이 사라졌다")
    return covers


def check_tla_models(dtext: str, tla_names, runsh_text: str) -> str:
    """(8) 부록 D 진행 현황의 모델 수 — 원천은 `rtl/formal/tla/` 실물 둘.

    T1  「`.tla` 는 N편」               == `rtl/formal/tla/*.tla` 편수
    T2  run.sh 의 `M=` 집합            == 그 `.tla` 집합 (양방향)
    T3  「모델 N개 (색인 속성을 …)」     == 라벨이 색인 속성 ID 를 인용하는 절 수
    T4  「축 모델 <수사> A · B · C」     == 그 여집합 (이름 집합과 수사 둘 다)

    앵커 부재는 통과가 아니라 실패다 — (3) 의 규율 그대로. 머리말 「(8) 은
    무엇을 재고 무엇을 안 재는가」가 이 넷의 정의역과 그 밖을 적는다.
    """
    tla = set(tla_names)
    flat = re.sub(r"\s+", " ", dtext)
    m = _TLA_ANCHOR.search(flat)
    if m is None:
        raise Drift(
            "T1: 부록 D 진행 현황에서 모델 수 앵커 「모델 N개 (색인 속성을 덮는 "
            "것; … 축 모델 <수사> A · B 이 있어 `.tla` 는 N편이다)」 를 찾지 "
            "못했다. 파도 셋이 모델을 더하는 동안 이 수가 세 번 안 움직였고 "
            "그때 검사가 없었다 — 문면이 바뀌었으면 이 검사도 함께 옮겨야 "
            "하고, 못 찾으면 통과가 아니라 실패다")
    said_idx, numeral = int(m.group(1)), m.group(2)
    names, said_files = m.group(3).split(" · "), int(m.group(4))
    said_axis = int(numeral) if numeral.isdigit() else ko_num(numeral)
    if said_files != len(tla):
        raise Drift(
            f"T1: 부록 D 는 `.tla` {said_files}편이라 적는데 실물 "
            f"rtl/formal/tla/*.tla 는 {len(tla)}편이다 ({sorted(tla)})")
    covers = runsh_models(runsh_text)
    if set(covers) != tla:
        raise Drift(
            f"T2: run.sh 의 M= 집합과 .tla 실물이 다르다 — 파일만 있고 배터리가 "
            f"안 도는 모델 {sorted(tla - set(covers))} · 배터리만 있고 파일이 "
            f"없는 모델 {sorted(set(covers) - tla)}")
    idx_models = sorted(n for n, c in covers.items() if c)
    axis_models = sorted(n for n, c in covers.items() if not c)
    if said_idx != len(idx_models):
        raise Drift(
            f"T3: 부록 D 는 색인 속성을 덮는 모델 {said_idx}개라 적는데 run.sh "
            f"라벨이 색인 속성 ID 를 인용하는 절은 {len(idx_models)}개다 "
            f"({idx_models})")
    if said_axis != len(names):
        raise Drift(
            f"T4: 축 모델 수사 「{numeral}」({said_axis}) 와 나열된 이름 "
            f"{len(names)}개 ({names}) 가 다르다")
    if set(names) != set(axis_models) or len(set(names)) != len(names):
        raise Drift(
            f"T4: 부록 D 가 축 모델로 적은 {names} 와 run.sh 라벨이 색인 속성 "
            f"ID 를 인용하지 않는 절 {axis_models} 가 다르다")
    return (f"선-formal 모델 {len(tla)}편 정합 (.tla = run.sh M= · 색인 덮음 "
            f"{len(idx_models)} + 축 모델 {' · '.join(names)})")


def _strip_ids_in_section(runsh_text: str, name: str) -> str:
    """run.sh 의 `M=<name>.tla` 절 라벨에서 색인 속성 ID 를 지운 변이를 만든다."""
    out, cur, n = [], None, 0
    for line in runsh_text.splitlines(keepends=True):
        m = re.match(r"^M=([A-Za-z_]\w*)\.tla\s*$", line)
        if m:
            cur = m.group(1)
        elif cur == name and re.match(r"^expect_(?:pass|fail)[ \t]", line):
            line, k = _PROP_ID.subn("X", line)
            n += k
        out.append(line)
    if n == 0:
        fail(f"자기 시험이 run.sh {name} 절의 라벨을 변이시키지 못했다 — 문면이 "
             f"움직였다")
    return "".join(out)


def _self_test(isa_text, ext_text, bgaps_text, sweep, words, bits,
               dtext, readme_text, n_declared, n_pre, n_post, n_refs,
               tla_names, runsh_text):
    """이 검사가 무엇을 배제하는지 매 실행마다 증명한다.

    변이를 먹여 전부 Drift 가 나야 한다. 하나라도 조용하면 그 결은
    검사되지 않는 것이고, 검사되지 않는 결은 다음 파도에서 다시 낡는다.

    (3)·(6)·(7)·(8) 이 여기 급여되는 이유는 (3) 이 *바로 그것이 없어서* 도입
    이래 죽어 있었기 때문이다. 자기 시험이 먹이지 않는 축은 수리해도 다시
    죽는다.
    """
    def must_raise(label, fn):
        try:
            fn()
        except Drift:
            return
        fail(f"자기 시험 실패 — 변이 「{label}」 를 이 검사가 잡지 못한다")

    # 변이 시험은 *기준 문면이 통과할 때만* 뜻이 있다. 기준이 이미 깨져 있으면
    # 모든 변이가 엉뚱한 이유로 울고 자기 시험은 공허하게 초록이 된다 — (3) 이
    # 죽어 있던 것과 같은 부류의 공허함이다. 그래서 기준을 먼저 통과시키고,
    # 실패하면 그 Drift 를 그대로 올려보낸다 (호출부가 크게 운다).
    check_stage_split(dtext, n_pre, n_post)
    check_b5_counts(bgaps_text)
    check_readme_copies(readme_text, n_declared, n_pre, n_post, n_refs)
    check_tla_models(dtext, tla_names, runsh_text)

    # --- (3) 단계별 분류 -------------------------------------------------
    must_raise("단계별 분류 앵커 삭제 (도입 이래 죽어 있던 결)",
               lambda: check_stage_split(
                   dtext.replace("선-formal", "선"), n_pre, n_post))
    must_raise("단계별 분류의 선 수를 어긋나게",
               lambda: check_stage_split(dtext, n_pre + 1, n_post))
    must_raise("단계별 분류의 후 수를 어긋나게",
               lambda: check_stage_split(dtext, n_pre, n_post + 1))
    # 이 축을 살린 수리가 *같은 파일에* 대조 안 되는 사본을 둘 낳았다 —
    # 자리 하나만 잡는 것으로는 부족하다는 것이 실측으로 드러난 결이다.
    must_raise("D.2 진행 현황의 분모(선-formal 대상 N건)를 어긋나게",
               lambda: check_stage_split(
                   dtext.replace(f"선-formal 대상 {n_pre}건",
                                 f"선-formal 대상 {n_pre - 1}건"),
                   n_pre, n_post))
    must_raise("D.2 진행 현황의 분모 문면 삭제",
               lambda: check_stage_split(
                   dtext.replace("선-formal 대상", "형식화 대상"),
                   n_pre, n_post))

    # --- (6) B.5 계수 ----------------------------------------------------
    _rows, _counts = parse_b5_table(bgaps_text)
    must_raise("B.5 요약의 행 수를 어긋나게",
               lambda: check_b5_counts(bgaps_text.replace(
                   f"지금 {_ko(_rows)}이다", f"지금 {_ko(_rows + 1)}이다")))
    must_raise("B.5 요약의 부류 하나를 어긋나게",
               lambda: check_b5_counts(bgaps_text.replace(
                   f"해소 {_ko(_counts['해소'])},",
                   f"해소 {_ko(_counts['해소'] + 1)},")))
    must_raise("B.5 요약 계수 문장 삭제",
               lambda: check_b5_counts(bgaps_text.replace(
                   "이 표는 처음", "이 표는 예전에")))
    must_raise("B.5 미결 분해 갈래 하나를 어긋나게",
               lambda: check_b5_counts(bgaps_text.replace(
                   "*넷*은 아래에서 새로 만든 부류", "*다섯*은 아래에서 새로 만든 부류")))
    must_raise("B.5 미결 분해 문장 삭제",
               lambda: check_b5_counts(bgaps_text.replace(
                   "한 부류가 아니다:", "한 부류가 아닐 수도 있다:")))
    must_raise("B.5 해설 산술의 우변을 깨뜨림",
               lambda: check_b5_counts(_break_arith(bgaps_text)))
    must_raise("B.5 표의 상태 칸을 네 부류 밖으로",
               lambda: check_b5_counts(bgaps_text.replace(
                   "[*미결* — 정본 자답 가능]", "[*검토중* — 정본 자답 가능]", 1)))
    # B4 — 요약 문장 *밖*의 행 수 사본. 실제로 표를 79 로 만든 커밋이 산문의
    # 「78행 계수」를 그대로 두었고 B1 은 그 자리에 닿지 않았다.
    must_raise("B.5 산문의 행 수 사본을 어긋나게",
               lambda: check_b5_counts(bgaps_text.replace(
                   f"{_rows}행 계수", f"{_rows + 1}행 계수")))

    # --- (7) README 사본 --------------------------------------------------
    for lbl, mut in (
        ("README 의 속성 총수", (f"({n_declared}개 색인", f"({n_declared + 1}개 색인")),
        ("README 의 선/후 분할", (f"선 {n_pre} / 후 {n_post})", f"선 {n_pre + 1} / 후 {n_post})")),
        ("README 의 서지 항 수", (f"({n_refs}항, 전부", f"({n_refs - 1}항, 전부")),
        ("README 의 「남은 수」 괄호", (f"서지 {n_refs})", f"서지 {n_refs - 1})")),
    ):
        must_raise(lbl, (lambda m: lambda: check_readme_copies(
            readme_text.replace(*m), n_declared, n_pre, n_post, n_refs))(mut))
    # R2 — 앵커가 날짜 박힌 기록 안으로 들어오는 변이. 이것이 조용하면 게이트가
    # 다음 파도에서 다시 「그날 재지 않은 값을 그날 잰 것으로」 고치게 만든다.
    must_raise(
        "게이트 앵커를 날짜 박힌 실측 기록 안으로 옮김",
        lambda: check_readme_copies(
            f"재실측 (2026-08-27): 남은 수(속성 {n_declared} · 서지 {n_refs}) 확인,\n"
            f"부록 D 색인 ({n_declared}개 색인 — 선 {n_pre} / 후 {n_post}),\n"
            f"서지 ({n_refs}항, 전부 본문 인용).\n\n",
            n_declared, n_pre, n_post, n_refs))

    # --- (5) 명령어 최대 길이 --------------------------------------------
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
        ("§4.5 현행 문장을 개정 전 값으로",
         (isa_text, ext_text.replace(f"{bits}비트", f"{old_bits}비트"),
          bgaps_text, sweep)),
        ("부록 B 원장 칸에서 현행 값 삭제",
         (isa_text, ext_text,
          bgaps_text.replace(f"최대 {bits}비트", "최대 여러 비트"), sweep)),
        ("표지 없는 낡은 값 삽입",
         (isa_text, ext_text, bgaps_text,
          sweep + [("(변이 문서)",
                    f"상한은 {old_words}워드 · 최대 {old_bits}비트다.")])),
        # L5 — 절 *번호*의 오기. 좌표가 실재하면 참조 검사는 조용하고, 이
        # 오기는 실제로 lint 메시지 → 원장 → README 로 세 자리를 번졌다.
        ("근거 절 번호를 이웃 절로 오기",
         (isa_text, ext_text, bgaps_text,
          sweep + [("(변이 문서)",
                    "명령어 최대 길이의 근거는 @sec:extpayload 4.9 다.")])),
        ("「인코딩 용량」 절 제목 삭제 — 번호를 셀 수 없게",
         (isa_text, ext_text.replace("== 인코딩 용량", "== 용량"),
          bgaps_text, sweep)),
    ]
    for label, (i, e, b, s) in cases:
        try:
            check_length_claims(i, e, b, s, words, bits)
        except Drift:
            continue
        fail(
            f"자기 시험 실패 — 변이 「{label}」 를 이 검사가 잡지 못한다. "
            f"(5) 는 그만큼 공허하다")

    # --- (8) 선-formal 모델 수 --------------------------------------------
    # 변이는 앵커 *문장 안*에서만 만든다 — 같은 이름·수가 부록 D 의 다른
    # 자리(run 수 문장의 「Mask 축 10 run」)에도 살기 때문이다. 기준 대조가
    # 위에서 통과했으므로 앵커는 있다; 없는 문면을 바꾸는 헛변이는 그 자리에서
    # 실패다 (조용히 안 먹은 변이는 「검사가 못 잡는다」로 오독된다).
    flat = re.sub(r"\s+", " ", dtext)
    am = _TLA_ANCHOR.search(flat)
    if am is None:
        fail("자기 시험이 (8) 앵커를 다시 찾지 못했다 — 기준 대조와 어긋난다")
    n_tla, covers = len(tla_names), runsh_models(runsh_text)
    n_idx = sum(covers.values())
    numeral, names = am.group(2), am.group(3).split(" · ")

    def anchored(old, new):
        a = am.group(0)
        if old not in a:
            fail(f"자기 시험이 (8) 앵커를 변이시키지 못했다 — 「{old}」 가 "
                 f"앵커 문면에 없다")
        return flat[:am.start()] + a.replace(old, new, 1) + flat[am.end():]

    for lbl, d, t, r in (
        ("`.tla` 편수를 하나 적게 (15 → 14 부류)",
         anchored(f"{n_tla}편", f"{n_tla - 1}편"), tla_names, runsh_text),
        ("모델 수 앵커 문면 삭제",
         anchored("`.tla` 는", "`.tla` 파일은"), tla_names, runsh_text),
        (".tla 를 하나 더한 척 (실물이 문면보다 많다)",
         flat, set(tla_names) | {"Ghost"}, runsh_text),
        ("편수는 맞춰 적었지만 run.sh 가 그 .tla 를 돌리지 않음",
         anchored(f"{n_tla}편", f"{n_tla + 1}편"),
         set(tla_names) | {"Ghost"}, runsh_text),
        ("run.sh 에 실물 없는 M= 절 추가",
         flat, tla_names, runsh_text + "\nM=Ghost.tla\n"),
        ("색인 속성을 덮는 모델 수를 하나 많게",
         anchored(f"모델 {n_idx}개", f"모델 {n_idx + 1}개"),
         tla_names, runsh_text),
        ("run.sh 한 절의 라벨에서 속성 ID 를 지움 (색인 모델이 축 모델로)",
         flat, tla_names,
         _strip_ids_in_section(runsh_text,
                               next(n for n, c in covers.items() if c))),
        ("축 모델 수사를 어긋나게 (셋 → 넷 부류)",
         anchored(f"축 모델 {numeral} ", f"축 모델 {_ko(len(names) + 1)} "),
         tla_names, runsh_text),
        ("축 모델 이름 하나를 실물에 없는 이름으로",
         anchored(f" {names[0]} ", " Ghost "), tla_names, runsh_text),
        ("축 모델 이름 하나를 뺌 (수사는 그대로)",
         anchored(f"{names[0]} · ", ""), tla_names, runsh_text),
    ):
        must_raise(lbl, (lambda d, t, r: lambda: check_tla_models(d, t, r))(d, t, r))


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
    # 매치 실패는 *실패*다. `if stage:` 로 건너뛰던 판이 도입 이래 한 번도
    # 돌지 않았고, 그러면서 아래 OK 줄이 자기가 센 값을 인쇄해 대조한 척했다.

    # --- 파생 (4): 진행 현황의 run 수 vs run.sh --------------------------
    if not RUNSH.is_file():
        fail(f"형식 배터리가 없다: {RUNSH}")
    # 호출만 센다. `expect_pass() {` 같은 *정의* 줄은 제외해야 한다 —
    # 처음 판은 `\b` 로 끝내서 정의 둘을 함께 세었고, 이 검사 자신이
    # 2 만큼 어긋난 수를 보고했다. 파생 표를 지키는 검사도 파생이다.
    runsh_text = RUNSH.read_text(encoding="utf-8")
    runs = len(re.findall(r"^expect_(?:pass|fail)[ \t]", runsh_text, re.M))
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

    # --- 파생 (8): 모델 수 vs rtl/formal/tla 실물 --------------------------
    # 편수의 원천은 glob 이고 절 수의 원천은 위에서 읽은 run.sh 다. 대조 자체는
    # check_tla_models 가 하고, 그 전에 자기 시험이 반증력을 증명한다.
    tla_names = {p.stem for p in TLADIR.glob("*.tla")}
    if not tla_names:
        fail(f"선-formal 모델이 하나도 없다: {TLADIR}/*.tla — (8) 의 원천이 "
             f"사라졌다")

    # --- 파생 (5): 명령어 최대 길이 주장 ---------------------------------
    if not ASM.is_file():
        fail(f"어셈블러가 없다: {ASM} — 명령어 길이의 원천이다")
    isa_p = GUIDE / "chapters" / "01-isa-asm.typ"
    ext_p = GUIDE / "chapters" / "04-ext-payload.typ"
    for p in (isa_p, ext_p):
        if not p.is_file():
            fail(f"정본 장이 없다: {p}")
    read = lambda p: p.read_text(encoding="utf-8")
    # README 도 스윕에 든다. 빠져 있던 동안 §4.6 오기가 *바로 그 파일로*
    # 번졌고 (lint 메시지 → 원장 → README), 음성 시험이 그 구멍을 드러냈다 —
    # 원장 쪽 변이는 잡히는데 README 쪽 같은 변이는 조용했다. 파생을 지키는
    # 검사가 파생이 사는 파일을 안 읽으면 그만큼 공허하다.
    sweep = [(str(p.relative_to(ROOT)), read(p))
             for p in sorted(GUIDE.glob("chapters/*.typ"))
             + sorted(GUIDE.glob("appendix/*.typ"))
             + sorted(EXTDOCS.glob("*.md"))
             + [GUIDE / "README.md"]]
    isa_text, ext_text = read(isa_p), read(ext_p)
    bgaps_text = read(GUIDE / "appendix" / "b-gaps.typ")
    for p in (REFS, README):
        if not p.is_file():
            fail(f"정본 파일이 없다: {p}")
    refs_text, readme_text = read(REFS), read(README)
    try:
        words, bits = _asm_length_constants(read(ASM))
        n_refs = count_refs(refs_text)
        # 매 실행마다 반증력을 먼저 증명하고, 그 다음에 실물을 잰다.
        _self_test(isa_text, ext_text, bgaps_text, sweep, words, bits,
                   dtext, readme_text, n_declared, n_pre, n_post, n_refs,
                   tla_names, runsh_text)
        check_stage_split(dtext, n_pre, n_post)
        b5_note, _b5_rows, _b5_counts = check_b5_counts(bgaps_text)
        readme_note = check_readme_copies(readme_text, n_declared, n_pre,
                                          n_post, n_refs)
        length_note = check_length_claims(isa_text, ext_text, bgaps_text,
                                          sweep, words, bits)
        tla_note = check_tla_models(dtext, tla_names, runsh_text)
    except Drift as exc:
        fail(str(exc))

    print(
        f"lint_guide_derived_tables: OK — 속성 {n_declared}건 "
        f"(선 {n_pre} / 후 {n_post} — 부록 D 문면과 대조) · 부록 D 색인 {n_index}건 정합"
        + f" · 축별 (a){axes['a']}/(b){axes['b']}/(c){axes['c']} 합계 정합"
        + f" · 형식 배터리 {runs} run 정합"
        + f" · {b5_note}"
        + f" · {readme_note}"
        + f" · {length_note}"
        + f" · {tla_note}"
    )


if __name__ == "__main__":
    main()
