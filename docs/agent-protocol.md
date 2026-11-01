# Agent socket protocol

How `wisp-agent` (and anything else) talks to Wisp about coding-agent sessions. Everything stays on the Mac.

## Transport

- A Unix stream socket at `~/Library/Application Support/Wisp/agents.sock` (`Wisp Dev/agents.sock` for development builds).
- One message per connection. The client writes the message, then closes its write side (`shutdown(SHUT_WR)`); the end of the stream marks the end of the message.
- Wisp drops anything over 1 MB.
- Messages that get no reply: Wisp closes the connection once it has read the message. Wait for that close (a few milliseconds) before closing your end; hanging up straight after writing can lose the message.
- Messages that get a reply: Wisp writes the reply and closes. An empty reply means "no decision".
- `statusline` messages are best effort. `wisp-agent` waits at most 50 ms for Wisp, so a snapshot sent while Wisp is busy (for example showing one of its own dialogs) can be lost; the next one catches up.

## Envelope

Every message is a JSON object:

```json
{
  "v": 1,
  "kind": "statusline",
  "source": "claude",
  "terminal": "com.mitchellh.ghostty",
  "payload": { }
}
```

| Field | Meaning |
|---|---|
| `v` | Protocol version. Wisp ignores messages with a newer version and logs it once. |
| `kind` | What the payload is (below). Unknown kinds are ignored and logged once. |
| `source` | `claude` or `codex`. Defaults to `claude`. |
| `terminal` | Optional bundle id of the app the agent runs in, so Wisp can bring it forward. |
| `payload` | The agent's own JSON, unchanged. |

## Kinds

| kind | Payload | Reply |
|---|---|---|
| `hook` | The hook's stdin JSON from Claude Code or Codex. | Only for `PermissionRequest`: the hook's stdout (an allow or deny decision), or empty to let the agent ask in the terminal. Wisp holds the connection open until the user answers, up to 110 s. |
| `statusline` | Claude Code's statusLine stdin JSON (`session_id`, `model`, `cost`, `context_window`, `workspace`, ...). | None. |
| `tool` | Tool activity: the stdin JSON of PreToolUse, PostToolUse or SubagentStop. The helper sends it without waiting (50 ms, like `statusline`), so a tool call never waits on Wisp. | None. |
| `query` | `{"query": "status"}` or `{"query": "spend"}`, from `wisp status`, `wisp watch` and `wisp spend`. | A report as JSON (below). An unknown query gets an empty reply. |

## Query reply

The reply to `query` is what `wisp status --json` and `wisp spend --json` print. Keys are only ever added, and a value Wisp doesn't know is `null` rather than missing.

| Key | Value |
|---|---|
| `v` | Report version, 1. |
| `generated` | ISO 8601 time. |
| `hidden` | Why details are hidden ("during a call"), or `null`. While hidden, `id` and `folder` are `null` and `tool` is only its verb ("Running a command"). |
| `sessions` | Newest activity first. Each has `id`, `project`, `branch`, `agent`, `state` (`working`, `needs you`, `needs approval`, `done`, `idle` or `compacting`), `model`, `contextPercent`, `cost`, `costIsReal`, `tool`, `toolSeconds`, `turnSeconds` and `folder`. |
| `spend` | For `spend`: `today`, `week`, `days` (the last 7, oldest first) and `projects` (`project`, `today`, `week`, most first; spend from before projects were kept is "Other projects"). `null` for `status`. |

## Older format

Before the envelope, the helper sent the hook's JSON directly with two keys added: `wisp_source` and `wisp_terminal`. Wisp still accepts that: a message without `v` is read as a hook.

## Hooks Wisp installs

Claude Code (`~/.claude/settings.json`): SessionStart, UserPromptSubmit, PermissionRequest (120 s timeout), Notification, Stop, SessionEnd, PreCompact and PostCompact (both `"async": true`), with tool activity on PreToolUse, PostToolUse and SubagentStop (all `"async": true`), plus `statusLine` running `wisp-agent statusline`.

Codex (`~/.codex/hooks.json`): the same hooks without Notification, and no status bar (Codex has no external status line command).

The statusLine command keeps any bar you had before inside it (`--saved '<command>'` or `--chain '<command>'`), so Wisp can put it back exactly.
