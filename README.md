# Claude-in-Chrome Tab Isolation

Hooks-based enforcement of Chrome tab isolation for multi-session Claude Code
usage with the [Claude-in-Chrome](https://code.claude.com/docs/en/chrome) MCP
server.

## Problem

When running multiple Claude Code sessions that use Claude-in-Chrome for browser
automation, sessions interfere with each other because they share a single
"Claude (MCP)" tab group. One session can accidentally navigate, click, or type
in another session's tab, causing unpredictable failures.

## Solution

Three Claude Code hooks work together to **programmatically enforce** that each
session creates its own dedicated tab and uses only that tab:

```
┌─────────────────────────────────────────────────────────────┐
│  SessionStart hook                                          │
│  → Injects context: "create a tab before browser work"      │
│  → Creates ~/.claude/chrome-sessions/ state dir             │
└──────────────────────────┬──────────────────────────────────┘
                           │
              Claude calls tabs_create_mcp
                           │
┌──────────────────────────▼──────────────────────────────────┐
│  PostToolUse hook  (matcher: tabs_create_mcp)               │
│  → Extracts tab ID from response                            │
│  → Writes to ~/.claude/chrome-sessions/{session_id}         │
└──────────────────────────┬──────────────────────────────────┘
                           │
              Claude calls any chrome tool
                           │
┌──────────────────────────▼──────────────────────────────────┐
│  PreToolUse hook  (matcher: mcp__claude-in-chrome__*)       │
│  → Reads stored tab ID                                      │
│  → DENIES if no tab pinned yet                              │
│  → OVERRIDES tabId in tool input with stored value          │
└─────────────────────────────────────────────────────────────┘
```

The PreToolUse hook is the enforcement layer — it rewrites the `tabId` field on
**every** claude-in-chrome tool call, so even if the model "forgets" which tab
it should be using, the hook corrects it.

## Quick start

```bash
git clone https://github.com/jermwatt/claude-in-chrome-multiplexing.git
cd claude-in-chrome-multiplexing
chmod +x .claude/hooks/*.sh
# Hooks are configured in .claude/settings.json — just use Claude Code
```

## Adopt in your own project

1. Copy `.claude/hooks/` into your project's `.claude/hooks/` directory
2. Merge the hook entries from `.claude/settings.json` into your project's
   `.claude/settings.json`
3. Optionally copy `.claude/CLAUDE.md` for the soft reinforcement layer

## Dependencies

- **jq** — `brew install jq` / `apt install jq`
- **Claude Code** with the Claude-in-Chrome MCP server configured

## How the hooks work

| File | Event | Matcher | Purpose |
|------|-------|---------|---------|
| `session-start.sh` | `SessionStart` | `*` | Remind Claude to create a tab; prune stale state |
| `capture-tab-id.sh` | `PostToolUse` | `tabs_create_mcp` | Extract and persist the new tab ID |
| `enforce-tab-id.sh` | `PreToolUse` | `mcp__claude-in-chrome__.*` | Inject stored `tabId`; deny if missing |

### Bootstrap whitelist

`tabs_context_mcp` and `tabs_create_mcp` are allowed through without a stored
tab ID (they're needed to create the tab in the first place). All other
claude-in-chrome tools are blocked until a tab has been pinned.

### First-write wins

`capture-tab-id.sh` only writes the session file if it doesn't already exist.
This prevents accidental tab switches if `tabs_create_mcp` is called more than
once.

### Automatic cleanup

`session-start.sh` prunes session files older than 24 hours on every new
session start.

## Session state

Per-session tab IDs are stored as plain-text files:

```
~/.claude/chrome-sessions/
├── abc123          # contains "42" (the tab ID)
├── def456          # contains "87"
└── debug.log       # append-only log of all captures
```

## Known limitations

- **Separate sessions only**: Isolation works across separate Claude Code
  sessions (different terminal windows). Task agents and agent teams within a
  single session share the parent's session key and therefore share a tab.
  `$CLAUDE_ENV_FILE` writes from `SubagentStart` hooks do not propagate to
  subsequent hooks, so per-subagent isolation is not currently achievable.
- **Tab closure mid-session**: If the pinned tab is closed in Chrome, calls will
  fail with a stale tab ID. Restart the Claude Code session to recover.
- **Response format variance**: The `tabs_create_mcp` response format isn't
  formally specified. `capture-tab-id.sh` tries six extraction strategies but
  may need adjustment if the format changes.
- **Single tab per session**: Each session is pinned to one tab. Multi-tab
  workflows within a single session aren't supported.

## Contributing

PRs welcome. Please ensure `shellcheck` passes on all hook scripts and add
tests in the CI workflow for new behavior.
