---
name: wavetensor-sdk-lives-in-its-own-local-repo
description: "WaveTensor SDK (Rust core + 4 FFI bindings, extracted from sdk_architecture.md) is developed at /home/ybi/wavetensor-sdk as a separate git repo, single Apache-2.0; WaveTensor's sdk_architecture.md is now historical context only."
metadata: 
  node_type: memory
  type: project
  originSessionId: 09e02def-fe68-4449-8866-9db15ac81932
---

WaveTensor SDK development was extracted out of WaveTensor's `.claude-memos/sdk_architecture.md` into its own local git repo at `/home/ybi/wavetensor-sdk` on 2026-07-10.

**Why:** SDK is a separate product asset (Rust core + 4-language FFI bindings for the WaveTensor accelerator). It has a different license stance (single Apache-2.0 vs WaveTensor's multi-license HW/SW/docs split), a different toolchain focus (cargo + maturin + cargo-component + jextract), and its own polyrepo landscape (planned `wavetensor-daemon` for first RPC client, `wt-notebook-ext` for Dasima glue). It also functions as the natural common consumer for `imads-hpo` (same distribution model twin).

**How to apply:**
- New SDK design / code / docs go to `/home/ybi/wavetensor-sdk`, not `WaveTensor/.claude-memos/`.
- The WaveTensor memo `WaveTensor/.claude-memos/sdk_architecture.md` stays as historical context (now marked with a forward pointer at the top); it is no longer the canonical design source. Canonical doc is `/home/ybi/wavetensor-sdk/docs/architecture.md` (Apache-2.0).
- WaveTensor's Python reference assembler at `asm/wavetensor_asm.py` **stays in the WaveTensor repo through Phase B–C of SDK** — it is the bit-equivalence reference the Rust port validates against. Phase E of SDK deprecates it (with 6-month grace period). Do not delete or heavily modify it during SDK Phase B–C.
- SDK spin-off is the third under the spin-off pattern (`spinoff_pattern.md`). Remaining candidates in `.claude-memos/`: `remote_accelerator_access.md` (→ future `wavetensor-daemon` repo), `imads_hpo_integration.md` (integration with existing `imads-hpo`).
- WaveTensor SDK repo is not yet committed (initial scaffold only); first commit is deferred until the user explicitly asks.

**ABI crossings** (rare cases where a SDK change forces WaveTensor changes):
- **WT64v1 ISA change** — 4-way lockstep: SDK's `wavetensor-asm` + `wavetensor-core::types` + WaveTensor's Python assembler + WaveTensor cocotb tests.
- **HIU ABI change** — SDK's `PcieTransport` (Phase D) + Y4 lease capability + WaveTensor RTL HIU module. Lockstep.
