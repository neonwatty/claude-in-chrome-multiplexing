#!/usr/bin/env bash
# session-start.sh — SessionStart hook
# Creates per-session state directory and injects tab-creation reminder.
set -euo pipefail

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
SOURCE=$(echo "$INPUT" | jq -r '.source // "startup"')

STATE_DIR="$HOME/.claude/chrome-sessions"
mkdir -p "$STATE_DIR"

# Prune stale session files (>24 h)
find "$STATE_DIR" -type f -mtime +1 -delete 2>/dev/null || true

# Fresh session → clear any leftover state for this session ID
case "$SOURCE" in
  startup|clear)
    rm -f "$STATE_DIR/$SESSION_ID"
    ;;
  resume|compact)
    # Keep existing state — tab may still be valid
    ;;
esac

# Inject context so Claude knows what to do
jq -n '{
  "additionalContext": "CHROME TAB ISOLATION ACTIVE: Before using any browser automation tools you MUST call tabs_context_mcp (to initialise the tab group) then tabs_create_mcp (to create your own dedicated tab). A PreToolUse hook will BLOCK every other claude-in-chrome tool call until a tab has been created and pinned for this session. Do NOT reuse tabs from other sessions."
}'
