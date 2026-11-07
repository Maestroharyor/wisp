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
  "terminalContext": { "TMUX_PANE": "%3", "tty": "/dev/ttys004" },
  "payload": { }
}
```

| Field | Meaning |
|---|---|
| `v` | Protocol version. Wisp ignores messages with a newer version and logs it once. |
| `kind` | What the payload is (below). Unknown kinds are ignored and logged once. |
| `source` | `claude`, `codex`, `gemini` or `cursor` (an agent in `AgentAdapters`). Defaults to `claude` when missing. Any other value is ignored and logged once, and a hook from it gets an empty reply. |
| `terminal` | Optional bundle id of the app the agent runs in, so Wisp can bring it forward. |
| `terminalContext` | Optional object saying where in the terminal the agent runs, so Wisp can bring forward the exact pane or tab (below). Sent with `hook`, `tool` and `statusline`. |
| `payload` | The agent's own JSON, unchanged. |

## Terminal context

`wisp-agent` copies these environment variables, when set, and nothing else from the environment. Every value is a string; empty values and values over 512 bytes are left out, and so is the whole object when nothing is set. Keys are only ever added; Wisp ignores keys it doesn't know and values that aren't strings, and older Wisps ignore the whole object.

| Key | From | Used for |
|---|---|---|
| `TMUX` | `$TMUX` (socket path, server pid, session index) | The tmux server to talk to (`tmux -S <socket>`). |
| `TMUX_PANE` | `$TMUX_PANE` (`%3`) | `select-window` and `select-pane` on that pane; `switch-client` when no client shows its session. |
| `ITERM_SESSION_ID` | `$ITERM_SESSION_ID` (`w0t1p0:<GUID>`) | Selecting the iTerm2 session whose AppleScript `id` is the GUID. |
| `TERM_SESSION_ID` | `$TERM_SESSION_ID` | Sent for completeness; not used yet. |
| `KITTY_WINDOW_ID` | `$KITTY_WINDOW_ID` | Sent for completeness; kitty also needs its remote control socket, which isn't sent, so kitty is only brought forward. |
| `WEZTERM_PANE` | `$WEZTERM_PANE` | `wezterm cli activate-pane --pane-id`. |
| `TERM_PROGRAM` | `$TERM_PROGRAM` | Naming the terminal when `terminal` is missing. |
| `tty` | The agent process's controlling terminal (`/dev/ttys004`), from the process table | Selecting the tab in Terminal, iTerm2 (without a session id) and Ghostty, whose AppleScript dictionaries expose each tab's tty. |

Inside tmux, the tty and the host terminal's ids belong to tmux's pane or are left over from when the tmux server started, so Wisp finds the outer tab from the tty of the tmux client showing the pane instead. Wisp skips the tmux step when `terminal` names an editor (editors started from a tmux shell pass `TMUX` on to their own terminals), and when tmux reports a `pane_tty` other than the context's `tty` (a shell started from tmux keeps `TMUX` and `TMUX_PANE`); the agent's own `tty` and ids then name the tab.

## Kinds

| kind | Payload | Reply |
|---|---|---|
| `hook` | The hook's stdin JSON from Claude Code, Codex, Gemini CLI or Cursor. | Only for `PermissionRequest`: the hook's stdout (an allow or deny decision), or empty to let the agent ask in the terminal. Wisp holds the connection open until the user answers, up to 110 s. For Cursor, which reads every hook's stdout as JSON, the helper prints a "carry on" reply whenever the reply is empty or Wisp can't be reached: `{"continue":true}` for beforeSubmitPrompt, `{}` for the rest. |
| `statusline` | Claude Code's statusLine stdin JSON (`session_id`, `model`, `cost`, `context_window`, `workspace`, ...). | None. |
| `tool` | Tool activity: the stdin JSON of PreToolUse, PostToolUse or SubagentStop. The helper sends it without waiting (50 ms, like `statusline`), so a tool call never waits on Wisp. | None. |
| `query` | `{"query": "status"}` or `{"query": "spend"}`, from `wisp status`, `wisp watch` and `wisp spend`. | A report as JSON (below). An unknown query gets an empty reply. |
| `activity` | A live activity from `wisp activity` or your own script (below). | `{"ok":true}` once Wisp has taken it, or `{"ok":false,"error":"..."}` when it understood the message but couldn't act on it (an `update` for an id that isn't showing, without a `title`). An invalid payload, or a Wisp too old to know the kind, gets an empty reply. |

## Activity payload

`source` isn't used for `activity`, but like every message it must be a known source or left out.

```json
{"action": "start", "id": "build", "title": "Building", "symbol": "hammer.fill", "progress": 0.4}
```

| Key | Meaning |
|---|---|
| `action` | `start` (show or replace), `update` (change only the fields given; with a `title` it starts an unknown id) or `end`. |
| `id` | Letters, digits, `.`, `-` and `_`, up to 64 characters. Required. |
| `title` | Up to 60 characters (and 240 Unicode scalars) after cleaning: control characters such as newlines and the line and paragraph separators become spaces, format characters such as bidi overrides are removed (the joiner, non-joiner and the tag characters of subdivision flags stay), then it's trimmed. Required for `start`. |
| `symbol` | One of the SF Symbols listed by `wisp activity --help`. Defaults to `bolt.fill`. |
| `progress` | A number from 0 to 1. Leave it out for an activity with no measurable end. |

The same rules apply to `wisp activity` and `wisp://activity/...` links (`WispCore/ExternalCommand.swift`). The activity touched last shows in the notch. Each lasts 15 minutes after its last `start` or `update`, then goes away on its own; at most 8 are kept, dropping the oldest.

## Query reply

The reply to `query` is what `wisp status --json` and `wisp spend --json` print. Keys are only ever added, and a value Wisp doesn't know is `null` rather than missing.

| Key | Value |
|---|---|
| `v` | Report version, 1. |
| `generated` | ISO 8601 time. |
| `hidden` | Why details are hidden ("during a call"), or `null`. While hidden, `id` and `folder` are `null` and `tool` is only its verb ("Running a command"). |
| `sessions` | Newest activity first. Each has `id`, `project`, `branch`, `agent`, `state` (`working`, `needs you`, `needs approval`, `done`, `idle` or `compacting`), `model`, `contextPercent`, `cost`, `costIsReal`, `tool`, `toolSeconds`, `turnSeconds` and `folder`. |
| `limits` | Plan usage windows: Claude Code's from the latest status line, then Codex's from the latest rollout read, five-hour first within each. `window` (`fiveHour` or `sevenDay`), `percent`, `resets`, `full` (when it runs out at the last hour's pace, if before it resets; otherwise `null`) and `agent` (`Claude Code` or `Codex`; missing from older Wisps). An empty list when none were reported; missing from older Wisps. |
| `spend` | For `spend`: `today`, `week`, `days` (the last 7, oldest first) and `projects` (`project`, `today`, `week`, most first; spend from before projects were kept is "Other projects"; a project is its folder name, so two folders with the same name share a row). `null` for `status`. |

## Older format

Before the envelope, the helper sent the hook's JSON directly with two keys added: `wisp_source` and `wisp_terminal`. Wisp still accepts that: a message without `v` is read as a hook, and one whose `wisp_source` names no known agent is ignored.

## Hooks Wisp installs

Each agent's hook file, events and reply format come from its adapter in `WispCore/AgentAdapter.swift`.

Claude Code (`~/.claude/settings.json`): SessionStart, UserPromptSubmit, PermissionRequest (120 s timeout), Notification, Stop, SessionEnd, PreCompact and PostCompact (both `"async": true`), with tool activity on PreToolUse, PostToolUse and SubagentStop (all `"async": true`), plus `statusLine` running `wisp-agent statusline`.

Codex (`~/.codex/hooks.json`, command `wisp-agent --source codex`): the same hooks without Notification. Tool activity hooks are `"async": true`; the compaction hooks stay synchronous, as installed before Codex documented `async`, so hooks already trusted in `/hooks` don't change. No status bar (Codex has no external status line command). Codex asks you to trust new or changed hooks once in `/hooks`.

Gemini CLI (`~/.gemini/settings.json`, command `wisp-agent --source gemini`): SessionStart, BeforeAgent, Notification, AfterTool, AfterAgent, SessionEnd and PreCompress, with tool activity adding BeforeTool. AfterTool is always installed: it's the first event after a tool confirmation answered in the terminal, so the session leaves Needs you. Timeouts are in milliseconds there (5000), and Gemini CLI has no `async`, so tool hooks are synchronous: each tool call waits for one helper launch (two with tool activity on), which sends the event as `tool` and exits without waiting for Wisp. The helper decides `tool` from the event as the adapter reads it, not from the tool activity list. Monitor only: no PermissionRequest hook, no `--timeout`, and push never makes these hooks outdated. Wisp reads Gemini's event names as its own: BeforeAgent is a prompt, AfterAgent is Stop, PreCompress is PreCompact, BeforeTool and AfterTool are tool activity, and a Notification of type `ToolPermission` is Needs you. Hooks run only while `hooksConfig.enabled` is on, the default.

Cursor (`~/.cursor/hooks.json`, command `wisp-agent --source cursor`): sessionStart, beforeSubmitPrompt, stop, sessionEnd and preCompact, with tool activity adding postToolUse. The file is `{"version": 1, "hooks": {...}}` with a flat list of handlers (`command`, `timeout` in seconds) under each event, no matcher groups; Wisp adds `version: 1` only when the file has none. Monitor only, and Wisp installs none of Cursor's permission hooks (preToolUse, beforeShellExecution, beforeMCPExecution, beforeReadFile, subagentStart): Cursor blocks the action when one of those prints output it can't read, beforeShellExecution and beforeMCPExecution enforce only deny today, and preToolUse has no `ask` to hand a call back to Cursor's prompt (and would hold every tool call). The helper answers every Cursor hook with `{"continue":true}` for beforeSubmitPrompt and `{}` for the rest, including when Wisp isn't running. Wisp reads `conversation_id` as the session, the first of `workspace_roots` as the project (falling back to `cwd`), beforeSubmitPrompt as a prompt, stop as Stop and postToolUse as a finished tool, shown in the pill as the last tool. Cursor has no event for a prompt waiting on you, so a Cursor session never shows Needs you.

**Claude Code hooks run by Cursor.** Cursor also runs the hooks in `~/.claude/settings.json` and a project's `.claude/settings.json` and `.claude/settings.local.json` (Settings › Agents › Third-Party Imports, on by default), mapping SessionStart, UserPromptSubmit, Stop, SessionEnd, PreCompact, PreToolUse, PostToolUse and SubagentStop to its own events. With Claude Code connected, Wisp's Claude Code hooks would then report every Cursor session a second time, as Claude Code. Their payload is Cursor's and carries `cursor_version`, which Claude Code never sends, so the helper drops any Claude Code hook call with that field without contacting Wisp, and answers it with Cursor's "carry on" reply (`{"continue":true}` for the prompt hook, `{}` otherwise, including PreToolUse, where an empty object carries no verdict). Cursor sessions show only through Cursor's own hooks, once.

**Approval wait.** By default the PermissionRequest hook has a 120 s timeout and the command takes no extra argument. While phone push is on (Settings › Phone) the wait is the "Wait for an answer" setting (10 minutes by default, 2 to 60): the hook's `timeout` becomes that many seconds and the command ends in `--timeout <seconds>` (for example `wisp-agent --source codex --timeout 600`). The helper exits on its own 5 s after its timeout (120 s without the flag), and Wisp hands an unanswered request back to the terminal 10 s before the timeout the hook was installed with. Hooks whose wait differs from the current setting read as outdated, so Settings offers "Update hooks"; Codex then asks you to trust them again in `/hooks`.

The statusLine command keeps any bar you had before inside it (`--saved '<command>'` or `--chain '<command>'`), so Wisp can put it back exactly.

## Claude Code, Codex and Gemini CLI compared

Checked on 2026-11-07 against Codex's hooks documentation (developers.openai.com/codex/hooks) and the structure of local Codex rollout files written by Codex 0.45 to 0.77 (keys and event types only). Codex itself wasn't installed, so nothing below was run against a live Codex. The Gemini CLI column was checked on 2026-11-07 against its hooks reference (geminicli.com/docs/hooks, github.com/google-gemini/gemini-cli `docs/hooks/`, latest release v0.67.0), its configuration reference and its source (`hooks/types.ts`, `hooks/hookPlanner.ts`, `hooks/hookRunner.ts`, `scheduler/scheduler.ts`). Gemini CLI wasn't installed either, so the fixtures in `GeminiAdapterTests` are built from the documented field names, not a live run.

| | Claude Code | Codex | Gemini CLI |
|---|---|---|---|
| Hook file | `~/.claude/settings.json` (`hooks` next to other settings) | `~/.codex/hooks.json` (also read from `config.toml` and project `.codex/`; Wisp writes only the user hooks.json) | `~/.gemini/settings.json` (`hooks` next to other settings; also project `.gemini/settings.json` and `/etc/gemini-cli/settings.json`; Wisp writes only the user file). Timeouts in milliseconds, 60 s by default |
| Hook input fields | `session_id`, `cwd`, `hook_event_name`, `transcript_path`, `tool_name`, `tool_input`, `tool_use_id`, ... | The same names, plus `turn_id`, `model` and `permission_mode` | `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `timestamp`, `tool_name`, `tool_input`; no `tool_use_id` |
| SessionStart, UserPromptSubmit, Stop, SessionEnd | Yes | Yes (`SessionStart.source` adds `fork`) | SessionStart (`startup`, `resume`, `clear`), BeforeAgent (prompt), AfterAgent (turn done), SessionEnd (best effort) |
| Notification (idle, elicitation) | Yes | No such event | Notification `ToolPermission` only, when Gemini asks to confirm a tool call; read as Needs you |
| PermissionRequest | Allow or deny, `updatedInput` for plans and questions | Allow or deny only; `updatedInput` is reserved and fails closed | No such event. BeforeTool blocks and can deny, rewrite the input or add a confirmation (`ask`), but it runs before the policy check for every tool call, and its allow doesn't skip Gemini's own confirmation (`ask` can only add one), so Wisp doesn't answer: monitor only |
| Plan approval (ExitPlanMode) | From the notch | No equivalent tool | No |
| Questions (AskUserQuestion) | Answered from the notch | No equivalent tool | No |
| PreCompact, PostCompact | Yes, `async` | Yes, synchronous (matcher `manual` or `auto`) | PreCompress only (`trigger` `auto` or `manual`); no event after |
| PreToolUse, PostToolUse, SubagentStop | Yes, `async` | Yes, `async`. File edits arrive as `apply_patch` with the whole patch in `tool_input.command`; Wisp shows the first file it touches | BeforeTool (with tool activity) and AfterTool (always), synchronous, so each costs every tool call a helper launch. Tools are `run_shell_command`, `replace`, `write_file`, `read_file`, `grep_search`, `glob`, `web_fetch`, `google_web_search`, ...; MCP tools are `mcp_<server>_<tool>` |
| `async` handlers | Yes | Yes | No |
| Status line (live cost, context, model) | `statusLine` command | None | None |
| Context % | Status line `context_window.used_percentage` | Rollout `token_count`: `info.last_token_usage.total_tokens` over `info.model_context_window`, read when a turn stops | Not read |
| Model | Status line, or the transcript's messages | Rollout `turn_context.payload.model` | Not read |
| Cost | Status line `cost.total_cost_usd` (real); transcript estimate otherwise | Estimate from rollout `info.total_token_usage` (cached input split out) at OpenAI list prices | Not read |
| Plan limits | Status line `rate_limits.five_hour` / `seven_day` | Rollout `token_count.rate_limits.primary` / `secondary` with `used_percent`, `window_minutes` (300 and 10080 are shown) and `resets_at` (epoch seconds), or `resets_in_seconds` in older rollouts | Not read (quotas aren't in the hook payloads or a documented file) |
| Always-allow rules | `permissions.allow` (roadmap phase 2) | Not yet | No |
| Not used by Wisp | | `Interrupt`, `SubagentStart`, `PreModelRequest`, `PostModelRequest` | `BeforeModel`, `AfterModel`, `BeforeToolSelection` |

## Cursor

Checked on 2026-11-07 against Cursor's hooks reference (cursor.com/docs/agent/hooks) and Cursor staff replies on the Cursor forum (March 2026) about which hook verdicts are enforced. The CLI changelog lists sessionStart, sessionEnd, prompt, stop, preToolUse and postToolUse hooks in `cursor-agent` (now `agent`). The cursor-agent installed here (2025.09.12) predates hooks, so the fixtures in `CursorAdapterTests` follow the documented payloads, not a live run.

- **Hook file:** `~/.cursor/hooks.json` (also project `.cursor/hooks.json`, team and MDM files; Wisp writes only the user file). User hooks run from `~/.cursor/`.
- **Input fields:** every hook gets `conversation_id`, `generation_id`, `model`, `hook_event_name`, `cursor_version`, `workspace_roots`, `user_email` and `transcript_path`. sessionStart and sessionEnd add `session_id` (the same as `conversation_id`); tool hooks add `tool_name`, `tool_input`, `tool_use_id` and `cwd`.
- **Tool names:** `Shell` (`tool_input.command`), `Read`, `Write`, `Grep`, `Delete`, `Task` and `MCP:<tool>`. The other tools' `tool_input` fields aren't documented, so their labels may show only the verb.
- **Approvals:** beforeShellExecution and beforeMCPExecution document `allow`, `deny` and `ask`, but Cursor staff say only `deny` is enforced there: `allow` doesn't skip Cursor's own approval and `ask` is ignored (forum, March 2026). preToolUse enforces `allow` and `deny` but not `ask`, so it can't give a call back to Cursor's prompt; it also fires for every tool and blocks on output it can't read. Monitor only until that changes.
- **Transcripts:** `transcript_path` (null unless Cursor's transcripts are on) is kept, so Reveal transcript works. The token reader looks for Claude Code and Codex lines and isn't expected to find any in Cursor's transcript, so no cost is shown.
- **Exit codes:** 0 uses the JSON output, 2 denies, anything else fails open unless the hook has `failClosed`. For permission hooks, invalid JSON blocks the action.
- **Not read:** context, model, cost and usage limits (none in a documented file; preCompact's `context_usage_percent` is only sent at compaction). Not used: afterShellExecution, afterMCPExecution, afterFileEdit, afterAgentResponse, afterAgentThought, postToolUseFailure, subagentStart, subagentStop, workspaceOpen and the Tab hooks.
