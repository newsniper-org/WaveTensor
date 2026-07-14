---
name: wavetensor-drivers-lives-in-its-own-local-repo-parent-per-kernel-submodules
description: Formally-verified multi-kernel device drivers for WaveTensor; developed at /home/ybi/wavetensor-drivers as parent repo with per-kernel git submodules; not a spin-off from a specific WaveTensor memo — new project born from career + product + formal-verification intersection.
metadata: 
  node_type: memory
  type: project
  originSessionId: 09e02def-fe68-4449-8866-9db15ac81932
---

wavetensor-drivers is a new sibling repo at `/home/ybi/wavetensor-drivers`, initialized on 2026-07-14.

**Not a memo spin-off.** Unlike Y4 / Dasima / wavetensor-sdk (each spun off from a specific `.claude-memos/*.md`), the driver project is a new sibling born from a 3-motivation intersection:
1. Career development (résumé) — Linux kernel driver + formal verification is a rare industry combination.
2. Product need — SDK's `PcieTransport` (SDK Phase D) needs a real host driver; `wavetensor-daemon` (planned) also.
3. Formal-first alignment — extends Y4's rigor to the host boundary.

Enabled by the FPGA hardware wait window (Stage 1 ULX3S quote pending) — driver is 100% hardware-independent via libvfio-user QEMU emulation.

**Structure:** parent repo (this) hosts `common/` + docs + LICENSE; per-kernel drivers are git submodules (`wavetensor-driver-linux`, `-freebsd`, `-redox`, `-windows`). Only `wavetensor-driver-linux` planned to open at Phase P3; others deferred.

**Related WaveTensor memos** (referenced but not spun off):
- `.claude-memos/remote_accelerator_access.md` — daemon architecture; driver is one piece of that stack
- `.claude-memos/board_hw_plan.md` — created the wait window
- `.claude-memos/wt64v1_spec.md` — ISA (driver treats programs as opaque bytes)

**License structure (Alt A — no custom license):**
- `common/**` = Apache-2.0 OR BSD-2-Clause-Patent (recipient chooses)
- `wavetensor-driver-linux/**` = GPL-2.0-or-later (kernel transitivity)
- Ethical concerns via separate `ETHICS.md` + `CODE_OF_CONDUCT.md` (post-scaffold P0.5)

**Formal verification stack (5 layers):**
- TLA+ + TLC (protocol) → Isabelle/HOL (refinement) → Frama-C ACSL (C contracts) → Frama-C WP + CBMC (C verification) → Kani (Rust userspace)

**How to apply:**
- New driver design / code / docs go to `/home/ybi/wavetensor-drivers`, not WaveTensor's `.claude-memos/`.
- WaveTensor RTL side: future `Top_Pcie.v` (or equivalent host-facing wrapper) must match `wavetensor-drivers/docs/pcie_host_interface.md` — this is a lockstep ABI crossing.
- SDK Phase B runs in lockstep with driver P1-P5 (see `wavetensor-drivers/docs/phase_plan.md` §"SDK 병행").
- Y4 lease capability integration (when Y4 resumes) → `wavetensor-driver-redox` submodule.
- Driver repo is not yet committed (initial scaffold only); first commit deferred until user explicitly asks.

**ABI crossings** (driver → WaveTensor RTL):
- PCIe host interface spec change → WaveTensor RTL host-facing wrapper must update
- HIU interface changes (TRNG output format, partition semantics) → shadow region BAR mapping updates
