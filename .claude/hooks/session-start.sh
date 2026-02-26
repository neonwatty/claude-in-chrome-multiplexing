#!/usr/bin/env bash
# session-start.sh — SessionStart hook
# Creates per-session state directory, generates a stable CHROME_SESSION_KEY
# (bridging the session-ID mismatch between PreToolUse and PostToolUse hooks),
# and injects the tab-creation reminder.
set -euo pipefail

INPUT=$(cat)

SOURCE=$(echo "$INPUT" | jq -r '.source // "startup"')

STATE_DIR="$HOME/.claude/chrome-sessions"
mkdir -p "$STATE_DIR"

# Prune stale session files (>24 h)
find "$STATE_DIR" -type f -mtime +1 -delete 2>/dev/null || true

case "$SOURCE" in
  startup|clear)
    # Fresh session → generate a new stable key and clear old state
    SESSION_KEY="chrome-$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$$-$(date +%s)")"
    rm -f "$STATE_DIR/$SESSION_KEY"

    # Persist the key so every subsequent hook in this session can read it
    if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
      echo "CHROME_SESSION_KEY=$SESSION_KEY" >> "$CLAUDE_ENV_FILE"
    fi
    ;;
  resume|compact)
    # Keep existing state — tab may still be valid.
    # CHROME_SESSION_KEY is already in the environment from the original start.
    ;;
esac

# Inject context so Claude knows what to do
jq -n '{
  "additionalContext": "CHROME TAB ISOLATION ACTIVE: Before using any browser automation tools you MUST call tabs_context_mcp (to initialise the tab group) then tabs_create_mcp (to create your own dedicated tab). A PreToolUse hook will BLOCK every other claude-in-chrome tool call until a tab has been created and pinned for this session. Do NOT reuse tabs from other sessions."
}'
