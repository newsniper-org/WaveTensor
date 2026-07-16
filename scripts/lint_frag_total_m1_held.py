#!/usr/bin/env python3
# SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""v1.7 §22.18 CI lint — structural backstop for the frag_total_m1_held
invariant.

PE_Core.v's fragment-drain FSM (frag_idx) is a shared resource: every
dispatch site that enters the drain (frag_idx <= FRAG_EMIT_1) MUST also
write frag_total_m1_held in the SAME begin/end block, so the drain loop
knows how many fragments to emit. A dispatch site that forgets this
leaves a STALE frag_total_m1_held from whatever the PREVIOUS drain wrote,
silently corrupting the fragment count of the next legacy op that
immediately follows a WIDEN dispatch (or vice versa).

This script scans PE_Core.v for every syntactic block assigning
`frag_idx <= FRAG_EMIT_1` and asserts the SAME block also assigns
frag_total_m1_held. It is a simple brace-balance scanner, not a full
Verilog parser — sufficient for this repo's consistent formatting.

Exit code 0 = all sites compliant. Exit code 1 = violation found (prints
the offending line number and surrounding context).
"""

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PE_CORE_V = REPO_ROOT / "PE_Core.v"

FRAG_IDX_ASSIGN = re.compile(r"frag_idx\s*<=\s*FRAG_EMIT_1\b")
FRAG_TOTAL_ASSIGN = re.compile(r"frag_total_m1_held\s*<=")
CASE_ITEM_START = re.compile(r":\s*begin\s*$")


def _strip_comment(line: str) -> str:
    idx = line.find("//")
    return line if idx < 0 else line[:idx]


def _indent(line: str) -> int:
    return len(line) - len(line.lstrip())


def _find_enclosing_case_arm(lines, hit_line_idx):
    """Find the (start, end) line range of the case-item arm containing
    hit_line_idx, using indentation as a proxy for Verilog block nesting
    (reliable given this file's consistent formatting): walk backward for
    the nearest preceding "...: begin" line at LESS indentation than the
    hit line (the arm's own opening), then walk forward for the next line
    at that SAME indentation starting with "end" (the arm's closing)."""
    start = 0
    start_indent = 0
    for i in range(hit_line_idx, -1, -1):
        stripped = _strip_comment(lines[i]).rstrip()
        if CASE_ITEM_START.search(stripped) and _indent(lines[i]) < _indent(lines[hit_line_idx]):
            start = i
            start_indent = _indent(lines[i])
            break
    end = len(lines) - 1
    for i in range(start + 1, len(lines)):
        stripped = _strip_comment(lines[i]).strip()
        if _indent(lines[i]) == start_indent and stripped.startswith("end"):
            end = i
            break
    return start, end


def main() -> int:
    if not PE_CORE_V.exists():
        print(f"lint_frag_total_m1_held: {PE_CORE_V} not found", file=sys.stderr)
        return 1

    lines = PE_CORE_V.read_text().splitlines()
    violations = []

    for i, line in enumerate(lines):
        code = _strip_comment(line)
        if FRAG_IDX_ASSIGN.search(code):
            start, end = _find_enclosing_case_arm(lines, i)
            block = lines[start:end + 1]
            if not any(FRAG_TOTAL_ASSIGN.search(_strip_comment(l)) for l in block):
                violations.append((i + 1, line.strip()))

    if violations:
        print("lint_frag_total_m1_held: FAIL — found dispatch site(s) "
              "entering the fragment drain without writing "
              "frag_total_m1_held in the same block:", file=sys.stderr)
        for lineno, text in violations:
            print(f"  PE_Core.v:{lineno}: {text}", file=sys.stderr)
        return 1

    print(f"lint_frag_total_m1_held: OK — all frag_idx<=FRAG_EMIT_1 "
          f"sites co-locate a frag_total_m1_held write.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
