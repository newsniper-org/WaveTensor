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
| XDC / SDC constraints | `# SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0` |
| Synth/impl Tcl scripts | `# SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0` |
| Python (assembler, tests, drivers, daemon) | `# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0` |
| Makefile | `# SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0` |
| Documentation (`*.md`, ISA spec) | `<!-- SPDX-License-Identifier: CC-BY-4.0 -->` |

PRs that introduce new source files without the appropriate SPDX header
will be rejected.

---

## 3. Code review bar

* **Hardware (RTL)**: Verilator `--lint-only -Wall -Wno-fatal` must be
  clean (warnings allowed only with documented `lint_off` and rationale).
  cocotb regression must pass on the affected module.
* **Software**: All cocotb tests must continue to pass. Assembler unit
  tests (`python -m unittest -q asm.test_wavetensor_asm`) must pass.
* **Documentation**: Markdown files should remain valid CommonMark and
  use UTF-8.
* **Synthesis impact**: Changes to RTL that cross the EHDecode / PE_Core
  boundary should be re-synthesized (XCAU25P reference part) and the
  post-route LUT/FF/WNS deltas posted in the PR description.

---

## 4. ISA changes (WT64v1)

WT64v1 is **frozen** as defined in `.claude-memos/wt64v1_spec.md`. New
opcodes, EH types, or src_kind values require:

1. A new `.claude-memos/` design memo justifying the addition.
2. Reservation in the appropriate range (see `wt64v1_spec.md` §3.9).
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
