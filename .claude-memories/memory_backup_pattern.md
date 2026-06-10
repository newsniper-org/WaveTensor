---
name: cc-memory-backup-session-resume-infrastructure-mirror-memory-claude-resume
description: "Every WaveTensor-family repo carries a Makefile-based memory mirror (`.claude-memories/`) and a CC SessionEnd hook that stamps session_id; `make claude-resume` re-attaches."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 09e02def-fe68-4449-8866-9db15ac81932
---

The user wants every repo in the WaveTensor / Y4 / Dasima family to ship a standard memory-backup and session-resume infrastructure. The pieces work together — adding one in isolation is half-broken.

**Why:** the user works across multiple repos and CC sessions; without these, memory drift and session-loss are easy. The convention was first established in WaveTensor (this repo) on 2026-05-05, then replicated to Y4 and Dasima.

**How to apply** when adding to a new repo, or fixing one of the pieces:

**1. Makefile targets** — append to the repo's Makefile (or create one):

```make
CC_MEMORY_SRC := $(HOME)/.claude/projects/-home-ybi-<repo>/memory
CC_MEMORY_DST := $(CURDIR)/.claude-memories
CC_RECENT_SID := $(CURDIR)/.claude-recent-session-id

.PHONY: mirror-memory mirror-memory-dry mirror-memory-clean
.PHONY: claude-resume claude-recent-id

mirror-memory:
	# rsync -a --delete with .git/ excluded; create dst if missing; emit ls of dst
mirror-memory-dry:
	# rsync --dry-run --itemize-changes
mirror-memory-clean:
	rm -rf $(CC_MEMORY_DST)

claude-resume:
	# read CC_RECENT_SID, error if missing/empty, exec claude --resume <sid>
claude-recent-id:
	# print CC_RECENT_SID contents
```

**Use `$(CURDIR)` not `$(PWD)`** — see `makefile_curdir_rule.md`. This bug was introduced and fixed on 2026-05-07.

**2. CC SessionEnd hook** — `.claude/settings.local.json`:

```json
"hooks": {
  "SessionEnd": [{
    "matcher": "",
    "hooks": [{
      "type": "command",
      "command": "sh /home/ybi/<repo>/.claude/session-end-hook.sh"
    }]
  }]
}
```

**3. SessionEnd hook script** — `.claude/session-end-hook.sh` (chmod +x):

```sh
#!/bin/sh
# Captures session_id from stdin JSON, writes to .claude-recent-session-id,
# then runs make mirror-memory. Best-effort; never blocks shutdown.
set -e
REPO=/home/ybi/<repo>
payload=$(cat 2>/dev/null || true)
if [ -n "$payload" ] && command -v jq >/dev/null 2>&1; then
    sid=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null || true)
    if [ -n "$sid" ] && [ "$sid" != "null" ]; then
        printf '%s\n' "$sid" > "$REPO/.claude-recent-session-id" 2>/dev/null || true
    fi
fi
cd "$REPO" 2>/dev/null && make mirror-memory >/dev/null 2>&1 || true
exit 0
```

**4. Pre-commit hook** — `.git/hooks/pre-commit` (chmod +x):

Runs `make mirror-memory`, then `git add` the `.claude-memories/` changes so the snapshot is captured in the commit. Never blocks (`|| true`).

**5. `.gitignore` entries**:

```
.claude/settings.local.json      # per-user CC settings
.claude/scheduled_tasks.lock     # per-user CC runtime
.claude-recent-session-id        # per-machine session stamp
```

`.claude-memories/` is **not** gitignored — it should be tracked so memory history is preserved across machines via git history.

**6. Smoke test** before declaring done:

```sh
make mirror-memory                                              # exits 0, mirrors files
printf '{"session_id":"test"}' | sh .claude/session-end-hook.sh # exits 0
cat .claude-recent-session-id                                   # prints "test"
rm .claude-recent-session-id
bash .git/hooks/pre-commit                                      # exits 0
git check-ignore .claude/settings.local.json .claude-recent-session-id  # both ignored
```

Applied in: WaveTensor (this repo), Y4, Dasima. Future spin-offs (per `spinoff_pattern.md`) inherit this automatically as part of the scaffold.
