#!/usr/bin/env bash
# capture-tab-id.sh — PostToolUse hook for tabs_create_mcp
# Extracts the new tab ID from the tool response and persists it
# so that enforce-tab-id.sh can pin all subsequent calls to it.
set -euo pipefail

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
TOOL_RESPONSE=$(echo "$INPUT" | jq -r '.tool_response // empty')

STATE_DIR="$HOME/.claude/chrome-sessions"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/$SESSION_ID"

# First tab created wins — don't overwrite on accidental re-creation
if [ -f "$STATE_FILE" ] && [ -s "$STATE_FILE" ]; then
  exit 0
fi

TAB_ID=""

# Strategy 1: JSON with tabId field
TAB_ID=$(echo "$TOOL_RESPONSE" | jq -r '.tabId // empty' 2>/dev/null || true)

# Strategy 2: JSON with id field
if [ -z "$TAB_ID" ]; then
  TAB_ID=$(echo "$TOOL_RESPONSE" | jq -r '.id // empty' 2>/dev/null || true)
fi

# Strategy 3: Nested tabId anywhere in the object
if [ -z "$TAB_ID" ]; then
  TAB_ID=$(echo "$TOOL_RESPONSE" | jq -r '[.. | .tabId? // empty] | map(select(. != "")) | first // empty' 2>/dev/null || true)
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
  echo "$TAB_ID" > "$STATE_FILE"

  # Debug log (append)
  LOG="$STATE_DIR/debug.log"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] session=$SESSION_ID tab=$TAB_ID" >> "$LOG"
fi

exit 0
