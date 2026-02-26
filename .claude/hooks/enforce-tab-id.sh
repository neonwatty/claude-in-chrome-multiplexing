#!/usr/bin/env bash
# enforce-tab-id.sh — PreToolUse hook for mcp__claude-in-chrome__*
#
# • Bootstrap tools (tabs_context_mcp, tabs_create_mcp) are always allowed
#   through without modification.
# • All other claude-in-chrome tools are DENIED until a tab has been captured,
#   and once a tab exists, the stored tabId is merged into tool_input so every
#   call is automatically pinned to the session's dedicated tab.
#
# Uses CHROME_SESSION_KEY (set by session-start.sh) as the primary lookup key,
# falling back to session_id from the hook input.
set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')
INPUT_SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')

# ── Bootstrap tools: allow through without tab pinning ──────────────
case "$TOOL_NAME" in
  mcp__claude-in-chrome__tabs_context_mcp|mcp__claude-in-chrome__tabs_create_mcp)
    jq -n '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow"
      }
    }'
    exit 0
    ;;
esac

# ── All other chrome tools: enforce tab pinning ─────────────────────
STATE_DIR="$HOME/.claude/chrome-sessions"

# Try the canonical key first, then fall back to input session_id
SESSION_KEY="${CHROME_SESSION_KEY:-$INPUT_SESSION_ID}"
STATE_FILE="$STATE_DIR/$SESSION_KEY"

# Fallback: if the canonical key file doesn't exist, try input session_id
if { [ ! -f "$STATE_FILE" ] || [ ! -s "$STATE_FILE" ]; } && [ "$INPUT_SESSION_ID" != "$SESSION_KEY" ]; then
  STATE_FILE="$STATE_DIR/$INPUT_SESSION_ID"
fi

if [ ! -f "$STATE_FILE" ] || [ ! -s "$STATE_FILE" ]; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "No Chrome tab pinned for this session. You MUST call tabs_create_mcp first to create a dedicated tab before using any other browser tools."
    }
  }'
  exit 0
fi

TAB_ID=$(tr -d '[:space:]' < "$STATE_FILE")

# Validate that the stored value is a number
if ! [[ "$TAB_ID" =~ ^[0-9]+$ ]]; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "Stored tab ID is invalid. Call tabs_create_mcp to create a new dedicated tab."
    }
  }'
  exit 0
fi

# Merge the pinned tabId into the original tool input (preserving all
# other parameters) and allow the call.
TOOL_INPUT=$(echo "$INPUT" | jq '.tool_input // {}')
UPDATED=$(echo "$TOOL_INPUT" | jq --argjson tabId "$TAB_ID" '. + {"tabId": $tabId}')

jq -n --argjson updated "$UPDATED" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "updatedInput": $updated
  }
}'
