# Chrome Tab Isolation

This project uses Claude Code hooks to enforce Chrome tab isolation across
multiple concurrent sessions.  **The hooks are authoritative** — even if you
forget these rules, the PreToolUse hook will block or correct your calls.

## Rules

1. **Before any browser work**, call `tabs_context_mcp` (to initialise the tab
   group), then `tabs_create_mcp` (to create your own dedicated tab).
2. **Never pass `tabId` manually** — the `enforce-tab-id` hook automatically
   injects the correct value on every `mcp__claude-in-chrome__*` call.
3. **Never reuse a tab you did not create** — even if `tabs_context_mcp` shows
   existing tabs from other sessions, ignore them.  The hook pins you to the
   tab returned by YOUR `tabs_create_mcp` call.
4. If a browser tool call is **denied with "No Chrome tab pinned"**, that means
   you haven't created your tab yet.  Call `tabs_create_mcp` and retry.

## How It Works

| Hook | Event | Purpose |
|------|-------|---------|
| `session-start.sh` | SessionStart | Injects this reminder into context |
| `capture-tab-id.sh` | PostToolUse (`tabs_create_mcp`) | Stores your tab ID |
| `enforce-tab-id.sh` | PreToolUse (`mcp__claude-in-chrome__*`) | Overrides `tabId` on every call |

Session state is stored at `~/.claude/chrome-sessions/{session_id}` and
automatically cleaned up after 24 hours.
