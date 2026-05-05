#!/bin/sh
# CC SessionEnd hook — fires when a Claude Code session terminates
# (Ctrl-C twice, /exit, /clear, logout, etc.).
#
# Two side effects:
#   1. Capture the session_id from the JSON payload on stdin and write it
#      to .claude-recent-session-id, so `make claude-resume` can pick it
#      up without the user having to copy/paste the resume command.
#   2. Run `make mirror-memory` to snapshot CC project memory into
#      .claude-memories/ before the session is gone.
#
# Never blocks session shutdown — every step is best-effort.
set -e

REPO=/home/ybi/WaveTensor
payload=$(cat 2>/dev/null || true)

if [ -n "$payload" ] && command -v jq >/dev/null 2>&1; then
    sid=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null || true)
    if [ -n "$sid" ] && [ "$sid" != "null" ]; then
        printf '%s\n' "$sid" > "$REPO/.claude-recent-session-id" 2>/dev/null || true
    fi
fi

cd "$REPO" 2>/dev/null && make mirror-memory >/dev/null 2>&1 || true

exit 0
