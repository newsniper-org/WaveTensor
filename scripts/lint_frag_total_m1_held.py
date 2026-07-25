#!/usr/bin/env python3
# SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
# SPDX-FileCopyrightText: 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors
"""v1.7 §22.18 CI lint — structural backstop for the frag_total_m1_held
invariant. v1.8.0e §25.3 EXTENSION (same commit as the first new writer,
the DEQUANT loop-completion handoff): the writer-discovery heuristic now
covers NON-case-arm writer blocks, and the FRAG_EMIT_1 SYMBOL is
enforced.

PE_Core.v's fragment-drain FSM (frag_idx) is a shared resource: every
dispatch site that enters the drain (frag_idx <= FRAG_EMIT_1) MUST also
write frag_total_m1_held in the SAME begin/end block, so the drain loop
knows how many fragments to emit. A dispatch site that forgets this
leaves a STALE frag_total_m1_held from whatever the PREVIOUS drain wrote,
silently corrupting the fragment count of the next op that immediately
follows a multi-fragment dispatch (or vice versa). Originally motivated
by the retired 0x6B WIDEN 4-fragment emitter (removed pre-stable in the
opcode cleanup); the invariant binds every remaining 2-fragment site,
the v1.8.0e comb-arm emitters (0x6B GAMMA_MUL_W / 0x79 FMINMAX) and the
DEQUANT loop-completion frag0_hold handoff.

v1.8.0e extensions (spec §25.3, closing the confirmed blind spot):
  1. WRITER DISCOVERY — the old heuristic only recognized case-arm
     openers (`...: begin`), so a drain-entry writer in a plain
     if-block (the atomic frag0_hold handoff) or a generate region
     passed VACUOUSLY. The enclosing block is now found via the nearest
     preceding line ENDING in `begin` at strictly less indentation
     (case arms, if/else blocks and generate bodies all match under
     this repo's consistent formatting).
  2. FRAG_EMIT_1 SYMBOL — a drain entry spelled `frag_idx <= 4'd1`
     (the literal aliasing FRAG_EMIT_1) is flagged: the symbol is the
     lint's own discovery anchor, so a literal spelling would silently
     escape rule 1 entirely (lint discoverability pin). Any other
     non-symbol RHS besides the FSM's own FRAG_IDLE return and up-count
     is flagged for the same reason.
  3. WRITER CENSUS — the total number of `frag_idx <= FRAG_EMIT_1`
     sites is printed so a review can see new writers appear.

Block discovery is a real begin/end token stack (v1.8.0e — the old
indentation heuristic missed openers whose `begin` sits on a wrapped
continuation line, exactly the shape of the new handoff writer), not a
full Verilog parser — sufficient for this repo's consistent formatting
(`\bend\b` never matches endcase/endgenerate/endfunction/endmodule).

Exit code 0 = all sites compliant. Exit code 1 = violation found (prints
the offending line number and surrounding context).
"""

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PE_CORE_V = REPO_ROOT / "PE_Core.v"

FRAG_IDX_ANY_ASSIGN = re.compile(r"frag_idx\s*<=\s*(?P<rhs>[^;]+);")
FRAG_IDX_ASSIGN = re.compile(r"frag_idx\s*<=\s*FRAG_EMIT_1\b")
FRAG_TOTAL_ASSIGN = re.compile(r"frag_total_m1_held\s*<=")
# Legal non-entry RHS forms for frag_idx (the FSM's own drain logic).
LEGAL_NON_ENTRY_RHS = (
    re.compile(r"^FRAG_IDLE\s*$"),            # reset / drain return
    re.compile(r"^frag_idx\s*\+\s*4'd1\s*$"),  # drain up-count
    re.compile(r"^FRAG_EMIT_1\s*$"),           # symbolic drain entry
)


def _strip_comment(line: str) -> str:
    idx = line.find("//")
    return line if idx < 0 else line[:idx]


_BEGIN_END = re.compile(r"\b(begin|end)\b")


def _block_map(lines):
    """Token-accurate begin/end pairing: returns a list of
    (begin_line, end_line) for every begin/end block in the file, built
    with a stack over the in-order token stream. `\\bend\\b` cannot
    match inside endcase/endgenerate/endfunction/endmodule (word
    boundary), and `end else begin` orders correctly via finditer.
    Replaces the v1.7 indentation heuristic, whose case-arm/indent
    assumptions passed VACUOUSLY on (a) generate-region writers and
    (b) writers under a multi-line if whose `begin` sits on a wrapped
    continuation line — both confirmed blind spots (§25.3)."""
    blocks = []
    stack = []
    for i, line in enumerate(lines):
        code = _strip_comment(line)
        for m in _BEGIN_END.finditer(code):
            if m.group(1) == "begin":
                stack.append(i)
            elif stack:
                blocks.append((stack.pop(), i))
    # Unbalanced leftovers close at EOF (defensive — should not happen).
    while stack:
        blocks.append((stack.pop(), len(lines) - 1))
    return blocks


def _find_enclosing_block(blocks, hit_line_idx):
    """The INNERMOST begin/end block containing hit_line_idx: among all
    blocks whose range covers the line, the one with the latest begin."""
    best = (0, len(blocks) and max(e for _, e in blocks) or 0)
    found = False
    for b, e in blocks:
        if b <= hit_line_idx <= e and (not found or b > best[0]):
            best = (b, e)
            found = True
    return best


def main() -> int:
    if not PE_CORE_V.exists():
        print(f"lint_frag_total_m1_held: {PE_CORE_V} not found", file=sys.stderr)
        return 1

    lines = PE_CORE_V.read_text().splitlines()
    blocks = _block_map(lines)
    violations = []
    entry_sites = 0

    for i, line in enumerate(lines):
        code = _strip_comment(line)
        m = FRAG_IDX_ANY_ASSIGN.search(code)
        if m:
            rhs = m.group("rhs").strip()
            if not any(p.match(rhs) for p in LEGAL_NON_ENTRY_RHS):
                # v1.8.0e rule 2 — non-symbol drain entry (e.g. 4'd1
                # literal): would silently escape the co-location scan.
                violations.append(
                    (i + 1, line.strip(),
                     f"non-symbol frag_idx RHS {rhs!r} — drain entry must "
                     f"use the FRAG_EMIT_1 SYMBOL (lint discoverability)"))
                continue
        if FRAG_IDX_ASSIGN.search(code):
            entry_sites += 1
            start, end = _find_enclosing_block(blocks, i)
            block = lines[start:end + 1]
            if not any(FRAG_TOTAL_ASSIGN.search(_strip_comment(l)) for l in block):
                violations.append(
                    (i + 1, line.strip(),
                     "drain entry without a frag_total_m1_held write in "
                     "the same begin/end block"))

    if violations:
        print("lint_frag_total_m1_held: FAIL — frag-drain invariant "
              "violation(s):", file=sys.stderr)
        for lineno, text, why in violations:
            print(f"  PE_Core.v:{lineno}: {text}\n    -> {why}",
                  file=sys.stderr)
        return 1

    print(f"lint_frag_total_m1_held: OK — {entry_sites} "
          f"frag_idx<=FRAG_EMIT_1 site(s), all co-locate a "
          f"frag_total_m1_held write; no non-symbol drain entries.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
