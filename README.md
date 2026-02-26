# Claude-in-Chrome Tab Isolation

[Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) that
prevent multiple concurrent Claude Code sessions from interfering with each
other's Chrome tabs when using the
[Claude-in-Chrome](https://code.claude.com/docs/en/chrome) MCP server.

## What this is

Three shell scripts configured as Claude Code hooks. They ensure each session
creates its own dedicated Chrome tab and is pinned to it — the `PreToolUse` hook
rewrites the `tabId` field on every `mcp__claude-in-chrome__*` tool call.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with the
  Claude-in-Chrome MCP server already configured
- `jq` — `brew install jq` / `apt install jq`

## Install into your project

Copy the three hook scripts:

```bash
mkdir -p .claude/hooks
curl -fsSL https://raw.githubusercontent.com/neonwatty/claude-in-chrome-multiplexing/main/.claude/hooks/{session-start,capture-tab-id,enforce-tab-id}.sh \
  -o .claude/hooks/session-start.sh \
  -o .claude/hooks/capture-tab-id.sh \
  -o .claude/hooks/enforce-tab-id.sh
chmod +x .claude/hooks/*.sh
```

Then add these hook entries to your project's `.claude/settings.json` (merge
into existing `hooks` object if you already have one):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": ".claude/hooks/session-start.sh" }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "mcp__claude-in-chrome__tabs_create_mcp",
        "hooks": [{ "type": "command", "command": ".claude/hooks/capture-tab-id.sh" }]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "mcp__claude-in-chrome__.*",
        "hooks": [{ "type": "command", "command": ".claude/hooks/enforce-tab-id.sh" }]
      }
    ]
  }
}
```

Optionally copy `.claude/CLAUDE.md` for a soft reinforcement layer that reminds
Claude of the rules in-context.

## How it works

| Hook | Event | Purpose |
|------|-------|---------|
| `session-start.sh` | `SessionStart` | Generates a stable session key; injects tab-creation reminder |
| `capture-tab-id.sh` | `PostToolUse` (`tabs_create_mcp`) | Captures tab ID and writes to `~/.claude/chrome-sessions/{key}` |
| `enforce-tab-id.sh` | `PreToolUse` (`mcp__claude-in-chrome__*`) | Overrides `tabId` on every call; denies if no tab pinned |

Bootstrap tools (`tabs_context_mcp`, `tabs_create_mcp`) are whitelisted —
everything else is blocked until a tab has been created.

## Monitoring

Watch isolation in real time from a separate terminal:

```bash
tail -f ~/.claude/chrome-sessions/debug.log
```

Each line shows the session key, pinned tab ID, and tool being called.

## Known limitations

- **Separate sessions only** — isolation works across separate Claude Code
  sessions (different terminals). Task agents within a single session share the
  parent's tab.
- **Single tab per session** — each session is pinned to one tab.
- **Tab closure** — if the pinned tab is closed in Chrome, restart the session.
