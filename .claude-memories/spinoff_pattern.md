---
name: wavetensor-memo-spin-off-scaffold-pattern
description: "When extracting a `.claude-memos/` idea into a separate sibling repo (like Y4 or Dasima), follow the locked scaffold pattern — Apache-2.0 single license, full doc set, memory seeds, mirror-memory infra, forward pointer in original memo."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 09e02def-fe68-4449-8866-9db15ac81932
---

When the user asks to extract a `.claude-memos/<idea>.md` into a separate sibling repo, apply this exact pattern. Y4 (from `host_a_custom_hypervisor.md`) and Dasima (from `notebook_web_ui.md`) both followed it.

**Why:** the user wants consistency across spin-offs so that scaffold doesn't need to be redesigned each time, future contributors find the same conventions, and CC sessions across repos behave identically (memory backup, session resume, hook wiring).

**How to apply** (the full pattern, in order):

1. **Repo location**: `/home/ybi/<repo-name>/` — sibling to WaveTensor / Y4, not nested.
2. **Single Apache-2.0 license** — not the multi-license stack WaveTensor uses for HW/SW/docs. Reasoning: spin-offs are self-contained software products; multi-license overhead only pays off for HW co-design.
3. **Top-level scaffold files** (file names exact):
   - `LICENSE` (Apache-2.0 full text — copy from `WaveTensor/LICENSE-SW-Apache-2.0`)
   - `NOTICE` (project intro + reuse manifest + trademark/naming notes)
   - `README.md` (project overview, status = scaffold-only, repo layout)
   - `CLAUDE.md` (CC auto-loaded context — 9 sections including architectural decisions, principles, cross-project relationships)
   - `CONTRIBUTING.md` (DCO sign-off required, SPDX header policy, code style by language, verification expectations)
   - `.gitignore` + `.editorconfig`
   - `Makefile` (mirror-memory + claude-resume targets — see `memory_backup_pattern.md`)
4. **Subdirectories**:
   - `docs/architecture.md` — canonical design (the *new* source of truth for this idea; the original WaveTensor memo becomes historical context)
   - `docs/licensing.md` — Apache-2.0 + trademark policy + cross-integration uniformity
   - `docs/phase_plan.md` — A → E phase progression with explicit entry triggers
   - `.claude/settings.local.json` + `.claude/session-end-hook.sh`
   - `.vscode/settings.json` (language-specific editor settings)
   - `.git/hooks/pre-commit` (chmod +x; calls `make mirror-memory` + auto-stages)
   - `third_party/.gitkeep` (Phase B+ upstream pins)
5. **Project memory at `/home/ybi/.claude/projects/-home-ybi-<repo-name>/memory/`** with seed entries:
   - `MEMORY.md` index (one line per seed, ~150 char each)
   - `<name>_basics.md` (project type) — what it is, status, license, SPDX pattern, Phase trigger
   - `<name>_canonical_doc.md` (project type) — docs/architecture.md is truth source; WT memo is historical
   - `<name>_design_decisions.md` (project type) — the architectural choices locked at Phase A
   - `<name>_relationships.md` (reference type) — sibling repo positions + ABI crossing rules
   - any naming / lineage rationale if non-obvious (`<name>_naming_lineage.md`)
6. **Forward pointer in the original WaveTensor memo**: add a callout block at the top of `WaveTensor/.claude-memos/<original>.md` saying "🛈 본 메모는 historical context 입니다 (date). 정전 디자인은 `/home/ybi/<repo-name>/docs/architecture.md`."
7. **WaveTensor's project memory**: add `<repo-name>_separate_repo.md` (project type) + an MEMORY.md index entry pointing to it.
8. **First commit is deferred until the user explicitly asks** — never auto-commit a fresh spin-off scaffold.

**Use this even if the spin-off feels small.** The pattern's per-file cost is fixed; not following it means inconsistency that compounds across spin-offs.

Reference applications:
- `/home/ybi/Y4/` (from `host_a_custom_hypervisor.md`, spun off 2026-05-04)
- `/home/ybi/dasima/` (from `notebook_web_ui.md`, spun off 2026-05-07)

Candidates still living in `WaveTensor/.claude-memos/` (future spin-off targets per earlier session discussion): `remote_accelerator_access.md` (→ Linux + Rust daemon repo), `sdk_architecture.md` (→ `wavetensor-sdk` repo), `imads_hpo_integration.md`.
