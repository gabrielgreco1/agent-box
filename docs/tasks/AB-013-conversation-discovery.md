# AB-013: CLI conversation discovery and resume foundation

The Core catalog exposes conversation identity, provider, project path, activity, and source without reading transcript content. `claude agents --json` is the only implemented discovery adapter: it returns active external Claude sessions, with `sessionId` and `cwd` copied into bounded metadata models. The command runs without a shell, has a five-second default deadline and a one-megabyte output limit, and uses an owner-private temporary file. Invalid rows are skipped. A returned active session remains blocked from a second writer.

For an explicitly supplied native session ID, the resume descriptor uses the selected project's current working directory and exact provider arguments:

| Provider | Resume arguments | Discovery |
| --- | --- | --- |
| Claude Code | `--resume <UUID>` | `agents --json` active sessions |
| Codex CLI | `resume <UUID>` | Explicit ID only |
| OpenCode | `--session <ses_id>` | Explicit ID only |

These forms were checked against locally installed Claude Code 2.1.301 and Codex CLI 0.162.1 help, and the [OpenCode CLI documentation](https://opencode.ai/docs/cli/). OpenCode was not installed locally, so its session-list JSON schema was not assumed. IDs and paths are validated before producing a command descriptor; the descriptor does not launch a process.

`CLIConversationWriteCoordinator` is an app-wide, thread-safe in-memory reservation. The host must refresh Claude's active listing immediately before admission, obtain a ticket before PTY start, retain that ticket for the actual process lifetime, and release only that ticket when the process exits. Active external conversations cannot be reserved. Unknown or explicit external conversations require the user's confirmation that the other writer has closed. The coordinator prevents duplicate Agent Box writers inside one app process; it cannot lock a separate CLI process or guarantee that an external writer will not start between the check and PTY launch.

## Interface and terminal integration

The workspace menu now opens **Retomar conversa…** for its selected session. The sheet accepts a provider, native ID and project folder, detects the installed CLI, and optionally lists active Claude conversations. It asks the user to close other terminals using that conversation before starting a new writer. OpenCode and Codex accept explicit IDs; neither advertises a verified conversation catalog.

The runtime refreshes Claude's active listing immediately before admission, checks the command against the chosen terminal's provider/ID/folder/argv, reserves a writer, then starts the actual provider executable in a retained PTY. The reservation survives view changes and is released by that process's exit callback. A generation check cancels a pending discovery if the app quits. A persisted terminal's optional `nativeConversation` field retains its identity separately from its editable title; old records decode without this field. Restored conversations require a fresh review instead of automatically starting on launch.

Workspace metadata is saved and published before the asynchronous discovery step. A failure leaves a stopped terminal for retry without rolling back unrelated workspace changes. Repeating the same resume in the same session reuses that terminal. Existing saved-agent snapshots are not silently attached to an external conversation.

Core tests cover metadata filtering, unsupported discovery, exact argv, malformed IDs, duplicate writers and stale reservation release. A runtime test uses a real PTY and local CLI fixture to verify argv delivery, duplicate rejection, release after exit, persistence and quit during discovery. These are not proof of resuming real histories across all three harnesses. Historical discovery, external cross-process locking, context binding on resumed conversations and visual acceptance remain open under AC15, AC18 and AC23.
