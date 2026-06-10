---
name: use-curdir-not-pwd-in-makefiles
description: "$(PWD) is inherited from the invoking shell — wrong target dir when `make -C <other-dir>` is used. $(CURDIR) is GNU Make's per-invocation cwd and always correct."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 09e02def-fe68-4449-8866-9db15ac81932
---

In any Makefile that may be invoked with `make -C <dir> <target>` (which CC sessions do routinely), use **`$(CURDIR)`** for paths computed relative to the Makefile's directory. **Do not use `$(PWD)`**.

**Why:** `$(PWD)` is a shell environment variable inherited from the parent shell that invoked `make`. `make -C /home/ybi/dasima target` from a shell whose `pwd` is `/home/ybi/WaveTensor` will set `$(PWD)` = `/home/ybi/WaveTensor` *inside* the dasima Makefile — wrong. `$(CURDIR)` is set by GNU Make itself to the working directory after `-C` is applied — `/home/ybi/dasima/` in this case.

**Failure mode (what actually happened on 2026-05-07):** Dasima's `mirror-memory` target used `$(PWD)/.claude-memories` as destination. When tested via `make -C /home/ybi/dasima mirror-memory` from the WaveTensor session's shell, Dasima's memory got rsync'd to `/home/ybi/WaveTensor/.claude-memories/` — overwriting WaveTensor's actual backup with Dasima's. Detected on first smoke test, fixed in two edits, WaveTensor backup restored via re-mirror.

**How to apply:**
- Any `:=` assignment using `$(PWD)` in any Makefile under `/home/ybi/{WaveTensor,Y4,dasima,…}` is a latent bug. Replace with `$(CURDIR)`.
- The `mirror-memory` and `claude-resume` targets in particular (see `memory_backup_pattern.md`) are most exposed because they're routinely invoked from hooks and other-cwd shells.
- The same rule applies to any future repo's Makefile created via the spin-off pattern.
- This is GNU Make specific behavior — POSIX `make` does not define `$(CURDIR)`, but every Makefile in this family targets GNU Make.

Fix applied to both `/home/ybi/WaveTensor/Makefile` and `/home/ybi/dasima/Makefile` on 2026-05-07. Y4's `justfile` is unaffected (just sets cwd to the justfile's dir natively).
