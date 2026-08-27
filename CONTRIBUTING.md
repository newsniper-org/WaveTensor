# Contributing to WaveTensor

Thank you for your interest in WaveTensor. This document covers the
licensing covenant required for all contributions, the technical bar
for proposed changes, and the local development workflow.

---

## 1. Developer Certificate of Origin (DCO) — required

WaveTensor uses the Linux-style **Developer Certificate of Origin v1.1**
plus an **explicit multi-license consent clause**. Every contribution
(commit, pull request, patch) must be signed off with a `Signed-off-by`
trailer. The signed-off-by certifies all of the following:

> Developer's Certificate of Origin 1.1 (Linux-style):
>
> By making a contribution to this project, I certify that:
>
> (a) The contribution was created in whole or in part by me and I have
>     the right to submit it under the open source license indicated in
>     the file; or
> (b) The contribution is based upon previous work that, to the best of
>     my knowledge, is covered under an appropriate open source license
>     and I have the right under that license to submit that work with
>     modifications, whether created in whole or in part by me, under
>     the same open source license (unless I am permitted to submit
>     under a different license), as indicated in the file; or
> (c) The contribution was provided directly to me by some other person
>     who certified (a), (b) or (c) and I have not modified it.
> (d) I understand and agree that this project and the contribution are
>     public and that a record of the contribution (including all
>     personal information I submit with it, including my sign-off) is
>     maintained indefinitely and may be redistributed consistent with
>     this project or the open source license(s) involved.
>
> WaveTensor multi-license consent (extension):
>
> (e) I expressly agree that my hardware contribution may be released
>     under EITHER of:
>     - Solderpad Hardware License Version 2.1 (SHL-2.1)
>     - CERN Open Hardware Licence Version 2 — Weakly Reciprocal
>       (CERN-OHL-W-2.0)
>     at the recipient's choice, as documented in `LICENSE.md`.
>
> (f) I expressly agree that my software contribution may be released
>     under ANY of:
>     - GNU Lesser General Public License v2.1 or later
>       (LGPL-2.1-or-later) — including any later version of the LGPL
>       at the recipient's option ("or-later" semantics)
>     - BSD 2-Clause License (BSD-2-Clause)
>     - Apache License Version 2.0 (Apache-2.0)
>     at the recipient's choice, as documented in `LICENSE.md`.
>
> (g) I expressly agree that my documentation contribution may be
>     released under Creative Commons Attribution 4.0 International
>     (CC-BY-4.0).
>
> (h) I confirm that I have the legal right to grant the above licenses
>     for the contribution. If I am contributing on behalf of an
>     employer, I have obtained the necessary authorization.

To sign off, append the following to your commit message (`git commit -s`
adds it automatically):

```
Signed-off-by: Your Name <your.email@example.com>
```

PRs without DCO sign-off will not be merged.

---

## 2. SPDX header requirement

Every new source file must carry the appropriate SPDX-License-Identifier
on the first or second line:

| File class | SPDX header |
|---|---|
| Verilog/SystemVerilog (`*.v`, `*.sv`) | `// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0` |
| **SpinalHDL design sources (`rtl/spinal/src/**/*.scala`)** | `// SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0` |
| **Scala build definitions (`build.sbt`, `*.sbt`, `project/*.properties`, `project/*.scala`)** | `// SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0` (`#` for `.properties`) |
| XDC / SDC constraints | `# SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0` |
| Synth/impl Tcl scripts | `# SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0` |
| Python (assembler, tests, drivers, daemon) | `# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0` |
| Makefile | `# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0` |
| Documentation (`*.md`, ISA spec) | `<!-- SPDX-License-Identifier: CC-BY-4.0 -->` |

### Why `.scala` splits into two rows

A `.scala` file under `rtl/spinal/src/` **is hardware description** — it is the
source from which the SystemVerilog in `rtl/generated/` is produced, and that
generated output carries the HW header. Licensing the generator under a
software licence while its output is hardware-licensed would put the two out
of step. So design sources take the **HW** header.

Build definitions (`build.sbt`, `project/build.properties`) describe *how to
run the compiler*, not the circuit. They are tooling, like the `Makefile`, and
take the **SW** header.

> The dividing line is *what the file describes*, not what language it is
> written in. `rtl/README.md` declares the same boundary per directory.

PRs that introduce new source files without the appropriate SPDX header
will be rejected.

---

## 3. Code review bar

* **Hardware (RTL)**: Verilator `--lint-only -Wall -Wno-fatal -Iinclude`
  must be clean (warnings allowed only with documented `lint_off` and
  rationale; `-Iinclude` is required since v1.8.0a — EHDecode.v reads
  generated includes). cocotb regression must pass on the affected module.
* **Software**: All cocotb tests must continue to pass. Assembler unit
  tests (`python -m unittest -q asm.test_wavetensor_asm`) must pass.
* **Lint**: `make lint` must pass. It is **fifteen** stdlib-only checks, not
  two — this count has now gone stale *twice* (two → eight → fourteen → fifteen), which
  is exactly the failure mode `lint_estimate_index` exists to catch. A count
  written in prose next to a list that grows is a defect waiting to happen;
  the authority is `Makefile`'s `lint:` target, not this sentence:
  `lint_isa_tables_fresh` (generated ISA artifacts match the JSON) ·
  `lint_frag_total_m1_held` (frag-drain FSM invariant) ·
  `lint_synth_coverage` (every cocotb-verified module declares a synthesis
  position) · `lint_output_payload_hold` (qualifier-hold invariant) ·
  `lint_frag_slots_dual_run` (FRAG_SLOTS=1/4 dual build is really run) ·
  `lint_known_defect_tests` (`expect_fail` two-way ratchet) ·
  `lint_estimate_index` (spec §39.2 estimate index: anchors live, IDs
  agree with spec §39.2.3 both ways, graduation evidence exists) ·
  `lint_gate_thresholds` (the gate **judges** themselves are BLAKE2b-512
  pinned — editing a judge is changing a gate criterion, and that must not
  pass silently; see 정본 부록 B.3 "판정기 상수를 편집해도 아무것도 울지 않는다").
  Each is runnable directly without cocotb, e.g.
  `python3 scripts/lint_isa_tables_fresh.py`. Note `make lint` itself
  parses the Makefile, which needs `cocotb-config` on PATH.
* **ISA single source (v1.8.0a §23.9)**: opcode identity / EH legality
  facts live ONLY in `isa/wt64v1_isa.json`. To change them: edit the
  JSON, run `python3 scripts/gen_isa_tables.py generate`, commit the
  source and all five generated artifacts together. Never hand-edit a
  `generated/` file. Merge-conflict protocol: resolve conflicts in the
  JSON only, regenerate, never hand-merge generated artifacts.
* **Documentation**: Markdown files should remain valid CommonMark and
  use UTF-8.
* **Synthesis impact**: Changes to RTL that cross the EHDecode / PE_Core
  boundary should be re-synthesized and the post-route LUT/FF/WNS deltas
  posted in the PR description. The reference part is
  **`xcu55c-fsvh2892-2L-e`** — every tracked `synth/reports/fp_ops/
  *_summary.json` records that device, and `python3
  synth/scripts/fp_op_gate_check.py` judges against those reports.
  *(XCAU25P was the Stage-0 board and was retired — see
  `wt64v1_spec.md` §"참조 구현 마이그레이션". Do not target it: the
  current design is 173K LUT against the part's 141K, a 123% overflow,
  so P&R cannot complete and the procedure is not reproducible.)*

---

## 4. ISA changes (WT64v1)

WT64v1 is **pre-stable**, and the freeze guarantees are **not yet in
force**. Per `wt64v1_spec.md` §12a, the three freeze promises — frozen
first-class opcodes, truth-table keep-forever, and snapshot equivalence
— take effect **at the stable release**, not before. Until then,
removing a dead opcode or re-deriving a latency contract is a *regular*
development act, not a policy reversal. What does bind you today is
**spec-first** (§12a rule 3): the spec amendment lands before the JSON,
the JSON before the regenerated artifacts, and those before RTL/tests.

New opcodes, EH types, or src_kind values require:

1. A new `.claude-memos/` design memo justifying the addition.
2. Reservation recorded in `isa/wt64v1_isa.json` (the single source),
   then regenerated artifacts — see `wt64v1_spec.md` §3 for the opcode
   map and §23.9 for the staging procedure.
3. Decision on whether the change is `WT64v1.x` (backward-compatible
   patch — additions only), `WT64v2` (incompatible), or a `WT64v1-C`
   extension (additive but separately conformant).

Implementation may proceed in this repository **only after** the spec
memo lands in mainline.

---

## 5. Issue / PR template (informal)

When opening an issue or PR, please include:

* What changed, and why (link to spec memo if applicable).
* Affected modules and tests.
* Synthesis numbers (if RTL change crosses synth boundary).
* DCO sign-off (`Signed-off-by:` trailer in every commit).

---

## 6. Code of conduct

Be technical, be specific, be patient. Hardware/software co-design has
a long debug horizon — review feedback should focus on correctness,
clarity, and synthesis impact rather than style preferences.
