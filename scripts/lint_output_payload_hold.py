#!/usr/bin/env python3
# SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""v1.9.1 §31.14 CI lint — **자격자-홀드 불변식** (qualifier-hold invariant).

무엇을 지키는가
---------------
`PE_Core.output_payload` 는 단순한 출력 레지스터가 아니다. **`Cluster` 의
NoC bank (OPREF.src_kind=1) 가 L-PE 슬롯의 저장소로 그것을 그대로 쓴다**
(`Cluster.v` 의 bank mux — `pe_out_payload[k]` 를 조합적으로 읽는다).
MU/DU 슬롯이 `mu_bank_reg`/`du_bank_reg` 라는 **valid-게이트 레지스터**를
따로 두는 것과 달리, L-PE 슬롯은 별도 뱅크 레지스터를 두지 않고
`PE_Core` 의 출력 레지스터를 재사용한다 (면적 최적화: PE 당 64-bit
레지스터 1개 절약).

그 재사용이 성립하려면 다음이 참이어야 한다:

    **불변식 H1** — `output_payload` 는 `output_valid` 가 뜨는 사이클에만
    바뀐다. 즉 토큰을 내지 않는 명령은 뱅크를 오염시킬 수 없다.

    **불변식 H2** — `mem_addr` 는 `memory_req` 가 뜨는 사이클에만 바뀐다
    (같은 형식. D11 수리의 나머지 절반).

H1 이 깨지면 **`output_valid == 0` 인 사이클의 `output_payload` 차이는
"masked" 가 아니다** — 그 값이 다음 명령의 B 피연산자로 그대로 읽힌다.
실제로 v1.9 baseline 은 H1 을 위반했고(성공 arm 이 `cr_valid_out` 과
무관하게 `output_payload <= cr_payload` 를 수행), 그 결과 토큰을 내지 않는
LD(0x04) 한 건이 앞선 2-fragment wave 가 뱅크에 남긴 값을 되돌려 놓았다
(spec §31.14.2 실증: 소비자가 읽은 값이 `0x7777...` → `0x3333...` 로 바뀐다).

왜 lint 인가 — "소비자에 레지스터를 하나 더 달면 되지 않나"
---------------------------------------------------------
`Cluster` 쪽에 `pe_bank_reg` 를 두어 자격자로 게이트하면 구조적으로는
안전해지지만, 그것은 `PE_Core` 의 출력 레지스터와 **완전히 중복된**
NUM_PES × 64-bit 레지스터를 새로 만드는 것이고 (Pod 문맥에서는 × 클러스터
수), 무엇보다 **미래의 H1 위반을 조용히 덮는다.** 침묵시키는 대신 소리내는
것이 프로젝트 법칙(loud-fault-never-silent)이므로, 계약을 기록하고
**기계적으로 집행**한다. 이 파일이 그 집행이다.

검사 규칙 (기계적 — begin/end 토큰 스택으로 블록을 판정한다)
------------------------------------------------------------
`PE_Core.v` 의 모든 `<LHS> <= ...;` 대입에 대해 셋 중 하나여야 한다:

  1. **reset arm** — 감싸는 최내곽 begin/end 의 opener 가 `if (rst)` 다.
     (결정적 초기화. 자격자도 같은 arm 에서 0 이 된다.)
  2. **무조건 emit arm** — 같은 블록에 `<QUAL> <= 1'b1;` 이 있다.
     (그 사이클에 반드시 토큰이 나가므로 자격자와 동시에 바뀐다.)
  3. **자격 가드 복사** — 대입이 `if (<G>)` 로 인라인 가드돼 있고, 같은
     블록에 `<QUAL> <= <G>;` 가 있다. (자격자와 **같은 식**으로 가드되므로
     자격자가 0 인 사이클에는 값이 바뀌지 않는다.)

셋 중 어느 것도 아니면 위반이다 — 자격자가 0 인 사이클에 값이 바뀔 수
있다는 뜻이고, 그 순간 NoC bank 계약이 깨진다.

Exit 0 = 전 대입 site 가 세 형식 중 하나. Exit 1 = 위반 (행 번호 출력).
"""

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PE_CORE_V = REPO_ROOT / "PE_Core.v"

# (값 레지스터, 그 값을 유효하게 만드는 자격자)
PAIRS = (
    ("output_payload", "output_valid"),
    ("mem_addr", "memory_req"),
)

_BEGIN_END = re.compile(r"\b(begin|end)\b")
_RST_OPENER = re.compile(r"\bif\s*\(\s*rst\s*\)")


def _strip_comment(line: str) -> str:
    idx = line.find("//")
    return line if idx < 0 else line[:idx]


def _block_map(lines):
    """begin/end 토큰 스택 페어링 (lint_frag_total_m1_held 와 동일 형식).

    `\\bend\\b` 는 endcase/endgenerate/endfunction/endmodule 안에서 매치되지
    않고 (word boundary), `end else begin` 은 finditer 로 올바른 순서가 된다.
    """
    blocks = []
    stack = []
    for i, line in enumerate(lines):
        code = _strip_comment(line)
        for m in _BEGIN_END.finditer(code):
            if m.group(1) == "begin":
                stack.append(i)
            else:
                if stack:
                    blocks.append((stack.pop(), i))
    while stack:
        blocks.append((stack.pop(), len(lines) - 1))
    return blocks


def _enclosing(blocks, idx):
    """idx 를 포함하는 **최내곽** 블록 (begin 이 가장 늦은 것)."""
    best = None
    for b, e in blocks:
        if b <= idx <= e and (best is None or b > best[0]):
            best = (b, e)
    return best


def main() -> int:
    if not PE_CORE_V.exists():
        print(f"lint_output_payload_hold: {PE_CORE_V} not found",
              file=sys.stderr)
        return 1

    lines = PE_CORE_V.read_text().splitlines()
    blocks = _block_map(lines)

    violations = []
    census = {}

    for lhs, qual in PAIRS:
        # `cr_payload` / `cr_mem_addr` 같은 접두어 붙은 다른 레지스터를
        # 잡지 않도록 왼쪽 word boundary 를 강제한다.
        assign_re = re.compile(r"(?<![\w.])" + re.escape(lhs) + r"\s*<=")
        guard_re = re.compile(r"\bif\s*\(([^()]*)\)\s*" + re.escape(lhs)
                              + r"\s*<=")
        qual_true_re = re.compile(r"(?<![\w.])" + re.escape(qual)
                                  + r"\s*<=\s*1'b1\s*;")
        counts = {"reset": 0, "emit": 0, "guarded": 0}

        for i, raw in enumerate(lines):
            code = _strip_comment(raw)
            if not assign_re.search(code):
                continue
            enc = _enclosing(blocks, i)
            if enc is None:
                violations.append(
                    (i + 1, raw.strip(), lhs,
                     "감싸는 begin/end 블록을 찾지 못했다"))
                continue
            b, e = enc
            opener = _strip_comment(lines[b])
            block = [_strip_comment(l) for l in lines[b:e + 1]]

            # 형식 1 — reset arm
            if _RST_OPENER.search(opener):
                counts["reset"] += 1
                continue

            # 형식 2 — 무조건 emit arm (`<QUAL> <= 1'b1;` 동거)
            if any(qual_true_re.search(l) for l in block):
                counts["emit"] += 1
                continue

            # 형식 3 — 자격 가드 복사 (`if (G) LHS <= ...` + `QUAL <= G;`)
            gm = guard_re.search(code)
            if gm:
                g = gm.group(1).strip()
                qual_g_re = re.compile(
                    r"(?<![\w.])" + re.escape(qual) + r"\s*<=\s*"
                    + re.escape(g) + r"\s*;")
                if any(qual_g_re.search(l) for l in block):
                    counts["guarded"] += 1
                    continue
                violations.append(
                    (i + 1, raw.strip(), lhs,
                     f"`if ({g})` 로 가드돼 있으나 같은 블록에 "
                     f"`{qual} <= {g};` 가 없다 — 가드 식과 자격자 식이 "
                     f"달라 자격자가 0 인 사이클에 값이 바뀔 수 있다"))
                continue

            violations.append(
                (i + 1, raw.strip(), lhs,
                 f"자격자 없는 대입 — 같은 블록에 `{qual} <= 1'b1;` 도 "
                 f"없고 인라인 `if ({qual}...)` 가드도 없다. "
                 f"`{qual} == 0` 인 사이클에 `{lhs}` 가 바뀌면 "
                 f"Cluster NoC bank (OPREF.src_kind=1) 가 오염된다 "
                 f"(spec §31.14 불변식 H1/H2)"))

        census[lhs] = counts

    if violations:
        print("lint_output_payload_hold: FAIL — 자격자-홀드 불변식 위반:",
              file=sys.stderr)
        for lineno, text, lhs, why in violations:
            print(f"  PE_Core.v:{lineno}: {text}\n    -> [{lhs}] {why}",
                  file=sys.stderr)
        print("\n  이 불변식이 왜 있는지: Cluster 의 NoC bank 는 L-PE "
              "슬롯의 저장소로 PE_Core 의 출력 레지스터를 그대로 재사용한다 "
              "(MU/DU 처럼 별도 bank 레지스터를 두지 않는다). 자격자가 0 인 "
              "사이클에 값이 바뀌면 토큰을 내지 않은 명령이 뱅크를 덮어쓴다 "
              "— spec §31.14.", file=sys.stderr)
        return 1

    parts = []
    for lhs, qual in PAIRS:
        c = census[lhs]
        parts.append(f"{lhs}/{qual}: reset {c['reset']} + emit {c['emit']} "
                     f"+ guarded {c['guarded']} = "
                     f"{c['reset'] + c['emit'] + c['guarded']} site(s)")
    print("lint_output_payload_hold: OK — 자격자-홀드 불변식 전건 성립 "
          "(spec §31.14 H1/H2)")
    for p in parts:
        print(f"  {p}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
