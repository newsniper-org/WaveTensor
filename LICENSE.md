# WaveTensor — License Overview

Copyright © 2026 윤병익 (BYUNG-IK YEUN) and WaveTensor contributors.

WaveTensor is published under the following licenses, by component class.
Recipients **MAY choose ANY ONE** of the listed licenses for their use of
each component, at their option. The choice may be made independently for
each file or compilation unit.

---

## 1. Hardware components — choose one of:

* **Solderpad Hardware License Version 2.1** (`SHL-2.1`)
  See `LICENSE-HW-SHL-2.1`.
* **CERN Open Hardware Licence Version 2 — Weakly Reciprocal** (`CERN-OHL-W-2.0`)
  See `LICENSE-HW-CERN-OHL-W-2.0`.

Files in this class are tagged with:

```
SPDX-License-Identifier: SHL-2.1 OR CERN-OHL-W-2.0
```

This applies to:

* All Verilog/SystemVerilog sources (`*.v`, `*.sv`)
* Constraints (`*.xdc`, `*.sdc`)
* Synthesis & implementation Tcl scripts (`synth/scripts/*.tcl`)
* Any future floor-plans, IP-XACT files, or netlists derived from the above.

Solderpad 2.1 is permissive (Apache-2.0 with hardware semantics) and includes
an explicit patent grant. CERN-OHL-W v2 is weakly reciprocal — modifications
to the hardware sources must be released in source form, but components used
unmodified do not propagate the obligation. Both licenses are widely accepted
in the open-silicon ecosystem (lowRISC, OpenHW Group, CERN/CHIPS Alliance).

---

## 2. Software components — choose one of:

* **GNU Lesser General Public License v2.1 or later** (`LGPL-2.1-or-later`)
  See `LICENSE-SW-LGPL-2.1`.
* **BSD 2-Clause "Simplified" License** (`BSD-2-Clause`)
  See `LICENSE-SW-BSD-2-Clause`.
* **Apache License Version 2.0** (`Apache-2.0`)
  See `LICENSE-SW-Apache-2.0`.

Files in this class are tagged with:

```
SPDX-License-Identifier: LGPL-2.1-or-later OR BSD-2-Clause OR Apache-2.0
```

This applies to:

* The assembler (`asm/wavetensor_asm.py`) and its tests
* All cocotb testbenches (`test_*.py`)
* Build scaffolding (`Makefile`)
* Report parsers (`synth/parse_reports.py`)
* Future driver, hypervisor, and host-side daemon code that ships in this
  repository.

The triple license is offered for downstream license-stack compatibility:

* Linux-kernel-adjacent codebases naturally accept LGPL.
* BSD-derived ecosystems (FreeBSD, illumos) prefer BSD-2-Clause.
* Apache-Foundation-aligned projects pull in Apache-2.0 (with patent grant).

---

## 3. Documentation & ISA specification — single license:

* **Creative Commons Attribution 4.0 International** (`CC-BY-4.0`)
  See `LICENSE-DOC-CC-BY-4.0`.

Files in this class are tagged with:

```
SPDX-License-Identifier: CC-BY-4.0
```

This applies to:

* `claude.md` — project root specification document.
* `.claude-memos/*.md` — design memos (including `wt64v1_spec.md`,
  `wt64v1c_extension_plan.md`, etc.).
* `README.md` and any prose documentation added later.

The CC-BY-4.0 choice deliberately decouples the **WT64v1 ISA specification**
from RTL implementation licensing. This allows third parties to author
independent WT64v1-conformant implementations (RTL, simulator, FPGA bitstream,
silicon) without inheriting any obligation from this repository's RTL — they
need only cite the specification per CC-BY-4.0.

---

## 4. Patents

Patent grants are present in **Solderpad-2.1**, **CERN-OHL-W-2.0**, and
**Apache-2.0** options (clauses §3 / §3.4 / §3 respectively). The BSD-2-Clause
option does NOT carry an explicit patent grant; recipients choosing BSD-2 for
software components do so without contributor patent indemnity. The
LGPL-2.1-or-later option includes implicit patent rights through GPL §7 but
no explicit grant.

Contributors to WaveTensor agree to the patent grants of all licenses they
contribute under — see `CONTRIBUTING.md` for the contribution covenant.

---

## 5. Trademarks

"WaveTensor", "WT64v1", and the WT64v1-C extension naming are not yet
registered trademarks; future trademark policy will be published separately.

---

## 6. NOTICE file

When redistributing under Solderpad-2.1 or Apache-2.0, attribution
requirements (clause §4(d)) require preserving the contents of `NOTICE`. See
that file for required attributions and external dependency credits.
