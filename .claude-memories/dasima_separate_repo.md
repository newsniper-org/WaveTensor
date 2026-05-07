---
name: Dasima notebook kit lives in its own local repo
description: Dasima (the generic notebook kit extracted from notebook_web_ui.md) is developed at /home/ybi/dasima as a separate git repo, single Apache-2.0; WaveTensor's notebook_web_ui.md is now historical context only.
type: project
originSessionId: 09e02def-fe68-4449-8866-9db15ac81932
---
Dasima development was extracted out of WaveTensor's `.claude-memos/notebook_web_ui.md` into its own local git repo at `/home/ybi/dasima` on 2026-05-07.

**Why:** Dasima is a separate product asset (generic accelerator-agnostic notebook environment kit, JupyterLab + Matrix.org + room-anchored ACL). It has a different license stance (single Apache-2.0 vs WaveTensor's multi-license HW/SW/doc split), different architecture (Matrix-shaped abstractions, no homeserver mods, Hybrid β ACL, DB+blob), and a polyrepo plan (`dasima` core + `dasima-integration-matrix` + `dasima-integration-claude-code` + `dasima-integration-backblaze-b2`). It is also intended to outlive WaveTensor's relevance — Marimo competitor positioning means it has its own roadmap independent of accelerator development.

**How to apply:**
- New Dasima design / code / docs go to `/home/ybi/dasima`, not `WaveTensor/.claude-memos/`.
- The WaveTensor memo `WaveTensor/.claude-memos/notebook_web_ui.md` stays as historical context (now marked with a forward pointer at the top); it is no longer the canonical design source. Canonical doc is `/home/ybi/dasima/docs/architecture.md` (Apache-2.0).
- WaveTensor-specific UI (WT64v1 ISA visualisation, HIU dashboard, `%%wt` magic, synth dashboard, PE topology heatmap) is **NOT** in Dasima — it goes into a future `wt-notebook-ext` repo that will import Dasima core + integrations + WaveTensor SDK. Do not put accelerator-specific code into Dasima.
- When a task mentions "notebook UI" in a WaveTensor session, check whether it's about the historical memo (CC-BY-4.0, archival) or a planned `wt-notebook-ext` extension (Apache-2.0, future). The two are distinct.
- Dasima repo is not yet committed (initial scaffold only); first commit is deferred until the user explicitly asks.
