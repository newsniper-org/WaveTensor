---
name: Y4 hypervisor lives in its own local repo
description: Y4 (the WaveTensor host hypervisor) is developed in /home/ybi/Y4 as a separate git repo, single-licensed Apache-2.0; WaveTensor's host_a_custom_hypervisor.md is kept as historical context only.
type: project
originSessionId: 09e02def-fe68-4449-8866-9db15ac81932
---
Y4 development was lifted out of WaveTensor into its own local git repo at `/home/ybi/Y4`.

**Why:** Y4 is a separate product asset (hypervisor for every WaveTensor accelerator form factor). It has a different license stance (single Apache-2.0 vs WaveTensor's multi-license HW/SW/doc split), different reuse manifest (seL4/Tock/DragonFlyBSD/Redox), and a long-horizon Phase 0→4 roadmap that should not be entangled with WaveTensor's RTL milestones.

**How to apply:**
- New Y4 design / code / docs go to `/home/ybi/Y4`, not `WaveTensor/.claude-memos/`.
- The WaveTensor memo `WaveTensor/.claude-memos/host_a_custom_hypervisor.md` stays as historical context but is no longer the canonical design source. Canonical doc is `/home/ybi/Y4/docs/architecture.md` (Apache-2.0).
- When changing Y4 design, update Y4's `docs/architecture.md` first; only sync to the WaveTensor memo if the change affects WaveTensor-side decisions (HIU integration shape, lease ABI).
- Y4's bootloader priority: Limine (1st, BSD-2-Clause) → GRUB2-BLS (2nd) → U-Boot (3rd) → coreboot (4th). systemd-boot and rEFInd are explicitly excluded for Y4.
- Y4 repo is not yet committed (initial scaffold only); first commit is deferred until the user explicitly asks.
