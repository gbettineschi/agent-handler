# Claude native audit observation

The user asked to continue the backend before UI, then suggested ignoring ordinary ChatGPT Chat after asking how competitors integrate. Defer ordinary ChatGPT Chat; keep Claude surfaces explicitly separate. Existing authorization permits building without further design/plan approval pauses.

## Evidence and scope

CodeIsland observes Claude's local agent-session audit files, including explicit result and permission events. OpenIsland's documented Desktop coverage is Claude Code runtime coverage, not every consumer Chat. Consumer plugin hooks do not run in ordinary Claude Chat. This Mac has nine local session logs, most recently modified in June; the installed Claude UI is signed into Free, and the installed Claude Code CLI reports signed out.

Build a read-only ClaudeDesktopAdapter for local audit files. It covers local Cowork/Code-backed sessions that actually append this format. Cloud-only Chat/Cowork sessions without a local audit are not covered. Logs do not establish a live response channel: this adapter must not create answerable AttentionRequests, send answers, grant permissions or settle delivery-ledger entries. Native Claude responses need a separately verified callback transport.

Fresh activity has an explicit `system/init` anchor UUID in an ordered audit stream. A same-session `result` is terminal only with recognized subtype, boolean error flag and terminal reason. A terminal result without an observed init cannot establish completion. Main-agent records only; subagent events cannot end or clear the main turn. Parallel permissions remain distinct by UUID; a response clears only an exact ID. Assistant output and unrelated tool results do not clear them. Malformed lines, duplicate identities with changed content, unknown state-changing schemas and read gaps invalidate the observation until a new init.

## Reading and freshness

- Discover only `<root>/<account>/<org>/local_<id>/audit.jsonl`, with matching sibling session metadata. Exclude plugin directories, archives and hidden agent/dispatch/radar sessions. Bound discovery to 512 candidates and follow at most 16 changed sessions.
- Open regular same-user files read-only with `O_NOFOLLOW`; validate canonical parents stay below the configured root. Do not parse unrelated logs, credentials, prompts or response text for meaning.
- On start/resume, baseline existing files at EOF. No historical completion replay. A file created after observation began may be read from byte zero, provided its creation time is known and current. Metadata timestamps only select candidates, never establish completion.
- Poll filesystem metadata once per second; read only appended bytes, at most 256 KiB per file per tick and 512 KiB per line. Retain partial UTF-8/JSON lines until newline. Oversize or malformed records make state unknown; discard safely through the next newline. Inode changes, truncation and changed checkpoint bytes invalidate and rebaseline at EOF.
- Loss of the Claude process, sleep, stop or a source read failure invalidates activity. Resumption establishes a new observation generation and baseline. A new init is required before a result can be current again. Stop clears tailer buffers; at most 16 presentation records survive, all unavailable.

ActivityStore remains the common presentation model. Its turn ID is the audit init UUID, not a claim of a native SDK turn ID. Scope includes the root and account/org/session path. SDK `session_id` binds subsequent events. File order is the observation contract; no atomic response or whole-agent-tree completion is claimed. This increment adds no notification delivery or UI layout.

## Verification

Use minimal fabricated records shaped from the installed host's real records; never commit personal transcripts. Tests must exercise partial writes, malformed/oversize lines, non-boolean error flags, root versus child results, mismatched sessions, duplicate events, multiple permissions, fresh init recovery, EOF baseline, append/rotation/truncation/rewrites, symlink refusal, process absence and independent sessions. Run the entire suite, release build/signature, read-only native probe and macOS CI. Live Claude observation requires a fresh supported runtime; old files are not a live pass.
