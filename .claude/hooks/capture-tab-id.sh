#!/usr/bin/env bash
# capture-tab-id.sh — PostToolUse hook for tabs_create_mcp
# Extracts the new tab ID from the tool response and persists it.
#
# Uses CHROME_SESSION_KEY (set by session-start.sh via $CLAUDE_ENV_FILE) as the
# primary state-file key.  Falls back to session_id from the hook input, and
# also writes to BOTH keys so that enforce-tab-id.sh can always find the file
# regardless of which identifier it sees.
set -euo pipefail

INPUT=$(cat)

INPUT_SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
TOOL_RESPONSE=$(echo "$INPUT" | jq -r '.tool_response // empty')

STATE_DIR="$HOME/.claude/chrome-sessions"
mkdir -p "$STATE_DIR"

# Determine the canonical key (env var from SessionStart, else input session_id)
SESSION_KEY="${CHROME_SESSION_KEY:-$INPUT_SESSION_ID}"
STATE_FILE="$STATE_DIR/$SESSION_KEY"

# First tab created wins — don't overwrite on accidental re-creation
if [ -f "$STATE_FILE" ] && [ -s "$STATE_FILE" ]; then
  exit 0
fi

TAB_ID=""

# Strategy 1: JSON with top-level tabId field (most reliable)
TAB_ID=$(echo "$TOOL_RESPONSE" | jq -r '.tabId // empty' 2>/dev/null || true)

# Strategy 2: JSON with top-level id field
if [ -z "$TAB_ID" ]; then
  TAB_ID=$(echo "$TOOL_RESPONSE" | jq -r '.id // empty' 2>/dev/null || true)
fi

# Strategy 3: Text format "Tab ID: <number>"
if [ -z "$TAB_ID" ]; then
  TAB_ID=$(echo "$TOOL_RESPONSE" | grep -oiE 'Tab ID[: ]+([0-9]+)' | grep -oE '[0-9]+' | head -1 || true)
fi

# Strategy 4: Regex match "tabId": <number> in a string
if [ -z "$TAB_ID" ]; then
  TAB_ID=$(echo "$TOOL_RESPONSE" | grep -oE '"tabId"\s*:\s*([0-9]+)' | grep -oE '[0-9]+' | head -1 || true)
fi

# Strategy 5: Regex match "id": <number>
if [ -z "$TAB_ID" ]; then
  TAB_ID=$(echo "$TOOL_RESPONSE" | grep -oE '"id"\s*:\s*([0-9]+)' | grep -oE '[0-9]+' | head -1 || true)
fi

# Strategy 6: Response is just a bare number
if [ -z "$TAB_ID" ]; then
  STRIPPED=$(echo "$TOOL_RESPONSE" | tr -d '[:space:]')
  if [[ "$STRIPPED" =~ ^[0-9]+$ ]]; then
    TAB_ID="$STRIPPED"
  fi
fi

if [ -n "$TAB_ID" ]; then
  # Write to the canonical key
  echo "$TAB_ID" > "$STATE_FILE"

  # Also write to the input session_id key (belt-and-suspenders for the
  # PreToolUse/PostToolUse session-ID mismatch)
  if [ "$INPUT_SESSION_ID" != "$SESSION_KEY" ]; then
    echo "$TAB_ID" > "$STATE_DIR/$INPUT_SESSION_ID"
  fi

  # Debug log (append)
  LOG="$STATE_DIR/debug.log"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] key=$SESSION_KEY input_sid=$INPUT_SESSION_ID tab=$TAB_ID" >> "$LOG"
fi

exit 0
