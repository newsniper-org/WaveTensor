---
name: cc-memory-backup-session-resume-infrastructure-mirror-memory-claude-resume
description: "Every WaveTensor-family repo carries a Makefile-based memory mirror (`.claude-memories/`) and a CC SessionEnd hook that stamps session_id; `make claude-resume` re-attaches."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 09e02def-fe68-4449-8866-9db15ac81932
  modified: 2026-08-30T09:35:05.948Z
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

Applied in: WaveTensor (this repo), Y4, Dasima, wavetensor-drivers, wavetensor-sdk.
Future spin-offs (per `spinoff_pattern.md`) inherit this automatically as part of the scaffold.

---

## ⚠️ 거울을 고치면 조용히 사라진다 — 그리고 그것을 막는 기계가 없다

`mirror-memory` 는 **`rsync -a --delete` 정본 → 거울** 단방향이다. 그러므로
`.claude-memories/` 안의 파일을 직접 고치면 **다음 `mirror-memory` 가 되돌린다.**
그리고 **pre-commit 훅이 그것을 부르므로**, 거울에 쓴 편집은 대개 *바로 다음 커밋에서*
사라진다 — 커밋에는 그 편집이 안 담기고 실패도 안 난다.

**2026-08-30 실제로 아슬아슬했다.** 한 파도가 `wavetensor-drivers` 의
`.claude-memories/MEMORY.md` **한 파일만** 거울에 직접 썼다(3,066 B / 17:59). 정본은
2,712 B / 14:18 로 더 낡아 있었다. 다음 파도가 `mirror-memory` 를 그대로 돌렸으면
그 편집이 통째로 사라졌을 것이다. 다음 파도가 착수 시 거울↔정본을 대조해 **거울이
정본보다 새롭다**는 것을 알아채고 거울 내용을 정본에 먼저 반영해서 소실은 0 이었다.

**Why:** 실패가 아니라 **되돌림**이다. rsync 는 성공하고, 훅은 통과하고, 커밋은
착지한다. 잃은 것만 없다. 이 저장소군이 반복해서 만난 침묵의 또 다른 얼굴이다
([[yosys-bind-trap]] · [[differential-domain-trap]]).

**How to apply:**
1. **편집은 언제나 정본 디렉터리**(`$(HOME)/.claude/projects/-home-ybi-<repo>/memory`)
   에 한다. 저장소 안 `.claude-memories/` 는 **읽기 전용 산출물**로 다뤄라.
2. 서브에이전트에게 메모리 갱신을 시킬 때 **이 방향을 브리프에 명시**하라 — 저장소
   안 경로가 먼저 눈에 띄므로 기본값으로 그쪽을 고친다. 실제로 그렇게 됐다.
3. 착지 후 `diff -rq .claude-memories <정본>` 으로 무차이를 확인하라.
4. **게이트가 없다** — 「거울이 정본보다 새로우면 실패」를 재는 것이 `Makefile` 에도
   pre-commit 훅에도 없다. `mirror-memory` 앞에 mtime/내용 비교를 넣어 **덮어쓰기 전에
   멈추는** 것이 처방이고, 아직 아무 저장소에도 없다. 신설 여부는 사람 몫.
