#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""정본 **절 번호 인용**의 실재성 검사.

## 왜 이 검사가 있는가

2026-08-27 실측 — 정본이 토큰 비증식 규범(ISA-9)을 **§1.4.6 으로 가리키는
자리가 열두 곳**이었다. 실제 자리는 §1.4.2 이고 §1.4.6 은 「OPREF 의 포트
인덱스 — 폐지」다. **그중 여섯은 하루 사이에 생겼다** — 그 규범을 개정하던
사람이 개정하면서 틀린 번호를 새로 여섯 번 적었다.

같은 날 두 번째 사례도 나왔다: `01-isa-asm.typ` 이 「순회를 멈추는 것이
아니라 효과를 멈춘다」를 §4.3 이 적은 것으로 인용했는데 그 문장은 §4.2.1 에
산다. 같은 파도의 `b-gaps.typ` 은 4.2.1 로 옳게 인용했다 — **정본이 같은
문장을 두 절 번호로 불렀다.**

근본 원인은 오탈자가 아니라 **배치**다. 한 절의 제목이 그 절이 담은 규범을
예고하지 않으면(ISA-9 는 「입력 포트 마스크 — 폐지」라는 제목의 절 안에 산다)
인용하는 쪽은 번호를 *확인하지 않고 짐작한다.* 그리고 절은 문서를 고칠 때마다
움직인다.

정본이 재구현의 유일한 기준인데 그 기준이 자기 안에서 어긋난 좌표를 가리키면,
그것을 밟는 쪽은 기준을 따랐다고 말할 수 있다.

## 무엇을 재는가 — 셋

1. **장 라벨이 실재하는가** — `@sec:xxx` 의 `xxx` 가 선언된 라벨인가.
2. **그 절 번호가 실재하는가** — `@sec:isa 1.4.2` 에서 1장에 §1.4.2 가 있는가.
   장 번호가 라벨이 사는 파일의 장 번호와 같은가 (`@sec:isa 2.3` 은 틀렸다).
3. **인용에 딸린 따옴표 내용이 그 절 안에 있는가** ← **이 검사의 알맹이**.
   「§4.3 이 적은 「순회를 멈추는 것이 아니라…」」에서 그 문장이 §4.3 범위 밖에
   있으면 잡는다. 1·2 만으로는 「실재하는 엉뚱한 절」을 가리키는 것을 못 잡고,
   위 두 실측 사례가 **전부 그 부류**다.

## 사각지대 하나를 실제로 밟았다 (2026-08-27)

이 검사를 만든 날, 같은 사람이 `.claude-memos/di_calculus_extension.md` 의
§4.4.4 를 §4.4.3 으로 **틀리게 「고쳤다」.** 헤딩(`=== `)이 아니라 *본문 언급*을
세었기 때문이다 — `04-ext-payload.typ:602` 가 「§4.4.4 가 … 택했고」라 적는데
그 줄 자체는 §4.4.3 안에 있고, 문자열 검색이 헤딩보다 먼저 그것을 잡았다.

**이 검사는 그것을 놓쳤다** — `@sec:` 형태만 보고 `§N.M.K` 는 보지 않았기
때문이다. 잡은 것은 `Di` 설계의 적대적 검증(사람 쪽)이었다.
⇒ 그날 `§N.M.K` 형태를 검사에 넣었다. **검사가 놓친 자리를 검사에 넣는 것이
이 저장소의 규율이다** (`claude.md` §7.2).

## 무엇을 재지 못하는가 — 정직하게

- **따옴표 없는 인용의 대상 적합성.** 「(@sec:isa 1.4.2)」처럼 문장 인용이
  없으면 3 이 발동하지 않는다. 절이 실재하기만 하면 통과한다. 489건 중
  따옴표를 동반하는 것은 일부다 — 나머지는 사람 검토에 남는다.
- **의미의 적합성.** 문장이 그 절에 있어도 그 인용이 옳은 근거인지는 재지 않는다.
- **축약 인용.** 「적중·대체·미적중」처럼 구분자로 이은 축약은 조각이 대상 절에
  흩어져 있으면 통과시킨다(보고만 한다) — 붙인 형태가 다른 절에만 있다는 이유로
  실패시키면 옳은 인용을 막는다. 이 완화 자체가 검출력의 구멍이다.
- **절 번호가 함께 움직이는 경우.** 인용과 대상이 같은 커밋에서 함께 밀리면
  둘 다 옳으므로 아무 일도 일어나지 않는다 — 그것이 정상이다.

⇒ **이 검사는 「좌표가 실재하는가」를 재지 「인용이 옳은가」를 재지 않는다.**
이름을 「인용 검사」가 아니라 **「절 인용 실재성 검사」**로 붙인 이유다.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
GUIDE = REPO / "docs" / "wt64v1-architecture-guide"

# 인용을 담을 수 있는 파일 — 정본 + 정본을 인용하는 층
SCAN_GLOBS = [
    (GUIDE, "**/*.typ"),
    (REPO / "rtl" / "formal" / "tla", "*.tla"),
    (REPO / "rtl" / "formal" / "sby", "**/*.sby"),
    (REPO / "rtl" / "sv" / "assert", "*.sv"),
    (REPO / ".claude-memos", "*.md"),
    (REPO / "docs" / "research", "*.md"),
]

# `@sec:label N.M[.K]` — 절 번호가 붙은 인용만 본다. 번호 없는 장 참조는 대상 아님.
REF_RE = re.compile(r"@sec:([a-z][a-z0-9-]*)\s+((?:\d+|부록\s*[A-Z])(?:\.\d+)*)")

# 인용 직후의 따옴표 내용.
#
# **거리를 30자로 좁힌 이유** (2026-08-27 실측): 120자로 열었더니 B.5 표의
# *요약 서술*을 축자 인용으로 오인해 오탐이 30건 넘게 났다. B.5 는 미결의
# 제목을 자기 말로 적으므로 그 문자열이 정본에 없는 것이 정상이다.
# 「A 가 적은 「…」」 형태의 진짜 인용은 사이가 짧다.
QUOTE_RE = re.compile(r"^.{0,30}?「([^」]{6,120})」", re.S)

LABEL_DECL_RE = re.compile(r"<(sec:[a-z][a-z0-9-]*)>")

# `§N.M[.K]` — 라벨 없이 절 번호만 쓴 인용. 장 번호 N 이 어느 파일인지는
# 장 번호 → 파일 맵으로 푼다. 2026-08-27 에 이 형태를 놓쳐 개악이 났다.
BARE_RE = re.compile(r"§(\d+\.\d+(?:\.\d+)?)")


def chapter_number(path: Path) -> str | None:
    """파일명에서 장 번호를 유도한다. 01-isa-asm.typ → '1', a-capacity.typ → '부록 A'."""
    m = re.match(r"(\d+)-", path.name)
    if m:
        n = int(m.group(1))
        return None if n == 0 else str(n)  # 00-preface 는 번호 없는 장
    m = re.match(r"([a-e])-", path.name)
    if m:
        return "부록 " + m.group(1).upper()
    return None


def build_section_map(path: Path) -> dict[str, tuple[int, int]]:
    """파일의 `==`/`===` 를 세어 {'1.4.2': (시작줄, 끝줄)} 를 만든다 (1-indexed, 끝 배타)."""
    ch = chapter_number(path)
    if ch is None:
        return {}
    lines = path.read_text(encoding="utf-8").splitlines()
    out: dict[str, tuple[int, int]] = {}
    sec = sub = 0
    open_keys: list[tuple[str, int]] = []

    def close(upto: int) -> None:
        while open_keys:
            k, start = open_keys.pop()
            out[k] = (start, upto)

    for i, line in enumerate(lines, 1):
        if line.startswith("=== "):
            sub += 1
            # 같은 깊이 이하만 닫는다
            while open_keys and open_keys[-1][0].count(".") >= 2:
                k, s = open_keys.pop()
                out[k] = (s, i)
            open_keys.append((f"{ch}.{sec}.{sub}", i))
        elif line.startswith("== "):
            sec += 1
            sub = 0
            close(i)
            open_keys.append((f"{ch}.{sec}", i))
    close(len(lines) + 1)
    return out


def main() -> int:
    # 1) 라벨 선언 수집 — 라벨 → (파일, 장 번호)
    labels: dict[str, tuple[Path, str | None]] = {}
    for p in sorted(GUIDE.rglob("*.typ")):
        for m in LABEL_DECL_RE.finditer(p.read_text(encoding="utf-8")):
            labels.setdefault(m.group(1), (p, chapter_number(p)))

    # 2) 절 맵 (파일별)
    secmaps: dict[Path, dict[str, tuple[int, int]]] = {}
    contents: dict[Path, list[str]] = {}
    for p in sorted(GUIDE.rglob("*.typ")):
        secmaps[p] = build_section_map(p)
        contents[p] = p.read_text(encoding="utf-8").splitlines()

    # 장 번호 → 파일 (`§4.4.4` 를 04-ext-payload.typ 로 풀기 위한 맵)
    chap_files: dict[str, Path] = {}
    for p in sorted(GUIDE.rglob("*.typ")):
        c = chapter_number(p)
        if c and c.isdigit():
            chap_files.setdefault(c, p)

    hard: list[str] = []
    soft: list[str] = []
    checked = quoted = 0

    for root, pat in SCAN_GLOBS:
        if not root.exists():
            continue
        for src in sorted(root.glob(pat)):
            try:
                text = src.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            rel = src.relative_to(REPO)
            # (b) `§N.M[.K]` — 라벨 없는 절 인용
            for m in BARE_RE.finditer(text):
                num = m.group(1)
                ch = num.split(".")[0]
                tgt = chap_files.get(ch)
                if tgt is None:
                    continue          # 그 장이 없다 — 다른 문서의 절일 수 있다
                checked += 1
                line_no = text[: m.start()].count("\n") + 1
                if num not in secmaps.get(tgt, {}):
                    near = sorted(k for k in secmaps.get(tgt, {})
                                  if k.startswith(num.rsplit(".", 1)[0]))
                    msg = (f"{rel}:{line_no} — `§{num}` 이 실재하지 않는다 "
                           f"({tgt.name}). 이웃: {', '.join(near[:6]) or '(없음)'}")
                    # **비정본은 자기 절 번호를 가진다.** `.claude-memos/wt64v1_spec.md`
                    # 의 `§2.1.1` 은 *그 문서의* 절이지 정본 2장이 아니다 —
                    # 2026-08-27 첫 실행에서 이 부류로 오탐 16건이 났다.
                    # ⇒ 정본 안과 `rtl/`(정본을 인용하는 층)만 하드로 본다.
                    if str(rel).startswith(("docs/wt64v1-architecture-guide/", "rtl/")):
                        hard.append(msg)
                    else:
                        soft.append(msg + " — 비정본이라 자기 절일 수 있다")

            for m in REF_RE.finditer(text):
                checked += 1
                label, num = "sec:" + m.group(1), m.group(2)
                line_no = text[: m.start()].count("\n") + 1

                if label not in labels:
                    hard.append(f"{rel}:{line_no} — 라벨 `@{label}` 이 정본에 선언되지 않았다")
                    continue
                tgt_path, tgt_ch = labels[label]

                # 장 번호 대조 — `@sec:isa 2.3` 부류
                if tgt_ch is not None and not num.startswith(tgt_ch):
                    hard.append(
                        f"{rel}:{line_no} — `@{label} {num}` 의 장 번호가 어긋난다. "
                        f"`{label}` 은 {tgt_ch}장({tgt_path.name})이다"
                    )
                    continue

                secmap = secmaps.get(tgt_path, {})
                if num not in secmap:
                    near = sorted(k for k in secmap if k.startswith(num.rsplit(".", 1)[0]))
                    hard.append(
                        f"{rel}:{line_no} — `@{label} {num}` 이 실재하지 않는다. "
                        f"{tgt_path.name} 의 이웃: {', '.join(near[:6]) or '(없음)'}"
                    )
                    continue

                # 3) 따옴표 내용이 그 절 안에 있는가
                tail = text[m.end() : m.end() + 120]
                q = QUOTE_RE.search(tail)
                if not q:
                    continue
                quoted += 1
                needle = re.sub(r"\s+", "", q.group(1))
                # 강조 표시(*)는 대상 문서에 있고 인용에는 없을 수 있다 — 양쪽에서 제거
                needle = needle.replace("*", "").replace("`", "")
                s, e = secmap[num]
                # 같은 파일 안의 인용이면 **인용문 자신**을 대조 대상에서 뺀다.
                # 빼지 않으면 「자기가 쓴 문장」을 「실제 자리」로 오인한다 (2026-08-27 실측).
                lines_tgt = list(contents[tgt_path])
                if tgt_path == src:
                    for k in range(line_no - 1, min(line_no + 2, len(lines_tgt))):
                        lines_tgt[k] = ""
                body = "".join(lines_tgt[s - 1 : e - 1])
                body = re.sub(r"\s+", "", body).replace("*", "").replace("`", "")
                if needle in body:
                    continue
                # 절 밖 어딘가에는 있는가 — 있으면 「엉뚱한 절」이고, 없으면 인용 자체가 낡았다
                whole = re.sub(r"\s+", "", "".join(lines_tgt))
                whole = whole.replace("*", "").replace("`", "")
                if needle in whole:
                    # **축약 인용 완화** (2026-08-27 실측): 「적중·대체·미적중」처럼
                    # 구분자로 이은 축약형은 인용된 절에 조각이 *흩어져* 있고
                    # 붙여 쓴 형태만 다른 절에 있을 수 있다. 그때 인용은 옳다 —
                    # §5.3(상수 시간성)에 셋이 14/2/9회 나오는데 붙인 형태는
                    # §5.8 에만 있던 실측 사례가 그것이다.
                    parts = [x for x in re.split(r"[·/,]", q.group(1)) if len(x.strip()) >= 2]
                    if len(parts) >= 2 and all(
                        re.sub(r"\s+", "", x).replace("*", "").replace("`", "") in body
                        for x in parts
                    ):
                        soft.append(
                            f"{rel}:{line_no} — `@{label} {num}` 의 축약 인용 "
                            f"「{q.group(1)[:30]}…」 — 조각은 그 절에 있고 붙인 형태만 밖에 있다"
                        )
                        continue
                    owner = next(
                        (k for k, (a, b) in secmap.items()
                         if k.count(".") >= 2
                         and needle in re.sub(r"\s+", "", "".join(lines_tgt[a - 1 : b - 1]))
                                        .replace("*", "").replace("`", "")),
                        "(항 밖)",
                    )
                    hard.append(
                        f"{rel}:{line_no} — `@{label} {num}` 이 인용한 「{q.group(1)[:34]}…」는 "
                        f"그 절에 없다. 실제 자리는 **{owner}** 다"
                    )
                else:
                    # 대상 파일 어디에도 없다 — 축자 인용이 아니라 *요약*일 수 있다.
                    # B.5 는 미결 제목을 자기 말로 적으므로 이것이 정상인 경우가 많다.
                    # ⇒ 보고만 하고 실패시키지 않는다. 잡는 것은 「실재하는 엉뚱한 절」이다.
                    soft.append(
                        f"{rel}:{line_no} — `@{label} {num}` 뒤의 「{q.group(1)[:30]}…」가 "
                        f"{tgt_path.name} 에 축자로 없다 (요약이면 정상)"
                    )

    if soft:
        print(f"  · 축자 대조 보류 {len(soft)}건 (요약 인용으로 보인다 — 실패 아님):")
        for t in soft[:6]:
            print(f"      {t}")
        if len(soft) > 6:
            print(f"      … 외 {len(soft)-6}건")

    if hard:
        print("lint_section_refs: 실패", file=sys.stderr)
        for h in hard:
            print(f"  ❌ {h}", file=sys.stderr)
        print(
            f"\n  — 절 인용 {checked}건 중 {len(hard)}건이 어긋난다.\n"
            f"    좌표는 문서를 고칠 때마다 움직인다. 인용할 때 절 번호를 짐작하지 말고\n"
            f"    대상 파일의 `==`/`===` 를 세어 확인하라 (이 검사가 그것을 대신 센다).",
            file=sys.stderr,
        )
        return 1

    print(
        f"lint_section_refs: OK — 절 인용 {checked}건 실재 "
        f"(그중 {quoted}건은 따옴표 내용까지 해당 절에서 확인) · 라벨 {len(labels)}종"
    )
    print(
        "  ※ 재는 것은 「좌표가 실재하는가」이지 「인용이 옳은 근거인가」가 아니다 — "
        "따옴표 없는 인용의 대상 적합성은 사람 검토에 남는다"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
